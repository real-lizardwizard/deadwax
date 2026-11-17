import Foundation

// The event log on the phone (Phase 8, slice 9 - notes/ios-specs/phase8-managing.md 8; notes/ios.md "The event log on
// the phone"): what deadwax has said since it started, the last 500 lines meant for the page (src/logger.py), read once
// from `GET /interface_logs/recent` and then from the stream (EventStream.swift) - the web's app/EventLog.tsx over
// ui/src/lib/eventLog.ts and ui/src/api/logs.ts. Every rule and word here is the web's, held to it by
// Tests/DeadwaxCoreTests/Fixtures/log/log-vectors.json (ios/scripts/export-log-vectors.cjs runs the TypeScript as it is;
// ui/test/ioslog.sim.cjs checks it is current) - but for the phone's own few, said where they are: each line's identity
// (`Line.ID`), Copy (`copyText`), what VoiceOver reads (`spoken`), the first read's spinner (`reading`) and a refused
// stream's words (`EventStream`).

// MARK: the answers

/// One line of the log as deadwax sends it (src/logger.py SSEHandler; ui/src/api/logs.ts LogLine): its level, its words,
/// which part of deadwax said it, its number - rising by one per line from 1 each time deadwax starts - when the server
/// logged it, and which run of deadwax numbered it. Read loosely: a field of another type is left out, never the line.
public struct LogLine: Decodable, Sendable, Equatable {
    /// The level: INFO, WARNING, ERROR...
    public let eventType: String
    public let eventContent: String
    /// Which part of deadwax said it, when it said.
    public let src: String?
    /// Rising by one per line, from 1 each time deadwax starts; nil from a deadwax before 2.0.0-player.33.
    public let seq: Int?
    /// When the server logged it, seconds since 1970.
    public let time: Double?
    /// Which run of deadwax numbered it.
    public let boot: String?

    enum CodingKeys: String, CodingKey {
        case src, seq, time, boot
        case eventType = "event_type"
        case eventContent = "event_content"
    }

    public init(eventType: String, eventContent: String, src: String? = nil, seq: Int? = nil, time: Double? = nil,
                boot: String? = nil) {
        self.eventType = eventType
        self.eventContent = eventContent
        self.src = src
        self.seq = seq
        self.time = time
        self.boot = boot
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        eventType = fields.looseField(String.self, .eventType) ?? ""
        eventContent = fields.looseField(String.self, .eventContent) ?? ""
        src = fields.looseField(String.self, .src)
        //? `typeof line.seq === 'number'`: deadwax's numbers are whole; a fractional one is read as none
        seq = fields.looseField(Int.self, .seq)
        time = fields.looseField(Double.self, .time)
        boot = fields.looseField(String.self, .boot)
    }

    /// The line under the run a history named, unless it names its own (`{ boot: recent.boot, ...line }`).
    public func under(_ run: String) -> LogLine {
        boot == nil ? LogLine(eventType: eventType, eventContent: eventContent, src: src, seq: seq, time: time, boot: run)
            : self
    }
}

/// `GET /deadwax/interface_logs/recent` (ui/src/api/logs.ts RecentLog): the lines kept since deadwax started, oldest
/// first, the number of the last one logged (0: none yet), and this run's name.
public struct RecentLog: Decodable, Sendable, Equatable {
    public let lines: [LogLine]
    public let last: Int
    public let boot: String

    enum CodingKeys: String, CodingKey { case lines, last, boot }

    public init(lines: [LogLine], last: Int, boot: String) {
        self.lines = lines
        self.last = last
        self.boot = boot
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        lines = fields.looseList(LogLine.self, .lines) ?? []
        last = fields.looseField(Int.self, .last) ?? 0
        boot = fields.looseField(String.self, .boot) ?? ""
    }
}

// MARK: the rules

