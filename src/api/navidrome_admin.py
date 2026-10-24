"""
Navidrome's own accounts, asked AS THE SIGNED-IN PERSON (2.0.0-player.61, People - src/routes/people.py).

Subsonic can't manage accounts: Navidrome 0.64 answers createUser, updateUser, deleteUser and
changePassword with 501 (server/subsonic/api.go). So People goes through Navidrome's NATIVE API - the JSON
API its own web UI talks to itself with (react-admin's "JSON server" dialect, deluan/rest), UNDOCUMENTED
AND UNVERSIONED: every answer's shape is checked, and anything else is `unknown_shape` in words, never
guessed at. Nothing else in deadwax depends on it - sign-in, the re-check, the player, starring and
playlists are Subsonic - so a Navidrome that changed it degrades People alone. Every fact below was read
from Navidrome 0.64.2's source, never watched against a real one.

James (2026-10-21): "deadwax will use whoever is signed in for the navidrome account making changes". So
NOTHING HERE IS EVER ASKED AS NAVIDROME_USER: the key to the native API is a JWT, and only a password gets
one (`POST /auth/login`, server/auth.go doLogin) - which deadwax doesn't keep. So the person UNLOCKS People
with their own Navidrome password, once, and the JWT that gives is held for THAT SESSION alone, in memory
(`_unlocked`, by the session's id hash): 15 minutes since it was last used (UNLOCK_IDLE_SECONDS), ended by
Lock, by the session's end (src/auth.py _note_ended calls forget), by a restart, by Navidrome's 401, and
never sent to any address but the one it was got from (the base is checked on every use). Each answer's
refreshed JWT (the `X-ND-Authorization` response header, Navidrome's JWTRefresher) replaces it.

A FIXED LIST, as the player's Subsonic calls are: `login`, `list_users`, `get_user`, `create_user`,
`save_user` (the whole-record PUT: Navidrome's PUT writes every column from the body, so a password or the
admin flag is set by sending the record back whole) and `delete_user`. Each builds its method and path from
the constants below and an id checked against ID_PATTERN; nothing the page sends becomes a path or a
method. tests/test_people.py holds the list (test_the_native_api_is_a_fixed_list), and that only
src/routes/people.py, src/routes/own_password.py and src/auth.py import this module.

(2.0.2) Changing your OWN password (src/routes/own_password.py, You > Change password) asks through the same three of
the six - `login` as yourself with your current password (key None: nothing is held), `get_user` of your own record,
`save_user` of it whole with `password` and `currentPassword` - adding no operation.

THE LOGIN BUDGET IS SHARED. Navidrome limits `/auth/login` to 5 requests per 20 s per client address,
successful ones too, and every one of deadwax's comes from deadwax's one address - every admin unlocking,
and every sign-in that reads an account's id for its permissions. So deadwax holds itself to LOGIN_GATE
per LOGIN_WINDOW, one under, and says so (`held_off`) with nothing sent; nothing is ever retried.

NEVER LOGGED OR ANSWERED: a password, a JWT, a token - Navidrome's login answer also carries
`subsonicToken` and `subsonicSalt`, password-equivalent, which are dropped unread - or a request body.
`str(NativeError)` is its words alone. No redirect is followed (a 3xx is "not Navidrome").
"""

import re
import threading
import time
from collections import OrderedDict, deque
from dataclasses import dataclass

import httpx

from src import __version__
from src.config import Config, describe_navidrome_url

#? Navidrome's native API, as 0.64 has it (server/server.go, server/nativeapi/native_api.go)
LOGIN_PATH = "/auth/login"
USERS_PATH = "/api/user"
#? the header the JWT goes in, and its refreshed one comes back in (consts.UIAuthorizationHeader)
AUTH_HEADER = "X-ND-Authorization"

#? An account id as deadwax will put it in a path: 0.64's are 22 characters of base62, older ones UUIDs
ID_PATTERN = re.compile(r"^[A-Za-z0-9-]{1,64}$")

#? How long an unlock lasts unused, and how many are held at most (the oldest dropped)
UNLOCK_IDLE_SECONDS = 900.0
UNLOCKS_KEPT = 300

#? deadwax's own gate on /auth/login: one under Navidrome's 5 per 20 s (AuthRequestLimit, AuthWindowLength)
LOGIN_GATE = 4
LOGIN_WINDOW = 20.0

#? A read is given 10 s; a PUT or a DELETE 30 s - a write that times out, or loses its connection once it may have
#? been sent, is an unknown outcome (`timed_out`)
TIMEOUT_SECONDS = 10.0
WRITE_TIMEOUT_SECONDS = 30.0

