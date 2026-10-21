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
and deadwax has no login of its own unless AUTH_MODE is on (2.0.0-player.48) - and even then
every signed-in user would reach it - so a general proxy would hand them the means to create users
or delete anybody's playlists on Navidrome. The playlist routes (2.0.0-player.58) change only the asker's own
playlists, the owner checked by deadwax before anything is written (src/playlists.py), so a shared admin account
still can't touch anyone else's through deadwax.

WHO IS ASKED AS (2.0.0-player.52, step 6 of the multi-user plan): with logins on, every player call is
made AS THE SIGNED-IN USER - client_for(request) lays the login their session was signed in with over
each call (UserClient), so their plays, scrobbles, "Not played", play counts and favourites are theirs.
NAVIDROME_USER and NAVIDROME_PASSWORD stay for logins off (one account, everybody's), for the
break-glass admin (no Navidrome account of its own), and for the questions that answer for nobody in
particular - SHARED_ACCOUNT_USES below, the one list of them, which tests/test_player_as_you.py holds
the code to.
"""

import asyncio
import hashlib
import secrets
import time
from collections import OrderedDict

import httpx
from starlette.requests import Request

from src import __version__
#? without_login lives in config.py since 1.0.5, shared with the settings payload; it is
#? imported here under the name the rest of this module (and its tests) use
from src.config import Config, describe_navidrome_url, without_login

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
                 unreachable: bool = False, code: int | None = None):
        super().__init__(message)
        self.status = status
        self.headers = headers
        self.unreachable = unreachable
        #? Subsonic's own error code, when Navidrome answered with one - 40 is the one logins read
        #? (src/auth.py): the login no longer stands, so the session ends
        self.code = code


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
        raise NavidromeError(message, 404 if code == 70 else 502, code=code if isinstance(code, int) else None)

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

    async def call(self, endpoint: str, params: dict | None = None, form: bool = False) -> dict:
        """
        A JSON call - the answer's body, with its status checked.

        `form` (2.0.0-player.58, the playlist writes): POSTed as application/x-www-form-urlencoded, every parameter
        and the login in the body - a list as its key repeated, in order - and nothing in the URL. Navidrome takes a
        form body on every Subsonic endpoint (OpenSubsonic's formPost), and a 2,000-song playlist's songId pairs
        (~60 KB) would be refused in a URL by a reverse proxy in front of it at its usual 8 KB request line.
        """
        client = await self.get_client()
        try:
            if form:
                response = await client.post(f"/{endpoint}", data=self._params(params or {}))
            else:
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

#? (2.0.0-player.52) What asks Navidrome as NAVIDROME_USER even with logins on - the shared `navidrome`
#? itself, never client_for: questions that answer for nobody in particular. Each file, and why:
#?   src/player_cache.py      the stream cache's make: a song's file fetched ONCE for every phone that plays
#?                            it (its version check, its download, the turntable's byte ranges) - the
#?                            route checks the asker may have the song first (routes/navidrome.py _theirs)
#?   src/album_context.py     the songs beside a hi-res song, for the cache's resample of it - the same make
#?   src/routes/library.py    the apply's getScanStatus: whether Navidrome has finished a scan, a question
#?                            about the server
#?   src/navidrome_listing.py "Not in Navidrome": which album folders Navidrome lists at all
#?   src/routes/settings.py   drops the client when NAVIDROME_URL changes (asks nothing)
#?   src/api/app.py           closes it at shutdown (asks nothing)
#? A file added here is a decision, like a route added to routes/navidrome.py.
SHARED_ACCOUNT_USES = (
    "src/player_cache.py", "src/album_context.py", "src/routes/library.py", "src/navidrome_listing.py",
    "src/routes/settings.py", "src/api/app.py",
)


#? (2.0.0-player.52 review) How long a login Navidrome last took is believed to stand before a call made with
#? it goes ALONE again (UserClient). Navidrome 0.64.1+ blocks a user name, from one address, for 20 s after 5
#? failed logins in 20 s - correct passwords included (server/subsonic/auth_limiter.go) - and every call
#? deadwax makes comes from deadwax's one address, its sign-in's getUser too. Calls are often many at once:
#? Home's shelves and covers, the pins resolved together (routes/pins.py), the bridge's other pressings. Had
#? they all gone out with a login that died a moment before (a password changed), each would have been a
#? failed login, and the new password typed into the sign-in screen refused by the block. So until a call
#? as this login has been answered in the last few seconds, one goes first and the rest wait for it: it
#? standing lets them all go at once; it refused ends the session, and they are a 401 without asking. A few
#? seconds, so a page's burst after a pause waits one round trip at most - and so the calls that can still
#? go out with a login that died are only those already on their way within seconds of the last answer.
CONFIRMED_SECONDS = 5.0
#? ...kept for this many sessions at most, the least recently answered going first
CONFIRMED_KEPT = 1000

#? session id hash -> time.monotonic() when a call as its login was last answered
_confirmed: "OrderedDict[str, float]" = OrderedDict()
#? session id hash -> (the event loop, its lock): one call at a time while the login isn't confirmed. A lock
#? is the loop's it is first waited on in - the server runs one, the tests a new one per run - so one is
#? made afresh for another loop
_gates: "OrderedDict[str, tuple[asyncio.AbstractEventLoop, asyncio.Lock]]" = OrderedDict()


def forget_confirmed() -> None:
    """Every login's confirmation forgotten (the tests)."""
    _confirmed.clear()
    _gates.clear()


def _gate(key: str) -> asyncio.Lock:
    loop = asyncio.get_running_loop()
    held = _gates.get(key)
    if held is None or held[0] is not loop:
        held = (loop, asyncio.Lock())
        _gates[key] = held
    _gates.move_to_end(key)
    while len(_gates) > CONFIRMED_KEPT:
        _gates.popitem(last=False)
    return held[1]


class UserClient(NavidromeClient):
    """
    Navidrome asked AS ONE SIGNED-IN USER (2.0.0-player.52): every call carries the token and salt their
    session was signed in with (auth.PlayerLogin), laid on LAST as the shared login is, so nothing the page
    sent stands in for it. The HTTP connections are the shared client's - one pool for the process, dropped
    with it when NAVIDROME_URL changes.

    Navidrome REFUSING the login (error 40 - the password changed, or the account was deleted) ends the
    session as the re-check would (auth.player_refused) and is a 401 saying why (SignedOut), which brings
    the app's sign-in screen up with the reason. A session already ended in this process asks Navidrome
    nothing - a 401 at once - and (review) until a call as this login has been answered in the last
    CONFIRMED_SECONDS, calls go ONE AT A TIME: the first asks, and the rest wait for its answer - so a burst
    of calls (Home's covers, the pins resolved together) made just after a password changed is one failed
    login against the account, not one per call, and never Navidrome's block.
    """

    def __init__(self, shared: NavidromeClient, login, username: str, token: str, salt: str):
        super().__init__()
        self.shared, self.login = shared, login
        self.username, self.token, self.salt = username, token, salt

    async def get_client(self) -> httpx.AsyncClient:
        return await self.shared.get_client()

    async def close_client(self) -> None:
        #? the connections are the shared client's - closing them is its owner's business
        return None

    def _params(self, params: dict) -> dict:
        #? The login goes on LAST, so nothing the page sent can stand in for it.
        return {
            **{key: value for key, value in params.items() if value is not None},
            "u": self.username, "t": self.token, "s": self.salt, "v": API_VERSION, "c": CLIENT_NAME, "f": "json",
        }

    def _ended(self) -> None:
        from src import auth

        reason = auth.session_ended(self.login.key)
        if reason is not None:
            raise SignedOut(reason)

    async def _refused(self, error: NavidromeError) -> None:
        from src import auth

        if error.code == 40:
            _confirmed.pop(self.login.key, None)
            await asyncio.to_thread(auth.player_refused, self.login)
            raise SignedOut(auth.LOGIN_GONE, code=40) from error

    def _fresh(self) -> bool:
        at = _confirmed.get(self.login.key)
        return at is not None and time.monotonic() - at < CONFIRMED_SECONDS

    def _stood(self) -> None:
        key = self.login.key
        _confirmed[key] = time.monotonic()
        _confirmed.move_to_end(key)
        while len(_confirmed) > CONFIRMED_KEPT:
            _confirmed.popitem(last=False)

    async def _answered(self, ask):
        """`ask()` - then the login confirmed by any answer but a refusal: Navidrome checks the login before
        anything else, so its "not found" stood too; and nothing answering at all (down, unreachable) was no
        failed login either, so the calls waiting on it needn't go one by one to find that out."""
        try:
            answer = await ask()
        except NavidromeError as e:
            await self._refused(e)
            self._stood()
            raise
        self._stood()
        return answer

    async def _asked(self, ask):
        self._ended()
        if not self._fresh():
            async with _gate(self.login.key):
                #? waited on the call before: it ended the session, or confirmed the login
                self._ended()
                if not self._fresh():
                    return await self._answered(ask)
        return await self._answered(ask)

    async def call(self, endpoint: str, params: dict | None = None, form: bool = False) -> dict:
        return await self._asked(lambda: super(UserClient, self).call(endpoint, params, form))

    async def open(self, endpoint: str, params: dict, headers: dict | None = None) -> httpx.Response:
        return await self._asked(lambda: super(UserClient, self).open(endpoint, params, headers))


class SignedOut(NavidromeError):
    """The asker's session has ended - Navidrome refused their login, or something else ended it: a 401
    in words (src/api/app.py answers one that reaches it), which brings the app's sign-in up saying why.
    Anything that quietly turns a NavidromeError into "Navidrome didn't say" lets this one through."""

    def __init__(self, message: str, code: int | None = None):
        super().__init__(message, 401, code=code)


class _NoLogin(NavidromeClient):
    """With logins on, a request that carries no login to ask as - never the shared account in its place:
    every call is a 401 saying why (fail closed). Every route is included with current_user, which sets one,
    so this answers only a mistake - or a login that won't open (another DEADWAX_SECRET_KEY), met while its
    session was still held in memory (auth's _session ends one at its first read from the database): that
    session ends at the first call, as the re-check would end it, so /me says signed out too (review) and the
    app's sign-in screen stays up."""

    def __init__(self, why: str, login=None):
        super().__init__()
        self.why, self.login = why, login

    async def _refuse(self):
        if self.login is not None:
            from src import auth

            await asyncio.to_thread(auth.player_refused, self.login, self.why)
        raise SignedOut(self.why)

    async def call(self, endpoint: str, params: dict | None = None, form: bool = False) -> dict:
        await self._refuse()

    async def open(self, endpoint: str, params: dict, headers: dict | None = None) -> httpx.Response:
        await self._refuse()


def asks_as_shared(client: NavidromeClient) -> bool:
    """Whether `client` is the shared account itself (logins off, the break-glass admin) - the account the
    stream cache asks as, so a cached answer needs no check of the asker's own access."""
    return client is navidrome


def client_for(request: Request | None) -> NavidromeClient:
    """
    The Navidrome client to ask on behalf of whoever made `request` (2.0.0-player.13; as them since
    2.0.0-player.52, step 6 of the multi-user plan).

    THE SEAM for per-user Navidrome logins: every player route, and every internal call made while
    answering one (the turntable's getAlbum, the id bridge's lookups, the pins'), asks through this.

      - Logins OFF: the one shared client, whatever the request - one account, everybody's.
      - Logins ON, signed in through Navidrome: a UserClient carrying the login the session was signed
        in with (src/auth.py's user_for keeps it on the request as current_user resolves it), so the
        calls are theirs. Error 40 ends the session (UserClient).
      - The break-glass admin: the shared client - it has no Navidrome account of its own (notes/logins.md
        "The player as you" says why that, and not a refusal).
      - Logins on and nothing to ask as: a client that refuses every call with a 401 - never the shared
        account in its place.

    What does NOT come through here, on purpose - SHARED_ACCOUNT_USES above: the stream cache's make and
    the album context (player_cache.py, album_context.py), which fetch a file ONCE for every phone that asks
    for it and so have no one request to answer for - the stream and scrub routes check the asker's access
    first (routes/navidrome.py _theirs); the apply's getScanStatus (routes/library.py) and the "Not in
    Navidrome" listing (navidrome_listing.py), questions about the server, not about anybody's library.
    """
    if request is None or not Config.logins_on():
        return navidrome
    from src import auth

    login = getattr(getattr(request, "state", None), auth.LOGIN_STATE, None)
    if login == auth.SHARED_LOGIN:
        return navidrome
    if not isinstance(login, auth.PlayerLogin):
        return _NoLogin(auth.SIGN_IN)
    opened = auth.unseal_credential(login.sealed) if login.sealed else None
    if opened is None:
        #? a login that won't open (another DEADWAX_SECRET_KEY) asks nothing, and its first call ends the session
        return _NoLogin(auth.KEY_CHANGED, login)
    return UserClient(navidrome, login, *opened)
