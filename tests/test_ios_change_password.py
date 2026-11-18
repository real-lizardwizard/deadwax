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
  the fields emptied, the page's words in the palette's faces;
- (after review) where it goes: a redirect followed only within the address asked, by every session the app makes.
"""

import inspect
import re
import sys
import unicodedata
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
from tests.test_ios_needs_look import APP, app_file, swift_like, timeouts  # noqa: E402
from tests.test_logins import ROUTES  # noqa: E402
from tests.test_people import ME, password, signed_in  # noqa: E402

#? the change's fixtures - People's app, store and fake Navidrome, and the change's own clock - bound by assignment
nd = test_people.nd
own = test_own_password.own

OWN = (CORE / "OwnPassword.swift").read_text(encoding="utf-8")
CHANGE = "/deadwax/me/password"
NEW = "a-fresh-phone-password"


def swift_words(name: str) -> str:
    """A `public static let <name> = "..."` of OwnPassword.swift, its `+`-joined pieces joined - or (the Mac app,
    slice 4) the words a `public static func <name>(_ device: Device) -> String` returns, its interpolations as written."""
    found = re.search(r"public static (?:let " + name + r" = |func " + name + r"\(_ device: Device\) -> String \{\s*)"
                      + r'((?:"[^"\n]*"\s*(?:\+\s*)?)+)', OWN)
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


def _swift_trimmed(text: str) -> str:
    """`String.trimmingCharacters(in: .whitespaces)`: Unicode's space separators (Zs) and the tab, off both ends."""
    def blank(character: str) -> bool:
        return character == "\t" or unicodedata.category(character) == "Zs"
    start, end = 0, len(text)
    while start < end and blank(text[start]):
        start += 1
    while end > start and blank(text[end - 1]):
        end -= 1
    return text[start:end]


def session_of(header: str | None) -> str | None:
    """SessionCookie.value(fromSetCookie:), step for step: each `<name>=` in turn, taken where it starts the header
    (only spaces before it) or follows a `,`, a space or a `;`; its value up to the next `;` or `,`, trimmed, one pair of
    surrounding quotes taken off; nil when empty (a sign-out's clearing) or when there is none."""
    if header is None:
        return None
    needle = auth.COOKIE + "="
    rest = header
    while (at := rest.find(needle)) >= 0:
        before, after = rest[:at], rest[at + len(needle):]
        if all(c == " " for c in before) or before[-1] in (",", " ", ";"):
            value = _swift_trimmed(re.split(r"[;,]", after, maxsplit=1)[0])
            if len(value) >= 2 and value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            return value or None
        rest = after
    return None


