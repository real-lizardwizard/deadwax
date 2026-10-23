import asyncio

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field

from src.api.musicbrainz_endpoint import MusicBrainzUnavailable
from src.api.slskd_endpoint import SlskdSearchRefused, build_search_query
from src.artists import former_names
from src.config import Config, search_timeout_seconds
from src.logger import logger
from src.matching import rank_candidates
from src.organizer import remove_incomplete_downloads
from src.poller import (NOT_FILED_PATTERNS, job_lock_key, job_outcome, retry_next_peer, retry_same_peer, retryable,
                        tidy_cancelled_later, tidy_cancelled_transfers, untried_alternatives)
from src.store import (CLEARABLE_STATUSES, OPEN_STATUSES, RETRYABLE_STATUSES,
                       index_transfers_by_user, summarize_transfers)
from src.store_index import (FILING_STATUSES, already_have, coming_now, describe_job, filing_folder, held_copy,
                             in_flight, is_whole, other_pressings, release_lock)
from src import library_ledger
from src.auth import BREAK_GLASS_USER
from src.users import can, current_user, require

router = APIRouter()


async def _everyone(request: Request, user: str | None) -> bool:
    """Whether `user` may see and act on everyone's downloads (Everyone's downloads) - asked in a worker thread:
    for an ordinary person the permissions table may be read from SQLite (once a minute at most, after a failed
    read), which must never hold up the event loop and every stream on it (2.0.0-player.61 review)."""
    return bool(user) and await asyncio.to_thread(can, request, user, "downloads")


class Track(BaseModel):
    #? the RUNNING number across every disc - what the matcher keys on and files are named after
    position: int | None = None
    title: str = ""
    length_ms: int | None = None
    #? Which disc, and where on it. Declared rather than left to ride along because pydantic
    #? drops undeclared fields without a word, and a multi-disc download would then be tagged
    #? 1..20 with no disc numbers - quietly unlike the same album corrected in the editor.
    disc: int | None = None
    disc_position: int | None = None
    #? The track's OWN credit, where it differs from the release's - a split, a compilation, a
    #? guest spot. Declared for the same reason disc is: pydantic drops what it was not told
    #? about without a word, so an undeclared artist would arrive from the browser, vanish
    #? here, and every track of a compilation would be filed under the release's artist with
    #? nothing anywhere saying why.
    artist: str | None = None
    artist_mbids: list[str] = Field(default_factory=list)
    #? The title of this track's DISC - MusicBrainz's medium title, written as DISCSUBTITLE
    #? (v1.1.0). Declared for the same reason again: undeclared, it would vanish here and the
    #? download would file with no disc titles while the editor's apply wrote them.
    disc_title: str | None = None
    #? On a video medium (DVD-Video, Blu-ray) or a video recording: a track that never arrives as
    #? an audio file, so the "already have it" checks leave it out (store_index.audio_tracks).
    #? Declared for the reason everything above is - undeclared, a CD+DVD pressing held whole
    #? could never read as complete.
    video: bool = False


class FindCandidatesRequest(BaseModel):
    #? as CREDITED on this release - the name most shares of it will carry
    artist: str
    #? The artist's CURRENT name, and their ids. Declared because the browser has sent both
    #? since v0.6.18 and pydantic dropped them without a word; the search is now what they are
    #? for. See search_names().
    album_artist: str | None = None
    artist_mbids: list[str] = Field(default_factory=list)
    album: str
    year: str | None = None
    #? the release GROUP's first-release-date, i.e. when the album came out rather than when
    #? this pressing did. Names the folder; see build_album_dirname.
    original_year: str | None = None
    release_mbid: str | None = None
    #? Which ALBUM the pressing belongs to, for "you also have another pressing" (step 2).
    #? Declared because the browser has always sent it and pydantic dropped it without a word -
    #? the trap this file's comments describe four times over.
    release_group_mbid: str | None = None
    #? What names an edition's folder (src/editions.py), declared for the same reason: Find works
    #? out where a download WOULD be filed, to say truthfully whether it fills in a part already
    #? held (store_index.filing_folder), and without these it would work out the wrong folder.
    #? Both Find builders send the first four, as they send them to /enqueue; edition_label is
    #? sent by nothing yet, and is here because EnqueueRelease has it and filing reads it.
    disambiguation: str | None = None
    media_format: str | None = None
    country: str | None = None
    catalog_number: str | None = None
    edition_label: str | None = None
    edition_tags: list[str] = Field(default_factory=list)
    tracks: list[Track] = Field(default_factory=list)
    format_preference: str = "prefer_lossless"
    #? lets the UI re-run a tweaked query when the generated one finds nothing
    query_override: str | None = None


class EnqueueFile(BaseModel):
    filename: str
    size: int


