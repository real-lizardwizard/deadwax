"""
Pins (2.0.0-player.18): `GET`/`PUT /deadwax/me/pins` and `POST /deadwax/me/pins/toggle` - the albums and
artists a user pinned to the app's Home - and store.adopt_local, step 3's take-over, written now.

Through the whole app start() builds (no lifespan), with a real SQLite store over a scratch library
of real folders, and a fake Navidrome that records every request. What these hold:

  - an album pin keys on the store index's row (`store:<store_album.id>`), so it follows the album:
    through a re-file (index_move), a disc folder merged into its release's (merged_into followed),
    and - with Navidrome giving the moved album a new id - opens the album as it is now, the old id
    checked and found wanting; a deleted album reads as gone, a folder that has gone as missing, and
    a pin whose album has gone is pointed at a live copy of its release when there is one;
  - a `release:<mbid>` pin, made before the index held the release, upgrades itself to `store:<id>`;
  - an artist pin keys on their MusicBrainz id (`mb:`) or their folded name (`name:`), and a name
    pin becomes an `mb:` pin, in its place, once the id is known;
  - the toggle is idempotent - it says what should be, not "flip" - and a new pin goes first; the
    PUT takes the whole ordered list, keeps that order, removes what it leaves out and never adds;
  - per user, through current_user (`local` while logins are off), and an old database gains the
    table; a PUT or toggle another website asks for is refused by the same-origin guard;
  - NEVER Navidrome's stars: nothing here ever asks Navidrome to star, unstar or list stars;
  - adopt_local hands local's pins and preferences to the first admin, theirs winning.
"""

import asyncio
import json
import shutil
import sqlite3
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from src import pins as rules  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.navidrome_endpoint import navidrome  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import pins as route  # noqa: E402
from src.routes import search_musicbrainz  # noqa: E402
from src.routes import store_album as bridge  # noqa: E402
from src.store import SCHEMA, JobStore  # noqa: E402
from src.users import LOCAL_USER, current_user  # noqa: E402
from test_navidrome import failed, ok  # noqa: E402

ROUTE = "/deadwax/me/pins"
TOGGLE = "/deadwax/me/pins/toggle"

CD = "11111111-1111-4111-8111-111111111111"        # Dummy, the 1994 CD
VINYL = "f5804905-0000-4000-8000-000000000000"     # Dummy, the 2014 vinyl
THIRD = "33333333-3333-4333-8333-333333333333"     # Third
LOOSE = "44444444-4444-4444-8444-444444444444"     # a release no folder holds yet
GROUP = "48140466-cff6-3222-bd55-63c27e43190d"
PORTISHEAD = "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"

CD_PATH = "Portishead/Dummy (1994)"
VINYL_PATH = "Portishead/Dummy (1994) [20th Anniversary Reissue 180gram]"
THIRD_PATH = "Portishead/Third (2008)"


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
    """Navidrome holding the albums a test puts in `albums` (id -> its answer); every request kept."""
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")
    seen: list[httpx.Request] = []
    state = {"albums": {}, "down": False}

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
                     if q.get("query") == album.get("musicBrainzId")
                     or (words and all(word in album["name"].lower() for word in words))]
            return httpx.Response(200, json=ok(searchResult3={"album": found}))
        return httpx.Response(200, json=failed(0, f"not this one: {endpoint}"))

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(handle), base_url="http://navidrome:4533/rest")
    yield state, seen
    run(navidrome.close_client())


def album(album_id, release, name="Dummy"):
    return {"id": album_id, "name": name, "musicBrainzId": release, "coverArt": f"al-{album_id}_0"}


def folder(root, path, store, release, album_name="Dummy", group=GROUP):
    (root / path).mkdir(parents=True, exist_ok=True)
    return run(store.index_upsert(str(root), {
        "path": path, "release_mbid": release, "release_group_mbid": group, "artist": "Portishead",
        "album": album_name, "year": "1994", "edition": "", "track_count": 11, "formats": ["flac"],
    }))


def client(store, user=None):
    app = start()
    app.state.store = store
    if user:
        app.dependency_overrides[current_user] = lambda: user
    return TestClient(app)  # no `with`: no lifespan, nothing connects


def rows(store):
    with sqlite3.connect(store.path) as connection:
        return connection.execute("SELECT user, kind, ref, position FROM pins ORDER BY user, position").fetchall()


def pin_album(store, release=None, navidrome_id=None, label="Dummy", **more):
    body = {"kind": "album", "pinned": True, "label": label, "sub": "Portishead", **more}
    if release:
        body["release_mbid"] = release
    if navidrome_id:
        body["navidrome_id"] = navidrome_id
    return client(store).post(TOGGLE, json=body)


def refs(answer):
    return [pin["ref"] for pin in answer.json()["pins"]]


# ---------------------------------------------------------------- the rules

