"""
MusicBrainz's answers kept on disk (2.0.0-player.54) - src/musicbrainz_cache.py under ResponseCache.

James asked for it (2026-10-15): the first search of an artist asks MusicBrainz, and the next is instant -
after the hour in memory, after a restart. Every MusicBrainz here is a fake transport that counts what
leaves the process; MusicBrainz itself is never asked.

What it pins:

  - a miss asks once and saves; a restart (a new client, a new memory) answers from the file with nothing
    asked; a saved answer round-trips byte for byte as JSON;
  - FAILURES ARE NEVER SAVED - a 403, a 400, an overloaded 503, a 500, a network error, an answer that
    isn't JSON - on disk exactly as not in memory (a bad minute must not become a bad month);
  - the age rule: a search old after 7 days, a lookup after 30; an old answer answered AT ONCE, one refresh
    queued behind it however often it is used, the saved answer replaced only on success, a failed refresh
    keeping it and dropping the rest - but a 400 or 404 (MusicBrainz answering about that one question)
    dropping only itself; a refresh never ahead of a question somebody is waiting for - one far slower than
    the quiet, and one still reading the disk, included (`asking`, back down after a question called off);
    at most one refresh in the limiter's
    window, so three questions asked together after it all go at once; a refresh's failure saying nothing
    in the event log, closing its own connection and never a question's (nor the reverse); a refresher
    whose queue is emptied while it waits ending quietly;
  - a paged browse (a discography, a group's pressings) as ONE answer: its pages under one stamp, read whole
    from the caches or asked again whole, refreshed whole and saved only when every page came, never put
    together from pages of different ages; an item on two pages listed once;
  - the size bound: the answers used longest ago dropped first, the file kept under its budget and trimmed
    back under 90% of it (so not on every answer), an answer bigger than 90% of the budget not kept; 0 is
    off - nothing read or written;
  - a corrupt file set aside (its journal with it) and a new one started - by real use, never by the
    settings' look at it, and never a file of any other name; a database that isn't the saved answers left
    alone; the job database never the file; a file of another shape emptied and made afresh; one whose
    making was cut short (a full disk, a SIGKILL) made afresh; a failure mid-transaction (a trim refused
    by another process's lock) rolled back, the answers after it saved;
  - the path ALWAYS a folder (James's addendum), made when missing, shareable with the player's cache; a
    path naming a file refused by the settings and never touched; one that can't be made said on its row
    from the start, for as long as it lasts; the example compose file and .env.example naming both
    settings; closing writes what is queued, and the lifespan's order;
  - the default file beside DB_PATH - the legacy jimbrainz.db's folder too;
  - a slow disk given up for MusicBrainz; the disk only ever touched on its own thread;
  - the connection check (ping) never answered from the file;
  - which keys mean the same question: only a query's runs of whitespace, never its case;
  - Clear (on disk and in memory), the size the settings show, the two settings and their refusals;
  - no MusicBrainz request bypasses request_with_retries.
"""

import ast
import asyncio
import json
import os
import sqlite3
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import httpx  # noqa: E402
import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from src import musicbrainz_cache  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.musicbrainz_endpoint import MusicBrainzClient, RateLimit, ResponseCache, same_question  # noqa: E402
from src.config import (Config, default_db_path, is_the_database, musicbrainz_cache_path,  # noqa: E402
                        parse_musicbrainz_cache_mb)
from src.musicbrainz_cache import (LOOKUP_FRESH_SECONDS, SEARCH_FRESH_SECONDS, SavedAnswers,  # noqa: E402
                                   is_stale, pack, unpack)
from src.routes.settings import _validate  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
DAY = 24 * 3600
SEARCH = ("release-group/", {"query": "Portishead", "fmt": "json", "limit": 12})
LOOKUP = ("artist/8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11", {"inc": "aliases", "fmt": "json"})
DUMMY = {"release-groups": [{"id": "48140466-cff6-3222-bd55-63c27e43190d", "title": "Dummy", "score": 100}],
         "count": 1}


class Clock:
    """Wall time as the saved answers read it, moved by hand - optionally a step on at every reading."""

    def __init__(self, now: float = 1_760_000_000.0, step: float = 0.0):
        self.now = now
        self.step = step

    def __call__(self) -> float:
        self.now += self.step
        return self.now


class Answer:
    def __init__(self, payload=None, status_code=200, not_json=False):
        self.payload = payload if payload is not None else {}
        self.status_code = status_code
        self.not_json = not_json
        self.text = "fake"

    def raise_for_status(self):
        if self.status_code >= 400:
            raise httpx.HTTPStatusError("refused", request=None, response=self)  # type: ignore[arg-type]

    def json(self):
        if self.not_json:
            raise ValueError("not JSON")
        return self.payload


class MusicBrainz:
    """A fake connection: answers by endpoint (or one answer for all), every request kept, in `log` too -
    with `delay`, a slow MusicBrainz, its answering logged as well."""

    def __init__(self, answers=None, error=None, name="question", log=None, delay=0.0):
        self.answers = answers if answers is not None else {}
        self.error = error
        self.name = name
        self.log = log if log is not None else []
        self.delay = delay
        self.calls = []

    async def get(self, endpoint, params=None):
        self.calls.append((endpoint, dict(params or {})))
        self.log.append((self.name, endpoint))
        if self.delay:
            await asyncio.sleep(self.delay)
            self.log.append((f"{self.name} answered", endpoint))
        if self.error is not None:
            raise self.error
        answer = self.answers.get(endpoint) if isinstance(self.answers, dict) and endpoint in self.answers else self.answers
        return answer if isinstance(answer, Answer) else Answer(answer)


def connect(client, question, refresh=None):
    """Point the client's two connections at fakes: a question's, and the refreshes' own."""
    refresh = refresh if refresh is not None else MusicBrainz(name="refresh", log=question.log)

    async def get_client():
        return question

    async def get_refresh_client():
        return refresh

    client.get_client = get_client  # type: ignore[method-assign]
    client.get_refresh_client = get_refresh_client  # type: ignore[method-assign]
    return question, refresh


@pytest.fixture
def instant(monkeypatch):
    """The retry back-offs patched out - these tests are about what is saved, not how long it waits."""
    real_sleep = asyncio.sleep

    async def no_wait(delay=0, *args, **kwargs):
        await real_sleep(0)

    monkeypatch.setattr(asyncio, "sleep", no_wait)


@pytest.fixture
def made(tmp_path, monkeypatch):
    """Saved answers in this test's own folder (closed after), and a client whose memory sits over them."""
    opened = []
    #? a short window: a refresh waits for a whole window with nothing asked (_refresh_saved), and these
    #? tests are about what is saved, not how long the real five seconds take
    limiter = RateLimit()
    limiter.time_window = 0.1
    monkeypatch.setattr(MusicBrainzClient, "rate_limit", limiter)

    def answers(path=None, max_bytes=8 << 20, clock=None) -> SavedAnswers:
        saved = SavedAnswers(str(path or tmp_path / "musicbrainz-cache.db"), max_bytes=max_bytes, clock=clock or Clock())
        opened.append(saved)
        return saved

    def client(saved: SavedAnswers | None) -> MusicBrainzClient:
        #? a new memory every time: "a restart" is a new client over the same file
        monkeypatch.setattr(MusicBrainzClient, "cache", ResponseCache(ttl_seconds=60, max_entries=16, disk=saved))
        made_client = MusicBrainzClient()
        made_client.REFRESH_QUIET_SECONDS = 0.05
        made_client.REFRESH_POLL_SECONDS = 0.01
        return made_client

    yield answers, client
    for saved in opened:
        asyncio.run(saved.close())


def ask(client, question=SEARCH, **options):
    async def go():
        answer = await client.request_with_retries(*question, **options)
        if client.cache.disk is not None:
            await client.cache.disk.flush()
        return answer

    return asyncio.run(go())


def saved_rows(path) -> list[tuple]:
    if not os.path.exists(path):
        return []
    with sqlite3.connect(path) as connection:
        return connection.execute("SELECT key, fetched_at, used_at FROM answers ORDER BY used_at").fetchall()


# ---------------------------------------------------------------- a miss, a restart, the same JSON

def test_a_miss_asks_once_and_saves_the_answer(made):
    answers, client = made
    saved = answers()
    first = client(saved)
    question, _ = connect(first, MusicBrainz(DUMMY))

    assert ask(first) == DUMMY
    assert len(question.calls) == 1
    [(key, fetched_at, used_at)] = saved_rows(saved.path())
    assert key == ResponseCache.disk_key(*SEARCH)
    assert fetched_at == used_at == saved._clock.now


def test_a_restart_answers_from_the_file_with_nothing_asked(made, caplog):
    """The point of it: deadwax restarted (every image update) - a new client, an empty memory - and the
    search is answered from the file, nothing leaving the process. The log says so."""
    answers, client = made
    before = client(answers())
    connect(before, MusicBrainz(DUMMY))
    ask(before)
    asyncio.run(before.cache.disk.close())

    after = client(answers())
    question, refresh = connect(after, MusicBrainz(error=AssertionError("MusicBrainz was asked")))
    with caplog.at_level("INFO"):
        answer = ask(after)

    assert answer == DUMMY
    assert question.calls == [] and refresh.calls == []
    assert "from the saved answers on disk, nothing asked" in caplog.text
    #? ...and put back in memory: the next is the hour's, not the file's
    assert after.cache.get(*SEARCH) == DUMMY


def test_a_saved_answer_round_trips_byte_for_byte_as_json(made):
    """Every answer the app draws is the one MusicBrainz gave: the order of keys, unicode, numbers, nulls."""
    payload = {"z-first": 1, "title": "Björk ‐ Homogenic “Live” 東京", "score": 100, "length": 254.5, "rating": None,
               "nested": [{"b": True, "a": [1, 2.25, "x"]}], "empty": {}, "count": 12345678901234}
    answers, client = made
    before = client(answers())
    connect(before, MusicBrainz(payload))
    original = ask(before)
    asyncio.run(before.cache.disk.close())

    after = client(answers())
    connect(after, MusicBrainz(error=AssertionError("asked")))
    again = ask(after)

    assert json.dumps(again) == json.dumps(original) == json.dumps(payload)
    assert json.dumps(again, ensure_ascii=False) == json.dumps(payload, ensure_ascii=False)
    assert list(again) == list(payload), "the keys in MusicBrainz's order"
    assert unpack(pack(payload)) == payload


# ---------------------------------------------------------------- failures are never saved

