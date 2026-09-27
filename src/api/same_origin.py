"""
Refuse writes that another website asks for (v1.0.1).

deadwax has no login, so anything that can reach it can use it - which is the documented
trade-off. What that trade-off never meant was "any web page the owner happens to have open".
A page elsewhere can make the browser send a POST to deadwax's address, and before this nothing
stood in the way: FastAPI reads a JSON body even when no Content-Type says it is JSON, and the
routes that take no body at all (cancel, retry, clear, rescan) accept a plain form post. So a
page that knew the LAN address could delete an album.

A cookie wouldn't have fixed it either, and won't once logins exist. Browsers treat every port
on one host as the SAME site, so Navidrome, slskd, the NAS's own admin page and deadwax are all
"same-site" to each other, and a SameSite cookie rides along on a request from any of them.

What does work is the header browsers attach to every cross-origin POST and cannot be told to
forge: Origin. A write whose Origin names another scheme://host:port than the one deadwax is
being reached at is refused. A request with no Origin and no Referer at all is not a browser
acting for a web page - curl, a script, a health check - and is let through, because those were
never the threat and there is no login to protect yet.

The comparison is on host and port, not scheme: behind a proxy that terminates TLS, the page is
https://music.example but deadwax itself is spoken to over plain http. A proxy that REWRITES the
Host header (nginx does by default) makes every write look foreign; X-Forwarded-Host is honoured
when it is set, X-Forwarded-Port fills in a port the Host left out, and TRUSTED_ORIGINS names any
other origin to accept. None of those headers can be set by a web page on a cross-origin request
without a CORS preflight, which deadwax never grants, so trusting them costs nothing here. That setting is read from
the environment only - it guards the settings tab's own save, so a bad value saved there could
never be undone from there.

PLAIN ASGI, like the other middleware in app.py - see its note on BaseHTTPMiddleware.
"""

import json
import os
from urllib.parse import urlsplit

from src.logger import logger

#? Methods that change nothing. Everything else is a write and gets checked.
SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})

DEFAULT_PORTS = {"http": 80, "https": 443}


def _split_host(value: str) -> tuple[str, int | None] | None:
    """`host[:port]` as (lowercase host, port or None). IPv6 keeps its brackets off."""
    value = value.strip().lower()
    if not value:
        return None
    if value.startswith("["):
        end = value.find("]")
        if end == -1:
            return None
        host, rest = value[1:end], value[end + 1:]
        port_text = rest[1:] if rest.startswith(":") else ""
    else:
        host, _, port_text = value.partition(":")
    if not port_text:
        return host, None
    if not port_text.isdigit():
        return None
    return host, int(port_text)


def _origin_of(url: str) -> tuple[str, int] | None:
    """An Origin (or a Referer's origin) as (lowercase host, port with the scheme's default filled in)."""
    try:
        parts = urlsplit(url.strip())
        port = parts.port
    except ValueError:
        return None
    if parts.scheme not in DEFAULT_PORTS or not parts.hostname:
        return None
    return parts.hostname.lower(), port or DEFAULT_PORTS[parts.scheme]


def _matches(origin: tuple[str, int], host: tuple[str, int | None]) -> bool:
    #? a Host header with no port means the scheme's default - 80 or 443, whichever the page used
    if origin[0] != host[0]:
        return False
    return origin[1] == host[1] if host[1] is not None else origin[1] in DEFAULT_PORTS.values()


def trusted_origins(value: str | None = None) -> list[tuple[str, int]]:
    """TRUSTED_ORIGINS, comma-separated full origins ("https://music.example"). Unreadable entries are skipped."""
    raw = os.getenv("TRUSTED_ORIGINS", "") if value is None else value
    found = []
    for item in raw.split(","):
        origin = _origin_of(item) if item.strip() else None
        if origin:
            found.append(origin)
    return found


def refusal(method: str, headers: dict[str, str], trusted: list[tuple[str, int]] | None = None) -> str | None:
    """
    Why this request must be refused, or None if it may go ahead.

    `headers` are the request's, lowercase names. Pure, so every rule can be tested without a server.
    """
    if method.upper() in SAFE_METHODS:
        return None

    stated = headers.get("origin")
    if stated is None:
        #? no Origin: an old browser, or a same-origin form in one that omits it - the Referer
        #? still says which page asked. Neither at all is not a browser acting for a page.
        referer = headers.get("referer")
        if not referer:
            return None
        stated = referer

    if stated.strip().lower() == "null":
        #? what a sandboxed frame, a data: page or a file:// page sends - never deadwax's own page
        return "it came from a page with no web address (Origin: null)"

    origin = _origin_of(stated)
    if origin is None:
        return f"its Origin ({stated[:100]}) isn't a web address"

    #? nginx's $host drops the port, so a proxy on a non-default port (http://nas:8443) passes
    #? "nas" on - which alone would only match 80 or 443. X-Forwarded-Port says which it was (1.0.2).
    forwarded_port = (headers.get("x-forwarded-port") or "").split(",")[0].strip()
    candidates = []
    for name in ("host", "x-forwarded-host"):
        #? a proxy may list several hosts; the first is the one the browser used
        value = (headers.get(name) or "").split(",")[0]
        host = _split_host(value)
        if host:
            candidates.append(host)
            if host[1] is None and forwarded_port.isdigit():
                candidates.append((host[0], int(forwarded_port)))

    if any(_matches(origin, host) for host in candidates):
        return None
    if origin in (trusted if trusted is not None else trusted_origins()):
        return None

    return f"it came from another website ({stated[:100]})"


class SameOriginWrites:
    """The ASGI side of refusal(): answers 403 before the request reaches any route."""

    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.inner(scope, receive, send)

        headers = {k.decode("latin-1").lower(): v.decode("latin-1") for k, v in scope.get("headers", [])}
        reason = refusal(scope.get("method", "GET"), headers)
        if reason is None:
            return await self.inner(scope, receive, send)

        path = scope.get("path", "")
        logger.warning(
            f"refused {scope.get('method')} {path}: {reason}. If deadwax sits behind a proxy that "
            f"changes the Host header, add the address you open it at to TRUSTED_ORIGINS.",
            extra={"frontend": True},
        )
        body = json.dumps({
            "detail": (
                f"Refused: {reason}. deadwax only takes changes from its own page. Behind a proxy "
                f"that rewrites the Host header, add the address you open deadwax at to "
                f"TRUSTED_ORIGINS in the container's environment."
            )
        }).encode()
        await send({
            "type": "http.response.start",
            "status": 403,
            "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())],
        })
        await send({"type": "http.response.body", "body": body})
