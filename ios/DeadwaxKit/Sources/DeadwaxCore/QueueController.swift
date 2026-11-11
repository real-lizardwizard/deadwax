import Foundation

// The player's own rules around Up Next (the web's usePlayer.ts: catchUp, edit/apply/replaceUpcoming, runHeld,
// topUp, playTracks, next, previous, onEnded, a failure's skip, restoreQueue) as a state machine over the engine,
// which it reaches only through EngineLink - so it is tested on Linux against a fake engine, as player.sim.cjs
// tests usePlayer. The app makes one, on the main thread, and calls it for every action and every engine change.

/// One entry of the queue as the engine plays it: the song (with the level it plays at), and the key Up Next names
/// the entry by - unique in the queue, so the engine can tell the same song twice apart.
public struct QueueEntry: Sendable, Equatable {
    public let key: Int
    public let track: QueueTrack

    public init(key: Int, track: QueueTrack) {
        self.key = key
        self.track = track
    }

    /// What the entry decodes to: two entries with the same `audio` are the same samples at the same gain, so an
    /// edit that only re-keys them (Shuffle off makes new marks for the same songs) changes nothing heard.
    public var audio: String { "\(track.id)|\(track.level?.rawValue ?? "off")" }
}

/// Where the engine is, as it answers at the moment it is asked - after every call made to it before.
public struct EngineHeard: Sendable, Equatable {
    /// the entry heard (or, before anything is heard, the one loading or put back)
    public var index: Int
    /// how far into it, in seconds, as heard (the output's latency taken off)
    public var seconds: Double
    /// the queue played out: the engine stopped at its last entry's end
    public var ended: Bool

    public init(index: Int, seconds: Double, ended: Bool = false) {
        self.index = index
        self.seconds = seconds
        self.ended = ended
    }
}

/// What the controller asks of the audio engine. Every call is made on the main thread, and `heard()` and
/// `replaceUpcoming` answer at once (the engine's own queue, synchronously), each after every call before it.
public protocol EngineLink: AnyObject {
    /// A new queue, played from `index`, `seconds` in.
    func play(_ entries: [QueueEntry], from index: Int, at seconds: Double)
    /// A queue put back paused at `index`, `seconds` in: nothing loads, fetches or plays until `resume()`.
    func restore(_ entries: [QueueEntry], from index: Int, at seconds: Double)
    /// Up Next changed what comes after the entry heard (`current`, the same in both lists, and everything before
    /// it). True: the engine follows `entries` from here. False: it can't now - the entry heard isn't `current`
    /// (it moved on), or the change would replace a next song already scheduled on a player node - and nothing
    /// changed; the controller holds the change and makes it again at the next song change (a row's tap, which
    /// leaves the song heard anyway, is played afresh with `play` instead).
    func replaceUpcoming(_ entries: [QueueEntry], current: Int) -> Bool
    /// Another entry of the queue, from its start; playing or paused as the engine was.
    func skip(to index: Int)
    /// `seconds` into the entry heard.
    func seek(to seconds: Double)
    func resume()
    func stop()
    /// The entry heard and how far into it; nil with nothing loaded.
    func heard() -> EngineHeard?
}

/// Up Next's player: the queue, the device's Repeat, and every change made through the engine so the song heard is
/// never touched.
public final class QueueController {
    /// The queue as the engine plays it - its index the entry heard as of the last catch-up.
    public private(set) var queue: UpNextQueue = .empty
    /// The device's Repeat (never saved with the queue).
    public private(set) var repeatMode: Repeat
    /// Whether the listener means the music to be playing: a play, a tap on a song or a row, a queue started set it;
    /// a pause, the queue's end, a failure that stops and a stop clear it. The app keeps it in step with its own
    /// play and pause; Next and Previous keep it as it is (paused stays paused).
    public var intendsToPlay = false
    /// The queue changed - redraw.
    public var onChange: ((UpNextQueue) -> Void)?
    /// Repeat changed - keep it (UserDefaults, `Repeat.storageKey`, `rawValue`).
    public var onRepeatChange: ((Repeat) -> Void)?

