"""
Personal libraries in Navidrome (2.0.0-player.51, step 5 of the multi-user plan): each album in a user's
ledger starred AS THAT USER, and their starred albums read back - two-way with Amperfy, since your
library is your Navidrome favourites. src/library_ledger.py has the rules; store.py the ledger.

  STARRED AS YOU, ONCE NAVIDROME HAS IT. An entry waiting is found with search3 by its release id (the id
  bridge's way: an album believed only when its own musicBrainzId is the release), starred with `star`,
  then CONFIRMED with getAlbum's `starred` - `star` answers OK even for an id Navidrome doesn't know. Not
  found, not confirmed, Navidrome down: it waits, saying why, and is tried again - 30 s, doubling, at
  most every half hour, for as long as it takes (library_ledger.retry_after).

  EVERY CALL IS MADE AS ITS USER - with the token and salt they last signed in with (store.py's
  user_credentials, sealed with DEADWAX_SECRET_KEY), kept per user, not per session, so an album filed
  overnight is starred without anyone signed in. Never NAVIDROME_USER's login, never Navidrome's admin.
  Navidrome refusing it (error 40: the password changed) kills the credential - the albums wait until
  the user signs in again (auth.sign_in keeps the new one), and their library view says so.

  READ BACK EVERY FEW MINUTES (SYNC_SECONDS) while deadwax holds their credential: getStarred2's albums.
  An album starred elsewhere (Amperfy) is added; one unstarred is removed - EXCEPT when the star was lost
  rather than taken away: the album missing from Navidrome (mid-retag, or between scans), back under
  another Navidrome id than the one deadwax starred (an apply that changed its tags), or being applied to
  right now (library_ledger.retagging). Those wait to be starred again instead. Only albums count: song
  and artist stars stay ordinary favourites. Pins stay deadwax's own (notes/app-artists-pins.md).

A lifespan task with logins on and a database (run_library_worker); a kick (library_ledger.kick) wakes it
early. One task, so its calls to Navidrome are one at a time - a seeding of a hundred albums is three
hundred small calls in a row, a few seconds on a LAN.
"""

import asyncio
import time
from collections import Counter

import httpx

from src import library_ledger as rules
from src.api.navidrome_endpoint import API_VERSION, CLIENT_NAME, NOT_NAVIDROME, NavidromeError, subsonic_body
from src.auth import KEY_CHANGED, LOGIN_GONE, LoginClient, unseal_credential
from src.config import Config
from src.logger import logger

#? How often the worker looks for something to do, with no kick - each pass stars what has come due
WORK_SECONDS = 15
#? How often each user's starred albums are read back ("every few minutes")
SYNC_SECONDS = 300
#? How many entries one pass stars for one user; a full batch asks for another pass at once
STAR_BATCH = 25
#? How many albums one search3 is asked for - enough to find one pressing among an album's others
SEARCH_ALBUMS = 20

#? the HTTP client every star and read is sent through: its own, beside the player's and the sign-in's,
#? held to describe_navidrome_url as they are - nothing is sent to an address that would leak a token
star_client = LoginClient()


class CredentialDead(Exception):
    """Navidrome refused the user's login (error 40), or it won't open."""


class NavidromeDown(Exception):
    """Nothing answered: the pass stops for everyone, and is tried again next time."""


class SyncRefused(Exception):
    """Navidrome answered one user's getStarred2 with an error (not a refused login): their stars aren't read
    back this time - tried again at their next sync - and nobody else's pass is stopped by it."""


class AsUser:
    """Navidrome asked AS one user, with the token and salt they signed in with - `call` as NavidromeClient's."""

    def __init__(self, user: str, username: str, token: str, salt: str):
        self.user, self.username, self.token, self.salt = user, username, token, salt

    async def call(self, endpoint: str, params: dict | None = None) -> dict:
        client = await star_client.get_client()
        query = {key: value for key, value in (params or {}).items() if value is not None}
        #? the login goes on LAST, as the player's does: nothing above stands in for it
        query.update({"u": self.username, "t": self.token, "s": self.salt, "v": API_VERSION, "c": CLIENT_NAME, "f": "json"})
        try:
            response = await client.get(f"/{endpoint}", params=query)
        except httpx.HTTPError as e:
            #? never the URL: it carries the token
            raise NavidromeError(f"Navidrome couldn't be reached ({type(e).__name__})",
                                 unreachable=isinstance(e, httpx.TransportError)) from e
        if response.status_code >= 400:
            raise NavidromeError(f"Navidrome answered {response.status_code}")
        try:
            payload = response.json()
        except ValueError as e:
            raise NavidromeError(f"the answer wasn't JSON - {NOT_NAVIDROME}") from e
        return subsonic_body(payload)


