"""
Personal libraries (2.0.0-player.51, step 5 of the multi-user plan) - store.py's library_membership,
user_credentials, library_flags, library_seed and store_index_scanned; src/library_ledger.py; src/stars.py;
the poller's grants; routes/my_library.py and routes/held.py; the writers keeping it true - through the whole
app start() builds (no lifespan), a real SQLite store, real tagged files where the disk decides, the real
organizer, and a fake Navidrome that checks Subsonic token auth for james (the admin), ethan and sam and keeps
EACH USER'S STARS apart, as Navidrome does (search3 by release id, star, unstar, getAlbum's `starred`,
getStarred2).

What these hold (every rule decided with James on 2026-09-27):

  - Grants on every way a download ends, to each requester still waiting: filed - added; every file already
    there - added in the same release's folder (a second copy not filed beside the first), flagged for the
    admin in an untagged one; some files failed - added, incomplete; a dry run, nothing filed - nothing.
  - Starred AS THE USER once Navidrome has it (search3 by release id, star, confirmed by getAlbum's starred;
    `star` answering OK proves nothing), retried with a growing wait; never NAVIDROME_USER's login. A
    credential Navidrome refuses dies - the albums wait, the library says "sign in again" - and a new
    sign-in brings it back.
  - Two-way with Amperfy: starred elsewhere is added, unstarred removed - but a star LOST (the album missing
    from Navidrome mid-retag, back under another id, or being applied to now) is put back, not removed.
    Albums only.
  - Seeding: the store into the first admin's library once (at the sign-in or the take-over), seen; never
    a user's, never twice, never what somebody else's download brought (what they starred or added is in
    both libraries). Albums nobody asked for are held by nobody.
  - Writers: a merge unions the holders; a re-file keeps them; a delete turns them into tombstones the
    holders see and can put away, and the dialog names them; an apply re-stars it for everyone.
  - Add to my library, the store line's `yours`, the new marker, held by nobody and the flags, the row's
    `library`, the next peer for a download nothing of could be filed.
  - With logins off nothing visible changes: local's library is kept silently, nothing is starred.
"""

import asyncio
import hashlib
import logging
import shutil
import sqlite3
import time
from types import SimpleNamespace
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from src import auth, library, library_ledger, organizer, poller, stars
from src.api.app import start
from src.config import Config
from src.library_ledger import ADDED, FLAGGED, INCOMPLETE, grant_for
from src.poller import poll_downloads_once
from src.routes import library as library_routes
from src.routes.store_album import forget_navidrome_ids
from src.store import JobStore
from src.store_index import index_folder
from src.users import LOCAL_USER
from tests.test_library import write_flac
from tests.test_logins import GLASS, LOGIN, PASSWORDS, SECRET

NAVIDROME = "http://navidrome:4533"
SAM_PASSWORD = "sam-navidrome-pw"
LIBRARY = "/deadwax/me/library"
HELD = "/deadwax/library/held"
JOBS = "/deadwax/download/jobs"
STORE_STATE = "/deadwax/download/store_state"
DUMMY = "Portishead/Dummy (1994)"
THIRD = "Portishead/Third (2008)"
FOLDER = "Boards of Canada/Music Has the Right to Children (1998)"
FILES = [{"filename": "share/album/01.flac", "size": 1}, {"filename": "share/album/02.flac", "size": 1}]
FILED_RELEASE = {"artist": "Boards of Canada", "album": "Music Has the Right to Children", "year": "1998",
                 "release_mbid": "mb-1", "tracks": []}


def run(coroutine):
    return asyncio.run(coroutine)


def ok(**body) -> dict:
    return {"subsonic-response": {"status": "ok", "version": "1.16.1", "type": "navidrome", **body}}


def failed(code: int, message: str) -> dict:
    return {"subsonic-response": {"status": "failed", "version": "1.16.1", "error": {"code": code, "message": message}}}


class Navidrome:
    """
    getUser, and the library as starring uses it: search3 (a query that IS an album's release id finds it,
    as Navidrome matches MusicBrainz ids; else every word in its name), star / unstar (OK for any id, known
    or not - as Navidrome), getAlbum (its `starred` only for the user asking), getStarred2 (that user's
    albums, songs and artists). Token auth checked for real; every call kept, with who made it.
    """

    def __init__(self):
        self.passwords = {**PASSWORDS, "sam": SAM_PASSWORD, "demo": "demo-pw"}
        self.albums: dict[str, dict] = {}
        self.stars: dict[str, set[str]] = {}
        self.song_stars: dict[str, list[dict]] = {}
        self.calls: list[tuple[str, str, dict]] = []
        self.down = False
        #? False: `star` answers OK and keeps nothing - what an id it doesn't know gets
        self.keeps_stars = True
        #? False: search3 doesn't match a MusicBrainz id - only the words of an album's name (a Navidrome
        #? that can't search ids: the title is then what finds it)
        self.mbid_search = True
        #? (user, endpoint) -> the answer given instead: an error Navidrome answers one user with
        self.errors: dict[tuple[str, str], httpx.Response] = {}

    def add(self, album_id: str, release: str, name: str = "Dummy", artist: str = "Portishead") -> None:
        self.albums[album_id] = {"id": album_id, "name": name, "artist": artist, "musicBrainzId": release}

    def starred(self, user: str) -> set[str]:
        return self.stars.setdefault(user, set())

    def asked(self, endpoint: str) -> list[tuple[str, dict]]:
        return [(user, q) for user, called, q in self.calls if called == endpoint]

    def handle(self, request: httpx.Request) -> httpx.Response:
        q = {key: values[0] for key, values in parse_qs(urlparse(str(request.url)).query).items()}
        endpoint = request.url.path.removeprefix("/rest/")
        user = q.get("u", "").lower()
        self.calls.append((user, endpoint, q))
        if self.down:
            raise httpx.ConnectError("connection refused")
        assert "p" not in q, "a password was sent - deadwax should only send tokens"
        token = hashlib.md5((self.passwords.get(user, "") + q.get("s", "")).encode()).hexdigest()
        if user not in self.passwords or q.get("t") != token:
            return httpx.Response(200, json=failed(40, "Wrong username or password"))
        if (user, endpoint) in self.errors:
            return self.errors[(user, endpoint)]
        if endpoint == "getUser":
            return httpx.Response(200, json=ok(user={"username": user, "adminRole": False}))
        if endpoint == "search3":
            asked = q.get("query", "")
            words = asked.lower().split()
            found = [album for album in self.albums.values()
                     if (self.mbid_search and album["musicBrainzId"] == asked)
                     or (words and all(w in album["name"].lower() for w in words))]
            return httpx.Response(200, json=ok(searchResult3={"album": found, "artist": [], "song": []}))
        if endpoint == "star":
            if self.keeps_stars and q.get("albumId"):
                self.starred(user).add(q["albumId"])
            return httpx.Response(200, json=ok())
        if endpoint == "unstar":
            self.starred(user).discard(q.get("albumId"))
            return httpx.Response(200, json=ok())
        if endpoint == "getAlbum":
            album = self.albums.get(q.get("id", ""))
            if album is None:
                return httpx.Response(200, json=failed(70, "Album not found"))
            body = dict(album)
            if album["id"] in self.starred(user):
                body["starred"] = "2026-10-15T09:00:00.000Z"
            return httpx.Response(200, json=ok(album=body))
        if endpoint == "getStarred2":
            listed = [{**self.albums[i], "starred": "2026-10-15T09:00:00.000Z"} for i in sorted(self.starred(user)) if i in self.albums]
            return httpx.Response(200, json=ok(starred2={"album": listed, "song": self.song_stars.get(user, []), "artist": []}))
        return httpx.Response(200, json=failed(0, f"not faked: {endpoint}"))


class Slskd:
    """slskd as filing reads it: every transfer of `peers` done."""

    def __init__(self, *peers: str):
        self.peers = peers

    async def get_downloads(self, usernames=()):
        return [{"username": name, "directories": [{"files": [
            {"filename": f["filename"], "state": "Completed, Succeeded", "percentComplete": 100} for f in FILES]}]}
            for name in self.peers if name in set(usernames)]

    async def enqueue(self, username, files):
        return True, ""

    async def cancel_download(self, *args, **kwargs):
        return True

    async def queue_position(self, *args):
        return None


def wire(fake: Navidrome) -> None:
    for client in (auth.login_client, stars.star_client):
        client.client = httpx.AsyncClient(transport=httpx.MockTransport(fake.handle), base_url=f"{NAVIDROME}/rest")
        client.base = f"{NAVIDROME}/rest"


@pytest.fixture
def on(monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "AUTH_MODE", "on")
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", SECRET)
    monkeypatch.setattr(Config, "DEADWAX_ADMINS", "james")
    monkeypatch.setattr(Config, "DEADWAX_ADMIN_PASSWORD", GLASS)
    monkeypatch.setattr(Config, "NAVIDROME_URL", NAVIDROME)
    #? the player's shared login - which no star is ever made with
    monkeypatch.setattr(Config, "NAVIDROME_USER", "demo")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "demo-pw")
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "copy")
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "downloads"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "library"))
    monkeypatch.setattr(Config, "SLSKD_INCOMPLETE_PATH", None)
    monkeypatch.setattr(Config, "AUTO_RETRY_PEER", "off")
    monkeypatch.setattr(Config, "FETCH_LYRICS", "off")
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", "0")
    monkeypatch.setattr(auth, "throttle", auth.Throttle())
    monkeypatch.setattr(library_ledger, "_RETAGGING", {})
    library.clear_scan_cache()
    library_routes._cache_loaded_for = None
    auth.forget_sessions()
    stars.forget_syncs()
    forget_navidrome_ids()
    (tmp_path / "library").mkdir()
    fake = Navidrome()
    wire(fake)
    store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    store.init()
    #? a library deadwax has scanned - the store index knows it, so seeding needn't wait for a scan (a test
    #? of the wait takes this away: unscanned())
    with sqlite3.connect(tmp_path / "state" / "deadwax.db") as connection:
        connection.execute("INSERT INTO store_index_scanned (root, scanned_at) VALUES (?, 'then')",
                           (str(tmp_path / "library"),))
    app = start()
    app.state.store = store
    app.state.slskd_client = Slskd()
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    yield SimpleNamespace(app=app, store=store, fake=fake, tmp=tmp_path, root=str(tmp_path / "library"),
                          path=tmp_path / "state" / "deadwax.db")
    auth.forget_sessions()
    library.clear_scan_cache()
    library_routes._cache_loaded_for = None
    run(auth.login_client.close_client())
    run(stars.star_client.close_client())


