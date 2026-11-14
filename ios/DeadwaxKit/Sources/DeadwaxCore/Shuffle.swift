import Foundation

// The Library's Shuffle of your whole library (Phase 4, slice 3b - notes/ios-specs/phase4-library.md 2.7 and 2.8; the
// web's 2.0.0-player.57 "Part B" of Up Next, shuffle and repeat, notes/app.md): every song of the Library's scope,
// each once, in a random order deadwax makes and holds (src/routes/navidrome.py /shuffle), played a page at a time.
// ShuffleAhead is app/ShuffleSongs.tsx's rules - its first page asked ahead, so the tap plays songs in hand;
// ShuffleFeed and ShuffleFeedRun are app/useShuffleFeed.ts's - the rest of the order brought in as it plays. Pure: the
// app makes the asks they name and hands back what came (ShuffleModel, PlayerModel's feed). Held to the web by hand
// until slice 5's exporter (question 24): each number and word below is named with its source.

/// `GET /deadwax/navidrome/shuffle`: a new order - its token, how many songs it has, and its first page (SHUFFLE_PAGE,
/// 200). Read leniently, as every answer is: a song that can't be read is left out.
public struct ShuffleStart: Decodable, Sendable, Equatable {
    public let token: String
    public let total: Int
    public let songs: [Song]

    enum CodingKeys: String, CodingKey {
        case token, total, songs
    }

    public init(token: String, total: Int, songs: [Song]) {
        self.token = token
        self.total = total
        self.songs = songs
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        token = try fields.decode(String.self, forKey: .token)
        total = fields.looseField(Int.self, .total) ?? 0
        songs = fields.looseList(Song.self, .songs) ?? []
    }
}

/// `GET /deadwax/navidrome/shuffle/{token}?offset=`: a page of an order from `offset` - a 404 ("gone") once deadwax no
/// longer holds it.
public struct ShufflePage: Decodable, Sendable, Equatable {
    public let total: Int
    public let songs: [Song]

    enum CodingKeys: String, CodingKey {
        case total, songs
    }

    public init(total: Int, songs: [Song]) {
        self.total = total
        self.songs = songs
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        total = fields.looseField(Int.self, .total) ?? 0
        songs = fields.looseList(Song.self, .songs) ?? []
    }
}

/// The Shuffle's words: the web's, verbatim.
public enum ShuffleWords {
    /// The button's (ShuffleSongs.tsx).
    public static let shuffle = "Shuffle"
    /// SHUFFLE_GETTING_READY: while its first page is on its way.
    public static let gettingReady = "Getting ready\u{2026}"
    /// SHUFFLE_UNREADY: when it won't come.
    public static let unready = "Couldn't get your songs ready to shuffle"
    /// SHUFFLE_STARTED_OVER (useShuffleFeed.ts): said once, when deadwax no longer had the order and a fresh one took
    /// over.
    public static let startedOver = "Your shuffle started over - deadwax no longer had its order"

    /// Why the first page didn't come, in a listener's words: a 413's own words (SHUFFLE_TOO_BIG, "Your library is too
    /// big to shuffle here") as the server says them, else SHUFFLE_UNREADY.
    public static func unready(status: Int?, detail: String?) -> String {
        if status == 413, let detail, !detail.isEmpty { return detail }
        return unready
    }
}

/// The Library's Shuffle's first page, asked ahead (ShuffleSongs.tsx): asked as the Library shows, and again when it shows
/// more than SHUFFLE_FRESH_MS after the last ask; ready once a page with songs is in; a tap plays it and asks a new order
/// for the next tap, naming the one it played until one gets through - so deadwax claims it.
public struct ShuffleAhead: Sendable, Equatable {
    /// SHUFFLE_FRESH_MS, in seconds: how long a first page asked ahead stays the one a tap plays - the route's
    /// SHUFFLE_LIST_TTL_S, so songs added meanwhile are in the next shuffle.
    public static let freshSeconds = 600

