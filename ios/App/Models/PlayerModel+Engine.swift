import AVFAudio
import DeadwaxAudio
import DeadwaxCore
import Foundation

// The player's engine glue (app 0.2): PlaybackEngine behind Core's EngineLink, each entry's level decided once and
// applied in its source, and the first song of a play held while deadwax measures its album. notes/ios.md, "Phase 1:
// the player's wiring".

/// A clock that only goes forward and runs on while the phone sleeps (ContinuousClock), in seconds - the listen's,
/// the level wait's and the loudness book's time. Read from any thread.
enum Monotonic {
    private static let origin = ContinuousClock.now

    static func seconds() -> Double {
        let elapsed = ContinuousClock.now - origin
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
}

/// The client the engine's opens ask through, read at each open: a sign-in mid-queue makes a new client with the
/// new session, and the next song streams under it rather than under the session that ended.
final class ClientBox: @unchecked Sendable {
    private let lock = NSLock()
    private var held: DeadwaxClient?

    var client: DeadwaxClient? {
        get { lock.withLock { held } }
        set { lock.withLock { held = newValue } }
    }
}

/// QueueController's engine (Core's EngineLink): every call on the main thread, each made on PlaybackEngine.
///
/// - **Keys.** The engine names an entry by `generation << 32 | Up Next's key`. Up Next's keys start again at 0 with
///   every queue, so a state still on its way from the queue before (the engine publishes on the main queue, later)
///   would otherwise name an entry of the new one; the generation moves with each new queue and each stop, and the
///   model drops a state of another generation.
/// - **Levels.** One `LevelStore` per queue (levels.md 4.3: "a new play is a new queue and new decisions"): each
///   entry's decision made at its first open and kept for every later one, by Up Next's key - carried to the new key
///   when the engine re-keys what it has scheduled (`replaceUpcoming`). The first entry of a play or a skip may wait
///   for its album's loudness (`LevelGate`); a join never does; a queue put back decides when played, at once.
/// - **The session.** Play and resume make the audio session active first (`activate`); iOS refusing it plays
///   nothing - the queue is put back paused where it was asked to play, and `refused` says so.
final class PlayerEngineLink: EngineLink {
    let engine: PlaybackEngine
    let clientBox = ClientBox()
    /// The queue's generation: +1 with each new queue and each stop.
    private(set) var generation = 0
    /// The level decisions of the queue playing.
    private(set) var levels: LevelStore
    /// The entries last given to the engine (the engine's tracks, by place).
    private(set) var entries: [QueueEntry] = []
    /// Debug's test songs: their downloaded copies played (a song with none is streamed).
    private(set) var copies = false
    /// Navidrome's size of a song by its id, when the app has the song (the stream cache's length check).
    var size: (String) -> Int64? = { _ in nil }
    /// The audio session made active before anything plays; false - iOS refused - and nothing plays.
    var activate: () -> Bool = { true }
    /// iOS refused the session at a play or a resume.
    var refused: () -> Void = {}

    private let files: SongFiles
    private let shelf: LoudnessShelf
    private let decided: @Sendable (LevelStore, LevelDecisions) -> Void
    /// The next play or restore starts a new queue: a new generation and new decisions.
    private var startsQueue = false
    private var nextCopies = false

    init(engine: PlaybackEngine, files: SongFiles, shelf: LoudnessShelf,
         decided: @escaping @Sendable (LevelStore, LevelDecisions) -> Void) {
        self.engine = engine
        self.files = files
        self.shelf = shelf
        self.decided = decided
        levels = LevelStore(shelf: shelf, onDecided: decided)
    }

    // MARK: keys

    static func engineKey(_ key: Int, generation: Int) -> Int { generation << 32 | (key & 0xFFFF_FFFF) }

    /// The engine's key for an entry of the queue playing.
    func engineKey(_ key: Int) -> Int { Self.engineKey(key, generation: generation) }

    /// Whether an engine key is of the queue playing.
    func isCurrent(_ engineKey: Int) -> Bool { engineKey >> 32 == generation }

    // MARK: the app's

    /// The calls made until `endStart()` may start a new queue (Play, Shuffle, a song's tap, a Play Next with nothing
    /// queued, a queue put back): the first play or restore among them does, with Debug's copies or not.
    func beginStart(copies: Bool) {
        startsQueue = true
        nextCopies = copies
    }

