"""
Change your own password (2.0.2) - src/routes/own_password.py, `POST /deadwax/me/password`, with auth.own_password_changed
and auth.superseded - through start() with a real SQLite store, logins on, and the fake Navidrome People's tests use
(tests/navidrome_native_fake.py: its native API and Subsonic getUser over one set of accounts, shaped from Navidrome
0.64.2's source - validatePasswordChange's currentPassword, EnableUserEditing, the token epoch's bump).

What these hold (the spec's list, each mutation-checked):

  - Refused with nothing sent: logins off, break-glass, NAVIDROME_USER's account; the new password's rules (People's)
    and the same password again; no current password.
  - The current password checked against the session's kept login first: a wrong one never reaches Navidrome and
    counts in the sign-in throttle; three in a minute and even the right one waits.
  - As the person, three of People's six calls: /auth/login with the current password, GET their record, PUT it back
    whole with `password` and `currentPassword`; then one getUser with the new password.
  - Success: this session re-sealed (it keeps working - with Navidrome, the re-check and the stars), every other
    session of theirs ended with PASSWORD_CHANGED, their kept login the new one, alive; People's unlock dropped.
  - Navidrome failing part-way - its 403 (EnableUserEditing off), a timeout, a password it ignores, not answering -
    re-seals nothing and ends nothing.
  - While the change is under way, and after it, a refusal of the old login never ends this session.
  - At most CHANGES_PER_MINUTE tries a minute; never a password in a log line, an answer or a 422.
"""

import asyncio
import json
import logging
import sys
import time
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import auth  # noqa: E402
from src.api import navidrome_admin, navidrome_endpoint  # noqa: E402
from src.config import Config  # noqa: E402
from src.people import PASSWORD_MAX  # noqa: E402
from src.routes import own_password as routes  # noqa: E402
from tests import test_people  # noqa: E402
from tests.test_people import LOGIN, ME, NAVIDROME, PEOPLE, act, later, password, signed_in, unlock  # noqa: E402

#? People's fixture - its app, store and fake Navidrome - which `own` builds on
nd = test_people.nd

CHANGE = "/deadwax/me/password"
NEW = "a-fresh-own-password"


def run(coroutine):
    return asyncio.run(coroutine)


@pytest.fixture
def own(nd, monkeypatch):
    """People's `nd`, and the change's own clock - apart from Navidrome's, so a test can let Navidrome's login budget
    come back without the change's minute passing."""
    clock = [50_000.0]
    monkeypatch.setattr(routes, "_clock", lambda: clock[0])
    routes.forget_tries()
    nd.own_clock = clock
    yield nd
    routes.forget_tries()


def change(nd, client: TestClient, name: str, current: str | None = None, new: str = NEW, again: str | None = None):
    later(nd)
    act(nd, name)
    return client.post(CHANGE, json={"current": password(nd, name) if current is None else current, "password": new,
                                     "password_again": new if again is None else again})


def key_of(client: TestClient) -> str:
    return auth.id_hash(client.cookies[auth.COOKIE])


def kept(nd, client: TestClient) -> tuple[str, str, str]:
    """The login the session's row keeps, opened."""
    return auth.unseal_credential(nd.store.session(key_of(client))["credential"])


def works(login: tuple[str, str, str], pw: str) -> bool:
    _name, token, salt = login
    return token == auth.subsonic_token(pw, salt)


# ----------------------------------------------------------------- refused, with nothing sent

def test_logins_off_has_no_password_of_yours_to_change(own, monkeypatch):
    monkeypatch.setattr(Config, "AUTH_MODE", "off")
    answer = TestClient(own.app).post(CHANGE, json={"current": "whatever-it-is", "password": NEW, "password_again": NEW})
    assert answer.status_code == 409 and answer.json() == {"detail": routes.LOGINS_OFF, "kind": "off", "fix": None}
    assert own.fake.requests == []


def test_break_glass_has_no_navidrome_password_to_change(own):
    glass = signed_in(own, auth.BREAK_GLASS_USER)
    answer = glass.post(CHANGE, json={"current": "break-the-glass-please", "password": NEW, "password_again": NEW})
    assert answer.status_code == 409 and answer.json()["detail"] == routes.BREAK_GLASS
    assert own.fake.native() == []


def test_deadwaxs_own_account_is_refused_with_nothing_sent(own, monkeypatch):
    ethan = signed_in(own, "ethan")
    asked = len(own.fake.requests)
    monkeypatch.setattr(Config, "NAVIDROME_USER", "Ethan")          # ethan's account is deadwax's own now
    answer = change(own, ethan, "ethan")
    assert answer.status_code == 409 and answer.json()["detail"] == routes.SHARED_ACCOUNT
    assert len(own.fake.requests) == asked and works(kept(own, ethan), password(own, "ethan"))


@pytest.mark.parametrize("current, new, again, said", [
    ("", NEW, NEW, routes.NO_CURRENT),
    (None, "short", "short", "A password is at least 8 characters."),
    (None, "x" * (PASSWORD_MAX + 1), "x" * (PASSWORD_MAX + 1), "A password is at most 128 characters."),
    (None, "EthanEthan", "EthanEthan", None),                        # fine: not the name
    (None, "ETHAN", "ETHAN", "A password is at least 8 characters."),
    (None, NEW, NEW + "x", "The two passwords aren't the same."),
    (None, "tab\there-pw", "tab\there-pw", "A password can't have control characters in it."),
    (None, "ethan-navidrome-pw", "ethan-navidrome-pw", routes.SAME_PASSWORD),
])
def test_the_forms_rules_refuse_with_nothing_sent(own, current, new, again, said):
    ethan = signed_in(own, "ethan")
    asked = len(own.fake.requests)
    answer = change(own, ethan, "ethan", current, new, again)
    if said is None:
        assert answer.status_code == 200, answer.text
        return
    assert answer.status_code == 400 and answer.json() == {"detail": said, "kind": "form", "fix": None}
    assert len(own.fake.requests) == asked


def test_a_password_that_is_the_user_name_is_refused(own):
    own.fake.add("maya-long-name", "maya-original-pw")
    maya = signed_in(own, "maya-long-name")
    answer = change(own, maya, "maya-long-name", new="Maya-Long-Name")
    assert answer.status_code == 400 and answer.json()["detail"] == "A password can't be the user name."


