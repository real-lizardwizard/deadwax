import re
import asyncio
from pathlib import Path
from urllib.parse import urlsplit
from fastapi import Depends, FastAPI
from fastapi.exception_handlers import request_validation_exception_handler
from fastapi.exceptions import RequestValidationError
from contextlib import asynccontextmanager
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse, RedirectResponse, Response
from starlette.middleware.gzip import GZipMiddleware

from src.routes import search_musicbrainz, interface_logs, monitor_slskd, download, library, settings, navidrome, me, pins, store_album
from src.routes import auth as auth_routes, held, my_library, people
from src import auth, permissions, player_cache, stars
from src.api import navidrome_admin
from src.musicbrainz_cache import saved_answers
from src.users import current_user, require
from src.logger import logger, cleanup_logging
from src.poller import run_download_poller
from src.store import JobStore
from src.store_index import seed_from_saved_scan

from src.api.musicbrainz_endpoint import MusicBrainzClient
from src.api.slskd_endpoint import SlskdClient
from src.api.lrclib_endpoint import lrclib
from src.api.same_origin import SameOriginWrites
from src.api.navidrome_endpoint import SignedOut, navidrome as navidrome_client
from src.config import Config
from src import __version__

#? The routes that answer with a picture or with audio - bytes deadwax didn't make. The library's
#? are matched EXACTLY, since each takes its album as a query parameter: as a prefix,
#? "/deadwax/library/art" also caught every /deadwax/library/artist route, all of them JSON.
MEDIA_PATHS = frozenset({
    "/deadwax/library/art", "/deadwax/library/artist/art", "/deadwax/library/disc_art",
    "/deadwax/library/tracks/picture",
    #? the player's turntable face (2.0.0-player.11): CD art found by a Navidrome album id
    "/deadwax/library/disc_art/navidrome",
})
#? The player's, whose ids are in the path - the turntable's windows of a song (2.0.0-player.14)
#? among them: FLAC, which gzip would only waste time on and take the length off
MEDIA_PREFIXES = ("/deadwax/navidrome/stream/", "/deadwax/navidrome/cover/", "/deadwax/navidrome/scrub/")


def serves_media(path: str) -> bool:
    return path in MEDIA_PATHS or path.startswith(MEDIA_PREFIXES)


def relative_location(location: str, host: str) -> str:
    """
    (2.0.0-player.65, the 2.0.0 release review) A redirect deadwax made to itself, as a relative reference - its path,
    query and fragment, with no scheme or host. Starlette writes the Location of its slash redirects (`/player` ->
    `/player/`, by the static mount and the router alike) from the request as deadwax received it - plain http behind
    a proxy that ends TLS - so the browser was sent to http:// and, with no http listener, nowhere. Relative, it stays
    on whatever scheme and host the browser is on. A Location naming another host (none is made today) is left as
    it is.

    The path never starts with two slashes (or a slash and a backslash): a browser reads `//host/...` as
    protocol-relative, ANOTHER host. Starlette's static mount writes its slash redirect from the decoded path, so
    `/%2Fevil.example%2F..%2Fplayer` came back as `http://host//evil.example/../player/` - on deadwax's host while
    absolute, but `//evil.example/../player/` once made relative, an open redirect (the .65 review). Every leading
    slash collapses to one, which the browser resolves on deadwax's own host.
    """
    parts = urlsplit(location)
    if parts.scheme not in ("http", "https") or not host or parts.netloc.lower() != host.lower():
        return location
    relative = "/" + parts.path.lstrip("/\\")
    if parts.query:
        relative += f"?{parts.query}"
    if parts.fragment:
        relative += f"#{parts.fragment}"
    return relative


#? (2.0.0-player.61) What a People request deadwax couldn't read is answered - in place of FastAPI's 422, which
#? would echo what was sent
PEOPLE_FORM = people.PEOPLE_FORM

