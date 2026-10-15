"""
Personal libraries (2.0.0-player.51, step 5 of the multi-user plan) - the rules, and the few steps that
need only the store. src/stars.py is the other half: starring each album as its user in Navidrome, and
reading their stars back.

Every rule here was decided with James on 2026-09-27 (option B: one Navidrome library; "your library" is
that user's Navidrome FAVOURITES - their starred albums - two-way with Amperfy). In short:

  YOUR LIBRARY IS YOUR STARRED ALBUMS. deadwax keeps a ledger of it (store.py's library_membership),
  keyed on store_album's id - which survives a re-file and an apply - so a download that files at 3am is
  still starred for you, and a star Navidrome loses can be put back.

  GRANTS ON EVERY WAY A DOWNLOAD ENDS, for each requester of the job (job_requests): filed - added;
  every file already there - added only if that folder holds the same release, else flagged for the
  admin (it hit another pressing or an untagged rip); some files failed - added, marked incomplete; a
  second copy of a release already held - not filed beside the first, ends "already in the store", and
  added (that is "every file already there" in the same release's folder); a dry run, organizing off,
  failed, nothing filed - nothing (grant_for). A Get of a release already in the store offers Add to my
  library instead (routes/my_library.py).

  WITH LOGINS OFF nothing visible changes: the one user, `local`, is given what it files, silently - an
  entry nobody ever stars (local is nobody's Navidrome account, and the worker runs only with logins on)
  and no word of it on any page, the event log included: a filing that would be flagged for the admin is
  neither flagged nor said (grant_job). The first admin's take-over moves those entries on (store.adopt_local),
  so what was got with logins off is still theirs once logins come on - the rule pins, preferences and
  requests already follow.

Pure, but for kick/kicked (a wake-up for the worker) and the retag marks (memory), has_library (which
names the break-glass admin), and grant_job, which writes what grant_for decides.
"""

import asyncio
from pathlib import Path

from src.config import Config
from src.logger import logger

#? What a filing gave those who asked (jobs.library_grant)
ADDED = "added"
INCOMPLETE = "incomplete"
FLAGGED = "flagged"
#? ...and once an admin has looked at a FLAGGED one (routes/held.py): Add for them makes it ADDED; Put away
#? LOOKED - still not given, but no longer "an admin has been asked to look"
LOOKED = "looked"

#? How an entry came (library_membership.how)
GRABBED, FROM_STORE, SEEDED, STARRED_ELSEWHERE = "grabbed", "added", "seeded", "starred"

#? Why an entry is still waiting (library_membership.problem) - said by problem_text
NOT_IN_NAVIDROME = "not_in_navidrome"
NO_RELEASE = "no_release"
MISSING = "missing"
NAVIDROME_DOWN = "navidrome_down"
NOT_CONFIRMED = "not_confirmed"
#? Navidrome lost a star it had (the album came back under another id, or went missing mid-retag)
STAR_LOST = "star_lost"

PROBLEM_WORDS = {
    NOT_IN_NAVIDROME: "Navidrome hasn't got it yet (it may still be scanning) - deadwax asks again by itself.",
    NO_RELEASE: ("It has no MusicBrainz release id, so deadwax can't find it in Navidrome - an admin can "
                 "apply a release to it."),
    MISSING: "Its folder isn't there just now - deadwax asks again once it is.",
    NAVIDROME_DOWN: "Navidrome isn't answering - deadwax asks again by itself.",
    NOT_CONFIRMED: "Navidrome took the star but didn't keep it - deadwax tries again by itself.",
    STAR_LOST: "Navidrome lost its star (the album moved or was re-tagged) - deadwax is putting it back.",
}

#? The backoff between tries of one entry: 30 s, doubling, at most half an hour - and on for ever: the
#? star is retried until it holds
FIRST_RETRY_SECONDS = 30
LAST_RETRY_SECONDS = 1800


def retry_after(attempts: int) -> float:
    """Seconds before an entry tried `attempts` times (counting this one) is tried again."""
    return float(min(LAST_RETRY_SECONDS, FIRST_RETRY_SECONDS * 2 ** max(0, attempts - 1)))


def problem_text(problem: str | None) -> str | None:
    return PROBLEM_WORDS.get(problem or "") if problem else None


def grant_for(results: dict | None, same_release: bool) -> str | None:
    """
    What a filing gives each of the job's requesters (the plan's table), from organize_job's results and
    whether the album folder it filed into already held this very release (`same_release` - the plan's,
    read before anything was written): ADDED, INCOMPLETE, FLAGGED, or None for nothing.

      - a dry run, or no results (organizing off, filing that raised): nothing - the row says why
      - some files failed: INCOMPLETE when a track landed, else nothing (no track filed)
      - nothing placed and nothing already there (nothing could be filed): nothing
      - nothing placed, everything already there: ADDED in the same release's folder (a second copy of a
        release already held, not filed beside the first), else FLAGGED for the admin - the folder
        holds another pressing or an untagged rip, which is nobody's to be given on a guess
      - otherwise (filed): ADDED
    """
    if not results or results.get("dry_run"):
        return None
    if results.get("failed"):
        return INCOMPLETE if results.get("tracks_organized", results.get("organized")) else None
    if not results.get("organized"):
        if not results.get("skipped"):
            return None
        return ADDED if same_release else FLAGGED
    return ADDED


