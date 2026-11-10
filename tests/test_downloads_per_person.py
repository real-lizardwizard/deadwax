"""
Downloads per person (2.0.0-player.49, step 4 of the multi-user plan) - store.py's job_requests,
routes/download.py, store_index's retry_pending, the poller's _fail, slskd_endpoint's search gate and
the organizing rule logins need - through the whole app start() builds (no lifespan), a real SQLite
store, a fake slskd, and test_logins' fake Navidrome checking token auth (james the admin; ethan and
sam users).

What these hold (every rule decided with James on 2026-09-27):

  - Requesters are their own table: a job made before it is `local`'s, once, and the first admin's
    take-over moves local's requests to them.
  - Who sees what: a user their own requests (joined ones too); an admin everyone's, each row saying
    who else asked (`requested_by`), whether it's theirs (`mine`) and whether somebody else waits on it
    (`shared`); a user can't act on, or even find, somebody else's (404).
  - Joining: a second person's Get of a release downloading whole joins it - nothing asked of slskd -
    and so does the join route; the same person asking twice is still refused; Find's answer says
    whether the download in flight is yours, and what its copy is.
  - Cancel means leave: a user's cancel withdraws their request while someone else still waits; slskd
    is cancelled, and the partials removed, only at the last leave - or an admin's cancel.
  - Retry by any requester moves the one download, everyone with it.
  - Clear finished hides it for you; the row goes once everyone has hidden it (an admin's clear of
    somebody else's hides it for the admin alone).
  - "Downloading now" counts a failed download with a retry pending.
  - One Soulseek search STARTS at a time across all users: two Finds at once both answer, their
    starts in turn; the wait is bounded and never refuses.
  - Logins need organizing on (copy or move, both folders): otherwise every protected route answers
    503 with the reason, start-up says so, and the settings tab won't switch it off under logins.
  - With logins off, everything is as it was.
"""

import asyncio
import logging
import sqlite3
import threading
import time
from pathlib import Path
from types import SimpleNamespace

import httpx
import pytest
import requests
from fastapi.testclient import TestClient

from src import auth, poller, store_index
from src.api import slskd_endpoint
from src.api.app import start
from src.api.slskd_endpoint import SearchGate, SlskdClient
from src.config import Config
from src.store import JobStore, job_quality
from src.users import LOCAL_USER
from tests.test_logins import GLASS, LOGIN, PASSWORDS, SECRET, FakeNavidrome, wire_native
from src import permissions
from src.api import navidrome_admin

JOBS = "/deadwax/download/jobs"
ENQUEUE = "/deadwax/download/enqueue"
STORE_STATE = "/deadwax/download/store_state"
SAM_PASSWORD = "sam-navidrome-pw"

TRACKS = [{"position": 1, "title": "Mysterons"}, {"position": 2, "title": "Sour Times"}]
RELEASE = {"artist": "Portishead", "album": "Dummy", "year": "1994", "release_mbid": "rel-dummy", "tracks": TRACKS}
FILES = [{"filename": "share\\Dummy\\01 Mysterons.flac", "size": 10}, {"filename": "share\\Dummy\\02 Sour Times.flac", "size": 10}]
QUALITY = {"formats": ["flac"], "bitrates": [], "bit_depths": [24], "sample_rates": [96000], "variable_bitrate": False}


def run(coroutine):
    return asyncio.run(coroutine)


class Slskd:
    """slskd as the download routes use it: every enqueue accepted (and remembered as transfers), cancels counted."""

    def __init__(self):
        self.enqueued: list[str] = []
        self.cancelled: list[tuple[str, str]] = []
        self.transfers: dict[str, list[dict]] = {}

    async def enqueue(self, username, files):
        self.enqueued.append(username)
        self.transfers[username] = [{"id": f"{username}-{n}", "filename": f["filename"], "state": "Queued, Remotely",
                                     "size": f.get("size", 0), "bytesTransferred": 0} for n, f in enumerate(files)]
        return True, ""

    async def get_downloads(self, usernames=()):
        return [{"username": name, "directories": [{"directory": "d", "files": self.transfers[name]}]}
                for name in sorted(set(usernames)) if name in self.transfers]

    async def cancel_download(self, username, transfer_id, remove=True):
        self.cancelled.append((username, transfer_id))
        return True

    async def queue_position(self, username, transfer_id):
        return 3

    def fail(self, username):
        """The peer's transfers stop for good, as slskd reports a refusal."""
        for transfer in self.transfers.get(username, []):
            transfer["state"] = "Completed, Errored"


@pytest.fixture
def on(monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "AUTH_MODE", "on")
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", SECRET)
    monkeypatch.setattr(Config, "DEADWAX_ADMIN_PASSWORD", GLASS)
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "copy")
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "slskd"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "library"))
    monkeypatch.setattr(Config, "SLSKD_INCOMPLETE_PATH", None)
    monkeypatch.setattr(Config, "AUTO_RETRY_PEER", "off")
    monkeypatch.setattr(auth, "throttle", auth.Throttle())
    auth.forget_sessions()
    permissions.forget_all()
    fake = FakeNavidrome()
    fake.passwords["sam"] = SAM_PASSWORD
    fake.ids["sam"] = "id-sam"
    auth.login_client.client = httpx.AsyncClient(transport=httpx.MockTransport(fake.handle),
                                                 base_url="http://navidrome:4533/rest")
    auth.login_client.base = "http://navidrome:4533/rest"
    #? (2.0.0-player.61) the sign-in reads the account id of someone an admin gave a permission to
    wire_native(fake.handle)
    store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    store.init()
    app = start()
    app.state.store = store
    app.state.slskd_client = Slskd()
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    yield SimpleNamespace(app=app, store=store, slskd=app.state.slskd_client, tmp=tmp_path, fake=fake,
                          path=tmp_path / "state" / "deadwax.db")
    auth.forget_sessions()
    permissions.forget_all()
    run(auth.login_client.close_client())
    run(navidrome_admin.close_client())


def password_of(name: str) -> str:
    return SAM_PASSWORD if name == "sam" else PASSWORDS[name]


def signed_in(on, name: str) -> TestClient:
    client = TestClient(on.app)
    assert client.post(LOGIN, json={"username": name, "password": password_of(name)}).status_code == 200
    return client


def enqueue_body(username="bob", release=None, quality=None, alternatives=()):
    body = {"username": username, "files": FILES, "directory": "share\\Dummy", "release": release or RELEASE,
            "alternatives": list(alternatives)}
    if quality is not None:
        body["quality"] = quality
    return body


def rows(client) -> dict[int, dict]:
    answer = client.get(JOBS)
    assert answer.status_code == 200, answer.text
    return {row["id"]: row for row in answer.json()["jobs"]}


def get(client, **body) -> dict:
    answer = client.post(ENQUEUE, json=enqueue_body(**body))
    assert answer.status_code == 200, answer.text
    return answer.json()


def requests_on(path, job_id) -> list[tuple]:
    with sqlite3.connect(path) as connection:
        return connection.execute("SELECT user, requested_at IS NOT NULL, left_at IS NOT NULL, hidden_at IS NOT NULL "
                                  "FROM job_requests WHERE job_id = ? ORDER BY user", (job_id,)).fetchall()


def job_exists(path, job_id) -> bool:
    with sqlite3.connect(path) as connection:
        return connection.execute("SELECT 1 FROM jobs WHERE id = ?", (job_id,)).fetchone() is not None


# ----------------------------------------------------------------- requesters, their own table

