"""
What the player at /player/ may ask Navidrome, and nothing else.

Each route is one Subsonic call with its own parameters, rather than a proxy that passes on
whatever it is sent - see src/api/navidrome_endpoint.py for why that line matters. Adding a
call means adding a route here, on purpose.
"""

from typing import Literal

import httpx
from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import Response, StreamingResponse
from starlette.background import BackgroundTask

from src import player_cache
from src.api.navidrome_endpoint import NOT_CONFIGURED, NavidromeError, navidrome
from src.config import Config
from src.logger import logger
from src.routes.download import ClientGone, unless_abandoned

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
    wrap: Literal["mp4", "fmp4"] | None = None,
    #? a string, converted below: FastAPI won't take the query's "48000" for the number 48000, and
    #? a Literal[48000] refuses every request. DECLARED, like everything the page sends - a
    #? parameter left out is ignored without a word, and the song would come back as it is
    max_rate: Literal["48000"] | None = None,
):
    """
    A song's audio, with the page's byte range and conditions passed through.

    `wrap=mp4`, with `format=raw`, asks for a FLAC song inside an MP4 of the very same frames -
    lossless, and the one form of it whose seeks Safari lands where they were asked (see
    src/player_cache.py, and src/flac_mp4.py for why). The page asks for it only from WebKit, and
    only for a FLAC. It is made once per version of the file and served from a cache, with byte
    ranges; anything that isn't a FLAC it can repackage is sent exactly as it would be without it.
    One URL stays on one container: a range carrying on from an MP4 that can't be had just now is
    a 503, never the FLAC's bytes under another length.

    `wrap=fmp4`, with `format=raw` only (anything else is a 400), asks for the same frames as a
    FRAGMENTED MP4, which the gapless player feeds to one MediaSource stream across songs. It is
    cached like the MP4 but apart from it, and always answered by deadwax itself - never relayed,
    since the stream can't take the FLAC: the fragments with byte ranges, a 415 saying why when the
    song can't be repackaged, or a 503 saying whether to ask again (`scope`: song or server).

    `max_rate=48000`, with `format=raw` and a `wrap` only (anything else is a 400), is the player's
    "Up to 48 kHz": a FLAC song above 48 kHz - 88.2 to 384 kHz, at a whole ratio, 16- or 24-bit - is
    resampled by deadwax to 48 kHz or 44.1 kHz, as 24-bit FLAC in either container, so the gapless
    stream can take it; its answers say `X-Deadwax-Resampled: <from>-<to>`. Nothing below 20 kHz
    changes (src/resample.py says how that is kept), and the songs of an album still join exactly,
    each resampled with its neighbours' samples on one grid (src/album_context.py). Any other song is
    answered exactly as without it - the same bytes, the same ETag. It is a variant of its own: the
    same song asked for without it is another file, answered on its own.

    `format=raw` is the file as it is, which is the only kind Navidrome can answer a byte range
    for, and the player asks for it for every file the phone can play. It is asked for by name
    because Navidrome answers `raw` before it looks at anything set for this client on its
    Players page, where leaving the format out lets a setting there turn every song into a
    transcode. Another format is asked for only when the phone can't play the file (see the
    player's canPlayType check). A transcode is produced as it plays, so it can't be sought by
    range until Navidrome has cached it, and its length is only an estimate.

    Never cached without asking: a retag rewrites a file in place under the same URL.
    """
    rate = int(max_rate) if max_rate else None
    if rate is not None and (format != "raw" or wrap is None):
        #? a transcode has no FLAC to resample, and the FLAC relayed as it is can't be either
        raise HTTPException(status_code=400, detail="max_rate needs format=raw and wrap=mp4 or wrap=fmp4: only "
                                                    "the file as it is, repackaged by deadwax, can be resampled")

    if wrap == "fmp4":
        if format != "raw":
            #? a transcode has no FLAC frames to put in fragments, and relaying one would feed the
            #? stream something it can't take
            raise HTTPException(status_code=400, detail="wrap=fmp4 needs format=raw: only the file as it is "
                                                        "can be repackaged")
        try:
            #? as for the MP4: the phone hanging up is looked for, and cancels the answer
            return await unless_abandoned(request, player_cache.cache.answer_fragmented(song_id, request, rate))
        except ClientGone:
            return Response(status_code=204)
        except NavidromeError as e:
            raise _fail(e)

    if wrap == "mp4" and format == "raw":
        try:
            #? uvicorn never cancels a handler whose phone has gone, so this looks every half second
            #? and cancels the answer itself - which takes the request off the MP4 it waits for, and a
            #? make nobody waits for stops, its download from Navidrome included
            wrapped = await unless_abandoned(request, player_cache.cache.answer(song_id, request, rate))
        except ClientGone:
            return Response(status_code=204)
        except NavidromeError as e:
            raise _fail(e)
        if wrapped is not None:
            return wrapped

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