def test_the_cookie_is_read_as_session_cookie_reads_it():
    code = _code((CORE / "SessionCookie.swift").read_text(encoding="utf-8"))
    found = list(re.finditer(r"\bfunc value\(fromSetCookie[^{]*\{", code))
    assert len(found) == 1
    rule = _block(code, found[0].end() - 1)
    # the Swift this follows, step by step
    for part in ('rest.range(of: name + "=")', 'before.allSatisfy({ $0 == " " }) || before.last == ","',
                 'after.prefix(while: { $0 != ";" && $0 != "," })', ".trimmingCharacters(in: .whitespaces)",
                 'value.hasPrefix("\\""), value.hasSuffix("\\""), value.count >= 2', "return value.isEmpty ? nil : value"):
        assert part in rule, part
    name = auth.COOKIE
    cases = [
        (f"{name}=s.a; HttpOnly; Path=/", "s.a"),
        (f'{name}="s.q"; Path=/', "s.q"),
        (f"other=1; Path=/, {name}=s.b; HttpOnly", "s.b"),
        (f"x{name}=no; {name}=s.c", "s.c"),
        (f"  {name}= s.d ;", "s.d"),
        (f"{name}=; Max-Age=0", None),
        (f'{name}=""; Max-Age=0', None),
        (f'{name}="', '"'),
        ("other=1", None),
        (None, None),
    ]
    for header, value in cases:
        assert session_of(header) == value, header


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
    assert "rekey.began(under: session)" in change and "BackgroundHold(named:" in change
    order = [change.index(step) for step in ("changingPassword = true", "let sent = changeContext",
                                             "await client.changeOwnPassword(body",
                                             "guard PasswordRekey.answerStands(sent: sent, now: changeContext) else {",
                                             "SessionStore.save(cookie, for: address.key)", "session = cookie",
                                             "self.client = makeClient(address, session: cookie)",
                                             "let then = rekey.ended(outcome, device: Platform.device)", "changingPassword = false")]
    assert order == sorted(order)
    # the cookie kept, in hand and in the client in one turn: nothing awaited between, so nothing asks under the old one
    kept = change[change.index("SessionStore.save(cookie"):change.index("self.client = makeClient(address")]
    assert "await" not in kept
    # an answer whose person, address or session has moved on is dropped, and the hold with it
    assert "dropChange()\n            return .cancelled" in change
    assert ("PasswordRekey.Context(person: person, address: address?.key, session: session, ready: launch == .ready)"
            in server)
    # nothing asked again by itself: one call to the client
    assert change.count("client.changeOwnPassword(") == 1
    # every 401 that would end the session goes through the hold - held only under the session it began under
    ended = swift_like(server, "sessionEnded")
    assert "if rekey.holds(reason: reason, session: session) { return }" in ended
    assert server.count("sessionEnded(reason:") == 4
    # and the sign-in is brought from two places only: a 401 not held, and the change's end
    assert len(re.findall(r"(?<!func )\bbringSignIn\(", server)) == 2
    assert "bringSignIn(reason: reason)" in ended and "bringSignIn(reason: reason)" in change
    # a sign-out, another address, another person: the hold let go with them
    assert len(re.findall(r"(?<!func )\bdropChange\(\)", server)) == 4
    assert "dropChange()" in swift_like(server, "personChanged")
    drop = swift_like(server, "dropChange")
    assert "rekey.forgot()" in drop and "changingPassword = false" in drop
    # Core's hold: what each outcome leaves
    after = own_function("ended(_ outcome: OwnPassword.Outcome, device: Device)")
    assert "defer { forgot() }" in after
    assert re.search(r"case \.changed:\s*return \.nothing", after)
    assert ("case .notRenewed, .failed, .unknown, .cancelled:\n"
            "            return heard ? .signIn(reason: OwnPassword.endedWhileChanging(device)) : .askMe") in after
    holds = own_function("holds(reason said: String?, session: String?)")
    assert "guard out, under == .some(session) else { return false }" in holds
    assert "now.ready && sent == now" in own_function("answerStands(sent: Context, now: Context)")
    # the words the sign-in says when a held 401 is brought: the phone's, never PASSWORD_CHANGED's "another device"
    assert "another device" not in swift_words("endedWhileChanging")
    assert "another device" in auth.PASSWORD_CHANGED


def test_a_downloads_401_is_told_by_the_session_it_went_out_under():
    session = _code(app_file("Downloads", "DownloadSession.swift"))
    assert "sentUnder: String??" in session
    assert 'SessionCookie.value(fromCookie: $0.value(forHTTPHeaderField: "Cookie"))' in session
    model = _code(app_file("Downloads", "DownloadModel.swift"))
    assert "if current { signedOutHeard(sentUnder: sentUnder, song: record.id) }" in model
    heard = swift_like(model, "signedOutHeard")
    assert ("switch DownloadRules.heard401(sentUnder: sentUnder, current: session, changing: server.changingPassword)"
            in heard)
    assert "heldForChange.insert(song)" in heard and "refuseSession(session)" in heard
    assert "refusedSession = .some(session)" in swift_like(model, "refuseSession")
    # a 401 while a change is out holds its own song back, not every download; the change's end decides it
    assert "&& !(server.changingPassword && heldForChange.contains($0.id))" in model
    changed = swift_like(model, "serverChanged")
    assert "DownloadRules.afterChange(deferred: deferred, current: server.client?.session)" in changed
    assert "_ = server.changingPassword" in swift_like(model, "watchServer")
    # Core's rule
    rule = swift_function("DownloadRules.swift", "heard401")
    assert "if under != .some(current) { return .replaced }" in rule
    assert "return changing ? .deferred : .refused" in rule
    # and Resume's: a save's 401 stops saving only under the session it was sent under
    resume = _code((CORE / "ResumeController.swift").read_text(encoding="utf-8"))
    assert "if let held = Resume.heldAfter401(sentUnder: under, now: session()) {" in resume
    assert "sentUnder == now ? now : nil" in swift_function("Resume.swift", "heldAfter401")
    # the request carries the cookie the way SessionCookie reads it back
    cookie = swift_function("SessionCookie.swift", "header")
    assert '"\\(name)=\\(value)"' in cookie


