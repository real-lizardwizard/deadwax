"""
The iPhone app's Edit album (Phase 8, slice 1 - notes/ios-specs/phase8-managing.md 3.1-3.3, 14; notes/ios.md "Edit album
on the phone") against the nine routes it asks, read from its own source (ios/DeadwaxKit/Sources/DeadwaxCore: Retag.swift,
ScanAlbums.swift, EditClient.swift, Routes.swift) and held to the server's:

- what it SENDS - RetagRequestBody and RetagRelease, CoverFetchBody, QueueMarkBody - every key one the model it is posted
  to declares (pydantic drops an undeclared one without a word), and every payload the vectors hold (the web's own
  buildRetagRelease, Fixtures/edit/edit-vectors.json) taken by the real preview route;
- what it READS - ScanAnswer and ScanAlbum from the real scan asked as the phone asks it (`?tracks=false`, no tracks),
  RetagPlan, RetagFileChange and RetagArtPlan from the real preview, RetagResponse and RetagResults from a real apply,
  CoverFetched from the art route's own answer, QueueMarked from the two real marks - every field it reads one the
  server sends;
- how long it waits - the apply held past the longest pause before a rename plus a cover's fetch, the cover alone past
  two fetches (the full size's fallback), the scan (no bound of its own) longer than a folder's read, the pressings'
  asks at least what Phase 6 gives MusicBrainz;
- and that its writes, sent with no Origin or Referer, are what the same-origin guard lets through.
"""

import inspect
import json
import re
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import library  # noqa: E402
from src import retag as retag_module  # noqa: E402
from src.api import same_origin  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.coverart_endpoint import CoverArtClient  # noqa: E402
from src.config import RENAME_WAIT_RANGE, Config  # noqa: E402
from src.routes import library as library_route  # noqa: E402
from src.scan_wait import SCAN_WAIT_CAP_SECONDS  # noqa: E402
from src.store import JobStore  # noqa: E402
from tests.test_ios_contract import CORE, coding_keys, returned_keys, swift_function, swift_struct  # noqa: E402
from tests.test_retag import RELEASE, seed  # noqa: E402

ALBUM = "Tame Impala/The Slow Rush (2020)"
VECTORS = CORE.parent.parent / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "edit" / "edit-vectors.json"


def reads(struct: str) -> set[str]:
    """Every JSON name a Decodable struct reads: its CodingKeys (each of these models reads every key it names)."""
    keys = coding_keys(swift_struct(struct))
    assert keys is not None, f"{struct} has no CodingKeys"
    return set(keys.values())


def sends(struct: str) -> set[str]:
    """Every key an Encodable struct can send: the keys its CodingKeys name (its encode(to:) writes no other)."""
    return reads(struct)


def timeouts() -> dict[str, float]:
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    literal = re.search(r"public static let timeouts: \[Endpoint: Double\] = \[([^\]]*)\]", text)
    return {name: float(seconds) for name, seconds in re.findall(r"(\w+): ([\d.]+)", literal.group(1))}


@pytest.fixture(autouse=True)
def nothing_left_over(monkeypatch):
    """The scan's caches emptied, Navidrome not set up, no rename held and no album's lock taken - all of it lives in
    the process, not the request."""
    library.clear_scan_cache()
    monkeypatch.setattr(library_route, "_cache_loaded_for", None)
    monkeypatch.setattr(library_route, "_HELD_RENAMES", {})
    monkeypatch.setattr(library_route, "_APPLY_LOCKS", {})
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", "0")
    yield
    library.clear_scan_cache()


@pytest.fixture
def client(monkeypatch, tmp_path):
    root = tmp_path / "music"
    root.mkdir()
    seed(root)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(root))
    store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    store.init()
    app = start()
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    app.state.store = store
    return TestClient(app)


# ---------------------------------------------------------------------------- what the phone sends

def test_every_body_the_phone_posts_is_the_servers_model():
    assert sends("RetagRequestBody") == {"album_path", "release", "fetch_art"} <= set(library_route.RetagRequest.model_fields)
    release = sends("RetagRelease")
    assert release <= set(library_route.RetagRelease.model_fields), release - set(library_route.RetagRelease.model_fields)
    # the editor sends no album artist: its artist field IS the album artist (the server's own note on the model)
    assert "album_artist" not in release
    assert sends("CoverFetchBody") == {"album_path", "replace", "release_mbid"} <= set(library_route.CoverArtRequest.model_fields)
    assert sends("QueueMarkBody") == {"album_path", "issues"} <= set(library_route.QueueRequest.model_fields)
    # an unignore sends no issues, which the model defaults to none
    assert library_route.QueueRequest(album_path="A/B").issues == []


