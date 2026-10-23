"""
The Library's Shuffle (2.0.0-player.57, Part B of Up Next, shuffle and repeat) - routes/navidrome.py's `/shuffle` and
`/shuffle/{token}`: every song of the asker's library (`yours`: the songs of the albums they starred) or of the store,
each once, in a random order deadwax makes, paged to the app as it plays.

Through the whole app start() builds (no lifespan) with logins on - step 6's fixtures (test_player_as_you.py) - and a
fake Navidrome shaped from 0.64.2's source: search3's EMPTY query answers every song in its natural order (by rowid,
persistence/sql_search.go), paged by songOffset with songCount uncapped; getAlbumList2 `starred` answers the asker's
own starred albums, `size` and `offset` honoured; token auth checked for real, every call kept with who made it.

What these hold:

  - EVERY SONG ONCE, IN AN ORDER: the pages of an order are a permutation of the scope's songs; two orders, two
    permutations. The list read a SCAN_PAGE at a time until a short page, a song a scan moved between pages read once.
  - WHOSE: `yours` is the asker's starred albums' songs, asked as them; with logins off, or for the break-glass admin
    (no library), it is the store's - the library then.
  - KEPT: the scope's songs reused within SHUFFLE_LIST_TTL_S and built again after; an order per user (another's is a
    404 "gone", as is one deadwax no longer holds), one never handed to the player per user and scope - a new one of
    that scope replacing it - and the two claimed most recently (paged; named as `playing` by the next tap's ask,
    before that replacing; or made with `claim`, the feed's), each kept SHUFFLE_ORDER_TTL_S after it was last asked
    for (sliding). One list build at a time per (user, scope).
  - BOUNDED: a scope outside the two, a token unlike one, an offset out of range - 422; a library past SHUFFLE_MAX -
    413 in words; nothing the page sends reaches Navidrome but the scope, which picks the calls; a Navidrome that
    can't be reached answers as every route does.
"""

import asyncio
import hashlib
from unittest import mock
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi.testclient import TestClient

from src import auth, player_cache
from src.api import navidrome_endpoint
from src.api.navidrome_endpoint import navidrome
from src.config import Config
from src.player_cache import Mp4Cache
from src.routes import navidrome as navidrome_routes
from tests.test_personal_libraries import NAVIDROME, failed, ok, run, signed_in, wire
from tests.test_player_as_you import Player
from tests import test_personal_libraries

#? step 5's fixture - its app, store and Navidrome - which `shuffling` builds on
on = test_personal_libraries.on

SHUFFLE = "/deadwax/navidrome/shuffle"


class Shuffler(Player):
    """
    Step 6's Navidrome with a library to shuffle: `count` songs over albums of ten, in their natural order - search3's
    empty query pages them (songOffset, songCount), and getAlbumList2 `starred` pages each user's own stars (size,
    offset). `moves`: a song read again at the start of the next page, as a scan between two pages can move a rowid.
    """

    def __init__(self, count: int = 450):
        super().__init__()
        self.library = [{"id": f"so-{n}", "title": f"Song {n}", "artist": "Portishead", "album": f"Album {n // 10}",
                         "albumId": f"al-{n // 10}", "coverArt": f"al-{n // 10}", "duration": 200, "contentType": "audio/flac",
                         "suffix": "flac", "samplingRate": 44100, "bitDepth": 16, "channelCount": 2, "track": n % 10 + 1,
                         "discNumber": 1, "path": f"/music/{n}.flac", "genres": [{"name": "Trip hop"}]}
                        for n in range(count)]
        for album in {song["albumId"] for song in self.library}:
            self.albums[album] = {"id": album, "name": album, "artist": "Portishead", "musicBrainzId": ""}
        self.moves = False

    def handle(self, request: httpx.Request) -> httpx.Response:
        endpoint = request.url.path.removeprefix("/rest/")
        q = {key: values[0] for key, values in parse_qs(urlparse(str(request.url)).query, keep_blank_values=True).items()}
        if endpoint not in ("search3", "getAlbumList2") or (endpoint == "search3" and q.get("query") != ""):
            return super().handle(request)
        user = q.get("u", "").lower()
        self.calls.append((user, endpoint, q))
        if self.down:
            raise httpx.ConnectError("connection refused")
        token = hashlib.md5((self.passwords.get(user, "") + q.get("s", "")).encode()).hexdigest()
        if user not in self.passwords or q.get("t") != token:
            return httpx.Response(200, json=failed(40, "Wrong username or password"))
        if (user, endpoint) in self.errors:
            return self.errors[(user, endpoint)]
        if endpoint == "search3":
            offset, count = int(q.get("songOffset", 0)), int(q.get("songCount", 20))
            page = self.library[offset:offset + count]
            if self.moves and offset and page:
                page = [self.library[offset - 1], *page[:-1]]
            return httpx.Response(200, json=ok(searchResult3={"artist": [], "album": [], "song": page}))
        offset, size = int(q.get("offset", 0)), int(q.get("size", 10))
        stars = self.starred(user)
        listed = [album for album in self.albums.values() if q.get("type") != "starred" or album["id"] in stars]
        return httpx.Response(200, json=ok(albumList2={"album": listed[offset:offset + size]}))

    def asked(self, endpoint: str) -> list[tuple[str, dict]]:
        return [(user, q) for user, called, q in self.calls if called == endpoint]


