"""
People (2.0.0-player.61): managing Navidrome's accounts from deadwax - at /deadwax/people, included with
require("people") (src/api/app.py; tests/test_logins.py's ROUTES): a Navidrome admin's, as deadwax's admins
now are (src/auth.py).

James (2026-10-21) chose all four - create an account, reset someone's password, remove an account, make
someone an admin - and then: "deadwax will use whoever is signed in for the navidrome account making
changes". So EVERY CALL TO NAVIDROME HERE IS MADE AS THE SIGNED-IN PERSON, with their own JWT
(src/api/navidrome_admin.py), never NAVIDROME_USER and never anyone else's - which takes their password,
which deadwax doesn't keep: People opens LOCKED, and the person UNLOCKS it by typing their own Navidrome
password, checked against the login their session keeps first (in constant time, counted in the sign-in
throttle), so a typo never reaches Navidrome or spends the login budget deadwax shares with everyone.

  GET  ""                          the state - and, unlocked, Navidrome's accounts joined with what deadwax
                                   knows of each, and "Known only to deadwax"
  POST "/unlock"   {password}      unlock, for this session alone, 15 minutes since last used
  POST "/lock"     {}              lock again
  POST "/create"   {user, name, password, password_again}       a new, ORDINARY account
  POST "/{id}/password" {user, password, password_again}        reset someone's password
  POST "/{id}/admin"    {user, admin}                           make or unmake a Navidrome admin
  POST "/{id}/remove"   {user, confirm}                         remove the account - and what deadwax kept
  POST "/forget"        {user}                                  forget what deadwax kept for a name Navidrome
                                                                has no account for
  POST "/{id}/permissions" {user, request, edit, library, downloads, server}   an ordinary person's permissions

EVERY WRITE re-reads its target from Navidrome (GET first - a PUT to an id Navidrome doesn't have would MAKE
one) and checks it is still the person the page drew (`user`), then the guards (src/people.py refusals)
against that fresh record - and, for the last-admin rule, a fresh list. Writes go one at a time (an
asyncio.Lock per event loop) and at most WRITES_PER_MINUTE per admin. Nothing is taken over the wire but
the id, the expected name and what the person typed. Every request model forbids undeclared fields, with
plain str and bool and no constraint - every check is here, in deadwax's words - and a 422 from one of these
routes never echoes its input (src/api/app.py). Logged under the acting admin's name; never a password, a
JWT, a token or a body.
"""

import asyncio
import re
import secrets
import time
import weakref
from collections import deque

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict

from src import auth, people as rules, permissions
from src.api import navidrome_admin
from src.api.navidrome_endpoint import NavidromeError
from src.config import Config, describe_navidrome_url
from src.logger import logger
from src.users import LABELS, current_user

router = APIRouter()

#? A page-sent account id, checked before it goes near a URL (navidrome_admin checks it again)
PERSON_ID = re.compile(r"^[A-Za-z0-9-]{1,64}$")

#? At most this many People writes per admin in any WRITE_WINDOW seconds (unlock and lock aren't counted)
WRITES_PER_MINUTE = 10
WRITE_WINDOW = 60.0

#? The words each refusal says
NOT_YOUR_PASSWORD = ("That isn't the password you signed in to deadwax with - if you've changed it since, sign out "
                     "and in again.")
NO_PASSWORD = "Type your Navidrome password."
NOT_ADMIN_NOW = "Navidrome says you're no longer one of its admins, so it won't let you change accounts."
STALE = "That account has changed since this page was drawn - open People again."
GONE = "{user}'s account isn't in Navidrome any more."
LEFTOVERS = ("deadwax still keeps pins, settings or a library for an earlier '{user}' - Forget them under Known only "
             "to deadwax first, or choose another name.")
DIDNT_TAKE = ("Navidrome made {user}, but the password didn't take - set it in Navidrome's Users page (this Navidrome "
              "may be newer than People knows).")
RESET_DIDNT_TAKE = "Navidrome said it changed {user}'s password, but the new one doesn't work."
RESET_TIMED_OUT = ("Navidrome didn't answer in time, so deadwax can't tell whether {user}'s password changed - try "
                   "signing in as them, or reset it again.")
