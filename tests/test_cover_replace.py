"""
Replacing an album's cover removes the cover file it replaces (cover removal, 27 Nov).

Both writers only ever wrote `cover.<ext>`, so the old cover stayed on disk beside the new one - and when it
was another `cover.*` sorting before the name written (`Cover.jpg` on a case-sensitive disk, as James's
server is, `cover.jpeg`, `cover.gif`, `cover.bmp`, `cover.JPG`), find_cover_file went on showing it: the
replace did nothing visible, and the editor's "Apply deletes it" wasn't true. (A `folder.jpg` was never shown
over a new cover - `cover` comes first in COVER_BASENAMES - it only stayed.) James chose: "Delete the old file".

So the plan names the file (`art.removes`, plan_cover_art's `removes`) - only one named as a cover, a regular
file, in a folder with music in it - with the file's identity, and the write removes that one file once the
new cover is saved, behind every guard again; it says, never removes, any other cover that still outranks the
new one, which the plan predicts (`also_covers`, `still_shown_first`). Both writers are run through each case:
Apply with the cover on (execute_retag) and the cover alone (save_cover_art, which the editor's Replace cover
only and Compare covers' replace both call, through /library/art/fetch).
"""

import logging
import os
import sys
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from mutagen.flac import FLAC, Picture

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.config import Config  # noqa: E402
from src.library import find_cover_file  # noqa: E402
from src.retag import (LINK_NOT_REMOVED, NOT_AN_ALBUM, execute_retag, plan_cover_art, plan_retag,  # noqa: E402
                       remove_replaced_cover, save_cover_art)
from tests.test_retag import RELEASE, seed  # noqa: E402

#? already filed under the release's own name, so applying it retags in place and the folder stays put
FOLDER = "The Slow Rush (2020) [Deluxe edition]"
ALBUM = f"Tame Impala/{FOLDER}"
NEW = (b"\xff\xd8\xff\xe0 the pressing's cover", "image/jpeg")
OLD = b"\xff\xd8\xff\xe0 your cover"
WRITERS = ("apply", "alone")
SHOWN_FIRST = "saved cover.jpg, but {} is still shown first - another cover in the album's folder, left as it was"


def put(path: Path, data: bytes = OLD) -> Path:
    #? open(), not write_bytes: failing_write makes a cover's write_bytes fail
    with open(path, "wb") as file:
        file.write(data)
    return path


def album(root: Path, *covers: str) -> Path:
    directory = seed(root, folder=FOLDER, musicbrainz_albumid="mbid-deluxe")
    for name in covers:
        put(directory / name)
    return directory


def case_sensitive(root: Path) -> bool:
    probe = root / "case-probe"
    probe.write_bytes(b"")
    try:
        return not (root / "CASE-PROBE").exists()
    finally:
        probe.unlink()


def identity(path: Path) -> list[int]:
    info = path.lstat()
    return [info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns]


def planned(directory: Path, name: str) -> dict:
    """A plan's cover naming `name` as the file to remove, with the identity it has now."""
    try:
        seen = identity(directory / name)
    except OSError:
        seen = None
    return {"removes": name, "removes_identity": seen, "existing": name}


def plan_of(writer: str, root: Path, size: str | None = "500", path: str = ALBUM) -> dict:
    """Each writer's plan - the one the write is then handed, as the routes do."""
    if writer == "apply":
        return plan_retag(path, RELEASE, str(root), want_art=True, cover_size=size)
    return plan_cover_art(path, str(root), replace=True, release_mbid="mbid-deluxe", cover_size=size)


def art_of(writer: str, plan: dict) -> dict:
    """The plan's cover fields: a retag's plan.art, the cover alone's plan itself."""
    return plan["art"] if writer == "apply" else plan


def write(writer: str, root: Path, plan: dict, art=NEW, path: str = ALBUM) -> dict:
    """Run the writer on `plan`; answer {written, removed, problems} whichever it was."""
    if writer == "apply":
        results = execute_retag(plan, RELEASE, "apply", art)
        cover = [p for p in results["problems"] if "cover" in p or "shown" in p]
        return {"written": results["art_written"], "removed": results["art_removed"], "problems": cover}
    results = save_cover_art(path, str(root), art, plan)
    return {"written": results["written"], "removed": results["removed"],
            "problems": results["problems"] + ([results["problem"]] if results["problem"] else [])}


def replace(writer: str, root: Path, art=NEW, size: str | None = "500") -> tuple[dict, dict]:
    plan = plan_of(writer, root, size)
    return plan, write(writer, root, plan, art)


def shown(directory: Path) -> Path | None:
    return find_cover_file(sorted(p for p in directory.iterdir() if p.is_file()))


def images(directory: Path) -> list[str]:
    return sorted(p.name for p in directory.iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".gif", ".bmp"})


# ---------------------------------------------------------------- the replace shows

