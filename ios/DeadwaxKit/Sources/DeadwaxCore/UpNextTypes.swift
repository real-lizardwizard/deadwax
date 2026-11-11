import Foundation

// Up Next's types: the web app's ui/src/lib/upNext.ts and the queue parts of ui/src/lib/playQueue.ts, as values.
// The functions are in UpNext.swift, what is drawn in UpNextView.swift; notes/ios.md says why the port is held to
// traces recorded from the TypeScript (ios/scripts/export-traces.cjs).

/// One song as the queue needs it: enough to play it, label it and show its cover (playQueue.ts `QueueTrack`), and
/// the level it was queued at (loudness.ts `LevelledTrack`).
public struct QueueTrack: Sendable, Equatable, Hashable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var albumId: String?
    public var coverArt: String?
    /// seconds, from Navidrome's tags; 0 when it doesn't know
    public var duration: Double
    public var contentType: String?
    /// the file's extension - what tells an Opus file from a Vorbis one (both `audio/ogg`)
    public var suffix: String?
    /// Hz, bits and channels as Navidrome read them from the file; 0 when it didn't say
    public var sampleRate: Int
    public var bitDepth: Int
    public var channels: Int
    /// the Normalization level it plays at; nil plays it as the file is (Off)
    public var level: Level?

    public init(id: String, title: String, artist: String, album: String, albumId: String? = nil,
                coverArt: String? = nil, duration: Double = 0, contentType: String? = nil, suffix: String? = nil,
                sampleRate: Int = 0, bitDepth: Int = 0, channels: Int = 0, level: Level? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.albumId = albumId
        self.coverArt = coverArt
        self.duration = duration
        self.contentType = contentType
        self.suffix = suffix
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
        self.level = level
    }

    /// A song of Navidrome's as a queue entry, its album's answer filling in what the song leaves out - the web's
    /// `toQueueTrack(song, album)` (ui/src/player/api.ts): the album's artist, name, id and cover, 0 for a length or
    /// a format Navidrome didn't say.
    public init(song: Song, albumId: String, albumName: String, albumArtist: String? = nil,
                albumCoverArt: String? = nil, level: Level? = nil) {
        self.init(id: song.id, title: song.name, artist: song.artist ?? albumArtist ?? "",
                  album: song.album ?? albumName, albumId: song.albumId ?? albumId,
                  coverArt: song.coverArt ?? albumCoverArt, duration: song.duration ?? 0,
                  contentType: song.contentType, suffix: song.suffix, sampleRate: song.samplingRate ?? 0,
                  bitDepth: song.bitDepth ?? 0, channels: song.channelCount ?? 0, level: level)
    }
}

/// Repeat, the device's own setting (never saved with the queue). `allCases` is REPEATS, the Repeat button's
/// cycle: off -> all -> one.
public enum Repeat: String, CaseIterable, Sendable {
    case off, all, one

    /// Where the device keeps it - the web's localStorage key, in UserDefaults on the phone.
    public static let storageKey = "deadwax-player-repeat"

    /// What was stored, read with care (state/persisted.ts): "all" and "one" as they are; anything else - nothing,
    /// "ALL", a word, an empty string - is off.
    public static func read(_ stored: String?) -> Repeat {
        switch stored {
        case "all": return .all
        case "one": return .one
        default: return .off
        }
    }
}

/// Where one entry of the queue came from.
public enum MarkFrom: String, Sendable {
    /// the list playTracks was given - an album, an artist's albums, a library's shuffle
    case source
    /// Play Next or Play Last
    case added
    /// a copy Repeat One put after the song
    case one
}

/// Up Next's account of one entry of the queue.
public struct Mark: Sendable, Equatable, Hashable {
    /// unique in this queue: what a row of Up Next, a move, a removal and a jump name it by
    public var key: Int
    public var from: MarkFrom
    /// a source entry's place in `source` (a copy: its original's); -1 for a song added
    public var at: Int
    /// which time round of the list (0 the first; Repeat All's later ones 1, 2...); -1 for a song added
    public var pass: Int

    public init(key: Int, from: MarkFrom, at: Int, pass: Int) {
        self.key = key
        self.from = from
        self.at = at
        self.pass = pass
    }
}

