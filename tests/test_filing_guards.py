"""
What filing needs now that it always moves (2.1.13) - the review of moving-always, its four findings:

  1. the library is never searched, moved out of or cleared: find_local_file never enters LIBRARY_PATH or returns
     a file in it, a plan with a source in the library or with the two folders overlapping is refused whole, the
     clean-up never removes a folder in the library or holding it, and Server settings says when they overlap.
     The review reproduced it with the real organize_job: slskd's folder a parent "media", the library
     media/music, the job's file absent from slskd's folder - and the library's own track was moved, retagged
     as the new release, its cover taken, its album folder removed.
  2. Server settings asks what filing asks - the download folders slskd made, and a read-only mount - not the
     root's own permissions, and its words cover both causes: `:ro`, or slskd and deadwax as different users.
  3. a download refused before anything moved is filed by itself once it can be: at start and every 15 minutes.
  4. the clean-up leaves a folder holding anything it doesn't know to be disposable - DSD, Musepack, video, a name
     it has never seen - rather than only what matching calls audio.

The read-only guard itself is at the bottom of tests/test_organize_move_only.py. See "Filing only moves (2.1.13)"
in notes/decisions.md.
"""

import asyncio
import logging
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import organizer, poller  # noqa: E402
from src.config import Config  # noqa: E402
from src.organizer import (cleanup_source_dirs, disposable, find_local_file, folders_overlap,  # noqa: E402
                           organize_job, plan_organization)
from src.poller import (FOLDERS_OVERLAP, INTERRUPTED_FILING, NOTHING_ORGANIZED, READ_ONLY_DOWNLOADS,  # noqa: E402
                        REFILE_POLLS, POLL_INTERVAL_SECONDS, job_outcome, poll_downloads_once, refile_refused)
from src.routes import settings as settings_module  # noqa: E402
from tests.test_poller import FakeSlskd, _all_done, make_store, seed_job  # noqa: E402

needs_a_user = pytest.mark.skipif(hasattr(os, "geteuid") and os.geteuid() == 0, reason="root ignores folder permissions")

#? r-x for everyone: readable and searchable, as a `:ro` mount is - nothing can be taken out of it
READ_ONLY = 0o555


def _everything_under(root: Path) -> dict[str, bytes]:
    """Each file under `root` and what it holds - so a test can say nothing in the library changed at all."""
    return {str(p.relative_to(root)): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file()}


def _job(remote_dir, names, release):
    return {"id": 9, "artist": release["artist"], "album": release["album"], "username": "peer",
            "directory": remote_dir, "release": release,
            "files": [{"filename": f"{remote_dir}\\{name}", "size": 3} for name in names]}


# ----------------------------------------------------------------- 1. never the library

NEW_RELEASE = {"artist": "Someone Else", "album": "Another Album", "year": "2010", "release_mbid": "mb-new",
               "tracks": [{"position": 1, "title": "Intro"}]}


@pytest.fixture
def media(tmp_path):
    """The review's setup: SLSKD_DOWNLOAD_PATH a parent folder, "media", with the library inside it at media/music
    holding Someone's Their Album (2001) - its first track and a cover - and slskd's own downloads beside it."""
    media = tmp_path / "media"
    album = media / "music" / "Someone" / "Their Album (2001)"
    album.mkdir(parents=True)
    (album / "01 - Intro.flac").write_bytes(b"the library's own")
    (album / "cover.jpg").write_bytes(b"the library's cover")
    (media / "slskd").mkdir()
    return media