    func endStart() {
        startsQueue = false
    }

    /// The engine's position, when it is in the queue playing - the entry heard (or loading, or put back), its place,
    /// how far in as heard, and its decoded length once known.
    func position() -> EnginePosition? {
        guard let at = engine.position(), isCurrent(at.key), entries.indices.contains(at.index),
              engineKey(entries[at.index].key) == at.key else { return nil }
        return at
    }

    // MARK: EngineLink

    func play(_ entries: [QueueEntry], from index: Int, at seconds: Double) {
        take(entries)
        levels.mayWait(entries.indices.contains(index) ? entries[index].key : nil)
        let tracks = makeTracks(entries)
        guard activate() else {
            engine.restoreQueue(tracks, at: index, seconds: seconds)
            refused()
            return
        }
        engine.play(tracks, from: index, at: seconds)
    }

    func restore(_ entries: [QueueEntry], from index: Int, at seconds: Double) {
        take(entries)
        levels.mayWait(nil)
        engine.restoreQueue(makeTracks(entries), at: index, seconds: seconds)
    }

    func replaceUpcoming(_ new: [QueueEntry], current: Int) -> Bool {
        guard engine.replaceUpcoming(makeTracks(new)) else { return false }
        // what the engine kept of what it had scheduled takes the new list's keys, and each kept entry's decision
        // goes with it (LevelDecisions.carry(from:to:after:), the engine's own walk)
        levels.carry(from: entries, to: new, after: current)
        entries = new
        return true
    }

    func skip(to index: Int) {
        levels.mayWait(entries.indices.contains(index) ? entries[index].key : nil)
        engine.skip(to: index)
    }

    func seek(to seconds: Double) {
        engine.seek(to: seconds)
    }

    func resume() {
        guard activate() else {
            refused()
            return
        }
        engine.resume()
    }

    func stop() {
        generation += 1
        levels = LevelStore(shelf: shelf, onDecided: decided)
        entries = []
        engine.stop()
    }

    func heard() -> EngineHeard? {
        guard let at = position() else { return nil }
        let ended = at.index == entries.count - 1 && engine.debug().phase == .ended
        return EngineHeard(index: at.index, seconds: at.seconds, ended: ended)
    }

    // MARK: the tracks

    private func take(_ new: [QueueEntry]) {
        if startsQueue {
            startsQueue = false
            generation += 1
            levels = LevelStore(shelf: shelf, onDecided: decided)
            copies = nextCopies
        }
        entries = new
    }

    /// The engine's tracks: each entry's song as the entry has it (`Song(track:size:)`, so the cache, the format and
    /// the level all read the entry), opened from the cache or the stream - or Debug's downloaded copy - and handed
    /// to the queue's LevelStore, which wraps it at the entry's gain. The closures run on the engine's queue.
    private func makeTracks(_ entries: [QueueEntry]) -> [EngineTrack] {
        let generation = self.generation
        let copies = self.copies
        let levels = self.levels
        let files = self.files
        let box = clientBox
        return entries.map { entry in
            let song = Song(track: entry.track, size: size(entry.track.id))
            let level = entry.track.level
            let key = entry.key
            return EngineTrack(key: Self.engineKey(key, generation: generation), audio: entry.audio, song: song) { start in
                let source: PCMSource
                if copies, let url = files.downloadedURL(for: song) {
                    source = try FileSource(url: url, start: start)
                } else {
                    guard let client = box.client else {
                        throw AudioFailure("There's no deadwax address to stream the song from.", kind: .other)
                    }
                    source = try files.streamSource(for: song, client: client, start: start)
                }
                return levels.open(key: key, level: level, song: song, source: source)
            }
        }
    }
}

/// One queue's level decisions (levels.md 4.3), shared by the main thread and the engine's queue behind one lock:
/// each entry decided once, at its first open, from the loudness book's answer for its album then - one answer per
/// album for its album-level entries - and the source wrapped at the decision's multiplier (`GainedSource.wrap`,
/// which hands an Off, as-it-is or 0 dB source back untouched: no multiply at all).
///
/// The first entry of a play or skip (`mayWait`) is opened behind a `LevelGate` while `LevelWait` says to wait - no
/// answer yet, or one saying its album is being measured - for at most 20 s on the engine's own retry, with the book
/// asked to read every second meanwhile (`LoudnessShelf.hurry`); a failed read with no answer ends the wait. An
/// answer read before the wait began and no longer fresh (LoudnessAsking.believed) counts as none.
final class LevelStore: @unchecked Sendable {
    private let lock = NSLock()
    private let shelf: LoudnessShelf
    private let onDecided: @Sendable (LevelStore, LevelDecisions) -> Void
    private var decisions = LevelDecisions()
    /// The Up Next key whose next open may wait.
    private var waitKey: Int?
    /// When each waiting entry's wait began: a seek mid-wait opens it again without starting the 20 s afresh.
    private var waitSince: [Int: Double] = [:]

