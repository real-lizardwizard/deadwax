import Foundation

// MusicBrainz's answers as deadwax passes them on (Phase 5, slice 2 - notes/ios-specs/phase5-search.md 6.2, 3.6):
// `/search_musicbrainz/fully_search`'s release groups (Search's albums you don't have) and `/release_group`'s pressings
// with their tracklists (the album you don't have) - MusicBrainz's own shapes (ui/src/api/types.ts ReleaseGroup,
// ArtistCredit, Release), read leniently: a field of the wrong shape is absent, a row that can't be read (no id) left
// out, as every answer of deadwax's is read. And the credit's two names (release.ts creditName, currentName), the one
// artist an album is by (artistPage.ts soleCredit) and a MusicBrainz id as MusicBrainz writes one (mbidOf).

/// One name of a credit (`ArtistCredit`): what the sleeve said, what goes between it and the next, and the artist.
public struct MBArtistCredit: Decodable, Sendable, Equatable, Hashable {
    public struct Credited: Decodable, Sendable, Equatable, Hashable {
        public let id: String?
        public let name: String?

        public init(id: String? = nil, name: String? = nil) {
            self.id = id
            self.name = name
        }

        enum CodingKeys: String, CodingKey { case id, name }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            id = fields.looseField(String.self, .id)
            name = fields.looseField(String.self, .name)
        }
    }

    public let name: String?
    /// What MusicBrainz puts between this name and the next: " & ", " feat. ".
    public let joinphrase: String?
    public let artist: Credited?

    public init(name: String? = nil, joinphrase: String? = nil, artist: Credited? = nil) {
        self.name = name
        self.joinphrase = joinphrase
        self.artist = artist
    }

    enum CodingKeys: String, CodingKey { case name, joinphrase, artist }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        name = fields.looseField(String.self, .name)
        joinphrase = fields.looseField(String.self, .joinphrase)
        artist = fields.looseField(Credited.self, .artist)
    }
}

/// A MusicBrainz album (a release group), as `fully_search` and a pressing's `release-group` carry it.
public struct ReleaseGroup: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String?
    public let firstReleaseDate: String?
    public let primaryType: String?
    public let secondaryTypes: [String]?
    public let artistCredit: [MBArtistCredit]?
    /// (Phase 8, slice 1) MusicBrainz's own score for the search that found it (0-100) - the album editor's weakest
    /// tiebreak (Retag.score(_:fields:), release.ts `scoreReleaseGroupMatch`). nil where it gave none.
    public let score: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, score
        case firstReleaseDate = "first-release-date"
        case primaryType = "primary-type"
        case secondaryTypes = "secondary-types"
        case artistCredit = "artist-credit"
    }

    public init(id: String, title: String? = nil, firstReleaseDate: String? = nil, primaryType: String? = nil,
                secondaryTypes: [String]? = nil, artistCredit: [MBArtistCredit]? = nil, score: Double? = nil) {
        self.id = id
        self.title = title
        self.firstReleaseDate = firstReleaseDate
        self.primaryType = primaryType
        self.secondaryTypes = secondaryTypes
        self.artistCredit = artistCredit
        self.score = score
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        title = fields.looseField(String.self, .title)
        firstReleaseDate = fields.looseField(String.self, .firstReleaseDate)
        primaryType = fields.looseField(String.self, .primaryType)
        secondaryTypes = fields.looseList(String.self, .secondaryTypes)
        artistCredit = fields.looseList(MBArtistCredit.self, .artistCredit)
        score = fields.looseField(Double.self, .score)
    }
}

/// `GET /deadwax/search_musicbrainz/fully_search`: the groups found (`{}` - none - when MusicBrainz matched nothing),
/// and how many match in all when MusicBrainz said.
public struct FullySearchAnswer: Decodable, Sendable, Equatable {
    public let releaseGroups: [ReleaseGroup]
    public let count: Int?

    enum CodingKeys: String, CodingKey {
        case releaseGroups = "release-groups"
        case count
    }

    public init(releaseGroups: [ReleaseGroup] = [], count: Int? = nil) {
        self.releaseGroups = releaseGroups
        self.count = count
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        releaseGroups = fields.looseList(ReleaseGroup.self, .releaseGroups) ?? []
        count = fields.looseField(Int.self, .count)
    }
}

