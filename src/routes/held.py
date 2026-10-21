"""
Held by nobody (2.0.0-player.51, step 5 of the multi-user plan) - the admin's, at /deadwax/library/held
(included with require("library") since 2.0.0-player.61 - Look after the library: tests/test_logins.py's ROUTES):

  GET  ""                     every album in the store nobody holds - one copied in by hand or by another
                              tool belongs to nobody, and stays for anyone to add - and the downloads
                              flagged for a look: every file was already in the folder they'd have filed
                              into, but that folder holds another pressing or an untagged rip, so nobody
                              was given it.
  POST "/flags/{id}/add"      give a flagged album to those who asked, after all - their row then says
                              it was added.
  POST "/flags/{id}/dismiss"  put the flag away - their row then says an admin has looked.

Library care draws it, with logins on (app/LibraryCare.tsx).
"""

from fastapi import APIRouter, HTTPException, Request

from src import library_ledger as rules
from src.config import Config
from src.logger import logger

router = APIRouter()


def _store(request: Request):
    store = getattr(request.app.state, "store", None)
    if store is None or not getattr(store, "available", False):
        raise HTTPException(status_code=503, detail="deadwax can't read its database, so it can't say who holds what")
    return store


def _album(row: dict) -> dict:
    return {
        "id": row.get("id"),
        "path": row.get("path") or "",
        "artist": row.get("artist") or "",
        "album": row.get("album") or "",
        "edition": row.get("edition") or "",
        "year": row.get("year") or "",
        "release_mbid": row.get("release_mbid") or None,
        "formats": row.get("formats") or [],
        "track_count": row.get("track_count") or 0,
    }


def _flag(row: dict) -> dict:
    return {key: row.get(key) for key in ("id", "album_id", "artist", "album", "path", "release_mbid", "users", "created_at")}


@router.get("")
async def held_by_nobody(request: Request):
    store = _store(request)
    albums = await store.ledger_unheld(Config.LIBRARY_PATH or "")
    flags = await store.flags_open()
    if albums is None or flags is None:
        raise HTTPException(status_code=503, detail="deadwax couldn't read its database, so it can't say who holds what")
    return {"count": len(albums), "albums": [_album(row) for row in albums], "flags": [_flag(row) for row in flags]}


@router.post("/flags/{flag_id}/add")
async def add_flagged(request: Request, flag_id: int):
    """The admin has looked: the album goes into the libraries of those who asked for it, as if filed."""
    store = _store(request)
    flags = {flag["id"]: flag for flag in await store.flags_open() or []}
    if flag_id not in flags:
        raise HTTPException(status_code=409, detail="That has been dealt with already.")
    #? the album as it is now - a disc folder merged since is followed to the folder it went into
    found = (await store.index_follow([flags[flag_id].get("album_id")]) or {}) if flags[flag_id].get("album_id") else {}
    row = found.get(flags[flag_id].get("album_id"))
    if row is None or row.get("state") != "present":
        raise HTTPException(status_code=409, detail="That album isn't in the store any more - put the flag away.")
    flag = await store.flag_close(flag_id, "added")
    if flag is None:
        raise HTTPException(status_code=409, detail="That has been dealt with already.")
    #? never the break-glass admin, who has no library (a flag from before that rule may name it)
    users = [user for user in flag.get("users") or [] if rules.has_library(user)]
    added = await store.grant_albums(users, [row["id"]], rules.GRABBED) if users else 0
    if users:
        #? the requesters' row says so - it said "so not added - an admin has been asked to look" (review)
        if flag.get("job_id") is not None:
            await store.set_job_grant(flag["job_id"], row["id"], rules.ADDED, was=rules.FLAGGED)
        logger.info(f"added {flag.get('artist')} - {flag.get('album')} to {', '.join(users)}'s library after a look",
                    extra={"frontend": True})
        rules.kick()
    return {"added": bool(added), "users": users}


@router.post("/flags/{flag_id}/dismiss")
async def dismiss_flag(request: Request, flag_id: int):
    """The admin has looked and left it: still nobody's - and the requesters' row stops saying an admin
    has been asked to look."""
    store = _store(request)
    flag = await store.flag_close(flag_id, "dismissed")
    if flag is None:
        raise HTTPException(status_code=409, detail="That has been dealt with already.")
    if flag.get("job_id") is not None:
        await store.set_job_grant(flag["job_id"], flag.get("album_id"), rules.LOOKED, was=rules.FLAGGED)
    return {"dismissed": True}
