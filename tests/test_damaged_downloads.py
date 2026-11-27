"""
A damaged download is refused, and the next source says how it differs (asked for, 27 Nov; the review's fixes).

James: "Let's avoid trimming for now and just move on to the next peer with some sort of message about it so I know
what happened." / "Actually I want it to tell me the differences in the next peer." / "Actually if the download file
is bad, then it should go ahead and move to the next peer regardless".

Held here, through the real organizer, poller, store and /jobs route, on synthetic FLACs (tests/test_flac_mp4.py's
encoder): one damaged song refuses the whole album from that source - nothing moved, nothing changed; the job moves
to its next source by itself, AUTO_RETRY_PEER off or on (once), and the row and the log say what was wrong and how
the new source differs; with none left it fails saying so. The refused files are kept in the store (refused_files)
and never filed by any job: not the next source's - whose files slskd writes beside them as `name_<ticks>.flac`
when the names collide (its FileService.MoveFile, Destination.Exists = rename by default) - not a fresh Get's, not
after a restart. The refusal is one transaction, and a stop before the move still moves on at the next poll; a stop
during the check is checked again. The comparison's rules - deadwax's own scores, the four verdicts - are held on
source_compare directly.
"""

import asyncio
import logging
import os
import sys
import threading
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import organizer, poller  # noqa: E402
from src.config import Config  # noqa: E402
from src.flac_check import OK as CHECKED_OK, Verdict, check_file  # noqa: E402
from src.organizer import execute_plan, file_identity, find_local_file, plan_organization  # noqa: E402
from src.poller import (INTERRUPTED_FILING, check_again, forget_gone_refusals, poll_downloads_once,  # noqa: E402
                        refile_refused, retry_next_peer, retry_same_peer, settle_interrupted_filing,
                        tidy_cancelled_on_start)
from src.routes.download import next_source_key  # noqa: E402
from src.source_compare import (AS_GOOD, BETTER, DIFFERENT, WEAKER, compare, match_score, next_source,  # noqa: E402
                                source_facts)
from src.store import JobStore  # noqa: E402
from tests.test_flac_mp4 import encode  # noqa: E402

TITLES = ["Krakow", "Glass", "Static"]
TRACKS = [{"position": n, "disc": 1, "title": title} for n, title in enumerate(TITLES, 1)]
RELEASE = {"artist": "Dummy Band", "album": "Album", "year": "2001", "release_mbid": "mb-damaged", "tracks": TRACKS}
#? each source's folder on its share - slskd names the local folder after the last of it
FOLDERS = {"glassbeads": "Album (2001) [FLAC]", "sofaking": "Dummy Band - Album", "thirdpeer": "Album"}
FLAC_16 = {"formats": ["flac"], "bit_depths": [16], "sample_rates": [44100]}
FLAC_24 = {"formats": ["flac"], "bit_depths": [24], "sample_rates": [96000]}
MP3_320 = {"formats": ["mp3"], "bitrates": [320]}
#? DateTime.UtcNow.Ticks, as slskd appends it to a name that's taken
TICKS = "639001234567890123"


def song(seed: int) -> bytes:
    return encode(seed=seed, blocks=(4096, 4096, 500))[0]


def stale(data: bytes, extra: int = 2000) -> bytes:
    """The report's copy loop: what follows the true end repeats the stretch 6,144 bytes before it."""
    return data + data[len(data) - 6144:len(data) - 6144 + extra]


def remote(peer: str, n: int, extension: str = "flac") -> str:
    return f"share\\{FOLDERS[peer]}\\0{n} - {TITLES[n - 1]}.{extension}"


def files_of(peer: str, extension: str = "flac", size: int = 30_000_000) -> list[dict]:
    return [{"filename": remote(peer, n, extension), "size": size} for n in range(1, 4)]


def lay_down(downloads: Path, peer: str, damaged: dict[int, bytes] | None = None, seed: int = 0,
             suffix: str = "", extras: dict[str, bytes] | None = None) -> dict[str, bytes]:
    """The peer's files as slskd leaves them: in a folder named after the peer's, each song's bytes - a damaged one
    in place of the clean one for each song number in `damaged` - `suffix` after each name's stem (slskd's
    `_<ticks>` for a name that was taken), and any `extras` (a cover, a log) beside them."""
    folder = downloads / FOLDERS[peer]
    folder.mkdir(parents=True, exist_ok=True)
    written = {}
    for n in range(1, 4):
        data = (damaged or {}).get(n) or song(seed * 10 + n)
        path = folder / f"0{n} - {TITLES[n - 1]}{suffix}.flac"
        path.write_bytes(data)
        written[path.name] = data
    for name, data in (extras or {}).items():
        (folder / name).write_bytes(data)
        written[name] = data
    return written


def alternative(peer: str, quality: dict | None = None, extension: str = "flac", **card) -> dict:
    return {"username": peer, "directory": f"share\\{FOLDERS[peer]}", "files": files_of(peer, extension),
            "quality": quality or FLAC_16, "has_free_slot": True, "queue_length": 0, **card}