def test_the_reviews_reproduction_files_nothing_and_leaves_the_library_whole(media, caplog):
    """The job's file isn't in slskd's folder at all, and a search by name under "media" found the library's: it was
    moved, retagged as the new release, its cover taken and the album folder removed. Now the overlap is refused
    before anything is searched, and every byte of the library is where it was."""
    library = media / "music"
    before = _everything_under(library)
    job = _job("share\\Their Album (2001)", ["01 - Intro.flac"], NEW_RELEASE)
    marked = []
    caplog.set_level(logging.INFO)

    results = asyncio.run(organize_job(job, str(media), str(library), on_plan=marked.append))

    assert results["overlap"] == "LIBRARY_PATH is inside SLSKD_DOWNLOAD_PATH"
    assert (results["organized"], results["failed"], results["skipped"]) == (0, 0, 0)
    assert "removed_dirs" not in results and marked == []
    assert _everything_under(library) == before
    said = [r.getMessage() for r in caplog.records if "not filing" in r.getMessage()]
    assert len(said) == 1 and "LIBRARY_PATH is inside SLSKD_DOWNLOAD_PATH" in said[0]
    assert "two separate folders, neither inside the other" in said[0]


def test_the_search_itself_never_returns_the_librarys_file(media):
    """What made the reproduction possible, held on its own: by name alone the library's track is the only match."""
    library = media / "music"
    remote = "share\\Their Album (2001)\\01 - Intro.flac"
    assert find_local_file(str(media), remote, "share\\Their Album (2001)") == \
        library / "Someone" / "Their Album (2001)" / "01 - Intro.flac", "without the library named, the hazard"
    assert find_local_file(str(media), remote, "share\\Their Album (2001)", str(library)) is None


def test_slskds_copy_wins_even_where_the_librarys_folders_agree_better(media):
    """With slskd's file there too, the old search preferred the hit agreeing on more of the peer's folders - and the
    library's Someone/Their Album (2001)/ agrees on two where slskd's Their Album (2001)/ agrees on one."""
    library = media / "music"
    ours = media / "slskd" / "Their Album (2001)" / "01 - Intro.flac"
    ours.parent.mkdir(parents=True)
    ours.write_bytes(b"slskd's download")
    remote = "share\\Someone\\Their Album (2001)\\01 - Intro.flac"

    assert find_local_file(str(media), remote) == library / "Someone" / "Their Album (2001)" / "01 - Intro.flac"
    assert find_local_file(str(media), remote, "", str(library)) == ours


def test_the_librarys_folder_is_never_entered_by_identity(tmp_path, monkeypatch):
    """LIBRARY_PATH known by its identity, not its spelling: here a link elsewhere names the folder under slskd's, as
    a second mount of it would. The walk passes it by even with the per-hit check taken away."""
    downloads = tmp_path / "downloads"
    shelved = downloads / "shelf" / "Album"
    shelved.mkdir(parents=True)
    (shelved / "01.flac").write_bytes(b"x")
    library = tmp_path / "library-link"
    library.symlink_to(downloads / "shelf", target_is_directory=True)

    monkeypatch.setattr(organizer, "in_library", lambda path, lib: False)
    assert find_local_file(str(downloads), "share\\Album\\01.flac", "", str(library)) is None
    assert find_local_file(str(downloads), "share\\Album\\01.flac") == shelved / "01.flac"


def test_a_link_into_the_library_is_passed_over(tmp_path):
    """A file in slskd's folder that is a link to one of the library's: moving it would be the library's business."""
    library_track = tmp_path / "music" / "Someone" / "Album" / "01.flac"
    library_track.parent.mkdir(parents=True)
    library_track.write_bytes(b"the library's own")
    link = tmp_path / "downloads" / "Album" / "01.flac"
    link.parent.mkdir(parents=True)
    link.symlink_to(library_track)

    assert find_local_file(str(tmp_path / "downloads"), "share\\Album\\01.flac") == link
    assert find_local_file(str(tmp_path / "downloads"), "share\\Album\\01.flac", "", str(tmp_path / "music")) is None


