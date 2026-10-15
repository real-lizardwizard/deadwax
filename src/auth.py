"""
Logins (2.0.0-player.48, step 3 of the multi-user plan): signing in, the session that follows, and
who is an admin - the mechanics. src/users.py's `current_user` is the dependency every router is
checked by; src/routes/auth.py is the sign-in and sign-out; this is what both stand on.

Every choice here was made with James when the plan was made (the plan's "Accounts, logging in,
roles"); notes/logins.md has the reasoning. In short:

  OFF IS TODAY. With AUTH_MODE off nothing here runs: current_user answers the implicit admin
  `local` without looking at the request, and no table is written.

  SIGNING IN IS THROUGH NAVIDROME'S SUBSONIC API, never its web login. deadwax picks a salt, makes
  the token (md5 of password + salt) itself, and asks `getUser` for the account's own name as that
  account: a wrong password or a deleted account fails with Subsonic's error 40. Navidrome's web
  login (/auth/login) is undocumented and limited to 5 logins per 20 s per IP - and every deadwax
  sign-in comes from deadwax's one IP, so one mistyped password would have locked everybody out.

  THE TOKEN IS AS GOOD AS THE PASSWORD on Navidrome's API, for as long as the password stands. It is
  kept (the re-check below needs it, and step 6 will play as each user with it) ENCRYPTED with a key
  from the environment, DEADWAX_SECRET_KEY, through the `cryptography` package's Fernet - never a
  cipher of our own. Without the key logins don't work at all: every protected route answers 503
  and says why, rather than storing a token bare. The password itself is never kept or logged.

  NOTHING RETRIES A SIGN-IN, and sign-ins are throttled per name (Throttle): Navidrome blocks an
  account for a while after a run of failures, and a bot hammering deadwax must not be able to get
  James blocked through it. The re-check asks Navidrome about each person at most once a pass.

  A SESSION is a random id (secrets.token_urlsafe) in an HttpOnly, SameSite=Strict cookie named
  `deadwax_session` (Navidrome's own is `jwt`), Secure when the page came over HTTPS. The database
  keeps only the id's SHA-256, so a copy of the file is no live cookie; sessions are kept there so a
  restart signs nobody out, and held in memory a minute at a time so a stream's every byte range
  doesn't read the database. The expiry slides forward with use (SESSION_IDLE_SECONDS), so the
  phone doesn't ask again mid-song.

  RE-CHECKED: every few minutes (RECHECK_SECONDS) each live session's token is put to getUser again.
  Error 40 - the password changed, or the account is gone - ends the session, and the next request
  answers 401 saying why. Navidrome not answering ends nothing: it is proof of nothing.

  ADMINS are deadwax's own list, DEADWAX_ADMINS; Navidrome's admin flag is never read.

  BREAK-GLASS: DEADWAX_ADMIN_PASSWORD signs in the fixed admin `admin` with neither Navidrome nor
  the database, for when Navidrome is down - a cookie sealed with DEADWAX_SECRET_KEY (Fernet, so it
  is signed and dated), good for BREAK_GLASS_SECONDS, and bound to the password: changing the
  password ends every one. The password is compared in constant time.

  FAIL CLOSED: a database that can't be read answers 503 on every protected route, never "signed
  in" - and never "signed out" either, which would only send everyone to a sign-in that can't work.
  The health check stays 200 (it judges deadwax alone, as it always did).
"""

import asyncio
import base64
import hashlib
import hmac
import json
import secrets
import threading
import time
from collections import OrderedDict, deque
from dataclasses import dataclass
from typing import Callable

import httpx
from cryptography.fernet import Fernet, InvalidToken
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from fastapi import HTTPException

from src import __version__
from src.api.navidrome_endpoint import API_VERSION, CLIENT_NAME, NavidromeError, subsonic_body, unusable_url
from src.config import Config, describe_navidrome_url, describe_secret_key
from src.logger import logger

#? The session cookie's name. Not `jwt`, which is Navidrome's - cookies aren't kept apart by port,
#? so on one host the two would overwrite each other.
COOKIE = "deadwax_session"

#? The break-glass admin's fixed name (DEADWAX_ADMIN_PASSWORD). Nobody signs in AS this through
#? Navidrome: the name is reserved, so a Navidrome account called `admin` can't become deadwax's admin
#? by its name alone.
BREAK_GLASS_USER = "admin"

