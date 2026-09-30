"""
Background reconciliation of slskd transfers against tracked download jobs.

slskd never tells us anything; it only answers when asked. So a loop polls its transfer
list and watches for jobs crossing a boundary - first bytes moving, everything finished,
the peer giving up - and records the transition. Progress itself is deliberately not
persisted (see store.summarize_transfers); this only cares about state changes worth
reacting to.

Phase 3 hooks the organizer onto the queued -> complete transition.
"""

import asyncio
import time
from pathlib import Path

from src.config import Config
from src.library import note_library_changed
from src.logger import logger
from src.lyrics import fetch_album_lyrics
from src.organizer import organize_job, remove_empty_incomplete_dirs, remove_incomplete_downloads
from src.peer_speed import RateAccumulator, measured_rate, observe
from src.store import RETRYABLE_STATUSES, index_transfers_by_user, settled_transfer_ids, summarize_transfers
from src.store_index import already_have, filing_finished, filing_started, index_folder, release_lock


POLL_INTERVAL_SECONDS = 5.0

#? a job whose files slskd has never heard of is usually a peer that went offline between
#? queueing and transferring. Give it a while before calling it, since a long queue can
#? legitimately sit unreported for a bit.
UNMATCHED_GRACE_POLLS = 24


async def poll_downloads_once(
    slskd_client,
    store,
    missing_counts: dict[int, int],
    rate_samples: dict[int, RateAccumulator] | None = None,
) -> None:
    """
    One reconciliation pass.

    `rate_samples` carries the peer-speed measurement across polls, the same way
    `missing_counts` carries the grace period. Optional so the existing callers and tests that
    do not care about measurement keep working unchanged; when it is omitted, nothing is
    measured and nothing is recorded.
    """
    open_jobs = await store.open_jobs()

    if not open_jobs:
        missing_counts.clear()
        #? Nothing is in flight, so no half-finished measurement can still be valid. Clearing
        #? here is what stops the dict growing for the life of the process.
        if rate_samples is not None:
            rate_samples.clear()
        return

    downloads = await slskd_client.get_downloads(job["username"] for job in open_jobs)
    transfers_by_user = index_transfers_by_user(downloads)

    for job in open_jobs:
        job_id = job["id"]
        summary = summarize_transfers(job, transfers_by_user)
        label = f"{job['artist']} - {job['album']}"

        if not summary["matched"]:
            missing_counts[job_id] = missing_counts.get(job_id, 0) + 1

            if missing_counts[job_id] >= UNMATCHED_GRACE_POLLS:
                logger.error(
                    f"gave up on {label}: slskd never reported these transfers, "
                    f"the peer is probably gone",
                    extra={"frontend": True, "src": "slskd"},
                )
                await store.update_status(job_id, "failed", "no transfers reported by slskd")
                missing_counts.pop(job_id, None)
                if rate_samples is not None:
                    rate_samples.pop(job_id, None)
                await _auto_retry(slskd_client, store, job)

            continue

        missing_counts.pop(job_id, None)

        #? Sampled on every matched poll, whatever the job's state. Intervals where the
        #? counter did not move are excluded inside observe() rather than here, because
        #? "queued" and "moving but slskd hasn't refreshed" are indistinguishable from out
        #? here and must be treated identically.
        if rate_samples is not None:
            rate_samples[job_id] = observe(
                rate_samples.get(job_id), summary["bytes_transferred"], time.monotonic()
            )

        if summary["files_done"] >= summary["files_total"]:
            logger.info(f"finished downloading {label}", extra={"frontend": True, "src": "slskd"})
            await _settle_peer_speed(job, store, rate_samples)
            await store.update_status(job_id, "complete")
            await _organize_if_enabled(job, store)
            continue

        #? Nothing is still moving and not everything arrived. Reaching a terminal status here
        #? is the whole point: a rejected transfer is reported by slskd forever without ever
        #? changing, so a job that doesn't act on it waits for a file that is never coming and
        #? shows "queued" indefinitely - which reads as "hasn't started yet" rather than as the
        #? refusal it is.
        if summary["files_failed"] and summary["files_done"] + summary["files_failed"] >= summary["files_total"]:
            reason = summary.get("failure_reason") or "the transfer failed"

            #? a partial arrival is a different situation from an outright refusal, and the
            #? files that DID land are still sitting in slskd's folder
            detail = (
                f"{reason} ({summary['files_done']} of {summary['files_total']} file(s) arrived)"
                if summary["files_done"]
                else reason
            )

            logger.error(
                f"download of {label} failed: {detail}",
                extra={"frontend": True, "src": "slskd"},
            )
            #? A partial arrival still measured a real rate, and a peer that half-sends is
            #? exactly one you want a number for next time. A refusal that moved no bytes
            #? measures nothing and records nothing - see measured_rate().
            await _settle_peer_speed(job, store, rate_samples)
            await store.update_status(job_id, "failed", detail)
            await _auto_retry(slskd_client, store, job)
            continue

        if job["status"] == "queued" and summary["progress"] > 0:
            logger.info(f"downloading {label}", extra={"frontend": True, "src": "slskd"})
            await store.update_status(job_id, "downloading")


