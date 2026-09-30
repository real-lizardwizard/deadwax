import asyncio
from pathlib import Path
from fastapi import FastAPI
from contextlib import asynccontextmanager
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from starlette.middleware.gzip import GZipMiddleware

from src.routes import search_musicbrainz, interface_logs, monitor_slskd, download, library, settings, navidrome, me
from src.logger import logger, cleanup_logging
from src.poller import run_download_poller
from src.store import JobStore
from src.store_index import seed_from_saved_scan

from src.api.musicbrainz_endpoint import MusicBrainzClient
from src.api.slskd_endpoint import SlskdClient
from src.api.lrclib_endpoint import lrclib
from src.api.same_origin import SameOriginWrites
from src.api.navidrome_endpoint import navidrome as navidrome_client
from src.config import Config
from src import __version__

#? The routes that answer with a picture or with audio - bytes deadwax didn't make. The library's
#? are matched EXACTLY, since each takes its album as a query parameter: as a prefix,
#? "/deadwax/library/art" also caught every /deadwax/library/artist route, all of them JSON.
MEDIA_PATHS = frozenset({
    "/deadwax/library/art", "/deadwax/library/artist/art", "/deadwax/library/disc_art",
    "/deadwax/library/tracks/picture",
})
#? The player's, whose ids are in the path.
MEDIA_PREFIXES = ("/deadwax/navidrome/stream/", "/deadwax/navidrome/cover/")


def serves_media(path: str) -> bool:
    return path in MEDIA_PATHS or path.startswith(MEDIA_PREFIXES)


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

    #? An empty store index - the first start of a version with one - is filled from the saved
    #? scan, so Find knows what the library holds before anyone opens its tab (step 2). After the
    #? overrides, since LIBRARY_PATH can be one; from the database alone, never the disk.
    await seed_from_saved_scan(app.state.store, Config.LIBRARY_PATH or "")

    poller_task = asyncio.create_task(
        run_download_poller(app.state.slskd_client, app.state.store)
    )
    #? kept where /health can see it - see there
    app.state.poller_task = poller_task

    yield
    logger.info("Shutting down API server...")

    poller_task.cancel()
    try:
        await poller_task
    except asyncio.CancelledError:
        pass

    await app.state.musicbrainz_client.close_client()
    await app.state.slskd_client.close_client()
    await library.coverart_client.close_client()
    await library.artist_images_client.close_client()
    await lrclib.close_client()
    await navidrome_client.close_client()

    cleanup_logging()


def start() -> FastAPI:
    logger.info("Starting API server")
    app = FastAPI(
        title="deadwax",
        summary="Search MusicBrainz, download through slskd",
        lifespan=lifespan
    )

    #? Vite writes these with a content hash in the filename, so a given URL's contents can
    #? never change. Revalidating them would be pure waste, and caching them hard is what
    #? makes the hashing worth doing at all.
    IMMUTABLE_PREFIXES = ("/dist/assets/",)

    #? Everything whose URL stays the same while its contents change: the hand-written
    #? interface files, and the Vite entry bundle - deliberately unhashed so the static
    #? index.html can name it (see ui/vite.config.ts), which is exactly what makes it mutable.
    #? The player's page and manifest belong here for the same reason: an installed web app
    #? revalidates on launch like any page, and a cached page is an old app.
    REVALIDATE_PREFIXES = ("/scripts/", "/styles/", "/assets/", "/dist/", "/player/")

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
            elif path == "/" or path.startswith(REVALIDATE_PREFIXES):
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

    #? Added last, so it is the OUTERMOST layer: a write another website asked for is refused
    #? before anything else runs. See src/api/same_origin.py.
    app.add_middleware(SameOriginWrites)

    logger.info("adding routers")
    app.include_router(interface_logs.router, prefix="/deadwax/interface_logs", tags=["interface_logs"])
    app.include_router(search_musicbrainz.router, prefix="/deadwax/search_musicbrainz", tags=["search_musicbrainz"])
    app.include_router(monitor_slskd.router, prefix="/deadwax/monitor_slskd", tags=["monitor_slskd"])
    app.include_router(download.router, prefix="/deadwax/download", tags=["download"])
    app.include_router(library.router, prefix="/deadwax/library", tags=["library"])
    app.include_router(settings.router, prefix="/deadwax/settings", tags=["settings"])
    app.include_router(navidrome.router, prefix="/deadwax/navidrome", tags=["navidrome"])
    #? who the page is talking to - the implicit admin while logins are off (src/users.py)
    app.include_router(me.router, prefix="/deadwax/me", tags=["me"])

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
    app.mount("/", StaticFiles(directory=interface_path, html=True), name="interface")
    logger.info("adding root endpoint to serve index.html")
    @app.get("/")
    async def serve_index():
        return FileResponse(interface_path / "index.html")

    logger.info("API server started")
    return app
