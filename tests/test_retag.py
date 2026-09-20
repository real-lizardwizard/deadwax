"""
Applying a release to an album already in the library.

This is the second thing in jimbrainz that writes to the user's filesystem, and unlike the
organizer it operates on files the user already had rather than ones we just downloaded. The
guards matter more than the happy path here, so most of these are about what it refuses.
"""

import shutil
from pathlib import Path

import pytest
from mutagen.flac import FLAC

from src.retag import execute_retag, plan_retag, read_current_tags

STREAMINFO = (
    b"fLaC" + b"\x80\x00\x00\x22"
    + b"\x10\x00\x10\x00\x00\x00\x00\x00\x00\x00\x0a\xc4\x42\xf0\x00\x00\x00\x00" + b"\x00" * 16
)


def write_flac(path, **tags):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(STREAMINFO)
    audio = FLAC(str(path))
    for key, value in tags.items():
        audio[key] = str(value)
    audio.save()
    return path


def seed(root, artist="Tame Impala", folder="The Slow Rush (2020)", album="The Slow Rush",
         titles=("One More Year", "Instant Destiny"), **extra):
    directory = root / artist / folder
    for n, title in enumerate(titles, start=1):
        write_flac(directory / f"{n:02d} - {title}.flac", album=album, albumartist=artist,
                   artist=artist, title=title, tracknumber=str(n), date="2020", **extra)
    return directory


RELEASE = {
    "artist": "Tame Impala",
    "album": "The Slow Rush",
    "year": "2020",
    "release_mbid": "mbid-deluxe",
    "disambiguation": "deluxe edition",
    "tracks": [
        {"position": 1, "title": "One More Year", "length_ms": 1000},
        {"position": 2, "title": "Instant Destiny", "length_ms": 1000},
    ],
}


# ---------------------------------------------------------------- planning

def test_plan_reports_the_tags_that_would_change(tmp_path):
    seed(tmp_path)
    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path))

    assert plan["file_count"] == 2
    assert plan["matched_tracks"] == 2
    assert plan["changed_file_count"] == 2

    first = plan["files"][0]
    #? the album already carried these, so they aren't listed as changes
    assert "album" not in first["changes"]
    #? but it had no MBID, so that's new
    assert first["changes"]["musicbrainz_albumid"] == {"from": "", "to": "mbid-deluxe"}


def test_plan_writes_nothing(tmp_path):
    directory = seed(tmp_path)
    before = {p.name: p.read_bytes() for p in directory.iterdir()}

    plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path))

    assert {p.name: p.read_bytes() for p in directory.iterdir()} == before


def test_plan_targets_the_edition_aware_folder_name(tmp_path):
    """A hand-corrected album should land where a freshly downloaded one would have."""
    seed(tmp_path)
    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path))

    assert plan["moves"] is True
    assert plan["target_path"] == "Tame Impala/The Slow Rush (2020) [Deluxe edition]"
    assert plan["edition_label"] == "Deluxe edition"


def test_plan_does_not_move_when_the_name_is_already_right(tmp_path):
    seed(tmp_path, folder="The Slow Rush (2020) [Deluxe edition]")
    plan = plan_retag("Tame Impala/The Slow Rush (2020) [Deluxe edition]", RELEASE, str(tmp_path))
    assert plan["moves"] is False


def test_plan_refuses_to_merge_into_an_existing_folder(tmp_path):
    """Two albums becoming one is not something to do quietly."""
    seed(tmp_path)
    (tmp_path / "Tame Impala" / "The Slow Rush (2020) [Deluxe edition]").mkdir(parents=True)

    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path))

    assert plan["moves"] is False
    assert any("already exists" in p for p in plan["problems"])


def test_plan_flags_a_tracklist_that_does_not_fit(tmp_path):
    seed(tmp_path, titles=("One More Year",))
    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path))
    assert any("2 track(s) but the folder has 1" in p for p in plan["problems"])


