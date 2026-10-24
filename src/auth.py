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
  kept (the re-check below needs it, and since 2.0.0-player.52 the player asks Navidrome as each user with
  it - src/api/navidrome_endpoint.py's client_for) ENCRYPTED with a key
  from the environment, DEADWAX_SECRET_KEY, through the `cryptography` package's Fernet - never a
  cipher of our own. Without the key logins don't work at all: every protected route answers 503
  and says why, rather than storing a token bare. The password itself is never kept or logged.

  NOTHING RETRIES A SIGN-IN, and sign-ins are throttled per name (Throttle): Navidrome blocks an
  account for a while after a run of failures, and a bot hammering deadwax must not be able to get
  James blocked through it. The re-check asks Navidrome about each person at most once a pass. The
  break-glass name alone is throttled per name AND client address (break_glass_key), since it is public.

  A SESSION is a random id (secrets.token_urlsafe) in an HttpOnly, SameSite=Strict cookie named
  `deadwax_session` (Navidrome's own is `jwt`), Secure when the page came over HTTPS. The database
  keeps only the id's SHA-256, so a copy of the file is no live cookie; sessions are kept there so a
  restart signs nobody out, and held in memory a minute at a time so a stream's every byte range
  doesn't read the database. The expiry slides forward with use (SESSION_IDLE_SECONDS), so the
  phone doesn't ask again mid-song.

  RE-CHECKED: every few minutes (RECHECK_SECONDS) each live session's token is put to getUser again.
  Error 40 - the password changed, or the account is gone - ends the session, and the next request
  answers 401 saying why. Navidrome not answering ends nothing: it is proof of nothing.

  ADMINS ARE NAVIDROME'S ADMINS (2.0.0-player.61 - until then deadwax's own list, DEADWAX_ADMINS,
  which is ignored now and said so at start-up): a person is deadwax's admin exactly when their own
  Navidrome account is one, as getUser's `adminRole` last said. Read at the sign-in (check_login asks
  getUser as them anyway), re-read at every re-check (so a change made in Navidrome reaches deadwax
  within about six minutes), and set at once when People changes it (set_role). Navidrome not
  answering changes nothing - the last word stands, as for the session itself. UNKNOWN IS NOT ADMIN:
  a session with no flag yet, an `adminRole` missing or not a boolean, are an ordinary person's. The
  role is kept on the session's row (`sessions.admin`), on each session held in memory, and in a map
  by user (`_roles`) that src/users.py's is_admin reads.

  BREAK-GLASS: DEADWAX_ADMIN_PASSWORD signs in the fixed admin `deadwax` (since 2.0.0-player.61 - it
  was `admin` until then, which is an ordinary Navidrome name now) with neither Navidrome nor the
  database, for when Navidrome is down or nobody is a Navidrome admin - a cookie sealed with
  DEADWAX_SECRET_KEY (Fernet, so it is signed and dated), good for BREAK_GLASS_SECONDS, and bound to
  the password: changing the password ends every one. The password is compared in constant time. A
  cookie made under the old name holds `"u": "admin"`, which break_glass_user refuses, so it ends at
  its next request - and, a `b.` cookie, it never reaches the session table, so it can never be read
  as Navidrome's `admin`.

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
import ipaddress
import time
from collections import OrderedDict, deque
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Callable, Hashable

import httpx
from cryptography.fernet import Fernet, InvalidToken
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from fastapi import HTTPException

from src import __version__, library_ledger, permissions
from src.api import navidrome_admin
from src.api.navidrome_endpoint import API_VERSION, CLIENT_NAME, NavidromeError, subsonic_body, unusable_url
from src.config import Config, describe_navidrome_url, describe_secret_key
from src.logger import logger

#? The session cookie's name. Not `jwt`, which is Navidrome's - cookies aren't kept apart by port,
#? so on one host the two would overwrite each other.
COOKIE = "deadwax_session"

#? The break-glass admin's fixed name (DEADWAX_ADMIN_PASSWORD). Nobody signs in AS this through
#? Navidrome: the name is reserved, so a Navidrome account called `deadwax` can't become deadwax's
#? break-glass admin by its name alone. (2.0.0-player.61) It was `admin` until then - renamed so that
#? Navidrome's own `admin` account, a Navidrome admin and so deadwax's, can sign in as itself.
BREAK_GLASS_USER = "deadwax"

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
#? (2.0.4) a listener's words: the setting behind it (another DEADWAX_SECRET_KEY) is said in the event log, as
#? _end_unopenable and the re-check say it
KEY_CHANGED = "deadwax's sign-ins have been reset since you signed in - sign in again."
BREAK_GLASS_ENDED = ("The break-glass sign-in has ended - it lasts 12 hours, and ends when "
                     "DEADWAX_ADMIN_PASSWORD changes. Sign in again.")
#? (2.0.4) what anyone reads when the database can't be read, and (NO_DATABASE_WHY) what whoever runs deadwax
#? needs - answered as an Explained, so the app shows the second to an admin, and on the sign-in screen under
#? "For whoever runs deadwax", never as the line everyone reads
NO_DATABASE = "deadwax can't read its database just now, so it can't check who you are."
NO_DATABASE_WHY = ("deadwax can't read its database, so nothing is let in until it can. Check DB_PATH points at a "
                   "writable volume.")
#? (2.0.4) ...and when logins can't work at all (unusable(): the key, or organizing off) - its why is unusable()'s
CANT_SIGN_IN = "deadwax isn't ready for signing in, so nobody can use it just now."
#? (2.0.4) the sign-in's own words for Navidrome not letting it check a password - its why Navidrome's or the setting's
NAVIDROME_UNSET = "deadwax can't reach the music server, so nobody can sign in just now."
NAVIDROME_REFUSED = "Navidrome couldn't check your password just now - try again in a moment."
LDAP_ACCOUNT = ("This account can't sign in to deadwax: it's an LDAP account, and deadwax needs a local Navidrome "
                "account. Ask an admin for one.")
WRONG_LOGIN = "That user name and password didn't work."
#? (2.0.0-player.61) What the next request of a session People ended is told
PASSWORD_RESET = "An admin reset your password - sign in with the new one."
ACCOUNT_REMOVED = "Your account was removed."
#? (2.0.2) What the next request of a person's OTHER sessions is told when they changed their own password from deadwax
PASSWORD_CHANGED = "Your password was changed from another device - sign in with the new one."
#? (2.0.0-player.61 review) a session kept under a name deadwax now keeps for itself - a Navidrome account called
#? `deadwax` signed in before break-glass took that name. It ends at its first request, never standing for
#? break-glass (JobStore.init also deletes such rows, once, as the upgrade's migration).
RESERVED_SESSION = ("deadwax keeps that user name for itself now, so the sign-in it had has ended - sign in with "
                    "another Navidrome account.")


