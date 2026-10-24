#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// The engine rendered OFFLINE (AVAudioEngine's manual rendering), compared sample by sample - what
// pins gapless and "nothing processed" without a phone. These run on ios.yml's macOS job only:
// AVFAudio doesn't exist on Linux.

/// A song held in memory: `channels` arrays of samples at `rate`.
final class MemorySource: PCMSource {
    let samples: [[Float]]
    let format: AVAudioFormat?
    private var at: Int

    init(_ samples: [[Float]], rate: Double, start: Int = 0) {
        self.samples = samples
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                               channels: AVAudioChannelCount(samples.count), interleaved: false)
        at = start
    }

    func read(maxFrames: AVAudioFrameCount) throws -> PCMRead {
        let left = samples[0].count - at
        if left <= 0 { return .end }
        let count = min(Int(maxFrames), left)
        let buffer = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: AVAudioFrameCount(count))!
        for channel in 0..<samples.count {
            samples[channel].withUnsafeBufferPointer { from in
                buffer.floatChannelData![channel].update(from: from.baseAddress! + at, count: count)
            }
        }
        buffer.frameLength = AVAudioFrameCount(count)
        at += count
        return .frames(buffer)
    }

    func close() {}
}

/// Bytes released a little at a time, as a slow stream's are.
final class GrowingBytes: ByteSource {
    let all: Data
    var released = 0
    var step: Int
    var failure: String?

    init(_ data: Data, step: Int) {
        all = data
        self.step = step
    }

    var isComplete: Bool { released >= all.count }

    func bytes(at offset: Int, count: Int) -> Data {
        if offset >= released { released = min(released + step, all.count) }
        guard offset < released else { return Data() }
        return all.subdata(in: offset..<min(offset + count, released))
    }
}

/// A test signal: distinct in every sample, so a dropped or doubled sample shows.
func signal(frames: Int, channels: Int, seed: Float) -> [[Float]] {
    (0..<channels).map { channel in
        (0..<frames).map { index in
            // multiples of 1/32768: exact in Float32, and in a 16-bit file
            let step = (index * 37 + channel * 101 + Int(seed * 1000)) % 30_000 - 15_000
            return Float(step) / 32_768
        }
    }
}

func offlineEngine(rate: Double, channels: AVAudioChannelCount, changeSettle: Double = 0) throws -> PlaybackEngine {
    var settings = PlaybackEngine.Settings()
    settings.offline = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)
    settings.aheadSeconds = 60
    settings.startSeconds = 0
    settings.bufferSeconds = 0.1
    settings.changeSettleSeconds = changeSettle
    return try PlaybackEngine(settings: settings)
}

/// What the engine asked the songs' sources for: each open's frame at the song's own rate - and
/// how many opens are to fail first (a stream cut off).
final class Opens {
    var frames: [Int64] = []
    var failing = 0
}

/// Songs whose sources start where they are asked, at their own rate, as FileSource and
/// StreamSource do.
func tracksFromWhereAsked(_ songs: [[[Float]]], rate: Double, opens: Opens = Opens()) -> [EngineTrack] {
    songs.enumerated().map { index, song in
        EngineTrack(song: Song(id: "\(index)")) { start in
            let frame = start.frame(at: rate)
            opens.frames.append(frame)
            if opens.failing > 0 {
                opens.failing -= 1
                throw AudioFailure("The song stopped arriving.")
            }
            return MemorySource(song, rate: rate, start: Int(frame))
        }
    }
}

/// A tone at `frequency`, `seconds` long at `rate`, both channels.
func tone(_ frequency: Double, rate: Double, seconds: Double, level: Float = 0.5) -> [[Float]] {
    let one = (0..<Int(rate * seconds)).map { level * Float(sin(2 * Double.pi * frequency * Double($0) / rate)) }
    return [one, one]
}

func samples(_ buffer: AVAudioPCMBuffer, channel: Int) -> [Float] {
    Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength)))
}

