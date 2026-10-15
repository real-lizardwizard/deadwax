"""
Your library (2.0.0-player.51, step 5 of the multi-user plan) - the user's own routes, at
/deadwax/me/library (included with current_user: every one a USER's, tests/test_logins.py's ROUTES):

  GET  ""         what your library holds and how far its starring has got: how many albums, how many
                  still waiting to be starred and why - Navidrome no longer taking your login above all
                  ("sign in again") - the albums new in it (the marker Home and the Library draw), and the
                  ones an admin deleted ("removed by the admin, request it again"). With logins off,
                  `{"on": false}` and nothing else: the one user's library is kept silently, never shown.
  POST "/add"     Add to my library: a pressing the store holds - checked on disk, as Find checks it - goes
                  into your library, to be starred for you. The body is a Find's (the release), so the
                  pressing is judged the way the store line judged it.
  POST "/seen"    you opened it: the new marker goes (by release id, or by the store's album ids).
  POST "/dismiss" put away an album the admin deleted.

The starring itself is src/stars.py's, in the background; these write the ledger and wake it.
"""

import asyncio

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from src import auth
from src import library_ledger as rules
from src.config import Config
from src.logger import logger
from src.routes.download import FindCandidatesRequest
from src.store_index import held_copy
from src.users import current_user

router = APIRouter()

#? said for the break-glass admin, who has no Navidrome account behind them
NO_ACCOUNT = "The break-glass admin has no Navidrome account, so there's no library to add to - sign in as yourself."
LOGINS_OFF = "Logins are off, so there's one library and everything in the store is in it."


def has_library(user: str) -> bool:
    """Whether `user` can have a library: everyone signed in through Navidrome - not the break-glass admin
    (library_ledger.has_library, which a filing's grant asks too)."""
    return rules.has_library(user)


def _usable(store) -> bool:
    return store is not None and bool(getattr(store, "available", False))


def _entry(entry: dict) -> dict:
    """An entry as the page reads it: which album, and what it is."""
    return {
        "album_id": entry["album_id"],
        "artist": entry.get("artist") or "",
        "album": entry.get("album") or "",
        "release_mbid": entry.get("release_mbid") or None,
        "release_group_mbid": entry.get("release_group_mbid") or None,
        "navidrome_id": entry.get("navidrome_id") or None,
        "added_at": entry.get("added_at"),
        "how": entry.get("how"),
    }


def _login_state(store, user: str) -> tuple[str, str | None]:
    """('ok' | 'dead' | 'none', why) - whether deadwax can star for `user` now. SYNCHRONOUS."""
    row = store.credential_row(user)
    if row is None:
        #? signed in before credentials were kept per user: their session's stands in (kept here once)
        store.live_credentials()
        row = store.credential_row(user)
    if row is None:
        return "none", None
    if row.get("dead_at"):
        return "dead", row.get("dead_why") or auth.LOGIN_GONE
    return "ok", None


@router.get("")
async def my_library(request: Request, user: str = Depends(current_user)):
    if not Config.logins_on():
        return {"on": False}
    store = getattr(request.app.state, "store", None)
    if not has_library(user):
        return {"on": True, "library": False, "kept": False}
    if not _usable(store):
        return {"on": True, "library": True, "kept": False}
    entries = await store.ledger_entries(user)
    if entries is None:
        return {"on": True, "library": True, "kept": False}
    try:
        login, why = await asyncio.to_thread(_login_state, store, user)
    except Exception as e:
        logger.warning(f"could not read whether {user}'s login still works: {e}")
        login, why = "none", None

    held = [entry for entry in entries if entry["state"] in ("waiting", "starred")]
    waiting = [entry for entry in held if entry["state"] == "waiting"]
    return {
        "on": True,
        "library": True,
        "kept": True,
        "count": len(held),
        "starred": len(held) - len(waiting),
        "waiting": len(waiting),
        "incomplete": sum(1 for entry in held if entry.get("incomplete")),
        "login": login,
        "login_problem": why if login == "dead" else None,
        "waiting_albums": [{**_entry(entry), "problem": entry.get("problem"),
                            "words": rules.problem_text(entry.get("problem"))} for entry in waiting],
        "new": [_entry(entry) for entry in held if entry.get("seen_at") is None],
        "removed": [{**_entry(entry), "removed_at": entry.get("removed_at")} for entry in entries
                    if entry["state"] == "removed" and entry.get("removed_why") == "deleted"],
    }


@router.post("/add")
async def add_to_my_library(request: Request, body: FindCandidatesRequest, user: str = Depends(current_user)):
    """
    Add to my library: the pressing the store holds - every folder of it that passes the look Find makes
    (store_index.held_copy: still there, tagged with this release) - into your library, to be starred for
    you in Navidrome. A part held is added marked incomplete. 409 in words when there is nothing to add.
    """
    if not Config.logins_on():
        raise HTTPException(status_code=409, detail=LOGINS_OFF)
    if not has_library(user):
        raise HTTPException(status_code=409, detail=NO_ACCOUNT)
    store = getattr(request.app.state, "store", None)
    if not _usable(store):
        raise HTTPException(status_code=503, detail="deadwax can't read its database, so it can't keep your library")
    if not body.release_mbid:
        raise HTTPException(status_code=409, detail="That pressing has no MusicBrainz release id, so the store can't be asked for it.")
    held = await held_copy(store, Config.LIBRARY_PATH or "", body.release_mbid, body.model_dump())
    if held is None or not held.get("album_ids"):
        raise HTTPException(status_code=409, detail="That pressing isn't in the store now - Get it instead.")
    already = await store.ledger_holds(user, held["album_ids"])
    added = await store.grant_albums([user], held["album_ids"], rules.FROM_STORE, incomplete=not held["complete"], seen=True)
    if not added:
        raise HTTPException(status_code=503, detail="deadwax couldn't write to its database, so it couldn't add it")
    if not already:
        logger.info(f"{user} added {held.get('artist')} - {held.get('album')} to their library from the store",
                    extra={"frontend": True})
    rules.kick()
    return {"added": True, "already": bool(already), "complete": held["complete"]}


class Seen(BaseModel):
    release_mbid: str | None = Field(default=None, max_length=64)
    album_ids: list[int] = Field(default_factory=list, max_length=200)


@router.post("/seen")
async def seen(request: Request, body: Seen, user: str = Depends(current_user)):
    """You opened it: the new marker goes from your entries of this release (or these albums)."""
    store = getattr(request.app.state, "store", None)
    if not Config.logins_on() or not _usable(store):
        return {"cleared": 0}
    return {"cleared": await store.ledger_seen(user, body.release_mbid, body.album_ids)}


class Dismiss(BaseModel):
    album_id: int


@router.post("/dismiss")
async def dismiss(request: Request, body: Dismiss, user: str = Depends(current_user)):
    """Put away an album the admin deleted - one of your "removed by the admin" entries."""
    store = getattr(request.app.state, "store", None)
    if not Config.logins_on() or not _usable(store):
        return {"dismissed": False}
    return {"dismissed": await store.ledger_dismiss(user, body.album_id)}
