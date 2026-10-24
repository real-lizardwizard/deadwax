from src.api.musicbrainz_endpoint import MusicBrainzRejected, MusicBrainzUnavailable, raise_for_search
from src.artists import artist_facts, artist_match
from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import JSONResponse, Response
from src.logger import logger
from src.routes.download import ClientGone, unless_abandoned

router = APIRouter()

#? The app's Search's own words (2.0.0-player.55): MusicBrainz shedding searches, said as busy - its body
#? carries `busy: true` beside the words, which the page reads (api/http.ts) - and a quick search
#? MusicBrainz refused as malformed, said as the words, never as an outage.
BUSY_WORDS = "MusicBrainz is busy just now - try again in a moment."
REJECTED_WORDS = "That search couldn't be read - try other words"
UNREACHABLE_WORDS = ("MusicBrainz is unreachable right now, so this search couldn't run. "
                     "This isn't a problem with your search terms - try again shortly.")


def _away(error: MusicBrainzUnavailable):
    """MusicBrainz away, as a quick search answers it: busy (with `busy: true`), or unreachable."""
    if getattr(error, "busy", False):
        return JSONResponse(status_code=503, content={"detail": BUSY_WORDS, "busy": True})
    raise HTTPException(status_code=503, detail=f"{UNREACHABLE_WORDS} ({error})")


async def _quick(request: Request, work):
    """
    A quick search's MusicBrainz work (2.0.0-player.55: /fully_search with `quick`, /songs, /artists), run
    so an abandoned search stops: the page's latestOnly() abort closes the connection, and a request still
    waiting its turn in the rate limiter, or between attempts, is cancelled before it spends one - answered
    204, nobody being there to read it. A 400 is a 422 with words; MusicBrainz away a 503 (busy or not).
    """
    try:
        return await unless_abandoned(request, work)
    except ClientGone:
        return Response(status_code=204)
    except MusicBrainzRejected:
        raise HTTPException(status_code=422, detail=REJECTED_WORDS)
    except MusicBrainzUnavailable as e:
        return _away(e)

#? How far into a search's answers /fully_search pages (2.0.0-player.50): the app's "More from
#? MusicBrainz" asks for the next dozen by offset. A bound, so a page can't send MusicBrainz - rate
#? limited, often away - deep into a relevance tail nobody reads; ui/src/lib/searchResults.ts keeps
#? the same number, and says so when a search reaches it.
FULLY_SEARCH_OFFSET_MAX = 1000


@router.get("/fully_search")
async def fully_search(
    request: Request,
    query: str,
    limit: int = 5,
    #? Defaults True so the search view is unaffected - it renders the best group's releases
    #? straight away and would break without them. The metadata editor passes False: it ranks
    #? the groups itself and fetches the ones it wants, so eagerly walking the first group's
    #? full release list (five requests and 1.4 MB for a big album) was spent on a payload it
    #? never looked at.
    releases: bool = True,
    #? Where in MusicBrainz's answers this page starts (2.0.0-player.50, the app's "More from
    #? MusicBrainz"). 0 - the first page - is asked as it always was, with no offset sent, so every
    #? existing search keeps its request and its cache entry.
    offset: int = Query(0, ge=0, le=FULLY_SEARCH_OFFSET_MAX),
    #? (2.0.0-player.55) the app's Search alone sends it: a search's patience (three attempts, not ten), a
    #? 400 said as words to try others, MusicBrainz shedding said as busy, and an abandoned search stopped.
    #? Not sent to MusicBrainz, so the request and its cache entry are the same; the metadata editor
    #? sends none (as the main page sent none) and is answered exactly as before.
    quick: bool = Query(False),
):
    if quick:
        try:
            mb_client = request.app.state.musicbrainz_client
            return await _quick(request, mb_client.fully_search(query, limit, include_releases=releases, offset=offset, quick=True))
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Exception in /fully_search endpoint: {e}")
            raise HTTPException(status_code=500, detail=f"Error searching MusicBrainz: {e}")

    try:
        mb_client = request.app.state.musicbrainz_client
        search_result = await mb_client.fully_search(query, limit, include_releases=releases, offset=offset)
        return search_result

    except MusicBrainzUnavailable as e:
        #? 503 not 500: nothing is wrong with the request, the upstream is just down
        raise HTTPException(
            status_code=503,
            detail=f"MusicBrainz is unreachable right now, so this search couldn't run. "
                   f"This isn't a problem with your search terms - try again shortly. ({e})",
        )

    except Exception as e:
        logger.error(f"Exception in /fully_search endpoint: {e}")
        raise HTTPException(status_code=500, detail=f"Error searching MusicBrainz: {e}")


