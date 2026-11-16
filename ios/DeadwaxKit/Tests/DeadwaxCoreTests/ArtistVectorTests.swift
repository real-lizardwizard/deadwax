import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/artists/artist-vectors.json: what the web's TypeScript (lib/shelves.ts's artist rules, lib/artistPage.ts,
/// lib/yourLibrary.ts, lib/appFrame.ts) answers, written by ios/scripts/export-artist-vectors.cjs - never by hand - and
/// the shapes it is read into. The lists and albums in it are decoded by the real models (Artist, Album, IndexAlbum).
enum ArtistVectors {
    struct Vectors: Decodable {
        let words: Words
        let lists: [ListCase]
        let yours: [YoursCase]
        let rows: [RowsCase]
        let playOrders: [PlayOrderCase]
        let playsLine: [PlaysCase]
        let turns: [TurnsCase]
        let joined: [JoinedCase]
        let mbids: [MbidCase]
    }

    /// One of MusicBrainz's albums none of yours claims, as the web's artistRows makes its row.
    struct TheirRow: Decodable {
        let key: String
        let title: String
        let year: String?
        let held: Bool?
        let yours: Bool?
        let editions: Int
        let releases: [String]
        let kind: String?
        let line: String
        let personalLine: String
    }
    struct JoinedCase: Decodable {
        let name: String
        let held: [Album]
        let groups: [ReleaseGroup]
        let folders: [OwnedAlbum]?
        let claimed: [String]
        let theirs: [TheirRow]
    }
    struct MbidCase: Decodable {
        let name: String
        let artist: ArtistWithAlbums?
        let folders: [OwnedAlbum]?
        let mbid: String?
    }

    struct Words: Decodable {
        struct Order: Decodable { let id: String; let label: String }
        struct Saved: Decodable { let saved: String?; let order: String }
        struct Titles: Decodable { let artists, yourArtists, allArtists, allMusic: String }
        struct Typed: Decodable { let typed: String; let text: String }
        struct Count: Decodable { let count: Int?; let text: String }
        struct CountLine: Decodable { let count: Int?; let place: String?; let text: String }

        let orders: [Order]
        let saved: [Saved]
        let storageKey: String
        let titles: Titles
        let find, sortLabel, noArtists, noArtistsOfYours, emptyLibraryHow: String
        let noMatch: [Typed]
        let counts: [Count]
        let albumCountLine: [CountLine]
        let inYourLibrary, inTheCollection, artistGone: String
        let prefetchAtOnce, artistsKept, indexMin: Int
    }

    struct Group: Decodable { let key: String; let label: String?; let ids: [String] }
    struct Entry: Decodable { let label: String; let aria: String; let group: Int }
    struct Under: Decodable {
        let ids: [String]
        let groups: [Group]
        let index: [Entry]
        let showsIndex: Bool
        let count: String
    }
    struct Found: Decodable {
        let order: String
        let typed: String
        let finding: Bool
        let ids: [String]
        let heads: [String?]
        let sizes: [Int]
        let showsIndex: Bool
        let count: String
        let noMatch: String
    }
    struct ListCase: Decodable {
        let name: String
        let list: [Artist]
        let name_order: Under
        let albums_order: Under
        let finds: [Found]
    }

    struct YoursCase: Decodable { let name: String; let artists: [Artist]; let albums: [IndexAlbum]; let yours: [Artist] }

    struct Row: Decodable {
        let key: String
        let title: String
        let year: String?
        let albumId: String
        let coverArt: String?
        let yours: Bool
        let line: String
        let personalLine: String
    }
    struct RowsCase: Decodable { let name: String; let held: [Album]; let rows: [Row]; let playOrder: [String] }
    struct PlayOrderCase: Decodable { let albumIds: [String]; let playOrder: [String] }

    struct PlaysCase: Decodable {
        let albums, inHand: Int
        let settled: Bool
        let library: String
        let personal: Bool
        let text: String
    }

