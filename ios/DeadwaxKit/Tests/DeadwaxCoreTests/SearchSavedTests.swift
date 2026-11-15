import Foundation
import Testing
@testable import DeadwaxCore

/// What's saved, the kept answers and More from MusicBrainz (Phase 5, slice 4 - notes/ios-specs/phase5-search.md 5.1
/// and 6.4) as SearchState runs them: what's saved asked once per words and given up past its wait, drawn at the
/// library's moment with MusicBrainz's answer adding only what isn't there, a kind view's rows kept where they were
/// drawn, the kept answers taken with no request, More by offset with its late answers dropped, the answers read
/// leniently and the client's calls. The web's rules themselves are held by SearchSavedVectorTests; these are what the
/// exporter can't reach - Search.tsx's own state, which it can't compile without Preact.
@Suite struct SearchSavedTests {
    static let portisheadMB = "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"
    static let credit = [MBArtistCredit(name: "Portishead", artist: .init(id: portisheadMB, name: "Portishead"))]
    static let roseland = ReleaseGroup(id: "a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e03", title: "Roseland NYC Live",
                                       firstReleaseDate: "1998-11-02", primaryType: "Album", secondaryTypes: ["Live"],
                                       artistCredit: credit)
    static let third = ReleaseGroup(id: "a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e01", title: "Third",
                                    firstReleaseDate: "2008-04-28", primaryType: "Album", secondaryTypes: [],
                                    artistCredit: credit)
    static let marks = SearchMarks(personal: false, index: OwnedIndex([]))

    static func groups(_ count: Int, from: Int = 0) -> [ReleaseGroup] {
        (from..<(from + count)).map { (n: Int) -> ReleaseGroup in
            ReleaseGroup(id: "g-\(n)", title: "Roseland \(n)", primaryType: "Album", artistCredit: credit)
        }
    }

    static func savedAlbums(_ groups: [ReleaseGroup]) -> SavedSearchAnswer {
        SavedSearchAnswer(albums: FullySearchAnswer(releaseGroups: groups), available: true)
    }

    /// `text` typed, the library asked and answered with nothing, what's saved asked - its token - and MusicBrainz asked.
    static func asked(_ text: String) throws -> (SearchState, Int, SearchState.MusicBrainzAsks) {
        var state = SearchState()
        state.typed(text)
        let token = state.askingLibrary()
        let savedMade = state.askingSaved(state.query)
        let saved = try #require(savedMade)
        state.libraryAnswered(token, state.query, LibraryResults())
        let asks = state.askingMusicBrainz(state.query, view: .all)
        return (state, saved, asks)
    }

    static func draw(_ state: inout SearchState) -> SearchState.Drawing? {
        state.advance(artistList: nil, marks: marks)
    }

    // MARK: what's saved

    @Test func whatsSavedIsAskedOncePerWordsAndGivenUpPastItsWait() throws {
        #expect(SearchSaved.waitMs == 400)
        var state = SearchState()
        state.typed("portishead")
        let firstMade = state.askingSaved("portishead")
        let first = try #require(firstMade)
        let again = state.askingSaved("portishead")
        #expect(again == nil, "asked once for the words")
        let waiting = state.savedSettled("portishead")
        #expect(!waiting, "the library's moment waits for it")
        // its wait passed: given up for the words, its answer let go when it lands
        let gaveUp = state.savedGaveUp("portishead")
        let settled = state.savedSettled("portishead")
        #expect(gaveUp && settled)
        let late = state.savedAnswered(first, Self.savedAlbums([Self.third]))
        #expect(!late && state.saved == .none("portishead"))
        let afterGivingUp = state.askingSaved("portishead")
        #expect(afterGivingUp == nil, "given up, it stays so until the words change")
        let twice = state.savedGaveUp("portishead")
        #expect(!twice)
        // new words: asked again; nothing searchable is none, never an error
        let nextMade = state.askingSaved("portishead third")
        let next = try #require(nextMade)
        let unavailable = state.savedAnswered(next, SavedSearchAnswer(available: false))
        #expect(unavailable && state.saved == .none("portishead third"))
        // a failure is none too; an older ask's failure changes nothing
        let thirdMade = state.askingSaved("roseland")
        let third = try #require(thirdMade)
        let stale = state.savedFailed(next)
        #expect(!stale && state.saved == .asking("roseland"))
        let failed = state.savedFailed(third)
        #expect(failed && state.saved == .none("roseland"))
        let empty = state.askingSaved("")
        #expect(empty == nil)
    }

