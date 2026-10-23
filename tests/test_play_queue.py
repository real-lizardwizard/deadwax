"""
Resume what was playing (2.0.0-player.64) - src/play_queue.py, routes/navidrome.py's /queue and /queue/at, and
store.py's play_queue - through the whole app start() builds (no lifespan), a real SQLite store, and the player's fake
Navidrome (tests/test_player_as_you.py's Player), whose play queue is shaped from Navidrome 0.64.2's own source:
server/subsonic/bookmarks.go and persistence/playqueue_repository.go - one queue per user, by index or by first id,
an empty save clearing it, songs it no longer has dropped on a read with the stored index answered unchanged, the
`c` of the saving call as changedBy, the empty answer's exact shape.

What these hold:

  - A save then a read as ethan: Navidrome holds his ids in order (a song twice kept twice), the index, the position
    in ms and deadwax as changedBy - asked AS him, as a form - and `kept` carries his snapshot back byte for byte.
  - /queue/at moves the index and position against the ids of the full save it names; a stale `ids_rev`, or no
    record, is a 409 that writes nothing anywhere; an index past the ids a 422.
  - `kept` only when deadwax saved last: another app's savePlayQueue (by first id) leaves deadwax's record unread.
  - Songs gone from the library: answered without them, Navidrome's stored index as it answers it.
  - A Navidrome failure (a 502, error 40 ending the session, Navidrome unreachable) leaves the record as it was, and
    the next save carries on from it.
  - Every body bounded and declared: over 2,000 ids, none, a bad device or label, a snapshot that isn't JSON, isn't
    an object, isn't v 1, is over the cap - and an extra field (pydantic would drop it without a word) - each a 422
    in words, never FastAPI's echo of the input.
  - One save at a time per user (a full save and a position save never interleave their two writes); two users never
    wait on each other.
  - Privacy: james never reads ethan's queue or record; with logins off everything is `local`'s and the shared
    account's, `shared`; the break-glass admin asks Navidrome nothing and writes nothing; every read's and save's
    answer no-store (the break-glass admin's too).
  - A read waits for a save in flight - Navidrome slow, or the record - and never reads between its two writes.
  - The database failing: a read still answers Navidrome's queue (no `kept`), a save is a 503 in words.
  - Another app's name cleaned before the notice shows it; a 401 is never logged as Navidrome not keeping it.
  - A foreign list over 2,000 answered as the window around its current song.
  - forget_person clears it, adopt_local leaves it, and an existing database gains the table.
  - The same-origin guard lets the page's own JSON POST (a beacon's Origin) through and refuses another site's.
"""

import asyncio
import json
import sqlite3
import time

import httpx
import pytest
from fastapi.testclient import TestClient

from src import auth, play_queue as rules
from src.api import navidrome_endpoint
from src.api.navidrome_endpoint import navidrome
from src.config import Config
from src.routes import navidrome as navidrome_routes
from src.store import JobStore
from src.users import LOCAL_USER
from tests import test_personal_libraries, test_player_as_you
from tests.test_personal_libraries import NAVIDROME, failed, signed_in

on = test_personal_libraries.on
player = test_player_as_you.player

QUEUE = "/deadwax/navidrome/queue"
AT = "/deadwax/navidrome/queue/at"
DEVICE = "phone-device-01"
SNAPSHOT = json.dumps({"v": 1, "levels": "aa", "marks": [[0, "s", 0, 0], [1, "s", 1, 0]], "note": "kept as sent"},
                      separators=(",", ":"))


@pytest.fixture(autouse=True)
def fresh_locks():
    navidrome_routes.forget_queue_locks()
    yield
    navidrome_routes.forget_queue_locks()


def songs(env, count: int, prefix: str = "q") -> list[str]:
    """`count` songs Navidrome has, ids prefix-1 ... prefix-count."""
    made = []
    for n in range(1, count + 1):
        song_id = f"{prefix}-{n}"
        env.fake.songs[song_id] = {"id": song_id, "title": f"Song {n}", "albumId": "nd-dummy", "album": "Dummy",
                                   "artist": "Portishead", "coverArt": "al-1", "duration": 200,
                                   "contentType": "audio/flac", "suffix": "flac", "samplingRate": 44100,
                                   "bitDepth": 16, "channelCount": 2, "track": n, "discNumber": 1,
                                   "path": f"Portishead/Dummy/{n:02d}.flac", "playCount": 3}
        made.append(song_id)
    return made


