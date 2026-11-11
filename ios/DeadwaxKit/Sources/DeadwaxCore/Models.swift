import Foundation

/// `GET /deadwax/health`: `{status, version, poller}`. Answered 503 (with the same body) when the
/// download poller has stopped - deadwax is reachable then, but not doing its job.
public struct Health: Codable, Sendable, Equatable {
    public let status: String
    public let version: String?
    public let poller: String?

    public init(status: String, version: String?, poller: String?) {
        self.status = status
        self.version = version
        self.poller = poller
    }
}

/// `GET /deadwax/me`, and a sign-in's answer: who is asking. `auth` is "on" or "off"; with logins
/// off the user is `local`, the shared account, an admin. `permissions` (2.0.0-player.61) are the names an
/// admin gave this person - every one for an admin - and `permissions_unverified` says some of them are off
/// until they sign in again; both absent from a server before then (`Access` reads them as the web does).
public struct Me: Codable, Sendable, Equatable {
    public let user: String
    public let admin: Bool
    public let auth: String
    public let version: String?
    public let permissions: [String]?
    public let permissionsUnverified: Bool?

    enum CodingKeys: String, CodingKey {
        case user, admin, auth, version, permissions
        case permissionsUnverified = "permissions_unverified"
    }

    public init(user: String, admin: Bool, auth: String, version: String? = nil, permissions: [String]? = nil,
                permissionsUnverified: Bool? = nil) {
        self.user = user
        self.admin = admin
        self.auth = auth
        self.version = version
        self.permissions = permissions
        self.permissionsUnverified = permissionsUnverified
    }

    public var loginsOn: Bool { auth == "on" }
    /// The answer's own name for `permissionsUnverified`.
    public var permissions_unverified: Bool? { permissionsUnverified }
}

/// A song as Navidrome's Subsonic answers describe it, passed on by deadwax as it is. Only what the
/// app reads is declared; everything is optional but the id, since Navidrome leaves out what a file
/// doesn't have (`samplingRate` and `bitDepth` come from OpenSubsonic, and older servers omit them;
/// `playCount` only once it has been played).
///
/// Read leniently: a field of an unexpected type is read as absent rather than failing the song (and with it
/// a whole album's answer) - only the id must be there, and a string.
public struct Song: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String?
    public let album: String?
    public let albumId: String?
    public let artist: String?
    public let track: Int?
    public let discNumber: Int?
    public let duration: Double?
    public let suffix: String?
    public let contentType: String?
    public let size: Int64?
    public let bitRate: Int?
    public let samplingRate: Int?
    public let bitDepth: Int?
    public let channelCount: Int?
    public let coverArt: String?
    /// The song's own artist's Navidrome id.
    public let artistId: String?
    /// Its album's year.
    public let year: Int?
    /// How many times this person has played it - absent until they have.
    public let playCount: Int?
    /// OpenSubsonic: who wrote it, as one line ("" for nobody).
    public let displayComposer: String?
    /// OpenSubsonic: its album's artist as one line.
    public let displayAlbumArtist: String?
    /// OpenSubsonic: everyone credited on it, by role - composers among them.
    public let contributors: [Contributor]?

    /// One credit: a role (`composer`, `performer`...) and who.
    public struct Contributor: Codable, Sendable, Equatable, Hashable {
        public let role: String?
        public let artist: Name?

        public struct Name: Codable, Sendable, Equatable, Hashable {
            public let name: String?

            public init(name: String?) { self.name = name }

            public init(from decoder: any Decoder) throws {
                let fields = try decoder.container(keyedBy: CodingKeys.self)
                name = fields.looseField(String.self, .name)
            }
        }

        public init(role: String?, artist: String?) {
            self.role = role
            self.artist = artist.map { Name(name: $0) }
        }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            role = fields.looseField(String.self, .role)
            artist = fields.looseField(Name.self, .artist)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, album, albumId, artist, track, discNumber, duration, suffix, contentType, size, bitRate
        case samplingRate, bitDepth, channelCount, coverArt, artistId, year, playCount, displayComposer
        case displayAlbumArtist, contributors
    }

    public init(id: String, title: String? = nil, album: String? = nil, albumId: String? = nil,
                artist: String? = nil, track: Int? = nil, discNumber: Int? = nil, duration: Double? = nil,
                suffix: String? = nil, contentType: String? = nil, size: Int64? = nil, bitRate: Int? = nil,
                samplingRate: Int? = nil, bitDepth: Int? = nil, channelCount: Int? = nil, coverArt: String? = nil,
                artistId: String? = nil, year: Int? = nil, playCount: Int? = nil, displayComposer: String? = nil,
                displayAlbumArtist: String? = nil, contributors: [Contributor]? = nil) {
        self.id = id
        self.title = title
        self.album = album
        self.albumId = albumId
        self.artist = artist
        self.track = track
        self.discNumber = discNumber
        self.duration = duration
        self.suffix = suffix
        self.contentType = contentType
        self.size = size
        self.bitRate = bitRate
        self.samplingRate = samplingRate
        self.bitDepth = bitDepth
        self.channelCount = channelCount
        self.coverArt = coverArt
        self.artistId = artistId
        self.year = year
        self.playCount = playCount
        self.displayComposer = displayComposer
        self.displayAlbumArtist = displayAlbumArtist
        self.contributors = contributors
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        title = fields.looseField(String.self, .title)
        album = fields.looseField(String.self, .album)
        albumId = fields.looseField(String.self, .albumId)
        artist = fields.looseField(String.self, .artist)
        track = fields.looseField(Int.self, .track)
        discNumber = fields.looseField(Int.self, .discNumber)
        duration = fields.looseField(Double.self, .duration)
        suffix = fields.looseField(String.self, .suffix)
        contentType = fields.looseField(String.self, .contentType)
        size = fields.looseField(Int64.self, .size)
        bitRate = fields.looseField(Int.self, .bitRate)
        samplingRate = fields.looseField(Int.self, .samplingRate)
        bitDepth = fields.looseField(Int.self, .bitDepth)
        channelCount = fields.looseField(Int.self, .channelCount)
        coverArt = fields.looseField(String.self, .coverArt)
        artistId = fields.looseField(String.self, .artistId)
        year = fields.looseField(Int.self, .year)
        playCount = fields.looseField(Int.self, .playCount)
        displayComposer = fields.looseField(String.self, .displayComposer)
        displayAlbumArtist = fields.looseField(String.self, .displayAlbumArtist)
        contributors = fields.looseList(Contributor.self, .contributors)
    }

    /// The title, or the id when the file has none.
    public var name: String { (title?.isEmpty == false ? title : nil) ?? id }
}

