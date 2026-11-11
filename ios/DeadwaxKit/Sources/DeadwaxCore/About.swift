import Foundation

// Info > About on the phone (Phase 1): the song, its album and its artist, as the web's About draws them
// (ui/src/lib/aboutRows.ts aboutRows, with lib/format.ts, lib/discTitles.ts and lib/idBridge.ts's helpers) -
// from the queue's entry, the album answer it was played from, and what Info asks for as it opens: the song as
// Navidrome has it now (`GET /deadwax/navidrome/songs/{song_id}`, decoded as `SongDetails`) and the store's
// rows of its album (the id bridge's `present`). The rule for every line, as on the web: a field Navidrome
// didn't send is LEFT OUT, never guessed. Phase 1's artist card is the name and nothing else (D8): the web's
// note "The album is by …", its link, facts and count are not made here at all (the last three need routes the
// phone gets in Phase 4). Fixtures/levels/info-vectors.json holds every line to the TypeScript's own answers.

/// A song as Navidrome's answers carry it, for About: `GET /deadwax/navidrome/songs/{song_id}` (getSong passed
/// on as it is - `{}` when Navidrome sent none), and each song of the album answer. Every field optional, and
/// read leniently - a field of an unexpected type is left out, never a failed decode - since a line is only
/// drawn from what is there. Numbers are kept as Navidrome sent them: About uses one only when it is a whole
/// number above 0, as the web does.
public struct SongDetails: Decodable, Sendable, Equatable {
    public struct Credit: Decodable, Sendable, Equatable {
        public let role: String?
        public let name: String?

        public init(role: String?, name: String?) {
            self.role = role
            self.name = name
        }

        enum CodingKeys: String, CodingKey { case role, artist }
        enum ArtistKeys: String, CodingKey { case name }

        public init(from decoder: Decoder) throws {
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            role = keyed.aboutString(.role)
            name = (try? keyed.nestedContainer(keyedBy: ArtistKeys.self, forKey: .artist))?.aboutString(.name)
        }
    }

    public let id: String?
    public let artist: String?
    public let artistId: String?
    public let track: Double?
    public let discNumber: Double?
    public let duration: Double?
    public let suffix: String?
    /// left out by Navidrome until the song has been played
    public let playCount: Double?
    /// OpenSubsonic: who wrote it, as one line
    public let displayComposer: String?
    /// OpenSubsonic: everyone credited, by role
    public let contributors: [Credit]?

    public init(id: String? = nil, artist: String? = nil, artistId: String? = nil, track: Double? = nil, discNumber: Double? = nil,
                duration: Double? = nil, suffix: String? = nil, playCount: Double? = nil, displayComposer: String? = nil,
                contributors: [Credit]? = nil) {
        self.id = id
        self.artist = artist
        self.artistId = artistId
        self.track = track
        self.discNumber = discNumber
        self.duration = duration
        self.suffix = suffix
        self.playCount = playCount
        self.displayComposer = displayComposer
        self.contributors = contributors
    }

    enum CodingKeys: String, CodingKey {
        case id, artist, artistId, track, discNumber, duration, suffix, playCount, displayComposer, contributors
    }

    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        id = keyed.aboutString(.id)
        artist = keyed.aboutString(.artist)
        artistId = keyed.aboutString(.artistId)
        track = keyed.aboutNumber(.track)
        discNumber = keyed.aboutNumber(.discNumber)
        duration = keyed.aboutNumber(.duration)
        suffix = keyed.aboutString(.suffix)
        playCount = keyed.aboutNumber(.playCount)
        displayComposer = keyed.aboutString(.displayComposer)
        contributors = keyed.aboutList(.contributors)
    }
}

/// A disc's title, as Navidrome's album answer carries it (OpenSubsonic `discTitles`): `disc` a number (or a
/// number written as a string), `title` the title. Ones the rule can't use are dropped when it reads them.
///
/// About's own reading of the field, apart from the album page's `DiscTitle` (the routes' models), which reads
/// `disc` as an Int: here it is read as the web's discTitleMap reads it, JS's `Number(disc)` - " 2 ", "2.0",
/// "0x2" and `true` are discs to the web and so to About, which info-vectors.json holds to the web's answers.
public struct AboutDiscTitle: Decodable, Sendable, Equatable {
    /// JS's `Number(disc)`, or nil when it is none
    public let disc: Double?
    public let title: String?