#? Names nobody signs in as through Navidrome: the break-glass admin's, and src/users.py's LOCAL_USER,
#? the implicit user of logins-off whose pins and preferences the first admin takes over.
RESERVED_NAMES = frozenset({"local", BREAK_GLASS_USER})

#? How long a session lasts unused: each use moves its end this far on (written at most every
#? TOUCH_SECONDS). Long, so the phone never asks again mid-song; the re-check is what ends a session
#? whose login no longer stands, not this.
SESSION_IDLE_SECONDS = 30 * 86400
#? How long the browser keeps the cookie: the most a browser allows (Chrome caps it at 400 days). The
#? server's own sliding end is what counts; the cookie only has to outlive it.
COOKIE_MAX_AGE = 400 * 86400
#? How long a break-glass sign-in lasts. Not sliding: it is for getting past an outage.
BREAK_GLASS_SECONDS = 12 * 3600

#? A session held in memory is read from the database again after this long - so a database that
#? has gone away is found within a minute (fail closed), and a session deleted by hand ends.
CACHE_SECONDS = 60
#? The sliding expiry is written at most this often per session, not on every byte range.
TOUCH_SECONDS = 600
#? How old Navidrome's last word on a session may get before the re-check asks again: "every few
#? minutes", so a changed password or a deleted account ends a session quickly.
RECHECK_SECONDS = 300
#? How often the re-check looks for sessions due.
CHECK_EVERY_SECONDS = 60

#? Wrong passwords allowed per name in any THROTTLE_WINDOW seconds before deadwax stops asking
#? Navidrome. Navidrome blocks a user for 20 s after 5 failures; 3 a minute, and the re-check's one a
#? pass, never reach that.
THROTTLE_FAILURES = 3
THROTTLE_WINDOW = 60.0

#? What a request is told, in the words the app's sign-in screen shows.
SIGN_IN = "Sign in to use deadwax."
SIGNED_OUT = "You've been signed out - sign in again."
EXPIRED = "Your sign-in ran out after 30 days without use - sign in again."
LOGIN_GONE = ("Navidrome no longer accepts the login you signed in with - if you changed your Navidrome "
              "password, sign in with the new one.")
KEY_CHANGED = "deadwax's DEADWAX_SECRET_KEY has changed since you signed in - sign in again."
BREAK_GLASS_ENDED = ("The break-glass sign-in has ended - it lasts 12 hours, and ends when "
                     "DEADWAX_ADMIN_PASSWORD changes. Sign in again.")
NO_DATABASE = ("deadwax can't read its database, so it can't check who you are - nothing is let in until "
               "it can. Check DB_PATH points at a writable volume.")
WRONG_LOGIN = "That user name and password didn't work."


def unusable() -> str | None:
    """Why nobody can sign in at all right now, in words for whoever asks - or None. Logins on only."""
    problem = describe_secret_key(Config.DEADWAX_SECRET_KEY)
    if problem:
        return (f"Logins are on, but DEADWAX_SECRET_KEY {problem}, so deadwax can't sign anyone in. "
                f"Set it in the container's environment and restart deadwax.")
    return None


# ===== the key ======================================================================================

#? one Fernet per purpose for the key in use (the key is the environment's, so it changes only in tests)
_fernets: dict[tuple[str, str], Fernet] = {}


def _derived(purpose: str) -> bytes:
    """32 bytes for one purpose, from DEADWAX_SECRET_KEY through HKDF-SHA256 - so the credential and the
    break-glass cookie never share a key, and any string of AUTH_SECRET_MIN characters will do."""
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=None,
                info=f"deadwax {purpose}".encode()).derive((Config.DEADWAX_SECRET_KEY or "").encode("utf-8"))


def _fernet(purpose: str) -> Fernet:
    held = (Config.DEADWAX_SECRET_KEY or "", purpose)
    if held not in _fernets:
        if len(_fernets) > 8:
            _fernets.clear()
        _fernets[held] = Fernet(base64.urlsafe_b64encode(_derived(purpose)))
    return _fernets[held]


def seal_credential(username: str, token: str, salt: str) -> str:
    """What the database keeps of a sign-in: the name as Navidrome took it, the token and its salt, encrypted."""
    return _fernet("navidrome credential").encrypt(
        json.dumps({"u": username, "t": token, "s": salt}).encode()).decode("ascii")