def test_a_wrong_current_password_never_reaches_navidrome_and_counts_in_the_throttle(own):
    ethan = signed_in(own, "ethan")
    asked = len(own.fake.requests)
    for _ in range(3):
        answer = change(own, ethan, "ethan", current="not-my-password")
        assert answer.status_code == 409 and answer.json()["detail"] == routes.NOT_YOUR_PASSWORD
        own.clock[0] -= 21                                 # the sign-in throttle's minute: still the same one
    assert len(own.fake.requests) == asked
    held = change(own, ethan, "ethan")
    assert held.status_code == 429 and "Too many tries for ethan" in held.json()["detail"]
    assert len(own.fake.requests) == asked and works(kept(own, ethan), password(own, "ethan"))


def test_a_change_that_goes_through_clears_the_sign_in_throttle(own):
    """(review) As a sign-in and People's unlock do: two typos, then the right one, leave nothing counted."""
    ethan = signed_in(own, "ethan")
    for _ in range(2):
        assert change(own, ethan, "ethan", current="not-my-password").json()["kind"] == "not_your_password"
        own.clock[0] -= 21
    assert change(own, ethan, "ethan").status_code == 200
    own.clock[0] -= 21
    act(own, None)
    wrong = TestClient(own.app).post("/deadwax/auth/login", json={"username": "ethan", "password": "another-typo-pw"})
    assert wrong.status_code == 401
    #? one failure counted, not three: the right one signs in at once
    right = TestClient(own.app).post("/deadwax/auth/login", json={"username": "ethan", "password": NEW})
    assert right.status_code == 200, right.text


def test_at_most_five_tries_a_minute_then_nothing_sent(own):
    own.fake.enable_user_editing = False                   # each try reaches Navidrome and is refused there
    ethan = signed_in(own, "ethan")
    for _ in range(routes.CHANGES_PER_MINUTE):
        assert change(own, ethan, "ethan").status_code == 403
    asked = len(own.fake.requests)
    answer = change(own, ethan, "ethan")
    assert answer.status_code == 429 and answer.json()["kind"] == "busy"
    assert answer.json()["detail"] == routes.TOO_MANY.format(seconds=60) and answer.headers["Retry-After"] == "60"
    assert len(own.fake.requests) == asked
    own.own_clock[0] += routes.CHANGE_WINDOW
    assert change(own, ethan, "ethan").status_code == 403


def test_deadwaxs_login_gate_holds_it_off_with_nothing_sent(own):
    ethan = signed_in(own, "ethan")
    later(own)
    for _ in range(navidrome_admin.LOGIN_GATE):
        navidrome_admin._logins.append(own.clock[0])
    asked = len(own.fake.requests)
    act(own, "ethan")
    answer = ethan.post(CHANGE, json={"current": password(own, "ethan"), "password": NEW, "password_again": NEW})
    assert answer.status_code == 429 and answer.json()["kind"] == "held_off" and "Retry-After" in answer.headers
    assert len(own.fake.requests) == asked


# ----------------------------------------------------------------- as the person, and what follows

def test_it_is_three_calls_as_you_the_record_put_back_whole_and_proved(own):
    ethan = signed_in(own, "ethan")
    before = dict(own.fake.by_name("ethan"))
    old = password(own, "ethan")
    seen = len(own.fake.requests)
    answer = change(own, ethan, "ethan")
    assert answer.status_code == 200 and answer.json() == {"changed": True, "signed_out": 0, "warning": None}
    sent = own.fake.requests[seen:]
    assert [(r["method"], r["path"]) for r in sent] == [
        ("POST", "/auth/login"), ("GET", f"/api/user/{before['id']}"), ("PUT", f"/api/user/{before['id']}"),
        ("GET", "/rest/getUser")]
    assert sent[0]["body"] == {"username": "ethan", "password": old}
    assert sent[2]["body"] == {**before, "password": NEW, "currentPassword": old}
    #? the proof: Subsonic, as them, with the new password
    assert sent[3]["query"]["u"] == "ethan" and sent[3]["query"]["t"] == auth.subsonic_token(NEW, sent[3]["query"]["s"])
    after = own.fake.by_name("ethan")
    assert (after["userName"], after["name"], after["email"], after["isAdmin"]) == ("ethan", "Ethan", "ethan@example.com", False)
    assert password(own, "ethan") == NEW


def test_this_session_keeps_working_and_every_other_device_signs_in_again(own):
    phone, laptop, tablet = signed_in(own, "ethan"), signed_in(own, "ethan"), signed_in(own, "ethan")
    james = signed_in(own, "james")
    assert laptop.get(ME).status_code == 200                # held in memory
    tablet_raw = tablet.cookies[auth.COOKIE]
    answer = change(own, phone, "ethan")
    assert answer.json() == {"changed": True, "signed_out": 2, "warning": None}
    #? this one: still signed in, its login the new password's - in the database and in memory
    assert phone.get(ME).json()["user"] == "ethan"
    assert works(kept(own, phone), NEW)
    with auth._lock:
        assert works(auth.unseal_credential(auth._held[key_of(phone)].credential), NEW)
    #? Navidrome takes it, as the player asks
    assert run(auth.check_login(*kept(own, phone)))[0] == "ethan"
    #? the others: ended at once, told why - and gone from the database, so a restart brings none back
    assert laptop.get(ME).json()["detail"] == auth.PASSWORD_CHANGED
    assert tablet.get(ME).json()["detail"] == auth.PASSWORD_CHANGED
    assert own.store.session_keys("ethan") == [key_of(phone)]
    auth.forget_sessions()
    replay = TestClient(own.app)
    replay.cookies.set(auth.COOKIE, tablet_raw)
    assert replay.get(ME).status_code == 401
    assert phone.get(ME).json()["user"] == "ethan"
    assert james.get(ME).json()["user"] == "james"
    #? their kept login, for starring, is the new one and alive
    row = own.store.credential_row("ethan")
    assert row["dead_at"] is None and works(auth.unseal_credential(row["credential"]), NEW)
    #? the re-check vouches for this session with the new login and ends nothing
    counts = run(auth.check_sessions(own.store, now=time.time() + auth.RECHECK_SECONDS + 1))
    assert counts["ended"] == 0 and phone.get(ME).json()["user"] == "ethan"
    #? the new password signs in; the old one doesn't
    act(own, None)
    assert signed_in(own, "ethan", NEW).get(ME).json()["user"] == "ethan"
    assert TestClient(own.app).post("/deadwax/auth/login", json={"username": "ethan", "password": "ethan-navidrome-pw"}).status_code == 401


