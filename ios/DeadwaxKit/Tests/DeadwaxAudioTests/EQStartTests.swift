#if canImport(AVFAudio)
import AVFAudio
import DeadwaxCore
import Foundation
import Testing
@testable import DeadwaxAudio

// Slice 3 (eq.md 5.3), slice 2's review's two items, against the real EQHost and engine: Core's EQStartDesk, which the
// app's start hook and its changes go through. Item 1, a start that only looks its bank up - measured here, before and
// after; item 2, the bank for the unit's rate landing in every order of a change and a start (Core's
// EQStartBookTests runs the same orders against a model of the host's rules; this is the host itself).

@Suite(.serialized) struct EQStartTests {
    static let key = "speaker"
    static let speaker = EQOutputs.speaker

    static func desk() -> EQStartDesk {
        EQStartDesk(muffleKey: EQTestCurve.key, muffleBank: { (rate: Double, version: Int) -> EQBank in
            EQTestCurve.bank(on: true, rate: rate, version: version)
        }, clock: { PlaybackEngine.hostSeconds() })
    }

    static func taker(_ host: EQHost) -> EQTaker {
        EQTaker(setOutput: { host.setOutput($0) }, publish: { host.publish($0) }, rate: { host.rate })
    }

    static func settings(_ tone: EQTone, correction: [EQFilter] = []) -> EQSettings {
        var s = EQSettings()
        s.met(speaker, at: "")
        s.choose(tone, for: speaker)
        if !correction.isEmpty, let i = s.outputs.firstIndex(where: { $0.key == key }) {
            s.outputs[i].correction = EQCorrection(kind: .built, name: "test", nextFilterID: correction.count + 1,
                                                   filters: correction)
        }
        return s
    }

    /// AutoEq's shape: a low shelf, eight peaks, a high shelf - slice 4's usual correction.
    static let tenFilters: [EQFilter] = [EQFilter(id: 1, kind: .lowShelf, fc: 105, gain: 6.2, width: .q(0.7))]
        + [(24.0, -1.2, 0.5), (190, -2.4, 0.9), (1_400, 2.1, 1.6), (2_800, -3.1, 2.5), (4_100, 4.4, 3.2),
           (6_200, -2.9, 4.1), (7_900, 2.2, 2.2), (9_800, -4.4, 3)].enumerated().map {
            EQFilter(id: $0.offset + 2, kind: .peak, fc: $0.element.0, gain: $0.element.1, width: .q($0.element.2))
        }
        + [EQFilter(id: 10, kind: .highShelf, fc: 10_000, gain: -1.8, width: .q(0.7))]

    /// The race, on the real host: a change on the main thread and a start at a new rate, every order of their steps.
    @Test func theRightBankLandsOnTheRealHost() {
        let before = Self.settings(.preset("bassBoost"))
        let after = Self.settings(.preset("trebleBoost"))
        let wanted = after.bank(after.output(Self.key)!, rate: 48_000, version: 0)
        func orders(_ m: Int, _ s: Int) -> [[Bool]] {
            if m == 0 { return [Array(repeating: false, count: s)] }
            if s == 0 { return [Array(repeating: true, count: m)] }
            return orders(m - 1, s).map { [true] + $0 } + orders(m, s - 1).map { [false] + $0 }
        }
        var checked = 0
        for order in orders(3, 3) {
            let desk = Self.desk()
            let host = EQHost()
            _ = desk.take(before, muffle: false)
            host.allocated(rate: 44_100, channels: 2)
            desk.start(Self.key, rate: 44_100, host: Self.taker(host))
            var ticket: EQTicket?
            var read: Double?
            var plan: EQStartPlan?
            var m = 0, s = 0
            for isMain in order {
                if isMain {
                    switch m {
                    case 0: ticket = desk.take(after, muffle: false)
                    case 1: read = host.rate
                    default:
                        let (output, bank) = desk.bank(Self.key, rate: read!, ticket: ticket!)
                        host.setOutput(output)
                        host.publish(bank)
                    }
                    m += 1
                } else {
                    switch s {
                    case 0: host.allocated(rate: 48_000, channels: 2)
                    case 1: plan = desk.plan(Self.key, rate: 48_000)
                    default:
                        let (output, bank, _) = desk.bank(plan!, rate: 48_000)
                        host.setOutput(output)
                        host.publish(bank)
                    }
                    s += 1
                }
            }
            var landed = host.newest
            landed?.version = 0
            #expect(landed == wanted, "\(order)")
            checked += 1
        }
        #expect(checked == 20)
    }

