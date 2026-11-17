"""
The iPhone app's Library care (Phase 8, slice 7 - notes/ios-specs/phase8-managing.md 6; notes/ios.md "Library care on the
phone") against the four routes it adds - Rescan (`POST /library/rescan?tracks=false`), In nobody's library (`GET
/library/held`) and its two writes (`POST /library/held/flags/{flag_id}/add` and `.../dismiss`) - read from its own source
(ios/DeadwaxKit/Sources/DeadwaxCore: LibraryCare.swift, Routes.swift, Managing.swift; ios/App/Manage) and held to the
server's. Its runs ask only the routes a single Get in Edit album asks (tests/test_ios_edit_parts_contract.py holds those),
one album at a time from the phone.

- what it SENDS - a rescan with `tracks=false` and no body; Add for them and Dismiss with none either;
- what it READS - the rescan's answer, the scan's own form with its ETag and headers, from a real rescan over real FLACs;
  In nobody's library's answer and each write's, from the real routes with logins on;
- how long it waits - a rescan 300 s, the route having no bound of its own (and one that never answers may have
  finished); the list and its writes each SQLite's busy timeout for every store call they make, and 10 s more;
- who may: Rescan and In nobody's library by Look after the library, the runs by Edit albums, as the server's routes are
  (tests/test_logins.py ROUTES) - and the app only carrying out what Core's CareRuns decides.
"""

import inspect
import re
import sqlite3
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import library  # noqa: E402
from src.api.app import start  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import held as held_route  # noqa: E402
from src.routes import library as library_route  # noqa: E402
from src.store import JobStore  # noqa: E402
from tests.test_ios_contract import CORE, _block, _code, fields, swift_function  # noqa: E402
from tests.test_ios_needs_look import app_file, swift_like, timeouts  # noqa: E402
from tests.test_logins import ROUTES  # noqa: E402
from tests import test_personal_libraries  # noqa: E402
from tests.test_personal_libraries import HELD, THIRD, grant, held, run, signed_in  # noqa: E402
from tests.test_retag import seed  # noqa: E402

# The logins-on fixture, used by name: bound by assignment (as test_player_as_you.py does), since pyflakes
# reads an imported fixture as an unused import.
on = test_personal_libraries.on

ALBUM = "Tame Impala/The Slow Rush (2020)"
CARE = (CORE / "LibraryCare.swift").read_text(encoding="utf-8")


def held_struct(name: str) -> str:
    """The body of `struct <name>` inside LibraryCare.swift's `enum Held` (Album and Answer are names other types share)."""
    code = _code(CARE)
    enum = re.search(r"\benum\s+Held\b[^{]*\{", code)
    body = _block(code, enum.end() - 1)
    match = re.search(r"\bstruct\s+" + name + r"\b[^{]*\{", body)
    assert match, f"Held.{name}"
    return _block(body, match.end() - 1)


def client_function(name: str) -> str:
    """The body of the DeadwaxClient extension's `func <name>` in LibraryCare.swift (CareRuns has a rescan too)."""
    code = _code(CARE)
    extension = re.search(r"\bextension\s+DeadwaxClient\b[^{]*\{", code)
    body = _block(code, extension.end() - 1)
    match = re.search(r"\bfunc\s+" + name + r"\b[^{]*\{", body)
    assert match, name
    return _block(body, match.end() - 1)


@pytest.fixture
def env(monkeypatch, tmp_path):
    """A library of real FLACs, logins off, Navidrome not set up - the scan's caches emptied before and after."""
    library.clear_scan_cache()
    monkeypatch.setattr(library_route, "_cache_loaded_for", None)
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    root = tmp_path / "music"
    root.mkdir()
    seed(root)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(root))
    store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    store.init()
    app = start()
    app.state.poller_task = SimpleNamespace(done=lambda: False)
    app.state.store = store
    yield SimpleNamespace(client=TestClient(app), store=store, app=app)
    library.clear_scan_cache()


# ---------------------------------------------------------------------------- the routes, and who may

