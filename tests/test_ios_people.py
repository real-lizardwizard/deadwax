"""
The iPhone app's People (Phase 8, slice 11 - notes/ios-specs/phase8-managing.md 10; notes/ios.md "People on the
phone") against the routes it asks - `GET /deadwax/people` and its eight POSTs (src/routes/people.py) - read from its
own source (ios/DeadwaxKit/Sources/DeadwaxCore: People.swift, PeopleFlow.swift, Routes.swift; ios/App: Manage/People*,
Shared/Routes.swift, You/ManageSection.swift, DeadwaxApp.swift, Root/RootView.swift) and held to the server's.

- the routes - method, path, and People's permission (tests/test_logins.py ROUTES), each in the client's list;
- what it SENDS - each body the strict model takes, key for key (an extra one, or a permission left out, is People's
  422 with nothing echoed), posted for real against People's fake Navidrome, one write after another;
- what it READS - the list's fields, each row's, the known-only's, each write's answer, and a refusal's kind - `locked`
  the one that brings Unlock People back;
- how long it waits - worked out from the server's own waits, and the idle unlock the server's;
- the words the server writes for the web app's places, said as the phone has them;
- what the app does with it - a page of its own (no Safari), the ticket taken in the tap, nothing asked under the
  sign-in, never a password logged, kept or put in an address, each emptied as the page goes.
"""

import inspect
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import auth, people as rules  # noqa: E402
from src.api import navidrome_admin  # noqa: E402
from src.routes import people as routes  # noqa: E402
from src.store import JobStore  # noqa: E402
from tests import test_people  # noqa: E402
from tests.test_ios_contract import (CORE, _code, coding_keys, fields, sent_fields, swift_function,  # noqa: E402
                                     swift_struct)
from tests.test_ios_needs_look import app_file, swift_like, timeouts  # noqa: E402
from tests.test_logins import ROUTES  # noqa: E402
from tests.test_people import PEOPLE, act, keep_things_for, later, password, signed_in  # noqa: E402

#? People's app, store and fake Navidrome - bound by assignment
nd = test_people.nd

PEOPLE_SWIFT = (CORE / "People.swift").read_text(encoding="utf-8")
FLOW_SWIFT = (CORE / "PeopleFlow.swift").read_text(encoding="utf-8")

#? the client's name for each route, and the route
ENDPOINTS = {
    "people": ("GET", "/deadwax/people"),
    "unlockPeople": ("POST", "/deadwax/people/unlock"),
    "lockPeople": ("POST", "/deadwax/people/lock"),
    "createPerson": ("POST", "/deadwax/people/create"),
    "resetPassword": ("POST", "/deadwax/people/{person_id}/password"),
    "setAdmin": ("POST", "/deadwax/people/{person_id}/admin"),
    "removePerson": ("POST", "/deadwax/people/{person_id}/remove"),
    "forgetPerson": ("POST", "/deadwax/people/forget"),
    "savePermissions": ("POST", "/deadwax/people/{person_id}/permissions"),
}

#? each body the phone sends, and the model that takes it
BODIES = {
    "PeopleUnlockBody": routes.UnlockBody,
    "PeopleCreateBody": routes.CreateBody,
    "PeopleResetBody": routes.ResetBody,
    "PeopleAdminBody": routes.AdminBody,
    "PeopleRemoveBody": routes.RemoveBody,
    "PeopleForgetBody": routes.ForgetBody,
    "PeoplePermissionsBody": routes.PermissionsBody,
}

APP_FILES = (("Manage", "PeopleModel.swift"), ("Manage", "PeopleScreen.swift"), ("Manage", "PeopleSheets.swift"))


def phone(struct: str, **values) -> dict:
    """A body as `struct` encodes it: each property under its CodingKeys name - every one of them sent."""
    keys = coding_keys(swift_struct(struct))
    assert set(values) == set(keys), (struct, set(keys) - set(values))
    return {keys[name]: value for name, value in values.items()}


def reads(struct: str, answer: dict) -> None:
    """Every field `struct` reads is in the answer, under the name it reads it by."""
    missing = set(fields(struct)) - set(answer)
    assert not missing, (struct, missing, sorted(answer))


