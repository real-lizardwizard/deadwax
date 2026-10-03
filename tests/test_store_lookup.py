"""
The id bridge (2.0.0-player.17): `GET /deadwax/store/album?release_mbid=...|navidrome_id=...` - one
album as the store index has it, its other pressings, and Navidrome's album id for each.

Through the whole app start() builds (no lifespan), with a real SQLite store over a scratch library
of real folders, and a fake Navidrome (test_navidrome.py's answers) that records every request. What
these hold:

  - the store's half: live rows only - a tombstone (missing, deleted) never listed, a disc folder
    merged into its release's not listed (the release's own row is), a folder gone since the index
    saw it marked `missing` and left out; the album's other pressings by its release group; nothing
    at all for a release the store doesn't hold, or a Navidrome album with no release id;
  - the Navidrome half, asked INTERNALLY: search3 by the release id, then by the album's title, an
    album believed only when its own musicBrainzId is the release - a title match of another
    pressing is never taken; what is found kept a while (a second look asks nothing) and what isn't
    asked afresh; Navidrome down, or unset, is `navidrome_id: null` with the store's half answered;
  - given a Navidrome id, the release is Navidrome's own reading of the album (getAlbum), and only
    getAlbum and search3 ever reach Navidrome, with what deadwax built - never what the page sent;
  - exactly one of the two ids, each bounded, or a 422 with nothing asked of anyone;
  - after review, the limits CLAUDE.md states: an id found is kept NAVIDROME_ID_SECONDS and then
    asked again (Navidrome gives an album a new id when its tags change enough), no more than
    NAVIDROME_IDS_KEPT are kept (the least recently used let go), only OTHER_PRESSINGS_LOOKED_UP
    other pressings are looked up, and a store read that fails says nothing of the store while
    Navidrome's id is still answered;
  - (2.0.0-player.21) the path the app's Edit panel hands every editor: a row's `path` IS the folder
    relative to LIBRARY_PATH that the library's routes take - at the library's root, or with brackets,
    an ampersand, a hash and accents in it - and it follows the album through a re-file (the same
    row, at the new folder), a disc merge (the folder it joined, the merged-away one not listed even
    while a leftover cover keeps it on disk) and a delete through the route (no folder at all).
"""

import asyncio
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from src.api.app import start  # noqa: E402
from src.api.navidrome_endpoint import navidrome  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import store_album as bridge  # noqa: E402
from src.store import JobStore  # noqa: E402
from test_navidrome import failed, ok  # noqa: E402

ROUTE = "/deadwax/store/album"

CD = "11111111-1111-4111-8111-111111111111"        # Dummy, the 1994 CD
VINYL = "f5804905-0000-4000-8000-000000000000"     # Dummy, the 2014 vinyl
REMASTER = "22222222-2222-4222-8222-222222222222"  # a third pressing, deleted
GROUP = "48140466-cff6-3222-bd55-63c27e43190d"
THIRD = "33333333-3333-4333-8333-333333333333"     # Third: another album, never Dummy's pressing

CD_PATH = "Portishead/Dummy (1994)"
VINYL_PATH = "Portishead/Dummy (1994) [20th Anniversary Reissue 180gram]"


def run(coroutine):
    return asyncio.run(coroutine)


@pytest.fixture
def store(tmp_path):
    job_store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    job_store.init()
    return job_store


@pytest.fixture
def root(tmp_path, monkeypatch):
    music = tmp_path / "music"
    music.mkdir()
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(music))
    return music


@pytest.fixture(autouse=True)
def forget():
    bridge.forget_navidrome_ids()
    yield
    bridge.forget_navidrome_ids()


@pytest.fixture
def navidrome_up(monkeypatch):
    """Navidrome, holding the albums a test puts in `albums` (id -> its answer); every request kept."""
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")
    seen: list[httpx.Request] = []
    state = {"albums": {}, "mbid_search": True, "down": False}

    def handle(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if state["down"]:
            raise httpx.ConnectError("refused", request=request)
        endpoint = request.url.path.rsplit("/", 1)[-1]
        q = {k: v[0] for k, v in parse_qs(urlparse(str(request.url)).query, keep_blank_values=True).items()}
        if endpoint == "getAlbum":
            album = state["albums"].get(q.get("id"))
            return httpx.Response(200, json=ok(album=album) if album else failed(70, "Album not found"))
        if endpoint == "search3":
            words = q.get("query", "").lower().split()
            found = [album for album in state["albums"].values()
                     if (state["mbid_search"] and q.get("query") == album.get("musicBrainzId"))
                     or (words and all(word in album["name"].lower() for word in words))]
            return httpx.Response(200, json=ok(searchResult3={"album": found}))
        return httpx.Response(200, json=failed(0, f"not this one: {endpoint}"))

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(handle), base_url="http://navidrome:4533/rest")
    yield state, seen
    run(navidrome.close_client())