@pytest.mark.parametrize("answer", [
    Answer(status_code=403), Answer(status_code=400), Answer(status_code=503), Answer(status_code=500),
    Answer(status_code=404), Answer({"anything": 1}, not_json=True),
], ids=["403", "400", "503", "500", "404", "not-json"])
def test_a_failure_is_never_saved(made, instant, answer):
    answers, client = made
    saved = answers()
    first = client(saved)
    connect(first, MusicBrainz(answer))

    result = ask(first)

    assert result["status"] == "failed"
    assert saved_rows(saved.path()) == []
    assert first.cache.entries == {}, "nor in memory, as ever"


def test_a_network_failure_is_never_saved_and_the_next_success_is(made, instant):
    answers, client = made
    saved = answers()
    first = client(saved)
    question, _ = connect(first, MusicBrainz(error=httpx.ConnectError("down")))

    assert ask(first)["status"] == "failed"
    assert saved_rows(saved.path()) == []

    question.error = None
    question.answers = DUMMY
    assert ask(first) == DUMMY
    assert len(saved_rows(saved.path())) == 1


# ---------------------------------------------------------------- how old is old

def test_a_search_is_fresh_for_7_days_and_a_lookup_for_30():
    assert SEARCH_FRESH_SECONDS == 7 * DAY and LOOKUP_FRESH_SECONDS == 30 * DAY
    now = 1_760_000_000.0
    assert not is_stale(SEARCH[1], now - 7 * DAY + 60, now)
    assert is_stale(SEARCH[1], now - 7 * DAY - 60, now)
    assert not is_stale(LOOKUP[1], now - 29 * DAY, now)
    assert is_stale(LOOKUP[1], now - 31 * DAY, now)
    #? a browse - a release group's pressings, a discography - is a lookup
    assert not is_stale({"release-group": "g", "inc": "media", "offset": 0}, now - 20 * DAY, now)


def test_a_fresh_saved_answer_queues_no_refresh(made):
    answers, client = made
    clock = Clock()
    before = client(answers(clock=clock))
    connect(before, MusicBrainz(DUMMY))
    ask(before)

    clock.now += 6 * DAY
    after = client(before.cache.disk)
    connect(after, MusicBrainz(error=AssertionError("asked")))
    assert ask(after) == DUMMY
    assert not after.refreshes and after.refresher is None


def test_an_old_answer_is_answered_at_once_and_refreshed_once_behind_it(made):
    """Eight days on, the search is answered straight from the file - not after MusicBrainz - however often
    it is asked; ONE refresh goes behind it, on the refreshes' own connection, and its answer replaces the
    saved one (and the one in memory), so the next time is current."""
    answers, client = made
    clock = Clock()
    saved = answers(clock=clock)
    before = client(saved)
    connect(before, MusicBrainz(DUMMY))
    ask(before)
    first_fetched = saved_rows(saved.path())[0][1]

    clock.now += 8 * DAY
    after = client(saved)
    newer = {"release-groups": DUMMY["release-groups"] + [{"id": "new", "title": "Third"}], "count": 2}
    question, refresh = connect(after, MusicBrainz(error=AssertionError("a question was asked")),
                                MusicBrainz(newer, name="refresh"))

    async def go():
        began = time.monotonic()
        answered = [await after.request_with_retries(*SEARCH) for _ in range(3)]
        took = time.monotonic() - began
        queued = list(after.refreshes)
        asked_meanwhile = len(refresh.calls)
        await asyncio.wait_for(after.refresher, 5)
        await saved.flush()
        return answered, took, queued, asked_meanwhile

    answered, took, queued, asked_meanwhile = asyncio.run(go())

    assert answered == [DUMMY, DUMMY, DUMMY], "the old answer, at once"
    assert took < 0.5 and asked_meanwhile == 0, "nothing waited for MusicBrainz"
    assert queued == [ResponseCache.key(*SEARCH)], "one refresh, however often it was used"
    assert question.calls == [] and len(refresh.calls) == 1
    assert asyncio.run(saved.get(ResponseCache.disk_key(*SEARCH)))[0] == newer
    assert saved_rows(saved.path())[0][1] > first_fetched, "fetched now"
    assert after.cache.get(*SEARCH) == newer


def test_a_failed_refresh_keeps_the_saved_answer_and_drops_the_rest(made, instant):
    answers, client = made
    clock = Clock()
    saved = answers(clock=clock)
    before = client(saved)
    other = ("release-group/", {"query": "Massive Attack", "fmt": "json", "limit": 12})
    connect(before, MusicBrainz(DUMMY))
    ask(before)
    ask(before, other)
    rows = saved_rows(saved.path())

    clock.now += 40 * DAY
    after = client(saved)
    question, refresh = connect(after, MusicBrainz(error=AssertionError("asked")),
                                MusicBrainz(error=httpx.ConnectError("MusicBrainz is away"), name="refresh"))

    async def go():
        await after.request_with_retries(*SEARCH)
        await after.request_with_retries(*other)
        assert len(after.refreshes) == 2
        await asyncio.wait_for(after.refresher, 5)
        await saved.flush()

    asyncio.run(go())

    assert len(refresh.calls) == 1, "asked once - not retried, and the rest dropped"
    assert not after.refreshes
    assert sorted((key, fetched) for key, fetched, _ in saved_rows(saved.path())) == \
        sorted((key, fetched) for key, fetched, _ in rows), "the saved answers stand, as they were fetched"
    assert asyncio.run(saved.get(ResponseCache.disk_key(*SEARCH)))[0] == DUMMY


def test_a_refresh_never_goes_ahead_of_a_question_somebody_is_waiting_for(made):
    """A question is on its way to a slow MusicBrainz when an old answer is read and its refresh queued:
    the refresh waits until that question has its answer, and then for MusicBrainz to be quiet - never
    beside it, on its own connection, while somebody waits."""
    answers, client = made
    clock = Clock()
    saved = answers(clock=clock)
    before = client(saved)
    connect(before, MusicBrainz(DUMMY))
    ask(before)

    clock.now += 8 * DAY
    after = client(saved)
    #? longer than the question takes: the quiet is counted from the last request asked
    after.REFRESH_QUIET_SECONDS = 0.5
    log = []
    question, refresh = connect(after, MusicBrainz({"artist/x": {"id": "x"}}, log=log, delay=0.3),
                                MusicBrainz(DUMMY, name="refresh", log=log))
    times = {}

    async def go():
        waiting = asyncio.create_task(after.request_with_retries("artist/x", {"inc": "aliases"}))
        while not log:
            await asyncio.sleep(0.005)
        times["asked"] = time.monotonic()
        await after.request_with_retries(*SEARCH)           # old: answered at once, and a refresh queued
        assert after.refreshes, "queued"
        await waiting
        await asyncio.wait_for(after.refresher, 5)
        times["refreshed"] = time.monotonic()

    asyncio.run(go())

    assert log == [("question", "artist/x"), ("question answered", "artist/x"), ("refresh", "release-group/")]
    assert times["refreshed"] - times["asked"] >= after.REFRESH_QUIET_SECONDS - 0.05, \
        "and then waited for MusicBrainz to be quiet"


def test_a_refresh_waits_for_room_in_the_rate_limiter(made):
    answers, client = made
    limiter = RateLimit()
    limiter.time_window = 0.4
    c = client(answers())
    c.rate_limit = limiter
    c.REFRESH_QUIET_SECONDS = 0.0

    async def go():
        now = time.monotonic()
        for _ in range(limiter.max_requests):
            limiter.request_times.append(now)
        assert not limiter.quiet(0.0), "full: no refresh may take a turn"
        await asyncio.sleep(0.45)
        assert limiter.quiet(0.0), "room again"
        limiter.request_times.append(time.monotonic())
        assert not limiter.quiet(0.2), "...but not within the quiet of the last request"

    asyncio.run(go())


def test_a_refresh_is_queued_once_and_the_queue_is_bounded(made):
    answers, client = made
    c = client(answers())
    c.REFRESH_QUEUE_MAX = 2

    async def go():
        #? no MusicBrainz: the refresher is called off at once, the queue is what's looked at
        c.rate_limit = RateLimit()
        c.asking = 1
        for n in (1, 1, 2, 3):
            c._queue_refresh("release-group/", {"query": f"q{n}"})
        queued = [params["query"] for _, params in c.refreshes.values()]
        await c.stop_refreshing()
        return queued

    assert asyncio.run(go()) == ["q1", "q2"]