def test_every_payload_the_vectors_hold_is_taken_by_the_real_preview(client):
    # the payloads RetagModelTests and EditVectorTests hold the phone's to are the web's buildRetagRelease's own - each
    # posted to the real route over a real folder, as the phone posts it, answered with a plan (never a 422)
    payloads = json.loads(VECTORS.read_text(encoding="utf-8"))["payloads"]
    assert len(payloads) >= 100
    declared = set(library_route.RetagRelease.model_fields)
    for case in payloads:
        payload = case["payload"]
        assert set(payload) <= declared, set(payload) - declared
        answer = client.post("/deadwax/library/retag/preview",
                             json={"album_path": ALBUM, "release": payload, "fetch_art": False})
        assert answer.status_code == 200, answer.text
        assert answer.json()["album_path"] == ALBUM


def test_the_writes_pass_the_same_origin_guard():
    # the phone's writes carry no Origin and no Referer - not a browser acting for a page, so let through - and the
    # client sets neither (DeadwaxClient's headers are the cookie, the content type, Accept and If-None-Match)
    assert same_origin.refusal("POST", {"content-type": "application/json"}) is None
    for file in ("DeadwaxClient.swift", "EditClient.swift"):
        text = (CORE / file).read_text(encoding="utf-8")
        assert '"Origin"' not in text and '"Referer"' not in text, file


# ---------------------------------------------------------------------------- what the phone reads

def test_the_scan_is_asked_without_its_tracks_and_holds_what_the_phone_reads(client):
    body = swift_function("EditClient.swift", "libraryScan")
    assert 'request(Routes.libraryAlbums, query: [("tracks", "false")])' in body
    answer = client.get("/deadwax/library/albums", params={"tracks": "false"})
    assert answer.status_code == 200, answer.text
    scan = answer.json()
    assert reads("ScanAnswer") <= set(scan), reads("ScanAnswer") - set(scan)
    [album] = scan["albums"]
    assert album["path"] == ALBUM
    assert reads("ScanAlbum") <= set(album), reads("ScanAlbum") - set(album)
    assert "tracks" not in album and "track_defaults" not in album
    for kind, words in scan["issue_types"].items():
        assert reads("MetadataIssueType") <= set(words), kind
    # the headers the phone reads off it (stale, when it was read) are the ones the route lays on
    assert {"X-Scanned-At", "X-Scan-Stale"} <= set(library_route._SCAN_HEADERS.values())
    scan_text = (CORE / "ScanAlbums.swift").read_text(encoding="utf-8") + (CORE / "EditClient.swift").read_text(encoding="utf-8")
    assert '"X-Scanned-At"' in scan_text and '"X-Scan-Stale"' in scan_text
    # and the ETag the phone sends back is answered: a 304 when nothing changed (asked once more first - the first scan
    # of a folder enrols it for review, which the next answer says)
    settled = client.get("/deadwax/library/albums", params={"tracks": "false"})
    again = client.get("/deadwax/library/albums", params={"tracks": "false"},
                       headers={"If-None-Match": settled.headers["ETag"]})
    assert again.status_code == 304, (answer.json() == settled.json())


def test_the_preview_holds_what_the_phone_reads(client):
    answer = client.post("/deadwax/library/retag/preview",
                         json={"album_path": ALBUM, "release": RELEASE, "fetch_art": True})
    assert answer.status_code == 200, answer.text
    plan = answer.json()
    assert reads("RetagPlan") <= set(plan), reads("RetagPlan") - set(plan)
    assert plan["files"] and plan["moves"]
    for file in plan["files"]:
        assert reads("RetagFileChange") <= set(file), reads("RetagFileChange") - set(file)
        for tag, change in file["changes"].items():
            assert reads("TagChange") == set(change), tag
    assert reads("RetagArtPlan") <= set(plan["art"]), reads("RetagArtPlan") - set(plan["art"])
    # a merge's detail, named as plan_retag names it
    source = inspect.getsource(retag_module)
    for key in reads("RetagMerge"):
        assert f'"{key}":' in source, key
    # the filename is the one field a file can't do without: it is decoded strictly
    assert "filename = try fields.decode(String.self, forKey: .filename)" in swift_struct("RetagFileChange")