/// An album as search3 lists it - only what the app shows.
public struct AlbumSummary: Codable, Sendable, Equatable {
    public let id: String
    public let name: String?
    public let artist: String?

    public init(id: String, name: String? = nil, artist: String? = nil) {
        self.id = id
        self.name = name
        self.artist = artist
    }
}

/// `GET /deadwax/navidrome/search`: `{artists, albums, songs}`. Artists aren't read in Phase 0.
public struct SearchResult: Codable, Sendable, Equatable {
    public let albums: [AlbumSummary]
    public let songs: [Song]

    public init(albums: [AlbumSummary] = [], songs: [Song] = []) {
        self.albums = albums
        self.songs = songs
    }
}

// MARK: an album

/// `GET /deadwax/navidrome/albums/{album_id}`: one album with its songs, in Navidrome's order (disc, then
/// track) - Navidrome's getAlbum passed on as it is (ui/src/player/api.ts AlbumWithSongs). Read leniently, as
/// `Song` is: a field of an unexpected type is absent, and a song that can't be read is left out rather than
/// losing the album.
public struct Album: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String?
    public let artist: String?
    /// The album artist's Navidrome id - what the artist line opens.
    public let artistId: String?
    public let coverArt: String?
    public let songCount: Int?
    /// Seconds.
    public let duration: Double?
    public let year: Int?
    public let genre: String?
    /// OpenSubsonic: the release's MusicBrainz id, as Navidrome read it from the files ("" for none).
    public let musicBrainzId: String?
    /// When the asker starred it (ISO) - with logins on, that it is in their library.
    public let starred: String?
    /// When Navidrome first had it (ISO).
    public let created: String?
    /// OpenSubsonic: when it was last played (ISO), once it has been.
    public let played: String?
    /// How many times the asker has played it, once they have.
    public let playCount: Int?
    /// Its songs; absent from a list's album.
    public let song: [Song]?
    /// OpenSubsonic: the discs that have a title of their own.
    public let discTitles: [DiscTitle]?
    /// OpenSubsonic: the labels the files name.
    public let recordLabels: [RecordLabel]?

    public struct RecordLabel: Codable, Sendable, Equatable, Hashable {
        public let name: String?

        public init(name: String?) { self.name = name }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            name = fields.looseField(String.self, .name)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, artist, artistId, coverArt, songCount, duration, year, genre, musicBrainzId, starred
        case created, played, playCount, song, discTitles, recordLabels
    }

    public init(id: String, name: String? = nil, artist: String? = nil, artistId: String? = nil,
                coverArt: String? = nil, songCount: Int? = nil, duration: Double? = nil, year: Int? = nil,
                genre: String? = nil, musicBrainzId: String? = nil, starred: String? = nil, created: String? = nil,
                played: String? = nil, playCount: Int? = nil, song: [Song]? = nil, discTitles: [DiscTitle]? = nil,
                recordLabels: [RecordLabel]? = nil) {
        self.id = id
        self.name = name
        self.artist = artist
        self.artistId = artistId
        self.coverArt = coverArt
        self.songCount = songCount
        self.duration = duration
        self.year = year
        self.genre = genre
        self.musicBrainzId = musicBrainzId
        self.starred = starred
        self.created = created
        self.played = played
        self.playCount = playCount
        self.song = song
        self.discTitles = discTitles
        self.recordLabels = recordLabels
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        name = fields.looseField(String.self, .name)
        artist = fields.looseField(String.self, .artist)
        artistId = fields.looseField(String.self, .artistId)
        coverArt = fields.looseField(String.self, .coverArt)
        songCount = fields.looseField(Int.self, .songCount)
        duration = fields.looseField(Double.self, .duration)
        year = fields.looseField(Int.self, .year)
        genre = fields.looseField(String.self, .genre)
        musicBrainzId = fields.looseField(String.self, .musicBrainzId)
        starred = fields.looseField(String.self, .starred)
        created = fields.looseField(String.self, .created)
        played = fields.looseField(String.self, .played)
        playCount = fields.looseField(Int.self, .playCount)
        song = fields.looseList(Song.self, .song)
        discTitles = fields.looseList(DiscTitle.self, .discTitles)
        recordLabels = fields.looseList(RecordLabel.self, .recordLabels)
    }

    /// Whether the asker starred it - with logins on, whether it is in their library.
    public var isStarred: Bool { starred?.isEmpty == false }
}