def test_the_rules_say_which_refs_are_well_formed():
    assert rules.valid_ref("album", "store:12") and rules.valid_ref("album", f"release:{CD}")
    assert rules.valid_ref("artist", f"mb:{PORTISHEAD}") and rules.valid_ref("artist", "name:bjork")
    for kind, ref in [("album", "store:0"), ("album", "store:-1"), ("album", "store:12x"), ("album", "release:nope"),
                      ("album", f"mb:{CD}"), ("artist", "store:12"), ("artist", "name:"), ("artist", "name:   "),
                      ("artist", "name:a\nb"), ("artist", "mb:nope"), ("album", "nd:abc"), ("song", "store:1")]:
        assert not rules.valid_ref(kind, ref), (kind, ref)


def test_an_artist_is_known_by_their_mbid_else_by_their_name_as_typed_folded():
    assert rules.artist_ref(PORTISHEAD, "Portishead") == f"mb:{PORTISHEAD}"
    assert rules.artist_ref(None, "Björk") == rules.artist_ref(None, "BJORK") == "name:bjork"
    assert rules.artist_ref(None, "JAY\u2010Z") == "name:jay-z"
    assert rules.artist_ref(None, "   ") is None and rules.artist_ref("not-an-id", "") is None


def test_the_mbid_rule_is_the_search_routes_own():
    assert rules.MBID_PATTERN == search_musicbrainz.MBID_PATTERN


def test_a_put_list_reorders_and_removes_and_never_adds():
    stored = [{"kind": "album", "ref": "store:1"}, {"kind": "artist", "ref": "name:x"}, {"kind": "album", "ref": "store:2"}]
    wanted = [("album", "store:2"), ("album", "store:9"), ("album", "store:1"), ("album", "store:2")]
    assert [pin["ref"] for pin in rules.ordered(stored, wanted)] == ["store:2", "store:1"]


def test_a_put_list_made_from_what_the_page_knew_leaves_a_pin_made_since_where_it_is():
    """Home's Edit names every pin it was told of; one pinned on another device since keeps its place."""
    pin = lambda ref: {"kind": "album", "ref": ref}  # noqa: E731
    stored = [pin("store:9"), pin("store:1"), pin("store:2"), pin("store:3")]
    knew = [("album", "store:1"), ("album", "store:2"), ("album", "store:3")]
    moved = rules.ordered(stored, [("album", "store:3"), ("album", "store:1"), ("album", "store:2")], knew)
    assert [p["ref"] for p in moved] == ["store:9", "store:3", "store:1", "store:2"]
    #? a removal leaves the place it held; the pin the page never heard of stays, at the end too
    at_end = [pin("store:1"), pin("store:2"), pin("store:9")]
    removed = rules.ordered(at_end, [("album", "store:2")], [("album", "store:1"), ("album", "store:2")])
    assert [p["ref"] for p in removed] == ["store:2", "store:9"]
    #? a pin the page knew of and another device removed since stays removed; no `known`: the list is all
    assert [p["ref"] for p in rules.ordered(at_end, [("album", "store:1")], [("album", "store:1"), ("album", "store:7")])] == ["store:1", "store:2", "store:9"]
    assert [p["ref"] for p in rules.ordered(at_end, [("album", "store:2")])] == ["store:2"]


def test_artist_names_fold_as_the_app_folds_them():
    """tests/fixtures/name_folds.json is what both sides answer: pins.sim.cjs holds lib/pins.ts to it."""
    cases = json.loads((Path(__file__).parent / "fixtures" / "name_folds.json").read_text())["cases"]
    assert len(cases) > 10
    for name, folded in cases:
        assert rules.artist_ref(None, name) == (f"name:{folded}" if folded else None), name


# ---------------------------------------------------------------- albums

def test_nothing_pinned(store):
    assert client(store).get(ROUTE).json() == {"pins": [], "can_save": True}


def test_an_album_pin_keys_on_the_store_row_and_opens_navidromes_album(store, root, navidrome_up):
    state, _ = navidrome_up
    state["albums"]["nd-cd"] = album("nd-cd", CD)
    row_id = folder(root, CD_PATH, store, CD)

    answer = pin_album(store, CD, "nd-cd", cover="al-nd-cd")

    assert answer.status_code == 200
    assert answer.json() == {"pins": [{
        "kind": "album", "ref": f"store:{row_id}", "label": "Dummy", "sub": "Portishead", "state": "present",
        "navidrome_id": "nd-cd", "cover": "al-nd-cd_0", "release_mbid": CD,
    }], "can_save": True}
    assert rows(store) == [(LOCAL_USER, "album", f"store:{row_id}", 0)]


def test_pinning_by_navidromes_id_reads_the_release_from_navidrome(store, root, navidrome_up):
    state, seen = navidrome_up
    state["albums"]["nd-cd"] = album("nd-cd", CD)
    row_id = folder(root, CD_PATH, store, CD)

    answer = pin_album(store, navidrome_id="nd-cd")

    assert refs(answer) == [f"store:{row_id}"]
    assert seen[0].url.path.endswith("/getAlbum")


