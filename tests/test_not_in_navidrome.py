"""
"Not in Navidrome" in the review queue (2.0.0-player.46), through the whole app start() builds.

The app's library is Navidrome's, so a folder deadwax's scan holds that Navidrome doesn't list is out
of the app's reach - and the queue raises it, as an issue like any other, worked out on every response
(never stored), counted by the badge's route as the page lists it. What these pin:

  - a folder Navidrome doesn't list carries `not_in_navidrome` (with its label and hint in
    issue_types, and its facet's count in the queue); one it lists, by release id or - untagged - by
    name, doesn't; a folder named after its folder is never judged;
  - the badge (/queue/summary) counts the same albums the page lists, from the listing in hand;
  - until Navidrome has answered, nothing is raised: a snapshot asks Navidrome nothing; Navidrome unset
    or down raises nothing, and `navidrome_check` says which (for the queue to say once);
  - a folder changed since Navidrome's last scan BEGAN - filed since, filed while it ran, moved in by
    hand with its old mtime (its ctime), or written by deadwax a moment ago (an apply moves no folder
    mtime; its time saved with the scan, so a restart changes nothing) - is never newly flagged, until
    LISTING_GRACE_SECONDS pass with no scan; one flagged stays flagged through a count read in between
    and through deadwax moving it; the badge counts a written folder as the page does;
  - a real scan asks again only past LISTING_FRESH_SECONDS, a Rescan always, the count only past
    LISTING_STALE_SECONDS; a read is never held for a refresh once Navidrome has answered; an
    unchanged library is still a 304; `navidrome_check` is read with the verdicts;
  - the issue is ignored per issue, like any other.

Navidrome is httpx's MockTransport on the shared client, answering getScanStatus and getAlbumList2 -
the only two things asked. A test that needs the refresh a read leaves running to LAND serves the app
on one event loop (`served`), as uvicorn does - TestClient runs each request on a loop of its own,
which ends with it. The pure match and the cache's own rules: tests/test_navidrome_listing.py.
"""

import asyncio
import os
import shutil
import time
from functools import partial
from types import SimpleNamespace
from urllib.parse import parse_qs, urlparse

import anyio.from_thread
import httpx
import pytest
from fastapi.testclient import TestClient
from mutagen.flac import FLAC

from src import library
from src.api.app import start
from src.api.navidrome_endpoint import navidrome
from src.config import Config
from src.metadata_health import ISSUE_TYPES
from src import navidrome_listing as nl
from src.navidrome_listing import LISTING_FRESH_SECONDS, LISTING_STALE_SECONDS, navidrome_listing
from src.routes import library as route
from src.store import JobStore
from tests.test_queue_summary import ALBUMS, SUMMARY, clean_album, queue_lists, snapshot_albums, write_flac

DUMMY = "Portishead/Dummy (1994)"
THIRD = "Portishead/Third (2008)"
DUMMY_ID = "11111111-1111-4111-8111-111111111111"
THIRD_ID = "33333333-3333-4333-8333-333333333333"
OTHER_ID = "44444444-4444-4444-8444-444444444444"


def run(awaitable):
    return asyncio.run(awaitable)


def stamp(moment: float) -> str:
    """A time as Navidrome writes lastScan: RFC 3339 with nanoseconds, in UTC."""
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(moment)) + f".{int(moment % 1 * 1e6):06d}789Z"


@pytest.fixture(autouse=True)
def fresh():
    library.clear_scan_cache()
    route._cache_loaded_for = None
    navidrome_listing.forget()
    yield
    library.clear_scan_cache()
    route._cache_loaded_for = None
    navidrome_listing.forget()


@pytest.fixture
def store(tmp_path):
    job_store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    job_store.init()
    return job_store


@pytest.fixture
def root(tmp_path, monkeypatch):
    music = tmp_path / "music"
    music.mkdir()
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(music))
    return music


def configure(monkeypatch):
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")