#? A song search's bounds (2.0.0-player.53). The app asks SONG_SEARCH_LIMIT recordings a page
#? (ui/src/lib/songs.ts keeps the number); MusicBrainz serves at most 100 to one search page, so a
#? limit past that is refused here rather than quietly cut short there. Its paging goes no further
#? than the album search's - one bound for both halves of the app's MusicBrainz search - and the query
#? no longer than the app's box (200 characters) read as a title and an artist, quoted, can make it.
SONG_SEARCH_LIMIT = 25
SONG_SEARCH_LIMIT_MAX = 100
SONG_SEARCH_OFFSET_MAX = FULLY_SEARCH_OFFSET_MAX
SONG_SEARCH_QUERY_MAX = 1000


@router.get("/songs")
async def songs(
    request: Request,
    query: str = Query(..., min_length=1, max_length=SONG_SEARCH_QUERY_MAX),
    limit: int = Query(SONG_SEARCH_LIMIT, ge=1, le=SONG_SEARCH_LIMIT_MAX),
    offset: int = Query(0, ge=0, le=SONG_SEARCH_OFFSET_MAX),
):
    """
    A SONG search (2.0.0-player.53, step 7 of the multi-user plan): MusicBrainz's recordings matching
    the query - the app's box read as the album search reads it (`recording:"..." AND (artist:"..." OR
    artistname:"...")` for a title beside an artist you have, else the words typed) - for "Songs on
    MusicBrainz" in its Search tab, where a song found shows the albums it is on.

    ONE request a page, and the least that answers: a recording search's answer already carries each
    recording's releases with their release group (title, primary and secondary types), status, date,
    country and the track - so the albums a song is on come in the same answer, with nothing asked per
    album. Cached in the ResponseCache like every MusicBrainz success (a failure never is); paged by
    `offset` as /fully_search is, the first page asked with no offset. MusicBrainz away is a 503 that
    says so - never an empty answer that reads as a song nobody recorded.
    """
    if not query.strip():
        raise HTTPException(status_code=422, detail="A song search needs some words to search for.")

    #? (2.0.0-player.55) always a quick search: a search's patience, a 400 a 422 with words (it was a 503),
    #? busy said, an abandoned search stopped - see _quick
    try:
        mb_client = request.app.state.musicbrainz_client
        return await _quick(request, mb_client.search_recordings(query, limit, offset=offset, quick=True))

    except HTTPException:
        raise

    except Exception as e:
        logger.error(f"Exception in /songs endpoint: {e}")
        raise HTTPException(status_code=500, detail=f"Error searching MusicBrainz for songs: {e}")


#? An artist search's bounds (2.0.0-player.55, the app's Search). ARTIST_SEARCH_LIMIT is the app's own page
#? (ui/src/lib/searchList.ts keeps the number); MusicBrainz serves at most 100 to a search page; the paging
#? goes no further than the other two searches'; the name no longer than the app's box.
ARTIST_SEARCH_LIMIT = 10
ARTIST_SEARCH_LIMIT_MAX = 100
ARTIST_SEARCH_OFFSET_MAX = FULLY_SEARCH_OFFSET_MAX
ARTIST_SEARCH_NAME_MAX = 200