def test_the_routes_are_the_servers_by_method_path_and_permission():
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    for name, method, path, query in (
            ("rescan", "POST", "/deadwax/library/rescan", '["tracks"]'),
            ("held", "GET", "/deadwax/library/held", "[]"),
            ("heldAdd", "POST", "/deadwax/library/held/flags/{flag_id}/add", "[]"),
            ("heldDismiss", "POST", "/deadwax/library/held/flags/{flag_id}/dismiss", "[]")):
        line = f'public static let {name} = Endpoint(method: "{method}", path: "{path}", query: {query})'
        assert line in text, line
        # all four Look after the library's, as Rescan and In nobody's library are on the phone
        assert ROUTES[(method, path)] == "library", (method, path)
    # the runs ask only a single Get's routes, each Edit albums' - as the runs are on the phone
    for path in ("/deadwax/library/art/fetch", "/deadwax/library/disc_art/fetch", "/deadwax/library/lyrics/fetch"):
        assert ROUTES[("POST", path)] == "edit", path
    parts = swift_function("LibraryCare.swift", "careParts")
    assert "let library = permissions.contains(.library), edit = permissions.contains(.edit)" in parts
    assert "CareParts(shown: library || edit, rescan: library, held: library, bulk: edit)" in parts
    assert "loginsOn && parts.held" in swift_function("LibraryCare.swift", "heldShown")
    # the page is the app's own now: no Safari for Library care
    managing = _code((CORE / "Managing.swift").read_text(encoding="utf-8"))
    assert "case .edit, .queue, .care, .settings, .log: return true" in managing[managing.index("public var native: Bool {"):]


def test_a_rescan_sends_tracks_false_and_no_body_and_the_writes_none():
    rescan = client_function("rescan")
    assert 'request(Routes.rescan, query: [("tracks", "false")])' in rescan
    assert "json:" not in rescan and "sending:" not in rescan
    assert "response.header(\"ETag\")" in rescan and ".with(headers: response)" in rescan
    for name, route in (("heldByNobody", "Routes.held"), ("addFlagged", "Routes.heldAdd"),
                        ("dismissFlag", "Routes.heldDismiss")):
        body = client_function(name)
        assert route in body and "sending:" not in body and "json:" not in body, name
    # the server's writes take no body: nothing the phone could leave out
    for handler in (held_route.add_flagged, held_route.dismiss_flag):
        assert list(inspect.signature(handler).parameters) == ["request", "flag_id"]
    assert list(inspect.signature(library_route.rescan).parameters) == ["request", "tracks"]


# ---------------------------------------------------------------------------- what the phone reads, from real routes

def test_a_rescan_answers_as_the_scan_does(env):
    scan = env.client.get("/deadwax/library/albums", params={"tracks": "false"})
    assert scan.status_code == 200, scan.text
    rescan = env.client.post("/deadwax/library/rescan", params={"tracks": "false"})
    assert rescan.status_code == 200, rescan.text
    [album] = rescan.json()["albums"]
    assert album["path"] == ALBUM
    # the scan's own form: no tracks, and every key the phone's ScanAlbum reads (the edit contract holds the scan's)
    assert "tracks" not in album and "track_defaults" not in album
    assert set(scan.json()["albums"][0]) == set(album)
    assert set(fields("ScanAlbum")) <= set(album), set(fields("ScanAlbum")) - set(album)
    assert "total_size" in fields("ScanAlbum") and album["total_size"] > 0, "Library care's totals add them up"
    # its ETag, kept for the next read, and the headers its facts read
    assert rescan.headers.get("ETag")
    assert rescan.headers.get("X-Scanned-At") and float(rescan.headers["X-Scan-Seconds"]) >= 0
    # a read after it is the same answer: a 304 for the ETag the rescan gave
    again = env.client.get("/deadwax/library/albums", params={"tracks": "false"},
                           headers={"If-None-Match": rescan.headers["ETag"]})
    assert again.status_code == 304


