import DeadwaxAudio
import DeadwaxCore
import Foundation
import Observation
import UIKit

/// The player every screen draws and taps: the queue as Up Next has it, the entry heard, where it is, Repeat,
/// Shuffle, Normalization, the song's failure words and the notice - and the actions, each the Core call named on it.
///
/// THE PLAYER (app 0.2, notes/ios.md "Phase 1: the player's wiring"): Core's QueueController drives the queue over
/// PlaybackEngine (PlayerEngineLink: Repeat's copies, held edits (D4), Play Next/Last, moves, Shuffle, skipFailed);
/// each entry plays at the level decided at its first open (LevelStore, the LoudnessBook's answers - Off plays bit
/// for bit); plays go to Navidrome (PlayReporter, D6); the queue is saved and put back paused at launch (Core's
/// ResumeController, D5); a song that won't play is retried once, passed over or stops the queue, in a listener's
/// words (D7); the lock screen shows the entry heard. AirPods, Siri, interruptions and routes are Phase 0's: a pause
/// stops the output at once, and a call ended goes on from the same place in the same song.
@MainActor
@Observable
final class PlayerModel {
    // MARK: what the screens read

    /// Up Next's account of the queue (upnext.md 6): its tracks, the index heard, and Up Next's own state (marks,
    /// source, shuffle). `UpNextQueue.empty` with nothing queued.
    private(set) var queue: UpNextQueue = .empty
    /// What Up Next draws (Core's `upNextView(queue, repeatMode)`): playing, Playing Next, the list, Repeat One.
    var upNext: UpNextView { upNextView(queue, repeatMode) }
    /// The entry heard - its key (Up Next's mark) and its track; nil with nothing queued.
    var current: QueueEntry? { entries.indices.contains(queue.index) ? entries[queue.index] : nil }
    /// Something is queued: the mini player shows.
    var hasQueue: Bool { current != nil }
    /// The player means to play (playing, or loading to play): Play/Pause shows Pause. Not while a song that failed
    /// waits the retry's 1.5 s - Play shows, busy (`isLoading`), as the web's retry does (setPlaying(false),
    /// setBuffering(true)); a tap on it asks for the song now.
    var isPlaying: Bool { engineState.phase == .playing || engineState.phase == .loading }
    /// The song is loading (the spinner over Play/Pause): its bytes, its level's wait, or the retry's 1.5 s.
    var isLoading: Bool { retrying || engineState.phase == .loading }
    /// Seconds into the entry heard, as the engine last said (twice a second while it plays).
    private(set) var position: Double = 0
    /// What the scrubber and both clocks show: a seek's target while it is on its way (Scrub.reportedPosition, let
    /// go by Scrub.settled once the engine reports it landed), else `position`.
    var shownPosition: Double {
        Scrub.reportedPosition(pendingSeek, position: position, now: Self.nowMs())
    }
    /// The entry heard's length: the engine's decoded length once it has one, else what Navidrome said (0 for none).
    var duration: Double { length ?? current?.track.duration ?? 0 }
    /// The device's Repeat (UserDefaults `Repeat.storageKey`, never saved with the queue).
    private(set) var repeatMode: Repeat = Repeat.read(UserDefaults.standard.string(forKey: Repeat.storageKey))
    /// Shuffle is on for this queue (its UpNextState's).
    var shuffle: Bool { queue.upNext?.shuffle ?? false }
    /// A library's shuffle read on page by page (Part B); nil for every queue Phase 1 makes.
    var paged: Paged? { queue.upNext?.paged }
    /// The song's failure words, in a listener's words (PlayerWords.words / skipped) - the second line of the mini
    /// player and Now Playing (PlayerWords.secondLine(error:artist:)). Nil while all is well.
    private(set) var errorLine: String?
    /// The notice capsule's words (D11): "Playing next: …", "Added to Up Next: …", "Picked up from …" - shown for
    /// `Notice.seconds`.
    private(set) var notice: String?
    /// The device's Normalization (levels.md 4.2; UserDefaults `Normalization.storageKey`), read at each play's tap.
    /// A change applies from the next thing played: queued entries keep their level and decision.
    var normalization: Normalization {
        get { normalizationSetting }
        set {
            normalizationSetting = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Normalization.storageKey)
        }
    }

    // MARK: Debug's readings

    /// The engine's own state, as it last said (of the queue playing).
    private(set) var engineState = EngineState()
    /// The last failure in the engine's own words (D7: raw words only in Debug's "Last failure").
    private(set) var lastFailure: String?
    /// The output's name (AVAudioSession's route), for Debug's readout.
    private(set) var outputName: String?

    /// The Hi-res readout for the song playing: its file's rate and bits, and the output's rate (Phase 0's), with the
    /// output's name.
    var readout: String? {
        guard var line = conversion else { return nil }
        if let outputName { line += " (\(outputName))" }
        return line
    }

    /// The readout without the output's name - Info's Debug, whose Output row names it already.
    var conversion: String? {
        guard let entry = current, let rate = engineState.fileRate else { return nil }
        let song = song(for: entry) ?? Song(track: entry.track)
        var bits = song.bitDepth ?? headerBits[song.id]
        if bits == nil, (song.suffix ?? "").lowercased() == "flac", let header = files.header(of: song),
           let info = FLACStreamInfo.parse(header) {
            bits = info.bitsPerSample
            headerBits[song.id] = info.bitsPerSample
        }
        let output = engineState.outputRate ?? session.outputRate
        return RateWords.readout(fileRate: rate, bits: bits, codec: song.suffix, outputRate: output)
    }

    /// The engine's phase in words, for Debug.
    var phaseWords: String {
        switch engineState.phase {
        case .idle: return "Nothing playing"
        case .loading: return "Loading"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .ended: return "Ended"
        case .failed: return "Stopped"
        }
    }

    /// The engine's lanes and clocks, for Debug; nil before anything played.
    func engineDebug() -> EngineDebug? { link?.engine.debug() }

    /// An Up Next edit made in a song's last moments is held for the join (D4), for Debug.
    var holdsAnEdit: Bool { controller?.holdsAnEdit ?? false }

    // MARK: Info's readings (D8)

    /// The song an entry was queued from - every field Navidrome gave (Info's Format, Sample rate, Bit depth): the
    /// album page's, or the one deadwax's saved queue sent back (resume).
    func song(for entry: QueueEntry) -> Song? { shelf[entry.track.id] }

    /// An album a queue came from, as its page last loaded it (the last 8 kept), for Info's album lines.
    func playedAlbum(id: String) -> Album? { albums.first { $0.id == id } }

    /// Each entry of the queue's level as decided (levels.md 4.3, LevelDecisions) - by Up Next's key; Info reads
    /// `settled(key:level:song:)`.
    private(set) var levelDecisions = LevelDecisions()

    /// An album's loudness as deadwax last answered it (GET .../loudness/album/{id}); nil until the book has asked.
    func loudness(albumID: String) -> AlbumLoudness? { loudnessAnswers[albumID] }

    // MARK: kept

    private let server: ServerModel
    private let files: SongFiles
    private let session = AudioSessionController()
    private let nowPlaying = NowPlayingController()
    private let book: LoudnessBook
    private let reporter: PlayReporter
    @ObservationIgnored private var link: PlayerEngineLink?
    @ObservationIgnored private var controller: QueueController?
    /// The queue's entries, as QueueController.entries(queue) gives them: Up Next's keys.
    private var entries: [QueueEntry] = []
    /// The songs the app has of the queue's tracks, by id (an album page's, Debug's, resume's).
    @ObservationIgnored private var shelf: [String: Song] = [:]
    @ObservationIgnored private var albums: [Album] = []
    private var loudnessAnswers: [String: AlbumLoudness] = [:]
    /// The decoded length the engine reported for the entry heard.
    private var length: Double?
    private var pendingSeek: Scrub.PendingSeek?
    private var normalizationSetting = Normalization.read(UserDefaults.standard.string(forKey: Normalization.storageKey))
    /// A song that failed to load is being asked for again (PlayerWords.retryDelaySeconds).
    private var retrying = false
    /// The song's line says iOS refused to play (sayRefusal): words for a play that didn't happen, gone at the next.
    @ObservationIgnored private var refusalSaid = false
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var interrupted = false
    @ObservationIgnored private var artwork: (id: String, image: UIImage)?
    @ObservationIgnored private var coverAsked: String?
    /// The lock screen's cover that last failed, and when: not asked again for `coverAgainSeconds`.
    @ObservationIgnored private var coverFailed: (id: String, at: Double)?
    private static let coverAgainSeconds: Double = 15
    /// The next song's cover being fetched ahead (`coverAhead`), until the fetch lands: not asked twice at once.
    @ObservationIgnored private var coverAheadAsked: String?
    @ObservationIgnored private var headerBits: [String: Int] = [:]
    @ObservationIgnored private var noticeShown = 0
    @ObservationIgnored private var skipShown = 0
    /// The entry heard as the model last followed it: the engine's key (unique across queues), nil for none.
    @ObservationIgnored private var heardEntry: Int?
    @ObservationIgnored private var heardLength: Double = 0
    /// Inside an action of the listener's: a song change in it starts a new listen; outside, the engine ran on by
    /// itself (a join).
    @ObservationIgnored private var acting = false
    /// Where a queue put back starts its listen.
    @ObservationIgnored private var listenFrom: Double = 0
    /// The song heard was asked for again already (afterFailure's `retried`) - false at every song change.
    @ObservationIgnored private var retried = false
    @ObservationIgnored private var retryWork: DispatchWorkItem?
    /// A failure asks who is signed in once per song, not at each of its re-publishes.
    @ObservationIgnored private var askedAfterFailure = false
    /// iOS refused the session in the action just made: said once the action's song change is drawn.
    @ObservationIgnored private var refusedNow = false
    @ObservationIgnored private var levelsShown: LevelStore?
    // resume
    @ObservationIgnored private var resuming: ResumeController?
    @ObservationIgnored private var resumeFor: Int?
    @ObservationIgnored private var sessionSeen: String?
    @ObservationIgnored private var sessionCount = 0
    @ObservationIgnored private let resumeClock = MainQueueClock()

    init(server: ServerModel, files: SongFiles) {
        self.server = server
        self.files = files
        book = LoudnessBook(server: server)
        reporter = PlayReporter(server: server)
        book.onAnswer = { [weak self] album, answer in self?.loudnessAnswers[album] = answer }
        session.onInterruption = { [weak self] began, shouldResume in self?.interruption(began: began, shouldResume: shouldResume) }
        session.onOldDeviceGone = { [weak self] in self?.pause() }
        session.onReset = { [weak self] in self?.mediaReset() }
        nowPlaying.connect(.init(
            play: { [weak self] in self?.resume() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.toggle() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() },
            seek: { [weak self] seconds in self?.seek(to: seconds) }
        ))
        watchServer()
    }

    // MARK: playing

    /// The album page's Play, Shuffle and a song's tap: `songs` played from `index` (nil with Shuffle: anywhere),
    /// every one at QueuePickWords.playLevel(normalization) - as an album. Call it in the tap, nothing awaited first.
    /// QueueController.playTracks(tracks, start:, shuffle:) (upnext.md 6).
    func play(songs: [Song], album: Album, at index: Int?, shuffle: Bool = false) {
        let level = QueuePickWords.playLevel(normalization)
        let tracks = songs.map { QueueTrack(song: $0, albumId: album.id, albumName: album.name ?? "",
                                            albumArtist: album.artist, albumCoverArt: album.coverArt, level: level) }
        remember(album)
        shelve(songs)
        startQueue(copies: false) { $0.playTracks(tracks, start: index, shuffle: shuffle) }
    }

    /// Play Next from a ••• menu: the pick queued straight after the song playing's copies (pick.choose(.next,
    /// setting: normalization)), and the notice said when the music didn't start from it (pick.notice). True when
    /// something was queued (the menu closes). QueueController.playNext(tracks).
    @discardableResult
    func playNext(_ pick: QueuePick<Song>, album: Album) -> Bool { choose(.next, pick, album: album) }

    /// Play Last from a ••• menu: the pick queued at the end of Playing Next. QueueController.playLast.
    @discardableResult
    func playLast(_ pick: QueuePick<Song>, album: Album) -> Bool { choose(.last, pick, album: album) }

    /// Play Next or Play Last, by the choice (QueuedHow). With nothing playing - or a queue played out with nothing
    /// after it - the songs play from the first, and the mini player is the notice.
    @discardableResult
    func choose(_ choice: QueueChoice, _ pick: QueuePick<Song>, album: Album) -> Bool {
        guard let queued = pick.choose(choice, setting: normalization) else { return false }
        // no engine (iOS wouldn't make one): nothing queued, and the song's line says so
        guard ensureController() != nil else { return true }
        let tracks = queued.tracks.map { QueueTrack(song: $0, albumId: album.id, albumName: album.name ?? "",
                                                    albumArtist: album.artist, albumCoverArt: album.coverArt,
                                                    level: queued.level) }
        remember(album)
        shelve(queued.tracks)
        var started = false
        // only songs added: a song that failed keeps its retry (the web's addSongs leaves the retry's timer alone)
        startQueue(copies: false, cancelsRetry: false) { controller in
            started = choice == .next ? controller.playNext(tracks) : controller.playLast(tracks)
        }
        if started { cancelRetry() }
        if let words = pick.notice(choice, started: started) { say(words) }
        return true
    }

    /// The notice capsule says `words` for `Notice.seconds` (D11), and VoiceOver reads them.
    func say(_ words: String) {
        noticeShown += 1
        let shown = noticeShown
        notice = words
        Task {
            try? await Task.sleep(for: .seconds(Notice.seconds))
            if shown == noticeShown { notice = nil }
        }
    }

    /// Play/Pause.
    func toggle() {
        if isPlaying { pause() } else { resume() }
    }

    /// Play: the song from where it paused (a queue put back: from where it was left); after the queue ended, the
    /// entry shown again from its start; after a failure, from where it stopped.
    func resume() {
        guard let controller, let link, hasQueue else { return }
        follow()
        cancelRetry()
        switch engineState.phase {
        case .ended:
            if let heardEntry, let track = current?.track { reporter.newListen(entry: heardEntry, songID: track.id) }
        case .failed:
            // from where it stopped: the same listen, and who is signed in asked again should it fail again - and
            // its words gone, as the web's reload() clears them: the song is being asked for again
            reporter.seeked()
            askedAfterFailure = false
            errorLine = nil
        default:
            break
        }
        if refusalSaid {
            refusalSaid = false
            errorLine = nil
        }
        controller.intendsToPlay = true
        link.resume()
        sayRefusal()
        startTicking()
        observeResume()
    }

    /// Pause: the output off at once (iOS counts a running one as playing); play goes on from the sample heard.
    func pause() {
        guard let link else { return }
        cancelRetry()
        tick()
        controller?.intendsToPlay = false
        link.engine.pause()
        observeResume()
    }

    /// Next: past Repeat One's copies to the next song (a held edit made first). Playing or paused as it was.
    func next() {
        guard let controller else { return }
        cancelRetry()
        act { controller.next() }
        startTicking()
    }

    /// Previous: the song again from its start after `UpNext.restartAfterSeconds`, else the entry before the run of
    /// Repeat One's copies it is part of. Playing or paused as it was.
    func previous() {
        guard let controller, let link else { return }
        cancelRetry()
        follow()
        if case .restart = backward(queue, position: link.heard()?.seconds ?? 0) {
            // the same entry from its start: a new listen, and the thumb held at 0 until the engine lands there
            pendingSeek = Scrub.PendingSeek(target: 0, since: Self.nowMs())
            if let heardEntry, let track = current?.track { reporter.newListen(entry: heardEntry, songID: track.id) }
            resuming?.position(0)
        }
        act { controller.previous() }
        startTicking()
        // paused, no tick follows: the clock read back now, so it shows the restart once the hold lets go
        tick()
        showNowPlaying()
    }

    /// The scrubber let go, or the lock screen's: `seconds` into the entry heard. The thumb holds there until the
    /// engine reports it landed (Scrub.PendingSeek, Scrub.settled).
    func seek(to seconds: Double) {
        guard let link, hasQueue else { return }
        follow()
        pendingSeek = Scrub.PendingSeek(target: seconds, since: Self.nowMs())
        reporter.seeked()
        link.seek(to: seconds)
        resuming?.position(seconds)
        // paused, the ticker is stopped and the engine says nothing of a seek: the position read back now (the
        // engine answers the seek's target), so the clock keeps it once Scrub's hold has let go
        tick()
        showNowPlaying()
    }

    /// Repeat's button: off -> all -> one (Repeat.allCases), kept on the device, the queue fitted to it
    /// (QueueController.setRepeat: one's copies queued ahead). In a song's last ~2.5 s the change is made after the
    /// join (D4): Repeat One turned on there repeats the NEXT song.
    func setRepeat(_ mode: Repeat) {
        guard let controller else {
            repeatChanged(mode)
            return
        }
        act { controller.setRepeat(mode) }
    }

    /// Shuffle's button mid-queue: QueueController.setShuffle(!shuffle).
    func toggleShuffle() {
        guard let controller else { return }
        act { controller.setShuffle(!controller.shuffle) }
    }

    /// An Up Next or History row tapped: that entry played from its start, paused or not (QueueController.jumpTo(key:))
    /// - in a song's last moments too: a skip, or, when the edit it needs can't be made then, the queue played afresh
    /// from the row. (2.1.3) The songs it passes stay behind it;
    /// History's plays its song again. True when the jump was made: the screen says what started only then.
    @discardableResult
    func jump(to key: Int) -> Bool {
        guard let controller else { return false }
        cancelRetry()
        var took = false
        act { took = controller.jumpTo(key: key) }
        startTicking()
        return took
    }

    /// An Up Next row dragged to `index` of its own group (QueueController.moveInQueue(key:to:)).
    func move(key: Int, to index: Int) {
        guard let controller else { return }
        act { controller.moveInQueue(key: key, to: index) }
    }

    /// An Up Next row removed (QueueController.removeFromQueue(key:)).
    func remove(key: Int) {
        guard let controller else { return }
        act { controller.removeFromQueue(key: key) }
    }

    /// Up Next's Clear on Playing Next (QueueController.clearPlayingNext()).
    func clearPlayingNext() {
        guard let controller else { return }
        act { controller.clearPlayingNext() }
    }

    /// Stops and forgets the queue: the mini player goes.
    func stop() {
        cancelRetry()
        reporter.stop()
        link?.stop()
        controller = nil
        files.keep([], ahead: [])
        nowPlaying.clear()
        stopTicking()
        queue = .empty
        entries = []
        heardEntry = nil
        coverAheadAsked = nil
        position = 0
        length = nil
        pendingSeek = nil
        errorLine = nil
        refusalSaid = false
        levelDecisions = LevelDecisions()
        levelsShown = link?.levels
        book.wantQueue([])
        observeResume()
    }

    /// The person changed (ServerModel.whenPersonChanges): everything of theirs let go - resume first, so the stop
    /// saves nothing over their queue.
    func reset() {
        resuming?.stop()
        resuming = nil
        resumeFor = nil
        stop()
        albums = []
        shelf = [:]
        book.reset()
        loudnessAnswers = [:]
        noticeShown += 1
        notice = nil
        lastFailure = nil
        engineState = EngineState()
    }

    /// The album page showed `album` with its songs: kept for Info, and - when Normalization will level them
    /// (AlbumPageLines.warms) - its loudness asked for and its levels warmed (the LoudnessBook).
    func albumShown(_ album: Album) {
        remember(album)
        guard AlbumPageLines.warms(normalization, songs: album.song) else { return }
        book.wantPage(album.id)
    }

    /// The album page found its album gone (404): nothing kept of it.
    func albumGone(id: String) {
        albums.removeAll { $0.id == id }
        book.leavePage(id)
    }

    /// The album page went: its loudness no longer wanted for it (the queue may still want it).
    func albumLeft(id: String) {
        book.leavePage(id)
    }

    /// The app came to the front: the position read again, and resume's look for what another device played.
    func becameActive() {
        tick()
        resuming?.foreground()
    }

    /// The app went to the back: what resume has due is saved at once.
    func movedToBackground() {
        tick()
        resuming?.background()
    }

    /// Debug's test songs and hi-res row: `songs` played from `index` as they are (no album; Off), their downloaded
    /// copies when `copies` (a song with none is streamed).
    func playTest(_ songs: [Song], at index: Int, copies: Bool) {
        let tracks = songs.map { QueueTrack(song: $0, albumId: $0.albumId ?? "", albumName: $0.album ?? "") }
        shelve(songs)
        startQueue(copies: copies) { $0.playTracks(tracks, start: index) }
    }

    // MARK: the controller

    /// A play that may start a new queue: a new generation of engine keys and of level decisions, from its first play
    /// or restore. Made in the tap: nothing awaited. A failed song's retry is called off first, unless `cancelsRetry`
    /// is false (Play Next and Play Last, which may only add songs). The songs kept for the queue are pruned only when
    /// a new queue did start: songs added by an edit held for the join (D4) are not in the queue yet, and keep their
    /// Navidrome song (its size, for the stream cache's length check; Info's fields) for when they are.
    private func startQueue(copies: Bool, cancelsRetry: Bool = true, _ body: (QueueController) -> Void) {
        guard let controller = ensureController(), let link else { return }
        if cancelsRetry { cancelRetry() }
        let generation = link.generation
        link.beginStart(copies: copies)
        act { body(controller) }
        link.endStart()
        if link.generation != generation { pruneShelf() }
        startTicking()
    }

    /// An action of the listener's on the controller: the queue caught up with the engine first (a join it hasn't
    /// seen is a join), then the action - whose song change is a new listen.
    private func act(_ body: () -> Void) {
        follow()
        acting = true
        body()
        acting = false
        sayRefusal()
    }

    /// The queue caught up with what the engine is playing.
    private func follow() {
        guard let controller, !acting else { return }
        controller.catchUp()
    }

    private func ensureController() -> QueueController? {
        if let controller { return controller }
        guard let link = ensureLink() else { return nil }
        let made = QueueController(engine: link, repeat: repeatMode)
        made.onChange = { [weak self] next in MainActor.assumeIsolated { self?.queueChanged(next) } }
        made.onRepeatChange = { [weak self] mode in MainActor.assumeIsolated { self?.repeatChanged(mode) } }
        controller = made
        return made
    }

    private func ensureLink() -> PlayerEngineLink? {
        if let link { return link }
        do {
            let engine = try PlaybackEngine()
            Self.lead(engine)
            EngineTrace.attach(engine)
            engine.onChange = { [weak self] state in
                MainActor.assumeIsolated { self?.engineChanged(state) }
            }
            let made = PlayerEngineLink(engine: engine, files: files, shelf: book.shelf, decided: Self.decidedHook(self))
            made.size = { [weak self] id in MainActor.assumeIsolated { self?.shelf[id]?.size } }
            made.activate = { [weak self] in MainActor.assumeIsolated { self?.activateSession() ?? false } }
            made.refused = { [weak self] in MainActor.assumeIsolated { self?.refusedNow = true } }
            made.clientBox.client = server.client
            link = made
            return made
        } catch {
            errorLine = ErrorWords.other
            lastFailure = "iOS couldn't make the audio engine: \(error.localizedDescription)"
            return nil
        }
    }

    /// The engine's three readings of the output, from AVAudioSession - made outside the main actor, as the engine
    /// reads them on its own queue.
    nonisolated static func lead(_ engine: PlaybackEngine) {
        engine.startLead = { AudioSessionController.startLead() }
        engine.latency = { AudioSessionController.latency() }
        engine.ioBuffer = { AudioSessionController.ioBuffer() }
    }

    /// A level decided on the engine's queue, drawn on the main one - made outside the main actor for the same reason.
    nonisolated static func decidedHook(_ model: PlayerModel) -> @Sendable (LevelStore, LevelDecisions) -> Void {
        { [weak model] store, made in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { model?.levelsDecided(store, made) }
            }
        }
    }

    private func levelsDecided(_ store: LevelStore, _ made: LevelDecisions) {
        guard link?.levels === store else { return }
        levelDecisions = made
    }

    private func repeatChanged(_ mode: Repeat) {
        repeatMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Repeat.storageKey)
    }

    // MARK: following the queue and the engine

    /// The queue changed (QueueController.onChange): drawn, the song change handled, the albums it needs asked about,
    /// the cache kept and the next song fetched, resume told, the lock screen set.
    private func queueChanged(_ next: UpNextQueue) {
        guard let link else { return }
        queue = next
        entries = QueueController.entries(next)
        if levelsShown !== link.levels {
            levelsShown = link.levels
            levelDecisions = link.levels.snapshot
        }
        let entry = current.map { link.engineKey($0.key) }
        if entry != heardEntry { songChanged(to: entry) }
        book.wantQueue(LoudnessAsking.wanted(next.tracks, playing: next.index))
        keepAndPrefetch()
        observeResume()
        showNowPlaying()
    }

    /// Another entry is heard: its words and its retry start afresh (usePlayer.ts at every load and join), and its
    /// listen begins - a new one when the listener moved, the old song's rest counted to it when the engine ran on.
    private func songChanged(to entry: Int?) {
        let old = heardEntry
        let oldLength = length ?? heardLength
        heardEntry = entry
        heardLength = current?.track.duration ?? 0
        length = nil
        pendingSeek = nil
        position = listenFrom
        errorLine = nil
        refusalSaid = false
        retried = false
        askedAfterFailure = false
        cancelRetry()
        guard let entry, let track = current?.track else {
            reporter.stop()
            return
        }
        if acting || old == nil {
            reporter.newListen(entry: entry, songID: track.id, from: listenFrom)
        } else if case .failed = engineState.phase, engineState.key == entry {
            // the next song failed while the one before played (the engine says so at its end): the one before
            // counted to its end, and the failed one's listen never begins - it was never heard
            reporter.tick(position: oldLength, duration: oldLength)
            reporter.newListen(entry: entry, songID: track.id)
        } else {
            let at = link?.position()
            let heard = at.map { $0.key == entry ? $0.seconds : 0 } ?? 0
            position = heard
            reporter.join(entry: entry, songID: track.id, oldLength: oldLength, newPosition: heard,
                          newDuration: track.duration)
        }
    }

    /// The engine said something changed. A state of another queue's generation (still on its way from before a new
    /// play or a stop) is dropped.
    private func engineChanged(_ state: EngineState) {
        guard let link else { return }
        if let key = state.key {
            guard link.isCurrent(key) else { return }
        } else if hasQueue {
            return
        }
        let was = engineState
        engineState = state
        outputName = session.outputName
        follow()
        switch state.phase {
        case .playing:
            retrying = false
            if let key = state.key { reporter.began(entry: key) }
        case .ended where was.phase != .ended:
            // the queue played out: the listen counted to its end, then Repeat's next time round, or the music stops
            tick()
            act { _ = controller?.queueEnded() }
        case .failed(let words) where state.failures != was.failures:
            // a new failure (EngineState.failures counts each) - the same words again included: a retry that met the
            // same failure is what lets afterFailure skip the song. A failure said again (a new route) is not new.
            failed(state, words: words)
        default:
            break
        }
        if isPlaying { startTicking() }
        tick()
        keepAndPrefetch()
        observeResume()
        showNowPlaying()
    }

    /// A song that won't play (D7): its raw words to Debug, who is signed in asked again (a stream's 401 brings the
    /// sign-in), and then PlayerWords.afterEngineFailure - asked for again once after 1.5 s, passed over to the next
    /// song (its notice where the artist goes, for 5 s), or the queue stopped at it with the words.
    private func failed(_ state: EngineState, words: String) {
        lastFailure = words
        guard let controller, let key = state.key, key == heardEntry else { return }
        if !askedAfterFailure {
            askedAfterFailure = true
            Task { await server.refreshMe() }
        }
        let failure = PlayerWords.Failure(rawValue: state.failure?.kind.rawValue ?? "") ?? .other
        switch PlayerWords.afterEngineFailure(failure, intendsToPlay: controller.intendsToPlay, retried: retried) {
        case .retry:
            retried = true
            errorLine = PlayerWords.words(failure)
            retrying = true
            scheduleRetry(of: key)
        case .skip:
            let title = current?.track.title
            var skippedTo: Int?
            act { skippedTo = controller.skipFailed() }
            if skippedTo != nil {
                showSkipped(PlayerWords.skipped(title: title?.isEmpty == false ? title : nil, failure: failure))
            } else {
                errorLine = PlayerWords.words(failure)
            }
        case .stop:
            controller.intendsToPlay = false
            errorLine = PlayerWords.words(failure)
        }
    }

    /// The song asked for again from where it stopped, after the retry's delay - the same listen - unless the
    /// listener moved or paused meanwhile.
    private func scheduleRetry(of key: Int) {
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.retryWork = nil
                guard self.retrying else { return }
                self.retrying = false
                guard self.heardEntry == key, self.controller?.intendsToPlay == true, let link = self.link else { return }
                self.reporter.seeked()
                // asked for again: its words go (the web's reload()); failing again says so again
                self.errorLine = nil
                link.resume()
                self.sayRefusal()
                self.startTicking()
            }
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PlayerWords.retryDelaySeconds, execute: work)
    }

    private func cancelRetry() {
        retryWork?.cancel()
        retryWork = nil
        retrying = false
    }

    /// A skipped song's words in the next song's second line, for PlayerWords.skipNoticeSeconds - cleared only if
    /// they are still what it says.
    private func showSkipped(_ words: String) {
        skipShown += 1
        let shown = skipShown
        errorLine = words
        Task {
            try? await Task.sleep(for: .seconds(PlayerWords.skipNoticeSeconds))
            if shown == skipShown, errorLine == words { errorLine = nil }
        }
    }

    // MARK: the session

    private func activateSession() -> Bool {
        do {
            try session.activate()
            return true
        } catch {
            lastFailure = "iOS wouldn't let the app play: \(error.localizedDescription)"
            return false
        }
    }

    /// iOS refused the session in the action just made: nothing plays, and the song says so.
    private func sayRefusal() {
        guard refusedNow else { return }
        refusedNow = false
        controller?.intendsToPlay = false
        errorLine = ErrorWords.other
        refusalSaid = true
    }

    /// iOS reset its media services: the session made active again when something was playing, then the engine
    /// makes itself again and goes on from the frame heard.
    private func mediaReset() {
        if isPlaying { _ = activateSession() }
        link?.engine.rebuild()
    }

    private func interruption(began: Bool, shouldResume: Bool) {
        if began {
            // a song waiting its retry was meant to play too: the call ended, it is asked for again
            interrupted = isPlaying || retrying
            pause()
        } else if shouldResume, interrupted {
            interrupted = false
            resume()
        }
    }

    // MARK: the cache, the ticker, the lock screen

    /// The song heard and the next kept in the cache (StreamCache.kept), and - while the music is meant to play -
    /// the next song's bytes begun, so the join stays seamless. A queue put back loads nothing.
    private func keepAndPrefetch() {
        guard let link else { return }
        let queued = entries.map { engineSong($0.track) }
        guard queued.indices.contains(queue.index) else { return }
        let (inUse, ahead) = StreamCache.kept(queued, shown: queue.index, engineAt: link.position()?.index)
        files.keep(inUse, ahead: ahead)
        guard controller?.intendsToPlay == true, !link.copies, let client = server.client, let next = nextIndex(queue),
              queued.indices.contains(next) else { return }
        files.prefetch(queued[next], client: client)
    }

    /// The song the engine plays for a track: the entry's own, with Navidrome's size when the app has it.
    private func engineSong(_ track: QueueTrack) -> Song {
        Song(track: track, size: shelf[track.id]?.size)
    }

    /// The ticker runs in the run loop's common modes: a scheduledTimer's default mode doesn't fire while a list is
    /// being scrolled, which would freeze the hairline, Repeat's top-up, a held edit and resume's reports meanwhile.
    private func startTicking() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    /// Twice a second while playing: the queue caught up, the position read, the listen counted, Repeat's top-up
    /// and a held edit given their chance, and resume told where it is.
    private func tick() {
        guard let link else { return }
        follow()
        if let at = link.position(), let entry = current, at.key == link.engineKey(entry.key) {
            position = at.seconds
            length = at.length
            pendingSeek = Scrub.settled(pendingSeek, position: at.seconds, now: Self.nowMs())
        }
        if engineState.phase == .playing {
            reporter.tick(position: position, duration: duration)
            controller?.tick(heard: reporter.heard, length: length)
            resuming?.position(position)
        }
        if !isPlaying { stopTicking() }
    }

    /// Seconds into the entry heard as the engine says it now (a queue put back: its parked second).
    private func heardSeconds() -> Double {
        link?.position()?.seconds ?? position
    }

    /// The lock screen and Control Center: the entry heard, its cover drawn at once when the cover cache holds it - the
    /// next song's is fetched there ahead, while this one plays (`coverAhead`) - else fetched now and drawn when it
    /// comes. The lock screen's cover is CoverSize.lockScreen, the size Now Playing's own is asked at, so the two share
    /// one fetch. The next song's cover is asked for only once this one's is drawn, has none, or failed: at a change
    /// neither is kept, the two fetches don't share the network.
    private func showNowPlaying() {
        guard let entry = current else { return }
        let track = entry.track
        let cover = track.coverArt
        if let cover, artwork?.id != cover, let client = server.client,
           let kept = CoverCache.shared.cached(client: client, id: cover, size: CoverSize.lockScreen) {
            artwork = (cover, kept)
            coverAsked = nil
            coverFailed = nil
        }
        nowPlaying.show(title: track.title.isEmpty ? track.id : track.title,
                        artist: track.artist.isEmpty ? nil : track.artist,
                        album: track.album.isEmpty ? nil : track.album,
                        duration: duration > 0 ? duration : nil,
                        elapsed: shownPosition, playing: engineState.phase == .playing,
                        artwork: cover != nil && artwork?.id == cover ? artwork?.image : nil)
        let now = Monotonic.seconds()
        let failedLately = coverFailed.map { $0.id == cover && now - $0.at < Self.coverAgainSeconds } ?? false
        if let cover, artwork?.id != cover, coverAsked != cover, !failedLately, let client = server.client {
            coverAsked = cover
            Task {
                // againAfter 0: the lock screen's own failure rule is coverFailed's 15 s, counted from its own
                // failure - a fetch ahead that failed just before the change doesn't hold this one back
                let image = await CoverCache.shared.load(client: client, id: cover, size: CoverSize.lockScreen,
                                                         againAfter: 0)
                // only the newest answer draws: a cover asked for a song left since is dropped
                guard self.coverAsked == cover else { return }
                guard let image else {
                    // failed: asked again at the lock screen's next change (a song, a pause, a seek) once
                    // coverAgainSeconds have gone by; the next song's is asked for all the same
                    self.coverAsked = nil
                    self.coverFailed = (cover, Monotonic.seconds())
                    self.coverAhead()
                    return
                }
                self.coverFailed = nil
                self.artwork = (cover, image)
                self.showNowPlaying()
            }
        }
        // this song's cover on its way: the next one's waits for it (its landing calls this again)
        let drawing = cover != nil && artwork?.id != cover && coverAsked == cover
        if !drawing { coverAhead() }
    }

    /// The next song's cover, fetched into the cover cache while this one plays - one ahead, at the lock screen's size -
    /// so the change sets the lock screen's artwork at once rather than a moment after (James's check of 0.2 (2)).
    /// Nothing when it is this song's cover too (the album's songs mostly share one), when the cache has it, while
    /// its fetch is out, or while the player isn't meaning to play (a queue put back, paused). Asked again whenever it
    /// isn't kept: the cache may have let it go since (a Repeat All coming round to it), and a fetch that failed is
    /// held back by the cache's own minute (CoverCache.againAfter), not for good. The fetch is the cache's, shared with
    /// any view showing the cover, kept within its cost limit (a 1024 px cover is 4 MB of its 96), and never called
    /// off: it is the next song's whichever screen is shown.
    private func coverAhead() {
        guard controller?.intendsToPlay == true, let client = server.client, let next = nextIndex(queue),
              entries.indices.contains(next), let cover = entries[next].track.coverArt, !cover.isEmpty,
              cover != current?.track.coverArt, cover != coverAheadAsked,
              CoverCache.shared.cached(client: client, id: cover, size: CoverSize.lockScreen) == nil else { return }
        coverAheadAsked = cover
        Task {
            _ = await CoverCache.shared.load(client: client, id: cover, size: CoverSize.lockScreen)
            // landed, kept or failed: a later look asks again only if it isn't kept (and the cache's minute is up)
            if self.coverAheadAsked == cover { self.coverAheadAsked = nil }
        }
    }

    // MARK: resume

    /// Who is signed in, watched: the engine's opens ask through the client in hand, and resume is made for each
    /// person once /me has answered.
    private func watchServer() {
        withObservationTracking {
            _ = server.launch
            _ = server.me
            _ = server.person
            _ = server.client
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.serverChanged()
                    self?.watchServer()
                }
            }
        }
    }

    private func serverChanged() {
        link?.clientBox.client = server.client
        guard server.launch == .ready, server.me != nil, resumeFor != server.person else { return }
        resuming?.stop()
        let player = ResumePlayerLink(
            position: { [weak self] in MainActor.assumeIsolated { self?.heardSeconds() ?? 0 } },
            restore: { [weak self] queue, position in MainActor.assumeIsolated { self?.putBack(queue, position: position) } }
        )
        let routes = ResumeRoutes(
            client: { [weak self] in self?.server.client },
            shelve: { [weak self] songs in self?.shelve(songs) }
        )
        let made = ResumeController(
            device: Self.deviceID(), label: Resume.label, player: player, server: routes, clock: resumeClock,
            session: { [weak self] in MainActor.assumeIsolated { self?.sessionGeneration() ?? 0 } },
            normalization: { [weak self] in MainActor.assumeIsolated { self?.normalization ?? .default } },
            say: { [weak self] words in MainActor.assumeIsolated { self?.say(words) } }
        )
        resuming = made
        resumeFor = server.person
        made.observe(queue: queue, playing: isPlaying)
        made.start()
    }

    /// The queue resume put back (its one action): paused at `position` seconds into its song, nothing loaded or
    /// fetched, fitted to this device's Repeat - a new queue, its listen from where it was left.
    private func putBack(_ saved: UpNextQueue, position at: Double) -> UpNextQueue? {
        guard let controller = ensureController(), let link else { return nil }
        link.beginStart(copies: false)
        listenFrom = at
        var made: UpNextQueue?
        act { made = controller.restoreQueue(saved, position: at) }
        listenFrom = 0
        link.endStart()
        if made != nil { pruneShelf() }
        return made
    }

    private func observeResume() {
        resuming?.observe(queue: queue, playing: isPlaying)
    }

    /// The sign-in's generation, as resume reads it: +1 each time the session in hand changes.
    private func sessionGeneration() -> Int {
        let now = server.client?.session
        if now != sessionSeen {
            sessionSeen = now
            sessionCount += 1
        }
        return sessionCount
    }

    /// This phone's id in deadwax's record of the queue (DeviceID), made once and kept.
    private static func deviceID() -> String {
        let read = DeviceID.read(UserDefaults.standard.string(forKey: DeviceID.storageKey))
        if read.isNew { UserDefaults.standard.set(read.id, forKey: DeviceID.storageKey) }
        return read.id
    }

    // MARK: kept for Info

    private func remember(_ album: Album) {
        albums.removeAll { $0.id == album.id }
        albums.insert(album, at: 0)
        if albums.count > 8 { albums.removeLast(albums.count - 8) }
    }

    private func shelve(_ songs: [Song]) {
        for song in songs { shelf[song.id] = song }
    }

    /// Only the songs of the queue kept, once a new one is made.
    private func pruneShelf() {
        let ids = Set(queue.tracks.map(\.id))
        shelf = shelf.filter { ids.contains($0.key) }
    }

    private static func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }
}
