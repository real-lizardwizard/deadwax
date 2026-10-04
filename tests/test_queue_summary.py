"""
GET /deadwax/library/queue/summary - the app's count beside "Needs a look" (2.0.0-player.25).

- `total` is what the app's queue page lists over the same saved scan: an album with an outstanding
  issue, or one deadwax filed and nobody has looked at yet - the rule ui/src/lib/metadataQueue.ts's
  queueAlbums(albums, null) applies (`queue_lists` below is that rule, read off the payload
  /albums?snapshot=true gives the page), so the badge and the page count the same albums BY
  CONSTRUCTION. Ignores count per issue, a reviewed import no longer counts, a clean new import does.
- It NEVER walks the disk: from the saved scan, or - with none - the new imports alone (`known`
  false), never a real scan in its place. An import filed since the last scan (the scan cache
  doesn't hold its folder yet) is counted too, as the page lists it once it has scanned.
- No LIBRARY_PATH, or no store: zeros, `known` false, a 200.

Through the whole app start() builds (no lifespan, so nothing connects), with a real SQLite store.
"""

import asyncio

import pytest
from fastapi.testclient import TestClient
from mutagen.flac import FLAC

from src import library
from src.api.app import start
from src.config import Config
from src.routes import library as route
from src.store import JobStore

SUMMARY = "/deadwax/library/queue/summary"
ALBUMS = "/deadwax/library/albums"

STREAMINFO = (
    b"fLaC" + b"\x80\x00\x00\x22"
    + b"\x10\x00\x10\x00\x00\x00\x00\x00\x00\x00\x0a\xc4\x42\xf0\x00\x00\x00\x00" + b"\x00" * 16
)

CLEAN = "Portishead/Dummy (1994)"
UNTAGGED = "Old Rips/Third rip"


def run(awaitable):
    return asyncio.run(awaitable)


def write_flac(path, **tags):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(STREAMINFO)
    audio = FLAC(str(path))
    for key, value in tags.items():
        audio[key] = str(value)
    audio.save()


def clean_album(root, folder=CLEAN, release="11111111-1111-4111-8111-111111111111"):
    """An album with nothing wrong with it: tagged with its release, dated, named as filed, a cover."""
    artist, name = folder.split("/")
    album, year = name[:-1].split(" (")
    directory = root / artist / name
    for n in (1, 2):
        write_flac(directory / f"{n:02d} - Track {n}.flac", album=album, albumartist=artist, artist=artist,
                   title=f"Track {n}", tracknumber=str(n), date=year, originaldate=year,
                   musicbrainz_albumid=release)
    (directory / "cover.jpg").write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 16)
    return directory


def untagged_album(root, folder=UNTAGGED):
    """A stranger's rip: no release, no dates, no cover - several issues at once."""
    directory = root.joinpath(*folder.split("/"))
    for n in (1, 2):
        write_flac(directory / f"{n:02d}.flac", title=f"Track {n}", artist="Portishead", tracknumber=str(n))
    return directory


@pytest.fixture(autouse=True)
def fresh_cache():
    library.clear_scan_cache()
    route._cache_loaded_for = None
    yield
    library.clear_scan_cache()
    route._cache_loaded_for = None


@pytest.fixture
def store(tmp_path):
    job_store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    job_store.init()
    return job_store


@pytest.fixture
def root(tmp_path, monkeypatch):
    music = tmp_path / "music"
    music.mkdir()
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(music))
    return music


def client(store):
    app = start()
    app.state.store = store
    return TestClient(app)


def queue_lists(album: dict) -> bool:
    """metadataQueue.ts queueAlbums(albums, null)'s rule: an outstanding issue, or a new import."""
    return album["needs_attention"] or (album["imported"] and not album["reviewed"])


def snapshot_albums(app_client) -> list[dict]:
    response = app_client.get(ALBUMS, params={"snapshot": "true"})
    assert response.headers["x-scan-stale"] == "1"
    return response.json()["albums"]


def test_the_clean_album_is_clean_and_the_rip_is_not(root, store):
    """The library the rest is built on: one album with nothing to say, one with plenty."""
    clean_album(root)
    untagged_album(root)
    app = client(store)
    scanned = {album["path"]: album for album in app.get(ALBUMS).json()["albums"]}
    assert scanned[CLEAN]["issues"] == []
    assert len(scanned[UNTAGGED]["issues"]) > 1


def test_it_counts_the_albums_with_something_outstanding(root, store):
    clean_album(root)
    untagged_album(root)
    app = client(store)
    app.get(ALBUMS)

    answer = app.get(SUMMARY).json()

    assert answer == {"known": True, "needs_attention": 1, "new_imports": 0, "total": 1,
                      "unscanned_imports": 0, "tracking_enabled": True}


def test_ignores_count_per_issue(root, store):
    untagged_album(root)
    app = client(store)
    issues = app.get(ALBUMS).json()["albums"][0]["issues"]

    run(store.ignore_album_issues(UNTAGGED, issues[:1]))
    assert app.get(SUMMARY).json()["total"] == 1

    run(store.ignore_album_issues(UNTAGGED, issues))
    assert app.get(SUMMARY).json()["total"] == 0


