#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// What Phase 1's render tests share (the Phase 0 helpers are at the top of EngineRenderTests.swift).

/// A gain in dB as the engine's sources get it: one Float, computed in Double and rounded once (the
/// app's rule, Core's `gainMultiplier` - written out here so these tests don't lean on another file).
func multiplier(_ db: Double) -> Float { Float(pow(10.0, db / 20)) }

/// An offline engine as `offlineEngine` makes it, keeping only `ahead` seconds scheduled (so a song's
/// next is decoded and committed in its last seconds, as on the phone) and hearing `latency` behind the
/// render.
func liveEngine(rate: Double, channels: AVAudioChannelCount = 2, ahead: Double = 0.3, latency: Double = 0,
                changeSettle: Double = 0) throws -> PlaybackEngine {
    var settings = PlaybackEngine.Settings()
    settings.offline = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)
    settings.aheadSeconds = ahead
    settings.startSeconds = 0
    settings.bufferSeconds = 0.1
    settings.changeSettleSeconds = changeSettle
    let engine = try PlaybackEngine(settings: settings)
    engine.latency = { latency }
    return engine
}

/// Renders `frames` frames a `piece` at a time, the engine's buffer completions handled between (as
/// they are on the phone while it plays). `before` is called with the frames rendered so far ahead of
/// each piece. Channel 0.
func render(_ engine: PlaybackEngine, frames: Int, piece: Int = 4_096, before: ((Int) -> Void)? = nil,
            sourceLocation: SourceLocation = #_sourceLocation) throws -> [Float] {
    var out: [Float] = []
    while out.count < frames {
        before?(out.count)
        out += samples(try engine.renderOffline(AVAudioFrameCount(min(piece, frames - out.count))), channel: 0)
        try completionsHandled(engine, sourceLocation: sourceLocation)
    }
    return out
}

/// Waits (bounded) until the engine has handled the completion of every buffer the render has passed,
/// then requires it. They come on AVAudioEngine's own thread after the render, at no set time: a sleep
/// of 10 ms was enough on this Mac, and on ios.yml's 3-core runner, with Core's 450 tests in the same
/// process, it wasn't - the next piece rendered before they came, nothing new was on the node in time,
/// and the render was silent where the next song should have joined (notes/ios.md "The engine's tests
/// under load"). On the phone they come long before the render needs them, 2 s ahead; this is that,
/// made certain.
func completionsHandled(_ engine: PlaybackEngine, seconds: Double = 5,
                        sourceLocation: SourceLocation = #_sourceLocation) throws {
    let until = Date().addingTimeInterval(seconds)
    while engine.completionsDue > 0, Date() < until { Thread.sleep(forTimeInterval: 0.001) }
    try #require(engine.completionsDue == 0, "the completions of what was rendered, handled within \(seconds) s",
                 sourceLocation: sourceLocation)
}

/// The engine's trace, each line with the seconds since the test began - printed when a test fails, to
/// say what the engine did and when.
final class TraceLines: CustomStringConvertible {
    private let lock = NSLock()
    private let began = Date()
    private var lines: [String] = []

    func add(_ line: String) {
        let at = String(format: "%.4f", Date().timeIntervalSince(began))
        lock.withLock { lines.append("\(at) s: \(line)") }
    }

    var description: String { lock.withLock { lines.joined(separator: "\n") } }
}

/// Where a render that should have been `expected` from its first frame begins instead: silent
/// throughout, or silent (or other) until frame N where `expected` begins - what tells a stopped output
/// from a node that started late.
func whereItBegins(_ got: [Float], _ expected: [Float]) -> String {
    guard let sound = got.firstIndex(where: { $0 != 0 }) else { return "the render is silent throughout" }
    let probe = 64
    guard expected.count >= probe,
          let at = (0...(got.count - probe)).first(where: { start in (0..<probe).allSatisfy { got[start + $0] == expected[$0] } }) else {
        return "the first sound at frame \(sound), and the song's first frames nowhere"
    }
    return "the first sound at frame \(sound); the song's first frames at frame \(at)"
}

