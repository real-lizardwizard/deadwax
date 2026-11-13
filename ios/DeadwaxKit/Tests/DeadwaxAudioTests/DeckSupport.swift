#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// What turntable slice 2's tests share (notes/ios-specs/turntable.md 7.2): the voice's cases read from Core's own
// fixtures (Tests/DeadwaxCoreTests/Fixtures/deck/voice - lib/deckVoice.ts's runs, their windows made from the same
// recipes DeckVoiceTests makes them from), the deck's FLAC fixtures (Fixtures/deck, ios/scripts/make-test-album.py
// --deck-fixtures), and an offline deck engine.

enum DeckCases {
    static let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let voiceFolder = here.deletingLastPathComponent().appendingPathComponent("DeadwaxCoreTests/Fixtures/deck/voice")
    static let deckFolder = here.appendingPathComponent("Fixtures/deck")

    static func deckFixture(_ name: String) -> URL { deckFolder.appendingPathComponent(name) }

    /// A double as the exporter writes it: "<16 hex digits of its bits> <readable>".
    static func number(_ value: Any?) -> Double {
        guard let text = value as? String, text.count >= 16, let bits = UInt64(text.prefix(16), radix: 16) else { return .nan }
        return Double(bitPattern: bits)
    }

    static func optionalNumber(_ value: Any?) -> Double? {
        guard let text = value as? String, text.count >= 16, let bits = UInt64(text.prefix(16), radix: 16) else { return nil }
        return Double(bitPattern: bits)
    }

    /// export-deck-vectors.cjs recipeChannel, as DeckVoiceTests has it.
    static func recipeChannel(_ kind: String, _ seed: Int, _ ch: Int, _ length: Int) -> [Float] {
        var out = [Float](repeating: 0, count: length)
        var x = UInt32(truncatingIfNeeded: seed * 2 + ch + 1)
        var phase = 0
        let period = 2400 + seed * 7 + ch * 331
        let stepAt = length / 2 + ch * 9601
        for i in 0..<length {
            var v: Int32 = 0
            switch kind {
            case "noise", "soft":
                x ^= x << 13
                x ^= x >> 17
                x ^= x << 5
                v = Int32(x >> 16) - 32768
                if kind == "soft" { v >>= 3 }
            case "sweep":
                phase = (phase + 1 + ((i >> 7) % 600) * (ch + 1)) & 0xffff
                v = Int32(phase < 32768 ? phase * 2 - 32768 : (65535 - phase) * 2 - 32767)
            case "clicks":
                let at = i % period
                v = at == 0 ? 32767 : at == 1 ? -32768 : 0
            case "step":
                v = i >= stepAt ? (ch == 0 ? 32767 : -32768) : 0
            default:
                break
            }
            out[i] = Float(v) / 32768
        }
        return out
    }

    struct Message {
        let post: Double
        /// the window's recipe, made into PCM by the caller; or the message itself
        let window: DeckPCM?
        let windowStart: Double
        let windowRate: Double
        let message: VoiceMessage?

        func voice() -> VoiceMessage {
            if let message { return message }
            if let window { return .window(window.voiceWindow(start: windowStart, rate: windowRate)) }
            return .window(nil)
        }
    }

    struct Run {
        let rate: Double
        let block: Int
        let from: Int
        let frames: Int
    }

    struct Case {
        let name: String
        let messages: [Message]
        let runs: [Run]
    }

    final class Windows: @unchecked Sendable {
        private var made: [String: DeckPCM] = [:]
        private let lock = NSLock()
        func get(_ kind: String, _ seed: Int, _ rate: Double, _ channels: Int) -> DeckPCM {
            lock.lock()
            defer { lock.unlock() }
            let key = "\(kind) \(seed) \(rate) \(channels)"
            if let window = made[key] { return window }
            let length = 8 * Int(rate)
            let window = DeckPCM((0..<channels).map { (c: Int) -> [Float] in recipeChannel(kind, seed, c, length) })
            made[key] = window
            return window
        }
    }
    static let windows = Windows()

    static func cases() throws -> [Case] {
        let names = try FileManager.default.contentsOfDirectory(atPath: voiceFolder.path)
            .filter { $0.hasSuffix(".json") && $0 != "windows.json" }.sorted()
        return try names.map { (name: String) -> Case in
            let data = try Data(contentsOf: voiceFolder.appendingPathComponent(name))
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let messages = ((json["messages"] as? [[String: Any]]) ?? []).compactMap { (m: [String: Any]) -> Message? in
                let post = number(m["post"])
                func n(_ key: String) -> Double { number(m[key]) }
                switch m["type"] as? String {
                case "window":
                    guard let w = m["window"] as? [String: Any] else {
                        return Message(post: post, window: nil, windowStart: 0, windowRate: 0, message: .window(nil))
                    }
                    let rate = number(w["rate"])
                    let pcm = windows.get(w["kind"] as? String ?? "", w["seed"] as? Int ?? 0, rate, w["channels"] as? Int ?? 2)
                    return Message(post: post, window: pcm, windowStart: number(w["start"]), windowRate: rate, message: nil)
                case "take":
                    return Message(post: post, window: nil, windowStart: 0, windowRate: 0,
                                   message: .take(at: n("at"), rate: n("rate"), time: n("time"), until: n("until")))
                case "drive":
                    return Message(post: post, window: nil, windowStart: 0, windowRate: 0,
                                   message: .drive(at: n("at"), rate: n("rate"), accel: optionalNumber(m["accel"]),
                                                   time: n("time"), until: n("until")))
                case "hand":
                    return Message(post: post, window: nil, windowStart: 0, windowRate: 0, message: .hand(at: n("at"), time: n("time")))
                case "fade":
                    return Message(post: post, window: nil, windowStart: 0, windowRate: 0, message: .fade(seconds: n("seconds")))
                case "stop":
                    return Message(post: post, window: nil, windowStart: 0, windowRate: 0, message: .stop)
                default:
                    return nil
                }
            }
            let runs = ((json["runs"] as? [[String: Any]]) ?? []).map { (r: [String: Any]) -> Run in
                Run(rate: (r["rate"] as? Double) ?? Double(r["rate"] as? Int ?? 0), block: r["block"] as? Int ?? 0,
                    from: r["from"] as? Int ?? 0, frames: r["frames"] as? Int ?? 0)
            }
            return Case(name: json["name"] as? String ?? name, messages: messages, runs: runs)
        }
    }

