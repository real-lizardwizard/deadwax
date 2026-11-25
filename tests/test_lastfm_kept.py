"""
Last.fm's answers, kept (2.1.36, notes/lastfm.md): src/lastfm_kept.py over store.py's lastfm_kept.

What this holds:
  - the standing by age: found 7 days fresh, to 30 answered at once and asked again behind, then asked first; "not
    known" 3 days; and whatever is kept answered when asking fails;
  - a failure never kept, "not known" kept as none;
  - one ask per key: two asks of one key, or two refreshes behind, reach Last.fm once - and a page that stops waiting
    doesn't stop the ask, whose answer is still kept;
  - the size: a row over 32 KB not kept, a trim dropping the answers used longest ago, reading a row using it;
  - a shape bumped never serving an old row;
  - emptied with no key: at start-up, and by the save that removes the key or reverts it to none.
"""

import asyncio
import json
import logging

import pytest
from fastapi.testclient import TestClient

from src import lastfm as lastfm_module
from src import lastfm_kept
from src.api.app import start
from src.config import Config
from src.lastfm import Answer, Limited, NotKnown, Refused, Unreachable
from src.lastfm_kept import (DAY, ROW_MAX_BYTES, TRIM_EVERY, Keeper, album_key, artist_key, at_start, standing,
                             track_key)
from src.store import JobStore

#? the kept rows' shape now (src/lastfm.py LASTFM_SHAPE): 2 since 2.1.43
SHAPE = lastfm_module.LASTFM_SHAPE

NOW = 2_000_000_000.0
TAME = "63aa26c3-d59b-4da4-84ac-716b54f1ef4d"
KEY = "5e17e1d0b5e17e1d0b5e17e1d0b5e1ab"
#? half a surrogate pair, alone: json.loads makes one of an escape Last.fm (or anyone) can send, and no UTF-8 holds it
LONE = chr(0xD800)


@pytest.fixture
def store(tmp_path):
    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()
    return store


@pytest.fixture
def keeper(monkeypatch):
    """A keeper on a fake clock, with a key: only an answer asked with the key still in use is kept."""
    monkeypatch.setattr(Config, "LASTFM_API_KEY", KEY)
    keeper = Keeper()
    keeper.clock = lambda: keeper.now
    keeper.now = NOW
    return keeper


class Asks:
    """Last.fm as an ask: what each call answers, in turn (the last again), and how many were made."""

    def __init__(self, *outcomes, gate: asyncio.Event | None = None):
        self.outcomes = list(outcomes)
        self.calls = 0
        self.gate = gate

    async def __call__(self):
        self.calls += 1
        if self.gate is not None:
            await self.gate.wait()
        return self.outcomes[min(self.calls, len(self.outcomes)) - 1]


async def until(condition, limit: float = 5.0) -> None:
    """Waits for `condition` - the store reads on a worker thread, so a few turns of the loop aren't enough."""
    loop = asyncio.get_running_loop()
    give_up = loop.time() + limit
    while not condition():
        assert loop.time() < give_up, "waited too long"
        await asyncio.sleep(0.002)


class Counting:
    """A store that counts the reads it has answered: once it has answered n, n asks have each joined or begun theirs
    (kept() goes from its read to the ask without waiting on anything)."""

    def __init__(self, store):
        self.store = store
        self.available = store.available
        self.read = 0

    async def lastfm_get(self, *args, **kwargs):
        row = await self.store.lastfm_get(*args, **kwargs)
        self.read += 1
        return row

    def __getattr__(self, name):
        return getattr(self.store, name)


def keep(store, key, body, fetched_at):
    asyncio.run(store.lastfm_put(key, None if body is None else json.dumps(body), fetched_at))


def rows(store):
    return asyncio.run(store.lastfm_kept_rows())


