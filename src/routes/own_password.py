"""
Change your own password (2.0.2): `POST /deadwax/me/password`, You > Change password - a user's route (included with
current_user, src/api/app.py; tests/test_logins.py's ROUTES), for anyone signed in to deadwax through their own
Navidrome account.

James (2026-10-23): "I would like to be able to change my user password from deadwax". The password is Navidrome's -
deadwax keeps none of its own - so the change is made IN NAVIDROME, AS THE PERSON: Subsonic's changePassword answers
501 in Navidrome 0.64 (server/subsonic/api.go), so it goes through the native API People uses
(src/api/navidrome_admin.py), with three of its six calls and no new one:

  1. refused, with nothing sent, for logins off, the break-glass sign-in (no Navidrome account behind it) and
     NAVIDROME_USER's account (changing it would cut deadwax off from Navidrome until the setting is changed too);
     the new password held to People's rules (src/people.py password_problem: 8-128, no control characters, not the
     user name, typed twice the same) and not the current one; at most CHANGES_PER_MINUTE a minute per person;
  2. the CURRENT password checked against the login the session keeps first - in constant time, under the sign-in
     throttle's lock for the name and counted in it (auth.password_matches, as People's unlock) - so a typo never
     reaches Navidrome or spends the login budget deadwax shares with everyone;
  3. then, as the person: `POST /auth/login` with the current password (through deadwax's 4-per-20-s gate, nothing
     held), `GET /api/user/{their id}`, and `PUT` of that record WHOLE with `password` (the new) and
     `currentPassword` (the current) - Navidrome's PUT replaces the record, and its validatePasswordChange wants the
     current password from anyone changing their OWN (admins too); a non-admin may only when Navidrome's
     EnableUserEditing is on (its default) - off, Navidrome answers 403 and deadwax says so in words; then one
     Subsonic getUser with the NEW password proves it took;
  4. then this session is re-sealed with a login made from the new password, so playback, stars and playlists carry
     on, and every OTHER session of theirs ends (auth.own_password_changed) - each other device signs in again, told
     why - and any People unlock of theirs is dropped. Then (review 3) this session moves under a new id
     (auth.rotate_session), its new cookie set on the answer exactly as a sign-in sets one, so a copy of this
     device's old cookie is signed out too. The answer says how many devices were signed out.

A failure anywhere before Navidrome's 200 changes nothing in deadwax. A PUT sent and then not answered in a way deadwax
can read - timed out, the connection dropped, an answer not shaped as a user - may have landed, so the proof is asked
then too (review): the new password working, the change carries on as an answered one; otherwise it is said as an
unknown outcome and changes nothing (the re-check ends this session within minutes if it did take). While the change
is under way, a refusal of the old login of the session it is made FROM - the re-check's, a player call's - never ends
that session (auth.changing_password, auth.superseded); the person's other sessions end at their first refusal as
ever, so none of them makes a burst of failed logins that would trip Navidrome's block and refuse the proof - told
PASSWORD_CHANGED and counted among the devices signed out (review 2: auth._refusal).

Never logged or answered: a password, a JWT or a token. The request model forbids undeclared fields and has plain
str fields with no constraint - every check is here, in deadwax's words - and a 422 from this route never echoes its
input (src/api/app.py). Refusals are People's (`Refused`: {detail, kind, fix}).
"""

import asyncio
import secrets
import time
from collections import deque

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict

from src import auth, people as rules
from src.api import navidrome_admin
from src.config import Config
from src.logger import logger
from src.routes.auth import _set_cookie
from src.routes.people import Refused, _signs_in_with
from src.users import current_user, is_admin

router = APIRouter()

#? At most this many changes a minute per person - every attempt that passes the form, a wrong current password too
CHANGES_PER_MINUTE = 5
CHANGE_WINDOW = 60.0

#? The words each refusal says (ui/src/lib/ownPassword.ts draws them as they are)
LOGINS_OFF = "Logins are off, so deadwax has no password of yours to change - change it in Navidrome."
BREAK_GLASS = ("The break-glass sign-in has no Navidrome account, so it has no password to change here - its "
               "password is DEADWAX_ADMIN_PASSWORD, in the container's environment.")