class Timed(MusicBrainz):
    """A fake connection that also keeps WHEN each request reached it (time.monotonic)."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.times = []

    async def get(self, endpoint, params=None):
        self.times.append(time.monotonic())
        return await super().get(endpoint, params)


def test_a_refresh_leaves_three_turns_for_the_questions_after_it(made):
    """Review: refreshes paced at two seconds' quiet filled the limiter's window (four turns in five seconds)
    three at a time, so a page's burst of questions after one waited seconds it never had before. A refresh
    now waits for a WHOLE window with nothing asked: at most one is ever in it, and three questions asked
    together right after it all go at once."""
    answers, client = made
    c = client(None)
    limiter = RateLimit()
    limiter.time_window = 0.6
    c.rate_limit = limiter
    c.REFRESH_QUIET_SECONDS = 0.05
    question, refresh = connect(c, Timed({}), Timed({}, name="refresh"))

    async def go():
        for n in range(4):
            c._queue_refresh(f"artist/r{n}", {})
        while not refresh.calls:
            await asyncio.sleep(0.005)
        #? paced by the quiet alone, two more refreshes would have gone by now, filling the window
        await asyncio.sleep(0.2)
        refreshed_before = len(refresh.calls)
        began = time.monotonic()
        await asyncio.gather(*(c.request_with_retries(f"artist/q{n}", {}) for n in range(3)))
        await c.stop_refreshing()
        return refreshed_before, [round(at - began, 2) for at in question.times]

    refreshed_before, started = asyncio.run(go())
    assert refreshed_before == 1, "one refresh in the window, the next waiting for it to empty"
    assert len(started) == 3 and max(started) < 0.1, f"all three at once, none held by the limiter ({started})"


@pytest.mark.parametrize("status, goes_on", [(404, True), (400, True), (503, False), (500, False), (429, False)])
def test_a_refresh_that_fails_for_its_own_question_drops_only_itself(made, instant, status, goes_on):
    """Review: any failed refresh dropped every one waiting behind it, as if MusicBrainz were away - but a
    404 (something since deleted from MusicBrainz) or a 400 is MusicBrainz ANSWERING, about that one
    question: it alone is dropped, its saved answer kept, and the rest go on. Anything else (a 503, a 5xx,
    a 429, no connection) is MusicBrainz away, and drops the rest as before."""
    answers, client = made
    clock = Clock()
    saved = answers(clock=clock)
    before = client(saved)
    lookups = [(f"artist/{n}", {"inc": "aliases"}) for n in range(1, 4)]
    connect(before, MusicBrainz({endpoint: {"id": endpoint, "v": "old"} for endpoint, _ in lookups}))
    for lookup in lookups:
        ask(before, lookup)

    clock.now += 31 * DAY
    after = client(saved)
    fresh = {endpoint: {"id": endpoint, "v": "new"} for endpoint, _ in lookups}
    fresh["artist/1"] = Answer(status_code=status)
    question, refresh = connect(after, MusicBrainz(error=AssertionError("asked")), MusicBrainz(fresh, name="refresh"))

    async def go():
        for lookup in lookups:
            await after.request_with_retries(*lookup)
        assert len(after.refreshes) == 3
        await asyncio.wait_for(after.refresher, 10)
        await saved.flush()

    asyncio.run(go())

    asked = [endpoint for endpoint, _ in refresh.calls]
    kept = {endpoint: asyncio.run(saved.get(ResponseCache.disk_key(endpoint, params)))[0]["v"] for endpoint, params in lookups}
    if goes_on:
        assert asked == ["artist/1", "artist/2", "artist/3"], "the rest went on"
        assert kept == {"artist/1": "old", "artist/2": "new", "artist/3": "new"}, "its own saved answer kept"
    else:
        assert asked == ["artist/1"], "MusicBrainz away: the rest dropped"
        assert kept == {"artist/1": "old", "artist/2": "old", "artist/3": "old"}
    assert not after.refreshes


def test_a_refresh_waits_for_a_slow_question_however_quiet_it_has_been(made):
    """Review: the test above held the refresh back with the quiet alone (longer than its question took), so
    breaking `asking` left the suite green. Here the question takes far longer than the quiet and the
    limiter's window: only `asking` keeps the refresh from going beside it while somebody waits."""
    answers, client = made
    clock = Clock()
    saved = answers(clock=clock)
    before = client(saved)
    connect(before, MusicBrainz(DUMMY))
    ask(before)

    clock.now += 8 * DAY
    after = client(saved)
    limiter = RateLimit()
    limiter.time_window = 0.05
    after.rate_limit = limiter
    after.REFRESH_QUIET_SECONDS = 0.05
    log = []
    connect(after, MusicBrainz({"artist/x": {"id": "x"}}, log=log, delay=0.4), MusicBrainz(DUMMY, name="refresh", log=log))

    async def go():
        waiting = asyncio.create_task(after.request_with_retries("artist/x", {"inc": "aliases"}))
        while not log:
            await asyncio.sleep(0.005)
        await after.request_with_retries(*SEARCH)           # old: answered at once, and a refresh queued
        await waiting
        await asyncio.wait_for(after.refresher, 5)

    asyncio.run(go())
    assert log == [("question", "artist/x"), ("question answered", "artist/x"), ("refresh", "release-group/")]


def test_a_refresh_waits_for_a_question_still_reading_the_disk(made):
    """`asking` counts from the memory miss on - the disk read included: a question whose saved answer is
    slow to read (and then isn't there) may still need MusicBrainz, and a refresh mustn't take the turn
    first."""
    answers, client = made
    clock = Clock()
    saved = answers(clock=clock)
    before = client(saved)
    connect(before, MusicBrainz(DUMMY))
    ask(before)

    clock.now += 8 * DAY
    after = client(saved)
    limiter = RateLimit()
    limiter.time_window = 0.3
    after.rate_limit = limiter
    after.REFRESH_QUIET_SECONDS = 0.05
    log = []
    connect(after, MusicBrainz({"artist/y": {"id": "y"}}, log=log), MusicBrainz(DUMMY, name="refresh", log=log))
    slow_key = ResponseCache.disk_key("artist/y", {})
    real_get = saved._get

    def slow_get(key):
        if key == slow_key:
            time.sleep(0.6)                                 # inside READ_TIMEOUT_SECONDS: waited for
        return real_get(key)

    saved._get = slow_get  # type: ignore[method-assign]

    async def go():
        limiter.request_times.append(time.monotonic())      # MusicBrainz asked just now: no refresh for a window
        await after.request_with_retries(*SEARCH)           # old: answered at once, and a refresh queued
        await asyncio.create_task(after.request_with_retries("artist/y", {}))
        await asyncio.wait_for(after.refresher, 5)

    asyncio.run(go())
    assert log == [("question", "artist/y"), ("refresh", "release-group/")]


@pytest.mark.parametrize("where", ["MusicBrainz", "the disk"])
def test_a_question_called_off_takes_itself_off_the_count(made, monkeypatch, where):
    """Review: a question called off - the former names' 8 s budget runs out on a slow MusicBrainz
    (routes/download.py), or a browser goes away - must take itself off `asking`, or no refresh would ever
    go again until a restart. Called off while MusicBrainz is slow to answer, and while the disk is slow."""
    answers, client = made
    saved = answers()
    c = client(saved)
    question, refresh = connect(c, MusicBrainz(DUMMY, delay=2.0 if where == "MusicBrainz" else 0.0),
                                MusicBrainz({"id": "r"}, name="refresh"))
    if where == "the disk":
        real_get = saved._get

        def slow_get(key):
            time.sleep(0.4)                                 # inside READ_TIMEOUT_SECONDS: still being read
            return real_get(key)

        monkeypatch.setattr(saved, "_get", slow_get)

    async def go():
        with pytest.raises((asyncio.TimeoutError, TimeoutError)):
            await asyncio.wait_for(c.request_with_retries(*SEARCH), 0.1)
        counted = c.asking
        c._queue_refresh("artist/r", {})
        await asyncio.wait_for(c.refresher, 5)
        return counted

    assert asyncio.run(go()) == 0
    assert [endpoint for endpoint, _ in refresh.calls] == ["artist/r"], "and a refresh goes after it"


@pytest.mark.parametrize("failure", [Answer(status_code=403), Answer(status_code=400), Answer(status_code=503),
                                     httpx.ConnectError("away")], ids=["403", "400", "503", "network"])
def test_a_failed_refresh_says_nothing_in_the_event_log(made, instant, caplog, failure):
    """Nobody is waiting for a refresh, so nothing of it reaches the page's event log (`frontend`) - where
    the same 403 or 400 from a question somebody asked does."""
    answers, client = made
    c = client(None)
    error = failure if isinstance(failure, Exception) else None
    refresh = MusicBrainz(None if error else failure, error=error, name="refresh")
    connect(c, MusicBrainz(Answer(status_code=403)), refresh)

    async def go():
        c._queue_refresh("artist/r", {})
        await asyncio.wait_for(c.refresher, 10)

    with caplog.at_level("DEBUG"):
        asyncio.run(go())
    assert len(refresh.calls) == 1
    assert [r.getMessage() for r in caplog.records if getattr(r, "frontend", False)] == []

    #? ...and the test can see one: a question's 403 is said there
    caplog.clear()
    with caplog.at_level("DEBUG"):
        ask(c, ("artist/q", {}))
    assert any(getattr(r, "frontend", False) for r in caplog.records)


class Closable:
    """Stands in for an httpx.AsyncClient held by the client: closed or not."""

    is_closed = False

    async def aclose(self):
        self.is_closed = True


def test_a_failed_connection_closes_only_its_own(made, instant):
    """A refresh has a connection of its own, and its network error closes that one alone - never the one
    a question is waiting on - and a question's closes its own, never the refreshes'."""
    answers, client = made
    c = client(None)
    question_connection, refresh_connection = Closable(), Closable()
    c.client, c.refresh_client = question_connection, refresh_connection
    connect(c, MusicBrainz(DUMMY), MusicBrainz(error=httpx.ConnectError("away"), name="refresh"))

    async def refresh_once():
        c._queue_refresh("artist/r", {})
        await asyncio.wait_for(c.refresher, 10)

    asyncio.run(refresh_once())
    assert refresh_connection.is_closed and c.refresh_client is None, "the refresh's own, closed"
    assert c.client is question_connection and not question_connection.is_closed, "the question's left open"

    other = Closable()
    c.refresh_client = other
    connect(c, MusicBrainz(error=httpx.ConnectError("away")), MusicBrainz(DUMMY, name="refresh"))
    c.client = question_connection
    assert ask(c, ("artist/q", {}))["status"] == "failed"
    assert question_connection.is_closed and c.client is None
    assert c.refresh_client is other and not other.is_closed, "the refreshes' left open"


def test_a_refresher_emptied_while_it_waits_ends_quietly(made):
    """Clear empties the queue without calling the refresher off: one waiting for its turn then finds
    nothing to ask, and ends - asking nothing, raising nothing."""
    answers, client = made
    c = client(None)
    question, refresh = connect(c, MusicBrainz(DUMMY), MusicBrainz(DUMMY, name="refresh"))

    async def go():
        c.asking = 1                                        # somebody's question on its way: it waits
        c._queue_refresh("artist/r", {})
        await asyncio.sleep(0.05)
        assert not c.refresher.done()
        c.refreshes.clear()                                 # what Clear does
        c.asking = 0
        await asyncio.wait_for(c.refresher, 2)              # raises whatever the refresher raised

    asyncio.run(go())
    assert refresh.calls == []


# ---------------------------------------------------------------- a paged browse, read as one answer

class Pages:
    """A fake MusicBrainz answering a paged browse: `ids` (changed by hand, as an edit on MusicBrainz would
    change them) a page at a time by offset and limit; `fail` maps an offset to the Answer it fails with;
    `between`, called after each answer, an edit made while the browse is under way."""

    def __init__(self, ids, items="release-groups", count="release-group-count", name="question", between=None):
        self.ids = ids
        self.items = items
        self.count = count
        self.name = name
        self.between = between
        self.fail: dict[int, Answer] = {}
        self.calls: list[tuple[str, dict]] = []
        self.times: list[float] = []
        self.log: list = []

    async def get(self, endpoint, params=None):
        params = dict(params or {})
        self.calls.append((endpoint, params))
        self.times.append(time.monotonic())
        offset, limit = int(params.get("offset", 0)), int(params.get("limit", 100))
        if offset in self.fail:
            return self.fail[offset]
        answer = Answer({self.items: [{"id": i, "title": f"Album {i}"} for i in self.ids[offset:offset + limit]],
                         self.count: len(self.ids)})
        if self.between is not None:
            self.between(self)
        return answer

    def offsets(self) -> list[int]:
        return [params["offset"] for _, params in self.calls]


#? the two paged browses: an artist's discography (release groups) and a release group's pressings
BROWSES = {
    "discography": (lambda c: c.get_artist_release_groups("artist-id"), "release-groups", "release-group-count"),
    "pressings": (lambda c: c.get_releases("group-id", log=False), "releases", "release-count"),
}


def browsed(kind, answer) -> list[str]:
    return [item["id"] for item in answer[BROWSES[kind][1]]]


