"""
Replacing an album's cover removes the cover file it replaces (cover removal, 27 Nov).

Both writers only ever wrote `cover.<ext>`, so a `folder.jpg`, a `Cover.jpg` on a case-sensitive disk
(James's server) or a `cover.jpeg` beside a new `cover.jpg` stayed - and find_cover_file went on
showing the old cover: the replace did nothing visible, and the editor's "Apply deletes it" wasn't
true. James chose: "Delete the old file".

So the plan names the file (`art.removes`, plan_cover_art's `removes`), and the write removes that one
file once the new cover is saved, behind every guard again - and says, never removes, any other cover
that still outranks the new one. Both writers are run through each case: Apply with the cover on
(execute_retag) and the cover alone (save_cover_art, which the editor's Replace cover only and
Compare covers' replace both call, through /library/art/fetch).
"""

import logging
import sys
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from mutagen.flac import FLAC, Picture

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.config import Config  # noqa: E402
from src.library import find_cover_file  # noqa: E402
from src.retag import (LINK_NOT_REMOVED, execute_retag, plan_cover_art, plan_retag,  # noqa: E402
                       remove_replaced_cover, save_cover_art)
from tests.test_retag import RELEASE, seed  # noqa: E402

#? already filed under the release's own name, so applying it retags in place and the folder stays put
FOLDER = "The Slow Rush (2020) [Deluxe edition]"
ALBUM = f"Tame Impala/{FOLDER}"
NEW = (b"\xff\xd8\xff\xe0 the pressing's cover", "image/jpeg")
OLD = b"\xff\xd8\xff\xe0 your cover"
WRITERS = ("apply", "alone")


def album(root: Path, *covers: str) -> Path:
    directory = seed(root, folder=FOLDER, musicbrainz_albumid="mbid-deluxe")
    for name in covers:
        #? open(), not write_bytes: failing_write makes a cover's write_bytes fail
        with open(directory / name, "wb") as file:
            file.write(OLD)
    return directory


def case_sensitive(root: Path) -> bool:
    probe = root / "case-probe"
    probe.write_bytes(b"")
    try:
        return not (root / "CASE-PROBE").exists()
    finally:
        probe.unlink()


def plan_of(writer: str, root: Path) -> dict:
    """The art part of each writer's plan - the one the write is then handed, as the routes do."""
    if writer == "apply":
        return plan_retag(ALBUM, RELEASE, str(root), want_art=True)
    return plan_cover_art(ALBUM, str(root), replace=True)


def removes_of(writer: str, plan: dict):
    return plan["art"]["removes"] if writer == "apply" else plan["removes"]


def write(writer: str, root: Path, plan: dict, art=NEW) -> dict:
    """Run the writer on `plan`; answer {written, removed, problems} whichever it was."""
    if writer == "apply":
        results = execute_retag(plan, RELEASE, "apply", art)
        cover = [p for p in results["problems"] if "cover" in p or "shown" in p]
        return {"written": results["art_written"], "removed": results["art_removed"], "problems": cover}
    results = save_cover_art(ALBUM, str(root), art, plan["removes"])
    return {"written": results["written"], "removed": results["removed"],
            "problems": results["problems"] + ([results["problem"]] if results["problem"] else [])}


def replace(writer: str, root: Path, art=NEW) -> tuple[dict, dict]:
    plan = plan_of(writer, root)
    return plan, write(writer, root, plan, art)


def shown(directory: Path) -> Path | None:
    return find_cover_file(sorted(p for p in directory.iterdir() if p.is_file()))


def images(directory: Path) -> list[str]:
    return sorted(p.name for p in directory.iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".gif"})


# ---------------------------------------------------------------- the replace shows