def body(ids, index=0, position=12.5, snapshot=SNAPSHOT, device=DEVICE, label="iPhone", **more) -> dict:
    return {"ids": ids, "index": index, "position": position, "device": device, "label": label, "snapshot": snapshot, **more}


def at_body(ids_rev, index, position=30.0, device=DEVICE, label="iPhone") -> dict:
    return {"ids_rev": ids_rev, "index": index, "position": position, "device": device, "label": label}


def another_app(env, user: str, ids: list[str], current: str, position_ms: int = 4000, client: str = "Symfonium"):
    """Another Subsonic app saving the user's queue the plain way - savePlayQueue, `current` an id."""
    return env.fake.play_queue_call("savePlayQueue", user, {"id": ids, "current": [current],
                                                             "position": [str(position_ms)], "c": [client]})


# ----------------------------------------------------------------- the pure half

def test_the_window_is_fifty_before_and_two_thousand_in_all():
    assert rules.window(10, 3) == (0, 10)
    assert rules.window(5000, 0) == (0, 2000)
    assert rules.window(5000, 100) == (50, 2050)
    assert rules.window(2500, 2200) == (2150, 2500)
    #? an index Navidrome answered past the end (songs dropped since) is clamped for the window
    assert rules.window(3000, 9999) == (2949, 3000)
    assert rules.window(0, 0) == (0, 0)


def test_a_client_name_is_cleaned_for_the_notice():
    assert rules.cleaned_name("Symfonium") == "Symfonium"
    assert rules.cleaned_name("Sym\x00fon\x1bium\n") == "Symfonium"
    assert rules.cleaned_name("x" * 100) == "x" * 64
    assert rules.cleaned_name(None) == "" and rules.cleaned_name(7) == ""


def test_a_save_sends_ids_the_index_and_milliseconds_only():
    assert rules.save_params(["a", "b", "a"], 2, 95.4996) == {"id": ["a", "b", "a"], "currentIndex": 2, "position": 95500}


@pytest.mark.parametrize("text, problem", [
    (None, None), ('{"v":1}', None), ("{not json", "isn't JSON"), ("[1]", "isn't an object"), ('{"v":2}', "v 1"),
    ('{"v":true}', "v 1"), ('{"x":1}', "v 1"), ('{"v":1,"pad":"' + "x" * rules.SNAPSHOT_MAX + '"}', "over"),
])
def test_a_snapshot_is_checked_to_be_one_and_nothing_more(text, problem):
    found = rules.snapshot_problem(text)
    assert (found is None) if problem is None else (problem in found), found


# ----------------------------------------------------------------- a save, and reading it back

def test_a_save_then_a_read_round_trips_as_ethan_by_index_as_a_form(player):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 3)
    queue = [ids[0], ids[1], ids[0], ids[2]]
    saved = ethan.post(QUEUE, json=body(queue, index=2, position=95.25))
    assert saved.status_code == 200, saved.text
    assert saved.json() == {"rev": 1, "ids_rev": 1}
    assert saved.headers["cache-control"] == "no-store"
    [call] = [c for c in player.fake.queue_calls if c["endpoint"] == "savePlayQueueByIndex"]
    assert call["user"] == "ethan" and call["form"] and call["query"] == ""
    assert call["values"]["id"] == queue and call["values"]["currentIndex"] == ["2"] and call["values"]["position"] == ["95250"]
    assert player.fake.queues["ethan"] == {"ids": queue, "current": 2, "position": 95250, "changedBy": "deadwax",
                                           "changed": player.fake.queues["ethan"]["changed"]}

    read = ethan.get(QUEUE)
    assert read.status_code == 200 and read.headers["cache-control"] == "no-store"
    answer = read.json()
    assert [t["id"] for t in answer["tracks"]] == queue
    assert answer["index"] == 2 and answer["position"] == 95.25 and answer["changed_by"] == "deadwax"
    assert answer["shared"] is False
    assert answer["kept"] == {"rev": 1, "ids_rev": 1, "ids": queue, "index": 2, "position": 95.25, "snapshot": SNAPSHOT,
                              "device": DEVICE, "label": "iPhone"}
    #? the songs as the shuffle answers them - the page's shuffledTrack reads exactly these, nothing more
    assert set(answer["tracks"][0]) == set(navidrome_routes.SHUFFLE_FIELDS)
    assert [c["user"] for c in player.fake.queue_calls] == ["ethan", "ethan"]


