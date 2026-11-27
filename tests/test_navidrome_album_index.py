"""
The Library's whole album list (2.0.0-player.59, a better Library) - routes/navidrome.py's `/album_index`: every
album of the asker's library (`yours`: getAlbumList2 `starred`) or of the store (`newest`), read a page of
INDEX_PAGE at a time on deadwax's side of the network, each album once, trimmed to INDEX_FIELDS, in one answer
with an ETag.

Through the whole app start() builds (no lifespan) with logins on - step 6's fixtures (test_player_as_you.py) - and
a fake Navidrome shaped from 0.64.2's source: getAlbumList2 honouring `size` and `offset`, `starred` answering the
asker's own stars, `newest` every album; token auth checked for real, every call kept with who made it.

What these hold:

  - PAGING: INDEX_PAGE a call, until a short page; `truncated` after INDEX_MAX's pages with no call past them.
  - THE LIST TYPE per scope - `starred` or `newest` - and nothing else the page sends passed on.
  - EACH ALBUM ONCE, AS SENT: an id repeated across pages left out; non-dicts and entries without a string id
    dropped; only INDEX_FIELDS kept, and only those present, values untouched; Navidrome's order kept.
  - NEVER A PARTIAL LIST: a page failing fails the answer, in Navidrome's words.
  - AN ETAG: stable for the same body, a 304 on If-None-Match, Cache-Control no-cache; a new star a new tag.
  - WHO IS ASKED: the signed-in user with logins on; the shared account with logins off and for break-glass; a
    refused login the 401 that ends the session; a bad scope a 422 asking nothing.
"""

import hashlib
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi.testclient import TestClient

from src import auth, index_keep, library, player_cache
from src.api import navidrome_endpoint
from src.api.navidrome_endpoint import navidrome
from src.config import Config
from src.player_cache import Mp4Cache
from src.routes import navidrome as navidrome_routes
from tests import test_personal_libraries
from tests.test_personal_libraries import NAVIDROME, failed, ok, run, signed_in, wire
from tests import test_player_as_you
from tests.test_player_as_you import Player

#? step 5's fixture - its app, store and Navidrome - which `listing` builds on
on = test_personal_libraries.on

INDEX = "/deadwax/navidrome/album_index"


class Lister(Player):
    """
    Step 6's Navidrome with `count` albums more, newest first, each carrying more than the Library reads (a path, the
    genres list, OpenSubsonic's extras) - getAlbumList2 pages them by `size` and `offset`: `newest` all of them,
    `starred` the asker's own stars. `repeat`: a page starts with the album the last page ended on, as a filing
    between two pages can push one along; `junk`: a page also carries a non-dict and entries without a string id;
    `fail_at`: the page at that offset fails, in Navidrome's words.
    """

    def __init__(self, count: int = 1200):
        super().__init__()
        self.albums.clear()
        for n in range(count):
            self.albums[f"al-{n}"] = {
                "id": f"al-{n}", "name": f"Album {n}", "artist": "Portishead", "artistId": "ar-1", "coverArt": f"al-{n}",
                "year": 1990 + n % 30, "genre": "Trip hop", "created": f"2026-01-01T00:00:{n % 60:02d}Z", "songCount": 10,
                "duration": 2400, "musicBrainzId": "", "path": f"/music/{n}", "genres": [{"name": "Trip hop"}],
                "isCompilation": False, "sortName": f"album {n}",
            }
        self.repeat = False
        self.junk = False
        self.fail_at: int | None = None

    def handle(self, request: httpx.Request) -> httpx.Response:
        endpoint = request.url.path.removeprefix("/rest/")
        if endpoint != "getAlbumList2":
            return super().handle(request)
        q = {key: values[0] for key, values in parse_qs(urlparse(str(request.url)).query, keep_blank_values=True).items()}
        user = q.get("u", "").lower()
        self.calls.append((user, endpoint, q))
        token = hashlib.md5((self.passwords.get(user, "") + q.get("s", "")).encode()).hexdigest()
        if user not in self.passwords or q.get("t") != token:
            return httpx.Response(200, json=failed(40, "Wrong username or password"))
        offset, size = int(q.get("offset", 0)), min(int(q.get("size", 10)), 500)
        if self.fail_at == offset:
            return httpx.Response(200, json=failed(0, "database is locked"))
        stars = self.starred(user)
        listed = [{**album, **({"starred": "2026-10-15T09:00:00.000Z"} if album["id"] in stars else {})}
                  for album in self.albums.values() if q.get("type") != "starred" or album["id"] in stars]
        page = listed[offset:offset + size]
        if self.repeat and offset and page:
            page = [listed[offset - 1], *page[:-1]]
        if self.junk:
            page = [*page, "not an album", {"name": "no id"}, {"id": 7, "name": "a number for an id"}]
        return httpx.Response(200, json=ok(albumList2={"album": page}))

    def asked(self) -> list[tuple[str, dict]]:
        return [(user, q) for user, called, q in self.calls if called == "getAlbumList2"]