class Explained(HTTPException):
    """
    (2.0.4) A refusal in two halves: `detail`, the sentence anyone reads - no setting, no exception, no address -
    and `why`, what whoever runs deadwax needs to fix it. Answered as {"detail", "why"} (src/api/app.py); the app
    (ui/src/lib/errorWords.ts) shows `why` only to an admin or someone with Settings and the log, and the sign-in
    screen under "For whoever runs deadwax" - it can't know who is reading there. The status is the HTTPException's.
    """

    def __init__(self, status_code: int, detail: str, why: str, headers: dict[str, str] | None = None):
        super().__init__(status_code=status_code, detail=detail, headers=headers)
        self.why = why


def cant_sign_in(problem: str) -> Explained:
    """The 503 every request is answered with while unusable() says logins can't work."""
    return Explained(503, CANT_SIGN_IN, problem)


def no_database() -> Explained:
    """The 503 for a database that can't be read (a session, a sign-in)."""
    return Explained(503, NO_DATABASE, NO_DATABASE_WHY)


def unusable() -> str | None:
    """Why nobody can sign in at all right now, in words for whoever asks - or None. Logins on only.

    The secret key missing; and (2.0.0-player.49) organizing not on: downloads are per person with
    logins on, and under ORGANIZE_MODE dry_run (or off) nothing is ever filed, so nothing could be
    granted to the people who asked or found already held - logins are refused until it's copy or move
    (Config.describe_logins_organizing), every protected route answering 503 with the reason, as for the key."""
    problem = describe_secret_key(Config.DEADWAX_SECRET_KEY)
    if problem:
        return (f"Logins are on, but DEADWAX_SECRET_KEY {problem}, so deadwax can't sign anyone in. "
                f"Set it in the container's environment and recreate the container (a restart keeps the old values).")
    organizing = Config.describe_logins_organizing()
    if organizing:
        return f"Logins are on, but {organizing}"
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
    #? (2.0.0-player.52) the sealed Navidrome login the session was signed in with - what the player asks
    #? Navidrome AS (PlayerLogin, src/api/navidrome_endpoint.py client_for)
    credential: str = ""
    #? (2.0.0-player.61) Navidrome's admin flag for the session's user, as last read (sessions.admin) - and
    #? the Navidrome account's id as read at the sign-in, for permissions bound to it (src/permissions.py):
    #? None when it wasn't read (nobody had given them anything, or Navidrome couldn't be asked)
    admin: bool = False
    navidrome_id: str | None = None


#? Guards everything below: current_user runs in FastAPI's thread pool, the sign-in and the re-check on
#? the event loop.
_lock = threading.Lock()
_held: dict[str, _Held] = {}
#? sessions ended here (signed out, error 40, a key that changed), by id hash, with why - so the request
#? that comes next is told the reason rather than only "sign in". Bounded: the oldest go first.
_ended: "OrderedDict[str, str]" = OrderedDict()
ENDED_KEPT = 1000


#? (2.0.0-player.49) whether this process has looked for what `local` still holds, to hand it to the
#? first admin it sees with a session - _take_over_leftovers. Under _lock.
_leftovers_looked = False

#? (2.0.0-player.61) Navidrome's admin flag by user, as last read - written whenever a session row is read
#? (_session, at most every CACHE_SECONDS), at a sign-in, by the re-check and by People (set_role). What
#? src/users.py's is_admin reads: anyone it doesn't know is NOT an admin (fail closed). Bounded - a
#? household's handful; past ROLES_KEPT it is emptied and filled again from the next reads.
_roles: dict[str, bool] = {}
ROLES_KEPT = 10000
#? (2.0.0-player.61 review) WHEN each user's role was last set, on one clock that only goes forward (`now`, bumped
#? by every set_role): an answer read before a change - a session row, a re-check's or a sign-in's getUser - is
#? never let undo it (role_mark, set_role's `since`). `floor` is the clock when the map was last emptied: a user
#? missing from it counts as changed then. Under _lock.
_role_changes: dict[str, int] = {}
_role_clock = {"now": 0, "floor": 0}
#? set_role's write and its memory, one at a time, so two of them can't land in the database in one order and in
#? memory in the other
_role_write = threading.Lock()


def forget_sessions() -> None:
    """Drop everything held in memory (tests; the database is untouched) - as a restart would."""
    global _leftovers_looked
    with _lock:
        _held.clear()
        _ended.clear()
        _revoked_glass.clear()
        _roles.clear()
        _role_changes.clear()
        _role_clock["floor"] = _role_clock["now"]
        _resealed.clear()
        _rotated.clear()
        _leftovers_looked = False
    navidrome_admin.forget_all()


def _note_ended(key: str, reason: str, keep: bool = False) -> None:
    """The session `key` ended in this process, `reason` told to its next request. With `keep` (a refusal of its
    login - player_refused, the re-check), a reason already noted stands: a call in flight when the session was
    ended for something else (2.0.2 review: PASSWORD_CHANGED, People's PASSWORD_RESET) and refused after it must not
    turn the words the device is shown into LOGIN_GONE."""
    with _lock:
        _held.pop(key, None)
        if keep and key in _ended:
            reason = _ended[key]
        _ended[key] = reason
        _ended.move_to_end(key)
        while len(_ended) > ENDED_KEPT:
            _ended.popitem(last=False)
    #? (2.0.0-player.61) an unlocked People ends with the session it was unlocked in
    navidrome_admin.forget(key)


def _note_role(user: str, admin: bool) -> None:
    """The map's word for `user` - under _lock, by the caller."""
    if len(_roles) >= ROLES_KEPT and user not in _roles:
        _roles.clear()
    _roles[user] = bool(admin)


def role_mark() -> int:
    """(2.0.0-player.61 review) The role clock now - taken before Navidrome is asked (or a session row read), and
    handed to set_role as `since`, so an answer older than People's change never undoes it."""
    with _lock:
        return _role_clock["now"]


def _changed_since(user: str, mark: int) -> bool:
    """Whether `user`'s role was set after `mark` - under _lock, by the caller."""
    return _role_changes.get(user, _role_clock["floor"]) > mark


def role(user: str) -> bool:
    """(2.0.0-player.61) Whether `user` is a Navidrome admin, as deadwax last read it - False for anyone it
    hasn't read (fail closed). What src/users.py's is_admin asks with logins on."""
    with _lock:
        return _roles.get(user, False)