def test_an_album_with_no_release_id_cant_be_pinned(store, root, navidrome_up):
    state, _ = navidrome_up
    state["albums"]["nd-rip"] = {"id": "nd-rip", "name": "Old rip", "musicBrainzId": ""}

    answer = pin_album(store, navidrome_id="nd-rip")

    assert answer.status_code == 422
    assert "release id" in answer.json()["detail"]
    assert rows(store) == []


def test_pinning_by_navidromes_id_while_navidrome_cant_be_asked_is_a_503_never_no_release_id(store, root, navidrome_up):
    """The menu pins by Navidrome's id when the album answer isn't in hand: a Navidrome that didn't answer
    says nothing about the album, so the page is told to try again - not that it has no release id."""
    state, _ = navidrome_up
    state["albums"]["nd-cd"] = album("nd-cd", CD)
    folder(root, CD_PATH, store, CD)
    state["down"] = True

    refused = pin_album(store, navidrome_id="nd-cd")

    assert refused.status_code == 503
    assert "Navidrome" in refused.json()["detail"] and "release id" not in refused.json()["detail"]
    assert rows(store) == []

    #? Navidrome answering that it has no such album: a 422 that says so
    state["down"] = False
    gone = pin_album(store, navidrome_id="nd-nothing")
    assert gone.status_code == 422 and "doesn't have it" in gone.json()["detail"]


def test_an_unpin_by_navidromes_id_needs_no_navidrome(store, root, navidrome_up):
    state, _ = navidrome_up
    state["albums"]["nd-cd"] = album("nd-cd", CD)
    folder(root, CD_PATH, store, CD)
    pin_album(store, CD, "nd-cd")
    state["down"] = True

    answer = client(store).post(TOGGLE, json={"kind": "album", "pinned": False, "navidrome_id": "nd-cd"})

    assert answer.status_code == 200 and answer.json()["pins"] == [] and rows(store) == []


def test_the_toggle_is_idempotent(store, root, navidrome_up):
    folder(root, CD_PATH, store, CD)
    for _ in range(2):
        assert len(pin_album(store, CD).json()["pins"]) == 1
    assert len(rows(store)) == 1
    for _ in range(2):
        gone = client(store).post(TOGGLE, json={"kind": "album", "pinned": False, "release_mbid": CD})
        assert gone.status_code == 200 and gone.json()["pins"] == []
    assert rows(store) == []


def test_a_new_pin_goes_first_and_the_order_is_kept(store, root, navidrome_up):
    ids = {release: folder(root, path, store, release, name) for release, path, name in
           [(CD, CD_PATH, "Dummy"), (VINYL, VINYL_PATH, "Dummy"), (THIRD, THIRD_PATH, "Third")]}
    for release in (CD, VINYL, THIRD):
        pin_album(store, release)

    assert refs(client(store).get(ROUTE)) == [f"store:{ids[THIRD]}", f"store:{ids[VINYL]}", f"store:{ids[CD]}"]


def test_a_put_takes_the_whole_ordered_list(store, root, navidrome_up):
    ids = {release: folder(root, path, store, release, name) for release, path, name in
           [(CD, CD_PATH, "Dummy"), (VINYL, VINYL_PATH, "Dummy"), (THIRD, THIRD_PATH, "Third")]}
    for release in (CD, VINYL, THIRD):
        pin_album(store, release)

    #? the CD first, Third after it, the vinyl left out - and a ref nobody pinned passed over
    put = client(store).put(ROUTE, json={"pins": [
        {"kind": "album", "ref": f"store:{ids[CD]}"}, {"kind": "album", "ref": "store:999"},
        {"kind": "album", "ref": f"store:{ids[THIRD]}"},
    ]})

    assert put.status_code == 200
    assert refs(put) == [f"store:{ids[CD]}", f"store:{ids[THIRD]}"]
    assert [row[2:] for row in rows(store)] == [(f"store:{ids[CD]}", 0), (f"store:{ids[THIRD]}", 1)]
    assert refs(client(store).get(ROUTE)) == [f"store:{ids[CD]}", f"store:{ids[THIRD]}"]


@pytest.mark.parametrize("body", [
    {"pins": [{"kind": "album", "ref": "nope"}]},
    {"pins": [{"kind": "album", "ref": f"mb:{CD}"}]},
    {"pins": [{"kind": "song", "ref": "store:1"}]},
    {"pins": [{"kind": "album", "ref": "store:1", "label": "extra"}]},
    {"pins": [{"kind": "album", "ref": f"store:{n}"} for n in range(1, rules.PINS_MAX + 2)]},
    {"order": []},
])
def test_a_put_that_isnt_a_list_of_pins_is_refused_and_nothing_changes(store, root, navidrome_up, body):
    row_id = folder(root, CD_PATH, store, CD)
    pin_album(store, CD)

    assert client(store).put(ROUTE, json=body).status_code == 422
    assert rows(store) == [(LOCAL_USER, "album", f"store:{row_id}", 0)]


