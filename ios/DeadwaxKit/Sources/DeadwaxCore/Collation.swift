import Foundation

/// JavaScript's `a.localeCompare(b)` as the web's browsers answer it: ICU's root collation (CLDR's, which every
/// English locale keeps), compared at its three levels - letters first (accents and case away), then accents, then
/// case, lowercase first - with punctuation weighed rather than ignored, in ICU's own order, before the digits and the
/// letters. Nothing on Linux has ICU's tables, so this is an approximation of them, built from what Node's ICU answers
/// for the characters titles carry (slice 3, Search's songs - an album's bootlegs tie on everything before their
/// titles, and "1984-09-24" stands before "1984‐09‐15" there because a hyphen-minus weighs less than a hyphen):
///
/// - punctuation and symbols: `variables`, in ICU's order; any other, after them by code point;
/// - digits by their value, whatever their script; a compatibility character (fullwidth, a ligature, a superscript,
///   "…") as what it decomposes to, weighed a little more at the third level;
/// - Latin letters by their base letter - æ and œ as two letters, ß as "ss", ø, đ, ð, ł and ħ as their base letter
///   with a mark, ı, ŋ and þ letters of their own - and every other script after Latin, by code point;
/// - the marks in ICU's order at the second level.
///
/// Two strings in other scripts that tie on everything before them may still stand in another order than the web's -
/// held by Tests/DeadwaxCoreTests's song vectors for what the recorded answers reach.
public enum WebCollation {
    /// The punctuation and symbols ICU weighs before the digits, in its order.
    static let variables: [UInt32] = [
        0x0020, 0x005F, 0x2017, 0x002D, 0x2010, 0x2012, 0x2013, 0x2014, 0x2015, 0x002C, 0x3001, 0x003B, 0x003A, 0x0021,
        0x00A1, 0x003F, 0x00BF, 0x203D, 0x002E, 0x3002, 0x00B7, 0x0027, 0x2018, 0x2019, 0x201A, 0x201B, 0x2039, 0x203A,
        0x0022, 0x201C, 0x201D, 0x201E, 0x201F, 0x00AB, 0x00BB, 0x0028, 0x0029, 0x005B, 0x005D, 0x007B, 0x007D, 0x300C,
        0x300D, 0x2016, 0x00A7, 0x00B6, 0x0040, 0x002A, 0x002F, 0x005C, 0x0026, 0x0023, 0x0025, 0x2030, 0x2031, 0x2020,
        0x2021, 0x2022, 0x2023, 0x2027, 0x2032, 0x2035, 0x2038, 0x203B, 0x0060, 0x00B4, 0x02DC, 0x005E, 0x00AF, 0x00A8,
        0x00B8, 0x02C6, 0x00B0, 0x00A9, 0x00AE, 0x2190, 0x2192, 0x002B, 0x00B1, 0x00F7, 0x00D7, 0x003C, 0x003D, 0x003E,
        0x00AC, 0x007C, 0x00A6, 0x007E, 0x2212, 0x2605, 0x266A, 0x00A4, 0x00A2, 0x0024, 0x00A3, 0x00A5, 0x20AC,
    ]

    static let variableRank: [UInt32: UInt32] = {
        var ranks: [UInt32: UInt32] = [:]
        for (rank, scalar) in variables.enumerated() { ranks[scalar] = UInt32(rank) }
        return ranks
    }()

    /// The spacing accents ICU weighs as symbols, never as a space and a mark (their compatibility decomposition).
    static let spacingAccents: Set<UInt32> = [0x00A8, 0x00AF, 0x00B4, 0x00B8, 0x02D8, 0x02D9, 0x02DA, 0x02DB, 0x02DC, 0x02DD,
                                              0x2017]

    /// The marks' order at the second level: acute, grave, breve, circumflex, caron, ring, diaeresis, double acute,
    /// tilde, dot above, cedilla, ogonek, a stroke, eth's, macron.
    static let marks: [UInt32] = [0x0301, 0x0300, 0x0306, 0x0302, 0x030C, 0x030A, 0x0308, 0x030B, 0x0303, 0x0307, 0x0327,
                                  0x0328, stroke, eth, 0x0304]
    /// Stand-ins for the marks ø, đ, ł and ħ carry, and ð's - none of them a decomposition.
    static let stroke: UInt32 = 0x0338
    static let eth: UInt32 = 0x10_0001

    static let markRank: [UInt32: UInt32] = {
        var ranks: [UInt32: UInt32] = [:]
        for (rank, scalar) in marks.enumerated() { ranks[scalar] = UInt32(rank) }
        return ranks
    }()

    // the first level's ranges
    static let variableBase: UInt32 = 0x100
    static let symbolBase: UInt32 = 0x1000
    static let digitBase: UInt32 = 0x20_0000
    static let latinBase: UInt32 = 0x30_0000
    static let scriptBase: UInt32 = 0x40_0000

    // the second level: a letter's own, then each mark's
    static let base: UInt32 = 0x20

    // the third level: ICU's tertiary weights - lowercase, a compatibility form of one, an expansion (æ, ß), uppercase,
    // a compatibility form of one, an expansion of one, a superscript or ordinal
    static let lower: UInt32 = 0x02, compatLower: UInt32 = 0x03, expanded: UInt32 = 0x04
    static let upper: UInt32 = 0x08, compatUpper: UInt32 = 0x09, expandedUpper: UInt32 = 0x0A, special: UInt32 = 0x14

    struct Element: Equatable {
        let primary, secondary, tertiary: UInt32
    }

