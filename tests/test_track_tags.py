"""
Editing tags by hand - the fourth thing in deadwax that writes to the user's filesystem.

What these protect is mostly what it REFUSES, the same as the retag tests: a filename that is
really a path, a tag that isn't on the list, a value that can't be what it claims, and any batch
with one of those in it. Then that an edit changes exactly what was edited and nothing else -
not the tags nobody touched, not the other files, not the folder's name.
"""

import asyncio
import os
import re
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from mutagen.flac import FLAC

from src.config import Config
from src.track_tags import EDITABLE_TAGS, execute_tag_edits, plan_tag_edits, validate_tag
from tests.test_retag import write_flac

ALBUM = "Dance Gavin Dance/Jackpot Juicer (2022)"
NAMES = ("01 - Untitled 2.flac", "02 - Cream of the Crop.flac", "03 - Synergy.flac")


def seed(root: Path) -> Path:
    """Three tracks of Jackpot Juicer, with the opening one stranded on disc 2."""
    directory = root / ALBUM
    common = {"album": "Jackpot Juicer", "albumartist": "Dance Gavin Dance",
              "artist": "Dance Gavin Dance", "date": "2022", "genre": "Post-hardcore"}
    write_flac(directory / NAMES[0], title="Untitled 2", tracknumber="1", discnumber="2", **common)
    write_flac(directory / NAMES[1], title="Cream of the Crop", tracknumber="2", **common)
    write_flac(directory / NAMES[2], title="Synergy", tracknumber="3", **{**common, "genre": "Rock"})
    (directory / "cover.jpg").write_bytes(b"\xff\xd8\xff\xe0 cover")
    return directory


def snapshot(directory: Path) -> dict:
    return {p.name: p.read_bytes() for p in directory.iterdir()}


# ---------------------------------------------------------------- the two lists

def test_the_editable_tags_are_exactly_the_ones_the_dialog_offers():
    """
    One list, in two languages. A field the dialog offers that this refuses fails on every
    save; one this accepts that the dialog never offers is a guard in front of nothing. Read
    straight out of the TypeScript, so drift fails here rather than in somebody's library.
    """
    source = (Path(__file__).resolve().parent.parent / "ui/src/lib/tagEdit.ts").read_text()
    block = source.split("export const EDIT_FIELDS", 1)[1].split("\n]", 1)[0]

    assert tuple(re.findall(r"key: '([a-z_]+)'", block)) == EDITABLE_TAGS


# ---------------------------------------------------------------- planning

def test_only_what_was_edited_is_planned(tmp_path):
    seed(tmp_path)

    plan = plan_tag_edits(ALBUM, [{"filename": NAMES[0], "tags": {"discnumber": "1"}}], str(tmp_path))

    assert plan["problems"] == []
    assert plan["files"] == [{"filename": NAMES[0], "changes": {"discnumber": {"from": "2", "to": "1"}}}]
    assert plan["changed_file_count"] == 1
    assert plan["empty"] is False


def test_planning_writes_nothing(tmp_path):
    directory = seed(tmp_path)
    before = snapshot(directory)

    plan_tag_edits(ALBUM, [{"filename": NAMES[0], "tags": {"title": "Intro"}}], str(tmp_path))

    assert snapshot(directory) == before


def test_one_value_across_mixed_tracks_changes_only_the_ones_that_differ(tmp_path):
    """
    The mass edit: one genre for all three, where two already have it. The preview lists the
    one track that actually changes, rather than claiming to rewrite all of them.
    """
    seed(tmp_path)
    edits = [{"filename": name, "tags": {"genre": "Post-hardcore"}} for name in NAMES]

    plan = plan_tag_edits(ALBUM, edits, str(tmp_path))

    assert [f["filename"] for f in plan["files"] if f["changes"]] == [NAMES[2]]
    assert plan["changed_file_count"] == 1
    assert plan["file_count"] == 3


def test_a_tag_nobody_edited_is_never_in_the_plan(tmp_path):
    seed(tmp_path)

    plan = plan_tag_edits(ALBUM, [{"filename": NAMES[2], "tags": {"composer": "Will Swan"}}], str(tmp_path))

    assert set(plan["files"][0]["changes"]) == {"composer"}


@pytest.mark.parametrize("cleared", ["", None, "   "])
def test_an_empty_value_removes_the_tag(tmp_path, cleared):
    directory = seed(tmp_path)

    plan = plan_tag_edits(ALBUM, [{"filename": NAMES[2], "tags": {"genre": cleared}}], str(tmp_path))
    assert plan["files"][0]["changes"] == {"genre": {"from": "Rock", "to": ""}}

    execute_tag_edits(plan, "apply")
    assert "genre" not in FLAC(str(directory / NAMES[2]))