@pytest.mark.parametrize("body", [
    {"kind": "album", "pinned": True},
    {"kind": "album", "pinned": True, "release_mbid": CD, "mbid": PORTISHEAD},
    {"kind": "album", "pinned": True, "release_mbid": "Dummy"},
    {"kind": "artist", "pinned": True, "name": "Portishead"},
    {"kind": "artist", "pinned": True, "release_mbid": CD, "mbid": PORTISHEAD},
    {"kind": "artist", "pinned": True, "mbid": PORTISHEAD, "theme": "dark"},
    {"kind": "playlist", "pinned": True, "navidrome_id": "x"},
    {"kind": "album", "release_mbid": CD},
])
def test_a_toggle_that_doesnt_say_what_it_is_is_refused(store, root, navidrome_up, body):
    assert client(store).post(TOGGLE, json=body).status_code == 422
    assert rows(store) == []


def test_home_holds_so_many_pins_and_says_so(store, root, navidrome_up, monkeypatch):
    monkeypatch.setattr(rules, "PINS_MAX", 2)
    for path, release in [(CD_PATH, CD), (VINYL_PATH, VINYL)]:
        folder(root, path, store, release)
        pin_album(store, release)

    refused = pin_album(store, THIRD)

    assert refused.status_code == 409
    assert "up to 2" in refused.json()["detail"]
    assert len(rows(store)) == 2


def test_a_pin_follows_its_album_through_a_refile_and_navidromes_new_id(store, root, navidrome_up):
    """Re-filed through the old editor: the same store row at a new path, and - as the stub's ids
    are its folders' - a new Navidrome album for it. The pin opens the album as it is now."""
    state, _ = navidrome_up
    state["albums"]["nd-cd"] = album("nd-cd", CD)
    row_id = folder(root, CD_PATH, store, CD)
    assert pin_album(store, CD, "nd-cd").json()["pins"][0]["navidrome_id"] == "nd-cd"

    moved_to = "Portishead/Dummy (1994) [Remaster]"
    shutil.move(str(root / CD_PATH), str(root / moved_to))
    assert run(store.index_move(str(root), CD_PATH, moved_to)) == row_id
    del state["albums"]["nd-cd"]
    state["albums"]["nd-cd-moved"] = album("nd-cd-moved", CD)

    pinned = client(store).get(ROUTE).json()["pins"]

    assert [(pin["ref"], pin["state"], pin["navidrome_id"], pin["cover"]) for pin in pinned] == \
        [(f"store:{row_id}", "present", "nd-cd-moved", "al-nd-cd-moved_0")]
    #? kept for next time, and the bridge no longer hands out the old id either
    with sqlite3.connect(store.path) as connection:
        assert connection.execute("SELECT navidrome_id, cover FROM pins").fetchall() == [("nd-cd-moved", "al-nd-cd-moved_0")]
    assert bridge.known_navidrome_id(CD) == "nd-cd-moved"


def test_a_merge_is_followed_along_merged_into(store, root, navidrome_up):
    disc_two = folder(root, "Portishead/Dummy (Disc 2)", store, CD)
    whole = folder(root, CD_PATH, store, CD)
    #? pinned while the disc folder was the first live row of the release
    with sqlite3.connect(store.path) as connection:
        connection.execute("INSERT INTO pins VALUES ('local', 'album', ?, 'Dummy', 'Portishead', NULL, NULL, 0, 'then')", (f"store:{disc_two}",))
    shutil.rmtree(root / "Portishead/Dummy (Disc 2)")
    assert run(store.index_merge(str(root), "Portishead/Dummy (Disc 2)", CD_PATH)) == whole

    pinned = client(store).get(ROUTE).json()["pins"]

    assert [(pin["ref"], pin["state"]) for pin in pinned] == [(f"store:{whole}", "present")]
    assert [row[2] for row in rows(store)] == [f"store:{whole}"]


def test_a_deleted_album_reads_as_gone(store, root, navidrome_up):
    state, _ = navidrome_up
    state["albums"]["nd-cd"] = album("nd-cd", CD)
    row_id = folder(root, CD_PATH, store, CD)
    pin_album(store, CD, "nd-cd")
    shutil.rmtree(root / CD_PATH)
    run(store.index_gone(str(root), CD_PATH, "deleted"))

    pinned = client(store).get(ROUTE).json()["pins"]

    assert [(pin["ref"], pin["state"], pin["navidrome_id"], pin["label"]) for pin in pinned] == \
        [(f"store:{row_id}", "gone", None, "Dummy")]


