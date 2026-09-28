"""
Applying a release writes the tags, waits, and only then renames the folder (v1.0.1).

Navidrome carries every user's plays, ratings, favourites and playlist entries across a folder
rename (same tags) and across a retag (same path) - but not both in one scan, where the old ids
simply go missing with everything on them. A one-step apply was exactly that. So when an apply
changes an id tag AND moves the folder, the route writes the tags, pauses RETAG_RENAME_WAIT
seconds for Navidrome's watcher to see them where the album already is, then renames.

With Navidrome set up (v1.0.3) the pause is no longer a guess: the route asks getScanStatus
until a scan that began after the tags were written has finished. Navidrome is replaced here by
httpx's MockTransport, answering each getScanStatus from a list, and asyncio.sleep is patched so
nothing actually waits - the rules for what an answer proves are pinned in test_scan_wait.py.
"""

import asyncio
import logging
import sys
from pathlib import Path
from types import SimpleNamespace

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from mutagen.flac import FLAC

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.api.navidrome_endpoint import navidrome  # noqa: E402
from src.config import Config, parse_rename_wait, rename_wait_seconds  # noqa: E402
from src.retag import (RENAME_HELD, RENAME_UNREACHABLE, changes_player_ids, execute_retag,  # noqa: E402
                       move_retagged, plan_retag)
from src.routes import library  # noqa: E402
from src.scan_wait import SCAN_MAX_POLLS, SCAN_WAIT_CAP_SECONDS  # noqa: E402
from tests.test_retag import RELEASE, seed  # noqa: E402

ALBUM = "Tame Impala/The Slow Rush (2020)"
RENAMED = "Tame Impala/The Slow Rush (2020) [Deluxe edition]"


@pytest.fixture(autouse=True)
def no_navidrome(monkeypatch):
    """
    Every test starts with Navidrome not set up, whatever the environment says - and with no
    rename held back and no album's lock taken, since both live in the process, not the request.
    """
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    monkeypatch.setattr(library, "_HELD_RENAMES", {})
    monkeypatch.setattr(library, "_APPLY_LOCKS", {})


# ----- which applies need the pause -----

def test_a_new_release_id_plus_a_rename_needs_the_pause(tmp_path):
    seed(tmp_path)
    plan = plan_retag(ALBUM, RELEASE, str(tmp_path))
    assert plan["moves"] and changes_player_ids(plan)


def test_a_rename_alone_does_not(tmp_path):
    """Same tags, new folder: Navidrome follows it as a move, nothing to wait for."""
    seed(tmp_path, musicbrainz_albumid="mbid-deluxe")
    plan = plan_retag(ALBUM, RELEASE, str(tmp_path))
    assert plan["moves"]
    assert not changes_player_ids(plan)


def test_a_retag_in_place_does_not(tmp_path):
    """New tags, same folder: Navidrome carries everything across on its own."""
    seed(tmp_path, folder="The Slow Rush (2020) [Deluxe edition]")
    plan = plan_retag(RENAMED, RELEASE, str(tmp_path))
    assert not plan["moves"]
    assert not changes_player_ids(plan)


# ----- the two halves -----

def test_the_tags_can_be_written_without_the_rename(tmp_path):
    directory = seed(tmp_path)
    plan = plan_retag(ALBUM, RELEASE, str(tmp_path))

    results = execute_retag(plan, RELEASE, "apply", move=False)
    assert results["tagged"] == 2 and results["moved_to"] is None
    assert directory.is_dir(), "still where it was"
    assert FLAC(str(directory / "01 - One More Year.flac"))["musicbrainz_albumid"] == ["mbid-deluxe"]

    move_retagged(plan, results)
    assert results["moved_to"] == str(tmp_path / RENAMED)
    assert not directory.exists() and (tmp_path / RENAMED).is_dir()


def test_a_failed_tag_write_still_leaves_the_folder_in_place(tmp_path):
    seed(tmp_path)
    plan = plan_retag(ALBUM, RELEASE, str(tmp_path))
    results = {"dry_run": False, "failed": 1, "moved_to": None, "problems": []}
    move_retagged(plan, results)
    assert results["moved_to"] is None
    assert "left the folder in place" in results["problems"][0]


