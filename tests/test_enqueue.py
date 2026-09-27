"""
Queueing a download - and saying why slskd wouldn't.

slskd_api's enqueue returns only response.ok, and slskd puts its reason in the body - usually
that the peer is offline, from the lookup its enqueue does first. The downloads panel shows that
reason on the row you just asked for (v0.9.9), so it has to survive the trip.
"""

import asyncio
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from src.api.slskd_endpoint import SlskdClient
from src.routes import download as routes


class Response:
    def __init__(self, status, body):
        self.status_code = status
        self.ok = 200 <= status < 300
        self._body = body
        self.text = body if isinstance(body, str) else ""

    def json(self):
        if isinstance(self._body, str):
            raise ValueError("not json")
        return self._body


def client_answering(response):
    """slskd_api's session, which RAISES on a non-2xx - a response hook calling raise_for_status."""
    from requests.exceptions import HTTPError
    posted = []

    def post(url, json):
        posted.append((url, json))
        if not response.ok:
            raise HTTPError(f"{response.status_code} Server Error", response=response)
        return response

    client = SlskdClient()
    client.client = SimpleNamespace(transfers=SimpleNamespace(
        api_url="http://slskd/api/v0", session=SimpleNamespace(post=post)))
    return client, posted


FILES = [{"filename": "share\\Dummy\\01.flac", "size": 10, "extra": "dropped"}]


def test_an_accepted_enqueue_posts_exactly_what_slskd_api_would():
    client, posted = client_answering(Response(201, {"enqueued": [], "failed": []}))
    assert asyncio.run(client.enqueue("bob smith", FILES)) == (True, "")
    assert posted == [("http://slskd/api/v0/transfers/downloads/bob%20smith",
                       [{"filename": "share\\Dummy\\01.flac", "size": 10}])]


def test_a_refusal_carries_slskds_own_words():
    client, _ = client_answering(Response(500, "User bob appears to be offline"))
    ok, reason = asyncio.run(client.enqueue("bob", FILES))
    assert not ok
    assert reason == "slskd couldn't queue it: User bob appears to be offline"


def test_a_refusal_with_nothing_said_still_names_the_status():
    client, _ = client_answering(Response(429, ""))
    assert asyncio.run(client.enqueue("bob", FILES)) == (False, "slskd refused the download (429)")


def test_the_route_hands_the_reason_to_the_panel():
    class Refusing:
        async def enqueue(self, username, files):
            return False, "slskd couldn't queue it: User bob appears to be offline"

    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(slskd_client=Refusing(), store=None)))
    body = routes.EnqueueRequest(username="bob", files=[{"filename": "a.flac", "size": 1}], directory="share",
                                 release={"artist": "Portishead", "album": "Dummy"})

    with pytest.raises(HTTPException) as refused:
        asyncio.run(routes.enqueue(request, body))

    assert refused.value.status_code == 502
    assert refused.value.detail == "slskd couldn't queue it: User bob appears to be offline"


def test_queue_positions_are_asked_side_by_side_and_land_on_the_right_jobs(tmp_path):
    """One after another, every queued job added a round trip to every poll of the panel."""
    from src.store import JobStore

    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()

    async def seed(user):
        return await store.create_job(user, "share", [{"filename": f"{user}.flac", "size": 1}],
                                      {"artist": user, "album": "x", "tracks": []})

    for user in ("ann", "bob", "cat"):
        asyncio.run(seed(user))

    class Slskd:
        def __init__(self):
            self.in_flight = self.most = 0

        async def get_downloads(self, usernames=()):
            #? only the users asked about - so a /jobs that forgot one would lose its position
            wanted = set(usernames)
            return [{"username": u, "directories": [{"files": [
                {"id": f"t-{u}", "filename": f"{u}.flac", "state": "Queued, Remotely",
                 "percentComplete": 0, "size": 1}]}]} for u in ("ann", "bob", "cat") if u in wanted]

        async def queue_position(self, username, transfer_id):
            self.in_flight += 1
            self.most = max(self.most, self.in_flight)
            await asyncio.sleep(0.01)
            self.in_flight -= 1
            return {"ann": 4, "bob": 9, "cat": 1}[username]

    slskd = Slskd()
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(store=store, slskd_client=slskd)))
    answer = asyncio.run(routes.jobs(request))

    assert {j["username"]: j["queue_position"] for j in answer["jobs"]} == {"ann": 4, "bob": 9, "cat": 1}
    assert slskd.most == 3
