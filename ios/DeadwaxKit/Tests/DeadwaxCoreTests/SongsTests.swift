import Foundation
import Testing
@testable import DeadwaxCore

/// Songs (Phase 4, slice 5 - phase4-library.md 2.7, 3.1, 6.5): every song a page at a time (usePaged.ts's rules), what
/// the page draws and under its rows, a row's rules and words, All songs' Shuffle button, and the two Shuffles kept
/// apart (ShuffleAheads). appendPage itself, the words read from the web and the feed are ShuffleVectorTests'.
@Suite struct SongsTests {
    private static func songs(_ range: Range<Int>, prefix: String = "s") -> [Song] {
        range.map { (n: Int) -> Song in Song(id: "\(prefix)\(n)", title: "Song \(n)", album: "Album", albumId: "al\(n % 5)") }
    }
    private static func ids(_ songs: [Song]) -> [String] { songs.map { (song: Song) -> String in song.id } }
    /// #require for a mutating call's answer: the call made outside the macro, whose closure can't mutate.
    private static func some<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T {
        try #require(value, sourceLocation: sourceLocation)
    }

    // MARK: the paging

    @Test func everySongAPageAtATime() throws {
        var paging = SongsPaging()
        #expect(paging.more() == nil, "nothing asked yet: no next page")
        let first = paging.start("")
        #expect(first.offset == 0 && first.query == "" && first.count == 100)
        #expect(paging.loading && !paging.done && paging.items.isEmpty)
        #expect(paging.more() == nil, "one ask at a time")
        paging.answered(first, Self.songs(0..<100))
        #expect(paging.items.count == 100 && !paging.loading && !paging.done && paging.next == 100)
        #expect(paging.countText == "", "the count only once every page is in")
        let second = try Self.some(paging.more())
        #expect(second.offset == 100 && second.serial > first.serial)
        paging.answered(second, Self.songs(100..<200))
        let third = try Self.some(paging.more())
        #expect(third.offset == 200)
        paging.answered(third, Self.songs(200..<237))
        #expect(paging.done && paging.items.count == 237 && paging.next == 237, "a page short of 100 is the last")
        #expect(paging.more() == nil, "every page in: nothing more")
        #expect(paging.countText == "237 songs")
    }

    @Test func aPageOfExactlyAHundredAsksOnceMore() throws {
        var paging = SongsPaging()
        let first = paging.start("")
        paging.answered(first, Self.songs(0..<100))
        let second = try Self.some(paging.more())
        paging.answered(second, [])
        #expect(paging.done && paging.items.count == 100, "an empty page ends it - usePaged's page.length < pageSize")
        #expect(paging.countText == "100 songs")
    }

    @Test func theNextOffsetFollowsWhatTheServerHandedOut() throws {
        var paging = SongsPaging()
        let first = paging.start("")
        paging.answered(first, Self.songs(0..<100))
        let second = try Self.some(paging.more())
        // the list is live: a song added at the front shifts every later page by one, repeating s99 at the edge
        paging.answered(second, Self.songs(99..<199))
        #expect(paging.items.count == 199, "the song already drawn left out")
        #expect(Self.ids(paging.items).filter { (id: String) -> Bool in id == "s99" }.count == 1)
        #expect(paging.next == 200, "the offset counts the page as the server sent it, not as it was drawn")
        #expect(!paging.done, "a full page, whatever was left out of it")
        let after = try Self.some(paging.more())
        #expect(after.offset == 200)
    }

    @Test func onlyTheNewestAsksAnswerCounts() throws {
        var paging = SongsPaging()
        let old = paging.start("roads")
        let new = paging.start("dummy")
        paging.answered(old, Self.songs(0..<3, prefix: "r"))
        #expect(paging.items.isEmpty && paging.loading, "another query's answer dropped")
        paging.failed(old)
        #expect(!paging.failing && paging.loading, "and its failure")
        paging.answered(new, Self.songs(0..<2, prefix: "d"))
        #expect(Self.ids(paging.items) == ["d0", "d1"] && paging.done)
        var reset = SongsPaging()
        let asked = reset.start("")
        reset.reset()
        reset.answered(asked, Self.songs(0..<5))
        #expect(reset.items.isEmpty && reset.query == nil && !reset.loading, "a reset drops what was asked before it")
        #expect(reset.more() == nil && reset.retry() == nil)
    }

