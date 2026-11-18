import Foundation

// The event log's stream on the phone (Phase 8, slice 9 - notes/ios-specs/phase8-managing.md 8; notes/ios.md "The event
// log on the phone"): `GET /deadwax/interface_logs/interface_logs?after=&boot=` is Server-Sent Events (src/routes/
// interface_logs.py: ":" at once, the kept lines after `after` of run `boot`, then `data: {json}` per line as it is
// logged and ":" every 15 s while nothing is). The web reads it with the browser's EventSource; the phone has none, so
// this is what EventSource does, pure: the body's bytes as lines (`Lines`), the lines as frames (`Frames` - WHATWG HTML's
// "interpreting an event stream"), and the page's whole life with the history and the stream (`Feed`) - when each is
// asked, what an answer does to the lines, and when a stream lost is asked again. The App's transport only hands the
// bytes on (URLSessionTransport `lines(for:)`), and EventLogModel only carries out what Feed says.

/// The event log's stream, read.
public enum EventStream {
    /// src/routes/interface_logs.py: a keepalive (":") every 15 s while nothing is logged - `asyncio.wait_for(...,
    /// timeout=15)`, held to it by tests/test_ios_event_log.py.
    public static let keepalive: Double = 15
    /// How long the stream may say nothing at all before it's taken as lost: three keepalives. The stream has no wait
    /// over all - it's meant never to end - so this is URLSession's wait between bytes (Routes.timeouts[logStream]), and
    /// a connection gone silent (WireGuard dropped with no word) is noticed within it rather than never.
    public static let silence: Double = 45
    /// STREAM_RETRY_MS: how long after the stream is lost it's asked for again - from the last line held.
    public static let retry: Double = 5

    /// The phone's own: what didn't work, when deadwax refused the stream (a 4xx with no words of its own).
    public static let refusedFailed = "Couldn't open the live feed."

    /// deadwax refused the stream (a 4xx): its own words as they came, as every managing page says them, else in a
    /// listener's words - a 403 a Managing page's NO_PERMISSION.
    public static func refusal(_ error: any Error, admin: Bool) -> String {
        EditWords.said(error, failed: refusedFailed, admin: admin)
    }

    /// An answer is the stream when it says it is (EventSource's check): `text/event-stream`, parameters allowed.
    public static func isStream(_ contentType: String?) -> Bool {
        guard let contentType else { return false }
        let essence = contentType.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return essence.trimmingCharacters(in: .whitespaces).lowercased() == "text/event-stream"
    }

    /// An answer that wasn't the stream: a 200 that isn't an event stream - a reverse proxy's page while deadwax
    /// restarts. Asked again, as a stream lost is.
    public struct NotTheStream: Error, Sendable, Equatable {
        public let contentType: String?

        public init(contentType: String?) {
            self.contentType = contentType
        }
    }

    // MARK: the body, as lines

    /// The body's bytes as lines, each without its ending - LF, CR or CRLF, a CRLF split across two reads included -
    /// blank lines kept (they end an event: `URLSession.AsyncBytes.lines` drops them, so it can't be used). A byte order
    /// mark at the stream's start is dropped; a line past `most` bytes is dropped whole, so a stream that never ends a
    /// line never holds more than that.
    public struct Lines: Sendable {
        public static let most = 1 << 20

        private var pending: [UInt8] = []
        private var afterCR = false
        private var started = false
        private var over = false

        public init() {}

        /// One byte in: the line it ends, if it ends one.
        public mutating func feed(_ byte: UInt8) -> String? {
            if afterCR {
                afterCR = false
                //? CRLF: the CR ended the line already
                if byte == 0x0A { return nil }
            }
            if byte == 0x0A || byte == 0x0D {
                afterCR = byte == 0x0D
                return take()
            }
            if over { return nil }
            if pending.count >= Self.most {
                over = true
                pending = []
                return nil
            }
            pending.append(byte)
            return nil
        }

        /// Bytes in: every line they end.
        public mutating func feed<Bytes: Sequence>(_ bytes: Bytes) -> [String] where Bytes.Element == UInt8 {
            var lines: [String] = []
            for byte in bytes {
                if let line = feed(byte) { lines.append(line) }
            }
            return lines
        }

