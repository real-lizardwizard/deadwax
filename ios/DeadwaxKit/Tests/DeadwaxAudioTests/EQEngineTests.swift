#if canImport(AVFAudio)
import AVFAudio
import AudioToolbox
import CAudioRing
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// The EQ's engine (notes/ios-specs/eq.md 1.7, slice 2): its unit in the graph, rendered offline through the real
// AVAudioEngine, against an engine with no unit at all and against Core's own render. Test 1 is every other render
// test in this target, unchanged, each engine now with the unit in its graph and Off. Tests 5, 8, 9 and 10 call the
// render directly: EQRealTimeTests. Test 3 is EQClickTests.

@Suite(.serialized) struct EQEngineTests {
    /// 1.2's first question: `AVAudioUnitEffect(audioComponentDescription:)` hands back our subclass, in-process and
    /// at once - so `configure` stays synchronous and needs no app extension.
    @Test func theUnitIsOurs() throws {
        EQUnit.register()
        let effect = AVAudioUnitEffect(audioComponentDescription: EQUnit.component)
        let unit = effect.auAudioUnit
        print("EQ unit: AVAudioUnitEffect(audioComponentDescription:) gave \(type(of: unit)), "
              + "in-process \(unit is EQUnit), latency \(unit.latency), tail \(unit.tailTime), "
              + "in place \(unit.canProcessInPlace), largest block \(unit.maximumFramesToRender)")
        #expect(unit is EQUnit, "the unit made is \(type(of: unit)), not EQUnit")
        #expect(unit.latency == 0 && unit.tailTime == 0 && unit.canProcessInPlace)
        #expect(unit.maximumFramesToRender == 4_096)
        // and the engine's own way of making it agrees
        let node = try EQUnit.node()
        #expect(node.auAudioUnit is EQUnit)
    }

    /// Test 2: a 30 s song of seeded noise and a 20 Hz-20 kHz log sweep, each channel its own, written as a 44.1 kHz
    /// FLAC and rendered to a 48 kHz output (so the lane's converter runs too), is the same bit for bit with the unit
    /// Off, with the unit On at a flat curve (put in at the start and again while it plays), and with no unit at all.
    @Test func offIsBitForBitNoUnitAtAll() throws {
        let fileRate = 44_100.0, rate = 48_000.0
        let song = noiseAndSweep(seconds: 30, rate: fileRate)
        guard let url = flacFile(song, rate: fileRate) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = Int(30 * rate)

        func rendered(eq: Bool, flat: Bool) throws -> (out: [[Float]], status: EQUnitStatus?) {
            let engine = try eqEngine(rate: rate, eq: eq)
            var version = 0
            if flat {
                engine.eqStart = { host, unitRate, _ in
                    host.setOutput(EQTestCurve.key)
                    host.publish(toneBank(EQGraphic.flat, rate: unitRate, version: 0, preamp: nil))
                }
            }
            engine.play([EngineTrack(key: 0, audio: "noise|off", song: Song(id: "noise")) { start in
                try FileSource(url: url, start: start)
            }], from: 0)
            engine.settle()
            let out = try renderChannels(engine, frames: frames) { done in
                // a flat curve put in again while it plays, every 5 s: a correction of 0 dB filters and the tone at 0
                guard flat, done > 0, done % (4_096 * 60) == 0, let host = engine.eq else { return }
                version += 1
                let zero = [EQFilter(id: 1, kind: .peak, fc: 1_000, gain: 0, width: .q(1)),
                            EQFilter(id: 2, kind: .lowShelf, fc: 100, gain: 0)]
                host.publish(EQBank.make(rate: rate, key: EQTestCurve.key, version: version, on: true,
                                         correction: zero, offsets: .zero, bands: EQGraphic.flat, preamp: nil))
            }
            return (out, engine.debug().eq)
        }

        let none = try rendered(eq: false, flat: false)
        let off = try rendered(eq: true, flat: false)
        let flat = try rendered(eq: true, flat: true)
        #expect(none.status == nil)
        let sound = none.out[0].firstIndex { $0 != 0 } ?? -1
        print("EQ Off: \(frames) frames x 2 rendered with no unit, the unit Off and the unit at a flat curve; "
              + "the song's first sound at frame \(sound); the unit Off: \(off.status.map(describe) ?? "none"); "
              + "at a flat curve: \(flat.status.map(describe) ?? "none")")
        #expect(sound >= 0 && sound < 8_192, "the render holds the song")
        #expect(firstBitDifference(off.out, none.out) == nil, "the unit Off: \(firstBitDifference(off.out, none.out) ?? "")")
        #expect(firstBitDifference(flat.out, none.out) == nil, "a flat curve: \(firstBitDifference(flat.out, none.out) ?? "")")
        for status in [off.status, flat.status] {
            // the unit really was in the graph, rendering, and passing everything through
            #expect(status?.mode == .passing && (status?.blocks ?? 0) >= frames / 4_096 - 1 && status?.crossfades == 0)
        }
    }