def password_of(name: str) -> str:
    return SAM_PASSWORD if name == "sam" else PASSWORDS[name]


def signed_in(on, name: str) -> TestClient:
    client = TestClient(on.app)
    password = GLASS if name == auth.BREAK_GLASS_USER else password_of(name)
    assert client.post(LOGIN, json={"username": name, "password": password}).status_code == 200
    return client


def entries(on, user: str | None = None) -> dict:
    """Every ledger entry, keyed (user, album_id) - or one user's, keyed on album_id."""
    with sqlite3.connect(on.path) as connection:
        connection.row_factory = sqlite3.Row
        found = [dict(row) for row in connection.execute("SELECT * FROM library_membership")]
    if user is None:
        return {(row["user"], row["album_id"]): row for row in found}
    return {row["album_id"]: row for row in found if row["user"] == user}


def held(on, folder=DUMMY, release="rel-dummy", tracks=2, tagged=True) -> int:
    """An album folder in the store, indexed - its store_album id."""
    directory = on.tmp / "library" / folder
    for n in range(1, tracks + 1):
        tags = {"album": folder.split("/")[1].split(" (")[0], "albumartist": folder.split("/")[0],
                "artist": folder.split("/")[0], "title": f"Track {n}", "tracknumber": str(n), "date": "1994"}
        if tagged:
            tags["musicbrainz_albumid"] = release
        write_flac(directory / f"{n:02d} - Track {n}.flac", **tags)
    return run(index_folder(on.store, on.root, directory))


def release_body(release="rel-dummy", tracks=2, album="Dummy", artist="Portishead") -> dict:
    return {"artist": artist, "album": album, "year": "1994", "release_mbid": release,
            "tracks": [{"position": n, "title": f"Track {n}"} for n in range(1, tracks + 1)]}


def downloads(on) -> None:
    for n in (1, 2):
        write_flac(on.tmp / "downloads" / "album" / f"0{n}.flac", title=f"Track {n}", tracknumber=str(n))


def job(on, *users: str, peer: str = "bob") -> int:
    """A download asked for by `users` (the first made it, the rest joined), its files in slskd's folder."""
    job_id = run(on.store.create_job(peer, "share/album", FILES, FILED_RELEASE, user=users[0]))
    for user in users[1:]:
        assert run(on.store.request_job(job_id, user)) == "joined"
    return job_id


def file_it(on, peer: str = "bob") -> None:
    run(poll_downloads_once(Slskd(peer), on.store, {}))


def work(on, now: float | None = None, sync: bool = True) -> dict:
    if sync:
        stars.forget_syncs()
    return run(stars.work_once(on.store, now))


def grant(on, users, album_id, how=library_ledger.GRABBED, incomplete=False):
    assert run(on.store.grant_albums(list(users), [album_id], how, incomplete=incomplete))


def credential(on, user: str) -> dict | None:
    return on.store.credential_row(user)


# ================================================================ the rules, pure

@pytest.mark.parametrize("results, same, given", [
    ({"organized": 2, "tracks_organized": 2, "skipped": 0, "failed": 0}, False, ADDED),
    #? nothing new, every file already in the folder - the same release's: a second copy, not filed beside it
    ({"organized": 0, "skipped": 2, "duplicates": 2, "failed": 0}, True, ADDED),
    #? ...in an untagged folder, or another pressing's: nobody's to be given on a guess
    ({"organized": 0, "skipped": 2, "duplicates": 2, "failed": 0}, False, FLAGGED),
    ({"organized": 1, "tracks_organized": 1, "skipped": 0, "failed": 1}, True, INCOMPLETE),
    #? some failed and no TRACK landed (a cover alone): nothing
    ({"organized": 1, "tracks_organized": 0, "skipped": 0, "failed": 1}, True, None),
    #? nothing placed, nothing there: nothing could be filed
    ({"organized": 0, "skipped": 0, "failed": 0}, True, None),
    ({"organized": 2, "tracks_organized": 2, "skipped": 0, "failed": 0, "dry_run": True}, True, None),
    (None, True, None),
])
def test_what_each_way_a_download_ends_gives(results, same, given):
    assert grant_for(results, same) == given


def test_a_waiting_star_is_tried_again_sooner_then_later_and_for_ever():
    assert [library_ledger.retry_after(n) for n in (1, 2, 3, 6, 7, 50)] == [30, 60, 120, 960, 1800, 1800]


# ================================================================ grants from a filing

def test_a_filed_download_goes_into_the_library_of_everyone_still_waiting_for_it(on):
    downloads(on)
    job_id = job(on, "ethan", "james", "sam")
    assert run(on.store.leave_job(job_id, "sam")) == "left"

    file_it(on)

    [album] = [row for row in run(on.store.index_present(on.root, "mb-1"))]
    assert album["path"] == FOLDER
    got = entries(on)
    assert set(got) == {("ethan", album["id"]), ("james", album["id"])}
    for entry in got.values():
        assert (entry["how"], entry["state"], entry["incomplete"], entry["seen_at"]) == ("grabbed", "waiting", 0, None)
    stored = run(on.store.get_job(job_id))
    assert (stored["status"], stored["album_id"], stored["library_grant"]) == ("organized", album["id"], "added")


def test_a_second_copy_of_a_release_held_is_not_filed_and_is_given(on):
    downloads(on)
    job(on, "james")
    file_it(on)
    [album] = run(on.store.index_present(on.root, "mb-1"))
    second = job(on, "ethan", peer="carol")

    file_it(on, "carol")

    stored = run(on.store.get_job(second))
    assert stored["error"].startswith("already in the store: all 2 track(s) were already there")
    assert stored["library_grant"] == "added"
    assert entries(on, "ethan")[album["id"]]["how"] == "grabbed"
    #? two files, not four: nothing filed beside the first copy
    assert sorted(p.name for p in (on.tmp / "library" / FOLDER).iterdir()) == ["01.flac", "02.flac"]


def test_everything_already_in_an_untagged_folder_is_flagged_for_the_admin_and_given_to_nobody(on):
    downloads(on)
    untagged = held(on, FOLDER, tagged=False)
    job_id = job(on, "ethan", "sam")

    file_it(on)

    assert entries(on) == {}
    stored = run(on.store.get_job(job_id))
    assert (stored["album_id"], stored["library_grant"]) == (untagged, "flagged")
    [flag] = run(on.store.flags_open())
    assert (flag["album_id"], flag["job_id"], flag["users"], flag["path"]) == (untagged, job_id, ["ethan", "sam"], FOLDER)


def test_some_files_failing_to_file_still_gives_it_marked_incomplete(on, monkeypatch):
    downloads(on)
    real_copy = shutil.copy2

    def copy2(source, target, *args, **kwargs):
        if str(source).endswith("02.flac"):
            raise OSError(28, "No space left on device")
        return real_copy(source, target, *args, **kwargs)

    monkeypatch.setattr(organizer.shutil, "copy2", copy2)
    job_id = job(on, "ethan")
    file_it(on)

    [entry] = entries(on, "ethan").values()
    assert (entry["state"], entry["incomplete"]) == ("waiting", 1)
    assert run(on.store.get_job(job_id))["library_grant"] == "incomplete"


@pytest.mark.parametrize("mode_or_problem", ["dry_run", "nothing", "no track"])
def test_a_dry_run_or_nothing_filed_gives_nothing(on, monkeypatch, mode_or_problem):
    downloads(on)
    if mode_or_problem == "dry_run":
        monkeypatch.setattr(Config, "ORGANIZE_MODE", "dry_run")
    elif mode_or_problem == "nothing":
        monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(on.tmp / "elsewhere"))
    else:
        monkeypatch.setattr(organizer.shutil, "copy2", lambda *a, **k: (_ for _ in ()).throw(OSError(13, "denied")))
    job_id = job(on, "ethan")
    file_it(on)
    assert entries(on) == {}
    assert run(on.store.get_job(job_id))["library_grant"] is None


def test_the_row_says_what_its_filing_gave_with_logins_on_only(on, monkeypatch):
    downloads(on)
    ethan = signed_in(on, "ethan")
    job(on, "ethan")
    file_it(on)
    [row] = ethan.get(JOBS).json()["jobs"]
    assert (row["outcome"], row["library"]) == ("filed", "added")
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    [row] = TestClient(on.app).get(JOBS).json()["jobs"]
    assert "library" not in row


# ================================================================ starred as you

def test_an_album_is_starred_as_its_user_found_by_release_and_confirmed(on):
    album = held(on)
    on.fake.add("nd-dummy", "rel-dummy")
    signed_in(on, "ethan")
    grant(on, ["ethan"], album)

    done = work(on)

    assert done["starred"] == 1
    entry = entries(on, "ethan")[album]
    assert (entry["state"], entry["navidrome_id"], entry["problem"]) == ("starred", "nd-dummy", None)
    assert on.fake.starred("ethan") == {"nd-dummy"}
    #? found by its release id, starred, then confirmed - every call as ethan, none with the shared login
    asked = [(user, endpoint) for user, endpoint, _ in on.fake.calls if endpoint in ("search3", "star", "getAlbum")]
    assert asked == [("ethan", "search3"), ("ethan", "star"), ("ethan", "getAlbum")]
    assert on.fake.asked("search3")[0][1]["query"] == "rel-dummy"
    assert "demo" not in {user for user, _, _ in on.fake.calls}


def test_a_star_navidrome_answers_ok_to_but_doesnt_keep_waits_and_is_tried_again(on):
    album = held(on)
    on.fake.add("nd-dummy", "rel-dummy")
    on.fake.keeps_stars = False
    signed_in(on, "ethan")
    grant(on, ["ethan"], album)
    now = time.time() + 1

    work(on, now=now)
    entry = entries(on, "ethan")[album]
    assert (entry["state"], entry["problem"], entry["attempts"], entry["next_try"]) == ("waiting", "not_confirmed", 1, now + 30)

    #? not before its turn
    work(on, now=now + 10)
    assert entries(on, "ethan")[album]["attempts"] == 1
    on.fake.keeps_stars = True
    work(on, now=now + 31)
    assert entries(on, "ethan")[album]["state"] == "starred"


