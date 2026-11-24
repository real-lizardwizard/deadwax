"""
The Last.fm client (2.1.36, notes/lastfm.md): src/api/lastfm_endpoint.py over src/lastfm.py's classify().

No Last.fm is asked: every answer is httpx's MockTransport, shaped from Last.fm's API pages (read 2026-11-24) - the
error JSON `{"error": <code>, "message": ...}` - NOT recorded from Last.fm itself. The real answers come with
tests/fixtures/lastfm/record.py, run by whoever holds a key.

What this holds:
  - the key never leaves the request: not in a log line, the event log, an outcome's words, the settings answer or
    /deadwax/me - every outcome run with a sentinel key Last.fm "echoes", and everything captured searched;
  - what each answer is: 6 not known (never a failure), 10 and 26 refused, 29 and a 429 limited, the rest unreachable;
  - a refusal held an hour, said once, asked again by one ask after it, and let go when a new key is saved;
  - the pace: 60 s of nothing after a 29, never more than 5 begun in a second or 4 under way, a redirect never
    followed, an answer over 512 KB refused before it is read whole;
  - deadwax's own user agent, never MusicBrainz's with its email.
"""

import asyncio
import heapq
import itertools
import json
import logging

import httpx
import pytest
from fastapi.testclient import TestClient

from src import __version__
from src.api import lastfm_endpoint
from src.api.app import start
from src.api.lastfm_endpoint import API_URL, IN_FLIGHT, LIMITED_PAUSE_S, MAX_BYTES, PER_SECOND, lastfm
from src.config import Config
from src.lastfm import Answer, Limited, NotKnown, Refused, Unreachable, classify
from src.logger import SSEHandler, recent_log
from src.routes.settings import settings
from src.store import JobStore

#? a sentinel, 32 hex digits as Last.fm's keys are
KEY = "5e17e1d0b5e17e1d0b5e17e1d0b5e1ab"
START = 1_000_000.0
#? the wall clock's reading at START: as far from the monotonic clock as time.time() is from time.monotonic(), so a
#? clock mixed up anywhere shows
WALL = 1_764_000_000.0


class FakeTime:
    """A clock and a sleep that only move when every task is waiting: run() advances to the next sleeper. clock() is
    the one that only goes forward (time.monotonic's stand-in); wall() is time.time's, which `wall_offset` sets
    forward or back as NTP, a sleeping laptop or a hand can."""

    def __init__(self) -> None:
        self.now = START
        self.wall_offset = WALL - START
        self._sleepers: list = []
        self._order = itertools.count()

    def clock(self) -> float:
        return self.now

    def wall(self) -> float:
        return self.now + self.wall_offset

    async def sleep(self, seconds: float) -> None:
        future = asyncio.get_running_loop().create_future()
        heapq.heappush(self._sleepers, (self.now + max(0.0, seconds), next(self._order), future))
        await future

    async def run(self, *coroutines):
        tasks = [asyncio.ensure_future(coroutine) for coroutine in coroutines]
        for _ in range(200_000):
            for _ in range(30):
                await asyncio.sleep(0)
            if all(task.done() for task in tasks):
                break
            assert self._sleepers, "a task waits on something that isn't the fake clock"
            wake, _, future = heapq.heappop(self._sleepers)
            self.now = max(self.now, wake)
            future.set_result(None)
        return [task.result() for task in tasks]


@pytest.fixture
def client(monkeypatch):
    """The module's own client - the one /deadwax/me and the settings row read - on a fake clock, with a key; and the
    event log's handler on the root logger, as deadwax's own start puts it there (pytest's come first, so it doesn't
    here)."""
    monkeypatch.setattr(Config, "LASTFM_API_KEY", KEY)
    root = logging.getLogger()
    event_log = SSEHandler()
    root.addHandler(event_log)
    fake = FakeTime()
    lastfm.clock, lastfm.monotonic, lastfm.sleep = fake.wall, fake.clock, fake.sleep
    lastfm.fake = fake
    yield lastfm
    asyncio.run(lastfm.close_client())
    lastfm._client = None
    lastfm.transport = None
    lastfm.refusal = None
    lastfm.refused_since = 0.0
    lastfm._retrying = False
    lastfm.limited_until = 0.0
    lastfm._starts.clear()
    lastfm._in_flight = 0
    lastfm.clock, lastfm.monotonic, lastfm.sleep = lastfm_endpoint.time.time, lastfm_endpoint.time.monotonic, asyncio.sleep
    del lastfm.fake
    root.removeHandler(event_log)