    @Test func anotherQueryEmptiesTheListAtOnce() throws {
        var paging = SongsPaging()
        let first = paging.start("")
        paging.answered(first, Self.songs(0..<100))
        let found = paging.start("roads")
        #expect(paging.items.isEmpty && !paging.stale && found.offset == 0 && found.query == "roads")
        #expect(SongsBody.of(paging, online: true) == .loading)
    }

    @Test func theSameQueryAgainKeepsTheListDrawnUntilItsFirstPage() throws {
        var paging = SongsPaging()
        let first = paging.start("")
        paging.answered(first, Self.songs(0..<100))
        let second = try Self.some(paging.more())
        paging.answered(second, Self.songs(100..<150))
        #expect(paging.done)
        let again = paging.start("")
        #expect(again.offset == 0 && paging.items.count == 150 && paging.stale && !paging.done, "a refresh: drawn as it was")
        #expect(paging.more() == nil, "no later page of the old list")
        #expect(SongsFoot.of(paging, online: true) == .nothing, "the old list drawn, no spinner under it")
        paging.answered(again, Self.songs(0..<100, prefix: "n"))
        #expect(paging.items.count == 100 && Self.ids(paging.items).first == "n0" && !paging.stale, "page 0 in its place")
        let after = try Self.some(paging.more())
        #expect(after.offset == 100)
    }

    @Test func aRefreshThatFailsKeepsTheOldListAndSaysSo() throws {
        var paging = SongsPaging()
        let first = paging.start("")
        paging.answered(first, Self.songs(0..<40))
        let again = paging.start("")
        paging.failed(again)
        #expect(paging.items.count == 40 && paging.stale && paging.failing)
        #expect(SongsFoot.of(paging, online: true) == .couldntRefresh)
        #expect(SongsBody.of(paging, online: true) == .songs)
        let retried = try Self.some(paging.retry())
        #expect(retried.offset == 0, "Try again asks the first page again")
        paging.answered(retried, Self.songs(0..<41))
        #expect(paging.items.count == 41 && !paging.stale && !paging.failing && paging.done)
    }

    @Test func aPageThatWontComeWaitsForTryAgain() throws {
        var paging = SongsPaging()
        let first = paging.start("")
        paging.answered(first, Self.songs(0..<100))
        let second = try Self.some(paging.more())
        paging.failed(second)
        #expect(paging.failing && !paging.loading && paging.items.count == 100)
        #expect(paging.more() == nil, "the end coming near again asks nothing: Try again does")
        #expect(SongsFoot.of(paging, online: true) == .failed)
        let retried = try Self.some(paging.retry())
        #expect(retried.offset == 100 && paging.loading && !paging.failing)
        #expect(paging.retry() == nil, "nothing failed now")
        #expect(SongsFoot.of(paging, online: true) == .loading)
        paging.answered(retried, Self.songs(100..<120))
        #expect(paging.items.count == 120 && paging.done)
    }

    // MARK: what the page draws

    @Test func deadwaxBackPicksUpWhereTheReaderGotTo() throws {
        var paging = SongsPaging()
        var reach = SongsReach()
        #expect(!reach.wantsMore(paging), "nothing drawn, nothing appeared")
        let first = paging.start("")
        paging.answered(first, Self.songs(0..<100))
        // offline: the rows to the end appear, asking nothing (SongsModel asks only while deadwax can be reached)
        for index in 60..<100 { reach.appeared(index, in: paging) }
        #expect(reach.furthest == 99)
        #expect(reach.wantsMore(paging), "back: the reader is at the end")
        let next = try Self.some(paging.more())
        #expect(next.offset == 100)
        // a row past the list counts for nothing, and the furthest stays the furthest
        reach.appeared(500, in: paging)
        reach.appeared(-1, in: paging)
        reach.appeared(10, in: paging)
        #expect(reach.furthest == 99)
        paging.answered(next, Self.songs(100..<200))
        #expect(!reach.wantsMore(paging), "99 of 200: not near the end")
        // only near the end: row 40 of 100 wants nothing more, row 75 (25 from the end) does
        var short = SongsPaging()
        var near = SongsReach()
        let page = short.start("")
        short.answered(page, Self.songs(0..<100))
        near.appeared(40, in: short)
        #expect(!near.wantsMore(short))
        near.appeared(75, in: short)
        #expect(near.wantsMore(short), "25 from the end")
        // another list drawn - another query, or a first page in place of the old - forgets the old list's rows
        _ = short.start("roads")
        #expect(!near.wantsMore(short))
        var refreshed = SongsPaging()
        var seen = SongsReach()
        let one = refreshed.start("")
        refreshed.answered(one, Self.songs(0..<100))
        seen.appeared(99, in: refreshed)
        let again = refreshed.start("")
        #expect(seen.wantsMore(refreshed), "a refresh's old list still drawn: the reader is still at its end")
        let over = refreshed.more()
        #expect(over == nil, "...though nothing more is asked over it")
        refreshed.answered(again, Self.songs(0..<100))
        #expect(!seen.wantsMore(refreshed), "its first page in its place: back at the top")
        seen.appeared(80, in: refreshed)
        #expect(seen.furthest == 80 && seen.wantsMore(refreshed), "the new list's own rows")
    }

