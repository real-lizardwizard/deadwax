import Foundation
import Testing
@testable import DeadwaxCore

/// The artist's albums you don't have (15 Nov), by hand and by property: your albums never waiting and never moving among
/// themselves as MusicBrainz's answer lands; an album you have never listed again as one you don't; MusicBrainz's rows
/// among yours in the web's order; what Play plays; when MusicBrainz's rows are drawn; who the artist is. The web's own
/// answers are ArtistVectorTests' (`joined`, `mbids`).
@Suite struct ArtistJoinTests {
    static let portishead = "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"
    static func group(_ n: Int) -> String { "aaaaaaaa-0000-4000-8000-\(String(format: "%012d", n))" }
    static func release(_ n: Int) -> String { "bbbbbbbb-0000-4000-8000-\(String(format: "%012d", n))" }

    static let dummy = ReleaseGroup(id: group(1), title: "Dummy", firstReleaseDate: "1994-08-22", primaryType: "Album",
                                    secondaryTypes: [])
    static let third = ReleaseGroup(id: group(2), title: "Third", firstReleaseDate: "2008-04-28", primaryType: "Album",
                                    secondaryTypes: [])
    static let selfTitled = ReleaseGroup(id: group(3), title: "Portishead", firstReleaseDate: "1997-09-29",
                                         primaryType: "Album", secondaryTypes: [])
    static let roseland = ReleaseGroup(id: group(4), title: "Roseland NYC Live", firstReleaseDate: "1998-11-02",
                                       primaryType: "Album", secondaryTypes: ["Live"])
    static let undated = ReleaseGroup(id: group(8), title: "Untitled", primaryType: "Album")

    static func keys(_ rows: [ArtistJoin.Row]) -> [String] { rows.map(\.key) }

    static func yoursKeys(_ rows: [ArtistJoin.Row]) -> [String] {
        rows.compactMap { (row: ArtistJoin.Row) -> String? in
            if case .yours(let mine) = row { return mine.key }
            return nil
        }
    }

    static func theirKeys(_ rows: [ArtistJoin.Row]) -> [String] {
        rows.compactMap { (row: ArtistJoin.Row) -> String? in
            if case .theirs(let other) = row { return other.key }
            return nil
        }
    }

    @Test func yourAlbumsNeverWaitForMusicBrainz() {
        let albums = [Album(id: "a1", name: "Dummy", year: 1994), Album(id: "a2", name: "Portishead", year: 1997)]
        let before = ArtistJoin.rows(albums: albums, groups: nil, index: nil)
        #expect(before == ArtistPage.rows(albums).map { ArtistJoin.Row.yours($0) }, "Phase 4's rows, before it answers")
        // MusicBrainz answered with nothing: still yours alone
        #expect(ArtistJoin.rows(albums: albums, groups: [], index: nil) == before)
    }

    @Test func anAlbumYouHaveIsNeverListedAgain() {
        let index = OwnedIndex([
            OwnedAlbum(path: "P/Dummy", artist: "Portishead", album: "Dummy", releaseMbid: Self.release(1),
                       releaseGroupMbid: Self.group(1)),
            OwnedAlbum(path: "P/Third (2018)", artist: "Portishead", album: "Third", releaseMbid: Self.release(4),
                       releaseGroupMbid: Self.group(2)),
        ])
        let albums = [
            // by its release, whatever Navidrome titles it
            Album(id: "a-third", name: "Third - 2018 Remaster", year: 2018, musicBrainzId: Self.release(4).uppercased()),
            // by its exact title, no folder tying it to another album
            Album(id: "a-self", name: "PORTISHEAD", year: 1997),
            Album(id: "a-dummy", name: "Dummy", year: 1994, musicBrainzId: Self.release(1)),
        ]
        let groups = [Self.dummy, Self.third, Self.selfTitled, Self.roseland, Self.undated]
        let rows = ArtistJoin.rows(albums: albums, groups: groups, index: index)
        #expect(Self.theirKeys(rows) == ["group:\(Self.group(4))", "group:\(Self.group(8))"], "Roseland and Untitled alone")
        #expect(Self.yoursKeys(rows) == ["album:a-third", "album:a-self", "album:a-dummy"])
        // before /library/owned has answered, the remaster's title can't say it is Third: Third is listed, and goes once
        // the library answers (the page waits for it a moment - drawsTheirs)
        let early = ArtistJoin.rows(albums: albums, groups: groups, index: nil)
        #expect(Self.theirKeys(early).contains("group:\(Self.group(2))"))
        #expect(!Self.theirKeys(early).contains("group:\(Self.group(1))"), "Dummy by its title alone")
        // two of MusicBrainz's albums under one title: a name can't say which, so neither is claimed by it
        let twins = [ReleaseGroup(id: Self.group(6), title: "Plain", firstReleaseDate: "2001"),
                     ReleaseGroup(id: Self.group(7), title: "plain", firstReleaseDate: "2003")]
        let plain = ArtistJoin.rows(albums: [Album(id: "a-plain", name: "Plain", year: 2001)], groups: twins, index: nil)
        #expect(Self.theirKeys(plain).count == 2 && Self.yoursKeys(plain) == ["album:a-plain"])
        // a folder tying an album to another group MusicBrainz doesn't list: never claimed by its title
        let bootleg = OwnedIndex([OwnedAlbum(path: "P/Roseland", artist: "Portishead", album: "Roseland NYC Live",
                                             releaseMbid: Self.release(7), releaseGroupMbid: Self.group(20))])
        let live = ArtistJoin.rows(albums: [Album(id: "a-live", name: "Roseland NYC Live", year: 1998,
                                                  musicBrainzId: Self.release(7))],
                                   groups: [Self.roseland], index: bootleg)
        #expect(Self.theirKeys(live) == ["group:\(Self.group(4))"])
    }