async def _settle_peer_speed(
    job: dict, store, rate_samples: dict[int, RateAccumulator] | None
) -> None:
    """
    Write out what this peer actually gave us, and forget the working state.

    Called on every terminal transition rather than only on success, because a transfer that
    half-arrived measured a perfectly real rate while it was moving.

    Never raises and never blocks the transition. The download has already happened; failing
    to note the speed down is not a reason to report anything about the job differently.
    """
    if rate_samples is None:
        return

    state = rate_samples.pop(job["id"], None)
    rate = measured_rate(state)

    #? None means it never moved long enough to say anything - a refusal, or a transfer that
    #? died in its first tick. Recording a 0 there would put "this peer gives you nothing" on
    #? a candidate row as though it had been measured.
    if rate is None:
        return

    try:
        await store.record_peer_speed(job["username"], rate)
        logger.debug(f"measured {rate / 1024:.0f} KB/s from {job['username']}")

    except Exception as e:
        logger.debug(f"could not record the speed measured from {job['username']}: {e}")


async def _organize_if_enabled(job: dict, store) -> None:
    """
    Hand a finished download to the organizer.

    Kept off the critical path deliberately: a job that downloaded fine but failed to file
    itself is recorded as such and left on disk in slskd's folder, rather than being marked
    failed as though the download itself had gone wrong. Those are different problems and
    want different fixes.
    """
    if not Config.organizing_enabled():
        return

    await store.update_status(job["id"], "organizing")

    #? the album folder being filed, from the moment the plan names it until the index has it: a
    #? scan landing mid-copy must not pair it with some other copy's tombstone (store_index)
    filing: list[str | None] = []

    def plan_made(plan: dict) -> None:
        filing.append(filing_started(Config.LIBRARY_PATH or "", plan.get("album_dir")))

    try:
        results = await organize_job(
            job, Config.SLSKD_DOWNLOAD_PATH, Config.LIBRARY_PATH, Config.ORGANIZE_MODE, on_plan=plan_made
        )

        #? Whatever status the job ends on - organized, or complete with some files failed - the
        #? tracks that did land are in the library, and everything that has to know is told BEFORE
        #? the status is written.
        if results.get("organized") and not results.get("dry_run"):
            #? The store index learns the folder (step 2): until the status moves on from
            #? `organizing` a Find of this release sees the job in flight, and after it the index has
            #? to say the album is here, or there is a moment where neither is true and a second
            #? download gets through.
            await index_folder(store, Config.LIBRARY_PATH, (results.get("plan") or {}).get("album_dir"))
            #? Until 1.1.2 only a clean `organized` said so, so /owned went on answering from a
            #? snapshot without the album and the new-import badge never counted it. The page reacts
            #? to `organized` by asking /owned and the badge again, and must find both already
            #? knowing. The cache doesn't know about this folder yet, so the next "what do I own"
            #? asks the disk rather than the saved scan - see /library/owned.
            note_library_changed()
            #? a cover alone doesn't make the folder an album the scan would list, and a badge
            #? naming an album it can't show you is worse than no badge
            if results.get("tracks_organized"):
                await _enrol_for_review(job, results, store)
        for key in filing:
            filing_finished(key)
        filing.clear()

        if results.get("dry_run"):
            #? nothing actually moved, so don't claim it did
            await store.update_status(job["id"], "complete", "dry run - not organized")

        elif results["failed"]:
            await store.update_status(
                job["id"], "complete", f"{results['failed']} file(s) failed to organize"
            )

        elif not results["organized"] and not results.get("skipped"):
            #? nothing was placed and nothing was already there - usually the download path
            #? doesn't actually point at slskd's files. Saying "organized" here would send
            #? the user looking for an album that was never filed.
            await store.update_status(
                job["id"], "complete", "nothing could be organized, check SLSKD_DOWNLOAD_PATH"
            )

        elif not results["organized"]:
            #? every file was skipped because something was already at its destination, so
            #? nothing from THIS download reached the library. That used to fall through to
            #? "organized" below and report a green, finished job for an album that never
            #? arrived - the failure mode that made a second edition of an album look like it
            #? had been filed when it had not.
            if results.get("duplicates"):
                #? every track was already in that album folder, perhaps in another format - the
                #? organizer wouldn't file a second copy beside the first (v1.0.1). Counted from
                #? the duplicates, not everything skipped: a cover.jpg already there is skipped too
                message = (f"already in the store: all {results['duplicates']} track(s) were already "
                           f"there, nothing was filed")
            else:
                message = f"all {results['skipped']} file(s) already existed, nothing was filed"
            await store.update_status(job["id"], "complete", message)

        else:
            await store.update_status(job["id"], "organized")
            _fetch_lyrics_later(results)

    except Exception as e:
        logger.error(
            f"organizing {job['artist']} - {job['album']} failed: {e}",
            extra={"frontend": True, "src": "slskd"},
        )
        await store.update_status(job["id"], "complete", f"organize failed: {e}")

    finally:
        for key in filing:
            filing_finished(key)