def _same_release(album: dict, release: str) -> bool:
    found = album.get("musicBrainzId")
    return isinstance(found, str) and found.strip().lower() == release.lower()


async def find_album(as_user: AsUser, release: str, title: str | None = None) -> str | None:
    """
    Navidrome's album id for a release, asked as the user - search3 by the release id, then by the
    album's title - believed only when its own musicBrainzId is the release; None when Navidrome hasn't
    got it. RAISES NavidromeError (unlike the id bridge's navidrome_album): a refused login must not read
    as "not found". The bridge's id kept a moment ago is tried first, checked with getAlbum.
    """
    #? imported here: the bridge's module reaches the download routes, which reach the poller, which
    #? reaches this one through library_ledger - at import time that is a loop
    from src.routes.store_album import forget_navidrome_id, known_navidrome_id, remember_navidrome_id

    known = known_navidrome_id(release)
    if known:
        try:
            album = (await as_user.call("getAlbum", {"id": known})).get("album")
            if isinstance(album, dict) and _same_release(album, release):
                return known
        except NavidromeError as e:
            if e.code != 70:
                raise
        forget_navidrome_id(release)
    for query in dict.fromkeys(term for term in (release, (title or "").strip()) if term):
        body = await as_user.call("search3", {"query": query, "albumCount": SEARCH_ALBUMS, "artistCount": 0, "songCount": 0})
        for album in (body.get("searchResult3") or {}).get("album") or []:
            if isinstance(album, dict) and album.get("id") and _same_release(album, release):
                remember_navidrome_id(release, str(album["id"]))
                return str(album["id"])
    return None


def _fail(error: NavidromeError) -> None:
    """A refused login or nothing answering stop the pass; anything else is the entry's own problem."""
    if error.code == 40:
        raise CredentialDead(LOGIN_GONE) from error
    if error.unreachable:
        raise NavidromeDown(str(error)) from error


async def _wait(store, entry: dict, problem: str, now: float) -> bool | None:
    """The entry waits, saying why, its next try further off: False once that is written - None when the
    ledger wouldn't take it (star_entry's answer)."""
    attempts = int(entry.get("attempts") or 0) + 1
    landed = await store.ledger_wait(entry["user"], entry["album_id"], problem, now + rules.retry_after(attempts))
    return False if landed else None


async def star_entry(store, as_user: AsUser, entry: dict, now: float | None = None) -> bool | None:
    """
    Star one waiting entry as its user, and confirm it held. True once starred (and written); False when
    it waits, saying why; None when the ledger wouldn't take what happened (a full disk, a database it
    can't write) - the entry is unchanged, still due, and the worker must not ask again at once
    (work_once). Raises CredentialDead / NavidromeDown, which stop the pass.
    """
    now = time.time() if now is None else now
    if entry.get("album_state") != "present":
        return await _wait(store, entry, rules.MISSING, now)
    release = (entry.get("release_mbid") or "").strip().lower()
    if not release:
        return await _wait(store, entry, rules.NO_RELEASE, now)
    try:
        album_id = await find_album(as_user, release, entry.get("album"))
        if album_id is None:
            return await _wait(store, entry, rules.NOT_IN_NAVIDROME, now)
        #? (2.0.0-player.65, the 2.0.0 release review) asked first: `star` on an album already starred sets
        #? Navidrome's starred date to now - an album you starred years ago would read as starred today. A
        #? first scan landing within a sync of a sign-in made the ledger's grants before the read-back saw them
        album = (await as_user.call("getAlbum", {"id": album_id})).get("album")
        if not (isinstance(album, dict) and album.get("starred")):
            await as_user.call("star", {"albumId": album_id})
            album = (await as_user.call("getAlbum", {"id": album_id})).get("album")
    except NavidromeError as e:
        if e.unreachable:
            #? said on the entry, not counted against it: Navidrome being away is nobody's backoff
            await store.ledger_wait(entry["user"], entry["album_id"], rules.NAVIDROME_DOWN,
                                    now + rules.FIRST_RETRY_SECONDS, counted=False)
        _fail(e)
        return await _wait(store, entry, rules.NOT_IN_NAVIDROME if e.code == 70 else rules.NOT_CONFIRMED, now)
    if isinstance(album, dict) and album.get("starred"):
        return True if await store.ledger_starred(entry["user"], entry["album_id"], album_id) else None
    return await _wait(store, entry, rules.NOT_CONFIRMED, now)