# ----- the route -----

def client(monkeypatch, tmp_path, wait):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", wait)
    app = FastAPI()
    app.include_router(library.router, prefix="/deadwax/library")
    return TestClient(app)


def test_the_route_writes_tags_pauses_then_renames(monkeypatch, tmp_path):
    directory = seed(tmp_path)
    seen = []

    async def pause(seconds):
        #? at the moment of the pause: tags written, folder not yet moved
        tagged = FLAC(str(directory / "01 - One More Year.flac")).get("musicbrainz_albumid")
        seen.append((seconds, tagged, directory.is_dir()))

    monkeypatch.setattr(library.asyncio, "sleep", pause)
    response = client(monkeypatch, tmp_path, "7").post(
        "/deadwax/library/retag/apply", json={"album_path": ALBUM, "release": RELEASE})

    assert response.status_code == 200
    assert seen == [(7, ["mbid-deluxe"], True)]
    assert response.json()["results"]["moved_to"] == str(tmp_path / RENAMED)
    assert response.json()["results"]["rename_wait"] == 7


def test_zero_renames_straight_away(monkeypatch, tmp_path):
    seed(tmp_path)
    monkeypatch.setattr(library.asyncio, "sleep", lambda s: (_ for _ in ()).throw(AssertionError("paused")))
    response = client(monkeypatch, tmp_path, "0").post(
        "/deadwax/library/retag/apply", json={"album_path": ALBUM, "release": RELEASE})

    assert response.status_code == 200
    assert response.json()["results"]["moved_to"] == str(tmp_path / RENAMED)
    assert response.json()["results"]["rename_wait"] == 0


def test_the_preview_says_how_long_it_will_pause(monkeypatch, tmp_path):
    seed(tmp_path)
    plan = client(monkeypatch, tmp_path, "15").post(
        "/deadwax/library/retag/preview", json={"album_path": ALBUM, "release": RELEASE}).json()
    assert plan["rename_wait"] == 15


# ----- the setting -----

def test_the_setting_is_whole_seconds_from_0_to_300(monkeypatch):
    assert [parse_rename_wait(v) for v in ("0", "20", "300", "301", "-1", "2.5", "soon")] == \
        [0, 20, 300, None, None, None, None]
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", "garbage")
    assert rename_wait_seconds() == 20, "unreadable falls back to the default"
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", "0")
    assert rename_wait_seconds() == 0


# ----- after review (v1.0.2) -----

def test_a_target_that_appeared_during_the_pause_is_never_moved_into(tmp_path):
    """
    Two copies of one release applied back to back both planned a plain rename; the second
    shutil.move'd its folder INSIDE the first's. The rename now looks again before it moves.
    """
    directory = seed(tmp_path)
    plan = plan_retag(ALBUM, RELEASE, str(tmp_path))
    results = execute_retag(plan, RELEASE, "apply", move=False)

    (tmp_path / RENAMED).mkdir(parents=True)  # filed by something else during the pause
    move_retagged(plan, results)

    assert results["moved_to"] is None
    assert "appeared while waiting" in results["problems"][-1]
    assert directory.is_dir() and not any((tmp_path / RENAMED).iterdir())


def test_an_album_with_no_release_id_pauses_for_its_name_too(tmp_path):
    """With no release id, Navidrome keys the album on its name, artist and date instead."""
    seed(tmp_path, folder="Slow Rush", album="Slow Rsh")
    release = {**RELEASE, "release_mbid": None, "disambiguation": None}
    plan = plan_retag("Tame Impala/Slow Rush", release, str(tmp_path))
    assert plan["moves"]
    assert set().union(*(e["changes"] for e in plan["files"])) & {"album"}
    assert changes_player_ids(plan, release)
    assert not changes_player_ids(plan, {**release, "release_mbid": "x"}), "with an id, the name isn't one"