# ----- the standing --------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("found, days, stand", [
    (True, 0, "fresh"), (True, 6.9, "fresh"), (True, 7, "stale"), (True, 29.9, "stale"), (True, 30, "due"),
    (True, 400, "due"),
    (False, 0, "fresh"), (False, 2.9, "fresh"), (False, 3, "due"), (False, 10, "due"), (False, 40, "due"),
    #? a row from the clock's future is as fresh as one from now
    (True, -2, "fresh"),
])
def test_the_standing_by_age(found, days, stand):
    assert standing(found, NOW - days * DAY, NOW) == stand


# ----- asking and keeping --------------------------------------------------------------------------------------------

def test_an_answer_is_kept_and_answered_again_without_asking(store, keeper):
    asks = Asks(Answer({"listeners": 5}))
    key = artist_key("artist.getinfo", mbid=TAME)

    first = asyncio.run(keeper.kept(store, key, asks))
    keeper.now += 6 * DAY
    second = asyncio.run(keeper.kept(store, key, asks))

    assert first == second == Answer({"listeners": 5})
    assert asks.calls == 1
    [row] = rows(store)
    assert row["key"] == f"{SHAPE}|artist.getinfo|mbid|{TAME}" and json.loads(row["body"]) == {"listeners": 5}


def test_not_known_is_kept_as_none_for_3_days(store, keeper):
    asks = Asks(NotKnown("not found"), Answer({"listeners": 1}))
    key = artist_key("artist.getinfo", name="Nobody At All")

    assert asyncio.run(keeper.kept(store, key, asks)) == NotKnown("not found")
    keeper.now += 2 * DAY
    assert asyncio.run(keeper.kept(store, key, asks)) == NotKnown()
    assert asks.calls == 1
    assert rows(store)[0]["body"] is None

    keeper.now += 1 * DAY
    assert asyncio.run(keeper.kept(store, key, asks)) == Answer({"listeners": 1})
    assert asks.calls == 2


@pytest.mark.parametrize("failure", [Unreachable("HTTP 503"), Limited("error 29"), Refused(10, "Invalid API key", NOW)])
def test_a_failure_is_never_kept(store, keeper, failure):
    asks = Asks(failure)
    key = artist_key("artist.gettoptracks", mbid=TAME)

    assert asyncio.run(keeper.kept(store, key, asks)) == failure
    assert asyncio.run(keeper.kept(store, key, asks)) == failure

    assert asks.calls == 2
    assert rows(store) == []


def test_a_stale_answer_is_answered_at_once_and_asked_again_behind(store, keeper):
    key = artist_key("artist.getinfo", mbid=TAME)
    keep(store, key, {"listeners": 1}, NOW - 8 * DAY)

    async def go():
        gate = asyncio.Event()
        asks = Asks(Answer({"listeners": 2}), gate=gate)
        answered = await keeper.kept(store, key, asks)
        #? answered before Last.fm answers at all
        assert not gate.is_set()
        refreshing = keeper.asking[key]
        gate.set()
        await refreshing
        return answered, asks.calls

    answered, calls = asyncio.run(go())

    assert answered == Answer({"listeners": 1})
    assert calls == 1
    [row] = rows(store)
    assert json.loads(row["body"]) == {"listeners": 2} and row["fetched_at"] == NOW


def test_a_failed_refresh_behind_changes_nothing(store, keeper, caplog):
    caplog.set_level(logging.INFO)
    key = artist_key("artist.getinfo", mbid=TAME)
    keep(store, key, {"listeners": 1}, NOW - 8 * DAY)

    async def go():
        answered = await keeper.kept(store, key, Asks(Unreachable("HTTP 503")))
        await keeper.asking[key]
        await asyncio.sleep(0)
        return answered

    assert asyncio.run(go()) == Answer({"listeners": 1})
    [row] = rows(store)
    assert row["fetched_at"] == NOW - 8 * DAY
    assert "couldn't be refreshed" in caplog.text