    /// Test 4: joins unbroken through a curve that boosts - one tone cut in two (test sounds 9 and 10: 440 Hz at
    /// -12 dBFS, 44.1 kHz, cut near a peak), and a lane change from a 44.1 kHz song to a 96 kHz one - and the unit's
    /// output is Core's `EQRender` over the same engine's render with no unit, sample for sample.
    @Test func joinsAreUnbrokenAndTheUnitIsCoresRender() throws {
        let rate = 48_000.0
        let boost = [5.0, 4.5, 3, 1, 0, 0, 0, 1, 2.5, 3]   // Loudness's shape, played at 0 dB of preamp: it boosts
        let cut = 44_100 + 25                              // a quarter of 440 Hz's period past 1 s: near a peak
        let whole = (0..<88_200).map { (n: Int) -> Float in Float(0.25 * sin(2 * Double.pi * 440 * Double(n) / 44_100)) }
        let tone = [Array(whole[..<cut]), Array(whole[cut...])]
        let a = signal(frames: 22_050, channels: 2, seed: 0.3)          // 0.5 s at 44.1 kHz
        let b = signal(frames: 48_000, channels: 2, seed: 0.9)          // 0.5 s at 96 kHz
        let cases: [(name: String, tracks: [EngineTrack], seconds: Double)] = [
            ("one tone cut in two", [memoryTrack([tone[0], tone[0]], rate: 44_100, key: 0),
                                     memoryTrack([tone[1], tone[1]], rate: 44_100, key: 1)], 2),
            ("44.1 kHz into 96 kHz", [memoryTrack(a, rate: 44_100, key: 0), memoryTrack(b, rate: 96_000, key: 1)], 1),
        ]
        for (name, tracks, seconds) in cases {
            let frames = Int(seconds * rate)
            let bank = toneBank(boost, rate: rate, version: 0)
            func rendered(eq: Bool) throws -> [[Float]] {
                let engine = try eqEngine(rate: rate, eq: eq)
                engine.eqStart = { host, unitRate, _ in
                    host.setOutput(EQTestCurve.key)
                    host.publish(toneBank(boost, rate: unitRate, version: 0))
                }
                engine.play(tracks, from: 0)
                engine.settle()
                return try renderChannels(engine, frames: frames)
            }
            let plain = try rendered(eq: false)
            let unit = try rendered(eq: true)
            let core = coreRender(plain, rate: rate, banks: [0: bank])
            let plainAgain = try rendered(eq: false)
            #expect(firstBitDifference(plainAgain, plain) == nil, "\(name): the engine renders the same twice")
            // the songs' frames at the output's rate, less a block: the output stops on its own clock after the end
            let compared = 0..<(frames - 4_096)
            let difference = firstBitDifference(unit, core, in: compared)
            let peak = unit[0][compared].reduce(Float(0)) { max($0, abs($1)) }
            print("EQ join, \(name): \(compared.count) frames compared, the unit against Core's render: "
                  + "\(difference ?? "the same, bit for bit"); its largest sample \(peak)")
            #expect(difference == nil, "\(name): \(difference ?? "")")
            #expect(firstBitDifference(unit, plain, in: compared) != nil, "\(name): the curve did something")
        }
    }