def test_the_plan_searches_with_the_library_named(media, monkeypatch):
    """Where the overlap goes unseen (two mounts no path relates), the plan's search still passes the library by and
    files slskd's copy - rather than finding the library's and refusing."""
    monkeypatch.setattr(organizer, "folders_overlap", lambda downloads, library: None)
    ours = media / "slskd" / "Their Album (2001)" / "01 - Intro.flac"
    ours.parent.mkdir(parents=True)
    ours.write_bytes(b"slskd's download")
    job = _job("share\\Someone\\Their Album (2001)", ["01 - Intro.flac"], NEW_RELEASE)

    plan = plan_organization(job, str(media), str(media / "music"))
    assert plan["overlap"] is None and [op["source"] for op in plan["operations"]] == [str(ours)]


def test_executing_an_overlapping_plan_writes_nothing(media):
    library = media / "music"
    before = _everything_under(library)
    plan = plan_organization(_job("share\\Their Album (2001)", ["01 - Intro.flac"], NEW_RELEASE), str(media), str(library))
    results = organizer.execute_plan(plan, NEW_RELEASE)
    assert results["overlap"] == "LIBRARY_PATH is inside SLSKD_DOWNLOAD_PATH" and results["organized"] == 0
    assert _everything_under(library) == before


def test_filing_hands_the_clean_up_the_library(tmp_path, monkeypatch):
    (tmp_path / "downloads" / "Album").mkdir(parents=True)
    (tmp_path / "downloads" / "Album" / "01.flac").write_bytes(b"x")
    seen = []
    monkeypatch.setattr(organizer, "cleanup_source_dirs",
                        lambda plan, root, results, library_root="": seen.append(library_root) or [])
    job = _job("share\\Album", ["01.flac"], NEW_RELEASE)
    asyncio.run(organize_job(job, str(tmp_path / "downloads"), str(tmp_path / "music")))
    assert seen == [str(tmp_path / "music")]


def test_a_name_with_brackets_is_found_as_itself(tmp_path):
    """Found along the way: rglob(name) read `[Live]` as a set of four letters, so a track with brackets in its name
    was never found ("not found on disk") and a `Song L.flac` beside it would have been taken instead. `?` and `*`
    still stand for any character, as they did."""
    downloads = tmp_path / "downloads" / "Album"
    downloads.mkdir(parents=True)
    (downloads / "Song [Live].flac").write_bytes(b"live")
    (downloads / "Song L.flac").write_bytes(b"not it")
    (downloads / "Wh_t.flac").write_bytes(b"slskd's spelling")

    assert find_local_file(str(tmp_path / "downloads"), "share\\Album\\Song [Live].flac") == downloads / "Song [Live].flac"
    assert find_local_file(str(tmp_path / "downloads"), "share\\Album\\Wh?t.flac") == downloads / "Wh_t.flac"


@pytest.mark.parametrize("downloads, library, said", [
    ("a", "a", "SLSKD_DOWNLOAD_PATH and LIBRARY_PATH are the same folder"),
    ("link-to-a", "a", "SLSKD_DOWNLOAD_PATH and LIBRARY_PATH are the same folder"),
    ("a", "a/music", "LIBRARY_PATH is inside SLSKD_DOWNLOAD_PATH"),
    ("a", "link-to-a-music", "LIBRARY_PATH is inside SLSKD_DOWNLOAD_PATH"),
    ("a/music/downloads", "a/music", "SLSKD_DOWNLOAD_PATH is inside LIBRARY_PATH"),
    ("a/downloads", "a/music", None),
    ("a/music", "a/music2", None),
])
def test_how_the_two_folders_overlap(tmp_path, downloads, library, said):
    for folder in ("a/music/downloads", "a/downloads", "a/music2"):
        (tmp_path / folder).mkdir(parents=True, exist_ok=True)
    (tmp_path / "link-to-a").symlink_to(tmp_path / "a", target_is_directory=True)
    (tmp_path / "link-to-a-music").symlink_to(tmp_path / "a" / "music", target_is_directory=True)
    assert folders_overlap(str(tmp_path / downloads), str(tmp_path / library)) == said


