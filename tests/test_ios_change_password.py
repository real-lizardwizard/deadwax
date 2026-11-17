"""
The iPhone app's Change password (Phase 8, slice 10 - notes/ios-specs/phase8-managing.md 9; notes/ios.md "Change
password on the phone") against the route it asks - `POST /deadwax/me/password` (src/routes/own_password.py) - read
from its own source (ios/DeadwaxKit/Sources/DeadwaxCore: OwnPassword.swift, APIFailure.swift, SessionCookie.swift,
Routes.swift; ios/App: You/ChangePasswordScreen.swift, You/AccountSection.swift, Models/ServerModel.swift,
Downloads/, Shared/Routes.swift) and held to the server's.

- what it SENDS - the body the strict model takes, key for key (an extra one is the route's 422), posted for real;
- what it READS - the answer's fields, the new session's cookie by SessionCookie's rule (and that cookie IS the session
  after, the old one refused), a refusal's detail, kind and fix;
- how long it waits - worked out from the server's own waits, with room;
- who may - a user's route (tests/test_logins.py ROUTES), offered by the rule the web's is;
- what the app does with it - the cookie kept in the Keychain before the new client is made, a 401 held while the
  change is out, a background download's 401 told by the session it went out under, never a password logged or kept,
  the fields emptied, the page's words in the palette's faces.
"""

import inspect
import re
import sys
from pathlib import Path

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import auth  # noqa: E402
from src.api import navidrome_admin  # noqa: E402
from src.routes import own_password as routes  # noqa: E402
from src.routes.people import answer as refusal_answer, Refused  # noqa: E402
from src.store import JobStore  # noqa: E402
from tests import test_own_password, test_people  # noqa: E402
from tests.test_ios_contract import (CORE, _block, _code, coding_keys, fields, sent_fields, swift_function,  # noqa: E402
                                     swift_struct)
from tests.test_ios_needs_look import app_file, swift_like, timeouts  # noqa: E402
from tests.test_logins import ROUTES  # noqa: E402
from tests.test_people import ME, password, signed_in  # noqa: E402

#? the change's fixtures - People's app, store and fake Navidrome, and the change's own clock - bound by assignment
nd = test_people.nd
own = test_own_password.own

OWN = (CORE / "OwnPassword.swift").read_text(encoding="utf-8")
CHANGE = "/deadwax/me/password"
NEW = "a-fresh-phone-password"


def swift_words(name: str) -> str:
    """A `public static let <name> = "..."` of OwnPassword.swift, its `+`-joined pieces joined."""
    found = re.search(r"public static let " + name + r' = ((?:"[^"\n]*"\s*(?:\+\s*)?)+)', OWN)
    assert found, f"no {name}"
    return "".join(re.findall(r'"([^"\n]*)"', found.group(1)))


def own_function(signature: str) -> str:
    """The body of the one `func <signature>...` in OwnPassword.swift - for a name declared twice (`outcome(of:)` for an
    answer and for an error, the flow's and the re-key's `ended`), told apart by how its signature starts."""
    code = _code(OWN)
    found = list(re.finditer(r"\bfunc\s+" + re.escape(signature) + r"[^{]*\{", code))
    assert len(found) == 1, f"func {signature} is declared {len(found)} times"
    return _block(code, found[0].end() - 1)


def phone_body(current: str, new: str, again: str) -> dict:
    """The body as OwnPasswordBody encodes it: each property under its CodingKeys name."""
    keys = coding_keys(swift_struct("OwnPasswordBody"))
    values = {"current": current, "password": new, "passwordAgain": again}
    return {keys[name]: values[name] for name in keys}


def session_of(header: str) -> str | None:
    """SessionCookie.value(fromSetCookie:)'s rule: after the name and `=`, up to `;` or `,`."""
    found = re.search(r"(?:^|[,;]\s*)" + re.escape(auth.COOKIE) + r"=([^;,]*)", header or "")
    return found.group(1).strip() or None if found else None


# ---------------------------------------------------------------------------- the route, and who may

def test_the_route_is_the_servers_by_method_path_and_permission():
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    line = f'public static let ownPassword = Endpoint(method: "POST", path: "{CHANGE}", query: [])'
    assert line in text
    assert ROUTES[("POST", CHANGE)] == "user"
    # in the list the client's routes are checked from
    listed = re.search(r"public static let all: \[Endpoint\] = \[(.*?)\]", text, re.S).group(1)
    assert re.search(r"\bownPassword\b", listed)
    # offered as the web offers it: OwnPassword's rule, and Manage's old name for it only hands on to it
    offered = swift_function("OwnPassword.swift", "changeOffered")
    assert 'me.auth == "on"' in offered and "Access.breakGlassUser.utf16" in offered
    assert "OwnPassword.changeOffered(me)" in swift_function("Managing.swift", "changeOffered")


# ---------------------------------------------------------------------------- what it sends

