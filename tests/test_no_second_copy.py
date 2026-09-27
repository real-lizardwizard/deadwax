"""
A release already in the store is not filed a second time beside itself (v1.0.1).

resolve_album_dir sends a download of a release to the folder already holding that release, and
the organizer only ever refused an EXACT existing filename. So a FLAC copy and then an MP3 copy
landed side by side - one album in Navidrome with every track twice - and a grab made without a
tracklist, which keeps the sharer's own filenames, did it even in the same format.

Now a track the folder already has (by disc and track number, from the files' own tags) is
skipped, and a missing one still files, so a second download can fill gaps a partial one left.
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import poller  # noqa: E402
from src.config import Config  # noqa: E402
from src.organizer import execute_plan, existing_track_keys, plan_organization  # noqa: E402
from tests.test_library import write_flac  # noqa: E402

RELEASE = {
    "artist": "Boards of Canada",
    "album": "Music Has the Right to Children",
    "year": "1998",
    "release_mbid": "mb-1",
    "tracks": [
        {"position": 1, "title": "Wildlife Analysis", "length_ms": 87000},
        {"position": 2, "title": "An Eagle in Your Mind", "length_ms": 383000},
    ],
}
ALBUM = "Boards of Canada/Music Has the Right to Children (1998)"


def job(files, release=None):
    return {"id": 7, "artist": "Boards of Canada", "album": "Music Has the Right to Children",
            "username": "bob", "directory": "share/BoC", "release": release or RELEASE,
            "files": [{"filename": f"share\\BoC\\{name}", "size": 1000} for name in files]}


def library_with(tmp_path, *tracks):
    """The album as deadwax filed it earlier, in FLAC, holding these track numbers."""
    names = {1: "01 - Wildlife Analysis.flac", 2: "02 - An Eagle in Your Mind.flac"}
    for number in tracks:
        write_flac(tmp_path / "music" / ALBUM / names[number], tracknumber=number,
                   musicbrainz_albumid="mb-1", album="Music Has the Right to Children")
    return str(tmp_path / "music")


def downloads_with(tmp_path, names, tagged=None):
    folder = tmp_path / "downloads" / "BoC"
    folder.mkdir(parents=True, exist_ok=True)
    for name in names:
        if tagged and name in tagged:
            write_flac(folder / name, **tagged[name])
        else:
            (folder / name).write_bytes(b"audio")
    return str(tmp_path / "downloads")


def album_files(library):
    return sorted(p.name for p in (Path(library) / ALBUM).iterdir())


def test_an_mp3_copy_is_not_filed_beside_the_flac_one(tmp_path):
    library = library_with(tmp_path, 1, 2)
    downloads = downloads_with(tmp_path, ["01 Wildlife Analysis.mp3", "02 An Eagle in Your Mind.mp3"])

    plan = plan_organization(job(["01 Wildlife Analysis.mp3", "02 An Eagle in Your Mind.mp3"]), downloads, library)
    assert [op.get("duplicate_of") for op in plan["operations"]] == \
        ["01 - Wildlife Analysis.flac", "02 - An Eagle in Your Mind.flac"]

    results = execute_plan(plan, RELEASE, "copy")
    assert (results["organized"], results["skipped"], results["duplicates"]) == (0, 2, 2)
    assert album_files(library) == ["01 - Wildlife Analysis.flac", "02 - An Eagle in Your Mind.flac"]


def test_a_missing_track_still_fills_the_gap(tmp_path):
    """A partial album is repaired by a later download of the same release, not blocked by it."""
    library = library_with(tmp_path, 1)
    names = ["01 Wildlife Analysis.flac", "02 An Eagle in Your Mind.flac"]
    downloads = downloads_with(tmp_path, names)

    results = execute_plan(plan_organization(job(names), downloads, library), RELEASE, "copy")
    assert (results["organized"], results["duplicates"]) == (1, 1)
    assert "02 - An Eagle in Your Mind.flac" in album_files(library)


def test_a_grab_with_no_tracklist_is_judged_by_its_own_tags(tmp_path):
    """Its files keep the sharer's names, so only their tags say which track each is."""
    library = library_with(tmp_path, 1, 2)
    release = {**RELEASE, "tracks": []}
    names = ["boc-wildlife.flac", "boc-eagle.flac", "bonus.flac"]
    downloads = downloads_with(tmp_path, names, tagged={
        "boc-wildlife.flac": {"tracknumber": "1/2"},
        "boc-eagle.flac": {"tracknumber": "02"},
    })

    plan = plan_organization(job(names, release), downloads, library)
    results = execute_plan(plan, release, "copy")

    assert results["duplicates"] == 2
    #? an untagged, unnumbered file can't be judged, so it files as it always did
    assert "bonus.flac" in album_files(library)


def test_the_other_disc_of_a_set_is_not_a_duplicate(tmp_path):
    release = {**RELEASE, "tracks": [
        {"position": 1, "title": "Wildlife Analysis", "disc": 1, "disc_position": 1},
        {"position": 2, "title": "Side Two Opener", "disc": 2, "disc_position": 1},
    ]}
    write_flac(tmp_path / "music" / ALBUM / "01 - Wildlife Analysis.flac",
               tracknumber=1, discnumber=1, musicbrainz_albumid="mb-1")
    names = ["01 Wildlife Analysis.flac", "02 Side Two Opener.flac"]
    downloads = downloads_with(tmp_path, names)

    plan = plan_organization(job(names, release), downloads, str(tmp_path / "music"))
    assert [bool(op.get("duplicate_of")) for op in plan["operations"]] == [True, False]


def test_an_empty_or_new_folder_has_nothing_to_duplicate(tmp_path):
    assert existing_track_keys(tmp_path / "nowhere") == {}
    names = ["01 Wildlife Analysis.flac", "02 An Eagle in Your Mind.flac"]
    downloads = downloads_with(tmp_path, names)
    plan = plan_organization(job(names), downloads, str(tmp_path / "music"))
    assert not any(op.get("duplicate_of") for op in plan["operations"])


def test_the_duplicate_stays_in_slskds_folder(tmp_path):
    """Counted as skipped, so a move's clean-up keeps the folder rather than deleting unfiled music."""
    library = library_with(tmp_path, 1, 2)
    names = ["01 Wildlife Analysis.mp3", "02 An Eagle in Your Mind.mp3"]
    downloads = downloads_with(tmp_path, names)

    execute_plan(plan_organization(job(names), downloads, library), RELEASE, "move")
    assert sorted(p.name for p in (Path(downloads) / "BoC").iterdir()) == names


class FakeStore:
    def __init__(self):
        self.statuses = []

    async def update_status(self, job_id, status, error=None):
        self.statuses.append((status, error))


def test_the_job_says_it_was_already_in_the_store(monkeypatch):
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", "/downloads")
    monkeypatch.setattr(Config, "LIBRARY_PATH", "/music")
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "move")

    async def organized(*args):
        return {"organized": 0, "skipped": 10, "duplicates": 10, "failed": 0, "dry_run": False}

    monkeypatch.setattr(poller, "organize_job", organized)
    store = FakeStore()
    asyncio.run(poller._organize_if_enabled({"id": 7, "artist": "a", "album": "b"}, store))

    assert store.statuses[-1] == ("complete", "already in the store: all 10 track(s) were already there, nothing was filed")