#? What each kind of failure says (the page shows it; `{}` filled in by the raiser)
WORDS = {
    "not_set_up": "Navidrome isn't set up in deadwax.",
    "bad_address": "NAVIDROME_URL is unusable ({}), so deadwax sends nothing to it.",
    "unreachable": "Navidrome isn't answering, so People can't read or change accounts right now.",
    "locked": "Unlock People with your Navidrome password.",
    "login_gone": "Navidrome no longer takes the login you signed in to deadwax with.",
    "not_admin": "Navidrome says you're not one of its admins, so it won't let you change accounts.",
    "held_off": "Navidrome only takes a few sign-ins from deadwax every 20 seconds - try again in {} seconds.",
    "taken": "There's already a Navidrome account called {}.",
    "refused": "Navidrome refused it: {}.",
    "not_found": "That account isn't in Navidrome any more.",
    "not_you": "Navidrome answered for another account than yours, so deadwax won't use what it gave.",
    "unknown_shape": ("Navidrome answered in a way deadwax doesn't know ({}). People was made for Navidrome 0.64 and "
                      "uses its web UI's own interface, which can change between versions - change accounts in "
                      "Navidrome's Users page meanwhile."),
    "timed_out": "Navidrome didn't answer in time.",
}

#? ...and what to do about them, where there is something
FIXES = {
    "not_set_up": "Server settings → Connections",
    "not_admin": "an admin can make you one, here or in Navidrome's Users page",
}


class NativeError(Exception):
    """A native API call that didn't work: `kind` (WORDS' keys), the words said, the status deadwax answers with.
    Its str() is the words alone - never a URL, a body or a header."""

    def __init__(self, kind: str, words: str, status: int = 502, retry_after: int | None = None):
        super().__init__(words)
        self.kind = kind
        self.words = words
        self.status = status
        self.fix = FIXES.get(kind)
        self.retry_after = retry_after

    def __str__(self) -> str:
        return self.words


def _error(kind: str, *fill, status: int = 502, retry_after: int | None = None) -> NativeError:
    return NativeError(kind, WORDS[kind].format(*fill), status, retry_after)


@dataclass
class Unlock:
    """People unlocked in one session: whose (the session's own name, lowercased), their Navidrome account's id
    and whether Navidrome said they are its admin, the JWT (replaced by each answer's refreshed one), the
    address it was got from, and when it was last used. `key` is the session's id hash it is held under -
    None for a login made only to read an account's id (src/auth.py), which nothing holds."""

    key: str | None
    user: str
    navidrome_id: str
    admin: bool
    jwt: str
    base: str
    last_used: float


#? The failures that mean no request ever left deadwax: no connection made, or none to be had from the pool
NOTHING_SENT = (httpx.ConnectError, httpx.ConnectTimeout, httpx.PoolTimeout)

_lock = threading.Lock()
_unlocked: "OrderedDict[str, Unlock]" = OrderedDict()
#? when each /auth/login of the last LOGIN_WINDOW went out
_logins: "deque[float]" = deque()
#? the clock unlocks and the gate are timed by - a test moves it
_clock = time.monotonic


def _base() -> str:
    """NAVIDROME_URL's root, held to describe_navidrome_url as the Subsonic clients are - or NativeError."""
    if not Config.NAVIDROME_URL:
        raise _error("not_set_up", status=409)
    problem = describe_navidrome_url(Config.NAVIDROME_URL)
    if problem:
        raise _error("bad_address", problem, status=503)
    return Config.NAVIDROME_URL.rstrip("/")


class _Client:
    """The one httpx client People asks through - its own, apart from the Subsonic ones: no redirects
    followed, deadwax's own user agent, no header of the browser's."""

    def __init__(self):
        self.client: httpx.AsyncClient | None = None
        self.base: str | None = None

    async def get(self, base: str) -> httpx.AsyncClient:
        if self.client is None or self.client.is_closed or self.base != base:
            await self.close()
            self.client = httpx.AsyncClient(base_url=base, timeout=httpx.Timeout(TIMEOUT_SECONDS),
                                            follow_redirects=False,
                                            headers={"User-Agent": f"deadwax/{__version__}"})
            self.base = base
        return self.client

    async def close(self) -> None:
        if self.client is not None and not self.client.is_closed:
            await self.client.aclose()
        self.client = None


_native = _Client()


async def close_client() -> None:
    await _native.close()


# ----------------------------------------------------------------- unlocks

def forget(key: str) -> None:
    """The unlock held for this session, if any, gone - Lock, the session's end."""
    with _lock:
        _unlocked.pop(key, None)


