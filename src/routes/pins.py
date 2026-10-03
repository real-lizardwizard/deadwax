"""
A user's pins (2.0.0-player.18): `GET`/`PUT /deadwax/me/pins` and `POST /deadwax/me/pins/toggle` - the
albums and artists pinned to the app's Home, in their order. What a pin's ref is, and why a pin is
deadwax's own and NEVER a Navidrome star, is src/pins.py's; this reads and writes them per user,
through `current_user` like everything per user (/deadwax/me/preferences is the pattern), every write
behind the same-origin guard (src/api/same_origin.py) like every other.

  - GET answers every pin as it is NOW. Each album pin's ref is brought up to date: a `release:` pin
    whose release the index has since found becomes `store:<id>`; a merge is followed to the row it
    ended in; a pin whose album isn't there is pointed at a live copy of its release, when there is
    one. Then its state - `present`; `missing`, its folder not there just now (an unmounted share, as
    often as not - it comes back); `gone`, deadwax deleted it - its name from the store row, and
    Navidrome's album id and cover to open it with: the id it last opened checked against Navidrome
    (getAlbum, whose musicBrainzId must still be the release) and, when it isn't, looked up afresh
    (the id bridge's search3) - Navidrome gives an album a new id when its tags change enough, and a
    re-file can change it too. Whatever changed is written back.
  - PUT takes the WHOLE ordered list (Home's Edit): the stored pins it names, in its order; any it
    leaves out are removed; a ref it names that isn't pinned is passed over - it never adds one. With
    `known` - every pin the list was made from - a pin stored since that the page was never told of
    (pinned on another device meanwhile) keeps its place rather than being removed unseen.
  - toggle pins or unpins ONE thing by what it is - an album by its release (or by Navidrome's id for
    it, from which deadwax reads the release itself), an artist by their MusicBrainz id (or by
    Navidrome's id for them and their name) - and says whether it should end up pinned, so asking
    twice is asking once. A new pin goes FIRST, where Home shows it at once. An album with no release
    id can't be pinned: nothing would find it again once it moved. A Navidrome that can't be asked
    for the release is a 503, never "no release id": that would be a fact about the album, and it
    isn't one.

Every answer is the whole list, as GET gives it. Writes to one user's pins go one at a time (a lock -
each is a read, a change and a write), and Navidrome is asked outside it, so a Navidrome that is slow
to answer holds up no toggle. With no usable database at all the answer is nothing pinned with
`can_save` false, and a write is a 503; a database there whose read or write fails just now is a 503
either way - "nothing pinned" would be a wrong answer, and the page keeps what it last had.
"""

import asyncio
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator

from src import pins as rules
from src.api.navidrome_endpoint import NavidromeError, client_for
from src.config import Config
from src.routes import store_album as bridge
from src.routes.navidrome import ID_MAX
from src.store import PIN_COLUMNS
from src.users import current_user

router = APIRouter()

#? One lock per user while anyone holds or waits for it - dropped after, as store_index's release_lock.
_locks: dict[str, list] = {}


@asynccontextmanager
async def _writing(user: str):
    entry = _locks.setdefault(user, [asyncio.Lock(), 0])
    entry[1] += 1
    try:
        async with entry[0]:
            yield
    finally:
        entry[1] -= 1
        if not entry[1]:
            _locks.pop(user, None)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _store(request: Request):
    store = getattr(request.app.state, "store", None)
    return store if store is not None and getattr(store, "available", False) else None


def _stored_form(pin: dict) -> dict:
    """A pin as its row holds it - what is compared to say whether anything needs writing."""
    form = {column: pin.get(column) for column in PIN_COLUMNS}
    form["label"] = form["label"] or ""
    form["sub"] = form["sub"] or ""
    form["navidrome_id"] = form["navidrome_id"] or None
    form["cover"] = form["cover"] or None
    return form


async def _live_release_row(store, root: str, release: str | None) -> dict | None:
    """A live store row of the release in this library whose folder is still there - or None."""
    if not root or not release:
        return None
    rows = await bridge.live_rows(store, root, await store.index_present(root, release))
    return rows[0] if rows else None