def test_the_saved_scan_is_refreshed_before_the_pause(monkeypatch, tmp_path):
    """A container stopped mid-pause must not restart onto a saved scan of the old tags."""
    seed(tmp_path)
    order = []
    monkeypatch.setattr(library, "forget_cached_album", lambda path: order.append(("forget", Path(path).name)))

    async def persist(request, scan=None):
        order.append(("persist",))

    async def pause(seconds):
        order.append(("pause",))

    monkeypatch.setattr(library, "_persist_cache", persist)
    monkeypatch.setattr(library.asyncio, "sleep", pause)
    client(monkeypatch, tmp_path, "5").post("/deadwax/library/retag/apply", json={"album_path": ALBUM, "release": RELEASE})

    assert order.index(("persist",)) < order.index(("pause",))
    assert order[0] == ("forget", "The Slow Rush (2020)")


def test_one_apply_per_album_at_a_time():
    assert library._apply_lock("A/B") is library._apply_lock("A/B")
    assert library._apply_lock("A/B") is not library._apply_lock("A/C")


# ----- asking Navidrome instead of counting (v1.0.3) -----

T0 = "2026-09-27T10:00:00.123456789Z"
T1 = "2026-09-27T10:00:07.5Z"
T2 = "2026-09-27T10:00:30Z"


def idle(last: str) -> dict:
    return {"scanStatus": {"scanning": False, "count": 40, "folderCount": 4, "lastScan": last}}


def busy(last: str) -> dict:
    return {"scanStatus": {"scanning": True, "count": 3, "folderCount": 1, "lastScan": last,
                           "scanType": "quick-selective"}}


def down(request: httpx.Request) -> httpx.Response:
    return httpx.Response(502)


@pytest.fixture
def slept(monkeypatch):
    """Every pause the route took, in seconds - none of them real."""
    pauses = []

    async def pause(seconds):
        pauses.append(seconds)

    monkeypatch.setattr(library.asyncio, "sleep", pause)
    return pauses


@pytest.fixture
def scans(monkeypatch, tmp_path):
    """
    Navidrome, set up and answering getScanStatus from `answers` in turn - the last one again
    once they run out. Each answer is a scanStatus body, or a function answering the request.
    Every call records whether the album was still where it was, with its new tags on.
    """
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")
    state = {"answers": [idle(T0)], "calls": []}
    directory = tmp_path / ALBUM

    def handle(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/rest/getScanStatus", "the only thing the wait may ask"
        first = directory / "01 - One More Year.flac"
        state["calls"].append(first.exists() and FLAC(str(first)).get("musicbrainz_albumid") == ["mbid-deluxe"])
        answers = state["answers"]
        answer = answers.pop(0) if len(answers) > 1 else answers[0]
        if callable(answer):
            return answer(request)
        return httpx.Response(200, json={"subsonic-response": {"status": "ok", "version": "1.16.1", **answer}})

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(handle),
                                         base_url="http://navidrome:4533/rest")
    yield state
    asyncio.run(navidrome.close_client())


def apply(monkeypatch, tmp_path, wait="7"):
    return client(monkeypatch, tmp_path, wait).post(
        "/deadwax/library/retag/apply", json={"album_path": ALBUM, "release": RELEASE})


def test_the_rename_follows_the_scan_navidrome_finished(monkeypatch, tmp_path, scans, slept):
    """The ordinary case: nothing running at the write, the watcher's scan starts and ends."""
    seed(tmp_path)
    scans["answers"] = [idle(T0), idle(T0), idle(T0), busy(T0), idle(T1)]

    results = apply(monkeypatch, tmp_path).json()["results"]

    assert scans["calls"] == [True] * 5, "asked five times, the tags on and the folder in place each time"
    assert results["moved_to"] == str(tmp_path / RENAMED)
    assert (results["rename_by"], results["rename_wait"]) == ("navidrome", SCAN_WAIT_CAP_SECONDS)
    assert slept == [0.5] * 3, "polled every half second - and no fixed pause"
    assert "rename_held" not in results


def test_a_scan_already_running_at_the_write_is_not_enough(monkeypatch, tmp_path, scans, slept):
    """Its end may have passed this folder before the tags changed; the NEXT scan is the proof."""
    seed(tmp_path)
    scans["answers"] = [busy(T0), busy(T0), idle(T1), idle(T1), busy(T1), idle(T2)]

    results = apply(monkeypatch, tmp_path).json()["results"]

    assert len(scans["calls"]) == 6 and all(scans["calls"]), "not renamed when the straddler ended"
    assert results["moved_to"] == str(tmp_path / RENAMED)