/// The event log's rules (lib/eventLog.ts) and the page's words (app/EventLog.tsx).
///
/// deadwax keeps the last 500 lines meant for the page, numbered from 1 each time it starts and named by the run
/// (`boot`). The page reads that history, then opens the stream from the last number it has, and the stream sends the
/// kept lines after it first; a stream asked for again asks from the number held. So a line can come twice - from the
/// history and the stream, or a reconnect - and is shown once: a line of this run at or below the newest number held is
/// dropped (`State.joining(_:)`). A line of another run (deadwax restarted) starts again from its own numbers. Clear
/// empties the view and keeps the number, so nothing cleared comes back from the history.
///
/// When the history couldn't be read, the stream is opened from now, and the run's first line heard leaves a GAP below
/// it: the lines of that run deadwax kept from before it, which the page never had. The next history read fills it
/// (`State.joining(history:)`), under the run's lines and above any older run's.
public enum EventLog {
    /// LOG_KEPT: the most lines the page keeps - the oldest go - as many as deadwax keeps (src/logger.py LOG_HISTORY).
    public static let kept = 500

    /// A line the page holds: what deadwax sent, and who it is to the list.
    public struct Line: Sendable, Equatable, Identifiable {
        /// A line's identity in the list: the run and the number it came with - the web's key, `${boot ?? ''}:${seq}` - and
        /// the phone's own count of lines taken, so that no two lines can ever share one (two runs' numbers can meet only
        /// if a run came back after another, which deadwax's runs, named at random, never do). Fixed as the line is
        /// taken, so it stays the same line as others come above it: never its place in the list.
        public struct ID: Hashable, Sendable {
            public let boot: String
            /// nil for a line of a deadwax before 2.0.0-player.33, which numbered none.
            public let seq: Int?
            public let taken: Int
        }

        public let id: ID
        public let line: LogLine

        public var eventType: String { line.eventType }
        public var eventContent: String { line.eventContent }
        public var src: String? { line.src }
        public var seq: Int? { line.seq }
        public var time: Double? { line.time }
        public var boot: String? { line.boot }
    }

    /// What the page holds (lib/eventLog.ts LogState).
    public struct State: Sendable, Equatable {
        /// Newest first, as the main page drew its log.
        public private(set) var lines: [Line] = []
        /// The run the newest number is of (nil: none heard yet).
        public private(set) var boot: String?
        /// The newest number heard of that run: a line at or below it is one the page has had.
        public private(set) var last = 0
        /// This run's lines below this number were never had: its first line came with no history of it.
        public private(set) var gap: Int?
        /// The view was emptied by Clear (and nothing has come since): said, not taken for a quiet deadwax.
        public private(set) var cleared = false
        /// How many lines have been taken, for each one's identity (the phone's own).
        private var taken = 0

        public init() {}

        /// The state as the vectors give it (a line's identity made as it would be taken).
        public init(lines: [LogLine], boot: String?, last: Int, gap: Int?, cleared: Bool) {
            self.boot = boot
            self.last = last
            self.gap = gap
            self.cleared = cleared
            var held: [Line] = []
            for line in lines { held.append(taking(line)) }
            self.lines = held
        }

        private mutating func taking(_ line: LogLine) -> Line {
            taken += 1
            return Line(id: Line.ID(boot: line.boot ?? "", seq: line.seq, taken: taken), line: line)
        }

        /// joinLine: one line in. A line of the run in hand at or below what the page has had is dropped; another run's
        /// starts again from its own number; a line with no number (an older deadwax) is taken.
        public func joining(_ line: LogLine) -> State {
            var next = self
            guard let seq = line.seq else {
                next.cleared = false
                next.lines = Array(([next.taking(line)] + lines).prefix(EventLog.kept))
                return next
            }
            let run = line.boot ?? boot
            if run == boot && seq <= last { return self }
            //? a run's first line: whatever of that run came before it the page hasn't had - unless it is the first
            //? line deadwax logged (joining(history:) closes the gap a history leaves: it is all there is)
            let gap = run == boot ? self.gap : seq > 1 ? seq : nil
            next.lines = Array(([next.taking(line)] + lines).prefix(EventLog.kept))
            next.boot = run
            next.last = seq
            next.gap = gap
            next.cleared = false
            return next
        }