    public init(disc: Double?, title: String?) {
        self.disc = disc
        self.title = title
    }

    enum CodingKeys: String, CodingKey { case disc, title }

    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        title = keyed.aboutString(.title)
        if let number = keyed.aboutNumber(.disc) {
            disc = number
        } else if let text = keyed.aboutString(.disc) {
            disc = AboutDiscTitle.number(text)
        } else if let flag = try? keyed.decodeIfPresent(Bool.self, forKey: .disc) {
            disc = flag ? 1 : 0
        } else {
            disc = nil
        }
    }

    /// JS's `Number(text)` for what a disc can be written as: trimmed, "" is 0, a decimal (or 0x hex) number
    /// its value - and nil for anything else (JS's NaN; its "Infinity" isn't a disc either, nor are its rarer
    /// 0b and 0o forms here).
    static func number(_ text: String) -> Double? {
        let trimmed = WebText.trim(text)
        if trimmed.isEmpty { return 0 }
        let lowered = trimmed.lowercased()
        guard !lowered.contains("n"), !lowered.contains("p"), let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }
}

/// The album answer a queue was played from (`GET /deadwax/navidrome/albums/{album_id}`, getAlbum's album as
/// it is), as About reads it - decoded from the same bytes, leniently, so the app can keep the answer and read
/// it for Info whatever else it decodes it as.
public struct AboutAlbum: Decodable, Sendable, Equatable {
    public struct Label: Decodable, Sendable, Equatable {
        public let name: String?

        public init(name: String?) {
            self.name = name
        }

        enum CodingKeys: String, CodingKey { case name }

        public init(from decoder: Decoder) throws {
            name = try decoder.container(keyedBy: CodingKeys.self).aboutString(.name)
        }
    }

    public let id: String?
    public let name: String?
    public let artist: String?
    public let year: Double?
    public let coverArt: String?
    public let songCount: Double?
    public let song: [SongDetails]?
    /// a playlist's stub of the album (the web's, 2.0.0-player.58): `song` holds only the playlist's songs of it
    public let partial: Bool?
    public let discTitles: [AboutDiscTitle]?
    public let artistId: String?
    /// OpenSubsonic: the labels the files name
    public let recordLabels: [Label]?

    public init(id: String? = nil, name: String? = nil, artist: String? = nil, year: Double? = nil, coverArt: String? = nil,
                songCount: Double? = nil, song: [SongDetails]? = nil, partial: Bool? = nil, discTitles: [AboutDiscTitle]? = nil,
                artistId: String? = nil, recordLabels: [Label]? = nil) {
        self.id = id
        self.name = name
        self.artist = artist
        self.year = year
        self.coverArt = coverArt
        self.songCount = songCount
        self.song = song
        self.partial = partial
        self.discTitles = discTitles
        self.artistId = artistId
        self.recordLabels = recordLabels
    }

    enum CodingKeys: String, CodingKey {
        case id, name, artist, year, coverArt, songCount, song, partial, discTitles, artistId, recordLabels
    }

    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        id = keyed.aboutString(.id)
        name = keyed.aboutString(.name)
        artist = keyed.aboutString(.artist)
        year = keyed.aboutNumber(.year)
        coverArt = keyed.aboutString(.coverArt)
        songCount = keyed.aboutNumber(.songCount)
        song = keyed.aboutList(.song)
        partial = try? keyed.decodeIfPresent(Bool.self, forKey: .partial)
        discTitles = keyed.aboutList(.discTitles)
        artistId = keyed.aboutString(.artistId)
        recordLabels = keyed.aboutList(.recordLabels)
    }
}

/// One of the store's folders of the album, as the id bridge answers it (`GET /deadwax/store/album`'s
/// `present`): what "This pressing: …" and the folder are made from.
public struct PressingRow: Decodable, Sendable, Equatable {
    public let path: String?
    public let edition: String?
    /// as the store keeps it, a string ("1975", "1975-09-12"); a number is read as JS's String() writes it
    public let year: String?
    public let formats: [String]?

    public init(path: String? = nil, edition: String? = nil, year: String? = nil, formats: [String]? = nil) {
        self.path = path
        self.edition = edition
        self.year = year
        self.formats = formats
    }

