"""
Logins and roles (2.0.0-player.48, step 3 of the multi-user plan) - src/auth.py, src/users.py,
src/routes/auth.py - through the whole app start() builds (no lifespan), a real SQLite store, and a
fake Navidrome that checks Subsonic token auth for two accounts, james and ethan, as Navidrome does.

What these hold:

  - EVERY ROUTE IS DECIDED: the app's routes are exactly ROUTES' keys, each public, a user's or one
    permission's (2.0.0-player.61: request, edit, library, server or people - src/users.py require);
    with logins on every route but the public ones answers 401 without a session; THE WALK: every route
    of permission P answers 403 in NEEDS' words to an ordinary person given every OTHER category, and
    lets through one given only P (and an admin, and break-glass) - so granting one category never opens
    another's routes; a `request` route 403s when Get albums is taken away. A route added without
    deciding fails here.
  - Admins are Navidrome's admins (2.0.0-player.61): getUser's adminRole at the sign-in and every
    re-check (a change in Navidrome reaches deadwax at the next pass; Navidrome down keeps the role),
    exactly true or not admin, every session of a person agreeing; the sessions table gains its role
    column (every session made due for the re-check); DEADWAX_ADMINS is ignored and said so.
  - Off is today: no sign-in, /me the implicit admin with every permission, no mark on the pages, /docs
    there, login a 409.
  - Signing in is Navidrome's getUser with a token deadwax makes from a fresh salt - the name as typed,
    the identity lowercased (whatever case Navidrome answers with) - never the web login. A wrong password is a 401 that says so; Navidrome not
    answering a 503 that says so, and not counted; error 41 named. Reserved names never reach Navidrome,
    nor does anything reach an address describe_navidrome_url refuses (said as the address problem).
  - The cookie: `deadwax_session`, HttpOnly, SameSite=Strict, Path=/, Secure only over HTTPS (itself or
    X-Forwarded-Proto); its id unguessable and never stored - only its SHA-256; the token stored
    encrypted, never in the answer, the log or the database in the clear.
  - The throttle: three wrong passwords a minute per name, then 429 with Retry-After and Navidrome
    not asked; tries for one name in turn; a success clears it; other names untouched; its bounded
    record never flushed of a name it holds off by failing other names.
  - Sign-out and the re-check's error 40 end a session in memory AND the database (replayed after a
    restart); the next request says why; Navidrome down ends nothing; one ask per person a pass, and
    not again for five minutes; a key that changed ends it; expired sessions swept. Expiry slides with
    use - best effort: a failed write lets the request through, tried once, never lengthening it; a
    session held in memory is read again after a minute. The lifespan starts the re-check
    only with logins on, and it pauses a minute between passes.
  - AUTH_MODE as the app reads it (Config.logins_on) is on for a typo; a missing key said at start-up
    (by the lifespan itself).
  - Break-glass: DEADWAX_ADMIN_PASSWORD signs in `deadwax` (2.0.0-player.61 - `admin` until then, an
    ordinary Navidrome name now) with neither Navidrome nor the database, compared in constant time;
    ends with a new password, after 12 hours, and on sign-out; an old `admin` break-glass cookie ends.
  - Fail closed: no key, or no database, is a 503 on every protected route; the health check stays 200.
  - The first Navidrome admin's sign-in takes over what `local` saved; a user's or break-glass's doesn't,
    and a second admin's (an upgraded database) takes over nothing.
  - The settings show the three read-only, secrets as set or not; a PUT of one is refused; /docs is off.
"""

import asyncio
import hashlib
import json
import logging
import sqlite3
import sys
import time
from pathlib import Path
from types import SimpleNamespace
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi import HTTPException
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient
from starlette.routing import Mount

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import __version__, auth, permissions as granted  # noqa: E402
from src.api import navidrome_admin  # noqa: E402
from src.api.app import LOGINS_MARK, start  # noqa: E402
from src.api.musicbrainz_endpoint import ResponseCache  # noqa: E402
from src.config import DEADWAX_ADMINS_IGNORED, Config, describe_auth_mode  # noqa: E402
from src.store import JobStore  # noqa: E402
from src.users import (LOCAL_USER, NEEDS, NEEDS_PEOPLE, LABELS, PERMISSIONS, current_user, is_admin,  # noqa: E402
                       require)

SECRET = "0123456789abcdef0123456789abcdef-test-key"
GLASS = "break-the-glass-please"
PASSWORDS = {"james": "james-navidrome-pw", "ethan": "ethan-navidrome-pw"}
ME = "/deadwax/me"
LOGIN = "/deadwax/auth/login"
LOGOUT = "/deadwax/auth/logout"

#? Every route the app has, and whose it is: `public` answers without a session, `user` needs one, and
#? (2.0.0-player.61, in place of `admin`) a permission's name needs that permission - `request` Get albums,
#? `edit` Edit albums, `library` Look after the library, `server` Settings and the log, `people` People
#? (src/users.py require; an admin has them all). Adding a route means deciding here - the first test fails
#? until then. (`downloads`, Everyone's downloads, has no route of its own: the downloads routes check it
#? inside - tests/test_downloads_per_person.py.)
ROUTES = {
    ("GET", "/deadwax/health"): "public",
    ("POST", "/deadwax/auth/login"): "public",
    ("POST", "/deadwax/auth/logout"): "public",
    ("GET", "/player/"): "public",
    ("GET", "/player/index.html"): "public",
    ("GET", "/player/lab/"): "public",
    ("GET", "/player/lab/index.html"): "public",
    #? (2.0.0-player.66) the main page's addresses: a 307 to the app, GET and HEAD, public as the page was
    ("GET", "/"): "public",
    ("HEAD", "/"): "public",
    ("GET", "/index.html"): "public",
    ("HEAD", "/index.html"): "public",
    ("GET", "/deadwax/interface_logs/recent"): "server",
    ("GET", "/deadwax/interface_logs/interface_logs"): "server",
    ("GET", "/deadwax/search_musicbrainz/fully_search"): "user",
    ("GET", "/deadwax/search_musicbrainz/songs"): "user",
    #? (2.0.0-player.55) the app's Search's artists: a search, like /songs - MusicBrainz's data is nobody's own
    ("GET", "/deadwax/search_musicbrainz/artists"): "user",
    #? (2.0.0-player.56) search what's saved: MusicBrainz's answers kept on disk, searched - nobody's own either
    ("GET", "/deadwax/search_musicbrainz/saved"): "user",
    ("GET", "/deadwax/search_musicbrainz/discography"): "user",
    ("GET", "/deadwax/search_musicbrainz/releases"): "user",
    ("GET", "/deadwax/search_musicbrainz/release_group"): "user",
    ("GET", "/deadwax/search_musicbrainz/artist"): "user",
    ("GET", "/deadwax/search_musicbrainz/release"): "user",
    ("GET", "/deadwax/search_musicbrainz/ping"): "user",
    ("GET", "/deadwax/monitor_slskd/ping"): "user",
    ("POST", "/deadwax/download/store_state"): "user",
    ("POST", "/deadwax/download/find_candidates"): "request",
    ("POST", "/deadwax/download/enqueue"): "request",
    #? a user's own downloads, an admin's everyone's (2.0.0-player.49, step 4 - tests/test_downloads_per_person.py)
    ("GET", "/deadwax/download/jobs"): "user",
    ("POST", "/deadwax/download/jobs/{job_id}/cancel"): "user",
    ("POST", "/deadwax/download/jobs/{job_id}/retry"): "request",
    ("POST", "/deadwax/download/jobs/{job_id}/retry_same"): "request",
    ("POST", "/deadwax/download/jobs/clear"): "user",
    ("POST", "/deadwax/download/jobs/{job_id}/join"): "request",
    ("GET", "/deadwax/library/albums"): "user",
    ("GET", "/deadwax/library/owned"): "user",
    ("POST", "/deadwax/library/rescan"): "library",
    ("GET", "/deadwax/library/art"): "user",
    ("GET", "/deadwax/library/tracks"): "user",
    ("POST", "/deadwax/library/retag/preview"): "edit",
    ("POST", "/deadwax/library/retag/apply"): "edit",
    ("POST", "/deadwax/library/art/fetch"): "edit",
    ("POST", "/deadwax/library/lyrics/fetch"): "edit",
    ("GET", "/deadwax/library/lyrics"): "user",
    ("GET", "/deadwax/library/tracks/picture"): "user",
    ("GET", "/deadwax/library/disc_art"): "user",
    ("GET", "/deadwax/library/disc_art/navidrome"): "user",
    ("POST", "/deadwax/library/disc_art/fetch"): "edit",
    ("POST", "/deadwax/library/tags/preview"): "edit",
    ("POST", "/deadwax/library/tags/apply"): "edit",
    ("GET", "/deadwax/library/queue/new_imports"): "library",
    ("GET", "/deadwax/library/queue/summary"): "library",
    ("POST", "/deadwax/library/queue/ignore"): "library",
    ("POST", "/deadwax/library/queue/unignore"): "library",
    ("POST", "/deadwax/library/queue/reviewed"): "library",
    ("POST", "/deadwax/library/delete"): "library",
    ("GET", "/deadwax/library/deletion_summary"): "library",
    ("GET", "/deadwax/library/artist"): "user",
    ("GET", "/deadwax/library/artist/art"): "user",
    ("POST", "/deadwax/library/artist/images/preview"): "edit",
    ("POST", "/deadwax/library/artist/images/apply"): "edit",
    ("POST", "/deadwax/library/artist/refile/preview"): "library",
    ("POST", "/deadwax/library/artist/refile/apply"): "library",
    ("POST", "/deadwax/library/artist/search"): "edit",
    ("GET", "/deadwax/settings"): "server",
    ("GET", "/deadwax/settings/"): "server",
    ("PUT", "/deadwax/settings"): "server",
    ("PUT", "/deadwax/settings/"): "server",
    #? MusicBrainz's saved answers: their size, and Clear (2.0.0-player.54 - tests/test_musicbrainz_disk_cache.py)
    ("GET", "/deadwax/settings/musicbrainz_cache"): "server",
    ("POST", "/deadwax/settings/musicbrainz_cache/clear"): "server",
    ("GET", "/deadwax/navidrome/status"): "user",
    ("GET", "/deadwax/navidrome/album_index"): "user",
    ("GET", "/deadwax/navidrome/albums"): "user",
    ("GET", "/deadwax/navidrome/albums/{album_id}"): "user",
    ("GET", "/deadwax/navidrome/search"): "user",
    ("GET", "/deadwax/navidrome/artists"): "user",
    ("GET", "/deadwax/navidrome/artists/{artist_id}"): "user",
    ("GET", "/deadwax/navidrome/songs/{song_id}"): "user",
    ("GET", "/deadwax/navidrome/cover/{cover_id}"): "user",
    ("GET", "/deadwax/navidrome/stream/{song_id}"): "user",
    ("GET", "/deadwax/navidrome/scrub/{song_id}"): "user",
    #? (2.0.0-player.62) Normalization: Info's level of a song, and an album page's "measure this album"
    ("GET", "/deadwax/navidrome/level/{song_id}"): "user",
    ("POST", "/deadwax/navidrome/level/album/{album_id}"): "user",
    ("POST", "/deadwax/navidrome/scrobble/{song_id}"): "user",
    #? (2.0.0-player.57) the Library's Shuffle: an order of the asker's library (or the store), and its pages - theirs
    ("GET", "/deadwax/navidrome/shuffle"): "user",
    ("GET", "/deadwax/navidrome/shuffle/{token}"): "user",
    #? (2.0.0-player.58) playlists - each person's own, as their library is: the owner check is Navidrome's and
    #? deadwax's, per playlist
    ("GET", "/deadwax/navidrome/playlists"): "user",
    ("POST", "/deadwax/navidrome/playlists"): "user",
    ("GET", "/deadwax/navidrome/playlists/{playlist_id}"): "user",
    ("POST", "/deadwax/navidrome/playlists/{playlist_id}/add"): "user",
    ("POST", "/deadwax/navidrome/playlists/{playlist_id}/edit"): "user",
    ("POST", "/deadwax/navidrome/playlists/{playlist_id}/delete"): "user",
    #? (2.0.0-player.64) resume what was playing - each person's own queue, as their plays are
    ("GET", "/deadwax/navidrome/queue"): "user",
    ("POST", "/deadwax/navidrome/queue"): "user",
    ("POST", "/deadwax/navidrome/queue/at"): "user",
    ("GET", "/deadwax/me"): "user",
    ("GET", "/deadwax/me/preferences"): "user",
    ("PUT", "/deadwax/me/preferences"): "user",
    ("GET", "/deadwax/me/pins"): "user",
    ("PUT", "/deadwax/me/pins"): "user",
    ("POST", "/deadwax/me/pins/toggle"): "user",
    ("GET", "/deadwax/store/album"): "user",
    #? each user's own library - their starred albums - and the admin's "held by nobody" (2.0.0-player.51,
    #? step 5 - tests/test_personal_libraries.py)
    ("GET", "/deadwax/me/library"): "user",
    ("POST", "/deadwax/me/library/add"): "user",
    ("POST", "/deadwax/me/library/seen"): "user",
    ("POST", "/deadwax/me/library/dismiss"): "user",
    #? (2.0.0-player.52, step 6) Remove from my library - tests/test_player_as_you.py
    ("POST", "/deadwax/me/library/remove"): "user",
    #? (2.0.2) your own Navidrome password, changed as you - tests/test_own_password.py
    ("POST", "/deadwax/me/password"): "user",
    ("GET", "/deadwax/library/held"): "library",
    ("POST", "/deadwax/library/held/flags/{flag_id}/add"): "library",
    ("POST", "/deadwax/library/held/flags/{flag_id}/dismiss"): "library",
    #? (2.0.0-player.61) People: Navidrome's accounts, as the signed-in Navidrome admin - tests/test_people.py
    ("GET", "/deadwax/people"): "people",
    ("POST", "/deadwax/people/unlock"): "people",
    ("POST", "/deadwax/people/lock"): "people",
    ("POST", "/deadwax/people/create"): "people",
    ("POST", "/deadwax/people/{person_id}/password"): "people",
    ("POST", "/deadwax/people/{person_id}/admin"): "people",
    ("POST", "/deadwax/people/{person_id}/remove"): "people",
    ("POST", "/deadwax/people/forget"): "people",
    ("POST", "/deadwax/people/{person_id}/permissions"): "people",
}