#? What a page's head carries when logins are on (2.0.0-player.48): ui/src/api/auth.ts reads it.
LOGINS_MARK = '<meta name="deadwax-auth" content="on">'
#? ...and the app's page, the sign-in screen's own stylesheet beside it - linked only then, so with logins
#? off the page is exactly what it was
SIGNIN_SHEET = '<link rel="stylesheet" href="/player/signin.css">'


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.musicbrainz_client = MusicBrainzClient()
    app.state.slskd_client = SlskdClient()
    logger.info("slskd client initialized")

    app.state.store = JobStore()
    app.state.store.init()

    #? Overrides from the settings tab, laid over the environment BEFORE anything serves a
    #? request or the poller starts. Order matters: the store has to be open to read them,
    #? and Config has to be reconciled before the first read of any setting - otherwise the
    #? first request in gets the environment's value and the one after it gets the override.
    Config.apply_overrides(app.state.store.stored_settings())

    #? Here rather than in Config.check(), which runs before the overrides exist - an email set
    #? in the settings tab would otherwise be reported missing on every single restart.
    Config.report_musicbrainz()
    Config.report_navidrome()
    #? after the overrides too: whether a sign-in can reach Navidrome depends on NAVIDROME_URL, which can be one
    Config.report_logins()

    #? (2.0.0-player.54) MusicBrainz's answers kept on disk, under the hour in memory - after the
    #? overrides, since MUSICBRAINZ_CACHE_PATH and MUSICBRAINZ_CACHE_MB can be ones. Nothing is made
    #? until the first answer is saved. Only here, so nothing outside a running app touches the file.
    MusicBrainzClient.cache.disk = saved_answers
    if saved_answers.enabled():
        logger.info(f"MusicBrainz's answers are kept on disk in {saved_answers.path()}, at most "
                    f"{saved_answers.max_bytes() >> 20} MB")
        #? (2.0.0-player.56) opened now, on its own thread, if it is there: answers saved before there was a
        #? saved-search index are read into one in the background, from the first start of this version
        saved_answers.warm()
    else:
        logger.info("MUSICBRAINZ_CACHE_MB is 0, so MusicBrainz's answers are kept in memory only, for an hour")

    #? An empty store index - the first start of a version with one - is filled from the saved
    #? scan, so Find knows what the library holds before anyone opens its tab (step 2). After the
    #? overrides, since LIBRARY_PATH can be one; from the database alone, never the disk.
    await seed_from_saved_scan(app.state.store, Config.LIBRARY_PATH or "")
    #? (2.0.0-player.65) ...and when even that left it never filled from a scan of LIBRARY_PATH (an upgrade whose
    #? saved scan is of an older format), the library is walked once, in the background, so album pages can offer
    #? Add without anyone opening the library first
    library_scan = asyncio.create_task(library.scan_at_start(app.state.store))
    #? (2.0.0-player.65) the Library's Shuffle forgets what has aged out on a timer, not only when asked again
    shuffle_sweeps = asyncio.create_task(navidrome.run_shuffle_sweeps())

    #? (2.0.0-player.62) what the player's Normalization measures is kept in the database, so a restart
    #? measures nothing again (src/levels.py)
    player_cache.cache.levels.store = app.state.store

    poller_task = asyncio.create_task(
        run_download_poller(app.state.slskd_client, app.state.store)
    )
    #? kept where /health can see it - see there
    app.state.poller_task = poller_task

    #? logins (2.0.0-player.48): each session's login put to Navidrome again every few minutes - only
    #? with them on, and a database to keep sessions in (without one, every protected route is a 503)
    session_checks = None
    #? (2.0.0-player.51) each user's library starred as them in Navidrome, and their stars read back - the
    #? same terms: logins on, and a database to keep the ledger in
    library_worker = None
    if Config.logins_on() and app.state.store.available:
        #? (2.0.0-player.61) what admins gave people, held in memory from the start (a failure is logged, and
        #? read again by the first request a minute on - nobody but an admin can do anything meanwhile)
        await asyncio.to_thread(permissions.load, app.state.store)
        session_checks = asyncio.create_task(auth.run_session_checks(app.state.store))
        library_worker = asyncio.create_task(stars.run_library_worker(app.state.store))

    yield
    logger.info("Shutting down API server...")

    for task in (poller_task, session_checks, library_worker, library_scan, shuffle_sweeps):
        if task is None:
            continue
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass

    await app.state.musicbrainz_client.stop_refreshing()
    await app.state.musicbrainz_client.close_client()
    #? what is queued for the file is written first; then it is closed
    await saved_answers.close()
    MusicBrainzClient.cache.disk = None
    await app.state.slskd_client.close_client()
    await library.coverart_client.close_client()
    await library.artist_images_client.close_client()
    await lrclib.close_client()
    await navidrome_client.close_client()
    await auth.login_client.close_client()
    await navidrome_admin.close_client()
    await stars.star_client.close_client()

    cleanup_logging()