#? Lyrics lookups in flight. asyncio holds only a WEAK reference to a task, so one nobody keeps
#? can be collected half way through - the set is what keeps them alive until they finish.
_lyrics_tasks: set[asyncio.Task] = set()


def _filed_path(results: dict) -> str | None:
    """Where an organized album landed, relative to LIBRARY_PATH, or None if it isn't inside it."""
    album_dir = (results.get("plan") or {}).get("album_dir")

    if not album_dir or not Config.LIBRARY_PATH:
        return None

    try:
        return str(Path(album_dir).relative_to(Path(Config.LIBRARY_PATH)))
    except ValueError:
        return None


def _fetch_lyrics_later(results: dict, client=None):
    """
    Look up lyrics for a just-filed album, without holding up anything else.

    A TASK, not an await: LRCLIB can take seconds a track when it hasn't seen one before, and the
    job is already organized and the album already in the library. Making the poller wait on
    lyrics would delay every other download's progress for words nobody has asked to read yet.

    Only reached for a job that really was organized, so a dry run fetches nothing - dry run
    writes nothing, and a .lrc is a write. Never raises: failing to find lyrics says nothing
    about whether the download worked.
    """
    if (Config.FETCH_LYRICS or "on") == "off":
        return None

    path = _filed_path(results)
    if path is None:
        return None

    if client is None:
        from src.api.lrclib_endpoint import lrclib
        client = lrclib

    async def run():
        try:
            await fetch_album_lyrics(path, Config.LIBRARY_PATH, client, lead_ms=Config.lyrics_lead_ms())
        except Exception as e:
            logger.warning(f"fetching lyrics for {path} failed: {e}")

    task = asyncio.create_task(run())
    _lyrics_tasks.add(task)
    task.add_done_callback(_lyrics_tasks.discard)
    return task


async def _enrol_for_review(job: dict, results: dict, store) -> None:
    """
    Register a just-filed album with the metadata queue.

    This is the moment the interface can honestly say "something new arrived", and recording it
    here rather than inferring it later is what makes the prompt free: the library is
    deliberately not scanned until you open its tab, so a badge that had to diff two scans
    would need a scan to exist. One row, written once, keyed on where the album landed.

    Everything it needs is already in the plan the organizer just executed. Called whenever a
    track reached the library, including when others failed to (v1.1.2): the album is there
    either way, and part of an album is exactly what wants looking at. It never raises - the
    files are filed, so failing to note it down is not a reason to report the job as broken.
    """
    album_dir = (results.get("plan") or {}).get("album_dir")

    if not album_dir or not Config.LIBRARY_PATH:
        return

    try:
        #? relative to LIBRARY_PATH, because that is the form every library endpoint takes and
        #? what album_review is keyed on
        path = str(Path(album_dir).relative_to(Path(Config.LIBRARY_PATH)))
    except ValueError:
        #? organized somewhere outside the library, which means LIBRARY_PATH moved under us.
        #? Nothing useful to record, and the scan won't find it either.
        logger.debug(f"not enrolling {album_dir} for review, it is outside LIBRARY_PATH")
        return

    await store.record_albums_seen(
        [{"path": path, "artist": job.get("artist"), "album": job.get("album")}],
        source="import",
    )