/// One disc's own title - MusicBrainz's medium title, which deadwax writes as `discsubtitle` and Navidrome
/// hands back as OpenSubsonic's `discTitles` on getAlbum. Only the discs that have one.
public struct DiscTitle: Codable, Sendable, Equatable, Hashable {
    /// The disc's number; a string of digits is read as one, anything else is absent.
    public let disc: Int?
    public let title: String?

    public init(disc: Int?, title: String?) {
        self.disc = disc
        self.title = title
    }

    enum CodingKeys: String, CodingKey { case disc, title }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        disc = fields.looseField(Int.self, .disc) ?? fields.looseField(String.self, .disc).flatMap { Int($0) }
        title = fields.looseField(String.self, .title)
    }
}

// MARK: the id bridge (src/routes/store_album.py)

/// `GET /deadwax/store/album?navidrome_id=`: one album across its three ids - the release Navidrome's files are
/// tagged with, the store's folders of it (`present`), its other pressings in the store, and (logins on) whether it
/// is in the asker's library. Asked only when there is a library to ask about (Access.hasLibrary).
public struct StoreAlbum: Codable, Sendable, Equatable {
    public let releaseMbid: String?
    public let releaseGroupMbid: String?
    /// Navidrome's album for the release; nil when Navidrome doesn't have it or can't be asked.
    public let navidromeId: String?
    /// The store's live folders of the release.
    public let present: [StoreRow]
    public let otherPressings: [StoreRow]
    /// Whether the album is in the asker's library - absent when "your library" means the store (logins off, the
    /// break-glass admin) or deadwax couldn't say.
    public let yours: Bool?

    enum CodingKeys: String, CodingKey {
        case releaseMbid = "release_mbid"
        case releaseGroupMbid = "release_group_mbid"
        case navidromeId = "navidrome_id"
        case present
        case otherPressings = "other_pressings"
        case yours
    }

