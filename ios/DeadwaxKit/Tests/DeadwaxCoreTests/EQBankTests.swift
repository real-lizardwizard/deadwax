import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 1.6 and 5.1: a bank is the identity exactly when it should be; each channel's list; the curve made again at
/// each rate; 1.6's version-and-key rule; `.band` and `.filter` ids never matching; the packed layout the render reads.
@Suite struct EQBankTests {
    static let correction = [
        EQFilter(id: 1, kind: .lowShelf, written: "LSC", fc: 105, gain: 2.6, width: .q(0.7)),
        EQFilter(id: 2, kind: .peak, fc: 514, gain: -4.4, width: .q(0.68), channel: .left),
        EQFilter(id: 3, kind: .peak, fc: 3000, gain: 3, width: .q(1), channel: .right),
        EQFilter(id: 4, kind: .peak, fc: 8903, gain: 6, width: .q(1.66)),
        EQFilter(id: 5, kind: .peak, fc: 22000, gain: 2, width: .q(1)),
        EQFilter(id: 6, kind: .peak, fc: 200, gain: 5, width: .q(1), on: false),
    ]

    static func make(rate: Double = 48000, on: Bool = true, correction: [EQFilter] = correction,
                     offsets: EQPreampParts = .zero, bands: [Double] = EQGraphic.flat, preamp: Double? = nil) -> EQBank {
        EQBank.make(rate: rate, key: "bluetooth:1", version: 3, on: on, correction: correction, offsets: offsets,
                    bands: bands, preamp: preamp)
    }

    @Test func theIdentityExactlyWhenItShouldBe() {
        #expect(Self.make(on: false).isIdentity)
        #expect(Self.make(on: false) == EQBank.identity(rate: 48000, key: "bluetooth:1", version: 3))
        #expect(Self.make(correction: []).isIdentity)
        #expect(Self.make(correction: [], preamp: 0).isIdentity)
        //? nothing that plays at this rate: off, flat, above 0.49 x the rate
        let silent = [EQFilter(id: 1, kind: .peak, fc: 100, gain: 0, width: .q(1)),
                      EQFilter(id: 2, kind: .peak, fc: 100, gain: 6, width: .q(1), on: false),
                      EQFilter(id: 3, kind: .highShelf, fc: 21700, gain: 6, width: .q(1))]
        #expect(Self.make(rate: 44100, correction: silent).isIdentity)
        #expect(!Self.make(rate: 48000, correction: silent).isIdentity)
        //? a level that isn't exactly 1 is a curve
        #expect(!Self.make(correction: [], preamp: -1).isIdentity)
        #expect(!Self.make(correction: [], offsets: EQPreampParts(all: 0, left: 0, right: -2)).isIdentity)
        #expect(!Self.make(correction: [], bands: EQGraphic.preset("bassBoost")!.gains).isIdentity)
        #expect(!Self.make().isIdentity)
    }

    @Test func eachChannelsList() {
        let bank = Self.make(offsets: EQPreampParts(all: -6, left: 0, right: -1.5), bands: EQGraphic.preset("vocal")!.gains)
        let tone: [EQSectionID] = EQGraphic.preset("vocal")!.gains.enumerated().filter { $0.element != 0 }.map { .band($0.offset) }
        //? the correction's own order, the ear's filters among the shared ones; the 22 kHz peak plays at 48 kHz
        #expect(bank.left.map(\.id) == [.filter(1), .filter(2), .filter(4), .filter(5)] + tone)
        #expect(bank.right.map(\.id) == [.filter(1), .filter(3), .filter(4), .filter(5)] + tone)
        #expect(bank.shared.map(\.id) == [.filter(1), .filter(4), .filter(5)] + tone)
        //? the automatic preamp over both ears, each with its offset; the levels the preamp and each ear's offset
        let ears = [EQResponse.Ear(sections: bank.left, offset: 0), EQResponse.Ear(sections: bank.right, offset: -1.5)]
        #expect(bank.preamp == EQPreamp.automatic(ears, rate: 48000) && bank.preamp < 0)
        let shared = min(bank.preamp, EQPreamp.automatic([EQResponse.Ear(sections: bank.shared)], rate: 48000))
        #expect(bank.levels == [bank.preamp, bank.preamp - 1.5, shared].map(EQPreamp.linear))
        //? set by hand, the preamp is yours
        let hand = Self.make(offsets: EQPreampParts(all: -6, left: -2, right: 0), preamp: -7.5)
        #expect(hand.preamp == -7.5 && hand.levels == [-9.5, -7.5, -7.5].map(EQPreamp.linear))
        #expect(bank.key == "bluetooth:1" && bank.version == 3 && bank.rate == 48000)
    }