ADMIN_TIMED_OUT = ("Navidrome didn't answer in time, so deadwax can't tell whether {user}'s admin role changed - open "
                   "People again.")
ROLE_DIDNT_TAKE = ("Navidrome answered, but {user}'s admin role didn't change there - this Navidrome may be newer than "
                   "People knows; change it in Navidrome's Users page.")
REMOVE_TIMED_OUT = ("Navidrome didn't answer in time - open People again: if {user} is gone, Forget them under Known "
                    "only to deadwax.")
CREATE_TIMED_OUT = ("Navidrome didn't answer in time, so deadwax can't tell whether {user} was made - open People "
                    "again.")
FORGET_FAILED = ("Navidrome removed {user}, but deadwax couldn't clear what it kept for them ({why}). They're listed "
                 "under Known only to deadwax - Forget them there.")
NO_LIBRARY = "Navidrome gives them no library - they'll see nothing. Tick one for them in Navidrome's Users page."
LIBRARIES_UNREAD = ("deadwax couldn't read the new account back to see which libraries Navidrome gives them - check "
                    "in Navidrome's Users page that they have one.")
#? What a People request deadwax couldn't read is answered (src/api/app.py answers FastAPI's 422 with it too)
PEOPLE_FORM = "deadwax couldn't read that form - reload People and try again."
TYPE_THE_NAME = "Type their user name to remove them."
STILL_THERE = "{user} has a Navidrome account - remove them instead."
NOTHING_KEPT = "deadwax keeps nothing for {user}."
RESERVED = "deadwax keeps '{user}' for itself - there's nothing of it to forget."
TOO_MANY = "That's a lot of changes in a minute - wait {seconds} seconds and try again."
NO_DATABASE = "deadwax can't read its database, so People can't say what it keeps for each person."


class Refused(Exception):
    """A People route's refusal, in words - answered (src/api/app.py) as {detail, kind, fix} with its status, so the
    page can tell `locked` (bring the unlock form back) from the rest."""

    def __init__(self, status: int, words: str, kind: str | None = None, fix: str | None = None,
                 retry_after: int | None = None):
        super().__init__(words)
        self.status, self.words, self.kind, self.fix, self.retry_after = status, words, kind, fix, retry_after


def answer(error: Refused) -> dict:
    return {"detail": error.words, "kind": error.kind, "fix": error.fix}


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class UnlockBody(_Strict):
    password: str = ""


class LockBody(_Strict):
    pass


class CreateBody(_Strict):
    user: str = ""
    name: str = ""
    password: str = ""
    password_again: str = ""


class ResetBody(_Strict):
    user: str = ""
    password: str = ""
    password_again: str = ""


class AdminBody(_Strict):
    user: str = ""
    admin: bool = False


class RemoveBody(_Strict):
    user: str = ""
    confirm: str = ""


class ForgetBody(_Strict):
    user: str = ""


class PermissionsBody(_Strict):
    #? (review) all five REQUIRED: a body leaving one out is the People 422 (PEOPLE_FORM), never saved as a restriction
    #? of what it left out. None, not a missing field, so logins off and break-glass are still said before the body
    #? is read (save_permissions checks after _login)
    user: str = ""
    request: bool | None = None
    edit: bool | None = None
    library: bool | None = None
    downloads: bool | None = None
    server: bool | None = None


# ----------------------------------------------------------------- the frame every route stands in

_locks: "weakref.WeakKeyDictionary[asyncio.AbstractEventLoop, asyncio.Lock]" = weakref.WeakKeyDictionary()
#? each admin's writes in the last WRITE_WINDOW
_writes: dict[str, deque] = {}
#? the clock the rate limit is timed by - a test moves it
_clock = time.monotonic


def _write_lock() -> asyncio.Lock:
    """One People write at a time: the guards and the stale-record checks hold only if writes can't interleave.
    One lock per event loop (a lock is bound to the loop it first waits in)."""
    loop = asyncio.get_running_loop()
    held = _locks.get(loop)
    if held is None:
        held = _locks[loop] = asyncio.Lock()
    return held


