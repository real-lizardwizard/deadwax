import Foundation

// Which albums are already in the library (Phase 5, slice 1 - notes/ios-specs/phase5-search.md 0, 2.2): deadwax's
// `GET /deadwax/library/owned` read, and indexed as the web's ui/src/lib/owned.ts indexes it - by release, by release
// group, and by name for a folder with no MusicBrainz ids at all - held to the web by Fixtures/search/search-vectors.json
// (ios/scripts/export-search-vectors.cjs). Search reads it for the names the box is read against (its album artists,
// app/useOwned.ts) and for whose an album is when Navidrome hasn't starred it (Whose.navidromeYours); slice 2 for which
// of MusicBrainz's albums you already hold.

/// One album on disk, as `/library/owned` answers it (OWNED_FIELDS in src/routes/library.py) - read leniently: a field
/// of the wrong shape is absent, as every answer of deadwax's is read.
public struct OwnedAlbum: Decodable, Sendable, Equatable, Hashable {
    /// Where it is, under the library - what a folder is told apart by.
    public let path: String
    public let artist: String?
    public let album: String?
    /// The folder's year, as the scan read it: digits, or text.
    public let year: String?
    public let edition: String?
    public let releaseMbid: String?
    public let releaseGroupMbid: String?
    public let formats: [String]?
    public let trackCount: Int?
    /// Who the album is by, as MusicBrainz ids (2.0.0-player.17) - none for a folder tagged with none.
    public let albumartistMbids: [String]?
    /// (logins on) Whether it is in the asker's own library - nil when deadwax didn't say: "your library" is then the
    /// collection (logins off, the break-glass admin, a ledger it couldn't read), and the web counts it as yours.
    public let yours: Bool?

    enum CodingKeys: String, CodingKey {
        case path, artist, album, year, edition, formats, yours
        case releaseMbid = "release_mbid"
        case releaseGroupMbid = "release_group_mbid"
        case trackCount = "track_count"
        case albumartistMbids = "albumartist_mbids"
    }

    public init(path: String, artist: String? = nil, album: String? = nil, year: String? = nil, edition: String? = nil,
                releaseMbid: String? = nil, releaseGroupMbid: String? = nil, formats: [String]? = nil,
                trackCount: Int? = nil, albumartistMbids: [String]? = nil, yours: Bool? = nil) {
        self.path = path
        self.artist = artist
        self.album = album
        self.year = year
        self.edition = edition
        self.releaseMbid = releaseMbid
        self.releaseGroupMbid = releaseGroupMbid
        self.formats = formats
        self.trackCount = trackCount
        self.albumartistMbids = albumartistMbids
        self.yours = yours
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        path = fields.looseField(String.self, .path) ?? ""
        artist = fields.looseField(String.self, .artist)
        album = fields.looseField(String.self, .album)
        if let text = fields.looseField(String.self, .year) {
            year = text
        } else if let number = fields.looseField(Int.self, .year) {
            year = String(number)
        } else {
            year = nil
        }
        edition = fields.looseField(String.self, .edition)
        releaseMbid = fields.looseField(String.self, .releaseMbid)
        releaseGroupMbid = fields.looseField(String.self, .releaseGroupMbid)
        formats = fields.looseList(String.self, .formats)
        trackCount = fields.looseField(Int.self, .trackCount)
        albumartistMbids = fields.looseList(String.self, .albumartistMbids)
        yours = fields.looseField(Bool.self, .yours)
    }
}

/// `GET /deadwax/library/owned`: every album in the library, and what kept it from reading it (`problem`: no
/// LIBRARY_PATH, a scan that failed) - an album that can't be read left out, none `[]`.
public struct OwnedAnswer: Decodable, Sendable, Equatable {
    public let albums: [OwnedAlbum]
    public let problem: String?

    enum CodingKeys: String, CodingKey {
        case albums, problem
    }

    public init(albums: [OwnedAlbum], problem: String? = nil) {
        self.albums = albums
        self.problem = problem
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        albums = fields.looseList(OwnedAlbum.self, .albums) ?? []
        problem = fields.looseField(String.self, .problem)
    }