    @Test func whatSongsDraws() throws {
        var paging = SongsPaging()
        #expect(SongsBody.of(paging, online: true) == .loading, "nothing asked yet")
        #expect(SongsBody.of(paging, online: false) == .offline)
        let first = paging.start("")
        #expect(SongsBody.of(paging, online: true) == .loading)
        paging.failed(first)
        #expect(SongsBody.of(paging, online: true) == .failed)
        #expect(SongsBody.of(paging, online: false) == .offline, "out of reach says so, not the error")
        let again = try Self.some(paging.retry())
        paging.answered(again, [])
        #expect(SongsBody.of(paging, online: true) == .empty("No songs yet."))
        #expect(SongsBody.of(paging, online: false) == .empty("No songs yet."), "an answer in hand stands")
        var found = SongsPaging()
        let ask = found.start("dumy")
        found.answered(ask, [])
        #expect(SongsBody.of(found, online: true) == .empty("No songs match \u{201C}dumy\u{201D}."))
        // the words are what was searched, not what Find holds now: typed on ("dumyq", the pause before it is asked, or
        // offline, when it isn't), the list drawn is still "dumy"'s, and says so
        #expect(SongsBody.of(found, online: false) == .empty("No songs match \u{201C}dumy\u{201D}."))
        // Find cleared: every song asked - the spinner, never "No songs yet." for a frame
        _ = found.start(SongsList.query(""))
        #expect(SongsBody.of(found, online: true) == .loading)
        var some = SongsPaging()
        let page = some.start("")
        some.answered(page, Self.songs(0..<3))
        #expect(SongsBody.of(some, online: true) == .songs)
        #expect(SongsBody.of(some, online: false) == .songs, "songs in hand drawn offline (question 34)")
        #expect(SongsFoot.of(some, online: true) == .nothing)
    }

    @Test func underTheRows() throws {
        var paging = SongsPaging()
        #expect(SongsFoot.of(paging, online: true) == .nothing)
        let first = paging.start("")
        #expect(SongsFoot.of(paging, online: true) == .nothing, "no rows: the body's spinner, not the foot's")
        paging.answered(first, Self.songs(0..<100))
        _ = try Self.some(paging.more())
        #expect(SongsFoot.of(paging, online: true) == .loading)
        #expect(SongsFoot.of(paging, online: false) == .nothing, "no spinner while deadwax is out of reach")
    }

    // MARK: a row

    @Test func aRowsRules() {
        #expect(SongsList.query("") == "" && SongsList.query("   ") == "")
        #expect(SongsList.query("  roads ") == "roads")
        #expect(SongsList.query("glory box") == "glory box")
        #expect(SongsList.opensAlbum(Song(id: "1", albumId: "al")))
        #expect(!SongsList.opensAlbum(Song(id: "1")) && !SongsList.opensAlbum(Song(id: "1", albumId: "")))
        let here = { (id: String) -> Bool in id == "kept" }
        #expect(!SongsList.dimmed(Song(id: "x"), online: true, here: here))
        #expect(SongsList.dimmed(Song(id: "x"), online: false, here: here))
        #expect(!SongsList.dimmed(Song(id: "kept"), online: false, here: here), "on this phone: it plays from its album")
        #expect(SongsList.nearTheEnd == 25)
        #expect(!SongsList.asksMore(at: 74, of: 100) && SongsList.asksMore(at: 75, of: 100) && SongsList.asksMore(at: 99, of: 100))
        #expect(SongsList.asksMore(at: 0, of: 10), "a short list: its first row")
    }

