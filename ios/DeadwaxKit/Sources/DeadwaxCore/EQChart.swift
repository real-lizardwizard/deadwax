import Foundation

/// The curve as the screen draws it and VoiceOver's audio graph plays it (eq.md 3.4, 3.14): 1.4's response, the one
/// formula, at the output's rate (48 kHz while it isn't connected).
public enum EQChart {
    public struct Point: Equatable, Sendable {
        public var frequency: Double
        public var db: Double

        public init(_ frequency: Double, _ db: Double) {
            self.frequency = frequency
            self.db = db
        }
    }

    /// Every 1/24 octave over the ten octaves centred on the bands: 1000 · 2^((k - 132)/24), 22.1 Hz to 22.6 kHz.
    public static let grid: [Double] = (0...240).map { 1000 * pow(2.0, Double($0 - 132) / 24) }

    /// One ear's curve: the grid and each section's own f0 (so a narrow peak is drawn at its height), below half the
    /// rate, with `level` added - the preamp and the ear's offset, so it is what you hear; 0 for the shape alone.
    public static func points(_ sections: [EQSection], level: Double, rate: Double) -> [Point] {
        let top = min(grid.last!, rate / 2)
        var frequencies = Set(grid.filter { $0 <= top })
        for s in sections where s.f0 >= grid[0] && s.f0 <= top { frequencies.insert(s.f0) }
        let sorted = frequencies.sorted()
        let db = EQResponse.curve(sections.map(\.coefficients), at: sorted, rate: rate, offset: level)
        return zip(sorted, db).map { Point($0, $1) }
    }

    /// The audio graph's series (3.14): 61 points a sixth of an octave apart, 20 Hz to 20 kHz (3.10's centres).
    public static func audioGraph(_ sections: [EQSection], level: Double, rate: Double) -> [Point] {
        let frequencies = GraphicEQFit.centres
        let db = EQResponse.curve(sections.map(\.coefficients), at: frequencies, rate: rate, offset: level)
        return zip(frequencies, db).map { Point($0, $1) }
    }

    /// The y axis, either way of 0 (3.4): ±15 dB, growing to ±18 or ±24 when a curve goes further - and, so nothing
    /// is ever cut off, past that to the next 6 dB.
    public static func range(_ curves: [[Point]]) -> Double {
        let most = curves.flatMap { $0 }.map { abs($0.db) }.max() ?? 0
        for r in [15.0, 18, 24] where most <= r { return r }
        return (most / 6).rounded(.up) * 6
    }

    /// The shape's largest boost and largest cut, and where (for the summary): over every ear's points.
    public static func extremes(_ curves: [[Point]]) -> (boost: Point?, cut: Point?) {
        let all = curves.flatMap { $0 }
        let boost = all.max { $0.db < $1.db }.flatMap { $0.db > 0 ? $0 : nil }
        let cut = all.min { $0.db < $1.db }.flatMap { $0.db < 0 ? $0 : nil }
        return (boost, cut)
    }
}