class EnqueueRelease(BaseModel):
    """What the download is *for*. Persisted with the job so organizing it later needs no network."""
    #? as CREDITED - what the Soulseek search and the matcher work from
    artist: str = ""
    #? Who the album is BY, in their current name: the folder it is filed under and the
    #? albumartist tag inside. Declared, not left to ride along, because pydantic drops an
    #? undeclared field without a word - and every album would then be filed by its credit
    #? again, one folder per name an artist ever recorded under. Absent on jobs queued before it
    #? existed, which fall back to `artist` and file exactly as they always would have.
    album_artist: str | None = None
    album: str = ""
    year: str | None = None
    #? the release GROUP's first-release-date, i.e. when the album came out rather than when
    #? this pressing did. Names the folder; see build_album_dirname.
    original_year: str | None = None
    release_mbid: str | None = None
    edition_tags: list[str] = Field(default_factory=list)
    #? who the album is by, in MusicBrainz's terms, so the tags can say so
    artist_mbids: list[str] = Field(default_factory=list)
    tracks: list[Track] = Field(default_factory=list)

    #? Everything below feeds src/editions.py, which works out the folder an edition is filed
    #? into. Stored with the job rather than looked up at organize time on purpose: the same
    #? reason the tracklist is denormalized here, namely that MusicBrainz is regularly
    #? unreachable and filing a finished download must not depend on it.
    release_group_mbid: str | None = None
    #? MusicBrainz's own edition descriptor ("deluxe edition", "2011 remaster"). The single
    #? best source for naming an edition, because it is the field editors use to tell
    #? releases apart in the first place.
    disambiguation: str | None = None
    media_format: str | None = None
    country: str | None = None
    catalog_number: str | None = None
    #? An explicit override that beats every derived source. Nothing sets it yet - it is the
    #? hook for a future metadata manager, so that picking an edition by hand is a matter of
    #? writing this field rather than changing how editions are resolved.
    edition_label: str | None = None


class Quality(BaseModel):
    """
    What a folder's files are, as its candidate showed them (2.0.0-player.49) - kept with the job
    (store.quality_json) so someone offered to join the download is told what they'd get. Declared,
    every field: pydantic drops what it wasn't told about without a word.
    """
    formats: list[str] = Field(default_factory=list)
    bitrates: list[int | float] = Field(default_factory=list)
    bit_depths: list[int | float] = Field(default_factory=list)
    sample_rates: list[int | float] = Field(default_factory=list)
    variable_bitrate: bool | None = None


class Alternative(BaseModel):
    """A runner-up from the candidates list - somewhere else the same album could come from."""
    username: str
    directory: str = ""
    files: list[EnqueueFile]
    score: float | None = None
    #? (2.0.0-player.49) its quality, which the job takes on if a retry moves it here
    quality: Quality | None = None


class EnqueueRequest(BaseModel):
    username: str
    files: list[EnqueueFile]
    directory: str = ""
    release: EnqueueRelease = Field(default_factory=EnqueueRelease)
    #? The rest of the list as it was SHOWN when this was picked (v0.9.12), for "try the next
    #? peer". Declared - pydantic drops an undeclared field without a word, the trap this file
    #? has fallen into four times - and optional, so a caller that sends none still works.
    alternatives: list[Alternative] = Field(default_factory=list)
    #? the picked folder's quality (2.0.0-player.49) - optional, as everything added since is
    quality: Quality | None = None


def _asker(user) -> str:
    """
    Who is asking: the user FastAPI resolved for the request (current_user, in the route's signature)
    - or, for a route called straight from Python, as the tests call them, whoever current_user says
    with no request at all: `local` with logins off, and a 401 with them on (never a guess).
    """
    return user if isinstance(user, str) else current_user()


#? How long the Soulseek search will wait on MusicBrainz for an artist's former names. It runs
#? ALONGSIDE the first round of searches, which take about as long as their timeout, so within
#? this budget an artist who never renamed - nearly all of them - costs no extra time at all.
FORMER_NAMES_BUDGET_SECONDS = 8.0


def search_names(credit: str, current: str | None, former: list[str] | None = None) -> list[str]:
    """
    Every name an album might be shared under, most likely first.

    What a stranger typed into their folder name is what the album said when they got it - the
    CREDIT - or what they file that artist under now, which is the current name or, for someone
    who never re-filed, a former one. Ye's Donda is credited "Kanye West" and BULLY "Ye", and
    each is shared under both; Soulseek needs every word of a query in a path, so a search under
    one name cannot find a share under the other at all.

    Case-insensitive and in order, so an artist who never renamed is exactly one search.
    """
    names: dict[str, str] = {}
    for name in [credit, current or "", *(former or [])]:
        key = " ".join((name or "").split()).casefold()
        if key and key not in names:
            names[key] = name
    return list(names.values())


def _distinct(queries: list[str]) -> list[str]:
    """Queries in order, each once - two names can boil down to the same search."""
    seen: dict[str, str] = {}
    for query in queries:
        if query and query.casefold() not in seen:
            seen[query.casefold()] = query
    return list(seen.values())


async def _former_names(request: Request, body: "FindCandidatesRequest") -> list[str]:
    """
    Names this release's artist has stopped using, if MusicBrainz says so in time. Never raises.

    Only for a single-artist credit: a collaboration's names multiply (each artist, each name),
    and its credit and current names are already searched. A MusicBrainz that is slow or down
    costs nothing but the former names - the search goes on with what the release carried.
    """
    if len(body.artist_mbids) != 1:
        return []

    client = getattr(request.app.state, "musicbrainz_client", None)
    if client is None:
        return []

    try:
        artist = await asyncio.wait_for(
            client.get_artist_aliases(body.artist_mbids[0]), timeout=FORMER_NAMES_BUDGET_SECONDS
        )
    except (asyncio.TimeoutError, MusicBrainzUnavailable) as e:
        logger.debug(f"no former names for {body.artist}: {e or 'MusicBrainz took too long'}")
        return []
    except Exception as e:
        logger.debug(f"no former names for {body.artist}: {e}")
        return []

    #? request_with_retries answers with an error dict rather than raising when it gives up
    if not isinstance(artist, dict) or "error" in artist:
        return []

    return former_names(artist)


class ClientGone(Exception):
    """The request's client disconnected before the work finished."""


#? how often a long request looks to see whether anybody is still waiting for it
DISCONNECT_CHECK_SECONDS = 0.5


