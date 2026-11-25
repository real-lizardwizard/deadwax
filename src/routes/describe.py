"""
A short description of an artist or an album (2.0.13) - `GET /deadwax/describe/artist` and
`GET /deadwax/describe/album`, a user's routes (tests/test_logins.py ROUTES), for the app's artist page, album
page and the album you don't have. src/descriptions.py says where the words come from and why.

Each takes `mbid` (the artist's MusicBrainz id, or the album's RELEASE GROUP id) and/or `navidrome_id`
(Navidrome's artist or album id, at most ID_MAX letters, only ever Navidrome's `id` parameter) - at least one,
a 422 otherwise - and answers `{text, source, url, subtitle, unavailable}`: the paragraph Navidrome's own
(getArtistInfo2 / getAlbumInfo2, asked AS THE SIGNED-IN PERSON through client_for, `source` "lastfm") when it
has one, else Wikipedia's when the MusicBrainz id leads to an English page; the subtitle Wikidata's English
one-line description of that same item, whichever the paragraph is; every field null when there is none.
Navidrome and the Wikipedia side are asked at once, so the slower sets the pace, not the two in turn.

WITH A LASTFM_API_KEY (2.1.42, S3 - notes/lastfm.md): a third side, Last.fm's own words (lastfm_side), asked at
once with the other two, and the paragraph Last.fm's, else Wikipedia's, else Navidrome's. `source` is "lastfm" for
Last.fm's as for Navidrome's (its link says only where it goes: "More on Last.fm"), so the answer's shape and the
app don't change. The Wikipedia side and the Last.fm side share one MusicBrainz lookup, made once between them
(_once). Without a key the route is as it was - the same two sides, the same order, the same lookups.

Always a 200: a page with no description draws nothing, and a page whose description couldn't be had draws
nothing either - deadwax's own log (the container's output) says why, at info level, never the event log a
listener's page could show. `unavailable` says a source couldn't be asked just now, so the app keeps that
answer only a moment rather than for its session (lib/describe.ts).

KEPT: the Wikipedia side's answers - Wikipedia's words and page, and Wikidata's subtitle - in the database
(store.py `descriptions`, src/descriptions.py's freshness - a found one a month, "there is none" three days),
shared by everyone; a kept one too old is asked again, and still answered when asking fails. Wikipedia's words
are asked and kept even when Navidrome has its own, so the row is whole and stands in when Navidrome can't
answer. Never kept: a failure (MusicBrainz, Wikidata or Wikipedia away), and Navidrome's answers - Navidrome
keeps those itself (core/external/provider.go: fetched once, refreshed in the background after its TTL), and
they are asked as each person, whose access is Navidrome's to judge.

The MusicBrainz lookups are the ones deadwax already makes or the least that answers: an artist's is
get_artist, the artist page's facts' own (so it costs nothing once the facts have come - the page asks for its
description after them); an album's is its release group with url-rels alone (get_release_group_urls), kept
on disk a month like every lookup. An id MusicBrainz has nothing at (a 404 - a bad tag, a merged-away entity)
is a definite "none", kept: it is asked once, not on every visit. With a Last.fm key an album's lookup carries its
artist credit too (Last.fm is asked by the album's names) - one lookup still, under a cache key of its own.
"""

import asyncio
import time

from fastapi import APIRouter, HTTPException, Query, Request

from src.api.musicbrainz_endpoint import MusicBrainzUnavailable
from src.api.navidrome_endpoint import NavidromeError, SignedOut, client_for
from src.api.wikipedia_endpoint import Unreachable, wikipedia
from src.artists import credit_name
from src.config import Config
from src.descriptions import (answer_lastfm_first, answer_of, english_description, enwiki_title, found_in,
                              from_lastfm, from_navidrome, from_summary, is_fresh, wikidata_entity, wikipedia_relation)
from src.lastfm import Answer, NotKnown, album_info, answerable
from src.lastfm_kept import kept, release_group_key
from src.logger import logger
from src.routes.lastfm import INFO, NAME_MAX, artist_part, parsed_ask, started
from src.routes.navidrome import ID_MAX
from src.routes.search_musicbrainz import MBID_PATTERN