@pytest.fixture
def navidrome_up(monkeypatch):
    """Navidrome listing `albums`; its last scan began `took` seconds before it finished at `last_scan`
    (None: a scan begun as Navidrome is first asked - after every folder the test made - and finished a
    moment later); `delay` seconds before each getAlbumList2 page; every endpoint asked kept in `asked`."""
    configure(monkeypatch)
    state = {"albums": [], "last_scan": None, "took": 0.001, "scanning": False, "down": False, "asked": [], "delay": 0}

    async def handle(request: httpx.Request) -> httpx.Response:
        endpoint = request.url.path.rsplit("/", 1)[-1]
        state["asked"].append(endpoint)
        if state["down"]:
            raise httpx.ConnectError("refused", request=request)
        q = {k: v[0] for k, v in parse_qs(urlparse(str(request.url)).query).items()}
        if endpoint == "getScanStatus":
            if state["last_scan"] is None:
                state["last_scan"] = time.time() + state["took"]
            #? elapsedTime: a Go duration, nanoseconds - lastScan less it is when the scan began
            body = {"scanStatus": {"scanning": state["scanning"], "lastScan": stamp(state["last_scan"]), "count": 3,
                                   "elapsedTime": int(state["took"] * 1e9)}}
        elif endpoint == "getAlbumList2":
            assert q["type"] == "alphabeticalByName"
            if state["delay"]:
                await asyncio.sleep(state["delay"])
            offset, size = int(q["offset"]), int(q["size"])
            body = {"albumList2": {"album": state["albums"][offset:offset + size]}}
        else:
            raise AssertionError(f"only the listing's two calls are asked, not {endpoint}")
        return httpx.Response(200, json={"subsonic-response": {"status": "ok", "version": "1.16.1", **body}})

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(handle), base_url="http://navidrome:4533/rest")
    yield state
    run(navidrome.close_client())


def nav(name, release=None, artist="Portishead"):
    entry = {"id": f"al-{name}-{release}", "name": name, "artist": artist}
    if release:
        entry["musicBrainzId"] = release
    return entry


def client(store):
    app = start()
    app.state.store = store
    return TestClient(app)


class OneLoop:
    """The app on ONE event loop for every request, as uvicorn serves it - so a refresh a read leaves
    running behind it carries on, and `landed()` waits for it."""

    def __init__(self, app, portal):
        self.portal = portal
        self.http = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://testserver")

    def get(self, url, **more):
        return self.portal.call(partial(self.http.get, url, **more))

    def post(self, url, **more):
        return self.portal.call(partial(self.http.post, url, **more))

    def landed(self):
        async def wait():
            task = navidrome_listing._task
            if task is not None and not task.done():
                await asyncio.wait({task}, timeout=10)
        self.portal.call(wait)


@pytest.fixture
def served(store):
    app = start()
    app.state.store = store
    with anyio.from_thread.start_blocking_portal() as portal:
        one = OneLoop(app, portal)
        yield one
        portal.call(one.http.aclose)


def scan(app) -> dict:
    return app.get(ALBUMS).json()


def issues_of(payload: dict) -> dict:
    return {album["path"]: album["issues"] for album in payload["albums"]}


def two_albums(root):
    clean_album(root, DUMMY, DUMMY_ID)
    clean_album(root, THIRD, THIRD_ID)


def test_a_folder_navidrome_doesnt_list_is_raised_and_one_it_lists_is_not(root, store, navidrome_up):
    two_albums(root)
    navidrome_up["albums"] = [nav("Dummy (Remastered)", DUMMY_ID)]

    payload = scan(client(store))

    assert issues_of(payload) == {DUMMY: [], THIRD: ["not_in_navidrome"]}
    assert payload["navidrome_check"] == {"state": "listed", "problem": None}
    assert payload["queue"]["by_issue"] == {"not_in_navidrome": 1}
    assert payload["issue_types"]["not_in_navidrome"] == ISSUE_TYPES["not_in_navidrome"]
    label, hint = ISSUE_TYPES["not_in_navidrome"]["label"], ISSUE_TYPES["not_in_navidrome"]["hint"]
    assert label == "Not in Navidrome"
    #? what it means, and each of the three things to do
    assert all(words in hint for words in ("can't show or play it", "scan", "read its files", "music folder"))