class Slskd:
    """slskd: every file of each peer named in `done` finished; asked to queue, it accepts unless the peer is in
    `declines`. A transfer it is told to remove leaves its list, and a peer asked again starts new transfers."""

    def __init__(self, done: dict[str, list[dict]] | None = None, declines=()):
        self.done = dict(done or {})
        self.declines = set(declines)
        self.asked: list[str] = []
        self.removed: list[tuple[str, str]] = []
        self.attempt: dict[str, int] = {}

    async def get_downloads(self, usernames=()):
        wanted = set(usernames)
        gone = {transfer for _, transfer in self.removed}
        return [{"username": peer, "directories": [{"directory": "d", "files": [
            {"id": transfer, "filename": f["filename"], "state": "Completed, Succeeded", "percentComplete": 100.0,
             "averageSpeed": 100000, "size": f["size"]}
            for i, f in enumerate(files) if (transfer := f"{peer}-{self.attempt.get(peer, 0)}-{i}") not in gone]}]}
            for peer, files in self.done.items() if peer in wanted]

    async def enqueue(self, username, files):
        self.asked.append(username)
        if username in self.declines:
            return False, f"{username} refused"
        self.attempt[username] = self.attempt.get(username, 0) + 1
        return True, ""

    async def cancel_download(self, username, transfer_id, remove=False):
        self.removed.append((username, transfer_id))
        return True


def run(awaitable):
    return asyncio.run(awaitable)


@pytest.fixture
def setup(tmp_path, monkeypatch):
    downloads, library = tmp_path / "downloads", tmp_path / "music"
    downloads.mkdir()
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(downloads))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(library))
    monkeypatch.setattr(Config, "SLSKD_INCOMPLETE_PATH", None)
    monkeypatch.setattr(Config, "FETCH_LYRICS", "off")
    #? off: the move to the next source is the refusal's own, never AUTO_RETRY_PEER's
    monkeypatch.setattr(Config, "AUTO_RETRY_PEER", "off")
    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()
    return downloads, library, store


def queue(store, alternatives=(), quality=None, peer="glassbeads", release=None, source=None) -> int:
    """A job as the app's Get makes one: the peer's folder and files, its quality, the runners-up - and none of the
    card's score (the iPhone and Mac apps send none; deadwax scores both sources itself)."""
    return run(store.create_job(peer, f"share\\{FOLDERS[peer]}", files_of(peer), release or RELEASE,
                                list(alternatives), quality=quality or FLAC_16,
                                source=source if source is not None else {"has_free_slot": True, "queue_length": 0}))


def everything_under(root: Path) -> dict[str, bytes]:
    return {str(p.relative_to(root)): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file()} if root.exists() else {}


def library_names(library: Path) -> list[str]:
    return sorted(p.name for p in library.rglob("*") if p.is_file())


# --- the plan: one damaged song refuses the album ---------------------------------------------------------------

def test_one_damaged_song_refuses_the_whole_album_and_nothing_moves(setup):
    downloads, library, _ = setup
    before = lay_down(downloads, "glassbeads", {2: stale(song(2))})
    job = {"id": 1, "username": "glassbeads", "directory": f"share\\{FOLDERS['glassbeads']}",
           "files": files_of("glassbeads"), "release": RELEASE}

    plan = plan_organization(job, str(downloads), str(library))
    assert [(d["file"], d["kind"]) for d in plan["damaged"]] == [("02 - Glass.flac", "stale_tail")]
    assert plan["damaged"][0]["extra"] == 2000 and plan["songs"] == 3

    results = execute_plan(plan, RELEASE)
    assert results["damaged"] and results["organized"] == 0
    assert everything_under(library) == {}
    #? every song still where slskd put it, byte for byte - the clean ones too
    assert {p.name: p.read_bytes() for p in (downloads / FOLDERS["glassbeads"]).iterdir()} == before


def test_a_whole_album_is_planned_and_filed_as_before(setup):
    downloads, library, _ = setup
    lay_down(downloads, "glassbeads")
    job = {"id": 1, "username": "glassbeads", "directory": f"share\\{FOLDERS['glassbeads']}",
           "files": files_of("glassbeads"), "release": RELEASE}

    plan = plan_organization(job, str(downloads), str(library))
    assert plan["damaged"] == []
    assert execute_plan(plan, RELEASE)["tracks_organized"] == 3


def test_a_plan_made_only_to_see_a_refusal_holds_checks_nothing(setup):
    downloads, library, _ = setup
    lay_down(downloads, "glassbeads", {1: stale(song(1))})
    job = {"id": 1, "username": "glassbeads", "directory": f"share\\{FOLDERS['glassbeads']}",
           "files": files_of("glassbeads"), "release": RELEASE}
    assert plan_organization(job, str(downloads), str(library), check_audio=False)["damaged"] == []


# --- finding the next source's files beside the refused ones ---------------------------------------------------

