import Foundation
import Testing
@testable import DeadwaxCore

/// The Library's sorts, headers and Find (lib/shelves.ts): the fixture lists replayed, and ui/test/shelves.sim.cjs's
/// and whose.sim.cjs's own checks.
@Suite struct LibraryShelvesTests {
    static let utc = TimeZone(identifier: "UTC")!

    static func decode(_ json: String) throws -> [IndexAlbum] {
        try JSONDecoder().decode([IndexAlbum].self, from: Data(json.utf8))
    }

    /// shelves.sim's ALBUMS: "The Beatles" and "Beatles Tribute", "Björk", "&", digit-led "10cc" and "2Pac", a
    /// non-Latin name, an empty artist, undated and 0-year albums, ties, a `created` that won't parse, and the dev
    /// stand-in's float.
    static let simAlbums = """
    [{"id":"abbey","name":"Abbey Road","artist":"The Beatles","year":1969,"created":"2026-09-02T10:00:00Z","played":"2026-10-01T10:00:00Z","playCount":3},
     {"id":"help","name":"Help!","artist":"The Beatles","year":1965,"created":"2026-10-05T10:00:00Z"},
     {"id":"tribute","name":"Tribute","artist":"Beatles Tribute","year":2001,"created":"2026-10-06T10:00:00Z","played":"2026-10-15T10:00:00Z","playCount":1},
     {"id":"debut","name":"Debut","artist":"Björk","year":1993,"created":"not a date"},
     {"id":"post","name":"Post","artist":"bjork","year":0,"created":"2026-10-06T11:00:00Z"},
     {"id":"cc","name":"Sheet Music","artist":"10cc","year":1974,"created":"2026-08-31T23:59:59Z","played":"2026-10-14T10:00:00Z","playCount":3},
     {"id":"pac","name":"Me Against the World","artist":"2Pac","created":"2026-10-07T10:00:00Z"},
     {"id":"sakamoto","name":"async","artist":"坂本龍一","year":2017},
     {"id":"nobody","name":"Untitled","artist":"","year":1999,"created":1729000000.5},
     {"id":"simon","name":"Bookends","artist":"Simon & Garfunkel","year":1968,"created":"2026-10-06T10:00:00Z","playCount":0},
     {"id":"debut2","name":"Debut","artist":"Björk","year":1993}]
    """

    static func shelf(_ json: String) throws -> Shelf { Shelf(try decode(json), zone: utc) }

    static func ids(_ shelf: Shelf, _ places: [Int]) -> [String] { places.map { shelf.albums[$0].id } }

    static func heads(_ groups: [ShelfGroup]) -> [String] { groups.map { "\($0.label ?? "nil") \($0.items.count)" } }

    // MARK: - the fixtures

    @Test func everyListSortsHeadsAndFindsAsTheTypeScriptDoes() throws {
        let fixture = try LibraryFixtures.load("shelves", as: ShelvesFixture.self)
        #expect(fixture.lists.count >= 20)
        var misses = LibraryFixtures.Misses()
        var checked = 0
        for list in fixture.lists {
            let shelf = Shelf(list.albums, zone: Self.utc)
            for (n, typed) in list.typed.enumerated() where Find.noMatchText("albums", typed: typed) != list.noMatch[n]
                || LibraryWords.noMatch(typed) != list.noMatch[n] {
                misses.add("\(list.name) no match \(typed): \(Find.noMatchText("albums", typed: typed)), TS \(list.noMatch[n])")
            }
            for case_ in list.sorts {
                let sort = try #require(AlbumSort(rawValue: case_.sort))
                let by = try #require(AddedBy(rawValue: case_.by))
                let name = "\(list.name) \(case_.sort)/\(case_.by)"
                let sorted = shelf.sorted(sort, by: by)
                if sorted != case_.order { misses.add("\(name) order: \(sorted), TS \(case_.order)") }
                let groups = shelf.groups(sorted, sort, by: by, whole: sorted)
                if groups.map(\.label) != case_.heads || groups.map(\.items.count) != case_.sizes {
                    misses.add("\(name) heads: \(Self.heads(groups)), TS \(case_.heads) \(case_.sizes)")
                }
                let index = ShelfIndex.entries(groups, sort).map { ShelvesFixture.LabelGroup(label: $0.label, group: $0.group) }
                if index != case_.index { misses.add("\(name) index: \(index), TS \(case_.index)") }
                for (n, typed) in list.typed.enumerated() {
                    let expected = case_.finds[n]
                    let view = shelf.view(sort, by: by, typed: typed, sorted: sorted)
                    let what = "\(name) typed \(LibraryFixtures.spelled(typed))"
                    if view.found != expected.found { misses.add("\(what) found: \(view.found), TS \(expected.found)") }
                    if view.groups.map(\.label) != expected.heads || view.groups.map(\.items.count) != expected.sizes {
                        misses.add("\(what) heads: \(Self.heads(view.groups)), TS \(expected.heads) \(expected.sizes)")
                    }
                    if (view.index != nil) != expected.shows { misses.add("\(what) index shown: \(view.index != nil), TS \(expected.shows)") }
                    if let drawn = view.index, drawn.map({ ShelvesFixture.LabelGroup(label: $0.label, group: $0.group) }) != case_.index {
                        misses.add("\(what) index: \(drawn)")
                    }
                    if view.countText != expected.count { misses.add("\(what) count: \(view.countText), TS \(expected.count)") }
                    if Find.finding(typed) && shelf.filter(sorted, typed: typed) != expected.found { misses.add("\(what) filter") }
                    checked += 1
                }
            }
        }
        #expect(checked > 1000)
        #expect(misses.isEmpty, "\(misses)")
    }