@pytest.mark.parametrize("writer", WRITERS)
@pytest.mark.parametrize("old", ["folder.jpg", "Cover.jpg", "cover.jpeg", "cover.png", "FRONT.png", "thumb.jpg"])
def test_replacing_a_cover_removes_it_and_the_new_one_is_shown(tmp_path, writer, old):
    directory = album(tmp_path, old)
    seen = identity(directory / old)

    plan, done = replace(writer, tmp_path)

    art = art_of(writer, plan)
    assert (art["removes"], art["removes_refused"]) == (old, None), "the plan names the file the replace deletes"
    assert art["removes_identity"] == seen, "and the file it is"
    assert (art["also_covers"], art["still_shown_first"]) == ([], [])
    assert done["written"] == "cover.jpg" and done["problems"] == []
    if old == "Cover.jpg" and not case_sensitive(tmp_path):
        #? on a case-insensitive disk (a Mac's) Cover.jpg IS cover.jpg: the write overwrote it, and the
        #? one file there now holds the new cover - removing it would remove the cover just saved
        assert done["removed"] is None
        assert images(directory) == ["Cover.jpg"]
    else:
        assert done["removed"] == old
        assert images(directory) == ["cover.jpg"]
    assert shown(directory).read_bytes() == NEW[0]


@pytest.mark.parametrize("writer", WRITERS)
def test_a_cover_of_the_same_name_is_overwritten_and_nothing_else_is_removed(tmp_path, writer):
    directory = album(tmp_path, "cover.jpg", "folder.jpg", "back.jpg")

    plan, done = replace(writer, tmp_path)

    assert art_of(writer, plan)["removes"] == "cover.jpg"
    assert done["written"] == "cover.jpg" and done["removed"] is None and done["problems"] == []
    assert (directory / "cover.jpg").read_bytes() == NEW[0], "overwritten, not deleted after being written"
    assert images(directory) == ["back.jpg", "cover.jpg", "folder.jpg"]
    assert (directory / "folder.jpg").read_bytes() == OLD


@pytest.mark.parametrize("writer", WRITERS)
def test_a_full_size_png_removes_a_cover_jpg_rather_than_overwriting_it(tmp_path, writer):
    """At `full` the original can be a PNG: cover.png is written, so the old cover.jpg - which would sort first
    and go on being shown - is the file removed."""
    directory = album(tmp_path, "cover.jpg")

    plan, done = replace(writer, tmp_path, (b"\x89PNG the original", "image/png"), size="full")

    assert art_of(writer, plan)["still_shown_first"] is None, "not known at full"
    assert (done["written"], done["removed"], done["problems"]) == ("cover.png", "cover.jpg", [])
    assert images(directory) == ["cover.png"]


@pytest.mark.parametrize("writer", WRITERS)
def test_a_cover_only_inside_the_files_removes_nothing(tmp_path, writer):
    directory = album(tmp_path)
    track = directory / "01 - One More Year.flac"
    audio = FLAC(str(track))
    picture = Picture()
    picture.type, picture.mime, picture.data = 3, "image/jpeg", OLD
    audio.add_picture(picture)
    audio.save()
    before = sorted(p.name for p in directory.iterdir())

    plan, done = replace(writer, tmp_path)

    assert art_of(writer, plan)["removes"] is None
    assert done["written"] == "cover.jpg" and done["removed"] is None and done["problems"] == []
    assert sorted(p.name for p in directory.iterdir()) == sorted(before + ["cover.jpg"])
    assert [p.data for p in FLAC(str(track)).pictures] == [OLD], "the embedded picture is left as it was"


# ---------------------------------------------------------------- what is never removed

@pytest.mark.parametrize("writer", WRITERS)
@pytest.mark.parametrize("lone", ["cdart.png", "scan001.jpg", "fanart.jpg", "spine.jpg", "IMG_0042.jpg"])
def test_a_folders_only_image_under_another_name_is_kept(tmp_path, writer, lone):
    """find_cover_file takes a folder's only image for its cover. Once a cover.* is written the `cover` stem
    comes first anyway, so deleting it would gain nothing: it's kept, and the plan says why."""
    directory = album(tmp_path, lone)

    plan, done = replace(writer, tmp_path)

    art = art_of(writer, plan)
    assert (art["existing"], art["removes"], art["removes_refused"]) == (lone, None, "not_a_cover_name")
    assert done["written"] == "cover.jpg" and done["removed"] is None and done["problems"] == []
    assert (directory / lone).read_bytes() == OLD
    assert shown(directory).name == "cover.jpg" and shown(directory).read_bytes() == NEW[0]


@pytest.mark.parametrize("where", ["an artist's folder", "a Scans folder"])
def test_the_cover_alone_removes_nothing_from_a_folder_with_no_music(tmp_path, where):
    """/library/art/fetch takes any folder inside the library. A folder with no audio directly in it is no
    album, as delete_album requires: its folder.jpg (an artist picture) or front.jpg is never deleted."""
    seed(tmp_path, folder=FOLDER, musicbrainz_albumid="mbid-deluxe")
    path = "Tame Impala" if where == "an artist's folder" else f"{ALBUM}/Scans"
    folder = tmp_path / path
    folder.mkdir(exist_ok=True)
    old = put(folder / ("folder.jpg" if where == "an artist's folder" else "front.jpg"))

    plan = plan_of("alone", tmp_path, path=path)
    done = write("alone", tmp_path, plan, path=path)

    assert (plan["existing"], plan["removes"], plan["removes_refused"]) == (old.name, None, "not_an_album")
    assert done["removed"] is None and old.read_bytes() == OLD
    assert done["problems"] == [f"saved cover.jpg, but the old {old.name} was left where it is - {NOT_AN_ALBUM}"]