def folder(root, path, store, release, group=GROUP, edition="", year="1994", album="Dummy"):
    (root / path).mkdir(parents=True, exist_ok=True)
    return run(store.index_upsert(str(root), {
        "path": path, "release_mbid": release, "release_group_mbid": group, "artist": "Portishead",
        "album": album, "year": year, "edition": edition, "track_count": 11, "formats": ["flac"],
    }))


def dummies(root, store):
    """The CD and the vinyl held; a remaster deadwax deleted; Third, another album."""
    ids = {
        "cd": folder(root, CD_PATH, store, CD),
        "vinyl": folder(root, VINYL_PATH, store, VINYL, edition="20th Anniversary Reissue 180gram", year="2014"),
        "remaster": folder(root, "Portishead/Dummy (1994) [Remaster]", store, REMASTER, edition="Remaster"),
        "third": folder(root, "Portishead/Third (2008)", store, THIRD, group="other-group", album="Third", year="2008"),
    }
    run(store.index_gone(str(root), "Portishead/Dummy (1994) [Remaster]", "deleted"))
    return ids


def ask(store, **params):
    app = start()
    app.state.store = store
    return TestClient(app).get(ROUTE, params=params)  # no `with`: no lifespan


def navidrome_albums(state):
    state["albums"].update({
        "nd-cd": {"id": "nd-cd", "name": "Dummy", "musicBrainzId": CD},
        "nd-vinyl": {"id": "nd-vinyl", "name": "Dummy", "musicBrainzId": VINYL},
        "nd-third": {"id": "nd-third", "name": "Third", "musicBrainzId": THIRD},
    })


# ---------------------------------------------------------------- the store's half

def test_a_held_release_is_its_rows_and_its_other_pressings(root, store, navidrome_up):
    state, _ = navidrome_up
    navidrome_albums(state)
    ids = dummies(root, store)

    answer = ask(store, release_mbid=CD).json()

    assert (answer["release_mbid"], answer["release_group_mbid"], answer["navidrome_id"]) == (CD, GROUP, "nd-cd")
    [cd] = answer["present"]
    assert (cd["id"], cd["path"], cd["edition"], cd["year"], cd["formats"], cd["track_count"]) == (
        ids["cd"], CD_PATH, "", "1994", ["flac"], 11)
    #? the vinyl - and not the deleted remaster, nor Third (another album)
    [vinyl] = answer["other_pressings"]
    assert (vinyl["id"], vinyl["path"], vinyl["release_mbid"], vinyl["edition"], vinyl["year"], vinyl["navidrome_id"]) == (
        ids["vinyl"], VINYL_PATH, VINYL, "20th Anniversary Reissue 180gram", "2014", "nd-vinyl")


def test_a_tombstone_is_never_listed(root, store, navidrome_up):
    dummies(root, store)
    run(store.index_gone(str(root), VINYL_PATH, "missing"))

    answer = ask(store, release_mbid=VINYL).json()
    assert answer["present"] == [] and answer["other_pressings"] == []

    deleted = ask(store, release_mbid=REMASTER).json()
    assert deleted["present"] == [], "a deleted album is gone, whatever its row says"
    assert [row["release_mbid"] for row in ask(store, release_mbid=CD).json()["other_pressings"]] == []


def test_a_disc_folder_merged_into_its_release_is_not_listed_but_the_release_is(root, store, navidrome_up):
    disc_one = folder(root, "Portishead/Roseland (1998) (Disc 1)", store, CD, album="Roseland")
    folder(root, "Portishead/Roseland (1998) (Disc 2)", store, CD, album="Roseland")
    run(store.index_merge(str(root), "Portishead/Roseland (1998) (Disc 2)", "Portishead/Roseland (1998) (Disc 1)"))

    answer = ask(store, release_mbid=CD).json()

    assert [(row["id"], row["path"]) for row in answer["present"]] == [(disc_one, "Portishead/Roseland (1998) (Disc 1)")]


