"""
A damaged download is refused, and the next source says how it differs (asked for, 27 Nov).

James: "Let's avoid trimming for now and just move on to the next peer with some sort of message about it so I know
what happened." / "Actually I want it to tell me the differences in the next peer." / "Actually if the download file
is bad, then it should go ahead and move to the next peer regardless".

Held here, through the real organizer, poller, store and /jobs route, on synthetic FLACs (tests/test_flac_mp4.py's
encoder): one damaged song refuses the whole album from that source - nothing moved, nothing changed; the job moves
to its next source by itself with AUTO_RETRY_PEER off, and the row and the log say what was wrong and how the new
source differs; with none left it fails saying so; the refused files are never filed later, by the next source's
filing, a restart, or asking the same source again. The comparison's own rules are held on source_compare directly.
"""

import asyncio
import logging
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.config import Config  # noqa: E402
from src.flac_check import check_file  # noqa: E402
from src.organizer import execute_plan, plan_organization  # noqa: E402
from src.poller import (poll_downloads_once, refile_refused, retry_same_peer, settle_interrupted_filing,  # noqa: E402
                        tidy_cancelled_on_start)
from src.source_compare import AS_GOOD, WEAKER, compare, next_source, source_facts  # noqa: E402
from src.store import JobStore  # noqa: E402
from tests.test_flac_mp4 import encode  # noqa: E402

TITLES = ["Krakow", "Glass", "Static"]
TRACKS = [{"position": n, "disc": 1, "title": title} for n, title in enumerate(TITLES, 1)]
RELEASE = {"artist": "Dummy Band", "album": "Album", "year": "2001", "release_mbid": "mb-damaged", "tracks": TRACKS}
#? each source's folder on its share - slskd names the local folder after the last of it
FOLDERS = {"glassbeads": "Album (2001) [FLAC]", "sofaking": "Dummy Band - Album", "thirdpeer": "Album"}
FLAC_16 = {"formats": ["flac"], "bit_depths": [16], "sample_rates": [44100]}
MP3_320 = {"formats": ["mp3"], "bitrates": [320]}


def song(seed: int) -> bytes:
    return encode(seed=seed, blocks=(4096, 4096, 500))[0]


def stale(data: bytes, extra: int = 2000) -> bytes:
    """The report's copy loop: what follows the true end repeats the stretch 6,144 bytes before it."""
    return data + data[len(data) - 6144:len(data) - 6144 + extra]


def remote(peer: str, n: int, extension: str = "flac") -> str:
    return f"share\\{FOLDERS[peer]}\\0{n} - {TITLES[n - 1]}.{extension}"


def files_of(peer: str, extension: str = "flac", size: int = 30_000_000) -> list[dict]:
    return [{"filename": remote(peer, n, extension), "size": size} for n in range(1, 4)]


def lay_down(downloads: Path, peer: str, damaged: dict[int, bytes] | None = None, seed: int = 0) -> dict[str, bytes]:
    """The peer's files as slskd leaves them: in a folder named after the peer's, each song's bytes - a damaged one
    in place of the clean one for each song number in `damaged`."""
    folder = downloads / FOLDERS[peer]
    folder.mkdir(parents=True, exist_ok=True)
    written = {}
    for n in range(1, 4):
        data = (damaged or {}).get(n) or song(seed * 10 + n)
        path = folder / f"0{n} - {TITLES[n - 1]}.flac"
        path.write_bytes(data)
        written[path.name] = data
    return written


def alternative(peer: str, score: float = 0.97, quality: dict | None = None, extension: str = "flac", **card) -> dict:
    return {"username": peer, "directory": f"share\\{FOLDERS[peer]}", "files": files_of(peer, extension),
            "score": score, "quality": quality or FLAC_16, "has_free_slot": True, "queue_length": 0, **card}


