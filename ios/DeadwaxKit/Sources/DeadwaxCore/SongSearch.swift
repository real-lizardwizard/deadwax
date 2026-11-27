import Foundation

// MusicBrainz's songs in Search (Phase 5, slice 3 - notes/ios-specs/phase5-search.md 2.3, 6.3): the web's
// ui/src/lib/songs.ts - a recording search's answer made into SONGS (every take of one title by one credit one row,
// their albums unioned and ordered so the studio album leads), what the library holds of each album a song is on and
// whether that is the song, the album a song's row names, an album's line under its song, the fold's words, and the
// album opened from a song: the pressing that has it and the song marked in its tracklist - and searchQuery.ts's song
// queries. Held to the web by Fixtures/search/search-songs-vectors.json (ios/scripts/export-search-songs-vectors.cjs),
// which runs the web's own functions over the real answers in tests/fixtures/songs/.

// MARK: what /songs answers

/// A track of a release a recording is on, as the recording search carries it (types.ts `RecordingTrack`).
public struct MBRecordingTrack: Decodable, Sendable, Equatable, Hashable {
    public let id: String?
    public let number: String?
    public let title: String?
    /// Milliseconds.
    public let length: Double?

    enum CodingKeys: String, CodingKey { case id, number, title, length }

    public init(id: String? = nil, number: String? = nil, title: String? = nil, length: Double? = nil) {
        self.id = id
        self.number = number
        self.title = title
        self.length = length
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = fields.looseField(String.self, .id)
        number = fields.looseField(String.self, .number)
        title = fields.looseField(String.self, .title)
        length = fields.looseField(Double.self, .length)
    }
}

/// A medium of a release a recording is on - only the recording's own track (`track`).
public struct MBRecordingMedium: Decodable, Sendable, Equatable, Hashable {
    public let position: Int?
    public let format: String?
    public let track: [MBRecordingTrack]

    enum CodingKeys: String, CodingKey { case position, format, track }

    public init(position: Int? = nil, format: String? = nil, track: [MBRecordingTrack] = []) {
        self.position = position
        self.format = format
        self.track = track
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        position = fields.looseField(Int.self, .position)
        format = fields.looseField(String.self, .format)
        track = fields.looseList(MBRecordingTrack.self, .track) ?? []
    }
}

/// A release a recording is on (`RecordingRelease`): its status, date and credit, its album (`release-group` - one
/// without an id is no album), and the recording's track on it.
public struct MBRecordingRelease: Decodable, Sendable, Equatable, Hashable {
    public let id: String?
    public let title: String?
    public let status: String?
    public let date: String?
    public let country: String?
    public let artistCredit: [MBArtistCredit]?
    public let releaseGroup: ReleaseGroup?
    public let media: [MBRecordingMedium]

    enum CodingKeys: String, CodingKey {
        case id, title, status, date, country, media
        case artistCredit = "artist-credit"
        case releaseGroup = "release-group"
    }

    public init(id: String? = nil, title: String? = nil, status: String? = nil, date: String? = nil,
                country: String? = nil, artistCredit: [MBArtistCredit]? = nil, releaseGroup: ReleaseGroup? = nil,
                media: [MBRecordingMedium] = []) {
        self.id = id
        self.title = title
        self.status = status
        self.date = date
        self.country = country
        self.artistCredit = artistCredit
        self.releaseGroup = releaseGroup
        self.media = media
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = fields.looseField(String.self, .id)
        title = fields.looseField(String.self, .title)
        status = fields.looseField(String.self, .status)
        date = fields.looseField(String.self, .date)
        country = fields.looseField(String.self, .country)
        artistCredit = fields.looseList(MBArtistCredit.self, .artistCredit)
        releaseGroup = fields.looseField(ReleaseGroup.self, .releaseGroup)
        media = fields.looseList(MBRecordingMedium.self, .media) ?? []
    }
}