def test_an_answer_over_30_days_is_asked_first_and_answered_anyway_when_asking_fails(store, keeper):
    key = artist_key("artist.getinfo", mbid=TAME)
    keep(store, key, {"listeners": 1}, NOW - 31 * DAY)
    asks = Asks(Unreachable("HTTP 503"), Answer({"listeners": 3}))

    assert asyncio.run(keeper.kept(store, key, asks)) == Answer({"listeners": 1})
    assert asks.calls == 1
    assert asyncio.run(keeper.kept(store, key, asks)) == Answer({"listeners": 3})
    assert asks.calls == 2


def test_a_kept_answer_is_answered_while_the_key_is_refused(store, keeper):
    key = artist_key("artist.getinfo", mbid=TAME)
    keep(store, key, {"listeners": 1}, NOW - 90 * DAY)

    assert asyncio.run(keeper.kept(store, key, Asks(Refused(10, "Invalid API key", NOW)))) == Answer({"listeners": 1})


def test_two_asks_of_one_key_reach_last_fm_once(store, keeper):
    key = artist_key("artist.gettoptracks", mbid=TAME)

    async def go():
        gate = asyncio.Event()
        asks = Asks(Answer({"top": [1]}), gate=gate)
        counting = Counting(store)
        first = asyncio.ensure_future(keeper.kept(counting, key, asks))
        second = asyncio.ensure_future(keeper.kept(counting, key, asks))
        await until(lambda: counting.read == 2)
        gate.set()
        return await first, await second, asks.calls

    first, second, calls = asyncio.run(go())

    assert first == second == Answer({"top": [1]})
    assert calls == 1


def test_two_refreshes_behind_of_one_key_reach_last_fm_once(store, keeper):
    key = artist_key("artist.gettoptracks", mbid=TAME)
    keep(store, key, {"top": [1]}, NOW - 10 * DAY)

    async def go():
        gate = asyncio.Event()
        asks = Asks(Answer({"top": [2]}), gate=gate)
        await keeper.kept(store, key, asks)
        await keeper.kept(store, key, asks)
        refreshing = keeper.asking[key]
        gate.set()
        await refreshing
        return asks.calls

    assert asyncio.run(go()) == 1


def test_an_ask_a_page_stopped_waiting_for_is_still_kept(store, keeper):
    key = artist_key("artist.getinfo", mbid=TAME)

    async def go():
        gate = asyncio.Event()
        asks = Asks(Answer({"listeners": 9}), gate=gate)
        page = asyncio.ensure_future(keeper.kept(store, key, asks))
        await until(lambda: key in keeper.asking)
        asking = keeper.asking[key]
        page.cancel()
        with pytest.raises(asyncio.CancelledError):
            await page
        gate.set()
        await asking

    asyncio.run(go())

    assert json.loads(rows(store)[0]["body"]) == {"listeners": 9}


def test_an_answer_over_32_kb_is_answered_but_not_kept(store, keeper):
    big = {"pad": "x" * ROW_MAX_BYTES}
    asks = Asks(Answer(big))
    key = artist_key("artist.gettoptracks", mbid=TAME)

    assert asyncio.run(keeper.kept(store, key, asks)) == Answer(big)
    assert rows(store) == []


def test_without_a_database_it_still_answers(keeper):
    unavailable = JobStore("/nonexistent/deadwax.db")
    asks = Asks(Answer({"listeners": 1}))

    assert asyncio.run(keeper.kept(unavailable, "1|artist.getinfo|name|x", asks)) == Answer({"listeners": 1})
    assert asyncio.run(keeper.kept(None, "1|artist.getinfo|name|x", asks)) == Answer({"listeners": 1})


def test_stop_cancels_every_ask_under_way(store, keeper):
    async def go():
        gate = asyncio.Event()
        waiting = asyncio.ensure_future(keeper.kept(store, "1|artist.getinfo|name|x", Asks(Answer({}), gate=gate)))
        await until(lambda: "1|artist.getinfo|name|x" in keeper.asking)
        asking = keeper.asking["1|artist.getinfo|name|x"]
        await keeper.stop()
        waiting.cancel()
        return asking

    assert asyncio.run(go()).cancelled()
    assert rows(store) == []


