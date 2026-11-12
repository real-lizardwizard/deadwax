import Foundation

/// A point of a `GraphicEQ:` line: a frequency and its gain.
public struct GraphicEQPoint: Equatable, Sendable {
    public var frequency: Double
    public var gain: Double

    public init(_ frequency: Double, _ gain: Double) {
        self.frequency = frequency
        self.gain = gain
    }
}

/// A `GraphicEQ:` curve as filters (eq.md 3.10, James's decision) - close to it, not exact, and said in numbers:
/// pure and deterministic.
///
/// 1. The target: each line's points linear on a log-frequency axis, flat outside them (APO's GainIterator.cpp);
///    several lines add up.
/// 2. Its level: the median over 20 Hz-20 kHz, which becomes the correction's own preamp - the filters fit the shape.
/// 3. 61 peaks at 1/6-octave centres (`1000 · 2^(k/6)`, k = -34 … 26, rounded to whole hertz), Q 4.32, their gains
///    solved together by Gauss-Newton on the 1/48-octave grid from 20 Hz to 21 kHz at 48 kHz, from zero:
///    `(JᵀJ / n + λI) Δ = -(Jᵀr / n + λg)`, λ = 1e-4, the Jacobian by central differences of 0.001 dB, until no gain
///    moves by more than 0.001 dB or 50 rounds, gains held within ±30 dB; then rounded to 0.1 dB (half away from
///    zero), and a band at 0 dropped.
/// 4. Its fit, after rounding, on the same grid: the mean, RMS and largest difference up to 16 kHz, and the largest
///    above it with where - at 48 kHz, and at 44.1 kHz for the record.
///
/// ios/scripts/make-eq-fixtures.py solves the same in NumPy (Fixtures/eq/graphic.json).
public enum GraphicEQFit {
    public static let q = 4.32
    public static let rate = 48000.0
    public static let lambda = 1e-4
    public static let step = 1e-3

    /// The 61 centres, 20 Hz to 20.2 kHz, as an export writes them.
    public static let centres: [Double] = (-34...26).map { (1000 * pow(2.0, Double($0) / 6)).rounded() }

    /// Every 1/48 octave from 20 Hz to 21 kHz.
    public static func grid() -> [Double] {
        var out: [Double] = []
        var k = 0
        while 20 * pow(2.0, Double(k) / 48) <= 21000 {
            out.append(20 * pow(2.0, Double(k) / 48))
            k += 1
        }
        return out
    }

    /// The lines' summed curve at each frequency.
    public static func target(_ lines: [[GraphicEQPoint]], at frequencies: [Double]) -> [Double] {
        frequencies.map { (f: Double) -> Double in
            var total = 0.0
            for points in lines where !points.isEmpty {
                var j = 0
                while j < points.count && points[j].frequency < f { j += 1 }
                if j == 0 {
                    total += points[0].gain
                } else if j == points.count {
                    total += points[points.count - 1].gain
                } else {
                    let left = points[j - 1]
                    let right = points[j]
                    if left.gain == right.gain {
                        total += left.gain
                    } else {
                        let logLeft = log(left.frequency)
                        let t = (log(f) - logLeft) / (log(right.frequency) - logLeft)
                        total += left.gain + t * (right.gain - left.gain)
                    }
                }
            }
            return total
        }
    }

    /// The middle value; of an even count, the mean of the middle two.
    public static func median(_ values: [Double]) -> Double {
        let ordered = values.sorted()
        let n = ordered.count
        return n % 2 == 1 ? ordered[n / 2] : (ordered[n / 2 - 1] + ordered[n / 2]) / 2
    }

    /// How close the rounded filters come to the target.
    public struct Stats: Equatable, Sendable {
        /// up to 16 kHz
        public var mean: Double
        public var rms: Double
        public var largest: Double
        /// the largest above 16 kHz, and where
        public var above: Double
        public var aboveAt: Double
    }

    public struct Result: Equatable, Sendable {
        public var centres: [Double]
        /// the target's median over 20 Hz-20 kHz: the correction's own preamp
        public var median: Double
        /// on the grid, less the median
        public var target: [Double]
        public var unrounded: [Double]
        public var rounded: [Double]
        public var rounds: Int
        public var stats48000: Stats
        public var stats44100: Stats

        /// The filters that change something: peaks at the centres with their rounded gains, Q 4.32.
        public var kept: Int { rounded.filter { $0 != 0 }.count }

        public func filters(channel: EQChannel, firstID: Int) -> [EQFilter] {
            var out: [EQFilter] = []
            for (centre, gain) in zip(centres, rounded) where gain != 0 {
                out.append(EQFilter(id: firstID + out.count, kind: .peak, written: "PK", fc: centre, gain: gain,
                                    width: .q(GraphicEQFit.q), channel: channel))
            }
            return out
        }
    }