@pytest.mark.parametrize("writer", WRITERS)
def test_a_folder_that_lost_its_music_after_the_plan_keeps_its_cover(tmp_path, writer):
    """The audio guard is checked again at the write."""
    directory = album(tmp_path, "folder.jpg")
    plan = plan_of(writer, tmp_path)
    for track in directory.glob("*.flac"):
        track.unlink()

    done = write(writer, tmp_path, plan)

    assert done["removed"] is None and (directory / "folder.jpg").read_bytes() == OLD
    assert f"saved cover.jpg, but the old folder.jpg was left where it is - {NOT_AN_ALBUM}" in done["problems"]


@pytest.mark.parametrize("writer", WRITERS)
@pytest.mark.parametrize("where", ["in the album", "outside the library"])
def test_an_old_cover_that_is_a_link_is_refused_and_nothing_is_removed(tmp_path, writer, where):
    library = tmp_path / "library"
    directory = album(library)
    if where == "in the album":
        (directory / "scans").mkdir()
        target = directory / "scans" / "front.jpg"
    else:
        target = tmp_path / "elsewhere.jpg"
    put(target)
    (directory / "folder.jpg").symlink_to(target)

    plan, done = replace(writer, library)

    art = art_of(writer, plan)
    assert (art["existing"], art["removes"], art["removes_refused"]) == ("folder.jpg", None, "link"), \
        "the preview never names a link it won't remove"
    assert done["written"] == "cover.jpg" and done["removed"] is None
    assert done["problems"] == [f"saved cover.jpg, but the old folder.jpg {LINK_NOT_REMOVED}"]
    assert (directory / "folder.jpg").is_symlink(), "the link is left"
    assert target.read_bytes() == OLD, "and never followed"


@pytest.mark.parametrize("writer", WRITERS)
def test_a_cover_made_a_link_after_the_plan_is_refused_at_the_write(tmp_path, writer):
    """Every guard is checked again at the write: the plan named a plain file."""
    directory = album(tmp_path, "folder.jpg")
    plan = plan_of(writer, tmp_path)
    put(directory / "front.jpg")
    (directory / "folder.jpg").unlink()
    (directory / "folder.jpg").symlink_to(directory / "front.jpg")

    done = write(writer, tmp_path, plan)

    assert done["removed"] is None and (directory / "folder.jpg").is_symlink()
    assert (directory / "front.jpg").read_bytes() == OLD
    assert f"saved cover.jpg, but the old folder.jpg {LINK_NOT_REMOVED}" in done["problems"]


@pytest.mark.parametrize("writer", WRITERS)
@pytest.mark.parametrize("change", ["new contents", "touched"])
def test_a_cover_that_changed_after_the_plan_is_not_removed(tmp_path, writer, change):
    """Removed only if it is the very file the plan saw - device, inode, size and mtime unchanged."""
    directory = album(tmp_path, "folder.jpg")
    plan = plan_of(writer, tmp_path)
    old = directory / "folder.jpg"
    if change == "new contents":
        put(old, b"\xff\xd8\xff\xe0 a cover someone saved since, a different size")
    else:
        info = old.stat()
        os.utime(old, ns=(info.st_atime_ns, info.st_mtime_ns + 1_000_000_000))
    kept = old.read_bytes()

    done = write(writer, tmp_path, plan)

    assert done["written"] == "cover.jpg" and done["removed"] is None
    assert old.read_bytes() == kept
    assert ("saved cover.jpg, but the old folder.jpg was left where it is - it changed while the new cover was "
            "being fetched") in done["problems"]


@pytest.fixture
def failing_write(monkeypatch):
    """A cover's write that fails, as a full disk would - the tags and everything else still write."""
    real = Path.write_bytes

    def write_bytes(self, data):
        if self.name.startswith("cover."):
            raise OSError(28, "No space left on device")
        return real(self, data)

    monkeypatch.setattr(Path, "write_bytes", write_bytes)


@pytest.mark.parametrize("writer", WRITERS)
@pytest.mark.parametrize("covers", [("folder.jpg",), ("cover.gif", "cover.jpg")])
def test_a_failed_write_removes_nothing(tmp_path, writer, covers, failing_write):
    """("cover.gif", "cover.jpg"): the file being written is already there, so a removal after a failed write
    would find a cover.jpg to stand for the new one - and still has removed nothing."""
    directory = album(tmp_path, *covers)

    plan, done = replace(writer, tmp_path)

    assert art_of(writer, plan)["removes"] == covers[0]
    assert done["written"] is None and done["removed"] is None
    assert any("could not" in p and "No space left" in p for p in done["problems"])
    assert images(directory) == sorted(covers)
    assert all((directory / name).read_bytes() == OLD for name in covers)


