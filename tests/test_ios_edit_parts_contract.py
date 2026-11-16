"""
The iPhone app's Edit album, its parts after Release (Phase 8, slices 2-4 - notes/ios-specs/phase8-managing.md 3.4-3.7;
notes/ios.md "Edit album's Tags, Artwork, Lyrics and Delete"), against the routes they ask, read from the app's own source
(ios/DeadwaxKit/Sources/DeadwaxCore: TagEdit.swift, AlbumInfo.swift, EditClient.swift, Routes.swift) and held to the
server's, as tests/test_ios_edit_contract.py holds slice 1's:

- Tags: what it SENDS - TagEditBody and its Edit, the keys TagEditRequest and TagEdit declare (pydantic drops an
  undeclared one without a word), only the eleven tags the server lets be edited, every draft the vectors hold (the web's
  own tagEdit.ts, Fixtures/edit/edit-parts-vectors.json) taken by the real preview over a real folder; a value the web's
  rule takes never one the server refuses. What it READS - TagEditPlan, TagEditFile and TagChange from the real preview,
  TagEditResponse and TagEditResults from a real apply, AlbumFile and EmbeddedPicture from the real track listing of a
  file with a picture in it, and the picture itself (a 404 for one that isn't there). How long it waits.
- and that its writes, sent with no Origin or Referer, are what the same-origin guard lets through.
"""

import inspect
import json
import re
import sys
from pathlib import Path

from mutagen.flac import FLAC, Picture

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import library  # noqa: E402
from src import track_tags  # noqa: E402
from src.routes import library as library_route  # noqa: E402
from tests.test_ios_contract import CORE, coding_keys, swift_function, swift_struct  # noqa: E402
from tests.test_ios_edit_contract import (  # noqa: E402,F401 - the fixtures, used by name
    ALBUM,
    client,
    nothing_left_over,
    reads,
    sends,
    timeouts,
)

PARTS = CORE.parent.parent / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "edit" / "edit-parts-vectors.json"
FILES = ("01 - One More Year.flac", "02 - Instant Destiny.flac")
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64


def vectors() -> dict:
    return json.loads(PARTS.read_text(encoding="utf-8"))


def nested(struct: str, name: str) -> set[str]:
    """The JSON names of a struct nested in another (TagEditBody.Edit): its own CodingKeys."""
    body = swift_struct(struct)
    match = re.search(r"\bstruct\s+" + name + r"\b[^{]*\{", body)
    assert match, f"no {struct}.{name}"
    depth = 0
    for index in range(match.end() - 1, len(body)):
        depth += {"{": 1, "}": -1}.get(body[index], 0)
        if depth == 0:
            keys = coding_keys(body[match.end():index])
            assert keys is not None, f"{struct}.{name} has no CodingKeys"
            return set(keys.values())
    raise AssertionError("unbalanced braces")


def embed(path: Path) -> None:
    audio = FLAC(str(path))
    picture = Picture()
    picture.type, picture.mime, picture.data, picture.desc = 3, "image/jpeg", JPEG, "front"
    audio.add_picture(picture)
    audio.save()


# ---------------------------------------------------------------------------- Tags: what the phone sends

def test_the_tag_body_is_the_servers_model():
    assert sends("TagEditBody") == {"album_path", "edits"} <= set(library_route.TagEditRequest.model_fields)
    assert nested("TagEditBody", "Edit") == {"filename", "tags"} <= set(library_route.TagEdit.model_fields)
    # the phone sends strings - "" removes a tag, as the web sends it; the server takes "" or null alike
    assert "public let tags: [String: String]" in swift_struct("TagEditBody")


def test_the_forms_fields_are_the_tags_the_server_lets_be_edited():
    fields = [field["key"] for field in vectors()["tags"]["fields"]]
    assert fields == list(track_tags.EDITABLE_TAGS), "the web's TAG_FIELDS, in its order, is the server's list"
    # and the phone's own list is the vectors' (EditPartsVectorTests holds labels and flags)
    source = (CORE / "TagEdit.swift").read_text(encoding="utf-8")
    assert re.findall(r'Field\(key: "(\w+)"', source) == fields


