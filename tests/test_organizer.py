"""
Tests for the library organizer.

This is the only code in deadwax that writes to the user's filesystem, so it gets the most
paranoid coverage: everything below runs against real files in a pytest tmp_path, and the
destructive cases (overwrite, collision, the move and its clean-up) are asserted explicitly
rather than assumed. Since 2.1.13 filing only ever MOVES - James: "I would like it to only move the
files" - so there is no copy, dry run or off left to test; the plan is still checked on its own,
without executing it.
"""

import asyncio
import inspect
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.organizer import (  # noqa: E402
    build_target_path,
    execute_plan,
    find_local_file,
    organize_job,
    plan_organization,
    sanitize_filename,
)

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


def make_job(files, release=None, directory="share/BoC/MHTRTC"):
    return {
        "id": 1, "artist": "Boards of Canada", "album": "Music Has the Right to Children",
        "username": "bob", "directory": directory,
        "release": release or RELEASE,
        "files": [{"filename": f, "size": 1000} for f in files],
    }


def seed_downloads(tmp_path, names, subdir="MHTRTC"):
    """Create files where slskd would have put them."""
    folder = tmp_path / "downloads" / subdir
    folder.mkdir(parents=True, exist_ok=True)
    for name in names:
        (folder / name).write_bytes(b"audio")
    return tmp_path / "downloads"


# ---------------------------------------------------------------- naming

def test_sanitize_strips_path_separators_and_illegal_chars():
    assert sanitize_filename('AC/DC: Back?') == "AC_DC_ Back_"


def test_sanitize_falls_back_when_nothing_survives():
    assert sanitize_filename("", "Unknown Artist") == "Unknown Artist"
    assert sanitize_filename("...") == "unknown"


def test_target_path_layout():
    target = build_target_path("/music", RELEASE, RELEASE["tracks"][0], "flac")
    assert target == Path("/music/Boards of Canada/Music Has the Right to Children (1998)/01 - Wildlife Analysis.flac")


def test_target_path_without_year_omits_the_parens():
    release = {**RELEASE, "year": ""}
    assert build_target_path("/music", release, RELEASE["tracks"][0], "flac").parent.name \
        == "Music Has the Right to Children"


def test_unmatched_track_keeps_its_original_name_rather_than_inventing_a_number():
    """A wrong track number is worse than no track number."""
    target = build_target_path("/music", RELEASE, {"filename": "hidden track"}, "flac")
    assert target.name == "hidden track.flac"


# ---------------------------------------------------------------- locating files

def test_find_local_file_locates_by_basename(tmp_path):
    root = seed_downloads(tmp_path, ["01 - Wildlife Analysis.flac"])
    found = find_local_file(str(root), r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac")
    assert found is not None and found.name == "01 - Wildlife Analysis.flac"


def test_find_local_file_prefers_the_matching_folder_when_ambiguous(tmp_path):
    """Same filename under two albums - the remote directory disambiguates."""
    seed_downloads(tmp_path, ["01.flac"], subdir="Geogaddi")
    seed_downloads(tmp_path, ["01.flac"], subdir="MHTRTC")
    root = tmp_path / "downloads"

    found = find_local_file(str(root), r"share\BoC\MHTRTC\01.flac", r"share\BoC\MHTRTC")
    assert found.parent.name == "MHTRTC"


def test_find_local_file_finds_each_disc_by_its_own_folder(tmp_path):
    """
    A set shared one folder per disc is one job whose directory is the album folder, while slskd
    files each track under ITS folder - "CD 1", "CD 2" - and both discs can hold the same name.
    The job's directory would pick neither; the file's own folder picks the right one.
    """
    root = tmp_path / "downloads"
    (root / "CD 1").mkdir(parents=True)
    (root / "CD 2").mkdir(parents=True)
    (root / "CD 1" / "01 - Intro.flac").write_bytes(b"disc one")
    (root / "CD 2" / "01 - Intro.flac").write_bytes(b"disc two")

    album = r"share\Pink Floyd - Wish You Were Here (Experience Edition)"
    assert find_local_file(str(root), album + r"\CD 1\01 - Intro.flac", album).read_bytes() == b"disc one"
    assert find_local_file(str(root), album + r"\CD 2\01 - Intro.flac", album).read_bytes() == b"disc two"


def test_find_local_file_prefers_the_deepest_agreement_under_a_full_path_layout(tmp_path):
    """slskd can be set to keep the whole remote path, where two albums' "CD 1"s sit side by side."""
    root = tmp_path / "downloads"
    for album in ("Wish You Were Here", "Animals"):
        (root / "share" / album / "CD 1").mkdir(parents=True)
        (root / "share" / album / "CD 1" / "01 - Intro.flac").write_bytes(album.encode())

    found = find_local_file(str(root), r"share\Wish You Were Here\CD 1\01 - Intro.flac")
    assert found.read_bytes() == b"Wish You Were Here"
    found = find_local_file(str(root), r"share\Animals\CD 1\01 - Intro.flac")
    assert found.read_bytes() == b"Animals"


def test_find_local_file_returns_none_when_absent(tmp_path):
    root = seed_downloads(tmp_path, ["other.flac"])
    assert find_local_file(str(root), r"share\x\missing.flac") is None


def test_find_local_file_tolerates_a_missing_download_root(tmp_path):
    assert find_local_file(str(tmp_path / "nope"), r"share\x\a.flac") is None


# ---------------------------------------------------------------- planning

def test_plan_maps_files_to_their_tracks(tmp_path):
    root = seed_downloads(tmp_path, ["01 - Wildlife Analysis.flac", "02 - An Eagle in Your Mind.flac"])
    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac",
                    r"share\BoC\MHTRTC\02 - An Eagle in Your Mind.flac"])

    plan = plan_organization(job, str(root), str(tmp_path / "music"))

    assert len(plan["operations"]) == 2
    assert plan["problems"] == []
    assert Path(plan["operations"][0]["target"]).name == "01 - Wildlife Analysis.flac"
    assert plan["matched_tracks"] == 2


def test_plan_reports_files_missing_from_disk(tmp_path):
    root = seed_downloads(tmp_path, ["01 - Wildlife Analysis.flac"])
    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac",
                    r"share\BoC\MHTRTC\02 - An Eagle in Your Mind.flac"])

    plan = plan_organization(job, str(root), str(tmp_path / "music"))

    assert len(plan["operations"]) == 1
    assert any("not found on disk" in p for p in plan["problems"])


