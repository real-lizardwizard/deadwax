import Foundation
import Testing
@testable import DeadwaxCore

/// Search's state and the phone's own rules (Phase 5, slice 1 - notes/ios-specs/phase5-search.md 2.6-2.9 and 7): when
/// the library is asked and the list drawn, what freezes and what changes in place, a kind view's own and its More, the
/// albums asked for so a song plays, and the two answers read leniently. The web's rules themselves are held by
/// SearchVectorTests.
@Suite struct SearchTests {
    static let portishead = Artist(id: "ar-p", name: "Portishead", albumCount: 3)
    static let dummy = Album(id: "nd-dummy", name: "Dummy", artist: "Portishead", artistId: "ar-p", year: 1994,
                             musicBrainzId: "rel-dummy")
    static let third = Album(id: "nd-third", name: "Third", artist: "Portishead", artistId: "ar-p", year: 2008)
    static let roads = Song(id: "s-roads", title: "Roads", album: "Dummy", albumId: "nd-dummy", artist: "Portishead",
                            artistId: "ar-p")
    static let glory = Song(id: "s-glory", title: "Glory Box", album: "Dummy", albumId: "nd-dummy", artist: "Portishead",
                            artistId: "ar-p")
    static let rip = Song(id: "s-rip", title: "The Rip", album: "Third", albumId: "nd-third", artist: "Portishead",
                          artistId: "ar-p")
    static let found = LibraryResults(artists: [portishead], albums: [dummy], songs: [roads, glory])
    static let marks = SearchMarks(personal: false)

    /// A state with `text` typed, asked and answered with `results`.
    static func answered(_ text: String, _ results: LibraryResults = found) -> SearchState {
        var state = SearchState()
        state.typed(text)
        let token = state.askingLibrary()
        state.libraryAnswered(token, state.query, results)
        return state
    }

    /// The All view's next draw, with no folders and no full artist list unless given - MusicBrainz's albums, when the
    /// words ask them, answered at once with nothing (these are the library's half's tests), so the list is drawn whole.
    static func drawing(_ state: inout SearchState, owned: [String] = [], list: [Artist]? = nil) -> SearchState.Drawing? {
        state.ownedArtists = owned
        if state.view == .all, !state.query.isEmpty, state.drawnMusicBrainz(state.query), !state.askedForQuery,
           let ask = state.askingMusicBrainz(state.query, view: .all) {
            state.albumsAnswered(ask, FullySearchAnswer(), query: ask.first, index: nil)
        }
        return state.advance(artistList: list, marks: marks)
    }

    static func advance(_ state: inout SearchState, owned: [String] = [], list: [Artist]? = nil) -> SearchList.Drawn? {
        drawing(&state, owned: owned, list: list)?.drawn
    }

    // MARK: the box and the list drawn

    @Test func theListIsDrawnOnceTheLibrarySettlesAndThenFrozen() throws {
        var state = SearchState()
        let emptied = state.typed("  portishead ")
        #expect(emptied == .settle && state.query == "portishead")
        #expect(state.wantsLibrary)
        let early = Self.advance(&state)
        #expect(early == nil, "not asked yet")
        let token = state.askingLibrary()
        #expect(!state.wantsLibrary, "asked once for the words")
        #expect(state.library == .asking && !state.settled)
        let asking = Self.advance(&state)
        #expect(asking == nil, "still asking")
        let kept = state.libraryAnswered(token, "portishead", Self.found)
        #expect(kept && state.settled && state.resultsForQuery == Self.found)
        let drawingMade = Self.drawing(&state)
        let drawing = try #require(drawingMade)
        let drawn = drawing.drawn
        #expect(drawn.text == "portishead")
        #expect(drawn.top.map(\.key) == ["artist:ar-p", "album:nd-dummy", "song:s-roads"])
        #expect(drawn.sections?.map(\.kind) == [.artists, .albums, .songs])
        #expect(drawing.said == "In your library: 1 artist, 1 album, 2 songs. Nothing more found.")
        #expect(state.drawn == drawn)
        // drawn once per run: nothing new however often it is asked
        let again = Self.advance(&state)
        #expect(again == nil)
        // the same words with other spaces are the same words: no new run
        let spaced = state.typed("portishead  ")
        let still = Self.advance(&state)
        #expect(spaced == nil && still == nil)
    }

