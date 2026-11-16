import Foundation

// The library's scan as the album editor reads it (Phase 8, slice 1 - notes/ios-specs/phase8-managing.md 3.1):
// `GET /deadwax/library/albums?tracks=false` (server 2.1.28), the web's LibraryResponse less every album's tracks -
// each album's album-level fields (ui/src/api/types.ts LibraryAlbum), what is wrong with it (the queue's decoration,
// src/metadata_health.py attach_issues), the issues' words (`issue_types`) and why the library can't be read at all
// (`problem`, LIBRARY_PATH unset - not an error). The scan's volatile parts ride as headers (X-Scanned-At, X-Scan-Stale -
// `_SCAN_HEADERS` in src/routes/library.py), so an unchanged library is a 304 to the ETag kept. Read leniently, as every
// answer of deadwax's is: a field of the wrong shape is its default, an album with no path is left out. Kept in memory
// by the page that asked, never on disk (phase8-managing.md 2).

/// One album folder in the library's scan: album-level only - the phone never asks for its tracks.
public struct ScanAlbum: Decodable, Sendable, Equatable, Hashable, Identifiable {
    /// Relative to LIBRARY_PATH - what every editor names the album by.
    public let path: String
    public let artist: String
    public let album: String
    /// This pressing's year, as the files' `date` says it ("" for none).
    public let year: String
    /// The album's first year, the files' `originaldate` ("" for none).
    public let originalYear: String
    /// The edition worked out from the folder and its tags ("Standard" for none in particular).
    public let edition: String
    /// The release the files name ("" for none).
    public let releaseMbid: String
    /// "file" (a cover beside the tracks), "embedded" (only inside them) or "" (none).
    public let art: String
    /// When the cover file last changed - what keeps a cover drawn current (`albumArtUrl`'s `v`).
    public let artMtime: Double
    public let trackCount: Int
    public let discCount: Int
    public let formats: [String]
    public let lyricsCount: Int
    public let discArt: [String]
    /// Every issue found, worst first - ignored ones too (`ignoredIssues` says which).
    public let issues: [String]
    public let ignoredIssues: [String]
    public let needsAttention: Bool
    public let imported: Bool
    public let reviewed: Bool

    public var id: String { path }

    enum CodingKeys: String, CodingKey {
        case path, artist, album, year, edition, art, formats, issues, imported, reviewed
        case originalYear = "original_year"
        case releaseMbid = "release_mbid"
        case artMtime = "art_mtime"
        case trackCount = "track_count"
        case discCount = "disc_count"
        case lyricsCount = "lyrics_count"
        case discArt = "disc_art"
        case ignoredIssues = "ignored_issues"
        case needsAttention = "needs_attention"
    }

    public init(path: String, artist: String = "", album: String = "", year: String = "", originalYear: String = "",
                edition: String = "", releaseMbid: String = "", art: String = "", artMtime: Double = 0,
                trackCount: Int = 0, discCount: Int = 0, formats: [String] = [], lyricsCount: Int = 0,
                discArt: [String] = [], issues: [String] = [], ignoredIssues: [String] = [], needsAttention: Bool = false,
                imported: Bool = false, reviewed: Bool = false) {
        self.path = path
        self.artist = artist
        self.album = album
        self.year = year
        self.originalYear = originalYear
        self.edition = edition
        self.releaseMbid = releaseMbid
        self.art = art
        self.artMtime = artMtime
        self.trackCount = trackCount
        self.discCount = discCount
        self.formats = formats
        self.lyricsCount = lyricsCount
        self.discArt = discArt
        self.issues = issues
        self.ignoredIssues = ignoredIssues
        self.needsAttention = needsAttention
        self.imported = imported
        self.reviewed = reviewed
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        path = try fields.decode(String.self, forKey: .path)
        artist = fields.looseField(String.self, .artist) ?? ""
        album = fields.looseField(String.self, .album) ?? ""
        year = fields.looseField(String.self, .year) ?? ""
        originalYear = fields.looseField(String.self, .originalYear) ?? ""
        edition = fields.looseField(String.self, .edition) ?? ""
        releaseMbid = fields.looseField(String.self, .releaseMbid) ?? ""
        art = fields.looseField(String.self, .art) ?? ""
        artMtime = fields.looseField(Double.self, .artMtime) ?? 0
        trackCount = fields.looseField(Int.self, .trackCount) ?? 0
        discCount = fields.looseField(Int.self, .discCount) ?? 0
        formats = fields.looseList(String.self, .formats) ?? []
        lyricsCount = fields.looseField(Int.self, .lyricsCount) ?? 0
        discArt = fields.looseList(String.self, .discArt) ?? []
        issues = fields.looseList(String.self, .issues) ?? []
        ignoredIssues = fields.looseList(String.self, .ignoredIssues) ?? []
        needsAttention = fields.looseField(Bool.self, .needsAttention) ?? false
        imported = fields.looseField(Bool.self, .imported) ?? false
        reviewed = fields.looseField(Bool.self, .reviewed) ?? false
    }
}