    private let engine: EngineLink
    private let random: () -> Double
    /// An Up Next change the engine couldn't take when it was made: made at the next song change or tick, against
    /// the queue as it is then. Changes held one after another compose, the first first: none is lost.
    private var heldEdit: ((UpNextQueue) -> UpNextQueue)?

    public init(engine: EngineLink, repeat mode: Repeat = .off, random: @escaping () -> Double = UpNext.systemRandom) {
        self.engine = engine
        self.repeatMode = mode
        self.random = random
    }

    /// Shuffle is the queue's: carried by it (and by resume's snapshot), never kept apart.
    public var shuffle: Bool { queue.upNext?.shuffle ?? false }
    /// (Part B) the library's shuffle the queue is, when it is one: Shuffle can't be turned off then.
    public var paged: Paged? { queue.upNext?.paged }
    /// Whether a change is waiting for the engine (Debug).
    public var holdsAnEdit: Bool { heldEdit != nil }
    /// What Up Next draws now.
    public var view: UpNextView { upNextView(queue, repeatMode) }

    /// The queue's entries as the engine takes them: each song with its mark's key (a plain queue's, its place).
    public static func entries(_ queue: UpNextQueue) -> [QueueEntry] {
        let marks = queue.upNext?.marks
        return queue.tracks.enumerated().map { place, track in
            QueueEntry(key: marks.map { place < $0.count ? $0[place].key : place } ?? place, track: track)
        }
    }

    // MARK: following the engine

    /// The engine has run into a later entry than the queue says (a join no change has been seen for yet): the queue
    /// moved there first, and a held change made against it - so nothing acts on a song that has finished. True if
    /// it moved. Every action calls it first.
    @discardableResult
    public func catchUp() -> Bool {
        guard let heard = engine.heard(), heard.index > queue.index, heard.index < queue.tracks.count else { return false }
        queue.index = heard.index
        changed()
        runHeld()
        return true
    }

    /// The engine said something changed (its entry, its phase): caught up with it.
    public func engineChanged() {
        catchUp()
    }

    /// Twice a second or so while playing, with how much of the song playing has been heard (the listen's seconds,
    /// not the position) and its length when the decoded length is known: a held change made, then Repeat's top-up
    /// once the song has been heard TOP_UP_HEARD_S (or half of a shorter one). Only listening tops up, so a queue
    /// whose songs all fail still comes to an end.
    public func tick(heard: Double, length: Double? = nil) {
        catchUp()
        runHeld()
        guard repeatMode != .off, let track = queue.current else { return }
        let songLength = length ?? track.duration
        let need = songLength > 0 ? min(UpNext.topUpHeardSeconds, songLength / 2) : UpNext.topUpHeardSeconds
        guard heard >= need else { return }
        let mode = repeatMode
        edit { [random] in toppedUp($0, mode, random: random) }
    }

    // MARK: starting

    /// A list played - an album's Play (start 0), Shuffle (start nil, shuffled), a song's tap (its place): topped up
    /// for Repeat before the engine starts, a change held for the queue before let go.
    public func playTracks(_ tracks: [QueueTrack], start: Int?, shuffle: Bool = false, paged: Paged? = nil) {
        heldEdit = nil
        let next = toppedUp(startUpNext(tracks, start: start, shuffle: shuffle, random: random, paged: paged),
                            repeatMode, random: random)
        queue = next
        guard next.current != nil else {
            intendsToPlay = false
            engine.stop()
            changed()
            return
        }
        intendsToPlay = true
        engine.play(Self.entries(next), from: next.index, at: 0)
        changed()
    }

    /// A queue put back paused at `position` seconds into its song (resume's one action): fitted to this device's
    /// Repeat, any change held for the queue before let go, nothing loaded or played. Nil - and nothing done - while
    /// the listener means the music to be playing, or for a queue with no song to show.
    @discardableResult
    public func restoreQueue(_ saved: UpNextQueue, position: Double) -> UpNextQueue? {
        guard !intendsToPlay else { return nil }
        let next = toppedUp(withRepeat(saved, repeatMode), repeatMode, random: random)
        guard let track = next.current else { return nil }
        heldEdit = nil
        queue = next
        let at = position.isFinite ? max(0, track.duration > 0 ? min(position, track.duration) : position) : 0
        engine.restore(Self.entries(next), from: next.index, at: at)
        changed()
        return next
    }