@pytest.mark.parametrize("writer", WRITERS)
@pytest.mark.parametrize("old", ["folder.jpg", "Cover.jpg", "cover.jpeg", "cover.png"])
def test_replacing_a_cover_removes_it_and_the_new_one_is_shown(tmp_path, writer, old):
    directory = album(tmp_path, old)

    plan, done = replace(writer, tmp_path)

    assert removes_of(writer, plan) == old, "the plan names the file the replace deletes"
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

    assert removes_of(writer, plan) == "cover.jpg"
    assert done["written"] == "cover.jpg" and done["removed"] is None and done["problems"] == []
    assert (directory / "cover.jpg").read_bytes() == NEW[0], "overwritten, not deleted after being written"
    assert images(directory) == ["back.jpg", "cover.jpg", "folder.jpg"]
    assert (directory / "folder.jpg").read_bytes() == OLD


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

    assert removes_of(writer, plan) is None
    assert done["written"] == "cover.jpg" and done["removed"] is None and done["problems"] == []
    assert sorted(p.name for p in directory.iterdir()) == sorted(before + ["cover.jpg"])
    assert [p.data for p in FLAC(str(track)).pictures] == [OLD], "the embedded picture is left as it was"


# ---------------------------------------------------------------- what is never removed

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
    target.write_bytes(OLD)
    (directory / "folder.jpg").symlink_to(target)

    plan, done = replace(writer, library)

    assert removes_of(writer, plan) == "folder.jpg"
    assert done["written"] == "cover.jpg" and done["removed"] is None
    assert done["problems"] == [f"saved cover.jpg, but the old folder.jpg {LINK_NOT_REMOVED}"]
    assert (directory / "folder.jpg").is_symlink(), "the link is left"
    assert target.read_bytes() == OLD, "and never followed"


