import Foundation

/// The curve's response (eq.md 1.4) - the one formula for "what the curve does": each section's
/// `|b0 + b1 z⁻¹ + b2 z⁻²| / |1 + a1 z⁻¹ + a2 z⁻²|` at `z = e^{jw}`, in dB, summed. Evaluated directly from
/// `cos w`, `sin w`, `cos 2w` and `sin 2w`: within 4e-7 dB of 50-digit arithmetic over every case of
/// Fixtures/eq/filters.json (AutoEq's peq.py form, through `4 sin²(w/2)`, loses up to 0.007 dB at 20 Hz, Q 100 and
/// 176.4 kHz - measured by the fixture script). The screen's curve, the preamp's top and the fixtures' `freqz` are
/// all this.
public enum EQResponse {
    /// `cos w, sin w, cos 2w, sin 2w` at one frequency, `w = 2π f / rate`.
    public struct Trig: Sendable {
        public let c1: Double
        public let s1: Double
        public let c2: Double
        public let s2: Double

        public init(frequency: Double, rate: Double) {
            let w = 2 * Double.pi * frequency / rate
            c1 = cos(w)
            s1 = sin(w)
            c2 = cos(2 * w)
            s2 = sin(2 * w)
        }
    }

    /// One section's dB (a numerator of exactly 0, a notch's own frequency, is -inf).
    public static func db(_ c: EQCoefficients, _ t: Trig) -> Double {
        let nr = c.b0 + c.b1 * t.c1 + c.b2 * t.c2
        let ni = c.b1 * t.s1 + c.b2 * t.s2
        let dr = 1 + c.a1 * t.c1 + c.a2 * t.c2
        let di = c.a1 * t.s1 + c.a2 * t.s2
        return 10 * log10(nr * nr + ni * ni) - 10 * log10(dr * dr + di * di)
    }

    public static func db(_ c: EQCoefficients, at frequency: Double, rate: Double) -> Double {
        db(c, Trig(frequency: frequency, rate: rate))
    }

    /// The sum of the sections' dB at one frequency, from `offset` (a level in dB), in the sections' order.
    public static func db(_ sections: [EQCoefficients], at frequency: Double, rate: Double, offset: Double = 0) -> Double {
        let t = Trig(frequency: frequency, rate: rate)
        var total = offset
        for c in sections { total = total + db(c, t) }
        return total
    }

    public static func curve(_ sections: [EQCoefficients], at frequencies: [Double], rate: Double,
                             offset: Double = 0) -> [Double] {
        frequencies.map { db(sections, at: $0, rate: rate, offset: offset) }
    }

    /// 1.4's grid: every 1/48 octave from 10 Hz to just below Nyquist (DC and Nyquist are the top's own points).
    public static func grid(rate: Double) -> [Double] {
        var out: [Double] = []
        var k = 0
        while true {
            let f = 10 * pow(2.0, Double(k) / 48)
            if f >= rate / 2 { return out }
            out.append(f)
            k += 1
        }
    }

    /// One channel's curve, for the top: its sections and its level in dB.
    public struct Ear: Sendable {
        public var sections: [EQSection]
        public var offset: Double

        public init(sections: [EQSection], offset: Double = 0) {
            self.sections = sections
            self.offset = offset
        }
    }

    /// The curve's top over every ear (1.4), and the point it was found beside: the curve at DC, the grid, each
    /// section's f0 and Nyquist; then each local maximum among those points refined by 80 rounds of golden-section
    /// search on log frequency between its two neighbours (a neighbour at DC: half the point's frequency). Without
    /// `refined`, the points alone (what the review measured falling short).
    public static func top(_ ears: [Ear], rate: Double, refined: Bool = true) -> (db: Double, at: Double) {
        var set: Set<Double> = [0, rate / 2]
        for f in grid(rate: rate) { set.insert(f) }
        for ear in ears {
            for s in ear.sections where s.f0 > 0 && s.f0 < rate / 2 { set.insert(s.f0) }
        }
        let points = set.sorted()
        var best = -Double.infinity
        var bestAt = 0.0
        for ear in ears {
            let sections = ear.sections.map(\.coefficients)
            let values = curve(sections, at: points, rate: rate, offset: ear.offset)
            for (i, v) in values.enumerated() {
                if (i > 0 && v < values[i - 1]) || (i + 1 < values.count && v < values[i + 1]) { continue }
                var here = v
                if refined && i > 0 && i < points.count - 1 {
                    let lo = points[i - 1] > 0 ? points[i - 1] : points[i] / 2
                    here = max(here, refine(sections, rate: rate, offset: ear.offset, lo: lo, hi: points[i + 1]))
                }
                if here > best {
                    best = here
                    bestAt = points[i]
                }
            }
        }
        return (best, bestAt)
    }

    /// The largest of the curve between two frequencies: 80 rounds of golden-section search on log frequency -
    /// deterministic, to well under 1e-6 dB.
    static func refine(_ sections: [EQCoefficients], rate: Double, offset: Double, lo: Double, hi: Double) -> Double {
        let golden = ((5.0).squareRoot() - 1) / 2
        func at(_ u: Double) -> Double { db(sections, at: exp(u), rate: rate, offset: offset) }
        var a = log(lo)
        var b = log(hi)
        var c = b - golden * (b - a)
        var d = a + golden * (b - a)
        var fc = at(c)
        var fd = at(d)
        var best = max(fc, fd)
        for _ in 0..<80 {
            if fc >= fd {
                b = d
                d = c
                fd = fc
                c = b - golden * (b - a)
                fc = at(c)
            } else {
                a = c
                c = d
                fc = fd
                d = a + golden * (b - a)
                fd = at(d)
            }
            best = max(best, max(fc, fd))
        }
        return best
    }
}
