import Foundation

// The albums' Most played order on an artist's page (Last.fm, slice A2 - deadwax-plans/lastfm.md 3.3; notes/ios.md
// "Last.fm, slice A2"): the Albums heading's menu, "Newest first" or "Most played", the choice kept per device; each
// row's plays from Last.fm's albums by plays (`LastfmArtist.topAlbums`); and the order they make, judged once for the
// visit so nothing moves under a finger.

/// The albums' order (lastfm.md 3.3), per device: UserDefaults `deadwax-artist-album-order`, `newest` or `played` -
/// read with care, anything else newest.
public enum AlbumOrder: String, Sendable, Equatable, CaseIterable {
    /// The page's own order, and the default: the newest first, the undated last (ArtistJoin.rows).
    case newest
    /// The rows with Last.fm plays first, most first; ties and the rest as newest first.
    case played

    public static let storageKey = "deadwax-artist-album-order"

    /// The stored word: `played` is Most played, anything else - none, an old word, a typo - Newest first.
    public init(saved: String?) {
        self = saved == AlbumOrder.played.rawValue ? .played : .newest
    }

    /// The menu's words for it.
    public var words: String {
        switch self {
        case .newest: return LastfmWords.newestFirst
        case .played: return LastfmWords.mostPlayed
        }
    }
}

/// Plays per row and the Most played order (lastfm.md 3.3) - over the page's rows as Studio only leaves them, never
/// adding one: Last.fm's albums are counted against the rows, they are not rows.
///
/// - **Plays per row** (`of`): an album of yours by Last.fm's album `mbid` equal to the album's `musicBrainzId`, else
///   by its folded title (Fold.key) equal to Last.fm's; one of theirs by the folded group title. Several of Last.fm's
///   albums on one row ("Currents" and "Currents (B-Sides)" fold together) give it THE LARGEST, never a sum. The list's
///   count is its first album's kind (plays, or listeners where Last.fm gave none); an album of another kind is left
///   out - plays are never set beside listeners. A count of 0 is no plays.
/// - **Most played** (`ordered`): the rows with plays first, most first; ties, and the rows with none, in the order
///   given (newest first).
/// - **The visit** (`Visit`): the albums the page orders by are the answer in hand as the albums are first drawn -
///   inside the page's wait (LastfmPage.Arrival) whenever Top Songs comes in place. An answer later than that leaves
///   the visit newest first, and so it stays; a pull to refresh takes the next answer, and choosing Most played in the
///   menu the answer in hand at once (the person asked for the rows to move).
public enum AlbumPlays {
    /// The kind of count of an answer's albums, and the albums of it - nil for no usable albums (Last.fm not enabled,
    /// none listed). The first album's kind is the list's.
    public static func counted(_ answer: LastfmArtist?) -> [LastfmAlbum]? {
        guard let answer, answer.enabled, let albums = answer.topAlbums, let kind = albums.first?.counted else {
            return nil
        }
        let ofKind = albums.filter { (album: LastfmAlbum) -> Bool in album.counted == kind }
        return ofKind.isEmpty ? nil : ofKind
    }

    /// Whether the menu offers Most played: the answer in hand has albums by plays.
    public static func offered(_ answer: LastfmArtist?) -> Bool {
        counted(answer) != nil
    }

    /// Each row's plays, by its key (`album:<id>`, `group:<id>`) - rows Last.fm has no plays for left out. `albums` is
    /// the page's albums of yours (their `musicBrainzId`, by the row's album id).
    public static func of(_ rows: [ArtistJoin.Row], lastfm: [LastfmAlbum], albums: [Album]) -> [String: Int] {
        guard let kind = lastfm.first?.counted else { return [:] }
        // keyed by FoldKey - UTF-16 units, as the rest of Core compares fold keys (A2's review)
        var byMbid: [FoldKey: Int] = [:]
        var byTitle: [FoldKey: Int] = [:]
        for album in lastfm where album.counted == kind && album.plays > 0 {
            if let mbid = album.mbid.map(FoldKey.init) { byMbid[mbid] = max(byMbid[mbid] ?? 0, album.plays) }
            let key = FoldKey(Fold.key(album.title))
            if !key.units.isEmpty { byTitle[key] = max(byTitle[key] ?? 0, album.plays) }
        }
        var release: [String: FoldKey] = [:]
        for album in albums {
            if let mbid = MBID.of(album.musicBrainzId), release[album.id] == nil { release[album.id] = FoldKey(mbid) }
        }
        let titled = byTitle
        let titledPlays = { (title: String) -> Int? in
            let key = FoldKey(Fold.key(title))
            return key.units.isEmpty ? nil : titled[key]
        }
        var plays: [String: Int] = [:]
        for row in rows {
            let found: Int?
            switch row {
            case .yours(let mine):
                // the release's id first, its folded title only without one Last.fm has
                found = release[mine.albumId].flatMap { (mbid: FoldKey) -> Int? in byMbid[mbid] } ?? titledPlays(mine.title)
            case .theirs(let other):
                found = titledPlays(other.group.title ?? other.title)
            }
            if let found { plays[row.key] = found }
        }
        return plays
    }