def test_a_position_save_moves_the_song_and_second_against_the_full_saves_ids(player):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 4)
    assert ethan.post(QUEUE, json=body(ids, index=0)).json() == {"rev": 1, "ids_rev": 1}
    moved = ethan.post(AT, json=at_body(1, 2, position=61.5, label="Mac", device="desk-device-2"))
    assert moved.status_code == 200 and moved.json() == {"rev": 2, "ids_rev": 1}
    assert moved.headers["cache-control"] == "no-store"
    assert player.fake.queues["ethan"]["ids"] == ids and player.fake.queues["ethan"]["current"] == 2
    assert player.fake.queues["ethan"]["position"] == 61500
    kept = player.store.play_queue("ethan")
    assert (kept["ids"], kept["index"], kept["position"], kept["snapshot"], kept["device"], kept["label"]) == (
        ids, 2, 61.5, SNAPSHOT, "desk-device-2", "Mac")
    assert ethan.get(QUEUE).json()["kept"]["rev"] == 2


def test_a_stale_ids_rev_or_no_record_is_a_409_that_writes_nothing(player):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 4)
    #? no record yet
    nothing = ethan.post(AT, json=at_body(1, 0))
    assert nothing.status_code == 409 and nothing.json()["detail"] == rules.QUEUE_CHANGED
    assert player.fake.queues == {} and player.store.play_queue("ethan") is None
    ethan.post(QUEUE, json=body(ids[:2]))
    #? another device saved new ids since
    ethan.post(QUEUE, json=body(ids[2:], device="desk-device-2"))
    before_navidrome, before_record = dict(player.fake.queues["ethan"]), player.store.play_queue("ethan")
    stale = ethan.post(AT, json=at_body(1, 1))
    assert stale.status_code == 409 and stale.json()["detail"] == rules.QUEUE_CHANGED
    assert player.fake.queues["ethan"] == before_navidrome and player.store.play_queue("ethan") == before_record
    #? an index past the ids kept
    past = ethan.post(AT, json=at_body(2, 2))
    assert past.status_code == 422 and past.json()["detail"] == rules.NOT_IN_QUEUE
    assert player.fake.queues["ethan"] == before_navidrome


def test_kept_is_left_out_when_another_app_saved_last(player):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 3)
    ethan.post(QUEUE, json=body(ids))
    another_app(player, "ethan", [ids[2], ids[1], ids[2]], current=ids[2])
    answer = ethan.get(QUEUE).json()
    #? Navidrome found `current` by its FIRST copy - index 0 - and the record, still there, isn't handed out
    assert [t["id"] for t in answer["tracks"]] == [ids[2], ids[1], ids[2]]
    assert (answer["index"], answer["position"], answer["changed_by"], answer["kept"]) == (0, 4.0, "Symfonium", None)
    assert player.store.play_queue("ethan") is not None


def test_another_apps_name_is_cleaned_before_the_notice_shows_it(player):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 2)
    another_app(player, "ethan", ids, current=ids[0], client="Sym\x07fon\u202eium\n" + "x" * 80)
    assert ethan.get(QUEUE).json()["changed_by"] == "Symfonium" + "x" * 55


def test_songs_gone_are_left_out_and_the_stored_index_is_answered_as_navidrome_does(player):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 5)
    ethan.post(QUEUE, json=body(ids, index=3))
    del player.fake.songs[ids[1]]
    answer = ethan.get(QUEUE).json()
    assert [t["id"] for t in answer["tracks"]] == [ids[0], ids[2], ids[3], ids[4]]
    #? still 3 - which is now ids[4]: the page aligns it against kept.ids (lib/resume.ts)
    assert answer["index"] == 3 and answer["kept"]["ids"] == ids and answer["kept"]["index"] == 3


def test_an_empty_navidrome_queue_is_answered_as_one(player):
    ethan = signed_in(player, "ethan")
    answer = ethan.get(QUEUE).json()
    assert answer == {"tracks": [], "index": None, "position": 0, "changed_by": "", "shared": False, "kept": None}
    #? a record with Navidrome's queue cleared by another app: Navidrome is the authority
    ids = songs(player, 2)
    ethan.post(QUEUE, json=body(ids))
    player.fake.play_queue_call("savePlayQueue", "ethan", {"c": ["Symfonium"]})
    assert ethan.get(QUEUE).json()["tracks"] == [] and player.store.play_queue("ethan") is not None