def test_no_scan_within_the_cap_holds_the_rename_back(monkeypatch, tmp_path, scans, slept):
    """Navidrome answering throughout and never scanning: renaming would be the one-step apply."""
    directory = seed(tmp_path)
    scans["answers"] = [idle(T0)]

    response = apply(monkeypatch, tmp_path)
    results = response.json()["results"]

    assert response.status_code == 200
    assert len(scans["calls"]) == 2 + SCAN_MAX_POLLS
    assert results["moved_to"] is None and results["rename_held"] is True
    assert RENAME_HELD in results["problems"]
    assert directory.is_dir() and not (tmp_path / RENAMED).exists()
    assert FLAC(str(directory / "01 - One More Year.flac"))["musicbrainz_albumid"] == ["mbid-deluxe"]


def test_applying_again_before_navidrome_has_scanned_holds_it_again(monkeypatch, tmp_path, scans, slept):
    """
    After a hold the tags on disk match, so nothing about the files says to wait - and a second
    click renaming at once, with Navidrome never having scanned, was the one-step apply itself
    (1.0.3 review). The hold is remembered, and the next apply asks Navidrome first.
    """
    directory = seed(tmp_path)
    scans["answers"] = [idle(T0)]
    apply(monkeypatch, tmp_path)
    scans["calls"].clear()

    results = apply(monkeypatch, tmp_path).json()["results"]

    assert len(scans["calls"]) == 2 + SCAN_MAX_POLLS, "getScanStatus asked, and the whole wait again"
    assert results["tagged"] == 0, "the tags were written by the first apply"
    assert results["moved_to"] is None and results["rename_held"] is True
    assert (results["rename_by"], results["rename_wait"]) == ("navidrome", SCAN_WAIT_CAP_SECONDS)
    assert RENAME_HELD in results["problems"]
    assert directory.is_dir() and not (tmp_path / RENAMED).exists()


def test_applying_again_after_a_scan_past_the_hold_renames_at_once(monkeypatch, tmp_path, scans, slept):
    """Navidrome has finished a scan since the hold: the baseline's two reads say so, no polling."""
    seed(tmp_path)
    scans["answers"] = [idle(T0)]
    apply(monkeypatch, tmp_path)
    scans["calls"].clear()
    slept.clear()

    scans["answers"] = [idle(T1)]
    results = apply(monkeypatch, tmp_path).json()["results"]

    assert len(scans["calls"]) == 2 and slept == []
    assert results["moved_to"] == str(tmp_path / RENAMED)
    assert results["rename_by"] == "navidrome" and "rename_held" not in results
    assert library._HELD_RENAMES == {}, "the hold ends with the rename"


def test_an_apply_queued_during_the_wait_asks_navidrome_too(monkeypatch, tmp_path, scans, slept):
    """
    Close the editor mid-wait, reopen the album, press Apply: the second request waits on the
    album's lock, then plans against a folder already tagged. It used to rename at once.
    """
    directory = seed(tmp_path)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", "7")
    scans["answers"] = [idle(T0)]
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace()))  # no store
    body = library.RetagRequest(album_path=ALBUM, release=RELEASE)
    order = []

    async def both():
        async def one(name):
            result = await library.retag_apply(request, body)
            order.append(name)
            return result["results"]
        return await asyncio.gather(one("first"), one("queued"))

    first, queued = asyncio.run(both())

    assert order == ["first", "queued"], "the second waited on the first"
    assert first["tagged"] == 2 and first["rename_held"] is True
    assert queued["tagged"] == 0 and queued["rename_held"] is True, "held again, not renamed"
    assert len(scans["calls"]) == 2 * (2 + SCAN_MAX_POLLS), "each of them asked Navidrome"
    assert directory.is_dir() and not (tmp_path / RENAMED).exists()