def test_a_folder_gone_since_reads_as_missing(store, root, navidrome_up):
    row_id = folder(root, CD_PATH, store, CD)
    pin_album(store, CD)
    shutil.rmtree(root / CD_PATH)

    pinned = client(store).get(ROUTE).json()["pins"]

    assert [(pin["ref"], pin["state"], pin["navidrome_id"]) for pin in pinned] == [(f"store:{row_id}", "missing", None)]
    with sqlite3.connect(store.path) as connection:
        assert connection.execute("SELECT state FROM store_album WHERE id = ?", (row_id,)).fetchone() == ("missing",)


def test_a_pin_whose_album_has_gone_opens_a_copy_of_the_same_release(store, root, navidrome_up):
    first = folder(root, CD_PATH, store, CD)
    copy = folder(root, "Portishead/Dummy (1994) [copy]", store, CD)
    assert refs(pin_album(store, CD)) == [f"store:{first}"]
    shutil.rmtree(root / CD_PATH)
    run(store.index_gone(str(root), CD_PATH, "deleted"))

    pinned = client(store).get(ROUTE).json()["pins"]

    assert [(pin["ref"], pin["state"]) for pin in pinned] == [(f"store:{copy}", "present")]


def test_two_pins_that_come_to_one_album_are_one_pin_in_the_first_ones_place(store, root, navidrome_up):
    """A pin on a Dummy deleted since, and one on its copy: both now name the copy - one pin, where the
    first was, and written back so (two rows of one ref would break the table's key on every read)."""
    first = folder(root, CD_PATH, store, CD)
    copy = folder(root, "Portishead/Dummy (1994) [copy]", store, CD)
    with sqlite3.connect(store.path) as connection:
        connection.executemany("INSERT INTO pins VALUES ('local', ?, ?, ?, '', NULL, NULL, ?, 'then')", [
            ("album", f"store:{first}", "Dummy", 0), ("artist", f"mb:{PORTISHEAD}", "Portishead", 1),
            ("album", f"store:{copy}", "Dummy", 2)])
    shutil.rmtree(root / CD_PATH)
    run(store.index_gone(str(root), CD_PATH, "deleted"))

    answer = client(store).get(ROUTE)

    assert answer.status_code == 200
    assert refs(answer) == [f"store:{copy}", f"mb:{PORTISHEAD}"]
    assert [row[2:] for row in rows(store)] == [(f"store:{copy}", 0), (f"mb:{PORTISHEAD}", 1)]


def test_a_put_made_from_what_the_page_knew_keeps_a_pin_made_since_on_another_device(store, root, navidrome_up):
    ids = {release: folder(root, path, store, release, name) for release, path, name in
           [(CD, CD_PATH, "Dummy"), (VINYL, VINYL_PATH, "Dummy"), (THIRD, THIRD_PATH, "Third")]}
    pin_album(store, CD)
    knew = refs(pin_album(store, VINYL))           # what this page was told: the vinyl, the CD
    pin_album(store, THIRD)                        # ...and then, on the phone, Third

    #? this page moves the CD up and says what it knew: Third keeps its place, first
    moved = client(store).put(ROUTE, json={"pins": [{"kind": "album", "ref": f"store:{ids[CD]}"}, {"kind": "album", "ref": f"store:{ids[VINYL]}"}],
                                           "known": [{"kind": "album", "ref": ref} for ref in knew]})
    assert refs(moved) == [f"store:{ids[THIRD]}", f"store:{ids[CD]}", f"store:{ids[VINYL]}"]

    #? and a removal made from what it then knew leaves Third alone too
    removed = client(store).put(ROUTE, json={"pins": [{"kind": "album", "ref": f"store:{ids[VINYL]}"}],
                                             "known": [{"kind": "album", "ref": f"store:{ids[CD]}"}, {"kind": "album", "ref": f"store:{ids[VINYL]}"}]})
    assert refs(removed) == [f"store:{ids[THIRD]}", f"store:{ids[VINYL]}"]
    assert [row[2] for row in rows(store)] == [f"store:{ids[THIRD]}", f"store:{ids[VINYL]}"]


def test_a_release_pin_upgrades_itself_once_the_index_holds_the_release(store, root, navidrome_up):
    """Pinned before the first scan: no store row yet, so `release:`; the next read finds the row."""
    state, _ = navidrome_up
    state["albums"]["nd-loose"] = album("nd-loose", LOOSE, "Roseland")

    first = pin_album(store, LOOSE, "nd-loose", label="Roseland NYC Live")
    assert [(pin["ref"], pin["state"], pin["navidrome_id"]) for pin in first.json()["pins"]] == [(f"release:{LOOSE}", "present", "nd-loose")]

    row_id = folder(root, "Portishead/Roseland NYC Live (1998)", store, LOOSE, "Roseland NYC Live")

    assert refs(client(store).get(ROUTE)) == [f"store:{row_id}"]
    assert [row[2] for row in rows(store)] == [f"store:{row_id}"]


