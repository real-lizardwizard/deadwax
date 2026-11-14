import Foundation

// Search's one list, your library's half (Phase 5, slice 1 - notes/ios-specs/phase5-search.md 2.2-2.8): the web's
// ui/src/lib/searchList.ts (the rows, whose, the pool and the sections, Top results, the lines, the words),
// ui/src/lib/searchResults.ts (the hint, the busy words, the prefetch, the artist's count), ui/src/lib/whose.ts
// (navidromeYours, libraryPlace) and ui/src/lib/songs.ts' titleKey - the library's rows only: MusicBrainz's rows,
// phantoms and the moments come with slice 2 on. Held to the web by Fixtures/search/search-vectors.json
// (ios/scripts/export-search-vectors.cjs), which runs the web's own functions.

// MARK: kinds and views

/// A section's kind, in the list's order (`KINDS`).
public enum SearchKind: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case artists, albums, songs

    public var id: String { rawValue }

    /// The order Top results compare kinds in (`KIND_RANK`).
    var rank: Int {
        switch self {
        case .artists: return 0
        case .albums: return 1
        case .songs: return 2
        }
    }
}

/// What the list shows: everything, or one kind in full (the chips).
public enum SearchView: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case all, artists, albums, songs

    public var id: String { rawValue }

    /// The kind a kind view shows - nil for All.
    public var kind: SearchKind? {
        switch self {
        case .all: return nil
        case .artists: return .artists
        case .albums: return .albums
        case .songs: return .songs
        }
    }

    public init(_ kind: SearchKind) {
        switch kind {
        case .artists: self = .artists
        case .albums: self = .albums
        case .songs: self = .songs
        }
    }
}

// MARK: what search3 answers

/// `GET /deadwax/navidrome/search` as Search reads it: search3's artists, albums and songs, each in Navidrome's order -
/// read leniently, a kind missing or unreadable none, a row that can't be read left out. (Songs reads the same route
/// through `SearchResult`, which the contract test pins as albums and songs alone.)
public struct LibraryResults: Decodable, Sendable, Equatable {
    public let artists: [Artist]
    public let albums: [Album]
    public let songs: [Song]

    enum CodingKeys: String, CodingKey {
        case artists, albums, songs
    }

    public init(artists: [Artist] = [], albums: [Album] = [], songs: [Song] = []) {
        self.artists = artists
        self.albums = albums
        self.songs = songs
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        artists = fields.looseList(Artist.self, .artists) ?? []
        albums = fields.looseList(Album.self, .albums) ?? []
        songs = fields.looseList(Song.self, .songs) ?? []
    }

    /// How many of each kind it holds - what the list's words count.
    public var counts: [SearchKind: Int] { [.artists: artists.count, .albums: albums.count, .songs: songs.count] }
}

/// How many of each kind search3 is asked for, from where (`searchLibrary`'s counts and offsets).
public struct SearchCounts: Sendable, Equatable, Hashable {
    public let artists: Int
    public let albums: Int
    public let songs: Int

    public init(artists: Int, albums: Int, songs: Int) {
        self.artists = artists
        self.albums = albums
        self.songs = songs
    }

    public subscript(kind: SearchKind) -> Int {
        switch kind {
        case .artists: return artists
        case .albums: return albums
        case .songs: return songs
        }
    }

    /// This kind at `count`, the others 0 (a kind view's own, and its More's offsets).
    public static func only(_ kind: SearchKind, _ count: Int) -> SearchCounts {
        SearchCounts(artists: kind == .artists ? count : 0, albums: kind == .albums ? count : 0,
                     songs: kind == .songs ? count : 0)
    }

    public static let none = SearchCounts(artists: 0, albums: 0, songs: 0)
}

/// The numbers Search asks by (api.ts SEARCH_COUNTS, searchList.ts CHIP_LIBRARY_COUNTS, TOP_RESULTS and PREVIEW for a
/// phone, searchResults.ts SONG_ALBUMS_PREFETCHED). tests/test_ios_contract.py holds each within the route's bounds.
public enum SearchPacing {
    /// All's search3: 5 artists, 8 albums, 12 songs.
    public static let artistCount = 5
    public static let albumCount = 8
    public static let songCount = 12
    /// A kind view's own: 50 artists, 50 albums, 100 songs.
    public static let chipArtistCount = 50
    public static let chipAlbumCount = 50
    public static let chipSongCount = 100
    /// Top results on a phone.
    public static let topResults = 3
    /// The albums asked for as an answer lands, so a song's tap plays.
    public static let albumsPrefetched = 5

    public static let all = SearchCounts(artists: artistCount, albums: albumCount, songs: songCount)

    /// A kind view's own counts, the other kinds 0.
    public static func chip(_ kind: SearchKind) -> SearchCounts {
        switch kind {
        case .artists: return .only(.artists, chipArtistCount)
        case .albums: return .only(.albums, chipAlbumCount)
        case .songs: return .only(.songs, chipSongCount)
        }
    }

    /// The All view's preview of a kind's library rows on a phone: 2 artists, 3 albums, 3 songs.
    public static func preview(_ kind: SearchKind) -> Int {
        kind == .artists ? 2 : 3
    }