# ----- keeping never raises (after review) ----------------------------------------------------------------------------

def test_an_answer_with_a_lone_surrogate_is_kept_and_answered_again(store, keeper):
    asks = Asks(Answer({"name": f"Sigur R{LONE}s", "tags": [LONE]}))
    key = artist_key("artist.getinfo", mbid=TAME)

    first = asyncio.run(keeper.kept(store, key, asks))
    second = asyncio.run(keeper.kept(store, key, asks))

    assert first == second == Answer({"name": f"Sigur R{LONE}s", "tags": [LONE]})
    assert asks.calls == 1
    assert rows(store)[0]["body"].isascii()


def test_an_answer_deadwax_cannot_write_is_answered_not_kept_and_said(store, keeper, caplog):
    caplog.set_level(logging.INFO)
    unwritable = Answer({"listeners": object()})
    key = artist_key("artist.getinfo", mbid=TAME)

    assert asyncio.run(keeper.kept(store, key, Asks(unwritable))) == unwritable
    assert rows(store) == []
    assert f"Last.fm's answer for {key} couldn't be kept" in caplog.text


def test_a_key_utf_8_cannot_hold_is_answered_never_raised(store, keeper):
    """The keys fold a lone surrogate away; one that held it anyway is answered, and the store refuses it quietly."""
    assert LONE not in artist_key("artist.getinfo", name=f"Sigur R{LONE}s")
    key = f"1|artist.getinfo|name|sigur r{LONE}s"

    assert asyncio.run(keeper.kept(store, key, Asks(Answer({"listeners": 1})))) == Answer({"listeners": 1})
    assert asyncio.run(store.lastfm_put(key, "{}", NOW)) is False
    assert rows(store) == []


def test_a_refresh_behind_that_cannot_be_kept_is_said(store, keeper, caplog):
    caplog.set_level(logging.INFO)
    key = artist_key("artist.getinfo", mbid=TAME)
    keep(store, key, {"listeners": 1}, NOW - 8 * DAY)

    async def go():
        answered = await keeper.kept(store, key, Asks(Answer({"listeners": object()})))
        await until(lambda: key not in keeper.asking)
        await asyncio.sleep(0)
        return answered

    assert asyncio.run(go()) == Answer({"listeners": 1})
    assert json.loads(rows(store)[0]["body"]) == {"listeners": 1}
    assert f"Last.fm's answer for {key} couldn't be kept" in caplog.text


def test_a_refresh_behind_that_fails_is_said_once_however_many_visits_it_answered(store, keeper, caplog):
    caplog.set_level(logging.INFO)
    key = artist_key("artist.gettoptracks", mbid=TAME)
    keep(store, key, {"top": [1]}, NOW - 10 * DAY)

    async def go():
        gate = asyncio.Event()
        asks = Asks(Unreachable("HTTP 503"), gate=gate)
        answers = [await keeper.kept(store, key, asks) for _ in range(5)]
        gate.set()
        await until(lambda: key not in keeper.asking)
        await asyncio.sleep(0)
        return answers, asks.calls

    answers, calls = asyncio.run(go())

    assert answers == [Answer({"top": [1]})] * 5 and calls == 1
    assert [r.getMessage() for r in caplog.records].count(
        f"Last.fm's kept answer for {key} couldn't be refreshed (Unreachable): it's answered as it is") == 1


# ----- an answer to a key no longer in use (after review) ------------------------------------------------------------

@pytest.mark.parametrize("now_key", [None, "0123456789abcdef0123456789abcdef"], ids=["removed", "replaced"])
def test_an_answer_that_comes_after_the_key_changed_is_answered_not_kept(store, keeper, monkeypatch, now_key):
    key = artist_key("artist.getinfo", mbid=TAME)

    async def go():
        gate = asyncio.Event()
        page = asyncio.ensure_future(keeper.kept(store, key, Asks(Answer({"listeners": 9}), gate=gate)))
        await until(lambda: key in keeper.asking)
        #? the save: the key changed, and (removed) the table emptied - before Last.fm answers
        monkeypatch.setattr(Config, "LASTFM_API_KEY", now_key)
        await store.lastfm_clear()
        gate.set()
        return await page

    assert asyncio.run(go()) == Answer({"listeners": 9})
    assert rows(store) == []