async def unless_abandoned(request: Request, work, check_every: float | None = None):
    """
    Await `work`, cancelling it if the client goes away first (raising ClientGone).

    The browser aborts a Soulseek search the page no longer wants (lib/latest.ts, v0.9.2), but
    uvicorn does not cancel a handler when its client disconnects - so the search ran on in
    slskd to its full timeout, was scored, and was returned into a closed connection. This
    notices the disconnect and cancels the work, which stops the searches (search_all).
    """
    check_every = DISCONNECT_CHECK_SECONDS if check_every is None else check_every
    task = asyncio.ensure_future(work)
    try:
        while True:
            done, _ = await asyncio.wait({task}, timeout=check_every)
            if done:
                return task.result()
            if await request.is_disconnected():
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
                raise ClientGone()
    finally:
        if not task.done():
            task.cancel()


#? how long Find waits on slskd to say how far an in-flight download has got - the answer is a
#? nicety on a panel that isn't searching, and must not hold it up
PROGRESS_BUDGET_SECONDS = 3.0


async def _files_done(slskd_client, job: dict) -> int | None:
    """How many of an in-flight job's files slskd says have arrived, or None if it won't say."""
    try:
        downloads = await asyncio.wait_for(slskd_client.get_downloads([job["username"]]),
                                           timeout=PROGRESS_BUDGET_SECONDS)
        summary = summarize_transfers(job, index_transfers_by_user(downloads))
        return summary["files_done"] if summary["matched"] else None
    except Exception:
        return None


def _nothing_here() -> dict:
    return {"downloading": None, "downloading_part": None, "held": None, "other_pressings": []}


async def _describe_in_flight(request: Request, job: dict, user: str | None = None) -> dict:
    """describe_job, with how far it has got: slskd's count while it downloads, every file after - and,
    with logins on (2.0.0-player.49), whether it's the asker's own, whether somebody else waits for it
    and what the copy is."""
    requesters = await request.app.state.store.requesters(job["id"]) if Config.logins_on() else None
    described = describe_job(job, user, requesters, everyone=await _everyone(request, user))
    if job["status"] in OPEN_STATUSES:
        done = await _files_done(request.app.state.slskd_client, job)
        if done is not None:
            described["done_files"] = done
    elif job["status"] in FILING_STATUSES:
        #? organizing, or complete and about to be: every file is in
        described["done_files"] = described["files"]
    #? failed, its retry pending (2.0.0-player.49): moving to its next peer - nothing is in from it yet
    return described


async def _store_state(request: Request, body: "FindCandidatesRequest", user: str | None = None) -> dict:
    """
    What the library and the downloads already have of this pressing (step 2), for a Find:
    {"downloading", "downloading_part", "held", "other_pressings"}. Only for a release with an
    id - the card's fallback without a tracklist is searched as it always was. Never raises: a
    check that fails is a check that says nothing, and the search runs.

    `downloading` is a job bringing the WHOLE pressing in (as many files as it has audio tracks),
    which stops the search. A job for part of it - a lone disc folder, a 9-of-10 folder - will
    never bring the rest, so it is `downloading_part`, a note, and the search runs. With logins on
    (2.0.0-player.49) each says whether it is `user`'s own - one somebody else asked for is theirs to
    join - and what its copy is (describe_job).
    """
    state = _nothing_here()
    if not body.release_mbid:
        return state

    store = getattr(request.app.state, "store", None)
    root = Config.LIBRARY_PATH or ""
    release = body.model_dump()
    try:
        state["other_pressings"] = await other_pressings(store, root, body.release_group_mbid, body.release_mbid)
        #? (2.0.0-player.52) with logins on, whether each is the asker's own: "The store also has another
        #? pressing" for one that isn't - left out when that means the store, or the ledger can't be read
        if state["other_pressings"]:
            yours = await library_ledger.yours_paths(store, root, user)
            if yours is not None:
                for pressing in state["other_pressings"]:
                    pressing["yours"] = pressing["path"] in yours
        job = await in_flight(store, body.release_mbid, release=release)
        if job is not None:
            state["downloading"] = await _describe_in_flight(request, job, user)
            return state

        part = await in_flight(store, body.release_mbid, release=release, whole=False)
        if part is not None:
            state["downloading_part"] = await _describe_in_flight(request, part, user)
        held = await held_copy(store, root, body.release_mbid, release)
        if held is not None:
            #? (2.0.0-player.51) the store's rows stay here - and, with logins on, say whether the asker
            #? holds it: "Already in your library", or "In the store" with Add to my library
            album_ids = held.pop("album_ids", [])
            if Config.logins_on() and user and user != BREAK_GLASS_USER:
                yours = await store.ledger_holds(user, album_ids)
                #? unread (None) says nothing - the line reads as it always did - never "not yours" on a guess
                if yours is not None:
                    held["yours"] = yours
        if held is not None and not held["complete"]:
            #? a download fills in a part only when filing would put it in that very folder
            held["filed_to"] = await filing_folder(root, release)
            held["fills_gaps"] = held["filed_to"] in held["paths"]
        state["held"] = held
    except Exception as e:
        logger.warning(f"could not check what is already here for {body.album}: {e}")
        return _nothing_here()
    return state


#? (2.0.0-player.61) Get albums: what starts a download - search Soulseek, enqueue, join one, the two retries -
#? needs `request` (src/users.py require): on for everyone by default, so an admin can take it away for a
#? listen-only account. The store's state, the list, cancelling and clearing your own need nothing more.
GET_ALBUMS = [Depends(require("request"))]