    /// Most played: the rows with plays first, most first; ties and the rest in the order given - the same rows, none
    /// added, none dropped.
    public static func ordered(_ rows: [ArtistJoin.Row], plays: [String: Int]) -> [ArtistJoin.Row] {
        var counted: [(at: Int, plays: Int)] = []
        var rest: [ArtistJoin.Row] = []
        for at in rows.indices {
            if let count = plays[rows[at].key] {
                counted.append((at, count))
            } else {
                rest.append(rows[at])
            }
        }
        let first = counted.sorted { (a: (at: Int, plays: Int), b: (at: Int, plays: Int)) -> Bool in
            a.plays != b.plays ? a.plays > b.plays : a.at < b.at
        }
        return first.map { (one: (at: Int, plays: Int)) -> ArtistJoin.Row in rows[one.at] } + rest
    }

    /// What the Albums list draws: its rows in the order shown, and - in Most played order - each row's plays in words
    /// ("4.1M plays"), by its key.
    public struct Shown: Sendable, Equatable {
        public let rows: [ArtistJoin.Row]
        /// The order drawn: Most played only when chosen and the visit has albums to order by.
        public let order: AlbumOrder
        public let plays: [String: String]

        public init(rows: [ArtistJoin.Row], order: AlbumOrder, plays: [String: String]) {
            self.rows = rows
            self.order = order
            self.plays = plays
        }

        /// A row's line, in Most played order led by its plays: "4.1M plays · 2015 · in your library". First, so the
        /// number the list is sorted by is never the part a one-line row cuts (A2's review: at the end, "2012 · in the
        /// collection · 2 pressings · 65M plays" outgrew a phone's 271 points at the default size, and nearly every row
        /// at xxxLarge).
        public func line(_ row: ArtistJoin.Row, _ line: String) -> String {
            guard let plays = plays[row.key] else { return line }
            return line.isEmpty ? plays : "\(plays) · \(line)"
        }

        /// How many lines a phone's row of `row` may take: two for one with plays at the accessibility sizes (where
        /// "999K listeners" alone outgrows a line at AX5), so they wrap rather than being cut; else one, as drawn.
        public func lines(_ row: ArtistJoin.Row, accessibility: Bool) -> Int {
            accessibility && plays[row.key] != nil ? 2 : 1
        }
    }

    /// The Albums list as drawn: `chosen` the menu's order, `visit` the albums the visit orders by (Visit.albums).
    /// Newest first: the rows as given, nothing at their ends.
    public static func shown(_ rows: [ArtistJoin.Row], chosen: AlbumOrder, visit: [LastfmAlbum]?,
                             albums: [Album]) -> Shown {
        guard chosen == .played, let visit, let kind = visit.first?.counted else {
            return Shown(rows: rows, order: .newest, plays: [:])
        }
        let plays = of(rows, lastfm: visit, albums: albums)
        let words = plays.mapValues { (count: Int) -> String in LastfmWords.plays(count, counted: kind) }
        return Shown(rows: ordered(rows, plays: plays), order: .played, plays: words)
    }

    /// `shown`, made once for what it is made from: the page is drawn again as each album's songs land.
    public struct Made: Sendable {
        private var made: (rows: [ArtistJoin.Row], chosen: AlbumOrder, visit: [LastfmAlbum]?, albums: [Album],
                           shown: Shown)?