def test_a_value_the_web_takes_is_never_one_the_server_refuses():
    # the phone offers Apply only with no field wrong as TagEdit.problem judges it (the web's own rule, held to the web
    # by EditPartsVectorTests): every value it takes, the server's validate_tag takes too, trimmed as the phone sends it
    # and stripped again as the server does. The web is stricter in three places only, which refuse something the
    # server would have written - never the other way: digits from other scripts (Python's \d takes them), a NEL after
    # a number (Python's strip removes it, JS's trim doesn't), and a length counted in UTF-16 units, not characters
    stricter = 0
    for case in vectors()["tags"]["problems"]:
        key, value, web = case["key"], case["value"], case["problem"]
        if key not in track_tags.EDITABLE_TAGS:
            continue
        server = track_tags.validate_tag(key, value.strip())
        if web is None:
            assert server is None, (key, value, server)
        elif server is None:
            stricter += 1
            text = value.strip()
            other_digits = any(ch.isdigit() and not ch.isascii() for ch in value)
            nel = "\x85" in value
            astral = len(text.encode("utf-16-le")) // 2 > track_tags.MAX_VALUE_LENGTH >= len(text)
            assert other_digits or nel or astral, (key, value, web)
    assert stricter <= 10, "the web's rule drifted further from the server's"


def test_every_draft_the_vectors_hold_is_taken_by_the_real_preview(client):
    # TagEdit.edits' bodies (the web's edits() over each draft) posted as the phone posts them, to the real folder's
    # files: answered with a plan - never a 422 - and every tag the plan names one the body sent
    cases = [case for case in vectors()["tags"]["edits"] if case["edits"]]
    assert len(cases) >= 20
    for case in cases:
        tags = case["edits"][0]["tags"]
        assert all(edit["tags"] == tags for edit in case["edits"]), "one draft goes to every file chosen"
        assert set(tags) <= set(track_tags.EDITABLE_TAGS), set(tags) - set(track_tags.EDITABLE_TAGS)
        body = {"album_path": ALBUM, "edits": [{"filename": name, "tags": tags} for name in FILES]}
        answer = client.post("/deadwax/library/tags/preview", json=body)
        assert answer.status_code == 200, answer.text
        plan = answer.json()
        assert plan["album_path"] == ALBUM and plan["file_count"] + len(plan["problems"]) >= 1
        for file in plan["files"]:
            assert set(file["changes"]) <= set(tags)


# ---------------------------------------------------------------------------- Tags: what the phone reads

def test_the_preview_holds_what_the_phone_reads(client):
    body = {"album_path": ALBUM, "edits": [{"filename": name, "tags": {"genre": "Psychedelic", "title": ""}}
                                           for name in FILES]}
    answer = client.post("/deadwax/library/tags/preview", json=body)
    assert answer.status_code == 200, answer.text
    plan = answer.json()
    assert reads("TagEditPlan") == set(plan)
    assert plan["changed_file_count"] == 2 and not plan["problems"] and plan["empty"] is False
    for file in plan["files"]:
        assert reads("TagEditFile") == set(file)
        assert set(file["changes"]) == {"genre", "title"}
        for change in file["changes"].values():
            assert reads("TagChange") == set(change)
    # the filename is the one field a file can't do without: decoded strictly
    assert "filename = try fields.decode(String.self, forKey: .filename)" in swift_struct("TagEditFile")
    # a refusal the plan carries - the whole batch refused, the problems the phone says - and a folder outside the library
    bad = client.post("/deadwax/library/tags/preview",
                      json={"album_path": ALBUM, "edits": [{"filename": "../x.flac", "tags": {"date": "July 2022"}}]})
    assert bad.status_code == 200 and len(bad.json()["problems"]) == 1
    gone = client.post("/deadwax/library/tags/preview", json={"album_path": "../..", "edits": []})
    assert gone.json()["source"] is None and gone.json()["problems"]