def test_the_preview_after_a_hold_says_it_waits_for_navidrome(monkeypatch, tmp_path, scans, slept):
    """So the editor says what the next Apply will do, and its button says what it is doing."""
    seed(tmp_path)
    scans["answers"] = [idle(T0)]
    apply(monkeypatch, tmp_path)

    preview = client(monkeypatch, tmp_path, "7").post(
        "/deadwax/library/retag/preview", json={"album_path": ALBUM, "release": RELEASE}).json()

    assert preview["changed_file_count"] == 0
    assert (preview["rename_by"], preview["rename_wait"]) == ("navidrome", SCAN_WAIT_CAP_SECONDS)


def test_a_hold_ends_when_applying_the_album_no_longer_moves_it(monkeypatch, tmp_path, scans, slept):
    seed(tmp_path)
    scans["answers"] = [idle(T0)]
    apply(monkeypatch, tmp_path)
    assert list(library._HELD_RENAMES) == [ALBUM]

    #? the same release without its edition names the folder the album is already in
    stay = {**RELEASE, "disambiguation": None}
    results = client(monkeypatch, tmp_path, "7").post(
        "/deadwax/library/retag/apply", json={"album_path": ALBUM, "release": stay}).json()["results"]

    assert results["moved_to"] is None and "rename_held" not in results
    assert library._HELD_RENAMES == {}


def test_after_a_hold_with_navidrome_no_longer_set_up_it_renames_in_one_step(monkeypatch, tmp_path, scans, slept):
    """Nothing to ask any more - which is how every apply stood before there was."""
    seed(tmp_path)
    scans["answers"] = [idle(T0)]
    apply(monkeypatch, tmp_path)
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    scans["calls"].clear()

    results = apply(monkeypatch, tmp_path).json()["results"]

    assert scans["calls"] == [] and results["rename_by"] is None
    assert results["moved_to"] == str(tmp_path / RENAMED)
    assert library._HELD_RENAMES == {}


def test_a_baseline_navidrome_wont_give_means_the_fixed_wait(monkeypatch, tmp_path, scans, slept, caplog):
    seed(tmp_path)
    scans["answers"] = [down]

    with caplog.at_level(logging.INFO):
        results = apply(monkeypatch, tmp_path, wait="7").json()["results"]

    assert len(scans["calls"]) == 1, "the second read isn't taken once the first has failed"
    assert slept == [7]
    assert results["moved_to"] == str(tmp_path / RENAMED)
    assert (results["rename_by"], results["rename_wait"]) == ("timer", 7)
    assert "couldn't ask Navidrome" in caplog.text and "502" in caplog.text


def test_an_unreadable_second_read_means_the_fixed_wait_too(monkeypatch, tmp_path, scans, slept):
    seed(tmp_path)
    scans["answers"] = [idle(T0), {"scanStatus": {"scanning": False}}, idle(T1)]

    results = apply(monkeypatch, tmp_path, wait="7").json()["results"]

    assert len(scans["calls"]) == 2 and slept == [7]
    assert results["rename_by"] == "timer"


def test_each_question_is_bounded_on_its_own(monkeypatch, tmp_path, scans, slept):
    """
    The client waits a minute for a stream; a scan status that doesn't come in 5s isn't coming.
    No answer in time is Navidrome not being there, so the rename is held back (1.0.3 review).
    """
    directory = seed(tmp_path)
    monkeypatch.setattr(library, "SCAN_CALL_TIMEOUT_SECONDS", 0.05)

    async def never(request):
        await asyncio.Event().wait()

    scans["answers"] = [never]

    results = apply(monkeypatch, tmp_path, wait="7").json()["results"]

    assert len(scans["calls"]) == 1 and slept == [], "asked once, and no fixed pause"
    assert results["rename_held"] is True and RENAME_UNREACHABLE in results["problems"]
    assert directory.is_dir() and not (tmp_path / RENAMED).exists()