@pytest.fixture
def shuffling(on, monkeypatch, tmp_path):
    """Step 5's `on` with the Shuffler as its Navidrome - the shared client wired to it - and nothing kept of before."""
    fake = Shuffler()
    wire(fake)
    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(fake.handle), base_url=f"{NAVIDROME}/rest")
    monkeypatch.setattr(player_cache, "cache", Mp4Cache(tmp_path / "deadwax-player"))
    navidrome_routes.forget_access()
    navidrome_routes.forget_shuffles()
    navidrome_endpoint.forget_confirmed()
    on.fake = fake
    yield on
    navidrome_routes.forget_shuffles()
    navidrome_routes.forget_access()
    navidrome_endpoint.forget_confirmed()
    run(navidrome.close_client())


def whole(client: TestClient, scope: str = "store") -> tuple[str, list[str], int]:
    """A new order of `scope`, every page of it: its token, the song ids in order, and the total it said."""
    first = client.get(f"{SHUFFLE}?scope={scope}")
    assert first.status_code == 200, first.text
    answer = first.json()
    ids = [song["id"] for song in answer["songs"]]
    while len(ids) < answer["total"]:
        page = client.get(f"{SHUFFLE}/{answer['token']}?offset={len(ids)}")
        assert page.status_code == 200, page.text
        assert page.json()["total"] == answer["total"]
        more = [song["id"] for song in page.json()["songs"]]
        assert more, "a page with nothing in it before the end"
        ids += more
    return answer["token"], ids, answer["total"]


# ---------------------------------------------------------------- every song once, in an order

def test_every_song_of_the_store_once_in_a_random_order(shuffling):
    james = signed_in(shuffling, "james")

    token, ids, total = whole(james)
    _, again, _ = whole(james)

    every = [song["id"] for song in shuffling.fake.library]
    assert total == 450 and sorted(ids) == sorted(every) and len(set(ids)) == 450
    assert ids != every  # an order, not Navidrome's own
    assert sorted(again) == sorted(every) and again != ids  # two orders, two permutations
    #? the first page and every later one SHUFFLE_PAGE songs, the last what is left
    first = james.get(f"{SHUFFLE}?scope=store").json()
    assert len(first["songs"]) == navidrome_routes.SHUFFLE_PAGE
    assert len(james.get(f"{SHUFFLE}/{first['token']}?offset=400").json()["songs"]) == 50


def test_each_song_is_what_the_queue_needs_in_navidromes_own_names(shuffling):
    song = signed_in(shuffling, "james").get(f"{SHUFFLE}?scope=store").json()["songs"][0]

    assert set(song) == set(navidrome_routes.SHUFFLE_FIELDS)
    assert "path" not in song and "genres" not in song


def test_the_list_is_read_a_page_at_a_time_until_a_short_page(shuffling, monkeypatch):
    monkeypatch.setattr(navidrome_routes, "SCAN_PAGE", 100)

    total = signed_in(shuffling, "james").get(f"{SHUFFLE}?scope=store").json()["total"]

    scans = [q for _, q in shuffling.fake.asked("search3")]
    assert total == 450
    assert [(q["query"], q["songCount"], q["songOffset"], q["artistCount"], q["albumCount"]) for q in scans] == [
        ("", "100", str(offset), "0", "0") for offset in (0, 100, 200, 300, 400)
    ]


