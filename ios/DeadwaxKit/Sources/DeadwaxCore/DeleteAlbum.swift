import Foundation

/// What Delete album says (Phase 8, slice 4 - notes/ios-specs/phase8-managing.md 3.6): the web's DeleteAlbumDialog -
/// lib/albumEdit.ts since 2.1.30 (`DELETE_TITLE`, `DELETE_CHECKING`, `DELETE_READ_FAILED`, `DELETE_FAILED`,
/// `deleteCounts`, `deleteOthers`, `DELETE_WARNING`, `DELETE_CONFIRM`, `DELETING`, `deletesAll`) and lib/myLibrary.ts's
/// `holdersText` - and the phone's own question before it goes. Held to the web's by EditPartsVectorTests over
/// Fixtures/edit/edit-parts-vectors.json.
public enum DeleteWords {
    /// `DELETE_TITLE`: the page's heading.
    public static let title = "Delete this album?"
    /// `DELETE_CHECKING`: while the folder is read.
    public static let checking = "Checking what's in there…"
    /// `DELETE_READ_FAILED`, `DELETE_FAILED`: the leads of what didn't work.
    public static let readFailed = "Couldn't read that folder."
    public static let failed = "Couldn't delete it."
    /// `DELETE_WARNING`, over the button.
    public static let warning = "This deletes the folder and everything in it, permanently. There is no undo."
    /// `DELETE_CONFIRM`, `DELETING`: the button, and while it runs.
    public static let confirm = "Delete permanently"
    public static let deleting = "Deleting…"

    /// The phone's own question once Delete permanently is tapped (an action sheet: Cancel the default).
    public static func question(_ album: String) -> String { "Delete \(album.isEmpty ? "this album" : album)?" }
    public static let noUndo = "There is no undo."
    public static let delete = "Delete"
    public static let cancel = "Cancel"
    /// The page's title in the sheet's bar.
    public static let page = "Delete album"
    /// `editStatus`'s line once the folder is gone - said to VoiceOver as the sheet closes.
    public static func deleted(_ path: String) -> String { "Deleted \(path)." }

    /// `deleteCounts`: what goes - "12 tracks · 300 MB".
    public static func counts(_ summary: DeletionSummary) -> String {
        let size = Sources.size(summary.totalBytes)
        return "\(summary.audioFiles) track\(summary.audioFiles == 1 ? "" : "s")" + (size.isEmpty ? "" : " · \(size)")
    }

    /// `deleteOthers`: the other files, named, because they might not exist anywhere else - "and 3 other files:" over
    /// their names, ", …" when there are more than the summary lists; nil with none.
    public static func others(_ summary: DeletionSummary) -> (lead: String, names: String)? {
        guard summary.otherFileCount > 0 else { return nil }
        let count = summary.otherFileCount
        return ("and \(count) other file\(count == 1 ? "" : "s"):",
                summary.otherFiles.joined(separator: ", ") + (count > summary.otherFiles.count ? ", …" : ""))
    }

    /// `holdersText`: who holds the album (logins on: `holders` - everyone else - and `yours`), nil with logins off.
    /// Unread (`holders_unknown`) is said as unread, never as "nobody".
    public static func holders(_ summary: DeletionSummary?) -> String? {
        guard let summary else { return nil }
        if summary.holdersUnknown {
            return "deadwax couldn't read who has it in their library - whoever does will find it was removed by an admin."
        }
        guard let holders = summary.holders else { return nil }
        let yours = summary.yours == true
        if holders.isEmpty {
            return yours ? "In your library: deleting it takes it out." : "Nobody has it in their library."
        }
        let others = listed(holders)
        if yours {
            return "In \(listed(["your library"] + holders.map { "\($0)'s" })): deleting it takes it out, and \(others) "
                + "will see it was removed by an admin."
        }
        return "In \(others)'s \(holders.count == 1 ? "library" : "libraries"): deleting it takes it out, and they'll see "
            + "it was removed by an admin."
    }

    /// myLibrary.ts `listed`: "A", "A and B", "A, B and C".
    static func listed(_ items: [String]) -> String {
        guard items.count >= 2 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
}

extension AlbumEdit {
    /// `deletesAll(folders, tracks, album)`: deleting the folder of `tracks` tracks leaves Navidrome's album with
    /// nothing, so the page goes back from it - it was the album's only folder, or, found by name among several, it
    /// holds as many songs as Navidrome lists for the album (same-named untagged folders can be albums of their own
    /// there; several of one release are one album).
    public static func deletesAll(_ folders: Folders?, tracks: Int, _ album: Subject?) -> Bool {
        guard let folders, folders.paths.count > 1 else { return true }
        guard folders.from == .name, let songs = album?.songCount else { return false }
        return tracks >= songs
    }
}

/// `GET /library/deletion_summary`'s answer (summarize_for_deletion, and with logins on who holds it): read live, so it
/// counts what the scan ignores - a rip log or a cue sheet might be the only copy.
public struct DeletionSummary: Decodable, Sendable, Equatable {
    public let audioFiles: Int
    public let totalBytes: Double
    /// The other files' names, at most twelve.
    public let otherFiles: [String]
    public let otherFileCount: Int
    /// Logins on: everyone else whose library holds it, in the order they got it - nil with logins off, or unread.
    public let holders: [String]?
    /// Logins on: whether the person asking holds it.
    public let yours: Bool?
    /// Logins on: deadwax couldn't read who holds it.
    public let holdersUnknown: Bool