def forget_writes() -> None:
    """The rate limit's record emptied (tests)."""
    _writes.clear()


def _count(user: str) -> None:
    """One more write by `user` - or 429, with nothing sent, past WRITES_PER_MINUTE in WRITE_WINDOW."""
    now = _clock()
    times = _writes.setdefault(user, deque())
    while times and now - times[0] >= WRITE_WINDOW:
        times.popleft()
    if len(times) >= WRITES_PER_MINUTE:
        seconds = max(1, int(WRITE_WINDOW - (now - times[0]) + 0.999))
        raise Refused(429, TOO_MANY.format(seconds=seconds), "busy", retry_after=seconds)
    times.append(now)
    if len(_writes) > 1000:
        for name in [name for name, held in _writes.items() if not held]:
            del _writes[name]


def _store(request: Request):
    store = getattr(request.app.state, "store", None)
    if store is None or not getattr(store, "available", False):
        raise Refused(503, NO_DATABASE, "no_database")
    return store


def _login(request: Request, user: str) -> auth.PlayerLogin:
    """The signed-in person's own Navidrome login - or 409: logins off, or break-glass, has none to ask as."""
    if not Config.logins_on():
        raise Refused(409, rules.NEEDS_LOGINS, "off")
    if user == auth.BREAK_GLASS_USER:
        raise Refused(409, rules.BREAK_GLASS, "break_glass")
    login = getattr(request.state, auth.LOGIN_STATE, None)
    if not isinstance(login, auth.PlayerLogin) or auth.unseal_credential(login.sealed) is None:
        raise Refused(409, rules.BREAK_GLASS, "break_glass")
    return login


def _unlocked(login: auth.PlayerLogin) -> navidrome_admin.Unlock:
    held = navidrome_admin.unlocked(login.key)
    if held is None:
        raise Refused(409, navidrome_admin.WORDS["locked"], "locked")
    return held


async def _refusal(error: navidrome_admin.NativeError, request: Request, user: str, login=None) -> Refused:
    """A native API failure in the page's words. Navidrome's 403 means they are no longer one of its admins: the
    role goes in deadwax at once, and so does the unlock."""
    if error.kind == "not_admin":
        if login is not None:
            navidrome_admin.forget(login.key)
        try:
            await asyncio.to_thread(auth.set_role, _store(request), user, False)
        except Exception as e:
            logger.error(f"could not note that {user} is no longer a Navidrome admin ({type(e).__name__}: {e})")
        return Refused(403, NOT_ADMIN_NOW, "not_admin", error.fix)
    return Refused(error.status, error.words, error.kind, error.fix, error.retry_after)


def _context(user: str, accounts: list[dict] | None = None) -> dict:
    return {
        "logins": Config.logins_on(),
        "break_glass": user == auth.BREAK_GLASS_USER,
        "shared": (Config.NAVIDROME_USER or "").strip().lower(),
        "admins": {account["userName"].lower() for account in accounts or [] if account.get("isAdmin")},
        "reserved": auth.RESERVED_NAMES,
    }


def _checked_id(person_id: str) -> str:
    if not PERSON_ID.match(person_id or ""):
        raise Refused(404, "That isn't an account id Navidrome gives.", "not_found")
    return person_id


async def _target(unlock, person_id: str, expected: str) -> dict:
    """The account as Navidrome has it now - and still the person the page drew."""
    try:
        record = await navidrome_admin.get_user(unlock, _checked_id(person_id))
    except navidrome_admin.NativeError as e:
        if e.kind == "not_found":
            raise Refused(404, GONE.format(user=rules.shown(expected) or "That"), "not_found") from e
        raise
    if record["userName"].strip().lower() != (expected or "").strip().lower():
        raise Refused(409, STALE, "stale")
    return record


async def _accounts(unlock) -> list[dict]:
    return await navidrome_admin.list_users(unlock)


def _said(names: list[str]) -> str:
    words = [LABELS[name] for name in names]
    return words[0] if len(words) == 1 else f"{', '.join(words[:-1])} and {words[-1]}"