def test_the_badge_counts_it_as_the_page_lists_it(root, store, navidrome_up):
    two_albums(root)
    clean_album(root, "Tame Impala/Currents (2015)", OTHER_ID)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    app = client(store)
    scan(app)

    albums = snapshot_albums(app)
    answer = app.get(SUMMARY).json()

    listed = sorted(album["path"] for album in albums if queue_lists(album))
    assert listed == ["Portishead/Third (2008)", "Tame Impala/Currents (2015)"]
    assert (answer["total"], answer["needs_attention"]) == (2, 2)


def test_the_badge_asks_navidrome_when_nothing_has_yet(root, store, navidrome_up, monkeypatch):
    """The count the app shows as it starts: the saved scan, judged by Navidrome's first answer."""
    two_albums(root)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    monkeypatch.setattr(Config, "NAVIDROME_URL", "")
    app = client(store)
    scan(app)  #? the saved scan, made while Navidrome wasn't set up
    configure(monkeypatch)

    assert app.get(SUMMARY).json()["total"] == 1
    assert navidrome_up["asked"] == ["getScanStatus", "getAlbumList2", "getScanStatus"]


def test_a_snapshot_asks_navidrome_nothing_and_raises_nothing_until_it_has_answered(root, store, navidrome_up, monkeypatch):
    two_albums(root)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    monkeypatch.setattr(Config, "NAVIDROME_URL", "")
    app = client(store)
    scan(app)
    configure(monkeypatch)

    payload = app.get(ALBUMS, params={"snapshot": "true"}).json()

    assert navidrome_up["asked"] == [], "a snapshot never asks"
    assert payload["navidrome_check"] == {"state": "checking", "problem": None}
    assert issues_of(payload) == {DUMMY: [], THIRD: []}, "nothing until Navidrome has answered"

    assert issues_of(scan(app))[THIRD] == ["not_in_navidrome"], "the real scan behind it asks"


def test_navidrome_unset_raises_nothing_and_says_so(root, store):
    two_albums(root)
    payload = scan(client(store))
    assert issues_of(payload) == {DUMMY: [], THIRD: []}
    assert payload["navidrome_check"] == {"state": "unset", "problem": None}


def test_navidrome_down_raises_nothing_and_says_why(root, store, navidrome_up):
    two_albums(root)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    app = client(store)
    assert issues_of(scan(app))[THIRD] == ["not_in_navidrome"]

    navidrome_up["down"] = True
    payload = app.post("/deadwax/library/rescan").json()

    assert issues_of(payload) == {DUMMY: [], THIRD: []}
    assert payload["navidrome_check"]["state"] == "failed"
    assert "Navidrome couldn't be reached at http://navidrome:4533" in payload["navidrome_check"]["problem"]
    assert app.get(SUMMARY).json()["total"] == 0


def test_an_untagged_rip_is_matched_by_name_and_one_named_after_its_folder_never_judged(root, store, navidrome_up):
    for name, album in (("Old Rips/dummy", "Dummy"), ("Old Rips/roseland", "Roseland NYC Live")):
        for n in (1, 2):
            write_flac(root / name / f"{n:02d}.flac", album=album, artist="Portishead", title=f"T{n}", tracknumber=str(n))
    for n in (1, 2):
        write_flac(root / "Old Rips" / "nameless" / f"{n:02d}.flac", artist="Portishead", title=f"T{n}", tracknumber=str(n))
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]

    issues = issues_of(scan(client(store)))

    assert "not_in_navidrome" not in issues["Old Rips/dummy"], "Navidrome has an album of that name, by them"
    assert "not_in_navidrome" in issues["Old Rips/roseland"]
    assert "not_in_navidrome" not in issues["Old Rips/nameless"], "no album tag: nothing to look for"