def test_plan_refuses_to_map_two_sources_onto_one_target(tmp_path):
    """Without this guard one file would silently destroy the other."""
    root = seed_downloads(tmp_path, ["a.flac", "b.flac"])
    release = {**RELEASE, "tracks": []}  # no tracklist -> names come from the files
    job = make_job([r"share\x\a.flac", r"share\x\a.flac"], release=release)

    plan = plan_organization(job, str(root), str(tmp_path / "music"))

    assert len(plan["operations"]) == 1
    assert any("same destination" in p for p in plan["problems"])


def test_plan_writes_nothing(tmp_path):
    root = seed_downloads(tmp_path, ["01 - Wildlife Analysis.flac"])
    library = tmp_path / "music"
    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac"])

    plan_organization(job, str(root), str(library))

    assert not library.exists()


# ---------------------------------------------------------------- executing

def test_the_plan_names_every_move_and_makes_none(tmp_path):
    """The split that stays (2.1.13): the plan says where each file goes, and nothing has moved until the
    execute - the source still there, no library yet."""
    root = seed_downloads(tmp_path, ["01 - Wildlife Analysis.flac"])
    library = tmp_path / "music"
    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac"])

    plan = plan_organization(job, str(root), str(library))

    assert [Path(op["target"]).relative_to(library).as_posix() for op in plan["operations"]] == [
        "Boards of Canada/Music Has the Right to Children (1998)/01 - Wildlife Analysis.flac"]
    assert plan["source_dirs"] == [str(root / "MHTRTC")]
    assert not library.exists()
    assert (root / "MHTRTC" / "01 - Wildlife Analysis.flac").exists()


def test_filing_has_no_mode_any_more():
    """2.1.13: execute_plan and organize_job take no mode - off, dry run and copy are gone - and their results
    say nothing of one."""
    assert list(inspect.signature(execute_plan).parameters) == ["plan", "release"]
    assert list(inspect.signature(organize_job).parameters) == ["job", "download_root", "library_root", "on_plan"]
    import src.organizer as organizer
    assert not hasattr(organizer, "ORGANIZE_MODES")


def test_filing_MOVES_the_file_never_copies_it(tmp_path):
    """The one way filing goes: the file arrives in the library, byte for byte, and is gone from slskd's
    folder - one copy of it on the disk, not two."""
    root = seed_downloads(tmp_path, ["01 - Wildlife Analysis.flac"])
    (root / "MHTRTC" / "01 - Wildlife Analysis.flac").write_bytes(b"the very bytes slskd fetched")
    library = tmp_path / "music"
    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac"])

    results = execute_plan(plan_organization(job, str(root), str(library)), RELEASE)

    filed = library / "Boards of Canada" / "Music Has the Right to Children (1998)" / "01 - Wildlife Analysis.flac"
    assert results == {"organized": 1, "tracks_organized": 1, "skipped": 0, "duplicates": 0, "failed": 0}
    assert filed.read_bytes() == b"the very bytes slskd fetched"
    assert not (root / "MHTRTC" / "01 - Wildlife Analysis.flac").exists()
    assert [path.name for path in tmp_path.rglob("*.flac")] == ["01 - Wildlife Analysis.flac"]


def test_move_removes_the_source(tmp_path):
    root = seed_downloads(tmp_path, ["01 - Wildlife Analysis.flac"])
    library = tmp_path / "music"
    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac"])

    execute_plan(plan_organization(job, str(root), str(library)), RELEASE)

    assert (library / "Boards of Canada" / "Music Has the Right to Children (1998)"
            / "01 - Wildlife Analysis.flac").exists()
    assert not (root / "MHTRTC" / "01 - Wildlife Analysis.flac").exists()


def test_existing_destination_is_never_overwritten(tmp_path):
    """An existing file is far more likely to be the user's real album than something safe to clobber."""
    root = seed_downloads(tmp_path, ["01 - Wildlife Analysis.flac"])
    library = tmp_path / "music"
    destination = (library / "Boards of Canada" / "Music Has the Right to Children (1998)"
                   / "01 - Wildlife Analysis.flac")
    destination.parent.mkdir(parents=True)
    destination.write_bytes(b"the copy i already had")

    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac"])
    results = execute_plan(plan_organization(job, str(root), str(library)), RELEASE)

    assert results["skipped"] == 1
    assert results["organized"] == 0
    assert destination.read_bytes() == b"the copy i already had"
    assert (root / "MHTRTC" / "01 - Wildlife Analysis.flac").exists()  # source untouched too


# ---------------------------------------------------------------- tagging

def write_minimal_flac(path: Path) -> None:
    """
    Hand-build the smallest valid FLAC: the "fLaC" marker plus one STREAMINFO block.

    Worth the fiddliness - tagging is the part most likely to silently do nothing, so the
    test needs mutagen to genuinely parse and round-trip a real container rather than a file
    that merely ends in .flac.

    Its length is 0, "unknown" (damaged downloads, 27 Nov): a STREAMINFO counting a second of audio that the file
    doesn't hold is a file cut short, which filing now refuses (src/flac_check.py).
    """
    sample_rate, channels, bits_per_sample, total_samples = 44100, 2, 16, 0

    packed = (sample_rate << 44) | ((channels - 1) << 41) | ((bits_per_sample - 1) << 36) | total_samples

    streaminfo = (
        (4096).to_bytes(2, "big")      # min blocksize
        + (4096).to_bytes(2, "big")    # max blocksize
        + (0).to_bytes(3, "big")       # min framesize (0 = unknown)
        + (0).to_bytes(3, "big")       # max framesize
        + packed.to_bytes(8, "big")    # rate / channels / depth / sample count
        + b"\x00" * 16                 # md5 of the audio, unused here
    )
    assert len(streaminfo) == 34

    header = bytes([0x80]) + len(streaminfo).to_bytes(3, "big")  # last-block flag | type 0
    path.write_bytes(b"fLaC" + header + streaminfo)


def test_tags_are_written_from_the_release(tmp_path):
    """
    Uses a real FLAC so mutagen actually round-trips, rather than trusting that the tag call
    would have worked on a fake file.
    """
    from mutagen.flac import FLAC

    root = tmp_path / "downloads" / "MHTRTC"
    root.mkdir(parents=True)
    write_minimal_flac(root / "01 - Wildlife Analysis.flac")

    library = tmp_path / "music"
    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac"])
    execute_plan(plan_organization(job, str(tmp_path / "downloads"), str(library)), RELEASE)

    written = FLAC(str(library / "Boards of Canada" / "Music Has the Right to Children (1998)"
                       / "01 - Wildlife Analysis.flac"))
    assert written["album"][0] == "Music Has the Right to Children"
    assert written["artist"][0] == "Boards of Canada"
    assert written["title"][0] == "Wildlife Analysis"
    assert written["tracknumber"][0] == "1"
    assert written["musicbrainz_albumid"][0] == "mb-1"