def answering(client, handler) -> list[httpx.Request]:
    """`handler` as Last.fm, on a fresh connection; the requests it was sent."""
    sent: list[httpx.Request] = []

    async def recorded(request):
        sent.append(request)
        result = handler(request)
        return await result if asyncio.iscoroutine(result) else result

    asyncio.run(client.close_client())
    client._client = None
    client.transport = httpx.MockTransport(recorded)
    return sent


def error(code: int, message: str, status: int = 400) -> httpx.Response:
    return httpx.Response(status, json={"error": code, "message": message})


def ask(client, method="artist.getinfo", **params):
    return asyncio.run(client.ask(method, params or {"artist": "Tame Impala"}))


# ----- the request ---------------------------------------------------------------------------------------------------

def test_an_answer_is_its_json_from_one_get(client):
    sent = answering(client, lambda request: httpx.Response(200, json={"artist": {"name": "Tame Impala"}}))

    outcome = ask(client, "artist.gettoptracks", artist="Tame Impala", limit="50")

    assert outcome == Answer({"artist": {"name": "Tame Impala"}})
    [request] = sent
    assert request.method == "GET"
    assert str(request.url).startswith(API_URL)
    assert dict(request.url.params) == {"method": "artist.gettoptracks", "artist": "Tame Impala", "limit": "50",
                                        "api_key": KEY, "format": "json"}


def test_the_agent_is_deadwax_s_own_never_musicbrainz_s_with_its_email(client, monkeypatch):
    monkeypatch.setattr(Config, "MUSICBRAINZ_EMAIL", "someone@example.com")
    sent = answering(client, lambda request: httpx.Response(200, json={}))

    ask(client)

    [request] = sent
    assert request.headers["User-Agent"] == f"deadwax/{__version__}"
    assert not any("someone@example.com" in value for value in request.headers.values())


def test_no_key_asks_nothing(client, monkeypatch):
    monkeypatch.setattr(Config, "LASTFM_API_KEY", "   ")
    sent = answering(client, lambda request: httpx.Response(200, json={}))

    assert isinstance(ask(client), Unreachable)
    assert sent == []


# ----- what each answer is -------------------------------------------------------------------------------------------

@pytest.mark.parametrize("status, body, kind", [
    (200, {"error": 6, "message": "The artist you supplied could not be found"}, NotKnown),
    (400, {"error": 6, "message": "Invalid parameters"}, NotKnown),
    (403, {"error": 10, "message": "Invalid API key"}, Refused),
    (403, {"error": 26, "message": "Suspended API key"}, Refused),
    (200, {"error": "10", "message": "a code as a string"}, Refused),
    (429, None, Limited),
    (200, {"error": 29, "message": "Rate limit exceeded"}, Limited),
    (500, {"error": 8, "message": "Operation failed"}, Unreachable),
    (200, {"error": 11, "message": "Service Offline"}, Unreachable),
    (503, {"error": 16, "message": "Temporarily unavailable"}, Unreachable),
    (200, {"error": 2, "message": "Invalid service"}, Unreachable),
    (502, "<html>Bad gateway</html>", Unreachable),
    (200, "not json at all", Unreachable),
    (200, [1, 2, 3], Unreachable),
    (301, None, Unreachable),
])
def test_each_answer_is_classified(status, body, kind):
    raw = b"" if body is None else (body.encode() if isinstance(body, str) else json.dumps(body).encode())
    assert isinstance(classify(status, raw, START), kind)


def test_error_6_is_not_known_never_a_failure(client):
    answering(client, lambda request: error(6, "The artist you supplied could not be found"))

    outcome = ask(client)

    assert outcome == NotKnown("The artist you supplied could not be found")
    assert client.refusal is None and client.limited_until == 0.0


# ----- refused -------------------------------------------------------------------------------------------------------

def refusals_logged(after: int) -> list[str]:
    lines, _ = recent_log()
    return [line["event_content"] for line in lines
            if line["seq"] > after and line["event_content"].startswith("Last.fm refused LASTFM_API_KEY")]


@pytest.mark.parametrize("code", [10, 26])
def test_a_refused_key_is_held_an_hour_asking_nothing(client, code):
    sent = answering(client, lambda request: error(code, "Invalid API key - You must be granted a valid key", 403))
    _, before = recent_log()

    first = ask(client)
    client.fake.now += 3599
    second = ask(client)

    assert isinstance(first, Refused) and first.error == code
    assert second == first
    assert len(sent) == 1
    assert client.state() == "refused"
    assert refusals_logged(before) == [
        f"Last.fm refused LASTFM_API_KEY (error {code}: Invalid API key - You must be granted a valid key): top songs, "
        f"similar artists and radio are off until it's fixed in Server settings."]


