"""
The MusicBrainz routes the app's album-you-don't-have page reads (2.0.0-player.13), through the
real app, start(), with a real MusicBrainzClient whose network is a fake that counts what leaves.

- `/releases` passes get_releases' `problem` on. It used to drop it, so a MusicBrainz failure part
  way through a group's pressings reached the page as a short (or empty) list - indistinguishable
  from the album's whole set of pressings.
- `/release_group` is every pressing of a group WITH its tracklist (the pressing dropdown needs
  every one to find the most common) and its release group (the header, on a cold link), cached
  like every MusicBrainz success, never a failure.
"""

import sys
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.api.app import start  # noqa: E402
from src.api.musicbrainz_endpoint import MusicBrainzClient, RateLimit, ResponseCache  # noqa: E402

GROUP = "c6fc678e-e987-45c5-811c-e2bd09c8b902"  # The Slow Rush


class Answer:
    def __init__(self, payload=None, status_code=200):
        self.payload = payload or {}
        self.status_code = status_code
        self.text = "fake"

    def raise_for_status(self):
        if self.status_code >= 400:
            raise httpx.HTTPStatusError("refused", request=None, response=self)  # type: ignore[arg-type]

    def json(self):
        return self.payload


class MusicBrainz:
    """MusicBrainz's release browse: `pages` by offset, or a refusal (a 403 gives up at once)."""

    def __init__(self, pages=None, total=None, refuse_from=None):
        self.pages = pages or {0: []}
        self.total = total if total is not None else sum(len(page) for page in self.pages.values())
        self.refuse_from = refuse_from
        self.calls = []

    async def get(self, endpoint, params=None):
        self.calls.append((endpoint, dict(params or {})))
        offset = (params or {}).get("offset", 0)
        if self.refuse_from is not None and offset >= self.refuse_from:
            return Answer(status_code=403)
        return Answer({"releases": self.pages.get(offset, []), "release-count": self.total})


@pytest.fixture
def musicbrainz(monkeypatch):
    """A real client with a fresh cache and pacing, its network handed to whichever fake is set."""
    monkeypatch.setattr(MusicBrainzClient, "cache", ResponseCache(ttl_seconds=60, max_entries=16))
    monkeypatch.setattr(MusicBrainzClient, "rate_limit", RateLimit())
    client = MusicBrainzClient()
    state = {"fake": MusicBrainz()}

    async def get_client():
        return state["fake"]

    client.get_client = get_client  # type: ignore[method-assign]
    return client, state


@pytest.fixture
def app_client(musicbrainz):
    app = start()  # no `with`: no lifespan, nothing connects
    app.state.musicbrainz_client = musicbrainz[0]
    return TestClient(app)


def release(id_, *titles):
    return {"id": id_, "media": [{"position": 1, "tracks": [{"title": t, "length": 200000} for t in titles]}]}


# ---------------------------------------------------------------- /releases

def test_releases_passes_a_failure_on_as_its_problem(app_client, musicbrainz):
    musicbrainz[1]["fake"] = MusicBrainz(refuse_from=0)

    answer = app_client.get(f"/deadwax/search_musicbrainz/releases?release_group_mbid={GROUP}")

    assert answer.status_code == 200
    body = answer.json()
    assert body["releases"] == []
    assert body["problem"], "an outage must not read as an album with no pressings"


def test_releases_that_all_came_say_no_problem(app_client, musicbrainz):
    musicbrainz[1]["fake"] = MusicBrainz({0: [release("a", "One")]})

    body = app_client.get(f"/deadwax/search_musicbrainz/releases?release_group_mbid={GROUP}&tracks=false").json()

    assert [r["id"] for r in body["releases"]] == ["a"]
    assert body["problem"] is None


# ---------------------------------------------------------------- /release_group

