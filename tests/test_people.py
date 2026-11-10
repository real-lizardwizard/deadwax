"""
People (2.0.0-player.61) - src/routes/people.py, src/people.py, src/api/navidrome_admin.py and the permissions
(src/permissions.py) - through start() with a real SQLite store, logins on, and a fake Navidrome
(tests/navidrome_native_fake.py) whose native API and Subsonic getUser share one set of accounts: `admin` (a
Navidrome admin, as on James's install), `james` and `ethan` (ordinary), and `demo`, NAVIDROME_USER.

What these hold (the spec's list, each mutation-checked):

  - Logins off and break-glass: GET says why, every write 409s, Navidrome is asked nothing.
  - Unlock: checked against the session's own login first (a wrong password never reaches Navidrome, and
    counts in the sign-in throttle); one /auth/login as the session's own name; held PER SESSION, 15 idle
    minutes, Lock, the session's end, a changed NAVIDROME_URL; Navidrome's 401 after the local check ends the
    session; isAdmin false drops the role; deadwax's own gate of 4 logins per 20 s.
  - Every native request comes AS THE SIGNED-IN PERSON (the fake fails the test otherwise), never as
    NAVIDROME_USER; every write re-reads its target first and checks the name the page drew.
  - Create, Reset, Make / unmake admin, Remove, Forget, Permissions - each as the spec has them, with every
    guard, and nothing sent when one refuses.
  - Never leaked: no password, JWT or token in a log line or an answer; a People 422 echoes nothing.
  - The rate limit (10 writes a minute per admin) and one write at a time.
  - Permissions: only differences stored, a change in force at the next request, fail closed, bound to the
    Navidrome account's id (read at the sign-in only for someone with a grant, through the gate), healed by
    an admin's list, gone with the person.
  - Every page refuses to be framed; the native API is a fixed list; lib/people.ts's numbers are these.
"""

import ast
import asyncio
import json
import logging
import re
import sqlite3
import sys
import time
from pathlib import Path
from types import SimpleNamespace

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import auth, people as rules, permissions  # noqa: E402
from src.api import navidrome_admin  # noqa: E402
from src.api.app import PEOPLE_FORM, start  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import people as routes  # noqa: E402
from src.store import JobStore, PERSON_TABLES  # noqa: E402
from src.users import LOCAL_USER, NEEDS_PEOPLE, PERMISSIONS  # noqa: E402
from tests.navidrome_native_fake import FakeNavidromeNative  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SECRET = "0123456789abcdef0123456789abcdef-test-key"
GLASS = "break-the-glass-please"
NAVIDROME = "http://navidrome:4533"
PEOPLE = "/deadwax/people"
ME = "/deadwax/me"
LOGIN = "/deadwax/auth/login"
NEW_PASSWORD = "a-brand-new-password"


def run(coroutine):
    return asyncio.run(coroutine)


def wire(fake: FakeNavidromeNative, base: str = NAVIDROME) -> None:
    auth.login_client.client = httpx.AsyncClient(transport=httpx.MockTransport(fake.handle), base_url=f"{base}/rest")
    auth.login_client.base = f"{base}/rest"
    navidrome_admin._native.client = httpx.AsyncClient(transport=httpx.MockTransport(fake.handle), base_url=base,
                                                       follow_redirects=False)
    navidrome_admin._native.base = base


class Slskd:
    """slskd as the downloads list asks it: nothing transferring."""

    async def get_downloads(self, usernames=()):
        return []

    async def queue_position(self, *args):
        return None


@pytest.fixture
def nd(monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "AUTH_MODE", "on")
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", SECRET)
    monkeypatch.setattr(Config, "DEADWAX_ADMIN_PASSWORD", GLASS)
    monkeypatch.setattr(Config, "NAVIDROME_URL", NAVIDROME)
    monkeypatch.setattr(Config, "NAVIDROME_USER", "demo")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "shared-pw")
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "copy")
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "slskd"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "library"))
    monkeypatch.setattr(auth, "throttle", auth.Throttle())
    clock = [10_000.0]
    monkeypatch.setattr(navidrome_admin, "_clock", lambda: clock[0])
    monkeypatch.setattr(routes, "_clock", lambda: clock[0])
    auth.forget_sessions()
    permissions.forget_all()
    routes.forget_writes()
    fake = FakeNavidromeNative(clock)
    wire(fake)
    store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    store.init()
    app = start()
    app.state.store = store
    app.state.slskd_client = Slskd()
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    yield SimpleNamespace(app=app, store=store, fake=fake, clock=clock, path=tmp_path / "state" / "deadwax.db", tmp=tmp_path)
    assert fake.violations == []
    #? (review) the fixed list holds over EVERY test here, not only its own walk: whatever path a test took, each
    #? native request the fake saw was one of the six
    assert native_shapes(fake) <= SIX, native_shapes(fake) - SIX
    auth.forget_sessions()
    permissions.forget_all()
    routes.forget_writes()
    run(auth.login_client.close_client())
    run(navidrome_admin.close_client())


#? The six native requests there are (src/api/navidrome_admin.py)
SIX = {("POST", "/auth/login"), ("GET", "/api/user"), ("POST", "/api/user"), ("GET", "/api/user/{id}"),
       ("PUT", "/api/user/{id}"), ("DELETE", "/api/user/{id}")}


def native_shapes(fake) -> set:
    return {(r["method"], re.sub(r"^/api/user/[A-Za-z0-9-]+$", "/api/user/{id}", r["path"])) for r in fake.native()}


def password(nd, name: str) -> str:
    return nd.fake.passwords[nd.fake.id_of(name)]


def signed_in(nd, name: str, pw: str | None = None) -> TestClient:
    client = TestClient(nd.app)
    answer = client.post(LOGIN, json={"username": name, "password": GLASS if name == auth.BREAK_GLASS_USER else (pw or password(nd, name))})
    assert answer.status_code == 200, answer.text
    return client


def later(nd, seconds: float = 21) -> None:
    """Time passes - enough, by default, for every login budget to be whole again."""
    nd.clock[0] += seconds


def unlock(nd, client: TestClient, name: str, pw: str | None = None) -> httpx.Response:
    later(nd)
    nd.fake.acting = name
    return client.post(f"{PEOPLE}/unlock", json={"password": pw or password(nd, name)})


def unlocked(nd, name: str = "admin") -> TestClient:
    client = signed_in(nd, name)
    answer = unlock(nd, client, name)
    assert answer.status_code == 200, answer.text
    return client


def act(nd, name: str) -> None:
    nd.fake.acting = name


def listed(client: TestClient) -> dict:
    return {row["user"]: row for row in client.get(PEOPLE).json()["people"]}


def secret_free(text: str, *secrets_: str) -> None:
    for secret in secrets_:
        assert secret not in text


# ----------------------------------------------------------------- who, and when

def test_people_is_a_navidrome_admins_and_ordinary_people_are_refused_in_words(nd):
    ethan = signed_in(nd, "ethan")
    for method, path in [("GET", PEOPLE), ("POST", f"{PEOPLE}/unlock"), ("POST", f"{PEOPLE}/create")]:
        answer = ethan.request(method, path, json={})
        assert answer.status_code == 403 and answer.json()["detail"] == NEEDS_PEOPLE.format(user="ethan")
    assert TestClient(nd.app).get(PEOPLE).status_code == 401
    assert nd.fake.native() == []


