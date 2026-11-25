import Foundation
import Testing
@testable import DeadwaxCore

/// LastfmMatch.key against the one contract (lastfm.md 2.4): tests/fixtures/lastfm/match-vectors.json, copied byte for
/// byte to Fixtures/lastfm/ (tests/test_lastfm_vectors.py holds the copy) - `stripped` written by hand, `key` the web
/// TypeScript's own titleKey of it, src/lastfm.py held to the same file.
@Suite struct LastfmMatchTests {
    struct Vectors: Decodable {
        struct Title: Decodable { let title: String; let stripped: String; let key: String }
        struct Name: Decodable { let name: String; let key: String; let first: String }
        let titles: [Title]
        let names: [Name]
    }

    static func vectors() throws -> Vectors {
        try JSONDecoder().decode(Vectors.self, from: Fixtures.data("lastfm/match-vectors.json"))
    }

    /// A string's scalars: Swift's `==` on Strings is canonical equivalence (a precomposed letter equals its decomposed
    /// spelling), while Python's - and the server's keys - compare code points, so every comparison here is of these.
    static func scalars(_ text: String) -> [UInt32] {
        text.unicodeScalars.map(\.value)
    }

    @Test func everyTitleStripsAndKeysAsTheVectorsSay() throws {
        let vectors = try Self.vectors()
        #expect(vectors.titles.count >= 40)
        for vector in vectors.titles {
            #expect(Self.scalars(LastfmMatch.strip(vector.title)) == Self.scalars(vector.stripped), "\(vector.title)")
            #expect(Self.scalars(LastfmMatch.key(vector.title)) == Self.scalars(vector.key), "\(vector.title)")
        }
    }

    @Test func everyNameFoldsAsTheVectorsSay() throws {
        // the album pick's credit check is Fold.key (owned.ts foldName) - the names' `key`
        let vectors = try Self.vectors()
        #expect(vectors.names.count >= 20)
        for vector in vectors.names {
            #expect(Self.scalars(Fold.key(vector.name)) == Self.scalars(vector.key), "\(vector.name)")
        }
    }

    /// Past the vectors: Python's own `re` and `str`, as src/lastfm.py strip_title matched each (read off Python 3.14 on
    /// 24 Nov) - its white space (U+001C, NEL, the no-break space), its case folds (ſ, İ, ı), its `\w` (a digit and `_`
    /// are word characters), its brackets left open.
    @Test func pythonsOwnEdgesAreMatchedAsPythonMatchesThem() {
        let cases: [(String, String)] = [
            ("Roads\u{1C}-\u{1C}Live", "Roads"),
            ("Roads - Rema\u{17F}tered", "Roads"),
            ("Roads - L\u{130}VE", "Roads"),
            ("Roads - l\u{131}ve", "Roads"),
            ("Roads - Remasters", "Roads - Remasters"),
            ("Roads (feat. X", "Roads (feat. X"),
            ("Roads [x - Live", "Roads [x - Live"),
            ("A - B (x) - Live", "A - B (x)"),
            ("Roads\u{A0}-\u{A0}Live", "Roads"),
            ("Roads -Live", "Roads -Live"),
            ("Roads- Live", "Roads- Live"),
            ("Roads  -  Live Forever", "Roads"),
            ("Roads (FEAT. X) ft. Y", "Roads"),
            ("Roads ft.\u{85}Y", "Roads"),
            ("Roads \u{2014} Live", "Roads \u{2014} Live"),
            ("Roads (WITH\tX)", "Roads"),
            ("Roads (within)", "Roads (within)"),
            ("Roads - Live_Take", "Roads - Live_Take"),
            ("Roads - Live2", "Roads - Live2"),
            ("Roads - 2ive", "Roads - 2ive"),
            ("Roads\u{85}", "Roads"),
            ("Roads - Mono (2014)", "Roads"),
            ("(Live) - Live", "(Live)"),
            ("Roads - Live)", "Roads"),
            ("Roads ) - Live", "Roads )"),
            (" - Live", ""),
            ("Roads feat. X - Live", "Roads"),
            ("Roads (feat. A) (feat. B)", "Roads"),
            ("Roads [Remix] - Remaster", "Roads [Remix]"),
        ]
        for (title, stripped) in cases {
            #expect(Self.scalars(LastfmMatch.strip(title)) == Self.scalars(stripped), "\(title.debugDescription)")
            #expect(Self.scalars(LastfmMatch.key(title)) == Self.scalars(SongTitle.key(stripped)),
                    "\(title.debugDescription)")
        }
        // a scalar's difference is a difference: "e" and a combining acute are "é" to Swift's ==, never to Python
        #expect("Caf\u{E9}" == "Cafe\u{301}" && Self.scalars("Caf\u{E9}") != Self.scalars("Cafe\u{301}"))
        #expect(Self.scalars(LastfmMatch.strip("Cafe\u{301} - Live")) == Self.scalars("Cafe\u{301}"))
        #expect(LastfmMatch.key("(Live) - Live") == "")
        #expect(LastfmMatch.key(nil) == "")
    }
}
