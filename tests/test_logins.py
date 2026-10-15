"""
Logins and roles (2.0.0-player.48, step 3 of the multi-user plan) - src/auth.py, src/users.py,
src/routes/auth.py - through the whole app start() builds (no lifespan), a real SQLite store, and a
fake Navidrome that checks Subsonic token auth for two accounts, james and ethan, as Navidrome does.

What these hold:

  - EVERY ROUTE IS DECIDED: the app's routes are exactly ROUTES' keys, each public, a user's or an
    admin's; with logins on every route but the public ones answers 401 without a session, every
    admin route answers 403 to a signed-in user (in words), and no user route asks for an admin. A
    route added without deciding fails here.
  - Off is today: no sign-in, /me the implicit admin, no mark on the pages, /docs there, login a 409.
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
  - Break-glass: DEADWAX_ADMIN_PASSWORD signs in `admin` with neither Navidrome nor the database,
    compared in constant time; ends with a new password, after 12 hours, and on sign-out.
  - Fail closed: no key, or no database, is a 503 on every protected route; the health check stays 200.
  - The first admin's sign-in takes over what `local` saved; a user's or break-glass's doesn't.
  - The settings show the four read-only, secrets as set or not; a PUT of one is refused; /docs is off.
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

from src import __version__, auth  # noqa: E402
from src.api.app import LOGINS_MARK, start  # noqa: E402
from src.config import Config, describe_auth_mode, parse_admins  # noqa: E402
from src.store import JobStore  # noqa: E402
from src.users import ADMIN_ONLY, LOCAL_USER, current_user, is_admin, require_admin  # noqa: E402

SECRET = "0123456789abcdef0123456789abcdef-test-key"
GLASS = "break-the-glass-please"
PASSWORDS = {"james": "james-navidrome-pw", "ethan": "ethan-navidrome-pw"}
ME = "/deadwax/me"
LOGIN = "/deadwax/auth/login"
LOGOUT = "/deadwax/auth/logout"

#? Every route the app has, and whose it is: `public` answers without a session, `user` needs one,
#? `admin` needs an admin's. Adding a route means deciding here - the first test fails until then.
ROUTES = {
    ("GET", "/deadwax/health"): "public",
    ("POST", "/deadwax/auth/login"): "public",
    ("POST", "/deadwax/auth/logout"): "public",
    ("GET", "/player/"): "public",
    ("GET", "/player/index.html"): "public",
    ("GET", "/player/lab/"): "public",
    ("GET", "/player/lab/index.html"): "public",
    ("GET", "/"): "public",
    ("GET", "/index.html"): "public",
    ("GET", "/deadwax/interface_logs/recent"): "admin",
    ("GET", "/deadwax/interface_logs/interface_logs"): "admin",
    ("GET", "/deadwax/search_musicbrainz/fully_search"): "user",
    ("GET", "/deadwax/search_musicbrainz/discography"): "user",
    ("GET", "/deadwax/search_musicbrainz/releases"): "user",
    ("GET", "/deadwax/search_musicbrainz/release_group"): "user",
    ("GET", "/deadwax/search_musicbrainz/artist"): "user",
    ("GET", "/deadwax/search_musicbrainz/release"): "user",
    ("GET", "/deadwax/search_musicbrainz/ping"): "user",
    ("GET", "/deadwax/monitor_slskd/ping"): "user",
    ("POST", "/deadwax/download/store_state"): "user",
    ("POST", "/deadwax/download/find_candidates"): "user",
    ("POST", "/deadwax/download/enqueue"): "user",
    #? everyone's downloads, for everyone, until step 4 makes requests per person - the one known gap
    ("GET", "/deadwax/download/jobs"): "user",
    ("POST", "/deadwax/download/jobs/{job_id}/cancel"): "user",
    ("POST", "/deadwax/download/jobs/{job_id}/retry"): "user",
    ("POST", "/deadwax/download/jobs/{job_id}/retry_same"): "user",
    ("POST", "/deadwax/download/jobs/clear"): "user",
    ("GET", "/deadwax/library/albums"): "user",
    ("GET", "/deadwax/library/owned"): "user",
    ("POST", "/deadwax/library/rescan"): "admin",
    ("GET", "/deadwax/library/art"): "user",
    ("GET", "/deadwax/library/tracks"): "user",
    ("POST", "/deadwax/library/retag/preview"): "admin",
    ("POST", "/deadwax/library/retag/apply"): "admin",
    ("POST", "/deadwax/library/art/fetch"): "admin",
    ("POST", "/deadwax/library/lyrics/fetch"): "admin",
    ("GET", "/deadwax/library/lyrics"): "user",
    ("GET", "/deadwax/library/tracks/picture"): "user",
    ("GET", "/deadwax/library/disc_art"): "user",
    ("GET", "/deadwax/library/disc_art/navidrome"): "user",
    ("POST", "/deadwax/library/disc_art/fetch"): "admin",
    ("POST", "/deadwax/library/tags/preview"): "admin",
    ("POST", "/deadwax/library/tags/apply"): "admin",
    ("GET", "/deadwax/library/queue/new_imports"): "admin",
    ("GET", "/deadwax/library/queue/summary"): "admin",
    ("POST", "/deadwax/library/queue/ignore"): "admin",
    ("POST", "/deadwax/library/queue/unignore"): "admin",
    ("POST", "/deadwax/library/queue/reviewed"): "admin",
    ("POST", "/deadwax/library/delete"): "admin",
    ("GET", "/deadwax/library/deletion_summary"): "admin",
    ("GET", "/deadwax/library/artist"): "user",
    ("GET", "/deadwax/library/artist/art"): "user",
    ("POST", "/deadwax/library/artist/images/preview"): "admin",
    ("POST", "/deadwax/library/artist/images/apply"): "admin",
    ("POST", "/deadwax/library/artist/refile/preview"): "admin",
    ("POST", "/deadwax/library/artist/refile/apply"): "admin",
    ("POST", "/deadwax/library/artist/search"): "admin",
    ("GET", "/deadwax/settings"): "admin",
    ("GET", "/deadwax/settings/"): "admin",
    ("PUT", "/deadwax/settings"): "admin",
    ("PUT", "/deadwax/settings/"): "admin",
    ("GET", "/deadwax/navidrome/status"): "user",
    ("GET", "/deadwax/navidrome/albums"): "user",
    ("GET", "/deadwax/navidrome/albums/{album_id}"): "user",
    ("GET", "/deadwax/navidrome/search"): "user",
    ("GET", "/deadwax/navidrome/artists"): "user",
    ("GET", "/deadwax/navidrome/artists/{artist_id}"): "user",
    ("GET", "/deadwax/navidrome/songs/{song_id}"): "user",
    ("GET", "/deadwax/navidrome/cover/{cover_id}"): "user",
    ("GET", "/deadwax/navidrome/stream/{song_id}"): "user",
    ("GET", "/deadwax/navidrome/scrub/{song_id}"): "user",
    ("POST", "/deadwax/navidrome/scrobble/{song_id}"): "user",
    ("GET", "/deadwax/me"): "user",
    ("GET", "/deadwax/me/preferences"): "user",
    ("PUT", "/deadwax/me/preferences"): "user",
    ("GET", "/deadwax/me/pins"): "user",
    ("PUT", "/deadwax/me/pins"): "user",
    ("POST", "/deadwax/me/pins/toggle"): "user",
    ("GET", "/deadwax/store/album"): "user",
}


def query(request: httpx.Request) -> dict:
    return {key: values[0] for key, values in parse_qs(urlparse(str(request.url)).query).items()}


def ok(**body) -> dict:
    return {"subsonic-response": {"status": "ok", "version": "1.16.1", "type": "navidrome", **body}}


def failed(code: int, message: str) -> dict:
    return {"subsonic-response": {"status": "failed", "version": "1.16.1", "error": {"code": code, "message": message}}}


class FakeNavidrome:
    """Navidrome's getUser as far as logins use it: token auth checked for real, accounts found whatever the
    case - and named in the answer as STORED (`stored`: an account kept as 'James' answers 'James')."""

    def __init__(self):
        self.passwords = dict(PASSWORDS)
        self.stored: dict[str, str] = {}
        self.seen: list[httpx.Request] = []
        self.down = False
        self.code: int | None = None   # answer every call with this Subsonic error instead

    def handle(self, request: httpx.Request) -> httpx.Response:
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
        #? Navidrome's own admin flag set for ethan - deadwax must never read it
        return httpx.Response(200, json=ok(user={"username": self.stored.get(account, account), "adminRole": account == "ethan"}))

    def asks(self) -> int:
        return len(self.seen)


def run(coroutine):
    return asyncio.run(coroutine)


@pytest.fixture
def on(monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "AUTH_MODE", "on")
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", SECRET)
    monkeypatch.setattr(Config, "DEADWAX_ADMINS", " James , someone-else ")
    monkeypatch.setattr(Config, "DEADWAX_ADMIN_PASSWORD", GLASS)
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(auth, "throttle", auth.Throttle())
    auth.forget_sessions()
    fake = FakeNavidrome()
    auth.login_client.client = httpx.AsyncClient(transport=httpx.MockTransport(fake.handle),
                                                 base_url="http://navidrome:4533/rest")
    auth.login_client.base = "http://navidrome:4533/rest"
    store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    store.init()
    app = start()
    app.state.store = store
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    yield SimpleNamespace(app=app, store=store, fake=fake, client=TestClient(app), path=tmp_path / "state" / "deadwax.db")
    auth.forget_sessions()
    run(auth.login_client.close_client())


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
        .replace("{song_id}", "so-1").replace("{cover_id}", "co-1")


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


def test_every_admin_route_answers_a_user_403_in_words(on):
    ethan = signed_in(on, "ethan")
    for (method, path), side in sorted(ROUTES.items()):
        if side != "admin":
            continue
        response = ethan.request(method, concrete(path))
        assert response.status_code == 403, (method, path, response.status_code)
        assert response.json()["detail"] == ADMIN_ONLY.format(user="ethan")


def test_no_user_route_asks_for_an_admin_and_every_admin_route_does(on):
    sides = {}
    for route in on.app.routes:
        if isinstance(route, APIRoute):
            for method in route.methods:
                sides[(method, route.path)] = route
    for key, side in ROUTES.items():
        route = sides.get(key)
        if route is None:
            continue
        if side == "admin":
            assert require_admin in needs(route), key
        elif side == "user":
            assert current_user in needs(route) and require_admin not in needs(route), key
        else:
            assert current_user not in needs(route), key


def test_a_user_reaches_what_is_theirs(on):
    ethan = signed_in(on, "ethan")
    assert ethan.get(ME).json() == {"user": "ethan", "admin": False, "auth": "on", "version": __version__}
    assert ethan.get("/deadwax/me/preferences").status_code == 200
    assert ethan.get("/deadwax/me/pins").status_code == 200
    assert ethan.get("/deadwax/download/jobs").status_code == 200


def test_an_admin_reaches_the_admin_routes(on):
    james = signed_in(on, "james")
    assert james.get(ME).json() == {"user": "james", "admin": True, "auth": "on", "version": __version__}
    assert james.get("/deadwax/settings").status_code == 200
    assert james.get("/deadwax/library/queue/new_imports").status_code == 200


# ----------------------------------------------------------------- off is today

def test_off_is_the_implicit_admin_with_no_sign_in(monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    client = TestClient(start())
    response = client.get(ME)
    assert response.json() == {"user": LOCAL_USER, "admin": True, "auth": "off", "version": __version__}
    assert "set-cookie" not in response.headers
    assert client.post(LOGIN, json={"username": "james", "password": "x"}).status_code == 409
    assert current_user() == LOCAL_USER and is_admin(LOCAL_USER) and not is_admin("james")


def test_off_leaves_the_pages_unmarked_and_the_api_pages_there(monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    client = TestClient(start())
    assert LOGINS_MARK not in client.get("/player/").text
    assert LOGINS_MARK not in client.get("/").text
    assert client.get("/openapi.json").status_code == 200


def test_on_marks_the_pages_and_takes_the_api_pages_away(on):
    assert LOGINS_MARK in on.client.get("/player/").text
    assert LOGINS_MARK in on.client.get("/").text
    assert LOGINS_MARK in on.client.get("/index.html").text
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


def test_the_admin_list_is_lowercased_and_trimmed():
    assert parse_admins(" James ,, Ethan ") == {"james", "ethan"}
    assert parse_admins(None) == frozenset()


def test_the_implicit_user_is_a_name_nobody_signs_in_as():
    assert LOCAL_USER in auth.RESERVED_NAMES and auth.BREAK_GLASS_USER in auth.RESERVED_NAMES


# ----------------------------------------------------------------- signing in

def test_signing_in_asks_navidromes_getuser_with_a_token_of_deadwaxs_own(on):
    response = sign_in(on.client, "Ethan", PASSWORDS["ethan"])
    assert response.status_code == 200
    assert response.json() == {"user": "ethan", "admin": False, "auth": "on", "version": __version__}

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
    'James' here. The identity is still 'james': DEADWAX_ADMINS is lowercased, and the pins and
    preferences are kept under it - trusting the answered name would have made James no admin."""
    on.fake.stored["james"] = "James"
    response = sign_in(on.client, "JAMES", PASSWORDS["james"])
    assert response.status_code == 200
    assert response.json()["user"] == "james" and response.json()["admin"] is True
    assert on.client.get(ME).json()["user"] == "james"
    with sqlite3.connect(on.path) as connection:
        assert connection.execute("SELECT user FROM sessions").fetchall() == [("james",)]


