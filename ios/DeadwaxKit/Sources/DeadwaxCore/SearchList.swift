import Foundation

// Search's one list (Phase 5, slices 1 and 2 - notes/ios-specs/phase5-search.md 2.2-2.8): the web's
// ui/src/lib/searchList.ts (the rows, whose, the pool and the sections, Top results, the lines, the moments, the
// words), ui/src/lib/searchResults.ts (the hint, the busy words, the prefetch, the artist's count), ui/src/lib/whose.ts
// (navidromeYours, libraryPlace) and ui/src/lib/songs.ts' titleKey - the library's rows (slice 1) and MusicBrainz's
// albums with the phantoms and the moments (slice 2); MusicBrainz's artists and songs come with slice 3. Held to the web
// by Fixtures/search/search-vectors.json (ios/scripts/export-search-vectors.cjs) and search-albums-vectors.json
// (export-search-albums-vectors.cjs), which run the web's own functions.

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

    /// ...and of its MusicBrainz rows, each capped on its own (`PREVIEW.phone`'s second): 2, 3, 3.
    public static func previewMusicBrainz(_ kind: SearchKind) -> Int {
        kind == .artists ? 2 : 3
    }

    /// Both caps, as `sectionRows` takes them.
    public static func cap(_ kind: SearchKind) -> (Int, Int) {
        (preview(kind), previewMusicBrainz(kind))
    }

    /// How long the sections wait, after MusicBrainz is asked, for every kind asked (`RESULTS_WAIT_MS`).
    public static let resultsWaitMs = 1500
    /// How long the list waits for the library before it is drawn as if the library found nothing, a place kept at its
    /// top for it (`LIBRARY_LATE_MS`).
    public static let libraryLateMs = 1500
    /// How long MusicBrainz's albums wait for `/library/owned`, asked beside them, before they are drawn anyway
    /// (Search.tsx `OWNED_WAIT_MS`).
    public static let ownedWaitMs = 1500

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

/// One row of the list - a section's, or a Top result (searchList.ts `Row`): the library's three, and MusicBrainz's
/// albums (slice 2), artists and songs (slice 3) - and a MusicBrainz song's named album, pulled into Top results from
/// the song's own fields. Its key is what keeps it in its place: the kind and the id.
public enum SearchRow: Sendable, Equatable, Identifiable {
    case artist(Artist)
    case album(Album)
    case song(Song)
    /// MusicBrainz's album - one you don't have, or one MusicBrainz brought in that you hold.
    case group(ReleaseGroup)
    /// MusicBrainz's artist - one `/artists` found, or one a credit names.
    case mbArtist(MBArtistMatch)
    /// MusicBrainz's song: every take of one title by one credit, on the albums it is on.
    case mbSong(FoundSong)
    /// A MusicBrainz song's named album, as Top results pull it in (not a ReleaseGroup: the song's own fields) - keyed
    /// as MusicBrainz's album would be, so the two are never both drawn.
    case songAlbum(FoundSong, SongAlbum)

    public var key: String {
        switch self {
        case .artist(let artist): return "artist:\(artist.id)"
        case .album(let album): return "album:\(album.id)"
        case .song(let song): return "song:\(song.id)"
        case .group(let group): return "group:\(group.id)"
        case .mbArtist(let match): return "mb-artist:\(match.mbid)"
        case .mbSong(let song): return "mb-song:\(song.key)"
        case .songAlbum(_, let album): return "group:\(album.id)"
        }
    }

    public var id: String { key }

    public var kind: SearchKind {
        switch self {
        case .artist, .mbArtist: return .artists
        case .album, .group, .songAlbum: return .albums
        case .song, .mbSong: return .songs
        }
    }

    /// The row's title.
    public var title: String {
        switch self {
        case .artist(let artist): return artist.name ?? ""
        case .album(let album): return album.name ?? ""
        case .song(let song): return song.title ?? ""
        case .group(let group): return group.title ?? ""
        case .mbArtist(let match): return match.name
        case .mbSong(let song): return song.title
        case .songAlbum(_, let album): return album.title
        }
    }

    /// Whether it is MusicBrainz's.
    public var isMusicBrainz: Bool {
        switch self {
        case .group, .mbArtist, .mbSong, .songAlbum: return true
        case .artist, .album, .song: return false
        }
    }

    /// Its name or title, and whom it is credited to - what its tier is read from (`facts`).
    var facts: (name: String, credit: String) {
        switch self {
        case .artist(let artist): return (artist.name ?? "", artist.name ?? "")
        case .album(let album): return (album.name ?? "", album.artist ?? "")
        case .song(let song): return (song.title ?? "", song.artist ?? "")
        case .group(let group): return (group.title ?? "", Credits.name(group.artistCredit))
        case .mbArtist(let match): return (match.name, match.name)
        case .mbSong(let song): return (song.title, song.credit)
        case .songAlbum(_, let album): return (album.title, album.credit)
        }
    }
}

// MARK: whose

/// What says whose a row is (searchList.ts `Marks`): logins on with a library of your own (`personal`),
/// `/library/owned`'s index, your albums' ids and each artist's count of them (nil until they have answered), and the
/// albums in hand by id - search3's, a kind view's, those asked for so a song plays (`albumOf`) - and what else says a
/// pressing you hold has a MusicBrainz song (`evidence`, Search.tsx's: search3's songs, the pressings kept).
public struct SearchMarks: Sendable {
    public var personal: Bool
    public var index: OwnedIndex?
    public var yourAlbums: Set<String>?
    public var yourArtists: [String: Int]?
    public var known: [String: Album]
    public var evidence: SongEvidence

