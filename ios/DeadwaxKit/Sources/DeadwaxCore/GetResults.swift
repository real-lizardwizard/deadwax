import Foundation

/// What an album's own Get cover, Get CD art and Get lyrics say (Phase 8, slice 3 - notes/ios-specs/phase8-managing.md
/// 3.5): lib/getResults.ts (`GETTING`, `GET_FAILED`, `getProblem`, `lyricsResult`), lib/lyrics.ts (`describeLyrics`,
/// `lyricsOnDisk`), the three buttons as components/LibraryParts.tsx draws them - when each is offered, its words, what
/// a 404 means - and the Artwork and Lyrics pages' lines, which lib/albumEdit.ts holds since 2.1.30 (`coverNote`,
/// `coverPointer`, `discArtPointer`, `lyricsLine`, `allLyricsNote`, ...). Held to the web's by EditPartsVectorTests over
/// Fixtures/edit/edit-parts-vectors.json.
public enum GetResults {
    public enum Kind: String, Sendable, CaseIterable, Hashable {
        case cover, disc, lyrics
    }

    /// What each button says while it works (`GETTING`).
    public static func getting(_ kind: Kind) -> String {
        switch kind {
        case .cover: "Getting the cover…"
        case .disc: "Getting CD art…"
        case .lyrics: "Getting lyrics…"
        }
    }

    /// What a failed Get says when it has nothing better to say (`GET_FAILED`).
    public static func failed(_ kind: Kind) -> String {
        switch kind {
        case .cover: "Couldn't get the cover."
        case .disc: "Couldn't get CD art."
        case .lyrics: "Couldn't get lyrics."
        }
    }

    /// `getProblem`: a Get that didn't work, as the line under its button - the route's words as a sentence (a 404's
    /// too), else ErrorWords' sentence with `failed` for its lead, the error's own words in brackets for whoever runs
    /// deadwax. The button is the page's Try again (`retry`).
    public static func problem(_ error: any Error, _ kind: Kind, admin: Bool) -> String {
        let words = ErrorWords.of(error, admin: admin, failed: failed(kind), retry: true)
        let line = ErrorWords.said(text: ErrorWords.asSentence(words.text), advice: words.advice)
        if let detail = words.detail, !detail.isEmpty { return "\(line) (\(detail))" }
        return line
    }

    /// `lyricsOnDisk`: the tracks with lyrics on disk after a fetch - the ones it wrote and the ones already there.
    public static func lyricsOnDisk(_ summary: LyricsSummary) -> Int {
        summary.written + summary.replaced + summary.kept
    }

    /// `describeLyrics`: what a fetch did, in the order to read it - what was saved, what LRCLIB doesn't have, what
    /// went wrong and is worth another go.
    public static func describeLyrics(_ summary: LyricsSummary) -> String {
        let saved = summary.written + summary.replaced
        var parts: [String] = []
        if saved != 0 {
            let synced = summary.synced != 0
                ? " (\(summary.synced == saved ? "all" : String(summary.synced)) synced)" : ""
            parts.append("Saved lyrics for \(saved) track\(saved == 1 ? "" : "s")\(synced)")
        } else {
            parts.append("No new lyrics")
        }
        if summary.kept != 0 { parts.append("\(summary.kept) already had them") }
        if summary.missing != 0 { parts.append("\(summary.missing) not on LRCLIB") }
        if summary.instrumental != 0 { parts.append("\(summary.instrumental) instrumental") }
        if summary.untagged != 0 { parts.append("\(summary.untagged) need a title and artist tag first") }
        if summary.failed != 0 { parts.append("\(summary.failed) failed - try again") }
        return parts.joined(separator: ", ")
    }

    /// `lyricsResult`: what a Get lyrics that answered did, as the line under its button.
    public static func lyricsResult(_ summary: LyricsSummary) -> String {
        ErrorWords.asSentence(describeLyrics(summary))
    }

    // MARK: when each button is offered (LibraryParts.tsx)

    /// Get cover: only for a folder with no cover that names a release - nothing to look one up by otherwise.
    public static func offersCover(_ album: ScanAlbum) -> Bool {
        album.art.isEmpty && !album.releaseMbid.isEmpty
    }

    /// The folder has CD art deadwax saved (a `disc*` picture beside the tracks), which a Get never replaces.
    public static func hasOwnDiscArt(_ album: ScanAlbum) -> Bool {
        album.discArt.contains { $0.lowercased().hasPrefix("disc") }
    }

