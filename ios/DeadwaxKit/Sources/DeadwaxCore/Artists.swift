import Foundation

// Artists (Phase 4, slice 4 - notes/ios-specs/phase4-library.md 2.6, 3.1 and 6.4): the Library's Artists page and an
// artist's page, as the web's lib/shelves.ts (sortArtistsBy, groupArtists, filterArtists, artistOrderFrom, the index),
// lib/artistPage.ts (artistRows over Navidrome's albums alone, rowLine, playOrder, playsLine, inTurns, albumCountLine),
// lib/yourLibrary.ts (yourArtists) and app/ArtistPage.tsx (its album asks, Play and Shuffle) have them - held to the
// web by Fixtures/artists/artist-vectors.json (ios/scripts/export-artist-vectors.cjs). No MusicBrainz: no discography,
// description, facts, pins or managing (question 4) - the page is their albums in the collection.

/// An artist as deadwax's `GET /deadwax/navidrome/artists` lists them (Navidrome's getArtists, its index flattened) and
/// `/artists/{id}` answers one (getArtist) - only the id needed; anything else the wrong shape read as absent.
public struct Artist: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    /// How many albums Navidrome holds of theirs - absent for one it doesn't count.
    public let albumCount: Int?
    /// Their picture's cover id (the `artist.jpg` deadwax writes, through /cover).
    public let coverArt: String?
    /// OpenSubsonic: the album artist's MusicBrainz id (unused on the phone: no discography, question 4).
    public let musicBrainzId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, albumCount, coverArt, musicBrainzId
    }

    public init(id: String, name: String? = nil, albumCount: Int? = nil, coverArt: String? = nil,
                musicBrainzId: String? = nil) {
        self.id = id
        self.name = name
        self.albumCount = albumCount
        self.coverArt = coverArt
        self.musicBrainzId = musicBrainzId
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        name = fields.looseField(String.self, .name)
        albumCount = fields.looseField(Int.self, .albumCount)
        coverArt = fields.looseField(String.self, .coverArt)
        musicBrainzId = fields.looseField(String.self, .musicBrainzId)
    }

    /// The artist counting `albums` of theirs instead (yourArtists' `{ ...artist, albumCount }`).
    public func counting(_ albums: Int) -> Artist {
        Artist(id: id, name: name, albumCount: albums, coverArt: coverArt, musicBrainzId: musicBrainzId)
    }
}

/// `GET /deadwax/navidrome/artists`: every artist, in Navidrome's order - an artist unreadable left out, no list none.
public struct ArtistList: Decodable, Sendable, Equatable {
    public let artists: [Artist]

    enum CodingKeys: String, CodingKey {
        case artists
    }

    public init(artists: [Artist]) {
        self.artists = artists
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        artists = fields.looseList(Artist.self, .artists) ?? []
    }
}

/// `GET /deadwax/navidrome/artists/{id}`: the artist, as getArtist sends them, with the albums Navidrome has of theirs
/// (`album`, no songs) - `{}` for an artist Navidrome doesn't have (DeadwaxClient's nil).
public struct ArtistWithAlbums: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String?
    public let albumCount: Int?
    public let coverArt: String?
    public let musicBrainzId: String?
    /// Their albums, in Navidrome's order; an album unreadable left out, none `[]`.
    public let album: [Album]

    enum CodingKeys: String, CodingKey {
        case id, name, albumCount, coverArt, musicBrainzId, album
    }

    public init(_ artist: Artist, albums: [Album]) {
        id = artist.id
        name = artist.name
        albumCount = artist.albumCount
        coverArt = artist.coverArt
        musicBrainzId = artist.musicBrainzId
        album = albums
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        name = fields.looseField(String.self, .name)
        albumCount = fields.looseField(Int.self, .albumCount)
        coverArt = fields.looseField(String.self, .coverArt)
        musicBrainzId = fields.looseField(String.self, .musicBrainzId)
        album = fields.looseList(Album.self, .album) ?? []
    }

    /// The artist alone.
    public var artist: Artist {
        Artist(id: id, name: name, albumCount: albumCount, coverArt: coverArt, musicBrainzId: musicBrainzId)
    }
}

