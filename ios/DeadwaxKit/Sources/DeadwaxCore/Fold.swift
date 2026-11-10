import Foundation

/// Names folded as the web app folds them (ui/src/lib/owned.ts `foldName`, ui/src/lib/shelves.ts `findText`), scalar
/// for scalar, so the Library's sorts, headers and Find answer on the phone exactly as they do on the web:
///
/// 1. NFKD (compatibility decomposition: ligatures, fullwidth, superscripts, Roman numerals, Hangul as jamo);
/// 2. every mark (Mn, Mc, Me) out;
/// 3. JavaScript's `toLowerCase`: each scalar's full lowercase mapping, and a capital sigma ending a word as `ς`
///    (Final_Sigma) - `String.lowercased()` never makes one;
/// 4. `key` only: a bracketed aside - an opener `(` or `[` up to the first `)` or `]` after it, either kind - as a
///    space (an opener with no closer after it stays);
/// 5. `&` as " and ", then every run of scalars that aren't letters or numbers (L*, N*) as one space;
/// 6. trimmed, then `key` only: a leading "the " once.
///
/// And compared as JavaScript compares strings - by UTF-16 code unit (`FoldKey`), never by Swift's `<`, which
/// compares canonically (NFKD's Hangul jamo against composed syllables) and so orders other scripts otherwise.
/// Verified against the compiled TypeScript by Tests/DeadwaxCoreTests/Fixtures/library (ios/scripts/
/// export-library-vectors.cjs writes them).
public enum Fold {
    /// `foldName`: what the sorts and headers compare.
    public static func key(_ name: String?) -> String { fold(name, comparing: true) }

    /// `findText`: what Find matches - the same folding, keeping a bracketed aside and a leading "The", which are
    /// words a person types to find an album.
    public static func findText(_ name: String?) -> String { fold(name, comparing: false) }

    /// The `#` header: what no letter heads.
    public static let otherInitial = "#"

    /// `initialOf`: a fold key's group - its first UTF-16 unit `a`...`z` as a capital, anything else (the empty key
    /// too) `#`.
    public static func initial(of key: String) -> String {
        guard let first = key.utf16.first, first >= 0x61, first <= 0x7A else { return otherInitial }
        return String(Character(Unicode.Scalar(UInt8(first - 0x20))))
    }

    static func fold(_ name: String?, comparing: Bool) -> String {
        var scalars = Array((name ?? "").decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !isMark($0) })
        scalars = JSText.lowercased(scalars)
        if comparing { scalars = dropAsides(scalars) }
        var out = String.UnicodeScalarView()
        var spaced = false
        func gap() {
            if !spaced { out.append(" "); spaced = true }
        }
        for scalar in scalars {
            if scalar == "&" {
                gap()
                out.append(contentsOf: "and".unicodeScalars)
                spaced = false
                gap()
            } else if isLetterOrNumber(scalar) {
                out.append(scalar)
                spaced = false
            } else {
                gap()
            }
        }
        //? only letters, numbers and single spaces are left: trimming spaces is all JS's trim() can do here
        var text = Substring(String(out)).unicodeScalars
        while text.first == " " { text = text.dropFirst() }
        while text.last == " " { text = text.dropLast() }
        if comparing && text.starts(with: "the ".unicodeScalars) { text = text.dropFirst(4) }
        return String(String.UnicodeScalarView(text))
    }

    static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    static func isLetterOrNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
    }

    /// `/\s*[([][^)\]]*[)\]]/g` as one space each (the leading `\s*` changes nothing once runs of spaces are one).
    static func dropAsides(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(scalars.count)
        var at = 0
        while at < scalars.count {
            if scalars[at] == "(" || scalars[at] == "[",
               let close = scalars[(at + 1)...].firstIndex(where: { $0 == ")" || $0 == "]" }) {
                out.append(" ")
                at = close + 1
            } else {
                out.append(scalars[at])
                at += 1
            }
        }
        return out
    }
}

/// A fold key as JavaScript compares strings: by UTF-16 code unit, equal only when every unit is.
public struct FoldKey: Comparable, Hashable, Sendable {
    public let units: [UInt16]

    public init(_ text: String) { units = Array(text.utf16) }

    public init(units: [UInt16]) { self.units = units }

    public static func < (a: FoldKey, b: FoldKey) -> Bool { a.units.lexicographicallyPrecedes(b.units) }

    /// The key's header: `Fold.initial(of:)`.
    public var initial: String {
        guard let first = units.first, first >= 0x61, first <= 0x7A else { return Fold.otherInitial }
        return String(Character(Unicode.Scalar(UInt8(first - 0x20))))
    }

    /// Whether `word` is in this text as a run of code units, as JavaScript's `includes` finds it - not whole
    /// Characters, as `String.contains` does (which wouldn't find "바" in "방탄", as jamo).
    public func contains(_ word: FoldKey) -> Bool { Self.contains(units, word.units) }

    static func contains(_ hay: [UInt16], _ needle: [UInt16]) -> Bool {
        if needle.isEmpty { return true }
        if needle.count > hay.count { return false }
        let first = needle[0]
        for start in 0...(hay.count - needle.count) where hay[start] == first {
            if hay[start..<(start + needle.count)].elementsEqual(needle) { return true }
        }
        return false
    }
}

/// What JavaScript's string methods do, where Swift's differ.
public enum JSText {
    /// `toLowerCase()`: each scalar's full lowercase mapping; a capital sigma (U+03A3) is `ς` (U+03C2) where
    /// Final_Sigma holds - the nearest scalar before it that isn't case-ignorable is cased, and the nearest after
    /// it isn't (or there is none) - as ICU, which V8 calls, decides it.
    public static func lowercase(_ text: String) -> String {
        String(String.UnicodeScalarView(lowercased(Array(text.unicodeScalars))))
    }

    static let finalSigma = Unicode.Scalar(UInt32(0x03C2))!

    static func lowercased(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(scalars.count)
        for (at, scalar) in scalars.enumerated() {
            if scalar.value == 0x03A3, cased(scalars, from: at - 1, step: -1), !cased(scalars, from: at + 1, step: 1) {
                out.append(finalSigma)
            } else if scalar.isASCII {
                out.append(scalar.value >= 0x41 && scalar.value <= 0x5A ? Unicode.Scalar(UInt8(scalar.value + 0x20)) : scalar)
            } else {
                out.append(contentsOf: scalar.properties.lowercaseMapping.unicodeScalars)
            }
        }
        return out
    }

    /// Whether the first scalar from `from` walking by `step` that isn't case-ignorable is cased (ICU's
    /// isFollowedByCasedLetter: an ignorable one is passed over even when it is cased too).
    static func cased(_ scalars: [Unicode.Scalar], from: Int, step: Int) -> Bool {
        var at = from
        while at >= 0 && at < scalars.count {
            let properties = scalars[at].properties
            if !properties.isCaseIgnorable { return properties.isCased }
            at += step
        }
        return false
    }

    /// `trim()`: JavaScript's white space and line terminators off both ends - not Foundation's set, which has
    /// U+0085 and lacks U+FEFF.
    public static func trim(_ text: String) -> String {
        var scalars = Substring(text).unicodeScalars
        while let first = scalars.first, isTrimmed(first) { scalars = scalars.dropFirst() }
        while let last = scalars.last, isTrimmed(last) { scalars = scalars.dropLast() }
        return String(String.UnicodeScalarView(scalars))
    }

    static func isTrimmed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
        default: return false
        }
    }
}
