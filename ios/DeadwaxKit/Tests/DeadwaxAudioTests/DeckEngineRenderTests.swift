#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

/// The deck engine's sound (notes/ios-specs/turntable.md 4.3, 7.2): the source node's output, through the rings, the
/// mixer at unity and the engine's offline render, bit for bit Core's voice for the same messages - over test A's
/// cases (Core's Fixtures/deck/voice), each run rendered in its own blocks of 128 or 1,024 - and with an EQ curve on
/// the deck (eq.md 1.9), bit for bit Core's voice run through EQRender for the same bank.
@Suite(.serialized) struct DeckEngineRenderTests {
    @Test func theSourceNodeIsCoresVoiceBitForBit() throws {
        let cases = try DeckCases.cases()
        #expect(cases.count >= 8)
        var runs = 0
        for c in cases {
            for run in c.runs where run.block == 128 || run.block == 1_024 {
                let what = "\(c.name) at \(Int(run.rate)) Hz in blocks of \(run.block) from \(run.from)"
                let expected = DeckCases.reference(c, run)
                let engine = try DeckCases.offlineDeck(rate: run.rate, maximumFrames: run.block, messageCapacity: 4_096)
                let got = try DeckCases.deck(c, run, engine: engine)
                runs += 1
                if let at = DeckCases.firstBitDifference(got, expected) {
                    let gotValue: Float = at < got.count ? got[at] : .nan
                    let wantValue: Float = at < expected.count ? expected[at] : .nan
                    Issue.record("\(what): the deck engine first differs at frame \(at / 2), channel \(at % 2) (\(gotValue) against \(wantValue))")
                }
                let status = engine.status()
                #expect(status.dropped == 0 && status.refused == 0, "\(what)")
            }
        }
        print("DeckEngineRenderTests: \(runs) runs of \(cases.count) cases through the deck engine, bit for bit Core's voice")
        #expect(runs >= 20)
    }

    /// eq.md 1.9: the deck's output with a curve is Core's voice run through EQRender for the same bank, bit for bit.
    @Test func theDecksEQIsEQRenderAfterTheVoice() throws {
        let cases = try DeckCases.cases()
        let c = try #require(cases.first { $0.name == "hand-turns" } ?? cases.first)
        let run = try #require(c.runs.first { $0.block == 128 && $0.rate == 48_000 } ?? c.runs.first { $0.block == 128 })
        let bank = EQTestCurve.bank(on: true, rate: run.rate, version: 1)
        #expect(!bank.isIdentity, "a curve that filters")

        let state = EQRender.make(rate: run.rate, channels: 2, maximumFrames: run.block)
        defer { EQRender.free(state) }
        let packed = bank.packed
        var first = true
        let expected = DeckCases.reference(c, run) { (outputs: UnsafeMutablePointer<UnsafeMutablePointer<Float>>, n: Int) -> Void in
            packed.withUnsafeBufferPointer { (bankDoubles: UnsafeBufferPointer<Double>) -> Void in
                EQRender.process(state, buffers: UnsafePointer(outputs), frames: n, offered: first ? bankDoubles.baseAddress : nil)
            }
            first = false
        }
        let plain = DeckCases.reference(c, run)
        #expect(DeckCases.firstBitDifference(expected, plain) != nil, "the curve changes the sound")

        let engine = try DeckCases.offlineDeck(rate: run.rate, maximumFrames: run.block, messageCapacity: 4_096)
        let host = try #require(engine.eq)
        host.setOutput(EQTestCurve.key)
        #expect(host.publish(bank))
        let got = try DeckCases.deck(c, run, engine: engine)
        if let at = DeckCases.firstBitDifference(got, expected) {
            Issue.record("the deck's EQ first differs at frame \(at / 2): \(got[at]) against \(expected[at])")
        }
        let status = host.status()
        print("DeckEngineRenderTests EQ: \(run.frames) frames of \(c.name) through the deck's EQ; \(status.blocks) blocks, "
              + "mode \(status.mode)")
        #expect(engine.status().eqBlocks == (run.frames + run.block - 1) / run.block)
    }

    /// The deck engine's start and stop: L from twice the IO buffer, the voice kept across a stop (as the web's
    /// suspended context), reset only while stopped, and a new rate making the source node and the voice again.
    @Test func startStopAndReset() throws {
        let engine = try DeckCases.offlineDeck(rate: 48_000)
        engine.ioBuffer = { 0.0213 }
        try engine.start()
        #expect(engine.isRunning && engine.rate == 48_000)
        let pcm = DeckPCM([[Float](repeating: 0.25, count: 48_000), [Float](repeating: -0.25, count: 48_000)])
        #expect(engine.post(.window(DeckWindow(pcm: pcm, start: 0, end: 1, rate: 48_000, source: .file, bytes: 0, madeIn: 0))))
        #expect(engine.post(.take(at: 0.5, rate: 1, time: 0, until: .infinity)))
        _ = try engine.renderOffline(1_024)
        var status = engine.status()
        #expect(status.messages == 2 && status.windowsLive == 1 && status.blocks == 1)
        // a second window replaces the first: the first comes back to be freed
        #expect(engine.post(.window(DeckWindow(pcm: DeckPCM([[0.1, 0.1], [0.1, 0.1]]), start: 0, end: 1, rate: 48_000,
                                               source: .file, bytes: 0, madeIn: 0))))
        _ = try engine.renderOffline(1_024)
        status = engine.status()
        #expect(status.windowsReturned == 1 && status.windowsLive == 1, "\(status)")
        engine.stop()
        #expect(!engine.isRunning && engine.status().stops == 1)
        engine.reset()
        #expect(engine.status().windowsLive == 0)
        try engine.start()
        #expect(engine.status().starts == 2)
        engine.stop()
    }

    /// Debug's run (DeckTrial, checks 0a-0c): the hand grabs the record where the take has it and at its speed, and lets
    /// go where it grabbed at speed 1, so the run's only cut is the loop's top; its record is 6 s, loud enough to hear
    /// and nowhere near the limiter.
    @Test func debugsRunIsContinuous() {
        let grab = DeckTrial.takeFrom + DeckTrial.grabS
        #expect(DeckTrial.hand(DeckTrial.grabS) == grab)
        #expect(abs(DeckTrial.hand(DeckTrial.letGoS) - grab) < 1e-12)
        let h = 1e-7
        #expect(abs((DeckTrial.hand(DeckTrial.grabS + h) - DeckTrial.hand(DeckTrial.grabS)) / h - 1) < 1e-4)
        #expect(abs((DeckTrial.hand(DeckTrial.letGoS) - DeckTrial.hand(DeckTrial.letGoS - h)) / h - 1) < 1e-4)
        #expect(grab + DeckTrial.loopS - DeckTrial.letGoS <= 6, "the drive ends inside the record")
        let record = DeckTrial.record(rate: 44_100)
        #expect(record.frames == 6 * 44_100 && record.channelCount == 2)
        let peak = (0..<record.frames).reduce(Float(0)) { max($0, abs(record.channel(0)[$1])) }
        #expect(peak > 0.15 && peak < 0.5, "peak \(peak)")
    }
}
#endif