@pytest.mark.parametrize("writer", WRITERS)
def test_an_old_cover_gone_before_the_write_is_said_and_no_error(tmp_path, writer):
    directory = album(tmp_path, "folder.jpg")
    plan = plan_of(writer, tmp_path)
    (directory / "folder.jpg").unlink()

    done = write(writer, tmp_path, plan)

    assert done["written"] == "cover.jpg" and done["removed"] is None
    assert done["problems"] == ["saved cover.jpg - the old folder.jpg was already gone, so there was nothing to remove"]
    assert images(directory) == ["cover.jpg"]


@pytest.mark.parametrize("writer", WRITERS)
def test_with_two_covers_only_the_planned_one_goes_and_the_other_is_said(tmp_path, writer):
    """Only the one file the plan named is ever removed: a second cover still outranking the new one is
    reported, in words, and left. cover.gif sorts first, so it is the cover shown and the one replaced;
    cover.jpeg then still sorts before the new cover.jpg - as the plan said it would."""
    directory = album(tmp_path, "cover.gif", "cover.jpeg")

    plan, done = replace(writer, tmp_path)

    art = art_of(writer, plan)
    assert (art["removes"], art["also_covers"], art["still_shown_first"]) == ("cover.gif", ["cover.jpeg"], ["cover.jpeg"])
    assert done["removed"] == "cover.gif"
    assert done["problems"] == [SHOWN_FIRST.format("cover.jpeg")]
    assert images(directory) == ["cover.jpeg", "cover.jpg"]
    assert (directory / "cover.jpeg").read_bytes() == OLD


@pytest.mark.parametrize("writer", WRITERS)
def test_cover_jpg_beside_cover_jpeg_on_a_case_sensitive_disk(tmp_path, writer):
    """The case the review found, on James's server: Cover.jpg (shown) and cover.jpeg. Cover.jpg goes,
    cover.jpeg is said - and left. On a case-insensitive disk Cover.jpg is overwritten instead."""
    directory = album(tmp_path, "Cover.jpg", "cover.jpeg")

    plan, done = replace(writer, tmp_path)

    assert art_of(writer, plan)["removes"] == "Cover.jpg"
    if case_sensitive(tmp_path):
        assert art_of(writer, plan)["still_shown_first"] == ["cover.jpeg"]
        assert done["removed"] == "Cover.jpg"
        assert done["problems"] == [SHOWN_FIRST.format("cover.jpeg")]
        assert images(directory) == ["cover.jpeg", "cover.jpg"]
    else:
        assert art_of(writer, plan)["still_shown_first"] == [], "listed as Cover.jpg, which cover.jpeg sorts after"
        assert done["removed"] is None and done["problems"] == []
        assert images(directory) == ["Cover.jpg", "cover.jpeg"]
        assert (directory / "Cover.jpg").read_bytes() == NEW[0]
    assert (directory / "cover.jpeg").read_bytes() == OLD


# ---------------------------------------------------------------- what the plan says will stay

@pytest.mark.parametrize("covers", [
    ("cover.gif", "cover.jpeg"), ("cover.jpg", "cover.png"), ("COVER.GIF", "COVER.jpg"), ("Cover.jpg", "cover.jpeg"),
    ("COVER.jpg", "Cover.gif"), ("folder.jpg",), ("cover.JPG",), ("cover.bmp", "cover.webp"), ("scan001.jpg",),
])
def test_still_shown_first_is_what_the_write_then_finds(tmp_path, covers):
    """At 250, 500 or 1200 the Archive sends a JPEG, so the new cover is cover.jpg, and the plan can say which
    covers will still come before it. Each case, on whichever disk this runs: the prediction, then the write."""
    album(tmp_path, *covers)

    plan = plan_of("alone", tmp_path)
    done = write("alone", tmp_path, plan)

    found = [p.split(", but ")[1].split(" is still")[0] for p in done["problems"] if "still shown first" in p]
    assert plan["still_shown_first"][:1] == found
    assert done["written"] == "cover.jpg"


def test_also_covers_leaves_out_a_file_that_is_cover_jpg(tmp_path):
    """COVER.GIF is the cover shown (it sorts first), COVER.jpg another. On a case-insensitive disk COVER.jpg IS
    cover.jpg, which the write overwrites: not one that stays. On a case-sensitive one it stays, and sorts first."""
    album(tmp_path, "COVER.GIF", "COVER.jpg")

    plan = plan_cover_art(ALBUM, str(tmp_path), replace=True, cover_size="1200")

    assert plan["removes"] == "COVER.GIF"
    if case_sensitive(tmp_path):
        assert (plan["also_covers"], plan["still_shown_first"]) == (["COVER.jpg"], ["COVER.jpg"])
    else:
        assert (plan["also_covers"], plan["still_shown_first"]) == ([], [])


def test_a_linked_cover_is_among_those_that_stay(tmp_path):
    directory = album(tmp_path, "front-scan.gif")
    (directory / "cover.gif").symlink_to(directory / "front-scan.gif")

    plan = plan_cover_art(ALBUM, str(tmp_path), replace=True, cover_size="500")
    done = write("alone", tmp_path, plan)

    assert (plan["existing"], plan["removes"], plan["removes_refused"]) == ("cover.gif", None, "link")
    assert (plan["also_covers"], plan["still_shown_first"]) == (["cover.gif"], ["cover.gif"])
    assert done["problems"] == [f"saved cover.jpg, but the old cover.gif {LINK_NOT_REMOVED}", SHOWN_FIRST.format("cover.gif")]


