"""
A manual search through the routes: the iPhone and Mac app's Search Soulseek, an artist and an album as
typed with no release behind them, POSTed as `manual: true` - to Find (2.1.37, and its echo since 2.1.38) and
with the release a Get enqueues (2.1.38).

pydantic drops an undeclared field without a word, so each of these goes through the whole app start()
builds (no lifespan, so nothing connects) with real JSON: a `manual` the model didn't declare would be
dropped here, and the question scored as a trackless Get. A fake slskd answers the search; the store is
real SQLite. How the folders are ranked is tests/test_matching.py's.
"""

import asyncio

import pytest
from fastapi.testclient import TestClient

from src.api.app import start
from src.routes import download
from src.store import JobStore
from tests.test_matching import folder_files, make_response

FIND = "/deadwax/download/find_candidates"
MANUAL = {"artist": "Radiohead", "album": "OK Computer", "manual": True}


class Slskd:
    """slskd answering every search with the same folders."""

    def __init__(self, responses=()):
        self.responses = list(responses)
        self.rounds: list[list[str]] = []

    async def search_all(self, queries, **kwargs):
        self.rounds.append(list(queries))
        return list(self.responses)


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


SHARES = [
    make_response("extra", folder_files(r"@@extra\Radiohead\OK Computer OKNOTOK 1997 2017")),
    make_response("exact", folder_files(r"@@exact\Radiohead\OK Computer", extension="mp3"), free_slot=False,
                  queue=40, speed=1_000),
    make_response("other", folder_files(r"@@other\Radiohead\The Bends")),
]


def test_a_manual_question_reaches_the_ranking_as_manual(store, monkeypatch):
    seen = []
    real = download.rank_candidates

    def ranking(responses, expected, *args):
        seen.append(expected)
        return real(responses, expected, *args)

    monkeypatch.setattr(download, "rank_candidates", ranking)
    answer = client(store, Slskd(SHARES)).post(FIND, json=MANUAL)

    assert answer.status_code == 200
    assert seen[0]["manual"] is True
    assert (seen[0]["artist"], seen[0]["album"]) == ("Radiohead", "OK Computer")


def test_a_manual_search_ranks_by_the_folders_name_first(store):
    slskd = Slskd(SHARES)
    answer = client(store, slskd).post(FIND, json=MANUAL).json()

    #? searched as any Find is: the typed words, under the one name
    assert slskd.rounds == [["Radiohead OK Computer"]]
    ranked = answer["candidates"]
    assert [c["username"] for c in ranked] == ["exact", "extra", "other"]
    assert ranked[0]["signals"]["name_match"] == 1.0
    assert list(ranked[0]["signals"])[0] == "name_match"
    #? nothing to judge the files against, so Tracks reads "3 files" and no line is missing
    assert ranked[0]["expected_tracks"] == 0 and ranked[0]["missing_count"] == 0


def test_a_question_without_manual_has_no_folder_name_signal(store):
    answer = client(store, Slskd(SHARES)).post(FIND, json={"artist": "Radiohead", "album": "OK Computer"}).json()
    assert answer["candidates"] and all("name_match" not in c["signals"] for c in answer["candidates"])
    #? and the trackless Get's order is as it was: by format and availability alone, which the fit can't touch
    assert answer["candidates"][-1]["username"] == "exact"


@pytest.mark.parametrize("body", [
    {**MANUAL, "album": ""}, {**MANUAL, "album": "   "}, {**MANUAL, "artist": " \t"}, {**MANUAL, "artist": ""},
])
def test_a_manual_search_needs_both_an_artist_and_an_album(store, body):
    slskd = Slskd(SHARES)
    answer = client(store, slskd).post(FIND, json=body)
    assert answer.status_code == 400
    assert answer.json()["detail"] == "Type an artist and an album."
    assert slskd.rounds == [], "nothing was searched"


def test_a_blank_album_without_manual_is_not_refused_by_it(store):
    #? what a question without `manual` does with a blank album is what it always did
    answer = client(store, Slskd()).post(FIND, json={"artist": "Radiohead", "album": ""})
    assert answer.status_code == 200


def test_the_request_model_keeps_manual():
    assert download.FindCandidatesRequest(**MANUAL).model_dump()["manual"] is True
    assert download.FindCandidatesRequest(artist="a", album="b").model_dump()["manual"] is False


# ---------------------------------------------------------------- the download (2.1.38)

ENQUEUE = "/deadwax/download/enqueue"


class Enqueuing(Slskd):
    async def enqueue(self, username, files):
        self.enqueued = (username, files)
        return True, None


def get(store, release):
    body = {"username": "bob", "directory": "share\\Radiohead\\OK Computer",
            "files": [{"filename": "share\\Radiohead\\OK Computer\\01.flac", "size": 10}], "release": release}
    answer = client(store, Enqueuing()).post(ENQUEUE, json=body)
    assert answer.status_code == 200
    return asyncio.run(store.get_job(answer.json()["job_id"]))


def test_a_manual_get_is_stored_as_manual_with_the_job(store):
    stored = get(store, {"artist": "radiohead", "album_artist": "radiohead", "album": "ok computer", "manual": True})
    assert stored["release"]["manual"] is True


def test_any_other_get_stores_its_release_exactly_as_before(store):
    #? no `manual` key at all, said or not: every other job's stored release is byte for byte what it was
    for release in ({"artist": "Portishead", "album": "Dummy"}, {"artist": "Portishead", "album": "Dummy",
                                                                 "manual": False}):
        assert "manual" not in get(store, release)["release"]


def test_the_enqueue_model_keeps_manual():
    assert download.EnqueueRelease(artist="a", album="b", manual=True).model_dump()["manual"] is True


def test_find_echoes_a_manual_question_and_no_other(store):
    #? the app's gate: a server that answers without it would file a manual Get by the typed words
    assert client(store, Slskd(SHARES)).post(FIND, json=MANUAL).json()["manual"] is True
    assert "manual" not in client(store, Slskd(SHARES)).post(FIND, json={"artist": "Radiohead",
                                                                          "album": "OK Computer"}).json()