@pytest.fixture
def listing(on, monkeypatch, tmp_path):
    """Step 5's `on` with the Lister as its Navidrome - the shared client wired to it."""
    fake = Lister()
    wire(fake)
    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(fake.handle), base_url=f"{NAVIDROME}/rest")
    monkeypatch.setattr(player_cache, "cache", Mp4Cache(tmp_path / "deadwax-player"))
    navidrome_routes.forget_access()
    navidrome_endpoint.forget_confirmed()
    on.fake = fake
    yield on
    navidrome_routes.forget_access()
    navidrome_endpoint.forget_confirmed()
    run(navidrome.close_client())


# ---------------------------------------------------------------- paging, and the list type per scope

def test_the_store_is_every_album_read_500_a_call_until_a_short_page(listing):
    answer = signed_in(listing, "james").get(f"{INDEX}?scope=store")

    assert answer.status_code == 200
    body = answer.json()
    assert [album["id"] for album in body["albums"]] == [f"al-{n}" for n in range(1200)]
    assert body["truncated"] is False
    #? the first page alone, then a round of PAGES_AT_ONCE - the list ended in its second page, and the two
    #? asked past it were empty answers nothing waited for (2.1.49)
    assert [(q["type"], q["size"], q["offset"]) for _, q in listing.fake.asked()] == [
        ("newest", "500", str(offset)) for offset in (0, 500, 1000, 1500, 2000)]


def test_a_full_last_page_asks_once_more_and_finds_the_end(listing):
    listing.fake.__init__(1000)

    body = signed_in(listing, "james").get(f"{INDEX}?scope=store").json()

    assert len(body["albums"]) == 1000 and body["truncated"] is False
    assert [q["offset"] for _, q in listing.fake.asked()] == ["0", "500", "1000", "1500", "2000"]


def test_yours_is_your_starred_albums_asked_as_you(listing):
    listing.fake.starred("ethan").update({"al-3", "al-700"})
    listing.fake.starred("james").add("al-1")

    body = signed_in(listing, "ethan").get(f"{INDEX}?scope=yours").json()

    assert [album["id"] for album in body["albums"]] == ["al-3", "al-700"]
    assert all(album["starred"] for album in body["albums"])
    assert [(user, q["type"]) for user, q in listing.fake.asked()] == [("ethan", "starred")]


def test_nothing_the_page_sends_reaches_navidrome_but_the_scope(listing):
    signed_in(listing, "ethan").get(f"{INDEX}?scope=store&type=random&size=5&offset=9&u=james&musicFolderId=2&f=xml")

    user, q = listing.fake.asked()[0]
    assert user == "ethan"
    assert (q["type"], q["size"], q["offset"], q["f"]) == ("newest", "500", "0", "json")
    assert "musicFolderId" not in q


@pytest.mark.parametrize("path", [f"{INDEX}", f"{INDEX}?scope=frequent", f"{INDEX}?scope=", f"{INDEX}?scope=STORE"])
def test_a_scope_outside_the_two_is_refused_before_navidrome_is_asked(listing, path):
    client = signed_in(listing, "james")
    listing.fake.calls.clear()

    assert client.get(path).status_code == 422
    assert listing.fake.asked() == []


def test_past_twenty_full_pages_the_answer_says_truncated_and_asks_no_more(listing, monkeypatch):
    monkeypatch.setattr(navidrome_routes, "INDEX_PAGE", 10)
    monkeypatch.setattr(navidrome_routes, "INDEX_MAX", 200)

    body = signed_in(listing, "james").get(f"{INDEX}?scope=store").json()

    assert len(body["albums"]) == 200 and body["truncated"] is True
    assert [int(q["offset"]) for _, q in listing.fake.asked()] == list(range(0, 200, 10))
    assert {q["size"] for _, q in listing.fake.asked()} == {"10"}