def query(request: httpx.Request) -> dict:
    return {key: values[0] for key, values in parse_qs(urlparse(str(request.url)).query).items()}


def ok(**body) -> dict:
    return {"subsonic-response": {"status": "ok", "version": "1.16.1", "type": "navidrome", **body}}


def failed(code: int, message: str) -> dict:
    return {"subsonic-response": {"status": "failed", "version": "1.16.1", "error": {"code": code, "message": message}}}


class FakeNavidrome:
    """Navidrome's getUser as far as logins use it: token auth checked for real, accounts found whatever the
    case - and named in the answer as STORED (`stored`: an account kept as 'James' answers 'James'). Since
    2.0.0-player.61 its `adminRole` is each account's own Navidrome admin flag (`admins` - james, as on a
    household where the owner is Navidrome's admin; a test flips it, or answers `role` instead: missing, a
    string), and `/auth/login` answers as Navidrome's native sign-in does, with each account's id (`ids`) -
    what a sign-in reads for someone an admin gave a permission to (`logins` counts them)."""

    def __init__(self):
        self.passwords = dict(PASSWORDS)
        self.stored: dict[str, str] = {}
        self.admins: set[str] = {"james"}
        self.ids: dict[str, str] = {name: f"id-{name}" for name in PASSWORDS}
        self.role: dict[str, object] = {}   # an account's adminRole answered as this instead ("missing": none at all)
        self.seen: list[httpx.Request] = []
        self.logins: list[str] = []
        self.down = False
        self.code: int | None = None   # answer every call with this Subsonic error instead

    def handle(self, request: httpx.Request) -> httpx.Response:
        if request.url.path == navidrome_admin.LOGIN_PATH:
            return self.login(request)
        self.seen.append(request)
        if self.down:
            raise httpx.ConnectError("connection refused")
        if self.code is not None:
            return httpx.Response(200, json=failed(self.code, "as told"))
        asked = query(request)
        assert request.url.path == "/rest/getUser"
        assert "p" not in asked, "a password was sent - deadwax should only send tokens"
        account = next((name for name in self.passwords if name == asked.get("u", "").lower()), None)
        token = hashlib.md5((self.passwords.get(account, "") + asked.get("s", "")).encode()).hexdigest()
        if account is None or asked.get("t") != token:
            return httpx.Response(200, json=failed(40, "Wrong username or password"))
        if asked.get("username", "").lower() != account:
            return httpx.Response(200, json=failed(50, "not allowed"))
        user = {"username": self.stored.get(account, account), "adminRole": account in self.admins}
        if account in self.role:
            if self.role[account] == "missing":
                del user["adminRole"]
            else:
                user["adminRole"] = self.role[account]
        return httpx.Response(200, json=ok(user=user))

    def login(self, request: httpx.Request) -> httpx.Response:
        """Navidrome's POST /auth/login (server/auth.go doLogin): a JSON body, 401 for a wrong login."""
        if self.down:
            raise httpx.ConnectError("connection refused")
        body = json.loads(request.content)
        account = next((name for name in self.passwords if name == str(body.get("username", "")).lower()), None)
        self.logins.append(account or "?")
        if account is None or body.get("password") != self.passwords[account]:
            return httpx.Response(401, json={"error": "Invalid username or password"})
        return httpx.Response(200, json={"id": self.ids[account], "name": account.title(), "username": account,
                                         "isAdmin": account in self.admins, "token": f"jwt-{account}",
                                         "subsonicSalt": "abc", "subsonicToken": "def"})

    def asks(self) -> int:
        return len(self.seen)


def wire_native(handler, base: str = "http://navidrome:4533") -> None:
    """Navidrome's native API (src/api/navidrome_admin.py) answered by `handler`."""
    navidrome_admin._native.client = httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url=base,
                                                       follow_redirects=False)
    navidrome_admin._native.base = base


def run(coroutine):
    return asyncio.run(coroutine)


@pytest.fixture
def on(monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "AUTH_MODE", "on")
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", SECRET)
    monkeypatch.setattr(Config, "DEADWAX_ADMIN_PASSWORD", GLASS)
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    #? (2.0.0-player.49) logins need organizing on - copy or move, both folders set - or every route is a 503
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "copy")
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "slskd"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "library"))
    monkeypatch.setattr(auth, "throttle", auth.Throttle())
    auth.forget_sessions()
    granted.forget_all()
    fake = FakeNavidrome()
    auth.login_client.client = httpx.AsyncClient(transport=httpx.MockTransport(fake.handle),
                                                 base_url="http://navidrome:4533/rest")
    auth.login_client.base = "http://navidrome:4533/rest"
    wire_native(fake.handle)
    store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    store.init()
    app = start()
    app.state.store = store
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    yield SimpleNamespace(app=app, store=store, fake=fake, client=TestClient(app), path=tmp_path / "state" / "deadwax.db")
    auth.forget_sessions()
    granted.forget_all()
    run(auth.login_client.close_client())
    run(navidrome_admin.close_client())


def sign_in(client: TestClient, name: str, password: str, **headers) -> httpx.Response:
    return client.post(LOGIN, json={"username": name, "password": password}, headers=headers)


def signed_in(on, name: str) -> TestClient:
    """A client of its own, signed in as `name` (or the break-glass admin)."""
    client = TestClient(on.app)
    password = GLASS if name == auth.BREAK_GLASS_USER else PASSWORDS[name]
    assert sign_in(client, name, password).status_code == 200
    return client


def concrete(path: str) -> str:
    return path.replace("{job_id}", "1").replace("{album_id}", "al-1").replace("{artist_id}", "ar-1") \
        .replace("{song_id}", "so-1").replace("{cover_id}", "co-1").replace("{flag_id}", "1") \
        .replace("{token}", "tok-1").replace("{playlist_id}", "pl-1").replace("{person_id}", "id-ethan")


def app_routes(app) -> set[tuple[str, str]]:
    found = set()
    for route in app.routes:
        if isinstance(route, APIRoute):
            found |= {(method, route.path) for method in route.methods}
        elif not isinstance(route, Mount):
            found.add(("GET", route.path))
    return found


def needs(route: APIRoute) -> set:
    def calls(dependant):
        for dependency in dependant.dependencies:
            yield dependency.call
            yield from calls(dependency)
    return set(calls(route.dependant))


# ----------------------------------------------------------------- every route decided

def test_every_route_is_decided(on):
    """The app's routes are exactly the table's: a route nobody decided about fails here."""
    assert app_routes(on.app) == set(ROUTES)


def test_every_route_but_the_public_ones_needs_a_session(on):
    refused = {}
    for (method, path), side in sorted(ROUTES.items()):
        status = on.client.request(method, concrete(path)).status_code
        if side == "public":
            assert status != 401, (method, path)
        elif status != 401:
            refused[(method, path)] = status
    assert refused == {}


#? the five categories an admin can tick (src/permissions.py), and the routes' sides that are permissions
CATEGORIES = granted.CATEGORIES
SIDES = ("request", "edit", "library", "server", "people")
#? what the walk's stub endpoints answer: the guard let the request through to the route itself
REACHED = {"reached": True}


def stubbed(on):
    """The app with every route's own work replaced by a stub answering REACHED - so the walk sends every route
    a request, the stream and the writers included, and sees only what its dependencies decide. The public
    routes (the sign-in) are left as they are."""
    import inspect
    app = start()
    app.state.store = on.store
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    for route in app.routes:
        #? never the public ones: the sign-in must sign in
        if isinstance(route, APIRoute) and not any(ROUTES.get((method, route.path)) == "public" for method in route.methods):
            if inspect.iscoroutinefunction(route.dependant.call):
                async def stub(**_):
                    return REACHED
            else:
                def stub(**_):
                    return REACHED
            route.dependant.call = stub
    return app


def give(on, user: str, wanted: dict[str, bool]) -> None:
    """What an admin's Save in People writes for `user` (src/permissions.py set_for), bound to their account."""
    granted.set_for(on.store, user, on.fake.ids[user], {category: wanted.get(category, False) for category in CATEGORIES},
                    by="james")


def answered_by_the_route(response) -> bool:
    """Let through: the stub answered - with the route's own success status, a 202 for one that only starts
    work (2.0.0-player.62's /level/album) - or FastAPI refused the empty body the walk sends - never a 401/403."""
    return response.status_code in (200, 202, 422) and (response.status_code == 422 or response.json() == REACHED)


def test_the_walk_every_permissions_routes_refuse_every_other_category_and_open_to_their_own(on):
    """
    The spec's walk (Part 3), route by route: for every route of permission P - 403 in NEEDS' words to an
    ordinary person given every OTHER category (for `request`: everything else, Get albums taken away); let
    through to one given only P (with the default Get albums). Granting P never opens another category's
    route. An admin and break-glass are let through everywhere (People's own 409 for break-glass is
    tests/test_people.py's: here the routes are stubs).
    """
    app = stubbed(on)
    #? ethan, given something before he signs in: his account's id is read as he does, so grants are honoured
    give(on, "ethan", {"request": True, "edit": True})
    ethan = TestClient(app)
    assert sign_in(ethan, "ethan", PASSWORDS["ethan"]).status_code == 200
    assert on.fake.logins == ["ethan"]
    james = TestClient(app)
    assert sign_in(james, "james", PASSWORDS["james"]).status_code == 200
    glass = TestClient(app)
    assert sign_in(glass, auth.BREAK_GLASS_USER, GLASS).status_code == 200

    #? the words themselves, as a person reads them
    assert NEEDS.format(label=LABELS["edit"], user="ethan") == \
        "That needs Edit albums, which an admin hasn't given you. You're signed in as ethan."
    assert NEEDS_PEOPLE.format(user="ethan") == "That's People, which only Navidrome's admins can use. You're signed in as ethan."
    checked = {side: 0 for side in SIDES}
    for side in SIDES:
        routes = [(method, path) for (method, path), wanted in sorted(ROUTES.items()) if wanted == side]
        assert routes, side
        #? every other category - and for `request` itself, Get albums taken away
        give(on, "ethan", {category: category != side for category in CATEGORIES})
        for method, path in routes:
            response = ethan.request(method, concrete(path))
            assert response.status_code == 403, (side, method, path, response.status_code)
            words = NEEDS_PEOPLE.format(user="ethan") if side == "people" else NEEDS.format(label=LABELS[side], user="ethan")
            assert response.json()["detail"] == words, (method, path)
            checked[side] += 1
        #? only this one (and the default Get albums) - People can't be given: it is a Navidrome admin's
        if side != "people":
            give(on, "ethan", {"request": True, side: True})
            for method, path in routes:
                assert answered_by_the_route(ethan.request(method, concrete(path))), (side, method, path)
        for who in (james, glass):
            for method, path in routes:
                assert answered_by_the_route(who.request(method, concrete(path))), (side, method, path)
    assert all(checked.values()), checked


def test_an_ordinary_person_with_only_the_default_reaches_every_user_and_request_route(on):
    """Upgrading takes nothing away: everyone not an admin has Get albums, and every user route is theirs."""
    app = stubbed(on)
    ethan = TestClient(app)
    assert sign_in(ethan, "ethan", PASSWORDS["ethan"]).status_code == 200
    for (method, path), side in sorted(ROUTES.items()):
        if side in ("user", "request"):
            assert answered_by_the_route(ethan.request(method, concrete(path))), (method, path)
        elif side != "public":
            assert ethan.request(method, concrete(path)).status_code == 403, (method, path)


