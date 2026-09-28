"""
What the player at /player/ may ask Navidrome, and nothing else.

Each route is one Subsonic call with its own parameters, rather than a proxy that passes on
whatever it is sent - see src/api/navidrome_endpoint.py for why that line matters. Adding a
call means adding a route here, on purpose.
"""

from typing import Literal

import httpx
from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import StreamingResponse
from starlette.background import BackgroundTask

from src.api.navidrome_endpoint import NOT_CONFIGURED, NavidromeError, navidrome
from src.config import Config
from src.logger import logger

router = APIRouter()

#? Subsonic's own album list orders - the ones that need no further parameter.
AlbumList = Literal[
    "newest", "recent", "frequent", "random", "starred", "highest",
    "alphabeticalByName", "alphabeticalByArtist",
]

#? What is passed back from a stream or a cover as Navidrome sent it. Content-Range and
#? Accept-Ranges are the ones that matter: Safari will not play audio from a server that can't
#? answer a byte range, and it asks for the first two bytes before anything else to find out.
#? The type and the cache policy are decided below instead of copied.
PASSED_HEADERS = (
    "content-length", "content-range", "accept-ranges", "content-encoding", "last-modified", "etag",
)

#? The only types a cover goes out as. Navidrome sets no type on a cover - Go guesses one from the
#? first bytes - and a picture it can't decode is served as the bytes it was given, so an audio
#? file's embedded "picture" that is really a web page would come back as text/html and run as a
#? page on deadwax's own address, where it can use everything the page can. Never SVG either,
#? which carries script of its own.
COVER_TYPES = frozenset({"image/jpeg", "image/png", "image/gif", "image/webp", "image/avif", "image/bmp"})

#? What anything else goes out as: bytes nothing will render.
UNKNOWN_TYPE = "application/octet-stream"

#? A cover whose answer carries no policy of its own. Navidrome's usually does (never for a
#? placeholder, a year for an id carrying the picture's hash, revalidate otherwise), and it is
#? passed on as it is; this is only for something that sent none.
COVER_CACHE = "private, max-age=86400"

#? The request headers the page may send on. Navidrome answers each of them - Go's ServeContent
#? for a file, its own ETag check for a cover - so a cover the phone already holds comes back as a
#? 304 with no body, and If-Range stops a seek splicing two versions of a file that a retag
#? rewrote in place between one range and the next.
COVER_CONDITIONS = ("if-none-match", "if-modified-since")
STREAM_CONDITIONS = ("range", "if-range", "if-none-match", "if-modified-since")


#? How much of Navidrome's estimate a transcode has to have sent for its connection closing to be
#? its ordinary end (1.0.3 review). The estimate runs a few per cent over for a constant bit rate
#? MP3; a transcode that stops further short than this - or sends nothing - has failed.
TRANSCODE_END_SHARE = 0.9


def _whole(value: str | None) -> int | None:
    """A Content-Length as a number, or None when it isn't one."""
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _media_type(value: str | None) -> str:
    return (value or "").split(";")[0].strip().lower()


def cover_type(value: str | None) -> str:
    media = _media_type(value)
    return media if media in COVER_TYPES else UNKNOWN_TYPE


def audio_type(value: str | None) -> str:
    media = _media_type(value)
    return media if media.startswith("audio/") or media == "application/ogg" else UNKNOWN_TYPE


def _fail(error: NavidromeError) -> HTTPException:
    return HTTPException(status_code=error.status, detail=str(error), headers=error.headers)


def _conditions(request: Request, names: tuple[str, ...]) -> dict[str, str]:
    return {name: request.headers[name] for name in names if name in request.headers}