def test_with_logins_off_people_says_why_and_every_write_409s(nd, monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    client = TestClient(start())
    state = client.get(PEOPLE).json()
    assert state["on"] is False and state["available"] is False and state["problem"] == rules.NEEDS_LOGINS
    for path, body in [("unlock", {"password": "x"}), ("lock", {}), ("create", {}), ("forget", {"user": "x"}),
                       ("id-1/password", {}), ("id-1/admin", {}), ("id-1/remove", {}), ("id-1/permissions", {})]:
        answer = client.post(f"{PEOPLE}/{path}", json=body)
        assert answer.status_code == 409 and answer.json()["detail"] == rules.NEEDS_LOGINS, path
    assert nd.fake.requests == []


def test_break_glass_sees_people_s_line_and_every_write_409s(nd):
    glass = signed_in(nd, auth.BREAK_GLASS_USER)
    state = glass.get(PEOPLE).json()
    assert state["on"] is True and state["available"] is False and state["problem"] == rules.BREAK_GLASS
    for path, body in [("unlock", {"password": GLASS}), ("lock", {}), ("create", {}), ("forget", {"user": "x"}),
                       ("id-1/password", {}), ("id-1/admin", {}), ("id-1/remove", {}), ("id-1/permissions", {})]:
        answer = glass.post(f"{PEOPLE}/{path}", json=body)
        assert answer.status_code == 409 and answer.json()["detail"] == rules.BREAK_GLASS, path
    assert nd.fake.requests == []


# ----------------------------------------------------------------- unlocking

def test_a_locked_people_sends_nothing_about_anyone(nd):
    admin = signed_in(nd, "admin")
    state = admin.get(PEOPLE).json()
    assert state["available"] and state["locked"] and state["people"] == [] and state["known_only"] == []
    assert nd.fake.native() == []
    answer = admin.post(f"{PEOPLE}/create", json={"user": "maya", "name": "", "password": "maya-password", "password_again": "maya-password"})
    assert answer.status_code == 409 and answer.json()["kind"] == "locked"
    assert nd.fake.native() == []


def test_a_wrong_password_never_reaches_navidrome_and_counts_in_the_throttle(nd):
    admin = signed_in(nd, "admin")
    for _ in range(3):
        answer = unlock(nd, admin, "admin", "not-my-password")
        assert answer.status_code == 409 and answer.json()["detail"] == routes.NOT_YOUR_PASSWORD
        nd.clock[0] -= 21                                  # within the same minute
    assert nd.fake.native() == []
    held = admin.post(f"{PEOPLE}/unlock", json={"password": password(nd, "admin")})
    assert held.status_code == 429 and "Too many tries for admin" in held.json()["detail"]
    assert nd.fake.native() == []


def test_the_right_password_is_one_login_as_the_sessions_own_name(nd):
    admin = signed_in(nd, "admin")
    assert unlock(nd, admin, "admin").json() == {"unlocked": True}
    [sent] = nd.fake.native()
    assert (sent["method"], sent["path"]) == ("POST", "/auth/login")
    assert sent["body"] == {"username": "admin", "password": password(nd, "admin")}
    #? no name from the page: a field the model doesn't declare is refused, in words that echo nothing
    answer = admin.post(f"{PEOPLE}/unlock", json={"password": password(nd, "admin"), "username": "ethan"})
    assert answer.status_code == 422 and answer.json() == {"detail": PEOPLE_FORM}
    assert password(nd, "admin") not in answer.text
    state = admin.get(PEOPLE).json()
    assert state["locked"] is False and {"admin", "james", "ethan", "demo"} <= set(row["user"] for row in state["people"])


def test_navidrome_refusing_a_login_the_local_check_passed_ends_the_session(nd):
    admin = signed_in(nd, "admin")
    old = password(nd, "admin")
    nd.fake.set_password("admin", "changed-in-navidrome")
    answer = unlock(nd, admin, "admin", old)
    assert answer.status_code == 401 and answer.json()["detail"] == auth.LOGIN_GONE
    assert admin.get(ME).json()["detail"] == auth.LOGIN_GONE


def test_a_login_navidrome_says_isnt_an_admin_drops_the_role(nd):
    nd.fake.by_name("ethan")["isAdmin"] = True
    ethan = signed_in(nd, "ethan")
    assert ethan.get(ME).json()["admin"] is True
    nd.fake.by_name("ethan")["isAdmin"] = False             # demoted in Navidrome, before the re-check
    answer = unlock(nd, ethan, "ethan")
    assert answer.status_code == 403 and answer.json()["kind"] == "not_admin"
    assert ethan.get(ME).json()["admin"] is False
    assert ethan.get(PEOPLE).status_code == 403


@pytest.mark.parametrize("how", ["the list", "a write"])
def test_navidromes_403_to_an_unlocked_admin_drops_the_role_at_once(nd, how):
    """(second review) Unlocked, then demoted in Navidrome: the next People call Navidrome refuses with its 403
    ends deadwax's role at once - /me says so on the very next request, and People is refused - without waiting
    for the re-check (none runs here). The unlock goes with it."""
    nd.fake.by_name("ethan")["isAdmin"] = True
    ethan = unlocked(nd, "ethan")
    assert ethan.get(ME).json()["admin"] is True
    nd.fake.by_name("ethan")["isAdmin"] = False             # demoted in Navidrome, after the unlock
    act(nd, "ethan")
    if how == "the list":
        state = ethan.get(PEOPLE).json()
        assert state["problem"] == routes.NOT_ADMIN_NOW and state["available"] is False and state["people"] == []
    else:
        answer = ethan.post(f"{PEOPLE}/create", json={"user": "maya", "name": "", "password": "maya-password",
                                                      "password_again": "maya-password"})
        assert answer.status_code == 403 and answer.json()["kind"] == "not_admin"
        assert answer.json()["detail"] == routes.NOT_ADMIN_NOW and nd.fake.by_name("maya") is None
    me = ethan.get(ME).json()
    assert me["admin"] is False and "people" not in me["permissions"]
    assert ethan.get(PEOPLE).status_code == 403
    assert not any(held.user == "ethan" for held in navidrome_admin._unlocked.values())


def test_navidrome_answering_for_another_account_is_never_used(nd):
    """(second review) /auth/login answering for someone else - a misbehaving Navidrome, or a proxy - is refused as
    `not_you`: no unlock is held from its JWT, and a sign-in reads no account id from it (so a grant isn't honoured,
    fail closed, rather than bound to the other account's id)."""
    admin = signed_in(nd, "admin")
    nd.fake.answer_login_as = "james"
    answer = unlock(nd, admin, "admin")
    assert answer.status_code == 409 and answer.json()["kind"] == "not_you"
    assert answer.json()["detail"] == navidrome_admin.WORDS["not_you"]
    assert admin.get(PEOPLE).json()["locked"] is True
    assert [r["path"] for r in nd.fake.native()] == ["/auth/login"]
    #? at a sign-in: ethan has a grant, Navidrome's login answers as james - the grant waits, unverified
    permissions.set_for(nd.store, "ethan", nd.fake.id_of("ethan"), {"request": True, "edit": True, "library": False,
                                                                   "downloads": False, "server": False}, "admin")
    later(nd)
    act(nd, "ethan")
    ethan = signed_in(nd, "ethan")
    me = ethan.get(ME).json()
    assert me["permissions"] == ["request"] and me["permissions_unverified"] is True
    with sqlite3.connect(nd.path) as connection:
        assert connection.execute("SELECT DISTINCT navidrome_id FROM permissions").fetchall() == [(nd.fake.id_of("ethan"),)]


def test_deadwaxs_gate_holds_the_fifth_login_in_20_seconds_with_nothing_sent(nd):
    for name in ("james", "ethan"):
        nd.fake.by_name(name)["isAdmin"] = True
    nd.fake.add("maya", "maya-navidrome-pw", admin=True)
    nd.fake.add("sam", "sam-navidrome-pw", admin=True)
    clients = {name: signed_in(nd, name) for name in ("admin", "james", "ethan", "maya", "sam")}
    later(nd)
    for name in ("admin", "james", "ethan", "maya"):
        act(nd, name)
        assert clients[name].post(f"{PEOPLE}/unlock", json={"password": password(nd, name)}).status_code == 200
    sent = len(nd.fake.native())
    act(nd, "sam")
    held = clients["sam"].post(f"{PEOPLE}/unlock", json={"password": password(nd, "sam")})
    assert held.status_code == 429 and held.json()["kind"] == "held_off"
    assert "only takes a few sign-ins from deadwax every 20 seconds" in held.json()["detail"]
    assert int(held.headers["retry-after"]) > 0
    assert len(nd.fake.native()) == sent


def test_navidromes_own_429_is_said_the_same_way_and_never_retried(nd):
    admin = signed_in(nd, "admin")
    later(nd)
    for _ in range(5):                                      # five logins from elsewhere at deadwax's address
        nd.fake.logins.append(nd.clock[0])
    act(nd, "admin")
    answer = admin.post(f"{PEOPLE}/unlock", json={"password": password(nd, "admin")})
    assert answer.status_code == 429 and answer.json()["kind"] == "held_off"
    assert len(nd.fake.native("POST")) == 1


def test_an_unlock_is_held_per_session_never_per_person(nd):
    nd.fake.by_name("ethan")["isAdmin"] = True
    phone = unlocked(nd, "admin")
    laptop = signed_in(nd, "admin")
    state = laptop.get(PEOPLE).json()
    assert state["locked"] is True and state["people"] == []
    #? ethan, an admin too, unlocks with HIS password and asks with HIS JWT (the fake fails the test otherwise)
    ethan = unlocked(nd, "ethan")
    act(nd, "ethan")
    assert "admin" in listed(ethan)
    act(nd, "admin")
    assert "ethan" in listed(phone)


def test_an_unlock_ends_idle_on_lock_and_with_the_session(nd):
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    later(nd, navidrome_admin.UNLOCK_IDLE_SECONDS - 30)
    assert admin.get(PEOPLE).json()["locked"] is False      # used: the 15 minutes start again
    later(nd, navidrome_admin.UNLOCK_IDLE_SECONDS)
    assert admin.get(PEOPLE).json()["locked"] is True
    assert unlock(nd, admin, "admin").status_code == 200
    assert admin.post(f"{PEOPLE}/lock", json={}).json() == {"locked": True}
    assert admin.get(PEOPLE).json()["locked"] is True
    assert unlock(nd, admin, "admin").status_code == 200
    key = auth.id_hash(admin.cookies[auth.COOKIE])
    admin.post("/deadwax/auth/logout")
    assert navidrome_admin.unlocked(key) is None


def test_an_unlock_is_never_sent_to_another_navidrome_address(nd, monkeypatch):
    admin = unlocked(nd, "admin")
    sent = len(nd.fake.requests)
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://elsewhere:4533")
    state = admin.get(PEOPLE).json()
    assert state["locked"] is True
    assert len(nd.fake.requests) == sent


def test_an_unlock_held_for_one_address_is_never_used_at_another(nd, monkeypatch):
    """Both halves of it: unlocked() lets go of an unlock got from another NAVIDROME_URL, and _ask - should one
    still be in hand - refuses to send its JWT anywhere but where it came from."""
    admin = unlocked(nd, "admin")
    key = auth.id_hash(admin.cookies[auth.COOKIE])
    held = navidrome_admin._unlocked[key]
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://elsewhere:4533")
    sent = len(nd.fake.requests)
    with pytest.raises(navidrome_admin.NativeError) as refused:
        run(navidrome_admin.list_users(held))
    assert refused.value.kind == "locked" and len(nd.fake.requests) == sent
    monkeypatch.setattr(Config, "NAVIDROME_URL", NAVIDROME)
    navidrome_admin._hold(held)
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://elsewhere:4533")
    assert navidrome_admin.unlocked(key) is None and key not in navidrome_admin._unlocked


def test_a_401_on_a_call_locks_people_and_sends_no_login(nd):
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    nd.fake.epochs[nd.fake.id_of("admin")] += 1             # every JWT of it dead (a password changed elsewhere)
    logins = len(nd.fake.native("POST"))
    state = admin.get(PEOPLE).json()
    assert state["locked"] is True and "asked for your password again" in state["problem"]
    assert len([r for r in nd.fake.native("POST") if r["path"] == "/auth/login"]) == logins
    answer = admin.post(f"{PEOPLE}/create", json={"user": "maya", "name": "", "password": "maya-password",
                                                  "password_again": "maya-password"})
    assert answer.json()["kind"] == "locked"


def test_the_refreshed_jwt_is_the_one_used_next(nd):
    """The fake takes only an unlock's newest two JWTs: a client keeping the first is refused after two calls."""
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    for _ in range(4):
        assert admin.get(PEOPLE).json()["locked"] is False


# ----------------------------------------------------------------- the list

def test_the_list_joins_what_deadwax_knows_and_sends_nothing_private(nd):
    signed_in(nd, "ethan")
    signed_in(nd, "ethan")
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    state = admin.get(PEOPLE).json()
    rows = {row["user"]: row for row in state["people"]}
    assert state["you"] == "admin" and state["account"] == "demo"
    assert rows["admin"]["you"] and rows["admin"]["admin"] and state["people"][0]["user"] == "admin"
    assert rows["demo"]["shared_account"] and rows["ethan"]["signed_in"] == 2 and rows["james"]["signed_in"] == 0
    assert rows["james"]["last_sign_in"] is None and rows["ethan"]["last_sign_in"] is not None
    assert rows["ethan"]["libraries"] == 1 and rows["ethan"]["permissions"] == {
        "request": True, "edit": False, "library": False, "downloads": False, "server": False}
    assert rows["admin"]["permissions"] is None
    assert rows["admin"]["can"] == {"reset": rules.YOUR_PASSWORD, "remove": rules.YOUR_ACCOUNT, "admin": rules.YOUR_ROLE,
                                    "permissions": rules.YOUR_PERMISSIONS}
    #? (2.0.8) Change password is in You's Account section now, and the refusal sends you there by that path
    assert rules.YOUR_PASSWORD.endswith("You → Account → Change password.")
    assert set(rows["demo"]["can"].values()) == {rules.SHARED_ACCOUNT}
    assert rows["ethan"]["can"] == {"reset": None, "remove": None, "admin": None, "permissions": None}
    text = json.dumps(state)
    for private in ("@example.com", "createdAt", "lastLoginAt", "jwt.", password(nd, "ethan")):
        assert private not in text


def test_known_only_to_deadwax_lists_names_navidrome_has_no_account_for(nd):
    ethan = signed_in(nd, "ethan")
    run(nd.store.write_pins("ethan", [{"kind": "artist", "ref": "name:tricky", "label": "Tricky"}]))
    nd.fake.remove("ethan")
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    [only] = admin.get(PEOPLE).json()["known_only"]
    assert only["user"] == "ethan" and only["sessions"] == 1 and only["pins"] == 1 and only["credential"] is True
    assert ethan is not None


# ----------------------------------------------------------------- create

def make(client, user="Maya", name="Maya Rudolph", pw="maya-password", again=None):
    return client.post(f"{PEOPLE}/create", json={"user": user, "name": name, "password": pw,
                                                 "password_again": pw if again is None else again})


def test_create_sends_exactly_an_ordinary_lowercased_account_and_checks_it_took(nd):
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    answer = make(admin)
    assert answer.status_code == 200, answer.text
    made = answer.json()
    assert made["made"]["user"] == "maya" and made["made"]["name"] == "Maya Rudolph" and made["warning"] is None
    [post] = [r for r in nd.fake.writes() if r["method"] == "POST"]
    assert post["body"] == {"userName": "maya", "name": "Maya Rudolph", "email": "", "isAdmin": False, "password": "maya-password"}
    #? exactly one getUser as the new account, with its password
    assert len(nd.fake.subsonic("maya")) == 1
    #? and it signs in
    act(nd, None)
    assert signed_in(nd, "maya", "maya-password").get(ME).json()["user"] == "maya"
    assert "maya-password" not in answer.text


@pytest.mark.parametrize("user, pw, again, said", [
    ("", "long-enough-pw", None, "Type a user name."),
    ("has space", "long-enough-pw", None, "lowercase letters"),
    ("x" * 33, "long-enough-pw", None, "at most 32"),
    ("-dash", "long-enough-pw", None, "lowercase letters"),
    ("Local", "long-enough-pw", None, "keeps for itself"),
    ("deadwax", "long-enough-pw", None, "keeps for itself"),
    ("maya", "short", None, "at least 8"),
    ("maya", "x" * 129, None, "at most 128"),
    ("maya", "MAYA", None, "at least 8"),
    ("mayamaya", "MayaMaya", None, "can't be the user name"),
    ("maya", "long-enough-pw", "another-one", "aren't the same"),
    ("maya", "tab\there-pw", None, "control characters"),
])
def test_every_name_and_password_refusal_sends_nothing(nd, user, pw, again, said):
    admin = unlocked(nd, "admin")
    sent = len(nd.fake.requests)
    answer = make(admin, user=user, pw=pw, again=again)
    assert answer.status_code == 400 and said in answer.json()["detail"], answer.text
    assert len(nd.fake.requests) == sent


def test_a_display_name_too_long_or_with_control_characters_is_refused(nd):
    admin = unlocked(nd, "admin")
    assert make(admin, name="x" * 65).status_code == 400
    assert make(admin, name="bell\x07").status_code == 400


def test_a_name_navidrome_has_in_any_case_is_taken(nd):
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    answer = make(admin, user="ETHAN")
    assert answer.status_code == 409 and answer.json()["detail"] == "There's already a Navidrome account called ethan."


def test_a_name_deadwax_still_keeps_things_for_is_refused_until_forgotten(nd):
    run(nd.store.write_pins("maya", [{"kind": "artist", "ref": "name:tricky", "label": "Tricky"}]))
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    answer = make(admin)
    assert answer.status_code == 409 and answer.json()["detail"] == routes.LEFTOVERS.format(user="maya")
    assert nd.fake.writes() == []


def test_a_new_account_with_no_library_is_warned_about(nd, monkeypatch):
    from tests import navidrome_native_fake
    monkeypatch.setattr(navidrome_native_fake, "DEFAULT_NEW_USERS", set())
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    assert "gives them no library" in make(admin).json()["warning"]


def test_a_navidrome_that_ignores_the_password_is_said(nd):
    nd.fake.ignore_password = True
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    answer = make(admin)
    assert answer.status_code == 502 and answer.json()["detail"] == routes.DIDNT_TAKE.format(user="maya")


def test_a_made_account_navidrome_then_wont_read_back_is_still_made_with_a_warning(nd):
    """(review) Once the POST made the account, a failure of the read that follows is a warning beside `made` -
    never the refusal that would send the admin to try again into "already an account called maya"."""
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    nd.fake.one_unread = True
    answer = make(admin)
    assert answer.status_code == 200, answer.text
    assert answer.json()["made"]["user"] == "maya" and answer.json()["warning"] == routes.LIBRARIES_UNREAD
    assert len(nd.fake.subsonic("maya")) == 1                 # the password was still checked


@pytest.mark.parametrize("method, route, words", [("POST", "create", "CREATE_TIMED_OUT"),
                                                  ("PUT", "reset", "RESET_TIMED_OUT")])
def test_a_write_whose_connection_drops_after_sending_is_an_unknown_outcome(nd, method, route, words):
    """(review) A dropped connection once a write may have reached Navidrome is no "Navidrome isn't answering":
    Navidrome may well have done it, so it is the route's unknown-outcome words."""
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    nd.fake.dropped.add(method)
    answer = make(admin) if route == "create" else reset(admin, nd)
    assert answer.status_code == 504 and answer.json()["kind"] == "timed_out"
    assert answer.json()["detail"] == getattr(routes, words).format(user="maya" if route == "create" else "ethan")


def test_a_write_that_never_connected_is_navidrome_not_answering():
    """...while one that never made a connection sent nothing, and says so."""
    unlock = navidrome_admin.Unlock(None, "admin", "id", True, "jwt", NAVIDROME, 0.0)

    def refuse(request):
        raise httpx.ConnectError("connection refused")

    async def go():
        navidrome_admin._native.client = httpx.AsyncClient(transport=httpx.MockTransport(refuse), base_url=NAVIDROME)
        navidrome_admin._native.base = NAVIDROME
        try:
            await navidrome_admin.delete_user(unlock, "id-1")
        finally:
            await navidrome_admin.close_client()

    original = Config.NAVIDROME_URL
    Config.NAVIDROME_URL = NAVIDROME
    try:
        with pytest.raises(navidrome_admin.NativeError) as raised:
            run(go())
    finally:
        Config.NAVIDROME_URL = original
    assert raised.value.kind == "unreachable"


# ----------------------------------------------------------------- reset

def reset(client, nd, name="ethan", pw=NEW_PASSWORD, again=None, user=None):
    return client.post(f"{PEOPLE}/{nd.fake.id_of(name)}/password",
                       json={"user": user or name, "password": pw, "password_again": pw if again is None else again})


def test_a_reset_puts_the_record_back_whole_and_signs_them_out_everywhere(nd):
    ethan_phone, ethan_laptop, james = signed_in(nd, "ethan"), signed_in(nd, "ethan"), signed_in(nd, "james")
    assert ethan_phone.get(ME).status_code == 200            # held in memory
    raw = ethan_laptop.cookies[auth.COOKIE]
    before = dict(nd.fake.by_name("ethan"))
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    answer = reset(admin, nd)
    assert answer.json() == {"reset": "ethan", "signed_out": 2}
    [got] = [r for r in nd.fake.native("GET") if r["path"] == f"/api/user/{before['id']}"]
    [put] = [r for r in nd.fake.writes() if r["method"] == "PUT"]
    assert put["body"] == {**before, "password": NEW_PASSWORD}
    after = nd.fake.by_name("ethan")
    assert (after["userName"], after["name"], after["email"], after["isAdmin"]) == ("ethan", "Ethan", "ethan@example.com", False)
    assert got is not None
    #? signed out at once, memory and database - the next request says why
    assert ethan_phone.get(ME).json()["detail"] == auth.PASSWORD_RESET
    auth.forget_sessions()
    replay = TestClient(nd.app)
    replay.cookies.set(auth.COOKIE, raw)
    assert replay.get(ME).status_code == 401
    assert nd.store.credential_row("ethan")["dead_why"] == auth.PASSWORD_RESET
    assert james.get(ME).json()["user"] == "james"
    #? the re-check asks nothing as them any more; their new password signs in at once
    asked = len(nd.fake.subsonic("ethan"))
    run(auth.check_sessions(nd.store, now=time.time() + auth.RECHECK_SECONDS + 1))
    assert len(nd.fake.subsonic("ethan")) == asked
    act(nd, None)
    assert signed_in(nd, "ethan", NEW_PASSWORD).get(ME).json()["user"] == "ethan"
    assert nd.fake.refused.get("ethan", 0) == 0


def test_a_reset_checks_the_name_the_page_drew_and_that_the_account_is_there(nd):
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    stale = reset(admin, nd, user="james")
    assert stale.status_code == 409 and stale.json()["detail"] == routes.STALE
    gone_id = nd.fake.id_of("ethan")
    nd.fake.remove("ethan")
    gone = admin.post(f"{PEOPLE}/{gone_id}/password", json={"user": "ethan", "password": NEW_PASSWORD, "password_again": NEW_PASSWORD})
    assert gone.status_code == 404 and gone.json()["detail"] == "ethan's account isn't in Navidrome any more."
    assert nd.fake.writes() == []
    assert admin.post(f"{PEOPLE}/not%20an%20id/password", json={"user": "x"}).status_code == 404


def test_a_reset_navidrome_ignores_is_said_and_ends_nothing(nd):
    ethan = signed_in(nd, "ethan")
    nd.fake.ignore_password = True
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    answer = reset(admin, nd)
    assert answer.status_code == 502 and answer.json()["detail"] == routes.RESET_DIDNT_TAKE.format(user="ethan")
    assert ethan.get(ME).json()["user"] == "ethan"


def test_a_reset_that_times_out_is_an_unknown_outcome_and_ends_nothing(nd):
    ethan = signed_in(nd, "ethan")
    nd.fake.timeout.add("PUT")
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    answer = reset(admin, nd)
    assert answer.status_code == 504 and answer.json()["detail"] == routes.RESET_TIMED_OUT.format(user="ethan")
    assert ethan.get(ME).json()["user"] == "ethan"


def test_a_reset_of_an_admin_ends_their_unlock_too(nd):
    nd.fake.by_name("ethan")["isAdmin"] = True
    ethan = unlocked(nd, "ethan")
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    assert reset(admin, nd).status_code == 200
    assert navidrome_admin.unlocked(auth.id_hash(ethan.cookies[auth.COOKIE])) is None


def test_a_removal_of_an_admin_ends_their_unlock_too(nd):
    nd.fake.by_name("ethan")["isAdmin"] = True
    ethan = unlocked(nd, "ethan")
    key = auth.id_hash(ethan.cookies[auth.COOKIE])
    assert navidrome_admin.unlocked(key) is not None
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    assert remove(admin, nd).status_code == 200
    assert navidrome_admin.unlocked(key) is None
    assert ethan.get(ME).json()["detail"] == auth.ACCOUNT_REMOVED


# ----------------------------------------------------------------- make and unmake an admin

def make_admin(client, nd, name="ethan", admin=True, user=None):
    return client.post(f"{PEOPLE}/{nd.fake.id_of(name)}/admin", json={"user": user or name, "admin": admin})


def test_making_an_admin_puts_only_the_flag_and_is_the_role_at_their_next_request(nd):
    ethan = signed_in(nd, "ethan")
    assert ethan.get("/deadwax/settings").status_code == 403
    before = dict(nd.fake.by_name("ethan"))
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    assert make_admin(admin, nd).json() == {"user": "ethan", "admin": True, "changed": True}
    [put] = [r for r in nd.fake.writes() if r["method"] == "PUT"]
    assert put["body"] == {**before, "isAdmin": True}
    assert len(nd.fake.by_name("ethan")["libraries"]) == 2      # Navidrome gives an admin every library
    assert ethan.get(ME).json()["admin"] is True and ethan.get("/deadwax/settings").status_code == 200
    assert make_admin(admin, nd, admin=False).json()["admin"] is False
    assert ethan.get(ME).json()["admin"] is False


def test_a_navidrome_that_ignores_the_flag_leaves_the_role_as_it_was(nd):
    ethan = signed_in(nd, "ethan")
    nd.fake.ignore_admin = True
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    answer = make_admin(admin, nd)
    assert answer.status_code == 502 and answer.json()["kind"] == "unknown_shape"
    assert ethan.get(ME).json()["admin"] is False


# ----------------------------------------------------------------- remove and forget

def remove(client, nd, name="ethan", confirm=None, user=None):
    return client.post(f"{PEOPLE}/{nd.fake.id_of(name)}/remove", json={"user": user or name, "confirm": name if confirm is None else confirm})


def keep_things_for(nd, name: str) -> int:
    """Something of every kind deadwax keeps for `name` - and a download only they wait for. Its job id."""
    run(nd.store.write_pins(name, [{"kind": "artist", "ref": "name:tricky", "label": "Tricky"}]))
    run(nd.store.set_user_preferences(name, {"get_mode": "pick"}))
    job_id = run(nd.store.create_job("peer", "dir", [{"filename": "a.flac"}], {"release_mbid": "rel-x", "artist": "A", "album": "B"}, user=name))
    with sqlite3.connect(nd.path) as connection:
        connection.execute("INSERT INTO library_membership (user, album_id, added_at, how, state, updated_at) "
                           "VALUES (?, 1, 'then', 'added', 'starred', 'then')", (name,))
    return job_id


def test_remove_needs_the_typed_name_reads_first_and_forgets_everything_of_theirs_alone(nd):
    ethan = signed_in(nd, "ethan")
    job_id = keep_things_for(nd, "ethan")
    keep_things_for(nd, "james")
    permissions.set_for(nd.store, "ethan", nd.fake.id_of("ethan"), {"request": True, "edit": True, "library": False,
                                                                   "downloads": False, "server": False}, "admin")
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    for wrong in ("Ethan", "ethan ", ""):
        answer = remove(admin, nd, confirm=wrong)
        assert answer.status_code == 400 and answer.json()["detail"] == routes.TYPE_THE_NAME
    assert nd.fake.writes() == []
    target = f"/api/user/{nd.fake.id_of('ethan')}"
    answer = remove(admin, nd)
    assert answer.status_code == 200, answer.text
    asked = [(r["method"], r["path"]) for r in nd.fake.native() if r["path"].startswith("/api")]
    assert asked.index(("GET", target)) < asked.index(("DELETE", target))
    assert answer.json()["forgot"]["pins"] == 1 and answer.json()["forgot"]["permissions"] == 1
    assert nd.fake.by_name("ethan") is None and nd.fake.cascades[0]["user"] == "ethan"
    with sqlite3.connect(nd.path) as connection:
        for table in PERSON_TABLES:
            assert connection.execute(f"SELECT COUNT(*) FROM {table} WHERE user = 'ethan'").fetchone()[0] == 0, table
        assert connection.execute("SELECT COUNT(*) FROM pins WHERE user = 'james'").fetchone()[0] == 1
    assert ethan.get(ME).json()["detail"] == auth.ACCOUNT_REMOVED
    assert permissions.ticked(nd.store, "ethan")["edit"] is False
    #? the download only they wanted carries on - nobody's now, seen by an admin as such
    job = run(nd.store.get_job(job_id))
    assert job is not None and job["status"] not in ("cancelled",) and run(nd.store.requesters(job_id)) == []
    rows = {row["id"]: row for row in admin.get("/deadwax/download/jobs").json()["jobs"]}
    assert rows[job_id]["requested_by"] == [] and rows[job_id]["mine"] is False


def test_removing_a_reserved_name_is_navidromes_alone(nd):
    nd.fake.add("local", "local-navidrome-pw")
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    #? (after the admin's sign-in, which takes over what `local` holds)
    run(nd.store.write_pins(LOCAL_USER, [{"kind": "artist", "ref": "name:tricky", "label": "Tricky"}]))
    assert remove(admin, nd, "local").json() == {"removed": "local", "forgot": None}
    assert len(run(nd.store.pins(LOCAL_USER))) == 1
    with pytest.raises(ValueError):
        nd.store.forget_person("local")


def test_navidrome_refusing_a_remove_changes_nothing_in_deadwax(nd):
    keep_things_for(nd, "ethan")
    nd.fake.refuse_delete = True
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    answer = remove(admin, nd)
    assert answer.status_code == 502 and answer.json()["kind"] == "unknown_shape"
    #? (2.0.8) said as People's version note is: "checked with" Navidrome 0.64, and where to go meanwhile
    detail = answer.json()["detail"]
    assert "People was checked with Navidrome 0.64" in detail and "made for" not in detail
    assert detail.endswith("use Navidrome's own Users page meanwhile.")
    assert len(run(nd.store.pins("ethan"))) == 1


def test_a_failed_forget_after_navidromes_200_is_said_and_listed_under_known_only(nd, monkeypatch):
    keep_things_for(nd, "ethan")
    admin = unlocked(nd, "admin")
    act(nd, "admin")

    def locked(_user):
        raise sqlite3.OperationalError("database is locked")

    real = nd.store.forget_person
    monkeypatch.setattr(nd.store, "forget_person", locked)
    answer = remove(admin, nd)
    assert answer.status_code == 500 and answer.json()["detail"] == routes.FORGET_FAILED.format(user="ethan", why="OperationalError")
    monkeypatch.setattr(nd.store, "forget_person", real)
    assert [row["user"] for row in admin.get(PEOPLE).json()["known_only"]] == ["ethan"]


def test_a_remove_that_times_out_says_to_look_again(nd):
    nd.fake.timeout.add("DELETE")
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    answer = remove(admin, nd)
    assert answer.status_code == 504 and answer.json()["detail"] == routes.REMOVE_TIMED_OUT.format(user="ethan")


def test_forget_only_for_a_name_a_fresh_list_lacks_and_never_a_reserved_one(nd):
    keep_things_for(nd, "ethan")
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    still = admin.post(f"{PEOPLE}/forget", json={"user": "ethan"})
    assert still.status_code == 409 and still.json()["detail"] == routes.STILL_THERE.format(user="ethan")
    for reserved in ("local", "deadwax"):
        assert admin.post(f"{PEOPLE}/forget", json={"user": reserved}).status_code == 409
    nothing = admin.post(f"{PEOPLE}/forget", json={"user": "nobody"})
    assert nothing.status_code == 404
    nd.fake.remove("ethan")
    assert admin.post(f"{PEOPLE}/forget", json={"user": "ethan"}).json()["forgot"] == "ethan"
    assert not nd.store.keeps_anything("ethan")
    assert admin.get(PEOPLE).json()["known_only"] == []


# ----------------------------------------------------------------- the guards

def test_yourself_navidrome_user_and_the_last_admin_are_refused_with_nothing_sent(nd):
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    for answer, said in [(reset(admin, nd, "admin"), rules.YOUR_PASSWORD), (remove(admin, nd, "admin"), rules.YOUR_ACCOUNT),
                         (make_admin(admin, nd, "admin", admin=False), rules.YOUR_ROLE),
                         (reset(admin, nd, "demo"), rules.SHARED_ACCOUNT), (remove(admin, nd, "demo"), rules.SHARED_ACCOUNT),
                         (make_admin(admin, nd, "demo"), rules.SHARED_ACCOUNT)]:
        assert answer.status_code == 409 and answer.json()["detail"] == said, answer.text
    #? the last admin: forced through a list that leaves the actor out, so ethan reads as Navidrome's last
    nd.fake.by_name("ethan")["isAdmin"] = True
    nd.fake.hide_from_list.add("admin")
    for answer in (remove(admin, nd), make_admin(admin, nd, admin=False)):
        assert answer.status_code == 409 and answer.json()["detail"] == rules.LAST_ADMIN.format(user="ethan")
    assert nd.fake.writes() == []


def test_another_admin_may_be_reset_demoted_and_removed(nd):
    """Admins are equals, as in Navidrome."""
    nd.fake.by_name("ethan")["isAdmin"] = True
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    assert reset(admin, nd).status_code == 200
    assert make_admin(admin, nd, admin=False).status_code == 200
    assert make_admin(admin, nd).status_code == 200
    assert remove(admin, nd).status_code == 200


def test_the_guards_are_pure_and_first_match_wins():
    ctx = {"logins": True, "break_glass": False, "shared": "demo", "admins": {"admin", "ethan"},
           "reserved": auth.RESERVED_NAMES}
    assert rules.refusals("admin", {"user": "ethan", "admin": True}, ctx) == {"reset": None, "remove": None, "admin": None,
                                                                              "permissions": rules.ADMIN_PERMISSIONS}
    assert rules.refusals("admin", {"user": "ethan", "admin": True}, {**ctx, "admins": {"ethan"}})["remove"] == \
        rules.LAST_ADMIN.format(user="ethan")
    assert rules.refusals("admin", {"user": "local", "admin": False}, ctx) == {"reset": None, "remove": None, "admin": None,
                                                                               "permissions": rules.RESERVED_PERMISSIONS}
    assert set(rules.refusals("admin", {"user": "x"}, {**ctx, "logins": False}).values()) == {rules.NEEDS_LOGINS}
    assert set(rules.refusals("admin", {"user": "x"}, {**ctx, "break_glass": True}).values()) == {rules.BREAK_GLASS}
    #? NAVIDROME_USER beats "yourself"
    assert set(rules.refusals("demo", {"user": "demo"}, ctx).values()) == {rules.SHARED_ACCOUNT}
    assert rules.last_admin({"ethan"}, "ethan") and not rules.last_admin({"ethan", "admin"}, "ethan")


# ----------------------------------------------------------------- permissions

def tick(client, nd, name="ethan", user=None, **wanted):
    body = {"user": user or name, "request": True, "edit": False, "library": False, "downloads": False, "server": False}
    body.update(wanted)
    return client.post(f"{PEOPLE}/{nd.fake.id_of(name)}/permissions", json=body)


def test_permissions_are_saved_as_differences_and_in_force_at_the_next_request(nd, caplog):
    caplog.set_level(logging.INFO)
    ethan = signed_in(nd, "ethan")
    assert ethan.get(ME).json()["permissions"] == ["request"]
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    answer = tick(admin, nd, edit=True, library=True, request=False)
    assert answer.json()["permissions"] == {"request": False, "edit": True, "library": True, "downloads": False, "server": False}
    with sqlite3.connect(nd.path) as connection:
        rows = connection.execute("SELECT permission, granted, navidrome_id, changed_by FROM permissions ORDER BY permission").fetchall()
    assert rows == [("edit", 1, nd.fake.id_of("ethan"), "admin"), ("library", 1, nd.fake.id_of("ethan"), "admin"),
                    ("request", 0, nd.fake.id_of("ethan"), "admin")]
    assert "admin gave ethan Edit albums and Look after the library; took away Get albums" in caplog.text
    #? his session read no account id (he had no grant as he signed in) - the grants wait; the restriction doesn't
    me = ethan.get(ME).json()
    assert me["permissions"] == [] and me["permissions_unverified"] is True
    assert ethan.post("/deadwax/download/enqueue", json={}).status_code == 403
    #? the People list heals his session with his account's id: in force at his next request, no sign-in
    admin.get(PEOPLE)
    assert ethan.get(ME).json()["permissions"] == ["edit", "library"]
    assert ethan.get("/deadwax/library/queue/summary").status_code != 403
    #? and taken back
    tick(admin, nd)
    assert ethan.get(ME).json()["permissions"] == ["request"]
    with sqlite3.connect(nd.path) as connection:
        assert connection.execute("SELECT COUNT(*) FROM permissions").fetchone()[0] == 0


def test_a_sign_in_reads_the_account_id_only_for_someone_with_a_grant_through_the_gate(nd):
    signed_in(nd, "james")
    assert nd.fake.native() == []
    permissions.set_for(nd.store, "ethan", nd.fake.id_of("ethan"), {"request": True, "edit": True, "library": False,
                                                                   "downloads": False, "server": False}, "admin")
    ethan = signed_in(nd, "ethan")
    [login] = nd.fake.native()
    assert login["path"] == "/auth/login" and login["body"]["username"] == "ethan"
    assert ethan.get(ME).json()["permissions"] == ["request", "edit"]
    #? the gate full: the sign-in goes on, the grant isn't honoured, a restriction still is
    for _ in range(navidrome_admin.LOGIN_GATE):
        navidrome_admin._logins.append(nd.clock[0])
    permissions.set_for(nd.store, "ethan", nd.fake.id_of("ethan"), {"request": False, "edit": True, "library": False,
                                                                   "downloads": False, "server": False}, "admin")
    held = signed_in(nd, "ethan")
    me = held.get(ME).json()
    assert me["permissions"] == [] and me["permissions_unverified"] is True
    assert len(nd.fake.native()) == 1


def test_a_grant_for_an_account_removed_and_made_again_is_dropped_at_the_sign_in(nd, caplog):
    caplog.set_level(logging.INFO)
    permissions.set_for(nd.store, "ethan", nd.fake.id_of("ethan"), {"request": True, "edit": True, "library": False,
                                                                   "downloads": False, "server": False}, "admin")
    nd.fake.remove("ethan")
    nd.fake.add("ethan", "ethan-navidrome-pw")
    ethan = signed_in(nd, "ethan")
    assert ethan.get(ME).json()["permissions"] == ["request"]
    assert "ethan's account isn't the one those permissions were given to" in caplog.text
    assert nd.store.permission_rows() == []


def test_the_people_list_drops_a_grant_given_to_an_account_since_removed_and_made_again(nd, caplog):
    """(review) ethan, given Edit albums, signs in (his session reads his account's id); his account is then removed
    in Navidrome's own Users page and made again under the same name and password - so his old session survives the
    re-check. An admin's People list, naming the new id, is what drops the old account's grant."""
    caplog.set_level(logging.INFO)
    permissions.set_for(nd.store, "ethan", nd.fake.id_of("ethan"), {"request": True, "edit": True, "library": False,
                                                                   "downloads": False, "server": False}, "admin")
    ethan = signed_in(nd, "ethan")
    assert ethan.get(ME).json()["permissions"] == ["request", "edit"]
    nd.fake.remove("ethan")
    nd.fake.add("ethan", "ethan-navidrome-pw")
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    assert admin.get(PEOPLE).status_code == 200
    assert nd.store.permission_rows() == []
    assert "ethan's account isn't the one those permissions were given to" in caplog.text
    assert ethan.get(ME).json()["permissions"] == ["request"]


def test_the_people_list_never_hands_a_remade_account_an_earlier_ones_sessions(nd):
    """(review) ethan #1 signed in with no grant, so his session read no account id. Removed and made again in
    Navidrome (another id, made after that session began), the new ethan is given Settings and the log - and the
    old session, which only the re-check will end, is not healed into the new account and gets none of it."""
    old = signed_in(nd, "ethan")
    nd.fake.remove("ethan")
    nd.fake.add("ethan", "ethan-navidrome-pw")
    later_by = rules.made_at(nd.fake.by_name("ethan"))
    assert later_by is not None
    #? made a few seconds after the session began, whatever the clocks' grain
    nd.fake.by_name("ethan")["createdAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 5))
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    assert tick(admin, nd, server=True).status_code == 200
    admin.get(PEOPLE)
    me = old.get(ME).json()
    assert me["permissions"] == ["request"] and me["permissions_unverified"] is True
    assert old.get("/deadwax/settings").status_code == 403
    #? a sign-in as the new account reads its id, and has it
    act(nd, None)
    assert "server" in signed_in(nd, "ethan").get(ME).json()["permissions"]


def test_an_accounts_made_at_is_read_as_go_writes_it_and_never_guessed():
    assert rules.made_at({"createdAt": "2026-10-21T12:00:00Z"}) == 1792584000.0
    assert rules.made_at({"createdAt": "2026-10-21T12:00:00.123456789Z"}) == pytest.approx(1792584000.123456)
    assert rules.made_at({"createdAt": "2026-10-21T13:00:00+01:00"}) == 1792584000.0
    for nothing in (None, "", "yesterday", "0001-01-01T00:00:00Z", 12345):
        assert rules.made_at({"createdAt": nothing}) is None


def test_a_permissions_save_leaving_a_category_out_is_refused_never_a_restriction(nd):
    """(review) All five are required: a body without one is the People 422 in words, and nothing is saved."""
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    answer = admin.post(f"{PEOPLE}/{nd.fake.id_of('ethan')}/permissions", json={"user": "ethan", "edit": True})
    assert answer.status_code == 422 and answer.json()["detail"] == PEOPLE_FORM
    assert nd.store.permission_rows() == [] and nd.fake.writes() == []


def test_the_permissions_route_refuses_admins_yourself_the_shared_account_and_reserved_names(nd):
    nd.fake.add("local", "local-navidrome-pw")
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    for name, said in [("admin", rules.YOUR_PERMISSIONS), ("demo", rules.SHARED_ACCOUNT), ("local", rules.RESERVED_PERMISSIONS)]:
        answer = tick(admin, nd, name, edit=True)
        assert answer.status_code == 409 and answer.json()["detail"] == said
    nd.fake.by_name("ethan")["isAdmin"] = True
    assert tick(admin, nd, edit=True).json()["detail"] == rules.ADMIN_PERMISSIONS
    assert nd.store.permission_rows() == []
    #? there is no `people` to send
    answer = admin.post(f"{PEOPLE}/{nd.fake.id_of('james')}/permissions", json={"user": "james", "people": True})
    assert answer.status_code == 422


def test_permissions_fail_closed_when_the_table_cant_be_read_and_are_read_again_a_minute_on(nd, monkeypatch):
    ethan = signed_in(nd, "ethan")
    permissions.forget_all()
    real = nd.store.permission_rows

    def broken():
        raise sqlite3.OperationalError("no such table: permissions")

    monkeypatch.setattr(nd.store, "permission_rows", broken)
    assert ethan.get(ME).json()["permissions"] == []
    assert ethan.post("/deadwax/download/enqueue", json={}).status_code == 403
    monkeypatch.setattr(nd.store, "permission_rows", real)
    assert ethan.get(ME).json()["permissions"] == []        # not asked again within the minute
    now = time.monotonic
    monkeypatch.setattr(permissions.time, "monotonic", lambda: now() + permissions.RETRY_SECONDS + 1)
    assert ethan.get(ME).json()["permissions"] == ["request"]
    #? an admin is never held up by it
    assert signed_in(nd, "admin").get(ME).json()["permissions"] == list(PERMISSIONS)


def test_a_promoted_person_keeps_their_rows_for_if_they_are_unmade(nd):
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    tick(admin, nd, edit=True)
    make_admin(admin, nd)
    assert len(nd.store.permission_rows()) == 1
    assert listed(admin)["ethan"]["permissions"] is None
    make_admin(admin, nd, admin=False)
    assert listed(admin)["ethan"]["permissions"]["edit"] is True


# ----------------------------------------------------------------- the rate limit, and one at a time

def test_the_eleventh_write_in_a_minute_is_refused_with_nothing_sent(nd):
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    for _ in range(routes.WRITES_PER_MINUTE):
        assert tick(admin, nd).status_code == 200
    sent = len(nd.fake.requests)
    held = tick(admin, nd)
    assert held.status_code == 429 and int(held.headers["retry-after"]) > 0 and held.json()["kind"] == "busy"
    assert len(nd.fake.requests) == sent
    later(nd, routes.WRITE_WINDOW)
    assert tick(admin, nd).status_code == 200


def test_writes_run_one_at_a_time(nd, monkeypatch):
    unlocked(nd, "admin")
    act(nd, "admin")
    inside, most = [0], [0]
    real = navidrome_admin.get_user

    async def slow(unlock, person_id):
        inside[0] += 1
        most[0] = max(most[0], inside[0])
        await asyncio.sleep(0.02)
        try:
            return await real(unlock, person_id)
        finally:
            inside[0] -= 1

    monkeypatch.setattr(navidrome_admin, "get_user", slow)
    key = next(iter(navidrome_admin._unlocked))
    held = navidrome_admin._unlocked[key]

    async def both():
        async def one(name):
            async with routes._write_lock():
                await navidrome_admin.get_user(held, nd.fake.id_of(name))
        await asyncio.gather(one("ethan"), one("james"))

    run(both())
    assert most[0] == 1


def test_writes_sent_together_through_the_routes_run_one_at_a_time(nd, monkeypatch):
    """(review) The lock in _write itself - two People writes sent at once, through the app, never interleave (the
    guards and the stale-record checks hold only if they can't)."""
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    raw = admin.cookies[auth.COOKIE]
    inside, most = [0], [0]
    real = navidrome_admin.get_user

    async def slow(unlock, person_id):
        inside[0] += 1
        most[0] = max(most[0], inside[0])
        await asyncio.sleep(0.05)
        try:
            return await real(unlock, person_id)
        finally:
            inside[0] -= 1

    monkeypatch.setattr(navidrome_admin, "get_user", slow)
    body = {"request": True, "edit": True, "library": False, "downloads": False, "server": False}

    async def together():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=nd.app), base_url="http://testserver",
                                     cookies={auth.COOKIE: raw}) as client:
            return await asyncio.gather(
                client.post(f"{PEOPLE}/{nd.fake.id_of('ethan')}/permissions", json={"user": "ethan", **body}),
                client.post(f"{PEOPLE}/{nd.fake.id_of('james')}/permissions", json={"user": "james", **body}))

    answers = run(together())
    assert [answer.status_code for answer in answers] == [200, 200]
    assert most[0] == 1


