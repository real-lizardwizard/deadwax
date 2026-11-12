import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 5.1: real AutoEq ParametricEQ.txt files (Fixtures/eq/autoeq/, MIT, at AutoEq's 7ae0f56) - their curve here
/// against AutoEq's own biquads (peq.py, run by the fixture script) within 0.001 dB at 44.1 and 48 kHz, against the
/// result CSV's `parametric_eq` within 0.15 dB where there is one (that curve is the filters' before AutoEq rounded
/// them, 0.4), and deadwax's automatic preamp within 0.5 dB of the file's own `Preamp:`.
@Suite struct AutoEqProfileTests {
    static func sections(_ filters: [EQFilter], rate: Double) -> [EQSection] {
        filters.compactMap { f in
            let d = f.design(rate: rate)
            guard d.outcome == .plays, let f0 = d.f0, let c = d.coefficients else { return nil }
            return EQSection(id: .filter(f.id), kind: f.kind, f0: f0, coefficients: c)
        }
    }

    @Test func eachProfilesCurveIsAutoEqsOwn() throws {
        let file = try EQFixtures.profiles()
        #expect(file.profiles.count >= 12)
        //? crinacle's AirPods Pro and an AirPods Pro 2 among them (5.1)
        #expect(file.profiles.contains { $0.measurer == "crinacle" && $0.path.hasSuffix("/Apple AirPods Pro ParametricEQ.txt") })
        #expect(file.profiles.contains { $0.path.contains("AirPods Pro 2") })
        let grid = EQFixtures.profileGrid()
        #expect(grid.count == file.gridCount)
        var worst = 0.0
        for profile in file.profiles {
            let filters = profile.filters.map(\.filter)
            for (rate, reference) in [(44100.0, profile.peq44100_f4), (48000.0, profile.peq48000_f4)] {
                let curve = EQResponse.curve(Self.sections(filters, rate: rate).map(\.coefficients), at: grid, rate: rate)
                let peq = EQFixtures.floats(reference)
                #expect(peq.count == grid.count)
                for (i, (mine, theirs)) in zip(curve, peq).enumerated() {
                    worst = max(worst, abs(mine - Double(theirs)))
                    #expect(abs(mine - Double(theirs)) <= 0.001, "\(profile.name) at \(rate): \(mine) dB at \(grid[i]) Hz against peq.py's \(theirs)")
                }
            }
        }
        print("AutoEq profiles: within \(worst) dB of peq.py")
    }

    @Test func aProfileWithACSVIsWithinItsUnroundedCurve() throws {
        let profiles = try EQFixtures.profiles().profiles.filter { $0.csv != nil }
        #expect(profiles.count >= 1)
        #expect(profiles.contains { $0.path.contains("Sennheiser HD 650") })
        for profile in profiles {
            let text = String(decoding: try Fixtures.data("eq/\(profile.csv!)"), as: UTF8.self)
            let rows = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").map(String.init) }
            let header = rows[0]
            let fi = header.firstIndex(of: "frequency")!
            let pi = header.firstIndex(of: "parametric_eq")!
            let sections = Self.sections(profile.filters.map(\.filter), rate: 44100).map(\.coefficients)
            var worst = 0.0
            var count = 0
            for row in rows.dropFirst() where row.count > max(fi, pi) {
                let f = Double(row[fi])!
                let mine = EQResponse.db(sections, at: f, rate: 44100)
                worst = max(worst, abs(mine - Double(row[pi])!))
                count += 1
            }
            #expect(count > 600)
            #expect(worst <= 0.15, "\(profile.name): \(worst) dB from the CSV's parametric_eq")
            print("\(profile.name): within \(worst) dB of the CSV's parametric_eq over \(count) frequencies")
        }
    }

    @Test func deadwaxsPreampIsWithinHalfADecibelOfTheFiles() throws {
        for profile in try EQFixtures.profiles().profiles {
            let sections = Self.sections(profile.filters.map(\.filter), rate: 48000)
            let top = EQResponse.top([EQResponse.Ear(sections: sections)], rate: 48000)
            let mine = EQPreamp.automatic(top: top.db)
            let theirs = EQFixtures.d(profile.filePreamp)
            print("\(profile.name): the file's preamp \(theirs) dB, deadwax's \(mine) dB (its top \(top.db) dB at \(top.at) Hz)")
            #expect(abs(mine - theirs) <= 0.5 + 1e-12, "\(profile.name)")
            //? and the Python's: the same top, to libm's last bits
            #expect(mine == EQFixtures.d(profile.automaticPreamp48000), "\(profile.name)")
            #expect(abs(top.db - EQFixtures.d(profile.top48000)) <= 1e-9, "\(profile.name): top")
        }
    }
}
