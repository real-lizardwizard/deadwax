import DeadwaxAudio
import DeadwaxCore
import Foundation
import Observation
import UIKit

/// Everything Phase 0's one screen shows and does. Thin on purpose: the rules are DeadwaxCore's
/// (tested on Linux) and the audio is DeadwaxAudio's (tested on the macOS runner).
@MainActor
@Observable
final class AppModel {
    enum Source: String, CaseIterable, Identifiable {
        case stream = "Streamed"
        case downloaded = "Downloaded"
        var id: String { rawValue }
    }

    // the server
    var addressText = UserDefaults.standard.string(forKey: "address") ?? ""
    var checking = false
    var report: CheckReport?
    var me: Me?

    // signing in (logins on)
    var username = ""
    var password = ""
    var signingIn = false
    var signInWords: String?

    // the test sounds and the hi-res row
    var testSongs: [Song] = []
    var testWords: String?
    var source: Source = .stream
    var downloaded: Set<String> = []
    var downloading: Set<String> = []
    var downloadWords: String?
    var hiRes: Song?
    var hiResWords: String?
    var findingHiRes = false

    // playing
    var engineState = EngineState()
    var queue = PlayQueue(songs: [])
    var elapsed: Double = 0
    var playWords: String?
    var outputName: String?

    let installLine: String

    private let transport = URLSessionTransport()
    private let files = SongFiles()
    private let session = AudioSessionController()
    private let nowPlaying = NowPlayingController()
    private var client: DeadwaxClient?
    private var engine: PlaybackEngine?
    private var ticker: Timer?
    private var interrupted = false
    private var artwork: (id: String, image: UIImage)?
    /// Bits per sample read from a file's STREAMINFO, when Navidrome didn't say.
    @ObservationIgnored private var headerBits: [String: Int] = [:]
    /// The cover last asked for the lock screen, so a failed fetch isn't asked again at every change.
    @ObservationIgnored private var coverAsked: String?
    /// The engine's key for each song of `queue` (Up Next's marks, until its own slice lands): unique
    /// across plays, so a state of the queue before the last play - still on its way to the main
    /// queue - names no song of this one.
    @ObservationIgnored private var keys: [Int] = []
    @ObservationIgnored private var nextKey = 0
    /// A 401 on a stream asks who is signed in once, not at each of the failure's re-publishes.
    @ObservationIgnored private var askedAfterSignOut = false

    init() {
        installLine = InstallExpiry.line(expiration: Self.profile()?.expiration, now: Date())
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

    /// The app's own provisioning profile: how long this install runs (7 days on a free account).
    static func profile() -> ProvisioningProfile? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ProvisioningProfile.parse(data)
    }

    // MARK: Check, and signing in

    func check() async {
        let address: ServerAddress
        switch ServerAddress.parse(addressText) {
        case .failure(let error):
            report = CheckReport(health: .failure(error), who: nil)
            return
        case .success(let parsed):
            address = parsed
        }
        UserDefaults.standard.set(address.base.absoluteString, forKey: "address")
        addressText = address.base.absoluteString
        let client = DeadwaxClient(server: address, session: SessionKeychain.read(address.key), transport: transport)
        self.client = client
        checking = true
        defer { checking = false }
        let health = await outcome { try await client.health() }
        var who: Result<Me, DeadwaxError>?
        if case .success = health { who = await outcome { try await client.me() } }
        let report = CheckReport.from(health: health, me: who)
        self.report = report
        me = try? who?.get()
        if report.ok { await loadTestSongs() }
    }

    func signIn() async {
        guard let client else { return }
        signingIn = true
        defer { signingIn = false }
        do {
            let (_, value) = try await client.signIn(username: username, password: password)
            SessionKeychain.save(value, for: client.server.key)
            password = ""
            signInWords = nil
            await check()
        } catch {
            signInWords = (error as? DeadwaxError)?.words ?? error.localizedDescription
        }
    }

    func signOut() async {
        guard let client else { return }
        stop()
        try? await client.signOut()
        SessionKeychain.delete(client.server.key)
        testSongs = []
        hiRes = nil
        await check()
    }

    // MARK: the test sounds and the hi-res row