def test_a_folder_filed_since_navidromes_last_scan_is_not_raised(root, store, navidrome_up):
    two_albums(root)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    navidrome_up["last_scan"] = time.time() - 3600

    payload = scan(client(store))

    assert issues_of(payload) == {DUMMY: [], THIRD: []}, "Navidrome hasn't scanned since they arrived"
    assert payload["navidrome_check"]["state"] == "listed"


def retag_in_place(directory, release):
    """An apply's tags written in place, as mutagen saves them: the folder's own mtime and ctime don't
    move - only deadwax's word (forget_cached_album) says it changed."""
    before = directory.stat()
    for track in sorted(directory.glob("*.flac")):
        audio = FLAC(str(track))
        audio["musicbrainz_albumid"] = release
        audio.save()
    after = directory.stat()
    assert (after.st_mtime, after.st_ctime) == (before.st_mtime, before.st_ctime)
    library.forget_cached_album(str(directory))  #? what every writer does once its files are written


def test_an_album_deadwax_wrote_a_moment_ago_is_never_newly_flagged(root, store, navidrome_up):
    """An apply's new release id, before Navidrome's watcher has scanned it: Navidrome still has the old one."""
    directory = clean_album(root, DUMMY, DUMMY_ID)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    navidrome_up["last_scan"] = time.time() + 1
    app = client(store)
    assert issues_of(scan(app))[DUMMY] == []

    time.sleep(1.1)  #? past the lastScan Navidrome says, so the write is after it
    retag_in_place(directory, OTHER_ID)
    navidrome_listing._answered -= LISTING_FRESH_SECONDS

    payload = scan(app)

    assert next(a for a in payload["albums"] if a["path"] == DUMMY)["release_mbid"] == OTHER_ID
    assert issues_of(payload)[DUMMY] == [], "listed before, and Navidrome hasn't looked since"


def restart():
    """deadwax restarted: the scan cache, the write times and the verdicts in memory gone - the saved
    scan loaded back on the next read."""
    library.clear_scan_cache()
    library._behind = True
    route._cache_loaded_for = None
    navidrome_listing.forget()


def test_a_restart_doesnt_flag_an_album_deadwax_wrote_before_navidrome_looked(root, store, navidrome_up):
    """The write time is saved with the scan (written_at), so the verdict doesn't hang on a restart -
    a Komodo redeploy inside the seconds before Navidrome's watcher scans an apply."""
    directory = clean_album(root, DUMMY, DUMMY_ID)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    navidrome_up["last_scan"] = time.time() + 1
    assert issues_of(scan(client(store)))[DUMMY] == []
    time.sleep(1.1)
    retag_in_place(directory, OTHER_ID)
    assert issues_of(scan(client(store)))[DUMMY] == [], "the scan that reads the new tags, saved"

    restart()
    app = client(store)
    assert issues_of(app.get(ALBUMS, params={"snapshot": "true"}).json())[DUMMY] == []
    payload = scan(app)

    assert payload["navidrome_check"]["state"] == "listed"
    assert issues_of(payload)[DUMMY] == [], "Navidrome still has the old id, and hasn't looked since the write"
    assert app.get(SUMMARY).json()["total"] == 0


def test_a_folder_moved_in_by_hand_is_not_flagged_before_navidrome_has_scanned_it(root, store, navidrome_up, tmp_path):
    """mv (or cp -a, rsync -a, an unzip) keeps the folder's old mtime: when it ARRIVED is its ctime."""
    clean_album(root, DUMMY, DUMMY_ID)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    navidrome_up["last_scan"] = time.time() - 600
    downloaded = clean_album(tmp_path / "downloads", THIRD, THIRD_ID)
    hour_ago = time.time() - 3600
    os.utime(downloaded, (hour_ago, hour_ago))
    os.rename(downloaded, root / THIRD)
    assert (root / THIRD).stat().st_mtime == pytest.approx(hour_ago, abs=1)

    payload = scan(client(store))

    assert issues_of(payload) == {DUMMY: [], THIRD: []}, "Navidrome's last scan began before it came"