def test_a_song_a_scan_moved_between_pages_is_read_once(shuffling, monkeypatch):
    monkeypatch.setattr(navidrome_routes, "SCAN_PAGE", 100)
    shuffling.fake.moves = True

    _, ids, total = whole(signed_in(shuffling, "james"))

    assert len(ids) == len(set(ids)) == total


def test_a_navidrome_that_ignores_the_offset_ends_the_read(shuffling, monkeypatch):
    """A full page bringing nothing new is the end, not a loop for ever."""
    monkeypatch.setattr(navidrome_routes, "SCAN_PAGE", 100)
    real = shuffling.fake.handle

    def same_page(request):
        url = str(request.url)
        if "search3" in url:
            url = url.replace(f"songOffset={parse_qs(urlparse(url).query)['songOffset'][0]}", "songOffset=0")
            request = httpx.Request(request.method, url)
        return real(request)

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(same_page), base_url=f"{NAVIDROME}/rest")
    answer = signed_in(shuffling, "james").get(f"{SHUFFLE}?scope=store")

    assert answer.status_code == 200 and answer.json()["total"] == 100
    assert len(shuffling.fake.asked("search3")) == 2


# ---------------------------------------------------------------- whose

def test_yours_is_the_songs_of_the_albums_you_starred_asked_as_you(shuffling):
    shuffling.fake.starred("ethan").update({"al-3", "al-7"})
    shuffling.fake.starred("james").add("al-1")

    _, ids, total = whole(signed_in(shuffling, "ethan"), "yours")

    assert total == 20 and sorted(ids) == sorted(f"so-{n}" for n in [*range(30, 40), *range(70, 80)])
    assert {user for user, _ in shuffling.fake.asked("getAlbumList2")} == {"ethan"}
    assert {user for user, _ in shuffling.fake.asked("search3")} == {"ethan"}
    assert [q["type"] for _, q in shuffling.fake.asked("getAlbumList2")] == ["starred"]


def test_your_starred_albums_are_read_a_page_at_a_time(shuffling, monkeypatch):
    monkeypatch.setattr(navidrome_routes, "STARRED_PAGE", 2)
    shuffling.fake.starred("ethan").update({"al-0", "al-1", "al-2", "al-3", "al-4"})

    total = signed_in(shuffling, "ethan").get(f"{SHUFFLE}?scope=yours").json()["total"]

    assert total == 50
    assert [(q["size"], q["offset"]) for _, q in shuffling.fake.asked("getAlbumList2")] == [("2", "0"), ("2", "2"), ("2", "4")]