        /// fillGap: a gap filled from the history - the run's lines below it, oldest at the bottom, under the run's own
        /// lines (the newest, at the top) and above any older run's.
        private func filling(_ recent: RecentLog) -> State {
            guard let gap, boot == recent.boot else { return self }
            var next = self
            let below = recent.lines.filter { line in line.seq.map { $0 < gap } ?? false }
            next.gap = nil
            if below.isEmpty { return next }
            let older = below.reversed().map { next.taking($0.under(recent.boot)) }
            let cut = lines.firstIndex { ($0.boot ?? boot) != boot } ?? lines.count
            next.lines = Array((lines[..<cut] + older + lines[cut...]).prefix(EventLog.kept))
            return next
        }

        /// joinHistory: the kept history (oldest first) joined - every line the page hasn't had, in order.
        public func joining(history recent: RecentLog) -> State {
            var next = filling(recent)
            for line in recent.lines { next = next.joining(line.under(recent.boot)) }
            //? lines at or below what the history ends with were all in it: nothing older is new any more, and nothing
            //? older is left to have (a gap a line of the history opened is all deadwax kept) - and a history of another
            //? run (deadwax restarted, nothing logged yet) is that run's from now
            if next.boot != recent.boot {
                next.boot = recent.boot
                next.last = recent.last
                next.gap = nil
                return next
            }
            next.last = max(next.last, recent.last)
            next.gap = nil
            return next
        }

        /// clearLog: the view emptied, the number kept - nothing cleared comes back from the history, nor anything older
        /// it never had.
        public func emptied() -> State {
            var next = self
            next.lines = []
            next.gap = nil
            next.cleared = true
            return next
        }

        /// The stream asked from where the page stands (EventLog.tsx `logStreamUrl(boot ? last : null, boot)`): the
        /// number held of the run held, or from now when no run is held.
        public var streamFrom: (after: Int?, boot: String?) { EventLog.streamFrom(last: last, boot: boot) }
    }

    /// Where the stream is asked from (EventLog.tsx `logStreamUrl(boot ? last : null, boot)`): the number held of the
    /// run held, or from now when no run is held (none, or one named "").
    public static func streamFrom(last: Int, boot: String?) -> (after: Int?, boot: String?) {
        guard let boot, !boot.isEmpty else { return (nil, boot) }
        return (last, boot)
    }

    /// The stream's query (api/logs.ts logStreamUrl): the kept lines after `last` of run `boot` sent first - both, or
    /// neither (from now only).
    public static func streamQuery(after last: Int?, boot: String?) -> [(String, String)] {
        guard let last, let boot, !boot.isEmpty else { return [] }
        return [("after", String(last)), ("boot", boot)]
    }

    // MARK: how a line is drawn

    /// levelOf: errors red, warnings amber, the rest plain.
    public enum Level: String, Sendable, Equatable {
        case error, warning, info
    }

    public static func level(_ type: String) -> Level {
        let upper = type.uppercased()
        if upper == "ERROR" || upper == "CRITICAL" { return .error }
        if upper == "WARNING" || upper == "WARN" { return .warning }
        return .info
    }

    /// lineTime: the time a line was logged, as the main page drew it - HH:MM:SS on this device's clock
    /// (`new Date(time * 1000).toTimeString().slice(0, 8)`), "" with no time.
    public static func time(_ time: Double?, in zone: TimeZone = .current) -> String {
        guard let time, time.isFinite else { return "" }
        //? a Date's time is whole milliseconds, cut toward zero (TimeClip); past ±8.64e15 ms it is no date at all
        let ms = (time * 1000).rounded(.towardZero)
        guard abs(ms) <= 8.64e15 else { return "Invalid " }
        let seconds = (ms / 1000).rounded(.down)
        let local = Int(seconds) + zone.secondsFromGMT(for: Date(timeIntervalSince1970: seconds))
        let day = ((local % 86_400) + 86_400) % 86_400
        return two(day / 3600) + ":" + two(day % 3600 / 60) + ":" + two(day % 60)
    }