def test_the_body_is_the_strict_models_key_for_key():
    assert sent_fields("OwnPasswordBody") == set(routes.OwnPasswordBody.model_fields)
    assert routes.OwnPasswordBody.model_config.get("extra") == "forbid"
    # every property is sent, none kept back: three lets, three keys
    assert set(fields("OwnPasswordBody")) == set(routes.OwnPasswordBody.model_fields)


def test_the_phones_body_changes_it_and_its_cookie_is_the_session_after(own):
    ethan = signed_in(own, "ethan")
    old = ethan.cookies[auth.COOKIE]
    test_people.later(own)
    test_people.act(own, "ethan")
    answer = ethan.post(CHANGE, json=phone_body(password(own, "ethan"), NEW, NEW))
    assert answer.status_code == 200, answer.text
    # what OwnPasswordAnswer reads is all there, under the names it reads
    assert set(fields("OwnPasswordAnswer")) <= set(answer.json()), answer.json()
    assert answer.json()["changed"] is True and answer.json()["signed_out"] == 0
    # the new session, read as the phone reads it - and it IS the session now; the old cookie is refused
    new = session_of(answer.headers.get("set-cookie"))
    assert new and new != old
    fresh = TestClient(own.app)
    fresh.cookies.set(auth.COOKIE, new)
    assert fresh.get(ME).json()["user"] == "ethan"
    stale = TestClient(own.app)
    stale.cookies.set(auth.COOKIE, old)
    refused = stale.get(ME)
    assert refused.status_code == 401 and refused.json()["detail"] == auth.PASSWORD_CHANGED


def test_an_extra_field_is_the_routes_422_with_nothing_echoed(own):
    ethan = signed_in(own, "ethan")
    body = phone_body(password(own, "ethan"), NEW, NEW) | {"show": True}
    answer = ethan.post(CHANGE, json=body)
    assert answer.status_code == 422 and answer.json() == {"detail": routes.FORM}
    assert NEW not in answer.text


# ---------------------------------------------------------------------------- what it reads

def test_a_refusal_is_read_with_its_kind_and_fix(own):
    ethan = signed_in(own, "ethan")
    test_people.later(own)
    test_people.act(own, "ethan")
    same = password(own, "ethan")
    answer = ethan.post(CHANGE, json=phone_body(same, same, same))
    assert answer.status_code == 400 and answer.json()["detail"] == routes.SAME_PASSWORD
    assert set(answer.json()) == {"detail", "kind", "fix"}
    assert refusal_answer(Refused(400, "x", "k", "f")) == {"detail": "x", "kind": "k", "fix": "f"}
    # a wrong current password: its kind is the one the page empties and focuses Current for
    wrong = ethan.post(CHANGE, json=phone_body("not-the-one-at-all", NEW, NEW))
    assert wrong.status_code == 409 and wrong.json()["kind"] == "not_your_password"
    assert f'public static let notYourPassword = "{wrong.json()["kind"]}"' in OWN
    # ErrorBody reads all three, as strings
    failure = _code((CORE / "APIFailure.swift").read_text(encoding="utf-8"))
    assert "case detail, why, kind, fix, busy" in failure
    assert "fix = (try? body.decodeIfPresent(String.self, forKey: .fix)) ?? nil" in failure
    # and Navidrome's own fix words are the ones a refusal may carry
    assert all(isinstance(words, str) and words for words in navidrome_admin.FIXES.values())


def test_the_phones_words_are_the_servers_where_both_say_them():
    assert swift_words("samePassword") == routes.SAME_PASSWORD


def test_the_answer_with_no_cookie_is_read_as_not_renewed_never_as_rekeyed():
    outcome = own_function("outcome(of response: HTTPResponse)")
    assert 'SessionCookie.value(fromSetCookie: response.header("Set-Cookie"))' in outcome
    assert "guard answer.changed else { return .unknown(words: unknownLine) }" in outcome
    assert "return .notRenewed(" in outcome
    # the server's two ways of answering 200: with the cookie, and NOT_RENEWED's without it
    source = inspect.getsource(routes.change_own_password)
    assert "if raw is not None:" in source and "_set_cookie(response, request, raw" in source
    assert "NOT_RENEWED, not renewed" in source


# ---------------------------------------------------------------------------- how long it waits

def test_the_wait_is_the_servers_worst_case_with_room():
    login, native, write = 10.0, navidrome_admin.TIMEOUT_SECONDS, navidrome_admin.WRITE_TIMEOUT_SECONDS
    busy = 10.0
    # each httpx.Timeout(x) is x for the connection and x for the read: the login, the record read, the PUT, the proof
    navidrome = 2 * native + 2 * native + 2 * write + 2 * login
    # the session read, and three store calls in the handler, each may wait out SQLite's busy timeout; a sign-in
    # holding the throttle's lock asks Navidrome's getUser once
    worst = navidrome + 4 * busy + 2 * login
    assert worst == 180
    assert timeouts()["ownPassword"] == 240 > worst
    # the numbers it is worked out from are the server's
    assert "timeout=httpx.Timeout(10.0)" in inspect.getsource(auth)
    assert "timeout=10" in inspect.getsource(JobStore)