def test_overlap_through_a_second_mount_is_known_by_identity(tmp_path, monkeypatch):
    """A folder above the library that IS slskd's folder by identity - a bind mount of it - though no path says so."""
    (tmp_path / "downloads").mkdir()
    (tmp_path / "mounted" / "music").mkdir(parents=True)
    real = organizer._identity

    def identity(path):
        if path is not None and Path(path) == tmp_path / "mounted":
            return real(tmp_path / "downloads")
        return real(path)

    monkeypatch.setattr(organizer, "_identity", identity)
    assert folders_overlap(str(tmp_path / "downloads"), str(tmp_path / "mounted" / "music")) == \
        "LIBRARY_PATH is inside SLSKD_DOWNLOAD_PATH"


def test_unset_or_missing_folders_are_not_an_overlap(tmp_path):
    (tmp_path / "a").mkdir()
    assert folders_overlap("", str(tmp_path)) is None
    assert folders_overlap(str(tmp_path), None) is None
    assert folders_overlap(str(tmp_path / "gone"), str(tmp_path / "a")) is None


def test_a_source_found_in_the_library_refuses_the_whole_filing(tmp_path, monkeypatch):
    """The plan's own word, whatever the search answers: one source in the library and nothing is filed."""
    (tmp_path / "downloads").mkdir()
    track = tmp_path / "music" / "Someone" / "Their Album (2001)" / "01 - Intro.flac"
    track.parent.mkdir(parents=True)
    track.write_bytes(b"the library's own")
    monkeypatch.setattr(organizer, "find_local_file", lambda *args, **kwargs: track)
    job = _job("share\\Their Album (2001)", ["01 - Intro.flac"], NEW_RELEASE)

    plan = plan_organization(job, str(tmp_path / "downloads"), str(tmp_path / "music"))
    assert plan["overlap"] == f"{track} is in LIBRARY_PATH" and plan["operations"] == []

    results = asyncio.run(organize_job(job, str(tmp_path / "downloads"), str(tmp_path / "music")))
    assert results["overlap"] == f"{track} is in LIBRARY_PATH" and results["organized"] == 0
    assert track.read_bytes() == b"the library's own"


def test_the_row_says_the_folders_overlap_and_it_files_once_they_are_apart(tmp_path, monkeypatch):
    """Through the poller: refused with the named words, never offered another source; then, with LIBRARY_PATH
    moved out of slskd's folder, filed by itself as it would have been."""
    downloads = tmp_path / "downloads"
    (downloads / "album").mkdir(parents=True)
    (downloads / "album" / "01.flac").write_bytes(b"one")
    (downloads / "album" / "02.flac").write_bytes(b"two")
    (downloads / "music").mkdir()
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(downloads))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(downloads / "music"))
    monkeypatch.setattr(Config, "FETCH_LYRICS", "off")
    store = make_store(tmp_path)
    job_id = seed_job(store)

    asyncio.run(poll_downloads_once(FakeSlskd(_all_done()), store, {}))
    job = next(j for j in asyncio.run(store.list_jobs()) if j["id"] == job_id)
    assert (job["status"], job["error"]) == ("complete", FOLDERS_OVERLAP)
    assert job_outcome("complete", FOLDERS_OVERLAP, not_filed=True) is None
    assert "again" not in FOLDERS_OVERLAP and "filed by itself once fixed" in FOLDERS_OVERLAP
    assert sorted(p.name for p in (downloads / "album").iterdir()) == ["01.flac", "02.flac"]

    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))
    assert asyncio.run(refile_refused(store)) == 1
    job = next(j for j in asyncio.run(store.list_jobs()) if j["id"] == job_id)
    assert (job["status"], job["error"]) == ("organized", None)
    assert sorted(_everything_under(tmp_path / "music")) == [
        "Boards of Canada/Music Has the Right to Children (1998)/01.flac",
        "Boards of Canada/Music Has the Right to Children (1998)/02.flac"]


def _clean(results=None):
    return results or {"failed": 0, "skipped": 0}


