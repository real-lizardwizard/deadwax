import Foundation
import Testing
@testable import DeadwaxCore

/// The index down the Albums screen's edge (lib/shelves.ts indexEntries, showsIndex, fitIndex, entryAt): the fixture's
/// sweeps replayed, and ui/test/shelves.sim.cjs's own checks.
@Suite struct LibraryIndexTests {
    static let letterEntries = ShelfIndex.entries([ShelfGroup(key: "A", label: "A", items: [0])], .alphabeticalByArtist)
    static let decadeEntries: [ShelfIndex.Entry] = {
        let groups: [ShelfGroup] = (0..<9).map { (n: Int) -> ShelfGroup in
            let year = String(2020 - n * 10)
            return ShelfGroup(key: year, label: year, items: [0])
        }
        return ShelfIndex.entries(groups, .byYearDesc)
    }()

    /// Each slot as the fixture writes it: its place among the entries, -1 for a dot.
    static func places(_ drawn: [ShelfIndex.Slot]) -> [Int] {
        drawn.map { slot in
            if case let .entry(_, at) = slot { return at }
            return -1
        }
    }

    static func labels(_ drawn: [ShelfIndex.Slot]) -> String {
        drawn.map { slot in
            if case let .entry(entry, _) = slot { return entry.label }
            return "\u{2022}"
        }.joined()
    }

    static var sim: (shelf: Shelf, byArtist: [ShelfGroup]) {
        let shelf = Shelf(try! LibraryShelvesTests.decode(LibraryShelvesTests.simAlbums), zone: LibraryShelvesTests.utc)
        return (shelf, shelf.groups(shelf.sorted(.alphabeticalByArtist), .alphabeticalByArtist))
    }

    // MARK: - the fixture

    @Test func theEntriesAndWhatVoiceOverSays() throws {
        let fixture = try LibraryFixtures.load("index", as: IndexFixture.self)
        #expect(Self.letterEntries.map { [$0.label, $0.accessibility] } == fixture.letters)
        #expect(Self.decadeEntries.map { [$0.label, $0.accessibility] } == fixture.decades)
    }

    @Test func everyFitAndEveryFingerAsTheTypeScriptHasThem() throws {
        let fixture = try LibraryFixtures.load("index", as: IndexFixture.self)
        #expect(fixture.fits.count == 2 * 42)
        var misses = LibraryFixtures.Misses()
        var fingers = 0
        for fit in fixture.fits {
            let entries = fit.kind == "letters" ? Self.letterEntries : Self.decadeEntries
            let drawn = ShelfIndex.fit(entries, slots: fit.slots)
            if Self.places(drawn) != fit.drawn { misses.add("\(fit.kind) at \(fit.slots): \(Self.places(drawn)), TS \(fit.drawn)") }
            for (k, expected) in fit.at.enumerated() {
                let y = fit.from + Double(k) * fit.step
                let got = ShelfIndex.entryAt(drawn, y: y, top: fit.top, height: fit.height)
                if got != expected { misses.add("\(fit.kind) at \(fit.slots), y \(y): \(got.map(String.init) ?? "nil"), TS \(expected.map(String.init) ?? "nil")") }
                fingers += 1
            }
        }
        #expect(fingers > 20_000)
        #expect(misses.isEmpty, "\(misses)")
    }

    // MARK: - shelves.sim "the index down the right edge"

    @Test func lettersAllTwentySevenEachToItsGroup() {
        let letters = ShelfIndex.entries(Self.sim.byArtist, .alphabeticalByArtist)
        #expect(letters.count == 27)
        #expect(letters.map(\.label).joined() == "ABCDEFGHIJKLMNOPQRSTUVWXYZ#")
        #expect(letters.map { String($0.group) }.joined(separator: ",") == "0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2")
        #expect([letters[0].accessibility, letters[26].accessibility] == ["Jump to A", "Jump to numbers and symbols"])
        let onlyZ = [ShelfGroup(key: "Z", label: "Z", items: [1])]
        #expect(ShelfIndex.entries(onlyZ, .alphabeticalByName).map(\.group) == Array(repeating: 0, count: 27))
    }

