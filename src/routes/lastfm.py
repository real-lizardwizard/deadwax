"""
Last.fm, for the iPhone and Mac app's artist page (2.1.41, S2; 2.1.43, S4 - notes/lastfm.md; the design is
deadwax-plans/lastfm.md 2.5): `GET /deadwax/lastfm/artist`, a user's route (tests/test_logins.py ROUTES). The web app
doesn't call it.

Takes `mbid` (the artist's MusicBrainz id, MBID_PATTERN) and/or `name` (1-NAME_MAX letters) - at least one, a 422
otherwise - and answers, always a 200:

  {"enabled": true, "unavailable": false, "why": null,
   "url": "https://www.last.fm/music/Tame+Impala", "listeners": 4724887,
   "top_songs": [{"title": "The Less I Know the Better", "playcount": 51995043, "listeners": 2955438,
                  "url": "https://www.last.fm/music/Tame+Impala/_/The+Less+I+Know+the+Better"}, ...],
   "similar": [{"name": "Pond", "mbid": "69ac44f7-c80d-47b4-9bc8-fcc758d209e6", "match": 1.0,
                "url": "https://www.last.fm/music/Pond"}, ...],
   "top_albums": [{"title": "Currents", "mbid": "031ecbde-35e1-4d3a-917f-f89f31aca1c9", "plays": 197990342,
                   "counted": "plays"}, ...]}

(Tame Impala as Last.fm answered on 2026-11-25 - tests/fixtures/lastfm/recorded/.)

src/lastfm.py artist_answer() says what each field is. `similar` and `top_albums` are 2.1.43's (S4): before it they
weren't in the answer at all, and an app that reads neither decodes it as before.

FOUR PARTS, ASKED AT ONCE - artist.getInfo (url, listeners), artist.getTopTracks (limit 50), artist.getSimilar (limit
30) and artist.getTopAlbums (limit 50) - each through the keeping (src/lastfm_kept.py: shared by everyone, a week
fresh), by MusicBrainz id first; a "not known" by id (kept 3 days) asks again by name with autocorrect=1, kept under the
name. With no id, by name. A name that folds to nothing (lastfm.name_key: "!!!") is never asked by: it would share one
kept row with every other such name. Each part stands alone: one failing, late or not known leaves the others.

ANSWERED BY ARTIST_DEADLINE_S: a part not in by then is null, with `unavailable`, and goes on - its answer kept when
it comes, so the next visit has it. The part's own ask is never cancelled by the page; deadwax's stop cancels it.
Every text in the answer is one UTF-8 can carry (lastfm.answerable, 2.1.43's review): a lone surrogate from Last.fm
is U+FFFD, never a 500.

NO KEY: `enabled` false and `why` saying where to add one - nothing asked. REFUSED (the client holds Last.fm's 10 or
26): kept answers are still answered, `why` in refused words; with nothing kept `enabled` is false. `why` is for whoever
runs deadwax (auth.Explained's rule: the app shows it only to them); a blip - Last.fm down, limiting, slow - has none,
only `unavailable`. Nothing here raises past the route: whatever goes wrong is a part that couldn't be had.

RADIO (2.1.44, S5 - the design's 2.6): `GET /deadwax/lastfm/radio?song_id=&title=&artist=&scope=`, a user's route too.
Songs of the asker's scope Last.fm calls similar to the seed, in the order the app plays them, the whole list at once
(the app holds it and adds ten at a time; nothing is asked while it plays):

  {"enabled": true, "unavailable": false, "why": null,
   "songs": [{"id": ..., "title": ..., "artist": ..., "album": ..., "albumId": ..., "coverArt": ..., "duration": ...,
              "contentType": ..., "suffix": ..., "samplingRate": ..., "bitDepth": ..., "channelCount": ...,
              "track": ..., "discNumber": ...}, ...]}

Each song as the Library's Shuffle answers one (routes/navidrome.py SHUFFLE_FIELDS), so the app plays it as it plays a
shuffle's. Three things asked at once: track.getSimilar (the seed's first credit and its title as its key reads it -
lastfm.radio_title - limit 100, autocorrect=1), kept under lastfm_kept.track_key; artist.getSimilar by that name, the
artist page's own by-name row (artist_part); and the scope's songs AS THE ASKER (routes/navidrome.py songs_of: the
Shuffle's list, kept ten minutes - `yours` the asker's library, never the store's). lastfm.radio_order() makes the
radio. The Last.fm parts are waited for RADIO_DEADLINE_S at most from the start, and are kept when they come; the
scope's songs are waited for, as the Shuffle waits.

`songs` is [] only for a definite nothing - both Last.fm parts had and nothing of the scope's similar - and null when
the radio couldn't be made - the similar tracks not had (Last.fm down, late, refusing with nothing kept) or the scope's
songs not had (Navidrome failing as the asker, or more songs than SHUFFLE_MAX, which `why` says) - or came to nothing
while a part couldn't be had, with `unavailable`, so the app asks again. radio_order() runs in a thread
(asyncio.to_thread): it keys every song of the scope. The day it is seeded by is UTC's. A session Navidrome ended
is a 401, as everywhere. No key: nothing asked of Last.fm or Navidrome.
"""

