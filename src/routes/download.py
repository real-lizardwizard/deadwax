import asyncio

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field

from src.api.musicbrainz_endpoint import MusicBrainzUnavailable
from src.api.slskd_endpoint import SlskdSearchRefused, build_search_query
from src.artists import former_names
from src.config import Config, search_timeout_seconds
from src.logger import logger
from src.matching import rank_candidates
from src.organizer import remove_incomplete_downloads
from src.poller import (retry_next_peer, retry_same_peer, tidy_cancelled_later, tidy_cancelled_transfers,
                        untried_alternatives)
from src.store import (CLEARABLE_STATUSES, OPEN_STATUSES, RETRYABLE_STATUSES,
                       index_transfers_by_user, summarize_transfers)

router = APIRouter()


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


class Alternative(BaseModel):
    """A runner-up from the candidates list - somewhere else the same album could come from."""
    username: str
    directory: str = ""
    files: list[EnqueueFile]
    score: float | None = None


class EnqueueRequest(BaseModel):
    username: str
    files: list[EnqueueFile]
    directory: str = ""
    release: EnqueueRelease = Field(default_factory=EnqueueRelease)
    #? The rest of the list as it was SHOWN when this was picked (v0.9.12), for "try the next
    #? peer". Declared - pydantic drops an undeclared field without a word, the trap this file
    #? has fallen into four times - and optional, so a caller that sends none still works.
    alternatives: list[Alternative] = Field(default_factory=list)


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

    The browser aborts a Soulseek search the page no longer wants (latest.mjs, v0.9.2), but
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


@router.post("/find_candidates")
async def find_candidates(request: Request, body: FindCandidatesRequest):
    """
    Search Soulseek for the release the user picked and rank what comes back against it.

    The ranking is the whole point - see src/matching.py. Candidates that don't match the
    requested edition are ranked down but deliberately still returned, since Soulseek folder
    names often omit edition text entirely and filtering would hide real results.
    """
    lookup = None

    try:
        slskd_client = request.app.state.slskd_client

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


def _serialize_candidate(candidate: dict) -> dict:
    """
    Strip the bits the UI doesn't need. `track_mapping` in particular holds whole file dicts
    and gets big; it's recomputed server-side when the organizer needs it (phase 3).
    """
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
        "files": [
            {"filename": f["filename"], "size": f.get("size", 0)}
            for f in candidate["files"]
        ],
    }


@router.post("/enqueue")
async def enqueue(request: Request, body: EnqueueRequest):
    try:
        slskd_client = request.app.state.slskd_client
        files = [f.model_dump() for f in body.files]

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
            release=body.release.model_dump(),
            alternatives=[a.model_dump() for a in body.alternatives],
        )

        return {"status": "ok", "queued": len(files), "job_id": job_id}

    except HTTPException:
        raise

    except Exception as e:
        logger.error(f"Exception in /enqueue endpoint: {e}")
        raise HTTPException(status_code=500, detail=f"Error queueing download: {e}")


@router.get("/jobs")
async def jobs(request: Request):
    """
    Tracked download jobs, merged with live progress from slskd.

    Progress is computed per request rather than stored - slskd is the source of truth for
    it and it changes every second, so persisting it would be churn for no benefit.
    """
    try:
        store = request.app.state.store
        stored = await store.list_jobs()

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
                "queue_position": queue_position,
                **summary,
                #? how many other peers "try next peer" could still move it to - only where it can
                #? (list_jobs reads the runners-up for no other job), and 0 hides the button
                **({"alternatives_left": len(untried_alternatives(job))}
                   if job["status"] in RETRYABLE_STATUSES else {}),
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


@router.post("/jobs/{job_id}/cancel")
async def cancel_job(request: Request, job_id: int):
    """
    Stop a download and mark the job cancelled.

    Cancels every transfer slskd currently holds for this job.

    Anything already filed into the library stays. The half-finished file in slskd's INCOMPLETE
    folder is removed only when SLSKD_INCOMPLETE_PATH says where that folder is - slskd keeps
    partials deliberately so a retried download can resume from them, so pointing deadwax at
    it is the explicit "no, a cancelled download is finished with" signal.
    """
    try:
        store = request.app.state.store
        job = await store.get_job(job_id)

        if job is None:
            raise HTTPException(status_code=404, detail="No such download job")

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
            "cancelled": cancelled,
            "partials_removed": len(removed["removed"]),
            #? surfaced rather than swallowed so "why is my incomplete folder still full" has
            #? an answer in the response as well as the log
            "partials_problem": removed["problem"],
        }

    except HTTPException:
        raise

    except Exception as e:
        logger.error(f"Exception in /jobs/{job_id}/cancel: {e}")
        raise HTTPException(status_code=500, detail=f"Error cancelling download: {e}")



@router.post("/jobs/{job_id}/retry")
async def retry_job(request: Request, job_id: int):
    """
    Move a failed or cancelled download to the next peer from the list it was picked from
    (v0.9.12). Answers 200 either way: `moved` false with a `problem` - every peer refused, or
    none left to try - is an outcome to show on the row, not a server error.
    """
    store = request.app.state.store
    job = await store.get_job(job_id)

    if job is None:
        raise HTTPException(status_code=404, detail="No such download job")
    if job["status"] not in RETRYABLE_STATUSES:
        raise HTTPException(status_code=409, detail=f"this download is {job['status']}, not failed or cancelled")

    try:
        return await retry_next_peer(request.app.state.slskd_client, store, job)
    except Exception as e:
        logger.error(f"Exception in /jobs/{job_id}/retry: {e}")
        raise HTTPException(status_code=500, detail=f"Error trying the next peer: {e}")


@router.post("/jobs/{job_id}/retry_same")
async def retry_job_same_peer(request: Request, job_id: int):
    """
    Ask the same peer for a failed or cancelled download again (v1.0.7), for the files that
    didn't arrive. 200 either way, as /retry: `retried` false with a `problem` - the peer
    refused, or slskd is still stopping the last attempt - is shown on the row.
    """
    store = request.app.state.store
    job = await store.get_job(job_id)

    if job is None:
        raise HTTPException(status_code=404, detail="No such download job")
    if job["status"] not in RETRYABLE_STATUSES:
        raise HTTPException(status_code=409, detail=f"this download is {job['status']}, not failed or cancelled")

    try:
        return await retry_same_peer(request.app.state.slskd_client, store, job)
    except Exception as e:
        logger.error(f"Exception in /jobs/{job_id}/retry_same: {e}")
        raise HTTPException(status_code=500, detail=f"Error asking the peer again: {e}")


@router.post("/jobs/clear")
async def clear_jobs(request: Request):
    """Forget finished jobs. Anything still moving is deliberately left alone."""
    try:
        store = request.app.state.store

        #? the last chance to take a cancelled job's transfers out of slskd's list - once its
        #? row is gone nothing can match them to it. Best effort: failing it clears anyway.
        try:
            cancelled = await store.jobs_with_status(("cancelled",))
            if cancelled:
                await tidy_cancelled_transfers(request.app.state.slskd_client, cancelled)
        except Exception as e:
            logger.error(f"couldn't tidy cancelled transfers before clearing: {e}")

        removed = await store.delete_jobs(CLEARABLE_STATUSES)
        return {"status": "ok", "removed": removed}

    except Exception as e:
        logger.error(f"Exception in /jobs/clear: {e}")
        raise HTTPException(status_code=500, detail=f"Error clearing jobs: {e}")