// MARK: - the list

/// The Artists page's two orders (ARTIST_ORDERS), kept per phone.
public enum ArtistOrder: String, CaseIterable, Sendable {
    case name
    case albums

    /// Where the order is kept (UserDefaults) - the web's own key (persisted.ts playerArtistOrder).
    public static let storageKey = "deadwax-player-artist-order"

    /// `artistOrderFrom`: Name unless the value is exactly "albums".
    public init(saved: String?) {
        self = saved == ArtistOrder.albums.rawValue ? .albums : .name
    }

    /// The picker's words.
    public var label: String {
        switch self {
        case .name: return "Name"
        case .albums: return "Most albums"
        }
    }
}

/// One artist list as the Artists page draws it: the artists in Navidrome's order, each one's fold key, header and
/// Find text made once as the list lands. Everything else - an order, its groups, what Find keeps - is places in
/// `artists`, as `Shelf` is for albums.
public struct ArtistShelf: Sendable {
    public let artists: [Artist]
    let keys: [FoldKey]
    let initials: [String]
    let findTexts: [FoldKey]

    public init(_ artists: [Artist]) {
        self.artists = artists
        let folded = artists.map { (artist: Artist) -> FoldKey in FoldKey(Fold.key(artist.name)) }
        keys = folded
        initials = folded.map(\.initial)
        findTexts = artists.map { (artist: Artist) -> FoldKey in FoldKey(Fold.findText(artist.name)) }
    }

    public var count: Int { artists.count }

    /// `sortArtistsBy`: Name by deadwax's own folding (a leading "The", accents and case set aside), `#` last (digits,
    /// symbols, other scripts, no name), a tie in Navidrome's order; Most albums most first (an artist Navidrome
    /// didn't count as none), a tie in Navidrome's order.
    public func sorted(_ order: ArtistOrder) -> [Int] {
        let places = Array(artists.indices)
        switch order {
        case .name:
            return places.sorted { (a: Int, b: Int) -> Bool in
                let named = Shelf.byName(keys[a], initials[a], keys[b], initials[b])
                return named != 0 ? named < 0 : a < b
            }
        case .albums:
            return places.sorted { (a: Int, b: Int) -> Bool in
                let first = artists[a].albumCount ?? 0
                let second = artists[b].albumCount ?? 0
                return first != second ? first > second : a < b
            }
        }
    }

    /// `groupArtists`: by Name's first letter (`#` for the rest), or one unlabelled group for Most albums. An empty
    /// list has none.
    public func groups(_ sorted: [Int], _ order: ArtistOrder) -> [ShelfGroup] {
        if sorted.isEmpty { return [] }
        switch order {
        case .name:
            let initials = self.initials
            return Shelf.runs(sorted, key: { (place: Int) -> String in initials[place] },
                              label: { (place: Int) -> String? in initials[place] })
        case .albums:
            return [ShelfGroup(key: "all", label: nil, items: sorted)]
        }
    }

    /// `filterArtists`: the artists whose name holds every word typed, in any order, as runs of code units (Find's
    /// folding). Nothing typed (or spaces): everything.
    public func filter(_ sorted: [Int], typed: String) -> [Int] {
        let words = Find.words(typed)
        if words.isEmpty { return sorted }
        let texts = findTexts
        return sorted.filter { (place: Int) -> Bool in words.allSatisfy { texts[place].contains($0) } }
    }

    /// Everything one Artists page draws for an order and what is typed into Find (LibrarySection.tsx ArtistSection).
    /// Pass the `sorted` list already made for this order to keep from sorting again as Find changes.
    public func view(_ order: ArtistOrder, typed: String, sorted: [Int]? = nil) -> ShelfView {
        let sorted = sorted ?? self.sorted(order)
        let finding = Find.finding(typed)
        let found = finding ? filter(sorted, typed: typed) : sorted
        let groups = self.groups(found, order)
        let index = ShelfIndex.shows(order, count: sorted.count, typed: typed) ? ShelfIndex.entries(groups, order) : nil
        let count = finding ? Find.filteredCountText(shown: found.count, total: sorted.count, one: "artist", many: "artists")
            : Find.countText(sorted.count, one: "artist", many: "artists")
        return ShelfView(sorted: sorted, found: found, groups: groups, index: index, countText: count)
    }
}

