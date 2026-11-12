#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The transcendental functions the turntable's ports call, behind one protocol (notes/ios-specs/turntable.md, 4.2).
///
/// The web's arithmetic is IEEE doubles and Float32 stores in a fixed order, which Swift reproduces exactly; the only
/// answers that differ between engines are these functions', which V8 computes with its own fdlibm-derived code and a
/// phone with Apple's libm. So every exp, log, sin, cos, atan2, hypot, pow and log10 the voice, the platter, the
/// geometry, the speed and the deck's rules evaluate goes through a `DeckMaths`: `PlatformMaths` in the app, and in
/// the tests `RecordedMaths`, which answers with what V8 answered to each call the web's traces made - so a port that
/// replays a trace through it must come out bit for bit the web's (the spec's test A).
///
/// Every type that computes with it is generic over it, and the render's entry (slice 2) is a concrete function over
/// `PlatformMaths`, so the protocol costs nothing where it runs.
public protocol DeckMaths {
    func exp(_ x: Double) -> Double
    func log(_ x: Double) -> Double
    func sin(_ x: Double) -> Double
    func cos(_ x: Double) -> Double
    func atan2(_ y: Double, _ x: Double) -> Double
    func hypot(_ a: Double, _ b: Double) -> Double
    func pow(_ base: Double, _ exponent: Double) -> Double
    func log10(_ x: Double) -> Double
}

/// The platform's own functions (Darwin's libm on a phone, glibc's on Linux), with JavaScript's meaning where C's
/// differs: `pow(1, NaN)` and `pow(±1, ±Infinity)` are NaN in JavaScript and 1 in C.
public struct PlatformMaths: DeckMaths, Sendable {
    public init() {}
    @inlinable public func exp(_ x: Double) -> Double { cExp(x) }
    @inlinable public func log(_ x: Double) -> Double { cLog(x) }
    @inlinable public func sin(_ x: Double) -> Double { cSin(x) }
    @inlinable public func cos(_ x: Double) -> Double { cCos(x) }
    @inlinable public func atan2(_ y: Double, _ x: Double) -> Double { cAtan2(y, x) }
    @inlinable public func hypot(_ a: Double, _ b: Double) -> Double {
        //? Math.hypot: Infinity when either is infinite, NaN otherwise when either is NaN - as C99's hypot
        cHypot(a, b)
    }
    @inlinable public func pow(_ base: Double, _ exponent: Double) -> Double {
        if exponent.isNaN { return .nan }
        if exponent.isInfinite && Swift.abs(base) == 1 { return .nan }
        return cPow(base, exponent)
    }
    @inlinable public func log10(_ x: Double) -> Double { cLog10(x) }
}

//? at file scope, where `exp` is the C function rather than the protocol's method
@usableFromInline func cExp(_ x: Double) -> Double { exp(x) }
@usableFromInline func cLog(_ x: Double) -> Double { log(x) }
@usableFromInline func cSin(_ x: Double) -> Double { sin(x) }
@usableFromInline func cCos(_ x: Double) -> Double { cos(x) }
@usableFromInline func cAtan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) }
@usableFromInline func cHypot(_ a: Double, _ b: Double) -> Double { hypot(a, b) }
@usableFromInline func cPow(_ a: Double, _ b: Double) -> Double { pow(a, b) }
@usableFromInline func cLog10(_ x: Double) -> Double { log10(x) }

/// Which function a recorded call was - its number in the hash of a run's calls (export-deck-vectors.cjs RECORDED).
public enum DeckMathsFunction: UInt8, CaseIterable, Sendable {
    case exp = 0, log, sin, cos, atan2, hypot, pow, log10
}

/// The web's own answers, replayed: every call the exported traces made, by its function and its inputs' bits
/// (Fixtures/deck/maths.json). A call the web never made answers NaN and is counted in `missed` - the test fails on
/// any - and every call is counted and hashed in order (FNV-1a over the function's number and each input's
/// little-endian bytes, as the exporter hashes V8's), so a run that asks the same things in another order, or asks
/// more or fewer, is told apart from the web's run.
public final class RecordedMaths: DeckMaths {
    public struct Call: Hashable, Sendable {
        public let function: DeckMathsFunction
        public let a: UInt64
        public let b: UInt64
        public init(_ function: DeckMathsFunction, _ a: UInt64, _ b: UInt64 = 0) {
            self.function = function
            self.a = a
            self.b = b
        }
    }

    private let answers: [Call: UInt64]
    /// Calls the web never made, as asked.
    public private(set) var missed: [Call] = []
    /// How many calls since the last `restart()`, and the hash of them in order.
    public private(set) var calls = 0
    public private(set) var hash: UInt64 = RecordedMaths.fnvStart

