import Foundation
import Testing
@testable import DeadwaxCore

/// eq.md 3.3, 3.4 and 3.14: the curve the EQ screen draws and VoiceOver's audio graph plays - what you hear, the preamp
/// added, so it tops at 0 dB or below; Off flat; the same x axis at every rate, so one output's line morphs into
/// another's.
@Suite struct EQDrawingTests {
    static let airpods = EQOutputs.output(EQRoutePort(port: .bluetoothA2DP, portType: "", name: "James's AirPods Pro",
                                                      uid: "a"))

    static func settings(_ tone: EQTone, on: Bool = true, preamp: EQPreampSetting = .automatic,
                         correction: EQCorrection? = nil) -> (EQSettings, EQOutputSetting) {
        var s = EQSettings()
        s.met(airpods, at: "")
        s.choose(tone, for: airpods)
        s.setOn(on, for: airpods)
        if let i = s.outputs.firstIndex(where: { $0.key == airpods.key }) {
            s.outputs[i].preamp = preamp
            s.outputs[i].correction = correction
        }
        return (s, s.output(airpods.key)!)
    }

    @Test func offIsFlatAtZero() {
        let (s, o) = Self.settings(.preset("bassBoost"), on: false)
        let d = EQDrawing.make(o, in: s, rate: 48_000)
        #expect(!d.on && d.identity && d.preamp == 0 && d.range == 15)
        #expect(d.lines.count == 1 && d.lines[0].db.allSatisfy { $0 == 0 })
        #expect(d.frequencies == EQChart.grid)
        #expect(d.summary == "Off.")
        #expect(d.graph.count == 1 && d.graph[0].points.count == 61 && d.graph[0].points.allSatisfy { $0.db == 0 })
    }

