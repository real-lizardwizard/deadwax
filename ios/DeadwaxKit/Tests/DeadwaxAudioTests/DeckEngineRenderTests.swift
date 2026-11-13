#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
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

    /// eq.md 1.6, 1.9: every start of the deck engine installs the newest bank at its first block - states zeroed, no
    /// crossfade - as the song's unit does at every allocation, not a crossfade from the run before the stop with its
    /// filters' state. Two decks given the same messages, one with the EQ and one without: after a stop and a start the
    /// first's block is a fresh EQRender over the second's, bit for bit; and a curve turned Off while the deck is
    /// stopped is Off from the restart's first sample - the voice itself, bit for bit.
    @Test func theDecksEQStartsAfreshAtEveryStart() throws {
        let rate = 48_000.0, frames = 512
        let withEQ = try DeckCases.offlineDeck(rate: rate, maximumFrames: frames)
        let plain = try DeckCases.offlineDeck(rate: rate, maximumFrames: frames, eq: false)
        let host = try #require(withEQ.eq)
        host.setOutput(EQTestCurve.key)
        let curve = EQTestCurve.bank(on: true, rate: rate, version: 1)
        #expect(host.publish(curve))
        let pcm = DeckPCM((0..<2).map { (c: Int) -> [Float] in
            (0..<(4 * 48_000)).map { (i: Int) -> Float in Float(sin(Double(i) * 0.3 * Double(c + 1)) * 0.4) }
        })
        var done = 0
        func start(_ deck: DeckEngine) throws {
            try deck.start()
            // the voice's clock carried on from where it stopped, whatever the offline render's sample time does
            deck.setOfflineClock(frames: Double(done) - Double(deck.engine.manualRenderingSampleTime))
        }
        func block(_ deck: DeckEngine) throws -> [[Float]] {
            let buffer = try deck.renderOffline(AVAudioFrameCount(frames))
            return [samples(buffer, channel: 0), samples(buffer, channel: 1)]
        }
        for deck in [withEQ, plain] {
            try start(deck)
            #expect(deck.post(.window(pcm.voiceWindow(start: 0, rate: rate)), keeping: pcm))
            #expect(deck.post(.take(at: 0.5, rate: 1, time: 0, until: .infinity), keeping: nil))
        }
        // 0.32 s: the record sounding (from the hand's 0.12 s behind), the curve's filters full of it
        for _ in 0..<30 {
            _ = try block(withEQ)
            _ = try block(plain)
            done += frames
        }
        withEQ.stop()
        plain.stop()
        try start(withEQ)
        try start(plain)
        let filtered = try block(withEQ), voice = try block(plain)
        done += frames
        #expect(voice[0].contains { $0 != 0 }, "the record sounds across the restart")
        // the curve installed afresh - a state just made, the bank offered at its first block - over the voice's block
        let fresh = EQRender.make(rate: rate, channels: 2, maximumFrames: frames)
        let channels = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 2)
        channels[0] = .allocate(capacity: frames)
        channels[1] = .allocate(capacity: frames)
        defer {
            EQRender.free(fresh)
            channels[0].deallocate()
            channels[1].deallocate()
            channels.deallocate()
        }
        channels[0].update(from: voice[0], count: frames)
        channels[1].update(from: voice[1], count: frames)
        curve.packed.withUnsafeBufferPointer { (bank: UnsafeBufferPointer<Double>) -> Void in
            EQRender.process(fresh, buffers: UnsafePointer(channels), frames: frames, offered: bank.baseAddress)
        }
        let expected = (0..<2).map { (c: Int) -> [Float] in Array(UnsafeBufferPointer(start: channels[c], count: frames)) }
        for c in 0..<2 {
            #expect(DeckCases.firstBitDifference(filtered[c], expected[c]) == nil,
                    "channel \(c): the restart's first block is the curve installed afresh over the voice")
        }
        #expect(host.status().crossfades == 0, "installed, not crossfaded")

        // Off while stopped: Off from the first sample of the next start
        withEQ.stop()
        plain.stop()
        #expect(host.publish(EQTestCurve.bank(on: false, rate: rate, version: 2)))
        try start(withEQ)
        try start(plain)
        let off = try block(withEQ), untouched = try block(plain)
        for c in 0..<2 {
            #expect(DeckCases.firstBitDifference(off[c], untouched[c]) == nil, "channel \(c): Off is the voice, bit for bit")
        }
        #expect(host.status().crossfades == 0 && host.status().mode == .passing)
        withEQ.stop()
        plain.stop()
    }

    /// 4.3's rings when full: a full message ring drops the message and counts it - the producer never waits - and a
    /// window it dropped isn't kept; a full return ring keeps a window the voice let go of (counted) rather than free it
    /// on the audio thread, until the voice is reset.
    @Test func fullRingsDropKeepAndCount() throws {
        let rate = 48_000.0
        let deck = try DeckCases.offlineDeck(rate: rate, eq: false, messageCapacity: 16)
        let returns = Int(DeckEngine.returnCapacity)
        let windows = (0..<12).map { (k: Int) -> DeckPCM in DeckPCM([[Float](repeating: Float(k) / 100, count: 64)]) }
        // stopped, so nothing reads the ring: twelve windows and four takes fill it
        for window in windows { #expect(deck.post(.window(window.voiceWindow(start: 0, rate: rate)), keeping: window)) }
        for _ in 0..<4 { #expect(deck.post(.take(at: 0, rate: 1, time: 0, until: .infinity), keeping: nil)) }
        #expect(!deck.post(.window(windows[0].voiceWindow(start: 0, rate: rate)), keeping: windows[0]))
        #expect(!deck.post(.stop, keeping: nil))
        var status = deck.status()
        #expect(status.dropped == 2 && status.windowsLive == 12, "the window dropped isn't kept: \(status)")
        // one block applies all sixteen: eleven windows let go at once, as many as the return ring holds back through it
        try deck.start()
        defer { deck.stop() }
        _ = try deck.renderOffline(512)
        status = deck.status()
        #expect(status.messages == 16 && status.windowsReturned == returns && status.windowsKept == 11 - returns, "\(status)")
        #expect(status.windowsLive == 12 - returns, "those returned freed; those kept, and the one in use, still live")
        deck.stop()
        deck.reset()
        #expect(deck.status().windowsLive == 0)
    }

    /// 4.3: a window comes back to be freed only once the voice has let go of it - the one replaced, never the one now
    /// in use (the counts alone can't tell the two apart: either way one comes back and one stays live).
    @Test func aWindowIsGivenBackOnlyOnceTheVoiceLetsGoOfIt() throws {
        let rate = 48_000.0
        let deck = try DeckCases.offlineDeck(rate: rate, eq: false)
        try deck.start()
        defer { deck.stop() }
        let a = DeckPCM([[Float](repeating: 0.1, count: 4_800)]), b = DeckPCM([[Float](repeating: 0.2, count: 4_800)])
        #expect(deck.post(.window(a.voiceWindow(start: 0, rate: rate)), keeping: a))
        _ = try deck.renderOffline(512)
        #expect(deck.post(.window(b.voiceWindow(start: 0, rate: rate)), keeping: b))
        _ = try deck.renderOffline(512)
        deck.collect()
        let onlyB = deck.live.values.allSatisfy { (pcm: DeckPCM) -> Bool in pcm === b }
        #expect(deck.live.count == 1 && onlyB, "a given back, b the voice's")
        #expect(deck.post(.window(nil), keeping: nil))
        _ = try deck.renderOffline(512)
        deck.collect()
        #expect(deck.live.isEmpty, "no window: b given back too")
    }

    /// 3.2 in the render: `L` follows the largest lead at once while the voice is quiet, and under a sound - the
    /// voice's own gain, as each block begins - only at CLOCK_SLEW, so the record's clock never steps under a hand.
    @Test func theRendersClockSlewsUnderASound() throws {
        let rate = 48_000.0, frames = 512
        let deck = try DeckCases.offlineDeck(rate: rate, maximumFrames: frames, eq: false)
        deck.host.pointee.offline = false
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: 2 * frames)
        storage.initialize(repeating: 0, count: 2 * frames)
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        let time = UnsafeMutablePointer<AudioTimeStamp>.allocate(capacity: 1)
        time.initialize(to: AudioTimeStamp())
        defer {
            storage.deallocate()
            free(list.unsafeMutablePointer)
            time.deallocate()
        }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticksPerSecond = 1e9 * Double(timebase.denom) / Double(timebase.numer)
        // a block presented `ahead` after it is made: its lead about `ahead` plus the block
        func call(ahead: Double) throws -> Double {
            for c in 0..<2 {
                list[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: UnsafeMutableRawPointer(storage + c * frames))
            }
            time.pointee.mFlags = [.sampleTimeValid, .hostTimeValid]
            time.pointee.mHostTime = UInt64((PlaybackEngine.hostSeconds() + ahead) * ticksPerSecond)
            #expect(DeckVoiceHost.render(deck.host, time, UInt32(frames), list.unsafeMutablePointer) == noErr)
            return try #require(deck.status().lead)
        }
        let block = Double(frames) / rate
        var quiet = 0.0
        for _ in 0..<20 { quiet = try call(ahead: 0.010) }
        #expect(abs(quiet - (0.010 + block)) < 0.002, "quiet: L is the lead (\(quiet))")
        // the record taken: sounding from the next block, when the leads grow by 20 ms
        let pcm = DeckPCM([[Float](repeating: 0.25, count: 96_000)])
        #expect(deck.post(.window(pcm.voiceWindow(start: 0, rate: rate)), keeping: pcm))
        #expect(deck.post(.take(at: 1, rate: 1, time: PlaybackEngine.hostSeconds(), until: .infinity), keeping: nil))
        _ = try call(ahead: 0.010)
        var sounding = 0.0
        for _ in 0..<20 { sounding = try call(ahead: 0.030) }
        #expect(abs(sounding - quiet) < 0.001, "under a sound L slews, never steps (\(quiet) -> \(sounding))")
        // stopped, and quiet again: straight to the largest lead
        #expect(deck.post(.stop, keeping: nil))
        var after = 0.0
        for _ in 0..<40 { after = try call(ahead: 0.030) }
        #expect(abs(after - (0.030 + block)) < 0.002, "quiet again: L at the lead (\(after))")
    }

    /// Reports no one reads are kept as their ring keeps them - the newest 2 s - not for as long as the engine plays
    /// (Debug's run reads none; every post collects them).
    @Test func unreadReportsDontPileUp() throws {
        let deck = try DeckCases.offlineDeck(rate: 48_000, eq: false)
        try deck.start()
        defer { deck.stop() }
        // 6.4 s: 192 reports
        for _ in 0..<300 {
            _ = try deck.renderOffline(1_024)
            deck.collect()
        }
        let kept = deck.reports()
        #expect(kept.count == Int(DeckEngine.reportCapacity))
        #expect((kept.last?.time ?? 0) > 6.3, "the newest kept")
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