    /// One ask of deadwax: `/shuffle?scope=&playing=` (never claimed: the list's own ask).
    public struct Ask: Sendable, Equatable {
        public let serial: Int
        public let scope: PagedScope
        /// the order the last tap played, for deadwax to claim
        public let playing: String?
    }

    /// What a tap plays: the first page's songs as tracks, the songs themselves, the shuffle they are, and the ask for
    /// the next tap's order.
    public struct Taken: Sendable, Equatable {
        public let tracks: [QueueTrack]
        public let songs: [Song]
        public let paged: Paged
        public let next: Ask
    }

    /// The first page in hand; nil before it comes, and once a tap has played it.
    public private(set) var first: ShuffleStart?
    /// Why the last ask failed, in a listener's words; nil while it hasn't.
    public private(set) var failure: String?
    /// The scope asked for.
    public private(set) var scope: PagedScope?
    /// When the last ask was made (seconds); nil before one, and after one failed - so it is asked the next time.
    var askedAt: Double?
    /// The order the last tap played, named in each ask until one gets through.
    var played: String?
    /// The newest ask's: an answer for any other is dropped.
    var serial = 0

    public init() {}

    /// A tap would play: a first page with songs is in.
    public var ready: Bool { first.map { !$0.songs.isEmpty } ?? false }
    /// The scope has no songs at all: no Shuffle.
    public var empty: Bool { first?.total == 0 }

    /// The Library came into view (`now`, seconds): an ask when none was made yet - or the last failed, or was made
    /// more than `freshSeconds` ago (the page in hand let go) - else nil. Another scope starts afresh.
    public mutating func shown(_ scope: PagedScope, now: Double) -> Ask? {
        if self.scope != scope { restart(scope) }
        if let at = askedAt, !(now - at > Double(Self.freshSeconds)) { return nil }
        first = nil
        return begin(now)
    }

    /// The newest ask answered: the order it named has got through, and is named no more. (The web lets it go only if
    /// it is still the one named; here the newest ask always names what `played` holds - `take` sets both, and an older
    /// ask's answer is dropped - so that test is always true.)
    public mutating func answered(_ ask: Ask, _ answer: ShuffleStart) {
        guard ask.serial == serial else { return }
        played = nil
        first = answer
        failure = nil
    }

    /// The newest ask failed: why, and asked again the next time the Library shows.
    public mutating func failed(_ ask: Ask, words: String) {
        guard ask.serial == serial else { return }
        askedAt = nil
        failure = words
    }

    /// The tap: the first page, every song at `level` (the songs level - PlaylistPlay.songsLevel), as a library's
    /// shuffle with the level the first one got - and the ask for the next tap's order, naming this one. Nil when not
    /// ready: the tap does nothing.
    public mutating func take(level: Level?, now: Double) -> Taken? {
        guard let first, !first.songs.isEmpty, let scope else { return nil }
        let tracks = first.songs.map { ShuffleFeed.track($0, level: level) }
        let paged = Paged(token: first.token, total: first.total, fetched: first.songs.count, scope: scope,
                          level: tracks.first?.level)
        played = first.token
        self.first = nil
        return Taken(tracks: tracks, songs: first.songs, paged: paged, next: begin(now))
    }

    /// A new person: everything let go, and no answer asked before lands.
    public mutating func reset() {
        serial += 1
        first = nil
        failure = nil
        scope = nil
        askedAt = nil
        played = nil
    }

    private mutating func restart(_ scope: PagedScope) {
        serial += 1
        first = nil
        failure = nil
        askedAt = nil
        played = nil
        self.scope = scope
    }

    private mutating func begin(_ now: Double) -> Ask {
        serial += 1
        askedAt = now
        return Ask(serial: serial, scope: scope ?? .store, playing: played)
    }
}

/// The feed's numbers and pure rules (useShuffleFeed.ts).
public enum ShuffleFeed {
    /// FEED_BELOW: fewer of a library's shuffle's songs than this after the song playing, and its next page is asked for -
    /// about three hours of music ahead.
    public static let below = 50
    /// FEED_RETRY_MS, in seconds: a page that wouldn't come is asked for again this long after.
    public static let retrySeconds = 30