def test_answers_that_cannot_be_used_after_the_baseline_rename_as_the_fixed_wait_would(
        monkeypatch, tmp_path, scans, slept, caplog):
    """Something answered every poll, never usably: no evidence either way, where the fixed wait stood."""
    seed(tmp_path)
    scans["answers"] = [idle(T0), idle(T0), down]

    with caplog.at_level(logging.INFO):
        results = apply(monkeypatch, tmp_path).json()["results"]

    assert len(scans["calls"]) == 2 + SCAN_MAX_POLLS
    assert results["moved_to"] == str(tmp_path / RENAMED)
    assert results["rename_by"] == "navidrome" and "rename_held" not in results
    assert "stopped answering" in caplog.text


def test_a_refused_login_at_the_baseline_means_the_fixed_wait(monkeypatch, tmp_path, scans, slept):
    """An answer that arrives and can't be used is not Navidrome being away."""
    seed(tmp_path)
    scans["answers"] = [lambda request: httpx.Response(200, json={"subsonic-response": {
        "status": "failed", "version": "1.16.1", "error": {"code": 40, "message": "Wrong username or password"}}})]

    results = apply(monkeypatch, tmp_path, wait="7").json()["results"]

    assert slept == [7] and results["rename_by"] == "timer"
    assert results["moved_to"] == str(tmp_path / RENAMED)


# ----- Navidrome not there at all (1.0.3 review) -----

def refused(request: httpx.Request) -> httpx.Response:
    """What a Navidrome container that is down or restarting looks like from here."""
    raise httpx.ConnectError("All connection attempts failed", request=request)


def test_navidrome_unreachable_at_the_baseline_holds_the_rename(monkeypatch, tmp_path, scans, slept, caplog):
    """
    It may be restarting - and Navidrome scans on start-up by default, so a rename made now would
    land in that scan with the new tags. The fixed wait renamed; the folder stays instead.
    """
    directory = seed(tmp_path)
    scans["answers"] = [refused]

    with caplog.at_level(logging.INFO):
        results = apply(monkeypatch, tmp_path).json()["results"]

    assert len(scans["calls"]) == 1 and slept == []
    assert results["moved_to"] is None and results["rename_held"] is True
    assert RENAME_UNREACHABLE in results["problems"] and RENAME_HELD not in results["problems"]
    assert (results["rename_by"], results["rename_wait"]) == ("navidrome", SCAN_WAIT_CAP_SECONDS)
    assert directory.is_dir() and not (tmp_path / RENAMED).exists()
    assert "couldn't be reached" in caplog.text and "All connection attempts failed" in caplog.text
    assert "hunter2" not in caplog.text


def test_navidrome_going_away_after_the_baseline_holds_the_rename(monkeypatch, tmp_path, scans, slept):
    directory = seed(tmp_path)
    scans["answers"] = [idle(T0), idle(T0), refused]

    results = apply(monkeypatch, tmp_path).json()["results"]

    assert len(scans["calls"]) == 2 + SCAN_MAX_POLLS
    assert results["rename_held"] is True and RENAME_UNREACHABLE in results["problems"]
    assert directory.is_dir()


def test_navidrome_back_and_scanned_after_an_unreachable_hold_renames(monkeypatch, tmp_path, scans, slept):
    """No baseline was read at the hold, so a lastScan after the tags were written is the proof."""
    seed(tmp_path)
    scans["answers"] = [refused]
    apply(monkeypatch, tmp_path)
    scans["calls"].clear()

    scans["answers"] = [idle("2999-01-01T00:00:00Z")]
    results = apply(monkeypatch, tmp_path).json()["results"]

    assert len(scans["calls"]) == 2
    assert results["moved_to"] == str(tmp_path / RENAMED)


def test_navidrome_back_but_not_yet_scanned_after_an_unreachable_hold_holds_again(
        monkeypatch, tmp_path, scans, slept):
    directory = seed(tmp_path)
    scans["answers"] = [refused]
    apply(monkeypatch, tmp_path)

    scans["answers"] = [idle("2000-01-01T00:00:00Z")]  # its last scan was before the tags
    results = apply(monkeypatch, tmp_path).json()["results"]

    assert results["rename_held"] is True and RENAME_HELD in results["problems"]
    assert directory.is_dir()


