"""
The event log's history (2.0.0-player.33): GET /deadwax/interface_logs/recent, and the stream's `after`.

The stream kept no history, so the app's Log page - opened when there is something to look at, which is
after it happened - would have been empty. src/logger.py now keeps the last LOG_HISTORY (500) lines meant
for the page: exactly what the stream sends, plus a server time, this run's name (`boot`) and a sequence
number rising by one per line, from whichever thread logged it. The page reads /recent, then opens the
stream from the last number it has (`?after=`), and the stream sends the kept lines after that first -
taken together with adding the stream's queue, so nothing falls between the two - and each number once.

- /recent's shape; the bound (501 lines -> 500, the oldest gone); numbers rising across threads; a line
  logged from a worker thread there; nothing without `frontend: True`; gzipped like any text route; a GET,
  so the same-origin guard (writes only) passes it from anywhere, as it passes the stream.
- The stream: every event carrying its number; `after` sending the missed lines first, each once; another
  run's `after` (deadwax restarted) taken as nothing seen; the main page's stream - no `after` - only what is
  logged from now, as it always was.

Through the whole app start() builds (no lifespan: nothing connects), a dedicated logger carrying the real
SSEHandler, as test_log_stream.py does.
"""

import asyncio
import json
import logging
import threading

import pytest
from fastapi.testclient import TestClient

from src import logger as log_module
from src.api.app import start
from src.logger import LOG_BOOT, LOG_HISTORY, SSEHandler

RECENT = "/deadwax/interface_logs/recent"
STREAM = "/deadwax/interface_logs/interface_logs"


@pytest.fixture
def log():
    """A logger carrying the real handler, and the history emptied (the numbers carry on: they only rise)."""
    log_module._history.clear()
    one = logging.getLogger("deadwax-test-history")
    one.setLevel(logging.INFO)
    one.propagate = False
    handler = SSEHandler()
    one.addHandler(handler)
    yield one
    one.removeHandler(handler)
    log_module._history.clear()


@pytest.fixture
def client():
    return TestClient(start())


def test_recent_answers_the_lines_kept_their_number_and_the_run(log, client):
    log.info("searching slskd for Portishead Dummy", extra={"frontend": True, "src": "SLSKD"})
    log.warning("no cover on the Archive", extra={"frontend": True})
    answer = client.get(RECENT)
    assert answer.status_code == 200
    body = answer.json()
    assert set(body) == {"lines", "last", "boot"}
    assert body["boot"] == LOG_BOOT
    first, second = body["lines"]
    assert first["event_type"] == "INFO" and first["event_content"] == "searching slskd for Portishead Dummy"
    assert first["src"] == "SLSKD"
    assert second["event_type"] == "WARNING" and "src" not in second
    assert second["seq"] == first["seq"] + 1 and body["last"] == second["seq"]
    assert all(isinstance(line["time"], float) and line["boot"] == LOG_BOOT for line in body["lines"])


def test_the_history_keeps_the_last_500_lines(log, client):
    assert LOG_HISTORY == 500
    for n in range(LOG_HISTORY + 1):
        log.info(f"line {n}", extra={"frontend": True})
    lines = client.get(RECENT).json()["lines"]
    assert len(lines) == 500
    assert lines[0]["event_content"] == "line 1", "the oldest went"
    assert lines[-1]["event_content"] == "line 500"