def test_slskds_renamed_file_is_found_and_the_newest_not_refused_wins(tmp_path):
    """slskd's FileService.MoveFile: a name that's taken is written as `{stem}_{DateTime.UtcNow.Ticks}{ext}`."""
    folder = tmp_path / "downloads" / "Album"
    folder.mkdir(parents=True)
    first, second, third = (folder / "01 - Krakow.flac", folder / f"01 - Krakow_{TICKS}.flac",
                            folder / "01 - Krakow_639001234567999999.flac")
    for at, path in enumerate((first, second, third)):
        path.write_bytes(b"x" * (10 + at))
        os.utime(path, ns=(10**18 + at * 10**9, 10**18 + at * 10**9))
    remote_name = "share\\Album\\01 - Krakow.flac"
    downloads = str(tmp_path / "downloads")
    assert find_local_file(downloads, remote_name) == third
    assert find_local_file(downloads, remote_name, skip={file_identity(third)}) == second
    assert find_local_file(downloads, remote_name, skip={file_identity(p) for p in (second, third)}) == first
    #? the size the peer reported outranks the newest
    assert find_local_file(downloads, remote_name, size=11) == second
    #? a name's own digits are not slskd's: "Track_2", "Live_1999" stay other files
    (folder / "01 - Krakow_1999.flac").write_bytes(b"y")
    assert find_local_file(downloads, "share\\Album\\01 - Krakow_1999.flac") == folder / "01 - Krakow_1999.flac"
    assert find_local_file(downloads, remote_name, skip={file_identity(p) for p in (first, second, third)}) is None


# --- the poller: moved on by itself -------------------------------------------------------------------------

def test_a_damaged_download_moves_to_the_next_source_with_auto_retry_off(setup, caplog):
    downloads, library, store = setup
    refused = lay_down(downloads, "glassbeads", {1: stale(song(1)), 3: stale(song(3), 900)})
    job_id = queue(store, [alternative("sofaking")])
    slskd = Slskd({"glassbeads": files_of("glassbeads")})

    with caplog.at_level(logging.WARNING):
        run(poll_downloads_once(slskd, store, {}))

    job = run(store.get_job(job_id))
    assert (job["status"], job["username"], job["error"]) == ("queued", "sofaking", None)
    assert slskd.asked == ["sofaking"]
    said = ("The copy from glassbeads was damaged (extra data after the end of 2 of 3 songs). "
            "Now coming from sofaking, as good a match: same quality, songs and edition.")
    assert job["notice"]["text"] == said
    assert (job["notice"]["from"], job["notice"]["to"], job["notice"]["verdict"]) == ("glassbeads", "sofaking", AS_GOOD)
    #? the notice carries the comparison as /jobs' next_source does
    assert job["notice"]["lead"] == "Next: sofaking · FLAC 16/44.1 · 100%"
    assert job["notice"]["facts"]["username"] == "sofaking" and job["notice"]["was"]["username"] == "glassbeads"
    assert "moving" not in job["notice"]
    assert said in caplog.text
    #? the refused source remembered with why; every one of its files in the store's refused_files, for every job
    first = job["tried"][0]
    assert first["username"] == "glassbeads" and first["damaged"] == "extra data after the end of 2 of 3 songs"
    assert sorted(Path(path).name for path, _, _ in run(store.refused_files())) == sorted(refused)
    #? nothing filed, nothing of it changed; its transfers out of slskd's list, as a cancel's go
    assert everything_under(library) == {}
    assert {p.name: p.read_bytes() for p in (downloads / FOLDERS["glassbeads"]).iterdir()} == refused
    assert {name for name, _ in slskd.removed} == {"glassbeads"}


def test_with_auto_retry_peer_on_it_moves_once(setup, monkeypatch):
    """(review) The refusal's own move is the only one: AUTO_RETRY_PEER's never moves it a second time."""
    downloads, _, store = setup
    monkeypatch.setattr(Config, "AUTO_RETRY_PEER", "on")
    lay_down(downloads, "glassbeads", {1: stale(song(1))})
    job_id = queue(store, [alternative("sofaking"), alternative("thirdpeer")])
    slskd = Slskd({"glassbeads": files_of("glassbeads")})
    run(poll_downloads_once(slskd, store, {}))
    run(poll_downloads_once(slskd, store, {}))
    assert slskd.asked == ["sofaking"]
    assert run(store.get_job(job_id))["username"] == "sofaking"


def test_the_next_sources_download_is_filed_and_never_the_refused_files(setup):
    downloads, library, store = setup
    lay_down(downloads, "glassbeads", {1: stale(song(1))})
    job_id = queue(store, [alternative("sofaking")])
    slskd = Slskd({"glassbeads": files_of("glassbeads")})
    run(poll_downloads_once(slskd, store, {}))

    #? sofaking's whole copy arrives in a folder of its own
    whole = lay_down(downloads, "sofaking", seed=5)
    slskd.done["sofaking"] = files_of("sofaking")
    run(poll_downloads_once(slskd, store, {}))

    job = run(store.get_job(job_id))
    assert job["status"] == "organized"
    filed = sorted(p for p in library.rglob("*.flac"))
    assert sorted(p.name for p in filed) == sorted(whole)
    assert all(check_file(p).kind == "ok" for p in filed)
    assert not any((downloads / FOLDERS["sofaking"]).glob("*.flac"))
    #? glassbeads' refused copy is still in slskd's folder, whole
    assert len(list((downloads / FOLDERS["glassbeads"]).iterdir())) == 3