    /// A song of a shuffle as the queue takes it: shuffledTrack (Resume.swift, the web's) - its album known only by its
    /// id and name, Info asking for the rest - at `level` (atLevel: nil leaves it none).
    public static func track(_ song: Song, level: Level?) -> QueueTrack {
        var track = shuffledTrack(song)
        track.level = level
        return track
    }

    /// startingElsewhere: a fresh order's first page, to follow the queue's last song (`ending`), never starting with
    /// that same song - with any other to start with, the first swapped with a random later place.
    public static func startingElsewhere(_ tracks: [QueueTrack], ending: String?,
                                         random: () -> Double = UpNext.systemRandom) -> [QueueTrack] {
        var out = tracks
        guard let ending, out.count >= 2, out[0].id == ending else { return out }
        let later = out.indices.filter { $0 > 0 && out[$0].id != ending }
        guard !later.isEmpty else { return out }
        let pick = later[min(Int((random() * Double(later.count)).rounded(.down)), later.count - 1)]
        out.swapAt(0, pick)
        return out
    }

    /// songsAhead: how many of the list's songs come after the song playing - what the feed keeps at FEED_BELOW or more.
    public static func songsAhead(_ queue: UpNextQueue) -> Int {
        guard let marks = queue.upNext?.marks else { return 0 }
        var count = 0
        var place = queue.index + 1
        while place < marks.count {
            if marks[place].from == .source { count += 1 }
            place += 1
        }
        return count
    }
}

/// One ask the feed makes of deadwax.
public struct FeedAsk: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// the next page of the order playing, from `offset` (`/shuffle/{token}?offset=`)
        case page(offset: Int)
        /// a fresh order, claimed (`/shuffle?scope=&claim=true`): the next time round under Repeat All - or, after a
        /// 404, the rest of this one (`startedOver`)
        case fresh(startedOver: Bool)
    }

    public let serial: Int
    /// the shuffle playing's token: what the answer is added to
    public let token: String
    public let kind: Kind
    public let scope: PagedScope
    /// the level the shuffle was queued at: the rest of it is queued at it too
    public let level: Level?
    /// the queue's last song, as the ask was made: a fresh order never starts with it
    public let ending: String?
}

/// What the app does with an answer.
public enum FeedStep: Sendable, Equatable {
    /// add `tracks` to the shuffle `token` (QueueController.extendQueue) - `next` the fresh order from then on - and
    /// say `notice` when there is one
    case extend(token: String, tracks: [QueueTrack], next: Paged?, notice: String?)
    /// ask this now (a fresh order, after a 404)
    case ask(FeedAsk)
    /// look again in `ShuffleFeed.retrySeconds`
    case retry
    case nothing
}

/// The feed's state (useShuffleFeed.ts's `asking`, `asks` and its effects): one ask at a time, the newest only. The app
/// calls `look` whenever the queue or Repeat changes, and again for a retry; makes the ask it returns; and hands each
/// answer back to `page`, `gone`, `fresh` or `failed`, carrying out the step. It only ever adds to the queue.
///
/// Another shuffle, none, or Repeat moved off All lets an ask go: the look either asks afresh (another order is
/// another key) or isn't wanted (`letGo`) - each a new serial, so the old ask's answer is dropped. The web keys its ask
/// on Repeat too; here Repeat can't change while an ask is wanted with the key unchanged (with the whole order in,
/// only Repeat All wants one), so the key is the order and where in it.
public struct ShuffleFeedRun: Sendable, Equatable {
    /// what is being asked for - the order and where in it - so a change meanwhile asks nothing twice; nil when nothing
    /// is (every ask made is either still out under it, or answered)
    var asking: String?
    /// the newest ask's: every other's answer is dropped
    var serial = 0
    /// the failed ask's serial while its retry is waited for: its key stays `asking`, so no look asks it again sooner
    var retrying: Int?

    public init() {}

