"""
Talking to Navidrome, for the player at /player/.

Navidrome speaks the Subsonic API, which is how every Subsonic app - Amperfy, play:Sub,
Symfonium - talks to it. deadwax is one more of those, with one difference that is the reason
this module exists rather than the page calling Navidrome itself:

  THE PASSWORD STAYS HERE. Subsonic authenticates every request with the user name and a token
  made from the password, and a page that can make tokens holds the account. Keeping the login
  server-side and handing the page only what it asked for also removes two other problems at
  once: the page and Navidrome are different origins (CORS), and deadwax served over HTTPS
  asking a phone to fetch audio from Navidrome over plain HTTP is mixed content Safari refuses.

What passes through is a fixed list of calls in routes/navidrome.py, each with its own
parameters - never a general proxy. The account configured here may well be Navidrome's admin,
and deadwax has no login of its own, so a general proxy would hand anybody who can reach
deadwax the means to create users or delete playlists on Navidrome.
"""

import hashlib
import secrets
from urllib.parse import urlsplit, urlunsplit

import httpx

from src import __version__
from src.config import Config, describe_navidrome_url

#? The Subsonic API version deadwax speaks: the last one Subsonic itself published, which is
#? what Navidrome reports, and the one carrying the album-based (ID3) calls used here.
API_VERSION = "1.16.1"

#? Navidrome lists every client under this name in its Players page. Don't set a transcoding or
#? a max bit rate for it there, though it looks like the place for a phone's bitrate: it is ONE
#? entry for every browser using the player, and Navidrome applies it to every stream that doesn't
#? ask for `raw` - a bit rate alone turns each song into a transcode, in Opus by default, and a
#? transcode has no byte ranges, which Safari won't play without (core/stream/legacy_client.go,
#? decider.go, media_streamer.go). The player asks for `format=raw` for every file it can play,
#? which Navidrome answers before it looks at the Players page, so a setting there never reaches
#? them - though a transcoding set there would still replace the MP3 asked for a file it can't.
CLIENT_NAME = "deadwax"

#? A binary call's statuses that are passed on as they are: the whole file, a byte range, and
#? "you already have it" for a conditional request. Anything else is an error of some kind.
PASSED_STATUSES = (200, 206, 304)

#? Said when something other than Navidrome's Subsonic API answered - a reverse proxy's login
#? page, a redirect, a web server at the wrong path.
NOT_NAVIDROME = "is NAVIDROME_URL the address of Navidrome itself?"

NOT_CONFIGURED = (
    "Navidrome isn't set up - fill in NAVIDROME_URL, NAVIDROME_USER and NAVIDROME_PASSWORD in "
    "the settings tab"
)

#? Subsonic's own error codes, in words that say what to do. Anything else is quoted as sent.
SUBSONIC_ERRORS = {
    40: "Navidrome refused the login - check NAVIDROME_USER and NAVIDROME_PASSWORD",
    41: "Navidrome can't use token logins for this user (LDAP accounts can't) - use a local account",
    50: "Navidrome says this user isn't allowed to do that",
    70: "Navidrome has nothing by that id",
}


class NavidromeError(Exception):
    """
    Navidrome couldn't be asked, or said no. `status` is what the route should answer with, and
    `headers` any of Navidrome's own that belong on that answer - a 416's Content-Range, a 429's
    Retry-After.

    `unreachable` is set when nothing answered at all - refused, no such host, timed out - as
    opposed to an answer that came and couldn't be used. The apply route tells them apart: a
    Navidrome that isn't there may be restarting, and its first scan would see a rename made now
    (see _pause_before_rename in routes/library.py).
    """

    def __init__(self, message: str, status: int = 502, headers: dict[str, str] | None = None,
                 unreachable: bool = False):
        super().__init__(message)
        self.status = status
        self.headers = headers
        self.unreachable = unreachable