    public init(audioFiles: Int, totalBytes: Double = 0, otherFiles: [String] = [], otherFileCount: Int = 0,
                holders: [String]? = nil, yours: Bool? = nil, holdersUnknown: Bool = false) {
        self.audioFiles = audioFiles
        self.totalBytes = totalBytes
        self.otherFiles = otherFiles
        self.otherFileCount = otherFileCount
        self.holders = holders
        self.yours = yours
        self.holdersUnknown = holdersUnknown
    }

    enum CodingKeys: String, CodingKey {
        case holders, yours
        case audioFiles = "audio_files"
        case totalBytes = "total_bytes"
        case otherFiles = "other_files"
        case otherFileCount = "other_file_count"
        case holdersUnknown = "holders_unknown"
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        audioFiles = fields.looseField(Int.self, .audioFiles) ?? 0
        totalBytes = fields.looseField(Double.self, .totalBytes) ?? 0
        otherFiles = fields.looseList(String.self, .otherFiles) ?? []
        otherFileCount = fields.looseField(Int.self, .otherFileCount) ?? 0
        holders = fields.looseList(String.self, .holders)
        yours = fields.looseField(Bool.self, .yours)
        holdersUnknown = fields.looseField(Bool.self, .holdersUnknown) ?? false
    }
}

/// What Delete permanently sends (DeleteRequest): the folder.
public struct DeleteAlbumBody: Encodable, Sendable, Equatable {
    public let albumPath: String

    public init(albumPath: String) { self.albumPath = albumPath }

    enum CodingKeys: String, CodingKey { case albumPath = "album_path" }
}

/// `POST /library/delete`'s answer (delete_album): it went.
public struct AlbumDeleted: Decodable, Sendable, Equatable {
    public let deleted: Bool

    public init(deleted: Bool) { self.deleted = deleted }

    enum CodingKeys: String, CodingKey { case deleted }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        deleted = fields.looseField(Bool.self, .deleted) ?? false
    }
}

/// Delete album's state (DeleteAlbumDialog's, Phase 8 slice 4): the summary read live for the folder shown - only the
/// newest read lands, a cancelled one changes nothing - Delete permanently on only with this folder's summary in hand
/// and nothing under way, and how the delete ended: gone, refused (said, nothing deleted), or no answer (or a 5xx) -
/// said as maybe finished until the folder's next read says whether it went (`settled`).
public struct DeleteFlow: Sendable, Equatable {
    /// The folder the summary is for.
    public private(set) var path: String?
    public private(set) var summary: DeletionSummary?
    public private(set) var reading = false
    /// The summary couldn't be read: said, with Look again.
    public private(set) var readFailure: String?
    public private(set) var deleting = false
    /// The delete was refused, or its answer never came and the folder is still there: said under the button.
    public private(set) var failure: String?
    /// The answer never came (or came as a 5xx): deadwax may have deleted it - the folder is read again.
    public private(set) var mayHaveFinished = false
    private var reads = 0

    public init() {}

    /// The page opened on `path`, or Look again: a ticket for the read. Another folder's summary and words go.
    public mutating func beginRead(_ path: String) -> Int {
        if self.path != path {
            summary = nil
            failure = nil
            mayHaveFinished = false
        }
        self.path = path
        reads += 1
        reading = true
        readFailure = nil
        return reads
    }

    /// The summary came: false (dropped) when a newer read was asked since.
    @discardableResult
    public mutating func read(_ ticket: Int, _ answer: DeletionSummary) -> Bool {
        guard ticket == reads else { return false }
        summary = answer
        reading = false
        return true
    }

    /// The read failed: no summary, so nothing can be deleted until one lands.
    public mutating func readFailed(_ ticket: Int, said: String) {
        guard ticket == reads else { return }
        summary = nil
        reading = false
        readFailure = said
    }

    /// The read was called off (the page left): nothing said.
    public mutating func readCancelled(_ ticket: Int) {
        guard ticket == reads else { return }
        reading = false
    }

    /// Delete permanently may be pressed for the folder at `path`: its summary in hand, nothing reading or deleting.
    public func canDelete(_ path: String) -> Bool {
        self.path == path && summary != nil && !reading && !deleting
    }

    /// Delete permanently confirmed: false when it can't start.
    public mutating func beginDelete(_ path: String) -> Bool {
        guard canDelete(path) else { return false }
        deleting = true
        failure = nil
        mayHaveFinished = false
        return true
    }

    /// How the delete ended (RetagFlow.outcome's rule). A refusal is said; no answer is said as maybe finished, until
    /// `settled` says whether the folder went. `said` is EditWords.writeFailure's - nil for no words of deadwax's.
    public mutating func deleteEnded(_ outcome: RetagFlow.Outcome, said: String?) {
        deleting = false
        switch outcome {
        case .applied:
            break
        case .refused:
            failure = said
        case .unanswered:
            failure = said
            mayHaveFinished = true
        }
    }

    /// Whether a delete that never answered went, by the library's next read: gone from a scan that read the library -
    /// nil when it couldn't (its `problem`: no albums listed says nothing of this one).
    public static func went(_ scan: ScanAnswer, path: String) -> Bool? {
        if let problem = scan.problem, !problem.isEmpty { return nil }
        return scan.album(at: path) == nil
    }

    /// The folder read again after a delete that never answered: `gone` - the scan no longer lists it - is a delete
    /// that went (nothing more said here - the sheet closes); still there, the delete didn't, and its summary is read again.
    public mutating func settled(gone: Bool) {
        mayHaveFinished = false
        if gone {
            failure = nil
        } else if failure == nil {
            failure = DeleteWords.failed
        }
    }
}
