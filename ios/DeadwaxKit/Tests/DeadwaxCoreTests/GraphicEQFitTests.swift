import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 3.10: AutoEq's two GraphicEQ.txt files (the HD 650's and the AirPods Pro's) fitted within 0.15 dB RMS and
/// 0.8 dB at most from 20 Hz to 16 kHz, and to NumPy's own solve (Fixtures/eq/graphic.json): the unrounded gains
/// within 1e-6 dB - libm's sin, cos and pow may differ by an ulp between Linux and macOS, so the platforms are held to
/// that, not to each other's bits - and the rounded gains equal.
@Suite struct GraphicEQFitTests {
    /// The file's one line, read plainly here (APOReaderTests hold the reader to the same points).
    static func points(_ path: String) throws -> [GraphicEQPoint] {
        let text = String(decoding: try Fixtures.data("eq/\(path)"), as: UTF8.self)
        let line = text.split(separator: "\n").first { $0.hasPrefix("GraphicEQ:") }!
        return line.dropFirst("GraphicEQ:".count).split(separator: ";").map { (pair: Substring) -> GraphicEQPoint in
            let numbers = pair.split(separator: " ").map { Double($0)! }
            return GraphicEQPoint(numbers[0], numbers[1])
        }.sorted { $0.frequency < $1.frequency }
    }

    @Test func theTwoFixturesAreFittedLikeNumPys() throws {
        let file = try EQFixtures.graphic()
        #expect(GraphicEQFit.centres == file.centres.map(EQFixtures.d))
        #expect(GraphicEQFit.centres.count == 61 && GraphicEQFit.centres.first == 20 && GraphicEQFit.centres.last == 20159)
        #expect(GraphicEQFit.q == EQFixtures.d(file.q))
        #expect(GraphicEQFit.grid().count == file.gridCount)
        #expect(file.fits.count == 2)
        for expected in file.fits {
            let points = try Self.points(expected.path)
            #expect(points.count == expected.points)
            let fit = GraphicEQFit.fit([points])
            let name = expected.path.split(separator: "/").last!
            #expect(abs(fit.median - EQFixtures.d(expected.median)) <= 1e-12, "\(name): median")
            let target = EQFixtures.doubles(expected.target_f8)
            #expect(target.count == fit.target.count)
            #expect(zip(target, fit.target).allSatisfy { abs($0 - $1) <= 1e-12 }, "\(name): target")
            let unrounded = expected.unrounded.map(EQFixtures.d)
            let worst = zip(unrounded, fit.unrounded).map { abs($0 - $1) }.max()!
            #expect(worst <= 1e-6, "\(name): the unrounded gains within \(worst) dB of NumPy's")
            //? a gain within 1e-6 of a rounding boundary may round either way across platforms: none in the
            //? fixtures (the script asserts it), and this says so if one appears
            let nearBoundary = unrounded.filter { abs(abs(($0 * 10).truncatingRemainder(dividingBy: 1)) - 0.5) < 1e-5 }
            #expect(nearBoundary.isEmpty, "\(name): gains on a rounding boundary: \(nearBoundary)")
            #expect(fit.rounded == expected.rounded.map(EQFixtures.d), "\(name): rounded")
            #expect(fit.kept == expected.kept, "\(name): filters")
            #expect(fit.rounds == expected.rounds, "\(name): rounds")
            for (mine, theirs) in [(fit.stats48000, expected.stats48000), (fit.stats44100, expected.stats44100)] {
                #expect(abs(mine.mean - EQFixtures.d(theirs["mean"]!)) <= 1e-6, "\(name): mean")
                #expect(abs(mine.rms - EQFixtures.d(theirs["rms"]!)) <= 1e-6, "\(name): rms")
                #expect(abs(mine.largest - EQFixtures.d(theirs["largest"]!)) <= 1e-6, "\(name): largest")
                #expect(abs(mine.above - EQFixtures.d(theirs["above"]!)) <= 1e-6, "\(name): above")
                #expect(mine.aboveAt == EQFixtures.d(theirs["aboveAt"]!), "\(name): where")
            }
            //? 3.10's bounds: 0.15 dB RMS and 0.8 dB at most up to 16 kHz
            #expect(fit.stats48000.rms <= 0.15 && fit.stats48000.largest <= 0.8, "\(name)")
            print("\(name): unrounded gains within \(worst) dB of NumPy's; median \(fit.median) dB, \(fit.rounds) rounds, \(fit.kept) filters; to 16 kHz mean \(fit.stats48000.mean), RMS \(fit.stats48000.rms), at most \(fit.stats48000.largest) dB; above it \(fit.stats48000.above) dB at \(fit.stats48000.aboveAt) Hz (44.1 kHz: \(fit.stats44100.above) dB)")
        }
    }

    @Test func theSameAnswerEveryRun() throws {
        let points = try Self.points(EQFixtures.graphic().fits[0].path)
        #expect(GraphicEQFit.fit([points]) == GraphicEQFit.fit([points]))
    }

    @Test func itsFiltersArePeaksAtTheCentres() throws {
        let points = try Self.points(EQFixtures.graphic().fits[1].path)
        let fit = GraphicEQFit.fit([points])
        let filters = fit.filters(channel: .left, firstID: 5)
        #expect(filters.count == fit.kept)
        #expect(filters.map(\.id) == Array(5..<(5 + fit.kept)))
        #expect(filters.allSatisfy { $0.kind == .peak && $0.written == "PK" && $0.width == .q(4.32) && $0.channel == .left && $0.gain != 0 })
        #expect(Set(filters.map(\.fc)).isSubset(of: Set(GraphicEQFit.centres)))
    }

    @Test func theTargetIsAPOs() {
        let line = [GraphicEQPoint(100, -2), GraphicEQPoint(1000, 4), GraphicEQPoint(10000, 4)]
        let t = GraphicEQFit.target([line], at: [10, 100, 1000.0.squareRoot() * 10, 1000, 5000, 20000])
        //? flat outside the points at the end points' gains, linear on log frequency between them
        #expect(t[0] == -2 && t[1] == -2 && t[3] == 4 && t[4] == 4 && t[5] == 4)
        #expect(abs(t[2] - 1) <= 1e-12)
        //? several lines add up
        let two = GraphicEQFit.target([line, [GraphicEQPoint(50, 1)]], at: [10, 1000])
        #expect(two == [-1, 5])
        #expect(GraphicEQFit.median([3, 1, 2]) == 2 && GraphicEQFit.median([4, 1, 2, 3]) == 2.5)
    }
}