def test_the_real_cap_is_twenty_pages_of_navidromes_500():
    assert (navidrome_routes.INDEX_PAGE, navidrome_routes.INDEX_MAX) == (500, 10000)
    assert navidrome_routes.SCOPE_LIST == {"yours": "starred", "store": "newest"}


# ---------------------------------------------------------------- each album once, as Navidrome sent it

def test_an_album_repeated_across_pages_is_left_out(listing):
    listing.fake.repeat = True

    ids = [album["id"] for album in signed_in(listing, "james").get(f"{INDEX}?scope=store").json()["albums"]]

    assert len(ids) == len(set(ids))
    assert ids[:3] == ["al-0", "al-1", "al-2"] and "al-499" in ids


def test_entries_that_are_not_albums_with_an_id_are_dropped(listing):
    listing.fake.__init__(3)
    listing.fake.junk = True

    body = signed_in(listing, "james").get(f"{INDEX}?scope=store").json()

    assert [album["id"] for album in body["albums"]] == ["al-0", "al-1", "al-2"]


def test_each_album_is_trimmed_to_what_the_library_reads_values_untouched(listing):
    listing.fake.starred("james").add("al-5")
    listing.fake.albums["al-6"].pop("year")
    listing.fake.albums["al-6"]["playCount"] = 4
    listing.fake.albums["al-6"]["played"] = "2026-10-01T10:00:00Z"

    albums = {album["id"]: album for album in signed_in(listing, "james").get(f"{INDEX}?scope=store").json()["albums"]}

    assert set(albums["al-5"]) == {"id", "name", "artist", "artistId", "coverArt", "year", "genre", "created", "starred",
                                   "musicBrainzId", "songCount", "duration"}
    assert all(set(album) <= set(navidrome_routes.INDEX_FIELDS) for album in albums.values())
    assert "year" not in albums["al-6"] and (albums["al-6"]["playCount"], albums["al-6"]["played"]) == (4, "2026-10-01T10:00:00Z")
    sent = listing.fake.albums["al-5"]
    assert {name: albums["al-5"][name] for name in ("name", "year", "created", "musicBrainzId")} == {
        name: sent[name] for name in ("name", "year", "created", "musicBrainzId")}


# ---------------------------------------------------------------- never a partial list

def test_a_page_that_fails_fails_the_whole_answer_in_navidromes_words(listing):
    listing.fake.fail_at = 500

    answer = signed_in(listing, "james").get(f"{INDEX}?scope=store")

    assert answer.status_code == 502 and "database is locked" in answer.json()["detail"]
    assert "albums" not in answer.json()


def test_a_navidrome_that_cant_be_reached_answers_as_every_route_does(listing):
    james = signed_in(listing, "james")
    james.get("/deadwax/navidrome/status")
    real = listing.fake.handle

    def down(request):
        raise httpx.ConnectError("connection refused")

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(down), base_url=f"{NAVIDROME}/rest")
    answer = james.get(f"{INDEX}?scope=store")
    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(real), base_url=f"{NAVIDROME}/rest")

    assert answer.status_code == 502 and "couldn't be reached" in answer.json()["detail"]


# ---------------------------------------------------------------- the ETag

def test_the_answer_carries_an_etag_and_an_unchanged_list_is_a_304(listing):
    james = signed_in(listing, "james")

    first = james.get(f"{INDEX}?scope=store")
    again = james.get(f"{INDEX}?scope=store")
    held = james.get(f"{INDEX}?scope=store", headers={"If-None-Match": first.headers["etag"]})

    assert first.headers["cache-control"] == "no-cache" and first.headers["etag"].startswith('"')
    assert again.headers["etag"] == first.headers["etag"]
    assert held.status_code == 304 and held.content == b"" and held.headers["etag"] == first.headers["etag"]
    assert held.headers["cache-control"] == "no-cache"


def test_a_change_in_the_list_is_a_new_etag_and_a_200(listing, monkeypatch):
    #? a star made somewhere else (another Subsonic app): seen once the kept list has had its time (2.1.49)
    monkeypatch.setattr(index_keep, "INDEX_KEEP_S", 0)
    james = signed_in(listing, "james")
    first = james.get(f"{INDEX}?scope=yours")
    listing.fake.starred("james").add("al-9")

    after = james.get(f"{INDEX}?scope=yours", headers={"If-None-Match": first.headers["etag"]})

    assert after.status_code == 200 and after.headers["etag"] != first.headers["etag"]
    assert [album["id"] for album in after.json()["albums"]] == ["al-9"]