def test_a_folder_no_scan_comes_for_is_flagged_once_its_grace_is_over(root, store, navidrome_up, monkeypatch):
    """Filed outside Navidrome's music folder, its watcher never wakes and lastScan never moves: past
    LISTING_GRACE_SECONDS from the change (here a second), the folder is judged anyway."""
    monkeypatch.setattr(nl, "LISTING_GRACE_SECONDS", 1.0)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    navidrome_up["last_scan"] = time.time() - 3600
    two_albums(root)

    assert issues_of(scan(client(store)))[THIRD] == [], "a moment after it was filed: Navidrome may be about to scan"
    time.sleep(1.2)
    navidrome_listing._answered -= LISTING_FRESH_SECONDS
    app = client(store)
    scan(app)  #? the read that asks again (no scan since: one call), judged by the answer in hand
    payload = scan(app)

    assert issues_of(payload) == {DUMMY: [], THIRD: ["not_in_navidrome"]}, "no scan came: Navidrome can't see it"
    assert app.get(SUMMARY).json()["total"] == 1


def test_the_badge_counts_an_album_deadwax_wrote_as_the_page_does(root, store, navidrome_up, monkeypatch):
    """A folder never judged (Navidrome unset until now), written by deadwax in place before Navidrome's
    last scan is known: the page's scan reads when, and the count - from the saved scan - knows it too."""
    two_albums(root)
    monkeypatch.setattr(Config, "NAVIDROME_URL", "")
    app = client(store)
    scan(app)
    time.sleep(0.05)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    navidrome_up["last_scan"] = time.time()  #? after the folders came, before the write
    time.sleep(0.05)
    retag_in_place(root / THIRD, THIRD_ID)
    configure(monkeypatch)

    payload = scan(app)
    answer = app.get(SUMMARY).json()

    assert issues_of(payload) == {DUMMY: [], THIRD: []}, "written after Navidrome's last scan: not judged"
    assert (answer["total"], answer["needs_attention"]) == (0, 0), "the badge = the page"
    assert THIRD not in navidrome_listing._verdicts, "nor judged by the count"


def test_a_real_scan_asks_again_only_past_its_freshness_and_a_rescan_always(root, store, navidrome_up, served):
    two_albums(root)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    scan(served)
    asked = len(navidrome_up["asked"])

    scan(served)
    served.landed()
    assert len(navidrome_up["asked"]) == asked, "answered a moment ago"

    navidrome_listing._answered -= LISTING_FRESH_SECONDS
    scan(served)
    served.landed()
    assert navidrome_up["asked"][asked:] == ["getScanStatus"], "past its freshness: asked again - one call, with no scan since"

    asked = len(navidrome_up["asked"])
    served.post("/deadwax/library/rescan")
    assert navidrome_up["asked"][asked:] == ["getScanStatus"], "a Rescan asks, answered a moment ago or not"


def test_an_unchanged_library_is_still_a_304(root, store, navidrome_up, served):
    two_albums(root)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    scan(served)  #? the first scan enrols the albums (first_seen), which the next answer carries
    first = served.get(ALBUMS)
    navidrome_listing._answered -= LISTING_FRESH_SECONDS
    asked = len(navidrome_up["asked"])

    served.get(ALBUMS)
    served.landed()
    again = served.get(ALBUMS, headers={"If-None-Match": first.headers["etag"]})

    assert len(navidrome_up["asked"]) > asked, "Navidrome was asked again"
    assert again.status_code == 304, "...its answer the same: the same body"
    assert first.json()["navidrome_check"] == {"state": "listed", "problem": None}