async def star_due(store, as_user: AsUser, now: float | None = None) -> tuple[int, int, int]:
    """
    Star `as_user`'s entries whose turn has come, at most STAR_BATCH: (starred, tried, written) - written
    counting the entries whose outcome the ledger took (starred, or waiting with a later turn).
    """
    now = time.time() if now is None else now
    due = await store.ledger_due(as_user.user, now, STAR_BATCH)
    starred = written = 0
    for entry in due:
        outcome = await star_entry(store, as_user, entry, now)
        starred += outcome is True
        written += outcome is not None
    return starred, len(due), written


async def sync_user(store, as_user: AsUser, now: float | None = None, first: bool = False) -> dict:
    """
    Read `as_user`'s starred albums back (getStarred2) and bring the ledger in line - see the module's
    note: starred elsewhere is added, unstarred is removed, a star LOST is put back. Albums only.

    `first`: deadwax has never read this user's stars back (user_credentials.synced_at): what this read
    adds was theirs before deadwax kept a ledger of it - favourites from before - so it goes in SEEN, not
    "new in your library" (review: a user with three hundred favourites would have had three hundred New
    marks). Every read after it marks what it adds new: a star made since is something added. It counts
    as done (synced_at written) only when the store index knew the store as it began (index_scanned):
    before the library's first scan the index finds none of the favourites, and the next read - no longer
    the first - would have added every one of them New (review). Until then each read is the first.

    Raises CredentialDead / NavidromeDown - and SyncRefused when getStarred2 itself answers with another
    error, which is this user's problem alone. Counts what changed.
    """
    now = time.time() if now is None else now
    user = as_user.user
    counts = {"added": 0, "confirmed": 0, "removed": 0, "lost": 0}
    root = Config.LIBRARY_PATH or ""
    #? asked BEFORE the read: a first scan finishing while it runs leaves it a read of the index before
    #? the scan, which mustn't count as done
    index_known = first and bool(root) and await store.index_scanned(root)
    try:
        body = await as_user.call("getStarred2")
    except NavidromeError as e:
        _fail(e)
        #? it answered - with an error, an HTTP status, or something not JSON - so it isn't down: never
        #? stop everyone's pass on one user's read (review), never say "Navidrome isn't answering"
        raise SyncRefused(str(e)) from e
    starred: dict[str, dict] = {}
    #? (2.0.0-player.65) starred albums Navidrome reads no release id from, by (album artist, name) - None where
    #? two share them: what an untagged entry is matched to (deadwax can't star one, but you can, in Amperfy)
    untagged: dict[tuple[str, str], dict | None] = {}
    starred_ids: set[str] = set()
    for album in (body.get("starred2") or {}).get("album") or []:
        if not isinstance(album, dict) or not album.get("id"):
            continue
        starred_ids.add(str(album["id"]))
        release = album.get("musicBrainzId")
        if isinstance(release, str) and release.strip():
            starred.setdefault(release.strip().lower(), album)
        else:
            key = _named(album.get("artist"), album.get("name"))
            untagged[key] = None if key in untagged else album

    entries = await store.ledger_entries(user)
    if entries is None:
        return counts

    #? an untagged entry is matched only by a name no other of this user's untagged entries has: two pressings
    #? of one album in the store (Album (2001), Album (2001) [Deluxe]) would both be confirmed from one star
    #? (the 2.0.0-player.65 review) - then neither is, and both wait
    names = Counter(_named(entry.get("artist"), entry.get("album")) for entry in entries
                    if entry["state"] in ("waiting", "starred") and not (entry.get("release_mbid") or "").strip())
    for key, count in names.items():
        if count > 1:
            untagged[key] = None

    held: set[str] = set()
    for entry in entries:
        release = (entry.get("release_mbid") or "").strip().lower()
        if entry["state"] in ("waiting", "starred") and not release:
            await _untagged(store, as_user, entry, untagged, starred_ids, counts)
            continue
        if entry["state"] not in ("waiting", "starred"):
            continue
        held.add(release)
        album = starred.get(release)
        if album is not None and (entry["state"] == "waiting" or entry.get("navidrome_id") != str(album["id"])):
            if await store.ledger_starred(user, entry["album_id"], str(album["id"])):
                counts["confirmed"] += 1

    #? starred elsewhere - Amperfy - and in the store, but not held: added (an unstarred one held again)
    for release, album in starred.items():
        if release in held:
            continue
        rows = await store.index_present(root, release) if root else []
        if rows and await store.ledger_sync_add(user, [row["id"] for row in rows], str(album["id"]), seen=first):
            counts["added"] += 1

    #? held and starred by deadwax, not starred now: unstarred - or a star lost
    for entry in entries:
        release = (entry.get("release_mbid") or "").strip().lower()
        if entry["state"] != "starred" or not release or release in starred:
            continue
        if entry.get("album_state") != "present" or rules.retagging(entry.get("path")):
            continue
        try:
            album_id = await find_album(as_user, release, entry.get("album"))
            album = (await as_user.call("getAlbum", {"id": album_id})).get("album") if album_id else None
        except NavidromeError as e:
            _fail(e)
            continue
        if album_id is None or album_id != entry.get("navidrome_id"):
            #? missing from Navidrome (mid-retag, between scans), or back under another id: the star was
            #? lost, not taken away - starred again at its turn
            if await store.ledger_wait(user, entry["album_id"], rules.STAR_LOST, now, counted=False,
                                       from_state=("starred",)):
                counts["lost"] += 1
        elif isinstance(album, dict) and album.get("starred"):
            await store.ledger_starred(user, entry["album_id"], album_id)
        elif await store.ledger_remove(user, entry["album_id"], "unstarred", entry.get("navidrome_id")):
            counts["removed"] += 1
    if index_known:
        await store.ledger_synced(user, now)
    return counts


