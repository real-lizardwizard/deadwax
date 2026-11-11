#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// The hold on the callbacks (notes/ios.md "The hold on the callbacks"): a lane has played everything put on it
// when AVAudioEngine has called back every buffer scheduled on it since it began - never by its clock, which on a
// real output runs ahead of its samples - and the faults the hold review of 98a9d9e found around it: a lane
// begun again with nothing (or only its converter's tail) left, a converter lane's count, a song in another
// format started at a time already past, and the start lead taken on an output already running. Each test is
// one of the review's or its judges' probes, its prints made expectations; each fails without its change.

/// The first open is `first` (a stream behind); a reopen (play after a pause) has the whole song, from where asked.
private func gatedTrack(_ first: PCMSource, _ song: [[Float]], rate: Double, key: Int = 0, id: String = "s") -> EngineTrack {
    var opened = false
    return EngineTrack(key: key, audio: "\(id)|off", song: Song(id: id)) { start in
        if !opened, start == .beginning {
            opened = true
            return first
        }
        return MemorySource(song, rate: rate, start: Int(start.frame(at: rate)))
    }
}

/// Mean square.
private func energy(_ samples: ArraySlice<Float>) -> Float {
    guard !samples.isEmpty else { return 0 }
    let squares: [Float] = samples.map { (sample: Float) -> Float in sample * sample }
    return squares.reduce(0, +) / Float(samples.count)
}

private func traced(_ engine: PlaybackEngine) -> TraceLines {
    let trace = TraceLines()
    engine.trace = trace.add
    return trace
}