def test_after_the_hour_one_ask_tries_again_and_the_rest_wait_for_it(client):
    gate = asyncio.Event()
    answers = iter([error(10, "Invalid API key", 403), None])

    async def handler(request):
        response = next(answers)
        if response is None:
            await gate.wait()
            return httpx.Response(200, json={"artist": {}})
        return response

    sent = answering(client, handler)
    _, before = recent_log()
    ask(client)
    client.fake.now += 3600
    assert client.state() == "on"

    async def both():
        retry = asyncio.ensure_future(client.ask("artist.getinfo", {"artist": "a"}))
        for _ in range(20):
            await asyncio.sleep(0)
        meanwhile = await client.ask("artist.getinfo", {"artist": "b"})
        gate.set()
        return await retry, meanwhile

    retried, meanwhile = asyncio.run(both())

    assert isinstance(meanwhile, Refused)
    assert retried == Answer({"artist": {}})
    assert len(sent) == 2
    assert client.refusal is None and client.state() == "on"
    assert len(refusals_logged(before)) == 1


def test_a_second_refusal_after_the_hour_is_held_again_but_not_said_again(client):
    sent = answering(client, lambda request: error(10, "Invalid API key", 403))
    _, before = recent_log()

    ask(client)
    client.fake.now += 3601
    ask(client)
    ask(client)

    assert len(sent) == 2
    assert client.state() == "refused"
    assert len(refusals_logged(before)) == 1


@pytest.fixture
def app(client, tmp_path, monkeypatch):
    monkeypatch.setattr(Config, "OVERRIDDEN", set())
    monkeypatch.setattr(Config, "ENV_VALUES", {})
    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()
    application = start()
    application.state.store = store
    return TestClient(application)


def save(app, value):
    return app.put("/deadwax/settings", json=[{"key": "LASTFM_API_KEY", "value": value}])


def test_a_new_key_saved_lets_the_refusal_go(app, client):
    sent = answering(client, lambda request: error(10, "Invalid API key", 403))
    ask(client)
    assert client.state() == "refused"

    assert save(app, "0123456789abcdef0123456789abcdef").status_code == 200

    assert client.state() == "on"
    ask(client)
    assert len(sent) == 2


def test_reverting_the_key_lets_the_refusal_go_too(app, client):
    answering(client, lambda request: error(26, "Suspended API key", 403))
    ask(client)

    assert save(app, None).status_code == 200

    assert client.refusal is None


def test_an_answer_for_a_key_since_replaced_says_nothing_of_the_new_one(client, monkeypatch):
    async def handler(request):
        monkeypatch.setattr(Config, "LASTFM_API_KEY", "0123456789abcdef0123456789abcdef")
        return error(10, "Invalid API key", 403)

    answering(client, handler)

    assert isinstance(ask(client), Refused)
    assert client.refusal is None and client.state() == "on"


# ----- the pace ------------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("limited", [httpx.Response(429), error(29, "Rate limit exceeded", 200)],
                         ids=["HTTP 429", "error 29"])
def test_29_asks_nothing_for_a_minute(client, limited):
    answers = iter([limited, httpx.Response(200, json={})])
    sent = answering(client, lambda request: next(answers))

    assert isinstance(ask(client), Limited)
    client.fake.now += LIMITED_PAUSE_S - 1
    paused = ask(client)
    client.fake.now += 1
    after = ask(client)

    assert isinstance(paused, Unreachable)
    assert after == Answer({})
    assert len(sent) == 2


@pytest.mark.parametrize("first", [error(29, "Rate limit exceeded", 200), httpx.Response(429),
                                   error(10, "Invalid API key", 403), error(26, "Suspended API key", 403)],
                         ids=["error 29", "HTTP 429", "error 10", "error 26"])
