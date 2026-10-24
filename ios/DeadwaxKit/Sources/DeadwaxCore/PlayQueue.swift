import Foundation

/// The songs being played and which one is current - Phase 0's queue, with the web app's rules for
/// previous and next (ui/src/lib/playQueue.ts).
public struct PlayQueue: Sendable, Equatable {
    /// How far into a song "previous" restarts it instead of going back one (RESTART_AFTER_SECONDS).
    public static let restartAfterSeconds: Double = 3

    public enum Previous: Sendable, Equatable {
        case restart
        case go(Int)
    }

    public private(set) var songs: [Song]
    public private(set) var index: Int

    public init(songs: [Song], index: Int = 0) {
        self.songs = songs
        self.index = songs.isEmpty ? 0 : min(max(index, 0), songs.count - 1)
    }

    public var current: Song? { songs.indices.contains(index) ? songs[index] : nil }
    public var isEmpty: Bool { songs.isEmpty }

    /// What "previous" does `position` seconds into the current song. The first song only restarts.
    public func previous(at position: Double) -> Previous {
        if position > Self.restartAfterSeconds || index <= 0 { return .restart }
        return .go(index - 1)
    }

    /// The song after the current one, or nil at the end (no repeat in Phase 0).
    public var nextIndex: Int? { index + 1 < songs.count ? index + 1 : nil }

    public mutating func move(to index: Int) {
        guard songs.indices.contains(index) else { return }
        self.index = index
    }
}