def test_a_foreign_list_over_two_thousand_is_the_window_around_its_song(player):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 2500)
    another_app(player, "ethan", ids, current=ids[100])
    answer = ethan.get(QUEUE).json()
    assert len(answer["tracks"]) == 2000 and answer["tracks"][0]["id"] == ids[50] and answer["index"] == 50
    assert answer["tracks"][answer["index"]]["id"] == ids[100]


# ----------------------------------------------------------------- Navidrome failing

@pytest.mark.parametrize("how", ["502", "unreachable", "subsonic error"])
def test_a_navidrome_failure_leaves_the_record_and_the_next_save_carries_on(player, how):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 3)
    assert ethan.post(QUEUE, json=body(ids)).json()["rev"] == 1
    before = player.store.play_queue("ethan")
    if how == "502":
        player.fake.errors[("ethan", "savePlayQueueByIndex")] = httpx.Response(502)
    elif how == "unreachable":
        player.fake.down = True
    else:
        player.fake.errors[("ethan", "savePlayQueueByIndex")] = httpx.Response(200, json=failed(0, "database is locked"))
    for answer in (ethan.post(QUEUE, json=body(ids[::-1])), ethan.post(AT, json=at_body(1, 2))):
        assert answer.status_code == 502, (how, answer.text)
    assert player.store.play_queue("ethan") == before
    player.fake.errors.clear()
    player.fake.down = False
    assert ethan.post(AT, json=at_body(1, 2)).json() == {"rev": 2, "ids_rev": 1}
    assert ethan.post(QUEUE, json=body(ids[::-1])).json() == {"rev": 3, "ids_rev": 3}


def test_navidrome_refusing_the_login_ends_the_session_and_writes_nothing(player, caplog):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 2)
    player.fake.errors[("ethan", "savePlayQueueByIndex")] = httpx.Response(200, json=failed(40, "Wrong username or password"))
    with caplog.at_level("WARNING"):
        refused = ethan.post(QUEUE, json=body(ids))
    assert refused.status_code == 401 and refused.json()["detail"] == auth.LOGIN_GONE
    assert player.store.play_queue("ethan") is None
    assert ethan.get(QUEUE).status_code == 401
    #? a session ending isn't Navidrome failing to keep the queue: nothing said in the server's log for it
    assert not [record for record in caplog.records if "play queue" in record.getMessage()]


def test_a_failed_write_is_said_once_in_the_servers_log_not_once_a_save(player, caplog):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 2)
    player.fake.errors[("ethan", "savePlayQueueByIndex")] = httpx.Response(502)
    caplog.set_level("WARNING")
    for _ in range(4):
        ethan.post(QUEUE, json=body(ids))
    said = [record for record in caplog.records if "play queue" in record.getMessage()]
    assert len(said) == 1 and not getattr(said[0], "frontend", False)


# ----------------------------------------------------------------- every body bounded and declared

@pytest.mark.parametrize("change, words", [
    ({"ids": [f"s{n}" for n in range(2001)]}, None),
    ({"ids": []}, None),
    ({"index": 3}, "isn't in the queue sent"),
    ({"index": -1}, None),
    ({"position": -1}, None),
    ({"position": 86401}, None),
    ({"device": "short"}, None),
    ({"device": "bad device id"}, None),
    ({"label": "Mac\x07"}, None),
    ({"label": ""}, None),
    ({"label": "x" * 41}, None),
    ({"snapshot": "{not json"}, "isn't JSON"),
    ({"snapshot": "[]"}, "isn't an object"),
    ({"snapshot": '{"levels":"aa"}'}, "v 1"),
    ({"snapshot": '{"v":1,"pad":"' + "x" * rules.SNAPSHOT_MAX + '"}'}, None),
    ({"shuffle": True}, None),
])
def test_a_body_out_of_bounds_is_a_422_in_words_and_reaches_nothing(player, change, words):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 3)
    refused = ethan.post(QUEUE, json={**body(ids), **change})
    assert refused.status_code == 422, (change, refused.text[:200])
    detail = refused.json()["detail"]
    assert isinstance(detail, str) and (words in detail if words else detail == rules.QUEUE_FORM), detail
    #? never the echo of what was sent - a 256 KB account of Up Next would come back with it
    assert len(refused.text) < 300
    assert player.fake.queue_calls == [] and player.store.play_queue("ethan") is None