def test_an_apply_answers_what_the_phone_reads_and_a_refusal_is_a_400(client):
    body = {"album_path": ALBUM, "edits": [{"filename": FILES[0], "tags": {"genre": "Psychedelic"}}]}
    answer = client.post("/deadwax/library/tags/apply", json=body)
    assert answer.status_code == 200, answer.text
    response = answer.json()
    assert reads("TagEditResponse") == set(response)
    assert reads("TagEditPlan") == set(response["plan"])
    assert reads("TagEditResults") <= set(response["results"])
    assert response["results"]["written"] == 1 and response["results"]["failed"] == 0
    # written: the folder's files say so now, as Tags reads them again
    files = client.get("/deadwax/library/tracks", params={"album": ALBUM}).json()["files"]
    assert files[0]["tags"]["genre"] == "Psychedelic"
    # a value the server refuses refuses the whole batch with a 400 and its words (RetagFlow.outcome: refused,
    # nothing written) - what EditWords.writeFailure says
    refused = client.post("/deadwax/library/tags/apply", json={
        "album_path": ALBUM, "edits": [{"filename": FILES[1], "tags": {"genre": "Rock", "date": "July 2022"}}]})
    assert refused.status_code == 400
    assert refused.json()["detail"] == "date has to be a year or a date, like 2022 or 2022-07-29"
    after = client.get("/deadwax/library/tracks", params={"album": ALBUM}).json()["files"]
    assert after[1]["tags"].get("genre", "") == "", "half an edit is worse than none"
    assert "results = try fields.decode(TagEditResults.self, forKey: .results)" in swift_struct("TagEditResponse")


def test_a_tracks_files_and_its_pictures_are_what_the_phone_reads(client, tmp_path):
    embed(tmp_path / "music" / ALBUM / FILES[0])
    library.clear_scan_cache()
    answer = client.get("/deadwax/library/tracks", params={"album": ALBUM})
    assert answer.status_code == 200, answer.text
    files = answer.json()["files"]
    for file in files:
        assert reads("AlbumFile") <= set(file), reads("AlbumFile") - set(file)
    [picture] = files[0]["pictures"]
    assert reads("EmbeddedPicture") == set(picture)
    assert picture["label"] == "Front cover" and picture["size"] == len(JPEG) and picture["description"] == "front"
    # the picture itself, asked as the phone asks it; one that isn't there is a 404 (EditClient: nil)
    query = swift_function("EditClient.swift", "trackPictureRequest")
    assert '("album", path), ("file", file), ("index", String(index))' in query
    got = client.get("/deadwax/library/tracks/picture", params={"album": ALBUM, "file": FILES[0], "index": 0})
    assert got.status_code == 200 and got.content == JPEG and got.headers["content-type"] == "image/jpeg"
    for params in ({"album": ALBUM, "file": FILES[0], "index": 1}, {"album": ALBUM, "file": FILES[1], "index": 0}):
        assert client.get("/deadwax/library/tracks/picture", params=params).status_code == 404
    assert "accept: [200, 404]" in swift_function("EditClient.swift", "trackPicture")


# ---------------------------------------------------------------------------- how long the phone waits

def test_the_tag_routes_are_waited_for_past_a_folders_read():
    # the preview reads every file it is sent (MAX_EDITS of them at most) - as the track listing reads them; the apply
    # reads them again, writes each, and then reads the folder into the scan's cache and the store index - nothing on
    # the network, no pause, no lock (track_tags writes tags only: no file renamed, no folder moved)
    wait = timeouts()
    assert wait["tagsPreview"] >= wait["libraryTracks"]
    assert wait["tagsApply"] >= 2 * wait["tagsPreview"]
    apply = inspect.getsource(library_route.tags_apply)
    for slow in ("_pause_before_rename", "coverart_client", "_wait_for_navidrome_scan", "_album_lock"):
        assert slow not in apply, slow
    assert "rename" not in inspect.getsource(track_tags.execute_tag_edits).replace("renamed", "")
    # a picture is one file's read: as long as the listing's
    assert wait["trackPicture"] >= wait["libraryTracks"]


def test_each_part_is_asked_with_the_permission_the_root_shows_it_for():
    # Tags is on the root under Edit albums (Managing.albumEdit's `editors`), as its routes are; the track listing and
    # its pictures are any signed-in person's (tests/test_logins.py ROUTES holds the server's side)
    from tests.test_logins import ROUTES
    assert ROUTES[("POST", "/deadwax/library/tags/preview")] == "edit"
    assert ROUTES[("POST", "/deadwax/library/tags/apply")] == "edit"
    assert ROUTES[("GET", "/deadwax/library/tracks/picture")] == "user"
    sheet = (CORE.parent.parent.parent / "App" / "Edit" / "EditAlbumSheet.swift").read_text(encoding="utf-8")
    editors = sheet.index("if edit.editors, let retag = model.retag {")
    assert editors < sheet.index("NavigationLink(value: EditPage.tags)")
