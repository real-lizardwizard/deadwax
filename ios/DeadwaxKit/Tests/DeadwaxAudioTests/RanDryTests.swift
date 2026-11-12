#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// A lane that runs dry mid-song - a stream behind, or a phone too busy to handle the buffers' completions
// in time - starts again from the frame it reached, and its count stays the node's own: the position, the
// frame a pause (or a call, a new route) goes on from, and the moment a song in another format starts are
// where the listener is.
//
// AVAudioPlayerNode's clock runs on through the silence once it has played everything on it, and a buffer
// put on it then plays after the silence. Put on before the lane's last completion said it had run dry,
// the engine counted it straight on: ahead by the silence for the rest of the lane (the phone review of
// fix/engine-ci; notes/ios.md "The engine's tests under load"). The engine holds such a buffer until that
// completion now, which starts the lane again from the frame it reached - the path a stream behind always
// took when its completion came first.
extension EngineRenderTests {
    /// A 2 s song at 48 kHz, the frames past `arrived` not come yet, on an engine keeping 0.3 s ahead in
    /// 0.1 s buffers whose completions are handled `lag` after AVAudioEngine calls them back.
    private func behind(lag: Double, arrived: Int = 24_000) throws -> (PlaybackEngine, GatedFrames, [[Float]], TraceLines) {
        let rate = 48_000.0
        let song = signal(frames: 96_000, channels: 2, seed: 0.52)
        let gate = GatedFrames(song, rate: rate, arrived: arrived)
        let track = EngineTrack(key: 0, audio: "s|off", song: Song(id: "s")) { start in
            // the first open is the stream behind; a reopen (play after a pause) has it all, from where asked
            if start == .beginning { return gate }
            return MemorySource(song, rate: rate, start: Int(start.frame(at: rate)))
        }
        let engine = try liveEngine(rate: rate)
        engine.completionLag = lag
        let trace = TraceLines()
        engine.trace = trace.add
        engine.play([track], from: 0)
        engine.settle()
        return (engine, gate, song, trace)
    }

    /// The frame the engine says is heard (latency 0 here: the frame rendered).
    private func heardFrame(_ engine: PlaybackEngine) -> Int? {
        engine.position().map { Int(($0.seconds * 48_000).rounded()) }
    }

