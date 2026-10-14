"""
Which album folders Navidrome lists (2.0.0-player.46) - what raises "Not in Navidrome" in the review
queue, so that no folder on disk is out of the app's reach without saying so.

The app's library IS Navidrome's: its Library tab, album and artist pages, Home's shelves and Search's
library half all show what Navidrome lists. Navidrome became required for the library in this version,
and a folder deadwax's scan holds that Navidrome doesn't list - not scanned yet, unreadable, or outside
Navidrome's music folder - would otherwise be in nobody's view at all. So the queue says so, as an issue
like any other (metadata_health.py's `not_in_navidrome`), and the Edit panel opens on it as on any
queue folder. Not a second library view.

HOW deadwax knows, cheaply and without a page-facing relay - every call here is an internal client call,
made by deadwax as its own Navidrome account (`navidrome`, not `client_for`: what Navidrome lists is a
fact about the server that every viewer of the queue shares, cached once, as the scan wait's
getScanStatus and the stream cache ask):

  - getScanStatus FIRST: when Navidrome last finished a scan (`lastScan`) and whether one is running.
  - getAlbumList2, alphabeticalByName, LISTING_PAGE albums a page until a short page: every album the
    account can see, each with OpenSubsonic's `musicBrainzId` (the release id Navidrome read from the
    tags), its name and its artists. Skipped when Navidrome hasn't scanned since the last listing
    (same `lastScan`, nothing running either time): its albums can't have changed, so one cheap call
    is the usual cost of a refresh.
  - getScanStatus again after the pages: a scan running at either end, or one that finished in
    between, makes the listing UNSETTLED - an album can slip between two pages while Navidrome adds and
    removes them, so such a listing may say an album IS there, never that it isn't.

THE MATCH (`judge`, pure): a folder is listed when its release id is one Navidrome has; else - a folder
with no release id, or one whose id Navidrome's album doesn't carry (an id-less album) - when its
folded album title and one of its artists name an album Navidrome lists. A folder no file of which
names an artist is also tried as "[Unknown Artist]", Navidrome's name for it. The title alone is
enough only against an album credited to "Various Artists" (or marked a compilation), and only for a
folder with no album artist tagged but Various Artists - Navidrome credits Various Artists only then,
so a folder whose album artist is Queen is never "listed" by somebody's compilation of the same name.
A folder deadwax names from its folder rather than its tags (no album tag on any file) is never
judged: Navidrome files those under "[Unknown Album]". And a NEGATIVE needs evidence from a scan that
saw the folder as it is now: a folder changed since Navidrome's last scan BEGAN - `lastScan` is when
it ended, so less its `elapsedTime` (or LISTING_SETTLE_SECONDS when it doesn't say) - keeps the verdict
it had, and has none until it has been judged once. Changed by the folder's own mtime or ctime, the
later (library.py's `changed_at`: a folder filed, a file added or renamed - and a folder moved or
copied in by hand, which keeps its old mtime but not its ctime), or by deadwax writing it (a retag
moves neither: `written_at`, which the scan stamps on the album and the scan cache saves). So a
just-filed album, a just-applied release, a just-fetched cover and a folder just moved in are never
flagged in the seconds before Navidrome's watcher scans them, and one already flagged stays flagged
until Navidrome has looked again. But only for LISTING_GRACE_SECONDS after the change, counted to
when the listing in hand was asked: a folder Navidrome's watcher can't see (outside its music folder)
never brings a scan, and waiting for one would leave exactly the folders the issue is for unflagged
for good. Those last verdicts are kept in memory (`_verdicts`), never written down - the metadata
queue stores only what you ignored (notes/decisions.md) - merged from every read, pruned only by a
real scan that found albums, and carried along when deadwax moves a folder (`follow`).

WHEN it is asked (`ask`): a real scan of the library asks again when the listing is older than
LISTING_FRESH_SECONDS, alongside the disk scan; a Rescan always asks; the count's route
(/queue/summary) asks only when there is no listing yet or it is older than LISTING_STALE_SECONDS; a
snapshot never asks. A read is judged by the answer IN HAND, the refresh running behind it for the
next read - it waits only for Navidrome's very first answer (the one that can put a chip on the page
first opened; nothing reads again on its own) and for a Rescan, at most LISTING_WAIT_SECONDS. Until
Navidrome has answered, nothing is raised; Navidrome unset or failing raises nothing, and `check()`
says why, for the queue to say once.
"""

import asyncio
import time
from dataclasses import dataclass, replace

from src.api.navidrome_endpoint import NavidromeError, navidrome
from src.artists import _fold as fold_name
from src.config import Config
from src.scan_wait import ScanStatus, read_status