# ---------------------------------------------------------------- what is refused

@pytest.mark.parametrize("filename", [
    "../../../etc/passwd", "/etc/passwd", "Jackpot Juicer (2022)/01 - Untitled 2.flac",
    "missing.flac", "cover.jpg", "", ".", "..",
])
def test_anything_but_an_audio_file_in_the_album_is_refused(tmp_path, filename):
    """
    Only a name found in a listing of the folder is accepted, so nothing a caller sends is
    joined onto a path until it has matched a file that was already there.
    """
    seed(tmp_path)

    plan = plan_tag_edits(ALBUM, [{"filename": filename, "tags": {"title": "x"}}], str(tmp_path))

    assert plan["files"] == []
    assert "not an audio file in this album" in plan["problems"][0]


@pytest.mark.parametrize("attempt", ["../../../etc", "", "/etc", "Dance Gavin Dance/../../.."])
def test_an_album_outside_the_library_is_refused(tmp_path, attempt):
    seed(tmp_path)

    plan = plan_tag_edits(attempt, [], str(tmp_path))

    assert plan["source"] is None
    assert plan["problems"] == ["that album is not inside the library"]


def test_a_symlink_out_of_the_library_is_refused(tmp_path):
    outside = tmp_path.parent / "outside-tags"
    outside.mkdir(exist_ok=True)
    write_flac(outside / "01 - Track.flac", title="Elsewhere")

    library = tmp_path / "library"
    library.mkdir()
    os.symlink(outside, library / "escape")

    plan = plan_tag_edits("escape", [{"filename": "01 - Track.flac", "tags": {"title": "x"}}],
                          str(library))

    assert plan["source"] is None
    assert FLAC(str(outside / "01 - Track.flac"))["title"] == ["Elsewhere"]


@pytest.mark.parametrize("key, value, says", [
    ("musicbrainz_albumid", "abc", "can't be edited here"),
    ("tracknumber", "one", "has to be a number"),
    ("discnumber", "2 of 2", "has to be a number"),
    ("date", "July 2022", "has to be a year or a date"),
    ("title", "two\nlines", "control character"),
    ("title", "x" * 1001, "longer than"),
])
def test_values_that_cannot_be_what_they_claim_are_refused(key, value, says):
    assert says in validate_tag(key, value)


@pytest.mark.parametrize("key, value", [
    ("tracknumber", "3"), ("tracknumber", "03"), ("tracknumber", "3/12"),
    #? MusicBrainz's number for a hidden track in the pregap
    ("tracknumber", "0"),
    ("discnumber", "1"), ("date", "2022"), ("date", "2022-07"), ("date", "2022-07-29"),
    ("title", "Pray to God for Your Mother"), ("genre", ""),
])
def test_ordinary_values_pass(key, value):
    assert validate_tag(key, value) is None


def test_one_bad_value_refuses_the_whole_batch(tmp_path):
    """Half an edit - some tracks changed, some not, and no telling which - is worse than none."""
    directory = seed(tmp_path)
    before = snapshot(directory)

    plan = plan_tag_edits(ALBUM, [
        {"filename": NAMES[0], "tags": {"discnumber": "1"}},
        {"filename": NAMES[1], "tags": {"tracknumber": "two"}},
    ], str(tmp_path))
    results = execute_tag_edits(plan, "apply")

    assert plan["problems"]
    assert results["written"] == 0
    assert snapshot(directory) == before


def test_the_same_bad_value_on_every_track_is_reported_once(tmp_path):
    seed(tmp_path)
    edits = [{"filename": name, "tags": {"date": "someday"}} for name in NAMES]

    assert len(plan_tag_edits(ALBUM, edits, str(tmp_path))["problems"]) == 1


def test_a_file_named_twice_is_refused(tmp_path):
    seed(tmp_path)
    edits = [{"filename": NAMES[0], "tags": {"title": "a"}}, {"filename": NAMES[0], "tags": {"title": "b"}}]

    assert any("twice" in p for p in plan_tag_edits(ALBUM, edits, str(tmp_path))["problems"])


# ---------------------------------------------------------------- writing