    struct Step: Decodable { let op: String; let item: Int?; let started: [Int] }
    struct TurnsCase: Decodable { let name: String; let count: Int; let limit: Int; let goingAtStart: Bool; let steps: [Step] }

    static func load() throws -> Vectors {
        try JSONDecoder().decode(Vectors.self, from: Fixtures.data("artists/artist-vectors.json"))
    }
}

/// The phone's artists against the web's own answers (export-artist-vectors.cjs).
@Suite struct ArtistVectorTests {
    private static func ids(_ places: [Int], in list: [Artist]) -> [String] {
        places.map { (place: Int) -> String in list[place].id }
    }

    @Test func theWordsAndNumbersAreTheWebs() throws {
        let words = try ArtistVectors.load().words
        #expect(words.orders.map(\.id) == ArtistOrder.allCases.map(\.rawValue))
        #expect(words.orders.map(\.label) == ArtistOrder.allCases.map(\.label))
        for saved in words.saved {
            #expect(ArtistOrder(saved: saved.saved).rawValue == saved.order, "saved \(String(describing: saved.saved))")
        }
        #expect(ArtistOrder.storageKey == words.storageKey)
        #expect(ArtistWords.artists == words.titles.artists && LibraryPage.artists.title == words.titles.artists)
        #expect(ArtistWords.title(.yours, personal: true) == words.titles.yourArtists)
        #expect(ArtistWords.title(.store, personal: true) == words.titles.allArtists)
        #expect(ArtistWords.title(.yours, personal: false) == words.titles.artists)
        #expect(ArtistWords.title(.store, personal: false) == words.titles.artists)
        #expect(LibraryWords.allMusic == words.titles.allMusic)
        #expect(ArtistWords.findPlaceholder == words.find)
        #expect(ArtistWords.sortLabel == words.sortLabel)
        #expect(ArtistWords.noArtists == words.noArtists)
        #expect(ArtistWords.noArtistsOfYours == words.noArtistsOfYours)
        #expect(LibraryWords.emptyLibraryHow == words.emptyLibraryHow)
        for each in words.noMatch {
            #expect(ArtistWords.noMatch(each.typed) == each.text)
        }
        for each in words.counts {
            #expect(Find.countText(each.count, one: "artist", many: "artists") == each.text)
        }
        for each in words.albumCountLine {
            let said = each.place.map { (place: String) -> String in ArtistWords.albumCountLine(each.count, place: place) }
                ?? ArtistWords.albumCountLine(each.count)
            #expect(said == each.text, "\(String(describing: each.count)) \(String(describing: each.place))")
        }
        #expect(Whose.inYourLibrary == words.inYourLibrary && Whose.inTheCollection == words.inTheCollection)
        #expect(ErrorWords.artistGone == words.artistGone)
        #expect(ArtistPage.atOnce == words.prefetchAtOnce)
        #expect(ArtistPage.kept == words.artistsKept)
        #expect(ShelfIndex.minimum == words.indexMin)
    }