    func loadTestSongs() async {
        guard let client else { return }
        do {
            let found = try await client.search(TestSounds.query, songs: TestSounds.pageSize)
            testSongs = TestSounds.pick(found.songs)
            testWords = testSongs.isEmpty
                ? "The beep album isn't in the library: copy \"Start test (2026)\" by \"deadwax test\" into it, let Navidrome scan, and Check again."
                : nil
            refreshDownloaded()
        } catch {
            testWords = words(error)
        }
    }

    func findHiRes() async {
        guard let client else { return }
        findingHiRes = true
        defer { findingHiRes = false }
        var best: Song?
        var ratesSaid = false
        do {
            for page in 0..<HiRes.maxPages {
                let found = try await client.search("", songs: HiRes.pageSize, songOffset: page * HiRes.pageSize)
                ratesSaid = ratesSaid || found.songs.contains { $0.samplingRate != nil }
                if let candidate = HiRes.best(found.songs + (best.map { [$0] } ?? [])) { best = candidate }
                if let best, HiRes.isTwentyFourOneNinetyTwo(best) { break }
                if found.songs.count < HiRes.pageSize { break }
            }
        } catch {
            hiResWords = words(error)
            return
        }
        hiRes = best
        refreshDownloaded()
        if let best {
            hiResWords = HiRes.isTwentyFourOneNinetyTwo(best) ? nil
                : "No 24/192 FLAC in the library; this is the highest rate there is."
        } else {
            hiResWords = ratesSaid ? "No FLAC above 48 kHz in the library."
                : "Navidrome didn't say any song's sample rate, so a hi-res song can't be found this way."
        }
    }

    func refreshDownloaded() {
        downloaded = Set((testSongs + (hiRes.map { [$0] } ?? [])).filter { files.downloadedURL(for: $0) != nil }.map(\.id))
    }

    func download(_ songs: [Song]) async {
        guard let client else { return }
        downloadWords = nil
        for song in songs where !downloaded.contains(song.id) {
            downloading.insert(song.id)
            do {
                try await files.download(song, client: client)
                downloaded.insert(song.id)
            } catch {
                downloadWords = "\(song.name): \(words(error))"
            }
            downloading.remove(song.id)
        }
    }

    func removeDownloads() {
        files.removeDownloads()
        refreshDownloaded()
    }

    // MARK: playing

    func play(_ songs: [Song], at index: Int) {
        guard let client, songs.indices.contains(index) else { return }
        do {
            try session.activate()
        } catch {
            playWords = "iOS wouldn't let the app play: \(error.localizedDescription)"
            return
        }
        guard let engine = ensureEngine() else { return }
        playWords = nil
        askedAfterSignOut = false
        queue = PlayQueue(songs: songs, index: index)
        keys = songs.indices.map { nextKey + $0 }
        nextKey += songs.count
        elapsed = 0
        engine.play(Self.tracks(songs, keys: keys, copies: source == .downloaded, files: files, client: client), from: index)
        startTicking()
        showNowPlaying()
    }