@router.post("/store_state")
async def store_state(request: Request, body: FindCandidatesRequest, user: str = Depends(current_user)):
    """
    What the library and the downloads already have of this pressing - and NO Soulseek search
    (2.0.0-player.15). The app's album-you-don't-have page asks it before Get, so it can say
    "Already in your library", "Already downloading", "You have 9 of 10 tracks" or "You also have
    another pressing" under the pressing you chose without costing a search: exactly what
    find_candidates answers before it decides whether to search (_store_state), and nothing more.
    The body is a Find's (the release the Get would download), so the same pressing is judged the
    same way by both. Never fails: a check that can't be made says nothing.
    """
    return await _store_state(request, body, _asker(user))


@router.post("/find_candidates", dependencies=GET_ALBUMS)
async def find_candidates(request: Request, body: FindCandidatesRequest, user: str = Depends(current_user)):
    """
    Search Soulseek for the release the user picked and rank what comes back against it.

    The ranking is the whole point - see src/matching.py. Candidates that don't match the
    requested edition are ranked down but deliberately still returned, since Soulseek folder
    names often omit edition text entirely and filtering would hide real results.

    Asks first whether it is needed at all (step 2): a pressing already downloading whole, or
    already in the library complete, isn't searched for - the answer says which, with no
    candidates. One held in part is searched as usual, with a note saying how much is held and
    whether a download would fill in that folder or be filed separately (store_index.
    filing_folder); a download of part of it already running, and other pressings of the album
    held, are notes too.
    """
    lookup = None

    try:
        slskd_client = request.app.state.slskd_client

        #? before any search starts - a few indexed reads, and per folder held a listing and each
        #? audio file's tags (existing_tracks), in a thread
        store_state = await _store_state(request, body, _asker(user))
        if store_state["downloading"] or (store_state["held"] and store_state["held"]["complete"]):
            what = "downloading" if store_state["downloading"] else "in your library"
            logger.info(f"not searching for {body.artist} - {body.album}: it is already {what}",
                        extra={"frontend": True, "src": "slskd"})
            return {**store_state, "query": "", "queries": [], "response_count": 0, "candidates": []}

        if body.query_override:
            #? typed by hand - searched exactly as typed, and only that
            queries = [body.query_override]
        else:
            queries = _distinct([
                build_search_query(name, body.album)
                for name in search_names(body.artist, body.album_artist)
            ])
            lookup = asyncio.create_task(_former_names(request, body))

        if not queries:
            raise HTTPException(status_code=400, detail="Could not build a search query")

        async def search():
            #? SLSKD_SEARCH_TIMEOUT (v0.9.16); max_wait covers slskd's own bookkeeping past it
            timeout = search_timeout_seconds()
            responses = await slskd_client.search_all(queries, search_timeout_ms=timeout * 1000,
                                                      max_wait=timeout + 17)

            if lookup is not None:
                #? Usually long finished - it had the whole first round to answer. A former
                #? name the release itself did not carry is a second round, and the only case
                #? that costs a second search's worth of waiting.
                extra = [
                    query for query in _distinct([
                        build_search_query(name, body.album) for name in await lookup
                    ])
                    if query.casefold() not in {q.casefold() for q in queries}
                ]
                if extra:
                    responses += await slskd_client.search_all(extra, search_timeout_ms=timeout * 1000,
                                                                max_wait=timeout + 17)
                    queries.extend(extra)

            return responses

        try:
            responses = await unless_abandoned(request, search())
        except ClientGone:
            #? nobody to answer - the page moved on, and the searches have been stopped
            return Response(status_code=204)

        expected = {
            "artist": body.artist,
            "album": body.album,
            "year": body.year,
            "edition_tags": body.edition_tags,
            "tracks": [t.model_dump() for t in body.tracks],
        }

        #? in a thread: scoring every folder a search returns is plain CPU, and done on the event
        #? loop it held up every other request - the downloads poll included - while it ran
        candidates = await asyncio.to_thread(rank_candidates, responses, expected, body.format_preference)

        if not candidates:
            logger.warning(
                f"no usable candidates for: {' / '.join(queries)}",
                extra={"frontend": True, "src": "slskd"},
            )

        else:
            logger.info(
                f"ranked {len(candidates)} candidates, best score {candidates[0]['score']}",
                extra={"frontend": True, "src": "slskd"},
            )

        serialized = [_serialize_candidate(c) for c in candidates]
        await _attach_measured_speeds(request, serialized)

        return {
            #? the first is what goes in the panel's query box, for editing
            "query": queries[0],
            #? every name it was searched under, so the panel can say so
            "queries": queries,
            "response_count": len(responses),
            "candidates": serialized,
            #? part of it held (a note that downloading fills the gaps), and other pressings
            **store_state,
        }

    except HTTPException:
        raise

    except SlskdSearchRefused as e:
        #? slskd would not start the search, and has already said why in the log. 502 rather
        #? than 500: nothing here is broken, the service we depend on declined - and the detail
        #? is a sentence about slskd, so it renders on its own without a prefix explaining that
        #? something went wrong searching slskd.
        raise HTTPException(status_code=502, detail=str(e))

    except Exception as e:
        logger.error(f"Exception in /find_candidates endpoint: {e}")
        raise HTTPException(status_code=500, detail=f"Error searching slskd: {e}")

    finally:
        #? however the search ended - a refusal, a failure, or an early 400 - the MusicBrainz
        #? lookup running beside it has nobody left to answer
        if lookup is not None and not lookup.done():
            lookup.cancel()