    public init(releaseMbid: String? = nil, releaseGroupMbid: String? = nil, navidromeId: String? = nil,
                present: [StoreRow] = [], otherPressings: [StoreRow] = [], yours: Bool? = nil) {
        self.releaseMbid = releaseMbid
        self.releaseGroupMbid = releaseGroupMbid
        self.navidromeId = navidromeId
        self.present = present
        self.otherPressings = otherPressings
        self.yours = yours
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        releaseMbid = fields.looseField(String.self, .releaseMbid)
        releaseGroupMbid = fields.looseField(String.self, .releaseGroupMbid)
        navidromeId = fields.looseField(String.self, .navidromeId)
        present = fields.looseList(StoreRow.self, .present) ?? []
        otherPressings = fields.looseList(StoreRow.self, .otherPressings) ?? []
        yours = fields.looseField(Bool.self, .yours)
    }
}

/// One folder of the store (`store_album` row): which folder, what is in it - and, on `present` rows, what the
/// saved scan and its review row say of it; on `other_pressings` rows, Navidrome's album for it and whether it is
/// the asker's.
public struct StoreRow: Codable, Sendable, Equatable, Identifiable {
    /// store_album.id: stays put through a re-file or a merge.
    public let id: Int
    /// Relative to LIBRARY_PATH.
    public let path: String
    public let releaseMbid: String?
    public let artist: String?
    public let album: String?
    public let edition: String?
    public let year: String?
    public let formats: [String]?
    public let trackCount: Int?
    /// Bytes, as the saved scan read them (a present row's).
    public let size: Int64?
    /// The year of the folder's `originaldate` tag - "" for none (a present row's).
    public let originalYear: String?
    /// When deadwax first saw the folder, ISO (a present row's).
    public let firstSeen: String?
    /// deadwax filed it (a download) rather than finding it there (a present row's).
    public let imported: Bool?
    /// Navidrome's album for this pressing (another pressing's).
    public let navidromeId: String?
    /// It is in the asker's library (another pressing's).
    public let yours: Bool?

    enum CodingKeys: String, CodingKey {
        case id, path
        case releaseMbid = "release_mbid"
        case artist, album, edition, year, formats
        case trackCount = "track_count"
        case size
        case originalYear = "original_year"
        case firstSeen = "first_seen"
        case imported
        case navidromeId = "navidrome_id"
        case yours
    }

    public init(id: Int, path: String, releaseMbid: String? = nil, artist: String? = nil, album: String? = nil,
                edition: String? = nil, year: String? = nil, formats: [String]? = nil, trackCount: Int? = nil,
                size: Int64? = nil, originalYear: String? = nil, firstSeen: String? = nil, imported: Bool? = nil,
                navidromeId: String? = nil, yours: Bool? = nil) {
        self.id = id
        self.path = path
        self.releaseMbid = releaseMbid
        self.artist = artist
        self.album = album
        self.edition = edition
        self.year = year
        self.formats = formats
        self.trackCount = trackCount
        self.size = size
        self.originalYear = originalYear
        self.firstSeen = firstSeen
        self.imported = imported
        self.navidromeId = navidromeId
        self.yours = yours
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(Int.self, forKey: .id)
        path = try fields.decode(String.self, forKey: .path)
        releaseMbid = fields.looseField(String.self, .releaseMbid)
        artist = fields.looseField(String.self, .artist)
        album = fields.looseField(String.self, .album)
        edition = fields.looseField(String.self, .edition)
        year = fields.looseField(String.self, .year)
        formats = fields.looseField([String].self, .formats)
        trackCount = fields.looseField(Int.self, .trackCount)
        size = fields.looseField(Int64.self, .size)
        originalYear = fields.looseField(String.self, .originalYear)
        firstSeen = fields.looseField(String.self, .firstSeen)
        imported = fields.looseField(Bool.self, .imported)
        navidromeId = fields.looseField(String.self, .navidromeId)
        yours = fields.looseField(Bool.self, .yours)
    }
}

// MARK: your library (src/routes/my_library.py)

/// `POST /deadwax/me/library/add`'s body: the pressing the store holds, as the album page sends it
/// (src/routes/download.py FindCandidatesRequest - the release a Get would download). Built with `from(store:...)`.
public struct AddRelease: Encodable, Sendable, Equatable {
    /// As credited on this release.
    public let artist: String
    public let albumArtist: String?
    public let artistMbids: [String]
    public let album: String
    public let year: String?
    public let originalYear: String?
    public let releaseMbid: String?
    public let releaseGroupMbid: String?
    public let editionTags: [String]