def test_untaggable_file_is_still_filed(tmp_path):
    """A filed-but-untagged file beats a half-organized album."""
    root = seed_downloads(tmp_path, ["01 - Wildlife Analysis.flac"])  # not a real flac
    library = tmp_path / "music"
    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac"])

    results = execute_plan(plan_organization(job, str(root), str(library)), RELEASE)

    assert results["organized"] == 1
    assert results["failed"] == 0


# ---------------------------------------------------------------- end to end

def test_organize_job_end_to_end_moves_the_album_and_tidies_slskd_s_folder(tmp_path):
    root = seed_downloads(tmp_path, ["01 - Wildlife Analysis.flac", "02 - An Eagle in Your Mind.flac"])
    library = tmp_path / "music"
    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac",
                    r"share\BoC\MHTRTC\02 - An Eagle in Your Mind.flac"])
    told = []

    results = asyncio.run(organize_job(job, str(root), str(library), on_plan=told.append))

    album = library / "Boards of Canada" / "Music Has the Right to Children (1998)"
    assert results["organized"] == 2 and results["tracks_organized"] == 2
    assert results["plan"]["album_dir"] == str(album) and told == [results["plan"]]
    assert sorted(path.name for path in album.iterdir()) == ["01 - Wildlife Analysis.flac",
                                                             "02 - An Eagle in Your Mind.flac"]
    assert results["removed_dirs"] == [str(root / "MHTRTC")] and not (root / "MHTRTC").exists()
    assert "dry_run" not in results and "mode" not in results


def test_organize_job_reports_when_nothing_is_on_disk(tmp_path):
    root = tmp_path / "downloads"
    root.mkdir()
    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac"])

    results = asyncio.run(organize_job(job, str(root), str(tmp_path / "music")))

    assert results["organized"] == 0
    assert results["plan"]["problems"]


# ---------------------------------------------------------------- companions & cleanup

def seed_with_extras(tmp_path, audio, extras):
    folder = tmp_path / "downloads" / "MHTRTC"
    folder.mkdir(parents=True, exist_ok=True)
    for name in audio + extras:
        (folder / name).write_bytes(b"x")
    return tmp_path / "downloads"


def test_cover_art_is_carried_into_the_library(tmp_path):
    """Only audio is ever enqueued, so art left in slskd's folder would simply be lost."""
    root = seed_with_extras(tmp_path, ["01 - Wildlife Analysis.flac"], ["cover.jpg", "album.log"])
    library = tmp_path / "music"
    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac"])

    plan = plan_organization(job, str(root), str(library))
    assert plan["companion_count"] == 2

    execute_plan(plan, RELEASE)
    album = library / "Boards of Canada" / "Music Has the Right to Children (1998)"
    assert (album / "cover.jpg").exists()
    assert (album / "album.log").exists()
    #? moved with the tracks, like them
    assert not (root / "MHTRTC" / "cover.jpg").exists() and not (root / "MHTRTC" / "album.log").exists()


def test_unrelated_file_types_are_not_dragged_along(tmp_path):
    root = seed_with_extras(tmp_path, ["01 - Wildlife Analysis.flac"], ["setup.exe", "notes.doc"])
    plan = plan_organization(make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac"]),
                             str(root), str(tmp_path / "music"))
    assert plan["companion_count"] == 0


def test_move_removes_the_emptied_source_folder(tmp_path):
    root = seed_with_extras(tmp_path, ["01 - Wildlife Analysis.flac"], ["cover.jpg"])
    library = tmp_path / "music"
    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac"])

    results = asyncio.run(organize_job(job, str(root), str(library)))

    assert results["removed_dirs"]
    assert not (root / "MHTRTC").exists()


def test_a_filing_never_deletes_audio_it_did_not_file(tmp_path):
    """The clean-up runs after every filing now (until 2.1.13, only after a move): a folder still holding
    music nobody asked for - another job's, or files of this share not wanted - is kept, music and all."""
    root = seed_with_extras(tmp_path, ["01 - Wildlife Analysis.flac"], ["99 - Bonus.flac"])
    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac"])

    results = asyncio.run(organize_job(job, str(root), str(tmp_path / "music")))

    assert results["organized"] == 1 and results["removed_dirs"] == []
    assert (root / "MHTRTC" / "99 - Bonus.flac").exists()
    assert not (root / "MHTRTC" / "01 - Wildlife Analysis.flac").exists()


def test_source_is_kept_when_something_was_skipped(tmp_path):
    """A half-finished job must not have its source deleted out from under it."""
    root = seed_with_extras(tmp_path, ["01 - Wildlife Analysis.flac"], [])
    library = tmp_path / "music"
    destination = library / "Boards of Canada" / "Music Has the Right to Children (1998)" \
        / "01 - Wildlife Analysis.flac"
    destination.parent.mkdir(parents=True)
    destination.write_bytes(b"already here")

    job = make_job([r"share\BoC\MHTRTC\01 - Wildlife Analysis.flac"])
    results = asyncio.run(organize_job(job, str(root), str(library)))

    assert results["skipped"] == 1
    assert results["removed_dirs"] == []
    assert (root / "MHTRTC" / "01 - Wildlife Analysis.flac").exists()


def test_a_directory_outside_the_download_root_is_never_removed(tmp_path):
    """The containment guard: a stray path must not let the delete escape."""
    from src.organizer import cleanup_source_dirs

    outside = tmp_path / "somewhere-else"
    outside.mkdir()
    plan = {"source_dirs": [str(outside)]}

    removed = cleanup_source_dirs(plan, str(tmp_path / "downloads"), {"failed": 0, "skipped": 0})

    assert removed == []
    assert outside.exists()


def test_the_download_root_itself_is_never_removed(tmp_path):
    from src.organizer import cleanup_source_dirs

    root = tmp_path / "downloads"
    root.mkdir()
    removed = cleanup_source_dirs({"source_dirs": [str(root)]}, str(root), {"failed": 0, "skipped": 0})

    assert removed == []
    assert root.exists()


def test_leftovers_do_not_keep_an_emptied_download_folder_alive(tmp_path):
    """
    Asked for: "I'd like the album folder to be deleted when the songs are".

    It used to use rmdir, which refuses a non-empty folder by construction - so every share
    that came with a Thumbs.db, a checksum or a Scans/ folder kept its folder for ever with
    the music gone out of it. The sidecars worth having (art, cue, log, nfo, txt, m3u, sfv)
    moved into the library with the tracks before this runs.
    """
    from src.organizer import cleanup_source_dirs

    root = tmp_path / "downloads"
    folder = root / "MHTRTC"
    (folder / "Scans").mkdir(parents=True)
    (folder / "Scans" / "booklet.tif").write_bytes(b"x")
    (folder / "Thumbs.db").write_bytes(b"x")

    removed = cleanup_source_dirs({"source_dirs": [str(folder)]}, str(root), {"failed": 0, "skipped": 0})

    assert removed == [str(folder)]
    assert not folder.exists()


