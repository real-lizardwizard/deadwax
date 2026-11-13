import Foundation

// The EQ's filters (notes/ios-specs/eq.md 1.3): each kept as a file writes it - its type as written, its width as
// written - and worked out at every rate the way Equalizer APO's source works it out (0.3: BiQuadFilterFactory.cpp,
// BiQuadFilter.cpp, BiQuad.cpp at 53d885f7f1), in Double. ios/scripts/make-eq-fixtures.py writes the same rules out
// again in Python, and Fixtures/eq/filters.json holds this file to it.

/// 1.3's eight kinds.
public enum EQKind: String, Codable, Sendable, CaseIterable, Equatable {
    case peak, lowShelf, highShelf, lowPass, highPass, bandPass, notch, allPass

    public var isShelf: Bool { self == .lowShelf || self == .highShelf }

    /// A gain that changes the sound: peaks and shelves. A band pass reads one and ignores it (0.3); the passes, the
    /// notch and the all pass ignore it.
    public var hasGain: Bool { self == .peak || isShelf }

    /// Equalizer APO's type names and what each plays (0.3, 1.3's table), names matched with their case. `IIR` is
    /// another factory's (refused, 3.9) and `None` plays nothing.
    public static let written: [String: EQKind] = [
        "PK": .peak, "PEQ": .peak, "Modal": .peak, "LP": .lowPass, "LPQ": .lowPass, "HP": .highPass, "HPQ": .highPass,
        "BP": .bandPass, "LS": .lowShelf, "HS": .highShelf, "LSC": .lowShelf, "HSC": .highShelf, "NO": .notch,
        "AP": .allPass,
    ]

    /// The type a filter made here is written as: a shelf by its centre (`LSC`, `HSC`, as AutoEq writes it).
    public var defaultWritten: String {
        switch self {
        case .peak: "PK"
        case .lowShelf: "LSC"
        case .highShelf: "HSC"
        case .lowPass: "LP"
        case .highPass: "HP"
        case .bandPass: "BP"
        case .notch: "NO"
        case .allPass: "AP"
        }
    }

    /// The kind's place, as the render's packed bank keeps it.
    var code: Double { Double(Self.allCases.firstIndex(of: self)!) }
}

/// A filter's width as the file wrote it (1.3): a Q, a bandwidth in octaves (`BW Oct`) or a shelf's slope in dB an
/// octave (`LSC 12 dB`, `LS 6dB`). Kept as written - 0 included, which is the type's default - so every rate works it
/// out as APO does.
public enum EQWidth: Equatable, Sendable {
    case q(Double)
    case bandwidth(Double)
    case slope(Double)

    public var value: Double {
        switch self {
        case .q(let v), .bandwidth(let v), .slope(let v): v
        }
    }
}

extension EQWidth: Codable {
    private enum Keys: String, CodingKey { case q, bandwidth, slope }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let v = try c.decodeIfPresent(Double.self, forKey: .q) {
            self = .q(v)
        } else if let v = try c.decodeIfPresent(Double.self, forKey: .bandwidth) {
            self = .bandwidth(v)
        } else {
            self = .slope(try c.decode(Double.self, forKey: .slope))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .q(let v): try c.encode(v, forKey: .q)
        case .bandwidth(let v): try c.encode(v, forKey: .bandwidth)
        case .slope(let v): try c.encode(v, forKey: .slope)
        }
    }
}

/// Which channels a filter is for (APO's `Channel:` as a phone has them).
public enum EQChannel: String, Codable, Sendable, CaseIterable, Equatable {
    case all, left, right
}

/// A section's five coefficients, normalised by a0: `y = b0 x + b1 x1 + b2 x2 - a1 y1 - a2 y2`.
public struct EQCoefficients: Equatable, Sendable {
    public var b0: Double
    public var b1: Double
    public var b2: Double
    public var a1: Double
    public var a2: Double

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    /// The same five, bit for bit - `==` would take 0 and -0 as one.
    public func sameBits(_ other: EQCoefficients) -> Bool {
        b0.bitPattern == other.b0.bitPattern && b1.bitPattern == other.b1.bitPattern
            && b2.bitPattern == other.b2.bitPattern && a1.bitPattern == other.a1.bitPattern
            && a2.bitPattern == other.a2.bitPattern
    }
}

