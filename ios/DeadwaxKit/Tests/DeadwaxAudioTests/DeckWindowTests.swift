#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import CAllocHook
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// The record's windows (notes/ios-specs/turntable.md 4.4, 4.5, 7.2), made from the deck's FLAC fixtures
// (Fixtures/deck: ios/scripts/make-test-album.py --deck-fixtures, and export-scrub-window.py for the /scrub answer):
// (a) on the grid, a window is the very frames the song's lane plays - decoded, levelled and converted as the lane
// does it; the pre-roll long enough; a /scrub answer's window equal to a local file's; (b) off the grid, the seam: the
// lane after a seek to an odd place and the voice reading a window both play the three tones as they are; a long
// window made in pieces; and the errors.

/// A song's samples, every channel, read whole (the fixtures are small).
private func fileSamples(_ url: URL) throws -> [[Float]] {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    return (0..<Int(buffer.format.channelCount)).map { (c: Int) -> [Float] in samples(buffer, channel: c) }
}

/// A window's channel, as an array.
private func channel(_ window: DeckWindow, _ c: Int) -> [Float] {
    guard let pcm = window.pcm else { return window.channels[c] }
    return Array(UnsafeBufferPointer(start: pcm.channel(c), count: pcm.frames))
}

/// A folder of the test's own, removed after.
private func withFolder(_ body: (URL) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deck-windows-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(folder)
}

/// The three tones of 4.4 (b) as make-test-album.py writes them, at song time `t`, as the decoder reads them
/// (the file's 32767 steps over 32768): 1, 5 and 12 kHz at -12 dBFS each.
private let tonesLevel = pow(10.0, -12.0 / 20) * 32_767 / 32_768
private let tones = [1_000.0, 5_000.0, 12_000.0]

/// The error of `got` against `want`, relative to `want`'s power, in dB.
private func relativeDB(_ got: [Double], _ want: [Double]) -> Double {
    var error = 0.0, power = 0.0
    for (g, w) in zip(got, want) {
        error += (g - w) * (g - w)
        power += w * w
    }
    return 10 * log10(error / power)
}

/// `/scrub` as deadwax answers it, from a fixture: the window's FLAC and its `X-Deadwax-Window`.
private final class ScrubServer: HTTPTransport, @unchecked Sendable {
    let flac: Data
    let header: String
    private let lock = NSLock()
    private var urls: [URL] = []

    init(flac: Data, header: String) {
        self.flac = flac
        self.header = header
    }

    var asked: [URL] { lock.withLock { urls } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { urls.append(request.url) }
        return HTTPResponse(status: 200, headers: ["X-Deadwax-Window": header, "Content-Type": "audio/flac"], body: flac)
    }
}

/// The fixture `/scrub` answer: its FLAC, its header, and what it was asked.
private func scrubFixture() throws -> (flac: Data, header: DeckScrub.Header, text: String, at: Double, seconds: Double) {
    let about = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: DeckCases.deckFixture("deck-44k-scrub.json")))
        as? [String: Any])
    let text = try #require(about["header"] as? String)
    let header = try #require(DeckScrub.Header.parse(text))
    let flac = try Data(contentsOf: DeckCases.deckFixture("deck-44k-scrub.flac"))
    #expect(about["bytes"] as? Int == flac.count, "the answer is the one the exporter wrote")
    return (flac, header, text, try #require(about["at"] as? Double), try #require(about["seconds"] as? Double))
}

@Suite(.serialized) struct DeckWindowTests {
    static let output = 48_000.0
    /// the signal fixtures' length: 2.3 s, so a window from the 2 s grid start is 0.3 s
    static let songFrames = 110_400

    // MARK: (a) on the grid