def test_with_logins_off_yours_is_the_store_which_is_the_library(shuffling, monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")

    _, ids, total = whole(TestClient(shuffling.app), "yours")

    assert total == 450 and len(set(ids)) == 450
    assert shuffling.fake.asked("getAlbumList2") == []
    assert {user for user, _ in shuffling.fake.asked("search3")} == {"demo"}


def test_the_break_glass_admin_shuffles_the_store(shuffling):
    glass = signed_in(shuffling, auth.BREAK_GLASS_USER)

    assert glass.get(f"{SHUFFLE}?scope=yours").json()["total"] == 450
    assert shuffling.fake.asked("getAlbumList2") == []


# ---------------------------------------------------------------- kept

def test_the_scopes_songs_are_reused_for_a_while_then_read_again(shuffling, monkeypatch):
    james = signed_in(shuffling, "james")
    james.get(f"{SHUFFLE}?scope=store")
    james.get(f"{SHUFFLE}?scope=store")
    assert len(shuffling.fake.asked("search3")) == 1

    monkeypatch.setattr(navidrome_routes, "SHUFFLE_LIST_TTL_S", 0)
    shuffling.fake.library.append({**shuffling.fake.library[0], "id": "so-new"})
    answer = james.get(f"{SHUFFLE}?scope=store").json()
    assert len(shuffling.fake.asked("search3")) == 2
    assert answer["total"] == 451  # a song added since is in the next shuffle


# ---------------------------------------------------------------- memory (2.0.0-player.65, the 2.0.0 release review)

def test_orders_over_lists_built_again_hold_one_copy_of_each_song(shuffling, monkeypatch):
    """Each order held its own copy of the list it was made from, built again every ten minutes - about 20 MB a copy
    at 20,000 songs, ten orders a person, kept a day while idle. An order holds the songs' ids now - the very strings
    the one table keys them under - and a page answers the table's songs."""
    james = signed_in(shuffling, "james")
    first = james.get(f"{SHUFFLE}?scope=store").json()["token"]
    monkeypatch.setattr(navidrome_routes, "SHUFFLE_LIST_TTL_S", 0)
    second = james.get(f"{SHUFFLE}?scope=store").json()["token"]
    assert len(shuffling.fake.asked("search3")) == 2, "the list was read again"

    orders = [navidrome_routes._shuffle_orders[token] for token in (first, second)]
    table = navidrome_routes._shuffle_songs_by_id
    assert len(table) == 450
    for held in orders:
        assert len(held.ids) == 450 and all(type(song_id) is str for song_id in held.ids)
        assert all(song_id is table[song_id]["id"] for song_id in held.ids), "the table's own strings"
    page = navidrome_routes._shuffle_page(orders[0], 0)
    assert all(song is table[song["id"]] for song in page)


def test_a_song_changed_since_is_paged_as_navidrome_now_has_it(shuffling, monkeypatch):
    james = signed_in(shuffling, "james")
    token = james.get(f"{SHUFFLE}?scope=store").json()["token"]
    monkeypatch.setattr(navidrome_routes, "SHUFFLE_LIST_TTL_S", 0)
    shuffling.fake.library[0] = {**shuffling.fake.library[0], "title": "Retitled"}
    james.get(f"{SHUFFLE}?scope=store")

    songs = [song for offset in (0, 200, 400) for song in james.get(f"{SHUFFLE}/{token}?offset={offset}").json()["songs"]]
    assert len(songs) == 450 and {song["title"] for song in songs if song["id"] == "so-0"} == {"Retitled"}


def test_a_sweep_forgets_old_orders_and_lists_and_every_song_nothing_names(shuffling):
    james = signed_in(shuffling, "james")
    old = james.get(f"{SHUFFLE}?scope=store").json()["token"]
    navidrome_routes._shuffle_orders[old].used -= navidrome_routes.SHUFFLE_ORDER_TTL_S + 1
    now = navidrome_routes.time.monotonic()
    key = next(iter(navidrome_routes._shuffle_lists))

    #? the list is fresh: its songs stay, though the order went
    navidrome_routes._sweep_shuffles(now)
    assert old not in navidrome_routes._shuffle_orders and len(navidrome_routes._shuffle_songs_by_id) == 450

    built, ids = navidrome_routes._shuffle_lists[key]
    navidrome_routes._shuffle_lists[key] = (built - navidrome_routes.SHUFFLE_LIST_TTL_S, ids)
    navidrome_routes._sweep_shuffles(now)
    assert navidrome_routes._shuffle_lists == {} and navidrome_routes._shuffle_songs_by_id == {}


def test_a_live_order_keeps_its_songs_through_a_sweep(shuffling):
    james = signed_in(shuffling, "james")
    token = james.get(f"{SHUFFLE}?scope=store").json()["token"]
    navidrome_routes._shuffle_lists.clear()

    navidrome_routes._sweep_shuffles(navidrome_routes.time.monotonic())

    assert len(navidrome_routes._shuffle_songs_by_id) == 450
    assert len(james.get(f"{SHUFFLE}/{token}?offset=400").json()["songs"]) == 50


def test_a_sweep_between_two_pages_of_a_build_drops_none_of_its_songs(shuffling, monkeypatch):
    """The lifespan's sweep runs between any two awaits - so between two search3 pages of a build. It keeps only songs a
    list or order names, and a build's list is stored at its end: with the songs put in the table page by page, the ones
    read before the sweep were gone, and the order's pages came back short or empty while its total said all of them
    (the 2.0.0-player.65 review). The table takes a build's songs as its list is stored, with nothing awaited between."""
    monkeypatch.setattr(navidrome_routes, "SCAN_PAGE", 100)
    real = shuffling.fake.handle
    swept = []

    def sweeping(request):
        if "search3" in str(request.url) and parse_qs(urlparse(str(request.url)).query).get("songOffset") == ["200"]:
            navidrome_routes._sweep_shuffles(navidrome_routes.time.monotonic())
            swept.append(len(navidrome_routes._shuffle_songs_by_id))
        return real(request)

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(sweeping), base_url=f"{NAVIDROME}/rest")
    _, ids, total = whole(signed_in(shuffling, "james"))

    assert swept == [0], "the sweep ran mid-build, with nothing yet in the table"
    assert total == 450 and len(ids) == len(set(ids)) == 450
    assert len(navidrome_routes._shuffle_songs_by_id) == 450