/// How a filter plays at a rate (1.3): it plays, or why it doesn't.
public enum EQOutcome: String, Sendable, Equatable {
    /// a section at `f0`
    case plays
    /// switched off (APO's `OFF`)
    case off
    /// a peak or an all pass with no width, or a width of 0: APO leaves it out
    case noWidth
    /// a shelf whose slope is too steep for its gain: no filter (refused at import, 3.9)
    case tooSteep
    /// a peak or a shelf at exactly 0 dB: exactly flat, so left out - which is what lets a flat curve be the
    /// identity (1.7)
    case flat
    /// its f0 at or above 0.49 x the rate: the formulas fold over past Nyquist
    case above
}

/// A filter worked out at a rate.
public struct EQDesign: Equatable, Sendable {
    public var outcome: EQOutcome
    /// where it is centred (a corner shelf's moved frequency); nil when it has no width or is off
    public var f0: Double?
    /// only when it plays
    public var coefficients: EQCoefficients?
}

/// One correction filter (1.3, kept as 4 says).
public struct EQFilter: Equatable, Sendable, Codable {
    /// the correction's own counter (`nextFilterID`, 4): the warm start (1.6) matches a section by it
    public var id: Int
    public var kind: EQKind
    /// the type as the file wrote it (`LSC`, `LS`, `PEQ`, `Modal`), so an export writes it back
    public var written: String
    /// Hz: a shelf's corner when `corner`, else its centre
    public var fc: Double
    /// dB (0 for a pass, a notch or an all pass)
    public var gain: Double
    public var width: EQWidth?
    /// a shelf read by its corner (0.3: `LS`/`HS` given a Q or a slope)
    public var corner: Bool
    public var channel: EQChannel
    public var on: Bool

    public init(id: Int = 0, kind: EQKind, written: String? = nil, fc: Double, gain: Double = 0, width: EQWidth? = nil,
                corner: Bool = false, channel: EQChannel = .all, on: Bool = true) {
        self.id = id
        self.kind = kind
        self.written = written ?? kind.defaultWritten
        self.fc = fc
        self.gain = gain
        self.width = width
        self.corner = corner
        self.channel = channel
        self.on = on
    }

    private enum Keys: String, CodingKey { case id, kind, written, fc, gain, width, corner, channel, on }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decode(EQKind.self, forKey: .kind)
        written = try c.decode(String.self, forKey: .written)
        fc = try c.decode(Double.self, forKey: .fc)
        gain = try c.decode(Double.self, forKey: .gain)
        width = try c.decodeIfPresent(EQWidth.self, forKey: .width)
        corner = try c.decode(Bool.self, forKey: .corner)
        channel = try c.decode(EQChannel.self, forKey: .channel)
        on = try c.decode(Bool.self, forKey: .on)
    }

    /// 4's shape, `"width": null` included.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(written, forKey: .written)
        try c.encode(fc, forKey: .fc)
        try c.encode(gain, forKey: .gain)
        try c.encode(width, forKey: .width)
        try c.encode(corner, forKey: .corner)
        try c.encode(channel, forKey: .channel)
        try c.encode(on, forKey: .on)
    }

    /// The width APO plays (BiQuadFilterFactory.cpp's bandwidthOrQOrS and isBandwidthOrS): a Q (`isBandwidthOrS`
    /// false); a bandwidth in octaves, or for a shelf its S (true). A bandwidth is ignored on a shelf and a slope
    /// anywhere else; with no width, or a width of 0, the type's default - a pass or band pass Q 1/√2 (a `BW Oct 0`
    /// keeping its kind: 1/√2 octaves), a notch Q 30 (or 30 octaves), a shelf S 0.9 - and a peak or an all pass none.
    /// `given` is false for a default.
    public struct PlayedWidth: Equatable, Sendable {
        public var value: Double
        public var isBandwidthOrS: Bool
        public var given: Bool
    }

    public var playedWidth: PlayedWidth? {
        var value = 0.0
        var isBWS = false
        switch width {
        case .q(let v)?:
            value = v
        case .bandwidth(let v)? where !kind.isShelf:
            value = v
            isBWS = true
        case .slope(let v)? where kind.isShelf:
            value = v
            isBWS = true
        default:
            break
        }
        if value == 0 {
            switch kind {
            case .peak, .allPass: return nil
            case .lowPass, .highPass, .bandPass: return PlayedWidth(value: (0.5).squareRoot(), isBandwidthOrS: isBWS, given: false)
            case .lowShelf, .highShelf: return PlayedWidth(value: 0.9, isBandwidthOrS: true, given: false)
            case .notch: return PlayedWidth(value: 30, isBandwidthOrS: isBWS, given: false)
            }
        }
        if kind.isShelf && isBWS { value = value / 12 }
        return PlayedWidth(value: value, isBandwidthOrS: isBWS, given: true)
    }

    /// Where the cookbook centres it (BiQuadFilter.cpp): a shelf read by its corner moved by
    /// `10^(|g| / 80 / S)` - up for a low shelf, down for a high one - with S from its slope, or from its Q as
    /// `1 / ((1/Q² − 2) / (A + 1/A) + 1)`; every other filter at its Fc. Nil when it has no width.
    public var f0: Double? {
        guard let w = playedWidth else { return nil }
        return Self.f0(fc: fc, gain: gain, kind: kind, corner: corner, width: w)
    }

    static func f0(fc: Double, gain: Double, kind: EQKind, corner: Bool, width w: PlayedWidth) -> Double {
        guard corner && kind.isShelf && w.given else { return fc }
        var s = w.value
        if !w.isBandwidthOrS {
            let q = w.value
            let a = pow(10.0, gain / 40)
            s = 1.0 / ((1.0 / (q * q) - 2.0) / (a + 1.0 / a) + 1.0)
        }
        let factor = pow(10.0, abs(gain) / 80.0 / s)
        return kind == .lowShelf ? fc * factor : fc / factor
    }

    /// The filter at a rate (1.3): off, no width, too steep, flat (a peak or shelf at 0 dB) or above 0.49 x the rate
    /// leave it out; otherwise its section.
    public func design(rate: Double) -> EQDesign {
        guard on else { return EQDesign(outcome: .off) }
        guard let w = playedWidth else { return EQDesign(outcome: .noWidth) }
        if kind.isShelf && w.isBandwidthOrS && EQCookbook.shelfRadicand(gain: gain, s: w.value) <= 0 {
            return EQDesign(outcome: .tooSteep)
        }
        let f0 = Self.f0(fc: fc, gain: gain, kind: kind, corner: corner, width: w)
        if kind.hasGain && gain == 0 { return EQDesign(outcome: .flat, f0: f0) }
        if f0 >= EQLimits.topFraction * rate { return EQDesign(outcome: .above, f0: f0) }
        return EQDesign(outcome: .plays, f0: f0,
                        coefficients: EQCookbook.coefficients(kind, gain: gain, f0: f0, rate: rate, value: w.value,
                                                              isBandwidthOrS: w.isBandwidthOrS))
    }
}

