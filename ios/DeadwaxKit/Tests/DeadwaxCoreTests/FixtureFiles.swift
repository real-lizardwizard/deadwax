import Foundation
import Testing
@testable import DeadwaxCore

/// Where every test of this target finds its fixtures (Fixtures/, one folder per area) - the one way, for each
/// area's loader (LevelVectors, LibraryFixtures, ErrorFixture, the Up Next and resume traces).
///
/// The folder beside this file in the checkout first, found from `#filePath`: `swift test` runs from the checkout on
/// the Mac and in ios.yml's ubuntu job alike, and a path made from it is read the same on both - no Bundle in it,
/// so Bundle.module isn't even made. Else the copy SwiftPM puts in the test bundle (`resources: [.copy("Fixtures")]`),
/// at a path made from the bundle's `resourceURL` - never found by `url(forResource:withExtension:subdirectory:)`,
/// whose search reads Linux's flat `.resources` folder by CFBundle's own rules. (review: two loaders leaned on that
/// search with no fallback, and it has never run on Linux; nothing on this Mac can try it.)
enum Fixtures {
    /// A fixture in neither place, named by its path under Fixtures/.
    struct Missing: Error, Equatable, CustomStringConvertible {
        let path: String
        var description: String { "Fixtures/\(path) is in neither the checkout nor the test bundle" }
    }

    /// Fixtures/ in the checkout, beside this file.
    static let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    /// A fixture's file, by its path under Fixtures/ ("levels/levels-vectors.json").
    static func url(_ path: String) throws -> URL {
        let mine = checkout.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: mine.path) { return mine }
        if let bundled = Bundle.module.resourceURL?.appendingPathComponent("Fixtures").appendingPathComponent(path),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        throw Missing(path: path)
    }

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: url(path))
    }

    static func json(_ path: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data(path))
    }
}

@Suite struct FixtureFilesTests {
    @Test func everyAreasFixturesAreReadFromTheCheckout() throws {
        for path in ["errors/error-words.json", "levels/levels-vectors.json", "library/dates.json", "resume/cases.json",
                     "upnext/traces.json", "you/you.json", "gate/navidrome.json"] {
            #expect(try Fixtures.url(path) == Fixtures.checkout.appendingPathComponent(path), "\(path)")
        }
    }

    @Test func oneInNeitherPlaceIsNamed() {
        #expect(throws: Fixtures.Missing(path: "levels/no-such-vectors.json")) {
            try Fixtures.data("levels/no-such-vectors.json")
        }
        #expect("\(Fixtures.Missing(path: "levels/x.json"))" == "Fixtures/levels/x.json is in neither the checkout nor the test bundle")
    }
}