import asyncio
import time
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request

from src.api.lastfm_endpoint import lastfm
from src.api.navidrome_endpoint import NavidromeError, SignedOut
from src.config import Config
from src.lastfm import (Answer, NotKnown, Outcome, Refused, Unreachable, answerable, artist_answer, artist_info,
                        first_credit, kept_tracks, match_key, name_key, no_key_answer, no_key_radio, radio_answer,
                        radio_order, radio_title, similar_artists, similar_of, similar_tracks, too_big_why,
                        top_albums, top_tracks, whole)
from src.lastfm_kept import artist_key, kept, track_key
from src.logger import logger
from src.routes import navidrome as navidrome_routes
from src.routes.navidrome import ID_MAX
from src.routes.search_musicbrainz import MBID_PATTERN
from src.users import current_user

router = APIRouter()

NAME_MAX = 200
#? the page's answer waits this long for its parts at most
ARTIST_DEADLINE_S = 4.0
#? how many top tracks are asked for: the fold (lastfm.top_songs) drops repeats, so more than the 10 shown
TOP_TRACKS_ASKED = "50"
#? (2.1.43) how many similar artists and top albums: lastfm.SIMILAR_MAX and TOP_ALBUMS_MAX, as record.py asks
SIMILAR_ASKED = "30"
TOP_ALBUMS_ASKED = "50"

NEEDS_AN_ARTIST = "Give the artist's MusicBrainz id (mbid), their name, or both."

#? each part: its method, what it asks besides the artist, and how its answer is parsed
INFO = ("artist.getinfo", {}, artist_info)
TRACKS = ("artist.gettoptracks", {"limit": TOP_TRACKS_ASKED}, top_tracks)
SIMILAR = ("artist.getsimilar", {"limit": SIMILAR_ASKED}, similar_artists)
ALBUMS = ("artist.gettopalbums", {"limit": TOP_ALBUMS_ASKED}, top_albums)

#? (2.1.44) the radio: how many similar tracks are asked for (lastfm.SIMILAR_TRACKS_MAX, as record.py asks), the
#? most a seed's title or artist may be, and how long the Last.fm parts are waited for
SIMILAR_TRACKS_ASKED = "100"
WORDS_MAX = 500
RADIO_DEADLINE_S = 4.0
NEEDS_A_SONG = "Give the song's id, its title and its artist."
TRACK = ("track.getsimilar", {"limit": SIMILAR_TRACKS_ASKED, "autocorrect": "1"}, similar_tracks)
#? the wall clock the radio's day is read from - the tests' to replace
clock = time.time

#? the parts under way - held, so none is lost before it ends (asyncio keeps only weak references), and so deadwax's
#? stop can cancel those the deadline left running. The descriptions' Last.fm side too (src/routes/describe.py, 2.1.42)
_running: set[asyncio.Task] = set()


