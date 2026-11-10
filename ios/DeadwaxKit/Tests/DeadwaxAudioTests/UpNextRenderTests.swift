#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// Up Next's edits under the engine (replaceUpcoming), a queue put back paused (restoreQueue), and a
// next song that fails - rendered offline with only 0.3 s kept scheduled, so the next song is decoded
// and committed in a song's last moments as on the phone. Every song here is at the render's rate, so
// every join is exact.
extension EngineRenderTests {
    /// A (1 s), B and C (0.5 s each) at 44.1 kHz, keyed 0, 1, 2.
    private func abc() -> (a: [[Float]], b: [[Float]], c: [[Float]]) {
        (signal(frames: 44_100, channels: 2, seed: 0.12), signal(frames: 22_050, channels: 2, seed: 0.22),
         signal(frames: 22_050, channels: 2, seed: 0.32))
    }

    @Test func anEditBeforeTheNextSongIsCommittedPlaysTheNewNext() throws {
        let rate = 44_100.0
        let (a, b, c) = abc()
        let (A, B, C) = (entry(a, rate: rate, key: 0, id: "a"), entry(b, rate: rate, key: 1, id: "b"), entry(c, rate: rate, key: 2, id: "c"))
        let engine = try liveEngine(rate: rate)
        engine.play([A, B, C], from: 0)
        engine.settle()
        var took: Bool?
        let out = try render(engine, frames: 88_200 + 4_096) { done in
            if done >= 8_820, took == nil { took = engine.replaceUpcoming([A, C, B]) }
        }
        #expect(took == true)
        #expect(firstDifference(out[4_096..<44_100], a[0][4_096...]) == nil, "A")
        #expect(firstDifference(out[44_100..<66_150], c[0]) == nil, "C next, joined exactly")
        #expect(firstDifference(out[66_150..<88_200], b[0]) == nil, "then B")
    }

    @Test func anEditOfACommittedSongIsHeldAndTheSongHeardUntouched() throws {
        let rate = 44_100.0
        let (a, b, c) = abc()
        let (A, B, C) = (entry(a, rate: rate, key: 0, id: "a"), entry(b, rate: rate, key: 1, id: "b"), entry(c, rate: rate, key: 2, id: "c"))
        let engine = try liveEngine(rate: rate)
        var committed = false
        engine.trace = { line in if line.contains("held: entry 1 is on a node") { committed = true } }
        engine.play([A, B, C], from: 0)
        engine.settle()
        var took: Bool?
        let out = try render(engine, frames: 66_150 + 4_096) { done in
            // 0.93 s: B's first buffers are on the node behind A's last
            if done >= 40_960, took == nil { took = engine.replaceUpcoming([A, C]) }
        }
        #expect(took == false, "held: the app makes it again after the join")
        #expect(committed)
        #expect(firstDifference(out[4_096..<44_100], a[0][4_096...]) == nil, "A, every sample as decoded")
        #expect(firstDifference(out[44_100..<66_150], b[0]) == nil, "B, as it was scheduled")
        #expect(engine.position()?.key == 1 || engine.position()?.key == 2)
    }

    @Test func aSongAddedAfterTheQueuesEndJoins() throws {
        let rate = 44_100.0
        let (a, b, _) = abc()
        let (A, B) = (entry(a, rate: rate, key: 0, id: "a"), entry(b, rate: rate, key: 1, id: "b"))
        let engine = try liveEngine(rate: rate)
        engine.play([A], from: 0)
        engine.settle()
        var took: Bool?
        let out = try render(engine, frames: 66_150 + 4_096) { done in
            // A's decode has ended (its last 0.3 s): nothing was after it
            if done >= 36_864, took == nil { took = engine.replaceUpcoming([A, B]) }
        }
        #expect(took == true)
        #expect(firstDifference(out[44_100..<66_150], b[0]) == nil, "B joins A sample-exact")
        #expect(engine.phase == .ended || engine.phase == .playing)
    }

    @Test func theSameAudioUnderANewKeyIsKept() throws {
        let rate = 44_100.0
        let (a, b, _) = abc()
        let A = entry(a, rate: rate, key: 0, id: "a")
        let engine = try liveEngine(rate: rate)
        engine.play([A, entry(b, rate: rate, key: 1, id: "b")], from: 0)
        engine.settle()
        var took: Bool?
        let out = try render(engine, frames: 50_000) { done in
            // B is committed: the same audio under key 7 (Shuffle turned off makes new entries) keeps it
            if done >= 40_960, took == nil { took = engine.replaceUpcoming([A, entry(b, rate: rate, key: 7, id: "b")]) }
        }
        #expect(took == true)
        #expect(firstDifference(out[44_100..<50_000], b[0][0..<5_900]) == nil, "nothing dropped")
        let at = try #require(engine.position())
        #expect(at.key == 7 && at.index == 1)
    }

