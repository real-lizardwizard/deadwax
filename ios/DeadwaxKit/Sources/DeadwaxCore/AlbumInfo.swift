import Foundation

// Album info (James, 2026-11-15: "I'd like somewhere I can see all the album metadata like quality, media type,
// etc."): an album as a whole, in a listener's words, grouped - opened from an album page's ••• and from Info's album
// card. The phone's own; the web has no such sheet (its album page's Properties, lib/albumProperties.ts, is the
// nearest, and its year, size, release link and "Added" are said here too).
//
// Where each line comes from (notes/ios.md "Album info"), every one of them a route the app could already call, so
// the server is unchanged:
//
//  - the album's songs as Navidrome answered them (`Album`, getAlbum through `GET /deadwax/navidrome/albums/{id}`) -
//    the quality (suffix, bitDepth, samplingRate, bitRate, channelCount), the size and length, the songs and discs,
//    with the album's `discTitles`; drawn at once from the album in hand, offline too;
//  - getAlbum's OpenSubsonic fields beyond those (`AlbumExtras`, read from the same answer): releaseTypes,
//    releaseDate, originalReleaseDate, version, genres, isCompilation, recordLabels - as Navidrome's
//    server/subsonic/helpers.go buildOSAlbumID3 sets them;
//  - the id bridge (`GET /deadwax/store/album?navidrome_id=`, a user's route): the release group, the store's folders
//    of the album (an admin's "On the server"), its edition, and when deadwax first saw it;
//  - the files' own tags, read now (`GET /deadwax/library/tracks?album=<folder>`, the track viewer's route, a user's):
//    what only the tags hold - Picard's MEDIA, CATALOGNUMBER, BARCODE, RELEASECOUNTRY, RELEASESTATUS - by the
//    server's names for them (`tags`) where it reads them, else by each container's own name (`raw`), as Picard's tag
//    map writes them (picard-docs appendices/tag_mapping).
//
// A line with nothing to say is left out, never "Unknown"; a section with no lines is left out.

// MARK: - what is read

/// What getAlbum says of an album beyond what `Album` reads: OpenSubsonic's fields, as Navidrome's buildOSAlbumID3
/// sets them. Read leniently from the same answer - a field of an unexpected type is left out - since a line is only
/// drawn from what is there.
public struct AlbumExtras: Decodable, Sendable, Equatable {
    /// A date as OpenSubsonic writes one (`ItemDate`): its parts, each left out when not known.
    public struct Day: Decodable, Sendable, Equatable {
        public let year: Int?
        public let month: Int?
        public let day: Int?

        public init(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
            self.year = year
            self.month = month
            self.day = day
        }

        enum CodingKeys: String, CodingKey { case year, month, day }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            year = fields.looseField(Int.self, .year)
            month = fields.looseField(Int.self, .month)
            day = fields.looseField(Int.self, .day)
        }
    }

    /// A genre or a label: OpenSubsonic's `{name}`.
    public struct Named: Decodable, Sendable, Equatable {
        public let name: String?

        public init(name: String?) { self.name = name }

        enum CodingKeys: String, CodingKey { case name }

        public init(from decoder: any Decoder) throws {
            name = try decoder.container(keyedBy: CodingKeys.self).looseField(String.self, .name)
        }
    }

    /// MusicBrainz's types as the files name them: "album", "live", "compilation".
    public let releaseTypes: [String]?
    /// This pressing's date.
    public let releaseDate: Day?
    /// The album's first release.
    public let originalReleaseDate: Day?
    /// The files' album version ("Deluxe Edition"), when they name one.
    public let version: String?
    public let genres: [Named]?
    public let isCompilation: Bool?
    public let recordLabels: [Named]?

    public init(releaseTypes: [String]? = nil, releaseDate: Day? = nil, originalReleaseDate: Day? = nil, version: String? = nil,
                genres: [Named]? = nil, isCompilation: Bool? = nil, recordLabels: [Named]? = nil) {
        self.releaseTypes = releaseTypes
        self.releaseDate = releaseDate
        self.originalReleaseDate = originalReleaseDate
        self.version = version
        self.genres = genres
        self.isCompilation = isCompilation
        self.recordLabels = recordLabels
    }

    enum CodingKeys: String, CodingKey {
        case releaseTypes, releaseDate, originalReleaseDate, version, genres, isCompilation, recordLabels
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        releaseTypes = fields.looseList(String.self, .releaseTypes)
        releaseDate = fields.looseField(Day.self, .releaseDate)
        originalReleaseDate = fields.looseField(Day.self, .originalReleaseDate)
        version = fields.looseField(String.self, .version)
        genres = fields.looseList(Named.self, .genres)
        isCompilation = fields.looseField(Bool.self, .isCompilation)
        recordLabels = fields.looseList(Named.self, .recordLabels)
    }
}