def unseal_credential(sealed: str) -> tuple[str, str, str] | None:
    """(username, token, salt) back out - None when it won't open (another key) or isn't one."""
    try:
        held = json.loads(_fernet("navidrome credential").decrypt(sealed.encode("ascii")))
        return str(held["u"]), str(held["t"]), str(held["s"])
    except (InvalidToken, ValueError, KeyError, TypeError, UnicodeError):
        return None


def subsonic_token(password: str, salt: str) -> str:
    """Subsonic's token: md5(password + salt), as every Subsonic client makes it (src/api/navidrome_endpoint.py)."""
    return hashlib.md5((password + salt).encode("utf-8")).hexdigest()


# ===== session ids ==================================================================================

def new_session_id() -> str:
    """A cookie's session id: 256 random bits from the secrets module, unguessable."""
    return "s." + secrets.token_urlsafe(32)


def id_hash(raw: str) -> str:
    """What the database keys a session on: the id's SHA-256, never the id."""
    return hashlib.sha256(raw.encode("utf-8", "replace")).hexdigest()


def cookie_secure(scheme: str, forwarded_proto: str | None) -> bool:
    """Whether the cookie gets Secure: the page came over HTTPS - itself, or by a proxy's X-Forwarded-Proto."""
    first = (forwarded_proto or "").split(",")[0].strip().lower()
    return scheme == "https" or first == "https"


# ===== break-glass ==================================================================================

#? break-glass cookies signed out, by their nonce, until they would have run out anyway. In memory: a
#? cookie needs no database, so neither does its sign-out - a restart forgets these, and the cookie's
#? own 12 hours bound what that leaves.
_revoked_glass: dict[str, float] = {}


def _password_mark(password: str) -> str:
    """What ties a break-glass cookie to the password it was made with - a keyed hash, never the password."""
    return hmac.new(_derived("break-glass password"), password.encode("utf-8"), hashlib.sha256).hexdigest()


def break_glass_matches(given: str) -> bool:
    """`given` is DEADWAX_ADMIN_PASSWORD - in constant time, whatever either's length. False when it is unset."""
    password = Config.DEADWAX_ADMIN_PASSWORD
    if not password:
        return False
    return hmac.compare_digest(hashlib.sha256(given.encode("utf-8")).digest(),
                               hashlib.sha256(password.encode("utf-8")).digest())


def break_glass_cookie() -> str:
    """A break-glass session: sealed and dated by Fernet, naming the password it was made with."""
    payload = {"u": BREAK_GLASS_USER, "n": secrets.token_urlsafe(16),
               "m": _password_mark(Config.DEADWAX_ADMIN_PASSWORD or "")}
    #? Fernet's padding off: an `=` would have the cookie quoted on its way out
    return "b." + _fernet("break-glass").encrypt(json.dumps(payload).encode()).decode("ascii").rstrip("=")


def _break_glass_payload(raw: str, now: float | None = None) -> dict | None:
    """What a break-glass cookie holds, if Fernet opens it and it was made in the last BREAK_GLASS_SECONDS."""
    token = raw[2:]
    token += "=" * (-len(token) % 4)
    try:
        sealed = token.encode("ascii")
        opened = _fernet("break-glass").decrypt_at_time(sealed, BREAK_GLASS_SECONDS, int(time.time() if now is None else now))
        payload = json.loads(opened)
    except (InvalidToken, ValueError, UnicodeError):
        return None
    return payload if isinstance(payload, dict) else None


def break_glass_user(raw: str, now: float | None = None) -> str | None:
    """The break-glass admin, if `raw` is a live break-glass cookie made with the password set now."""
    password = Config.DEADWAX_ADMIN_PASSWORD
    if not password:
        return None
    payload = _break_glass_payload(raw, now)
    if payload is None or payload.get("u") != BREAK_GLASS_USER:
        return None
    if not hmac.compare_digest(str(payload.get("m", "")), _password_mark(password)):
        return None
    with _lock:
        if str(payload.get("n")) in _revoked_glass:
            return None
    return BREAK_GLASS_USER


def revoke_break_glass(raw: str) -> None:
    payload = _break_glass_payload(raw)
    if payload is None:
        return
    now = time.time()
    with _lock:
        for nonce, until in list(_revoked_glass.items()):
            if until <= now:
                del _revoked_glass[nonce]
        _revoked_glass[str(payload.get("n"))] = now + BREAK_GLASS_SECONDS


# ===== sessions =====================================================================================