def _named(artist, name) -> tuple[str, str]:
    """An album as an untagged one is matched: album artist and name, case and spacing folded."""
    def fold(text) -> str:
        return " ".join(text.split()).casefold() if isinstance(text, str) else ""
    return fold(artist), fold(name)


async def _untagged(store, as_user: AsUser, entry: dict, untagged: dict, starred_ids: set[str], counts: dict) -> None:
    """
    (2.0.0-player.65, the 2.0.0 release review) An entry whose album has no release id: deadwax can't find it in
    Navidrome to star it, so it waited for ever - even one already starred (the first admin's seed takes in every
    album of the store, untagged ones too, and a store from Soulseek holds many). Starred by you, it is matched to
    the one starred album Navidrome reads no release id from with its album artist and name, and confirmed. Once
    starred: kept while that album stays starred; unstarred (getAlbum says so) it is removed, as a tagged one is;
    gone from Navidrome (error 70), or being applied to, it is left as it is - a star lost isn't one taken away.
    """
    user = as_user.user
    if entry["state"] == "waiting":
        album = untagged.get(_named(entry.get("artist"), entry.get("album")))
        if album is not None and await store.ledger_starred(user, entry["album_id"], str(album["id"])):
            counts["confirmed"] += 1
        return
    navidrome_id = entry.get("navidrome_id")
    if not navidrome_id or navidrome_id in starred_ids or entry.get("album_state") != "present" \
            or rules.retagging(entry.get("path")):
        return
    try:
        album = (await as_user.call("getAlbum", {"id": navidrome_id})).get("album")
    except NavidromeError as e:
        _fail(e)
        return
    if isinstance(album, dict) and not album.get("starred") \
            and await store.ledger_remove(user, entry["album_id"], "unstarred", navidrome_id):
        counts["removed"] += 1