def test_unmatched_files_keep_their_own_title_and_number(tmp_path):
    """A wrong track number is worse than none - same rule as the organizer."""
    seed(tmp_path, titles=("One More Year", "Something Else Entirely"))
    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path))

    unmatched = [f for f in plan["files"] if not f["matched"]]
    assert len(unmatched) == 1
    assert "title" not in unmatched[0]["changes"]
    assert "tracknumber" not in unmatched[0]["changes"]
    assert any("didn't match the tracklist" in p for p in plan["problems"])


@pytest.mark.parametrize("attempt", ["../../../etc", "", "/etc", "Tame Impala/../../.."])
def test_plan_refuses_anything_outside_the_library(tmp_path, attempt):
    seed(tmp_path)
    plan = plan_retag(attempt, RELEASE, str(tmp_path))
    assert plan["source"] is None
    assert plan["problems"] == ["that album is not inside the library"]


def test_plan_refuses_a_symlink_out_of_the_library(tmp_path):
    import os
    outside = tmp_path.parent / "outside-retag"
    outside.mkdir(exist_ok=True)
    write_flac(outside / "01 - Track.flac", album="Elsewhere")

    seed(tmp_path)
    os.symlink(outside, tmp_path / "escape")

    assert plan_retag("escape", RELEASE, str(tmp_path))["source"] is None


# ---------------------------------------------------------------- executing

def test_dry_run_changes_nothing_on_disk(tmp_path):
    directory = seed(tmp_path)
    before = {p.name: p.read_bytes() for p in directory.iterdir()}

    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path))
    results = execute_retag(plan, RELEASE, "dry_run")

    assert results["dry_run"] is True
    assert results["tagged"] == 2
    assert directory.exists()
    assert {p.name: p.read_bytes() for p in directory.iterdir()} == before


def test_apply_writes_the_tags_and_refiles_the_folder(tmp_path):
    seed(tmp_path)
    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path))
    results = execute_retag(plan, RELEASE, "apply")

    moved = tmp_path / "Tame Impala" / "The Slow Rush (2020) [Deluxe edition]"
    assert results["failed"] == 0
    assert results["moved_to"] == str(moved)
    assert moved.is_dir()
    assert not (tmp_path / "Tame Impala" / "The Slow Rush (2020)").exists()

    tags = read_current_tags(sorted(moved.glob("*.flac"))[0])
    assert tags["musicbrainz_albumid"] == "mbid-deluxe"
    assert tags["title"] == "One More Year"


def test_applying_twice_is_a_no_op_the_second_time(tmp_path):
    """The album is already correct, so there is nothing left to change."""
    seed(tmp_path)
    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path))
    execute_retag(plan, RELEASE, "apply")

    again = plan_retag("Tame Impala/The Slow Rush (2020) [Deluxe edition]", RELEASE, str(tmp_path))
    assert again["empty"] is True
    assert again["changed_file_count"] == 0
    assert again["moves"] is False


def test_an_explicit_edition_label_beats_the_disambiguation(tmp_path):
    """The metadata-manager override: name this edition whatever the user says."""
    seed(tmp_path)
    release = {**RELEASE, "edition_label": "Japanese promo"}

    plan = plan_retag("Tame Impala/The Slow Rush (2020)", release, str(tmp_path))
    execute_retag(plan, release, "apply")

    assert (tmp_path / "Tame Impala" / "The Slow Rush (2020) [Japanese promo]").is_dir()


def test_the_folder_stays_put_when_a_file_fails(tmp_path, monkeypatch):
    """Half an album in one folder and half in another is the worst possible outcome."""
    import src.retag as retag

    seed(tmp_path)
    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path))

    def explode(*args, **kwargs):
        raise OSError("disk went away")

    monkeypatch.setattr(retag, "write_tags", explode)
    results = execute_retag(plan, RELEASE, "apply")

    assert results["failed"] == 2
    assert results["moved_to"] is None
    assert (tmp_path / "Tame Impala" / "The Slow Rush (2020)").is_dir()
    assert any("left the folder in place" in p for p in results["problems"])