def test_an_album_navidrome_hasnt_scanned_waits_longer_each_time_until_it_has(on):
    album = held(on)
    signed_in(on, "ethan")
    grant(on, ["ethan"], album)
    now = time.time() + 1

    work(on, now=now)
    work(on, now=now + 31)
    entry = entries(on, "ethan")[album]
    assert (entry["problem"], entry["attempts"], entry["next_try"]) == ("not_in_navidrome", 2, now + 91)

    on.fake.add("nd-dummy", "rel-dummy")
    work(on, now=now + 91)
    assert entries(on, "ethan")[album]["state"] == "starred"


def test_an_album_with_no_release_id_waits_saying_so(on):
    album = held(on, tagged=False)
    signed_in(on, "ethan")
    grant(on, ["ethan"], album)
    work(on)
    assert entries(on, "ethan")[album]["problem"] == "no_release"
    assert on.fake.asked("search3") == []


def test_navidrome_down_stops_the_pass_and_counts_against_nothing(on):
    first, second = held(on), held(on, THIRD, "rel-third")
    signed_in(on, "ethan")
    grant(on, ["ethan"], first)
    grant(on, ["ethan"], second)
    on.fake.down = True

    #? reading the stars back fails first: everything waiting is said to wait on Navidrome, not counted
    work(on, now=time.time() + 1)
    assert sorted((e["problem"], e["attempts"]) for e in entries(on, "ethan").values()) == [("navidrome_down", 0)] * 2
    assert [endpoint for _, endpoint, _ in on.fake.calls if endpoint != "getUser"] == ["getStarred2"]

    #? starring, the stars read already: the pass stops at the first album asked about - the same said
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE library_membership SET problem = NULL")
    on.fake.calls.clear()
    stars._last_sync["ethan"] = time.time() + 1
    run(stars.work_once(on.store, time.time() + 1))
    assert sorted((e["problem"], e["attempts"]) for e in entries(on, "ethan").values()) == [("navidrome_down", 0)] * 2
    assert [endpoint for _, endpoint, _ in on.fake.calls] == ["search3"]


def test_a_login_navidrome_no_longer_takes_waits_for_a_sign_in_and_says_so(on):
    album = held(on)
    on.fake.add("nd-dummy", "rel-dummy")
    ethan = signed_in(on, "ethan")
    grant(on, ["ethan"], album)
    on.fake.passwords["ethan"] = "a-new-password"

    work(on)

    assert credential(on, "ethan")["dead_at"] is not None
    assert entries(on, "ethan")[album]["state"] == "waiting"
    mine = ethan.get(LIBRARY).json()
    assert (mine["login"], mine["waiting"]) == ("dead", 1)
    assert "changed your Navidrome password" in mine["login_problem"]
    #? nothing more is asked as ethan until he signs in again
    on.fake.calls.clear()
    work(on)
    assert on.fake.calls == []

    #? an entry waiting its long turn is asked about as he signs in again, not half an hour later
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE library_membership SET next_try = ?", (time.time() + 1800,))
    on.fake.passwords["ethan"] = "a-new-password"
    TestClient(on.app).post(LOGIN, json={"username": "ethan", "password": "a-new-password"})
    assert credential(on, "ethan")["dead_at"] is None
    work(on)
    assert entries(on, "ethan")[album]["state"] == "starred"


def test_the_credential_is_kept_per_user_and_outlives_signing_out(on):
    ethan = signed_in(on, "ethan")
    with sqlite3.connect(on.path) as connection:
        [session] = connection.execute("SELECT credential FROM sessions WHERE user = 'ethan'").fetchall()
    kept = credential(on, "ethan")
    #? the very login the session keeps, encrypted - never the token in the clear
    assert kept["credential"] == session[0] and "ethan-navidrome-pw" not in kept["credential"]
    ethan.post("/deadwax/auth/logout")
    assert credential(on, "ethan")["credential"] == session[0]


def test_the_recheck_kills_the_kept_login_only_when_it_is_that_login(on):
    signed_in(on, "ethan")
    first = credential(on, "ethan")["credential"]
    signed_in(on, "ethan")
    newest = credential(on, "ethan")["credential"]
    assert newest != first
    on.fake.passwords["ethan"] = "changed"
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE sessions SET checked_at = 0 WHERE credential = ?", (first,))

    run(auth.check_sessions(on.store))
    #? the older session's login died; the user's kept one is the newer sign-in's, and stands
    assert credential(on, "ethan")["dead_at"] is None

    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE sessions SET checked_at = 0")
    run(auth.check_sessions(on.store))
    assert credential(on, "ethan")["dead_at"] is not None


def test_a_session_from_before_credentials_were_kept_stands_in_for_one(on):
    signed_in(on, "ethan")
    with sqlite3.connect(on.path) as connection:
        connection.execute("DELETE FROM user_credentials")
    album = held(on)
    on.fake.add("nd-dummy", "rel-dummy")
    grant(on, ["ethan"], album)
    work(on)
    assert entries(on, "ethan")[album]["state"] == "starred"


# ================================================================ read back: two-way with Amperfy

def starred_for(on, user: str, album: int, navidrome_id: str = "nd-dummy", release: str = "rel-dummy") -> None:
    if navidrome_id not in on.fake.albums:
        on.fake.add(navidrome_id, release)
    grant(on, [user], album)
    work(on)
    assert entries(on, user)[album]["state"] == "starred"


def test_starring_an_album_in_amperfy_adds_it(on):
    signed_in(on, "ethan")
    third = held(on, THIRD, "rel-third")
    on.fake.add("nd-third", "rel-third", "Third")
    #? his stars read back once already: what he stars from now on is something added
    work(on)
    on.fake.starred("ethan").add("nd-third")

    work(on)

    entry = entries(on, "ethan")[third]
    assert (entry["how"], entry["state"], entry["navidrome_id"], entry["seen_at"]) == ("starred", "starred", "nd-third", None)
    assert entries(on, "james") == {}


def test_favourites_from_before_the_first_read_back_are_his_but_not_new(on):
    """Review: a user with favourites from before deadwax kept a ledger of them got every one marked New."""
    ethan = signed_in(on, "ethan")
    dummy, third = held(on), held(on, THIRD, "rel-third")
    on.fake.add("nd-dummy", "rel-dummy")
    on.fake.add("nd-third", "rel-third", "Third")
    on.fake.starred("ethan").update({"nd-dummy", "nd-third"})
    assert credential(on, "ethan")["synced_at"] is None

    work(on)

    got = entries(on, "ethan")
    assert {album: (e["how"], e["state"]) for album, e in got.items()} == {dummy: ("starred", "starred"), third: ("starred", "starred")}
    assert all(e["seen_at"] for e in got.values())
    assert credential(on, "ethan")["synced_at"] is not None
    assert ethan.get(LIBRARY).json()["new"] == []

    #? read back again after a restart (the memory of syncs gone): still not the first - a star made since IS new
    unstarred = held(on, "Portishead/Portishead (1997)", "rel-portishead")
    on.fake.add("nd-portishead", "rel-portishead", "Portishead")
    on.fake.starred("ethan").add("nd-portishead")
    work(on)
    assert entries(on, "ethan")[unstarred]["seen_at"] is None


def test_unstarring_it_in_amperfy_removes_it(on):
    signed_in(on, "ethan")
    album = held(on)
    starred_for(on, "ethan", album)
    on.fake.starred("ethan").discard("nd-dummy")

    work(on)

    entry = entries(on, "ethan")[album]
    assert (entry["state"], entry["removed_why"]) == ("removed", "unstarred")
    #? and starring it again brings it back
    on.fake.starred("ethan").add("nd-dummy")
    work(on)
    assert entries(on, "ethan")[album]["state"] == "starred"


def test_a_star_lost_while_the_album_is_missing_from_navidrome_is_put_back_not_removed(on):
    signed_in(on, "ethan")
    album = held(on)
    starred_for(on, "ethan", album)
    #? mid-retag: Navidrome has lost the album, and the star with it
    del on.fake.albums["nd-dummy"]
    on.fake.starred("ethan").clear()

    work(on, now=time.time())
    entry = entries(on, "ethan")[album]
    #? not removed: waiting to be starred again - tried at once, and Navidrome hasn't got it (yet)
    assert (entry["state"], entry["removed_why"], entry["problem"]) == ("waiting", None, "not_in_navidrome")

    #? back - under another id, as an album whose tags changed is
    on.fake.add("nd-dummy-2", "rel-dummy")
    work(on, now=time.time() + 60)
    entry = entries(on, "ethan")[album]
    assert (entry["state"], entry["navidrome_id"]) == ("starred", "nd-dummy-2")
    assert on.fake.starred("ethan") == {"nd-dummy-2"}


def test_a_star_lost_to_a_new_navidrome_id_is_put_back(on):
    signed_in(on, "ethan")
    album = held(on)
    starred_for(on, "ethan", album)
    del on.fake.albums["nd-dummy"]
    on.fake.starred("ethan").clear()
    on.fake.add("nd-dummy-2", "rel-dummy")

    work(on)

    entry = entries(on, "ethan")[album]
    assert (entry["state"], entry["navidrome_id"]) == ("starred", "nd-dummy-2")


def test_an_album_being_applied_to_is_never_read_as_unstarred(on):
    signed_in(on, "ethan")
    album = held(on)
    starred_for(on, "ethan", album)
    on.fake.starred("ethan").clear()

    key = library_ledger.retag_started(DUMMY)
    work(on)
    assert entries(on, "ethan")[album]["state"] == "starred"
    library_ledger.retag_finished(key)
    work(on)
    assert entries(on, "ethan")[album]["state"] == "removed"