def test_a_put_naming_a_release_pin_upgraded_since_keeps_it(store, root, navidrome_up):
    pin_album(store, LOOSE, label="Roseland NYC Live")
    pin_album(store, CD)  # no folder either: release: too
    row_id = folder(root, "Portishead/Roseland NYC Live (1998)", store, LOOSE, "Roseland NYC Live")

    #? the page's list was drawn before the index held Roseland
    put = client(store).put(ROUTE, json={"pins": [{"kind": "album", "ref": f"release:{LOOSE}"}, {"kind": "album", "ref": f"release:{CD}"}]})

    assert refs(put) == [f"store:{row_id}", f"release:{CD}"]


def test_navidrome_down_leaves_the_id_last_opened_standing(store, root, navidrome_up):
    state, _ = navidrome_up
    state["albums"]["nd-cd"] = album("nd-cd", CD)
    folder(root, CD_PATH, store, CD)
    pin_album(store, CD, "nd-cd")
    bridge.forget_navidrome_ids()
    state["down"] = True

    pinned = client(store).get(ROUTE).json()["pins"]

    assert [(pin["state"], pin["navidrome_id"]) for pin in pinned] == [("present", "nd-cd")]


def test_an_album_navidrome_hasnt_found_has_no_id_to_open(store, root, navidrome_up):
    folder(root, CD_PATH, store, CD)

    pinned = pin_album(store, CD).json()["pins"]

    assert [(pin["state"], pin["navidrome_id"]) for pin in pinned] == [("present", None)]


def test_pins_are_never_navidromes_stars(store, root, navidrome_up):
    state, seen = navidrome_up
    state["albums"]["nd-cd"] = album("nd-cd", CD)
    folder(root, CD_PATH, store, CD)
    pin_album(store, CD, "nd-cd")
    client(store).post(TOGGLE, json={"kind": "artist", "pinned": True, "mbid": PORTISHEAD, "name": "Portishead"})
    client(store).get(ROUTE)
    client(store).post(TOGGLE, json={"kind": "album", "pinned": False, "release_mbid": CD})

    asked = {request.url.path.rsplit("/", 1)[-1] for request in seen}
    assert asked <= {"getAlbum", "search3"}
    assert not asked & {"star", "unstar", "getStarred", "getStarred2"}


# ---------------------------------------------------------------- artists

def test_an_artist_pin_keys_on_their_mbid(store):
    answer = client(store).post(TOGGLE, json={"kind": "artist", "pinned": True, "mbid": PORTISHEAD, "name": "Portishead",
                                               "navidrome_id": "ar-portishead", "cover": "ar-portishead"})

    assert answer.json()["pins"] == [{
        "kind": "artist", "ref": f"mb:{PORTISHEAD}", "label": "Portishead", "sub": "", "state": "present",
        "navidrome_id": "ar-portishead", "cover": "ar-portishead", "mbid": PORTISHEAD,
    }]


def test_an_artist_with_no_mbid_keys_on_their_name_and_takes_the_mbid_in_place_once_known(store, root, navidrome_up):
    folder(root, CD_PATH, store, CD)
    pin_album(store, CD)
    named = client(store).post(TOGGLE, json={"kind": "artist", "pinned": True, "navidrome_id": "ar-bjork", "name": "Björk"})
    assert refs(named)[0] == "name:bjork"
    client(store).put(ROUTE, json={"pins": [{"kind": "album", "ref": refs(named)[1]}, {"kind": "artist", "ref": "name:bjork"}]})

    known = client(store).post(TOGGLE, json={"kind": "artist", "pinned": True, "navidrome_id": "ar-bjork", "name": "Björk",
                                              "mbid": "87c5dedd-371d-4a53-9f7f-80522fb7f3cb"})

    #? one pin, where it was (second), keyed on the id now
    assert refs(known)[1:] == ["mb:87c5dedd-371d-4a53-9f7f-80522fb7f3cb"]
    assert len(rows(store)) == 2


def test_an_artist_without_an_mbid_needs_a_name(store):
    answer = client(store).post(TOGGLE, json={"kind": "artist", "pinned": True, "navidrome_id": "ar-x"})
    assert answer.status_code == 422
    assert rows(store) == []


def test_an_artist_is_unpinned_by_navidromes_id_for_them(store):
    client(store).post(TOGGLE, json={"kind": "artist", "pinned": True, "navidrome_id": "ar-bjork", "name": "Björk"})

    answer = client(store).post(TOGGLE, json={"kind": "artist", "pinned": False, "navidrome_id": "ar-bjork"})

    assert answer.json()["pins"] == [] and rows(store) == []


