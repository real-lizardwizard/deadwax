"""
Play history that lasts (2.1.14) - src/play_history.py, src/routes/play_history.py and store.py's play_history,
through the whole app start() builds (no lifespan), a real SQLite store and the player's fake Navidrome
(tests/test_player_as_you.py's Player), whose scrobble the counted mark rides on.

What these hold:

  - A start kept as sent - the song in the queue's own shape, its queue and entry - and paged back newest first,
    100 by default, `next` the last one's own time and song; two songs begun in the same millisecond still page.
  - The same start sent again (a lost answer, the phone's offline batch twice) is the same row: `counted` ORed in,
    never taken back, the rest as first kept.
  - A start that can't be right is SKIPPED, the rest taken: a clock in the future or before 2020, no song id, one
    too long; text cut, numbers clamped, a queue id that isn't one kept as none. Each start is validated on its own:
    one of a wrong type is skipped, the rest of its batch taken, and a field deadwax doesn't know (a newer app's) is
    ignored. Only a body that isn't a batch - no starts, none, too many - is a 422.
  - A counted scrobble with its `time` marks its start counted - whatever Navidrome answers, and a resend too; one
    without a `time`, or "now playing", marks nothing.
  - Privacy: each person their own; logins off, everything `local`'s, `shared`.
  - No database: GET answers nothing, POST a 503; a failing one a 503 either way. Every answer no-store.
  - forget_person clears it, known_users counts it, adopt_local hands `local`'s to the first admin, an existing
    database gains the table; the guard trims the oldest past the cap, once a day per person and sooner after
    HISTORY_TRIM_AFTER starts. A page asked from past SQLite's INTEGER is a 422, never an overflow.
"""

import sqlite3
import time

import pytest
from fastapi.testclient import TestClient

from src import auth, play_history as rules
from src.config import Config
from src.routes import navidrome as navidrome_routes
from src.routes import play_history as history_routes
from src.store import JobStore, PLAY_HISTORY_COLUMNS
from src.users import LOCAL_USER
from tests import test_personal_libraries, test_player_as_you
from tests.test_personal_libraries import signed_in

on = test_personal_libraries.on
player = test_player_as_you.player

HISTORY = "/deadwax/me/history"
PLAYER = "/deadwax/navidrome"
NOW = int(time.time() * 1000)
SONG = "nd-song-1"


@pytest.fixture(autouse=True)
def fresh():
    history_routes.forget_trims()
    navidrome_routes.forget_plays_counted()
    yield
    history_routes.forget_trims()
    navidrome_routes.forget_plays_counted()


def song(song_id: str = SONG, **more) -> dict:
    return {"id": song_id, "title": "Teardrop", "artist": "Massive Attack", "album": "Mezzanine", "albumId": "nd-al-1",
            "coverArt": "al-nd-al-1_0", "duration": 330.5, "contentType": "audio/flac", "suffix": "flac",
            "sampleRate": 44100, "bitDepth": 16, "channels": 2, **more}


def start(at: int, song_id: str = SONG, counted: bool = False, queue: str | None = "q-1", entry: int | None = 0,
          **more) -> dict:
    return {"at": at, "counted": counted, "queue": queue, "entry": entry, "song": song(song_id), **more}


def plays(client, **query) -> dict:
    answer = client.get(HISTORY, params=query)
    assert answer.status_code == 200, answer.text
    assert answer.headers["cache-control"] == "no-store"
    return answer.json()


def kept(path, user: str | None = None) -> list[dict]:
    with sqlite3.connect(path) as connection:
        connection.row_factory = sqlite3.Row
        where = " WHERE user = ?" if user else ""
        return [dict(row) for row in connection.execute(
            f"SELECT * FROM play_history{where} ORDER BY started_at", (user,) if user else ())]


# ----------------------------------------------------------------- the pure half