def test_navidrome_still_away_keeps_the_hold_it_had(monkeypatch, tmp_path, scans, slept):
    """A hold with a baseline, then Navidrome unreachable on the next apply: the baseline stands."""
    seed(tmp_path)
    scans["answers"] = [idle(T0)]
    apply(monkeypatch, tmp_path)
    held = library._HELD_RENAMES[ALBUM]

    scans["answers"] = [refused]
    results = apply(monkeypatch, tmp_path).json()["results"]

    assert RENAME_UNREACHABLE in results["problems"]
    assert library._HELD_RENAMES[ALBUM] == held, "the same base, and the same moment the tags were written"


def test_without_navidrome_it_is_the_fixed_wait(monkeypatch, tmp_path, slept):
    seed(tmp_path)

    results = apply(monkeypatch, tmp_path, wait="7").json()["results"]

    assert slept == [7]
    assert (results["rename_by"], results["rename_wait"]) == ("timer", 7)


def test_zero_renames_at_once_whatever_navidrome_says(monkeypatch, tmp_path, scans, slept):
    seed(tmp_path)

    results = apply(monkeypatch, tmp_path, wait="0").json()["results"]

    assert scans["calls"] == [] and slept == []
    assert results["moved_to"] == str(tmp_path / RENAMED)
    assert (results["rename_by"], results["rename_wait"]) == (None, 0)


def test_the_saved_scan_is_refreshed_before_navidrome_is_asked(monkeypatch, tmp_path, scans, slept):
    seed(tmp_path)
    order = []

    async def persist(request, scan=None):
        order.append("persist")

    def answer(request):
        order.append("asked")
        #? the baseline and one poll at T0, then a finished scan
        last = T1 if order.count("asked") > 3 else T0
        return httpx.Response(200, json={"subsonic-response": {"status": "ok", **idle(last)}})

    monkeypatch.setattr(library, "_persist_cache", persist)
    scans["answers"] = [answer]
    results = apply(monkeypatch, tmp_path).json()["results"]

    assert order.index("persist") < order.index("asked")
    assert results["moved_to"] == str(tmp_path / RENAMED)


def test_the_preview_says_whether_it_waits_for_navidrome(monkeypatch, tmp_path, scans):
    seed(tmp_path)
    preview = client(monkeypatch, tmp_path, "15").post(
        "/deadwax/library/retag/preview", json={"album_path": ALBUM, "release": RELEASE}).json()

    assert (preview["rename_by"], preview["rename_wait"]) == ("navidrome", SCAN_WAIT_CAP_SECONDS)
    assert scans["calls"] == [], "a preview asks Navidrome nothing"


def test_the_preview_without_navidrome_names_the_timer(monkeypatch, tmp_path):
    seed(tmp_path)
    preview = client(monkeypatch, tmp_path, "15").post(
        "/deadwax/library/retag/preview", json={"album_path": ALBUM, "release": RELEASE}).json()

    assert (preview["rename_by"], preview["rename_wait"]) == ("timer", 15)


def test_an_address_the_client_refuses_means_the_fixed_wait(monkeypatch, tmp_path, scans, slept):
    """Navidrome can't be asked at such an address, so the apply doesn't try - and says so first."""
    seed(tmp_path)
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://james:hunter2@navidrome:4533")
    preview = client(monkeypatch, tmp_path, "7").post(
        "/deadwax/library/retag/preview", json={"album_path": ALBUM, "release": RELEASE}).json()
    results = apply(monkeypatch, tmp_path).json()["results"]

    assert preview["rename_by"] == "timer" and results["rename_by"] == "timer"
    assert scans["calls"] == [] and slept == [7]
    assert results["moved_to"] == str(tmp_path / RENAMED)


def test_an_apply_in_one_step_says_so_in_its_preview(monkeypatch, tmp_path, scans):
    """Same tags, new folder: nothing to wait for, Navidrome or not."""
    seed(tmp_path, musicbrainz_albumid="mbid-deluxe")
    preview = client(monkeypatch, tmp_path, "15").post(
        "/deadwax/library/retag/preview", json={"album_path": ALBUM, "release": RELEASE}).json()

    assert (preview["rename_by"], preview["rename_wait"]) == (None, 0)
