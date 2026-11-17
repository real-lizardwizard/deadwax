"""
The server's answers the iPhone app's event log reads (Phase 8, slice 9 - notes/ios.md "The event log on the phone"):
`GET /deadwax/interface_logs/recent`'s body and the first frames of `GET /deadwax/interface_logs/interface_logs` as the
real routes send them - made through the whole app start() builds (no lifespan: nothing connects), logins off, a
logger carrying the real SSEHandler, its lines' times fixed and the run named for the file (src/logger.py LOG_BOOT,
patched for the run and put back). Written to

  ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/log/stream.json

which DeadwaxCoreTests' EventStreamTests reads as the phone does - the history with RecentLog, the stream's bytes
through EventStream.Lines and Frames, every message as a LogLine, each case's query from what the history ends with -
and tests/test_ios_event_log.py holds to what this makes now: so a change to what the server sends fails there until
the file is written again (`.venv/bin/python ios/scripts/log_stream_answers.py`) and the phone's tests run on it.

Each stream is held open only long enough to send what it has: never the 15 s keepalive, which is the same ":" the
stream opens with (tests/test_ios_event_log.py pins its 15).

Every line here is invented; text outside ASCII is written as JSON escapes, so the file holds none raw.
"""

import asyncio
import json
import logging
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from fastapi.testclient import TestClient  # noqa: E402

from src import logger as log_module  # noqa: E402
from src.api.app import start  # noqa: E402
from src.config import Config  # noqa: E402
from src.logger import SSEHandler  # noqa: E402
from src.routes import interface_logs as route_module  # noqa: E402

FIXTURE = ROOT / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "log" / "stream.json"
RECENT = "/deadwax/interface_logs/recent"
STREAM = "/deadwax/interface_logs/interface_logs"
BOOT = "d00dfeed0001"
OTHER = "0123456789ab"

#? what deadwax had logged before the page looked: (level, words, src, time)
KEPT = [
    (logging.INFO, 'Searching Soulseek for "Dummy" by Portishead', "SLSKD", 1763300000.25),
    (logging.WARNING, "no cover on the Archive for this pressing", None, 1763300001.5),
    (logging.ERROR, "slskd answered 409: it isn't logged in to Soulseek", "SLSKD", 1763300002.125),
    (logging.INFO, "Filed 11 tracks into Portishead/Dummy (1994) - Sigur Rós next ♪", "organizer", 1763300003.0),
]
#? what is logged once the stream is open
LIVE = [
    (logging.INFO, "download 41 finished", "poller", 1763300010.75),
    (logging.CRITICAL, "the database can't be written", None, 1763300011.0),
    (logging.WARNING, "a candidate left out: its folder holds no audio", "matching", 1763300012.5),
]


def _say(handler: SSEHandler, level: int, words: str, src, created: float) -> None:
    """One line meant for the page, through the real handler, at a fixed time."""
    record = logging.LogRecord("deadwax-ios-log", level, __file__, 0, words, None, None)
    record.created = created
    record.frontend = True
    if src is not None:
        record.src = src
    handler.handle(record)


def _stream(query: str, during) -> dict:
    """The stream through the whole app: open it, run `during()` once it has said its first frame, and keep what it
    sends for a moment after - its status, the headers the phone reads, and its body as sent."""
    app = start()
    sent = []

    async def receive():
        await asyncio.sleep(3600)
        return {"type": "http.disconnect"}

    async def send(message):
        sent.append(message)

    scope = {
        "type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": "GET",
        "scheme": "http", "path": STREAM, "root_path": "", "raw_path": STREAM.encode(),
        "query_string": query.encode(),
        "headers": [(b"host", b"deadwax.test"), (b"accept", b"text/event-stream"), (b"accept-encoding", b"gzip")],
        "server": ("deadwax.test", 8080), "client": ("phone", 1),
    }

    async def go():
        task = asyncio.create_task(app(scope, receive, send))
        try:
            for _ in range(200):
                if any(m["type"] == "http.response.body" for m in sent):
                    break
                await asyncio.sleep(0.01)
            await during()
            await asyncio.sleep(0.2)
        finally:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    asyncio.run(go())
    start_message = next(m for m in sent if m["type"] == "http.response.start")
    headers = {name.decode().lower(): value.decode() for name, value in start_message["headers"]}
    body = b"".join(m.get("body", b"") for m in sent if m["type"] == "http.response.body").decode()
    return {
        "status": start_message["status"],
        "headers": {name: headers.get(name) for name in ("content-type", "cache-control", "x-accel-buffering",
                                                          "content-encoding")},
        "body": body,
    }


def answers() -> dict:
    """Each case: the history as /recent sends it, then a stream asked as the phone asks it, its first frames."""
    saved = (log_module.LOG_BOOT, route_module.LOG_BOOT, log_module._seq, list(log_module._history), Config.AUTH_MODE)
    log = logging.getLogger("deadwax-ios-log")
    log.setLevel(logging.INFO)
    log.propagate = False
    handler = SSEHandler()
    log.addHandler(handler)
    try:
        log_module.LOG_BOOT = route_module.LOG_BOOT = BOOT
        Config.AUTH_MODE = "off"
        log_module._seq = 0
        log_module._history.clear()
        for level, words, src, created in KEPT:
            _say(handler, level, words, src, created)
        recent = TestClient(start()).get(RECENT)
        assert recent.status_code == 200, recent.text
        kept = recent.json()

        def logs(lines):
            async def during():
                for level, words, src, created in lines:
                    _say(handler, level, words, src, created)
            return during

        cases = []
        #? the phone's own way: the history, then the stream from where it ends - nothing again, the live line
        query = f"after={kept['last']}&boot={kept['boot']}"
        cases.append({"name": "from where the history ends", "query": query, **_stream(query, logs(LIVE[:1]))})
        #? from a line below the last: the kept lines after it first, then what is new
        query = f"after=2&boot={BOOT}"
        cases.append({"name": "from a line held below the last", "query": query, **_stream(query, logs(LIVE[1:2]))})
        #? another run's number (deadwax restarted since): every kept line
        query = f"after=3&boot={OTHER}"
        cases.append({"name": "another run's number", "query": query, **_stream(query, logs([]))})
        #? neither: what is logged from now
        cases.append({"name": "from now", "query": "", **_stream("", logs(LIVE[2:]))})
        last = TestClient(start()).get(RECENT).json()
        return {
            "made_from": "src/routes/interface_logs.py and src/logger.py (ios/scripts/log_stream_answers.py)",
            "boot": BOOT,
            "recent": recent.text,
            "cases": cases,
            "recentAfter": json.dumps(last, separators=(",", ":")),
        }
    finally:
        log.removeHandler(handler)
        log_module.LOG_BOOT, route_module.LOG_BOOT, log_module._seq, history, Config.AUTH_MODE = saved
        log_module._history.clear()
        log_module._history.extend(history)


def text() -> str:
    return json.dumps(answers(), indent=1, ensure_ascii=True) + "\n"


if __name__ == "__main__":
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(text(), encoding="utf-8")
    print(f"wrote {FIXTURE.relative_to(ROOT)}")