def test_the_kept_login_comes_alive_what_waits_is_asked_about_at_once_and_this_session_is_vouched_for(own):
    """(review) store.own_password_changed's three other writes, as a sign-in's keep_credential has them."""
    ethan = signed_in(own, "ethan")
    sealed = own.store.session(key_of(ethan))["credential"]
    assert own.store.credential_dead("ethan", auth.LOGIN_GONE, sealed, time.time())   # the stars worker gave up on it
    assert run(own.store.grant_albums(["ethan"], [7], "requested")) == 1
    with own.store._connect() as connection:
        connection.execute("UPDATE library_membership SET next_try = ? WHERE user = 'ethan'", (time.time() + 9999,))
        connection.execute("UPDATE sessions SET checked_at = 0 WHERE user = 'ethan'")
    started = time.time()
    assert change(own, ethan, "ethan").status_code == 200
    row = own.store.credential_row("ethan")
    assert row["dead_at"] is None and row["dead_why"] is None and works(auth.unseal_credential(row["credential"]), NEW)
    with own.store._connect() as connection:
        waiting = connection.execute("SELECT next_try FROM library_membership WHERE user = 'ethan'").fetchone()[0]
    assert started - 1 <= waiting <= time.time() + 1
    assert own.store.session(key_of(ethan))["checked_at"] >= started - 1


def test_the_answer_and_the_log_say_how_many_devices(own, caplog):
    caplog.set_level(logging.INFO)
    phone = signed_in(own, "ethan")
    signed_in(own, "ethan")                                  # a laptop too
    assert change(own, phone, "ethan").json()["signed_out"] == 1
    assert "ethan changed their Navidrome password (signed out of 1 other device)" in caplog.text


def test_a_session_already_run_out_is_cleared_but_not_counted_as_a_device(own):
    phone, laptop = signed_in(own, "ethan"), signed_in(own, "ethan")
    sealed = own.store.session(key_of(laptop))["credential"]
    own.store.create_session("an-expired-one", "ethan", sealed, time.time() - 100, time.time() - 10)
    answer = change(own, phone, "ethan")
    assert answer.json()["signed_out"] == 1
    assert own.store.session_keys("ethan") == [key_of(phone)]


def test_an_admin_changes_their_own_and_their_people_unlocks_go(own):
    here, there = signed_in(own, "admin"), signed_in(own, "admin")
    assert unlock(own, here, "admin").status_code == 200
    assert unlock(own, there, "admin").status_code == 200
    assert navidrome_admin.unlocked(key_of(here)) is not None
    old = password(own, "admin")
    answer = change(own, here, "admin", current=old)
    assert answer.status_code == 200 and answer.json()["signed_out"] == 1
    assert navidrome_admin.unlocked(key_of(here)) is None and navidrome_admin.unlocked(key_of(there)) is None
    assert not any(held.user == "admin" for held in navidrome_admin._unlocked.values())
    #? People asks for the password again - the new one
    assert here.get(PEOPLE).json()["locked"] is True
    assert unlock(own, here, "admin", NEW).status_code == 200
    assert own.fake.by_name("admin")["isAdmin"] is True


def test_enable_user_editing_off_is_said_and_changes_nothing(own):
    own.fake.enable_user_editing = False
    ethan, other = signed_in(own, "ethan"), signed_in(own, "ethan")
    before = own.store.session(key_of(ethan))["credential"]
    answer = change(own, ethan, "ethan")
    assert answer.status_code == 403 and answer.json() == {"detail": routes.EDITING_OFF, "kind": "editing_off", "fix": None}
    assert password(own, "ethan") == "ethan-navidrome-pw"
    assert own.store.session(key_of(ethan))["credential"] == before
    assert other.get(ME).json()["user"] == "ethan" and ethan.get(ME).json()["user"] == "ethan"
    #? an admin's own record is theirs to change whatever the setting, as Navidrome has it
    admin = signed_in(own, "admin")
    assert change(own, admin, "admin").status_code == 200


@pytest.mark.parametrize("how, status, said", [
    ("timeout", 504, routes.TIMED_OUT),
    ("ignore_password", 502, routes.DIDNT_TAKE),
    ("one_unread", 503, routes.UNREACHABLE),
    ("down", 503, routes.UNREACHABLE),
])
def test_navidrome_failing_part_way_reseals_nothing_and_ends_nothing(own, how, status, said):
    ethan, other = signed_in(own, "ethan"), signed_in(own, "ethan")
    assert other.get(ME).status_code == 200
    before = own.store.session(key_of(ethan))["credential"]
    kept_before = own.store.credential_row("ethan")["credential"]
    if how == "timeout":
        own.fake.timeout = {"PUT"}
    else:
        setattr(own.fake, how, True)
    answer = change(own, ethan, "ethan")
    assert answer.status_code == status and answer.json()["detail"] == said
    own.fake.down = own.fake.one_unread = False
    assert own.store.session(key_of(ethan))["credential"] == before
    assert own.store.credential_row("ethan")["credential"] == kept_before
    assert sorted(own.store.session_keys("ethan")) == sorted([key_of(ethan), key_of(other)])
    assert ethan.get(ME).json()["user"] == "ethan" and other.get(ME).json()["user"] == "ethan"


def test_a_put_that_landed_with_its_answer_lost_is_proved_and_kept(own):
    """(review) The PUT carried out and its answer lost (the connection dropped - `timed_out`): the proof says the new
    password works, so the change carries on as an answered one - this session re-sealed, the others signed out."""
    ethan, other = signed_in(own, "ethan"), signed_in(own, "ethan")
    own.fake.dropped = {"PUT"}
    answer = change(own, ethan, "ethan")
    assert answer.status_code == 200 and answer.json() == {"changed": True, "signed_out": 1, "warning": None}
    assert password(own, "ethan") == NEW and works(kept(own, ethan), NEW)
    assert other.get(ME).json()["detail"] == auth.PASSWORD_CHANGED


def _saved_then_unreadable(monkeypatch, land: bool = True):
    real = navidrome_admin.save_user

    async def unreadable(unlock_, navidrome_id, record):
        if land:
            await real(unlock_, navidrome_id, record)
        raise navidrome_admin._error("unknown_shape", "a saved user")
    monkeypatch.setattr(navidrome_admin, "save_user", unreadable)