    /// Get CD art: a release to look it up by, and none of deadwax's own yet.
    public static func offersDiscArt(_ album: ScanAlbum) -> Bool {
        !album.releaseMbid.isEmpty && !hasOwnDiscArt(album)
    }

    /// Get lyrics: while any track has none - and, once it has run, for as long as the album is open, saying what it
    /// came to.
    public static func offersLyrics(_ album: ScanAlbum, ran: Bool) -> Bool {
        ran || album.lyricsCount < album.trackCount
    }

    /// A button's words, by how its last run for this album went (nil: never run).
    public static func label(_ kind: Kind, _ run: GetRun?, trackCount: Int) -> String {
        switch run?.state {
        case .working?:
            return getting(kind)
        case .none?:
            return kind == .lyrics ? "Try again" : "Look again"
        case .failed?, .unanswered?:
            return "Try again"
        case .done?:
            if kind == .lyrics, let summary = run?.summary { return "Lyrics · \(lyricsOnDisk(summary)) of \(trackCount)" }
            return idle(kind)
        case nil:
            return idle(kind)
        }
    }

    static func idle(_ kind: Kind) -> String {
        switch kind {
        case .cover: "Get cover"
        case .disc: "Get CD art"
        case .lyrics: "Get lyrics"
        }
    }

    // MARK: the Artwork and Lyrics pages (lib/albumEdit.ts, 2.1.30)

    /// `coverNote`: where the folder's cover is, if it has one.
    public static func coverNote(_ art: String) -> String {
        art == "file" ? "A cover is saved beside the tracks."
            : art == "embedded" ? "The cover is inside the files, with none beside them."
            : "No cover is saved with the album."
    }

    /// `COVER_MISSING`.
    public static let coverMissing = "No cover on disk, and none on the Cover Art Archive for this release"

    /// `coverPointer`, as the web says it: with no release, that one comes first; with a cover, where replacing it is.
    public static func webCoverPointer(_ album: ScanAlbum) -> String? {
        if album.releaseMbid.isEmpty { return "To get a cover, first match the album to a release in the Release tab." }
        if !album.art.isEmpty { return "To replace it, compare it with the release's in the Release tab (Compare full size…)." }
        return nil
    }

    /// `DISC_ART_BESIDE`, `NO_DISC_ART`.
    public static let discArtBeside = "Beside the tracks - what players show for a song with a disc number:"
    public static let noDiscArt = "No picture of the disc beside the tracks."

    /// `discArtPointer`, as the web says it: with no release, that one comes first; with deadwax's own CD art, that it
    /// never replaces it.
    public static func webDiscArtPointer(_ album: ScanAlbum) -> String? {
        if album.releaseMbid.isEmpty { return "To get CD art, first match the album to a release in the Release tab." }
        if hasOwnDiscArt(album) { return "deadwax never replaces CD art it saved." }
        return nil
    }

    /// The pointers on the phone: the web's, its Release *tab* the phone's Release *page*, and its Compare full size…
    /// the Compare covers… the phone's Release page has.
    public static func onThePhone(_ words: String) -> String {
        words.replacingOccurrences(of: "in the Release tab (Compare full size…)", with: "on the Release page (Compare covers…)")
            .replacingOccurrences(of: "in the Release tab", with: "on the Release page")
    }

    public static func coverPointer(_ album: ScanAlbum) -> String? { webCoverPointer(album).map(onThePhone) }
    public static func discArtPointer(_ album: ScanAlbum) -> String? { webDiscArtPointer(album).map(onThePhone) }

    /// `lyricsLine`: "8 of 12 tracks have lyrics saved beside them, as a .lrc."
    public static func lyricsLine(_ lyricsCount: Int, _ trackCount: Int) -> String {
        "\(lyricsCount) of \(trackCount) track\(trackCount == 1 ? " has" : "s have") lyrics saved beside"
            + "\(trackCount == 1 ? " it" : " them"), as a .lrc."
    }

    /// `allLyricsNote`: under Get lyrics once every track has them.
    public static func allLyricsNote(_ album: ScanAlbum) -> String? {
        album.lyricsCount >= album.trackCount ? "Every track has lyrics." : nil
    }

    /// `RETIME_POINTER` - Server settings is still the web app's (Phase 8's slice 8), so it is said, not linked.
    public static let retimePointer = "To shift when synced lyrics appear, or re-time the ones already saved, see Lyrics in Server settings (Library)."

    /// The tabs' headings, and what VoiceOver says of a picture to open.
    public static let artwork = "Artwork"
    public static let lyrics = "Lyrics"
    public static let cover = "Cover"
    public static let discArt = "CD art"
    public static let seeCover = "See the cover full size"
    public static func seeDiscArt(_ name: String) -> String { "\(name) - see it full size" }
}