async def _signs_in_with(name: str, password: str) -> bool | None:
    """The check that a password took: one Subsonic getUser as `name` with it, from a fresh salt. True it works, False
    Navidrome refused it, None it couldn't be asked."""
    salt = secrets.token_hex(16)
    try:
        await auth.check_login(name, auth.subsonic_token(password, salt), salt)
    except NavidromeError as e:
        return False if e.code == 40 else None
    return True


# ----------------------------------------------------------------- the state

@router.get("")
async def people(request: Request, user: str = Depends(current_user)):
    """People's state, and - unlocked - Navidrome's accounts, read fresh each time, as the unlocked person."""
    state = {"on": Config.logins_on(), "available": False, "locked": True, "problem": None, "fix": None, "you": user,
             "account": rules.shown((Config.NAVIDROME_USER or "").strip().lower()) or None, "people": [], "known_only": []}
    try:
        login = _login(request, user)
    except Refused as e:
        state["problem"] = e.words
        return state
    if not Config.NAVIDROME_URL:
        state.update(problem=navidrome_admin.WORDS["not_set_up"], fix=navidrome_admin.FIXES["not_set_up"])
        return state
    problem = describe_navidrome_url(Config.NAVIDROME_URL)
    if problem:
        state["problem"] = navidrome_admin.WORDS["bad_address"].format(problem)
        return state
    state["available"] = True
    unlock = navidrome_admin.unlocked(login.key)
    if unlock is None:
        return state
    try:
        accounts = await _accounts(unlock)
    except navidrome_admin.NativeError as e:
        refused = await _refusal(e, request, user, login)
        state.update(locked=e.kind == "locked", problem=refused.words, fix=refused.fix,
                     available=e.kind != "not_admin")
        return state
    state["locked"] = False
    store = _store(request)
    await asyncio.to_thread(_heal, store, accounts)
    facts = await asyncio.to_thread(store.people_facts)
    known = await asyncio.to_thread(store.known_users)
    ctx = _context(user, accounts)
    rows = []
    for account in accounts:
        name = account["userName"].strip().lower()
        ticked = None if account.get("isAdmin") else await asyncio.to_thread(permissions.ticked, store, name)
        rows.append(rules.person(account, facts.get(name), ctx, user, ticked))
    state["people"] = sorted(rows, key=lambda row: (not row["you"], row["user"]))
    state["known_only"] = rules.known_only(known, {account["userName"].strip().lower() for account in accounts})
    return state


def _heal(store, accounts: list[dict]) -> None:
    """An admin's fresh list names each account's id: sessions whose sign-in couldn't read theirs get it - only those
    begun since the account was made (its createdAt; none when Navidrome gives no usable one), never an earlier
    account's of the same name (review) - and grants given to another account under the same name (removed and made
    again since) are dropped."""
    for account in accounts:
        name = account["userName"].strip().lower()
        if name in auth.RESERVED_NAMES:
            continue
        made = rules.made_at(account)
        if made is not None:
            healed = store.heal_session_ids(name, account["id"], made)
            if healed:
                auth.note_account_id(name, account["id"], healed)
        dropped = permissions.drop_other_accounts(store, name, account["id"])
        if dropped:
            logger.warning(f"{name}'s account isn't the one those permissions were given to - it was removed and made "
                           f"again - so deadwax dropped them ({dropped})", extra={"frontend": True})


# ----------------------------------------------------------------- unlock and lock