def without_login(url: str | None) -> str:
    """
    The address as it may be shown: any user name or password in it taken out. The client refuses
    such an address (see get_client), so this is the second line - an error message quoting it
    lands in the log, the page's event log and the player's screen.
    """
    url = url or ""
    try:
        parts = urlsplit(url)
    except ValueError:
        return url.rpartition("@")[2] if "@" in url else url
    if "@" not in parts.netloc:
        return url
    return urlunsplit(parts._replace(netloc=parts.netloc.rpartition("@")[2]))


def unusable_url(problem: str) -> str:
    """What the player and the apply are told when NAVIDROME_URL fails describe_navidrome_url()."""
    return (f"NAVIDROME_URL is unusable ({problem}), so deadwax sends nothing to it - fix it in the "
            f"settings tab (Connections), or in your compose file")


def unreachable(error: httpx.HTTPError) -> NavidromeError:
    """
    A request that got no usable answer at all. A TransportError - refused, no such host, timed
    out, the connection dropped mid-answer - is Navidrome not being there, and says so in
    `unreachable`; anything else httpx raises (too many redirects, a body it can't decode) came
    from something that did answer.
    """
    return NavidromeError(
        f"Navidrome couldn't be reached at {without_login(Config.NAVIDROME_URL)}: "
        f"{str(error) or type(error).__name__}",
        unreachable=isinstance(error, httpx.TransportError),
    )


def auth_params(user: str, password: str, salt: str | None = None) -> dict[str, str]:
    """
    What every Subsonic request carries: who is asking, a salted token, and which client this is.

    Token auth - `t` is md5(password + salt) - rather than the password itself, so the password
    is never written into Navidrome's access log or anything between here and there. A fresh
    salt per request is what the API asks for.
    """
    salt = salt or secrets.token_hex(8)
    token = hashlib.md5((password + salt).encode("utf-8")).hexdigest()
    return {"u": user, "t": token, "s": salt, "v": API_VERSION, "c": CLIENT_NAME, "f": "json"}


def subsonic_body(payload) -> dict:
    """The inside of a Subsonic JSON answer. Raises NavidromeError with Navidrome's own reason."""
    body = payload.get("subsonic-response") if isinstance(payload, dict) else None
    if not isinstance(body, dict):
        raise NavidromeError(f"the answer wasn't a Subsonic one - {NOT_NAVIDROME}")

    if body.get("status") != "ok":
        error = body.get("error") if isinstance(body.get("error"), dict) else {}
        code = error.get("code")
        message = SUBSONIC_ERRORS.get(code) or f"Navidrome said: {error.get('message') or 'failed'}"
        raise NavidromeError(message, 404 if code == 70 else 502)

    return body


