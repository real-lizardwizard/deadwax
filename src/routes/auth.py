"""
Signing in and out (2.0.0-player.48): `POST /deadwax/auth/login` {username, password} and
`POST /deadwax/auth/logout`. The mechanics are src/auth.py's; this is the HTTP.

These two - beside the health check and the pages - are the routes that answer without a session: the
router is included with no dependency (src/api/app.py), and tests/test_logins.py's walk of every route
names them. Both are writes, so the same-origin guard stands in front of them like every other POST: a
page elsewhere can't sign the browser in to an account of its choosing.

The answer to a sign-in is what `GET /deadwax/me` answers - {user, admin, auth, version} - and a cookie;
NEVER the Navidrome token, which stays in deadwax, encrypted. The cookie: `deadwax_session`, HttpOnly
(no script on any page reads it), SameSite=Strict, Path=/, and Secure when the page came over HTTPS -
itself, or through a proxy's X-Forwarded-Proto. Plain http on the LAN and WireGuard is how James reaches
deadwax, so Secure can't be always: a Secure cookie is never sent over http.
"""

import asyncio

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from src import __version__, auth
from src.config import Config
from src.users import is_admin

router = APIRouter()


class SignIn(BaseModel):
    """A sign-in. Both bounded: nothing longer is anybody's user name or password."""
    username: str = Field(default="", max_length=200)
    password: str = Field(default="", max_length=1000)


def _set_cookie(response, request: Request, value: str, max_age: int) -> None:
    response.set_cookie(
        auth.COOKIE, value, max_age=max_age, path="/", httponly=True, samesite="strict",
        secure=auth.cookie_secure(request.url.scheme, request.headers.get("x-forwarded-proto")),
    )


@router.post("/login")
async def login(body: SignIn, request: Request):
    if not Config.logins_on():
        raise HTTPException(status_code=409, detail="Logins are off, so there's nothing to sign in to: deadwax lets everyone in.")
    problem = auth.unusable()
    if problem:
        raise HTTPException(status_code=503, detail=problem)
    if not body.username.strip() or not body.password:
        raise HTTPException(status_code=400, detail="Type your user name and your password.")

    store = getattr(request.app.state, "store", None)
    user, value, max_age = await auth.sign_in(store, body.username, body.password)
    response = JSONResponse({"user": user, "admin": is_admin(user), "auth": "on", "version": __version__})
    _set_cookie(response, request, value, max_age)
    return response


@router.post("/logout")
async def logout(request: Request):
    """
    End this browser's session - in the database and in memory, or for a break-glass cookie by
    remembering it - and clear the cookie. Answers 200 whatever there was: signing out of nothing is
    still signed out. A database that can't be written is said (503), and the cookie is cleared anyway.
    """
    raw = request.cookies.get(auth.COOKIE)
    store = getattr(request.app.state, "store", None)
    failed = None
    try:
        await asyncio.to_thread(auth.sign_out, store, raw)
    except Exception as e:
        failed = f"deadwax couldn't forget the session in its database ({type(e).__name__}) - it is ended in memory"
    response = JSONResponse({"signed_out": True, **({"problem": failed} if failed else {})},
                            status_code=503 if failed else 200)
    response.delete_cookie(auth.COOKIE, path="/", httponly=True, samesite="strict",
                           secure=auth.cookie_secure(request.url.scheme, request.headers.get("x-forwarded-proto")))
    return response