def test_the_jackpot_juicer_fix(tmp_path):
    """
    The case that prompted this: the opening track alone on disc 2. Two fields on one track and
    the album is in order - and nothing else about any file changes.
    """
    directory = seed(tmp_path)
    others = {name: (directory / name).read_bytes() for name in NAMES[1:]}

    plan = plan_tag_edits(ALBUM, [{"filename": NAMES[0], "tags": {"discnumber": "1", "tracknumber": "1"}}],
                          str(tmp_path))
    results = execute_tag_edits(plan, "apply")

    assert results == {"mode": "apply", "dry_run": False, "written": 1, "failed": 0, "problems": []}
    assert plan["files"][0]["changes"] == {"discnumber": {"from": "2", "to": "1"}}, \
        "the track number was already 1, so it is not a change"

    audio = FLAC(str(directory / NAMES[0]))
    assert audio["discnumber"] == ["1"]
    assert audio["title"] == ["Untitled 2"], "a tag nobody edited is left exactly as it was"
    assert {name: (directory / name).read_bytes() for name in NAMES[1:]} == others
    assert directory.is_dir(), "and the folder was not renamed"


def test_the_same_edit_twice_has_nothing_left_to_do(tmp_path):
    seed(tmp_path)
    edit = [{"filename": NAMES[0], "tags": {"discnumber": "1"}}]

    execute_tag_edits(plan_tag_edits(ALBUM, edit, str(tmp_path)), "apply")

    assert plan_tag_edits(ALBUM, edit, str(tmp_path))["empty"] is True


def test_dry_run_writes_nothing(tmp_path):
    directory = seed(tmp_path)
    before = snapshot(directory)

    plan = plan_tag_edits(ALBUM, [{"filename": NAMES[0], "tags": {"title": "Intro"}}], str(tmp_path))
    results = execute_tag_edits(plan, "dry_run")

    assert results["dry_run"] is True
    assert results["written"] == 1
    assert snapshot(directory) == before


def test_a_tag_the_format_cannot_hold_is_named_rather_than_swallowed(tmp_path, monkeypatch):
    """
    Easy MP4 has no originaldate, for one. An edit that quietly didn't happen reads exactly like
    one that did, so the refusal is reported by name - and the rest of the edit still lands.
    """
    import mutagen

    seed(tmp_path)
    plan = plan_tag_edits(ALBUM, [{"filename": NAMES[0], "tags": {"originaldate": "2022", "genre": "Rock"}}],
                          str(tmp_path))

    written = {}

    class Picky(dict):
        """Behaves like an easy-MP4 file: takes a genre, refuses an original date."""
        def __setitem__(self, key, value):
            if key == "originaldate":
                raise ValueError(f"{key!r} is not a valid key")
            written[key] = value

        def save(self):
            pass

    monkeypatch.setattr(mutagen, "File", lambda *args, **kwargs: Picky())
    results = execute_tag_edits(plan, "apply")

    assert written == {"genre": "Rock"}
    assert results["written"] == 1
    assert "can't hold originaldate" in results["problems"][0]


# ---------------------------------------------------------------- the endpoint

def no_store():
    """A request as the route sees one, from an app whose store never opened."""
    return SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace()))


def test_the_apply_route_refuses_an_invalid_batch_outright(tmp_path, monkeypatch):
    from src.routes.library import TagEditRequest, tags_apply

    directory = seed(tmp_path)
    before = snapshot(directory)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))

    body = TagEditRequest(album_path=ALBUM, edits=[{"filename": NAMES[0], "tags": {"tracknumber": "first"}}])

    with pytest.raises(HTTPException) as refused:
        asyncio.run(tags_apply(no_store(), body))

    assert refused.value.status_code == 400
    assert "has to be a number" in refused.value.detail
    assert snapshot(directory) == before


def test_the_apply_route_writes_and_forgets_the_cached_album(tmp_path, monkeypatch):
    """
    An in-place tag edit doesn't move the folder's mtime, so the scan cache would go on serving
    the old values - and the edit would look like it had silently failed.
    """
    from src.routes import library as routes

    directory = seed(tmp_path)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    forgotten: list[str] = []
    monkeypatch.setattr(routes, "forget_cached_album", forgotten.append)

    body = routes.TagEditRequest(album_path=ALBUM, edits=[{"filename": NAMES[0], "tags": {"discnumber": "1"}}])
    response = asyncio.run(routes.tags_apply(no_store(), body))

    assert response["results"]["written"] == 1
    assert forgotten == [str(directory)]
    assert FLAC(str(directory / NAMES[0]))["discnumber"] == ["1"]