@pytest.mark.parametrize("size, expected", [("250", ["cover.jpeg"]), ("500", ["cover.jpeg"]), ("1200", ["cover.jpeg"]),
                                            ("full", None), (None, None), ("", ["cover.jpeg"]), ("huge", ["cover.jpeg"])])
def test_still_shown_first_is_known_only_at_the_archives_thumbnail_sizes(tmp_path, size, expected):
    """None at `full`, whose original can be a PNG, GIF or WebP, and when the size wasn't given; an empty or unknown
    COVER_ART_SIZE is asked as the default 500, as fetch_front_why does."""
    album(tmp_path, "cover.gif", "cover.jpeg")

    for plan in (plan_retag(ALBUM, RELEASE, str(tmp_path), want_art=True, cover_size=size)["art"],
                 plan_cover_art(ALBUM, str(tmp_path), replace=True, cover_size=size)):
        assert plan["also_covers"] == ["cover.jpeg"]
        assert plan["still_shown_first"] == expected


# ---------------------------------------------------------------- what a replace would do, before one is asked for

#? the fields that say what a replace of the folder's cover would do - the same on a retag's plan.art and on the
#? cover alone's plan
REMOVAL = ("existing", "removes", "removes_refused", "removes_identity", "also_covers", "still_shown_first")


def removal(plan: dict) -> dict:
    return {key: plan[key] for key in REMOVAL}


def linked(directory: Path, name: str) -> None:
    put(directory.parent / f"elsewhere-{name}")
    (directory / name).symlink_to(directory.parent / f"elsewhere-{name}")


#? a cover named as one, a lone image under another name, a link, two covers, a same-named cover.jpg, and none
FOLDERS = [("folder.jpg",), ("cdart.png",), ("link:folder.jpg",), ("cover.gif", "cover.jpeg"),
           ("cover.jpg", "folder.jpg"), ("Cover.jpg", "cover.jpeg"), ()]


def album_of(root: Path, covers: tuple) -> Path:
    directory = album(root, *(c for c in covers if not c.startswith("link:")))
    for c in covers:
        if c.startswith("link:"):
            linked(directory, c[len("link:"):])
    return directory


@pytest.mark.parametrize("size", ["500", "full", None])
@pytest.mark.parametrize("covers", FOLDERS)
def test_the_retag_plan_says_what_the_cover_alone_would_do_with_the_cover_off_or_on(tmp_path, covers, size):
    """Compare covers' "Replace your cover with this one" is the cover alone (/library/art/fetch, plan_cover_art),
    which has no preview of its own: the editor reads the retag preview's plan.art for it, and for wording the
    switch before it's ticked. Both plan over the same folder's entries, so they agree - the cover off and on alike.
    Only `action` differs: the cover off fetches, writes and removes nothing."""
    album_of(tmp_path, covers)

    off = plan_retag(ALBUM, RELEASE, str(tmp_path), want_art=False, cover_size=size)["art"]
    on = plan_retag(ALBUM, RELEASE, str(tmp_path), want_art=True, cover_size=size)["art"]
    alone = plan_cover_art(ALBUM, str(tmp_path), replace=True, release_mbid="mbid-deluxe", cover_size=size)

    assert removal(off) == removal(on) == removal(alone)
    assert (off["action"], off["reason"]) == ("", "")
    assert on["action"] == alone["action"] == ("replace" if covers else "download")


@pytest.mark.parametrize("covers, removes, refused", [
    (("folder.jpg",), "folder.jpg", None),
    (("cdart.png",), None, "not_a_cover_name"),
    (("link:folder.jpg",), None, "link"),
])
def test_with_the_cover_off_the_plan_says_what_a_replace_would_remove(tmp_path, covers, removes, refused):
    """The switch's words before it's ticked: a lone cdart.png reads as kept, not "deletes it"."""
    album_of(tmp_path, covers)

    art = plan_retag(ALBUM, RELEASE, str(tmp_path), cover_size="500")["art"]

    assert (art["action"], art["removes"], art["removes_refused"]) == ("", removes, refused)


def test_with_the_cover_off_apply_removes_nothing_though_the_plan_names_a_file(tmp_path):
    """`removes` with the cover off says what a replace WOULD do; Apply reads `action`, so nothing is written or
    removed - even handed the bytes of a cover."""
    directory = album(tmp_path, "folder.jpg")
    plan = plan_retag(ALBUM, RELEASE, str(tmp_path), want_art=False, cover_size="500")
    assert plan["art"]["removes"] == "folder.jpg"

    results = execute_retag(plan, RELEASE, "apply", NEW)

    assert (results["art_written"], results["art_removed"]) == (None, None)
    assert images(directory) == ["folder.jpg"]
    assert (directory / "folder.jpg").read_bytes() == OLD


def test_with_no_release_id_the_plan_still_says_what_a_replace_would_do(tmp_path):
    album(tmp_path, "folder.jpg")

    art = plan_retag(ALBUM, {**RELEASE, "release_mbid": ""}, str(tmp_path), want_art=True, cover_size="500")["art"]

    assert (art["action"], art["removes"]) == ("", "folder.jpg")
    assert "no MusicBrainz id" in art["reason"]