async def _up_to_date(store, root: str, pins: list[dict]) -> tuple[list[dict], dict[tuple[str, str], dict | None]]:
    """
    Each pin with its ref brought up to date (see the module's note), each (kind, ref) once - and,
    for every album pin, the store row it ends at (None for a `release:` pin the index doesn't hold,
    and for a `store:` pin with nothing to follow).
    """
    ids = [rules.store_id_of(pin["ref"]) for pin in pins if pin["kind"] == "album"]
    followed = await store.index_follow([row_id for row_id in ids if row_id is not None])
    if followed is None:
        #? not "every album gone": the index couldn't be read, and the page keeps what it last had
        raise HTTPException(status_code=503, detail="deadwax couldn't read its store index just now")
    rows: dict[tuple[str, str], dict | None] = {}
    current: list[dict] = []
    for pin in pins:
        if pin["kind"] != "album":
            current.append(pin)
            continue
        release = rules.release_of(pin["ref"])
        if release is not None:
            row = await _live_release_row(store, root, release)
        else:
            row_id = rules.store_id_of(pin["ref"])
            row = followed.get(row_id) if row_id is not None else None
            #? a live row whose folder has gone since: marked missing, as the id bridge marks it
            if row is not None and root and rules.album_state(row, root) == "present":
                if not await bridge.live_rows(store, root, [row]):
                    row = {**row, "state": "missing"}
            #? not here: a live copy of the same release stands in for it, when there is one
            if row is not None and rules.album_state(row, root) != "present" and row.get("release_mbid"):
                row = await _live_release_row(store, root, row["release_mbid"]) or row
        ref = rules.store_ref(row["id"]) if row is not None and row.get("id") is not None else pin["ref"]
        moved = {**pin, "ref": ref}
        rows.setdefault(rules.key(moved), row)
        current.append(moved)
    return rules.unique(current), rows


def _album_release(pin: dict, row: dict | None) -> str | None:
    return (row or {}).get("release_mbid") or rules.release_of(pin["ref"])


def _album_state(pin: dict, row: dict | None, root: str) -> str:
    #? a release the index doesn't hold yet isn't known to be gone - Navidrome may well have it
    if row is None and rules.release_of(pin["ref"]) is not None:
        return "present"
    return rules.album_state(row, root)


async def _navidrome_for(client, release: str, title: str, known: str | None, cover: str | None) -> tuple[str | None, str | None]:
    """
    Navidrome's album id for the release, and its cover: the id kept for it (the bridge's, else the
    one this pin last opened), checked with getAlbum - whose musicBrainzId must still be the release -
    else looked up afresh through the bridge (search3). Navidrome that can't be asked leaves what was
    known standing; an id Navidrome no longer has as the release is forgotten, in the bridge too.
    """
    candidate = bridge.known_navidrome_id(release) or known
    if candidate:
        try:
            body = await client.call("getAlbum", {"id": candidate})
        except NavidromeError as e:
            if e.status != 404:
                return known or candidate, cover
            body = {}
        album = body.get("album")
        if isinstance(album, dict) and bridge.is_release(album, release):
            bridge.remember_navidrome_id(release, candidate)
            return candidate, album.get("coverArt") or cover
        bridge.forget_navidrome_id(release)
    found = await bridge.navidrome_album(client, release, title)
    if not found:
        return None, cover
    try:
        album = (await client.call("getAlbum", {"id": found})).get("album")
    except NavidromeError:
        album = None
    return found, (album.get("coverArt") if isinstance(album, dict) else None) or None


async def _resolved(client, pin: dict, row: dict | None, root: str) -> tuple[dict, dict]:
    """(the pin as the page reads it, the pin as it should be stored)."""
    if pin["kind"] == "artist":
        return {
            "kind": "artist", "ref": pin["ref"], "label": pin.get("label") or "", "sub": "", "state": "present",
            "navidrome_id": pin.get("navidrome_id") or None, "cover": pin.get("cover") or None,
            "mbid": rules.mbid_of(pin["ref"]),
        }, pin
    release = _album_release(pin, row)
    state = _album_state(pin, row, root)
    label = (row or {}).get("album") or pin.get("label") or ""
    sub = (row or {}).get("artist") or pin.get("sub") or ""
    navidrome_id, cover = pin.get("navidrome_id") or None, pin.get("cover") or None
    if state == "present" and release:
        navidrome_id, cover = await _navidrome_for(client, release, label, navidrome_id, cover)
    return {
        "kind": "album", "ref": pin["ref"], "label": label, "sub": sub, "state": state,
        #? only a present album opens; the rest keep their last id stored, for when they come back
        "navidrome_id": navidrome_id if state == "present" else None, "cover": cover, "release_mbid": release,
    }, {**pin, "label": label, "sub": sub, "navidrome_id": navidrome_id, "cover": cover}