def test_a_folder_that_still_holds_MUSIC_is_kept_whatever_else_is_in_it(tmp_path):
    """
    The guard that replaced rmdir, and the reason a plain rmtree would not do.

    Audio still in there was never filed: a second job downloading into the same peer folder -
    whose files are still arriving - or tracks of it nobody asked for. Deleting it would take
    music that no library has a copy of.
    """
    from src.organizer import cleanup_source_dirs

    root = tmp_path / "downloads"
    folder = root / "MHTRTC"
    folder.mkdir(parents=True)
    (folder / "still-downloading.flac").write_bytes(b"x")
    (folder / "Thumbs.db").write_bytes(b"x")

    removed = cleanup_source_dirs({"source_dirs": [str(folder)]}, str(root), {"failed": 0, "skipped": 0})

    assert removed == []
    assert (folder / "still-downloading.flac").exists()


def test_music_in_a_SUBFOLDER_keeps_it_too(tmp_path):
    #? a two-disc share, where one disc is another job's
    from src.organizer import cleanup_source_dirs

    root = tmp_path / "downloads"
    folder = root / "MHTRTC"
    (folder / "Disc 2").mkdir(parents=True)
    (folder / "Disc 2" / "01.flac").write_bytes(b"x")

    assert cleanup_source_dirs({"source_dirs": [str(folder)]}, str(root), {"failed": 0, "skipped": 0}) == []
    assert (folder / "Disc 2" / "01.flac").exists()


def test_a_half_finished_job_still_has_its_folder_left_alone(tmp_path):
    #? unchanged, and load-bearing now that a delete takes the leftovers with it: a skip means
    #? files of this download never reached the library
    from src.organizer import cleanup_source_dirs

    root = tmp_path / "downloads"
    folder = root / "MHTRTC"
    folder.mkdir(parents=True)
    (folder / "note.txt").write_bytes(b"x")

    assert cleanup_source_dirs({"source_dirs": [str(folder)]}, str(root), {"failed": 0, "skipped": 1}) == []
    assert cleanup_source_dirs({"source_dirs": [str(folder)]}, str(root), {"failed": 1, "skipped": 0}) == []
    assert folder.exists()


# ---------------------------------------------------------------- one artist, one folder
#
# A release is credited to whatever the artist was calling themselves that year. Ye's records
# say "Kanye West" up to 2024 and "Ye" after, and filing by the credit put Donda in Kanye West/
# and BULLY in Ye/ - one artist, two folders, and two artists in anything that groups on the
# albumartist tag. `album_artist` is the current name, and it names the folder and that tag.

YE = "164f0d73-1234-4e2c-8743-d77bf2191051"

DONDA = {
    "artist": "Kanye West", "album_artist": "Ye", "artist_mbids": [YE],
    "album": "Donda", "year": "2021", "release_mbid": "donda",
    "tracks": [{"position": 1, "title": "Donda Chant", "artist": "Kanye West",
                "artist_mbids": [YE]}],
}

BULLY = {
    "artist": "Ye", "album_artist": "Ye", "artist_mbids": [YE],
    "album": "BULLY", "year": "2025", "release_mbid": "bully",
    "tracks": [{"position": 1, "title": "KING", "artist": "Ye", "artist_mbids": [YE]}],
}


def test_an_artist_who_renamed_is_filed_under_one_folder(tmp_path):
    donda = build_target_path(str(tmp_path), DONDA, DONDA["tracks"][0], "flac")
    bully = build_target_path(str(tmp_path), BULLY, BULLY["tracks"][0], "flac")

    assert donda.parent.parent == bully.parent.parent == tmp_path / "Ye"


def test_a_job_queued_before_the_current_name_existed_files_where_it_always_did(tmp_path):
    #? stored jobs carry the release denormalized, and one queued last week has no album_artist
    old = {key: value for key, value in DONDA.items() if key != "album_artist"}
    target = build_target_path(str(tmp_path), old, old["tracks"][0], "flac")
    assert target.parent.parent == tmp_path / "Kanye West"


def test_the_albumartist_tag_follows_the_folder_and_the_track_keeps_its_credit(tmp_path):
    """
    Folder and albumartist are one decision: the misfiled check compares them, so moving only
    the folder would flag the whole discography. The TRACK artist stays the credit - it is what
    the sleeve says, and a feature still reads as one.
    """
    from mutagen.flac import FLAC

    source = tmp_path / "downloads" / "Donda"
    source.mkdir(parents=True)
    write_minimal_flac(source / "01 - Donda Chant.flac")

    library = tmp_path / "music"
    job = make_job([r"share\Kanye West\Donda\01 - Donda Chant.flac"], release=DONDA,
                   directory=r"share\Kanye West\Donda")
    execute_plan(plan_organization(job, str(tmp_path / "downloads"), str(library)), DONDA)

    written = FLAC(str(library / "Ye" / "Donda (2021)" / "01 - Donda Chant.flac"))
    assert written["albumartist"] == ["Ye"]
    assert written["artist"] == ["Kanye West"]
    assert written["musicbrainz_albumartistid"] == [YE]


def test_the_download_request_does_not_drop_the_current_name():
    #? pydantic drops an undeclared field without a word, which is how disc numbers and track
    #? artists were each lost once - and losing this one files everything by its credit again
    from src.routes.download import EnqueueRelease

    assert EnqueueRelease(**DONDA).model_dump()["album_artist"] == "Ye"
    assert EnqueueRelease(artist="Kanye West").model_dump()["album_artist"] is None


# ---------------------------------------------------------------- a grab that names no release (v1.0.1)

def test_a_job_with_no_release_drops_the_sharers_release_id(tmp_path):
    """
    tag_values skips empty values, so a job naming no release used to leave the SHARER's
    musicbrainz_albumid in place - claiming a pressing nobody chose, which the scan and the
    "already held" checks both trust.
    """
    from mutagen.flac import FLAC
    from src.organizer import write_tags
    from tests.test_library import write_flac

    path = write_flac(tmp_path / "01.flac", musicbrainz_albumid="the-sharers-pressing", title="x")
    write_tags(path, {**RELEASE, "release_mbid": None, "release_group_mbid": "rg-1"}, RELEASE["tracks"][0],
               drop_stale_release_id=True)

    tags = FLAC(str(path))
    assert "musicbrainz_albumid" not in tags
    assert tags["musicbrainz_releasegroupid"] == ["rg-1"], "the group is known, so it is still written"


