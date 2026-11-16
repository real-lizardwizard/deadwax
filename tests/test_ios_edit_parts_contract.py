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
- Artwork and Lyrics (slice 3): what Get cover, Get CD art and Get lyrics SEND - LyricsFetchBody, DiscArtFetchBody and
  CoverFetchBody, nothing replaced or re-timed - and what they READ: LyricsSummary from a real lyrics fetch over a real
  folder (LRCLIB faked), CoverFetched and the 404 a release with no cover is, DiscArtFetched and a CD art picture asked
  by name (the Archive faked), a second Get never replacing what the first saved; how long each is waited for, worked
  out from the server's own timeouts; and the permission each is asked with.
- Delete album (slice 4): what it SENDS - DeleteAlbumBody, DeleteRequest's one field, and the summary asked by the
  folder - and what it READS: DeletionSummary from a real summary of a real folder holding a file the scan ignores (and
  the logins-on keys the route writes), AlbumDeleted from a real delete, after which the scan no longer lists the folder
  (what settles a delete that never answered); each refusal's words; how long each is waited for; and its permission.
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
from src.config import Config  # noqa: E402
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


# ---------------------------------------------------------------------------- Artwork and Lyrics: what the phone sends

def tagged(root: Path, release: str = "b84ee12a-09ef-421b-82de-0441a926375b") -> None:
    """The seeded album tagged with a MusicBrainz release - what Get cover and Get CD art look one up by."""
    for name in FILES:
        audio = FLAC(str(root / ALBUM / name))
        audio["musicbrainz_albumid"] = release
        audio.save()
    library.clear_scan_cache()


def scanned(client) -> dict:
    """The folder as the phone's scan reads it (`?tracks=false`)."""
    albums = client.get("/deadwax/library/albums", params={"tracks": "false"}).json()["albums"]
    [album] = [album for album in albums if album["path"] == ALBUM]
    return album


def test_the_get_bodies_are_the_servers_models_and_never_replace():
    assert sends("LyricsFetchBody") == {"album_path", "replace", "retime"} <= set(library_route.LyricsRequest.model_fields)
    assert sends("DiscArtFetchBody") == {"album_path"} <= set(library_route.DiscArtRequest.model_fields)
    # GetArtButton's, GetLyricsButton's and GetDiscArtButton's bodies: the folder alone, nothing replaced, nothing
    # re-timed, the release the folder's own tags name
    assert "CoverFetchBody(albumPath: path, replace: false, releaseMbid: nil)" in swift_function("EditClient.swift",
                                                                                                 "getCover")
    lyrics = swift_struct("LyricsFetchBody")
    assert "self.replace = false" in lyrics and "self.retime = false" in lyrics
    assert "LyricsFetchBody(albumPath: path)" in swift_function("EditClient.swift", "getLyrics")
    assert "DiscArtFetchBody(albumPath: path)" in swift_function("EditClient.swift", "getDiscArt")


# ---------------------------------------------------------------------------- Artwork and Lyrics: what the phone reads

class FakeLrclib:
    """LRCLIB with lyrics for the first track only - synced - counting what it is asked."""

    def __init__(self):
        self.asked: list[str] = []

    async def find(self, lookup: dict):
        self.asked.append(lookup["title"])
        if lookup["title"] == "One More Year":
            return {"syncedLyrics": "[00:01.00] One more year", "plainLyrics": "One more year"}
        return None


def test_get_lyrics_answers_what_the_phone_reads_and_never_replaces(client, monkeypatch):
    lrclib = FakeLrclib()
    monkeypatch.setattr(library_route, "lrclib", lrclib)
    body = {"album_path": ALBUM, "replace": False, "retime": False}
    answer = client.post("/deadwax/library/lyrics/fetch", json=body)
    assert answer.status_code == 200, answer.text
    summary = answer.json()
    assert reads("LyricsSummary") <= set(summary), reads("LyricsSummary") - set(summary)
    assert (summary["written"], summary["missing"], summary["synced"], summary["kept"]) == (1, 1, 1, 0)
    # what the page's line and the root's row count next: the scan's own
    album = scanned(client)
    assert (album["lyrics_count"], album["track_count"]) == (1, 2)
    # a second Get asks only for the track without one, and keeps the .lrc there
    again = client.post("/deadwax/library/lyrics/fetch", json=body).json()
    assert (again["written"], again["kept"], again["missing"]) == (0, 1, 1)
    assert lrclib.asked == ["One More Year", "Instant Destiny", "Instant Destiny"]
    # a folder that isn't the library's is refused with its words (GetRun: failed, nothing read again)
    refused = client.post("/deadwax/library/lyrics/fetch", json={"album_path": "../..", "replace": False, "retime": False})
    assert refused.status_code == 400 and refused.json()["detail"] == "that album is not inside the library"


