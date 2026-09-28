"""
When Navidrome has scanned an album's new tags (v1.0.3) - the pure rules, case by case.

The route asks getScanStatus and hands each answer to these; what they protect is the one
promise that matters: the folder is only renamed after a scan that BEGAN after the tags were
written has finished. A wrong "yes" is the one-step apply that loses every user's plays; a wrong
"no" only holds the rename back for a second click. So every doubtful case here comes out "no".
"""

import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.scan_wait import (SCAN_MAX_POLLS, SCAN_POLL_SECONDS, SCAN_WAIT_CAP_SECONDS,  # noqa: E402
                           ScanStatus, WaitState, begin, parse_time, read_status, scanned_since_hold,
                           step)

T0 = "2026-09-27T10:00:00.123456789Z"
T1 = "2026-09-27T10:00:07.5Z"
T2 = "2026-09-27T10:00:30Z"


def at(text: str, scanning: bool = False, scan_type: str | None = "quick-selective") -> ScanStatus:
    return ScanStatus(scanning, parse_time(text), scan_type)


def run(state: WaitState, *answers: ScanStatus | None) -> list[bool]:
    """Feed answers in turn; what each one concluded."""
    verdicts = []
    for answer in answers:
        state, confirmed = step(state, answer)
        verdicts.append(confirmed)
    return verdicts


# ----- reading an answer -----

def test_navidromes_nanosecond_times_are_read():
    """RFC 3339 with nine digits of fraction, as Go writes it."""
    assert parse_time(T0) == datetime(2026, 9, 27, 10, 0, 0, 123456, tzinfo=timezone.utc)
    assert parse_time("2026-09-27T12:00:00.5+02:00") == datetime(2026, 9, 27, 10, 0, 0, 500000, tzinfo=timezone.utc)


def test_a_server_that_never_scanned_still_has_a_time():
    """Go's zero time, which Navidrome sends rather than leaving the field out."""
    assert parse_time("0001-01-01T00:00:00Z") < parse_time(T0)


def test_a_time_without_a_zone_is_read_as_utc():
    assert parse_time("2026-09-27T10:00:00") == datetime(2026, 9, 27, 10, tzinfo=timezone.utc)


def test_a_whole_answer_is_read():
    body = {"status": "ok", "scanStatus": {"scanning": True, "count": 12, "folderCount": 3,
                                           "lastScan": T0, "scanType": "quick-selective",
                                           "elapsedTime": 1200000000}}
    assert read_status(body) == ScanStatus(True, parse_time(T0), "quick-selective")


def test_an_answer_that_cannot_be_judged_is_none():
    """No flag, no time, or a time that isn't one - there is nothing to measure against."""
    assert read_status({"scanStatus": {"lastScan": T0}}) is None
    assert read_status({"scanStatus": {"scanning": "false", "lastScan": T0}}) is None
    assert read_status({"scanStatus": {"scanning": False}}) is None
    assert read_status({"scanStatus": {"scanning": False, "lastScan": "yesterday"}}) is None
    assert read_status({"scanStatus": {"scanning": False, "lastScan": ""}}) is None
    assert read_status({"status": "ok"}) is None
    assert read_status(None) is None


# ----- the baseline -----

def test_the_baseline_is_the_second_read():
    state = begin(at(T0), at(T0))
    assert state == WaitState(base=parse_time(T0), straddler=False)


def test_a_scan_running_at_either_read_straddles_the_write():
    assert begin(at(T0, scanning=True), at(T0)).straddler
    assert begin(at(T0), at(T0, scanning=True)).straddler


def test_a_scan_that_ended_between_the_two_reads_is_still_a_straddler():
    """
    Navidrome reads lastScan before the running flag, so the first read can say {old time,
    running}; the second then says {its end, idle}. The baseline takes its end, and its end is
    not proof - it may have read the folder before the tags changed.
    """
    state = begin(at(T0, scanning=True), at(T1))
    assert state == WaitState(base=parse_time(T1), straddler=True)


def test_a_baseline_that_cannot_be_read_is_none():
    """The route then holds the rename (Navidrome unreachable) or waits the fixed time (unusable)."""
    assert begin(None, at(T0)) is None
    assert begin(at(T0), None) is None


# ----- the wait -----

def test_idle_then_a_finished_scan_confirms():
    """The ordinary case: the watcher scans 5s after the write, and lastScan moves."""
    state = begin(at(T0), at(T0))
    assert run(state, at(T0), at(T0, scanning=True), at(T1)) == [False, False, True]


def test_idle_then_an_advance_confirms_even_while_the_next_scan_runs():
    """Nothing ran at the baseline, so the scan that finished began after it."""
    state = begin(at(T0), at(T0))
    assert run(state, at(T1, scanning=True)) == [True]


def test_nothing_finishing_never_confirms():
    """Where a cap reached with Navidrome answering ends: held back."""
    state = begin(at(T0), at(T0))
    assert run(state, *[at(T0)] * 20) == [False] * 20