    /// From `from`, played on: the next 9600 frames are the song's own from there (past a node's start, which
    /// may be ramped) - and after a pause and play, the 9600 after those.
    private func goesOn(_ engine: PlaybackEngine, _ song: [[Float]], from: Int, _ trace: TraceLines,
                        sourceLocation: SourceLocation = #_sourceLocation) throws {
        let out = samples(try engine.renderOffline(9_600), channel: 0)
        #expect(firstDifference(out[4_096...], song[0][(from + 4_096)..<(from + 9_600)]) == nil,
                "the song goes on unbroken from frame \(from)\n\(trace)", sourceLocation: sourceLocation)
        let heard = from + 9_600
        #expect(heardFrame(engine) == heard, "the position is the frame heard, \(heard)\n\(trace)", sourceLocation: sourceLocation)
        engine.pause()
        engine.settle()
        engine.resume()
        engine.settle()
        let after = samples(try engine.renderOffline(9_600), channel: 0)
        #expect(firstDifference(after[4_096...], song[0][(heard + 4_096)..<(heard + 9_600)]) == nil,
                "a pause and play go on from the frame heard, \(heard)\n\(trace)", sourceLocation: sourceLocation)
    }

    // The designed order: the lane's last completion says it ran dry before the bytes come back.
    @Test func aLaneThatRunsDryMidSongGoesOnFromTheFrameItReached() throws {
        let (engine, gate, song, trace) = try behind(lag: 0)
        _ = try render(engine, frames: 19_200, piece: 4_800)
        _ = try engine.renderOffline(4_800 + 512) // what has arrived, and one IO cycle's worth past it
        try completionsHandled(engine)
        #expect(engine.phase == .loading, "out of what has arrived: loading again")
        gate.release()
        waitFor(engine) { engine.phase == .playing }
        try #require(engine.phase == .playing, "on again once the bytes came (\(engine.phase))\n\(trace)")
        try goesOn(engine, song, from: 24_000, trace)
    }

    // The stream's retry finds the bytes before the lane's last completion is handled - late by a quarter of
    // a second here, the race on a busy phone made certain. The engine used to put them on the node that had
    // run out and count them straight on: 512 frames ahead from then on, and a pause and play skipped them.
    @Test func aLaneRunDryWhoseLastCompletionIsLateGoesOnFromTheFrameHeard() throws {
        let (engine, gate, song, trace) = try behind(lag: 0.25)
        _ = try render(engine, frames: 19_200, piece: 4_800)
        _ = try engine.renderOffline(4_800 + 512)
        try runOutCalledBack(engine)
        let handled = engine.callbacksDone
        gate.release() // the retry (every 50 ms) reads them well before the last completion is handled
        waitFor(engine) { engine.callbacksDone > handled && engine.phase == .playing }
        try #require(engine.callbacksDone > handled && engine.phase == .playing,
                     "the last completion handled, the lane on again (\(engine.phase))\n\(trace)")
        #expect(trace.description.contains("entry 0 held: its lane's node has played all on it"),
                "the bytes were read before the last completion: the race this is about\n\(trace)")
        try goesOn(engine, song, from: 24_000, trace)
    }

    // No stream behind: the phone too busy to handle any completion for longer than what is scheduled ahead
    // (a second here, past the 0.3 s ahead). When they come, the first one's pump used to put the next
    // buffers on the node that had run out, and the engine said 24000 frames ahead of the ear.
    @Test func aStallLongerThanWhatIsAheadGoesOnFromTheFrameHeard() throws {
        let rate = 48_000.0
        let song = signal(frames: 96_000, channels: 2, seed: 0.58)
        let engine = try liveEngine(rate: rate)
        engine.completionLag = 1
        let trace = TraceLines()
        engine.trace = trace.add
        engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
        engine.settle()
        for _ in 0..<8 { _ = try engine.renderOffline(4_800) } // 0.8 s: the node runs out at 14400
        try #require(engine.callbacksDone == 0, "no completion handled during the render: the stall is longer than it")
        waitFor(engine) { engine.callbacksDone >= 3 && engine.phase == .playing }
        try #require(engine.callbacksDone >= 3 && engine.phase == .playing,
                     "the three completions handled, the lane on again (\(engine.phase))\n\(trace)")
        #expect(trace.description.contains("entry 0 held: its lane's node has played all on it"),
                "the first completion's pump found the node run out\n\(trace)")
        try goesOn(engine, song, from: 14_400, trace)
    }

    // The next song in another format starts when the lane before it really ends. With the lane's count
    // ahead of its node (the race above), the 96 kHz song started 4800 frames early, over the end of the
    // first. (3 s kept ahead here, so all there is goes on at once and each render is one call.)
    @Test func aSongInAnotherFormatStartsWhereALaneRunDryReallyEnds() throws {
        let rate = 48_000.0
        let a = signal(frames: 48_000, channels: 2, seed: 0.62) // 1 s
        let b = signal(frames: 96_000, channels: 2, seed: 0.72) // 1 s at 96 kHz
        let gate = GatedFrames(a, rate: rate, arrived: 24_000)
        let A = EngineTrack(key: 0, audio: "a|off", song: Song(id: "a")) { _ in gate }
        let B = entry(b, rate: 96_000, key: 1, id: "b")
        let engine = try liveEngine(rate: rate, ahead: 3)
        engine.completionLag = 0.25
        let trace = TraceLines()
        engine.trace = trace.add
        engine.play([A, B], from: 0)
        engine.settle()
        var out = samples(try engine.renderOffline(28_800), channel: 0) // 4800 past what has arrived
        try runOutCalledBack(engine)
        gate.release()
        waitFor(engine) { engine.callbacksDone >= 5 && engine.phase == .playing }
        try #require(engine.callbacksDone >= 5 && engine.phase == .playing, "A's five completions handled, A on again (\(engine.phase))\n\(trace)")
        #expect(trace.description.contains("entry 0 held"), "the bytes were read before the last completion\n\(trace)")
        out += samples(try engine.renderOffline(72_000), channel: 0)
        // A goes on at 28800, the render's first frame after the silence, so it ends at 52800
        let end = 28_800 + 24_000
        #expect(firstDifference(out[(28_800 + 4_096)..<end], a[0][(24_000 + 4_096)...]) == nil,
                "A's second half alone, to its very end - nothing of B over it\n\(trace)")
        let after = out[(end + 4_096)..<(end + 40_000)]
        let squares: [Float] = after.map { (sample: Float) -> Float in sample * sample }
        #expect(squares.reduce(0, +) / Float(after.count) > 0.01, "then B")
    }
}
#endif
