"""
A release already in the store is not filed a second time beside itself (v1.0.1).

resolve_album_dir sends a download of a release to the folder already holding that release, and
the organizer only ever refused an EXACT existing filename. So a FLAC copy and then an MP3 copy
landed side by side - one album in Navidrome with every track twice - and a grab made without a
tracklist, which keeps the sharer's own filenames, did it even in the same format.

Now a track the folder already has is skipped, and a missing one still files, so a second
download can fill gaps a partial one left. "Already has" is the same disc and track number when
the folder holds this very release, and the same title otherwise (v1.0.2) - two pressings can
number their tracks differently.
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import poller  # noqa: E402
from src.config import Config  # noqa: E402
from src.organizer import execute_plan, existing_tracks, plan_organization  # noqa: E402
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
    titles = {1: "Wildlife Analysis", 2: "An Eagle in Your Mind"}
    for number in tracks:
        write_flac(tmp_path / "music" / ALBUM / names[number], tracknumber=number, title=titles[number],
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
    assert existing_tracks(tmp_path / "nowhere") == []
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


# ----- after review (v1.0.2) -----

DUMMY = "Portishead/Dummy (1994)"
UK = ["Mysterons", "Sour Times", "Strangers", "It Could Be Sweet", "Wandering Star", "Numb", "Roads",
      "Pedestal", "Biscuit", "Glory Box"]
US = UK[:5] + ["It's a Fire"] + UK[5:]


def test_another_pressing_in_an_untagged_folder_is_judged_by_title(tmp_path):
    """
    A pre-deadwax rip of the 10-track UK CD, untagged, shares its folder name with the 11-track US
    CD. By number, 'It's a Fire' (US 6) would be a "duplicate" of 'Numb' (UK 6) and be left out,
    while 'Glory Box' (US 11) filed beside UK 10. By title, only the missing song files.
    """
    for n, title in enumerate(UK, 1):
        write_flac(tmp_path / "music" / DUMMY / f"{n:02d} - {title}.mp3.flac", tracknumber=n, title=title)
    release = {"artist": "Portishead", "album": "Dummy", "year": "1994", "release_mbid": "us-cd",
               "tracks": [{"position": n, "title": t} for n, t in enumerate(US, 1)]}
    names = [f"{n:02d} {t}.flac" for n, t in enumerate(US, 1)]
    downloads = downloads_with(tmp_path, names)

    job_ = {**job(names, release), "artist": "Portishead", "album": "Dummy"}
    plan = plan_organization(job_, downloads, str(tmp_path / "music"))
    filed = [Path(op["target"]).name for op in plan["operations"] if not op.get("duplicate_of")]
    assert filed == ["06 - It's a Fire.flac"]


def test_the_same_release_is_judged_by_number_even_with_retitled_files(tmp_path):
    """Holding the SAME release, the numbering is the release's - a retitled track is still that track."""
    write_flac(tmp_path / "music" / ALBUM / "01 - Wildlife Analysis.flac",
               tracknumber=1, title="Wildlife Analysis (retitled by hand)", musicbrainz_albumid="mb-1")
    names = ["01 Wildlife Analysis.flac"]
    plan = plan_organization(job(names), downloads_with(tmp_path, names), str(tmp_path / "music"))
    assert plan["operations"][0].get("duplicate_of") == "01 - Wildlife Analysis.flac"


def test_the_sidecars_of_an_unfiled_copy_stay_with_it(tmp_path):
    """A log and cue describe the copy they came with, not the one already in the folder."""
    library = library_with(tmp_path, 1, 2)
    names = ["01 Wildlife Analysis.flac", "02 An Eagle in Your Mind.flac"]
    downloads = downloads_with(tmp_path, names)
    for extra in ("rip.log", "rip.cue"):
        (Path(downloads) / "BoC" / extra).write_text("describes the FLAC rip")

    plan = plan_organization(job(names), downloads, library)
    assert plan["companion_count"] == 0
    results = execute_plan(plan, RELEASE, "move")
    assert results["organized"] == 0, "nothing arrived, so it mustn't read as organized"
    assert "rip.log" in {p.name for p in (Path(downloads) / "BoC").iterdir()}


def test_already_in_the_store_counts_the_tracks_not_a_skipped_cover(monkeypatch):
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", "/downloads")
    monkeypatch.setattr(Config, "LIBRARY_PATH", "/music")
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "move")

    async def organized(*args):
        return {"organized": 0, "skipped": 11, "duplicates": 10, "failed": 0, "dry_run": False}

    monkeypatch.setattr(poller, "organize_job", organized)
    store = FakeStore()
    asyncio.run(poller._organize_if_enabled({"id": 7, "artist": "a", "album": "b"}, store))
    assert store.statuses[-1][1].startswith("already in the store: all 10 track(s)")
