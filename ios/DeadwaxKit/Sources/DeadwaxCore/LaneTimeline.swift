import Foundation

/// Where each song sits on one player node's own sample count - how the engine says which song is
/// playing, and how far in, from the node's `playerTime`.
///
/// A lane is one AVAudioPlayerNode in one format (sample rate x channels). Its node counts samples
/// from the moment it started playing, and every buffer is scheduled straight after the one before,
/// so the songs on it lie end to end: song A from 0 for its frames, song B straight after. A song
/// may begin part-way in (a seek): `songOffset` is the frame of the song the entry starts at.
///
/// Pure, so the arithmetic is tested on Linux; the engine (DeadwaxAudio) only feeds it.
public struct LaneTimeline: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        /// The engine's own id for this scheduling of a song.
        public let id: Int
        /// Where the entry starts on the node's sample count.
        public let start: Int64
        /// How many frames of it are scheduled so far.
        public var frames: Int64
        /// The frame of the song the entry starts at (0 unless it began with a seek).
        public let songOffset: Int64
        /// No more frames will be added: the song's decode ended.
        public var closed: Bool

        public var end: Int64 { start + frames }
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    /// The node's sample count where the next frame scheduled will play.
    public var end: Int64 { entries.last?.end ?? 0 }

    public var isEmpty: Bool { entries.isEmpty }

    /// Begins an entry at the end of what is scheduled, and says where that is.
    @discardableResult
    public mutating func begin(id: Int, songOffset: Int64 = 0) -> Int64 {
        let start = end
        if let last = entries.indices.last { entries[last].closed = true }
        entries.append(Entry(id: id, start: start, frames: 0, songOffset: songOffset, closed: false))
        return start
    }

    /// Adds `frames` scheduled frames to the entry `id` - which must be the last one.
    public mutating func extend(id: Int, frames: Int64) {
        guard let last = entries.indices.last, entries[last].id == id, !entries[last].closed else { return }
        entries[last].frames += frames
    }

    public mutating func close(id: Int) {
        if let at = entries.firstIndex(where: { $0.id == id }) { entries[at].closed = true }
    }

    public func entry(id: Int) -> Entry? { entries.first { $0.id == id } }

    /// Which entry is playing at `sample` on the node, and the frame of its song there. A sample at an
    /// entry's end belongs to the next one; before the first it is the first's start; past the last
    /// it is held at the last's end.
    public func locate(_ sample: Int64) -> (entry: Entry, songFrame: Int64)? {
        guard let first = entries.first else { return nil }
        if sample < first.start { return (first, first.songOffset) }
        for entry in entries where sample < entry.end {
            if sample >= entry.start {
                return (entry, entry.songOffset + (sample - entry.start))
            }
        }
        let last = entries[entries.count - 1]
        return (last, last.songOffset + last.frames)
    }

    /// Drops the entries that end at or before `sample` - played, and not needed to locate anything.
    /// The last entry is always kept.
    public mutating func forget(before sample: Int64) {
        while entries.count > 1, entries[0].end <= sample { entries.removeFirst() }
    }

    public mutating func reset() { entries.removeAll() }
}
