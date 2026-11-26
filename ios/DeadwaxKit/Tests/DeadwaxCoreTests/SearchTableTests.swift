import Foundation
import Testing
@testable import DeadwaxCore

/// The redesign's slice R7 (notes/ios.md "The redesign, slice R7: Search, Get and Sources (2026-11-25)"): the Mac's
/// Search table - its columns at the widths the review fits (1280's page 1060, 880's 660, beside the panel 589), what a
/// row says in them, its buttons and the status bar's counts - and the Get page's and Sources' words.
@Suite struct SearchTableTests {
    static let held = OwnedIndex([OwnedAlbum(path: "P/Third", artist: "Portishead", album: "Third",
                                             releaseGroupMbid: SearchAlbumsTests.third.id)])
    static let marks = SearchMarks(personal: false, index: held)
    static let unanswered = SearchMarks(personal: false, index: nil)

    // MARK: the columns

    @Test func everyColumnAtAWindowAsItFirstOpens() {
        let shown = SearchTable.columns(1060)
        #expect(shown == SearchTable.Column.allCases)
        #expect(shown.map(SearchTable.title) == ["Name", "Kind", "Artist", "Year", "In your library", ""])
        let widths = SearchTable.widths(shown, 1060)
        #expect(widths == [336, 100, 190, 64, 200, 170])
        #expect(widths.reduce(0, +) == 1060, "nothing scrolls sideways at 1280")
    }

    @Test func theYearThenTheKindThenTheArtistGiveWay() {
        #expect(SearchTable.columns(884) == SearchTable.Column.allCases)
        #expect(SearchTable.columns(883) == [.name, .kind, .artist, .place, .actions])
        #expect(SearchTable.columns(820) == [.name, .kind, .artist, .place, .actions])
        #expect(SearchTable.columns(819) == [.name, .artist, .place, .actions])
        #expect(SearchTable.columns(719) == [.name, .place, .actions])
        // 880's page, and the page beside the side panel at 1280: the name, the place and the buttons, none scrolling
        for page in [660.0, 589] {
            let shown = SearchTable.columns(page)
            #expect(shown == [.name, .place, .actions])
            #expect(SearchTable.tableWidth(shown, page) == page)
            #expect(SearchTable.widths(shown, page).first! >= SearchTable.nameLeast)
        }
        // narrower than even those: the table keeps the name's least and scrolls
        #expect(SearchTable.tableWidth([.name, .place, .actions], 400) == 530)
    }

    @Test func theNamesLeastGrowsWithTheRowsCover() {
        #expect(SearchTable.nameLeast(.small) == 160)
        #expect(SearchTable.nameLeast(.large) == 160 + MacRowSize.large.requestCoverGrowth)
        // a larger row gives up the year sooner
        #expect(SearchTable.columns(884, size: .small) == SearchTable.Column.allCases)
        #expect(SearchTable.columns(884, size: .large) != SearchTable.Column.allCases)
    }

    // MARK: a row's cells