#? getAlbumList2's largest page: Subsonic caps `size` at 500, and Navidrome holds to it.
LISTING_PAGE = 500

#? Pages asked at most - 100,000 albums. A server that ignored `offset` would otherwise be asked
#? forever; one that repeats a page ends the listing too (nothing new in it).
LISTING_PAGES_MAX = 200

#? A real scan asks again when the listing is older than this: bursts of reads (a write's rescan, the
#? page shown again) share one answer, and a refresh is usually one getScanStatus anyway.
LISTING_FRESH_SECONDS = 10.0

#? The count's route asks again past this - it is asked often, and a listing this old is still the
#? best guess there is.
LISTING_STALE_SECONDS = 300.0

#? How long Navidrome's FIRST answer is waited for (and a Rescan's), from when it was asked - never
#? longer, however many reads come while it is out. Every other read is judged by the answer in hand.
LISTING_WAIT_SECONDS = 3.0

#? Each call's own bound: the client's read timeout is a minute, made for streams.
LISTING_CALL_TIMEOUT_SECONDS = 10.0

#? With no usable lastScan to measure a folder's changes against (a server that won't say), a folder
#? changed this long before the listing was asked for counts as changed since - and when Navidrome
#? says when its last scan ended but not how long it took (no usable elapsedTime), this long before
#? that end. A scan longer than this could still have passed a folder before it changed.
LISTING_SETTLE_SECONDS = 120.0

#? How long a folder changed since Navidrome's last scan keeps the verdict it had (none, for a folder
#? never judged) when no scan comes - counted from the change to when the listing in hand was asked.
#? Navidrome's watcher scans a change about 5s after it (WatcherWait), so a quarter of an hour is
#? long past any scan that was coming; a folder it still doesn't list then is one its watcher can't
#? see (outside its music folder), or a watcher that is off - and the issue's hint covers both.
LISTING_GRACE_SECONDS = 900.0

#? How Navidrome credits an album with no album artist and many track artists.
VARIOUS_ARTISTS = fold_name("Various Artists")

#? ...and one whose files name no artist at all (consts.UnknownArtist).
UNKNOWN_ARTIST = fold_name("[Unknown Artist]")


@dataclass(frozen=True)
class Listing:
    """What Navidrome lists, reduced to what a folder is matched by. Built by build_listing()."""
    #? release ids, lowercased
    ids: frozenset
    #? (folded title, folded artist) of every album, for every name each is credited with
    names: frozenset
    #? the same for the albums Navidrome knows by no release id
    idless_names: frozenset
    #? folded titles of the albums credited to Various Artists (or marked a compilation)
    compilations: frozenset
    idless_compilations: frozenset
    #? a folder changed after this moment (epoch seconds) may not be what Navidrome last read: when
    #? its last scan BEGAN
    seen_until: float
    #? no scan ran across the asking: the listing can say an album ISN'T there
    settled: bool
    count: int
    #? when Navidrome was last asked for it (epoch seconds) - moved on each time getScanStatus says
    #? it still holds (no scan since). What LISTING_GRACE_SECONDS is counted to.
    asked_at: float


def _text(value) -> str:
    return value.strip() if isinstance(value, str) else ""


def _album_artists(album: dict) -> set[str]:
    """Every name Navidrome credits an album to: its artist, its display artist, OpenSubsonic's artists."""
    names = {_text(album.get("artist")), _text(album.get("displayArtist"))}
    for credit in album.get("artists") or []:
        if isinstance(credit, dict):
            names.add(_text(credit.get("name")))
    return {fold_name(name) for name in names if name}


def build_listing(albums: list[dict], seen_until: float, settled: bool = True,
                  asked_at: float | None = None) -> Listing:
    """Navidrome's albums (getAlbumList2's `album` entries) as a Listing, asked for at `asked_at` (now)."""
    ids, names, idless_names, compilations, idless_compilations = set(), set(), set(), set(), set()
    count = 0
    for album in albums:
        if not isinstance(album, dict):
            continue
        count += 1
        release = _text(album.get("musicBrainzId")).lower()
        title = fold_name(_text(album.get("name")))
        artists = _album_artists(album)
        if release:
            ids.add(release)
        if not title:
            continue
        keys = {(title, artist) for artist in artists}
        various = VARIOUS_ARTISTS in artists or album.get("isCompilation") is True
        names |= keys
        if various:
            compilations.add(title)
        if not release:
            idless_names |= keys
            if various:
                idless_compilations.add(title)
    return Listing(frozenset(ids), frozenset(names), frozenset(idless_names), frozenset(compilations),
                   frozenset(idless_compilations), seen_until, settled, count,
                   time.time() if asked_at is None else asked_at)