    /// Item 1, measured: what a start spends putting its curve in - slice 2's hook (the test curve made at the start),
    /// the output's bank made at the start (what slice 3 would do without making ahead), and looked up (made ahead) -
    /// for the tone alone and for slice 4's usual correction with it. Each the median and the worst of 200 starts, on
    /// the real host. In a debug build, so the phone's release build is quicker still.
    @Test func theStartsTime() {
        func measure(_ label: String, _ body: (Int) -> Void) -> (median: Double, worst: Double) {
            var times: [Double] = []
            for i in 0..<200 {
                let t = PlaybackEngine.hostSeconds()
                body(i)
                times.append((PlaybackEngine.hostSeconds() - t) * 1_000)
            }
            times.sort()
            let result = (times[100], times[199])
            print(String(format: "EQ start, %@: median %.3f ms, worst %.3f ms", label, result.0, result.1))
            return result
        }
        let host = EQHost()
        host.allocated(rate: 48_000, channels: 2)
        var version = 0
        let slice2 = measure("slice 2's hook (the test curve made at the start)") { _ in
            version += 1
            host.setOutput(EQTestCurve.key)
            host.publish(EQTestCurve.bank(on: true, rate: 48_000, version: version))
        }
        var results: [String: (median: Double, worst: Double)] = ["slice 2": slice2]
        for (name, s) in [("Bass Boost", Self.settings(.preset("bassBoost"))),
                          ("ten bands", Self.settings(.custom([4, 3, 2, 1, -1, -2, 1, 2, 3, 4]))),
                          ("ten bands + 10 filters", Self.settings(.custom([4, 3, 2, 1, -1, -2, 1, 2, 3, 4]),
                                                                   correction: Self.tenFilters))] {
            // made at the start: desks that have the settings and have made nothing ahead, one a start
            let fresh = (0..<200).map { (_: Int) -> EQStartDesk in
                let desk = Self.desk()
                _ = desk.take(s, muffle: false)
                return desk
            }
            results[name + ", made"] = measure(name + ", made at the start") { i in
                fresh[i].start(Self.key, rate: 48_000, host: Self.taker(host))
            }
            // made ahead: the start looks it up
            let desk = Self.desk()
            _ = desk.take(s, muffle: false)
            desk.makeAhead([Self.key])
            results[name + ", ahead"] = measure(name + ", made ahead") { _ in
                desk.start(Self.key, rate: 48_000, host: Self.taker(host))
            }
            #expect(desk.lastStart?.ready == true)
            #expect(host.newest.map { b in var c = b; c.version = 0; return c }
                    == s.bank(s.output(Self.key)!, rate: 48_000, version: 0))
        }
        // made ahead, a start costs no more than slice 2's own, and far less than making the bank there
        for name in ["Bass Boost", "ten bands", "ten bands + 10 filters"] {
            #expect(results[name + ", ahead"]!.median < results[name + ", made"]!.median, "\(name)")
            #expect(results[name + ", ahead"]!.median <= max(slice2.median, 0.05), "\(name)")
        }
    }

    /// Through the engine's own start (`eqStart`, between prepare and start): the curve made ahead is what the first
    /// block plays, and Debug's Start took says it was looked up.
    @Test func theEnginesStartUsesTheBankMadeAhead() throws {
        let rate = 48_000.0
        let s = Self.settings(.preset("bassBoost"))
        let desk = Self.desk()
        _ = desk.take(s, muffle: false)
        desk.makeAhead([Self.key])
        let engine = try eqEngine(rate: rate)
        engine.eqStart = { (host: EQHost, unitRate: Double, _: Int) -> Void in
            desk.start(Self.key, rate: unitRate, host: Self.taker(host))
        }
        engine.play([memoryTrack(tone(440, rate: rate, seconds: 2, level: 0.25), rate: rate, key: 0)], from: 0)
        engine.settle()
        _ = try renderChannels(engine, frames: 4_096 * 2)
        let status = try #require(engine.eq?.status())
        let took = try #require(desk.lastStart)
        print("EQ start through the engine: \(took.words); \(describe(status))")
        #expect(took.ready && took.rate == rate)
        #expect(status.mode == .filtering && status.started?.key == Self.key && status.started?.identity == false)
        var newest = try #require(engine.eq?.newest)
        newest.version = 0
        #expect(newest == s.bank(s.output(Self.key)!, rate: rate, version: 0))
    }
}
#endif