    /// A window of each fixture, from the 2 s grid start, at -3 dB - against the song rendered offline through the
    /// engine from 0 at 48 kHz, frame for frame: bit-exact, or under -120 dBFS (4.4 (a)). The 48 kHz one is the file's
    /// samples times the factor, exactly.
    @Test(arguments: ["deck-22k.flac", "deck-44k.flac", "deck-48k.flac", "deck-96k.flac"])
    func aWindowOnTheGridIsWhatTheLanePlays(_ name: String) throws {
        let file = DeckCases.deckFixture(name)
        let factor = multiplier(-3)
        let window = try DeckWindows.window(of: file, from: 2, seconds: 40, outputRate: Self.output, factor: factor)
        #expect(window.start == 2 && window.rate == Self.output && window.channelCount == 2 && window.source == .file)
        #expect(window.frames == 14_400, "\(name): from 2 s to the song's end at 2.3 s")
        #expect(abs(window.end - 2.3) < 1e-12)

        let engine = try offlineEngine(rate: Self.output, channels: 2)
        engine.play([fileEntry(file, key: 0, id: name, factor: factor)], from: 0)
        engine.settle()
        try #require(engine.phase == .playing && engine.outputRunning)
        let lane = try renderBoth(engine, frames: Self.songFrames)
        var line: [String] = []
        for c in 0..<2 {
            let made = channel(window, c)
            let heard = Array(lane[c][96_000..<Self.songFrames])
            let worst = DeckCases.worstDB(made[...], heard[...])
            let exact = firstDifference(made, heard) == nil
            line.append("channel \(c) " + (exact ? "bit-exact" : String(format: "worst %.1f dBFS", worst)))
            #expect(exact || worst <= -120, "\(name) channel \(c): the window is the lane's frames (worst \(worst) dBFS)")
        }
        print("Deck window \(name) -> 48 kHz on the grid: \(line.joined(separator: ", ")); made in "
              + String(format: "%.1f ms", window.madeIn * 1_000))
        if name == "deck-48k.flac" {
            let song = try fileSamples(file)
            for c in 0..<2 {
                let expected = song[c][96_000..<Self.songFrames].map { $0 * factor }
                #expect(firstDifference(channel(window, c), expected) == nil, "48 to 48: the file's samples times the factor, exactly")
            }
        }
    }