# ---------------------------------------------------------------- cover art

def write_image(path, data=b"\xff\xd8\xff\xe0 existing cover"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return path


def test_art_is_not_fetched_unless_asked(tmp_path):
    """Correcting tags should never pull something off the internet by itself."""
    seed(tmp_path)
    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path))
    assert plan["art"]["action"] == ""


def test_art_is_downloaded_when_the_album_has_none(tmp_path):
    seed(tmp_path)
    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path), want_art=True)
    assert plan["art"] == {"action": "download", "reason": "", "existing": None}


def test_existing_art_is_a_replacement_not_a_download(tmp_path):
    """Named differently on purpose - the interface says 'replace cover.jpg', not 'download'."""
    directory = seed(tmp_path)
    write_image(directory / "cover.jpg")

    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path), want_art=True)
    assert plan["art"] == {"action": "replace", "reason": "", "existing": "cover.jpg"}


def test_art_needs_a_release_id_and_says_so(tmp_path):
    seed(tmp_path)
    release = {**RELEASE, "release_mbid": ""}

    plan = plan_retag("Tame Impala/The Slow Rush (2020)", release, str(tmp_path), want_art=True)
    assert plan["art"]["action"] == ""
    assert any("no MusicBrainz id" in p for p in plan["problems"])


def test_planning_art_makes_no_network_call(tmp_path, monkeypatch):
    """
    Previewing must stay cheap and side-effect free - it runs on every click in the release
    list, and hitting the Archive each time would be slow and rude.
    """
    import src.api.coverart_endpoint as coverart

    def explode(*args, **kwargs):
        raise AssertionError("planning must not fetch anything")

    monkeypatch.setattr(coverart.CoverArtClient, "fetch_front", explode)
    seed(tmp_path)
    plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path), want_art=True)


def test_apply_writes_the_cover_it_is_given(tmp_path):
    seed(tmp_path)
    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path), want_art=True)
    results = execute_retag(plan, RELEASE, "apply", (b"\x89PNG downloaded art", "image/png"))

    moved = tmp_path / "Tame Impala" / "The Slow Rush (2020) [Deluxe edition]"
    assert results["art_written"] == "cover.png"
    assert (moved / "cover.png").read_bytes() == b"\x89PNG downloaded art"


def test_dry_run_names_the_cover_without_writing_it(tmp_path):
    directory = seed(tmp_path)
    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path), want_art=True)
    results = execute_retag(plan, RELEASE, "dry_run")

    assert results["art_written"] == "cover.jpg"
    assert not list(directory.glob("cover*"))


def test_a_failed_download_does_not_fail_the_retag(tmp_path):
    """The tags are the point; the art is a bonus. Losing it shouldn't lose the edit."""
    seed(tmp_path)
    plan = plan_retag("Tame Impala/The Slow Rush (2020)", RELEASE, str(tmp_path), want_art=True)
    results = execute_retag(plan, RELEASE, "apply", None)

    assert results["tagged"] == 2
    assert results["art_written"] is None
    assert results["moved_to"] is not None
    assert any("no cover art was available" in p for p in results["problems"])


def test_art_alone_is_enough_to_make_a_plan_worth_applying(tmp_path):
    """An album already correctly tagged still has something to do if it has no cover."""
    seed(tmp_path, folder="The Slow Rush (2020) [Deluxe edition]")
    path = "Tame Impala/The Slow Rush (2020) [Deluxe edition]"

    execute_retag(plan_retag(path, RELEASE, str(tmp_path)), RELEASE, "apply")

    assert plan_retag(path, RELEASE, str(tmp_path))["empty"] is True
    assert plan_retag(path, RELEASE, str(tmp_path), want_art=True)["empty"] is False