def test_only_starred_albums_count_not_songs_or_artists(on):
    signed_in(on, "ethan")
    held(on, THIRD, "rel-third")
    on.fake.add("nd-third", "rel-third", "Third")
    on.fake.song_stars["ethan"] = [{"id": "so-1", "albumId": "nd-third", "musicBrainzId": "rel-third", "title": "Silence"}]
    work(on)
    assert entries(on, "ethan") == {}


def test_each_users_stars_are_their_own(on):
    signed_in(on, "ethan")
    signed_in(on, "sam")
    album = held(on)
    starred_for(on, "ethan", album)
    work(on)
    assert entries(on, "sam") == {}
    assert on.fake.starred("sam") == set()


# ================================================================ seeding

def test_the_first_admins_first_sign_in_puts_the_store_into_their_library_once(on):
    dummy, third = held(on), held(on, THIRD, "rel-third")
    signed_in(on, "ethan")
    assert entries(on) == {}

    signed_in(on, "james")

    seeded = entries(on, "james")
    assert set(seeded) == {dummy, third}
    assert all((e["how"], e["state"]) == ("seeded", "waiting") and e["seen_at"] for e in seeded.values())
    #? once, ever: an album copied in afterwards belongs to nobody, whoever signs in
    later = held(on, "Portishead/Portishead (1997)", "rel-portishead")
    signed_in(on, "james")
    assert later not in entries(on, "james")


def test_seeding_leaves_out_what_somebody_else_already_holds(on):
    dummy, third = held(on), held(on, THIRD, "rel-third")
    signed_in(on, "ethan")
    grant(on, ["ethan"], third)
    signed_in(on, "james")
    assert set(entries(on, "james")) == {dummy}


def test_an_admin_signed_in_before_this_step_is_seeded_at_their_next_request(on):
    dummy = held(on)
    james = signed_in(on, "james")
    #? a session from 2.0.0-player.50: no seeding then - and it outlives the restart
    with sqlite3.connect(on.path) as connection:
        connection.execute("DELETE FROM library_membership")
        connection.execute("DELETE FROM library_seed")
    auth.forget_sessions()
    assert james.get("/deadwax/me").status_code == 200
    assert set(entries(on, "james")) == {dummy}


def test_seeded_albums_are_starred_for_the_admin(on):
    held(on)
    on.fake.add("nd-dummy", "rel-dummy")
    signed_in(on, "james")
    work(on)
    assert on.fake.starred("james") == {"nd-dummy"}


# ================================================================ writers keep it true

def test_merging_disc_folders_unions_their_holders(on):
    disc1, disc2 = held(on, "Radiohead/OK Computer (1997)", "rel-okc"), held(on, "Radiohead/OK Computer (Disc 2)", "rel-okc")
    grant(on, ["james"], disc2)
    grant(on, ["ethan"], disc1)
    grant(on, ["sam"], disc1)
    grant(on, ["sam"], disc2)
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE library_membership SET state = 'removed', removed_why = 'unstarred' WHERE user = 'sam' AND album_id = ?", (disc1,))
        connection.execute("UPDATE library_membership SET state = 'starred' WHERE user = 'sam' AND album_id = ?", (disc2,))

    assert run(on.store.index_merge(on.root, "Radiohead/OK Computer (Disc 2)", "Radiohead/OK Computer (1997)")) == disc1

    got = entries(on)
    assert set(got) == {("james", disc1), ("ethan", disc1), ("sam", disc1)}
    #? sam held disc 2 (starred) and had removed disc 1: the one they hold wins
    assert got[("sam", disc1)]["state"] == "starred"


def test_refiling_an_album_keeps_its_holders(on):
    album = held(on)
    grant(on, ["ethan"], album)
    assert run(on.store.index_move(on.root, DUMMY, "Portishead (renamed)/Dummy (1994)")) == album
    assert entries(on, "ethan")[album]["state"] == "waiting"


def test_deleting_an_album_names_its_holders_first_and_leaves_them_a_tombstone(on):
    album = held(on)
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")   # james is seeded with it
    #? james's first request takes over what `local` holds - so local's entry, made after it, stays local's
    assert james.get("/deadwax/me").status_code == 200
    grant(on, ["ethan"], album)
    grant(on, [LOCAL_USER], album)

    summary = james.get("/deadwax/library/deletion_summary", params={"album": DUMMY}).json()
    #? everyone else who holds it, and whether the admin asking does - never local
    assert (summary["holders"], summary["yours"]) == (["ethan"], True)
    assert "holders_unknown" not in summary

    assert james.post("/deadwax/library/delete", json={"album_path": DUMMY}).status_code == 200

    #? ethan sees it was removed by the admin; james, who deleted it, isn't asked to request it again
    assert (entries(on, "ethan")[album]["state"], entries(on, "ethan")[album]["removed_why"]) == ("removed", "deleted")
    assert (entries(on, "james")[album]["state"], entries(on, "james")[album]["removed_why"]) == ("removed", "dismissed")
    assert james.get(LIBRARY).json()["removed"] == []
    mine = ethan.get(LIBRARY).json()
    assert [(r["album_id"], r["album"]) for r in mine["removed"]] == [(album, "Dummy")]
    assert mine["count"] == 0

    assert ethan.post(f"{LIBRARY}/dismiss", json={"album_id": album}).json() == {"dismissed": True}
    assert ethan.get(LIBRARY).json()["removed"] == []


def test_getting_a_deleted_album_again_puts_its_tombstone_away(on):
    album = held(on)
    grant(on, ["ethan"], album)
    run(on.store.index_gone(on.root, DUMMY, "deleted"))
    shutil.rmtree(on.tmp / "library" / "Portishead")
    again = held(on)
    assert again != album

    grant(on, ["ethan"], again)

    assert entries(on, "ethan")[album]["removed_why"] == "dismissed"
    assert entries(on, "ethan")[again]["state"] == "waiting"


def test_starring_a_deleted_album_got_again_in_amperfy_puts_its_tombstone_away(on):
    signed_in(on, "ethan")
    album = held(on)
    grant(on, ["ethan"], album)
    run(on.store.index_gone(on.root, DUMMY, "deleted"))
    shutil.rmtree(on.tmp / "library" / "Portishead")
    again = held(on)
    on.fake.add("nd-dummy-again", "rel-dummy")
    on.fake.starred("ethan").add("nd-dummy-again")
    work(on)
    assert entries(on, "ethan")[again]["how"] == "starred"
    assert entries(on, "ethan")[album]["removed_why"] == "dismissed"


def test_a_folder_indexed_before_a_move_lands_on_it_hands_its_holders_to_the_album_that_moved(on):
    album = held(on)
    newcomer = held(on, "Portishead/Dummy (moved)", "rel-dummy")
    grant(on, ["ethan"], album)
    grant(on, ["sam"], newcomer)
    assert run(on.store.index_move(on.root, DUMMY, "Portishead/Dummy (moved)")) == album
    assert set(entries(on)) == {("ethan", album), ("sam", album)}


def test_the_marker_can_be_cleared_by_the_stores_ids_too(on):
    album = held(on)
    ethan = signed_in(on, "ethan")
    grant(on, ["ethan"], album)
    assert ethan.post(f"{LIBRARY}/seen", json={"album_ids": [album]}).json() == {"cleared": 1}
    assert ethan.get(LIBRARY).json()["new"] == []


def test_the_break_glass_admin_has_no_library(on):
    glass = signed_in(on, auth.BREAK_GLASS_USER)
    assert glass.get(LIBRARY).json() == {"on": True, "library": False, "kept": False}
    assert auth.BREAK_GLASS_USER not in {user for user, _ in entries(on)}


def test_an_admin_back_with_a_session_takes_over_locals_library_alone(on):
    album = held(on)
    james = signed_in(on, "james")
    with sqlite3.connect(on.path) as connection:
        connection.execute("DELETE FROM library_membership")
    grant(on, [LOCAL_USER], album)
    auth.forget_sessions()
    #? local holds nothing but a library entry: that alone is something to take over
    assert on.store.local_has_anything()
    assert james.get("/deadwax/me").status_code == 200
    assert set(entries(on)) == {("james", album)}


def test_a_missing_album_keeps_its_holders(on):
    album = held(on)
    grant(on, ["ethan"], album)
    run(on.store.index_gone(on.root, DUMMY, "missing"))
    assert entries(on, "ethan")[album]["state"] == "waiting"


def test_applying_a_release_has_it_starred_again_for_everyone_who_holds_it(on, monkeypatch):
    from tests.test_retag import RELEASE as SLOW_RUSH, seed

    seed(on.tmp / "library")
    album = run(index_folder(on.store, on.root, on.tmp / "library" / "Tame Impala" / "The Slow Rush (2020)"))
    grant(on, ["ethan"], album)
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE library_membership SET state = 'starred', next_try = NULL, navidrome_id = 'nd-old'")
    app = FastAPI()
    app.state.store = on.store
    app.include_router(library_routes.router, prefix="/deadwax/library")
    monkeypatch.setattr(Config, "AUTH_MODE", "off")

    response = TestClient(app).post("/deadwax/library/retag/apply",
                                    json={"album_path": "Tame Impala/The Slow Rush (2020)", "release": SLOW_RUSH})

    assert response.status_code == 200 and response.json()["results"]["moved_to"]
    entry = entries(on, "ethan")[album]
    assert entry["state"] == "waiting" and entry["next_try"] <= time.time()


def test_an_apply_marks_the_album_as_being_retagged_while_it_runs(on, monkeypatch):
    seen = []

    async def apply(request, body):
        seen.append(library_ledger.retagging(body.album_path))
        return {}

    monkeypatch.setattr(library_routes, "_retag_apply", apply)
    monkeypatch.setattr(Config, "LIBRARY_PATH", on.root)
    body = SimpleNamespace(album_path=DUMMY)
    run(library_routes.retag_apply(SimpleNamespace(), body))
    assert seen == [True] and not library_ledger.retagging(DUMMY)


# ================================================================ the routes

def test_the_store_line_says_whether_the_pressing_is_yours(on, monkeypatch):
    album = held(on)
    ethan, james = signed_in(on, "ethan"), signed_in(on, "james")
    body = release_body()
    assert ethan.post(STORE_STATE, json=body).json()["held"]["yours"] is False
    assert james.post(STORE_STATE, json=body).json()["held"]["yours"] is True   # seeded
    grant(on, ["ethan"], album)
    answer = ethan.post(STORE_STATE, json=body).json()["held"]
    assert answer["yours"] is True and "album_ids" not in answer
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    answer = TestClient(on.app).post(STORE_STATE, json=body).json()["held"]
    assert "yours" not in answer and "album_ids" not in answer