    /// The albums of `songs` to ask for, so a tap plays (`albumsToPrefetch`): `preferred`'s first (Top results' songs),
    /// then `songs`' - each album once, up to `count`.
    public static func albumsToPrefetch(_ songs: [Song], preferred: [Song] = [], count: Int = albumsPrefetched) -> [String] {
        var ids: [String] = []
        for song in preferred + songs {
            if ids.count >= count { break }
            if let id = song.albumId, !id.isEmpty, !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    /// Where a song sits in its album's own answer (`songIndex`) - nil when it isn't there.
    public static func songIndex(_ songs: [Song]?, _ id: String) -> Int? {
        (songs ?? []).firstIndex { $0.id == id }
    }

    /// Whether a library song plays from its tap: its album's songs in hand, with it among them (SearchRows.tsx `plays`).
    public static func plays(_ song: Song, ready: [String: Album]) -> Bool {
        guard let id = song.albumId, !id.isEmpty else { return false }
        return songIndex(ready[id]?.song, song.id) != nil
    }

    /// The library songs among Top results' picks - whose albums are asked for first (`preferredSongs`).
    public static func preferredSongs(_ rows: [SearchRow]) -> [Song] {
        rows.compactMap { (row: SearchRow) -> Song? in
            if case .song(let song) = row { return song }
            return nil
        }
    }
}

// MARK: the rows

/// One row of the list - a section's, or a Top result (searchList.ts `Row`, the library's three). Its key is what
/// keeps it in its place: the kind and Navidrome's id.
public enum SearchRow: Sendable, Equatable, Identifiable {
    case artist(Artist)
    case album(Album)
    case song(Song)

    public var key: String {
        switch self {
        case .artist(let artist): return "artist:\(artist.id)"
        case .album(let album): return "album:\(album.id)"
        case .song(let song): return "song:\(song.id)"
        }
    }

    public var id: String { key }

    public var kind: SearchKind {
        switch self {
        case .artist: return .artists
        case .album: return .albums
        case .song: return .songs
        }
    }

    /// The row's title.
    public var title: String {
        switch self {
        case .artist(let artist): return artist.name ?? ""
        case .album(let album): return album.name ?? ""
        case .song(let song): return song.title ?? ""
        }
    }

    /// Its name or title, and whom it is credited to - what its tier is read from (`facts`).
    var facts: (name: String, credit: String) {
        switch self {
        case .artist(let artist): return (artist.name ?? "", artist.name ?? "")
        case .album(let album): return (album.name ?? "", album.artist ?? "")
        case .song(let song): return (song.title ?? "", song.artist ?? "")
        }
    }
}

// MARK: whose

/// What says whose a row is (searchList.ts `Marks`): logins on with a library of your own (`personal`),
/// `/library/owned`'s index, your albums' ids and each artist's count of them (nil until they have answered), and the
/// albums in hand by id - search3's, a kind view's, those asked for so a song plays (`albumOf`).
public struct SearchMarks: Sendable {
    public var personal: Bool
    public var index: OwnedIndex?
    public var yourAlbums: Set<String>?
    public var yourArtists: [String: Int]?
    public var known: [String: Album]

    public init(personal: Bool, index: OwnedIndex? = nil, yourAlbums: Set<String>? = nil,
                yourArtists: [String: Int]? = nil, known: [String: Album] = [:]) {
        self.personal = personal
        self.index = index
        self.yourAlbums = yourAlbums
        self.yourArtists = yourArtists
        self.known = known
    }

    /// Your albums as the marks read them: their ids, and how many each artist (by the album's artist id) has.
    public static func yours(_ albums: [IndexAlbum]) -> (ids: Set<String>, artists: [String: Int]) {
        var counts: [String: Int] = [:]
        for album in albums {
            if let artist = album.artistId, !artist.isEmpty { counts[artist, default: 0] += 1 }
        }
        return (Set(albums.map(\.id)), counts)
    }
}

/// Which block of a section a row is in: yours, or the collection's (`holder`).
public enum SearchHolder: String, Sendable, Equatable {
    case yours, store

    /// An unknown whose is yours - never "not yours" on a guess.
    public init(_ yours: Bool?) {
        self = yours == false ? .store : .yours
    }
}

public enum SearchWhose {
    /// Whose a Navidrome album is by Navidrome and the folders (whose.ts `navidromeYours`): starred - yours; else,
    /// with the index, whether a folder holding its release is yours (one deadwax didn't say of counts); nil without
    /// the index.
    public static func navidrome(starred: String?, musicBrainzId: String?, index: OwnedIndex?) -> Bool? {
        if let starred, !starred.isEmpty { return true }
        guard let index else { return nil }
        let release = JSText.lowercase(JSText.trim(musicBrainzId ?? ""))
        let held = release.isEmpty ? [] : OwnedIndex.forRelease(index, release)
        return held.contains { $0.yours == true || $0.yours == nil }
    }

    /// A library album's (`albumYours`): yours among your albums whatever search3's star said; one with no star and
    /// no release id read as the albums in hand have it - unknown when none does.
    public static func album(_ album: Album, _ marks: SearchMarks) -> Bool? {
        if !marks.personal { return true }
        if marks.yourAlbums?.contains(album.id) == true { return true }
        if (album.starred ?? "").isEmpty && (album.musicBrainzId ?? "").isEmpty {
            guard let known = marks.known[album.id] else { return nil }
            return navidrome(starred: known.starred, musicBrainzId: known.musicBrainzId, index: marks.index)
        }
        return navidrome(starred: album.starred, musicBrainzId: album.musicBrainzId, index: marks.index)
    }

    /// A library song's - its album's (`songYours`); a song's own star doesn't count.
    public static func song(_ song: Song, _ marks: SearchMarks) -> Bool? {
        if !marks.personal { return true }
        guard let id = song.albumId, !id.isEmpty else { return nil }
        if marks.yourAlbums?.contains(id) == true { return true }
        guard let album = marks.known[id] else { return nil }
        return navidrome(starred: album.starred, musicBrainzId: album.musicBrainzId, index: marks.index)
    }

    /// A library artist's (`artistYours`): yours with albums of theirs among yours - unknown until yours answer.
    public static func artist(_ artist: Artist, _ marks: SearchMarks) -> Bool? {
        if !marks.personal { return true }
        guard let counts = marks.yourArtists else { return nil }
        return (counts[artist.id] ?? 0) > 0
    }

    /// A row's (`rowYours`).
    public static func row(_ row: SearchRow, _ marks: SearchMarks) -> Bool? {
        switch row {
        case .artist(let artist): return self.artist(artist, marks)
        case .album(let album): return self.album(album, marks)
        case .song(let song): return self.song(song, marks)
        }
    }

    /// A row's place in its line (whose.ts `libraryPlace`): "in your library" with logins off; with a library of your
    /// own "in your library" or "in the collection" - nothing while it can't be told.
    public static func place(personal: Bool, yours: Bool?) -> String {
        if !personal { return Whose.inYourLibrary }
        guard let yours else { return "" }
        return yours ? Whose.inYourLibrary : Whose.inTheCollection
    }
}

// MARK: the pool and the sections

/// A row in its place: whose block, and its index in its own answer (-1 for the artist the box named, who leads).
public struct SearchPlaced: Sendable, Equatable {
    public let row: SearchRow
    public let holder: SearchHolder
    public let position: Int

    public init(row: SearchRow, holder: SearchHolder, position: Int) {
        self.row = row
        self.holder = holder
        self.position = position
    }
}

/// Each kind's rows in hand (searchList.ts `pool`, the library's part): search3's, in its order, each in its block.
public struct SearchPool: Sendable, Equatable {
    public var artists: [SearchPlaced] = []
    public var albums: [SearchPlaced] = []
    public var songs: [SearchPlaced] = []

    public init(artists: [SearchPlaced] = [], albums: [SearchPlaced] = [], songs: [SearchPlaced] = []) {
        self.artists = artists
        self.albums = albums
        self.songs = songs
    }

    public subscript(kind: SearchKind) -> [SearchPlaced] {
        switch kind {
        case .artists: return artists
        case .albums: return albums
        case .songs: return songs
        }
    }
}

public enum SearchList {
    /// The artist the box named, under the album-by-artist reading (`namedArtist`): by foldName, believed only when
    /// exactly one of `artists` answers to the name.
    public static func namedArtist(_ reading: SearchPlan, _ artists: [Artist]) -> Artist? {
        guard reading.kind == .albumByArtist, let name = reading.artist, !name.isEmpty else { return nil }
        let wanted = FoldKey(Fold.key(name))
        let found = artists.filter { FoldKey(Fold.key($0.name)) == wanted }
        return found.count == 1 ? found[0] : nil
    }

    /// The library's artists to look among (`knownArtists`): the full list when it has answered, with search3's own
    /// beside it - each once, by id, the first kept.
    public static func knownArtists(_ list: [Artist]?, _ listed: [Artist]) -> [Artist] {
        var seen = Set<String>()
        var known: [Artist] = []
        for artist in (list ?? []) + listed where seen.insert(artist.id).inserted {
            known.append(artist)
        }
        return known
    }

    /// Everything the library has for the words, each in its block (`pool`, the library's part): under the
    /// album-by-artist reading the artist named leads Artists when search3 didn't list them.
    public static func pool(reading: SearchPlan, library: LibraryResults?, artistList: [Artist]?,
                            marks: SearchMarks) -> SearchPool {
        let listedArtists = library?.artists ?? []
        let known = knownArtists(artistList, listedArtists)
        var artists: [SearchPlaced] = []
        if let named = namedArtist(reading, known), !listedArtists.contains(where: { $0.id == named.id }) {
            artists.append(SearchPlaced(row: .artist(named), holder: SearchHolder(SearchWhose.artist(named, marks)),
                                        position: -1))
        }
        for (position, artist) in listedArtists.enumerated() {
            artists.append(SearchPlaced(row: .artist(artist), holder: SearchHolder(SearchWhose.artist(artist, marks)),
                                        position: position))
        }
        let albums = (library?.albums ?? []).enumerated().map { (each: (offset: Int, element: Album)) -> SearchPlaced in
            SearchPlaced(row: .album(each.element), holder: SearchHolder(SearchWhose.album(each.element, marks)),
                         position: each.offset)
        }
        let songs = (library?.songs ?? []).enumerated().map { (each: (offset: Int, element: Song)) -> SearchPlaced in
            SearchPlaced(row: .song(each.element), holder: SearchHolder(SearchWhose.song(each.element, marks)),
                         position: each.offset)
        }
        return SearchPool(artists: artists, albums: albums, songs: songs)
    }

    /// A section's rows in the order drawn (`sectionRows`, the library's part): yours, then the collection's, each in
    /// search3's order - the first `cap` of them (the All view's preview), or all.
    public static func sectionRows(_ placed: [SearchPlaced], cap: Int? = nil) -> [SearchRow] {
        let rows = placed.filter { $0.holder == .yours }.map(\.row) + placed.filter { $0.holder == .store }.map(\.row)
        guard let cap else { return rows }
        return Array(rows.prefix(max(0, cap)))
    }

    // MARK: Top results

    /// One thing Top results may pick (`Candidate`). `source` 0 yours, 1 the collection's (slice 2: what's saved 1.5,
    /// MusicBrainz's 2); `position` its index in its answer.
    public struct Candidate: Sendable, Equatable {
        public let row: SearchRow
        public let tier: Int
        public let source: Double
        public let position: Double

        public var key: String { row.key }
        public var kind: SearchKind { row.kind }

        public init(row: SearchRow, tier: Int, source: Double, position: Double) {
            self.row = row
            self.tier = tier
            self.source = source
            self.position = position
        }
    }

    /// Deadwax's exactness test (`matchTier`): 0 exact, 1 by the box's artist, 2 starts with, 3 the rest - the
    /// library's rows (phase5-search.md 2.4).
    public static func matchTier(_ row: SearchRow, box: String, reading: SearchPlan) -> Int {
        let typed = Fold.key(box)
        let (name, credit) = row.facts
        let kind = row.kind
        let songs = kind == .songs
        func fold(_ text: String?) -> String { songs ? SongTitle.key(text) : Fold.key(text) }
        let own = fold(name)
        let artist = Fold.key(reading.artist)
        if kind == .artists {
            if reading.kind == .albumByArtist && !artist.isEmpty && WebText.same(Fold.key(name), artist) { return 1 }
            if WebText.same(Fold.key(name), typed) { return 0 }
        } else if reading.kind == .albumByArtist {
            if !own.isEmpty && WebText.same(own, fold(reading.title)) && WebText.same(Fold.key(credit), artist) { return 0 }
            if !artist.isEmpty && WebText.same(Fold.key(credit), artist) { return 1 }
        } else if reading.kind == .artist {
            if !artist.isEmpty && WebText.same(Fold.key(credit), artist) { return 1 }
        } else if !own.isEmpty && WebText.same(own, fold(box)) {
            return 0
        }
        let start = kind == .songs ? SongTitle.key(box) : typed
        if typed.utf16.count >= 3 && own.utf16.starts(with: start.utf16) { return 2 }
        return 3
    }

    /// Whether `a` goes before `b` (`rank`): tier, source, kind, position.
    public static func ranks(_ a: Candidate, before b: Candidate) -> Bool {
        if a.tier != b.tier { return a.tier < b.tier }
        if a.source != b.source { return a.source < b.source }
        if a.kind.rank != b.kind.rank { return a.kind.rank < b.kind.rank }
        return a.position < b.position
    }

    /// Top results' candidates from the pool (`candidatesOf`, the library's part): yours 0, the collection's 1.
    public static func candidates(_ pool: SearchPool, box: String, reading: SearchPlan) -> [Candidate] {
        SearchKind.allCases.flatMap { (kind: SearchKind) -> [Candidate] in
            pool[kind].map { (placed: SearchPlaced) -> Candidate in
                Candidate(row: placed.row, tier: matchTier(placed.row, box: box, reading: reading),
                          source: placed.holder == .store ? 1 : 0, position: Double(placed.position))
            }
        }
    }

    /// What the best match belongs to, as Apple pulls it in (`familyOf`, the library's rows): a song's album
    /// (search3's row when it has one, else made of the song's own fields) then its artist; an album's artist.
    public static func family(of row: SearchRow, library: LibraryResults?, artistList: [Artist]?) -> [SearchRow] {
        func libraryArtist(_ id: String?, _ name: String?) -> SearchRow? {
            guard let id, !id.isEmpty else { return nil }
            let listed: Artist? = library?.artists.first(where: { (artist: Artist) -> Bool in artist.id == id })
            let found: Artist? = listed ?? artistList?.first(where: { (artist: Artist) -> Bool in artist.id == id })
            return .artist(found ?? Artist(id: id, name: name ?? ""))
        }
        switch row {
        case .song(let song):
            var out: [SearchRow] = []
            if let albumId = song.albumId, !albumId.isEmpty {
                let album: Album? = library?.albums.first(where: { (each: Album) -> Bool in each.id == albumId })
                out.append(.album(album ?? Album(id: albumId, name: song.album ?? "", artist: nonEmpty(song.artist),
                                                 coverArt: nonEmpty(song.coverArt))))
            }
            if let artist = libraryArtist(song.artistId, song.artist) { out.append(artist) }
            return out
        case .album(let album):
            return libraryArtist(album.artistId, album.artist).map { [$0] } ?? []
        case .artist:
            return []
        }
    }

    /// Top results (`topResults`): `n` picks, continuing `fixed` as if those were picked first. Without any: the best,
    /// then its family, each skipped if already picked; then round by round over the kinds, a kind with fewer picks
    /// than the round taking its best left, until there are `n` (fewer candidates, fewer picks).
    public static func topResults(_ candidates: [Candidate], n: Int, library: LibraryResults?, artistList: [Artist]?,
                                  fixed: [SearchRow] = []) -> [SearchRow] {
        var picked: [SearchRow] = fixed
        var keys = Set(fixed.map(\.key))
        //? JavaScript's sort is stable: equal candidates keep their order
        let left = candidates.enumerated()
            .filter { !keys.contains($0.element.key) }
            .sorted { (a: (offset: Int, element: Candidate), b: (offset: Int, element: Candidate)) -> Bool in
                if ranks(a.element, before: b.element) { return true }
                if ranks(b.element, before: a.element) { return false }
                return a.offset < b.offset
            }
            .map(\.element)
        func take(_ row: SearchRow) {
            picked.append(row)
            keys.insert(row.key)
        }
        if picked.isEmpty, let best = left.first {
            take(best.row)
            for relative in family(of: best.row, library: library, artistList: artistList) {
                if picked.count >= n { break }
                if keys.contains(relative.key) { continue }
                take(relative)
            }
        }
        var round = 1
        while picked.count < n {
            var took = false
            for kind in SearchKind.allCases {
                if picked.count >= n { break }
                if picked.filter({ $0.kind == kind }).count >= round { continue }
                guard let next = left.first(where: { $0.kind == kind && !keys.contains($0.key) }) else { continue }
                take(next.row)
                took = true
            }
            if !took && !left.contains(where: { !keys.contains($0.key) }) { break }
            round += 1
        }
        return Array(picked.prefix(max(0, n)))
    }

    // MARK: the lines

    /// A row's second line as its two parts (`rowLine`): the facts, which take the ellipsis, and the place, never cut.
    public struct Line: Sendable, Equatable {
        public let line: String
        public let place: String

        public init(line: String, place: String) {
            self.line = line
            self.place = place
        }

        /// Both as one, as a row reads: "Portishead · Dummy · in your library".
        public var said: String {
            [line, place].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// A row's line (`rowLine`, the library's rows); `top` as Top results say it, the kind word first.
    public static func line(_ row: SearchRow, _ marks: SearchMarks, top: Bool = false) -> Line {
        func join(_ parts: String?...) -> String {
            parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        switch row {
        case .artist(let artist):
            let yours = marks.personal ? marks.yourArtists?[artist.id] ?? 0 : 0
            let count = yours > 0 ? "\(yours) \(yours == 1 ? "album" : "albums") \(Whose.inYourLibrary)"
                : artistLine(artist.albumCount, personal: marks.personal)
            return Line(line: top ? "Artist" : "", place: count)
        case .album(let album):
            let year = (album.year ?? 0) > 0 ? String(album.year ?? 0) : ""
            return Line(line: join(top ? "Album" : "", album.artist, year),
                        place: SearchWhose.place(personal: marks.personal, yours: SearchWhose.album(album, marks)))
        case .song(let song):
            return Line(line: join(top ? "Song" : "", song.artist, song.album),
                        place: SearchWhose.place(personal: marks.personal, yours: SearchWhose.song(song, marks)))
        }
    }

    /// A library artist's count (searchResults.ts `artistLine`): "12 albums in your library" ("in the collection" with
    /// a library of your own) - nothing for none; `top` "Artist" first.
    public static func artistLine(_ albumCount: Int?, personal: Bool, top: Bool = false) -> String {
        let count = albumCount ?? 0
        let words = count != 0
            ? "\(count) \(count == 1 ? "album" : "albums") \(personal ? Whose.inTheCollection : Whose.inYourLibrary)" : ""
        return top ? ["Artist", words].filter { !$0.isEmpty }.joined(separator: " · ") : words
    }

    // MARK: the list drawn

    /// The All view as drawn for some words (Search.tsx `Drawn`, the library's part): Top results' picks and each
    /// section's rows - frozen once made; afterwards only their lines change, in place.
    public struct Drawn: Sendable, Equatable {
        public struct Section: Sendable, Equatable, Identifiable {
            public let kind: SearchKind
            public let rows: [SearchRow]

            public var id: SearchKind { kind }

            public init(kind: SearchKind, rows: [SearchRow]) {
                self.kind = kind
                self.rows = rows
            }
        }

        /// The words it answers.
        public let text: String
        public let top: [SearchRow]
        public let sections: [Section]
        /// The library failed: its failure stands at the top (the rows from what else is in hand below it).
        public let failed: Bool
        /// The library wasn't searched - Navidrome known not to be there (its gate's words stand above).
        public let skipped: Bool
        /// What search3 found, by kind - what the list's words say.
        public let counts: [SearchKind: Int]

        public init(text: String, top: [SearchRow], sections: [Section], failed: Bool, skipped: Bool = false,
                    counts: [SearchKind: Int]) {
            self.text = text
            self.top = top
            self.sections = sections
            self.failed = failed
            self.skipped = skipped
            self.counts = counts
        }

        /// Nothing at all found - searched, and nothing failed: "No results for …".
        public var nothing: Bool { top.isEmpty && sections.isEmpty && !failed && !skipped }

        /// What is announced as it draws: "In your library: 1 artist, 2 albums, 11 songs." - nothing for none.
        public func said(personal: Bool) -> String { SearchWords.library(counts, personal: personal) }
    }

    /// The All view drawn for `text` (Search.tsx's moment, the library's part): the box read against the album
    /// artists of `/library/owned` and search3's artists of this answer, the pool, Top results and each section's
    /// preview. `results` nil: the library failed (`failed`) or wasn't searched. Nil for an empty box.
    public static func draw(_ text: String, results: LibraryResults?, failed: Bool, skipped: Bool = false,
                            ownedArtists: [String], artistList: [Artist]?, marks: SearchMarks) -> Drawn? {
        let names = SearchReading.artistNames(knownNames(ownedArtists, results))
        guard let reading = SearchReading.read(text, names: names) else { return nil }
        let pool = self.pool(reading: reading, library: results, artistList: artistList, marks: marks)
        let top = topResults(candidates(pool, box: text, reading: reading), n: SearchPacing.topResults,
                             library: results, artistList: artistList)
        var sections: [Drawn.Section] = []
        for kind in SearchKind.allCases {
            let rows = sectionRows(pool[kind], cap: SearchPacing.preview(kind))
            if !rows.isEmpty { sections.append(Drawn.Section(kind: kind, rows: rows)) }
        }
        return Drawn(text: text, top: top, sections: sections, failed: failed, skipped: skipped,
                     counts: results?.counts ?? [:])
    }

    /// A kind view's rows as drawn (Search.tsx `kindModel`): its own search3's, in its order - under the
    /// album-by-artist reading Artists led by the artist the box named, when not among them. The reading is the box's
    /// against `/library/owned`'s album artists and All's search3 artists for the words.
    public static func kindRows(_ kind: SearchKind, rows: [SearchRow], text: String, allResults: LibraryResults?,
                                ownedArtists: [String], artistList: [Artist]?) -> [SearchRow] {
        guard kind == .artists else { return rows }
        let names = SearchReading.artistNames(knownNames(ownedArtists, allResults))
        guard let reading = SearchReading.read(text, names: names),
              let named = namedArtist(reading, knownArtists(artistList, allResults?.artists ?? [])),
              !rows.contains(where: { $0.key == "artist:\(named.id)" }) else { return rows }
        return [.artist(named)] + rows
    }

    /// The names the box is read against (Search.tsx `artistsKnown`): `/library/owned`'s album artists, then the
    /// artists search3 found for the words.
    public static func knownNames(_ ownedArtists: [String], _ results: LibraryResults?) -> [String?] {
        ownedArtists.map { (name: String) -> String? in name } + (results?.artists ?? []).map(\.name)
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}

// MARK: a kind view's own

/// A kind view's own search3 (Search.tsx `KindLibrary`): `CHIP_LIBRARY_COUNTS` of its kind for its words, kept until
/// either changes; full (as many as asked) offers More, its next page by offset, appended without repeats.
public struct KindLibrary: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case asking, answered, failed, skipped
    }

    public enum More: Sendable, Equatable {
        case idle, asking, failed
    }

    public let text: String
    public let kind: SearchKind
    public private(set) var state: State
    public private(set) var rows: [SearchRow]
    public private(set) var full: Bool
    public private(set) var more: More

    public init(text: String, kind: SearchKind, state: State = .asking) {
        self.text = text
        self.kind = kind
        self.state = state
        rows = []
        full = false
        more = .idle
    }

    /// Whether it is these words' and this kind's, asked or answered - asked again otherwise (failed, skipped).
    public func holds(_ text: String, _ kind: SearchKind) -> Bool {
        WebText.same(self.text, text) && self.kind == kind && (state == .asking || state == .answered)
    }

    /// The first page landed.
    public mutating func answered(_ results: LibraryResults) {
        rows = Self.rows(kind, results)
        state = .answered
        full = rows.count >= SearchPacing.chip(kind)[kind]
        more = .idle
    }

    public mutating func failed() {
        state = .failed
        rows = []
        full = false
        more = .idle
    }

    /// Where More asks from - nil while it can't (not answered, not full, asking already).
    public var moreOffsets: SearchCounts? {
        guard state == .answered, full, more != .asking else { return nil }
        return .only(kind, rows.count)
    }

    public mutating func moreAsked() {
        more = .asking
    }

    /// More's page landed: what is new appended; full again only when the page was full and brought something new.
    /// Returns how many the page held - what is said of it.
    @discardableResult
    public mutating func moreAnswered(_ results: LibraryResults) -> Int {
        let page = Self.rows(kind, results)
        let known = Set(rows.map(\.key))
        let fresh = page.filter { !known.contains($0.key) }
        rows += fresh
        full = page.count >= SearchPacing.chip(kind)[kind] && !fresh.isEmpty
        more = .idle
        return page.count
    }

    public mutating func moreFailed() {
        more = .failed
    }

    static func rows(_ kind: SearchKind, _ results: LibraryResults) -> [SearchRow] {
        switch kind {
        case .artists: return results.artists.map { SearchRow.artist($0) }
        case .albums: return results.albums.map { SearchRow.album($0) }
        case .songs: return results.songs.map { SearchRow.song($0) }
        }
    }
}

// MARK: the words

/// Search's words (searchList.ts, searchResults.ts, Search.tsx) - and the phone's own for slice 1's hint (question 3)
/// and offline (question 5).
public enum SearchWords {
    public static let title = "Search"
    public static let prompt = "Artists, albums and songs"
    /// The box, as VoiceOver names it.
    public static let label = "Search for artists, albums and songs"
    /// The chips' group.
    public static let chipsLabel = "Show"
    public static let topResults = "Top results"
    public static let seeAll = "See all"
    public static let checkSpelling = "Check the spelling or try a new search."
    public static let tryAgain = "Try again"
    public static let loading = "Loading…"
    /// Offline, with nothing drawn for the words (the phone's own).
    public static let offline = "Search works once deadwax is back."
    /// What a song's row adds for VoiceOver: whether its tap plays it or opens its album.
    public static let playsSaid = ", plays it from its album"
    public static let opensSaid = ", opens its album"

    /// An empty box's line, slice 1's (question 3): what is searched - your library, and the collection with a library
    /// of your own.
    public static func hint(personal: Bool) -> String {
        personal ? "Search your library and the collection." : "Search your library."
    }

    /// While the library is asked (`searchWords().searching(false)`).
    public static func searching(personal: Bool) -> String {
        personal ? "Searching the collection…" : "Searching your library…"
    }

    /// A chip's words.
    public static func chip(_ view: SearchView) -> String {
        switch view {
        case .all: return "All"
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .songs: return "Songs"
        }
    }

    /// A section's heading.
    public static func section(_ kind: SearchKind) -> String {
        chip(SearchView(kind))
    }

    /// See all's VoiceOver label: "See all albums".
    public static func seeAllLabel(_ kind: SearchKind) -> String {
        "See all \(kind.rawValue)"
    }

    static func plural(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }

    static func kindWords(_ kind: SearchKind) -> (one: String, many: String) {
        switch kind {
        case .artists: return ("artist", "artists")
        case .albums: return ("album", "albums")
        case .songs: return ("song", "songs")
        }
    }

    /// "1 artist, 2 albums, 11 songs" - nothing for nothing (`countWords`).
    public static func count(_ counts: [SearchKind: Int]) -> String {
        SearchKind.allCases.filter { (counts[$0] ?? 0) > 0 }.map { (kind: SearchKind) -> String in
            let words = kindWords(kind)
            return plural(counts[kind] ?? 0, words.one, words.many)
        }.joined(separator: ", ")
    }

    /// "In your library: 1 artist, 2 albums, 11 songs." ("In the collection: …" with a library of your own) - nothing
    /// when it found nothing (`libraryWords`).
    public static func library(_ counts: [SearchKind: Int], personal: Bool) -> String {
        let said = count(counts)
        return said.isEmpty ? "" : "\(personal ? "In the collection" : "In your library"): \(said)."
    }

    /// "Showing everything." / "Showing albums." (`viewWords`).
    public static func view(_ view: SearchView) -> String {
        view == .all ? "Showing everything." : "Showing \(view.rawValue)."
    }

    /// "No results for “…”." / "No albums for “…”." (`nothingWords`).
    public static func nothing(_ view: SearchView, _ text: String) -> String {
        view == .all ? "No results for \u{201C}\(text)\u{201D}." : "No \(view.rawValue) for \u{201C}\(text)\u{201D}."
    }

    /// A kind view's More: "More from your library" / "More from the collection".
    public static func moreFromLibrary(personal: Bool) -> String {
        personal ? "More from the collection" : "More from your library"
    }

    /// What More brought, announced: "8 more albums from your library" (Search.tsx's askMoreLibrary).
    public static func moreSaid(_ count: Int, _ kind: SearchKind, personal: Bool) -> String {
        let words = kindWords(kind)
        return "\(count) more \(count == 1 ? words.one : words.many) \(personal ? "from the collection" : "from your library")"
    }
}

// MARK: titleKey

/// Song titles as songs are told apart (songs.ts `titleKey`): an aside naming another take or a remaster dropped -
/// "(live …)", "(… remaster …)", "(… remastered …)", "(mono)", "(stereo)", in either bracket - then accents, case and
/// punctuation folded as foldName folds them, but brackets and apostrophes kept, and no leading "the" dropped: so
/// "Roads (Max Cooper remix)" stays a song of its own. Held to the web by the search vectors.
public enum SongTitle {
    public static func key(_ title: String?) -> String {
        let stripped = dropTakeAsides(Array((title ?? "").unicodeScalars))
        let decomposed = String(String.UnicodeScalarView(stripped)).decomposedStringWithCompatibilityMapping
        let scalars = JSText.lowercased(Array(decomposed.unicodeScalars.filter { !Fold.isMark($0) }))
        var out = String.UnicodeScalarView()
        var spaced = false
        func gap() {
            if !spaced { out.append(" "); spaced = true }
        }
        for scalar in scalars {
            switch scalar.value {
            case 0x2019, 0x2018, 0x60, 0xB4:
                out.append("'")
                spaced = false
            case 0x26:
                gap()
                out.append(contentsOf: "and".unicodeScalars)
                spaced = false
                gap()
            case 0x28, 0x29, 0x5B, 0x5D, 0x27:
                out.append(scalar)
                spaced = false
            default:
                if Fold.isLetterOrNumber(scalar) {
                    out.append(scalar)
                    spaced = false
                } else {
                    gap()
                }
            }
        }
        //? only letters, numbers, brackets, apostrophes and single spaces are left: JS's trim() can only take spaces
        var text = Substring(String(out)).unicodeScalars
        while text.first == " " { text = text.dropFirst() }
        while text.last == " " { text = text.dropLast() }
        return String(String.UnicodeScalarView(text))
    }

    /// `SAME_SONG_ASIDE` (`/\s*[([]\s*(?:live\b[^)\]]*|[^)\]]*\bremaster(?:ed)?\b[^)\]]*|mono|stereo)\s*[)\]]/giu`) each
    /// as one space, matched as JavaScript matches it: leftmost first, case folded (an ſ is an s), `\b` by ASCII word
    /// characters and ſ and K, `\s` JavaScript's white space.
    static func dropTakeAsides(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(scalars.count)
        var at = 0
        while at < scalars.count {
            if let end = asideEnd(scalars, from: at) {
                out.append(" ")
                at = end
            } else {
                out.append(scalars[at])
                at += 1
            }
        }
        return out
    }

    /// Where an aside starting at `start` ends (past its closer) - nil when none starts there.
    static func asideEnd(_ s: [Unicode.Scalar], from start: Int) -> Int? {
        var at = start
        while at < s.count && JSText.isTrimmed(s[at]) { at += 1 }
        guard at < s.count, s[at] == "(" || s[at] == "[" else { return nil }
        var content = at + 1
        while content < s.count && JSText.isTrimmed(s[content]) { content += 1 }
        //? `[^)\]]*` runs to the first closer, whatever is between: every alternative ends there or nowhere
        guard let closer = s[content...].firstIndex(where: { $0 == ")" || $0 == "]" }) else { return nil }
        // live\b ...
        if word(s, content, "live"), boundary(s, content + 4) { return closer + 1 }
        // ... \bremaster(ed)?\b ... - anywhere before the closer
        var p = content
        while p + 8 <= closer {
            if boundary(s, p), word(s, p, "remaster") {
                if p + 10 <= s.count, word(s, p + 8, "ed"), boundary(s, p + 10), p + 10 <= closer { return closer + 1 }
                if boundary(s, p + 8) { return closer + 1 }
            }
            p += 1
        }
        // mono / stereo, then \s*, then the closer
        for whole in ["mono", "stereo"] {
            let count = whole.unicodeScalars.count
            guard word(s, content, whole) else { continue }
            var after = content + count
            while after < s.count && JSText.isTrimmed(s[after]) { after += 1 }
            if after < s.count, s[after] == ")" || s[after] == "]" { return after + 1 }
        }
        return nil
    }

    /// Whether `pattern` (lowercase ASCII) is at `at`, case folded as `/iu` folds it.
    static func word(_ s: [Unicode.Scalar], _ at: Int, _ pattern: String) -> Bool {
        let wanted = Array(pattern.unicodeScalars)
        guard at >= 0, at + wanted.count <= s.count else { return false }
        for (offset, letter) in wanted.enumerated() {
            let scalar = s[at + offset]
            let lower = scalar.value >= 0x41 && scalar.value <= 0x5A ? scalar.value + 0x20 : scalar.value
            if lower == letter.value { continue }
            if letter == "s" && scalar.value == 0x17F { continue }
            return false
        }
        return true
    }

    /// `\b` at `at`, under `/iu`: a word character on one side only.
    static func boundary(_ s: [Unicode.Scalar], _ at: Int) -> Bool {
        let before = at > 0 && at - 1 < s.count && isWord(s[at - 1])
        let after = at < s.count && isWord(s[at])
        return before != after
    }

    static func isWord(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x17F, 0x212A: return true
        default: return false
        }
    }
}
