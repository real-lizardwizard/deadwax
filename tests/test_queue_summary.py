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


# ---------------------------------------------------------------- the count, kept (2.1.48)

def count_inspections(monkeypatch):
    """Counts every working-out of the count, and notes whether any ran on the event loop."""
    real = route._count_queue
    seen = {"counts": 0, "on_the_loop": 0}

    def counted(albums, reviews, unlisted):
        seen["counts"] += 1
        try:
            asyncio.get_running_loop()
            seen["on_the_loop"] += 1
        except RuntimeError:
            pass
        return real(albums, reviews, unlisted)

    monkeypatch.setattr(route, "_count_queue", counted)
    return seen


def test_the_count_is_kept_while_nothing_it_counts_has_changed(root, store, monkeypatch):
    clean_album(root)
    untagged_album(root)
    app = client(store)
    app.get(ALBUMS)
    seen = count_inspections(monkeypatch)

    first = app.get(SUMMARY).json()
    assert seen == {"counts": 1, "on_the_loop": 0}, "worked out once, in a worker thread"

    #? asked again - and the saved scan isn't even put together for it
    monkeypatch.setattr(route, "snapshot_library", lambda *_: (_ for _ in ()).throw(AssertionError("assembled again")))
    assert app.get(SUMMARY).json() == first
    assert app.get(SUMMARY).json() == first
    assert seen["counts"] == 1


def test_a_review_written_is_counted_at_the_next_ask(root, store, monkeypatch):
    """The review rows are read on every ask and compared by value: no writer has to say it wrote."""
    untagged_album(root)
    app = client(store)
    issues = app.get(ALBUMS).json()["albums"][0]["issues"]
    seen = count_inspections(monkeypatch)
    assert app.get(SUMMARY).json()["total"] == 1

    run(store.ignore_album_issues(UNTAGGED, issues))
    assert app.get(SUMMARY).json()["total"] == 0
    run(store.record_albums_seen([{"path": "Someone/Just Filed (2024)"}], source="import"))
    assert app.get(SUMMARY).json()["total"] == 1, "an import filed since the scan, though no folder was read"
    assert seen["counts"] == 3


def test_a_folder_changed_is_counted_at_the_next_ask(root, store, monkeypatch):
    clean_album(root)
    directory = untagged_album(root)
    app = client(store)
    app.get(ALBUMS)
    seen = count_inspections(monkeypatch)
    assert app.get(SUMMARY).json()["total"] == 1

    #? a writer forgets the folder it wrote (a retag moves no mtime): the saved scan is another one
    library.forget_cached_album(str(directory))
    assert app.get(SUMMARY).json()["total"] == 0
    #? and the scan that reads it again is another still
    app.get(ALBUMS)
    assert app.get(SUMMARY).json()["total"] == 1
    assert seen["counts"] == 3


def test_a_setting_an_issue_is_judged_by_is_counted_at_the_next_ask(root, store, monkeypatch):
    clean_album(root)
    app = client(store)
    app.get(ALBUMS)
    seen = count_inspections(monkeypatch)
    assert app.get(SUMMARY).json()["total"] == 0

    #? every folder is misfiled by another template's lights
    monkeypatch.setattr(Config, "ALBUM_FOLDER_TEMPLATE", "{year} - {album}")
    assert app.get(SUMMARY).json()["total"] == 1
    assert seen["counts"] == 2


def test_the_settings_an_issue_reads_are_the_ones_the_count_is_kept_by(monkeypatch):
    from src.metadata_health import settings_read

    before = settings_read()
    monkeypatch.setattr(Config, "ALBUM_FOLDER_TEMPLATE", "{year} - {album}")
    templated = settings_read()
    monkeypatch.setattr(Config, "COUNTRY_IN_FOLDER", "on")
    assert len({before, templated, settings_read()}) == 3


# ---------------------------------------------------------------- after review (2.1.53)

def test_a_count_is_never_answered_from_what_is_kept_while_the_scan_cache_is_being_changed(root, store, monkeypatch):
    """The lookup reads the scan cache's generation, which is none while a change is under way: nothing kept can
    be the answer to that."""
    untagged_album(root)
    app = client(store)
    app.get(ALBUMS)
    seen = count_inspections(monkeypatch)
    assert app.get(SUMMARY).json()["total"] == 1 and seen["counts"] == 1
    assert app.get(SUMMARY).json()["total"] == 1 and seen["counts"] == 1, "kept"

    with library._changing():
        assert app.get(SUMMARY).json()["total"] == 1
    assert seen["counts"] == 2, "worked out afresh, mid-change"
    kept_before = route._kept_summary
    assert kept_before is not None and kept_before[0][1] != library.generation(), "and what was worked out mid-change was not kept"


def test_with_no_saved_scan_navidrome_is_not_asked_and_nothing_waits_for_it(root, store, monkeypatch):
    """Until 2.1.48 the imports-only count was returned before anything else was asked; 2.1.48 read the reviews and
    asked Navidrome first, so on a fresh install with a slow Navidrome the badge waited for an answer it never
    needed."""
    clean_album(root)
    run(store.record_albums_seen([{"path": CLEAN}], source="import"))
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")

    async def asked(*_args, **_kwargs):
        raise AssertionError("Navidrome was asked for a count that has no album to judge")

    async def read(*_args, **_kwargs):
        raise AssertionError("the review rows were read for a count that is the new imports alone")

    monkeypatch.setattr(route.navidrome_listing, "ask", asked)
    monkeypatch.setattr(store, "album_reviews", read)

    answer = client(store).get(SUMMARY).json()

    assert (answer["known"], answer["total"], answer["new_imports"], answer["unscanned_imports"]) == (False, 1, 1, 1)


def test_holds_albums_says_whether_there_is_a_saved_scan_of_this_library(root, tmp_path):
    assert library.holds_albums(str(root)) is False and library.holds_albums("") is False
    untagged_album(root)
    library.scan_library(str(root))
    assert library.holds_albums(str(root)) is True
    assert library.holds_albums(str(tmp_path / "elsewhere")) is False, "another library's albums are not this one's"