def test_add_to_my_library_adds_a_pressing_the_store_holds(on):
    album = held(on)
    ethan = signed_in(on, "ethan")

    answer = ethan.post(f"{LIBRARY}/add", json=release_body())

    #? (2.0.0-player.52) Add stars it at once as ethan - Navidrome hasn't the album here, so it waits
    assert answer.json() == {"added": True, "already": False, "complete": True, "starred": False}
    entry = entries(on, "ethan")[album]
    #? added while looking at it: no new marker
    assert (entry["how"], entry["state"], entry["incomplete"]) == ("added", "waiting", 0) and entry["seen_at"]
    assert ethan.post(f"{LIBRARY}/add", json=release_body()).json()["already"] is True


def test_adding_a_part_held_marks_it_incomplete(on):
    album = held(on, tracks=1)
    ethan = signed_in(on, "ethan")
    assert ethan.post(f"{LIBRARY}/add", json=release_body()).json()["complete"] is False
    assert entries(on, "ethan")[album]["incomplete"] == 1


def test_add_to_my_library_is_refused_in_words_when_there_is_nothing_to_add(on, monkeypatch):
    ethan = signed_in(on, "ethan")
    answer = ethan.post(f"{LIBRARY}/add", json=release_body("rel-nowhere"))
    assert answer.status_code == 409 and "isn't in the store" in answer.json()["detail"]
    held(on)
    glass = signed_in(on, auth.BREAK_GLASS_USER)
    answer = glass.post(f"{LIBRARY}/add", json=release_body())
    assert answer.status_code == 409 and "no Navidrome account" in answer.json()["detail"]
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    assert TestClient(on.app).post(f"{LIBRARY}/add", json=release_body()).status_code == 409


def test_your_library_says_what_waits_and_why_and_what_is_new(on):
    dummy, third = held(on), held(on, THIRD, "rel-third")
    on.fake.add("nd-dummy", "rel-dummy")
    ethan = signed_in(on, "ethan")
    grant(on, ["ethan"], dummy)
    grant(on, ["ethan"], third)
    work(on)

    mine = ethan.get(LIBRARY).json()
    assert (mine["on"], mine["count"], mine["starred"], mine["waiting"], mine["login"]) == (True, 2, 1, 1, "ok")
    [waiting] = mine["waiting_albums"]
    assert (waiting["album_id"], waiting["problem"]) == (third, "not_in_navidrome")
    assert "hasn't got it yet" in waiting["words"]
    assert {n["album_id"]: n["navidrome_id"] for n in mine["new"]} == {dummy: "nd-dummy", third: None}

    assert ethan.post(f"{LIBRARY}/seen", json={"release_mbid": "rel-dummy"}).json() == {"cleared": 1}
    assert [n["album_id"] for n in ethan.get(LIBRARY).json()["new"]] == [third]


def test_held_by_nobody_lists_what_nobody_holds_and_the_flags(on):
    dummy, third = held(on), held(on, THIRD, "rel-third")
    ethan = signed_in(on, "ethan")
    grant(on, ["ethan"], dummy)
    with sqlite3.connect(on.path) as connection:
        connection.execute("INSERT INTO library_seed (id, user, seeded_at, albums) VALUES (1, 'x', 'then', 0)")
    james = signed_in(on, "james")
    flag = run(on.store.flag_add(third, 7, ["ethan", "sam"], "Portishead", "Third", THIRD, "rel-third"))

    answer = james.get(HELD).json()
    assert [a["path"] for a in answer["albums"]] == [THIRD]
    assert [(f["id"], f["users"]) for f in answer["flags"]] == [(flag, ["ethan", "sam"])]
    assert ethan.get(HELD).status_code == 403

    assert james.post(f"{HELD}/flags/{flag}/add").json() == {"added": True, "users": ["ethan", "sam"]}
    assert {user for (user, album) in entries(on) if album == third} == {"ethan", "sam"}
    assert james.get(HELD).json() == {"count": 0, "albums": [], "flags": []}
    assert james.post(f"{HELD}/flags/{flag}/add").status_code == 409


def test_a_flag_can_be_put_away_and_a_flag_for_an_album_gone_isnt_given(on):
    third = held(on, THIRD, "rel-third")
    james = signed_in(on, "james")
    first = run(on.store.flag_add(third, 1, ["ethan"], "Portishead", "Third", THIRD, "rel-third"))
    second = run(on.store.flag_add(third, 2, ["sam"], "Portishead", "Third", THIRD, "rel-third"))
    assert james.post(f"{HELD}/flags/{first}/dismiss").json() == {"dismissed": True}
    run(on.store.index_gone(on.root, THIRD, "deleted"))
    answer = james.post(f"{HELD}/flags/{second}/add")
    assert answer.status_code == 409 and "isn't in the store" in answer.json()["detail"]
    assert ("sam", third) not in entries(on)


def test_a_download_nothing_of_could_be_filed_offers_the_next_peer_with_logins_on(on, monkeypatch):
    ethan = signed_in(on, "ethan")
    alternatives = [{"username": "carol", "directory": "share/album", "files": FILES}]
    job_id = run(on.store.create_job("bob", "share/album", FILES, FILED_RELEASE, alternatives, user="ethan"))
    run(on.store.update_status(job_id, "complete", poller.NOTHING_ORGANIZED))

    [row] = ethan.get(JOBS).json()["jobs"]
    assert (row["outcome"], row["alternatives_left"]) == ("not_filed", 1)
    moved = ethan.post(f"{JOBS}/{job_id}/retry").json()
    assert (moved["moved"], moved["username"]) == (True, "carol")

    #? logins off: as it always was
    run(on.store.update_status(job_id, "complete", f"{poller.ORGANIZE_FAILED} disk full"))
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    [row] = TestClient(on.app).get(JOBS).json()["jobs"]
    assert row["outcome"] is None and "alternatives_left" not in row
    assert TestClient(on.app).post(f"{JOBS}/{job_id}/retry").status_code == 409


def test_a_partly_filed_or_dry_run_download_is_not_one_nothing_could_be_filed_of():
    assert poller.job_outcome("complete", "1 file(s) failed to organize", not_filed=True) == "partly_filed"
    assert poller.job_outcome("complete", "1 file(s) failed to organize, no track was filed", not_filed=True) == "not_filed"
    assert poller.job_outcome("complete", "dry run - not organized", not_filed=True) is None
    assert poller.job_outcome("complete", poller.NOTHING_ORGANIZED) is None


# ================================================================ logins off, the take-over, the worker

def test_with_logins_off_local_is_given_what_it_files_silently_and_nothing_is_starred(on, monkeypatch):
    #? a credential kept from when logins were on: with them off it is used for nothing
    signed_in(on, "ethan")
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    downloads(on)
    job(on, LOCAL_USER)
    file_it(on)
    [album] = run(on.store.index_present(on.root, "mb-1"))
    assert entries(on, LOCAL_USER)[album["id"]]["state"] == "waiting"

    client = TestClient(on.app)
    assert client.get(LIBRARY).json() == {"on": False}
    on.fake.calls.clear()
    assert work(on)["tried"] == 0
    assert on.fake.calls == []


def test_the_first_admin_takes_over_locals_library_and_none_of_it_is_new(on, monkeypatch):
    album = held(on)
    grant(on, [LOCAL_USER], album)
    with sqlite3.connect(on.path) as connection:
        connection.execute("INSERT INTO library_seed (id, user, seeded_at, albums) VALUES (1, 'x', 'then', 0)")
    signed_in(on, "james")
    assert entries(on, LOCAL_USER) == {}
    entry = entries(on, "james")[album]
    assert entry["state"] == "waiting" and entry["seen_at"] is not None


def test_the_worker_starts_only_with_logins_on_and_a_kick_wakes_it(monkeypatch):
    passes = []

    async def once(store, now=None):
        passes.append(store)
        if len(passes) >= 2:
            raise asyncio.CancelledError
        return {"more": False}

    monkeypatch.setattr(stars, "work_once", once)
    monkeypatch.setattr(stars, "WORK_SECONDS", 3600)

    async def drive():
        task = asyncio.create_task(stars.run_library_worker("the store"))
        for _ in range(3):
            await asyncio.sleep(0)
        library_ledger.kick()
        for _ in range(20):
            await asyncio.sleep(0.01)
            if passes:
                break
        library_ledger.kick()
        with pytest.raises(asyncio.CancelledError):
            await asyncio.wait_for(task, 2)

    run(drive())
    assert passes == ["the store", "the store"]
    #? the wake-up goes with the worker
    assert library_ledger._worker == {"loop": None, "event": None}


def test_deadwax_starts_the_starring_worker_only_with_logins_on(monkeypatch, tmp_path):
    from src.api import app as app_module
    started = []

    async def worker(store):
        started.append(store)
        await asyncio.Event().wait()

    async def forever(*_args):
        await asyncio.Event().wait()

    async def nothing(*_args):
        return None

    class Client:
        async def close_client(self):
            return None

    monkeypatch.setattr(app_module, "MusicBrainzClient", Client)
    monkeypatch.setattr(app_module, "SlskdClient", Client)
    monkeypatch.setattr(app_module, "JobStore", lambda: JobStore(str(tmp_path / "deadwax.db")))
    monkeypatch.setattr(app_module, "seed_from_saved_scan", nothing)
    monkeypatch.setattr(app_module, "run_download_poller", forever)
    monkeypatch.setattr(app_module, "cleanup_logging", lambda: None)
    monkeypatch.setattr(auth, "run_session_checks", forever)
    for client in (app_module.library.coverart_client, app_module.library.artist_images_client,
                   app_module.lrclib, app_module.navidrome_client, auth.login_client, stars.star_client):
        monkeypatch.setattr(client, "close_client", nothing)
    monkeypatch.setattr(Config, "apply_overrides", lambda stored: None)
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", SECRET)
    monkeypatch.setattr(stars, "run_library_worker", worker)
    logging.getLogger().setLevel(logging.WARNING)

    async def lifespan_with(mode):
        monkeypatch.setattr(Config, "AUTH_MODE", mode)
        app = start()
        async with app_module.lifespan(app):
            await asyncio.sleep(0)
            return app.state.store

    store = run(lifespan_with("on"))
    assert started == [store]
    started.clear()
    run(lifespan_with("off"))
    assert started == []