/// Your artists (lib/yourLibrary.ts `yourArtists`): Navidrome's artists that your albums name as their album artist,
/// each counting your albums of theirs, in Navidrome's order.
public enum YourArtists {
    public static func of(_ artists: [Artist], albums: [IndexAlbum]) -> [Artist] {
        of(artists, artistIds: albums.map(\.artistId))
    }

    /// The same over the albums' artist ids (nil or "" naming nobody).
    public static func of(_ artists: [Artist], artistIds: [String?]) -> [Artist] {
        var counts: [String: Int] = [:]
        for id in artistIds {
            guard let id, !id.isEmpty else { continue }
            counts[id, default: 0] += 1
        }
        return artists.compactMap { (artist: Artist) -> Artist? in
            guard let count = counts[artist.id] else { return nil }
            return artist.counting(count)
        }
    }
}

/// The Artists page's words, verbatim from the web (lib/appFrame.ts, app/LibrarySection.tsx, lib/yourLibrary.ts,
/// lib/artistPage.ts) - and the phone's own, offline.
public enum ArtistWords {
    /// The switch's page, and the list's title without a library of your own (libraryTitle('artists')).
    public static let artists = "Artists"
    /// With a library of your own: the page is yours, and All music's is the collection's.
    public static let yourArtists = "Your artists"
    public static let allArtists = "All artists"

    /// The page's title (`libraryTitle`): "Your artists" or "All artists" with a library of your own, else "Artists".
    public static func title(_ scope: AlbumScope, personal: Bool) -> String {
        guard personal else { return artists }
        return scope == .yours ? yourArtists : allArtists
    }

    /// Find's placeholder, and the order picker's label.
    public static let findPlaceholder = "Find in artists"
    public static let sortLabel = "Artist order"
    /// The collection's list empty (NO_ARTISTS), and Your artists with nothing in your library (NO_ARTISTS_OF_YOURS -
    /// over LibraryWords.emptyLibraryHow and See All music, as the web's EmptyLibrary).
    public static let noArtists = "No artists yet."
    public static let noArtistsOfYours = "No artists in your library yet."
    /// The artist page's heading over their albums.
    public static let albumsHeading = "Albums"

    /// "No artists match “bjrk”."
    public static func noMatch(_ typed: String) -> String { Find.noMatchText("artists", typed: typed) }

    /// `albumCountLine`: "2 albums in your library", "1 album in the collection", "12 albums" for no `place` - ""
    /// for none, or an artist Navidrome didn't count.
    public static func albumCountLine(_ count: Int?, place: String = Whose.inYourLibrary) -> String {
        let albums = count ?? 0
        guard albums > 0 else { return "" }
        return "\(albums) \(albums == 1 ? "album" : "albums")" + (place.isEmpty ? "" : " \(place)")
    }

    /// A row's count's place (LibraryViews.tsx ArtistRow): none inside your own list or without a library of your own
    /// (the count alone); "in the collection" for All artists with one.
    public static func countPlace(_ scope: AlbumScope, personal: Bool) -> String {
        personal && scope == .store ? Whose.inTheCollection : ""
    }

    /// The phone's own, while deadwax can't be reached and no list is in hand: the artists of the albums on this phone
    /// stand in, under this note.
    public static let offlineList = "Only the artists of downloaded albums show until deadwax is back."
}

// MARK: - an artist's page