def test_get_cover_is_a_404_when_the_archive_has_none_and_the_cover_after(client, monkeypatch, tmp_path):
    tagged(tmp_path / "music")
    fronts: list = [(None, "missing")]

    async def fetch_front_why(release_mbid, size=None):
        return fronts[0]

    monkeypatch.setattr(library_route.coverart_client, "fetch_front_why", fetch_front_why)
    body = {"album_path": ALBUM, "replace": False, "release_mbid": None}
    # a fact about the release: GetRun's `none`, Look again - the detail said under the button
    missing = client.post("/deadwax/library/art/fetch", json=body)
    assert missing.status_code == 404
    assert missing.json()["detail"] == "the Cover Art Archive has no front cover for that release"
    fronts[0] = (None, "unreachable")
    assert client.post("/deadwax/library/art/fetch", json=body).status_code == 502, "maybe worth another go"
    fronts[0] = ((JPEG + b"\x00" * 2048, "image/jpeg"), "ok")
    saved = client.post("/deadwax/library/art/fetch", json=body)
    assert saved.status_code == 200, saved.text
    assert reads("CoverFetched") <= set(saved.json()) and saved.json()["written"] == "cover.jpg"
    # the folder read again has it: Get cover is no longer offered (GetResults.offersCover), the cover drawn
    assert scanned(client)["art"] == "file"
    assert client.get("/deadwax/library/art", params={"album": ALBUM}).status_code == 200


def test_get_cd_art_answers_what_the_phone_reads_and_never_replaces(client, monkeypatch, tmp_path):
    tagged(tmp_path / "music")
    picture = JPEG + b"\x00" * 2048

    async def release_images(release_mbid):
        return [{"types": ["Medium"], "image": "https://coverartarchive.org/release/x/1.jpg",
                 "thumbnails": {"500": "https://coverartarchive.org/release/x/1-500.jpg"}}]

    async def fetch_image(url):
        return picture, "image/jpeg"

    monkeypatch.setattr(library_route.coverart_client, "release_images", release_images)
    monkeypatch.setattr(library_route.coverart_client, "fetch_image", fetch_image)
    answer = client.post("/deadwax/library/disc_art/fetch", json={"album_path": ALBUM})
    assert answer.status_code == 200, answer.text
    assert reads("DiscArtFetched") == set(answer.json())
    assert answer.json() == {"written": ["disc.jpg"], "source": "the Cover Art Archive"}
    # the grid's pictures: the scan's disc_art, each asked by name as the phone asks it
    album = scanned(client)
    assert album["disc_art"] == ["disc.jpg"]
    query = swift_function("EditClient.swift", "libraryDiscArtRequest")
    assert '("album", path), ("file", file)' in query
    got = client.get("/deadwax/library/disc_art", params={"album": ALBUM, "file": "disc.jpg"})
    assert got.status_code == 200 and got.content == picture and got.headers["content-type"] == "image/jpeg"
    # a name the scan doesn't count as disc art, or one that isn't there: the 404 EditClient reads as nothing
    for name in ("cover.jpg", "disc2.jpg", "../disc.jpg"):
        assert client.get("/deadwax/library/disc_art", params={"album": ALBUM, "file": name}).status_code == 404, name
    assert "accept: [200, 404]" in swift_function("EditClient.swift", "libraryDiscArt")
    # a second Get never replaces it: refused, with its words (GetResults.hasOwnDiscArt hides the button first)
    again = client.post("/deadwax/library/disc_art/fetch", json={"album_path": ALBUM})
    assert again.status_code == 400 and again.json()["detail"] == "this album already has CD art: disc.jpg"
    # and with nothing on the Archive, a 404 - GetRun's `none`, Look again
    (tmp_path / "music" / ALBUM / "disc.jpg").unlink()
    library.clear_scan_cache()

    async def nothing(release_mbid):
        return []

    monkeypatch.setattr(library_route.coverart_client, "release_images", nothing)
    monkeypatch.setattr(Config, "FANARTTV_KEY", None)
    none = client.post("/deadwax/library/disc_art/fetch", json={"album_path": ALBUM})
    assert none.status_code == 404 and none.json()["detail"].startswith("no CD art on the Cover Art Archive")