def set_role(store, user: str, admin: bool, since: int | None = None) -> bool:
    """
    (2.0.0-player.61) Navidrome's admin flag for `user` is `admin` now: in the database (every session of
    theirs, so they all agree), then every session of theirs held in memory, then the map - so their next
    request is answered in the new role. SYNCHRONOUS; raises on a database error, with nothing in memory
    changed. The sign-in, the re-check and People call it.

    With `since` (role_mark, taken before Navidrome was asked), NOTHING is written when the role was set after
    it - People's change is newer than the answer, and stands (review: the re-check, or a sign-in, waiting on
    the database between Navidrome's answer and this, put back a role People had just taken away). Whether it
    wrote.
    """
    with _role_write:
        if since is not None:
            with _lock:
                if _changed_since(user, since):
                    return False
        store.set_user_admin(user, bool(admin))
        with _lock:
            _role_clock["now"] += 1
            _role_changes[user] = _role_clock["now"]
            if len(_role_changes) > ROLES_KEPT:
                _role_changes.clear()
                _role_clock["floor"] = _role_clock["now"]
            for held in _held.values():
                if held.user == user:
                    held.admin = bool(admin)
            _note_role(user, admin)
    return True


def note_account_id(user: str, navidrome_id: str, keys: list[str]) -> None:
    """(2.0.0-player.61) These sessions of `user` (id hashes), held in memory, whose sign-in couldn't read their
    account's id given it - an admin's People list has just named it, and store.heal_session_ids healed exactly
    these rows: the ones begun since that account was made (review - never one of an earlier account of the name)."""
    wanted = set(keys)
    with _lock:
        for key, held in _held.items():
            if key in wanted and held.user == user and held.navidrome_id is None:
                held.navidrome_id = navidrome_id


def end_held_sessions(user: str, keys: list[str], reason: str) -> int:
    """(2.0.0-player.61) End these sessions of `user` in memory - and any other of theirs held there - with
    `reason` told to the next request: what end_user_sessions and People's removal do before the database.
    How many it ended."""
    with _lock:
        extra = [key for key, held in _held.items() if held.user == user]
    ended = set(keys) | set(extra)
    for key in ended:
        _note_ended(key, reason)
    return len(ended)


def end_user_sessions(store, user: str, reason: str) -> int:
    """
    (2.0.0-player.61) End every session of `user` at once - in memory first, then the database - with
    `reason` told to the next request of each (People's reset: PASSWORD_RESET). How many sessions there
    were. SYNCHRONOUS; raises on a database error (the sessions are ended in memory by then).
    """
    keys = store.session_keys(user)
    ended = end_held_sessions(user, keys, reason)
    store.delete_user_sessions(user)
    return ended


def end_session(store, key: str, reason: str, keep: bool = False) -> None:
    """End one session, by id hash: gone from the database and from memory. SYNCHRONOUS - raises on a database error.
    `keep`: as _note_ended's - a reason already noted for it stands."""
    _note_ended(key, reason, keep)
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
    return _session(store, raw, now)[1].user


def _session(store, raw: str, now: float | None = None) -> tuple[str, _Held]:
    """session_user's work: the session's id hash and what is held of it (its user, and since
    2.0.0-player.52 the login it was signed in with). Raises as session_user does."""
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
        return key, held

    #? (2.0.0-player.61 review) the role clock before the row is read: a role set while it was being read (People,
    #? the re-check) is newer than the row's, and is the one held
    mark = role_mark()
    #? (2.0.2 review) and the re-seal clock: a password change re-sealing this session while its row was being read
    #? is newer than the row, and its login is the one held
    sealed_mark = reseal_mark()
    row = store.session(key)
    if row is None:
        with _lock:
            _held.pop(key, None)
        raise signed_out(SIGNED_OUT)
    if row["user"] in RESERVED_NAMES:
        #? (2.0.0-player.61 review) a row can never stand for `local` or the break-glass admin, whose names are
        #? checked only at a sign-in: one left from before a name was reserved ends here, as a session
        _end_reserved(store, key, row)
        raise signed_out(RESERVED_SESSION)
    if row["expires_at"] <= now:
        end_session(store, key, EXPIRED)
        raise signed_out(EXPIRED)
    #? (2.0.0-player.52 review) the login the session was signed in with must still open: the player asks
    #? Navidrome with it, and one sealed under another DEADWAX_SECRET_KEY (changed, and deadwax restarted -
    #? which empties what is held here, so the first request after reads the row) would have every player
    #? call refused while /me and the rest still said "signed in" - and the app's sign-in screen, asking /me,
    #? come and go until the re-check ended it minutes later. So the session ends here, at its first request,
    #? as the re-check would end it. Opened once per read of the row (CACHE_SECONDS), never per byte range.
    if unseal_credential(row.get("credential") or "") is None:
        _end_unopenable(store, key, row)
        raise signed_out(KEY_CHANGED)
    held = _Held(row["user"], row["expires_at"], row["last_seen"], time.monotonic(), row.get("credential") or "",
                 admin=bool(row.get("admin")), navidrome_id=row.get("navidrome_id") or None)
    with _lock:
        if _changed_since(held.user, mark):
            #? set since the row was read: the map has the newer word (unknown is not an admin)
            held.admin = _roles.get(held.user, False)
        resealed = _resealed.get(key)
        if resealed is not None and resealed[0] > sealed_mark:
            held.credential = resealed[1]
        _held[key] = held
        #? (2.0.0-player.61) the role as the database has it - what is_admin reads for this user
        _note_role(held.user, held.admin)
    if now - held.touched >= TOUCH_SECONDS:
        _touch(store, key, held, now)
    return key, held


def _end_reserved(store, key: str, row: dict) -> None:
    """(2.0.0-player.61 review) A session row under a reserved name ends - RESERVED_SESSION told to the next request.
    Best effort, as _end_unopenable: a database that refuses the delete leaves it ended in memory."""
    _note_ended(key, RESERVED_SESSION)
    try:
        store.delete_session(key)
    except Exception as e:
        logger.warning(f"could not take a session kept under the reserved name {row.get('user')} out of the database "
                       f"({type(e).__name__}: {e})")
    logger.warning(f"ended a sign-in kept under '{row.get('user')}', a name deadwax keeps for itself now",
                   extra={"frontend": True})