/// A recording - one performance of a song (`Recording`): its title, credit and length, and every release it is on.
public struct MBRecording: Decodable, Sendable, Equatable, Hashable {
    public let id: String?
    public let title: String?
    public let length: Double?
    /// "live, 2008-04-07: Heineken Music Hall, Amsterdam, Netherlands" for most live tapes.
    public let disambiguation: String?
    public let artistCredit: [MBArtistCredit]?
    public let releases: [MBRecordingRelease]

    enum CodingKeys: String, CodingKey {
        case id, title, length, disambiguation, releases
        case artistCredit = "artist-credit"
    }

    public init(id: String? = nil, title: String? = nil, length: Double? = nil, disambiguation: String? = nil,
                artistCredit: [MBArtistCredit]? = nil, releases: [MBRecordingRelease] = []) {
        self.id = id
        self.title = title
        self.length = length
        self.disambiguation = disambiguation
        self.artistCredit = artistCredit
        self.releases = releases
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = fields.looseField(String.self, .id)
        title = fields.looseField(String.self, .title)
        length = fields.looseField(Double.self, .length)
        disambiguation = fields.looseField(String.self, .disambiguation)
        artistCredit = fields.looseList(MBArtistCredit.self, .artistCredit)
        releases = fields.looseList(MBRecordingRelease.self, .releases) ?? []
    }
}

/// `GET /deadwax/search_musicbrainz/songs` (`SongSearchResponse`): the recordings matching a query, each with every
/// release it is on - none when MusicBrainz matched nothing - and how many match in all when MusicBrainz said.
public struct SongSearchAnswer: Decodable, Sendable, Equatable {
    public let recordings: [MBRecording]
    public let count: Int?

    enum CodingKeys: String, CodingKey { case recordings, count }

    public init(recordings: [MBRecording] = [], count: Int? = nil) {
        self.recordings = recordings
        self.count = count
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        recordings = fields.looseList(MBRecording.self, .recordings) ?? []
        count = fields.looseField(Int.self, .count)
    }
}

// MARK: songs

/// Which band an album sits in under its song (`SongBand`): Albums and EPs, Singles, or the rest - folded.
public enum SongBand: String, Sendable, Equatable, Hashable {
    case album, single, other

    var rank: Int {
        switch self {
        case .album: return 0
        case .single: return 1
        case .other: return 2
        }
    }
}

/// An artist a song's credit names, by MusicBrainz id (lowercase) and the name the credit gives them.
public struct SongArtist: Sendable, Equatable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// One album a song is on (`SongAlbum`): a release group, as the song's releases in it tell it.
public struct SongAlbum: Sendable, Equatable, Hashable, Identifiable {
    /// The release group's id (lowercase).
    public let id: String
    public let title: String
    public let primaryType: String?
    public let secondaryTypes: [String]
    /// "Album", "EP", "Single", "Compilation", "Live album"… (groupKind's words).
    public let kind: String
    public let band: SongBand
    /// The best status of its releases that have the song: "Official", "Promotion", "Bootleg", or "".
    public internal(set) var status: String
    /// The earliest date any of them came out, "" when none says.
    public internal(set) var date: String
    /// Who the album is credited to - "Various Artists" for most compilations.
    public let credit: String
    /// Its releases that have the song, by id (lowercase).
    public internal(set) var releases: [String]
    /// The song's recordings on it, by id (lowercase).
    public internal(set) var recordings: [String]
    /// The song's length on it in milliseconds, or nil.
    public internal(set) var length: Double?

    public init(id: String, title: String, primaryType: String? = nil, secondaryTypes: [String] = [], kind: String,
                band: SongBand, status: String = "", date: String = "", credit: String = "", releases: [String] = [],
                recordings: [String] = [], length: Double? = nil) {
        self.id = id
        self.title = title
        self.primaryType = primaryType
        self.secondaryTypes = secondaryTypes
        self.kind = kind
        self.band = band
        self.status = status
        self.date = date
        self.credit = credit
        self.releases = releases
        self.recordings = recordings
        self.length = length
    }

