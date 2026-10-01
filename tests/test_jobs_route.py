"""
What GET /deadwax/download/jobs gives the app's Requests tab (2.0.0-player.12).

Each row gains what the tab draws that the downloads panel never needed:

- `release_mbid` (a cover from the Cover Art Archive) and `updated_at` ("12 minutes ago") -
  list_jobs always read both; the route dropped them.
- `release_group_mbid` and `edition` ("Dummy · 2014 vinyl"), read out of the stored release BY
  SQLITE (json_extract): the poll runs twice a second while the tab shows, and v0.9.24 took the
  stored release out of it for its cost - decoding it again here would put that back. The
  edition is the one set by hand, else MusicBrainz's disambiguation; a blank is none; a row whose
  release isn't JSON gives neither and doesn't fail the poll.
- `outcome` - filed | already_there | partly_filed | interrupted | failed, or null while going
  and for any other ending - from the status and poller.py's NAMED messages, so "Already in your
  library" is never parsed out of free text. Held both on the messages as written and on the
  messages the poller actually writes as it files.

Through the whole app start() builds (no lifespan, so nothing connects), with a real SQLite store
and a fake slskd on app.state.
"""

import asyncio
import json

import pytest
from fastapi.testclient import TestClient

from src import poller, store as store_module
from src.api.app import start
from src.config import Config
from src.poller import (ALREADY_THERE, FAILED_TO_ORGANIZE, INTERRUPTED_FILING, NO_TRACK_FILED, NOTHING_FILED,
                        job_outcome, poll_downloads_once)
from src.store import JobStore

ROUTE = "/deadwax/download/jobs"
FILES = [{"filename": f"share\\Dummy\\0{n}.flac", "size": 10} for n in (1, 2)]
#? a string that appears in the stored release and nowhere else, to see whether it was decoded
MARKER = "only-in-the-stored-release"


def release(**overrides) -> dict:
    return {
        "artist": "Portishead", "album": "Dummy", "year": "2014", "release_mbid": "rel-dummy-vinyl",
        "release_group_mbid": "rg-dummy", "disambiguation": "2014 vinyl", "edition_label": None,
        "tracks": [{"position": 1, "title": MARKER}], **overrides,
    }


class Slskd:
    """slskd, holding a transfer list per user, answering only for the users it's asked about."""

    def __init__(self, transfers=None):
        self.transfers = transfers or {}
        self.asked: list[list[str]] = []

    async def get_downloads(self, usernames=()):
        names = sorted(set(usernames))
        self.asked.append(names)
        return [{"username": name, "directories": [{"directory": "d", "files": self.transfers[name]}]}
                for name in names if name in self.transfers]

    async def queue_position(self, username, transfer_id):
        return 4


def run(awaitable):
    return asyncio.run(awaitable)


@pytest.fixture
def store(tmp_path):
    job_store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    job_store.init()
    return job_store


def client(store, slskd=None):
    app = start()
    app.state.store = store
    app.state.slskd_client = slskd or Slskd()
    return TestClient(app)  # no `with`: no lifespan, so nothing connects


def job(store, status="queued", error=None, username="bob", **overrides) -> int:
    async def go():
        job_id = await store.create_job(username, "share\\Dummy", FILES, release(**overrides), [])
        if status != "queued" or error:
            await store.update_status(job_id, status, error)
        return job_id
    return run(go())


def rows(store, slskd=None) -> dict[int, dict]:
    answer = client(store, slskd).get(ROUTE)
    assert answer.status_code == 200
    return {row["id"]: row for row in answer.json()["jobs"]}


def test_every_row_carries_its_release_group_edition_and_when_it_last_moved(store):
    job_id = job(store, status="organized")
    stored = run(store.get_job(job_id))

    row = rows(store)[job_id]

    assert (row["release_mbid"], row["release_group_mbid"], row["edition"]) == ("rel-dummy-vinyl", "rg-dummy", "2014 vinyl")
    assert row["updated_at"] == stored["updated_at"]
    #? the old fields are all still there
    assert {"id", "artist", "album", "year", "username", "status", "error", "created_at", "progress",
            "files_done", "files_total", "attempt"} <= row.keys()


