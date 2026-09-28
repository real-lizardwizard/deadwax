"""
When Navidrome has scanned an album's new tags, so its folder can be renamed (v1.0.3).

Applying a release that changes an album's id tags AND its folder is done in two steps - the
tags, then the rename - because Navidrome carries every user's plays, ratings and favourites
across either change alone but not across both in one scan (see changes_player_ids in
retag.py). 1.0.1 waited a fixed RETAG_RENAME_WAIT between the two. With the Navidrome
connection there to ask, deadwax asks instead: getScanStatus, which any account may call (only
startScan needs an admin - server/subsonic/api.go), polled until a scan that BEGAN after the
tags were written has finished.

This module is the pure half: what one answer says, and when the answers so far prove the scan
happened. The apply route in routes/library.py does the asking and the waiting.

WHAT AN ANSWER CAN PROVE, read in Navidrome's source (scanner/controller.go, scanner.go):

  - `lastScan` moves only when a scan SUCCEEDS - writing it is the last step of a scan - and it
    moves for every kind of scan, the watcher's selective ones included.
  - `scanning` is one flag for the whole process, and only one scan can run at a time.
  - Waiting until `scanning` is false is NOT enough. The watcher waits 5s after a change before
    it scans, so straight after the write nothing is running, and renaming then would land the
    rename in the very scan the two steps exist to keep it out of.

So a baseline is taken after the write (two reads - see begin()), and the wait is for lastScan
to move past it. With nothing running at the baseline, any scan that finishes later began after
the write. With a scan running at the baseline - a STRADDLER, which may have passed this folder
before the write - its own completion proves nothing, so the wait follows it to its end and
then needs one more. Seeing its end takes care for the same reason the baseline takes two reads:
see step().

When the wait gives up and the rename is held back, its state is kept, so applying the album
again asks Navidrome from where it left off rather than renaming unasked (scanned_since_hold()).

What it can't prove: which folders a scan read. getScanStatus says nothing about folders, so a
finished scan of somewhere else (an admin's targeted scan, or a second library - lastScan is
the latest across all of them) would count. For one library, where scans come from the watcher
(which queued this folder when the tags were written) or cover everything, that is sound. It is
said here so nobody mistakes it for more.
"""

import re
from dataclasses import dataclass
from datetime import datetime, timezone

#? How often Navidrome is asked while waiting. Speed only narrows one window - a straddling scan
#? ending and the next one starting and finishing all between two polls - which ends in a
#? hold-back, never in a wrong rename.
SCAN_POLL_SECONDS = 0.5

#? How long to wait for a scan before holding the rename back. The usual case is the watcher's 5s
#? plus about a second for the folder; 90 leaves room for several of its 15s retries while
#? another scan is running.
SCAN_WAIT_CAP_SECONDS = 90

#? Each question is bounded on its own - the Navidrome client's read timeout is a minute, which
#? suits a stream and would swallow the whole wait here.
SCAN_CALL_TIMEOUT_SECONDS = 5

#? Polls the cap allows. The route stops at whichever comes first, this or the clock, so a test
#? that makes waiting instant still ends.
SCAN_MAX_POLLS = int(SCAN_WAIT_CAP_SECONDS / SCAN_POLL_SECONDS)

#? Navidrome writes lastScan as RFC 3339 with nanoseconds. Python 3.12 reads nine digits, but
#? only keeps six; trimming first makes that true of any parser, and a scan is never timed
#? closer than a microsecond from the next.
_FRACTION = re.compile(r"(\.\d{6})\d+")


@dataclass(frozen=True)
class ScanStatus:
    """The part of one getScanStatus answer the wait uses."""
    scanning: bool
    last_scan: datetime
    #? "quick-selective" for a watcher scan - said in the log, never used as proof
    scan_type: str | None = None


@dataclass(frozen=True)
class WaitState:
    #? the lastScan a finished scan has to move past
    base: datetime
    #? a scan was running at the baseline, so its end doesn't count and one more is needed
    straddler: bool
    #? the straddler was last seen stopped with lastScan where it was - failed, or ended between
    #? the two reads Navidrome takes to answer - so the NEXT answer's lastScan is the new base
    ending: bool = False


