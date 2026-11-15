import Foundation

// What the app watches, when it asks for the downloads, the Done rows' looks and what a screen reader hears
// (phase6-get-requests.md 2.5-2.7, 2.12): ui/src/lib/requestsView.ts's watchingOf, stallsOn, asksAgain, changes,
// focusAfterGone and doneLooks, held to them by Fixtures/requests/requests-vectors.json; useDownloadJobs.ts's cadences,
// with the phone's own rules beside them (RequestsPolling); and You's Confirm before cancelling.

/// What the app is looking at, as far as downloads go: Requests' root (whose poll is fast), Home (the web's; the phone
/// has none), another tab or page, or nothing - the app in the background.
public enum Watching: String, Sendable, Equatable, CaseIterable {
    case requests, home, other, hidden
}

public enum RequestsWatch {
    /// `watchingOf`: a tab counts only at its root, and only with Now Playing not over it; nothing while the app is in
    /// the background.
    public static func watching(shown: Bool, tab: String, depth: Int, sheetOpen: Bool) -> Watching {
        if !shown { return .hidden }
        if depth > 0 || sheetOpen { return .other }
        return tab == "requests" ? .requests : tab == "home" ? .home : .other
    }

    /// `stallsOn`: the last look failed while something was on its way, and the app is on screen - keep asking at
    /// Requests' pace until an answer comes, so the badge doesn't freeze on one blip.
    public static func stallsOn(_ watching: Watching, error: String?, arriving: Int) -> Bool {
        (watching == .home || watching == .other) && error != nil && arriving > 0
    }

    /// `asksAgain`: one look as Home comes into view, or the app back from the background on any tab. Requests polls by
    /// itself, and its `open` turning off asked once already.
    public static func asksAgain(_ before: Watching, _ now: Watching) -> Bool {
        if now == before || now == .hidden || now == .requests || before == .requests { return false }
        return now == .home || before == .hidden
    }

    /// libraryEvents.ts `statusesOf`: each job's status, by id - what the next look is compared with.
    public static func statuses(_ jobs: [DownloadJob]) -> [Int: String] {
        var out: [Int: String] = [:]
        for job in jobs { out[job.id] = job.status }
        return out
    }

    /// libraryEvents.ts `newlyOrganized`: the jobs this look saw filed since the last one (`previous`) - none on the
    /// first look, so what was filed before the app asked is never news.
    public static func newlyFiled(_ previous: [Int: String]?, _ jobs: [DownloadJob]) -> [Int] {
        guard let previous else { return [] }
        return jobs.filter { $0.status == "organized" && previous[$0.id] != "organized" }.map { $0.id }
    }
}

/// The one poll's pace (useDownloadJobs.ts), with the phone's own rules (phase6-get-requests.md 2.5, question 3): fast
/// while Requests' root shows, faster than the background while an album is being filed, slow while anything is on its
/// way - and never while deadwax can't be reached, nor while the app is in the background.
public enum RequestsPolling {
    /// POLL_OPEN_MS, POLL_FILING_MS, POLL_BACKGROUND_MS - in seconds.
    public static let openSeconds: Double = 0.5
    public static let filingSeconds: Double = 1
    public static let backgroundSeconds: Double = 5

    /// How long until the next look after one that saw `hasActive` (an active job) and `filing` (one being filed), or
    /// nil for none - until something asks again. `open`: Requests' root shows, or a failed look stalls (`stallsOn`).
    public static func delay(open: Bool, hasActive: Bool, filing: Bool, online: Bool, watching: Watching) -> Double? {
        guard online, watching != .hidden else { return nil }
        if !hasActive && !open { return nil }
        return open ? openSeconds : filing ? filingSeconds : backgroundSeconds
    }

    /// Whether a look may go out at all now.
    public static func asks(online: Bool, watching: Watching) -> Bool {
        online && watching != .hidden
    }
}

/// What a screen reader hears as the board changes (`changes`), and where a keyboard's focus would go from a card that
/// went (`focusAfterGone`).
public enum RequestChanges {
    public struct Said: Sendable, Equatable {
        public let said: String
        public let moved: [String]
        /// Every row of `before` that `now` hasn't got, in `before`'s order, with the row focus would go to.
        public let gone: [(key: String, focus: String?)]

        public static func == (a: Said, b: Said) -> Bool {
            a.said == b.said && a.moved == b.moved && a.gone.map { $0.key } == b.gone.map { $0.key }
                && a.gone.map { $0.focus } == b.gone.map { $0.focus }
        }
    }