def test_the_numbers_rise_by_one_whichever_thread_logged(log, client):
    def many(name):
        for n in range(50):
            log.info(f"{name} {n}", extra={"frontend": True})

    threads = [threading.Thread(target=many, args=(f"t{i}",)) for i in range(4)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    lines = client.get(RECENT).json()["lines"]
    numbers = [line["seq"] for line in lines]
    assert len(numbers) == 200
    assert numbers == list(range(numbers[0], numbers[0] + 200)), "one apart, in the order kept"
    for name in ("t0", "t1", "t2", "t3"):
        own = [line["event_content"] for line in lines if line["event_content"].startswith(name + " ")]
        assert own == [f"{name} {n}" for n in range(50)], "each thread's own lines in its own order"


def test_a_line_logged_from_a_worker_thread_is_kept(log, client):
    async def go():
        await asyncio.to_thread(log.info, "re-filed Third rip as Third (2008)", extra={"frontend": True})

    asyncio.run(go())
    assert [line["event_content"] for line in client.get(RECENT).json()["lines"]] == ["re-filed Third rip as Third (2008)"]


def test_nothing_without_frontend_is_kept(log, client):
    log.info("interface connecting to event stream")
    log.error("a traceback for the container log only", extra={"frontend": False})
    log.info("for the page", extra={"frontend": True})
    assert [line["event_content"] for line in client.get(RECENT).json()["lines"]] == ["for the page"]


def test_recent_is_gzipped_and_a_get_from_anywhere(log, client):
    for n in range(40):
        log.info(f"a long enough line to be worth compressing, number {n}", extra={"frontend": True})
    answer = client.get(RECENT, headers={"accept-encoding": "gzip", "origin": "http://elsewhere.example"})
    assert answer.status_code == 200, "a read: the same-origin guard is for writes"
    assert answer.headers.get("content-encoding") == "gzip"
    assert len(answer.json()["lines"]) == 40


def stream(query, during):
    """The stream through the whole app: open it, run `during()` once it has opened, and gather the events
    it sends for a moment after."""
    app = start()
    sent = []

    async def receive():
        await asyncio.sleep(3600)
        return {"type": "http.disconnect"}

    async def send(message):
        sent.append(message)

    raw = STREAM.encode()
    scope = {
        "type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": "GET",
        "scheme": "http", "path": STREAM, "root_path": "", "raw_path": raw, "query_string": query.encode(),
        "headers": [(b"host", b"test")], "server": ("test", 80), "client": ("page", 1),
    }

    async def go():
        task = asyncio.create_task(app(scope, receive, send))
        try:
            for _ in range(100):
                if any(m["type"] == "http.response.body" for m in sent):
                    break
                await asyncio.sleep(0.01)
            await during()
            await asyncio.sleep(0.1)
        finally:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    asyncio.run(go())
    body = b"".join(m.get("body", b"") for m in sent if m["type"] == "http.response.body").decode()
    return [json.loads(chunk[len("data: "):]) for chunk in body.split("\n\n") if chunk.startswith("data: ")]


def test_every_event_on_the_stream_carries_its_number(log):
    async def during():
        log.info("from the loop", extra={"frontend": True})
        await asyncio.to_thread(log.info, "from a worker thread", extra={"frontend": True})

    events = stream("", during)
    assert [event["event_content"] for event in events] == ["from the loop", "from a worker thread"]
    assert events[1]["seq"] == events[0]["seq"] + 1 and all(event["boot"] == LOG_BOOT for event in events)


def test_the_main_pages_stream_sends_only_what_is_logged_from_now(log):
    log.info("before the page looked", extra={"frontend": True})

    async def during():
        log.info("after", extra={"frontend": True})

    assert [event["event_content"] for event in stream("", during)] == ["after"]


def test_a_stream_from_after_sends_the_missed_lines_first_and_each_once(log):
    for n in range(5):
        log.info(f"kept {n}", extra={"frontend": True})
    lines, last = log_module.recent_log()
    seen = lines[2]["seq"]  # the page has up to "kept 2"

    async def during():
        log.info("live", extra={"frontend": True})

    events = stream(f"after={seen}&boot={LOG_BOOT}", during)
    assert [event["event_content"] for event in events] == ["kept 3", "kept 4", "live"]
    numbers = [event["seq"] for event in events]
    assert numbers == sorted(set(numbers)), "no number twice"


def test_a_line_published_after_it_was_replayed_is_not_sent_twice(log):
    """A line kept on another thread just before the stream's queue is added is in the replay AND, its
    publishing running on the loop a moment later, in the queue. Sent once."""
    async def go():
        log.info("both", extra={"frontend": True})  # its publish is scheduled, not yet run
        queue, missed, floor = log_module.register_sse_client(0, LOG_BOOT)
        try:
            await asyncio.sleep(0.05)
            queued = [queue.get_nowait() for _ in range(queue.qsize())]
        finally:
            log_module.unregister_sse_client(queue)
        return missed, floor, queued

    #? with a stream already open, so the handler publishes
    async def with_one_open():
        other, _, _ = log_module.register_sse_client()
        try:
            return await go()
        finally:
            log_module.unregister_sse_client(other)

    missed, floor, queued = asyncio.run(with_one_open())
    assert [line["event_content"] for line in missed][-1:] == ["both"]
    assert floor == missed[-1]["seq"]
    assert [seq for seq, _ in queued] == [floor], "published to the queue too - which the stream skips at or below floor"


def test_another_runs_after_is_taken_as_nothing_seen(log):
    log.info("since the restart", extra={"frontend": True})

    async def during():
        log.info("live", extra={"frontend": True})

    events = stream("after=999999&boot=an-earlier-run", during)
    assert [event["event_content"] for event in events] == ["since the restart", "live"]


def test_the_stream_sends_a_number_it_already_replayed_only_once(log, monkeypatch):
    """The other half of the rule above: whatever the queue is handed at or below what the replay sent
    (the line kept just before the queue was added, published just after) the stream skips."""
    from src.routes import interface_logs as route

    for n in range(3):
        log.info(f"kept {n}", extra={"frontend": True})
    real = route.register_sse_client

    def twice(after, boot):
        queue, missed, floor = real(after, boot)
        for line in missed:  # each replayed line published again, as the race would
            queue.put_nowait((line["seq"], json.dumps(line)))
        return queue, missed, floor

    monkeypatch.setattr(route, "register_sse_client", twice)
    first = log_module.recent_log()[0][0]["seq"]

    async def during():
        log.info("live", extra={"frontend": True})

    events = stream(f"after={first}&boot={LOG_BOOT}", during)
    assert [event["event_content"] for event in events] == ["kept 1", "kept 2", "live"]


def status(query):
    """The status the stream answers `query` with, through the whole app - asked directly, so an answer
    that IS a stream (endless) is read for its start and let go rather than waited out."""
    app = start()
    started = []

    async def receive():
        await asyncio.sleep(3600)
        return {"type": "http.disconnect"}

    async def send(message):
        if message["type"] == "http.response.start":
            started.append(message["status"])

    scope = {
        "type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": "GET",
        "scheme": "http", "path": STREAM, "root_path": "", "raw_path": STREAM.encode(),
        "query_string": query.encode(), "headers": [(b"host", b"test")], "server": ("test", 80),
        "client": ("page", 1),
    }

    async def go():
        task = asyncio.create_task(app(scope, receive, send))
        try:
            for _ in range(200):
                if started:
                    break
                await asyncio.sleep(0.01)
        finally:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    asyncio.run(go())
    return started[0]


def test_the_streams_query_is_bounded():
    """`after` a line number (0 or more), `boot` a run's name (deadwax's are 12 characters; at most 64 taken):
    anything else is refused before a stream is opened - and the bounds themselves are taken."""
    assert status("after=-1") == 422
    assert status(f"after=0&boot={'x' * 65}") == 422
    assert status("after=three") == 422
    assert status(f"after=0&boot={'x' * 64}") == 200


def test_the_bounds_themselves_are_taken(log):
    """0 and a 64-character run name are inside the bounds: another run's name, so every kept line is sent."""
    log.info("kept", extra={"frontend": True})

    async def during():
        log.info("live", extra={"frontend": True})

    assert [event["event_content"] for event in stream(f"after=0&boot={'x' * 64}", during)] == ["kept", "live"]
    assert [event["event_content"] for event in stream(f"after=0&boot={LOG_BOOT}", during)] == ["kept", "live", "live"]