    @Test func theirAlbumsComeInAmongYoursNewestFirst() {
        let albums = [Album(id: "a-dummy", name: "Dummy", year: 1994), Album(id: "a-self", name: "Portishead", year: 1997),
                      Album(id: "a-none", name: "Demos")]
        let rows = ArtistJoin.rows(albums: albums, groups: [Self.dummy, Self.third, Self.undated, Self.roseland],
                                   index: OwnedIndex([]))
        #expect(rows.map(\.title) == ["Third", "Roseland NYC Live", "Portishead", "Dummy", "Demos", "Untitled"],
                "the newest year first, the undated last - yours and theirs alike, then by title")
        let lines: [String] = rows.compactMap { (row: ArtistJoin.Row) -> String? in
            if case .theirs(let other) = row { return MBArtistPage.line(other, personal: false) }
            return nil
        }
        #expect(lines == ["2008 \u{00B7} not in your library", "1998 \u{00B7} Live album \u{00B7} not in your library",
                          "not in your library"])
        // yours keep their own line: Navidrome's year, "in your library", unchanged
        if case .yours(let mine) = rows[2] {
            #expect(ArtistPage.line(mine, personal: false) == "1997 \u{00B7} in your library")
        } else {
            Issue.record("Portishead is yours")
        }
    }

    @Test func aTieOfYearAndTitleTakesTheKeysOrderYoursFirst() {
        let albums = [Album(id: "a1", name: "Untitled", year: 2001)]
        let group = ReleaseGroup(id: Self.group(9), title: "Untitled", firstReleaseDate: "2001")
        let twin = ReleaseGroup(id: Self.group(10), title: "untitled", firstReleaseDate: "2001")
        // two groups share the title, so neither claims the album: all three tie on year and title
        let rows = ArtistJoin.rows(albums: albums, groups: [group, twin], index: nil)
        #expect(Self.keys(rows) == ["album:a1", "group:\(Self.group(9))", "group:\(Self.group(10))"])
    }

    @Test func playPlaysWhatYouHaveAsBefore() {
        let albums = [Album(id: "a1", name: "Dummy", year: 1994), Album(id: "a2", name: "Dummy", year: 1994),
                      Album(id: "a3", name: "Third", year: 2008)]
        let rows = ArtistJoin.rows(albums: albums, groups: [Self.dummy, Self.roseland, Self.undated], index: nil)
        #expect(ArtistJoin.playOrder(rows) == ArtistPage.playOrder(ArtistPage.rows(albums)))
        #expect(ArtistJoin.playOrder(rows) == ["a3", "a1", "a2"], "two pressings both, as before; nothing of theirs")
    }

    @Test func theirRowsWaitForTheLibraryAMomentAndNeverOffline() {
        #expect(!ArtistJoin.drawsTheirs(online: false, indexKnown: true, waited: true), "offline: yours alone")
        #expect(!ArtistJoin.drawsTheirs(online: true, indexKnown: false, waited: false), "the library a moment")
        #expect(ArtistJoin.drawsTheirs(online: true, indexKnown: true, waited: false))
        #expect(ArtistJoin.drawsTheirs(online: true, indexKnown: false, waited: true), "no longer than that")
    }

    @Test func underTheRowsMusicBrainzSaysOneThing() {
        let foot = { (asking: Bool, answered: Bool, failed: Bool, truncated: Bool, holding: Bool, rows: Int) -> ArtistJoin.Foot in
            ArtistJoin.foot(asking: asking, answered: answered, failed: failed, truncated: truncated, holding: holding,
                            rows: rows)
        }
        #expect(foot(true, false, false, false, false, 3) == .loading, "asking")
        #expect(foot(true, true, false, false, false, 3) == .loading, "asked again, the last answer drawn meanwhile")
        #expect(foot(false, false, false, false, false, 3) == .loading, "not asked yet")
        #expect(foot(false, true, false, false, true, 3) == .loading, "answered, its rows waiting for the library")
        #expect(foot(false, false, true, false, false, 3) == .trouble, "failed: said once, under your albums")
        #expect(foot(false, false, true, false, true, 0) == .trouble, "said at once, not held for the library")
        #expect(foot(false, true, false, true, false, 500) == .truncated)
        #expect(foot(false, true, false, false, false, 0) == .noAlbums, "no row at all")
        #expect(foot(false, true, false, false, false, 1) == .nothing, "your albums and theirs drawn: nothing to say")
    }

    @Test func whoTheyAreOnMusicBrainz() {
        let artist = { (id: String?, albums: [Album]) -> ArtistWithAlbums in
            ArtistWithAlbums(Artist(id: "ar-1", name: "Portishead", musicBrainzId: id), albums: albums)
        }
        #expect(ArtistJoin.mbid(nil, index: OwnedIndex([])) == nil, "not before the artist answers")
        #expect(ArtistJoin.mbid(artist(" \(Self.portishead.uppercased())", []), index: nil) == Self.portishead)
        let folders = OwnedIndex([OwnedAlbum(path: "P/Dummy", artist: "Portishead", album: "Dummy",
                                             releaseMbid: Self.release(1), albumartistMbids: [Self.portishead])])
        let dummy = Album(id: "a1", name: "Dummy", musicBrainzId: Self.release(1))
        #expect(ArtistJoin.mbid(artist(nil, [dummy]), index: folders) == Self.portishead, "the folders say")
        #expect(ArtistJoin.mbid(artist(nil, [dummy]), index: nil) == nil, "nothing to say it")
        #expect(ArtistJoin.mbid(artist("not an id", [Album(id: "a2", name: "Third")]), index: folders) == Self.portishead,
                "by their name, with no release of theirs known")
        let collaboration = OwnedIndex([OwnedAlbum(path: "P/Dummy", artist: "Portishead", album: "Dummy",
                                                   releaseMbid: Self.release(1),
                                                   albumartistMbids: [Self.portishead, "cccccccc-0000-4000-8000-000000000002"])])
        #expect(ArtistJoin.mbid(artist(nil, [dummy]), index: collaboration) == nil, "a collaboration says nothing")
    }

    // MARK: by property

    static let titles = ["Dummy", "dummy", "Third", "Plain", "Glory Times", "Zebra", "Album", "Live", "Demos", ""]
    static let dates: [String?] = ["1994", "1994-08-22", "2001-02", "1997", "19xx", "", nil, "2008-04-28"]
    static let years: [Int?] = [1994, 1997, 2001, nil, 0, 2008]

    static func pick<T>(_ list: [T], _ random: inout ArtistTests.Seeded) -> T {
        list[Int(random.next() % UInt64(list.count))]
    }

    @Test func overSeededPagesYoursNeverMoveAndTheMergeKeepsTheWebsOrder() {
        var random = ArtistTests.Seeded(state: 2026_11_15)
        for round in 0..<400 {
            let groups = (0..<Int(random.next() % 9)).map { (n: Int) -> ReleaseGroup in
                ReleaseGroup(id: Self.group(100 * round + n), title: Self.pick(Self.titles, &random),
                             firstReleaseDate: Self.pick(Self.dates, &random), primaryType: "Album")
            }
            let releases = groups.indices.map { Self.release(100 * round + $0) }
            let folders = groups.indices.compactMap { (n: Int) -> OwnedAlbum? in
                random.next() % 2 == 0 ? nil : OwnedAlbum(path: "A/\(n)", artist: "A", album: groups[n].title,
                                                           releaseMbid: releases[n], releaseGroupMbid: groups[n].id)
            }
            let albums = (0..<Int(random.next() % 7)).map { (n: Int) -> Album in
                let release: String? = !releases.isEmpty && random.next() % 2 == 0 ? Self.pick(releases, &random) : nil
                return Album(id: "r\(round)-\(n)", name: Self.pick(Self.titles, &random), year: Self.pick(Self.years, &random),
                             musicBrainzId: release)
            }
            let index: OwnedIndex? = random.next() % 4 == 0 ? nil : OwnedIndex(folders)
            let rows = ArtistJoin.rows(albums: albums, groups: groups, index: index)
            let what = "round \(round)"
            #expect(Self.yoursKeys(rows) == ArtistPage.rows(albums).map(\.key), "\(what): yours as they were")
            #expect(Self.theirKeys(rows) == ArtistJoin.theirs(albums: albums, groups: groups, index: index).map(\.key),
                    "\(what): theirs in their order")
            #expect(Set(Self.keys(rows)).count == rows.count, "\(what): each once")
            // ASCII titles: the two orders agree, so the merge is the web's order over every row
            for (at, row) in rows.enumerated() where at > 0 {
                #expect(!ArtistJoin.before(row, rows[at - 1]), "\(what): \(row.key) after \(rows[at - 1].key)")
            }
            // an album you have is never one of theirs: no row of theirs holds a release Navidrome has of yours
            let navidromes = Set(albums.compactMap(\.musicBrainzId))
            for other in ArtistJoin.theirs(albums: albums, groups: groups, index: index) {
                #expect(other.releases.allSatisfy { !navidromes.contains($0) }, "\(what): \(other.key) holds one of yours")
            }
        }
    }
}