def _end_unopenable(store, key: str, row: dict) -> None:
    """(2.0.0-player.52 review) A session whose login won't open (another DEADWAX_SECRET_KEY) ends as the re-check
    ends it - KEY_CHANGED told to the next request, the user's kept login dead when it is that same one. Best
    effort: a database that refuses the delete leaves it ended in memory, and the next read tries again."""
    _note_ended(key, KEY_CHANGED)
    try:
        store.delete_session(key)
    except Exception as e:
        logger.warning(f"could not take {row.get('user')}'s ended session out of the database ({type(e).__name__}: {e})")
    _credential_dead(store, row, KEY_CHANGED)
    logger.info(f"signed {row.get('user')} out: their sign-in was sealed with another DEADWAX_SECRET_KEY",
                extra={"frontend": True})


def user_for(request) -> str:
    """
    The signed-in user a request comes from, with logins on - what src/users.py's current_user answers.
    401 with no session or one that no longer stands; 503 when logins can't work (no key) or the
    database can't be read. A break-glass cookie is checked first: it needs no database.
    """
    problem = unusable()
    if problem:
        raise cant_sign_in(problem)
    raw = request.cookies.get(COOKIE)
    if not raw:
        raise signed_out(SIGN_IN)
    if raw.startswith("b."):
        user = break_glass_user(raw)
        if user is None:
            raise signed_out(BREAK_GLASS_ENDED)
        #? (2.0.0-player.52) no Navidrome account behind it: the player asks as the shared one
        _remember_login(request, SHARED_LOGIN)
        return user

    store = getattr(request.app.state, "store", None)
    if store is None or not getattr(store, "available", False):
        raise no_database()
    try:
        key, held = _session(store, raw)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"could not read a session from the database, so the request was refused ({type(e).__name__}: {e})")
        raise no_database() from e
    user = held.user
    _remember_login(request, PlayerLogin(key, user, held.credential, store, held.navidrome_id))
    #? (2.0.0-player.61) a Navidrome admin, as the session holds it - deadwax's admin
    if held.admin:
        _take_over_leftovers(store, user)
    return user


# ===== the player, as you (2.0.0-player.52) ===========================================================

@dataclass(frozen=True)
class PlayerLogin:
    """
    Who the player asks Navidrome as, for one request (step 6 of the multi-user plan): the session's id hash,
    its user and the sealed login they signed in with - laid on every player call by
    src/api/navidrome_endpoint.py's client_for, so plays, scrobbles, "Not played", play counts and
    favourites are theirs. Set by user_for, on the request's state.
    """
    key: str
    user: str
    sealed: str
    store: object = None
    #? (2.0.0-player.61) the Navidrome account's id as read at the sign-in (sessions.navidrome_id) - None when
    #? it wasn't: what src/permissions.py binds an admin's grants to
    navidrome_id: str | None = None


#? The break-glass admin's: no Navidrome account of its own, so the player asks as NAVIDROME_USER - the
#? shared account, which a deadwax with logins off asks as for everyone (notes/logins.md says why)
SHARED_LOGIN = "shared"

#? The request state's name for it
LOGIN_STATE = "navidrome_login"


def _remember_login(request, login) -> None:
    """What the player asks as, kept on the request for client_for - quietly nothing for a request
    without state (a test's stand-in)."""
    state = getattr(request, "state", None)
    if state is not None:
        setattr(state, LOGIN_STATE, login)


def held_login(raw: str, store) -> "PlayerLogin | str | None":
    """(2.0.0-player.61) What a cookie just made at a sign-in asks Navidrome as - read back from its row, for the
    sign-in's own answer (its permissions, as /me will say them). SYNCHRONOUS; None when it can't be read."""
    if raw.startswith("b."):
        return SHARED_LOGIN
    key = id_hash(raw)
    try:
        row = store.session(key)
    except Exception:
        return None
    if row is None:
        return None
    return PlayerLogin(key, row["user"], row.get("credential") or "", store, row.get("navidrome_id") or None)


def session_ended(key: str) -> str | None:
    """Why the session with this id hash was ended in this process (signed out, refused, expired), or None."""
    with _lock:
        return _ended.get(key)


def player_refused(login: PlayerLogin, why: str = LOGIN_GONE) -> bool:
    """
    Navidrome refused the login a player call was made as (error 40 - the password changed, or the account
    is gone): the session ends as the re-check would end it - from memory and the database, `why` said to
    the next request - and the user's kept login dies too when it is that same login (a newer sign-in's
    stands). Also for a login that won't open at all (`why` KEY_CHANGED - another DEADWAX_SECRET_KEY, met
    while the session was still held in memory). True the first time for a session, so it is logged once
    however many calls were in flight. SYNCHRONOUS (the database); best effort - a database that fails
    still has the session ended here.

    (2.0.2) Not when the login is `superseded` - its person is changing their password from deadwax right now,
    or the session has been re-sealed with the new one since this login was read: the refusal says nothing
    about the session then, and it stands (False).
    """
    if superseded(login.store, login.user, login.key, login.sealed):
        return False
    first, told = _refusal(login.user, login.key, why)
    _note_ended(login.key, told, keep=True)
    store = login.store
    if store is not None and getattr(store, "available", False):
        try:
            store.delete_session(login.key)
        except Exception as e:
            logger.warning(f"could not take {login.user}'s ended session out of the database ({type(e).__name__}: {e})")
        _credential_dead(store, {"user": login.user, "credential": login.sealed}, why)
    if first:
        said = ("their sign-in was sealed with another DEADWAX_SECRET_KEY" if why == KEY_CHANGED
                else "their password was being changed from another device (the player was refused)"
                if told == PASSWORD_CHANGED
                else "Navidrome no longer accepts the login they signed in with (the player was refused)")
        logger.info(f"signed {login.user} out: {said}", extra={"frontend": True})
    return first


def _take_over_leftovers(store, user: str) -> None:
    """
    The first admin seen with a session after a start (2.0.0-player.61: a Navidrome admin, as the session
    holds it) takes over what `local` still holds - the
    downloads, pins and Getting albums settings saved while logins were off (store.adopt_local_now),
    as a sign-in does (sign_in). For an admin whose session outlived the restart that switched logins
    on - a session lasts 30 days from its last use - and who so may never sign in again: an upgrade
    from 2.0.0-player.48 (every download from before became `local`'s as job_requests was made), or
    logins switched off and on again (2.0.0-player.49 review: their rows read "Asked by local", and a
    finished download nobody can clear for `local` was never deleted). Logins only change at a
    restart and `local` gains nothing while they're on, so once a process is enough. Best effort and
    tried once: a database that fails here is logged, and the admin's next sign-in takes it over.
    SYNCHRONOUS, in FastAPI's thread pool, as user_for is.
    """
    global _leftovers_looked
    with _lock:
        if _leftovers_looked:
            return
        _leftovers_looked = True
    try:
        if store.local_has_anything():
            pins, preferences, requests = store.adopt_local_now(user)
            if pins or preferences or requests:
                logger.info(f"{user} took over what deadwax saved before logins: {pins} pin(s), {preferences} "
                            f"preference(s) and {requests} download(s)", extra={"frontend": True})
    except Exception as e:
        logger.error(f"could not hand {user} what deadwax saved before logins ({type(e).__name__}: {e}) - their "
                     f"next sign-in takes it over", extra={"frontend": True})
        return
    #? (2.0.0-player.51) and the store, into their library - once ever, as at a sign-in ("or the take-over")
    try:
        seeded = store.library_seeded()
    except Exception as e:
        logger.error(f"could not tell whether the store is in {user}'s library yet ({type(e).__name__}: {e})",
                     extra={"frontend": True})
        return
    if not seeded:
        _seed_library(store, user)