async def _attach_measured_speeds(request: Request, candidates: list[dict]) -> None:
    """
    Add what we have actually measured from each peer, where we have measured anything.

    Separate from _serialize_candidate because that one is pure and this one reads the
    database, and because it is one query for the whole list rather than one per candidate.

    Failure here is silent by design. Most peers have never been downloaded from, so a
    candidate with no measurement is the ordinary case and already renders correctly - which
    means a degraded read looks exactly like a peer nobody has met, rather than like an error.
    The advertised figure and the slot/queue chips are all still there.
    """
    if not candidates:
        return

    try:
        measured = await request.app.state.store.peer_speeds(
            [c["username"] for c in candidates]
        )

    except Exception as e:
        logger.debug(f"could not read measured peer speeds: {e}")
        return

    for candidate in candidates:
        row = measured.get(candidate["username"])
        if not row:
            continue

        candidate["measured_speed"] = row["avg_bytes_sec"]
        #? How many transfers that average stands on, so the UI can distinguish "one lucky
        #? download" from a settled figure instead of presenting both as equally certain.
        candidate["measured_samples"] = row["samples"]
        candidate["measured_at"] = row["last_seen"]


#? How many of a candidate's missing tracks are named on the page (2.0.0-player.15); the rest are
#? only counted, in `missing_count` - a folder missing half an album is said in a line, not a list.
MISSING_NAMED = 5


def _serialize_candidate(candidate: dict) -> dict:
    """
    Strip the bits the UI doesn't need. `track_mapping` in particular holds whole file dicts
    and gets big; it's recomputed server-side when the organizer needs it (phase 3). What the
    page wants of it - which tracks nothing in the folder was paired with - was worked out
    before it was dropped (matching.missing_tracks): the first MISSING_NAMED, and how many.
    """
    missing = candidate.get("missing_tracks") or []
    return {
        "username": candidate["username"],
        "directory": candidate["directory"],
        "directory_name": candidate["directory_name"],
        "score": candidate["score"],
        "signals": candidate["signals"],
        "matched_tracks": candidate["matched_tracks"],
        "expected_tracks": candidate["expected_tracks"],
        "audio_file_count": candidate["audio_file_count"],
        "detected_edition_tags": candidate["detected_edition_tags"],
        "disc_folders": candidate.get("disc_folders", []),
        "formats": candidate["formats"],
        "upload_speed": candidate["upload_speed"],
        "queue_length": candidate["queue_length"],
        "has_free_slot": candidate["has_free_slot"],
        "total_size": candidate["total_size"],
        "bitrates": candidate["bitrates"],
        "bit_depths": candidate.get("bit_depths", []),
        "sample_rates": candidate.get("sample_rates", []),
        "variable_bitrate": candidate.get("variable_bitrate", False),
        "missing_tracks": missing[:MISSING_NAMED],
        "missing_count": len(missing),
        #? the release's audio tracks (matching.audio_tracks) - a card's Tracks is "held of these"
        "audio_expected": candidate.get("audio_expected", candidate["expected_tracks"]),
        "files": [
            {"filename": f["filename"], "size": f.get("size", 0)}
            for f in candidate["files"]
        ],
    }


@router.post("/enqueue", dependencies=GET_ALBUMS)
async def enqueue(request: Request, body: EnqueueRequest, user: str = Depends(current_user)):
    """
    Queue a download with slskd, and record the job - and who asked for it (2.0.0-player.49).

    Refused with 409 when the whole release is already downloading, or already in the library
    complete (step 2) - Find says so first, so this is the race it can't see: a second tab, a
    double click, a panel left open while the album was filed. A job for part of it (a lone disc
    folder) refuses nothing: it will never bring the rest. The check, slskd's enqueue and the
    job's row are all under the release's lock, so of two at once only one reaches slskd; the
    other finds its job. A release with no id is neither checked nor locked.

    Per person (2.0.0-player.49), with logins on: the whole release already on its way for SOMEBODY
    ELSE is joined rather than refused - a request on that job, nothing asked of slskd (`joined`, and
    its `job_id`). Only one already waiting for it is refused, as before. With logins off there is one
    user, and every download already on its way is refused, as it always was - even one somebody asked
    for while logins were on.
    """
    user = _asker(user)
    try:
        slskd_client = request.app.state.slskd_client
        store = getattr(request.app.state, "store", None)
        files = [f.model_dump() for f in body.files]
        release = body.release.model_dump()

        async with release_lock(release.get("release_mbid")):
            #? the whole pressing already coming for someone else: join it, under the same lock (logins on)
            coming = await in_flight(store, release.get("release_mbid"), release=release) if Config.logins_on() else None
            if coming is not None and user not in await store.requesters(coming["id"]):
                #? 'waiting', 'gone' (cleared since) or None fall through: already_have says what's true now
                if await store.request_job(coming["id"], user) == "joined":
                    logger.info(f"{user} joined the download of {coming.get('artist')} - {coming.get('album')} "
                                f"from {coming.get('username')}", extra={"frontend": True, "src": "slskd"})
                    return {"status": "ok", "queued": 0, "job_id": coming["id"], "joined": True}

            problem = await already_have(store, release)
            if problem:
                #? the downloads panel shows this on the row you just asked for, as "refused: ..."
                raise HTTPException(status_code=409, detail=problem)

            ok, reason = await slskd_client.enqueue(body.username, files)

            if not ok:
                #? slskd's own words where it gave any - "bob is offline" is an answer, "refused"
                #? is a shrug. The downloads panel shows this on the row you just asked for.
                raise HTTPException(status_code=502, detail=reason or "slskd refused the download")

            #? record only after slskd accepts, so a rejected download never leaves a phantom job
            job_id = await request.app.state.store.create_job(
                username=body.username,
                directory=body.directory,
                files=files,
                release=release,
                #? a runner-up sent without a quality is stored as it always was
                alternatives=[a.model_dump(exclude=None if a.quality else {"quality"}) for a in body.alternatives],
                user=user,
                quality=body.quality.model_dump() if body.quality else None,
            )

        return {"status": "ok", "queued": len(files), "job_id": job_id}

    except HTTPException:
        raise

    except Exception as e:
        logger.error(f"Exception in /enqueue endpoint: {e}")
        raise HTTPException(status_code=500, detail=f"Error queueing download: {e}")