# ----------------------------------------------------------------- nothing leaks

def test_no_password_jwt_or_token_reaches_a_log_line_or_an_answer(nd, caplog):
    caplog.set_level(logging.DEBUG)
    answers = []
    ethan = signed_in(nd, "ethan")
    admin = signed_in(nd, "admin")
    answers.append(unlock(nd, admin, "admin", "a-wrong-guess-pw"))
    answers.append(unlock(nd, admin, "admin"))
    act(nd, "admin")
    answers += [admin.get(PEOPLE), make(admin), reset(admin, nd), tick(admin, nd, edit=True), make_admin(admin, nd, "james"),
                remove(admin, nd, "maya"), admin.post(f"{PEOPLE}/create", json={"user": "x", "password": "sekret-in-a-422", "bogus": 1})]
    assert ethan is not None
    seen = caplog.text + "".join(answer.text + json.dumps(dict(answer.headers)) for answer in answers)
    jwts = [token for token in nd.fake.tokens]
    for secret in (password(nd, "admin"), "a-wrong-guess-pw", "maya-password", NEW_PASSWORD, "sekret-in-a-422",
                   "0123456789abcdef0123456789abcdef", "subsonicToken", *jwts):
        assert secret not in seen, secret
    assert answers[-1].json() == {"detail": PEOPLE_FORM}