    public static func time(_ line: Line, in zone: TimeZone = .current) -> String { time(line.time, in: zone) }

    private static func two(_ number: Int) -> String { number < 10 ? "0\(number)" : String(number) }

    // MARK: the page's words

    /// The page's title (EventLog.tsx's large title), and Manage's row.
    public static let title = "Event log"
    /// What the page is (EventLog.tsx `.app-log-line`).
    public static let pageLine = "What deadwax has said since it started - the last 500 lines - newest first. Clear empties "
        + "this view only."
    /// Clear, in the bar: the view emptied, nothing on the server.
    public static let clear = "Clear"
    /// The list, read by VoiceOver (EventLog.tsx's `aria-label`).
    public static let listLabel = "Event log, newest first"
    /// EMPTY_WORDS: nothing yet, or emptied by Clear (lines were logged; deadwax still has them).
    public static let emptyNever = "Nothing logged yet."
    public static let emptyCleared = "Cleared. New lines show here as deadwax logs them."

    public static func empty(_ state: State) -> String { state.cleared ? emptyCleared : emptyNever }

    /// What the history couldn't be had says - the stream still says what happens from now.
    public static let historyFailed = "Couldn't load the lines deadwax kept - what happens from now still shows."

    /// The history read failed (EventLog.tsx's `sayError(reason, '', { failed, retry: true })`): in a listener's words,
    /// the page's own Try again beside it.
    public static func historyFailure(_ error: any Error, admin: Bool) -> String {
        ErrorWords.notice("", error, admin: admin, failed: historyFailed, retry: true)
    }

    /// The phone's own: the first history read is out and nothing has come yet - said, rather than "Nothing logged yet."
    /// while it isn't known.
    public static let reading = "Reading what deadwax kept…"
    /// The phone's own: a long press offers it (the web has none).
    public static let copy = "Copy"
    public static let tryAgain = "Try again"

    /// The phone's own: what Copy puts on the clipboard - the line as drawn, time, level, part and words.
    public static func copyText(_ line: Line, in zone: TimeZone = .current) -> String {
        [time(line, in: zone), line.eventType, line.src ?? "", line.eventContent].filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The phone's own: what VoiceOver reads of a line, once - its words, then its level, time and part.
    public static func spoken(_ line: Line, in zone: TimeZone = .current) -> String {
        var parts = [line.eventContent]
        if !line.eventType.isEmpty { parts.append(line.eventType.lowercased()) }
        let at = time(line, in: zone)
        if !at.isEmpty { parts.append(at) }
        if let src = line.src, !src.isEmpty { parts.append(src) }
        return parts.joined(separator: ", ")
    }

    // MARK: the stream's state

    /// Where the stream stands, said in one line under the bar - never a line of the log itself. `connecting`, `live` and
    /// `lost` are the web's; `stopped` is the phone's own: deadwax refused the stream (a 4xx), and it isn't asked again
    /// until Try again.
    public enum StreamState: String, Sendable, Equatable {
        case connecting, live, lost, stopped
    }

    /// STREAM_WORDS, and the phone's own for `stopped`.
    public static func words(_ state: StreamState) -> String {
        switch state {
        case .connecting: return "Connecting…"
        case .live: return "Live"
        //? (2.0.8, UX batch 5) it was "The stream was lost - trying again"
        case .lost: return "Lost the live feed - reconnecting…"
        case .stopped: return "Not live"
        }
    }

    // MARK: who may

    /// Who opens the page (App.tsx `<EventLog allowed={perms.has('server')}`): Settings and the log - an admin has it,
    /// and everyone with logins off. The server refuses for itself (403) whatever this says.
    public static func allowed(_ access: Access) -> Bool { access.can(.server) }
}
