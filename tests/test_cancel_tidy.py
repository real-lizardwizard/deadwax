"""
A cancelled download leaves slskd's own list, not just deadwax's.

Asked for: "make sure a canceled job also gets removed from slskd's UI. Currently there's a bunch
of canceled jobs just sitting there." deadwax always cancelled with remove=true, and slskd always
answered 204 and removed nothing: its controller calls TryCancel and then Remove on the next line,
but TryCancel on a live transfer only signals it, and Remove only touches transfers that have
already reached a completed state. So the fake slskd here behaves exactly that way - a cancel
settles on the NEXT look, and a remove before then does nothing - and the tests hold deadwax to
asking again once it has.
"""

import asyncio
from types import SimpleNamespace

import src.poller as poller
from src.poller import tidy_cancelled_later, tidy_cancelled_on_start, tidy_cancelled_transfers
from src.store import JobStore, settled_transfer_ids

FILES = [{"filename": "share/album/01.flac", "size": 1}, {"filename": "share/album/02.flac", "size": 1}]
RELEASE = {"artist": "Portishead", "album": "Dummy", "year": "1994", "release_mbid": "mb", "tracks": []}


class SlowCancellingSlskd:
    """slskd as its source says it behaves: a cancel settles a moment later; remove needs settled."""

    def __init__(self, states):
        self.states = dict(states)  # id -> state
        self.pending_cancel = set()
        self.removed = set()
        self.remove_calls = []

    def _listing(self):
        files = [{"id": tid, "filename": f"share/album/{tid}.flac", "state": state}
                 for tid, state in self.states.items() if tid not in self.removed]
        return [{"username": "bob", "directories": [{"directory": "share/album", "files": files}]}]

    async def get_downloads(self):
        #? whatever was cancelled since the last look has now settled
        for tid in self.pending_cancel:
            self.states[tid] = "Completed, Cancelled"
        self.pending_cancel.clear()
        return self._listing()

    async def cancel_download(self, username, transfer_id, remove=True):
        self.remove_calls.append(transfer_id)
        if "Completed" not in self.states[transfer_id]:
            self.pending_cancel.add(transfer_id)  # TryCancel: signalled, not yet settled
            return True  # ...and Remove quietly matched nothing, with a 204
        if remove:
            self.removed.add(transfer_id)
        return True


def job(**extra):
    return {"id": 1, "username": "bob", "artist": "Portishead", "album": "Dummy",
            "files": [{"filename": "share/album/01.flac"}, {"filename": "share/album/02.flac"}], **extra}


def by_user(*specs):
    return {"bob": [{"id": tid, "filename": f"share/album/{tid}.flac", "state": state} for tid, state in specs]}


def test_only_settled_transfers_of_this_job_can_be_removed():
    transfers = by_user(("01", "Completed, Cancelled"), ("02", "InProgress"), ("99", "Completed, Cancelled"))
    assert settled_transfer_ids(job(), transfers) == (["01"], 1)


def test_another_users_transfers_are_never_touched():
    transfers = {"alice": [{"id": "01", "filename": "share/album/01.flac", "state": "Completed, Cancelled"}]}
    assert settled_transfer_ids(job(), transfers) == ([], 0)


def test_a_cancel_that_has_not_settled_is_asked_again_once_it_has():
    slskd = SlowCancellingSlskd({"01": "InProgress", "02": "Queued, Remotely"})

    async def go():
        #? what cancel_job does first: cancel with remove=true, which removes nothing yet
        for tid in ("01", "02"):
            await slskd.cancel_download("bob", tid, remove=True)
        assert slskd.removed == set()

        naps = []

        async def nap(seconds):
            naps.append(seconds)

        await tidy_cancelled_later(slskd, job(), sleep=nap)
        return naps

    naps = asyncio.run(go())
    assert slskd.removed == {"01", "02"}
    assert naps == []  # settled by the first look, so it never had to wait


def test_the_tidy_gives_up_after_its_wait_and_leaves_the_rest_for_later(monkeypatch):
    class NeverSettles(SlowCancellingSlskd):
        async def get_downloads(self):
            return self._listing()

    slskd = NeverSettles({"01": "InProgress", "02": "InProgress"})
    monkeypatch.setattr(poller, "TIDY_WAIT_SECONDS", 3.0)

    async def go():
        naps = []

        async def nap(seconds):
            naps.append(seconds)

        await tidy_cancelled_later(slskd, job(), sleep=nap)
        return naps

    assert asyncio.run(go()) == [1.0, 1.0, 1.0]
    assert slskd.removed == set()


def test_one_pass_reports_what_it_removed_and_what_is_still_settling():
    slskd = SlowCancellingSlskd({"01": "Completed, Cancelled", "02": "InProgress"})
    assert asyncio.run(tidy_cancelled_transfers(slskd, [job()])) == (1, 1)
    assert slskd.removed == {"01"}


def make_store(tmp_path):
    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()
    return store


def seed(store, status):
    async def go():
        job_id = await store.create_job("bob", "share/album", FILES, RELEASE)
        await store.update_status(job_id, status)
        return job_id
    return asyncio.run(go())


def test_on_start_it_tidies_cancelled_jobs_still_in_the_list(tmp_path):
    store = make_store(tmp_path)
    seed(store, "cancelled")
    seed(store, "organized")  # a finished download's transfers are not this tidy's business

    slskd = SlowCancellingSlskd({"01": "Completed, Cancelled", "02": "Completed, Succeeded"})
    assert asyncio.run(tidy_cancelled_on_start(slskd, store)) == 2
    #? both belong to the cancelled job's files - the organized one names the same files, which
    #? is exactly why only cancelled JOBS are consulted rather than every transfer
    assert slskd.removed == {"01", "02"}


def test_on_start_with_nothing_cancelled_it_never_asks_slskd(tmp_path):
    store = make_store(tmp_path)
    seed(store, "organized")

    class Untouchable:
        async def get_downloads(self):
            raise AssertionError("asked slskd for nothing")

    assert asyncio.run(tidy_cancelled_on_start(Untouchable(), store)) == 0


def test_clearing_finished_jobs_tidies_their_transfers_first(tmp_path):
    from src.routes.download import clear_jobs

    store = make_store(tmp_path)
    seed(store, "cancelled")
    slskd = SlowCancellingSlskd({"01": "Completed, Cancelled", "02": "Completed, Cancelled"})
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(store=store, slskd_client=slskd)))

    answer = asyncio.run(clear_jobs(request))

    assert answer["removed"] == 1
    assert slskd.removed == {"01", "02"}


def test_cancelling_a_job_takes_its_transfers_out_of_slskds_list(tmp_path, monkeypatch):
    from src.routes import download as routes

    store = make_store(tmp_path)
    job_id = seed(store, "downloading")
    slskd = SlowCancellingSlskd({"01": "InProgress", "02": "Queued, Remotely"})
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(store=store, slskd_client=slskd)))
    monkeypatch.setattr(routes.Config, "SLSKD_INCOMPLETE_PATH", "")

    async def go():
        answer = await routes.cancel_job(request, job_id)
        #? the tidy is a task; let it finish
        await asyncio.gather(*list(poller._tidy_tasks))
        return answer

    answer = asyncio.run(go())
    assert answer["cancelled"] == 2
    assert slskd.removed == {"01", "02"}