def test_a_native_errors_words_carry_no_url_body_or_header():
    error = navidrome_admin.NativeError("unknown_shape", "Navidrome answered in a way deadwax doesn't know (500).", 502)
    assert str(error) == error.words and "http" not in str(error) and "Bearer" not in str(error)


# ----------------------------------------------------------------- the fixed list, frames, the page's numbers

def test_the_native_api_is_a_fixed_list(nd):
    """Every request the fake sees across this module is one of six shapes (each test's own walk here, and every
    test's in the `nd` fixture's teardown); the module's public names are the six
    operations and the few around them; only routes/people.py, routes/own_password.py (2.0.2) and auth.py import it;
    nothing a page sends becomes a path or a method (only an id that matched ID_PATTERN does)."""
    tree = ast.parse((ROOT / "src/api/navidrome_admin.py").read_text())
    public = {node.name for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
              and not node.name.startswith("_")}
    assert public == {"login", "list_users", "get_user", "create_user", "save_user", "delete_user", "Unlock",
                      "NativeError", "forget", "forget_all", "forget_user", "unlocked", "close_client"}
    importers = sorted(str(path.relative_to(ROOT)) for path in (ROOT / "src").rglob("*.py")
                       if re.search(r"navidrome_admin", path.read_text()) and path.name != "navidrome_admin.py")
    assert importers == ["src/api/app.py", "src/auth.py", "src/routes/own_password.py", "src/routes/people.py"]
    #? app.py only closes it, in the lifespan
    assert re.findall(r"navidrome_admin\.\w+", (ROOT / "src/api/app.py").read_text()) == ["navidrome_admin.close_client"]
    #? a walk through every route, then every request the fake saw
    admin = unlocked(nd, "admin")
    act(nd, "admin")
    make(admin), reset(admin, nd), make_admin(admin, nd, "james"), tick(admin, nd, edit=True), remove(admin, nd, "maya")
    admin.post(f"{PEOPLE}/{'..%2F..%2Fapi'}/remove", json={"user": "x", "confirm": "x"})
    shapes = native_shapes(nd.fake)
    assert shapes == SIX