def people_words(name: str) -> str:
    """A `public static let <name> = "..."` of People.swift, its `+`-joined pieces joined."""
    found = re.search(r"public static let " + name + r' = ((?:"[^"\n]*"\s*(?:\+\s*)?)+)', PEOPLE_SWIFT)
    assert found, f"no {name}"
    return "".join(re.findall(r'"([^"\n]*)"', found.group(1)))


def flow_function(signature: str) -> str:
    """The body of the one `func <signature>...` in PeopleFlow.swift, told apart by how its signature starts."""
    code = _code(FLOW_SWIFT)
    found = list(re.finditer(r"\bfunc\s+" + re.escape(signature) + r"[^{]*\{", code))
    assert len(found) == 1, f"func {signature} is declared {len(found)} times"
    opening = found[0].end() - 1
    depth = 0
    for index in range(opening, len(code)):
        depth += {"{": 1, "}": -1}.get(code[index], 0)
        if depth == 0:
            return code[opening + 1:index]
    raise AssertionError("unbalanced braces")


def app_code(*parts: str) -> str:
    return _code(app_file(*parts))


# ---------------------------------------------------------------------------- the routes, and who may

def test_every_route_is_the_servers_by_method_path_and_permission():
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    listed = re.search(r"public static let all: \[Endpoint\] = \[(.*?)\]", text, re.S).group(1)
    for name, (method, path) in ENDPOINTS.items():
        assert f'public static let {name} = Endpoint(method: "{method}", path: "{path}", query: [])' in text, name
        assert ROUTES[(method, path)] == "people", name
        assert re.search(rf"\b{name}\b", listed), name
    # every one of People's routes is one the phone asks
    assert {key for key, permission in ROUTES.items() if key[1].startswith("/deadwax/people")} == set(ENDPOINTS.values())


def test_the_page_is_offered_by_the_webs_rule_and_opens_in_the_app():
    offered = swift_function("People.swift", "offered")
    assert "Managing.parts(access.permissions, loginsOn: access.on).people" in offered
    assert "access.permissions.contains(.people)" in swift_function("People.swift", "allowed")
    section = app_code("You", "ManageSection.swift")
    assert "} else if tool == .people {" in section and "NavigationLink(value: AppRoute.people)" in section
    # no row opens Safari any more: since slice 12 WebAppRow, the openURL extension that opened it and the footer that
    # said which rows opened there are gone (tests/test_ios_no_web_app.py)
    assert "WebAppRow" not in section and "openURL" not in section and "footer:" not in section


# ---------------------------------------------------------------------------- what it sends

def test_each_body_is_the_strict_models_key_for_key():
    for struct, model in BODIES.items():
        assert sent_fields(struct) == set(model.model_fields), struct
        # every property is sent, none kept back
        assert set(fields(struct)) == set(model.model_fields), struct
        assert model.model_config.get("extra") == "forbid", struct
    # Lock's model declares nothing, and the phone sends `{}`
    assert routes.LockBody.model_fields == {} and routes.LockBody.model_config.get("extra") == "forbid"
    lock = swift_struct("PeopleLockBody")
    assert "try body.encode([String: String]())" in lock and "CodingKeys" not in lock