# ===== your own password (2.0.2) =====================================================================

#? (2.0.2 review) the SESSIONS (id hashes) a password change is being made from right now (src/routes/own_password.py),
#? and by how many requests at once - under _lock. While one is, a refusal of its OLD login (the re-check's, a player
#? call's) is the change itself, never a reason to end it. Only that session: every other one of the person's ends at
#? its first refusal as ever (the change ends them anyway), so its burst of calls stays one failed login - never
#? Navidrome's 5-in-20-s block on the name, which would refuse the change's own proof with the NEW password too.
_changing: dict[str, int] = {}
#? (2.0.2 review 2) and per PERSON: the changes of theirs running right now (`count`), the OTHER sessions of theirs a
#? refusal of the old login ended meanwhile (`refused` - the change's doing, so told PASSWORD_CHANGED and counted
#? among the devices it signed out), and whether one took (`took`, set by own_password_changed). A change that
#? didn't take puts LOGIN_GONE back for those: their logins died of something else. Under _lock.
_person_changes: dict[str, dict] = {}
#? (2.0.2 review) the re-seal clock: bumped by every own_password_changed, which notes the session's new login here
#? with the clock's value - so a session row read BEFORE the re-seal and installed in memory AFTER it (_session) can
#? never put the old login back. Under _lock; bounded, the oldest going first (it only matters for one read).
_resealed: "OrderedDict[str, tuple[int, str]]" = OrderedDict()
_reseal_clock = {"now": 0}
RESEALED_KEPT = 1000
#? (2.0.2 review 3) the sessions (old id hash -> new) a password change has moved under a new id (rotate_session): the
#? old id is ended, but a request already let in under it - this device's own, sent just before its new cookie came -
#? may still be refused by Navidrome with the old login, which says nothing about the session it became. Under _lock;
#? bounded, the oldest going first (it only matters for the requests in flight at the change).
_rotated: "OrderedDict[str, str]" = OrderedDict()


@contextmanager
def changing_password(key: str, user: str):
    """(2.0.2) Held from just before Navidrome is asked to change `user`'s password, until the session `key` (the id
    hash it was asked from) has been re-sealed with the new one (or the change has failed)."""
    with _lock:
        _changing[key] = _changing.get(key, 0) + 1
        change = _person_changes.setdefault(user, {"count": 0, "refused": set(), "took": False})
        change["count"] += 1
    try:
        yield
    finally:
        with _lock:
            left = _changing.get(key, 1) - 1
            if left > 0:
                _changing[key] = left
            else:
                _changing.pop(key, None)
            change = _person_changes.get(user)
            if change is not None:
                change["count"] -= 1
                if change["count"] <= 0:
                    _person_changes.pop(user, None)
                    if not change["took"]:
                        for other in change["refused"]:
                            if _ended.get(other) == PASSWORD_CHANGED:
                                _ended[other] = LOGIN_GONE


def _refusal(user: str, key: str, why: str) -> tuple[bool, str]:
    """
    (2.0.2 review 2) A refusal of the session `key`'s login is ending it with `why`: whether it is the first end of
    that session here (so it is logged once), and the reason to note - PASSWORD_CHANGED, not LOGIN_GONE, while a
    change of `user`'s is running from another of their sessions (the change's own session is `superseded`, never
    ended): Navidrome took the new password a moment ago and this device's old login died of it, so it is told what
    own_password_changed would have told it, and counted among the devices the change signed out.
    """
    with _lock:
        first = key not in _ended
        change = _person_changes.get(user)
        if change is None or why != LOGIN_GONE:
            return first, why
        if first:
            change["refused"].add(key)
        return first, PASSWORD_CHANGED


def superseded(store, user: str, key: str, sealed: str) -> bool:
    """
    (2.0.2) Whether Navidrome refusing the login `sealed` - the one the session `key` of `user` was read with - says
    nothing about that session: a password change is being made from that very session this moment, or the session
    has been re-sealed since with the new one (its login, in memory or else in the database, is another). Never for
    the person's OTHER sessions while one changes (review). (Review 3) Also for a session the change has since moved
    under a new id (rotate_session): a request let in under the old one just before is the device's own. SYNCHRONOUS (it may read the session's row); a database
    that can't be read is no evidence, so False.
    """
    with _lock:
        if _changing.get(key) or key in _rotated:
            return True
        held = _held.get(key)
    if held is not None:
        return held.credential != sealed
    if store is None or not getattr(store, "available", False):
        return False
    try:
        row = store.session(key)
    except Exception:
        return False
    return row is not None and row.get("user") == user and (row.get("credential") or "") != sealed


def reseal_mark() -> int:
    """(2.0.2 review) The re-seal clock now - taken before a session row is read (_session)."""
    with _lock:
        return _reseal_clock["now"]


def own_password_changed(store, key: str, user: str, sealed: str, now: float | None = None) -> int:
    """
    (2.0.2) `user` changed their own Navidrome password from the session `key`, and Navidrome took the new one:
    every OTHER session of theirs ends - in memory first (PASSWORD_CHANGED told to each one's next request, and
    any People unlock held for it gone with it; one a refusal of its old login ended while the change ran is counted
    too), then the database - and this one is re-sealed with `sealed`, the
    login made with the new password, in the database (store.own_password_changed, one transaction, which also
    keeps it as their login for starring) and then in memory, so the player, the stars and the re-check carry on
    with it. How many other devices were signed out. SYNCHRONOUS; raises on a database error (the other sessions
    are ended in memory by then - their logins are dead in Navidrome anyway).
    """
    now = time.time() if now is None else now
    with _lock:
        held_others = [other for other, held in _held.items() if held.user == user and other != key]
        #? (review 2) the devices a refusal of their old login signed out while this change ran - its doing too
        change = _person_changes.get(user)
        refused = set(change["refused"]) if change is not None else set()
        if change is not None:
            change["took"] = True
    for other in held_others:
        _note_ended(other, PASSWORD_CHANGED)
    stored_others, live = store.own_password_changed(user, key, sealed, now)
    for other in stored_others:
        if other not in held_others and other != key:
            _note_ended(other, PASSWORD_CHANGED)
    with _lock:
        _reseal_clock["now"] += 1
        _resealed[key] = (_reseal_clock["now"], sealed)
        _resealed.move_to_end(key)
        while len(_resealed) > RESEALED_KEPT:
            _resealed.popitem(last=False)
        held = _held.get(key)
        if held is not None:
            held.credential = sealed
    return live + len(refused - set(stored_others) - {key})


