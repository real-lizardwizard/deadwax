"""
Removing the partial files a cancelled download leaves behind.

This deletes files deadwax did not create, in a folder belonging to another application, so
it is written and tested like delete_album() rather than like the organizer.

The thing to understand before changing any of it: **slskd keeps partial files on purpose.** It
stores one at `<incomplete>/<username>/<remote path>/<file>` and, with `retry.partial` set to
Resume, starts the next attempt at that file's length rather than at zero. A leftover is a
feature for a download that failed and junk only for one that was deliberately cancelled - which
is why this runs on cancel alone, and does nothing until SLSKD_INCOMPLETE_PATH says where to
look.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.organizer import remove_incomplete_downloads  # noqa: E402


def seed(root: Path, username: str, remote_dir: str, *names: str) -> Path:
    """Lay out a partial download the way slskd does: incomplete/user/remote path/file."""
    directory = root / username / remote_dir
    directory.mkdir(parents=True, exist_ok=True)
    for name in names:
        (directory / name).write_bytes(b"partial")
    return directory


FILES = [{"filename": "@@abc\\Music\\Album\\01 - One.flac"},
         {"filename": "@@abc\\Music\\Album\\02 - Two.flac"}]


def test_the_partial_files_are_removed(tmp_path):
    seed(tmp_path, "bob", "Album", "01 - One.flac", "02 - Two.flac")

    result = remove_incomplete_downloads(str(tmp_path), FILES, "@@abc\\Music\\Album")

    assert len(result["removed"]) == 2
    assert result["problem"] is None
    assert not list(tmp_path.rglob("*.flac"))


def test_the_emptied_folders_go_too(tmp_path):
    """Otherwise the incomplete folder fills with empty directories instead of files."""
    seed(tmp_path, "bob", "Album", "01 - One.flac", "02 - Two.flac")

    remove_incomplete_downloads(str(tmp_path), FILES, "@@abc\\Music\\Album")

    assert not (tmp_path / "bob" / "Album").exists()
    assert not (tmp_path / "bob").exists()
    assert tmp_path.exists(), "the incomplete folder itself is never removed"


def test_a_folder_still_holding_something_is_left_alone(tmp_path):
    """
    rmdir refuses a non-empty directory by construction, which is the guard. Anything still in
    there is another download's, and not ours to tidy.
    """
    directory = seed(tmp_path, "bob", "Album", "01 - One.flac", "02 - Two.flac")
    (directory / "somebody elses.flac").write_bytes(b"partial")

    remove_incomplete_downloads(str(tmp_path), FILES, "@@abc\\Music\\Album")

    assert directory.exists()
    assert (directory / "somebody elses.flac").exists()


def test_nothing_happens_without_a_configured_path(tmp_path):
    """
    The default. Not setting the path keeps slskd's own behaviour, where the partial is
    retained so a retry can resume from it - so this must be inert, not best-effort.
    """
    seed(tmp_path, "bob", "Album", "01 - One.flac")

    result = remove_incomplete_downloads("", FILES, "@@abc\\Music\\Album")

    assert result["removed"] == []
    assert "not set" in result["problem"]
    assert list(tmp_path.rglob("*.flac")), "the file is still there"


def test_a_missing_incomplete_folder_is_reported_not_guessed(tmp_path):
    result = remove_incomplete_downloads(str(tmp_path / "nope"), FILES, "@@abc\\Music\\Album")

    assert result["removed"] == []
    assert "isn't there" in result["problem"]


def test_a_file_in_a_different_folder_is_not_touched(tmp_path):
    """
    Matching is by basename, because slskd sanitizes the remote path into the name on disk and
    that mapping is its business. So the folder check is what stops it reaching into an
    unrelated download that happens to contain the same track name.
    """
    seed(tmp_path, "bob", "Album", "01 - One.flac")
    seed(tmp_path, "bob", "A Different Album", "01 - One.flac")

    remove_incomplete_downloads(str(tmp_path), [FILES[0]], "@@abc\\Music\\Album")

    assert not (tmp_path / "bob" / "Album" / "01 - One.flac").exists()
    assert (tmp_path / "bob" / "A Different Album" / "01 - One.flac").exists()


def test_an_ambiguous_basename_is_skipped_rather_than_guessed(tmp_path):
    """
    Two users part-way through the same album, and no remote folder to tell them apart. Guessing
    wrong here deletes somebody else's download, so it declines and says so - the opposite of
    find_local_file, which guesses because the cost of being wrong there is only a misfiled
    track.
    """
    seed(tmp_path, "bob", "Album", "01 - One.flac")
    seed(tmp_path, "carol", "Album", "01 - One.flac")

    result = remove_incomplete_downloads(str(tmp_path), [FILES[0]], "")

    assert result["removed"] == []
    assert any("several partial files" in s for s in result["skipped"])
    assert len(list(tmp_path.rglob("01 - One.flac"))) == 2


def test_a_symlink_pointing_out_of_the_incomplete_folder_is_refused(tmp_path):
    """
    The same containment guard delete_album carries. `is_within` resolves both sides, so neither
    a symlink nor a '..' in the configured path can walk the delete out of the folder.
    """
    outside = tmp_path / "outside"
    outside.mkdir()
    precious = outside / "01 - One.flac"
    precious.write_bytes(b"not yours")

    incomplete = tmp_path / "incomplete"
    (incomplete / "bob" / "Album").mkdir(parents=True)
    (incomplete / "bob" / "Album" / "01 - One.flac").symlink_to(precious)

    result = remove_incomplete_downloads(str(incomplete), [FILES[0]], "@@abc\\Music\\Album")

    #? The target surviving is not evidence on its own - unlink() removes a symlink rather than
    #? what it points at, so that would hold with no guard at all. The guard is what makes this
    #? a REFUSAL: the link is still there and the reason was reported.
    assert result["removed"] == []
    assert any("outside the incomplete folder" in s for s in result["skipped"])
    assert (incomplete / "bob" / "Album" / "01 - One.flac").is_symlink(), "refused, so left alone"
    assert precious.exists(), "and the file it pointed at is untouched"


def test_files_that_were_never_written_are_not_an_error(tmp_path):
    """A download cancelled before anything arrived has nothing to clean up."""
    (tmp_path / "bob").mkdir()

    result = remove_incomplete_downloads(str(tmp_path), FILES, "@@abc\\Music\\Album")

    assert result["removed"] == []
    assert result["skipped"] == []
    assert result["problem"] is None


# ----- empty folders slskd leaves behind (v0.9.6) -----
#
# slskd writes to <incomplete>/<user>/<remote path>/<file>, creating every level, and on
# completion deletes only the one folder the file sat in. Everything above stays, empty, for
# every download it ever finished - which is what James found piling up.

import os  # noqa: E402

from src.organizer import EMPTY_DIR_MIN_AGE_SECONDS, remove_empty_incomplete_dirs  # noqa: E402

OLD = 1_000_000.0
NOW = OLD + EMPTY_DIR_MIN_AGE_SECONDS + 1


def age(*paths, at=OLD):
    for path in paths:
        os.utime(path, (at, at))


def test_the_levels_slskd_leaves_above_a_finished_download_are_removed(tmp_path):
    #? what a completed download leaves: slskd removed "Dummy", nothing above it
    left = tmp_path / "bob" / "@@music" / "Portishead"
    left.mkdir(parents=True)
    age(left, left.parent, left.parent.parent)

    removed = remove_empty_incomplete_dirs(str(tmp_path), now=NOW)

    assert sorted(Path(p).relative_to(tmp_path).as_posix() for p in removed) == [
        "bob", "bob/@@music", "bob/@@music/Portishead"]
    assert tmp_path.is_dir() and list(tmp_path.iterdir()) == []


def test_a_folder_with_a_partial_in_it_and_everything_above_it_stays(tmp_path):
    #? a FAILED download's partial is what lets slskd resume it - it and its path stay
    kept = seed(tmp_path, "bob", "Album", "01 - One.flac")
    empty = tmp_path / "alice" / "Other"
    empty.mkdir(parents=True)
    age(kept, kept.parent, empty, empty.parent)

    remove_empty_incomplete_dirs(str(tmp_path), now=NOW)

    assert (kept / "01 - One.flac").is_file()
    assert not (tmp_path / "alice").exists()


def test_a_folder_slskd_has_only_just_made_is_left_for_it(tmp_path):
    #? created for a download that is about to open its file inside it
    fresh = tmp_path / "bob" / "New Album"
    fresh.mkdir(parents=True)
    age(fresh.parent)
    age(fresh, at=NOW - 5)

    remove_empty_incomplete_dirs(str(tmp_path), now=NOW)

    assert fresh.is_dir()
    assert fresh.parent.is_dir()  # not empty: it holds the fresh one


def test_the_root_itself_is_never_removed_even_when_empty(tmp_path):
    root = tmp_path / "incomplete"
    root.mkdir()
    age(root)
    assert remove_empty_incomplete_dirs(str(root), now=NOW) == []
    assert root.is_dir()


def test_a_link_out_of_the_folder_is_not_followed(tmp_path):
    outside = tmp_path / "outside" / "empty"
    outside.mkdir(parents=True)
    root = tmp_path / "incomplete"
    root.mkdir()
    (root / "link").symlink_to(outside.parent)
    age(outside, outside.parent)

    remove_empty_incomplete_dirs(str(root), now=NOW)

    assert outside.is_dir()
    assert (root / "link").is_symlink()


def test_no_folder_configured_does_nothing():
    assert remove_empty_incomplete_dirs("", now=NOW) == []


def test_the_poller_sweeps_only_where_it_has_been_told_to(tmp_path, monkeypatch):
    import asyncio

    from src.config import Config
    from src.poller import sweep_empty_incomplete_dirs

    left = tmp_path / "bob" / "share"
    left.mkdir(parents=True)
    age(left, left.parent)

    monkeypatch.setattr(Config, "SLSKD_INCOMPLETE_PATH", None)
    assert asyncio.run(sweep_empty_incomplete_dirs()) == 0
    assert left.is_dir()

    monkeypatch.setattr(Config, "SLSKD_INCOMPLETE_PATH", str(tmp_path))
    assert asyncio.run(sweep_empty_incomplete_dirs()) == 2
    assert not (tmp_path / "bob").exists()


def test_a_set_shared_one_folder_per_disc_is_found_disc_by_disc(tmp_path):
    """
    A joined set's job directory is the album folder, but slskd keeps each partial under its own
    disc folder. Judged by the job's directory, no partial of it would ever match; each file's
    own folder finds it - and only it, since both discs hold a "01 - Intro.flac".
    """
    seed(tmp_path, "bob", "Album/CD 1", "01 - Intro.flac")
    seed(tmp_path, "bob", "Album/CD 2", "01 - Intro.flac")
    files = [{"filename": "@@abc\\Music\\Album\\CD 1\\01 - Intro.flac"},
             {"filename": "@@abc\\Music\\Album\\CD 2\\01 - Intro.flac"}]

    result = remove_incomplete_downloads(str(tmp_path), files, "@@abc\\Music\\Album")

    assert sorted(Path(p).parent.name for p in result["removed"]) == ["CD 1", "CD 2"]
    assert not list(tmp_path.rglob("*.flac"))
