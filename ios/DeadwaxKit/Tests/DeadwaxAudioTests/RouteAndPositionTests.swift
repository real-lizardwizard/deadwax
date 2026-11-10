#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// One heard position (the output's latency behind the render), new routes and media services reset
// going on from the frame heard, a seek into what hasn't arrived, and Debug's numbers - offline.
extension EngineRenderTests {
    @Test func positionIsWhatIsHeard() throws {
        let rate = 48_000.0
        let a = signal(frames: 48_000, channels: 2, seed: 0.14)
        let b = signal(frames: 48_000, channels: 2, seed: 0.24)
        // half a second behind the render (AirPlay is about 2 s)
        let engine = try liveEngine(rate: rate, ahead: 0.3, latency: 0.5)
        engine.play(tracksFromWhereAsked([a, b], rate: rate), from: 0)
        engine.settle()
        var readings: [Int: EnginePosition] = [:]
        var published: [Int: Int?] = [:]
        _ = try render(engine, frames: 81_600, piece: 4_800) { done in
            readings[done] = engine.position()
            published[done] = engine.stateNow.key
        }
        // the render at 14400: the ear at 14400 - 24000, before the song's start - its first frame
        #expect(readings[14_400]?.key == 0 && readings[14_400]?.seconds == 0)
        #expect(readings[38_400]?.key == 0 && readings[38_400]?.seconds == 0.3, "38400 rendered, 14400 heard")
        // the render past the join at 48000, the ear not yet
        #expect(readings[52_800]?.key == 0 && readings[52_800]?.seconds == 0.6)
        #expect(published[52_800] == 0, "the lock screen still names A: it is still heard")
        // the ear past the join
        #expect(readings[76_800]?.key == 1 && readings[76_800]?.index == 1 && readings[76_800]?.seconds == 0.1)
        #expect(published[76_800] == 1, "said once heard")
    }