/// Where two runs of samples first part (nil: they are the same, sample for sample). Expectations
/// compare through this, not `==` on the arrays: a failed `==` on two collections has Swift Testing
/// diff them, which is quadratic - two runs of 18,000 samples that differed took the whole test
/// process down with no message (ios.yml's first macOS run).
func firstDifference<A: Collection, B: Collection>(_ got: A, _ expected: B) -> String?
where A.Element == Float, B.Element == Float {
    var index = 0
    var left = got.makeIterator(), right = expected.makeIterator()
    while true {
        switch (left.next(), right.next()) {
        case (nil, nil): return nil
        case let (g?, e?):
            if g != e { return "sample \(index) of \(got.count) is \(g), expected \(e)" }
        case (nil, _?): return "\(got.count) samples, expected \(expected.count)"
        case (_?, nil): return "\(got.count) samples, expected \(expected.count)"
        }
        index += 1
    }
}

/// Mean square of each `block` frames - a picture of where the sound is, printed by the tests that
/// lay songs out in time.
func energyMap(_ samples: [Float], block: Int = 2_048) -> String {
    stride(from: 0, to: samples.count, by: block).map { start in
        let piece = samples[start..<min(start + block, samples.count)]
        let squares: [Float] = piece.map { (sample: Float) -> Float in sample * sample }
        let mean: Float = squares.reduce(0, +) / Float(piece.count)
        return "\(start):" + String(format: "%.4f", mean)
    }.joined(separator: " ")
}

@Suite(.serialized) struct EngineRenderTests {
    @Test func aJoinIsTheTwoSongsLaidEndToEnd() throws {
        let rate = 44_100.0
        let a = signal(frames: 13_230, channels: 2, seed: 0.1) // 0.3 s
        let b = signal(frames: 11_025, channels: 2, seed: 0.7) // 0.25 s
        let engine = try offlineEngine(rate: rate, channels: 2)
        let tracks = [a, b].enumerated().map { index, song in
            EngineTrack(song: Song(id: "\(index)")) { _ in MemorySource(song, rate: rate) }
        }
        engine.play(tracks, from: 0)
        engine.settle()
        let total = a[0].count + b[0].count
        let out = try engine.renderOffline(AVAudioFrameCount(total + 4096))
        // the node's start may be ramped (Apple DTS: "a short volume ramp"); the join is well past it
        let from = 4096
        for channel in 0..<2 {
            let expected = a[channel] + b[channel]
            let got = samples(out, channel: channel)
            var first: Int?
            for index in from..<total where got[index] != expected[index] {
                first = index
                break
            }
            #expect(first == nil, "channel \(channel): first difference at frame \(first ?? -1) (the join is at \(a[0].count))")
            #expect(got[total...].allSatisfy { $0 == 0 }, "silence after the last song")
            let ramp = (0..<from).map { abs(got[$0] - expected[$0]) }.max() ?? 0
            print("channel \(channel): largest difference in the first \(from) frames (the start ramp, if any): \(ramp)")
        }
    }

    @Test func positionFollowsTheSongHeard() throws {
        let rate = 48_000.0
        let a = signal(frames: 24_000, channels: 2, seed: 0.2)
        let b = signal(frames: 24_000, channels: 2, seed: 0.3)
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play([a, b].enumerated().map { index, song in
            EngineTrack(song: Song(id: "\(index)")) { _ in MemorySource(song, rate: rate) }
        }, from: 0)
        engine.settle()
        _ = try engine.renderOffline(36_000)
        engine.settle()
        let at = try #require(engine.position())
        #expect(at.index == 1)
        #expect(abs(at.seconds - 0.25) < 0.1)
    }

    @Test func anotherFormatPlaysOnItsOwnLaneAfterTheFirst() throws {
        let a = signal(frames: 4_410 * 3, channels: 2, seed: 0.4) // 0.3 s at 44.1
        let b = signal(frames: 9_600 * 3, channels: 2, seed: 0.5) // 0.3 s at 96
        let engine = try offlineEngine(rate: 48_000, channels: 2)
        engine.play([
            EngineTrack(song: Song(id: "cd")) { _ in MemorySource(a, rate: 44_100) },
            EngineTrack(song: Song(id: "hires")) { _ in MemorySource(b, rate: 96_000) },
        ], from: 0)
        engine.settle()
        let out = try engine.renderOffline(48_000)
        let left = samples(out, channel: 0)
        let energy = { (range: Range<Int>) -> Float in
            let squares: [Float] = left[range].map { (sample: Float) -> Float in sample * sample }
            return squares.reduce(0, +) / Float(range.count)
        }
        #expect(energy(2_000..<12_000) > 0.01, "the first song")
        #expect(energy(17_000..<27_000) > 0.01, "the second song, on its own lane")
        #expect(energy(40_000..<48_000) == 0, "silence after both")
    }

