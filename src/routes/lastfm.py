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
"""

import asyncio

from fastapi import APIRouter, HTTPException, Query, Request

from src.api.lastfm_endpoint import lastfm
from src.config import Config
from src.lastfm import (Answer, NotKnown, Outcome, Refused, Unreachable, answerable, artist_answer, artist_info,
                        name_key, no_key_answer, similar_artists, top_albums, top_tracks)
from src.lastfm_kept import artist_key, kept
from src.logger import logger
from src.routes.search_musicbrainz import MBID_PATTERN

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