    /// Core's voice over a case's run, as DeckVoiceTests' harness drives it - every block's both channels,
    /// interleaved - with PlatformMaths through DeckRender (the render's own entries), and `after` given each block
    /// (an EQ, say) before it is kept.
    static func reference(_ c: Case, _ run: Run,
                          after: ((UnsafeMutablePointer<UnsafeMutablePointer<Float>>, Int) -> Void)? = nil) -> [Float] {
        let state = UnsafeMutablePointer<VoiceState>.allocate(capacity: 1)
        state.initialize(to: DeckRender.newState())
        let left = UnsafeMutablePointer<Float>.allocate(capacity: run.block)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: run.block)
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
        var out: [Float] = []
        out.reserveCapacity(run.frames * 2)
        var next = 0, done = 0
        while done < run.frames {
            let n = min(run.block, run.frames - done)
            let now = Double(run.from + done) / run.rate
            while next < c.messages.count && c.messages[next].post <= now {
                DeckRender.command(state, c.messages[next].voice(), now: now, rate: run.rate)
                next += 1
            }
            DeckRender.render(state, UnsafeMutableBufferPointer(start: outputs, count: 2), frames: n, rate: run.rate, now: now)
            _ = DeckRender.report(state, frames: n, rate: run.rate, now: now)
            after?(outputs, n)
            for i in 0..<n {
                out.append(left[i])
                out.append(right[i])
            }
            done += n
        }
        return out
    }

    /// The deck engine, offline, over the same run: each message posted before the block whose now is at or past
    /// it - so the render applies it at that block's start, with that now - and every block's output kept,
    /// interleaved.
    static func deck(_ c: Case, _ run: Run, engine: DeckEngine) throws -> [Float] {
        engine.setOfflineClock(frames: Double(run.from))
        try engine.start()
        defer { engine.stop() }
        var out: [Float] = []
        out.reserveCapacity(run.frames * 2)
        var next = 0, done = 0
        while done < run.frames {
            let n = min(run.block, run.frames - done)
            let now = Double(run.from + done) / run.rate
            while next < c.messages.count && c.messages[next].post <= now {
                let m = c.messages[next]
                #expect(engine.post(m.voice(), keeping: m.window), "\(c.name): the ring took every message")
                next += 1
            }
            let buffer = try engine.renderOffline(AVAudioFrameCount(n))
            #expect(Int(buffer.frameLength) == n)
            let l = buffer.floatChannelData![0], r = buffer.floatChannelData![1]
            for i in 0..<n {
                out.append(l[i])
                out.append(r[i])
            }
            done += n
        }
        return out
    }

    static func offlineDeck(rate: Double, maximumFrames: Int = 4_096, eq: Bool = true,
                            messageCapacity: UInt32 = DeckEngine.messageCapacity) throws -> DeckEngine {
        var settings = DeckEngine.Settings()
        settings.offline = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        settings.maximumFrames = maximumFrames
        settings.eq = eq
        settings.messageCapacity = messageCapacity
        return DeckEngine(settings: settings)
    }

    /// Where two runs of samples first differ in their bits (nil: identical).
    static func firstBitDifference(_ a: [Float], _ b: [Float]) -> Int? {
        if a.count != b.count { return min(a.count, b.count) }
        for i in 0..<a.count where a[i].bitPattern != b[i].bitPattern && !(a[i].isNaN && b[i].isNaN) { return i }
        return nil
    }

    /// The largest difference between two runs, in dBFS (-inf for none).
    static func worstDB(_ a: ArraySlice<Float>, _ b: ArraySlice<Float>) -> Double {
        var worst = 0.0
        for (x, y) in zip(a, b) { worst = max(worst, abs(Double(x) - Double(y))) }
        return worst == 0 ? -.infinity : 20 * log10(worst)
    }
}

/// An entry playing `file` from where it is asked, at `factor` - the app's own way of opening a download.
func fileEntry(_ file: URL, key: Int, id: String, factor: Float?, opened: ((Int64, Double) -> Void)? = nil) -> EngineTrack {
    EngineTrack(key: key, audio: EngineTrack.audio(songID: id, level: factor.map { "\($0)" }), song: Song(id: id)) {
        (start: StartPoint) throws -> PCMSource in
        let source = try FileSource(url: file, start: start)
        let rate = source.format?.sampleRate ?? 0
        opened?(start.frame(at: rate), rate)
        return GainedSource.wrap(source, factor: factor)
    }
}

/// Both channels of `frames` of the song's engine's output, a piece at a time with its completions handled between.
func renderBoth(_ engine: PlaybackEngine, frames: Int, piece: Int = 4_096) throws -> [[Float]] {
    var out: [[Float]] = [[], []]
    while out[0].count < frames {
        let buffer = try engine.renderOffline(AVAudioFrameCount(min(piece, frames - out[0].count)))
        out[0] += samples(buffer, channel: 0)
        out[1] += samples(buffer, channel: buffer.format.channelCount > 1 ? 1 : 0)
        try completionsHandled(engine)
    }
    return out
}
#endif