    /// 4.4 step 4: the pre-roll is longer than the converter's filter reaches - a window decoded from `P` before its
    /// start and one from `2P` agree past the pre-roll, bit for bit.
    @Test(arguments: ["deck-22k.flac", "deck-44k.flac", "deck-96k.flac"])
    func thePreRollIsLongEnough(_ name: String) throws {
        let file = DeckCases.deckFixture(name)
        let p = try DeckWindows.window(of: file, from: 2, seconds: 40, outputRate: Self.output, factor: multiplier(-3))
        let twice = try DeckWindows.window(of: file, from: 2, seconds: 40, outputRate: Self.output, factor: multiplier(-3),
                                           preRoll: 2 * DeckScrub.preRollS)
        #expect(p.frames == twice.frames && p.start == twice.start)
        for c in 0..<2 {
            let a = channel(p, c), b = channel(twice, c)
            #expect(firstDifference(a, b) == nil,
                    "\(name) channel \(c): P and 2P agree bit for bit (worst \(DeckCases.worstDB(a[...], b[...])) dBFS)")
        }
    }

    /// A window made from deadwax's `/scrub` answer (cut by the server's own code, export-scrub-window.py) is the one
    /// made from the local file, bit for bit - the answer's frame 0 placed by `X-Deadwax-Window` - and its file is
    /// deleted after.
    @Test func aScrubWindowIsTheLocalFilesWindow() throws {
        let fixture = try scrubFixture()
        let ask = DeckScrub.ask(from: 2, seconds: 40, outputRate: Self.output)
        #expect(ask.at == fixture.at && ask.seconds == fixture.seconds, "the fixture was cut as the phone asks")
        let factor = multiplier(-3)
        try withFolder { (folder: URL) -> Void in
            let scrub = try DeckWindows.window(scrub: fixture.flac, header: fixture.header, songID: "deck-44k", folder: folder,
                                               from: 2, seconds: 40, outputRate: Self.output, factor: factor)
            let local = try DeckWindows.window(of: DeckCases.deckFixture("deck-44k.flac"), from: 2, seconds: 40,
                                               outputRate: Self.output, factor: factor)
            #expect(scrub.source == .server && scrub.bytes == fixture.flac.count)
            #expect(scrub.start == local.start && scrub.end == local.end && scrub.frames == local.frames)
            for c in 0..<2 {
                #expect(firstDifference(channel(scrub, c), channel(local, c)) == nil, "channel \(c): the same frames")
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty, "the answer's file deleted")
        }
    }

    /// The same through the client and DeckWindows' own queue: asked of a server answering the fixture, answered on the
    /// queue given - and a window asked and then cancelled is never answered.
    @Test func windowsAreAskedAndAnswered() throws {
        let fixture = try scrubFixture()
        let server = ScrubServer(flac: fixture.flac, header: fixture.text)
        let client = DeadwaxClient(server: ServerAddress(base: try #require(URL(string: "http://deadwax.test:8080"))),
                                   transport: server)
        let answers = DispatchQueue(label: "deck-window-test.answers")
        let local = try DeckWindows.window(of: DeckCases.deckFixture("deck-44k.flac"), from: 2, seconds: 40,
                                           outputRate: Self.output, factor: nil)
        try withFolder { (folder: URL) -> Void in
            let windows = DeckWindows(scrubFolder: folder, answerQueue: answers)
            let done = DispatchSemaphore(value: 0)
            let got = Locked<Result<DeckWindow, DeckWindowError>?>(nil)
            windows.make(scrub: client, songID: "deck-44k", from: 2, seconds: 40, outputRate: Self.output, factor: nil) {
                (result: Result<DeckWindow, DeckWindowError>) -> Void in
                got.set(result)
                done.signal()
            }
            #expect(done.wait(timeout: .now() + 30) == .success, "answered")
            let window = try #require(try got.get()?.get())
            #expect(window.source == .server && firstDifference(channel(window, 0), channel(local, 0)) == nil)
            let url = try #require(server.asked.first)
            #expect(url.path == "/deadwax/navidrome/scrub/deck-44k" && url.query == "at=1.8&seconds=41.2")

            // from the local file, then one cancelled: only the first is answered
            got.set(nil)
            windows.make(file: DeckCases.deckFixture("deck-44k.flac"), from: 2, seconds: 40, outputRate: Self.output, factor: nil) {
                (result: Result<DeckWindow, DeckWindowError>) -> Void in
                got.set(result)
                done.signal()
            }
            #expect(done.wait(timeout: .now() + 30) == .success)
            #expect(try got.get()?.get().source == .file)
            let late = Locked(false)
            windows.make(file: DeckCases.deckFixture("deck-44k.flac"), from: 2, seconds: 40, outputRate: Self.output, factor: nil) {
                (_: Result<DeckWindow, DeckWindowError>) -> Void in
                late.set(true)
            }
            windows.cancel()
            Thread.sleep(forTimeInterval: 1)
            answers.sync {}
            #expect(!late.get(), "a cancelled window is never answered")
        }
    }

    // MARK: (b) off the grid: the seam

    /// 4.4 (b): the three tones played through the engine from a seek to an odd place (2.0123 s: the fixture is short),
    /// and the voice at rate 1 reading a window of the same stretch from the grid start (2 s). Each output against the
    /// tones computed exactly at the song time of each of its frames - the lane's frame n at the seek's frame plus n
    /// output frames; the voice's at the position it played (its state's, frame by frame), through its own DC blocker
    /// and 1.5 ms behind for its limiter's lookahead. A window placed a twentieth of a sample off would be about -44 dB
    /// at 1 kHz and fail.
    @Test func theSeamOffTheGrid() throws {
        let rate = Self.output
        let file = DeckCases.deckFixture("deck-tones.flac")
        let seek = 2.0123
        var opened: (frame: Int64, rate: Double)?
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play([fileEntry(file, key: 0, id: "tones", factor: nil) { (frame: Int64, fileRate: Double) -> Void in
            opened = (frame, fileRate)
        }], from: 0, at: seek)
        engine.settle()
        try #require(engine.phase == .playing && engine.outputRunning)
        let lane = try renderBoth(engine, frames: 24_000)
        let start = try #require(opened)
        #expect(start.rate == 44_100 && start.frame == 88_742, "the seek's frame, at the file's rate")
        // the lane: past its first 20 ms
        let laneRange = 960..<24_000
        let laneWant = laneRange.map { (n: Int) -> Double in
            let t = Double(start.frame) / start.rate + Double(n) / rate
            return tones.reduce(0.0) { $0 + tonesLevel * sin(2 * Double.pi * $1 * t) }
        }
        let laneDB = relativeDB(laneRange.map { Double(lane[0][$0]) }, laneWant)

        // the voice: Core's own, through the render's entries, a frame a block so its position is known for each
        let window = try DeckWindows.window(of: file, from: 2, seconds: 40, outputRate: rate, factor: nil)
        let pcm = try #require(window.pcm)
        let state = UnsafeMutablePointer<VoiceState>.allocate(capacity: 1)
        state.initialize(to: DeckRender.newState())
        let left = UnsafeMutablePointer<Float>.allocate(capacity: 1), right = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        let outputs = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        outputs[0] = left
        outputs[1] = right
        defer {
            state.pointee.deallocate()
            state.deallocate()
            left.deallocate()
            right.deallocate()
            outputs.deallocate()
        }
        DeckRender.command(state, .window(pcm.voiceWindow(start: window.start, rate: rate)), now: 0, rate: rate)
        // at the seek's place as the voice plays it (the hand's delay behind the message), at rate 1
        DeckRender.command(state, .take(at: seek + DeckVoice.handDelayS, rate: 1, time: 0, until: .infinity), now: 0, rate: rate)
        let frames = 24_000 + 200
        var played: [Double] = [], heard: [Float] = []
        played.reserveCapacity(frames)
        heard.reserveCapacity(frames)
        for k in 0..<frames {
            DeckRender.render(state, UnsafeMutableBufferPointer(start: outputs, count: 2), frames: 1, rate: rate, now: Double(k) / rate)
            played.append(state.pointee.pos)
            heard.append(left[0])
        }
        let lookahead = Int((DeckVoice.lookaheadS * rate).rounded())
        let pole = exp(-2 * Double.pi * 10 / rate)
        let blocker = tones.map { (f: Double) -> (gain: Double, phase: Double) in
            let w = 2 * Double.pi * f / rate
            let (nr, ni) = (1 - cos(w), sin(w))
            let (dr, di) = (1 - pole * cos(w), pole * sin(w))
            let d = dr * dr + di * di
            let (hr, hi) = ((nr * dr + ni * di) / d, (ni * dr - nr * di) / d)
            return ((hr * hr + hi * hi).squareRoot(), atan2(hi, hr))
        }
        // past the gain's ramp and the DC blocker's start (200 ms)
        let voiceRange = 9_600..<24_000
        let voiceWant = voiceRange.map { (k: Int) -> Double in
            zip(tones, blocker).reduce(0.0) { $0 + tonesLevel * $1.1.gain * sin(2 * Double.pi * $1.0 * played[k] + $1.1.phase) }
        }
        let voiceDB = relativeDB(voiceRange.map { Double(heard[$0 + lookahead]) }, voiceWant)
        print(String(format: "Deck seam off the grid (the tones from %.4f s): the lane %.1f dB, the voice %.1f dB against the tones; "
                     + "the voice at %.6f s of a window from %.1f s", seek, laneDB, voiceDB, played[voiceRange.lowerBound], window.start))
        #expect(laneDB <= -50, "the lane after its seek plays the tones where it says (\(laneDB) dB)")
        #expect(voiceDB <= -50, "the voice plays the window where it says (\(voiceDB) dB)")
        #expect(abs(played[voiceRange.lowerBound] - (seek + Double(voiceRange.lowerBound + 1) / rate)) < 1e-6,
                "at rate 1, on from the seek's place")
    }

    // MARK: in pieces

    /// 4.4 step 5: a 40 s window of the 96 kHz fixture is decoded and converted a second at a time, never the stretch
    /// whole: the most the making thread's own allocations hold at once is under the window's size plus 2 MB. Counted by
    /// CAllocHook's byte count on this thread (a canary of 1 MB seen first) - the suite runs beside others, so the
    /// process's resident size, before and after, is printed, not bounded.
    @Test func aLongWindowIsMadeInPieces() throws {
        let file = DeckCases.deckFixture("deck-long-96k.flac")
        // the decoder's and the converter's first-time costs outside the count
        _ = try DeckWindows.window(of: file, from: 0, seconds: 2, outputRate: Self.output, factor: nil)
        guard alloc_hook_available() else { return }
        allocationHookInUse.lock()
        defer { allocationHookInUse.unlock() }
        alloc_hook_install()
        defer { alloc_hook_remove() }
        alloc_hook_watch_this_thread()
        alloc_hook_bytes_begin()
        alloc_hook_bytes_canary(1 << 20)
        let canary = alloc_hook_bytes_peak()
        alloc_hook_bytes_begin()
        let before = residentBytes()
        let window = try DeckWindows.window(of: file, from: 0, seconds: 40, outputRate: Self.output, factor: nil)
        let peak = alloc_hook_bytes_peak(), held = alloc_hook_bytes_held(), untracked = alloc_hook_bytes_untracked()
        alloc_hook_bytes_end()
        alloc_hook_unwatch()
        let after = residentBytes()
        let windowBytes = Int64(window.frames * window.channelCount * MemoryLayout<Float>.size)
        let mb = { (bytes: Int64) -> String in String(format: "%.2f MB", Double(bytes) / 1_048_576) }
        print("Deck window made in pieces: 40 s of 96 kHz to 48 kHz, the window \(mb(windowBytes)); the making thread held at most "
              + "\(mb(peak)) (\(mb(held)) at the end); the process's resident size \(mb(Int64(before))) before, \(mb(Int64(after))) after; "
              + String(format: "made in %.0f ms", window.madeIn * 1_000))
        #expect(canary >= 1 << 20, "the byte count saw its canary")
        #expect(untracked == 0)
        #expect(window.frames == 1_920_000 && window.start == 0)
        #expect(peak <= windowBytes + 2 * 1_048_576, "the window and its pieces: \(mb(peak)) against \(mb(windowBytes)) + 2 MB")
    }

    // MARK: errors

    @Test func whatCantBeAWindowSaysWhy() throws {
        // past the song's end
        #expect(throws: DeckWindowError.pastTheEnd) {
            try DeckWindows.window(of: DeckCases.deckFixture("deck-44k.flac"), from: 4, seconds: 40, outputRate: Self.output, factor: nil)
        }
        try withFolder { (folder: URL) -> Void in
            // a file that isn't FLAC: a WAV
            let wav = folder.appendingPathComponent("song.wav")
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
            do {
                let out = try AVAudioFile(forWriting: wav, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100,
                                                                     AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16],
                                          commonFormat: .pcmFormatFloat32, interleaved: false)
                let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
                buffer.frameLength = 44_100
                try out.write(from: buffer)
            }
            #expect(throws: DeckWindowError.notFlac("it isn't a FLAC file")) {
                try DeckWindows.window(of: wav, from: 0, seconds: 1, outputRate: Self.output, factor: nil)
            }
            // nothing a decoder can open
            let junk = folder.appendingPathComponent("junk.flac")
            try Data(repeating: 0x5A, count: 4_096).write(to: junk)
            do {
                _ = try DeckWindows.window(of: junk, from: 0, seconds: 1, outputRate: Self.output, factor: nil)
                Issue.record("junk made a window")
            } catch DeckWindowError.undecodable {
            } catch {
                Issue.record("junk: \(error)")
            }
            // a /scrub answer that isn't at the rate it says, and one that begins after where it was asked
            let fixture = try scrubFixture()
            var wrongRate = fixture.header
            wrongRate.rate = 48_000
            wrongRate.first = Int64((Double(fixture.header.first) / 44_100 * 48_000).rounded(.down))
            do {
                _ = try DeckWindows.window(scrub: fixture.flac, header: wrongRate, songID: "s", folder: folder, from: 2, seconds: 40,
                                           outputRate: Self.output, factor: nil)
                Issue.record("an answer at another rate than it said made a window")
            } catch DeckWindowError.failed(let words) {
                #expect(words.contains("44100"))
            }
            var late = fixture.header
            late.first = 2 * 44_100
            #expect(throws: DeckWindowError.failed("its window began after where it was asked")) {
                try DeckWindows.window(scrub: fixture.flac, header: late, songID: "s", folder: folder, from: 2, seconds: 40,
                                       outputRate: Self.output, factor: nil)
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["junk.flac", "song.wav"],
                    "every answer's file deleted")
        }
    }
}

/// A value two threads share.
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ new: Value) { lock.withLock { value = new } }
}

/// The process's resident size (task_info's MACH_TASK_BASIC_INFO).
func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { (pointer: UnsafeMutablePointer<mach_task_basic_info>) -> kern_return_t in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { (raw: UnsafeMutablePointer<integer_t>) -> kern_return_t in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), raw, &count)
        }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
}
#endif