def test_a_start_is_kept_as_its_columns():
    row = rules.clean_start(start(NOW - 5000, entry=12), NOW)
    assert row == {"started_at": NOW - 5000, "song_id": SONG, "title": "Teardrop", "artist": "Massive Attack",
                   "album": "Mezzanine", "album_id": "nd-al-1", "cover_art": "al-nd-al-1_0", "duration": 330.5,
                   "content_type": "audio/flac", "suffix": "flac", "sample_rate": 44100, "bit_depth": 16,
                   "channels": 2, "counted": 0, "queue": "q-1", "entry": 12, "recorded_at": NOW}
    assert tuple(row) == ("started_at", *PLAY_HISTORY_COLUMNS[1:]) and PLAY_HISTORY_COLUMNS == rules.COLUMNS
    assert rules.play_of({**row, "user": "ethan"}) == start(NOW - 5000, entry=12)


@pytest.mark.parametrize("at", [NOW + rules.HISTORY_FUTURE_MS + 1, rules.HISTORY_EARLIEST_MS - 1, 0, True, 1.5, "1"])
def test_a_start_dated_where_no_listen_was_is_skipped(at):
    assert rules.clean_start(start(at), NOW) is None


def test_the_edges_of_when_are_taken():
    assert rules.clean_start(start(NOW + rules.HISTORY_FUTURE_MS), NOW)["started_at"] == NOW + rules.HISTORY_FUTURE_MS
    assert rules.clean_start(start(rules.HISTORY_EARLIEST_MS), NOW) is not None


@pytest.mark.parametrize("song_id", ["", "x" * (rules.HISTORY_ID_MAX + 1), None, 7])
def test_a_start_with_no_usable_song_id_is_skipped(song_id):
    raw = start(NOW)
    raw["song"]["id"] = song_id
    assert rules.clean_start(raw, NOW) is None


def test_what_is_long_is_cut_and_what_is_wrong_is_kept_as_none():
    raw = start(NOW, queue="not a queue id!", entry=-1)
    raw["song"].update(title="t" * 900, albumId="a" * 900, duration=float("nan"), sampleRate=-4, bitDepth=True,
                       contentType="")
    row = rules.clean_start(raw, NOW)
    assert len(row["title"]) == rules.HISTORY_TEXT_MAX and len(row["album_id"]) == rules.HISTORY_ID_MAX
    assert (row["duration"], row["sample_rate"], row["bit_depth"], row["content_type"]) == (0.0, 0, 0, None)
    assert (row["queue"], row["entry"]) == (None, None)
    assert rules.clean_start({**start(NOW), "counted": "yes"}, NOW)["counted"] == 0


def test_the_ids_bound_is_the_navidrome_routes_own():
    assert rules.HISTORY_ID_MAX == navidrome_routes.ID_MAX


def test_a_page_says_next_only_when_there_is_more():
    rows = [rules.clean_start(start(NOW - n, f"s-{n}"), NOW) for n in range(3)]
    assert rules.page(rows, 3, False)["next"] is None
    page = rules.page(rows, 2, True)
    assert [play["song"]["id"] for play in page["plays"]] == ["s-0", "s-1"]
    assert page["next"] == {"at": NOW - 1, "id": "s-1"} and page["shared"] is True
    assert rules.page([], 2, False) == {"plays": [], "next": None, "shared": False}


# ----------------------------------------------------------------- kept, and read back

def test_starts_are_kept_and_paged_back_newest_first(player):
    ethan = signed_in(player, "ethan")
    sent = [start(NOW - 60_000 * n, f"s-{n}", entry=n) for n in range(250)]
    answer = ethan.post(HISTORY, json={"starts": sent})
    assert answer.status_code == 200, answer.text
    assert answer.json() == {"taken": 250, "skipped": 0} and answer.headers["cache-control"] == "no-store"
    first = plays(ethan)
    assert [play["song"]["id"] for play in first["plays"]] == [f"s-{n}" for n in range(100)]
    assert first["plays"][0] == start(NOW, "s-0", entry=0) and first["shared"] is False
    assert first["next"] == {"at": NOW - 60_000 * 99, "id": "s-99"}
    second = plays(ethan, before_at=first["next"]["at"], before_id=first["next"]["id"])
    third = plays(ethan, before_at=second["next"]["at"], before_id=second["next"]["id"])
    assert [play["song"]["id"] for play in second["plays"] + third["plays"]] == [f"s-{n}" for n in range(100, 250)]
    assert third["next"] is None
    assert len(plays(ethan, limit=500)["plays"]) == 250