# ================================================================ after review (2.0.0-player.51)
#
# Each test below holds a rule a reviewer found broken or unpinned, and fails with it broken.

def unscanned(on) -> None:
    """A library deadwax has never scanned: the store index holds only what downloads and applies indexed."""
    with sqlite3.connect(on.path) as connection:
        connection.execute("DELETE FROM store_index_scanned")


def frontend_lines(caplog) -> list[str]:
    return [record.getMessage() for record in caplog.records if getattr(record, "frontend", False)]


def test_with_logins_off_a_filing_into_an_untagged_folder_is_neither_flagged_nor_said(on, monkeypatch, caplog):
    """Logins off, nothing visible changes: no event-log line pointing at a Library care section that isn't
    drawn, no flag left naming `local` for when logins come on, nothing on the row."""
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    downloads(on)
    held(on, FOLDER, tagged=False)
    job_id = job(on, LOCAL_USER)
    caplog.set_level(logging.DEBUG)

    file_it(on)

    stored = run(on.store.get_job(job_id))
    assert stored["error"].startswith("already in the store")
    assert stored["library_grant"] is None
    assert run(on.store.flags_open()) == []
    assert entries(on) == {}
    assert not [line for line in frontend_lines(caplog) if "Library care" in line or "nobody was given" in line]


def test_a_flagged_filing_with_logins_on_is_said_in_the_event_log(on, caplog):
    downloads(on)
    held(on, FOLDER, tagged=False)
    job(on, "ethan")
    caplog.set_level(logging.DEBUG)
    file_it(on)
    assert [line for line in frontend_lines(caplog) if "waits for an admin in Library care" in line]


def test_the_downloads_poll_reads_runners_up_only_where_the_next_peer_can_start_it(on):
    """Review: reading every finished row's runners-up doubled the poll's cost - dry runs above all."""
    alternatives = [{"username": "carol", "directory": "share/album", "files": FILES}]
    errors = {
        "dry": "dry run - not organized",
        "there": "already in the store: all 2 track(s) were already there, nothing was filed",
        "partly": "1 file(s) failed to organize",
        "nothing": poller.NOTHING_ORGANIZED,
        "raised": f"{poller.ORGANIZE_FAILED} disk full",
        "no track": "1 file(s) failed to organize, no track was filed",
    }
    ids = {}
    for name, error in errors.items():
        ids[name] = run(on.store.create_job("bob", "share/album", FILES, FILED_RELEASE, alternatives, user="ethan"))
        run(on.store.update_status(ids[name], "complete", error))
    ids["failed"] = run(on.store.create_job("bob", "share/album", FILES, FILED_RELEASE, alternatives, user="ethan"))
    run(on.store.update_status(ids["failed"], "failed", "peer vanished"))

    def read(**kwargs):
        listed = {job["id"]: job for job in run(on.store.list_jobs(**kwargs))}
        return {name for name, job_id in ids.items() if listed[job_id]["alternatives"]}

    #? logins off - no patterns: failed and cancelled alone, as before
    assert read() == {"failed"}
    #? logins on: and the three a download nothing of could be filed ends with - nothing else
    assert read(user="ethan", not_filed=poller.NOT_FILED_PATTERNS) == {"failed", "nothing", "raised", "no track"}
    #? and every one of those the route counts, it can start again
    for name in ("nothing", "raised", "no track"):
        assert poller.retryable(run(on.store.get_job(ids[name])), logins=True)


def test_the_delete_dialog_never_says_nobody_has_it_on_a_guess(on, monkeypatch):
    """Review: an unread ledger read as "Nobody has it in their library" - in the confirmation of the one
    action with no undo."""
    album = held(on)
    james = signed_in(on, "james")
    grant(on, ["ethan"], album)
    summary = james.get("/deadwax/library/deletion_summary", params={"album": DUMMY}).json()
    assert (summary["holders"], summary["yours"]) == (["ethan"], True)

    async def unread(*_args):
        return None

    with monkeypatch.context() as patched:
        patched.setattr(on.store, "ledger_holders", unread)
        summary = james.get("/deadwax/library/deletion_summary", params={"album": DUMMY}).json()
    assert summary["holders_unknown"] is True and "holders" not in summary and "yours" not in summary

    #? the database gone altogether: the break-glass admin, who needs none, still gets no "nobody"
    glass = signed_in(on, auth.BREAK_GLASS_USER)
    on.store.available = False
    summary = glass.get("/deadwax/library/deletion_summary", params={"album": DUMMY}).json()
    assert summary["holders_unknown"] is True and "holders" not in summary


def test_the_store_line_says_nothing_of_yours_when_the_ledger_cant_be_read(on, monkeypatch):
    held(on)
    james = signed_in(on, "james")
    assert james.post(STORE_STATE, json=release_body()).json()["held"]["yours"] is True

    async def unread(*_args):
        return None

    monkeypatch.setattr(on.store, "ledger_holds", unread)
    answer = james.post(STORE_STATE, json=release_body()).json()["held"]
    assert "yours" not in answer


def test_the_break_glass_admin_gets_no_yours_on_the_store_line(on):
    held(on)
    glass = signed_in(on, auth.BREAK_GLASS_USER)
    answer = glass.post(STORE_STATE, json=release_body()).json()["held"]
    assert "yours" not in answer and answer["complete"] is True


def test_with_logins_off_the_delete_summary_names_nobody(on, monkeypatch):
    album = held(on)
    grant(on, [LOCAL_USER], album)
    grant(on, ["ethan"], album)
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    summary = TestClient(on.app).get("/deadwax/library/deletion_summary", params={"album": DUMMY}).json()
    assert not {"holders", "yours", "holders_unknown"} & set(summary)


def test_what_local_deletes_with_logins_off_isnt_handed_on_as_removed_by_the_admin(on, monkeypatch):
    album = held(on)
    grant(on, [LOCAL_USER], album)
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    assert TestClient(on.app).post("/deadwax/library/delete", json={"album_path": DUMMY}).status_code == 200
    assert entries(on, LOCAL_USER)[album]["removed_why"] == "dismissed"
    monkeypatch.setattr(Config, "AUTH_MODE", "on")
    james = signed_in(on, "james")
    assert james.get(LIBRARY).json()["removed"] == []


def test_a_full_batch_whose_writes_fail_waits_for_the_next_pass(on, monkeypatch):
    """Review: with the ledger's writes failing and its reads working (a full disk), a full batch asked for
    another pass at once, for ever - thousands of calls to Navidrome a second."""
    signed_in(on, "ethan")
    albums = [held(on, f"Artist {n}/Album {n} (2000)", f"rel-{n}", tracks=1) for n in range(stars.STAR_BATCH + 5)]
    for album in albums:
        grant(on, ["ethan"], album)

    #? the writes landing: a full batch, every outcome kept - another pass at once is worth it
    done = work(on)
    assert (done["tried"], done["more"]) == (stars.STAR_BATCH, True)

    async def refused(*_args, **_kwargs):
        return False

    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE library_membership SET next_try = NULL, attempts = 0, problem = NULL")
    monkeypatch.setattr(on.store, "ledger_wait", refused)
    monkeypatch.setattr(on.store, "ledger_starred", refused)
    done = work(on, sync=False)
    assert (done["tried"], done["more"]) == (stars.STAR_BATCH, False)


def test_a_full_batch_is_one_batch(on):
    signed_in(on, "ethan")
    for n in range(stars.STAR_BATCH + 3):
        grant(on, ["ethan"], held(on, f"Artist {n}/Album {n} (2000)", f"rel-{n}", tracks=1))
    done = work(on)
    assert (done["tried"], done["more"]) == (stars.STAR_BATCH, True)
    assert len(on.fake.asked("search3")) == stars.STAR_BATCH * 2
    done = work(on, sync=False)
    assert (done["tried"], done["more"]) == (3, False)


@pytest.mark.parametrize("error", [
    httpx.Response(200, json=failed(0, "something went wrong")),
    httpx.Response(200, json=failed(50, "not authorized")),
    httpx.Response(500, text="oops"),
    httpx.Response(200, text="<html>not json</html>"),
])
def test_one_users_read_back_error_never_stops_the_others(on, error):
    """Review: any getStarred2 error but a refused login stopped everyone's pass, every pass - nobody after
    that user in name order was ever starred - and called it "Navidrome isn't answering"."""
    dummy, third = held(on), held(on, THIRD, "rel-third")
    on.fake.add("nd-dummy", "rel-dummy")
    signed_in(on, "james")                       # seeded with both
    signed_in(on, "ethan")
    grant(on, ["ethan"], third)
    on.fake.errors[("ethan", "getStarred2")] = error
    now = time.time() + 1

    done = work(on, now=now)

    assert entries(on, "james")[dummy]["state"] == "starred"
    #? ethan's own albums are still starred - his read-back alone waits for his next sync
    assert entries(on, "ethan")[third]["problem"] == "not_in_navidrome"
    assert stars._last_sync["ethan"] == now and done["synced"] == 1
    #? not asked again until his next sync is due
    on.fake.calls.clear()
    run(stars.work_once(on.store, now + 60))
    assert ("ethan", "getStarred2") not in {(user, endpoint) for user, endpoint, _ in on.fake.calls}


def test_an_album_is_found_by_its_title_when_navidrome_cant_search_ids_and_only_its_own_pressing(on):
    """The title is the only way in when search3 doesn't match MusicBrainz ids (not verified on a real 0.64)."""
    album = held(on)
    on.fake.mbid_search = False
    #? another pressing of the same name first: never taken on its title
    on.fake.add("nd-other", "rel-another-pressing")
    signed_in(on, "ethan")
    grant(on, ["ethan"], album)

    work(on)
    entry = entries(on, "ethan")[album]
    assert (entry["state"], entry["problem"]) == ("waiting", "not_in_navidrome")
    assert on.fake.starred("ethan") == set()
    assert [q["query"] for _, q in on.fake.asked("search3")] == ["rel-dummy", "Dummy"]

    on.fake.add("nd-dummy", "rel-dummy")
    work(on, now=time.time() + 60)
    entry = entries(on, "ethan")[album]
    assert (entry["state"], entry["navidrome_id"]) == ("starred", "nd-dummy")
    assert on.fake.starred("ethan") == {"nd-dummy"}