    @Test func aRowAsVoiceOverReadsIt() {
        #expect(SongWords.spoken(Song(id: "1", title: "Roads", album: "Dummy", albumId: "al", artist: "Portishead"))
                == "Roads, Portishead \u{00B7} Dummy, opens its album")
        #expect(SongWords.spoken(Song(id: "1", title: "Roads", artist: "Portishead")) == "Roads, Portishead",
                "no album to open: not said")
        #expect(SongWords.spoken(Song(id: "1", title: "Roads", albumId: "al")) == "Roads, opens its album")
        #expect(SongWords.spoken(Song(id: "1", album: "Dummy", albumId: "al")) == "Dummy, opens its album")
    }

    @Test func songsWords() {
        #expect(SongWords.songs == "Songs" && SongWords.allSongs == "All songs")
        #expect(SongWords.title(personal: false) == "Songs" && SongWords.title(personal: true) == "All songs")
        #expect(SongWords.noSongs == "No songs yet.")
        #expect(SongWords.findPlaceholder == "Find in songs")
        #expect(SongWords.offline == "Songs show here once deadwax is back.")
        #expect(SongWords.noMatch(" roads ") == "No songs match \u{201C}roads\u{201D}.")
        #expect(SongWords.count(nil) == "" && SongWords.count(1) == "1 song" && SongWords.count(2) == "2 songs")
    }

    // MARK: All songs' Shuffle

    @Test func allSongsShuffleButton() {
        #expect(ShuffleButtonFace.of(.ready) == ShuffleButtonFace(words: "Shuffle", enabled: true, why: nil))
        #expect(ShuffleButtonFace.of(.downloads) == ShuffleButtonFace(words: "Shuffle downloads", enabled: true, why: nil))
        #expect(ShuffleButtonFace.of(.gettingReady) == ShuffleButtonFace(words: "Getting ready\u{2026}", enabled: false, why: nil))
        #expect(ShuffleButtonFace.of(.failed("Couldn't get your songs ready to shuffle"))
                == ShuffleButtonFace(words: "Getting ready\u{2026}", enabled: false, why: "Couldn't get your songs ready to shuffle"),
                "the web's: still Getting ready…, dimmed, why under it")
        #expect(ShuffleButtonFace.of(.nothingHere) == nil && ShuffleButtonFace.of(.none) == nil, "no dead button")
    }

    @Test func whichShufflesScope() {
        #expect(ShuffleOf.library.scope(library: .yours) == .yours)
        #expect(ShuffleOf.library.scope(library: .store) == .store)
        #expect(ShuffleOf.allSongs.scope(library: .yours) == .store, "All songs is the collection's")
        #expect(ShuffleOf.allSongs.scope(library: .store) == .store)
    }

    @Test func theTwoShufflesNeverMoveEachOther() throws {
        var aheads = ShuffleAheads()
        let yours = try Self.some(aheads.shown(.library, library: .yours, now: 0))
        let all = try Self.some(aheads.shown(.allSongs, library: .yours, now: 0))
        #expect(yours.scope == .yours && all.scope == .store)
        aheads.answered(.library, yours, ShuffleStart(token: "y1", total: 30, songs: Self.songs(0..<30)))
        aheads.answered(.allSongs, all, ShuffleStart(token: "a1", total: 900, songs: Self.songs(0..<200)))
        #expect(aheads[.library].ready && aheads[.allSongs].ready)
        // showing one again asks nothing of either, and lets neither's page go
        #expect(aheads.shown(.allSongs, library: .yours, now: 5) == nil)
        #expect(aheads.shown(.library, library: .yours, now: 6) == nil)
        #expect(aheads[.library].first?.token == "y1" && aheads[.allSongs].first?.token == "a1")
        let taken = try Self.some(aheads.take(.allSongs, level: .track, now: 10))
        #expect(taken.paged.token == "a1" && taken.paged.scope == .store && taken.tracks.count == 200 && taken.paged.total == 900)
        #expect(taken.next.scope == .store && taken.next.playing == "a1")
        #expect(aheads[.library].ready && !aheads[.allSongs].ready, "yours still in hand")
        aheads.failed(.allSongs, taken.next, words: "why")
        #expect(aheads[.allSongs].failure == "why" && aheads[.library].failure == nil)
        let mine = try Self.some(aheads.take(.library, level: nil, now: 11))
        #expect(mine.paged.token == "y1" && mine.paged.scope == .yours)
        // each answer lands on its own: the Library's next order, and not All songs' failure undone
        aheads.answered(.library, mine.next, ShuffleStart(token: "y2", total: 30, songs: Self.songs(0..<30)))
        #expect(aheads[.library].first?.token == "y2" && !aheads[.allSongs].ready && aheads[.allSongs].failure == "why")
        aheads.reset()
        #expect(!aheads[.library].ready && !aheads[.allSongs].ready && aheads[.allSongs].failure == nil)
        #expect(aheads[.library].scope == nil && aheads[.allSongs].scope == nil)
    }
}