extension EQDesign {
    init(outcome: EQOutcome, f0: Double? = nil) {
        self.init(outcome: outcome, f0: f0, coefficients: nil)
    }
}

/// The ranges (1.3, 3.8, 3.9).
public enum EQLimits {
    /// a filter's Fc, on every output (8, question 14)
    public static let frequency = 1.0...22000.0
    /// a filter's gain, either way
    public static let gain = 30.0
    public static let q = 0.01...100.0
    /// `BW Oct`, in octaves
    public static let bandwidth = 0.01...10.0
    /// a file's `Preamp:`, either way
    public static let filePreamp = 30.0
    /// the preamp set by hand (8, question 18)
    public static let handPreamp = -30.0...12.0
    /// a correction's filters for one ear, as you make it: Add Filter stops here, and no edit takes an ear past it -
    /// or past what a file gave it
    public static let filtersPerEar = 64
    /// what a file may hold for one ear (back-home 15): the most you make and the tone's ten bands, which The Whole
    /// Curve writes as ten more filters - so every export of a correction you made, AutoEq's or a file within the 64
    /// reads back, whatever the tone. An import of one is a correction of up to 74 that the next export adds a tone
    /// to again, so no limit reads back every export: over a Flat tone (the correction alone) one still does.
    public static let importPerEar = 74
    /// the render's sections a channel: a file's 74 and the tone's 10
    public static let sectionsPerChannel = 84
    public static let channels = 8
    /// a filter whose f0 is at or above this fraction of the rate is left out at that rate
    public static let topFraction = 0.49
}

/// The RBJ cookbook as APO's BiQuad.cpp computes it, in its order of operations.
public enum EQCookbook {
    /// `(A + 1/A)(1/S − 1) + 2`: under the root of a shelf's alpha by its S - a shelf too steep for its gain makes it
    /// 0 or less.
    public static func shelfRadicand(gain: Double, s: Double) -> Double {
        let a = pow(10.0, gain / 40)
        return (a + 1 / a) * (1 / s - 1) + 2
    }

