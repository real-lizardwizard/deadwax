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

    // A media reset while the queue has ended or failed leaves it so, as a new route does: play after the
    // end starts the song again (not the end frame, which would end at once), and a failure keeps its words.
    @Test func aMediaResetKeepsAnEndedQueueEnded() throws {
        let rate = 48_000.0
        let song = signal(frames: 24_000, channels: 2, seed: 0.55)
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
        engine.settle()
        _ = try render(engine, frames: 32_768)
        #expect(engine.phase == .ended)
        engine.rebuild()
        engine.settle()
        #expect(engine.phase == .ended, "not paused at the end frame")
        engine.resume()
        engine.settle()
        #expect(engine.phase == .playing)
        let out = samples(try engine.renderOffline(24_000), channel: 0)
        #expect(firstDifference(out[4_096..<24_000], song[0][4_096...]) == nil, "the song again, from its start")

        let failing = Opens()
        failing.failing = 1
        let failed = try offlineEngine(rate: rate, channels: 2)
        failed.play(tracksFromWhereAsked([song], rate: rate, opens: failing), from: 0)
        failed.settle()
        #expect(failed.stateNow.failure?.kind == .network)
        failed.rebuild()
        failed.settle()
        #expect(failed.stateNow.failure?.kind == .network, "a failure keeps its words through a media reset")
        guard case .failed = failed.phase else {
            Issue.record("a failure stays a failure: \(failed.phase)")
            return
        }
    }

    // A skip while paused opens nothing, so nothing knows the new song's rate yet: the Hi-res readout
    // must not say the song before's for it. A pause keeps its own song's.
    @Test func aPausedSkipDoesNotSayTheRateOfTheSongBefore() throws {
        let cd = signal(frames: 44_100, channels: 2, seed: 0.4)
        let hiRes = signal(frames: 96_000, channels: 2, seed: 0.5)
        let engine = try offlineEngine(rate: 48_000, channels: 2)
        engine.play([entry(cd, rate: 44_100, key: 0, id: "cd"), entry(hiRes, rate: 96_000, key: 1, id: "hires")], from: 0)
        engine.settle()
        _ = try engine.renderOffline(4_096)
        engine.settle()
        #expect(engine.stateNow.fileRate == 44_100)
        engine.pause()
        engine.settle()
        #expect(engine.stateNow.fileRate == 44_100 && engine.stateNow.fileChannels == 2, "paused on it: still its rate")
        engine.skip(to: 1)
        engine.settle()
        #expect(engine.stateNow.key == 1)
        #expect(engine.stateNow.fileRate == nil && engine.stateNow.fileChannels == nil, "not known until play opens it")
        engine.resume()
        engine.settle()
        #expect(engine.stateNow.fileRate == 96_000, "opened: its own")
        engine.stop()
        engine.settle()
        #expect(engine.stateNow.fileRate == nil, "stopped: nothing")
    }

    // The engine itself reads a deep seek again at once while its source says `busy` (arrived bytes still
    // being dropped), never after the wait for a stream with nothing yet - which is made 30 s here, so
    // only `busy` can bring the seek's first frames in time.
    @Test func theEngineReadsADeepSeekAgainAtOnce() throws {
        let rate = 44_100.0
        let song = signal(frames: 529_200, channels: 2, seed: 0.39) // 12 s
        guard let url = flacFile(song, rate: rate) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let whole = try decodeAll(FileSource(url: url))
        let gate = GatedBytes(try Data(contentsOf: url))
        gate.release()
        let track = EngineTrack(key: 0, audio: "s|off", song: Song(id: "s")) { start in
            try StreamSource(bytes: gate, typeHint: kAudioFileFLACType, start: start)
        }
        var settings = PlaybackEngine.Settings()
        settings.offline = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false)
        settings.startSeconds = 0
        settings.bufferSeconds = 0.1
        settings.retrySeconds = 30
        let engine = try PlaybackEngine(settings: settings)
        engine.play([track], from: 0, at: 10) // frame 441000: two reads of 64 x 4410 dropped frames, the first busy
        waitFor(engine, seconds: 5) { engine.phase == .playing }
        #expect(engine.phase == .playing, "no 30 s wait: a busy source is read again at once")
        let out = samples(try engine.renderOffline(22_050), channel: 0)
        let from = 441_000
        #expect(firstDifference(out[4_096..<22_050], whole[(from + 4_096)..<(from + 22_050)]) == nil, "from frame \(from) exactly")
    }

    // The entries played are forgotten a second and the latency behind the render, never up to it. A lane
    // holds three entries once the render is 0.3 s past a join (the song after next begun, 0.3 s kept
    // ahead); with the ear half a second behind, it is still 0.2 s back in the song before then - and
    // must find it there, at every reading.
    @Test func aSongJustPassedByTheRenderIsStillHeard() throws {
        let rate = 48_000.0
        let songs = (0..<4).map { signal(frames: 19_200, channels: 2, seed: 0.15 + Float($0) / 10) } // 0.4 s each, one lane
        let engine = try liveEngine(rate: rate, ahead: 0.3, latency: 0.5)
        engine.play(tracksFromWhereAsked(songs, rate: rate), from: 0)
        engine.settle()
        var readings: [Int: EnginePosition] = [:]
        _ = try render(engine, frames: 76_800, piece: 4_800) { done in readings[done] = engine.position() }
        #expect(readings.count == 16)
        for (rendered, at) in readings.sorted(by: { $0.key < $1.key }) {
            let heard = max(rendered - 24_000, 0)
            let (key, frame) = (heard / 19_200, heard % 19_200)
            #expect(at.key == key && at.seconds == Double(frame) / rate,
                    "rendered \(rendered), heard \(heard): song \(key) at \(frame), not \(at)")
        }
    }

    // The queue's end stops the output only once its last samples have been heard (the latency, and a
    // tenth of a second): stopped at once, the ear would lose the last of the album.
    @Test func theQueuesEndIsHeardBeforeTheOutputStops() throws {
        let rate = 48_000.0
        let engine = try liveEngine(rate: rate, ahead: 0.3, latency: 0.5)
        engine.play(tracksFromWhereAsked([signal(frames: 9_600, channels: 2, seed: 0.45)], rate: rate), from: 0)
        engine.settle()
        var pieces = 0
        while engine.phase != .ended, pieces < 20 {
            _ = try engine.renderOffline(2_400)
            Thread.sleep(forTimeInterval: 0.01)
            engine.settle()
            pieces += 1
        }
        #expect(engine.phase == .ended)
        Thread.sleep(forTimeInterval: 0.1)
        engine.settle()
        #expect(engine.outputRunning, "0.6 s to go: its last samples are on their way to the ear")
        waitFor(engine, seconds: 3) { !engine.outputRunning }
        #expect(!engine.outputRunning, "stopped once heard")
    }

    // A song played from part-way in still has its whole length once its decode has ended - the plays
    // rule splits a join across it.
    @Test func theLengthIsTheWholeSongsAfterASeek() throws {
        let rate = 48_000.0
        let a = signal(frames: 24_000, channels: 2, seed: 0.2)
        let b = signal(frames: 24_000, channels: 2, seed: 0.3)
        let engine = try liveEngine(rate: rate)
        engine.play(tracksFromWhereAsked([a, b], rate: rate), from: 0, at: 0.25)
        engine.settle()
        _ = try render(engine, frames: 4_096)
        let at = try #require(engine.position())
        #expect(at.key == 0 && at.length == 0.5, "played from 0.25 s, its decode ended: \(at)")
    }

    // The song change is said when the ear reaches the join, on a timer of its own - not only at the
    // next buffer's completion, which (one buffer a second here) can come long after.
    @Test func theSongChangeIsSaidWhenHeardBetweenCompletions() throws {
        let rate = 48_000.0
        var settings = PlaybackEngine.Settings()
        settings.offline = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false)
        settings.bufferSeconds = 2
        settings.aheadSeconds = 3
        settings.startSeconds = 0
        let engine = try PlaybackEngine(settings: settings)
        engine.latency = { 1 }
        let a = signal(frames: 96_000, channels: 2, seed: 0.61) // one buffer
        let b = signal(frames: 192_000, channels: 2, seed: 0.71) // two
        engine.play(tracksFromWhereAsked([a, b], rate: rate), from: 0)
        engine.settle()
        // A's buffer rendered: the render is in B, the ear a second back in A - the change armed, 0.95 s off
        _ = try render(engine, frames: 98_304)
        #expect(engine.stateNow.key == 0)
        // on past where the ear passes the join (144000), in one go: B's first buffer runs to 192000, so
        // no completion comes
        _ = try engine.renderOffline(55_296)
        engine.settle()
        #expect(engine.stateNow.key == 0, "not said yet")
        #expect(engine.position()?.key == 1, "though B is what is heard")
        Thread.sleep(forTimeInterval: 1.2)
        engine.settle()
        #expect(engine.stateNow.key == 1 && engine.stateNow.index == 1, "said when heard, with no completion")
    }
}
#endif