    @Test func newWordsKeepTheOldListUntilTheirsSettles() throws {
        var state = Self.answered("portishead")
        let oldMade = Self.advance(&state)
        let old = try #require(oldMade)
        state.typed("portishead third")
        #expect(state.drawn == old, "the old list stays while the new words are asked")
        #expect(state.wantsLibrary && !state.settled)
        let first = state.askingLibrary()
        state.typed("portishead thi")
        let second = state.askingLibrary()
        // the older ask's answer lands late: not kept
        let late = state.libraryAnswered(first, "portishead third", LibraryResults(albums: [Self.third]))
        let none = Self.advance(&state)
        #expect(!late && none == nil && state.drawn == old)
        let newest = state.libraryAnswered(second, "portishead thi", LibraryResults(albums: [Self.third]))
        let drawnMade = Self.advance(&state)
        let drawn = try #require(drawnMade)
        // Third, and its artist made of its own fields (Top results' family)
        #expect(newest && drawn.text == "portishead thi" && drawn.top.map(\.key) == ["album:nd-third", "artist:ar-p"])
    }

    @Test func anEmptyBoxLetsEverythingGo() {
        var state = Self.answered("dummy")
        _ = Self.advance(&state)
        state.choose(.albums)
        _ = state.askingKind()
        state.albumReady(Self.dummy)
        let token = state.askingLibrary()
        let emptied = state.typed("   ")
        #expect(emptied == .clear)
        #expect(state.query.isEmpty && state.drawn == nil && state.library == nil && state.libraryText == nil)
        #expect(state.kind == nil && state.ready.isEmpty && state.view == .all)
        #expect(!state.wantsLibrary && !state.wantsKind)
        // what was asked before it emptied counts for nothing
        let kept = state.libraryAnswered(token, "dummy", Self.found)
        #expect(!kept && state.library == nil)
    }

    @Test func aFailureIsDrawnAndAskedAgainOnlyWhenAskedTo() throws {
        var state = SearchState()
        state.typed("portishead dummy")
        let token = state.askingLibrary()
        let failed = state.libraryFailed(token, "portishead dummy")
        #expect(failed && state.settled && state.library == .failed && state.results == nil)
        // the named artist still leads Artists, from the full list
        let drawnMade = Self.advance(&state, owned: ["Portishead"], list: [Self.portishead])
        let drawn = try #require(drawnMade)
        #expect(drawn.failed && !drawn.nothing)
        #expect(drawn.sections?.map(\.kind) == [.artists])
        #expect(drawn.top.map(\.key) == ["artist:ar-p"])
        // the keyboard's Search asks again, and the answer is drawn afresh
        #expect(state.wantsLibrary)
        state.submitted()
        let again = state.askingLibrary()
        #expect(state.library == .asking, "a failure isn't an answer to keep while asking again")
        state.libraryAnswered(again, "portishead dummy", LibraryResults(albums: [Self.dummy]))
        let redrawnMade = Self.advance(&state, owned: ["Portishead"], list: [Self.portishead])
        let redrawn = try #require(redrawnMade)
        #expect(!redrawn.failed && redrawn.top.first?.key == "album:nd-dummy")
    }

    @Test func tryAgainAndBackToAllDrawAfresh() throws {
        var state = Self.answered("dummy")
        let firstMade = Self.advance(&state)
        let first = try #require(firstMade)
        #expect((first.sections ?? []).flatMap(\.rows).map(\.key).contains("album:nd-dummy"))
        // a chip and back: drawn again from what is in hand, its lines as they are now
        let chose = state.choose(.albums)
        let inKind = Self.advance(&state)
        #expect(chose && inKind == nil, "never in a kind view")
        let same = state.choose(.albums)
        let back = state.choose(.all)
        let redrawn = Self.advance(&state)
        #expect(!same && back && redrawn != nil)
        // Try again: asked again, then drawn afresh
        state.tryAgain()
        #expect(state.wantsLibrary)
        let token = state.askingLibrary()
        #expect(state.settled, "the words' answer stays while it is asked again")
        state.libraryAnswered(token, "dummy", Self.found)
        let afresh = Self.advance(&state)
        #expect(afresh != nil)
    }