def test_the_edition_set_by_hand_beats_the_disambiguation_and_a_blank_is_none(store):
    by_hand = job(store, status="organized", edition_label="The Experience edition")
    blank_label = job(store, status="organized", edition_label="  ")
    neither = job(store, status="organized", disambiguation="", edition_label=None)
    no_group = job(store, status="organized", release_group_mbid=None, release_mbid=None)

    found = rows(store)

    assert found[by_hand]["edition"] == "The Experience edition"
    assert found[blank_label]["edition"] == "2014 vinyl", "a blank label falls through to the disambiguation"
    assert found[neither]["edition"] is None
    assert (found[no_group]["release_group_mbid"], found[no_group]["release_mbid"]) == (None, None)


def test_a_row_whose_release_is_not_json_is_listed_without_them(store):
    broken = job(store, status="organized")
    fine = job(store, status="organized")
    with store._connect() as connection:
        connection.execute("UPDATE jobs SET release_json = 'not json {' WHERE id = ?", (broken,))

    found = rows(store)

    assert (found[broken]["release_group_mbid"], found[broken]["edition"]) == (None, None)
    assert found[broken]["release_mbid"] == "rel-dummy-vinyl", "the column, not the JSON"
    assert found[fine]["edition"] == "2014 vinyl", "one bad row doesn't take the others with it"


def test_list_jobs_still_decodes_no_stored_release(store, monkeypatch):
    """The poll's cost (v0.9.24): SQLite reads the two fields; Python never parses the release."""
    job(store, status="organized")
    job(store, status="failed", error="the peer went offline")
    parsed: list[str] = []
    real_loads = json.loads

    def loads(text, *args, **kwargs):
        parsed.append(text)
        return real_loads(text, *args, **kwargs)

    monkeypatch.setattr(store_module.json, "loads", loads)

    listed = run(store.list_jobs())

    assert len(listed) == 2
    assert all("release" not in row and "release_json" not in row for row in listed)
    assert not [text for text in parsed if MARKER in str(text)], "the stored release was decoded"
    assert parsed, "the loads that were made were seen (files, runners-up, tried)"
    assert [row["edition"] for row in listed] == ["2014 vinyl", "2014 vinyl"]


def test_each_outcome_from_the_status_and_the_named_messages(store):
    cases = {
        "filed": ("organized", None),
        "already_there": ("complete", f"{ALREADY_THERE}: all 10 track(s) were already there, {NOTHING_FILED}"),
        "partly_filed": ("complete", f"2 {FAILED_TO_ORGANIZE}"),
        "interrupted": ("complete", INTERRUPTED_FILING),
        "failed": ("failed", "the peer went offline"),
        "cancelled": ("cancelled", "cancelled from deadwax"),
        "no track filed": ("complete", f"3 {FAILED_TO_ORGANIZE}, {NO_TRACK_FILED}"),
        "dry run": ("complete", "dry run - not organized"),
        "organizing off": ("complete", None),
        "nothing to file": ("complete", "nothing could be organized, check SLSKD_DOWNLOAD_PATH"),
        "filing raised": ("complete", "organize failed: disk on fire"),
        "queued": ("queued", None),
        "downloading": ("downloading", None),
        "organizing": ("organizing", None),
    }
    ids = {name: job(store, status, error) for name, (status, error) in cases.items()}

    found = rows(store)

    assert {name: found[job_id]["outcome"] for name, job_id in ids.items()} == {
        "filed": "filed",
        "already_there": "already_there",
        "partly_filed": "partly_filed",
        "interrupted": "interrupted",
        "failed": "failed",
        "cancelled": "failed",
        "no track filed": None,
        "dry run": None,
        "organizing off": None,
        "nothing to file": None,
        "filing raised": None,
        "queued": None,
        "downloading": None,
        "organizing": None,
    }