def test_in_nobodys_library_is_what_the_phone_reads(on):
    dummy, third = held(on), held(on, THIRD, "rel-third")
    signed_in(on, "ethan")
    grant(on, ["ethan"], dummy)
    # seeded already: nobody is given the whole store at their first sign-in (test_personal_libraries' own setup)
    with sqlite3.connect(on.path) as connection:
        connection.execute("INSERT INTO library_seed (id, user, seeded_at, albums) VALUES (1, 'x', 'then', 0)")
    james = signed_in(on, "james")
    flag = run(on.store.flag_add(third, 7, ["ethan", "sam"], "Portishead", "Third", THIRD, "rel-third"))
    answer = james.get(HELD)
    assert answer.status_code == 200, answer.text
    got = answer.json()
    assert set(fields("Answer", held_struct("Answer"))) <= set(got)
    [album] = got["albums"]
    assert set(fields("UnheldAlbum", held_struct("UnheldAlbum"))) <= set(album), set(fields("UnheldAlbum", held_struct("UnheldAlbum"))) - set(album)
    [flagged] = got["flags"]
    assert set(fields("Flag", held_struct("Flag"))) <= set(flagged), set(fields("Flag", held_struct("Flag"))) - set(flagged)
    # Add for them, then a second press: deadwax's words, a refusal (4xx) the phone says as they are
    added = james.post(f"{HELD}/flags/{flag}/add")
    assert added.status_code == 200 and set(fields("Added", held_struct("Added"))) <= set(added.json())
    second = james.post(f"{HELD}/flags/{flag}/add")
    assert second.status_code == 409 and second.json()["detail"] == "That has been dealt with already."
    other = run(on.store.flag_add(third, 8, ["sam"], "Portishead", "Third", THIRD, "rel-third"))
    dismissed = james.post(f"{HELD}/flags/{other}/dismiss")
    assert dismissed.status_code == 200 and set(fields("Dismissed", held_struct("Dismissed"))) <= set(dismissed.json())


# ---------------------------------------------------------------------------- how long the phone waits

def test_a_rescan_and_the_list_are_waited_for_past_the_routes_worst_case():
    given = timeouts()
    # a rescan drops the cache and reads every file - no bound of its own, so the phone gives it 300 s, and one that
    # never answers may have finished (CareRuns.rescanEnded: said, and read again)
    handler = inspect.getsource(library_route.rescan)
    assert "await _scan_with_queue(request, True)" in handler
    scan = inspect.getsource(library_route._scan_with_queue)
    assert "wait_for" not in handler + scan and "timeout" not in handler, "the rescan has no bound of its own"
    #? no server constant to pin it to: the value itself is pinned, and the phone says a rescan that never answered may
    #? have finished (CareRuns.rescanEnded), so the wait is a choice, not a bound
    assert given["rescan"] == 300
    assert "case .unanswered:\n            return AfterRescan(readAgain: true, tell: true, mayHaveFinished: true)" \
        in swift_function("LibraryCare.swift", "rescanEnded")
    # In nobody's library and its writes are SQLite alone, each store call its own connection - which may wait out the
    # busy timeout (store._connect's) before it gets the database: the list's two calls, Add for them's five (the open
    # flags, the album followed, the flag closed, the grants, the job's row) and Dismiss's two, each that long, and 10 s
    busy = re.search(r"sqlite3\.connect\(self\.path, timeout=(\d+)\)", inspect.getsource(JobStore._connect))
    assert busy, "store._connect's busy timeout"
    for route, handler, calls in (("held", held_route.held_by_nobody, 2), ("heldAdd", held_route.add_flagged, 5),
                                  ("heldDismiss", held_route.dismiss_flag, 2)):
        source = inspect.getsource(handler)
        assert source.count("await store.") == calls, route
        assert "httpx" not in source and "navidrome" not in source.lower(), "nothing asked of another server"
        assert given[route] == calls * int(busy.group(1)) + 10, route


# ---------------------------------------------------------------------------- the app