def test_a_put_answered_in_a_shape_deadwax_doesnt_know_is_proved_and_kept_when_it_took(own, monkeypatch):
    _saved_then_unreadable(monkeypatch)
    ethan = signed_in(own, "ethan")
    answer = change(own, ethan, "ethan")
    assert answer.status_code == 200 and answer.json()["changed"] is True
    assert works(kept(own, ethan), NEW) and own.store.credential_row("ethan")["dead_at"] is None


def test_an_unreadable_put_that_didnt_take_says_nothing_changed(own, monkeypatch):
    _saved_then_unreadable(monkeypatch, land=False)
    ethan = signed_in(own, "ethan")
    before = own.store.session(key_of(ethan))["credential"]
    answer = change(own, ethan, "ethan")
    assert answer.status_code == 502 and answer.json()["detail"] == routes.UNKNOWN.format("a saved user")
    assert own.store.session(key_of(ethan))["credential"] == before


def test_an_unreadable_put_that_cant_be_proved_says_it_cant_tell(own, monkeypatch):
    _saved_then_unreadable(monkeypatch)

    async def unanswered(name, pw):
        return None
    monkeypatch.setattr(routes, "_signs_in_with", unanswered)
    ethan = signed_in(own, "ethan")
    answer = change(own, ethan, "ethan")
    assert answer.status_code == 502 and answer.json() == {"detail": routes.UNKNOWN_SAVED.format("a saved user"),
                                                           "kind": "unknown_shape", "fix": None}
    assert "nothing changed" not in answer.json()["detail"]


def test_navidrome_unable_to_answer_the_proof_still_keeps_the_change_with_a_warning(own, monkeypatch):
    async def unanswered(name, pw):
        return None
    monkeypatch.setattr(routes, "_signs_in_with", unanswered)
    ethan = signed_in(own, "ethan")
    answer = change(own, ethan, "ethan")
    assert answer.json() == {"changed": True, "signed_out": 0, "warning": routes.UNCHECKED}
    assert works(kept(own, ethan), NEW)


def test_navidrome_refusing_a_current_password_the_local_check_passed_ends_the_session(own):
    ethan = signed_in(own, "ethan")
    old = password(own, "ethan")
    own.fake.set_password("ethan", "changed-in-navidrome")   # changed in Navidrome itself since this sign-in
    answer = change(own, ethan, "ethan", current=old)
    assert answer.status_code == 401 and answer.json()["detail"] == auth.LOGIN_GONE
    assert ethan.get(ME).json()["detail"] == auth.LOGIN_GONE
    assert [r["method"] for r in own.fake.native()] == ["POST"]


def test_a_save_refused_by_navidrome_while_another_device_changes_it_is_told_why(own):
    """(review 2) The desktop's own Save, or People's unlock, reaching Navidrome just after the phone's change took:
    its old login is refused there - the phone's change, so the 401 says PASSWORD_CHANGED, as /me then does."""
    phone, desktop = signed_in(own, "ethan"), signed_in(own, "ethan")
    admin_phone, admin_desktop = signed_in(own, "admin"), signed_in(own, "admin")
    ethans_old, admins_old = password(own, "ethan"), password(own, "admin")
    own.fake.set_password("ethan", NEW)
    own.fake.set_password("admin", NEW)
    with auth.changing_password(key_of(phone), "ethan"), auth.changing_password(key_of(admin_phone), "admin"):
        answer = change(own, desktop, "ethan", current=ethans_old, new="another-new-one")
        unlocked = unlock(own, admin_desktop, "admin", admins_old)
    assert answer.status_code == 401 and answer.json()["detail"] == auth.PASSWORD_CHANGED, answer.text
    assert unlocked.status_code == 401 and unlocked.json()["detail"] == auth.PASSWORD_CHANGED, unlocked.text


def test_navidromes_own_current_password_refusal_is_said(own, monkeypatch):
    real = navidrome_admin.save_user

    async def stale(unlock_, navidrome_id, record):
        return await real(unlock_, navidrome_id, {**record, "currentPassword": "something-else-pw"})
    monkeypatch.setattr(navidrome_admin, "save_user", stale)
    ethan = signed_in(own, "ethan")
    answer = change(own, ethan, "ethan")
    assert answer.status_code == 409 and answer.json()["detail"] == routes.WRONG_CURRENT
    assert password(own, "ethan") == "ethan-navidrome-pw"


def test_a_record_navidrome_answers_for_someone_else_is_never_put_back(own, monkeypatch):
    real = navidrome_admin.get_user

    async def someone_else(unlock_, navidrome_id):
        return {**await real(unlock_, navidrome_id), "userName": "james"}
    monkeypatch.setattr(navidrome_admin, "get_user", someone_else)
    ethan = signed_in(own, "ethan")
    answer = change(own, ethan, "ethan")
    assert answer.status_code == 409 and answer.json()["detail"] == routes.STALE
    assert own.fake.writes() == [] and password(own, "ethan") == "ethan-navidrome-pw"


# ----------------------------------------------------------------- this device under a new id (review 3)

PLAYER_STATUS = "/deadwax/navidrome/status"


def player_wired(own, monkeypatch) -> None:
    """The player's shared client answered by the fake's accounts: any Subsonic call is answered ok when its login is
    the account's password now, error 40 when not - so a player call works only with a login Navidrome takes."""
    def handle(request: httpx.Request) -> httpx.Response:
        query = dict(httpx.QueryParams(request.url.query.decode()))
        own.fake.requests.append({"method": request.method, "path": request.url.path, "headers": dict(request.headers),
                                  "body": None, "query": query})
        return own.fake.get_user({**query, "username": query.get("u", "")})
    monkeypatch.setattr(navidrome_endpoint.navidrome, "client",
                        httpx.AsyncClient(transport=httpx.MockTransport(handle), base_url=f"{NAVIDROME}/rest"))
    navidrome_endpoint.forget_confirmed()


def copy_of(own, client: TestClient) -> TestClient:
    """Another browser holding a copy of `client`'s cookie - the reason someone changes their password."""
    copy = TestClient(own.app)
    copy.cookies.set(auth.COOKIE, client.cookies[auth.COOKIE])
    return copy


def cookie_attributes(header: str) -> tuple[str, list[str]]:
    """A Set-Cookie header as (its name, its attributes - everything after the value - sorted, lowercased)."""
    first, *rest = [part.strip() for part in header.split(";")]
    return first.split("=", 1)[0], sorted(part.lower() for part in rest)