_last_sync: dict[str, float] = {}


def forget_syncs() -> None:
    """Every user's sync forgotten (tests; a start)."""
    _last_sync.clear()


async def work_once(store, now: float | None = None) -> dict:
    """
    One pass: for each user with a live credential, their stars read back when due, then what is due of
    their library starred. A credential refused (or that won't open) is noted dead - their albums wait;
    Navidrome not answering stops the pass; a read-back Navidrome answers with an error is that user's
    alone (SyncRefused), tried again at their next sync, their starring going on. Counts what was done; `more` when a batch was full and every
    outcome in it was written - progress made, so another pass at once is worth it.
    """
    now = time.time() if now is None else now
    done = {"starred": 0, "tried": 0, "synced": 0, "dead": 0, "more": False}
    if not getattr(store, "available", False) or not Config.logins_on():
        return done
    try:
        credentials = await asyncio.to_thread(store.live_credentials)
    except Exception as e:
        logger.error(f"could not read whose albums to star ({type(e).__name__}: {e})")
        return done
    for row in credentials:
        user = row["user"]
        opened = unseal_credential(row["credential"])
        if opened is None:
            await _dead(store, row, KEY_CHANGED)
            done["dead"] += 1
            continue
        as_user = AsUser(user, *opened)
        try:
            if now - _last_sync.get(user, 0.0) >= SYNC_SECONDS:
                try:
                    counts = await sync_user(store, as_user, now, first=row.get("synced_at") is None)
                except SyncRefused as e:
                    #? tried again at their next sync; their albums are still starred below
                    logger.warning(f"could not read {user}'s starred albums back from Navidrome ({e}) - deadwax "
                                   f"asks again in a few minutes")
                    counts = None
                _last_sync[user] = now
                if counts is not None:
                    done["synced"] += 1
                    if any(counts.values()):
                        logger.info(f"{user}'s stars read back: {counts['added']} added, {counts['removed']} "
                                    f"unstarred, {counts['lost']} lost and to be starred again", extra={"frontend": True})
            starred, tried, written = await star_due(store, as_user, now)
            done["starred"] += starred
            done["tried"] += tried
            #? another pass at once only for a full batch the ledger took every word of: one whose writes
            #? failed (a full disk, /config refusing writes while reads still work) leaves the same entries
            #? due, and asking again at once would hammer Navidrome as each user, non-stop (review) - it
            #? waits for the next pass like anything else
            done["more"] = done["more"] or (tried >= STAR_BATCH and written == tried)
        except CredentialDead:
            await _dead(store, row, LOGIN_GONE)
            done["dead"] += 1
        except NavidromeDown as e:
            #? what waits is said to wait on Navidrome - not counted against it - and the pass stops
            await store.ledger_note_waiting(user, rules.NAVIDROME_DOWN)
            logger.debug(f"starring stopped for now: {e}")
            break
    return done


async def _dead(store, row: dict, why: str) -> None:
    try:
        if await asyncio.to_thread(store.credential_dead, row["user"], why, row["credential"], time.time()):
            logger.warning(f"deadwax can't star albums for {row['user']} any more: {why} Their albums wait until they "
                           f"sign in again.", extra={"frontend": True})
    except Exception as e:
        logger.warning(f"could not note that {row['user']}'s login no longer works ({type(e).__name__}: {e})")


async def run_library_worker(store) -> None:
    """The starring worker, for as long as deadwax runs with logins on: a pass every WORK_SECONDS, or at a kick."""
    event = asyncio.Event()
    rules.worker_started(asyncio.get_running_loop(), event)
    forget_syncs()
    try:
        while True:
            try:
                await asyncio.wait_for(event.wait(), WORK_SECONDS)
            except asyncio.TimeoutError:
                pass
            event.clear()
            try:
                done = await work_once(store)
                if done["more"]:
                    event.set()
            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.error(f"starring albums couldn't run this time ({type(e).__name__}: {e})")
    finally:
        rules.worker_stopped()