    enum CodingKeys: String, CodingKey {
        case artist
        case albumArtist = "album_artist"
        case artistMbids = "artist_mbids"
        case album, year
        case originalYear = "original_year"
        case releaseMbid = "release_mbid"
        case releaseGroupMbid = "release_group_mbid"
        case editionTags = "edition_tags"
        case tracks
    }

    public init(artist: String, albumArtist: String?, artistMbids: [String] = [], album: String, year: String? = nil,
                originalYear: String? = nil, releaseMbid: String?, releaseGroupMbid: String? = nil,
                editionTags: [String] = []) {
        self.artist = artist
        self.albumArtist = albumArtist
        self.artistMbids = artistMbids
        self.album = album
        self.year = year
        self.originalYear = originalYear
        self.releaseMbid = releaseMbid
        self.releaseGroupMbid = releaseGroupMbid
        self.editionTags = editionTags
    }

    /// What the album page sends (ui/src/player/AlbumPage.tsx changeMine): the store's first present folder's
    /// artist and album, else the album's own; its year; the bridge's release and release group. The release is
    /// sent as the bridge said it, an empty one included - the server says in words that it can't be added.
    public static func from(store: StoreAlbum?, artistName: String, albumName: String?) -> AddRelease {
        let first = store?.present.first
        let artist = said(first?.artist) ?? artistName
        return AddRelease(artist: artist, albumArtist: artist, album: said(first?.album) ?? said(albumName) ?? "",
                          year: said(first?.year), originalYear: nil, releaseMbid: store?.releaseMbid,
                          releaseGroupMbid: store?.releaseGroupMbid)
    }

    /// JS's `||`: an empty string is none.
    private static func said(_ words: String?) -> String? {
        guard let words, !words.isEmpty else { return nil }
        return words
    }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(artist, forKey: .artist)
        try fields.encode(albumArtist, forKey: .albumArtist)
        try fields.encode(artistMbids, forKey: .artistMbids)
        try fields.encode(album, forKey: .album)
        try fields.encode(year, forKey: .year)
        try fields.encode(originalYear, forKey: .originalYear)
        try fields.encode(releaseMbid, forKey: .releaseMbid)
        try fields.encode(releaseGroupMbid, forKey: .releaseGroupMbid)
        try fields.encode(editionTags, forKey: .editionTags)
        // the tracklist a Get would match against; Add files nothing, so none
        try fields.encode([String](), forKey: .tracks)
    }
}

/// `POST /deadwax/me/library/add`'s answer.
public struct AddedToLibrary: Codable, Sendable, Equatable {
    public let added: Bool
    /// It was in the asker's library already.
    public let already: Bool
    /// False: the store holds only part of it, added marked incomplete.
    public let complete: Bool
    /// Starred in Navidrome at once - false: it waits for deadwax's worker to star it.
    public let starred: Bool?

    public init(added: Bool, already: Bool, complete: Bool, starred: Bool? = nil) {
        self.added = added
        self.already = already
        self.complete = complete
        self.starred = starred
    }
}

/// `POST /deadwax/me/library/remove`'s answer: unstarred, out of the asker's library - nothing deleted.
public struct RemovedFromLibrary: Codable, Sendable, Equatable {
    public let removed: Bool
    /// How many of the library's entries went (0 for an album starred elsewhere that deadwax never kept).
    public let entries: Int
    /// What the page says: it's still in the collection, nothing deleted.
    public let words: String

    public init(removed: Bool, entries: Int, words: String) {
        self.removed = removed
        self.entries = entries
        self.words = words
    }
}

/// `POST /deadwax/me/library/remove`'s body (src/routes/my_library.py Remove).
public struct LibraryRemoveBody: Codable, Sendable, Equatable {
    /// Navidrome's album id - the album as the Library shows it.
    public let navidromeId: String

    enum CodingKeys: String, CodingKey {
        case navidromeId = "navidrome_id"
    }

    public init(navidromeId: String) { self.navidromeId = navidromeId }
}

// MARK: reading leniently

fileprivate extension KeyedDecodingContainer {
    /// The field, or nil when it is absent, null or of another type.
    func looseField<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// A list's readable elements, the rest left out; nil when the field is absent or isn't a list.
    func looseList<T: Decodable>(_ type: T.Type, _ key: Key) -> [T]? {
        looseField([LooseElement<T>].self, key)?.compactMap(\.value)
    }
}

/// One element of a list, read or left out.
private struct LooseElement<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: any Decoder) throws {
        value = try? T(from: decoder)
    }
}