/// A track of a pressing (tracklistDiff.ts `MbTrack`): its number as printed, its running position, its title and
/// length (milliseconds), and its recording's. And (Phase 6, slice 2) what a Get sends of it (releasePayload.ts
/// `RawTrack`): the track's own credit, and its recording's credit and video flag - nil where MusicBrainz gave none,
/// an empty credit kept as one (JavaScript's `[]` is truthy: a track credited to nobody is "N/A", not its recording's).
public struct MBTrack: Decodable, Sendable, Equatable, Hashable {
    public struct Recording: Decodable, Sendable, Equatable, Hashable {
        public let id: String?
        public let title: String?
        public let length: Double?
        public let artistCredit: [MBArtistCredit]?
        /// MusicBrainz's own word that the recording is a video - never an audio file (release.ts `isVideoTrack`).
        public let video: Bool?

        public init(id: String? = nil, title: String? = nil, length: Double? = nil, artistCredit: [MBArtistCredit]? = nil,
                    video: Bool? = nil) {
            self.id = id
            self.title = title
            self.length = length
            self.artistCredit = artistCredit
            self.video = video
        }

        enum CodingKeys: String, CodingKey {
            case id, title, length, video
            case artistCredit = "artist-credit"
        }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            id = fields.looseField(String.self, .id)
            title = fields.looseField(String.self, .title)
            length = fields.looseField(Double.self, .length)
            artistCredit = fields.looseList(MBArtistCredit.self, .artistCredit)
            video = fields.looseField(Bool.self, .video)
        }
    }

    public let number: String?
    public let position: Int?
    public let title: String?
    public let length: Double?
    public let recording: Recording?
    public let artistCredit: [MBArtistCredit]?

    public init(number: String? = nil, position: Int? = nil, title: String? = nil, length: Double? = nil,
                recording: Recording? = nil, artistCredit: [MBArtistCredit]? = nil) {
        self.number = number
        self.position = position
        self.title = title
        self.length = length
        self.recording = recording
        self.artistCredit = artistCredit
    }

    enum CodingKeys: String, CodingKey {
        case number, position, title, length, recording
        case artistCredit = "artist-credit"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        number = fields.looseField(String.self, .number)
        position = fields.looseField(Int.self, .position)
        title = fields.looseField(String.self, .title)
        length = fields.looseField(Double.self, .length)
        recording = fields.looseField(Recording.self, .recording)
        artistCredit = fields.looseList(MBArtistCredit.self, .artistCredit)
    }
}

/// A medium of a pressing - a disc, a record (`MbMedium`).
public struct MBMedium: Decodable, Sendable, Equatable, Hashable {
    public let position: Int?
    public let format: String?
    public let title: String?
    public let tracks: [MBTrack]
    /// (Phase 8, slice 1) How many tracks it has as MusicBrainz counts them - there without the tracks themselves, in a
    /// pressing listed `?tracks=false` (the album editor's Choose a release: release.ts `releaseTrackCount`).
    public let trackCount: Int?

    public init(position: Int? = nil, format: String? = nil, title: String? = nil, tracks: [MBTrack] = [],
                trackCount: Int? = nil) {
        self.position = position
        self.format = format
        self.title = title
        self.tracks = tracks
        self.trackCount = trackCount
    }

    enum CodingKeys: String, CodingKey {
        case position, format, title, tracks
        case trackCount = "track-count"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        position = fields.looseField(Int.self, .position)
        format = fields.looseField(String.self, .format)
        title = fields.looseField(String.self, .title)
        tracks = fields.looseList(MBTrack.self, .tracks) ?? []
        trackCount = fields.looseField(Int.self, .trackCount)
    }
}

/// A pressing of an album, as the album you don't have reads it (pressings.ts `PageRelease`).
public struct PageRelease: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public struct LabelInfo: Decodable, Sendable, Equatable, Hashable {
        public let label: String?
        public let catalogNumber: String?

        public init(label: String? = nil, catalogNumber: String? = nil) {
            self.label = label
            self.catalogNumber = catalogNumber
        }

        enum CodingKeys: String, CodingKey {
            case label
            case catalogNumber = "catalog-number"
        }

        private struct Label: Decodable {
            let name: String?

            enum CodingKeys: String, CodingKey { case name }

