import asyncio
import json
import logging

#? one queue per open event-log stream (routes/interface_logs.py)
sse_clients = set()

#? The event loop those queues belong to, recorded when a stream registers - always from inside
#? the loop. A line logged from a worker thread (anything run through asyncio.to_thread) has no
#? running loop of its own and is handed across to this one. The handler used to fall back on
#? asyncio.get_event_loop() there, which from a worker thread raises or finds a loop that isn't
#? running, and the line was silently dropped (found in the v0.9.26 audit): "re-filed X as Y",
#? "deleted ...", the download cleanup naming what it removed - none of it ever reached the page.
_loop: asyncio.AbstractEventLoop | None = None


def register_sse_client():
    global _loop
    _loop = asyncio.get_running_loop()
    q = asyncio.Queue()
    sse_clients.add(q)
    return q


def unregister_sse_client(q):
    sse_clients.discard(q)


def publish_sse_event(event_json):
    for q in list(sse_clients):
        q.put_nowait(event_json)


class SSEHandler(logging.Handler):
    """Sends the records marked `extra={"frontend": True}` to every open event-log stream."""

    def emit(self, record):
        if not getattr(record, "frontend", False) or not sse_clients:
            return

        event = {"event_type": record.levelname, "event_content": record.getMessage()}
        src = getattr(record, "src", None)
        if src is not None:
            event["src"] = src

        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            loop = _loop
        if loop is None or loop.is_closed():
            return
        loop.call_soon_threadsafe(publish_sse_event, json.dumps(event))


def setup_logging():
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)

    console = logging.StreamHandler()
    console.setFormatter(logging.Formatter('%(levelname)s: %(message)s'))

    logger.handlers = [SSEHandler(), console]
    return logger


def cleanup_logging():
    logger = logging.getLogger()
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
        handler.close()

    logging.shutdown()


if not logging.getLogger().handlers:
    logger = setup_logging()
else:
    logger = logging.getLogger()