    @Test func aLibraryNotThereIsSkippedNotNothingFound() throws {
        var state = SearchState()
        state.typed("roads")
        state.librarySkipped()
        #expect(state.settled && !state.wantsLibrary)
        let drawingMade = Self.drawing(&state)
        let drawing = try #require(drawingMade)
        let drawn = drawing.drawn
        //? MusicBrainz finding nothing as well: "No results", as the web's says it (a skipped library is no problem drawn)
        #expect(drawn.skipped && !drawn.failed && drawn.nothing)
        #expect(drawing.said == "Nothing more found.", "nothing said of the library, which wasn't searched")
        // and with nothing found it is "No results"
        var empty = Self.answered("zzz", LibraryResults())
        let noneMade = Self.advance(&empty)
        let none = try #require(noneMade)
        #expect(none.nothing && SearchWords.nothing(.all, none.text) == "No results for \u{201C}zzz\u{201D}.")
    }

    @Test func deadwaxBackAsksAFailedLibraryAgainAndDrawsItsAnswer() throws {
        // (7291225's review) a first search over a dropping connection runs and fails - its failure drawn - before the
        // phone counts itself offline; deadwax answering again asks it again, and the answer takes the failure's place
        var state = SearchState()
        state.typed("roads")
        let token = state.askingLibrary()
        state.libraryFailed(token, "roads")
        let failedMade = Self.advance(&state)
        let failed = try #require(failedMade)
        #expect(failed.failed)
        // asked again without a new run, the answer would be drawn nowhere: the failure stays (the bug)
        var stale = state
        let staleToken = stale.askingLibrary()
        stale.libraryAnswered(staleToken, "roads", Self.found)
        let nowhere = Self.advance(&stale)
        #expect(nowhere == nil && stale.drawn == failed)
        // resumed: asked again, and drawn afresh once it lands
        let resumed = state.resumed()
        #expect(resumed && state.wantsLibrary)
        let again = state.askingLibrary()
        let asking = Self.advance(&state)
        #expect(asking == nil && state.drawn == failed, "the failure stays drawn while it is asked again")
        state.libraryAnswered(again, "roads", Self.found)
        let answeredMade = Self.advance(&state)
        let answered = try #require(answeredMade)
        #expect(!answered.failed && answered.top.first?.key == "song:s-roads")
    }

    @Test func navidromeFoundAgainAsksASkippedLibraryAndDrawsItsAnswer() throws {
        var state = SearchState()
        state.typed("roads")
        state.librarySkipped()
        let skippedMade = Self.advance(&state)
        let skipped = try #require(skippedMade)
        #expect(skipped.skipped && !state.wantsLibrary)
        let resumed = state.resumed()
        #expect(resumed && state.wantsLibrary)
        let token = state.askingLibrary()
        state.libraryAnswered(token, "roads", Self.found)
        let answeredMade = Self.advance(&state)
        let answered = try #require(answeredMade)
        #expect(!answered.skipped && answered.sections?.map(\.kind) == [.artists, .albums, .songs])
    }