@router.get("/artists")
async def artists(
    request: Request,
    name: str = Query(..., min_length=1, max_length=ARTIST_SEARCH_NAME_MAX),
    limit: int = Query(ARTIST_SEARCH_LIMIT, ge=1, le=ARTIST_SEARCH_LIMIT_MAX),
    offset: int = Query(0, ge=0, le=ARTIST_SEARCH_OFFSET_MAX),
):
    """
    Artists on MusicBrainz going by a name (2.0.0-player.55, "search like Apple Music"): the app's Search
    lists them under Artists, beside the library's own. Before this no user could search MusicBrainz for an
    artist - the only artist search was the admin route POST /library/artist/search, the main page's picker.

    `name` is words, never a query: it is asked as artist_query(name) - `(artist:"X" OR alias:"X")`, quoted
    and escaped - so an alias finds the artist ("Kanye West" finds Ye) and nothing typed can change the
    query or make MusicBrainz refuse it. Each match in the admin route's shape (artist_match): mbid, name,
    disambiguation, country, type, score and `matched_as`. Always a quick search (_quick); cached in the
    ResponseCache per name, limit and offset, successes only - an offset sent only past the first page. A
    failed or shapeless answer is a 503 with words, never an empty list.
    """
    if not name.strip():
        raise HTTPException(status_code=422, detail="An artist search needs a name to search for.")

    async def search():
        found = await request.app.state.musicbrainz_client.search_artists(name, limit=limit, offset=offset, quick=True)
        #? request_with_retries answers a failure with an error dict rather than raising
        if not isinstance(found, dict) or found.get("status") == "failed" or not isinstance(found.get("artists"), list):
            raise_for_search(found if isinstance(found, dict) else {}, True)
        count = found.get("count")
        return {
            "matches": [artist_match(artist, name) for artist in found["artists"] if isinstance(artist, dict) and artist.get("id")],
            "count": count if isinstance(count, int) and not isinstance(count, bool) else None,
        }

    try:
        return await _quick(request, search())

    except HTTPException:
        raise

    except Exception as e:
        logger.error(f"Exception in /artists endpoint: {e}")
        raise HTTPException(status_code=500, detail=f"Error searching MusicBrainz for artists: {e}")


#? How long the words a saved search takes may be: the app's box (ARTIST_SEARCH_NAME_MAX, its 200 characters)
SAVED_SEARCH_WORDS_MAX = ARTIST_SEARCH_NAME_MAX


@router.get("/saved")
async def saved(
    request: Request,
    words: str = Query(..., min_length=1, max_length=SAVED_SEARCH_WORDS_MAX),
):
    """
    Search what's saved (2.0.0-player.56): the artists, albums and songs MusicBrainz's saved answers hold that
    match the words typed - anything you have come across before, under any words, in milliseconds, MusicBrainz
    asked nothing (src/saved_index.py says what is in the index and how it matches: every word, the last as a
    prefix, accents folded, names and titles over credits).

    The app's Search asks it beside MusicBrainz's own searches and draws what it finds first, MusicBrainz's answer
    adding what it found below. Each kind in the shape of the route the app already draws it from - `artists` as
    /artists, `albums` as /fully_search, `songs` as /songs - bounded to the app's page of each (SAVED_ARTISTS 10,
    SAVED_ALBUMS 12, SAVED_SONGS 25 recordings) - and `credited`, as `albums`: the albums credited to exactly these
    words, in studio order (SAVED_CREDITED 50), which is what the app draws when it reads the words as an artist. Shared by everyone signed in: MusicBrainz's data is nobody's own,
    and nothing in the index says who looked it up.

    `available` is false when nothing could be searched - saving off (MUSICBRAINZ_CACHE_MB 0), no file yet, an
    index this SQLite can't keep, or one slow or broken (given up within a second, read off the event loop) -
    never an error: Search then shows MusicBrainz's answer alone, as before.
    """
    empty = {"artists": {"matches": [], "count": 0}, "albums": {"release-groups": [], "count": 0},
             "songs": {"recordings": [], "count": 0}, "credited": {"release-groups": [], "count": 0}}
    if not words.strip():
        return {**empty, "available": False}
    disk = getattr(getattr(request.app.state, "musicbrainz_client", None), "cache", None)
    disk = getattr(disk, "disk", None)
    if disk is None:
        return {**empty, "available": False}
    found = await disk.search(words.strip())
    if found is None:
        return {**empty, "available": False}
    return {**found, "available": True}