def parsed_ask(method: str, params: dict[str, str], parse):
    """The keeping's ask: Last.fm's answer parsed to deadwax's shape - an answer that can't be read Unreachable (never
    kept), anything else as the client said it. The descriptions' too (src/routes/describe.py, 2.1.42)."""
    async def ask() -> Outcome:
        outcome = await lastfm.ask(method, params)
        if not isinstance(outcome, Answer):
            return outcome
        parsed = parse(outcome.body)
        if parsed is None:
            logger.info(f"Last.fm {method}: an answer deadwax couldn't read, so it isn't kept")
            return Unreachable("an answer deadwax couldn't read")
        return Answer(parsed)
    return ask


async def artist_part(store, part, mbid: str | None, name: str | None) -> Outcome:
    """One part of the page: by MusicBrainz id, then - Last.fm not knowing the id - by name. With no name, a "not
    known" by id is answered as it is: the descriptions (src/routes/describe.py) ask for the name only then."""
    method, extra, parse = part
    if mbid:
        outcome = await kept(store, artist_key(method, mbid=mbid), parsed_ask(method, {"mbid": mbid, **extra}, parse))
        if not isinstance(outcome, NotKnown):
            return outcome
    if not name or not name_key(name):
        return NotKnown()
    return await kept(store, artist_key(method, name=name),
                      parsed_ask(method, {"artist": name, "autocorrect": "1", **extra}, parse))


def started(coroutine) -> asyncio.Task:
    """`coroutine` under way, held until it ends and stopped as deadwax stops - so a page's deadline can stop waiting
    for it without cancelling it."""
    task = asyncio.create_task(coroutine)
    _running.add(task)
    task.add_done_callback(_running.discard)
    task.add_done_callback(_ended)
    return task


def _ended(task: asyncio.Task) -> None:
    """A part that raised - it never should: the keeping and the client answer failures - said, never lost."""
    if not task.cancelled() and task.exception() is not None:
        logger.warning(f"Last.fm: a part of a page failed - a fault in deadwax: {type(task.exception()).__name__}")


def _result(task: asyncio.Task, done: set) -> Outcome | None:
    """What a part came to - None when the deadline passed it, Unreachable when it failed."""
    if task not in done:
        return None
    if task.cancelled() or task.exception() is not None:
        return Unreachable("a fault in deadwax")
    return task.result()


async def stop() -> None:
    """deadwax is stopping: the parts still under way cancelled."""
    tasks = list(_running)
    for task in tasks:
        task.cancel()
    for task in tasks:
        try:
            await task
        except (asyncio.CancelledError, Exception):
            pass


@router.get("/artist")
async def lastfm_artist(
    request: Request,
    mbid: str | None = Query(None, pattern=MBID_PATTERN),
    name: str | None = Query(None, min_length=1, max_length=NAME_MAX),
):
    """An artist's Last.fm page, listeners, top songs, similar artists and top albums, for the app's artist page."""
    name = (name or "").strip() or None
    if not mbid and not name:
        raise HTTPException(status_code=422, detail=NEEDS_AN_ARTIST)
    if not Config.lastfm_key():
        return no_key_answer()
    store = getattr(request.app.state, "store", None)
    #? the parts read here, at each ask - never a tuple made once, so a part replaced (the tests') is the one asked
    tasks = [started(artist_part(store, part, mbid, name)) for part in (INFO, TRACKS, SIMILAR, ALBUMS)]
    done, late = await asyncio.wait(set(tasks), timeout=ARTIST_DEADLINE_S)
    if late:
        logger.info(f"Last.fm: {len(late)} part(s) of an artist page not in by {ARTIST_DEADLINE_S:g} s - answered "
                    f"without, and kept when they come")
    outcomes = [_result(task, done) for task in tasks]
    refusal = lastfm.held() or next((part for part in outcomes if isinstance(part, Refused)), None)
    #? answerable(): the last guard - a text the parse let through that UTF-8 can't carry is U+FFFD, never a 500
    return answerable(artist_answer(*outcomes, refusal, mbid=mbid, name=name))


# ----- radio (2.1.44, S5) --------------------------------------------------------------------------------------------

