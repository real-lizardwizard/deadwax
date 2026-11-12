import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 1.3: every filter APO plays, at eight rates, held to the cookbook and APO's rules written out again in
/// Python (Fixtures/eq/filters.json): the coefficients within 1e-13 (they are of order 1, and a relative bound means
/// nothing for one near zero, as a band pass's b1), the response within 0.001 dB of scipy's freqz.
@Suite struct EQFilterTests {
    @Test func everyFixtureFilterIsMadeAsThePythonMakesIt() throws {
        let file = try EQFixtures.filters()
        #expect(file.rates.map(EQFixtures.d) == [44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000])
        #expect(file.cases.count > 150)
        var worstCoefficient = 0.0
        var worstResponse = 0.0
        for each in file.cases {
            let rate = EQFixtures.d(each.rate)
            let design = each.filter.filter.design(rate: rate)
            let name = "\(each.name) at \(rate)"
            #expect(design.outcome.rawValue == each.outcome, "\(name): outcome")
            if let f0 = each.f0.map(EQFixtures.d) {
                #expect(abs((design.f0 ?? .nan) - f0) <= 1e-14 * f0, "\(name): f0 \(String(describing: design.f0)) against \(f0)")
            } else {
                #expect(design.f0 == nil, "\(name): no f0")
            }
            guard let expected = each.coefficientsValue else {
                #expect(design.coefficients == nil, "\(name): no section")
                continue
            }
            guard let mine = design.coefficients else {
                Issue.record("\(name): no section made")
                continue
            }
            for (a, b) in zip([mine.b0, mine.b1, mine.b2, mine.a1, mine.a2],
                              [expected.b0, expected.b1, expected.b2, expected.a1, expected.a2]) {
                worstCoefficient = max(worstCoefficient, abs(a - b))
                #expect(abs(a - b) <= 1e-13, "\(name): coefficient \(a) against \(b)")
            }
            let grid = EQResponse.grid(rate: rate)
            let reference = EQFixtures.floats(each.response_f4!)
            #expect(reference.count == grid.count, "\(name): the grid")
            for (f, freqz) in zip(grid, reference) {
                let db = EQResponse.db(mine, at: f, rate: rate)
                if db <= -200 && Double(freqz) <= -200 { continue }
                worstResponse = max(worstResponse, abs(db - Double(freqz)))
                #expect(abs(db - Double(freqz)) <= 0.001, "\(name): \(db) dB at \(f) Hz against freqz's \(freqz)")
            }
        }
        print("EQ filters: coefficients within \(worstCoefficient) of the Python's; response within \(worstResponse) dB of freqz")
    }

    @Test func aPeakOrShelfAtZeroDecibelsIsLeftOutAsFlat() {
        for kind in [EQKind.peak, .lowShelf, .highShelf] {
            for gain in [0.0, -0.0] {
                let design = EQFilter(kind: kind, fc: 1000, gain: gain, width: .q(0.7)).design(rate: 48000)
                #expect(design.outcome == .flat && design.coefficients == nil, "\(kind) at \(gain) dB")
            }
        }
        //? a pass or a notch has no gain to be flat at
        #expect(EQFilter(kind: .lowPass, fc: 1000, width: .q(0.7)).design(rate: 48000).outcome == .plays)
        //? and the smallest gain plays
        #expect(EQFilter(kind: .peak, fc: 1000, gain: 0.0001, width: .q(1)).design(rate: 48000).outcome == .plays)
    }

    @Test func aFilterAtOrAbove049TimesTheRateIsLeftOutAtThatRate() {
        let rate = 44100.0
        let at = EQFilter(kind: .peak, fc: 0.49 * rate, gain: 3, width: .q(1))
        #expect(at.design(rate: rate).outcome == .above)
        #expect(EQFilter(kind: .peak, fc: (0.49 * rate).nextDown, gain: 3, width: .q(1)).design(rate: rate).outcome == .plays)
        //? the same filter plays at a higher rate: it is worked out at each
        #expect(at.design(rate: 48000).outcome == .plays)
        //? a corner shelf is held to the rule at its moved f0, not its Fc
        let corner = EQFilter(kind: .lowShelf, written: "LS", fc: 20000, gain: 12, width: .slope(6), corner: true)
        #expect(corner.f0! > 0.49 * 44100 && corner.design(rate: 44100).outcome == .above)
    }