def test_this_devices_session_moves_under_a_new_id_and_a_copy_of_its_old_cookie_is_signed_out(own, monkeypatch):
    """(review 3) The device the change is made from gets a NEW session id on the answer's cookie: the old cookie - and
    every copy of it - is signed out with the person's other devices, on every route, and after a restart too; the
    new one works, with the player as with /me, as the new password."""
    player_wired(own, monkeypatch)
    phone = signed_in(own, "ethan")
    copy = copy_of(own, phone)
    assert copy.get(ME).json()["user"] == "ethan" and copy.get(PLAYER_STATUS).json()["ok"] is True
    old_raw, old_key = phone.cookies[auth.COOKIE], key_of(phone)
    answer = change(own, phone, "ethan")
    #? the answer as it was, and a new cookie with it
    assert answer.status_code == 200 and answer.json() == {"changed": True, "signed_out": 0, "warning": None}
    assert auth.COOKIE in answer.cookies and answer.cookies[auth.COOKIE] != old_raw
    assert phone.cookies[auth.COOKIE] == answer.cookies[auth.COOKIE] and key_of(phone) != old_key
    #? the copy: signed out everywhere, told why - a user's route, the player, the change itself, signing out
    assert copy.get(ME).status_code == 401 and copy.get(ME).json()["detail"] == auth.PASSWORD_CHANGED
    asked = len(own.fake.requests)
    assert copy.get(PLAYER_STATUS).status_code == 401
    assert copy.get("/deadwax/me/pins").status_code == 401
    assert copy.post(CHANGE, json={"current": NEW, "password": "the-thiefs-own-pw", "password_again": "the-thiefs-own-pw"}
                     ).status_code == 401
    assert len(own.fake.requests) == asked                  # nothing asked of Navidrome as it
    #? the new cookie: /me and the player, as the new password
    assert phone.get(ME).json()["user"] == "ethan"
    assert phone.get(PLAYER_STATUS).json()["ok"] is True
    asked_as = own.fake.requests[-1]["query"]
    assert asked_as["u"] == "ethan" and asked_as["t"] == auth.subsonic_token(NEW, asked_as["s"])
    #? the old id names nothing - in the database, and in memory where it follows to the new one
    assert own.store.session(old_key) is None and own.store.session_keys("ethan") == [key_of(phone)]
    with auth._lock:
        assert old_key not in auth._held and works(auth.unseal_credential(auth._held[key_of(phone)].credential), NEW)
    #? and after a restart: the copy stays out, the device stays in
    auth.forget_sessions()
    assert copy.get(ME).status_code == 401 and copy.get(PLAYER_STATUS).status_code == 401
    replay = TestClient(own.app)
    replay.cookies.set(auth.COOKIE, old_raw)
    assert replay.get(ME).status_code == 401
    assert phone.get(ME).json()["user"] == "ethan" and phone.get(PLAYER_STATUS).json()["ok"] is True


def test_the_session_moves_whole_its_role_and_account_id_with_it(own):
    """(review 3) Everything the row carries goes with it: when it began, its expiry, when it was vouched for, the role,
    the account's id - only the id and (the change's) the login are new."""
    here = signed_in(own, "admin")
    key = key_of(here)
    with own.store._connect() as connection:
        connection.execute("UPDATE sessions SET navidrome_id = 'nd-admin-id' WHERE id_hash = ?", (key,))
    with auth._lock:
        auth._held.pop(key, None)                           # read again from the row
    assert here.get(ME).json()["admin"] is True
    before = own.store.session(key)
    started = time.time()
    assert change(own, here, "admin").status_code == 200
    after = own.store.session(key_of(here))
    assert key_of(here) != key and own.store.session(key) is None
    for column in ("user", "created_at", "last_seen", "expires_at", "admin", "navidrome_id"):
        assert after[column] == before[column], column
    assert after["checked_at"] >= started - 1 and works(auth.unseal_credential(after["credential"]), NEW)
    with auth._lock:
        held = auth._held[key_of(here)]
        assert (held.user, held.admin, held.navidrome_id) == ("admin", True, "nd-admin-id")
    assert here.get(ME).json()["admin"] is True and here.get(PEOPLE).status_code == 200
    with auth._lock:
        auth._held.pop(key_of(here), None)
    assert here.get(ME).json()["admin"] is True


@pytest.mark.parametrize("proto", [None, "https"])
def test_the_new_cookie_is_set_exactly_as_a_sign_in_sets_one(own, proto):
    """(review 3) The same name, HttpOnly, SameSite=Strict, Path=/, max-age - and Secure as a sign-in's is, from the
    request's scheme or a proxy's X-Forwarded-Proto."""
    headers = {"x-forwarded-proto": proto} if proto else {}
    later(own)
    act(own, None)
    client = TestClient(own.app)
    signing_in = client.post(LOGIN, json={"username": "ethan", "password": password(own, "ethan")}, headers=headers)
    assert signing_in.status_code == 200
    raw = signing_in.headers["set-cookie"].split(";", 1)[0].split("=", 1)[1]
    client.cookies.set(auth.COOKIE, raw)
    later(own)
    act(own, "ethan")
    answer = client.post(CHANGE, json={"current": password(own, "ethan"), "password": NEW, "password_again": NEW},
                         headers=headers)
    assert answer.status_code == 200, answer.text
    assert len(answer.headers.get_list("set-cookie")) == 1
    made, renewed = cookie_attributes(signing_in.headers["set-cookie"]), cookie_attributes(answer.headers["set-cookie"])
    assert made == renewed and made[0] == auth.COOKIE
    assert f"max-age={auth.COOKIE_MAX_AGE}" in renewed[1] and "httponly" in renewed[1] and "path=/" in renewed[1]
    assert "samesite=strict" in renewed[1] and ("secure" in renewed[1]) == (proto == "https")


def _not_kept(own, monkeypatch):
    def broken(*args):
        raise RuntimeError("database is locked")
    monkeypatch.setattr(own.store, "own_password_changed", broken)