def test_two_songs_begun_the_same_millisecond_both_page(player):
    ethan = signed_in(player, "ethan")
    ethan.post(HISTORY, json={"starts": [start(NOW, "b"), start(NOW, "a"), start(NOW - 1, "c")]})
    first = plays(ethan, limit=1)
    second = plays(ethan, limit=1, before_at=first["next"]["at"], before_id=first["next"]["id"])
    third = plays(ethan, limit=1, before_at=second["next"]["at"], before_id=second["next"]["id"])
    assert [p["plays"][0]["song"]["id"] for p in (first, second, third)] == ["b", "a", "c"]
    assert third["next"] is None
    #? `before_at` alone is everything before that moment
    assert [p["song"]["id"] for p in plays(ethan, before_at=NOW)["plays"]] == ["c"]


def test_the_same_start_twice_is_one_row_and_counted_is_never_taken_back(player):
    ethan = signed_in(player, "ethan")
    assert ethan.post(HISTORY, json={"starts": [start(NOW), start(NOW)]}).json() == {"taken": 2, "skipped": 0}
    assert len(kept(player.path, "ethan")) == 1
    ethan.post(HISTORY, json={"starts": [start(NOW, counted=True)]})
    assert kept(player.path, "ethan")[0]["counted"] == 1
    renamed = start(NOW)
    renamed["song"]["title"] = "Something else"
    ethan.post(HISTORY, json={"starts": [renamed]})
    row = kept(player.path, "ethan")[0]
    assert (row["counted"], row["title"]) == (1, "Teardrop")


def test_a_bad_start_is_skipped_and_the_rest_taken(player):
    ethan = signed_in(player, "ethan")
    answer = ethan.post(HISTORY, json={"starts": [start(NOW + 3_600_000, "future"), start(NOW, "fine"),
                                                  start(1000, "1970"), start(NOW - 1, "")]})
    assert answer.json() == {"taken": 1, "skipped": 3}
    assert [row["song_id"] for row in kept(player.path, "ethan")] == ["fine"]


@pytest.mark.parametrize("body", [
    {"starts": []},
    {"starts": [start(NOW)] * (rules.HISTORY_POST_MAX + 1)},
    {"starts": start(NOW)},
    {"starts": None},
    {},
])
def test_a_body_that_isnt_a_batch_of_starts_is_refused(player, body):
    ethan = signed_in(player, "ethan")
    assert ethan.post(HISTORY, json=body).status_code == 422
    assert kept(player.path) == []


@pytest.mark.parametrize("bad", [
    {**start(NOW - 5, "bad"), "at": "soon"},
    {**start(NOW - 5, "bad"), "at": 1.5e12},
    {**start(NOW - 5, "bad"), "counted": "perhaps"},
    {**start(NOW - 5, "bad"), "entry": "first"},
    {**start(NOW - 5, "bad"), "song": {**song("bad"), "duration": "long"}},
    {**start(NOW - 5, "bad"), "song": {"title": "no id"}},
    {**start(NOW - 5, "bad"), "song": None},
    "a start",
    None,
    [],
])
def test_one_bad_start_is_skipped_and_the_rest_of_its_batch_taken(player, bad):
    """The apps let a batch answered with a 4xx go - so one start that fails validation must cost only itself."""
    ethan = signed_in(player, "ethan")
    answer = ethan.post(HISTORY, json={"starts": [start(NOW, "first"), bad, start(NOW - 10, "last")]})
    assert answer.status_code == 200, answer.text
    assert answer.json() == {"taken": 2, "skipped": 1}
    assert [row["song_id"] for row in kept(player.path, "ethan")] == ["last", "first"]