SHARED_ACCOUNT = ("That's deadwax's own account (NAVIDROME_USER) - change its password in Navidrome, then put the new "
                  "one in Server settings → Connections, or deadwax loses its way into Navidrome.")
NO_CURRENT = "Type your current password."
SAME_PASSWORD = "That's the password you have now - type a new one."
NOT_YOUR_PASSWORD = ("That isn't your current password - the one you signed in to deadwax with. If you've changed it "
                     "since, sign out and in again.")
EDITING_OFF = ("Navidrome is set not to let people change their own details - an admin can change it in People, or "
               "turn on EnableUserEditing in Navidrome.")
WRONG_CURRENT = "Navidrome says that isn't your current password - nothing changed."
STALE = "Navidrome answered with another account than yours, so deadwax changed nothing."
GONE = "Your account isn't in Navidrome any more."
UNREACHABLE = "Navidrome isn't answering, so your password can't be changed right now - nothing changed."
LOCKED = "Navidrome stopped taking deadwax's sign-in part-way through, so nothing changed - try again."
UNKNOWN = ("Navidrome answered in a way deadwax doesn't know ({}), so nothing changed in deadwax - change your password "
           "in Navidrome itself meanwhile.")
UNKNOWN_SAVED = ("Navidrome answered your change in a way deadwax doesn't know ({}), and couldn't be asked whether "
                 "the new password works - so deadwax can't tell whether it changed. Try signing in to Navidrome with "
                 "the new one; if deadwax asks you to sign in again within a few minutes, use the new one.")
TIMED_OUT = ("Navidrome didn't answer in time, so deadwax can't tell whether your password changed. If it did, deadwax "
             "asks you to sign in again within a few minutes - with the new one; if not, try again.")
DIDNT_TAKE = ("Navidrome said it changed your password, but the new one doesn't work - deadwax changed nothing. Try "
              "signing in to Navidrome with each, or change it there.")
UNCHECKED = "deadwax couldn't check that the new password works - Navidrome didn't answer that one question."
NOT_RENEWED = ("deadwax couldn't give this device a new sign-in, so a copy of its old one would still work - sign out "
               "and in again here to be sure none does.")
NOT_KEPT = ("Navidrome changed your password, but deadwax couldn't keep the new one ({}) - sign out and sign in again "
            "with the new password.")
TOO_MANY = "That's a lot of tries in a minute - wait {seconds} seconds and try again."
NO_DATABASE = "deadwax can't read its database, so it can't change your password right now."
#? What a body deadwax couldn't read is answered (src/api/app.py answers FastAPI's 422 with it): never its input
FORM = "deadwax couldn't read that form - reload the page and try again."


class OwnPasswordBody(BaseModel):
    """What the form sends: nothing else is taken (an extra field is the 422, which echoes nothing)."""
    model_config = ConfigDict(extra="forbid")

    current: str = ""
    password: str = ""
    password_again: str = ""


#? each person's tries in the last CHANGE_WINDOW
_tries: dict[str, deque] = {}
#? the clock the limit is timed by - a test moves it
_clock = time.monotonic


def forget_tries() -> None:
    """The limit's record emptied (tests)."""
    _tries.clear()


def _count(user: str) -> None:
    """One more try by `user` - or 429, with nothing sent, past CHANGES_PER_MINUTE in CHANGE_WINDOW."""
    now = _clock()
    times = _tries.setdefault(user, deque())
    while times and now - times[0] >= CHANGE_WINDOW:
        times.popleft()
    if len(times) >= CHANGES_PER_MINUTE:
        seconds = max(1, int(CHANGE_WINDOW - (now - times[0]) + 0.999))
        raise Refused(429, TOO_MANY.format(seconds=seconds), "busy", retry_after=seconds)
    times.append(now)
    if len(_tries) > 1000:
        for name in [name for name, held in _tries.items() if not held]:
            del _tries[name]