def test_the_clean_up_never_removes_a_folder_in_the_library(tmp_path):
    album = tmp_path / "music" / "Someone" / "Their Album (2001)"
    album.mkdir(parents=True)
    (album / "Thumbs.db").write_bytes(b"x")

    #? slskd's folder the library's parent, as in the review: every guard before this one lets it through
    assert cleanup_source_dirs({"source_dirs": [str(album)]}, str(tmp_path), _clean(), str(tmp_path / "music")) == []
    assert (album / "Thumbs.db").exists()


def test_the_clean_up_never_removes_a_folder_holding_the_library(tmp_path):
    holder = tmp_path / "downloads" / "a"
    (holder / "music" / "Someone").mkdir(parents=True)
    (holder / "music" / "Someone" / "desktop.ini").write_bytes(b"x")

    assert cleanup_source_dirs({"source_dirs": [str(holder)]}, str(tmp_path / "downloads"), _clean(),
                               str(holder / "music")) == []
    assert (holder / "music" / "Someone" / "desktop.ini").exists()


def test_the_clean_up_never_removes_a_folder_with_the_library_mounted_beneath(tmp_path):
    """Known by identity: here a link stands for the second mount - nothing in it is a file of the folder's own."""
    library = tmp_path / "music"
    library.mkdir()
    (library / "keep.flac").write_bytes(b"x")
    folder = tmp_path / "downloads" / "x"
    folder.mkdir(parents=True)
    (folder / "lib").symlink_to(library, target_is_directory=True)

    assert cleanup_source_dirs({"source_dirs": [str(folder)]}, str(tmp_path / "downloads"), _clean(), str(library)) == []
    assert folder.exists() and (library / "keep.flac").exists()


# ----------------------------------------------------------------- 2. Server settings asks what filing asks

@pytest.fixture
def paths(tmp_path, monkeypatch):
    """slskd's folder and a library apart from it, set as the container's; each test makes the download folders."""
    downloads, library = tmp_path / "downloads", tmp_path / "music"
    downloads.mkdir()
    library.mkdir()
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(downloads))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(library))
    made = []

    def download_folder(name, writable=True, names=("01.flac",)):
        folder = downloads / name
        folder.mkdir(parents=True)
        for file in names:
            (folder / file).write_bytes(b"x")
        if not writable:
            folder.chmod(READ_ONLY)
            made.append(folder)
        return folder

    yield downloads, library, download_folder
    for folder in made + [downloads]:
        folder.chmod(0o755)


def _answer():
    answer = asyncio.run(settings_module.settings())
    rows = {s["key"]: s for g in answer["groups"] for s in g["settings"]}
    return answer["organizing"], rows["SLSKD_DOWNLOAD_PATH"], rows["LIBRARY_PATH"]


@needs_a_user
def test_the_root_alone_is_never_a_blocker(paths):
    """(review) slskd's folder can be another user's and each download's folder writable: filing works, so nothing
    says otherwise - the reverse of what the 2.1.13 draft said. A fresh install, no download folders yet, too."""
    downloads, _, download_folder = paths
    downloads.chmod(READ_ONLY)
    assert _answer()[0] == {"enabled": True, "blockers": []}
    downloads.chmod(0o755)

    download_folder("Album")
    downloads.chmod(READ_ONLY)
    organizing, row, _ = _answer()
    assert organizing == {"enabled": True, "blockers": []} and (row["status"], row["detail"]) == ("ok", None)


@needs_a_user
def test_download_folders_deadwax_cant_write_are_what_it_says(paths):
    """(review) The likeliest case: slskd running as another user makes every download's folder its own. The root is
    fine, nothing is `:ro` - and every filing is refused. Server settings now says so, with the fix."""
    downloads, _, download_folder = paths
    download_folder("Album One", writable=False)
    download_folder("Album Two", writable=False)

    organizing, row, _ = _answer()
    assert organizing == {"enabled": False, "blockers": [
        "deadwax can't move files out of slskd's download folders - run slskd and deadwax as the same PUID/PGID, "
        "or give deadwax write access to them"]}
    assert row["status"] == "error"
    assert row["detail"].startswith("deadwax can't move files out of 2 of the 2 download folder(s) it looked at")
    assert "(and 1 more)" in row["detail"] and "filed by themselves once it can" in row["detail"]