        private mutating func take() -> String? {
            defer { pending = [] }
            if over {
                over = false
                return nil
            }
            var bytes = pending[...]
            if !started {
                started = true
                if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
            }
            //? UTF-8, a byte that isn't read as U+FFFD (the spec's "UTF-8 decode")
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    // MARK: the lines, as frames

    /// What a stream says.
    public enum Frame: Sendable, Equatable {
        /// A comment (a line beginning ":"): deadwax's first frame, and every keepalive - the stream is there.
        case comment(String)
        /// An event, dispatched at the blank line that ends it: its type ("message" unless an `event:` line named
        /// another), its data (each `data:` line's, joined by newlines) and the last id the stream gave.
        case message(type: String, data: String, id: String)
    }

    /// The lines as frames, as EventSource reads them (WHATWG HTML 9.2.6, "interpreting an event stream"): a line that
    /// begins ":" is a comment; `field: value` (one space after the colon dropped) or a field alone; `data` lines
    /// gathered, `event` naming the type, `id` kept, `retry` noted; a blank line dispatches what was gathered, if any.
    public struct Frames: Sendable {
        private var data = ""
        private var type = ""
        private var lastID = ""
        /// The reconnection time a `retry:` line set, in milliseconds - deadwax sends none; the phone waits `retry`.
        public private(set) var retry: Int?

        public init() {}

        /// One line in: the frame it makes, if it makes one.
        public mutating func take(_ line: String) -> Frame? {
            let scalars = line.unicodeScalars
            if scalars.isEmpty {
                defer {
                    data = ""
                    type = ""
                }
                guard !data.isEmpty else { return nil }
                var text = data
                if text.unicodeScalars.last == "\n" { text.unicodeScalars.removeLast() }
                return .message(type: type.isEmpty ? "message" : type, data: text, id: lastID)
            }
            if scalars.first == ":" { return .comment(String(scalars.dropFirst())) }
            let field: String
            var value = ""
            if let colon = scalars.firstIndex(of: ":") {
                field = String(scalars[..<colon])
                var rest = scalars[scalars.index(after: colon)...]
                if rest.first == " " { rest = rest.dropFirst() }
                value = String(rest)
            } else {
                field = line
            }
            switch field {
            case "event":
                type = value
            case "data":
                data += value + "\n"
            case "id":
                if !value.unicodeScalars.contains("\u{0}") { lastID = value }
            case "retry":
                if !value.isEmpty, value.unicodeScalars.allSatisfy({ $0.value >= 0x30 && $0.value <= 0x39 }) {
                    retry = Int(value)
                }
            default:
                break
            }
            return nil
        }
    }

    // MARK: how an ask ended

    /// How an ask - the history, or the stream - ended without what it asked for.
    public enum End: Sendable, Equatable {
        /// Called off: the page's own stop (never seen - its ask is stale by then), or the system's. Never an error.
        case cancelled
        /// A 401: the session ended - the sign-in comes over the app, as a 401 anywhere brings it.
        case signedOut
        /// A 403: Settings and the log taken away since /me last said.
        case forbidden
        /// Another 4xx: deadwax refused, and asking again won't change it.
        case refused
        /// No answer, a timeout, a 5xx, an answer that isn't the stream, or the stream ended: asked again.
        case lost

        public init(_ error: any Error) {
            if APIFailure.isCancellation(error) {
                self = .cancelled
                return
            }
            if let failure = error as? APIFailure, let answer = failure.answer {
                if failure.isSignedOut {
                    self = .signedOut
                } else if answer.status == 403 {
                    self = .forbidden
                } else if (400..<500).contains(answer.status) {
                    self = .refused
                } else {
                    self = .lost
                }
                return
            }
            self = .lost
        }
    }

    // MARK: the page's life

    /// Everything the page decides about the history and the stream (EventLog.tsx's effect, and what EventSource does by
    /// itself): the lines held, where the stream stands, what went wrong, and what to ask next. Each ask - the history,
    /// the stream - takes the next number as it's made, before anything is sent, and an answer for any but the newest is
    /// dropped: a stop, a page gone, a Try again all make what is out stale at once.
    ///
    /// - The page wanted (it shows, the app in front, deadwax in reach, Settings and the log, no sign-in over the app): the
    ///   history (`GET /recent`), then the stream from the last line held. The history failing says so (Try again beside
    ///   it) and the stream opens all the same, from the last line held or from now.
    /// - The stream lost - no answer, a timeout, a 5xx, an answer that isn't it, or it ended: "Lost the live feed -
    ///   reconnecting…", and asked again after `retry`, from the last line held (the history first when it is owed: its
    ///   last read failed, or the lines have a gap it fills).
    /// - Refused (a 4xx): not asked again until Try again, or until it's wanted again after it wasn't (the page shown
    ///   again, the app back in front, deadwax back in reach, Now Playing put away); a 401 leaves it to the sign-in, a
    ///   403 asks /me again.
    /// - Not wanted any more - the page gone, the app to the background, deadwax out of reach, the sign-in or Now Playing
    ///   over the app - what is out is called off (never said as a failure). Wanted again, the history is read again and
    ///   the stream rejoined by number: nothing twice, nothing cleared back.
    /// - Nothing answering at all: the app's Reachability probes deadwax and, finding it out of reach, makes the stream
    ///   no longer wanted - usually before `retry` is up - and it's asked again once deadwax is back. An answer that
    ///   isn't the stream (a 5xx, another page), with deadwax in reach, is asked again every `retry` while it lasts.
    public struct Feed: Sendable, Equatable {
        public enum Step: Sendable, Equatable {
            /// Nothing out.
            case idle
            /// The history is out.
            case reading
            /// The stream is asked for, or open.
            case streaming
            /// The stream was lost: asked again after `retry`.
            case waiting
            /// Refused: nothing asked until Try again, or until it's wanted again after it wasn't.
            case halted
        }

        /// What the App does next.
        public enum Action: Sendable, Equatable {
            case none
            /// Call off what is out.
            case stop
            /// Read the history, as this ask.
            case read(Int)
            /// Open the stream from the line after `after` of run `boot` (both or neither), as this ask.
            case open(Int, after: Int?, boot: String?)
            /// Wait this long, then say `retryDue` with this ask.
            case wait(Int, seconds: Double)
            /// A 403: ask /me again, so the page draws what this person may do now.
            case askMe
        }

        /// The lines held.
        public private(set) var log = EventLog.State()
        /// Where the stream stands.
        public private(set) var stream: EventLog.StreamState = .connecting
        public private(set) var step: Step = .idle
        /// The history couldn't be read: said over the lines, with Try again.
        public private(set) var historyProblem: String?
        /// The stream was refused: said, with Try again.
        public private(set) var streamProblem: String?
        /// Something has answered for this person - the history, or the stream opened: until then, out of reach, the
        /// page says it needs deadwax.
        public private(set) var heard = false
        /// The newest ask's number.
        public private(set) var ask = 0
        /// The history is owed: its last read failed (or was called off) - the next ask after a loss reads it first.
        private var owed = false
        /// (Phase 8, slice 10's review) Halted by a 401: the session's, so the session moving lets it go (`sessionMoved`).
        private var haltedSignedOut = false
        /// What VoiceOver was last left knowing (`announcement`): the stream's state and the history's failure as they
        /// stood, and whether it was told the stream was lost or refused - so live again is said only after that.
        private var toldStream: EventLog.StreamState = .connecting
        private var toldProblem: String?
        private var toldTrouble = false

        public init() {}

        /// The first history read is out and nothing has come yet: "Reading what deadwax kept…", never "Nothing logged
        /// yet." while it isn't known - and once it fails, the failure and Try again, never a spinner for good.
        public var reading: Bool { step == .reading && !heard && historyProblem == nil && log.lines.isEmpty }

        /// Try again is offered: the history failed, or the stream was refused.
        public var tryAgainShown: Bool { historyProblem != nil || step == .halted }

        /// What the page wants now. Wanted and nothing out: the history read. Not wanted and something out: called off -
        /// the line saying "Lost the live feed - reconnecting…" while deadwax is out of reach (it is asked again once it's
        /// back), and "Connecting…" for the next time the page shows.
        public mutating func update(wanted: Bool, online: Bool) -> Action {
            if wanted {
                guard step == .idle else { return .none }
                return begin()
            }
            guard step != .idle else {
                if !online && stream != .lost && heard { stream = .lost }
                return .none
            }
            ask += 1
            step = .idle
            stream = online ? .connecting : .lost
            return .stop
        }

        /// Try again (beside the history's failure, or a refused stream's): what is out called off, and the history read
        /// again, then the stream.
        public mutating func tryAgain(wanted: Bool) -> Action {
            guard wanted, tryAgainShown else { return .none }
            stream = .connecting
            return begin()
        }

        private mutating func begin() -> Action {
            ask += 1
            step = .reading
            haltedSignedOut = false
            //? lost stays lost until the stream opens again ("reconnecting…" is what happens); a page shown afresh connects
            if stream != .lost { stream = .connecting }
            streamProblem = nil
            return .read(ask)
        }

        /// (Phase 8, slice 10's review) The session in hand moved - Change password re-keyed it, or the same person signed
        /// in again: whatever is out went under the old one (deadwax answers its cookie 401 from the move on), and a halt
        /// for a 401 was the old one's. So it is all asked again under the new one, the history first - nothing twice,
        /// nothing cleared back. A refusal or a 403 stays halted until Try again; nothing out and nothing halted is
        /// `update`'s.
        public mutating func sessionMoved(wanted: Bool, online: Bool) -> Action {
            switch step {
            case .idle:
                return update(wanted: wanted, online: online)
            case .halted:
                guard haltedSignedOut else { return .none }
            case .reading, .streaming, .waiting:
                break
            }
            let wasOut = step != .halted
            step = .idle
            haltedSignedOut = false
            if wanted { return begin() }
            guard wasOut else { return .none }
            ask += 1
            stream = online ? .connecting : .lost
            return .stop
        }

        /// The history landed: joined (only what the page hasn't had), then the stream from where it ends.
        public mutating func historyLanded(_ asked: Int, _ recent: RecentLog) -> Action {
            guard asked == ask, step == .reading else { return .none }
            log = log.joining(history: recent)
            historyProblem = nil
            owed = false
            heard = true
            return open()
        }

        /// The history couldn't be had: the stream still says what happens from now (and the next history read fills in
        /// what this one would have) - unless the session ended (the sign-in comes) or Settings and the log went.
        public mutating func historyFailed(_ asked: Int, _ error: any Error, admin: Bool) -> Action {
            guard asked == ask, step == .reading else { return .none }
            switch End(error) {
            case .signedOut:
                step = .halted
                haltedSignedOut = true
                return .none
            case .forbidden:
                return forbidden()
            case .cancelled:
                //? called off by the system, not by the page (its stop makes the ask stale first): the stream as after
                //? any history not had, with nothing said
                owed = true
                return open()
            case .refused, .lost:
                historyProblem = EventLog.historyFailure(error, admin: admin)
                owed = true
                return open()
            }
        }

        private mutating func open() -> Action {
            ask += 1
            step = .streaming
            let from = log.streamFrom
            return .open(ask, after: from.after, boot: from.boot)
        }

        private mutating func forbidden() -> Action {
            step = .halted
            stream = .stopped
            streamProblem = EditWords.noPermission
            return .askMe
        }

        /// The stream opened (a 200 that is the stream): Live.
        public mutating func opened(_ asked: Int) {
            guard asked == ask, step == .streaming else { return }
            stream = .live
            heard = true
            streamProblem = nil
        }

        /// A frame came: a message's line joined (one that isn't a line - not JSON, not an object - is left out, as the
        /// web's JSON.parse failing leaves it); a comment says only that the stream is there.
        public mutating func frame(_ asked: Int, _ frame: Frame) {
            guard asked == ask, step == .streaming else { return }
            guard case .message(let type, let data, _) = frame, type == "message",
                  let line = try? JSONDecoder().decode(LogLine.self, from: Data(data.utf8)) else { return }
            log = log.joining(line)
        }

        /// The stream ended: `error` nil when deadwax closed it (a stop of its own: shutting down, or the reader no
        /// longer let in - the next ask finds out which). Lost: asked again after `retry`. Refused: not asked again.
        public mutating func streamEnded(_ asked: Int, _ error: (any Error)?, admin: Bool) -> Action {
            guard asked == ask, step == .streaming else { return .none }
            let end = error.map(End.init) ?? .lost
            switch end {
            case .cancelled:
                //? not the page's own (that makes the ask stale first): asked again as after a loss, but never said as one
                step = .waiting
                if stream != .lost { stream = .connecting }
                return .wait(ask, seconds: EventStream.retry)
            case .signedOut:
                step = .halted
                haltedSignedOut = true
                return .none
            case .forbidden:
                return forbidden()
            case .refused:
                step = .halted
                stream = .stopped
                streamProblem = error.map { EventStream.refusal($0, admin: admin) }
                return .none
            case .lost:
                //? an answer that wasn't the stream - a 5xx, a proxy's page - is where the web's EventSource gives up
                //? for good (CLOSED) and EventLog.tsx asks again by hand, the history first; a connection dropped is
                //? where EventSource asks again by itself, the stream alone
                if let error, (error as? APIFailure)?.answer != nil || error is NotTheStream { owed = true }
                step = .waiting
                stream = .lost
                return .wait(ask, seconds: EventStream.retry)
            }
        }

        /// The wait after a loss is over: the stream again from the last line held - the history first when it's owed.
        public mutating func retryDue(_ asked: Int) -> Action {
            guard asked == ask, step == .waiting else { return .none }
            if owed || log.gap != nil {
                ask += 1
                step = .reading
                return .read(ask)
            }
            return open()
        }

        /// Clear: the view emptied, nothing on the server.
        public mutating func clear() {
            log = log.emptied()
        }

        /// What VoiceOver hears now, if anything (the phone's own; the web's line is a live region, read at every change),
        /// asked after each change is carried out - ONE announcement for what changed since it was last asked, as a new
        /// one cuts off the one before:
        /// - the history's failure, when it's new (what it says - "what happens from now still shows" - covers the stream
        ///   that opens after it, so live isn't said on top of it);
        /// - the stream lost; refused, with why in the same breath ("Not live. Couldn't open the live feed."), never the
        ///   words then "Not live" over them; and live again after either was said - never the first Live, nor every
        ///   Connecting….
        ///
        /// Out of reach (`inReach` false) nothing: the app's banner says deadwax has gone at that very moment
        /// (Reachability), and its "Back online" says it's back - so the stream's lost isn't said over it, nor its live
        /// again after.
        public mutating func announcement(inReach: Bool) -> String? {
            let (oldStream, oldProblem) = (toldStream, toldProblem)
            toldStream = stream
            toldProblem = historyProblem
            guard inReach else {
                toldTrouble = false
                return nil
            }
            if let problem = historyProblem, problem != oldProblem {
                toldTrouble = false
                return problem
            }
            guard stream != oldStream else { return nil }
            switch stream {
            case .lost:
                toldTrouble = true
                return EventLog.words(.lost)
            case .stopped:
                toldTrouble = true
                guard let why = streamProblem, !why.isEmpty else { return EventLog.words(.stopped) }
                return EventLog.words(.stopped) + ". " + why
            case .live:
                guard toldTrouble else { return nil }
                toldTrouble = false
                return EventLog.words(.live)
            case .connecting:
                return nil
            }
        }
    }
}

// MARK: the client

extension DeadwaxClient {
    /// `GET /deadwax/interface_logs/recent`: the lines deadwax kept since it started, oldest first, the number of the
    /// last one, and the run's name.
    public func recentLog() async throws -> RecentLog {
        try await call(Routes.recentLog)
    }