def look(client, kind) -> list[str]:
    async def go():
        answer = await BROWSES[kind][0](client)
        if client.cache.disk is not None:
            await client.cache.disk.flush()
        return browsed(kind, answer)

    return asyncio.run(go())


def stamps(path) -> list[float]:
    return [fetched for _, fetched, _ in saved_rows(path)]


def saved_browse(made, kind, clock):
    """150 items saved as a browse of two pages, both under one stamp."""
    answers, client = made
    saved = answers(clock=clock)
    ids = [str(n) for n in range(1, 151)]
    before = client(saved)
    connect(before, Pages(ids, *BROWSES[kind][1:]))
    assert look(before, kind) == ids
    assert len(set(stamps(saved.path()))) == 1 and len(stamps(saved.path())) == 2, "two pages, one stamp"
    return saved, ids


@pytest.mark.parametrize("kind", list(BROWSES))
def test_a_browse_refreshed_halfway_keeps_its_old_pages_together(made, instant, kind):
    """Review: each page was saved and refreshed on its own, so a refresh that replaced the first page and
    then failed on the second left today's first page joined to the month-old second - and an album merged
    away on MusicBrainz meanwhile moved the page boundary, so one showed twice (150 groups, 149 different).
    Now an old browse is refreshed as ONE: every page asked, and nothing saved unless every page came."""
    clock = Clock(step=1.0)                                 # every reading a second on
    saved, ids = saved_browse(made, kind, clock)
    old = list(ids)
    rows = saved_rows(saved.path())

    clock.now += 31 * DAY
    ids.remove("1")                                         # merged away: everything after it moves up one
    after = made[1](saved)
    refresh = Pages(ids, *BROWSES[kind][1:], name="refresh")
    refresh.fail[100] = Answer(status_code=503)
    connect(after, MusicBrainz(error=AssertionError("a question was asked")), refresh)
    run = BROWSES[kind][0]

    async def go():
        first = await run(after)
        queued = list(after.refreshes)
        await asyncio.wait_for(after.refresher, 5)
        await saved.flush()
        return first, queued, await run(after)

    first, queued, second = asyncio.run(go())
    assert browsed(kind, first) == old, "the old browse, at once"
    assert len(queued) == 1, "one refresh, for the whole browse"
    assert refresh.offsets() == [0, 100], "every page asked, once"
    assert browsed(kind, second) == old, "still the old browse, whole - never today's first page and an old second"
    assert [row[:2] for row in saved_rows(saved.path())] == [row[:2] for row in rows], "nothing saved"

    #? a restart: the same, from the file
    assert look(made[1](saved), kind) == old


@pytest.mark.parametrize("kind", list(BROWSES))
def test_a_browse_refreshed_whole_is_saved_under_one_stamp(made, kind):
    clock = Clock(step=1.0)                                 # every reading a second on
    saved, ids = saved_browse(made, kind, clock)
    clock.now += 31 * DAY
    ids.remove("1")
    after = made[1](saved)
    refresh = Pages(ids, *BROWSES[kind][1:], name="refresh")
    connect(after, MusicBrainz(error=AssertionError("a question was asked")), refresh)

    async def go():
        await BROWSES[kind][0](after)
        await asyncio.wait_for(after.refresher, 5)
        await saved.flush()
        return await BROWSES[kind][0](after)

    old_stamp = stamps(saved.path())[0]
    second = asyncio.run(go())
    assert browsed(kind, second) == ids, "the new browse, whole"
    assert len(set(stamps(saved.path()))) == 1 and stamps(saved.path())[0] > old_stamp, "one stamp, the refresh's"
    #? each page took a turn of its own: at most one refresh in the limiter's window, as ever
    assert refresh.times[1] - refresh.times[0] >= after.rate_limit.time_window - 0.01
    assert look(made[1](saved), kind) == ids, "and after a restart"


@pytest.mark.parametrize("gone", [0, 100], ids=["first page trimmed", "second page trimmed"])
@pytest.mark.parametrize("kind", list(BROWSES))
def test_a_browse_missing_a_page_is_asked_again_whole(made, kind, gone):
    """Review: the size trim drops answers one by one, so it could drop one page of a browse and keep the
    other - and the next read asked MusicBrainz for the missing page and joined it to the kept one, for up
    to a month. Now a page from MusicBrainz means every page from MusicBrainz, and a page in no cache after
    pages that were means the browse is asked again, whole."""
    clock = Clock(step=1.0)                                 # every reading a second on
    saved, ids = saved_browse(made, kind, clock)
    with sqlite3.connect(saved.path()) as connection:
        connection.execute("DELETE FROM answers WHERE key LIKE ?", (f'%["offset", "{gone}"]%',))
    assert len(saved_rows(saved.path())) == 1

    clock.now += 10 * DAY                                   # neither page old
    ids.remove("1")
    after = made[1](saved)
    question, _ = connect(after, Pages(ids, *BROWSES[kind][1:]))
    assert look(after, kind) == ids, "every item once, none missing"
    assert question.offsets() == [0, 100]
    assert len(set(stamps(saved.path()))) == 1 and len(stamps(saved.path())) == 2, "saved together again"


@pytest.mark.parametrize("kind", list(BROWSES))
def test_pages_saved_at_different_times_are_never_joined(made, kind):
    clock = Clock(step=1.0)                                 # every reading a second on
    saved, ids = saved_browse(made, kind, clock)
    clock.now += 5 * DAY
    again = made[1](saved)
    question, _ = connect(again, Pages(ids, *BROWSES[kind][1:]))
    assert look(again, kind) == ids and question.calls == [], "one stamp: from the file, nothing asked"

    with sqlite3.connect(saved.path()) as connection:
        connection.execute("UPDATE answers SET fetched_at = fetched_at - 3600 WHERE key LIKE ?", ('%["offset", "100"]%',))
    ids.remove("1")
    after = made[1](saved)
    question, _ = connect(after, Pages(ids, *BROWSES[kind][1:]))
    assert look(after, kind) == ids
    assert question.offsets() == [0, 100], "asked again, whole"
    assert not after.refreshes, "nothing old: nothing queued"


@pytest.mark.parametrize("kind", list(BROWSES))
def test_an_item_on_two_pages_of_one_browse_is_listed_once(made, kind):
    """The pages of one browse are still asked seconds apart, and an edit on MusicBrainz between them can
    move an item across the boundary: it is listed once."""
    answers, client = made
    c = client(None)
    ids = [str(n) for n in range(1, 151)]

    def added_one(pages):
        if len(pages.calls) == 1:
            pages.ids.insert(0, "new")                      # added between the two pages: "100" moves to the second

    connect(c, Pages(ids, *BROWSES[kind][1:], between=added_one))
    got = look(c, kind)
    assert len(got) == len(set(got)) and got.count("100") == 1, got[95:105]


# ---------------------------------------------------------------- how big

def test_the_file_keeps_to_its_size_dropping_the_least_recently_used(made):
    answers, client = made
    budget = 512 << 10
    saved = answers(max_bytes=budget, clock=Clock(step=1.0))
    c = client(saved)
    #? thirty-odd requests: the pacing is not what this is about
    c.rate_limit = RateLimit()
    c.rate_limit.time_window = 0.0

    def noise(n):
        #? incompressible, so each answer costs about what it says
        return {"n": n, "noise": os.urandom(12 << 10).hex()}

    pages = {f"artist/{n}": noise(n) for n in range(32)}
    question, _ = connect(c, MusicBrainz({endpoint: Answer(payload) for endpoint, payload in pages.items()}))

    #? fifteen answers of about 12-16 KB each fit in 512 KB
    for n in range(15):
        ask(c, (f"artist/{n}", {}))
    assert len(saved_rows(saved.path())) == 15
    #? artist/0 used again, through the file (the memory forgotten): the most recently used now
    c.cache.clear()
    ask(c, ("artist/0", {}))
    assert len(question.calls) == 15
    for n in range(15, 32):
        ask(c, (f"artist/{n}", {}))

    kept = {json.loads(key)[0] for key, _, _ in saved_rows(saved.path())}
    stats = asyncio.run(saved.stats())
    assert stats["bytes"] <= budget, stats
    assert "artist/31" in kept and "artist/0" in kept, "the newest, and the one used again"
    assert "artist/1" not in kept and "artist/2" not in kept, "the ones used longest ago went first"
    assert 15 < len(kept) < 32, len(kept)


def test_an_answer_bigger_than_the_budget_is_not_kept(made):
    """...and nothing else is dropped to make room for it."""
    answers, client = made
    #? (2.0.0-player.56) half a megabyte: the saved-search index's empty tables are some 68 KB of the file (17 pages of 4 KB, measured)
    saved = answers(max_bytes=512 << 10)
    c = client(saved)
    connect(c, MusicBrainz({"release-group/": DUMMY, LOOKUP[0]: {"noise": os.urandom(600 << 10).hex()}}))
    ask(c)
    ask(c, LOOKUP)
    assert [json.loads(key)[0] for key, _, _ in saved_rows(saved.path())] == ["release-group/"]


def test_an_answer_over_90_percent_of_the_budget_is_not_kept(made):
    """Review: the test above used an answer bigger than the whole budget, so `> budget` passed it as well
    as `> 90% of it`. One between the two: kept, the trim back under 90% would drop everything else - and
    then it too."""
    answers, client = made
    #? (2.0.0-player.56) half a megabyte: the saved-search index's empty tables are some 68 KB of the file (17 pages of 4 KB, measured)
    budget = 512 << 10
    saved = answers(max_bytes=budget)
    c = client(saved)
    key = ResponseCache.disk_key(*LOOKUP)
    noise = os.urandom(240 << 10)
    for _ in range(40):
        payload = {"noise": noise.hex()}
        share = (len(pack(payload)) + len(key)) / budget
        if 0.92 <= share <= 0.98:
            break
        noise = noise[: int(len(noise) * 0.95 / share)] if share > 0.98 else noise + os.urandom(int(len(noise) * (0.95 / share - 1)) + 1)
    assert 0.92 <= share <= 0.98, share
    connect(c, MusicBrainz({"release-group/": DUMMY, LOOKUP[0]: payload}))
    ask(c)
    ask(c, LOOKUP)
    assert [json.loads(row_key)[0] for row_key, _, _ in saved_rows(saved.path())] == ["release-group/"]