async def _answer(request: Request, user: str, change=None) -> dict:
    """
    Every pin, as GET answers them - after `change(current, rows)` has made the list a write wants
    (run under the user's lock, on the pins as they are now; it may raise an HTTPException).
    """
    store = _store(request)
    root = Config.LIBRARY_PATH or ""
    if store is None:
        if change is not None:
            raise HTTPException(status_code=503, detail="deadwax can't keep pins: its database isn't writable")
        return {"pins": [], "can_save": False}

    async with _writing(user):
        stored = await store.pins(user)
        if stored is None:
            #? a database there whose read failed just now (locked past its timeout, say) - not
            #? "nothing pinned", which the page would take as the server's word and draw
            raise HTTPException(status_code=503, detail="deadwax couldn't read its pins just now")
        current, rows = await _up_to_date(store, root, stored)
        wanted = await change(current, rows) if change is not None else current
        if [_stored_form(pin) for pin in wanted] != [_stored_form(pin) for pin in stored]:
            if not await store.write_pins(user, wanted) and change is not None:
                raise HTTPException(status_code=503, detail="deadwax couldn't save that: its database refused the write")

    #? Navidrome is asked outside the lock: a Navidrome slow to answer holds up no one's toggle
    client = client_for(request)
    resolved = await asyncio.gather(*(_resolved(client, pin, rows.get(rules.key(pin)), root) for pin in wanted))

    #? what Navidrome said (an id, a cover) kept for next time - on the pins as they are by then
    found = {rules.key(kept): kept for (_, kept), pin in zip(resolved, wanted) if _stored_form(kept) != _stored_form(pin)}
    if found:
        async with _writing(user):
            again = await store.pins(user)
            if again is not None:
                patched = [found.get(rules.key(pin), pin) for pin in again]
                if [_stored_form(pin) for pin in patched] != [_stored_form(pin) for pin in again]:
                    await store.write_pins(user, patched)

    return {"pins": [public for public, _ in resolved], "can_save": True}


class PinRef(BaseModel):
    """One pin in a PUT's list: its kind and its ref, as GET gave it."""
    model_config = ConfigDict(extra="forbid")

    kind: Literal["album", "artist"]
    ref: str = Field(min_length=1, max_length=rules.LABEL_MAX + len(rules.NAME))

    @model_validator(mode="after")
    def well_formed(self):
        if not rules.valid_ref(self.kind, self.ref):
            raise ValueError(f"not a ref an {self.kind} pin can have")
        return self


class PinOrder(BaseModel):
    """
    A PUT: the whole list, in its order - and, optionally, `known`: every pin the page had been told
    of when it made the list (the server's last answer to it). A pin stored since that isn't in it
    keeps its place (src/pins.py ordered).
    """
    model_config = ConfigDict(extra="forbid")

    pins: list[PinRef] = Field(max_length=rules.PINS_MAX)
    known: list[PinRef] | None = Field(None, max_length=rules.PINS_MAX)


class PinToggle(BaseModel):
    """
    A toggle: one album or artist, by what it is, and whether it should end up pinned. `label`, `sub`
    and `cover` are what Home's card shows for a new pin (the album and its artist, and its picture).
    """
    model_config = ConfigDict(extra="forbid")

    kind: Literal["album", "artist"]
    pinned: bool
    release_mbid: str | None = Field(None, pattern=rules.MBID_PATTERN)
    navidrome_id: str | None = Field(None, min_length=1, max_length=ID_MAX)
    mbid: str | None = Field(None, pattern=rules.MBID_PATTERN)
    name: str | None = Field(None, max_length=rules.LABEL_MAX)
    label: str | None = Field(None, max_length=rules.LABEL_MAX)
    sub: str | None = Field(None, max_length=rules.LABEL_MAX)
    cover: str | None = Field(None, min_length=1, max_length=ID_MAX)

    @model_validator(mode="after")
    def by_what_it_is(self):
        if self.kind == "album":
            if self.mbid or self.name:
                raise ValueError("an album is known by its release_mbid or navidrome_id, not an artist's mbid or name")
            if not (self.release_mbid or self.navidrome_id):
                raise ValueError("an album needs its release_mbid or its navidrome_id")
        else:
            if self.release_mbid:
                raise ValueError("an artist is known by their mbid, or navidrome_id and name, not a release")
            if not (self.mbid or self.navidrome_id):
                raise ValueError("an artist needs their mbid or their navidrome_id")
        return self


@router.get("")
async def pins(request: Request, user: str = Depends(current_user)):
    return await _answer(request, user)