        public init() {}

        public mutating func shown(_ rows: [ArtistJoin.Row], chosen: AlbumOrder, visit: [LastfmAlbum]?,
                                   albums: [Album]) -> Shown {
            if let made, made.chosen == chosen, made.visit == visit, made.rows == rows, made.albums == albums {
                return made.shown
            }
            let shown = AlbumPlays.shown(rows, chosen: chosen, visit: visit, albums: albums)
            made = (rows, chosen, visit, albums, shown)
            return shown
        }
    }

    /// Which albums a visit to the page orders by - judged once, as the albums are first drawn.
    public struct Visit: Sendable, Equatable {
        /// The albums by plays the visit orders by (`counted`) - nil for none: the visit is newest first.
        public private(set) var albums: [LastfmAlbum]?
        /// Judged: the albums were drawn, so an answer now doesn't move them.
        public private(set) var judged = false

        public init() {}

        /// The albums drawn for the first time (the page's wait over): the answer in hand then. Once only - an answer
        /// that comes after leaves the visit as it is.
        public mutating func drawn(_ answer: LastfmArtist?) {
            guard !judged else { return }
            judged = true
            albums = AlbumPlays.counted(answer)
        }

        /// A pull to refresh: the next answer is judged again (the albums in hand kept until it comes).
        public mutating func reopen() {
            judged = false
        }

        /// Most played chosen in the menu: the answer in hand at once.
        public mutating func chose(_ answer: LastfmArtist?) {
            judged = true
            albums = AlbumPlays.counted(answer)
        }

        /// (A2's review) Whether the menu offers Most played, read with the order drawn: the visit's albums (the rows
        /// may be in Most played order by them), or the answer in hand's (choosing it would order them) - so the menu
        /// is never hidden while the rows are in Most played order.
        public func offers(_ answer: LastfmArtist?) -> Bool {
            albums != nil || AlbumPlays.offered(answer)
        }
    }
}

/// (A2's review) An artist page's visit as Last.fm's answer comes, event by event - what ArtistPageModel drives: A1's
/// arrival (LastfmPage.Arrival: whether what lies below Play waits, where Top Songs goes) and the albums' order judged
/// with it (AlbumPlays.Visit), so the order's timing is Core's and tested here, not only read in the model's source.
///
/// - Begun with nothing to wait for (an answer the session keeps): the albums drawn at once, by it.
/// - No ask can be made (Last.fm not on, deadwax out of reach): released, the albums drawn by what is in hand.
/// - An ask begins: a pull's reopens the visit (judged again by the answer it brings); any other ask doesn't.
/// - An answer lands: placed (A1's rule), then the albums drawn by it - if they weren't yet: inside the wait it orders
///   them, after the wait nothing moves.
/// - The wait is over: released, the albums drawn by what is in hand - an answer after this leaves them as drawn.
/// - Most played chosen: the answer in hand at once.
public struct LastfmVisit: Sendable, Equatable {
    public private(set) var arrival: LastfmPage.Arrival
    public private(set) var albums = AlbumPlays.Visit()

    public init(arrival: LastfmPage.Arrival, answer: LastfmArtist?) {
        self.arrival = arrival
        if arrival.released { albums.drawn(answer) }
    }

    /// No ask can be made: everything drawn now, by `answer` (the one in hand).
    public mutating func unasked(_ answer: LastfmArtist?) {
        arrival.release()
        albums.drawn(answer)
    }

    /// An ask begins - `pulled` for a pull to refresh.
    public mutating func asking(pulled: Bool) {
        if pulled { albums.reopen() }
    }

    /// An answer landed (`answer`: the page's answer now, the landed one kept part by part over the one before).
    public mutating func answered(_ answer: LastfmArtist?) {
        arrival.answered(present: LastfmPage.present(answer))
        albums.drawn(answer)
    }

    /// `LastfmPage.waitMs` passed: everything drawn now, by `answer` (the one in hand).
    public mutating func waited(_ answer: LastfmArtist?) {
        arrival.release()
        albums.drawn(answer)
    }

    /// Most played chosen in the menu.
    public mutating func chose(_ answer: LastfmArtist?) {
        albums.chose(answer)
    }
}