@pytest.mark.parametrize("change", [{"ids_rev": 0}, {"index": -1}, {"position": float("inf")}, {"device": "x"},
                                    {"label": "\n"}, {"ids": ["a"]}, {"snapshot": None}])
def test_a_position_save_out_of_bounds_or_with_more_is_a_422(player, change):
    ethan = signed_in(player, "ethan")
    refused = ethan.post(AT, content=json.dumps({**at_body(1, 0), **change}), headers={"Content-Type": "application/json"})
    assert refused.status_code == 422 and refused.json()["detail"] == rules.QUEUE_FORM, refused.text
    assert player.fake.queue_calls == []


# ----------------------------------------------------------------- one save at a time per user

class Timed:
    """The fake Navidrome a round trip away: each save of the play queue waits the next of `delays` (seconds) before
    it is answered; every other call answers at once. How many saves were out at once, at most."""

    def __init__(self, fake, delays):
        self.fake, self.delays = fake, list(delays)
        self.flying = self.most = 0

    async def __call__(self, request: httpx.Request) -> httpx.Response:
        if not request.url.path.endswith("savePlayQueueByIndex"):
            return self.fake.handle(request)
        delay = self.delays.pop(0) if self.delays else 0
        self.flying += 1
        self.most = max(self.most, self.flying)
        try:
            await asyncio.sleep(delay)
            return self.fake.handle(request)
        finally:
            self.flying -= 1


def async_client(env, signed: TestClient) -> httpx.AsyncClient:
    """The app spoken to from this test's own event loop, with a signed-in client's session."""
    return httpx.AsyncClient(transport=httpx.ASGITransport(app=env.app), base_url="http://testserver",
                             cookies=dict(signed.cookies))


def test_a_full_save_and_a_position_save_for_one_user_never_interleave(player):
    """A full save whose Navidrome write is slow, and a position save against the ids it is replacing that comes in
    meanwhile with a slower write still: one at a time, the position save sees the new ids and is a 409 - Navidrome
    and the record both hold the new ids. Without the lock it would read the old record, and its write of the OLD ids
    would land in Navidrome last, after the new ones."""
    ethan = signed_in(player, "ethan")
    ids = songs(player, 4)
    assert ethan.post(QUEUE, json=body(ids[:2])).json() == {"rev": 1, "ids_rev": 1}
    timed = Timed(player.fake, [0.1, 0.25])
    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(timed), base_url=f"{NAVIDROME}/rest")

    async def both():
        async with async_client(player, ethan) as client:
            full = asyncio.create_task(client.post(QUEUE, json=body(ids[2:], device="desk-device-2")))
            await asyncio.sleep(0.02)
            position = asyncio.create_task(client.post(AT, json=at_body(1, 1)))
            return await full, await position

    full, position = asyncio.run(both())
    assert full.json() == {"rev": 2, "ids_rev": 2} and position.status_code == 409
    assert timed.most == 1
    assert player.fake.queues["ethan"]["ids"] == ids[2:] and player.store.play_queue("ethan")["ids"] == ids[2:]


@pytest.mark.parametrize("slow", ["navidrome", "record"])
def test_a_read_waits_for_a_save_in_flight_and_never_reads_between_its_writes(player, monkeypatch, slow):
    """A reload's GET while the save its page sent going away is still out: with Navidrome's write slow, read before
    it the queue would come back from the save before; with the record's slow, read between the two writes Navidrome's
    new ids would sit beside the old record and come back a plain list. Under the lock it answers once the save is
    done, both places agreeing."""
    ethan = signed_in(player, "ethan")
    ids = songs(player, 4)
    assert ethan.post(QUEUE, json=body(ids[:2])).json() == {"rev": 1, "ids_rev": 1}
    if slow == "navidrome":
        timed = Timed(player.fake, [0.25])
        navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(timed), base_url=f"{NAVIDROME}/rest")
    else:
        put = player.store.put_play_queue

        def slow_put(*args):
            time.sleep(0.25)
            return put(*args)

        monkeypatch.setattr(player.store, "put_play_queue", slow_put)

    async def both():
        async with async_client(player, ethan) as client:
            save = asyncio.create_task(client.post(QUEUE, json=body(ids[2:], device="desk-device-2")))
            await asyncio.sleep(0.05)
            read = asyncio.create_task(client.get(QUEUE))
            return await save, await read

    save, read = asyncio.run(both())
    assert save.json() == {"rev": 2, "ids_rev": 2}
    answer = read.json()
    assert [t["id"] for t in answer["tracks"]] == ids[2:]
    assert answer["kept"]["ids"] == ids[2:] and answer["kept"]["rev"] == 2 and answer["kept"]["device"] == "desk-device-2"