    static func sectionWords(_ row: RequestRow) -> String {
        switch row.section {
        case .downloading: return "downloading"
        case .waiting: return "waiting"
        case .attention:
            if let reason = row.reason, !reason.isEmpty { return "needs attention: \(reason)" }
            return "needs attention"
        case .done: return row.line
        }
    }

    /// What changed between two looks that a screen reader should hear, which rows moved to another heading, and which
    /// went.
    public static func changes(before: RequestsView?, now: RequestsView) -> Said {
        guard let before else { return Said(said: "", moved: [], gone: []) }
        var was: [String: RequestRow] = [:]
        var wasOrder: [String] = []
        for section in RequestSection.allCases {
            for row in before.rows(section) {
                if was[row.key] == nil { wasOrder.append(row.key) }
                was[row.key] = row
            }
        }
        var phrases: [String] = []
        var moved: [String] = []
        var still = Set<String>()
        for section in RequestSection.allCases {
            for row in now.rows(section) {
                still.insert(row.key)
                guard let previous = was[row.key] else { continue }
                if previous.section != row.section {
                    moved.append(row.key)
                    phrases.append("\(row.title): \(sectionWords(row))")
                } else if let problem = row.problem, !problem.isEmpty, problem != previous.problem {
                    phrases.append("\(row.title): \(problem)")
                } else if row.busy && !previous.busy {
                    let label = row.askAgain?.label == RequestWords.tryingSame ? "trying again\u{2026}" : "trying another source\u{2026}"
                    phrases.append("\(row.title): \(label)")
                } else if row.cancel == .cancelling && previous.cancel != .cancelling {
                    phrases.append("\(row.title): \(row.cancelWords.leaves ? "leaving\u{2026}" : "cancelling\u{2026}")")
                }
            }
        }
        var gone: [(key: String, focus: String?)] = []
        for key in wasOrder where !still.contains(key) {
            guard let previous = was[key] else { continue }
            gone.append((key, focusAfterGone(before: before, now: now, key: key)))
            if previous.cancel == .cancelling && previous.cancelWords.leaves {
                phrases.append("\(previous.title): left - it carries on for whoever else asked")
            }
        }
        return Said(said: phrases.joined(separator: ". "), moved: moved, gone: gone)
    }

    /// Where focus goes when the row `key` - in `before`, not in `now` - had it: the card after it under its heading,
    /// still there; else the one before it; else the first card on the page; nil with none left.
    public static func focusAfterGone(before: RequestsView, now: RequestsView, key: String) -> String? {
        var present = Set<String>()
        for section in RequestSection.allCases { for row in now.rows(section) { present.insert(row.key) } }
        for section in RequestSection.allCases {
            let rows = before.rows(section)
            guard let at = rows.firstIndex(where: { $0.key == key }) else { continue }
            if let after = rows[(at + 1)...].first(where: { present.contains($0.key) }) { return after.key }
            if let earlier = rows[..<at].reversed().first(where: { present.contains($0.key) }) { return earlier.key }
        }
        for section in RequestSection.allCases {
            if let first = now.rows(section).first { return first.key }
        }
        return nil
    }
}

/// The Done rows' albums looked for ahead of a tap (`doneLooks`), so a ▶ plays at once - Navidrome given time to scan
/// what a download filed, a look that found nothing tried again backing off, songs asked again when they may be out
/// of date.
public enum DoneLooks {
    /// How many Done rows have their album asked for ahead (Requests.tsx DONE_PREFETCHED).
    public static let prefetched = 5
    /// How long after a Done row first shows Navidrome is taken to have scanned what it filed.
    public static let scanSettleMs: Double = 10_000
    /// Songs asked longer ago than this before the tab last came into view are asked again.
    public static let freshMs: Double = 30_000
    /// A look that found no album: the next after this, doubling, to retryMaxMs.
    public static let retryMs: Double = 5_000
    public static let retryMaxMs: Double = 60_000

    /// A Done row's release, and when it first showed as done (this phone's clock, ms; 0 for one already done in the
    /// first answer).
    public struct Row: Sendable, Equatable {
        public let release: String
        public let since: Double

        public init(release: String, since: Double) {
            self.release = release
            self.since = since
        }
    }

    public struct Miss: Sendable, Equatable {
        public var count: Int
        public var at: Double

        public init(count: Int, at: Double) {
            self.count = count
            self.at = at
        }
    }

    /// What the tab holds of its Done rows' albums, by release.
    public struct Held: Sendable, Equatable {
        /// Navidrome's album id, once the id bridge found it.
        public var ids: [String: String]
        /// When the album's songs were last asked for (ms).
        public var asked: [String: Double]
        /// Looks in a row that found no album.
        public var misses: [String: Miss]
        /// Asked for now: not asked again until it answers.
        public var inFlight: Set<String>
        /// When the tab last came into view (ms).
        public var activeSince: Double