    public static let fnvStart: UInt64 = 0xcbf2_9ce4_8422_2325
    public static let fnvPrime: UInt64 = 0x0000_0100_0000_01b3

    public init(answers: [Call: UInt64]) {
        self.answers = answers
    }

    /// Start counting and hashing a new run.
    public func restart() {
        calls = 0
        hash = Self.fnvStart
    }

    private func note(_ call: Call, inputs: Int) {
        calls += 1
        var h = hash
        h = (h ^ UInt64(call.function.rawValue)) &* Self.fnvPrime
        for value in inputs == 2 ? [call.a, call.b] : [call.a] {
            for shift in stride(from: 0, to: 64, by: 8) {
                h = (h ^ ((value >> UInt64(shift)) & 0xff)) &* Self.fnvPrime
            }
        }
        hash = h
    }

    private func answer(_ call: Call, inputs: Int) -> Double {
        note(call, inputs: inputs)
        guard let bits = answers[call] else {
            missed.append(call)
            return .nan
        }
        return Double(bitPattern: bits)
    }

    public func exp(_ x: Double) -> Double { answer(Call(.exp, x.bitPattern), inputs: 1) }
    public func log(_ x: Double) -> Double { answer(Call(.log, x.bitPattern), inputs: 1) }
    public func sin(_ x: Double) -> Double { answer(Call(.sin, x.bitPattern), inputs: 1) }
    public func cos(_ x: Double) -> Double { answer(Call(.cos, x.bitPattern), inputs: 1) }
    public func atan2(_ y: Double, _ x: Double) -> Double { answer(Call(.atan2, y.bitPattern, x.bitPattern), inputs: 2) }
    public func hypot(_ a: Double, _ b: Double) -> Double { answer(Call(.hypot, a.bitPattern, b.bitPattern), inputs: 2) }
    public func pow(_ base: Double, _ exponent: Double) -> Double { answer(Call(.pow, base.bitPattern, exponent.bitPattern), inputs: 2) }
    public func log10(_ x: Double) -> Double { answer(Call(.log10, x.bitPattern), inputs: 1) }
}

/// The JavaScript number rules the ports lean on, as JavaScript has them (the spec's 4.2) - held to Node's own
/// answers by Fixtures/deck/jsmath.json. These are rules, not style: a Swift `rounded()`, `min` or `max` in their
/// place would round or choose differently on exactly the inputs the web's traces can hold.
public enum JSMath {
    /// `Math.round`: to the nearest integer, a half towards +infinity - as the spec of Math.round reads, so exact for
    /// every double: 0.49999999999999994 rounds to 0 (where `(x + 0.5).rounded(.down)` gives 1), 2^52 - 0.5 to 2^52,
    /// -0.5 and -0 to -0; NaN and the infinities pass through.
    @inlinable public static func round(_ x: Double) -> Double {
        let r = x.rounded(.up)
        return r - 0.5 > x ? r - 1 : r
    }

    /// `Math.min(a, b)`: NaN when either is, and -0 below +0 - not Swift's `min`, which picks by `<` alone.
    @inlinable public static func min(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN { return .nan }
        if a == b { return a.sign == .minus ? a : b }
        return a < b ? a : b
    }

    /// `Math.max(a, b)`: NaN when either is, and +0 above -0.
    @inlinable public static func max(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN { return .nan }
        if a == b { return a.sign == .minus ? b : a }
        return a > b ? a : b
    }

    /// `Math.fround`: the nearest Float32, read back as a double - what a store into a Float32Array keeps.
    @inlinable public static func fround(_ x: Double) -> Double {
        Double(Float(x))
    }

    /// ToInt32 - what `x | 0` and `x & mask` make of a number: NaN and the infinities 0, else truncated and taken
    /// modulo 2^32 as a signed integer.
    @inlinable public static func toInt32(_ x: Double) -> Int32 {
        guard x.isFinite else { return 0 }
        let whole = x.rounded(.towardZero).truncatingRemainder(dividingBy: 4_294_967_296)
        let unsigned = whole < 0 ? whole + 4_294_967_296 : whole
        return Int32(bitPattern: UInt32(unsigned))
    }

    /// `Math.sign`: -1, 1, or the zero or NaN it was given.
    @inlinable public static func sign(_ x: Double) -> Double {
        x > 0 ? 1 : x < 0 ? -1 : x
    }

    /// A number as `||` reads it: anything but 0, -0 and NaN.
    @inlinable public static func truthy(_ x: Double) -> Bool {
        x != 0 && !x.isNaN
    }
}
