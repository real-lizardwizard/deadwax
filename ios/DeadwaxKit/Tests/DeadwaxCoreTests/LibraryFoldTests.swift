import Foundation
import Testing
@testable import DeadwaxCore

/// Fold (lib/owned.ts foldName, lib/shelves.ts findText, initialOf) and how the Library compares and finds.
@Suite struct LibraryFoldTests {
    @Test func everyNameFoldsAsTheTypeScriptFoldsIt() throws {
        let fixture = try LibraryFixtures.load("fold", as: FoldFixture.self)
        #expect(fixture.names.count > 2000)
        var misses = LibraryFixtures.Misses()
        for row in fixture.names {
            let name = row[0]
            let key = Fold.key(name)
            if !LibraryFixtures.same(key, row[1]) {
                misses.add("foldName \(LibraryFixtures.spelled(name)): \(LibraryFixtures.spelled(key)), TS \(LibraryFixtures.spelled(row[1]))")
            }
            let find = Fold.findText(name)
            if !LibraryFixtures.same(find, row[2]) {
                misses.add("findText \(LibraryFixtures.spelled(name)): \(LibraryFixtures.spelled(find)), TS \(LibraryFixtures.spelled(row[2]))")
            }
            if Fold.initial(of: key) != row[3] || FoldKey(key).initial != row[3] {
                misses.add("initial \(LibraryFixtures.spelled(name)): \(Fold.initial(of: key)), TS \(row[3] ?? "nil")")
            }
        }
        #expect(misses.isEmpty, "\(misses)")
    }

    /// The spec's vectors (library.md section 5), each read off the compiled TypeScript: [name, foldName, findText].
    @Test func theNamedCases() {
        let cases: [(String?, String, String)] = [
            ("The Beatles", "beatles", "the beatles"), ("Björk", "bjork", "bjork"),
            ("Simon & Garfunkel", "simon and garfunkel", "simon and garfunkel"),
            ("Dummy (Deluxe Edition)", "dummy", "dummy deluxe edition"), ("AC/DC", "ac dc", "ac dc"),
            ("Guns N' Roses", "guns n roses", "guns n roses"), ("坂本龍一", "坂本龍一", "坂本龍一"),
            ("İstanbul", "istanbul", "istanbul"), ("ﬁve", "five", "five"), ("Ｔｈｅ Ｂｅａｔｌｅｓ", "beatles", "the beatles"),
            ("½ Life", "1 2 life", "1 2 life"), ("x²", "x2", "x2"), ("Ⅳ", "iv", "iv"), ("ǅemal", "dzemal", "dzemal"),
            ("Ⓐrt", "art", "art"), ("Æther", "æther", "æther"), ("Øresund", "øresund", "øresund"), ("Łódź", "łodz", "łodz"),
            ("Đorđe", "đorđe", "đorđe"), ("Straße", "straße", "straße"), ("Ångström", "angstrom", "angstrom"),
            ("The The", "the", "the the"), ("The", "the", "the"), ("  the  beatles ", "beatles", "the beatles"),
            ("Thé Band", "band", "the band"), ("The-Band", "band", "the band"), ("THE BEATLES", "beatles", "the beatles"),
            ("the\tbeatles", "beatles", "the beatles"), ("Theatre", "theatre", "theatre"),
            ("[Remastered] Album", "album", "remastered album"), ("Album (unclosed", "album unclosed", "album unclosed"),
            ("x (a] y", "x y", "x a y"), ("a (b) c (d) e", "a c e", "a b c d e"), ("Kid A [Deluxe] (2009)", "kid a", "kid a deluxe 2009"),
            ("Plaid & Co (Live)", "plaid and co", "plaid and co live"), ("Hello ‘World’", "hello world", "hello world"),
            ("$uicideboy$", "uicideboy", "uicideboy"), ("!!!", "", ""), ("", "", ""), (nil, "", ""),
            ("…And You Will Know Us", "and you will know us", "and you will know us"), ("🎵 Music", "music", "music"),
        ]
        for (name, key, find) in cases {
            #expect(LibraryFixtures.same(Fold.key(name), key), "foldName \(LibraryFixtures.spelled(name)): \(LibraryFixtures.spelled(Fold.key(name)))")
            #expect(LibraryFixtures.same(Fold.findText(name), find), "findText \(LibraryFixtures.spelled(name)): \(LibraryFixtures.spelled(Fold.findText(name)))")
        }
    }

    @Test func aCapitalSigmaEndingAWordIsAFinalSigma() {
        let units = { (text: String) in Array(Fold.key(text).unicodeScalars.map(\.value)) }
        #expect(units("ΟΔΟΣ") == [0x3BF, 0x3B4, 0x3BF, 0x3C2])
        #expect(units("ΑΣ ΣΑ") == [0x3B1, 0x3C2, 0x20, 0x3C3, 0x3B1])
        //? ’ is case-ignorable: the sigma isn't final, the Α after it is cased
        #expect(units("ΟΔΟΣ’Α") == [0x3BF, 0x3B4, 0x3BF, 0x3C3, 0x20, 0x3B1])
        #expect(units("Σ") == [0x3C3])
        #expect(JSText.lowercase("ΟΔΟΣ") == "οδος")
        #expect(Array(JSText.lowercase("ΟΔΟΣ").unicodeScalars.map(\.value)) == [0x3BF, 0x3B4, 0x3BF, 0x3C2])
        //? Swift's own never makes one - why the port does it by hand
        #expect(Array("ΟΔΟΣ".lowercased().unicodeScalars.map(\.value)) == [0x3BF, 0x3B4, 0x3BF, 0x3C3])
    }

