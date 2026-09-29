"""
A Soulseek search the page gave up on is stopped in slskd, not run out to its timeout.

The browser has aborted a superseded candidates request since v0.9.2, but uvicorn doesn't cancel
a handler when its client goes: the search ran on in slskd, was scored, and was returned into a
closed connection. These hold the two halves - the route noticing the client has gone, and the
search stopping what it started when it is cancelled.
"""

import asyncio
from types import SimpleNamespace

import pytest

from src.api.slskd_endpoint import SlskdClient
from src.routes import download as routes
from src.routes.download import ClientGone, unless_abandoned


class NeverFinishingSearches:
    """slskd with searches that run for ever, recording what is done to them."""

    def __init__(self):
        self.stopped, self.deleted, self.started = [], [], []

    def search_text(self, searchText, **kwargs):
        self.started.append(searchText)
        return {"id": f"id:{searchText}"}

    def state(self, search_id, **kwargs):
        return {"isComplete": False}

    def search_responses(self, search_id):
        return []

    def stop(self, search_id):
        self.stopped.append(search_id)
        return True

    def delete(self, search_id):
        self.deleted.append(search_id)
        return True


def client_with(searches):
    client = SlskdClient()
    client.client = SimpleNamespace(searches=searches, application=SimpleNamespace(state=lambda: {}))
    return client


async def until(condition, seconds=5.0):
    """Wait for a condition rather than a fixed time - CI's runners are slower than a laptop."""
    for _ in range(int(seconds / 0.005)):
        if condition():
            return
        await asyncio.sleep(0.005)
    raise AssertionError("timed out waiting")


def test_cancelling_a_search_stops_and_deletes_every_search_it_started():
    searches = NeverFinishingSearches()
    client = client_with(searches)

    async def go():
        task = asyncio.create_task(client.search_all(["Kanye West Donda", "Ye Donda"], poll_interval=0.01, max_wait=60))
        await until(lambda: len(searches.started) == 2)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task

    asyncio.run(go())
    assert searches.stopped == ["id:Kanye West Donda", "id:Ye Donda"]
    assert searches.deleted == ["id:Kanye West Donda", "id:Ye Donda"]


def test_a_search_still_starting_when_cancelled_is_stopped_too():
    """
    The race CI's slower runner found (v1.1.7): the cancel lands while the second start is still
    in its thread. The thread can't be cancelled, so slskd starts that search anyway - and it was
    never recorded, so it ran to its timeout for nobody.
    """
    import threading

    release = threading.Event()

    class SlowSecondStart(NeverFinishingSearches):
        def search_text(self, searchText, **kwargs):
            if self.started:
                self.started.append(searchText)
                release.wait(5)  # still starting when the cancel arrives
                return {"id": f"id:{searchText}"}
            return super().search_text(searchText, **kwargs)

    searches = SlowSecondStart()
    client = client_with(searches)

    async def go():
        task = asyncio.create_task(client.search_all(["Kanye West Donda", "Ye Donda"], poll_interval=0.01, max_wait=60))
        await until(lambda: len(searches.started) == 2)
        task.cancel()
        await asyncio.sleep(0.05)
        release.set()
        with pytest.raises(asyncio.CancelledError):
            await task

    asyncio.run(go())
    assert searches.stopped == ["id:Kanye West Donda", "id:Ye Donda"]
    assert searches.deleted == ["id:Kanye West Donda", "id:Ye Donda"]


class Request:
    def __init__(self, gone_after):
        self.checks = 0
        self.gone_after = gone_after

    async def is_disconnected(self):
        self.checks += 1
        return self.checks >= self.gone_after


def test_work_that_finishes_is_simply_answered():
    async def work():
        return "candidates"
    assert asyncio.run(unless_abandoned(Request(gone_after=10**6), work(), check_every=0.01)) == "candidates"


def test_the_work_is_cancelled_when_the_client_goes():
    cancelled = []

    async def work():
        try:
            await asyncio.sleep(60)
        except asyncio.CancelledError:
            cancelled.append(True)
            raise

    with pytest.raises(ClientGone):
        asyncio.run(unless_abandoned(Request(gone_after=2), work(), check_every=0.01))
    assert cancelled == [True]


def test_the_route_stops_the_search_when_the_page_drops_it(monkeypatch):
    searches = NeverFinishingSearches()
    request = SimpleNamespace(
        app=SimpleNamespace(state=SimpleNamespace(slskd_client=client_with(searches), store=None)),
        is_disconnected=Request(gone_after=3).is_disconnected,
    )
    body = routes.FindCandidatesRequest(artist="Portishead", album="Dummy", query_override="Portishead Dummy")
    monkeypatch.setattr(routes, "DISCONNECT_CHECK_SECONDS", 0.01)

    response = asyncio.run(routes.find_candidates(request, body))

    assert response.status_code == 204
    assert searches.started == ["Portishead Dummy"]
    assert searches.stopped == ["id:Portishead Dummy"]
