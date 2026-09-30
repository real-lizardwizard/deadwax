"""
Who the page is talking to: `GET /deadwax/me`.

The app at /player/ decides what to show from this, not from assumptions - admin-only rows (server
settings, the review queue, the log, editing) show when `admin` is true, and Sign out only when
logins are on. With logins off it is always the implicit admin, `local` (src/users.py), and the
page says "logins are off". Step 3 fills in real values; the page already reads them.
"""

from fastapi import APIRouter, Depends

from src import __version__
from src.users import auth_mode, current_user, is_admin

router = APIRouter()


@router.get("")
async def me(user: str = Depends(current_user)):
    return {"user": user, "admin": is_admin(user), "auth": auth_mode(), "version": __version__}
