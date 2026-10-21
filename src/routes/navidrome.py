"""
What the player at /player/ may ask Navidrome, and nothing else.

Each route is one Subsonic call with its own parameters, rather than a proxy that passes on
whatever it is sent - see src/api/navidrome_endpoint.py for why that line matters. Adding a
call means adding a route here, on purpose. (The Library's Shuffle, 2.0.0-player.57, makes several:
search3 and getAlbumList2 as the asker, deadwax's own order of what they list - see the end.)
"""

import asyncio
import random
import secrets
import time
from array import array
from collections import OrderedDict
from dataclasses import dataclass
from typing import Literal

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi import Path as PathParam
from fastapi.responses import Response, StreamingResponse
from starlette.background import BackgroundTask

from src import library_ledger, player_cache
from src.api.navidrome_endpoint import NOT_CONFIGURED, NavidromeError, SignedOut, asks_as_shared, client_for
from src.config import Config
from src.logger import logger
from src.routes.download import ClientGone, unless_abandoned
from src.users import current_user

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


#? (2.0.0-player.52) How long Navidrome's word that a user may have a song - getSong answered AS THEM - is
#? believed before the stream cache hands them its copy again without asking: five minutes, the same few
#? minutes the re-check takes to end a session whose password changed (auth.RECHECK_SECONDS). A song is
#? asked for many times while it plays - Safari's probe and every seek, the gapless stream's fragments by
#? range, the turntable's windows - and asking each time would put a round trip in front of every seek;
#? longer would let access Navidrome took away (a library its admin closed to them) outlast the re-check.
#? Only a yes is kept: a song Navidrome hasn't scanned yet is asked about afresh.
ACCESS_SECONDS = 300
#? ...for this many (user, song) pairs at most, the least recently asked going first
ACCESS_KEPT = 4096

_access: "OrderedDict[tuple[str, str], float]" = OrderedDict()


def forget_access() -> None:
    """Every user's access forgotten (the tests; a start)."""
    _access.clear()