    /// The album artists, each trimmed and once, in the answer's order (useOwned.ts: `[...new Set(...)]`) - names the
    /// box is read against (SearchReading).
    public var artists: [String] {
        WebText.unique(albums.map { JSText.trim($0.artist ?? "") }.filter { !$0.isEmpty })
    }
}

/// Every album on disk, indexed three ways, surest first (owned.ts `buildOwnedIndex`): by RELEASE id (this pressing),
/// by RELEASE-GROUP id (some pressing of the album), and by NAME - the artist's and the album's foldName - only for a
/// folder with no MusicBrainz ids at all. Keys compared as JavaScript's Map compares them, by UTF-16 code unit.
public struct OwnedIndex: Sendable, Equatable {
    public let byRelease: [FoldKey: [OwnedAlbum]]
    public let byGroup: [FoldKey: [OwnedAlbum]]
    public let byName: [FoldKey: [OwnedAlbum]]
    public let total: Int

    public init(_ albums: [OwnedAlbum]) {
        var byRelease: [FoldKey: [OwnedAlbum]] = [:]
        var byGroup: [FoldKey: [OwnedAlbum]] = [:]
        var byName: [FoldKey: [OwnedAlbum]] = [:]
        func add(_ map: inout [FoldKey: [OwnedAlbum]], _ key: String?, _ album: OwnedAlbum) {
            guard let key, !key.isEmpty else { return }
            map[FoldKey(key), default: []].append(album)
        }
        for album in albums {
            add(&byRelease, album.releaseMbid, album)
            add(&byGroup, album.releaseGroupMbid, album)
            if (album.releaseMbid ?? "").isEmpty && (album.releaseGroupMbid ?? "").isEmpty {
                add(&byName, Self.nameKey(album.artist, album.album), album)
            }
        }
        self.byRelease = byRelease
        self.byGroup = byGroup
        self.byName = byName
        total = albums.count
    }

    /// An untagged folder's key: its artist's and its album's foldName, a newline between.
    static func nameKey(_ artist: String?, _ album: String?) -> String {
        "\(Fold.key(artist))\n\(Fold.key(album))"
    }

    /// The folders holding exactly this pressing (`ownedForRelease`) - none for no index or no id.
    public static func forRelease(_ index: OwnedIndex?, _ releaseId: String?) -> [OwnedAlbum] {
        guard let index, let releaseId, !releaseId.isEmpty else { return [] }
        return index.byRelease[FoldKey(releaseId)] ?? []
    }

    /// What the library holds of one release group (`ownedForGroup`): `held` by id - the group's, and any of
    /// `releaseIds` (a folder tagged with a release but no group) - each folder once by its path; `guessed` by name,
    /// looked for only when nothing is held, under each of `artists` (the credit, the current name) once.
    public static func forGroup(_ index: OwnedIndex?, groupId: String?, releaseIds: [String] = [], title: String = "",
                                artists: [String?] = []) -> (held: [OwnedAlbum], guessed: [OwnedAlbum]) {
        guard let index else { return ([], []) }
        var held = PathOrder()
        if let groupId, !groupId.isEmpty {
            for album in index.byGroup[FoldKey(groupId)] ?? [] { held.set(album) }
        }
        for id in releaseIds {
            for album in index.byRelease[FoldKey(id)] ?? [] { held.set(album) }
        }
        var guessed = PathOrder()
        if held.albums.isEmpty {
            let names = WebText.unique(artists.compactMap { (name: String?) -> String? in
                guard let name, !name.isEmpty else { return nil }
                return name
            })
            for artist in names {
                for album in index.byName[FoldKey(nameKey(artist, title))] ?? [] { guessed.set(album) }
            }
        }
        return (held.albums, guessed.albums)
    }

    /// A Map keyed by path, as owned.ts keeps one: a path seen again keeps its first place, with the later folder.
    private struct PathOrder {
        var albums: [OwnedAlbum] = []
        var at: [[UInt16]: Int] = [:]

        mutating func set(_ album: OwnedAlbum) {
            let key = Array(album.path.utf16)
            if let place = at[key] {
                albums[place] = album
            } else {
                at[key] = albums.count
                albums.append(album)
            }
        }
    }
}