extension EngineRenderTests {
    // Finding 1. On a real output a node started with play(at:) counts its clock ahead of its samples (245-651
    // frames on this Mac's), so 98a9d9e's clock rule read "played all" while the node still had frames to play,
    // held a stream's bytes found then, and turned a seamless join into a rebuffer (21.7 ms of silence on this
    // Mac's output, 0.5 s and more on the phone's settings). `clockAhead` starts the node that far in the past,
    // its clock 600 frames ahead of what it has played. Nothing is held: the bytes go straight on.
    @Test func bytesFoundWhileTheNodeStillPlaysGoStraightOnWhateverItsClockSays() throws {
        let rate = 48_000.0
        let song = signal(frames: 96_000, channels: 2, seed: 0.81)
        let gate = GatedFrames(song, rate: rate, arrived: 24_000)
        let engine = try liveEngine(rate: rate)
        engine.clockAhead = 600
        let trace = traced(engine)
        engine.play([gatedTrack(gate, song, rate: rate)], from: 0)
        engine.settle()
        _ = try render(engine, frames: 19_200, piece: 4_800)
        // 23700 rendered: the node has 300 frames left of the 24000 on it, its clock reads 24300
        var out = samples(try engine.renderOffline(4_500), channel: 0)
        let scheduled = engine.callbacksOutstanding
        gate.release()
        waitFor(engine, seconds: 2) { engine.callbacksOutstanding > scheduled || trace.description.contains("held") }
        #expect(!trace.description.contains("held") && !trace.description.contains("ran dry"),
                "nothing held: the node had frames to play\n\(trace)")
        out += samples(try engine.renderOffline(9_600), channel: 0)
        #expect(firstDifference(out, song[0][19_200..<(19_200 + 4_500 + 9_600)]) == nil,
                "the song on, unbroken: \(whereItBegins(Array(out[4_500...]), Array(song[0][23_700...])))\n\(trace)")
        #expect(engine.phase == .playing)
    }

    // Finding 8, the race, on the phone's own buffering: the bytes read after AVAudioEngine has called the lane's
    // last buffer back and before the engine has handled it (late by a quarter of a second here). They are held
    // ("entry 0 held"), and that completion starts the lane again from the frame it reached, once a second is
    // buffered as after any run dry: the count exact, a pause and play exact. Laid on the node that had run out
    // (70cbef6, and a race bound that lets them on) they played after the silence, counted straight on.
    @Test func aRaceOnThePhonesBufferingIsHeldThenGoesOnExactly() throws {
        let rate = 48_000.0
        let song = signal(frames: 192_000, channels: 2, seed: 0.85)
        let gate = GatedFrames(song, rate: rate, arrived: 48_000)
        let engine = try phoneLikeEngine(rate: rate)
        engine.completionLag = 0.25
        let trace = traced(engine)
        engine.play([gatedTrack(gate, song, rate: rate)], from: 0)
        engine.settle()
        try #require(engine.phase == .playing, "started on its first second (\(engine.phase))\n\(trace)")
        _ = try engine.renderOffline(48_000 + 512) // its node runs out at 48000; every callback arrives
        let handled = engine.callbacksDone
        gate.release() // the retry reads it long before the last completion is handled
        waitFor(engine) { engine.callbacksDone >= handled + 10 && engine.phase == .playing }
        try #require(engine.phase == .playing, "on again (\(engine.phase))\n\(trace)")
        #expect(trace.description.contains("entry 0 held: its lane's node has played all on it"),
                "the bytes were read before the last completion was handled: the race\n\(trace)")
        let out = samples(try engine.renderOffline(9_600), channel: 0)
        #expect(firstDifference(out[4_096...], song[0][(48_000 + 4_096)..<(48_000 + 9_600)]) == nil,
                "on from the frame it reached, 48000\n\(trace)")
        let at = try #require(engine.position())
        #expect(at.seconds * rate == 57_600, "the position is the frame heard, 57600: \(at.seconds * rate)\n\(trace)")
        engine.pause()
        engine.settle()
        engine.resume()
        engine.settle()
        let after = samples(try engine.renderOffline(9_600), channel: 0)
        #expect(firstDifference(after[4_096...], song[0][(57_600 + 4_096)..<(57_600 + 9_600)]) == nil,
                "a pause and play go on from the frame heard, 57600\n\(trace)")
        let resumed = try #require(engine.position())
        #expect(resumed.seconds * rate == 57_600 + 9_600, "and say it: \(resumed.seconds * rate)\n\(trace)")
    }

    // AVAudioEngine's own completion thread held off for longer than what is ahead: no callback arrives while the
    // node plays all on it and runs out, then they come in a burst, the first handled before the next is
    // counted. Its pump must not lay the next buffer on the node that ran out half a second ago: the clock's
    // backstop (a quarter of a second past all on the node) holds it, and the lane goes on from the frame it
    // reached.
    @Test func aBurstOfLateCallbacksAfterAStallGoesOnFromTheFrameHeard() throws {
        let rate = 48_000.0
        let song = signal(frames: 96_000, channels: 2, seed: 0.77)
        let engine = try liveEngine(rate: rate)
        engine.callbackLag = 1
        let trace = traced(engine)
        engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
        engine.settle()
        for _ in 0..<8 { _ = try engine.renderOffline(4_800) } // 0.8 s: the node runs out at 14400
        try #require(engine.callbacksArrived == 0, "no callback yet: the stall is longer than the render")
        waitFor(engine) { engine.callbacksDone >= 3 && engine.phase == .playing }
        try #require(engine.callbacksDone >= 3 && engine.phase == .playing, "on again (\(engine.phase))\n\(trace)")
        #expect(trace.description.contains("entry 0 held"), "held by the backstop\n\(trace)")
        let out = samples(try engine.renderOffline(9_600), channel: 0)
        #expect(firstDifference(out[4_096...], song[0][(14_400 + 4_096)..<(14_400 + 9_600)]) == nil,
                "from the frame it reached\n\(trace)")
        let at = try #require(engine.position())
        #expect(abs(at.seconds * rate - 24_000) < 1, "the position, the frame heard: \(at.seconds * rate)\n\(trace)")
    }

    // A lane's count of callbacks is of its own beginning (`epoch`): a seek lets every buffer on the node go, and
    // their callbacks - late here, after the lane has begun again - must not count for what is put on it next, or
    // the lane reads "played all" while it plays, its top-ups are held, and it runs dry mid-song. Without the
    // callbacks held off (0) it is the control: they come before the lane begins again.
    @Test func lateCallbacksOfBuffersLetGoDontCountForTheNext() throws {
        let rate = 48_000.0
        for lag in [0.0, 0.15] {
            let song = signal(frames: 240_000, channels: 2, seed: 0.79)
            let engine = try liveEngine(rate: rate)
            engine.callbackLag = lag
            let trace = traced(engine)
            engine.play(tracksFromWhereAsked([song], rate: rate), from: 0)
            engine.settle()
            _ = try render(engine, frames: 9_600, piece: 4_800)
            for seek in [1.0, 2.0, 0.5] {
                engine.seek(to: seek)
                engine.settle()
                let out = try render(engine, frames: 28_800, piece: 4_800)
                let from = Int(seek * rate)
                #expect(firstDifference(out[4_096...], song[0][(from + 4_096)..<(from + 28_800)]) == nil,
                        "callbacks \(lag) s late: from \(seek) s, unbroken\n\(trace)")
                let at = try #require(engine.position())
                #expect(abs(at.seconds * rate - Double(from + 28_800)) < 1, "callbacks \(lag) s late: the position, the frame heard")
            }
            #expect(!trace.description.contains("held") && !trace.description.contains("ran dry"),
                    "callbacks \(lag) s late: nothing held, nothing run dry\n\(trace)")
        }
    }

    // Findings 3 and 6. A song whose rate isn't the output's (44.1 and 96 kHz on 48 kHz), run dry mid-song: its
    // converter held the last 12-13 ms of what went in (576 song frames at 44.1 kHz, 1152 at 96), and those are
    // the first frames heard when it goes on. Counted from what went INTO the converter, the position - and every
    // pause, call or new route after - was that far ahead of the ear; counted from what came out, it is within a
    // frame. In the designed order (the last completion handled first) and the race's (the bytes read first).
    @Test func aResampledLaneBegunAgainCountsFromTheFrameItGaveOut() throws {
        for songRate in [44_100.0, 96_000.0] {
            for lag in [0.0, 0.25] {
                let song = signal(frames: Int(songRate * 3), channels: 2, seed: 0.87)
                let gate = GatedFrames(song, rate: songRate, arrived: Int(songRate * 1.25))
                let engine = try phoneLikeEngine(rate: 48_000)
                engine.completionLag = lag
                let trace = traced(engine)
                engine.play([gatedTrack(gate, song, rate: songRate)], from: 0)
                engine.settle()
                let what = "\(Int(songRate)) Hz, completions \(lag) s late"
                try #require(engine.phase == .playing, "\(what): started (\(engine.phase))\n\(trace)")
                var before: [Float]
                if lag == 0 {
                    before = try render(engine, frames: 72_000, piece: 4_800) // 1.5 s: the node runs out near 1.25
                    waitFor(engine) { engine.phase == .loading }
                } else {
                    before = try render(engine, frames: 48_000, piece: 4_800)
                    before += samples(try engine.renderOffline(24_000), channel: 0) // runs out unhandled
                }
                try #require(engine.phase == .loading || lag > 0, "\(what): ran dry (\(engine.phase))\n\(trace)")
                let reached = (before.lastIndex { $0 != 0 } ?? -1) + 1 // the output frames the node played
                gate.release()
                waitFor(engine) { engine.phase == .playing && trace.description.contains("ran dry mid-song") }
                try #require(engine.phase == .playing, "\(what): on again (\(engine.phase))\n\(trace)")
                if lag > 0 {
                    #expect(trace.description.contains("entry 0 held"), "\(what): the race\n\(trace)")
                }
                let after = samples(try engine.renderOffline(19_200), channel: 0)
                let first = try #require(after.firstIndex { $0 != 0 }, "\(what): heard again\n\(trace)")
                let heard = Double(reached + after.count - first) * songRate / 48_000 // song frames to the ear
                let at = try #require(engine.position())
                #expect(abs(at.seconds * songRate - heard) <= 1.5,
                        "\(what): the frame heard, \(heard) - said \(at.seconds * songRate)\n\(trace)")
                engine.pause()
                engine.settle()
                let held = try #require(engine.position())
                #expect(abs(held.seconds * songRate - heard) <= 1.5,
                        "\(what): a pause holds the frame heard, \(heard) - held \(held.seconds * songRate)")
            }
        }
    }

    // Finding 4. A 44.1 kHz song on the 48 kHz output whose stream runs dry at its very last frame, its end said
    // only after: its converter still holds its last frames (about 627 of the output's). 98a9d9e never started
    // the lane again (nothing counted on it), silent for good, the queue never ending. They are played - the lane
    // begun again only once they are on its node - and the queue ends, the output stopped.
    @Test func aResampledSongsLastFramesAfterARunDryArePlayedAndTheQueueEnds() throws {
        let song = signal(frames: 22_050, channels: 2, seed: 0.81) // 0.5 s at 44.1 kHz
        let gate = GatedFrames(song, rate: 44_100, arrived: 22_050, endHeld: true)
        let engine = try liveEngine(rate: 48_000)
        let trace = traced(engine)
        engine.play([gatedTrack(gate, song, rate: 44_100)], from: 0)
        engine.settle()
        _ = try render(engine, frames: 28_800, piece: 4_800)
        #expect(engine.phase == .loading, "its lane ran dry at the song's end, the end not yet said\n\(trace)")
        gate.releaseEnd()
        waitFor(engine) { engine.phase != .loading }
        let out = samples(try engine.renderOffline(4_800), channel: 0)
        let sound = out.filter { $0 != 0 }.count
        #expect(sound > 500 && sound < 700, "the converter's last frames heard: \(sound)\n\(trace)")
        let lines = trace.description.components(separatedBy: "\n")
        let flushed = lines.firstIndex { $0.contains("flushed") } ?? Int.max
        let starts = lines.indices.filter { lines[$0].contains("started from silence") }
        #expect(starts.count == 2 && starts[1] > flushed, "begun again only once its last frames were on the node\n\(trace)")
        waitFor(engine) { !engine.outputRunning }
        #expect(engine.phase == .ended && !engine.outputRunning, "the queue's end, the output stopped (\(engine.phase))\n\(trace)")
    }

    // ...and a next song in another format (48 kHz, no converter) starts straight after those frames, bit for
    // bit (98a9d9e: never heard).
    @Test func aResampledSongsLastFramesAfterARunDryThenTheNextSongStraightAfter() throws {
        let song = signal(frames: 22_050, channels: 2, seed: 0.81)
        let next = signal(frames: 24_000, channels: 2, seed: 0.82) // 0.5 s at 48 kHz
        let gate = GatedFrames(song, rate: 44_100, arrived: 22_050, endHeld: true)
        let engine = try liveEngine(rate: 48_000)
        let trace = traced(engine)
        engine.play([gatedTrack(gate, song, rate: 44_100), entry(next, rate: 48_000, key: 1, id: "n")], from: 0)
        engine.settle()
        _ = try render(engine, frames: 28_800, piece: 4_800)
        gate.releaseEnd()
        waitFor(engine) { engine.phase == .playing }
        try #require(engine.phase == .playing, "on with the converter's last frames (\(engine.phase))\n\(trace)")
        let out = try render(engine, frames: 24_000, piece: 4_800)
        let starts = (500..<700).first { k in firstDifference(out[(k + 4_096)..<(k + 8_192)], next[0][4_096..<8_192]) == nil }
        let at = try #require(starts, "the next song nowhere just after the converter's last frames\n\(trace)")
        #expect(out[..<at].filter { $0 != 0 }.count > at - 20, "the converter's last frames, then the next song at once")
        #expect(firstDifference(out[(at + 4_096)..<(at + 20_000)], next[0][4_096..<20_000]) == nil, "the next song, bit for bit")
    }

    // A 44.1 kHz lane whose node ran out at its song's end with its converter still holding that end (the next
    // song in the same format not come yet): those frames used to be laid on the node that had run out and played
    // after the silence, counted straight on - the next song's position 1650 frames ahead (11250 for 9600). The
    // lane starts again with them, counted where they play, and the next song goes on straight after.
    @Test func aConverterTailAfterTheNodeRanOutIsCountedWhereItPlays() throws {
        let songRate = 44_100.0
        let a = signal(frames: 44_100, channels: 2, seed: 0.98)
        let b = signal(frames: 88_200, channels: 2, seed: 0.99)
        let gate = GatedFrames(b, rate: songRate, arrived: 0)
        let engine = try liveEngine(rate: 48_000)
        engine.completionLag = 0.25
        let trace = traced(engine)
        engine.play([entry(a, rate: songRate, key: 0, id: "a"), gatedTrack(gate, b, rate: songRate, key: 1, id: "b")], from: 0)
        engine.settle()
        _ = try render(engine, frames: 43_200, piece: 4_800)
        _ = try engine.renderOffline(4_800 + 1_024)
        let handled = engine.callbacksDone
        gate.release()
        waitFor(engine) { engine.callbacksDone > handled && trace.description.contains("converter holding") && engine.phase == .playing }
        try #require(engine.phase == .playing, "on (\(engine.phase))\n\(trace)")
        let tail = samples(try engine.renderOffline(627), channel: 0)
        #expect(tail.filter { $0 != 0 }.count > 600, "A's last frames first\n\(trace)")
        _ = try render(engine, frames: 9_600, piece: 4_800)
        let at = try #require(engine.position())
        #expect(at.key == 1 && abs(at.seconds * 48_000 - 9_600) < 3, "B at the frame heard: \(at.seconds * 48_000)\n\(trace)")
    }

    // Findings 2 and 11. A song at the output's rate (no converter) whose stream runs dry at its very last frame,
    // its end said after: nothing of it is left anywhere. 70cbef6 played silence for good saying playing, and
    // 98a9d9e said loading for good, the output running both times. The queue ends, the output stopped, the
    // position at the song's end.
    @Test func aLaneBegunAgainWithNothingLeftEndsTheQueue() throws {
        let song = signal(frames: 24_000, channels: 2, seed: 0.83)
        let gate = GatedFrames(song, rate: 48_000, arrived: 24_000, endHeld: true)
        let engine = try liveEngine(rate: 48_000)
        let trace = traced(engine)
        engine.play([gatedTrack(gate, song, rate: 48_000)], from: 0)
        engine.settle()
        _ = try render(engine, frames: 28_800, piece: 4_800)
        #expect(engine.phase == .loading, "ran dry at the song's end\n\(trace)")
        gate.releaseEnd()
        waitFor(engine) { engine.phase == .ended && !engine.outputRunning }
        #expect(engine.phase == .ended && !engine.outputRunning, "the queue's end (\(engine.phase))\n\(trace)")
        let at = try #require(engine.position())
        #expect(at.key == 0 && abs(at.seconds - 0.5) < 1e-9, "left at the song's end: \(at)")
    }

    // ...and a next song in another format starts from silence, its position its own (before: never heard).
    @Test func aLaneBegunAgainWithNothingLeftThenASongInAnotherFormat() throws {
        let song = signal(frames: 24_000, channels: 2, seed: 0.83)
        let next = signal(frames: 48_000, channels: 2, seed: 0.84) // 0.5 s at 96 kHz
        let gate = GatedFrames(song, rate: 48_000, arrived: 24_000, endHeld: true)
        let engine = try liveEngine(rate: 48_000)
        let trace = traced(engine)
        engine.play([gatedTrack(gate, song, rate: 48_000), entry(next, rate: 96_000, key: 1, id: "n")], from: 0)
        engine.settle()
        _ = try render(engine, frames: 28_800, piece: 4_800)
        gate.releaseEnd()
        waitFor(engine) { engine.phase == .playing }
        try #require(engine.phase == .playing, "the next song started (\(engine.phase))\n\(trace)")
        let out = samples(try engine.renderOffline(9_600), channel: 0)
        #expect(energy(out[4_096...]) > 0.01, "the next song heard\n\(trace)")
        let at = try #require(engine.position())
        #expect(at.key == 1 && abs(at.seconds - 0.2) < 1e-6, "the position is the next song's: \(at)\n\(trace)")
    }

    // Finding 10's trade, pinned: a lane begun again with nothing left, the next song in the same format still
    // behind. Its lane isn't started with nothing on it (70cbef6 started it empty, its clock running through the
    // wait, and counted the next song ahead of the ear by that wait); the next song starts from its own first
    // frame once it is on the node, counted exactly.
    @Test func aLaneBegunAgainEmptyThenTheSameFormatBehindCountsFromItsOwnStart() throws {
        let a = signal(frames: 24_000, channels: 2, seed: 0.85)
        let b = signal(frames: 48_000, channels: 2, seed: 0.86)
        let gateA = GatedFrames(a, rate: 48_000, arrived: 24_000, endHeld: true)
        let gateB = GatedFrames(b, rate: 48_000, arrived: 0)
        let engine = try liveEngine(rate: 48_000)
        let trace = traced(engine)
        engine.play([gatedTrack(gateA, a, rate: 48_000), gatedTrack(gateB, b, rate: 48_000, key: 1, id: "b")], from: 0)
        engine.settle()
        _ = try render(engine, frames: 28_800, piece: 4_800)
        gateA.releaseEnd()
        waitFor(engine) { engine.debug().feedKey == 1 }
        _ = try engine.renderOffline(4_800) // B not come yet: a node started now would count this silence
        gateB.release()
        waitFor(engine) { engine.phase == .playing }
        try #require(engine.phase == .playing, "B on (\(engine.phase))\n\(trace)")
        let out = samples(try engine.renderOffline(9_600), channel: 0)
        #expect(firstDifference(out[4_096...], b[0][4_096..<9_600]) == nil, "B from its start\n\(trace)")
        let at = try #require(engine.position())
        #expect(at.key == 1 && abs(at.seconds - 0.2) < 1e-6, "B where the ear is: \(at)\n\(trace)")
        engine.pause()
        engine.settle()
        engine.resume()
        engine.settle()
        let after = samples(try engine.renderOffline(9_600), channel: 0)
        #expect(firstDifference(after[4_096...], b[0][(9_600 + 4_096)..<19_200]) == nil, "a pause and play go on from it\n\(trace)")
    }

    // A seek to a song's very end - or a queue put back there, and play - opens nothing of it: on to the next
    // song from its start (it waited for good: no lane held the song heard, so nothing started the next).
    @Test func aSeekOrAResumeAtASongsVeryEndPlaysTheNext() throws {
        let rate = 48_000.0
        let a = signal(frames: 48_000, channels: 2, seed: 0.93)
        let b = signal(frames: 48_000, channels: 2, seed: 0.94)
        for resume in [false, true] {
            let engine = try liveEngine(rate: rate)
            let trace = traced(engine)
            if resume {
                engine.restoreQueue(tracksFromWhereAsked([a, b], rate: rate), at: 0, seconds: 1.0)
                engine.settle()
                engine.resume()
            } else {
                engine.play(tracksFromWhereAsked([a, b], rate: rate), from: 0)
                engine.settle()
                _ = try render(engine, frames: 4_800, piece: 4_800)
                engine.seek(to: 1.0)
            }
            let how = resume ? "play at the very end" : "a seek to the very end"
            waitFor(engine) { engine.phase == .playing && engine.stateNow.key == 1 }
            #expect(engine.phase == .playing && engine.stateNow.key == 1,
                    "\(how): the next song (\(engine.phase), \(String(describing: engine.stateNow.key)))\n\(trace)")
            let out = samples(try engine.renderOffline(9_600), channel: 0)
            #expect(firstDifference(out[4_096...], b[0][4_096..<9_600]) == nil, "\(how): from its start\n\(trace)")
        }
    }

    // Finding 5. A song in another format whose bytes come after the heard lane has played all on it (its last
    // completion late) was started at that lane's end - a time the render had passed - so its count ran ahead by
    // the silence and the song after it started that much early, over its end (B's position 25024 for 24000, C at
    // 23488). It starts from silence once the lane's completions are handled, exactly.
    @Test func anotherFormatLateAfterTheLaneRanOutStartsWhereItIsHeard() throws {
        try anotherFormatLate(lag: { $0.completionLag = 0.25 })
    }

    // ...and with AVAudioEngine's own callbacks late, so no callback says A ran out while the render is past its
    // end: only "never at an end already rendered" can see it.
    @Test func anotherFormatAfterAnEndAlreadyRenderedWithCallbacksLate() throws {
        try anotherFormatLate(lag: { $0.callbackLag = 0.25 })
    }

    private func anotherFormatLate(lag: (PlaybackEngine) -> Void, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let a = signal(frames: 24_000, channels: 2, seed: 0.95)
        let b = signal(frames: 48_000, channels: 2, seed: 0.96) // 0.5 s at 96 kHz
        let c = signal(frames: 24_000, channels: 2, seed: 0.97)
        let gate = GatedFrames(b, rate: 96_000, arrived: 0)
        let engine = try liveEngine(rate: 48_000, ahead: 3)
        lag(engine)
        let trace = traced(engine)
        engine.play([entry(a, rate: 48_000, key: 0, id: "a"), gatedTrack(gate, b, rate: 96_000, key: 1, id: "b"),
                     entry(c, rate: 48_000, key: 2, id: "c")], from: 0)
        engine.settle()
        _ = try engine.renderOffline(24_512)
        gate.release()
        waitFor(engine) { trace.description.contains("lane 96000 Hz") && engine.callbacksDone >= 5 && engine.phase == .playing }
        try #require(engine.phase == .playing, "B on (\(engine.phase))\n\(trace)", sourceLocation: sourceLocation)
        var out = samples(try engine.renderOffline(12_000), channel: 0)
        let mid = try #require(engine.position(), sourceLocation: sourceLocation)
        #expect(mid.key == 1 && abs(mid.seconds * 96_000 - 24_000) < 3, "mid-B, the frame heard: \(mid.seconds * 96_000)\n\(trace)",
                sourceLocation: sourceLocation)
        out += samples(try engine.renderOffline(36_000), channel: 0)
        // B's 24000 frames from the render's first after A's end; C straight after, alone
        let probe = Array(c[0][4_096..<4_160])
        let found = (20_000..<30_000).first { start in (0..<64).allSatisfy { out[start + $0] == probe[$0] } }
        let cAt = found.map { $0 - 4_096 }
        #expect(cAt.map { $0 >= 24_000 && $0 <= 24_002 } == true,
                "C at \(cAt.map(String.init) ?? "nowhere"), straight after B's 24000 frames\n\(trace)", sourceLocation: sourceLocation)
        if let cAt {
            #expect(firstDifference(out[(cAt + 4_096)..<(cAt + 14_000)], c[0][4_096..<14_000]) == nil,
                    "C alone, nothing of B under it", sourceLocation: sourceLocation)
        }
    }

    // Findings 7 and 9. The start lead (the output's latency and an IO buffer: about 0.2 s on AirPods, 2 s on
    // AirPlay) is for an output just started, so its first sample lands on a live output. On one that has run all
    // along - a lane begun again after running dry, a skip or a seek while playing - it was only silence the
    // listener waited through. Play after a pause and a new route start the output again, and take it.
    @Test func theLeadIsTakenOnlyOnAnOutputJustStarted() throws {
        let rate = 48_000.0
        let song = signal(frames: 96_000, channels: 2, seed: 0.83)
        let other = signal(frames: 96_000, channels: 2, seed: 0.84)
        let gate = GatedFrames(song, rate: rate, arrived: 24_000)
        let engine = try liveEngine(rate: rate)
        engine.startLead = { 0.25 }
        let trace = traced(engine)
        engine.play([gatedTrack(gate, song, rate: rate), entry(other, rate: rate, key: 1, id: "o")], from: 0)
        engine.settle()
        #expect(engine.leadsTaken == [0.25], "the first start, on an output just started\n\(trace)")
        #expect(engine.stateNow.lastStartLead == 0.25)
        _ = try render(engine, frames: 24_000 + 12_000 + 4_800, piece: 4_800)
        waitFor(engine) { engine.phase == .loading }
        try #require(engine.phase == .loading, "ran dry (\(engine.phase))\n\(trace)")
        gate.release()
        waitFor(engine) { engine.phase == .playing }
        try #require(engine.phase == .playing, "on again\n\(trace)")
        #expect(engine.leadsTaken == [0.25, 0], "begun again on the running output: no lead\n\(trace)")
        #expect(engine.stateNow.lastStartLead == 0)
        engine.skip(to: 1)
        engine.settle()
        #expect(engine.leadsTaken == [0.25, 0, 0], "a skip while playing: no lead")
        _ = try render(engine, frames: 4_800, piece: 4_800)
        engine.seek(to: 1.5)
        engine.settle()
        #expect(engine.leadsTaken == [0.25, 0, 0, 0], "a seek while playing: no lead")
        engine.pause()
        engine.settle()
        engine.resume()
        engine.settle()
        #expect(engine.leadsTaken == [0.25, 0, 0, 0, 0.25], "play after a pause starts the output again: the lead")
        _ = try render(engine, frames: 4_800, piece: 4_800)
        engine.systemStopped(change: true) // a new route
        engine.settle()
        #expect(engine.leadsTaken == [0.25, 0, 0, 0, 0.25, 0.25], "a new route starts the output again: the lead\n\(trace)")
    }
}
#endif