@needs_a_user
def test_some_folders_deadwax_cant_write_are_the_rows_not_a_blocker(paths):
    """Filing works for the rest, so organizing isn't off - the row says which can't, and why."""
    _, _, download_folder = paths
    stuck = download_folder("Old One", writable=False)
    download_folder("New One")

    organizing, row, _ = _answer()
    assert organizing == {"enabled": True, "blockers": []}
    assert row["status"] == "error" and row["detail"].startswith("deadwax can't move files out of 1 of the 2")
    assert str(stuck) in row["detail"] and "(and" not in row["detail"]


def test_a_read_only_mount_is_a_blocker_with_its_own_fix(paths, monkeypatch):
    monkeypatch.setattr(settings_module, "mounted_read_only", lambda path: True)
    organizing, row, _ = _answer()
    assert organizing["blockers"] == ["SLSKD_DOWNLOAD_PATH is mounted read-only, so nothing can be moved out of it"]
    assert row["status"] == "error" and "remove :ro from the /downloads volume" in row["detail"]


def test_overlapping_folders_are_a_blocker_and_both_rows_say_so(tmp_path, monkeypatch):
    (tmp_path / "downloads").mkdir()
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "downloads"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))

    organizing, downloads_row, library_row = _answer()
    assert organizing == {"enabled": False, "blockers": [
        "SLSKD_DOWNLOAD_PATH is inside LIBRARY_PATH, so filing would move music out of the library"]}
    for row in (downloads_row, library_row):
        assert row["status"] == "error" and row["detail"].startswith("SLSKD_DOWNLOAD_PATH is inside LIBRARY_PATH")
        assert "neither inside the other" in row["detail"]


@needs_a_user
def test_the_probe_is_bounded_asks_only_music_folders_and_never_the_library(tmp_path, monkeypatch):
    downloads = tmp_path / "downloads"
    shut = []
    for n in range(5):
        folder = downloads / f"Album {n}"
        folder.mkdir(parents=True)
        (folder / "01.flac").write_bytes(b"x")
    art = downloads / "Art only"
    art.mkdir()
    (art / "cover.jpg").write_bytes(b"x")
    #? the library's folder under slskd's - a second mount of it, as far as the walk can tell - is never asked
    library = downloads / "music" / "Album"
    library.mkdir(parents=True)
    (library / "01.flac").write_bytes(b"x")
    for folder in (art, library):
        folder.chmod(READ_ONLY)
        shut.append(folder)
    try:
        assert settings_module._probe_downloads(str(downloads), str(downloads / "music")) == {"checked": 5, "refused": []}
        monkeypatch.setattr(settings_module, "PROBE_FOLDERS", 3)
        assert settings_module._probe_downloads(str(downloads), str(downloads / "music"))["checked"] == 3
        monkeypatch.setattr(settings_module, "PROBE_VISITS", 2)
        assert settings_module._probe_downloads(str(downloads), str(downloads / "music"))["checked"] <= 1
    finally:
        for folder in shut:
            folder.chmod(0o755)


# ----------------------------------------------------------------- 3. refused downloads file by themselves

def _refused_by_a_read_only_folder(tmp_path, monkeypatch):
    downloads = tmp_path / "downloads" / "album"
    downloads.mkdir(parents=True)
    (downloads / "01.flac").write_bytes(b"one")
    (downloads / "02.flac").write_bytes(b"two")
    downloads.chmod(READ_ONLY)
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "downloads"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))
    monkeypatch.setattr(Config, "FETCH_LYRICS", "off")
    store = make_store(tmp_path)
    job_id = seed_job(store)
    asyncio.run(poll_downloads_once(FakeSlskd(_all_done()), store, {}))
    return store, job_id, downloads