    // MARK: Up Next's changes

    /// Shuffle on or off for the queue playing (nothing for a library's shuffle, whose order is the shuffle).
    public func setShuffle(_ on: Bool) {
        guard queue.current != nil else { return }
        let mode = repeatMode
        edit { [random] in toppedUp(withShuffle($0, on, random: random), mode, random: random) }
    }

    /// Repeat set: kept on the device, and the queue fitted to it - the copies or later rounds let go, the new ones
    /// queued. Set in a song's last ~2.5 s, with the next song already on a player node (D4), the change is held and
    /// made after the join, against the song then playing: Repeat One turned on there repeats the NEXT song, and
    /// Repeat off lets the song's copy already scheduled play once more - where the web, which can cut its buffer up
    /// to the playhead, repeats (or stops repeating) the song being heard.
    public func setRepeat(_ mode: Repeat) {
        guard mode != repeatMode else { return }
        repeatMode = mode
        onRepeatChange?(mode)
        guard queue.current != nil else {
            changed()
            return
        }
        edit { [random] in toppedUp(withRepeat($0, mode), mode, random: random) }
        changed()
    }

    /// Play Next. True when it started the music - nothing was playing, or the queue had played out with nothing
    /// after it - so the songs play from the first, as playTracks; false when they were added (the notice's case).
    @discardableResult
    public func playNext(_ tracks: [QueueTrack]) -> Bool { addSongs(tracks) { withNext($0, tracks) } }

    /// Play Last: as Play Next, after the songs already added.
    @discardableResult
    public func playLast(_ tracks: [QueueTrack]) -> Bool { addSongs(tracks) { withLast($0, tracks) } }

    private func addSongs(_ tracks: [QueueTrack], _ how: @escaping (UpNextQueue) -> UpNextQueue) -> Bool {
        guard !tracks.isEmpty else { return false }
        catchUp()
        if queue.current == nil || (engine.heard()?.ended == true && onward(queue) == nil) {
            playTracks(tracks, start: 0)
            return true
        }
        apply(how)
        return false
    }

    /// A row's tap: that song now, playing even from a pause - made now or not at all, never held. A key gone from
    /// Up Next does nothing. An edit the engine can't take this moment (D4: the next song already on a player node,
    /// which is every song's last ~2.5 s; or a seek on its way) is no bar, unlike the web's "a seek on its way:
    /// nothing": the jump leaves the song heard anyway, so the queue is played afresh from the row, as a skip would
    /// start it - nothing the listener stays on is cut.
    public func jumpTo(key: Int) {
        catchUp()
        guard let edited = jumpedTo(queue, key) else { return }
        if replaceUpcoming(edited) {
            //? a row's tap plays it, paused or not - next() starts what the listener means to be playing
            intendsToPlay = true
            next()
            return
        }
        //? the engine may have run on into the next song since the catch-up: the row found again in the queue as it
        //? is now (gone, or now the song playing: nothing more to do)
        catchUp()
        guard let fresh = jumpedTo(queue, key), let index = onward(fresh) else { return }
        queue = fresh
        queue.index = index
        intendsToPlay = true
        engine.play(Self.entries(queue), from: index, at: 0)
        changed()
        runHeld()
    }

    public func moveInQueue(key: Int, to: Int) { edit { movedKey($0, key, to: to) } }
    public func removeFromQueue(key: Int) { edit { withoutKey($0, key) } }
    public func clearPlayingNext() { edit { withoutAdded($0) } }

    /// (Part B) the library's shuffle's next page, or a fresh order - an edit like Play Last.
    public func extendQueue(token: String, tracks: [QueueTrack], next: Paged? = nil) {
        edit { withMore($0, token: token, tracks: tracks, next: next) }
    }

    // MARK: moving