    @Test func eachDefaultIsAPOs() {
        func played(_ f: EQFilter) -> EQFilter.PlayedWidth? { f.playedWidth }
        let root = (0.5).squareRoot()
        for kind in [EQKind.lowPass, .highPass, .bandPass] {
            #expect(played(EQFilter(kind: kind, fc: 1000)) == .init(value: root, isBandwidthOrS: false, given: false))
            #expect(played(EQFilter(kind: kind, fc: 1000, width: .q(0))) == .init(value: root, isBandwidthOrS: false, given: false))
            //? BW Oct 0 keeps its kind (BiQuadFilterFactory.cpp:150-151, 177-189): 1/√2 octaves
            #expect(played(EQFilter(kind: kind, fc: 1000, width: .bandwidth(0))) == .init(value: root, isBandwidthOrS: true, given: false))
        }
        #expect(played(EQFilter(kind: .notch, fc: 60)) == .init(value: 30, isBandwidthOrS: false, given: false))
        #expect(played(EQFilter(kind: .notch, fc: 60, width: .bandwidth(0))) == .init(value: 30, isBandwidthOrS: true, given: false))
        for kind in [EQKind.lowShelf, .highShelf] {
            for width in [nil, EQWidth.q(0), .slope(0), .bandwidth(2)] {
                #expect(played(EQFilter(kind: kind, fc: 100, gain: 3, width: width)) == .init(value: 0.9, isBandwidthOrS: true, given: false),
                        "\(kind) with \(String(describing: width)): S 0.9 (a BW ignored on a shelf)")
            }
        }
        for kind in [EQKind.peak, .allPass] {
            for width in [nil, EQWidth.q(0), .bandwidth(0), .slope(12)] {
                #expect(played(EQFilter(kind: kind, fc: 1000, gain: 3, width: width)) == nil, "\(kind): no width")
                #expect(EQFilter(kind: kind, fc: 1000, gain: 3, width: width).design(rate: 48000).outcome == .noWidth)
            }
        }
        //? a slope on anything but a shelf is ignored, as APO ignores it: a low pass with one takes its default
        #expect(played(EQFilter(kind: .lowPass, fc: 1000, width: .slope(12))) == .init(value: root, isBandwidthOrS: false, given: false))
        //? a shelf's slope is S = slope / 12 ("Maximum S is 1 for 12 dB")
        #expect(played(EQFilter(kind: .lowShelf, fc: 100, gain: 3, width: .slope(6))) == .init(value: 0.5, isBandwidthOrS: true, given: true))
        #expect(played(EQFilter(kind: .lowShelf, fc: 100, gain: 3, width: .slope(12)))?.value == 1)
        #expect(played(EQFilter(kind: .peak, fc: 100, gain: 3, width: .bandwidth(1))) == .init(value: 1, isBandwidthOrS: true, given: true))
    }

    @Test func aCornerShelfIsMovedToTheCookbooksCentre() {
        //? LS 6dB: S 0.5, f0 = Fc · 10^(|g| / 80 / S)
        let low = EQFilter(kind: .lowShelf, written: "LS", fc: 100, gain: 5, width: .slope(6), corner: true)
        #expect(abs(low.f0! - 100 * pow(10.0, 5.0 / 80 / 0.5)) <= 1e-12)
        #expect(abs(low.f0! - 133.35214321633241) <= 1e-9)
        //? a high one is moved down, by the gain's size whichever way it goes
        let high = EQFilter(kind: .highShelf, written: "HS", fc: 8000, gain: -6, width: .slope(12), corner: true)
        #expect(abs(high.f0! - 8000 / pow(10.0, 6.0 / 80)) <= 1e-9)
        //? from a Q: S = 1 / ((1/Q² − 2) / (A + 1/A) + 1)
        let a = pow(10.0, 5.0 / 40)
        let s = 1 / ((1 / (0.7 * 0.7) - 2) / (a + 1 / a) + 1)
        let byQ = EQFilter(kind: .lowShelf, written: "LS", fc: 100, gain: 5, width: .q(0.7), corner: true)
        #expect(abs(byQ.f0! - 100 * pow(10.0, 5.0 / 80 / s)) <= 1e-12)
        //? and made there with its own Q
        let design = byQ.design(rate: 48000)
        let centred = EQCookbook.coefficients(.lowShelf, gain: 5, f0: byQ.f0!, rate: 48000, value: 0.7, isBandwidthOrS: false)
        #expect(design.coefficients == centred)
        //? a centre shelf, and a corner shelf given no width (S 0.9), are made at Fc
        #expect(EQFilter(kind: .lowShelf, written: "LSC", fc: 100, gain: 5, width: .q(0.7)).f0 == 100)
        #expect(EQFilter(kind: .lowShelf, written: "LS", fc: 100, gain: 5, width: nil, corner: true).f0 == 100)
    }

    @Test func aShelfTooSteepForItsGainMakesNoFilter() {
        let steep = EQFilter(kind: .lowShelf, written: "LSC", fc: 100, gain: 23, width: .slope(24))
        #expect(EQCookbook.shelfRadicand(gain: 23, s: 2) <= 0)
        #expect(steep.design(rate: 48000) == EQDesign(outcome: .tooSteep, f0: nil, coefficients: nil))
        //? only a slope can make one: the same shelf with any Q is made with that Q (a corner shelf of 30 dB and a low
        //? Q moved far enough up to be above the rate, but never too steep)
        for q in [0.01, 0.7, 2, 10, 100] {
            #expect(EQFilter(kind: .lowShelf, written: "LS", fc: 100, gain: 30, width: .q(q), corner: true).design(rate: 48000).outcome != .tooSteep)
            #expect(EQFilter(kind: .lowShelf, written: "LSC", fc: 100, gain: 30, width: .q(q)).design(rate: 48000).outcome == .plays)
        }
        //? the editor's "at most": just under it plays, at it doesn't
        let most = EQCookbook.steepestSlope(gain: 23)!
        #expect(EQFilter(kind: .lowShelf, fc: 100, gain: 23, width: .slope(most.nextDown)).design(rate: 48000).outcome == .plays)
        #expect(EQFilter(kind: .lowShelf, fc: 100, gain: 23, width: .slope(most * 1.0001)).design(rate: 48000).outcome == .tooSteep)
        #expect(EQCookbook.steepestSlope(gain: 0) == nil)
    }

    @Test func anOffFilterPlaysNothing() {
        #expect(EQFilter(kind: .peak, fc: 1000, gain: 6, width: .q(1), on: false).design(rate: 48000).outcome == .off)
    }

    @Test func aFilterIsKeptAsFourWritesIt() throws {
        let filter = EQFilter(id: 3, kind: .lowShelf, written: "LS", fc: 105, gain: 2.6, width: .slope(6), corner: true,
                              channel: .left, on: false)
        let data = try JSONEncoder().encode(filter)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect((object["width"] as? [String: Double]) == ["slope": 6])
        #expect(try JSONDecoder().decode(EQFilter.self, from: data) == filter)
        //? no width is written as null, and read back as none
        let none = EQFilter(id: 1, kind: .lowShelf, fc: 90, gain: 3)
        let noneData = try JSONEncoder().encode(none)
        #expect(String(decoding: noneData, as: UTF8.self).contains("\"width\":null"))
        #expect(try JSONDecoder().decode(EQFilter.self, from: noneData) == none)
    }
}