def test_two_users_saves_never_wait_on_each_other(player):
    ethan, james = signed_in(player, "ethan"), signed_in(player, "james")
    ids = songs(player, 2)
    #? each login answered once, so neither goes alone (navidrome_endpoint.UserClient's gate)
    ethan.get(QUEUE)
    james.get(QUEUE)
    timed = Timed(player.fake, [0.2, 0.2])
    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(timed), base_url=f"{NAVIDROME}/rest")

    async def both():
        async with async_client(player, ethan) as first, async_client(player, james) as second:
            started = time.monotonic()
            answers = await asyncio.gather(first.post(QUEUE, json=body(ids)), second.post(QUEUE, json=body(ids[::-1])))
            return answers, time.monotonic() - started

    (one, two), took = asyncio.run(both())
    assert one.status_code == two.status_code == 200
    assert timed.most == 2 and took < 0.35


# ----------------------------------------------------------------- whose queue it is

def test_one_persons_queue_and_record_are_never_another_persons(player):
    ethan, james = signed_in(player, "ethan"), signed_in(player, "james")
    ids = songs(player, 3)
    ethan.post(QUEUE, json=body(ids))
    assert james.get(QUEUE).json() == {"tracks": [], "index": None, "position": 0, "changed_by": "", "shared": False,
                                       "kept": None}
    #? james's own Navidrome queue saved by deadwax elsewhere - but no record of his: nothing of ethan's handed out
    player.fake.play_queue_call("savePlayQueueByIndex", "james", {"id": [ids[0]], "currentIndex": ["0"], "c": ["deadwax"]})
    assert james.get(QUEUE).json()["kept"] is None
    #? and james's position save can't move ethan's record
    assert james.post(AT, json=at_body(1, 0)).status_code == 409
    assert player.store.play_queue("ethan")["rev"] == 1