def test_a_folder_gone_since_the_index_saw_it_is_left_out_and_marked_missing(root, store, navidrome_up):
    dummies(root, store)
    (root / VINYL_PATH).rmdir()

    answer = ask(store, release_mbid=CD).json()

    assert answer["other_pressings"] == []
    assert run(store.index_pressings(str(root), GROUP, CD)) == [], "its row is a `missing` tombstone now"


def test_a_release_the_store_doesnt_hold_is_nothing(root, store, navidrome_up):
    dummies(root, store)

    answer = ask(store, release_mbid="44444444-4444-4444-8444-444444444444").json()

    assert (answer["present"], answer["other_pressings"], answer["release_group_mbid"], answer["navidrome_id"]) == ([], [], None, None)


def test_a_navidrome_album_with_no_release_id_is_nothing_but_its_id(root, store, navidrome_up):
    state, seen = navidrome_up
    state["albums"]["nd-rip"] = {"id": "nd-rip", "name": "Old Rip", "musicBrainzId": ""}
    dummies(root, store)

    answer = ask(store, navidrome_id="nd-rip").json()

    assert answer == {"release_mbid": None, "release_group_mbid": None, "navidrome_id": "nd-rip",
                      "present": [], "other_pressings": []}
    assert [request.url.path for request in seen] == ["/rest/getAlbum"]


# ---------------------------------------------------------------- the Navidrome half

def test_given_a_navidrome_id_the_release_is_navidromes_reading_of_it(root, store, navidrome_up):
    state, seen = navidrome_up
    navidrome_albums(state)
    dummies(root, store)

    answer = ask(store, navidrome_id="nd-vinyl").json()

    assert (answer["release_mbid"], answer["navidrome_id"]) == (VINYL, "nd-vinyl")
    assert [row["path"] for row in answer["present"]] == [VINYL_PATH]
    assert [(row["path"], row["navidrome_id"]) for row in answer["other_pressings"]] == [(CD_PATH, "nd-cd")]
    #? getAlbum for the release, and a search for the other pressing - nothing else, ever
    assert {request.url.path for request in seen} == {"/rest/getAlbum", "/rest/search3"}


def test_navidrome_found_by_title_when_it_cant_search_ids_and_only_the_right_pressing(root, store, navidrome_up):
    """A Navidrome that doesn't match MusicBrainz ids in a search: the title finds every Dummy, and
    only the one whose own musicBrainzId is the release is taken - never the CD for the vinyl."""
    state, seen = navidrome_up
    navidrome_albums(state)
    state["mbid_search"] = False
    dummies(root, store)

    answer = ask(store, release_mbid=VINYL).json()

    assert answer["navidrome_id"] == "nd-vinyl"
    queries = [parse_qs(urlparse(str(request.url)).query)["query"][0] for request in seen if request.url.path == "/rest/search3"]
    assert queries[:2] == [VINYL, "Dummy"]


def test_a_title_match_of_another_pressing_is_never_taken(root, store, navidrome_up):
    state, _ = navidrome_up
    state["albums"]["nd-cd"] = {"id": "nd-cd", "name": "Dummy", "musicBrainzId": CD}
    state["mbid_search"] = False
    dummies(root, store)

    assert ask(store, release_mbid=VINYL).json()["navidrome_id"] is None


def test_what_is_found_is_kept_and_what_isnt_is_asked_again(root, store, navidrome_up):
    state, seen = navidrome_up
    navidrome_albums(state)
    dummies(root, store)

    assert ask(store, release_mbid=CD).json()["navidrome_id"] == "nd-cd"
    asked = len(seen)
    assert ask(store, release_mbid=CD).json()["navidrome_id"] == "nd-cd"
    #? a second look searches nothing: the kept ids are only CHECKED (getAlbum), one each
    assert {r.url.path for r in seen[asked:]} == {"/rest/getAlbum"}, "a second look searches Navidrome for nothing"

    #? an album Navidrome hasn't scanned yet: asked again, and found once it has
    del state["albums"]["nd-third"]
    assert ask(store, release_mbid=THIRD).json()["navidrome_id"] is None
    state["albums"]["nd-third"] = {"id": "nd-third", "name": "Third", "musicBrainzId": THIRD}
    assert ask(store, release_mbid=THIRD).json()["navidrome_id"] == "nd-third"


def test_a_kept_id_navidrome_no_longer_has_is_found_afresh_at_once(root, store, navidrome_up):
    #? an apply writes the tags, Navidrome scans and the album is found - then the folder is renamed,
    #? and a Navidrome that ids albums by folder gives it a new id: the kept one must not be handed
    #? out for the rest of the while (the album page following the apply would never reach it)
    state, _ = navidrome_up
    navidrome_albums(state)
    dummies(root, store)
    assert ask(store, release_mbid=CD).json()["navidrome_id"] == "nd-cd"

    state["albums"]["nd-cd-renamed"] = {**state["albums"].pop("nd-cd"), "id": "nd-cd-renamed"}

    assert ask(store, release_mbid=CD).json()["navidrome_id"] == "nd-cd-renamed"