    @Test func aPauseGoesOnFromWhatWasHeard() throws {
        let rate = 48_000.0
        let song = signal(frames: 96_000, channels: 2, seed: 0.74)
        let engine = try liveEngine(rate: rate, ahead: 60, latency: 0.1)
        engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
        engine.settle()
        _ = try engine.renderOffline(24_000)
        engine.settle()
        engine.pause()
        engine.settle()
        let held = try #require(engine.position())
        #expect(held.seconds == 0.4, "24000 rendered, 4800 of them not yet heard")
        engine.resume()
        engine.settle()
        let out = try engine.renderOffline(24_000)
        #expect(firstDifference(samples(out, channel: 0)[8_192..<9_192], song[0][(19_200 + 8_192)..<(19_200 + 9_192)]) == nil,
                "on from 19200: what was rendered and never heard is played")
    }

    @Test func aNewRouteGoesOnFromTheFrameHeard() throws {
        let rate = 48_000.0
        let song = signal(frames: 96_000, channels: 2, seed: 0.84)
        let engine = try liveEngine(rate: rate, ahead: 60, latency: 0.1)
        engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
        engine.settle()
        _ = try engine.renderOffline(24_000)
        engine.settle()
        _ = engine.position() // the app's ticker reads it every 0.5 s
        engine.systemStopped(change: true) // AirPods connecting: stopped, then the change posted
        engine.settle()
        #expect(engine.phase == .playing)
        #expect(engine.position()?.seconds == 0.4)
        let out = try engine.renderOffline(24_000)
        #expect(firstDifference(samples(out, channel: 0)[8_192..<9_192], song[0][(19_200 + 8_192)..<(19_200 + 9_192)]) == nil,
                "on from the frame heard, 19200 - the old route's 4800 frames went with it")
    }

    @Test func aNewRouteKeepsAnEndedQueueEnded() throws {
        let rate = 48_000.0
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play(tracksFromWhereAsked([signal(frames: 4_800, channels: 2, seed: 0.5)], rate: rate), from: 0)
        engine.settle()
        _ = try render(engine, frames: 12_288)
        #expect(engine.phase == .ended)
        engine.systemStopped(change: true)
        engine.settle()
        #expect(engine.phase == .ended, "play after it still starts the queue's own rule")
        let failing = Opens()
        failing.failing = 1
        let failed = try offlineEngine(rate: rate, channels: 2)
        failed.play(tracksFromWhereAsked([signal(frames: 4_800, channels: 2, seed: 0.5)], rate: rate, opens: failing), from: 0)
        failed.settle()
        failed.systemStopped(change: true)
        failed.settle()
        #expect(failed.stateNow.failure?.kind == .network, "a failure keeps its words through a new route")
    }

    @Test func aMediaResetGoesOnInANewEngine() throws {
        let rate = 48_000.0
        let song = signal(frames: 96_000, channels: 2, seed: 0.94)
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
        engine.settle()
        _ = try engine.renderOffline(24_000)
        engine.settle()
        let before = try #require(engine.position())
        engine.rebuild() // the old engine is dead: nothing is asked of it
        engine.settle()
        #expect(engine.phase == .playing)
        #expect(engine.position()?.seconds == before.seconds)
        let out = try engine.renderOffline(24_000)
        let from = Int((before.seconds * rate).rounded())
        #expect(firstDifference(samples(out, channel: 0)[8_192..<9_192], song[0][(from + 8_192)..<(from + 9_192)]) == nil,
                "on from \(from) in the new engine")
    }

    // A seek into what hasn't arrived waits (Loading, the position the target), and lands on the very
    // frame once the bytes come.
    @Test func aSeekPastWhatHasArrivedWaitsThenLandsExactly() throws {
        let rate = 44_100.0
        let song = signal(frames: 88_200, channels: 2, seed: 0.19)
        guard let url = flacFile(song, rate: rate) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let whole = try decodeAll(FileSource(url: url))
        let gate = GatedBytes(try Data(contentsOf: url))
        let track = EngineTrack(key: 0, audio: "s|off", song: Song(id: "s")) { start in
            try StreamSource(bytes: gate, typeHint: kAudioFileFLACType, start: start)
        }
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play([track], from: 0)
        engine.seek(to: 0.75)
        engine.settle()
        #expect(engine.phase == .loading)
        #expect(engine.position()?.seconds == 0.75, "the scrubber holds the target")
        gate.release()
        waitFor(engine) { engine.phase == .playing }
        #expect(engine.phase == .playing)
        let out = samples(try engine.renderOffline(22_050), channel: 0)
        let from = 33_075 // 0.75 s at 44.1 kHz
        #expect(firstDifference(out[4_096..<22_050], whole[(from + 4_096)..<(from + 22_050)]) == nil, "from frame \(from) exactly")
    }

    // A seek deep into bytes that have arrived: each read drops at most 64 decodes' worth and says
    // `busy`, so the engine reads again at once instead of after its retry delay.
    @Test func aDeepSeekInArrivedBytesSaysBusy() throws {
        let rate = 44_100.0
        let song = signal(frames: 529_200, channels: 2, seed: 0.29) // 12 s
        guard let url = flacFile(song, rate: rate) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        let all = GatedBytes(data)
        all.release()
        let source = try StreamSource(bytes: all, typeHint: kAudioFileFLACType, start: .frame(441_000, rate: rate))
        var waits = 0
        var first: [Float]?
        while first == nil, waits < 100 {
            switch try source.read(maxFrames: 4_410) {
            case .waiting:
                #expect(source.busy, "a .waiting while dropping arrived frames is busy")
                waits += 1
            case .frames(let buffer): first = samples(buffer, channel: 0)
            case .end: Issue.record("ended before the seek's frame")
            }
        }
        #expect(waits >= 1, "64 x 4410 = 282240 frames per read, short of 441000")
        let whole = try decodeAll(FileSource(url: url))
        #expect(first.map { firstDifference($0, whole[441_000..<(441_000 + $0.count)]) } == .some(nil),
                "the first frames are 441000's")
        let nothing = try StreamSource(bytes: GatedBytes(data), typeHint: kAudioFileFLACType, start: .frame(441_000, rate: rate))
        guard case .waiting = try nothing.read(maxFrames: 4_410) else {
            Issue.record("nothing has arrived: it waits")
            return
        }
        #expect(!nothing.busy, "waiting for bytes is not busy")
    }

    @Test func debugSaysTheLanesAndTheOutput() throws {
        let engine = try liveEngine(rate: 48_000, ahead: 0.5, latency: 0.02)
        engine.play(tracksFromWhereAsked([signal(frames: 88_200, channels: 2, seed: 0.33)], rate: 44_100), from: 0)
        engine.settle()
        _ = try render(engine, frames: 9_600)
        let debug = engine.debug()
        #expect(debug.lanes.count == 1)
        let lane = try #require(debug.lanes.first)
        #expect(lane.rate == 44_100 && lane.channels == 2 && lane.nodeRate == 48_000 && lane.converting)
        #expect(lane.started && lane.heard && lane.pendingBuffers > 0)
        #expect(lane.aheadSeconds > 0.3 && lane.aheadSeconds < 1, "about the half second kept ahead: \(lane.aheadSeconds)")
        #expect(debug.outputRunning && !debug.asleep && debug.phase == .playing && debug.key == 0 && debug.feedKey == 0)
        #expect(debug.latency == 0.02 && debug.outputRate == 48_000)
    }
}
#endif