    // MARK: - shelves.sim "the seven album sorts" (the five Phase 1 has)

    @Test func theSortsOfferedInThePickersOrder() throws {
        #expect(AlbumSort.allCases.map { [$0.rawValue, $0.label] } == [
            ["alphabeticalByArtist", "Artist"], ["alphabeticalByName", "Title"], ["newest", "Recently added"],
            ["byYearDesc", "Year, newest first"], ["byYearAsc", "Year, oldest first"],
        ])
        let words = try LibraryFixtures.load("words", as: WordsFixture.self)
        #expect(AlbumSort.allCases.map { [$0.rawValue, $0.label] } == words.sorts)
        #expect(AlbumSort.default.rawValue == words.defaultSort)
    }

    @Test func theFiveSortsOfTheSimsAlbums() throws {
        let shelf = try Self.shelf(Self.simAlbums)
        let sorted = { (sort: AlbumSort) in Self.ids(shelf, shelf.sorted(sort)) }
        #expect(sorted(.alphabeticalByArtist) == ["help", "abbey", "tribute", "debut", "debut2", "post", "simon", "nobody", "cc", "pac", "sakamoto"])
        #expect(sorted(.alphabeticalByName) == ["abbey", "sakamoto", "simon", "debut", "debut2", "help", "pac", "post", "cc", "tribute", "nobody"])
        #expect(sorted(.newest) == ["pac", "post", "tribute", "simon", "help", "abbey", "cc", "debut", "sakamoto", "nobody", "debut2"])
        #expect(sorted(.byYearDesc) == ["sakamoto", "tribute", "nobody", "debut", "debut2", "cc", "abbey", "simon", "help", "post", "pac"])
        #expect(sorted(.byYearAsc) == ["help", "simon", "abbey", "cc", "debut", "debut2", "nobody", "tribute", "sakamoto", "post", "pac"])
        //? nothing left out or doubled, the list handed in untouched
        #expect(shelf.sorted(.alphabeticalByArtist).count == 11 && shelf.sorted(.newest).count == 11)
        #expect(Set(shelf.sorted(.byYearAsc)) == Set(0..<11))
        #expect(shelf.albums[0].id == "abbey")
    }

    @Test func theHeadersEachSortGroupsBy() throws {
        let shelf = try Self.shelf(Self.simAlbums)
        let heads = { (sort: AlbumSort) in Self.heads(shelf.groups(shelf.sorted(sort), sort)) }
        #expect(heads(.alphabeticalByArtist) == ["B 6", "S 1", "# 4"])
        #expect(heads(.alphabeticalByName) == ["A 2", "B 1", "D 2", "H 1", "M 1", "P 1", "S 1", "T 1", "U 1"])
        #expect(heads(.newest) == ["October 2026 5", "September 2026 1", "August 2026 1", "Date unknown 4"])
        #expect(heads(.byYearDesc) == ["2017 1", "2001 1", "1999 1", "1993 2", "1974 1", "1969 1", "1968 1", "1965 1", "No year 2"])
        #expect(heads(.byYearAsc) == ["1965 1", "1968 1", "1969 1", "1974 1", "1993 2", "1999 1", "2001 1", "2017 1", "No year 2"])
        #expect(Shelf([]).groups([], .alphabeticalByArtist) == [])
        #expect(Shelf([]).sorted(.newest, by: .you) == [])
    }

    // MARK: - shelves.sim "Recently added over YOUR albums" (2.0.11)

    static let yours = """
    [{"id":"late","name":"Old in the collection, new to you","artist":"a","starred":"2026-10-20T10:00:00Z","created":"2024-01-01T00:00:00Z"},
     {"id":"tA","name":"Starred together A","artist":"a","starred":"2026-10-10T00:00:00Z","created":"2026-03-01T00:00:00Z"},
     {"id":"tB","name":"Starred together B","artist":"a","starred":"2026-10-10T00:00:00Z","created":"2026-05-01T00:00:00Z"},
     {"id":"amperfy","name":"Starred in Amperfy","artist":"a","starred":"2026-10-05T09:00:00Z","created":"2026-10-04T00:00:00Z"},
     {"id":"noStar","name":"No star (never in your list)","artist":"a","created":"2026-09-15T00:00:00Z"},
     {"id":"far","name":"A minute after the seed","artist":"a","starred":"2026-09-01T12:01:00Z","created":"2020-01-01T00:00:00Z"},
     {"id":"s3","name":"Seed 3","artist":"a","starred":"2026-09-01T12:00:03Z","created":"2026-08-15T00:00:00Z"},
     {"id":"s4","name":"Seed 4","artist":"a","starred":"2026-09-01T12:00:03.000Z"},
     {"id":"s2","name":"Seed 2","artist":"a","starred":"2026-09-01T11:59:50Z","created":"2026-06-01T00:00:00Z"},
     {"id":"s1","name":"Seed 1","artist":"a","starred":"2026-09-01T11:59:25Z","created":"2026-08-01T00:00:00Z"},
     {"id":"none","name":"No date at all","artist":"a"}]
    """

    @Test func recentlyAddedOverYourAlbumsIsWhenYouAddedEach() throws {
        #expect(Shelf.sameMomentMs == 30_000)
        let shelf = try Self.shelf(Self.yours)
        #expect(Self.ids(shelf, shelf.sorted(.newest, by: .you)) == ["late", "tB", "tA", "amperfy", "noStar", "far", "s3", "s1", "s2", "s4", "none"])
        //? the same list as the collection's: by created, the stars passed over
        #expect(Self.ids(shelf, shelf.sorted(.newest)) == ["amperfy", "noStar", "s3", "s1", "s2", "tB", "tA", "late", "far", "s4", "none"])
        for sort in [AlbumSort.alphabeticalByArtist, .alphabeticalByName, .byYearDesc] {
            #expect(shelf.sorted(sort, by: .you) == shelf.sorted(sort, by: .collection))
        }
        #expect(shelf.sorted(.newest, by: .you).count == 11 && shelf.albums[0].id == "late")
        #expect(Self.heads(shelf.groups(shelf.sorted(.newest, by: .you), .newest, by: .you)) == ["October 2026 4", "September 2026 6", "Date unknown 1"])
    }

    @Test func oneMomentOverAMonthsEndIsUnderOneHeader() throws {
        let shelf = try Self.shelf("""
        [{"id":"m2","name":"m2","artist":"a","starred":"2026-09-01T00:00:05Z","created":"2025-01-01T00:00:00Z"},
         {"id":"m1","name":"m1","artist":"a","starred":"2026-08-31T23:59:50Z","created":"2026-01-01T00:00:00Z"},
         {"id":"aug","name":"aug","artist":"a","starred":"2026-08-20T00:00:00Z","created":"2026-01-02T00:00:00Z"}]
        """)
        let groups = shelf.groups(shelf.sorted(.newest, by: .you), .newest, by: .you)
        #expect(groups.map { "\($0.label ?? "") \(Self.ids(shelf, $0.items))" } == ["September 2026 [\"m1\", \"m2\"]", "August 2026 [\"aug\"]"])
    }

    /// (review) Find narrowing a moment: its headers from the WHOLE list's moments - a moment cut again from what
    /// Find left would split over the month's end, out of order.
    @Test func findLeavingOutAMomentsMiddleKeepsItsHeader() throws {
        let shelf = try Self.shelf("""
        [{"id":"a","name":"Alpha","artist":"x","starred":"2026-09-01T00:00:10Z","created":"2025-01-01T00:00:00Z"},
         {"id":"b","name":"Beta","artist":"x","starred":"2026-08-31T23:59:50Z","created":"2026-03-01T00:00:00Z"},
         {"id":"c","name":"Gamma","artist":"x","starred":"2026-08-31T23:59:30Z","created":"2026-06-01T00:00:00Z"},
         {"id":"d","name":"Delta","artist":"x","starred":"2026-08-20T00:00:00Z","created":"2026-01-02T00:00:00Z"}]
        """)
        let sorted = shelf.sorted(.newest, by: .you)
        #expect(Self.ids(shelf, sorted) == ["c", "b", "a", "d"])
        let found = sorted.filter { shelf.albums[$0].id != "b" }
        let describe = { (groups: [ShelfGroup]) in groups.map { "\($0.label ?? "") \(Self.ids(shelf, $0.items))" } }
        #expect(describe(shelf.groups(found, .newest, by: .you, whole: sorted)) == ["September 2026 [\"c\", \"a\"]", "August 2026 [\"d\"]"])
        #expect(describe(shelf.groups(sorted, .newest, by: .you)) == ["September 2026 [\"c\", \"b\", \"a\"]", "August 2026 [\"d\"]"])
        //? without the whole list, the two left would be 40 s apart - two moments, two months
        #expect(describe(shelf.groups(found, .newest, by: .you)) == ["August 2026 [\"c\"]", "September 2026 [\"a\"]", "August 2026 [\"d\"]"])
    }

    @Test func insideAMomentTheNewerStarFirstWhenCreatedTies() throws {
        let shelf = try Self.shelf("""
        [{"id":"older","name":"older","artist":"a","starred":"2026-09-01T12:00:00Z","created":"2026-01-01T00:00:00Z"},
         {"id":"newer","name":"newer","artist":"a","starred":"2026-09-01T12:00:05Z","created":"2026-01-01T00:00:00Z"},
         {"id":"olderBare","name":"olderBare","artist":"a","starred":"2026-09-01T11:59:50Z"},
         {"id":"newerBare","name":"newerBare","artist":"a","starred":"2026-09-01T11:59:55Z"}]
        """)
        #expect(Self.ids(shelf, shelf.sorted(.newest, by: .you)) == ["newer", "older", "newerBare", "olderBare"])
    }

    @Test func theCollectionsListGoesByCreatedEvenWhereAlbumsCarryAStar() throws {
        let shelf = try Self.shelf("""
        [{"id":"c1","name":"c1","artist":"a","created":"2026-10-01T00:00:00Z","starred":"2026-10-20T00:00:00Z"},
         {"id":"c2","name":"c2","artist":"a","created":"2026-10-10T00:00:00Z"},
         {"id":"c3","name":"c3","artist":"a","created":"2026-09-01T00:00:00Z","starred":"2026-10-22T00:00:00Z"}]
        """)
        #expect(Self.ids(shelf, shelf.sorted(.newest)) == ["c2", "c1", "c3"])
        #expect(Self.ids(shelf, shelf.sorted(.newest, by: .collection)) == ["c2", "c1", "c3"])
        #expect(Self.heads(shelf.groups(shelf.sorted(.newest), .newest)) == ["October 2026 2", "September 2026 1"])
        #expect(Self.ids(shelf, shelf.sorted(.newest, by: .you)) == ["c3", "c1", "c2"])
    }

    /// The thirty seconds are to the album before, chained: a seed of stars 25 s apart is one moment however long.
    @Test func aMomentChainsFromOneStarToTheNext() {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        let albums = (0..<10).map { n in
            IndexAlbum(id: "s\(n)", name: "s\(n)", artist: "a",
                       starred: ISO8601DateFormatter().string(from: base.addingTimeInterval(Double(-25 * n))))
        }
        let shelf = Shelf(albums, zone: Self.utc)
        #expect(shelf.moments(Array(albums.indices)).count == 1)
        let apart = (0..<3).map { n in
            IndexAlbum(id: "t\(n)", starred: ISO8601DateFormatter().string(from: base.addingTimeInterval(Double(-31 * n))))
        }
        #expect(Shelf(apart, zone: Self.utc).moments([0, 1, 2]).count == 3)
    }

    // MARK: - whose.sim "your library: your starred albums, in the order chosen"

    @Test func yourStarredAlbumsInTheOrderChosen() throws {
        let shelf = try Self.shelf("""
        [{"id":"a","name":"The Slow Rush","artist":"Tame Impala","year":2020,"created":"2026-10-01T00:00:00Z","played":"2026-10-14T00:00:00Z"},
         {"id":"b","name":"Dummy","artist":"Portishead","year":1994,"created":"2026-10-10T00:00:00Z"},
         {"id":"c","name":"Third","artist":"Portishead","year":2008,"created":"2026-09-01T00:00:00Z","played":"2026-10-15T00:00:00Z"},
         {"id":"d","name":"Abbey Road","artist":"The Beatles","year":1969}]
        """)
        #expect(Self.ids(shelf, shelf.sorted(.newest, by: .you)) == ["b", "a", "c", "d"])
        #expect(Self.ids(shelf, shelf.sorted(.alphabeticalByArtist, by: .you)) == ["d", "b", "c", "a"])
        #expect(Self.ids(shelf, shelf.sorted(.alphabeticalByName, by: .you)) == ["d", "b", "a", "c"])
    }

    /// Code-unit order under Artist: "방탄" (jamo) before "一", U+20000 (a surrogate pair) before U+FA0E.
    @Test func otherScriptsInJavaScriptsOrder() throws {
        let shelf = Shelf([IndexAlbum(id: "one", artist: "一"), IndexAlbum(id: "bts", artist: "방탄"),
                           IndexAlbum(id: "fa0e", artist: "\u{FA0E}"), IndexAlbum(id: "astral", artist: "\u{20000}")], zone: Self.utc)
        #expect(Self.ids(shelf, shelf.sorted(.alphabeticalByArtist)) == ["bts", "one", "astral", "fa0e"])
    }

    // MARK: - a sort read from storage

    @Test func aSortReadFromStorage() {
        let saved: [String?] = ["newest", "alphabeticalByArtist", "alphabeticalByName", "byYearDesc", "byYearAsc",
                                "starred", "random", "", nil, "Newest", "recent", "frequent"]
        #expect(saved.map { AlbumSort(saved: $0).rawValue } == ["newest", "alphabeticalByArtist", "alphabeticalByName", "byYearDesc",
            "byYearAsc", "alphabeticalByArtist", "alphabeticalByArtist", "alphabeticalByArtist", "alphabeticalByArtist",
            "alphabeticalByArtist", "alphabeticalByArtist", "alphabeticalByArtist"])
        #expect(AlbumSort.default == .alphabeticalByArtist)
    }

    // MARK: - shelves.sim "Find"

    @Test func find() throws {
        let shelf = try Self.shelf(Self.simAlbums)
        let all = Array(shelf.albums.indices)
        let found = { (typed: String) in Self.ids(shelf, shelf.filter(all, typed: typed)) }
        #expect(found("beatles road") == ["abbey"])
        #expect(found("road BEATLES") == ["abbey"])
        #expect(found("help") == ["help"])
        #expect(found("beatles") == ["abbey", "help", "tribute"])
        #expect(found("bjork") == ["debut", "post", "debut2"])
        #expect(found("BJÖRK post") == ["post"])
        #expect(found("simon and") == ["simon"])
        #expect(found("&") == ["simon"])
        #expect(found("the beatles abbey") == ["abbey"])
        #expect(found("eat") == ["abbey", "help", "tribute"])
        #expect(found("").count == 11 && found("   ").count == 11)
        #expect(!Find.finding("  ") && Find.finding("a"))
        let deluxe = Shelf(shelf.albums + [IndexAlbum(id: "dlx", name: "Dummy (Deluxe Edition)", artist: "Portishead")], zone: Self.utc)
        #expect(Self.ids(deluxe, deluxe.filter(Array(deluxe.albums.indices), typed: "deluxe")) == ["dlx"])
    }

    @Test func theCountAndTheWordsWhenNothingMatches() {
        #expect(Find.filteredCountText(shown: 12, total: 3012, one: "album", many: "albums") == "12 of 3012 albums")
        #expect(Find.filteredCountText(shown: 1, total: 1, one: "album", many: "albums") == "1 of 1 album")
        #expect(Find.filteredCountText(shown: 0, total: 2, one: "artist", many: "artists") == "0 of 2 artists")
        #expect(Find.noMatchText("albums", typed: " dumy ") == "No albums match \u{201C}dumy\u{201D}.")
        #expect(Find.noMatchText("artists", typed: "x") == "No artists match \u{201C}x\u{201D}.")
        #expect(Find.countText(3012, one: "album", many: "albums") == "3012 albums")
        #expect(Find.countText(1, one: "album", many: "albums") == "1 album")
        #expect(Find.countText(0, one: "album", many: "albums") == "0 albums")
        #expect(Find.countText(nil, one: "album", many: "albums") == "")
    }

    @Test func oneScreensView() throws {
        let shelf = try Self.shelf(Self.simAlbums)
        let plain = shelf.view(.alphabeticalByArtist, by: .collection, typed: "")
        #expect(plain.countText == "11 albums")
        #expect(plain.index == nil)                                    //? 11 albums: under INDEX_MIN
        #expect(plain.found == plain.sorted)
        let finding = shelf.view(.alphabeticalByArtist, by: .collection, typed: "bjork")
        #expect(finding.countText == "3 of 11 albums")
        #expect(Self.ids(shelf, finding.found) == ["debut", "debut2", "post"])
        #expect(Self.heads(finding.groups) == ["B 3"])
        let many = Shelf((0..<60).map { IndexAlbum(id: "a\($0)", name: "Album \($0)", artist: $0 % 2 == 0 ? "Portishead" : "Björk") }, zone: Self.utc)
        let drawn = many.view(.alphabeticalByArtist, by: .collection, typed: "")
        #expect(drawn.index?.count == 27)
        #expect(many.view(.alphabeticalByArtist, by: .collection, typed: "album").index == nil)
        #expect(many.view(.newest, by: .collection, typed: "").index == nil)
    }

    // MARK: - decoding /album_index

    @Test func theAnswerDecodesLeniently() throws {
        let albums = try Self.decode(Self.simAlbums)
        #expect(albums.count == 11)
        let nobody = try #require(albums.first { $0.id == "nobody" })
        #expect(nobody.created == nil)                                  //? the float: no date, never a failed list
        #expect(nobody.artist == "")
        let post = try #require(albums.first { $0.id == "post" })
        #expect(post.year == 0 && AlbumKeys(post).year == nil)
        #expect(AlbumKeys(post).initial == "B")
        let odd = try JSONDecoder().decode(IndexAlbum.self, from: Data(#"{"id":"x","name":null,"year":"1994","duration":245.5,"songCount":12,"musicBrainzId":""}"#.utf8))
        #expect(odd.name == nil && odd.year == nil && odd.duration == 245.5 && odd.songCount == 12 && odd.musicBrainzId == "")
        let bare = try JSONDecoder().decode(IndexAlbum.self, from: Data(#"{"id":"x"}"#.utf8))
        #expect(AlbumKeys(bare).initial == "#" && AlbumKeys(bare).title == FoldKey(""))
        #expect(throws: (any Error).self) { try JSONDecoder().decode(IndexAlbum.self, from: Data(#"{"name":"no id"}"#.utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(IndexAlbum.self, from: Data(#"{"id":7}"#.utf8)) }
        let answer = try JSONDecoder().decode(AlbumIndexAnswer.self, from: Data(#"{"albums":[{"id":"a"}],"truncated":true}"#.utf8))
        #expect(answer.albums.map(\.id) == ["a"] && answer.truncated)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(AlbumIndexAnswer.self, from: Data(#"{"albums":[]}"#.utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(AlbumIndexAnswer.self, from: Data(#"{"truncated":false}"#.utf8)) }
    }

    /// Every field the phone reads is one of the route's INDEX_FIELDS (src/routes/navidrome.py) - one it strips
    /// would always be nil.
    @Test func theFieldsReadAreTheRoutesFourteen() {
        #expect(IndexAlbum.fieldNames == ["id", "name", "artist", "artistId", "coverArt", "year", "genre", "created", "played",
                                          "playCount", "starred", "musicBrainzId", "songCount", "duration"])
    }

    // MARK: - the screen's body and words

    @Test func whatAnAlbumsScreenDraws() throws {
        let words = try LibraryFixtures.load("words", as: WordsFixture.self)
        #expect(AlbumListBody.of(.yours, list: nil, failed: false, found: 0, typed: "") == .loading)
        #expect(AlbumListBody.of(.store, list: nil, failed: true, found: 0, typed: "") == .failed)
        #expect(AlbumListBody.of(.yours, list: [], failed: false, found: 0, typed: "") == .emptyLibrary)
        #expect(AlbumListBody.of(.store, list: [], failed: true, found: 0, typed: "x") == .noAlbums)
        let one = [IndexAlbum(id: "a")]
        #expect(AlbumListBody.of(.store, list: one, failed: false, found: 0, typed: " dumy ") == .noMatch("No albums match \u{201C}dumy\u{201D}."))
        #expect(AlbumListBody.of(.yours, list: one, failed: true, found: 1, typed: "") == .albums)
        #expect(LibraryWords.title(.yours, personal: true) == words.titles.yours)
        #expect(LibraryWords.title(.store, personal: false) == words.titles.albums)
        #expect(LibraryWords.title(.store, personal: true) == words.titles.store)
        #expect(LibraryWords.allAlbums == words.allAlbumsRow && LibraryWords.allMusic == words.allMusic)
        #expect(LibraryWords.recentlyAdded == words.titles.recent)
        #expect(LibraryWords.emptyLibrary == words.emptyLibrary && LibraryWords.emptyLibraryHow == words.emptyLibraryHow)
        #expect(LibraryWords.noAlbums == words.noAlbums && LibraryWords.couldntRefresh == words.couldntRefresh)
        #expect(LibraryWords.truncated == words.truncated && LibraryWords.findPlaceholder == words.findPlaceholder)
        #expect(LibraryWords.sortLabel == words.sortLabel && LibraryWords.tryAgain == words.tryAgain)
        #expect(LibraryWords.loading == words.loading && LibraryWords.seeAllMusic == words.seeAllMusic)
        #expect(LibraryWords.newMark == words.newMark && LibraryWords.newMarkSpoken == words.newMarkSpoken)
        #expect(Shelf.sameMomentMs == words.sameMomentMs && ShelfIndex.minimum == words.indexMin)
        #expect(Fold.otherInitial == words.otherInitial && AlbumTime.dateUnknown == words.dateUnknown && Shelf.noYear == words.noYear)
        #expect(AlbumIndexState.freshMs == words.freshMs && PersonalLibrary.breakGlassUser == words.breakGlassUser)
    }

    /// Not a bound to hold the phone to - a number to read in the log: 3,000 albums' keys and the five sorts.
    @Test func threeThousandAlbums() {
        let names = ["The Beatles", "Björk", "Portishead", "10cc", "Massive Attack", "坂本龍一", "방탄소년단"]
        let albums = (0..<3000).map { n in
            IndexAlbum(id: "al-\(n)", name: "Album \(n % 97)", artist: names[n % names.count], year: 1960 + n % 60,
                       created: "2026-\(String(format: "%02d", 1 + n % 12))-01T00:00:00Z", starred: "2026-10-01T00:\(String(format: "%02d", n % 60)):00Z")
        }
        let start = Date()
        let shelf = Shelf(albums, zone: Self.utc)
        let made = Date().timeIntervalSince(start)
        var counts: [Int] = []
        for sort in AlbumSort.allCases {
            let sorted = shelf.sorted(sort, by: .you)
            counts.append(shelf.groups(sorted, sort, by: .you).reduce(0) { $0 + $1.items.count })
        }
        print("Library: 3,000 albums' keys in \(Int(made * 1000)) ms; the five sorts and their headers in \(Int(Date().timeIntervalSince(start) * 1000 - made * 1000)) ms")
        #expect(counts == [3000, 3000, 3000, 3000, 3000])
    }
}