def test_every_route_asks_for_exactly_its_permission(on):
    """Read from the routes themselves: a user's route asks for a session and no permission; a permission's for
    exactly that one (src/users.py require, cached per permission); a public one for neither."""
    sides = {}
    for route in on.app.routes:
        if isinstance(route, APIRoute):
            for method in route.methods:
                sides[(method, route.path)] = route
    for key, side in ROUTES.items():
        route = sides.get(key)
        if route is None:
            continue
        asked = {getattr(call, "permission", None) for call in needs(route)} - {None}
        if side == "public":
            assert current_user not in needs(route) and not asked, key
        elif side == "user":
            assert current_user in needs(route) and not asked, key
        else:
            assert current_user in needs(route) and asked == {side}, key
            assert require(side) in needs(route), key


def test_a_user_reaches_what_is_theirs(on):
    ethan = signed_in(on, "ethan")
    assert ethan.get(ME).json() == {"user": "ethan", "admin": False, "auth": "on", "version": __version__,
                                    "permissions": ["request"], "permissions_unverified": False}
    assert ethan.get("/deadwax/me/preferences").status_code == 200
    assert ethan.get("/deadwax/me/pins").status_code == 200
    assert ethan.get("/deadwax/download/jobs").status_code == 200


def test_an_admin_reaches_the_admin_routes(on):
    james = signed_in(on, "james")
    assert james.get(ME).json() == {"user": "james", "admin": True, "auth": "on", "version": __version__,
                                    "permissions": list(PERMISSIONS), "permissions_unverified": False}
    assert james.get("/deadwax/settings").status_code == 200
    assert james.get("/deadwax/library/queue/new_imports").status_code == 200


# ----------------------------------------------------------------- off is today