/// One kind of metadata problem as the server words it (src/metadata_health.py ISSUE_TYPES, the web's
/// MetadataIssueType): its short label, the sentence that says what fixes it, and how bad it is.
public struct MetadataIssueType: Decodable, Sendable, Equatable, Hashable {
    public let label: String
    public let hint: String
    public let severity: Int

    enum CodingKeys: String, CodingKey { case label, hint, severity }

    public init(label: String, hint: String = "", severity: Int = 0) {
        self.label = label
        self.hint = hint
        self.severity = severity
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        label = try fields.decode(String.self, forKey: .label)
        hint = fields.looseField(String.self, .hint) ?? ""
        severity = fields.looseField(Int.self, .severity) ?? 0
    }
}

/// `GET /deadwax/library/albums?tracks=false`: the scan's albums, the issues' words, and why the library can't be read
/// (`problem`) - with the scan's own headers laid on by `DeadwaxClient.libraryScan`.
public struct ScanAnswer: Decodable, Sendable, Equatable {
    public let albums: [ScanAlbum]
    /// LIBRARY_PATH unset or missing: the library can't be read at all - said as it is, never as an error.
    public let problem: String?
    public let issueTypes: [String: MetadataIssueType]
    /// The answer is the saved scan, the disk not read (X-Scan-Stale) - never for an ask without `snapshot`.
    public var stale = false
    /// When the disk was last read, Unix seconds (X-Scanned-At) - nil when nobody knows.
    public var scannedAt: Double?

    enum CodingKeys: String, CodingKey {
        case albums, problem
        case issueTypes = "issue_types"
    }

    public init(albums: [ScanAlbum] = [], problem: String? = nil, issueTypes: [String: MetadataIssueType] = [:],
                stale: Bool = false, scannedAt: Double? = nil) {
        self.albums = albums
        self.problem = problem
        self.issueTypes = issueTypes
        self.stale = stale
        self.scannedAt = scannedAt
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        albums = fields.looseList(ScanAlbum.self, .albums) ?? []
        problem = fields.looseField(String.self, .problem)
        issueTypes = (fields.looseField([String: LooseIssueType].self, .issueTypes) ?? [:])
            .compactMapValues(\.value)
    }

    /// The album at `path` in this scan, if it lists it.
    public func album(at path: String) -> ScanAlbum? {
        albums.first { WebText.same($0.path, path) }
    }

    /// `_SCAN_HEADERS`' two the editor reads: stale ("1") and when the disk was read.
    public func with(headers response: HTTPResponse) -> ScanAnswer {
        var answer = self
        answer.stale = response.header("X-Scan-Stale") == "1"
        answer.scannedAt = response.header("X-Scanned-At").flatMap(Double.init)
        return answer
    }
}

/// An issue type read, or left out.
private struct LooseIssueType: Decodable {
    let value: MetadataIssueType?

    init(from decoder: any Decoder) throws {
        value = try? MetadataIssueType(from: decoder)
    }
}

/// What the editor reads of what is wrong with an album (ui/src/lib/metadataQueue.ts - its three the editor uses; Needs
/// a look's own rules come with its slice).
public enum MetadataQueue {
    /// `outstandingIssues`: the issues not marked fine - what puts the album in Needs a look - worst first.
    public static func outstanding(_ album: ScanAlbum) -> [String] {
        if album.ignoredIssues.isEmpty { return album.issues }
        return album.issues.filter { code in !album.ignoredIssues.contains { WebText.same($0, code) } }
    }

    /// `markedFineIssues`: what was marked fine that the album still has - the stored list can name one since fixed.
    public static func markedFine(_ album: ScanAlbum) -> [String] {
        album.ignoredIssues.filter { code in album.issues.contains { WebText.same($0, code) } }
    }

    /// `issueLabel`: the server's label for a code, else the code itself.
    public static func label(_ code: String, _ types: [String: MetadataIssueType]) -> String {
        types[code]?.label ?? code
    }

    /// The code's hint, "" for none (the web draws `issueTypes[code]?.hint`, nothing for none).
    public static func hint(_ code: String, _ types: [String: MetadataIssueType]) -> String {
        types[code]?.hint ?? ""
    }
}