def test_a_merge_that_drops_the_cover_still_says_what_the_cover_alone_would_do(tmp_path):
    """Apply joining a disc to a folder that has a cover fetches none (action ""), but the cover alone on this
    folder still replaces its cover - so the fields say what that would do, as they do with the cover off."""
    from tests.test_split_discs import RELEASE as SET, disc_folder

    there = disc_folder(tmp_path, "OK Computer (1997)", 1, ["Airbag", "Paranoid Android"])
    put(there / "cover.jpg")
    source = disc_folder(tmp_path, "OK Computer (Disc 2)", 2, ["Lucky", "The Tourist"])
    put(source / "folder.jpg")
    path = "Radiohead/OK Computer (Disc 2)"

    plan = plan_retag(path, SET, str(tmp_path), want_art=True, cover_size="500")
    alone = plan_cover_art(path, str(tmp_path), replace=True, release_mbid="okc-2cd", cover_size="500")

    assert plan["merge"] and plan["art"]["action"] == ""
    assert removal(plan["art"]) == removal(alone)
    assert plan["art"]["removes"] == "folder.jpg"
    results = execute_retag(plan, SET, "apply", NEW)
    assert (results["art_written"], results["art_removed"]) == (None, None)
    assert (there / "cover.jpg").read_bytes() == OLD


# ---------------------------------------------------------------- the guards, one at a time

@pytest.mark.parametrize("name, why", [
    ("01 - One More Year.flac", "it isn't an image file"),
    ("art.jpg", "it isn't an image file"),                     # a folder named like an image
    ("scans/front.jpg", "it isn't a file in the album's own folder"),
    ("../elsewhere.jpg", "it isn't a file in the album's own folder"),
    ("..", "it isn't a file in the album's own folder"),
    (".", "it isn't a file in the album's own folder"),
])
def test_the_removal_takes_only_an_image_file_directly_in_the_album(tmp_path, name, why):
    directory = album(tmp_path)
    (directory / "art.jpg").mkdir()
    (directory / "scans").mkdir()
    put(directory / "scans" / "front.jpg")
    put(tmp_path / "Tame Impala" / "elsewhere.jpg")
    put(directory / "cover.jpg", NEW[0])
    before = sorted(str(p.relative_to(tmp_path)) for p in tmp_path.rglob("*"))

    removed, problems = remove_replaced_cover(directory, directory / "cover.jpg", planned(directory, name), str(tmp_path))

    assert removed is None
    assert problems == [f"saved cover.jpg, but the old {name} was left where it is - {why}"]
    assert sorted(str(p.relative_to(tmp_path)) for p in tmp_path.rglob("*")) == before


def test_the_removal_takes_nothing_from_an_album_outside_the_library(tmp_path):
    directory = album(tmp_path / "elsewhere", "folder.jpg")
    put(directory / "cover.jpg", NEW[0])

    removed, problems = remove_replaced_cover(directory, directory / "cover.jpg", planned(directory, "folder.jpg"),
                                              str(tmp_path / "library"))

    assert removed is None and (directory / "folder.jpg").exists()
    assert problems == ["saved cover.jpg, but the old folder.jpg was left where it is - the album isn't inside the library"]


def test_the_removal_takes_nothing_from_the_library_itself(tmp_path):
    put(tmp_path / "folder.jpg")
    put(tmp_path / "cover.jpg", NEW[0])

    removed, problems = remove_replaced_cover(tmp_path, tmp_path / "cover.jpg", planned(tmp_path, "folder.jpg"),
                                              str(tmp_path))

    assert removed is None and (tmp_path / "folder.jpg").exists()
    assert "the album isn't inside the library" in problems[0]


def test_the_removal_takes_nothing_from_a_folder_with_no_music(tmp_path):
    folder = tmp_path / "Tame Impala"
    folder.mkdir()
    put(folder / "folder.jpg")
    put(folder / "cover.jpg", NEW[0])

    removed, problems = remove_replaced_cover(folder, folder / "cover.jpg", planned(folder, "folder.jpg"), str(tmp_path))

    assert removed is None and (folder / "folder.jpg").exists()
    assert problems == [f"saved cover.jpg, but the old folder.jpg was left where it is - {NOT_AN_ALBUM}"]


def test_the_removal_needs_the_identity_the_plan_saw(tmp_path):
    directory = album(tmp_path, "folder.jpg")
    put(directory / "cover.jpg", NEW[0])

    removed, problems = remove_replaced_cover(directory, directory / "cover.jpg", {"removes": "folder.jpg"}, str(tmp_path))

    assert removed is None and (directory / "folder.jpg").exists()
    assert "it changed while the new cover was being fetched" in problems[0]


def test_the_removal_waits_for_the_new_cover_to_be_on_disk(tmp_path):
    directory = album(tmp_path, "folder.jpg")

    removed, problems = remove_replaced_cover(directory, directory / "cover.jpg", planned(directory, "folder.jpg"),
                                              str(tmp_path))

    assert removed is None and (directory / "folder.jpg").exists()
    assert problems == ["saved cover.jpg, but the old folder.jpg was left where it is - "
                        "the new cover couldn't be found after saving it",
                        #? true, too: with no cover.jpg, folder.jpg is the cover shown
                        SHOWN_FIRST.format("folder.jpg")]


