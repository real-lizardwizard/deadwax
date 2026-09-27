import asyncio

from fastapi import APIRouter
from fastapi.responses import StreamingResponse

from src.logger import logger, register_sse_client, unregister_sse_client

router = APIRouter()


@router.get("/interface_logs")
async def interface_logs():
    async def event_generator():
        logger.info("interface connecting to event stream")
        client_queue = register_sse_client()

        try:
            #? something at once, so the page sees the stream OPEN now rather than at the first
            #? event or keepalive: anything that holds the response back until it has a body -
            #? Starlette's gzip does, whatever the content type, and so do some reverse proxies -
            #? would otherwise keep it shut for up to 15s. The page waits for it before pinging.
            yield ":\n\n"
            while True:
                try:
                    event = await asyncio.wait_for(client_queue.get(), timeout=15)
                    yield f"data: {event}\n\n"
                except asyncio.TimeoutError:
                    yield ":\n\n"  # keepalive
        finally:
            unregister_sse_client(client_queue)

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
        },
    )
