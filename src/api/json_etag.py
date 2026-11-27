"""
JSON with an ETag (v0.9.20's library pattern), shared by the routes that send big answers that are usually
unchanged since the last look: src/routes/library.py's scan, and (2.0.0-player.59) the app's whole album list,
src/routes/navidrome.py's /album_index. Moved here from library.py unchanged.

(2.1.47) And the same answer KEPT: `pack()` is the body encoded, hashed and gzipped once - made in a worker
thread by whoever keeps it - and `answer_packed()` sends what was kept, so an answer that hasn't changed costs
the event loop a comparison rather than megabytes of JSON. See notes/performance.md "The scan's answer, kept".
"""

import asyncio
import gzip
import hashlib
import json

from fastapi import Request, Response

#? what CompressText (src/api/app.py) compresses at, so a kept answer is the size it always was on the wire
PACK_LEVEL = 6


def json_with_etag(request: Request, payload: dict, headers: dict | None = None) -> Response:
    """
    JSON with an ETag, answered 304 when the browser already holds this exact body (v0.9.20).

    For big payloads that are usually unchanged since the last visit: with `no-cache` the browser
    revalidates every time and, on a 304, hands the page its cached copy - no body crosses the
    network at all. The server still does the work (a warm scan is ~70ms on a thousand albums);
    what is saved is the transfer, which on a phone over a LAN was the wait.

    `headers` go on the 304 as well, and that is how anything that changes on every answer
    reaches the page without changing the body: the browser freshens its stored copy's headers
    from the 304 (RFC 9111 4.3.4). See library.py's _SCAN_HEADERS.
    """
    body = json.dumps(payload, separators=(",", ":"), default=str).encode()
    etag = '"' + hashlib.blake2b(body, digest_size=12).hexdigest() + '"'
    headers = {**(headers or {}), "ETag": etag, "Cache-Control": "no-cache"}
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers=headers)
    return Response(body, media_type="application/json", headers=headers)


def pack(payload: dict) -> tuple[str, bytes]:
    """
    A payload as json_with_etag() would send it, made once to be kept: its ETag (of the very same bytes, so
    a browser's stored copy from before 2.1.47 still answers 304) and the body gzipped.

    Kept gzipped and only gzipped: a thousand albums' scan is megabytes as JSON and a twentieth of that
    packed, every browser and the iPhone app accept gzip, and a 304 needs no body at all. This is the
    megabytes of work - call it through asyncio.to_thread, never on the event loop.
    """
    body = json.dumps(payload, separators=(",", ":"), default=str).encode()
    etag = '"' + hashlib.blake2b(body, digest_size=12).hexdigest() + '"'
    #? mtime=0: the same body packs to the same bytes whenever it is packed
    return etag, gzip.compress(body, PACK_LEVEL, mtime=0)


async def answer_packed(request: Request, etag: str, packed: bytes, headers: dict | None = None) -> Response:
    """
    What pack() made, answered as json_with_etag() answers: a 304 when the asker holds this body, else the
    body - gzipped as it was kept when the asker accepts gzip (CompressText leaves a response that names its
    own Content-Encoding alone), unpacked in a worker thread for the rare one that doesn't.
    """
    headers = {**(headers or {}), "ETag": etag, "Cache-Control": "no-cache", "Vary": "Accept-Encoding"}
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers=headers)
    #? the test Starlette's GZipMiddleware makes of the same header
    if "gzip" in request.headers.get("accept-encoding", ""):
        return Response(packed, media_type="application/json", headers={**headers, "Content-Encoding": "gzip"})
    return Response(await asyncio.to_thread(gzip.decompress, packed), media_type="application/json", headers=headers)