    /// What you hear: the tone's response with the preamp added - EQChart's own points, so the top sits at 0 dB.
    @Test func whatYouHearTopsAtZero() {
        let (s, o) = Self.settings(.preset("bassBoost"))
        let d = EQDrawing.make(o, in: s, rate: 48_000)
        let bank = s.bank(o, rate: 48_000, version: 0)
        #expect(d.on && !d.identity && d.preamp == bank.preamp && d.preamp < -6)
        #expect(d.lines.map(\.kind) == [.heard] && d.lines[0].label == nil)
        let chart = EQChart.points(bank.left, level: bank.preamp, rate: 48_000)
        #expect(chart.map(\.frequency) == d.frequencies)
        for (a, b) in zip(chart, d.lines[0].db) { #expect(abs(a.db - b) < 1e-12) }
        #expect(d.lines[0].db.max()! <= 1e-9)
        #expect(d.lines[0].db.max()! > -0.2)
        #expect(d.summary == "Up to 6 decibels louder in the bass. Preamp minus 6.1 decibels.")
        //? the audio graph says the same line: 61 points, 20 Hz to 20 kHz
        #expect(d.graph.map(\.name) == ["What you hear"])
        #expect(d.graph[0].points.first?.frequency == 20 && d.graph[0].points.last?.frequency == 20_159)
    }

    /// The ten bands sit on the grid, so the tone's drawing is at the grid's frequencies at every rate - and a line
    /// morphs from one output's to another's, point for point.
    @Test func theSameFrequenciesAtEveryRate() {
        let (s, o) = Self.settings(.preset("loudness"))
        for rate in [44_100.0, 48_000, 96_000] {
            let d = EQDrawing.make(o, in: s, rate: rate)
            #expect(d.frequencies == EQChart.grid, "\(rate)")
            #expect(d.lines[0].db.count == EQChart.grid.count)
        }
        //? above half the rate the line holds its last value, rather than folding back
        let low = EQDrawing.make(o, in: s, rate: 22_050)
        let half = EQChart.grid.lastIndex { $0 <= 11_025 }!
        #expect(low.lines[0].db[(half + 1)...].allSatisfy { $0 == low.lines[0].db[half] })
    }

    /// The simple face's curve morphs point for point (EQCurveView's EQVector): so every tone - each preset, Custom, a
    /// band at any value, Off - is drawn at the grid's frequencies alone, the bands' centres being on it (slice 3).
    @Test func everyToneIsDrawnOnTheGrid() {
        var tones: [EQTone] = EQGraphic.presets.map { .preset($0.id) }
        tones.append(.custom([12, -12, 0.5, -0.5, 7, -3, 1.5, 0, -8, 11.5]))
        for band in 0..<10 {
            var gains = EQGraphic.flat
            gains[band] = -12
            tones.append(.custom(gains))
        }
        for tone in tones {
            for rate in [44_100.0, 48_000] {
                for on in [true, false] {
                    let (s, o) = Self.settings(tone, on: on)
                    let d = EQDrawing.make(o, in: s, rate: rate)
                    #expect(d.frequencies == EQChart.grid, "\(tone) at \(rate), on \(on)")
                    #expect(d.lines.allSatisfy { $0.db.count == EQChart.grid.count })
                }
            }
        }
    }

    /// The y axis grows when a curve goes past ±15 dB (a cut has no preamp to bring it back).
    @Test func theRangeGrows() {
        let deep = EQTone.custom([-12, -12, -12, -12, -12, -12, -12, -12, -12, -12])
        let (s, o) = Self.settings(deep)
        let d = EQDrawing.make(o, in: s, rate: 48_000)
        #expect(d.preamp == 0)
        #expect(d.lines[0].db.min()! < -18 && d.range == 24)
        #expect(d.summary.hasPrefix("Up to 18.5 decibels quieter in the lower mids."))
    }

    /// State 5: a correction and a tone - the sum, and the correction alone as a second line; in Advanced the tone
    /// alone too. State 6: a correction per ear - "Left" and "Right".
    @Test func aCorrectionDrawsItsOwnLine() {
        let filters = [EQFilter(id: 1, kind: .peak, fc: 3_000, gain: 4, width: .q(2)),
                       EQFilter(id: 2, kind: .lowShelf, fc: 105, gain: -3, width: .q(0.7))]
        let correction = EQCorrection(kind: .built, name: "Mine", nextFilterID: 3, filters: filters)
        let (s, o) = Self.settings(.preset("bassBoost"), correction: correction)
        let d = EQDrawing.make(o, in: s, rate: 48_000)
        #expect(d.lines.map(\.kind) == [.heard, .correction])
        #expect(d.frequencies.contains(3_000) && d.frequencies.count == EQChart.grid.count + 2)
        let advanced = EQDrawing.make(o, in: s, rate: 48_000, advanced: true)
        #expect(advanced.lines.map(\.kind) == [.heard, .correction, .tone])
        #expect(advanced.graph.map(\.name) == ["What you hear", "Correction", "Tone"])

        var perEar = correction
        perEar.filters[0].channel = .left
        let (s2, o2) = Self.settings(.preset("bassBoost"), correction: perEar)
        let ears = EQDrawing.make(o2, in: s2, rate: 48_000)
        #expect(ears.lines.map(\.kind) == [.heard, .right] && ears.lines.map(\.label) == ["Left", "Right"])
        #expect(ears.graph.map(\.name) == ["Left", "Right"])
        #expect(max(ears.lines[0].db.max()!, ears.lines[1].db.max()!) <= 1e-9)
    }

    /// A preamp set by hand: the curve's top worked out, for the line under it (states 8, 9).
    @Test func aPreampByHand() {
        let (s, o) = Self.settings(.preset("bassBoost"), preamp: .hand(-3))
        let d = EQDrawing.make(o, in: s, rate: 48_000)
        #expect(d.preamp == -3 && d.top > 5.9 && d.top < 6.1)
        let line = EQScreenRules.line(on: d.on, identity: d.identity, preamp: o.preamp, played: d.preamp, top: d.top,
                                      unitNotMade: false)
        #expect(line.tone == .amber && line.text.hasPrefix("Loud songs may clip: the curve boosts 3."))
    }

    @Test func flatOnIsTheIdentity() {
        let (s, o) = Self.settings(.preset("flat"))
        let d = EQDrawing.make(o, in: s, rate: 48_000)
        #expect(d.on && d.identity && d.summary == "Flat.")
        #expect(EQScreenRules.line(on: true, identity: d.identity, preamp: o.preamp, played: d.preamp, top: 0,
                                   unitNotMade: false).text == "Flat: nothing changes the sound yet.")
    }

    @Test func placesInThePlot() {
        #expect(EQDrawing.x(EQChart.grid[0], width: 300) == 0)
        #expect(abs(EQDrawing.x(EQChart.grid[240], width: 300) - 300) < 1e-9)
        #expect(abs(EQDrawing.x(1_000, width: 240) - 132) < 1e-9)
        #expect(EQDrawing.y(0, range: 15, height: 150) == 75)
        #expect(EQDrawing.y(15, range: 15, height: 150) == 0 && EQDrawing.y(-15, range: 15, height: 150) == 150)
    }
}