def test_zero_turns_the_disk_off(made, monkeypatch):
    answers, client = made
    saved = answers(max_bytes=0)
    c = client(saved)
    question, _ = connect(c, MusicBrainz(DUMMY))
    ask(c)
    assert not os.path.exists(saved.path()), "nothing written - not even made"

    again = client(saved)
    question, _ = connect(again, MusicBrainz(DUMMY))
    ask(again)
    assert len(question.calls) == 1, "and nothing read: MusicBrainz is asked after a restart, as before"

    #? the setting itself
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_MB", "0")
    assert SavedAnswers().enabled() is False
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_MB", "200")
    assert SavedAnswers().max_bytes() == 200 << 20
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_MB", "lots")
    assert SavedAnswers().max_bytes() == 200 << 20, "unreadable is the default"


@pytest.mark.parametrize("value, megabytes", [("0", 0), ("200", 200), ("64 MB", 64), ("1048576", 1 << 20),
                                              ("-1", None), ("1048577", None), ("1.5", None), ("", None),
                                              ("1_024", None), ("٣", None)])
def test_the_size_setting_reads_whole_megabytes(value, megabytes):
    assert parse_musicbrainz_cache_mb(value) == megabytes


def test_a_full_file_is_trimmed_back_under_90_percent_not_on_every_answer(made):
    """Past the budget the answers used longest ago go until the file is back under TRIM_TO (90%) of it -
    so the next answers are kept without dropping any, rather than one dropped on every answer saved."""
    answers, client = made
    budget = 512 << 10
    saved = answers(max_bytes=budget, clock=Clock(step=1.0))

    def used():
        return asyncio.run(saved._run(saved._with_file, False, SavedAnswers._used_bytes))

    counts, trimmed_at = [], None
    for n in range(60):
        saved.put(f"answer-{n}", {"n": n, "noise": os.urandom(12 << 10).hex()})
        asyncio.run(saved.flush())
        counts.append(len(saved_rows(saved.path())))
        if trimmed_at is None and n and counts[-1] <= counts[-2]:
            trimmed_at = n
            after_trim = used()
        if trimmed_at is not None and n == trimmed_at + 1:
            break

    assert trimmed_at is not None, counts
    assert counts[trimmed_at - 1] - counts[trimmed_at] >= 2, "several dropped at once, not one"
    assert after_trim <= budget * musicbrainz_cache.TRIM_TO, (after_trim, budget)
    assert counts[trimmed_at + 1] == counts[trimmed_at] + 1, "the next answer kept with nothing dropped"


# ---------------------------------------------------------------- a broken file, a wrong one, the database

def test_a_corrupt_file_is_set_aside_and_a_new_one_started(made, tmp_path, caplog):
    path = tmp_path / "musicbrainz-cache.db"
    path.write_bytes(b"this is not a database at all, " * 100)
    (tmp_path / "musicbrainz-cache.db-journal").write_bytes(b"a journal that would be played back")
    answers, client = made
    saved = answers(path)
    c = client(saved)
    question, _ = connect(c, MusicBrainz(DUMMY))

    with caplog.at_level("WARNING"):
        assert ask(c) == DUMMY

    aside = sorted(p.name for p in tmp_path.iterdir() if ".unreadable-" in p.name)
    assert len(aside) == 2 and aside[1].endswith("-journal"), aside
    assert not (tmp_path / "musicbrainz-cache.db-journal").exists()
    assert len(saved_rows(path)) == 1, "a new file, with the answer in it"
    assert sum("couldn't be read" in record.message for record in caplog.records) == 1, "said once"


def test_a_file_broken_while_in_use_is_set_aside_too(made, tmp_path):
    answers, client = made
    saved = answers()
    c = client(saved)
    connect(c, MusicBrainz(DUMMY))
    ask(c)

    def broken(connection):
        raise sqlite3.DatabaseError("database disk image is malformed")

    asyncio.run(saved._run(saved._with_file, False, broken))
    assert any(".unreadable-" in p.name for p in tmp_path.iterdir())
    c.cache.clear()
    question, _ = connect(c, MusicBrainz(DUMMY))
    assert ask(c) == DUMMY and len(question.calls) == 1, "asked again, and saved in a new file"
    assert len(saved_rows(saved.path())) == 1


def test_a_database_that_isnt_the_saved_answers_is_left_alone(made, tmp_path):
    path = tmp_path / "someone-elses.db"
    with sqlite3.connect(path) as connection:
        connection.execute("CREATE TABLE jobs (id INTEGER PRIMARY KEY, what TEXT)")
        connection.execute("INSERT INTO jobs (what) VALUES ('mine')")
    before = path.read_bytes()
    answers, client = made
    saved = answers(path)
    c = client(saved)
    connect(c, MusicBrainz(DUMMY))

    assert ask(c) == DUMMY
    stats = asyncio.run(saved.clear())

    assert path.read_bytes() == before, "not written, not emptied"
    assert "not deadwax's saved answers" in stats["problem"]
    assert (stats["answers"], stats["bytes"]) == (0, 0), "nor counted as if it were"


def test_the_job_database_is_never_the_file(made, tmp_path, monkeypatch):
    database = tmp_path / "deadwax.db"
    with sqlite3.connect(database) as connection:
        connection.execute("CREATE TABLE jobs (id INTEGER PRIMARY KEY)")
    monkeypatch.setattr(Config, "DB_PATH", str(database))
    before = database.read_bytes()
    answers, client = made
    saved = answers(database)
    c = client(saved)
    connect(c, MusicBrainz(DUMMY))

    assert ask(c) == DUMMY
    stats = asyncio.run(saved.clear())
    assert database.read_bytes() == before
    assert "deadwax's own database" in stats["problem"] and stats["bytes"] == 0

    #? ...and the settings tab won't save it, by its name or by the folder it is musicbrainz-cache.db in
    assert "deadwax's own database" in _validate("MUSICBRAINZ_CACHE_PATH", str(database))
    monkeypatch.setattr(Config, "DB_PATH", str(tmp_path / "musicbrainz-cache.db"))
    assert "deadwax's own database" in _validate("MUSICBRAINZ_CACHE_PATH", str(tmp_path))
    assert _validate("MUSICBRAINZ_CACHE_PATH", str(tmp_path / "elsewhere")) is None, "a folder not made yet"
    assert is_the_database(str(tmp_path / "a" / ".." / "musicbrainz-cache.db"), Config.DB_PATH)


def test_a_trim_refused_by_a_lock_leaves_no_transaction_open(made):
    """Review: a trim whose DELETE (or COMMIT) another process's lock refused left its BEGIN open - SQLite
    doesn't roll back on SQLITE_BUSY - so every answer saved after it went into that transaction, never
    committed, gone at a restart, with the file's lock held all the while. Now the trim rolls back: it
    costs that trim, and the answers after it are saved as ever."""
    answers, client = made
    budget = 256 << 10
    saved = answers(max_bytes=budget)
    for n in range(14):
        saved.put(f"answer-{n}", {"noise": os.urandom(12 << 10).hex()})
    asyncio.run(saved.flush())
    other = sqlite3.connect(saved.path(), isolation_level=None, timeout=0, check_same_thread=False)
    real_used = SavedAnswers._used_bytes
    locked = []

    def used_bytes(connection):
        used = real_used(connection)
        #? over budget, a trim about to start: another process takes the write lock first
        if used > budget and not locked:
            connection.execute("PRAGMA busy_timeout = 50")
            other.execute("BEGIN IMMEDIATE")
            locked.append(True)
        return used

    saved._used_bytes = used_bytes  # type: ignore[method-assign]
    for n in range(14, 40):
        saved.put(f"answer-{n}", {"noise": os.urandom(12 << 10).hex()})
        asyncio.run(saved.flush())
        if locked:
            break
    assert locked, "a trim came, and was refused"
    other.execute("ROLLBACK")
    other.close()

    assert asyncio.run(saved._run(lambda: saved._connection is None or not saved._connection.in_transaction)), \
        "out of the transaction"
    saved.put("after the lock", {"kept": True})
    asyncio.run(saved.flush())
    assert "after the lock" in [key for key, _, _ in saved_rows(saved.path())], "committed: another connection sees it"
    asyncio.run(saved.close())
    assert "after the lock" in [key for key, _, _ in saved_rows(saved.path())], "...and it outlives a restart"


def test_a_failure_inside_a_transaction_is_rolled_back(made):
    """Whatever fails with an OperationalError inside a transaction (locked, a full disk) costs that work and
    no more: the transaction is rolled back, never left open for the next write to fall into."""
    answers, client = made
    saved = answers()
    saved.put("first", {"n": 1})
    asyncio.run(saved.flush())

    def work(connection):
        connection.execute("BEGIN")
        connection.execute("INSERT INTO answers (key, body, size, fetched_at, used_at) VALUES ('half', x'00', 1, 0, 0)")
        connection.execute("SELECT * FROM no_such_table")      # an OperationalError, mid-transaction

    asyncio.run(saved._run(saved._with_file, False, work))
    assert asyncio.run(saved._run(lambda: saved._connection is None or not saved._connection.in_transaction))
    saved.put("second", {"n": 2})
    asyncio.run(saved.flush())
    assert sorted(key for key, _, _ in saved_rows(saved.path())) == ["first", "second"], "the half-done work undone"


def test_a_file_of_another_shape_is_emptied_and_made_afresh(made, tmp_path):
    """The saved answers' own file (its `kind`) in a shape of an older or newer deadwax (its `format`): only
    a cache, so emptied and made in this shape - never left unusable."""
    path = tmp_path / "musicbrainz-cache.db"
    with sqlite3.connect(path) as connection:
        connection.execute("CREATE TABLE meta (name TEXT PRIMARY KEY, value TEXT NOT NULL)")
        connection.executemany("INSERT INTO meta VALUES (?, ?)", [("kind", musicbrainz_cache.KIND), ("format", "0")])
        connection.execute("CREATE TABLE answers (key TEXT PRIMARY KEY, payload TEXT)")
        connection.execute("INSERT INTO answers VALUES ('old', '{}')")
    answers, client = made
    saved = answers(path)
    c = client(saved)
    connect(c, MusicBrainz(DUMMY))
    assert ask(c) == DUMMY

    assert [key for key, _, _ in saved_rows(path)] == [ResponseCache.disk_key(*SEARCH)]
    with sqlite3.connect(path) as connection:
        assert answers_meta(connection) == {"kind": musicbrainz_cache.KIND, "format": musicbrainz_cache.FORMAT}


def answers_meta(connection) -> dict:
    """The meta rows that say what the file is - less the saved-search index's own (2.0.0-player.56: `index_*`)."""
    return {name: value for name, value in connection.execute("SELECT name, value FROM meta") if not name.startswith("index_")}


class FullAtTheMetaRows(sqlite3.Connection):
    """A connection whose disk fills just as the meta rows are written - once."""

    failed = False

    def _check(self, sql):
        if "INTO meta" in sql and not FullAtTheMetaRows.failed:
            FullAtTheMetaRows.failed = True
            raise sqlite3.OperationalError("database or disk is full")

    def execute(self, sql, *args):
        self._check(sql)
        return super().execute(sql, *args)

    def executemany(self, sql, *args):
        self._check(sql)
        return super().executemany(sql, *args)