class Slskd:
    """slskd: every file of each peer named in `done` finished; asked to queue, it accepts."""

    def __init__(self, done: dict[str, list[dict]] | None = None):
        self.done = dict(done or {})
        self.asked: list[str] = []
        self.removed: list[tuple[str, str]] = []

    async def get_downloads(self, usernames=()):
        wanted = set(usernames)
        return [{"username": peer, "directories": [{"directory": "d", "files": [
            {"id": f"{peer}-{i}", "filename": f["filename"], "state": "Completed, Succeeded", "percentComplete": 100.0,
             "averageSpeed": 100000, "size": f["size"]} for i, f in enumerate(files)]}]}
            for peer, files in self.done.items() if peer in wanted]

    async def enqueue(self, username, files):
        self.asked.append(username)
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


def queue(store, alternatives=(), score=0.96, quality=None) -> int:
    return run(store.create_job("glassbeads", f"share\\{FOLDERS['glassbeads']}", files_of("glassbeads"), RELEASE,
                                list(alternatives), quality=quality or FLAC_16,
                                source={"score": score, "has_free_slot": True, "queue_length": 0}))


def everything_under(root: Path) -> dict[str, bytes]:
    return {str(p.relative_to(root)): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file()} if root.exists() else {}


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


def test_a_plan_made_only_to_see_a_refusal_holds_checks_nothing(setup, monkeypatch):
    downloads, library, _ = setup
    lay_down(downloads, "glassbeads", {1: stale(song(1))})
    job = {"id": 1, "username": "glassbeads", "directory": f"share\\{FOLDERS['glassbeads']}",
           "files": files_of("glassbeads"), "release": RELEASE}
    assert plan_organization(job, str(downloads), str(library), check_audio=False)["damaged"] == []


# --- the poller: moved on by itself -------------------------------------------------------------------------

def test_a_damaged_download_moves_to_the_next_source_with_auto_retry_off(setup, caplog):
    downloads, library, store = setup
    refused = lay_down(downloads, "glassbeads", {1: stale(song(1)), 3: stale(song(3), 900)})
    job_id = queue(store, [alternative("sofaking", score=0.96)])
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
    assert said in caplog.text
    #? the refused source remembered with why, and every one of its files by identity
    first = job["tried"][0]
    assert first["username"] == "glassbeads" and first["damaged"] == "extra data after the end of 2 of 3 songs"
    assert sorted(Path(identity[0]).name for identity in first["refused"]) == sorted(refused)
    #? nothing filed, nothing of it changed; its transfers out of slskd's list, as a cancel's go
    assert everything_under(library) == {}
    assert {p.name: p.read_bytes() for p in (downloads / FOLDERS["glassbeads"]).iterdir()} == refused
    assert {name for name, _ in slskd.removed} == {"glassbeads"}


def test_the_next_sources_download_is_filed_and_never_the_refused_files(setup):
    downloads, library, store = setup
    lay_down(downloads, "glassbeads", {1: stale(song(1))})
    job_id = queue(store, [alternative("sofaking")])
    slskd = Slskd({"glassbeads": files_of("glassbeads")})
    run(poll_downloads_once(slskd, store, {}))

    #? sofaking's whole copy arrives, named as glassbeads' were
    whole = lay_down(downloads, "sofaking", seed=5)
    slskd.done["sofaking"] = files_of("sofaking")
    run(poll_downloads_once(slskd, store, {}))

    job = run(store.get_job(job_id))
    assert job["status"] == "organized"
    filed = sorted(p for p in library.rglob("*.flac"))
    assert sorted(p.name for p in filed) == sorted(whole)
    #? sofaking's copy moved (and tagged); every song of it whole - none of them glassbeads' damaged one
    assert all(check_file(p).kind == "ok" for p in filed)
    assert not any((downloads / FOLDERS["sofaking"]).glob("*.flac"))
    #? glassbeads' refused copy is still in slskd's folder, whole
    assert len(list((downloads / FOLDERS["glassbeads"]).iterdir())) == 3


