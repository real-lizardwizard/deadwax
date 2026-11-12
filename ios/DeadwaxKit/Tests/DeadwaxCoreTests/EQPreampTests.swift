import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 1.4 and 3.6: the automatic preamp - never a boost, rounded toward quieter, DC and Nyquist counted, a sum's
/// top found where no filter is (Fixtures/eq/preamp.json's close pairs, against a 4-million-point search), one for
/// both ears - and the presets' table.
@Suite struct EQPreampTests {
    @Test func itNeverBoosts() {
        #expect(EQPreamp.automatic(top: 0) == 0)
        #expect(EQPreamp.automatic(top: -3) == 0)
        #expect(EQPreamp.automatic(top: 1e-12) == 0)
        //? a curve that only cuts: Bass Reduce's top is 0 dB, so no preamp
        let reduce = EQGraphic.sections(gains: EQGraphic.preset("bassReduce")!.gains, rate: 48000)
        #expect(EQPreamp.automatic([EQResponse.Ear(sections: reduce)], rate: 48000) == 0)
    }

    @Test func itIsRoundedToATenthTowardQuieter() {
        #expect(EQPreamp.automatic(top: 6.32) == -6.4)
        #expect(EQPreamp.automatic(top: 6.31) == -6.4)
        #expect(EQPreamp.automatic(top: 6.3) == -6.3)
        #expect(EQPreamp.automatic(top: 0.01) == -0.1)
        //? within 1e-9 dB of a tenth counts as on it (oratory1990's HD 650 tops out at 6.400000000025 dB)
        #expect(EQPreamp.automatic(top: 6.400000000024982) == -6.4)
        #expect(EQPreamp.automatic(top: 6.4000001) == -6.5)
        #expect(EQPreamp.automatic(top: 5.998014703301653) == -6.0)
    }

    @Test func DCAndNyquistAreCounted() {
        //? a low shelf's top is at DC, a high shelf's at Nyquist: on no grid point and no f0
        let low = EQFilter(kind: .lowShelf, fc: 105, gain: 6, width: .q(0.7)).design(rate: 48000)
        let lowTop = EQResponse.top([EQResponse.Ear(sections: [EQSection(id: .filter(1), kind: .lowShelf, f0: low.f0!, coefficients: low.coefficients!)])], rate: 48000)
        #expect(lowTop.at == 0)
        #expect(abs(lowTop.db - 6) <= 1e-9)
        let high = EQFilter(kind: .highShelf, fc: 10000, gain: 6, width: .q(0.7)).design(rate: 44100)
        let highTop = EQResponse.top([EQResponse.Ear(sections: [EQSection(id: .filter(1), kind: .highShelf, f0: high.f0!, coefficients: high.coefficients!)])], rate: 44100)
        #expect(highTop.at == 22050)
        #expect(abs(highTop.db - 6) <= 1e-9)
    }

    @Test func aSumsTopIsFoundWhereNoFilterIs() throws {
        let pairs = try EQFixtures.preamp().closePairs
        #expect(pairs.count == 3)
        for pair in pairs {
            let rate = EQFixtures.d(pair.rate)
            let sections: [EQSection] = pair.filters.map(\.filter).map { (f: EQFilter) -> EQSection in
                let d = f.design(rate: rate)
                return EQSection(id: .filter(f.id), kind: f.kind, f0: d.f0!, coefficients: d.coefficients!)
            }
            let ears = [EQResponse.Ear(sections: sections)]
            let truth = EQFixtures.d(pair.trueTop)
            let refined = EQResponse.top(ears, rate: rate).db
            let gridOnly = EQResponse.top(ears, rate: rate, refined: false).db
            print("\(pair.name): true top \(truth), the grid and f0s \(gridOnly) (short \(truth - gridOnly)), refined \(refined) (off \(abs(refined - truth)))")
            #expect(abs(refined - truth) <= 1e-5, "\(pair.name): refined")
            #expect(abs(gridOnly - EQFixtures.d(pair.gridTop)) <= 1e-9, "\(pair.name): the grid's")
            //? the grid alone falls short enough to round the preamp a tenth short
            #expect(truth - gridOnly > 0.02, "\(pair.name)")
        }
    }

