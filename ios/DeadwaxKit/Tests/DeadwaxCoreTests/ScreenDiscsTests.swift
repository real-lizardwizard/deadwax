import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/screens/discs.json: lib/discTitles.ts's headings and title map, for ui/test/discs.sim.cjs's albums by its
/// names and for seeded ones - the titles read through the app's own model (`DiscTitle`'s decoding), as an album
/// answer's are.
@Suite struct ScreenDiscsTests {
    let fixture = try! Web.load("discs")

    func songs(_ list: Web) -> [Song] {
        list.list.enumerated().map { Song(id: "s\($0.offset)", discNumber: $0.element["discNumber"].int) }
    }

    func titles(_ list: Web) throws -> [DiscTitle]? {
        if list.isNull { return nil }
        let bytes = try JSONEncoder().encode(list)
        return try JSONDecoder().decode([DiscTitle].self, from: bytes)
    }

    func replay(_ cases: [Web], _ diffs: ScreenDiffs) throws {
        for one in cases {
            let name = one["name"].string ?? "?"
            let headings = DiscHeadings.headings(songs(one["songs"]), try titles(one["titles"]))
            diffs.check("\(name): how many headings", headings.count, one["headings"].list.count)
            for (index, heading) in headings.enumerated() {
                diffs.text("\(name): heading \(index)", heading, one["headings"][index])
            }
            let list = DiscHeadings.titleList(try titles(one["titles"]))
            diffs.check("\(name): how many titles", list.count, one["map"].list.count)
            for (index, entry) in list.enumerated() {
                diffs.check("\(name): title \(index)'s disc", entry.disc, one["map"][index][0].int ?? -999)
                diffs.text("\(name): title \(index)", entry.title, one["map"][index][1])
            }
        }
    }

    @Test func theFixtureIsThere() {
        #expect(fixture["sim"].list.count == 14 && fixture["seeded"].list.count == 220)
        expectMadeFrom(fixture, ["ui/src/lib/discTitles.ts"])
        #expect(DiscHeadings.dot == fixture["dot"].string.map { " \($0) " })
    }

    /// discs.sim.cjs's cases, each by its name.
    @Test func theSimsAlbums() throws {
        let diffs = ScreenDiffs()
        try replay(fixture["sim"].list, diffs)
        diffs.done()
    }

    @Test func seededAlbums() throws {
        let diffs = ScreenDiffs()
        try replay(fixture["seeded"].list, diffs)
        diffs.done()
    }

    @Test func aHeadingIsTheWebs() {
        for row in fixture["heading"].list {
            let map = Dictionary(uniqueKeysWithValues: row["titles"].list.map { ($0[0].int!, $0[1].string!) })
            #expect(Screens.same(DiscHeadings.heading(row["disc"].int!, map), row["heading"].string), "heading(\(row["disc"]))")
        }
    }

    @Test func theFourthDiscOfWembley() {
        //? discs.sim.cjs's first case, written out
        let album = Album(id: "al", song: [1, 1, 2, 2, 3, 4, 4].enumerated().map { Song(id: "s\($0.offset)", discNumber: $0.element) },
                          discTitles: [DiscTitle(disc: 4, title: "TDSOTM - Live at Wembley - From Pre-FM Master Tape")])
        #expect(DiscHeadings.headings(album) == ["Disc 1", nil, "Disc 2", nil, "Disc 3",
                                                 "Disc 4 · TDSOTM - Live at Wembley - From Pre-FM Master Tape", nil])
        #expect(DiscHeadings.headings(Album(id: "al", song: [Song(id: "a"), Song(id: "b")])) == [nil, nil])
    }

    /// About's disc headings (About.swift, Info's port) read the field JS's way; on every album Navidrome's numbers
    /// make, they say what these do.
    @Test func aboutsCopyAgreesWithThis() throws {
        for one in fixture["sim"].list + fixture["seeded"].list {
            let mine = DiscHeadings.headings(songs(one["songs"]), try titles(one["titles"]))
            let details = one["songs"].list.map { SongDetails(discNumber: $0["discNumber"].num) }
            let aboutTitles: [AboutDiscTitle]? = one["titles"].isNull ? nil : try JSONDecoder().decode(
                [AboutDiscTitle].self, from: JSONEncoder().encode(one["titles"]))
            #expect(AboutCard.discHeadings(details, aboutTitles) == mine, "\(one["name"])")
        }
    }
}

extension Web: Encodable {
    func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let flag): try value.encode(flag)
        case .number(let number): try value.encode(number)
        case .string(let text): try value.encode(text)
        case .array(let list): try value.encode(list)
        case .object(let fields): try value.encode(fields)
        }
    }
}