def test_with_logins_off_it_is_locals_and_the_shared_accounts_one_queue(player, monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    anyone = TestClient(player.app)
    ids = songs(player, 2)
    assert anyone.post(QUEUE, json=body(ids)).json() == {"rev": 1, "ids_rev": 1}
    answer = anyone.get(QUEUE).json()
    assert answer["shared"] is True and answer["kept"]["ids"] == ids
    assert {c["user"] for c in player.fake.queue_calls} == {"demo"}
    assert player.store.play_queue(LOCAL_USER)["rev"] == 1


def test_the_break_glass_admin_keeps_no_queue_and_asks_nothing(player):
    glass = signed_in(player, auth.BREAK_GLASS_USER)
    ids = songs(player, 2)
    #? the shared account's queue, which may be a person's, is never shown to it
    player.fake.play_queue_call("savePlayQueueByIndex", "demo", {"id": ids, "currentIndex": ["1"], "c": ["deadwax"]})
    assert glass.get(QUEUE).json() == {"tracks": [], "index": None, "position": 0, "changed_by": "", "shared": False,
                                       "kept": None}
    for answer in (glass.get(QUEUE), glass.post(QUEUE, json=body(ids)), glass.post(AT, json=at_body(1, 0))):
        assert answer.headers["cache-control"] == "no-store"
    assert glass.post(QUEUE, json=body(ids)).json() == {"rev": None, "ids_rev": None}
    assert glass.post(AT, json=at_body(1, 0)).json() == {"rev": None, "ids_rev": None}
    assert player.fake.queue_calls == []
    assert player.fake.queues["demo"]["current"] == 1 and player.store.play_queue(auth.BREAK_GLASS_USER) is None


# ----------------------------------------------------------------- the record in the database

def test_forgetting_a_person_clears_their_queue_and_the_take_over_leaves_locals(player):
    store = player.store
    store.put_play_queue("ethan", ["a"], 0, 1.0, None, DEVICE, "iPhone")
    store.put_play_queue(LOCAL_USER, ["b"], 0, 2.0, None, DEVICE, "Mac")
    assert store.keeps_anything("ethan") and store.known_users()["ethan"]["queue"] is True
    assert store.forget_person("ethan")["play_queue"] == 1
    assert store.play_queue("ethan") is None and not store.keeps_anything("ethan")
    store.adopt_local_now("james")
    assert store.play_queue(LOCAL_USER)["ids"] == ["b"] and store.play_queue("james") is None


def test_a_name_with_only_a_queue_left_is_listed_to_be_forgotten(player):
    player.store.put_play_queue("olduser", ["a"], 0, 1.0, None, DEVICE, "iPhone")
    assert player.store.known_users()["olduser"] == {"user": "olduser", "sessions": 0, "credential": False, "library": 0,
                                                     "pins": 0, "preferences": False, "requests": 0, "permissions": 0,
                                                     "queue": True}


def test_an_existing_database_gains_the_table(tmp_path):
    path = tmp_path / "deadwax.db"
    store = JobStore(str(path))
    store.init()
    with sqlite3.connect(path) as connection:
        connection.execute("DROP TABLE play_queue")
    store.init()
    assert store.available
    assert store.put_play_queue("ethan", ["a", "a"], 1, 3.5, None, DEVICE, "iPhone") == (1, 1)
    assert store.move_play_queue("ethan", 1, 0, 9.0, DEVICE, "iPhone") == (2, 1)
    assert store.move_play_queue("ethan", 2, 0, 9.0, DEVICE, "iPhone") is None
    assert store.put_play_queue("ethan", ["b"], 0, 0.0, '{"v":1}', DEVICE, "iPhone") == (3, 3)
    assert store.play_queue("ethan") == {"rev": 3, "ids_rev": 3, "ids": ["b"], "index": 0, "position": 0.0,
                                         "snapshot": '{"v":1}', "device": DEVICE, "label": "iPhone"}


def test_without_its_database_a_save_says_so_and_navidrome_is_not_written(player, monkeypatch):
    #? (logins off: with them on, no database lets nobody in at all - src/auth.py)
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    anyone = TestClient(player.app)
    ids = songs(player, 2)
    player.store.available = False
    try:
        refused = anyone.post(QUEUE, json=body(ids))
        assert refused.status_code == 503 and refused.json()["detail"] == rules.NO_RECORD
        assert player.fake.queue_calls == []
    finally:
        player.store.available = True


def test_the_record_failing_to_read_still_answers_navidromes_queue(player, monkeypatch, caplog):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 3)
    ethan.post(QUEUE, json=body(ids, index=1))

    def broken(*_args):
        raise sqlite3.OperationalError("database is locked")

    monkeypatch.setattr(player.store, "play_queue", broken)
    with caplog.at_level("ERROR"):
        read = ethan.get(QUEUE)
    assert read.status_code == 200 and read.headers["cache-control"] == "no-store"
    answer = read.json()
    #? the songs as Navidrome holds them, its index and position - the page puts them back as a plain list
    assert [t["id"] for t in answer["tracks"]] == ids and answer["index"] == 1 and answer["kept"] is None
    assert any("couldn't read ethan's play queue" in record.getMessage() for record in caplog.records)


@pytest.mark.parametrize("failing, route", [("put_play_queue", QUEUE), ("move_play_queue", AT), ("play_queue", AT)])
def test_the_record_failing_on_a_save_is_a_503_in_words(player, monkeypatch, failing, route):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 3)
    assert ethan.post(QUEUE, json=body(ids)).json() == {"rev": 1, "ids_rev": 1}

    def broken(*_args):
        raise sqlite3.OperationalError("database is locked")

    monkeypatch.setattr(player.store, failing, broken)
    refused = ethan.post(route, json=body(ids[::-1]) if route == QUEUE else at_body(1, 2))
    assert refused.status_code == 503 and refused.json()["detail"] == rules.NO_RECORD


# ----------------------------------------------------------------- the same-origin guard

def test_the_pages_own_json_post_passes_the_guard_and_another_sites_does_not(player):
    ethan = signed_in(player, "ethan")
    ids = songs(player, 2)
    own = ethan.post(QUEUE, content=json.dumps(body(ids)),
                     headers={"Origin": "http://testserver", "Content-Type": "application/json"})
    assert own.status_code == 200
    foreign = ethan.post(AT, content=json.dumps(at_body(1, 1)),
                         headers={"Origin": "http://evil.example", "Content-Type": "application/json"})
    assert foreign.status_code == 403 and player.store.play_queue("ethan")["rev"] == 1
    assert navidrome_endpoint.CLIENT_NAME == "deadwax"