/// An artist's page (ArtistPage.tsx, with lib/artistPage.ts's rules): their albums in the collection newest first, the
/// line under Play and Shuffle, how many albums are asked for at once and how many artists' answers are kept.
public enum ArtistPage {
    /// PREFETCH_AT_ONCE: their albums asked for this many at a time, in the page's order.
    public static let atOnce = 4
    /// ARTISTS_KEPT: the answers kept for Back (the app's memory, as the web's session).
    public static let kept = 20

    /// One row: an album of theirs Navidrome has (artistRows over Navidrome's albums alone, `album:<id>`).
    public struct Row: Sendable, Equatable, Identifiable {
        /// `album:<id>` - stable as answers land.
        public let key: String
        public let title: String
        /// The year as words ("1994"), nil for none (0, absent).
        public let year: String?
        public let albumId: String
        public let coverArt: String?
        /// You starred it - in your library, with a library of your own.
        public let yours: Bool

        public var id: String { key }

        public init(key: String, title: String, year: String?, albumId: String, coverArt: String?, yours: Bool) {
            self.key = key
            self.title = title
            self.year = year
            self.albumId = albumId
            self.coverArt = coverArt
            self.yours = yours
        }
    }

    /// `artistRows(held, null, null)`: one row per album (an id twice, once - the first), the newest year first, the
    /// undated last, then by title. The year's order is its words' (as the web compares them: "999" before "2008"),
    /// a tie by the folded title, then by the row's key.
    ///
    /// The web breaks those last two ties with `localeCompare` - ICU's collation, which nothing on Linux has: here
    /// the folded titles compare by code unit (the same for every pair whose folding leaves ASCII - accents, case and
    /// a leading "The" folded away) and the keys as ASCII collates them (`asciiCollate`). Two albums of one year under
    /// titles in other scripts may stand in another order than the web's; the fixture holds only pairs where the two
    /// agree (export-artist-vectors.cjs checks every one).
    public static func rows(_ albums: [Album]) -> [Row] {
        var seen = Set<String>()
        var rows: [(row: Row, title: FoldKey)] = []
        for album in albums where seen.insert(album.id).inserted {
            let year = album.year.flatMap { (year: Int) -> String? in year > 0 ? String(year) : nil }
            let row = Row(key: "album:\(album.id)", title: album.name ?? "", year: year, albumId: album.id,
                          coverArt: album.coverArt, yours: album.isStarred)
            rows.append((row, FoldKey(Fold.key(row.title))))
        }
        return rows.sorted { (a: (row: Row, title: FoldKey), b: (row: Row, title: FoldKey)) -> Bool in
            switch (a.row.year, b.row.year) {
            case (nil, .some): return false
            case (.some, nil): return true
            case let (.some(first), .some(second)) where first != second:
                return FoldKey(second) < FoldKey(first)
            default: break
            }
            if a.title != b.title { return a.title < b.title }
            return asciiCollate(a.row.key, b.row.key) < 0
        }.map { (pair: (row: Row, title: FoldKey)) -> Row in pair.row }
    }

    /// Two keys as ICU collates ASCII: letters by their case folded (digits before letters, as code units have them),
    /// then - nothing else differing - the first place their case does, the lowercase first; then by code unit.
    static func asciiCollate(_ a: String, _ b: String) -> Int {
        func lower(_ unit: UInt16) -> UInt16 { unit >= 0x41 && unit <= 0x5A ? unit + 0x20 : unit }
        let first = Array(a.utf16)
        let second = Array(b.utf16)
        let folded = (first.map(lower), second.map(lower))
        if folded.0 != folded.1 { return folded.0.lexicographicallyPrecedes(folded.1) ? -1 : 1 }
        for (one, other) in zip(first, second) where one != other {
            return lower(one) == one ? -1 : 1
        }
        if first == second { return 0 }
        return first.lexicographicallyPrecedes(second) ? -1 : 1
    }

    /// `rowLine`: "1994 · in your library" - with a library of your own, an album you haven't starred "in the
    /// collection" (heldPhrase).
    public static func line(_ row: Row, personal: Bool) -> String {
        [row.year, Whose.heldPhrase(personal: personal, yours: row.yours)].compactMap { $0 }.joined(separator: " · ")
    }

