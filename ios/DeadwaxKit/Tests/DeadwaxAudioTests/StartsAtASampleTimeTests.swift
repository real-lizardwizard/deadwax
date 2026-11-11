#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// Starts at a sample time (notes/ios.md "Starts at a sample time"). A node started at a host time counted its
// clock 245-651 frames ahead of its first sample on this Mac's output, and a song in another format started at
// a host time from the heard lane's clock overlapped its end by 238-723 frames; a node started at a SAMPLE time
// puts its first sample exactly there, its count with it, on a real output as offline. So a start from silence
// is at the render's time plus the lead (or one IO buffer on an output already running), the lane's count begins
// there (`origin`), and a song in another format starts at the very sample the heard lane's last one plays.
// Offline the lead is now taken as the phone takes it, so these renders hold where it puts things.

/// Where `c`'s frames 4096-4159 are in `out` between `range`, less 4096: where `c` begins.
private func whereSongBegins(_ out: [Float], _ c: [Float], in range: Range<Int>) -> Int? {
    let probe = Array(c[4_096..<4_160])
    return range.first { start in start + 64 <= out.count && (0..<64).allSatisfy { out[start + $0] == probe[$0] } }
        .map { $0 - 4_096 }
}

extension EngineRenderTests {
    // A start from silence on an output just started is the lead ahead of the render, as a sample time: the
    // song's first frame there, nothing before it, and its count from that frame - the position, and a pause
    // and play, from the frame heard.
    @Test func aStartFromSilenceLandsWhereItsCountSays() throws {
        let rate = 48_000.0
        let song = signal(frames: 48_000, channels: 2, seed: 0.61)
        let engine = try offlineEngine(rate: rate, channels: 2)
        engine.startLead = { 0.05 }
        let trace = TraceLines()
        engine.trace = trace.add
        engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
        engine.settle()
        #expect(engine.leadsTaken == [0.05])
        let out = try render(engine, frames: 12_000, piece: 4_800)
        #expect(out[0..<2_400].allSatisfy { $0 == 0 }, "silence for the lead's 2400 frames: \(whereItBegins(out, song[0]))\n\(trace)")
        #expect(firstDifference(out[(2_400 + 4_096)...], song[0][4_096..<(12_000 - 2_400)]) == nil,
                "the song from frame 2400: \(whereItBegins(out, song[0]))\n\(trace)")
        #expect(trace.description.contains("started from silence at 2400"), "its count from there\n\(trace)")
        let at = try #require(engine.position())
        #expect(abs(at.seconds * rate - Double(12_000 - 2_400)) < 1, "the position, the frame heard: \(at.seconds * rate)\n\(trace)")
        engine.pause()
        engine.settle()
        engine.resume()
        engine.settle()
        let after = try render(engine, frames: 12_000, piece: 4_800)
        // play after a pause starts the output again: the lead again, then the song from the frame left
        #expect(after[0..<2_400].allSatisfy { $0 == 0 }, "the lead again\n\(trace)")
        #expect(firstDifference(after[(2_400 + 4_096)...], song[0][(9_600 + 4_096)..<(9_600 + 12_000 - 2_400)]) == nil,
                "on from 9600, the frame heard: \(whereItBegins(Array(after[2_400...]), Array(song[0][9_600...])))\n\(trace)")
    }

    // A song in another format starts at the sample the heard lane's last one plays: the heard lane counted from
    // its own start (here the lead in), so nothing of the next song over its end and no gap; and the song after
    // that straight after it. Then the same after a 44.1 kHz song, whose end is its converter's last frame - with
    // the song after the 96 kHz one in a third format, which started at the 44.1 kHz song's end too, over the
    // 96 kHz one, before only the lane whose song comes next was started.
    @Test func aSongInAnotherFormatJoinsAtTheSampleTheHeardLaneEnds() throws {
        // 48 kHz, started 2400 frames in; 96 kHz (24000 of the output's); 48 kHz again
        let a = signal(frames: 24_000, channels: 2, seed: 0.62)
        let b = signal(frames: 48_000, channels: 2, seed: 0.63)
        let c = signal(frames: 24_000, channels: 2, seed: 0.64)
        let engine = try liveEngine(rate: 48_000, ahead: 3)
        engine.startLead = { 0.05 }
        let trace = TraceLines()
        engine.trace = trace.add
        engine.play([entry(a, rate: 48_000, key: 0, id: "a"), entry(b, rate: 96_000, key: 1, id: "b"),
                     entry(c, rate: 48_000, key: 2, id: "c")], from: 0)
        engine.settle()
        let out = try render(engine, frames: 2_400 + 72_000 + 4_800, piece: 4_800)
        #expect(out[0..<2_400].allSatisfy { $0 == 0 }, "the lead\n\(trace)")
        #expect(firstDifference(out[(2_400 + 4_096)..<(2_400 + 24_000)], a[0][4_096...]) == nil,
                "A whole to its last frame, nothing of B over it\n\(trace)")
        #expect(trace.description.contains("lane 96000 Hz to start at 26400"), "B at A's last sample's next\n\(trace)")
        #expect(out[(2_400 + 24_000)..<(2_400 + 24_000 + 64)].allSatisfy { $0 != 0 }, "B straight after A, no gap\n\(trace)")
        let cAt = whereSongBegins(out, c[0], in: 40_000..<60_000)
        #expect(cAt.map { $0 >= 2_400 + 48_000 && $0 <= 2_400 + 48_002 } == true,
                "C at \(cAt.map(String.init) ?? "nowhere"), straight after B's 24000 frames\n\(trace)")
        if let cAt {
            #expect(firstDifference(out[(cAt + 4_096)..<(cAt + 24_000)], c[0][4_096...]) == nil, "C alone")
        }

        // 44.1 kHz (its converter's last frames its end), then 96 kHz, then 48 kHz
        let cd = signal(frames: 22_050, channels: 2, seed: 0.65)
        let engine2 = try liveEngine(rate: 48_000, ahead: 3)
        let trace2 = TraceLines()
        engine2.trace = trace2.add
        engine2.play([entry(cd, rate: 44_100, key: 0, id: "cd"), entry(b, rate: 96_000, key: 1, id: "b"),
                      entry(c, rate: 48_000, key: 2, id: "c")], from: 0)
        engine2.settle()
        let out2 = try render(engine2, frames: 72_000 + 4_800, piece: 4_800)
        let line = trace2.description.split(separator: "\n").first { $0.contains("lane 96000 Hz to start at") }
        let bAt = line.flatMap { Int(($0.split(separator: " ").drop { $0 != "at" }.dropFirst().first ?? "").filter(\.isNumber)) }
        #expect(bAt != nil, "B started at a sample time, when the 44.1 kHz lane ends\n\(trace2)")
        if let bAt {
            // the 44.1 kHz song's last frame's next: its converter's output, 24000 frames, all of it on the node
            #expect(abs(bAt - 24_000) <= 1, "B at the converted song's end, 24000: \(bAt)\n\(trace2)")
            #expect(out2[(bAt - 64)..<(bAt + 64)].allSatisfy { $0 != 0 }, "B straight after it, no gap\n\(trace2)")
            // three formats: C, decoded while the 44.1 kHz song still played, waits for B to be heard (it started
            // at the same end as B, over it)
            let c2 = whereSongBegins(out2, c[0], in: 20_000..<56_000)
            #expect(c2.map { $0 >= bAt + 24_000 && $0 <= bAt + 24_002 } == true,
                    "C at \(c2.map(String.init) ?? "nowhere"), straight after B\n\(trace2)")
            if let c2 {
                #expect(firstDifference(out2[(c2 + 4_096)..<(c2 + 24_000)], c[0][4_096...]) == nil, "C alone")
            }
        }
    }

    // No render time to start at, ever (an output that never renders, or only the last run's reading): the start
    // waits for one for a tenth of a second (`renderWaitSeconds`), then falls back to what it was - at once, or
    // the lead ahead at a host time - and a song in another format after it still joins at the heard lane's last
    // sample, its end read off its clock (no `origin`). A's length is no piece's, so only that join puts B
    // straight after it.
    @Test func startWithNoRenderTimeFallsBack() throws {
        let a = signal(frames: 22_222, channels: 2, seed: 0.66)
        let b = signal(frames: 48_000, channels: 2, seed: 0.67)
        let c = signal(frames: 24_000, channels: 2, seed: 0.68)
        let engine = try liveEngine(rate: 48_000, ahead: 3)
        engine.noRenderTime = true
        let trace = TraceLines()
        engine.trace = trace.add
        engine.play([entry(a, rate: 48_000, key: 0, id: "a"), entry(b, rate: 96_000, key: 1, id: "b"),
                     entry(c, rate: 48_000, key: 2, id: "c")], from: 0)
        engine.settle()
        #expect(engine.phase == .loading, "waiting for a render (\(engine.phase))\n\(trace)")
        waitFor(engine) { engine.phase == .playing }
        try #require(engine.phase == .playing, "playing (\(engine.phase))\n\(trace)")
        #expect(trace.description.contains("no render of this run of the output yet, waiting for one"), "\(trace)")
        #expect(trace.description.contains("started from silence at a host time: no render of this run in 100 ms"), "\(trace)")
        var out: [Float] = []
        while engine.phase != .ended, out.count < 96_000 {
            out += samples(try engine.renderOffline(4_800), channel: 0)
            try completionsHandled(engine)
        }
        #expect(firstDifference(out[4_096..<22_222], a[0][4_096...]) == nil, "A at once, whole\n\(trace)")
        #expect(trace.description.contains("lane 96000 Hz to start at 22222"), "B at A's last sample's next\n\(trace)")
        #expect(out[22_222..<(22_222 + 64)].allSatisfy { $0 != 0 }, "B straight after it\n\(trace)")
        let cAt = whereSongBegins(out, c[0], in: 40_000..<56_000)
        #expect(cAt.map { $0 >= 46_222 && $0 <= 46_224 } == true, "C at \(cAt.map(String.init) ?? "nowhere")\n\(trace)")
        #expect(engine.phase == .ended, "the queue's end\n\(trace)")
    }

    // A render time is a time to start at only if it is of this run of the output. Just after engine.stop() and
    // start() of the same engine, this Mac's output still read the last run's - its node's 18944, 505 ms old -
    // and a node started there played at once with its count 23040 frames (0.48 s) ahead of its samples; 20 ms on
    // it read 43520, the nodes' time running on across the stop. These are those readings.
    @Test func aRenderTimeLeftFromBeforeAStopIsNoTimeToStartAt() {
        let started = 1_000.0
        // the reading the node had as the output started, its host time before the start
        #expect(PlaybackEngine.ofThisRun(18_944, host: started - 0.505, atStart: 18_944, startedAt: started) == nil)
        // the same reading with its host time after the start (a stop of a few ms, a timestamp ahead of the render)
        #expect(PlaybackEngine.ofThisRun(18_944, host: started + 0.010, atStart: 18_944, startedAt: started) == nil)
        // a node attached since (nothing read at the start), stamped before the start
        #expect(PlaybackEngine.ofThisRun(18_944, host: started - 0.505, atStart: nil, startedAt: started) == nil)
        // a render of this run
        #expect(PlaybackEngine.ofThisRun(43_520, host: started + 0.0157, atStart: 18_944, startedAt: started) == 43_520)
        #expect(PlaybackEngine.ofThisRun(43_008, host: nil, atStart: nil, startedAt: started) == 43_008)
    }

    // Play after a pause, wired through: the output starts again and the song's second is decoded before its first
    // render of this run, so its lane's node still reads the render time left from before the stop - for 5-12 ms on
    // this Mac's output; `staleRenderReads` gives that reading (12000 frames behind, stamped just after the start,
    // so only its being the reading taken at the start tells it apart). The start waits for a render of this run,
    // then starts at a sample time: the lead's silence, the song from the frame left, its count exact, and a song in
    // another format straight after its last sample. Started at a host time instead, as efb8b6a fell back to every
    // time here, the count ran 12-22 ms ahead of the ear on this Mac's output and the next song over its end (the
    // verifiers' first finding); started at the reading left, a quarter of a second ahead here (0.3-1.45 s on the
    // output: their second).
    @Test func playAfterAPauseWaitsForThisRunsFirstRender() throws {
        let rate = 48_000.0
        let a = signal(frames: 48_000, channels: 2, seed: 0.69)
        let b = signal(frames: 48_000, channels: 2, seed: 0.70) // 0.5 s at 96 kHz
        let engine = try liveEngine(rate: rate)
        engine.startLead = { 0.05 }
        engine.staleRenderReads = 3 // the lanes made before a start: only A's, at play after the pause
        engine.staleRenderBehind = 12_000
        let trace = TraceLines()
        engine.trace = trace.add
        engine.play([entry(a, rate: rate, key: 0, id: "a"), entry(b, rate: 96_000, key: 1, id: "b")], from: 0)
        engine.settle()
        try #require(engine.phase == .playing, "the first start: no lane read stale (\(engine.phase))\n\(trace)")
        _ = try render(engine, frames: 12_000, piece: 4_800) // A from 2400: 9600 heard
        engine.pause()
        engine.settle()
        engine.resume()
        waitFor(engine) { engine.phase == .playing }
        try #require(engine.phase == .playing, "on again (\(engine.phase))\n\(trace)")
        #expect(trace.description.contains("no render of this run of the output yet, waiting for one"), "it waited\n\(trace)")
        #expect(trace.description.contains("this run's first render after"), "\(trace)")
        let starts = trace.description.split(separator: "\n").filter { $0.contains("started from silence") }
        #expect(starts.count == 2 && starts.last?.hasSuffix("started from silence at 14400") == true,
                "at the render's count, 12000, and the lead - never at the reading left (2400), nor a host time\n\(trace)")
        var out = try render(engine, frames: 12_000, piece: 4_800)
        #expect(out[0..<2_400].allSatisfy { $0 == 0 }, "the lead's silence: \(whereItBegins(out, Array(a[0][9_600...])))\n\(trace)")
        #expect(firstDifference(out[2_400...], a[0][9_600..<19_200]) == nil,
                "A from 9600, the frame left: \(whereItBegins(Array(out[2_400...]), Array(a[0][9_600...])))\n\(trace)")
        let at = try #require(engine.position())
        #expect(abs(at.seconds * rate - 19_200) < 1, "the position, the frame heard: \(at.seconds * rate)\n\(trace)")
        out += try render(engine, frames: 28_800 + 9_600, piece: 4_800)
        #expect(firstDifference(out[2_400..<40_800], a[0][9_600...]) == nil, "A whole to its last frame, nothing of B over it\n\(trace)")
        #expect(trace.description.contains("lane 96000 Hz to start at 52800"), "B at A's last sample's next\n\(trace)")
        #expect(out[40_800..<(40_800 + 64)].allSatisfy { $0 != 0 }, "B straight after A\n\(trace)")
    }

    // On an output just started, the lead counts from when the start was asked, on the render's own time line: a
    // real output stamps a render's time ahead of now (24.8 ms on this Mac's), and a play(at:) host time -
    // 307384f's, which Phase 0 heard lose no start on AirPods - is read on that line. Counted from the render's
    // sample instead, every first start was that much later (224.8 ms after the call for a 0.2 s lead; the
    // verifiers' finding). `renderHostAhead` stamps the offline render ahead of now: 20 ms leaves 30 of a 50 ms
    // lead (1440 frames), and 80 ms leaves none - the next render, never before it.
    @Test func theLeadCountsFromWhenTheStartWasAskedOnTheRendersTimeLine() throws {
        let rate = 48_000.0
        let song = signal(frames: 48_000, channels: 2, seed: 0.71)
        for (ahead, expected) in [(0.02, 1_440), (0.08, 0)] {
            let engine = try offlineEngine(rate: rate, channels: 2)
            engine.startLead = { 0.05 }
            engine.renderHostAhead = ahead
            let trace = TraceLines()
            engine.trace = trace.add
            engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
            engine.settle()
            let line = trace.description.split(separator: "\n").first { $0.contains("started from silence at") }
            let at = try #require(line.flatMap { Int(String($0.split(separator: " ").last ?? "")) }, "started at a sample time\n\(trace)")
            #expect(abs(at - expected) <= 1, "render \(ahead) s ahead: started at \(at), not \(expected)\n\(trace)")
            let out = try render(engine, frames: 9_600, piece: 4_800)
            #expect(out[..<at].allSatisfy { $0 == 0 }, "silence to it\n\(trace)")
            #expect(firstDifference(out[at...], song[0][..<(9_600 - at)]) == nil,
                    "the song from it: \(whereItBegins(out, song[0]))\n\(trace)")
            let position = try #require(engine.position())
            #expect(abs(position.seconds * rate - Double(9_600 - at)) < 1, "its count from it: \(position.seconds * rate)")
        }
    }
}
#endif
