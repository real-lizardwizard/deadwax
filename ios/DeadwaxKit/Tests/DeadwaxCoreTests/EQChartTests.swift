import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 3.4 and 3.14: the drawn points - ten octaves centred on the bands, each filter's own f0, the preamp added -
/// the audio graph's 61, the axis's range, and the summary VoiceOver says.
@Suite struct EQChartTests {
    static func shape(_ preset: String, rate: Double = 48000) -> [EQChart.Point] {
        EQChart.points(EQGraphic.sections(gains: EQGraphic.preset(preset)!.gains, rate: rate), level: 0, rate: rate)
    }

    @Test func thePoints() {
        let g = EQChart.grid
        #expect(g.count == 241 && g[132] == 1000)
        #expect(abs(g[0] - 22.097) < 0.001 && abs(g[240] - 22627.4) < 0.1)
        //? the bands are on it, exactly
        for band in EQGraphic.bands { #expect(g.contains(band), "\(band)") }
        //? a narrow peak's own f0 is a point, at its height; the level added; nothing above half the rate
        let peak = EQFilter(id: 1, kind: .peak, fc: 1234.5, gain: 9, width: .q(30))
        let sections = EQBank.sections([peak], rate: 44100)
        let points = EQChart.points(sections, level: -9, rate: 44100)
        let at = points.first { $0.frequency == 1234.5 }
        #expect(abs(at!.db - 0) < 1e-9)
        #expect(points.allSatisfy { $0.frequency <= 22050 } && points.count == g.filter { $0 <= 22050 }.count + 1)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.frequency < $1.frequency })
        #expect(EQChart.points(sections, level: -9, rate: 48000).count == 242)
        //? flat is 0 everywhere, plus its level
        #expect(EQChart.points([], level: -2.5, rate: 48000).allSatisfy { $0.db == -2.5 })
    }

    @Test func theAudioGraph() {
        let graph = EQChart.audioGraph(EQGraphic.sections(gains: EQGraphic.preset("bassBoost")!.gains, rate: 48000),
                                       level: -6.1, rate: 48000)
        #expect(graph.count == 61 && graph.first!.frequency == 20 && graph.last!.frequency == 20159)
        #expect(graph.map(\.db).max()! < 0 && graph.map(\.db).max()! > -0.2)
    }

    @Test func theRange() {
        func curve(_ db: Double) -> [[EQChart.Point]] { [[EQChart.Point(100, db), EQChart.Point(1000, 0)]] }
        #expect(EQChart.range(curve(0)) == 15 && EQChart.range(curve(-15)) == 15)
        #expect(EQChart.range(curve(15.1)) == 18 && EQChart.range(curve(-18)) == 18)
        #expect(EQChart.range(curve(-20)) == 24 && EQChart.range(curve(24)) == 24)
        #expect(EQChart.range(curve(-31)) == 36)
        #expect(EQChart.range([]) == 15)
    }

    @Test func theSummaries() {
        #expect(EQWords.curveSummary(on: false, shape: [Self.shape("bassBoost")], preamp: -6.1) == "Off.")
        #expect(EQWords.curveSummary(on: true, shape: [Self.shape("flat")], preamp: 0) == "Flat.")
        #expect(EQWords.curveSummary(on: true, shape: [Self.shape("flat")], preamp: -1) == "Flat. Preamp minus 1 decibel.")
        #expect(EQWords.curveSummary(on: true, shape: [Self.shape("bassBoost")], preamp: -6.1)
                == "Up to 6 decibels louder in the bass. Preamp minus 6.1 decibels.")
        #expect(EQWords.curveSummary(on: true, shape: [Self.shape("bassReduce")], preamp: 0)
                == "Up to 6 decibels quieter in the bass.")
        #expect(EQWords.curveSummary(on: true, shape: [Self.shape("trebleBoost")], preamp: -4.8)
                == "Up to 5 decibels louder in the treble. Preamp minus 4.8 decibels.")
        #expect(EQWords.curveSummary(on: true, shape: [Self.shape("vocal")], preamp: -3.3)
                == "Up to 3.5 decibels louder in the upper mids; up to 2.5 decibels quieter in the bass. Preamp minus 3.3 decibels.")
        #expect(EQWords.curveSummary(on: true, shape: [Self.shape("spokenWord")], preamp: -3.7)
                == "Up to 3.5 decibels louder in the upper mids; up to 7 decibels quieter in the bass. Preamp minus 3.7 decibels.")
        //? the lower mids, and under 1 dB said as nothing
        let mids = EQBank.sections([EQFilter(id: 1, kind: .peak, fc: 500, gain: 4.2, width: .q(2)),
                                    EQFilter(id: 2, kind: .peak, fc: 8000, gain: -0.9, width: .q(2))], rate: 48000)
        #expect(EQWords.curveSummary(on: true, shape: [EQChart.points(mids, level: 0, rate: 48000)], preamp: -4.2)
                == "Up to 4 decibels louder in the lower mids. Preamp minus 4.2 decibels.")
        //? over both ears
        let left = EQChart.points(EQBank.sections([EQFilter(id: 1, kind: .peak, fc: 100, gain: 3, width: .q(1))], rate: 48000), level: 0, rate: 48000)
        let right = EQChart.points(EQBank.sections([EQFilter(id: 2, kind: .peak, fc: 6000, gain: -5, width: .q(1))], rate: 48000), level: 0, rate: 48000)
        #expect(EQWords.curveSummary(on: true, shape: [left, right], preamp: -3)
                == "Up to 3 decibels louder in the bass; up to 5 decibels quieter in the treble. Preamp minus 3 decibels.")
    }
}
