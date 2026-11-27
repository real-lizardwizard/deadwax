"""
A song's credits - who played what on it - for the app's Info (credits, slice C1, 27 Nov 2026):
`GET /deadwax/credits/song/{song_id}`, a user's route (tests/test_logins.py ROUTES), asked AS THE ASKER. The rules of
what is shown are src/credits.py's (pure); notes/credits.md has the whole story.

FINDING THE SONG ON ITS RELEASE, from Navidrome alone, as the asker (client_for): getSong (which is also their access:
a song they may not have is its "not found", a 404, as every by-id player route answers) - its `musicBrainzId` is the
RECORDING's id, from the file's musicbrainz_trackid tag (Picard's; deadwax writes none, so every song it filed sends
""), its `discNumber` and `track` - then getAlbum of its `albumId`: the album's `musicBrainzId` (the release id Navidrome
read from the folder's MUSICBRAINZ_ALBUMID, as stars.py and the id bridge read it), its songs (the track numbers on
the song's disc) and its originalReleaseDate. By the recording id when the file has one, else by disc and track - only
when the disc's track numbers are the release's positions (credits.place). No release id: "unmatched".

ASKING MUSICBRAINZ: get_release_credits (kept parsed, in memory an hour and on disk a month, shared by everyone - the
data is nobody's own), and, only when nothing on the release says who performed and its one artist is a group, the
artist lookup deadwax already makes (get_artist, ARTIST_INC - the band's members). Each is ONE LOOKUP AT A TIME PER
KEY (`_asking`, by release id and by the band's artist id): however many ask at once, MusicBrainz is asked once and
every ask awaits that one, shielded, so one that stops waiting never cancels it for the rest. A band's artist
MusicBrainz has nothing at (a 404) is a definite "no line-up" - "none", not "unavailable" - kept NO_ARTIST_KEPT_S here,
since the client keeps successes only. Both waited for CREDITS_DEADLINE_S at most: past it the answer is "unavailable"
- the app says credits can't be asked for just now - and the lookups go on, held and stopped as deadwax stops, so what
comes is kept and the next ask has it. A kept answer, of any age, is always answered at once, MusicBrainz up or down.

NEVER A 500, NEVER THE INFO PAGE'S END: MusicBrainz away, Navidrome away or a fault in deadwax are "unavailable";
MusicBrainz having nothing at the release id is "unmatched". This route's own lines ("credits: ...") are said in
deadwax's log at info (a fault in deadwax at warning), never marked for the event log - but the MusicBrainz client's
own, while it retries and when it gives up (its network errors, a 503, a refused user agent), are, as every
MusicBrainz question's are: so an outage met by a credits lookup can show in the event log. Only two answers aren't a
200: a song the asker may not have (404), and a session Navidrome ended (401, as everywhere).
"""

import asyncio
import time

from fastapi import APIRouter, HTTPException, Path as PathParam, Request

from src import credits
from src.api.navidrome_endpoint import NavidromeError, SignedOut, client_for
from src.lastfm import answerable
from src.logger import logger
from src.routes.navidrome import ID_MAX

router = APIRouter()

#? How long MusicBrainz is waited for before the answer is "unavailable" (the lookups going on behind it). A kept
#? answer never waits: it comes from memory or the disk in well under a second.
CREDITS_DEADLINE_S = 8.0
#? Subsonic's "data not found"
NOT_FOUND = 70
#? A band's artist id MusicBrainz has nothing at (a 404 - deleted, or merged away), kept as "no line-up" for a day,
#? the newest NO_ARTIST_MOST of them
NO_ARTIST_KEPT_S = 24 * 3600.0
NO_ARTIST_MOST = 512

#? each ask's own lookup, held to its end so the deadline can stop waiting without cancelling it
_running: set[asyncio.Task] = set()
#? the MusicBrainz lookups under way, one per key ("release:<id>", "artist:<id>"), shared by every ask
_asking: dict[str, asyncio.Task] = {}
#? the band artist ids MusicBrainz answered a 404 for, with when (time.monotonic)
_no_artist: dict[str, float] = {}


def _held(coroutine) -> asyncio.Task:
    """An ask's lookup, held until it ends - so the deadline can stop waiting without cancelling it."""
    task = asyncio.create_task(coroutine)
    _running.add(task)
    task.add_done_callback(_running.discard)
    task.add_done_callback(_ended)
    return task


def _ended(task: asyncio.Task) -> None:
    if not task.cancelled() and task.exception() is not None:
        logger.warning(f"credits: a lookup failed - a fault in deadwax: {type(task.exception()).__name__}")


def _asked(key: str, ask) -> asyncio.Task:
    """The lookup of `key` under way, or a new one of `ask()` - one at a time per key, as lastfm_kept's are."""
    task = _asking.get(key)
    if task is None or task.done() or task.get_loop() is not asyncio.get_running_loop():
        task = _asking[key] = asyncio.create_task(ask())
        task.add_done_callback(lambda done: _settled(key, done))
    return task


def _settled(key: str, task: asyncio.Task) -> None:
    if _asking.get(key) is task:
        del _asking[key]


async def _shared(key: str, ask):
    """The answer of the one lookup of `key`, awaited SHIELDED: an ask that stops waiting (cancelled) never cancels
    it for the others, nor what it keeps."""
    return await asyncio.shield(_asked(key, ask))