def test_it_is_ignored_per_issue_like_any_other(root, store, navidrome_up):
    two_albums(root)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    app = client(store)
    scan(app)

    response = app.post("/deadwax/library/queue/ignore", json={"album_path": THIRD, "issues": ["not_in_navidrome"]})
    assert response.status_code == 200

    third = next(album for album in scan(app)["albums"] if album["path"] == THIRD)
    assert (third["issues"], third["ignored_issues"], third["needs_attention"]) == (["not_in_navidrome"], ["not_in_navidrome"], False)
    assert app.get(SUMMARY).json()["total"] == 0


def test_the_badge_asks_navidrome_again_only_past_five_minutes(root, store, navidrome_up, served):
    """The count's route is asked on every frame shown, filing and review mark: it must stay cheap."""
    two_albums(root)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    scan(served)
    asked = len(navidrome_up["asked"])

    assert served.get(SUMMARY).json()["total"] == 1
    navidrome_listing._answered -= 60  #? past a real scan's freshness, well inside the count's
    assert served.get(SUMMARY).json()["total"] == 1
    served.landed()
    assert len(navidrome_up["asked"]) == asked, "an answer under five minutes old does"

    navidrome_listing._answered -= LISTING_STALE_SECONDS
    served.get(SUMMARY)
    served.landed()
    assert navidrome_up["asked"][asked:] == ["getScanStatus"]


def test_once_navidrome_has_answered_a_read_is_never_held_for_it(root, store, navidrome_up, served):
    """"Never blocking the queue": Navidrome scanned since and is slow to list its albums - the read is
    judged by the answer in hand, and the next one by the new answer."""
    two_albums(root)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    assert issues_of(scan(served))[THIRD] == ["not_in_navidrome"]

    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID), nav("Third", THIRD_ID)]
    navidrome_up["last_scan"] = time.time()
    navidrome_up["delay"] = 1.5
    navidrome_listing._answered -= LISTING_FRESH_SECONDS

    started = time.monotonic()
    payload = scan(served)
    assert time.monotonic() - started < 1.0, "not held for the refresh"
    assert issues_of(payload)[THIRD] == ["not_in_navidrome"], "judged by the answer in hand"
    assert payload["navidrome_check"] == {"state": "listed", "problem": None}
    #? the count's own due: past five minutes, it joins the refresh still out - and isn't held for it
    navidrome_listing._answered -= LISTING_STALE_SECONDS
    started = time.monotonic()
    assert served.get(SUMMARY).json()["total"] == 1
    assert time.monotonic() - started < 1.0, "nor is the count"

    served.landed()
    assert issues_of(scan(served))[THIRD] == [], "the next read, by the new answer"


def test_a_rescan_waits_for_navidromes_answer(root, store, navidrome_up):
    """The way to see the check afresh: Navidrome has scanned and lists Third now, slowly - a Rescan's
    answer is its new one, where an ordinary read would be judged by the old."""
    two_albums(root)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    app = client(store)
    assert issues_of(scan(app))[THIRD] == ["not_in_navidrome"]

    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID), nav("Third", THIRD_ID)]
    navidrome_up["last_scan"] = time.time()
    navidrome_up["delay"] = 0.5

    assert issues_of(app.post("/deadwax/library/rescan").json())[THIRD] == []


def test_the_check_is_said_as_the_verdicts_were_made(root, store, navidrome_up, monkeypatch):
    """Navidrome's first answer comes after its wait has ended but before the disk's walk has: the
    body says what the chips were judged by, never "hasn't answered" over albums marked."""
    two_albums(root)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    navidrome_up["delay"] = 0.2
    monkeypatch.setattr(nl, "LISTING_WAIT_SECONDS", 0.05)
    walk = route.scan_library

    def slow_walk(*args):
        time.sleep(0.6)
        return walk(*args)

    monkeypatch.setattr(route, "scan_library", slow_walk)
    payload = scan(client(store))

    assert issues_of(payload)[THIRD] == ["not_in_navidrome"]
    assert payload["navidrome_check"] == {"state": "listed", "problem": None}