    /// `localeCompare`'s sign: -1, 0 or 1.
    public static func compare(_ a: String, _ b: String) -> Int {
        if a == b && Array(a.utf16) == Array(b.utf16) { return 0 }
        let x = elements(a), y = elements(b)
        for level in 0..<3 {
            let one = weights(x, level), other = weights(y, level)
            if one != other { return one.lexicographicallyPrecedes(other) ? -1 : 1 }
        }
        return 0
    }

    static func weights(_ elements: [Element], _ level: Int) -> [UInt32] {
        elements.compactMap { (element: Element) -> UInt32? in
            let weight = level == 0 ? element.primary : level == 1 ? element.secondary : element.tertiary
            return weight == 0 ? nil : weight
        }
    }

    static func elements(_ text: String) -> [Element] {
        var out: [Element] = []
        for scalar in text.unicodeScalars {
            if let rank = variableRank[scalar.value], spacingAccents.contains(scalar.value) || !decomposes(scalar) {
                out.append(Element(primary: variableBase + rank, secondary: base, tertiary: lower))
                continue
            }
            if spacingAccents.contains(scalar.value) {
                out.append(Element(primary: symbolBase + scalar.value, secondary: base, tertiary: lower))
                continue
            }
            let one = String(scalar)
            let compat = one.decomposedStringWithCompatibilityMapping
            let isCompat = Array(compat.unicodeScalars) != Array(one.decomposedStringWithCanonicalMapping.unicodeScalars)
            let category = scalar.properties.generalCategory
            let tertiary: UInt32? = !isCompat ? nil
                : category == .lowercaseLetter ? compatLower
                : (category == .uppercaseLetter || category == .titlecaseLetter) ? compatUpper
                : category == .otherLetter || category == .modifierLetter || category == .otherNumber
                    || category == .letterNumber ? special : compatLower
            for part in compat.unicodeScalars { out.append(contentsOf: elements(of: part, tertiary: tertiary)) }
        }
        return out
    }

    static func decomposes(_ scalar: Unicode.Scalar) -> Bool {
        let one = String(scalar)
        return Array(one.decomposedStringWithCompatibilityMapping.unicodeScalars) != [scalar]
    }

    /// One decomposed scalar's elements; `given`: the third level a compatibility form takes, nil for its own.
    static func elements(of scalar: Unicode.Scalar, tertiary given: UInt32?) -> [Element] {
        let value = scalar.value
        let properties = scalar.properties
        if let rank = variableRank[value] {
            return [Element(primary: variableBase + rank, secondary: base, tertiary: given ?? lower)]
        }
        if let rank = markRank[value] { return [Element(primary: 0, secondary: base + 1 + rank, tertiary: lower)] }
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return [Element(primary: 0, secondary: base + 0x40 + (value & 0xFF), tertiary: lower)]
        case .control, .format, .unassigned, .surrogate, .privateUse:
            return []
        case .spaceSeparator, .lineSeparator, .paragraphSeparator:
            return [Element(primary: variableBase, secondary: base, tertiary: given ?? compatLower)]
        case .decimalNumber:
            let digit = UInt32(max(0, properties.numericValue.map { Int($0) } ?? 0))
            return [Element(primary: digitBase + digit * 16, secondary: base, tertiary: given ?? lower)]
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return letter(scalar, given)
        default:
            return [Element(primary: symbolBase + value, secondary: base, tertiary: given ?? lower)]
        }
    }

    static func letter(_ scalar: Unicode.Scalar, _ given: UInt32?) -> [Element] {
        let properties = scalar.properties
        let isUpper = properties.generalCategory == .uppercaseLetter || properties.generalCategory == .titlecaseLetter
        let case_ = given ?? (isUpper ? upper : lower)
        let lowered = properties.lowercaseMapping.unicodeScalars.first ?? scalar
        func latin(_ letter: Character, after: UInt32 = 0) -> UInt32 {
            latinBase + UInt32(letter.asciiValue! - 0x61) * 4 + after
        }
        func plain(_ primary: UInt32) -> Element { Element(primary: primary, secondary: base, tertiary: case_) }
        func marked(_ primary: UInt32, _ mark: UInt32) -> [Element] {
            [plain(primary), Element(primary: 0, secondary: base + 1 + (markRank[mark] ?? 0), tertiary: lower)]
        }
        //? an expansion is its two letters with a mark of its own between them, after every accent (DUCET's 0110/0111):
        //? "ae" < "AE" < "æ", "SS" < "ß" < "st"
        let both = given ?? (isUpper ? expandedUpper : expanded)
        func expansion(_ first: Character, _ second: Character, _ mark: UInt32) -> [Element] {
            [Element(primary: latin(first), secondary: base, tertiary: both),
             Element(primary: 0, secondary: base + 0xF0 + mark, tertiary: both),
             Element(primary: latin(second), secondary: base, tertiary: both)]
        }
        switch lowered.value {
        case 0x00E6: return expansion("a", "e", 0)
        case 0x0153: return expansion("o", "e", 0)
        case 0x00DF: return expansion("s", "s", 1)
        case 0x00F8: return marked(latin("o"), stroke)
        case 0x0111: return marked(latin("d"), stroke)
        case 0x00F0: return marked(latin("d"), eth)
        case 0x0142: return marked(latin("l"), stroke)
        case 0x0127: return marked(latin("h"), stroke)
        case 0x0131: return [plain(latin("i", after: 1))]
        case 0x014B: return [plain(latin("n", after: 1))]
        case 0x00FE: return [plain(latin("z", after: 1))]
        case 0x61...0x7A: return [plain(latinBase + (lowered.value - 0x61) * 4)]
        case 0x00C0...0x036F, 0x1D00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF:
            return [plain(latinBase + 27 * 4 + lowered.value)]
        default:
            return [plain(scriptBase + lowered.value)]
        }
    }
}