    /// The row's tick (ArtistPage.tsx's): held - every row here is - and yours, or every one without a library of your
    /// own.
    public static func marked(_ row: Row, personal: Bool) -> Bool {
        !personal || row.yours
    }

    /// `playOrder`: what Play and Shuffle play - each row's album once, in the page's order (an empty id none).
    public static func playOrder(_ rows: [Row]) -> [String] {
        var seen = Set<String>()
        return rows.compactMap { (row: Row) -> String? in
            !row.albumId.isEmpty && seen.insert(row.albumId).inserted ? row.albumId : nil
        }
    }

    /// What Navidrome has said of their albums (`library`): still asking, answered, or failed.
    public enum Library: String, Sendable, Equatable {
        case asking, done, failed
    }

    /// `playsLine`, under Play and Shuffle: "Plays the 2 albums you have" - with some not answered yet, or that didn't
    /// load, how many; with nothing to play, what Navidrome said. `personal`: their albums are the collection's.
    public static func playsLine(albums: Int, inHand: Int, settled: Bool, library: Library = .done,
                                 personal: Bool = false) -> String {
        let had = personal ? Whose.inTheCollection : "you have"
        if albums == 0 {
            switch library {
            case .asking: return "Looking for their albums \(personal ? Whose.inTheCollection : Whose.inYourLibrary)\u{2026}"
            case .done: return "None of their albums are here to play."
            case .failed: return ""
            }
        }
        let all = albums == 1 ? "Plays the album \(had)" : "Plays the \(albums) albums \(had)"
        if !settled { return "Getting the songs of the \(albums == 1 ? "album" : "\(albums) albums") \(had)\u{2026}" }
        if inHand >= albums { return all }
        if inHand == 0 { return "Couldn't load their songs." }
        return "Plays \(inHand) of the \(albums) albums \(had) - the rest didn't load"
    }
}

/// `inTurns`: items started `limit` at a time (one at least), the next as each settles - answered or failed - and only
/// while `going` (a newer set superseding this one stops it). As a state the app drives: `begin` gives the first
/// places to start, `settled` the next (nil for none).
public struct InTurns: Sendable, Equatable {
    public let count: Int
    public let limit: Int
    /// The next place to start.
    public private(set) var next = 0

    public init(count: Int, limit: Int) {
        self.count = count
        self.limit = limit
    }

    /// The first: up to `max(1, limit)`, each asking `going` before it starts.
    public mutating func begin(going: () -> Bool = { true }) -> [Int] {
        var started: [Int] = []
        for _ in 0..<max(1, limit) {
            if let place = more(going: going) { started.append(place) }
        }
        return started
    }

    /// One started has settled: the next to start, if there is one and it is still going.
    public mutating func settled(going: () -> Bool = { true }) -> Int? {
        more(going: going)
    }

    private mutating func more(going: () -> Bool) -> Int? {
        guard next < count, going() else { return nil }
        next += 1
        return next - 1
    }
}

/// The artist page's album asks (ArtistPage.tsx's prefetch): every album Play plays asked for as it is known,
/// `ArtistPage.atOnce` at a time in the page's order, so Play and Shuffle have every song in hand at the tap (the
/// gesture rule) - an album that won't come left out and said so under the buttons, Try again asking those again.
/// Asked anew only when the albums are others (the web's `playKey`, their ids sorted); what is in hand stays. Only the
/// newest round's answers count.
public struct ArtistAlbumAsks<Answer: Sendable>: Sendable {
    /// One ask: the album, and the round it belongs to.
    public struct Ask: Sendable, Hashable {
        public let id: String
        public let round: Int
    }

    /// The albums Play plays, in the page's order.
    public private(set) var order: [String] = []
    public private(set) var ready: [String: Answer] = [:]
    /// The albums that didn't come this round.
    public private(set) var unsent: Set<String> = []
    private var round = 0
    private var key: String?
    private var wanted: [String] = []
    private var turns = InTurns(count: 0, limit: ArtistPage.atOnce)

    public init() {}