def test_a_job_that_names_its_release_writes_that_id(tmp_path):
    from mutagen.flac import FLAC
    from src.organizer import write_tags
    from tests.test_library import write_flac

    path = write_flac(tmp_path / "01.flac", musicbrainz_albumid="the-sharers-pressing")
    write_tags(path, RELEASE, RELEASE["tracks"][0])
    assert FLAC(str(path))["musicbrainz_albumid"] == ["mb-1"]


def test_the_editor_naming_no_release_leaves_the_files_id_alone(tmp_path):
    """
    The metadata editor shares write_tags. A retag naming no release previews no change to the
    release id, so the write must not remove one either (v1.0.2).
    """
    from mutagen.flac import FLAC
    from src.organizer import write_tags
    from tests.test_library import write_flac

    path = write_flac(tmp_path / "01.flac", musicbrainz_albumid="picard-wrote-this")
    write_tags(path, {**RELEASE, "release_mbid": None}, RELEASE["tracks"][0])
    assert FLAC(str(path))["musicbrainz_albumid"] == ["picard-wrote-this"]


# ---------------------------------------------------------------- a manual search, filed by its own tags (2.1.38)
#
# The iPhone and Mac app's Search Soulseek downloads a folder found by a typed artist and album, with no release
# behind it. It is filed by the files' OWN tags: the folder from the commonest of them by the library scan's own
# rule, only what a file lacks filled in (the typed words, for an untagged share), the sharer's release and
# release-group ids taken out, the files keeping their names - and never into a known pressing's folder.

from src.library_ledger import ADDED, FLAGGED, grant_for  # noqa: E402
from src.organizer import own_tags_release, resolve_album_dir, write_own_tags, write_tags  # noqa: E402

#? typed in lowercase, as a person types - the tags spell it their own way
TYPED = {"artist": "radiohead", "album_artist": "radiohead", "album": "ok computer", "year": None,
         "original_year": None, "release_mbid": None, "release_group_mbid": None, "edition_tags": [],
         "tracks": [], "manual": True}
SHARE = "share\\Radiohead\\OK Computer"

PICARD = {"album": "OK Computer", "albumartist": "Radiohead", "artist": "Radiohead", "date": "1997-05-21",
          "originaldate": "1997-05-21", "musicbrainz_albumid": "the-sharers-pressing",
          "musicbrainz_releasegroupid": "the-sharers-group", "musicbrainz_artistid": "radiohead-id",
          "musicbrainz_albumartistid": "radiohead-id"}


def manual_job(names, release=None, directory=SHARE, job_id=7):
    return {"id": job_id, "artist": "radiohead", "album": "ok computer", "username": "bob", "directory": directory,
            "release": release or TYPED,
            "files": [{"filename": f"{directory}\\{name}", "size": 1000} for name in names]}


def share(tmp_path, files: dict, folder="OK Computer"):
    """Real FLACs where slskd would have put them: {name: tags}, None for a file with no tags at all."""
    from tests.test_library import write_flac
    root = tmp_path / "downloads"
    for name, tags in files.items():
        path = root / folder / name
        if tags is None:
            path.parent.mkdir(parents=True, exist_ok=True)
            write_minimal_flac(path)
        else:
            write_flac(path, **tags)
    return root


def file_manually(tmp_path, files: dict, release=None, job_id=7, folder="OK Computer"):
    root = share(tmp_path, files, folder)
    library = tmp_path / "music"
    job = manual_job(list(files), release, job_id=job_id)
    plan = plan_organization(job, str(root), str(library))
    return plan, execute_plan(plan, job["release"]), library


def tags_of(path) -> dict:
    from mutagen.flac import FLAC
    return {key: list(values) for key, values in (FLAC(str(path)).tags or {}).as_dict().items()}


def scanned(library, path):
    from src import library as scan
    return next(a for a in scan.scan_library(str(library), force=True)["albums"] if a["path"] == path)


def test_picard_tagged_flacs_are_filed_by_their_own_tags_and_lose_only_the_sharers_ids(tmp_path):
    files = {"01 Airbag.flac": {**PICARD, "title": "Airbag", "tracknumber": "1", "discnumber": "1"},
             "02 Paranoid Android.flac": {**PICARD, "title": "Paranoid Android", "tracknumber": "2", "discnumber": "1"}}
    before = {name: {k: [v] for k, v in tags.items()} for name, tags in files.items()}
    plan, results, library = file_manually(tmp_path, files)

    album = library / "Radiohead" / "OK Computer (1997)"
    assert plan["album_dir"] == str(album) and plan["manual"] is True
    assert results["organized"] == 2 and results["failed"] == 0
    #? the sharer's names, kept
    assert sorted(p.name for p in album.iterdir()) == ["01 Airbag.flac", "02 Paranoid Android.flac"]
    for name in files:
        after = tags_of(album / name)
        #? everything as the sharer's tagger left it - titles, numbers, dates, artist ids - but the two ids
        assert after == {k: v for k, v in before[name].items()
                         if k not in ("musicbrainz_albumid", "musicbrainz_releasegroupid")}
        assert after["musicbrainz_artistid"] == ["radiohead-id"] and "musicbrainz_albumid" not in after


def test_a_compilations_own_artists_are_kept_track_by_track(tmp_path):
    comp = {"album": "Sounds of the Seventies", "albumartist": "Various Artists", "date": "2001"}
    files = {"01.flac": {**comp, "artist": "Can", "title": "Vitamin C"},
             "02.flac": {**comp, "artist": "Neu!", "title": "Hallogallo"}}
    plan, _, library = file_manually(tmp_path, files, {**TYPED, "artist": "various", "album": "seventies"})

    album = library / "Various Artists" / "Sounds of the Seventies (2001)"
    assert plan["album_dir"] == str(album)
    assert [tags_of(album / n)["artist"] for n in ("01.flac", "02.flac")] == [["Can"], ["Neu!"]]


def test_the_typed_words_never_overwrite_what_the_tags_say(tmp_path):
    files = {"01 Airbag.flac": {**PICARD, "title": "Airbag"}}
    _, _, library = file_manually(tmp_path, files)

    album = library / "Radiohead" / "OK Computer (1997)"
    assert [p.name for p in (library).iterdir()] == ["Radiohead"]
    values = {v for values in tags_of(album / "01 Airbag.flac").values() for v in values}
    assert not values & {"radiohead", "ok computer"}


