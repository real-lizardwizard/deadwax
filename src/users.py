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

ADMINS ARE NAVIDROME'S ADMINS (2.0.0-player.61): with logins on, someone is deadwax's admin exactly when
their own Navidrome account is a Navidrome admin, as deadwax last read it (src/auth.py role) - plus the
break-glass admin. Until then it was DEADWAX_ADMINS, deadwax's own list, which is ignored now.

PERMISSIONS (2.0.0-player.61, src/permissions.py): an admin has every one of PERMISSIONS; an ordinary
person Get albums (`request`) unless an admin took it away, plus what an admin ticked for them in People -
never `people`, which is a Navidrome admin's. `require(permission)` is the second dependency, on every route
an admin alone could use until then (the table in notes/logins.md, route by route - tests/test_logins.py's
ROUTES names each route's): a signed-in person without it is answered 403, in words naming what is missing
(NEEDS). `can` is the same check inside a route (the downloads routes' "everyone's" view). The app only
hides what someone can't use; every check is here, on the server.
"""

from functools import lru_cache

from fastapi import Depends, HTTPException, Request

from src import auth
from src import permissions as granted
from src.config import Config

#? The one user there is while logins are off. Rows saved per user before logins exist are saved
#? under this name, which is what the first admin's sign-in takes over (JobStore.adopt_local) - or, since
#? 2.0.0-player.49, the first admin seen with a session after a start (src/auth.py _take_over_leftovers).
LOCAL_USER = "local"

#? (2.0.0-player.61) Every permission, in the order /deadwax/me lists them: src/permissions.py's categories,
#? then `people` - a Navidrome admin's alone, never a tick.
PERMISSIONS = (*granted.CATEGORIES, "people")
ALL = frozenset(PERMISSIONS)

#? What each is called - in People's checkboxes, in NEEDS, in the docs
LABELS = {
    "request": "Get albums",
    "edit": "Edit albums",
    "library": "Look after the library",
    "downloads": "Everyone's downloads",
    "server": "Settings and the log",
    "people": "People",
}

#? What a signed-in person without the permission a route needs is told (403)
NEEDS = "That needs {label}, which an admin hasn't given you. You're signed in as {user}."
#? ...and for People, which no admin can tick for anyone: it comes with being a Navidrome admin
NEEDS_PEOPLE = "That's People, which only Navidrome's admins can use. You're signed in as {user}."


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
    """Whether `user` is deadwax's admin: everyone (`local`) while logins are off; with them on, a Navidrome
    admin as deadwax last read it (src/auth.py role - unknown is not), and the break-glass admin."""
    if not Config.logins_on():
        return user == LOCAL_USER
    return user == auth.BREAK_GLASS_USER or auth.role(user)


def auth_mode() -> str:
    """'off' while deadwax has no logins - so the page hides Sign out, and every admin row shows - or 'on'."""
    return "on" if Config.logins_on() else "off"


def _navidrome_id(request) -> str | None:
    """The account id the request's session read at its sign-in (src/auth.py PlayerLogin), or None."""
    login = getattr(getattr(request, "state", None), auth.LOGIN_STATE, None)
    return getattr(login, "navidrome_id", None) if isinstance(login, auth.PlayerLogin) else None


def _store(request):
    app = getattr(request, "app", None)
    return getattr(getattr(app, "state", None), "store", None)


def permissions(request, user: str) -> frozenset[str]:
    """
    What `user` may do (2.0.0-player.61): every permission for `local` with logins off, for the break-glass
    admin and for a Navidrome admin; for anyone else Get albums unless an admin took it away, plus what an
    admin ticked for them - a grant only for the Navidrome account it was given to (src/permissions.py).
    Never `people` but for an admin. SYNCHRONOUS (the table is read from SQLite the first time).
    """
    if is_admin(user):
        return ALL
    if not Config.logins_on():
        return frozenset()
    return granted.ordinary(_store(request), user, _navidrome_id(request))


def permissions_unverified(request, user: str) -> bool:
    """Whether an admin gave `user` something this session doesn't honour - their account couldn't be checked
    with Navidrome as they signed in, so the extra permissions are off until they sign in again."""
    if is_admin(user) or not Config.logins_on():
        return False
    return granted.unverified(_store(request), user, _navidrome_id(request))


def can(request, user: str, permission: str) -> bool:
    """Whether `user` has `permission` - the check inside a route (the downloads routes' everyone's view)."""
    return permission in permissions(request, user)


def needs_words(permission: str, user: str) -> str:
    """What a person without `permission` is told."""
    if permission == "people":
        return NEEDS_PEOPLE.format(user=user)
    return NEEDS.format(label=LABELS[permission], user=user)


@lru_cache(maxsize=None)
def require(permission: str):
    """
    The dependency for a route that needs `permission` (2.0.0-player.61, in place of require_admin): 403, in
    words, for a signed-in person without it; the user otherwise. One function per permission (cached), so a
    route's guard can be named - tests/test_logins.py's walk reads `.permission` off it. It runs after
    current_user, which has just read the session, so the role it reads is fresh for the person asking.
    """
    if permission not in PERMISSIONS:
        raise ValueError(f"no such permission: {permission}")

    def check(request: Request, user: str = Depends(current_user)) -> str:
        if permission not in permissions(request, user):
            raise HTTPException(status_code=403, detail=needs_words(permission, user))
        return user

    check.permission = permission
    check.__name__ = f"require_{permission}"
    return check