/// `GET /deadwax/library/tracks?album=<folder>`: every audio file of one of the store's folders, read from the disk as
/// it asks (src/library.py read_track_details). Only what Album info reads of each is declared.
public struct AlbumFiles: Decodable, Sendable, Equatable {
    public let files: [AlbumFile]

    public init(files: [AlbumFile]) { self.files = files }

    enum CodingKeys: String, CodingKey { case files }

    public init(from decoder: any Decoder) throws {
        files = try decoder.container(keyedBy: CodingKeys.self).looseList(AlbumFile.self, .files) ?? []
    }
}

/// One file as the track viewer's route reads it: its disc, its tags by the server's names for them (mutagen's easy
/// names, every value of a tag joined by "; "), and every tag under its container's own name (`raw`, `[name, text]`
/// pairs - a FLAC's lower-cased, an MP3's ID3 frame ids, an M4A's atoms).
public struct AlbumFile: Decodable, Sendable, Equatable {
    public let disc: Int?
    public let tags: [String: String]?
    public let raw: [[String]]?

    public init(disc: Int? = nil, tags: [String: String]? = nil, raw: [[String]]? = nil) {
        self.disc = disc
        self.tags = tags
        self.raw = raw
    }

    enum CodingKeys: String, CodingKey { case disc, tags, raw }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        disc = fields.looseField(Int.self, .disc)
        tags = fields.looseField([String: String].self, .tags)
        raw = fields.looseList([String].self, .raw)
    }

    /// Every value the file holds for `tag`: the server's named tag first, else any of the container names Picard
    /// writes it under - each value once, in the file's order.
    public func values(_ tag: AlbumTag) -> [String] {
        for key in tag.named {
            let found = AlbumInfo.split(tags?[key] ?? "")
            if !found.isEmpty { return found }
        }
        let names = Set(tag.raw)
        for pair in raw ?? [] where pair.count >= 2 && names.contains(pair[0].lowercased()) {
            let found = AlbumInfo.split(pair[1])
            if !found.isEmpty { return found }
        }
        return []
    }
}

/// A tag Album info reads from the files, with the names it may be under: the server's (`named`, src/library.py
/// DETAIL_TAGS) and each container's as Picard writes it (`raw`, lower-cased: Vorbis comments, ID3, MP4 freeform
/// atoms, ASF, APEv2).
public enum AlbumTag: CaseIterable, Sendable {
    case media, catalogueNumber, barcode, country, status, type, label, date, originalDate, genre, releaseGroup

    public var named: [String] {
        switch self {
        case .media: return ["media"]
        case .catalogueNumber: return ["catalognumber"]
        case .barcode: return ["barcode"]
        case .country: return ["releasecountry"]
        // not among the server's named tags: read raw
        case .status, .type: return []
        case .label: return ["label", "organization"]
        case .date: return ["date"]
        case .originalDate: return ["originaldate"]
        case .genre: return ["genre"]
        case .releaseGroup: return ["musicbrainz_releasegroupid"]
        }
    }

    public var raw: [String] {
        switch self {
        case .media: return ["media", "tmed", "----:com.apple.itunes:media", "wm/media"]
        case .catalogueNumber:
            return ["catalognumber", "txxx:catalognumber", "----:com.apple.itunes:catalognumber", "wm/catalogno"]
        case .barcode: return ["barcode", "txxx:barcode", "----:com.apple.itunes:barcode", "wm/barcode"]
        case .country:
            return ["releasecountry", "txxx:musicbrainz album release country",
                    "----:com.apple.itunes:musicbrainz album release country", "musicbrainz/album release country"]
        case .status:
            return ["releasestatus", "musicbrainz_albumstatus", "txxx:musicbrainz album status",
                    "----:com.apple.itunes:musicbrainz album status", "musicbrainz/album status"]
        case .type:
            return ["releasetype", "musicbrainz_albumtype", "txxx:musicbrainz album type",
                    "----:com.apple.itunes:musicbrainz album type", "musicbrainz/album type"]
        case .label: return ["label", "organization", "publisher", "tpub", "----:com.apple.itunes:label", "wm/publisher"]
        case .date: return []
        case .originalDate: return ["originaldate", "tdor", "tory"]
        case .genre: return []
        case .releaseGroup:
            return ["musicbrainz_releasegroupid", "txxx:musicbrainz release group id",
                    "----:com.apple.itunes:musicbrainz release group id"]
        }
    }
}