@dataclass
class _Held:
    user: str
    expires_at: float
    touched: float      # when its expiry was last written forward (or tried: _touch)
    loaded: float       # time.monotonic() when it was read from the database


#? Guards everything below: current_user runs in FastAPI's thread pool, the sign-in and the re-check on
#? the event loop.
_lock = threading.Lock()
_held: dict[str, _Held] = {}
#? sessions ended here (signed out, error 40, a key that changed), by id hash, with why - so the request
#? that comes next is told the reason rather than only "sign in". Bounded: the oldest go first.
_ended: "OrderedDict[str, str]" = OrderedDict()
ENDED_KEPT = 1000


def forget_sessions() -> None:
    """Drop everything held in memory (tests; the database is untouched)."""
    with _lock:
        _held.clear()
        _ended.clear()
        _revoked_glass.clear()


def _note_ended(key: str, reason: str) -> None:
    with _lock:
        _held.pop(key, None)
        _ended[key] = reason
        _ended.move_to_end(key)
        while len(_ended) > ENDED_KEPT:
            _ended.popitem(last=False)


def end_session(store, key: str, reason: str) -> None:
    """End one session, by id hash: gone from the database and from memory. SYNCHRONOUS - raises on a database error."""
    _note_ended(key, reason)
    store.delete_session(key)


def signed_out(detail: str) -> HTTPException:
    #? No Set-Cookie clearing the cookie here: a request sent before a fresh sign-in, answered after it,
    #? would delete the NEW cookie. A stale cookie is harmless; the next sign-in overwrites it.
    return HTTPException(status_code=401, detail=detail)


def _touch(store, key: str, held: _Held, now: float) -> None:
    """
    Write a session's expiry forward - BEST EFFORT. The session was read and stands; this only moves
    when it would run out, so a write that fails (a full /config, a volume gone read-only, a lock held
    past SQLite's timeout) is logged and the request goes on: refusing it would stop the music over a
    date, with a 503 saying the database can't be READ. `touched` moves on first either way, so the
    write isn't tried again on every byte range (nor by the requests arriving beside this one);
    `expires_at` moves only once the database has it, so a missed write can only end the session
    sooner, never later. A failed READ is still the 503 (user_for).
    """
    held.touched = now
    try:
        store.touch_session(key, now, now + SESSION_IDLE_SECONDS)
    except Exception as e:
        logger.warning(f"could not write a session's new expiry to the database - it stands, and ends when it "
                       f"would have ({type(e).__name__}: {e})")
        return
    held.expires_at = now + SESSION_IDLE_SECONDS


def session_user(store, raw: str, now: float | None = None) -> str:
    """
    Who a Navidrome session cookie belongs to - or HTTPException 401 saying why it doesn't stand.
    SYNCHRONOUS (current_user runs in the thread pool) and RAISES on a database error, which the caller
    turns into a 503. Held in memory for CACHE_SECONDS between reads; its expiry written forward at most
    every TOUCH_SECONDS.
    """
    key = id_hash(raw)
    now = time.time() if now is None else now
    with _lock:
        held = _held.get(key)
        ended = _ended.get(key)
    if ended is not None:
        raise signed_out(ended)
    if held is not None and time.monotonic() - held.loaded < CACHE_SECONDS and held.expires_at > now:
        if now - held.touched >= TOUCH_SECONDS:
            _touch(store, key, held, now)
        return held.user

    row = store.session(key)
    if row is None:
        with _lock:
            _held.pop(key, None)
        raise signed_out(SIGNED_OUT)
    if row["expires_at"] <= now:
        end_session(store, key, EXPIRED)
        raise signed_out(EXPIRED)
    held = _Held(row["user"], row["expires_at"], row["last_seen"], time.monotonic())
    with _lock:
        _held[key] = held
    if now - held.touched >= TOUCH_SECONDS:
        _touch(store, key, held, now)
    return held.user


def user_for(request) -> str:
    """
    The signed-in user a request comes from, with logins on - what src/users.py's current_user answers.
    401 with no session or one that no longer stands; 503 when logins can't work (no key) or the
    database can't be read. A break-glass cookie is checked first: it needs no database.
    """
    problem = unusable()
    if problem:
        raise HTTPException(status_code=503, detail=problem)
    raw = request.cookies.get(COOKIE)
    if not raw:
        raise signed_out(SIGN_IN)
    if raw.startswith("b."):
        user = break_glass_user(raw)
        if user is None:
            raise signed_out(BREAK_GLASS_ENDED)
        return user

    store = getattr(request.app.state, "store", None)
    if store is None or not getattr(store, "available", False):
        raise HTTPException(status_code=503, detail=NO_DATABASE)
    try:
        return session_user(store, raw)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"could not read a session from the database, so the request was refused ({type(e).__name__}: {e})")
        raise HTTPException(status_code=503, detail=NO_DATABASE) from e