    /// (review) Every category the fold keeps or drops, as it is after NFKD: a spacing mark (Mc) is a mark, gone as
    /// \p{M} takes it - the vowel signs of Hindi, Tamil and Bengali names, two-part ones split by NFKD first - and a
    /// letter number (Nl) or other number (No) that no decomposition touches is a number, kept. Each answer read off
    /// the compiled TypeScript (fold.json has them, and ~500 random names drawn mostly from these scripts).
    @Test func spacingMarksGoLetterAndOtherNumbersStay() {
        let scalars = { (text: String) in Fold.key(text).unicodeScalars.map(\.value) }
        #expect(scalars("हिंदी") == [0x939, 0x926])
        #expect(scalars("தமிழ்") == [0xBA4, 0xBAE, 0xBB4])
        #expect(scalars("বাংলা") == [0x9AC, 0x9B2])
        #expect(scalars("কোলকাতা") == [0x995, 0x9B2, 0x995, 0x9A4])
        #expect(scalars("〇〇") == [0x3007, 0x3007])
        #expect(scalars("ↅ") == [0x2185])
        #expect(scalars("𐍁") == [0x10341])
        #expect(scalars("x༪y") == [0x78, 0xF2A, 0x79])
        #expect(scalars("৴a") == [0x9F4, 0x61])
        #expect(scalars("𐄇") == [0x10107])
        //? the categories themselves, scalar by scalar: Mc out; Nl, No in
        let scalar = { (value: UInt32) in Unicode.Scalar(value)! }
        #expect([0x93F, 0x940, 0xBBF, 0x9BE, 0x903].allSatisfy { Fold.isMark(scalar($0)) })
        #expect([0x3007, 0x2185, 0x16EE, 0x10341, 0xF2A, 0x9F4, 0x1369, 0x10107].allSatisfy { Fold.isLetterOrNumber(scalar($0)) })
        //? a sigma before a spacing mark: the mark goes first, so the sigma ends the word
        #expect(scalars("aΣः") == [0x61, 0x3C2])
    }

    @Test func hangulIsKeptAsJamo() {
        #expect(Array(Fold.key("방탄").unicodeScalars.map(\.value)) == [0x1107, 0x1161, 0x11BC, 0x1110, 0x1161, 0x11AB])
        #expect(Fold.key("ŉ").unicodeScalars.map(\.value) == [0x2BC, 0x6E])
    }

    /// shelves.sim "initials: a-z a capital, anything else `#`".
    @Test func initials() {
        #expect(["beatles", "zz", "10cc", "", "ß", "坂本"].map(Fold.initial(of:)) == ["B", "Z", "#", "#", "#", "#"])
        #expect(["beatles", "zz", "10cc", "", "ß", "坂本"].map { FoldKey($0).initial } == ["B", "Z", "#", "#", "#", "#"])
    }

    /// Code-unit order, as JS's `<` - never Swift's String `<`, which compares canonically and orders these the
    /// other way: NFKD's Hangul jamo against a CJK ideograph, and an astral ideograph (a surrogate pair, D840)
    /// against U+FA0E.
    @Test func keysCompareByCodeUnitAsJavaScriptDoes() {
        let bts = Fold.key("방탄"), one = Fold.key("一")
        #expect(FoldKey(bts) < FoldKey(one))
        #expect(!(bts < one))
        let astral = Fold.key("\u{20000}"), compatibility = Fold.key("\u{FA0E}")
        #expect(FoldKey(astral) < FoldKey(compatibility))
        #expect(!(astral < compatibility))
        #expect(FoldKey("10cc") < FoldKey("2pac"))
        #expect(FoldKey("a") == FoldKey("a") && !(FoldKey("a") < FoldKey("a")))
    }

    /// Find matches runs of code units: "바" is found in "방탄소년단" (the jamo of 바 start 방), which Swift's
    /// `contains` - whole Characters - wouldn't find.
    @Test func findLooksForCodeUnitsNotCharacters() {
        let text = FoldKey(Fold.findText("방탄소년단"))
        let word = Find.words("바")
        #expect(word.count == 1)
        #expect(text.contains(word[0]))
        #expect(!Fold.findText("방탄소년단").contains(Fold.findText("바")))
        #expect(FoldKey(Fold.findText("The Beatles")).contains(FoldKey("eat")))
        #expect(FoldKey("abc").contains(FoldKey("")))
        #expect(!FoldKey("ab").contains(FoldKey("abc")))
    }

    @Test func javaScriptsTrim() {
        #expect(JSText.trim(" \t\n dumy \u{3000}\u{FEFF}") == "dumy")
        //? U+0085 is Foundation's white space, not JavaScript's
        #expect(JSText.trim("\u{85}x\u{85}") == "\u{85}x\u{85}")
        #expect(JSText.trim("") == "")
        #expect(JSText.trim("   ") == "")
    }
}