// MARK: - what is drawn

/// One line of Album info: its label, its words, more lines under them (a mix, a disc's title), and what it does - its
/// words in the monospaced face with a Copy button (an id, a path, a barcode), or a link opening beside the app.
public struct AlbumInfoRow: Sendable, Equatable, Identifiable {
    public enum Style: Sendable, Equatable {
        case plain
        /// an id, a path or a number read in columns: monospaced, selectable, with Copy
        case copyable
        /// a link out: opens in Safari, beside the app
        case link
    }

    public let label: String
    public let value: String
    public var lines: [String]
    public var style: Style
    /// What Copy puts on the clipboard (a copyable row's).
    public var copy: String?
    /// Where a link row goes.
    public var link: URL?

    public init(label: String, value: String, lines: [String] = [], style: Style = .plain, copy: String? = nil,
                link: URL? = nil) {
        self.label = label
        self.value = value
        self.lines = lines
        self.style = style
        self.copy = copy
        self.link = link
    }

    public var id: String { label }
}

/// A group of Album info's lines under its heading.
public struct AlbumInfoSection: Sendable, Equatable, Identifiable {
    public let title: String
    public let rows: [AlbumInfoRow]

    public init(title: String, rows: [AlbumInfoRow]) {
        self.title = title
        self.rows = rows
    }

    public var id: String { title }
}

/// Album info's words.
public enum AlbumInfoWords {
    /// The sheet's title, and the ••• item and Info's row that open it.
    public static let title = "Album info"
    public static let symbol = "info.circle"
    public static let done = InfoWords.done

    public static let qualityTitle = "Quality"
    public static let albumTitle = "The album"
    public static let phoneTitle = "On this phone"
    public static let releaseTitle = "The release"
    public static let musicBrainzTitle = "MusicBrainz"
    public static let serverTitle = InfoWords.serverTitle

    /// While deadwax is asked for the rest (the files, the bridge, getAlbum's other fields).
    public static let reading = "Reading the album's files…"
    /// deadwax out of reach: what is drawn is what the phone has.
    public static let offline = "The rest shows once deadwax is back."
    /// The files' read failed (ErrorWords' `failed`).
    public static let filesFailed = "The album's files couldn't be read just now."
    /// The files' folder answered 404 (ErrorWords' `gone`).
    public static let filesGone = "The album's folder isn't where deadwax last saw it - it may have been moved."

    public static let copy = "Copy"
    public static let copied = "Copied"
    public static let copySymbol = "doc.on.doc"
    public static let copiedSymbol = "checkmark"
    /// A Copy button's name to VoiceOver: "Copy release".
    public static func copyName(_ label: String) -> String { "Copy \(label.lowercased())" }
    /// iOS refused to open a link out (Safari turned off in Screen Time, no browser to take it).
    public static let notOpened = "Couldn't open it - Safari may be turned off in Screen Time."
    /// VoiceOver's hint on a link row.
    public static let opensInSafari = ManagingWords.opensInSafari
    public static let outSymbol = ManagingWords.outSymbol

    /// How long the server's sections wait for every answer before drawing what has come (the files are read as they
    /// are asked for - a box set on a sleeping disk takes a while); later answers then land as they come.
    public static let settleSeconds = 3.0
}

/// Album info's rules: each section's lines from what is in hand.
public enum AlbumInfo {
    static let dot = DiscHeadings.dot

    // MARK: Quality

    /// Formats nothing has a bit depth in, whatever a tag reader says: their depth is never drawn.
    static let lossy: Set<String> = ["mp3", "aac", "ogg", "oga", "opus", "wma", "mpc", "mp2"]

    /// One kind of file the album is in: its format, and for a lossless one its depth and rate.
    struct Kind: Hashable {
        let format: String
        let bits: Int
        let rate: Int
    }

