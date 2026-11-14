import Foundation

/// The album answers the queue's songs were played from, kept so Info, Go to album and the turntable can say more of
/// the song playing than the queue does - the web app's ui/src/lib/playedAlbums.ts (createPlayedAlbums), ported (Phase
/// 4, phase4-library.md 2.3) and held to what the TypeScript answers by Fixtures/playlists/playlist-vectors.json.
///
/// A small most-recent-first store. Only the last `kept` (8) are held - unless a queue of several albums asked for
/// more: a playlist's Play (`rememberQueue`, every album of it, up to `queueKept` (64), until the next queue starts),
/// or songs added to Up Next (`also`: in as the newest, letting go of nothing held, up to `queueKept`). An album's own
/// Play is `remember`: the floor back to none, the last 8.
///
/// `forget` is the phone's own (the web never lets one go by hand): an album its page found gone.
public struct PlayedAlbums<Album: Identifiable & Sendable>: Sendable where Album.ID == String {
    /// PLAYED_KEPT and QUEUE_ALBUMS_KEPT.
    public static var playedKept: Int { 8 }
    public static var queueAlbumsKept: Int { 64 }

    private let kept: Int
    private let queueKept: Int
    /// Oldest first - a JavaScript Map's insertion order.
    private var order: [String] = []
    private var albums: [String: Album] = [:]
    /// How many the newest queue needs kept, past `kept`: its albums, none once another queue starts.
    private var floor = 0

    public init(kept: Int = PlayedAlbums.playedKept, queueKept: Int = PlayedAlbums.queueAlbumsKept) {
        self.kept = kept
        self.queueKept = queueKept
    }

    /// How many are held.
    public var count: Int { order.count }

    /// The ids held, oldest first (for the tests).
    public var ids: [String] { order }

    /// An album's own Play: put in as the newest, the floor back to none.
    public mutating func remember(_ album: Album) {
        floor = 0
        put(album)
        trim()
    }

    /// A queue of several albums started (a playlist's Play): every one kept, up to `queueKept`, until the next queue -
    /// the first to play remembered last, so it is the newest and the last to be let go.
    public mutating func rememberQueue(_ list: [Album]) {
        floor = Swift.min(Set(list.map(\.id)).count, Swift.max(1, queueKept))
        for album in list.reversed() { put(album) }
        trim()
    }

    /// Songs added to Up Next (Play Next, Play Last), with their album's answer: in as the newest, letting go of
    /// nothing held (up to `queueKept`) - one more kept for an album not held already.
    public mutating func also(_ album: Album) {
        if albums[album.id] == nil {
            floor = Swift.min(Swift.max(floor, albums.count) + 1, Swift.max(1, queueKept))
        }
        put(album)
        trim()
    }

    /// The answer for that album id, or nil when it was never played from (or has been let go of).
    public func get(_ id: String?) -> Album? {
        guard let id, !id.isEmpty else { return nil }
        return albums[id]
    }

    /// The phone's own: an album gone from the collection let go of at once.
    public mutating func forget(_ id: String) {
        guard albums.removeValue(forKey: id) != nil else { return }
        order.removeAll { $0 == id }
    }

    /// Taken out first, so the one just played from is the newest whether or not it was there.
    private mutating func put(_ album: Album) {
        if albums[album.id] != nil { order.removeAll { $0 == album.id } }
        albums[album.id] = album
        order.append(album.id)
    }

    private mutating func trim() {
        while order.count > Swift.max(1, kept, floor) {
            let oldest = order.removeFirst()
            albums.removeValue(forKey: oldest)
        }
    }
}