def test_a_job_made_before_requests_existed_is_locals_once(tmp_path):
    path = tmp_path / "old.db"
    store = JobStore(str(path))
    store.init()
    job_id = run(store.create_job("bob", "d", FILES, RELEASE))
    #? a database from before 2.0.0-player.49: no job_requests table at all
    with sqlite3.connect(path) as connection:
        connection.execute("DROP TABLE job_requests")

    JobStore(str(path)).init()
    assert requests_on(path, job_id) == [(LOCAL_USER, 1, 0, 0)]

    #? taken over by the first admin - and a later start never hands it back to local
    assert run(store.adopt_local("james")) == (0, 0, 1)
    JobStore(str(path)).init()
    assert requests_on(path, job_id) == [("james", 1, 0, 0)]


def test_a_new_job_is_its_askers_in_the_same_write(tmp_path):
    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()
    job_id = run(store.create_job("bob", "d", FILES, RELEASE, user="ethan", quality=QUALITY))
    assert requests_on(tmp_path / "jobs.db", job_id) == [("ethan", 1, 0, 0)]
    assert run(store.get_job(job_id))["quality"] == QUALITY
    #? the default is logins-off's one user
    other = run(store.create_job("bob", "d", FILES, RELEASE))
    assert requests_on(tmp_path / "jobs.db", other) == [(LOCAL_USER, 1, 0, 0)]


def test_the_first_admins_sign_in_takes_over_locals_downloads(on):
    job_id = run(on.store.create_job("bob", "share\\Dummy", FILES, RELEASE))
    ethan = signed_in(on, "ethan")
    assert rows(ethan) == {}
    james = signed_in(on, "james")
    assert rows(james)[job_id]["mine"] is True
    assert requests_on(on.path, job_id) == [("james", 1, 0, 0)]


def test_a_job_keeps_only_the_quality_it_knows(tmp_path):
    assert job_quality({**QUALITY, "extra": "dropped", "variable_bitrate": None}) == {
        key: value for key, value in QUALITY.items() if key != "variable_bitrate"}
    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()
    job_id = run(store.create_job("bob", "d", FILES, RELEASE, quality={**QUALITY, "path": "/etc"}))
    assert run(store.get_job(job_id))["quality"] == QUALITY


def test_the_take_over_keeps_a_row_the_admin_already_has(tmp_path):
    path = tmp_path / "jobs.db"
    store = JobStore(str(path))
    store.init()
    job_id = run(store.create_job("bob", "d", FILES, RELEASE, user="james"))
    #? `local` cleared it while logins were off; james is still waiting for it
    with sqlite3.connect(path) as connection:
        connection.execute("INSERT INTO job_requests (job_id, user, requested_at, hidden_at) VALUES (?, ?, ?, ?)",
                           (job_id, LOCAL_USER, "2026-01-01T00:00:00+00:00", "2026-01-02T00:00:00+00:00"))
    assert run(store.adopt_local("james")) == (0, 0, 0)
    assert requests_on(path, job_id) == [("james", 1, 0, 0)]