def _row(store, job_id):
    job = next(j for j in asyncio.run(store.list_jobs()) if j["id"] == job_id)
    return job["status"], job["error"]


@needs_a_user
def test_a_refused_download_waits_then_files_by_itself_once_its_folder_can_be_written(tmp_path, monkeypatch):
    store, job_id, downloads = _refused_by_a_read_only_folder(tmp_path, monkeypatch)
    try:
        assert _row(store, job_id) == ("complete", READ_ONLY_DOWNLOADS)
        #? still refused: left as it is, nothing written
        assert asyncio.run(refile_refused(store)) == 0
        assert _row(store, job_id) == ("complete", READ_ONLY_DOWNLOADS)
        assert not (tmp_path / "music").exists()
    finally:
        downloads.chmod(0o755)

    assert asyncio.run(refile_refused(store)) == 1
    assert _row(store, job_id) == ("organized", None)
    assert sorted(_everything_under(tmp_path / "music")) == [
        "Boards of Canada/Music Has the Right to Children (1998)/01.flac",
        "Boards of Canada/Music Has the Right to Children (1998)/02.flac"]
    assert not downloads.exists(), "moved, and the emptied folder cleared away, as any filing"
    #? filed once: the next pass finds nothing refused
    assert asyncio.run(refile_refused(store)) == 0


@needs_a_user
def test_the_poller_tries_them_at_start_before_its_first_poll(tmp_path, monkeypatch):
    """A mount put right means a container restarted: the refused row is filed before the first poll."""
    store, job_id, downloads = _refused_by_a_read_only_folder(tmp_path, monkeypatch)
    downloads.chmod(0o755)
    monkeypatch.setattr(Config, "SLSKD_INCOMPLETE_PATH", "")

    async def stop(_seconds):
        raise asyncio.CancelledError

    monkeypatch.setattr(poller.asyncio, "sleep", stop)
    try:
        asyncio.run(poller.run_download_poller(FakeSlskd(), store))
    except asyncio.CancelledError:
        pass
    assert _row(store, job_id) == ("organized", None)


def test_and_every_fifteen_minutes(monkeypatch):
    assert REFILE_POLLS * POLL_INTERVAL_SECONDS == 15 * 60
    tried, polls = [], []

    async def tick(_seconds):
        if len(polls) >= 2 * REFILE_POLLS:
            raise asyncio.CancelledError

    async def poll(*args, **kwargs):
        polls.append(1)

    async def refile(_store):
        tried.append(len(polls))
        return 0

    async def nothing(*args, **kwargs):
        return 0

    monkeypatch.setattr(poller.asyncio, "sleep", tick)
    monkeypatch.setattr(poller, "poll_downloads_once", poll)
    monkeypatch.setattr(poller, "refile_refused", refile)
    for name in ("settle_interrupted_filing", "tidy_cancelled_on_start", "sweep_empty_incomplete_dirs"):
        monkeypatch.setattr(poller, name, nothing)
    with pytest.raises(asyncio.CancelledError):
        asyncio.run(poller.run_download_poller(FakeSlskd(), object()))
    assert tried == [0, REFILE_POLLS, 2 * REFILE_POLLS]


def test_only_a_refusal_is_tried_again(tmp_path, monkeypatch):
    """Nothing else a row can say is filed by itself: not a filing that couldn't find its files, not one a stop caught
    half-way (a move may have taken half the tracks - INTERRUPTED_FILING's rule), not one already filed."""
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))
    store = make_store(tmp_path)
    ids = [seed_job(store) for _ in range(5)]
    for job_id, (status, error) in zip(ids, [("complete", NOTHING_ORGANIZED), ("complete", INTERRUPTED_FILING),
                                             ("organized", None), ("failed", READ_ONLY_DOWNLOADS),
                                             ("complete", FOLDERS_OVERLAP)]):
        asyncio.run(store.update_status(job_id, status, error))

    found = asyncio.run(store.jobs_with_error("complete", poller.REFUSED_FILING))
    assert [j["id"] for j in found] == [ids[4]]