    static func kind(_ song: Song) -> Kind {
        let suffix = WebText.trim(song.suffix ?? "").lowercased()
        let format = suffix.isEmpty ? LevelWords.kindOf(FileFacts(suffix: nil, contentType: song.contentType)) : suffix.uppercased()
        let bits = song.bitDepth ?? 0
        guard bits > 0, !lossy.contains(suffix) else { return Kind(format: format, bits: 0, rate: 0) }
        return Kind(format: format, bits: bits, rate: max(song.samplingRate ?? 0, 0))
    }

    /// Quality: "FLAC · 24-bit / 96 kHz · all 10 songs" (each kind of file a line when they differ, the commonest
    /// first, "8 of 10 songs"), the bitrate and the channels.
    public static func quality(_ songs: [Song]) -> [AlbumInfoRow] {
        var rows: [AlbumInfoRow] = []
        let kinds = groups(songs, by: kind).filter { !$0.key.format.isEmpty }
        if !kinds.isEmpty {
            let lines = kinds.map { group in
                [kindWords(group.key, songs: group.songs), countWords(group.songs.count, of: songs.count)]
                    .filter { !$0.isEmpty }.joined(separator: dot)
            }
            rows.append(AlbumInfoRow(label: "Format", value: lines[0], lines: Array(lines.dropFirst())))
        }
        if let bitrate = bitrateWords(songs) {
            rows.append(AlbumInfoRow(label: "Bitrate", value: bitrate))
        }
        let channels = groups(songs.filter { ($0.channelCount ?? 0) > 0 }, by: { $0.channelCount ?? 0 })
        if channels.count == 1, let only = channels.first {
            rows.append(AlbumInfoRow(label: "Channels", value: channelWords(only.key)))
        } else if channels.count > 1 {
            let lines = channels.map { "\(channelWords($0.key))\(dot)\(countWords($0.songs.count, of: songs.count))" }
            rows.append(AlbumInfoRow(label: "Channels", value: lines[0], lines: Array(lines.dropFirst())))
        }
        return rows
    }

    /// What one kind of file says: "FLAC · 24-bit / 96 kHz", "FLAC · 16-bit", "MP3 · 320 kbps", "MP3 · 245 kbps on average".
    static func kindWords(_ kind: Kind, songs: [Song]) -> String {
        if kind.bits > 0 {
            let depth = kind.rate > 0 ? "\(kind.bits)-bit / \(RateWords.kHz(Double(kind.rate)))" : "\(kind.bits)-bit"
            return "\(kind.format)\(dot)\(depth)"
        }
        guard let rate = bitrateWords(songs) else { return kind.format }
        return "\(kind.format)\(dot)\(rate)"
    }

    /// "all 10 songs", "8 of 10 songs" - nothing for an album of one song.
    static func countWords(_ count: Int, of total: Int) -> String {
        if total <= 1 { return "" }
        return count >= total ? "all \(DownloadWords.songs(total))" : "\(count) of \(DownloadWords.songs(total))"
    }

    /// The songs' bitrate: "320 kbps" when every song says the same, "1,411 kbps on average" otherwise - Navidrome's
    /// bitrates weighed by each song's length (never the files' sizes over their lengths: a cover in every file would
    /// count as sound). Nil when nothing says.
    static func bitrateWords(_ songs: [Song]) -> String? {
        let rates = songs.compactMap(\.bitRate).filter { $0 > 0 }
        if rates.count == songs.count, let first = rates.first, rates.allSatisfy({ $0 == first }) {
            return "\(grouped(first)) kbps"
        }
        let weighed = songs.filter { ($0.bitRate ?? 0) > 0 && ($0.duration ?? 0) > 0 }
        guard !weighed.isEmpty else {
            guard !rates.isEmpty else { return nil }
            return "\(grouped(Int((Double(rates.reduce(0, +)) / Double(rates.count)).rounded()))) kbps on average"
        }
        let seconds = weighed.reduce(0.0) { $0 + ($1.duration ?? 0) }
        let sum = weighed.reduce(0.0) { $0 + Double($1.bitRate ?? 0) * ($1.duration ?? 0) }
        return "\(grouped(Int((sum / seconds).rounded()))) kbps on average"
    }

    /// 1 "Mono", 2 "Stereo", 6 "5.1 surround", 8 "7.1 surround", else "4 channels".
    static func channelWords(_ count: Int) -> String {
        switch count {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1 surround"
        case 8: return "7.1 surround"
        default: return "\(count) channels"
        }
    }