def test_a_kept_id_that_is_now_another_release_is_found_afresh(root, store, navidrome_up):
    state, _ = navidrome_up
    navidrome_albums(state)
    dummies(root, store)
    assert ask(store, release_mbid=CD).json()["navidrome_id"] == "nd-cd"

    #? the same id, re-tagged as another pressing; the CD now under another id
    state["albums"]["nd-cd"] = {"id": "nd-cd", "name": "Dummy", "musicBrainzId": REMASTER}
    state["albums"]["nd-cd-elsewhere"] = {"id": "nd-cd-elsewhere", "name": "Dummy", "musicBrainzId": CD}

    assert ask(store, release_mbid=CD).json()["navidrome_id"] == "nd-cd-elsewhere"


def test_a_kept_id_stands_while_navidrome_cant_be_reached(root, store, navidrome_up):
    state, _ = navidrome_up
    navidrome_albums(state)
    dummies(root, store)
    assert ask(store, release_mbid=CD).json()["navidrome_id"] == "nd-cd"

    state["down"] = True

    assert ask(store, release_mbid=CD).json()["navidrome_id"] == "nd-cd"


def test_navidrome_down_is_a_null_id_and_the_store_still_answers(root, store, navidrome_up):
    state, _ = navidrome_up
    state["down"] = True
    dummies(root, store)

    answer = ask(store, release_mbid=CD).json()

    assert answer["navidrome_id"] is None
    assert [row["path"] for row in answer["present"]] == [CD_PATH]
    assert [(row["path"], row["navidrome_id"]) for row in answer["other_pressings"]] == [(VINYL_PATH, None)]


def test_navidrome_unset_is_a_null_id_and_the_store_still_answers(root, store, monkeypatch):
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    dummies(root, store)

    answer = ask(store, release_mbid=CD)

    assert answer.status_code == 200
    assert (answer.json()["navidrome_id"], [row["path"] for row in answer.json()["present"]]) == (None, [CD_PATH])


def test_it_asks_navidrome_through_client_for(root, store, navidrome_up, monkeypatch):
    """Made while answering the page, so it reads that user's library (step 6's seam)."""
    state, _ = navidrome_up
    navidrome_albums(state)
    dummies(root, store)
    asked = []
    monkeypatch.setattr(bridge, "client_for", lambda request: asked.append(request.url.path) or navidrome)

    ask(store, release_mbid=CD)

    assert asked == [ROUTE]


def test_nothing_the_page_sends_reaches_navidrome(root, store, navidrome_up):
    state, seen = navidrome_up
    navidrome_albums(state)
    dummies(root, store)

    ask(store, navidrome_id="nd-cd", u="admin", t="forged", query="x", f="xml")

    for request in seen:
        sent = {k: v[0] for k, v in parse_qs(urlparse(str(request.url)).query).items()}
        assert sent["u"] == "james" and sent["t"] != "forged" and sent["f"] == "json"
        assert sent.get("query") in (None, CD, VINYL, "Dummy")


# ---------------------------------------------------------------- what it takes

@pytest.mark.parametrize("params", [
    {},                                                      # neither
    {"release_mbid": CD, "navidrome_id": "nd-cd"},           # both
    {"release_mbid": "not-an-id"},
    {"release_mbid": VINYL.upper()},
    {"release_mbid": f"{CD}x"},
    {"navidrome_id": ""},
    {"navidrome_id": "x" * 257},
])
def test_exactly_one_id_each_bounded_or_a_422_with_nothing_asked(root, store, navidrome_up, params):
    _, seen = navidrome_up

    assert ask(store, **params).status_code == 422
    assert seen == []


def test_without_a_library_path_only_navidrome_is_asked(store, navidrome_up, monkeypatch):
    state, _ = navidrome_up
    navidrome_albums(state)
    monkeypatch.setattr(Config, "LIBRARY_PATH", "")

    answer = ask(store, release_mbid=CD).json()

    assert (answer["present"], answer["other_pressings"], answer["navidrome_id"]) == ([], [], "nd-cd")


# ---------------------------------------------------------------- the limits (review)