def test_the_phones_bodies_do_what_they_say_one_after_another(nd):
    keep_things_for(nd, "ghost")
    admin = signed_in(nd, "admin")
    # locked: Navidrome's accounts are none of the answer's, and a write is refused with the kind that brings Unlock back
    state = admin.get(PEOPLE).json()
    reads("PeopleState", state)
    assert state["available"] and state["locked"] and state["people"] == []
    refused = admin.post(f"{PEOPLE}/create", json=phone("PeopleCreateBody", user="maya", name="", password="maya-pass-1",
                                                       passwordAgain="maya-pass-1"))
    assert refused.status_code == 409 and refused.json()["kind"] == "locked"
    assert f'public static let lockedKind = "{refused.json()["kind"]}"' in FLOW_SWIFT
    # Unlock, as the phone sends it
    later(nd)
    act(nd, "admin")
    unlocked = admin.post(f"{PEOPLE}/unlock", json=phone("PeopleUnlockBody", password=password(nd, "admin")))
    assert unlocked.status_code == 200, unlocked.text
    act(nd, "admin")
    state = admin.get(PEOPLE).json()
    reads("PeopleState", state)
    assert not state["locked"] and state["people"][0]["you"]
    rows = {row["user"]: row for row in state["people"]}
    for row in rows.values():
        reads("PeoplePerson", row)
        reads("PeopleCan", row["can"])
    reads("PeopleTicks", rows["ethan"]["permissions"])
    [ghost] = state["known_only"]
    reads("PeopleKnownOnly", ghost)
    # Make account
    made = admin.post(f"{PEOPLE}/create", json=phone("PeopleCreateBody", user="maya", name="Maya", password="maya-pass-1",
                                                    passwordAgain="maya-pass-1"))
    assert made.status_code == 200, made.text
    reads("PeopleMade", made.json())
    reads("PeopleMadeAccount", made.json()["made"])
    assert made.json()["made"]["user"] == "maya" and "maya-pass-1" not in made.text
    # Reset password
    ethan = nd.fake.id_of("ethan")
    reset = admin.post(f"{PEOPLE}/{ethan}/password", json=phone("PeopleResetBody", user="ethan", password="a-new-one-1",
                                                               passwordAgain="a-new-one-1"))
    assert reset.status_code == 200, reset.text
    reads("PeopleReset", reset.json())
    assert "a-new-one-1" not in reset.text
    # Make admin, then No longer admin
    flipped = admin.post(f"{PEOPLE}/{ethan}/admin", json=phone("PeopleAdminBody", user="ethan", admin=True))
    assert flipped.status_code == 200, flipped.text
    reads("PeopleAdminAnswer", flipped.json())
    assert flipped.json()["admin"] is True
    back = admin.post(f"{PEOPLE}/{ethan}/admin", json=phone("PeopleAdminBody", user="ethan", admin=False))
    assert back.status_code == 200 and back.json()["admin"] is False
    # Save permissions: all five
    james = nd.fake.id_of("james")
    saved = admin.post(f"{PEOPLE}/{james}/permissions",
                       json=phone("PeoplePermissionsBody", user="james", request=True, edit=True, library=False,
                                  downloads=False, server=False))
    assert saved.status_code == 200, saved.text
    assert saved.json()["permissions"]["edit"] is True
    # Remove, the name typed
    maya = nd.fake.id_of("maya")
    removed = admin.post(f"{PEOPLE}/{maya}/remove", json=phone("PeopleRemoveBody", user="maya", confirm="maya"))
    assert removed.status_code == 200, removed.text
    assert nd.fake.by_name("maya") is None
    # Forget a name known only to deadwax
    forgot = admin.post(f"{PEOPLE}/forget", json=phone("PeopleForgetBody", user="ghost"))
    assert forgot.status_code == 200, forgot.text
    assert not nd.store.keeps_anything("ghost")
    # Lock: `{}`, and the list says locked again
    locked = admin.post(f"{PEOPLE}/lock", json={})
    assert locked.status_code == 200, locked.text
    assert admin.get(PEOPLE).json()["locked"] is True


def test_an_extra_field_or_a_permission_left_out_is_peoples_422_with_nothing_echoed(nd):
    admin = test_people.unlocked(nd, "admin")
    act(nd, "admin")
    secret = "never-echoed-pw-1"
    body = phone("PeopleCreateBody", user="maya", name="", password=secret, passwordAgain=secret) | {"show": True}
    answer = admin.post(f"{PEOPLE}/create", json=body)
    assert answer.status_code == 422 and answer.json() == {"detail": routes.PEOPLE_FORM}
    assert secret not in answer.text
    # the five are each required: one left out is never saved as taken away
    james = nd.fake.id_of("james")
    short = phone("PeoplePermissionsBody", user="james", request=True, edit=True, library=False, downloads=False,
                  server=False)
    del short["server"]
    answer = admin.post(f"{PEOPLE}/{james}/permissions", json=short)
    assert answer.status_code == 422 and answer.json()["detail"] == routes.PEOPLE_FORM
    assert nd.fake.writes() == []