def test_the_same_folder_and_names_every_song_of_the_new_source_is_filed_after_a_restart(setup, tmp_path):
    """
    (review) Soulseek copies often share a folder name. The second source's songs go into the first's folder, and
    every name is taken, so slskd writes each as `name_<ticks>.flac`. After a restart, every song of the new
    source is filed - found under slskd's names - and nothing of the refused copy: its songs stay where they are,
    byte for byte, and its cover and rip log are never filed with the new source's album, whose own cover is filed
    as cover.jpg.
    """
    downloads, library, store = setup
    FOLDERS["sofaking"] = FOLDERS["glassbeads"]
    try:
        refused = lay_down(downloads, "glassbeads", {2: stale(song(2))},
                           extras={"cover.jpg": b"glassbeads' cover", "glassbeads.log": b"EAC log"})
        job_id = queue(store, [alternative("sofaking")])
        slskd = Slskd({"glassbeads": files_of("glassbeads")})
        run(poll_downloads_once(slskd, store, {}))
        assert run(store.get_job(job_id))["username"] == "sofaking"

        #? a restart: the store opened again, and every step the poller takes as it starts
        store = JobStore(str(tmp_path / "jobs.db"))
        store.init()
        run(settle_interrupted_filing(store))
        run(check_again(store, slskd))
        run(forget_gone_refusals(store))
        run(refile_refused(store, slskd))
        theirs = lay_down(downloads, "sofaking", seed=7, suffix=f"_{TICKS}", extras={f"cover_{TICKS}.jpg": b"sofaking's"})
        slskd.done["sofaking"] = files_of("sofaking")
        run(poll_downloads_once(slskd, store, {}))

        job = run(store.get_job(job_id))
        assert job["status"] == "organized", job["error"]
        assert library_names(library) == ["01 - Krakow.flac", "02 - Glass.flac", "03 - Static.flac", "cover.jpg"]
        assert next(library.rglob("cover.jpg")).read_bytes() == b"sofaking's"
        folder = downloads / FOLDERS["glassbeads"]
        #? the refused copy untouched in slskd's folder; the new source's songs all moved out of it
        assert {name: (folder / name).read_bytes() for name in refused} == refused
        assert not any((folder / name).exists() for name in theirs)
    finally:
        FOLDERS["sofaking"] = "Dummy Band - Album"


def test_a_fresh_get_of_the_album_never_files_the_refused_copy(setup):
    """(review) The refused files are the store's (refused_files), not the job's: a new job for the album - which
    never knew of the refusal - passes over them too."""
    downloads, library, store = setup
    lay_down(downloads, "glassbeads", {2: stale(song(2))}, extras={"glassbeads.log": b"EAC log"})
    first = queue(store)
    slskd = Slskd({"glassbeads": files_of("glassbeads")})
    run(poll_downloads_once(slskd, store, {}))
    assert run(store.get_job(first))["status"] == "failed"
    run(store.delete_jobs(("failed",)))

    #? a fresh Get from thirdpeer, its folder named as glassbeads' was: slskd writes beside the refused files
    FOLDERS["thirdpeer"] = FOLDERS["glassbeads"]
    try:
        fresh = queue(store, peer="thirdpeer")
        lay_down(downloads, "thirdpeer", seed=8, suffix=f"_{TICKS}")
        slskd.done["thirdpeer"] = files_of("thirdpeer")
        run(poll_downloads_once(slskd, store, {}))
        assert run(store.get_job(fresh))["status"] == "organized"
        assert library_names(library) == ["01 - Krakow.flac", "02 - Glass.flac", "03 - Static.flac"]
    finally:
        FOLDERS["thirdpeer"] = "Album"


def test_a_weaker_next_source_says_how_it_is_weaker(setup):
    downloads, library, store = setup
    lay_down(downloads, "glassbeads", {1: stale(song(1))})
    job_id = queue(store, [alternative("sofaking", quality=MP3_320, extension="mp3")])
    run(poll_downloads_once(Slskd({"glassbeads": files_of("glassbeads")}), store, {}))

    notice = run(store.get_job(job_id))["notice"]
    assert notice["text"] == ("The copy from glassbeads was damaged (extra data after the end of 1 of 3 songs). "
                              "Now coming from sofaking, a weaker match: MP3 320, was FLAC 16/44.1 · match 91%, was 100%"
                              " (format 45, was 100).")
    assert notice["verdict"] == WEAKER


def test_with_no_other_source_it_fails_saying_so(setup):
    downloads, library, store = setup
    lay_down(downloads, "glassbeads", {3: stale(song(3))})
    job_id = queue(store)
    slskd = Slskd({"glassbeads": files_of("glassbeads")})
    run(poll_downloads_once(slskd, store, {}))

    job = run(store.get_job(job_id))
    said = "The copy from glassbeads was damaged (extra data after the end of 1 of 3 songs) and there is no other source."
    assert (job["status"], job["error"]) == ("failed", said)
    assert job["notice"]["text"] == said and job["notice"]["to"] is None and "moving" not in job["notice"]
    assert slskd.asked == [] and everything_under(library) == {}
    #? its transfers out of slskd's list, as a cancelled download's go; its files stay in slskd's folder
    assert {name for name, _ in slskd.removed} == {"glassbeads"}
    assert len(list((downloads / FOLDERS["glassbeads"]).iterdir())) == 3