def test_asks_waiting_their_turn_send_nothing_once_last_fm_says_stop(client, first):
    """8 at once: 4 go out, 4 wait their turn. The first answer is a 29 (or a refusal) - the 3 already under way
    can't be called back, but not one of the 4 waiting may go out after it: each is the pause, or the refusal."""
    began: list[float] = []
    stopped_at: list[float] = []

    async def handler(request):
        began.append(client.fake.now)
        if len(began) == 1:
            await client.fake.sleep(0.1)
            stopped_at.append(client.fake.now)
            return first
        await client.fake.sleep(0.6)
        return httpx.Response(200, json={})

    sent = answering(client, handler)
    outcomes = asyncio.run(client.fake.run(*(client.ask("artist.getinfo", {"artist": str(n)}) for n in range(8))))

    assert len(sent) == IN_FLIGHT
    assert all(at < stopped_at[0] for at in began)
    waiting = outcomes[IN_FLIGHT:]
    if first.status_code == 403:
        assert all(outcome is client.refusal for outcome in waiting) and client.state() == "refused"
    else:
        assert waiting == [Unreachable("paused: Last.fm asked deadwax to slow down")] * 4


def test_asks_waiting_their_turn_send_nothing_once_the_key_is_removed(client, monkeypatch):
    """The key removed in Server settings while 4 wait their turn: none of them goes out with it."""
    began: list[float] = []

    async def handler(request):
        began.append(client.fake.now)
        if len(began) == 1:
            await client.fake.sleep(0.1)
            monkeypatch.setattr(Config, "LASTFM_API_KEY", None)
            return httpx.Response(200, json={})
        await client.fake.sleep(0.6)
        return httpx.Response(200, json={})

    sent = answering(client, handler)
    outcomes = asyncio.run(client.fake.run(*(client.ask("artist.getinfo", {"artist": str(n)}) for n in range(8))))

    assert len(sent) == IN_FLIGHT
    assert outcomes[IN_FLIGHT:] == [Unreachable("LASTFM_API_KEY changed while the request waited")] * 4


# ----- the clock: the pace, the pause and the hold, timed on one that only goes forward -------------------------------

@pytest.mark.parametrize("jump", [3600.0, -3600.0], ids=["set forward an hour", "set back an hour"])
def test_the_pause_after_a_29_is_a_minute_whatever_the_wall_clock_does(client, jump):
    answers = iter([error(29, "Rate limit exceeded", 200), httpx.Response(200, json={})])
    sent = answering(client, lambda request: next(answers))

    assert isinstance(ask(client), Limited)
    client.fake.wall_offset += jump
    client.fake.now += LIMITED_PAUSE_S - 1
    paused = ask(client)
    client.fake.now += 1
    after = ask(client)

    assert paused == Unreachable("paused: Last.fm asked deadwax to slow down")
    assert after == Answer({})
    assert len(sent) == 2


def test_the_pace_holds_whatever_the_wall_clock_does(client):
    """5 begun in one second, then the wall clock set back an hour: a second later the next one goes out - on the
    wall clock those 5 would be an hour in the future, and every ask busy until it passed."""
    began: list[float] = []

    def handler(request):
        began.append(client.fake.now)
        return httpx.Response(200, json={})

    answering(client, handler)
    for n in range(PER_SECOND):
        ask(client, artist=str(n))
    client.fake.wall_offset -= 3600
    client.fake.now += 1

    [outcome] = asyncio.run(client.fake.run(client.ask("artist.getinfo", {"artist": "next"})))

    assert outcome == Answer({})
    assert began == [START] * PER_SECOND + [START + 1]


@pytest.mark.parametrize("jump", [3 * 3600.0, -3 * 3600.0], ids=["set forward", "set back"])
def test_a_refusal_is_held_an_hour_whatever_the_wall_clock_does_and_says_its_wall_time(client, jump):
    sent = answering(client, lambda request: error(10, "Invalid API key", 403))

    refused = ask(client)
    client.fake.wall_offset += jump
    client.fake.now += 3599
    held = ask(client)
    state = client.state()
    client.fake.now += 1
    state_after_the_hour = client.state()
    ask(client)

    assert refused.at == WALL
    assert held is refused and state == "refused"
    assert state_after_the_hour == "on"
    assert len(sent) == 2


def starts_and_overlap(client, asks: int, latency: float):
    """`asks` asks at once, each answered after `latency` seconds: when each request began, how many were ever under
    way together, and what each ask came to."""
    began: list[float] = []
    under_way = [0, 0]

    async def handler(request):
        began.append(client.fake.now)
        under_way[0] += 1
        under_way[1] = max(under_way)
        try:
            await client.fake.sleep(latency)
        finally:
            under_way[0] -= 1
        return httpx.Response(200, json={})

    answering(client, handler)
    outcomes = asyncio.run(client.fake.run(*(client.ask("artist.getinfo", {"artist": str(n)}) for n in range(asks))))
    return began, under_way[1], outcomes


def most_in_a_second(began: list[float]) -> int:
    return max(sum(1 for later in began if 0 <= later - start < 1.0) for start in began)