# ---------------------------------------------------------------- disc numbers

#? Jackpot Juicer, as MusicBrainz holds it: the ordinary CD, and the Target exclusive whose second
#? disc is the whole album again as instrumentals - the same titles, with "(instrumental)" on.
JJ_TITLES = ("Untitled 2", "Cream of the Crop", "Synergy")
JJ_PATH = "Dance Gavin Dance/Jackpot Juicer (2022)"

JJ_CD = {
    "artist": "Dance Gavin Dance",
    "album": "Jackpot Juicer",
    "year": "2022",
    "release_mbid": "48da6cb3-3232-4c28-b101-a5616637315a",
    "tracks": [
        {"position": n, "title": title, "disc": 1, "disc_position": n}
        for n, title in enumerate(JJ_TITLES, start=1)
    ],
}

JJ_TARGET = {
    **JJ_CD,
    "release_mbid": "c4e30f05-dc20-4ee1-bfad-0fe1e5c1e7ae",
    "disambiguation": "Target exclusive",
    "tracks": JJ_CD["tracks"] + [
        {"position": len(JJ_TITLES) + n, "title": f"{title} (instrumental)", "disc": 2, "disc_position": n}
        for n, title in enumerate(JJ_TITLES, start=1)
    ],
}


def seed_jackpot(root, discs=None):
    """The ordinary album on disk. `discs` maps a track number to the disc tag it carries."""
    directory = root / JJ_PATH
    for n, title in enumerate(JJ_TITLES, start=1):
        tags = {"album": "Jackpot Juicer", "albumartist": "Dance Gavin Dance",
                "artist": "Dance Gavin Dance", "title": title, "tracknumber": str(n),
                "date": "2022", "musicbrainz_albumid": JJ_CD["release_mbid"]}
        if (discs or {}).get(n):
            tags["discnumber"] = discs[n]
        write_flac(directory / f"{n:02d} - {title}.flac", **tags)
    return directory


def disc_changes(plan):
    return {f["filename"]: f["changes"].get("discnumber") for f in plan["files"]}


def test_a_one_disc_release_puts_a_stray_disc_number_back_to_1(tmp_path):
    """
    Jackpot Juicer's opening track was found alone on "disc 2" of a one-disc album. A
    single-disc release wrote no disc tag at all, so re-applying the right release could never
    move it back - the album just reported nothing to change.
    """
    seed_jackpot(tmp_path, discs={1: "2"})

    plan = plan_retag(JJ_PATH, JJ_CD, str(tmp_path))

    assert disc_changes(plan) == {
        "01 - Untitled 2.flac": {"from": "2", "to": "1"},
        "02 - Cream of the Crop.flac": None,
        "03 - Synergy.flac": None,
    }

    #? and the write agrees with the preview: afterwards there is nothing left to do
    execute_retag(plan, JJ_CD, "apply")
    assert plan_retag(JJ_PATH, JJ_CD, str(tmp_path))["empty"] is True


def test_a_one_disc_release_still_gives_an_untagged_album_no_disc_number(tmp_path):
    """
    The rule this refines, which still holds: an album with no disc tags is already right, and
    writing "1" into every one would give the whole library a diff it could never clear.
    """
    seed_jackpot(tmp_path)

    plan = plan_retag(JJ_PATH, JJ_CD, str(tmp_path))

    assert set(disc_changes(plan).values()) == {None}
    assert plan["empty"] is True


def test_disc_1_written_any_way_is_already_disc_1(tmp_path):
    seed_jackpot(tmp_path, discs={1: "1/1", 2: "1", 3: "01"})

    assert plan_retag(JJ_PATH, JJ_CD, str(tmp_path))["empty"] is True


