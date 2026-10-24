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
/// off the user is `local`, the shared account, an admin.
public struct Me: Codable, Sendable, Equatable {
    public let user: String
    public let admin: Bool
    public let auth: String
    public let version: String?
    public let permissions: [String]?

    public init(user: String, admin: Bool, auth: String, version: String? = nil, permissions: [String]? = nil) {
        self.user = user
        self.admin = admin
        self.auth = auth
        self.version = version
        self.permissions = permissions
    }

    public var loginsOn: Bool { auth == "on" }
}

/// A song as Navidrome's Subsonic answers describe it, passed on by deadwax as it is. Only what the
/// app reads is declared; everything is optional but the id, since Navidrome leaves out what a file
/// doesn't have (`samplingRate` and `bitDepth` come from OpenSubsonic, and older servers omit them).
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

    public init(id: String, title: String? = nil, album: String? = nil, albumId: String? = nil,
                artist: String? = nil, track: Int? = nil, discNumber: Int? = nil, duration: Double? = nil,
                suffix: String? = nil, contentType: String? = nil, size: Int64? = nil, bitRate: Int? = nil,
                samplingRate: Int? = nil, bitDepth: Int? = nil, channelCount: Int? = nil, coverArt: String? = nil) {
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