def test_no_password_is_logged_kept_or_put_in_an_address():
    screen = _code(app_file("You", "ChangePasswordScreen.swift"))
    server = _code(swift_like(app_file("Models", "ServerModel.swift"), "changeOwnPassword"))
    # the page, the change, Core's rules for it, the client that sends it and the transport under that
    wider = [_code((CORE / name).read_text(encoding="utf-8")) for name in ("OwnPassword.swift", "DeadwaxClient.swift")]
    transport = _code(app_file("URLSessionTransport.swift"))
    for code in (screen, server, *wider, transport):
        for leak in ("print(", "Logger", "os_log", "NSLog", "note(", "UserDefaults", "AppStorage", "dump("):
            assert leak not in code, leak
    # nothing in an address: the page and OwnPassword make none, and the client's are the route's query alone - which
    # for this route is none
    for code in (screen, server, wider[0]):
        assert "URLQueryItem" not in code
    assert "parts.queryItems = sent.map { URLQueryItem(name: $0.0, value: $0.1) }" in wider[1]
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
    # and as Now Playing comes over the page
    assert ".onChange(of: navigation.nowPlayingShown) { _, shown in\n" in screen and "if shown { forget() }" in screen


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
    # on only by Core's rule, the sign-in over the app among it
    assert "flow.canChange(user: user, online: reachability.online, signInOver: server.signInOver != nil)" in screen
    assert "!changing && online && !signInOver && OwnPassword.formReady(form, user: user)" in own_function(
        "canChange(user: String, online: Bool, signInOver: Bool)")
    assert "OwnPassword.httpNote(at: server.address)" in screen and "Text(OwnPassword.appsLine)" in screen
    # the ticket taken in the tap, before the Task
    change = swift_like(screen, "change")
    assert change.index("flow.begin(user: user, online: reachability.online,") < change.index("Task {")
    assert "Notice.announce(words)" in change
    # nothing announced under the sign-in: it says what happened
    assert "let words = flow.ended(ticket, outcome, signInOver: server.signInOver != nil, device: Platform.device)" in change
    assert "return signInOver ? nil : said?.announcement" in own_function("ended(_ ticket: Int")
    # Account's row pushes it, offered by the web's rule
    account = _code(app_file("You", "AccountSection.swift"))
    assert "if OwnPassword.changeOffered(server.me) {" in account
    assert "NavigationLink(value: AppRoute.changePassword)" in account and "WebAppRow" not in account
    navigation = _code(app_file("Shared", "Routes.swift"))
    assert "case .changePassword: ChangePasswordScreen()" in navigation
    assert "OwnPassword.pagesKept(password, changing: changingPassword)" in navigation


# ---------------------------------------------------------------------------- where it goes (after review)

FOLLOWS = "Redirects.follows(from: task.originalRequest?.url, to: request.url) ? request : nil"


def test_every_session_the_app_makes_follows_a_redirect_only_within_the_address_asked():
    """A request carries deadwax's session as `Cookie:`, a sign-in or Change password a password: a 307 or 308 to
    another scheme, host or port would take them there. Every URLSession the app makes is found, and each says so."""
    sources = CORE.parent
    made = {}
    for path in sorted([*APP.rglob("*.swift"), *sources.rglob("*.swift")]):
        code = _code(path.read_text(encoding="utf-8"))
        assert "URLSession.shared" not in code, path.name
        calls = re.findall(r"URLSession\(configuration:[^\n]*", code)
        if calls:
            made[path.name] = (code, calls)
    assert set(made) == {"URLSessionTransport.swift", "Reachability.swift", "DownloadSession.swift", "StreamFetch.swift"}
    for name, (code, calls) in made.items():
        for call in calls:
            assert "delegate:" in call, (name, call)
            if "delegate: SameOriginRedirects.shared" in call:
                continue
            if name == "DownloadSession.swift":
                # a background session follows redirects itself, never asking: an answer from elsewhere isn't the song
                assert "URLSessionConfiguration.background(" in code
                assert "!Redirects.follows(from: downloadTask.originalRequest?.url, to: answeredAt) {" in code
                assert "status = 0" in code
                continue
            # its own delegate (a capped read, the player's StreamFetch) asks the same rule
            assert "willPerformHTTPRedirection" in code and FOLLOWS in code, (name, call)
    transport = made["URLSessionTransport.swift"][0]
    # every route's sessions and the event log's stream, the rule's own class; and the capped read's delegate
    assert transport.count("delegate: SameOriginRedirects.shared") == 2
    assert "final class SameOriginRedirects: NSObject, URLSessionTaskDelegate" in transport
    assert transport.count(FOLLOWS) == 2
    assert "delegate: SameOriginRedirects.shared" in made["Reachability.swift"][0]
    # Core's rule: the same scheme, host and port, each URL's own port where it names none
    rule = _code((CORE / "Redirects.swift").read_text(encoding="utf-8"))
    assert "return from == to" in rule
    assert 'case "http": return 80' in rule and 'case "https": return 443' in rule