    /// The album as a MusicBrainz album, for the cover and the busy look: its id, title and types.
    public var group: ReleaseGroup {
        ReleaseGroup(id: id, title: title, primaryType: primaryType, secondaryTypes: secondaryTypes)
    }
}

/// A song MusicBrainz found (songs.ts `Song`, searchList.ts's `FoundSong`): every recording of one title by one credit
/// that a search found, and the albums they are on - never none.
public struct FoundSong: Sendable, Equatable, Hashable, Identifiable {
    public let key: String
    public let title: String
    public let credit: String
    /// The artists its credit names - what Top results pull in for it (its sole credited artist).
    public let artists: [SongArtist]
    /// Its recordings, by id (lowercase), in the order found.
    public let recordings: [String]
    /// The albums it is on, sorted (`sortAlbums`).
    public let albums: [SongAlbum]

    public var id: String { key }

    public init(key: String, title: String, credit: String, artists: [SongArtist] = [], recordings: [String] = [],
                albums: [SongAlbum]) {
        self.key = key
        self.title = title
        self.credit = credit
        self.artists = artists
        self.recordings = recordings
        self.albums = albums
    }
}

/// What else says a pressing you hold has the song (`SongEvidence`): the library half's songs (search3's, whatever its
/// words - `heard`), and the album's pressings with their tracklists when the session already has them (`pressings`,
/// by the album's id - GroupPageModel's kept lists).
public struct SongEvidence: Sendable {
    public var heard: [Song]?
    public var pressings: [String: [PageRelease]]

    public init(heard: [Song]? = nil, pressings: [String: [PageRelease]] = [:]) {
        self.heard = heard
        self.pressings = pressings
    }

    public static let none = SongEvidence()
}

/// What the library holds of a song's album (`SongHolding`): the folders of a pressing that has the song (`song`), of
/// one the library's own search shows the song on (`heard`, with `albums` their Navidrome albums), and of one nothing
/// here says has it or hasn't (`other`).
public struct SongHolding: Sendable, Equatable {
    public var song: [OwnedAlbum] = []
    public var heard: [OwnedAlbum] = []
    public var other: [OwnedAlbum] = []
    public var albums: [String] = []

    public init(song: [OwnedAlbum] = [], heard: [OwnedAlbum] = [], other: [OwnedAlbum] = [], albums: [String] = []) {
        self.song = song
        self.heard = heard
        self.other = other
        self.albums = albums
    }
}

public enum SongSearch {
    /// How many recordings a song search asks for (`SONG_SEARCH_LIMIT`, the route's own default).
    public static let limit = 25
    /// How many of a song's recordings an album's address carries, at most (`SONG_IDS_KEPT`).
    public static let idsKept = 8

    // MARK: the words

    /// A Songs view under the artist reading (searchList.ts `SONGS_NEED_A_TITLE`).
    public static let needATitle = "Type a song's title with the artist (\u{201C}roads portishead\u{201D}) to find songs you don't have yet."
    /// What VoiceOver hears on the song an album was opened from (ReleaseGroupPage.tsx `SONG_WORDS`).
    public static let songWords = ", the song you searched for"

    /// What VoiceOver hears of a MusicBrainz song's row, the disclosure onto its albums (the phone's own - the web's
    /// `aria-expanded`): what a tap does now.
    public static func disclosureHint(open: Bool) -> String {
        open ? "Hides the albums it's on." : "Shows the albums it's on."
    }

    /// ...and of its fold's button (the web's `aria-expanded` on `app-song-fold`).
    public static func foldHint(open: Bool) -> String {
        open ? "Hides them." : "Shows them."
    }

    /// Songs found, none on an album (Search.tsx `noReleaseWords`).
    public static func noRelease(_ term: String) -> String {
        "Found songs called \u{201C}\(term)\u{201D}, but none is on an album yet - there's nothing to get."
    }

    // MARK: the queries (searchQuery.ts)

    /// A title by an artist you have (`fieldedSongQuery`).
    public static func fieldedQuery(title: String, artist: String) -> String {
        let artist = SearchReading.quoteTerm(artist)
        return "recording:\(SearchReading.quoteTerm(title)) AND (artist:\(artist) OR artistname:\(artist))"
    }

