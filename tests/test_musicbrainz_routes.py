"""
The MusicBrainz routes the app's album-you-don't-have page reads (2.0.0-player.13), through the
real app, start(), with a real MusicBrainzClient whose network is a fake that counts what leaves.

- `/releases` passes get_releases' `problem` on. It used to drop it, so a MusicBrainz failure part
  way through a group's pressings reached the page as a short (or empty) list - indistinguishable
  from the album's whole set of pressings.
- `/release_group` is every pressing of a group WITH its tracklist (the pressing dropdown needs
  every one to find the most common) and its release group (the header, on a cold link), cached
  like every MusicBrainz success, never a failure.
- `/fully_search` pages on by `offset` (2.0.0-player.50, the app's "More from MusicBrainz"): the first
  page asked exactly as before (no offset sent - the same cache entry), each page cached apiece,
  MusicBrainz's `count` passed on, and an offset outside 0-FULLY_SEARCH_OFFSET_MAX a 422 with nothing
  asked - the app keeps the same bound.
- `/songs` (2.0.0-player.53, the app's "Songs on MusicBrainz") is one recording search a page - its answer
  already holds the albums each song is on - paged and cached as /fully_search is, a failure a 503 that
  says so and never kept, and its query, limit and offset bounded, a 422 outside with nothing asked.
"""

import json
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


# ---------------------------------------------------------------- /fully_search's offset (2.0.0-player.50)

class Search:
    """MusicBrainz's release-group search: `groups` paged by offset and limit, with its `count`."""

    def __init__(self, groups, count=None):
        self.groups = groups
        self.count = len(groups) if count is None else count
        self.calls = []

    async def get(self, endpoint, params=None):
        self.calls.append((endpoint, dict(params or {})))
        offset = int((params or {}).get("offset", 0))
        limit = int((params or {}).get("limit", 25))
        return Answer({"created": "2026-10-14T00:00:00Z", "count": self.count, "offset": offset,
                       "release-groups": self.groups[offset:offset + limit]})


GROUPS = [{"id": f"g{n}", "title": f"Album {n}"} for n in range(30)]


def test_fully_search_asks_its_first_page_as_it_always_did(app_client, musicbrainz):
    """No offset sent for the first page: the same request, so the same cache entry, as before."""
    fake = Search(GROUPS)
    musicbrainz[1]["fake"] = fake

    body = app_client.get("/deadwax/search_musicbrainz/fully_search", params={"query": "portishead", "limit": 12, "releases": "false"}).json()

    [(endpoint, params)] = fake.calls
    assert endpoint == "release-group/" and "offset" not in params
    assert [group["id"] for group in body["release-groups"]] == [f"g{n}" for n in range(12)]
    #? how many match in all, so the app knows there is another page to ask for
    assert body["count"] == 30 and body["best-match-releases"] == []


def test_fully_search_pages_on_by_offset(app_client, musicbrainz):
    fake = Search(GROUPS)
    musicbrainz[1]["fake"] = fake

    body = app_client.get("/deadwax/search_musicbrainz/fully_search",
                          params={"query": "portishead", "limit": 12, "releases": "false", "offset": 12}).json()

    [(_, params)] = fake.calls
    assert params["offset"] == 12 and params["limit"] == 12 and params["query"] == "portishead"
    assert [group["id"] for group in body["release-groups"]] == [f"g{n}" for n in range(12, 24)]
    assert body["count"] == 30


def test_fully_search_pages_are_cached_apiece(app_client, musicbrainz):
    fake = Search(GROUPS)
    musicbrainz[1]["fake"] = fake

    for offset in (0, 12, 0, 12):
        app_client.get("/deadwax/search_musicbrainz/fully_search", params={"query": "portishead", "limit": 12, "releases": "false", "offset": offset})

    assert [params.get("offset", 0) for _, params in fake.calls] == [0, 12], "each page asked once, the repeats from the cache"


