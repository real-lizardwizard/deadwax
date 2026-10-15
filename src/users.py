"""
Who is asking, and what they may do. Step 1 of the unified app (2.0.0-player.9) made the seam; logins
(2.0.0-player.48, step 3 of the multi-user plan) fill it in - the mechanics are src/auth.py's.

`current_user` is a FastAPI DEPENDENCY, never middleware. Since 2.0.0-player.48 every router is
included with it (src/api/app.py: `dependencies=[Depends(current_user)]`), so with logins on nothing but
the health check, the pages and the sign-in itself answers anybody without a session - and a route that
needs to know WHO is asking still says so in its own signature (`user: str = Depends(current_user)`),
which FastAPI answers from the same call. It is not `@app.middleware("http")`, which is Starlette's
BaseHTTPMiddleware and hides a client hanging up from every route (see
test_no_middleware_hides_a_disconnect_from_the_routes).

With logins OFF - the default, and deadwax as it always was - there is one implicit user, `local`, and it
is the admin: current_user answers it without looking at the request at all, and nothing is read or
written for it. With logins ON it is the signed-in user (src/auth.py user_for): 401 with no session, 503
when logins can't work or the database can't be read.

`require_admin` is the second dependency: on the admin-only routes (editing the shared library, the
review queue, the log, the server settings - the plan's table, in notes/logins.md), a signed-in user who
isn't an admin is answered 403, in words. Admins are DEADWAX_ADMINS, and the break-glass admin; never
Navidrome's own admin flag.
"""

from fastapi import Depends, HTTPException, Request

from src import auth
from src.config import Config

#? The one user there is while logins are off. Rows saved per user before logins exist are saved
#? under this name, which is what the first admin's sign-in takes over (JobStore.adopt_local).
LOCAL_USER = "local"

#? What a signed-in user who isn't an admin is told by an admin-only route.
ADMIN_ONLY = (
    "That's for deadwax's admin: editing the shared library, the albums that need a look, the log and "
    "the server settings are theirs. You're signed in as {user}."
)


def current_user(request: Request = None) -> str:
    """
    The user a request comes from: the implicit admin `local` while logins are off, else the user its
    session names (or 401/503 - src/auth.py user_for). SYNCHRONOUS: FastAPI runs it in its thread pool,
    where reading a session from SQLite blocks nothing. `request` is FastAPI's to pass.
    """
    if not Config.logins_on():
        return LOCAL_USER
    if request is None:
        raise HTTPException(status_code=401, detail=auth.SIGN_IN)
    return auth.user_for(request)


def is_admin(user: str) -> bool:
    """Whether `user` may use the admin-only parts: everyone (`local`) while logins are off; with them on,
    the names DEADWAX_ADMINS lists, and the break-glass admin."""
    if not Config.logins_on():
        return user == LOCAL_USER
    return user == auth.BREAK_GLASS_USER or user in Config.admins()


def auth_mode() -> str:
    """'off' while deadwax has no logins - so the page hides Sign out, and every admin row shows - or 'on'."""
    return "on" if Config.logins_on() else "off"


def require_admin(user: str = Depends(current_user)) -> str:
    """The admin-only routes' dependency: 403, in words, for a signed-in user who isn't an admin."""
    if not is_admin(user):
        raise HTTPException(status_code=403, detail=ADMIN_ONLY.format(user=user))
    return user