def test_two_navidrome_artists_whose_names_fold_alike_are_one_pin(store):
    """No MusicBrainz id on either: "Björk" and "Bjork" are one `name:bjork` - one pin, which an unpin
    from either page removes. lib/pins.ts isPinOf matches the same way, so both pages show it pinned."""
    client(store).post(TOGGLE, json={"kind": "artist", "pinned": True, "navidrome_id": "ar-1", "name": "Björk"})

    again = client(store).post(TOGGLE, json={"kind": "artist", "pinned": True, "navidrome_id": "ar-2", "name": "Bjork"})
    assert refs(again) == ["name:bjork"] and len(rows(store)) == 1

    gone = client(store).post(TOGGLE, json={"kind": "artist", "pinned": False, "navidrome_id": "ar-1", "name": "BJORK"})
    assert gone.json()["pins"] == [] and rows(store) == []


def test_two_artists_with_their_own_mbids_are_two_pins_whatever_navidromes_id_says(store):
    other = "87c5dedd-371d-4a53-9f7f-80522fb7f3cb"
    client(store).post(TOGGLE, json={"kind": "artist", "pinned": True, "mbid": PORTISHEAD, "navidrome_id": "ar-x", "name": "Portishead"})
    both = client(store).post(TOGGLE, json={"kind": "artist", "pinned": True, "mbid": other, "navidrome_id": "ar-x", "name": "Other"})
    assert refs(both) == [f"mb:{other}", f"mb:{PORTISHEAD}"]

    one = client(store).post(TOGGLE, json={"kind": "artist", "pinned": False, "mbid": other, "navidrome_id": "ar-x"})
    assert refs(one) == [f"mb:{PORTISHEAD}"]


# ---------------------------------------------------------------- users, the database, the guard

def test_the_user_is_local_while_logins_are_off_and_each_user_has_their_own(store, root, navidrome_up):
    folder(root, CD_PATH, store, CD)
    pin_album(store, CD)
    client(store, "james").post(TOGGLE, json={"kind": "artist", "pinned": True, "mbid": PORTISHEAD, "name": "Portishead"})

    assert [row[:2] for row in rows(store)] == [("james", "artist"), (LOCAL_USER, "album")]
    assert [pin["kind"] for pin in client(store).get(ROUTE).json()["pins"]] == ["album"]
    assert [pin["kind"] for pin in client(store, "james").get(ROUTE).json()["pins"]] == ["artist"]


def test_the_user_comes_from_the_dependency_never_middleware():
    for found in route.router.routes:
        assert current_user in [dependency.call for dependency in found.dependant.dependencies], found.path


def test_an_old_database_gains_the_table(tmp_path, root, navidrome_up):
    path = tmp_path / "old.db"
    old_schema = SCHEMA[:SCHEMA.index("CREATE TABLE IF NOT EXISTS pins")]
    with sqlite3.connect(path) as connection:
        connection.executescript(old_schema)
        assert connection.execute("SELECT name FROM sqlite_master WHERE name = 'pins'").fetchall() == []

    store = JobStore(str(path))
    store.init()
    folder(root, CD_PATH, store, CD)

    assert store.available
    assert len(pin_album(store, CD).json()["pins"]) == 1


def test_an_unusable_database_reads_as_nothing_pinned_and_refuses_writes(tmp_path):
    store = JobStore(str(tmp_path / "state" / "deadwax.db"))  # never init(): not available
    assert client(store).get(ROUTE).json() == {"pins": [], "can_save": False}
    assert client(store).put(ROUTE, json={"pins": []}).status_code == 503
    assert client(store).post(TOGGLE, json={"kind": "artist", "pinned": True, "mbid": PORTISHEAD, "name": "x"}).status_code == 503


def test_a_read_that_fails_just_now_is_a_503_never_nothing_pinned(store, root, navidrome_up, monkeypatch):
    """A database that is there but whose read failed (locked past its timeout, say): the page keeps
    what it had - "nothing pinned, can't save" would be drawn as the server's word."""
    folder(root, CD_PATH, store, CD)
    pin_album(store, CD)

    async def unreadable(_user):
        return None

    monkeypatch.setattr(store, "pins", unreadable)

    read = client(store).get(ROUTE)
    assert read.status_code == 503 and "read its pins" in read.json()["detail"]
    assert client(store).put(ROUTE, json={"pins": []}).status_code == 503
    assert client(store).post(TOGGLE, json={"kind": "album", "pinned": False, "release_mbid": CD}).status_code == 503
    assert len(rows(store)) == 1


def test_a_write_the_database_refuses_is_a_503_and_nothing_changes(store, root, navidrome_up, monkeypatch):
    for path, release in [(CD_PATH, CD), (VINYL_PATH, VINYL)]:
        folder(root, path, store, release)
        pin_album(store, release)
    before = rows(store)

    async def refused(_user, _pins):
        return False

    monkeypatch.setattr(store, "write_pins", refused)

    put = client(store).put(ROUTE, json={"pins": [{"kind": "album", "ref": before[1][2]}]})
    assert put.status_code == 503 and "refused the write" in put.json()["detail"]
    toggle = client(store).post(TOGGLE, json={"kind": "album", "pinned": False, "release_mbid": CD})
    assert toggle.status_code == 503
    assert rows(store) == before


