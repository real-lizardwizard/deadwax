import DeadwaxAudio
import DeadwaxCore
import Foundation
import Observation
import UIKit

/// The player every screen draws and taps: the queue as Up Next has it, the entry heard, where it is, Repeat,
/// Shuffle, Normalization, the song's failure words and the notice - and the actions, each the Core call named on it.
///
/// THE SHELL'S PLAYER (app 0.2): this is the surface the parts build on, and its names don't change. Under it runs
/// Phase 0's engine path, made a little wider - a queue started by Core's `startUpNext` (Shuffle included), the
/// engine's keys unique across plays, Next/Previous/seek/jump as the engine does them, a failure in a listener's
/// words, the lock screen and interruptions exactly as Phase 0. What it does NOT do yet is marked "the Player part":
/// QueueController over an EngineLink (Repeat's copies, held edits, Play Next/Last with a queue, moves, Shuffle
/// mid-queue, skipFailed and the retry), Normalization's levels (every song plays as the file is, Off), resume and
/// prefetch through SongFiles' own rules. A screen calls the names here and gets that behaviour when it lands.
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
    /// The player means to play (playing, or loading to play): Play/Pause shows Pause.
    var isPlaying: Bool { engineState.phase == .playing || engineState.phase == .loading }
    /// The song is loading (the spinner over Play/Pause).
    var isLoading: Bool { engineState.phase == .loading }
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
    /// The notice capsule's words (D11): "Playing next: …", "Added to Up Next: …" - shown for `Notice.seconds`.
    private(set) var notice: String?
    /// The device's Normalization (levels.md 4.2; UserDefaults `Normalization.storageKey`), read at each play's tap.
    var normalization: Normalization {
        get { normalizationSetting }
        set {
            normalizationSetting = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Normalization.storageKey)
        }
    }

    // MARK: Debug's readings

    /// The engine's own state, as it last said.
    private(set) var engineState = EngineState()
    /// The last failure in the engine's own words (D7: raw words only in Debug's "Last failure").
    private(set) var lastFailure: String?
    /// The output's name (AVAudioSession's route), for Debug's readout.
    private(set) var outputName: String?

    /// The Hi-res readout for the song playing: its file's rate and bits, and the output's rate (Phase 0's).
    var readout: String? {
        guard let entry = current, let song = songs[entry.key], let rate = engineState.fileRate else { return nil }
        var bits = song.bitDepth ?? headerBits[song.id]
        if bits == nil, (song.suffix ?? "").lowercased() == "flac", let header = files.header(of: song),
           let info = FLACStreamInfo.parse(header) {
            bits = info.bitsPerSample
            headerBits[song.id] = info.bitsPerSample
        }
        let output = engineState.outputRate ?? session.outputRate
        var line = RateWords.readout(fileRate: rate, bits: bits, codec: song.suffix, outputRate: output)
        if let outputName { line += " (\(outputName))" }
        return line
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
    func engineDebug() -> EngineDebug? { engine?.debug() }

    // MARK: Info's readings (D8)

    /// The song an entry was queued from - every field Navidrome gave (Info's Format, Sample rate, Bit depth).
    func song(for entry: QueueEntry) -> Song? { songs[entry.key] }

    /// An album a queue came from, as its page last loaded it (the last 8 kept), for Info's album lines.
    func playedAlbum(id: String) -> Album? { albums.first { $0.id == id } }

    /// Each entry's level as decided (levels.md 4.3, LevelDecisions) - empty until the Player part decides levels.
    private(set) var levelDecisions = LevelDecisions()

    /// An album's loudness as deadwax last answered it (GET .../loudness/album/{id}); nil until the Player part asks.
    func loudness(albumID: String) -> AlbumLoudness? { nil }

    // MARK: kept

    private let server: ServerModel
    private let files: SongFiles
    private let session = AudioSessionController()
    private let nowPlaying = NowPlayingController()
    @ObservationIgnored private var engine: PlaybackEngine?
    /// The queue's entries, as QueueController.entries(queue) gives them: Up Next's keys.
    private var entries: [QueueEntry] = []
    /// The engine's key for each entry: unique across plays, so a state from before the last play - still on its
    /// way to the main queue - names no entry of this one (Phase 0's rule).
    @ObservationIgnored private var engineKeys: [Int] = []
    @ObservationIgnored private var nextEngineKey = 0
    /// Each entry's song, by Up Next's key.
    @ObservationIgnored private var songs: [Int: Song] = [:]
    @ObservationIgnored private var albums: [Album] = []
    /// The decoded length the engine reported for the entry heard.
    private var length: Double?
    private var pendingSeek: Scrub.PendingSeek?
    private var normalizationSetting = Normalization.read(UserDefaults.standard.string(forKey: Normalization.storageKey))
    /// Debug's test songs play their downloaded copies.
    @ObservationIgnored private var playsCopies = false
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var interrupted = false
    @ObservationIgnored private var artwork: (id: String, image: UIImage)?
    @ObservationIgnored private var coverAsked: String?
    @ObservationIgnored private var headerBits: [String: Int] = [:]
    /// A failure asks who is signed in once, not at each of its re-publishes.
    @ObservationIgnored private var askedAfterFailure = false
    @ObservationIgnored private var noticeShown = 0

    init(server: ServerModel, files: SongFiles) {
        self.server = server
        self.files = files
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
    }

    // MARK: playing

    /// The album page's Play, Shuffle and a song's tap: `songs` played from `index` (nil with Shuffle: anywhere),
    /// every one at QueuePickWords.playLevel(normalization) - as an album. Call it in the tap, nothing awaited first.
    /// Will be: QueueController.playTracks(tracks, start:, shuffle:) (upnext.md 6).
    func play(songs: [Song], album: Album, at index: Int?, shuffle: Bool = false) {
        let level = QueuePickWords.playLevel(normalization)
        let tracks = songs.map { QueueTrack(song: $0, albumId: album.id, albumName: album.name ?? "",
                                            albumArtist: album.artist, albumCoverArt: album.coverArt, level: level) }
        remember(album)
        start(startUpNext(tracks, start: index, shuffle: shuffle), songs: songs, copies: false)
    }

    /// Play Next from a ••• menu: the pick queued straight after the song playing's copies (pick.choose(.next,
    /// setting: normalization)), and the notice said when the music didn't start from it (pick.notice). True when
    /// something was queued (the menu closes). Will be: QueueController.playNext(tracks).
    /// THE SHELL: only with nothing queued (it plays); with a queue it does nothing yet and answers false.
    @discardableResult
    func playNext(_ pick: QueuePick<Song>, album: Album) -> Bool { choose(.next, pick, album: album) }

    /// Play Last from a ••• menu: the pick queued at the end of Playing Next. Will be: QueueController.playLast.
    /// THE SHELL: as playNext.
    @discardableResult
    func playLast(_ pick: QueuePick<Song>, album: Album) -> Bool { choose(.last, pick, album: album) }

    /// Play Next or Play Last, by the choice (QueuedHow).
    @discardableResult
    func choose(_ choice: QueueChoice, _ pick: QueuePick<Song>, album: Album) -> Bool {
        guard let queued = pick.choose(choice, setting: normalization) else { return false }
        guard !hasQueue else { return false }
        let tracks = queued.tracks.map { QueueTrack(song: $0, albumId: album.id, albumName: album.name ?? "",
                                                    albumArtist: album.artist, albumCoverArt: album.coverArt,
                                                    level: queued.level) }
        remember(album)
        // it started the music: the mini player is the notice (pick.notice(choice, started: true) is nil)
        start(startUpNext(tracks, start: 0), songs: queued.tracks, copies: false)
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

    /// Play: the song from where it paused; after the queue ended or failed, the entry shown again.
    func resume() {
        guard let engine else { return }
        try? session.activate()
        engine.resume()
        startTicking()
    }

    func pause() {
        engine?.pause()
    }

    /// Next: the entry after the one heard (Core's `onward`), kept paused when paused. Will be: QueueController.next()
    /// (Repeat One's copies passed by, a held edit made first).
    func next() {
        catchUp()
        guard let index = onward(queue) else { return }
        engine?.skip(to: index)
        playIfStopped()
    }

    /// Previous: the song again from its start after `UpNext.restartAfterSeconds`, else the entry before (Core's
    /// `backward`). Will be: QueueController.previous().
    func previous() {
        catchUp()
        switch backward(queue, position: position) {
        case .restart: seek(to: 0)
        case .go(let index): engine?.skip(to: index)
        }
        playIfStopped()
    }

    /// The scrubber let go, or the lock screen's: `seconds` into the entry heard. The thumb holds there until the
    /// engine reports it landed (Scrub.PendingSeek, Scrub.settled).
    func seek(to seconds: Double) {
        guard let engine else { return }
        pendingSeek = Scrub.PendingSeek(target: seconds, since: Self.nowMs())
        engine.seek(to: seconds)
        showNowPlaying()
    }

    /// Repeat's button: off -> all -> one (Repeat.allCases), kept on the device. Will be: QueueController.setRepeat
    /// (one's copies queued ahead). THE SHELL: the setting is kept and drawn; the engine doesn't repeat yet.
    func setRepeat(_ mode: Repeat) {
        repeatMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Repeat.storageKey)
    }

    /// Shuffle's button mid-queue. Will be: QueueController.setShuffle(!shuffle). THE SHELL: nothing yet.
    func toggleShuffle() {}

    /// An Up Next row tapped: that entry played from its start. Will be: QueueController.jumpTo(key:) (a row ahead
    /// in Playing Next or the list, the rows before it let go). THE SHELL: the engine skips to it.
    func jump(to key: Int) {
        catchUp()
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return }
        engine?.skip(to: index)
        playIfStopped()
    }

    /// An Up Next row dragged to `index` of its own group. Will be: QueueController.moveInQueue(key:to:). THE SHELL:
    /// nothing yet.
    func move(key: Int, to index: Int) {}

    /// An Up Next row removed. Will be: QueueController.removeFromQueue(key:). THE SHELL: nothing yet.
    func remove(key: Int) {}

    /// Up Next's Clear on Playing Next. Will be: QueueController.clearPlayingNext(). THE SHELL: nothing yet.
    func clearPlayingNext() {}

    /// Stops and forgets the queue: the mini player goes.
    func stop() {
        engine?.stop()
        files.keep([], ahead: [])
        nowPlaying.clear()
        ticker?.invalidate()
        ticker = nil
        queue = .empty
        entries = []
        engineKeys = []
        songs = [:]
        position = 0
        length = nil
        pendingSeek = nil
        errorLine = nil
    }

    /// The person changed (ServerModel.whenPersonChanges): everything of theirs let go.
    func reset() {
        stop()
        albums = []
        levelDecisions = LevelDecisions()
        notice = nil
        lastFailure = nil
        engineState = EngineState()
    }

    /// The album page showed `album` with its songs: kept for Info, and its levels warmed when the setting will want
    /// them (AlbumPageLines.warms). Will be: the LoudnessBook's warm (its 202 "measuring" recorded, LevelWait).
    func albumShown(_ album: Album) {
        remember(album)
        guard AlbumPageLines.warms(normalization, songs: album.song), let client = server.client else { return }
        Task { _ = try? await client.warmLevels(albumID: album.id) }
    }

    /// The album page found its album gone (404): nothing kept of it.
    func albumGone(id: String) {
        albums.removeAll { $0.id == id }
    }

    /// The app came to the front: the position read again. Will be: resume's save and the engine's re-read (resume.md 6).
    func becameActive() {
        tick()
    }

    /// The app went to the back. Will be: the queue saved for resume (resume.md 6).
    func movedToBackground() {}

    /// Debug's test songs and hi-res row: `songs` played from `index` as they are (no album; Off), their downloaded
    /// copies when `copies` (a song with none is streamed).
    func playTest(_ songs: [Song], at index: Int, copies: Bool) {
        let tracks = songs.map { QueueTrack(song: $0, albumId: $0.albumId ?? "", albumName: $0.album ?? "") }
        start(startUpNext(tracks, start: index), songs: songs, copies: copies)
    }

    // MARK: the engine (Phase 0's path)

    private func start(_ started: UpNextQueue, songs played: [Song], copies: Bool) {
        guard let client = server.client, started.current != nil else { return }
        do {
            try session.activate()
        } catch {
            errorLine = ErrorWords.other
            lastFailure = "iOS wouldn't let the app play: \(error.localizedDescription)"
            return
        }
        guard let engine = ensureEngine() else { return }
        let made = QueueController.entries(started)
        // the song each entry was queued from, by its track's id (startUpNext keeps the order it was given or shuffles it)
        var byID: [String: Song] = [:]
        for song in played { byID[song.id] = song }
        var kept: [Int: Song] = [:]
        for entry in made { kept[entry.key] = byID[entry.track.id] }
        errorLine = nil
        askedAfterFailure = false
        playsCopies = copies
        queue = started
        entries = made
        songs = kept
        engineKeys = made.indices.map { nextEngineKey + $0 }
        nextEngineKey += made.count
        position = 0
        length = nil
        pendingSeek = nil
        engine.play(Self.tracks(made, songs: kept, keys: engineKeys, copies: copies, files: files, client: client),
                    from: started.index)
        startTicking()
        showNowPlaying()
    }

    /// The engine's tracks. Nonisolated, so the closures it makes - which the engine calls on its own queue - belong
    /// to no actor. Every entry plays as the file is (Off: GainedSource.wrap hands the source itself back) until the
    /// Player part applies its level.
    nonisolated static func tracks(_ entries: [QueueEntry], songs: [Int: Song], keys: [Int], copies: Bool,
                                   files: SongFiles, client: DeadwaxClient) -> [EngineTrack] {
        zip(entries, keys).map { entry, key in
            let song = songs[entry.key] ?? Song(id: entry.track.id, title: entry.track.title)
            let factor: Float? = nil
            return EngineTrack(key: key, audio: EngineTrack.audio(songID: song.id, level: nil), song: song) { start in
                let source: PCMSource
                if copies, let url = files.downloadedURL(for: song) {
                    source = try FileSource(url: url, start: start)
                } else {
                    source = try files.streamSource(for: song, client: client, start: start)
                }
                return GainedSource.wrap(source, factor: factor)
            }
        }
    }

    /// The engine's two readings of the output, from AVAudioSession.
    nonisolated static func lead(_ engine: PlaybackEngine) {
        engine.startLead = { AudioSessionController.startLead() }
        engine.latency = { AudioSessionController.latency() }
    }

    private func ensureEngine() -> PlaybackEngine? {
        if let engine { return engine }
        do {
            let engine = try PlaybackEngine()
            Self.lead(engine)
            engine.onChange = { [weak self] state in
                MainActor.assumeIsolated { self?.changed(state) }
            }
            self.engine = engine
            return engine
        } catch {
            errorLine = ErrorWords.other
            lastFailure = "iOS couldn't make the audio engine: \(error.localizedDescription)"
            return nil
        }
    }

    private func changed(_ state: EngineState) {
        // the entry heard, by its engine key: a state from before the last play names none of this queue's
        let index = state.key.flatMap { engineKeys.firstIndex(of: $0) }
        let moved = index != nil && index != queue.index
        engineState = state
        if let index, moved {
            queue.index = index
            position = 0
            length = nil
            pendingSeek = nil
            errorLine = nil
        }
        if case .failed(let words) = state.phase {
            lastFailure = words
            let failure = PlayerWords.Failure(rawValue: state.failure?.kind.rawValue ?? "") ?? .other
            errorLine = PlayerWords.words(failure)
            if !askedAfterFailure {
                // a song that failed to load asks who is signed in (D7): a stream's 401 shows the sign-in
                askedAfterFailure = true
                Task { await server.refreshMe() }
            }
        }
        outputName = session.outputName
        if moved || state.phase != .loading { tick() }
        if index != nil { keepAndPrefetch() }
        showNowPlaying()
    }

    /// The queue's place from the engine's own position (what is heard), before a Next or Previous is worked out.
    private func catchUp() {
        guard let at = engine?.position(), engineKeys.indices.contains(at.index), engineKeys[at.index] == at.key else { return }
        queue.index = at.index
        position = at.seconds
    }

    private func playIfStopped() {
        switch engineState.phase {
        case .ended, .failed: resume()
        default: break
        }
    }

    /// iOS reset its media services: the session made active again when something was playing, then the engine
    /// makes itself again and goes on from the frame heard.
    private func mediaReset() {
        if isPlaying { try? session.activate() }
        engine?.rebuild()
    }

    /// The song heard and the next kept in the cache, and the next song's bytes begun (Phase 0's StreamCache.kept).
    private func keepAndPrefetch() {
        let queued = entries.compactMap { songs[$0.key] }
        guard queued.count == entries.count, queued.indices.contains(queue.index) else { return }
        let now = engine?.position()
        let engineAt = now.flatMap { at in engineKeys.indices.contains(at.index) && engineKeys[at.index] == at.key ? at.index : nil }
        let (inUse, ahead) = StreamCache.kept(queued, shown: queue.index, engineAt: engineAt)
        files.keep(inUse, ahead: ahead)
        if now != nil, !playsCopies, let client = server.client, let next = nextIndex(queue), queued.indices.contains(next) {
            files.prefetch(queued[next], client: client)
        }
    }

    private func startTicking() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let engine else { return }
        if let at = engine.position(), engineKeys.indices.contains(queue.index), at.key == engineKeys[queue.index] {
            position = at.seconds
            length = at.length
            pendingSeek = Scrub.settled(pendingSeek, position: at.seconds, now: Self.nowMs())
        }
        if !isPlaying {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func showNowPlaying() {
        guard let entry = current, let song = songs[entry.key] else { return }
        let cover = entry.track.coverArt
        nowPlaying.show(song: song, elapsed: shownPosition, playing: engineState.phase == .playing,
                        artwork: cover != nil && artwork?.id == cover ? artwork?.image : nil)
        if let cover, artwork?.id != cover, coverAsked != cover, let client = server.client {
            coverAsked = cover
            Task {
                guard let data = try? await client.cover(coverID: cover, size: CoverSize.lockScreen),
                      let image = UIImage(data: data) else { return }
                self.artwork = (cover, image)
                self.showNowPlaying()
            }
        }
    }

    private func interruption(began: Bool, shouldResume: Bool) {
        if began {
            interrupted = isPlaying
            engine?.pause()
        } else if shouldResume, interrupted {
            interrupted = false
            resume()
        }
    }

    private func remember(_ album: Album) {
        albums.removeAll { $0.id == album.id }
        albums.insert(album, at: 0)
        if albums.count > 8 { albums.removeLast(albums.count - 8) }
    }

    private static func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }
}
