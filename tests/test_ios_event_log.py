"""
The iPhone app's event log (Phase 8, slice 9 - notes/ios-specs/phase8-managing.md 8; notes/ios.md "The event log on the
phone") against the routes it reads - the lines kept (`GET /interface_logs/recent`) and the stream of them
(`GET /interface_logs/interface_logs?after=&boot=`, Server-Sent Events) - read from its own source
(ios/DeadwaxKit/Sources/DeadwaxCore: EventLog.swift, EventStream.swift, Routes.swift, HTTP.swift; ios/App/Manage,
ios/App/URLSessionTransport.swift) and held to the server's.

- what it READS - the history and the stream's first frames as the real routes send them (Fixtures/log/stream.json,
  made by ios/scripts/log_stream_answers.py through the whole app, and what it makes now), every field of a line the
  phone reads, the stream never gzipped and named as one;
- what it SENDS - `after` and `boot` as the route takes them, the session's cookie by hand (cookies off), the stream's
  Accept;
- how long it waits - the stream's keepalive is 15 s, so a silence of three is a stream lost (URLSession's wait between
  bytes, never a wait over all); the history held in memory, the transport's own 8 s; asked again STREAM_RETRY_MS after;
- who may: both routes Settings and the log's (tests/test_logins.py ROUTES), as the page is - and the app only carrying
  out what Core decides: nothing asked under the sign-in, the stream called off as the page goes or the app leaves the
  front, never held in the background.
"""

import importlib.util
import inspect
import json
import re
import sys
from pathlib import Path

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import logger as log_module  # noqa: E402
from src.api.app import start  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import interface_logs as route_module  # noqa: E402
from tests.test_ios_contract import CORE, _code, fields, swift_function  # noqa: E402
from tests.test_ios_needs_look import app_file, swift_like, timeouts  # noqa: E402
from tests.test_logins import ROUTES  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
LOG = (CORE / "EventLog.swift").read_text(encoding="utf-8")
STREAM = (CORE / "EventStream.swift").read_text(encoding="utf-8")
HELPER = REPO / "ios" / "scripts" / "log_stream_answers.py"
ANSWERS = REPO / "ios" / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "log" / "stream.json"
WEB_RULES = (REPO / "ui" / "src" / "lib" / "eventLog.ts").read_text(encoding="utf-8")