def test_release_group_asks_for_every_pressings_tracklist(app_client, musicbrainz):
    fake = MusicBrainz({0: [release("a", "One"), release("b", "One", "Two")]})
    musicbrainz[1]["fake"] = fake

    body = app_client.get(f"/deadwax/search_musicbrainz/release_group?release_group_mbid={GROUP}").json()

    assert body == {"id": GROUP, "releases": fake.pages[0], "problem": None}
    [(endpoint, params)] = fake.calls
    assert endpoint == "release/" and params["release-group"] == GROUP
    assert "recordings" in params["inc"], "the tracklists are what the differences are worked out from"
    #? and each pressing's group, so a page opened from a link or a reload can say "Album" too
    assert params["inc"].split("+")[-1] == "release-groups"


def test_only_release_group_asks_for_each_pressings_group(app_client, musicbrainz):
    """The main page's /releases is unchanged: release-groups would change its cache key and payload."""
    fake = MusicBrainz({0: [release("a", "One")]})
    musicbrainz[1]["fake"] = fake

    app_client.get(f"/deadwax/search_musicbrainz/releases?release_group_mbid={GROUP}")

    [(_, params)] = fake.calls
    assert "release-groups" not in params["inc"]


def test_release_group_walks_every_page(app_client, musicbrainz):
    first = [release(f"r{n}", "One") for n in range(100)]
    fake = MusicBrainz({0: first, 100: [release("last", "One")]}, total=101)
    musicbrainz[1]["fake"] = fake

    body = app_client.get(f"/deadwax/search_musicbrainz/release_group?release_group_mbid={GROUP}").json()

    assert len(body["releases"]) == 101 and body["problem"] is None
    assert [params["offset"] for _, params in fake.calls] == [0, 100]


def test_release_group_is_cached(app_client, musicbrainz):
    fake = MusicBrainz({0: [release("a", "One")]})
    musicbrainz[1]["fake"] = fake

    for _ in range(2):
        assert app_client.get(f"/deadwax/search_musicbrainz/release_group?release_group_mbid={GROUP}").status_code == 200

    assert len(fake.calls) == 1, "a second look at the same album is answered without asking MusicBrainz"


def test_release_group_failure_is_a_problem_and_never_cached(app_client, musicbrainz):
    musicbrainz[1]["fake"] = MusicBrainz(refuse_from=0)

    failed = app_client.get(f"/deadwax/search_musicbrainz/release_group?release_group_mbid={GROUP}").json()
    assert failed["releases"] == [] and failed["problem"]

    recovered = MusicBrainz({0: [release("a", "One")]})
    musicbrainz[1]["fake"] = recovered
    body = app_client.get(f"/deadwax/search_musicbrainz/release_group?release_group_mbid={GROUP}").json()

    assert [r["id"] for r in body["releases"]] == ["a"] and body["problem"] is None
    assert len(recovered.calls) == 1, "Try again asks MusicBrainz again rather than replaying the failure"


def test_release_group_failing_part_way_says_so(app_client, musicbrainz):
    first = [release(f"r{n}", "One") for n in range(100)]
    musicbrainz[1]["fake"] = MusicBrainz({0: first}, total=150, refuse_from=100)

    body = app_client.get(f"/deadwax/search_musicbrainz/release_group?release_group_mbid={GROUP}").json()

    assert len(body["releases"]) == 100
    assert body["problem"], "a partial list must not pass for the album's pressings"


@pytest.mark.parametrize("bad", ["", "not-an-id", "C6FC678E-E987-45C5-811C-E2BD09C8B902", f"{GROUP}x", f"x{GROUP}",
                                 f"{GROUP}&inc=aliases", "../x"])
def test_release_group_refuses_anything_but_an_mbid(app_client, musicbrainz, bad):
    fake = MusicBrainz()
    musicbrainz[1]["fake"] = fake

    assert app_client.get("/deadwax/search_musicbrainz/release_group", params={"release_group_mbid": bad}).status_code == 422
    assert fake.calls == []
