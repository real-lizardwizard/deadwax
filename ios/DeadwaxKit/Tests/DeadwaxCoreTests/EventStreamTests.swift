import Foundation
import Testing
@testable import DeadwaxCore

/// A transport that reads answers as they come (HTTPLineTransport): each request answered by a handler with its
/// response and its body's lines, remembered - and each answer's lines told when whoever reads them stops.
final class FakeLineTransport: HTTPLineTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (HTTPRequest) throws -> HTTPLines)?
    private(set) var sent: [HTTPRequest] = []
    private(set) var stopped = 0

    func handle(_ handler: @escaping @Sendable (HTTPRequest) throws -> HTTPLines) {
        lock.withLock { self.handler = handler }
    }

    /// An answer whose body is `lines`, then (when `ending` is given) that failure - or never ending at all.
    func answer(_ status: Int, _ type: String?, _ lines: [String], ending: URLError? = nil, endless: Bool = false,
                body: String = "") {
        handle { [weak self] _ in
            let owner = self
            let stream = AsyncThrowingStream<String, any Error> { continuation in
                for line in lines { continuation.yield(line) }
                if let ending { continuation.finish(throwing: ending) } else if !endless { continuation.finish() }
                continuation.onTermination = { _ in owner?.noteStop() }
            }
            return HTTPLines(response: HTTPResponse(status: status, headers: type.map { ["Content-Type": $0] } ?? [:],
                                                    body: Data(body.utf8)),
                             lines: stream)
        }
    }

    private func noteStop() { lock.withLock { stopped += 1 } }

    var last: HTTPRequest? { lock.withLock { sent.last } }
    var stops: Int { lock.withLock { stopped } }

    func lines(for request: HTTPRequest) async throws -> HTTPLines {
        let handler = lock.withLock { () -> (@Sendable (HTTPRequest) throws -> HTTPLines)? in
            sent.append(request)
            return self.handler
        }
        guard let handler else { throw URLError(.cannotConnectToHost) }
        return try handler(request)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { sent.append(request) }
        return HTTPResponse(status: 404, body: Data(#"{"detail":"Not Found"}"#.utf8))
    }
}

/// The event log's stream (notes/ios-specs/phase8-managing.md 8): the body read as lines and frames as EventSource
/// reads them, the page's life with the history and the stream (EventStream.Feed) case by case, the client's stream
/// through a line transport, the waits, and the real server's answers (Fixtures/log/stream.json, made by
/// ios/scripts/log_stream_answers.py through the real routes) read as the phone reads them.
@Suite struct EventStreamTests {
    static let server = try! ServerAddress.parse("192.168.3.20:8090").get()

    static func lines(_ text: String, split: Int = 0) -> [String] {
        var reader = EventStream.Lines()
        let bytes = Array(text.utf8)
        guard split > 0 else { return reader.feed(bytes) }
        var out: [String] = []
        var at = 0
        while at < bytes.count {
            out += reader.feed(bytes[at..<min(at + split, bytes.count)])
            at += split
        }
        return out
    }

    static func frames(_ text: String) -> [EventStream.Frame] {
        var frames = EventStream.Frames()
        return lines(text).compactMap { frames.take($0) }
    }

    static func answered(_ status: Int, _ path: String = "/interface_logs/interface_logs",
                         detail: String? = nil) -> APIFailure {
        .answered(.init(status: status, method: "GET", path: path, detail: detail))
    }

    static let offline = APIFailure.offline(.init(server: server, method: "GET", path: "/interface_logs/recent",
                                                  reason: "The Internet connection appears to be offline."))
    static let timedOut = APIFailure.timeout(.init(server: server, method: "GET", path: "/interface_logs/interface_logs",
                                                   reason: "The request timed out."))

    static func line(_ seq: Int?, _ words: String = "w", boot: String? = "b1", type: String = "INFO") -> LogLine {
        LogLine(eventType: type, eventContent: words, src: nil, seq: seq, time: 1763300000, boot: boot)
    }

    static func message(_ line: LogLine) -> EventStream.Frame {
        var fields: [String: Any] = ["event_type": line.eventType, "event_content": line.eventContent]
        if let seq = line.seq { fields["seq"] = seq }
        if let time = line.time { fields["time"] = time }
        if let boot = line.boot { fields["boot"] = boot }
        let data = try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return .message(type: "message", data: String(decoding: data, as: UTF8.self), id: "")
    }

    // MARK: the body, as lines

    @Test func theBodyIsReadAsLinesEveryEndingAndBlankLinesKept() {
        #expect(Self.lines(":\n\ndata: a\n\n") == [":", "", "data: a", ""])
        #expect(Self.lines("a\r\nb\rc\nd") == ["a", "b", "c"], "d has no ending yet")
        #expect(Self.lines("a\r\n\r\nb\r\r") == ["a", "", "b", ""])
        // a CRLF split across two reads is one ending, never a blank line
        for split in 1...5 {
            #expect(Self.lines("ab\r\ncd\r\n\r\n", split: split) == ["ab", "cd", ""], "split every \(split)")
        }
        // a character's bytes split across reads, and a byte order mark only at the very start
        #expect(Self.lines("\u{FEFF}data: Ros\u{E9} \u{266A}\n\u{FEFF}x\n", split: 1) == ["data: Ros\u{E9} \u{266A}", "\u{FEFF}x"])
        // bytes that aren't UTF-8 read as the replacement character, as the spec's decode does
        var reader = EventStream.Lines()
        #expect(reader.feed([0x61, 0xFF, 0x62, 0x0A]) == ["a\u{FFFD}b"])
    }

    @Test func aLineLongerThanTheMostIsDroppedWholeAndTheNextRead() {
        var reader = EventStream.Lines()
        var said = reader.feed(Array(repeating: UInt8(ascii: "x"), count: EventStream.Lines.most + 10))
        #expect(said.isEmpty)
        said = reader.feed(Array("\ndata: next\n".utf8))
        #expect(said == ["data: next"], "the long line gone at its ending, and nothing of it held")
        #expect(EventStream.Lines.most == 1 << 20)
    }

    // MARK: the lines, as frames

    @Test func framesAreReadAsEventSourceReadsThem() {
        #expect(Self.frames(":\n\n") == [.comment("")])
        #expect(Self.frames(": keepalive\n") == [.comment(" keepalive")])
        #expect(Self.frames("data: {\"a\":1}\n\n") == [.message(type: "message", data: "{\"a\":1}", id: "")])
        // data lines joined by newlines; one space after the colon dropped, a second kept; a field with no colon
        #expect(Self.frames("data:one\ndata:  two\ndata\n\n") == [.message(type: "message", data: "one\n two\n", id: "")])
        #expect(Self.frames("data\n\n") == [.message(type: "message", data: "", id: "")])
        // an event's type, and the last id kept across events; a blank line with nothing gathered dispatches nothing
        #expect(Self.frames("event: ping\nid: 7\ndata: x\n\n\n\ndata: y\n\n")
                == [.message(type: "ping", data: "x", id: "7"), .message(type: "message", data: "y", id: "7")])
        // an event not ended by a blank line is never dispatched; fields not known are left alone
        #expect(Self.frames("data: half\nfoo: bar") == [])
        #expect(Self.frames("foo: bar\n\n") == [])
        var frames = EventStream.Frames()
        for line in Self.lines("retry: 3000\nretry: soon\n\n") { _ = frames.take(line) }
        #expect(frames.retry == 3000)
    }

    // MARK: how an ask ended

    @Test func anEndIsClassedByWhatCameBack() {
        #expect(EventStream.End(CancellationError()) == .cancelled)
        #expect(EventStream.End(URLError(.cancelled)) == .cancelled)
        #expect(EventStream.End(Self.answered(401)) == .signedOut)
        // a 401 from the sign-in's own route is a wrong password, never a session ended
        #expect(EventStream.End(Self.answered(401, "/auth/login")) == .refused)
        #expect(EventStream.End(Self.answered(403)) == .forbidden)
        for status in [400, 404, 405, 409, 422, 429, 499] {
            #expect(EventStream.End(Self.answered(status)) == .refused, "\(status)")
        }
        for status in [500, 502, 503, 504, 599] {
            #expect(EventStream.End(Self.answered(status)) == .lost, "\(status)")
        }
        #expect(EventStream.End(Self.offline) == .lost)
        #expect(EventStream.End(Self.timedOut) == .lost)
        #expect(EventStream.End(APIFailure.other("garbled")) == .lost)
        #expect(EventStream.End(EventStream.NotTheStream(contentType: "text/html")) == .lost)
        #expect(EventStream.isStream("text/event-stream"))
        #expect(EventStream.isStream("text/event-stream; charset=utf-8"))
        #expect(EventStream.isStream(" Text/Event-Stream ;charset=utf-8"))
        #expect(!EventStream.isStream("text/html; charset=utf-8"))
        #expect(!EventStream.isStream("application/json"))
        #expect(!EventStream.isStream(nil))
    }

    // MARK: the waits

    @Test func theWaitsAreTheServersAndHeldToIt() {
        // src/routes/interface_logs.py's keepalive (tests/test_ios_event_log.py holds the route to it)
        #expect(EventStream.keepalive == 15)
        // silence: three keepalives missed is a stream lost - URLSession's wait between bytes, nothing over all
        #expect(EventStream.silence == 3 * EventStream.keepalive)
        #expect(Routes.timeouts[Routes.logStream] == EventStream.silence)
        // the history is held in memory: the transport's own 8 s
        #expect(Routes.timeouts[Routes.recentLog] == nil)
        // STREAM_RETRY_MS
        #expect(EventStream.retry == 5)
    }

    // MARK: the page's life

    @Test func thePageReadsTheHistoryThenTheStreamFromWhereItEnds() {
        var feed = EventStream.Feed()
        #expect(feed.stream == .connecting && feed.step == .idle && !feed.reading)
        #expect(feed.update(wanted: false, online: true) == .none, "nothing out, nothing to stop")
        #expect(feed.update(wanted: true, online: true) == .read(1))
        #expect(feed.reading && feed.stream == .connecting)
        #expect(feed.update(wanted: true, online: true) == .none, "asked once")
        let recent = RecentLog(lines: [Self.line(1), Self.line(2), Self.line(3)], last: 3, boot: "b1")
        #expect(feed.historyLanded(1, recent) == .open(2, after: 3, boot: "b1"))
        #expect(feed.log.lines.count == 3 && feed.heard && !feed.reading && feed.stream == .connecting)
        feed.opened(2)
        #expect(feed.stream == .live)
        // the replay of a line had, a keepalive, a new line, something that isn't a line
        feed.frame(2, Self.message(Self.line(3)))
        feed.frame(2, .comment(""))
        feed.frame(2, Self.message(Self.line(4, "new")))
        feed.frame(2, .message(type: "message", data: "not json", id: ""))
        feed.frame(2, .message(type: "message", data: "[1, 2]", id: ""))
        feed.frame(2, .message(type: "ping", data: String(decoding: try! JSONEncoder().encode(["event_type": "INFO"]), as: UTF8.self), id: ""))
        #expect(feed.log.lines.map(\.seq) == [4, 3, 2, 1])
        #expect(feed.log.last == 4)
    }

    @Test func anAnswerForAnAskNoLongerNewestIsDropped() {
        var feed = EventStream.Feed()
        #expect(feed.update(wanted: true, online: true) == .read(1))
        // the page goes before the history lands: called off, and its answer dropped
        #expect(feed.update(wanted: false, online: true) == .stop)
        #expect(feed.step == .idle && feed.stream == .connecting)
        #expect(feed.historyLanded(1, RecentLog(lines: [Self.line(1)], last: 1, boot: "b1")) == .none)
        #expect(feed.log.lines.isEmpty)
        #expect(feed.historyFailed(1, Self.offline, admin: false) == .none)
        #expect(feed.historyProblem == nil)
        // shown again: a new ask, and a stream of the old one draws nothing
        #expect(feed.update(wanted: true, online: true) == .read(3))
        #expect(feed.historyLanded(3, RecentLog(lines: [Self.line(1)], last: 1, boot: "b1")) == .open(4, after: 1, boot: "b1"))
        feed.frame(2, Self.message(Self.line(9)))
        feed.opened(2)
        #expect(feed.log.lines.count == 1 && feed.stream == .connecting)
        #expect(feed.streamEnded(2, nil, admin: false) == .none)
        #expect(feed.retryDue(4) == .none, "no wait out")
    }

    @Test func aHistoryNotReadIsSaidAndTheStreamOpensFromNowAndTheNextFillsTheGap() {
        var feed = EventStream.Feed()
        _ = feed.update(wanted: true, online: true)
        #expect(feed.historyFailed(1, Self.offline, admin: false) == .open(2, after: nil, boot: nil))
        #expect(feed.historyProblem == EventLog.historyFailure(Self.offline, admin: false))
        #expect(!feed.reading, "a failure said, never a spinner for good")
        #expect(feed.tryAgainShown)
        feed.opened(2)
        feed.frame(2, Self.message(Self.line(9)))
        #expect(feed.log.gap == 9)
        // lost: asked again after the retry - the history first, owed
        #expect(feed.streamEnded(2, Self.timedOut, admin: false) == .wait(2, seconds: 5))
        #expect(feed.stream == .lost && feed.step == .waiting)
        #expect(feed.retryDue(2) == .read(3))
        let recent = RecentLog(lines: (1...10).map { Self.line($0) }, last: 10, boot: "b1")
        #expect(feed.historyLanded(3, recent) == .open(4, after: 10, boot: "b1"))
        #expect(feed.historyProblem == nil && !feed.tryAgainShown)
        #expect(feed.log.lines.map(\.seq) == [10, 9, 8, 7, 6, 5, 4, 3, 2, 1])
        #expect(feed.log.gap == nil)
        // still lost until the stream opens again
        #expect(feed.stream == .lost)
        feed.opened(4)
        #expect(feed.stream == .live)
    }

    @Test func aStreamDroppedIsAskedAgainFromTheLastLineHeld() {
        var feed = EventStream.Feed()
        _ = feed.update(wanted: true, online: true)
        _ = feed.historyLanded(1, RecentLog(lines: [Self.line(1)], last: 1, boot: "b1"))
        feed.opened(2)
        feed.frame(2, Self.message(Self.line(2)))
        feed.frame(2, Self.message(Self.line(3)))
        // deadwax closed it (shutting down), or the connection dropped: the stream alone, from 3
        #expect(feed.streamEnded(2, nil, admin: false) == .wait(2, seconds: EventStream.retry))
        #expect(feed.stream == .lost)
        #expect(feed.retryDue(2) == .open(3, after: 3, boot: "b1"))
        feed.opened(3)
        #expect(feed.streamEnded(3, Self.offline, admin: false) == .wait(3, seconds: 5))
        #expect(feed.retryDue(3) == .open(4, after: 3, boot: "b1"))
        // an answer that wasn't the stream (a proxy's 502 while deadwax restarts): the history first, as the web's
        // EventSource gives up for good there and the page asks again by hand
        #expect(feed.streamEnded(4, Self.answered(502), admin: false) == .wait(4, seconds: 5))
        #expect(feed.retryDue(4) == .read(5))
        #expect(feed.historyLanded(5, RecentLog(lines: [], last: 0, boot: "b2")) == .open(6, after: 0, boot: "b2"))
        #expect(feed.streamEnded(6, EventStream.NotTheStream(contentType: "text/html"), admin: false) == .wait(6, seconds: 5))
        #expect(feed.retryDue(6) == .read(7))
        // the lines held through all of it
        #expect(feed.log.lines.map(\.seq) == [3, 2, 1])
    }

    @Test func aRefusalStopsUntilTryAgainAndASessionEndedLeavesItToTheSignIn() {
        var feed = EventStream.Feed()
        _ = feed.update(wanted: true, online: true)
        _ = feed.historyLanded(1, RecentLog(lines: [], last: 0, boot: "b1"))
        let refused = Self.answered(404, detail: "Not Found")
        #expect(feed.streamEnded(2, refused, admin: true) == .none)
        #expect(feed.step == .halted && feed.stream == .stopped)
        #expect(feed.streamProblem == EventStream.refusal(refused, admin: true))
        #expect(feed.tryAgainShown)
        #expect(feed.update(wanted: true, online: true) == .none, "not asked again by itself")
        #expect(feed.tryAgain(wanted: false) == .none)
        #expect(feed.tryAgain(wanted: true) == .read(3))
        #expect(feed.streamProblem == nil && feed.stream == .connecting)
        // a 401: halted, nothing said - the sign-in comes over the app, which calls it off, and its going asks again
        _ = feed.historyLanded(3, RecentLog(lines: [], last: 0, boot: "b1"))
        #expect(feed.streamEnded(4, Self.answered(401), admin: false) == .none)
        #expect(feed.step == .halted && feed.streamProblem == nil)
        #expect(feed.update(wanted: false, online: true) == .stop)
        #expect(feed.update(wanted: true, online: true) == .read(6))
        #expect(feed.historyFailed(6, Self.answered(401, "/interface_logs/recent"), admin: false) == .none)
        #expect(feed.step == .halted && feed.historyProblem == nil)
    }

    @Test func aForbiddenAsksMeAgainAndSaysSo() {
        var feed = EventStream.Feed()
        _ = feed.update(wanted: true, online: true)
        #expect(feed.historyFailed(1, Self.answered(403, "/interface_logs/recent"), admin: false) == .askMe)
        #expect(feed.step == .halted && feed.stream == .stopped && feed.streamProblem == EditWords.noPermission)
        _ = feed.tryAgain(wanted: true)
        _ = feed.historyLanded(2, RecentLog(lines: [], last: 0, boot: "b1"))
        #expect(feed.streamEnded(3, Self.answered(403), admin: true) == .askMe)
        #expect(feed.streamProblem == EditWords.noPermission)
    }

    @Test func aCancellationIsNeverSaidAsAFailure() {
        var feed = EventStream.Feed()
        _ = feed.update(wanted: true, online: true)
        // the history called off by the system, not the page: the stream all the same, nothing said
        #expect(feed.historyFailed(1, CancellationError(), admin: false) == .open(2, after: nil, boot: nil))
        #expect(feed.historyProblem == nil && feed.streamProblem == nil)
        feed.opened(2)
        #expect(feed.streamEnded(2, URLError(.cancelled), admin: false) == .wait(2, seconds: 5))
        #expect(feed.stream == .connecting, "never Lost for a cancellation")
        #expect(feed.historyProblem == nil && feed.streamProblem == nil)
        // the history was owed: read first
        #expect(feed.retryDue(2) == .read(3))
    }

    @Test func outOfReachTheStreamStopsAndSaysLostThenRejoins() {
        var feed = EventStream.Feed()
        _ = feed.update(wanted: true, online: true)
        _ = feed.historyLanded(1, RecentLog(lines: [Self.line(1), Self.line(2)], last: 2, boot: "b1"))
        feed.opened(2)
        #expect(feed.update(wanted: false, online: false) == .stop)
        #expect(feed.stream == .lost && feed.step == .idle)
        // back: the history read again, still "reconnecting" until the stream opens - from the last line
        #expect(feed.update(wanted: true, online: true) == .read(4))
        #expect(feed.stream == .lost)
        #expect(feed.historyLanded(4, RecentLog(lines: [Self.line(1), Self.line(2), Self.line(3)], last: 3, boot: "b1"))
                == .open(5, after: 3, boot: "b1"))
        feed.opened(5)
        #expect(feed.stream == .live)
        #expect(feed.log.lines.map(\.seq) == [3, 2, 1], "nothing twice")
        // gone with nothing out, out of reach once heard: said lost
        _ = feed.update(wanted: false, online: true)
        #expect(feed.stream == .connecting)
        _ = feed.update(wanted: false, online: false)
        #expect(feed.stream == .lost)
    }

    @Test func clearEmptiesTheViewAndNothingClearedComesBack() {
        var feed = EventStream.Feed()
        _ = feed.update(wanted: true, online: true)
        let recent = RecentLog(lines: [Self.line(1), Self.line(2)], last: 2, boot: "b1")
        _ = feed.historyLanded(1, recent)
        feed.clear()
        #expect(feed.log.lines.isEmpty && feed.log.cleared)
        #expect(EventLog.empty(feed.log) == EventLog.emptyCleared)
        _ = feed.update(wanted: false, online: true)
        _ = feed.update(wanted: true, online: true)
        _ = feed.historyLanded(4, RecentLog(lines: [Self.line(1), Self.line(2), Self.line(3)], last: 3, boot: "b1"))
        #expect(feed.log.lines.map(\.seq) == [3], "the lines since, only")
    }

    @Test func theFirstReadsSpinnerGivesWayAndTryAgainReadsAgain() {
        var feed = EventStream.Feed()
        _ = feed.update(wanted: true, online: true)
        #expect(feed.reading)
        _ = feed.historyFailed(1, Self.answered(500, "/interface_logs/recent"), admin: false)
        #expect(!feed.reading && feed.historyProblem != nil)
        // Try again while the stream is out: called off and read again
        #expect(feed.tryAgain(wanted: true) == .read(3))
        #expect(feed.streamEnded(2, nil, admin: false) == .none, "the old stream's end dropped")
        _ = feed.historyLanded(3, RecentLog(lines: [], last: 0, boot: "b1"))
        #expect(feed.historyProblem == nil)
        #expect(!feed.tryAgainShown)
        #expect(feed.tryAgain(wanted: true) == .none, "nothing to try again")
    }

    @Test func voiceOverHearsTheStreamLostAndBackNeverEveryConnecting() {
        var feed = EventStream.Feed()
        _ = feed.update(wanted: true, online: true)
        #expect(feed.announcement(inReach: true) == nil, "connecting")
        _ = feed.historyLanded(1, RecentLog(lines: [Self.line(1)], last: 1, boot: "b1"))
        feed.opened(2)
        #expect(feed.announcement(inReach: true) == nil, "the first Live")
        #expect(feed.announcement(inReach: true) == nil, "said once, whoever asks again")
        // lost, said; asked again (connecting, never said) and back: Live said
        _ = feed.streamEnded(2, nil, admin: false)
        #expect(feed.announcement(inReach: true) == EventLog.words(.lost))
        #expect(feed.announcement(inReach: true) == nil)
        _ = feed.retryDue(2)
        feed.opened(3)
        #expect(feed.announcement(inReach: true) == EventLog.words(.live))
        // refused: "Not live" and why, in ONE announcement - never the words cut off by the state after them
        let refused = Self.answered(404, detail: "Not Found")
        _ = feed.streamEnded(3, refused, admin: true)
        #expect(feed.announcement(inReach: true) == "Not live. " + EventStream.refusal(refused, admin: true))
        #expect(feed.announcement(inReach: true) == nil)
        // Try again, and live: said, after the refusal
        _ = feed.tryAgain(wanted: true)
        #expect(feed.announcement(inReach: true) == nil)
        _ = feed.historyLanded(4, RecentLog(lines: [Self.line(1)], last: 1, boot: "b1"))
        feed.opened(5)
        #expect(feed.announcement(inReach: true) == EventLog.words(.live))
        // a 403's refusal says NO_PERMISSION with it
        _ = feed.streamEnded(5, Self.answered(403), admin: false)
        #expect(feed.announcement(inReach: true) == "Not live. " + EditWords.noPermission)
    }

    @Test func voiceOverHearsTheHistorysFailureOnceAndNothingOverTheBanner() {
        var feed = EventStream.Feed()
        _ = feed.update(wanted: true, online: true)
        // the history's failure, said once; the stream opening after it isn't said over it
        _ = feed.historyFailed(1, Self.answered(500, "/interface_logs/recent"), admin: false)
        let problem = feed.historyProblem
        let said = feed.announcement(inReach: true)
        #expect(problem != nil && said == problem)
        #expect(feed.announcement(inReach: true) == nil)
        feed.opened(2)
        #expect(feed.announcement(inReach: true) == nil)
        // lost, said; asked again, the history first (owed) - failing again with the same words: nothing more; then
        // the stream back is what that failure already said ("what happens from now still shows")
        _ = feed.streamEnded(2, nil, admin: false)
        #expect(feed.announcement(inReach: true) == EventLog.words(.lost))
        _ = feed.retryDue(2)
        _ = feed.historyFailed(3, Self.answered(502, "/interface_logs/recent"), admin: false)
        #expect(feed.announcement(inReach: true) == nil, "the same failure, said already")
        feed.opened(4)
        #expect(feed.announcement(inReach: true) == EventLog.words(.live), "lost was said, and nothing since")
        // read again and landed, then failing anew: said anew
        _ = feed.update(wanted: false, online: true)
        _ = feed.update(wanted: true, online: true)
        _ = feed.historyLanded(6, RecentLog(lines: [], last: 0, boot: "b1"))
        #expect(feed.announcement(inReach: true) == nil)
        _ = feed.update(wanted: false, online: true)
        _ = feed.update(wanted: true, online: true)
        _ = feed.historyFailed(9, Self.offline, admin: false)
        let anew = feed.announcement(inReach: true)
        #expect(anew != nil && anew == feed.historyProblem && anew != problem)

        // out of reach: the app's banner says so at that moment - the stream's lost isn't said over it, nor its live
        // again after (the banner's "Back online" says that)
        var live = EventStream.Feed()
        _ = live.update(wanted: true, online: true)
        _ = live.historyLanded(1, RecentLog(lines: [Self.line(1)], last: 1, boot: "b1"))
        live.opened(2)
        #expect(live.announcement(inReach: true) == nil)
        #expect(live.update(wanted: false, online: false) == .stop)
        #expect(live.stream == .lost)
        #expect(live.announcement(inReach: false) == nil)
        _ = live.update(wanted: true, online: true)
        _ = live.historyLanded(4, RecentLog(lines: [Self.line(1)], last: 1, boot: "b1"))
        live.opened(5)
        #expect(live.announcement(inReach: true) == nil, "back online said it")
        // lost while in reach, said - then out of reach: the banner takes it from there, and live again isn't said
        _ = live.streamEnded(5, nil, admin: false)
        #expect(live.announcement(inReach: true) == EventLog.words(.lost))
        _ = live.update(wanted: false, online: false)
        #expect(live.announcement(inReach: false) == nil)
        _ = live.update(wanted: true, online: true)
        _ = live.historyLanded(7, RecentLog(lines: [Self.line(1)], last: 1, boot: "b1"))
        live.opened(8)
        #expect(live.announcement(inReach: true) == nil)
    }

    // MARK: the client's stream

    @Test func theStreamIsAskedWithTheSessionsCookieAndReadAsFrames() async throws {
        let transport = FakeLineTransport()
        transport.answer(200, "text/event-stream; charset=utf-8",
                         [":", "", "data: {\"event_type\":\"INFO\",\"event_content\":\"a\",\"seq\":5}", "", ":", ""])
        let deadwax = DeadwaxClient(server: Self.server, session: "s3ss10n", transport: transport)
        var frames: [EventStream.Frame] = []
        for try await frame in try await deadwax.logStream(after: 4, boot: "b1") { frames.append(frame) }
        #expect(frames == [.comment(""), .message(type: "message", data: "{\"event_type\":\"INFO\",\"event_content\":\"a\",\"seq\":5}", id: ""), .comment("")])
        let sent = try #require(transport.last)
        #expect(sent.method == "GET")
        #expect(sent.url.path == "/deadwax/interface_logs/interface_logs")
        #expect(sent.url.query == "after=4&boot=b1")
        #expect(sent.headers["Accept"] == "text/event-stream")
        #expect(sent.headers["Cookie"] == SessionCookie.header("s3ss10n"))
        #expect(sent.timeout == EventStream.silence)
        // from now: no query at all
        transport.answer(200, "text/event-stream", [":", ""])
        for try await _ in try await deadwax.logStream(after: nil, boot: nil) {}
        #expect(transport.last?.url.query == nil)
    }

    @Test func aRefusalIsTheRoutesAndA401TellsTheApp() async throws {
        let transport = FakeLineTransport()
        let heard = SignedOutHeard()
        let deadwax = DeadwaxClient(server: Self.server, session: "old", transport: transport) { failure, under in
            heard.hear(failure, under)
        }
        transport.answer(401, "application/json", [], body: #"{"detail":"Not signed in."}"#)
        await #expect(throws: APIFailure.answered(.init(status: 401, method: "GET", path: "/interface_logs/interface_logs",
                                                        detail: "Not signed in."))) {
            _ = try await deadwax.logStream(after: nil, boot: nil)
        }
        #expect(heard.all.count == 1 && heard.all.first?.1 == "old")
        transport.answer(403, "application/json", [], body: #"{"detail":"That needs Settings and the log."}"#)
        do {
            _ = try await deadwax.logStream(after: nil, boot: nil)
            Issue.record("expected a refusal")
        } catch {
            #expect(EventStream.End(error) == .forbidden)
        }
        #expect(heard.all.count == 1, "a 403 ends no session")
        // a 200 that isn't the stream: a proxy's page
        transport.answer(200, "text/html", ["<html>"])
        await #expect(throws: EventStream.NotTheStream(contentType: "text/html")) {
            _ = try await deadwax.logStream(after: nil, boot: nil)
        }
    }

    @Test func noAnswerAndAStreamThatFailsAreSaidAsNoAnswer() async throws {
        let transport = FakeLineTransport()
        let deadwax = DeadwaxClient(server: Self.server, transport: transport)
        transport.handle { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await deadwax.logStream(after: nil, boot: nil)
            Issue.record("expected no answer")
        } catch let failure as APIFailure {
            guard case .offline = failure else { Issue.record("\(failure)"); return }
        }
        // the stream went quiet past its wait: a timeout, so asked again
        transport.answer(200, "text/event-stream", [":", ""], ending: URLError(.timedOut))
        var frames = 0
        do {
            for try await _ in try await deadwax.logStream(after: nil, boot: nil) { frames += 1 }
            Issue.record("expected the stream to fail")
        } catch let failure as APIFailure {
            guard case .timeout = failure else { Issue.record("\(failure)"); return }
            #expect(EventStream.End(failure) == .lost)
        }
        #expect(frames == 1)
        // called off by the system: a cancellation, never a failure
        transport.answer(200, "text/event-stream", [], ending: URLError(.cancelled))
        do {
            for try await _ in try await deadwax.logStream(after: nil, boot: nil) {}
            Issue.record("expected the stream to end")
        } catch {
            #expect(error is CancellationError)
        }
        // a transport that can't read as it comes
        let (plain, _) = client()
        await #expect(throws: APIFailure.self) { _ = try await plain.logStream(after: nil, boot: nil) }
    }

    @Test func whoeverReadsTheStreamStoppingCallsTheRequestOff() async throws {
        let transport = FakeLineTransport()
        transport.answer(200, "text/event-stream", [":", ""], endless: true)
        let deadwax = DeadwaxClient(server: Self.server, transport: transport)
        let reading = Task {
            var count = 0
            for try await _ in try await deadwax.logStream(after: nil, boot: nil) { count += 1 }
            return count
        }
        for _ in 0..<400 where transport.last == nil { try await Task.sleep(for: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(20))
        #expect(transport.stops == 0, "an endless stream reads on until it's stopped")
        reading.cancel()
        _ = try? await reading.value
        for _ in 0..<200 where transport.stops == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(transport.stops == 1, "the transport's lines told to stop")
    }

    @Test func theHistoryIsAskedAsItsRoute() async throws {
        let (deadwax, transport) = client(session: "s")
        transport.answer("/deadwax/interface_logs/recent", 200,
                         #"{"lines":[{"event_type":"INFO","event_content":"a","seq":1,"time":1.5,"boot":"b"}],"last":1,"boot":"b"}"#)
        let recent = try await deadwax.recentLog()
        #expect(recent == RecentLog(lines: [LogLine(eventType: "INFO", eventContent: "a", seq: 1, time: 1.5, boot: "b")],
                                    last: 1, boot: "b"))
        #expect(transport.last?.timeout == nil, "the transport's own wait")
        #expect(transport.last?.headers["Cookie"] == SessionCookie.header("s"))
        // read loosely: a line of the wrong shape is left out, never the answer
        transport.answer("/deadwax/interface_logs/recent", 200, #"{"lines":[7,{"event_type":"INFO","event_content":"b"}],"boot":5}"#)
        let loose = try await deadwax.recentLog()
        #expect(loose == RecentLog(lines: [LogLine(eventType: "INFO", eventContent: "b")], last: 0, boot: ""))
    }

    // MARK: the real server's answers

    @Test func theRealServersAnswersReadAsThePhoneReadsThem() throws {
        let fixture = try JSONDecoder().decode(Web.self, from: Fixtures.data("log/stream.json"))
        #expect(fixture["made_from"].string?.contains("ios/scripts/log_stream_answers.py") == true)
        let boot = try #require(fixture["boot"].string)
        let recent = try JSONDecoder().decode(RecentLog.self, from: Data(fixture["recent"].string!.utf8))
        #expect(recent.boot == boot && recent.last == 4 && recent.lines.map(\.seq) == [1, 2, 3, 4])
        #expect(recent.lines.allSatisfy { $0.boot == boot && $0.time != nil })
        #expect(recent.lines[1].src == nil && recent.lines[0].src == "SLSKD")
        #expect(recent.lines[3].eventContent.contains("Sigur R\u{F3}s"))
        let cases = fixture["cases"].list
        #expect(cases.count == 4)
        var heard: [Int: LogLine] = [:]
        for row in cases {
            let name = row["name"].string!
            #expect(row["status"].int == 200, "\(name)")
            #expect(EventStream.isStream(row["headers"]["content-type"].string), "\(name) is the stream")
            #expect(row["headers"]["content-encoding"].isNull, "\(name) never gzipped")
            #expect(row["headers"]["x-accel-buffering"].string == "no")
            let frames = Self.frames(row["body"].string!)
            // ":" at once, so the stream is seen open before any line
            #expect(frames.first == .comment(""), "\(name)")
            for frame in frames.dropFirst() {
                guard case .message(let type, let data, _) = frame else { Issue.record("\(name): \(frame)"); continue }
                #expect(type == "message")
                let line = try JSONDecoder().decode(LogLine.self, from: Data(data.utf8))
                #expect(line.boot == boot && line.seq != nil, "\(name)")
                if let seq = line.seq {
                    if let had = heard[seq] { #expect(had == line, "line \(seq) the same wherever it came") }
                    heard[seq] = line
                }
            }
        }
        // the phone's own ask from the history: the first case's query, and on it only the line logged since
        var feed = EventStream.Feed()
        _ = feed.update(wanted: true, online: true)
        let opened = feed.historyLanded(1, recent)
        let from = feed.log.streamFrom
        #expect(opened == .open(2, after: from.after, boot: from.boot))
        let query = EventLog.streamQuery(after: from.after, boot: from.boot).map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        #expect(query == cases[0]["query"].string)
        feed.opened(2)
        for frame in Self.frames(cases[0]["body"].string!) { feed.frame(2, frame) }
        #expect(feed.log.lines.map(\.seq) == [5, 4, 3, 2, 1])
        // the replays: every line once, however it was asked for
        for frame in Self.frames(cases[1]["body"].string!) + Self.frames(cases[2]["body"].string!) { feed.frame(2, frame) }
        for frame in Self.frames(cases[3]["body"].string!) { feed.frame(2, frame) }
        #expect(feed.log.lines.map(\.seq) == [7, 6, 5, 4, 3, 2, 1])
        let after = try JSONDecoder().decode(RecentLog.self, from: Data(fixture["recentAfter"].string!.utf8))
        let joined = feed.log.joining(history: after)
        #expect(joined.lines.map(\.seq) == [7, 6, 5, 4, 3, 2, 1] && joined.last == 7, "nothing twice")
        // a page that held another run's lines gets them all, under their own run
        var other = EventLog.State().joining(history: RecentLog(lines: [Self.line(1, boot: "0123456789ab"),
                                                                       Self.line(2, boot: "0123456789ab"),
                                                                       Self.line(3, boot: "0123456789ab")],
                                                               last: 3, boot: "0123456789ab"))
        #expect(EventLog.streamQuery(after: other.streamFrom.after, boot: other.streamFrom.boot).map { "\($0.0)=\($0.1)" }
                    .joined(separator: "&") == cases[2]["query"].string)
        var messages = EventStream.Frames()
        for text in EventStreamTests.lines(cases[2]["body"].string!) {
            if case .message(_, let data, _)? = messages.take(text) {
                other = other.joining(try JSONDecoder().decode(LogLine.self, from: Data(data.utf8)))
            }
        }
        #expect(other.lines.count == 9 && other.boot == boot && other.last == 6)
    }
}