# ===== asking Navidrome =============================================================================

class LoginClient:
    """
    The HTTP client a sign-in and the re-check ask Navidrome through - its own, beside the player's,
    because the player's signs every request with NAVIDROME_USER's login, laid on last; this one asks
    as the person signing in, with the token deadwax just made for them. One call: getUser, for the
    account's own name. Only NAVIDROME_URL is needed, and it is held to describe_navidrome_url as the
    player's is - nothing is sent to an address that would leak the token.
    """

    def __init__(self):
        self.client: httpx.AsyncClient | None = None
        self.base: str | None = None

    async def get_client(self) -> httpx.AsyncClient:
        problem = describe_navidrome_url(Config.NAVIDROME_URL)
        if problem:
            raise NavidromeError(unusable_url(problem), 503)
        base = f"{(Config.NAVIDROME_URL or '').rstrip('/')}/rest"
        if self.client is None or self.client.is_closed or self.base != base:
            await self.close_client()
            self.client = httpx.AsyncClient(
                base_url=base, timeout=httpx.Timeout(10.0),
                headers={"User-Agent": f"deadwax/{__version__}"},
            )
            self.base = base
        return self.client

    async def close_client(self) -> None:
        if self.client is not None and not self.client.is_closed:
            await self.client.aclose()
        self.client = None


login_client = LoginClient()


async def check_login(username: str, token: str, salt: str) -> str | None:
    """
    Ask Navidrome whether this token stands for `username` - getUser for the account's own name, signed
    as that account. The user name Navidrome answered with (None if it named none); NavidromeError when
    it refused (`code` 40: wrong password or no such account) or couldn't be asked (`unreachable`).
    """
    client = await login_client.get_client()
    params = {"u": username, "t": token, "s": salt, "v": API_VERSION, "c": CLIENT_NAME, "f": "json",
              "username": username}
    try:
        response = await client.get("/getUser", params=params)
    except httpx.HTTPError as e:
        #? never the URL: it carries the token
        raise NavidromeError(f"Navidrome couldn't be reached ({type(e).__name__})",
                             unreachable=isinstance(e, httpx.TransportError)) from e
    if response.status_code >= 400:
        raise NavidromeError(f"Navidrome answered {response.status_code}")
    try:
        payload = response.json()
    except ValueError as e:
        raise NavidromeError("the answer wasn't a Subsonic one - is NAVIDROME_URL Navidrome's address?") from e
    body = subsonic_body(payload)
    user = body.get("user")
    name = user.get("username") if isinstance(user, dict) else None
    return name if isinstance(name, str) else None


# ===== the throttle =================================================================================