router = APIRouter()

NEEDS_AN_ID = "Give the MusicBrainz id (mbid), Navidrome's id (navidrome_id), or both."

#? Navidrome's call for each kind, and the field its words come in
NAVIDROME_CALLS = {"artist": ("getArtistInfo2", "biography"), "album": ("getAlbumInfo2", "notes")}
#? Subsonic's "data not found" - Navidrome has no such artist or album: a definite no, not a failure
NOT_FOUND = 70
#? (2.1.42) Last.fm's album method, asked by the album's title and its artist's name as record.py records it
ALBUM_INFO = "album.getinfo"
#? (2.1.42) the longest the Last.fm side is waited for - S2's ARTIST_DEADLINE_S, the app's artist page's: a Last.fm that
#? takes the connection but doesn't answer holds the words back no longer, while Wikipedia's are ready
LASTFM_DEADLINE_S = 4.0


async def _entity(request: Request, kind: str, mbid: str, credits: bool = False) -> dict:
    """The MusicBrainz artist (get_artist) or release group (url-rels alone; with `credits`, its artist credit
    too - 2.1.42, for Last.fm) - {} for an id MusicBrainz has nothing at (a 404: "none", kept), raising
    Unreachable for any other failure."""
    client = request.app.state.musicbrainz_client
    try:
        found = await (client.get_artist(mbid) if kind == "artist"
                       else client.get_release_group_urls(mbid, credits=True) if credits
                       else client.get_release_group_urls(mbid))
    except MusicBrainzUnavailable as e:
        raise Unreachable(f"MusicBrainz couldn't be reached ({e})") from e
    #? request_with_retries answers a failure with an error dict rather than raising
    if isinstance(found, dict) and found.get("status") == "failed" and found.get("code") == 404:
        return {}
    if not isinstance(found, dict) or found.get("status") == "failed" or "error" in found or not found.get("id"):
        problem = found.get("error") if isinstance(found, dict) else None
        raise Unreachable(f"MusicBrainz didn't answer ({problem or 'no answer'})")
    return found


async def _ask_wikipedia(request: Request, kind: str, mbid: str, lookup=None) -> dict:
    """The Wikipedia side, by way of MusicBrainz and Wikidata: {text, url, subtitle}, each None when there is
    none - or Unreachable when any of the three couldn't say. `lookup` (2.1.42, with a Last.fm key) is the
    MusicBrainz lookup it shares with the Last.fm side, made once between them."""
    relations = (await (lookup() if lookup is not None else _entity(request, kind, mbid))).get("relations") or []
    title = subtitle = None
    item = wikidata_entity(relations)
    if item:
        entity = await wikipedia.entity(item)
        title, subtitle = enwiki_title(entity, item), english_description(entity, item)
    #? an English `wikipedia` link of MusicBrainz's own, where Wikidata has none
    title = title or wikipedia_relation(relations)
    found = from_summary(await wikipedia.summary(title), title) if title else None
    return {"text": found["text"] if found else None, "url": found["url"] if found else None, "subtitle": subtitle}


async def wikipedia_side(request: Request, kind: str, mbid: str, lookup=None) -> tuple[dict | None, bool]:
    """The Wikipedia side - kept, or asked and kept - and whether asking failed just now."""
    store = getattr(request.app.state, "store", None)
    key = f"{kind}:{mbid}"
    kept = await store.description_get(key) if store is not None else None
    now = time.time()
    if kept and is_fresh(found_in(kept), float(kept.get("fetched_at") or 0), now):
        return kept, False

    try:
        found = await (_ask_wikipedia(request, kind, mbid, lookup) if lookup is not None
                       else _ask_wikipedia(request, kind, mbid))
    except Unreachable as e:
        logger.info(f"no description for that {kind} just now - {e}")
        #? an old description still answers while asking fails; an old "none" is still none
        return (kept if found_in(kept) else None), True

    if store is not None:
        await store.description_put(key, found["text"], found["url"], now, found["subtitle"])
    return found, False