def test_a_refused_copys_whole_songs_never_file_themselves_after_a_restart(setup, tmp_path):
    """
    The two sources' folders share a name, so slskd writes the second one's songs into the first one's folder - the
    two that collide under other names (assumed: slskd makes a colliding name unique), its own song 2 as it is. The
    refused copy's whole songs 1 and 3 are found under the names the new source's files have, and would be filed as
    its own, but for the refusal's record - kept with the job, so a restart in between keeps it too.
    """
    downloads, library, store = setup
    FOLDERS["thirdpeer"] = FOLDERS["glassbeads"]
    try:
        refused = lay_down(downloads, "glassbeads", {2: stale(song(2))})
        renamed = "share\\" + FOLDERS["thirdpeer"] + "\\02 - Glass (2011 Remaster).flac"
        theirs = [files_of("thirdpeer")[0], {"filename": renamed, "size": 30_000_000}, files_of("thirdpeer")[2]]
        job_id = queue(store, [{**alternative("thirdpeer"), "files": theirs}])
        slskd = Slskd({"glassbeads": files_of("glassbeads")})
        run(poll_downloads_once(slskd, store, {}))
        assert run(store.get_job(job_id))["username"] == "thirdpeer"

        #? a restart: the store opened again, and every step the poller takes as it starts
        store = JobStore(str(tmp_path / "jobs.db"))
        store.init()
        run(settle_interrupted_filing(store))
        run(refile_refused(store, slskd))
        folder = downloads / FOLDERS["glassbeads"]
        (folder / "02 - Glass (2011 Remaster).flac").write_bytes(song(52))
        (folder / "01 - Krakow_639001.flac").write_bytes(song(51))
        (folder / "03 - Static_639001.flac").write_bytes(song(53))
        slskd.done["thirdpeer"] = theirs
        run(poll_downloads_once(slskd, store, {}))

        filed = sorted(p.name for p in library.rglob("*.flac"))
        assert filed == ["02 - Glass.flac"], "only the new source's own song, never the refused copy's"
        assert {name: (folder / name).read_bytes() for name in refused} == refused
    finally:
        FOLDERS["thirdpeer"] = "Album"


def test_a_weaker_next_source_says_how_it_is_weaker(setup):
    downloads, library, store = setup
    lay_down(downloads, "glassbeads", {1: stale(song(1))})
    job_id = queue(store, [alternative("sofaking", score=0.81, quality=MP3_320, extension="mp3")], score=0.96)
    run(poll_downloads_once(Slskd({"glassbeads": files_of("glassbeads")}), store, {}))

    notice = run(store.get_job(job_id))["notice"]
    assert notice["text"] == ("The copy from glassbeads was damaged (extra data after the end of 1 of 3 songs). "
                              "Now coming from sofaking, a weaker match: MP3 320, was FLAC 16/44.1 · match 81%, was 96%.")
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
    assert job["notice"]["text"] == said and job["notice"]["to"] is None
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


# --- never filed later ----------------------------------------------------------------------------------------

def test_a_refused_album_never_files_itself_after_a_restart_or_when_asked_again(setup):
    downloads, library, store = setup
    lay_down(downloads, "glassbeads", {1: stale(song(1))})
    job_id = queue(store)
    slskd = Slskd({"glassbeads": files_of("glassbeads")})
    run(poll_downloads_once(slskd, store, {}))
    refused = run(store.get_job(job_id))
    assert refused["status"] == "failed"

    #? a restart: every step the poller takes as it starts, and a poll
    run(settle_interrupted_filing(store))
    run(refile_refused(store, slskd))
    run(tidy_cancelled_on_start(slskd, store))
    run(poll_downloads_once(slskd, store, {}))
    after = run(store.get_job(job_id))
    assert (after["status"], after["error"], after["updated_at"]) == (refused["status"], refused["error"],
                                                                      refused["updated_at"])
    assert everything_under(library) == {} and slskd.asked == []

    #? asking the same source again finds the same files - checked, and refused, again
    assert run(retry_same_peer(slskd, store, after))["retried"]
    run(poll_downloads_once(slskd, store, {}))
    again = run(store.get_job(job_id))
    assert again["status"] == "failed" and "was damaged" in again["error"]
    assert everything_under(library) == {}


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
    job_id = queue(store, [alternative("sofaking"), alternative("thirdpeer", score=0.5)])
    run(poll_downloads_once(Slskd({"glassbeads": files_of("glassbeads")}), store, {}))

    row = jobs_rows(store)[job_id]
    assert row["quality"] == {**FLAC_16, "words": "FLAC 16/44.1"}
    assert row["total_size"] == 3 * 30_000_000
    assert row["attempt"] == 2
    assert row["earlier_sources"] == [{"username": "glassbeads", "directory": f"share\\{FOLDERS['glassbeads']}",
                                       "damaged": "extra data after the end of 1 of 3 songs"}]
    assert row["notice"]["text"].startswith("The copy from glassbeads was damaged")
    #? still coming: "try the next peer" isn't offered, so no next source is described
    assert "next_source" not in row