class Clock:
    """The bridge's own clock, moved by hand - only its reference to `time`, nothing asyncio reads."""

    def __init__(self) -> None:
        self.now = 1000.0

    def monotonic(self) -> float:
        return self.now


def test_an_id_found_is_kept_a_while_and_then_asked_again(root, store, navidrome_up, monkeypatch):
    state, seen = navidrome_up
    navidrome_albums(state)
    dummies(root, store)
    clock = Clock()
    monkeypatch.setattr(bridge, "time", clock)
    searches = lambda: [r for r in seen if r.url.path == "/rest/search3" and CD in str(r.url)]  # noqa: E731

    assert ask(store, release_mbid=CD).json()["navidrome_id"] == "nd-cd"
    asked = len(searches())
    clock.now += bridge.NAVIDROME_ID_SECONDS - 1
    assert ask(store, release_mbid=CD).json()["navidrome_id"] == "nd-cd"
    assert len(searches()) == asked, "within the while, nothing is asked"

    #? re-tagged, Navidrome gives the album a new id: past the while, the new one is found
    state["albums"]["nd-cd-2"] = {**state["albums"].pop("nd-cd"), "id": "nd-cd-2"}
    clock.now += 2
    assert ask(store, release_mbid=CD).json()["navidrome_id"] == "nd-cd-2"
    assert len(searches()) == asked + 1


def test_no_more_ids_are_kept_than_the_bound_the_least_recently_used_let_go(monkeypatch):
    clock = Clock()
    monkeypatch.setattr(bridge, "time", clock)
    monkeypatch.setattr(bridge, "NAVIDROME_IDS_KEPT", 3)
    for n in range(3):
        bridge._keep(f"release-{n}", f"album-{n}")
    assert bridge._kept("release-0") == "album-0"  # used: the newest now
    bridge._keep("release-3", "album-3")

    assert [bridge._kept(f"release-{n}") for n in range(4)] == ["album-0", None, "album-2", "album-3"]
    assert len(bridge._navidrome_ids) == 3


def test_only_the_first_few_other_pressings_are_looked_up(root, store, navidrome_up):
    state, seen = navidrome_up
    navidrome_albums(state)
    folder(root, CD_PATH, store, CD)
    others = [f"{n}{n}{n}{n}{n}{n}{n}{n}-0000-4000-8000-00000000000{n}" for n in range(1, 8)]
    for n, release in enumerate(others, start=1):
        folder(root, f"Portishead/Dummy (1994) [Pressing {n}]", store, release, edition=f"Pressing {n}")
        state["albums"][f"nd-{n}"] = {"id": f"nd-{n}", "name": "Dummy", "musicBrainzId": release}

    answer = ask(store, release_mbid=CD).json()

    ids = [row["navidrome_id"] for row in answer["other_pressings"]]
    assert len(ids) == 7
    assert ids == [f"nd-{n}" for n in range(1, bridge.OTHER_PRESSINGS_LOOKED_UP + 1)] + [None] * (7 - bridge.OTHER_PRESSINGS_LOOKED_UP)
    looked = {parse_qs(urlparse(str(r.url)).query)["query"][0] for r in seen if r.url.path == "/rest/search3"}
    assert looked == {CD, *others[:bridge.OTHER_PRESSINGS_LOOKED_UP]}, "the rest are never asked about"


def test_a_store_read_that_fails_says_nothing_of_the_store_and_navidrome_still_answers(root, store, navidrome_up, monkeypatch):
    state, _ = navidrome_up
    navidrome_albums(state)
    dummies(root, store)

    def refused(*_):
        raise PermissionError("the share went away")

    monkeypatch.setattr(bridge, "_still_there", refused)

    answer = ask(store, release_mbid=CD)

    assert answer.status_code == 200
    assert (answer.json()["present"], answer.json()["other_pressings"], answer.json()["navidrome_id"]) == ([], [], "nd-cd")


# ---------------------------------------------------------------- the path the Edit panel opens (2.0.0-player.21)
#
# The app's Edit panel finds an album page's folder here - the store's `present` rows - and hands that
# path, as it is, to every editor: the release editor, the tag editor, the Get buttons, the delete
# confirmation. So a row's path must BE the folder relative to LIBRARY_PATH that the library's routes
# take; follow the album through a re-file, a disc merge and a delete; and be every folder of a set kept
# one per disc, in a steady order (the panel starts on the first).

def library(store, method, route, **kwargs):
    app = start()
    app.state.store = store
    client = TestClient(app)  # no `with`: no lifespan
    return client.get(route, **kwargs) if method == "get" else client.post(route, **kwargs)