def test_the_file_just_written_is_never_removed_under_another_name(tmp_path):
    """A hard link: folder.jpg IS cover.jpg, whatever the disk - the case a case-insensitive disk makes of Cover.jpg,
    tested where CI's case-sensitive disk never would."""
    directory = album(tmp_path)
    put(directory / "cover.jpg", NEW[0])
    os.link(directory / "cover.jpg", directory / "folder.jpg")

    removed, problems = remove_replaced_cover(directory, directory / "cover.jpg", planned(directory, "folder.jpg"),
                                              str(tmp_path))

    assert (removed, problems) == (None, [])
    assert (directory / "folder.jpg").read_bytes() == NEW[0] and (directory / "cover.jpg").read_bytes() == NEW[0]


def test_a_removal_that_fails_is_said_and_the_tags_stay_written(tmp_path, monkeypatch):
    directory = album(tmp_path, "folder.jpg")
    plan = plan_retag(ALBUM, {**RELEASE, "album": "The Slow Rush (Deluxe)"}, str(tmp_path), want_art=True)
    real = Path.unlink

    def unlink(self, missing_ok=False):
        if self.name == "folder.jpg":
            raise PermissionError(13, "Permission denied")
        return real(self, missing_ok)

    monkeypatch.setattr(Path, "unlink", unlink)
    results = execute_retag(plan, {**RELEASE, "album": "The Slow Rush (Deluxe)"}, "apply", NEW, move=False)

    assert results["tagged"] == 2 and results["failed"] == 0, "the tags are written, and not undone"
    assert FLAC(str(directory / "01 - One More Year.flac"))["album"] == ["The Slow Rush (Deluxe)"]
    assert results["art_written"] == "cover.jpg" and results["art_removed"] is None
    assert "saved cover.jpg, but the old folder.jpg couldn't be removed: Permission denied" in results["problems"]
    assert (directory / "folder.jpg").read_bytes() == OLD


# ---------------------------------------------------------------- a dry run, and the event log

def test_a_dry_run_names_what_it_would_remove_and_removes_nothing(tmp_path):
    directory = album(tmp_path, "folder.jpg")
    plan = plan_retag(ALBUM, RELEASE, str(tmp_path), want_art=True)

    results = execute_retag(plan, RELEASE, "dry_run")

    assert (results["art_written"], results["art_removed"]) == ("cover.jpg", "folder.jpg")
    assert images(directory) == ["folder.jpg"]


def test_a_dry_run_says_a_second_cover_would_still_be_shown_first(tmp_path):
    directory = album(tmp_path, "cover.gif", "cover.jpeg")
    plan = plan_retag(ALBUM, RELEASE, str(tmp_path), want_art=True)

    results = execute_retag(plan, RELEASE, "dry_run")

    assert results["art_removed"] == "cover.gif"
    assert ("cover.jpg would be saved, but cover.jpeg is still shown first - another cover in the album's "
            "folder, left as it was") in results["problems"]
    assert images(directory) == ["cover.gif", "cover.jpeg"]


@pytest.mark.parametrize("writer", WRITERS)
def test_the_event_log_names_the_cover_removed(tmp_path, writer, caplog):
    album(tmp_path, "folder.jpg")

    with caplog.at_level(logging.INFO):
        replace(writer, tmp_path)

    assert f"removed the old cover folder.jpg from {FOLDER} - cover.jpg replaces it" in caplog.text


# ---------------------------------------------------------------- the routes: the plan is the server's own

class Archive:
    """The Cover Art Archive, answering every release with NEW - so nothing here leaves the machine."""

    async def fetch_front(self, release_mbid):
        return NEW

    async def fetch_front_why(self, release_mbid):
        return NEW, "ok"


@pytest.fixture
def routes(monkeypatch, tmp_path):
    from src.routes import library

    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", "0")
    monkeypatch.setattr(Config, "COVER_ART_SIZE", "500")
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    monkeypatch.setattr(library, "_HELD_RENAMES", {})
    monkeypatch.setattr(library, "_APPLY_LOCKS", {})
    monkeypatch.setattr(library, "coverart_client", Archive())
    app = FastAPI()
    app.include_router(library.router, prefix="/deadwax/library")
    return TestClient(app)


#? what a caller might send hoping to choose the file removed - pydantic drops every one of these, and the
#? server plans again from the folder
FORGED = {"removes": "back.jpg", "removes_identity": [0, 0, 0, 0], "art": {"action": "replace", "removes": "back.jpg"},
          "plan": {"art": {"action": "replace", "removes": "back.jpg"}}}


