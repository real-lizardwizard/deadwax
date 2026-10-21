"""
JSON with an ETag (v0.9.20's library pattern), shared by the routes that send big answers that are usually
unchanged since the last look: src/routes/library.py's scan, and (2.0.0-player.59) the app's whole album list,
src/routes/navidrome.py's /album_index. Moved here from library.py unchanged.
"""

import hashlib
import json

from fastapi import Request, Response


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