def start() -> FastAPI:
    logger.info("Starting API server")
    #? (2.0.0-player.48) With logins on, the API's own pages go: /docs, /redoc and /openapi.json would
    #? describe every route to anybody who can reach the port. AUTH_MODE is the environment's alone, so
    #? it is read once, here.
    logins = Config.logins_on()
    app = FastAPI(
        title="deadwax",
        summary="Search MusicBrainz, download through slskd",
        lifespan=lifespan,
        **({"docs_url": None, "redoc_url": None, "openapi_url": None} if logins else {}),
    )

    #? Vite writes these with a content hash in the filename, so a given URL's contents can
    #? never change. Revalidating them would be pure waste, and caching them hard is what
    #? makes the hashing worth doing at all.
    #? ...and the bundled font files: a font that changed would be a new file under a new name
    IMMUTABLE_PREFIXES = ("/dist/assets/", "/styles/font/")
    #? the app's icons: small, asked for on every launch, and changed about never - a day
    DAY_PREFIXES = ("/player/icon",)

    #? Everything whose URL stays the same while its contents change: the hand-written
    #? interface files, and the Vite entry bundle - deliberately unhashed so the app's page
    #? can name it (see ui/vite.config.ts), which is exactly what makes it mutable.
    #? The player's page and manifest belong here for the same reason: an installed web app
    #? revalidates on launch like any page, and a cached page is an old app.
    #? what the app's page names with a stamp (see stamped_page): its own stylesheets and its bundle
    STAMPED_PREFIXES = ("/player/", "/dist/", "/styles/")
    #? (2.0.0-player.66) /scripts/ and /assets/ went with the main page
    REVALIDATE_PREFIXES = ("/styles/", "/dist/", "/player/")
    #? `/` and `/index.html`: the main page's addresses, a redirect to the app since 2.0.0-player.66 - asked about
    #? every time, so a browser that cached the old page meets the redirect
    REVALIDATE_PATHS = ("/", "/index.html")

    class RevalidateInterfaceAssets:
        """
        Make the browser revalidate the interface files instead of trusting its cache.

        Without this, updating the container leaves people staring at the old CSS and JS
        until they think to hard-refresh - the failure mode being "I upgraded and nothing
        changed", which is miserable to diagnose. `no-cache` still allows a conditional
        request, so with StaticFiles' ETags the normal case is a cheap 304 rather than a
        re-download. It cost real time during development before being noticed here.

        The hashed-asset carve-out matters as the Preact migration lands: matching only
        /scripts/ and /styles/ would have left the new bundle uncovered and reintroduced that
        exact bug for the half of the interface that had been ported.

        PLAIN ASGI, not @app.middleware("http") (v0.9.8). That decorator is Starlette's
        BaseHTTPMiddleware, whose wrapped `receive` cannot be checked without blocking - so
        `request.is_disconnected()` answered False for every request in the app, for ever, and
        a Soulseek search the page had abandoned ran on to its timeout with nobody to tell it.
        This only touches the response's headers and passes `receive` through untouched.
        """

        def __init__(self, inner):
            self.inner = inner

        async def __call__(self, scope, receive, send):
            if scope["type"] != "http":
                return await self.inner(scope, receive, send)

            path = scope.get("path", "")
            #? checked first - /dist/assets/x-HASH.js matches both tuples
            if path.startswith(IMMUTABLE_PREFIXES):
                policy = b"public, max-age=31536000, immutable"
            elif path.startswith(STAMPED_PREFIXES) and b"v=" in scope.get("query_string", b""):
                #? named with its own stamp by the app's page (stamped_page below): another file
                #? would be another address, so this one never needs asking about again
                policy = b"public, max-age=31536000, immutable"
            elif path.startswith(DAY_PREFIXES):
                policy = b"public, max-age=86400"
            elif path in REVALIDATE_PATHS or path.startswith(REVALIDATE_PREFIXES):
                policy = b"no-cache"
            else:
                return await self.inner(scope, receive, send)

            async def send_with_policy(message):
                if message["type"] == "http.response.start":
                    headers = [(k, v) for k, v in message.get("headers", []) if k.lower() != b"cache-control"]
                    headers.append((b"cache-control", policy))
                    message = {**message, "headers": headers}
                await send(message)

            await self.inner(scope, receive, send_with_policy)

    app.add_middleware(RevalidateInterfaceAssets)

    class CompressText:
        """
        Gzip what compresses - JSON, the interface's scripts and CSS - and nothing that doesn't
        (v0.9.20). Nothing was compressed before, and the library's album list is the largest
        thing the page fetches; JSON like it shrinks to about a tenth.

        Starlette's GZipMiddleware is plain ASGI (it wraps `send` and leaves `receive` alone, so
        the disconnect detection below still works) and already leaves the log's event stream
        uncompressed. Pictures, fonts and the player's icons are passed straight through, since
        they are compressed already and gzipping them is CPU for nothing.

        The player's audio and covers are passed through for CORRECTNESS, not just to save CPU.
        GZipMiddleware compresses any body that is streamed, whatever its size or type, and drops
        its Content-Length to do it - so Safari's two-byte probe came back as a gzipped 206 with
        no length, and a seek as a gzipped body under a Content-Range counting uncompressed bytes.
        Byte ranges have to reach Safari exactly as Navidrome sent them, or it won't play.
        """

        #? skipped as well as everything serves_media() names - `icon-` so that it catches the PNG
        #? icons and not icon.svg, which is text and still worth gzipping
        BINARY = ("/styles/font/", "/player/icon-")

        def __init__(self, inner):
            self.inner = inner
            self.gzip = GZipMiddleware(inner, minimum_size=1024, compresslevel=6)

        async def __call__(self, scope, receive, send):
            if scope["type"] == "http":
                path = scope.get("path", "")
                if not serves_media(path) and not path.startswith(self.BINARY):
                    return await self.gzip(scope, receive, send)
            return await self.inner(scope, receive, send)

    app.add_middleware(CompressText)

    class GuardMedia:
        """
        Pictures and audio are only ever shown to deadwax's own pages, and never as pages.

        Their bytes come from strangers - an embedded picture in a file a Soulseek peer shared,
        passed on by the library routes or by Navidrome - and each route decides which types it
        will serve them as. This is the rest of that: `nosniff` stops a browser guessing a type
        from the bytes, a sandbox with nothing allowed means a response opened as a page can run
        nothing even if a type slips through, and `same-origin` stops any other website
        embedding the covers and audio. The player and the library tab are same-origin, so their
        <img> and <audio> - and the lock screen's artwork - are unaffected.

        Plain ASGI, touching only the response's headers, like the layers around it.
        """

        HEADERS = [
            (b"x-content-type-options", b"nosniff"),
            (b"content-security-policy", b"default-src 'none'; sandbox"),
            (b"cross-origin-resource-policy", b"same-origin"),
        ]
        NAMES = {name for name, _ in HEADERS}

        def __init__(self, inner):
            self.inner = inner

        async def __call__(self, scope, receive, send):
            if scope["type"] != "http" or not serves_media(scope.get("path", "")):
                return await self.inner(scope, receive, send)

            async def send_guarded(message):
                if message["type"] == "http.response.start":
                    headers = [(k, v) for k, v in message.get("headers", []) if k.lower() not in self.NAMES]
                    message = {**message, "headers": headers + self.HEADERS}
                await send(message)

            await self.inner(scope, receive, send_guarded)

    app.add_middleware(GuardMedia)

    class RefuseFrames:
        """
        (2.0.0-player.61) Every page refuses to be framed by another website: `X-Frame-Options: DENY` and
        `Content-Security-Policy: frame-ancestors 'none'` on every text/html response - so People's buttons
        (and the sign-in, and everything else) can't be laid under a page elsewhere that tricks a click
        through to them. Plain ASGI, touching only the response's headers, like the layers around it.

        ADDED BESIDE any policy already there, never in its place (review): a browser enforces every
        Content-Security-Policy a response carries, so GuardMedia's `default-src 'none'; sandbox` on a media
        route that ever answered as HTML still holds - this layer is outside it, and replacing it would have
        let a stranger's bytes run as a page of deadwax's.
        """

        HEADERS = [(b"x-frame-options", b"DENY"), (b"content-security-policy", b"frame-ancestors 'none'")]

        def __init__(self, inner):
            self.inner = inner

        async def __call__(self, scope, receive, send):
            if scope["type"] != "http":
                return await self.inner(scope, receive, send)

            async def send_unframed(message):
                if message["type"] == "http.response.start":
                    headers = list(message.get("headers", []))
                    kind = next((v for k, v in headers if k.lower() == b"content-type"), b"")
                    if kind.lower().startswith(b"text/html"):
                        #? only an earlier copy of exactly these goes; every other policy stays and is enforced too
                        ours = set(self.HEADERS)
                        kept = [(k, v) for k, v in headers
                                if k.lower() != b"x-frame-options" and (k.lower(), v) not in ours]
                        message = {**message, "headers": kept + self.HEADERS}
                await send(message)

            await self.inner(scope, receive, send_unframed)

    app.add_middleware(RefuseFrames)

    class RelativeRedirects:
        """
        (2.0.0-player.65) Every redirect deadwax makes to itself goes out with a relative Location
        (relative_location), so behind a proxy that ends TLS `/player` lands on https://.../player/ rather than
        on an http:// address nothing answers. Plain ASGI, touching only the response's headers, like the layers
        around it - and not FORWARDED_ALLOW_IPS=*, which would have uvicorn trust anyone's X-Forwarded-For.
        """

        def __init__(self, inner):
            self.inner = inner

        async def __call__(self, scope, receive, send):
            if scope["type"] != "http":
                return await self.inner(scope, receive, send)
            host = next((value for name, value in scope.get("headers", []) if name == b"host"), b"").decode("latin-1")

            async def send_relative(message):
                if message["type"] == "http.response.start" and 300 <= message.get("status", 200) < 400:
                    headers = [(name, relative_location(value.decode("latin-1"), host).encode("latin-1"))
                               if name.lower() == b"location" else (name, value)
                               for name, value in message.get("headers", [])]
                    message = {**message, "headers": headers}
                await send(message)

            await self.inner(scope, receive, send_relative)

    app.add_middleware(RelativeRedirects)

    #? Added last, so it is the OUTERMOST layer: a write another website asked for is refused
    #? before anything else runs. See src/api/same_origin.py.
    app.add_middleware(SameOriginWrites)

    logger.info("adding routers")
    #? (2.0.0-player.48) EVERY router is checked by a dependency: current_user - with logins off the
    #? implicit admin, reading nothing; on, a session or 401 - and (2.0.0-player.61, in place of require_admin)
    #? require(permission), 403 in words for someone without it: the log and the server settings whole are
    #? `server`'s, Held by nobody `library`'s, People `people`'s (and per route the library's writers, in
    #? routes/library.py, and the downloads routes that start one, in routes/download.py). A dependency, never
    #? @app.middleware("http"), which hides disconnects. A router added here without one is caught by
    #? tests/test_logins.py's walk of every route.
    signed_in = [Depends(current_user)]
    server = [Depends(require("server"))]
    app.include_router(interface_logs.router, prefix="/deadwax/interface_logs", tags=["interface_logs"], dependencies=server)
    app.include_router(search_musicbrainz.router, prefix="/deadwax/search_musicbrainz", tags=["search_musicbrainz"], dependencies=signed_in)
    app.include_router(monitor_slskd.router, prefix="/deadwax/monitor_slskd", tags=["monitor_slskd"], dependencies=signed_in)
    app.include_router(download.router, prefix="/deadwax/download", tags=["download"], dependencies=signed_in)
    app.include_router(library.router, prefix="/deadwax/library", tags=["library"], dependencies=signed_in)
    app.include_router(settings.router, prefix="/deadwax/settings", tags=["settings"], dependencies=server)
    app.include_router(navidrome.router, prefix="/deadwax/navidrome", tags=["navidrome"], dependencies=signed_in)
    #? who the page is talking to - the implicit admin while logins are off, the signed-in user with them on
    app.include_router(me.router, prefix="/deadwax/me", tags=["me"], dependencies=signed_in)
    #? what each user pinned to the app's Home (2.0.0-player.18) - deadwax's own, never Navidrome's stars
    app.include_router(pins.router, prefix="/deadwax/me/pins", tags=["me"], dependencies=signed_in)
    #? (2.0.0-player.51) each user's own library - their starred albums - and the admin's "held by nobody"
    app.include_router(my_library.router, prefix="/deadwax/me/library", tags=["me"], dependencies=signed_in)
    app.include_router(held.router, prefix="/deadwax/library/held", tags=["library"], dependencies=[Depends(require("library"))])
    #? (2.0.0-player.61) People: Navidrome's accounts, managed as the signed-in Navidrome admin - see routes/people.py
    app.include_router(people.router, prefix="/deadwax/people", tags=["people"], dependencies=[Depends(require("people"))])
    #? the id bridge (2.0.0-player.17): one album across the store index, MusicBrainz and Navidrome
    app.include_router(store_album.router, prefix="/deadwax/store", tags=["store"], dependencies=signed_in)
    #? signing in and out (2.0.0-player.48) - with no session, of course: see routes/auth.py
    app.include_router(auth_routes.router, prefix="/deadwax/auth", tags=["auth"])

    #? (2.0.0-player.52) a player call Navidrome refused the asker's login for - the session ended
    #? (navidrome_endpoint.UserClient) - is a 401 in words wherever it surfaces, as current_user's own are:
    #? the app's sign-in screen comes up saying why
    @app.exception_handler(SignedOut)
    async def signed_out(request, error: SignedOut):
        return JSONResponse(status_code=401, content={"detail": str(error)})

    #? (2.0.0-player.58, review) a playlist route's body refused by its own validators: the refusal in deadwax's words
    #? as a plain `detail` (routes/navidrome.py validation_words) - FastAPI's list of errors reached the page as
    #? "POST ... failed". Every other route's 422 is FastAPI's own, as it always was.
    #? (2.0.0-player.61) a People route's refusal: its words, and what kind it is - `locked` brings the unlock back
    @app.exception_handler(people.Refused)
    async def people_refused(request, error: people.Refused):
        return JSONResponse(status_code=error.status, content=people.answer(error),
                            headers={"Retry-After": str(error.retry_after)} if error.retry_after else None)

    @app.exception_handler(RequestValidationError)
    async def refused_body(request, error: RequestValidationError):
        #? (2.0.0-player.61) a People form deadwax can't read: never FastAPI's list, which echoes the `input` - a
        #? password among it
        if request.url.path.startswith("/deadwax/people"):
            return JSONResponse(status_code=422, content={"detail": PEOPLE_FORM})
        #? (2.0.0-player.65, the 2.0.0 release review) nor a sign-in's: an over-long one echoed the password
        if request.url.path.startswith("/deadwax/auth"):
            return JSONResponse(status_code=422, content={"detail": auth_routes.SIGN_IN_FORM})
        words = navidrome.validation_words(request.url.path, error.errors())
        if words is not None:
            return JSONResponse(status_code=422, content={"detail": words})
        return await request_validation_exception_handler(request, error)

    @app.get("/deadwax/health")
    async def health():
        """
        Whether this container is doing its job, for the image's HEALTHCHECK - so Komodo can tell
        "running" from "working".

        Deliberately about deadwax ALONE. slskd being logged out, or MusicBrainz being down (which
        it often is), is a fact about another service: marking deadwax unhealthy for it would
        have an orchestrator restart a container that restarting cannot fix. The connection
        pills are where those are reported.

        What does make it unhealthy is the download poller having stopped: it catches every
        error per pass, so it only ends if something has gone badly wrong, and without it no
        download is ever tracked or filed while the page goes on looking fine.
        """
        poller = getattr(app.state, "poller_task", None)
        running = poller is not None and not poller.done()
        body = {"status": "ok" if running else "unhealthy", "version": __version__,
                "poller": "running" if running else "stopped"}
        return JSONResponse(body, status_code=200 if running else 503)

    logger.info("mounting static interface files")
    interface_path = Path(__file__).parent.parent.parent / "interface"

    def with_logins_mark(html: str, sign_in: bool = False) -> str:
        """
        A page with LOGINS_MARK in its head when logins are on (2.0.0-player.48), so its script knows to
        ask who is signed in before drawing anything - and the app's page (`sign_in`) the sign-in screen's
        stylesheet, SIGNIN_SHEET, too. Off, the page exactly as it is: the app then draws at once, as it
        always has, with no extra round trip. The pages stay public; the mark says only that logins are on.
        """
        if not logins:
            return html
        return html.replace("</head>", f"{LOGINS_MARK}\n{SIGNIN_SHEET if sign_in else ''}\n</head>", 1)
    #? The app's page, with each stylesheet and script it names stamped with that file's own size and
    #? time of writing (`?v=`). The page itself is still asked for on every launch (no-cache, above);
    #? what it names is then kept for good, because a file that changed has another stamp and so
    #? another address. Until this an installed app re-asked about every one of them on every launch -
    #? a round trip each, over the phone's connection - to be told nothing had changed. A stamp is
    #? read from the disk per request (a stat a file), so a new build is seen without a restart.
    STAMPED = re.compile(r'''(?P<attr>href|src)="(?P<path>/(?:player|dist|styles)/[^"?#]+\.(?:css|js))"''')

    def stamped_page(page: str = "player/index.html") -> Response:
        html = with_logins_mark((interface_path / page).read_text(encoding="utf-8"), page == "player/index.html")

        def stamp(match: re.Match) -> str:
            try:
                found = (interface_path / match["path"].lstrip("/")).stat()
            except OSError:
                return match[0]
            return f'{match["attr"]}="{match["path"]}?v={found.st_mtime_ns:x}-{found.st_size:x}"'

        return Response(STAMPED.sub(stamp, html), media_type="text/html")

    @app.get("/player/")
    async def serve_app():
        return stamped_page()

    @app.get("/player/index.html")
    async def serve_app_by_name():
        return stamped_page()

    #? the turntable's test bench (2.0.0-player.36): a page of its own beside the app, stamped the same way
    @app.get("/player/lab/")
    async def serve_lab():
        return stamped_page("player/lab/index.html")

    @app.get("/player/lab/index.html")
    async def serve_lab_by_name():
        return stamped_page("player/lab/index.html")

    #? (2.0.0-player.66) The main page retired: `/` and `/index.html` send the browser to the app, from the server - a
    #? 307, which needs no script, answers HEAD, and is never kept for good (a 301 or 308 would be, and `/` could never
    #? be given back); `no-cache` above, so a browser holding the old page asks again and meets it. The query is
    #? dropped (`?return=/` was the old page's own); a `#fragment` never reaches the server - the browser carries it
    #? across a redirect itself, and the app reads it (an app route opens; anything else is Home). The Location is
    #? relative, and RelativeRedirects would make it so behind a TLS proxy anyway. Before the mount, which would
    #? otherwise answer `/` itself - public, as the page was (tests/test_logins.py's ROUTES).
    async def to_the_app():
        return RedirectResponse("/player/", status_code=307)

    for retired in ("/", "/index.html"):
        app.api_route(retired, methods=["GET", "HEAD"], include_in_schema=False)(to_the_app)

    app.mount("/", StaticFiles(directory=interface_path, html=True), name="interface")

    logger.info("API server started")
    return app