def forget_user(user: str) -> int:
    """(2.0.2) Every unlock held for `user`, in whichever session, gone - they changed their own password, which kills
    every JWT of theirs in Navidrome anyway. How many there were."""
    with _lock:
        keys = [key for key, held in _unlocked.items() if held.user == user]
        for key in keys:
            del _unlocked[key]
    return len(keys)


def forget_all() -> None:
    """Every unlock gone, and the gate emptied - a restart (tests)."""
    with _lock:
        _unlocked.clear()
        _logins.clear()


def unlocked(key: str) -> Unlock | None:
    """This session's unlock - None when there is none, it has been idle UNLOCK_IDLE_SECONDS, or NAVIDROME_URL
    is not the address it was got from (the JWT is then never sent anywhere)."""
    with _lock:
        held = _unlocked.get(key)
    if held is None:
        return None
    try:
        base = _base()
    except NativeError:
        base = None
    if _clock() - held.last_used >= UNLOCK_IDLE_SECONDS or held.base != base:
        forget(key)
        return None
    return held


def _hold(unlock: Unlock) -> None:
    with _lock:
        _unlocked[unlock.key] = unlock
        _unlocked.move_to_end(unlock.key)
        while len(_unlocked) > UNLOCKS_KEPT:
            _unlocked.popitem(last=False)


def _gate() -> None:
    """One more /auth/login from deadwax, if the gate has room - else `held_off`, with nothing sent."""
    now = _clock()
    with _lock:
        while _logins and now - _logins[0] >= LOGIN_WINDOW:
            _logins.popleft()
        if len(_logins) >= LOGIN_GATE:
            wait = max(1, int(LOGIN_WINDOW - (now - _logins[0]) + 0.999))
            raise _error("held_off", wait, status=429, retry_after=wait)
        _logins.append(now)


# ----------------------------------------------------------------- the six

async def login(name: str, password: str, expect: str, key: str | None = None) -> Unlock:
    """
    `POST /auth/login` as `name` (the name the session signed in with, as typed then), through deadwax's own
    gate: the answer's `id`, `isAdmin` and `token` (the JWT) - nothing else of it is read. Its `username` must
    be `expect`'s, whatever the case. With `key`, and Navidrome saying they are its admin, the unlock is held
    for that session. NativeError: `login_gone` for Navidrome's 401 (the login no longer stands), `held_off`
    for the gate or Navidrome's 429, `unreachable`, `unknown_shape`.
    """
    base = _base()
    _gate()
    client = await _native.get(base)
    try:
        response = await client.post(LOGIN_PATH, json={"username": name, "password": password})
    except httpx.TransportError as e:
        raise _error("unreachable", status=503) from e
    except httpx.HTTPError as e:
        raise _error("unknown_shape", type(e).__name__) from e
    if response.status_code == 401:
        raise _error("login_gone", status=401)
    if response.status_code == 429:
        raise _error("held_off", int(LOGIN_WINDOW), status=429, retry_after=int(LOGIN_WINDOW))
    if response.status_code != 200:
        raise _error("unknown_shape", response.status_code)
    try:
        body = response.json()
    except ValueError as e:
        raise _error("unknown_shape", "not JSON") from e
    if not (isinstance(body, dict) and isinstance(body.get("token"), str) and body["token"]
            and isinstance(body.get("id"), str) and isinstance(body.get("isAdmin"), bool)
            and isinstance(body.get("username"), str)):
        raise _error("unknown_shape", "its sign-in's answer")
    if body["username"].strip().lower() != expect.strip().lower():
        raise _error("not_you", status=409)
    unlock = Unlock(key, expect.strip().lower(), body["id"], body["isAdmin"], body["token"], base, _clock())
    if key is not None and unlock.admin:
        _hold(unlock)
    return unlock


def _checked_id(navidrome_id: str) -> str:
    if not isinstance(navidrome_id, str) or not ID_PATTERN.match(navidrome_id):
        raise _error("not_found", status=404)
    return navidrome_id


def _errors(response: httpx.Response) -> dict:
    try:
        body = response.json()
    except ValueError:
        return {}
    errors = body.get("errors") if isinstance(body, dict) else None
    return errors if isinstance(errors, dict) else {}