def test_the_instrumental_disc_does_not_claim_the_opening_track(tmp_path):
    """
    The other way the opening track could have reached disc 2: applying the Target exclusive,
    whose second disc opens with "Untitled 2 (instrumental)". The matcher walks the tracklist
    in order, so disc 1's exact title claims the file before the instrumental ever looks at it.
    """
    seed_jackpot(tmp_path)

    plan = plan_retag(JJ_PATH, JJ_TARGET, str(tmp_path))
    first = next(f for f in plan["files"] if f["filename"] == "01 - Untitled 2.flac")

    assert (first["track_disc"], first["track_disc_position"]) == (1, 1)
    assert first["changes"]["discnumber"]["to"] == "1"


def test_a_correction_files_under_the_artists_current_name(tmp_path):
    """
    The editor seeds its artist field with the current name when a release is picked, so an
    album corrected by hand lands where the same release downloaded fresh would have - not back
    in the folder named after whatever it happened to be credited to.
    """
    write_flac(tmp_path / "Kanye West" / "Donda (2021)" / "01.flac", title="Donda Chant",
               album="Donda", albumartist="Kanye West", artist="Kanye West")

    release = {"artist": "Kanye West", "album_artist": "Ye", "album": "Donda", "year": "2021",
               "release_mbid": "donda", "tracks": []}
    plan = plan_retag("Kanye West/Donda (2021)", release, str(tmp_path))

    assert plan["moves"] is True
    assert plan["target_path"] == "Ye/Donda (2021)"


def test_the_artist_folder_a_move_empties_is_removed(tmp_path):
    """
    Asked for: "I'd like the album folder to be deleted when the songs are".

    Re-filing under the artist's current name (v0.6.18) is what makes this common - the last
    album leaves `Kanye West/` for `Ye/`, and the folder it came from stayed behind empty.
    """
    write_flac(tmp_path / "Kanye West" / "Donda (2021)" / "01.flac", title="Donda Chant",
               album="Donda", albumartist="Kanye West", artist="Kanye West")

    release = {"artist": "Kanye West", "album_artist": "Ye", "album": "Donda", "year": "2021",
               "release_mbid": "donda", "tracks": []}
    plan = plan_retag("Kanye West/Donda (2021)", release, str(tmp_path))
    results = execute_retag(plan, release, "apply")

    assert results["moved_to"].endswith("Ye/Donda (2021)")
    assert (tmp_path / "Ye" / "Donda (2021)" / "01.flac").exists()
    assert not (tmp_path / "Kanye West").exists(), "the folder it left should not linger"


def test_an_artist_folder_that_still_holds_something_is_left_alone(tmp_path):
    """rmdir refuses a non-empty folder by construction - another album, or anything you keep."""
    write_flac(tmp_path / "Kanye West" / "Donda (2021)" / "01.flac", title="Donda Chant",
               album="Donda", albumartist="Kanye West", artist="Kanye West")
    write_flac(tmp_path / "Kanye West" / "Graduation (2007)" / "01.flac", title="Good Morning",
               album="Graduation", albumartist="Kanye West", artist="Kanye West")

    release = {"artist": "Kanye West", "album_artist": "Ye", "album": "Donda", "year": "2021",
               "release_mbid": "donda", "tracks": []}
    execute_retag(plan_retag("Kanye West/Donda (2021)", release, str(tmp_path)), release, "apply")

    assert (tmp_path / "Kanye West" / "Graduation (2007)" / "01.flac").exists()
    assert (tmp_path / "Kanye West").is_dir()


def test_the_library_root_itself_is_never_tidied_away(tmp_path):
    #? an album sitting directly in the library has the ROOT as its parent
    from src.retag import _tidy_emptied_artist

    _tidy_emptied_artist(tmp_path, str(tmp_path))
    assert tmp_path.is_dir()

    outside = tmp_path.parent / "not-the-library"
    outside.mkdir(exist_ok=True)
    _tidy_emptied_artist(outside, str(tmp_path))
    assert outside.is_dir(), "a folder outside the library is not ours to remove"
    outside.rmdir()