/// One Get's last run for one folder (LibraryParts.tsx's `run`): keyed to the folder it ran for, so another folder's
/// page never shows it. `none` is a 404 - the Archive has nothing for the release, a fact, so the button looks again;
/// `failed` a refusal (nothing written); `unanswered` no answer or a 5xx - it may have written, so the folder is read
/// again (the phone's, as Release's apply: RetagFlow.outcome).
public struct GetRun: Sendable, Equatable {
    public enum State: Sendable, Equatable { case working, none, failed, unanswered, done }

    public let kind: GetResults.Kind
    public let path: String
    public private(set) var state: State
    /// The line under the button: the route's words, or the phone's.
    public private(set) var said: String?
    /// Get lyrics' answer.
    public private(set) var summary: LyricsSummary?

    public init(kind: GetResults.Kind, path: String) {
        self.kind = kind
        self.path = path
        self.state = .working
    }

    /// The Get answered.
    public mutating func done(_ summary: LyricsSummary? = nil) {
        state = .done
        self.summary = summary
        said = summary.map(GetResults.lyricsResult)
    }

    /// The Get didn't work: what it means, said.
    public mutating func failed(_ error: any Error, admin: Bool) {
        said = GetResults.problem(error, kind, admin: admin)
        if kind != .lyrics, case .answered(let answer)? = error as? APIFailure, answer.status == 404 {
            state = .none
        } else {
            state = RetagFlow.outcome(of: error) == .refused ? .failed : .unanswered
        }
    }

    /// The folder may have changed: read it again (an answer, or no answer at all - a 404 and a refusal wrote nothing).
    public var wrote: Bool { state == .done || state == .unanswered }
}

/// `POST /library/lyrics/fetch`'s answer (fetch_album_lyrics' summary): how many tracks came to what.
public struct LyricsSummary: Decodable, Sendable, Equatable {
    public let written: Int
    public let replaced: Int
    public let kept: Int
    public let instrumental: Int
    public let missing: Int
    public let failed: Int
    public let untagged: Int
    /// How many of the written or replaced ones carry timings.
    public let synced: Int

    public init(written: Int = 0, replaced: Int = 0, kept: Int = 0, instrumental: Int = 0, missing: Int = 0,
                failed: Int = 0, untagged: Int = 0, synced: Int = 0) {
        self.written = written
        self.replaced = replaced
        self.kept = kept
        self.instrumental = instrumental
        self.missing = missing
        self.failed = failed
        self.untagged = untagged
        self.synced = synced
    }

    enum CodingKeys: String, CodingKey { case written, replaced, kept, instrumental, missing, failed, untagged, synced }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        written = fields.looseField(Int.self, .written) ?? 0
        replaced = fields.looseField(Int.self, .replaced) ?? 0
        kept = fields.looseField(Int.self, .kept) ?? 0
        instrumental = fields.looseField(Int.self, .instrumental) ?? 0
        missing = fields.looseField(Int.self, .missing) ?? 0
        failed = fields.looseField(Int.self, .failed) ?? 0
        untagged = fields.looseField(Int.self, .untagged) ?? 0
        synced = fields.looseField(Int.self, .synced) ?? 0
    }
}

/// What Get lyrics and Get CD art are sent (LyricsRequest, DiscArtRequest): the folder - a lyrics fetch never
/// replacing a .lrc already there, never re-timing.
public struct LyricsFetchBody: Encodable, Sendable, Equatable {
    public let albumPath: String
    public let replace: Bool
    public let retime: Bool

    public init(albumPath: String) {
        self.albumPath = albumPath
        self.replace = false
        self.retime = false
    }

    enum CodingKeys: String, CodingKey {
        case replace, retime
        case albumPath = "album_path"
    }
}

public struct DiscArtFetchBody: Encodable, Sendable, Equatable {
    public let albumPath: String

    public init(albumPath: String) { self.albumPath = albumPath }

    enum CodingKeys: String, CodingKey { case albumPath = "album_path" }
}

/// `POST /library/disc_art/fetch`'s answer: the pictures written, and where they came from.
public struct DiscArtFetched: Decodable, Sendable, Equatable {
    public let written: [String]
    public let source: String

    public init(written: [String], source: String) {
        self.written = written
        self.source = source
    }

    enum CodingKeys: String, CodingKey { case written, source }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        written = fields.looseList(String.self, .written) ?? []
        source = fields.looseField(String.self, .source) ?? ""
    }
}
