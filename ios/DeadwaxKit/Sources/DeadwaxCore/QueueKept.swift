import Foundation

/// The queue this phone last saved or took, kept in the person's download store - its `queue_pending` row
/// (notes/ios-specs/phase2-downloads.md 7.5, 7.6). Two uses:
///
/// - **An app opened with deadwax out of reach** puts it back, paused, as resume puts back deadwax's - so an
///   Airplane-Mode launch doesn't start empty (ResumeController, when the open's ask isn't answered).
/// - **While `unsent`**, it is a save deadwax hasn't answered (the network gone, the app closed before the answer):
///   sent at the next open or return only once deadwax has been asked what it holds, and only when no other device
///   or app saved since - resume.md Open question 4, a position save's 409 rule. A sent save clears `unsent`; the
///   queue stays, as the one an offline launch puts back.
///
/// Per person: it lives in their store, so it is never put back or sent under someone else's sign-in.
public struct QueueKept: Sendable, Equatable {
    /// The queue as GET /queue would answer it had deadwax kept this phone's save of it: the window a full save sends,
    /// its songs, and this phone's own record of them - so `resumed()` puts it back exactly (Up Next's account, the
    /// levels, the second), and says nothing (it is this phone's own).
    public var answer: QueueAnswer
    /// The rev this phone had last saved or taken when it was kept - nil for none. A record deadwax holds from another
    /// device with a higher one was saved since.
    public var rev: Int?
    /// What GET /queue answered of the queue this phone last knew deadwax to hold (resume's signature of an answer): an
    /// answer the same is nothing new.
    public var seen: String?
    /// A save deadwax hasn't answered.
    public var unsent: Bool

    public init(answer: QueueAnswer, rev: Int?, seen: String?, unsent: Bool) {
        self.answer = answer
        self.rev = rev
        self.seen = seen
        self.unsent = unsent
    }

    /// The queue in the player, `position` seconds into its song, kept as this phone's own: the window a full save
    /// sends (`toSave` - pass `saving` when it is in hand), its songs as the engine has them (`Song(track:)`), with
    /// Navidrome's size where `size` knows it - the stream cache's whole-copy check reads it, offline after a relaunch.
    public init(queue: UpNextQueue, position: Double, saving: Saving? = nil, device: String, label: String, rev: Int?,
                idsRev: Int?, shared: Bool, seen: String?, unsent: Bool, size: (String) -> Int64? = { _ in nil }) {
        let made = saving ?? toSave(queue, position: position)
        let start = min(max(made.start, 0), queue.tracks.count)
        let end = min(start + made.ids.count, queue.tracks.count)
        let songs = queue.tracks[start..<end].map { Song(track: $0, size: size($0.id)) }
        let at = Resume.sent(position)
        let record = KeptQueue(rev: rev ?? 0, ids_rev: idsRev ?? 0, ids: made.ids, index: made.index, position: at,
                               snapshot: made.snapshot, device: device, label: label)
        self.init(answer: QueueAnswer(tracks: songs, index: made.index, position: at, changed_by: Resume.deadwaxClient,
                                      shared: shared, kept: record),
                  rev: rev, seen: seen, unsent: unsent)
    }

    // MARK: queue_pending's row

    /// The row's `kind`: whether deadwax has it.
    public static let unsentKind = "unsent"
    public static let sentKind = "sent"

    /// What the row's body holds: everything but `unsent`, which is the row's kind.
    private struct Body: Codable {
        var answer: QueueAnswer
        var rev: Int?
        var seen: String?
    }

    /// The row's kind and body.
    public func row() throws -> (kind: String, body: Data) {
        let body = try JSONEncoder().encode(Body(answer: answer, rev: rev, seen: seen))
        return (unsent ? Self.unsentKind : Self.sentKind, body)
    }

    /// The kept queue from the row - nil for a row that doesn't read (another build's: let go).
    public init?(kind: String, body: Data) {
        guard kind == Self.unsentKind || kind == Self.sentKind,
              let read = try? JSONDecoder().decode(Body.self, from: body), !read.answer.tracks.isEmpty else { return nil }
        self.init(answer: read.answer, rev: read.rev, seen: read.seen, unsent: kind == Self.unsentKind)
    }
}

extension DownloadDatabase {
    /// The person's kept queue (queue_pending's one row) - nil for none, or one that doesn't read.
    public func keptResume() throws -> QueueKept? {
        guard let row = try keptQueue() else { return nil }
        return QueueKept(kind: row.kind, body: row.body)
    }

    /// The kept queue replaced (nil: forgotten), `at` ms since 1970.
    public func keepResume(_ kept: QueueKept?, at: Int64) throws {
        guard let kept else {
            try forgetQueue()
            return
        }
        let row = try kept.row()
        try keepQueue(kind: row.kind, body: row.body, at: at)
    }
}