def track(root, path, name="01 - Wandering Star.flac"):
    (root / path / name).write_bytes(b"")


def test_a_rows_path_is_the_folder_the_library_routes_take(root, store, navidrome_up):
    dummies(root, store)
    track(root, CD_PATH)

    [row] = ask(store, release_mbid=CD).json()["present"]

    assert (root / row["path"]).resolve() == (root / CD_PATH).resolve()
    tracks = library(store, "get", "/deadwax/library/tracks", params={"album": row["path"]})
    assert tracks.status_code == 200 and tracks.json()["album"] == CD_PATH
    summary = library(store, "get", "/deadwax/library/deletion_summary", params={"album": row["path"]})
    assert summary.status_code == 200 and summary.json()["audio_files"] == 1


def test_a_folder_at_the_librarys_root_and_one_named_with_awkward_characters_both_map(root, store, navidrome_up):
    """A stranger's rip sits at the top of the library, with no artist folder; a name can hold brackets,
    an ampersand, a hash and accents - each goes through a query string to the routes and back."""
    rip = folder(root, "Portishead - Dummy", store, CD)
    awkward = "Sigur Rós/( ) [Edition #1] & More"
    folder(root, awkward, store, VINYL, edition="Edition #1", year="2002")

    assert [(r["id"], r["path"]) for r in ask(store, release_mbid=CD).json()["present"]] == [(rip, "Portishead - Dummy")]
    [row] = ask(store, release_mbid=VINYL).json()["present"]
    assert row["path"] == awkward
    for path in ("Portishead - Dummy", awkward):
        assert library(store, "get", "/deadwax/library/tracks", params={"album": path}).json()["album"] == path


def test_a_refiled_album_is_answered_at_its_new_folder_by_the_same_row(root, store, navidrome_up):
    """The release editor renames a folder (the retag route re-indexes it as moved): the row follows,
    same id, and the bridge answers the new path - the panel's next look finds the album where it is."""
    ids = dummies(root, store)
    (root / CD_PATH).rename(root / "Portishead" / "Dummy (1994) [UK CD]")
    run(store.index_move(str(root), CD_PATH, "Portishead/Dummy (1994) [UK CD]", CD))

    [row] = ask(store, release_mbid=CD).json()["present"]

    assert (row["id"], row["path"]) == (ids["cd"], "Portishead/Dummy (1994) [UK CD]")
    assert library(store, "get", "/deadwax/library/tracks", params={"album": CD_PATH}).status_code == 404


def test_a_disc_folder_merged_in_is_answered_as_the_folder_it_joined(root, store, navidrome_up):
    disc_one = folder(root, "Portishead/Roseland (1998) (Disc 1)", store, CD, album="Roseland")
    folder(root, "Portishead/Roseland (1998) (Disc 2)", store, CD, album="Roseland")

    both = ask(store, release_mbid=CD).json()["present"]
    #? a set kept one folder per disc: both, in the store's steady order - the panel starts on the first
    assert [row["path"] for row in both] == ["Portishead/Roseland (1998) (Disc 1)", "Portishead/Roseland (1998) (Disc 2)"]

    #? the merge moves the tracks across; a cover of the same name stays behind with its folder
    #? (retag._merge_into never overwrites), so the folder is still there - and still not the album
    (root / "Portishead/Roseland (1998) (Disc 2)" / "cover.jpg").write_bytes(b"")
    run(store.index_merge(str(root), "Portishead/Roseland (1998) (Disc 2)", "Portishead/Roseland (1998) (Disc 1)"))

    assert [(row["id"], row["path"]) for row in ask(store, release_mbid=CD).json()["present"]] == [
        (disc_one, "Portishead/Roseland (1998) (Disc 1)")]


def test_an_album_deleted_through_the_route_is_answered_as_nothing(root, store, navidrome_up):
    """The panel's Delete is the library's delete route: the folder goes, its row a `deleted` tombstone,
    and the bridge then answers no folder for the release - the album page has nothing left to edit."""
    dummies(root, store)
    track(root, VINYL_PATH)

    deleted = library(store, "post", "/deadwax/library/delete", json={"album_path": VINYL_PATH})

    assert deleted.status_code == 200 and deleted.json()["deleted"] is True
    assert not (root / VINYL_PATH).exists()
    assert ask(store, release_mbid=VINYL).json()["present"] == []
    assert [row["path"] for row in ask(store, release_mbid=CD).json()["present"]] == [CD_PATH]
