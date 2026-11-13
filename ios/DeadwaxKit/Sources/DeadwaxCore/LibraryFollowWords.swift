import Foundation

/// One check of your library with deadwax, as Debug and the downloads log tell it (phase3-autodownload.md 3.5).
public struct LibraryCheckRecord: Sendable, Equatable {
    public enum Result: Sendable, Equatable {
        /// A 200, with the albums listed.
        case listed(albums: Int)
        /// A 304: the last list again.
        case unchanged
        /// No answer, or a refusal - in its own words, for whoever runs deadwax.
        case failed(String)
    }

    public let reason: LibraryCheck
    public let result: Result
    /// When it was asked (ms).
    public let began: Int64
    /// How long the request and its sync took.
    public let seconds: Double

    public init(reason: LibraryCheck, result: Result, began: Int64, seconds: Double) {
        self.reason = reason
        self.result = result
        self.began = began
        self.seconds = seconds
    }
}

/// Debug's Your library (phase3-autodownload.md 3.5) and the downloads log's library lines, in words. For whoever runs
/// deadwax: Debug is an admin's.
public enum LibraryFollowWords {
    public static let section = "Your library"
    /// (slice 2) Debug shows what Download your library follows; it is turned on and off in You > Downloads.
    public static let followNote = "What Download your library follows, what fits on this phone, and the last check. It is turned on and off in You > Downloads; the library's log lines are the Downloads section's."
    public static let checkNow = "Check now"
    public static let notFollowing = "Off: Download your library is turned off in You > Downloads."
    public static let noCheckYet = "No check yet"

    /// What is followed.
    public static func scope(_ scope: AlbumScope) -> String {
        scope == .yours ? "Your library (your starred albums)" : "The collection (no library of your own)"
    }

    /// "3,010".
    public static func count(_ n: Int) -> String { UpNextWords.grouped(n) }

    /// "2,998 of 3,010" - the albums listed whose songs are read.
    public static func read(_ read: Int, of listed: Int) -> String { "\(count(read)) of \(count(listed))" }

    /// "None", or "2 (the first 4 min ago)".
    public static func missing(_ albums: [FollowedAlbum], now: Int64) -> String {
        let marks = albums.compactMap(\.missingSince)
        guard let oldest = marks.min() else { return "None" }
        return "\(count(marks.count)) (the first \(ago(oldest, now: now)))"
    }

    /// Why the last list's absences weren't believed: "No", or the reason.
    public static func held(_ held: LibraryFollow.Held?) -> String {
        switch held {
        case nil:
            return "No"
        case .empty(let kept)?:
            return "deadwax listed no albums while this phone follows \(count(kept)), so nothing is marked missing."
        case .drop(let gone, let of)?:
            return "The list left out \(count(gone)) of \(count(of)) albums at once, so nothing is marked missing."
        case .truncated?:
            return "The list stopped at deadwax's 10,000 albums, so nothing is marked missing."
        }
    }

    /// "just now", "1 min ago", "3 h ago", "2 days ago". A moment ahead of `now` is "just now".
    public static func ago(_ ms: Int64, now: Int64) -> String {
        let seconds = max(now - ms, 0) / 1_000
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours) h ago" }
        return "\(hours / 24) days ago"
    }

    /// "0.84 s" under a minute, "4 min 12 s" past it.
    public static func duration(_ seconds: Double) -> String {
        let whole = max(seconds, 0)
        if whole < 60 { return String(format: "%.2f s", whole) }
        let rounded = Int(whole.rounded())
        return "\(rounded / 60) min \(rounded % 60) s"
    }

    /// "200 · 3,010 albums · 0.84 s · 3 min ago", "unchanged (304) · 0.12 s · just now", "failed: <words> · ...".
    public static func lastCheck(_ record: LibraryCheckRecord, now: Int64) -> String {
        let what: String
        switch record.result {
        case .listed(let albums): what = "200 \u{00B7} \(count(albums)) album\(albums == 1 ? "" : "s")"
        case .unchanged: what = "unchanged (304)"
        case .failed(let words): what = "failed: \(words)"
        }
        return "\(what) \u{00B7} \(duration(record.seconds)) \u{00B7} \(ago(record.began, now: now))"
    }

    /// "4 min 12 s for 3,010 albums · 84 ms each" - the first read (R13).
    public static func firstRead(seconds: Double, albums: Int) -> String {
        guard albums > 0 else { return duration(seconds) }
        let each = Int((seconds * 1_000 / Double(albums)).rounded())
        return "\(duration(seconds)) for \(count(albums)) album\(albums == 1 ? "" : "s") \u{00B7} \(each) ms each"
    }

    /// "412 of 3,010 fit in 20 GB", "All 3,010 fit in 20 GB", "412 of 3,010 fit on this phone" (No limit).
    public static func wouldFit(_ plan: LibraryFill.Plan, limit: StorageLimit) -> String {
        let place = limit.bytes == nil ? "on this phone" : "in \(limit.label)"
        if plan.allFit && plan.of > 0 { return "All \(count(plan.of)) fit \(place)" }
        return "\(count(plan.fit)) of \(count(plan.of)) fit \(place)"
    }

    /// "They take 19.6 GB · 3 wait for room on the phone · 12 not read yet · 1 kept off" - the counts that are there.
    public static func fitDetail(_ plan: LibraryFill.Plan) -> String {
        var parts = ["They take \(Bytes.words(plan.bytes))"]
        let room = plan.count(.room)
        let phone = plan.count(.phoneFull)
        let unread = plan.count(.unread)
        let keptOff = plan.count(.keptOff)
        if room > 0 { parts.append("\(count(room)) over the limit") }
        if phone > 0 { parts.append("\(count(phone)) wait for room on the phone") }
        if unread > 0 { parts.append("\(count(unread)) not read yet") }
        if keptOff > 0 { parts.append("\(count(keptOff)) kept off") }
        if !plan.giveWay.isEmpty { parts.append("\(count(plan.giveWay.count)) would give way") }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The downloads log's line for a check: "library front: 200, 3,010 albums, 1 added, 1 missing, 2 removed (0.84 s)".
    public static func logLine(_ record: LibraryCheckRecord, _ outcome: LibraryFollow.Outcome?) -> String {
        var parts: [String] = []
        switch record.result {
        case .listed(let albums): parts.append("200, \(count(albums)) album\(albums == 1 ? "" : "s")")
        case .unchanged: parts.append("unchanged (304)")
        case .failed(let words): parts.append("failed: \(words)")
        }
        if let outcome {
            for (n, word) in [(outcome.added.count, "added"), (outcome.changed.count, "changed"),
                              (outcome.missing.count, "missing"), (outcome.back.count, "back"),
                              (outcome.removed.count, "removed")] where n > 0 {
                parts.append("\(count(n)) \(word)")
            }
            if let held = outcome.held { parts.append("held: \(held.raw)") }
        }
        return "library \(record.reason.rawValue): \(parts.joined(separator: ", ")) (\(duration(record.seconds)))"
    }

    /// The log's line for a read that failed: "library read <id>: <words>".
    public static func readFailed(_ album: String, _ words: String) -> String { "library read \(album): \(words)" }
}