    @Test func listsSortHeadAndIndexAsTheWebs() throws {
        for each in try ArtistVectors.load().lists {
            let shelf = ArtistShelf(each.list)
            let orders: [(ArtistOrder, ArtistVectors.Under)] = [(.name, each.name_order), (.albums, each.albums_order)]
            for (order, under) in orders {
                let what = "\(each.name), \(order)"
                let sorted = shelf.sorted(order)
                #expect(Self.ids(sorted, in: each.list) == under.ids, "\(what): the order")
                let groups = shelf.groups(sorted, order)
                #expect(groups.map(\.key) == under.groups.map(\.key), "\(what): the groups")
                #expect(groups.map(\.label) == under.groups.map(\.label), "\(what): the headers")
                #expect(groups.map { (group: ShelfGroup) -> [String] in Self.ids(group.items, in: each.list) }
                        == under.groups.map(\.ids), "\(what): each group's artists")
                let entries = ShelfIndex.entries(groups, order)
                #expect(entries.map(\.label) == under.index.map(\.label), "\(what): the index")
                #expect(entries.map(\.accessibility) == under.index.map(\.aria), "\(what): the index, spoken")
                #expect(entries.map(\.group) == under.index.map(\.group), "\(what): where each entry jumps")
                #expect(ShelfIndex.shows(order, count: sorted.count, typed: "") == under.showsIndex, "\(what): shown")
                let view = shelf.view(order, typed: "")
                #expect(view.countText == under.count, "\(what): the count")
                #expect(view.index == (under.showsIndex ? entries : nil), "\(what): the view's index")
            }
        }
    }

    @Test func findKeepsWhatTheWebsKeeps() throws {
        for each in try ArtistVectors.load().lists {
            let shelf = ArtistShelf(each.list)
            for found in each.finds {
                let order = try #require(ArtistOrder(rawValue: found.order))
                let what = "\(each.name), \(order), \"\(found.typed)\""
                let view = shelf.view(order, typed: found.typed)
                #expect(Find.finding(found.typed) == found.finding, "\(what): finding")
                #expect(Self.ids(view.found, in: each.list) == found.ids, "\(what): what Find keeps")
                #expect(view.groups.map(\.label) == found.heads, "\(what): the headers")
                #expect(view.groups.map { (group: ShelfGroup) -> Int in group.items.count } == found.sizes,
                        "\(what): the groups' sizes")
                #expect((view.index != nil) == found.showsIndex, "\(what): the index")
                #expect(view.countText == found.count, "\(what): the count")
                #expect(ArtistWords.noMatch(found.typed) == found.noMatch, "\(what): no match")
                // the filter alone, over the order, keeps the same
                #expect(Self.ids(shelf.filter(shelf.sorted(order), typed: found.typed), in: each.list) == found.ids)
            }
        }
    }

    @Test func yourArtistsAreTheWebs() throws {
        for each in try ArtistVectors.load().yours {
            #expect(YourArtists.of(each.artists, albums: each.albums) == each.yours, "\(each.name)")
        }
    }

    @Test func anArtistsRowsAreTheWebs() throws {
        for each in try ArtistVectors.load().rows {
            let rows = ArtistPage.rows(each.held)
            #expect(rows.map(\.key) == each.rows.map(\.key), "\(each.name): the order")
            #expect(rows.map(\.title) == each.rows.map(\.title), "\(each.name): the titles")
            #expect(rows.map(\.year) == each.rows.map(\.year), "\(each.name): the years")
            #expect(rows.map(\.albumId) == each.rows.map(\.albumId), "\(each.name): the albums")
            #expect(rows.map(\.coverArt) == each.rows.map(\.coverArt), "\(each.name): the covers")
            #expect(rows.map(\.yours) == each.rows.map(\.yours), "\(each.name): whose")
            #expect(rows.map { (row: ArtistPage.Row) -> String in ArtistPage.line(row, personal: false) }
                    == each.rows.map(\.line), "\(each.name): the lines")
            #expect(rows.map { (row: ArtistPage.Row) -> String in ArtistPage.line(row, personal: true) }
                    == each.rows.map(\.personalLine), "\(each.name): the lines with a library of your own")
            #expect(ArtistPage.playOrder(rows) == each.playOrder, "\(each.name): what Play plays")
        }
    }

    @Test func playsOrderOverAnyRowsIsTheWebs() throws {
        for each in try ArtistVectors.load().playOrders {
            let rows = each.albumIds.map { (id: String) -> ArtistPage.Row in
                ArtistPage.Row(key: "album:\(id)", title: id, year: nil, albumId: id, coverArt: nil, yours: false)
            }
            #expect(ArtistPage.playOrder(rows) == each.playOrder, "\(each.albumIds)")
        }
    }

    @Test func theLineUnderPlayIsTheWebs() throws {
        for each in try ArtistVectors.load().playsLine {
            let library = try #require(ArtistPage.Library(rawValue: each.library))
            let said = ArtistPage.playsLine(albums: each.albums, inHand: each.inHand, settled: each.settled,
                                            library: library, personal: each.personal)
            #expect(said == each.text, "\(each.albums) \(each.inHand) \(each.settled) \(each.library) \(each.personal)")
        }
    }

    @Test func inTurnsStartsWhatTheWebsStarts() throws {
        for each in try ArtistVectors.load().turns {
            var turns = InTurns(count: each.count, limit: each.limit)
            var going = each.goingAtStart
            var started: [Int] = []
            for step in each.steps {
                switch step.op {
                case "begin": started += turns.begin(going: { going })
                case "stop": going = false
                case "go": going = true
                default:
                    if let next = turns.settled(going: { going }) { started.append(next) }
                }
                #expect(started == step.started, "\(each.name), after \(step.op) \(String(describing: step.item))")
            }
        }
    }

    // MARK: the albums you don't have (15 Nov)

    @Test func theAlbumsYouDontHaveAreTheWebs() throws {
        let cases = try ArtistVectors.load().joined
        #expect(cases.count == 92)
        for each in cases {
            let index = each.folders.map { OwnedIndex($0) }
            let theirs = ArtistJoin.theirs(albums: each.held, groups: each.groups, index: index)
            #expect(theirs.map(\.key) == each.theirs.map(\.key), "\(each.name): which, in order")
            #expect(theirs.map(\.title) == each.theirs.map(\.title), "\(each.name): the titles")
            #expect(theirs.map(\.year) == each.theirs.map(\.year), "\(each.name): the years")
            #expect(theirs.map(\.held) == each.theirs.map(\.held), "\(each.name): what the library holds")
            #expect(theirs.map(\.yours) == each.theirs.map(\.yours), "\(each.name): whose")
            #expect(theirs.map(\.editions) == each.theirs.map(\.editions), "\(each.name): the pressings")
            #expect(theirs.map(\.releases) == each.theirs.map(\.releases), "\(each.name): what the bridge is asked")
            #expect(theirs.map(\.kind) == each.theirs.map(\.kind), "\(each.name): the kinds")
            #expect(theirs.map { (row: MBArtistPage.Row) -> String in MBArtistPage.line(row, personal: false) }
                    == each.theirs.map(\.line), "\(each.name): the lines")
            #expect(theirs.map { (row: MBArtistPage.Row) -> String in MBArtistPage.line(row, personal: true) }
                    == each.theirs.map(\.personalLine), "\(each.name): the lines with a library of your own")
            let claimed = ArtistJoin.claimed(each.held, each.groups, index: index).map { (key: FoldKey) -> String in
                "group:" + String(decoding: key.units, as: UTF16.self)
            }
            #expect(Set(claimed) == Set(each.claimed) && claimed.count == each.claimed.count,
                    "\(each.name): the groups an album of yours claims")
            // the page: your albums as Phase 4 drew them and in that order, theirs in theirs' order, each once
            let rows = ArtistJoin.rows(albums: each.held, groups: each.groups, index: index)
            let mine = rows.compactMap { (row: ArtistJoin.Row) -> String? in
                if case .yours(let yours) = row { return yours.key }
                return nil
            }
            let other = rows.compactMap { (row: ArtistJoin.Row) -> String? in
                if case .theirs(let theirs) = row { return theirs.key }
                return nil
            }
            #expect(mine == ArtistPage.rows(each.held).map(\.key), "\(each.name): your albums, as they were")
            #expect(other == each.theirs.map(\.key), "\(each.name): theirs, in the web's order")
            #expect(Set(rows.map(\.key)).count == rows.count, "\(each.name): each row once")
            #expect(ArtistJoin.playOrder(rows) == ArtistPage.playOrder(ArtistPage.rows(each.held)),
                    "\(each.name): Play plays what you have, as before")
        }
    }

    @Test func whoTheyAreOnMusicBrainzIsTheWebs() throws {
        let cases = try ArtistVectors.load().mbids
        #expect(cases.count == 17)
        for each in cases {
            #expect(ArtistJoin.mbid(each.artist, index: each.folders.map { OwnedIndex($0) }) == each.mbid, "\(each.name)")
        }
    }
}