# ---------------------------------------------------------------------------- what it reads

def test_a_refusal_is_read_with_its_kind_and_fix_and_peoples_403_has_none(nd):
    admin = test_people.unlocked(nd, "admin")
    act(nd, "admin")
    you = nd.fake.id_of("admin")
    answer = admin.post(f"{PEOPLE}/{you}/remove", json=phone("PeopleRemoveBody", user="admin", confirm="admin"))
    assert 400 <= answer.status_code < 500
    assert set(answer.json()) == {"detail", "kind", "fix"} and answer.json()["kind"]
    # someone without People: require("people")'s 403 has no kind - the phone says peopleOnly and asks /me again
    ethan = signed_in(nd, "ethan")
    refused = ethan.get(PEOPLE)
    assert refused.status_code == 403 and "kind" not in refused.json()
    outcome = swift_function("PeopleFlow.swift", "outcome")
    assert ("if answer.status == 403, kind == nil { return .refused(words: peopleOnly, kind: nil, fix: nil, askMe: true) }"
            in outcome)
    assert "askMe: answer.status == 403" in outcome
    # a 401 is the session's: never said here
    assert "if failure.isSignedOut { return .signedOut }" in outcome
    # only a 4xx is a refusal; a 5xx with deadwax's words says them; anything else may have happened
    assert "if (400..<500).contains(answer.status) {" in outcome
    assert "if answer.status >= 500, given(answer.detail) != nil {" in outcome
    assert "return .unknown(words: unknownWords(error, admin: admin))" in outcome
    # Navidrome saying they aren't one of its admins: the list's own answer, and /me asked again
    assert "!state.available && !state.locked" in swift_function("People.swift", "saysNotAdmin")


def test_the_server_words_naming_the_web_apps_place_are_said_as_the_phones():
    # since the web's 2.1.35 the server names Settings, the phone's place too; a server before it named the web's
    # You, which the phone still says as its own
    assert people_words("phonePasswordPlace") == "Settings → Account → Change password"
    assert people_words("phonePasswordPlace") in rules.YOUR_PASSWORD
    assert people_words("webPasswordPlace") == "You → Account → Change password"
    assert people_words("webPasswordPlace") not in rules.YOUR_PASSWORD
    # wherever the phone says the server's words: a refusal, its fix, a row's reasons, the locked reason
    outcome = swift_function("PeopleFlow.swift", "outcome")
    assert outcome.count("onPhone(") == 4
    screen = app_code("Manage", "PeopleScreen.swift")
    # (R14) said as a flat page's note
    assert "ManageNote(words: People.onPhone(reason))" in screen and screen.count("People.onPhone(") == 2
    # and the phone's place is where Change password is: Settings > Account
    account = app_code("You", "AccountSection.swift")
    assert "NavigationLink(value: AppRoute.changePassword)" in account


# ---------------------------------------------------------------------------- how long it waits