    /// Test 6: the response through the unit at every rate the phone may play, 44.1 to 384 kHz - an impulse rendered
    /// until the slowest section has decayed below -120 dB, its spectrum against Core's `EQResponse` for the same bank,
    /// within 0.01 dB from 20 Hz to 20 kHz.
    @Test func theResponseAtEveryRate() throws {
        let rates = [44_100.0, 48_000, 88_200, 96_000, 176_400, 192_000, 352_800, 384_000]
        var worstOfAll = 0.0
        for rate in rates {
            let bank = EQBank.make(rate: rate, key: EQTestCurve.key, version: 0, on: true, correction: aCorrection,
                                   offsets: .zero, bands: EQGraphic.preset("bassBoost")!.gains, preamp: nil)
            let sections = (bank.left).map(\.coefficients)
            let decay = sections.map(decaySamples).max() ?? 0
            let length = Int(Double(decay) * 1.5) + 4_096
            let at = 8_192                                   // past any start ramp a node may make
            var impulse = [Float](repeating: 0, count: at + length + 8_192)
            impulse[at] = 0.5
            let engine = try eqEngine(rate: rate)
            engine.eqStart = { host, unitRate, _ in
                host.setOutput(EQTestCurve.key)
                host.publish(EQBank.make(rate: unitRate, key: EQTestCurve.key, version: 0, on: true,
                                         correction: aCorrection, offsets: .zero,
                                         bands: EQGraphic.preset("bassBoost")!.gains, preamp: nil))
            }
            engine.play([memoryTrack([impulse, impulse], rate: rate, key: 0)], from: 0)
            engine.settle()
            let out = try renderChannels(engine, frames: impulse.count)[0]
            guard let start = out.firstIndex(where: { $0 != 0 }) else {
                Issue.record("\(rate) Hz: the impulse never came out")
                continue
            }
            let response = out[start..<min(start + length, out.count)].map { Double($0) / 0.5 }
            var worst = 0.0, worstAt = 0.0
            var f = 20.0
            while f <= 20_000 {
                let measured = 20 * log10(magnitude(response, frequency: f, rate: rate))
                let expected = EQResponse.db(sections, at: f, rate: rate) + 20 * log10(bank.levels[0])
                if abs(measured - expected) > worst {
                    worst = abs(measured - expected)
                    worstAt = f
                }
                f *= pow(2, 1.0 / 12)
            }
            worstOfAll = max(worstOfAll, worst)
            print("EQ response at \(Int(rate)) Hz: \(sections.count) sections, preamp \(bank.preamp) dB, an impulse "
                  + "of \(response.count) samples (the slowest section below -120 dB after \(decay)); the largest "
                  + "difference from EQResponse \(String(format: "%.2e", worst)) dB, at \(Int(worstAt)) Hz")
            #expect(worst < 0.01, "\(Int(rate)) Hz: \(worst) dB at \(worstAt) Hz")
        }
        print("EQ response: the largest difference at any rate \(String(format: "%.2e", worstOfAll)) dB")
    }

    /// Test 6's sweep: a 20 Hz-20 kHz log sweep through the unit at every one of those rates is Core's render of the
    /// same bank over the engine's own render with no unit, bit for bit - so the response the impulse measured is the
    /// response of everything the unit plays.
    @Test func theSweepAtEveryRateIsCoresRender() throws {
        let rates = [44_100.0, 48_000, 88_200, 96_000, 176_400, 192_000, 352_800, 384_000]
        for rate in rates {
            let frames = Int(rate)                                     // 1 s
            let k = log(20_000.0 / 20.0)
            let sweep = (0..<frames).map { (n: Int) -> Float in
                let t = Double(n) / rate
                return Float(0.25 * sin(2 * Double.pi * 20 * 1 / k * (exp(t * k) - 1)))
            }
            func bank(_ unitRate: Double) -> EQBank {
                EQBank.make(rate: unitRate, key: EQTestCurve.key, version: 0, on: true, correction: aCorrection,
                            offsets: .zero, bands: EQGraphic.preset("loudness")!.gains, preamp: nil)
            }
            func rendered(eq: Bool) throws -> [[Float]] {
                let engine = try eqEngine(rate: rate, eq: eq)
                engine.eqStart = { host, unitRate, _ in
                    host.setOutput(EQTestCurve.key)
                    host.publish(bank(unitRate))
                }
                engine.play([memoryTrack([sweep, sweep], rate: rate, key: 0)], from: 0)
                engine.settle()
                return try renderChannels(engine, frames: frames)
            }
            let plain = try rendered(eq: false)
            let unit = try rendered(eq: true)
            let core = coreRender(plain, rate: rate, banks: [0: bank(rate)])
            let difference = firstBitDifference(unit, core, in: 0..<(frames - 4_096))
            print("EQ sweep at \(Int(rate)) Hz: \(frames - 4_096) frames, the unit against Core's render: "
                  + (difference ?? "the same, bit for bit"))
            #expect(difference == nil, "\(Int(rate)) Hz: \(difference ?? "")")
        }
    }