def test_the_sweep_runs_on_a_timer_and_a_failure_never_stops_it(monkeypatch):
    calls = []

    def sweep(now):
        calls.append(now)
        if len(calls) == 1:
            raise RuntimeError("once")

    monkeypatch.setattr(navidrome_routes, "_sweep_shuffles", sweep)

    async def go():
        task = asyncio.create_task(navidrome_routes.run_shuffle_sweeps(every=0.01))
        await asyncio.sleep(0.1)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task

    asyncio.run(go())
    assert len(calls) >= 3


def test_each_users_list_is_their_own(shuffling):
    shuffling.fake.starred("ethan").add("al-3")
    shuffling.fake.starred("james").add("al-1")

    ethan = signed_in(shuffling, "ethan").get(f"{SHUFFLE}?scope=yours").json()
    james = signed_in(shuffling, "james").get(f"{SHUFFLE}?scope=yours").json()

    assert {song["albumId"] for song in ethan["songs"]} == {"al-3"} and {song["albumId"] for song in james["songs"]} == {"al-1"}


def test_another_users_token_and_one_deadwax_no_longer_holds_are_gone(shuffling):
    token = signed_in(shuffling, "james").get(f"{SHUFFLE}?scope=store").json()["token"]

    theirs = signed_in(shuffling, "ethan").get(f"{SHUFFLE}/{token}?offset=200")
    assert theirs.status_code == 404 and theirs.json() == {"detail": "gone"}

    navidrome_routes.forget_shuffles()  # as a restart forgets them
    assert signed_in(shuffling, "james").get(f"{SHUFFLE}/{token}?offset=200").status_code == 404


def test_the_orders_asked_ahead_most_recently_are_kept_and_the_oldest_goes_past_them(shuffling):
    james = signed_in(shuffling, "james")
    tokens = [james.get(f"{SHUFFLE}?scope=store").json()["token"]
              for _ in range(navidrome_routes.SHUFFLE_UNCLAIMED_KEPT + 1)]

    assert james.get(f"{SHUFFLE}/{tokens[0]}?offset=200").status_code == 404
    assert all(james.get(f"{SHUFFLE}/{token}?offset=200").status_code == 200 for token in tokens[1:])


def test_another_devices_visit_never_takes_the_order_this_devices_list_holds(shuffling):
    """The second review's case: one person (or everyone as `local`) on a desktop and a phone. The desktop's list
    asked its order ahead; the phone's list then asks its own; the desktop's tap plays the order it holds, and its
    next ask names it - it must still be there to claim, and its second page must come, not a 404 and a shuffle that
    "started over"."""
    james = signed_in(shuffling, "james")
    desktop = james.get(f"{SHUFFLE}?scope=store").json()["token"]
    james.get(f"{SHUFFLE}?scope=store")  # the phone's visit
    james.get(f"{SHUFFLE}?scope=store&playing={desktop}")  # the desktop's tap, and its ask for the next

    assert navidrome_routes._shuffle_orders[desktop].claimed is True
    assert james.get(f"{SHUFFLE}/{desktop}?offset=200").status_code == 200


def test_the_order_a_tap_played_is_claimed_by_the_next_taps_ask(shuffling):
    """The review's case: the list's Shuffle plays its first page and asks straight away for the next tap's order -
    long before the order playing is paged. Named as `playing`, it is claimed before the new one replaces it."""
    james = signed_in(shuffling, "james")
    played = james.get(f"{SHUFFLE}?scope=store").json()["token"]
    james.get(f"{SHUFFLE}?scope=store&playing={played}")
    for _ in range(navidrome_routes.SHUFFLE_UNCLAIMED_KEPT + 1):
        james.get(f"{SHUFFLE}?scope=store")

    assert james.get(f"{SHUFFLE}/{played}?offset=200").status_code == 200