def test_a_field_deadwax_doesnt_know_is_ignored_never_refused(player):
    """A newer app (the phone's, talking to an older deadwax) may send more: the start is kept as it would be without
    it - at the start's level, the song's and the batch's."""
    ethan = signed_in(player, "ethan")
    james = signed_in(player, "james")
    plain = {"starts": [start(NOW, "a"), start(NOW - 1, "b")]}
    more = {"starts": [{**start(NOW, "a"), "device": "phone", "position": 12.5},
                       {**start(NOW - 1, "b"), "song": {**song("b"), "level": "album", "isrc": "GBAAA9800001"}}],
            "client": "deadwax-ios/0.9"}
    assert ethan.post(HISTORY, json=plain).json() == {"taken": 2, "skipped": 0}
    assert james.post(HISTORY, json=more).json() == {"taken": 2, "skipped": 0}
    unlike = ("user", "recorded_at")
    strip = lambda rows: [{k: v for k, v in row.items() if k not in unlike} for row in rows]  # noqa: E731
    assert strip(kept(player.path, "james")) == strip(kept(player.path, "ethan"))
    assert plays(james)["plays"] == plays(ethan)["plays"]


def test_a_full_batch_is_taken(player):
    ethan = signed_in(player, "ethan")
    batch = [start(NOW - n, f"s-{n}") for n in range(rules.HISTORY_POST_MAX)]
    assert ethan.post(HISTORY, json={"starts": batch}).json() == {"taken": rules.HISTORY_POST_MAX, "skipped": 0}


def test_a_page_is_bounded(player):
    ethan = signed_in(player, "ethan")
    for query in ({"limit": 0}, {"limit": rules.HISTORY_PAGE_MAX + 1}, {"before_id": "s-1"},
                  {"before_at": -1}, {"before_at": 1, "before_id": "x" * (rules.HISTORY_ID_MAX + 1)},
                  {"before_at": 10**30}, {"before_at": 2**63}):
        assert ethan.get(HISTORY, params=query).status_code == 422, query
    #? the largest SQLite holds still answers - everything kept is before it
    ethan.post(HISTORY, json={"starts": [start(NOW)]})
    assert len(plays(ethan, before_at=2**63 - 1, before_id="z")["plays"]) == 1


# ----------------------------------------------------------------- counted, by the scrobble

def test_a_counted_play_marks_its_start_counted(player):
    ethan = signed_in(player, "ethan")
    ethan.post(HISTORY, json={"starts": [start(NOW, SONG), start(NOW - 1000, SONG)]})
    ethan.post(f"{PLAYER}/scrobble/{SONG}?submission=false")
    ethan.post(f"{PLAYER}/scrobble/{SONG}?submission=true")
    assert [row["counted"] for row in kept(player.path, "ethan")] == [0, 0]
    assert ethan.post(f"{PLAYER}/scrobble/{SONG}?submission=true&time={NOW}").status_code == 200
    assert [row["counted"] for row in kept(player.path, "ethan")] == [0, 1]
    #? a resend - counted once in Navidrome - marks it all the same
    assert ethan.post(f"{PLAYER}/scrobble/{SONG}?submission=true&time={NOW - 1000}").status_code == 200
    assert ethan.post(f"{PLAYER}/scrobble/{SONG}?submission=true&time={NOW - 1000}").status_code == 200
    assert [row["counted"] for row in kept(player.path, "ethan")] == [1, 1]
    assert [play["counted"] for play in plays(ethan)["plays"]] == [True, True]


def test_a_count_marks_only_the_askers_start(player):
    ethan = signed_in(player, "ethan")
    james = signed_in(player, "james")
    ethan.post(HISTORY, json={"starts": [start(NOW)]})
    james.post(HISTORY, json={"starts": [start(NOW)]})
    james.post(f"{PLAYER}/scrobble/{SONG}?submission=true&time={NOW}")
    assert (kept(player.path, "ethan")[0]["counted"], kept(player.path, "james")[0]["counted"]) == (0, 1)