async def navidrome_side(request: Request, kind: str, navidrome_id: str) -> tuple[dict | None, bool]:
    """Navidrome's own words for the artist or album, asked as the signed-in person - or None - and whether
    asking failed (anything but Navidrome saying it has no such thing)."""
    endpoint, field = NAVIDROME_CALLS[kind]
    params: dict = {"id": navidrome_id}
    if kind == "artist":
        #? no similar artists in the answer - only the biography is read
        params["count"] = 0
    try:
        body = await client_for(request).call(endpoint, params)
    except SignedOut:
        raise
    except NavidromeError as e:
        logger.debug(f"Navidrome had no description of that {kind}: {e}")
        return None, getattr(e, "code", None) != NOT_FOUND
    return from_navidrome(body, field), False


async def lastfm_side(request: Request, kind: str, mbid: str, lookup) -> tuple[dict | None, bool]:
    """
    (2.1.42) Last.fm's own words for the artist or album - kept, or asked and kept (src/lastfm_kept.py, a week,
    shared with the app's artist page) - or None, and whether asking failed just now (a definite "not known"
    isn't a failure; Last.fm down, limiting or refusing the key is, as is MusicBrainz failing the lookup the names
    come from).

      - An artist: artist.getInfo by MusicBrainz id - the very row GET /deadwax/lastfm/artist keeps - and, Last.fm
        not knowing the id, by the name MusicBrainz gives it (get_artist: the Wikipedia side's own lookup, `lookup`,
        so it costs nothing more).
      - An album: album.getInfo by its release group's title and its artist credit's name, autocorrect=1, from
        that same lookup asked with its artist credit (get_release_group_urls(credits=True)) - and KEPT UNDER THE
        RELEASE GROUP's id (release_group_key), never under the names: names fold alike for different albums
        ("Fearless" and "Fearless (Taylor's Version)"). Never asked by Last.fm's album mbid, which isn't a release
        group's. A title or artist that is empty or longer than NAME_MAX isn't asked.
    """
    store = getattr(request.app.state, "store", None)
    try:
        if kind == "artist":
            outcome = await artist_part(store, INFO, mbid, None)
            if isinstance(outcome, NotKnown):
                name = (await lookup()).get("name")
                name = name.strip() if isinstance(name, str) else ""
                #? the artist page's own bound on a name (S2's kept getInfo row fits 32 KB under it)
                outcome = await artist_part(store, INFO, None, name if len(name) <= NAME_MAX else None)
        else:
            outcome = await _album(store, mbid, await lookup())
    except Unreachable as e:
        logger.info(f"no Last.fm description for that {kind} just now - {e}")
        return None, True
    if isinstance(outcome, Answer):
        return from_lastfm(outcome.body, kind), False
    return None, not isinstance(outcome, NotKnown)


async def _album(store, mbid: str, group: dict):
    """album.getInfo for a release group MusicBrainz answered - asked by its names, kept under its id."""
    title = group.get("title")
    title = title.strip() if isinstance(title, str) else ""
    artist = credit_name(group.get("artist-credit"))
    if not all(name and len(name) <= NAME_MAX for name in (title, artist)):
        return NotKnown()
    return await kept(store, release_group_key(ALBUM_INFO, mbid),
                      parsed_ask(ALBUM_INFO, {"artist": artist, "album": title, "autocorrect": "1"}, album_info))


async def by_the_deadline(side) -> tuple[dict | None, bool]:
    """
    (2.1.42) The Last.fm side, waited for LASTFM_DEADLINE_S at most. Past it: none, and `unavailable`, so the app
    asks again soon - and the side goes on, never cancelled by the page (held, as S2's late parts are, and stopped
    with them as deadwax stops), so what Last.fm answers is kept when it comes and the next visit has it. A side that
    raised (a fault in deadwax - it never should) is a failure, said in the log, not the description's end.
    """
    task = started(side)
    done, _ = await asyncio.wait({task}, timeout=LASTFM_DEADLINE_S)
    if not done:
        logger.info(f"Last.fm: a description not in by {LASTFM_DEADLINE_S:g} s - answered without, and kept when "
                    f"it comes")
        return None, True
    if task.cancelled() or task.exception() is not None:
        return None, True
    return task.result()