def _per_person(job: dict, user: str, admin: bool) -> dict:
    """
    What a row says about who asked for it, with logins on (2.0.0-player.49): `mine` (the asker's
    request on it is active - always, in a user's own list), `shared` (somebody else's is too: a
    cancel there only withdraws yours, or - an admin's - cancels it for them as well) and, for an
    admin, `requested_by`: the OTHER people waiting for it, in the order they asked - "you and
    ethan". Nothing with logins off: one user, and the rows as they always were.
    """
    if not Config.logins_on():
        return {}
    requesters = job.get("requesters") or []
    others = [name for name in requesters if name != user]
    return {"mine": user in requesters, "shared": bool(others), **({"requested_by": others} if admin else {})}


@router.get("/jobs")
async def jobs(request: Request, user: str = Depends(current_user)):
    """
    Tracked download jobs, merged with live progress from slskd.

    Progress is computed per request rather than stored - slskd is the source of truth for
    it and it changes every second, so persisting it would be churn for no benefit.

    Per person (2.0.0-player.49): a user's own - the downloads they're waiting for, joined ones too
    - and an admin's everyone's, but those they cleared, each saying who asked (_per_person). With
    logins off the one user is `local`, the admin, and every download is theirs.
    """
    user = _asker(user)
    #? (2.0.0-player.61) everyone's downloads: an admin's, or anyone an admin gave Everyone's downloads
    admin = await _everyone(request, user)
    logins = Config.logins_on()
    try:
        store = request.app.state.store
        #? with logins off, every download, as it always was
        #? (2.0.0-player.51) with them on, the runners-up of a download nothing of could be filed are read too
        stored = await (store.list_jobs(user=user, everyone=admin, not_filed=NOT_FILED_PATTERNS) if logins
                        else store.list_jobs())

        if not stored:
            return {"jobs": [], "tracking_enabled": store.available}

        transfers_by_user = {}
        if any(j["status"] in OPEN_STATUSES for j in stored):
            downloads = await request.app.state.slskd_client.get_downloads(
                j["username"] for j in stored if j["status"] in OPEN_STATUSES
            )
            transfers_by_user = index_transfers_by_user(downloads)

        summaries = [
            summarize_transfers(job, transfers_by_user)
            if job["status"] in OPEN_STATUSES
            else {"progress": 100.0 if job["status"] != "failed" else 0.0,
                  "state": None, "speed": 0, "bytes_transferred": 0,
                  "files_done": len(job["files"]) if job["status"] != "failed" else 0,
                  "files_total": len(job["files"]), "matched": False}
            for job in stored
        ]

        #? Only for jobs actually sat in a queue, and only the first file - slskd answers this
        #? one transfer at a time, so asking for every file every poll would hammer it for
        #? information that's identical across the folder anyway. Asked side by side (v0.9.9):
        #? one after another, every queued job added a round trip to every poll of the panel.
        async def position(job, summary):
            if job["status"] == "queued" and summary.get("matched"):
                return await _first_queue_position(request.app.state.slskd_client, job, transfers_by_user)
            return None

        positions = await asyncio.gather(*(position(j, sm) for j, sm in zip(stored, summaries)))

        merged = []
        for job, summary, queue_position in zip(stored, summaries, positions):
            merged.append({
                "attempt": max(1, len(job.get("tried") or [])),
                "id": job["id"],
                "artist": job["artist"],
                "album": job["album"],
                "year": job["year"],
                "username": job["username"],
                "directory": job["directory"],
                "status": job["status"],
                "error": job["error"],
                "created_at": job["created_at"],
                #? for the app's Requests tab (2.0.0-player.12): the cover and the "12 minutes ago"
                #? (list_jobs reads them, the group and edition by SQLite out of the stored release)
                "updated_at": job.get("updated_at"),
                "release_mbid": job.get("release_mbid"),
                "release_group_mbid": job.get("release_group_mbid"),
                "edition": job.get("edition"),
                #? how it ended, from the status and poller.py's named messages - None while going (and,
                #? with logins on, 2.0.0-player.51, `not_filed` for one nothing of could be filed)
                "outcome": job_outcome(job["status"], job["error"], not_filed=logins),
                "queue_position": queue_position,
                **summary,
                #? how many other peers "try next peer" could still move it to - only where it can
                #? (list_jobs reads the runners-up for no other job: failed, cancelled, and with logins on
                #? one nothing of could be filed), and 0 hides the button
                **({"alternatives_left": len(untried_alternatives(job))}
                   if retryable(job, logins) else {}),
                **_per_person(job, user, admin),
                #? (2.0.0-player.51) what its filing gave those who asked - 'added', 'incomplete', 'flagged'
                #? or None - with logins on only (off, the one library isn't shown)
                **({"library": job.get("library_grant")} if logins else {}),
            })

        return {"jobs": merged, "tracking_enabled": store.available}

    except Exception as e:
        logger.error(f"Exception in /jobs endpoint: {e}")
        raise HTTPException(status_code=500, detail=f"Error fetching download jobs: {e}")