    /// The songs grouped by `key`, the largest group first, ties in the order first met.
    static func groups<Key: Hashable>(_ songs: [Song], by key: (Song) -> Key) -> [(key: Key, songs: [Song])] {
        var order: [Key] = []
        var found: [Key: [Song]] = [:]
        for song in songs {
            let each = key(song)
            if found[each] == nil { order.append(each) }
            found[each, default: []].append(song)
        }
        return order.enumerated()
            .sorted { a, b in
                let left = found[a.element]?.count ?? 0
                let right = found[b.element]?.count ?? 0
                return left != right ? left > right : a.offset < b.offset
            }
            .map { ($0.element, found[$0.element] ?? []) }
    }

    /// A whole number with its thousands marked: "1,411".
    static func grouped(_ number: Int) -> String {
        let digits = String(abs(number))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return number < 0 ? "-" + out : out
    }

    // MARK: The album

    /// The album: its songs, its discs (each disc's title and songs, when there is more than one or one has a title),
    /// its length and its size.
    public static func theAlbum(_ album: Album) -> [AlbumInfoRow] {
        let songs = album.song ?? []
        var rows: [AlbumInfoRow] = []
        let count = songs.isEmpty ? (album.songCount ?? 0) : songs.count
        if count > 0 { rows.append(AlbumInfoRow(label: "Songs", value: String(count))) }

        let titles = DiscHeadings.titleMap(album.discTitles)
        let discs = Array(Set(songs.map(DiscHeadings.discOf))).sorted()
        if discs.count > 1 {
            let lines = discs.map { disc -> String in
                let on = songs.filter { DiscHeadings.discOf($0) == disc }.count
                return "\(DiscHeadings.heading(disc, titles))\(dot)\(DownloadWords.songs(on))"
            }
            rows.append(AlbumInfoRow(label: "Discs", value: String(discs.count), lines: lines))
        } else if let disc = discs.first, let title = titles[disc] {
            rows.append(AlbumInfoRow(label: "Disc title", value: title))
        }

        let total = songs.isEmpty ? (album.duration ?? 0) : AlbumPageLines.total(songs)
        let length = Format.formatDuration(total)
        if !length.isEmpty { rows.append(AlbumInfoRow(label: "Length", value: length)) }

        if !songs.isEmpty, songs.allSatisfy({ ($0.size ?? 0) > 0 }) {
            rows.append(AlbumInfoRow(label: "Size", value: Bytes.words(songs.reduce(Int64(0)) { $0 + ($1.size ?? 0) })))
        }
        return rows
    }

    // MARK: On this phone

    /// What this phone holds of the album: "All 10 songs · 412 MB", "3 of 12 songs · 92 MB", "Not downloaded" - and
    /// what is under way (the album page's line: "Downloading - 4 of 12", "Waiting for Wi-Fi", "2 songs didn't
    /// download") under it.
    public static func onPhone(_ download: AlbumDownload, here: Int, of total: Int, bytes: Int64) -> AlbumInfoRow {
        let moving: String? = {
            switch download {
            case .downloading, .waiting, .failed: return DownloadWords.albumLine(download)
            case .none, .partial, .downloaded: return nil
            }
        }()
        guard here > 0 else {
            return AlbumInfoRow(label: "Downloaded", value: moving ?? "Not downloaded")
        }
        let songs = here >= total ? "All \(DownloadWords.songs(here))" : "\(here) of \(DownloadWords.songs(total))"
        return AlbumInfoRow(label: "Downloaded", value: "\(songs)\(dot)\(Bytes.words(bytes))", lines: moving.map { [$0] } ?? [])
    }

    // MARK: The release