class NavidromeClient:
    def __init__(self):
        self.client: httpx.AsyncClient | None = None

    async def get_client(self) -> httpx.AsyncClient:
        if not Config.navidrome_configured():
            raise NavidromeError(NOT_CONFIGURED, 503)

        #? The settings tab refuses such an address on save, but one from the environment never
        #? passed through it. Start-up already says it can't be used; nothing is sent to it either
        #? - a login in it would ride along as basic auth, a ? or # would swallow /rest.
        problem = describe_navidrome_url(Config.NAVIDROME_URL)
        if problem:
            raise NavidromeError(unusable_url(problem), 503)

        if not self.client or self.client.is_closed:
            self.client = httpx.AsyncClient(
                base_url=f"{Config.NAVIDROME_URL.rstrip('/')}/rest",
                #? generous on read: a stream is read for as long as the song lasts, and a
                #? transcode can take a moment to produce its first bytes
                timeout=httpx.Timeout(connect=10.0, write=10.0, read=60.0, pool=10.0),
                headers={"User-Agent": f"deadwax/{__version__}"},
            )
        return self.client

    async def close_client(self) -> None:
        if self.client and not self.client.is_closed:
            await self.client.aclose()
        self.client = None

    @staticmethod
    def _params(params: dict) -> dict:
        #? The login goes on LAST, so nothing the page sent can stand in for it.
        return {
            **{key: value for key, value in params.items() if value is not None},
            **auth_params(Config.NAVIDROME_USER or "", Config.NAVIDROME_PASSWORD or ""),
        }

    async def call(self, endpoint: str, params: dict | None = None) -> dict:
        """A JSON call - the answer's body, with its status checked."""
        client = await self.get_client()
        try:
            response = await client.get(f"/{endpoint}", params=self._params(params or {}))
        except httpx.HTTPError as e:
            raise unreachable(e) from e

        if response.status_code >= 400:
            raise NavidromeError(f"Navidrome answered {response.status_code}")

        try:
            payload = response.json()
        except ValueError as e:
            raise NavidromeError(f"the answer wasn't JSON - {NOT_NAVIDROME}") from e

        return subsonic_body(payload)

    async def open(self, endpoint: str, params: dict, headers: dict | None = None) -> httpx.Response:
        """
        A binary call - audio or a cover - left open to be streamed on. The caller closes it.

        Only a 200, a 206 or a 304 that isn't text comes back. Subsonic reports a failed binary
        call as an ordinary JSON answer with a 200, so a JSON or XML body is read as the error it
        is rather than passed on as a song that won't play. A web page, a redirect or a refusal
        from a proxy in front of Navidrome is said to be one, where passing it on would leave
        Safari saying only that it couldn't decode the "song".
        """
        client = await self.get_client()
        request = client.build_request(
            "GET", f"/{endpoint}", params=self._params(params), headers=headers or {}
        )
        try:
            response = await client.send(request, stream=True)
        except httpx.HTTPError as e:
            raise unreachable(e) from e

        status = response.status_code
        media = response.headers.get("content-type", "").split(";")[0].strip().lower()
        text = "json" in media or "xml" in media or media.startswith("text/")
        #? a 304 has no body to judge
        if status == 304 or (status in PASSED_STATUSES and not text):
            return response

        #? Subsonic's own reason, when the body is a Subsonic failure - never a guess made from a
        #? body that only happens to be JSON
        said = None
        try:
            await response.aread()
            if "json" in media:
                payload = response.json()
                if isinstance(payload, dict) and "subsonic-response" in payload:
                    subsonic_body(payload)
        except NavidromeError as e:
            said = e
        except (ValueError, httpx.HTTPError):
            pass
        finally:
            await response.aclose()

        #? Navidrome's cap on transcodes at once (0.64), with a Subsonic body and a Retry-After
        #? that is passed on, so whatever retries knows when
        if status == 429:
            retry_after = response.headers.get("retry-after")
            raise NavidromeError(str(said or "Navidrome is busy - try again shortly"), 429,
                                 {"Retry-After": retry_after} if retry_after else None)
        #? a byte range past the end, which is Safari's to handle - and it is told where the end
        #? is by the Content-Range (bytes */N) Navidrome sent, as Go's own 416 does
        if status == 416:
            content_range = response.headers.get("content-range")
            raise NavidromeError("the byte range asked for is past the end of the file", 416,
                                 {"Content-Range": content_range} if content_range else None)
        if said:
            raise said
        if status >= 500:
            raise NavidromeError(f"Navidrome answered {status} for {endpoint}")
        if status in PASSED_STATUSES:
            raise NavidromeError(f"{endpoint} answered with {media} instead of audio or a picture - {NOT_NAVIDROME}")
        #? a plain 404 stays one; Subsonic's own "not found" is a code in a 200, handled above
        raise NavidromeError(f"{endpoint} was answered with a {status} - {NOT_NAVIDROME}",
                             404 if status == 404 else 502)


#? One client for the process, like LRCLIB's. The app's lifespan closes it, and the settings
#? route drops it when NAVIDROME_URL changes.
navidrome = NavidromeClient()