    /// Test 7: a rebuilt engine (media services reset) has a new unit with the curve back in before its first sample
    /// - the start puts it in, states zeroed and with no crossfade, so what plays after the rebuild is Core's render of
    /// it from a fresh start, bit for bit.
    @Test func aRebuiltEngineHasTheCurveFromItsFirstSample() throws {
        let rate = 48_000.0
        let gains = EQGraphic.preset("bassBoost")!.gains
        let song = tone(440, rate: rate, seconds: 3, level: 0.25)
        func rendered(eq: Bool) throws -> (before: [[Float]], after: [[Float]], engine: PlaybackEngine) {
            let engine = try eqEngine(rate: rate, eq: eq)
            engine.eqStart = { host, unitRate, _ in
                host.setOutput(EQTestCurve.key)
                host.publish(toneBank(gains, rate: unitRate, version: 0, preamp: nil))
            }
            engine.play([memoryTrack(song, rate: rate, key: 0)], from: 0)
            engine.settle()
            let before = try renderChannels(engine, frames: 4_096 * 6)
            engine.rebuild()
            engine.settle()
            let after = try renderChannels(engine, frames: 4_096 * 6)
            return (before, after, engine)
        }
        let plain = try rendered(eq: false)
        let unit = try rendered(eq: true)
        let bank = toneBank(gains, rate: rate, version: 0, preamp: nil)
        let status = unit.engine.debug().eq
        print("EQ rebuild: after the reset \(status.map(describe) ?? "none")")
        #expect(firstBitDifference(unit.before, coreRender(plain.before, rate: rate, banks: [0: bank])) == nil)
        let after = coreRender(plain.after, rate: rate, banks: [0: bank])
        #expect(firstBitDifference(unit.after, after) == nil,
                "after the rebuild: \(firstBitDifference(unit.after, after) ?? "")")
        #expect(plain.after[0].contains { $0 != 0 }, "it plays on after the rebuild")
        #expect(status?.mode == .filtering && status?.crossfades == 0 && (status?.allocations ?? 0) >= 2)
    }
}