def test_jobs_describes_a_failed_downloads_next_source_against_its_own(setup):
    _, _, store = setup
    job_id = queue(store, [alternative("sofaking", score=0.81, quality=MP3_320, extension="mp3",
                                       has_free_slot=False, queue_length=4)])
    run(store.update_status(job_id, "failed", "the peer refused to send it"))

    upcoming = jobs_rows(store)[job_id]["next_source"]
    assert (upcoming["username"], upcoming["replaces"], upcoming["verdict"]) == ("sofaking", "glassbeads", WEAKER)
    assert upcoming["lead"] == "sofaking · MP3 320 · 3 of 3 songs · match 81%"
    assert upcoming["summary"] == ("A weaker match: MP3 320, was FLAC 16/44.1 · match 81%, was 96% · "
                                   "starts after 4 others, was now")
    assert [d["what"] for d in upcoming["differences"]] == ["quality", "score", "start"]


def test_jobs_says_when_the_next_source_is_the_same(setup):
    _, _, store = setup
    job_id = queue(store, [alternative("sofaking", score=0.96)])
    run(store.update_status(job_id, "cancelled", "cancelled from deadwax"))
    upcoming = jobs_rows(store)[job_id]["next_source"]
    assert upcoming["summary"] == "Same quality, songs and edition as glassbeads"
    assert upcoming["verdict"] == AS_GOOD and upcoming["differences"] == []


def test_a_job_from_before_reads_as_it_did(setup):
    """No source kept, a runner-up sent with nothing but its files: no score to compare, said so."""
    _, _, store = setup
    job_id = run(store.create_job("glassbeads", f"share\\{FOLDERS['glassbeads']}", files_of("glassbeads"), RELEASE,
                                  [{"username": "sofaking", "directory": f"share\\{FOLDERS['sofaking']}",
                                    "files": files_of("sofaking")}]))
    run(store.update_status(job_id, "failed", "the peer refused to send it"))
    row = jobs_rows(store)[job_id]
    assert row["quality"] == {"words": "FLAC"} and "notice" not in row and row["earlier_sources"] == []
    assert "no match score to compare" in row["next_source"]["notes"]


# --- the comparison ---------------------------------------------------------------------------------------------

def facts(peer="glassbeads", quality=None, files=None, score=0.96, signals=None, directory=None, free=True, queue=0,
          speed=None, tracks=TRACKS):
    return source_facts({"username": peer, "directory": directory or f"share\\{FOLDERS.get(peer, peer)}",
                         "files": files if files is not None else files_of(peer if peer in FOLDERS else "glassbeads"),
                         "quality": quality or FLAC_16, "score": score, "signals": signals or {},
                         "has_free_slot": free, "queue_length": queue}, tracks, speed)


def test_nothing_differs():
    described = next_source(facts("sofaking"), facts())
    assert described["summary"] == "Same quality, songs and edition as glassbeads"
    assert described["detail"] == "same quality, songs and edition"


