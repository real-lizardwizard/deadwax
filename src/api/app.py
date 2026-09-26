import asyncio
from pathlib import Path
from fastapi import FastAPI
from contextlib import asynccontextmanager
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse

from src.routes import search_musicbrainz, interface_logs, monitor_slskd, download, library, settings
from src.logger import logger, cleanup_logging
from src.poller import run_download_poller
from src.store import JobStore

from src.api.musicbrainz_endpoint import MusicBrainzClient
from src.api.slskd_endpoint import SlskdClient
from src.api.lrclib_endpoint import lrclib
from src.config import Config
from src import __version__

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
    REVALIDATE_PREFIXES = ("/scripts/", "/styles/", "/assets/", "/dist/")

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

    logger.info("adding routers")
    app.include_router(interface_logs.router, prefix="/deadwax/interface_logs", tags=["interface_logs"])
    app.include_router(search_musicbrainz.router, prefix="/deadwax/search_musicbrainz", tags=["search_musicbrainz"])
    app.include_router(monitor_slskd.router, prefix="/deadwax/monitor_slskd", tags=["monitor_slskd"])
    app.include_router(download.router, prefix="/deadwax/download", tags=["download"])
    app.include_router(library.router, prefix="/deadwax/library", tags=["library"])
    app.include_router(settings.router, prefix="/deadwax/settings", tags=["settings"])

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