def test_a_cut_short_and_a_broken_song_are_named_so(setup):
    downloads, library, store = setup
    data, frames = encode(seed=40, blocks=(4096, 4096, 4096, 500))
    broken = bytearray(data)
    broken[frames[1][0] + 300] ^= 0x08
    lay_down(downloads, "glassbeads", {1: song(1)[:-2000], 2: bytes(broken)})
    job_id = queue(store)
    run(poll_downloads_once(Slskd({"glassbeads": files_of("glassbeads")}), store, {}))
    assert run(store.get_job(job_id))["error"] == (
        "The copy from glassbeads was damaged (1 of 3 songs is cut short; 1 of 3 songs is damaged inside) "
        "and there is no other source.")


def test_a_later_move_replaces_the_notice(setup):
    """(review) A second damaged copy says so of itself, and a move by hand ("Another source") clears it."""
    downloads, _, store = setup
    lay_down(downloads, "glassbeads", {1: stale(song(1))})
    job_id = queue(store, [alternative("sofaking"), alternative("thirdpeer")])
    slskd = Slskd({"glassbeads": files_of("glassbeads")})
    run(poll_downloads_once(slskd, store, {}))
    lay_down(downloads, "sofaking", {3: song(3)[:-100]}, seed=4)
    slskd.done["sofaking"] = files_of("sofaking")
    run(poll_downloads_once(slskd, store, {}))

    job = run(store.get_job(job_id))
    assert job["username"] == "thirdpeer"
    assert job["notice"]["text"].startswith("The copy from sofaking was damaged (1 of 3 songs is cut short). "
                                            "Now coming from thirdpeer")
    run(store.update_status(job_id, "failed", "the peer refused to send it"))
    assert run(store.get_job(job_id))["notice"]["from"] == "sofaking"
    run(store.move_to_peer(job_id, "fourth", "share\\x", files_of("glassbeads"), job["tried"]))
    assert run(store.get_job(job_id))["notice"] is None


# --- stops ---------------------------------------------------------------------------------------------------

def test_a_stop_between_the_refusal_and_the_move_moves_on_at_the_next_poll(setup, tmp_path, monkeypatch):
    """(review) The refusal - failed, the source's `tried` entry, the notice still `moving`, the refused files - is
    one transaction, and the move another step: a stop between them finds it all written, and the next poll (after
    the restart) makes the move."""
    downloads, _, store = setup
    lay_down(downloads, "glassbeads", {1: stale(song(1))})
    job_id = queue(store, [alternative("sofaking")])
    slskd = Slskd({"glassbeads": files_of("glassbeads")})

    async def stopped(*args, **kwargs):
        raise asyncio.CancelledError

    monkeypatch.setattr(poller, "retry_next_peer", stopped)
    with pytest.raises(asyncio.CancelledError):
        run(poll_downloads_once(slskd, store, {}))
    monkeypatch.undo()
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(downloads))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))
    monkeypatch.setattr(Config, "AUTO_RETRY_PEER", "off")

    halfway = run(store.get_job(job_id))
    assert halfway["status"] == "failed" and halfway["notice"]["moving"] is True
    assert halfway["tried"][0]["damaged"] and len(run(store.refused_files())) == 3
    assert slskd.asked == []

    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()
    run(poll_downloads_once(slskd, store, {}))
    job = run(store.get_job(job_id))
    assert (job["status"], job["username"], slskd.asked) == ("queued", "sofaking", ["sofaking"])
    assert job["notice"]["text"].endswith("Now coming from sofaking, as good a match: same quality, songs and edition.")
    assert "moving" not in job["notice"]


def test_a_stop_during_the_check_is_checked_again_not_called_interrupted(setup, tmp_path, monkeypatch):
    """(review) The check reads and moves nothing: a stop while it runs leaves the row `organizing` with `checking`,
    which the start checks and files again - never INTERRUPTED_FILING, which can't be retried. A stop once the
    filing itself began is still that."""
    downloads, library, store = setup
    lay_down(downloads, "glassbeads")
    job_id = queue(store)
    slskd = Slskd({"glassbeads": files_of("glassbeads")})

    async def stopped(*args, **kwargs):
        raise asyncio.CancelledError

    monkeypatch.setattr(poller, "organize_job", stopped)
    with pytest.raises(asyncio.CancelledError):
        run(poll_downloads_once(slskd, store, {}))
    monkeypatch.setattr(poller, "organize_job", organizer.organize_job)
    caught = run(store.get_job(job_id))
    assert (caught["status"], caught["checking"]) == ("organizing", 1)

    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()
    assert run(settle_interrupted_filing(store)) == 0
    assert run(check_again(store, slskd)) == 1
    job = run(store.get_job(job_id))
    assert job["status"] == "organized" and job["error"] != INTERRUPTED_FILING and not job["checking"]
    assert len(library_names(library)) == 3

    #? once the filing began (filing_began), a stop is an interrupted filing, as ever
    other = queue(store)
    run(store.begin_filing_check(other))
    run(store.filing_began(other))
    assert run(settle_interrupted_filing(store)) == 1
    assert run(store.get_job(other))["error"] == INTERRUPTED_FILING