def test_an_untagged_share_is_filed_and_filled_with_the_typed_words(tmp_path):
    files = {"01 Airbag.flac": None, "02 Paranoid Android.flac": None}
    plan, results, library = file_manually(tmp_path, files)

    album = library / "radiohead" / "ok computer"
    assert plan["album_dir"] == str(album) and results["organized"] == 2
    for name in files:
        tags = tags_of(album / name)
        assert tags == {"album": ["ok computer"], "artist": ["radiohead"], "albumartist": ["radiohead"]}
        #? no title or number is made up
        assert "title" not in tags and "tracknumber" not in tags


def test_a_mixed_share_gets_only_what_each_file_lacks(tmp_path):
    files = {"01.flac": {"album": "OK Computer", "albumartist": "Radiohead", "artist": "Radiohead", "title": "a"},
             "02.flac": {"artist": "Radiohead", "title": "b"},
             "03.flac": {"title": "c"}}
    _, _, library = file_manually(tmp_path, files)

    album = library / "Radiohead" / "OK Computer"
    assert tags_of(album / "01.flac") == {"album": ["OK Computer"], "albumartist": ["Radiohead"],
                                          "artist": ["Radiohead"], "title": ["a"]}
    #? the album it lacked; an artist and no albumartist gets no albumartist
    assert tags_of(album / "02.flac") == {"artist": ["Radiohead"], "title": ["b"], "album": ["OK Computer"]}
    #? neither, so both - the album's, which the tags gave, not the typed words
    assert tags_of(album / "03.flac") == {"title": ["c"], "album": ["OK Computer"], "artist": ["Radiohead"],
                                          "albumartist": ["Radiohead"]}


def test_a_two_album_folder_is_named_for_the_commonest_album_and_the_scan_says_so(tmp_path):
    from src.metadata_health import inspect_album
    tag = {"albumartist": "Radiohead", "artist": "Radiohead", "date": "1997"}
    files = {"01.flac": {**tag, "album": "OK Computer"}, "02.flac": {**tag, "album": "Kid A"},
             "03.flac": {**tag, "album": "OK Computer"}}
    plan, _, library = file_manually(tmp_path, files)

    assert Path(plan["album_dir"]).name == "OK Computer (1997)"
    issues = inspect_album(scanned(library, "Radiohead/OK Computer (1997)"))
    assert "mixed_tags" in issues and "misfiled" not in issues


def test_the_naming_is_the_commonest_of_the_tags_and_the_typed_words_only_where_none_has_one():
    tags = [{"album": "OK Computer", "albumartist": "", "artist": "Radiohead", "date": "1997-05-21",
             "originaldate": ""}, {"album": "OK Computer", "artist": "radiohead"}, {}]
    assert own_tags_release(TYPED, tags) == {
        "artist": "Radiohead", "album_artist": "Radiohead", "album": "OK Computer", "year": "1997",
        "original_year": "", "manual": True}
    assert own_tags_release(TYPED, [{}, {}]) == {
        "artist": "radiohead", "album_artist": "radiohead", "album": "ok computer", "year": "",
        "original_year": "", "manual": True}


def test_a_known_pressings_folder_of_that_name_is_never_shared(tmp_path):
    from tests.test_library import write_flac
    held = tmp_path / "music" / "Radiohead" / "OK Computer (1997)"
    write_flac(held / "01 - Airbag.flac", musicbrainz_albumid="the-pressing-i-matched", title="Airbag")

    plan, results, library = file_manually(tmp_path, {"01 Airbag.flac": {**PICARD, "title": "Airbag"}})

    assert Path(plan["album_dir"]).name == "OK Computer (1997) [unmatched]"
    assert results["organized"] == 1 and sorted(p.name for p in held.iterdir()) == ["01 - Airbag.flac"]


def test_an_unmatched_folder_held_by_a_pressing_too_means_the_jobs_own(tmp_path):
    from tests.test_library import write_flac
    for name in ("OK Computer (1997)", "OK Computer (1997) [unmatched]"):
        write_flac(tmp_path / "music" / "Radiohead" / name / "01.flac", musicbrainz_albumid=f"id-{name}")

    plan, _, _ = file_manually(tmp_path, {"01 Airbag.flac": {**PICARD, "title": "Airbag"}}, job_id=42)
    assert Path(plan["album_dir"]).name == "OK Computer (1997) [unmatched-42]"


def test_a_folder_naming_a_pressing_in_any_file_is_never_shared_though_its_first_is_untagged(tmp_path):
    """
    Review (2026-11-24): read_album_mbid answers from the first file alone, so a hidden track with no tags
    sorted first made a matched pressing's folder read as untagged, and the manual download joined it.
    """
    from tests.test_library import write_flac
    held = tmp_path / "music" / "Radiohead" / "OK Computer (1997)"
    write_flac(held / "00 Hidden.flac", title="Hidden")
    for n, title in ((1, "Airbag"), (2, "Paranoid Android"), (3, "Subterranean Homesick Alien")):
        write_flac(held / f"0{n} - {title}.flac", musicbrainz_albumid="the-pressing-i-matched", title=title)

    plan, results, _ = file_manually(tmp_path, {"01 Airbag.flac": {**PICARD, "title": "Airbag"}})

    assert Path(plan["album_dir"]).name == "OK Computer (1997) [unmatched]"
    assert results["organized"] == 1 and len(list(held.iterdir())) == 4


def test_a_folder_that_cannot_be_read_counts_as_holding_a_release(tmp_path, monkeypatch):
    from src.organizer import holds_album_id
    assert holds_album_id(tmp_path) is False and holds_album_id(tmp_path / "not there") is False

    def unreadable(self):
        raise PermissionError(13, "Permission denied")
    monkeypatch.setattr(Path, "iterdir", unreadable)
    assert holds_album_id(tmp_path) is True


def test_an_untagged_folder_of_that_name_is_shared_and_its_titles_are_not_filed_twice(tmp_path):
    from tests.test_library import write_flac
    held = tmp_path / "music" / "Radiohead" / "OK Computer (1997)"
    write_flac(held / "Airbag.mp3.flac", title="Airbag")
    files = {"01 Airbag.flac": {**PICARD, "title": "Airbag"},
             "02 Paranoid Android.flac": {**PICARD, "title": "Paranoid Android"}}

    plan, results, _ = file_manually(tmp_path, files)

    assert plan["album_dir"] == str(held)
    assert (results["organized"], results["duplicates"]) == (1, 1)
    assert sorted(p.name for p in held.iterdir()) == ["02 Paranoid Android.flac", "Airbag.mp3.flac"]


def test_the_template_reads_unmatched_back_so_the_folder_still_matches_its_tags(tmp_path):
    from src.metadata_health import inspect_album
    from tests.test_library import write_flac
    write_flac(tmp_path / "music" / "Radiohead" / "OK Computer (1997)" / "x.flac", musicbrainz_albumid="known",
               album="OK Computer", albumartist="Radiohead", date="1997")
    file_manually(tmp_path, {"01 Airbag.flac": {**PICARD, "title": "Airbag"}})

    issues = inspect_album(scanned(tmp_path / "music", "Radiohead/OK Computer (1997) [unmatched]"))
    assert "no_release" in issues and "misfiled" not in issues