/// Debug's test curve (check 0) and Debug's rows for the unit (3.13).
@Suite(.serialized) struct EQDebugTests {
    /// "Muffle what plays" through the real engine: an 8 kHz tone comes out about 24 dB quieter and a 200 Hz one as it
    /// went in, the start putting the curve in before the first sample; turned off while it plays, a crossfade back to
    /// passing every sample through. And Debug's rows say so.
    @Test func muffleWhatPlays() throws {
        let rate = 48_000.0
        let high = tone(8_000, rate: rate, seconds: 2, level: 0.25)
        let low = tone(200, rate: rate, seconds: 2, level: 0.25)
        var version = 0
        let curve = EQTestCurve.bank(on: true, rate: rate, version: 0)
        for (name, song, frequency) in [("8 kHz", high, 8_000.0), ("200 Hz", low, 200.0)] {
            let expected = EQResponse.db(curve.left.map(\.coefficients), at: frequency, rate: rate)
                + 20 * log10(curve.levels[0])
            let engine = try eqEngine(rate: rate)
            engine.eqStart = { host, unitRate, _ in
                host.setOutput(EQTestCurve.key)
                host.publish(EQTestCurve.bank(on: true, rate: unitRate, version: version))
            }
            engine.play([memoryTrack(song, rate: rate, key: 0)], from: 0)
            engine.settle()
            let out = try renderChannels(engine, frames: 4_096 * 12) { done in
                guard done == 4_096 * 8, let host = engine.eq else { return }
                version += 1
                host.publish(EQTestCurve.bank(on: false, rate: rate, version: version))
            }[0]
            func rms(_ x: ArraySlice<Float>) -> Double {
                20 * log10((x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot())
            }
            // 24,000 frames: whole periods of both tones, well after the start and before the change
            let window = 8_192..<(8_192 + 24_000)
            let muffled = rms(out[window]) - rms(song[0][window])
            let after = firstBitDifference([Array(out[(4_096 * 9)...])], [Array(song[0][(4_096 * 9)..<(4_096 * 12)])])
            let status = try #require(engine.eq?.status())
            print("EQ Muffle, a \(name) tone: \(String(format: "%.3f", muffled)) dB through the test curve (its response "
                  + "\(String(format: "%.3f", expected)) dB); turned off: "
                  + "\(after ?? "every sample as it went in")\n  "
                  + status.rows.map { "\($0.label): \($0.value)" }.joined(separator: "\n  "))
            #expect(abs(muffled - expected) < 0.01, "\(name): \(muffled) dB, its response \(expected) dB")
            #expect(frequency < 1_000 || expected < -20, "the test curve muffles: \(expected) dB at \(frequency) Hz")
            #expect(after == nil, "\(name), turned off: \(after ?? "")")
            #expect(status.rows.first == EQDebugRow(label: "Unit", value: "In the graph: passing every sample through"))
            // asked as the unit was made, as the engine attached it, and at the start's allocation (macOS's count)
            #expect(status.rows.contains(EQDebugRow(label: "Render block", value: "iOS asked for it 3 times")))
            #expect(status.rows.contains { $0.label == "Started with" && $0.value.hasPrefix("The test curve, put in ") })
            #expect(status.rows.contains(EQDebugRow(label: "Changes", value: "1 crossfade; 0 waited for the one before; 0 made for another rate")))
        }
    }

    /// 1.2's "every play after a pause allocates afresh": a pause stops the output, which frees the unit's render
    /// memory (Debug: stopped); play allocates it again, and the start puts the curve back in before the first sample,
    /// states zeroed - no crossfade, whatever the last bank was.
    @Test func everyStartAllocatesAndPutsTheCurveBackIn() throws {
        let rate = 48_000.0
        let engine = try eqEngine(rate: rate)
        engine.eqStart = { host, unitRate, _ in
            host.setOutput(EQTestCurve.key)
            host.publish(EQTestCurve.bank(on: true, rate: unitRate, version: 0))
        }
        engine.play([memoryTrack(tone(440, rate: rate, seconds: 3, level: 0.25), rate: rate, key: 0)], from: 0)
        engine.settle()
        _ = try renderChannels(engine, frames: 4_096 * 4)
        let playing = try #require(engine.eq?.status())
        engine.pause()
        engine.settle()
        let paused = try #require(engine.eq?.status())
        engine.resume()
        engine.settle()
        _ = try renderChannels(engine, frames: 4_096 * 4)
        let again = try #require(engine.eq?.status())
        print("EQ across a pause: playing \(describe(playing)); paused \(describe(paused)); played again \(describe(again))")
        #expect(playing.mode == .filtering && playing.allocations == 1)
        #expect(paused.mode == .stopped && paused.rows.first?.value == "In the graph: the output is stopped")
        #expect(again.mode == .filtering && again.allocations == 2 && again.crossfades == 0 && again.blocks == 4)
        #expect(again.started?.key == EQTestCurve.key && again.started?.identity == false)
    }

    @Test func debugsRows() {
        var s = EQUnitStatus()
        #expect(s.rows == [EQDebugRow(label: "Unit", value: "In the graph: the output is stopped"),
                           EQDebugRow(label: "Render block", value: "iOS hasn't asked for it, so no sound can go through the EQ"),
                           EQDebugRow(label: "At this rate", value: "The output hasn't started yet")])
        s.mode = .notMade("The operation couldn't be completed.")
        #expect(s.rows == [EQDebugRow(label: "Unit", value: "Not made: The operation couldn't be completed.")])
        s.mode = .waiting
        s.renderBlockAsked = 3
        #expect(s.rows.prefix(2) == [EQDebugRow(label: "Unit", value: "In the graph: waiting for its first block of sound"),
                                     EQDebugRow(label: "Render block", value: "iOS asked for it 3 times")])
        s.mode = .filtering
        s.rate = 48_000
        s.channels = 2
        s.sections = 1
        s.crossfades = 112
        s.waited = 3
        s.blocks = 400
        s.meanSeconds = 0.000_04
        s.worstSeconds = 0.000_19
        s.lastFrames = 1_024
        s.started = EQUnitStatus.Started(key: EQTestCurve.key, identity: false, secondsBefore: 0.000_1)
        #expect(s.rows == [
            EQDebugRow(label: "Unit", value: "In the graph: filtering"),
            EQDebugRow(label: "Render block", value: "iOS asked for it 3 times"),
            EQDebugRow(label: "At this rate", value: "48 kHz: 1 section a channel"),
            EQDebugRow(label: "Changes", value: "112 crossfades; 3 waited for the one before; 0 made for another rate"),
            EQDebugRow(label: "Started with", value: "The test curve, put in 0.1 ms before the output started"),
            EQDebugRow(label: "Over full scale", value: "None since the output started"),
            EQDebugRow(label: "Render", value: "0.04 ms a block on average, 0.19 ms at worst - of 21.3 ms; refused blocks: 0"),
        ])
        s.overs = 14
        s.largest = pow(10, 0.8 / 20)
        s.started = EQUnitStatus.Started(key: EQTestCurve.key, identity: true, secondsBefore: 0.002)
        #expect(s.rows[4] == EQDebugRow(label: "Started with", value: "Off, put in 2.0 ms before the output started"))
        #expect(s.rows[5] == EQDebugRow(label: "Over full scale", value: "14 samples since the output started, the loudest +0.8 dBFS"))
        s.started = EQUnitStatus.Started(key: nil, identity: true, secondsBefore: nil)
        #expect(s.rows[4] == EQDebugRow(label: "Started with", value: "Nothing put in: the output started passing every sample through"))
    }
}

