import Foundation

/// The tone's ten bands and the built-in presets (eq.md 3.5, 3.6).
public enum EQGraphic {
    /// Octaves at exactly 1000 · 2^k Hz, k = -5 … 4 - so an export writes the frequency that plays (`Fc 31.25 Hz`;
    /// 8, question 24).
    public static let bands: [Double] = (-5...4).map { 1000.0 * pow(2.0, Double($0)) }

    /// One octave wide, written and played as 1.41 - AutoEq's FixedBandEQ's own (1.3; 8, question 11).
    public static let q = 1.41

    /// The ISO octaves' names, under each slider.
    public static let names = ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    /// ±12 dB in 0.5 dB steps.
    public static let range = -12.0...12.0
    public static let step = 0.5

    /// All ten at 0: no tone.
    public static let flat = [Double](repeating: 0, count: 10)

    /// A finger's value: rounded to the step, inside the range.
    public static func snapped(_ gain: Double) -> Double {
        min(max((gain / step).rounded() * step, range.lowerBound), range.upperBound)
    }

    /// A band as a filter - a peak at its frequency, Q 1.41 - as an export writes it (3.11).
    public static func filter(band: Int, gain: Double, id: Int = 0) -> EQFilter {
        EQFilter(id: id, kind: .peak, written: "PK", fc: bands[band], gain: gain, width: .q(q))
    }

    /// The bands that change the sound at a rate, as sections `.band(i)`: one at 0 dB is exactly flat, so left out
    /// (1.3), and the 16 kHz band is above what 32 kHz plays and left out there.
    public static func sections(gains: [Double], rate: Double) -> [EQSection] {
        var out: [EQSection] = []
        for (i, gain) in gains.prefix(bands.count).enumerated() {
            let design = filter(band: i, gain: gain).design(rate: rate)
            if design.outcome == .plays, let f0 = design.f0, let c = design.coefficients {
                out.append(EQSection(id: .band(i), kind: .peak, f0: f0, coefficients: c))
            }
        }
        return out
    }

    /// The built-in presets (James's decision), in the presets page's order: each a position of the ten sliders.
    public static let presets: [EQPreset] = [
        EQPreset(id: "flat", name: "Flat", gains: flat, note: "Nothing changed."),
        EQPreset(id: "bassBoost", name: "Bass Boost", gains: [5, 4.5, 3, 1, 0, 0, 0, 0, 0, 0], note: "More low end."),
        EQPreset(id: "bassReduce", name: "Bass Reduce", gains: [-5, -4.5, -3, -1, 0, 0, 0, 0, 0, 0],
                 note: "Less low end."),
        EQPreset(id: "trebleBoost", name: "Treble Boost", gains: [0, 0, 0, 0, 0, 0, 1, 2.5, 3.5, 4.5],
                 note: "More sparkle and air."),
        EQPreset(id: "trebleReduce", name: "Treble Reduce", gains: [0, 0, 0, 0, 0, 0, -1, -2.5, -3.5, -4.5],
                 note: "Softer highs, for bright recordings or headphones."),
        EQPreset(id: "vocal", name: "Vocal", gains: [-2, -1.5, -1, 0, 1, 2, 2.5, 2, 0.5, 0],
                 note: "Voices brought forward."),
        EQPreset(id: "loudness", name: "Loudness", gains: [5, 4, 2, 0.5, 0, 0, 0, 1, 2.5, 3],
                 note: "For listening quietly: the lows and highs lifted, as ears hear less of them at low volume."),
        EQPreset(id: "smallSpeakers", name: "Small Speakers", gains: [-4, -1, 2.5, 2.5, 1, 0, 0, 1, 1.5, 0],
                 note: "For small speakers that can't play deep bass: the upper bass lifted instead."),
        EQPreset(id: "spokenWord", name: "Spoken Word", gains: [-6, -4.5, -2.5, -1, 0, 1, 2.5, 3, 1.5, -1],
                 note: "For podcasts and audiobooks: rumble cut, voices clearer."),
    ]

    public static func preset(_ id: String) -> EQPreset? { presets.first { $0.id == id } }
}

/// A built-in preset: its id (as 4 keeps it), name, the ten gains and its note.
public struct EQPreset: Equatable, Sendable {
    public let id: String
    public let name: String
    public let gains: [Double]
    public let note: String
}