def test_the_preview_names_the_file_a_replace_removes_and_removes_nothing(routes, tmp_path):
    directory = album(tmp_path, "cover.gif", "cover.jpeg")

    plan = routes.post("/deadwax/library/retag/preview",
                       json={"album_path": ALBUM, "release": RELEASE, "fetch_art": True}).json()

    assert plan["art"]["action"] == "replace"
    assert (plan["art"]["existing"], plan["art"]["removes"], plan["art"]["removes_refused"]) == \
        ("cover.gif", "cover.gif", None)
    assert plan["art"]["removes_identity"] == identity(directory / "cover.gif")
    assert (plan["art"]["also_covers"], plan["art"]["still_shown_first"]) == (["cover.jpeg"], ["cover.jpeg"])
    assert images(directory) == ["cover.gif", "cover.jpeg"]


@pytest.mark.parametrize("covers", [("folder.jpg",), ("cdart.png",), ("cover.gif", "cover.jpeg"), ("cover.jpg",)])
def test_the_preview_with_the_cover_off_says_what_compare_covers_replace_then_does(routes, tmp_path, covers):
    """End to end: the retag preview, the cover off, is the cover alone's preview - what it says /library/art/fetch
    will remove is what it removes, and what it says stays is what then stays and is said."""
    directory = album(tmp_path, *covers)

    art = routes.post("/deadwax/library/retag/preview",
                      json={"album_path": ALBUM, "release": RELEASE, "fetch_art": False}).json()["art"]
    assert art["action"] == ""
    assert images(directory) == sorted(covers), "the preview removed nothing"

    done = routes.post("/deadwax/library/art/fetch",
                       json={"album_path": ALBUM, "replace": True, "release_mbid": "mbid-deluxe"}).json()

    overwritten = art["removes"] == "cover.jpg"
    assert done["removed"] == (None if overwritten else art["removes"])
    assert [n for n in images(directory) if n != "cover.jpg"] == art["also_covers"] + (
        [art["existing"]] if art["removes_refused"] == "not_a_cover_name" else [])
    assert [p.split(", but ")[1].split(" is still")[0] for p in done["problems"]] == art["still_shown_first"]


def test_apply_removes_what_its_own_plan_names_never_what_was_sent(routes, tmp_path):
    directory = album(tmp_path, "folder.jpg", "back.jpg")

    answer = routes.post("/deadwax/library/retag/apply", json={
        "album_path": ALBUM, "release": {**RELEASE, **FORGED}, "fetch_art": True, **FORGED}).json()

    assert answer["plan"]["art"]["removes"] == "folder.jpg"
    assert (answer["results"]["art_written"], answer["results"]["art_removed"]) == ("cover.jpg", "folder.jpg")
    assert images(directory) == ["back.jpg", "cover.jpg"]


def test_the_cover_alone_removes_what_its_own_plan_names_never_what_was_sent(routes, tmp_path):
    directory = album(tmp_path, "folder.jpg", "back.jpg")

    answer = routes.post("/deadwax/library/art/fetch",
                         json={"album_path": ALBUM, "replace": True, "release_mbid": "mbid-deluxe", **FORGED}).json()

    assert answer == {"written": "cover.jpg", "replaced": "folder.jpg", "removed": "folder.jpg", "problems": []}
    assert images(directory) == ["back.jpg", "cover.jpg"]


def test_the_cover_alone_still_never_replaces_unasked(routes, tmp_path):
    directory = album(tmp_path, "folder.jpg")

    refused = routes.post("/deadwax/library/art/fetch", json={"album_path": ALBUM, **FORGED})

    assert refused.status_code == 400 and "already has folder.jpg" in refused.json()["detail"]
    assert images(directory) == ["folder.jpg"]


def test_the_cover_alone_answers_a_cover_still_shown_first(routes, tmp_path, caplog):
    """...and says it in the event log, since the editor draws the cover alone's answer as one line."""
    album(tmp_path, "cover.gif", "cover.jpeg")

    with caplog.at_level(logging.INFO):
        answer = routes.post("/deadwax/library/art/fetch", json={"album_path": ALBUM, "replace": True}).json()

    assert (answer["removed"], answer["replaced"]) == ("cover.gif", "cover.gif")
    assert answer["problems"] == [SHOWN_FIRST.format("cover.jpeg")]
    assert f"{FOLDER}: {SHOWN_FIRST.format('cover.jpeg')}" in caplog.text


def test_the_cover_alone_takes_the_albums_lock_as_apply_does(routes, tmp_path, monkeypatch):
    """Two replaces of one album - two of these, or one beside an Apply - never plan against each other's folder."""
    from src.routes import library

    taken, real = [], library._apply_lock
    monkeypatch.setattr(library, "_apply_lock", lambda path: (taken.append(path), real(path))[1])
    album(tmp_path, "folder.jpg")

    routes.post("/deadwax/library/art/fetch", json={"album_path": ALBUM, "replace": True})
    routes.post("/deadwax/library/retag/apply", json={"album_path": ALBUM, "release": RELEASE})

    assert taken == [ALBUM, ALBUM]
    assert library._APPLY_LOCKS[ALBUM] is real(ALBUM), "one lock for the album, shared"


def test_the_route_logs_the_cover_it_removed(routes, tmp_path, caplog):
    album(tmp_path, "folder.jpg")

    with caplog.at_level(logging.INFO):
        routes.post("/deadwax/library/art/fetch", json={"album_path": ALBUM, "replace": True})

    assert f"removed the old cover folder.jpg from {FOLDER} - cover.jpg replaces it" in caplog.text