class Relayed(StreamingResponse):
    """
    A Navidrome answer streamed on as it arrives, closed however the client leaves - and left
    UNFINISHED when Navidrome stops sending part-way.

    Finishing it would tell the phone the song ended there. With a Content-Length it can't be
    finished anyway: h11 refuses to end a body short of its declared length, and uvicorn prints
    that refusal as a traceback. A connection closed early is how the phone learns the body was
    cut, and it is what Navidrome itself does when a transcode fails part-way. So the break is
    logged once in words, and uvicorn adds its own one line about the unfinished answer.
    """

    def __init__(self, upstream: httpx.Response, what: str, headers: dict[str, str]):
        self.upstream = upstream
        self.what = what
        self.cut = False
        super().__init__(
            self._body(),
            status_code=upstream.status_code,
            headers=headers,
            #? a client that leaves before the first chunk never starts the generator, so its
            #? finally never runs - this closes the connection to Navidrome in that case too
            background=BackgroundTask(upstream.aclose),
        )

    async def _body(self):
        sent = 0
        try:
            #? raw, so the bytes and the Content-Length passed on describe the same thing
            async for chunk in self.upstream.aiter_raw():
                sent += len(chunk)
                yield chunk
        except httpx.TransportError as e:
            self.cut = True
            self._report(sent, e)
        finally:
            await self.upstream.aclose()

    def _report(self, sent: int, error: httpx.TransportError) -> None:
        declared = self.upstream.headers.get("content-length")
        estimated = bool(declared) and self.upstream.headers.get("accept-ranges") == "none"
        estimate = _whole(declared) if estimated else None
        if estimate and sent >= estimate * TRANSCODE_END_SHARE:
            #? A transcode's length is Navidrome's ESTIMATE (duration x bit rate, a few per cent
            #? over for an MP3), and Navidrome closes the connection where the transcode really
            #? ends - so this is how a transcode ordinarily finishes, not a failure.
            logger.info(f"player: the transcode of {self.what} ended at {sent} of the {declared} "
                        f"bytes Navidrome estimated, and its connection was closed there")
            return
        #? Further short than an estimate is ever out by - 0 bytes included, which is ffmpeg
        #? producing nothing (Navidrome logs that as an error of its own) - is a failure
        amount = (f"{sent} of the {declared} bytes Navidrome estimated" if estimated
                  else f"{sent} of {declared} bytes" if declared else f"{sent} bytes")
        logger.warning(f"player: Navidrome stopped sending {self.what} after {amount} "
                       f"({str(error) or type(error).__name__}); the phone's connection was closed there too")

    async def stream_response(self, send) -> None:
        #? Starlette's own, except that the closing message isn't sent after a break
        await send({"type": "http.response.start", "status": self.status_code, "headers": self.raw_headers})
        async for chunk in self.body_iterator:
            await send({"type": "http.response.body", "body": chunk, "more_body": True})
        if not self.cut:
            await send({"type": "http.response.body", "body": b"", "more_body": False})


def _relay(upstream: httpx.Response, what: str, content_type: str, cache_control: str) -> Relayed:
    """Navidrome's answer on its way to the phone, with the type and cache policy given."""
    headers = {name: upstream.headers[name] for name in PASSED_HEADERS if name in upstream.headers}
    #? a 304 has no body, so it names no type
    if upstream.status_code != 304:
        headers["content-type"] = content_type
    headers["cache-control"] = cache_control
    return Relayed(upstream, what, headers)


@router.get("/status")
async def status():
    """Whether the player has a Navidrome to play from, and if not, why not."""
    if not Config.navidrome_configured():
        return {"configured": False, "ok": False, "server": None, "problem": NOT_CONFIGURED}

    try:
        body = await navidrome.call("ping")
    except NavidromeError as e:
        return {"configured": True, "ok": False, "server": None, "problem": str(e)}

    name = "Navidrome" if body.get("type") == "navidrome" else (body.get("type") or "Subsonic")
    version = body.get("serverVersion")
    return {
        "configured": True,
        "ok": True,
        "server": f"{name} {version}" if version else name,
        "problem": None,
    }


