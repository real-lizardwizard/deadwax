import Foundation

// Play history that lasts (app 0.8; the web's 2.1.15, ui/src/lib/playHistory.ts, function by function) - James,
// 2026-11-13: "I'd like it if the play history was persistent, so you can always look back and see what you played
// yesterday." In Up Next, Apple Music's way: scrolled up past the song playing, ONE CONTINUOUS LIST of everything
// played, newest nearest - no headings at all, no times on rows, skips drawn like plays. Kept by deadwax per person
// (src/routes/play_history.py, /deadwax/me/history), so the phone's plays and the web's show on both.
// notes/play-history.md, and notes/ios.md "Play history on the phone".
//
// A START is one song begun: the moment "now playing" goes (PlayReporter's began, or a join's - a listen's first
// sound, never a resume, a seek, a wait or a speed's restart), dated by the listen's own `startedAt`, the very `time`
// its counted play carries. It is recorded with the song as the queue holds it - so a row reads, and plays again, with
// nothing fetched - and with the queue's id and its entry's key, which is how each start is drawn exactly ONCE:
//
//   - while the queue still draws its entry - History (what Previous walks, the songs a tap passed included), the song
//     playing, or a row still to play - it is the QUEUE's row;
//   - (the web's 2.1.18) while one of the entries the queue's rows stand for holds it as a row brought back from the
//     play history (a tap on an older row rolled the queue back to it: UpNext.swift broughtBack, Mark.starts,
//     heldStarts), or its entry is ahead of the song playing up to the end of the furthest unit played (a roll-back or
//     Previous moved it back down: `reached`, even past the list's limit), it is the queue's too - moved down into Up
//     Next, never drawn above as history; it comes back into history as it plays again, a new start;
//   - once its entry has fallen past History's 50, or isn't drawn ahead (Previous back out of Repeat All's next round,
//     or past the list's first 100 rows), or the queue is another (an album tapped, a queue put back from another
//     app), it is one of the older rows ABOVE History, in the order they were begun.
//
// Above History the older rows run oldest first, so the list read upwards from the song playing goes back in time
// without a seam; a run of starts of one song (a restart, an hour of Repeat One) is one row, as History's unit is.
//
// Pure: no I/O, no clock; built and tested on Linux. Fixtures/history/vectors.json holds every function here to the
// TypeScript's own answers (ios/scripts/export-history.cjs). The app's HistoryModel and DownloadModel act on it.

/// One start, as deadwax keeps it - GET /deadwax/me/history's `plays`, and what POST takes (src/routes/play_history.py
/// HistoryStart).
public struct Played: Sendable, Equatable, Hashable, Codable {
    /// when the listen began, ms since the epoch, by the phone's clock - the counted play's `time`
    public let at: Int64
    /// whether it crossed the rule and counted as a play - kept, not drawn (skips are drawn like plays)
    public let counted: Bool
    /// the queue it was begun in (UpNextState.id) and its entry's key there - how the queue's own rows are told
    public let queue: String?
    public let entry: Int?
    /// the song as the queue holds it, without its level (bare())
    public let song: QueueTrack

    public init(at: Int64, counted: Bool = false, queue: String?, entry: Int?, song: QueueTrack) {
        self.at = at
        self.counted = counted
        self.queue = queue
        self.entry = entry
        self.song = bare(song)
    }

    /// The same start, counted.
    public var asCounted: Played { Played(at: at, counted: true, queue: queue, entry: entry, song: song) }

    enum CodingKeys: String, CodingKey {
        case at, counted, queue, entry, song
    }

    /// Read as deadwax answers it, leniently where it may say less (HistorySong): a song's id is all a start needs.
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        self.init(at: try fields.decode(Int64.self, forKey: .at),
                  counted: ((try? fields.decodeIfPresent(Bool.self, forKey: .counted)) ?? nil) ?? false,
                  queue: (try? fields.decodeIfPresent(String.self, forKey: .queue)) ?? nil,
                  entry: (try? fields.decodeIfPresent(Int.self, forKey: .entry)) ?? nil,
                  song: try fields.decode(HistorySong.self, forKey: .song).track)
    }

    /// Written as the web's POST writes a start: every field, none as null.
    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(at, forKey: .at)
        try fields.encode(counted, forKey: .counted)
        try fields.encode(queue, forKey: .queue)
        try fields.encode(entry, forKey: .entry)
        try fields.encode(HistorySong(song), forKey: .song)
    }
}