@pytest.mark.parametrize("how, status, kind", [
    ("editing_off", 403, "editing_off"),                     # Navidrome refusing
    ("ignore_password", 502, "didnt_take"),                  # the proof failing
    ("timeout", 504, "timed_out"),
    ("wrong_current", 409, "not_your_password"),
    ("not_kept", 500, "not_kept"),                           # the database, after Navidrome's 200
])
def test_a_change_that_fails_part_way_rotates_nothing(own, monkeypatch, how, status, kind):
    """(review 3) Anything short of the change kept: no new cookie, the old id standing, nothing moved in memory."""
    phone = signed_in(own, "ethan")
    assert phone.get(ME).status_code == 200
    old_raw, old_key = phone.cookies[auth.COOKIE], key_of(phone)
    current = None
    if how == "editing_off":
        own.fake.enable_user_editing = False
    elif how == "ignore_password":
        own.fake.ignore_password = True
    elif how == "timeout":
        own.fake.timeout = {"PUT"}
    elif how == "wrong_current":
        current = "not-my-password"
    else:
        _not_kept(own, monkeypatch)
    answer = change(own, phone, "ethan", current=current)
    assert answer.status_code == status and answer.json()["kind"] == kind, answer.text
    assert "set-cookie" not in answer.headers and phone.cookies[auth.COOKIE] == old_raw
    assert own.store.session(old_key) is not None and own.store.session_keys("ethan") == [old_key]
    with auth._lock:
        assert old_key in auth._held and old_key not in auth._rotated
    assert auth.session_ended(old_key) is None and phone.get(ME).json()["user"] == "ethan"


def test_a_session_that_cant_be_moved_stands_with_the_new_login_and_says_so(own, monkeypatch):
    """(review 3) The move failing (the database) leaves the session standing under its old id - with the new login,
    never none - and the answer says a copy of it would still work."""
    player_wired(own, monkeypatch)
    phone, laptop = signed_in(own, "ethan"), signed_in(own, "ethan")
    old_raw, old_key = phone.cookies[auth.COOKIE], key_of(phone)

    def broken(*args):
        raise RuntimeError("database is locked")
    monkeypatch.setattr(own.store, "rotate_session", broken)
    answer = change(own, phone, "ethan")
    assert answer.status_code == 200
    assert answer.json() == {"changed": True, "signed_out": 1, "warning": routes.NOT_RENEWED}
    assert "set-cookie" not in answer.headers and phone.cookies[auth.COOKIE] == old_raw
    assert works(kept(own, phone), NEW) and own.store.session_keys("ethan") == [old_key]
    assert phone.get(ME).json()["user"] == "ethan" and phone.get(PLAYER_STATUS).json()["ok"] is True
    assert laptop.get(ME).json()["detail"] == auth.PASSWORD_CHANGED


def test_both_warnings_are_said_together(own, monkeypatch):
    async def unanswered(name, pw):
        return None
    monkeypatch.setattr(routes, "_signs_in_with", unanswered)

    def broken(*args):
        raise RuntimeError("database is locked")
    monkeypatch.setattr(own.store, "rotate_session", broken)
    ethan = signed_in(own, "ethan")
    assert change(own, ethan, "ethan").json()["warning"] == f"{routes.UNCHECKED} {routes.NOT_RENEWED}"


def test_a_session_signed_out_while_the_change_ran_is_not_brought_back(own, monkeypatch):
    """(review 3) Signed out from another tab between the re-seal and the move: nothing to move, no cookie set."""
    phone = signed_in(own, "ethan")
    old_raw = phone.cookies[auth.COOKIE]
    real = auth.own_password_changed

    def then_signed_out(store, key, user, sealed, now=None):
        ended = real(store, key, user, sealed, now)
        auth.sign_out(store, old_raw)
        return ended
    monkeypatch.setattr(auth, "own_password_changed", then_signed_out)
    answer = change(own, phone, "ethan")
    assert answer.status_code == 200 and "set-cookie" not in answer.headers
    assert own.store.session_keys("ethan") == [] and phone.get(ME).json()["detail"] == auth.SIGNED_OUT


# ----------------------------------------------------------------- the old login never ends this session

def test_the_recheck_during_the_change_never_ends_the_session_it_is_made_from(own, monkeypatch):
    ethan = signed_in(own, "ethan")
    real = routes._signs_in_with
    asked = {}

    async def recheck_first(name, pw):
        #? Navidrome has the new password now; the re-check asks with the session's OLD login - error 40
        asked["counts"] = await auth.check_sessions(own.store, now=time.time() + auth.RECHECK_SECONDS + 1)
        return await real(name, pw)
    monkeypatch.setattr(routes, "_signs_in_with", recheck_first)
    assert change(own, ethan, "ethan").status_code == 200
    assert asked["counts"]["ended"] == 0 and asked["counts"]["unanswered"] == 1
    assert ethan.get(ME).json()["user"] == "ethan" and works(kept(own, ethan), NEW)


def test_a_refusal_of_the_old_login_after_the_change_ends_nothing(own):
    ethan = signed_in(own, "ethan")
    old = auth.PlayerLogin(key_of(ethan), "ethan", own.store.session(key_of(ethan))["credential"], own.store)
    stale_row = own.store.session(key_of(ethan))
    assert change(own, ethan, "ethan").status_code == 200
    #? a player call made with the login read before the change - under the old id, let in just before the new
    #? cookie came (review 3) - refused after it
    assert key_of(ethan) != old.key
    assert auth.superseded(own.store, "ethan", old.key, old.sealed) is True
    assert auth.player_refused(old) is False
    assert ethan.get(ME).json()["user"] == "ethan"
    #? the session as it is now, held in memory or only in the database: a refusal of the old login is the change's
    new = auth.PlayerLogin(key_of(ethan), "ethan", old.sealed, own.store)
    assert auth.superseded(own.store, "ethan", new.key, old.sealed) is True
    auth.forget_sessions()
    #? (a restart: no request is in flight under the old id any more, and it names no session)
    assert auth.superseded(own.store, "ethan", old.key, old.sealed) is False
    assert auth.superseded(own.store, "ethan", new.key, old.sealed) is True
    assert auth.superseded(own.store, "ethan", new.key, own.store.session(new.key)["credential"]) is False
    assert stale_row["credential"] == old.sealed
    assert ethan.get(ME).json()["user"] == "ethan"