            init(from decoder: any Decoder) throws {
                name = try decoder.container(keyedBy: CodingKeys.self).looseField(String.self, .name)
            }
        }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            label = fields.looseField(Label.self, .label)?.name
            catalogNumber = fields.looseField(String.self, .catalogNumber)
        }
    }

    public let id: String
    public let title: String?
    public let status: String?
    public let date: String?
    public let country: String?
    /// "" when MusicBrainz says it has none, nil when nobody has entered one.
    public let barcode: String?
    public let disambiguation: String?
    public let media: [MBMedium]
    /// The first of its release events' dates - what a pressing without a `date` is dated by.
    public let eventDates: [String?]
    /// (Phase 6, slice 2) Each release event's country - its area's first ISO 3166-1 code, as a Get sends it
    /// (releasePayload.ts `country`): the raw code, "XE" and "XW" included.
    public let eventCountries: [String?]
    /// "Box", "Jewel Case" - a Box is a box set (release.ts `detectEditionTags`).
    public let packaging: String?
    public let labelInfo: [LabelInfo]
    public let artistCredit: [MBArtistCredit]?
    public let releaseGroup: ReleaseGroup?

    enum CodingKeys: String, CodingKey {
        case id, title, status, date, country, barcode, disambiguation, media, packaging
        case releaseEvents = "release-events"
        case labelInfo = "label-info"
        case artistCredit = "artist-credit"
        case releaseGroup = "release-group"
    }

    private struct Event: Decodable {
        let date: String?
        let country: String?

        enum CodingKeys: String, CodingKey { case date, area }

        private struct Area: Decodable {
            let codes: [String]?

            enum CodingKeys: String, CodingKey { case codes = "iso-3166-1-codes" }

            init(from decoder: any Decoder) throws {
                codes = try decoder.container(keyedBy: CodingKeys.self).looseList(String.self, .codes)
            }
        }

        init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            date = fields.looseField(String.self, .date)
            country = fields.looseField(Area.self, .area)?.codes?.first
        }
    }

    public init(id: String, title: String? = nil, status: String? = nil, date: String? = nil, country: String? = nil,
                barcode: String? = nil, disambiguation: String? = nil, media: [MBMedium] = [], eventDates: [String?] = [],
                labelInfo: [LabelInfo] = [], artistCredit: [MBArtistCredit]? = nil, releaseGroup: ReleaseGroup? = nil,
                eventCountries: [String?] = [], packaging: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.date = date
        self.country = country
        self.barcode = barcode
        self.disambiguation = disambiguation
        self.media = media
        self.eventDates = eventDates
        self.eventCountries = eventCountries
        self.packaging = packaging
        self.labelInfo = labelInfo
        self.artistCredit = artistCredit
        self.releaseGroup = releaseGroup
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        title = fields.looseField(String.self, .title)
        status = fields.looseField(String.self, .status)
        date = fields.looseField(String.self, .date)
        country = fields.looseField(String.self, .country)
        barcode = fields.looseField(String.self, .barcode)
        disambiguation = fields.looseField(String.self, .disambiguation)
        media = fields.looseList(MBMedium.self, .media) ?? []
        let events = fields.looseList(Event.self, .releaseEvents) ?? []
        eventDates = events.map(\.date)
        eventCountries = events.map(\.country)
        packaging = fields.looseField(String.self, .packaging)
        labelInfo = fields.looseList(LabelInfo.self, .labelInfo) ?? []
        artistCredit = fields.looseList(MBArtistCredit.self, .artistCredit)
        releaseGroup = fields.looseField(ReleaseGroup.self, .releaseGroup)
    }

    /// `release.date || release['release-events']?.[0]?.date || ''` - the date a pressing is known by.
    public var knownDate: String {
        if let date, !date.isEmpty { return date }
        if let first = eventDates.first, let date = first, !date.isEmpty { return date }
        return ""
    }
}

/// `GET /deadwax/search_musicbrainz/release_group`: every pressing of one album with its tracklist - and `problem`
/// when MusicBrainz failed part way, so the list is not the album's pressings.
public struct ReleaseGroupAnswer: Decodable, Sendable, Equatable {
    public let id: String
    public let releases: [PageRelease]
    public let problem: String?

    enum CodingKeys: String, CodingKey { case id, releases, problem }

    public init(id: String, releases: [PageRelease], problem: String? = nil) {
        self.id = id
        self.releases = releases
        self.problem = problem
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = fields.looseField(String.self, .id) ?? ""
        releases = fields.looseList(PageRelease.self, .releases) ?? []
        problem = fields.looseField(String.self, .problem)
    }
}

/// A MusicBrainz artist as a row of the list (`ArtistMatch`): one `/artists` found (src/artists.py's artist_match),
/// or one made from a credit, Top results' relative of a MusicBrainz album (`creditArtist`: no disambiguation, type
/// or country). Read leniently, every field "" when absent or of the wrong shape.
public struct MBArtistMatch: Decodable, Sendable, Equatable, Hashable {
    public let mbid: String
    public let name: String
    public let disambiguation: String
    public let country: String
    public let type: String
    public let matchedAs: String

