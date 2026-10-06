import asyncio
import collections
import json
import logging
import secrets
import threading

#? httpx writes every request it makes to its own logger at INFO, with the whole URL, query
#? string and all - and the root logger below sends INFO to the container log that Komodo shows.
#? Two of those query strings hold a secret. Every Navidrome call carries the login as `t` and
#? `s`, a token and its salt, and Navidrome takes the same pair again for as long as the password
#? stands (it keeps no record of salts used), so one logged line is the account. fanart.tv takes
#? its `api_key` in the query too. Warnings and errors still come through. Set here at module
#? level rather than in setup_logging(), which is skipped when something has already given the
#? root logger a handler.
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)

#? one queue per open event-log stream (routes/interface_logs.py)
sse_clients = set()

#? The event loop those queues belong to, recorded when a stream registers - always from inside
#? the loop. A line logged from a worker thread (anything run through asyncio.to_thread) has no
#? running loop of its own and is handed across to this one. The handler used to fall back on
#? asyncio.get_event_loop() there, which from a worker thread raises or finds a loop that isn't
#? running, and the line was silently dropped (found in the v0.9.26 audit): "re-filed X as Y",
#? "deleted ...", the download cleanup naming what it removed - none of it ever reached the page.
_loop: asyncio.AbstractEventLoop | None = None


#? The page-bound lines, kept (2.0.0-player.33): the stream kept no history, so a log opened after
#? something happened was empty - the app's Log page is opened when there is something to look at,
#? which is after it happened. The last LOG_HISTORY lines meant for the page are kept, each exactly
#? as the stream sends it (nothing the stream didn't already send - no secret is kept that wasn't
#? already on the page) plus a server time and a sequence number rising by one per line, so the
#? page can join this history and the stream with no gap and no line twice
#? (GET /deadwax/interface_logs/recent; the stream's `after`). In memory only: it starts empty when
#? deadwax starts, and `LOG_BOOT` names this run, so a page that saw an earlier one's numbers can
#? tell them apart from this one's (they start again at 1).
LOG_HISTORY = 500
LOG_BOOT = secrets.token_hex(6)
_history: collections.deque = collections.deque(maxlen=LOG_HISTORY)
_seq = 0
#? lines are logged from worker threads as well as the loop: the number, the history and the order
#? the streams are handed lines in all change together, under this
_lock = threading.Lock()


def recent_log() -> tuple[list[dict], int]:
    """The page-bound lines kept, oldest first, and the number of the last one logged (0: none yet)."""
    with _lock:
        return list(_history), _seq


def register_sse_client(after: int | None = None, boot: str | None = None):
    """A stream's queue; the kept lines it hasn't had yet, to send first (none without `after`); and
    the number at or below which it has every line (the stream skips a publish it already sent).

    Taken together, with nothing awaited between: every line kept by then is in what is handed back,
    and every line after it is published to the queue (its publishing runs on this loop later), so a
    page that read the history up to `after` and opens a stream from there misses nothing. A line can
    be both (kept on another thread just before the queue was added, published just after); the stream
    sends each number once. `boot` is the run the page's `after` was from: another run's numbers say
    nothing about this one's, so every line kept is new to it.
    """
    global _loop
    _loop = asyncio.get_running_loop()
    q = asyncio.Queue()
    with _lock:
        if after is None:
            missed, floor = [], 0
        elif boot is not None and boot != LOG_BOOT:
            missed, floor = list(_history), 0
        else:
            missed, floor = [line for line in _history if line["seq"] > after], after
        sse_clients.add(q)
    return q, missed, max([floor, *(line["seq"] for line in missed)])


def unregister_sse_client(q):
    sse_clients.discard(q)


def publish_sse_event(event_json, seq=None):
    for q in list(sse_clients):
        q.put_nowait((seq, event_json))


class SSEHandler(logging.Handler):
    """Sends the records marked `extra={"frontend": True}` to every open event-log stream."""

    def emit(self, record):
        global _seq
        if not getattr(record, "frontend", False):
            return

        event = {"event_type": record.levelname, "event_content": record.getMessage()}
        src = getattr(record, "src", None)
        if src is not None:
            event["src"] = src

        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            loop = _loop

        with _lock:
            _seq += 1
            #? the main page reads event_type, event_content and src, and ignores the rest
            event.update(seq=_seq, time=record.created, boot=LOG_BOOT)
            _history.append(event)
            #? handed over inside the lock, so the streams get lines in the order they were numbered
            if sse_clients and loop is not None and not loop.is_closed():
                loop.call_soon_threadsafe(publish_sse_event, json.dumps(event), _seq)


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