def test_a_count_navidrome_refuses_still_marks_the_start(player):
    ethan = signed_in(player, "ethan")
    ethan.post(HISTORY, json={"starts": [start(NOW, "nd-gone")]})
    answer = ethan.post(f"{PLAYER}/scrobble/nd-gone?submission=true&time={NOW}")
    assert kept(player.path, "ethan")[0]["counted"] == 1, answer.status_code


def test_a_count_with_no_database_is_still_sent(player, monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    anyone = TestClient(player.app)
    player.store.available = False
    try:
        assert anyone.post(f"{PLAYER}/scrobble/{SONG}?submission=true&time={NOW}").status_code == 200
    finally:
        player.store.available = True


# ----------------------------------------------------------------- whose

def test_each_person_sees_only_their_own(player):
    ethan = signed_in(player, "ethan")
    james = signed_in(player, "james")
    ethan.post(HISTORY, json={"starts": [start(NOW, "ethans")]})
    james.post(HISTORY, json={"starts": [start(NOW, "james's")]})
    assert [p["song"]["id"] for p in plays(ethan)["plays"]] == ["ethans"]
    assert [p["song"]["id"] for p in plays(james)["plays"]] == ["james's"]


def test_with_logins_off_it_is_locals_one_history_shared(player, monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    anyone = TestClient(player.app)
    assert anyone.post(HISTORY, json={"starts": [start(NOW)]}).json() == {"taken": 1, "skipped": 0}
    answer = plays(anyone)
    assert answer["shared"] is True and len(answer["plays"]) == 1
    assert [row["user"] for row in kept(player.path)] == [LOCAL_USER]


def test_the_break_glass_admin_keeps_its_own(player):
    glass = signed_in(player, auth.BREAK_GLASS_USER)
    glass.post(HISTORY, json={"starts": [start(NOW)]})
    assert [row["user"] for row in kept(player.path)] == [auth.BREAK_GLASS_USER]


# ----------------------------------------------------------------- the database

def test_without_a_database_a_read_answers_nothing_and_a_write_says_so(player, monkeypatch):
    #? (logins off: with them on, no database lets nobody in at all - src/auth.py)
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    anyone = TestClient(player.app)
    player.store.available = False
    try:
        assert plays(anyone) == {"plays": [], "next": None, "shared": True}
        refused = anyone.post(HISTORY, json={"starts": [start(NOW)]})
        assert refused.status_code == 503 and refused.json()["detail"] == history_routes.NO_RECORD
    finally:
        player.store.available = True


def test_a_database_failing_just_now_is_a_503_either_way(player, monkeypatch):
    ethan = signed_in(player, "ethan")

    def broken(*_):
        raise sqlite3.OperationalError("disk I/O error")

    monkeypatch.setattr(player.store, "record_starts", broken)
    monkeypatch.setattr(player.store, "history_page", broken)
    refused = ethan.post(HISTORY, json={"starts": [start(NOW)]})
    assert refused.status_code == 503 and refused.json()["detail"] == history_routes.UNWRITTEN
    unread = ethan.get(HISTORY)
    assert unread.status_code == 503 and unread.json()["detail"] == history_routes.UNREAD


def test_forgetting_a_person_clears_it_and_known_users_counts_it(player):
    store = player.store
    store.record_starts("olduser", [rules.clean_start(start(NOW - n, f"s-{n}"), NOW) for n in range(3)])
    store.record_starts("ethan", [rules.clean_start(start(NOW), NOW)])
    assert store.keeps_anything("olduser")
    assert store.known_users()["olduser"] == {"user": "olduser", "sessions": 0, "credential": False, "library": 0,
                                              "pins": 0, "preferences": False, "requests": 0, "permissions": 0,
                                              "queue": False, "history": 3}
    assert store.forget_person("olduser")["play_history"] == 3
    assert not store.keeps_anything("olduser") and kept(player.path, "olduser") == []
    assert len(kept(player.path, "ethan")) == 1


def test_the_take_over_hands_locals_plays_to_the_first_admin(player):
    store = player.store
    store.record_starts(LOCAL_USER, [rules.clean_start(start(NOW, "a", counted=True), NOW),
                                     rules.clean_start(start(NOW - 1, "b"), NOW)])
    store.record_starts("james", [rules.clean_start(start(NOW, "a"), NOW)])
    assert store.local_has_anything()
    store.adopt_local_now("james")
    rows = kept(player.path, "james")
    #? a start they already had keeps theirs
    assert [(row["song_id"], row["counted"]) for row in rows] == [("b", 0), ("a", 0)]
    assert kept(player.path, LOCAL_USER) == [] and not store.local_has_anything()


def test_an_existing_database_gains_the_table(tmp_path):
    path = tmp_path / "deadwax.db"
    store = JobStore(str(path))
    store.init()
    with sqlite3.connect(path) as connection:
        connection.execute("DROP TABLE play_history")
    store.init()
    assert store.available
    assert store.record_starts("ethan", [rules.clean_start(start(NOW), NOW)]) == 1
    assert store.mark_counted("ethan", SONG, NOW) == 1 and store.mark_counted("ethan", SONG, NOW) == 0
    assert [row["counted"] for row in store.history_page("ethan", 10)] == [1]


def test_the_guard_trims_the_oldest_past_the_cap_once_a_day(player, monkeypatch):
    ethan = signed_in(player, "ethan")
    monkeypatch.setattr(rules, "HISTORY_KEPT_MAX", 3)
    ethan.post(HISTORY, json={"starts": [start(NOW - n, f"s-{n}") for n in range(5)]})
    assert [row["song_id"] for row in kept(player.path, "ethan")] == ["s-2", "s-1", "s-0"]
    #? looked at once a day: a second write the same day keeps what it adds
    ethan.post(HISTORY, json={"starts": [start(NOW + 1, "new")]})
    assert len(kept(player.path, "ethan")) == 4
    history_routes.forget_trims()
    ethan.post(HISTORY, json={"starts": [start(NOW + 2, "newer")]})
    assert [row["song_id"] for row in kept(player.path, "ethan")] == ["s-0", "new", "newer"]
    assert player.store.trim_history("ethan", 10) == 0


def test_the_guard_looks_again_sooner_once_many_starts_have_been_taken(player, monkeypatch):
    """A client gone wrong can't write without limit for a day: past HISTORY_TRIM_AFTER starts since the last look,
    the guard looks again - and counts per person, only the starts taken."""
    ethan = signed_in(player, "ethan")
    james = signed_in(player, "james")
    monkeypatch.setattr(rules, "HISTORY_KEPT_MAX", 3)
    monkeypatch.setattr(rules, "HISTORY_TRIM_AFTER", 4)
    ethan.post(HISTORY, json={"starts": [start(NOW - n, f"s-{n}") for n in range(5)]})
    assert len(kept(player.path, "ethan")) == 3
    #? 3 since the look (and a skipped one, which counts for nothing): not yet
    ethan.post(HISTORY, json={"starts": [start(NOW + n, f"n-{n}") for n in (1, 2, 3)] + [start(NOW, "")]})
    assert len(kept(player.path, "ethan")) == 6
    #? someone else's starts are theirs
    james.post(HISTORY, json={"starts": [start(NOW + n, f"j-{n}") for n in (1, 2)]})
    assert len(kept(player.path, "ethan")) == 6
    #? the 4th: looked at again, the oldest past the cap gone
    ethan.post(HISTORY, json={"starts": [start(NOW + 4, "n-4")]})
    assert [row["song_id"] for row in kept(player.path, "ethan")] == ["n-2", "n-3", "n-4"]
    #? ...and the count starts again from that look
    ethan.post(HISTORY, json={"starts": [start(NOW + 5, "n-5")]})
    assert len(kept(player.path, "ethan")) == 4