# ---------------------------------------------------------------- who is asked

def test_with_logins_off_the_shared_account_is_asked(listing, monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")

    answer = TestClient(listing.app).get(f"{INDEX}?scope=store")

    assert answer.status_code == 200 and len(answer.json()["albums"]) == 1200
    assert {user for user, _ in listing.fake.asked()} == {"demo"}


def test_the_break_glass_admin_asks_as_the_shared_account(listing):
    answer = signed_in(listing, auth.BREAK_GLASS_USER).get(f"{INDEX}?scope=store")

    assert answer.status_code == 200
    assert {user for user, _ in listing.fake.asked()} == {"demo"}


def test_a_refused_login_is_the_401_that_ends_the_session(listing):
    ethan = signed_in(listing, "ethan")
    listing.fake.passwords["ethan"] = "changed"

    answer = ethan.get(f"{INDEX}?scope=yours")

    assert answer.status_code == 401 and answer.json()["detail"] == auth.LOGIN_GONE


def test_with_logins_on_the_list_needs_a_session(listing):
    assert TestClient(listing.app).get(f"{INDEX}?scope=store").status_code == 401
    assert listing.fake.asked() == []


# ---------------------------------------------------------------- pages asked for together (2.1.49)

def test_the_pages_after_the_first_are_asked_for_together_and_read_in_order(listing):
    """Four at a time at most - and the list is Navidrome's, in its order, whatever order the answers came in."""
    import asyncio
    fake = listing.fake
    fake.__init__(3300)
    out = {"now": 0, "most": 0, "alone": []}

    async def slowly(request: httpx.Request) -> httpx.Response:
        if not request.url.path.endswith("getAlbumList2"):
            return fake.handle(request)
        out["now"] += 1
        out["most"] = max(out["most"], out["now"])
        offset = int(parse_qs(urlparse(str(request.url)).query)["offset"][0])
        out["alone"].append((offset, out["now"]))
        #? later pages answer first
        await asyncio.sleep(0.03 - offset / 200000)
        out["now"] -= 1
        return fake.handle(request)

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(slowly), base_url=f"{NAVIDROME}/rest")
    body = signed_in(listing, "james").get(f"{INDEX}?scope=store").json()

    assert [album["id"] for album in body["albums"]] == [f"al-{n}" for n in range(3300)]
    assert out["most"] == navidrome_routes.PAGES_AT_ONCE == 4
    assert out["alone"][0] == (0, 1), "the first page alone: most libraries end in it"
    assert sorted(offset for offset, _ in out["alone"]) == list(range(0, 4500, 500))


def test_a_library_that_ends_in_its_first_page_is_one_call(listing):
    listing.fake.__init__(499)

    body = signed_in(listing, "james").get(f"{INDEX}?scope=store").json()

    assert len(body["albums"]) == 499
    assert [q["offset"] for _, q in listing.fake.asked()] == ["0"]


def test_a_page_past_the_lists_end_failing_is_nothing(listing):
    listing.fake.fail_at = 1500

    answer = signed_in(listing, "james").get(f"{INDEX}?scope=store")

    assert answer.status_code == 200 and len(answer.json()["albums"]) == 1200


# ---------------------------------------------------------------- the list kept for a moment (2.1.49)

def test_a_list_just_read_answers_the_next_ask_without_navidrome(listing):
    james = signed_in(listing, "james")
    first = james.get(f"{INDEX}?scope=store")
    listing.fake.calls.clear()

    again = james.get(f"{INDEX}?scope=store")
    held = james.get(f"{INDEX}?scope=store", headers={"If-None-Match": first.headers["etag"]})
    other_device = signed_in(listing, "james").get(f"{INDEX}?scope=store")

    assert listing.fake.asked() == []
    assert again.content == first.content and again.headers["etag"] == first.headers["etag"]
    assert held.status_code == 304
    assert other_device.content == first.content