    @Test func resumingLeavesAnAnswerAndAKindViewsRunAlone() throws {
        // an answer for the words: nothing to ask again, no new run
        var state = Self.answered("roads")
        _ = Self.advance(&state)
        let resumed = state.resumed()
        let none = Self.advance(&state)
        #expect(!resumed && !state.wantsLibrary && none == nil)
        // a failure for other words than the box's: the box's own are asked as they always are
        var other = SearchState()
        other.typed("roads")
        let token = other.askingLibrary()
        other.libraryFailed(token, "roads")
        other.typed("glory")
        let forOther = other.resumed()
        #expect(!forOther && other.wantsLibrary)
        // a failure while a chip is on: asked again, drawn when All is chosen - All draws afresh anyway
        var kind = SearchState()
        kind.typed("roads")
        kind.choose(.songs)
        let failed = kind.askingLibrary()
        kind.libraryFailed(failed, "roads")
        let resumedInKind = kind.resumed()
        #expect(resumedInKind && kind.wantsLibrary)
        let again = kind.askingLibrary()
        kind.libraryAnswered(again, "roads", Self.found)
        let inKind = Self.advance(&kind)
        kind.choose(.all)
        let allMade = Self.advance(&kind)
        let all = try #require(allMade)
        #expect(inKind == nil && !all.failed)
    }

    @Test func backToWordsAlreadyAnsweredDrawsWithoutAsking() throws {
        // (7291225's review) "port" asked, "porta" typed, "port"'s answer lands under "porta" - then back to "port"
        // inside the pause: nothing to ask, and its list is drawn at once (the web's advance runs on every render)
        var state = SearchState()
        state.typed("port")
        let token = state.askingLibrary()
        state.typed("porta")
        let kept = state.libraryAnswered(token, "port", Self.found)
        let underOther = Self.advance(&state)
        #expect(kept && underOther == nil, "not the box's words")
        state.typed("port")
        #expect(!state.wantsLibrary && state.settled)
        let drawnMade = Self.advance(&state)
        let drawn = try #require(drawnMade)
        #expect(drawn.text == "port" && drawn.top.map(\.key) == ["artist:ar-p", "album:nd-dummy", "song:s-roads"])
    }

    @Test func aRowNamedTwiceIsDrawnOnce() {
        // search3 can name a song twice; a ForEach can't draw one id twice - the first is kept, the order is search3's
        let rows: [SearchRow] = [.song(Self.roads), .song(Self.glory), .song(Self.roads), .album(Self.dummy),
                                 .artist(Self.portishead), .album(Self.dummy)]
        let drawn = SearchList.drawable(rows)
        #expect(drawn.map(\.key) == ["song:s-roads", "song:s-glory", "album:nd-dummy", "artist:ar-p"])
        #expect(SearchList.drawable([]).isEmpty)
        // a song and its album share an id's words, never a key
        let same = Song(id: "nd-dummy", title: "Dummy")
        #expect(SearchList.drawable([.album(Self.dummy), .song(same)]).count == 2)
    }

    // MARK: a kind view's own

    @Test func aKindViewAsksItsOwnAndMoreByOffset() throws {
        var state = Self.answered("live")
        #expect(!state.wantsKind, "All asks no kind of its own")
        state.choose(.albums)
        #expect(state.wantsKind && state.libraryAskedForQuery)
        let askedMade = state.askingKind()
        let asked = try #require(askedMade)
        let twice = state.askingKind()
        #expect(asked.kind == .albums && twice == nil, "asked once for the words and the kind")
        // it fails, and is asked again: the first ask's answer, landing late, counts for nothing
        let failed = state.kindFailed(asked.token)
        #expect(failed && state.wantsKind)
        let newestMade = state.askingKind()
        let newest = try #require(newestMade)
        let page = (0..<50).map { Album(id: "al-\($0)", name: "Live \($0)") }
        let late = state.kindAnswered(asked.token, LibraryResults(albums: page))
        let kept = state.kindAnswered(newest.token, LibraryResults(albums: page))
        #expect(!late && kept, "only the newest ask's")
        let shown = try #require(state.kindShown)
        #expect(shown.rows.count == 50 && shown.full && !state.wantsKind)
        #expect(shown.moreOffsets == SearchCounts.only(.albums, 50))
        // the albums in hand by id: the kind view's are among them
        #expect(state.knownAlbums["al-7"]?.name == "Live 7")
        let moreMade = state.askingMore()
        let more = try #require(moreMade)
        #expect(more.offsets == SearchCounts.only(.albums, 50) && more.kind == .albums && more.text == "live")
        let whileAsking = state.askingMore()
        #expect(whileAsking == nil, "not while More asks")
        // the next page: one repeated, appended without it; fewer than asked - no More after it
        let next = [page[49]] + (50..<60).map { Album(id: "al-\($0)", name: "Live \($0)") }
        let held = state.moreAnswered(more.token, LibraryResults(albums: next))
        #expect(held == 11)
        let grown = try #require(state.kindShown)
        #expect(grown.rows.count == 60 && !grown.full && grown.moreOffsets == nil)
        #expect(SearchWords.moreSaid(11, .albums, personal: false) == "11 more albums from your library")
        #expect(SearchWords.moreSaid(1, .songs, personal: true) == "1 more song from the collection")
    }

