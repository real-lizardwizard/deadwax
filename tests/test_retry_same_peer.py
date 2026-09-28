"""
Asking the same peer again when a download fails (v1.0.7).

Beside "next peer": for a peer who was briefly offline, or a transfer that timed out, the same
folder from the same peer is usually the one worth having - and slskd picks up a partly
downloaded file where it stopped.
"""

import asyncio
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from src import poller
from src.poller import retry_same_peer
from src.routes import download as routes
from src.store import JobStore

RELEASE = {"artist": "Portishead", "album": "Dummy", "year": "1994", "tracks": []}
FILES = [{"filename": f"share\\Dummy\\0{n}.flac", "size": 10} for n in (1, 2, 3)]


def make_store(tmp_path):
    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()
    return store


def seed(store, status="failed"):
    async def go():
        job_id = await store.create_job("bob", "share\\Dummy", FILES, RELEASE, [])
        await store.update_status(job_id, status, "the peer stopped responding")
        return await store.get_job(job_id)
    return asyncio.run(go())


class Slskd:
    """Holds a state per file of bob's, as slskd lists them; records every enqueue."""

    def __init__(self, states=None, refuse=False):
        self.states = states or {}
        self.refuse = refuse
        self.enqueued = []

    async def get_downloads(self, usernames=()):
        files = [{"filename": name, "state": state} for name, state in self.states.items()]
        return [{"username": "bob", "directories": [{"directory": "d", "files": files}]}] if files else []

    async def enqueue(self, username, files):
        if self.refuse:
            return False, f"slskd couldn't queue it: User {username} appears to be offline"
        self.enqueued.append((username, [f["filename"] for f in files]))
        return True, ""


@pytest.fixture(autouse=True)
def no_partial_is_deleted(monkeypatch):
    """A partial file is what slskd resumes from, and it is this peer's own - never removed here."""
    def refuse(*a, **k):
        raise AssertionError("the same peer's partial files must be kept")
    monkeypatch.setattr(poller, "remove_incomplete_downloads", refuse)


def test_only_the_files_that_did_not_arrive_are_asked_for(tmp_path):
    store = make_store(tmp_path)
    job = seed(store)
    slskd = Slskd({FILES[0]["filename"]: "Completed, Succeeded", FILES[1]["filename"]: "Completed, TimedOut"})

    outcome = asyncio.run(retry_same_peer(slskd, store, job))

    #? the one that arrived isn't fetched twice; the one slskd has no record of is asked for too
    assert slskd.enqueued == [("bob", [FILES[1]["filename"], FILES[2]["filename"]])]
    assert outcome == {"retried": True, "username": "bob", "files": 2, "problem": None}
    after = asyncio.run(store.get_job(job["id"]))
    assert (after["status"], after["error"], after["username"]) == ("queued", None, "bob")
    assert after["tried"] == job["tried"], "the same peer is no new peer"


def test_a_transfer_still_stopping_is_left_to_finish(tmp_path):
    """slskd would refuse it as "Already in progress" inside a 201 that says nothing about it."""
    store = make_store(tmp_path)
    job = seed(store, status="cancelled")
    slskd = Slskd({FILES[0]["filename"]: "InProgress"})

    outcome = asyncio.run(retry_same_peer(slskd, store, job))

    assert outcome["retried"] is False and "still stopping" in outcome["problem"]
    assert slskd.enqueued == []
    assert asyncio.run(store.get_job(job["id"]))["status"] == "cancelled"


def test_a_refusal_leaves_the_job_as_it_was_and_says_why(tmp_path):
    store = make_store(tmp_path)
    job = seed(store)

    outcome = asyncio.run(retry_same_peer(Slskd(refuse=True), store, job))

    assert outcome["retried"] is False and "appears to be offline" in outcome["problem"]
    after = asyncio.run(store.get_job(job["id"]))
    assert (after["status"], after["error"]) == ("failed", "the peer stopped responding")


def test_with_every_file_already_here_nothing_is_asked_for_and_filing_follows(tmp_path):
    store = make_store(tmp_path)
    job = seed(store)
    slskd = Slskd({f["filename"]: "Completed, Succeeded" for f in FILES})

    outcome = asyncio.run(retry_same_peer(slskd, store, job))

    assert slskd.enqueued == [] and outcome["retried"] is True and outcome["files"] == 0
    assert asyncio.run(store.get_job(job["id"]))["status"] == "queued"


def test_when_slskd_lists_nothing_every_file_is_asked_for(tmp_path):
    store = make_store(tmp_path)
    job = seed(store)
    slskd = Slskd()

    asyncio.run(retry_same_peer(slskd, store, job))

    assert slskd.enqueued == [("bob", [f["filename"] for f in FILES])]


def request_for(store, slskd):
    return SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(store=store, slskd_client=slskd)))


def test_the_route_retries_a_failed_or_cancelled_download_and_refuses_a_moving_one(tmp_path):
    store = make_store(tmp_path)
    failed, cancelled = seed(store), seed(store, status="cancelled")
    moving = seed(store, status="downloading")

    assert asyncio.run(routes.retry_job_same_peer(request_for(store, Slskd()), failed["id"]))["retried"] is True
    assert asyncio.run(routes.retry_job_same_peer(request_for(store, Slskd()), cancelled["id"]))["retried"] is True
    with pytest.raises(HTTPException) as refused:
        asyncio.run(routes.retry_job_same_peer(request_for(store, Slskd()), moving["id"]))
    assert refused.value.status_code == 409
    with pytest.raises(HTTPException) as missing:
        asyncio.run(routes.retry_job_same_peer(request_for(store, Slskd()), 999))
    assert missing.value.status_code == 404