def test_one_persons_kept_list_is_never_anothers(listing):
    listing.fake.starred("james").update({"al-1", "al-2"})
    listing.fake.starred("ethan").add("al-3")
    james, ethan = signed_in(listing, "james"), signed_in(listing, "ethan")

    assert [album["id"] for album in james.get(f"{INDEX}?scope=yours").json()["albums"]] == ["al-1", "al-2"]
    listing.fake.calls.clear()
    theirs = ethan.get(f"{INDEX}?scope=yours").json()["albums"]

    assert [album["id"] for album in theirs] == ["al-3"]
    assert [(user, q["type"]) for user, q in listing.fake.asked()] == [("ethan", "starred")], "asked as him, not answered from james's"
    #? nor is the store's: each has their own stars on it
    james_store = {album["id"] for album in james.get(f"{INDEX}?scope=store").json()["albums"] if album.get("starred")}
    ethan_store = {album["id"] for album in ethan.get(f"{INDEX}?scope=store").json()["albums"] if album.get("starred")}
    assert (james_store, ethan_store) == ({"al-1", "al-2"}, {"al-3"})


def test_a_scope_is_kept_apart_from_the_other(listing):
    listing.fake.starred("james").add("al-7")
    james = signed_in(listing, "james")

    assert len(james.get(f"{INDEX}?scope=store").json()["albums"]) == 1200
    assert [album["id"] for album in james.get(f"{INDEX}?scope=yours").json()["albums"]] == ["al-7"]
    assert len(james.get(f"{INDEX}?scope=store").json()["albums"]) == 1200


def test_the_break_glass_admin_and_a_signed_in_user_never_share_a_kept_list(listing):
    listing.fake.starred("demo").add("al-4")
    listing.fake.starred("james").add("al-5")
    glass, james = signed_in(listing, auth.BREAK_GLASS_USER), signed_in(listing, "james")

    assert [album["id"] for album in glass.get(f"{INDEX}?scope=yours").json()["albums"]] == ["al-4"]
    assert [album["id"] for album in james.get(f"{INDEX}?scope=yours").json()["albums"]] == ["al-5"]
    assert [album["id"] for album in glass.get(f"{INDEX}?scope=yours").json()["albums"]] == ["al-4"]


def test_with_logins_off_there_is_one_asker_and_their_list_is_not_a_signed_in_users(listing, monkeypatch):
    listing.fake.starred("demo").add("al-4")
    james = signed_in(listing, "james")
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    anyone = TestClient(listing.app)

    assert [album["id"] for album in anyone.get(f"{INDEX}?scope=yours").json()["albums"]] == ["al-4"]
    listing.fake.calls.clear()
    assert [album["id"] for album in TestClient(listing.app).get(f"{INDEX}?scope=yours").json()["albums"]] == ["al-4"]
    assert listing.fake.asked() == [], "the one implicit user's list, kept"

    monkeypatch.setattr(Config, "AUTH_MODE", "navidrome")
    assert james.get(f"{INDEX}?scope=yours").json()["albums"] == []
    assert [user for user, _ in listing.fake.asked()] == ["james"]


def test_a_refused_login_is_never_answered_from_a_kept_list_once_its_session_has_ended(listing):
    ethan = signed_in(listing, "ethan")
    assert ethan.get(f"{INDEX}?scope=store").status_code == 200
    listing.fake.passwords["ethan"] = "changed"
    #? any call of his that reaches Navidrome ends the session...
    assert ethan.get(f"{INDEX}?scope=yours").status_code == 401

    #? ...and then the list kept a moment ago is no longer his to be answered from
    assert ethan.get(f"{INDEX}?scope=store").status_code == 401


def test_a_failed_reading_keeps_nothing(listing):
    james = signed_in(listing, "james")
    listing.fake.fail_at = 500
    assert james.get(f"{INDEX}?scope=store").status_code == 502
    listing.fake.fail_at = None

    assert len(james.get(f"{INDEX}?scope=store").json()["albums"]) == 1200