# ----------------------------------------------------------------- the worker's wake-up

#? The starring worker's own loop and event, set as it starts (src/stars.py run_library_worker); a kick
#? from anywhere - a route, the poller - wakes it rather than leaving the album to its next pass
_worker: dict = {"loop": None, "event": None}


def worker_started(loop: asyncio.AbstractEventLoop, event: asyncio.Event) -> None:
    _worker["loop"], _worker["event"] = loop, event


def worker_stopped() -> None:
    _worker["loop"], _worker["event"] = None, None


def kick() -> None:
    """Wake the starring worker now - something was added, or someone signed in. Nothing with no worker
    (logins off, the tests); safe from any thread."""
    loop, event = _worker["loop"], _worker["event"]
    if loop is None or event is None:
        return
    try:
        loop.call_soon_threadsafe(event.set)
    except RuntimeError:
        #? its loop has closed under it
        worker_stopped()


# ----------------------------------------------------------------- albums mid-retag

#? Album folders (relative to the library) a release is being applied to right now: the sync never
#? reads a star lost there as an unstar - Navidrome may be between scans of the new tags and the rename
_RETAGGING: dict[str, int] = {}


def _key(path) -> str:
    return str(Path(str(path))).casefold()


def retag_started(path) -> str | None:
    if not path:
        return None
    key = _key(path)
    _RETAGGING[key] = _RETAGGING.get(key, 0) + 1
    return key


def retag_finished(key: str | None) -> None:
    if key is None or key not in _RETAGGING:
        return
    _RETAGGING[key] -= 1
    if _RETAGGING[key] <= 0:
        del _RETAGGING[key]


def retagging(path) -> bool:
    return bool(path) and _key(path) in _RETAGGING


# ----------------------------------------------------------------- who can hold an album

def has_library(user: str | None) -> bool:
    """
    Whether `user` can have a library: everyone but the break-glass admin, who has no Navidrome account
    behind them (no favourites to be the library, no login to star with) - an entry for it would never be
    starred or shown, yet would count as held (review). `local`, logins-off's one user, can: its entries
    are kept silently and the first admin takes them over.
    """
    #? imported here: src/auth.py imports this module at its top
    from src.auth import BREAK_GLASS_USER

    return bool(user) and user != BREAK_GLASS_USER


# ----------------------------------------------------------------- grants from a filing

async def grant_job(store, job: dict, results: dict | None, album_id: int | None, same_release: bool,
                    path: str | None = None) -> str | None:
    """
    Give the job's requesters what its filing earned (grant_for), recorded on the job too, so its row can
    say so - and flag it for the admin when it hit another pressing or an untagged rip (`path`: the album
    folder, relative to the library). Only requesters who can have a library count (has_library: never the
    break-glass admin); with none of them, nothing is recorded, and the row reads as it always did.

    WITH LOGINS OFF a flag is never written or said: Library care's Held by nobody isn't drawn, so the
    event log would point at nothing, and the flag would outlive logins-off naming `local` (review) - and
    the job records nothing, so its row reads as it always did, then and once logins come on.

    Never raises: the album is filed either way, and the ledger is caught up by Add to my library or the
    admin's flag.
    """
    try:
        grant = grant_for(results, same_release)
        if grant is None or album_id is None:
            return None
        users = [user for user in await store.requesters(job["id"]) if has_library(user)]
        if not users:
            return None
        if grant == FLAGGED:
            if not Config.logins_on():
                #? nobody is given it, and with logins off nothing says so: no flag, no line, nothing on the
                #? row (a 'flagged' kept there would claim an admin was asked once logins come on)
                return None
            await store.flag_add(album_id, job["id"], users, job.get("artist") or "", job.get("album") or "",
                                 path, job.get("release_mbid"))
            logger.warning(
                f"{job.get('artist')} - {job.get('album')}: every file was already in {path or 'its folder'}, "
                f"which holds another pressing or an untagged rip - nobody was given it; it waits for an admin "
                f"in Library care", extra={"frontend": True, "src": "slskd"})
        else:
            await store.grant_albums(users, [album_id], GRABBED, incomplete=grant == INCOMPLETE)
            kick()
        await store.set_job_grant(job["id"], album_id, grant)
        return grant
    except Exception as e:
        logger.warning(f"could not add {job.get('artist')} - {job.get('album')} to the libraries of those who asked: {e}")
        return None
