#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// Phase 2 (notes/ios-specs/phase2-downloads.md 7.3, 8.4, 9): a downloaded copy is the file, played bit for bit as a
// stream of it is - through the same FileSource a complete stream-cache copy takes, gapless and at the same level - and
// the verifier hashes exactly what playback decodes.

/// The verifier's FLACs (make-test-album.py --verifier-fixtures; tests/test_ios_install.py decodes them with libsndfile
/// for an independent reference). The checkout's first, else the test bundle's copy.
private func fixture(_ name: String) throws -> URL {
    let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/verifier/\(name)")
    if FileManager.default.fileExists(atPath: checkout.path) { return checkout }
    if let bundled = Bundle.module.resourceURL?.appendingPathComponent("Fixtures/verifier/\(name)"),
       FileManager.default.fileExists(atPath: bundled.path) {
        return bundled
    }
    throw AudioFailure("Fixtures/verifier/\(name) is in neither the checkout nor the test bundle")
}

/// A downloads folder of its own, as the App lays one out (`music/<id>.<suffix>`), deleted after.
private func withDownloads(_ body: (URL) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("deadwax-downloads-\(UUID().uuidString)/music", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
    try body(folder)
}

/// `song` written as a 16-bit 44.1 kHz FLAC by this Mac's own encoder - nil (the test says why and is left out) on a Mac
/// that can't write one.
private func writeFLAC(_ song: [[Float]], to url: URL) -> Bool {
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: 44_100.0,
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
        return true
    } catch {
        print("This Mac can't write a FLAC to test with (\(error)); left out.")
        return false
    }
}

/// One entry whose source the test makes, at `factor` (the app's LevelStore wraps every open the same way).
private func track(key: Int, id: String, factor: Float?, _ open: @escaping () throws -> PCMSource) -> EngineTrack {
    EngineTrack(key: key, audio: EngineTrack.audio(songID: id, level: factor.map { "\($0)" }), song: Song(id: id)) { _ in
        GainedSource.wrap(try open(), factor: factor)
    }
}

/// Every channel of `tracks` played from the first and rendered offline, `frames` long.
private func rendered(_ tracks: [EngineTrack], frames: Int) throws -> [[Float]] {
    let engine = try offlineEngine(rate: 44_100, channels: 2)
    engine.play(tracks, from: 0)
    engine.settle()
    try #require(engine.phase == .playing && engine.outputRunning)
    return try renderAll(engine, frames: frames)
}

@Suite(.serialized) struct DownloadedCopyTests {
    @Test func aDownloadedCopyRendersTheSamplesItsStreamDoes() throws {
        try withDownloads { music in
            let url = music.appendingPathComponent("song-1.flac")
            let song = signal(frames: 30_000, channels: 2, seed: 0.42)
            guard writeFLAC(song, to: url) else { return }
            let bytes = try Data(contentsOf: url)
            for factor in [nil, multiplier(-6.02)] as [Float?] {
                let copy = try rendered([track(key: 0, id: "song-1", factor: factor) { try FileSource(url: url) }],
                                        frames: 34_096)
                let stream = try rendered([track(key: 0, id: "song-1", factor: factor) {
                    try StreamSource(bytes: GrowingBytes(bytes, step: 16_384), typeHint: kAudioFileFLACType)
                }], frames: 34_096)
                for channel in 0..<2 {
                    #expect(firstDifference(copy[channel], stream[channel]) == nil,
                            "channel \(channel) at \(factor.map { "\($0)" } ?? "Off"): the copy plays what its stream does")
                    // past the node's start (which may be ramped), each sample is the song's - times the gain
                    let expected = song[channel].map { $0 * (factor ?? 1) }
                    #expect(firstDifference(copy[channel][4_096..<30_000], expected[4_096...]) == nil,
                            "channel \(channel): bit for bit, at the gain decided")
                }
            }
        }
    }

    @Test func anAlbumOfDownloadedCopiesJoinsSampleExact() throws {
        try withDownloads { music in
            let a = signal(frames: 13_230, channels: 2, seed: 0.1)
            let b = signal(frames: 11_025, channels: 2, seed: 0.7)
            let urls = [music.appendingPathComponent("a.flac"), music.appendingPathComponent("b.flac")]
            guard writeFLAC(a, to: urls[0]), writeFLAC(b, to: urls[1]) else { return }
            let tracks = urls.enumerated().map { index, url in
                track(key: index, id: url.lastPathComponent, factor: nil) { try FileSource(url: url) }
            }
            let total = a[0].count + b[0].count
            let out = try rendered(tracks, frames: total + 4_096)
            for channel in 0..<2 {
                let expected = a[channel] + b[channel]
                #expect(firstDifference(out[channel][4_096..<total], expected[4_096...]) == nil,
                        "channel \(channel): the join (at \(a[0].count)) is the two songs end to end")
                #expect(out[channel][total...].allSatisfy { $0 == 0 }, "silence after the last song")
            }
        }
    }

    @Test func theVerifierHashesWhatPlaybackDecodes() throws {
        func check(_ name: String) throws -> FLACVerifier.Outcome {
            let url = try fixture(name)
            let info = FLACStreamInfo.parse(try Data(contentsOf: url))
            return FLACVerifier.verify(url, info: info)
        }
        #expect(try check("verify-16-44k.flac") == .matched, "16-bit 44.1 kHz")
        #expect(try check("verify-24-96k.flac") == .matched, "24-bit 96 kHz")
        #expect(try check("verify-24-96k-changed.flac") == .mismatch, "one sample changed, every frame's CRC right")
        #expect(try check("verify-16-44k-no-md5.flac") == .bySize, "no fingerprint: its size alone")
        // what the verifier hashes is what FileSource plays: the same decoder, the same samples
        let url = try fixture("verify-24-96k.flac")
        let source = try FileSource(url: url)
        var played: [[Float]] = [[], []]
        while case .frames(let buffer) = try source.read(maxFrames: 1_000) {
            for channel in 0..<2 { played[channel] += samples(buffer, channel: channel) }
        }
        let info = try #require(FLACStreamInfo.parse(try Data(contentsOf: url)))
        var hash = MD5()
        hash.update(FLACMD5.pack(played, bits: 24))
        #expect(hash.finish() == info.md5, "the samples playback decodes hash to STREAMINFO's MD5")
    }

    @Test func whatTheVerifierCantReadOrIsToldToStop() throws {
        try withDownloads { music in
            let bad = music.appendingPathComponent("bad.flac")
            let good = try Data(contentsOf: try fixture("verify-16-44k.flac"))
            // STREAMINFO whole, the frames gone: iOS can't decode it
            try (good.prefix(42) + Data(repeating: 0x55, count: 4_000)).write(to: bad)
            let info = FLACStreamInfo.parse(good)
            if case .unreadable = FLACVerifier.verify(bad, info: info) {} else {
                // AudioToolbox may decode nothing rather than fail: then the sound can't match
                #expect(FLACVerifier.verify(bad, info: info) == .mismatch)
            }
            #expect(FLACVerifier.verify(try fixture("verify-24-96k.flac"), info: FLACStreamInfo.parse(try Data(contentsOf: try fixture("verify-24-96k.flac"))),
                                        stop: { true }) == .stopped)
            #expect(FLACVerifier.verify(bad, info: nil) == .bySize, "not a FLAC: by size")
        }
    }
}
#endif