def test_better_is_said_the_same_way_as_worse():
    better = compare(facts("sofaking"), facts(quality=MP3_320, score=0.81))
    worse = compare(facts("sofaking", quality=MP3_320, score=0.81), facts())
    assert [d["words"] for d in better["differences"]] == ["FLAC 16/44.1, was MP3 320", "match 96%, was 81%"]
    assert [d["words"] for d in worse["differences"]] == ["MP3 320, was FLAC 16/44.1", "match 81%, was 96%"]
    #? Stricter: "as good a match" is the SAME quality - another one, better or worse, is not that match
    assert (better["verdict"], worse["verdict"]) == (WEAKER, WEAKER)
    assert better["detail"] == "FLAC 16/44.1, was MP3 320 · match 96%, was 81%"


def test_missing_songs_are_named_and_make_it_weaker():
    partial = [f for f in files_of("sofaking") if "Krakow" not in f["filename"]]
    described = compare(facts("sofaking", files=partial), facts())
    assert described["verdict"] == WEAKER
    assert described["differences"][0]["words"] == "2 of 3 songs (missing: Krakow), was all 3"


def test_extra_files_edition_words_size_start_and_speed():
    more = files_of("sofaking") + [{"filename": "share\\Dummy Band - Album\\04 - Hidden.flac", "size": 30_000_000}]
    described = compare(facts("sofaking", files=more, directory="share\\Album (Deluxe Edition)", free=False, queue=4,
                              speed=300 * 1024), facts(speed=1.2 * 1024 * 1024))
    words = [d["words"] for d in described["differences"]]
    assert words == ["4 files for 3 songs, was 3", "folder says Deluxe, was nothing", "114 MB, was 86 MB",
                     "starts after 4 others, was now", "about 300 KB/s, was 1.2 MB/s"]
    #? the edition words differ: weaker, though the score and quality are the same
    assert described["verdict"] == WEAKER


def test_the_parts_of_the_score_that_moved_are_named():
    described = compare(facts("sofaking", score=0.81, signals={"duration_match": 0.7, "format": 1.0}),
                        facts(score=0.96, signals={"duration_match": 1.0, "format": 0.98}))
    assert described["differences"][-1]["words"] == "match 81%, was 96% (track lengths 70%, was 100%)"


def test_a_lower_score_is_never_as_good_a_match():
    """Stricter: the same quality, every song and the same edition are not enough with a lower score."""
    assert compare(facts("sofaking", score=0.95), facts(score=0.96))["verdict"] == WEAKER
    assert compare(facts("sofaking", score=0.96), facts(score=0.96))["verdict"] == AS_GOOD
    assert compare(facts("sofaking", score=0.99), facts(score=0.96))["verdict"] == AS_GOOD


def test_small_differences_in_size_and_speed_are_not_differences():
    near = [{**f, "size": f["size"] + 1_000_000} for f in files_of("sofaking")]
    described = compare(facts("sofaking", files=near, speed=1100 * 1024), facts(speed=1000 * 1024))
    assert described["differences"] == [] and described["verdict"] == AS_GOOD


def test_no_tracklist_counts_the_files():
    fewer = files_of("sofaking")[:2]
    described = compare(facts("sofaking", files=fewer, tracks=[]), facts(tracks=[]))
    assert described["verdict"] == WEAKER and described["differences"][0]["words"] == "2 files, was 3"
    assert "no tracklist to count songs against" in described["notes"]


def test_a_file_refused_as_damaged_keeps_its_identity_only_while_unchanged(tmp_path):
    from src.organizer import file_identity, refused_identities
    path = tmp_path / "01.flac"
    path.write_bytes(b"x" * 10)
    identity = file_identity(path)
    tried = [{"username": "glassbeads", "refused": [list(identity)]}, {"username": "sofaking"}]
    assert refused_identities(tried, "sofaking") == {identity}
    #? asking glassbeads again checks its own files again rather than passing them over
    assert refused_identities(tried, "glassbeads") == frozenset()
    os.utime(path, ns=(identity[2] + 10**9, identity[2] + 10**9))
    assert file_identity(path) not in refused_identities(tried, "sofaking")