    @Test func aFullPageWithNothingNewEndsMore() {
        var library = KindLibrary(text: "x", kind: .artists)
        let page = (0..<50).map { Artist(id: "ar-\($0)") }
        library.answered(LibraryResults(artists: page))
        #expect(library.full)
        library.moreAsked()
        #expect(library.moreOffsets == nil)
        let held = library.moreAnswered(LibraryResults(artists: page))
        #expect(held == 50 && !library.full && library.rows.count == 50)
        library.moreFailed()
        #expect(library.more == .failed)
        var failed = KindLibrary(text: "x", kind: .songs)
        failed.failed()
        #expect(!failed.holds("x", .songs) && failed.moreOffsets == nil)
        #expect(KindLibrary(text: "x", kind: .songs).holds("x", .songs))
        #expect(!KindLibrary(text: "x", kind: .songs).holds("y", .songs))
    }

    @Test func aKindViewForOtherWordsIsNotShown() throws {
        var state = Self.answered("live")
        state.choose(.songs)
        let askMade = state.askingKind()
        let ask = try #require(askMade)
        state.kindAnswered(ask.token, LibraryResults(songs: [Self.roads]))
        #expect(state.kindShown?.rows.map(\.key) == ["song:s-roads"])
        state.typed("live at")
        #expect(state.kindShown == nil && state.wantsKind)
        #expect(!state.libraryAskedForQuery, "the new words aren't asked yet: the chip waits for the pause")
        state.kindSkipped()
        #expect(state.kindShown?.state == .skipped && state.wantsKind, "skipped is asked again once Navidrome is back")
    }

    // MARK: a song's tap