    enum CodingKeys: String, CodingKey { case path, edition, year, formats }

    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        path = keyed.aboutString(.path)
        edition = keyed.aboutString(.edition)
        year = keyed.aboutString(.year) ?? keyed.aboutNumber(.year).map(WebText.number)
        formats = try? keyed.decodeIfPresent([String].self, forKey: .formats)
    }
}

/// The queue entry About is about - what the web's QueueTrack gives it.
public struct AboutTrack: Sendable, Equatable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var albumId: String?
    public var coverArt: String?
    /// seconds; 0 when Navidrome didn't say
    public var duration: Double

    public init(id: String, title: String, artist: String, album: String, albumId: String?, coverArt: String?, duration: Double) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.albumId = albumId
        self.coverArt = coverArt
        self.duration = duration
    }

    /// A song as the web's toQueueTrack makes an entry of it: an absent title, artist or album empty.
    public init(song: Song) {
        self.init(id: song.id, title: song.title ?? "", artist: song.artist ?? "", album: song.album ?? "", albumId: song.albumId,
                  coverArt: song.coverArt, duration: song.duration ?? 0)
    }
}

/// What Info asks for as it opens: the song as Navidrome has it now, and the store's rows of its album - each
/// nil until, or unless, it answers.
public struct AboutDetails: Sendable, Equatable {
    public var song: SongDetails?
    public var present: [PressingRow]?

    public init(song: SongDetails? = nil, present: [PressingRow]? = nil) {
        self.song = song
        self.present = present
    }
}

/// Info > About's three cards.
public struct About: Codable, Sendable, Equatable {
    public struct SongCard: Codable, Sendable, Equatable {
        public let title: String
        public let artist: String
        /// "Track 4 of 10 · 7:05 · played 12 times", then "Disc 2 · Unreleased Tracks" - each only when known
        public let lines: [String]
        /// "Nick Mason, Roger Waters" - only when Navidrome names a writer
        public let writtenBy: String?
    }

    public struct AlbumCard: Codable, Sendable, Equatable {
        /// what "Go to album" opens; nil when the queue has no id for it
        public let id: String?
        public let title: String
        public let coverArt: String?
        /// "1973 · Harvest · FLAC · 10 songs" - "" when none of it is known
        public let line: String
        /// "This pressing: 20th Anniversary Reissue 180gram · 2014 · FLAC" - only when it adds to `line`
        public let pressing: String?
        /// its folder on the server (one per line for a set kept per disc) - only for whoever may see it
        public let folder: String?
    }

    /// The artist's card: the name, and nothing else in Phase 1 (D8).
    public struct ArtistCard: Codable, Sendable, Equatable {
        public let name: String
    }

    public let song: SongCard
    /// nil when the song names no album at all
    public let album: AlbumCard?
    /// nil when nobody named an artist
    public let artist: ArtistCard?
}

public enum AboutCard {
    static let dot = " · "