def test_a_straddler_seen_ending_then_the_next_completion_confirms():
    state = begin(at(T0, scanning=True), at(T0, scanning=True))
    assert run(state, at(T0, scanning=True), at(T1), at(T1, scanning=True), at(T2)) == \
        [False, False, False, True]


def test_a_straddler_followed_by_a_single_jump_does_not_confirm():
    """One completion after a straddler may be the straddler's own - it isn't proof."""
    state = begin(at(T0, scanning=True), at(T0, scanning=True))
    assert run(state, at(T1), at(T1), at(T1)) == [False, False, False]


def test_a_straddler_that_ended_and_a_new_scan_already_running_counts_the_new_one():
    """Seen as {moved, running}: the straddler is over and the scan now running began after it."""
    state = begin(at(T0, scanning=True), at(T0, scanning=True))
    assert run(state, at(T1, scanning=True), at(T2)) == [False, True]


def test_a_failed_straddler_then_an_advance_confirms():
    """
    A scan that fails ends with `scanning` false and lastScan where it was. That is taken as the
    straddler ENDING, and the answer after it gives the base; a scan running then began after it.
    """
    state = begin(at(T0, scanning=True), at(T0, scanning=True))
    state, confirmed = step(state, at(T0))
    assert not confirmed and state == WaitState(base=parse_time(T0), straddler=True, ending=True)
    assert run(state, at(T0, scanning=True), at(T1)) == [False, True]


def test_a_straddler_ending_inside_one_answer_cannot_confirm_on_its_own_end():
    """
    Navidrome reads lastScan before the running flag, so a straddler that writes its end between
    the two answers {old time, idle}; the next poll then sees its end. That end may have passed
    this folder before the tags changed, so it is the new base - and only the scan after counts.
    """
    state = begin(at(T0, scanning=True), at(T0, scanning=True))
    assert run(state, at(T0), at(T1)) == [False, False], "the straddler's own end is not proof"
    state, _ = step(step(state, at(T0))[0], at(T1))
    assert state == WaitState(base=parse_time(T1), straddler=False)
    assert run(state, at(T1, scanning=True), at(T2)) == [False, True], "one more completion is"


def test_an_ending_straddler_waits_out_an_unreadable_answer():
    state = begin(at(T0, scanning=True), at(T0, scanning=True))
    state, _ = step(state, at(T0))
    assert step(state, None) == (state, False)
    assert run(state, None, at(T1), at(T2)) == [False, False, True]


def test_a_straddler_seen_with_its_end_written_goes_straight_to_the_new_base():
    """Stopped AND moved: its end is on the answer already, so there is nothing to wait out."""
    state = begin(at(T0, scanning=True), at(T0, scanning=True))
    state, confirmed = step(state, at(T1))
    assert not confirmed and state == WaitState(base=parse_time(T1), straddler=False)
    assert run(state, at(T2)) == [True]


def test_an_answer_that_could_not_be_read_changes_nothing():
    state = begin(at(T0), at(T0))
    assert step(state, None) == (state, False)
    straddling = begin(at(T0, scanning=True), at(T0))
    assert step(straddling, None) == (straddling, False)


def test_a_last_scan_that_goes_backwards_cannot_lower_the_bar():
    """lastScan is the latest across libraries; one removed could move it back."""
    state = begin(at(T1, scanning=True), at(T1, scanning=True))
    state, _ = step(state, at(T0))
    assert state.base == parse_time(T1)
    assert run(state, at(T1)) == [False]


# ----- applying again after a hold -----

def test_after_a_hold_a_scan_past_the_base_lets_the_rename_go():
    held = WaitState(base=parse_time(T0), straddler=False)
    assert scanned_since_hold(held, parse_time(T0), at(T1))
    assert not scanned_since_hold(held, parse_time(T0), at(T0)), "nothing finished since"


def test_after_a_hold_with_a_straddler_unresolved_a_completion_is_not_enough():
    """The completion since may be the straddler's own; the ordinary wait decides from there."""
    for held in (WaitState(base=parse_time(T0), straddler=True),
                 WaitState(base=parse_time(T0), straddler=True, ending=True)):
        assert not scanned_since_hold(held, parse_time(T0), at(T2))


def test_after_a_hold_with_no_baseline_the_write_is_the_bar():
    """Navidrome couldn't be read at the hold; lastScan is compared with when the tags were written."""
    written = parse_time("2026-09-27T10:00:05Z")
    assert scanned_since_hold(None, written, at(T1))
    assert not scanned_since_hold(None, written, at(T0))


def test_the_cap_is_ninety_seconds_of_half_second_polls():
    assert (SCAN_WAIT_CAP_SECONDS, SCAN_POLL_SECONDS, SCAN_MAX_POLLS) == (90, 0.5, 180)