def test_fully_search_past_the_end_is_nothing_found(app_client, musicbrainz):
    """A page beyond the last answer is `{}`, as a search that matched nothing always was."""
    musicbrainz[1]["fake"] = Search(GROUPS)

    body = app_client.get("/deadwax/search_musicbrainz/fully_search", params={"query": "portishead", "limit": 12, "releases": "false", "offset": 36}).json()

    assert body == {}


def test_fully_search_without_a_count_says_none(app_client, musicbrainz):
    """An answer with no `count` (or one that isn't a number) passes none on, rather than a made-up one."""
    class Uncounted(Search):
        async def get(self, endpoint, params=None):
            answer = await super().get(endpoint, params)
            answer.payload.pop("count")
            return answer

    musicbrainz[1]["fake"] = Uncounted(GROUPS)

    body = app_client.get("/deadwax/search_musicbrainz/fully_search", params={"query": "portishead", "limit": 12, "releases": "false"}).json()

    assert "count" not in body and len(body["release-groups"]) == 12


@pytest.mark.parametrize("bad", ["-1", "1001", "twelve", "1.5"])
def test_fully_search_refuses_an_offset_out_of_bounds(app_client, musicbrainz, bad):
    from src.routes.search_musicbrainz import FULLY_SEARCH_OFFSET_MAX

    fake = Search(GROUPS)
    musicbrainz[1]["fake"] = fake

    assert FULLY_SEARCH_OFFSET_MAX == 1000
    assert app_client.get("/deadwax/search_musicbrainz/fully_search", params={"query": "portishead", "offset": bad}).status_code == 422
    assert fake.calls == [], "nothing asked of MusicBrainz for a page it would never be asked for"


def test_fully_search_takes_the_bounds_themselves(app_client, musicbrainz):
    fake = Search(GROUPS, count=5000)
    musicbrainz[1]["fake"] = fake

    for offset in ("0", "1000"):
        assert app_client.get("/deadwax/search_musicbrainz/fully_search", params={"query": "portishead", "releases": "false", "offset": offset}).status_code == 200


def test_the_app_and_the_route_page_no_further_than_one_bound():
    """lib/searchResults.ts keeps the route's bound, so the app never offers a page the route refuses."""
    from src.routes.search_musicbrainz import FULLY_SEARCH_OFFSET_MAX

    source = (Path(__file__).resolve().parent.parent / "ui" / "src" / "lib" / "searchResults.ts").read_text()
    assert f"export const MUSICBRAINZ_OFFSET_MAX = {FULLY_SEARCH_OFFSET_MAX}" in source


# ---------------------------------------------------------------- /artist (2.0.0-player.17)

PORTISHEAD = "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"

PORTISHEAD_ANSWER = {
    "id": PORTISHEAD, "name": "Portishead", "sort-name": "Portishead", "type": "Group",
    "country": "GB", "area": {"name": "United Kingdom"}, "begin-area": {"name": "Bristol"},
    "life-span": {"begin": "1991", "ended": False},
    "genres": [{"name": "trip hop", "count": 9}, {"name": "electronic", "count": 3}],
    "aliases": [{"name": "Portis Head", "type": "Search hint"}],
    "relations": [
        {"type": "official homepage", "url": {"resource": "https://portishead.co.uk/"}},
        {"type": "official homepage", "url": {"resource": "http://www.portishead.co.uk/"}},
        {"type": "official homepage", "url": {"resource": "https://web.archive.org/web/2001/http://godiscs.co.uk/portishead"}},
        {"type": "member of band", "direction": "backward", "begin": "1991", "ended": False,
         "artist": {"id": "b1", "name": "Beth Gibbons"}, "attributes": ["lead vocals"]},
        {"type": "member of band", "direction": "backward", "begin": "1991", "end": "1999", "ended": True,
         "artist": {"id": "d1", "name": "Dave McDonald"}, "attributes": []},
        #? the other way round: Portishead is a member of nothing on its own page
        {"type": "member of band", "direction": "forward", "artist": {"id": "x1", "name": "Somebody"}},
    ],
}