    @Test func whatsSavedIsDrawnOnlyOnceMusicBrainzIsForTheWords() throws {
        //? two letters don't ask MusicBrainz by themselves - the keyboard's Search does
        var state = SearchState()
        state.typed("ro")
        let token = state.askingLibrary()
        let savedMade = state.askingSaved(state.query)
        let saved = try #require(savedMade)
        state.libraryAnswered(token, state.query, LibraryResults())
        state.savedAnswered(saved, Self.savedAlbums([Self.roseland]))
        let plan = try #require(state.planFor("ro"))
        let before = state.savedOf("ro", plan, view: .all, index: Self.marks.index)
        #expect(before == nil, "MusicBrainz not drawn for the words yet")
        _ = state.askingMusicBrainz(state.query, view: .all)
        let after = state.savedOf("ro", plan, view: .all, index: Self.marks.index)
        let groups: [String] = (after?.groups ?? []).map(\.id)
        #expect(groups == [Self.roseland.id])
        // the Artists view draws the saved artists alone; another text's is none
        let artists = state.savedOf("ro", plan, view: .artists, index: Self.marks.index)
        let artistGroups: [ReleaseGroup] = artists?.groups ?? [Self.third]
        #expect(artistGroups.isEmpty)
        let other = state.savedOf("glory box", plan, view: .all, index: Self.marks.index)
        #expect(other == nil)
    }

    @Test func whatsSavedLeadsAtTheLibrarysMomentAndMusicBrainzAddsOnlyWhatIsntThere() throws {
        //? the album's whole title: as good a match as MusicBrainz's phantoms can be, and in hand before them
        var (state, saved, asks) = try Self.asked("roseland nyc live")
        let waiting = Self.draw(&state)
        #expect(waiting == nil, "the library has settled, what's saved hasn't")
        state.savedAnswered(saved, Self.savedAlbums([Self.roseland]))
        // moment 1: the saved album leads Top results (what's saved outranks MusicBrainz's phantoms), its credited
        // artist after it - both what's saved's - and a place kept for the rest
        let firstMade = Self.draw(&state)
        let first = try #require(firstMade)
        let topKeys: [String] = first.drawn.top.map(\.key)
        let artistKey = "mb-artist:\(Self.portisheadMB)"
        #expect(topKeys == ["group:\(Self.roseland.id)", artistKey])
        #expect(first.drawn.topSaved == Set(topKeys) && first.drawn.topPlace && first.drawn.sections == nil)
        // MusicBrainz answers the album again and one more: drawn once, as what's saved, the new one below it
        let albumsAsk = try #require(asks.albums)
        state.albumsAnswered(albumsAsk, FullySearchAnswer(releaseGroups: [Self.roseland, Self.third], count: 2),
                             query: albumsAsk.first, index: Self.marks.index)
        SearchTests.answerEmpty(&state, asks, albums: false)
        let secondMade = Self.draw(&state)
        let second = try #require(secondMade)
        let sections = try #require(second.drawn.sections)
        let albums = try #require(sections.first { $0.kind == .albums })
        let albumKeys: [String] = albums.rows.map(\.key)
        #expect(albumKeys == ["group:\(Self.roseland.id)", "group:\(Self.third.id)"])
        #expect(albums.saved == ["group:\(Self.roseland.id)"] && albums.holdsSaved && second.drawn.holdsSaved)
        let completed: [String] = second.drawn.top.map(\.key)
        #expect(completed == ["group:\(Self.roseland.id)", artistKey, "group:\(Self.third.id)"])
        #expect(second.drawn.topSaved == ["group:\(Self.roseland.id)", artistKey])
        #expect(second.said == "Found earlier: 1 album. More found: 1 album.")
    }

    @Test func everyKindFailingUnderWhatsSavedSaysTheseAreEarlierResults() throws {
        var (state, saved, asks) = try Self.asked("roseland")
        state.savedAnswered(saved, Self.savedAlbums([Self.roseland]))
        _ = Self.draw(&state)
        let away = MBFailure(message: "MusicBrainz couldn't be reached.", unavailable: true)
        if let ask = asks.albums { state.albumsFailed(ask, away) }
        if let ask = asks.artists { state.artistsFailed(ask, away) }
        if let ask = asks.songs { state.songsFailed(ask, away) }
        let drawnMade = Self.draw(&state)
        let drawn = try #require(drawnMade)
        #expect(drawn.drawn.allFailed == away && drawn.drawn.holdsSaved && !drawn.drawn.holdsLibrary)
        #expect(drawn.said == "Found earlier: 1 album. \(SearchWords.savedAwaySaid)")
        let foot = SearchWords.savedAway(away)
        #expect(foot == SearchWords.savedAwaySaid)
        let slot = SearchWords.savedAway(away, short: true)
        #expect(slot == "Showing earlier results.")
    }