def test_the_check_runs_off_the_event_loop(setup, monkeypatch):
    """(review) An album's FLACs are read whole: in a worker thread (organize_job's asyncio.to_thread), never on
    the loop that answers every request."""
    downloads, _, store = setup
    lay_down(downloads, "glassbeads")
    queue(store)
    threads = []

    def checked(path):
        threads.append(threading.current_thread())
        return Verdict(CHECKED_OK)

    monkeypatch.setattr(organizer, "check_file", checked)
    run(poll_downloads_once(Slskd({"glassbeads": files_of("glassbeads")}), store, {}))
    assert len(threads) == 3 and threading.main_thread() not in threads


def test_a_refused_album_never_files_itself_after_a_restart_and_asked_again_is_checked_again(setup):
    downloads, library, store = setup
    lay_down(downloads, "glassbeads", {1: stale(song(1))})
    job_id = queue(store)
    slskd = Slskd({"glassbeads": files_of("glassbeads")})
    run(poll_downloads_once(slskd, store, {}))
    refused = run(store.get_job(job_id))
    assert refused["status"] == "failed"

    #? a restart: every step the poller takes as it starts, and a poll
    run(settle_interrupted_filing(store))
    run(check_again(store, slskd))
    run(forget_gone_refusals(store))
    run(refile_refused(store, slskd))
    run(tidy_cancelled_on_start(slskd, store))
    run(poll_downloads_once(slskd, store, {}))
    after = run(store.get_job(job_id))
    assert (after["status"], after["error"], after["updated_at"]) == (refused["status"], refused["error"],
                                                                      refused["updated_at"])
    assert everything_under(library) == {} and slskd.asked == []

    #? asking the same source again fetches it again - slskd writes it beside the refused copy - and that copy is
    #? checked, and refused, again: the sharer's copy loop is the same every time
    assert run(retry_same_peer(slskd, store, after))["retried"] and slskd.asked == ["glassbeads"]
    lay_down(downloads, "glassbeads", {1: stale(song(1))}, suffix=f"_{TICKS}")
    run(poll_downloads_once(slskd, store, {}))
    again = run(store.get_job(job_id))
    assert again["status"] == "failed" and "was damaged" in again["error"]
    assert everything_under(library) == {}


def test_a_refused_file_gone_or_changed_is_forgotten_on_start(setup):
    downloads, _, store = setup
    written = lay_down(downloads, "glassbeads", {1: stale(song(1))})
    queue(store)
    run(poll_downloads_once(Slskd({"glassbeads": files_of("glassbeads")}), store, {}))
    assert len(run(store.refused_files())) == 3
    folder = downloads / FOLDERS["glassbeads"]
    (folder / "01 - Krakow.flac").unlink()
    (folder / "02 - Glass.flac").write_bytes(b"something else")
    assert run(forget_gone_refusals(store)) == 2
    assert [Path(path).name for path, _, _ in run(store.refused_files())] == ["03 - Static.flac"]
    assert set(written) >= {"03 - Static.flac"}


# --- /jobs ----------------------------------------------------------------------------------------------------

def jobs_rows(store, slskd=None) -> dict[int, dict]:
    from fastapi.testclient import TestClient
    from src.api.app import start
    app = start()
    app.state.store = store
    app.state.slskd_client = slskd or Slskd()
    answer = TestClient(app).get("/deadwax/download/jobs")
    assert answer.status_code == 200
    return {row["id"]: row for row in answer.json()["jobs"]}


def test_jobs_carries_quality_size_the_notice_and_who_it_came_from_before(setup):
    downloads, library, store = setup
    lay_down(downloads, "glassbeads", {1: stale(song(1))})
    #? sofaking declines: asked, never a source, so not one of the earlier sources (review)
    job_id = queue(store, [alternative("sofaking"), alternative("thirdpeer")])
    run(poll_downloads_once(Slskd({"glassbeads": files_of("glassbeads")}, declines={"sofaking"}), store, {}))

    row = jobs_rows(store)[job_id]
    assert row["username"] == "thirdpeer"
    assert row["quality"] == {**FLAC_16, "words": "FLAC 16/44.1"}
    assert row["total_size"] == 3 * 30_000_000
    assert row["earlier_sources"] == [{"username": "glassbeads", "directory": f"share\\{FOLDERS['glassbeads']}",
                                       "damaged": "extra data after the end of 1 of 3 songs"}]
    assert row["notice"]["text"].startswith("The copy from glassbeads was damaged")
    assert row["notice"]["to"] == "thirdpeer"
    #? still coming: "try the next peer" isn't offered, so no next source is described
    assert "next_source" not in row