/// One of the list's songs taken out of a time round - removed, or jumped over - so a shuffle doesn't bring it back.
public struct LeftOut: Sendable, Equatable, Hashable {
    public var pass: Int
    public var at: Int

    public init(pass: Int, at: Int) {
        self.pass = pass
        self.at = at
    }
}

/// Whose library a library's shuffle is: your albums', or the whole store's ("all music").
public enum PagedScope: String, Sendable {
    case yours, store
}

/// (Part B) A whole library's shuffle, played a page at a time: the order deadwax holds under `token`, how many
/// songs it has, how many of them are in the queue, whose library it is, and the level it was queued at.
public struct Paged: Sendable, Equatable, Hashable {
    public var token: String
    public var total: Int
    public var fetched: Int
    public var scope: PagedScope
    public var level: Level?

    public init(token: String, total: Int, fetched: Int, scope: PagedScope, level: Level? = nil) {
        self.token = token
        self.total = total
        self.fetched = fetched
        self.scope = scope
        self.level = level
    }
}

/// (Part B) The order of an earlier time round still in the queue, kept by its round.
public struct PagedRound: Sendable, Equatable, Hashable {
    public var pass: Int
    public var paged: Paged

    public init(pass: Int, paged: Paged) {
        self.pass = pass
        self.paged = paged
    }
}

/// Up Next's account of the queue, entry by entry beside its tracks.
public struct UpNextState: Sendable, Equatable {
    /// one per entry of the queue's tracks, in step with them: always the same count
    public var marks: [Mark]
    /// the list as playTracks was given it, in its own order
    public var source: [QueueTrack]
    public var shuffle: Bool
    public var nextKey: Int
    /// the index playTracks started at: the first time round's songs before it were never heard
    public var startedAt: Int
    /// the list's songs taken out of a time round; never pruned
    public var left: [LeftOut]
    /// (Part B) the library's shuffle this queue is, when it is one - the order of its last time round
    public var paged: Paged?
    /// (Part B) the orders of the earlier times round still in the queue. nil and [] are different states, as in
    /// the TypeScript (absent, and present but empty - withRepeat can leave it so).
    public var pagedRounds: [PagedRound]?

    public init(marks: [Mark], source: [QueueTrack], shuffle: Bool, nextKey: Int, startedAt: Int,
                left: [LeftOut] = [], paged: Paged? = nil, pagedRounds: [PagedRound]? = nil) {
        self.marks = marks
        self.source = source
        self.shuffle = shuffle
        self.nextKey = nextKey
        self.startedAt = startedAt
        self.left = left
        self.paged = paged
        self.pagedRounds = pagedRounds
    }
}

/// The engine's queue - its entries and the one playing - with Up Next's account of it. `index` is -1 for
/// nothing; only `empty` (and a plain queue made by hand) has no `upNext`.
public struct UpNextQueue: Sendable, Equatable {
    public var tracks: [QueueTrack]
    public var index: Int
    public var upNext: UpNextState?

    public init(tracks: [QueueTrack], index: Int, upNext: UpNextState? = nil) {
        self.tracks = tracks
        self.index = index
        self.upNext = upNext
    }

    /// EMPTY_QUEUE: nothing queued, nothing playing.
    public static let empty = UpNextQueue(tracks: [], index: -1)

    /// The song playing, or nil for none.
    public var current: QueueTrack? { tracks.indices.contains(index) ? tracks[index] : nil }
}

/// What "previous" does at a position in a song: the song again from its start, or another entry.
public enum PreviousAction: Sendable, Equatable {
    case restart
    case go(Int)
}

/// Up Next's numbers (upNext.ts, playQueue.ts).
public enum UpNext {
    /// REPEAT_AHEAD: entries a Repeat keeps queued past the song playing - well ahead of where the engine looks.
    public static let repeatAhead = 2
    /// UP_NEXT_DRAWN: the list's own rows Up Next draws; "And N more songs." past that.
    public static let drawn = 100
    /// TOP_UP_HEARD_S: seconds of a song heard (or half of a shorter one) before Repeat tops the queue up.
    public static let topUpHeardSeconds: Double = 2
    /// RESTART_AFTER_SECONDS: how far into a song Previous restarts it instead of going back one.
    public static let restartAfterSeconds: Double = 3
}