#? how long a cancelled job's transfers are waited on before the tidy gives up. slskd settles a
#? cancel in well under a second when the peer is reachable; this is the generous end.
TIDY_WAIT_SECONDS = 30.0
TIDY_INTERVAL_SECONDS = 1.0


async def tidy_cancelled_transfers(slskd_client, jobs: list[dict]) -> tuple[int, int]:
    """
    Take cancelled jobs' transfers out of slskd's own list. One pass: returns (removed, still
    waiting to settle).

    Asked for: "make sure a canceled job also gets removed from slskd's UI. Currently there's a
    bunch of canceled jobs just sitting there." deadwax always cancelled with `remove=true`,
    and slskd always answered 204 - and removed nothing. Read in slskd's source
    (TransfersController.CancelDownloadAsync, DownloadService): it calls TryCancel and then
    Remove on the same line, but TryCancel on a live transfer only SIGNALS its cancellation
    token, and the transfer reaches "Completed, Cancelled" when its task notices, a moment
    later. Remove only touches transfers already in a completed state, so it updates nothing and
    says nothing. A transfer slskd had lost track of (no token) is cancelled synchronously and
    WAS removed, which is why it only happened most of the time.

    So this asks again once slskd reports the transfer settled - the same call, which on a
    completed transfer is a no-op cancel and a real remove. Removal is slskd's soft delete: the
    record stays in its database, it just leaves the list.
    """
    downloads = await slskd_client.get_downloads(job["username"] for job in jobs)
    transfers_by_user = index_transfers_by_user(downloads)

    removed = waiting = 0
    for job in jobs:
        settled, unsettled = settled_transfer_ids(job, transfers_by_user)
        waiting += unsettled
        for transfer_id in settled:
            if await slskd_client.cancel_download(job["username"], transfer_id, remove=True):
                removed += 1

    return removed, waiting


def untried_alternatives(job: dict) -> list[dict]:
    """
    The runners-up a retry may still move a job to, in the order they were shown.

    Skips every PEER already tried, not just every folder: a peer who refused one folder or went
    offline is the likeliest to do it again, and the point of the next peer is a different one.
    """
    tried_users = {t.get("username") for t in job.get("tried") or []} | {job.get("username")}
    return [a for a in job.get("alternatives") or [] if a.get("username") not in tried_users]


#? how many runners-up one retry will ask before giving up - each ask can take seconds while
#? slskd connects to the peer, and a string of offline peers shouldn't hold a click for a minute
RETRY_ASKS = 3


def _job_release(job: dict) -> dict:
    """The release a job is for, with its id wherever the row keeps it."""
    release = dict(job.get("release") or {})
    release["release_mbid"] = release.get("release_mbid") or job.get("release_mbid")
    return release


#? what a retry says when the job it was asked about has moved on while it waited
MOVED_ON = "this download has already moved on - it's been retried or restarted meanwhile"
#? ...and when it was cleared from the list while it waited
CLEARED = "this download has been cleared from the list - search again to download it"


def _retry_lock(job: dict) -> str | None:
    """
    What a retry of this job locks on: its release - or, for a job with no release id, the job
    itself. Without that a job with no release id took no lock, so two retries of it (auto-retry
    and a click) both got past the re-read below and asked two peers (step 2 review).
    """
    release_mbid = _job_release(job)["release_mbid"]
    if release_mbid:
        return release_mbid
    return f"job:{job['id']}" if job.get("id") is not None else None