def test_jobs_describes_a_failed_downloads_next_source_scored_by_deadwax(setup):
    """(review) The app's jobs carry no score: deadwax scores both sources from the release and their files."""
    _, _, store = setup
    job_id = queue(store, [alternative("sofaking", quality=MP3_320, extension="mp3", has_free_slot=False,
                                       queue_length=4)])
    run(store.update_status(job_id, "failed", "the peer refused to send it"))

    upcoming = jobs_rows(store)[job_id]["next_source"]
    assert (upcoming["username"], upcoming["replaces"], upcoming["verdict"]) == ("sofaking", "glassbeads", WEAKER)
    assert upcoming["lead"] == "Next: sofaking · MP3 320 · 91%"
    assert upcoming["summary"] == ("A weaker match: MP3 320, was FLAC 16/44.1 · match 91%, was 100% (format 45, was 100)"
                                   " · 5th in their queue, the first had a free slot.")
    assert [d["what"] for d in upcoming["differences"]] == ["quality", "score", "start"]


def test_a_score_a_client_sent_is_never_the_one_compared(setup):
    """(review) A card's score sent with the Get is not trusted: the two sources score the same, so they match,
    whatever the client said of them."""
    _, _, store = setup
    job_id = queue(store, [alternative("sofaking", score=0.20, signals={"title_match": 0.1})],
                   source={"score": 0.99, "has_free_slot": True, "queue_length": 0})
    run(store.update_status(job_id, "cancelled", "cancelled from deadwax"))
    upcoming = jobs_rows(store)[job_id]["next_source"]
    assert upcoming["summary"] == "Same quality, songs and edition as glassbeads."
    assert upcoming["verdict"] == AS_GOOD and upcoming["differences"] == []


def test_a_score_deadwax_cant_make_never_allows_as_good_or_better():
    """(review) With no release to score against, the client's scores are no stand-in: not known, said, and a
    difference of kind - never "as good", never "better"."""
    new = source_facts({**alternative("sofaking"), "score": 0.99}, {}, None)
    old = source_facts({"username": "glassbeads", "directory": "share\\x", "files": files_of("glassbeads"),
                        "quality": FLAC_16, "score": 0.50}, {}, None)
    assert (new["score"], old["score"]) == (None, None)
    described = compare(new, old)
    assert described["verdict"] == DIFFERENT and "no match score to compare" in described["notes"]
    assert described["detail"] == "match not known for either"
    assert match_score({"files": files_of("sofaking")}, {}) == (None, {})


def test_the_next_source_cache_key_moves_with_the_job(setup):
    """(review) /jobs keeps each answer by what it was made from: after a move, the row's next source is the next
    one along, described against the new source - never the answer kept from before."""
    _, _, store = setup
    job_id = queue(store, [alternative("sofaking"), alternative("thirdpeer", quality=MP3_320, extension="mp3")])
    run(store.update_status(job_id, "failed", "the peer refused to send it"))
    before = run(store.get_job(job_id))
    assert jobs_rows(store)[job_id]["next_source"]["username"] == "sofaking"

    assert run(retry_next_peer(Slskd(), store, before))["moved"]
    run(store.update_status(job_id, "failed", "the peer refused to send it"))
    after = run(store.get_job(job_id))
    assert next_source_key(store, before, 0, None, None) != next_source_key(store, after, 1, None, None)
    upcoming = jobs_rows(store)[job_id]["next_source"]
    assert (upcoming["username"], upcoming["replaces"], upcoming["verdict"]) == ("thirdpeer", "sofaking", WEAKER)


def test_one_row_that_cant_be_described_leaves_the_others_theirs(setup, monkeypatch):
    _, _, store = setup
    good = queue(store, [alternative("sofaking")])
    bad = queue(store, [alternative("thirdpeer")])
    for job_id in (good, bad):
        run(store.update_status(job_id, "failed", "the peer refused to send it"))
    real = store.next_source_inputs

    async def inputs(job_id, index):
        if job_id == bad:
            raise RuntimeError("a row nobody can read")
        return await real(job_id, index)

    monkeypatch.setattr(store, "next_source_inputs", inputs)
    rows = jobs_rows(store)
    assert rows[good]["next_source"]["username"] == "sofaking" and "next_source" not in rows[bad]


# --- the comparison: deadwax's scores, four verdicts ----------------------------------------------------------------

def facts(peer="glassbeads", quality=None, files=None, directory=None, free=True, queue=0, speed=None,
          release=RELEASE):
    return source_facts({"username": peer, "directory": directory or f"share\\{FOLDERS.get(peer, peer)}",
                         "files": files if files is not None else files_of(peer if peer in FOLDERS else "glassbeads"),
                         "quality": quality or FLAC_16, "has_free_slot": free, "queue_length": queue},
                        release, speed)


def test_nothing_differs():
    described = next_source(facts("sofaking"), facts())
    assert described["summary"] == "Same quality, songs and edition as glassbeads."
    assert described["detail"] == "same quality, songs and edition"
    assert described["verdict"] == AS_GOOD


def test_the_four_verdicts_and_their_words():
    """App Design's ruling: first that applies wins - weaker, different, better, as good - the deciding difference
    first, and the "new, was old" list after it in every case."""
    weaker = compare(facts("sofaking", quality=MP3_320, files=files_of("sofaking", "mp3")), facts())
    assert (weaker["match"], weaker["detail"]) == ("a weaker match",
                                                   "MP3 320, was FLAC 16/44.1 · match 91%, was 100% (format 45, was 100)")
    #? the Deluxe release, the first source's folder saying nothing: a different match, though its score is higher
    deluxe = {**RELEASE, "edition_tags": ["DELUXE"]}
    different = compare(facts("sofaking", directory="share\\Album (2001) (Deluxe)", release=deluxe),
                        facts(release=deluxe))
    assert different["match"] == "a different match"
    assert different["detail"].startswith("folder says Deluxe, the first said nothing · match 100%, was ")
    better = compare(facts("sofaking", quality=FLAC_24), facts())
    assert (better["match"], better["detail"]) == ("a better match", "FLAC 24/96, was FLAC 16/44.1")
    assert compare(facts("sofaking"), facts())["match"] == "as good a match"


