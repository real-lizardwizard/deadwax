#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// 1.7 test 3 (notes/ios-specs/eq.md): no clicks. A tone at -6 dBFS through each change the app makes while playing -
// a band from 0 to +12 dB and back, and to -12 dB and back; a preset put in and swapped for another; On to Off and
// back; another output's curve put in - rendered through the real engine with the unit in its graph. The click is the
// largest sample after an 8th-order Butterworth high-pass far above the tone, in the 200 ms after the change; its
// floor the same measure in the 200 ms before. The same changes made in one step (Core's render, the crossfade one
// frame long, over the same engine's render with no unit) must fail the same thresholds, so the measure is shown
// able to hear a click; and the unit's own output is Core's render with its 20 ms crossfade, bit for bit.

@Suite(.serialized) struct EQClickTests {
    struct Case {
        let name: String
        let frequency: Double
        /// the measure's high-pass
        let cutoff: Double
        /// the largest click allowed, dBFS
        let limit: Double
        let band: Int
        let presets: (String, String)
        /// 1.6's measurement heard this change's click in one step: the control must hear it here too
        let oneStepHeard: Bool
    }

    struct Change {
        let name: String
        let bank: EQBank
        /// another output's curve: the output now changes first
        let output: String?
    }

    @Test func noClicksAndTheLowBandsSettle() throws {
        let rate = 48_000.0
        let block = 4_096
        let cases = [
            Case(name: "a 1 kHz tone, the 1 kHz band", frequency: 1_000, cutoff: 8_000, limit: -110, band: 5,
                 presets: ("vocal", "trebleBoost"), oneStepHeard: true),
            Case(name: "a 100 Hz tone, the 125 Hz band", frequency: 100, cutoff: 2_000, limit: -95, band: 2,
                 presets: ("bassBoost", "bassReduce"), oneStepHeard: true),
            Case(name: "a 40 Hz tone, the 63 Hz band", frequency: 40, cutoff: 2_000, limit: -95, band: 1,
                 presets: ("bassBoost", "bassReduce"), oneStepHeard: false),
            Case(name: "a 40 Hz tone, the 31 Hz band", frequency: 40, cutoff: 2_000, limit: -95, band: 0,
                 presets: ("bassBoost", "bassReduce"), oneStepHeard: false),
        ]
        for test in cases {
            let first = EQGraphic.preset(test.presets.0)!.gains, second = EQGraphic.preset(test.presets.1)!.gains
            let changes = [
                Change(name: "band 0 -> +12 dB", bank: toneBank(band(test.band, 12), rate: rate, version: 1), output: nil),
                Change(name: "band +12 -> 0 dB", bank: toneBank(EQGraphic.flat, rate: rate, version: 2), output: nil),
                Change(name: "band 0 -> -12 dB", bank: toneBank(band(test.band, -12), rate: rate, version: 3), output: nil),
                Change(name: "band -12 -> 0 dB", bank: toneBank(EQGraphic.flat, rate: rate, version: 4), output: nil),
                Change(name: "preset \(test.presets.0) put in", bank: toneBank(first, rate: rate, version: 5, preamp: nil),
                       output: nil),
                Change(name: "-> preset \(test.presets.1)", bank: toneBank(second, rate: rate, version: 6, preamp: nil),
                       output: nil),
                Change(name: "On -> Off", bank: EQBank.make(rate: rate, key: EQTestCurve.key, version: 7, on: false,
                                                            correction: [], offsets: .zero, bands: second, preamp: nil),
                       output: nil),
                Change(name: "Off -> On", bank: toneBank(second, rate: rate, version: 8, preamp: nil), output: nil),
                Change(name: "another output's curve", bank: EQBank.make(
                    rate: rate, key: "other", version: 9, on: true, correction: aCorrection, offsets: .zero,
                    bands: second, preamp: nil), output: "other"),
            ]
            // a change every 6 blocks (0.51 s) from the 12th (1.02 s): each at a block's start, as the unit takes them
            let at = changes.indices.map { (12 + 6 * $0) * block }
            let frames = at.last! + 6 * block
            let song = tone(test.frequency, rate: rate, seconds: Double(frames) / rate + 0.5, level: 0.5)
            let start = toneBank(EQGraphic.flat, rate: rate, version: 0)

            func rendered(eq: Bool) throws -> [[Float]] {
                let engine = try eqEngine(rate: rate, eq: eq)
                engine.eqStart = { host, _, _ in
                    host.setOutput(EQTestCurve.key)
                    host.publish(start)
                }
                engine.play([memoryTrack(song, rate: rate, key: 0)], from: 0)
                engine.settle()
                return try renderChannels(engine, frames: frames) { done in
                    guard let host = engine.eq, let index = at.firstIndex(of: done) else { return }
                    let change = changes[index]
                    if let output = change.output { host.setOutput(output) }
                    #expect(host.publish(change.bank), "\(change.name) was published")
                }
            }
            let plain = try rendered(eq: false)
            let unit = try rendered(eq: true)
            var banks: [Int: EQBank] = [0: start]
            for (index, change) in changes.enumerated() { banks[at[index]] = change.bank }
            let crossfaded = coreRender(plain, rate: rate, banks: banks)
            let oneStep = coreRender(plain, rate: rate, banks: banks, fadeFrames: 1)
            #expect(firstBitDifference(unit, crossfaded) == nil,
                    "\(test.name): the unit against Core's render: \(firstBitDifference(unit, crossfaded) ?? "")")

            let window = Int(0.200 * rate)
            let heard = butterworthHighPass(unit[0], cutoff: test.cutoff, rate: rate)
            let control = butterworthHighPass(oneStep[0], cutoff: test.cutoff, rate: rate)
            var lines: [String] = []
            for (index, change) in changes.enumerated() {
                let n = at[index]
                let click = peakDBFS(heard, n..<(n + window))
                let floor = peakDBFS(heard, (n - window)..<n)
                let stepped = peakDBFS(control, n..<(n + window))
                lines.append("  \(change.name): \(String(format: "%.1f", click)) dBFS (floor before "
                             + "\(String(format: "%.1f", floor))); in one step \(String(format: "%.1f", stepped))")
                #expect(click < test.limit, "\(test.name), \(change.name): a click at \(click) dBFS")
                #expect(floor < test.limit - 15, "\(test.name), before \(change.name): the floor is \(floor) dBFS")
                if test.oneStepHeard && index == 0 {
                    #expect(stepped > test.limit, "\(test.name): the one-step control heard nothing (\(stepped) dBFS)")
                }
            }
            print("EQ clicks, \(test.name), above \(Int(test.cutoff)) Hz (limit \(Int(test.limit)) dBFS):\n"
                  + lines.joined(separator: "\n"))

            if test.band == 0 {
                // the settle: the 31 Hz band's own time constant on a 40 Hz tone, the first four changes
                let period = Int(rate / test.frequency)                    // 1,200 frames: exact
                func level(_ from: Int) -> Double {
                    let x = unit[0][from..<(from + period)]
                    let mean = x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(period)
                    return 20 * log10((2 * mean).squareRoot())
                }
                for index in 0..<4 {
                    let n = at[index]
                    let before = level(n - period)
                    let steady = level(n + 18 * period)                      // 450-475 ms after
                    let envelope = (0..<18).map { level(n + $0 * period) }
                    let outside = envelope.lastIndex { abs($0 - steady) > 0.5 }
                    let settled = Double((outside ?? -1) + 1) * Double(period) / rate * 1_000
                    let overshoot = (envelope.max() ?? steady) - max(before, steady)
                    print("EQ settle, the 31 Hz band, \(changes[index].name): \(String(format: "%.1f", before)) -> "
                          + "\(String(format: "%.1f", steady)) dB; within 0.5 dB after \(Int(settled)) ms, "
                          + "overshoot \(String(format: "%.2f", overshoot)) dB; each 25 ms: "
                          + envelope.map { String(format: "%.2f", $0) }.joined(separator: " "))
                    #expect(settled <= 80, "\(changes[index].name): settled after \(settled) ms")
                    #expect(overshoot <= 1.5, "\(changes[index].name): overshot by \(overshoot) dB")
                }
            }
        }
    }
}
#endif