    @Test func decadesInTheSortsDirectionNoneForNoYear() {
        let shelf = Self.sim.shelf
        let down = shelf.groups(shelf.sorted(.byYearDesc), .byYearDesc)
        #expect(ShelfIndex.entries(down, .byYearDesc).map { "\($0.label) \($0.accessibility) \($0.group)" } == [
            "2010 Jump to the 2010s 0", "2000 Jump to the 2000s 1", "1990 Jump to the 1990s 2", "1970 Jump to the 1970s 4", "1960 Jump to the 1960s 5",
        ])
        let up = shelf.groups(shelf.sorted(.byYearAsc), .byYearAsc)
        #expect(ShelfIndex.entries(up, .byYearAsc).map(\.label) == ["1960", "1970", "1990", "2000", "2010"])
        #expect(ShelfIndex.entries(Self.sim.byArtist, .newest).isEmpty)
        #expect(ShelfIndex.entries([], .alphabeticalByArtist).isEmpty)
    }

    @Test func drawnWithFiftyOrMoreNothingTypedASortThatHasOne() {
        #expect(ShelfIndex.shows(.alphabeticalByArtist, count: 50, typed: ""))
        #expect(!ShelfIndex.shows(.alphabeticalByArtist, count: 49, typed: ""))
        #expect(!ShelfIndex.shows(.alphabeticalByArtist, count: 3000, typed: "dum"))
        #expect(ShelfIndex.shows(.alphabeticalByArtist, count: 3000, typed: "   "))
        #expect(!ShelfIndex.shows(.newest, count: 3000, typed: ""))
        #expect(ShelfIndex.shows(.byYearAsc, count: 50, typed: ""))
        #expect(ShelfIndex.shows(.alphabeticalByName, count: 50, typed: ""))
        #expect(ShelfIndex.minimum == 50)
    }

    @Test func thinnedToTheSlotsThereIsRoomFor() {
        let letters = ShelfIndex.entries(Self.sim.byArtist, .alphabeticalByArtist)
        let thin = ShelfIndex.fit(letters, slots: 13)
        #expect(thin.count == 13)
        #expect(Self.labels(thin) == "A\u{2022}E\u{2022}J\u{2022}N\u{2022}R\u{2022}W\u{2022}#")
        #expect(ShelfIndex.fit(letters, slots: 27).count == 27)
        #expect(ShelfIndex.fit(letters, slots: 40).allSatisfy { if case .entry = $0 { return true } else { return false } })
        #expect(ShelfIndex.slots(height: 195) == 13 && ShelfIndex.slots(height: 194.9) == 12)
        #expect(ShelfIndex.slots(height: 0) == 1 && ShelfIndex.slots(height: .nan) == 1 && ShelfIndex.slots(height: 3) == 1)
    }

    @Test func theFingersEntryIsTheDrawnSlotUnderIt() {
        let letters = ShelfIndex.entries(Self.sim.byArtist, .alphabeticalByArtist)
        let full = ShelfIndex.fit(letters, slots: 27)
        let at = { (y: Double) in ShelfIndex.entryAt(full, y: y, top: 100, height: 270) }
        #expect([at(100), at(110), at(120), at(369), at(9999), at(0)] == [0, 1, 2, 26, 26, 0])
        #expect(ShelfIndex.entryAt([], y: 5, top: 0, height: 10) == nil)
        #expect(ShelfIndex.entryAt(full, y: 5, top: 0, height: 0) == nil)
        #expect(ShelfIndex.entryAt(full, y: .nan, top: 0, height: 10) == nil)
        #expect([at(106), at(109.9), at(115.5)] == [0, 0, 1])
    }

    /// (review of .59) a thinned strip: every drawn letter lands on itself, at the top, middle and foot of its slot.
    @Test func everyDrawnLetterLandsOnItself() {
        let letters = ShelfIndex.entries(Self.sim.byArtist, .alphabeticalByArtist)
        var lands: [String] = []
        for count in 1...27 {
            let drawn = ShelfIndex.fit(letters, slots: count)
            for (place, slot) in drawn.enumerated() {
                guard case let .entry(entry, at) = slot else { continue }
                for part in [0.05, 0.5, 0.95] {
                    let got = ShelfIndex.entryAt(drawn, y: 100 + (Double(place) + part) * 15, top: 100, height: Double(drawn.count) * 15)
                    if got != at { lands.append("\(count) slots: \(entry.label) -> \(got.map { letters[$0].label } ?? "nil")") }
                }
            }
        }
        #expect(lands == [])
    }

    @Test func aDragAcrossADotReachesEachLetterItStandsFor() {
        let letters = ShelfIndex.entries(Self.sim.byArtist, .alphabeticalByArtist)
        let thin = ShelfIndex.fit(letters, slots: 13)
        func place(_ label: String) -> Int {
            thin.firstIndex { if case let .entry(entry, _) = $0 { return entry.label == label } else { return false } }!
        }
        var across: [String] = []
        var y = 100 + Double(place("A") + 1) * 15
        while y < 100 + Double(place("E")) * 15 {
            let label = letters[ShelfIndex.entryAt(thin, y: y, top: 100, height: 13 * 15)!].label
            if across.last != label { across.append(label) }
            y += 1
        }
        #expect(across == ["B", "C", "D"])
        for count in [3, 7, 13, 18, 26] {
            let drawn = ShelfIndex.fit(letters, slots: count)
            var swept = Set<Int>()
            var y = 100.0
            while y < 100 + Double(drawn.count) * 15 {
                if let got = ShelfIndex.entryAt(drawn, y: y, top: 100, height: Double(drawn.count) * 15) { swept.insert(got) }
                y += 0.25
            }
            #expect(swept.count == 27, "a drag down the whole strip at \(count) slots")
        }
    }
}