def test_a_file_whose_making_was_cut_short_is_made_afresh(made, tmp_path, monkeypatch):
    """Review: a new file's tables and the meta rows saying whose they are were made a statement at a time, so
    a disk filling (or deadwax killed) between them left tables with no `kind` - refused ever after as "a
    database, but not deadwax's saved answers", nothing saved until it was deleted by hand. Made in one
    transaction, it is all there or not at all."""
    answers, client = made
    saved = answers()
    real_connect = sqlite3.connect
    FullAtTheMetaRows.failed = False
    monkeypatch.setattr(musicbrainz_cache.sqlite3, "connect",
                        lambda *args, **kwargs: real_connect(*args, factory=FullAtTheMetaRows, **kwargs))
    saved.put("first", {"n": 1})
    asyncio.run(saved.flush())
    assert FullAtTheMetaRows.failed and "disk is full" in saved.problem

    asyncio.run(saved.reset())                              # a minute on, or a settings save: tried again
    saved.put("second", {"n": 2})
    asyncio.run(saved.flush())
    assert saved.problem is None
    assert [key for key, _, _ in saved_rows(saved.path())] == ["second"]
    with real_connect(saved.path()) as connection:
        assert answers_meta(connection) == {"kind": musicbrainz_cache.KIND, "format": musicbrainz_cache.FORMAT}


def test_a_file_killed_while_it_was_being_made_is_made_afresh(tmp_path):
    """The same, with deadwax killed (SIGKILL, a power cut) between the tables and the meta rows."""
    path = tmp_path / "musicbrainz-cache.db"
    script = f"""
import os, signal, sqlite3, sys
sys.path.insert(0, {str(REPO)!r})
from src import musicbrainz_cache

class Killed(sqlite3.Connection):
    def executemany(self, sql, *args):
        if "INTO meta" in sql:
            os.kill(os.getpid(), signal.SIGKILL)
        return super().executemany(sql, *args)

real = sqlite3.connect
musicbrainz_cache.sqlite3.connect = lambda *a, **k: real(*a, factory=Killed, **k)
saved = musicbrainz_cache.SavedAnswers({str(path)!r}, max_bytes=8 << 20)
saved._put("first", {{"n": 1}}, 1.0, 1.0)
"""
    import subprocess
    finished = subprocess.run([sys.executable, "-c", script], cwd=REPO, capture_output=True, timeout=60)
    assert finished.returncode == -9, finished.stderr.decode()[-500:]
    assert path.exists()

    saved = SavedAnswers(str(path), max_bytes=8 << 20)
    try:
        saved.put("second", {"n": 2})
        asyncio.run(saved.flush())
        assert saved.problem is None, saved.problem
        assert [key for key, _, _ in saved_rows(path)] == ["second"]
    finally:
        asyncio.run(saved.close())


def test_a_file_of_any_other_name_is_never_set_aside(made, tmp_path):
    """Only a file named musicbrainz-cache.db is ever set aside (and the log calls the old one deletable): a
    path given by hand that names somebody's file leaves it exactly as it was, and nothing is saved."""
    notes = tmp_path / "notes.txt"
    notes.write_bytes(b"my notes")
    answers, client = made
    saved = answers(notes)
    c = client(saved)
    connect(c, MusicBrainz(DUMMY))

    assert ask(c) == DUMMY
    stats = asyncio.run(saved.stats())
    asyncio.run(saved.clear())

    assert notes.read_bytes() == b"my notes"
    assert sorted(p.name for p in tmp_path.iterdir()) == ["notes.txt"], "nothing renamed, nothing made beside it"
    assert stats["answers"] == 0 and "left alone" in (saved.problem or "")


def test_the_settings_look_at_the_file_never_sets_it_aside_nor_makes_one(made, tmp_path):
    """The size the settings show (stats, the GET they read as they draw) only looks: no file made where
    there is none, and a broken one left for the next answer saved to set aside."""
    answers, client = made
    saved = answers()
    assert asyncio.run(saved.stats())["bytes"] == 0
    assert list(tmp_path.iterdir()) == [], "nothing made"

    path = tmp_path / "musicbrainz-cache.db"
    path.write_bytes(b"this is not a database at all, " * 100)
    stats = asyncio.run(saved.stats())
    assert (stats["answers"], path.read_bytes()[:8]) == (0, b"this is "), "looked at, left as it was"
    assert sorted(p.name for p in tmp_path.iterdir()) == ["musicbrainz-cache.db"]

    c = client(saved)
    connect(c, MusicBrainz(DUMMY))
    ask(c)
    assert any(".unreadable-" in p.name for p in tmp_path.iterdir()), "used for real (a read, a write), it is set aside"
    assert len(saved_rows(path)) == 1


# ---------------------------------------------------------------- where the file is

def test_the_file_is_beside_the_database_by_default(tmp_path):
    assert musicbrainz_cache_path(None, "/config/deadwax.db") == "/config/musicbrainz-cache.db"
    assert musicbrainz_cache_path("", "/config/jimbrainz.db") == "/config/musicbrainz-cache.db"
    assert musicbrainz_cache_path(None, "jimbrainz.db") == os.path.join(".", "musicbrainz-cache.db")
    #? the legacy database default_db_path() goes on using - the file goes in its folder
    legacy = tmp_path / "jimbrainz.db"
    legacy.write_bytes(b"")
    chosen = default_db_path(str(tmp_path / "deadwax.db"), str(legacy))
    assert chosen == str(legacy)
    assert musicbrainz_cache_path(None, chosen) == str(tmp_path / "musicbrainz-cache.db")
    #? set: ALWAYS a folder, holding the file (James's addendum) - there or not yet, with a slash or without
    assert musicbrainz_cache_path("/cache", "/config/deadwax.db") == "/cache/musicbrainz-cache.db"
    assert musicbrainz_cache_path(str(tmp_path), "/config/deadwax.db") == str(tmp_path / "musicbrainz-cache.db")
    assert musicbrainz_cache_path("/not/yet/", "/config/deadwax.db") == "/not/yet/musicbrainz-cache.db"
    assert musicbrainz_cache_path("/not/yet", "/config/deadwax.db") == "/not/yet/musicbrainz-cache.db"
    #? never the value itself as the file, whatever it looks like
    assert musicbrainz_cache_path("/ssd/mb.db", "/config/deadwax.db") == "/ssd/mb.db/musicbrainz-cache.db"


def test_the_apps_saved_answers_follow_the_settings(tmp_path, monkeypatch):
    monkeypatch.setattr(Config, "DB_PATH", str(tmp_path / "config" / "deadwax.db"))
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_PATH", None)
    saved = SavedAnswers()
    assert saved.path() == str(tmp_path / "config" / "musicbrainz-cache.db")
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_PATH", str(tmp_path / "ssd") + "/")
    assert saved.path() == str(tmp_path / "ssd" / "musicbrainz-cache.db")
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_PATH", str(tmp_path / "ssd"))
    assert saved.path() == str(tmp_path / "ssd" / "musicbrainz-cache.db"), "a folder not there yet is still a folder"


def test_nothing_but_the_running_app_attaches_the_file():
    """Every test's ResponseCache is memory alone unless it says otherwise, and so is the class's own until
    the lifespan attaches the app's - nothing outside a running app ever writes the real file."""
    assert ResponseCache().disk is None
    source = (REPO / "src/api/app.py").read_text()
    assert "MusicBrainzClient.cache.disk = saved_answers" in source
    assert "MusicBrainzClient.cache.disk = None" in source


def test_closing_writes_what_is_queued_first(made):
    answers, _ = made
    saved = answers()
    saved.put("queued", {"n": 1})
    asyncio.run(saved.close())                              # no flush first
    assert [key for key, _, _ in saved_rows(saved.path())] == ["queued"]


def test_the_lifespan_attaches_the_file_and_closes_it_after_the_refreshes_stop(monkeypatch, tmp_path):
    """The lifespan attaches the app's saved answers once the settings' overrides are in, and as it ends stops
    the refreshes and drops MusicBrainz's connections BEFORE closing the file (which writes what is queued),
    and only then detaches it."""
    from src import auth
    from src.api import app as app_module
    from src.store import JobStore

    order = []

    class Client:
        cache = ResponseCache()

        async def stop_refreshing(self):
            order.append("stop refreshing")

        async def close_client(self):
            order.append("close connections")

    class Other:
        async def close_client(self):
            return None

    class File:
        def enabled(self):
            return True

        def path(self):
            return str(tmp_path / "musicbrainz-cache.db")

        def max_bytes(self):
            return 200 << 20

        async def close(self):
            order.append(("close the file", Client.cache.disk is self))

        def warm(self):
            #? (2.0.0-player.56) opened as the app starts, attached first - so its backfill reads the attached file
            order.append(("warm", Client.cache.disk is self))

    the_file = File()

    async def forever(*_args):
        await asyncio.Event().wait()

    async def nothing(*_args):
        return None

    monkeypatch.setattr(app_module, "MusicBrainzClient", Client)
    monkeypatch.setattr(app_module, "SlskdClient", Other)
    monkeypatch.setattr(app_module, "saved_answers", the_file)
    monkeypatch.setattr(app_module, "JobStore", lambda: JobStore(str(tmp_path / "deadwax.db")))
    monkeypatch.setattr(app_module, "seed_from_saved_scan", nothing)
    monkeypatch.setattr(app_module, "run_download_poller", forever)
    monkeypatch.setattr(app_module, "cleanup_logging", lambda: None)
    for client in (app_module.library.coverart_client, app_module.library.artist_images_client,
                   app_module.lrclib, app_module.navidrome_client, auth.login_client, app_module.stars.star_client):
        monkeypatch.setattr(client, "close_client", nothing)
    monkeypatch.setattr(Config, "apply_overrides", lambda stored: None)
    monkeypatch.setattr(Config, "AUTH_MODE", "off")

    async def go():
        application = start()
        async with app_module.lifespan(application):
            attached = Client.cache.disk is the_file
        return attached

    assert asyncio.run(go()) is True, "attached while the app runs"
    assert order == [("warm", True), "stop refreshing", "close connections", ("close the file", True)]
    assert Client.cache.disk is None, "detached after"


