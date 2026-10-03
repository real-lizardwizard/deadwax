"""
Who the page is talking to: `GET /deadwax/me`, and what they chose for themselves:
`GET`/`PUT /deadwax/me/preferences` (2.0.0-player.15).

The app at /player/ decides what to show from this, not from assumptions - admin-only rows (server
settings, the review queue, the log, editing) show when `admin` is true, and Sign out only when
logins are on. With logins off it is always the implicit admin, `local` (src/users.py), and the
page says "logins are off". Step 3 fills in real values; the page already reads them.

The preferences are You > Getting albums in the app: "When I tap Get" (show me the sources, or
pick the best source for me) and the quality floor. Kept PER USER on the server (store.user_prefs),
through `current_user` like everything per user, so a person's choice follows them from device to
device - unlike a device's own settings (Gapless, Maximum quality), which stay in its browser.
Only the keys in PREFERENCES, and only the values listed for each, are taken: anything else is a
422 and nothing is written, so a typo can't leave a setting the app can't read. A PUT is a write,
so the same-origin guard (src/api/same_origin.py) stands in front of it like every other. Every save
also writes SEEDED, so the answer's `seeded` says whether anything was ever saved for the user -
what lets the app carry the main page's quality floor over once, without storing the defaults.
"""

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict

from src import __version__
from src.users import auth_mode, current_user, is_admin

router = APIRouter()

#? The preferences a user may set, each with the values it takes - the first is the default.
#? `get_mode`: what Get does - show the sources (James: "I don't think I can reliably trust
#? automatically grabbing from the correct source"), or pick the best one. `quality_floor`: what a
#? source must at least be - any, 320 kbps, lossless, 24-bit. Keep in step with Preferences below
#? and with ui/src/lib/getSettings.ts, which tests/test_me_prefs.py reads to hold the three to one.
PREFERENCES: dict[str, tuple[str, ...]] = {
    "get_mode": ("sources", "pick"),
    "quality_floor": ("any", "320", "lossless", "24bit"),
}

DEFAULTS = {key: values[0] for key, values in PREFERENCES.items()}

#? A row every save writes beside what it sets (2.0.0-player.15, review): it says the app has written
#? for this user - which is what tells the app it has already carried the main page's quality floor
#? over, even when that came to nothing but the defaults and so stored no preference at all. The
#? defaults are never stored as if chosen: an absent preference is its default, so a default changed
#? later reaches everyone who never chose. An underscore, so no preference (a pydantic field, which
#? can't start with one) can ever be called this.
SEEDED = "_seeded"


class Preferences(BaseModel):
    """A PUT: any of the preferences, each one of its values. Nothing else - extra keys are refused."""
    model_config = ConfigDict(extra="forbid")

    get_mode: Literal["sources", "pick"] | None = None
    quality_floor: Literal["any", "320", "lossless", "24bit"] | None = None


def _answer(stored: dict[str, str] | None, can_save: bool) -> dict:
    """
    Every preference, the user's own where they set one (and it is still allowed) and the default
    otherwise; `stored` names the ones they set; `seeded` whether anything was ever saved for them
    (SEEDED, or any row) - the app seeds a user's preferences once, when it is false - and
    `can_save` whether deadwax can keep them at all (an unwritable database).
    """
    kept = {key: value for key, value in (stored or {}).items() if value in PREFERENCES.get(key, ())}
    return {**DEFAULTS, **kept, "stored": sorted(kept), "seeded": bool(stored), "can_save": can_save}


async def _stored(request: Request, user: str) -> tuple[dict[str, str] | None, bool]:
    store = getattr(request.app.state, "store", None)
    if store is None or not getattr(store, "available", False):
        return None, False
    stored = await store.user_preferences(user)
    return stored, stored is not None


@router.get("")
async def me(user: str = Depends(current_user)):
    return {"user": user, "admin": is_admin(user), "auth": auth_mode(), "version": __version__}


@router.get("/preferences")
async def preferences(request: Request, user: str = Depends(current_user)):
    stored, can_save = await _stored(request, user)
    return _answer(stored, can_save)


@router.put("/preferences")
async def save_preferences(request: Request, body: Preferences, user: str = Depends(current_user)):
    """
    Set any of the preferences; the rest are left as they are. Answers with all of them, as GET.
    Every save - an empty one too, which is the app's seeding when there was nothing to carry over -
    also writes SEEDED, so the app seeds a user once.
    """
    values = body.model_dump(exclude_none=True)
    store = getattr(request.app.state, "store", None)
    if store is None or not getattr(store, "available", False):
        raise HTTPException(status_code=503, detail="deadwax can't keep preferences: its database isn't writable")
    if not await store.set_user_preferences(user, {**values, SEEDED: "1"}):
        raise HTTPException(status_code=503, detail="deadwax couldn't save that: its database refused the write")
    stored, can_save = await _stored(request, user)
    return _answer(stored, can_save)
