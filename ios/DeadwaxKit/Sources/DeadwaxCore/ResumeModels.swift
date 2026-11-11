import Foundation

// Resume's wire: GET /deadwax/navidrome/queue's answer and the two saves' bodies and answers (src/routes/navidrome.py
// QueueSave and QueueAt, src/play_queue.py answer and kept_view). Each property is named as its JSON key, with no
// CodingKeys - as SignInBody is - so tests/test_ios_contract.py can read the names from the source and check them
// against the server's models. Both bodies are `extra="forbid"` on the server: a key it doesn't declare is a 422.

/// GET /deadwax/navidrome/queue: Navidrome's play queue as the asker, and deadwax's record when deadwax saved last.
public struct QueueAnswer: Codable, Sendable, Equatable {
    /// Navidrome's entries in its order (only the keys Navidrome sent: every field but `id` may be missing); songs
    /// it no longer has already dropped; over 2,000, the window around its index.
    public let tracks: [Song]
    /// Navidrome's currentIndex as it said it - nil for none; after songs were dropped it can name the wrong one,
    /// or be past the end. Never believed unaligned (resumed()).
    public let index: Int?
    /// seconds
    public let position: Double
    /// Navidrome's changedBy, cleaned: "deadwax" for deadwax's own saves, "" for none.
    public let changed_by: String
    /// Logins off: one queue for everyone.
    public let shared: Bool
    /// deadwax's record - only when deadwax saved last, a record exists and `tracks` isn't empty.
    public let kept: KeptQueue?

    public init(tracks: [Song], index: Int?, position: Double, changed_by: String, shared: Bool, kept: KeptQueue?) {
        self.tracks = tracks
        self.index = index
        self.position = position
        self.changed_by = changed_by
        self.shared = shared
        self.kept = kept
    }
}

/// deadwax's record of the asker's queue (store.py play_queue), as GET /queue hands it back.
public struct KeptQueue: Codable, Sendable, Equatable {
    /// bumped by every save
    public let rev: Int
    /// the rev of the last full save - what a position save is made against
    public let ids_rev: Int
    public let ids: [String]
    /// the song playing in `ids` - moved by position saves since the snapshot was made (the snapshot holds no
    /// index: its marks run with the entries)
    public let index: Int
    /// seconds
    public let position: Double
    /// the account of Up Next (snapshot v1, Resume.swift) - nil for a plain queue or one over the cap
    public let snapshot: String?
    public let device: String
    public let label: String

    public init(rev: Int, ids_rev: Int, ids: [String], index: Int, position: Double, snapshot: String?,
                device: String, label: String) {
        self.rev = rev
        self.ids_rev = ids_rev
        self.ids = ids
        self.index = index
        self.position = position
        self.snapshot = snapshot
        self.device = device
        self.label = label
    }
}

/// POST /deadwax/navidrome/queue: a full save. `snapshot` nil is left out of the JSON (the server's default).
public struct QueueSaveBody: Codable, Sendable, Equatable {
    /// 1...2,000 ids, duplicates and order kept
    public let ids: [String]
    /// the song playing, inside `ids`
    public let index: Int
    /// seconds, 0...86,400
    public let position: Double
    public let device: String
    public let label: String
    public let snapshot: String?

    public init(ids: [String], index: Int, position: Double, device: String, label: String, snapshot: String?) {
        self.ids = ids
        self.index = index
        self.position = position
        self.device = device
        self.label = label
        self.snapshot = snapshot
    }
}

/// POST /deadwax/navidrome/queue/at: a position save against the last full save's ids - exactly these five keys.
public struct QueueAtBody: Codable, Sendable, Equatable {
    public let ids_rev: Int
    /// the song playing, in the ids that full save sent
    public let index: Int
    /// seconds, 0...86,400
    public let position: Double
    public let device: String
    public let label: String

    public init(ids_rev: Int, index: Int, position: Double, device: String, label: String) {
        self.ids_rev = ids_rev
        self.index = index
        self.position = position
        self.device = device
        self.label = label
    }
}

/// What either save answers: the record's new rev and ids_rev - both nil for the break-glass admin, who keeps no
/// queue (nothing was asked or written).
public struct SavedQueue: Codable, Sendable, Equatable {
    public let rev: Int?
    public let ids_rev: Int?

    public init(rev: Int?, ids_rev: Int?) {
        self.rev = rev
        self.ids_rev = ids_rev
    }
}