@router.put("")
async def save_pins(request: Request, body: PinOrder, user: str = Depends(current_user)):
    """The whole ordered list: the stored pins it names, in its order - the rest removed."""
    root = Config.LIBRARY_PATH or ""

    async def change(current: list[dict], rows: dict) -> list[dict]:
        #? the list's refs brought up to date as the stored ones were, so a pin upgraded meanwhile
        #? (a `release:` pin the index has found since this list was drawn) is still the pin it names
        async def keys(entries: list[PinRef]) -> list[tuple[str, str]]:
            brought, _ = await _up_to_date(_store(request), root, [{"kind": entry.kind, "ref": entry.ref} for entry in entries])
            return [rules.key(pin) for pin in brought]

        known = await keys(body.known) if body.known is not None else None
        return rules.ordered(current, await keys(body.pins), known)

    return await _answer(request, user, change)


@router.post("/toggle")
async def toggle_pin(request: Request, body: PinToggle, user: str = Depends(current_user)):
    """Pin or unpin one album or artist - see the module's note. Answers with every pin, as GET."""
    store = _store(request)
    if store is None:
        raise HTTPException(status_code=503, detail="deadwax can't keep pins: its database isn't writable")
    root = Config.LIBRARY_PATH or ""

    release = row = ref = None
    if body.kind == "album":
        release = body.release_mbid
        if release is None and body.navidrome_id:
            try:
                release = await bridge.album_release(client_for(request), body.navidrome_id)
            except NavidromeError as e:
                #? an unpin needs no release: the pin is matched by Navidrome's id then (same, below)
                if body.pinned and e.status != 404:
                    #? Navidrome didn't say - not "no release id", which is a fact about the album
                    raise HTTPException(status_code=503, detail="deadwax couldn't ask Navidrome about this album just now - try again")
                if body.pinned:
                    raise HTTPException(status_code=422, detail="deadwax can't pin this album: Navidrome doesn't have it any more")
        if body.pinned and not release:
            raise HTTPException(status_code=422, detail="deadwax can't pin this album: it has no MusicBrainz release id to find it by")
        if body.pinned:
            row = await _live_release_row(store, root, release)
    else:
        ref = rules.artist_ref(body.mbid, body.name or body.label)
        if body.pinned and ref is None:
            raise HTTPException(status_code=422, detail="deadwax can't pin this artist: it needs their MusicBrainz id, or their name")

    def same(pin: dict, rows: dict) -> bool:
        """Whether a stored pin is of this album or artist - as the app's lib/pins.ts matches them."""
        if pin["kind"] != body.kind:
            return False
        if body.kind == "album":
            pinned_release = _album_release(pin, rows.get(rules.key(pin)))
            if pinned_release and release:
                return pinned_release == release
            #? one side has no release to say otherwise: the same album in Navidrome
            return body.navidrome_id is not None and pin.get("navidrome_id") == body.navidrome_id
        if ref is not None and pin["ref"] == ref:
            return True
        #? the same artist in Navidrome, where one side has no MusicBrainz id to say otherwise
        return (body.navidrome_id is not None and pin.get("navidrome_id") == body.navidrome_id
                and (rules.mbid_of(pin["ref"]) is None or body.mbid is None))

    async def change(current: list[dict], rows: dict) -> list[dict]:
        if not body.pinned:
            return [pin for pin in current if not same(pin, rows)]
        existing = next((pin for pin in current if same(pin, rows)), None)
        if existing is not None:
            refreshed = dict(existing)
            #? an artist pinned by name, now known by MusicBrainz id: the same pin, keyed on the id
            if ref is not None and rules.mbid_of(ref) and existing["ref"].startswith(rules.NAME):
                refreshed["ref"] = ref
                rows[rules.key(refreshed)] = None
            refreshed["navidrome_id"] = body.navidrome_id or existing.get("navidrome_id")
            refreshed["cover"] = body.cover or existing.get("cover")
            return rules.unique([refreshed if pin is existing else pin for pin in current])
        if len(current) >= rules.PINS_MAX:
            raise HTTPException(status_code=409, detail=f"Home holds up to {rules.PINS_MAX} pins - unpin one first")
        if body.kind == "album":
            new = {
                "kind": "album",
                "ref": rules.store_ref(row["id"]) if row is not None else rules.release_ref(release),
                "label": (body.label or (row or {}).get("album") or "").strip(),
                "sub": (body.sub or (row or {}).get("artist") or "").strip(),
            }
        else:
            new = {"kind": "artist", "ref": ref, "label": (body.name or body.label or "").strip(), "sub": ""}
        new.update({"navidrome_id": body.navidrome_id, "cover": body.cover, "created_at": _now()})
        rows[rules.key(new)] = row
        return rules.unique([new, *current])

    return await _answer(request, user, change)