class Throttle:
    """
    At most `failures` wrong passwords per name in any `window` seconds - then deadwax answers 429
    itself and asks Navidrome nothing until the oldest falls out of the window. Per name, lowercased, so
    a bot guessing at `james` gets James's Navidrome account nowhere near its block. A sign-in for a
    name holds that name's lock while it asks, so ten at once are ten in turn, each counted.

    The record is bounded (`cap` names) - but a name being HELD OFF is never what makes room: failing
    10000 other names once each would otherwise have pushed `james` out of the record and let him be
    tried again at once. Room is made from what has aged out of the window, then from names still under
    the limit, oldest first; held names stay until their own minute is up, so past the cap the record
    only grows by names that each cost Navidrome `failures` refusals and leave within `window`.
    """

    def __init__(self, failures: int = THROTTLE_FAILURES, window: float = THROTTLE_WINDOW,
                 clock: Callable[[], float] = time.monotonic, cap: int = 10000):
        self.failures, self.window, self.clock, self.cap = failures, window, clock, cap
        #? by the time of each name's LAST failure, oldest first (failed() moves a name to the end)
        self._failed: "OrderedDict[str, deque[float]]" = OrderedDict()
        self._locks: dict[str, asyncio.Lock] = {}

    def wait(self, name: str) -> float:
        """Seconds until `name` may try again - 0 when it may now."""
        times = self._failed.get(name)
        if not times:
            return 0.0
        now = self.clock()
        while times and now - times[0] >= self.window:
            times.popleft()
        if not times:
            del self._failed[name]
            return 0.0
        if len(times) < self.failures:
            return 0.0
        return max(0.0, self.window - (now - times[0]))

    def failed(self, name: str) -> None:
        now = self.clock()
        self._failed.setdefault(name, deque()).append(now)
        self._failed.move_to_end(name)
        if len(self._failed) > self.cap:
            self._make_room(now, keep=name)

    def _make_room(self, now: float, keep: str) -> None:
        """Down to nine tenths of the cap where it can (so, while there is room to make, it runs once in a
        while rather than on every failure): first every name whose last failure has left the window -
        the front of the order - then names under the limit, oldest first. Never a name held off, and
        never `keep`, the failure just counted."""
        target = self.cap - max(1, self.cap // 10)
        while self._failed:
            oldest, times = next(iter(self._failed.items()))
            if oldest == keep or now - times[-1] < self.window:
                break
            del self._failed[oldest]
        for other in list(self._failed):
            if len(self._failed) <= target:
                return
            if other == keep:
                continue
            times = self._failed[other]
            while times and now - times[0] >= self.window:
                times.popleft()
            if len(times) < self.failures:
                del self._failed[other]

    def succeeded(self, name: str) -> None:
        self._failed.pop(name, None)

    def lock(self, name: str) -> asyncio.Lock:
        held = self._locks.get(name)
        if held is None:
            if len(self._locks) >= self.cap:
                for other in [n for n, lock in self._locks.items() if not lock.locked()]:
                    del self._locks[other]
            held = self._locks[name] = asyncio.Lock()
        return held


throttle = Throttle()


# ===== signing in ===================================================================================

def _too_many(name: str, wait: float) -> HTTPException:
    seconds = max(1, int(wait + 0.999))
    return HTTPException(
        status_code=429,
        detail=(f"Too many tries for {name[:60]} - wait {seconds} seconds and try again. deadwax holds off "
                f"so Navidrome doesn't lock the account."),
        headers={"Retry-After": str(seconds)},
    )


async def sign_in(store, typed: str, password: str) -> tuple[str, str, int]:
    """
    Sign `typed` in with `password`: (the user, the cookie's value, its max age) - or HTTPException
    saying plainly why not: 401 a wrong password, 429 too many tries, 503 Navidrome not answering or
    deadwax unable to keep the session, 502 anything else Navidrome said.

    The break-glass name is checked against DEADWAX_ADMIN_PASSWORD alone and asks Navidrome nothing.
    Any other name is put to Navidrome's getUser with a token made here, from a fresh salt: the name
    as typed (Navidrome finds accounts whatever their case), the identity lowercased. Each name's tries
    are in turn and counted (`throttle`); nothing is ever retried. An admin's first sign-in takes over
    what `local` saved while logins were off (adopt_local) - for every admin who signs in, which after
    the first finds nothing left to take.
    """
    name = typed.strip().lower()
    async with throttle.lock(name):
        wait = throttle.wait(name)
        if wait:
            raise _too_many(name, wait)

        if name == BREAK_GLASS_USER:
            if not break_glass_matches(password):
                throttle.failed(name)
                logger.warning("a break-glass sign-in was refused: wrong password, or DEADWAX_ADMIN_PASSWORD isn't set",
                               extra={"frontend": True})
                raise HTTPException(status_code=401, detail=WRONG_LOGIN)
            throttle.succeeded(name)
            logger.info("signed in: the break-glass admin", extra={"frontend": True})
            return BREAK_GLASS_USER, break_glass_cookie(), BREAK_GLASS_SECONDS

        if name in RESERVED_NAMES:
            raise HTTPException(status_code=400, detail=f"'{name}' is a name deadwax keeps for itself - nobody signs in as it.")
        if store is None or not getattr(store, "available", False):
            raise HTTPException(status_code=503, detail=NO_DATABASE)

        salt = secrets.token_hex(16)
        token = subsonic_token(password, salt)
        try:
            answered = await check_login(typed.strip(), token, salt)
        except NavidromeError as e:
            if e.code == 40:
                throttle.failed(name)
                logger.info(f"a sign-in as {name[:60]} was refused: Navidrome didn't take the password", extra={"frontend": True})
                raise HTTPException(status_code=401, detail=WRONG_LOGIN) from e
            if e.code == 41:
                raise HTTPException(status_code=502, detail=(
                    "Navidrome can't check this account with a token (LDAP accounts can't), and deadwax only "
                    "signs in with tokens - use a local Navidrome account.")) from e
            if e.unreachable or e.status == 503:
                raise HTTPException(status_code=503, detail=(
                    "Navidrome isn't answering, so deadwax can't check your password right now - try again "
                    "in a moment." if e.unreachable else f"deadwax can't ask Navidrome: {e}")) from e
            raise HTTPException(status_code=502, detail=f"Navidrome couldn't check your password: {e}") from e
        throttle.succeeded(name)

        #? the identity is the Navidrome user name, lowercased - the one Navidrome answered with where it
        #? is the same name, else the one typed
        user = answered.strip().lower() if answered and answered.strip().lower() == name else name
        raw = new_session_id()
        now = time.time()
        try:
            await asyncio.to_thread(store.create_session, id_hash(raw), user, seal_credential(typed.strip(), token, salt),
                                    now, now + SESSION_IDLE_SECONDS)
        except Exception as e:
            logger.error(f"could not keep {user}'s session ({type(e).__name__}: {e})", extra={"frontend": True})
            raise HTTPException(status_code=503, detail=NO_DATABASE) from e

        if user in Config.admins():
            taken = await store.adopt_local(user)
            if taken and any(taken):
                pins, preferences = taken
                logger.info(f"{user} took over what deadwax saved before logins: {pins} pin(s) and "
                            f"{preferences} preference(s)", extra={"frontend": True})
        logger.info(f"signed in: {user}", extra={"frontend": True})
        return user, raw, COOKIE_MAX_AGE


def sign_out(store, raw: str | None) -> None:
    """End the session this cookie names, if it names one: from the database and memory, or - for a
    break-glass cookie - remembered as signed out. SYNCHRONOUS; raises on a database error."""
    if not raw:
        return
    if raw.startswith("b."):
        revoke_break_glass(raw)
        return
    key = id_hash(raw)
    _note_ended(key, SIGNED_OUT)
    if store is not None and getattr(store, "available", False):
        store.delete_session(key)


# ===== the re-check =================================================================================

async def check_sessions(store, now: float | None = None) -> dict[str, int]:
    """
    One pass of the re-check: every live session Navidrome hasn't vouched for in RECHECK_SECONDS is put
    to getUser again with its own token - one per person a pass, so the re-check never makes a run of
    failures for one account. Error 40 ends the session (the password changed, or the account is gone);
    a token that won't decrypt (another DEADWAX_SECRET_KEY) ends it too; anything else - Navidrome down,
    an address that won't do - ends nothing, and it is asked again next pass. Then expired sessions go.
    """
    now = time.time() if now is None else now
    counts = {"checked": 0, "ended": 0, "unanswered": 0, "expired": 0}
    due = await asyncio.to_thread(store.sessions_due, now - RECHECK_SECONDS, now)
    asked: set[str] = set()
    for row in due:
        if row["user"] in asked:
            continue
        asked.add(row["user"])
        credential = unseal_credential(row["credential"])
        if credential is None:
            await asyncio.to_thread(end_session, store, row["id_hash"], KEY_CHANGED)
            counts["ended"] += 1
            continue
        username, token, salt = credential
        try:
            await check_login(username, token, salt)
        except NavidromeError as e:
            if e.code == 40:
                await asyncio.to_thread(end_session, store, row["id_hash"], LOGIN_GONE)
                counts["ended"] += 1
                logger.info(f"signed {row['user']} out: Navidrome no longer accepts the login they signed in with",
                            extra={"frontend": True})
            else:
                counts["unanswered"] += 1
            continue
        await asyncio.to_thread(store.session_checked, row["id_hash"], time.time())
        counts["checked"] += 1

    for key in await asyncio.to_thread(store.delete_expired_sessions, now):
        _note_ended(key, EXPIRED)
        counts["expired"] += 1
    return counts


async def run_session_checks(store) -> None:
    """The re-check, for as long as deadwax runs with logins on. A pass that fails is tried again next time."""
    while True:
        await asyncio.sleep(CHECK_EVERY_SECONDS)
        try:
            await check_sessions(store)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.error(f"the sign-in re-check couldn't run this time ({type(e).__name__}: {e})")