class Artist:
    """MusicBrainz's artist lookup: one answer, or a refusal; every request kept."""

    def __init__(self, payload=None, status_code=200):
        self.payload = payload
        self.status_code = status_code
        self.calls = []

    async def get(self, endpoint, params=None):
        self.calls.append((endpoint, dict(params or {})))
        return Answer(self.payload, status_code=self.status_code)


def test_artist_is_the_full_facts_in_one_request(app_client, musicbrainz):
    fake = Artist(PORTISHEAD_ANSWER)
    musicbrainz[1]["fake"] = fake

    answer = app_client.get(f"/deadwax/search_musicbrainz/artist?mbid={PORTISHEAD}")

    assert answer.status_code == 200
    facts = answer.json()
    assert (facts["name"], facts["type"], facts["begin_area"], facts["began"], facts["ended"], facts["genres"]) == (
        "Portishead", "Group", "Bristol", "1991", False, ["trip hop", "electronic"])
    #? in full since 2.0.0-player.45 (the light facts were a build trim): the links, the same page once
    #? however it was written and told apart where two share a label, and the line-up - its current
    #? members first, and only the members OF this band
    assert facts["links"] == [
        {"label": "Official site · portishead.co.uk", "url": "https://portishead.co.uk/"},
        {"label": "Official site · godiscs.co.uk (archived)", "url": "https://web.archive.org/web/2001/http://godiscs.co.uk/portishead"},
    ]
    assert [(m["name"], m["current"], m["began"], m["ended"], m["roles"]) for m in facts["members"]] == [
        ("Beth Gibbons", True, "1991", None, ["lead vocals"]), ("Dave McDonald", False, "1991", "1999", [])]
    #? ...and every field artist_facts shapes, nothing else
    assert set(facts) == {"mbid", "name", "sort_name", "type", "disambiguation", "country", "area", "begin_area",
                          "began", "ended_on", "ended", "genres", "aliases", "links", "members"}
    #? one request - get_artist's, whose `inc` carries the relations the links and members come from
    [(endpoint, params)] = fake.calls
    assert endpoint == f"artist/{PORTISHEAD}"
    assert {"url-rels", "artist-rels"} <= set(params["inc"].split("+"))


def test_artist_is_cached_and_its_failure_is_not(app_client, musicbrainz):
    musicbrainz[1]["fake"] = Artist(status_code=403)

    assert app_client.get(f"/deadwax/search_musicbrainz/artist?mbid={PORTISHEAD}").status_code == 503

    recovered = Artist(PORTISHEAD_ANSWER)
    musicbrainz[1]["fake"] = recovered
    for _ in range(2):
        assert app_client.get(f"/deadwax/search_musicbrainz/artist?mbid={PORTISHEAD}").json()["name"] == "Portishead"
    assert len(recovered.calls) == 1, "the failure wasn't kept, and the success was"


@pytest.mark.parametrize("bad", ["", "portishead", PORTISHEAD.upper(), f"{PORTISHEAD}x", f"{PORTISHEAD}?inc=aliases"])
def test_artist_refuses_anything_but_an_mbid(app_client, musicbrainz, bad):
    fake = Artist(PORTISHEAD_ANSWER)
    musicbrainz[1]["fake"] = fake

    assert app_client.get("/deadwax/search_musicbrainz/artist", params={"mbid": bad}).status_code == 422
    assert fake.calls == []


# ---------------------------------------------------------------- /songs (2.0.0-player.53)

SONGS = Path(__file__).resolve().parent / "fixtures" / "songs"


def recorded(name):
    """A recording search as MusicBrainz answered it on 2026-10-15 (tests/fixtures/songs/, trimmed)."""
    return json.loads((SONGS / f"{name}.json").read_text())


