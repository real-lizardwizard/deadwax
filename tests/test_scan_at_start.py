"""
The library walked once as deadwax starts, when the store index has never been filled from a scan of LIBRARY_PATH
(2.0.0-player.65, the 2.0.0 release review).

2.0.0's SCAN_FORMAT is newer than 1.1.8's, so an upgrade seeds nothing from the saved scan (seed_from_saved_scan reads
only its own format): until something scanned, album pages couldn't offer Add, Find couldn't see the library, and the
first admin's library waited. What these hold:

  - an index never filled from a scan of the root (store_index_scanned): the library is walked, through the same
    machinery as every scan - the index filled and the root recorded as scanned;
  - one already filled from a scan: nothing is walked;
  - no LIBRARY_PATH, or no database: nothing is walked, nothing raises;
  - the lifespan starts it in the background (and the Library's Shuffle's sweep beside it), and cancels both as it
    ends.
"""

import asyncio

import pytest

from src import library
from src.config import Config
from src.routes import library as route
from src.store import JobStore
from tests.test_library_cache import seed_album


def run(coroutine):
    return asyncio.run(coroutine)


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


def test_an_index_never_filled_from_a_scan_is_filled_at_start_up(tmp_path, store, monkeypatch):
    root = tmp_path / "music"
    seed_album(root)
    seed_album(root, artist="Portishead", folder="Dummy (1994)", album="Dummy")
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(root))
    assert not run(store.index_scanned(str(root))) and run(store.index_count(str(root))) == 0

    run(route.scan_at_start(store))

    assert run(store.index_scanned(str(root)))
    assert run(store.index_count(str(root))) == 2


def test_a_library_path_changed_while_the_walk_ran_saves_nothing_under_the_new_one(tmp_path, store, monkeypatch):
    """(the 2.0.0-player.65 review) The walk of a big library takes minutes, and it begins unasked after an upgrade.
    LIBRARY_PATH saved in the settings tab meanwhile: the old root's albums were saved under the new root - its index
    the old library's paths, and the new root counted as scanned, so it was never walked at start-up."""
    old, new = tmp_path / "music", tmp_path / "elsewhere"
    seed_album(old)
    seed_album(new, artist="Portishead", folder="Dummy (1994)", album="Dummy")
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(old))
    real = route.scan_library

    def walk_then_moved(root, force):
        result = real(root, force)
        Config.LIBRARY_PATH = str(new)
        library.clear_scan_cache()
        return result

    monkeypatch.setattr(route, "scan_library", walk_then_moved)
    run(route.scan_at_start(store))

    assert not run(store.index_scanned(str(new))) and run(store.index_count(str(new))) == 0
    assert run(store.library_scan_info(str(new))) is None
    monkeypatch.setattr(route, "scan_library", real)
    run(route.scan_at_start(store))
    assert run(store.index_scanned(str(new))) and run(store.index_count(str(new))) == 1


def test_an_index_already_filled_from_a_scan_is_not_walked_again(tmp_path, store, monkeypatch):
    root = tmp_path / "music"
    seed_album(root)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(root))
    run(route.scan_at_start(store))

    walked = []
    monkeypatch.setattr(route, "scan_library", lambda *args: walked.append(args))
    run(route.scan_at_start(store))

    assert walked == []


@pytest.mark.parametrize("missing", ["path", "database"])
def test_without_a_library_path_or_a_database_nothing_is_walked(tmp_path, store, monkeypatch, missing):
    root = tmp_path / "music"
    seed_album(root)
    monkeypatch.setattr(Config, "LIBRARY_PATH", "" if missing == "path" else str(root))
    if missing == "database":
        store.available = False
    walked = []
    monkeypatch.setattr(route, "scan_library", lambda *args: walked.append(args))

    run(route.scan_at_start(store))
    run(route.scan_at_start(None))

    assert walked == []


def test_a_scan_that_fails_at_start_up_is_said_and_never_raises(tmp_path, store, monkeypatch, caplog):
    import logging
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))

    def fails(*_args):
        raise OSError("the array is spun down")

    monkeypatch.setattr(route, "scan_library", fails)
    with caplog.at_level(logging.ERROR):
        run(route.scan_at_start(store))
    assert any("the scan at start-up failed" in record.getMessage() for record in caplog.records)
    assert not run(store.index_scanned(str(tmp_path / "music")))


def test_the_lifespan_starts_the_scan_and_the_shuffle_sweep_in_the_background_and_stops_them(monkeypatch, tmp_path):
    """Neither is awaited before the app serves (a big library takes minutes), and both are cancelled as it ends."""
    from src import auth
    from src.api import app as app_module
    from src.api.app import start
    from src.routes import navidrome as navidrome_routes

    began, ended = [], []

    def background(name):
        async def task(*_args, **_kwargs):
            began.append(name)
            try:
                await asyncio.Event().wait()
            except asyncio.CancelledError:
                ended.append(name)
                raise
        return task

    class Client:
        async def stop_refreshing(self):
            return None

        async def close_client(self):
            return None

    class File:
        def enabled(self):
            return False

        async def close(self):
            return None

    async def nothing(*_args):
        return None

    from src.api.musicbrainz_endpoint import ResponseCache
    Client.cache = ResponseCache()
    monkeypatch.setattr(app_module, "MusicBrainzClient", Client)
    monkeypatch.setattr(app_module, "SlskdClient", Client)
    monkeypatch.setattr(app_module, "saved_answers", File())
    monkeypatch.setattr(app_module, "JobStore", lambda: JobStore(str(tmp_path / "deadwax.db")))
    monkeypatch.setattr(app_module, "seed_from_saved_scan", nothing)
    monkeypatch.setattr(app_module, "run_download_poller", background("poller"))
    monkeypatch.setattr(app_module, "cleanup_logging", lambda: None)
    monkeypatch.setattr(route, "scan_at_start", background("scan"))
    monkeypatch.setattr(navidrome_routes, "run_shuffle_sweeps", background("sweeps"))
    for client in (app_module.library.coverart_client, app_module.library.artist_images_client,
                   app_module.lrclib, app_module.navidrome_client, auth.login_client, app_module.stars.star_client,
                   app_module.navidrome_admin):
        monkeypatch.setattr(client, "close_client", nothing)
    monkeypatch.setattr(Config, "apply_overrides", lambda stored: None)
    monkeypatch.setattr(Config, "AUTH_MODE", "off")

    async def go():
        async with app_module.lifespan(start()):
            await asyncio.sleep(0)
            running = sorted(began)
        return running, sorted(ended)

    assert run(go()) == (["poller", "scan", "sweeps"], ["poller", "scan", "sweeps"])