async def _fresh_job(store, job: dict) -> tuple[dict, str | None]:
    """
    The job as it is NOW, read under the retry's lock - and why a retry mustn't go on, if so.

    The caller's copy was read before the lock: the route reads it, checks it's failed, and
    waits; auto-retry holds its copy from the poll. By the time the lock is had, another retry
    may have moved the job to a peer - and going on with the stale copy asked slskd a second
    time and pointed the job back at the old peer, two downloads of one album (step 2 review).
    A row that has gone ("clear finished" while the retry waited) is not retried either: slskd
    would fetch an album no job is watching, and nothing would ever file it. Only with the store
    down, when nothing can be read at all, is the caller's copy all there is.
    """
    fresh = await store.get_job(job["id"]) if job.get("id") is not None else None
    if fresh is None:
        return job, (CLEARED if job.get("id") is not None and getattr(store, "available", False) else None)
    if fresh.get("status") not in RETRYABLE_STATUSES:
        return fresh, MOVED_ON
    return fresh, None


async def retry_next_peer(slskd_client, store, job: dict) -> dict:
    """
    Move a failed or cancelled job to the next peer from the list it was picked from.

    Returns {"moved", "username", "directory", "left", "problem"}. slskd is asked to queue each
    runner-up in turn until one accepts (at most RETRY_ASKS); every peer asked is recorded as
    tried, accepted or not, so the next retry never asks them again. On success the job points at
    the new folder and is queued again - the same job, carrying on - and the old attempt's settled
    transfers leave slskd's list, and its partials go too where SLSKD_INCOMPLETE_PATH is set
    (they are another peer's, so nothing will resume from them).

    Not for a release that has since been filed complete, or is downloading under another job
    (step 2), nor for a job that has itself moved on since the caller read it - it answers `moved`
    false with that as the problem, which the row shows after a click (AUTO_RETRY_PEER, which
    comes through here too, puts it in the log). Checked on the job as it is now, and the peers
    asked, under the release's lock (the job's own, with no release id), as /enqueue does.
    """
    async with release_lock(_retry_lock(job)):
        job, problem = await _fresh_job(store, job)
        problem = problem or await already_have(store, _job_release(job), excluding_job_id=job.get("id"))
        if problem:
            return {"moved": False, "username": None, "directory": None,
                    "left": len(untried_alternatives(job)), "problem": problem}
        return await _move_to_next_peer(slskd_client, store, job)


async def _move_to_next_peer(slskd_client, store, job: dict) -> dict:
    """retry_next_peer, past the check."""
    candidates = untried_alternatives(job)
    tried = list(job.get("tried") or [{"username": job["username"], "directory": job.get("directory")}])
    problem = None if candidates else "no other peers to try - search again for more"

    for alternative in candidates[:RETRY_ASKS]:
        files = alternative.get("files") or []
        ok, reason = await slskd_client.enqueue(alternative["username"], files)
        tried.append({"username": alternative["username"], "directory": alternative.get("directory")})

        if not ok:
            problem = reason or f"{alternative['username']} refused"
            continue

        #? the attempt being left behind: out of slskd's list once settled, partials removed
        try:
            await tidy_cancelled_transfers(slskd_client, [job])
            await asyncio.to_thread(remove_incomplete_downloads, Config.SLSKD_INCOMPLETE_PATH or "",
                                    job.get("files") or [], job.get("directory") or "")
        except Exception as e:
            logger.warning(f"couldn't tidy the previous attempt of job {job['id']}: {e}")

        await store.move_to_peer(job["id"], alternative["username"], alternative.get("directory") or "",
                                 files, tried)
        logger.info(
            f"trying the next peer for {job.get('artist')} - {job.get('album')}: {alternative['username']}",
            extra={"frontend": True, "src": "slskd"},
        )
        moved = {**job, "username": alternative["username"], "tried": tried}
        return {"moved": True, "username": alternative["username"],
                "directory": alternative.get("directory"),
                "left": len(untried_alternatives(moved)), "problem": None}

    await store.record_tried(job["id"], tried)
    return {"moved": False, "username": None, "directory": None,
            "left": len(untried_alternatives({**job, "tried": tried})), "problem": problem}