def test_the_runs_are_the_apps_and_only_carry_out_what_core_decides():
    model = app_file("Manage", "CareRunModel.swift")
    # held by the app - made once, reset for another person, told of reach and of the scene
    app = app_file("DeadwaxApp.swift")
    assert "let care = CareRunModel(server: server, reachability: reachability, navigation: navigation)" in app
    assert "reachability.whenChanged { [weak care] in care?.reachChanged() }" in app
    assert "care.reset()" in app and ".environment(care)" in app
    assert "care.scene(phase)" in app_file("Root", "RootView.swift")
    # one album at a time, each asked for by CareRuns.next and counted by CareRuns.finished
    drive = swift_like(model, "drive")
    assert "switch runs.next(allowed: parts.bulk, online: reachability.online) {" in drive
    assert "if runs.finished(step) { navigation?.managed() }" in drive
    # the session ended, or none to ask with: the run stops after the album out (no step of its own for it)
    assert "if server.signInOver != nil || client == nil { runs.sessionEnded() }" in drive
    assert "let step = await fetch(kind, album, with: client)" in drive
    # (slice 7's review) a 403 stops the run (Core's .forbidden) and asks /me again, so the page draws what they may do
    assert "if case .forbidden = step { Task { await server.refreshMe() } }" in drive
    assert drive.index("if case .forbidden = step") < drive.index("if runs.finished(step)")
    assert ".cancelled" not in model + CARE, "nothing in the app cancels a run's request"
    assert drive.count("guard mine == generation else { return }") == 1 and "while mine == generation {" in drive
    # each album through the route a single Get uses, held through the background
    fetch = swift_like(model, "fetch")
    assert "BackgroundHold(named:" in fetch and "defer { hold.end() }" in fetch
    for call in ("client.getCover(path: album.path)", "client.getDiscArt(album)", "client.getLyrics(album)"):
        assert call in fetch, call
    assert "return BulkTargets.step(kind, album, failure: error)" in fetch
    assert "server.client" not in fetch, "the client drive checked is the one asked"
    # (slice 7's review) a read that lands asks again: one already out as a run ended, or as deadwax came back, began
    # too early to trust, and nothing else would ask for the one after it
    read = swift_like(model, "read")
    assert read.index("runs.readLanded(ticket)") < read.index("readIfNeeded(again: false)")
    assert read.index("guard mine == generation, read == .landed else { return }") < read.index("runs.readLanded(ticket)")
    # (slice 7's review) nothing read under the sign-in over the app (the page still counts as shown there); once it
    # goes, read again
    assert "guard parts.shown, server.signInOver == nil," in swift_like(model, "readIfNeeded")
    assert "readIfNeeded(again: true)" in swift_like(model, "sessionBack")
    screen = app_file("Manage", "LibraryCareScreen.swift")
    assert ".onChange(of: server.signInOver == nil) { _, clear in\n            if clear { care.sessionBack() }" in screen
    # (slice 7's review) the ladder as the web's: a read ended (answered or failed) is its `loaded`, and READ_FAILED is
    # said whenever there are no albums to show
    assert "NeedsLook.state(problem: scan.answer?.problem, loaded: scan.ended, failed: scan.failed != nil," in model
    assert "scan.failure(saying: scan.albums.isEmpty ? LibraryCare.readFailed : LibraryCare.rereadFailed)" in model
    assert "var ended: Bool { answer != nil || failed != nil }" in app_file("Edit", "LibraryScanModel.swift")
    # Rescan: Core decides, the count is told after it
    rescan = swift_like(model, "rescan")
    assert "let after = runs.rescanEnded(ticket, how)" in rescan
    assert rescan.index("if after.readAgain { await read() }") < rescan.index("if after.tell { navigation?.managed() }")
    assert "EditWords.mayHaveFinished" in rescan
    # the screen stays on only while a run goes and its page shows - through ScreenAwake, the one place the idle timer
    # is set since slice 8's Re-time wants it too (tests/test_ios_server_settings.py holds the rest of the app to it)
    assert "ScreenAwake.keep(runs.keepsScreenOn(visible: visible), for: .libraryCare)" in model
    for path in (CORE.parent.parent.parent / "App").rglob("*.swift"):
        if path.name != "ScreenAwake.swift":
            assert "isIdleTimerDisabled" not in path.read_text(encoding="utf-8"), path.name
    # to the background, the run stops after the album out; another person, it stops where it is
    assert "runs.suspended()" in swift_like(model, "scene")
    reset = swift_like(model, "reset")
    assert "generation += 1" in reset and "runs = CareRuns()" in reset and "scan = LibraryScanModel()" in reset
    for polling in ("Task.sleep", "Timer.publish", "Timer.scheduled", "TimelineView"):
        assert polling not in model, f"nothing polled: {polling}"
    # the rescan is the scan model's, ticketed as a read is
    scan = swift_like(app_file("Edit", "LibraryScanModel.swift"), "rescan")
    assert "let (fresh, tag) = try await client.rescan()" in scan and "guard ticket == reads else { return .dropped }" in scan
    assert "return RetagFlow.outcome(of: error) == .refused ? .refused : .unanswered" in scan