async def _first_queue_position(slskd_client, job: dict, transfers_by_user: dict) -> int | None:
    wanted = {f["filename"] for f in job["files"]}

    for transfer in transfers_by_user.get(job["username"], []):
        if transfer.get("filename") in wanted and transfer.get("id"):
            return await slskd_client.queue_position(job["username"], transfer["id"])

    return None


async def _job_for(request: Request, job_id: int, user: str) -> dict:
    """
    The download, if `user` may act on it - with Everyone's downloads (an admin's, or given -
    2.0.0-player.61) any, anyone else one they're waiting for (2.0.0-player.49) - else 404, as for no
    download at all: somebody else's isn't theirs to see.
    """
    store = request.app.state.store
    job = await store.get_job(job_id)
    if job is None or not (await _everyone(request, user) or user in await store.requesters(job_id)):
        raise HTTPException(status_code=404, detail="No such download job")
    return job


@router.post("/jobs/{job_id}/cancel")
async def cancel_job(request: Request, job_id: int, user: str = Depends(current_user)):
    """
    Stop a download and mark the job cancelled.

    Cancels every transfer slskd currently holds for this job.

    Anything already filed into the library stays. The half-finished file in slskd's INCOMPLETE
    folder is removed only when SLSKD_INCOMPLETE_PATH says where that folder is - slskd keeps
    partials deliberately so a retried download can resume from them, so pointing deadwax at
    it is the explicit "no, a cancelled download is finished with" signal.

    Cancel means LEAVE (2.0.0-player.49): a user's cancel withdraws their request (`left`), and the
    download carries on for whoever else is waiting for it; slskd is cancelled, and the partials
    removed, only when the last one waiting leaves - or an admin cancels, which is for everyone.
    Decided under the job's lock (poller.job_lock_key), so a join or a retry is never half-way
    through as the last request goes. With logins off the one user is the admin: as it always was.
    """
    user = _asker(user)
    try:
        store = request.app.state.store
        job = await _job_for(request, job_id, user)

        async with release_lock(job_lock_key(job)):
            if not await _everyone(request, user):
                outcome = await store.leave_job(job_id, user)
                if outcome == "none":
                    raise HTTPException(status_code=404, detail="No such download job")
                if outcome == "left":
                    logger.info(f"{user} left {job['artist']} - {job['album']}; it carries on for whoever else asked",
                                extra={"frontend": True, "src": "slskd"})
                    return {"status": "ok", "left": True, "cancelled": 0, "partials_removed": 0,
                            "partials_problem": None}
            #? the last request, or an admin: the download itself, as it is now
            job = await store.get_job(job_id) or job
            return await _cancel_download(request, job)

    except HTTPException:
        raise

    except Exception as e:
        logger.error(f"Exception in /jobs/{job_id}/cancel: {e}")
        raise HTTPException(status_code=500, detail=f"Error cancelling download: {e}")


async def _cancel_download(request: Request, job: dict) -> dict:
    """The download itself cancelled: slskd's transfers, the status, the tidy, the partials."""
    store = request.app.state.store
    job_id = job["id"]
    slskd_client = request.app.state.slskd_client
    downloads = await slskd_client.get_downloads([job["username"]])
    transfers_by_user = index_transfers_by_user(downloads)

    wanted = {f["filename"] for f in job["files"]}
    cancelled = 0

    for transfer in transfers_by_user.get(job["username"], []):
        if transfer.get("filename") in wanted and transfer.get("id"):
            if await slskd_client.cancel_download(job["username"], transfer["id"]):
                cancelled += 1

    await store.update_status(job_id, "cancelled", "cancelled from deadwax")

    #? slskd removes a transfer from its list only once the cancel has SETTLED, which is a
    #? moment after this - so the removal is asked for again when it has (see poller.py)
    tidy_cancelled_later(slskd_client, job)

    #? After the transfers are cancelled, never before: slskd holds the file open while a
    #? transfer is live, and deleting it underneath would be a race with slskd's own writer.
    removed = await asyncio.to_thread(
        remove_incomplete_downloads,
        Config.SLSKD_INCOMPLETE_PATH or "",
        job["files"],
        job.get("directory", ""),
    )

    logger.info(
        f"cancelled {job['artist']} - {job['album']} ({cancelled} transfer(s))"
        + (f", removed {len(removed['removed'])} partial file(s)" if removed["removed"] else ""),
        extra={"frontend": True, "src": "slskd"},
    )

    for skipped in removed["skipped"]:
        logger.warning(
            f"left a partial file in place: {skipped}",
            extra={"frontend": True, "src": "slskd"},
        )

    return {
        "status": "ok",
        #? (2.0.0-player.49) the download itself was cancelled - not only a request withdrawn
        "left": False,
        "cancelled": cancelled,
        "partials_removed": len(removed["removed"]),
        #? surfaced rather than swallowed so "why is my incomplete folder still full" has
        #? an answer in the response as well as the log
        "partials_problem": removed["problem"],
    }


@router.post("/jobs/{job_id}/retry", dependencies=GET_ALBUMS)
async def retry_job(request: Request, job_id: int, user: str = Depends(current_user)):
    """
    Move a failed or cancelled download to the next peer from the list it was picked from
    (v0.9.12). Answers 200 either way: `moved` false with a `problem` - every peer refused, or
    none left to try - is an outcome to show on the row, not a server error. Open to anyone
    waiting for it, and an admin (2.0.0-player.49): the one download moves, and everyone waiting
    moves with it.
    """
    store = request.app.state.store
    job = await _job_for(request, job_id, _asker(user))

    #? (2.0.0-player.51) with logins on, also one downloaded that nothing of could be filed (poller.retryable)
    if not retryable(job):
        raise HTTPException(status_code=409, detail=f"this download is {job['status']}, not failed or cancelled")

    try:
        return await retry_next_peer(request.app.state.slskd_client, store, job)
    except Exception as e:
        logger.error(f"Exception in /jobs/{job_id}/retry: {e}")
        raise HTTPException(status_code=500, detail=f"Error trying the next peer: {e}")


