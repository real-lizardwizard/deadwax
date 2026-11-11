#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import DeadwaxCore
import Foundation
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
func render(_ engine: PlaybackEngine, frames: Int, piece: Int = 4_096, before: ((Int) -> Void)? = nil) throws -> [Float] {
    var out: [Float] = []
    while out.count < frames {
        before?(out.count)
        out += samples(try engine.renderOffline(AVAudioFrameCount(min(piece, frames - out.count))), channel: 0)
        Thread.sleep(forTimeInterval: 0.01)
        engine.settle()
    }
    return out
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