def test_a_folder_filed_while_navidrome_scanned_is_not_raised(root, store, navidrome_up):
    """lastScan is when a scan ENDED: a folder filed while it ran may have been passed before it came."""
    clean_album(root, DUMMY, DUMMY_ID)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    began = time.time()
    clean_album(root, THIRD, THIRD_ID)
    time.sleep(0.05)
    navidrome_up["last_scan"], navidrome_up["took"] = time.time(), time.time() - began + 0.01

    payload = scan(client(store))

    assert issues_of(payload) == {DUMMY: [], THIRD: []}, "the scan that just ended began before it was filed"
    assert payload["navidrome_check"]["state"] == "listed"


def flagged_and_written(root, store, navidrome_up, served):
    two_albums(root)
    navidrome_up["albums"] = [nav("Dummy", DUMMY_ID)]
    assert issues_of(scan(served))[THIRD] == ["not_in_navidrome"]
    #? deadwax writes it - a cover, a tag, an apply's tags before its pause - after Navidrome's last scan
    library.forget_cached_album(str(root / THIRD))
    assert library.written_at(str(root / THIRD)) > navidrome_listing.listing.seen_until


def test_a_flagged_folder_stays_flagged_through_a_count_read_before_the_next_scan(root, store, navidrome_up, served):
    """The two-step apply forgets the folder before its pause; the page shown again asks the count, from
    the saved scan - which lacks the folder - before the panel's scan."""
    flagged_and_written(root, store, navidrome_up, served)

    served.get(SUMMARY)  #? the saved scan without the folder: not counted, nor judged, just now
    assert THIRD not in issues_of(served.get(ALBUMS, params={"snapshot": "true"}).json())
    navidrome_listing._answered -= LISTING_FRESH_SECONDS
    scan(served)
    served.landed()

    assert issues_of(scan(served))[THIRD] == ["not_in_navidrome"], "Navidrome hasn't looked since: still flagged"
    assert served.get(SUMMARY).json()["total"] == 1


def test_a_flagged_folder_deadwax_moves_stays_flagged_at_its_new_path(root, store, navidrome_up, served):
    flagged_and_written(root, store, navidrome_up, served)
    moved = "Portishead/Third (2008) [Deluxe]"
    shutil.move(str(root / THIRD), str(root / moved))
    library.forget_cached_album(str(root / moved))
    route._follow_verdict(str(root / THIRD), str(root / moved))

    assert issues_of(scan(served)) == {DUMMY: [], moved: ["not_in_navidrome"]}


def test_an_apply_that_renames_carries_the_verdict(tmp_path, monkeypatch):
    from tests.test_retag import RELEASE, seed

    seed(tmp_path)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", "0")
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    navidrome_listing._verdicts["Tame Impala/The Slow Rush (2020)"] = False

    response = TestClient(start()).post("/deadwax/library/retag/apply",
                                        json={"album_path": "Tame Impala/The Slow Rush (2020)", "release": RELEASE})

    assert response.json()["results"]["moved_to"] == str(tmp_path / "Tame Impala/The Slow Rush (2020) [Deluxe edition]")
    assert navidrome_listing._verdicts == {"Tame Impala/The Slow Rush (2020) [Deluxe edition]": False}


def test_an_artist_refiled_carries_its_verdicts(root, store, navidrome_up):
    from tests.test_artist_refile import album as refile_album

    refile_album(root, "Kanye West", "Donda (2021)", "Kanye West")
    assert "not_in_navidrome" in issues_of(scan(client(store)))["Kanye West/Donda (2021)"]

    class MusicBrainz:
        async def get_artist(self, mbid):
            return {"id": mbid, "name": "Ye", "aliases": []}

    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(musicbrainz_client=MusicBrainz(), store=store)))
    run(route.artist_refile_apply(request, route.ArtistRefileRequest(artist="Kanye West")))

    assert navidrome_listing._verdicts == {"Ye/Donda (2021)": False}
    issues = issues_of(scan(client(store)))
    assert list(issues) == ["Ye/Donda (2021)"] and "not_in_navidrome" in issues["Ye/Donda (2021)"], "Navidrome hasn't looked since"