    static func peakDB(_ fc: Double, _ gain: Double, _ trig: [EQResponse.Trig], rate: Double) -> [Double] {
        let c = EQCookbook.coefficients(.peak, gain: gain, f0: fc, rate: rate, value: q, isBandwidthOrS: false)
        return trig.map { EQResponse.db(c, $0) }
    }

    public static func fit(_ lines: [[GraphicEQPoint]]) -> Result {
        let grid = grid()
        let n = grid.count
        let trig = grid.map { EQResponse.Trig(frequency: $0, rate: rate) }
        let level = median(target(lines, at: grid.filter { $0 <= 20000 }))
        let goal = target(lines, at: grid).map { $0 - level }
        let m = centres.count
        var gains = [Double](repeating: 0, count: m)
        var rounds = 0
        for round in 1...50 {
            rounds = round
            var model = [Double](repeating: 0, count: n)
            var columns: [[Double]] = []
            columns.reserveCapacity(m)
            for (c, g) in zip(centres, gains) {
                let here = peakDB(c, g, trig, rate: rate)
                for k in 0..<n { model[k] = model[k] + here[k] }
                let up = peakDB(c, g + step, trig, rate: rate)
                let down = peakDB(c, g - step, trig, rate: rate)
                columns.append((0..<n).map { (up[$0] - down[$0]) / (2 * step) })
            }
            let residual = (0..<n).map { model[$0] - goal[$0] }
            var normal = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
            var rhs = [Double](repeating: 0, count: m)
            for i in 0..<m {
                for j in i..<m {
                    var sum = 0.0
                    for k in 0..<n { sum += columns[i][k] * columns[j][k] }
                    normal[i][j] = sum / Double(n)
                    normal[j][i] = normal[i][j]
                }
                normal[i][i] += lambda
                var sum = 0.0
                for k in 0..<n { sum += columns[i][k] * residual[k] }
                rhs[i] = -(sum / Double(n) + lambda * gains[i])
            }
            let delta = solve(normal, rhs)
            var moved = 0.0
            for i in 0..<m {
                let to = min(max(gains[i] + delta[i], -30), 30)
                moved = max(moved, abs(to - gains[i]))
                gains[i] = to
            }
            if moved <= 0.001 { break }
        }
        let rounded = gains.map { ($0 * 10).rounded() / 10 }

        func stats(_ at: Double) -> Stats {
            let trigAt = grid.map { EQResponse.Trig(frequency: $0, rate: at) }
            var model = [Double](repeating: 0, count: n)
            for (c, g) in zip(centres, rounded) where g != 0 {
                let here = peakDB(c, g, trigAt, rate: at)
                for k in 0..<n { model[k] = model[k] + here[k] }
            }
            var low: [Double] = []
            var above = -Double.infinity
            var aboveAt = 0.0
            for k in 0..<n {
                let diff = abs(model[k] - goal[k])
                if grid[k] <= 16000 {
                    low.append(diff)
                } else if diff > above {
                    above = diff
                    aboveAt = grid[k]
                }
            }
            let mean = low.reduce(0, +) / Double(low.count)
            let rms = (low.map { $0 * $0 }.reduce(0, +) / Double(low.count)).squareRoot()
            return Stats(mean: mean, rms: rms, largest: low.max() ?? 0, above: above, aboveAt: aboveAt)
        }
        return Result(centres: centres, median: level, target: goal, unrounded: gains, rounded: rounded, rounds: rounds,
                      stats48000: stats(48000), stats44100: stats(44100))
    }

    /// `a x = b` by Gaussian elimination with partial pivoting (what NumPy's solve does, LAPACK's gesv).
    static func solve(_ a: [[Double]], _ b: [Double]) -> [Double] {
        var a = a
        var b = b
        let n = b.count
        for col in 0..<n {
            var pivot = col
            for row in (col + 1)..<max(n, col + 1) where abs(a[row][col]) > abs(a[pivot][col]) { pivot = row }
            if pivot != col {
                a.swapAt(pivot, col)
                b.swapAt(pivot, col)
            }
            let p = a[col][col]
            guard p != 0 else { continue }
            for row in (col + 1)..<max(n, col + 1) {
                let factor = a[row][col] / p
                if factor == 0 { continue }
                for k in col..<n { a[row][k] -= factor * a[col][k] }
                b[row] -= factor * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<max(n, row + 1) { sum -= a[row][k] * x[k] }
            x[row] = a[row][row] == 0 ? 0 : sum / a[row][row]
        }
        return x
    }
}