    /// The steepest slope (dB an octave) a shelf of this gain can have - the editor's "at most" (3.8); nil when any
    /// slope will do (0 dB).
    public static func steepestSlope(gain: Double) -> Double? {
        let a = pow(10.0, gain / 40)
        let limit = 1 - 2 / (a + 1 / a)
        return limit > 0 ? 12 / limit : nil
    }

    /// The five normalised coefficients of a filter at f0, for a width `value` that is a Q (`isBandwidthOrS`
    /// false), or else a shelf's S or another filter's bandwidth in octaves.
    public static func coefficients(_ kind: EQKind, gain: Double, f0: Double, rate: Double, value: Double,
                                    isBandwidthOrS: Bool) -> EQCoefficients {
        let bigA = kind.hasGain ? pow(10.0, gain / 40) : 1.0
        let omega = 2 * Double.pi * f0 / rate
        let sn = sin(omega)
        let cs = cos(omega)
        let alpha: Double
        if !isBandwidthOrS {
            alpha = sn / (2 * value)
        } else if kind.isShelf {
            alpha = sn / 2 * ((bigA + 1 / bigA) * (1 / value - 1) + 2).squareRoot()
        } else {
            alpha = sn * sinh(log(2.0) / 2 * value * omega / sn)
        }
        let beta = 2 * bigA.squareRoot() * alpha
        let (b0, b1, b2, a0, a1, a2): (Double, Double, Double, Double, Double, Double)
        switch kind {
        case .lowPass:
            (b0, b1, b2, a0, a1, a2) = ((1 - cs) / 2, 1 - cs, (1 - cs) / 2, 1 + alpha, -2 * cs, 1 - alpha)
        case .highPass:
            (b0, b1, b2, a0, a1, a2) = ((1 + cs) / 2, -(1 + cs), (1 + cs) / 2, 1 + alpha, -2 * cs, 1 - alpha)
        case .bandPass:
            (b0, b1, b2, a0, a1, a2) = (alpha, 0.0, -alpha, 1 + alpha, -2 * cs, 1 - alpha)
        case .notch:
            (b0, b1, b2, a0, a1, a2) = (1.0, -2 * cs, 1.0, 1 + alpha, -2 * cs, 1 - alpha)
        case .allPass:
            (b0, b1, b2, a0, a1, a2) = (1 - alpha, -2 * cs, 1 + alpha, 1 + alpha, -2 * cs, 1 - alpha)
        case .peak:
            (b0, b1, b2, a0, a1, a2) = (1 + (alpha * bigA), -2 * cs, 1 - (alpha * bigA),
                                        1 + (alpha / bigA), -2 * cs, 1 - (alpha / bigA))
        case .lowShelf:
            (b0, b1, b2, a0, a1, a2) = (bigA * ((bigA + 1) - (bigA - 1) * cs + beta),
                                        2 * bigA * ((bigA - 1) - (bigA + 1) * cs),
                                        bigA * ((bigA + 1) - (bigA - 1) * cs - beta),
                                        (bigA + 1) + (bigA - 1) * cs + beta,
                                        -2 * ((bigA - 1) + (bigA + 1) * cs),
                                        (bigA + 1) + (bigA - 1) * cs - beta)
        case .highShelf:
            (b0, b1, b2, a0, a1, a2) = (bigA * ((bigA + 1) + (bigA - 1) * cs + beta),
                                        -2 * bigA * ((bigA - 1) + (bigA + 1) * cs),
                                        bigA * ((bigA + 1) + (bigA - 1) * cs - beta),
                                        (bigA + 1) - (bigA - 1) * cs + beta,
                                        2 * ((bigA - 1) - (bigA + 1) * cs),
                                        (bigA + 1) - (bigA - 1) * cs - beta)
        }
        return EQCoefficients(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }
}

/// A section's identity across banks (1.6): a tone band by its place, a correction filter by its own id - two kinds,
/// so a band and a filter never match.
public enum EQSectionID: Hashable, Sendable {
    case band(Int)
    case filter(Int)

    /// As the packed bank keeps it: a band -(i + 1), a filter +id.
    var code: Double {
        switch self {
        case .band(let i): -Double(i + 1)
        case .filter(let id): Double(id)
        }
    }
}

/// A filter made at a rate: what the render runs and the response sums.
public struct EQSection: Equatable, Sendable {
    public var id: EQSectionID
    public var kind: EQKind
    public var f0: Double
    public var coefficients: EQCoefficients

    public init(id: EQSectionID, kind: EQKind, f0: Double, coefficients: EQCoefficients) {
        self.id = id
        self.kind = kind
        self.f0 = f0
        self.coefficients = coefficients
    }
}
