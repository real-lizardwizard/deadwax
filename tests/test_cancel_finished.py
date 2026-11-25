"""
A download that has finished is never cancelled (2.1.45).

Found reviewing the Mac app's Requests table: its Cancel confirmation held the row as it was when Cancel was clicked,
and the cancel route checked nothing, so a download whose last file arrived while the question was up was marked
`cancelled` - a filing cancelled half-way, or a filed album called cancelled (its Done row turned Needs attention).
The apps never offer a cancel once a download is being filed; the route now refuses one too, on the job as it is
now, and again in the status's own write, since the poller starts a filing without the job's lock.
"""

import asyncio
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

import src.poller as poller
from src.routes import download as routes
from src.store import FINISHED_STATUSES, JobStore

FILES = [{"filename": "share/album/01.flac", "size": 1}, {"filename": "share/album/02.flac", "size": 1}]
RELEASE = {"artist": "Portishead", "album": "Dummy", "year": "1994", "release_mbid": "mb", "tracks": []}


class Slskd:
    """slskd holding the job's two transfers; `on_cancel` runs as each is cancelled - the poller's moment."""

    def __init__(self, on_cancel=None):
        self.cancelled: list[str] = []
        self.on_cancel = on_cancel

    async def get_downloads(self, usernames=()):
        files = [{"id": tid, "filename": f"share/album/{tid}.flac", "state": "InProgress"} for tid in ("01", "02")]
        return [{"username": "bob", "directories": [{"directory": "share/album", "files": files}]}]

    async def cancel_download(self, username, transfer_id, remove=True):
        self.cancelled.append(transfer_id)
        if self.on_cancel:
            await self.on_cancel()
        return True


def setup(tmp_path, monkeypatch, status, on_cancel=None):
    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()

    async def seed():
        job_id = await store.create_job("bob", "share/album", FILES, RELEASE)
        await store.update_status(job_id, status)
        return job_id

    job_id = asyncio.run(seed())
    slskd = Slskd(on_cancel and (lambda: on_cancel(store, job_id)))
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(store=store, slskd_client=slskd)))
    monkeypatch.setattr(routes.Config, "SLSKD_INCOMPLETE_PATH", "")
    removed: list = []
    monkeypatch.setattr(routes, "remove_incomplete_downloads",
                        lambda *args: removed.append(args) or {"removed": [], "skipped": [], "problem": None})
    return store, job_id, slskd, request, removed


def cancel(request, job_id):
    async def go():
        try:
            return await routes.cancel_job(request, job_id)
        finally:
            await asyncio.gather(*list(poller._tidy_tasks))
    return asyncio.run(go())


@pytest.mark.parametrize("status", FINISHED_STATUSES)
def test_a_finished_download_is_never_cancelled(tmp_path, monkeypatch, status):
    store, job_id, slskd, request, removed = setup(tmp_path, monkeypatch, status)
    with pytest.raises(HTTPException) as refused:
        cancel(request, job_id)
    assert refused.value.status_code == 409 and refused.value.detail == routes.ALREADY_FINISHED
    #? nothing asked of slskd, nothing removed, and the job as it was
    assert slskd.cancelled == [] and removed == []
    assert asyncio.run(store.get_job(job_id))["status"] == status


@pytest.mark.parametrize("status", ["queued", "downloading", "failed"])
def test_a_download_still_going_is_cancelled_as_before(tmp_path, monkeypatch, status):
    store, job_id, slskd, request, removed = setup(tmp_path, monkeypatch, status)
    answer = cancel(request, job_id)
    assert answer["cancelled"] == 2 and slskd.cancelled == ["01", "02"] and len(removed) == 1
    assert asyncio.run(store.get_job(job_id))["status"] == "cancelled"


def test_a_filing_begun_as_the_cancel_is_asked_is_left_to_finish(tmp_path, monkeypatch):
    #? the poller sees the last file arrive and starts filing while slskd is being asked to cancel: the status's
    #? own write refuses, the filing carries on, and nothing in slskd's incomplete folder is touched
    async def filing(store, job_id):
        await store.update_status(job_id, "organizing")

    store, job_id, slskd, request, removed = setup(tmp_path, monkeypatch, "downloading", on_cancel=filing)
    with pytest.raises(HTTPException) as refused:
        cancel(request, job_id)
    assert refused.value.status_code == 409
    assert asyncio.run(store.get_job(job_id))["status"] == "organizing"
    assert removed == []


def test_the_guarded_write_says_whether_it_wrote(tmp_path):
    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()

    async def go():
        job_id = await store.create_job("bob", "share/album", FILES, RELEASE)
        await store.update_status(job_id, "organized")
        refused = await store.update_status(job_id, "cancelled", "x", unless=FINISHED_STATUSES)
        kept = (await store.get_job(job_id))["status"]
        await store.update_status(job_id, "failed")
        written = await store.update_status(job_id, "cancelled", "x", unless=FINISHED_STATUSES)
        #? with no guard, a write is as it always was
        plain = await store.update_status(job_id, "organized")
        return refused, kept, written, plain, (await store.get_job(job_id))["status"]

    assert asyncio.run(go()) == (False, "organized", True, True, "organized")