def _helper():
    spec = importlib.util.spec_from_file_location("ios_log_stream_answers", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def constant(text: str, name: str) -> float:
    found = re.search(r"public static let " + name + r": Double = ([\d.]+)\b", text)
    assert found, f"no {name}"
    return float(found.group(1))


# ---------------------------------------------------------------------------- the routes, and who may

def test_the_routes_are_the_servers_by_method_path_and_permission():
    text = (CORE / "Routes.swift").read_text(encoding="utf-8")
    for name, path, query in (
            ("recentLog", "/deadwax/interface_logs/recent", "[]"),
            ("logStream", "/deadwax/interface_logs/interface_logs", '["after", "boot"]')):
        line = f'public static let {name} = Endpoint(method: "GET", path: "{path}", query: {query})'
        assert line in text, line
        assert ROUTES[("GET", path)] == "server", path
    # the stream's two, as the route takes them: `after` a whole number from 0, `boot` at most 64 characters
    params = inspect.signature(route_module.interface_logs).parameters
    assert set(params) >= {"after", "boot"}
    after, boot = params["after"].default, params["boot"].default
    assert after.default is None and any(getattr(m, "ge", None) == 0 for m in after.metadata)
    assert boot.default is None and any(getattr(m, "max_length", None) == 64 for m in boot.metadata)
    # both or neither (api/logs.ts logStreamUrl), and only with a run held (EventLog.tsx `boot ? last : null`)
    query = swift_function("EventLog.swift", "streamQuery")
    assert 'guard let last, let boot, !boot.isEmpty else { return [] }' in query
    assert 'return [("after", String(last)), ("boot", boot)]' in query
    # who opens the page: Settings and the log, as App.tsx's `perms.has('server')`
    assert "public static func allowed(_ access: Access) -> Bool { access.can(.server) }" in LOG
    # the page is the app's own now: no Safari for the event log
    managing = _code((CORE / "Managing.swift").read_text(encoding="utf-8"))
    native = managing[managing.index("public var native: Bool {"):]
    # (slice 11) and People: every row is the app's own
    assert "case .edit, .queue, .care, .people, .settings, .log: return true" in native


def test_a_line_and_the_history_are_read_as_the_server_sends_them(monkeypatch):
    # every field of a line the phone reads, as SSEHandler makes them: the level and words always, the rest optional
    # (src only when said; seq, time and boot from a deadwax before 2.0.0-player.33 none)
    assert fields("LogLine") == {"event_type": False, "event_content": False, "src": True, "seq": True, "time": True,
                                 "boot": True}
    assert fields("RecentLog") == {"lines": False, "last": False, "boot": False}
    emit = inspect.getsource(log_module.SSEHandler.emit)
    assert 'event = {"event_type": record.levelname, "event_content": record.getMessage()}' in emit
    assert 'event["src"] = src' in emit
    assert "event.update(seq=_seq, time=record.created, boot=LOG_BOOT)" in emit
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    body = TestClient(start()).get("/deadwax/interface_logs/recent").json()
    assert set(body) == {"lines", "last", "boot"}
    assert body["boot"] == log_module.LOG_BOOT


def test_the_real_routes_answers_are_the_ones_the_helper_makes():
    # Fixtures/log/stream.json is what ios/scripts/log_stream_answers.py writes now, byte for byte - a change to what the
    # routes send fails here until the file is written again, and the phone's tests read it as the phone does
    helper = _helper()
    assert ANSWERS.read_text(encoding="utf-8") == helper.text()
    answers = json.loads(ANSWERS.read_text(encoding="utf-8"))
    assert [case["name"] for case in answers["cases"]] == ["from where the history ends", "from a line held below the last",
                                                           "another run's number", "from now"]
    recent = json.loads(answers["recent"])
    assert answers["cases"][0]["query"] == f"after={recent['last']}&boot={recent['boot']}"
    for case in answers["cases"]:
        assert case["status"] == 200
        assert case["headers"]["content-type"].split(";")[0] == "text/event-stream"
        # never gzipped (the phone's reader would get gzip's bytes) nor held back by nginx
        assert case["headers"]["content-encoding"] is None
        assert case["headers"]["x-accel-buffering"] == "no" and case["headers"]["cache-control"] == "no-cache"
        # ":" at once, so the stream is seen open before any line
        assert case["body"].startswith(":\n\n")
        for chunk in case["body"].split("\n\n")[1:-1]:
            assert chunk.startswith("data: ") and "\n" not in chunk, chunk
    # and the helper put everything back: the run's name, the numbers, the lines kept
    assert route_module.LOG_BOOT == log_module.LOG_BOOT != helper.BOOT


def test_the_stream_is_read_as_it_comes_with_the_cookie_by_hand():
    # Core: a transport that reads as it comes, the client asking for the stream with its Accept and the route's own
    # request (the session's cookie, the route's wait), refused as every route's refusal is - a 401 telling the app
    http = (CORE / "HTTP.swift").read_text(encoding="utf-8")
    assert "public protocol HTTPLineTransport: HTTPTransport {" in http
    assert "func lines(for request: HTTPRequest) async throws -> HTTPLines" in http
    client = swift_function("EventStream.swift", "logStream")
    assert "var built = request(Routes.logStream, query: EventLog.streamQuery(after: last, boot: boot))" in client
    assert 'built.headers["Accept"] = "text/event-stream"' in client
    assert "guard opened.response.status == 200 else { throw failure(opened.response, to: built) }" in client
    assert "guard EventStream.isStream(type) else { throw EventStream.NotTheStream(contentType: type) }" in client
    assert "if APIFailure.isCancellation(error) { throw CancellationError() }" in client
    assert "continuation.onTermination = { _ in reading.cancel() }" in client
    request = (CORE / "DeadwaxClient.swift").read_text(encoding="utf-8")
    assert 'if let session { headers["Cookie"] = SessionCookie.header(session) }' in request
    # the App: URLSession's bytes(for:) on a session of its own - cookies off and no cache as every session has, a wait
    # between bytes and none over all - its lines through Core's reader, called off when whoever reads them stops
    transport = app_file("URLSessionTransport.swift")
    lines = swift_like(transport, "lines")
    assert "extension URLSessionTransport: HTTPLineTransport {" in transport
    assert "try await streamSession().bytes(for: sent)" in lines
    assert "var splitter = EventStream.Lines()" in lines and "splitter.feed(byte)" in lines
    assert "reading.cancel()" in lines and "task.cancel()" in lines
    session = swift_like(transport, "streamSession")
    assert "let configuration = Self.configuration(waiting: EventStream.silence)" in session
    # (after review) the wait over all left at URLSession's default, a week - never an infinite one, a value CFNetwork may
    # not take as meant - in the streams' session and the configuration it starts from
    assert "timeoutIntervalForResource" not in _code(session)
    configuration = swift_like(transport, "configuration")
    assert "timeoutIntervalForResource" not in _code(configuration)
    assert "configuration.httpShouldSetCookies = false" in configuration
    assert "configuration.httpCookieAcceptPolicy = .never" in configuration
    assert "configuration.urlCache = nil" in configuration


# ---------------------------------------------------------------------------- the waits

def test_the_waits_are_the_servers_keepalive_and_the_webs_retry():
    # src/routes/interface_logs.py: a keepalive every 15 s while nothing is logged
    route = inspect.getsource(route_module.interface_logs)
    assert "await asyncio.wait_for(client_queue.get(), timeout=15)" in route
    assert 'chunk = ":\\n\\n"  # keepalive' in route
    assert constant(STREAM, "keepalive") == 15
    # three keepalives missed is a stream lost: URLSession's wait between bytes - the stream has no wait over all
    assert constant(STREAM, "silence") == 3 * constant(STREAM, "keepalive")
    assert timeouts()["logStream"] == constant(STREAM, "silence")
    # the history is what deadwax holds in memory, answered at once: the transport's own 8 s
    assert "recentLog" not in timeouts()
    recent = inspect.getsource(route_module.recent)
    assert "lines, last = recent_log()" in recent
    assert "with _lock:\n        return list(_history), _seq" in inspect.getsource(log_module.recent_log)
    # STREAM_RETRY_MS, asked again after a loss
    assert "export const STREAM_RETRY_MS = 5000" in WEB_RULES
    assert constant(STREAM, "retry") * 1000 == 5000
    # LOG_KEPT, as deadwax keeps
    assert "public static let kept = 500" in LOG and log_module.LOG_HISTORY == 500


# ---------------------------------------------------------------------------- the app carries it out

def test_the_app_only_carries_out_what_core_decides():
    model = app_file("Manage", "EventLogModel.swift")
    code = _code(model)
    # every decision Core's: the Feed told, and what it says carried out
    for call in ("feed.update(wanted: wanted, online: reachability.online)", "feed.tryAgain(wanted: wanted)",
                 "feed.historyLanded(ask, recent)", "feed.historyFailed(ask, error, admin: admin)", "feed.opened(ask)",
                 "feed.frame(ask, frame)", "feed.streamEnded(ask, ended, admin: admin)", "feed.retryDue(ask)",
                 "feed.clear()"):
        assert call in code, call
    # no wait of its own: the action's (STREAM_RETRY_MS)
    assert "try? await Task.sleep(for: .seconds(seconds))" in code
    assert not re.search(r"\.seconds\(\d", code) and "5000" not in code
    # each ask's number taken by Feed as the ask is decided - synchronously, before the Task that sends it: recheck and
    # Try again tell Feed, then carry out what it said
    recheck = swift_like(model, "recheck")
    assert "carry(feed.update(wanted: wanted, online: reachability.online))" in recheck
    assert "carry(feed.tryAgain(wanted: wanted))" in swift_like(model, "tryAgain")
    assert "Task" not in _code(recheck)
    # and the Task is made only once the ask is decided: carry hands each action's own number on
    for asked in ("case .read(let ask):\n            read(ask)", "case .open(let ask, let after, let boot):\n"
                  "            open(ask, after: after, boot: boot)", "case .wait(let ask, let seconds):\n"
                  "            wait(ask, seconds)"):
        assert asked in _code(swift_like(model, "carry")), asked
    # answers for the last person, or an ask a stop made stale, are dropped
    for asked in ("read", "open"):
        body = _code(swift_like(model, asked))
        assert "let mine = generation" in body and "guard mine == generation, !Task.isCancelled else { return }" in body
    # wanted only while the page shows with the app in front, in reach, allowed, and neither the sign-in nor (after
    # review) Now Playing over the app - the web's managingLive, whose !sheetOpen is Now Playing
    wanted = code[code.index("private var wanted: Bool {"):]
    wanted = wanted[:wanted.index("}")]
    for part in ("pagesShown > 0", "active", "reachability.online", "allowed", "server.signInOver == nil",
                 "server.client != nil", "!navigation.nowPlayingShown"):
        assert part in wanted, part
    web = (REPO / "ui" / "src" / "app" / "App.tsx").read_text(encoding="utf-8")
    assert "const managingLive = (tab: Tab) => pageShown && nav.tab === tab && !visualizerShown && !sheetOpen" in web
    assert "<EventLog allowed={perms.has('server')} live={managingLive(tab)}" in web
    # VoiceOver told what Core decides, in one announcement at a time - nothing posted but what it says
    announce = _code(swift_like(model, "announce"))
    assert "guard let words = feed.announcement(inReach: reachability.online), !words.isEmpty else { return }" in announce
    assert code.count(".post()") == 1 and code.count("AccessibilityNotification.Announcement(") == 1
    # a stop calls off what is out; a 403 asks /me again
    carry = _code(swift_like(model, "carry"))
    assert "case .stop:\n            asking?.cancel()" in carry
    assert "case .askMe:\n            Task { await server.refreshMe() }" in carry
    # another person: everything let go
    reset = _code(swift_like(model, "reset"))
    assert "generation += 1" in reset and "asking?.cancel()" in reset and "feed = EventStream.Feed()" in reset


def test_a_stream_that_never_ends_never_keeps_the_app_awake_or_running():
    for name in ("EventLogModel.swift", "EventLogScreen.swift"):
        code = _code(app_file("Manage", name))
        assert "BackgroundHold" not in code, name
        assert "ScreenAwake" not in code and "isIdleTimerDisabled" not in code, name
        assert "beginBackgroundTask" not in code, name
    # to the background it stops, back in front it rejoins - told by the root, as the app's scene changes
    scene = _code(swift_like(app_file("Manage", "EventLogModel.swift"), "scene"))
    assert "case .background:\n            active = false\n            recheck()" in scene
    assert "case .active:\n            guard !active else { return }\n            active = true\n            recheck()" in scene
    root = _code(app_file("Root", "RootView.swift"))
    assert "eventLog.scene(phase)" in root
    # the sign-in over the app come or gone: asked again (called off under it, rejoined after)
    sign_in = root[root.index(".onChange(of: server.signInOver)"):]
    assert "eventLog.recheck()" in sign_in[:sign_in.index(".onOpenURL")]
    app = _code(app_file("DeadwaxApp.swift"))
    assert "let eventLog = EventLogModel(server: server, reachability: reachability, navigation: navigation)" in app
    assert "reachability.whenChanged { [weak eventLog] in eventLog?.recheck() }" in app
    assert "eventLog.reset()" in app[app.index("server.whenPersonChanges {"):]
    assert ".environment(eventLog)" in app


def test_the_page_draws_as_the_spec_says():
    screen = app_file("Manage", "EventLogScreen.swift")
    code = _code(screen)
    body = code[code.index("var body: some View {"):code.index("@ViewBuilder private func lines")]
    # the page's frame on a view that stays as the branches swap: a ZStack, never a Group of them
    assert "ZStack {" in body and "Group {" not in body
    frame = body[body.index("ZStack {"):]
    for modifier in (".onAppear { log.shows() }", ".onDisappear { log.hides() }", ".editOutOfReach(",
                     ".onChange(of: log.allowed)", ".navigationTitle(EventLog.title)"):
        assert modifier in frame, modifier
    # (after review) Now Playing over the page - a full-screen cover, which leaves it shown under it - asks again
    assert ".onChange(of: navigation.nowPlayingShown) { _, _ in\n            log.recheck()" in frame
    # without the permission it says so and asks nothing; out of reach before anything was heard, it needs deadwax
    assert "if !log.allowed {" in body and "Text(EditWords.noPermission)" in body
    assert "Text(EditWords.needsDeadwax)" in body
    # Clear in the bar, off with nothing to clear; the stream's state under it
    assert "Button(EventLog.clear) {\n                        log.clear()" in body
    assert ".disabled(feed.log.lines.isEmpty)" in body
    assert ".safeAreaInset(edge: .top, spacing: 0) {" in body and "StreamLine(state: feed.stream)" in body
    lines = code[code.index("@ViewBuilder private func lines"):code.index("private struct StreamLine")]
    # the web's line first, then what went wrong with Try again, then the lines newest first - keyed by identity
    assert lines.index("Text(EventLog.pageLine)") < lines.index("Problem(words: problem)") < lines.index("ForEach(")
    assert "ForEach(feed.log.lines) { (line: EventLog.Line) in" in lines
    assert "indices" not in lines and "\\.offset" not in lines and "enumerated()" not in lines
    # a first read that hasn't answered: said, never "Nothing logged yet." while it isn't known
    assert "if feed.reading {" in lines and "Text(EventLog.reading)" in lines
    assert "Text(EventLog.empty(feed.log))" in lines
    # (after review) no label on the List: on a container that isn't an element of its own it can go to every row
    assert "accessibilityLabel" not in lines and "listLabel" not in code
    # under Reduce Motion, nothing slides in: no animation, and none an `.animation` above could add
    assert "if reduceMotion {\n                transaction.disablesAnimations = true\n" in lines
    assert "transaction.animation = nil" in lines
    row = code[code.index("private struct LogRow"):]
    # read once, words first; Copy by a long press and by VoiceOver's action
    assert ".accessibilityElement(children: .ignore)" in row and ".accessibilityLabel(EventLog.spoken(line))" in row
    assert ".contextMenu {" in row and "UIPasteboard.general.string = EventLog.copyText(line)" in row
    assert ".accessibilityAction(named: Text(EventLog.copy))" in row
    # the largest text: time, level and part stacked; the words wrap - and (after review) the part too, nothing cut off
    assert "if typeSize.isAccessibilitySize {" in row
    assert ".fixedSize(horizontal: false, vertical: true)" in row
    part = row[row.index("private var part: some View {"):row.index("private func copy()")]
    assert ".lineLimit(typeSize.isAccessibilitySize ? nil : 1)" in part
    assert ".fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)" in part
    # levels as the web colours them: errors the danger text, warnings amber
    assert "case .error: return Palette.danger" in row and "case .warning: return Palette.amber" in row
    # the time in the data face
    assert ".font(Typeface.mono(.caption))" in row
    stream = code[code.index("private struct StreamLine"):code.index("private struct Problem")]
    assert "case .live: return Palette.greenIcon" in stream and "case .lost: return Palette.amberIcon" in stream
    assert "state == .lost ? Palette.amber : Palette.quiet" in stream
    # the route and Manage's row
    routes = _code(app_file("Shared", "Routes.swift"))
    assert "case eventLog\n" in routes and "case .eventLog: EventLogScreen()" in routes