    /// The page's albums as they are now (`ArtistPage.playOrder`): the asks to make, when they are other albums than
    /// before - none otherwise.
    public mutating func want(_ order: [String]) -> [Ask] {
        self.order = order
        let key = order.sorted { (a: String, b: String) -> Bool in FoldKey(a) < FoldKey(b) }.joined(separator: "\n")
        guard key != self.key else { return [] }
        self.key = key
        return start()
    }

    /// An album answered: kept, and the next ask.
    public mutating func answered(_ ask: Ask, with answer: Answer) -> [Ask] {
        guard ask.round == round else { return [] }
        ready[ask.id] = answer
        return next()
    }

    /// An album that wouldn't come: left out, and the next ask.
    public mutating func failed(_ ask: Ask) -> [Ask] {
        guard ask.round == round else { return [] }
        unsent.insert(ask.id)
        return next()
    }

    /// Try again: the albums that didn't come asked for again.
    public mutating func again() -> [Ask] {
        unsent = []
        return start()
    }

    private mutating func start() -> [Ask] {
        round += 1
        wanted = order.filter { (id: String) -> Bool in ready[id] == nil }
        turns = InTurns(count: wanted.count, limit: ArtistPage.atOnce)
        let round = self.round
        let wanted = self.wanted
        return turns.begin().map { (place: Int) -> Ask in Ask(id: wanted[place], round: round) }
    }

    private mutating func next() -> [Ask] {
        guard let place = turns.settled() else { return [] }
        return [Ask(id: wanted[place], round: round)]
    }

    /// The albums in hand, in the page's order.
    public var inHand: [String] { order.filter { (id: String) -> Bool in ready[id] != nil } }
    /// Every album has answered or failed.
    public var settled: Bool { order.allSatisfy { (id: String) -> Bool in ready[id] != nil || unsent.contains(id) } }
    /// Play and Shuffle can play: settled, and something in hand.
    public var playable: Bool { settled && !inHand.isEmpty }
    /// Some didn't load: Try again is offered under the line.
    public var someMissing: Bool { settled && inHand.count < order.count }
    /// The answers in hand, in the page's order.
    public var answers: [Answer] { order.compactMap { (id: String) -> Answer? in ready[id] } }

    /// The line under the buttons.
    public func line(library: ArtistPage.Library, personal: Bool) -> String {
        ArtistPage.playsLine(albums: order.count, inHand: inHand.count, settled: settled, library: library,
                             personal: personal)
    }
}

/// Play and Shuffle from an artist's page (ArtistPage.tsx `play`): every album in hand in the page's order, each song
/// with its own album; Play at the album level from the first song, Shuffle at the songs level, anywhere - and every
/// album remembered (rememberQueue). Nil with no song to play.
public enum ArtistPlay {
    public static func plan(_ albums: [Album], shuffle: Bool, setting: Normalization)
        -> (tracks: [QueueTrack], albums: [Album], start: Int?)? {
        let level = levelFor(setting, shuffle ? .songs : .album)
        let tracks = albums.flatMap { (album: Album) -> [QueueTrack] in
            (album.song ?? []).map { (song: Song) -> QueueTrack in
                QueueTrack(song: song, albumId: album.id, albumName: album.name ?? "", albumArtist: album.artist,
                           albumCoverArt: album.coverArt, level: level)
            }
        }
        guard !tracks.isEmpty else { return nil }
        return (tracks, albums, shuffle ? nil : 0)
    }
}

/// An artist's page and the Artists page while deadwax can't be reached (3.1's rule, the phone's own): what the phone
/// has in hand stands in - the answer kept in memory, else the albums downloaded - and only songs on this phone play.
public enum ArtistOffline {
    /// The albums the page lists: the artist's answer when one is in hand, else the downloaded albums naming them as
    /// album artist (kept answers, in the order given).
    public static func albums(answer: ArtistWithAlbums?, artistId: String, downloaded: [Album]) -> [Album] {
        if let answer { return answer.album }
        return downloaded.filter { (album: Album) -> Bool in album.artistId == artistId }
    }