def test_an_id_the_bridge_already_knows_is_tried_first(on):
    from src.routes.store_album import remember_navidrome_id

    album = held(on)
    on.fake.add("nd-dummy", "rel-dummy")
    remember_navidrome_id("rel-dummy", "nd-dummy")
    signed_in(on, "ethan")
    grant(on, ["ethan"], album)
    work(on)
    assert entries(on, "ethan")[album]["state"] == "starred"
    assert on.fake.asked("search3") == []


def test_a_login_sealed_with_another_key_dies_and_the_others_are_still_starred(on, monkeypatch):
    album = held(on)
    on.fake.add("nd-dummy", "rel-dummy")
    signed_in(on, "ethan")
    signed_in(on, "sam")
    grant(on, ["sam"], album)
    #? ethan's kept login sealed under a key deadwax no longer has - and he sorts before sam
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", "another-key-entirely-0123456789abcdef")
    foreign = auth.seal_credential("ethan", "t", "s")
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", SECRET)
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE user_credentials SET credential = ? WHERE user = 'ethan'", (foreign,))

    done = work(on)

    assert (credential(on, "ethan")["dead_why"], done["dead"]) == (auth.KEY_CHANGED, 1)
    assert entries(on, "sam")[album]["state"] == "starred"


def test_a_new_secret_key_kills_the_kept_login_of_a_session_it_cant_open(on, monkeypatch):
    signed_in(on, "ethan")
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", "another-key-entirely-0123456789abcdef")
    run(auth.check_sessions(on.store, now=time.time() + auth.RECHECK_SECONDS + 1))
    assert credential(on, "ethan")["dead_why"] == auth.KEY_CHANGED


def test_the_sign_in_keeps_the_login_off_the_event_loop(on, monkeypatch):
    """Review: kept with blocking SQLite on the loop, a writer holding the lock stalled every request and
    stream for up to ten seconds."""
    where = []
    keep = on.store.keep_credential

    def kept(*args):
        try:
            asyncio.get_running_loop()
            where.append("loop")
        except RuntimeError:
            where.append("thread")
        return keep(*args)

    monkeypatch.setattr(on.store, "keep_credential", kept)
    signed_in(on, "ethan")
    assert where == ["thread"]


def test_a_break_glass_download_gives_nobody_the_album(on):
    """Review: the break-glass admin has no library, yet a filing gave it an entry nobody would star or see -
    which counted as held: off Held by nobody, named in the delete dialog, left out of the seed."""
    downloads(on)
    job_id = job(on, auth.BREAK_GLASS_USER)

    file_it(on)

    [album] = run(on.store.index_present(on.root, "mb-1"))
    assert entries(on) == {}
    assert run(on.store.get_job(job_id))["library_grant"] is None
    with sqlite3.connect(on.path) as connection:
        connection.execute("DELETE FROM library_seed")
    signed_in(on, "james")
    #? james's seed has it: nobody held it
    assert album["id"] in entries(on, "james")


def test_a_flag_never_names_the_break_glass_admin(on):
    downloads(on)
    held(on, FOLDER, tagged=False)
    job(on, auth.BREAK_GLASS_USER, "ethan")
    file_it(on)
    [flag] = run(on.store.flags_open())
    assert flag["users"] == ["ethan"]
    #? and a flag from before that rule gives only who can hold it
    third = held(on, THIRD, "rel-third")
    old = run(on.store.flag_add(third, 9, [auth.BREAK_GLASS_USER, "sam"], "Portishead", "Third", THIRD, "rel-third"))
    james = signed_in(on, "james")
    assert james.post(f"{HELD}/flags/{old}/add").json()["users"] == ["sam"]
    assert auth.BREAK_GLASS_USER not in {user for user, _ in entries(on)}


def test_the_seed_waits_for_the_librarys_first_scan(on):
    """Review: a sign-in before the index knew the store seeded what little it held and was done for good -
    every album the first scan found then belonged to nobody (a fresh install, or an upgrade whose saved
    scan was in an older format)."""
    unscanned(on)
    #? a download indexed before any scan - the index holds it, and nothing else
    early = held(on)
    signed_in(on, "james")
    assert entries(on, "james") == {}
    assert not on.store.library_seeded()

    #? a scan that found nothing finishes nothing (an unmounted share looks like that)
    run(on.store.index_reconcile(on.root, []))
    assert not on.store.library_seeded()

    #? the first real scan: everything it found goes into james's library, seen
    write_flac(on.tmp / "library" / THIRD / "01 - Track 1.flac", album="Third", albumartist="Portishead",
               title="Track 1", tracknumber="1", musicbrainz_albumid="rel-third")
    from src.library import scan_library
    from src.store_index import reconcile_scan
    run(reconcile_scan(on.store, on.root, scan_library(on.root, True)["albums"]))
    third = run(on.store.index_present(on.root, "rel-third"))[0]["id"]
    seeded = entries(on, "james")
    assert set(seeded) == {early, third}
    assert all(e["how"] == "seeded" and e["seen_at"] for e in seeded.values())
    assert on.store.library_seeded()

    #? once: an album that arrives afterwards belongs to nobody, whatever scans or signs in
    later = held(on, "Portishead/Portishead (1997)", "rel-portishead")
    run(reconcile_scan(on.store, on.root, scan_library(on.root, True)["albums"]))
    signed_in(on, "james")
    assert later not in entries(on, "james")


def test_a_store_index_from_before_counts_as_scanned(tmp_path):
    """An upgrade from .50: the index was filled from scans, so the first admin is seeded at their sign-in."""
    path = tmp_path / "deadwax.db"
    store = JobStore(str(path))
    store.init()
    with sqlite3.connect(path) as connection:
        connection.execute("DROP TABLE store_index_scanned")
        connection.execute("INSERT INTO store_album (root, path, state, first_seen, updated_at) "
                           "VALUES ('/music', 'A/B', 'present', 'then', 'then')")
    store.init()
    with sqlite3.connect(path) as connection:
        assert connection.execute("SELECT root FROM store_index_scanned").fetchall() == [("/music",)]
    assert store.seed_library_now("james", "/music") == 1
    #? and a database made fresh has no root counted until a scan
    fresh = JobStore(str(tmp_path / "fresh.db"))
    fresh.init()
    assert fresh.seed_library_now("james", "/music") == JobStore.SEED_HELD_OVER


def test_a_seed_of_an_index_holding_only_others_albums_is_still_once(on):
    dummy = held(on)
    grant(on, ["ethan"], dummy)
    signed_in(on, "james")
    assert entries(on, "james") == {} and on.store.library_seeded()
    later = held(on, THIRD, "rel-third")
    signed_in(on, "james")
    assert later not in entries(on, "james")


# ----------------------------------------------------------------- the ledger's rules, each pinned

def test_add_to_my_library_over_an_album_you_unstarred_holds_it_again(on):
    album = held(on)
    ethan = signed_in(on, "ethan")
    grant(on, ["ethan"], album)
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE library_membership SET state = 'removed', removed_why = 'unstarred'")
    assert ethan.post(f"{LIBRARY}/add", json=release_body()).json()["added"] is True
    entry = entries(on, "ethan")[album]
    #? waiting to be starred again - and seen: added while looking at it
    assert (entry["state"], entry["removed_why"], entry["how"]) == ("waiting", None, "added") and entry["seen_at"]


def test_a_grant_over_an_album_you_unstarred_holds_it_again_new(on):
    album = held(on)
    grant(on, ["ethan"], album)
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE library_membership SET state = 'removed', removed_why = 'unstarred', seen_at = 'then'")
    grant(on, ["ethan"], album)
    entry = entries(on, "ethan")[album]
    assert (entry["state"], entry["removed_why"], entry["seen_at"]) == ("waiting", None, None)


def test_a_complete_grant_clears_incomplete(on):
    album = held(on)
    grant(on, ["ethan"], album, incomplete=True)
    assert entries(on, "ethan")[album]["incomplete"] == 1
    grant(on, ["ethan"], album)
    assert entries(on, "ethan")[album]["incomplete"] == 0


def test_a_delete_leaves_an_album_you_unstarred_or_put_away_as_it_was(on):
    album = held(on)
    grant(on, ["ethan", "sam"], album)
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE library_membership SET state = 'removed', removed_why = 'unstarred' WHERE user = 'ethan'")
        connection.execute("UPDATE library_membership SET state = 'removed', removed_why = 'dismissed' WHERE user = 'sam'")
    run(on.store.index_gone(on.root, DUMMY, "deleted"))
    assert entries(on, "ethan")[album]["removed_why"] == "unstarred"
    assert entries(on, "sam")[album]["removed_why"] == "dismissed"


def test_held_by_nobody_leaves_out_an_album_its_holder_has_starred(on):
    dummy, third = held(on), held(on, THIRD, "rel-third")
    grant(on, ["ethan"], dummy)
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE library_membership SET state = 'starred'")
    assert [row["id"] for row in run(on.store.ledger_unheld(on.root))] == [third]


def test_merging_keeps_the_new_marker_if_either_was_new(on):
    disc1, disc2 = held(on, "Radiohead/OK Computer (1997)", "rel-okc"), held(on, "Radiohead/OK Computer (Disc 2)", "rel-okc")
    grant(on, ["ethan"], disc1)
    grant(on, ["ethan"], disc2)
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE library_membership SET seen_at = 'then' WHERE album_id = ?", (disc1,))
    run(on.store.index_merge(on.root, "Radiohead/OK Computer (Disc 2)", "Radiohead/OK Computer (1997)"))
    assert entries(on, "ethan")[disc1]["seen_at"] is None