def test_a_session_row_read_before_the_reseal_never_puts_the_old_login_back(own, monkeypatch):
    """(review) The device making the change asks something just as its held copy has run out: its row is read (the
    old login), the change re-seals the session, and only then is what was read installed in memory - the newer login
    stands, so the next refusal of the old one doesn't sign out the device just told it stays signed in."""
    ethan = signed_in(own, "ethan")
    assert ethan.get(ME).status_code == 200
    key = key_of(ethan)
    new_sealed = auth.seal_credential("ethan", auth.subsonic_token(NEW, "a-salt"), "a-salt")
    with auth._lock:
        auth._held[key].loaded -= auth.CACHE_SECONDS + 1
    real = own.store.session
    armed = [True]

    def read_then_reseal(id_hash):
        row = real(id_hash)
        if armed and id_hash == key:
            armed.clear()
            auth.own_password_changed(own.store, key, "ethan", new_sealed)
        return row
    monkeypatch.setattr(own.store, "session", read_then_reseal)
    assert ethan.get(ME).json()["user"] == "ethan" and not armed
    with auth._lock:
        assert auth._held[key].credential == new_sealed


def test_a_device_whose_change_waited_on_another_is_told_its_password_was_changed(own, monkeypatch):
    """(review) Both devices press Save: the desktop's waits while the phone's goes through and ends it - it is told
    why, as its next /me would be, never a bare "signed out"."""
    phone, desktop = signed_in(own, "ethan"), signed_in(own, "ethan")
    assert desktop.get(ME).status_code == 200                # held: its request reads no row before the route
    new_sealed = auth.seal_credential("ethan", auth.subsonic_token(NEW, "a-salt"), "a-salt")
    real = own.store.session
    armed = [True]

    def phone_first(id_hash):
        if armed and id_hash == key_of(desktop):
            armed.clear()
            auth.own_password_changed(own.store, key_of(phone), "ethan", new_sealed)
        return real(id_hash)
    monkeypatch.setattr(own.store, "session", phone_first)
    answer = change(own, desktop, "ethan")
    assert not armed and answer.status_code == 401 and answer.json()["detail"] == auth.PASSWORD_CHANGED


def test_a_refusal_in_flight_after_the_change_keeps_the_other_devices_reason(own, monkeypatch):
    """(review) A player call - or the re-check - of another device, made with its old login before the change and
    refused after it, never turns PASSWORD_CHANGED into LOGIN_GONE."""
    phone, desktop, tablet = signed_in(own, "ethan"), signed_in(own, "ethan"), signed_in(own, "ethan")
    desktop_row = own.store.session(key_of(desktop))
    tablet_row = own.store.session(key_of(tablet))
    assert change(own, phone, "ethan").status_code == 200
    stale = auth.PlayerLogin(key_of(desktop), "ethan", desktop_row["credential"], own.store)
    auth.player_refused(stale)
    assert auth.session_ended(key_of(desktop)) == auth.PASSWORD_CHANGED
    assert desktop.get(ME).json()["detail"] == auth.PASSWORD_CHANGED
    #? the re-check, holding the tablet's row as it read it before the change
    monkeypatch.setattr(own.store, "sessions_due", lambda before, now: [tablet_row])
    later(own)
    counts = run(auth.check_sessions(own.store))
    assert counts["ended"] == 1 and auth.session_ended(key_of(tablet)) == auth.PASSWORD_CHANGED
    assert phone.get(ME).json()["user"] == "ethan"


def test_a_device_refused_while_the_change_runs_is_told_why_and_counted(own, monkeypatch):
    """(review 2) Navidrome has taken the new password, and before the phone's change re-seals it, the desktop's next
    player call and the re-check of the tablet carry their OLD logins and are refused: both are the change's doing -
    told PASSWORD_CHANGED, never LOGIN_GONE, and counted in "Signed out of your other 2 devices"."""
    phone, desktop, tablet = signed_in(own, "ethan"), signed_in(own, "ethan"), signed_in(own, "ethan")
    assert desktop.get(ME).status_code == 200 and tablet.get(ME).status_code == 200
    desktop_login = auth.PlayerLogin(key_of(desktop), "ethan", own.store.session(key_of(desktop))["credential"], own.store)
    tablet_row = own.store.session(key_of(tablet))
    real = routes._signs_in_with
    seen = {}

    async def others_refused_first(name, pw):
        seen["desktop"] = await asyncio.to_thread(auth.player_refused, desktop_login)
        monkeypatch.setattr(own.store, "sessions_due", lambda before, now: [tablet_row])
        seen["counts"] = await auth.check_sessions(own.store, now=time.time() + auth.RECHECK_SECONDS + 1)
        return await real(name, pw)
    monkeypatch.setattr(routes, "_signs_in_with", others_refused_first)
    answer = change(own, phone, "ethan")
    assert answer.status_code == 200 and answer.json()["signed_out"] == 2, answer.text
    assert seen["desktop"] is True and seen["counts"]["ended"] == 1
    assert desktop.get(ME).json()["detail"] == auth.PASSWORD_CHANGED
    assert tablet.get(ME).json()["detail"] == auth.PASSWORD_CHANGED
    assert phone.get(ME).json()["user"] == "ethan" and own.store.session_keys("ethan") == [key_of(phone)]


def test_a_device_refused_during_a_change_that_didnt_take_is_told_login_gone(own, monkeypatch):
    """(review 2) The same refusal, and then the change doesn't take (Navidrome ignored the password): the desktop's
    login died of something else, so the reason it is told is LOGIN_GONE again once the change is over."""
    phone, desktop = signed_in(own, "ethan"), signed_in(own, "ethan")
    desktop_login = auth.PlayerLogin(key_of(desktop), "ethan", own.store.session(key_of(desktop))["credential"], own.store)
    own.fake.ignore_password = True
    real = routes._signs_in_with

    async def desktop_refused_first(name, pw):
        await asyncio.to_thread(auth.player_refused, desktop_login)
        assert auth.session_ended(desktop_login.key) == auth.PASSWORD_CHANGED
        return await real(name, pw)
    monkeypatch.setattr(routes, "_signs_in_with", desktop_refused_first)
    answer = change(own, phone, "ethan")
    assert answer.status_code == 502 and answer.json()["detail"] == routes.DIDNT_TAKE
    assert desktop.get(ME).json()["detail"] == auth.LOGIN_GONE
    assert phone.get(ME).json()["user"] == "ethan"