async def retry_same_peer(slskd_client, store, job: dict) -> dict:
    """
    Ask the same peer for a failed or cancelled job again (v1.0.7, asked for: "a button next to
    the next peer button to retry the same peer").

    Returns {"retried", "username", "files", "problem"}. Only the files that didn't arrive are
    asked for: a file slskd lists as succeeded is left alone, since asking again would fetch it a
    second time. slskd supersedes each old record itself (DownloadService.EnqueueAsync marks the
    previous one removed), and nothing here deletes a partial file - slskd resumes from it when
    `retry.partial` is Resume, which is the point of asking the same peer.

    A transfer slskd hasn't finished stopping - a cancel still settling - would be refused as
    "Already in progress" inside a 201 that says nothing about it, so the job is left as it was
    and the problem says to try again in a moment. When slskd's list can't be read at all,
    every file is asked for, which at worst fetches one again.

    Refused, as retry_next_peer is, for a release filed complete or downloading under another
    job since, or a job that has moved on since the caller read it (step 2), under the same lock.
    """
    async with release_lock(_retry_lock(job)):
        job, problem = await _fresh_job(store, job)
        problem = problem or await already_have(store, _job_release(job), excluding_job_id=job.get("id"))
        if problem:
            return {"retried": False, "username": job.get("username"), "files": 0, "problem": problem}
        return await _ask_same_peer(slskd_client, store, job)


async def _ask_same_peer(slskd_client, store, job: dict) -> dict:
    """retry_same_peer, past the check."""
    username = job["username"]
    files = job.get("files") or []

    downloads = await slskd_client.get_downloads([username])
    by_file = {t.get("filename"): t.get("state") or "" for t in index_transfers_by_user(downloads).get(username, [])}

    unsettled = [f for f in files if f["filename"] in by_file and "Completed" not in by_file[f["filename"]]]
    if unsettled:
        return {"retried": False, "username": username, "files": 0,
                "problem": "slskd is still stopping the last attempt - try again in a moment"}

    wanted = [f for f in files if "Succeeded" not in by_file.get(f["filename"], "")]
    if wanted:
        ok, reason = await slskd_client.enqueue(username, wanted)
        if not ok:
            return {"retried": False, "username": username, "files": 0,
                    "problem": reason or f"{username} refused"}

    #? the same peer, folder and files, back to queued with the error cleared - move_to_peer
    #? with nothing moved. `tried` is unchanged: this is no new peer.
    await store.move_to_peer(job["id"], username, job.get("directory") or "", files,
                             list(job.get("tried") or [{"username": username, "directory": job.get("directory")}]))
    logger.info(
        f"asking {username} again for {job.get('artist')} - {job.get('album')} "
        f"({len(wanted)} of {len(files)} file(s))",
        extra={"frontend": True, "src": "slskd"},
    )
    return {"retried": True, "username": username, "files": len(wanted), "problem": None}


async def _auto_retry(slskd_client, store, job: dict) -> None:
    """After a failure, when AUTO_RETRY_PEER is on and there is a runner-up to try."""
    if (Config.AUTO_RETRY_PEER or "off").strip().lower() != "on" or not untried_alternatives(job):
        return
    outcome = await retry_next_peer(slskd_client, store, job)
    if not outcome["moved"] and outcome["problem"] not in (MOVED_ON, CLEARED):
        #? a click got there first, or the row went: nothing failed, so nothing is said
        logger.warning(
            f"couldn't move {job.get('artist')} - {job.get('album')} to another peer: {outcome['problem']}",
            extra={"frontend": True, "src": "slskd"},
        )


#? held so asyncio's weak reference can't drop a tidy mid-wait, as with lyrics
_tidy_tasks: set[asyncio.Task] = set()


def tidy_cancelled_later(slskd_client, job: dict, sleep=asyncio.sleep) -> asyncio.Task:
    """
    Keep tidying one just-cancelled job until slskd has let go of all of it, or
    TIDY_WAIT_SECONDS pass. A task rather than an await: the cancel answers at once, and the
    downloads panel already shows it as cancelling without waiting on this.
    """
    async def run():
        waited = 0.0
        total = 0
        while True:
            removed, waiting = await tidy_cancelled_transfers(slskd_client, [job])
            total += removed
            if not waiting or waited >= TIDY_WAIT_SECONDS:
                break
            await sleep(TIDY_INTERVAL_SECONDS)
            waited += TIDY_INTERVAL_SECONDS

        if waiting:
            #? left for the next start-up sweep or "clear finished", which try again
            logger.warning(
                f"slskd was still cancelling {waiting} transfer(s) of {job['artist']} - {job['album']} "
                f"after {int(TIDY_WAIT_SECONDS)}s, so they're still in its list",
                extra={"frontend": True, "src": "slskd"},
            )
        elif total:
            logger.debug(f"removed {total} cancelled transfer(s) from slskd's list")

    task = asyncio.create_task(run())
    _tidy_tasks.add(task)
    task.add_done_callback(_tidy_tasks.discard)
    return task