# ---------------------------------------------------------------------------- what the app does with it

def test_the_new_session_is_kept_before_it_is_used_and_a_401_is_held_while_out():
    server = _code(app_file("Models", "ServerModel.swift"))
    change = swift_like(server, "changeOwnPassword")
    assert "rekey.began()" in change and "BackgroundHold(named:" in change
    order = [change.index(step) for step in ("SessionKeychain.save(cookie, for: address.key)", "session = cookie",
                                             "self.client = makeClient(address, session: cookie)",
                                             "rekey.ended(outcome, rekeyed: rekeyed)")]
    assert order == sorted(order)
    # nothing asked again by itself: one call to the client
    assert change.count("client.changeOwnPassword(") == 1
    # every 401 that would end the session goes through the hold
    ended = swift_like(server, "sessionEnded")
    assert "if rekey.holds(reason: reason) { return }" in ended
    assert server.count("sessionEnded(reason:") == 4
    # Core's hold: what each outcome leaves
    after = own_function("ended(_ outcome: OwnPassword.Outcome, rekeyed: Bool)")
    assert "if rekeyed { return .nothing }" in after


def test_a_downloads_401_is_told_by_the_session_it_went_out_under():
    session = _code(app_file("Downloads", "DownloadSession.swift"))
    assert "sentUnder: String??" in session
    assert 'SessionCookie.value(fromCookie: $0.value(forHTTPHeaderField: "Cookie"))' in session
    model = _code(app_file("Downloads", "DownloadModel.swift"))
    assert "if current { signedOutHeard(sentUnder: sentUnder) }" in model
    heard = swift_like(model, "signedOutHeard")
    early = heard.index("if let sentUnder, sentUnder != session {")
    assert early < heard.index("refusedSession = .some(session)")
    # the request carries the cookie the way SessionCookie reads it back
    cookie = swift_function("SessionCookie.swift", "header")
    assert '"\\(name)=\\(value)"' in cookie


def test_no_password_is_logged_kept_or_put_in_an_address():
    screen = _code(app_file("You", "ChangePasswordScreen.swift"))
    server = _code(swift_like(app_file("Models", "ServerModel.swift"), "changeOwnPassword"))
    for code in (screen, server):
        for leak in ("print(", "Logger", "os_log", "NSLog", "note(", "UserDefaults", "AppStorage", "URLQueryItem"):
            assert leak not in code, leak
    # the form and the body say nothing of what they hold, however they are printed
    for struct in ("OwnPasswordForm", "OwnPasswordBody"):
        body = swift_struct(struct)
        assert f'public var description: String {{ "{struct}(redacted)" }}' in body
        assert "public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }" in body
    # the fields live in the page's state alone, emptied as it goes and as the sign-in comes over the app
    assert "@State private var flow = OwnPasswordFlow()" in screen
    forget = swift_like(screen, "forget")
    assert "flow.hidden()" in forget
    assert ".onDisappear {\n            forget()" in screen
    assert "if over { forget() }" in screen


def test_the_page_draws_as_the_spec_says():
    screen = _code(app_file("You", "ChangePasswordScreen.swift"))
    for field, kind in (("currentLabel", ".password"), ("newLabel", ".newPassword"), ("againLabel", ".newPassword")):
        found = re.search(r"SecureField\(OwnPassword\." + field + r", text: [^)]*\)\)\s*\.textContentType\(([.\w]+)\)",
                          screen)
        assert found and found.group(1) == kind, field
    assert screen.count(".textInputAutocapitalization(.never)") == 3 and screen.count(".autocorrectionDisabled()") == 3
    assert ".navigationTitle(OwnPassword.title)" in screen
    assert ".navigationBarBackButtonHidden(flow.changing)" in screen
    assert ".editOutOfReach(!reachability.online)" in screen
    assert "navigation.passwordChanging(changing)" in screen
    assert "flow.canChange(user: user, online: reachability.online) && server.signInOver == nil" in screen
    assert "OwnPassword.httpNote(at: server.address)" in screen and "Text(OwnPassword.appsLine)" in screen
    # the ticket taken in the tap, before the Task
    change = swift_like(screen, "change")
    assert change.index("flow.begin(user: user, online: reachability.online)") < change.index("Task {")
    assert "Notice.announce(words)" in change
    # Account's row pushes it, offered by the web's rule
    account = _code(app_file("You", "AccountSection.swift"))
    assert "if OwnPassword.changeOffered(server.me) {" in account
    assert "NavigationLink(value: AppRoute.changePassword)" in account and "WebAppRow" not in account
    navigation = _code(app_file("Shared", "Routes.swift"))
    assert "case .changePassword: ChangePasswordScreen()" in navigation
    assert "OwnPassword.pagesKept(password, changing: changingPassword)" in navigation