@router.post("/jobs/{job_id}/retry_same", dependencies=GET_ALBUMS)
async def retry_job_same_peer(request: Request, job_id: int, user: str = Depends(current_user)):
    """
    Ask the same peer for a failed or cancelled download again (v1.0.7), for the files that
    didn't arrive. 200 either way, as /retry: `retried` false with a `problem` - the peer
    refused, or slskd is still stopping the last attempt - is shown on the row. Open to anyone
    waiting for it, and an admin, as /retry is (2.0.0-player.49).
    """
    store = request.app.state.store
    job = await _job_for(request, job_id, _asker(user))

    if job["status"] not in RETRYABLE_STATUSES:
        raise HTTPException(status_code=409, detail=f"this download is {job['status']}, not failed or cancelled")

    try:
        return await retry_same_peer(request.app.state.slskd_client, store, job)
    except Exception as e:
        logger.error(f"Exception in /jobs/{job_id}/retry_same: {e}")
        raise HTTPException(status_code=500, detail=f"Error asking the peer again: {e}")


@router.post("/jobs/clear")
async def clear_jobs(request: Request, user: str = Depends(current_user)):
    """
    Forget finished jobs. Anything still moving is deliberately left alone.

    Per person (2.0.0-player.49), with logins on: "Clear finished" HIDES them from the asker's list -
    an admin's, so everyone's in it - and a download goes for good once everyone who asked has cleared
    it (or left it): store.hide_finished. `removed` is how many left the asker's list. With logins off
    there is one user: every finished job is deleted, as it always was - one somebody asked for while
    logins were on too.
    """
    user = _asker(user)
    #? (2.0.0-player.61) everyone's downloads: an admin's, or anyone an admin gave Everyone's downloads
    admin = await _everyone(request, user)
    logins = Config.logins_on()
    try:
        store = request.app.state.store

        #? the last chance to take a cancelled job's transfers out of slskd's list - once its
        #? row is gone nothing can match them to it. Best effort: failing it clears anyway. With
        #? logins on, only the jobs this clear will really delete: the rest are still somebody's.
        try:
            cancelled = ([job for job in await store.jobs_to_forget(user, admin) if job["status"] == "cancelled"]
                         if logins else await store.jobs_with_status(("cancelled",)))
            if cancelled:
                await tidy_cancelled_transfers(request.app.state.slskd_client, cancelled)
        except Exception as e:
            logger.error(f"couldn't tidy cancelled transfers before clearing: {e}")

        if not logins:
            return {"status": "ok", "removed": await store.delete_jobs(CLEARABLE_STATUSES)}
        cleared = await store.hide_finished(user, admin)
        return {"status": "ok", "removed": cleared[0] if cleared else 0}

    except Exception as e:
        logger.error(f"Exception in /jobs/clear: {e}")
        raise HTTPException(status_code=500, detail=f"Error clearing jobs: {e}")


#? the join route's 409 for a download deleted since the page asked
CLEARED_SINCE = "that download has been cleared from the list since - get it again"


@router.post("/jobs/{job_id}/join", dependencies=GET_ALBUMS)
async def join_job(request: Request, job_id: int, user: str = Depends(current_user)):
    """
    Join a download somebody else asked for (2.0.0-player.49): the whole pressing already on its
    way - Find's "Already downloading", the album page's line - becomes yours too, a request on the
    one download rather than a second copy fetched. `joined` false: you were already waiting for it.

    Only a download still coming (store.still_coming: queued, downloading, being filed, or failed
    with its retry pending) and bringing the whole pressing; anything else is a 409 in words - it has
    landed, stopped, or been cleared since the page asked. Under the job's lock, so it never lands
    between a last request leaving and the download being cancelled.
    """
    user = _asker(user)
    store = request.app.state.store
    job = await store.get_job(job_id)
    if job is None:
        #? the usual way a Join meets no download: the last who asked cleared it from their list after
        #? the page drew its line. Said in words, not "No such download job" - joining somebody else's
        #? download is this route's point, so there is no id to hide (cancel and retry 404 instead)
        raise HTTPException(status_code=409, detail=CLEARED_SINCE)

    async with release_lock(job_lock_key(job)):
        job = await store.get_job(job_id)
        if job is None:
            raise HTTPException(status_code=409, detail=CLEARED_SINCE)
        if not coming_now(job):
            ended = {"organized": "has been filed into the library", "complete": "has finished",
                     "failed": "has failed", "cancelled": "has been cancelled"}.get(job["status"], f"is {job['status']}")
            raise HTTPException(status_code=409, detail=f"that download {ended} since - get it again to see where it stands")
        if not is_whole(job):
            raise HTTPException(status_code=409, detail="that download brings only part of this pressing, so it can't be joined")
        outcome = await store.request_job(job_id, user)

    if outcome is None:
        raise HTTPException(status_code=503, detail="deadwax couldn't write to its database, so you couldn't join it")
    if outcome == "gone":
        #? a clear (it takes no release lock) deleted it between the look above and the write
        raise HTTPException(status_code=409, detail=CLEARED_SINCE)
    if outcome == "joined":
        logger.info(f"{user} joined the download of {job.get('artist')} - {job.get('album')} from {job.get('username')}",
                    extra={"frontend": True, "src": "slskd"})
    return {"status": "ok", "job_id": job_id, "joined": outcome == "joined"}