def _store(request: Request):
    store = getattr(request.app.state, "store", None)
    if store is None or not getattr(store, "available", False):
        raise Refused(503, NO_DATABASE, "no_database")
    return store


def _login(request: Request, user: str) -> auth.PlayerLogin:
    """The signed-in person's own Navidrome login - or 409 in words: logins off, break-glass, NAVIDROME_USER."""
    if not Config.logins_on():
        raise Refused(409, LOGINS_OFF, "off")
    if user == auth.BREAK_GLASS_USER:
        raise Refused(409, BREAK_GLASS, "break_glass")
    login = getattr(request.state, auth.LOGIN_STATE, None)
    if not isinstance(login, auth.PlayerLogin):
        raise Refused(409, BREAK_GLASS, "break_glass")
    shared = (Config.NAVIDROME_USER or "").strip().lower()
    if shared and user == shared:
        raise Refused(409, SHARED_ACCOUNT, "shared_account")
    return login


def _detail(error: navidrome_admin.NativeError) -> str:
    """What an `unknown_shape`'s words name in brackets - the status, or what wasn't shaped as it should be."""
    return error.words.split("(", 1)[1].split(")", 1)[0] if "(" in error.words else "?"


def _refused(error: navidrome_admin.NativeError, user: str) -> Refused:
    """A native API failure before Navidrome took the change, in this page's words - nothing changed."""
    kind = error.kind
    if kind == "not_admin":
        #? Navidrome's 403: a non-admin's own record is theirs to change only with EnableUserEditing on
        if not is_admin(user):
            return Refused(403, EDITING_OFF, "editing_off")
        return Refused(403, navidrome_admin.WORDS["refused"].format("403"), "refused")
    if kind == "refused":
        if "currentPassword" in error.words:
            return Refused(409, WRONG_CURRENT, "wrong_current")
        return Refused(409, error.words, "refused")
    if kind == "not_found":
        return Refused(404, GONE, "not_found")
    if kind == "unreachable":
        return Refused(503, UNREACHABLE, "unreachable")
    if kind == "locked":
        return Refused(409, LOCKED, "locked_out")
    if kind == "unknown_shape":
        return Refused(502, UNKNOWN.format(_detail(error)), "unknown_shape")
    return Refused(error.status, error.words, kind, error.fix, error.retry_after)