@pytest.mark.parametrize("mode", ["on", "off"])
def test_every_page_refuses_to_be_framed(nd, monkeypatch, mode):
    monkeypatch.setattr(Config, "AUTH_MODE", mode)
    client = TestClient(start())
    for path in ("/player/", "/", "/player/lab/", "/index.html"):
        answer = client.get(path)
        assert answer.status_code == 200, path
        assert answer.headers["x-frame-options"] == "DENY", path
        assert answer.headers["content-security-policy"] == "frame-ancestors 'none'", path
    #? never anything that isn't a page
    assert "x-frame-options" not in client.get("/styles/theme.css").headers


def test_the_pages_numbers_are_the_servers():
    source = (ROOT / "ui/src/lib/people.ts").read_text()

    def number(name):
        return int(re.search(rf"export const {name} = (\d+)", source).group(1))

    assert number("NAME_MAX") == rules.NAME_MAX and number("DISPLAY_MAX") == rules.DISPLAY_MAX
    assert number("PASSWORD_MIN") == rules.PASSWORD_MIN and number("PASSWORD_MAX") == rules.PASSWORD_MAX
    assert re.search(r"export const NAME_PATTERN = /(.+)/\n", source).group(1) == rules.NAME_PATTERN
    assert re.search(r"export const UNLOCK_IDLE_MINUTES = (\d+)", source).group(1) == str(int(navidrome_admin.UNLOCK_IDLE_SECONDS // 60))