        public init(ids: [String: String] = [:], asked: [String: Double] = [:], misses: [String: Miss] = [:],
                    inFlight: Set<String> = [], activeSince: Double = 0) {
            self.ids = ids
            self.asked = asked
            self.misses = misses
            self.inFlight = inFlight
            self.activeSince = activeSince
        }
    }

    /// The asks out for the Done rows' albums (the id bridge's and the songs'), by release, each with its ticket - the
    /// web's `inFlight` set (Requests.tsx), made safe against an old ask ending after a new one of the same release
    /// began. An ask that ends, however it ends - answered, failed or let go - takes its release out of flight, unless a
    /// newer ask of it began since; letting every ask go (Requests' root left, deadwax out of reach, a new person)
    /// empties it at once, so a release whose ask was let go is looked for again next time, not skipped for good
    /// (slice 1's review, finding 2).
    public struct InFlight: Sendable, Equatable {
        private var asks: [String: Int] = [:]
        private var last = 0

        public init() {}

        /// The releases asked for now (Held's `inFlight`).
        public var releases: Set<String> { Set(asks.keys) }

        public func contains(_ release: String) -> Bool { asks[release] != nil }

        /// An ask begun: its ticket, for its end.
        public mutating func begin(_ release: String) -> Int {
            last += 1
            asks[release] = last
            return last
        }

        /// An ask ended: its release out of flight, unless a newer ask of it began since.
        public mutating func end(_ release: String, ticket: Int) {
            if asks[release] == ticket { asks[release] = nil }
        }

        /// Every ask let go: none in flight, and those let go end as nothing.
        public mutating func clear() { asks.removeAll() }
    }

    /// When each Done row first showed as done, kept only for the jobs deadwax still lists (slice 1's review, finding 6):
    /// a job it no longer lists - cleared, or gone - is forgotten; one it lists stays, a row a Clear done hides
    /// included, so a clear rolled back doesn't make its rows new.
    public static func kept(_ since: [String: Double], listed jobs: [DownloadJob]) -> [String: Double] {
        let keys = Set(jobs.map { RequestRow.key(job: $0.id) })
        return since.filter { keys.contains($0.key) }
    }

    public struct Looks: Sendable, Equatable {
        /// Releases to look up (the id bridge).
        public let look: [String]
        /// Releases whose album's songs to ask for.
        public let songs: [String]
        /// Milliseconds until the soonest look falls due, or nil for none.
        public let nextIn: Double?
    }

    /// `doneLooks`: what to ask about the rows' albums now, and when to look again.
    public static func looks(_ rows: [Row], held: Held, now: Double) -> Looks {
        var since: [String: Double] = [:]
        var order: [String] = []
        for row in rows {
            if since[row.release] == nil { order.append(row.release) }
            since[row.release] = JSMath.max(since[row.release] ?? 0, row.since)
        }
        var look: [String] = []
        var songs: [String] = []
        var due: Double?
        func later(_ at: Double) { due = due.map { JSMath.min($0, at) } ?? at }
        for release in order {
            guard let at = since[release], !held.inFlight.contains(release) else { continue }
            let scanned = at + scanSettleMs
            if held.ids[release] == nil {
                var backoff: Double = 0
                if let miss = held.misses[release] {
                    let doubled = retryMs * pow(2, Double(Swift.max(0, miss.count - 1)))
                    backoff = miss.at + JSMath.min(doubled, retryMaxMs)
                }
                let when = JSMath.max(scanned, backoff)
                if now >= when { look.append(release) } else { later(when) }
                continue
            }
            let asked = held.asked[release]
            if asked == nil || asked! < held.activeSince - freshMs {
                songs.append(release)
            } else if let asked, asked < scanned {
                if now >= scanned { songs.append(release) } else { later(scanned) }
            }
        }
        return Looks(look: look, songs: songs, nextIn: due.map { JSMath.max(0, $0 - now) })
    }
}

/// You > Getting albums' "Confirm before cancelling" (ConfirmCancelChoice.tsx): this phone's, on unless turned off -
/// kept under the web's key, "off" off and anything else (nothing stored included) on.
public enum ConfirmCancel {
    public static let storageKey = "deadwax-player-confirm-cancel"

    public static func read(_ stored: String?) -> Bool { stored != "off" }

    public static func stored(_ on: Bool) -> String { on ? "on" : "off" }
}