def test_the_page_draws_by_permission_and_out_of_reach_as_edit_album_does():
    screen = app_file("Manage", "LibraryCareScreen.swift")
    assert "if !parts.shown {" in screen and "Text(EditWords.noPermission)" in screen
    assert "} else if !reachability.online && !care.scan.loaded {" in screen and "Text(EditWords.needsDeadwax)" in screen
    assert "if parts.rescan {\n                    rescanSection(online: online)" in screen
    assert "if parts.bulk {" in screen and "ForEach(BulkTargets.kinds, id: \\.self)" in screen
    assert "if care.heldShown {" in screen and "NavigationLink(value: AppRoute.heldByNobody)" in screen
    assert ".editOutOfReach(!online && care.scan.loaded)" in screen
    assert "if reduceMotion { transaction.animation = nil }" in screen
    assert ".disabled(!care.startOpen(kind, online: online))" in screen
    assert ".disabled(!care.rescanOpen(online: online))" in screen
    manage = app_file("You", "ManageSection.swift")
    care = manage[manage.index("} else if tool == .care {"):manage.index("} else if let url")]
    assert "NavigationLink(value: AppRoute.libraryCare)" in care
    routes = app_file("Shared", "Routes.swift")
    assert "case .libraryCare: LibraryCareScreen()" in routes and "case .heldByNobody: HeldByNobodyScreen()" in routes


def test_in_nobodys_library_writes_one_at_a_time_and_reads_again_after_each():
    page = app_file("Manage", "HeldByNobodyScreen.swift")
    act = swift_like(page, "act")
    # (slice 7's review) never while the list is read - the read after a write included
    assert "flow.begin(flag.id, online: online, reading: reading)" in act
    assert "let open = model.flow.open(online: online, reading: model.reading)" in page
    assert "BackgroundHold(named:" in act
    assert "refused = EditWords.said(error, failed: write.failed, admin: admin)" in act
    assert "refused = EditWords.writeFailure(error, failed: write.failed, admin: admin)" in act
    assert "said = EditWords.mayHaveFinished" in act
    # the list read again whatever came of it, the write ended first
    assert act.index("flow.ended()") < act.index("await read()")
    assert act.index("} catch {") < act.index("await read()")
    read = swift_like(page, "read")
    # (slice 7's review) nothing read under the sign-in over the app; once it goes, read again while the page shows
    assert "guard reachability?.online == true, samePerson, server?.signInOver == nil, let client = server?.client" in read
    assert ".onChange(of: server.signInOver == nil) { _, clear in\n            guard clear, visible, shown else { return }" \
        in page
    assert "guard ticket == flow.reads, samePerson else { return }" in read
    assert "problem = EditWords.said(error, failed: Held.readFailed, admin: admin)" in read
    assert "ForEach(answer.flags)" in page and "ForEach(Held.listedAlbums(answer.albums, all: model.all))" in page
    assert ".editOutOfReach(!online && model.answer != nil)" in page