#? The primary types MusicBrainz browse accepts. Validated here rather than passed straight
#? through: an unrecognised value makes the whole browse return nothing, which would look
#? exactly like an artist with no records.
DISCOGRAPHY_TYPES = {"album", "ep", "single", "broadcast", "other"}


@router.get("/discography")
async def discography(
    request: Request,
    artist_mbid: str,
    #? Comma-separated, e.g. "album,ep". Empty means every type.
    types: str = "",
    #? Drops live albums, compilations, demos and the like. Applied after the browse, which
    #? is sound here because the browse is complete - see the client's note.
    studio_only: bool = False,
):
    """
    Every release group credited to one artist.

    A BROWSE, deliberately, not a search. A search answers in relevance order and spends its
    limit on whatever matched, so sorting those results by year gives you the oldest of the N
    most relevant - not the artist's earliest work. Only a browse can answer "everything this
    artist released, in order" without lying about completeness.
    """
    requested = [t.strip().lower() for t in types.split(",") if t.strip()]
    unknown = [t for t in requested if t not in DISCOGRAPHY_TYPES]

    if unknown:
        raise HTTPException(
            status_code=400,
            detail=(
                f"unknown release type(s): {', '.join(unknown)}. "
                f"Expected any of {', '.join(sorted(DISCOGRAPHY_TYPES))}."
            ),
        )

    try:
        mb_client = request.app.state.musicbrainz_client
        return await mb_client.get_artist_release_groups(
            artist_mbid, requested or None, studio_only=studio_only
        )

    except MusicBrainzUnavailable as e:
        #? 503 not 500: nothing is wrong with the request, the upstream is just down
        raise HTTPException(
            status_code=503,
            detail=f"MusicBrainz is unreachable right now, so that discography couldn't be "
                   f"loaded. Try again shortly. ({e})",
        )

    except Exception as e:
        logger.error(f"Exception in /discography endpoint: {e}")
        raise HTTPException(status_code=500, detail=f"Error browsing MusicBrainz: {e}")


@router.get("/releases")
async def get_releases(
    request: Request,
    release_group_mbid: str,
    #? Defaults True: the download flow matches Soulseek folders against a release's real
    #? tracklist, and losing that quietly would gut the matching rather than break it loudly.
    #? False is for choosing BETWEEN pressings, which needs format, country, catalogue number
    #? and track count - all of which survive - but not 58 tracklists. See get_release.
    tracks: bool = True,
):
    try:
        mb_client = request.app.state.musicbrainz_client
        releases = await mb_client.get_releases(release_group_mbid, with_tracks=tracks)
        #? `problem` passed on (2.0.0-player.13): get_releases sets it when MusicBrainz failed part
        #? way, and dropping it handed the page a short or empty list that read as the album's whole
        #? set of pressings - exactly the confusion get_releases' own note is about
        return {"id": release_group_mbid, "releases": releases["releases"], "problem": releases.get("problem")}

    except Exception as e:
        logger.error(f"Exception in /releases endpoint: {e}")
        raise HTTPException(status_code=500, detail=f"Error retrieving releases from MusicBrainz: {e}")


#? A MusicBrainz id as MusicBrainz writes one. A cold link the app opens carries it in the
#? address, and anything else is refused here rather than spent on a request MusicBrainz rejects.
MBID_PATTERN = r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"


@router.get("/release_group")
async def release_group(
    request: Request,
    release_group_mbid: str = Query(..., pattern=MBID_PATTERN),
):
    """
    Every pressing of one album WITH its tracklist, for the app's album-you-don't-have page
    (2.0.0-player.13): the pressing dropdown defaults to the group's most common tracklist and
    shows what each pressing changes about it, which needs every pressing's tracks - the costly
    listing (`with_tracks`), up to five requests and 1.4 MB for a big group.

    Successes are cached for the process like every MusicBrainz answer (ResponseCache), so a
    second look costs nothing; a failure never is. `problem` says MusicBrainz failed - part way
    through a long list, or before the first page - and the page then offers to ask again rather
    than drawing a partial list as the album's pressings.

    Each release carries its `release-group` too (`with_group`), so a page opened from a link or a
    reload - with no group handed over by Search - still says the album's title, kind and year.
    """
    try:
        mb_client = request.app.state.musicbrainz_client
        releases = await mb_client.get_releases(release_group_mbid, log=False, with_tracks=True, with_group=True)
        return {"id": release_group_mbid, "releases": releases["releases"], "problem": releases.get("problem")}

    except Exception as e:
        logger.error(f"Exception in /release_group endpoint: {e}")
        raise HTTPException(status_code=500, detail=f"Error retrieving pressings from MusicBrainz: {e}")


