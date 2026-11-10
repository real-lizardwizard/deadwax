import Foundation

// The Library's answers from deadwax: /navidrome/album_index (src/routes/navidrome.py) and /me/library
// (src/routes/my_library.py). One stored property a line, in the form tests/test_ios_contract.py's
// `required_fields` reads.

/// Which album list: `yours` - your starred albums, asked as you - or `store`, every album deadwax holds
/// (src/routes/navidrome.py `AlbumScope`, SCOPE_LIST).
public enum AlbumScope: String, Codable, Sendable, CaseIterable {
    case yours
    case store

    /// Whose Recently added the list is: yours by when each album entered your library (its star), the store's by
    /// when the collection got it (2.0.11; app/LibrarySection.tsx `by`).
    public var addedBy: AddedBy { self == .yours ? .you : .collection }

    /// The Albums screen's scope (app/LibrarySection.tsx): yours with a library of your own, else the store's -
    /// with logins off, and for the break-glass admin, nothing ever asks `yours`.
    public static func albums(for me: Me?) -> AlbumScope { PersonalLibrary.has(me) ? .yours : .store }
}

/// Whether the person signed in has a library of their own (app/useMyLibrary.ts `hasLibrary`): logins on, and
/// signed in through Navidrome - not the break-glass admin, who has no Navidrome account.
public enum PersonalLibrary {
    /// lib/signIn.ts BREAK_GLASS_USER.
    public static let breakGlassUser = "deadwax"

    public static func has(_ me: Me?) -> Bool {
        guard let me else { return false }
        return me.loginsOn && me.user != breakGlassUser
    }
}

/// One album of `/album_index` - the route's INDEX_FIELDS, each present only when Navidrome sent it. Only `id` is
/// required; every other field is read leniently - missing, null, or a value of another type is nil, never a
/// failed list (the dev stand-in's `created` is a float, which synthesized decoding would throw on, losing the
/// whole Library; the web reads it as "Date unknown", and so does this).
public struct IndexAlbum: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let artist: String?
    public let artistId: String?
    public let coverArt: String?
    public let year: Int?
    public let genre: String?
    public let created: String?
    public let played: String?
    public let playCount: Int?
    public let starred: String?
    public let musicBrainzId: String?
    public let songCount: Int?
    public let duration: Double?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, artist, artistId, coverArt, year, genre, created, played, playCount, starred, musicBrainzId,
             songCount, duration
    }

    public init(id: String, name: String? = nil, artist: String? = nil, artistId: String? = nil,
                coverArt: String? = nil, year: Int? = nil, genre: String? = nil, created: String? = nil,
                played: String? = nil, playCount: Int? = nil, starred: String? = nil, musicBrainzId: String? = nil,
                songCount: Int? = nil, duration: Double? = nil) {
        self.id = id
        self.name = name
        self.artist = artist
        self.artistId = artistId
        self.coverArt = coverArt
        self.year = year
        self.genre = genre
        self.created = created
        self.played = played
        self.playCount = playCount
        self.starred = starred
        self.musicBrainzId = musicBrainzId
        self.songCount = songCount
        self.duration = duration
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        func text(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
        func whole(_ key: CodingKeys) -> Int? { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil }
        name = text(.name)
        artist = text(.artist)
        artistId = text(.artistId)
        coverArt = text(.coverArt)
        year = whole(.year)
        genre = text(.genre)
        created = text(.created)
        played = text(.played)
        playCount = whole(.playCount)
        starred = text(.starred)
        musicBrainzId = text(.musicBrainzId)
        songCount = whole(.songCount)
        duration = (try? c.decodeIfPresent(Double.self, forKey: .duration)) ?? nil
    }

    /// The names of the fields read - each must be one of the route's INDEX_FIELDS, or it would always be nil.
    public static let fieldNames: [String] = CodingKeys.allCases.map(\.rawValue)
}

/// `GET /deadwax/navidrome/album_index?scope=`: every album of the scope in one answer, in Navidrome's order, and
/// whether the route stopped at its cap (INDEX_MAX, 10,000 albums). The server always sends both.
public struct AlbumIndexAnswer: Codable, Sendable, Equatable {
    public let albums: [IndexAlbum]
    public let truncated: Bool

    public init(albums: [IndexAlbum], truncated: Bool = false) {
        self.albums = albums
        self.truncated = truncated
    }
}

/// One album of your library as `GET /deadwax/me/library` names it (src/routes/my_library.py `_entry`).
public struct LibraryEntry: Codable, Sendable, Equatable, Hashable {
    /// the store index's id for it (store_album.id)
    public let albumID: Int
    public let artist: String
    public let album: String
    public let releaseMBID: String?
    public let releaseGroupMBID: String?
    /// Navidrome's album it was starred on - nil until it has been
    public let navidromeID: String?
    public let addedAt: String?
    /// grabbed | added | seeded | starred
    public let how: String?

    enum CodingKeys: String, CodingKey {
        case albumID = "album_id", artist, album, releaseMBID = "release_mbid",
             releaseGroupMBID = "release_group_mbid", navidromeID = "navidrome_id", addedAt = "added_at", how
    }

    public init(albumID: Int, artist: String = "", album: String = "", releaseMBID: String? = nil,
                releaseGroupMBID: String? = nil, navidromeID: String? = nil, addedAt: String? = nil, how: String? = nil) {
        self.albumID = albumID
        self.artist = artist
        self.album = album
        self.releaseMBID = releaseMBID
        self.releaseGroupMBID = releaseGroupMBID
        self.navidromeID = navidromeID
        self.addedAt = addedAt
        self.how = how
    }
}

/// `GET /deadwax/me/library`: your library and how far deadwax has got starring it - only what the phone reads.
/// `on` false with logins off (and nothing else); `library` false for the break-glass admin; `kept` false when
/// deadwax can't read its database. `new`: added since, not yet opened - the Library's New marks.
public struct MyLibrary: Codable, Sendable, Equatable {
    public let on: Bool
    public let library: Bool?
    public let kept: Bool?
    public let count: Int?
    public let starred: Int?
    public let waiting: Int?
    public let incomplete: Int?
    /// 'ok' | 'dead' (Navidrome no longer takes the login you signed in with) | 'none'
    public let login: String?
    public var new: [LibraryEntry]?

    public init(on: Bool, library: Bool? = nil, kept: Bool? = nil, count: Int? = nil, starred: Int? = nil,
                waiting: Int? = nil, incomplete: Int? = nil, login: String? = nil, new: [LibraryEntry]? = nil) {
        self.on = on
        self.library = library
        self.kept = kept
        self.count = count
        self.starred = starred
        self.waiting = waiting
        self.incomplete = incomplete
        self.login = login
        self.new = new
    }
}

/// `POST /deadwax/me/library/seen` (src/routes/my_library.py `Seen`): exactly one of the two - the release opened,
/// or the store's ids of the entries it clears. `{cleared: n}` comes back.
public struct SeenBody: Codable, Sendable, Equatable {
    public let releaseMBID: String?
    public let albumIDs: [Int]?

    enum CodingKeys: String, CodingKey {
        case releaseMBID = "release_mbid", albumIDs = "album_ids"
    }

    public static func release(_ mbid: String) -> SeenBody { SeenBody(releaseMBID: mbid, albumIDs: nil) }
    public static func albums(_ ids: [Int]) -> SeenBody { SeenBody(releaseMBID: nil, albumIDs: ids) }

    init(releaseMBID: String?, albumIDs: [Int]?) {
        self.releaseMBID = releaseMBID
        self.albumIDs = albumIDs
    }
}