    func toggle() {
        if engineState.phase == .playing || engineState.phase == .loading {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        engine?.pause()
    }

    func resume() {
        guard let engine else { return }
        try? session.activate()
        engine.resume()
        startTicking()
    }

    func stop() {
        engine?.stop()
        files.keep([], ahead: [])
        nowPlaying.clear()
    }

    /// Next and Previous keep a pause (the engine moves there without loading, and play opens it);
    /// after the queue ended or failed they play.
    func next() {
        catchUp()
        guard let index = queue.nextIndex else { return }
        engine?.skip(to: index)
        playIfStopped()
    }

    func previous() {
        catchUp()
        switch queue.previous(at: elapsed) {
        case .restart: engine?.seek(to: 0)
        case .go(let index): engine?.skip(to: index)
        }
        playIfStopped()
    }

    func seek(to seconds: Double) {
        engine?.seek(to: seconds)
    }

    private func playIfStopped() {
        switch engineState.phase {
        case .ended, .failed: resume()
        default: break
        }
    }

    /// The queue's place from the engine's own position (what is heard), before a Next or Previous
    /// is worked out from it: a state change can still be on its way.
    private func catchUp() {
        guard let at = engine?.position(), keys.indices.contains(at.index), keys[at.index] == at.key else { return }
        queue.move(to: at.index)
        elapsed = at.seconds
    }

    /// iOS reset its media services: the old engine is dead. The session is made active again when
    /// something was playing, then the engine makes itself again and goes on from the frame heard.
    private func mediaReset() {
        if engineState.phase == .playing || engineState.phase == .loading { try? session.activate() }
        engine?.rebuild()
    }

    /// The engine's tracks. Nonisolated, so the closures it makes - which the engine calls on its
    /// own queue - belong to no actor.
    nonisolated static func tracks(_ songs: [Song], keys: [Int], copies: Bool, files: SongFiles,
                                   client: DeadwaxClient) -> [EngineTrack] {
        zip(songs, keys).map { song, key in
            // no Normalization yet (its own slice decides each entry's level, once): Off, so every
            // entry is the decode as it is - GainedSource.wrap hands the source itself back
            let factor: Float? = nil
            return EngineTrack(key: key, audio: EngineTrack.audio(songID: song.id, level: nil), song: song) { start in
                // a downloaded copy when asked for and there is one; the stream (or its cached copy) otherwise
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

    /// The engine's two readings of the output, from AVAudioSession: the lead before a song started
    /// from silence, and the latency taken off every position.
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
            playWords = "iOS couldn't make the audio engine: \(error.localizedDescription)"
            return nil
        }
    }

    private func changed(_ state: EngineState) {
        // the song heard, by its key: a state from before the last play names none of this queue's
        let index = state.key.flatMap { keys.firstIndex(of: $0) }
        let moved = index != nil && index != queue.index
        engineState = state
        if let index { queue.move(to: index) }
        if case .failed(let words) = state.phase {
            playWords = words
            if state.failure?.kind == .signedOut, !askedAfterSignOut {
                // a 401 on a stream stopped the queue at that song: ask who is signed in, so the
                // sign-in shows
                askedAfterSignOut = true
                Task { await self.check() }
            }
        }
        outputName = session.outputName
        if moved || state.phase != .loading { tick() }
        if index != nil { keepAndPrefetch() }
        showNowPlaying()
    }

    /// The song heard and the next kept in the cache, every fetch of a song skipped past let go, and
    /// the next song's bytes begun now, so the join is seamless. What is let go is decided from the
    /// earlier of this state's song and the engine's own now (StreamCache.kept): a state reaches the
    /// main queue after the engine has moved on, and after a quick Previous it names a later song than
    /// the one the engine has just opened a fetch for.
    private func keepAndPrefetch() {
        guard queue.songs.indices.contains(queue.index) else { return }
        // read on the engine's queue, after every skip and play sent from here: where it is now
        let now = engine?.position()
        let engineAt = now.flatMap { at in keys.indices.contains(at.index) && keys[at.index] == at.key ? at.index : nil }
        let (inUse, ahead) = StreamCache.kept(queue.songs, shown: queue.index, engineAt: engineAt)
        files.keep(inUse, ahead: ahead)
        // nothing begun for a queue the engine no longer holds (a state from before a stop)
        if now != nil, source == .stream, let client, let next = queue.nextIndex {
            files.prefetch(queue.songs[next], client: client)
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
        // what is heard, of the song the queue shows (the engine's change of song follows the ear)
        if let at = engine.position(), keys.indices.contains(queue.index), at.key == keys[queue.index] {
            elapsed = at.seconds
        }
        if engineState.phase != .playing && engineState.phase != .loading {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func showNowPlaying() {
        guard let song = queue.current else { return }
        nowPlaying.show(song: song, elapsed: elapsed, playing: engineState.phase == .playing,
                        artwork: artwork?.id == song.coverArt ? artwork?.image : nil)
        if let cover = song.coverArt, artwork?.id != cover, coverAsked != cover, let client {
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
            interrupted = engineState.phase == .playing || engineState.phase == .loading
            engine?.pause()
        } else if shouldResume, interrupted {
            interrupted = false
            resume()
        }
    }

    // MARK: words

    /// The Hi-res readout for the song playing: its file's rate and bits, and the output's rate.
    var readout: String? {
        guard let song = queue.current, let rate = engineState.fileRate else { return nil }
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

    private func words(_ error: Error) -> String {
        (error as? DeadwaxError)?.words ?? String(describing: error)
    }

    private func outcome<T>(_ body: () async throws -> T) async -> Result<T, DeadwaxError> {
        do {
            return .success(try await body())
        } catch let error as DeadwaxError {
            return .failure(error)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }
}