    public init(personal: Bool, index: OwnedIndex? = nil, yourAlbums: Set<String>? = nil,
                yourArtists: [String: Int]? = nil, known: [String: Album] = [:], evidence: SongEvidence = .none) {
        self.personal = personal
        self.index = index
        self.yourAlbums = yourAlbums
        self.yourArtists = yourArtists
        self.known = known
        self.evidence = evidence
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

    /// A row's (`rowYours`): a MusicBrainz album's when the library holds it (`groupYours`), else nil; a MusicBrainz
    /// song's, and its named album's, when a pressing with the song is held (`namedAlbum`, `songAlbumHeld`); a
    /// MusicBrainz artist's nil.
    public static func row(_ row: SearchRow, _ marks: SearchMarks) -> Bool? {
        switch row {
        case .artist(let artist): return self.artist(artist, marks)
        case .album(let album): return self.album(album, marks)
        case .song(let song): return self.song(song, marks)
        case .group(let group): return SearchAlbums.held(marks.index, group.id) ? SearchAlbums.yours(group, marks) : nil
        case .mbArtist: return nil
        case .mbSong(let song):
            let held = SongSearch.namedAlbum(song, marks.index, marks.evidence).held
            return held.isEmpty ? nil : !marks.personal || SongSearch.anyYours(held)
        case .songAlbum(let song, let album):
            let held = SongSearch.held(marks.index, album, song, marks.evidence)
            return held.isEmpty ? nil : !marks.personal || SongSearch.anyYours(held)
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

/// One kind's rows in hand (searchList.ts `KindPool`): the library's (search3, in its order), those MusicBrainz brought
/// in (held, but not listed by search3), and MusicBrainz's own. What's saved (slice 4) isn't in it yet.
public struct SearchKindPool: Sendable, Equatable {
    public var library: [SearchPlaced]
    public var brought: [SearchPlaced]
    public var musicbrainz: [SearchPlaced]

    public init(library: [SearchPlaced] = [], brought: [SearchPlaced] = [], musicbrainz: [SearchPlaced] = []) {
        self.library = library
        self.brought = brought
        self.musicbrainz = musicbrainz
    }
}

/// Each kind's rows in hand (searchList.ts `pool`): each thing once, in its block.
public struct SearchPool: Sendable, Equatable {
    public var artists: SearchKindPool
    public var albums: SearchKindPool
    public var songs: SearchKindPool

    public init(artists: SearchKindPool = SearchKindPool(), albums: SearchKindPool = SearchKindPool(),
                songs: SearchKindPool = SearchKindPool()) {
        self.artists = artists
        self.albums = albums
        self.songs = songs
    }

    public subscript(kind: SearchKind) -> SearchKindPool {
        switch kind {
        case .artists: return artists
        case .albums: return albums
        case .songs: return songs
        }
    }
}

/// MusicBrainz's albums answer as the pool takes it: its groups, and the block shown (`notInLibrary`, worked out once
/// as the answer landed).
public struct SearchAlbumsInHand: Sendable, Equatable {
    public let groups: [ReleaseGroup]
    public let shown: [ReleaseGroup]

    public init(groups: [ReleaseGroup], shown: [ReleaseGroup]) {
        self.groups = groups
        self.shown = shown
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

    /// Everything in hand for the words, each thing once, in its block (`pool`): under the album-by-artist reading the
    /// artist named leads Artists when search3 didn't list them; MusicBrainz's artists less the library's - one the
    /// library has brought in (`newArtists`); MusicBrainz's albums less those the library holds (`shown`), and those it
    /// holds that search3 didn't list brought into their holder's block (`heldUnlisted`) - a group found held only since
    /// its answer landed stays in MusicBrainz's block, marked in place; MusicBrainz's songs less the library's, one held
    /// on an album it is on brought in (`newSongs`).
    public static func pool(reading: SearchPlan, library: LibraryResults?, artistList: [Artist]?,
                            marks: SearchMarks, albums found: SearchAlbumsInHand? = nil,
                            artists matches: [MBArtistMatch]? = nil, songs foundSongs: [FoundSong]? = nil) -> SearchPool {
        let listedArtists = library?.artists ?? []
        let known = knownArtists(artistList, listedArtists)
        let named = namedArtist(reading, known)
        var artists = SearchKindPool()
        if let named, !listedArtists.contains(where: { $0.id == named.id }) {
            artists.library.append(SearchPlaced(row: .artist(named), holder: SearchHolder(SearchWhose.artist(named, marks)),
                                                position: -1))
        }
        for (position, artist) in listedArtists.enumerated() {
            artists.library.append(SearchPlaced(row: .artist(artist), holder: SearchHolder(SearchWhose.artist(artist, marks)),
                                                position: position))
        }
        if let matches {
            let listed = named.map { listedArtists + [$0] } ?? listedArtists
            let split = newArtists(matches, known: known, index: marks.index, listed: listed)
            artists.musicbrainz = split.musicbrainz.map { (each: (match: MBArtistMatch, position: Int)) -> SearchPlaced in
                SearchPlaced(row: .mbArtist(each.match), holder: .yours, position: each.position)
            }
            artists.brought = split.brought.map { (each: (artist: Artist, position: Int)) -> SearchPlaced in
                SearchPlaced(row: .artist(each.artist), holder: SearchHolder(SearchWhose.artist(each.artist, marks)),
                             position: each.position)
            }
        }
        let libraryAlbums = library?.albums ?? []
        var albums = SearchKindPool(library: libraryAlbums.enumerated().map { (each: (offset: Int, element: Album)) -> SearchPlaced in
            SearchPlaced(row: .album(each.element), holder: SearchHolder(SearchWhose.album(each.element, marks)),
                         position: each.offset)
        })
        if let found {
            //? a Map of id -> position: a group named twice keeps its last position, as JavaScript's Map does
            var at: [String: Int] = [:]
            for (position, group) in found.groups.enumerated() { at[group.id] = position }
            albums.musicbrainz = found.shown.map { (group: ReleaseGroup) -> SearchPlaced in
                SearchPlaced(row: .group(group), holder: .yours, position: at[group.id] ?? 0)
            }
            let shown = Set(found.shown.map(\.id))
            albums.brought = SearchAlbums.heldUnlisted(found.groups, marks.index, libraryAlbums)
                .filter { !shown.contains($0.id) }
                .map { (group: ReleaseGroup) -> SearchPlaced in
                    SearchPlaced(row: .group(group), holder: SearchHolder(SearchAlbums.yours(group, marks)),
                                 position: at[group.id] ?? 0)
                }
        }
        let librarySongs = library?.songs ?? []
        var songs = SearchKindPool(library: librarySongs.enumerated().map { (each: (offset: Int, element: Song)) -> SearchPlaced in
            SearchPlaced(row: .song(each.element), holder: SearchHolder(SearchWhose.song(each.element, marks)),
                         position: each.offset)
        })
        if let foundSongs {
            //? a Map of key -> position, as the albums' ids: a key named twice keeps its last
            var at: [FoldKey: Int] = [:]
            for (position, song) in foundSongs.enumerated() { at[FoldKey(song.key)] = position }
            let split = newSongs(foundSongs, library: librarySongs, index: marks.index, evidence: marks.evidence)
            songs.musicbrainz = split.musicbrainz.map { (each: (song: FoundSong, position: Int)) -> SearchPlaced in
                SearchPlaced(row: .mbSong(each.song), holder: .yours, position: at[FoldKey(each.song.key)] ?? 0)
            }
            songs.brought = split.brought.map { (each: (song: FoundSong, position: Int, yours: Bool)) -> SearchPlaced in
                SearchPlaced(row: .mbSong(each.song), holder: marks.personal && !each.yours ? .store : .yours,
                             position: at[FoldKey(each.song.key)] ?? 0)
            }
        }
        return SearchPool(artists: artists, albums: albums, songs: songs)
    }

    /// How many MusicBrainz artists of an answer answer to a name (`answering`): by their name, or the name they were
    /// matched as (foldName).
    static func answering(_ matches: [MBArtistMatch], _ name: String?) -> Int {
        let wanted = Fold.key(name)
        if wanted.isEmpty { return 0 }
        return matches.filter { (match: MBArtistMatch) -> Bool in
            WebText.same(Fold.key(match.name), wanted)
                || (!match.matchedAs.isEmpty && WebText.same(Fold.key(match.matchedAs), wanted))
        }.count
    }

    /// MusicBrainz's artists less the library's (`newArtists`): one is the library's when `libraryArtist` finds them in
    /// `known` - by id; by the name the folders with that id are filed under; by MusicBrainz's name for an artist with no
    /// id - the name steps believed only when exactly one artist of the answer answers to it (two Nirvanas stay two
    /// rows). A matched one is dropped: the library's artist shows instead, brought in when search3 didn't list them -
    /// at the match's position, each once.
    public static func newArtists(_ matches: [MBArtistMatch], known: [Artist], index: OwnedIndex?, listed: [Artist])
        -> (musicbrainz: [(match: MBArtistMatch, position: Int)], brought: [(artist: Artist, position: Int)]) {
        var musicbrainz: [(match: MBArtistMatch, position: Int)] = []
        var brought: [(artist: Artist, position: Int)] = []
        let listedIds = Set(listed.map(\.id))
        for (position, match) in matches.enumerated() {
            let found = SearchAlbums.libraryArtist(known, mbid: match.mbid, index: index, name: match.name)
            guard let found else {
                musicbrainz.append((match, position))
                continue
            }
            let byId = MBID.of(found.musicBrainzId) == MBID.of(match.mbid)
            if !byId && answering(matches, found.name) != 1 {
                musicbrainz.append((match, position))
                continue
            }
            if !listedIds.contains(found.id) && !brought.contains(where: { $0.artist.id == found.id }) {
                brought.append((found, position))
            }
        }
        return (musicbrainz, brought)
    }

    /// MusicBrainz's songs less the library's (`newSongs`): one dropped when a library song of the answer is it - its
    /// title (titleKey) and credit (foldName); one held on an album it is on (`songAlbumHeld`, any of them) brought in,
    /// with whether a folder of it is yours. No match by recording id: deadwax never writes one.
    public static func newSongs(_ found: [FoundSong], library: [Song], index: OwnedIndex?, evidence: SongEvidence = .none)
        -> (musicbrainz: [(song: FoundSong, position: Int)], brought: [(song: FoundSong, position: Int, yours: Bool)]) {
        let heard = Set(library.map { FoldKey("\(SongTitle.key($0.title))\n\(Fold.key($0.artist))") })
        var musicbrainz: [(song: FoundSong, position: Int)] = []
        var brought: [(song: FoundSong, position: Int, yours: Bool)] = []
        for (position, song) in found.enumerated() {
            if heard.contains(FoldKey("\(SongTitle.key(song.title))\n\(Fold.key(song.credit))")) { continue }
            let held = song.albums.flatMap { SongSearch.held(index, $0, song, evidence) }
            if held.isEmpty {
                musicbrainz.append((song, position))
            } else {
                brought.append((song, position, SongSearch.anyYours(held)))
            }
        }
        return (musicbrainz, brought)
    }

    /// Rows as the phone draws them: each key once, the first kept. search3 can name a song twice (the fixture's
    /// seeded answers do), and a SwiftUI ForEach given one id twice draws the wrong rows; the web's list keeps the repeat
    /// (React keys warn, and draw), and the sections' rules stay the web's - this is the drawing's alone.
    public static func drawable(_ rows: [SearchRow]) -> [SearchRow] {
        var seen = Set<String>()
        return rows.filter { (row: SearchRow) -> Bool in seen.insert(row.key).inserted }
    }

    /// A section's rows in the order drawn and kept (`sectionRows`): yours (the library's, then what MusicBrainz brought
    /// in that you hold), then the collection's (the same two), then MusicBrainz's in its order. `cap`: the All view's
    /// preview - (the library's rows, MusicBrainz's), each on its own; nil for everything.
    public static func sectionRows(_ kind: SearchKindPool, cap: (Int, Int)? = nil) -> [SearchRow] {
        let held = kind.library + kind.brought
        let library = held.filter { $0.holder == .yours }.map(\.row) + held.filter { $0.holder == .store }.map(\.row)
        let musicbrainz = kind.musicbrainz.map(\.row)
        guard let cap else { return library + musicbrainz }
        return Array(library.prefix(max(0, cap.0))) + Array(musicbrainz.prefix(max(0, cap.1)))
    }

    /// The rows a late kind brings to its slot (`lateRows`): held ones first (yours, then the collection's), then
    /// MusicBrainz's - never in the block above it, which would move the rows under it; `drawn` (the keys its section
    /// drew already) left out.
    public static func lateRows(_ kind: SearchKindPool, cap: (Int, Int)? = nil, drawn: Set<String> = []) -> [SearchRow] {
        func fresh(_ each: SearchPlaced) -> Bool { !drawn.contains(each.row.key) }
        let brought = (kind.brought.filter { $0.holder == .yours } + kind.brought.filter { $0.holder == .store })
            .filter(fresh).map(\.row)
        let musicbrainz = kind.musicbrainz.filter(fresh).map(\.row)
        guard let cap else { return brought + musicbrainz }
        return Array(brought.prefix(max(0, cap.0))) + Array(musicbrainz.prefix(max(0, cap.1)))
    }

    /// How many of a drawn section's rows are the library's (and brought in), and how many MusicBrainz's
    /// (`drawnCounts`) - what its late kind's rows are capped by.
    public static func drawnCounts(_ kind: SearchKindPool, _ rows: [SearchRow]) -> (Int, Int) {
        let library = Set((kind.library + kind.brought).map(\.row.key))
        let fromLibrary = rows.filter { library.contains($0.key) }.count
        return (fromLibrary, rows.count - fromLibrary)
    }

    // MARK: Top results

    /// Top results' sources, best first (`SOURCE`): yours, the collection's, what's saved (slice 4), MusicBrainz's.
    public enum Source {
        public static let yours: Double = 0
        public static let store: Double = 1
        public static let saved: Double = 1.5
        public static let musicbrainz: Double = 2
    }

    /// One thing Top results may pick (`Candidate`): its row and the keys it is compared by - `source` (`Source`),
    /// `position` its index in its answer. A phantom stands for a MusicBrainz kind still out, and has no row.
    public struct Candidate: Sendable, Equatable {
        public let row: SearchRow?
        public let key: String
        public let kind: SearchKind
        public let tier: Int
        public let source: Double
        public let position: Double
        public let phantom: Bool

        public init(row: SearchRow, tier: Int, source: Double, position: Double) {
            self.row = row
            key = row.key
            kind = row.kind
            self.tier = tier
            self.source = source
            self.position = position
            phantom = false
        }

        /// A MusicBrainz kind still out (`phantom`): the best tier its kind can reach under the reading, MusicBrainz's
        /// source, before every position - at least as good as anything that kind could bring.
        public init(phantom kind: SearchKind, tier: Int) {
            row = nil
            key = "phantom:\(kind.rawValue)"
            self.kind = kind
            self.tier = tier
            source = Source.musicbrainz
            position = -Double.infinity
            phantom = true
        }
    }

    /// The best tier each MusicBrainz kind can reach under a reading (`bestTier`) - nil where it isn't asked.
    public static func bestTier(_ reading: SearchPlan, _ kind: SearchKind) -> Int? {
        switch reading.kind {
        case .artist: return kind == .artists ? 0 : kind == .albums ? 1 : nil
        case .albumByArtist: return kind == .artists ? nil : 0
        case .free: return 0
        }
    }

    /// A MusicBrainz kind still out, as Top results' phantom - nil where the kind can't reach Top results.
    public static func phantom(_ kind: SearchKind, _ reading: SearchPlan) -> Candidate? {
        bestTier(reading, kind).map { Candidate(phantom: kind, tier: $0) }
    }

    /// Deadwax's exactness test (`matchTier`): 0 exact, 1 by the box's artist, 2 starts with, 3 the rest
    /// (phase5-search.md 2.4) - a MusicBrainz artist exact also when its name-or-alias match says so (`matched_as`),
    /// but not under album-by-artist.
    public static func matchTier(_ row: SearchRow, box: String, reading: SearchPlan) -> Int {
        let typed = Fold.key(box)
        let (name, credit) = row.facts
        let kind = row.kind
        let songs = kind == .songs
        func fold(_ text: String?) -> String { songs ? SongTitle.key(text) : Fold.key(text) }
        let own = fold(name)
        let artist = Fold.key(reading.artist)
        if kind == .artists {
            var matched = false
            if case .mbArtist(let match) = row { matched = !match.matchedAs.isEmpty }
            if reading.kind == .albumByArtist && !artist.isEmpty && WebText.same(Fold.key(name), artist) { return 1 }
            if WebText.same(Fold.key(name), typed) || (matched && reading.kind != .albumByArtist) { return 0 }
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

    /// Top results' candidates from the pool (`candidatesOf`): the library's (yours 0, the collection's 1, by the whose
    /// known now), and MusicBrainz's AND what MusicBrainz brought in (2, at their MusicBrainz positions) - so a decision
    /// taken before MusicBrainz answered stays sound.
    public static func candidates(_ pool: SearchPool, box: String, reading: SearchPlan) -> [Candidate] {
        SearchKind.allCases.flatMap { (kind: SearchKind) -> [Candidate] in
            func add(_ placed: SearchPlaced, _ source: Double) -> Candidate {
                Candidate(row: placed.row, tier: matchTier(placed.row, box: box, reading: reading), source: source,
                          position: Double(placed.position))
            }
            let rows = pool[kind]
            return rows.library.map { add($0, $0.holder == .store ? Source.store : Source.yours) }
                + rows.brought.map { add($0, Source.musicbrainz) }
                + rows.musicbrainz.map { add($0, Source.musicbrainz) }
        }
    }

    /// A MusicBrainz artist made from a credit (`creditArtist`): no disambiguation, type or country - its line is
    /// "Artist" alone.
    public static func creditArtist(mbid: String, name: String) -> MBArtistMatch {
        MBArtistMatch(mbid: mbid, name: name)
    }

    /// A MusicBrainz artist credited somewhere, as a row (`creditedRow`): the library's artist when the library knows
    /// them (over the full list of its artists), else MusicBrainz's.
    static func creditedRow(mbid: String, name: String, artistList: [Artist]?, index: OwnedIndex?) -> SearchRow {
        if let artistList, let library = SearchAlbums.libraryArtist(artistList, mbid: mbid, index: index, name: name) {
            return .artist(library)
        }
        return .mbArtist(creditArtist(mbid: mbid, name: name))
    }

    /// What the best match belongs to, as Apple pulls it in (`familyOf`): a library song's album (search3's row when it
    /// has one, else made of the song's own fields) then its artist; a library album's artist; a MusicBrainz song's named
    /// album (MusicBrainz's albums answer's own group when it holds the same id - `groups` - else made of the song's own
    /// album) then its sole credited artist; a MusicBrainz album's sole credited artist.
    public static func family(of row: SearchRow, library: LibraryResults?, artistList: [Artist]?,
                              index: OwnedIndex? = nil, groups: [ReleaseGroup] = [],
                              evidence: SongEvidence = .none) -> [SearchRow] {
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
        case .group(let group):
            guard let sole = Credits.sole(group.artistCredit) else { return [] }
            return [creditedRow(mbid: sole.mbid, name: sole.name, artistList: artistList, index: index)]
        case .mbSong(let song):
            let named = SongSearch.namedAlbum(song, index, evidence).album
            let group = groups.first { WebText.same($0.id, named.id) }
            var out: [SearchRow] = [group.map { SearchRow.group($0) } ?? .songAlbum(song, named)]
            if song.artists.count == 1, let mbid = MBID.of(song.artists[0].id) {
                let sole = song.artists[0]
                out.append(creditedRow(mbid: mbid, name: sole.name.isEmpty ? song.credit : sole.name,
                                       artistList: artistList, index: index))
            }
            return out
        case .artist, .mbArtist, .songAlbum:
            return []
        }
    }

    /// Top results' rows (`topResults`, its picks' rows - a phantom picked has none, and is left out).
    public static func topResults(_ candidates: [Candidate], n: Int, library: LibraryResults?, artistList: [Artist]?,
                                  index: OwnedIndex? = nil, groups: [ReleaseGroup] = [], evidence: SongEvidence = .none,
                                  fixed: [SearchRow] = []) -> [SearchRow] {
        topPicks(candidates, n: n, library: library, artistList: artistList, index: index, groups: groups,
                 evidence: evidence, fixed: fixed).compactMap(\.row)
    }

    /// Top results decided before MusicBrainz has answered, without anything moving (`decidedTop`): the picks over what
    /// is in hand plus one phantom per MusicBrainz kind still out. The picks before the first phantom are the decided
    /// `prefix`, drawn at once and frozen; `place` when a phantom was picked - one place kept at Top results' foot for
    /// the rest. A phantom first: no prefix.
    public static func decidedTop(_ candidates: [Candidate], phantoms: [Candidate], n: Int, library: LibraryResults?,
                                  artistList: [Artist]?, index: OwnedIndex? = nil, groups: [ReleaseGroup] = [],
                                  evidence: SongEvidence = .none) -> (prefix: [SearchRow], place: Bool) {
        let picks = topPicks(candidates + phantoms, n: n, library: library, artistList: artistList, index: index,
                             groups: groups, evidence: evidence)
        guard let first = picks.firstIndex(where: \.phantom) else { return (picks.compactMap(\.row), false) }
        return (picks[..<first].compactMap(\.row), true)
    }

    /// Top results' picks (`topResults`): `n`, continuing `fixed` as if those were picked first. Without any: the best,
    /// then its family, each skipped if already picked; then round by round over the kinds, a kind with fewer picks
    /// than the round taking its best left, until there are `n` (fewer candidates, fewer picks). A phantom picked is
    /// returned as one - decidedTop stops there.
    public static func topPicks(_ candidates: [Candidate], n: Int, library: LibraryResults?, artistList: [Artist]?,
                                index: OwnedIndex? = nil, groups: [ReleaseGroup] = [], evidence: SongEvidence = .none,
                                fixed: [SearchRow] = []) -> [Candidate] {
        var picked: [Candidate] = fixed.map { Candidate(row: $0, tier: 0, source: 0, position: 0) }
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
        func take(_ each: Candidate) {
            picked.append(each)
            keys.insert(each.key)
        }
        if picked.isEmpty, let best = left.first {
            take(best)
            if let row = best.row {
                for relative in family(of: row, library: library, artistList: artistList, index: index, groups: groups,
                                       evidence: evidence) {
                    if picked.count >= n { break }
                    if keys.contains(relative.key) { continue }
                    take(Candidate(row: relative, tier: 3, source: 2, position: 0))
                }
            }
        }
        var round = 1
        while picked.count < n {
            var took = false
            for kind in SearchKind.allCases {
                if picked.count >= n { break }
                if picked.filter({ $0.kind == kind }).count >= round { continue }
                guard let next = left.first(where: { $0.kind == kind && !keys.contains($0.key) }) else { continue }
                take(next)
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

    /// A row's line (`rowLine`); `top` as Top results say it, the kind word first. A MusicBrainz album: "[kind ·]
    /// credit · year", the kind said in a section only when it isn't a plain album, the place where the library holds
    /// it - or "maybe in your library" when a folder may be it by its name alone. A MusicBrainz artist: "[Artist ·]" its
    /// disambiguation, type and country, no place. A MusicBrainz song: "[Song ·] credit · [length ·] its named album",
    /// the place where a pressing with it is held. A song's named album: "[kind ·] credit · year", where it is held.
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
        case .group(let group):
            let held = SearchAlbums.held(marks.index, group.id)
            let word = top ? SearchAlbums.kind(group) : SearchAlbums.word(group)
            return Line(line: join(word, Credits.name(group.artistCredit), SearchAlbums.year(group)),
                        place: held ? SearchAlbums.place(marks.index, group.id, personal: marks.personal)
                            : SearchAlbums.maybe(group, marks))
        case .mbArtist(let match):
            let said = match.line
            return Line(line: top ? join("Artist", said) : said, place: "")
        case .mbSong(let song):
            let (album, held) = SongSearch.namedAlbum(song, marks.index, marks.evidence)
            return Line(line: top ? join("Song", song.credit, album.title)
                            : join(song.credit, SongSearch.length(album.length), album.title),
                        place: SongSearch.heldWords(held, personal: marks.personal))
        case .songAlbum(let song, let album):
            let word = !album.kind.isEmpty && album.kind != "Album" ? album.kind : "Album"
            return Line(line: join(top ? word : "", album.credit, SongSearch.yearOf(album.date)),
                        place: SongSearch.albumWords(SongSearch.holding(marks.index, album, song, marks.evidence),
                                                     personal: marks.personal))
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

    /// The All view as drawn for some words (Search.tsx `Drawn`) - frozen: Top results' picks, each section's rows and
    /// their order. Afterwards only the lines change in place, and a late kind's answer lands only in its slot (moment
    /// 1, `sections` nil: the asking line stands where they will go).
    public struct Drawn: Sendable, Equatable {
        /// A late kind's place in its section, one fixed height (Search.tsx `DrawnSection.slot`).
        public enum Slot: Sendable, Equatable {
            /// Still out: "Searching…".
            case asking
            /// Landed under something tappable: folded behind "Show 3 more albums".
            case show([SearchRow])
            /// Landed with nothing to draw: why.
            case said(String)
            /// Failed while another kind answered: its words and Try again.
            case failed
        }

        public struct Section: Sendable, Equatable, Identifiable {
            public let kind: SearchKind
            public let rows: [SearchRow]
            public let slot: Slot?

            public var id: SearchKind { kind }

            public init(kind: SearchKind, rows: [SearchRow], slot: Slot? = nil) {
                self.kind = kind
                self.rows = rows
                self.slot = slot
            }
        }

        /// The words it answers.
        public let text: String
        /// The run it was drawn for: a new run's first draw is a new list.
        public let run: Int
        public let top: [SearchRow]
        /// A place kept at Top results' foot for the picks still to come.
        public let topPlace: Bool
        /// Nil at moment 1: the asking line stands where they will go.
        public let sections: [Section]?
        /// Drawn as if the library found nothing, a place kept at the top for it.
        public let libraryLate: Bool
        /// The library failed: its failure stands at the top (the rows from what else is in hand below it).
        public let failed: Bool
        /// The library wasn't searched - Navidrome known not to be there (its gate's words stand above).
        public let skipped: Bool
        /// MusicBrainz is asked (or to be) for it: else the foot says how to ask it (`TYPE_MORE`).
        public let musicBrainz: Bool
        /// The Albums section's studio line is drawn.
        public let studio: Bool
        /// Every kind asked failed by moment 2, none late, none refused: one block at the foot.
        public let allFailed: MBFailure?
        /// What search3 found, by kind.
        public let counts: [SearchKind: Int]

        public init(text: String, run: Int = 0, top: [SearchRow], topPlace: Bool = false, sections: [Section]?,
                    libraryLate: Bool = false, failed: Bool, skipped: Bool = false, musicBrainz: Bool = false,
                    studio: Bool = false, allFailed: MBFailure? = nil, counts: [SearchKind: Int]) {
            self.text = text
            self.run = run
            self.top = top
            self.topPlace = topPlace
            self.sections = sections
            self.libraryLate = libraryLate
            self.failed = failed
            self.skipped = skipped
            self.musicBrainz = musicBrainz
            self.studio = studio
            self.allFailed = allFailed
            self.counts = counts
        }

        /// The same list with other sections, top or place - everything else as drawn.
        func with(top: [SearchRow]? = nil, topPlace: Bool? = nil, sections: [Section]?, studio: Bool? = nil,
                  allFailed: MBFailure?? = nil) -> Drawn {
            Drawn(text: text, run: run, top: top ?? self.top, topPlace: topPlace ?? self.topPlace, sections: sections,
                  libraryLate: libraryLate, failed: failed, skipped: skipped, musicBrainz: musicBrainz,
                  studio: studio ?? self.studio, allFailed: allFailed ?? self.allFailed, counts: counts)
        }

        /// Nothing at all found (Search.tsx's `nothing`): the sections drawn, none and no Top results, nothing failed,
        /// MusicBrainz asked, the library not late - "No results for …".
        public var nothing: Bool {
            guard let sections else { return false }
            return top.isEmpty && sections.isEmpty && allFailed == nil && musicBrainz && !failed && !libraryLate
        }

        /// Whether a row of the library's is drawn - what the all-failed foot says is above.
        public var holdsLibrary: Bool {
            top.contains { !$0.isMusicBrainz } || (sections ?? []).contains { $0.rows.contains { !$0.isMusicBrainz } }
        }
    }

    /// Top results' decided picks for a library answer just landed, as moment 1 will draw them (Search.tsx
    /// `decidedPrefix`) - whose songs' albums are asked for first, so a song at the top plays from its first tap.
    /// `musicBrainz`: MusicBrainz is to be asked for the words (a phantom stands for each kind it is asked).
    public static func decidedPrefix(_ text: String, results: LibraryResults, ownedArtists: [String],
                                     artistList: [Artist]?, marks: SearchMarks, musicBrainz: Bool) -> [SearchRow] {
        let names = SearchReading.artistNames(knownNames(ownedArtists, results))
        guard let reading = SearchReading.read(text, names: names) else { return [] }
        let pool = self.pool(reading: reading, library: results, artistList: artistList, marks: marks)
        let phantoms = musicBrainz ? SearchState.wantedKinds(text, reading, view: .all).compactMap { phantom($0, reading) } : []
        return decidedTop(candidates(pool, box: text, reading: reading), phantoms: phantoms, n: SearchPacing.topResults,
                          library: results, artistList: artistList, index: marks.index).prefix
    }

    // MARK: the moments

    /// Whether the sections are drawn now (`sectionsReady`, moment 2): the library settled, and - when MusicBrainz is to
    /// be asked - it has been, and every kind asked has answered or failed, or `resultsWaitMs` has passed since it was
    /// asked. MusicBrainz not to be asked: at once, the library alone.
    public static func sectionsReady(librarySettled: Bool, musicBrainz: Bool, asked: Bool, out: [SearchKind],
                                     capPassed: Bool) -> Bool {
        if !librarySettled { return false }
        if !musicBrainz { return true }
        if !asked { return false }
        return out.isEmpty || capPassed
    }

    /// The kinds still out at moment 2 (`lateKinds`): each gets a slot in its section for its answer to land in.
    public static func lateKinds(_ wanted: [SearchKind], inHand: (SearchKind) -> Bool) -> [SearchKind] {
        wanted.filter { !inHand($0) }
    }

    public enum Landing: String, Sendable, Equatable {
        case into = "in", fold
    }

    /// Where a late kind's answer goes as it lands (`drawInOrFold`): straight in when nothing tappable is drawn below
    /// its section - only the last section drawn - else folded into its slot, so nothing drawn below it moves.
    public static func drawInOrFold(_ kind: SearchKind, _ drawn: [SearchKind], footTappable: Bool = false) -> Landing {
        guard let at = drawn.firstIndex(of: kind) else { return .fold }
        return at == drawn.count - 1 && !footTappable ? .into : .fold
    }

    /// What a search's MusicBrainz asks came to, for Behind (`Outcome`).
    public enum Outcome: String, Sendable, Equatable {
        case inTime = "in-time", late, failed, superseded, refused
    }

    /// Behind (`nextBehind`): after a search whose MusicBrainz missed `resultsWaitMs` with a kind out, or failed as
    /// MusicBrainz away, the next searches draw at the library's moment, MusicBrainz's in slots; it ends after a search
    /// whose every kind asked answers in time. Superseded or refused counts for nothing.
    public static func nextBehind(_ was: Bool, _ outcome: Outcome) -> Bool {
        switch outcome {
        case .late, .failed: return true
        case .inTime: return false
        case .superseded, .refused: return was
        }
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

/// A MusicBrainz ask's failure, as Search keeps it with the kind's answer (Search.tsx `Failure`): its words - a refusal's
/// own (a 422 with words: the words again would be refused again, so no Try again, no Behind), else the error in a
/// listener's words - and whether MusicBrainz is away (a 503) or busy (a 503 saying so).
public struct MBFailure: Sendable, Equatable {
    public let message: String
    public let unavailable: Bool
    public let busy: Bool
    public let refused: Bool

    public init(message: String, unavailable: Bool = false, busy: Bool = false, refused: Bool = false) {
        self.message = message
        self.unavailable = unavailable
        self.busy = busy
        self.refused = refused
    }

    /// `failureOf`: `admin` whoever runs deadwax (the error's own words in brackets after it).
    public static func of(_ error: any Error, admin: Bool) -> MBFailure {
        let failure = error as? APIFailure
        let status = failure?.status
        let detail = JSText.trim(failure?.detail ?? "")
        let refused = status == 422 && !detail.isEmpty
        return MBFailure(message: refused ? detail : ErrorWords.notice("", error, admin: admin, retry: true),
                         unavailable: status == 503, busy: status == 503 && failure?.busy == true, refused: refused)
    }
}

/// Search's words (searchList.ts, searchResults.ts, Search.tsx) - and the phone's own for offline (question 5).
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

    /// An empty box's line (`searchWords().hint`, slice 2 on - question 3): what is searched.
    public static func hint(personal: Bool) -> String {
        personal ? "Search your library, the collection, and albums nobody has yet."
            : "Search your library and albums you don't have yet."
    }

    /// The one asking line before the library has answered (`searchWords().searching`) - "Searching…" once MusicBrainz
    /// is in it.
    public static func searching(personal: Bool, musicBrainz: Bool = false) -> String {
        if musicBrainz { return "Searching…" }
        return personal ? "Searching the collection…" : "Searching your library…"
    }

    /// Where the sections will go, and a late kind's slot.
    public static let searchingMore = "Searching…"

    /// Every album MusicBrainz found is held (`searchWords().allHeld`).
    public static func allHeld(personal: Bool) -> String {
        personal ? "Everything found is in the collection already." : "You already have everything found."
    }

    /// Where MusicBrainz's rows would go when it won't be asked yet (`TYPE_MORE`).
    public static let typeMore = "Type a little more, or press Search, to find albums you don't have yet."

    /// The line under an artist read's Albums when the studio clause asked them (`STUDIO_NOTE`).
    public static let studioNote = "Studio albums and EPs - See all for everything they made."

    /// A kind's slot's words when searching for what you don't have failed - short, to fit one row (`MORE_UNSEARCHED`).
    public static let moreUnsearched = "Can't search for more right now."

    /// What is announced for MusicBrainz once every kind asked has settled (`musicBrainzWords`): "Also found: 3 albums."
    /// - or that searching for more isn't working, when no kind answered.
    public static func musicBrainz(_ counts: [SearchKind: Int], answered: Bool) -> String {
        if !answered { return moreUnsearched }
        let said = count(counts)
        return said.isEmpty ? "Nothing more found." : "Also found: \(said)."
    }

    /// A MusicBrainz failure's words (`failureWords`): refused - its words; busy; away (`short` for a slot).
    public static func failure(_ failure: MBFailure, short: Bool = false) -> String {
        if failure.refused { return failure.message }
        if failure.busy { return "Too many searches just now - try again in a moment." }
        if failure.unavailable {
            return short ? moreUnsearched : "Searching for more isn't working right now - try again in a few minutes."
        }
        return failure.message
    }

    /// What the all-failed foot adds when the library's rows are drawn above it.
    public static func libraryAbove(personal: Bool) -> String {
        personal ? "What's in the collection is above." : "What's in your library is above."
    }

    /// A late kind folded into its slot (`foldWords`): the button, and what is announced.
    public static func fold(_ kind: SearchKind, _ count: Int) -> (button: String, said: String) {
        let words = kindWords(kind)
        let what = "\(count) more \(count == 1 ? words.one : words.many)"
        return ("Show \(what)", "\(what) found - Show them to see them.")
    }

    /// A late kind's slot when its answer brought no row to draw (`emptyWords`).
    public static func empty(_ kind: SearchKind, _ text: String) -> String {
        "No other \(kindWords(kind).many) for \u{201C}\(text)\u{201D}."
    }

    /// The library's place kept at the top, its answer landing after the list was drawn without it
    /// (`libraryLateWords`): Show them, or that it found nothing.
    public static func libraryLate(_ counts: [SearchKind: Int], personal: Bool, text: String) -> (button: String?, line: String) {
        let total = SearchKind.allCases.reduce(0) { $0 + (counts[$1] ?? 0) }
        let place = personal ? Whose.inTheCollection : Whose.inYourLibrary
        if total == 0 { return (nil, "Nothing \(place) for \u{201C}\(text)\u{201D}.") }
        return ("Show \(total) from \(personal ? "the collection" : "your library")", "")
    }

    /// The library's place kept at the top when Navidrome turned out not to be there (`librarySkippedWords`).
    public static func librarySkipped(personal: Bool) -> String {
        personal ? "The collection can't be searched just now." : "Your library can't be searched just now."
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

    /// Whether a title carries such an aside anywhere (songs.ts `hasAside`) - "Roads (live)" does, "Roads" doesn't.
    public static func hasAside(_ title: String) -> Bool {
        let scalars = Array(title.unicodeScalars)
        return scalars.indices.contains { asideEnd(scalars, from: $0) != nil }
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