    @Test func aLateAnswerUnderWhatsSavedBringingNothingNewSaysSo() throws {
        var (state, saved, asks) = try Self.asked("roseland")
        state.savedAnswered(saved, Self.savedAlbums([Self.roseland]))
        _ = Self.draw(&state)
        state.capPassed(run: state.run.id)
        let capMade = Self.draw(&state)
        let cap = try #require(capMade)
        let kinds: [SearchKind] = (cap.drawn.sections ?? []).map(\.kind)
        #expect(kinds == [.artists, .albums, .songs])
        let albums = try #require(cap.drawn.sections?[1])
        #expect(albums.rows.map(\.key) == ["group:\(Self.roseland.id)"] && albums.slot == .asking)
        // the albums answer only what's saved holds: under rows, the slot says no more - never "No albums"
        let ask = try #require(asks.albums)
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: [Self.roseland]), query: ask.first,
                             index: Self.marks.index)
        let landedMade = Self.draw(&state)
        let landed = try #require(landedMade)
        let slot = landed.drawn.sections?[1].slot
        let words = SearchWords.nothingMore(.albums, "roseland")
        #expect(slot == .said(words))
        #expect(words == "No more albums for \u{201C}roseland\u{201D}.")
    }

    @Test func savedAnswersAreReadLenientlyAndSongsGroupedAsTheyLand() throws {
        let json = #"""
        {"artists":{"matches":[{"mbid":"8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11","name":"Portishead"}],"count":1},
         "albums":{"release-groups":[{"id":"g1","title":"Dummy"}]},
         "songs":"junk", "credited":null, "available":true}
        """#
        let read = try JSONDecoder().decode(SavedSearchAnswer.self, from: Data(json.utf8))
        let groups: [String] = read.albums.releaseGroups.map(\.id)
        #expect(read.available && groups == ["g1"] && read.artists.matches.count == 1)
        #expect(read.songs == SongSearchAnswer() && read.credited == FullySearchAnswer())
        let bare = try JSONDecoder().decode(SavedSearchAnswer.self, from: Data("{}".utf8))
        #expect(!bare.available, "an answer that says nothing is nothing searched")
        let found = SavedFound(read)
        let credited: [ReleaseGroup] = found.credited ?? [Self.third]
        #expect(found.groups.map(\.id) == ["g1"] && credited.isEmpty && found.songs.isEmpty)
    }

    // MARK: a kind view

    /// The Albums view for `text`: its library answered with nothing, what's saved asked (its token).
    static func albumsView(_ text: String) throws -> (SearchState, Int?) {
        var state = SearchState()
        state.typed(text)
        state.choose(.albums)
        let savedToken = state.askingSaved(state.query)
        let askedMade = state.askingKind()
        let asked = try #require(askedMade)
        state.kindAnswered(asked.token, LibraryResults())
        return (state, savedToken)
    }

    @Test func aKindViewsSavedRowsLeadAndMusicBrainzsGoBelowThem() throws {
        var (state, savedMade) = try Self.albumsView("roseland")
        let saved = try #require(savedMade)
        state.savedAnswered(saved, Self.savedAlbums([Self.roseland]))
        let asks = state.askingMusicBrainz("roseland", view: .albums)
        let ask = try #require(asks.albums)
        let earlyMade = state.kindView(artistList: nil, marks: Self.marks)
        let early = try #require(earlyMade)
        #expect(early.savedRows.map(\.key) == ["group:\(Self.roseland.id)"] && early.foot == .searching)
        #expect(early.savedCount == 1 && early.said.musicBrainz == nil, "nothing said of MusicBrainz until it lands")
        // MusicBrainz answers the saved album again and one more: the saved one stays where it was, the new one below
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: [Self.third, Self.roseland], count: 2),
                             query: ask.first, index: Self.marks.index)
        let landedMade = state.kindView(artistList: nil, marks: Self.marks, before: early.area)
        let landed = try #require(landedMade)
        #expect(landed.savedRows.map(\.key) == ["group:\(Self.roseland.id)"] && landed.foot == .rows([.group(Self.third)]))
        #expect(landed.said.musicBrainz == "Found earlier: 1 album. More found: 1 album.")
        #expect(landed.more == nil, "every answer in")
    }

    @Test func whatsSavedLandingAfterMusicBrainzsRowsGoesBelowThem() throws {
        // what's saved not asked for these words yet: MusicBrainz's rows drawn first
        var state = SearchState()
        state.typed("roseland")
        state.choose(.albums)
        let askedMade = state.askingKind()
        let asked = try #require(askedMade)
        state.kindAnswered(asked.token, LibraryResults())
        let asks = state.askingMusicBrainz("roseland", view: .albums)
        let ask = try #require(asks.albums)
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: [Self.third], count: 1), query: ask.first,
                             index: Self.marks.index)
        let firstMade = state.kindView(artistList: nil, marks: Self.marks)
        let first = try #require(firstMade)
        #expect(first.foot == .rows([.group(Self.third)]) && first.savedRows.isEmpty)
        // asked now, and answered: below MusicBrainz's rows, never above them
        let savedMade = state.askingSaved("roseland")
        let saved = try #require(savedMade)
        let askingMade = state.kindView(artistList: nil, marks: Self.marks, before: first.area)
        let asking = try #require(askingMade)
        #expect(asking.foot == .rows([.group(Self.third)]), "rows drawn are never held back again")
        state.savedAnswered(saved, Self.savedAlbums([Self.roseland]))
        let laterMade = state.kindView(artistList: nil, marks: Self.marks, before: asking.area)
        let later = try #require(laterMade)
        #expect(later.savedRows.isEmpty && later.foot == .rows([.group(Self.third), .group(Self.roseland)]))
    }

    @Test func musicBrainzFailingUnderAKindViewsSavedRowsSaysTheyAreEarlierResults() throws {
        var (state, savedMade) = try Self.albumsView("roseland")
        let saved = try #require(savedMade)
        state.savedAnswered(saved, Self.savedAlbums([Self.roseland]))
        let asks = state.askingMusicBrainz("roseland", view: .albums)
        let ask = try #require(asks.albums)
        let busy = MBFailure(message: "MusicBrainz is busy.", busy: true)
        state.albumsFailed(ask, busy)
        let viewMade = state.kindView(artistList: nil, marks: Self.marks)
        let view = try #require(viewMade)
        #expect(view.savedRows.map(\.key) == ["group:\(Self.roseland.id)"] && view.foot == .failed(busy))
        #expect(view.said.musicBrainz == "Found earlier: 1 album. Showing earlier results.")
        #expect(view.area?.problem == true, "its failure drawn below the saved rows: a later answer goes below it")
    }

    // MARK: the kept answers

    @Test func theKeptAnswersAreTakenAtTheLibrarysMomentWithNoRequest() throws {
        // what one search of "roseland" asked, kept as the model keeps a success
        var first = SearchState()
        first.typed("roseland")
        let asks = first.askingMusicBrainz("roseland", view: .all)
        let albumsAsk = try #require(asks.albums)
        let artistsAsk = try #require(asks.artists)
        var kept = SearchAnswersKept()
        kept.keep(SearchAnswersKept.albumsKey(albumsAsk.first), .albums(FullySearchAnswer(releaseGroups: [Self.roseland], count: 1)),
                  at: 100)
        kept.keep(SearchAnswersKept.artistsKey(artistsAsk.name), .artists(ArtistSearchAnswer()), at: 100)

        // the words searched again: the albums and artists taken with no request, the songs still asked
        var state = SearchState()
        state.typed("roseland")
        let token = state.askingLibrary()
        state.libraryAnswered(token, state.query, LibraryResults())
        let took = state.takeKept(state.query, view: .all, kept: kept, now: 160, index: Self.marks.index)
        #expect(took.took && !took.songs)
        let again = state.askingMusicBrainz(state.query, view: .all)
        #expect(again.albums == nil && again.artists == nil && again.songs != nil)
        // and taken twice, nothing: they are in hand
        let twice = state.takeKept(state.query, view: .all, kept: kept, now: 160, index: Self.marks.index)
        #expect(!twice.took)
        // nothing is taken for words MusicBrainz isn't asked for: two letters, kept from the keyboard's Search before,
        // aren't taken as they're typed again (Search asks for them, and the ask answers from what's kept)
        var probe = SearchState()
        probe.typed("ro")
        let shortAsks = probe.askingMusicBrainz("ro", view: .all)
        let shortAlbums = try #require(shortAsks.albums)
        kept.keep(SearchAnswersKept.albumsKey(shortAlbums.first), .albums(FullySearchAnswer(releaseGroups: [Self.roseland], count: 1)),
                  at: 100)
        var short = SearchState()
        short.typed("ro")
        let none = short.takeKept("ro", view: .all, kept: kept, now: 160, index: nil)
        #expect(!none.took)
    }

    @Test func aKeptAnswerIsAnsweredFromForAnHourThenAskedAgain() throws {
        // (slice 4's review) deadwax's own in-memory hour - the web's page has no end, an iPhone app's runs to days
        #expect(SearchAnswersKept.lifetime == 3600)
        var first = SearchState()
        first.typed("roseland")
        let asks = first.askingMusicBrainz("roseland", view: .all)
        let albumsAsk = try #require(asks.albums)
        var kept = SearchAnswersKept()
        let landed: Double = 5_000
        kept.keep(SearchAnswersKept.albumsKey(albumsAsk.first), .albums(FullySearchAnswer(releaseGroups: [Self.roseland], count: 1)),
                  at: landed)
        let key = SearchAnswersKept.albumsKey(albumsAsk.first)
        let atOnce = kept.kept(key, at: landed)
        let lastSecond = kept.kept(key, at: landed + SearchAnswersKept.lifetime)
        let after = kept.kept(key, at: landed + SearchAnswersKept.lifetime + 1)
        let daysOn = kept.albums(albumsAsk, at: landed + 3 * 86_400)
        #expect(atOnce != nil && lastSecond != nil, "inside the hour")
        #expect(after == nil, "past the hour: missing")
        #expect(daysOn == nil, "days on: asked again")
        // the library's moment takes it inside the hour, and not past it
        func search(at now: Double) -> Bool {
            var state = SearchState()
            state.typed("roseland")
            let token = state.askingLibrary()
            state.libraryAnswered(token, state.query, LibraryResults())
            return state.takeKept(state.query, view: .all, kept: kept, now: now, index: Self.marks.index).took
        }
        let inside = search(at: landed + 600)
        let outside = search(at: landed + 7_200)
        #expect(inside)
        #expect(!outside)
        // kept again as it answers afresh: the hour runs from then
        kept.keep(key, .albums(FullySearchAnswer(count: 2)), at: landed + 7_200)
        let renewed = kept.kept(key, at: landed + 7_300)
        #expect(renewed == .albums(FullySearchAnswer(count: 2)))
    }

    @Test func aFieldedReadsKeptAnswerNeedsItsFallbackKeptToo() throws {
        var state = SearchState()
        state.ownedArtists = ["Portishead"]
        state.typed("third portishead")
        var probe = state
        let asks = probe.askingMusicBrainz("third portishead", view: .all)
        let ask = try #require(asks.albums)
        let fallback = try #require(ask.fallback)
        var kept = SearchAnswersKept()
        kept.keep(SearchAnswersKept.albumsKey(ask.first), .albums(FullySearchAnswer()), at: 0)
        let missing = kept.albums(ask, at: 1)
        #expect(missing == nil, "the fielded read found nothing; the words typed weren't kept")
        kept.keep(SearchAnswersKept.albumsKey(fallback), .albums(FullySearchAnswer(releaseGroups: [Self.third])), at: 0)
        let hit = try #require(kept.albums(ask, at: 1))
        #expect(hit.query == fallback && hit.found.releaseGroups.map(\.id) == [Self.third.id])
    }

    @Test func twentyFourAnswersAreKeptTheOldestGoingFirst() {
        var kept = SearchAnswersKept()
        for n in 0..<30 { kept.keep("ask-\(n)", .albums(FullySearchAnswer(count: n)), at: Double(n)) }
        let keys = kept.keys
        let wanted: [String] = (6..<30).map { (n: Int) -> String in "ask-\(n)" }
        #expect(keys == wanted && keys.count == SearchAnswersKept.count)
        // kept again: the newest, so another goes first
        kept.keep("ask-6", .albums(FullySearchAnswer(count: 99)), at: 30)
        kept.keep("ask-30", .albums(FullySearchAnswer(count: 30)), at: 31)
        let gone = kept.kept("ask-7", at: 32)
        let renewed = kept.kept("ask-6", at: 32)
        #expect(gone == nil && renewed == .albums(FullySearchAnswer(count: 99)))
    }

    // MARK: More from MusicBrainz

    @Test func moreFromMusicBrainzAsksTheNextPageAndAppendsIt() throws {
        var (state, _) = try Self.albumsView("roseland")
        let none = state.askingMoreMusicBrainz()
        #expect(none == nil, "nothing in hand to add to")
        let asks = state.askingMusicBrainz("roseland", view: .albums)
        let ask = try #require(asks.albums)
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: Self.groups(12), count: 30), query: ask.first,
                             index: Self.marks.index)
        //? MusicBrainz's rows held while what's saved is still asked for - then given up past its wait
        let heldMade = state.kindView(artistList: nil, marks: Self.marks)
        let held = try #require(heldMade)
        #expect(held.foot == .searching && held.more == nil)
        state.savedGaveUp("roseland")
        let viewMade = state.kindView(artistList: nil, marks: Self.marks, before: held.area)
        let view = try #require(viewMade)
        let more = try #require(view.more)
        #expect(more.pages == .more && more.label == "More albums" && !more.asking && more.note == nil)
        // asked: the same search from where the first page ended, through the albums' own token
        let pageMade = state.askingMoreMusicBrainz()
        let page = try #require(pageMade)
        #expect(page.kind == .albums && page.offset == 12 && page.words == ask.first)
        let twice = state.askingMoreMusicBrainz()
        #expect(twice == nil, "asking already")
        let askingMade = state.kindView(artistList: nil, marks: Self.marks, before: view.area)
        let asking = try #require(askingMade)
        #expect(asking.more?.asking == true && asking.more?.label == SearchWords.loading)
        // it lands: a repeat dropped, eleven new below the rows drawn - said, not noted
        let next = [Self.groups(1, from: 11)[0]] + Self.groups(11, from: 12)
        let said = state.moreAnswered(page, albums: FullySearchAnswer(releaseGroups: next, count: 30),
                                      index: Self.marks.index, personal: false)
        #expect(said == "11 more albums found")
        let landedMade = state.kindView(artistList: nil, marks: Self.marks, before: asking.area)
        let landed = try #require(landedMade)
        guard case .rows(let rows)? = landed.foot else {
            Issue.record("the rows drawn")
            return
        }
        let keys: [String] = rows.map(\.key)
        let wanted: [String] = (0..<23).map { (n: Int) -> String in "group:g-\(n)" }
        #expect(keys == wanted, "nothing drawn moves")
        #expect(landed.more?.pages == .more && landed.more?.note == nil)
        // the next page fails: its words under the rows, Try again in the button
        let thirdMade = state.askingMoreMusicBrainz()
        let third = try #require(thirdMade)
        #expect(third.offset == 24)
        let away = MBFailure(message: "MusicBrainz couldn't be reached.", unavailable: true)
        state.moreFailed(third, away)
        let failedMade = state.kindView(artistList: nil, marks: Self.marks)
        let failed = try #require(failedMade)
        #expect(failed.more?.failure == away && failed.more?.label == SearchWords.tryAgain)
        // tried again, it brings only what is drawn: no more results - the button kept, the count saying more match
        let fourthMade = state.askingMoreMusicBrainz()
        let fourth = try #require(fourthMade)
        let nothing = state.moreAnswered(fourth, albums: FullySearchAnswer(releaseGroups: Self.groups(2)),
                                         index: Self.marks.index, personal: false)
        #expect(nothing == "No more results")
        let repeatsMade = state.kindView(artistList: nil, marks: Self.marks)
        let repeats = try #require(repeatsMade)
        #expect(repeats.more?.note == "No more results." && repeats.more?.pages == .more)
        // a page of nothing ends it, whatever the count says: the button gone, the note kept
        let fifthMade = state.askingMoreMusicBrainz()
        let fifth = try #require(fifthMade)
        #expect(fifth.offset == 26)
        _ = state.moreAnswered(fifth, albums: FullySearchAnswer(), index: Self.marks.index, personal: false)
        let endMade = state.kindView(artistList: nil, marks: Self.marks)
        let end = try #require(endMade)
        #expect(end.more?.note == "No more results." && end.more?.pages == .end)
        let after = state.askingMoreMusicBrainz()
        #expect(after == nil)
    }

    @Test func moreFromMusicBrainzIsDroppedByNewWordsAndNeverAskedInAll() throws {
        var (state, _) = try Self.albumsView("roseland")
        let asks = state.askingMusicBrainz("roseland", view: .albums)
        let ask = try #require(asks.albums)
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: Self.groups(12)), query: ask.first,
                             index: Self.marks.index)
        let pageMade = state.askingMoreMusicBrainz()
        let page = try #require(pageMade, "a full page with no count: there may be more")
        //? new words asked: the albums' token moves on, as the web's latestOnly supersedes the page
        state.typed("roseland nyc")
        _ = state.askingMusicBrainz("roseland nyc", view: .albums)
        let late = state.moreAnswered(page, albums: FullySearchAnswer(releaseGroups: Self.groups(3, from: 12)),
                                      index: Self.marks.index, personal: false)
        #expect(late == nil, "its words have gone")
        state.moreFailed(page, MBFailure(message: "x"))
        let more = state.albums.found?.more
        #expect(more == nil || more == .idle, "nor its failure")
        // back to the words, their first page answered again (a kept answer, at once) before the page lands: it is
        // the old ask's, so it lands on nothing
        state.typed("roseland")
        let againAsks = state.askingMusicBrainz("roseland", view: .albums)
        let againAsk = try #require(againAsks.albums)
        state.albumsAnswered(againAsk, FullySearchAnswer(releaseGroups: Self.groups(12)), query: againAsk.first,
                             index: Self.marks.index)
        let stale = state.moreAnswered(page, albums: FullySearchAnswer(releaseGroups: Self.groups(3, from: 12)),
                                       index: Self.marks.index, personal: false)
        let afterStale = state.albums.found?.groups.count
        #expect(stale == nil, "the page asked before the words came back")
        #expect(afterStale == 12)
        // All has no More
        var all = SearchState()
        all.typed("roseland")
        let allAsks = all.askingMusicBrainz("roseland", view: .all)
        let allAsk = try #require(allAsks.albums)
        all.albumsAnswered(allAsk, FullySearchAnswer(releaseGroups: Self.groups(12)), query: allAsk.first,
                           index: Self.marks.index)
        let inAll = all.askingMoreMusicBrainz()
        #expect(inAll == nil)
    }

    @Test func aMoreLetGoCanBeAskedAgainAndItsPageLandsOnNothing() throws {
        // (slice 4's review) a kind's More cancelled is idle again - never "Loading…" until the words change
        var (state, _) = try Self.albumsView("roseland")
        let asks = state.askingMusicBrainz("roseland", view: .albums)
        let ask = try #require(asks.albums)
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: Self.groups(12), count: 40), query: ask.first,
                             index: Self.marks.index)
        let firstMade = state.askingMoreMusicBrainz()
        let first = try #require(firstMade)
        let asking = state.albums.found?.more
        #expect(asking == .asking)
        let refused = state.askingMoreMusicBrainz()
        #expect(refused == nil, "asking already")
        state.moreLetGo(.albums)
        let idle = state.albums.found?.more
        #expect(idle == .idle)
        // the let-go ask's page and failure land on nothing
        let late = state.moreAnswered(first, albums: FullySearchAnswer(releaseGroups: Self.groups(12, from: 12)),
                                      index: Self.marks.index, personal: false)
        state.moreFailed(first, MBFailure(message: "x"))
        let afterLate = state.albums.found?.groups.count
        let stillIdle = state.albums.found?.more
        #expect(late == nil && afterLate == 12)
        #expect(stillIdle == .idle)
        // asked again: the same offset, and its page lands
        let againMade = state.askingMoreMusicBrainz()
        let again = try #require(againMade)
        #expect(again.offset == first.offset && again.token != first.token)
        let said = state.moreAnswered(again, albums: FullySearchAnswer(releaseGroups: Self.groups(12, from: 12)),
                                      index: Self.marks.index, personal: false)
        let grown = state.albums.found?.groups.count
        #expect(said == "12 more albums found" && grown == 24)
        // a let-go with nothing asking leaves the page's words as they are
        state.moreLetGo(.albums)
        let added = state.albums.found?.more
        #expect(added == .added(12, other: 0))
    }

    @Test func oneKindsMoreLeavesAnothersAsking() throws {
        // (slice 4's review) Albums' More asking, then Songs' asked: Albums' still asking, and its page still lands
        var (state, _) = try Self.albumsView("roseland nyc live")
        let asks = state.askingMusicBrainz("roseland nyc live", view: .albums)
        let ask = try #require(asks.albums)
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: Self.groups(12), count: 40), query: ask.first,
                             index: Self.marks.index)
        let albumsMade = state.askingMoreMusicBrainz()
        let albumsMore = try #require(albumsMade)
        state.choose(.songs)
        let songAsks = state.askingMusicBrainz("roseland nyc live", view: .songs)
        let songAsk = try #require(songAsks.songs)
        let live = ReleaseGroup(id: "a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e03", title: "Roseland NYC Live",
                                firstReleaseDate: "1998-11-02", primaryType: "Album", secondaryTypes: ["Live"],
                                artistCredit: Self.credit)
        let takes: [MBRecording] = (0..<25).map { (n: Int) -> MBRecording in
            SearchSongsTests.recording("rec-\(n)", "Roseland \(n)", group: live, release: "r-\(n)")
        }
        state.songsAnswered(songAsk, SongSearchAnswer(recordings: takes, count: 60), query: songAsk.first)
        let songsMade = state.askingMoreMusicBrainz()
        let songsMore = try #require(songsMade)
        #expect(songsMore.kind == .songs && albumsMore.kind == .albums)
        let albumsStill = state.albums.found?.more
        #expect(albumsStill == .asking)
        state.choose(.albums)
        let said = state.moreAnswered(albumsMore, albums: FullySearchAnswer(releaseGroups: Self.groups(3, from: 12)),
                                      index: Self.marks.index, personal: false)
        #expect(said == "3 more albums found")
    }

    @Test func newWordsLetAMoreGoBeforeMusicBrainzIsAskedForThem() throws {
        // (slice 4's review) typing on - MusicBrainz not yet asked for the new words (its pause): the old page lands on
        // nothing, said or drawn, and More can be asked again back on the words
        var (state, _) = try Self.albumsView("roseland")
        let asks = state.askingMusicBrainz("roseland", view: .albums)
        let ask = try #require(asks.albums)
        state.albumsAnswered(ask, FullySearchAnswer(releaseGroups: Self.groups(12), count: 40), query: ask.first,
                             index: Self.marks.index)
        let pageMade = state.askingMoreMusicBrainz()
        let page = try #require(pageMade)
        let effect = state.typed("roseland n")
        #expect(effect == .settle, "MusicBrainz asked only once typing pauses")
        let late = state.moreAnswered(page, albums: FullySearchAnswer(releaseGroups: Self.groups(3, from: 12)),
                                      index: Self.marks.index, personal: false)
        let groups = state.albums.found?.groups.count
        let more = state.albums.found?.more
        #expect(late == nil, "nothing said")
        #expect(groups == 12, "nothing appended")
        #expect(more == .idle)
        state.typed("roseland")
        let againMade = state.askingMoreMusicBrainz()
        let again = try #require(againMade, "back on the words: More asks again")
        #expect(again.offset == page.offset)
    }

    @Test func moreArtistsAndMoreSongsAddOnlyWhatIsNew() throws {
        var state = SearchState()
        state.typed("roseland")
        state.choose(.artists)
        let kindMade = state.askingKind()
        let kind = try #require(kindMade)
        state.kindAnswered(kind.token, LibraryResults())
        let asks = state.askingMusicBrainz("roseland", view: .artists)
        let ask = try #require(asks.artists)
        let ten: [MBArtistMatch] = (0..<10).map { (n: Int) -> MBArtistMatch in
            MBArtistMatch(mbid: "1d2c3b4a-0000-4000-8000-0000000000\(10 + n)", name: "Roseland \(n)")
        }
        state.artistsAnswered(ask, ArtistSearchAnswer(matches: ten))
        let pageMade = state.askingMoreMusicBrainz()
        let page = try #require(pageMade)
        #expect(page.kind == .artists && page.offset == 10 && page.words == "roseland")
        let next = [ten[9], MBArtistMatch(mbid: "1d2c3b4a-0000-4000-8000-000000000099", name: "Roseland 99")]
        let said = state.moreAnswered(page, artists: ArtistSearchAnswer(matches: next))
        #expect(said == "2 more artists found", "the page's own count, as the web says it")
        let matches = state.artists.found?.matches.count
        #expect(matches == 11)
        let after = state.askingMoreMusicBrainz()
        #expect(after == nil, "a short page: every answer in")

        // songs: a later take of a song drawn adds its albums in place
        var songs = SearchState()
        songs.typed("roads")
        songs.choose(.songs)
        let songsKindMade = songs.askingKind()
        let songsKind = try #require(songsKindMade)
        songs.kindAnswered(songsKind.token, LibraryResults())
        let songAsks = songs.askingMusicBrainz("roads", view: .songs)
        let songAsk = try #require(songAsks.songs)
        let dummy = ReleaseGroup(id: "48140466-cff6-3222-bd55-63c27e43190d", title: "Dummy", firstReleaseDate: "1994-08-22",
                                 primaryType: "Album", secondaryTypes: [], artistCredit: Self.credit)
        let takes: [MBRecording] = (0..<25).map { (n: Int) -> MBRecording in
            SearchSongsTests.recording("rec-\(n)", "Roads \(n)", group: dummy, release: "r-\(n)")
        }
        songs.songsAnswered(songAsk, SongSearchAnswer(recordings: takes, count: 26), query: songAsk.first)
        let songPageMade = songs.askingMoreMusicBrainz()
        let songPage = try #require(songPageMade)
        #expect(songPage.offset == 25 && songPage.words == songAsk.first)
        let live = ReleaseGroup(id: "a4a5b1c6-0b43-3d1a-8e0b-3b0f9a1d0e03", title: "Roseland NYC Live",
                                firstReleaseDate: "1998-11-02", primaryType: "Album", secondaryTypes: ["Live"],
                                artistCredit: Self.credit)
        let songSaid = songs.moreAnswered(songPage, songs: SongSearchAnswer(recordings: [
            SearchSongsTests.recording("rec-live", "Roads 0", group: live, release: "r-live"),
        ]))
        #expect(songSaid == "No new songs - 1 more album for the songs above")
        let first = songs.songs.found?.songs.first
        let albumIds: [String] = (first?.albums ?? []).map(\.id)
        #expect(albumIds.contains(live.id) && songs.songs.found?.songs.count == 25)
    }

    @Test func theFurthestPageIsNarrowedNotAsked() {
        let far = SearchMore.pages(next: 1012, count: 5000, last: 12, limit: 12)
        let last = SearchMore.pages(next: 1000, count: 5000, last: 12, limit: 12)
        let empty = SearchMore.pages(next: 12, count: 5000, last: 0, limit: 12)
        let unknown = SearchMore.pages(next: 12, count: nil, last: 11, limit: 12)
        #expect(far == .far && last == .more && empty == .end && unknown == .end)
        #expect(SearchMore.far == "That's all for this search - add a word to narrow it.")
    }

    // MARK: the calls

    @Test func whatsSavedIsAskedByTheWordsAndPagesByOffset() async throws {
        let (deadwax, transport) = client(session: "s.1")
        transport.answer("/deadwax/search_musicbrainz/saved", 200,
                         #"{"artists":{"matches":[]},"albums":{"release-groups":[{"id":"g1"}]},"songs":{"recordings":[]},"credited":{"release-groups":[]},"available":true}"#)
        let saved = try await deadwax.savedSearch("roads portishead")
        #expect(saved.available && saved.albums.releaseGroups.map(\.id) == ["g1"])
        let url = try #require(transport.last?.url)
        #expect(url.path == "/deadwax/search_musicbrainz/saved" && url.query == "words=roads%20portishead")

        transport.answer("/deadwax/search_musicbrainz/fully_search", 200, #"{"release-groups":[],"count":30}"#)
        _ = try await deadwax.fullySearch("roseland", offset: 12)
        let albumItems = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        let albumNames: [String] = albumItems.map(\.name)
        let albumOffset: String? = albumItems.first { $0.name == "offset" }?.value
        #expect(albumNames == ["query", "limit", "releases", "quick", "offset"] && albumOffset == "12")

        transport.answer("/deadwax/search_musicbrainz/artists", 200, #"{"matches":[]}"#)
        _ = try await deadwax.searchArtists("roseland", offset: 10)
        let artistItems = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        let artistNames: [String] = artistItems.map(\.name)
        #expect(artistNames == ["name", "limit", "offset"])
        _ = try await deadwax.searchArtists("roseland")
        let firstItems = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        let firstNames: [String] = firstItems.map(\.name)
        #expect(firstNames == ["name", "limit"], "the first page sends no offset")

        transport.answer("/deadwax/search_musicbrainz/songs", 200, #"{"recordings":[]}"#)
        _ = try await deadwax.searchSongs("recording:roads", offset: 25)
        let songItems = URLComponents(url: try #require(transport.last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        let songNames: [String] = songItems.map(\.name)
        let songOffset: String? = songItems.first { $0.name == "offset" }?.value
        #expect(songNames == ["query", "limit", "offset"] && songOffset == "25")
    }
}