def test_the_current_password_is_checked_against_the_login_the_database_holds_now(own, monkeypatch):
    """(review 2) Two tabs share one session: tab 2's Save was read with the OLD login, and tab 1's change re-sealed the
    session (and Navidrome took the new password) before tab 2's reached the check. The old password typed into tab 2 is
    checked against the login the database holds NOW - refused here, with nothing sent - never against the request's
    copy, which would send it to Navidrome, be refused there and sign out a session that stands."""
    ethan = signed_in(own, "ethan")
    assert ethan.get(ME).status_code == 200                  # held: the request's login is read before the route
    key = key_of(ethan)
    old = password(own, "ethan")
    new_sealed = auth.seal_credential("ethan", auth.subsonic_token(NEW, "a-salt"), "a-salt")
    real = own.store.session
    armed = [True]

    def tab_one_first(id_hash):
        if armed and id_hash == key:
            armed.clear()
            own.fake.set_password("ethan", NEW)
            auth.own_password_changed(own.store, key, "ethan", new_sealed)
        return real(id_hash)
    later(own)
    act(own, "ethan")
    asked = len(own.fake.native())
    monkeypatch.setattr(own.store, "session", tab_one_first)
    answer = ethan.post(CHANGE, json={"current": old, "password": "another-new-one", "password_again": "another-new-one"})
    assert not armed
    assert answer.status_code == 409 and answer.json()["kind"] == "not_your_password", answer.text
    assert len(own.fake.native()) == asked
    monkeypatch.setattr(own.store, "session", real)
    assert auth.session_ended(key) is None and own.store.session(key)["credential"] == new_sealed


def test_changing_password_is_held_only_while_the_change_runs_and_only_for_its_session():
    with auth.changing_password("k", "maya"):
        with auth.changing_password("k", "maya"):
            assert auth.superseded(None, "maya", "k", "s") is True
        assert auth.superseded(None, "maya", "k", "s") is True
        #? (review) the person's other sessions: never - each ends at its first refusal, as ever
        assert auth.superseded(None, "maya", "another-session", "s") is False
        #? (review 2) told it is the change's doing - only a refusal of the login, never another DEADWAX_SECRET_KEY
        assert auth._refusal("maya", "another-session", auth.LOGIN_GONE) == (True, auth.PASSWORD_CHANGED)
        assert auth._refusal("maya", "another-session", auth.KEY_CHANGED) == (True, auth.KEY_CHANGED)
        assert auth._refusal("james", "james-session", auth.LOGIN_GONE) == (True, auth.LOGIN_GONE)
    assert auth.superseded(None, "maya", "k", "s") is False
    with pytest.raises(RuntimeError):
        with auth.changing_password("k", "maya"):
            raise RuntimeError("the change failed")
    assert auth.superseded(None, "maya", "k", "s") is False


def test_the_fake_keeps_a_non_admins_name_and_flag_and_refreshes_their_jwt_with_the_new_epoch(own):
    """(review) The fake's own rules for a PUT of your own record, as Navidrome 0.64.2's Update and
    user_password_token_refresh_test.go have them - held, so the fake can't drift from them unnoticed."""
    later(own)
    act(own, "ethan")
    held = run(navidrome_admin.login("ethan", password(own, "ethan"), expect="ethan"))
    record = run(navidrome_admin.get_user(held, held.navidrome_id))
    run(navidrome_admin.save_user(held, held.navidrome_id, {**record, "isAdmin": True, "userName": "ethan-the-admin"}))
    stored = own.fake.by_name("ethan")
    assert stored is not None and stored["isAdmin"] is False and own.fake.by_name("ethan-the-admin") is None
    before = held.jwt
    old = password(own, "ethan")
    run(navidrome_admin.save_user(held, held.navidrome_id, {**record, "password": NEW, "currentPassword": old}))
    account_id = own.fake.id_of("ethan")
    assert held.jwt != before and own.fake.tokens[held.jwt]["epoch"] == own.fake.epochs[account_id] == 1
    #? the JWT refreshed by that same PUT's start, before the password changed: one of its line's newest two, so only
    #? its old epoch refuses it
    line = own.fake.tokens[held.jwt]["line"]
    older = own.fake.issued[line][-2]
    assert own.fake.tokens[older]["epoch"] == 0
    stale = navidrome_admin.Unlock(None, "ethan", account_id, False, older, held.base, held.last_used)
    with pytest.raises(navidrome_admin.NativeError) as refused:
        run(navidrome_admin.get_user(stale, account_id))
    assert refused.value.kind == "locked"
    assert run(navidrome_admin.get_user(held, held.navidrome_id))["userName"] == "ethan"


# ----------------------------------------------------------------- never a password anywhere

def test_no_password_reaches_a_log_line_an_answer_or_a_422(own, caplog):
    caplog.set_level(logging.DEBUG)
    ethan = signed_in(own, "ethan")
    answers = [change(own, ethan, "ethan", current="a-wrong-guess-pw"),
               ethan.post(CHANGE, json={"current": "x", "password": "sekret-in-a-422", "password_again": "y", "bogus": 1}),
               ethan.post(CHANGE, json={"current": ["sekret-in-a-list"], "password": NEW, "password_again": NEW})]
    own.fake.enable_user_editing = False
    answers.append(change(own, ethan, "ethan"))
    own.fake.enable_user_editing = True
    answers.append(change(own, ethan, "ethan"))
    assert answers[-1].status_code == 200
    assert answers[1].status_code == 422 and answers[1].json() == {"detail": routes.FORM}
    assert answers[2].status_code == 422 and answers[2].json() == {"detail": routes.FORM}
    seen = caplog.text + "".join(answer.text + json.dumps(dict(answer.headers)) for answer in answers)
    for secret in ("ethan-navidrome-pw", "a-wrong-guess-pw", NEW, "sekret-in-a-422", "sekret-in-a-list",
                   "0123456789abcdef0123456789abcdef", *own.fake.tokens):
        assert secret not in seen, secret


def test_the_route_asks_through_three_of_peoples_six_calls_and_no_other():
    import ast
    source = (Path(__file__).resolve().parent.parent / "src/routes/own_password.py").read_text()
    used = {node.attr for node in ast.walk(ast.parse(source)) if isinstance(node, ast.Attribute)
            and isinstance(node.value, ast.Name) and node.value.id == "navidrome_admin"}
    assert used == {"login", "get_user", "save_user", "forget_user", "NativeError", "WORDS"}
    #? never the Subsonic changePassword (Navidrome 0.64 answers it 501), never a path or an httpx of its own
    tree = ast.parse(source)
    tree.body = tree.body[1:]                              # the docstring, which names what it doesn't use
    code = ast.unparse(tree)
    assert "changePassword" not in code and "/api/" not in code and "/auth/" not in code and "httpx" not in code
