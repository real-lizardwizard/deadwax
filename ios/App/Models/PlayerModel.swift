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
    /// The song is loading (the spinner over Play/Pause): its bytes, its level's wait, or the retry's 1.5 s - never the
    /// few milliseconds the engine takes to begin its lanes again for the speed (SpeedRestartHold).
    var isLoading: Bool { retrying || (engineState.phase == .loading && !speedHold.hiding) }
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

    /// The speed (notes/ios-specs/turntable.md 5): 0.25x to 2x, the pitch moving with it - a record deck's - kept on
    /// this phone under the web's key. The fader on the turntable, its readout, the cover's chip and the ••• menu's
    /// line set it; at 1x the engine plays the song's own samples.
    var speed: Double { speedControl.speed }

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

    /// The EQ (eq.md, slice 3): given the engine as it is made (`ensureLink`), so its start puts the output's curve in
    /// and its changes reach the unit. Debug's Muffle and the unit's rows are EQModel's since slice 3.
    @ObservationIgnored var eq: EQModel?

    // MARK: Info's readings (D8)

    /// The song an entry was queued from - every field Navidrome gave (Info's Format, Sample rate, Bit depth): the
    /// album page's, or the one deadwax's saved queue sent back (resume).
    func song(for entry: QueueEntry) -> Song? { shelf[entry.track.id] }

    /// Now Playing's Download Up Next (phase2-downloads.md 4.1): the songs from the one playing to the queue's end, as
    /// the app has them (an album page's, resume's) - else as their entries say.
    var songsFromCurrent: [Song] {
        guard entries.indices.contains(queue.index) else { return [] }
        return entries[queue.index...].map { shelf[$0.track.id] ?? Song(queued: $0.track) }
    }

    /// An album a queue came from, as its page last loaded it - or, for a playlist's songs, the stub made from them
    /// (PlaylistPlay.albums) - for Info's album lines, Go to album and the turntable. Kept as the web keeps them
    /// (PlayedAlbums: the last 8, or every album of a playlist up to 64), and every album the queue names kept while it
    /// names it (`keeping`).
    func playedAlbum(id: String) -> Album? { played.get(id) }

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
    /// The engine, for the turntable's `deck.position` queue to read (turntable.md 3.4, 2.6): its position and its
    /// last start, read-only - nothing of the player is changed through it.
    var engineForDeck: DeckEngineReading? { link?.engine }
    @ObservationIgnored private var controller: QueueController?
    /// The queue's entries, as QueueController.entries(queue) gives them: Up Next's keys.
    private var entries: [QueueEntry] = []
    /// The songs the app has of the queue's tracks, by id (an album page's, Debug's, resume's).
    @ObservationIgnored private var shelf: [String: Song] = [:]
    /// The album answers the queue's songs were played from (lib/playedAlbums.ts, ported - phase4-library.md 2.3).
    @ObservationIgnored private var played = PlayedAlbums<Album>()
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
    // Phase 2's downloads and offline (connect)
    @ObservationIgnored private weak var downloads: DownloadModel?
    /// (app 0.8) Play history: each song begun recorded there, each play counted marked (DeadwaxApp sets it).
    @ObservationIgnored weak var history: HistoryModel?
    @ObservationIgnored private weak var reachability: Reachability?
    /// The skips of songs not on this phone, counted for their notice.
    @ObservationIgnored private var skipRun = OfflinePlay.SkipRun()
    /// The Up Next entry the listener tapped: offline, a song not here is stopped on, never passed over.
    @ObservationIgnored private var chosenKey: Int?
    /// (Phase 4, slice 3b) The library's shuffle's feed (useShuffleFeed.ts): Core's ShuffleFeedLoop - when it looks, what
    /// each answer does to the queue, what a stop lets go - its asks made here, and its retry's timer.
    @ObservationIgnored private let feed = ShuffleFeedLoop()
    @ObservationIgnored private var feedRetry: Task<Void, Never>?

    /// The speed, and what the engine was told (Core's SpeedControl: exact again at 1x on a let-go).
    private var speedControl = SpeedControl(speed: PlaySpeed.read(UserDefaults.standard.string(forKey: PlaySpeed.storageKey)))
    /// The engine's `.loading` while it begins its lanes again for the speed, shown as playing.
    private var speedHold = SpeedRestartHold()
    /// The lock screen told a drag's speed four times a second at most.
    @ObservationIgnored private var speedPublishing = SpeedPublishing()
    /// The song's own pace, measured for Debug (playSpeed.ts paceStep): steps of song against the clock, from a tick
    /// that followed another while playing the same entry, with no seek or speed change between.
    @ObservationIgnored private var pace: [PlaySpeed.PaceSample] = []
    @ObservationIgnored private var paceFrom: (entry: Int, position: Double, at: Double)?

    init(server: ServerModel, files: SongFiles) {
        self.server = server
        self.files = files
        book = LoudnessBook(server: server)
        reporter = PlayReporter(server: server)
        reporter.speedChanged(speedControl.speed)
        reporter.onStart = { [weak self] entry, at in self?.started(entry: entry, at: at) }
        reporter.onCounted = { [weak self] songID, at in self?.history?.counted(songID: songID, at: at) }
        book.onAnswer = { [weak self] album, answer in self?.loudnessAnswers[album] = answer }
        session.onInterruption = { [weak self] began, shouldResume in self?.interruption(began: began, shouldResume: shouldResume) }
        session.onOldDeviceGone = { [weak self] in self?.pause() }
        session.onReset = { [weak self] in self?.mediaReset() }
        feed.send = { [weak self] (ask: FeedAsk) -> Void in self?.feedSend(ask) }
        feed.adding = { [weak self] (songs: [Song]) -> Void in self?.shelve(songs) }
        feed.say = { [weak self] (words: String) -> Void in self?.say(words) }
        feed.retry = { [weak self] (on: Bool) -> Void in self?.feedRetryTimer(on) }
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
        played.remember(album)
        shelve(songs)
        startQueue { $0.playTracks(tracks, start: index, shuffle: shuffle) }
    }

    /// A playlist's Play, Shuffle and a song's tap (phase4-library.md 2.3, PlaylistPage.tsx `play`): `songs` played from
    /// `index` (nil with Shuffle: anywhere), each with its own album, at the songs level - and the albums they are on
    /// remembered first (PlaylistPlay.plan: stubs, an album held whole kept as it is), every one of them. Call it in the
    /// tap, nothing awaited first.
    func play(playlist songs: [Song], at index: Int?, shuffle: Bool = false) {
        guard !songs.isEmpty else { return }
        let plan = PlaylistPlay.plan(songs, setting: normalization) { [played] (id: String) -> Album? in played.get(id) }
        // every album the new queue names kept while it does (PlayedAlbums' `keeping`), past the 64 too
        played.rememberQueue(plan.albums, keeping: QueueAlbums.named(plan.tracks))
        shelve(songs)
        startQueue { $0.playTracks(plan.tracks, start: index, shuffle: shuffle) }
    }

    /// (Phase 4, slice 4) An artist's Play and Shuffle (phase4-library.md 2.6, ArtistPage.tsx `play`): every song of
    /// `albums` - each album as its answer has it, in the page's order - Play from the first at the album level, Shuffle
    /// every song once, anywhere, at the songs level (ArtistPlay.plan); every album remembered as the queue's. Call it in
    /// the tap with the songs in hand, nothing awaited first.
    func play(artist albums: [Album], shuffle: Bool) {
        guard let plan = ArtistPlay.plan(albums, shuffle: shuffle, setting: normalization) else { return }
        played.rememberQueue(plan.albums, keeping: QueueAlbums.named(plan.tracks))
        shelve(albums.flatMap { (album: Album) -> [Song] in album.song ?? [] })
        startQueue { $0.playTracks(plan.tracks, start: plan.start, shuffle: shuffle) }
    }

    /// (Phase 4, slice 3b) The Library's Shuffle - the •••'s tap, the pull's release (phase4-library.md 2.8;
    /// ShuffleSongs.tsx's tap): the first page asked ahead, played from its first song as a library's shuffle (`paged`:
    /// the order's token and total, the songs fetched, the scope, the level the first song got) - the feed brings in the
    /// rest as it plays. Its songs are shelved for Info and the stream cache, as resume's are; no album is remembered
    /// (each track names its own, and Info asks). Call it in the tap, nothing awaited first.
    func play(shuffled taken: ShuffleAhead.Taken) {
        guard !taken.tracks.isEmpty else { return }
        shelve(taken.songs)
        startQueue { $0.playTracks(taken.tracks, start: 0, shuffle: false, paged: taken.paged) }
    }

    /// Play Next from a ••• menu: the pick queued straight after the song playing's copies (pick.choose(.next,
    /// setting: normalization)), and the notice said when the music didn't start from it (pick.notice). True when
    /// something was queued (the menu closes). QueueController.playNext(tracks).
    @discardableResult
    func playNext(_ pick: QueuePick<Song>, album: Album?) -> Bool { choose(.next, pick, album: album) }

    /// Play Last from a ••• menu: the pick queued at the end of Playing Next. QueueController.playLast.
    @discardableResult
    func playLast(_ pick: QueuePick<Song>, album: Album?) -> Bool { choose(.last, pick, album: album) }

    /// Play Next or Play Last, by the choice (QueuedHow). With nothing playing - or a queue played out with nothing
    /// after it - the songs play from the first, and the mini player is the notice. `album` nil: a playlist's songs,
    /// each queued with its own album and its stub remembered beside what is held (PlaylistPlay; the web's
    /// rememberAdded) - an album's own answer held already kept as it is.
    @discardableResult
    func choose(_ choice: QueueChoice, _ pick: QueuePick<Song>, album: Album?) -> Bool {
        guard let queued = pick.choose(choice, setting: normalization) else { return false }
        // no engine (iOS wouldn't make one): nothing queued, and the song's line says so
        guard ensureController() != nil else { return true }
        let tracks: [QueueTrack]
        if let album {
            tracks = queued.tracks.map { QueueTrack(song: $0, albumId: album.id, albumName: album.name ?? "",
                                                    albumArtist: album.artist, albumCoverArt: album.coverArt,
                                                    level: queued.level) }
            played.also(album, keeping: QueueAlbums.named(entries.map(\.track) + tracks))
        } else {
            tracks = PlaylistPlay.tracks(queued.tracks, level: queued.level)
            let held = PlaylistPlay.withHeld(PlaylistPlay.albums(queued.tracks)) { [played] (id: String) -> Album? in
                played.get(id)
            }
            // the queue's albums and every one being added kept: none of them lets another go
            let keeping = QueueAlbums.named(entries.map(\.track) + tracks)
            for each in held { played.also(each, keeping: keeping) }
        }
        shelve(queued.tracks)
        var started = false
        // only songs added: a song that failed keeps its retry (the web's addSongs leaves the retry's timer alone)
        startQueue(cancelsRetry: false) { controller in
            started = choice == .next ? controller.playNext(tracks) : controller.playLast(tracks)
        }
        if started { cancelRetry() }
        if let words = pick.notice(choice, started: started) { say(words) }
        return true
    }

    /// The notice capsule says `words` for `Notice.seconds` (D11), and VoiceOver reads them - announced here, once per
    /// notice said: two capsules draw it (the tabs' and Now Playing's), and neither announces.
    func say(_ words: String) {
        noticeShown += 1
        let shown = noticeShown
        notice = words
        Notice.announce(words)
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
        paceFrom = nil
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
    /// from the row. (2.1.3) The songs it passes stay behind it; (the web's 2.1.18) History's rolls back to it - the
    /// playing point moves up to the row, everything after it to come again. True when the jump was made: the screen
    /// says what started only then.
    @discardableResult
    func jump(to key: Int) -> Bool {
        guard let controller else { return false }
        chosenKey = key
        cancelRetry()
        var took = false
        act { took = controller.jumpTo(key: key) }
        if took {
            // the entry the jump plays (Phase 2's "the song tapped", OfflinePlay.chosen), read from the queue: the row's
            // key names it, but the queue says so for every jump alike
            let played = QueueController.entries(controller.queue)
            if played.indices.contains(controller.queue.index) { chosenKey = played[controller.queue.index].key }
        }
        startTicking()
        return took
    }

    /// (the web's 2.1.18) An older row of Up Next's tapped - a song played before, above History: ROLLED BACK to,
    /// everywhere (QueueController.rollBack: the web's jumpTo with Brought rows) - it and every older row below it down
    /// to History's come into the queue ahead of History's songs, and it plays; everything played since is to come
    /// again. `rows` and `floor` as PlayHistory.brought makes them (the rows from the one tapped, their songs at the
    /// setting's level for a song; the key of the first entry Up Next drew as it was tapped). Nothing with nothing
    /// playing - an older row is a queue's. True when it plays: the screen says what started only then.
    @discardableResult
    func rollBack(_ rows: [Brought], floor: Int?) -> Bool {
        guard let controller else { return false }
        cancelRetry()
        var took = false
        act { took = controller.rollBack(rows, floor: floor) }
        if took {
            // the song tapped (Phase 2's OfflinePlay.chosen): its new entry, stopped on offline rather than passed over
            let played = QueueController.entries(controller.queue)
            if played.indices.contains(controller.queue.index) { chosenKey = played[controller.queue.index].key }
        }
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
        feed.stopped()
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
        played = PlayedAlbums()
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
        // `also` (phase4-library.md question 8), the queue's albums kept: a page shown never lets go of one still to play
        played.also(album, keeping: QueueAlbums.named(entries.map(\.track)))
        guard AlbumPageLines.warms(normalization, songs: album.song) else { return }
        book.wantPage(album.id)
    }

    /// The album page found its album gone (404): nothing kept of it.
    func albumGone(id: String) {
        played.forget(id)
        book.leavePage(id)
    }

    /// The album page went: its loudness no longer wanted for it (the queue may still want it).
    func albumLeft(id: String) {
        book.leavePage(id)
    }

    /// Phase 2's downloads wired in (DeadwaxApp, once): a play that can't be sent is kept in the person's download
    /// store; an album's loudness kept with its download is put on the shelf for a queue (marked old, so a read is still
    /// asked for first when deadwax answers); and while deadwax can't be reached, no level read is asked - each is
    /// failed at once, so a first song's wait ends and it is levelled from the answer kept (7.3).
    ///
    /// And the player offline (7.3): a song not on this phone isn't streamed while deadwax can't be reached - its open
    /// fails at once - and is passed over to the next song here, or stopped on (OfflinePlay); nothing is prefetched.
    func connect(downloads: DownloadModel, reachability: Reachability) {
        self.downloads = downloads
        self.reachability = reachability
        reachability.whenChanged { [weak self, weak reachability] in
            self?.link?.reach.online = reachability?.online ?? true
        }
        reporter.online = { [weak reachability] in reachability?.online ?? true }
        reporter.keep = { [weak downloads] songID, timeMs in downloads?.keepPlay(songID: songID, timeMs: timeMs) }
        book.reachable = { [weak reachability] in reachability?.online ?? true }
        book.kept = { [weak downloads] album in downloads?.keptLoudness(album) }
        //? resume made for whoever the launch already has: one opened from the kept /me is .ready before this model
        //? watches, and /me answering the same (or not at all, offline) changes nothing it watches. Here, not in init,
        //? so the controller reads the person's kept queue through `downloads` (7.5)
        serverChanged()
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

    /// Debug's test songs and hi-res row: `songs` played from `index` as they are (no album; Off) - from their copies
    /// downloaded to this phone, as every song is, unless Debug says to stream them.
    func playTest(_ songs: [Song], at index: Int) {
        let tracks = songs.map { QueueTrack(song: $0, albumId: $0.albumId ?? "", albumName: $0.album ?? "") }
        shelve(songs)
        startQueue { $0.playTracks(tracks, start: index) }
    }

    // MARK: the controller

    /// A play that may start a new queue: a new generation of engine keys and of level decisions, from its first play
    /// or restore. Made in the tap: nothing awaited. A failed song's retry is called off first, unless `cancelsRetry`
    /// is false (Play Next and Play Last, which may only add songs). The songs kept for the queue are pruned only when
    /// a new queue did start: songs added by an edit held for the join (D4) are not in the queue yet, and keep their
    /// Navidrome song (its size, for the stream cache's length check; Info's fields) for when they are.
    private func startQueue(cancelsRetry: Bool = true, _ body: (QueueController) -> Void) {
        guard let controller = ensureController(), let link else { return }
        if cancelsRetry { cancelRetry() }
        let generation = link.generation
        link.beginStart()
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
            // the kept speed, before any lane begins: at 1x nothing (the chain is never made)
            if let send = speedControl.atStart { engine.setSpeed(send.speed, exact: send.exact) }
            // the EQ's start: each output's curve put in before its first sample (eq.md 1.8; EQModel.startHook)
            eq?.attach(engine)
            EngineTrace.attach(engine)
            engine.onChange = { [weak self] state in
                MainActor.assumeIsolated { self?.engineChanged(state) }
            }
            let made = PlayerEngineLink(engine: engine, files: files, shelf: book.shelf, decided: Self.decidedHook(self))
            made.size = { [weak self] id in MainActor.assumeIsolated { self?.shelf[id]?.size } }
            made.activate = { [weak self] in MainActor.assumeIsolated { self?.activateSession() ?? false } }
            made.refused = { [weak self] in MainActor.assumeIsolated { self?.refusedNow = true } }
            made.clientBox.client = server.client
            made.reach.online = reachability?.online ?? true
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
        if let controller { feed.look(controller) }
    }

    // MARK: the library's shuffle's feed (Phase 4, slice 3b - phase4-library.md 2.8; useShuffleFeed.ts)

    /// The feed's ask (ShuffleFeedLoop.send): made of deadwax as the person signed in, in an unstructured task, its
    /// answer handed back to the loop with the queue's controller as it is then. It only ever adds to the queue.
    private func feedSend(_ ask: FeedAsk) {
        guard let client = server.client else {
            feed.failed(ask, into: controller)
            return
        }
        Task { [weak self] in
            switch ask.kind {
            case .page(let offset):
                do {
                    let page = try await client.shufflePage(token: ask.token, offset: offset)
                    guard let self else { return }
                    self.feed.page(ask, songs: page.songs, into: self.controller)
                } catch let failure as APIFailure where failure.status == 404 {
                    // the order gone from deadwax (it restarted, or a day untouched): a fresh one, as the rest of this round
                    guard let self else { return }
                    self.feed.gone(ask, into: self.controller)
                } catch {
                    guard let self else { return }
                    self.feed.failed(ask, into: self.controller)
                }
            case .fresh:
                do {
                    let first = try await client.shuffleStart(scope: ask.scope, claim: true)
                    guard let self else { return }
                    self.feed.fresh(ask, first, into: self.controller)
                } catch {
                    guard let self else { return }
                    self.feed.failed(ask, into: self.controller)
                }
            }
        }
    }

    /// The retry's timer (ShuffleFeedLoop.retry): started afresh, FEED_RETRY_MS long, or called off.
    private func feedRetryTimer(_ on: Bool) {
        feedRetry?.cancel()
        feedRetry = nil
        guard on else { return }
        feedRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ShuffleFeed.retrySeconds))
            guard !Task.isCancelled, let self else { return }
            self.feedRetry = nil
            self.feed.retryDue(self.hasQueue ? self.controller : nil)
        }
    }

    // MARK: the speed (notes/ios-specs/turntable.md 5)

    /// The fader moved mid-drag (DeckController, in the touch): the speed it is at now. Through 1x the engine plays on
    /// in its chain at rate 1 - no gap at the mark.
    func dragSpeed(to speed: Double) {
        apply(speedControl.dragged(to: speed))
    }

    /// The fader let go, or its touch taken by the system: at 1x after a drag, the song's own samples again (James,
    /// 2026-11-13: exact again on let-go) - one short gap.
    func speedLetGo() {
        apply(speedControl.letGo())
    }

    /// A jump: the readout's tap, the chip's, the ••• menu's line, a VoiceOver step - exact when it lands on 1x.
    func setSpeed(_ speed: Double) {
        apply(speedControl.set(speed))
    }

    /// What the player does with the speed, for Debug's Speed row (playSpeed.ts SpeedReading): the speed asked for, the
    /// engine's as it reads it back, the pitch moving with it (a varispeed's: always), the song's pace measured. Debug's
    /// alone: the engine's read waits on its queue.
    func speedReading() -> SpeedReading {
        SpeedReading(speed: speedControl.speed, rate: link?.engine.speed ?? speedControl.speed, pitch: "moves",
                     measured: PlaySpeed.paceOf(pace))
    }

    /// A send to the engine: kept on the phone, the plays told, the pace measured afresh (the web's setSpeed: a step
    /// across the change would be part old speed, part new), the restart's loading held off the screen while the song
    /// plays, and the lock screen told.
    private func apply(_ send: SpeedControl.Send?) {
        guard let send else { return }
        UserDefaults.standard.set(PlaySpeed.stored(send.speed), forKey: PlaySpeed.storageKey)
        reporter.speedChanged(send.speed)
        pace = []
        paceFrom = nil
        if let link {
            if send.restarts, engineState.phase == .playing || speedHold.hiding, let key = engineState.key {
                speedHold.asked(entry: key, at: Monotonic.seconds())
                DispatchQueue.main.asyncAfter(deadline: .now() + SpeedRestartHold.seconds) { [weak self] in
                    MainActor.assumeIsolated {
                        // a restart still loading past the hold is a real wait: it shows
                        guard let self, self.speedHold.expired(at: Monotonic.seconds()) else { return }
                        self.showNowPlaying()
                    }
                }
            }
            link.engine.setSpeed(send.speed, exact: send.exact)
        }
        speedToLockScreen()
    }

    /// The lock screen's clock runs at the speed (MPNowPlayingInfoPropertyPlaybackRate): told at once, then four times a
    /// second at most through a drag, its last speed always (SpeedPublishing) - the position read afresh each time.
    private func speedToLockScreen() {
        guard hasQueue else { return }
        switch speedPublishing.changed(at: Monotonic.seconds()) {
        case .now:
            tellLockScreenSpeed()
        case .at(let time):
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, time - Monotonic.seconds())) { [weak self] in
                MainActor.assumeIsolated { self?.tellLockScreenSpeed() }
            }
        case .waiting:
            break
        }
    }

    private func tellLockScreenSpeed() {
        guard hasQueue else { return }
        tick()
        showNowPlaying()
    }

    /// A tick's step of playing, for the pace: from the tick before, the same entry, no seek, pause or speed between.
    private func measurePace() {
        guard let entry = heardEntry else { return }
        let now = Monotonic.seconds()
        if let from = paceFrom, from.entry == entry, position >= from.position {
            pace = PlaySpeed.paceStep(pace, PlaySpeed.PaceSample(media: position - from.position, wall: now - from.at))
        }
        paceFrom = (entry, position, now)
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
        if let controller { feed.look(controller) }
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
        paceFrom = nil
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

    /// (app 0.8) A song begun - its listen's "now playing" (PlayReporter's onStart): a start in play history, of the
    /// entry heard as the queue holds it, its queue's id and its entry's key with it. Only for the entry heard: a
    /// report from another moment is let go.
    private func started(entry: Int, at: Int64) {
        guard let link, let history, let current, link.engineKey(current.key) == entry else { return }
        history.record(PlayHistory.startOf(current.track, at: at, queue: queue))
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
        speedHold.phase(loading: state.phase == .loading, playing: state.phase == .playing, entry: state.key,
                        at: Monotonic.seconds())
        if state.phase != .playing { paceFrom = nil }
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
        // a song not on this phone while deadwax can't be reached: nothing to ask, nothing to retry
        if let reachability, !reachability.online, let track = current?.track, !playsHere(track) {
            notOnPhone(controller)
            return
        }
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

    /// A song not on this phone, met while deadwax can't be reached (7.3, OfflinePlay): passed over at once to the next
    /// song here, said in the notice ("Skipped "Roads" - it isn't on this phone", a run counted) - or, with nothing here
    /// still to come or for the song tapped in Up Next, stopped on, paused, its line saying why. Play asks for it again.
    private func notOnPhone(_ controller: QueueController) {
        let chosen = current.map { $0.key == chosenKey } ?? false
        chosenKey = nil
        let here = entries.map { playsHere($0.track) }
        let after = OfflinePlay.after(intendsToPlay: controller.intendsToPlay,
                                      hereAfter: OfflinePlay.hereAfter(here, index: queue.index, repeatAll: repeatMode == .all),
                                      chosen: chosen)
        if after == .skip {
            let title = current?.track.title
            var skippedTo: Int?
            act { skippedTo = controller.skipFailed() }
            if skippedTo != nil {
                errorLine = nil
                say(skipRun.skipped(title: title, now: Monotonic.seconds()))
                return
            }
        }
        controller.intendsToPlay = false
        errorLine = DownloadWords.stoppedNotHere
    }

    /// The song plays with deadwax out of reach: downloaded to this phone, or whole in the streaming cache.
    private func playsHere(_ track: QueueTrack) -> Bool {
        files.downloads.url(for: track.id) != nil || files.cache.reusable(Song(track: track, size: shelf[track.id]?.size)) != nil
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
        // nothing fetched for a song on the phone: it plays from there - and nothing at all while deadwax can't be reached
        guard controller?.intendsToPlay == true, reachability?.online != false, let client = server.client,
              let next = nextIndex(queue),
              queued.indices.contains(next), files.downloads.url(for: queued[next].id) == nil else { return }
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
            measurePace()
            reporter.tick(position: position, duration: duration)
            controller?.tick(heard: reporter.heard, length: length)
            resuming?.position(position)
        }
        if !isPlaying { stopTicking() }
    }

    /// The lyrics' clock (notes/app-lyrics.md 2.2): seconds into the entry heard as the engine says it NOW - "how far in
    /// as heard", read from it each time rather than the ticker's half-second `position` - but only when the engine's
    /// position is the entry heard's, the tick's own check: at a join it can still be answering for the song before, so
    /// `heardSeconds()`, which checks no key, isn't used. Else `position`. A seek on its way is its target, as the
    /// scrubber's is (Scrub.reportedPosition; the tick lets it go, Scrub.settled) - a tap on a line lights it at once.
    /// A read: nothing changes.
    func clock() -> Double {
        var heard = position
        if let link, let at = link.position(), let entry = current, at.key == link.engineKey(entry.key) {
            heard = at.seconds
        }
        return Scrub.reportedPosition(pendingSeek, position: heard, now: Self.nowMs())
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
                        elapsed: shownPosition, playing: engineState.phase == .playing || speedHold.hiding,
                        rate: speedControl.speed,
                        artwork: cover != nil && artwork?.id == cover ? artwork?.image : nil)
        speedPublishing.told(at: Monotonic.seconds())
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
            restore: { [weak self] queue, position in MainActor.assumeIsolated { self?.putBack(queue, position: position) } },
            continuing: { [weak self] queue in MainActor.assumeIsolated { self?.history?.continuing(queue) } }
        )
        let routes = ResumeRoutes(
            client: { [weak self] in self?.server.client },
            shelve: { [weak self] songs in self?.shelve(songs) }
        )
        // Phase 2: the person's queue kept on this phone, in their download store (7.5, 7.6)
        let keeper: ResumeKeep? = {
            guard let address = server.address, let me = server.me else { return nil }
            return ResumeKeep(
                downloads: { [weak self] in self?.downloads }, server: address.key, person: DownloadStore.person(me),
                sizes: { [weak self] id in self?.shelf[id]?.size },
                shelve: { [weak self] songs in self?.shelve(songs) }
            )
        }()
        let made = ResumeController(
            device: Self.deviceID(), label: Resume.label, player: player, server: routes, clock: resumeClock,
            session: { [weak self] in MainActor.assumeIsolated { self?.sessionGeneration() ?? 0 } },
            normalization: { [weak self] in MainActor.assumeIsolated { self?.normalization ?? .default } },
            say: { [weak self] words in MainActor.assumeIsolated { self?.say(words) } },
            keeper: keeper
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
        link.beginStart()
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