async def stop() -> None:
    """deadwax is stopping: every lookup still under way cancelled - each ask's, and the MusicBrainz ones they share."""
    tasks = [*_running, *_asking.values()]
    for task in tasks:
        task.cancel()
    for task in tasks:
        try:
            await task
        except (asyncio.CancelledError, Exception):
            pass
    _running.clear()
    _asking.clear()


def _failed(found) -> bool:
    return not isinstance(found, dict) or found.get("status") == "failed" or "error" in found


def _nothing_at(found) -> bool:
    """MusicBrainz's 404: nothing at that id - an answer, not an outage."""
    return isinstance(found, dict) and found.get("status") == "failed" and found.get("code") == 404


async def _band(client, band: str):
    """The band's artist lookup - None when MusicBrainz has nothing at its id (kept NO_ARTIST_KEPT_S, so it is asked
    once a day, not on every visit), else what the client answered (its error dict when it couldn't ask)."""
    seen = _no_artist.get(band)
    if seen is not None and time.monotonic() - seen < NO_ARTIST_KEPT_S:
        return None
    artist = await _shared(f"artist:{band}", lambda: client.get_artist(band))
    if _nothing_at(artist):
        logger.info("credits: MusicBrainz has nothing at the band's artist id - no line-up")
        _no_artist.pop(band, None)
        while len(_no_artist) >= NO_ARTIST_MOST:
            del _no_artist[next(iter(_no_artist))]
        _no_artist[band] = time.monotonic()
        return None
    return artist


async def _look_up(request: Request, release: str, where: credits.Where, album: dict) -> dict:
    """MusicBrainz asked (or its kept answers read), and the answer made - every failure an answer of its own."""
    client = request.app.state.musicbrainz_client
    found = await _shared(f"release:{release}", lambda: client.get_release_credits(release))
    if _failed(found) or not credits.is_current(found):
        if _nothing_at(found):
            logger.info("credits: MusicBrainz has nothing at that album's release id")
            return credits.empty("unmatched", credits.album_year(album, None))
        logger.info(f"credits: MusicBrainz couldn't be asked just now "
                    f"({found.get('error') if isinstance(found, dict) else 'no answer'})")
        return credits.empty("unavailable", credits.album_year(album, None))

    year = credits.album_year(album, found)
    track = credits.place(found, where)
    band = credits.band_of(found)
    members, dated, band_failed = None, None, False
    if band:
        artist = await _band(client, band)
        if artist is None:
            members = []
        elif _failed(artist):
            band_failed = True
            logger.info("credits: MusicBrainz couldn't be asked for the band's members just now")
        else:
            members, dated = credits.line_up(artist, credits.album_date(album, found))
    said = credits.answer(found, track, year=year, band=band, members=members, dated=dated)
    if said["level"] == "none" and band_failed:
        #? whether the band's line-up would have answered is unknown - not "none" yet
        return credits.empty("unavailable", year)
    return said


async def _navidrome(request: Request, song_id: str) -> tuple[dict, dict] | dict:
    """The song and its album from Navidrome, as the asker - or the answer to give instead."""
    navidrome = client_for(request)
    try:
        song = (await navidrome.call("getSong", {"id": song_id})).get("song")
    except SignedOut:
        raise
    except NavidromeError as e:
        if e.code == NOT_FOUND:
            #? a song the asker may not have, or none: Navidrome's own "not found", as the other by-id routes say it
            raise HTTPException(status_code=404, detail=str(e))
        logger.info(f"credits: Navidrome couldn't be asked for the song just now ({e})")
        return credits.empty("unavailable")
    song = song if isinstance(song, dict) else {}
    album_id = song.get("albumId")
    if not isinstance(album_id, str) or not album_id or len(album_id) > ID_MAX:
        return credits.empty("unmatched")
    try:
        album = (await navidrome.call("getAlbum", {"id": album_id})).get("album")
    except SignedOut:
        raise
    except NavidromeError as e:
        if e.code == NOT_FOUND:
            return credits.empty("unmatched")
        logger.info(f"credits: Navidrome couldn't be asked for the album just now ({e})")
        return credits.empty("unavailable")
    return song, album if isinstance(album, dict) else {}


@router.get("/song/{song_id}")
async def song_credits(request: Request, song_id: str = PathParam(..., min_length=1, max_length=ID_MAX)):
    """A song's credits: `{level, year, dated, others_credited, performers: [{id, name, did, joined, left}], written:
    [{job, people}], production: [{job, people}], recorded, source_url}` - src/credits.py answer(), its levels song,
    album, band, none, unmatched and unavailable."""
    known = await _navidrome(request, song_id)
    if isinstance(known, dict):
        return known
    song, album = known
    release = credits.release_of(album)
    if release is None:
        return credits.empty("unmatched", credits.album_year(album, None))

    task = _held(_look_up(request, release, credits.navidrome_place(song, album), album))
    done, _ = await asyncio.wait({task}, timeout=CREDITS_DEADLINE_S)
    if not done:
        logger.info(f"credits: MusicBrainz not in by {CREDITS_DEADLINE_S:g} s - answered without, and kept when it "
                    f"comes")
        return credits.empty("unavailable", credits.album_year(album, None))
    if task.cancelled() or task.exception() is not None:
        #? deadwax stopping (the lookup cancelled), or a fault in deadwax (said once, by _ended): never a 500
        return credits.empty("unavailable", credits.album_year(album, None))
    #? a text no UTF-8 carries (a lone surrogate in a name) is U+FFFD, never a 500
    return answerable(task.result())