    @Test func aNextSongNotYetOnANodeIsLetGo() throws {
        let rate = 44_100.0
        let (a, _, c) = abc()
        let A = entry(a, rate: rate, key: 0, id: "a")
        // B: a 96 kHz stream whose header hasn't arrived - opened, waiting, on no node
        let gate = GatedBytes(Data(repeating: 0, count: 100_000))
        let B = EngineTrack(key: 1, audio: "b|off", song: Song(id: "b")) { start in
            try StreamSource(bytes: gate, typeHint: kAudioFileFLACType, start: start)
        }
        let engine = try liveEngine(rate: rate)
        engine.play([A, B], from: 0)
        engine.settle()
        var took: Bool?
        let out = try render(engine, frames: 66_150 + 4_096) { done in
            if done >= 40_960, took == nil { took = engine.replaceUpcoming([A, entry(c, rate: rate, key: 2, id: "c")]) }
        }
        #expect(took == true)
        #expect(firstDifference(out[4_096..<44_100], a[0][4_096...]) == nil)
        #expect(firstDifference(out[44_100..<66_150], c[0]) == nil, "C straight after A, on one lane")
    }

    @Test func anEditWithoutTheSongHeardChangesNothing() throws {
        let rate = 44_100.0
        let (a, b, c) = abc()
        let (A, B) = (entry(a, rate: rate, key: 0, id: "a"), entry(b, rate: rate, key: 1, id: "b"))
        let engine = try liveEngine(rate: rate)
        engine.play([A, B], from: 0)
        engine.settle()
        var answers: [Bool] = []
        let out = try render(engine, frames: 66_150 + 4_096) { done in
            if done >= 8_820, answers.isEmpty {
                answers.append(engine.replaceUpcoming([entry(c, rate: rate, key: 9, id: "c"), B]))
                answers.append(engine.replaceUpcoming([entry(a, rate: rate, key: 0, id: "a", factor: 0.5), B]))
                answers.append(engine.replaceUpcoming([entry(c, rate: rate, key: 9, id: "c"), A, B]))
            }
        }
        #expect(answers == [false, false, false], "without the song heard, at another level, or moved: refused")
        #expect(firstDifference(out[4_096..<44_100], a[0][4_096...]) == nil)
        #expect(firstDifference(out[44_100..<66_150], b[0]) == nil, "B, as before")
    }

    @Test func theIndexReportedIsInTheNewList() throws {
        let rate = 44_100.0
        let (a, b, c) = abc()
        let (A, B) = (entry(a, rate: rate, key: 0, id: "a"), entry(b, rate: rate, key: 1, id: "b"))
        let engine = try liveEngine(rate: rate)
        engine.play([A, B], from: 0)
        engine.settle()
        var took: Bool?
        _ = try render(engine, frames: 50_000) { done in
            if done >= 8_820, took == nil { took = engine.replaceUpcoming([A, entry(c, rate: rate, key: 5, id: "x"), B]) }
        }
        #expect(took == true)
        let at = try #require(engine.position())
        #expect(at.key == 5 && at.index == 1)
        #expect(engine.stateNow.key == 5 && engine.stateNow.index == 1)
    }

    // Resume what was playing: the queue comes back paused, nothing opened or played, the output off;
    // play opens the song at the second it was left.
    @Test func aQueuePutBackPausedLoadsNothing() throws {
        let rate = 48_000.0
        let songs = [signal(frames: 144_000, channels: 2, seed: 0.13), signal(frames: 144_000, channels: 2, seed: 0.23)]
        let opens = Opens()
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.restoreQueue(tracksFromWhereAsked(songs, rate: rate, opens: opens), at: 1, seconds: 1.5)
        engine.settle()
        #expect(!engine.outputRunning, "iOS would count a running output as playing")
        #expect(opens.frames.isEmpty, "nothing opened (so nothing fetched)")
        #expect(engine.phase == .paused)
        let at = try #require(engine.position())
        #expect(at.key == 1 && at.index == 1 && at.seconds == 1.5)
        engine.seek(to: 2.0)
        engine.settle()
        #expect(opens.frames.isEmpty && engine.position()?.seconds == 2.0, "a seek moves it without loading")
        engine.resume()
        engine.settle()
        let expected: Int64 = 96_000
        #expect(opens.frames == [expected])
        let out = try engine.renderOffline(24_000)
        #expect(firstDifference(samples(out, channel: 0)[8_192..<9_192], songs[1][0][(96_000 + 8_192)..<(96_000 + 9_192)]) == nil,
                "on from 2.0 s")
    }

    // The next song's stream fails (a 401) while the song heard still plays: the song heard plays to
    // its end, and the failure is said at the song that failed.
    @Test func aNextSongThatFailsLetsTheOneHeardEnd() throws {
        let rate = 44_100.0
        let (a, _, _) = abc()
        let A = entry(a, rate: rate, key: 0, id: "a")
        let refusal = AudioFailure("deadwax says this phone isn't signed in (401). Sign in again.", kind: .signedOut, status: 401)
        let B = EngineTrack(key: 1, audio: "b|off", song: Song(id: "b")) { _ in FailingSource(refusal, rate: rate) }
        let engine = try liveEngine(rate: rate)
        engine.play([A, B], from: 0)
        engine.settle()
        var midway: EngineState.Phase?
        let out = try render(engine, frames: 44_100 + 8_192) { done in
            if done >= 40_960, midway == nil { midway = engine.phase }
        }
        #expect(midway == .playing, "A plays on while B has failed")
        #expect(firstDifference(out[4_096..<44_100], a[0][4_096...]) == nil, "A to its very end")
        #expect(engine.phase == .failed(refusal.description))
        #expect(engine.stateNow.failure == refusal)
        #expect(engine.stateNow.key == 1 && engine.position()?.key == 1, "at the song that failed")
    }
}
#endif