    /// Next: past Repeat One's copies to the next song. On Repeat All's last song, begun too lately for its top-up,
    /// the next time round queued first. Playing or paused as it was.
    public func next() {
        catchUp()
        if repeatMode == .all && onward(queue) == nil {
            apply { [random] in toppedUp($0, .all, random: random) }
        }
        guard let index = onward(queue) else { return }
        move(to: index)
    }

    /// Previous: the song again past 3 s (or at the first song), else the entry before the run of Repeat One's copies
    /// the song playing is part of. Playing or paused as it was.
    public func previous() {
        catchUp()
        switch backward(queue, position: engine.heard()?.seconds ?? 0) {
        case .restart: engine.seek(to: 0)
        case .go(let index): move(to: index)
        }
    }

    /// The engine played out its last entry (its phase ended). With Repeat on and nothing queued after the song - it
    /// was sought to its end before the top-up's 2 s - the list or the song again, played on from there; otherwise
    /// the music has stopped. True if it plays on.
    @discardableResult
    public func queueEnded() -> Bool {
        catchUp()
        if repeatMode != .off && nextIndex(queue) == nil {
            queue = toppedUp(queue, repeatMode, random: random)
        }
        guard let index = nextIndex(queue) else {
            intendsToPlay = false
            changed()
            return false
        }
        queue.index = index
        intendsToPlay = true
        engine.play(Self.entries(queue), from: index, at: 0)
        changed()
        runHeld()
        return true
    }

    /// The song heard won't play, and won't be asked for again (the retry is the app's): while the listener means the
    /// music to be playing, the next song past its Repeat One copies, played - or, with none, the music stops as at
    /// the queue's end. Paused (a pocketed phone a call paused), nothing moves and nothing plays: the failure waits
    /// for a tap, as the web's afterFailure() stops when !intendsToPlay. The index skipped to, or nil.
    @discardableResult
    public func skipFailed() -> Int? {
        catchUp()
        guard intendsToPlay else { return nil }
        guard let index = pastCopies(queue, from: queue.index + 1) else {
            intendsToPlay = false
            changed()
            return nil
        }
        queue.index = index
        intendsToPlay = true
        engine.play(Self.entries(queue), from: index, at: 0)
        changed()
        runHeld()
        return index
    }

    // MARK: the rules

    /// To another entry of the queue: the engine skips there (paused stays paused; a row's tap set intendsToPlay,
    /// and plays).
    private func move(to index: Int) {
        queue.index = index
        engine.skip(to: index)
        if intendsToPlay { engine.resume() }
        changed()
        runHeld()
    }

    /// An Up Next action: the queue caught up with the engine, then the change made.
    private func edit(_ change: @escaping (UpNextQueue) -> UpNextQueue) {
        catchUp()
        apply(change)
    }

    /// A change made now - or, if the engine can't take it this moment, held and made at the next song change, a
    /// change held already going first.
    private func apply(_ change: @escaping (UpNextQueue) -> UpNextQueue) {
        let all: (UpNextQueue) -> UpNextQueue
        if let held = heldEdit {
            all = { change(held($0)) }
        } else {
            all = change
        }
        heldEdit = nil
        if !replaceUpcoming(all(queue)) { heldEdit = all }
    }

    /// The change held, made now if the engine can take it.
    private func runHeld() {
        guard let held = heldEdit else { return }
        heldEdit = nil
        if !replaceUpcoming(held(queue)) { heldEdit = held }
    }

    /// Up Next changed what comes after the song playing. Up Next's functions keep the song playing and everything
    /// before it; a queue that doesn't is played afresh (a bug's guard, as the web's). False when the engine can't
    /// take it now.
    private func replaceUpcoming(_ next: UpNextQueue) -> Bool {
        if next == queue { return true }
        if next.index != queue.index || next.current?.id != queue.current?.id {
            queue = next
            if next.current == nil {
                engine.stop()
            } else if intendsToPlay {
                engine.play(Self.entries(next), from: next.index, at: 0)
            } else {
                engine.restore(Self.entries(next), from: next.index, at: 0)
            }
            changed()
            return true
        }
        guard engine.replaceUpcoming(Self.entries(next), current: next.index) else { return false }
        queue = next
        changed()
        return true
    }

    private func changed() {
        onChange?(queue)
    }
}