def test_the_path_is_always_a_folder_and_can_share_the_player_caches(tmp_path, monkeypatch):
    """James's addendum: MUSICBRAINZ_CACHE_PATH is a FOLDER, which can be the player cache's - one SSD
    mount for both. Named before the folder exists, it is made with the first answer saved (never a file
    of that name, which would then shut the player's cache out of it), and the same setting names the
    same file before the folder exists and after."""
    from src import player_cache

    shared = tmp_path / "cache"
    monkeypatch.setattr(Config, "DB_PATH", str(tmp_path / "config" / "deadwax.db"))
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_PATH", str(shared))
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_MB", "200")
    saved = SavedAnswers()
    before = saved.path()

    async def go():
        saved.put("a question", {"an": "answer"})
        await saved.flush()
        await saved.close()

    asyncio.run(go())
    assert shared.is_dir(), "made as a folder"
    assert saved.path() == before == str(shared / "musicbrainz-cache.db"), "the same file, before and after"
    assert len(saved_rows(before)) == 1
    folder, problem = player_cache.open_folder(str(shared))
    assert problem is None and folder == shared / player_cache.FOLDER_NAME, "the player's cache shares it"
    assert sorted(p.name for p in shared.iterdir()) == ["deadwax-player", "musicbrainz-cache.db"]


def test_a_path_naming_a_file_is_refused_and_the_file_never_touched(app, tmp_path, monkeypatch):
    """Review: a mistyped path that named a file of somebody's had it renamed aside, and a new database
    made under its name, by the settings' own GET - the log calling the original deletable. Now the
    setting is a folder: the settings tab refuses a file, and one set in the environment is never touched
    - nothing saved, the row saying why."""
    web, c, _ = app
    notes = tmp_path / "notes.txt"
    notes.write_bytes(b"my notes")
    refused = web.put("/deadwax/settings", json=[{"key": "MUSICBRAINZ_CACHE_PATH", "value": str(notes)}])
    assert refused.status_code == 400 and "MUSICBRAINZ_CACHE_PATH: that is a file" in refused.json()["detail"]

    following = SavedAnswers()
    c.cache.disk = following
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_PATH", str(notes))    # from compose, say
    try:
        assert web.get("/deadwax/settings/musicbrainz_cache").json()["answers"] == 0
        connect(c, MusicBrainz(DUMMY))
        assert ask(c) == DUMMY
        [row] = [r for g in web.get("/deadwax/settings").json()["groups"] for r in g["settings"]
                 if r["key"] == "MUSICBRAINZ_CACHE_PATH"]
        assert row["status"] == "error" and "is a file, not a directory" in row["detail"]
    finally:
        asyncio.run(following.close())
    assert notes.read_bytes() == b"my notes"
    assert not [p for p in tmp_path.iterdir() if p.name.startswith("notes.txt.")], "nothing set aside"


def test_the_example_compose_file_and_env_name_both_settings():
    """James's addendum: the compose example carries MUSICBRAINZ_CACHE_PATH beside PLAYER_CACHE_PATH,
    commented out, pointing at the same /cache mount, the mount's comment naming both - and .env.example
    both settings, as it lists PLAYER_CACHE_PATH."""
    from src.config import DEFAULT_MUSICBRAINZ_CACHE_MB

    compose = [line.strip() for line in (REPO / "docker-compose.example.yml").read_text().splitlines()]
    player = compose.index("#- PLAYER_CACHE_PATH=/cache")
    beside = compose[player:player + 16]
    assert "#- MUSICBRAINZ_CACHE_PATH=/cache" in beside
    assert f"#- MUSICBRAINZ_CACHE_MB={DEFAULT_MUSICBRAINZ_CACHE_MB}" in beside
    mount = compose.index("#- /path/to/fast/disk/deadwax-cache:/cache")
    said = " ".join(compose[mount - 3:mount])
    assert "PLAYER_CACHE_PATH" in said and "MUSICBRAINZ_CACHE_PATH" in said

    env = [line.strip() for line in (REPO / ".env.example").read_text().splitlines()]
    assert "#PLAYER_CACHE_PATH=" in env
    assert "#MUSICBRAINZ_CACHE_PATH=" in env and f"#MUSICBRAINZ_CACHE_MB={DEFAULT_MUSICBRAINZ_CACHE_MB}" in env


# ---------------------------------------------------------------- never in the way

def test_a_slow_disk_is_given_up_for_musicbrainz(made, monkeypatch):
    answers, client = made
    saved = answers()
    c = client(saved)
    connect(c, MusicBrainz(DUMMY))
    ask(c)
    c.cache.clear()
    monkeypatch.setattr(musicbrainz_cache, "READ_TIMEOUT_SECONDS", 0.05)
    real_get = saved._get

    def slow_get(key):
        time.sleep(0.6)
        return real_get(key)

    saved._get = slow_get  # type: ignore[method-assign]
    question, _ = connect(c, MusicBrainz(DUMMY))

    async def go():
        began = time.monotonic()
        answer = await c.request_with_retries(*SEARCH)
        return answer, time.monotonic() - began

    answer, took = asyncio.run(go())
    assert answer == DUMMY and len(question.calls) == 1, "MusicBrainz asked instead"
    assert took < 0.4, f"not held by the disk ({took:.2f}s)"


def test_the_disk_is_only_ever_touched_on_its_own_thread(made):
    answers, client = made
    saved = answers()
    seen = []
    for name in ("_get", "_put", "_touch", "_stats", "_clear"):
        real = getattr(saved, name)

        def spy(*args, _real=real, _name=name):
            seen.append((_name, threading.current_thread().name))
            return _real(*args)

        setattr(saved, name, spy)
    c = client(saved)
    connect(c, MusicBrainz(DUMMY))
    ask(c)
    c.cache.clear()
    ask(c)
    asyncio.run(saved.stats())
    asyncio.run(saved.clear())

    assert {name for name, _ in seen} == {"_get", "_put", "_touch", "_stats", "_clear"}
    assert all(thread.startswith("musicbrainz-answers") for _, thread in seen), seen


def test_the_connection_check_is_never_answered_from_the_file(made, instant):
    """ping asks whether MusicBrainz can be reached; an answer saved last week can't say."""
    answers, client = made
    saved = answers()
    c = client(saved)
    ping_key = ResponseCache.disk_key("release-group/f6b1b900-6108-32f0-abbd-2855af9151eb", {})
    saved.put(ping_key, {"id": "f6b1b900-6108-32f0-abbd-2855af9151eb"})
    asyncio.run(saved.flush())
    question, _ = connect(c, MusicBrainz(error=httpx.ConnectError("down")))

    assert asyncio.run(c.ping())["status"] == "failed"
    question.error = None
    question.answers = {"id": "f6b1b900-6108-32f0-abbd-2855af9151eb"}
    asyncio.run(saved.clear())
    assert asyncio.run(c.ping()) == {"status": "ok"}
    asyncio.run(saved.flush())
    assert saved_rows(saved.path()) == [], "nor saved"


# ---------------------------------------------------------------- which questions are the same

def test_only_a_querys_runs_of_whitespace_are_closed_up():
    assert same_question("query", "Massive  Attack ") == "Massive Attack"
    assert same_question("query", "\tMassive\r\n Attack") == "Massive Attack"
    assert same_question("query", 'releasegroup:"Dummy"   AND   artist:"Portishead"') == \
        'releasegroup:"Dummy" AND artist:"Portishead"'
    #? never the case: AND, OR and NOT are operators only in capitals
    assert same_question("query", "a AND b") != same_question("query", "a and b")
    #? never a no-break space, which Lucene reads as part of a word
    assert same_question("query", "Sigur\u00a0Ros") == "Sigur\u00a0Ros"
    #? never an escaped space
    assert same_question("query", "a\\ b") == "a\\ b"
    assert same_question("query", "a\\  b") == "a\\  b"
    assert same_question("query", "a\\   b") == "a\\  b"
    assert same_question("query", "end\\ ") == "end\\ "
    #? nor anything but a query
    assert same_question("artist", "Massive  Attack") == "Massive  Attack"
    assert same_question("limit", 12) == "12"


def test_the_same_question_written_two_ways_is_asked_once(made):
    answers, client = made
    saved = answers()
    c = client(saved)
    question, _ = connect(c, MusicBrainz(DUMMY))
    ask(c, ("release-group/", {"query": "Massive  Attack ", "fmt": "json"}))
    ask(c, ("release-group/", {"fmt": "json", "query": "Massive Attack"}))
    c.cache.clear()
    ask(c, ("release-group/", {"fmt": "json", "query": " Massive\tAttack"}))
    assert len(question.calls) == 1
    assert len(saved_rows(saved.path())) == 1
    #? ...but a different question is a different answer
    ask(c, ("release-group/", {"fmt": "json", "query": "massive attack"}))
    assert len(question.calls) == 2


# ---------------------------------------------------------------- Clear, and the settings

@pytest.fixture
def app(made, tmp_path, monkeypatch):
    from src.store import JobStore

    answers, client = made
    saved = answers()
    c = client(saved)
    monkeypatch.setattr(Config, "OVERRIDDEN", set())
    monkeypatch.setattr(Config, "ENV_VALUES", {})
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_PATH", None)
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_MB", "200")
    monkeypatch.setattr(Config, "DB_PATH", str(tmp_path / "deadwax.db"))
    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()
    application = start()  # no `with`: no lifespan, nothing connects
    application.state.store = store
    application.state.musicbrainz_client = c
    return TestClient(application), c, saved


def test_clear_empties_the_file_and_the_memory(app):
    web, c, saved = app
    question, _ = connect(c, MusicBrainz({"release-group/": DUMMY, "artist/a": {"id": "a", "pad": os.urandom(25000).hex()}}))
    ask(c)
    ask(c, ("artist/a", {}))
    c.refreshes[("x",)] = ("artist/b", {})

    shown = web.get("/deadwax/settings/musicbrainz_cache").json()
    assert (shown["answers"], shown["enabled"], shown["path"], shown["problem"]) == (2, True, saved.path(), None)
    assert shown["bytes"] == os.path.getsize(saved.path()) > 0
    assert shown["limit_mb"] == 8

    cleared = web.post("/deadwax/settings/musicbrainz_cache/clear")
    assert cleared.status_code == 200
    assert cleared.json()["answers"] == 0 and cleared.json()["bytes"] < shown["bytes"]
    assert c.cache.entries == {} and not c.refreshes

    ask(c)
    assert len(question.calls) == 3, "asked of MusicBrainz again"


def test_clear_is_a_write_another_website_cant_ask_for(app):
    web, c, saved = app
    connect(c, MusicBrainz(DUMMY))
    ask(c)
    refused = web.post("/deadwax/settings/musicbrainz_cache/clear", headers={"Origin": "https://evil.example"})
    assert refused.status_code == 403
    assert web.get("/deadwax/settings/musicbrainz_cache").json()["answers"] == 1