    @Test func aSongPlaysOnlyFromItsAlbumInHand() {
        let album = Album(id: "nd-dummy", name: "Dummy", song: [Self.roads, Self.glory])
        #expect(SearchPacing.plays(Self.roads, ready: ["nd-dummy": album]))
        #expect(!SearchPacing.plays(Self.rip, ready: ["nd-dummy": album]), "its album not in hand")
        #expect(!SearchPacing.plays(Song(id: "s-roads", title: "Roads", albumId: "nd-dummy"),
                                    ready: ["nd-dummy": Album(id: "nd-dummy", song: [Self.glory])]), "not among its songs")
        #expect(!SearchPacing.plays(Song(id: "s-loose", title: "Loose"), ready: ["": album]), "no album")
        #expect(SearchPacing.songIndex(album.song, "s-glory") == 1)
        #expect(SearchPacing.songIndex(nil, "s-glory") == nil)
    }

    @Test func theAlbumsAskedForArePrefetchedOnceAndKeptForTheBox() throws {
        var state = Self.answered("portishead", LibraryResults(artists: [Self.portishead], albums: [Self.dummy],
                                                               songs: [Self.rip, Self.roads, Self.glory]))
        let results = try #require(state.resultsForQuery)
        // Top results' songs first (Roads isn't among Top results - the Rip is the third pick), then the answer's
        let wanted = state.albumsWanted("portishead", results, artistList: nil, marks: Self.marks)
        #expect(wanted == ["nd-third", "nd-dummy"])
        state.albumReady(Album(id: "nd-third", song: [Self.rip]))
        #expect(state.albumsWanted("portishead", results, artistList: nil, marks: Self.marks)
                == ["nd-dummy"], "not asked again")
        // an album asked beside an older ask is not kept
        let stale = state.askingLibrary()
        _ = state.askingLibrary()
        state.albumReady(Album(id: "nd-dummy", song: [Self.roads]), library: stale)
        #expect(state.ready["nd-dummy"] == nil)
        // search3's own album is preferred over one asked for (its star, its release), and kept for the box
        state.albumReady(Album(id: "nd-dummy", name: "Dummy (asked)", song: [Self.roads]))
        #expect(state.knownAlbums["nd-dummy"]?.name == "Dummy")
        #expect(state.ready["nd-dummy"]?.song?.count == 1)
    }

    /// No two of the library's candidates tie in slice 1 (each kind's positions differ), but slice 2's brought rows
    /// will: tied candidates keep their order, as JavaScript's sort (stable) keeps it.
    @Test func tiedCandidatesKeepTheirOrderAsJavaScriptsSortDoes() {
        let roads = SearchList.Candidate(row: .song(Self.roads), tier: 3, source: 0, position: 0)
        let glory = SearchList.Candidate(row: .song(Self.glory), tier: 3, source: 0, position: 0)
        #expect(SearchList.topResults([roads, glory], n: 1, library: nil, artistList: nil).map(\.key) == ["song:s-roads"])
        #expect(SearchList.topResults([glory, roads], n: 1, library: nil, artistList: nil).map(\.key) == ["song:s-glory"])
        // and a better one is first wherever it stands
        let better = SearchList.Candidate(row: .song(Self.rip), tier: 2, source: 0, position: 5)
        #expect(SearchList.topResults([roads, glory, better], n: 1, library: nil, artistList: nil).map(\.key)
                == ["song:s-rip"])
    }

    // MARK: whose, the phone's own parts

    @Test func yourAlbumsAreCountedByTheirArtist() {
        let yours = SearchMarks.yours([IndexAlbum(id: "a", artistId: "ar-p"), IndexAlbum(id: "b", artistId: "ar-p"),
                                       IndexAlbum(id: "c", artistId: ""), IndexAlbum(id: "d")])
        #expect(yours.ids == ["a", "b", "c", "d"])
        #expect(yours.artists == ["ar-p": 2])
        let marks = SearchMarks(personal: true, yourAlbums: yours.ids, yourArtists: yours.artists)
        #expect(SearchList.line(.artist(Self.portishead), marks).place == "2 albums in your library")
        #expect(SearchList.line(.artist(Self.portishead), marks, top: true).said == "Artist \u{00B7} 2 albums in your library")
        #expect(SearchList.line(.artist(Artist(id: "ar-x", albumCount: 4)), marks).place == "4 albums in the collection")
        #expect(SearchList.line(.album(Self.third), SearchMarks(personal: true)).said == "Portishead \u{00B7} 2008",
                "nothing said while whose can't be told")
    }

    @Test func theWordsThePhoneAddsAreItsOwn() {
        #expect(SearchWords.hint(personal: false) == "Search your library and albums you don't have yet.")
        #expect(SearchWords.hint(personal: true) == "Search your library, the collection, and albums nobody has yet.")
        #expect(SearchWords.chip(.all) == "All" && SearchWords.section(.songs) == "Songs")
        #expect(SearchWords.seeAllLabel(.albums) == "See all albums")
        #expect(SearchView(.artists) == .artists && SearchView.all.kind == nil)
        #expect(SearchList.Line(line: "", place: "in your library").said == "in your library")
    }

    // MARK: the answers

    @Test func search3IsReadLeniently() throws {
        let json = #"{"artists":"none","albums":[{"id":"al"},{"name":"no id"}],"songs":[{"id":"so","title":"Roads"}],"extra":1}"#
        let read = try JSONDecoder().decode(LibraryResults.self, from: Data(json.utf8))
        #expect(read.artists.isEmpty)
        #expect(read.albums.map(\.id) == ["al"])
        #expect(read.songs.map(\.id) == ["so"])
        #expect(read.counts == [.artists: 0, .albums: 1, .songs: 1])
        let none = try JSONDecoder().decode(LibraryResults.self, from: Data("{}".utf8))
        #expect(none == LibraryResults())
    }

    @Test func theFoldersAreReadLeniently() throws {
        let json = #"""
        {"albums":[
          {"path":"Portishead/Dummy","artist":" Portishead ","album":"Dummy","year":1994,"release_mbid":"rel-dummy",
           "release_group_mbid":"rg-dummy","formats":["FLAC",3],"track_count":11,"albumartist_mbids":["mb-p"],"yours":true},
          {"path":"Portishead/Third","artist":"Portishead","year":"2008","track_count":"eleven","yours":"no"},
          {"path":"Unknown/x","artist":""},
          "not an album"
        ],"problem":null}
        """#
        let read = try JSONDecoder().decode(OwnedAnswer.self, from: Data(json.utf8))
        #expect(read.albums.map(\.path) == ["Portishead/Dummy", "Portishead/Third", "Unknown/x"])
        #expect(read.albums[0].year == "1994" && read.albums[1].year == "2008")
        #expect(read.albums[0].formats == ["FLAC"] && read.albums[0].trackCount == 11)
        #expect(read.albums[1].trackCount == nil && read.albums[1].yours == nil)
        #expect(read.albums[0].releaseMbid == "rel-dummy" && read.albums[0].albumartistMbids == ["mb-p"])
        #expect(read.problem == nil)
        #expect(read.artists == ["Portishead"], "trimmed, once, none empty")
        let problem = try JSONDecoder().decode(OwnedAnswer.self, from: Data(#"{"albums":[],"problem":"LIBRARY_PATH is not set"}"#.utf8))
        #expect(problem.albums.isEmpty && problem.problem == "LIBRARY_PATH is not set")
    }

    @Test func theLibraryIsAskedWithItsCountsAndOffsetsAboveNothing() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/navidrome/search", 200, #"{"artists":[],"albums":[{"id":"al"}],"songs":[]}"#)
        let found = try await deadwax.searchLibrary("portishead", counts: SearchPacing.all)
        #expect(found.albums.map(\.id) == ["al"])
        var items = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.map(\.name) == ["q", "artistCount", "albumCount", "songCount"])
        #expect(items.map { (item: URLQueryItem) -> String in item.value ?? "-" } == ["portishead", "5", "8", "12"])
        _ = try await deadwax.searchLibrary("live", counts: SearchPacing.chip(.albums), offsets: .only(.albums, 50))
        items = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.map(\.name) == ["q", "artistCount", "albumCount", "songCount", "albumOffset"])
        #expect(items.map { (item: URLQueryItem) -> String in item.value ?? "-" } == ["live", "0", "50", "0", "50"])
        _ = try await deadwax.searchLibrary("x", counts: SearchPacing.chip(.artists), offsets: .only(.artists, 50))
        items = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.last?.name == "artistOffset")
        _ = try await deadwax.searchLibrary("x", counts: SearchPacing.chip(.songs), offsets: .only(.songs, 100))
        items = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.last?.name == "songOffset" && items.last?.value == "100")
    }

    @Test func theFoldersAreAskedWithTheirETag() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.handle("/deadwax/library/owned") { request in
            if request.headers["If-None-Match"] == #""o1""# { return HTTPResponse(status: 304, headers: ["ETag": #""o1""#]) }
            return HTTPResponse(status: 200, headers: ["ETag": #""o1""#],
                                body: Data(#"{"albums":[{"path":"A/1","artist":"A"}],"problem":null}"#.utf8))
        }
        let first = try await deadwax.owned(ifNoneMatch: nil)
        #expect(first == .fresh(OwnedAnswer(albums: [OwnedAlbum(path: "A/1", artist: "A")]), etag: #""o1""#))
        #expect(transport.last?.url.path == "/deadwax/library/owned" && transport.last?.timeout == 30)
        #expect(try await deadwax.owned(ifNoneMatch: #""o1""#) == .unchanged)
    }
}