#? What an artist's facts carry to the app - who they are, in full: since 2.0.0-player.45 their links
#? (told apart, artists._tell_apart) and their line-up too, which the light facts of 2.0.0-player.17
#? left out as a build trim. They come in the very answer get_artist already asks for - its `inc`
#? has the relations - so the whole set costs no request more. No pictures: those are three hosts
#? deep, and the artist images picker's to ask for.
ARTIST_FACT_FIELDS = ("mbid", "name", "sort_name", "type", "disambiguation", "country", "area",
                      "begin_area", "began", "ended_on", "ended", "genres", "aliases", "links", "members")


@router.get("/artist")
async def artist(
    request: Request,
    mbid: str = Query(..., pattern=MBID_PATTERN),
):
    """
    Who an artist is, by their MusicBrainz id (2.0.0-player.17; in full since 2.0.0-player.45):
    type, where they're from, when they began and ended, their genres, the names they also go by,
    their links and their line-up, as artists.artist_facts shapes them. For the app's artist page
    (the line under their name, its About and its Line-up) and Info > About's artist card ("Group ·
    Bristol · 1991 to now").

    One request (get_artist, the main page's artist page's own, so the two share a cache entry),
    cached for the process like every MusicBrainz answer - SUCCESSES only: request_with_retries
    stores nothing else, and a failure here is a 503 saying so, never facts made of an error.
    """
    try:
        found = await request.app.state.musicbrainz_client.get_artist(mbid)
    except MusicBrainzUnavailable as e:
        raise HTTPException(status_code=503, detail=f"MusicBrainz is unreachable right now ({e})")

    #? request_with_retries answers a failure with an error dict rather than raising
    if not isinstance(found, dict) or found.get("status") == "failed" or "error" in found or not found.get("id"):
        problem = found.get("error") if isinstance(found, dict) else None
        raise HTTPException(status_code=503, detail=f"MusicBrainz is unreachable right now ({problem or 'no answer'})")

    facts = artist_facts(found)
    return {field: facts[field] for field in ARTIST_FACT_FIELDS}


@router.get("/release")
async def get_release(
    request: Request,
    release_mbid: str,
):
    """
    One release, with its tracklist. The other half of `/releases?tracks=false`.

    Costs one request for the pressing actually chosen, rather than carrying the contents of
    every pressing in the group on the chance that one of them gets picked.
    """
    try:
        mb_client = request.app.state.musicbrainz_client
        release = await mb_client.get_release(release_mbid)

        #? request_with_retries answers with an error dict rather than raising, and handing that
        #? back as a release would produce an apply with no tracklist at all - which writes
        #? nothing and looks like the edit silently did nothing
        if release.get("status") == "failed" or not release.get("id"):
            raise MusicBrainzUnavailable(release.get("error", "unknown error"))

        return release

    except MusicBrainzUnavailable as e:
        raise HTTPException(
            status_code=503,
            detail=f"MusicBrainz is unreachable right now, so that release couldn't be "
                   f"loaded. This isn't a problem with your search terms. ({e})",
        )

    except Exception as e:
        logger.error(f"Exception in /release endpoint: {e}")
        raise HTTPException(status_code=500, detail=f"Error retrieving that release from MusicBrainz: {e}")


@router.get("/ping")
async def ping(request: Request):
    try:
        mb_client = request.app.state.musicbrainz_client
        ping_response = await mb_client.ping()
        return ping_response
    except Exception as e:
        logger.error(f"Exception in /ping endpoint: {e}")
        raise HTTPException(status_code=500, detail=f"Error pinging MusicBrainz: {e}")