def test_a_change_deadwax_makes_to_the_library_is_never_answered_from_before_it(listing, monkeypatch):
    """A download filed, a retag, a delete: Navidrome will scan in its own time, so until it has had that
    time every ask reads it afresh - a new album shows as soon as Navidrome has it, as before 2.1.49."""
    clock = {"now": 1000.0}
    monkeypatch.setattr(index_keep.time, "monotonic", lambda: clock["now"])
    james = signed_in(listing, "james")
    james.get(f"{INDEX}?scope=store")

    library.note_library_changed()  # the poller, as it files
    listing.fake.albums = {"al-new": {"id": "al-new", "name": "Just filed"}, **listing.fake.albums}
    assert james.get(f"{INDEX}?scope=store").json()["albums"][0]["id"] == "al-new"

    #? and nothing is kept while Navidrome may still be scanning: the next album in is seen too
    clock["now"] += index_keep.INDEX_SETTLE_S - 1
    listing.fake.albums = {"al-newer": {"id": "al-newer", "name": "Filed after"}, **listing.fake.albums}
    assert james.get(f"{INDEX}?scope=store").json()["albums"][0]["id"] == "al-newer"

    #? settled: kept again
    clock["now"] += 2
    james.get(f"{INDEX}?scope=store")
    listing.fake.calls.clear()
    james.get(f"{INDEX}?scope=store")
    assert listing.fake.asked() == []


player = test_player_as_you.player


def test_add_and_remove_show_in_your_library_at_once(player):
    """A star made through deadwax drops what was kept: Add's album is in the list asked next, Remove's is not."""
    test_personal_libraries.held(player)
    ethan = signed_in(player, "ethan")
    assert ethan.get(f"{INDEX}?scope=yours").json()["albums"] == []

    assert ethan.post(f"{test_personal_libraries.LIBRARY}/add", json=test_personal_libraries.release_body()).json()["starred"] is True
    assert [album["id"] for album in ethan.get(f"{INDEX}?scope=yours").json()["albums"]] == ["nd-dummy"]

    assert ethan.post(f"{test_personal_libraries.LIBRARY}/remove", json={"navidrome_id": "nd-dummy"}).status_code == 200
    assert ethan.get(f"{INDEX}?scope=yours").json()["albums"] == []


def test_an_album_the_worker_stars_for_you_shows_at_once(player):
    album = test_personal_libraries.held(player)
    ethan = signed_in(player, "ethan")
    assert ethan.get(f"{INDEX}?scope=yours").json()["albums"] == []

    test_personal_libraries.grant(player, ["ethan"], album)
    test_personal_libraries.work(player)

    assert [album["id"] for album in ethan.get(f"{INDEX}?scope=yours").json()["albums"]] == ["nd-dummy"]


def test_a_star_made_in_another_app_shows_as_soon_as_deadwax_has_read_it_back(player):
    """The app asks for your list again as it sees your library move - and must not be handed the list
    kept from before the star."""
    test_personal_libraries.held(player)
    ethan = signed_in(player, "ethan")
    assert ethan.get(f"{INDEX}?scope=yours").json()["albums"] == []

    player.fake.starred("ethan").add("nd-dummy")  # in Amperfy
    test_personal_libraries.work(player)  # the worker's read-back

    assert [album["id"] for album in ethan.get(f"{INDEX}?scope=yours").json()["albums"]] == ["nd-dummy"]


# ---------------------------------------------------------------- a play counted, after review (2.1.53)

def test_a_play_counted_through_deadwax_drops_that_listeners_kept_lists_and_nobody_elses(listing):
    """The list carries each album's `played` and `playCount`, which Recently played and Most played sort by: a
    play counted through deadwax is deadwax's own doing, and must not be answered from before it. Only a counted
    play - never the now-playing call that goes with every song - and only the listener's own lists."""
    scrobble = f"/deadwax/navidrome/scrobble/{test_player_as_you.SONG}"
    james, ethan = signed_in(listing, "james"), signed_in(listing, "ethan")
    for client in (james, ethan):
        for scope in ("store", "yours"):
            assert client.get(f"{INDEX}?scope={scope}").status_code == 200
    listing.fake.calls.clear()

    assert james.post(scrobble).status_code == 200
    james.get(f"{INDEX}?scope=store")
    assert listing.fake.asked() == [], "now playing: nothing dropped"

    listing.fake.albums["al-0"]["playCount"] = 1
    assert james.post(f"{scrobble}?submission=true").status_code == 200
    albums = james.get(f"{INDEX}?scope=store").json()["albums"]
    james.get(f"{INDEX}?scope=yours")
    assert albums[0]["playCount"] == 1, "the play counted is in the list asked next"
    assert {(user, q["type"]) for user, q in listing.fake.asked()} == {("james", "newest"), ("james", "starred")}, "both of his lists read afresh"

    listing.fake.calls.clear()
    ethan.get(f"{INDEX}?scope=store")
    ethan.get(f"{INDEX}?scope=yours")
    assert listing.fake.asked() == [], "nobody else's dropped"