def test_an_apply_answers_what_the_phone_reads(client):
    answer = client.post("/deadwax/library/retag/apply",
                         json={"album_path": ALBUM, "release": RELEASE, "fetch_art": False})
    assert answer.status_code == 200, answer.text
    body = answer.json()
    assert reads("RetagResponse") == set(body)
    # the plan worked out again - without the pause's words, which only the preview lays on (the phone reads them
    # there, and of the apply's plan only where the folder went)
    assert reads("RetagPlan") - {"rename_wait", "rename_by"} <= set(body["plan"])
    assert {"rename_wait", "rename_by"} <= set(body["results"])
    results = body["results"]
    # every result the phone reads is one the apply sends - `merged` only by a merge, and read as false without it
    sent = set(results) | {"merged"}
    assert reads("RetagResults") <= sent, reads("RetagResults") - sent
    assert '"merged"' in inspect.getsource(retag_module)
    # the folder moved: the phone follows it by the plan's target (RetagResponse.pathAfter)
    assert results["moved_to"] and body["plan"]["target_path"]
    assert "results = try fields.decode(RetagResults.self, forKey: .results)" in swift_struct("RetagResponse")


def test_the_cover_alone_answers_what_the_phone_reads():
    assert reads("CoverFetched") <= returned_keys(library_route.fetch_cover_art)


def test_the_marks_answer_what_the_phone_reads(client):
    fine = client.post("/deadwax/library/queue/ignore", json={"album_path": ALBUM, "issues": ["no_mbid"]})
    assert fine.status_code == 200, fine.text
    assert reads("QueueMarked") <= set(fine.json()) and fine.json()["ignored"] is True
    # Ask about it again sends no issues at all
    again = client.post("/deadwax/library/queue/unignore", json={"album_path": ALBUM})
    assert again.status_code == 200, again.text
    assert reads("QueueMarked") <= set(again.json()) and again.json()["ignored"] is False


# ---------------------------------------------------------------------------- how long the phone waits

def _cover_fetch_seconds() -> float:
    """One cover fetch's longest silence: its connection, then the longest wait for the next chunk."""
    source = inspect.getsource(CoverArtClient.get_client)
    connect = float(re.search(r"connect=([\d.]+)", source).group(1))
    read = float(re.search(r"read=([\d.]+)", source).group(1))
    return connect + read


def test_the_apply_is_waited_for_past_its_longest_pause_and_a_cover():
    # an apply that moves the folder and changes an id pauses before the rename - RETAG_RENAME_WAIT (up to 300 s) or
    # until Navidrome has scanned (up to SCAN_WAIT_CAP_SECONDS) - and may fetch the cover first; the phone holds its
    # answer longer than both, and one that never comes is said as "may have finished" (RetagWords.mayHaveFinished)
    wait = timeouts()
    source = inspect.getsource(library_route._retag_apply)
    assert "coverart_client.fetch_front(" in source and "_pause_before_rename(" in source
    longest_pause = max(RENAME_WAIT_RANGE[1], SCAN_WAIT_CAP_SECONDS)
    assert wait["retagApply"] > longest_pause + _cover_fetch_seconds()
    # the cover alone: one fetch, and the full size's 1200 px fallback after it
    assert "FULL_SIZE_FALLBACK" in inspect.getsource(CoverArtClient.fetch_front_why)
    assert wait["artFetch"] > 2 * _cover_fetch_seconds()
    # the preview reads the folder's files, as the album info's tracks do
    assert wait["retagPreview"] >= wait["libraryTracks"]
    # a whole scan (a first walk of the library on a disk that has to spin up) has no bound of its own
    albums = inspect.getsource(library_route.albums)
    assert "wait_for" not in albums and "timeout" not in albums
    assert wait["libraryAlbums"] > wait["libraryTracks"]


def test_the_pressings_are_waited_for_as_long_as_phase_6_waits_for_musicbrainz():
    wait = timeouts()
    assert wait["releases"] >= wait["releaseGroup"] and wait["release"] >= wait["releaseGroup"]
    # the editor's search asks without `quick` (MusicBrainz's ten attempts, as the web's editor asks): longer than Get's
    routes = (CORE / "Routes.swift").read_text(encoding="utf-8")
    editor = float(re.search(r"public static let editorSearchTimeout: Double = ([\d.]+)\n", routes).group(1))
    assert editor >= wait["releaseGroup"] > wait["fullySearch"]
    search = swift_function("EditClient.swift", "editorSearch")
    assert "built.timeout = Routes.editorSearchTimeout" in search and '"quick"' not in search
