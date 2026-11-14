import Foundation
import Testing
@testable import DeadwaxCore

/// Artists (Phase 4, slice 4 - phase4-library.md 2.6), by hand and by property where the rules have edges: the answers
/// decoded leniently and the two calls; the orders' laws over seeded random lists (a permutation, `#` last, ties in
/// Navidrome's order, the groups the order cut into runs, the index's jumps); Find's; an artist's rows and their ties;
/// inTurns never running more than its limit; the album asks over every interleaving of answers and failures; Play's and
/// Shuffle's plan; offline; the album page's artist line. The web's own answers are ArtistVectorTests'.
@Suite struct ArtistTests {
    /// A seeded generator, so a failing case is the same case every run.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    static let names: [String] = ["The Beatles", "beatles", "Björk", "ABBA", "a-ha", "!!!", "2Pac", "", "Ølafur",
                                  "宇多田ヒカル", "Zola", "zZz", "Low", "low", "LOW", "The", "(Untitled)", "Édith",
                                  "Simon & Garfunkel", "Sigur Rós", "Mogwai", "Air", "air", "808 State", "Кино"]

    static func randomArtists(_ count: Int, _ random: inout Seeded) -> [Artist] {
        (0..<count).map { (at: Int) -> Artist in
            let name = names[Int(random.next() % UInt64(names.count))]
            let counted = random.next() % 5 == 0 ? nil : Int(random.next() % 6)
            return Artist(id: "a\(at)", name: random.next() % 9 == 0 ? nil : name, albumCount: counted)
        }
    }

    // MARK: the answers

    @Test func theArtistsListIsReadLeniently() async throws {
        let (client, transport) = client(session: "s")
        transport.answer("/deadwax/navidrome/artists", 200, #"{"artists": [{"id": "ar-1", "name": "Portishead", "albumCount": 2, "coverArt": "ar-ar-1", "musicBrainzId": "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"}, {"name": "no id"}, {"id": "ar-2", "name": 4, "albumCount": "lots"}]}"#)
        let list = try await client.artists()
        #expect(list == [Artist(id: "ar-1", name: "Portishead", albumCount: 2, coverArt: "ar-ar-1",
                                musicBrainzId: "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"),
                         Artist(id: "ar-2")], "an artist unreadable left out; a field of the wrong type absent")
        #expect(transport.last?.method == "GET" && transport.last?.url.path == "/deadwax/navidrome/artists")
        transport.answer("/deadwax/navidrome/artists", 200, #"{}"#)
        #expect(try await client.artists().isEmpty)
        transport.answer("/deadwax/navidrome/artists", 200, #"{"artists": "none"}"#)
        #expect(try await client.artists().isEmpty)
    }

    @Test func oneArtistIsReadWithTheirAlbums() async throws {
        let (client, transport) = client(session: "s")
        transport.answer("/deadwax/navidrome/artists/ar 1", 200, #"{"id": "ar-1", "name": "Portishead", "albumCount": 2, "coverArt": "ar-ar-1", "album": [{"id": "al-1", "name": "Dummy", "year": 1994, "artistId": "ar-1"}, {"name": "no id"}, {"id": "al-2", "name": "Third", "year": 2008, "starred": "2026-10-01T12:00:00Z"}]}"#)
        let found = try #require(try await client.artist(id: "ar 1"))
        #expect(found.artist == Artist(id: "ar-1", name: "Portishead", albumCount: 2, coverArt: "ar-ar-1"))
        #expect(found.album.map(\.id) == ["al-1", "al-2"], "an album unreadable left out")
        #expect(found.album[1].isStarred && !found.album[0].isStarred)
        #expect(transport.last?.url.path == "/deadwax/navidrome/artists/ar 1")
        // Navidrome has no such artist: deadwax answers {}
        transport.answer("/deadwax/navidrome/artists/none", 200, #"{}"#)
        #expect(try await client.artist(id: "none") == nil)
        transport.answer("/deadwax/navidrome/artists/bare", 200, #"{"id": "bare", "album": "none"}"#)
        #expect(try await client.artist(id: "bare")?.album == [])
        await #expect(throws: APIFailure.self) { try await client.artist(id: "gone") }
    }

    @Test func anArtistCountingYourAlbums() {
        let artist = Artist(id: "ar-1", name: "Portishead", albumCount: 5, coverArt: "c", musicBrainzId: "m")
        #expect(artist.counting(2) == Artist(id: "ar-1", name: "Portishead", albumCount: 2, coverArt: "c", musicBrainzId: "m"))
        let albums = [IndexAlbum(id: "1", artistId: "ar-1"), IndexAlbum(id: "2", artistId: ""), IndexAlbum(id: "3"),
                      IndexAlbum(id: "4", artistId: "ar-1"), IndexAlbum(id: "5", artistId: "ar-9")]
        #expect(YourArtists.of([artist, Artist(id: "ar-2")], albums: albums) == [artist.counting(2)])
        #expect(YourArtists.of([], albums: albums).isEmpty && YourArtists.of([artist], albums: []).isEmpty)
    }

    // MARK: the orders, by property

    @Test func nameOrderIsAPermutationWithHashLastAndTiesInOrder() {
        var random = Seeded(state: 42)
        for size in [0, 1, 2, 7, 49, 50, 200] {
            let list = Self.randomArtists(size, &random)
            let shelf = ArtistShelf(list)
            let sorted = shelf.sorted(.name)
            #expect(sorted.sorted() == Array(list.indices), "a permutation (\(size))")
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                let named = Shelf.byName(shelf.keys[a], shelf.initials[a], shelf.keys[b], shelf.initials[b])
                #expect(named < 0 || (named == 0 && a < b), "in order, a tie in Navidrome's (\(size): \(a), \(b))")
            }
            let initials = sorted.map { (place: Int) -> String in shelf.initials[place] }
            if let firstOther = initials.firstIndex(of: Fold.otherInitial) {
                #expect(initials[firstOther...].allSatisfy { $0 == Fold.otherInitial }, "# last (\(size))")
            }
            // the groups: the order cut into runs, each letter once, `#` last
            let groups = shelf.groups(sorted, .name)
            #expect(groups.flatMap(\.items) == sorted)
            #expect(Set(groups.map(\.key)).count == groups.count, "each header once (\(size))")
            #expect(groups.allSatisfy { (group: ShelfGroup) -> Bool in
                group.label == group.key && group.items.allSatisfy { shelf.initials[$0] == group.key }
            })
            // the index: 27 entries whose jumps never go back, each to its own letter or the next after it
            let entries = ShelfIndex.entries(groups, .name)
            #expect(entries.count == (groups.isEmpty ? 0 : 27))
            #expect(zip(entries, entries.dropFirst()).allSatisfy { $0.group <= $1.group })
            for entry in entries {
                if let own = groups.firstIndex(where: { $0.label == entry.label }) { #expect(entry.group == own) }
            }
            #expect(ShelfIndex.shows(.name, count: size, typed: "") == (size >= 50))
            #expect(!ShelfIndex.shows(.name, count: size, typed: "a b") && !ShelfIndex.shows(.albums, count: size, typed: ""))
        }
    }

    @Test func mostAlbumsIsMostFirstWithTiesInOrder() {
        var random = Seeded(state: 7)
        for size in [0, 1, 3, 60, 300] {
            let list = Self.randomArtists(size, &random)
            let shelf = ArtistShelf(list)
            let sorted = shelf.sorted(.albums)
            #expect(sorted.sorted() == Array(list.indices))
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                let (first, second) = (list[a].albumCount ?? 0, list[b].albumCount ?? 0)
                #expect(first > second || (first == second && a < b), "most first, a tie in Navidrome's order")
            }
            let groups = shelf.groups(sorted, .albums)
            #expect(groups == (size == 0 ? [] : [ShelfGroup(key: "all", label: nil, items: sorted)]))
            #expect(ShelfIndex.entries(groups, .albums).isEmpty && ShelfIndex.kind(ArtistOrder.albums) == nil)
            #expect(ShelfIndex.kind(ArtistOrder.name) == .letters)
        }
    }

    @Test func findKeepsEveryArtistHoldingEveryWordInOrder() {
        var random = Seeded(state: 99)
        let list = Self.randomArtists(300, &random)
        let shelf = ArtistShelf(list)
        let sorted = shelf.sorted(.name)
        for typed in ["the", "be", "low air", "AIR", "ø", "zz z", "  ", "x y z", "bjork", "&", "and"] {
            let found = shelf.filter(sorted, typed: typed)
            let words = Find.words(typed)
            #expect(found == sorted.filter { Set(found).contains($0) }, "in the order handed in")
            for place in sorted {
                let text = FoldKey(Fold.findText(list[place].name))
                let holds = words.allSatisfy { text.contains($0) }
                #expect(found.contains(place) == holds, "\"\(typed)\" and \(String(describing: list[place].name))")
            }
            let view = shelf.view(.name, typed: typed)
            #expect(view.found == found && view.sorted == sorted)
            if Find.finding(typed) {
                #expect(view.countText == "\(found.count) of 300 artists" && view.index == nil)
            } else {
                #expect(view.countText == "300 artists" && view.index?.count == 27)
            }
        }
    }

    @Test func theOrderAsKept() {
        #expect(ArtistOrder(saved: nil) == .name && ArtistOrder(saved: "albums") == .albums)
        #expect(ArtistOrder(saved: "Albums") == .name && ArtistOrder(saved: "albums ") == .name)
        #expect(ArtistOrder.storageKey == "deadwax-player-artist-order")
        #expect(ArtistWords.countPlace(.store, personal: true) == "in the collection")
        #expect(ArtistWords.countPlace(.yours, personal: true).isEmpty && ArtistWords.countPlace(.store, personal: false).isEmpty)
    }

    // MARK: an artist's rows

    @Test func rowsAreNewestFirstTheUndatedLastEachAlbumOnce() {
        let albums = [Album(id: "u", name: "Undated"), Album(id: "a", name: "Dummy", year: 1994),
                      Album(id: "b", name: "Third", coverArt: "c-b", year: 2008, starred: "2026-10-01T12:00:00Z"),
                      Album(id: "a", name: "Dummy again", year: 2001), Album(id: "z", name: "Zero", year: 0),
                      Album(id: "n", name: "Negative", year: -1), Album(id: "o", name: "Old", year: 999)]
        let rows = ArtistPage.rows(albums)
        #expect(rows.map(\.albumId) == ["o", "b", "a", "n", "u", "z"], "\"999\" before \"2008\", as the web compares years")
        #expect(rows[1] == ArtistPage.Row(key: "album:b", title: "Third", year: "2008", albumId: "b", coverArt: "c-b", yours: true))
        #expect(rows[2].title == "Dummy" && rows[2].year == "1994", "an album twice: the first")
        #expect(ArtistPage.line(rows[1], personal: true) == "2008 \u{00B7} in your library")
        #expect(ArtistPage.line(rows[2], personal: true) == "1994 \u{00B7} in the collection")
        #expect(ArtistPage.line(rows[2], personal: false) == "1994 \u{00B7} in your library")
        #expect(ArtistPage.line(rows[4], personal: false) == "in your library", "undated: the phrase alone")
        #expect(ArtistPage.marked(rows[2], personal: false) && !ArtistPage.marked(rows[2], personal: true))
        #expect(ArtistPage.marked(rows[1], personal: true))
        #expect(ArtistPage.playOrder(rows) == ["o", "b", "a", "n", "u", "z"])
        #expect(ArtistPage.rows([]).isEmpty && ArtistPage.playOrder([]).isEmpty)
    }

    @Test func rowsTiesByFoldedTitleThenKey() {
        let albums = [Album(id: "B1", name: "dummy", year: 1994), Album(id: "a1", name: "The Dummy", year: 1994),
                      Album(id: "A1", name: "Dümmy", year: 1994), Album(id: "c", name: "Album", year: 1994),
                      Album(id: "d", name: "Zed", year: 1994)]
        #expect(ArtistPage.rows(albums).map(\.albumId) == ["c", "a1", "A1", "B1", "d"])
    }

    @Test func keysCollateAsASCIIDoesUnderICU() {
        #expect(ArtistPage.asciiCollate("album:a1", "album:A1") < 0, "the lowercase first, nothing else differing")
        #expect(ArtistPage.asciiCollate("album:A1", "album:a1") > 0)
        #expect(ArtistPage.asciiCollate("album:a10", "album:a2") < 0, "digits as written, not as numbers")
        #expect(ArtistPage.asciiCollate("album:B1", "album:a1") > 0, "case folded before it decides")
        #expect(ArtistPage.asciiCollate("album:aB", "album:Ab") < 0, "the first place the case differs")
        #expect(ArtistPage.asciiCollate("album:a", "album:a") == 0)
        #expect(ArtistPage.asciiCollate("album:a", "album:ab") < 0 && ArtistPage.asciiCollate("album:9", "album:a") < 0)
        // antisymmetric and total over a mixed set
        let keys = ["a", "A", "b", "B", "a1", "A1", "aB", "Ab", "ab", "AB", "1", "10", "2", "z", "Z"]
        for one in keys {
            for other in keys {
                #expect(ArtistPage.asciiCollate(one, other) == -ArtistPage.asciiCollate(other, one))
                #expect((ArtistPage.asciiCollate(one, other) == 0) == (one == other))
            }
        }
    }

    @Test func rowsOrderByProperty() {
        var random = Seeded(state: 2026)
        let titles = ["Dummy", "dummy", "The Dummy", "Third", "", "Album", "Ålbum", "Zed"]
        for _ in 0..<40 {
            let count = Int(random.next() % 20)
            let albums = (0..<count).map { (at: Int) -> Album in
                let year = [nil, 0, 1994, 1994, 2008, 999][Int(random.next() % 6)]
                return Album(id: "x\(random.next() % 12)", name: titles[Int(random.next() % UInt64(titles.count))], year: year)
            }
            let rows = ArtistPage.rows(albums)
            #expect(Set(rows.map(\.albumId)) == Set(albums.map(\.id)) && rows.count == Set(albums.map(\.id)).count)
            let years = rows.map(\.year)
            if let undated = years.firstIndex(of: nil) {
                #expect(years[undated...].allSatisfy { $0 == nil }, "the undated last")
            }
            for (a, b) in zip(rows, rows.dropFirst()) {
                guard let first = a.year, let second = b.year else { continue }
                #expect(!(FoldKey(first) < FoldKey(second)), "newest first")
                if first == second {
                    let (one, other) = (FoldKey(Fold.key(a.title)), FoldKey(Fold.key(b.title)))
                    #expect(one < other || (one == other && ArtistPage.asciiCollate(a.key, b.key) < 0))
                }
            }
        }
    }

    // MARK: inTurns

    @Test func inTurnsNeverRunsMoreThanItsLimit() {
        var random = Seeded(state: 5)
        for _ in 0..<200 {
            let count = Int(random.next() % 15)
            let limit = Int(random.next() % 8) - 2
            var turns = InTurns(count: count, limit: limit)
            var started = turns.begin()
            var running = started.count
            #expect(running == min(count, max(1, limit)))
            while running > 0 {
                running -= 1
                if let next = turns.settled() {
                    started.append(next)
                    running += 1
                }
                #expect(running <= max(1, limit))
            }
            #expect(started == Array(0..<count), "every one started, once, in order")
            #expect(turns.settled() == nil && turns.next == count)
        }
        var stopped = InTurns(count: 9, limit: 3)
        #expect(stopped.begin() == [0, 1, 2])
        #expect(stopped.settled(going: { false }) == nil, "stopped: nothing more")
        #expect(stopped.settled() == 3, "going again: the next")
        var never = InTurns(count: 3, limit: 4)
        #expect(never.begin(going: { false }).isEmpty)
    }

    // MARK: the album asks

    @Test func theAlbumsAreAskedFourAtATimeInOrder() {
        var asks = ArtistAlbumAsks<String>()
        let order = ["a", "b", "c", "d", "e", "f"]
        let first = asks.want(order)
        #expect(first.map(\.id) == ["a", "b", "c", "d"])
        #expect(!asks.settled && !asks.playable)
        #expect(asks.line(library: .done, personal: false) == "Getting the songs of the 6 albums you have\u{2026}")
        #expect(asks.want(["f", "e", "d", "c", "b", "a"]).isEmpty, "the same albums in another order: nothing asked again")
        #expect(asks.order == ["f", "e", "d", "c", "b", "a"], "the order is the page's newest")
        let next = asks.answered(first[1], with: "B")
        #expect(next.map(\.id) == ["e"])
        #expect(asks.failed(first[0]).map(\.id) == ["f"])
        _ = asks.answered(first[2], with: "C")
        _ = asks.answered(first[3], with: "D")
        #expect(!asks.settled)
        _ = asks.answered(next[0], with: "E")
        _ = asks.answered(ArtistAlbumAsks<String>.Ask(id: "f", round: first[0].round), with: "F")
        #expect(asks.settled && asks.playable && asks.someMissing)
        #expect(asks.inHand == ["f", "e", "d", "c", "b"] && asks.answers == ["F", "E", "D", "C", "B"])
        #expect(asks.line(library: .done, personal: false) == "Plays 5 of the 6 albums you have - the rest didn't load")
        // Try again: only the one that didn't come
        let again = asks.again()
        #expect(again.map(\.id) == ["a"] && !asks.settled)
        // an answer of the round before lands nowhere
        #expect(asks.answered(first[0], with: "stale").isEmpty && asks.ready["a"] == nil)
        _ = asks.answered(again[0], with: "A")
        #expect(asks.settled && !asks.someMissing && asks.line(library: .done, personal: true)
                == "Plays the 6 albums in the collection")
    }

    @Test func otherAlbumsAskOnlyWhatIsntInHand() {
        var asks = ArtistAlbumAsks<Int>()
        let first = asks.want(["a", "b"])
        _ = asks.answered(first[0], with: 1)
        let more = asks.want(["a", "b", "c"])
        #expect(more.map(\.id) == ["b", "c"], "a in hand stays")
        #expect(asks.answered(first[1], with: 2).isEmpty && asks.ready["b"] == nil, "the older round's answer dropped")
        #expect(asks.failed(first[1]).isEmpty && asks.unsent.isEmpty && !asks.settled,
                "and its failure: b is still being asked this round")
        _ = asks.answered(more[0], with: 2)
        _ = asks.answered(more[1], with: 3)
        #expect(asks.answers == [1, 2, 3] && asks.playable)
        #expect(asks.want(["c", "a", "b"]).isEmpty, "everything in hand: nothing to ask")
        #expect(asks.again().isEmpty && asks.settled, "and nothing to try again")
        var none = ArtistAlbumAsks<Int>()
        #expect(none.want([]).isEmpty && none.settled && !none.playable && !none.someMissing)
        #expect(none.line(library: .asking, personal: false) == "Looking for their albums in your library\u{2026}")
        #expect(none.line(library: .done, personal: false) == "None of their albums are here to play.")
    }

    /// The review's first finding: a kept answer drew the albums, but their songs weren't asked until deadwax's answer
    /// came - the line said "None of their albums are here to play." meanwhile. Now the kept answer's albums are asked at
    /// once; deadwax's answer naming the same albums (other names, another order) asks nothing more, one more only it.
    @Test func aKeptAnswersAsksCarryOverToDeadwaxsAnswer() {
        let kept = [Album(id: "al-1", name: "Dummy", year: 1994), Album(id: "al-2", name: "Third", year: 2008)]
        let fresh = [Album(id: "al-2", name: "Third (Remastered)", year: 2008), Album(id: "al-1", name: "Dummy", year: 1994)]
        var asks = ArtistAlbumAsks<String>()
        #expect(asks.line(library: .done, personal: false) == "None of their albums are here to play.",
                "what the page said before its albums were asked")
        let first = asks.want(ArtistPage.playOrder(ArtistPage.rows(kept)))
        #expect(first.map(\.id) == ["al-2", "al-1"])
        #expect(asks.line(library: .done, personal: false) == "Getting the songs of the 2 albums you have\u{2026}")
        #expect(asks.want(ArtistPage.playOrder(ArtistPage.rows(fresh))).isEmpty, "the same albums: nothing more asked")
        _ = asks.answered(first[0], with: "Third")
        _ = asks.answered(first[1], with: "Dummy")
        #expect(asks.playable && asks.answers == ["Third", "Dummy"], "the kept round's answers count")
        let more = fresh + [Album(id: "al-3", name: "Roseland NYC Live", year: 1998)]
        #expect(asks.want(ArtistPage.playOrder(ArtistPage.rows(more))).map(\.id) == ["al-3"], "one more: only it")
    }

    @Test func everyInterleavingSettlesWithEachAlbumInHandOrLeftOut() {
        var random = Seeded(state: 11)
        for _ in 0..<150 {
            let count = Int(random.next() % 12)
            let order = (0..<count).map { "al-\($0)" }
            var asks = ArtistAlbumAsks<String>()
            var waiting = asks.want(order)
            var failed = Set<String>()
            var peak = waiting.count
            while !waiting.isEmpty {
                let ask = waiting.remove(at: Int(random.next() % UInt64(waiting.count)))
                if random.next() % 4 == 0 {
                    failed.insert(ask.id)
                    waiting += asks.failed(ask)
                } else {
                    waiting += asks.answered(ask, with: ask.id.uppercased())
                }
                peak = max(peak, waiting.count)
            }
            #expect(peak <= ArtistPage.atOnce, "never more than four out")
            #expect(asks.settled)
            #expect(Set(asks.inHand) == Set(order).subtracting(failed) && asks.unsent == failed)
            #expect(asks.someMissing == !failed.isEmpty && asks.playable == (failed.count < count))
            // and Try again asks exactly those left out, in the page's order, four at a time
            let again = asks.again()
            #expect(again.map(\.id) == Array(order.filter { failed.contains($0) }.prefix(ArtistPage.atOnce)))
        }
    }

    // MARK: Play and Shuffle

    @Test func playIsEveryAlbumInOrderAtItsAlbumLevel() throws {
        let dummy = Album(id: "al-1", name: "Dummy", artist: "Portishead", coverArt: "c1",
                          song: [Song(id: "s1", title: "Mysterons"), Song(id: "s2", title: "Sour Times")])
        let third = Album(id: "al-2", name: "Third", artist: "Portishead", coverArt: "c2", song: [Song(id: "s3", title: "Silence")])
        let empty = Album(id: "al-3", name: "Nothing", song: [])
        let play = try #require(ArtistPlay.plan([dummy, empty, third], shuffle: false, setting: .auto))
        #expect(play.tracks.map(\.id) == ["s1", "s2", "s3"] && play.start == 0)
        #expect(play.tracks.map(\.albumId) == ["al-1", "al-1", "al-2"], "each song with its own album")
        #expect(play.tracks.map(\.coverArt) == ["c1", "c1", "c2"] && play.tracks.allSatisfy { $0.level == .album })
        #expect(play.albums.map(\.id) == ["al-1", "al-3", "al-2"], "every album remembered")
        let shuffle = try #require(ArtistPlay.plan([dummy, third], shuffle: true, setting: .auto))
        #expect(shuffle.start == nil && shuffle.tracks.allSatisfy { $0.level == .track }, "Shuffle: as songs, anywhere")
        #expect(ArtistPlay.plan([dummy], shuffle: false, setting: .off)?.tracks.allSatisfy { $0.level == nil } == true)
        #expect(ArtistPlay.plan([dummy], shuffle: true, setting: .album)?.tracks.allSatisfy { $0.level == .album } == true)
        #expect(ArtistPlay.plan([empty], shuffle: false, setting: .auto) == nil && ArtistPlay.plan([], shuffle: true, setting: .auto) == nil)
    }

    // MARK: offline

    @Test func offlineTheAnswerInHandElseTheDownloads() {
        let answer = ArtistWithAlbums(Artist(id: "ar-1", name: "Portishead"), albums: [Album(id: "al-1")])
        let downloaded = [Album(id: "al-2", artistId: "ar-1"), Album(id: "al-3", artistId: "ar-2"), Album(id: "al-4", artistId: "ar-1")]
        #expect(ArtistOffline.albums(answer: answer, artistId: "ar-1", downloaded: downloaded).map(\.id) == ["al-1"])
        #expect(ArtistOffline.albums(answer: nil, artistId: "ar-1", downloaded: downloaded).map(\.id) == ["al-2", "al-4"])
        let kept: [String: Album] = [
            "al-1": Album(id: "al-1", song: [Song(id: "s1"), Song(id: "s2")]),
            "al-2": Album(id: "al-2", song: [Song(id: "s3")]),
            "al-4": Album(id: "al-4", song: [Song(id: "s4"), Song(id: "s5")]),
        ]
        let here: Set<String> = ["s2", "s4", "s5"]
        let plays = ArtistOffline.playable(["al-4", "al-2", "al-1", "al-9"], album: { kept[$0] }, here: { here.contains($0) })
        #expect(plays.map(\.id) == ["al-4", "al-1"], "in the page's order, an album with nothing here left out")
        #expect(plays.map { (album: Album) -> [String] in (album.song ?? []).map(\.id) } == [["s4", "s5"], ["s2"]])
        let index = [IndexAlbum(id: "1", artist: "Portishead", artistId: "ar-1"), IndexAlbum(id: "2", artist: "Portishead", artistId: "ar-1"),
                     IndexAlbum(id: "3", artist: "Nobody"), IndexAlbum(id: "4", artist: "Tricky", artistId: "ar-3"),
                     IndexAlbum(id: "5", artistId: "")]
        #expect(ArtistOffline.artists(index) == [Artist(id: "ar-1", name: "Portishead"), Artist(id: "ar-3", name: "Tricky")])
    }

    /// The review's fourth finding: an album names its album artist only by its credit, so an "A & B" album listed first
    /// named artist A "A & B" for the sort, Find and their page's title.
    @Test func offlineAnArtistIsNamedAsMostOfTheirAlbumsNameThem() {
        let index = [
            IndexAlbum(id: "1", artist: "Portishead & Tricky", artistId: "ar-1"),
            IndexAlbum(id: "2", artist: "Massive Attack & Tricky", artistId: "ar-2"),
            IndexAlbum(id: "3", artist: "Portishead", artistId: "ar-1"),
            IndexAlbum(id: "4", artist: "Massive Attack", artistId: "ar-2"),
            IndexAlbum(id: "5", artist: "Portishead", artistId: "ar-1"),
            IndexAlbum(id: "6", artist: "Xy", artistId: "ar-3"), IndexAlbum(id: "7", artist: "Zw", artistId: "ar-3"),
            IndexAlbum(id: "8", artistId: "ar-4"), IndexAlbum(id: "9", artist: "", artistId: "ar-4"),
            IndexAlbum(id: "10", artist: "Nobody's", artistId: ""), IndexAlbum(id: "11", artist: "Nobody's"),
        ]
        #expect(ArtistOffline.artists(index) == [
            Artist(id: "ar-1", name: "Portishead"),
            Artist(id: "ar-2", name: "Massive Attack"),
            Artist(id: "ar-3", name: "Xy"),
            Artist(id: "ar-4", name: nil),
        ], "most albums' name; a tie the shortest, then the first; an album naming nobody none")
        #expect(ArtistOffline.artists([]) == [])
    }

    @Test func offlineArtistsByProperty() {
        var random = Seeded(state: 41)
        let credits: [String?] = ["A", "A & B", "B", "Bb", "A, B & C", "", nil, "C"]
        for _ in 0..<300 {
            let count = Int(random.next() % 14)
            let index = (0..<count).map { (at: Int) -> IndexAlbum in
                let id: String? = random.next() % 7 == 0 ? (random.next() % 2 == 0 ? nil : "") : "ar-\(random.next() % 4)"
                return IndexAlbum(id: "al-\(at)", artist: credits[Int(random.next() % UInt64(credits.count))], artistId: id)
            }
            let artists = ArtistOffline.artists(index)
            let ids = index.compactMap { (album: IndexAlbum) -> String? in
                guard let id = album.artistId, !id.isEmpty else { return nil }
                return id
            }
            var firsts: [String] = []
            for id in ids where !firsts.contains(id) { firsts.append(id) }
            #expect(artists.map(\.id) == firsts, "each artist once, where they first appear")
            for artist in artists {
                let given = index.compactMap { (album: IndexAlbum) -> String? in
                    guard album.artistId == artist.id, let name = album.artist, !name.isEmpty else { return nil }
                    return name
                }
                guard let name = artist.name else {
                    #expect(given.isEmpty, "no name only when no album gives one")
                    continue
                }
                let albums = given.filter { (each: String) -> Bool in each == name }.count
                #expect(albums > 0, "a name one of their albums gives")
                for other in Set(given) {
                    let theirs = given.filter { (each: String) -> Bool in each == other }.count
                    #expect(theirs < albums || (theirs == albums && other.count >= name.count), "\(name) over \(other)")
                }
            }
        }
    }

    // MARK: the album page's artist line

    @Test func theAlbumsArtistLineLinksWhenItCan() {
        let named = Album(id: "al-1", artist: "Portishead", artistId: "ar-1")
        let nameless = Album(id: "al-2", artist: "Various")
        for coming in [true, false] {
            #expect(ArtistLink.of(album: named, opened: nil, name: "Portishead", coming: coming) == .link(id: "ar-1"))
            #expect(ArtistLink.of(album: nameless, opened: "ar-9", name: "Various", coming: coming) == .plain,
                    "the album's own once it answers")
            #expect(ArtistLink.of(album: nil, opened: "ar-1", name: "Portishead", coming: coming) == .link(id: "ar-1"),
                    "the opener's meanwhile - and after a failure, as the web's preview")
            #expect(ArtistLink.of(album: named, opened: nil, name: "", coming: coming) == .plain, "no name, nothing to link")
            #expect(ArtistLink.of(album: Album(id: "x", artistId: ""), opened: "ar-1", name: "A", coming: coming) == .plain)
        }
        #expect(ArtistLink.of(album: nil, opened: nil, name: "Portishead", coming: true) == .pending,
                "it might yet become a link")
        #expect(ArtistLink.of(album: nil, opened: "", name: "Portishead", coming: true) == .pending)
        // the review's third finding: opened without the artist's id (Go to the album, Downloads), and no answer coming
        // - failed, gone, or offline with nothing here - it stayed purple and still for good; the web draws it plain
        #expect(ArtistLink.of(album: nil, opened: nil, name: "Portishead", coming: false) == .plain)
        #expect(ArtistLink.of(album: nil, opened: "", name: "Portishead", coming: false) == .plain)
    }

    // MARK: the Artists page with nothing to draw

    struct Refused: Error, Equatable { let why: String }

    /// The review's second finding: Your artists with nothing of yours in hand and your albums' first ask failed spun for
    /// ever - only the artists' own failure was read.
    @Test func nothingToDrawSaysWhichAskFailed() {
        let artists = Refused(why: "artists")
        let albums = Refused(why: "albums")
        func said(_ artistsFailed: Refused?, _ albumsFailed: Refused?, yours: Bool) -> Refused? {
            ArtistsWaiting.failure(artists: artistsFailed, yourAlbums: albumsFailed, yours: yours) as? Refused
        }
        #expect(said(nil, albums, yours: true) == albums, "your albums failing: said, with Try again")
        #expect(said(nil, albums, yours: false) == nil, "All artists doesn't need your albums: still asking")
        #expect(said(artists, albums, yours: true) == artists && said(artists, nil, yours: false) == artists)
        #expect(said(nil, nil, yours: true) == nil && said(nil, nil, yours: false) == nil, "both may still come")
    }
}
