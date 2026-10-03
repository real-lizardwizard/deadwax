"""
POST /deadwax/download/store_state (2.0.0-player.15): what the library and the downloads already
have of a pressing, WITHOUT a Soulseek search - the status line the app's album-you-don't-have page
draws under the pressing before Get ("Already in your library", "Already downloading", "You have 1
of 2 tracks", "You also have another pressing").

It is exactly what find_candidates answers before it decides whether to search (_store_state), so
the page and a Get judge one pressing alike. Through the whole app start() builds (no lifespan, so
nothing connects), with a real SQLite store, real FLACs with real tags in a scratch library, and a
fake slskd that records every search - which must stay empty in every case, the point of the route.
"""

import asyncio

import pytest
from fastapi.testclient import TestClient

from src import library, store_index
from src.api.app import start
from src.config import Config
from src.store import JobStore
from src.store_index import index_folder
from tests.test_store_index import DUMMY, RELEASE, on_disk

ROUTE = "/deadwax/download/store_state"


def run(coroutine):
    return asyncio.run(coroutine)


class Slskd:
    """slskd that can say how far a download has got, and records any search it is asked for."""

    def __init__(self, transfers=None):
        self.searched: list[list[str]] = []
        self.transfers = transfers or []

    async def search_all(self, queries, **kwargs):
        self.searched.append(list(queries))
        return []

    async def search(self, *args, **kwargs):
        self.searched.append(["search"])
        return []

    async def get_downloads(self, usernames=()):
        return [t for t in self.transfers if t["username"] in set(usernames)]


@pytest.fixture
def store(tmp_path):
    job_store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    job_store.init()
    return job_store


@pytest.fixture(autouse=True)
def fresh(monkeypatch, tmp_path):
    library.clear_scan_cache()
    monkeypatch.setattr(store_index, "_FILING_NOW", {})
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "off")
    yield
    library.clear_scan_cache()


def ask(store, slskd, **fields):
    app = start()
    app.state.store = store
    app.state.slskd_client = slskd
    answer = TestClient(app).post(ROUTE, json={**RELEASE, **fields})  # no `with`: no lifespan
    assert answer.status_code == 200
    return answer.json()


def library_root(tmp_path):
    return tmp_path / "music"


def job_in(store, status, files=2, release_mbid="rel-1"):
    async def go():
        wanted = [{"filename": f"share\\Dummy\\0{n}.flac", "size": 1} for n in range(1, files + 1)]
        job_id = await store.create_job("bob", "share\\Dummy", wanted, {**RELEASE, "release_mbid": release_mbid})
        await store.update_status(job_id, status, None)
        return job_id
    return run(go())


def test_a_pressing_held_complete_says_where_and_searches_nothing(tmp_path, store):
    root = library_root(tmp_path)
    run(index_folder(store, str(root), on_disk(root)))
    slskd = Slskd()

    answer = ask(store, slskd)

    assert slskd.searched == []
    assert (answer["held"]["path"], answer["held"]["complete"], answer["held"]["track_count"]) == (DUMMY, True, 2)
    assert (answer["downloading"], answer["downloading_part"], answer["other_pressings"]) == (None, None, [])
    #? only the store's answer - none of a search's
    assert set(answer) == {"downloading", "downloading_part", "held", "other_pressings"}


def test_a_pressing_held_in_part_says_how_much_and_where_a_download_would_go(tmp_path, store):
    root = library_root(tmp_path)
    run(index_folder(store, str(root), on_disk(root, tracks=1)))
    slskd = Slskd()

    held = ask(store, slskd)["held"]

    assert slskd.searched == []
    assert (held["track_count"], held["expected_tracks"], held["complete"]) == (1, 2, False)
    assert (held["fills_gaps"], held["filed_to"]) == (True, DUMMY)


def test_a_pressing_downloading_says_from_whom_and_how_far(store):
    job_id = job_in(store, "downloading")
    slskd = Slskd(transfers=[{"username": "bob", "directories": [{"files": [
        {"filename": "share\\Dummy\\01.flac", "state": "Completed, Succeeded", "percentComplete": 100},
        {"filename": "share\\Dummy\\02.flac", "state": "InProgress", "percentComplete": 40}]}]}])

    answer = ask(store, slskd)

    assert slskd.searched == []
    assert answer["downloading"] == {"job_id": job_id, "status": "downloading", "username": "bob", "files": 2, "done_files": 1}
    assert answer["held"] is None


def test_a_download_of_part_of_it_is_a_note(store):
    job_in(store, "queued", files=1)
    slskd = Slskd()

    answer = ask(store, slskd)

    assert slskd.searched == []
    assert answer["downloading"] is None
    assert (answer["downloading_part"]["username"], answer["downloading_part"]["files"]) == ("bob", 1)


def test_another_pressing_held_is_named(tmp_path, store):
    root = library_root(tmp_path)
    run(index_folder(store, str(root), on_disk(root, "Portishead/Dummy (1994) [2014 vinyl]", release="rel-vinyl")))
    slskd = Slskd()

    answer = ask(store, slskd)

    assert slskd.searched == []
    assert answer["held"] is None
    assert [p["path"] for p in answer["other_pressings"]] == ["Portishead/Dummy (1994) [2014 vinyl]"]


def test_nothing_held_and_nothing_downloading_says_nothing(store):
    slskd = Slskd()
    assert ask(store, slskd) == {"downloading": None, "downloading_part": None, "held": None, "other_pressings": []}
    assert slskd.searched == []


def test_a_release_with_no_id_is_checked_by_nothing(store):
    job_in(store, "downloading", release_mbid=None)
    slskd = Slskd()

    assert ask(store, slskd, release_mbid=None, tracks=[]) == {
        "downloading": None, "downloading_part": None, "held": None, "other_pressings": []}
    assert slskd.searched == []


def test_a_store_that_wont_open_says_nothing_rather_than_failing(tmp_path):
    broken = JobStore(str(tmp_path / "state" / "deadwax.db"))  # never init()ed: unavailable
    slskd = Slskd()

    assert ask(broken, slskd)["held"] is None
    assert slskd.searched == []


def test_the_route_is_a_write_and_the_guard_stands_in_front_of_it(store):
    """POST, like every write: a page on another site can't make the browser ask it."""
    app = start()
    app.state.store = store
    app.state.slskd_client = Slskd()
    answer = TestClient(app).post(ROUTE, json=RELEASE, headers={"Origin": "http://elsewhere.example"})
    assert answer.status_code == 403
