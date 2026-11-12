import Foundation

/// The curve as the EQ screen draws it and VoiceOver's audio graph plays it (eq.md 3.4, 3.14): what you hear on an
/// output - its response at the output's rate (48 kHz while it isn't connected), the one formula of 1.4, **with the
/// preamp added**, so the top sits at 0 dB or below - and beside it the correction alone (dashed, state 5), the tone
/// alone (dotted, Advanced), or each ear as a line of its own (state 6). Off is flat at 0.
///
/// Every line is drawn at the same frequencies - 1/24 octave over the ten octaves centred on the bands, plus each
/// section's own f0 so a narrow peak is drawn at its height - whatever the rate: above half the rate a line holds the
/// value it has there, so the x axis is the same on every output and a line can morph from one output's to another's.
public struct EQDrawing: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// what you hear - both ears, or the left's in state 6 - filled to 0 dB
            case heard
            /// the right ear's (state 6)
            case right
            /// the correction alone, dashed (state 5)
            case correction
            /// the tone alone, dotted (Advanced)
            case tone
        }

        public var kind: Kind
        /// dB at each of the drawing's frequencies
        public var db: [Double]
        /// "Left", "Right" at its right end (state 6)
        public var label: String?
    }

    /// One series of the audio graph (3.14).
    public struct Series: Equatable, Sendable {
        public var name: String
        public var points: [EQChart.Point]
    }

    public var on: Bool
    /// the rate it was worked out at
    public var rate: Double
    public var frequencies: [Double]
    public var lines: [Line]
    /// the y axis, either way of 0 (EQChart.range)
    public var range: Double
    /// the preamp as it plays
    public var preamp: Double
    /// the identity bank: no sections at this rate, the level exactly 1 - nothing changes the sound (3.3, state 2)
    public var identity: Bool
    /// the curve's top over the ears, before the preamp - worked out only for a preamp set by hand (3.3, states 8-9)
    public var top: Double
    /// VoiceOver's value for the curve (EQWords.curveSummary)
    public var summary: String
    /// the audio graph's series, 61 points each
    public var graph: [Series]

    /// An output's curve at a rate (`advanced`: the tone alone drawn too, beside a correction).
    public static func make(_ setting: EQOutputSetting, in settings: EQSettings, rate: Double,
                            advanced: Bool = false) -> EQDrawing {
        guard setting.on else { return off(rate: rate) }
        let bank = settings.bank(setting, rate: rate, version: 0)
        let offsets = setting.correction?.preamp ?? .zero
        let filters = setting.correction?.filters ?? []
        let perEar = offsets.perEar || filters.contains { $0.channel != .all }
        let frequencies = drawn(bank.left + bank.right)
        let left = values(bank.left, at: frequencies, rate: rate)
        let leftLevel = bank.preamp + offsets.left
        var lines = [Line(kind: .heard, db: left.map { $0 + leftLevel }, label: perEar ? EQWords.Screen.left : nil)]
        var shapes = [left]
        var graph = [Series(name: perEar ? EQWords.Screen.left : EQWords.Said.whatYouHear,
                            points: points(bank.left, rate: rate, level: leftLevel))]
        if perEar {
            let right = values(bank.right, at: frequencies, rate: rate)
            let rightLevel = bank.preamp + offsets.right
            lines.append(Line(kind: .right, db: right.map { $0 + rightLevel }, label: EQWords.Screen.right))
            shapes.append(right)
            graph.append(Series(name: EQWords.Screen.right, points: points(bank.right, rate: rate, level: rightLevel)))
        }
        let correction = EQBank.sections(filters.filter { $0.channel != .right }, rate: rate)
        let tone = EQGraphic.sections(gains: settings.gains(setting.tone), rate: rate)
        if !correction.isEmpty && !tone.isEmpty && !perEar {
            lines.append(Line(kind: .correction, db: values(correction, at: frequencies, rate: rate).map { $0 + leftLevel }))
            if advanced {
                graph.append(Series(name: EQWords.Said.correction, points: points(correction, rate: rate, level: leftLevel)))
            }
        }
        if advanced && !correction.isEmpty && !tone.isEmpty && !perEar {
            lines.append(Line(kind: .tone, db: values(tone, at: frequencies, rate: rate).map { $0 + leftLevel }))
            graph.append(Series(name: EQWords.Said.tone, points: points(tone, rate: rate, level: leftLevel)))
        }
        var top = 0.0
        if case .hand = setting.preamp {
            top = EQResponse.top([EQResponse.Ear(sections: bank.left, offset: offsets.left),
                                  EQResponse.Ear(sections: bank.right, offset: offsets.right)], rate: rate).db
        }
        let range = EQChart.range(lines.map { line in zip(frequencies, line.db).map { EQChart.Point($0, $1) } })
        let summary = EQWords.curveSummary(on: true, shape: shapes.map { shape in
            zip(frequencies, shape).map { EQChart.Point($0, $1) }
        }, preamp: bank.preamp)
        return EQDrawing(on: true, rate: rate, frequencies: frequencies, lines: lines, range: range,
                         preamp: bank.preamp, identity: bank.isIdentity, top: top, summary: summary, graph: graph)
    }

    /// Off: flat at 0 (3.3, state 1).
    public static func off(rate: Double) -> EQDrawing {
        let frequencies = EQChart.grid
        return EQDrawing(on: false, rate: rate, frequencies: frequencies,
                         lines: [Line(kind: .heard, db: Array(repeating: 0, count: frequencies.count))],
                         range: EQChart.range([]), preamp: 0, identity: true, top: 0,
                         summary: EQWords.curveSummary(on: false, shape: [], preamp: 0),
                         graph: [Series(name: EQWords.Said.whatYouHear, points: points([], rate: rate, level: 0))])
    }

    /// The x axis's frequencies (3.4): the chart's grid and each section's own f0 inside it, whatever the rate.
    public static func drawn(_ sections: [EQSection]) -> [Double] {
        var set = Set(EQChart.grid)
        let lo = EQChart.grid[0], hi = EQChart.grid[EQChart.grid.count - 1]
        for s in sections where s.f0 >= lo && s.f0 <= hi { set.insert(s.f0) }
        return set.sorted()
    }

    /// The response at each frequency (ascending), in dB; above half the rate, the value at the last frequency below
    /// it - the line stays level to the plot's edge rather than folding back.
    public static func values(_ sections: [EQSection], at frequencies: [Double], rate: Double, level: Double = 0) -> [Double] {
        let below = frequencies.prefix { $0 <= rate / 2 }
        var db = EQResponse.curve(sections.map(\.coefficients), at: Array(below), rate: rate, offset: level)
        db += Array(repeating: db.last ?? level, count: frequencies.count - below.count)
        return db
    }

    /// The audio graph's 61 points (3.14: 1/6 octave, 20 Hz to 20 kHz), held above half the rate as the lines are.
    static func points(_ sections: [EQSection], rate: Double, level: Double) -> [EQChart.Point] {
        let frequencies = GraphicEQFit.centres
        return zip(frequencies, values(sections, at: frequencies, rate: rate, level: level)).map { EQChart.Point($0, $1) }
    }

    /// The line drawn for VoiceOver and for the plot's y: a dB value's place in a plot of `height`, `range` either way
    /// of 0 at its middle - +range at the top.
    public static func y(_ db: Double, range: Double, height: Double) -> Double {
        height / 2 - db / range * height / 2
    }

    /// A frequency's place across a plot of `width`, by octaves from the grid's first to its last.
    public static func x(_ frequency: Double, width: Double) -> Double {
        let lo = log2(EQChart.grid[0]), hi = log2(EQChart.grid[EQChart.grid.count - 1])
        return (log2(frequency) - lo) / (hi - lo) * width
    }
}
