"""
The event log's stream: it has to OPEN the moment the page asks for it, and every line meant for
the page has to arrive on it, wherever it was logged from.

The page waits for it to open before pinging, because the MusicBrainz ping writes a line to the
log and the stream keeps no history - a line logged before the page is listening is gone.
Starlette's gzip holds a response's headers back until the first chunk of its body, whatever the
content type, so a stream whose first chunk was a keepalive 15s away stayed shut for 15s. Found
in the audit after v0.9.20 added the gzip; the stream now says something as soon as it connects.

Driven through the whole app, not the route alone, because the middleware is what held it.
"""

import asyncio
import json
import logging

from src.api.app import start
from src.logger import SSEHandler, register_sse_client, unregister_sse_client


def test_the_log_stream_opens_at_once_through_every_middleware():
    app = start()  # no lifespan: nothing connects to anything
    sent = []

    async def receive():
        await asyncio.sleep(3600)  # the page never hangs up during the test
        return {"type": "http.disconnect"}

    async def send(message):
        sent.append(message)

    scope = {
        "type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": "GET",
        "scheme": "http", "path": "/deadwax/interface_logs/interface_logs", "root_path": "",
        "raw_path": b"/deadwax/interface_logs/interface_logs", "query_string": b"",
        "headers": [(b"host", b"test"), (b"accept-encoding", b"gzip")],
        "server": ("test", 80), "client": ("page", 1),
    }

    async def go():
        stream = asyncio.create_task(app(scope, receive, send))
        try:
            #? well inside the 15s keepalive it would otherwise have waited for
            for _ in range(100):
                if any(m["type"] == "http.response.body" for m in sent):
                    break
                await asyncio.sleep(0.01)
        finally:
            stream.cancel()
            await asyncio.gather(stream, return_exceptions=True)

    asyncio.run(go())

    assert sent, "the stream sent nothing within a second"
    assert sent[0]["type"] == "http.response.start" and sent[0]["status"] == 200
    headers = dict(sent[0]["headers"])
    assert headers[b"content-type"].startswith(b"text/event-stream")
    assert b"content-encoding" not in headers, "an event stream must never be gzipped"
    assert sent[1]["body"] == b":\n\n"


def test_a_line_logged_from_a_worker_thread_reaches_the_page():
    """
    Everything run through asyncio.to_thread logs from a thread with no event loop of its own -
    the retag, the delete, the download cleanup that names what it removed. The handler used to
    ask asyncio.get_event_loop() for one there, which raised or found one that wasn't running,
    and the line was dropped without a word. It hands the line to the streams' own loop now.
    """
    log = logging.getLogger("deadwax-test-sse")
    log.setLevel(logging.INFO)
    log.propagate = False
    handler = SSEHandler()
    log.addHandler(handler)

    async def go():
        queue = register_sse_client()
        try:
            log.info("from the loop", extra={"frontend": True})
            await asyncio.to_thread(log.info, "from a worker thread", extra={"frontend": True})
            await asyncio.sleep(0.05)
            return [json.loads(queue.get_nowait())["event_content"] for _ in range(queue.qsize())]
        finally:
            unregister_sse_client(queue)

    try:
        assert asyncio.run(go()) == ["from the loop", "from a worker thread"]
    finally:
        log.removeHandler(handler)