def test_a_refused_download_whose_files_are_gone_is_left_as_it_is(tmp_path, monkeypatch):
    (tmp_path / "downloads").mkdir()
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "downloads"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))
    store = make_store(tmp_path)
    job_id = seed_job(store)
    asyncio.run(store.update_status(job_id, "complete", READ_ONLY_DOWNLOADS))

    assert asyncio.run(refile_refused(store)) == 0
    assert _row(store, job_id) == ("complete", READ_ONLY_DOWNLOADS)


def test_trying_again_never_raises(tmp_path, monkeypatch):
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))
    store = make_store(tmp_path)
    job_id = seed_job(store)
    asyncio.run(store.update_status(job_id, "complete", READ_ONLY_DOWNLOADS))

    def broken(*args, **kwargs):
        raise OSError("the disk went away")

    monkeypatch.setattr(poller, "plan_organization", broken)
    assert asyncio.run(refile_refused(store)) == 0

    async def unreadable(*args, **kwargs):
        raise RuntimeError("database is locked")

    monkeypatch.setattr(store, "jobs_with_error", unreadable)
    assert asyncio.run(refile_refused(store)) == 0

    monkeypatch.setattr(Config, "LIBRARY_PATH", "")
    assert asyncio.run(refile_refused(store)) == 0, "organizing off: nothing is tried"


# ----------------------------------------------------------------- 4. the clean-up keeps what it doesn't know

@pytest.mark.parametrize("left", [
    "01 - Intro.dsf", "01 - Intro.dff", "01 - Intro.mka", "Audiobook.m4b", "01 - Intro.tta", "01 - Intro.mpc",
    "Video.mp4", "Video.mkv", "README", "notes.xyz", "Extras/01 - Bonus.dsf",
])
def test_a_folder_holding_anything_unknown_is_kept(tmp_path, left, caplog):
    root = tmp_path / "downloads"
    folder = root / "Their Album"
    (folder / left).parent.mkdir(parents=True, exist_ok=True)
    (folder / left).write_bytes(b"x")
    (folder / "Thumbs.db").write_bytes(b"x")
    caplog.set_level(logging.INFO)

    assert cleanup_source_dirs({"source_dirs": [str(folder)]}, str(root), _clean()) == []
    assert (folder / left).exists()
    said = [r.getMessage() for r in caplog.records if r.getMessage().startswith("left Their Album in place")]
    assert said == [f"left Their Album in place, it still holds 1 file(s) nothing filed: {Path(left).name}"]


@pytest.mark.parametrize("left", [
    "Thumbs.db", "ehthumbs.db", "desktop.ini", ".DS_Store", "._01 - Intro.flac", "album.md5", "album.sha256",
    "album.ffp", "album.st5", "album.accurip", "Discogs.url", "01.sfk", "01.pk", "Scans/booklet.tif",
    "Scans/back.TIFF", "booklet.pdf", "cover.heic", "cover.avif", "cover.jfif", "second cover.jpg", "rip.log",
])
def test_a_folder_holding_only_what_is_known_to_go_is_cleared(tmp_path, left):
    root = tmp_path / "downloads"
    folder = root / "Their Album"
    (folder / left).parent.mkdir(parents=True, exist_ok=True)
    (folder / left).write_bytes(b"x")

    assert cleanup_source_dirs({"source_dirs": [str(folder)]}, str(root), _clean()) == [str(folder)]
    assert not folder.exists()


def test_what_is_disposable_is_the_clean_ups_own_list_not_matchings():
    """A search's idea of audio is unchanged: the clean-up's list is its own."""
    from src.matching import AUDIO_EXTENSIONS
    assert "dsf" not in AUDIO_EXTENSIONS, "if matching learns DSD, this test's reason to exist has moved"
    assert not disposable("01.dsf") and not disposable("01.flac") and not disposable("01.FLAC")
    assert disposable("THUMBS.DB") and disposable("._anything") and disposable("Folder.JPG")