def test_a_clean_new_import_counts_until_it_has_been_looked_at(root, store):
    clean_album(root)
    #? filed by the poller, which writes its import row as it files - before any scan has seen it
    run(store.record_albums_seen([{"path": CLEAN, "artist": "Portishead", "album": "Dummy"}], source="import"))
    app = client(store)
    app.get(ALBUMS)

    assert app.get(SUMMARY).json()["total"] == 1
    assert app.get(SUMMARY).json()["new_imports"] == 1

    run(store.mark_album_reviewed(CLEAN))
    assert app.get(SUMMARY).json()["total"] == 0


def test_the_badge_and_the_page_count_the_same_albums(root, store):
    """Run over one library: the summary's total is the number the page's queueAlbums lists."""
    clean_album(root)
    clean_album(root, "Portishead/Portishead (1997)", "22222222-2222-4222-8222-222222222222")
    clean_album(root, "Tame Impala/Currents (2015)", "33333333-3333-4333-8333-333333333333")
    untagged_album(root)
    untagged_album(root, "Old Rips/Dummy rip")
    run(store.record_albums_seen([{"path": "Portishead/Portishead (1997)"}, {"path": "Old Rips/Dummy rip"}], source="import"))
    app = client(store)
    app.get(ALBUMS)
    run(store.mark_album_reviewed("Old Rips/Dummy rip"))
    issues = {album["path"]: album["issues"] for album in app.get(ALBUMS).json()["albums"]}
    run(store.ignore_album_issues(UNTAGGED, issues[UNTAGGED]))

    albums = snapshot_albums(app)
    answer = app.get(SUMMARY).json()

    listed = [album["path"] for album in albums if queue_lists(album)]
    assert sorted(listed) == ["Old Rips/Dummy rip", "Portishead/Portishead (1997)"]
    assert answer["total"] == len(listed)
    assert answer["needs_attention"] == sum(1 for album in albums if album["needs_attention"])
    assert answer["new_imports"] == sum(1 for album in albums if album["imported"] and not album["reviewed"])


def test_with_no_saved_scan_it_counts_the_new_imports_and_never_walks_the_disk(root, store, monkeypatch):
    clean_album(root)
    run(store.record_albums_seen([{"path": CLEAN}], source="import"))

    def boom(*_args, **_kwargs):
        raise AssertionError("the summary walked the disk")

    monkeypatch.setattr(route, "scan_library", boom)
    monkeypatch.setattr(library, "scan_library", boom)
    monkeypatch.setattr(library, "_walk", boom)

    answer = client(store).get(SUMMARY).json()

    assert answer["known"] is False
    assert (answer["total"], answer["new_imports"]) == (1, 1)


def test_with_a_saved_scan_it_reads_that_and_never_the_disk(root, store, monkeypatch):
    clean_album(root)
    directory = untagged_album(root)
    app = client(store)
    app.get(ALBUMS)

    def boom(*_args, **_kwargs):
        raise AssertionError("the summary walked the disk")

    monkeypatch.setattr(route, "scan_library", boom)
    monkeypatch.setattr(library, "_walk", boom)
    #? and it is the saved scan it reads: the rip deleted behind its back still counts until a scan
    for entry in directory.iterdir():
        entry.unlink()
    directory.rmdir()

    assert app.get(SUMMARY).json()["total"] == 1


def test_after_a_restart_the_saved_scan_comes_from_the_database(root, store):
    untagged_album(root)
    client(store).get(ALBUMS)
    library.clear_scan_cache()
    route._cache_loaded_for = None  # the restart

    answer = client(store).get(SUMMARY).json()

    assert (answer["known"], answer["total"]) == (True, 1)


def test_an_import_filed_since_the_last_scan_is_counted(root, store):
    clean_album(root)
    app = client(store)
    app.get(ALBUMS)
    run(store.record_albums_seen([{"path": "Someone/Just Filed (2024)"}], source="import"))
    run(store.record_albums_seen([{"path": "Someone/Seen Already (2024)"}], source="import"))
    run(store.mark_album_reviewed("Someone/Seen Already (2024)"))
    #? and a row the scan merely found is no import, whatever the snapshot holds
    run(store.record_albums_seen([{"path": "Someone/Found (2024)"}], source="scan"))

    answer = app.get(SUMMARY).json()

    assert (answer["total"], answer["unscanned_imports"], answer["new_imports"]) == (1, 1, 1)


def test_no_library_and_no_store_answer_zeros(root, store, monkeypatch):
    untagged_album(root)
    zeros = {"known": False, "needs_attention": 0, "new_imports": 0, "total": 0, "unscanned_imports": 0}

    no_store = start()
    no_store.state.store = None
    answer = TestClient(no_store).get(SUMMARY)
    assert answer.status_code == 200
    assert answer.json() == {**zeros, "tracking_enabled": False}

    monkeypatch.setattr(Config, "LIBRARY_PATH", "")
    answer = client(store).get(SUMMARY)
    assert answer.status_code == 200
    assert answer.json() == {**zeros, "tracking_enabled": True}