async def _ask(unlock: Unlock, method: str, path: str, body: dict | None = None, write: bool = False):
    """One native API call with this unlock's JWT - its answer's JSON, the refreshed JWT kept. The base is checked
    first: a JWT is only ever sent to the address it was got from."""
    base = _base()
    if unlock.base != base:
        if unlock.key is not None:
            forget(unlock.key)
        raise _error("locked", status=409)
    client = await _native.get(base)
    timeout = httpx.Timeout(WRITE_TIMEOUT_SECONDS if write else TIMEOUT_SECONDS)
    try:
        response = await client.request(method, path, json=body, timeout=timeout,
                                        headers={AUTH_HEADER: f"Bearer {unlock.jwt}"})
    except NOTHING_SENT as e:
        #? no connection was ever made, so nothing reached Navidrome: a write too is plainly "not answering"
        raise _error("unreachable", status=503) from e
    except httpx.TransportError as e:
        #? (review) sent, or perhaps sent, and then no answer - a timeout, the connection dropped mid-answer (Navidrome
        #? restarting, a proxy closing it): for a WRITE that is an unknown outcome, never "nothing changed"
        raise (_error("timed_out", status=504) if write else _error("unreachable", status=503)) from e
    except httpx.HTTPError as e:
        raise _error("unknown_shape", type(e).__name__) from e
    status = response.status_code
    if status == 401:
        #? the JWT is dead - their password changed (each password write bumps the account's token epoch), or
        #? the account went - and there is no password here to ask for another: locked
        if unlock.key is not None:
            forget(unlock.key)
        raise NativeError("locked", "Navidrome asked for your password again - unlock People with it.", 409)
    refreshed = response.headers.get(AUTH_HEADER)
    if refreshed:
        unlock.jwt = refreshed.removeprefix("Bearer ").strip()
    unlock.last_used = _clock()
    if status == 403:
        raise _error("not_admin", status=403)
    if status == 404:
        raise _error("not_found", status=404)
    if status == 429:
        raise _error("held_off", int(LOGIN_WINDOW), status=429, retry_after=int(LOGIN_WINDOW))
    if status == 400:
        errors = _errors(response)
        said = "; ".join(f"{field}: {code}" for field, code in list(errors.items())[:3]) or "400"
        raise NativeError("refused", WORDS["refused"].format(said), 409)
    if status != 200:
        raise _error("unknown_shape", status)
    try:
        return response.json()
    except ValueError as e:
        raise _error("unknown_shape", "not JSON") from e


def _user_shaped(found) -> bool:
    return (isinstance(found, dict) and isinstance(found.get("id"), str) and isinstance(found.get("userName"), str)
            and isinstance(found.get("isAdmin"), bool))


async def list_users(unlock: Unlock) -> list[dict]:
    """`GET /api/user`: every account (an admin's to read)."""
    found = await _ask(unlock, "GET", USERS_PATH)
    if not (isinstance(found, list) and all(_user_shaped(user) for user in found)):
        raise _error("unknown_shape", "its list of users")
    return found


async def get_user(unlock: Unlock, navidrome_id: str) -> dict:
    """`GET /api/user/{id}`: one account, as Navidrome has it now."""
    found = await _ask(unlock, "GET", f"{USERS_PATH}/{_checked_id(navidrome_id)}")
    if not _user_shaped(found):
        raise _error("unknown_shape", "a user")
    return found


async def create_user(unlock: Unlock, user: str, name: str, password: str) -> str:
    """`POST /api/user` with exactly an ordinary account's fields: the new account's id. `taken` when the name
    is (Navidrome's 400 on userName - names are unique whatever their case)."""
    try:
        made = await _ask(unlock, "POST", USERS_PATH, {"userName": user, "name": name, "email": "", "isAdmin": False,
                                                       "password": password}, write=True)
    except NativeError as e:
        if e.kind == "refused" and "userName" in e.words:
            raise NativeError("taken", WORDS["taken"].format(user), 409) from e
        raise
    if not (isinstance(made, dict) and isinstance(made.get("id"), str) and made["id"]):
        raise _error("unknown_shape", "a new user's id")
    return made["id"]


async def save_user(unlock: Unlock, navidrome_id: str, record: dict) -> dict:
    """`PUT /api/user/{id}` with the WHOLE record (Navidrome's PUT writes every column from the body, and a PUT to
    an id it doesn't have makes one - so the caller GETs it first and sends it back with one change): the account
    as Navidrome answers it."""
    saved = await _ask(unlock, "PUT", f"{USERS_PATH}/{_checked_id(navidrome_id)}", record, write=True)
    if not _user_shaped(saved):
        raise _error("unknown_shape", "a saved user")
    return saved


async def delete_user(unlock: Unlock, navidrome_id: str) -> None:
    """`DELETE /api/user/{id}`: the account, and in Navidrome everything of it (its plays, stars, playlists...)."""
    await _ask(unlock, "DELETE", f"{USERS_PATH}/{_checked_id(navidrome_id)}", write=True)