def rotate_session(store, key: str, user: str) -> str | None:
    """
    (2.0.2 review 3) The session `key` of `user`, just re-sealed with the new login by their own password change
    (own_password_changed), moved under a NEW session id: the cookie's value to set on the change's answer, or None
    when its row was no longer there to move (signed out meanwhile). Someone changes their password because a copy of
    their sign-in may be loose - and the copy was of this device's cookie too, which the re-seal alone left working,
    with the new login. In the database in one statement (store.rotate_session: the row itself moves, with everything
    it carries), and only then in memory: what is held of it follows to the new id, and the old one ends, its next
    request told PASSWORD_CHANGED (with it any People unlock held under it). SYNCHRONOUS; raises on a database error
    with nothing changed - the session then stands under its old id, with the new login.
    """
    raw = new_session_id()
    new_key = id_hash(raw)
    if not store.rotate_session(key, new_key, user):
        return None
    with _lock:
        held = _held.pop(key, None)
        if held is not None:
            _held[new_key] = held
        _rotated[key] = new_key
        _rotated.move_to_end(key)
        while len(_rotated) > RESEALED_KEPT:
            _rotated.popitem(last=False)
    _note_ended(key, PASSWORD_CHANGED)
    return raw


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


async def check_login(username: str, token: str, salt: str) -> tuple[str | None, bool]:
    """
    Ask Navidrome whether this token stands for `username` - getUser for the account's own name, signed
    as that account. (The user name Navidrome answered with - None if it named none - and, since
    2.0.0-player.61, whether the account is a Navidrome admin: `adminRole` exactly true, anything else -
    missing, a string, null - not); NavidromeError when it refused (`code` 40: wrong password or no such
    account) or couldn't be asked (`unreachable`).
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
    #? (2.0.0-player.61) fail closed: only a real boolean true is an admin
    admin = isinstance(user, dict) and user.get("adminRole") is True
    return (name if isinstance(name, str) else None), admin


def password_matches(sealed: str, password: str) -> bool:
    """
    (2.0.0-player.61) Whether `password` is the one this sealed login was made with - md5(password + its
    salt) against its token, in constant time; False when it won't open. People's unlock asks this before
    Navidrome is asked anything, so a typo costs nothing of the login budget deadwax shares.
    """
    opened = unseal_credential(sealed or "")
    if opened is None:
        return False
    _name, token, salt = opened
    return hmac.compare_digest(subsonic_token(password, salt).encode("ascii"), token.encode("ascii", "replace"))


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
        #? by the time of each name's LAST failure, oldest first (failed() moves a name to the end). A key is a
        #? lowercased name - or, for break-glass alone, break_glass_key's (name, address) tuple, which no typed
        #? name (a string) can ever equal
        self._failed: "OrderedDict[Hashable, deque[float]]" = OrderedDict()
        self._locks: dict[Hashable, asyncio.Lock] = {}

    def wait(self, name: Hashable) -> float:
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

    def failed(self, name: Hashable) -> None:
        now = self.clock()
        self._failed.setdefault(name, deque()).append(now)
        self._failed.move_to_end(name)
        if len(self._failed) > self.cap:
            self._make_room(now, keep=name)

    def _make_room(self, now: float, keep: Hashable) -> None:
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

    def succeeded(self, name: Hashable) -> None:
        self._failed.pop(name, None)

    def lock(self, name: Hashable) -> asyncio.Lock:
        held = self._locks.get(name)
        if held is None:
            if len(self._locks) >= self.cap:
                for other in [n for n, lock in self._locks.items() if not lock.locked()]:
                    del self._locks[other]
            held = self._locks[name] = asyncio.Lock()
        return held


throttle = Throttle()


def break_glass_key(address: str | None) -> tuple[str, str]:
    """
    (2.0.0-player.65) What the break-glass name's tries are counted under: the name and the client's address, so a
    stranger's wrong guesses hold off only the stranger's address, and the owner signing in from another still gets
    in. A tuple, so no name anyone types - always a string - shares its count: `deadwax@<an address>` typed as a name
    is an ordinary name, counted as itself. An IPv6 address counts as its /64 (one connection is usually handed a
    whole /64, so counting each address would give a guesser billions of them); an IPv4-mapped one as its IPv4.
    Behind a reverse proxy every sign-in may come from the proxy's address, and then this is the name's count alone,
    as every other name's is.
    """
    text = (address or "").strip()
    try:
        ip = ipaddress.ip_address(text)
    except ValueError:
        return (BREAK_GLASS_USER, text.lower())
    if isinstance(ip, ipaddress.IPv6Address):
        if ip.ipv4_mapped is not None:
            return (BREAK_GLASS_USER, str(ip.ipv4_mapped))
        return (BREAK_GLASS_USER, str(ipaddress.IPv6Network((ip, 64), strict=False)))
    return (BREAK_GLASS_USER, str(ip))


# ===== signing in ===================================================================================

def too_many(name: str, wait: float) -> HTTPException:
    seconds = max(1, int(wait + 0.999))
    return HTTPException(
        status_code=429,
        detail=(f"Too many tries for {name[:60]} - wait {seconds} seconds and try again. deadwax holds off "
                f"so Navidrome doesn't lock the account."),
        headers={"Retry-After": str(seconds)},
    )


async def sign_in(store, typed: str, password: str, address: str | None = None) -> tuple[str, str, int, bool]:
    """
    Sign `typed` in with `password`: (the user, the cookie's value, its max age, whether they are an
    admin) - or HTTPException saying plainly why not: 401 a wrong password, 429 too many tries, 503
    Navidrome not answering or deadwax unable to keep the session, 502 anything else Navidrome said.

    The break-glass name is checked against DEADWAX_ADMIN_PASSWORD alone and asks Navidrome nothing; its tries
    are counted per name and `address` (the client's, break_glass_key), every other name's per name.
    Any other name is put to Navidrome's getUser with a token made here, from a fresh salt: the name
    as typed (Navidrome finds accounts whatever their case), the identity lowercased. Each name's tries
    are in turn and counted (`throttle`); nothing is ever retried. (2.0.0-player.61) The answer's
    `adminRole` is the role: kept on the session, and every other session of theirs brought into line.
    A Navidrome admin's first sign-in takes over what `local` saved while logins were off (adopt_local)
    - for every admin who signs in, which after the first finds nothing left to take. And someone an
    admin gave a permission to has their Navidrome account's id read once (_account_id), so the grant is
    honoured only for the account it was given to.
    """
    name = typed.strip().lower()
    #? (2.0.0-player.65, the 2.0.0 release review) the break-glass name is public, so counted per name alone anyone's
    #? three wrong guesses a minute kept the way in shut in an emergency. Its tries are counted per name AND address
    #? now: a stranger's guesses hold off the stranger's address, and the owner from another still gets in. The wait
    #? comes BEFORE the password, as for every name - the slice's first version checked the password first, so the
    #? right one answered 200 while every wrong one answered 429: the throttle told a guesser which was right and
    #? slowed nothing. Held off, an address learns nothing about any password. (Behind a reverse proxy, where every
    #? sign-in may share the proxy's address, it is the name's count alone again.)
    key = break_glass_key(address) if name == BREAK_GLASS_USER else name
    async with throttle.lock(key):
        wait = throttle.wait(key)
        if wait:
            raise too_many(name, wait)

        if name == BREAK_GLASS_USER:
            if not break_glass_matches(password):
                throttle.failed(key)
                logger.warning("a break-glass sign-in was refused: wrong password, or DEADWAX_ADMIN_PASSWORD isn't set",
                               extra={"frontend": True})
                raise HTTPException(status_code=401, detail=WRONG_LOGIN)
            throttle.succeeded(key)
            logger.info("signed in: the break-glass admin", extra={"frontend": True})
            return BREAK_GLASS_USER, break_glass_cookie(), BREAK_GLASS_SECONDS, True

        if name in RESERVED_NAMES:
            raise HTTPException(status_code=400, detail=f"'{name}' is a name deadwax keeps for itself - nobody signs in as it.")
        if store is None or not getattr(store, "available", False):
            raise no_database()

        salt = secrets.token_hex(16)
        token = subsonic_token(password, salt)
        #? (2.0.0-player.61 review) before Navidrome is asked: a role People sets while this sign-in is on its way
        #? is newer than getUser's answer
        mark = role_mark()
        try:
            answered, admin = await check_login(typed.strip(), token, salt)
        except NavidromeError as e:
            if e.code == 40:
                throttle.failed(name)
                logger.info(f"a sign-in as {name[:60]} was refused: Navidrome didn't take the password", extra={"frontend": True})
                raise HTTPException(status_code=401, detail=WRONG_LOGIN) from e
            if e.code == 41:
                raise Explained(502, LDAP_ACCOUNT, "Navidrome can't check this account with a token (LDAP accounts "
                                "can't), and deadwax only signs in with tokens.") from e
            if e.unreachable:
                raise HTTPException(status_code=503, detail=(
                    "Navidrome isn't answering, so deadwax can't check your password right now - try again "
                    "in a moment.")) from e
            if e.status == 503:
                #? not set up, or NAVIDROME_URL unusable: the sentence for anyone, the setting for whoever runs it
                raise Explained(503, NAVIDROME_UNSET, str(e)) from e
            raise Explained(502, NAVIDROME_REFUSED, f"Navidrome couldn't check the password: {e}") from e
        throttle.succeeded(name)

        #? the identity is the Navidrome user name, lowercased - the one Navidrome answered with where it
        #? is the same name, else the one typed
        user = answered.strip().lower() if answered and answered.strip().lower() == name else name
        raw = new_session_id()
        now = time.time()
        #? sealed once: the session keeps it, and (2.0.0-player.51) so does the user - the same string, so
        #? the re-check refusing this session's login knows it is the user's latest one dying
        sealed = seal_credential(typed.strip(), token, salt)
        #? (2.0.0-player.61) the Navidrome account's id, only for someone an admin gave a permission to
        navidrome_id = await _account_id(store, user, typed.strip(), password)
        try:
            await asyncio.to_thread(store.create_session, id_hash(raw), user, sealed, now, now + SESSION_IDLE_SECONDS,
                                    admin, navidrome_id)
            #? every other session of theirs (another device) brought into line, in the database and memory -
            #? unless People changed their role since Navidrome answered: then the new session takes that one
            if not await asyncio.to_thread(set_role, store, user, admin, mark):
                admin = role(user)
                await asyncio.to_thread(set_role, store, user, admin)
        except Exception as e:
            logger.error(f"could not keep {user}'s session ({type(e).__name__}: {e})", extra={"frontend": True})
            raise no_database() from e
        #? in the thread pool, as every write here is: SQLite waiting on another writer's lock must not
        #? hold the event loop - and every request and stream with it (review)
        await asyncio.to_thread(_keep_for_library, store, user, sealed, now)

        #? (2.0.0-player.61) a Navidrome admin, as getUser has just said - the first one takes over what
        #? `local` saved, and the store goes into their library once ever
        if admin:
            taken = await store.adopt_local(user)
            if taken and any(taken):
                pins, preferences, requests = taken
                logger.info(f"{user} took over what deadwax saved before logins: {pins} pin(s), "
                            f"{preferences} preference(s) and {requests} download(s)", extra={"frontend": True})
            await asyncio.to_thread(_seed_library, store, user)
        logger.info(f"signed in: {user}" + (" (a Navidrome admin)" if admin else ""), extra={"frontend": True})
        library_ledger.kick()
        return user, raw, COOKIE_MAX_AGE, admin


async def _account_id(store, user: str, typed: str, password: str) -> str | None:
    """
    (2.0.0-player.61) The Navidrome account's id for `user`, read once at a sign-in - only when an admin
    has given them a permission (a grant row, src/permissions.py), whose rows hold the id of the account
    they were given to. One `/auth/login` as them, through deadwax's own login gate
    (src/api/navidrome_admin.py) - the password is in hand and getUser has just taken it - its JWT thrown
    away. Another id than the grants': the account was removed and made again, so the grants are dropped
    (logged). Anything that stops the ask - the gate full, Navidrome's 429, unreachable - leaves the id
    unread: their grants are then not honoured on this session (fail closed), never the sign-in refused.
    """
    try:
        if not await asyncio.to_thread(permissions.has_grants, store, user):
            return None
    except Exception as e:
        logger.error(f"could not tell whether an admin gave {user} any permission ({type(e).__name__}: {e})")
        return None
    try:
        found = await navidrome_admin.login(typed, password, expect=user)
    except navidrome_admin.NativeError as e:
        logger.warning(f"could not read {user}'s Navidrome account as they signed in ({e.kind}), so the permissions "
                       f"an admin gave them are off until they sign in again", extra={"frontend": True})
        return None
    navidrome_id = found.navidrome_id
    try:
        dropped = await asyncio.to_thread(permissions.drop_other_accounts, store, user, navidrome_id)
    except Exception as e:
        logger.error(f"could not check {user}'s permissions against their account ({type(e).__name__}: {e})")
        return None
    if dropped:
        logger.warning(f"{user}'s account isn't the one those permissions were given to - it was removed and made "
                       f"again - so deadwax dropped them ({dropped})", extra={"frontend": True})
    return navidrome_id


def _keep_for_library(store, user: str, sealed: str, now: float) -> None:
    """
    (2.0.0-player.51) The login just signed in with, kept for the USER - so albums filed while they're
    signed out are still starred as them, and their stars read back (src/stars.py) - alive again if it
    had died (a password changed since). Best effort: the sign-in stands either way, and a session's own
    credential stands in until the next sign-in keeps one (store.live_credentials).
    """
    try:
        store.keep_credential(user, sealed, now)
    except Exception as e:
        logger.error(f"could not keep {user}'s login for starring their albums ({type(e).__name__}: {e})",
                     extra={"frontend": True})


def _seed_library(store, user: str) -> None:
    """
    (2.0.0-player.51) Once, ever, on the first admin's sign-in after this step or their take-over: every
    album in the store goes into their library, to be starred for them (store.seed_library_now). SYNCHRONOUS
    and best effort - a failure is logged, and the admin's next sign-in tries again (it is once only when
    it has been done). Held over, when the store index hasn't been filled from a scan of the library yet:
    the library's first scan does it (store.index_reconcile).
    """
    try:
        seeded = store.seed_library_now(user, Config.LIBRARY_PATH or "")
    except Exception as e:
        logger.error(f"could not put the store into {user}'s library ({type(e).__name__}: {e}) - their next sign-in "
                     f"tries again", extra={"frontend": True})
        return
    if seeded == store.SEED_HELD_OVER:
        logger.info(f"deadwax hasn't scanned the library yet, so the albums already in the store go into {user}'s "
                    f"library after its first scan, which deadwax makes by itself as it starts (Library care's Rescan "
                    f"makes one too)", extra={"frontend": True})
        return
    if seeded is not None:
        logger.info(f"put {seeded} album(s) already in the store into {user}'s library - deadwax stars each for them "
                    f"in Navidrome", extra={"frontend": True})
        library_ledger.kick()


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
    failures for one account - and (2.0.0-player.61) its answer's `adminRole` is the person's role from
    then on (set_role, said in the log when it changed). Error 40 ends the session (the password changed, or the account is gone);
    a token that won't decrypt (another DEADWAX_SECRET_KEY) ends it too; anything else - Navidrome down,
    an address that won't do - ends nothing, and it is asked again next pass. Then expired sessions go.
    """
    now = time.time() if now is None else now
    counts = {"checked": 0, "ended": 0, "unanswered": 0, "expired": 0}
    due = await asyncio.to_thread(store.sessions_due, now - RECHECK_SECONDS, now)
    asked: set[str] = set()
    for row in due:
        if row["user"] in RESERVED_NAMES:
            #? (2.0.0-player.61 review) never asked as, never standing - as _session ends it
            await asyncio.to_thread(_end_reserved, store, row["id_hash"], row)
            counts["ended"] += 1
            continue
        if row["user"] in asked:
            continue
        asked.add(row["user"])
        credential = unseal_credential(row["credential"])
        if credential is None:
            await asyncio.to_thread(end_session, store, row["id_hash"], KEY_CHANGED)
            await asyncio.to_thread(_credential_dead, store, row, KEY_CHANGED)
            counts["ended"] += 1
            continue
        username, token, salt = credential
        #? (2.0.0-player.61 review) before Navidrome is asked, so a role People sets meanwhile isn't undone
        mark = role_mark()
        try:
            _answered, admin = await check_login(username, token, salt)
        except NavidromeError as e:
            if e.code == 40 and await asyncio.to_thread(superseded, store, row["user"], row["id_hash"], row["credential"]):
                #? (2.0.2) they changed their password from deadwax while this was asked: the session stands, re-sealed
                counts["unanswered"] += 1
                continue
            if e.code == 40:
                #? (2.0.2 review) refused while a change of theirs runs from another device: that change, said so
                _first, told = _refusal(row["user"], row["id_hash"], LOGIN_GONE)
                await asyncio.to_thread(end_session, store, row["id_hash"], told, True)
                await asyncio.to_thread(_credential_dead, store, row, LOGIN_GONE)
                counts["ended"] += 1
                said = ("their password was being changed from another device" if told == PASSWORD_CHANGED
                        else "Navidrome no longer accepts the login they signed in with")
                logger.info(f"signed {row['user']} out: {said}", extra={"frontend": True})
            else:
                counts["unanswered"] += 1
            continue
        await asyncio.to_thread(store.session_checked, row["id_hash"], time.time())
        counts["checked"] += 1
        #? (2.0.0-player.61) Navidrome's admin flag as it says now: changed in Navidrome since, it is deadwax's
        #? role from this person's next request
        if admin != bool(row.get("admin")) or admin != role(row["user"]):
            if not await asyncio.to_thread(set_role, store, row["user"], admin, mark):
                #? People changed it while Navidrome was being asked: theirs is the newer word
                continue
            if admin != bool(row.get("admin")):
                logger.info(f"{row['user']} is now a Navidrome admin, so deadwax's admin too" if admin else
                            f"{row['user']} is no longer a Navidrome admin, so no longer deadwax's admin either",
                            extra={"frontend": True})

    for key in await asyncio.to_thread(store.delete_expired_sessions, now):
        _note_ended(key, EXPIRED)
        counts["expired"] += 1
    return counts


def _credential_dead(store, session: dict, why: str) -> None:
    """(2.0.0-player.51) The login a session ended with no longer works - the user's kept one too, when it is
    that same login (a newer sign-in's stands): their albums wait until they sign in again. Best effort."""
    try:
        store.credential_dead(session["user"], why, session["credential"], time.time())
    except Exception as e:
        logger.warning(f"could not note that {session.get('user')}'s login no longer works ({type(e).__name__}: {e})")


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