@router.post("/unlock")
async def unlock(request: Request, body: UnlockBody, user: str = Depends(current_user)):
    login = _login(request, user)
    if not body.password:
        raise Refused(400, NO_PASSWORD, "no_password")
    async with auth.throttle.lock(user):
        wait = auth.throttle.wait(user)
        if wait:
            raise auth.too_many(user, wait)
        #? checked here first, in constant time: a typo never reaches Navidrome
        if not auth.password_matches(login.sealed, body.password):
            auth.throttle.failed(user)
            logger.info(f"{user}'s People unlock was refused: not the password they signed in with",
                        extra={"frontend": True})
            raise Refused(409, NOT_YOUR_PASSWORD, "not_your_password")
        typed = auth.unseal_credential(login.sealed)[0]
        try:
            held = await navidrome_admin.login(typed, body.password, expect=user, key=login.key)
        except navidrome_admin.NativeError as e:
            if e.kind == "login_gone":
                #? the local check passed, so Navidrome no longer takes the login this session signed in with
                await asyncio.to_thread(auth.player_refused, login, auth.LOGIN_GONE)
                raise HTTPException(status_code=401, detail=auth.session_ended(login.key) or auth.LOGIN_GONE) from e
            raise await _refusal(e, request, user, login) from e
        auth.throttle.succeeded(user)
    if not held.admin:
        await asyncio.to_thread(auth.set_role, _store(request), user, False)
        raise Refused(403, navidrome_admin.WORDS["not_admin"], "not_admin", navidrome_admin.FIXES["not_admin"])
    logger.info(f"{user} unlocked People", extra={"frontend": True})
    return {"unlocked": True}


@router.post("/lock")
async def lock(request: Request, body: LockBody, user: str = Depends(current_user)):
    login = _login(request, user)
    navidrome_admin.forget(login.key)
    return {"locked": True}


# ----------------------------------------------------------------- the writes

async def _write(request: Request, user: str, work):
    """A People write's frame: a Navidrome sign-in, unlocked, counted, one at a time - `work(unlock, store)` inside,
    its native failures said in words."""
    login = _login(request, user)
    held = _unlocked(login)
    store = _store(request)
    _count(user)
    async with _write_lock():
        try:
            return await work(held, store)
        except navidrome_admin.NativeError as e:
            raise await _refusal(e, request, user, login) from e


@router.post("/create")
async def create(request: Request, body: CreateBody, user: str = Depends(current_user)):
    #? logins off or break-glass: said before anything sent is read
    _login(request, user)
    name = rules.clean_name(body.user)
    display = rules.clean_display(body.name)
    problem = (rules.name_problem(name, auth.RESERVED_NAMES) or rules.display_problem(display)
               or rules.password_problem(body.password, body.password_again, name))
    if problem:
        raise Refused(400, problem, "form")

    async def work(held, store):
        if await asyncio.to_thread(store.keeps_anything, name):
            raise Refused(409, LEFTOVERS.format(user=name), "leftovers")
        try:
            made = await navidrome_admin.create_user(held, name, display or name, body.password)
        except navidrome_admin.NativeError as e:
            if e.kind == "timed_out":
                raise Refused(504, CREATE_TIMED_OUT.format(user=name), "timed_out") from e
            raise
        logger.info(f"{user} made a Navidrome account: {name}", extra={"frontend": True})
        warning = None
        #? (review) the account is made: from here on nothing may answer as if it weren't - the libraries' read is
        #? best effort, and a failure of it is a warning beside `made`, never the refusal that would send the
        #? admin to try again into "There's already a Navidrome account called ..."
        try:
            record = await navidrome_admin.get_user(held, made)
        except navidrome_admin.NativeError as e:
            logger.warning(f"{user} made {name}, but deadwax couldn't read the new account back ({e.kind})")
            warning = LIBRARIES_UNREAD
        else:
            if isinstance(record.get("libraries"), list) and not record["libraries"]:
                warning = NO_LIBRARY
        took = await _signs_in_with(name, body.password)
        if took is False:
            raise Refused(502, DIDNT_TAKE.format(user=name), "didnt_take")
        if took is None:
            warning = " ".join(filter(None, [warning, "deadwax couldn't check the new password works - Navidrome didn't answer."]))
        return {"made": {"id": made, "user": name, "name": rules.shown(display or name)}, "warning": warning}

    return await _write(request, user, work)