    @Test func aRowSaysItsKindArtistYearAndPlace() {
        let artist = SearchTable.cells(.artist(SearchAlbumsTests.portishead), Self.marks)
        #expect(artist.kind == "Artist" && artist.artist == "" && artist.year == "")
        #expect(artist.place == "3 albums in your library" && artist.held)
        let album = SearchTable.cells(.album(SearchAlbumsTests.dummy), Self.marks)
        #expect(album == SearchTable.Cells(kind: "Album", artist: "Portishead", year: "1994", place: "in your library",
                                           held: true))
        let song = SearchTable.cells(.song(SearchAlbumsTests.roads), Self.marks)
        #expect(song.kind == "Song" && song.artist == "Portishead" && song.held)
        // MusicBrainz's: held by the index, or said not to be once the library has answered - nothing before it has
        let third = SearchTable.cells(.group(SearchAlbumsTests.third), Self.marks)
        #expect(third == SearchTable.Cells(kind: "Album", artist: "Portishead", year: "2008", place: "in your library",
                                           held: true))
        let live = SearchTable.cells(.group(SearchAlbumsTests.roseland), Self.marks)
        #expect(live.kind == "Live album" && live.year == "1998" && live.place == "not in your library" && !live.held)
        #expect(SearchTable.cells(.group(SearchAlbumsTests.roseland), Self.unanswered).place == "")
        let match = MBArtistMatch(mbid: "m", name: "Portishead", disambiguation: "UK trip hop band", country: "GB",
                                  type: "Group", matchedAs: "")
        let mb = SearchTable.cells(.mbArtist(match), Self.marks)
        #expect(mb.kind == "Artist" && mb.place == "" && !mb.held && mb.about == match.line)
    }

    // MARK: a row's buttons

    @Test func aRowsButtonsAreWhatItCanDoItsMainOneFirst() {
        let roads = SearchRow.song(SearchAlbumsTests.roads)
        #expect(SearchTable.actions(roads, plays: true, held: true) == [.play, .open])
        #expect(SearchTable.actions(roads, plays: false, held: true) == [.open])
        #expect(SearchTable.actions(roads, plays: false, held: true, opens: false) == [])
        #expect(SearchTable.actions(.artist(SearchAlbumsTests.portishead), plays: true, held: true) == [.open])
        #expect(SearchTable.actions(.album(SearchAlbumsTests.dummy), plays: true, held: true) == [.open],
                "no album Play: its songs aren't in hand")
        #expect(SearchTable.actions(.group(SearchAlbumsTests.third), plays: false, held: true) == [.open])
        #expect(SearchTable.actions(.group(SearchAlbumsTests.roseland), plays: false, held: false) == [.get])
        #expect(SearchTable.Action.allCases.map(\.words) == ["Play", "Open", "Get"])
        #expect(SearchTable.Action.get.spoken("Roseland NYC Live") == "Get Roseland NYC Live")
        #expect(SearchTable.Action.play.spoken("") == "Play")
    }

    // MARK: the status bar and the toolbar

    @Test func theStatusCountsTheRowsDrawnAndThoseHeld() {
        let rows: [SearchRow] = [.artist(SearchAlbumsTests.portishead), .album(SearchAlbumsTests.dummy),
                                 .group(SearchAlbumsTests.third), .group(SearchAlbumsTests.roseland),
                                 .song(SearchAlbumsTests.roads)]
        #expect(SearchTable.status(rows, Self.marks) == ["1 artist", "3 albums", "1 song", "4 in your library"])
        #expect(SearchTable.status([], Self.marks) == [])
        #expect(SearchTable.status([.group(SearchAlbumsTests.roseland)], Self.marks) == ["1 album"])
    }

    @Test func theTablesLinesAreInTheOrderDrawn() {
        let artist = SearchRow.artist(SearchAlbumsTests.portishead)
        let dummy = SearchRow.album(SearchAlbumsTests.dummy)
        let third = SearchRow.group(SearchAlbumsTests.third)
        let drawn = SearchList.Drawn(text: "portishead", top: [artist, dummy],
                                     sections: [.init(kind: .artists, rows: [artist]),
                                                .init(kind: .albums, rows: [dummy, third, dummy])],
                                     failed: false, counts: [:])
        // Top results' lines apart from the same rows again in their sections; a row drawn twice in one, once
        #expect(SearchTable.order(drawn, online: true)
                == ["top|artist:ar-p", "top|album:nd-dummy", "artist:ar-p", "album:nd-dummy", third.key])
        // MusicBrainz's left out while deadwax can't be reached, as the list leaves them out
        #expect(SearchTable.order(drawn, online: false)
                == ["top|artist:ar-p", "top|album:nd-dummy", "artist:ar-p", "album:nd-dummy"])
        #expect(SearchTable.lineID(third, top: true) == "top|" + third.key)
    }

    @Test func theToolbarsHeadingAndWayToRequests() {
        #expect(SearchTable.heading("portishead ") == "Results for \u{201C}portishead\u{201D}")
        #expect(SearchTable.heading("  ") == "Search")
        #expect(SearchTable.byHand == "Search Soulseek by hand\u{2026}")
    }

    // MARK: the Get page

    @Test func theGetPagesLines() {
        #expect(GetPageWords.pressings(7) == "7 pressings" && GetPageWords.pressings(1) == "1 pressing")
        #expect(GetPageWords.factsLine("Official \u{00B7} Cat. no. 539 189-2", pressings: 7)
                == "Official \u{00B7} Cat. no. 539 189-2 \u{00B7} 7 pressings")
        #expect(GetPageWords.factsLine("Official", pressings: 1) == "Official")
        #expect(GetPageWords.factsLine("", pressings: 3) == "3 pressings")
        func track(_ length: String) -> PressingTrack {
            PressingTrack(key: length, heading: nil, number: "1", title: "t", length: length, mark: nil)
        }
        #expect(GetPageWords.songsLine([track("4:38"), track("3:59"), track("4:18")]) == "3 songs \u{00B7} 13 min")
        #expect(GetPageWords.songsLine([track("4:38"), track("")]) == "2 songs", "a length missing: no total")
        #expect(GetPageWords.songsLine([track("0:20")]) == "1 song \u{00B7} 1 min")
        #expect(GetPageWords.songsLine([track("1:02:00"), track("10:00")]) == "2 songs \u{00B7} 1 hr 12 min")
        #expect(GetPageWords.songsLine([]) == "")
        #expect(GetPageWords.seconds("4:x8") == nil && GetPageWords.seconds("438") == nil)
        #expect(GetPageWords.minutes(3600) == "1 hr")
        #expect(GetPageWords.status([track("4:38")], pressing: "CD \u{00B7} 1997") == ["1 song \u{00B7} 5 min", "CD \u{00B7} 1997"])
        #expect(GetPageWords.status([], pressing: "") == [])
        // the Mac's third column: a mark's note, else the same - where there is a usual tracklist to say it against
        let bonus = PressingTrack.Mark(kind: .bonus, chip: "Bonus", note: "Only on this pressing")
        #expect(GetPageWords.against(bonus, compared: true) == "Only on this pressing")
        #expect(GetPageWords.against(nil, compared: true) == "the same")
        #expect(GetPageWords.against(nil, compared: false) == "")
    }

    @Test func sourcesWords() {
        #expect(SourcesLook.close == "Close" && SourcesLook.found(14) == "14 found" && SourcesLook.sort == "Sort")
        // (R7's review) the filters hiding some: how many of them are shown - the foot's two numbers
        #expect(SourcesLook.found(14, shown: 14) == "14 found")
        #expect(SourcesLook.found(14, shown: 3) == "3 of 14")
        #expect(SourcesLook.found(14, shown: 13) == "13 of 14", "one hidden")
        #expect(SourcesLook.found(14, shown: 0) == "0 of 14", "none through the filters")
        #expect(SourcesLook.found(1, shown: 1) == "1 found")
        let folders = (0..<14).map { (at: Int) -> Candidate in Candidate(username: "p\(at)", score: 0.9) }
        let answer = FindCandidatesAnswer(query: "Portishead Third", candidates: folders)
        #expect(Sources.searchedLine(answer, shown: 3).contains("14 sources, 3 match your filters"))
    }

    /// (R7's review) Sample rate ▾ beside the sort: the web panel's floors, in its words, laid on the chips' filters.
    @Test func theSampleRateFloor() {
        #expect(SourcesLook.sampleRates.map(\.value) == [0, 44100, 48000, 88200, 96000])
        #expect(SourcesLook.sampleRates.map(\.chip) == ["Sample rate", "44.1 kHz+", "48 kHz+", "88.2 kHz+", "96 kHz+"])
        #expect(SourcesLook.sampleRates.map(\.label)
                == ["Any sample rate", "44.1 kHz or more", "48 kHz or more", "88.2 kHz or more", "96 kHz or more"])
        #expect(SourcesLook.sampleRate(48000).chip == "48 kHz+" && SourcesLook.sampleRate(12345).value == 0)
        // laid on what the chips ask, nothing else changed
        var chips = SourceFilters.none
        chips.lossless = true
        var expected = GetSettings.candidateFilters(chips)
        expected.quality.minSampleRate = 96000
        #expect(SourcesLook.filters(chips, minSampleRate: 96000) == expected)
        #expect(SourcesLook.filters(chips, minSampleRate: 0) == GetSettings.candidateFilters(chips))
        // a folder judged by its WORST file, and one reporting none never passes a floor
        let mixed = Candidate(username: "a", score: 0.9, sampleRates: [96000, 44100])
        let hiRes = Candidate(username: "b", score: 0.9, sampleRates: [96000, 96000])
        let silent = Candidate(username: "c", score: 0.9)
        let floor = SourcesLook.filters(.none, minSampleRate: 96000)
        #expect(!Sources.passes(mixed, floor) && Sources.passes(hiRes, floor) && !Sources.passes(silent, floor))
        #expect(Sources.passes(silent, SourcesLook.filters(.none, minSampleRate: 0)))
        // the floor is one more filter on: Clear filters shows for it alone
        #expect(SourcesLook.pressed(.none, minSampleRate: 0) == 0)
        #expect(SourcesLook.pressed(.none, minSampleRate: 48000) == 1)
        #expect(SourcesLook.pressed(chips, minSampleRate: 48000) == 2)
    }

    /// (R7's review) The Mac's foot: the drawing's words while every speed shown is the peer's own average.
    @Test func theSpeedsNoteSaysWhatTheSpeedsAre() {
        let own = Candidate(username: "a", score: 0.9, uploadSpeed: 1_000_000)
        let measured = Candidate(username: "b", score: 0.9, uploadSpeed: 1_000_000, measuredSpeed: 500_000)
        #expect(SourcesLook.speeds([own]) == "Speeds are each peer's own average.")
        #expect(SourcesLook.speeds([own, measured]) == "Speeds are what you got from a peer before, else its own average.")
        #expect(SourcesLook.speeds([]) == SourcesLook.speedsOwn)
    }

    /// (R7's review) The table's stripes: every other row, starting again only under a heading - a kind view's runs
    /// one run.
    @Test func theStripesRunOnUnderEachHeading() {
        let artist = SearchRow.artist(SearchAlbumsTests.portishead)
        let dummy = SearchRow.album(SearchAlbumsTests.dummy)
        let third = SearchRow.group(SearchAlbumsTests.third)
        let drawn = SearchList.Drawn(text: "portishead", top: [artist, dummy],
                                     sections: [.init(kind: .artists, rows: [artist]),
                                                .init(kind: .albums, rows: [dummy, third])],
                                     failed: false, counts: [:])
        // Top results' second; the Artists' one unstriped, starting again; the Albums' second
        #expect(SearchTable.striped(drawn, online: true) == ["top|album:nd-dummy", third.key])
        #expect(SearchTable.striped(drawn, online: false) == ["top|album:nd-dummy"])
    }
}