@router.get("/albums")
async def albums(
    order: AlbumList = "newest",
    size: int = Query(60, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    """A page of albums. 500 is Subsonic's own ceiling on one page."""
    try:
        body = await navidrome.call(
            "getAlbumList2", {"type": order, "size": size, "offset": offset}
        )
    except NavidromeError as e:
        raise _fail(e)

    return {"albums": (body.get("albumList2") or {}).get("album") or []}


@router.get("/albums/{album_id}")
async def album(album_id: str):
    """One album with its songs, in Navidrome's order - disc, then track."""
    try:
        body = await navidrome.call("getAlbum", {"id": album_id})
    except NavidromeError as e:
        raise _fail(e)

    return body.get("album") or {}


@router.get("/cover/{cover_id}")
async def cover(cover_id: str, request: Request, size: int | None = Query(None, ge=16, le=2000)):
    """
    A cover, at a size Navidrome resizes to and keeps.

    Cached as Navidrome says. It never caches a placeholder (what it shows for an album whose art
    it hasn't resolved yet, which a fixed day's caching would pin on the phone long after the
    real cover arrived), keeps a cover whose id carries the picture's hash for a year, and has
    the rest revalidated - which the ETag and the conditions passed on make a 304 with no body.
    So a phone scrolling a grid of hundreds still doesn't fetch each of them again.
    """
    try:
        upstream = await navidrome.open(
            "getCoverArt", {"id": cover_id, "size": size}, _conditions(request, COVER_CONDITIONS)
        )
    except NavidromeError as e:
        raise _fail(e)

    return _relay(upstream, f"cover {cover_id}", cover_type(upstream.headers.get("content-type")),
                  upstream.headers.get("cache-control") or COVER_CACHE)


@router.get("/stream/{song_id}")
async def stream(
    song_id: str,
    request: Request,
    format: str | None = Query(None, pattern=r"^[a-z0-9]{1,10}$"),
    max_bitrate: int | None = Query(None, ge=0, le=3200),
):
    """
    A song's audio, with the page's byte range and conditions passed through.

    `format=raw` is the file as it is, which is the only kind Navidrome can answer a byte range
    for, and the player asks for it for every file the phone can play. It is asked for by name
    because Navidrome answers `raw` before it looks at anything set for this client on its
    Players page, where leaving the format out lets a setting there turn every song into a
    transcode. Another format is asked for only when the phone can't play the file (see the
    player's canPlayType check). A transcode is produced as it plays, so it can't be sought by
    range until Navidrome has cached it, and its length is only an estimate.

    Never cached without asking: a retag rewrites a file in place under the same URL.
    """
    params = {"id": song_id, "format": format, "maxBitRate": max_bitrate}
    #? For anything but the file as it is, have Navidrome send a Content-Length - its estimate,
    #? from the duration and bit rate. It reads this only for a transcode, which otherwise goes
    #? out with no length at all (core/stream/media_streamer.go), and no format at all can still
    #? become one, through the Players page.
    if format != "raw":
        params["estimateContentLength"] = "true"

    try:
        upstream = await navidrome.open("stream", params, _conditions(request, STREAM_CONDITIONS))
    except NavidromeError as e:
        raise _fail(e)

    return _relay(upstream, f"song {song_id}", audio_type(upstream.headers.get("content-type")), "no-cache")


@router.post("/scrobble/{song_id}")
async def scrobble(song_id: str, submission: bool = False, time: int | None = Query(None, ge=0)):
    """
    Tell Navidrome what is playing (`submission=false`) or that it was played (`true`).

    The second is what counts a play in Navidrome and passes it on to Last.fm or ListenBrainz
    if they are set up there; the first is what shows under "now playing".
    """
    try:
        await navidrome.call("scrobble", {
            "id": song_id, "submission": "true" if submission else "false", "time": time,
        })
    except NavidromeError as e:
        raise _fail(e)

    return {"ok": True}