    init(shelf: LoudnessShelf, onDecided: @escaping @Sendable (LevelStore, LevelDecisions) -> Void) {
        self.shelf = shelf
        self.onDecided = onDecided
    }

    /// The decisions as they are now.
    var snapshot: LevelDecisions { lock.withLock { decisions } }

    /// The entry whose open may wait (the first of a play or a skip); nil for none (a queue put back).
    func mayWait(_ key: Int?) {
        lock.withLock { waitKey = key }
    }

    /// An edit the engine took: each entry it re-keyed keeps its decision.
    func carry(from old: [QueueEntry], to new: [QueueEntry], after current: Int) {
        let changed: LevelDecisions? = lock.withLock {
            let before = decisions
            decisions.carry(from: old, to: new, after: current)
            return decisions == before ? nil : decisions
        }
        if let changed { onDecided(self, changed) }
    }

    /// The entry's source at its level: decided now, or behind a gate that decides once the wait is over.
    func open(key: Int, level: Level?, song: Song, source: PCMSource) -> PCMSource {
        let wait = lock.withLock { waitKey == key }
        if let made = attempt(key: key, level: level, song: song, wait: wait) {
            return GainedSource.wrap(source, factor: made.multiplier)
        }
        return LevelGate(source) { [self] in attempt(key: key, level: level, song: song, wait: true) }
    }

    /// The entry's decision - or nil while it should wait.
    private func attempt(key: Int, level: Level?, song: Song, wait: Bool) -> AppliedLevel? {
        var published: LevelDecisions?
        let made: AppliedLevel? = lock.withLock {
            if let made = decisions.decided(key) { return made }
            let album = song.albumId.flatMap { $0.isEmpty ? nil : $0 }
            let (answer, failed, fetchedAt) = album.map { shelf.answer($0) } ?? (nil, false, 0)
            if wait, let album, decisions.settled(key: key, level: level, song: song) == nil {
                let now = Monotonic.seconds()
                let since = waitSince[key] ?? now
                waitSince[key] = since
                // an answer from before the wait that is no longer fresh counts as none: the play's own read is
                // waited for (LoudnessAsking.believed); once the wait is over, decided from what is in hand
                let believed = answer.flatMap {
                    LoudnessAsking.believed($0, fetchedAt: fetchedAt, waitBegan: since, now: now) ? $0 : nil
                }
                if LevelWait.shouldWait(level: level, song: song, answer: believed, waited: now - since, readFailed: failed) {
                    shelf.hurry(album, at: now)
                    return nil
                }
            }
            let made = decisions.decide(key: key, level: level, song: song, answer: answer)
            waitSince[key] = nil
            published = decisions
            return made
        }
        if let published { onDecided(self, published) }
        return made
    }
}

/// The first song of a play, held while its level waits: `.waiting` (the engine asks again in a moment, Now Playing
/// shows it loading) until `decide` answers, then the source at that level - the song's bytes arriving meanwhile.
final class LevelGate: PCMSource {
    private let inner: PCMSource
    private let decide: () -> AppliedLevel?
    private var through: PCMSource?

    init(_ inner: PCMSource, decide: @escaping () -> AppliedLevel?) {
        self.inner = inner
        self.decide = decide
    }

    var format: AVAudioFormat? { inner.format }
    var busy: Bool { through?.busy ?? false }

    func read(maxFrames: AVAudioFrameCount) throws -> PCMRead {
        if let through { return try through.read(maxFrames: maxFrames) }
        guard let made = decide() else { return .waiting }
        let wrapped = GainedSource.wrap(inner, factor: made.multiplier)
        through = wrapped
        return try wrapped.read(maxFrames: maxFrames)
    }

    func close() {
        inner.close()
    }
}