def test_the_settings_show_the_two_rows_beside_musicbrainz(app, tmp_path):
    web, _, _ = app
    payload = web.get("/deadwax/settings").json()
    [group] = [g for g in payload["groups"] if g["id"] == "musicbrainz-cache"]
    ids = [g["id"] for g in payload["groups"]]
    assert ids.index("musicbrainz-cache") == ids.index("connections") + 1
    rows = {row["key"]: row for row in group["settings"]}
    assert list(rows) == ["MUSICBRAINZ_CACHE_PATH", "MUSICBRAINZ_CACHE_MB"]
    assert str(tmp_path / "musicbrainz-cache.db") in rows["MUSICBRAINZ_CACHE_PATH"]["effect"]
    assert rows["MUSICBRAINZ_CACHE_PATH"]["status"] == "unset" and rows["MUSICBRAINZ_CACHE_PATH"]["editable"]
    assert "at most 200 MB" in rows["MUSICBRAINZ_CACHE_MB"]["effect"]
    assert "about 4,000 artists" in rows["MUSICBRAINZ_CACHE_MB"]["effect"]
    assert "7 days" in group["note"] and "30" in group["note"]


@pytest.mark.parametrize("value", ["abc", "-1", "1048577", "1.5", "", " ", "1_024"])
def test_a_size_that_isnt_one_is_refused(app, value):
    web, _, _ = app
    response = web.put("/deadwax/settings", json=[{"key": "MUSICBRAINZ_CACHE_MB", "value": value}])
    assert response.status_code == 400
    assert "MUSICBRAINZ_CACHE_MB: expected a whole number of MB, 0 to 1048576" in response.json()["detail"]


def test_settings_saved_apply_from_the_next_answer(app, tmp_path):
    web, c, saved = app
    #? the app's own saved answers, following the settings - not the fixed test ones
    following = SavedAnswers()
    c.cache.disk = following
    try:
        question, _ = connect(c, MusicBrainz(DUMMY))
        ask(c)
        assert len(saved_rows(tmp_path / "musicbrainz-cache.db")) == 1, "beside the database"

        moved = tmp_path / "ssd"                          # not there yet: made with the first answer
        saved_response = web.put("/deadwax/settings", json=[{"key": "MUSICBRAINZ_CACHE_PATH", "value": str(moved)}])
        assert saved_response.status_code == 200
        c.cache.clear()
        ask(c)
        assert len(question.calls) == 2, "a new, empty file"
        assert len(saved_rows(moved / "musicbrainz-cache.db")) == 1

        off = web.put("/deadwax/settings", json=[{"key": "MUSICBRAINZ_CACHE_MB", "value": "0"}])
        assert off.status_code == 200
        [row] = [r for g in off.json()["groups"] for r in g["settings"] if r["key"] == "MUSICBRAINZ_CACHE_MB"]
        assert row["effect"].startswith("0: off")
        c.cache.clear()
        ask(c)
        assert len(question.calls) == 3, "off: MusicBrainz asked, the file not read"
    finally:
        asyncio.run(following.close())


def test_a_save_retries_a_file_that_couldnt_be_used_at_once(app, tmp_path, monkeypatch):
    """A file that couldn't be used is tried again only after a minute - unless a save of either setting
    says something changed: then from the next answer."""
    web, c, _ = app
    (tmp_path / "other").mkdir()
    other = tmp_path / "other" / "musicbrainz-cache.db"
    with sqlite3.connect(other) as connection:
        connection.execute("CREATE TABLE t (x)")
    following = SavedAnswers()
    c.cache.disk = following
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_PATH", str(tmp_path / "other"))
    try:
        question, _ = connect(c, MusicBrainz(DUMMY))
        ask(c)
        assert "not deadwax's saved answers" in asyncio.run(following.stats())["problem"]
        other.unlink()                                    # put right, by hand
        c.cache.clear()
        ask(c)
        assert not other.exists(), "not tried again yet - a minute hasn't passed"

        assert web.put("/deadwax/settings", json=[{"key": "MUSICBRAINZ_CACHE_MB", "value": "300"}]).status_code == 200
        c.cache.clear()
        ask(c)
        assert len(saved_rows(other)) == 1, "the save said try again: saved from the next answer"
        assert asyncio.run(following.stats())["problem"] is None
    finally:
        asyncio.run(following.close())


def test_a_problem_with_the_file_is_said_on_its_row(app, tmp_path, monkeypatch):
    web, c, _ = app
    (tmp_path / "other").mkdir()
    with sqlite3.connect(tmp_path / "other" / "musicbrainz-cache.db") as connection:
        connection.execute("CREATE TABLE t (x)")
    following = SavedAnswers()
    c.cache.disk = following
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_PATH", str(tmp_path / "other"))
    try:
        connect(c, MusicBrainz(DUMMY))
        ask(c)
        [row] = [r for g in web.get("/deadwax/settings").json()["groups"] for r in g["settings"]
                 if r["key"] == "MUSICBRAINZ_CACHE_PATH"]
        assert row["status"] == "error" and "not deadwax's saved answers" in row["detail"]
    finally:
        asyncio.run(following.close())


@pytest.mark.skipif(os.name != "posix" or os.geteuid() == 0, reason="root can make a folder anywhere")
def test_a_folder_that_cant_be_made_is_said_for_as_long_as_it_lasts(app, tmp_path, monkeypatch, caplog):
    """Review: MUSICBRAINZ_CACHE_PATH=/cache uncommented in the compose example with the /cache volume left
    out - deadwax running as PUID can't make /cache, and nothing is ever saved. The row said so only for the
    minute after a failed save: then any look at the missing file (the Clear line's stats, a search's read)
    cleared the problem, and Settings showed fine. Now the row checks the nearest folder that IS there, from
    the start, and the problem a save found stands until a file opens or the settings are saved."""
    web, c, _ = app
    shut = tmp_path / "shut"
    shut.mkdir()
    monkeypatch.setattr(Config, "MUSICBRAINZ_CACHE_PATH", str(shut / "cache"))
    following = SavedAnswers()
    c.cache.disk = following

    def row():
        [found] = [r for g in web.get("/deadwax/settings").json()["groups"] for r in g["settings"]
                   if r["key"] == "MUSICBRAINZ_CACHE_PATH"]
        return found

    assert row()["status"] != "error", "a folder not there yet, that can be made: fine"
    shut.chmod(0o555)
    try:
        before = row()
        assert before["status"] == "error", "said before any search"
        assert f"nothing exists at {shut / 'cache'}" in before["detail"] and "NOT writable" in before["detail"]

        question, _ = connect(c, MusicBrainz(DUMMY))
        with caplog.at_level("WARNING"):
            for n in range(3):
                c.cache.clear()
                ask(c)
                monkeypatch.setattr(musicbrainz_cache, "RETRY_OPEN_SECONDS", 0.0)   # the minute gone
                stats = web.get("/deadwax/settings/musicbrainz_cache").json()
                assert stats["problem"] and "Permission denied" in stats["problem"], n
        assert len(question.calls) == 3, "nothing saved, so asked each time"
        assert sum("aren't being saved" in r.getMessage() for r in caplog.records) == 1, "said once, not every minute"
        assert row()["status"] == "error"
    finally:
        shut.chmod(0o755)
        asyncio.run(following.close())


def test_clears_refusal_is_styled_by_aria_disabled_on_every_page():
    """Review: Clear refuses with aria-disabled, never `disabled` (it refuses itself on its own press, and a
    focused button made disabled drops the focus to the page) - so each page fades it by that, where a rule
    on :disabled would never apply, and the main page takes away its hover and press."""
    from tests.test_app_css import declarations, tokens

    main = (REPO / "interface/styles/main.css").read_text()
    phone = (REPO / "interface/player/app.css").read_text()
    desk = (REPO / "interface/player/app-desktop.css").read_text()
    refused = "[aria-disabled='true']"
    assert declarations(main, f".settings-answers .win-button{refused}") == \
        {"cursor": "not-allowed", "opacity": "var(--disabled-opacity)"}
    assert declarations(main, f".settings-answers .win-button{refused}:hover")["background"] == "var(--gloss-button)"
    assert tokens((REPO / "interface/styles/theme.css").read_text())["--disabled-opacity"] == "0.45"
    assert declarations(phone, f".app-shell:not(.app-desk) .app-settings .settings-answers .win-button{refused}") == \
        {"opacity": "var(--app-job-busy)"}
    assert declarations(desk, f".app-desk .app-settings .settings-answers .win-button{refused}", "@media (min-width: 1024px)") == \
        {"opacity": "var(--app-job-busy)", "cursor": "not-allowed"}
    assert not declarations(phone, ".app-shell:not(.app-desk) .app-settings .settings-answers .win-button:disabled")
    assert not declarations(desk, ".app-desk .app-settings .settings-answers .win-button:disabled", "@media (min-width: 1024px)")


# ---------------------------------------------------------------- nothing goes round it

def _enclosing_functions(tree: ast.AST) -> dict[ast.AST, str]:
    owner = {}

    def walk(node, name):
        for child in ast.iter_child_nodes(node):
            inner = child.name if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)) else name
            owner[child] = inner
            walk(child, inner)

    walk(tree, "<module>")
    return owner


def test_no_musicbrainz_request_goes_round_request_with_retries():
    """Every caller - searches, album pages, the artist page, the editor, the download flow's tracklists,
    the song search, whatever comes next - gets the caches because every request goes through
    request_with_retries: only _ask touches a connection, and only request_with_retries calls _ask."""
    endpoint = REPO / "src/api/musicbrainz_endpoint.py"
    tree = ast.parse(endpoint.read_text())
    owner = _enclosing_functions(tree)
    #? who refers to each of these (a call, or a reference called later), by the function it's in
    used_in: dict[str, set[str]] = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Attribute):
            used_in.setdefault(node.attr, set()).add(owner[node])
        if isinstance(node, ast.Name) and node.id == "connect":
            used_in.setdefault("connect-name", set()).add(owner[node])

    assert used_in["_ask"] == {"request_with_retries"}
    assert used_in["get_client"] == used_in["get_refresh_client"] == {"_ask"}
    assert used_in["_new_client"] == {"get_client", "get_refresh_client"}
    #? `connect` is _ask's own name for whichever connection it uses
    assert used_in["connect-name"] == {"_ask"}
    #? the network's own .get(...) is called nowhere but _ask (dict .get()s have other owners)
    gets = {owner[node] for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and node.func.attr == "get" and isinstance(node.func.value, ast.Name) and node.func.value.id == "client"}
    assert gets == {"_ask"}

    #? and no other module in src talks to MusicBrainz's web service at all
    talking = [str(path.relative_to(REPO)) for path in (REPO / "src").rglob("*.py")
               if "musicbrainz.org/ws" in path.read_text()]
    assert talking == ["src/api/musicbrainz_endpoint.py"]