def parse_time(value) -> datetime | None:
    """lastScan as a moment, or None when it isn't one. A time without a zone is read as UTC."""
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        moment = datetime.fromisoformat(_FRACTION.sub(r"\1", value.strip()))
    except ValueError:
        return None
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


def read_status(body) -> ScanStatus | None:
    """
    A getScanStatus answer's body (what navidrome.call() returns), or None when it can't be used.

    Unusable means no `scanning` flag or no readable `lastScan`: without the one there is no
    telling whether a scan straddles the write, without the other nothing to measure against. A
    server that has never scanned still sends one - Go's zero time, year 1 - which reads fine.
    """
    status = body.get("scanStatus") if isinstance(body, dict) else None
    if not isinstance(status, dict) or not isinstance(status.get("scanning"), bool):
        return None

    last_scan = parse_time(status.get("lastScan"))
    if last_scan is None:
        return None

    scan_type = status.get("scanType")
    return ScanStatus(status["scanning"], last_scan, scan_type if isinstance(scan_type, str) and scan_type else None)


def begin(first: ScanStatus | None, second: ScanStatus | None) -> WaitState | None:
    """
    The baseline, from two reads taken one after the other once the tags are on disk.

    Two, because Navidrome reads lastScan BEFORE the running flag when it answers
    (controller.go). A scan that began before the write and ended between those two reads
    answers {old lastScan, not scanning}, and its completion would then be taken for a new scan.
    The second read either sees that scan's lastScan, or the first caught it running.

    None when either read failed: the wait can't judge anything without a baseline. The caller
    holds the rename back when that was Navidrome not answering at all, and otherwise falls back
    to the fixed pause.
    """
    if first is None or second is None:
        return None
    return WaitState(base=second.last_scan, straddler=first.scanning or second.scanning)


def step(state: WaitState, status: ScanStatus | None) -> tuple[WaitState, bool]:
    """
    One more answer. Returns the new state, and whether a scan that began after the write has
    now finished. An answer that couldn't be read (None) changes nothing.
    """
    if status is None:
        return state, False

    advanced = status.last_scan > state.base

    if not state.straddler:
        #? Nothing was running at the baseline, so the finished scan began after it - and so
        #? after the write - whatever `scanning` says now (the watcher may already be on the next).
        return state, advanced

    if state.ending:
        #? The answer after the straddler was seen stopping. If it ended inside that answer, its
        #? end had been written before the flag was read, so this lastScan has it - and whatever
        #? is running now began after it. Taken as the base, never as proof, as begin()'s second
        #? read is. max(), so a lastScan that went backwards (a library removed) can't lower the bar.
        return WaitState(base=max(state.base, status.last_scan), straddler=False), False

    if advanced:
        #? The straddler has written its end. Not proof: it may have read this folder before the
        #? tags changed. Its end is the new baseline, and the next completion counts.
        return WaitState(base=status.last_scan, straddler=False), False

    if not status.scanning:
        #? Stopped with lastScan where it was. A scan that FAILED looks like this - and so does one
        #? that ended between Navidrome reading lastScan and reading the flag, for the same reason
        #? begin() takes two reads. Clearing it here would let the straddler's own end, seen on
        #? the next poll, confirm the rename. So one more answer is taken first, for its lastScan.
        return WaitState(base=state.base, straddler=True, ending=True), False

    return state, False


def scanned_since_hold(held: WaitState | None, written: datetime, status: ScanStatus) -> bool:
    """
    Whether a rename held back by an earlier apply may go ahead now, from one answer read when the
    album is applied again: a scan that began after the tags were written has finished since.

    `held` is the wait's state when it gave up. Past its base is proof - unless a straddler was
    still unresolved then, when a completion since may be the straddler's own, and the ordinary
    wait from here decides instead (costing, at worst, one more scan). With no state at all -
    Navidrome couldn't be read at the hold - the bar is the moment the tags were written, since
    deadwax and Navidrome read the clock of one host. That can't tell a scan which began before
    the write and ended after it; it is only reached when Navidrome didn't answer at the time.
    """
    if held is None:
        return status.last_scan > written
    if held.straddler:
        return False
    return status.last_scan > held.base
