import Foundation

/// Equalizer APO's syntax in AutoEq's shape (eq.md 3.11): what Export writes, and what reads back through
/// `APOReader` to the same filters, bit for bit.
///
/// ```
/// # deadwax EQ for James's AirPods Pro, 2026-11-12
/// Preamp: -7.1 dB
/// Filter 1: ON LSC Fc 105 Hz Gain 2.6 dB Q 0.70
/// Filter 11: ON PK Fc 31.25 Hz Gain 5.0 dB Q 1.41
/// ```
///
/// Numbers in AutoEq's decimals - Fc whole hertz, Gain one, Q two - and more where the value needs them to read back
/// the same: Swift's shortest round-trip digits, trailing zeros trimmed to that minimum. Never a comma, never an
/// exponent. And an Fc is never five or more characters with a point fourth from its end - APO reads that as
/// thousands, so `12.345` is written `12.3450`.
public enum APOWriter {
    /// The whole curve's filters (3.11): the correction's by frequency (in their order where two share one), then the
    /// tone's bands that aren't at 0, as `PK … Q 1.41` for both ears. The correction alone is `bands: nil`.
    public static func curve(correction: [EQFilter], bands: [Double]?) -> [EQFilter] {
        var out = correction.enumerated().sorted {
            $0.element.fc < $1.element.fc || ($0.element.fc == $1.element.fc && $0.offset < $1.offset)
        }.map(\.element)
        for (band, gain) in (bands ?? []).enumerated() where gain != 0 {
            out.append(EQGraphic.filter(band: band, gain: gain))
        }
        return out
    }

    /// A file: the comments (each a `#` line), the preamp - shared, and each ear's offset - and the filters, numbered
    /// from 1. Per ear (a filter or a preamp for one ear only): `Channel: all` and the shared filters, then
    /// `Channel: L` and the left's (its `Preamp:` offset first, when it has one), then `Channel: R`.
    public static func write(filters: [EQFilter], preamp: EQPreampParts, comments: [String] = []) -> String {
        var lines = comments.map { "# " + $0.map { $0 == "\n" || $0 == "\r" || $0 == "\r\n" ? " " : String($0) }.joined() }
        lines.append("Preamp: \(decibels(preamp.all)) dB")
        var n = 0
        func add(_ f: EQFilter) {
            n += 1
            lines.append(line(f, number: n))
        }
        let perEar = preamp.perEar || filters.contains { $0.channel != .all }
        if !perEar {
            filters.forEach(add)
        } else {
            lines.append("Channel: all")
            filters.filter { $0.channel == .all }.forEach(add)
            for (ear, name) in [(EQChannel.left, "L"), (.right, "R")] {
                lines.append("Channel: \(name)")
                let offset = preamp.offset(ear)
                if offset != 0 { lines.append("Preamp: \(decibels(offset)) dB") }
                filters.filter { $0.channel == ear }.forEach(add)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One filter: `Filter 3: ON PK Fc 105 Hz Gain 2.6 dB Q 0.70` - its type as written, a shelf's slope straight
    /// after it, a gain where the type plays one (and a band pass's when it has one, as APO reads it).
    public static func line(_ f: EQFilter, number n: Int) -> String {
        var out = "Filter \(n): \(f.on ? "ON" : "OFF") \(f.written)"
        if f.kind.isShelf, case .slope(let s)? = f.width { out += " \(number(s, decimals: 0)) dB" }
        out += " Fc \(frequency(f.fc)) Hz"
        if f.kind.hasGain || (f.kind == .bandPass && f.gain != 0) { out += " Gain \(number(f.gain, decimals: 1)) dB" }
        switch f.width {
        case .q(let q)?: out += " Q \(number(q, decimals: 2))"
        case .bandwidth(let b)? where !f.kind.isShelf: out += " BW Oct \(number(b, decimals: 2))"
        default: break
        }
        return out
    }

    /// A preamp: one decimal at least, and never "-0.0" (the automatic preamp of a flat curve is -0).
    static func decibels(_ x: Double) -> String { number(x == 0 ? 0 : x, decimals: 1) }

    /// An Fc: whole hertz at least, and a trailing zero where APO would read it as thousands.
    public static func frequency(_ fc: Double) -> String {
        let t = number(fc, decimals: 0)
        let s = Array(t)
        return s.count >= 5 && s[s.count - 4] == "." ? t + "0" : t
    }

    /// The shortest digits that read back as `x`, as a plain decimal, with at least `decimals` after the point.
    public static func number(_ x: Double, decimals: Int) -> String {
        guard x.isFinite else { return x.description }
        var (whole, fraction) = plain(x.description)
        while fraction.hasSuffix("0") { fraction.removeLast() }
        while fraction.count < decimals { fraction += "0" }
        return fraction.isEmpty ? whole : whole + "." + fraction
    }

    /// Swift's description ("1e-05", "1.25e+20", "105.0") as a sign and whole part, and the digits after the point.
    static func plain(_ text: String) -> (String, String) {
        var t = text
        var sign = ""
        if t.hasPrefix("-") {
            sign = "-"
            t.removeFirst()
        }
        var exponent = 0
        if let e = t.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            exponent = Int(t[t.index(after: e)...].replacingOccurrences(of: "+", with: "")) ?? 0
            t = String(t[..<e])
        }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        var digits = String(parts[0]) + (parts.count > 1 ? String(parts[1]) : "")
        var point = parts[0].count + exponent
        if point <= 0 {
            digits = String(repeating: "0", count: 1 - point) + digits
            point = 1
        }
        if point > digits.count { digits += String(repeating: "0", count: point - digits.count) }
        var whole = String(digits.prefix(point))
        while whole.count > 1 && whole.hasPrefix("0") { whole.removeFirst() }
        return (sign + whole, String(digits.dropFirst(point)))
    }
}
