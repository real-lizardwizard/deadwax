from src.api.musicbrainz_endpoint import MusicBrainzUnavailable
from src.artists import artist_facts
from fastapi import APIRouter, HTTPException, Query, Request
from src.logger import logger

router = APIRouter()

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
):
    try:
        mb_client = request.app.state.musicbrainz_client
        search_result = await mb_client.fully_search(query, limit, include_releases=releases)
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


#? What an artist's facts carry to the app - who they are, and nothing a page of theirs would need
#? more requests to show: no pictures (those are the main page's artist page, and three hosts deep),
#? no links or members.
ARTIST_FACT_FIELDS = ("mbid", "name", "sort_name", "type", "disambiguation", "country", "area",
                      "begin_area", "began", "ended_on", "ended", "genres", "aliases")


@router.get("/artist")
async def artist(
    request: Request,
    mbid: str = Query(..., pattern=MBID_PATTERN),
):
    """
    Who an artist is, by their MusicBrainz id - the LIGHT facts (2.0.0-player.17): type, where
    they're from, when they began and ended, their genres and the names they also go by, as
    artists.artist_facts shapes them. For the app's artist page (under their name) and Info > About's
    artist card ("Group · Bristol · 1991 to now").

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