    /// The release: media, label, catalogue number, barcode, country, its dates, type, status, edition, genres and when
    /// the collection got it - each from whatever says it (getAlbum's fields first, then the files' tags, then the
    /// bridge), and left out when nothing does. `countryName` names a two-letter country code ("GB" -> "United
    /// Kingdom"); `timeZone` is the reader's, for when it was added.
    public static func release(album: Album, extras: AlbumExtras?, store: StoreAlbum?, files: [AlbumFile]?,
                               countryName: (String) -> String? = { _ in nil },
                               timeZone: TimeZone = .current) -> [AlbumInfoRow] {
        let files = files ?? []
        let first = store?.present.first
        var rows: [AlbumInfoRow] = []

        if let media = media(files) { rows.append(AlbumInfoRow(label: "Media", value: media)) }

        let labels = names(extras?.recordLabels?.map(\.name) ?? album.recordLabels?.map(\.name) ?? [])
        let label = labels.isEmpty ? values(files, .label) : labels
        if !label.isEmpty { rows.append(AlbumInfoRow(label: label.count > 1 ? "Labels" : "Label", value: label.joined(separator: " / "))) }

        let catalogue = values(files, .catalogueNumber)
        if !catalogue.isEmpty {
            rows.append(AlbumInfoRow(label: "Catalogue number", value: catalogue.joined(separator: " / "), style: .copyable,
                                     copy: catalogue.joined(separator: " / ")))
        }
        let barcode = values(files, .barcode)
        if !barcode.isEmpty {
            rows.append(AlbumInfoRow(label: "Barcode", value: barcode.joined(separator: " / "), style: .copyable,
                                     copy: barcode.joined(separator: " / ")))
        }
        let countries = values(files, .country).map { country($0, name: countryName) }
        if !countries.isEmpty { rows.append(AlbumInfoRow(label: "Country", value: countries.joined(separator: " / "))) }

        let released = extras?.releaseDate.flatMap(dateWords)
            ?? values(files, .date).first.flatMap(dateWords)
            ?? album.year.flatMap { $0 > 0 ? String($0) : nil }
        if let released { rows.append(AlbumInfoRow(label: "Released", value: released)) }
        let original = extras?.originalReleaseDate.flatMap(dateWords)
            ?? values(files, .originalDate).first.flatMap(dateWords)
            ?? first?.originalYear.flatMap(dateWords)
        if let original, original != released {
            rows.append(AlbumInfoRow(label: "First released", value: original))
        }

        let types = typeWords(extras?.releaseTypes ?? [], compilation: extras?.isCompilation == true)
            ?? typeWords(values(files, .type), compilation: false)
        if let types { rows.append(AlbumInfoRow(label: "Type", value: types)) }
        let status = values(files, .status).map(capitalised)
        if !status.isEmpty { rows.append(AlbumInfoRow(label: "Status", value: status.joined(separator: " / "))) }

        let edition = nonEmpty(first?.edition) ?? nonEmpty(extras?.version)
        if let edition { rows.append(AlbumInfoRow(label: "Edition", value: edition)) }

        var genres = names(extras?.genres?.map(\.name) ?? [])
        if genres.isEmpty, let genre = nonEmpty(album.genre) { genres = [genre] }
        if genres.isEmpty { genres = values(files, .genre) }
        if !genres.isEmpty { rows.append(AlbumInfoRow(label: genres.count > 1 ? "Genres" : "Genre", value: genres.joined(separator: ", "))) }

        if let added = addedWords(store?.present ?? [], timeZone: timeZone) {
            rows.append(AlbumInfoRow(label: "Added", value: added))
        }
        return rows
    }

    /// Every value the files hold for `tag`, each once (whatever its case), in the order first met.
    public static func values(_ files: [AlbumFile], _ tag: AlbumTag) -> [String] {
        uniqueFolded(files.flatMap { $0.values(tag) })
    }

    /// What the album is on, from each disc's MEDIA tag, as MusicBrainz writes it: "CD", "2×CD", "CD + DVD-Video",
    /// `12" Vinyl` - each disc's the medium most of its files name (a file with no disc is disc 1); nil when none says.
    public static func media(_ files: [AlbumFile]) -> String? {
        var byDisc: [Int: [String]] = [:]
        for file in files {
            guard let medium = file.values(.media).first else { continue }
            byDisc[max(file.disc ?? 1, 1), default: []].append(medium)
        }
        var order: [String] = []
        var counts: [String: (words: String, count: Int)] = [:]
        for disc in byDisc.keys.sorted() {
            guard let medium = commonest(byDisc[disc] ?? []) else { continue }
            let folded = medium.lowercased()
            if counts[folded] == nil {
                order.append(folded)
                counts[folded] = (medium, 0)
            }
            counts[folded]?.count += 1
        }
        guard !order.isEmpty else { return nil }
        return order.compactMap { counts[$0] }
            .map { $0.count > 1 ? "\($0.count)\u{00D7}\($0.words)" : $0.words }
            .joined(separator: " + ")
    }