    enum CodingKeys: String, CodingKey {
        case mbid, name, disambiguation, country, type
        case matchedAs = "matched_as"
    }

    public init(mbid: String, name: String, disambiguation: String = "", country: String = "", type: String = "",
                matchedAs: String = "") {
        self.mbid = mbid
        self.name = name
        self.disambiguation = disambiguation
        self.country = country
        self.type = type
        self.matchedAs = matchedAs
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        mbid = fields.looseField(String.self, .mbid) ?? ""
        name = fields.looseField(String.self, .name) ?? ""
        disambiguation = fields.looseField(String.self, .disambiguation) ?? ""
        country = fields.looseField(String.self, .country) ?? ""
        type = fields.looseField(String.self, .type) ?? ""
        matchedAs = fields.looseField(String.self, .matchedAs) ?? ""
    }

    /// Its line (artistManage.ts `matchLine`): "as …" when matched by another name, its disambiguation, its type and
    /// country - "" for a credit's.
    public var line: String {
        let kind = [type, country].filter { !$0.isEmpty }.joined(separator: " · ")
        return [!matchedAs.isEmpty && !WebText.same(matchedAs, name) ? "as \(matchedAs)" : "", disambiguation, kind]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// What a Cover Art Archive front is asked by through deadwax's relay (`GET /deadwax/coverart/{kind}/{mbid}`): a
/// pressing's, or an album's - the mbid as MusicBrainz gave it (the relay refuses an uppercase one).
public struct ArchiveCoverID: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, Equatable, Hashable {
        case release
        case releaseGroup = "release-group"
    }

    public let kind: Kind
    public let mbid: String

    public init(_ kind: Kind, _ mbid: String) {
        self.kind = kind
        self.mbid = mbid
    }

    /// The fronts the album you don't have tries, in turn (pressings.ts `coverAddresses`): the pressing shown's, then
    /// the album's.
    public static func addresses(release: String?, group: String) -> [ArchiveCoverID] {
        var out: [ArchiveCoverID] = []
        if let release, !release.isEmpty { out.append(ArchiveCoverID(.release, release)) }
        out.append(ArchiveCoverID(.releaseGroup, group))
        return out
    }
}

/// A credit's two names, and the one artist it may be (release.ts, artistPage.ts).
public enum Credits {
    /// "Simon & Garfunkel": each name as credited, then what goes between - trimmed (`creditName`).
    public static func name(_ credit: [MBArtistCredit]?) -> String {
        JSText.trim((credit ?? []).map { (entry: MBArtistCredit) -> String in
            first(entry.name, entry.artist?.name) + (entry.joinphrase ?? "")
        }.joined())
    }

    /// The same credit in each artist's current name - what an album is filed under (`currentName`).
    public static func current(_ credit: [MBArtistCredit]?) -> String {
        JSText.trim((credit ?? []).map { (entry: MBArtistCredit) -> String in
            first(entry.artist?.name, entry.name) + (entry.joinphrase ?? "")
        }.joined())
    }

    /// The one artist an album is credited to, by MusicBrainz id (`soleCredit`) - nil for a collaboration or a credit
    /// with no id.
    public static func sole(_ credit: [MBArtistCredit]?) -> (mbid: String, name: String)? {
        guard let credit, credit.count == 1, let mbid = MBID.of(credit[0].artist?.id) else { return nil }
        let name = JSText.trim(first(credit[0].name, credit[0].artist?.name))
        return name.isEmpty ? nil : (mbid, name)
    }

    /// `a || b || ''`.
    static func first(_ a: String?, _ b: String?) -> String {
        if let a, !a.isEmpty { return a }
        if let b, !b.isEmpty { return b }
        return ""
    }
}

/// A MusicBrainz id as MusicBrainz writes one (artistPage.ts `mbidOf`, pressings.ts `groupMbid`).
public enum MBID {
    /// The id trimmed and lowercased, when it is one - else nil.
    public static func of(_ value: String?) -> String? {
        let id = JSText.lowercase(JSText.trim(value ?? ""))
        return isOne(id) ? id : nil
    }

    /// `/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/`.
    public static func isOne(_ id: String) -> Bool {
        let units = Array(id.utf16)
        guard units.count == 36 else { return false }
        for (at, unit) in units.enumerated() {
            if at == 8 || at == 13 || at == 18 || at == 23 {
                if unit != 0x2D { return false }
            } else if !((unit >= 0x30 && unit <= 0x39) || (unit >= 0x61 && unit <= 0x66)) {
                return false
            }
        }
        return true
    }
}