    // A short song in another format between two of the first: the third must wait for the first
    // lane to run out, not be laid straight after the first song, ahead of the one between. Rendered
    // a piece at a time so the buffers' completions (which let the third go on) are handled between.
    @Test func aShortSongInAnotherFormatPlaysBetweenNotOver() throws {
        let rate = 44_100.0
        let first = signal(frames: 22_050, channels: 2, seed: 0.15) // 0.5 s
        let between = signal(frames: 48_000, channels: 2, seed: 0.25) // 0.5 s at 96 kHz
        let third = signal(frames: 22_050, channels: 2, seed: 0.35) // 0.5 s
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play([
            EngineTrack(song: Song(id: "a")) { _ in MemorySource(first, rate: rate) },
            EngineTrack(song: Song(id: "b")) { _ in MemorySource(between, rate: 96_000) },
            EngineTrack(song: Song(id: "c")) { _ in MemorySource(third, rate: rate) },
        ], from: 0)
        engine.settle()
        var left: [Float] = []
        while left.count < 66_150 + 8_192 {
            left += samples(try engine.renderOffline(4_096), channel: 0)
            Thread.sleep(forTimeInterval: 0.01)
            engine.settle()
        }
        print("a short song between, energy by 2048 frames (the joins at 22050 and 44100): \(energyMap(left))")
        // past each node's start (it may be ramped) and the rate converter's tail
        let margin = 4_096
        #expect(firstDifference(left[margin..<22_050], first[0][margin...]) == nil, "the first song")
        let middle = (22_050 + margin)..<(44_100 - margin)
        let squares: [Float] = left[middle].map { (sample: Float) -> Float in sample * sample }
        let middleEnergy: Float = squares.reduce(0, +) / Float(middle.count)
        #expect(middleEnergy > 0.01, "the 96 kHz song, second")
        #expect(firstDifference(left[middle], third[0][(middle.lowerBound - 22_050)..<(middle.upperBound - 22_050)]) != nil,
                "not the third song laid straight after the first")
        #expect(firstDifference(left[(44_100 + margin)..<66_150], third[0][margin...]) == nil,
                "the third song, alone, from the moment the second ends")
        #expect(left[(66_150 + margin)...].allSatisfy { $0 == 0 }, "silence after the three")
    }

    // iOS stops the engine itself for a call (and a new route) before the app hears of it: the
    // node's clock is gone, so where the song was is the last position read while it played.
    @Test func aCallGoesOnFromWhereTheSongWas() throws {
        let rate = 48_000.0
        let song = signal(frames: 96_000, channels: 2, seed: 0.6) // 2 s
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
        engine.settle()
        _ = try engine.renderOffline(48_000)
        engine.settle()
        let before = try #require(engine.position()) // the app's ticker reads it every 0.5 s
        #expect(before.seconds > 0.9)
        engine.systemStopped(change: false) // the call: iOS stops the engine first...
        engine.pause() // ...then the app hears the interruption
        engine.settle()
        let held = try #require(engine.position())
        #expect(abs(held.seconds - before.seconds) < 0.001, "paused where the song was (\(held.seconds) s), not at its start")
        engine.resume()
        engine.settle()
        let out = try engine.renderOffline(24_000)
        let from = Int((held.seconds * rate).rounded())
        #expect(firstDifference(samples(out, channel: 0)[8_192..<9_192], song[0][(from + 8_192)..<(from + 9_192)]) == nil,
                "the song goes on from frame \(from)")
    }

    @Test func aNewRoutePlaysOnFromWhereItWas() throws {
        let rate = 48_000.0
        let song = signal(frames: 96_000, channels: 2, seed: 0.8)
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
        engine.settle()
        _ = try engine.renderOffline(24_000)
        engine.settle()
        let before = try #require(engine.position())
        engine.systemStopped(change: true) // AirPods connecting: stopped, then the change posted
        engine.settle()
        #expect(engine.phase == .playing)
        let at = try #require(engine.position())
        #expect(abs(at.seconds - before.seconds) < 0.001, "on from \(before.seconds) s, not \(at.seconds) s")
        let out = try engine.renderOffline(24_000)
        let from = Int((before.seconds * rate).rounded())
        #expect(firstDifference(samples(out, channel: 0)[8_192..<9_192], song[0][(from + 8_192)..<(from + 9_192)]) == nil)
    }

    // AirPods out: the engine's configuration change and the app's pause for the old device gone
    // arrive on different queues, in either order - the pause wins, nothing plays on the speaker.
    @Test func aRouteChangeThatPausesWinsOverPlayingOn() throws {
        let rate = 48_000.0
        let song = signal(frames: 96_000, channels: 2, seed: 0.9)
        let engine = try offlineEngine(rate: rate, channels: 2, changeSettle: 0.2)
        engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
        engine.settle()
        _ = try engine.renderOffline(24_000)
        engine.settle()
        let before = try #require(engine.position())
        engine.systemStopped(change: true) // the change first...
        engine.pause() // ...and the pause after it
        Thread.sleep(forTimeInterval: 0.4)
        engine.settle()
        #expect(engine.phase == .paused)
        let held = try #require(engine.position())
        #expect(abs(held.seconds - before.seconds) < 0.001)
    }

    // A song that failed (a stream cut off) plays again on play, rather than Loading for ever with
    // the output running; with nothing to play (after stop), play stays idle.
    @Test func playAfterAFailureOrAStop() throws {
        let rate = 48_000.0
        let opens = Opens()
        opens.failing = 1
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play(tracksFromWhereAsked([signal(frames: 48_000, channels: 2, seed: 0.3)], rate: rate, opens: opens), from: 0)
        engine.settle()
        guard case .failed = engine.phase else {
            Issue.record("expected the failure, got \(engine.phase)")
            return
        }
        engine.resume()
        engine.settle()
        #expect(engine.phase == .playing)
        #expect(opens.frames == [0, 0])
        engine.stop()
        engine.resume()
        engine.settle()
        #expect(engine.phase == .idle)
    }

    // A seek before the song has been heard (paused after a skip, or still loading) is seconds at
    // the file's own rate, not 44.1 kHz's.
    @Test func aSeekBeforeTheSongIsHeardIsAtItsOwnRate() throws {
        let rate = 192_000.0
        let opens = Opens()
        let engine = try offlineEngine(rate: 48_000, channels: 2)
        let songs = [signal(frames: 192_000, channels: 2, seed: 0.1), signal(frames: 192_000, channels: 2, seed: 0.2)]
        engine.play(tracksFromWhereAsked(songs, rate: rate, opens: opens), from: 0)
        engine.pause()
        engine.skip(to: 1) // loaded while paused: not heard yet
        engine.seek(to: 0.5)
        engine.settle()
        let expected: Int64 = 96_000
        #expect(opens.frames.last == expected)
        #expect(engine.position()?.seconds == 0.5)
    }

    // The one lossy step in the chain: the main mixer converting a file's rate to the output's
    // (48 kHz here, as on the speaker and AirPods). Measured and printed, so the quality is a number
    // (notes/ios.md); the bounds only catch a conversion that is broken outright.
    @Test func theMixersRateConversionMeasured() throws {
        for rate in [192_000.0, 96_000.0, 44_100.0] {
            func render(_ song: [[Float]]) throws -> [Float] {
                let engine = try offlineEngine(rate: 48_000, channels: 2)
                engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
                engine.settle()
                return samples(try engine.renderOffline(48_000), channel: 0)
            }
            // 1 kHz through it: what isn't 1 kHz afterwards is the conversion's noise and distortion
            let out = try render(tone(1_000, rate: rate, seconds: 1))
            let window = 9_600..<(9_600 + 24_000) // whole periods, past any start ramp
            var s = 0.0, c = 0.0
            for i in window {
                let w = 2 * Double.pi * 1_000 * Double(i) / 48_000
                s += Double(out[i]) * sin(w)
                c += Double(out[i]) * cos(w)
            }
            s *= 2 / Double(window.count)
            c *= 2 / Double(window.count)
            var signalPower = 0.0, residual = 0.0
            for i in window {
                let w = 2 * Double.pi * 1_000 * Double(i) / 48_000
                let fit = s * sin(w) + c * cos(w)
                signalPower += fit * fit
                residual += (Double(out[i]) - fit) * (Double(out[i]) - fit)
            }
            let snr = 10 * log10(signalPower / max(residual, 1e-30))
            var line = "rate conversion \(Int(rate)) -> 48000 Hz: 1 kHz comes out \(String(format: "%.1f", snr)) dB above what else"
            #expect(snr > 60, "\(line)")
            if rate > 48_000 {
                // a 30 kHz tone can't be at 48 kHz: what is left of it is aliasing
                let alias = try render(tone(30_000, rate: rate, seconds: 1))
                let rms = sqrt(window.map { Double(alias[$0]) * Double(alias[$0]) }.reduce(0, +) / Double(window.count))
                let left = 20 * log10(max(rms, 1e-12) / (0.5 / 2.0.squareRoot()))
                line += "; a 30 kHz tone is left at \(String(format: "%.1f", left)) dB"
                #expect(left < -40, "\(line)")
            }
            print(line)
        }
    }

    @Test func aTwentyFourBitFileDecodesExactly() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("deadwax-24-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = 4_800
        let values: [Int32] = (0..<frames).map { Int32(($0 * 104_729) % 16_000_000) - 8_000_000 }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 96_000.0,
                                       AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 24,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames))!
            for index in 0..<frames { buffer.floatChannelData![0][index] = Float(values[index]) / 8_388_608 }
            buffer.frameLength = AVAudioFrameCount(frames)
            try file.write(from: buffer)
        }
        let source = try FileSource(url: url)
        #expect(source.format?.sampleRate == 96_000)
        var got: [Float] = []
        while case .frames(let buffer) = try source.read(maxFrames: 1000) { got += samples(buffer, channel: 0) }
        #expect(got.count == frames)
        #expect(firstDifference(got, values.map { Float($0) / 8_388_608 }) == nil)
    }

    @Test func aStreamDecodesWhatTheFileDoes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("deadwax-\(UUID().uuidString).flac")
        defer { try? FileManager.default.removeItem(at: url) }
        let song = signal(frames: 44_100, channels: 2, seed: 0.9)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: 44_100.0,
                                       AVNumberOfChannelsKey: 2, AVEncoderBitDepthHintKey: 16]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 44_100)!
            for channel in 0..<2 {
                song[channel].withUnsafeBufferPointer { buffer.floatChannelData![channel].update(from: $0.baseAddress!, count: 44_100) }
            }
            buffer.frameLength = 44_100
            try file.write(from: buffer)
        } catch {
            print("This Mac can't write a FLAC to test with (\(error)); the stream test is left out.")
            return
        }
        let info = FLACStreamInfo.parse(try Data(contentsOf: url))
        #expect(info?.sampleRate == 44_100)
        #expect(info?.totalSamples == 44_100)

        func decode(_ source: PCMSource) throws -> [Float] {
            var left: [Float] = []
            var waits = 0
            while true {
                switch try source.read(maxFrames: 4_410) {
                case .frames(let buffer): left += samples(buffer, channel: 0)
                case .waiting:
                    waits += 1
                    if waits > 100_000 { return left }
                case .end: return left
                }
            }
        }
        let whole = try decode(FileSource(url: url))
        #expect(firstDifference(whole, song[0]) == nil, "the file decodes to what was written")
        let data = try Data(contentsOf: url)
        let streamed = try decode(StreamSource(bytes: GrowingBytes(data, step: 1_000), typeHint: kAudioFileFLACType))
        #expect(firstDifference(streamed, whole) == nil, "the stream decodes to what the file does")
        let sought = try decode(StreamSource(bytes: GrowingBytes(data, step: 7_000), typeHint: kAudioFileFLACType,
                                             start: .frame(10_000, rate: 44_100)))
        #expect(firstDifference(sought, whole[10_000...]) == nil, "a seek before the bytes arrive drops exactly the frames before it")
    }
}
#endif
