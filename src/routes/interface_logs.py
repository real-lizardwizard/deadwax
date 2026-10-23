import asyncio
import json

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import StreamingResponse

from src.logger import LOG_BOOT, logger, recent_log, register_sse_client, unregister_sse_client
from src.users import current_user, permissions

router = APIRouter()


@router.get("/recent")
async def recent():
    """The page-bound lines kept since deadwax started - the last 500 - oldest first, the number of
    the last one logged, and this run's name. The app's Log page reads this, then opens the stream
    from `last` (2.0.0-player.33). Only what the stream itself sent: nothing more."""
    lines, last = recent_log()
    return {"lines": lines, "last": last, "boot": LOG_BOOT}


def still_allowed(request: Request, user: str) -> bool:
    """
    (2.0.0-player.61 review) Whether the person a stream was opened for may still read the log: their session still
    stands, as the same person, with Settings and the log. The router's guard runs once, as the stream opens - and
    since .61 a session, a role and a permission can all go while it stays open (a reset, a removal, a demotion in
    Navidrome, an unticked box), so the stream asks again before every line and keepalive and closes once the
    answer is no. SYNCHRONOUS (a session is read from SQLite at most every minute, a permissions table that failed
    at most every minute): the stream asks it in a worker thread.
    """
    try:
        return current_user(request) == user and "server" in permissions(request, user)
    except HTTPException:
        return False
    except Exception as e:
        #? a database that can't be read is no answer at all: closed, as every request would be refused (503)
        logger.warning(f"the event stream couldn't check its reader is still let in, so it closed ({type(e).__name__})")
        return False


@router.get("/interface_logs")
async def interface_logs(
    request: Request,
    user: str = Depends(current_user),
    #? the last line the page has: the kept lines after it are sent first (the app's Log page). The
    #? main page sends neither, and gets the stream as it always has: only what is logged from now
    after: int | None = Query(default=None, ge=0),
    boot: str | None = Query(default=None, max_length=64),
):
    async def event_generator():
        logger.info("interface connecting to event stream")
        #? each line once: one kept just before the queue was added can be published to it as well
        client_queue, missed, sent = register_sse_client(after, boot)

        try:
            #? something at once, so the page sees the stream OPEN now rather than at the first
            #? event or keepalive: anything that holds the response back until it has a body -
            #? Starlette's gzip does, whatever the content type, and so do some reverse proxies -
            #? would otherwise keep it shut for up to 15s. The page waits for it before pinging.
            yield ":\n\n"
            for line in missed:
                yield f"data: {json.dumps(line)}\n\n"
            while True:
                try:
                    seq, event = await asyncio.wait_for(client_queue.get(), timeout=15)
                    #? the queue gets each line once, in the order the lines were numbered (handed
                    #? over in order, under the logger's lock), so only what the replay already sent
                    #? can come again: anything above it is new, and the floor never needs moving
                    if seq is not None and seq <= sent:
                        continue
                    chunk = f"data: {event}\n\n"
                except asyncio.TimeoutError:
                    chunk = ":\n\n"  # keepalive
                #? (2.0.0-player.61 review) asked again before anything more goes out - see still_allowed
                if not await asyncio.to_thread(still_allowed, request, user):
                    return
                yield chunk
        finally:
            unregister_sse_client(client_queue)

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            #? (2.0.0-player.65, the 2.0.0 release review) nginx buffers a proxied response by default, so behind
            #? it the Log sat on "Connecting..." - nothing reached the page until a buffer filled. This header is
            #? nginx's own way for a response to ask not to be (proxy_buffering off does it for everything)
            "X-Accel-Buffering": "no",
        },
    )
