#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// The CI cause (notes/ios.md "A node's buffers, taken late"). AVAudioPlayerNode performs scheduleBuffer on a serial
// queue of its own for a node attached while the engine runs - every lane - and a render begun before that queue
// has run plays the buffer a render late while the node's clock counts it on time. On ios.yml's runner that made
// aJoinIsTheTwoSongsLaidEndToEnd silent throughout and the queue's end wait for good. The phone schedules 2 s
// ahead of its render, so only an offline render can come that soon after a buffer: the engine waits for it
// before rendering offline (`offlineScheduleSettle`). These take every buffer half a millisecond late, as the
// runner did (`scheduleLag`), and pass only with that wait - the whole suite does too, ios.yml's second run.
extension EngineRenderTests {
    @Test func aJoinWithItsBuffersTakenLateIsStillTheTwoSongsEndToEnd() throws {
        let rate = 44_100.0
        let a = signal(frames: 13_230, channels: 2, seed: 0.1)
        let b = signal(frames: 11_025, channels: 2, seed: 0.7)
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.scheduleLag = 0.0005
        let trace = TraceLines()
        engine.trace = trace.add
        engine.play(tracksFromWhereAsked([a, b], rate: rate), from: 0)
        engine.settle()
        try #require(engine.phase == .playing && engine.outputRunning)
        let total = a[0].count + b[0].count
        let out = samples(try engine.renderOffline(AVAudioFrameCount(total + 4_096)), channel: 0)
        let expected = a[0] + b[0]
        #expect(firstDifference(out[4_096..<total], expected[4_096...]) == nil,
                "the join, exact: \(whereItBegins(out, expected))\n\(trace)")
        #expect(out[total...].allSatisfy { $0 == 0 }, "silence after the last song")
    }

    @Test func theQueuesEndWithItsBuffersTakenLateIsHeard() throws {
        let rate = 48_000.0
        let song = signal(frames: 9_600, channels: 2, seed: 0.45)
        let engine = try liveEngine(rate: rate, ahead: 0.3)
        engine.scheduleLag = 0.0005
        let trace = TraceLines()
        engine.trace = trace.add
        engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
        engine.settle()
        var out: [Float] = []
        while engine.phase != .ended, out.count < 48_000 {
            out += samples(try engine.renderOffline(2_400), channel: 0)
            try completionsHandled(engine)
        }
        #expect(engine.phase == .ended, "the queue's end\n\(trace)")
        #expect(firstDifference(out[4_096..<9_600], song[0][4_096...]) == nil, "the song whole, on time\n\(trace)")
    }

    // The hook's own call into the node held up past the settle - 184 ms once under `taskpolicy -b`, from before the
    // settle ended into the render, so the buffers behind it missed the render and this join was silent throughout
    // (notes/ios.md "A node's buffers, taken late", the verifier's finding 1). The engine's own call is made on its
    // queue, which a render waits for, and the settle after; the hook's is made off it, so the render waits for one
    // still under way. Without that wait, this is silent throughout.
    @Test func aJoinWhoseFirstCallTheHookHoldsUpPastTheSettleIsStillTheTwoSongsEndToEnd() throws {
        let rate = 44_100.0
        let a = signal(frames: 13_230, channels: 2, seed: 0.1)
        let b = signal(frames: 11_025, channels: 2, seed: 0.7)
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.scheduleLag = 0.0005
        engine.scheduleCallHeld = PlaybackEngine.offlineScheduleSettle + 0.05
        let trace = TraceLines()
        engine.trace = trace.add
        engine.play(tracksFromWhereAsked([a, b], rate: rate), from: 0)
        engine.settle()
        try #require(engine.phase == .playing && engine.outputRunning)
        let total = a[0].count + b[0].count
        let out = samples(try engine.renderOffline(AVAudioFrameCount(total + 4_096)), channel: 0)
        let expected = a[0] + b[0]
        #expect(trace.description.contains("under way as the settle ended: waited for it"), "the render waited\n\(trace)")
        #expect(firstDifference(out[4_096..<total], expected[4_096...]) == nil,
                "the join, exact: \(whereItBegins(out, expected))\n\(trace)")
        #expect(out[total...].allSatisfy { $0 == 0 }, "silence after the last song")
    }
}
#endif