@router.post("/{person_id}/password")
async def reset(request: Request, person_id: str, body: ResetBody, user: str = Depends(current_user)):
    #? logins off or break-glass: said before anything sent is read
    _login(request, user)
    _checked_id(person_id)

    async def work(held, store):
        target = await _target(held, person_id, body.user)
        name = target["userName"].strip().lower()
        refused = rules.refusals(user, {"user": name, "admin": target["isAdmin"]}, _context(user))["reset"]
        if refused:
            raise Refused(409, refused, "refused")
        problem = rules.password_problem(body.password, body.password_again, name)
        if problem:
            raise Refused(400, problem, "form")
        try:
            #? the record exactly as Navidrome answered it, with the password: its PUT writes every column
            await navidrome_admin.save_user(held, person_id, {**target, "password": body.password})
        except navidrome_admin.NativeError as e:
            if e.kind == "timed_out":
                raise Refused(504, RESET_TIMED_OUT.format(user=name), "timed_out") from e
            raise
        took = await _signs_in_with(target["userName"], body.password)
        if took is False:
            raise Refused(502, RESET_DIDNT_TAKE.format(user=name), "didnt_take")
        #? their old login is dead in Navidrome now: every session of theirs ended at once and their kept login
        #? marked dead, so neither the re-check, the player nor the star worker tries it from deadwax's one address
        #? (Navidrome blocks a name for 20 s after 5 failures from one address, right passwords included)
        ended = await asyncio.to_thread(auth.end_user_sessions, store, name, auth.PASSWORD_RESET)
        await asyncio.to_thread(store.credential_dead_for, name, auth.PASSWORD_RESET, time.time())
        logger.info(f"{user} reset {name}'s password (signed out of {ended} device{'' if ended == 1 else 's'})",
                    extra={"frontend": True})
        return {"reset": name, "signed_out": ended}

    return await _write(request, user, work)


@router.post("/{person_id}/admin")
async def admin(request: Request, person_id: str, body: AdminBody, user: str = Depends(current_user)):
    #? logins off or break-glass: said before anything sent is read
    _login(request, user)
    _checked_id(person_id)

    async def work(held, store):
        target = await _target(held, person_id, body.user)
        name = target["userName"].strip().lower()
        accounts = await _accounts(held)
        refused = rules.refusals(user, {"user": name, "admin": target["isAdmin"]}, _context(user, accounts))["admin"]
        if refused:
            raise Refused(409, refused, "refused")
        if target["isAdmin"] == body.admin:
            return {"user": name, "admin": body.admin, "changed": False}
        try:
            saved = await navidrome_admin.save_user(held, person_id, {**target, "isAdmin": body.admin})
        except navidrome_admin.NativeError as e:
            if e.kind == "timed_out":
                raise Refused(504, ADMIN_TIMED_OUT.format(user=name), "timed_out") from e
            raise
        #? the record the PUT answered must show it - else Navidrome ignored the field, and deadwax's role stays
        if saved["isAdmin"] is not body.admin:
            raise Refused(502, ROLE_DIDNT_TAKE.format(user=name), "unknown_shape")
        await asyncio.to_thread(auth.set_role, store, name, body.admin)
        logger.info(f"{user} made {name} an admin" if body.admin else f"{user} made {name} no longer an admin",
                    extra={"frontend": True})
        return {"user": name, "admin": body.admin, "changed": True}

    return await _write(request, user, work)


def _forgotten(counts: dict) -> str:
    said = [f"{counts.get('library_membership', 0)} library entr{'y' if counts.get('library_membership') == 1 else 'ies'}",
            f"{counts.get('pins', 0)} pin{'' if counts.get('pins') == 1 else 's'}",
            f"{counts.get('sessions', 0)} sign-in{'' if counts.get('sessions') == 1 else 's'}",
            f"{counts.get('job_requests', 0)} request{'' if counts.get('job_requests') == 1 else 's'}",
            f"{counts.get('permissions', 0)} permission{'' if counts.get('permissions') == 1 else 's'}"]
    return ", ".join(said)


async def _forget(store, name: str) -> dict:
    """What deadwax keeps for `name`, gone: every session of theirs ended in memory first (ACCOUNT_REMOVED told),
    then the database's rows in one transaction (store.forget_person), then the permissions held in memory."""
    keys = await asyncio.to_thread(store.session_keys, name)
    auth.end_held_sessions(name, keys, auth.ACCOUNT_REMOVED)
    counts = await asyncio.to_thread(store.forget_person, name)
    permissions.forget(name)
    return counts