    /// What the song search asks for the box as read (`songSearchQuery`): a title beside an artist you have is that song
    /// by them; anything else the words typed; an artist's name alone asks nothing. Nil for nothing to ask.
    public static func query(_ text: String, _ plan: SearchPlan?) -> String? {
        guard let plan, plan.kind != .artist else { return nil }
        if plan.kind == .albumByArtist, let title = plan.title, !title.isEmpty, let artist = plan.artist, !artist.isEmpty {
            return fieldedQuery(title: title, artist: artist)
        }
        let words = SearchReading.words(text).joined(separator: " ")
        return words.isEmpty ? nil : words
    }

    /// What it falls back to when a title beside an artist found no song by them (`songTitleQuery`): the words typed as
    /// one title.
    public static func titleQuery(_ text: String) -> String? {
        let words = SearchReading.words(text).joined(separator: " ")
        return words.isEmpty ? nil : "recording:\(SearchReading.quoteTerm(words))"
    }

    // MARK: grouping

    static func lower(_ id: String?) -> String { JSText.lowercase(JSText.trim(id ?? "")) }

    static func has(_ list: [String], _ id: String) -> Bool { list.contains { WebText.same($0, id) } }

    /// `STATUS_RANK`: Official, Promotion, Bootleg, then anything else.
    static func statusRank(_ status: String?) -> Int {
        switch JSText.lowercase(status ?? "") {
        case "official": return 0
        case "promotion": return 1
        case "bootleg": return 2
        default: return 3
        }
    }

    /// `dateKey`: "~" after every digit and "-" - a full date before its bare year, the undated last.
    static func dateKey(_ date: String) -> [UInt16] { Array((date + "~").utf16) }

    /// Which song a recording is (`songKey`): its title and its credit - by the artists' ids where it names them, else
    /// by the credit's words.
    public static func key(_ recording: MBRecording) -> String {
        let credit = recording.artistCredit ?? []
        let ids = credit.map { JSText.lowercase($0.artist?.id ?? "") }.filter { !$0.isEmpty }
            .sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
        let who = ids.isEmpty ? SongTitle.key(Credits.name(credit)) : ids.joined(separator: "+")
        return "\(who)\n\(SongTitle.key(recording.title))"
    }

    /// The band an album sits in (`songBand`): anything with a secondary type folded; Albums and EPs; Singles.
    public static func band(_ primaryType: String?, _ secondaryTypes: [String]?) -> SongBand {
        if !(secondaryTypes ?? []).isEmpty { return .other }
        let primary = JSText.lowercase(primaryType ?? "")
        if primary == "album" || primary == "ep" { return .album }
        return primary == "single" ? .single : .other
    }