def test_an_admin_signed_in_before_a_restart_takes_locals_downloads_at_their_next_request(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    done = get(james)["job_id"]
    run(on.store.update_status(done, "organized"))
    #? an upgrade from 2.0.0-player.48: no job_requests, so every download becomes local's at the
    #? next start - and james's session outlives it (sessions are kept in the database)
    with sqlite3.connect(on.path) as connection:
        connection.execute("DROP TABLE job_requests")
    auth.forget_sessions()
    on.store.init()
    assert requests_on(on.path, done) == [(LOCAL_USER, 1, 0, 0)]

    #? a user's request takes nothing over
    assert rows(ethan) == {}
    assert requests_on(on.path, done) == [(LOCAL_USER, 1, 0, 0)]
    #? the first admin's does: theirs, nobody "local" named, and theirs to clear for good
    row = rows(james)[done]
    assert (row["mine"], row["shared"], row["requested_by"]) == (True, False, [])
    assert requests_on(on.path, done) == [("james", 1, 0, 0)]
    assert james.post(f"{JOBS}/clear").json()["removed"] == 1
    assert not job_exists(on.path, done)


def test_downloads_got_with_logins_off_go_to_the_first_admin_back_with_a_session(on, monkeypatch):
    james = signed_in(on, "james")
    assert rows(james) == {}  # james seen once already in this process: local had nothing then
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    job_id = get(TestClient(on.app))["job_id"]
    assert requests_on(on.path, job_id) == [(LOCAL_USER, 1, 0, 0)]

    #? logins on again - a restart - and james's session still stands: no sign-in to take it over
    monkeypatch.setattr(Config, "AUTH_MODE", "on")
    auth.forget_sessions()
    row = rows(james)[job_id]
    assert (row["mine"], row["requested_by"]) == (True, [])
    assert requests_on(on.path, job_id) == [("james", 1, 0, 0)]

    #? looked for once a process: an admin's every request after asks the database nothing more
    looked = []
    monkeypatch.setattr(on.store, "local_has_anything", lambda: looked.append(True) or False)
    assert job_id in rows(james)
    assert looked == []


# ----------------------------------------------------------------- who sees what

def test_a_user_sees_their_own_and_an_admin_everyones_saying_who_asked(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    theirs = get(ethan, release={**RELEASE, "release_mbid": "rel-ethans"})["job_id"]
    mine = get(james, release={**RELEASE, "release_mbid": "rel-james"})["job_id"]

    assert list(rows(ethan)) == [theirs]
    row = rows(ethan)[theirs]
    assert (row["mine"], row["shared"]) == (True, False)
    #? who else asked is the admin's to see
    assert "requested_by" not in row

    seen = rows(james)
    assert set(seen) == {theirs, mine}
    assert (seen[mine]["mine"], seen[mine]["shared"], seen[mine]["requested_by"]) == (True, False, [])
    assert (seen[theirs]["mine"], seen[theirs]["shared"], seen[theirs]["requested_by"]) == (False, True, ["ethan"])


def test_who_else_asked_is_said_in_the_order_they_asked(on):
    james, ethan, sam = signed_in(on, "james"), signed_in(on, "ethan"), signed_in(on, "sam")
    #? one download asked for sam first, another ethan first - an order the alphabet can't fake both ways
    first = get(sam, release={**RELEASE, "release_mbid": "rel-first"})["job_id"]
    get(ethan, release={**RELEASE, "release_mbid": "rel-first"})
    second = get(ethan, release={**RELEASE, "release_mbid": "rel-second"})["job_id"]
    get(sam, release={**RELEASE, "release_mbid": "rel-second"})
    seen = rows(james)
    assert seen[first]["requested_by"] == ["sam", "ethan"]
    assert seen[second]["requested_by"] == ["ethan", "sam"]


def test_a_user_cant_act_on_or_find_somebody_elses_download(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    job_id = get(james)["job_id"]
    run(on.store.update_status(job_id, "failed", "offline"))
    for action in ("cancel", "retry", "retry_same"):
        answer = ethan.post(f"{JOBS}/{job_id}/{action}")
        assert answer.status_code == 404, action
    assert run(on.store.get_job(job_id))["status"] == "failed"
    assert on.slskd.cancelled == []


# ----------------------------------------------------------------- joining

def test_a_second_persons_get_joins_the_download_and_asks_slskd_nothing(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    job_id = get(james, quality=QUALITY)["job_id"]

    answer = get(ethan, username="someone-else")
    assert answer == {"status": "ok", "queued": 0, "job_id": job_id, "joined": True}
    assert on.slskd.enqueued == ["bob"]

    row = rows(ethan)[job_id]
    assert (row["mine"], row["shared"]) == (True, True)
    assert rows(james)[job_id]["requested_by"] == ["ethan"]


class SlowSlskd(Slskd):
    """slskd taking its time to accept, so two Gets of one release really are at it together."""

    async def enqueue(self, username, files):
        await asyncio.sleep(0.1)
        return await super().enqueue(username, files)


def test_two_peoples_gets_of_one_release_at_once_make_one_download_under_its_lock(on):
    on.app.state.slskd_client = slskd = SlowSlskd()

    async def go():
        transport = httpx.ASGITransport(app=on.app)
        async with httpx.AsyncClient(transport=transport, base_url="http://deadwax.test") as ethan, \
                httpx.AsyncClient(transport=transport, base_url="http://deadwax.test") as sam:
            for who, name in ((ethan, "ethan"), (sam, "sam")):
                assert (await who.post(LOGIN, json={"username": name, "password": password_of(name)})).status_code == 200
            return await asyncio.gather(ethan.post(ENQUEUE, json=enqueue_body("bob")),
                                        sam.post(ENQUEUE, json=enqueue_body("carol")))

    answers = [answer.json() for answer in run(go())]
    #? one reached slskd and made the job; the other found it under the lock, and joined it
    assert len(slskd.enqueued) == 1
    assert sorted(bool(answer.get("joined")) for answer in answers) == [False, True]
    assert answers[0]["job_id"] == answers[1]["job_id"]
    assert [row[0] for row in requests_on(on.path, answers[0]["job_id"])] == ["ethan", "sam"]


def test_the_same_person_asking_twice_is_still_refused(on):
    james = signed_in(on, "james")
    get(james)
    again = james.post(ENQUEUE, json=enqueue_body(username="carol"))
    assert again.status_code == 409 and again.json()["detail"] == "already downloading from bob"
    assert on.slskd.enqueued == ["bob"]


def test_find_says_whose_the_download_is_and_what_its_copy_is(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    job_id = get(james, quality=QUALITY)["job_id"]
    find = {**RELEASE, "album_artist": None}

    theirs = ethan.post(STORE_STATE, json=find).json()["downloading"]
    assert theirs["job_id"] == job_id and theirs["yours"] is False
    assert (theirs["formats"], theirs["bit_depths"], theirs["sample_rates"]) == (["flac"], [24], [96000])
    assert james.post(STORE_STATE, json=find).json()["downloading"]["yours"] is True

    assert ethan.post(f"{JOBS}/{job_id}/join").json() == {"status": "ok", "job_id": job_id, "joined": True}
    assert ethan.post(STORE_STATE, json=find).json()["downloading"]["yours"] is True
    #? joining twice is no second request
    assert ethan.post(f"{JOBS}/{job_id}/join").json()["joined"] is False
    assert requests_on(on.path, job_id) == [("ethan", 1, 0, 0), ("james", 1, 0, 0)]


def test_find_says_when_somebody_else_waits_for_your_download_too(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    get(ethan)
    find = {**RELEASE, "album_artist": None}
    alone = ethan.post(STORE_STATE, json=find).json()["downloading"]
    assert (alone["yours"], alone["shared"]) == (True, False) and "requested_by" not in alone

    get(james)  # joins it
    theirs = ethan.post(STORE_STATE, json=find).json()["downloading"]
    #? a user is told somebody else waits (their cancel would only leave it) - never who
    assert (theirs["yours"], theirs["shared"]) == (True, True) and "requested_by" not in theirs
    admins = james.post(STORE_STATE, json=find).json()["downloading"]
    assert (admins["yours"], admins["shared"], admins["requested_by"]) == (True, True, ["ethan"])


def test_a_join_a_clear_beats_to_the_write_is_refused_and_leaves_no_request(on, monkeypatch):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    job_id = get(james)["job_id"]
    #? downloaded, about to be filed: still coming (joinable) and finished (clearable) at once
    run(on.store.update_status(job_id, "complete"))
    real, calls = on.store.get_job, []

    async def get_job(asked):
        job = await real(asked)
        calls.append(asked)
        if len(calls) == 2:
            #? the look under the job's lock - and james's Clear (which takes no such lock) lands now
            assert await on.store.hide_finished("james", everyone=True) == (1, 1)
        return job

    monkeypatch.setattr(on.store, "get_job", get_job)
    answer = ethan.post(f"{JOBS}/{job_id}/join")
    assert answer.status_code == 409 and "cleared from the list since" in answer.json()["detail"]
    assert not job_exists(on.path, job_id) and requests_on(on.path, job_id) == []


def test_a_get_that_would_join_a_download_cleared_since_starts_its_own(on, monkeypatch):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    job_id = get(james)["job_id"]
    run(on.store.update_status(job_id, "complete"))
    real = on.store.requesters

    async def requesters(asked):
        found = await real(asked)
        await on.store.hide_finished("james", everyone=True)  # cleared between the look and the join
        return found

    monkeypatch.setattr(on.store, "requesters", requesters)
    answer = get(ethan, username="carol")
    #? nothing left to join: what's true now is nothing on its way, so this Get fetches it
    assert answer["queued"] == 2 and not answer.get("joined") and answer["job_id"] != job_id
    assert requests_on(on.path, job_id) == [] and on.slskd.enqueued == ["bob", "carol"]


def test_request_job_writes_nothing_for_a_job_that_has_gone(tmp_path):
    path = tmp_path / "jobs.db"
    store = JobStore(str(path))
    store.init()
    job_id = run(store.create_job("bob", "d", FILES, RELEASE, user="james"))
    assert run(store.request_job(job_id, "ethan")) == "joined"
    assert run(store.request_job(job_id, "ethan")) == "waiting"
    run(store.update_status(job_id, "organized"))
    run(store.hide_finished("james", everyone=True))
    run(store.hide_finished("ethan"))
    assert not job_exists(path, job_id)
    assert run(store.request_job(job_id, "sam")) == "gone"
    assert requests_on(path, job_id) == []


def test_a_join_deadwax_cant_write_is_a_503_in_words(on, monkeypatch):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    job_id = get(james)["job_id"]

    async def unwritable(job_id, user):
        return None

    monkeypatch.setattr(on.store, "request_job", unwritable)
    answer = ethan.post(f"{JOBS}/{job_id}/join")
    assert answer.status_code == 503
    assert answer.json()["detail"] == "deadwax couldn't write to its database, so you couldn't join it"


def test_a_copy_sent_without_its_quality_is_told_by_its_files(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    get(james)
    theirs = ethan.post(STORE_STATE, json=RELEASE).json()["downloading"]
    assert theirs["formats"] == ["flac"] and "bit_depths" not in theirs


def test_only_a_download_still_coming_and_whole_can_be_joined(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    job_id = get(james)["job_id"]
    run(on.store.update_status(job_id, "organized"))
    answer = ethan.post(f"{JOBS}/{job_id}/join")
    assert answer.status_code == 409 and "filed into the library" in answer.json()["detail"]

    part = get(james, release={**RELEASE, "release_mbid": "rel-part",
                               "tracks": TRACKS + [{"position": 3, "title": "Strangers"}]})["job_id"]
    answer = ethan.post(f"{JOBS}/{part}/join")
    assert answer.status_code == 409 and "only part" in answer.json()["detail"]

    #? no such download: said as cleared - a join has no id to hide (cancel and retry 404)
    answer = ethan.post(f"{JOBS}/999/join")
    assert answer.status_code == 409 and "cleared from the list since" in answer.json()["detail"]
    assert requests_on(on.path, job_id) == [("james", 1, 0, 0)]


def test_a_join_of_a_download_cleared_before_the_tap_says_so(on):
    #? the usual way: ethan's page drew "Already downloading for someone else" with Join; the download
    #? landed and james - the only one who asked - cleared it before ethan tapped
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    job_id = get(james)["job_id"]
    assert ethan.post(STORE_STATE, json=RELEASE).json()["downloading"]["job_id"] == job_id
    run(on.store.update_status(job_id, "organized"))
    assert james.post(f"{JOBS}/clear").json()["removed"] == 1
    assert not job_exists(on.path, job_id)

    answer = ethan.post(f"{JOBS}/{job_id}/join")
    assert answer.status_code == 409
    assert answer.json()["detail"] == "that download has been cleared from the list since - get it again"
    assert requests_on(on.path, job_id) == []


def test_a_failed_download_with_its_retry_pending_is_still_coming(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    job_id = get(james)["job_id"]
    run(on.store.update_status(job_id, "failed", "offline"))

    #? failed, nothing pending: Find doesn't see it downloading, and a Get would start another
    assert ethan.post(STORE_STATE, json=RELEASE).json()["downloading"] is None

    store_index.retry_pending_started(job_id)
    try:
        coming = ethan.post(STORE_STATE, json=RELEASE).json()["downloading"]
        #? moving to its next peer: failed, and nothing claimed to have arrived from it
        assert (coming["job_id"], coming["status"]) == (job_id, "failed") and "done_files" not in coming
        assert get(ethan, username="other")["joined"] is True
    finally:
        store_index.retry_pending_finished(job_id)
    assert store_index.retry_pending() == frozenset()
    assert on.slskd.enqueued == ["bob"]


def test_the_poller_holds_a_failed_job_as_pending_until_its_retry_has_had_its_turn(tmp_path, monkeypatch):
    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()
    job_id = run(store.create_job("bob", "d", FILES, RELEASE,
                                  [{"username": "next", "directory": "d2", "files": FILES, "score": 0.9}]))
    seen = {}

    async def retry(slskd_client, store, job):
        seen["pending"] = store_index.retry_pending()
        seen["coming"] = await store_index.in_flight(store, "rel-dummy", release=RELEASE)

    monkeypatch.setattr(Config, "AUTO_RETRY_PEER", "on")
    monkeypatch.setattr(poller, "_auto_retry", retry)
    run(poller._fail(Slskd(), store, run(store.get_job(job_id)), "offline"))

    assert seen["pending"] == frozenset({job_id}) and seen["coming"]["id"] == job_id
    assert store_index.retry_pending() == frozenset()
    assert run(store.get_job(job_id))["status"] == "failed"

    #? with no retry coming (AUTO_RETRY_PEER off) nothing is pending
    monkeypatch.setattr(Config, "AUTO_RETRY_PEER", "off")
    seen.clear()
    monkeypatch.setattr(poller, "_auto_retry", lambda *a: asyncio.sleep(0, seen.setdefault("pending", store_index.retry_pending())))
    run(poller._fail(Slskd(), store, run(store.get_job(job_id)), "offline"))
    assert seen["pending"] == frozenset()


@pytest.mark.parametrize("how", ["refused", "never reported"])
def test_the_poll_holds_a_failure_pending_while_its_retry_runs(tmp_path, monkeypatch, how):
    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()
    job_id = run(store.create_job("bob", "d", FILES, RELEASE,
                                  [{"username": "next", "directory": "d2", "files": FILES, "score": 0.9}]))
    slskd = Slskd()
    if how == "refused":
        run(slskd.enqueue("bob", FILES))
        slskd.fail("bob")
    else:
        monkeypatch.setattr(poller, "UNMATCHED_GRACE_POLLS", 1)
    seen = {}

    async def retry(slskd_client, store, job):
        seen["pending"] = store_index.retry_pending()
        seen["coming"] = await store_index.in_flight(store, "rel-dummy", release=RELEASE)
        return {"moved": False, "problem": poller.MOVED_ON}

    monkeypatch.setattr(Config, "AUTO_RETRY_PEER", "on")
    monkeypatch.setattr(poller, "retry_next_peer", retry)
    run(poller.poll_downloads_once(slskd, store, {}))

    #? the poll's failure goes through _fail: pending - and so still coming - while the retry runs
    assert seen["pending"] == frozenset({job_id}) and seen["coming"]["id"] == job_id
    assert store_index.retry_pending() == frozenset()
    assert run(store.get_job(job_id))["status"] == "failed"


def test_a_retry_that_raises_leaves_nothing_pending(tmp_path, monkeypatch):
    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()
    job_id = run(store.create_job("bob", "d", FILES, RELEASE,
                                  [{"username": "next", "directory": "d2", "files": FILES, "score": 0.9}]))

    async def boom(slskd_client, store, job):
        raise RuntimeError("database is locked")

    monkeypatch.setattr(Config, "AUTO_RETRY_PEER", "on")
    monkeypatch.setattr(poller, "_auto_retry", boom)
    #? the poll loop logs it; what matters is the job isn't left "still coming" for good
    with pytest.raises(RuntimeError):
        run(poller._fail(Slskd(), store, run(store.get_job(job_id)), "offline"))
    assert store_index.retry_pending() == frozenset()
    assert run(store_index.in_flight(store, "rel-dummy", release=RELEASE)) is None


# ----------------------------------------------------------------- cancel means leave

def test_leaving_keeps_it_for_the_other_and_the_last_leave_cancels_it(on, monkeypatch):
    incomplete = on.tmp / "incomplete"
    partial = incomplete / "bob" / "Dummy" / "01 Mysterons.flac"
    partial.parent.mkdir(parents=True)
    partial.write_bytes(b"half")
    monkeypatch.setattr(Config, "SLSKD_INCOMPLETE_PATH", str(incomplete))
    ethan, sam = signed_in(on, "ethan"), signed_in(on, "sam")
    job_id = get(ethan)["job_id"]
    assert get(sam)["joined"] is True

    left = ethan.post(f"{JOBS}/{job_id}/cancel").json()
    assert left["left"] is True and left["cancelled"] == 0
    #? slskd untouched, the partial kept, the download still going - for sam
    assert on.slskd.cancelled == [] and partial.exists()
    assert run(on.store.get_job(job_id))["status"] == "queued"
    assert rows(ethan) == {} and rows(sam)[job_id]["shared"] is False
    assert ethan.post(f"{JOBS}/{job_id}/cancel").status_code == 404

    last = sam.post(f"{JOBS}/{job_id}/cancel").json()
    assert last["left"] is False and last["cancelled"] == 2 and last["partials_removed"] == 1
    assert not partial.exists()
    assert run(on.store.get_job(job_id))["status"] == "cancelled"
    #? the last one still sees it - cancelled, and theirs to retry
    assert rows(sam)[job_id]["status"] == "cancelled"
    assert requests_on(on.path, job_id) == [("ethan", 1, 1, 0), ("sam", 1, 0, 0)]


def test_leaving_and_asking_again_puts_you_back(on):
    ethan, sam = signed_in(on, "ethan"), signed_in(on, "sam")
    job_id = get(ethan)["job_id"]
    get(sam)

    assert ethan.post(f"{JOBS}/{job_id}/cancel").json()["left"] is True
    #? a Get while it's still on its way: back in, nothing asked of slskd
    assert get(ethan, username="other") == {"status": "ok", "queued": 0, "job_id": job_id, "joined": True}
    assert job_id in rows(ethan) and ("ethan", 1, 0, 0) in requests_on(on.path, job_id)

    assert ethan.post(f"{JOBS}/{job_id}/cancel").json()["left"] is True
    #? and through the join route the same
    assert ethan.post(f"{JOBS}/{job_id}/join").json()["joined"] is True
    assert job_id in rows(ethan) and ("ethan", 1, 0, 0) in requests_on(on.path, job_id)
    assert on.slskd.enqueued == ["bob"]


def test_joining_again_after_clearing_one_still_coming_puts_you_back(on):
    ethan, sam = signed_in(on, "ethan"), signed_in(on, "sam")
    job_id = get(ethan)["job_id"]
    get(sam)
    #? downloaded and about to be filed: finished enough for sam's Clear to hide it, still joinable
    run(on.store.update_status(job_id, "complete"))
    sam.post(f"{JOBS}/clear")
    assert job_id not in rows(sam) and job_id in rows(ethan)
    assert sam.post(f"{JOBS}/{job_id}/join").json()["joined"] is True
    assert job_id in rows(sam) and ("sam", 1, 0, 0) in requests_on(on.path, job_id)


async def sign_in_async(client, name):
    """Sign an httpx client in as `name`, for requests that must really run at once."""
    answer = await client.post(LOGIN, json={"username": name, "password": password_of(name)})
    assert answer.status_code == 200
    return client


def clients(transport):
    return httpx.AsyncClient(transport=transport, base_url="http://deadwax.test")


def test_two_cancels_at_once_from_one_person_leave_once_and_cancel_nothing(on, monkeypatch):
    ethan, sam = signed_in(on, "ethan"), signed_in(on, "sam")
    job_id = get(ethan)["job_id"]
    get(sam)
    real = on.store.requesters

    async def slow(asked):
        #? both cancels past the check of who may act on it before either has left (a double tap)
        found = await real(asked)
        await asyncio.sleep(0.1)
        return found

    monkeypatch.setattr(on.store, "requesters", slow)

    async def go():
        transport = httpx.ASGITransport(app=on.app)
        async with clients(transport) as one, clients(transport) as two:
            await sign_in_async(one, "ethan")
            await sign_in_async(two, "ethan")
            return await asyncio.gather(one.post(f"{JOBS}/{job_id}/cancel"), two.post(f"{JOBS}/{job_id}/cancel"))

    answers = run(go())
    assert sorted(answer.status_code for answer in answers) == [200, 404]
    assert [answer.json()["left"] for answer in answers if answer.status_code == 200] == [True]
    #? sam's download untouched
    assert on.slskd.cancelled == [] and run(on.store.get_job(job_id))["status"] == "queued"


class SlowToCancel(Slskd):
    """slskd taking its time over the transfers a cancel looks up, so a join can try to slip in."""

    async def get_downloads(self, usernames=()):
        await asyncio.sleep(0.2)
        return await super().get_downloads(usernames)


def test_a_join_never_lands_between_the_last_leave_and_the_cancel(on):
    slskd = on.app.state.slskd_client = SlowToCancel()
    sam = signed_in(on, "sam")
    job_id = get(sam)["job_id"]

    async def go():
        transport = httpx.ASGITransport(app=on.app)
        async with clients(transport) as leaving, clients(transport) as joining:
            await sign_in_async(leaving, "sam")
            await sign_in_async(joining, "ethan")

            async def join_late():
                await asyncio.sleep(0.05)
                return await joining.post(f"{JOBS}/{job_id}/join")
            return await asyncio.gather(leaving.post(f"{JOBS}/{job_id}/cancel"), join_late())

    cancelled, joined = run(go())
    assert cancelled.json()["left"] is False and slskd.cancelled
    #? the join waited for the job's lock, and found it cancelled - no request on a dead download
    assert joined.status_code == 409 and "cancelled" in joined.json()["detail"]
    assert requests_on(on.path, job_id) == [("sam", 1, 0, 0)]


class SlowToEnqueue(Slskd):
    """slskd taking its time to accept the next peer, so a cancel arrives while a retry holds the job's lock."""

    async def enqueue(self, username, files):
        if username != "bob":
            await asyncio.sleep(0.3)
        return await super().enqueue(username, files)


@pytest.mark.parametrize("canceller", ["james", "ethan"])
def test_a_cancel_behind_a_retry_cancels_the_peer_it_moved_to(on, canceller):
    #? the cancel read the job before the lock (bob's); it must cancel what the job is once it has the
    #? lock - next1's - or next1's download runs on in slskd for nobody under a job marked cancelled
    slskd = on.app.state.slskd_client = SlowToEnqueue()
    alternatives = [{"username": "next1", "directory": "share\\Dummy1", "files": FILES, "score": 0.8}]
    job_id = get(signed_in(on, "ethan"), alternatives=alternatives)["job_id"]
    run(on.store.update_status(job_id, "failed", "offline"))
    slskd.fail("bob")

    async def go():
        transport = httpx.ASGITransport(app=on.app)
        async with clients(transport) as retrying, clients(transport) as cancelling:
            await sign_in_async(retrying, "ethan")
            await sign_in_async(cancelling, canceller)

            async def cancel_late():
                await asyncio.sleep(0.1)
                return await cancelling.post(f"{JOBS}/{job_id}/cancel")
            return await asyncio.gather(retrying.post(f"{JOBS}/{job_id}/retry"), cancel_late())

    moved, cancelled = run(go())
    assert moved.json()["moved"] is True and cancelled.json()["left"] is False
    #? next1's transfers cancelled (bob's go too: the retry's own tidy of the attempt it left)
    assert {("next1", "next1-0"), ("next1", "next1-1")} <= set(slskd.cancelled), slskd.cancelled
    job = run(on.store.get_job(job_id))
    assert job["status"] == "cancelled" and job["username"] == "next1"


def test_an_admins_cancel_is_for_everyone(on):
    james, ethan, sam = signed_in(on, "james"), signed_in(on, "ethan"), signed_in(on, "sam")
    job_id = get(ethan)["job_id"]
    get(sam)
    answer = james.post(f"{JOBS}/{job_id}/cancel").json()
    assert answer["left"] is False and answer["cancelled"] == 2
    assert run(on.store.get_job(job_id))["status"] == "cancelled"
    assert rows(ethan)[job_id]["status"] == rows(sam)[job_id]["status"] == "cancelled"


def test_a_shared_job_the_admin_asked_for_too_is_still_cancelled_for_everyone(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    job_id = get(james)["job_id"]
    get(ethan)
    assert james.post(f"{JOBS}/{job_id}/cancel").json()["left"] is False
    assert rows(ethan)[job_id]["status"] == "cancelled"


def test_two_last_requesters_leaving_at_once_cancel_it_once(on):
    ethan, sam = signed_in(on, "ethan"), signed_in(on, "sam")
    job_id = get(ethan)["job_id"]
    get(sam)

    async def both():
        return await asyncio.gather(on.store.leave_job(job_id, "ethan"), on.store.leave_job(job_id, "sam"))

    assert sorted(run(both())) == ["last", "left"]


# ----------------------------------------------------------------- retry, by any requester

def test_retry_by_either_moves_the_one_download_and_everyone_with_it(on):
    ethan, sam = signed_in(on, "ethan"), signed_in(on, "sam")
    alternatives = [{"username": f"next{n}", "directory": f"share\\Dummy{n}", "files": FILES, "score": 0.8,
                     "quality": {"formats": ["flac"], "bit_depths": [16]}} for n in (1, 2)]
    job_id = get(ethan, alternatives=alternatives, quality=QUALITY)["job_id"]
    get(sam)
    run(on.store.update_status(job_id, "failed", "offline"))
    on.slskd.fail("bob")

    moved = sam.post(f"{JOBS}/{job_id}/retry").json()
    assert moved["moved"] is True and moved["username"] == "next1"
    assert rows(ethan)[job_id]["username"] == rows(sam)[job_id]["username"] == "next1"
    #? the job takes on the new folder's quality
    assert run(on.store.get_job(job_id))["quality"]["bit_depths"] == [16]

    run(on.store.update_status(job_id, "failed", "offline again"))
    on.slskd.fail("next1")
    again = ethan.post(f"{JOBS}/{job_id}/retry_same").json()
    assert again["retried"] is True
    #? the same peer asked again: the same copy, so the job keeps its quality
    assert run(on.store.get_job(job_id))["quality"]["bit_depths"] == [16]
    assert rows(sam)[job_id]["status"] == rows(ethan)[job_id]["status"] == "queued"
    assert requests_on(on.path, job_id) == [("ethan", 1, 0, 0), ("sam", 1, 0, 0)]


def test_an_admin_may_retry_anybodys(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    job_id = get(ethan)["job_id"]
    run(on.store.update_status(job_id, "failed", "offline"))
    on.slskd.fail("bob")
    assert james.post(f"{JOBS}/{job_id}/retry_same").json()["retried"] is True


# ----------------------------------------------------------------- Everyone's downloads, given (2.0.0-player.61)

def given(on, name: str, **wanted) -> TestClient:
    """`name` signed in after an admin gave them these permissions in People - bound to their account, so honoured."""
    permissions.set_for(on.store, name, on.fake.ids[name], {"request": True, "edit": False, "library": False,
                                                            "downloads": False, "server": False, **wanted}, "james")
    return signed_in(on, name)


def test_everyones_downloads_given_is_an_admins_view_of_them(on):
    """An ordinary person given Everyone's downloads: everyone's rows saying who asked, another's job reached,
    a cancel for everyone, a clear of everyone's finished - as an admin's. Without it, their own."""
    ethan, sam = given(on, "ethan", downloads=True), signed_in(on, "sam")
    theirs = get(sam, release={**RELEASE, "release_mbid": "rel-sams"})["job_id"]
    shared = get(sam, release={**RELEASE, "release_mbid": "rel-shared"})["job_id"]
    seen = rows(ethan)
    assert set(seen) == {theirs, shared} and seen[theirs]["requested_by"] == ["sam"] and seen[theirs]["mine"] is False
    #? cancel for everyone, not leave
    answer = ethan.post(f"{JOBS}/{shared}/cancel").json()
    assert answer["left"] is False and run(on.store.get_job(shared))["status"] == "cancelled"
    #? clear everyone's finished - for himself alone, as an admin's clear is
    run(on.store.update_status(theirs, "organized"))
    assert ethan.post(f"{JOBS}/clear").json()["removed"] == 2
    assert theirs in rows(sam)
    #? taken away: his own again, the rest not found
    permissions.set_for(on.store, "ethan", "id-ethan", {"request": True, "edit": False, "library": False,
                                                        "downloads": False, "server": False}, "james")
    other = get(sam, release={**RELEASE, "release_mbid": "rel-other"})["job_id"]
    assert other not in rows(ethan) and "requested_by" not in str(rows(ethan))
    assert ethan.post(f"{JOBS}/{other}/cancel").status_code == 404


def test_retrying_someone_elses_download_needs_get_albums_too(on):
    """Everyone's downloads reaches another's job; a retry starts a download, so it needs Get albums as well."""
    sam = signed_in(on, "sam")
    job_id = get(sam)["job_id"]
    run(on.store.update_status(job_id, "failed", "offline"))
    on.slskd.fail("bob")
    ethan = given(on, "ethan", downloads=True, request=False)
    for action in ("retry", "retry_same"):
        answer = ethan.post(f"{JOBS}/{job_id}/{action}")
        assert answer.status_code == 403 and "Get albums" in answer.json()["detail"], action
    #? and seeing it is still his
    assert job_id in rows(ethan)
    permissions.set_for(on.store, "ethan", "id-ethan", {"request": True, "edit": False, "library": False,
                                                        "downloads": True, "server": False}, "james")
    assert ethan.post(f"{JOBS}/{job_id}/retry_same").json()["retried"] is True


def test_get_albums_taken_away_refuses_every_start_but_leaves_your_own_list(on):
    ethan = signed_in(on, "ethan")
    job_id = get(ethan)["job_id"]
    permissions.set_for(on.store, "ethan", "id-ethan", {"request": False, "edit": False, "library": False,
                                                        "downloads": False, "server": False}, "james")
    #? a restriction is by name: in force at once, no sign-in, no account id needed
    answer = ethan.post(ENQUEUE, json=enqueue_body(release={**RELEASE, "release_mbid": "rel-new"}))
    assert answer.status_code == 403 and answer.json()["detail"] == (
        "That needs Get albums, which an admin hasn't given you. You're signed in as ethan.")
    assert ethan.post("/deadwax/download/find_candidates", json={}).status_code == 403
    assert ethan.post(f"{JOBS}/{job_id}/join").status_code == 403
    assert job_id in rows(ethan) and ethan.post(f"{JOBS}/{job_id}/cancel").status_code == 200


# ----------------------------------------------------------------- clear finished hides it for you

def test_clearing_hides_it_for_you_and_it_goes_once_everyone_has(on):
    ethan, sam = signed_in(on, "ethan"), signed_in(on, "sam")
    job_id = get(ethan)["job_id"]
    get(sam)
    run(on.store.update_status(job_id, "organized"))

    assert ethan.post(f"{JOBS}/clear").json() == {"status": "ok", "removed": 1}
    assert rows(ethan) == {} and job_id in rows(sam)
    assert job_exists(on.path, job_id)

    assert sam.post(f"{JOBS}/clear").json()["removed"] == 1
    assert rows(sam) == {}
    assert not job_exists(on.path, job_id) and requests_on(on.path, job_id) == []


def test_clearing_leaves_what_is_still_moving(on):
    ethan = signed_in(on, "ethan")
    job_id = get(ethan)["job_id"]
    assert ethan.post(f"{JOBS}/clear").json()["removed"] == 0
    assert job_id in rows(ethan)


def test_an_admins_clear_of_somebody_elses_hides_it_for_the_admin_alone(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    job_id = get(ethan)["job_id"]
    run(on.store.update_status(job_id, "organized"))

    assert james.post(f"{JOBS}/clear").json()["removed"] == 1
    assert job_id not in rows(james) and job_id in rows(ethan)
    #? the admin's row is no request: it never keeps the job, nor counts as asking
    assert requests_on(on.path, job_id) == [("ethan", 1, 0, 0), ("james", 0, 0, 1)]

    ethan.post(f"{JOBS}/clear")
    assert not job_exists(on.path, job_id)


def test_a_download_an_admin_cleared_shows_again_once_it_is_retried(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    job_id = get(ethan)["job_id"]
    run(on.store.update_status(job_id, "failed", "offline"))
    on.slskd.fail("bob")
    james.post(f"{JOBS}/clear")
    assert job_id not in rows(james)

    assert ethan.post(f"{JOBS}/{job_id}/retry_same").json()["retried"] is True
    assert job_id in rows(james)
    assert requests_on(on.path, job_id) == [("ethan", 1, 0, 0)]


def test_a_retried_download_stays_cleared_for_a_user_who_cleared_it_but_shows_again_for_an_admin(on):
    james, ethan, sam = signed_in(on, "james"), signed_in(on, "ethan"), signed_in(on, "sam")
    job_id = get(james)["job_id"]
    get(ethan)
    get(sam)
    run(on.store.update_status(job_id, "failed", "offline"))
    on.slskd.fail("bob")
    #? james (who asked too) and sam give up on it; ethan still waits
    james.post(f"{JOBS}/clear")
    sam.post(f"{JOBS}/clear")
    assert job_id not in rows(james) and job_id not in rows(sam)

    assert ethan.post(f"{JOBS}/{job_id}/retry_same").json()["retried"] is True
    #? on its way again: the admin sees everyone's - it, as ethan's alone - and can cancel it
    seen = rows(james)[job_id]
    assert (seen["status"], seen["mine"], seen["requested_by"]) == ("queued", False, ["ethan"])
    #? a user who had given up on it isn't waiting for it, and stays cleared
    assert job_id not in rows(sam)
    assert requests_on(on.path, job_id) == [("ethan", 1, 0, 0), ("james", 1, 1, 0), ("sam", 1, 1, 0)]
    #? until they ask again
    assert get(sam, username="other")["joined"] is True and job_id in rows(sam)


def test_a_cancelled_download_is_taken_out_of_slskds_list_only_when_clearing_deletes_it(on, monkeypatch):
    ethan, sam = signed_in(on, "ethan"), signed_in(on, "sam")
    job_id = get(ethan)["job_id"]
    get(sam)
    run(on.store.update_status(job_id, "cancelled", "cancelled from deadwax"))
    tidied = []

    async def tidy(slskd_client, jobs):
        tidied.append([job["id"] for job in jobs])
        return 0, 0

    monkeypatch.setattr("src.routes.download.tidy_cancelled_transfers", tidy)
    ethan.post(f"{JOBS}/clear")
    assert tidied == []
    sam.post(f"{JOBS}/clear")
    assert tidied == [[job_id]]


# ----------------------------------------------------------------- one search starts at a time

class OneStartAtATime:
    """slskd's searches: a second START while one is starting is refused 429, as slskd's Wait(0) does."""

    def __init__(self, hold=0.2):
        self.hold = hold
        self.starting = threading.Lock()
        self.started: list[str] = []
        self.refused: list[str] = []

    def search_text(self, searchText, **kwargs):
        if not self.starting.acquire(blocking=False):
            self.refused.append(searchText)
            response = requests.Response()
            response.status_code = 429
            response._content = b'"Only one search is allowed at a time"'
            raise requests.exceptions.HTTPError("429 Client Error", response=response)
        try:
            time.sleep(self.hold)
            self.started.append(searchText)
            return {"id": f"id:{searchText}"}
        finally:
            self.starting.release()

    def state(self, search_id, **kwargs):
        return {"isComplete": True}

    def search_responses(self, search_id):
        return []

    def delete(self, search_id):
        return True


def test_two_peoples_finds_at_once_both_search_their_starts_in_turn(on):
    searches = OneStartAtATime()
    client = SlskdClient()
    client.client = SimpleNamespace(searches=searches, application=SimpleNamespace(state=lambda: {}))
    on.app.state.slskd_client = client

    async def go():
        transport = httpx.ASGITransport(app=on.app)
        async with httpx.AsyncClient(transport=transport, base_url="http://deadwax.test") as james, \
                httpx.AsyncClient(transport=transport, base_url="http://deadwax.test") as ethan:
            for who, name in ((james, "james"), (ethan, "ethan")):
                assert (await who.post(LOGIN, json={"username": name, "password": password_of(name)})).status_code == 200
            return await asyncio.gather(
                james.post("/deadwax/download/find_candidates", json={"artist": "Portishead", "album": "Dummy"}),
                ethan.post("/deadwax/download/find_candidates", json={"artist": "Massive Attack", "album": "Mezzanine"}),
            )

    answers = run(go())
    assert [answer.status_code for answer in answers] == [200, 200], [answer.text for answer in answers]
    assert searches.refused == []
    assert sorted(searches.started) == ["Massive Attack Mezzanine", "Portishead Dummy"]


def test_the_wait_for_a_turn_is_bounded_and_never_refuses(caplog):
    gate = SearchGate(bound=0.05)
    order = []

    async def go():
        async def start(name, pause):
            await asyncio.sleep(pause)
            async with gate.turn(name):
                order.append(f"{name} in")
                await asyncio.sleep(0.3)
                order.append(f"{name} out")

        await asyncio.gather(start("first", 0), start("second", 0.01), start("third", 0.02))

    caplog.set_level(logging.WARNING)
    run(go())
    #? the first gave up its turn after the bound and the second took it; the third waited its own
    #? bound behind the second, then started anyway - nobody refused, nobody waited the 0.3s out
    assert order == ["first in", "second in", "third in", "first out", "second out", "third out"]
    assert "the Soulseek search for 'first' has taken over" in caplog.text
    assert "starting 'third' anyway" in caplog.text
    assert slskd_endpoint.SEARCH_TURN_SECONDS >= 10


def test_a_start_that_never_finishes_holds_up_the_line_once_not_for_ever(caplog):
    #? slskd_api sends with no timeout, so a POST never answered leaves its start in a thread for good;
    #? its turn gives itself up after the bound rather than every start after it waiting the bound
    gate = SearchGate(bound=0.2)
    waits = []

    async def go():
        forever = asyncio.Event()

        async def stuck():
            async with gate.turn("stuck"):
                await forever.wait()

        hung = asyncio.ensure_future(stuck())
        await asyncio.sleep(0.05)
        for n in range(4):
            began = time.monotonic()
            async with gate.turn(f"later {n}"):
                waits.append(time.monotonic() - began)

        #? when the stuck start does end, it leaves whoever holds the gate by then holding it
        async with gate.turn("holder"):
            forever.set()
            await hung
            assert gate._lock.locked()
        assert not gate._lock.locked()

    caplog.set_level(logging.WARNING)
    run(go())
    assert waits[0] < 0.2 and max(waits[1:]) < 0.05, waits
    assert caplog.text.count("letting the next one start") == 1
    assert "the Soulseek search for 'stuck' has taken over" in caplog.text
    assert "anyway" not in caplog.text


def test_a_turn_that_ended_in_time_leaves_no_timer_behind():
    #? a stale give-up would release a later turn's hold and let the one after it in early
    gate = SearchGate(bound=0.2)
    order = []

    async def go():
        async def start(name, pause, hold):
            await asyncio.sleep(pause)
            async with gate.turn(name):
                order.append(f"{name} in")
                await asyncio.sleep(hold)
                order.append(f"{name} out")

        await asyncio.gather(start("a", 0, 0.01), start("b", 0.02, 0.12),
                             start("c", 0.05, 0.12), start("d", 0.15, 0.01))

    run(go())
    assert order == ["a in", "a out", "b in", "b out", "c in", "c out", "d in", "d out"]


def test_the_gate_lets_the_next_start_in_as_soon_as_one_has(caplog):
    gate = SearchGate(bound=5)
    order = []

    async def go():
        async def start(name, pause):
            await asyncio.sleep(pause)
            async with gate.turn(name):
                order.append(f"{name} in")
                await asyncio.sleep(0.05)
                order.append(f"{name} out")

        await asyncio.gather(start("a", 0), start("b", 0.01))

    caplog.set_level(logging.WARNING)
    run(go())
    assert order == ["a in", "a out", "b in", "b out"]
    assert "anyway" not in caplog.text


# ----------------------------------------------------------------- organizing must be on

@pytest.mark.parametrize("mode", ["dry_run", "off"])
def test_logins_are_refused_while_nothing_would_be_filed(on, monkeypatch, mode):
    monkeypatch.setattr(Config, "ORGANIZE_MODE", mode)
    client = TestClient(on.app)
    for answer in (client.get("/deadwax/me"), client.get(JOBS),
                   client.post(LOGIN, json={"username": "james", "password": PASSWORDS["james"]})):
        assert answer.status_code == 503
        #? (2.0.4) the setting for whoever runs deadwax (`why`); the sentence for anyone (src/auth.py Explained)
        assert answer.json()["detail"] == auth.CANT_SIGN_IN
        assert f"ORGANIZE_MODE is '{mode}'" in answer.json()["why"] and "copy or move" in answer.json()["why"]
    #? the health check judges deadwax alone, and the pages still draw (the sign-in shows why)
    assert client.get("/deadwax/health").status_code == 200
    assert client.get("/player/").status_code == 200


def test_a_signed_in_session_is_refused_too_once_organizing_is_off(on, monkeypatch):
    james = signed_in(on, "james")
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "dry_run")
    assert james.get(JOBS).status_code == 503


@pytest.mark.parametrize("folder", ["LIBRARY_PATH", "SLSKD_DOWNLOAD_PATH"])
def test_logins_are_refused_without_organizings_folders(on, monkeypatch, folder):
    #? either folder missing and organizing_enabled() is False: nothing would ever be filed
    monkeypatch.setattr(Config, folder, None)
    client = TestClient(on.app)
    for answer in (client.get("/deadwax/me"),
                   client.post(LOGIN, json={"username": "james", "password": PASSWORDS["james"]})):
        assert answer.status_code == 503 and f"{folder} is not set" in answer.json()["why"]


def test_start_up_says_why_and_where_to_change_it(on, monkeypatch, caplog):
    caplog.set_level(logging.INFO)
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "dry_run")
    monkeypatch.setattr(Config, "OVERRIDDEN", set())
    Config.report_logins()
    assert "logins are on but ORGANIZE_MODE is 'dry_run'" in caplog.text
    assert "set ORGANIZE_MODE=copy or move in the container's environment" in caplog.text

    #? saved in the settings tab, which beats the environment: the way back is through logins off
    monkeypatch.setattr(Config, "OVERRIDDEN", {"ORGANIZE_MODE"})
    assert "switch logins off" in Config.describe_logins_organizing()
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "move")
    assert Config.describe_logins_organizing() is None


def test_the_settings_tab_wont_switch_organizing_off_under_logins(on, monkeypatch):
    james = signed_in(on, "james")
    for update in ({"key": "ORGANIZE_MODE", "value": "dry_run"}, {"key": "ORGANIZE_MODE", "value": "off"},
                   {"key": "LIBRARY_PATH", "value": ""}, {"key": "SLSKD_DOWNLOAD_PATH", "value": ""}):
        answer = james.put("/deadwax/settings", json=[update])
        assert answer.status_code == 400, update
        assert "they need organizing to stay on" in answer.json()["detail"]
    assert on.store.stored_settings() == {}

    #? a revert to an environment that says dry_run would switch it off too
    monkeypatch.setattr(Config, "ENV_VALUES", {"ORGANIZE_MODE": "dry_run", "LIBRARY_PATH": str(on.tmp / "library"),
                                               "SLSKD_DOWNLOAD_PATH": str(on.tmp / "slskd")})
    assert james.put("/deadwax/settings", json=[{"key": "ORGANIZE_MODE", "value": None}]).status_code == 400
    monkeypatch.setattr(Config, "ENV_VALUES", {})

    assert james.put("/deadwax/settings", json=[{"key": "ORGANIZE_MODE", "value": "move"}]).status_code == 200
    Config.apply_overrides({})


def test_with_logins_off_dry_run_is_as_it_always_was(monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "dry_run")
    assert Config.describe_logins_organizing() is not None
    assert auth.unusable() is not None  # what logins WOULD say - but nothing asks with them off
    client = TestClient(start())
    assert client.get("/deadwax/me").status_code == 200


def test_with_logins_off_the_settings_tab_saves_organizing_as_it_always_did(monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "copy")
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "library"))
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "slskd"))
    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()
    app = start()
    app.state.store = store
    client = TestClient(app)
    try:
        for update in ({"key": "ORGANIZE_MODE", "value": "dry_run"}, {"key": "SLSKD_DOWNLOAD_PATH", "value": ""}):
            assert client.put("/deadwax/settings", json=[update]).status_code == 200, update
    finally:
        Config.apply_overrides({})


# ----------------------------------------------------------------- logins off is today

def test_logins_off_one_user_and_every_row_as_it_was(monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    monkeypatch.setattr(Config, "SLSKD_INCOMPLETE_PATH", None)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "library"))
    store = JobStore(str(tmp_path / "jobs.db"))
    store.init()
    app = start()
    app.state.store = store
    app.state.slskd_client = Slskd()
    client = TestClient(app)

    job_id = client.post(ENQUEUE, json=enqueue_body()).json()["job_id"]
    assert client.post(ENQUEUE, json=enqueue_body(username="carol")).status_code == 409
    row = rows(client)[job_id]
    assert not {"mine", "shared", "requested_by"} & row.keys()
    assert client.post(STORE_STATE, json=RELEASE).json()["downloading"] == {
        "job_id": job_id, "status": "queued", "username": "bob", "files": 2, "done_files": 0}

    #? cancel is the download's, at once - the one user is the admin
    assert client.post(f"{JOBS}/{job_id}/cancel").json()["left"] is False
    assert run(store.get_job(job_id))["status"] == "cancelled"
    #? and clearing forgets it, as it always did
    assert client.post(f"{JOBS}/clear").json()["removed"] == 1
    assert run(store.list_jobs()) == []
    assert not Path(tmp_path / "jobs.db").stat().st_size == 0


def test_logins_switched_off_again_are_one_user_as_they_always_were(on, monkeypatch):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    theirs = get(ethan, release={**RELEASE, "release_mbid": "rel-theirs"})["job_id"]
    run(on.store.update_status(theirs, "organized"))
    stopped = get(ethan, release={**RELEASE, "release_mbid": "rel-stopped"})["job_id"]
    run(on.store.update_status(stopped, "cancelled", "cancelled from deadwax"))
    mine = get(james, release={**RELEASE, "release_mbid": "rel-mine"})["job_id"]
    run(on.store.update_status(mine, "organized"))
    coming = get(ethan)["job_id"]
    tidied = []

    async def tidy(slskd_client, jobs):
        tidied.extend(job["id"] for job in jobs)
        return 0, 0

    monkeypatch.setattr("src.routes.download.tidy_cancelled_transfers", tidy)
    #? AUTH_MODE=off - the way back troubleshooting gives - and the one user is `local` again
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    local = TestClient(on.app)
    assert set(rows(local)) == {theirs, stopped, mine, coming}
    assert not {"mine", "shared", "requested_by"} & rows(local)[coming].keys()

    #? a Get of a pressing somebody asked for while logins were on is refused, as before - not joined
    again = local.post(ENQUEUE, json=enqueue_body(username="carol"))
    assert again.status_code == 409 and again.json()["detail"] == "already downloading from bob"
    assert requests_on(on.path, coming) == [("ethan", 1, 0, 0)]

    #? and Clear forgets every finished download, whoever asked - its transfers tidied first
    assert local.post(f"{JOBS}/clear").json()["removed"] == 3
    assert tidied == [stopped]
    for gone in (theirs, stopped, mine):
        assert not job_exists(on.path, gone) and requests_on(on.path, gone) == []
    assert set(rows(local)) == {coming}