async def track_part(store, artist: str, title: str) -> Outcome:
    """track.getSimilar for the seed - `artist` its first credit, `title` as its key reads it (lastfm.radio_title) -
    through the keeping. Names that fold to nothing are never asked by: every such pair would share one kept row."""
    if not name_key(artist) or not match_key(title):
        return NotKnown()
    method, extra, parse = TRACK
    return await kept(store, track_key(method, artist, title),
                      parsed_ask(method, {"artist": artist, "track": title, **extra}, parse))


async def similar_part(store, artist: str) -> Outcome:
    """artist.getSimilar by the seed's first credit: the artist page's own row by name (artist_part). A name longer
    than an artist page may ask by (NAME_MAX) isn't asked: its key wouldn't leave the row room to be kept."""
    if len(artist) > NAME_MAX:
        return NotKnown()
    return await artist_part(store, SIMILAR, None, artist)


def today() -> str:
    """The UTC day the radio's widening is seeded by, so it is the same all day - UTC's day, on purpose: one day for
    everyone, whatever the server's TZ (for James, in New York, it turns over at 19:00, 20:00 in summer)."""
    return time.strftime("%Y-%m-%d", time.gmtime(clock()))


@router.get("/radio")
async def lastfm_radio(
    request: Request,
    song_id: str = Query(..., min_length=1, max_length=ID_MAX),
    title: str = Query(..., min_length=1, max_length=WORDS_MAX),
    artist: str = Query(..., min_length=1, max_length=WORDS_MAX),
    scope: Literal["yours", "store"] = Query(...),
    user: str = Depends(current_user),
):
    """A radio from a song, for the app's Start Radio and Autoplay: songs of your scope Last.fm calls similar."""
    title, artist = whole(title).strip(), whole(artist).strip()
    if not title or not artist:
        raise HTTPException(status_code=422, detail=NEEDS_A_SONG)
    if not Config.lastfm_key():
        return no_key_radio()
    store = getattr(request.app.state, "store", None)
    credit = first_credit(artist)
    began = time.monotonic()
    tasks = [started(track_part(store, credit, radio_title(title))), started(similar_part(store, credit))]
    songs: list[dict] | None = None
    trouble: str | None = None
    try:
        songs = await navidrome_routes.songs_of(request, user, scope)
    except SignedOut:
        raise
    except NavidromeError as e:
        #? deadwax's own words for whoever runs it - a Navidrome that didn't answer at all is a blip, with none
        trouble = None if e.unreachable else str(e)
    except HTTPException as e:
        if e.status_code != 413:
            raise
        trouble = too_big_why(navidrome_routes.SHUFFLE_MAX)
    except Exception as e:  # noqa: BLE001 - a fault in deadwax is a radio not had, never a 500
        logger.warning(f"Last.fm's radio: the scope's songs couldn't be read - a fault in deadwax: {type(e).__name__}")
    left = max(0.0, RADIO_DEADLINE_S - (time.monotonic() - began))
    done, late = await asyncio.wait(set(tasks), timeout=left)
    if late:
        logger.info(f"Last.fm: {len(late)} part(s) of a radio not in by {RADIO_DEADLINE_S:g} s - answered without, "
                    f"and kept when they come")
    tracks, similar = (_result(task, done) for task in tasks)
    refusal = lastfm.held() or next((part for part in (tracks, similar) if isinstance(part, Refused)), None)
    ordered = None
    if songs is not None and isinstance(tracks, (Answer, NotKnown)):
        listed = kept_tracks(tracks.body.get("tracks")) if isinstance(tracks, Answer) and isinstance(
            tracks.body, dict) else []
        names = [entry["name"] for entry in similar_of(similar.body, None, credit)] if isinstance(
            similar, Answer) and isinstance(similar.body, dict) else []
        #? off the event loop: it keys every song of the scope (0.5 s at 50,000 songs, 2.3 s at SHUFFLE_MAX), which
        #? would stall every other route meanwhile - a stream's included. Pure, and the songs never change in place
        ordered = await asyncio.to_thread(radio_order, songs, listed, names, song_id, title, artist, user, today())
    #? answerable(): the last guard - a text the parse let through that UTF-8 can't carry is U+FFFD, never a 500
    return answerable(radio_answer(tracks, similar, ordered, refusal, trouble))