def test_unstarring_is_taken_only_while_it_is_still_the_star_read(on):
    album = held(on)
    grant(on, ["ethan"], album)
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE library_membership SET state = 'starred', navidrome_id = 'nd-new'")
    assert run(on.store.ledger_remove("ethan", album, "unstarred", "nd-old")) is False
    assert entries(on, "ethan")[album]["state"] == "starred"
    assert run(on.store.ledger_remove("ethan", album, "unstarred", "nd-new")) is True


def test_an_apply_asks_again_about_an_album_still_waiting_too(on):
    album = held(on)
    grant(on, ["ethan"], album)
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE library_membership SET next_try = ?, attempts = 6", (time.time() + 1800,))
    assert run(on.store.ledger_restar(album)) == 1
    entry = entries(on, "ethan")[album]
    assert entry["next_try"] <= time.time() and entry["attempts"] == 0


def test_a_flag_on_a_disc_folder_merged_since_gives_the_folder_it_went_into(on):
    disc1, disc2 = held(on, "Radiohead/OK Computer (1997)", "rel-okc"), held(on, "Radiohead/OK Computer (Disc 2)", "rel-okc")
    james = signed_in(on, "james")
    flag = run(on.store.flag_add(disc2, 3, ["ethan"], "Radiohead", "OK Computer", "Radiohead/OK Computer (Disc 2)", "rel-okc"))
    run(on.store.index_merge(on.root, "Radiohead/OK Computer (Disc 2)", "Radiohead/OK Computer (1997)"))
    assert james.post(f"{HELD}/flags/{flag}/add").json()["added"] is True
    assert ("ethan", disc1) in entries(on) and ("ethan", disc2) not in entries(on)


def test_an_album_deleted_before_you_opened_it_is_never_new(on):
    album = held(on)
    ethan = signed_in(on, "ethan")
    grant(on, ["ethan"], album)
    assert [n["album_id"] for n in ethan.get(LIBRARY).json()["new"]] == [album]
    run(on.store.index_gone(on.root, DUMMY, "deleted"))
    assert ethan.get(LIBRARY).json()["new"] == []


def test_a_refused_apply_leaves_no_album_marked_mid_retag(on, monkeypatch):
    from fastapi import HTTPException

    async def refuse(request, body):
        raise HTTPException(status_code=409, detail="the folder moved")

    monkeypatch.setattr(library_routes, "_retag_apply", refuse)
    with pytest.raises(HTTPException):
        run(library_routes.retag_apply(SimpleNamespace(), SimpleNamespace(album_path=DUMMY)))
    assert not library_ledger.retagging(DUMMY)


def test_an_album_whose_folder_is_gone_waits_without_asking_navidrome(on):
    album = held(on)
    signed_in(on, "ethan")
    grant(on, ["ethan"], album)
    run(on.store.index_gone(on.root, DUMMY, "missing"))
    work(on)
    assert entries(on, "ethan")[album]["problem"] == "missing"
    assert on.fake.asked("search3") == []


def test_the_read_back_leaves_a_starred_album_whose_folder_is_gone_alone(on):
    signed_in(on, "ethan")
    album = held(on)
    starred_for(on, "ethan", album)
    run(on.store.index_gone(on.root, DUMMY, "missing"))
    on.fake.starred("ethan").clear()
    work(on)
    entry = entries(on, "ethan")[album]
    assert (entry["state"], entry["removed_why"], entry["problem"]) == ("starred", None, None)


def test_your_library_counts_what_is_incomplete(on):
    dummy, third = held(on), held(on, THIRD, "rel-third")
    ethan = signed_in(on, "ethan")
    grant(on, ["ethan"], dummy, incomplete=True)
    grant(on, ["ethan"], third)
    assert ethan.get(LIBRARY).json()["incomplete"] == 1


# ================================================================ after the second review (2.0.0-player.51)

def test_seeding_puts_in_what_somebody_else_starred_or_added_and_leaves_out_only_their_downloads(on):
    """Review: an upgrade with Ethan's session kept - the worker's first pass, 15 s after the restart and
    before James's first request, read Ethan's favourites from before back, and the seed then left every
    one of them out of James's library, for good. Libraries aren't exclusive: only an album somebody
    else's download brought is left out."""
    dummy, third = held(on), held(on, THIRD, "rel-third")
    later = held(on, "Portishead/Portishead (1997)", "rel-portishead")
    signed_in(on, "ethan")
    on.fake.add("nd-dummy", "rel-dummy")
    on.fake.starred("ethan").add("nd-dummy")
    work(on)
    assert (entries(on, "ethan")[dummy]["how"], entries(on, "ethan")[dummy]["state"]) == ("starred", "starred")
    grant(on, ["ethan"], third, how=library_ledger.FROM_STORE)
    #? his download: it came with his request
    grant(on, ["ethan"], later)

    signed_in(on, "james")

    seeded = entries(on, "james")
    assert set(seeded) == {dummy, third}
    assert all(e["how"] == "seeded" and e["seen_at"] for e in seeded.values())
    assert set(entries(on, "ethan")) == {dummy, third, later}


def test_a_read_back_before_the_librarys_first_scan_is_not_counted_as_the_first(on):
    """Review: on a fresh install Ethan's first read-back ran before any scan, found none of his favourites
    in the index and still counted as the first - so the read after the first scan added every favourite
    he'd had for years as New."""
    unscanned(on)
    for folder, release in ((DUMMY, "rel-dummy"), (THIRD, "rel-third")):
        write_flac(on.tmp / "library" / folder / "01 - Track 1.flac", album=folder.split("/")[1].split(" (")[0],
                   albumartist="Portishead", artist="Portishead", title="Track 1", tracknumber="1",
                   musicbrainz_albumid=release)
    on.fake.add("nd-dummy", "rel-dummy")
    on.fake.add("nd-third", "rel-third", "Third")
    on.fake.starred("ethan").update({"nd-dummy", "nd-third"})
    ethan = signed_in(on, "ethan")

    work(on)
    assert entries(on, "ethan") == {}
    assert credential(on, "ethan")["synced_at"] is None

    #? the library's first scan - a search's
    assert ethan.get("/deadwax/library/owned").status_code == 200
    assert run(on.store.index_scanned(on.root))
    work(on)

    got = entries(on, "ethan")
    assert len(got) == 2 and all(e["how"] == "starred" and e["seen_at"] for e in got.values())
    assert credential(on, "ethan")["synced_at"] is not None
    assert ethan.get(LIBRARY).json()["new"] == []


def test_an_admins_look_at_a_flag_is_said_on_the_requesters_row(on):
    """Review: Add for them put the album in Ethan's library and his row still said "so not added - an
    admin has been asked to look"; Put away left it saying an admin was still being asked."""
    downloads(on)
    untagged = held(on, FOLDER, tagged=False)
    ethan = signed_in(on, "ethan")
    first = job(on, "ethan")
    file_it(on)
    second = job(on, "ethan", peer="carol")
    file_it(on, "carol")
    rows = {row["id"]: row for row in ethan.get(JOBS).json()["jobs"]}
    assert [rows[first]["library"], rows[second]["library"]] == ["flagged", "flagged"]
    flags = {flag["job_id"]: flag["id"] for flag in run(on.store.flags_open())}
    james = signed_in(on, "james")

    assert james.post(f"{HELD}/flags/{flags[first]}/add").json() == {"added": True, "users": ["ethan"]}
    assert james.post(f"{HELD}/flags/{flags[second]}/dismiss").json() == {"dismissed": True}

    rows = {row["id"]: row for row in ethan.get(JOBS).json()["jobs"]}
    assert (rows[first]["outcome"], rows[first]["library"]) == ("already_there", "added")
    assert (rows[second]["outcome"], rows[second]["library"]) == ("already_there", "looked")
    assert entries(on, "ethan")[untagged]["how"] == "grabbed"
    #? a look moves only a row still saying 'flagged'
    run(on.store.set_job_grant(first, untagged, library_ledger.LOOKED, was=library_ledger.FLAGGED))
    assert run(on.store.get_job(first))["library_grant"] == "added"


def test_an_apply_never_stars_back_an_album_its_holder_unstarred_or_put_away(on):
    """Review: nothing pinned ledger_restar's `state IN ('waiting', 'starred')` - without it an apply undid
    an unstar made in Amperfy, and starred a tombstone somebody had put away."""
    album = held(on)
    signed_in(on, "ethan")
    signed_in(on, "sam")
    starred_for(on, "ethan", album)
    starred_for(on, "sam", album)
    on.fake.starred("ethan").discard("nd-dummy")
    on.fake.starred("sam").discard("nd-dummy")
    work(on)
    with sqlite3.connect(on.path) as connection:
        connection.execute("UPDATE library_membership SET removed_why = 'dismissed' WHERE user = 'sam'")
    assert entries(on, "ethan")[album]["removed_why"] == "unstarred"

    assert run(on.store.ledger_restar(album)) == 0
    work(on)

    assert [(entries(on, user)[album]["state"], entries(on, user)[album]["removed_why"]) for user in ("ethan", "sam")] == \
        [("removed", "unstarred"), ("removed", "dismissed")]
    assert on.fake.starred("ethan") == on.fake.starred("sam") == set()


def test_a_star_read_back_under_a_new_navidrome_id_is_taken_so_unstarring_that_one_removes_it(on):
    """Review: nothing pinned the read-back taking a new id for a starred entry - without it, Navidrome
    re-iding the album and Ethan starring the new id in Amperfy left the old id kept, so his later unstar
    read as a star LOST and was starred straight back."""
    signed_in(on, "ethan")
    album = held(on)
    starred_for(on, "ethan", album)
    del on.fake.albums["nd-dummy"]
    on.fake.starred("ethan").clear()
    on.fake.add("nd-dummy-2", "rel-dummy")
    on.fake.starred("ethan").add("nd-dummy-2")

    work(on)
    entry = entries(on, "ethan")[album]
    assert (entry["state"], entry["navidrome_id"]) == ("starred", "nd-dummy-2")

    on.fake.starred("ethan").discard("nd-dummy-2")
    work(on)
    entry = entries(on, "ethan")[album]
    assert (entry["state"], entry["removed_why"]) == ("removed", "unstarred")
    assert on.fake.starred("ethan") == set()
