"""
Who is asking. Step 1 of the unified app (2.0.0-player.9), ahead of logins (step 3 of the
multi-user plan).

`current_user` is a FastAPI DEPENDENCY, never middleware: a route that needs to know who is asking
says so in its signature (`user: str = Depends(current_user)`), so which routes are per user is
readable from the routes themselves, and nothing is added to every request. It is also not
`@app.middleware("http")`, which is Starlette's BaseHTTPMiddleware and hides a client hanging up
from every route (see test_no_middleware_hides_a_disconnect_from_the_routes).

With logins off - the only way deadwax runs today - there is one implicit user, `local`, and it is
the admin. Step 3 changes the body of `current_user` to read the session, and adds the "take over
what `local` saved" step for each per-user table; nothing that depends on it has to change.
"""

#? The one user there is while logins are off. Rows saved per user before logins exist are saved
#? under this name, which is what step 3's take-over looks for.
LOCAL_USER = "local"


def current_user() -> str:
    """The user a request comes from: always the implicit admin, `local`, while logins are off."""
    return LOCAL_USER


def is_admin(user: str) -> bool:
    """Whether `user` may use the admin-only parts. Everyone is, while logins are off."""
    return user == LOCAL_USER


def auth_mode() -> str:
    """'off' while deadwax has no logins - so the page hides Sign out, and every admin row shows."""
    return "off"
