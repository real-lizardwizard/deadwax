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
/// Two things are the phone's own (phase4-library.md 2.3; notes/ios.md "Phase 4, slice 1, after its review"):
/// - **`keeping`**: every write takes the ids of the albums the queue names (QueueAlbums.named), and the trim never
///   lets one of them go - nor the album just put. With none passed, the store answers exactly as the web's: the
///   fixture's runs pass none. The phone needs it because it calls `also` for every album page shown (question 8),
///   so the floor climbs with each one, and past the bound the oldest album held goes - which, after a playlist's
///   `rememberQueue` (put in reverse), is the playlist's LAST album, still to play. The web has the same eviction, but
///   only past 64 albums held by Play Next and Play Last, which is all it calls `also` for.
/// - **`forget`**: an album its page found gone, let go of at once (the web never lets one go by hand).
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

    /// An album's own Play: put in as the newest, the floor back to none. `keeping`: albums never let go of here.
    public mutating func remember(_ album: Album, keeping: Set<String> = []) {
        floor = 0
        put(album)
        trim(keeping: keeping.union([album.id]))
    }

    /// A queue of several albums started (a playlist's Play): every one kept, up to `queueKept`, until the next queue -
    /// the first to play remembered last, so it is the newest and the last to be let go. `keeping`: albums never let
    /// go of here (the phone passes the new queue's, so a queue of more than `queueKept` albums keeps them all).
    public mutating func rememberQueue(_ list: [Album], keeping: Set<String> = []) {
        floor = Swift.min(Set(list.map(\.id)).count, Swift.max(1, queueKept))
        for album in list.reversed() { put(album) }
        trim(keeping: keeping)
    }

    /// Songs added to Up Next (Play Next, Play Last) - and, on the phone, an album page shown - with their album's
    /// answer: in as the newest, letting go of nothing held (up to `queueKept`) - one more kept for an album not held
    /// already. `keeping`: albums never let go of here (the phone passes the queue's, and those being added).
    public mutating func also(_ album: Album, keeping: Set<String> = []) {
        if albums[album.id] == nil {
            floor = Swift.min(Swift.max(floor, albums.count) + 1, Swift.max(1, queueKept))
        }
        put(album)
        trim(keeping: keeping.union([album.id]))
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

    /// Past the bound, the oldest let go first - passing over every album in `keeping`, so with all that is left kept
    /// the store holds more than its bound until the queue no longer names them. With `keeping` empty, the web's trim.
    private mutating func trim(keeping: Set<String>) {
        let bound = Swift.max(1, kept, floor)
        var index = 0
        while order.count > bound, index < order.count {
            let id = order[index]
            if keeping.contains(id) {
                index += 1
                continue
            }
            order.remove(at: index)
            albums.removeValue(forKey: id)
        }
    }
}

/// The albums a queue names - what PlayedAlbums' `keeping` takes (phase4-library.md 2.3): each track's album id, none
/// for a track that names none.
public enum QueueAlbums {
    public static func named(_ tracks: [QueueTrack]) -> Set<String> {
        Set(tracks.compactMap { (track: QueueTrack) -> String? in
            guard let id = track.albumId, !id.isEmpty else { return nil }
            return id
        })
    }
}