def test_a_key_removed_while_an_answer_is_written_leaves_nothing_kept(store, keeper, monkeypatch):
    """The save's emptying and the keeper's write each run on a thread of their own: whichever lands last, the key
    removed means the table ends empty."""
    key = artist_key("artist.getinfo", mbid=TAME)

    class SaveDuringTheWrite(Counting):
        async def lastfm_put(self, *args, **kwargs):
            monkeypatch.setattr(Config, "LASTFM_API_KEY", None)
            await self.store.lastfm_clear()
            return await self.store.lastfm_put(*args, **kwargs)

    assert asyncio.run(keeper.kept(SaveDuringTheWrite(store), key, Asks(Answer({"listeners": 9})))) == Answer(
        {"listeners": 9})
    assert rows(store) == []


# ----- the keys ------------------------------------------------------------------------------------------------------

def test_the_keys():
    assert artist_key("artist.getinfo", mbid=TAME.upper()) == f"{SHAPE}|artist.getinfo|mbid|{TAME}"
    assert artist_key("artist.getinfo", name="The Beatles") == f"{SHAPE}|artist.getinfo|name|beatles"
    assert album_key("album.getinfo", "Portishead", "Dummy") == f"{SHAPE}|album.getinfo|name|portishead|dummy"
    assert (track_key("track.getsimilar", "Tame Impala", "Let It Happen - 2015 Remaster")
            == f"{SHAPE}|track.getsimilar|name|tame impala|let it happen")


def test_a_shape_bumped_never_serves_an_old_row(store, keeper, monkeypatch):
    keep(store, artist_key("artist.getinfo", mbid=TAME), {"listeners": 1}, NOW)
    monkeypatch.setattr(lastfm_module, "LASTFM_SHAPE", SHAPE + 1)
    asks = Asks(Answer({"listeners": 2, "shape": SHAPE + 1}))

    assert asyncio.run(keeper.kept(store, artist_key("artist.getinfo", mbid=TAME), asks)) == Answer(
        {"listeners": 2, "shape": SHAPE + 1})
    assert asks.calls == 1


# ----- the size ------------------------------------------------------------------------------------------------------

def test_a_trim_drops_the_answers_used_longest_ago(store):
    for n in range(10):
        asyncio.run(store.lastfm_put(f"1|m|name|{n}", "x" * 1000, NOW + n))
    #? the oldest, read now - so used most recently of all
    asyncio.run(store.lastfm_get("1|m|name|0", NOW + 7200))

    dropped = asyncio.run(store.lastfm_trim(most=8000, down_to=6000))

    left = [row["key"] for row in rows(store)]
    assert dropped == 5
    assert left == [f"1|m|name|{n}" for n in (6, 7, 8, 9, 0)]
    assert sum(row["size"] for row in rows(store)) <= 6000


def test_a_trim_under_the_cap_drops_nothing(store):
    asyncio.run(store.lastfm_put("1|m|name|a", "x" * 100, NOW))

    assert asyncio.run(store.lastfm_trim(most=1000, down_to=500)) == 0
    assert len(rows(store)) == 1


def test_reading_a_row_uses_it_at_most_hourly(store):
    asyncio.run(store.lastfm_put("1|m|name|a", "{}", NOW))

    asyncio.run(store.lastfm_get("1|m|name|a", NOW + 1800))
    assert rows(store)[0]["used_at"] == NOW
    asyncio.run(store.lastfm_get("1|m|name|a", NOW + 3600))
    assert rows(store)[0]["used_at"] == NOW + 3600