/// The review's: the host's publish rule against a start at a new rate, and the unit left out where it can't go.
@Suite(.serialized) struct EQHostTests {
    /// A change that read the old rate while a start at a new one made its own bank first: the same settings version,
    /// made for the rate the unit no longer runs at. It mustn't push the start's bank out of the ring (the render could
    /// only ignore it, and the settings would play Off until the next change); a newer version always goes in.
    @Test func aBankForTheOldRateDoesNotPushOutTheStartsBank() {
        let host = EQHost()
        host.setOutput(EQTestCurve.key)
        host.allocated(rate: 44_100, channels: 2)
        let start = EQTestCurve.bank(on: true, rate: 44_100, version: 1)
        #expect(host.publish(start))
        #expect(!host.publish(EQTestCurve.bank(on: true, rate: 48_000, version: 1)))
        #expect(host.newest == start)
        #expect(audio_triple_take(host.triple))
        #expect(host.slots[Int(audio_triple_front(host.triple)) * host.packedCount] == 44_100)
        // the same version at the unit's own rate is taken (the start's bank made again), and a newer one at any rate
        #expect(host.publish(EQTestCurve.bank(on: true, rate: 44_100, version: 1)))
        #expect(host.publish(EQTestCurve.bank(on: false, rate: 48_000, version: 2)))
        // before any allocation the host knows no rate, and takes the newest as before
        let fresh = EQHost()
        fresh.setOutput(EQTestCurve.key)
        #expect(fresh.publish(EQTestCurve.bank(on: true, rate: 44_100, version: 1)))
        #expect(fresh.publish(EQTestCurve.bank(on: true, rate: 48_000, version: 1)))
    }