def test_without_naming_it_the_order_played_went_which_is_the_bug_the_claim_mends(shuffling):
    james = signed_in(shuffling, "james")
    played = james.get(f"{SHUFFLE}?scope=store").json()["token"]
    for _ in range(navidrome_routes.SHUFFLE_UNCLAIMED_KEPT):
        james.get(f"{SHUFFLE}?scope=store")

    assert james.get(f"{SHUFFLE}/{played}?offset=200").status_code == 404


def test_another_users_token_named_as_playing_claims_nothing(shuffling):
    theirs = signed_in(shuffling, "ethan").get(f"{SHUFFLE}?scope=store").json()["token"]
    signed_in(shuffling, "james").get(f"{SHUFFLE}?scope=store&playing={theirs}")

    assert navidrome_routes._shuffle_orders[theirs].claimed is False


def test_an_order_made_to_play_at_once_is_claimed_as_it_is_made(shuffling):
    """The feed's fresh order (Repeat All's next round, or one after a restart) goes straight into the queue."""
    james = signed_in(shuffling, "james")
    fresh = james.get(f"{SHUFFLE}?scope=store&claim=true").json()["token"]
    for _ in range(navidrome_routes.SHUFFLE_UNCLAIMED_KEPT + 1):
        james.get(f"{SHUFFLE}?scope=store")

    assert navidrome_routes._shuffle_orders[fresh].claimed is True
    assert james.get(f"{SHUFFLE}/{fresh}?offset=200").status_code == 200


def test_an_ask_ahead_of_one_scope_never_pushes_out_the_other_scopes(shuffling):
    """Your albums' Shuffle and Browse's Songs' each ask one ahead: neither replaces the other's."""
    shuffling.fake.starred("james").add("al-1")
    james = signed_in(shuffling, "james")
    yours = james.get(f"{SHUFFLE}?scope=yours").json()["token"]
    james.get(f"{SHUFFLE}?scope=store")

    assert james.get(f"{SHUFFLE}/{yours}?offset=0").status_code == 200


def test_one_users_two_scopes_are_two_lists(shuffling):
    """The list is kept per (user, scope): your albums' songs, then everything, within SHUFFLE_LIST_TTL_S."""
    shuffling.fake.starred("james").update({"al-1", "al-2"})
    james = signed_in(shuffling, "james")

    yours = james.get(f"{SHUFFLE}?scope=yours").json()["total"]
    store = james.get(f"{SHUFFLE}?scope=store").json()["total"]
    again = james.get(f"{SHUFFLE}?scope=yours").json()["total"]

    assert (yours, store, again) == (20, 450, 20)
    assert len(shuffling.fake.asked("search3")) == 2


def test_two_shuffles_asked_at_once_read_the_list_once(shuffling):
    """One build at a time per (user, scope): the second waits for the first's list rather than scanning again."""
    gate = asyncio.Event()
    scans = []

    class Client:
        async def call(self, endpoint, params):
            scans.append(endpoint)
            await gate.wait()
            return {"searchResult3": {"song": shuffling.fake.library[:10]}}

    async def race():
        first = asyncio.create_task(navidrome_routes._shuffle_songs(None, "james", "store"))
        second = asyncio.create_task(navidrome_routes._shuffle_songs(None, "james", "store"))
        await asyncio.sleep(0)
        await asyncio.sleep(0)
        gate.set()
        return await first, await second

    with mock.patch.object(navidrome_routes, "client_for", lambda _request: Client()):
        one, two = asyncio.run(race())

    assert scans == ["search3"] and one is two and len(one) == 10


def test_opening_the_list_again_and_again_never_pushes_out_the_order_playing(shuffling):
    james = signed_in(shuffling, "james")
    playing = james.get(f"{SHUFFLE}?scope=store").json()["token"]
    assert james.get(f"{SHUFFLE}/{playing}?offset=200").status_code == 200
    for _ in range(5):
        james.get(f"{SHUFFLE}?scope=store")

    assert james.get(f"{SHUFFLE}/{playing}?offset=400").status_code == 200