    /// The event log's stream (`GET /deadwax/interface_logs/interface_logs`, the kept lines after `after` of run `boot`
    /// first - both, or neither for what is logged from now): its frames as they come, until deadwax ends it, it fails or
    /// the task reading it is cancelled (which calls the request off). Refused (any status but 200) as every route's
    /// refusal is - a 401 telling the app the session has ended; a 200 that isn't an event stream is `NotTheStream`.
    public func logStream(after last: Int?, boot: String?) async throws -> AsyncThrowingStream<EventStream.Frame, any Error> {
        guard let streaming = transport as? any HTTPLineTransport else {
            throw APIFailure.other("The app can't read deadwax's stream through this connection.")
        }
        var built = request(Routes.logStream, query: EventLog.streamQuery(after: last, boot: boot))
        built.headers["Accept"] = "text/event-stream"
        let opened: HTTPLines
        do {
            opened = try await streaming.lines(for: built)
        } catch {
            if APIFailure.isCancellation(error) { throw CancellationError() }
            throw APIFailure.noAnswer(error, to: built, server: server, device: device)
        }
        guard opened.response.status == 200 else { throw failure(opened.response, to: built) }
        let type = opened.response.header("Content-Type")
        guard EventStream.isStream(type) else { throw EventStream.NotTheStream(contentType: type) }
        let server = self.server
        let device = self.device
        let sent = built
        let lines = opened.lines
        return AsyncThrowingStream { (continuation: AsyncThrowingStream<EventStream.Frame, any Error>.Continuation) in
            let reading = Task {
                var frames = EventStream.Frames()
                do {
                    for try await line in lines {
                        if let frame = frames.take(line) { continuation.yield(frame) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIFailure.isCancellation(error)
                                        ? CancellationError() : APIFailure.noAnswer(error, to: sent, server: server, device: device))
                }
            }
            continuation.onTermination = { _ in reading.cancel() }
        }
    }
}