def test_free_text_that_merely_mentions_a_message_is_not_that_outcome():
    assert job_outcome("complete", "the peer said: already in the store") is None
    assert job_outcome("complete", f"2 {FAILED_TO_ORGANIZE} and more") is None
    assert job_outcome("complete", INTERRUPTED_FILING + " twice") is None
    #? the status decides first: a failed job is failed whatever its words
    assert job_outcome("failed", f"{ALREADY_THERE}: all 3 track(s)") == "failed"
    assert job_outcome("organized", "anything") == "filed"
    assert job_outcome(None, None) is None


@pytest.mark.parametrize("results, message, outcome", [
    ({"organized": 2, "failed": 0, "skipped": 0}, None, "filed"),
    ({"organized": 0, "failed": 0, "skipped": 10, "duplicates": 10},
     "already in the store: all 10 track(s) were already there, nothing was filed", "already_there"),
    ({"organized": 1, "failed": 1, "skipped": 0}, "1 file(s) failed to organize", "partly_filed"),
    ({"organized": 2, "tracks_organized": 1, "failed": 1, "skipped": 0}, "1 file(s) failed to organize", "partly_filed"),
    ({"organized": 0, "tracks_organized": 0, "failed": 2, "skipped": 0}, "2 file(s) failed to organize, no track was filed", None),
    #? every track failed and only the cover landed: a folder, but none of the album in the library
    ({"organized": 1, "tracks_organized": 0, "failed": 2, "skipped": 0}, "2 file(s) failed to organize, no track was filed", None),
    ({"organized": 0, "failed": 0, "skipped": 3}, "all 3 file(s) already existed, nothing was filed", None),
    ({"organized": 2, "failed": 0, "skipped": 0, "dry_run": True}, "dry run - not organized", None),
])
def test_the_messages_the_poller_writes_read_back_as_their_outcome(store, monkeypatch, tmp_path, results, message, outcome):
    """
    The poller's own words, as it files - not a copy of them: the outcome and the messages come
    from the same constants, and this holds the two to one answer end to end.
    """
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "downloads"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "copy")
    monkeypatch.setattr(Config, "FETCH_LYRICS", "off")

    async def organize(job, download_root, library_root, mode, on_plan=None):
        return {"dry_run": False, "mode": mode, "plan": {}, **results}

    monkeypatch.setattr(poller, "organize_job", organize)
    job_id = job(store)
    done = [{"filename": f["filename"], "state": "Completed, Succeeded", "percentComplete": 100, "id": f"t{n}"}
            for n, f in enumerate(FILES)]
    run(poll_downloads_once(Slskd({"bob": done}), store, {}))

    row = rows(store)[job_id]

    assert row["error"] == message
    assert row["outcome"] == outcome


def test_a_queued_row_still_has_its_queue_position_and_the_poll_asks_only_open_jobs_peers(store):
    queued = job(store, username="vinylhead")
    job(store, status="organized", username="someone-else")
    slskd = Slskd({"vinylhead": [{"filename": FILES[0]["filename"], "state": "Queued, Remotely", "id": "t1"}]})

    row = rows(store, slskd)[queued]

    assert (row["queue_position"], row["outcome"], row["status"]) == (4, None, "queued")
    assert slskd.asked == [["vinylhead"]]


def test_the_runners_up_are_still_counted_only_where_they_can_be_used(store):
    async def go():
        failed = await store.create_job("bob", "share\\Dummy", FILES, release(),
                                        [{"username": "carol", "directory": "x", "files": FILES}])
        await store.update_status(failed, "failed", "the peer went offline")
        filed = await store.create_job("dave", "share\\Dummy", FILES, release(),
                                       [{"username": "erin", "directory": "y", "files": FILES}])
        await store.update_status(filed, "organized")
        return failed, filed

    failed, filed = run(go())
    found = rows(store)

    assert found[failed]["alternatives_left"] == 1
    assert "alternatives_left" not in found[filed]