def test_the_two_most_recently_paged_orders_are_kept_the_oldest_going_first(shuffling):
    james = signed_in(shuffling, "james")
    tokens = []
    for _ in range(navidrome_routes.SHUFFLE_CLAIMED_KEPT + 1):
        token = james.get(f"{SHUFFLE}?scope=store").json()["token"]
        assert james.get(f"{SHUFFLE}/{token}?offset=200").status_code == 200
        tokens.append(token)

    assert [james.get(f"{SHUFFLE}/{token}?offset=0").status_code for token in tokens] == [404, 200, 200]


def test_an_order_is_kept_a_day_after_it_was_last_asked_for(shuffling):
    james = signed_in(shuffling, "james")
    token = james.get(f"{SHUFFLE}?scope=store").json()["token"]
    held = navidrome_routes._shuffle_orders[token]

    held.used -= navidrome_routes.SHUFFLE_ORDER_TTL_S - 60
    assert james.get(f"{SHUFFLE}/{token}?offset=200").status_code == 200
    #? asked for just now: the day starts again from here
    held.used -= navidrome_routes.SHUFFLE_ORDER_TTL_S - 60
    assert james.get(f"{SHUFFLE}/{token}?offset=200").status_code == 200

    held.used -= navidrome_routes.SHUFFLE_ORDER_TTL_S + 1
    assert james.get(f"{SHUFFLE}/{token}?offset=200").status_code == 404


def test_a_page_asks_navidrome_nothing(shuffling):
    james = signed_in(shuffling, "james")
    token = james.get(f"{SHUFFLE}?scope=store").json()["token"]
    shuffling.fake.calls.clear()

    james.get(f"{SHUFFLE}/{token}?offset=200")

    assert shuffling.fake.calls == []


# ---------------------------------------------------------------- bounded

@pytest.mark.parametrize("path", [
    SHUFFLE,                                     # no scope
    f"{SHUFFLE}?scope=everything",               # a scope outside the two
    f"{SHUFFLE}?scope=store&playing=x%2Fy",      # a token named as playing unlike one
    f"{SHUFFLE}/x%2Fy?offset=0",                 # a token unlike one
    f"{SHUFFLE}/{'a' * 65}?offset=0",            # one past its bound
    f"{SHUFFLE}/abc",                            # no offset
    f"{SHUFFLE}/abc?offset=-1",
    f"{SHUFFLE}/abc?offset={navidrome_routes.SHUFFLE_MAX + 1}",
])
def test_what_is_out_of_bounds_is_refused_before_navidrome_is_asked(shuffling, path):
    client = signed_in(shuffling, "james")
    shuffling.fake.calls.clear()

    assert client.get(path).status_code in (404, 422)
    if "%2F" not in path:
        assert client.get(path).status_code == 422
    assert shuffling.fake.calls == []


def test_a_library_too_big_to_shuffle_says_so(shuffling, monkeypatch):
    monkeypatch.setattr(navidrome_routes, "SHUFFLE_MAX", 100)

    answer = signed_in(shuffling, "james").get(f"{SHUFFLE}?scope=store")

    assert answer.status_code == 413 and answer.json()["detail"] == navidrome_routes.SHUFFLE_TOO_BIG


def test_nothing_the_page_sends_reaches_navidrome_but_the_scope(shuffling):
    signed_in(shuffling, "ethan").get(f"{SHUFFLE}?scope=store&query=x&songCount=5&songOffset=9&u=james&musicFolderId=2&f=xml")

    [(user, q)] = shuffling.fake.asked("search3")
    assert user == "ethan"
    assert (q["query"], q["songCount"], q["songOffset"], q["f"]) == ("", str(navidrome_routes.SCAN_PAGE), "0", "json")
    assert "musicFolderId" not in q


def test_a_navidrome_that_cant_be_reached_answers_as_every_route_does(shuffling):
    james = signed_in(shuffling, "james")
    james.get("/deadwax/navidrome/status")
    shuffling.fake.down = True

    answer = james.get(f"{SHUFFLE}?scope=store")

    assert answer.status_code == 502 and "couldn't be reached" in answer.json()["detail"]


def test_with_logins_on_a_shuffle_needs_a_session(shuffling):
    assert TestClient(shuffling.app).get(f"{SHUFFLE}?scope=store").status_code == 401