    /// What `matchOutput` relies on when a start failed after `prepare()` left the unit holding its render memory: the
    /// unit refuses a new format then (AUAudioUnit's rule - and AVAudioEngine answers the refusal with an exception
    /// that ends the app, measured), and `stop()` on an engine that prepared but never ran lets the memory go, after
    /// which the new rate connects and starts. (`matchOutput` itself runs only on the phone's engine, never offline.)
    @Test func aPreparedEngineLetsTheUnitGoBeforeANewRate() throws {
        EQUnit.register()
        let at48 = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let at44 = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.realtime, format: at48, maximumFrameCount: 4_096)
        let node = try EQUnit.node()
        engine.attach(node)
        engine.connect(engine.mainMixerNode, to: node, format: at48)
        engine.connect(node, to: engine.outputNode, format: at48)
        engine.prepare()
        #expect(node.auAudioUnit.renderResourcesAllocated && !engine.isRunning)
        #expect(!node.auAudioUnit.shouldChange(to: at44, for: node.auAudioUnit.inputBusses[0]))
        engine.stop()
        #expect(!node.auAudioUnit.renderResourcesAllocated)
        engine.connect(engine.mainMixerNode, to: node, format: at44)
        engine.connect(node, to: engine.outputNode, format: at44)
        try engine.start()
        defer { engine.stop() }
        #expect(node.outputFormat(forBus: 0).sampleRate == 44_100 && node.auAudioUnit.renderResourcesAllocated)
    }

    /// An output of more channels than the unit takes (eight): AVAudioEngine answers a connection the unit refuses with
    /// an exception that ends the app (measured), so the unit is left out - mixer -> output as before it, the music
    /// playing on, and Debug saying why.
    @Test func anOutputOfMoreChannelsThanTheUnitTakesPlaysWithoutIt() throws {
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 10))
        var settings = PlaybackEngine.Settings()
        settings.offline = AVAudioFormat(standardFormatWithSampleRate: 48_000, channelLayout: layout)
        settings.aheadSeconds = 60
        settings.startSeconds = 0
        settings.bufferSeconds = 0.1
        settings.changeSettleSeconds = 0
        let engine = try PlaybackEngine(settings: settings)
        engine.scheduleLag = testScheduleLag
        engine.play([memoryTrack(tone(440, rate: 48_000, seconds: 1, level: 0.25), rate: 48_000, key: 0)], from: 0)
        engine.settle()
        let out = try renderChannels(engine, frames: 4_096 * 4)
        let status = try #require(engine.eq?.status())
        let words = "this output has 10 channels, and the EQ takes at most 8"
        print("EQ on ten channels: \(describe(status)); \(out.count) channels rendered, the first's peak "
              + "\(out.first?.map { abs($0) }.max() ?? 0)")
        #expect(status.mode == .notMade(words))
        #expect(status.rows == [EQDebugRow(label: "Unit", value: "Not made: " + words)])
        #expect(out.count == 10 && out[0].contains { $0 != 0 }, "it plays on without the unit")
    }
}

/// 30 s: seeded noise for the first half, then a 20 Hz-20 kHz log sweep - the left and the right each their own.
func noiseAndSweep(seconds: Double, rate: Double) -> [[Float]] {
    let frames = Int(seconds * rate)
    let half = frames / 2
    var random = SeededRandom(seed: 0x5EED)
    return (0..<2).map { (channel: Int) -> [Float] in
        (0..<frames).map { (n: Int) -> Float in
            if n < half { return Float(random.next() * 0.5) }
            let t = Double(n - half) / rate
            let length = Double(frames - half) / rate
            let k = log(20_000.0 / 20.0)
            let phase = 2 * Double.pi * 20 * length / k * (exp(t / length * k) - 1)
            return Float(0.4 * (channel == 0 ? sin(phase) : cos(phase + 0.7)))
        }
    }
}

/// A small seeded generator (xorshift64*), uniform in [-1, 1).
struct SeededRandom {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let x = state &* 2_685_821_657_736_338_717
        return Double(x >> 11) / Double(1 << 52) - 1
    }
}

/// How many samples a section's impulse takes to fall below -120 dB: its slowest pole's radius.
func decaySamples(_ c: EQCoefficients) -> Int {
    let disc = c.a1 * c.a1 - 4 * c.a2
    let r: Double
    if disc < 0 {
        r = c.a2.squareRoot()
    } else {
        r = max(abs((-c.a1 + disc.squareRoot()) / 2), abs((-c.a1 - disc.squareRoot()) / 2))
    }
    guard r > 0, r < 1 else { return 0 }
    return Int((log(1e-6) / log(r)).rounded(.up))
}

/// |H(f)| of an impulse response, by its sum at that one frequency.
func magnitude(_ h: [Double], frequency: Double, rate: Double) -> Double {
    let w = 2 * Double.pi * frequency / rate
    var re = 0.0, im = 0.0
    for (n, x) in h.enumerated() {
        re += x * cos(w * Double(n))
        im -= x * sin(w * Double(n))
    }
    return (re * re + im * im).squareRoot()
}

func describe(_ s: EQUnitStatus) -> String {
    "\(s.mode), \(s.rate.map { "\(Int($0)) Hz" } ?? "no rate"), \(s.blocks) blocks of \(s.lastFrames), "
        + "\(s.crossfades) crossfades, \(s.waited) waited, \(s.otherRate) for another rate, \(s.refused) refused, "
        + "\(s.overs) over (largest \(s.largest)), \(s.allocations) allocations, "
        + "render \(String(format: "%.4f", s.meanSeconds * 1000)) ms mean, \(String(format: "%.4f", s.worstSeconds * 1000)) ms worst"
}
#endif