def test_navidromes_own_admin_flag_is_never_used(on):
    """The fake says ethan is a Navidrome admin; DEADWAX_ADMINS doesn't name him, so he isn't deadwax's."""
    assert signed_in(on, "ethan").get(ME).json()["admin"] is False


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
    assert "logins are on" in caplog.text and "james" in caplog.text
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
        assert sign_in(on.client, "admin", "nope").status_code == 401
    assert sign_in(on.client, "admin", GLASS).status_code == 429


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
        async def close_client(self):
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
    response = sign_in(glass, "Admin", GLASS)
    assert response.status_code == 200
    assert response.json() == {"user": "admin", "admin": True, "auth": "on", "version": __version__}
    assert on.fake.asks() == 0
    raw = glass.cookies[auth.COOKIE]
    assert raw.startswith("b.") and "=" not in raw
    assert f"max-age={auth.BREAK_GLASS_SECONDS}" in [part.lower() for part in cookie_parts(response)]

    on.store.available = False
    assert glass.get(ME).json()["user"] == "admin"
    assert glass.get("/deadwax/settings").status_code != 403


def test_break_glass_refuses_a_wrong_password_and_needs_one_set(on, monkeypatch):
    assert sign_in(on.client, "admin", "wrong").status_code == 401
    monkeypatch.setattr(Config, "DEADWAX_ADMIN_PASSWORD", None)
    assert sign_in(on.client, "admin", "").status_code == 400
    assert sign_in(on.client, "admin", "anything").json()["detail"] == auth.WRONG_LOGIN
    assert on.fake.asks() == 0