class Recordings:
    """MusicBrainz's recording search: `recordings` paged by offset and limit, with its `count` - or a
    refusal (a 403 gives up at once)."""

    def __init__(self, recordings, count=None, status_code=200):
        self.recordings = recordings
        self.count = len(recordings) if count is None else count
        self.status_code = status_code
        self.calls = []

    async def get(self, endpoint, params=None):
        self.calls.append((endpoint, dict(params or {})))
        if self.status_code != 200:
            return Answer(status_code=self.status_code)
        offset = int((params or {}).get("offset", 0))
        limit = int((params or {}).get("limit", 25))
        return Answer({"created": "2026-10-15T00:00:00Z", "count": self.count, "offset": offset,
                       "recordings": self.recordings[offset:offset + limit]})


ROADS_QUERY = 'recording:"Roads" AND (artist:"Portishead" OR artistname:"Portishead")'


def test_songs_is_one_recording_search_and_carries_the_albums(app_client, musicbrainz):
    """One request a page - MusicBrainz's recording search, nothing asked per album: its answer already
    holds each recording's releases with their release group, status, date and country, passed on as sent."""
    roads = recorded("roads-portishead")
    fake = Recordings(roads["recordings"], count=roads["count"])
    musicbrainz[1]["fake"] = fake

    body = app_client.get("/deadwax/search_musicbrainz/songs", params={"query": ROADS_QUERY}).json()

    [(endpoint, params)] = fake.calls
    assert endpoint == "recording/"
    assert params == {"query": ROADS_QUERY, "fmt": "json", "limit": 25}, "no offset on the first page, and no inc: the answer has the releases already"
    assert [recording["id"] for recording in body["recordings"]] == [recording["id"] for recording in roads["recordings"]]
    assert body["count"] == 45
    studio = next(recording for recording in body["recordings"] if recording["id"] == "ef37de8d-8fab-42ed-82da-fbfe25715989")
    assert {release["release-group"]["title"] for release in studio["releases"]} == {"Dummy", "Dummy / Portishead"}
    assert all({"status", "release-group", "media"} <= set(release) for release in studio["releases"])


def test_songs_pages_on_by_offset_each_cached_apiece(app_client, musicbrainz):
    many = [{"id": f"r{n}", "title": "Roads", "releases": []} for n in range(60)]
    fake = Recordings(many)
    musicbrainz[1]["fake"] = fake

    for offset in (0, 25, 0, 25):
        body = app_client.get("/deadwax/search_musicbrainz/songs", params={"query": "roads", "offset": offset}).json()
        assert [recording["id"] for recording in body["recordings"]] == [f"r{n}" for n in range(offset, offset + 25)]

    assert [params.get("offset", 0) for _, params in fake.calls] == [0, 25], "each page asked once, the repeats from the cache"


def test_songs_nothing_found_is_an_empty_list_not_a_failure(app_client, musicbrainz):
    musicbrainz[1]["fake"] = Recordings([])

    answer = app_client.get("/deadwax/search_musicbrainz/songs", params={"query": "zzzz qqqq"})

    assert answer.status_code == 200 and answer.json() == {"recordings": [], "count": 0}


def test_songs_without_a_count_says_none(app_client, musicbrainz):
    class Uncounted(Recordings):
        async def get(self, endpoint, params=None):
            answer = await super().get(endpoint, params)
            answer.payload["count"] = "lots"
            return answer

    musicbrainz[1]["fake"] = Uncounted([{"id": "r1", "title": "Roads", "releases": []}])

    body = app_client.get("/deadwax/search_musicbrainz/songs", params={"query": "roads"}).json()

    assert body == {"recordings": [{"id": "r1", "title": "Roads", "releases": []}]}


