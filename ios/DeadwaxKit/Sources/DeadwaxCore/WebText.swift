import Foundation

/// A number as JavaScript's `toFixed(digits)` writes it - which is NOT printf's `%.Nf`. Both round the
/// number's exact binary value, but at an exact tie JS takes the larger digits (it formats |x|: away from zero)
/// where printf takes the even ones. Gains are hundredths, so ties are common: (0.25).toFixed(1) is "0.3" (printf
/// "0.2"), (2.25).toFixed(1) "2.3", (0.125).toFixed(2) "0.13", (10.25).toFixed(1) "10.3". Every word the web
/// writes with toFixed is written with this here (Fixtures/levels/levels-vectors.json `toFixed` holds it to
/// Node's own answers). A negative value is "-" and its magnitude's digits, as JS writes it ("-0.00" included).
public func jsFixed(_ value: Double, _ digits: Int) -> String {
    if value < 0 { return "-" + jsFixed(-value, digits) }
    guard value.isFinite else { return value.isNaN ? "NaN" : "Infinity" }
    let places = max(0, min(digits, 100))
    //? printf writes the exact binary value to as many places as asked: a tie is digit `places + 1` a 5 and
    //? nothing but zeros after it (a double this side of 1e21 has under 1100 significant places; 30 more than
    //? asked is enough for every value a word is made of, and an exact tie is all that needs telling apart)
    let exact = String(format: "%.\(places + 30)f", value)
    if let point = exact.firstIndex(of: ".") {
        let after = exact[exact.index(after: point)...]
        let tail = after.dropFirst(places)
        if tail.first == "5" && tail.dropFirst().allSatisfy({ $0 == "0" }) {
            return String(format: "%.\(places)f", value.nextUp)
        }
    }
    return String(format: "%.\(places)f", value)
}

/// The few JavaScript behaviours the web's words lean on, kept to JavaScript's own rules so a port says what
/// the web says to the character.
enum WebText {
    /// `String.prototype.trim`: JS's white space and line terminators, which aren't Foundation's
    /// `.whitespacesAndNewlines` (JS trims U+FEFF and not U+0085).
    static func trim(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !isSpace($0) }) else { return "" }
        let last = scalars.lastIndex(where: { !isSpace($0) })!
        return String(scalars[first...last])
    }

    static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// JS string equality (`===`): the same UTF-16 code units. Swift's `==` treats canonically equivalent
    /// strings as equal, which the web's comparisons and Sets don't.
    static func same(_ a: String, _ b: String) -> Bool {
        a.utf16.elementsEqual(b.utf16)
    }

    /// `[...new Set(values)]`: each value once, the first kept, in order - by JS's equality.
    static func unique(_ values: [String]) -> [String] {
        var seen = Set<[UInt16]>()
        return values.filter { seen.insert(Array($0.utf16)).inserted }
    }

    /// `Math.round`: halves up (towards +infinity), and 0.49999999999999994 down, as JS does it.
    static func round(_ value: Double) -> Double {
        let floor = value.rounded(.down)
        return value - floor >= 0.5 ? floor + 1 : floor
    }

    /// `Number.isInteger(value) && value > 0` - the value when it holds, else nil.
    static func whole(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value > 0, value == value.rounded(.towardZero), value < 9_007_199_254_740_992 else { return nil }
        return Int(value)
    }

    /// A number as JS's `String(n)` writes the ones the words use: whole numbers without a ".0", the rest
    /// as the shortest decimal that reads back the same (Swift's description; the same digits as JS's for
    /// every value from 1e-4 up to 1e16, the range a rate or a disc number is in).
    static func number(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(.towardZero), abs(value) < 1e16 {
            return value == 0 ? "0" : String(Int64(value))
        }
        return "\(value)"
    }

    /// Python's `round(x, places)` for a float: correctly rounded to that many decimal places, the exact tie
    /// to the even digit - which is what printf's `%.Nf` does with the value's exact binary expansion.
    static func pythonRound(_ value: Double, _ places: Int) -> Double {
        guard value.isFinite else { return value }
        return Double(String(format: "%.\(places)f", value)) ?? value
    }

    /// The part of a string before its first `;`, as JS's `split(';')[0]`.
    static func beforeSemicolon(_ text: String) -> String {
        text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    }

    /// JS `String.prototype.slice(0, count)`: the first `count` UTF-16 code units.
    static func prefix(_ text: String, _ count: Int) -> String {
        String(decoding: Array(text.utf16.prefix(count)), as: UTF16.self)
    }

    /// `/^\d{4}$/`: four ASCII digits and nothing else.
    static func fourDigits(_ text: String) -> Bool {
        text.utf16.count == 4 && text.utf16.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }
}