def test_break_glass_is_compared_in_constant_time():
    """By digest, so neither the password's length nor its first matching characters show in the time."""
    import inspect
    source = inspect.getsource(auth.break_glass_matches)
    assert "compare_digest" in source and "sha256" in source


def test_break_glass_ends_with_a_new_password_after_12_hours_and_on_sign_out(on, monkeypatch):
    glass = signed_in(on, "admin")
    raw = glass.cookies[auth.COOKIE]
    assert auth.break_glass_user(raw) == "admin"
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
    signed_in(on, "admin")
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
    assert list(rows) == ["AUTH_MODE", "DEADWAX_ADMINS", "DEADWAX_SECRET_KEY", "DEADWAX_ADMIN_PASSWORD"]
    for row in rows.values():
        assert row["editable"] is False and "environment" in row["locked_reason"]
    assert rows["DEADWAX_SECRET_KEY"]["value"] == rows["DEADWAX_ADMIN_PASSWORD"]["value"] == "set"
    assert "james, someone-else" in rows["DEADWAX_ADMINS"]["effect"]
    assert rows["AUTH_MODE"]["effect"].startswith("Logins are on")


def test_a_login_setting_cant_be_saved_from_the_settings_tab(on):
    james = signed_in(on, "james")
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
    assert is_admin("james") and is_admin(auth.BREAK_GLASS_USER) and is_admin("someone-else")
    assert not is_admin("ethan") and not is_admin(LOCAL_USER)


def test_the_sign_in_answer_is_what_me_answers(on):
    response = sign_in(on.client, "james", PASSWORDS["james"])
    assert response.json() == on.client.get(ME).json()
    assert json.dumps(response.json()).count("navidrome") == 0