def tagged_title(album: dict) -> str:
    """The folder's album title, folded - '' when no file carries an album tag (the scan then names it
    after the folder, and Navidrome files it under "[Unknown Album]": no name to match)."""
    if not any(_text(track.get("album")) for track in album.get("tracks") or []):
        return ""
    return fold_name(_text(album.get("album")))


def folder_artists(album: dict) -> set[str]:
    """
    Every artist the folder could be credited to: the scan's, and each file's album artist and artist
    - and "[Unknown Artist]" when no file names one (the scan's is then the parent folder's name, and
    Navidrome lists the album under its placeholder).
    """
    tracks = album.get("tracks") or []
    names = {_text(album.get("artist"))}
    for track in tracks:
        names.add(_text(track.get("albumartist")))
        names.add(_text(track.get("artist")))
    folded = {fold_name(name) for name in names if name}
    if tracks and not any(_text(t.get("artist")) or _text(t.get("albumartist")) for t in tracks):
        folded.add(UNKNOWN_ARTIST)
    return folded


def may_be_compilation(album: dict) -> bool:
    """
    No file names an album artist but Various Artists: the only folders Navidrome could list as a
    Various Artists album. One with an album artist of its own is listed under that name, so a
    compilation of the same title is somebody else's album, never this folder.
    """
    named = {fold_name(_text(track.get("albumartist"))) for track in album.get("tracks") or []}
    return not (named - {"", VARIOUS_ARTISTS})


def last_change(album: dict) -> float:
    """When the folder last changed, epoch seconds: its mtime, its ctime (`changed_at`), or deadwax
    writing it (`written_at` - a retag moves neither), the latest."""
    times = [album.get(key) for key in ("modified_at", "changed_at", "written_at")]
    return max([float(t) for t in times if isinstance(t, (int, float)) and not isinstance(t, bool)] or [0.0])


def changed_since(album: dict, listing: Listing) -> bool:
    """
    The folder may not be what Navidrome last read: it changed after Navidrome's last scan began -
    and not so long before the listing was asked (LISTING_GRACE_SECONDS) that a scan that was coming
    would have come by then.
    """
    changed = last_change(album)
    return changed > listing.seen_until and changed > listing.asked_at - LISTING_GRACE_SECONDS


def judge(album: dict, listing: Listing, last: bool | None = None) -> bool | None:
    """
    Whether Navidrome lists this folder: True, False - or None, not judged.

    `last` is the verdict it had the last time it was judged. A positive needs only a match; a
    negative needs a settled listing, a folder not changed since Navidrome's last scan (changed_since
    - which a quarter of an hour with no scan ends), and a title to have looked for - otherwise the
    last verdict stands (None for a folder never judged).
    """
    release = _text(album.get("release_mbid")).lower()
    if release and release in listing.ids:
        return True

    title = tagged_title(album)
    if title:
        #? a folder with a release id only matches albums Navidrome knows by NO id by name: an album
        #? with another release's id is another pressing (the deluxe beside the standard)
        names = listing.idless_names if release else listing.names
        compilations = listing.idless_compilations if release else listing.compilations
        if title in compilations and may_be_compilation(album):
            return True
        if any((title, artist) in names for artist in folder_artists(album)):
            return True

    if not title or not listing.settled or changed_since(album, listing):
        return last
    return False


def scan_began(body, status: ScanStatus | None) -> float | None:
    """
    When the scan behind `lastScan` began, epoch seconds - `lastScan` less `elapsedTime`, which
    Navidrome sends as a Go duration (nanoseconds) and works out, with nothing running, as lastScan
    less the time the scan started. None when that can't be had: no status, a scan running (its
    elapsedTime is the running scan's), or no elapsedTime above zero (an older server, or a scan that
    began and never finished - its start then after lastScan).
    """
    if status is None or status.scanning:
        return None
    raw = body.get("scanStatus", {}).get("elapsedTime") if isinstance(body, dict) else None
    if isinstance(raw, bool) or not isinstance(raw, (int, float)) or raw <= 0:
        return None
    return status.last_scan.timestamp() - raw / 1e9