def test_the_table_is_trimmed_once_every_100_answers_kept(store, keeper, monkeypatch):
    monkeypatch.setattr(lastfm_kept, "LASTFM_KEPT_BYTES", 1500)
    monkeypatch.setattr(lastfm_kept, "TRIM_TO_BYTES", 1000)

    async def go():
        for n in range(TRIM_EVERY - 1):
            keeper.now += 1
            await keeper.kept(store, f"1|m|name|{n:03}", Asks(Answer({"n": n})))
        before = len(await store.lastfm_kept_rows())
        keeper.now += 1
        await keeper.kept(store, "1|m|name|last", Asks(Answer({"n": "last"})))
        return before, await store.lastfm_kept_rows()

    before, after = asyncio.run(go())

    assert before == TRIM_EVERY - 1
    assert sum(row["size"] for row in after) <= 1000
    assert "1|m|name|last" in [row["key"] for row in after]
    assert "1|m|name|000" not in [row["key"] for row in after]


# ----- emptied with no key -------------------------------------------------------------------------------------------

def test_a_start_with_no_key_empties_the_table(store):
    keep(store, "1|artist.getinfo|name|a", {}, NOW)

    asyncio.run(at_start(store, key_set=False))

    assert rows(store) == []


def test_a_start_trims_the_table_past_its_cap(store, monkeypatch):
    """The trim every 100 answers counts in memory, and deadwax restarts with every update: so a start trims too."""
    monkeypatch.setattr(lastfm_kept, "LASTFM_KEPT_BYTES", 1500)
    monkeypatch.setattr(lastfm_kept, "TRIM_TO_BYTES", 1000)
    for n in range(100):
        keep(store, f"{SHAPE}|m|name|{n:03}", {"n": n}, NOW + n)
    assert sum(row["size"] for row in rows(store)) > 1500

    asyncio.run(at_start(store, key_set=True))

    kept = [row["key"] for row in rows(store)]
    assert sum(row["size"] for row in rows(store)) <= 1000
    assert f"{SHAPE}|m|name|099" in kept and f"{SHAPE}|m|name|000" not in kept


def test_a_start_with_a_key_drops_only_older_shapes(store):
    keep(store, f"{SHAPE}|artist.getinfo|name|a", {}, NOW)
    keep(store, f"{SHAPE - 1}|artist.getinfo|name|a", {}, NOW)
    keep(store, "0|artist.getinfo|name|a", {}, NOW)
    #? a shape that only begins with this one's digits
    keep(store, f"{SHAPE}{SHAPE}|artist.getinfo|name|a", {}, NOW)

    asyncio.run(at_start(store, key_set=True))

    assert [row["key"] for row in rows(store)] == [f"{SHAPE}|artist.getinfo|name|a"]


@pytest.fixture
def app(store, monkeypatch):
    monkeypatch.setattr(Config, "LASTFM_API_KEY", "0123456789abcdef0123456789abcdef")
    monkeypatch.setattr(Config, "OVERRIDDEN", set())
    monkeypatch.setattr(Config, "ENV_VALUES", {})
    application = start()
    application.state.store = store
    keep(store, "1|artist.getinfo|name|a", {"listeners": 1}, NOW)
    return TestClient(application)


def save(app, value):
    return app.put("/deadwax/settings", json=[{"key": "LASTFM_API_KEY", "value": value}])


def test_saving_no_key_empties_the_table(app, store):
    assert save(app, "").status_code == 200

    assert rows(store) == []


def test_reverting_to_an_environment_with_no_key_empties_the_table(app, store, monkeypatch):
    assert save(app, "fedcba9876543210fedcba9876543210").status_code == 200
    assert len(rows(store)) == 1
    #? the environment held none: what it would revert to
    Config.ENV_VALUES["LASTFM_API_KEY"] = None

    assert save(app, None).status_code == 200

    assert Config.lastfm_key() is None
    assert rows(store) == []


def test_saving_another_key_keeps_what_is_kept(app, store):
    assert save(app, "fedcba9876543210fedcba9876543210").status_code == 200

    assert len(rows(store)) == 1