@router.post("/{person_id}/remove")
async def remove(request: Request, person_id: str, body: RemoveBody, user: str = Depends(current_user)):
    #? logins off or break-glass: said before anything sent is read
    _login(request, user)
    _checked_id(person_id)
    if not body.user or body.confirm != body.user:
        raise Refused(400, TYPE_THE_NAME, "form")

    async def work(held, store):
        target = await _target(held, person_id, body.user)
        name = target["userName"].strip().lower()
        accounts = await _accounts(held)
        refused = rules.refusals(user, {"user": name, "admin": target["isAdmin"]}, _context(user, accounts))["remove"]
        if refused:
            raise Refused(409, refused, "refused")
        try:
            await navidrome_admin.delete_user(held, person_id)
        except navidrome_admin.NativeError as e:
            if e.kind == "timed_out":
                raise Refused(504, REMOVE_TIMED_OUT.format(user=name), "timed_out") from e
            raise
        if name in auth.RESERVED_NAMES:
            #? deadwax keeps nothing for a reserved name to forget: `local` is logins-off's user
            logger.info(f"{user} removed {name} from Navidrome", extra={"frontend": True})
            return {"removed": name, "forgot": None}
        try:
            counts = await _forget(store, name)
        except Exception as e:
            logger.error(f"{user} removed {name} from Navidrome, but deadwax couldn't clear what it kept for them "
                         f"({type(e).__name__}: {e})", extra={"frontend": True})
            raise Refused(500, FORGET_FAILED.format(user=name, why=type(e).__name__), "forget_failed") from e
        logger.info(f"{user} removed {name} from Navidrome and deadwax ({_forgotten(counts)})", extra={"frontend": True})
        return {"removed": name, "forgot": counts}

    return await _write(request, user, work)


@router.post("/forget")
async def forget(request: Request, body: ForgetBody, user: str = Depends(current_user)):
    #? logins off or break-glass: said before anything sent is read
    _login(request, user)
    name = rules.clean_name(body.user)
    if not name:
        raise Refused(400, "Name who to forget.", "form")
    if name in auth.RESERVED_NAMES:
        raise Refused(409, RESERVED.format(user=name), "reserved")

    async def work(held, store):
        #? only for a name a FRESH list lacks: a failure to read it is proof of nothing
        accounts = await _accounts(held)
        if name in {account["userName"].strip().lower() for account in accounts}:
            raise Refused(409, STILL_THERE.format(user=name), "still_there")
        if name not in await asyncio.to_thread(store.known_users):
            raise Refused(404, NOTHING_KEPT.format(user=name), "nothing_kept")
        counts = await _forget(store, name)
        logger.info(f"{user} forgot what deadwax kept for {name} ({_forgotten(counts)})", extra={"frontend": True})
        return {"forgot": name, "counts": counts}

    return await _write(request, user, work)


@router.post("/{person_id}/permissions")
async def save_permissions(request: Request, person_id: str, body: PermissionsBody, user: str = Depends(current_user)):
    #? logins off or break-glass: said before anything sent is read
    _login(request, user)
    _checked_id(person_id)
    if any(getattr(body, category) is None for category in permissions.CATEGORIES):
        raise Refused(422, PEOPLE_FORM, "form")
    wanted = {category: bool(getattr(body, category)) for category in permissions.CATEGORIES}

    async def work(held, store):
        target = await _target(held, person_id, body.user)
        name = target["userName"].strip().lower()
        refused = rules.refusals(user, {"user": name, "admin": target["isAdmin"]}, _context(user))["permissions"]
        if refused:
            raise Refused(409, refused, "refused")
        gave, took = await asyncio.to_thread(permissions.set_for, store, name, target["id"], wanted, user)
        said = "; ".join(filter(None, [f"gave {name} {_said(gave)}" if gave else "",
                                       (f"took away {_said(took)}" if gave else f"took away {name}'s {_said(took)}")
                                       if took else ""]))
        logger.info(f"{user} {said}" if said else f"{user} saved {name}'s permissions (nothing changed)",
                    extra={"frontend": True})
        return {"user": name, "permissions": await asyncio.to_thread(permissions.ticked, store, name)}

    return await _write(request, user, work)