    /// What About shows for the song playing (aboutRows.ts aboutRows): `album` the answer its queue was played
    /// from, nil when that isn't in hand (the lines that need it are then left out); `folders` whether this
    /// person sees the album's folder (an admin - the web's seesFolders).
    public static func about(track: AboutTrack, album: AboutAlbum?, details: AboutDetails? = nil, folders: Bool = false) -> About {
        let songs = album?.song ?? []
        let song = songs.first { $0.id.map { WebText.same($0, track.id) } ?? false }
        //? a playlist's stub holds only the playlist's songs of the album: nothing of the album's is counted from it
        let all = album?.partial == true ? [] : songs
        //? the song as Navidrome has it now, else as it was when the album was played from
        let fresh = details?.song.flatMap { $0.id.map { WebText.same($0, track.id) } == true ? $0 : nil }

        let length = trackTime(song?.duration ?? track.duration)
        let played = playedLine(fresh != nil ? fresh?.playCount : song?.playCount)
        let first = [song.map { trackOf($0, all) } ?? "", length, played].filter { !$0.isEmpty }.joined(separator: dot)
        var lines = [first]
        if let song, let album, album.partial != true { lines.append(discLine(song, album)) }
        lines = lines.filter { !$0.isEmpty }
        let writers = writtenBy(fresh ?? song)

        let title = nonEmpty(album?.name) ?? track.album
        let count = !all.isEmpty ? all.count : (WebText.whole(album?.songCount) ?? 0)
        let albumYear = WebText.whole(album?.year).map(String.init) ?? ""
        let albumFormat = sharedFormat(all) ?? ""
        let albumLine = [
            albumYear,
            labelLine(album?.recordLabels),
            albumFormat,
            count > 0 ? "\(count) \(count == 1 ? "song" : "songs")" : "",
        ].filter { !$0.isEmpty }.joined(separator: dot)
        let present = details?.present ?? []
        let pressing = pressingAdds(present, year: albumYear, format: albumFormat) ? pressingLine(present) : nil
        let folder = folders ? folderLine(present) : nil

        let name = nonEmpty(song?.artist) ?? nonEmpty(track.artist) ?? nonEmpty(album?.artist) ?? ""

        return About(
            song: About.SongCard(title: track.title, artist: track.artist, lines: lines, writtenBy: writers.isEmpty ? nil : writers),
            album: title.isEmpty ? nil : About.AlbumCard(id: track.albumId ?? album?.id, title: title, coverArt: album?.coverArt ?? track.coverArt,
                                                         line: albumLine, pressing: pressing, folder: folder),
            artist: name.isEmpty ? nil : About.ArtistCard(name: name))
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// Who wrote a song, as Navidrome sends it: OpenSubsonic's one line, else its composers, each once.
    public static func writtenBy(_ song: SongDetails?) -> String {
        let line = WebText.trim(song?.displayComposer ?? "")
        if !line.isEmpty { return line }
        let names = (song?.contributors ?? [])
            .filter { WebText.same(($0.role ?? "").lowercased(), "composer") }
            .map { WebText.trim($0.name ?? "") }
            .filter { !$0.isEmpty }
        return WebText.unique(names).joined(separator: ", ")
    }

    /// "played 12 times", "played once" - "" for a song never played (Navidrome then sends no count).
    public static func playedLine(_ count: Double?) -> String {
        guard let plays = WebText.whole(count) else { return "" }
        return plays == 1 ? "played once" : "played \(plays) times"
    }

    /// The labels the files name, each once: "Harvest", "Go! Beat / London".
    public static func labelLine(_ labels: [AboutAlbum.Label]?) -> String {
        WebText.unique((labels ?? []).map { WebText.trim($0.name ?? "") }.filter { !$0.isEmpty }).joined(separator: " / ")
    }

    /// A track's running time, "4:05" - "" for none (format.ts trackTime: Math.round, then minutes and seconds).
    public static func trackTime(_ seconds: Double?) -> String {
        guard let seconds, seconds != 0, !seconds.isNaN else { return "" }
        let whole = WebText.round(seconds)
        let minutes = (whole / 60).rounded(.down)
        let rest = WebText.number(whole.truncatingRemainder(dividingBy: 60))
        return "\(WebText.number(minutes)):\(rest.count < 2 ? "0" + rest : rest)"
    }

    /// The one format every song is in - "FLAC" - or nil when they differ, one has none, or there are none.
    public static func sharedFormat(_ songs: [SongDetails]) -> String? {
        let formats = WebText.unique(songs.map { ($0.suffix ?? "").uppercased() })
        guard formats.count == 1, let only = formats.first, !only.isEmpty else { return nil }
        return only
    }

    /// A song's disc as a heading counts it: no number (or 0) is disc 1.
    static func discOf(_ song: SongDetails) -> Double {
        guard let disc = song.discNumber, disc != 0, !disc.isNaN else { return 1 }
        return disc
    }

    /// "Track 4 of 10": of the songs on its disc; a number past its disc's count (numbered straight through
    /// the set) against the whole album; past that, no count. "" with no track number.
    static func trackOf(_ song: SongDetails, _ songs: [SongDetails]) -> String {
        guard let number = WebText.whole(song.track) else { return "" }
        let onDisc = songs.filter { discOf($0) == discOf(song) }.count
        let of = number <= onDisc ? onDisc : number <= songs.count ? songs.count : 0
        return of > 0 ? "Track \(number) of \(of)" : "Track \(number)"
    }

    /// Each disc's title, by its number - blank titles and discs that aren't whole numbers above 0 left out, the
    /// first title of a disc kept (discTitles.ts discTitleMap).
    static func discTitleMap(_ titles: [AboutDiscTitle]?) -> [Double: String] {
        var map: [Double: String] = [:]
        for entry in titles ?? [] {
            let title = WebText.trim(entry.title ?? "")
            guard let disc = entry.disc, WebText.whole(disc) != nil, !title.isEmpty, map[disc] == nil else { continue }
            map[disc] = title
        }
        return map
    }

    /// For each song, the album page's heading above it, or nil: the first song of each disc, whenever the album
    /// shows headings at all - more than one disc, or a disc with a title (discTitles.ts discHeadings).
    static func discHeadings(_ songs: [SongDetails], _ titles: [AboutDiscTitle]?) -> [String?] {
        let byDisc = discTitleMap(titles)
        let discs = Set(songs.map(discOf))
        let show = discs.count > 1 || discs.contains { byDisc[$0] != nil }
        return songs.indices.map { index in
            let disc = discOf(songs[index])
            let first = index == 0 || discOf(songs[index - 1]) != disc
            guard show && first else { return nil }
            if let title = byDisc[disc] { return "Disc \(WebText.number(disc))\(dot)\(title)" }
            return "Disc \(WebText.number(disc))"
        }
    }

    /// The heading the album page draws over the song's disc, or "" where it draws none.
    static func discLine(_ song: SongDetails, _ album: AboutAlbum) -> String {
        let songs = album.song ?? []
        guard let first = songs.firstIndex(where: { discOf($0) == discOf(song) }) else { return "" }
        return discHeadings(songs, album.discTitles)[first] ?? ""
    }

    static func formatsOf(_ present: [PressingRow]) -> [String] {
        WebText.unique(present.flatMap { $0.formats ?? [] }).map { $0.uppercased() }
    }

    /// "This pressing: 20th Anniversary Reissue 180gram · 2014 · FLAC" - nil when the store holds none
    /// (idBridge.ts pressingLine).
    static func pressingLine(_ present: [PressingRow]) -> String? {
        guard let first = present.first else { return nil }
        let year = WebText.prefix(first.year ?? "", 4)
        let parts = [WebText.trim(first.edition ?? ""), WebText.fourDigits(year) ? year : "", formatsOf(present).joined(separator: "/")]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : "This pressing: \(parts.joined(separator: dot))"
    }

    /// Whether "This pressing: …" says anything the album's line doesn't: an edition, another year, another
    /// format (idBridge.ts pressingAdds).
    static func pressingAdds(_ present: [PressingRow], year albumYear: String, format albumFormat: String) -> Bool {
        guard let first = present.first else { return false }
        if !WebText.trim(first.edition ?? "").isEmpty { return true }
        let year = WebText.prefix(first.year ?? "", 4)
        if WebText.fourDigits(year) && !WebText.same(year, albumYear) { return true }
        let formats = formatsOf(present).joined(separator: "/")
        return !formats.isEmpty && !WebText.same(formats, albumFormat.uppercased())
    }

    /// Where it is on disk: the folder (each folder of a set kept per disc, a line each), or nil.
    static func folderLine(_ present: [PressingRow]) -> String? {
        let paths = present.compactMap(\.path).filter { !$0.isEmpty }
        return paths.isEmpty ? nil : paths.joined(separator: "\n")
    }
}

extension KeyedDecodingContainer {
    /// A string, or nil when the key is missing, null or not a string.
    func aboutString(_ key: Key) -> String? {
        (try? decodeIfPresent(String.self, forKey: key)) ?? nil
    }

    /// A number, or nil when the key is missing, null or not a number.
    func aboutNumber(_ key: Key) -> Double? {
        (try? decodeIfPresent(Double.self, forKey: key)) ?? nil
    }

    /// A list of what can be read of it: nil when the key is missing or isn't a list, and an element that can't
    /// be read left out.
    func aboutList<T: Decodable>(_ key: Key) -> [T]? {
        guard let items = (try? decodeIfPresent([AboutLenient<T>].self, forKey: key)) ?? nil else { return nil }
        return items.compactMap(\.value)
    }
}

/// An element read if it can be, nil if not - so one odd entry doesn't lose the list.
struct AboutLenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