def test_a_set_shared_one_folder_per_disc_files_every_track_with_its_disc_before_its_name(tmp_path):
    root = tmp_path / "downloads"
    for disc in ("CD1", "CD2"):
        (root / disc).mkdir(parents=True)
        write_minimal_flac(root / disc / "01.flac")
        write_minimal_flac(root / disc / "02.flac")
    library = tmp_path / "music"
    job = manual_job([f"CD{d}\\0{n}.flac" for d in (1, 2) for n in (1, 2)])

    plan = plan_organization(job, str(root), str(library))
    results = execute_plan(plan, job["release"])

    assert plan["problems"] == [] and results["organized"] == 4
    assert sorted(p.name for p in (library / "radiohead" / "ok computer").iterdir()) == [
        "1-01.flac", "1-02.flac", "2-01.flac", "2-02.flac"]


def test_the_disc_a_file_is_tagged_with_names_it_before_its_folder_does(tmp_path):
    files = {"01.flac": {**PICARD, "discnumber": "1", "title": "a"},
             "01 (2).flac": {**PICARD, "discnumber": "2/2", "title": "b"}}
    _, _, library = file_manually(tmp_path, files)
    assert sorted(p.name for p in (library / "Radiohead" / "OK Computer (1997)").iterdir()) == [
        "1-01.flac", "2-01 (2).flac"]


def test_one_disc_is_never_given_a_prefix(tmp_path):
    files = {"01.flac": {**PICARD, "discnumber": "1"}, "02.flac": {**PICARD, "discnumber": "1"}}
    _, _, library = file_manually(tmp_path, files)
    assert sorted(p.name for p in (library / "Radiohead" / "OK Computer (1997)").iterdir()) == ["01.flac", "02.flac"]


def test_a_set_whose_files_are_all_tagged_disc_one_is_told_apart_by_its_folders(tmp_path):
    """Review (2026-11-24): CD1/01.flac and CD2/01.flac, both tagged disc 1, met on one name and half the set
    wasn't filed, with nothing failed."""
    from tests.test_library import write_flac
    root = tmp_path / "downloads"
    for disc in (1, 2):
        for n in (1, 2):
            write_flac(root / f"CD{disc}" / f"0{n}.flac", **PICARD, discnumber="1", tracknumber=str(n),
                       title=f"disc {disc} track {n}")
    library = tmp_path / "music"
    job = manual_job([f"CD{d}\\0{n}.flac" for d in (1, 2) for n in (1, 2)])

    plan = plan_organization(job, str(root), str(library))
    results = execute_plan(plan, job["release"])

    assert plan["problems"] == [] and (results["organized"], results["failed"]) == (4, 0)
    assert sorted(p.name for p in (library / "Radiohead" / "OK Computer (1997)").iterdir()) == [
        "1-01.flac", "1-02.flac", "2-01.flac", "2-02.flac"]


@pytest.mark.parametrize("bad", ["-1", "0"])
def test_a_disc_tag_below_one_is_no_disc(tmp_path, bad):
    files = {"a.flac": {**PICARD, "discnumber": bad, "title": "a"}, "b.flac": {**PICARD, "discnumber": "1", "title": "b"},
             "c.flac": {**PICARD, "discnumber": "2", "title": "c"}}
    _, _, library = file_manually(tmp_path, files)
    assert sorted(p.name for p in (library / "Radiohead" / "OK Computer (1997)").iterdir()) == [
        "1-b.flac", "2-c.flac", "a.flac"]


def test_two_files_that_would_be_filed_under_one_name_are_told_apart_by_their_folders(tmp_path):
    from tests.test_library import write_flac
    root = tmp_path / "downloads"
    for side in ("Side A", "Side B"):
        write_flac(root / side / "01.flac", **PICARD, title=side)
    library = tmp_path / "music"
    job = manual_job(["Side A\\01.flac", "Side B\\01.flac"])

    results = execute_plan(plan_organization(job, str(root), str(library)), job["release"])

    assert (results["organized"], results["failed"]) == (2, 0)
    assert sorted(p.name for p in (library / "Radiohead" / "OK Computer (1997)").iterdir()) == [
        "Side A-01.flac", "Side B-01.flac"]


def test_no_two_sources_are_ever_given_one_name(tmp_path):
    """Names that differ only in case meet on a case-insensitive disk: what's left after the folders is numbered."""
    from src.organizer import _manual_names
    from tests.test_library import write_flac
    located = []
    for n, name in enumerate(["01.flac", "01.FLAC", "x/01.flac", "x/01.Flac"]):
        write_flac(tmp_path / f"{n}.flac", title=str(n))
        located.append(({"filename": f"share\\Album\\{name}"}, tmp_path / f"{n}.flac"))

    _, tags = _manual_names(located)

    filed = [read["filename"] for read in tags.values()]
    assert len({name.casefold() for name in filed}) == 4, filed


@pytest.mark.parametrize("files, path", [
    ({"01 Airbag.flac": {**PICARD, "title": "Airbag", "tracknumber": "1"},
      "02 Paranoid Android.flac": {**PICARD, "title": "Paranoid Android", "tracknumber": "2"}},
     "Radiohead/OK Computer (1997)"),
    ({"01.flac": {**PICARD, "originaldate": "1997", "date": "2017", "title": "a"},
      "02.flac": {"title": "b"}}, "Radiohead/OK Computer (1997)"),
    ({"01.flac": None, "02.flac": None}, "radiohead/ok computer"),
    ({"01.flac": {"artist": "Radiohead", "date": "1997"}, "02.flac": {"title": "b"}}, "Radiohead/ok computer (1997)"),
])
def test_the_filed_album_reads_back_as_what_its_tags_say(tmp_path, files, path):
    """
    What ties the naming to the scan's rule: Needs a look says it isn't matched to MusicBrainz - the hook for
    Release - and neither that its folder disagrees with its tags nor that its artist is filed twice.
    """
    from src.metadata_health import inspect_album
    _, _, library = file_manually(tmp_path, files)

    issues = inspect_album(scanned(library, path))
    assert "no_release" in issues
    assert "misfiled" not in issues and "artist_split" not in issues