def test_songs_failure_is_a_503_that_says_so_and_never_cached(app_client, musicbrainz):
    musicbrainz[1]["fake"] = Recordings([], status_code=403)

    failed = app_client.get("/deadwax/search_musicbrainz/songs", params={"query": ROADS_QUERY})

    assert failed.status_code == 503
    assert "MusicBrainz is unreachable right now" in failed.json()["detail"]
    assert "isn't a problem with your search terms" in failed.json()["detail"]

    roads = recorded("roads-portishead")
    recovered = Recordings(roads["recordings"])
    musicbrainz[1]["fake"] = recovered
    for _ in range(2):
        assert len(app_client.get("/deadwax/search_musicbrainz/songs", params={"query": ROADS_QUERY}).json()["recordings"]) == 12
    assert len(recovered.calls) == 1, "Try again asks (the failure wasn't kept), and the success was kept"


def test_songs_answer_that_is_not_a_recording_list_is_a_failure(app_client, musicbrainz):
    """An answer without its `recordings` list is MusicBrainz misbehaving, never "no songs" (fully_search's trap)."""
    class Odd(Recordings):
        async def get(self, endpoint, params=None):
            self.calls.append((endpoint, dict(params or {})))
            return Answer({"error": "something else"})

    musicbrainz[1]["fake"] = Odd([])

    assert app_client.get("/deadwax/search_musicbrainz/songs", params={"query": "roads"}).status_code == 503


@pytest.mark.parametrize("bad", [
    {"query": "roads", "offset": "-1"}, {"query": "roads", "offset": "1001"}, {"query": "roads", "offset": "twelve"},
    {"query": "roads", "offset": "1.5"}, {"query": "roads", "limit": "0"}, {"query": "roads", "limit": "101"},
    {"query": "roads", "limit": "many"}, {"query": ""}, {"query": "   "}, {"query": "r" * 1001}, {},
])
def test_songs_refuses_anything_out_of_bounds_asking_nothing(app_client, musicbrainz, bad):
    from src.routes.search_musicbrainz import SONG_SEARCH_LIMIT_MAX, SONG_SEARCH_OFFSET_MAX, SONG_SEARCH_QUERY_MAX

    fake = Recordings([{"id": "r1", "title": "Roads", "releases": []}])
    musicbrainz[1]["fake"] = fake

    assert (SONG_SEARCH_LIMIT_MAX, SONG_SEARCH_OFFSET_MAX, SONG_SEARCH_QUERY_MAX) == (100, 1000, 1000)
    assert app_client.get("/deadwax/search_musicbrainz/songs", params=bad).status_code == 422
    assert fake.calls == [], "nothing asked of MusicBrainz for a search it would never be asked"


def test_songs_takes_the_bounds_themselves(app_client, musicbrainz):
    fake = Recordings([{"id": "r1", "title": "Roads", "releases": []}], count=5000)
    musicbrainz[1]["fake"] = fake

    for params in ({"query": "r", "limit": "1"}, {"query": "roads", "limit": "100"}, {"query": "roads", "offset": "0"},
                   {"query": "roads", "offset": "1000"}, {"query": "r" * 1000}):
        assert app_client.get("/deadwax/search_musicbrainz/songs", params=params).status_code == 200
    assert [params["limit"] for _, params in fake.calls] == [1, 100, 25, 25, 25]


def test_songs_and_albums_page_no_further_than_one_bound_and_the_app_asks_the_routes_page():
    """lib/songs.ts asks the route's own page size, and pages no further than the album half - one bound."""
    from src.routes.search_musicbrainz import FULLY_SEARCH_OFFSET_MAX, SONG_SEARCH_LIMIT, SONG_SEARCH_OFFSET_MAX

    source = (Path(__file__).resolve().parent.parent / "ui" / "src" / "lib" / "songs.ts").read_text()
    assert SONG_SEARCH_OFFSET_MAX == FULLY_SEARCH_OFFSET_MAX
    assert f"export const SONG_SEARCH_LIMIT = {SONG_SEARCH_LIMIT}" in source