async def _theirs(request: Request, song_id: str) -> None:
    """
    Before the stream cache answers - a cached MP4 or fragmented MP4, a turntable window cut from one - the
    song is confirmed to be one Navidrome would give THIS user (2.0.0-player.52): the cache fetches a file
    once for every phone, as the shared account (navidrome_endpoint.SHARED_ACCOUNT_USES), so with one library
    everyone sees everything - and a Navidrome giving users their own libraries must not leak through
    deadwax's cache. One getSong as them, kept ACCESS_SECONDS per user and song. Nothing for the shared
    account itself (logins off, the break-glass admin), which is what the cache asks as. Raises NavidromeError
    as the song itself would: 404 for a song that isn't theirs, 401 for a login Navidrome refused.
    """
    client = client_for(request)
    if asks_as_shared(client):
        return
    who = getattr(getattr(client, "login", None), "user", None)
    key = (who, song_id) if who else None
    now = time.monotonic()
    if key is not None:
        at = _access.get(key)
        if at is not None and now - at < ACCESS_SECONDS:
            _access.move_to_end(key)
            return
    await client.call("getSong", {"id": song_id})
    if key is not None:
        _access[key] = now
        _access.move_to_end(key)
        while len(_access) > ACCESS_KEPT:
            _access.popitem(last=False)


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
async def status(request: Request):
    """Whether the player has a Navidrome to play from, and if not, why not."""
    if not Config.navidrome_configured():
        return {"configured": False, "ok": False, "server": None, "problem": NOT_CONFIGURED}

    try:
        body = await client_for(request).call("ping")
    except SignedOut:
        #? (2.0.0-player.52) the asker's login refused: their session has ended - a 401, never "not set up"
        raise
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
    request: Request,
    order: AlbumList = "newest",
    size: int = Query(60, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    """A page of albums. 500 is Subsonic's own ceiling on one page."""
    try:
        body = await client_for(request).call(
            "getAlbumList2", {"type": order, "size": size, "offset": offset}
        )
    except NavidromeError as e:
        raise _fail(e)

    return {"albums": (body.get("albumList2") or {}).get("album") or []}


@router.get("/albums/{album_id}")
async def album(album_id: str, request: Request):
    """One album with its songs, in Navidrome's order - disc, then track."""
    try:
        body = await client_for(request).call("getAlbum", {"id": album_id})
    except NavidromeError as e:
        raise _fail(e)

    return body.get("album") or {}


#? The most of each the Search tab may ask for in one go: a screenful of artists and albums, and
#? songs enough to page through. Subsonic's own default is 20 of each.
SEARCH_MAX_ARTISTS = 50
SEARCH_MAX_ALBUMS = 50
SEARCH_MAX_SONGS = 500


@router.get("/search")
async def search(
    request: Request,
    #? DECLARED, every one: what isn't declared is never passed on (a forged `u`, a `musicFolderId`,
    #? `f=xml`) - the call is built from these alone, and the login laid over them last
    q: str = Query(..., max_length=200),
    artist_count: int = Query(20, alias="artistCount", ge=0, le=SEARCH_MAX_ARTISTS),
    artist_offset: int = Query(0, alias="artistOffset", ge=0),
    album_count: int = Query(20, alias="albumCount", ge=0, le=SEARCH_MAX_ALBUMS),
    album_offset: int = Query(0, alias="albumOffset", ge=0),
    song_count: int = Query(20, alias="songCount", ge=0, le=SEARCH_MAX_SONGS),
    song_offset: int = Query(0, alias="songOffset", ge=0),
):
    """
    Artists, albums and songs in the library matching `q` - Subsonic's search3, for the app's
    Search tab (2.0.0-player.13), which shows what you have before what MusicBrainz has.

    Safe to hand the page for the reason the other routes are: it READS the library the account
    can see, as every Subsonic app does, and changes nothing - and only these parameters reach it,
    each bounded. Navidrome's answer is passed on as it is (the page reads what it needs and plays
    a song from its album's own answer). An empty `q` is allowed: Navidrome answers it with
    everything, a page at a time, which a later slice's Songs list wants.
    """
    try:
        body = await client_for(request).call("search3", {
            "query": q,
            "artistCount": artist_count, "artistOffset": artist_offset,
            "albumCount": album_count, "albumOffset": album_offset,
            "songCount": song_count, "songOffset": song_offset,
        })
    except NavidromeError as e:
        raise _fail(e)

    found = body.get("searchResult3") or {}
    return {
        "artists": found.get("artist") or [],
        "albums": found.get("album") or [],
        "songs": found.get("song") or [],
    }


#? The longest id the three by-id routes below pass on. Navidrome's are 22-character ids (or 32 hex
#? from an older scan); anything far longer is no id of Navidrome's, and is refused (422) rather
#? than sent.
ID_MAX = 256


@router.get("/artists")
async def artists(request: Request):
    """
    Every artist in the library, in Navidrome's own order (by name, a leading "The" ignored) -
    Subsonic's getArtists, for the app's Library > Artists (2.0.0-player.17).

    Takes NOTHING: getArtists' one parameter, a music folder, is never passed on - the call is the
    same whoever asks, and the login is laid over it as for every route. Navidrome answers an index
    by initial ({index: [{name: "P", artist: [...]}]}); it is flattened into one list, in that order,
    each artist as Navidrome sent it (id, name, albumCount, coverArt, musicBrainzId - the album
    artist's MusicBrainz id, which is how the artist page finds the artist's discography).
    """
    try:
        body = await client_for(request).call("getArtists")
    except NavidromeError as e:
        raise _fail(e)

    index = (body.get("artists") or {}).get("index") or []
    return {"artists": [artist for initial in index if isinstance(initial, dict)
                        for artist in (initial.get("artist") or []) if isinstance(artist, dict)]}


@router.get("/artists/{artist_id}")
async def artist(request: Request, artist_id: str = PathParam(..., min_length=1, max_length=ID_MAX)):
    """
    One artist and their albums - Subsonic's getArtist, for the app's artist page (2.0.0-player.17):
    the albums you have of theirs, which its Play and Shuffle play, and their MusicBrainz id, which
    its discography is browsed by. Only the id is passed on (Navidrome's `id` parameter, never part
    of a path), and Navidrome's answer goes back as it is.
    """
    try:
        body = await client_for(request).call("getArtist", {"id": artist_id})
    except NavidromeError as e:
        raise _fail(e)

    return body.get("artist") or {}


@router.get("/songs/{song_id}")
async def song(request: Request, song_id: str = PathParam(..., min_length=1, max_length=ID_MAX)):
    """
    One song, as Navidrome has it NOW - Subsonic's getSong, for Info > About (2.0.0-player.17): how
    many times it has been played and who wrote it, which the album answer a queue was played from
    holds only as they were at the tap. Only the id is passed on, and the answer goes back as it is.
    """
    try:
        body = await client_for(request).call("getSong", {"id": song_id})
    except NavidromeError as e:
        raise _fail(e)

    return body.get("song") or {}


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
        upstream = await client_for(request).open(
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
            #? (2.0.0-player.52) the cache's copy only for a user Navidrome would give the song to
            await _theirs(request, song_id)
            #? as for the MP4: the phone hanging up is looked for, and cancels the answer
            return await unless_abandoned(request, player_cache.cache.answer_fragmented(song_id, request, rate))
        except ClientGone:
            return Response(status_code=204)
        except NavidromeError as e:
            raise _fail(e)

    if wrap == "mp4" and format == "raw":
        try:
            await _theirs(request, song_id)
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
        upstream = await client_for(request).open("stream", params, _conditions(request, STREAM_CONDITIONS))
    except NavidromeError as e:
        raise _fail(e)

    return _relay(upstream, f"song {song_id}", audio_type(upstream.headers.get("content-type")), "no-cache")


#? The turntable's windows (2.0.0-player.14): from 0 to a day into a song, 1 to 60 seconds long.
SCRUB_MAX_AT = 86400.0
SCRUB_SECONDS = 30.0
SCRUB_MIN_SECONDS = 1.0
SCRUB_MAX_SECONDS = 60.0
#? the only parameters it takes - anything else is refused, not ignored
SCRUB_PARAMETERS = frozenset({"at", "seconds", "max_rate"})


@router.get("/scrub/{song_id}")
async def scrub(
    song_id: str,
    request: Request,
    at: float = Query(..., ge=0, le=SCRUB_MAX_AT),
    seconds: float = Query(SCRUB_SECONDS, ge=SCRUB_MIN_SECONDS, le=SCRUB_MAX_SECONDS),
    max_rate: Literal["48000"] | None = None,
):
    """
    A stretch of a FLAC song - from `at` seconds, for `seconds` - as a FLAC file of its own, which the
    phone's turntable decodes and plays while a hand turns the record, a flick coasts or a pause winds
    it down (2.0.0-player.14). Its sound is its own, apart from the player's: nothing here touches
    what the song is playing on.

    Cut by deadwax from the MP4 its cache keeps of the song (src/player_cache.py, src/flac_window.py),
    which needs nothing from Navidrome but the version check every MP4 answer makes - or, with no MP4
    kept of the song as it is (a page playing the FLAC as it is), straight from the FLAC on Navidrome,
    a few byte ranges of `stream` with `format=raw` - its head, the frames that cover the stretch -
    with nothing made or kept (2.0.0-player.23, src/flac_ranges.py; the plain MP4 made as before only
    where that can't be done): the frames that cover the stretch, untouched, renumbered from 0 under a
    STREAMINFO of their own, the same bytes either way. Nothing the page sends is passed on.
    `max_rate=48000`, as the stream route takes it, when the page plays the song resampled: the window
    is cut from that very copy, so it sounds as the song does - its rate, its level. The answer says
    exactly where in the song it sits, `X-Deadwax-Window: <first sample>/<samples>/<rate>`, since it
    starts on a frame (or a fragment of about a second) at or before `at` and a hi-res song's window
    is shorter than asked (WINDOW_MAX_BYTES). A song that isn't a FLAC is a 415 saying so - the
    turntable is silent for it - a start past the end a 416, Navidrome breaking off a 503, and a cache
    that can't be used a 503 when the window can't be cut from the FLAC either.

    Only `at`, `seconds` and `max_rate`: anything else is refused (422), as everything out of their
    bounds is, and any cap but 48000.
    """
    unknown = set(request.query_params) - SCRUB_PARAMETERS
    if unknown:
        raise HTTPException(status_code=422, detail="the turntable's window takes only at, seconds and max_rate")
    try:
        rate = int(max_rate) if max_rate else None
        #? (2.0.0-player.52) cut from the cache's copy, or from the FLAC as the shared account - only for a
        #? user Navidrome would give the song to
        await _theirs(request, song_id)
        return await unless_abandoned(request, player_cache.cache.answer_window(song_id, at, seconds, rate))
    except ClientGone:
        return Response(status_code=204)
    except NavidromeError as e:
        raise _fail(e)


@router.post("/scrobble/{song_id}")
async def scrobble(song_id: str, request: Request, submission: bool = False, time: int | None = Query(None, ge=0)):
    """
    Tell Navidrome what is playing (`submission=false`) or that it was played (`true`).

    The second is what counts a play in Navidrome and passes it on to Last.fm or ListenBrainz
    if they are set up there; the first is what shows under "now playing".
    """
    try:
        await client_for(request).call("scrobble", {
            "id": song_id, "submission": "true" if submission else "false", "time": time,
        })
    except NavidromeError as e:
        raise _fail(e)

    return {"ok": True}


# ---------------------------------------------------------------- the Library's Shuffle (2.0.0-player.57, Part B)

#? A page of a shuffle's order, as the app asks for it - about 70 KB of JSON a page (15 KB gzipped).
SHUFFLE_PAGE = 200
#? search3's songs a call while a list is built: Navidrome's empty query pages them by rowid, and songCount has no cap
SCAN_PAGE = 2000
#? getAlbumList2's own ceiling, a page of your starred albums
STARRED_PAGE = 500
#? the most songs a shuffle reads - past it the route says so (413): far beyond a home server
SHUFFLE_MAX = 200_000
#? how long the songs of a scope are kept per user before the next order builds the list again - so a song added
#? since is in the next shuffle
SHUFFLE_LIST_TTL_S = 600
#? how long an order is kept after it was last asked for: it slides, so a shuffle that plays for a week is kept
SHUFFLE_ORDER_TTL_S = 24 * 3600
#? per user and scope: orders never handed to the player - what each visit to the list asks for ahead, kept a few so
#? one device's visit never takes the order another device's list holds for its tap (one person on a phone and a
#? desktop, or everyone as `local` with logins off) - and, per user, the ones claimed most recently (handed to the
#? player: paged, named as `playing`, or made with `claim`)
SHUFFLE_UNCLAIMED_KEPT = 4
SHUFFLE_CLAIMED_KEPT = 2
#? a token as secrets.token_urlsafe(16) makes it (22 characters), bounded like an id
SHUFFLE_TOKEN = r"^[A-Za-z0-9_-]{1,64}$"
#? what the queue takes of each song, in Navidrome's own names, so the page's toQueueTrack reads it as it is
SHUFFLE_FIELDS = ("id", "title", "artist", "album", "albumId", "coverArt", "duration", "contentType", "suffix",
                  "samplingRate", "bitDepth", "channelCount", "track", "discNumber")
SHUFFLE_TOO_BIG = "Your library is too big to shuffle here"


@dataclass
class ShuffleOrder:
    """One order of a scope's songs, as a permutation of them: whose it is, the scope it was asked for under, when it
    was last asked for, and whether it has been handed to the player (claimed) - a visit to the list makes one it may
    never play."""

    user: str
    scope: str
    songs: list[dict]
    order: array
    used: float
    claimed: bool = False


#? (user, scope) -> (when built, the songs); one build at a time per (user, scope); token -> its order
_shuffle_lists: dict[tuple[str, str], tuple[float, list[dict]]] = {}
_shuffle_builds: dict[tuple[str, str], asyncio.Lock] = {}
_shuffle_orders: dict[str, ShuffleOrder] = {}


def forget_shuffles() -> None:
    """Every list and order forgotten (the tests; a start)."""
    _shuffle_lists.clear()
    _shuffle_builds.clear()
    _shuffle_orders.clear()


async def _shuffle_songs(request: Request, user: str, scope: str) -> list[dict]:
    """
    Every song of `scope`, as the asker sees them: `store` all of Navidrome's, read with search3's empty query a
    SCAN_PAGE at a time (in Navidrome's natural order, by rowid - persistence/sql_search.go, read at 0.64.2), each
    song once (a scan between pages can move a rowid); `yours` only those of the albums the asker starred
    (getAlbumList2 starred, STARRED_PAGE at a time). Kept SHUFFLE_LIST_TTL_S per (user, scope); one build at a time.
    """
    key = (user, scope)
    lock = _shuffle_builds.setdefault(key, asyncio.Lock())
    async with lock:
        now = time.monotonic()
        for held_key, (built, _) in list(_shuffle_lists.items()):
            if now - built >= SHUFFLE_LIST_TTL_S:
                del _shuffle_lists[held_key]
        held = _shuffle_lists.get(key)
        if held is not None:
            return held[1]
        client = client_for(request)
        albums: set[str] | None = None
        if scope == "yours":
            albums = set()
            offset = 0
            while True:
                body = await client.call("getAlbumList2", {"type": "starred", "size": STARRED_PAGE, "offset": offset})
                page = (body.get("albumList2") or {}).get("album") or []
                albums.update(album["id"] for album in page if isinstance(album, dict) and isinstance(album.get("id"), str))
                if len(page) < STARRED_PAGE:
                    break
                offset += STARRED_PAGE
        songs: list[dict] = []
        seen: set[str] = set()
        offset = 0
        while True:
            body = await client.call("search3", {
                "query": "", "artistCount": 0, "albumCount": 0, "songCount": SCAN_PAGE, "songOffset": offset,
            })
            page = (body.get("searchResult3") or {}).get("song") or []
            before = len(seen)
            for song in page:
                if not isinstance(song, dict) or not isinstance(song.get("id"), str) or song["id"] in seen:
                    continue
                seen.add(song["id"])
                if albums is None or song.get("albumId") in albums:
                    songs.append({name: song[name] for name in SHUFFLE_FIELDS if name in song})
            if len(seen) > SHUFFLE_MAX:
                raise HTTPException(status_code=413, detail=SHUFFLE_TOO_BIG)
            #? a short page is the end - and so is a full one that brought nothing new (a server that ignores the offset)
            if len(page) < SCAN_PAGE or len(seen) == before:
                break
            offset += SCAN_PAGE
        _shuffle_lists[key] = (time.monotonic(), songs)
        return songs


def _keep_orders(user: str, claimed: bool, kept: int, scope: str | None = None) -> None:
    """The user's orders of one kind (and of one `scope`, if named), the most recently asked-for `kept` of them kept,
    the oldest going first."""
    theirs = sorted((held.used, token) for token, held in _shuffle_orders.items()
                    if held.user == user and held.claimed == claimed and (scope is None or held.scope == scope))
    for _, token in theirs[:max(0, len(theirs) - kept)]:
        del _shuffle_orders[token]


def _forget_old_orders(now: float) -> None:
    for token, held in list(_shuffle_orders.items()):
        if now - held.used >= SHUFFLE_ORDER_TTL_S:
            del _shuffle_orders[token]


def _shuffle_page(held: ShuffleOrder, offset: int) -> list[dict]:
    return [held.songs[at] for at in held.order[offset:offset + SHUFFLE_PAGE]]


def _claim(held: ShuffleOrder, now: float) -> None:
    """An order handed to the player: kept among the user's SHUFFLE_CLAIMED_KEPT claimed most recently."""
    held.used = now
    held.claimed = True
    _keep_orders(held.user, claimed=True, kept=SHUFFLE_CLAIMED_KEPT)


@router.get("/shuffle")
async def shuffle(
    request: Request,
    scope: Literal["yours", "store"] = Query(...),
    playing: str | None = Query(None, pattern=SHUFFLE_TOKEN),
    claim: bool = False,
    user: str = Depends(current_user),
):
    """
    A new order of every song of `scope` (2.0.0-player.57, Part B: the Library's Shuffle) - each once, in a random
    order deadwax makes (random.SystemRandom over the list), held under a new token for the asker. `yours`: the songs
    of your starred albums - with logins off, or for the break-glass admin (who has no library), the store, which is
    the library then. Answers the token, how many songs the order has, and its first SHUFFLE_PAGE; the app asks for
    the rest as it plays (/shuffle/{token}). Nothing the page sends reaches Navidrome but the scope, which picks the
    calls. A user keeps SHUFFLE_UNCLAIMED_KEPT orders per scope never handed to the player (each visit to the list
    asks for one ahead, on whichever device; the oldest goes when there are more - 2.0.0-player.57's second review: at
    one, a phone's visit took the order a desktop's list held, and its tap's shuffle "started over"). `playing`: the token of the order the list's Shuffle just played - claimed
    here, before that replacing, since the list asks for the next tap's order straight after the tap, long before the
    order playing is paged (2.0.0-player.57's review: it went, and its second page was a 404). `claim`: the order
    made now is to play at once (the feed's fresh order), so claimed as it is made.
    """
    asked = scope if scope == "store" or (Config.logins_on() and library_ledger.has_library(user)) else "store"
    try:
        songs = await _shuffle_songs(request, user, asked)
    except NavidromeError as e:
        raise _fail(e)
    order = array("I", range(len(songs)))
    random.SystemRandom().shuffle(order)
    now = time.monotonic()
    _forget_old_orders(now)
    played = _shuffle_orders.get(playing) if playing is not None else None
    if played is not None and played.user == user:
        _claim(played, now)
    token = secrets.token_urlsafe(16)
    held = ShuffleOrder(user=user, scope=scope, songs=songs, order=order, used=now)
    _shuffle_orders[token] = held
    if claim:
        _claim(held, now)
    else:
        _keep_orders(user, claimed=False, kept=SHUFFLE_UNCLAIMED_KEPT, scope=scope)
    return {"token": token, "total": len(order), "songs": _shuffle_page(held, 0)}


@router.get("/shuffle/{token}")
async def shuffle_more(
    token: str = PathParam(..., pattern=SHUFFLE_TOKEN),
    offset: int = Query(..., ge=0, le=SHUFFLE_MAX),
    user: str = Depends(current_user),
):
    """
    The next page of an order, from `offset` - claiming it: a user keeps the SHUFFLE_CLAIMED_KEPT orders most recently
    claimed (paged, or claimed by /shuffle), each SHUFFLE_ORDER_TTL_S after it was last asked for, so opening the list again and again never pushes out
    the order that is playing. Another user's token, or one deadwax no longer holds (it restarted, or a day passed
    untouched), is a 404 saying "gone" - the app's feed then starts a fresh order. Asks Navidrome nothing.
    """
    now = time.monotonic()
    _forget_old_orders(now)
    held = _shuffle_orders.get(token)
    if held is None or held.user != user:
        raise HTTPException(status_code=404, detail="gone")
    _claim(held, now)
    return {"total": len(held.order), "songs": _shuffle_page(held, offset)}