def test_off_is_the_implicit_admin_with_no_sign_in(monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    client = TestClient(start())
    response = client.get(ME)
    assert response.json() == {"user": LOCAL_USER, "admin": True, "auth": "off", "version": __version__,
                               "permissions": list(PERMISSIONS), "permissions_unverified": False}
    assert "set-cookie" not in response.headers
    assert client.post(LOGIN, json={"username": "james", "password": "x"}).status_code == 409
    assert current_user() == LOCAL_USER and is_admin(LOCAL_USER) and not is_admin("james")


def test_off_leaves_the_pages_unmarked_and_the_api_pages_there(monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    client = TestClient(start())
    assert LOGINS_MARK not in client.get("/player/").text
    #? (2.0.0-player.66) `/` is no page: a redirect to the app, whose page carries the mark or not
    assert client.get("/", follow_redirects=False).status_code == 307
    assert client.get("/openapi.json").status_code == 200


def test_on_marks_the_pages_and_takes_the_api_pages_away(on):
    assert LOGINS_MARK in on.client.get("/player/").text
    assert LOGINS_MARK in on.client.get("/player/index.html").text
    #? (2.0.0-player.66) the main page's addresses mark nothing: they send the browser to the app, signed in or not
    for path in ("/", "/index.html"):
        moved = on.client.get(path, follow_redirects=False)
        assert moved.status_code == 307 and moved.headers["location"] == "/player/", path
    for path in ("/docs", "/redoc", "/openapi.json"):
        assert on.client.get(path).status_code == 404, path
    #? the static files stay public
    assert on.client.get("/styles/theme.css").status_code == 200


def test_an_unreadable_auth_mode_is_on():
    assert describe_auth_mode(None) == (False, None)
    assert describe_auth_mode(" OFF ") == (False, None)
    assert describe_auth_mode("On") == (True, None)
    on, problem = describe_auth_mode("yes")
    assert on and "expected on or off" in problem


def test_an_auth_mode_typo_leaves_deadwax_closed_and_says_so(on, monkeypatch, caplog):
    """What the app reads - Config.logins_on, not only describe_auth_mode - is on for a typo: AUTH_MODE=yes
    must never leave deadwax open while the log says it reads it as on."""
    monkeypatch.setattr(Config, "AUTH_MODE", "yes")
    assert Config.logins_on()
    assert TestClient(on.app).get(ME).status_code == 401
    assert TestClient(start()).get("/openapi.json").status_code == 404
    caplog.set_level(logging.INFO)
    Config.report_logins()
    assert "reads it as on" in caplog.text and "logins are on" in caplog.text


def test_the_implicit_user_is_a_name_nobody_signs_in_as():
    assert LOCAL_USER in auth.RESERVED_NAMES and auth.BREAK_GLASS_USER in auth.RESERVED_NAMES


def test_break_glass_is_deadwax_now_and_admin_an_ordinary_name():
    """(2.0.0-player.61) Navidrome's own `admin` account - a Navidrome admin, so deadwax's - signs in as itself."""
    assert auth.BREAK_GLASS_USER == "deadwax"
    assert auth.RESERVED_NAMES == {"local", "deadwax"}


# ----------------------------------------------------------------- signing in

def test_signing_in_asks_navidromes_getuser_with_a_token_of_deadwaxs_own(on):
    response = sign_in(on.client, "Ethan", PASSWORDS["ethan"])
    assert response.status_code == 200
    assert response.json() == {"user": "ethan", "admin": False, "auth": "on", "version": __version__,
                               "permissions": ["request"], "permissions_unverified": False}

    [asked] = on.fake.seen
    sent = query(asked)
    #? the name as typed, the token md5(password + a fresh salt), never the password
    assert sent["u"] == sent["username"] == "Ethan"
    assert sent["t"] == hashlib.md5((PASSWORDS["ethan"] + sent["s"]).encode()).hexdigest()
    assert len(sent["s"]) >= 16 and "p" not in sent
    #? the token and the salt never reach the page
    assert sent["t"] not in response.text and sent["s"] not in response.text
    assert sent["t"] not in response.headers["set-cookie"]
    assert on.client.get(ME).json()["user"] == "ethan"


def test_the_identity_is_lowercased_whatever_case_navidrome_answers_with(on):
    """Navidrome finds an account whatever case it is typed in, and names it in its answer as STORED -
    'James' here. The identity is still 'james': the pins, preferences, library and role are kept under
    it - trusting the answered name would have split one person into two."""
    on.fake.stored["james"] = "James"
    response = sign_in(on.client, "JAMES", PASSWORDS["james"])
    assert response.status_code == 200
    assert response.json()["user"] == "james" and response.json()["admin"] is True
    assert on.client.get(ME).json()["user"] == "james"
    with sqlite3.connect(on.path) as connection:
        assert connection.execute("SELECT user FROM sessions").fetchall() == [("james",)]


def test_navidromes_own_admin_flag_is_the_role(on):
    """(2.0.0-player.61, inverted) Navidrome's flag IS deadwax's role: james is its admin, ethan isn't - and
    made one in Navidrome, ethan's next sign-in is an admin's."""
    assert signed_in(on, "james").get(ME).json()["admin"] is True
    ethan = signed_in(on, "ethan")
    assert ethan.get(ME).json()["admin"] is False
    assert ethan.get("/deadwax/settings").status_code == 403
    on.fake.admins.add("ethan")
    again = signed_in(on, "ethan")
    assert again.get(ME).json()["admin"] is True and again.get("/deadwax/settings").status_code == 200


def test_a_wrong_password_is_said_plainly_and_sets_no_cookie(on):
    response = sign_in(on.client, "ethan", "not-it")
    assert response.status_code == 401
    assert response.json()["detail"] == auth.WRONG_LOGIN
    assert "set-cookie" not in response.headers
    assert on.client.get(ME).status_code == 401


def test_an_account_navidrome_doesnt_have_is_a_wrong_login(on):
    assert sign_in(on.client, "mallory", "whatever").json()["detail"] == auth.WRONG_LOGIN


def test_navidrome_not_answering_is_said_and_not_counted_against_the_name(on):
    on.fake.down = True
    response = sign_in(on.client, "ethan", PASSWORDS["ethan"])
    assert response.status_code == 503
    assert "Navidrome isn't answering" in response.json()["detail"]
    assert auth.throttle.wait("ethan") == 0 and "ethan" not in auth.throttle._failed


def test_an_account_navidrome_cant_check_by_token_is_named(on):
    on.fake.code = 41
    response = sign_in(on.client, "ethan", PASSWORDS["ethan"])
    assert response.status_code == 502 and "LDAP" in response.json()["detail"]


@pytest.mark.parametrize("url, said", [
    ("http://james:hunter2@navidrome:4533", "user name or password"),
    ("navidrome:4533", "scheme"),
])
def test_an_unusable_navidrome_url_gets_no_sign_in_nor_recheck_sent_to_it(on, monkeypatch, url, said):
    """The sign-in's client is held to describe_navidrome_url as the player's is (test_navidrome.py has the
    player's): an address with a login in it, or no scheme, is told as the address problem it is - not
    "Navidrome isn't answering" - and nobody's token is sent to it, by a sign-in or by the re-check.
    Nothing else stands in front of it (the settings tab checks only what is saved there)."""
    ethan = signed_in(on, "ethan")
    asked = on.fake.asks()
    built = []
    real = httpx.AsyncClient

    def client(**kwargs):
        #? any client the sign-in builds for the new address reaches the fake, so a token sent would show
        built.append(kwargs.get("base_url"))
        return real(transport=httpx.MockTransport(on.fake.handle), **kwargs)

    monkeypatch.setattr(httpx, "AsyncClient", client)
    monkeypatch.setattr(Config, "NAVIDROME_URL", url)

    response = sign_in(TestClient(on.app), "james", PASSWORDS["james"])
    assert response.status_code == 503
    detail = response.json()["detail"]
    assert "NAVIDROME_URL is unusable" in detail and said in detail and "isn't answering" not in detail
    assert "hunter2" not in detail

    run(auth.check_sessions(on.store, now=time.time() + auth.RECHECK_SECONDS + 1))
    assert ethan.get(ME).json()["user"] == "ethan"   # the address being wrong ends nobody's session
    assert on.fake.asks() == asked and built == []


def test_reserved_names_never_reach_navidrome(on):
    for name in ("local", "LOCAL"):
        response = sign_in(on.client, name, "anything")
        assert response.status_code == 400 and "keeps for itself" in response.json()["detail"]
    assert on.fake.asks() == 0


def test_an_empty_sign_in_is_refused_in_words(on):
    assert sign_in(on.client, "  ", "x").json()["detail"] == "Type your user name and your password."
    assert sign_in(on.client, "ethan", "").status_code == 400
    assert on.fake.asks() == 0


def test_a_sign_in_another_website_asks_for_is_refused(on):
    response = sign_in(on.client, "ethan", PASSWORDS["ethan"], origin="https://evil.example")
    assert response.status_code == 403
    assert on.fake.asks() == 0


# ----------------------------------------------------------------- the cookie and what is kept

def cookie_parts(response: httpx.Response) -> list[str]:
    return [part.strip() for part in response.headers["set-cookie"].split(";")]


def test_the_cookie_is_httponly_strict_and_long_lived_and_not_secure_over_http(on):
    parts = cookie_parts(sign_in(on.client, "ethan", PASSWORDS["ethan"]))
    name, _, value = parts[0].partition("=")
    assert name == auth.COOKIE == "deadwax_session"
    lowered = [part.lower() for part in parts]
    assert "httponly" in lowered and "samesite=strict" in lowered and "path=/" in lowered
    assert f"max-age={auth.COOKIE_MAX_AGE}" in lowered
    assert "secure" not in lowered
    #? unguessable, and nothing in it that would have it quoted
    assert value.startswith("s.") and len(value) >= 40 and value.replace("-", "").replace("_", "").replace(".", "").isalnum()


def test_the_cookie_is_secure_when_the_page_came_over_https(on):
    by_proxy = cookie_parts(sign_in(on.client, "ethan", PASSWORDS["ethan"], **{"x-forwarded-proto": "https"}))
    assert "secure" in [part.lower() for part in by_proxy]
    direct = TestClient(on.app, base_url="https://deadwax.example")
    assert "secure" in [part.lower() for part in cookie_parts(sign_in(direct, "ethan", PASSWORDS["ethan"]))]


def test_each_sign_in_is_a_new_unguessable_session(on):
    first = sign_in(TestClient(on.app), "ethan", PASSWORDS["ethan"]).cookies[auth.COOKIE]
    second = sign_in(TestClient(on.app), "ethan", PASSWORDS["ethan"]).cookies[auth.COOKIE]
    assert first != second


def test_the_database_keeps_a_hash_of_the_id_and_the_token_encrypted(on):
    response = sign_in(on.client, "Ethan", PASSWORDS["ethan"])
    raw = response.cookies[auth.COOKIE]
    sent = query(on.fake.seen[0])

    with sqlite3.connect(on.path) as connection:
        [(key, user, credential)] = connection.execute("SELECT id_hash, user, credential FROM sessions").fetchall()
    assert key == hashlib.sha256(raw.encode()).hexdigest() and raw not in key
    assert user == "ethan"
    for secret in (sent["t"], sent["s"], PASSWORDS["ethan"], raw):
        assert secret not in credential
    assert auth.unseal_credential(credential) == ("Ethan", sent["t"], sent["s"])
    #? the whole file, as bytes: nothing of the login in it in the clear
    whole = on.path.read_bytes()
    for secret in (sent["t"], PASSWORDS["ethan"], raw):
        assert secret.encode() not in whole


def test_neither_the_password_nor_the_token_reaches_the_log(on, caplog):
    caplog.set_level(logging.DEBUG)
    sign_in(on.client, "ethan", "a-wrong-one")
    sign_in(on.client, "ethan", PASSWORDS["ethan"])
    sign_in(on.client, auth.BREAK_GLASS_USER, GLASS)
    logged = caplog.text
    for sent in map(query, on.fake.seen):
        assert sent["t"] not in logged and sent["s"] not in logged
    for secret in ("a-wrong-one", PASSWORDS["ethan"], GLASS, SECRET):
        assert secret not in logged


def test_report_logins_says_what_is_set_and_never_a_secret(on, caplog):
    caplog.set_level(logging.INFO)
    Config.report_logins()
    assert "logins are on" in caplog.text and "Navidrome's admins are deadwax's admins" in caplog.text
    assert "break-glass admin: set" in caplog.text
    assert SECRET not in caplog.text and GLASS not in caplog.text


def test_report_logins_says_plainly_at_start_up_that_the_key_is_missing(on, monkeypatch, caplog):
    """The spec's "said plainly at start-up": an error naming DEADWAX_SECRET_KEY - and what it means (the
    pages load, the sign-in screen says why, every request else is a 503) - never quoting a value."""
    for value in (None, "too-short-a-key"):
        caplog.clear()
        caplog.set_level(logging.INFO)
        monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", value)
        Config.report_logins()
        [said] = [record.getMessage() for record in caplog.records
                  if record.levelno == logging.ERROR and "DEADWAX_SECRET_KEY" in record.getMessage()]
        assert "nobody can sign in" in said and "but the health check and the pages" in said
        assert "every page" not in said
        if value:
            assert value not in caplog.text


# ----------------------------------------------------------------- the throttle

def test_three_wrong_passwords_a_minute_then_deadwax_holds_off(on, monkeypatch):
    clock = [1000.0]
    monkeypatch.setattr(auth, "throttle", auth.Throttle(clock=lambda: clock[0]))
    for _ in range(3):
        assert sign_in(on.client, "ethan", "nope").status_code == 401
    asked = on.fake.asks()

    held = sign_in(on.client, "Ethan", PASSWORDS["ethan"])
    assert held.status_code == 429
    assert "Too many tries for ethan" in held.json()["detail"]
    assert int(held.headers["retry-after"]) == 60
    #? Navidrome wasn't asked: deadwax held off itself
    assert on.fake.asks() == asked
    #? another name is untouched
    assert sign_in(on.client, "james", PASSWORDS["james"]).status_code == 200

    clock[0] += 61
    assert sign_in(on.client, "ethan", PASSWORDS["ethan"]).status_code == 200
    #? a success clears the count
    assert "ethan" not in auth.throttle._failed


def test_a_wrong_break_glass_password_is_throttled_too(on):
    for _ in range(3):
        assert sign_in(on.client, auth.BREAK_GLASS_USER, "nope").status_code == 401
    held = sign_in(on.client, auth.BREAK_GLASS_USER, "nope again")
    assert held.status_code == 429 and "Too many tries for deadwax" in held.json()["detail"]


@pytest.mark.parametrize("body", [
    {"username": "james", "password": "p" * 1001 + "-the-password"},
    {"username": "j" * 201, "password": "the-password-itself"},
    {"username": "james", "password": ["the-password-itself"]},
])
def test_a_sign_in_deadwax_cant_read_never_echoes_the_password(on, body):
    """(2.0.0-player.65, the 2.0.0 release review) FastAPI's 422 lists every field it refused with its `input` - an
    over-long password came straight back in the answer. It is the People form's handling now: words, nothing sent."""
    from src.routes.auth import SIGN_IN_FORM

    response = on.client.post(LOGIN, json=body)
    assert response.status_code == 422 and response.json() == {"detail": SIGN_IN_FORM}
    assert "the-password" not in response.text


STRANGER, OWNER = ("203.0.113.9", 40000), ("192.168.3.20", 40000)


def test_a_held_off_address_learns_nothing_from_the_right_break_glass_password(on):
    """(2.0.0-player.65, the 2.0.0 release review) The slice's first version checked the break-glass password BEFORE
    the throttle's wait, so the right one answered 200 while every wrong one answered 429: an oracle, and guesses at
    the public name `deadwax` went unslowed. The wait comes first again - held off, the right password is a 429 too,
    word for word the wrong one's, and the count isn't cleared."""
    stranger = TestClient(on.app, client=STRANGER)
    for _ in range(3):
        assert sign_in(stranger, auth.BREAK_GLASS_USER, "a stranger's guess").status_code == 401
    wrong = sign_in(stranger, auth.BREAK_GLASS_USER, "another guess")
    right = sign_in(stranger, auth.BREAK_GLASS_USER, GLASS)
    assert wrong.status_code == right.status_code == 429
    assert right.json()["detail"] == wrong.json()["detail"] and auth.COOKIE not in right.cookies
    assert auth.throttle.wait(auth.break_glass_key(STRANGER[0])) > 0


def test_a_strangers_guesses_never_keep_the_owner_out_from_another_address(on):
    """(2.0.0-player.65) The name is public, so counted per name alone anyone's three wrong guesses a minute kept the
    way in shut - in the emergency it is for. Counted per name and address, the stranger's are the stranger's: the
    owner from another address signs in, and the stranger is still held off."""
    stranger, owner = TestClient(on.app, client=STRANGER), TestClient(on.app, client=OWNER)
    for _ in range(5):
        sign_in(stranger, auth.BREAK_GLASS_USER, "a stranger's guess")
    assert sign_in(stranger, auth.BREAK_GLASS_USER, GLASS).status_code == 429

    assert sign_in(owner, auth.BREAK_GLASS_USER, GLASS).status_code == 200
    assert auth.throttle.wait(auth.break_glass_key(OWNER[0])) == 0
    assert sign_in(stranger, auth.BREAK_GLASS_USER, GLASS).status_code == 429


def test_ordinary_names_are_still_counted_per_name_whatever_the_address(on):
    """Only break-glass is counted per address: a Navidrome account's three wrong passwords from anywhere hold off
    that name from everywhere, before Navidrome is asked (so it never locks the account) - as before 2.0.0-player.65.
    And a name typed to look like break-glass's key is an ordinary name, never sharing its count."""
    stranger, owner = TestClient(on.app, client=STRANGER), TestClient(on.app, client=OWNER)
    for _ in range(3):
        assert sign_in(stranger, "ethan", "nope").status_code == 401
    asked = on.fake.asks()
    assert sign_in(owner, "ethan", PASSWORDS["ethan"]).status_code == 429
    assert on.fake.asks() == asked

    for _ in range(3):
        sign_in(stranger, f"deadwax@{OWNER[0]}", "nope")
        sign_in(stranger, OWNER[0], "nope")
    assert sign_in(owner, auth.BREAK_GLASS_USER, GLASS).status_code == 200


def test_break_glass_counts_an_ipv6_connection_as_its_64():
    """A connection is usually handed a whole IPv6 /64 - counted per address, a guesser would have billions."""
    key = auth.break_glass_key
    assert key("2001:db8:1:2::1") == key("2001:db8:1:2:ffff:ffff:ffff:ffff") == (auth.BREAK_GLASS_USER, "2001:db8:1:2::/64")
    assert key("2001:db8:1:3::1") != key("2001:db8:1:2::1")
    assert key("::ffff:203.0.113.9") == key("203.0.113.9") == (auth.BREAK_GLASS_USER, "203.0.113.9")
    assert key(None) == key("") == (auth.BREAK_GLASS_USER, "")


@pytest.mark.parametrize("password, warned", [("short-one", True), ("x" * 15, True), ("x" * 16, False)])
def test_a_short_break_glass_password_is_warned_about_never_refused(on, monkeypatch, caplog, password, warned):
    """(2.0.0-player.65) shorter than 16 characters: one line at start-up and its row in the settings tab say so -
    and it still signs in, since it is the way in during an emergency. Neither ever quotes it."""
    import logging
    monkeypatch.setattr(Config, "DEADWAX_ADMIN_PASSWORD", password)
    with caplog.at_level(logging.WARNING, logger="deadwax"):
        Config.report_logins()
    said = [r.getMessage() for r in caplog.records if "DEADWAX_ADMIN_PASSWORD is shorter than 16" in r.getMessage()]
    assert len(said) == (1 if warned else 0) and all(password not in line for line in said)

    james = signed_in(on, "james")
    [group] = [group for group in james.get("/deadwax/settings").json()["groups"] if group["id"] == "logins"]
    row = {row["key"]: row for row in group["settings"]}["DEADWAX_ADMIN_PASSWORD"]
    assert (row["status"] == "error") is warned
    assert (row["detail"] or "").startswith("DEADWAX_ADMIN_PASSWORD is shorter than 16 characters") is warned
    assert sign_in(TestClient(on.app), auth.BREAK_GLASS_USER, password).status_code == 200


def test_failing_other_names_never_frees_a_name_deadwax_is_holding_off(on, monkeypatch):
    """The record of failures is bounded, but a name held off is never what makes room: one wrong
    password each for enough OTHER names used to push james's record out, so he could be tried again
    within the same minute - Navidrome asked, and the throttle's promise gone. (The cap shrunk to 5.)"""
    clock = [1000.0]
    monkeypatch.setattr(auth, "throttle", auth.Throttle(cap=5, clock=lambda: clock[0]))
    for _ in range(3):
        assert sign_in(on.client, "james", "guess").status_code == 401
    for i in range(50):
        assert sign_in(on.client, f"nobody{i}", "x").status_code == 401
        assert len(auth.throttle._failed) <= 5
    asked = on.fake.asks()
    assert [sign_in(on.client, "james", "guess").status_code for _ in range(3)] == [429, 429, 429]
    assert on.fake.asks() == asked


def test_the_throttles_record_makes_room_from_what_aged_out_and_what_isnt_held():
    clock = [0.0]
    throttle = auth.Throttle(cap=10, clock=lambda: clock[0])
    for name in ("gone1", "gone2"):
        throttle.failed(name)
    clock[0] = 100.0
    for _ in range(3):
        throttle.failed("james")
    for i in range(30):
        throttle.failed(f"nobody{i}")
        assert len(throttle._failed) <= 10
    assert throttle.wait("james") > 0
    #? what had left the window went; of the names under the limit, the oldest; the newest stays
    assert not {"gone1", "gone2", "nobody0"} & set(throttle._failed) and "nobody29" in throttle._failed

    #? every name held: the record goes past the cap rather than free one - each of these cost Navidrome
    #? three refusals, and leaves within the minute
    full = auth.Throttle(cap=2, clock=lambda: clock[0])
    for name in ("a", "b", "c"):
        for _ in range(3):
            full.failed(name)
    assert [full.wait(name) > 0 for name in ("a", "b", "c")] == [True, True, True]
    clock[0] += auth.THROTTLE_WINDOW
    full.failed("d")
    assert set(full._failed) == {"d"}


def test_tries_for_one_name_at_once_go_in_turn_and_are_all_counted(on):
    """Navidrome takes a moment to answer here, so six tries at once would all be out before any came
    back - and all six asked - were they not in turn."""
    async def slowly(request):
        await asyncio.sleep(0.02)
        return on.fake.handle(request)

    auth.login_client.client = httpx.AsyncClient(transport=httpx.MockTransport(slowly), base_url="http://navidrome:4533/rest")

    async def many():
        async def one():
            try:
                await auth.sign_in(on.store, "ethan", "nope")
            except HTTPException as e:
                return e.status_code
        return await asyncio.gather(*(one() for _ in range(6)))

    statuses = run(many())
    assert sorted(statuses) == [401, 401, 401, 429, 429, 429]
    assert on.fake.asks() == 3


# ----------------------------------------------------------------- sessions

def test_no_session_is_told_to_sign_in_and_a_stale_one_why(on):
    assert on.client.get(ME).json()["detail"] == auth.SIGN_IN
    on.client.cookies.set(auth.COOKIE, "s.not-a-session")
    assert on.client.get(ME).json()["detail"] == auth.SIGNED_OUT
    on.client.cookies.set(auth.COOKIE, "b.not-a-cookie")
    assert on.client.get(ME).json()["detail"] == auth.BREAK_GLASS_ENDED


def test_signing_out_ends_the_session_and_clears_the_cookie(on):
    ethan = signed_in(on, "ethan")
    raw = ethan.cookies[auth.COOKIE]
    #? used first, so it is HELD in memory: signing out must end it there, not only in the database
    assert ethan.get(ME).status_code == 200
    response = ethan.post(LOGOUT)
    assert response.status_code == 200
    lowered = [part.lower() for part in cookie_parts(response)]
    assert "max-age=0" in lowered and "path=/" in lowered
    assert on.store.session(auth.id_hash(raw)) is None
    replay = TestClient(on.app)
    replay.cookies.set(auth.COOKIE, raw)
    response = replay.get(ME)
    assert response.status_code == 401 and response.json()["detail"] == auth.SIGNED_OUT


def test_signing_out_of_nothing_is_fine(on):
    assert on.client.post(LOGOUT).status_code == 200


def test_the_session_survives_a_restart(on):
    ethan = signed_in(on, "ethan")
    auth.forget_sessions()   # what a restart forgets: everything held in memory
    assert ethan.get(ME).json()["user"] == "ethan"


def test_the_expiry_slides_with_use_and_a_session_left_unused_ends(on):
    ethan = signed_in(on, "ethan")
    raw = ethan.cookies[auth.COOKIE]
    key = auth.id_hash(raw)
    first = on.store.session(key)["expires_at"]

    later = time.time() + auth.TOUCH_SECONDS + 5
    assert auth.session_user(on.store, raw, now=later) == "ethan"
    assert on.store.session(key)["expires_at"] == pytest.approx(later + auth.SESSION_IDLE_SECONDS)
    assert on.store.session(key)["expires_at"] > first

    with pytest.raises(HTTPException) as gone:
        auth.session_user(on.store, raw, now=later + auth.SESSION_IDLE_SECONDS + 1)
    assert gone.value.status_code == 401 and gone.value.detail == auth.EXPIRED
    assert on.store.session(key) is None


def replayed_after_a_restart(on, raw: str) -> httpx.Response:
    """The cookie sent again once deadwax has forgotten everything in memory: the database's word alone."""
    auth.forget_sessions()
    replay = TestClient(on.app)
    replay.cookies.set(auth.COOKIE, raw)
    return replay.get(ME)


def test_the_recheck_ends_a_session_whose_password_changed_and_says_why(on):
    ethan = signed_in(on, "ethan")
    raw = ethan.cookies[auth.COOKIE]
    on.fake.passwords["ethan"] = "a-new-password"
    counts = run(auth.check_sessions(on.store, now=time.time() + auth.RECHECK_SECONDS + 1))
    assert counts["ended"] == 1
    response = ethan.get(ME)
    assert response.status_code == 401 and response.json()["detail"] == auth.LOGIN_GONE
    #? ended in the database too, so a restart doesn't bring it back
    assert on.store.session(auth.id_hash(raw)) is None
    assert replayed_after_a_restart(on, raw).status_code == 401
    #? and signing in with the new password works at once
    assert sign_in(ethan, "ethan", "a-new-password").status_code == 200


def test_the_recheck_ends_a_session_whose_account_is_gone(on):
    ethan = signed_in(on, "ethan")
    raw = ethan.cookies[auth.COOKIE]
    del on.fake.passwords["ethan"]
    run(auth.check_sessions(on.store, now=time.time() + auth.RECHECK_SECONDS + 1))
    assert ethan.get(ME).json()["detail"] == auth.LOGIN_GONE
    assert on.store.session(auth.id_hash(raw)) is None
    assert replayed_after_a_restart(on, raw).status_code == 401


def test_navidrome_down_ends_no_session(on):
    ethan = signed_in(on, "ethan")
    on.fake.down = True
    counts = run(auth.check_sessions(on.store, now=time.time() + auth.RECHECK_SECONDS + 1))
    assert counts == {"checked": 0, "ended": 0, "unanswered": 1, "expired": 0}
    assert ethan.get(ME).json()["user"] == "ethan"


def test_the_recheck_asks_about_each_person_once_a_pass_and_only_when_due(on):
    signed_in(on, "ethan"), signed_in(on, "ethan"), signed_in(on, "james")
    before = on.fake.asks()
    run(auth.check_sessions(on.store))   # nothing is due yet
    assert on.fake.asks() == before
    run(auth.check_sessions(on.store, now=time.time() + auth.RECHECK_SECONDS + 1))
    asked = [query(request)["u"] for request in on.fake.seen[before:]]
    assert sorted(asked) == ["ethan", "james"]


def test_a_session_navidrome_vouched_for_isnt_asked_about_again_for_five_minutes(on):
    ethan = signed_in(on, "ethan")
    key = auth.id_hash(ethan.cookies[auth.COOKIE])
    #? last vouched for over five minutes ago: due
    on.store.session_checked(key, time.time() - auth.RECHECK_SECONDS - 5)
    before = on.fake.asks()
    run(auth.check_sessions(on.store))
    assert on.fake.asks() == before + 1
    #? vouched for just now: not due again until five minutes on
    run(auth.check_sessions(on.store, now=time.time() + auth.RECHECK_SECONDS - 5))
    assert on.fake.asks() == before + 1


def test_the_recheck_sweeps_away_sessions_left_to_run_out(on):
    """A session whose cookie never comes back (a cleared browser, a lost phone) still goes - with the
    encrypted login it holds - once its 30 days are up."""
    ethan = signed_in(on, "ethan")
    key = auth.id_hash(ethan.cookies[auth.COOKIE])
    counts = run(auth.check_sessions(on.store, now=time.time() + auth.SESSION_IDLE_SECONDS + 1))
    assert counts["expired"] == 1 and on.store.session(key) is None


def test_a_session_held_in_memory_is_read_from_the_database_again_after_a_minute(on):
    """Held a minute at a time, so a session deleted behind deadwax's back - or a database gone away - is
    found within a minute, not at the next restart."""
    ethan = signed_in(on, "ethan")
    key = auth.id_hash(ethan.cookies[auth.COOKIE])
    assert ethan.get(ME).status_code == 200
    on.store.delete_session(key)
    assert ethan.get(ME).status_code == 200      # still held: within the minute
    with auth._lock:
        auth._held[key].loaded -= auth.CACHE_SECONDS + 1
    response = ethan.get(ME)
    assert response.status_code == 401 and response.json()["detail"] == auth.SIGNED_OUT


def test_the_recheck_runs_every_minute_and_outlives_a_pass_that_fails(monkeypatch):
    slept, passes = [], []

    async def sleep(seconds):
        slept.append(seconds)
        if len(slept) > 3:
            raise asyncio.CancelledError

    async def check(store):
        passes.append(store)
        if len(passes) == 1:
            raise sqlite3.OperationalError("a pass that fails")

    monkeypatch.setattr(auth, "asyncio", SimpleNamespace(sleep=sleep, CancelledError=asyncio.CancelledError))
    monkeypatch.setattr(auth, "check_sessions", check)
    with pytest.raises(asyncio.CancelledError):
        run(auth.run_session_checks("the store"))
    assert slept == [auth.CHECK_EVERY_SECONDS] * 4 == [60] * 4
    assert passes == ["the store"] * 3


def test_deadwax_starts_the_recheck_only_with_logins_on(monkeypatch, tmp_path, caplog):
    """The lifespan - which no other test enters - starts the re-check as a task with logins on (and a
    database), and not with them off: without it a changed password would never end a session. And it
    is what says at start-up that the key is missing (the spec's "said plainly at start-up" - the test
    above holds the words; this, that starting deadwax says them)."""
    from src.api import app as app_module
    started = []

    async def recheck(store):
        started.append(store)
        await asyncio.Event().wait()

    async def forever(*_args):
        await asyncio.Event().wait()

    async def nothing(*_args):
        return None

    class Client:
        #? (2.0.0-player.54) the lifespan attaches MusicBrainz's saved answers to the client's cache, and
        #? stops its refreshes as it ends
        cache = ResponseCache()

        async def close_client(self):
            return None

        async def stop_refreshing(self):
            return None

    monkeypatch.setattr(app_module, "MusicBrainzClient", Client)
    monkeypatch.setattr(app_module, "SlskdClient", Client)
    monkeypatch.setattr(app_module, "JobStore", lambda: JobStore(str(tmp_path / "deadwax.db")))
    monkeypatch.setattr(app_module, "seed_from_saved_scan", nothing)
    monkeypatch.setattr(app_module, "run_download_poller", forever)
    monkeypatch.setattr(app_module, "cleanup_logging", lambda: None)
    for client in (app_module.library.coverart_client, app_module.library.artist_images_client,
                   app_module.lrclib, app_module.navidrome_client, auth.login_client):
        monkeypatch.setattr(client, "close_client", nothing)
    monkeypatch.setattr(Config, "apply_overrides", lambda stored: None)
    #? no key: the re-check still starts (it needs logins on and a database), and start-up says why
    #? nobody can sign in
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", None)
    monkeypatch.setattr(auth, "run_session_checks", recheck)
    caplog.set_level(logging.INFO)

    async def lifespan_with(mode):
        monkeypatch.setattr(Config, "AUTH_MODE", mode)
        app = start()
        async with app_module.lifespan(app):
            await asyncio.sleep(0)
            return app.state.store

    store = run(lifespan_with("on"))
    assert started == [store]
    said = [record.getMessage() for record in caplog.records
            if record.levelno == logging.ERROR and "DEADWAX_SECRET_KEY" in record.getMessage()]
    assert len(said) == 1 and "nobody can sign in" in said[0]
    started.clear()
    caplog.clear()
    run(lifespan_with("off"))
    assert started == []
    assert "logins are off (AUTH_MODE)" in caplog.text and "DEADWAX_SECRET_KEY" not in caplog.text


def test_a_new_secret_key_ends_the_sessions_it_cant_open(on, monkeypatch):
    ethan = signed_in(on, "ethan")
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", "another-key-entirely-0123456789abcdef")
    run(auth.check_sessions(on.store, now=time.time() + auth.RECHECK_SECONDS + 1))
    assert ethan.get(ME).json()["detail"] == auth.KEY_CHANGED


def test_current_user_with_logins_on_and_no_request_is_signed_out(on):
    with pytest.raises(HTTPException) as refused:
        current_user()
    assert refused.value.status_code == 401


# ----------------------------------------------------------------- break-glass

def test_break_glass_signs_in_the_fixed_admin_without_navidrome_or_the_database(on):
    on.fake.down = True
    glass = TestClient(on.app)
    response = sign_in(glass, "Deadwax", GLASS)
    assert response.status_code == 200
    assert response.json() == {"user": "deadwax", "admin": True, "auth": "on", "version": __version__,
                               "permissions": list(PERMISSIONS), "permissions_unverified": False}
    assert on.fake.asks() == 0
    raw = glass.cookies[auth.COOKIE]
    assert raw.startswith("b.") and "=" not in raw
    assert f"max-age={auth.BREAK_GLASS_SECONDS}" in [part.lower() for part in cookie_parts(response)]

    on.store.available = False
    assert glass.get(ME).json()["user"] == "deadwax"
    assert glass.get("/deadwax/settings").status_code != 403


def test_break_glass_refuses_a_wrong_password_and_needs_one_set(on, monkeypatch):
    assert sign_in(on.client, "deadwax", "wrong").status_code == 401
    monkeypatch.setattr(Config, "DEADWAX_ADMIN_PASSWORD", None)
    assert sign_in(on.client, "deadwax", "").status_code == 400
    assert sign_in(on.client, "deadwax", "anything").json()["detail"] == auth.WRONG_LOGIN
    assert on.fake.asks() == 0


def test_break_glass_is_compared_in_constant_time():
    """By digest, so neither the password's length nor its first matching characters show in the time."""
    import inspect
    source = inspect.getsource(auth.break_glass_matches)
    assert "compare_digest" in source and "sha256" in source


def test_break_glass_ends_with_a_new_password_after_12_hours_and_on_sign_out(on, monkeypatch):
    glass = signed_in(on, "deadwax")
    raw = glass.cookies[auth.COOKIE]
    assert auth.break_glass_user(raw) == "deadwax"
    assert auth.break_glass_user(raw, now=time.time() + auth.BREAK_GLASS_SECONDS + 120) is None

    monkeypatch.setattr(Config, "DEADWAX_ADMIN_PASSWORD", "a-new-glass-password")
    assert glass.get(ME).json()["detail"] == auth.BREAK_GLASS_ENDED
    monkeypatch.setattr(Config, "DEADWAX_ADMIN_PASSWORD", GLASS)
    assert glass.get(ME).status_code == 200

    glass.post(LOGOUT)
    replay = TestClient(on.app)
    replay.cookies.set(auth.COOKIE, raw)
    assert replay.get(ME).status_code == 401


# ----------------------------------------------------------------- fail closed

def test_no_secret_key_is_a_503_everywhere_but_the_health_check(on, monkeypatch):
    for value in (None, "too-short"):
        monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", value)
        for response in (on.client.get(ME), sign_in(on.client, "ethan", PASSWORDS["ethan"])):
            assert response.status_code == 503 and "DEADWAX_SECRET_KEY" in response.json()["detail"]
        assert on.client.get("/deadwax/health").status_code == 200
        assert on.client.get("/player/").status_code == 200
    assert on.fake.asks() == 0


def test_no_database_is_a_503_and_the_health_check_stays_200(on):
    ethan = signed_in(on, "ethan")
    on.store.available = False
    response = ethan.get(ME)
    assert response.status_code == 503 and response.json()["detail"] == auth.NO_DATABASE
    assert sign_in(TestClient(on.app), "ethan", PASSWORDS["ethan"]).status_code == 503
    assert on.client.get("/deadwax/health").status_code == 200


def test_a_database_that_fails_mid_read_is_a_503(on, monkeypatch):
    ethan = signed_in(on, "ethan")
    auth.forget_sessions()

    def broken(_key):
        raise sqlite3.OperationalError("disk I/O error")

    monkeypatch.setattr(on.store, "session", broken)
    assert ethan.get(ME).status_code == 503


def test_a_failed_expiry_write_lets_the_request_through_and_only_a_read_is_a_503(on, monkeypatch, caplog):
    """A session that was READ stands: its expiry written forward is best effort. Refusing the request
    when that write failed (a full /config, a read-only volume, a lock past the timeout) stopped the music
    within ten minutes with a 503 saying the database couldn't be READ - found in review."""
    ethan = signed_in(on, "ethan")
    raw = ethan.cookies[auth.COOKIE]
    key = auth.id_hash(raw)
    assert ethan.get(ME).status_code == 200   # held in memory now
    expires = on.store.session(key)["expires_at"]
    tried = []

    def full(*args):
        tried.append(args)
        raise sqlite3.OperationalError("database or disk is full")

    monkeypatch.setattr(on.store, "touch_session", full)
    later = time.time() + auth.TOUCH_SECONDS + 5
    monkeypatch.setattr(auth, "time", SimpleNamespace(time=lambda: later, monotonic=time.monotonic))
    caplog.set_level(logging.WARNING)

    assert [ethan.get(ME).json().get("user") for _ in range(3)] == ["ethan"] * 3
    stream = ethan.get("/deadwax/navidrome/stream/so-1")
    assert stream.json().get("detail") != auth.NO_DATABASE
    #? tried once, not on every request (nor every byte range); said as a WRITE, not a read
    assert len(tried) == 1
    assert "could not write a session's new expiry" in caplog.text and "could not read" not in caplog.text
    #? the expiry stays where the database has it - a missed write never lengthens a session
    assert on.store.session(key)["expires_at"] == expires

    auth.forget_sessions()   # read from the database again (a minute on, or a restart): the same
    assert ethan.get(ME).json().get("user") == "ethan"
    assert len(tried) == 2

    #? ...and once the expiry it has passes, it ends as any other - held in memory or not (the expiry
    #? held there was never moved past the database's)
    monkeypatch.setattr(auth, "time", SimpleNamespace(time=lambda: expires + 1, monotonic=time.monotonic))
    gone = ethan.get(ME)
    assert gone.status_code == 401 and gone.json()["detail"] == auth.EXPIRED


# ----------------------------------------------------------------- what local saved

def test_the_first_admin_to_sign_in_takes_over_what_local_saved(on):
    run(on.store.set_user_preferences(LOCAL_USER, {"get_mode": "pick"}))
    run(on.store.write_pins(LOCAL_USER, [{"kind": "artist", "ref": "name:portishead", "label": "Portishead"}]))

    signed_in(on, "ethan")
    signed_in(on, auth.BREAK_GLASS_USER)
    #? neither a user nor the break-glass admin takes anything
    assert run(on.store.user_preferences(LOCAL_USER)) == {"get_mode": "pick"}

    signed_in(on, "james")
    assert run(on.store.user_preferences("james")) == {"get_mode": "pick"}
    assert [pin["ref"] for pin in run(on.store.pins("james"))] == ["name:portishead"]
    assert run(on.store.user_preferences(LOCAL_USER)) == {} and run(on.store.pins(LOCAL_USER)) == []


def test_preferences_are_each_persons_own(on):
    james, ethan = signed_in(on, "james"), signed_in(on, "ethan")
    assert ethan.put("/deadwax/me/preferences", json={"get_mode": "pick"}).json()["get_mode"] == "pick"
    assert james.get("/deadwax/me/preferences").json()["get_mode"] == "sources"


# ----------------------------------------------------------------- the settings

def test_the_settings_show_logins_read_only_and_no_secret(on):
    james = signed_in(on, "james")
    response = james.get("/deadwax/settings")
    assert SECRET not in response.text and GLASS not in response.text
    [group] = [group for group in response.json()["groups"] if group["id"] == "logins"]
    rows = {row["key"]: row for row in group["settings"]}
    assert list(rows) == ["AUTH_MODE", "DEADWAX_SECRET_KEY", "DEADWAX_ADMIN_PASSWORD"]
    for row in rows.values():
        assert row["editable"] is False and "environment" in row["locked_reason"]
    assert rows["DEADWAX_SECRET_KEY"]["value"] == rows["DEADWAX_ADMIN_PASSWORD"]["value"] == "set"
    assert rows["AUTH_MODE"]["effect"].startswith("Logins are on") and "Navidrome's admins" in rows["AUTH_MODE"]["effect"]
    assert "as deadwax" in rows["DEADWAX_ADMIN_PASSWORD"]["effect"]


def test_only_an_admin_can_move_navidrome_url_even_with_settings_and_the_log(on, monkeypatch):
    """(review) NAVIDROME_URL is where every person's own login goes and what says who the admins are: someone given
    Settings and the log who pointed it elsewhere would collect every login - and an admin's password at People's
    next unlock - and make themselves an admin. Locked for them, in words; the rest of the settings stay theirs."""
    from src.routes.settings import ADMINS_ONLY

    granted.set_for(on.store, "ethan", "id-ethan", {"request": True, "edit": False, "library": False, "downloads": False,
                                                   "server": True}, "james")
    ethan = signed_in(on, "ethan")
    assert "server" in ethan.get(ME).json()["permissions"]
    rows = {row["key"]: row for group in ethan.get("/deadwax/settings").json()["groups"] for row in group["settings"]}
    assert rows["NAVIDROME_URL"]["editable"] is False and rows["NAVIDROME_URL"]["locked_reason"] == ADMINS_ONLY["NAVIDROME_URL"]
    assert rows["MUSICBRAINZ_EMAIL"]["editable"] is True and rows["MUSICBRAINZ_EMAIL"]["locked_reason"] is None
    #? (2.0.0-player.65) slskd's address and key too: the key is full control of slskd
    for key in ("SLSKD_URL", "SLSKD_APIKEY"):
        assert rows[key]["editable"] is False and rows[key]["locked_reason"] == ADMINS_ONLY[key], key
    #? (second review) deadwax's own account too: set to ethan's own, People could no longer take ethan's grants away
    monkeypatch.setattr(Config, "NAVIDROME_USER", "shared")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "shared-password")
    for key in ("NAVIDROME_USER", "NAVIDROME_PASSWORD"):
        assert rows[key]["editable"] is False and rows[key]["locked_reason"] == ADMINS_ONLY[key], key
    monkeypatch.setattr(Config, "SLSKD_URL", "http://slskd:5030")
    monkeypatch.setattr(Config, "SLSKD_APIKEY", "env-apikey")
    for key, value in (("NAVIDROME_USER", "ethan"), ("NAVIDROME_USER", None), ("NAVIDROME_PASSWORD", "ethans-own"),
                       ("SLSKD_URL", "http://evil:5030"), ("SLSKD_APIKEY", "ethans-key")):
        response = ethan.put("/deadwax/settings", json=[{"key": key, "value": value}])
        assert response.status_code == 400 and ADMINS_ONLY[key] in response.json()["detail"], (key, value)
    assert on.store.stored_settings() == {} and Config.NAVIDROME_USER == "shared"
    for value in ("http://evil:4533", None):
        response = ethan.put("/deadwax/settings", json=[{"key": "NAVIDROME_URL", "value": value},
                                                       {"key": "NAVIDROME_PASSWORD", "value": "anything-at-all"}])
        assert response.status_code == 400 and ADMINS_ONLY["NAVIDROME_URL"] in response.json()["detail"], value
    assert on.store.stored_settings() == {} and Config.NAVIDROME_URL == "http://navidrome:4533"
    #? saving the address it already is changes nothing, so isn't refused
    same = ethan.put("/deadwax/settings", json=[{"key": "NAVIDROME_URL", "value": "http://navidrome:4533"}])
    assert same.status_code == 200
    #? an admin's tab shows it to change
    james = signed_in(on, "james")
    rows = {row["key"]: row for group in james.get("/deadwax/settings").json()["groups"] for row in group["settings"]}
    for key in ADMINS_ONLY:
        assert rows[key]["editable"] is True and rows[key]["locked_reason"] is None, key
    run(on.store.clear_setting("NAVIDROME_URL"))
    Config.apply_overrides(on.store.stored_settings())


@pytest.mark.parametrize("address, secret, environments", [
    ("SLSKD_URL", "SLSKD_APIKEY", ("http://slskd:5030", "env-apikey-3e9a")),
    ("NAVIDROME_URL", "NAVIDROME_PASSWORD", ("http://navidrome:4533", "env-password-8c1f")),
])
def test_even_an_admin_cannot_send_the_environments_secret_to_a_new_address_over_two_saves(
        on, monkeypatch, address, secret, environments):
    """(2.0.0-player.65, the 2.0.0 release review) A new address saved with any secret at all, then the secret alone
    reverted, put the environment's secret back at the new address. With logins on only an admin can save either -
    and an admin's saves are held to it too, so a stolen session or a page they were tricked into can't do it."""
    monkeypatch.setattr(Config, address, environments[0])
    monkeypatch.setattr(Config, secret, environments[1])
    monkeypatch.setattr(Config, "OVERRIDDEN", set())
    monkeypatch.setattr(Config, "ENV_VALUES", {})
    from src.api.slskd_endpoint import SlskdClient
    on.app.state.slskd_client = SlskdClient()  # the lifespan's job, which doesn't run here
    james = signed_in(on, "james")
    first = james.put("/deadwax/settings", json=[{"key": address, "value": "http://collector:9999"},
                                                 {"key": secret, "value": "junk"}])
    assert first.status_code == 200
    second = james.put("/deadwax/settings", json=[{"key": secret, "value": None}])
    assert second.status_code == 400 and f"{secret}: type the" in second.json()["detail"]
    assert getattr(Config, secret) == "junk" and getattr(Config, address) == "http://collector:9999"
    run(on.store.clear_setting(address))
    run(on.store.clear_setting(secret))
    Config.apply_overrides(on.store.stored_settings())


@pytest.mark.parametrize("address, secret, environments", [
    ("SLSKD_URL", "SLSKD_APIKEY", ("http://slskd:5030", "env-apikey-3e9a")),
    ("NAVIDROME_URL", "NAVIDROME_PASSWORD", ("http://navidrome:4533", "env-password-8c1f")),
])
def test_even_an_admin_cannot_send_the_environments_secret_to_a_new_address_the_other_way_round(
        on, monkeypatch, address, secret, environments):
    """The reverse order, as an admin with logins on: a secret typed and then reverted at the environment's address is
    fine - the environment's pair - and the address moved alone after it takes the secret again."""
    monkeypatch.setattr(Config, address, environments[0])
    monkeypatch.setattr(Config, secret, environments[1])
    monkeypatch.setattr(Config, "OVERRIDDEN", set())
    monkeypatch.setattr(Config, "ENV_VALUES", {})
    from src.api.slskd_endpoint import SlskdClient
    on.app.state.slskd_client = SlskdClient()  # the lifespan's job, which doesn't run here
    james = signed_in(on, "james")
    assert james.put("/deadwax/settings", json=[{"key": secret, "value": "junk"}]).status_code == 200
    assert james.put("/deadwax/settings", json=[{"key": secret, "value": None}]).status_code == 200
    assert getattr(Config, secret) == environments[1]
    moved = james.put("/deadwax/settings", json=[{"key": address, "value": "http://collector:9999"}])
    assert moved.status_code == 400 and f"{address}: type the" in moved.json()["detail"]
    assert "again with the new address" in moved.json()["detail"]
    assert getattr(Config, address) == environments[0]
    Config.apply_overrides(on.store.stored_settings())


@pytest.mark.parametrize("lost", ["unticked", "signed out", "demoted"])
def test_an_open_log_stream_closes_once_its_reader_may_no_longer_read_it(on, monkeypatch, lost):
    """(review) The router's guard runs as the stream opens; since .61 a permission, a role and a session can all go
    while it is open - so the stream asks again before each line, and the next line after is never sent."""
    from starlette.requests import Request
    from src.routes import interface_logs as route

    every = {"request": True, "edit": False, "library": False, "downloads": False}
    name = "ethan"
    if lost == "demoted":
        on.fake.admins.add(name)
    else:
        granted.set_for(on.store, name, "id-ethan", {**every, "server": True}, "james")
    raw = signed_in(on, name).cookies[auth.COOKIE]

    async def go():
        queue = asyncio.Queue()
        monkeypatch.setattr(route, "register_sse_client", lambda after, boot: (queue, [], 0))
        request = Request({"type": "http", "method": "GET", "path": "/deadwax/interface_logs/interface_logs",
                           "headers": [(b"cookie", f"{auth.COOKIE}={raw}".encode())], "query_string": b"", "app": on.app})
        lines = (await route.interface_logs(request, user=name, after=None, boot=None)).body_iterator
        assert await lines.__anext__() == ":\n\n"
        queue.put_nowait((1, '"before"'))
        assert "before" in await asyncio.wait_for(lines.__anext__(), 5)
        if lost == "unticked":
            await asyncio.to_thread(granted.set_for, on.store, name, "id-ethan", {**every, "server": False}, "james")
        elif lost == "signed out":
            await asyncio.to_thread(auth.end_user_sessions, on.store, name, auth.PASSWORD_RESET)
        else:
            await asyncio.to_thread(auth.set_role, on.store, name, False)
        queue.put_nowait((2, '"after"'))
        with pytest.raises(StopAsyncIteration):
            await asyncio.wait_for(lines.__anext__(), 5)

    run(go())


def test_the_downloads_routes_never_read_the_permissions_table_on_the_event_loop(on, monkeypatch):
    """(review) An ordinary person's Everyone's downloads check may read the table from SQLite (after a failed read,
    once a minute) - which must happen in a worker thread, never on the loop every stream shares."""
    ethan = signed_in(on, "ethan")
    granted.forget_all()
    real = on.store.permission_rows
    on_the_loop = []

    def watched():
        try:
            asyncio.get_running_loop()
            on_the_loop.append(True)
        except RuntimeError:
            on_the_loop.append(False)
        return real()

    monkeypatch.setattr(on.store, "permission_rows", watched)
    #? a stand-in that answers nothing, so the list is only the check: current_user and require run in threads anyway
    monkeypatch.setattr(on.app.state, "slskd_client", SimpleNamespace(get_downloads=_nothing), raising=False)
    assert ethan.get("/deadwax/download/jobs").status_code == 200
    assert on_the_loop and not any(on_the_loop)


async def _nothing(*args, **kwargs):
    return []


def test_a_login_setting_cant_be_saved_from_the_settings_tab(on):
    james = signed_in(on, "james")
    #? DEADWAX_ADMINS, removed, is no setting at all now - refused as any unknown key is
    for key in ("AUTH_MODE", "DEADWAX_ADMINS", "DEADWAX_SECRET_KEY", "DEADWAX_ADMIN_PASSWORD"):
        response = james.put("/deadwax/settings", json=[{"key": key, "value": "off"}])
        assert response.status_code == 400, key
    assert on.store.stored_settings() == {}


def test_a_stored_login_setting_is_never_laid_over_the_environment(monkeypatch):
    monkeypatch.setattr(Config, "ENV_VALUES", {})
    monkeypatch.setattr(Config, "AUTH_MODE", "on")
    Config.apply_overrides({"AUTH_MODE": "off", "DEADWAX_ADMINS": "mallory"})
    try:
        assert Config.AUTH_MODE == "on" and "AUTH_MODE" not in Config.OVERRIDDEN
    finally:
        Config.apply_overrides({})


def test_the_off_settings_say_logins_are_off(monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    body = TestClient(start()).get("/deadwax/settings").json()
    [group] = [group for group in body["groups"] if group["id"] == "logins"]
    assert group["settings"][0]["effect"].startswith("Logins are off")


def test_is_admin_with_logins_on(on):
    """A Navidrome admin as last read, and break-glass; anyone deadwax hasn't read - unknown - is not."""
    assert not is_admin("james")
    signed_in(on, "james")
    assert is_admin("james") and is_admin(auth.BREAK_GLASS_USER)
    signed_in(on, "ethan")
    assert not is_admin("ethan") and not is_admin(LOCAL_USER) and not is_admin("someone-else")


def test_the_sign_in_answer_is_what_me_answers(on):
    response = sign_in(on.client, "james", PASSWORDS["james"])
    assert response.json() == on.client.get(ME).json()
    assert json.dumps(response.json()).count("navidrome") == 0


# ----------------------------------------------------------------- deadwax's admins are Navidrome's (2.0.0-player.61)

def test_a_navidrome_admin_is_deadwaxs_admin_at_the_sign_in_and_an_ordinary_account_isnt(on):
    james = TestClient(on.app)
    answer = sign_in(james, "james", PASSWORDS["james"]).json()
    assert answer["admin"] is True and answer["permissions"] == list(PERMISSIONS)
    assert james.get(ME).json()["admin"] is True
    assert james.get("/deadwax/settings").status_code == 200
    ethan = TestClient(on.app)
    assert sign_in(ethan, "ethan", PASSWORDS["ethan"]).json()["admin"] is False
    assert ethan.get(ME).json()["admin"] is False
    assert ethan.get("/deadwax/settings").status_code == 403
    #? the role is on the session's row
    with sqlite3.connect(on.path) as connection:
        assert dict(connection.execute("SELECT user, admin FROM sessions").fetchall()) == {"james": 1, "ethan": 0}


def due(on) -> float:
    return time.time() + auth.RECHECK_SECONDS + 1


def test_a_flag_changed_in_navidrome_is_the_role_from_the_next_recheck_and_navidrome_down_keeps_it(on, caplog):
    caplog.set_level(logging.INFO)
    ethan = signed_in(on, "ethan")
    assert ethan.get("/deadwax/settings").status_code == 403
    on.fake.admins.add("ethan")
    run(auth.check_sessions(on.store, now=due(on)))
    assert ethan.get(ME).json()["admin"] is True and ethan.get("/deadwax/settings").status_code == 200
    assert "ethan is now a Navidrome admin, so deadwax's admin too" in caplog.text
    #? Navidrome down: the last word stands
    on.fake.down = True
    on.store.session_checked(auth.id_hash(ethan.cookies[auth.COOKIE]), 0)
    run(auth.check_sessions(on.store, now=due(on)))
    assert ethan.get(ME).json()["admin"] is True
    #? and taken away again
    on.fake.down = False
    on.fake.admins.discard("ethan")
    on.store.session_checked(auth.id_hash(ethan.cookies[auth.COOKIE]), 0)
    run(auth.check_sessions(on.store, now=due(on)))
    assert ethan.get(ME).json()["admin"] is False and ethan.get("/deadwax/settings").status_code == 403
    assert "ethan is no longer a Navidrome admin, so no longer deadwax's admin either" in caplog.text
    #? the database has it too: a restart reads the same
    auth.forget_sessions()
    assert ethan.get(ME).json()["admin"] is False


@pytest.mark.parametrize("answered", ["missing", "true", 1, None])
def test_an_admin_role_that_isnt_exactly_true_is_not_admin(on, answered):
    """Fail closed: an adminRole missing, a string, a number or null is an ordinary person's."""
    on.fake.role["james"] = answered
    james = signed_in(on, "james")
    assert james.get(ME).json()["admin"] is False
    assert james.get("/deadwax/settings").status_code == 403


def test_every_session_of_one_person_agrees_after_a_sign_in_on_a_second_device(on):
    phone = signed_in(on, "ethan")
    assert phone.get(ME).json()["admin"] is False     # held in memory now
    on.fake.admins.add("ethan")
    laptop = signed_in(on, "ethan")
    assert laptop.get(ME).json()["admin"] is True
    #? the phone's session - held in memory - is an admin's at its next request, and in the database
    assert phone.get(ME).json()["admin"] is True
    with sqlite3.connect(on.path) as connection:
        assert connection.execute("SELECT DISTINCT admin FROM sessions WHERE user = 'ethan'").fetchall() == [(1,)]


OLD_SESSIONS = """CREATE TABLE sessions (id_hash TEXT PRIMARY KEY, user TEXT NOT NULL, credential TEXT NOT NULL,
    created_at REAL NOT NULL, last_seen REAL NOT NULL, expires_at REAL NOT NULL, checked_at REAL NOT NULL)"""


def an_upgraded_database(tmp_path, sessions=()) -> Path:
    """A database as 2.0.0-player.60 left it: sessions with no role column, and the given rows in it."""
    path = tmp_path / "upgraded" / "deadwax.db"
    path.parent.mkdir(parents=True)
    with sqlite3.connect(path) as connection:
        connection.execute(OLD_SESSIONS)
        for user, raw in sessions:
            now = time.time()
            connection.execute("INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?)",
                               (auth.id_hash(raw), user, auth.seal_credential(user, auth.subsonic_token(PASSWORDS[user], "salt"), "salt"),
                                now, now, now + auth.SESSION_IDLE_SECONDS, now))
    return path


def test_the_sessions_table_gains_its_role_and_every_session_is_rechecked_first(on, tmp_path, caplog):
    """The migration: `admin` and `navidrome_id` added by hand, every checked_at set to 0 so the first pass reads
    everyone's flag - else a session from before read not-admin for up to its next check."""
    path = an_upgraded_database(tmp_path, [("james", "s.james-from-before")])
    store = JobStore(str(path))
    store.init()
    with sqlite3.connect(path) as connection:
        columns = {row[1] for row in connection.execute("PRAGMA table_info(sessions)")}
        assert {"admin", "navidrome_id"} <= columns
        assert connection.execute("SELECT checked_at, admin FROM sessions").fetchall() == [(0, 0)]
    on.app.state.store = store
    client = TestClient(on.app)
    client.cookies.set(auth.COOKIE, "s.james-from-before")
    assert client.get(ME).json()["admin"] is False          # unknown until read: not an admin
    caplog.set_level(logging.INFO)
    counts = run(auth.check_sessions(store))                # the first pass - due at once
    assert counts["checked"] == 1
    assert client.get(ME).json()["admin"] is True
    #? made again, an existing database is left as it is - the reset is once, as the column is made
    store.session_checked(auth.id_hash("s.james-from-before"), 123.0)
    store.init()
    with sqlite3.connect(path) as connection:
        assert connection.execute("SELECT checked_at FROM sessions").fetchall() == [(123.0,)]


def test_the_take_over_and_the_seed_wait_for_a_navidrome_admin(on):
    run(on.store.write_pins(LOCAL_USER, [{"kind": "artist", "ref": "name:portishead", "label": "Portishead"}]))
    signed_in(on, "ethan")
    assert [pin["ref"] for pin in run(on.store.pins(LOCAL_USER))] == ["name:portishead"]
    assert not on.store.library_seeded()
    on.fake.admins.add("ethan")
    signed_in(on, "ethan")
    assert [pin["ref"] for pin in run(on.store.pins("ethan"))] == ["name:portishead"]
    assert run(on.store.pins(LOCAL_USER)) == []


def test_the_leftovers_go_only_to_a_session_held_as_an_admins(on):
    """_take_over_leftovers, keyed on the session's own role after a restart: an ordinary person's request takes
    nothing, an admin's takes what `local` still holds."""
    ethan, james = signed_in(on, "ethan"), signed_in(on, "james")
    run(on.store.write_pins(LOCAL_USER, [{"kind": "artist", "ref": "name:tricky", "label": "Tricky"}]))
    auth.forget_sessions()                                  # a restart
    assert ethan.get(ME).status_code == 200
    assert [pin["ref"] for pin in run(on.store.pins(LOCAL_USER))] == ["name:tricky"]
    assert james.get(ME).status_code == 200
    assert run(on.store.pins(LOCAL_USER)) == [] and [pin["ref"] for pin in run(on.store.pins("james"))] == ["name:tricky"]


def test_a_second_navidrome_admins_first_sign_in_on_an_upgraded_install_takes_over_nothing(on):
    """James's install: `james` took over what `local` saved (under DEADWAX_ADMINS, at .48) and the store was
    seeded into his library, once ever. Upgraded, `james` is an ordinary user and Navidrome's `admin` - a person
    like any other - signs in for the first time: it takes over nothing and is seeded nothing."""
    run(on.store.write_pins(LOCAL_USER, [{"kind": "artist", "ref": "name:portishead", "label": "Portishead"}]))
    run(on.store.set_user_preferences(LOCAL_USER, {"get_mode": "pick"}))
    signed_in(on, "james")                                  # .48: the take-over, to james
    with sqlite3.connect(on.path) as connection:
        connection.execute("INSERT OR REPLACE INTO library_seed (id, user, seeded_at, albums) VALUES (1, 'james', 'then', 3)")
    taken = (run(on.store.pins("james")), run(on.store.user_preferences("james")))
    on.fake.admins = {"admin"}
    on.fake.passwords["admin"] = "navidrome-admin-pw"
    on.fake.ids["admin"] = "id-admin"
    admin = TestClient(on.app)
    answer = sign_in(admin, "admin", "navidrome-admin-pw").json()
    assert answer["user"] == "admin" and answer["admin"] is True
    assert run(on.store.pins("admin")) == [] and run(on.store.user_preferences("admin")) == {}
    assert (run(on.store.pins("james")), run(on.store.user_preferences("james"))) == taken
    with sqlite3.connect(on.path) as connection:
        assert connection.execute("SELECT user, seeded_at FROM library_seed").fetchall() == [("james", "then")]
        assert connection.execute("SELECT COUNT(*) FROM library_membership WHERE user = 'admin'").fetchone()[0] == 0
    #? james, signed in again, is an ordinary user now
    assert signed_in(on, "james").get(ME).json()["admin"] is False


# ----------------------------------------------------------------- a role People set is never undone by an older answer

def demoted_meanwhile(on, monkeypatch, name="ethan"):
    """check_login answering as Navidrome did, and People's demotion of `name` landing just after - before the
    caller (the re-check, a sign-in) has written what Navidrome said."""
    real = auth.check_login

    async def answered_then_demoted(username, token, salt):
        answer = await real(username, token, salt)
        on.fake.admins.discard(name)
        await asyncio.to_thread(auth.set_role, on.store, name, False)
        return answer

    monkeypatch.setattr(auth, "check_login", answered_then_demoted)


def test_the_recheck_never_undoes_a_role_people_set_while_navidrome_was_asked(on, monkeypatch):
    """(review) The re-check's getUser said adminRole true; People demoted them before the re-check wrote it - the
    demotion stands, in memory and in the database, rather than for ~5 minutes the other way."""
    on.fake.admins.add("ethan")
    ethan = signed_in(on, "ethan")
    assert ethan.get(ME).json()["admin"] is True
    demoted_meanwhile(on, monkeypatch)
    run(auth.check_sessions(on.store, now=time.time() + auth.RECHECK_SECONDS + 1))
    assert auth.role("ethan") is False and ethan.get(ME).json()["admin"] is False
    with sqlite3.connect(on.path) as connection:
        assert connection.execute("SELECT DISTINCT admin FROM sessions WHERE user = 'ethan'").fetchall() == [(0,)]


def test_a_sign_in_never_undoes_a_role_people_set_while_navidrome_was_asked(on, monkeypatch):
    on.fake.admins.add("ethan")
    phone = signed_in(on, "ethan")
    demoted_meanwhile(on, monkeypatch)
    laptop = signed_in(on, "ethan")
    assert laptop.get(ME).json()["admin"] is False and phone.get(ME).json()["admin"] is False
    with sqlite3.connect(on.path) as connection:
        assert connection.execute("SELECT DISTINCT admin FROM sessions WHERE user = 'ethan'").fetchall() == [(0,)]


def test_a_session_row_read_as_a_role_changed_holds_the_new_role(on, monkeypatch):
    """(review) _session read the row (admin) and People demoted them before it was held: the held session takes the
    demotion, not the row it read a moment before."""
    on.fake.admins.add("ethan")
    ethan = signed_in(on, "ethan")
    auth.forget_sessions()                                  # so the next request reads the row
    real = on.store.session

    def read_then_demoted(key):
        row = real(key)
        auth.set_role(on.store, "ethan", False)
        return row

    monkeypatch.setattr(on.store, "session", read_then_demoted)
    assert ethan.get(ME).json()["admin"] is False
    monkeypatch.setattr(on.store, "session", real)
    assert auth.role("ethan") is False and ethan.get(ME).json()["admin"] is False
    assert ethan.get("/deadwax/settings").status_code == 403


def a_session_row(store, user: str, raw: str) -> None:
    """A session row as 2.0.0-player.60 could have written it for `user` - an ordinary Navidrome account."""
    now = time.time()
    store.create_session(auth.id_hash(raw), user, auth.seal_credential(user, auth.subsonic_token("pw", "salt"), "salt"),
                         now, now + auth.SESSION_IDLE_SECONDS)


@pytest.mark.parametrize("name", sorted(auth.RESERVED_NAMES))
def test_a_session_row_under_a_reserved_name_ends_and_is_never_break_glass(on, name):
    """(review) Before .61 `deadwax` was an ordinary name - the natural one for NAVIDROME_USER's account - and its
    session rows last 30 days of use. Read after the upgrade, such a row must never stand for the break-glass admin
    (whose name it now is): it ends at its first request, in words, and is never an admin, nor asked about again."""
    a_session_row(on.store, name, "s.from-before-the-rename")
    stale = TestClient(on.app)
    stale.cookies.set(auth.COOKIE, "s.from-before-the-rename")
    response = stale.get(ME)
    assert response.status_code == 401 and response.json()["detail"] == auth.RESERVED_SESSION
    assert stale.get("/deadwax/settings").status_code == 401
    assert on.store.session(auth.id_hash("s.from-before-the-rename")) is None
    #? and the re-check never asks Navidrome as it
    a_session_row(on.store, name, "s.another-from-before")
    on.store.session_checked(auth.id_hash("s.another-from-before"), 0)
    asked = on.fake.asks()
    counts = run(auth.check_sessions(on.store, now=time.time() + auth.RECHECK_SECONDS + 1))
    assert counts["ended"] == 1 and on.store.session(auth.id_hash("s.another-from-before")) is None
    assert on.fake.asks() == asked


def test_the_upgrade_ends_reserved_sessions_and_moves_break_glasss_rows_to_its_new_name(on, tmp_path):
    """(review) The one-time step: a `deadwax` account's sessions and kept login from before go, and what break-glass
    kept under `admin` - pins, Getting albums settings, the downloads it asked for - moves to `deadwax`, so
    Navidrome's own `admin` account, signing in as itself for the first time, takes over none of it."""
    path = tmp_path / "upgraded" / "deadwax.db"
    store = JobStore(str(path))
    store.init()
    run(store.write_pins("admin", [{"kind": "artist", "ref": "name:tricky", "label": "Tricky"}]))
    run(store.set_user_preferences("admin", {"get_mode": "pick"}))
    job = run(store.create_job("bob", "d", [{"filename": "share\\Dummy\\01 Mysterons.flac", "size": 10}],
                               {"artist": "Portishead", "album": "Dummy", "tracks": []}, user="admin"))
    a_session_row(store, "deadwax", "s.deadwax-account")
    store.keep_credential("deadwax", auth.seal_credential("deadwax", auth.subsonic_token("pw", "salt"), "salt"), time.time())
    a_session_row(store, "james", "s.james-from-before")
    with sqlite3.connect(path) as connection:
        #? the sessions table as .60 had it: no role column
        rows = connection.execute("SELECT id_hash, user, credential, created_at, last_seen, expires_at, checked_at "
                                  "FROM sessions").fetchall()
        connection.execute("DROP TABLE sessions")
        connection.execute(OLD_SESSIONS)
        connection.executemany("INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?)", rows)
    store.init()
    with sqlite3.connect(path) as connection:
        assert connection.execute("SELECT user FROM sessions").fetchall() == [("james",)]
        assert connection.execute("SELECT COUNT(*) FROM user_credentials WHERE user = 'deadwax'").fetchone()[0] == 0
        for table in ("pins", "user_prefs", "job_requests"):
            assert connection.execute(f"SELECT DISTINCT user FROM {table}").fetchall() == [("deadwax",)], table
    assert run(store.requesters(job)) == ["deadwax"]
    assert run(store.pins("admin")) == [] and run(store.user_preferences("admin")) in ({}, None)


def test_an_old_admin_break_glass_cookie_ends_and_is_never_navidromes_admin(on):
    """A break-glass cookie made before the rename names `"u": "admin"`: break_glass_user refuses it, so it ends at
    its next request - and as a `b.` cookie it never reaches the session table, where Navidrome's `admin` is."""
    on.fake.admins.add("admin")
    on.fake.passwords["admin"] = "navidrome-admin-pw"
    on.fake.ids["admin"] = "id-admin"
    signed_in_admin = TestClient(on.app)
    assert sign_in(signed_in_admin, "admin", "navidrome-admin-pw").status_code == 200
    payload = {"u": "admin", "n": "old-nonce", "m": auth._password_mark(GLASS)}
    old = "b." + auth._fernet("break-glass").encrypt(json.dumps(payload).encode()).decode("ascii").rstrip("=")
    stale = TestClient(on.app)
    stale.cookies.set(auth.COOKIE, old)
    response = stale.get(ME)
    assert response.status_code == 401 and response.json()["detail"] == auth.BREAK_GLASS_ENDED
    assert stale.get("/deadwax/settings").status_code == 401
    assert auth.break_glass_user(old) is None


def test_deadwax_admins_still_set_is_said_once_and_grants_nobody_anything(on, monkeypatch, caplog):
    monkeypatch.setenv("DEADWAX_ADMINS", "ethan")
    caplog.set_level(logging.INFO)
    Config.report_logins()
    said = [record.getMessage() for record in caplog.records if "DEADWAX_ADMINS" in record.getMessage()]
    assert said == [DEADWAX_ADMINS_IGNORED] and "no longer reads it" in said[0]
    assert [record.levelno for record in caplog.records if "DEADWAX_ADMINS" in record.getMessage()] == [logging.ERROR]
    ethan = signed_in(on, "ethan")
    assert ethan.get(ME).json()["admin"] is False and ethan.get("/deadwax/settings").status_code == 403
    assert not hasattr(Config, "DEADWAX_ADMINS") and not hasattr(Config, "admins")
    monkeypatch.delenv("DEADWAX_ADMINS")
    caplog.clear()
    Config.report_logins()
    assert "DEADWAX_ADMINS" not in caplog.text


def test_break_glass_is_still_an_admin_with_every_permission(on):
    glass = signed_in(on, auth.BREAK_GLASS_USER)
    body = glass.get(ME).json()
    assert body["admin"] is True and body["permissions"] == list(PERMISSIONS)
    assert glass.get("/deadwax/settings").status_code == 200


# ----------------------------------------------------------------- the example files (2.0.0-player.65)

def test_the_example_files_logins_lines_lock_nobody_out():
    """(2.0.0-player.65, the 2.0.0 release review) The compose example offered `#- DEADWAX_SECRET_KEY=` to uncomment:
    an empty line under environment: beats .env, and then nobody can sign in. It names no such line now, says logins
    need ORGANIZE_MODE copy or move, and points at .env - which carries the three login lines, commented out."""
    repo = Path(__file__).resolve().parent.parent
    compose = (repo / "docker-compose.example.yml").read_text()
    env = (repo / ".env.example").read_text()
    lines = [line.strip() for line in compose.splitlines()]
    assert not any(line.lstrip("#").strip().startswith("- DEADWAX_SECRET_KEY") for line in lines)
    assert not any(line.lstrip("#").strip().startswith("- DEADWAX_ADMIN_PASSWORD") for line in lines)
    auth_line = next(line for line in lines if line.startswith("#- AUTH_MODE=on"))
    assert "ORGANIZE_MODE copy or move" in auth_line and ".env" in auth_line
    for line in ("#AUTH_MODE=on", "#DEADWAX_SECRET_KEY=", "#DEADWAX_ADMIN_PASSWORD="):
        assert line in env.splitlines(), line
    assert "ORGANIZE_MODE copy or move" in env
    #? the figures they quote: MusicBrainz's 200 MB about 1,100 artists (measured in .56); and (2.0.0-player.68) no
    #? prerelease history - a reader comes from 1.1.8 and never ran those versions
    for text in (compose, env):
        assert "2.0.0-player" not in text
        assert "4,000 artists" not in text and "1,100 artists" in text


def test_the_compose_example_has_no_line_that_is_only_a_comment():
    """(2.0.0-player.68) James: "I would like to avoid having lines that are just comments". Each comment sits on the
    line of the setting, mount or key it explains; the only lines starting with # are settings left commented out."""
    repo = Path(__file__).resolve().parent.parent
    for number, line in enumerate((repo / "docker-compose.example.yml").read_text().splitlines(), 1):
        text = line.strip()
        assert text, f"line {number} is blank"
        if text.startswith("#"):
            assert text.startswith("#- "), f"line {number} is only a comment: {text}"