@router.post("")
async def change_own_password(request: Request, body: OwnPasswordBody, user: str = Depends(current_user)):
    login = _login(request, user)
    if not body.current:
        raise Refused(400, NO_CURRENT, "form")
    problem = rules.password_problem(body.password, body.password_again, user)
    if problem:
        raise Refused(400, problem, "form")
    if body.password == body.current:
        raise Refused(400, SAME_PASSWORD, "form")
    store = _store(request)
    _count(user)

    async with auth.throttle.lock(user):
        wait = auth.throttle.wait(user)
        if wait:
            raise auth.too_many(user, wait)
        #? the session's login as the database has it NOW - never the one this request was read with, which a change
        #? made a moment ago from this same session would have replaced
        row = await asyncio.to_thread(store.session, login.key)
        if row is None or row.get("user") != user:
            #? (review) ended while this waited - a change from another device of theirs says why, as /me would
            raise HTTPException(status_code=401, detail=auth.session_ended(login.key) or auth.SIGNED_OUT)
        sealed = row.get("credential") or ""
        opened = auth.unseal_credential(sealed)
        if opened is None:
            raise HTTPException(status_code=401, detail=auth.KEY_CHANGED)
        #? checked here first, in constant time: a typo never reaches Navidrome
        if not auth.password_matches(sealed, body.current):
            auth.throttle.failed(user)
            logger.info(f"{user}'s password change was refused: not the password they signed in with",
                        extra={"frontend": True})
            raise Refused(409, NOT_YOUR_PASSWORD, "not_your_password")
        typed = opened[0]
        now_login = auth.PlayerLogin(login.key, user, sealed, store, login.navidrome_id)
        try:
            held = await navidrome_admin.login(typed, body.current, expect=user)
        except navidrome_admin.NativeError as e:
            if e.kind == "login_gone":
                #? the local check passed, so Navidrome no longer takes the login this session signed in with
                await asyncio.to_thread(auth.player_refused, now_login, auth.LOGIN_GONE)
                raise HTTPException(status_code=401, detail=auth.session_ended(login.key) or auth.LOGIN_GONE) from e
            raise _refused(e, user) from e
        auth.throttle.succeeded(user)

        with auth.changing_password(login.key, user):
            try:
                record = await navidrome_admin.get_user(held, held.navidrome_id)
            except navidrome_admin.NativeError as e:
                raise _refused(e, user) from e
            if record["userName"].strip().lower() != user:
                raise Refused(409, STALE, "stale")
            try:
                #? the record exactly as Navidrome answered it, with the new password and the current one: its PUT writes
                #? every column from the body, and wants the current password from anyone changing their own
                await navidrome_admin.save_user(held, held.navidrome_id,
                                                {**record, "password": body.password, "currentPassword": body.current})
            except navidrome_admin.NativeError as e:
                if e.kind not in ("timed_out", "unknown_shape"):
                    raise _refused(e, user) from e
                #? (review) sent, and then no answer deadwax could read - the change may have landed, and if it did the
                #? old login is dead: the proof settles it, and a change that took carries on as one answered
                took = await _signs_in_with(typed, body.password)
                if took is not True:
                    if e.kind == "timed_out":
                        logger.warning(f"{user}'s password change timed out in Navidrome - it may or may not have taken",
                                       extra={"frontend": True})
                        raise Refused(504, TIMED_OUT, "timed_out") from e
                    if took is None:
                        logger.warning(f"{user}'s password change was answered in a way deadwax doesn't know, and the new "
                                       f"one couldn't be tried", extra={"frontend": True})
                        raise Refused(502, UNKNOWN_SAVED.format(_detail(e)), "unknown_shape") from e
                    raise _refused(e, user) from e
                logger.info(f"{user}'s password change got no answer deadwax could read, but the new one works",
                            extra={"frontend": True})
            else:
                took = await _signs_in_with(typed, body.password)
            if took is False:
                logger.warning(f"Navidrome said it changed {user}'s password, but the new one doesn't work",
                               extra={"frontend": True})
                raise Refused(502, DIDNT_TAKE, "didnt_take")
            salt = secrets.token_hex(16)
            new_sealed = auth.seal_credential(typed, auth.subsonic_token(body.password, salt), salt)
            try:
                ended = await asyncio.to_thread(auth.own_password_changed, store, login.key, user, new_sealed)
            except Exception as e:
                logger.error(f"{user} changed their Navidrome password, but deadwax couldn't keep the new one "
                             f"({type(e).__name__}: {e})", extra={"frontend": True})
                raise Refused(500, NOT_KEPT.format(type(e).__name__), "not_kept") from e
            #? (review 3) and this device's session under a new id, its cookie set on the answer as a sign-in's is: a copy
            #? of the old cookie - the reason someone changes a password - is signed out with the other devices. A failure
            #? here leaves the session standing under its old id, with the new login, and says so
            try:
                raw = await asyncio.to_thread(auth.rotate_session, store, login.key, user)
                renewed = True
            except Exception as e:
                raw, renewed = None, False
                logger.error(f"{user} changed their Navidrome password, but deadwax couldn't give their device a new "
                             f"sign-in ({type(e).__name__}: {e})", extra={"frontend": True})
    navidrome_admin.forget_user(user)
    logger.info(f"{user} changed their Navidrome password (signed out of {ended} other device{'' if ended == 1 else 's'})",
                extra={"frontend": True})
    warnings = [words for words, said in ((UNCHECKED, took is None), (NOT_RENEWED, not renewed)) if said]
    response = JSONResponse({"changed": True, "signed_out": ended, "warning": " ".join(warnings) or None})
    if raw is not None:
        _set_cookie(response, request, raw, auth.COOKIE_MAX_AGE)
    return response