/// Every channel of a render, at once.
func renderAll(_ engine: PlaybackEngine, frames: Int) throws -> [[Float]] {
    let out = try engine.renderOffline(AVAudioFrameCount(frames))
    return (0..<Int(out.format.channelCount)).map { samples(out, channel: $0) }
}

/// Bytes that arrive only when the test says (`release`) - a stream whose bytes haven't come yet.
final class GatedBytes: ByteSource {
    let all: Data
    private let lock = NSLock()
    private var released = 0
    private var failed: AudioFailure?

    init(_ data: Data) {
        all = data
    }

    func release(_ count: Int? = nil) {
        lock.withLock { released = min(count ?? all.count, all.count) }
    }

    func cut(_ failure: AudioFailure) {
        lock.withLock { failed = failure }
    }

    var isComplete: Bool { lock.withLock { !all.isEmpty && released >= all.count } }
    var failure: AudioFailure? { lock.withLock { failed } }

    func bytes(at offset: Int, count: Int) -> Data {
        lock.withLock {
            guard offset < released else { return Data() }
            return all.subdata(in: offset..<min(offset + count, released))
        }
    }
}

/// A song held in memory whose frames past `arrived` haven't come yet - a stream behind, decoded: `.waiting`
/// there until `release`.
final class GatedFrames: PCMSource {
    let samples: [[Float]]
    let format: AVAudioFormat?
    private let lock = NSLock()
    private var at = 0
    private var arrived: Int

    init(_ samples: [[Float]], rate: Double, arrived: Int) {
        self.samples = samples
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                               channels: AVAudioChannelCount(samples.count), interleaved: false)
        self.arrived = arrived
    }

    /// The rest of the song has arrived.
    func release() { lock.withLock { arrived = samples[0].count } }

    func read(maxFrames: AVAudioFrameCount) throws -> PCMRead {
        let total = samples[0].count
        if at >= total { return .end }
        let count = min(Int(maxFrames), lock.withLock { arrived } - at)
        if count <= 0 { return .waiting }
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

/// A source that says nothing has arrived, until `fail` - then throws it at the next read.
final class FailingSource: PCMSource {
    let failure: AudioFailure
    let format: AVAudioFormat?

    init(_ failure: AudioFailure, rate: Double) {
        self.failure = failure
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false)
    }

    func read(maxFrames: AVAudioFrameCount) throws -> PCMRead { throw failure }
    func close() {}
}

/// `song` (16-bit values) as a FLAC file at `rate` - or nil, with a line printed, when this Mac can't
/// write FLAC (as `aStreamDecodesWhatTheFileDoes` allows).
func flacFile(_ song: [[Float]], rate: Double) -> URL? {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("deadwax-\(UUID().uuidString).flac")
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: rate,
                                   AVNumberOfChannelsKey: song.count, AVEncoderBitDepthHintKey: 16]
    do {
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = song[0].count
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames))!
        for channel in 0..<song.count {
            song[channel].withUnsafeBufferPointer { buffer.floatChannelData![channel].update(from: $0.baseAddress!, count: frames) }
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        try file.write(from: buffer)
    } catch {
        print("This Mac can't write a FLAC to test with (\(error)); the test is left out.")
        try? FileManager.default.removeItem(at: url)
        return nil
    }
    return url
}

/// Every sample a source gives, channel 0, waiting through `.waiting` (bounded).
func decodeAll(_ source: PCMSource, maxFrames: AVAudioFrameCount = 4_410) throws -> [Float] {
    var out: [Float] = []
    var waits = 0
    while true {
        switch try source.read(maxFrames: maxFrames) {
        case .frames(let buffer): out += samples(buffer, channel: 0)
        case .waiting:
            waits += 1
            if waits > 100_000 { return out }
        case .end: return out
        }
    }
}

/// Waits (a little at a time, at most `seconds`) until `done` - for what the engine does on its own
/// clock offline: a stream's retries.
func waitFor(_ engine: PlaybackEngine, seconds: Double = 5, _ done: () -> Bool) {
    let until = Date().addingTimeInterval(seconds)
    while !done(), Date() < until {
        Thread.sleep(forTimeInterval: 0.02)
        engine.settle()
    }
}
#endif