    /// What Play and Shuffle play offline: each album in the page's order, as its kept answer has it, with only the
    /// songs on this phone - an album with none left out.
    public static func playable(_ order: [String], album: (String) -> Album?, here: (String) -> Bool) -> [Album] {
        order.compactMap { (id: String) -> Album? in
            guard let kept = album(id) else { return nil }
            let songs = (kept.song ?? []).filter { (song: Song) -> Bool in here(song.id) }
            return songs.isEmpty ? nil : PlaylistPlay.with(kept, songs: songs)
        }
    }

    /// The Artists page with no list in hand: an artist per album artist of the albums on this phone, in the albums'
    /// order (where each first appears), uncounted and pictureless (Navidrome's list would say).
    ///
    /// An album names its album artist only as its display line (`album.artist`), which is the credit - "A & B" for
    /// an album A made with B, under A's id. So each artist is named as most of their albums here name them, a tie
    /// going to the shortest name (the credit holding the most is the longest), then to the first seen; an album
    /// naming nobody (nil or "") counts for none, and an artist only such albums name has no name.
    public static func artists(_ downloaded: [IndexAlbum]) -> [Artist] {
        var order: [String] = []
        var names: [String: [(name: String, albums: Int)]] = [:]
        for album in downloaded {
            guard let id = album.artistId, !id.isEmpty else { continue }
            if names[id] == nil {
                order.append(id)
                names[id] = []
            }
            guard let name = album.artist, !name.isEmpty else { continue }
            if let place = names[id]?.firstIndex(where: { (each: (name: String, albums: Int)) -> Bool in each.name == name }) {
                names[id]?[place].albums += 1
            } else {
                names[id]?.append((name, 1))
            }
        }
        return order.map { (id: String) -> Artist in
            Artist(id: id, name: name(among: names[id] ?? []))
        }
    }

    /// The name most albums give, a tie to the shortest, then to the first seen; nil for none.
    static func name(among tally: [(name: String, albums: Int)]) -> String? {
        var best: (name: String, albums: Int)?
        for each in tally {
            guard let chosen = best else {
                best = each
                continue
            }
            if each.albums > chosen.albums || (each.albums == chosen.albums && each.name.count < chosen.name.count) {
                best = each
            }
        }
        return best?.name
    }
}

/// The Artists page with no list to draw (the app's ArtistsScreen): why, said with Try again - the artists' ask failed,
/// or, for Your artists, the ask for your albums (whose artists they are, and their counts) - or nil while both may
/// still come (the spinner). Your albums' failure counts only for Your artists: All artists and Artists don't need them.
public enum ArtistsWaiting {
    public static func failure(artists: (any Error)?, yourAlbums: (any Error)?, yours: Bool) -> (any Error)? {
        artists ?? (yours ? yourAlbums : nil)
    }
}

/// The album page's artist line (AlbumPage.tsx): a link to the artist when the album names one and their name; plain
/// once the album has answered without one, or once no answer is coming (it failed, it is gone, or deadwax can't be
/// reached with nothing of it on this phone - the web's `shown = preview` without an id); and, while it might still
/// become a link, drawn as one would be but not tappable - so it never flashes from grey to the link's colour.
public enum ArtistLink: Sendable, Equatable {
    case link(id: String)
    case pending
    case plain

    /// `album`: the album's answer (nil while it hasn't come); `opened`: the artist id the opener knew; `name` the
    /// line's words; `coming`: with no answer in hand, whether one may still come (false once the album's load failed,
    /// it is gone, or deadwax can't be reached and nothing of it is on this phone).
    public static func of(album: Album?, opened: String?, name: String, coming: Bool) -> ArtistLink {
        // `shown?.artistId ?? album?.artistId`, shown = album ?? preview: the album's own once it has answered
        let id = album != nil ? album?.artistId : opened
        if let id, !id.isEmpty, !name.isEmpty { return .link(id: id) }
        return album == nil && coming ? .pending : .plain
    }
}
