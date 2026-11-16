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
    /// (Phase 8, slice 6) How bad its worst outstanding issue is - 0 for none (attach_issues' `worst_severity`): what
    /// Needs a look orders the queue by, after the new imports.
    public let severity: Int
    /// (slice 6) One folder of several holding a release's discs, by its discs ("Disc 2") - "" for any other folder
    /// (src/library.py `disc_label`): Needs a look's row says it before the edition.
    public let discLabel: String

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
        case severity
        case discLabel = "disc_label"
    }

    public init(path: String, artist: String = "", album: String = "", year: String = "", originalYear: String = "",
                edition: String = "", releaseMbid: String = "", art: String = "", artMtime: Double = 0,
                trackCount: Int = 0, discCount: Int = 0, formats: [String] = [], lyricsCount: Int = 0,
                discArt: [String] = [], issues: [String] = [], ignoredIssues: [String] = [], needsAttention: Bool = false,
                imported: Bool = false, reviewed: Bool = false, severity: Int = 0, discLabel: String = "") {
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
        self.severity = severity
        self.discLabel = discLabel
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
        severity = fields.looseField(Int.self, .severity) ?? 0
        discLabel = fields.looseField(String.self, .discLabel) ?? ""
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
    /// (Phase 8, slice 6) deadwax can keep what was marked fine (`review_tracking_enabled` - its job store opened):
    /// false, and Needs a look warns that an "It's fine as it is" will come back. True when the answer doesn't say, as
    /// the web's useLibrary reads it (`!== false`).
    public let reviewTracking: Bool
    /// (slice 6) How the albums' check against Navidrome stands (`navidrome_check`, 2.0.0-player.46) - nil from a server
    /// before it, or an answer of the wrong shape.
    public let navidromeCheck: NavidromeCheck?
    /// The answer is the saved scan, the disk not read (X-Scan-Stale) - never for an ask without `snapshot`.
    public var stale = false
    /// When the disk was last read, Unix seconds (X-Scanned-At) - nil when nobody knows.
    public var scannedAt: Double?

    enum CodingKeys: String, CodingKey {
        case albums, problem
        case issueTypes = "issue_types"
        case reviewTracking = "review_tracking_enabled"
        case navidromeCheck = "navidrome_check"
    }

    public init(albums: [ScanAlbum] = [], problem: String? = nil, issueTypes: [String: MetadataIssueType] = [:],
                stale: Bool = false, scannedAt: Double? = nil, reviewTracking: Bool = true,
                navidromeCheck: NavidromeCheck? = nil) {
        self.albums = albums
        self.problem = problem
        self.issueTypes = issueTypes
        self.stale = stale
        self.scannedAt = scannedAt
        self.reviewTracking = reviewTracking
        self.navidromeCheck = navidromeCheck
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        albums = fields.looseList(ScanAlbum.self, .albums) ?? []
        problem = fields.looseField(String.self, .problem)
        issueTypes = (fields.looseField([String: LooseIssueType].self, .issueTypes) ?? [:])
            .compactMapValues(\.value)
        reviewTracking = fields.looseField(Bool.self, .reviewTracking) ?? true
        navidromeCheck = fields.looseField(NavidromeCheck.self, .navidromeCheck)
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

/// How the albums' check against Navidrome stands (`navidrome_check`, the web's NavidromeCheck - 2.0.0-player.46):
/// `listed` (checked: an album Navidrome doesn't list carries `not_in_navidrome`), `scanning`, `checking` (Navidrome
/// hasn't answered yet), `unset` (not set up) or `failed` (`problem` says why). A state the phone doesn't know is kept
/// as it came - NeedsLook.navidromeNote says nothing of it, as the web's says nothing.
public struct NavidromeCheck: Decodable, Sendable, Equatable {
    public let state: String
    public let problem: String?

    enum CodingKeys: String, CodingKey { case state, problem }

    public init(state: String, problem: String? = nil) {
        self.state = state
        self.problem = problem
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        state = try fields.decode(String.self, forKey: .state)
        problem = fields.looseField(String.self, .problem)
    }
}

/// What is wrong with an album, and the queue of them (ui/src/lib/metadataQueue.ts): the editor's three since slice 1,
/// and Needs a look's two since slice 6 (`isNewImport`, `queueAlbums`).
public enum MetadataQueue {
    /// `isNewImport`: an album deadwax filed that nobody has looked at yet - what clears with a look (reviewed).
    public static func isNewImport(_ album: ScanAlbum) -> Bool {
        album.imported && !album.reviewed
    }

    /// `queueAlbums(albums, issue)`: the albums to work through, in the order worth working through them - anything
    /// with an outstanding issue and anything newly imported (narrowed to one kind of issue when `issue` names one, a
    /// clean new import then none of them); new imports first, worst first, then by artist and album as JavaScript's
    /// `localeCompare` orders them (WebCollation), the list's own order kept between equals (JS's sort is stable).
    public static func queueAlbums(_ albums: [ScanAlbum], _ issue: String? = nil) -> [ScanAlbum] {
        let waiting = albums.enumerated().filter { (_, album) in
            //? the issue facet narrows to one KIND of problem, so a clean new import isn't one of them
            if let issue, !issue.isEmpty {
                return album.needsAttention && outstanding(album).contains { WebText.same($0, issue) }
            }
            return album.needsAttention || isNewImport(album)
        }
        return waiting.sorted { (one, other) -> Bool in
            let (a, b) = (one.element, other.element)
            let freshness = (isNewImport(b) ? 1 : 0) - (isNewImport(a) ? 1 : 0)
            if freshness != 0 { return freshness < 0 }
            if a.severity != b.severity { return b.severity - a.severity < 0 }
            let artist = WebCollation.compare(a.artist, b.artist)
            if artist != 0 { return artist < 0 }
            let name = WebCollation.compare(a.album, b.album)
            if name != 0 { return name < 0 }
            return one.offset < other.offset
        }.map(\.element)
    }

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
