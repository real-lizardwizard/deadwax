import Foundation
import Testing
@testable import DeadwaxCore

/// The Library's dates: Date.parse for the forms Navidrome sends, and the month headers (lib/shelves.ts).
@Suite struct LibraryTimeTests {
    static let utc = TimeZone(identifier: "UTC")!

    /// Every string in four zones - UTC, New York, London, Lord Howe (half-hour changes) - the clocks' changes
    /// included: a time that happens twice is the earlier, one that never happens is read with the offset before.
    @Test func everyDateReadsAsV8ReadsItInEachZone() throws {
        let fixture = try LibraryFixtures.load("dates", as: DatesFixture.self)
        #expect(fixture.dates.count > 1000)
        var misses = LibraryFixtures.Misses()
        for (at, name) in fixture.zones.enumerated() {
            let zone = try #require(TimeZone(identifier: name), "no time zone \(name) here")
            for row in fixture.dates {
                let ms = AlbumTime.ms(row.text, zone: zone)
                if ms != row.ms[at] { misses.add("\(name) \(row.text): \(ms.map(String.init) ?? "nil"), V8 \(row.ms[at].map(String.init) ?? "nil")") }
                let month = AlbumTime.monthLabel(row.text, zone: zone)
                if month != row.month[at] { misses.add("\(name) \(row.text): \(month), TS \(row.month[at])") }
            }
        }
        #expect(misses.isEmpty, "\(misses)")
    }

    /// The one deliberate difference: what V8 reads only with its legacy parser - a month or day of one digit, an
    /// offset without its colon, a Z after a date alone, a space around the date, a signed year of five digits - is no
    /// date here ("Date unknown", as an unreadable `created` already is). Navidrome sends RFC 3339; porting V8's
    /// fallback for strings it never sends would be the riskiest code in the Library for nothing.
    @Test func whatOnlyV8sLegacyParserReadsIsNoDate() throws {
        let fixture = try LibraryFixtures.load("dates", as: DatesFixture.self)
        #expect(fixture.legacy.count == 6)
        for row in fixture.legacy {
            #expect(row.ms.allSatisfy { $0 != nil }, "V8 no longer reads \(LibraryFixtures.spelled(row.text)) - move it to the dates")
            for name in fixture.zones {
                let zone = try #require(TimeZone(identifier: name))
                #expect(AlbumTime.ms(row.text, zone: zone) == nil, "\(name) \(LibraryFixtures.spelled(row.text))")
                #expect(AlbumTime.monthLabel(row.text, zone: zone) == AlbumTime.dateUnknown)
            }
        }
    }

    @Test func theExpandedYearsAndTheEdgesOfADate() {
        #expect(AlbumTime.ms("+002026-10-05T00:00:00Z", zone: Self.utc) == 1_791_158_400_000)
        #expect(AlbumTime.ms("+275760-09-13T00:00:00Z", zone: Self.utc) == 8_640_000_000_000_000)
        #expect(AlbumTime.ms("+275760-09-13T00:00:00.001Z", zone: Self.utc) == nil)
        #expect(AlbumTime.ms("-271821-04-20T00:00:00Z", zone: Self.utc) == -8_640_000_000_000_000)
        #expect(AlbumTime.ms("-000000-01-01T00:00:00Z", zone: Self.utc) == nil)
        #expect(AlbumTime.ms("+02026-10-05", zone: Self.utc) == nil)
        #expect(AlbumTime.monthLabel("-000001-01-01T00:00:00Z", zone: Self.utc) == "January -1")
    }

    /// library.md section 6's vectors.
    @Test func theNamedForms() throws {
        let cases: [(String, Int64?)] = [
            ("2026-10-05T14:22:31Z", 1_791_210_151_000), ("2026-10-05T14:22:31.1Z", 1_791_210_151_100),
            ("2026-10-05T14:22:31.123456789Z", 1_791_210_151_123), ("2026-10-05T14:22:31.9999Z", 1_791_210_151_999),
            ("2026-10-05T14:22:31+01:00", 1_791_206_551_000), ("2026-10-05T14:22:31.5-05:30", 1_791_229_951_500),
            ("2026-10-05", 1_791_158_400_000), ("2026-10-05T14:22Z", 1_791_210_120_000), ("2026-10-05 14:22:31Z", 1_791_210_151_000),
            ("2026-10-05T14:22:31", 1_791_210_151_000), ("2026", 1_767_225_600_000), ("2026-10", 1_790_812_800_000),
            ("2026-10-05T24:00:00Z", 1_791_244_800_000), ("2026-02-30T00:00:00Z", 1_772_409_600_000),
            ("0001-01-01T00:00:00Z", -62_135_596_800_000), ("1969-12-31T23:59:59.999Z", -1),
            ("2026-13-05T00:00:00Z", nil), ("2026-10-05T14:60:00Z", nil), ("2026-10-05T25:00:00Z", nil),
            ("2026-10-05T14:22:31.Z", nil), ("2026-10-05T14:22:31,5Z", nil), ("not a date", nil), ("", nil),
        ]
        for (text, expected) in cases {
            #expect(AlbumTime.ms(text, zone: Self.utc) == expected, "\(text)")
        }
        #expect(AlbumTime.ms(nil) == nil)
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let local: Int64 = 1_791_224_551_000
        #expect(AlbumTime.ms("2026-10-05T14:22:31", zone: newYork) == local)
        //? a zone named in the string is never the device's
        #expect(AlbumTime.ms("2026-10-05T14:22:31Z", zone: newYork) == 1_791_210_151_000)
        #expect(AlbumTime.ms("2026-10-05", zone: newYork) == 1_791_158_400_000)
        #expect(AlbumTime.month(AlbumTime.ms("2026-02-30T00:00:00Z")) == "March 2026")
        #expect(AlbumTime.month(-62_135_596_800_000) == "January 1")
        #expect(AlbumTime.month(-1) == "December 1969")
    }

    /// shelves.sim "a month from UTC, never the device's zone or language" - and the float the dev stand-in sends
    /// for `created`, which isn't a string, so no date.
    @Test func aMonthFromUTC() throws {
        for zone in [Self.utc, try #require(TimeZone(identifier: "Australia/Lord_Howe"))] {
            #expect(AlbumTime.monthLabel("2026-10-31T23:30:00-05:00", zone: zone) == "November 2026")
            #expect(AlbumTime.monthLabel("2026-01-01T00:00:00Z", zone: zone) == "January 2026")
            #expect(AlbumTime.monthLabel("", zone: zone) == "Date unknown")
            #expect(AlbumTime.monthLabel(nil, zone: zone) == "Date unknown")
        }
        let float = try JSONDecoder().decode(IndexAlbum.self, from: Data(#"{"id":"x","created":1729000000.5}"#.utf8))
        #expect(float.created == nil)
        #expect(AlbumKeys(float).created == nil)
        #expect(AlbumTime.monthLabel(float.created) == AlbumTime.dateUnknown)
    }

    @Test func theClocksChangingInNewYork() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        //? 2026-03-08 02:30 never happens: read before the change (EST), 07:30Z
        #expect(AlbumTime.ms("2026-03-08T02:30:00", zone: newYork) == 1_772_955_000_000)
        //? 2026-11-01 01:30 happens twice: the earlier (EDT), 05:30Z
        #expect(AlbumTime.ms("2026-11-01T01:30:00", zone: newYork) == 1_793_511_000_000)
    }
}