    @Test func oneForBothEars() {
        func peak(_ gain: Double, _ fc: Double) -> EQSection {
            let d = EQFilter(kind: .peak, fc: fc, gain: gain, width: .q(1)).design(rate: 48000)
            return EQSection(id: .filter(1), kind: .peak, f0: fc, coefficients: d.coefficients!)
        }
        let left = EQResponse.Ear(sections: [peak(6, 1000)])
        let right = EQResponse.Ear(sections: [peak(3, 2000)])
        #expect(EQPreamp.automatic([left, right], rate: 48000) == -6.0)
        #expect(EQPreamp.automatic([right, left], rate: 48000) == -6.0)
        //? an ear's own offset is part of its curve
        let quieter = EQResponse.Ear(sections: [peak(6, 1000)], offset: -4)
        #expect(EQPreamp.automatic([quieter, right], rate: 48000) == -3.0)
    }

    @Test func aFilesPreampsAreASharedPartAndEachEarsOwn() {
        //? the larger ear's part moves into the shared one: an ear's offset is never a boost over the other
        let parts = EQPreampParts.normalised(all: -5, left: -2, right: -0.5)
        #expect(parts == EQPreampParts(all: -5.5, left: -1.5, right: 0))
        #expect(parts.perEar)
        #expect(EQPreampParts.normalised(all: -6, left: 0, right: 0) == EQPreampParts(all: -6, left: 0, right: 0))
        #expect(!EQPreampParts.normalised(all: -6, left: 0, right: 0).perEar)
        //? parts already in this form don't move - what lets an export read back to them
        #expect(EQPreampParts.normalised(all: parts.all, left: parts.left, right: parts.right) == parts)
        #expect(parts.offset(.left) == -1.5 && parts.offset(.right) == 0 && parts.offset(.all) == 0)
        #expect(EQPreamp.linear(-6.1) == pow(10.0, -6.1 / 20))
    }

    @Test func thePresetsTable() throws {
        let rows = try EQFixtures.preamp().presets
        #expect(rows.map(\.id) == EQGraphic.presets.map(\.id))
        #expect(EQFixtures.d(try EQFixtures.preamp().bandQ) == EQGraphic.q)
        //? 3.6's table, as measured
        let expected: [String: Double] = ["flat": 0, "bassBoost": -6.1, "bassReduce": 0, "trebleBoost": -4.8, "trebleReduce": 0,
                                          "vocal": -3.3, "loudness": -5.9, "smallSpeakers": -3.1, "spokenWord": -3.7]
        for row in rows {
            let preset = EQGraphic.preset(row.id)!
            #expect(preset.gains == row.gains.map(EQFixtures.d), "\(row.id): gains")
            for (rate, at) in [(48000.0, row.rate48000), (44100.0, row.rate44100)] {
                let top = EQResponse.top([EQResponse.Ear(sections: EQGraphic.sections(gains: preset.gains, rate: rate))], rate: rate)
                #expect(abs(top.db - EQFixtures.d(at.top)) <= 1e-9, "\(row.id) at \(rate): top \(top.db)")
                #expect(EQPreamp.automatic(top: top.db) == EQFixtures.d(at.preamp), "\(row.id) at \(rate): preamp")
            }
            #expect(EQFixtures.d(row.rate48000.preamp) == expected[row.id], "\(row.id): 3.6's table")
        }
    }

    @Test func theBandsAreExactOctaves() {
        #expect(EQGraphic.bands == [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
        #expect(EQGraphic.q == 1.41)
        #expect(EQGraphic.names == ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"])
        //? a band at 0 dB is left out; one at 16 kHz is above what 32 kHz plays
        #expect(EQGraphic.sections(gains: EQGraphic.flat, rate: 48000).isEmpty)
        let all = [Double](repeating: 3, count: 10)
        #expect(EQGraphic.sections(gains: all, rate: 48000).map(\.id) == (0..<10).map { .band($0) })
        #expect(EQGraphic.sections(gains: all, rate: 32000).count == 9)
        #expect(EQGraphic.snapped(3.26) == 3.5 && EQGraphic.snapped(-13) == -12 && EQGraphic.snapped(0.2) == 0)
    }
}