    /// Channels 2 and up play the shared list at the preamp; automatic, its own top is counted for it when the ears'
    /// curves aren't it (1.4): no channel over 0 dB, and the ears not lowered for it.
    @Test func noChannelGoesOverFullScale() {
        //? both ears cut what the shared filter boosts: the ears are flat, the shared list 6 dB up at 1 kHz
        let cancelled = [EQFilter(id: 1, kind: .peak, fc: 1000, gain: 6, width: .q(1)),
                         EQFilter(id: 2, kind: .peak, fc: 1000, gain: -6, width: .q(1), channel: .left),
                         EQFilter(id: 3, kind: .peak, fc: 1000, gain: -6, width: .q(1), channel: .right)]
        func topOver(_ sections: [EQSection], _ level: Double) -> Double {
            EQResponse.top([EQResponse.Ear(sections: sections, offset: 20 * log10(level))], rate: 48000).db
        }
        let bank = Self.make(correction: cancelled)
        #expect(bank.preamp == 0 && bank.levels[0] == 1 && bank.levels[1] == 1)
        #expect(bank.levels[2] == EQPreamp.linear(-6))
        #expect(topOver(bank.shared, bank.levels[2]) <= 1e-9)
        //? both ears' offsets below 0 (a settings file's parts, not normalised): the ears' tops are 3 dB under the
        //  shared list's
        let quieter = Self.make(correction: [cancelled[0]], offsets: EQPreampParts(all: 0, left: -3, right: -3))
        #expect(quieter.preamp == -3 && quieter.levels[0] == EQPreamp.linear(-6) && quieter.levels[2] == EQPreamp.linear(-6))
        #expect(topOver(quieter.shared, quieter.levels[2]) <= 1e-9)
        //? no per-ear filters and an ear at offset 0: the shared list is that ear's, at its level - nothing more asked
        let plain = Self.make(correction: [cancelled[0]], offsets: EQPreampParts(all: 0, left: 0, right: -2))
        #expect(plain.levels[2] == plain.levels[0] && plain.preamp == -6)
        //? set by hand, the preamp is yours on every channel
        let hand = Self.make(correction: cancelled, preamp: 0)
        #expect(hand.levels == [1, 1, 1])
        //? the shared list never louder than the preamp, even where its curve only cuts
        let cuts = Self.make(correction: [EQFilter(id: 1, kind: .peak, fc: 1000, gain: -6, width: .q(1)),
                                          EQFilter(id: 2, kind: .peak, fc: 3000, gain: 4, width: .q(1), channel: .left)])
        #expect(cuts.levels[2] == EQPreamp.linear(cuts.preamp) && cuts.preamp < 0)
    }

    @Test func theCurveIsMadeAgainAtEachRate() {
        let at48 = Self.make(rate: 48000)
        let at44 = Self.make(rate: 44100)
        #expect(at48.left.map(\.id).contains(.filter(5)) && !at44.left.map(\.id).contains(.filter(5)))
        for (a, b) in zip(at44.left, at48.left.filter { $0.id != .filter(5) }) {
            #expect(a.id == b.id && !a.coefficients.sameBits(b.coefficients))
            let filter = Self.correction.first { .filter($0.id) == a.id }!
            #expect(a.coefficients.sameBits(filter.design(rate: 44100).coefficients!))
        }
        //? the 16 kHz band is above what 32 kHz plays
        let bands = [Double](repeating: 3, count: 10)
        #expect(Self.make(rate: 32000, correction: [], bands: bands).left.map(\.id) == (0..<9).map { .band($0) })
        #expect(Self.make(rate: 48000, correction: [], bands: bands).left.map(\.id) == (0..<10).map { .band($0) })
    }

    @Test func oneOutputAtATime() {
        //? made for the output now, from a version at least the last published
        #expect(EQBank.publishable(key: "wired", version: 4, keyNow: "wired", lastPublished: 3))
        #expect(EQBank.publishable(key: "wired", version: 4, keyNow: "wired", lastPublished: 4))
        #expect(EQBank.publishable(key: "wired", version: 1, keyNow: "wired", lastPublished: nil))
        #expect(!EQBank.publishable(key: "wired", version: 3, keyNow: "wired", lastPublished: 4))
        #expect(!EQBank.publishable(key: "speaker", version: 9, keyNow: "wired", lastPublished: 4))
        #expect(!EQBank.publishable(key: "speaker", version: 9, keyNow: nil, lastPublished: nil))
    }

    @Test func bandsAndFiltersAreTwoKindsOfID() {
        #expect(EQSectionID.band(1) != EQSectionID.filter(1))
        let bands = Set((0..<10).map { EQSectionID.band($0).code })
        let filters = Set((0...10_000).map { EQSectionID.filter($0).code })
        #expect(bands.count == 10 && bands.isDisjoint(with: filters))
    }

    @Test func packedAsTheRenderReadsIt() {
        #expect(EQBank.packedCount == 8 + 3 * 80 * 8)
        let bank = Self.make(offsets: EQPreampParts(all: -6, left: 0, right: -1.5), bands: EQGraphic.preset("vocal")!.gains)
        let p = bank.packed
        #expect(p.count == EQBank.packedCount)
        #expect(p[0] == 48000 && p[1] == 0 && Array(p[2..<5]) == bank.levels)
        #expect(Array(p[5..<8]) == [bank.left, bank.right, bank.shared].map { Double($0.count) })
        for (i, list) in [bank.left, bank.right, bank.shared].enumerated() {
            for (s, section) in list.enumerated() {
                let q = Array(p[(8 + (i * 80 + s) * 8)..<(8 + (i * 80 + s + 1) * 8)])
                let c = section.coefficients
                #expect(q == [c.b0, c.b1, c.b2, c.a1, c.a2, section.id.code, section.kind.code, 0])
            }
            //? the rest of the list's slots are empty
            #expect(p[(8 + (i * 80 + list.count) * 8)..<(8 + (i + 1) * 80 * 8)].allSatisfy { $0 == 0 })
        }
        #expect(EQBank.identity(rate: 44100, key: "", version: 0).packed[0...7] == [44100, 1, 1, 1, 1, 0, 0, 0])
        //? never more than 80 a list
        let many = (1...90).map { EQSection(id: .filter($0), kind: .peak, f0: 100, coefficients: EQCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)) }
        #expect(EQBank(rate: 48000, key: "", version: 0, left: many, right: [], shared: [], preamp: 0, levels: [1, 1, 1]).left.count == 80)
    }
}