class NavidromeListing:
    """
    The listing, kept for the process - one for everyone, as the scan cache is one. `ask()` refreshes
    it when it is due (waiting only for the first answer, or a Rescan's); `unlisted()` judges a
    scan's albums by it; `check()` says what the queue should say about it; `forget()` drops it (a
    Navidrome setting changed); `follow()` carries a folder's verdict through a move.
    """

    def __init__(self, client=None):
        #? the Navidrome client to ask - the shared one, or a test's
        self._client = client
        self.listing: Listing | None = None
        self.problem: str | None = None
        #? the scan status the listing was taken under: equal again, with nothing running, means no
        #? scan since - its albums can't have changed
        self._status: ScanStatus | None = None
        #? time.monotonic() of the last answer, listing or failure - None: never asked
        self._answered: float | None = None
        self._task: asyncio.Task | None = None
        #? time.monotonic() when that refresh began - a wait never runs past it plus the wait
        self._began = 0.0
        #? bumped by forget(): a refresh begun before it lands nowhere
        self._generation = 0
        #? the Navidrome these answers are about - another one (or another account) forgets them
        self._for: tuple[str, str] | None = None
        #? path -> the folder's last verdict, for a folder changed since Navidrome last scanned -
        #? merged from every read, pruned only by a real scan that found albums (prune=True)
        self._verdicts: dict[str, bool] = {}

    def forget(self) -> None:
        """Every answer dropped: the next read asks Navidrome afresh."""
        self.listing = None
        self.problem = None
        self._status = None
        self._answered = None
        self._task = None
        self._generation += 1
        self._verdicts = {}

    def _same_navidrome(self) -> bool:
        current = (Config.NAVIDROME_URL or "", Config.NAVIDROME_USER or "")
        if self._for != current:
            self.forget()
            self._for = current
        return Config.navidrome_configured()

    def check(self) -> dict:
        """What the queue says about the check: `state` listed | scanning | checking | unset | failed."""
        if not Config.navidrome_configured():
            return {"state": "unset", "problem": None}
        if self.listing is not None:
            return {"state": "listed" if self.listing.settled else "scanning", "problem": None}
        if self.problem:
            return {"state": "failed", "problem": self.problem}
        return {"state": "checking", "problem": None}

    def age(self) -> float | None:
        """Seconds since Navidrome last answered (a listing or a failure), None if never."""
        return None if self._answered is None else time.monotonic() - self._answered

    async def ask(self, due_after: float | None, wait: float | None = None, rescan: bool = False) -> dict:
        """
        Refresh the listing if it is older than `due_after` seconds (or never answered; 0 asks now,
        None never asks). Returns check(). Never raises.

        A read is NOT held for it: the answer in hand judges this read, and the refresh runs on behind
        it for the next one ("never blocking the queue"). Two exceptions, each waiting at most `wait`
        seconds: Navidrome's very FIRST answer - the one that can put a chip on the page first opened,
        since nothing reads again on its own - counted from when that refresh began, so the reads that
        come while it is out share one wait rather than each paying it; and a Rescan (`rescan`), the
        way to see the check afresh, counted from now, beside a re-read of every file. `wait` is
        LISTING_WAIT_SECONDS unless given.
        """
        wait = LISTING_WAIT_SECONDS if wait is None else wait
        if not self._same_navidrome():
            return self.check()

        age = self.age()
        if due_after is not None and (age is None or age >= due_after):
            task = self._running()
            if task is None:
                generation = self._generation
                task = asyncio.get_running_loop().create_task(self._refresh(generation))
                self._task = task
                self._began = time.monotonic()
            if rescan:
                until = time.monotonic() + wait
            elif self._answered is None:
                until = self._began + wait
            else:
                until = 0.0
            remaining = until - time.monotonic()
            if remaining > 0:
                #? shielded: a wait that ends leaves the refresh running, for the next read
                await asyncio.wait({task}, timeout=remaining)
        return self.check()

    def _running(self) -> asyncio.Task | None:
        """The refresh still out on THIS event loop (a test's client may run each request on its own)."""
        task = self._task
        if task is None or task.done():
            return None
        try:
            if task.get_loop() is not asyncio.get_running_loop():
                return None
        except RuntimeError:
            return None
        return task

    async def _call(self, endpoint: str, params: dict | None = None) -> dict:
        client = self._client or navidrome
        try:
            return await asyncio.wait_for(client.call(endpoint, params), LISTING_CALL_TIMEOUT_SECONDS)
        except TimeoutError as e:
            raise NavidromeError(f"Navidrome didn't answer within {LISTING_CALL_TIMEOUT_SECONDS:g}s",
                                 unreachable=True) from e

    async def _scan_status(self, first: bool = False) -> tuple[ScanStatus | None, float | None]:
        """
        getScanStatus read, and when the scan behind its lastScan began (scan_began) - each None when
        it can't be used or wasn't answered, and the listing goes on. But the FIRST one not reaching
        Navidrome at all (refused, timed out) ends the refresh: the album pages would only wait out
        the same timeout again.
        """
        try:
            body = await self._call("getScanStatus")
        except NavidromeError as e:
            if first and e.unreachable:
                raise
            return None, None
        status = read_status(body)
        return status, scan_began(body, status)

    async def _albums(self) -> list[dict]:
        albums: list[dict] = []
        seen: set = set()
        for page in range(LISTING_PAGES_MAX):
            body = await self._call("getAlbumList2", {
                "type": "alphabeticalByName", "size": LISTING_PAGE, "offset": page * LISTING_PAGE,
            })
            listed = body.get("albumList2") if isinstance(body.get("albumList2"), dict) else {}
            batch = [album for album in (listed.get("album") or []) if isinstance(album, dict)]
            fresh = [album for album in batch if album.get("id") not in seen]
            seen.update(album.get("id") for album in fresh)
            albums.extend(fresh)
            if len(batch) < LISTING_PAGE or not fresh:
                break
        return albums

    async def _refresh(self, generation: int) -> None:
        asked = time.time()
        try:
            before, began = await self._scan_status(first=True)
            quiet = before is not None and not before.scanning
            if (self.listing is not None and self.listing.settled and quiet and self._status == before):
                #? no scan since the last listing: Navidrome's albums are what they were - as of now,
                #? which is what a folder's grace is counted to
                listing = replace(self.listing, asked_at=asked)
            else:
                albums = await self._albums()
                after, _ = await self._scan_status()
                if before is None:
                    #? a server that won't say when it scanned: measured from now, with room
                    seen_until, settled = time.time() - LISTING_SETTLE_SECONDS, True
                else:
                    #? from when the last scan BEGAN: lastScan is written as a scan ends, and a folder
                    #? changed while it ran may have been passed before it changed
                    seen_until = began if began is not None else before.last_scan.timestamp() - LISTING_SETTLE_SECONDS
                    settled = quiet and after is not None and not after.scanning and after.last_scan == before.last_scan
                listing = build_listing(albums, seen_until, settled, asked)
            if generation != self._generation:
                return
            self.listing, self.problem, self._status = listing, None, before
        except NavidromeError as e:
            if generation != self._generation:
                return
            self.listing, self.problem, self._status = None, str(e) or type(e).__name__, None
        except Exception as e:
            #? a listing that fails must never fail the queue that asked for it
            if generation != self._generation:
                return
            self.listing, self.problem, self._status = None, f"{type(e).__name__}: {e}", None
        self._answered = time.monotonic()

    def unlisted(self, albums: list[dict], prune: bool = False) -> set[str]:
        """
        The paths of the albums Navidrome doesn't list, by the listing in hand - none without one.

        Each folder's verdict is kept for the next time it can't be judged afresh, MERGED into what
        is kept: a snapshot (the count's route, a page's first draw) lacks a folder a writer has just
        forgotten, and that folder's verdict must outlive it. Only `prune` - a real scan, that found
        albums (an empty one is far more often an unmounted volume) - lets go of the folders it
        didn't find.
        """
        listing = self.listing
        if listing is None or not Config.navidrome_configured():
            return set()
        missing: set[str] = set()
        found: set[str] = set()
        for album in albums:
            path = album.get("path") or ""
            if not path:
                continue
            found.add(path)
            #? when deadwax wrote it rides on the album (`written_at`), wherever it was read from - the
            #? disk's walk, the saved scan, or the cache loaded back after a restart
            verdict = judge(album, listing, self._verdicts.get(path))
            if verdict is None:
                continue
            self._verdicts[path] = verdict
            if verdict is False:
                missing.add(path)
        if prune and found:
            self._verdicts = {path: verdict for path, verdict in self._verdicts.items() if path in found}
        return missing

    def follow(self, source: str, target: str) -> None:
        """
        deadwax moved a folder (an apply's rename, an artist re-filed): its verdict goes with it, so a
        folder flagged before stays flagged at its new path until Navidrome has looked again - the
        new path counts as changed since (written_at, and its ctime). Paths relative to LIBRARY_PATH. A folder
        merged into one that has a verdict of its own leaves that one as it is.
        """
        if source == target:
            return
        verdict = self._verdicts.pop(source, None)
        if verdict is not None:
            self._verdicts.setdefault(target, verdict)

    def forget_folders(self) -> None:
        """Every folder's verdict dropped - LIBRARY_PATH moved, so the paths name other folders."""
        self._verdicts = {}


#? One for the process, like the Navidrome client it asks through.
navidrome_listing = NavidromeListing()
