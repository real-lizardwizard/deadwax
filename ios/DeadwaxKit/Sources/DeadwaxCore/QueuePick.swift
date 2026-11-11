import Foundation

/// Play Next and Play Last - the web app's ui/src/app/QueueMenu.tsx with lib/upNext.ts's QueuePick and queuedWords
/// and player/levelling.ts's queued(), ported as a choice the app carries out and nothing else. Held to what the
/// TypeScript answers: Tests/DeadwaxCoreTests/Fixtures/screens/queue.json (the menu driven under each setting, each
/// choice, the music started from it or not), written by ios/scripts/export-screen-vectors.cjs.
///
/// The app carries a choice out in the tap, nothing awaited first: `choose(_:setting:)` says which call and at what
/// level - `.next` is the queue's playNext, `.last` its playLast (QueueController on the Up Next branch), each song
/// queued as an entry carrying `level` - and the call answers whether the music STARTED from it (nothing was
/// playing); `notice(started:)` is then the line said for 5 s over the mini player, or nil when the music starting is
/// the notice. `QueueChoice` is the Up Next port's `QueuedHow` (UpNextView.swift), and the notice its `queuedWords`.
public typealias QueueChoice = QueuedHow

/// What the queue menu was opened with: one song (a row's •••) or an album's songs (the album's •••), always in
/// hand, and how they are queued for the player's Normalization - as an album for the album's own •••, else as songs.
public struct QueuePick<Track: Sendable>: Sendable {
    public let label: String
    public let tracks: [Track]
    /// The albums the songs are from - the app remembers them as just added (rememberAdded), so the album opens at
    /// once from Up Next.
    public let albumIds: [String]
    /// nil: queued as songs.
    public let queuedAs: QueuedAs?

    public init(label: String, tracks: [Track], albumIds: [String], queuedAs: QueuedAs? = nil) {
        self.label = label
        self.tracks = tracks
        self.albumIds = albumIds
        self.queuedAs = queuedAs
    }

    /// The menu's title (its accessibility name): the label, or "Up Next" with none.
    public var title: String { label.isEmpty ? "Up Next" : label }

    /// Play Next or Play Last chosen, under the player's Normalization `setting` - nil with no songs (nothing happens,
    /// and the menu stays). Every song is queued at `level` (loudness.ts levelFor: the album's level for an album's
    /// own •••, else the song's own; nil with Normalization Off - the file as it is). The menu closes.
    public func choose(_ choice: QueueChoice, setting: Normalization) -> Queued? {
        guard !tracks.isEmpty else { return nil }
        return Queued(choice: choice, level: levelFor(setting, queuedAs ?? .songs), tracks: tracks, remember: albumIds)
    }

    /// What `choose` asks of the app.
    public struct Queued: Sendable {
        public let choice: QueueChoice
        public let level: Level?
        public let tracks: [Track]
        /// the albums to remember as just added
        public let remember: [String]
    }

    /// The line said when the music didn't start from the choice (upNext.ts queuedWords): "Playing next: Dummy", "Added
    /// to Up Next: Dummy" - nil when it did start, the mini player being the notice then.
    public func notice(_ choice: QueueChoice, started: Bool) -> String? {
        started ? nil : queuedWords(choice, label: label)
    }
}

extension QueuePick where Track == Song {
    /// A row's •••: the one song, queued as a song (AlbumPage.tsx: `{ label: song.title, tracks: [song], albums:
    /// [album] }`).
    public static func song(_ song: Song, of album: Album) -> QueuePick<Song> {
        QueuePick(label: song.title ?? "", tracks: [song], albumIds: [album.id])
    }

    /// The album's •••: all its songs, queued as an album - nil until they are in.
    public static func album(_ album: Album) -> QueuePick<Song>? {
        guard let songs = album.song, !songs.isEmpty else { return nil }
        return QueuePick(label: album.name ?? "", tracks: songs, albumIds: [album.id], queuedAs: .album)
    }
}

public enum QueuePickWords {
    /// The menu's Cancel.
    public static let cancel = "Cancel"

    /// The level the album page's Play and Shuffle queue its songs at: always as an album (AlbumPage.tsx
    /// `queued(tracks, 'album')`).
    public static func playLevel(_ setting: Normalization) -> Level? {
        levelFor(setting, .album)
    }
}