def test_the_waits_are_the_servers_worst_cases():
    waits = _code(FLOW_SWIFT)
    store, login = 10, 10
    native, write = 2 * navidrome_admin.TIMEOUT_SECONDS, 2 * navidrome_admin.WRITE_TIMEOUT_SECONDS
    subsonic = 2 * login
    for name, seconds in (("store", store), ("native", native), ("nativeWrite", write), ("subsonic", subsonic)):
        assert f"public static let {name}: Double = {seconds:g}" in waits, name
    # the numbers they are read from
    assert "timeout=10" in inspect.getsource(JobStore)
    assert "timeout=httpx.Timeout(10.0)" in inspect.getsource(auth)
    session = store
    work = {"create": store + write + native + subsonic, "reset": native + write + subsonic + 3 * store,
            "admin": 2 * native + write + store, "remove": 2 * native + write + 2 * store,
            "forget": native + 3 * store, "permissions": native + 3 * store}
    for kind, line in (("create", "store + nativeWrite + native + subsonic"),
                       ("reset", "native + nativeWrite + subsonic + 3 * store"),
                       ("admin", "native + native + nativeWrite + store"),
                       ("remove", "native + native + nativeWrite + 2 * store"),
                       ("forget", "native + 3 * store"), ("permissions", "native + 3 * store")):
        assert f"case .{kind}: return {line}" in waits, kind
    longest = max(work.values())

    def minute(seconds: float, floor: float = 0) -> float:
        return max(floor, -(-seconds // 60) * 60)

    given = timeouts()
    for kind, name in (("create", "createPerson"), ("reset", "resetPassword"), ("admin", "setAdmin"),
                       ("remove", "removePerson"), ("forget", "forgetPerson"), ("permissions", "savePermissions")):
        assert given[name] == minute(session + longest + work[kind]) > session + longest + work[kind], name
    # the unlock: the session, another unlock holding the name's throttle, the login, the role kept
    unlock = session + (native + store) + native + store
    assert "public static var unlock: Double { session + (native + store) + native + store }" in waits
    assert given["unlockPeople"] == 120 > unlock
    # the list: never less than its floor, longer by each account the last answer listed
    assert "public static var readBase: Double { session + native + 2 * store }" in waits
    assert "public static var readPerAccount: Double { 3 * store }" in waits
    assert given["people"] == 120 >= minute(session + native + 2 * store)
    assert "built.timeout = PeopleWaits.read(accounts: accounts)" in waits
    # Lock forgets the unlock in memory: the transport's own wait
    assert "lockPeople" not in given
    # every write is waited for as the routes' table says, never sent again by itself
    write_call = flow_function("peopleWrite")
    assert "try await call(endpoint, as: type, path: parameters, json: json)" in write_call
    # each write's own work is what its handler does
    assert "_signs_in_with" in inspect.getsource(routes.create) and "_signs_in_with" in inspect.getsource(routes.reset)


def test_the_idle_unlock_is_the_servers():
    assert f"public static let unlockIdleSeconds: Double = {navidrome_admin.UNLOCK_IDLE_SECONDS:g}" in PEOPLE_SWIFT
    assert f"public static let unlockIdleMinutes = {int(navidrome_admin.UNLOCK_IDLE_SECONDS // 60)}" in PEOPLE_SWIFT
    # always after the server's has run out, so the read it brings never keeps it alive
    assert "public static let idleCheckSeconds: Double = unlockIdleSeconds + 2" in PEOPLE_SWIFT
    assert "return now - answeredAt >= idleCheckSeconds" in swift_function("People.swift", "idleDue")
    # (review) once per answer: a read sent while the check is due is that answer's check, and no other is armed for
    # it - so a read that fails (People's 403, a proxy's 502) never loops, and never keeps the unlock alive by asking
    wait = flow_function("idleWait")
    assert "guard view == .list, let answeredAt, answeredAt != idleAskedFor else { return nil }" in wait
    assert "return max(0, People.idleCheckSeconds - (now - answeredAt))" in wait
    assert "answeredAt != idleAskedFor" in flow_function("idleDue")
    assert "if let now, idleDue(now: now) { idleAskedFor = answeredAt }" in flow_function("readBegan")
    model = app_code("Manage", "PeopleModel.swift")
    arm = swift_like(model, "armIdle")
    assert "guard mayAsk, let wait = flow.idleWait(now: now) else { return }" in arm
    assert "flow.idleDue(now: now)" in arm
    assert "flow.readBegan(now: now)" in swift_like(model, "read")
    # on a clock that counts while the phone sleeps
    assert "ContinuousClock.now" in model
    # the server refreshes an unlock only by using it: a list read is a use
    assert "UNLOCK_IDLE_SECONDS" in inspect.getsource(navidrome_admin.unlocked)


# ---------------------------------------------------------------------------- what the app does with it

def test_no_password_is_logged_kept_or_put_in_an_address():
    codes = [app_code(*parts) for parts in APP_FILES] + [_code(PEOPLE_SWIFT), _code(FLOW_SWIFT)]
    for code in codes:
        for leak in ("print(", "Logger", "os_log", "NSLog", "note(", "UserDefaults", "AppStorage", "dump(",
                     "URLQueryItem"):
            assert leak not in code, leak
    # the forms, the bodies and the flow say nothing of what they hold, however they are printed
    for struct in ("PeopleAddForm", "PeoplePasswords", "PeopleUnlockBody", "PeopleCreateBody", "PeopleResetBody",
                   "PeopleFlow"):
        body = swift_struct(struct)
        assert f'public var description: String {{ "{struct}(redacted)" }}' in body, struct
        assert "public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }" in body, struct
    # every password typed lives in the flow alone - never a page's own state
    secure = 0
    for parts in APP_FILES:
        code = app_code(*parts)
        found = re.findall(r"SecureField\([^,]+,\s*text: ([^\n]+)", code)
        assert len(found) == code.count("SecureField("), parts
        secure += len(found)
        for field in found:
            assert field.startswith("people.typing(\\."), (parts, field)
        assert not re.search(r"@State private var \w*(password|again)", code, re.I), parts
    # Unlock's, Add's two and Reset's two
    assert secure == 5
    # emptied as each is sent, when the page goes, under Now Playing, under the sign-in, and with another person
    assert "unlockPassword = \"\"" in flow_function("beginUnlock")
    screen = app_code("Manage", "PeopleScreen.swift")
    assert screen.count("people.pageGone()") == 2
    model = app_code("Manage", "PeopleModel.swift")
    assert "if shown { flow.hidden() } else { read() }" in swift_like(model, "nowPlaying")
    assert "if signInOver { flow.signInCame() } else { read() }" in swift_like(model, "signInChanged")
    assert "flow = PeopleFlow()" in swift_like(model, "reset")
    root = app_code("Root", "RootView.swift")
    assert "people.nowPlaying(shown)" in root and "people.signInChanged()" in root
    assert "people.reset()" in app_code("DeadwaxApp.swift")


def test_the_ticket_is_taken_in_the_tap_and_nothing_is_asked_under_the_sign_in():
    model = app_code("Manage", "PeopleModel.swift")
    read = swift_like(model, "read")
    assert read.index("flow.readBegan(now: now)") < read.index("Task {")
    assert "guard mine == generation else { return }" in read
    assert "pagesShown > 0 && active && online && !signInOver && allowed && server.client != nil" in model
    for write, call in (("unlock", "flow.beginUnlock("), ("lock", "flow.beginLock("), ("create", "flow.beginCreate("),
                        ("resetPassword", "flow.beginReset("), ("flip", "flow.beginFlip("),
                        ("remove", "flow.beginRemove("), ("forget", "flow.beginForget("), ("save", "flow.beginSave(")):
        body = swift_like(model, write)
        assert body.index(call) < body.index("send(ticket"), write
    # each write's client call made once: never sent again by itself
    for call in ("unlockPeople(", "lockPeople(", "createPerson(", "resetPassword(id", "setAdmin(", "removePerson(",
                 "forgetPerson(", "savePermissions("):
        assert model.count(f"client.{call}") == 1, call
    send = swift_like(model, "send")
    for step in ("navigation.peopleWriting(true)", "BackgroundHold(named: name)", "let outcome = await call()",
                 "guard mine == generation else { return }", "flow.ended(ticket, outcome",
                 "navigation.peopleWriting(flow.writing != nil)", "Notice.announce(words)",
                 "navigation.leavePerson(id)", "await server.refreshMe()", "if after.read { read() }"):
        assert step in send, step
    # (review) a read landing after the sign-in came, or after the page went, asks nothing more of deadwax: not /me,
    # not Navidrome's version, not the idle check - and a write's /me waits for the sign-in to go
    assert "if askMe == true, mayAsk { Task { await server.refreshMe() } }" in read
    landed = swift_like(model, "landed")
    assert landed.index("guard mayAsk else { return }") < landed.index("askVersion()") < landed.index("armIdle()")
    assert "guard mayAsk, !versionAsked" in swift_like(model, "askVersion")
    assert "if after.askMe, !signInOver { Task { await server.refreshMe() } }" in send
    # (review) the read after Unlock waits for the list it brings: the last list's count, kept through a lock
    assert "let accounts = flow.accountsListed" in read
    # nothing announced under the sign-in, and the admin flip always asks /me again
    ended = flow_function("ended(_ ticket: Int")
    assert "after.announce = signInOver ? nil : said?.announcement" in ended
    # (review) and a write answered under the sign-in puts away the sheet it kept
    assert "if signInOver, outcome != .signedOut { signInCame() }" in ended
    assert "if case .admin = write, outcome != .signedOut { after.askMe = true }" in ended
    assert 'if let kind, People.same(kind, PeopleOutcome.lockedKind) { lockedAgain() }' in ended


def test_the_pages_draw_as_the_spec_says():
    screen = app_code("Manage", "PeopleScreen.swift")
    sheets = app_code("Manage", "PeopleSheets.swift")
    # the list: you first as the server lists them, keyed by each person's id; a row pushes their page
    assert "ForEach(state.people) { (person: PeoplePerson) in" in screen
    assert "NavigationLink(value: AppRoute.person(person.id))" in screen
    assert "public struct PeoplePerson: Decodable, Sendable, Equatable, Hashable, Identifiable" in PEOPLE_SWIFT
    assert "ForEach(state.knownOnly) { (entry: PeopleKnownOnly) in" in screen
    # Lock and + in the bar; Forget… behind a question
    assert "Button(People.lock) {" in screen and "Image(systemName: People.addSymbol)" in screen
    assert ".accessibilityLabel(People.addTitle)" in screen
    assert "People.forgetQuestion(" in screen and "Button(People.forget, role: .destructive)" in screen
    assert "ManageNote(words: People.unlockedLine)" in screen
    assert "People.versionNote(people.navidrome)" in screen
    # Unlock People: the password manager's current password, its words and the plain-http note
    assert re.search(r"SecureField\(People\.unlockLabel, text: [^\n]+\)\s*\.textContentType\(\.password\)", screen)
    assert "People.unlockLine(user)" in screen and "flow.canUnlock(online: people.online" in screen
    # a person's page: five switches, the locked reason, Save sending all five; the changes the server offers
    assert "Toggle(isOn: people.ticked(person, box.category))" in screen
    assert ".disabled(box.locked || flow.writing != nil)" in screen
    assert "People.lockedReason(admin: person.admin, refused: person.can.permissions)" in screen
    assert "people.save(person)" in screen and "People.savesPermissions(person)" in screen
    assert "People.actions(person).filter(\\.offered)" in screen and "People.refusals(person)" in screen
    assert "People.flipWords(" in screen and "Button(People.keepAsItIs, role: .cancel)" in screen
    assert "now.admin == asked.admin { people.flip(now) }" in screen
    # the sheets: Add, Reset, Remove - none closed while its write is out
    assert sheets.count(".interactiveDismissDisabled(flow.writing != nil)") == 3
    assert screen.count(".navigationBarBackButtonHidden(flow.writing != nil)") == 2
    for words in ("People.userLabel", "People.displayLabel", "People.passwordLabel", "People.againLabel",
                  "People.formProblem(flow.add)", "People.newPasswordLabel", "People.newAgainLabel",
                  "People.resetProblem(flow.resetPasswords, user: user)", "People.removeLines(shown)",
                  "People.typeTheName", "People.removeButton(user)", "People.lockedNote"):
        assert words in sheets, words
    assert sheets.count("People.httpNote(at: server.address)") == 2
    assert sheets.count(".textContentType(.newPassword)") == 4
    # Remove: on only once the name matches; Return never removes
    assert "!flow.canRemove($0, online: reachability.online, signInOver: people.signInOver)" in sheets
    assert ".onSubmit { focused = false }" in sheets
    assert "People.removeReady(removeTyped, user: person.user)" in FLOW_SWIFT
    # its routes, its place on the tab, and the model the app holds
    navigation = app_code("Shared", "Routes.swift")
    assert "case .people: PeopleScreen()" in navigation and "case .person(let id): PersonScreen(id: id)" in navigation
    assert "People.pagesKept(people, writing: writingPeople)" in navigation
    assert "writingPeople = false" in swift_like(navigation, "reset")
    app = app_code("DeadwaxApp.swift")
    assert "reachability.whenChanged { [weak people] in people?.reachChanged() }" in app
    assert ".environment(people)" in app
    root = app_code("Root", "RootView.swift")
    assert "people.scene(phase)" in root and "people.sessionMoved()" in root
