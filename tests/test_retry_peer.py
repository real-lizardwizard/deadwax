"""
Trying the next peer when a download fails (v0.9.12).

A job keeps the rest of the candidates list it was picked from, as it was shown, and a failed or
cancelled one can move to the next of them - by a button, or by itself with AUTO_RETRY_PEER on.
"""

import asyncio
import sqlite3
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

import src.poller as poller
from src.config import Config
from src.poller import poll_downloads_once, retry_next_peer, untried_alternatives
from src.routes import download as routes
from src.store import MAX_ALTERNATIVES, JobStore

RELEASE = {"artist": "Portishead", "album": "Dummy", "year": "1994", "tracks": []}


def alt(user, folder="Dummy"):
    return {"username": user, "directory": f"share\\{folder}", "files": [{"filename": f"share\\{folder}\\01.flac", "size": 1}], "score": 0.8}


def make_store(tmp_path):
    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()
    return store


def seed(store, alternatives, status="failed"):
    async def go():
        job_id = await store.create_job("first", "share\\Dummy", [{"filename": "share\\Dummy\\01.flac", "size": 1}],
                                        RELEASE, alternatives)
        await store.update_status(job_id, status, "the peer refused")
        return await store.get_job(job_id)
    return asyncio.run(go())


class Slskd:
    def __init__(self, refuse=()):
        self.refuse = set(refuse)
        self.asked = []

    async def enqueue(self, username, files):
        self.asked.append(username)
        return (False, f"slskd couldn't queue it: User {username} appears to be offline") if username in self.refuse else (True, "")

    async def get_downloads(self):
        return []

    async def cancel_download(self, *a, **k):
        return True


def test_a_job_keeps_its_runners_up_and_where_it_has_been(tmp_path):
    job = seed(make_store(tmp_path), [alt(f"p{i}") for i in range(15)])
    assert len(job["alternatives"]) == MAX_ALTERNATIVES
    assert job["tried"] == [{"username": "first", "directory": "share\\Dummy"}]


def test_a_database_from_before_this_gains_the_columns(tmp_path):
    path = tmp_path / "old.db"
    with sqlite3.connect(path) as connection:
        connection.execute("""CREATE TABLE jobs (id INTEGER PRIMARY KEY AUTOINCREMENT, release_mbid TEXT,
            artist TEXT, album TEXT, year TEXT, username TEXT NOT NULL, directory TEXT,
            release_json TEXT NOT NULL, files_json TEXT NOT NULL, status TEXT NOT NULL, error TEXT,
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL)""")
        connection.execute("""INSERT INTO jobs (username, release_json, files_json, status, created_at, updated_at)
            VALUES ('old', '{}', '[]', 'failed', 'x', 'x')""")
    store = JobStore(str(path))
    store.init()
    job = asyncio.run(store.get_job(1))
    assert (job["alternatives"], job["tried"]) == ([], [])


def test_the_next_peer_is_a_different_peer():
    job = {"username": "first", "tried": [{"username": "first"}, {"username": "second"}],
           "alternatives": [alt("first", "Dummy (other rip)"), alt("second"), alt("third")]}
    assert [a["username"] for a in untried_alternatives(job)] == ["third"]


def test_a_refusal_moves_on_to_the_one_after(tmp_path):
    store = make_store(tmp_path)
    job = seed(store, [alt("offline"), alt("online"), alt("spare")])
    slskd = Slskd(refuse={"offline"})

    outcome = asyncio.run(retry_next_peer(slskd, store, job))

    assert outcome["moved"] and outcome["username"] == "online" and outcome["left"] == 1
    moved = asyncio.run(store.get_job(job["id"]))
    assert (moved["username"], moved["status"], moved["error"]) == ("online", "queued", None)
    assert [t["username"] for t in moved["tried"]] == ["first", "offline", "online"]
    assert slskd.asked == ["offline", "online"]


def test_every_peer_refusing_is_remembered_so_the_next_retry_skips_them(tmp_path):
    store = make_store(tmp_path)
    job = seed(store, [alt("a"), alt("b")])

    outcome = asyncio.run(retry_next_peer(Slskd(refuse={"a", "b"}), store, job))

    assert not outcome["moved"] and "appears to be offline" in outcome["problem"]
    after = asyncio.run(store.get_job(job["id"]))
    assert after["status"] == "failed"
    assert untried_alternatives(after) == []


def test_nothing_left_says_so(tmp_path):
    store = make_store(tmp_path)
    outcome = asyncio.run(retry_next_peer(Slskd(), store, seed(store, [])))
    assert outcome == {"moved": False, "username": None, "directory": None, "left": 0,
                       "problem": "no other peers to try - search again for more"}


def request_for(store, slskd):
    return SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(store=store, slskd_client=slskd)))


def test_the_route_retries_a_failed_download_and_refuses_a_moving_one(tmp_path):
    store = make_store(tmp_path)
    failed = seed(store, [alt("next")])
    moving = seed(store, [alt("next")], status="downloading")

    assert asyncio.run(routes.retry_job(request_for(store, Slskd()), failed["id"]))["moved"] is True
    with pytest.raises(HTTPException) as refused:
        asyncio.run(routes.retry_job(request_for(store, Slskd()), moving["id"]))
    assert refused.value.status_code == 409


def test_enqueue_keeps_the_runners_up_it_was_sent(tmp_path):
    store = make_store(tmp_path)
    body = routes.EnqueueRequest(username="first", files=[{"filename": "a.flac", "size": 1}], directory="share",
                                 release={"artist": "Portishead", "album": "Dummy"},
                                 alternatives=[alt("second"), alt("third")])
    answer = asyncio.run(routes.enqueue(request_for(store, Slskd()), body))
    job = asyncio.run(store.get_job(answer["job_id"]))
    assert [a["username"] for a in job["alternatives"]] == ["second", "third"]


def test_jobs_say_how_many_peers_are_left(tmp_path):
    store = make_store(tmp_path)
    seed(store, [alt("second"), alt("third")])
    job = asyncio.run(routes.jobs(request_for(store, Slskd())))["jobs"][0]
    assert (job["alternatives_left"], job["attempt"]) == (2, 1)


def failing_transfers():
    return [{"username": "first", "directories": [{"files": [
        {"id": "t1", "filename": "share\\Dummy\\01.flac", "state": "Completed, Rejected", "size": 1}]}]}]


@pytest.mark.parametrize("setting, moved", [("on", True), ("off", False)])
def test_the_poller_moves_a_failure_on_only_when_asked_to(tmp_path, monkeypatch, setting, moved):
    store = make_store(tmp_path)
    job = seed(store, [alt("next")], status="queued")
    monkeypatch.setattr(Config, "AUTO_RETRY_PEER", setting)

    class Failing(Slskd):
        async def get_downloads(self):
            return failing_transfers()

    asyncio.run(poll_downloads_once(Failing(), store, {}))
    after = asyncio.run(store.get_job(job["id"]))
    assert (after["username"] == "next") is moved
    assert after["status"] == ("queued" if moved else "failed")