async def tidy_cancelled_on_start(slskd_client, store) -> int:
    """
    Once, on start: anything cancelled before a restart, or before this tidy existed, whose job
    is still in the downloads list. A job already cleared from the list can't be matched to its
    transfers any more, so those are left to slskd's own "clear completed". Never raises - a
    start-up nicety must not stop the poller starting.
    """
    try:
        cancelled = await store.jobs_with_status(("cancelled",))
        if not cancelled:
            return 0
        removed, _ = await tidy_cancelled_transfers(slskd_client, cancelled)
        if removed:
            logger.info(
                f"removed {removed} cancelled transfer(s) from slskd's list",
                extra={"frontend": True, "src": "slskd"},
            )
        return removed
    except Exception as e:
        logger.error(f"couldn't tidy cancelled transfers on start: {e}")
        return 0


#? what the row of a download a stop caught mid-filing says, instead of "organizing" for ever
INTERRUPTED_FILING = "deadwax stopped while filing this - check the library and slskd's folder"


async def settle_interrupted_filing(store) -> int:
    """
    Once, on start: downloads a stop caught mid-filing, moved on to `complete` with a reason
    (v1.1.3). Returns how many.

    `organizing` is written as filing starts and only filing itself moves it on. Stopping the
    container cancels the poller task wherever it is, and a CancelledError is not an Exception,
    so _organize_if_enabled's own handler never sees it. A job left there is in neither
    OPEN_STATUSES (never polled again) nor CLEARABLE_STATUSES ("clear finished" leaves it), and
    the downloads panel polls every second while any job reads `organizing`. Nothing else writes
    the status and one process runs one poller, so at start-up every such job was interrupted.

    Not filed again: how far it got is unknown - a move may already have taken half the tracks
    out of slskd's folder - and re-running the organizer over that unattended is a guess. The
    row says where to look instead. Never raises: a start-up nicety must not stop the poller.
    """
    try:
        stuck = await store.jobs_with_status(("organizing",))
        for job in stuck:
            await store.update_status(job["id"], "complete", INTERRUPTED_FILING)
        if stuck:
            logger.warning(
                f"{len(stuck)} download(s) were being filed when deadwax stopped, check them in "
                f"the library",
                extra={"frontend": True, "src": "slskd"},
            )
        return len(stuck)
    except Exception as e:
        logger.error(f"couldn't settle downloads interrupted while filing: {e}")
        return 0


#? every ten minutes at the poll interval - the empty-folder sweep is a walk of slskd's
#? incomplete folder, cheap but not free, and nothing about it is urgent
EMPTY_DIR_SWEEP_POLLS = 120


async def sweep_empty_incomplete_dirs() -> int:
    """
    Remove empty folders slskd left in its incomplete folder, when deadwax has been told where
    that is (SLSKD_INCOMPLETE_PATH - the same opt-in as removing a cancelled download's partial
    file). See organizer.remove_empty_incomplete_dirs for why they pile up. Never raises.
    """
    root = Config.SLSKD_INCOMPLETE_PATH or ""
    if not root:
        return 0
    try:
        removed = await asyncio.to_thread(remove_empty_incomplete_dirs, root)
    except Exception as e:
        logger.error(f"couldn't sweep empty folders from {root}: {e}")
        return 0
    if removed:
        logger.info(f"removed {len(removed)} empty folder(s) from slskd's incomplete folder")
    return len(removed)


async def run_download_poller(slskd_client, store) -> None:
    logger.info("download poller started")
    missing_counts: dict[int, int] = {}
    rate_samples: dict[int, RateAccumulator] = {}

    await settle_interrupted_filing(store)
    await tidy_cancelled_on_start(slskd_client, store)
    await sweep_empty_incomplete_dirs()
    polls = 0

    while True:
        try:
            await asyncio.sleep(POLL_INTERVAL_SECONDS)
            await poll_downloads_once(slskd_client, store, missing_counts, rate_samples)

            polls += 1
            if polls % EMPTY_DIR_SWEEP_POLLS == 0:
                await sweep_empty_incomplete_dirs()

        except asyncio.CancelledError:
            logger.info("download poller stopped")
            raise

        except Exception as e:
            # a transient slskd outage must not kill the loop for the rest of the process
            logger.error(f"download poller iteration failed, continuing: {e}")