def test_a_write_another_website_asks_for_is_refused(store, root, navidrome_up):
    folder(root, CD_PATH, store, CD)
    elsewhere = {"Origin": "http://elsewhere.example:8080"}

    assert client(store).post(TOGGLE, json={"kind": "album", "pinned": True, "release_mbid": CD}, headers=elsewhere).status_code == 403
    assert rows(store) == []
    assert client(store).post(TOGGLE, json={"kind": "album", "pinned": True, "release_mbid": CD}, headers={"Origin": "http://testserver"}).status_code == 200

    refused = client(store).put(ROUTE, json={"pins": []}, headers=elsewhere)
    assert refused.status_code == 403
    assert len(rows(store)) == 1


def test_an_index_that_cant_be_read_is_not_every_album_gone(store, root, navidrome_up, monkeypatch):
    folder(root, CD_PATH, store, CD)
    pin_album(store, CD)

    async def unreadable(_ids):
        return None

    monkeypatch.setattr(store, "index_follow", unreadable)
    answer = client(store).get(ROUTE)

    assert answer.status_code == 503
    assert "store index" in answer.json()["detail"]
    assert len(rows(store)) == 1


def test_a_merge_chain_is_followed_only_so_far(store, root):
    chain = [folder(root, f"Disc {n}", store, CD) for n in range(rules.MERGE_HOPS + 3)]
    with sqlite3.connect(store.path) as connection:
        for this, then in zip(chain, chain[1:]):
            connection.execute("UPDATE store_album SET state = 'merged', merged_into = ? WHERE id = ?", (then, this))

    followed = run(store.index_follow([chain[-3], chain[0]]))

    #? two hops to the live row at the end; from the start, further than MERGE_HOPS - a broken index
    assert followed[chain[-3]]["id"] == chain[-1] and followed[chain[0]] is None


def test_a_merge_chain_that_loops_is_a_broken_index_and_the_pin_is_gone(store, root):
    a = folder(root, "A", store, CD)
    b = folder(root, "B", store, CD)
    with sqlite3.connect(store.path) as connection:
        connection.execute("UPDATE store_album SET state = 'merged', merged_into = ? WHERE id = ?", (b, a))
        connection.execute("UPDATE store_album SET state = 'merged', merged_into = ? WHERE id = ?", (a, b))

    followed = run(store.index_follow([a, b, 999]))

    assert followed == {a: None, b: None, 999: None}


# ---------------------------------------------------------------- adopt_local, for step 3

def prefs(store):
    with sqlite3.connect(store.path) as connection:
        return connection.execute("SELECT user, key, value FROM user_prefs ORDER BY user, key").fetchall()


def put_pins(store, user, refs_in_order):
    run(store.write_pins(user, [{"kind": "album", "ref": ref, "label": ref} for ref in refs_in_order]))


def test_adopting_local_hands_its_pins_and_preferences_to_the_first_admin(store):
    run(store.set_user_preferences(LOCAL_USER, {"quality_floor": "lossless", "get_mode": "pick", "_seeded": "1"}))
    run(store.set_user_preferences("james", {"get_mode": "sources"}))
    put_pins(store, LOCAL_USER, ["store:1", "store:2", "store:3"])
    put_pins(store, "james", ["store:2", "store:9"])

    assert run(store.adopt_local("james")) == (2, 2)

    #? theirs first and theirs winning; local's after, in local's order; local left with nothing
    assert [row[2:] for row in rows(store)] == [("store:2", 0), ("store:9", 1), ("store:1", 2), ("store:3", 3)]
    assert {row[0] for row in rows(store)} == {"james"}
    assert prefs(store) == [("james", "_seeded", "1"), ("james", "get_mode", "sources"), ("james", "quality_floor", "lossless")]
    #? and a second time there is nothing left to take
    assert run(store.adopt_local("james")) == (0, 0)


def test_adopting_into_local_itself_takes_nothing(store):
    put_pins(store, LOCAL_USER, ["store:1"])
    assert run(store.adopt_local(LOCAL_USER)) == (0, 0)
    assert rows(store) == [(LOCAL_USER, "album", "store:1", 0)]


def test_adopting_keeps_to_what_home_holds(store, monkeypatch):
    monkeypatch.setattr("src.store.PINS_MAX", 3)
    put_pins(store, LOCAL_USER, ["store:1", "store:2", "store:3"])
    put_pins(store, "james", ["store:9", "store:8"])

    assert run(store.adopt_local("james"))[0] == 1
    assert [row[2] for row in rows(store)] == ["store:9", "store:8", "store:1"]


def test_adopting_with_no_store_says_it_couldnt(tmp_path):
    assert run(JobStore(str(tmp_path / "x.db")).adopt_local("james")) is None