def test_a_manual_plan_touches_nothing(tmp_path):
    root = share(tmp_path, {"01 Airbag.flac": {**PICARD, "title": "Airbag"}, "02.flac": None})
    library = tmp_path / "music"
    before = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in root.rglob("*") if p.is_file()}

    plan = plan_organization(manual_job(["01 Airbag.flac", "02.flac"]), str(root), str(library))

    assert plan["operations"] and not library.exists()
    assert {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in root.rglob("*") if p.is_file()} == before
    #? what it will fill, written in the plan rather than worked out again when it's executed
    assert [op["fill"] for op in plan["operations"]] == [
        {}, {"album": "OK Computer", "artist": "Radiohead", "albumartist": "Radiohead"}]
    assert plan["naming"]["album"] == "OK Computer"


def test_an_unreadable_file_is_filed_and_filled_rather_than_raising(tmp_path):
    root = seed_downloads(tmp_path, ["01.flac", "02.flac"], subdir="OK Computer")  # not real FLACs
    library = tmp_path / "music"
    job = manual_job(["01.flac", "02.flac"])

    plan = plan_organization(job, str(root), str(library))
    results = execute_plan(plan, job["release"])

    assert (results["organized"], results["failed"]) == (2, 0)
    assert sorted(p.name for p in (library / "radiohead" / "ok computer").iterdir()) == ["01.flac", "02.flac"]


def test_a_manual_filing_is_given_and_one_with_everything_already_there_is_flagged(tmp_path):
    from tests.test_library import write_flac
    plan, results, _ = file_manually(tmp_path, {"01 Airbag.flac": {**PICARD, "title": "Airbag"}})
    assert grant_for(results, plan["same_release"]) == ADDED

    again = tmp_path / "again"
    write_flac(again / "music" / "Radiohead" / "OK Computer (1997)" / "Airbag.flac", title="Airbag")
    plan, results, _ = file_manually(again, {"01 Airbag.flac": {**PICARD, "title": "Airbag"}})
    assert (results["organized"], results["skipped"]) == (0, 1)
    assert grant_for(results, plan["same_release"]) == FLAGGED


def test_write_own_tags_sets_only_what_it_is_given_and_drops_the_two_ids(tmp_path):
    from tests.test_library import write_flac
    path = write_flac(tmp_path / "01.flac", **PICARD, title="Airbag")
    write_own_tags(path, {})
    after = tags_of(path)
    assert "musicbrainz_albumid" not in after and "musicbrainz_releasegroupid" not in after
    assert after["album"] == ["OK Computer"] and after["musicbrainz_albumartistid"] == ["radiohead-id"]


def test_an_m4a_loses_its_sharers_release_group_too(tmp_path):
    """Easy MP4 has no name for it, so the atom the scan reads raw is taken out itself."""
    from mutagen.mp4 import MP4, MP4FreeForm
    from src import library as scan
    from tests.test_disc_titles import TINY_M4A
    path = tmp_path / "01.m4a"
    path.write_bytes(TINY_M4A)
    mp4 = MP4(str(path))
    mp4.tags[scan.MP4_RELEASE_GROUP_ATOM] = [MP4FreeForm(b"the-sharers-group")]
    mp4.tags["----:com.apple.iTunes:MusicBrainz Album Id"] = [MP4FreeForm(b"the-sharers-pressing")]
    mp4.save()

    write_own_tags(path, {"album": "ok computer"})

    tags = MP4(str(path)).tags
    assert scan.MP4_RELEASE_GROUP_ATOM not in tags and "----:com.apple.iTunes:MusicBrainz Album Id" not in tags
    assert scan.read_track(path)["album"] == "ok computer"


# ---- a question without `manual`: exactly as at 2.1.37 (the group fallback - MusicBrainz couldn't list pressings)

GROUP_FALLBACK = {"artist": "Portishead", "album_artist": "Portishead", "album": "Dummy", "year": "1994",
                  "original_year": "1994", "release_mbid": None, "release_group_mbid": "rg-dummy",
                  "edition_tags": [], "tracks": []}


@pytest.mark.parametrize("release", [GROUP_FALLBACK, {**GROUP_FALLBACK, "manual": False}])
def test_a_release_less_job_without_manual_is_planned_and_tagged_exactly_as_before(tmp_path, release):
    root = share(tmp_path, {"01 Mysterons.flac": {**PICARD, "title": "Mysterons", "artist": "portishead"},
                            "02.flac": None}, folder="Dummy")
    library = tmp_path / "music"
    job = {"id": 3, "artist": "Portishead", "album": "Dummy", "username": "bob", "directory": "share\\Dummy",
           "release": release, "files": [{"filename": f"share\\Dummy\\{n}", "size": 1000}
                                         for n in ("01 Mysterons.flac", "02.flac")]}

    plan = plan_organization(job, str(root), str(library))

    album = library / "Portishead" / "Dummy (1994)"
    assert plan == {
        "job_id": 3, "album_dir": str(album), "companion_count": 0,
        "operations": [
            {"source": str(root / "Dummy" / "01 Mysterons.flac"), "target": str(album / "01 Mysterons.flac"),
             "track": None, "exists": False},
            {"source": str(root / "Dummy" / "02.flac"), "target": str(album / "02.flac"), "track": None,
             "exists": False}],
        "source_dirs": [str(root / "Dummy")], "read_only_dirs": [], "overlap": None, "problems": [],
        "matched_tracks": 0, "total_tracks": 0, "same_release": False,
        #? (damaged downloads) every plan says which songs were found damaged, and how many it had
        "damaged": [], "songs": 2,
    }

    execute_plan(plan, release)
    #? the album's words over every file, the release group written, the sharer's pressing gone - as before
    assert tags_of(album / "01 Mysterons.flac") == {
        "album": ["Dummy"], "albumartist": ["Portishead"], "artist": ["Portishead"], "date": ["1994"],
        "originaldate": ["1994"], "musicbrainz_releasegroupid": ["rg-dummy"],
        "musicbrainz_artistid": ["radiohead-id"], "musicbrainz_albumartistid": ["radiohead-id"],
        "title": ["Mysterons"]}
    assert tags_of(album / "02.flac") == {
        "album": ["Dummy"], "albumartist": ["Portishead"], "artist": ["Portishead"], "date": ["1994"],
        "originaldate": ["1994"], "musicbrainz_releasegroupid": ["rg-dummy"]}


def test_resolve_album_dir_without_manual_still_shares_any_folder_for_a_job_naming_no_release(tmp_path):
    from tests.test_library import write_flac
    held = tmp_path / "Portishead" / "Dummy (1994)"
    write_flac(held / "01.flac", musicbrainz_albumid="a-pressing")
    assert resolve_album_dir(str(tmp_path), GROUP_FALLBACK) == (held, "")


def test_write_tags_is_still_what_a_non_manual_filing_uses():
    assert "write_tags(target, release" in inspect.getsource(execute_plan)
    assert write_tags is not write_own_tags