    /// A country as MusicBrainz codes it, in words: its two special areas, else `name`'s for a two-letter code, else the
    /// code as it is.
    public static func country(_ code: String, name: (String) -> String?) -> String {
        let upper = code.uppercased()
        if upper == "XW" { return "Worldwide" }
        if upper == "XE" { return "Europe" }
        if upper.count == 2, upper.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }),
           let named = name(upper).flatMap(nonEmpty) {
            return named
        }
        return code
    }

    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
                         "November", "December"]

    /// "1 March 1973", "March 1973", "1973" - nil without a year.
    public static func dateWords(year: Int?, month: Int?, day: Int?) -> String? {
        guard let year, year > 0 else { return nil }
        guard let month, (1...12).contains(month) else { return String(year) }
        guard let day, (1...31).contains(day) else { return "\(months[month - 1]) \(year)" }
        return "\(day) \(months[month - 1]) \(year)"
    }

    static func dateWords(_ day: AlbumExtras.Day) -> String? {
        dateWords(year: day.year, month: day.month, day: day.day)
    }

    /// A tag's date - "1973", "1973-03", "1973-03-01" (and a time after it) - in words; nil for anything else.
    public static func dateWords(_ text: String) -> String? {
        let parts = WebText.trim(text).prefix(10).split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let head = parts.first, head.count == 4, let year = Int(head) else { return nil }
        let month = parts.count > 1 && parts[1].count == 2 ? Int(parts[1]) : nil
        let day = month != nil && parts.count > 2 && parts[2].count == 2 ? Int(parts[2]) : nil
        return dateWords(year: year, month: month, day: day)
    }

    /// MusicBrainz's types in words: "Album · Live", "EP", with "Compilation" when Navidrome says it is one.
    static func typeWords(_ types: [String], compilation: Bool) -> String? {
        var words = uniqueFolded(types.flatMap { $0.split(whereSeparator: { $0 == "," || $0 == ";" }).map(String.init) }
            .map(WebText.trim).filter { !$0.isEmpty })
            .map { $0.lowercased() == "ep" ? "EP" : capitalised($0) }
        if compilation && !words.contains(where: { $0.lowercased() == "compilation" }) { words.append("Compilation") }
        return words.isEmpty ? nil : words.joined(separator: dot)
    }

    /// When the collection got the album - the earliest of its folders - and, when deadwax filed any of them, so:
    /// "14 October 2026, downloaded by deadwax". Nil when no folder says.
    static func addedWords(_ present: [StoreRow], timeZone: TimeZone) -> String? {
        let seen = present.compactMap(\.firstSeen).compactMap { text -> (String, Date)? in
            guard let when = parseISO(text) else { return nil }
            return (text, when)
        }
        guard let earliest = seen.min(by: { $0.1 < $1.1 }) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: earliest.1)
        guard let date = dateWords(year: parts.year, month: parts.month, day: parts.day) else { return nil }
        return present.contains { $0.imported == true } ? "\(date), downloaded by deadwax" : date
    }

    static func parseISO(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    // MARK: MusicBrainz

    /// The release and release group's ids, to copy, and their pages on musicbrainz.org.
    public static func musicBrainz(album: Album, store: StoreAlbum?, files: [AlbumFile]?) -> [AlbumInfoRow] {
        let release = nonEmpty(store?.releaseMbid) ?? nonEmpty(album.musicBrainzId)
        let group = nonEmpty(store?.releaseGroupMbid) ?? values(files ?? [], .releaseGroup).first
        var rows: [AlbumInfoRow] = []
        if let release {
            rows.append(AlbumInfoRow(label: "Release", value: release, style: .copyable, copy: release))
        }
        if let group {
            rows.append(AlbumInfoRow(label: "Release group", value: group, style: .copyable, copy: group))
        }
        if let release, let url = page("release", release) {
            rows.append(AlbumInfoRow(label: "This pressing on MusicBrainz", value: "", style: .link, link: url))
        }
        if let group, let url = page("release-group", group) {
            rows.append(AlbumInfoRow(label: "Every pressing on MusicBrainz", value: "", style: .link, link: url))
        }
        return rows
    }

    /// A MusicBrainz id's page - nil for anything that isn't one (it would open someone else's page, or none).
    static func page(_ kind: String, _ id: String) -> URL? {
        let hex = Set("0123456789abcdef")
        let groups = id.lowercased().split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12], groups.allSatisfy({ $0.allSatisfy(hex.contains) }) else { return nil }
        return URL(string: "https://musicbrainz.org/\(kind)/\(id.lowercased())")
    }

    // MARK: On the server

    /// The album's folder on the server (each of a set kept one folder per disc), for whoever may see it.
    public static func server(store: StoreAlbum?, folders: Bool) -> [AlbumInfoRow] {
        guard folders, let present = store?.present,
              let folder = AboutCard.folderLine(present.map { PressingRow(path: $0.path) }) else { return [] }
        return [AlbumInfoRow(label: present.count > 1 ? "Folders" : InfoWords.folder, value: folder, style: .copyable, copy: folder)]
    }

    // MARK: the sections

    /// What is drawn at once, from the album in hand and this phone: Quality, The album, On this phone.
    public static func local(album: Album, onPhone: AlbumInfoRow?) -> [AlbumInfoSection] {
        let songs = album.song ?? []
        return [
            AlbumInfoSection(title: AlbumInfoWords.qualityTitle, rows: quality(songs)),
            AlbumInfoSection(title: AlbumInfoWords.albumTitle, rows: theAlbum(album)),
            AlbumInfoSection(title: AlbumInfoWords.phoneTitle, rows: onPhone.map { [$0] } ?? []),
        ].filter { !$0.rows.isEmpty }
    }

    /// What deadwax's answers add, drawn once they have come (or the wait is over): The release, MusicBrainz and, for
    /// whoever may see it, On the server - each from what is in hand, so the album's own answer still gives what it
    /// can when the rest isn't there.
    public static func fromServer(album: Album, extras: AlbumExtras?, store: StoreAlbum?, files: [AlbumFile]?,
                                  folders: Bool, countryName: (String) -> String? = { _ in nil },
                                  timeZone: TimeZone = .current) -> [AlbumInfoSection] {
        [
            AlbumInfoSection(title: AlbumInfoWords.releaseTitle,
                             rows: release(album: album, extras: extras, store: store, files: files, countryName: countryName,
                                           timeZone: timeZone)),
            AlbumInfoSection(title: AlbumInfoWords.musicBrainzTitle, rows: musicBrainz(album: album, store: store, files: files)),
            AlbumInfoSection(title: AlbumInfoWords.serverTitle, rows: server(store: store, folders: folders)),
        ].filter { !$0.rows.isEmpty }
    }

    /// Which of the store's folders are read for their tags: the bridge's live ones, at most `foldersRead` (a set kept
    /// one folder per disc is one album; a dozen copies of one release is not this sheet's to read).
    public static func foldersToRead(_ store: StoreAlbum?) -> [String] {
        Array(WebText.unique((store?.present ?? []).map(\.path).filter { !$0.isEmpty }).prefix(foldersRead))
    }

    public static let foldersRead = 8

    // MARK: words

    /// A tag's value split into its values (the server joins several with "; "), each trimmed, empties dropped.
    static func split(_ text: String) -> [String] {
        text.components(separatedBy: ";").map(WebText.trim).filter { !$0.isEmpty }
    }

    /// Names, trimmed, empties dropped, each once whatever its case.
    static func names(_ names: [String?]) -> [String] {
        uniqueFolded(names.map { WebText.trim($0 ?? "") }.filter { !$0.isEmpty })
    }

    static func uniqueFolded(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    /// The value most of them are (whatever its case), ties to the first met.
    static func commonest(_ values: [String]) -> String? {
        var order: [String] = []
        var counts: [String: (words: String, count: Int)] = [:]
        for value in values {
            let folded = value.lowercased()
            if counts[folded] == nil {
                order.append(folded)
                counts[folded] = (value, 0)
            }
            counts[folded]?.count += 1
        }
        var best: (words: String, count: Int)?
        for key in order {
            guard let each = counts[key] else { continue }
            if each.count > (best?.count ?? 0) { best = each }
        }
        return best?.words
    }

    /// "Official", "Pseudo-release": the first letter a capital, the rest as MusicBrainz writes them (lower case).
    static func capitalised(_ word: String) -> String {
        let lowered = word.lowercased()
        guard let first = lowered.first else { return word }
        return first.uppercased() + lowered.dropFirst()
    }

    static func nonEmpty(_ text: String?) -> String? {
        let trimmed = WebText.trim(text ?? "")
        return trimmed.isEmpty ? nil : trimmed
    }
}
