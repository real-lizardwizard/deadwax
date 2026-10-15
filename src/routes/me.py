"""
Who the page is talking to: `GET /deadwax/me`, and what they chose for themselves:
`GET`/`PUT /deadwax/me/preferences` (2.0.0-player.15).

The app at /player/ decides what to show from this, not from assumptions - admin-only rows (server
settings, the review queue, the log, editing) show when `admin` is true, and Sign out only when
logins are on. With logins off it is always the implicit admin, `local` (src/users.py), and the
page says "logins are off"; with them on (2.0.0-player.48) the signed-in user - and with no session a
401, as every route but the public ones answers (src/auth.py), which is how the app knows to sign in.

The preferences are You > Getting albums in the app: "When I tap Get" (show me the sources, or
pick the best source for me), the quality floor and - since 2.0.0-player.41 - Format (any, prefer
lossless, lossless only: what the find route scores a folder's format by, src/matching.py score_format,
and Lossless only leaves out a folder with no lossless file). Kept PER USER on the server (store.user_prefs),
through `current_user` like everything per user, so a person's choice follows them from device to
device - unlike a device's own settings (Gapless, Maximum quality), which stay in its browser.
Only the keys in PREFERENCES, and only the values listed for each, are taken: anything else is a
422 and nothing is written, so a typo can't leave a setting the app can't read. A PUT is a write,
so the same-origin guard (src/api/same_origin.py) stands in front of it like every other. Every save
also writes SEEDED, so the answer's `seeded` says whether anything was ever saved for the user -
what lets the app carry the main page's settings over once, without storing the defaults - and
`unseeded` which preferences were added since the app last carried them over, so a preference new in
a later version (Format, 2.0.0-player.41) is carried over once too, for a user seeded before it,
without carrying the older ones over again on top of what they chose since.
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
#? source must at least be - any, 320 kbps, lossless, 24-bit. `format_preference` (2.0.0-player.41):
#? the Format a search is scored by - prefer lossless (the main page's default), any, lossless only -
#? sent with every Get as the find route's `format_preference`. Keep in step with Preferences below
#? and with ui/src/lib/getSettings.ts, which tests/test_me_prefs.py reads to hold the three to one.
PREFERENCES: dict[str, tuple[str, ...]] = {
    "get_mode": ("sources", "pick"),
    "quality_floor": ("any", "320", "lossless", "24bit"),
    "format_preference": ("prefer_lossless", "any", "lossless_only"),
}

DEFAULTS = {key: values[0] for key, values in PREFERENCES.items()}

#? A row every save writes beside what it sets (2.0.0-player.15, review): it says the app has written
#? for this user - which is what tells the app it has already carried the main page's settings over
#? (which ones: below), even when that came to nothing but the defaults and so stored no preference
#? at all. The defaults are never stored as if chosen: an absent preference is its default, so a
#? default changed later reaches everyone who never chose. An underscore, so no preference (a
#? pydantic field, which can't start with one) can ever be called this.
SEEDED = "_seeded"

#? What SEEDED holds (2.0.0-player.41): the preferences the app has carried over from the main page,
#? comma-separated - every save writes every key there is (`_seeded_value`). A row from before then
#? says "1", which meant the two there were: those count as carried over, and Format, new since, does
#? not - so the app carries Format over once for a user it seeded at 2.0.0-player.15, and only Format.
SEEDED_BEFORE = ("get_mode", "quality_floor")


def _seeded_value() -> str:
    """What every save writes in SEEDED: every preference there is, carried over or chosen since."""
    return ",".join(sorted(PREFERENCES))


def _unseeded(stored: dict[str, str] | None) -> list[str]:
    """
    The preferences never carried over for this user: every one when nothing was ever saved; for a row
    from before SEEDED listed them (its "1" - or rows with no SEEDED at all), all but SEEDED_BEFORE.
    """
    if not stored:
        return sorted(PREFERENCES)
    marker = stored.get(SEEDED)
    seeded = set(SEEDED_BEFORE) if marker in (None, "1") else set(marker.split(","))
    return sorted(key for key in PREFERENCES if key not in seeded)


class Preferences(BaseModel):
    """A PUT: any of the preferences, each one of its values. Nothing else - extra keys are refused."""
    model_config = ConfigDict(extra="forbid")

    get_mode: Literal["sources", "pick"] | None = None
    quality_floor: Literal["any", "320", "lossless", "24bit"] | None = None
    format_preference: Literal["prefer_lossless", "any", "lossless_only"] | None = None


def _answer(stored: dict[str, str] | None, can_save: bool) -> dict:
    """
    Every preference, the user's own where they set one (and it is still allowed) and the default
    otherwise; `stored` names the ones they set; `seeded` whether anything was ever saved for them
    (SEEDED, or any row) - the app seeds a user's preferences once, when it is false - `unseeded`
    which preferences it has never carried over for them (every one until then; since, any added in
    a later version - the app carries those over once, and only those), and `can_save` whether
    deadwax can keep them at all (an unwritable database).
    """
    kept = {key: value for key, value in (stored or {}).items() if value in PREFERENCES.get(key, ())}
    return {**DEFAULTS, **kept, "stored": sorted(kept), "seeded": bool(stored), "unseeded": _unseeded(stored), "can_save": can_save}


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
    also writes SEEDED, listing every preference there is, so the app seeds each one for a user once.
    """
    values = body.model_dump(exclude_none=True)
    store = getattr(request.app.state, "store", None)
    if store is None or not getattr(store, "available", False):
        raise HTTPException(status_code=503, detail="deadwax can't keep preferences: its database isn't writable")
    if not await store.set_user_preferences(user, {**values, SEEDED: _seeded_value()}):
        raise HTTPException(status_code=503, detail="deadwax couldn't save that: its database refused the write")
    stored, can_save = await _stored(request, user)
    return _answer(stored, can_save)