def _once(ask):
    """A lookup the sides share (2.1.42): made by the first side that needs it, never by none, and never twice -
    asked at once, each side would take a turn of MusicBrainz's limiter for the one answer."""
    task: asyncio.Task | None = None

    async def lookup() -> dict:
        nonlocal task
        if task is None:
            task = asyncio.ensure_future(ask())
        return await task
    return lookup


async def _nothing() -> tuple[None, bool]:
    return None, False


async def describe(request: Request, kind: str, mbid: str | None, navidrome_id: str | None) -> dict:
    if not mbid and not navidrome_id:
        raise HTTPException(status_code=422, detail=NEEDS_AN_ID)
    if Config.lastfm_key():
        return await _described_lastfm_first(request, kind, mbid, navidrome_id)
    #? both at once - Navidrome's first answer can be slow (it asks its agents then), and so can MusicBrainz's
    (said, said_failed), (row, row_failed) = await asyncio.gather(
        navidrome_side(request, kind, navidrome_id) if navidrome_id else _nothing(),
        wikipedia_side(request, kind, mbid) if mbid else _nothing(),
    )
    return answer_of(row, said, unavailable=said_failed or row_failed)


async def _described_lastfm_first(request: Request, kind: str, mbid: str | None, navidrome_id: str | None) -> dict:
    """With a LASTFM_API_KEY (2.1.42, S3): the three sides at once - Last.fm, Navidrome and the Wikipedia side, the
    last two as without a key - and Last.fm's words first, then Wikipedia's, then Navidrome's; the subtitle
    Wikidata's as ever. `unavailable` if any side failed, Last.fm's included - a Last.fm that refuses the key, is
    away or is still answering at LASTFM_DEADLINE_S only ever leaves the others' words. An id of Navidrome's alone has
    no Last.fm side: it is asked by MusicBrainz's id (an artist) or the names MusicBrainz gives (an album)."""
    lookup = _once(lambda: _entity(request, kind, mbid, credits=kind == "album")) if mbid else None
    (said, said_failed), (row, row_failed), (heard, heard_failed) = await asyncio.gather(
        navidrome_side(request, kind, navidrome_id) if navidrome_id else _nothing(),
        wikipedia_side(request, kind, mbid, lookup) if mbid else _nothing(),
        by_the_deadline(lastfm_side(request, kind, mbid, lookup)) if mbid else _nothing(),
    )
    return answer_lastfm_first(heard, row, said, unavailable=said_failed or row_failed or heard_failed)


@router.get("/artist")
async def describe_artist(
    request: Request,
    mbid: str | None = Query(None, pattern=MBID_PATTERN),
    navidrome_id: str | None = Query(None, min_length=1, max_length=ID_MAX),
):
    """An artist's description: Navidrome's biography of them, else Wikipedia's by their MusicBrainz id - with a
    Last.fm key, Last.fm's bio of them first and Navidrome's last - and Wikidata's subtitle."""
    #? answerable(): a text no UTF-8 carries (a lone surrogate, in any side's words) is U+FFFD, never a 500 (2.1.43)
    return answerable(await describe(request, "artist", mbid, navidrome_id))


@router.get("/album")
async def describe_album(
    request: Request,
    mbid: str | None = Query(None, pattern=MBID_PATTERN),
    navidrome_id: str | None = Query(None, min_length=1, max_length=ID_MAX),
):
    """An album's description: Navidrome's notes, else Wikipedia's by its release group's MusicBrainz id - with a
    Last.fm key, Last.fm's wiki of it first and Navidrome's last - and Wikidata's subtitle."""
    return answerable(await describe(request, "album", mbid, navidrome_id))