/// A start's song as deadwax keeps it - the queue's song without its level (bare()), in its twelve names (the server's
/// HistorySong) - and as the person's store keeps a start not yet sent (`start_pending.song`).
public struct HistorySong: Sendable, Equatable, Codable {
    public let track: QueueTrack

    public init(_ track: QueueTrack) {
        self.track = bare(track)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, albumId, coverArt, duration, contentType, suffix, sampleRate, bitDepth, channels
    }

    /// Leniently: the id is all it needs; anything else left out reads as none ("" for its words, 0 for its numbers).
    public init(from decoder: any Decoder) throws {
        let song = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String { ((try? song.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? "" }
        func optional(_ key: CodingKeys) -> String? { (try? song.decodeIfPresent(String.self, forKey: key)) ?? nil }
        func whole(_ key: CodingKeys) -> Int { ((try? song.decodeIfPresent(Int.self, forKey: key)) ?? nil) ?? 0 }
        track = QueueTrack(
            id: try song.decode(String.self, forKey: .id), title: text(.title), artist: text(.artist), album: text(.album),
            albumId: optional(.albumId), coverArt: optional(.coverArt),
            duration: ((try? song.decodeIfPresent(Double.self, forKey: .duration)) ?? nil) ?? 0,
            contentType: optional(.contentType), suffix: optional(.suffix), sampleRate: whole(.sampleRate),
            bitDepth: whole(.bitDepth), channels: whole(.channels))
    }

    public func encode(to encoder: any Encoder) throws {
        var out = encoder.container(keyedBy: CodingKeys.self)
        try out.encode(track.id, forKey: .id)
        try out.encode(track.title, forKey: .title)
        try out.encode(track.artist, forKey: .artist)
        try out.encode(track.album, forKey: .album)
        try out.encode(track.albumId, forKey: .albumId)
        try out.encode(track.coverArt, forKey: .coverArt)
        try out.encode(track.duration.isFinite ? track.duration : 0, forKey: .duration)
        try out.encode(track.contentType, forKey: .contentType)
        try out.encode(track.suffix, forKey: .suffix)
        try out.encode(track.sampleRate, forKey: .sampleRate)
        try out.encode(track.bitDepth, forKey: .bitDepth)
        try out.encode(track.channels, forKey: .channels)
    }
}

/// Where a page ends: its last play's moment and song - GET's `next`, the page before it asked for by it.
public struct HistoryCursor: Sendable, Equatable, Hashable, Codable {
    public let at: Int64
    public let id: String

    public init(at: Int64, id: String) {
        self.at = at
        self.id = id
    }
}

/// A page of them, newest first: `next` the last one's own moment and song, to ask for the page before it with.
public struct HistoryPage: Sendable, Equatable, Codable {
    public let plays: [Played]
    public let next: HistoryCursor?
    /// logins off: one history for everyone on this deadwax
    public let shared: Bool

    public init(plays: [Played], next: HistoryCursor?, shared: Bool) {
        self.plays = plays
        self.next = next
        self.shared = shared
    }
}

/// What POST /deadwax/me/history sends: the starts, at most PlayHistory.postMax.
public struct HistoryPost: Sendable, Equatable, Encodable {
    public let starts: [Played]

    public init(starts: [Played]) {
        self.starts = starts
    }
}

/// What it answers: the starts kept, and those skipped (each validated on its own - one deadwax can't take is skipped,
/// never the batch's refusal).
public struct HistoryTaken: Sendable, Equatable, Decodable {
    public let taken: Int
    public let skipped: Int
}

/// One older row of Up Next's list: the first start of a run of one song - its key - and the song; (the web's 2.1.18)
/// the moments of every start of the run, oldest first, and the entry of the queue playing its first start was begun
/// in, when it was - what a tap on it brings back (UpNext.swift Brought).
public struct PastRow: Sendable, Equatable, Hashable {
    public let key: String
    public let track: QueueTrack
    public internal(set) var starts: [Int64]
    public let entry: Int?

    public init(key: String, track: QueueTrack, starts: [Int64], entry: Int?) {
        self.key = key
        self.track = track
        self.starts = starts
        self.entry = entry
    }
}

/// The entries of a queue whose starts its own rows draw - its id, and shownKeys(): History's, the song playing's, the
/// songs added and the list's rows drawn (its first `limit`) - never a later time round or a row past the limit, whose
/// starts are older rows above. (2.1.18) And `held`: the starts the queue holds as rows brought back from the play
/// history (heldStarts) - of the entries its rows stand for, whatever queue they were begun in - each a start's key
/// (PlayHistory.key) in UTF-16 units, as the web's Set of strings tells them apart. None with nothing playing.
public struct QueueShows: Sendable, Equatable {
    public let id: String?
    public let keys: Set<Int>
    public let held: Set<[UInt16]>

    public init(id: String?, keys: Set<Int>, held: Set<[UInt16]> = []) {
        self.id = id
        self.keys = keys
        self.held = held
    }

    public static let none = QueueShows(id: nil, keys: [], held: [])
}

/// What the history model holds of deadwax's pages: every play they brought, newest first, each once; the cursor of
/// the page before the oldest (`before` - nil: there is none, or nothing asked yet); and whether a page has come.
public struct HistoryHeld: Sendable, Equatable {
    public let plays: [Played]
    public let before: HistoryCursor?
    public let asked: Bool

    public init(plays: [Played], before: HistoryCursor?, asked: Bool) {
        self.plays = plays
        self.before = before
        self.asked = asked
    }

    /// NOTHING_HELD
    public static let nothing = HistoryHeld(plays: [], before: nil, asked: false)
}

/// A queue put back mid-song (ResumeController's `continuing`): its next start, if it is of this entry, is the same
/// listen carrying on.
public struct Continuation: Sendable, Equatable {
    public let queue: String
    public let entry: Int

    public init(queue: String, entry: Int) {
        self.queue = queue
        self.entry = entry
    }
}

public enum PlayHistory {
    /// The plays a page asks for - src/play_history.py HISTORY_PAGE.
    public static let page = 100
    /// The starts one POST sends at most - HISTORY_POST_MAX.
    public static let postMax = 500
    /// The starts this run keeps of its own, sent or not - drawn until a page of deadwax's holds them (OWN_KEPT).
    public static let ownKept = 500
    /// How long after the first failed send in a row the outbox tries again, doubling to `retryMaxMs` (RETRY_MS,
    /// RETRY_MAX_MS).
    public static let retryMs: Int64 = 30_000
    public static let retryMaxMs: Int64 = 600_000
    /// Where the newest page is kept in the person's store (DownloadDatabase's `meta`), for showing recent plays offline.
    public static let keptPageKey = "history_newest"

    /// A start's key: its moment and its song - deadwax's own (user, started_at, song_id), within one person.
    public static func key(_ played: Played) -> String { "\(played.at):\(played.song.id)" }

    /// The start of the song playing in `queue`, begun at `at` (the listen's `startedAt`) - the song as the queue holds
    /// it, without its level, its queue's id and its entry's key with it.
    public static func startOf(_ track: QueueTrack, at: Int64, queue: UpNextQueue) -> Played {
        let entry = queue.upNext.flatMap { markAt($0.marks, queue.index)?.key }
        return Played(at: at, counted: false, queue: queue.upNext?.id, entry: entry, song: track)
    }

    public static func queueShows(_ queue: UpNextQueue, limit: Int = UpNext.drawn) -> QueueShows {
        guard let state = queue.upNext, !state.id.isEmpty, queue.current != nil else { return .none }
        let held = Set(heldStarts(queue, limit: limit).map { Array("\($0.at):\($0.id)".utf16) })
        return QueueShows(id: state.id, keys: shownKeys(queue, limit: limit), held: held)
    }

    /// Whether `played` is one of the queue's own rows - begun in this queue, its entry one the queue's rows stand for.
    /// Such a start is drawn there, never again above.
    public static func shownByQueue(_ played: Played, _ shows: QueueShows) -> Bool {
        guard let id = shows.id, let entry = played.entry, let queue = played.queue else { return false }
        return WebText.same(queue, id) && shows.keys.contains(entry)
    }

    /// (2.1.18) Whether the queue holds `played`: one of its own rows (shownByQueue), or a row brought back from the
    /// play history that it holds (QueueShows.held) - moved down into Up Next. Either way never an older row above.
    public static func heldByQueue(_ played: Played, _ shows: QueueShows) -> Bool {
        shownByQueue(played, shows) || shows.held.contains(Array(key(played).utf16))
    }

    /// deadwax's pages and this phone's own starts as one list, newest first, each start once - `counted` ORed, since a
    /// page may hold a start this phone has since seen count. Keys and ids compared as JavaScript compares them, by
    /// UTF-16 unit (Swift's `==` takes "\u{e9}" for "e\u{301}"; deadwax and the web keep them apart).
    public static func merged(_ pages: [Played], _ own: [Played]) -> [Played] {
        var order: [[UInt16]] = []
        var byKey: [[UInt16]: Played] = [:]
        for played in pages + own {
            let key = Array(key(played).utf16)
            if let held = byKey[key] {
                if played.counted && !held.counted { byKey[key] = held.asCounted }
            } else {
                byKey[key] = played
                order.append(key)
            }
        }
        return order.compactMap { byKey[$0] }.sorted(by: newerFirst)
    }

    /// The order deadwax pages in: newer first, and at one moment the greater song id first (UTF-16 units, as
    /// JavaScript compares strings).
    static func newerFirst(_ a: Played, _ b: Played) -> Bool {
        if a.at != b.at { return a.at > b.at }
        return b.song.id.utf16.lexicographicallyPrecedes(a.song.id.utf16)
    }

    /// The older rows above History, oldest first: every start (newest first, as `merged` gives them) the queue doesn't
    /// hold itself (`limit` the list's rows Up Next draws; heldByQueue), a run of starts of one song one row - keyed by
    /// the run's first start, with every start's moment (2.1.18), and the entry its first start was begun in when that
    /// was in the queue playing.
    public static func pastRows(_ plays: [Played], queue: UpNextQueue, limit: Int = UpNext.drawn) -> [PastRow] {
        let shows = queueShows(queue, limit: limit)
        var rows: [PastRow] = []
        var last: String?
        for played in plays.reversed() {
            if heldByQueue(played, shows) { continue }
            if let last, WebText.same(played.song.id, last) {
                rows[rows.count - 1].starts.append(played.at)
                continue
            }
            last = played.song.id
            let mine = shows.id.map { id in played.queue.map { WebText.same($0, id) } ?? false } ?? false
            rows.append(PastRow(key: key(played), track: played.song, starts: [played.at], entry: mine ? played.entry : nil))
        }
        return rows
    }

    /// (2.1.18) An older row's tap: the rows from it (by its key) down to History's, oldest first - what comes back into
    /// the queue, the tapped one first (UpNext.swift broughtBack). None for a key not among them.
    public static func rowsFrom(_ rows: [PastRow], _ key: String) -> [PastRow] {
        guard let at = rows.firstIndex(where: { WebText.same($0.key, key) }) else { return [] }
        return Array(rows[at...])
    }

    /// (the web's 2.1.18 replayPast, app/UpNext.tsx; review of the port) What an older row's tap hands the roll-back
    /// (QueueController.rollBack): the rows Up Next draws above History (pastRows, its default limit) from the one
    /// tapped down (rowsFrom), each song queued at the setting's level for a song (levelFor(setting, .songs) - under
    /// Off, as it was, as queued() leaves it), with its starts and its entry; and `floor`, the first entry Up Next draws
    /// for the queue now - History's first row, else the song playing's - which the rows were read against. No rows for
    /// a key not among them. Pure, so the hand-over is held to the web's by export-history.cjs's vectors, which compose
    /// replayPast from the web's own parts and hash its text.
    public static func brought(_ plays: [Played], queue: UpNextQueue, key: String,
                               setting: Normalization) -> (rows: [Brought], floor: Int?) {
        brought(rows: pastRows(plays, queue: queue), queue: queue, key: key, setting: setting)
    }

    /// brought(_:queue:key:setting:) over the rows Up Next drew (`past`).
    public static func brought(rows past: [PastRow], queue: UpNextQueue, key: String,
                               setting: Normalization) -> (rows: [Brought], floor: Int?) {
        let level = levelFor(setting, .songs)
        let rows = rowsFrom(past, key).map { row -> Brought in
            var song = row.track
            if let level { song.level = level }
            return Brought(track: song, starts: row.starts, entry: row.entry)
        }
        var floor = historyRows(queue).first?.key
        if floor == nil, let marks = queue.upNext?.marks, marks.indices.contains(queue.index) { floor = marks[queue.index].key }
        return (rows, floor)
    }

    /// Whether `a` comes after `b` in deadwax's order - its moment, then its song id (the page's ORDER BY).
    static func after(_ a: Played, _ b: Played) -> Bool {
        a.at > b.at || (a.at == b.at && b.song.id.utf16.lexicographicallyPrecedes(a.song.id.utf16))
    }

    /// The newest page come (Up Next opened, or the app back at the front with it open): joined to what is held - the
    /// older pages kept, and where to ask from for them - unless it doesn't reach back to the newest held (more played
    /// elsewhere since than a page holds), when it starts again from it, the plays between never left out. Nothing
    /// held yet - not asked, or an empty page came first - and this page is all there is.
    public static func withNewest(_ held: HistoryHeld, _ page: HistoryPage) -> HistoryHeld {
        let oldest = page.plays.last
        if !held.asked || held.plays.isEmpty
            || (page.next != nil && oldest != nil && after(oldest!, held.plays[0])) {
            return HistoryHeld(plays: page.plays, before: page.next, asked: true)
        }
        return HistoryHeld(plays: merged(page.plays, held.plays), before: page.next == nil ? nil : held.before, asked: true)
    }

    /// The page before the oldest held come, asked for from `from`: added below - unless what is held has moved on since
    /// (the newest page started again), when it is the same `held`.
    public static func withOlder(_ held: HistoryHeld, from: HistoryCursor, _ page: HistoryPage) -> HistoryHeld {
        guard let before = held.before, before.at == from.at, WebText.same(before.id, from.id) else { return held }
        return HistoryHeld(plays: merged(held.plays, page.plays), before: page.next, asked: true)
    }

    /// A start's `counted` set, when it is the one a counted play names (the play's song and `time`).
    public static func countedIn(_ own: [Played], songID: String, at: Int64) -> [Played] {
        guard own.contains(where: { WebText.same($0.song.id, songID) && $0.at == at && !$0.counted }) else { return own }
        return own.map { WebText.same($0.song.id, songID) && $0.at == at ? $0.asCounted : $0 }
    }

    /// What a failed send means for the starts it carried (afterFailure): `.retry` - deadwax unreachable (nil), a 5xx, a
    /// 408 or a 429, asked again later; or a 401, signed out, until a sign-in - or `.drop`, another 4xx: they will never
    /// be taken.
    public enum Failure: String, Sendable, Equatable {
        case retry, drop
    }

    public static func afterFailure(_ status: Int?) -> Failure {
        guard let status, (400..<500).contains(status), ![401, 408, 429].contains(status) else { return .retry }
        return .drop
    }

    /// A send's answer, for the phone's outbox (PendingPlays.After's four): taken; held (a 401: kept, sent after the
    /// same person signs in again); dropped (another 4xx); stopped (no answer, a 5xx, a 408 or a 429: kept, tried again
    /// after `retryAfter`, and at the next start).
    public static func after(status: Int?) -> PendingPlays.After {
        guard let status else { return .stopped }
        if (200..<300).contains(status) { return .sent }
        if status == 401 { return .held }
        return afterFailure(status) == .drop ? .dropped : .stopped
    }

    /// How long after the `failures`-th failed send in a row the outbox tries again, in ms: 30 s doubling - 30 s, 1 min,
    /// 2, 4, 8 - to 10 min, so a deadwax without its database isn't sent the same starts every 30 s for ever.
    public static func retryAfter(_ failures: Int) -> Int64 {
        let doublings = max(0, min(failures - 1, 20))
        return min(retryMaxMs, retryMs * (Int64(1) << Int64(doublings)))
    }
}

/// This phone's own starts as the app keeps them in memory (player/historyOutbox.ts's `own` and `continuation`; the
/// starts not yet taken are the person's store's `start_pending`, DownloadDatabase): the newest `PlayHistory.ownKept`,
/// sent or not - drawn until a page of deadwax's holds them - and the continuation a queue put back set.
public struct HistoryOutbox: Sendable, Equatable {
    /// This run's starts, newest first.
    public private(set) var own: [Played] = []
    public private(set) var continuation: Continuation?

    public init() {}

    /// A song begun: kept - unless it is the continuation's (the same queue's same entry, put back mid-song), which is
    /// the listen carrying on. Any start ends the continuation. False when it wasn't one to keep (nor to send).
    public mutating func record(_ played: Played) -> Bool {
        let went = continuation
        continuation = nil
        if let went, let queue = played.queue, WebText.same(queue, went.queue), played.entry == went.entry { return false }
        own = Array(([played] + own).prefix(PlayHistory.ownKept))
        return true
    }

    /// A counted play: `counted` set on its start (the play's song and its listen's start). True when it changed one.
    @discardableResult
    public mutating func counted(songID: String, at: Int64) -> Bool {
        let next = PlayHistory.countedIn(own, songID: songID, at: at)
        guard next != own else { return false }
        own = next
        return true
    }

    /// A queue of deadwax's own put back paused mid-song: its next start, if it is of the song put back, is the same
    /// listen carrying on. Nil - any other queue put back - ends one.
    public mutating func continuing(_ queue: UpNextQueue?) {
        guard let queue, let state = queue.upNext, let mark = markAt(state.marks, queue.index) else {
            continuation = nil
            return
        }
        continuation = Continuation(queue: state.id, entry: mark.key)
    }

    /// Everything forgotten (another person).
    public mutating func forget() {
        own = []
        continuation = nil
    }
}

/// What Up Next's play history may ask deadwax, and which failure it says (the App's HistoryModel, which holds the
/// answers and the errors): each ask numbered, so only the newest answer of each kind counts; an older page one at a
/// time; and the two kinds' failures apart -
///
///  - an older page's failure stops scrolling from asking until Try again (or every row coming into view would ask
///    again at once), and is always said;
///  - the newest page's never stops the older pages, and is said only online: offline the newest page isn't asked
///    for at all - what the phone keeps is drawn, and an ask could only fail - and one that failed before isn't news.
///    A newest page that comes lets it go; so does the network coming back, when Up Next asks again.
public struct HistoryAsking: Sendable, Equatable {
    public enum Ask: Sendable, Equatable {
        case newest, older
    }

    /// How near the list's top - in rows - a row in view asks for the next older page.
    public static let near = 10

    /// An older page is on its way.
    public private(set) var loadingOlder = false
    /// The last newest page asked for failed.
    public private(set) var newestFailed = false
    /// The last older page asked for failed.
    public private(set) var olderFailed = false
    private var newest = 0
    private var older = 0

    public init() {}

    /// The newest page asked for: its number - nil offline.
    public mutating func askNewest(online: Bool) -> Int? {
        guard online else { return nil }
        newest += 1
        return newest
    }

    /// The newest page's answer came: whether it is the last asked (only that one counts). Its failure let go.
    public mutating func newestCame(_ ask: Int) -> Bool {
        guard ask == newest else { return false }
        newestFailed = false
        return true
    }

    /// The newest page's ask failed: whether it is the last asked.
    public mutating func failedNewest(_ ask: Int) -> Bool {
        guard ask == newest else { return false }
        newestFailed = true
        return true
    }

    /// An older page may be asked for: there is one (`more`), none is on its way, and the last didn't fail.
    public func mayAskOlder(more: Bool) -> Bool {
        more && !loadingOlder && !olderFailed
    }

    /// The older page asked for: its number - nil when it may not be.
    public mutating func askOlder(more: Bool) -> Int? {
        guard mayAskOlder(more: more) else { return nil }
        older += 1
        loadingOlder = true
        return older
    }

    /// The older page's answer came: whether it is the last asked.
    public mutating func olderCame(_ ask: Int) -> Bool {
        guard ask == older else { return false }
        loadingOlder = false
        olderFailed = false
        return true
    }

    /// The older page's ask failed: whether it is the last asked.
    public mutating func failedOlder(_ ask: Int) -> Bool {
        guard ask == older else { return false }
        loadingOlder = false
        olderFailed = true
        return true
    }

    /// The failure Up Next says, with Try again: an older page's, else the newest page's while online - nil for none.
    public func shown(online: Bool) -> Ask? {
        if olderFailed { return .older }
        return newestFailed && online ? .newest : nil
    }

    /// Try again: the ask to make again (the failure shown), its failure let go.
    public mutating func retry(online: Bool) -> Ask? {
        let ask = shown(online: online)
        if ask == .older { olderFailed = false } else if ask == .newest { newestFailed = false }
        return ask
    }

    /// Another person: every answer on its way dropped, nothing failed.
    public mutating func reset() {
        newest += 1
        older += 1
        loadingOlder = false
        newestFailed = false
        olderFailed = false
    }

    /// An older page landed: whether to ask for the next at once - there is one, and a row among the list's first `near`
    /// is still in view. A row coming into view is what asks, so a page that added no row above the ones in view (its
    /// starts all the queue's own, or one run with the oldest row's) would otherwise leave scrolling stalled at the top.
    /// `order` the list's rows top to bottom, `inView` those in view.
    public static func asksAgain<Key: Hashable>(_ order: [Key], inView: Set<Key>, more: Bool) -> Bool {
        more && order.prefix(near).contains { inView.contains($0) }
    }
}