@pytest.mark.parametrize("writer", WRITERS)
def test_a_cover_made_a_link_after_the_plan_is_refused_at_the_write(tmp_path, writer):
    """Every guard is checked again at the write: the plan named a plain file."""
    directory = album(tmp_path, "folder.jpg")
    plan = plan_of(writer, tmp_path)
    (directory / "front.jpg").write_bytes(OLD)
    (directory / "folder.jpg").unlink()
    (directory / "folder.jpg").symlink_to(directory / "front.jpg")

    done = write(writer, tmp_path, plan)

    assert done["removed"] is None and (directory / "folder.jpg").is_symlink()
    assert (directory / "front.jpg").read_bytes() == OLD
    assert f"saved cover.jpg, but the old folder.jpg {LINK_NOT_REMOVED}" in done["problems"]


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

    assert removes_of(writer, plan) == covers[0]
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
    cover.jpeg then still sorts before the new cover.jpg."""
    directory = album(tmp_path, "cover.gif", "cover.jpeg")

    plan, done = replace(writer, tmp_path)

    assert removes_of(writer, plan) == "cover.gif"
    assert done["removed"] == "cover.gif"
    assert done["problems"] == [
        "saved cover.jpg, but cover.jpeg is still shown first - another cover in the album's folder, left as it was"]
    assert images(directory) == ["cover.jpeg", "cover.jpg"]
    assert (directory / "cover.jpeg").read_bytes() == OLD


@pytest.mark.parametrize("writer", WRITERS)
def test_cover_jpg_beside_cover_jpeg_on_a_case_sensitive_disk(tmp_path, writer):
    """The case the review found, on James's server: Cover.jpg (shown) and cover.jpeg. Cover.jpg goes,
    cover.jpeg is said - and left. On a case-insensitive disk Cover.jpg is overwritten instead."""
    directory = album(tmp_path, "Cover.jpg", "cover.jpeg")

    plan, done = replace(writer, tmp_path)

    assert removes_of(writer, plan) == "Cover.jpg"
    if case_sensitive(tmp_path):
        assert done["removed"] == "Cover.jpg"
        assert done["problems"] == [
            "saved cover.jpg, but cover.jpeg is still shown first - another cover in the album's folder, left as it was"]
        assert images(directory) == ["cover.jpeg", "cover.jpg"]
    else:
        assert done["removed"] is None and done["problems"] == []
        assert images(directory) == ["Cover.jpg", "cover.jpeg"]
        assert (directory / "Cover.jpg").read_bytes() == NEW[0]
    assert (directory / "cover.jpeg").read_bytes() == OLD


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
    (directory / "scans" / "front.jpg").write_bytes(OLD)
    (tmp_path / "Tame Impala" / "elsewhere.jpg").write_bytes(OLD)
    (directory / "cover.jpg").write_bytes(NEW[0])
    before = sorted(str(p.relative_to(tmp_path)) for p in tmp_path.rglob("*"))

    removed, problems = remove_replaced_cover(directory, directory / "cover.jpg", name, str(tmp_path))

    assert removed is None
    assert problems == [f"saved cover.jpg, but the old {name} was left where it is - {why}"]
    assert sorted(str(p.relative_to(tmp_path)) for p in tmp_path.rglob("*")) == before


def test_the_removal_takes_nothing_from_an_album_outside_the_library(tmp_path):
    directory = album(tmp_path / "elsewhere", "folder.jpg")
    (directory / "cover.jpg").write_bytes(NEW[0])

    removed, problems = remove_replaced_cover(directory, directory / "cover.jpg", "folder.jpg", str(tmp_path / "library"))

    assert removed is None and (directory / "folder.jpg").exists()
    assert problems == ["saved cover.jpg, but the old folder.jpg was left where it is - the album isn't inside the library"]


def test_the_removal_takes_nothing_from_the_library_itself(tmp_path):
    (tmp_path / "folder.jpg").write_bytes(OLD)
    (tmp_path / "cover.jpg").write_bytes(NEW[0])

    removed, problems = remove_replaced_cover(tmp_path, tmp_path / "cover.jpg", "folder.jpg", str(tmp_path))

    assert removed is None and (tmp_path / "folder.jpg").exists()
    assert "the album isn't inside the library" in problems[0]


def test_the_removal_waits_for_the_new_cover_to_be_on_disk(tmp_path):
    directory = album(tmp_path, "folder.jpg")

    removed, problems = remove_replaced_cover(directory, directory / "cover.jpg", "folder.jpg", str(tmp_path))

    assert removed is None and (directory / "folder.jpg").exists()
    assert problems == ["saved cover.jpg, but the old folder.jpg was left where it is - "
                        "the new cover couldn't be found after saving it",
                        #? true, too: with no cover.jpg, folder.jpg is the cover shown
                        "saved cover.jpg, but folder.jpg is still shown first - another cover in the album's folder, "
                        "left as it was"]


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
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    monkeypatch.setattr(library, "_HELD_RENAMES", {})
    monkeypatch.setattr(library, "_APPLY_LOCKS", {})
    monkeypatch.setattr(library, "coverart_client", Archive())
    app = FastAPI()
    app.include_router(library.router, prefix="/deadwax/library")
    return TestClient(app)


#? what a caller might send hoping to choose the file removed - pydantic drops every one of these, and the
#? server plans again from the folder
FORGED = {"removes": "back.jpg", "art": {"action": "replace", "removes": "back.jpg"},
          "plan": {"art": {"action": "replace", "removes": "back.jpg"}}}


def test_the_preview_names_the_file_a_replace_removes_and_removes_nothing(routes, tmp_path):
    directory = album(tmp_path, "folder.jpg")

    plan = routes.post("/deadwax/library/retag/preview",
                       json={"album_path": ALBUM, "release": RELEASE, "fetch_art": True}).json()

    assert plan["art"]["action"] == "replace"
    assert (plan["art"]["existing"], plan["art"]["removes"]) == ("folder.jpg", "folder.jpg")
    assert images(directory) == ["folder.jpg"]


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

    said = "saved cover.jpg, but cover.jpeg is still shown first - another cover in the album's folder, left as it was"
    assert (answer["removed"], answer["replaced"]) == ("cover.gif", "cover.gif")
    assert answer["problems"] == [said]
    assert f"{FOLDER}: {said}" in caplog.text


def test_the_route_logs_the_cover_it_removed(routes, tmp_path, caplog):
    album(tmp_path, "folder.jpg")

    with caplog.at_level(logging.INFO):
        routes.post("/deadwax/library/art/fetch", json={"album_path": ALBUM, "replace": True})

    assert f"removed the old cover folder.jpg from {FOLDER} - cover.jpg replaces it" in caplog.text