    /// A song's albums in the order listed (`sortAlbums`): the bands, Official before Promotion before Bootleg, the
    /// earliest first, then by title and id (`collate`).
    public static func sortAlbums(_ albums: [SongAlbum]) -> [SongAlbum] {
        albums.enumerated().sorted { (a: (offset: Int, element: SongAlbum), b: (offset: Int, element: SongAlbum)) -> Bool in
            let (x, y) = (a.element, b.element)
            if x.band != y.band { return x.band.rank < y.band.rank }
            let ranks = (statusRank(x.status), statusRank(y.status))
            if ranks.0 != ranks.1 { return ranks.0 < ranks.1 }
            let dates = (dateKey(x.date), dateKey(y.date))
            if dates.0 != dates.1 { return dates.0.lexicographicallyPrecedes(dates.1) }
            let title = collate(x.title, y.title)
            if title != 0 { return title < 0 }
            let id = collate(x.id, y.id)
            if id != 0 { return id < 0 }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// `localeCompare`'s sign for two titles - ICU's collation, as `WebCollation` approximates it (punctuation weighed in
    /// ICU's order: a bootleg's "1984-09-24" before another's "1984\u{2010}09\u{2010}15").
    public static func collate(_ a: String, _ b: String) -> Int { WebCollation.compare(a, b) }

    /// The song's length on a release, as the recording search carries its track.
    static func trackLength(_ release: MBRecordingRelease) -> Double? {
        for medium in release.media {
            for track in medium.track {
                if let length = track.length, length.isFinite { return length }
            }
        }
        return nil
    }

    /// The artists a credit names, each once, by id (lowercase) and the name the credit gives them (`creditArtists`).
    static func artists(_ credit: [MBArtistCredit]?) -> [SongArtist] {
        var out: [SongArtist] = []
        for entry in credit ?? [] {
            let id = lower(entry.artist?.id)
            let name = JSText.trim(Credits.first(entry.name, entry.artist?.name))
            if !id.isEmpty && !out.contains(where: { WebText.same($0.id, id) }) { out.append(SongArtist(id: id, name: name)) }
        }
        return out
    }

    /// The songs a search found (`groupSongs`): its recordings of one title by one credit made one song, in the order
    /// MusicBrainz first gave each, each with the albums its recordings are on - one per release group, unioned -
    /// sorted. A song on no release is left out: there is no album to show it on, or to get.
    public static func group(_ recordings: [MBRecording]) -> [FoundSong] {
        struct Making {
            var title: String
            let credit: String
            let artists: [SongArtist]
            var recordings: [String] = []
            var albums: [SongAlbum] = []
            var at: [FoldKey: Int] = [:]
        }
        var order: [String] = []
        var songs: [FoldKey: Making] = [:]
        for recording in recordings {
            let key = self.key(recording)
            let slot = FoldKey(key)
            var song: Making
            if let found = songs[slot] {
                song = found
            } else {
                order.append(key)
                song = Making(title: recording.title ?? "", credit: Credits.name(recording.artistCredit),
                              artists: artists(recording.artistCredit))
            }
            //? the row says the song by a plain title - "Roads", not "Roads (live)" - when any take has one
            if SongTitle.hasAside(song.title), let title = recording.title, !title.isEmpty, !SongTitle.hasAside(title) {
                song.title = title
            }
            let id = lower(recording.id)
            if !id.isEmpty && !has(song.recordings, id) { song.recordings.append(id) }
            for release in recording.releases {
                let group = release.releaseGroup
                let groupId = lower(group?.id)
                if groupId.isEmpty { continue }
                let length = trackLength(release) ?? recording.length
                let date = JSText.trim(release.date ?? "")
                let releaseId: String? = (release.id ?? "").isEmpty ? nil : lower(release.id)
                guard let at = song.at[FoldKey(groupId)] else {
                    let primary = group?.primaryType
                    let secondary = group?.secondaryTypes ?? []
                    let kind = SearchAlbums.kind(ReleaseGroup(id: groupId, primaryType: (primary ?? "").isEmpty ? nil : primary,
                                                              secondaryTypes: secondary))
                    let credit = Credits.first(Credits.name(release.artistCredit), Credits.name(recording.artistCredit))
                    song.at[FoldKey(groupId)] = song.albums.count
                    song.albums.append(SongAlbum(id: groupId, title: group?.title ?? release.title ?? "", primaryType: primary,
                                                 secondaryTypes: secondary, kind: kind, band: band(primary, secondary),
                                                 status: release.status ?? "", date: date, credit: credit,
                                                 releases: releaseId.map { [$0] } ?? [], recordings: id.isEmpty ? [] : [id],
                                                 length: length))
                    continue
                }
                var was = song.albums[at]
                if statusRank(release.status) < statusRank(was.status) { was.status = release.status ?? "" }
                if !date.isEmpty && (was.date.isEmpty || dateKey(date).lexicographicallyPrecedes(dateKey(was.date))) {
                    was.date = date
                }
                if let releaseId, !has(was.releases, releaseId) { was.releases.append(releaseId) }
                if !id.isEmpty && !has(was.recordings, id) { was.recordings.append(id) }
                if was.length == nil { was.length = length }
                song.albums[at] = was
            }
            songs[slot] = song
        }
        return order.compactMap { (key: String) -> FoundSong? in
            guard let song = songs[FoldKey(key)], !song.albums.isEmpty else { return nil }
            return FoundSong(key: key, title: song.title, credit: song.credit, artists: song.artists,
                             recordings: song.recordings, albums: sortAlbums(song.albums))
        }
    }

    // MARK: the albums under a song

    /// A song's albums split for drawing (`songAlbumBands`): Albums, EPs and Singles listed; the rest behind the fold.
    public static func bands(_ song: FoundSong) -> (listed: [SongAlbum], folded: [SongAlbum]) {
        (song.albums.filter { $0.band != .other }, song.albums.filter { $0.band == .other })
    }

    enum Family: CaseIterable {
        case compilation, live, soundtrack, broadcast, other

        var words: (one: String, many: String) {
            switch self {
            case .compilation: return ("compilation", "compilations")
            case .live: return ("live album", "live albums")
            case .soundtrack: return ("soundtrack", "soundtracks")
            case .broadcast: return ("broadcast", "broadcasts")
            case .other: return ("other record", "other records")
            }
        }
    }

    /// What a folded album is, for the fold's words (`family`): a live record is a "live album" only when it is an album.
    static func family(_ album: SongAlbum) -> Family {
        let types = album.secondaryTypes.map { JSText.lowercase($0) }
        let primary = JSText.lowercase(album.primaryType ?? "")
        if types.contains("compilation") { return .compilation }
        if types.contains("live") && (primary.isEmpty || primary == "album") { return .live }
        if types.contains("soundtrack") { return .soundtrack }
        if primary == "broadcast" { return .broadcast }
        return .other
    }

    /// The fold's words (`foldLabel`): "On 1 compilation", "On 11 compilations, live albums and soundtracks".
    public static func foldLabel(_ folded: [SongAlbum]) -> String {
        let present = Family.allCases.filter { (each: Family) -> Bool in folded.contains { family($0) == each } }
        let words = present.map { folded.count == 1 ? $0.words.one : $0.words.many }
        let listed: String
        if words.count > 1 {
            listed = "\(words.dropLast().joined(separator: ", ")) and \(words[words.count - 1])"
        } else {
            listed = words.first ?? "other records"
        }
        return "On \(folded.count) \(listed)"
    }

    // MARK: what the library holds of a song's album

    /// The tracks of a pressing, as `release_group` carries them.
    static func tracks(_ release: PageRelease) -> [MBTrack] { release.media.flatMap(\.tracks) }

    static func isRecording(_ track: MBTrack, _ wanted: Set<FoldKey>) -> Bool {
        wanted.contains(FoldKey(lower(track.recording?.id)))
    }

    /// Which tracks of an album are the song (`songMatcher`): one of its recordings, or one titled as a track of those
    /// recordings is (titleKey). Nil when no pressing has one of its recordings: nothing to know the song by.
    public static func matcher(_ releases: [PageRelease], _ ids: [String]) -> ((MBTrack) -> Bool)? {
        let wanted = Set(ids.map { FoldKey(lower($0)) })
        if wanted.isEmpty { return nil }
        var titles = Set<FoldKey>()
        for release in releases {
            for track in tracks(release) where isRecording(track, wanted) {
                for title in [track.title, track.recording?.title] {
                    let key = SongTitle.key(title)
                    if !key.isEmpty { titles.insert(FoldKey(key)) }
                }
            }
        }
        if titles.isEmpty { return nil }
        return { (track: MBTrack) -> Bool in
            isRecording(track, wanted) || titles.contains(FoldKey(SongTitle.key(track.title)))
                || titles.contains(FoldKey(SongTitle.key(track.recording?.title)))
        }
    }

    /// The releases of an album's pressings (as kept) that have the song (`pressingsWith`) - nil when nothing can be told.
    static func pressingsWith(_ releases: [PageRelease]?, _ ids: [String]) -> Set<FoldKey>? {
        guard let releases, !releases.isEmpty, let matches = matcher(releases, ids) else { return nil }
        return Set(releases.filter { !$0.id.isEmpty && tracks($0).contains(where: matches) }.map { FoldKey(lower($0.id)) })
    }

    /// The library half's songs that are this song on this folder's album: their Navidrome album ids (`heardOn`).
    static func heardOn(_ heard: [Song]?, _ song: FoundSong, _ folder: OwnedAlbum) -> [String] {
        let title = SongTitle.key(song.title)
        let credit = Fold.key(song.credit)
        let name = Fold.key(folder.album)
        guard let heard, !heard.isEmpty, !title.isEmpty, !credit.isEmpty, !name.isEmpty else { return [] }
        return heard.compactMap { (each: Song) -> String? in
            guard let album = each.albumId, !album.isEmpty, WebText.same(SongTitle.key(each.title), title),
                  WebText.same(Fold.key(each.artist), credit), WebText.same(Fold.key(each.album), name) else { return nil }
            return album
        }
    }

    /// What the library holds of a song's album, split by whether it has the song (`songAlbumHolding`): a pressing it
    /// was found on, or whose kept tracklist has it, or with no release id - the song; another the library's own search
    /// shows it on - heard; another nothing says has it or hasn't - other. All empty without the library's answer.
    public static func holding(_ index: OwnedIndex?, _ album: SongAlbum, _ song: FoundSong? = nil,
                               _ evidence: SongEvidence = .none) -> SongHolding {
        let releases = Set(album.releases.map { FoldKey(lower($0)) })
        var holding = SongHolding()
        var pressed: Set<FoldKey>?
        var looked = false
        for folder in OwnedIndex.forGroup(index, groupId: album.id, releaseIds: album.releases).held {
            let release = lower(folder.releaseMbid)
            if release.isEmpty || releases.contains(FoldKey(release)) {
                holding.song.append(folder)
                continue
            }
            if !looked {
                pressed = pressingsWith(evidence.pressings[album.id], album.recordings)
                looked = true
            }
            if let pressed, pressed.contains(FoldKey(release)) {
                holding.song.append(folder)
                continue
            }
            let albums = song.map { heardOn(evidence.heard, $0, folder) } ?? []
            if !albums.isEmpty {
                holding.heard.append(folder)
                for id in albums where !has(holding.albums, id) { holding.albums.append(id) }
                continue
            }
            holding.other.append(folder)
        }
        return holding
    }

    /// The folders held of a song's album that have the song (`songAlbumHeld`).
    public static func held(_ index: OwnedIndex?, _ album: SongAlbum, _ song: FoundSong? = nil,
                            _ evidence: SongEvidence = .none) -> [OwnedAlbum] {
        let holding = self.holding(index, album, song, evidence)
        return holding.song + holding.heard
    }

    /// The releases of a song's album held with the song by its release or its tracklist, in heldInOrder's order
    /// (`songAlbumHeldReleases`) - what the id bridge is asked about.
    public static func heldReleases(_ index: OwnedIndex?, _ album: SongAlbum, _ song: FoundSong? = nil,
                                    _ evidence: SongEvidence = .none) -> [String] {
        let ids = SearchAlbums.heldInOrder(holding(index, album, song, evidence).song).map { lower($0.releaseMbid) }
        return WebText.unique(ids.filter { !$0.isEmpty })
    }

    static func anyYours(_ albums: [OwnedAlbum]) -> Bool { albums.contains { $0.yours != false } }

    /// Where a held album is, in a line's words (`heldWords`): "in your library" / "in the collection" - "" for none.
    public static func heldWords(_ held: [OwnedAlbum], personal: Bool) -> String {
        held.isEmpty ? "" : Whose.heldPhrase(personal: personal, yours: anyYours(held))
    }

    /// Where a song's album is held, for its row under the song (`songAlbumWords`): heldWords for a pressing with the
    /// song; "a pressing in your library" for only a pressing nothing says has it; "" for none.
    public static func albumWords(_ holding: SongHolding, personal: Bool) -> String {
        let held = holding.song + holding.heard
        if !held.isEmpty { return heldWords(held, personal: personal) }
        return holding.other.isEmpty ? "" : "a pressing \(Whose.heldPhrase(personal: personal, yours: anyYours(holding.other)))"
    }

    /// The album a song's row names (`namedAlbum`): the first you have the song on - one of yours before one only the
    /// collection has - else the first it is on.
    public static func namedAlbum(_ song: FoundSong, _ index: OwnedIndex?,
                                  _ evidence: SongEvidence = .none) -> (album: SongAlbum, held: [OwnedAlbum]) {
        var store: (album: SongAlbum, held: [OwnedAlbum])?
        for album in song.albums {
            let held = self.held(index, album, song, evidence)
            if held.isEmpty { continue }
            if anyYours(held) { return (album, held) }
            if store == nil { store = (album, held) }
        }
        if let store { return store }
        return (song.albums[0], [])
    }

    /// The song's length on an album, "4:56" - "" for none.
    static func length(_ ms: Double?) -> String {
        guard let ms else { return "" }
        return Tracklist.clock(Tracklist.seconds(ms))
    }

    static func yearOf(_ date: String) -> String {
        let year = WebText.prefix(date, 4)
        return WebText.fourDigits(year) ? year : ""
    }

    /// An album's line under its song (`songAlbumLine`): "Album · 1994", "Live album · Bootleg · 2008 · 6:06" - its
    /// kind, its status unless Official, its credit when not the song's, its year, the song's length when another
    /// version's against the row's, and where it is held.
    public static func albumLine(_ album: SongAlbum, _ song: FoundSong, _ index: OwnedIndex?, personal: Bool = false,
                                 _ evidence: SongEvidence = .none) -> String {
        let rowLength = namedAlbum(song, index, evidence).album.length
        var other = false
        if let length = album.length, let rowLength,
           let mine = Tracklist.seconds(length), let row = Tracklist.seconds(rowLength) {
            other = Tracklist.isOtherVersion(mine - row, base: row)
        }
        let status = !album.status.isEmpty && JSText.lowercase(album.status) != "official" ? album.status : ""
        let credit = !album.credit.isEmpty && !WebText.same(album.credit, song.credit) ? album.credit : ""
        let parts = [album.kind, status, credit, yearOf(album.date), other ? length(album.length) : "",
                     albumWords(holding(index, album, song, evidence), personal: personal)]
        return parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    // MARK: the album opened from a song

    /// A song's recordings as an album's address carries them (`songIds`): lowercase MusicBrainz ids, each once, at most
    /// `idsKept` - anything else dropped.
    public static func ids(_ parts: [String]) -> [String] {
        var ids: [String] = []
        for part in parts {
            let id = lower(part)
            if MBID.isOne(id) && !has(ids, id) { ids.append(id) }
            if ids.count >= idsKept { break }
        }
        return ids
    }

    /// The same, from the address's comma-separated words.
    public static func ids(_ text: String) -> [String] {
        ids(text.split(separator: ",", omittingEmptySubsequences: false).map(String.init))
    }

    /// The pressing an album opened from a song shows (`songPressing`) - nil: the album's usual one. The usual pressing
    /// when it has the song; else the most usual of those with one of its recordings, else of those with a track of its
    /// title.
    public static func pressing(_ releases: [PageRelease], _ ids: [String]) -> String? {
        guard let matches = matcher(releases, ids) else { return nil }
        guard let usual = Tracklist.representative(releases) ?? releases.first else { return nil }
        func has(_ release: PageRelease) -> Bool { tracks(release).contains(where: matches) }
        if has(usual) { return nil }
        let wanted = Set(ids.map { FoldKey(lower($0)) })
        let byRecording = releases.filter { tracks($0).contains { isRecording($0, wanted) } }
        let pool = byRecording.isEmpty ? releases.filter(has) : byRecording
        guard !pool.isEmpty else { return nil }
        return (Tracklist.representative(pool) ?? pool[0]).id
    }
}