def test_never_more_than_5_begin_in_a_second(client):
    began, _, outcomes = starts_and_overlap(client, asks=12, latency=0.0)

    assert most_in_a_second(began) == PER_SECOND
    assert len(began) >= 10


def test_never_more_than_4_under_way(client):
    began, most, outcomes = starts_and_overlap(client, asks=8, latency=0.6)

    assert most == IN_FLIGHT
    assert most_in_a_second(began) <= PER_SECOND


def test_an_ask_that_gets_no_turn_in_2_s_is_busy(client):
    began, _, outcomes = starts_and_overlap(client, asks=20, latency=0.0)

    busy = [outcome for outcome in outcomes if outcome == Unreachable("busy")]
    assert len(busy) == 20 - len(began)
    assert busy and len(began) <= 3 * PER_SECOND


def test_a_redirect_is_never_followed(client):
    def handler(request):
        if request.url.path.endswith("/elsewhere"):
            return httpx.Response(200, json={"artist": {}})
        return httpx.Response(302, headers={"Location": "https://ws.audioscrobbler.com/elsewhere"})

    sent = answering(client, handler)

    assert isinstance(ask(client), Unreachable)
    assert len(sent) == 1


def test_an_answer_over_512_kb_is_refused_before_it_is_read_whole(client):
    piece = b"x" * (64 * 1024)
    read = [0]

    async def pieces():
        for _ in range(20):
            read[0] += 1
            yield piece

    answering(client, lambda request: httpx.Response(200, content=pieces()))

    outcome = ask(client)

    assert isinstance(outcome, Unreachable)
    assert read[0] <= MAX_BYTES // len(piece) + 1


def test_an_answer_of_512_kb_is_read(client):
    body = b'{"pad":"' + b"x" * (MAX_BYTES - 10) + b'"}'
    assert len(body) == MAX_BYTES
    answering(client, lambda request: httpx.Response(200, content=body))

    assert isinstance(ask(client), Answer)


# ----- the key never leaks -------------------------------------------------------------------------------------------

def _raises(kind):
    def handler(request):
        raise kind(f"couldn't reach {request.url}", request=request)
    return handler


def _raises_plain(request):
    raise RuntimeError(f"something broke asking {request.url}")


ECHOES = {
    "answer": lambda request: httpx.Response(200, json={"artist": {"name": "Tame Impala"}}),
    "not known": lambda request: error(6, f"no such artist for {request.url}"),
    "refused 10": lambda request: error(10, f"Invalid API key {KEY}", 403),
    "refused 26": lambda request: error(26, f"Suspended API key: {request.url}", 403),
    "limited 29": lambda request: error(29, f"Rate limit exceeded for {KEY}", 200),
    "limited 429": lambda request: httpx.Response(429, text=f"slow down {KEY}"),
    "error 8": lambda request: error(8, f"Operation failed {request.url}", 500),
    "5xx": lambda request: httpx.Response(503, text=f"<html>{request.url}</html>"),
    "not JSON": lambda request: httpx.Response(200, text=f"<html>{request.url}</html>"),
    "redirect": lambda request: httpx.Response(302, headers={"Location": f"https://elsewhere.example/?k={KEY}"}),
    "too big": lambda request: httpx.Response(200, content=b"x" * (MAX_BYTES + 1)),
    "connect error": _raises(httpx.ConnectError),
    "timeout": _raises(httpx.ReadTimeout),
    "a fault": _raises_plain,
}


@pytest.mark.parametrize("name", list(ECHOES))
def test_the_key_appears_nowhere_whatever_last_fm_answers(client, app, caplog, name):
    caplog.set_level(logging.DEBUG)
    sent = answering(client, ECHOES[name])
    _, before = recent_log()

    outcome = ask(client)

    assert len(sent) == 1 and KEY in str(sent[0].url)
    captured = [
        repr(outcome), str(outcome),
        *(record.getMessage() for record in caplog.records),
        caplog.text,
        *(json.dumps(line) for line in recent_log()[0] if line["seq"] > before),
        json.dumps(asyncio.run(settings())),
        app.get("/deadwax/settings").text,
        app.get("/deadwax/me").text,
    ]
    assert not [text for text in captured if KEY in text]


def test_the_settings_row_never_shows_the_key(client):
    row = next(row for group in asyncio.run(settings())["groups"] for row in group["settings"]
               if row["key"] == "LASTFM_API_KEY")

    assert row["secret"] is True and row["value"] == "set"
    assert row["env_value"] is None
