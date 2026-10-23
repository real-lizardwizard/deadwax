"""
How src/main.py runs uvicorn (2.0.0-player.65, the 2.0.0 release review).

With no timeout_graceful_shutdown, uvicorn waits for every open request at a stop - and a song playing, or the event
log open, never ends by itself - so `docker stop` SIGKILLed deadwax after its 10 seconds, and the lifespan's teardown
(the poller cancelled, MusicBrainz's saved answers written and closed, every client closed) never ran. These hold the
wait to 5 seconds, inside docker's 10, and that uvicorn then cancels what is still open before the teardown.
"""

import asyncio
import inspect

import uvicorn

from src import main as entry


def test_a_stop_waits_at_most_five_seconds_for_open_requests(monkeypatch):
    made = {}

    class Server:
        def __init__(self, config):
            made["config"] = config

        def run(self):
            made["ran"] = True

    monkeypatch.setattr(entry.Config, "check", lambda: None)
    monkeypatch.setattr(entry, "start", lambda: object())
    monkeypatch.setattr(entry.uvicorn, "Server", Server)

    entry.main()

    assert made["ran"] and made["config"].timeout_graceful_shutdown == 5
    assert entry.GRACEFUL_SHUTDOWN_S < 10, "inside docker's own wait before SIGKILL"


def test_past_the_wait_uvicorn_cancels_what_is_open_and_then_runs_the_teardown():
    """uvicorn's own order (0.40.0, Server.shutdown), which the teardown relies on: the wait is bounded by the
    setting, what is still open is cancelled, and only then is the lifespan's shutdown sent."""
    source = inspect.getsource(uvicorn.Server.shutdown)
    waited = source.index("timeout=self.config.timeout_graceful_shutdown")
    cancelled = source.index("t.cancel(")
    teardown = source.index("await self.lifespan.shutdown()")
    assert waited < cancelled < teardown


def test_an_open_request_is_cancelled_at_the_timeout_and_the_teardown_runs(monkeypatch):
    """A real uvicorn Server, shut down with a request task that never ends: its cancel asked for at the timeout, and
    the lifespan's shutdown sent after that (uvicorn doesn't wait for the cancelled task to unwind first)."""
    config = uvicorn.Config(app=lambda *a: None, timeout_graceful_shutdown=0.2, lifespan="off")
    server = uvicorn.Server(config)
    order = []
    tasks = []

    class Lifespan:
        async def shutdown(self):
            order.append(("teardown", "after the cancel" if tasks[0].cancelling() else "before it"))

    async def go():
        server.lifespan = Lifespan()
        server.servers = []

        async def stream():
            try:
                await asyncio.Event().wait()
            except asyncio.CancelledError:
                order.append("stream cancelled")
                raise

        task = asyncio.create_task(stream())
        tasks.append(task)
        server.server_state.tasks.add(task)
        task.add_done_callback(server.server_state.tasks.discard)
        await server.shutdown()
        await asyncio.gather(task, return_exceptions=True)

    asyncio.run(go())
    assert order == [("teardown", "after the cancel"), "stream cancelled"]
