import Foundation
import Testing
@testable import DeadwaxCore

/// Search's albums you don't have (Phase 5, slice 2 - notes/ios-specs/phase5-search.md 2.7, 3.6 and 6.2): the moments
/// as SearchState draws them - Top results decided before MusicBrainz answers, the sections at the cap, a late answer
/// landing in or folded into its slot, Behind, the library late - the Albums view's MusicBrainz part, the album's page,
/// MusicBrainz's answers read leniently and the client's four calls. The web's rules themselves are held by
/// SearchAlbumsVectorTests.
@Suite struct SearchAlbumsTests {
    static let portisheadMB = "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"
    static let portishead = Artist(id: "ar-p", name: "Portishead", albumCount: 3, musicBrainzId: portisheadMB)
    static let dummy = Album(id: "nd-dummy", name: "Dummy", artist: "Portishead", artistId: "ar-p", year: 1994)
    static let roads = Song(id: "s-roads", title: "Roads", album: "Dummy", albumId: "nd-dummy", artist: "Portishead",
                            artistId: "ar-p")
    static let credit = [MBArtistCredit(name: "Portishead", artist: .init(id: portisheadMB, name: "Portishead"))]
    static let third = ReleaseGroup(id: "a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e01", title: "Third",
                                    firstReleaseDate: "2008-04-28", primaryType: "Album", secondaryTypes: [],
                                    artistCredit: credit)
    static let roseland = ReleaseGroup(id: "a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e03", title: "Roseland NYC Live",
                                       firstReleaseDate: "1998-11-02", primaryType: "Album", secondaryTypes: ["Live"],
                                       artistCredit: credit)
    static let marks = SearchMarks(personal: false, index: OwnedIndex([]))

    /// A state with `text` typed, the library asked and answered with `results`, and MusicBrainz asked.
    static func asked(_ text: String, _ results: LibraryResults?) throws -> (SearchState, SearchState.AlbumsAsk) {
        var state = SearchState()
        state.typed(text)
        let token = state.askingLibrary()
        if let results { state.libraryAnswered(token, state.query, results) }
        let askMade = state.askingMusicBrainz(state.query, view: .all)
        let ask = try #require(askMade)
        return (state, ask)
    }

    static func draw(_ state: inout SearchState, list: [Artist]? = [portishead]) -> SearchState.Drawing? {
        state.advance(artistList: list, marks: marks)
    }

    // MARK: the moments