    /// The queue or Repeat changed: the ask to make now, if any.
    public mutating func look(_ queue: UpNextQueue, repeat mode: Repeat) -> FeedAsk? {
        guard let paged = queue.upNext?.paged else { return letGo() }
        let whole = paged.fetched >= paged.total
        let wanted = ShuffleFeed.songsAhead(queue) < ShuffleFeed.below && (!whole || mode == .all)
        guard wanted else { return letGo() }
        let key = "\(paged.token):\(paged.fetched)"
        if asking == key { return nil }
        asking = key
        serial += 1
        return FeedAsk(serial: serial, token: paged.token, kind: whole ? .fresh(startedOver: false) : .page(offset: paged.fetched),
                       scope: paged.scope, level: paged.level, ending: queue.tracks.last?.id)
    }

    /// A page came: its songs added at the shuffle's level.
    public mutating func page(_ ask: FeedAsk, songs: [Song]) -> FeedStep {
        guard ask.serial == serial else { return .nothing }
        return .extend(token: ask.token, tracks: songs.map { ShuffleFeed.track($0, level: ask.level) }, next: nil, notice: nil)
    }

    /// A page's 404: the order gone from deadwax - a fresh one, claimed, as the rest of this round.
    public mutating func gone(_ ask: FeedAsk) -> FeedStep {
        guard ask.serial == serial else { return .nothing }
        return .ask(FeedAsk(serial: ask.serial, token: ask.token, kind: .fresh(startedOver: true), scope: ask.scope,
                            level: ask.level, ending: ask.ending))
    }

    /// A fresh order came - Repeat as it is now (`mode`): a next round asked under Repeat All and landing after Repeat
    /// changed isn't wanted; otherwise its first page, never starting with the song ending, as the shuffle from then on.
    public mutating func fresh(_ ask: FeedAsk, _ first: ShuffleStart, repeat mode: Repeat,
                               random: () -> Double = UpNext.systemRandom) -> FeedStep {
        guard ask.serial == serial else { return .nothing }
        let startedOver = ask.kind == .fresh(startedOver: true)
        if !startedOver && mode != .all {
            asking = nil
            return .nothing
        }
        let tracks = ShuffleFeed.startingElsewhere(first.songs.map { ShuffleFeed.track($0, level: ask.level) },
                                                   ending: ask.ending, random: random)
        return .extend(token: ask.token, tracks: tracks,
                       next: Paged(token: first.token, total: first.total, fetched: 0, scope: ask.scope, level: ask.level),
                       notice: startedOver && !first.songs.isEmpty ? ShuffleWords.startedOver : nil)
    }

    /// An ask failed (not cancelled): asked again `ShuffleFeed.retrySeconds` later, from the same place - and not
    /// before, though the queue moves on meanwhile (the web's: its effect isn't run again by a song changing). Its key
    /// stays what is being asked until `retried`.
    public mutating func failed(_ ask: FeedAsk) -> FeedStep {
        guard ask.serial == serial else { return .nothing }
        retrying = serial
        return .retry
    }

    /// The retry is due (`ShuffleFeed.retrySeconds` after `.retry`): the failed ask let go, for the next look to ask it
    /// again. Nothing when another ask has been made since, or none is wanted - that one stands.
    public mutating func retried() {
        guard retrying == serial else { return }
        retrying = nil
        asking = nil
    }

    /// A new person, or the player stopped: every ask let go.
    public mutating func reset() {
        serial += 1
        asking = nil
    }

    /// No longer wanted: what was being asked let go.
    private mutating func letGo() -> FeedAsk? {
        if asking != nil {
            serial += 1
            asking = nil
        }
        return nil
    }
}

/// The Shuffle while deadwax can't be reached (2.8, question 22): every song on this phone.
public enum ShuffleHere {
    /// The songs of `ids` (those downloaded) that `song` can say - each once, in id order: the player shuffles them.
    public static func songs(_ ids: [String], song: (String) -> Song?) -> [Song] {
        var seen = Set<String>()
        var songs: [Song] = []
        for id in ids.sorted() where seen.insert(id).inserted {
            if let found = song(id) { songs.append(found) }
        }
        return songs
    }
}