def test_better_is_said_the_same_way_as_worse():
    better = compare(facts("sofaking", quality=FLAC_24), facts())
    worse = compare(facts("sofaking"), facts(quality=FLAC_24))
    assert [d["words"] for d in better["differences"]] == ["FLAC 24/96, was FLAC 16/44.1"]
    assert [d["words"] for d in worse["differences"]] == ["FLAC 16/44.1, was FLAC 24/96"]
    assert (better["verdict"], worse["verdict"]) == (BETTER, WEAKER)


def test_missing_songs_are_named_and_make_it_weaker():
    partial = [f for f in files_of("sofaking") if "Krakow" not in f["filename"]]
    described = compare(facts("sofaking", files=partial), facts())
    assert described["verdict"] == WEAKER
    assert described["differences"][0]["words"] == "2 of 3 songs, was all 3 (missing: Krakow)"


def test_the_same_song_missing_from_both_is_no_difference():
    """(review) Never "weaker" with nothing named: what both lack is not a difference."""
    mine = [f for f in files_of("glassbeads") if "Krakow" not in f["filename"]]
    theirs = [f for f in files_of("sofaking") if "Krakow" not in f["filename"]]
    described = compare(facts("sofaking", files=theirs), facts(files=mine))
    assert described["differences"] == [] and described["verdict"] == AS_GOOD


def test_scores_compare_at_the_whole_percent_shown():
    """(review) 95.5% against 96% reads 96% both: equal, so no difference and no "weaker"."""
    new, old = facts("sofaking"), facts()
    new["score"], old["score"] = 0.955, 0.96
    described = compare(new, old)
    assert described["differences"] == [] and described["verdict"] == AS_GOOD
    new["score"] = 0.95
    assert compare(new, old)["verdict"] == WEAKER


def test_no_quality_on_either_side_is_no_difference():
    new, old = facts("sofaking"), facts()
    new["quality"] = old["quality"] = ""
    new["grade"] = old["grade"] = None
    described = compare(new, old)
    assert described["differences"] == [] and "no quality to compare" in described["notes"]


def test_never_weaker_with_nothing_named():
    """(review) Whatever the facts, the verdict is the differences' kinds: weaker only with something worse listed."""
    cases = [(facts("sofaking"), facts()),
             (facts("sofaking", files=files_of("sofaking")[:2]), facts(files=files_of("glassbeads")[:2])),
             (facts("sofaking", free=False, queue=9, speed=10), facts(speed=10_000_000))]
    for new, old in cases:
        described = compare(new, old)
        worse = [d for d in described["differences"] if d["kind"] == "worse"]
        assert (described["verdict"] == WEAKER) == bool(worse), described


def test_extra_files_edition_words_size_start_and_speed():
    more = files_of("sofaking") + [{"filename": "share\\Dummy Band - Album\\04 - Hidden.flac", "size": 30_000_000}]
    described = compare(facts("sofaking", files=more, directory="share\\Album (Deluxe Edition)", free=False, queue=3,
                              speed=300 * 1024), facts(speed=1.2 * 1024 * 1024))
    words = [d["words"] for d in described["differences"]]
    assert words[0].startswith("match ") and words[1:] == [
        "4 files for 3 songs, was 3", "folder says Deluxe, the first said nothing", "114 MB, was 86 MB",
        "4th in their queue, the first had a free slot", "about 300 KB/s, was 1.2 MB/s"]
    #? its score is lower (a track count off, an edition the release doesn't have): weaker, the score said first
    assert described["verdict"] == WEAKER


def test_small_differences_in_size_and_speed_are_not_differences():
    near = [{**f, "size": f["size"] + 1_000_000} for f in files_of("sofaking")]
    described = compare(facts("sofaking", files=near, speed=1100 * 1024), facts(speed=1000 * 1024))
    assert described["differences"] == [] and described["verdict"] == AS_GOOD


def test_no_tracklist_counts_the_files():
    trackless = {**RELEASE, "tracks": []}
    described = compare(facts("sofaking", files=files_of("sofaking")[:2], release=trackless), facts(release=trackless))
    assert described["verdict"] == DIFFERENT and described["differences"][0]["words"] == "2 files, was 3"
    assert "no tracklist to count songs against" in described["notes"]


def test_a_file_refused_as_damaged_keeps_its_identity_only_while_unchanged(tmp_path):
    path = tmp_path / "01.flac"
    path.write_bytes(b"x" * 10)
    identity = file_identity(path)
    assert file_identity(path) == identity
    os.utime(path, ns=(identity[2] + 10**9, identity[2] + 10**9))
    assert file_identity(path) != identity