    @Test func anAlbumNobodyHasLeadsTopResultsOnceItLands() throws {
        var (state, ask) = try Self.asked("roseland", LibraryResults())
        // moment 1: a phantom first - no prefix, so no Top results and no place, the sections' asking line
        let firstMade = Self.draw(&state)
        let first = try #require(firstMade)
        #expect(first.drawn.top.isEmpty && !first.drawn.topPlace && first.drawn.sections == nil)
        let nothingNew = Self.draw(&state)
        #expect(nothingNew == nil, "nothing new until the albums land or the cap passes")
        // the albums land: moment 2, Top results completed - the album, then its credited artist (the library's)
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: [Self.roseland], count: 1), query: ask.first,
                             index: Self.marks.index)
        let secondMade = Self.draw(&state)
        let second = try #require(secondMade)
        #expect(second.drawn.top.map(\.key) == ["group:\(Self.roseland.id)", "artist:ar-p"])
        #expect(second.drawn.sections?.map(\.kind) == [.albums] && second.drawn.sections?.first?.slot == nil)
        #expect(second.said == "Also found: 1 album.")
        state.noteBehind()
        #expect(!state.behind, "answered in time")
    }

    @Test func theCapDrawsTheSectionsWithASlotForTheAlbumsStillOut() throws {
        let found = LibraryResults(artists: [Self.portishead], albums: [Self.dummy], songs: [Self.roads])
        var (state, ask) = try Self.asked("portishead", found)
        // an artist read: the library's artist is the best there can be - Top results decided whole
        let firstMade = Self.draw(&state)
        let first = try #require(firstMade)
        #expect(first.drawn.top.map(\.key) == ["artist:ar-p", "album:nd-dummy", "song:s-roads"] && !first.drawn.topPlace)
        #expect(first.drawn.sections == nil && first.said == "In your library: 1 artist, 1 album, 1 song.")
        let nothingNew = Self.draw(&state)
        #expect(nothingNew == nil)
        let run = state.run.id
        let passed = state.capPassed(run: run), again = state.capPassed(run: run)
        #expect(passed && !again, "once")
        let secondMade = Self.draw(&state)
        let second = try #require(secondMade)
        let sections = try #require(second.drawn.sections)
        #expect(sections.map(\.kind) == [.artists, .albums, .songs])
        #expect(sections[1].slot == .asking && sections[1].rows.map(\.key) == ["album:nd-dummy"])
        #expect(second.drawn.studio, "the studio clause asked, its line drawn under Albums")
        state.noteBehind()
        #expect(state.behind, "late, with a kind out")
        // the albums land under Songs: folded into the slot, nothing below moves
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: [Self.third, Self.roseland]), query: ask.first,
                             index: Self.marks.index)
        let landedMade = Self.draw(&state)
        let landed = try #require(landedMade)
        let albums = try #require(landed.drawn.sections?[1])
        #expect(albums.rows.map(\.key) == ["album:nd-dummy"])
        #expect(albums.slot == .show([.group(Self.third), .group(Self.roseland)]))
        #expect(landed.said == "2 more albums found - Show them to see them. Also found: 2 albums.")
        let focus = state.showFolded(.albums)
        #expect(focus?.key == "group:\(Self.third.id)")
        #expect(state.drawn?.sections?[1].rows.map(\.key) == ["album:nd-dummy", "group:\(Self.third.id)", "group:\(Self.roseland.id)"])
        #expect(state.drawn?.sections?[1].slot == nil)

        // Behind: the next words' list is drawn whole at the library's moment, MusicBrainz's in its slot
        state.typed("portishead third")
        let token = state.askingLibrary()
        state.libraryAnswered(token, "portishead third", found)
        _ = state.askingMusicBrainz("portishead third", view: .all)
        let behindMade = Self.draw(&state)
        let behind = try #require(behindMade)
        #expect(behind.drawn.sections != nil && behind.drawn.sections?.first(where: { $0.kind == .albums })?.slot == .asking)
    }

    @Test func aLateAnswerLastInTheListIsDrawnInAndOneWithNothingSaysSo() throws {
        let found = LibraryResults(artists: [Self.portishead])
        var (state, ask) = try Self.asked("portishead", found)
        _ = Self.draw(&state)
        state.capPassed(run: state.run.id)
        let secondMade = Self.draw(&state)
        let second = try #require(secondMade)
        #expect(second.drawn.sections?.map(\.kind) == [.artists, .albums])
        // Albums the last section: drawn straight in
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: [Self.third]), query: ask.first, index: Self.marks.index)
        let landedMade = Self.draw(&state)
        let landed = try #require(landedMade)
        #expect(landed.drawn.sections?.last?.rows.map(\.key) == ["group:\(Self.third.id)"] && landed.drawn.sections?.last?.slot == nil)

        // nothing found, the section empty: it goes
        var (empty, emptyAsk) = try Self.asked("portishead", found)
        _ = Self.draw(&empty)
        empty.capPassed(run: empty.run.id)
        _ = Self.draw(&empty)
        empty.albumsAnswered(emptyAsk, FullySearchAnswer(), query: emptyAsk.first, index: Self.marks.index)
        let goneMade = Self.draw(&empty)
        let gone = try #require(goneMade)
        #expect(gone.drawn.sections?.map(\.kind) == [.artists])
        #expect(gone.said == "Nothing more found.")
    }

    @Test func everyAlbumHeldIsSaidAndAFailureDrawnWithTryAgain() throws {
        let found = LibraryResults(artists: [Self.portishead], albums: [Self.dummy], songs: [Self.roads])
        // folded with nothing to draw: everything found is held
        let held = OwnedIndex([OwnedAlbum(path: "P/Third", artist: "Portishead", album: "Third", releaseGroupMbid: Self.third.id)])
        let marks = SearchMarks(personal: false, index: held)
        var (state, ask) = try Self.asked("portishead", found)
        _ = state.advance(artistList: nil, marks: marks)
        state.capPassed(run: state.run.id)
        _ = state.advance(artistList: nil, marks: marks)
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: [Self.third]), query: ask.first, index: held)
        let saidMade = state.advance(artistList: nil, marks: marks)
        let said = try #require(saidMade)
        //? held, but its folder isn't search3's: brought in - so it isn't "everything held" but a row folded in
        #expect(said.drawn.sections?[1].slot == .show([.group(Self.third)]))

        // the albums fail before the cap: every kind asked failed - the foot's words and Try again, MusicBrainz away
        var (failing, failingAsk) = try Self.asked("portishead", found)
        _ = Self.draw(&failing)
        let away = MBFailure.of(APIFailure.answered(.init(status: 503, method: "GET", path: "/search_musicbrainz/fully_search")),
                                admin: false)
        #expect(away.unavailable && !away.busy && !away.refused)
        failing.albumsFailed(failingAsk, away)
        let drawnMade = Self.draw(&failing)
        let drawn = try #require(drawnMade)
        #expect(drawn.drawn.allFailed == away && drawn.drawn.holdsLibrary)
        #expect(SearchWords.failure(away) == "Searching for more isn't working right now - try again in a few minutes.")
        failing.noteBehind()
        #expect(failing.behind, "MusicBrainz away")
        // Try again: drawn afresh, the albums asked again
        failing.tryMusicBrainzAgain()
        let askedAgain = failing.askingMusicBrainz(failing.query, view: .all)
        #expect(askedAgain != nil)

        // refused (a 422 with words): its words, no Try again, never Behind
        let refused = MBFailure.of(APIFailure.answered(.init(status: 422, method: "GET", path: "/x", detail: "Too long.")),
                                   admin: false)
        #expect(refused.refused && refused.message == "Too long." && SearchWords.failure(refused, short: true) == "Too long.")
        let busy = MBFailure.of(APIFailure.answered(.init(status: 503, method: "GET", path: "/x", busy: true)), admin: false)
        #expect(busy.busy && SearchWords.failure(busy) == "Too many searches just now - try again in a moment.")
        // busy only as a 503 says it (failureOf): a body saying busy on any other status is that status's failure
        let notBusy = MBFailure.of(APIFailure.answered(.init(status: 500, method: "GET", path: "/x", busy: true)), admin: false)
        #expect(!notBusy.busy && !notBusy.unavailable && !notBusy.refused)
    }

    @Test func aLateLibraryKeepsItsPlaceAndShowThemDrawsItIn() throws {
        var state = SearchState()
        state.typed("roseland")
        let token = state.askingLibrary()
        let askMade = state.askingMusicBrainz("roseland", view: .all)
        let ask = try #require(askMade)
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: [Self.roseland]), query: ask.first, index: Self.marks.index)
        let unsettled = Self.draw(&state)
        #expect(unsettled == nil, "the library hasn't settled")
        let term = state.armingLibraryLate()
        let isLate = state.libraryLatePassed(term)
        #expect(isLate)
        let lateMade = Self.draw(&state)
        let late = try #require(lateMade)
        #expect(late.drawn.libraryLate && late.drawn.sections?.map(\.kind) == [.albums])
        #expect(state.libraryLateSlot == .asking)
        state.libraryAnswered(token, "roseland", LibraryResults(albums: [Self.dummy]))
        let stays = Self.draw(&state)
        #expect(state.libraryLateSlot == .show(1) && stays == nil, "the list drawn stays")
        state.showLibrary()
        let wholeMade = Self.draw(&state)
        let whole = try #require(wholeMade)
        #expect(!whole.drawn.libraryLate && whole.drawn.sections?.map(\.kind) == [.albums])
        #expect(whole.drawn.sections?.first?.rows.first?.key == "album:nd-dummy")
        // and once it has settled, its clock passing is nothing
        let lateAgain = state.libraryLatePassed("roseland")
        #expect(!lateAgain)
    }

    /// (slice 2's review) Words typed while deadwax can't be reached: nothing asked, and no late clock run (SearchModel
    /// arms it only online), so nothing is drawn - the screen keeps "Search works once deadwax is back." - and once back
    /// the library is asked for them, with its late clock (`libraryUnplaced`), and the list drawn with it. The contrast:
    /// a clock left to run out while away drew the list without the library, its rows then behind "Show 3 …".
    @Test func wordsTypedWhileDeadwaxIsAwayDrawNothingAndTheLibraryOnceBack() throws {
        let found = LibraryResults(artists: [Self.portishead], albums: [Self.dummy], songs: [Self.roads])
        var state = SearchState()
        state.typed("portishead")
        let unasked = Self.draw(&state)
        #expect(unasked == nil && state.drawn == nil, "nothing drawn: the offline line stays")
        // deadwax back (SearchModel.resumed): nothing failed to ask again, but the words still want the library and
        // have no place for it - so it is asked, its late clock armed
        let again = state.resumed()
        #expect(!again && state.wantsLibrary && state.libraryUnplaced)
        let term = state.armingLibraryLate()
        let token = state.askingLibrary()
        #expect(state.libraryUnplaced, "asked, not yet settled, no place kept yet")
        state.libraryAnswered(token, state.query, found)
        #expect(!state.libraryUnplaced)
        let drawnMade = Self.draw(&state)
        let drawn = try #require(drawnMade)
        #expect(!drawn.drawn.libraryLate && state.libraryLateSlot == nil, "drawn with the library, no Show them")
        #expect(drawn.said.hasPrefix("In your library:"))
        let lateNow = state.libraryLatePassed(term)
        #expect(!lateNow, "settled: its clock running out is nothing")

        var late = SearchState()
        late.typed("portishead")
        let lateTerm = late.armingLibraryLate()
        let isLate = late.libraryLatePassed(lateTerm)
        #expect(isLate && !late.libraryUnplaced, "a place is kept: the clock is not armed again")
        let lateMade = Self.draw(&late)
        let lateDrawn = try #require(lateMade)
        #expect(lateDrawn.drawn.libraryLate)
        let lateToken = late.askingLibrary()
        late.libraryAnswered(lateToken, late.query, found)
        let stays = Self.draw(&late)
        #expect(stays == nil && late.libraryLateSlot == .show(3), "the rows behind Show them")
    }

    @Test func typingUnderThreeCharactersDropsTheAlbumsAndShortWordsAskNone() throws {
        var (state, _) = try Self.asked("portishead", LibraryResults())
        #expect(state.askedForQuery && state.albums != .idle)
        let typed = state.typed("po")
        #expect(typed == .drop)
        #expect(state.albums == .idle && state.asked == nil)
        let token = state.askingLibrary()
        state.libraryAnswered(token, "po", LibraryResults(artists: [Self.portishead]))
        let drawnMade = Self.draw(&state)
        let drawn = try #require(drawnMade)
        #expect(!drawn.drawn.musicBrainz && drawn.drawn.sections?.map(\.kind) == [.artists], "drawn at once, the library alone")
        #expect(!drawn.drawn.nothing, "the foot says to type more instead")
        // what each view asks: albums alone in slice 2
        let plan = try #require(SearchReading.read("portishead", names: SearchReading.artistNames(["Portishead"])))
        #expect(SearchState.wantedKinds(plan, view: .all) == [.albums] && SearchState.wantedKinds(plan, view: .songs).isEmpty)
        #expect(SearchState.keyFor(.albums, "portishead", plan, view: .albums) == "portishead\nalbums:\(plan.query)")
        #expect(SearchState.keyFor(.albums, "portishead", plan, view: .all)?.contains("primarytype") == true)
        #expect(SearchState.keyFor(.artists, "portishead", plan, view: .all) == nil)
    }

    @Test func aFieldedReadAsksThePlainWordsWhenItFindsNothing() throws {
        var state = SearchState()
        state.ownedArtists = ["Portishead"]
        state.typed("portishead  third")
        let askMade = state.askingMusicBrainz(state.query, view: .all)
        let ask = try #require(askMade)
        #expect(ask.plan.kind == .albumByArtist && ask.fallback == "portishead third" && !ask.studio)
        state.typed("dummy")
        let freeMade = state.askingMusicBrainz("dummy", view: .all)
        let free = try #require(freeMade)
        #expect(free.plan.kind == .free && free.fallback == nil)
        #expect(!state.isNewestAlbums(ask.token) && state.isNewestAlbums(free.token))
        let kept = state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: [Self.third]), query: ask.first, index: nil)
        #expect(!kept, "an older ask's answer counts for nothing")
        // the same words in the same view aren't asked twice
        let twice = state.askingMusicBrainz("dummy", view: .all)
        #expect(twice == nil)
    }

    @Test func theStudioClausesAnswerIsInStudioOrderAndItsFallbacksAsMusicBrainzGaveIt() throws {
        var state = SearchState()
        state.ownedArtists = ["Portishead"]
        state.typed("portishead")
        let askMade = state.askingMusicBrainz(state.query, view: .all)
        let ask = try #require(askMade)
        #expect(ask.studio && ask.fallback == "portishead")
        let ep = ReleaseGroup(id: "a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e04", title: "Glory Times", firstReleaseDate: "1995",
                              primaryType: "EP", secondaryTypes: [], artistCredit: Self.credit)
        let answer = FullySearchAnswer(releaseGroups: [ep, Self.third])
        // the studio clause's own answer: Album before EP
        state.albumsAnswered(ask, answer, query: ask.first, index: nil)
        guard case .done(let studio) = state.albums else { Issue.record("no albums"); return }
        #expect(studio.groups.map(\.id) == [Self.third.id, ep.id] && studio.studio)
        // the plain words' answer, asked when the studio clause found nothing: MusicBrainz's order, and no studio line
        let fallback = try #require(ask.fallback)
        state.albumsAnswered(ask, answer, query: fallback, index: nil)
        guard case .done(let plain) = state.albums else { Issue.record("no albums"); return }
        #expect(plain.groups.map(\.id) == [ep.id, Self.third.id] && !plain.studio)
    }

    // MARK: the Albums view

    @Test func theAlbumsViewsMusicBrainzPartIsBelowItsOwn() throws {
        var state = SearchState()
        state.typed("roseland")
        state.choose(.albums)
        let askedMade = state.askingKind()
        let asked = try #require(askedMade)
        #expect(asked.kind == .albums && asked.armLate, "a view that asks MusicBrainz arms its late clock")
        // before its library lands: one asking line, "Searching…" (MusicBrainz in it), and no foot yet
        let early = try #require(state.kindView(artistList: nil, marks: Self.marks))
        #expect(early.searching && early.searchingMusicBrainz && early.foot == nil)
        let askMade = state.askingMusicBrainz("roseland", view: .albums)
        let ask = try #require(askMade)
        #expect(ask.first == ask.plan.query && !ask.studio, "the Albums view asks the words as read, no studio clause")
        state.kindAnswered(asked.token, LibraryResults())
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: [Self.roseland]), query: ask.first, index: Self.marks.index)
        let view = try #require(state.kindView(artistList: nil, marks: Self.marks))
        #expect(view.foot == .rows([.group(Self.roseland)]) && !view.nothing)
        // the Artists view asks no MusicBrainz in slice 2: no foot, and nothing found is "No artists"
        state.choose(.artists)
        let artistsMade = state.askingKind()
        let artists = try #require(artistsMade)
        #expect(!artists.armLate)
        state.kindAnswered(artists.token, LibraryResults())
        let none = try #require(state.kindView(artistList: nil, marks: Self.marks))
        #expect(none.foot == nil && none.nothing)
        // a short word in the Albums view: Type a little more
        var short = SearchState()
        short.typed("ro")
        short.choose(.albums)
        let shortAskMade = short.askingKind()
        let shortAsk = try #require(shortAskMade)
        short.kindAnswered(shortAsk.token, LibraryResults())
        #expect(short.kindView(artistList: nil, marks: Self.marks)?.foot == .typeMore)
    }

    // MARK: the album you don't have

    static func release(_ id: String, _ tracks: [String], format: String = "CD", date: String = "1994-08-22") -> PageRelease {
        PageRelease(id: id, title: "Dummy", status: "Official", date: date, country: "GB",
                    media: [MBMedium(position: 1, format: format, tracks: tracks.enumerated().map { (pair: (offset: Int, element: String)) -> MBTrack in
                        MBTrack(number: String(pair.offset + 1), position: pair.offset + 1, title: pair.element, length: 240_000)
                    })])
    }

    @Test func theAlbumsPageIsDrawnFromWhatIsInHand() throws {
        let group = ReleaseGroup(id: "48140466-cff6-3222-bd55-63c27e43190d", title: "Dummy", firstReleaseDate: "1994-08-22",
                                 primaryType: "Album", secondaryTypes: [], artistCredit: Self.credit)
        let usual = ["Mysterons", "Sour Times", "Roads"]
        let answer = ReleaseGroupAnswer(id: group.id, releases: [
            Self.release("r-cd", usual), Self.release("r-lp", usual, format: "12\" Vinyl"),
            Self.release("r-bonus", usual + ["Airbus"], date: "2014-10-20"),
        ])
        // loading, from Search's album: its header, no pressings yet, nothing said of the library
        let loading = GroupPage(id: group.id, answer: nil, preview: group, index: nil, picked: nil, personal: false, editors: true)
        #expect(loading.title == "Dummy" && loading.artist == "Portishead" && loading.view == nil && loading.tracks.isEmpty)
        #expect(loading.meta == "1994 \u{00B7} Album", "the library hasn't said")
        // answered, nothing held: the usual pressing, its tracklist
        let page = GroupPage(id: group.id, answer: answer, preview: group, index: OwnedIndex([]), picked: nil,
                             personal: false, editors: true)
        #expect(page.meta == "1994 \u{00B7} Album \u{00B7} not in your library" && page.maybe.isEmpty)
        #expect(page.chosenId == "r-cd" && page.tracks.map(\.title) == usual)
        #expect(page.summary?.text == "The usual tracklist, shared by 2 of 3 pressings" && page.summary?.differs == false)
        // the bonus pressing picked: its bonus track marked
        let bonus = GroupPage(id: group.id, answer: answer, preview: group, index: OwnedIndex([]), picked: "r-bonus",
                              personal: false, editors: true)
        #expect(bonus.tracks.last?.mark?.chip == "Bonus" && bonus.summary?.text == "This pressing adds 1 track")
        // held by its group: in your library, the pressing held marked in the picker
        let held = OwnedIndex([OwnedAlbum(path: "P/Dummy", artist: "Portishead", album: "Dummy", releaseMbid: "r-lp",
                                          releaseGroupMbid: group.id)])
        let mine = GroupPage(id: group.id, answer: answer, preview: group, index: held, picked: nil, personal: false, editors: true)
        #expect(mine.meta.hasSuffix("in your library") && (mine.view?.shown ?? []).contains { $0.id == "r-lp" && $0.held })
        // an untagged folder by its name: maybe, dashed after the meta line, said under Get's place
        let maybe = GroupPage(id: group.id, answer: answer, preview: group,
                              index: OwnedIndex([OwnedAlbum(path: "U/Dummy", artist: "Portishead", album: "Dummy")]),
                              picked: nil, personal: false, editors: false)
        #expect(maybe.meta == "1994 \u{00B7} Album" && maybe.maybe == "maybe in your library")
        #expect(maybe.maybeNote == "You may already have this - an album with this name is in your library, but it isn't matched to a pressing.")
        // no pressings at all: nothing to pick
        let empty = GroupPage(id: group.id, answer: ReleaseGroupAnswer(id: group.id, releases: []), preview: nil, index: nil,
                              picked: nil, personal: false, editors: false, fallbackTitle: "Dummy")
        #expect(empty.view == nil && empty.title == "Dummy" && empty.tracks.isEmpty)
    }

    @Test func aHeldAlbumOpensYoursByItsReleasesInOrder() {
        let id = "48140466-cff6-3222-bd55-63c27e43190d"
        let index = OwnedIndex([
            OwnedAlbum(path: "P/Dummy (Deluxe)", artist: "Portishead", album: "Dummy", year: "2014", edition: "Deluxe",
                       releaseMbid: "f1f2f3f4-1111-4222-8333-944455550001", releaseGroupMbid: id),
            OwnedAlbum(path: "P/Dummy", artist: "Portishead", album: "Dummy", year: "1994",
                       releaseMbid: " F1F2F3F4-1111-4222-8333-944455550002 ", releaseGroupMbid: id),
        ])
        #expect(SearchAlbums.heldReleases(index, id) == ["f1f2f3f4-1111-4222-8333-944455550002", "f1f2f3f4-1111-4222-8333-944455550001"])
        #expect(SearchAlbums.heldReleases(index, nil).isEmpty && SearchAlbums.heldReleases(nil, id).isEmpty)
    }

    @Test func theSessionKeepsTwentyCompletePressingListsTheNewestLast() {
        var kept = KeptPressings()
        let broken = ReleaseGroupAnswer(id: "g-broken", releases: [PageRelease(id: "r1")], problem: "MusicBrainz went away")
        kept.keep("g-broken", broken)
        #expect(kept.kept("g-broken") == nil && kept.count == 0)
        // an empty problem is no problem (the web's `if (found.problem)`)
        kept.keep("g-0", ReleaseGroupAnswer(id: "g-0", releases: [], problem: ""))
        #expect(kept.kept("g-0") != nil)
        for n in 1...Pressings.kept {
            kept.keep("g-\(n)", ReleaseGroupAnswer(id: "g-\(n)", releases: []))
        }
        // the oldest let go past twenty
        #expect(kept.count == Pressings.kept && kept.kept("g-0") == nil && kept.kept("g-1") != nil)
        // kept again: the newest, so the next to go is g-2
        kept.keep("g-1", ReleaseGroupAnswer(id: "g-1", releases: []))
        kept.keep("g-new", ReleaseGroupAnswer(id: "g-new", releases: []))
        #expect(kept.kept("g-1") != nil && kept.kept("g-2") == nil && kept.count == Pressings.kept)
    }

    // MARK: the answers and the calls

    @Test func musicBrainzsAnswersAreReadLeniently() throws {
        let json = #"""
        {"release-groups":[
          {"id":"g1","title":"Dummy","first-release-date":1994,"primary-type":"Album","secondary-types":"Live",
           "artist-credit":[{"name":"Portishead","joinphrase":"","artist":{"id":"a1","name":"Portishead"}},"junk"]},
          {"title":"no id"},
          {"id":"g2"}
        ],"count":"many"}
        """#
        let read = try JSONDecoder().decode(FullySearchAnswer.self, from: Data(json.utf8))
        #expect(read.releaseGroups.map(\.id) == ["g1", "g2"])
        #expect(read.releaseGroups[0].firstReleaseDate == nil && read.releaseGroups[0].secondaryTypes == nil)
        #expect(Credits.name(read.releaseGroups[0].artistCredit) == "Portishead" && read.count == nil)
        #expect(try JSONDecoder().decode(FullySearchAnswer.self, from: Data("{}".utf8)) == FullySearchAnswer())
        let group = #"{"id":"g1","releases":[{"id":"r1","media":[{"position":1,"format":"CD","tracks":[{"title":"Roads","length":310000}]}]},{"title":"no id"}],"problem":null}"#
        let answer = try JSONDecoder().decode(ReleaseGroupAnswer.self, from: Data(group.utf8))
        #expect(answer.id == "g1" && answer.releases.map(\.id) == ["r1"] && answer.problem == nil)
        #expect(answer.releases[0].media.first?.tracks.first?.title == "Roads")
    }

    @Test func theAlbumsAreAskedQuicklyWithoutTheirPressings() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/search_musicbrainz/fully_search", 200, #"{"release-groups":[{"id":"g1"}],"count":1}"#)
        let found = try await deadwax.fullySearch("artist:\"Portishead\"")
        #expect(found.releaseGroups.map(\.id) == ["g1"] && found.count == 1)
        let items = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.map(\.name) == ["query", "limit", "releases", "quick"])
        #expect(items.map { (item: URLQueryItem) -> String in item.value ?? "-" } == ["artist:\"Portishead\"", "12", "false", "true"])
        #expect(transport.last?.timeout == 20)
        transport.answer("/deadwax/search_musicbrainz/release_group", 200, #"{"id":"g1","releases":[],"problem":"MusicBrainz is away"}"#)
        let group = try await deadwax.releaseGroup(mbid: "48140466-cff6-3222-bd55-63c27e43190d")
        #expect(group.problem == "MusicBrainz is away" && transport.last?.timeout == 60)
        #expect(transport.last?.url.query == "release_group_mbid=48140466-cff6-3222-bd55-63c27e43190d")
    }

    @Test func aCoverIsAskedThroughDeadwaxAndAnythingButAFrontIsTheEmptyCover() async throws {
        let (deadwax, transport) = client(session: "s.1")
        let id = "48140466-cff6-3222-bd55-63c27e43190d"
        transport.handle("/deadwax/coverart/release-group/\(id)") { request in
            if request.headers["If-None-Match"] == #""c1""# { return HTTPResponse(status: 304, headers: ["ETag": #""c1""#]) }
            return HTTPResponse(status: 200, headers: ["ETag": #""c1""#, "Content-Type": "image/jpeg"], body: Data([0xFF, 0xD8]))
        }
        let cover = ArchiveCoverID(.releaseGroup, id)
        let fresh = try await deadwax.archiveCover(cover, size: ArchiveCoverSize.row)
        #expect(fresh == .fresh(Data([0xFF, 0xD8]), etag: #""c1""#))
        #expect(transport.last?.url.query == "size=250" && transport.last?.headers["Accept"] == "image/*")
        #expect(try await deadwax.archiveCover(cover, size: ArchiveCoverSize.row, ifNoneMatch: #""c1""#) == .unchanged)
        // no front, the Archive away, a server before 2.1.24 (its own 404 for a route it hasn't): the empty cover
        for status in [404, 502, 504, 422] {
            transport.answer("/deadwax/coverart/release/r1", status, #"{"detail":"Not Found"}"#)
            #expect(try await deadwax.archiveCover(ArchiveCoverID(.release, "r1"), size: ArchiveCoverSize.hero) == nil, "\(status)")
        }
        #expect(transport.last?.url.query == "size=1200")
        #expect(ArchiveCoverID.addresses(release: "r1", group: id) == [ArchiveCoverID(.release, "r1"), cover])
        #expect(ArchiveCoverID.addresses(release: nil, group: id) == [cover])
    }

    @Test func theIdBridgeIsAskedReleaseByRelease() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.handle("/deadwax/store/album") { request in
            let release = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? ""
            let id = release == "r2" ? #""nd-2""# : "null"
            return HTTPResponse(status: 200, body: Data(#"{"release_mbid":"\#(release)","navidrome_id":\#(id),"present":[],"other_pressings":[]}"#.utf8))
        }
        #expect(try await deadwax.navidromeAlbum(releases: ["r1", "r2", "r3"]) == "nd-2")
        #expect(transport.sent.count == 2, "asked in turn, stopping at the first Navidrome has")
        #expect(try await deadwax.navidromeAlbum(releases: ["r1"]) == nil)
        #expect(try await deadwax.navidromeAlbum(releases: []) == nil)
    }
}