# ---------------------------------------------------------------------------- Artwork and Lyrics: how long the phone waits

#: tracks of an album Get lyrics is held for in full - a long LP's; one longer may outlast it, and is then said as "may
#: have finished" and read again (GetRun's unanswered), never asked again unseen
LYRICS_TRACKS = 12
#: CD art pictures held for in full - a four-disc set's
DISC_ART_DISCS = 4


def _seconds(source: str, connect: str = r"connect=([\d.]+)", read: str = r"read=([\d.]+)") -> float:
    return float(re.search(connect, source).group(1)) + float(re.search(read, source).group(1))


def test_the_gets_are_waited_for_past_their_worst_case():
    from src import lyrics as lyrics_module
    from src.api import artist_images_endpoint, coverart_endpoint, lrclib_endpoint
    wait = timeouts()
    # Get lyrics: each track asked by its own artist name (LRCLIB's exact lookup, then its search - two requests at
    # most for a name: a folder whose artist is its album artist, as most are), each request's longest silence its
    # connection and its read, CONCURRENCY tracks at once
    client = inspect.getsource(lrclib_endpoint.LrclibClient.get_client)
    request = _seconds(client)
    assert request == 40
    assert "CONCURRENCY" in inspect.getsource(lyrics_module.fetch_album_lyrics)
    rounds = -(-LYRICS_TRACKS // lyrics_module.CONCURRENCY)
    lyrics = rounds * 2 * request
    assert lyrics == 480
    assert wait["lyricsFetch"] >= lyrics + 60
    # Get CD art: the Archive's listing, fanart.tv's (with a key) when it has none, then one picture a disc - the
    # Archive's or fanart.tv's, the slower of the two
    archive = _seconds(inspect.getsource(coverart_endpoint.CoverArtClient.get_client))
    images = artist_images_endpoint.IMAGE_TIMEOUT
    listing = artist_images_endpoint.JSON_TIMEOUT
    fanart = listing.connect + listing.read
    picture = max(archive, images.connect + images.read)
    disc = archive + fanart + DISC_ART_DISCS * picture
    assert disc == 300
    assert wait["discArtFetch"] >= disc + 60
    # a CD art picture is one file read off disk, as the cover's
    assert wait["libraryDiscArt"] >= wait["libraryArt"]
    # Get cover is the cover alone's route, with no replacing: the same wait
    assert "Routes.artFetch" in swift_function("EditClient.swift", "getCover")


def test_artwork_and_lyrics_are_asked_with_the_permission_the_root_shows_them_for():
    from tests.test_logins import ROUTES
    assert ROUTES[("POST", "/deadwax/library/art/fetch")] == "edit"
    assert ROUTES[("POST", "/deadwax/library/lyrics/fetch")] == "edit"
    assert ROUTES[("POST", "/deadwax/library/disc_art/fetch")] == "edit"
    assert ROUTES[("GET", "/deadwax/library/disc_art")] == "user"
    sheet = (CORE.parent.parent.parent / "App" / "Edit" / "EditAlbumSheet.swift").read_text(encoding="utf-8")
    editors = sheet.index("if edit.editors, let retag = model.retag {")
    assert editors < sheet.index("NavigationLink(value: EditPage.artwork)") < sheet.index("if edit.delete")
    assert editors < sheet.index("NavigationLink(value: EditPage.lyrics)") < sheet.index("if edit.delete")


# ---------------------------------------------------------------------------- Delete album (slice 4)

def test_the_delete_body_is_the_servers_model_and_the_summary_is_asked_for_the_folder():
    assert sends("DeleteAlbumBody") == {"album_path"} <= set(library_route.DeleteRequest.model_fields)
    assert "DeleteAlbumBody(albumPath: path)" in swift_function("EditClient.swift", "deleteAlbum")
    # the dialog's read: the folder by its path, the route's one query name
    assert '[("album", path)]' in swift_function("EditClient.swift", "deletionSummary")
    assert "album" in inspect.signature(library_route.deletion_summary).parameters


def test_the_summary_is_what_the_phone_reads_and_names_what_the_scan_ignores(client):
    root = Path(Config.LIBRARY_PATH)
    (root / ALBUM / "rip.log").write_text("Exact Audio Copy", encoding="utf-8")
    answer = client.get("/deadwax/library/deletion_summary", params={"album": ALBUM})
    assert answer.status_code == 200, answer.text
    summary = answer.json()
    fields = reads("DeletionSummary")
    # logins off: what goes, and nobody to name (holdersText's null - nothing drawn)
    assert {"audio_files", "total_bytes", "other_files", "other_file_count"} <= set(summary) <= fields, set(summary) - fields
    assert summary["audio_files"] == len(FILES) and summary["total_bytes"] > 0
    assert "rip.log" in summary["other_files"] and summary["other_file_count"] >= 1
    # logins on: who holds it, or that deadwax couldn't read who does - the route's own keys, each one the phone reads
    source = inspect.getsource(library_route.deletion_summary)
    for key in ("holders_unknown", "yours", "holders"):
        assert f'summary["{key}"]' in source and key in fields, key
    # a folder that isn't the library's: refused with its words (the page's read failure, Look again)
    refused = client.get("/deadwax/library/deletion_summary", params={"album": "../.."})
    assert refused.status_code == 400 and refused.json()["detail"] == "that album is not inside the library"


def test_a_delete_answers_what_the_phone_reads_and_the_next_read_no_longer_lists_it(client):
    root = Path(Config.LIBRARY_PATH)
    assert scanned(client)["path"] == ALBUM
    answer = client.post("/deadwax/library/delete", json={"album_path": ALBUM})
    assert answer.status_code == 200, answer.text
    assert reads("AlbumDeleted") <= set(answer.json()) and answer.json()["deleted"] is True
    assert not (root / ALBUM).exists()
    # what settles a delete that never answered (DeleteFlow.went): the scan, read again, no longer lists it
    albums = client.get("/deadwax/library/albums", params={"tracks": "false"}).json()
    assert not albums.get("problem") and ALBUM not in [album["path"] for album in albums["albums"]]
    # a second Delete is refused with its words, nothing deleted - a refusal, said under the button
    again = client.post("/deadwax/library/delete", json={"album_path": ALBUM})
    assert again.status_code == 400 and again.json()["detail"] == "that folder is not there any more"
    outside = client.post("/deadwax/library/delete", json={"album_path": "../.."})
    assert outside.status_code == 400 and outside.json()["detail"] == "that album is not inside the library"


def test_a_folder_without_audio_is_refused_and_kept(client):
    root = Path(Config.LIBRARY_PATH)
    artist = ALBUM.split("/")[0]
    answer = client.post("/deadwax/library/delete", json={"album_path": artist})
    assert answer.status_code == 400 and answer.json()["detail"] == "that folder holds no audio, so it isn't an album"
    assert (root / ALBUM).is_dir()


def test_delete_is_waited_for_past_its_worst_case():
    # the summary walks the folder once (no network); the delete walks it again, removes it, saves the scan and writes
    # the store index - nothing on the network, no pause, no lock: as long as a folder's read, with margin
    wait = timeouts()
    assert wait["deletionSummary"] >= wait["libraryTracks"]
    assert wait["deleteAlbum"] >= 2 * wait["deletionSummary"]
    for route in (library_route.delete, library_route.deletion_summary):
        source = inspect.getsource(route)
        for slow in ("_pause_before_rename", "coverart_client", "_wait_for_navidrome_scan", "_album_lock", "lrclib"):
            assert slow not in source, (route.__name__, slow)


def test_delete_is_asked_with_the_permission_the_root_shows_it_for():
    # Look after the library's (Managing.albumEdit's `delete`), as both routes are; the row is under its gate alone,
    # never under Edit albums'
    from tests.test_logins import ROUTES
    assert ROUTES[("POST", "/deadwax/library/delete")] == "library"
    assert ROUTES[("GET", "/deadwax/library/deletion_summary")] == "library"
    sheet = (CORE.parent.parent.parent / "App" / "Edit" / "EditAlbumSheet.swift").read_text(encoding="utf-8")
    gate = sheet.index("if edit.delete {")
    assert gate < sheet.index("NavigationLink(value: EditPage.delete)")
    assert sheet.index("NavigationLink(value: EditPage.lyrics)") < gate
