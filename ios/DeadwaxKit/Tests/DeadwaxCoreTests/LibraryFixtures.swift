import Foundation
import Testing
@testable import DeadwaxCore

/// The Library's fixtures (Fixtures/library), written by ios/scripts/export-library-vectors.cjs from the web app's
/// own compiled TypeScript - never by hand - and read here through Fixtures (FixtureFiles.swift).
enum LibraryFixtures {
    static func load<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: Fixtures.data("library/\(name).json"))
    }

    /// Strings equal as JavaScript compares them - every UTF-16 unit - not as Swift's `==` (canonical equivalence),
    /// which would pass a key folded to another normalization.
    static func same(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return x.utf16.elementsEqual(y.utf16)
        default: return false
        }
    }

    /// A readable form of a string for a failure message: its code points.
    static func spelled(_ text: String?) -> String {
        guard let text else { return "nil" }
        return "\"\(text)\" [" + text.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ") + "]"
    }

    /// Up to `limit` mismatches are worth printing; the count says the rest.
    struct Misses: CustomStringConvertible {
        var found: [String] = []
        var count = 0
        let limit = 12

        mutating func add(_ what: @autoclosure () -> String) {
            count += 1
            if found.count < limit { found.append(what()) }
        }

        var isEmpty: Bool { count == 0 }
        var description: String { "\(count) differ from the TypeScript:\n" + found.joined(separator: "\n") }
    }
}

// MARK: - the fixtures' shapes

struct FoldFixture: Decodable {
    let names: [[String?]]
}

struct DatesFixture: Decodable {
    struct Row: Decodable {
        let text: String
        let ms: [Int64?]
        let month: [String]
    }

    let zones: [String]
    let dates: [Row]
    /// forms only V8's legacy parser reads - with what it reads them as
    let legacy: [Row]
}

struct ShelvesFixture: Decodable {
    struct LabelGroup: Decodable, Equatable {
        let label: String
        let group: Int

        init(label: String, group: Int) {
            self.label = label
            self.group = group
        }

        init(from decoder: Decoder) throws {
            var row = try decoder.unkeyedContainer()
            label = try row.decode(String.self)
            group = try row.decode(Int.self)
        }
    }

    struct FoundCase: Decodable {
        let found: [Int]
        let heads: [String?]
        let sizes: [Int]
        let shows: Bool
        let count: String
    }

    struct SortCase: Decodable {
        let sort: String
        let by: String
        let order: [Int]
        let heads: [String?]
        let sizes: [Int]
        let index: [LabelGroup]
        let finds: [FoundCase]
    }

    struct List: Decodable {
        let name: String
        let albums: [IndexAlbum]
        let typed: [String]
        let noMatch: [String]
        let sorts: [SortCase]
    }

    let lists: [List]
}

struct IndexFixture: Decodable {
    struct Fit: Decodable {
        let kind: String
        let slots: Int
        let drawn: [Int]
        let top: Double
        let height: Double
        let from: Double
        let step: Double
        let at: [Int?]
    }

    let letters: [[String]]
    let decades: [[String]]
    let fits: [Fit]
}

struct MarksFixture: Decodable {
    struct Album: Decodable {
        let id: String
        let musicBrainzId: String?
    }

    let answers: [MyLibrary?]
    let albums: [Album]
    let isNew: [[Bool]]
}

struct StoreFixture: Decodable {
    struct Step: Decodable {
        let op: String
        let scope: String?
        let ms: Int64?
        let newest: Bool?
        let none: Bool?
        let asks: Int
        let generation: [Int]
        let kept: [String?]
        let at: [Int64?]
        let truncated: [Bool?]
    }

    let traces: [String: [Step]]
}

struct SeenFixture: Decodable {
    struct Step: Decodable {
        let op: String
        let me: Me?
        let answer: MyLibrary?
        let album: MarksFixture.Album?
        let told: [SeenBody]
        let news: [Int]?
    }

    let openedKept: Int
    let traces: [String: [Step]]
}

struct WordsFixture: Decodable {
    struct Titles: Decodable {
        let yours: String
        let albums: String
        let store: String
        let recent: String
    }

    let sorts: [[String]]
    let defaultSort: String
    let sameMomentMs: Int64
    let indexMin: Int
    let otherInitial: String
    let dateUnknown: String
    let noYear: String
    let freshMs: Int64
    let allMusic: String
    let titles: Titles
    let allAlbumsRow: String
    let emptyLibrary: String
    let emptyLibraryHow: String
    let noAlbums: String
    let couldntRefresh: String
    let truncated: String
    let findPlaceholder: String
    let sortLabel: String
    let tryAgain: String
    let loading: String
    let seeAllMusic: String
    let newMark: String
    let newMarkSpoken: String
    let breakGlassUser: String
}
