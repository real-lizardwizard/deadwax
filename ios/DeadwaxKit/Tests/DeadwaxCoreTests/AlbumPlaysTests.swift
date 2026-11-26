import Foundation
import Testing
@testable import DeadwaxCore

/// The albums' Most played order (AlbumPlays, Last.fm slice A2 - lastfm.md 3.3): each row's plays by release id or
/// folded title, the largest of several never a sum, the rows with plays first with ties and the rest newest first,
/// over the rows Studio only leaves (none added), the order chosen kept with care, and the visit judged once.
@Suite struct AlbumPlaysTests {
    static func mine(_ id: String, _ title: String, year: String? = "2015") -> ArtistJoin.Row {
        .yours(ArtistPage.Row(key: "album:\(id)", title: title, year: year, albumId: id, coverArt: nil, yours: true))
    }

    static func theirs(_ id: String, _ title: String, year: String? = "2012") -> ArtistJoin.Row {
        .theirs(MBArtistPage.Row(key: "group:\(id)", title: title, year: year, group: ReleaseGroup(id: id, title: title),
                                 held: false, yours: nil, editions: 0, releases: [], kind: nil))
    }

    static let currentsId = "031ecbde-35e1-4d3a-917f-f89f31aca1c9"
    /// Tame Impala's page, newest first: Deadbeat (2025), The Slow Rush (2020), Currents (2015, its release's id - a
    /// title Navidrome tags otherwise), Lonerism (theirs, 2012), Innerspeaker (2010) and a live album Last.fm doesn't
    /// list.
    static let rows: [ArtistJoin.Row] = [
        mine("dbt", "Deadbeat", year: "2025"), mine("slw", "The Slow Rush", year: "2020"),
        mine("cur", "Currents (Deluxe Edition)"), theirs("lon", "Lonerism"), mine("inn", "Innerspeaker", year: "2010"),
        mine("liv", "Live Versions", year: "2014"),
    ]
    static let albums = [Album(id: "cur", name: "Currents (Deluxe Edition)", musicBrainzId: currentsId.uppercased()),
                         Album(id: "dbt", name: "Deadbeat"), Album(id: "slw", name: "The Slow Rush"),
                         Album(id: "inn", name: "Innerspeaker"), Album(id: "liv", name: "Live Versions")]

    static func album(_ title: String, _ plays: Int, mbid: String? = nil,
                      counted: LastfmAlbum.Counted = .plays) -> LastfmAlbum {
        LastfmAlbum(title: title, mbid: mbid, plays: plays, counted: counted)
    }

    static func keys(_ rows: [ArtistJoin.Row]) -> [String] { rows.map(\.key) }

    @Test func eachRowsPlaysByItsReleaseElseItsTitle() {
        let lastfm = [Self.album("Currents", 197_990_342, mbid: Self.currentsId), Self.album("The Slow Rush", 75_865_879),
                      Self.album("Lonerism", 65_345_426), Self.album("Deadbeat", 23_596_438),
                      Self.album("Innerspeaker", 29_854_021)]
        let plays = AlbumPlays.of(Self.rows, lastfm: lastfm, albums: Self.albums)
        // Currents by its release's id (its title is the deluxe's), theirs by the group's title, the live album none
        #expect(plays == ["album:cur": 197_990_342, "album:slw": 75_865_879, "group:lon": 65_345_426,
                          "album:dbt": 23_596_438, "album:inn": 29_854_021])
        // an album of yours whose release Last.fm doesn't list is met by its folded title
        let byTitle = AlbumPlays.of([Self.mine("x", "the slow rush")], lastfm: lastfm,
                                    albums: [Album(id: "x", musicBrainzId: "3a12923d-97cd-4e87-8cfd-fb67be970974")])
        #expect(byTitle == ["album:x": 75_865_879])
        // a title that folds to nothing meets nothing
        #expect(AlbumPlays.of([Self.mine("q", "!!!")], lastfm: [Self.album("???", 5)], albums: []).isEmpty)
    }

    @Test func severalOnOneRowGiveTheLargestNeverASum() {
        // "Dracula" and "Dracula (Remix)" fold together - the recorded answer's own pair
        let lastfm = [Self.album("Dracula (Remix)", 7_905_191), Self.album("Dracula", 6_876_079),
                      Self.album("Currents", 3_000, mbid: Self.currentsId), Self.album("Currents B-Sides", 9_000,
                                                                                       mbid: Self.currentsId)]
        let plays = AlbumPlays.of([Self.mine("dra", "Dracula"), Self.mine("cur", "Currents")], lastfm: lastfm,
                                  albums: Self.albums)
        #expect(plays["album:dra"] == 7_905_191)
        #expect(plays["album:cur"] == 9_000)
    }

    @Test func theListsOneKindOfCountAndNoneForNothing() {
        // the first album's kind is the list's: one of another kind left out, never set beside it
        let mixed = [Self.album("Lonerism", 10, counted: .listeners), Self.album("Currents", 99, counted: .plays)]
        let plays = AlbumPlays.of(Self.rows, lastfm: mixed, albums: [])
        #expect(plays == ["group:lon": 10])
        // a count of 0 is no plays
        #expect(AlbumPlays.of(Self.rows, lastfm: [Self.album("Lonerism", 0)], albums: []).isEmpty)
        #expect(AlbumPlays.counted(LastfmArtist(topAlbums: mixed)) == [mixed[0]])
        #expect(AlbumPlays.counted(LastfmArtist(topAlbums: [])) == nil)
        #expect(AlbumPlays.counted(LastfmArtist(enabled: false, topAlbums: mixed)) == nil)
        #expect(AlbumPlays.counted(nil) == nil)
        #expect(AlbumPlays.offered(LastfmArtist(topAlbums: mixed)) && !AlbumPlays.offered(LastfmArtist()))
    }

    @Test func mostPlayedFirstTiesAndTheRestNewestFirst() {
        let plays = ["album:inn": 50, "group:lon": 90, "album:cur": 50, "album:dbt": 50]
        let ordered = AlbumPlays.ordered(Self.rows, plays: plays)
        // Lonerism; then the three of 50 as the page had them (Deadbeat, Currents, Innerspeaker); then the rest, newest
        // first (The Slow Rush, Live Versions)
        #expect(Self.keys(ordered) == ["group:lon", "album:dbt", "album:cur", "album:inn", "album:slw", "album:liv"])
        // nothing counted: the page's own order
        #expect(Self.keys(AlbumPlays.ordered(Self.rows, plays: [:])) == Self.keys(Self.rows))
    }

    @Test func studioOnlyStillApplies() {
        // Studio only's rows: no live album among them. Last.fm's most played is a live album - counted against no row,
        // so no row comes of it; the order is the same rows, none added, none dropped
        let studio = Self.rows.filter { (row: ArtistJoin.Row) -> Bool in row.key != "album:liv" && row.key != "group:lon" }
        let lastfm = [Self.album("Live Versions", 900), Self.album("Lonerism", 800), Self.album("Innerspeaker", 10)]
        let shown = AlbumPlays.shown(studio, chosen: .played, visit: lastfm, albums: Self.albums)
        #expect(Set(Self.keys(shown.rows)) == Set(Self.keys(studio)) && shown.rows.count == studio.count)
        #expect(Self.keys(shown.rows) == ["album:inn", "album:dbt", "album:slw", "album:cur"])
        #expect(shown.plays == ["album:inn": "10 plays"])
        // Everything's rows: the same answer orders the live album and Lonerism first
        let every = AlbumPlays.shown(Self.rows, chosen: .played, visit: lastfm, albums: Self.albums)
        #expect(Array(Self.keys(every.rows).prefix(3)) == ["album:liv", "group:lon", "album:inn"])
        // and made once for what it is made from - a switch of Studio only is other rows, made again
        var made = AlbumPlays.Made()
        #expect(made.shown(studio, chosen: .played, visit: lastfm, albums: Self.albums) == shown)
        #expect(made.shown(Self.rows, chosen: .played, visit: lastfm, albums: Self.albums) == every)
        #expect(made.shown(Self.rows, chosen: .newest, visit: lastfm, albums: Self.albums).rows == Self.rows)
    }

    @Test func newestFirstIsThePagesOwnWithNothingAtTheEnds() {
        let lastfm = [Self.album("Lonerism", 800)]
        let newest = AlbumPlays.shown(Self.rows, chosen: .newest, visit: lastfm, albums: Self.albums)
        #expect(newest == AlbumPlays.Shown(rows: Self.rows, order: .newest, plays: [:]))
        // Most played chosen with no albums for the visit: newest first, and the menu's tick says so
        let none = AlbumPlays.shown(Self.rows, chosen: .played, visit: nil, albums: Self.albums)
        #expect(none.order == .newest && none.rows == Self.rows && none.plays.isEmpty)
        let played = AlbumPlays.shown(Self.rows, chosen: .played, visit: lastfm, albums: Self.albums)
        #expect(played.order == .played)
        // (A2's review) the plays lead the line: never the part a one-line row cuts
        #expect(played.line(Self.rows[3], "2012 · not in your library") == "800 plays · 2012 · not in your library")
        #expect(played.line(Self.rows[3], "") == "800 plays")
        #expect(played.line(Self.rows[0], "2025 · in your library") == "2025 · in your library")
        // two lines for a row with plays at the accessibility sizes, so they wrap rather than being cut; else one
        #expect(played.lines(Self.rows[3], accessibility: true) == 2)
        #expect(played.lines(Self.rows[3], accessibility: false) == 1)
        #expect(played.lines(Self.rows[0], accessibility: true) == 1)
        #expect(newest.lines(Self.rows[3], accessibility: true) == 1)
    }

    /// (A2's review) `Made` makes the list again for another visit's albums: a late answer drew Newest first (the
    /// visit's albums nil), then a choice of Most played or a pull's answer gives the visit albums - the same rows, the
    /// same choice, and the list must change.
    @Test func theListIsMadeAgainForTheVisitsAlbums() {
        let lastfm = [Self.album("Lonerism", 800)]
        var made = AlbumPlays.Made()
        let drawn = made.shown(Self.rows, chosen: .played, visit: nil, albums: Self.albums)
        #expect(drawn.order == .newest && drawn.rows == Self.rows)
        let chosen = made.shown(Self.rows, chosen: .played, visit: lastfm, albums: Self.albums)
        #expect(chosen.order == .played && chosen.rows.first?.key == "group:lon")
        #expect(chosen == AlbumPlays.shown(Self.rows, chosen: .played, visit: lastfm, albums: Self.albums))
        // and other albums for the visit, the same count of them: made again
        let other = [Self.album("Innerspeaker", 900)]
        #expect(made.shown(Self.rows, chosen: .played, visit: other, albums: Self.albums).rows.first?.key == "album:inn")
        // the same again: the list made before, unchanged
        #expect(made.shown(Self.rows, chosen: .played, visit: other, albums: Self.albums).rows.first?.key == "album:inn")
    }

    @Test func thePlaysWords() {
        #expect(LastfmWords.plays(4_123_456, counted: .plays) == "4.1M plays")
        #expect(LastfmWords.plays(1, counted: .plays) == "1 play")
        #expect(LastfmWords.plays(999, counted: .plays) == "999 plays")
        #expect(LastfmWords.plays(2_399_999, counted: .listeners) == "2.3M listeners")
        #expect(LastfmWords.plays(1, counted: .listeners) == "1 listener")
        #expect(AlbumOrder.newest.words == "Newest first" && AlbumOrder.played.words == "Most played")
        #expect(LastfmWords.sortAlbums == "Sort albums")
    }

    @Test func theOrderIsReadWithCare() {
        #expect(AlbumOrder.storageKey == "deadwax-artist-album-order")
        #expect(AlbumOrder(saved: "played") == .played)
        #expect(AlbumOrder(saved: "newest") == .newest)
        // anything else - none, an old word, another case, a typo - is newest first
        for other in [nil, "", "Played", "most", "played ", "plays", "frequent"] as [String?] {
            #expect(AlbumOrder(saved: other) == .newest, "\(other ?? "nil")")
        }
        #expect(AlbumOrder.allCases.map(\.rawValue) == ["newest", "played"])
    }

    @Test func theVisitIsJudgedOnce() {
        let early = LastfmArtist(topAlbums: [Self.album("Lonerism", 800)])
        let later = LastfmArtist(topAlbums: [Self.album("Currents", 900)])
        // the answer in hand as the albums are first drawn orders the visit
        var inTime = AlbumPlays.Visit()
        inTime.drawn(early)
        #expect(inTime.albums == early.topAlbums && inTime.judged)
        // a late answer: the albums drawn with none - it never re-sorts the page drawn
        var late = AlbumPlays.Visit()
        late.drawn(nil)
        late.drawn(later)
        #expect(late.albums == nil)
        inTime.drawn(later)
        #expect(inTime.albums == early.topAlbums)
        // a pull takes the next answer (the albums in hand kept until it comes)
        late.reopen()
        #expect(late.albums == nil && !late.judged)
        late.drawn(later)
        #expect(late.albums == later.topAlbums)
        // Most played chosen in the menu: the answer in hand at once
        var chosen = AlbumPlays.Visit()
        chosen.drawn(nil)
        chosen.chose(later)
        #expect(chosen.albums == later.topAlbums)
        // and none for an answer with nothing to order by
        var empty = AlbumPlays.Visit()
        empty.drawn(LastfmArtist(topAlbums: []))
        #expect(empty.albums == nil)
    }

    /// (A2's review) A pull reopens a visit whose albums are in hand: they stay - the rows keep their Most played order
    /// - until the pull's answer is judged.
    @Test func aPullKeepsTheAlbumsInHandUntilItsAnswer() {
        let early = LastfmArtist(topAlbums: [Self.album("Lonerism", 800)])
        let pulled = LastfmArtist(topAlbums: [Self.album("Currents", 900)])
        var visit = AlbumPlays.Visit()
        visit.drawn(early)
        visit.reopen()
        #expect(visit.albums == early.topAlbums && !visit.judged)
        let shown = AlbumPlays.shown(Self.rows, chosen: .played, visit: visit.albums, albums: Self.albums)
        #expect(shown.order == .played && shown.rows.first?.key == "group:lon")
        visit.drawn(pulled)
        #expect(visit.albums == pulled.topAlbums && visit.judged)
        // a pull whose answer has no albums by plays: newest first from then on
        visit.reopen()
        visit.drawn(LastfmArtist(topAlbums: []))
        #expect(visit.albums == nil)
    }

    /// (A2's review) Whether Most played is offered reads what the order drawn reads: the visit's albums, or the answer
    /// in hand's - never hidden while the rows are in Most played order.
    @Test func mostPlayedIsOfferedWhileTheRowsAreInItsOrder() {
        let albums = LastfmArtist(topAlbums: [Self.album("Lonerism", 800)])
        let none = LastfmArtist()
        var visit = AlbumPlays.Visit()
        #expect(!visit.offers(nil) && !visit.offers(none) && visit.offers(albums))
        visit.drawn(albums)
        // an answer in hand without albums now (were it ever to replace one): still offered, the rows being in its order
        #expect(visit.offers(none) && visit.offers(nil))
        // drawn newest first, a later answer with albums: offered, so it can be chosen
        var late = AlbumPlays.Visit()
        late.drawn(nil)
        #expect(late.offers(albums) && !late.offers(none))
    }

    // MARK: the visit's timing (A2's review): LastfmVisit, as ArtistPageModel drives it

    static let withAlbums = LastfmArtist(topSongs: [LastfmTrack(title: "Let It Happen")],
                                         topAlbums: [album("Lonerism", 800)])
    static let otherAlbums = LastfmArtist(topSongs: [LastfmTrack(title: "Let It Happen")],
                                          topAlbums: [album("Currents", 900)])

    static func waiting() -> LastfmVisit {
        LastfmVisit(arrival: LastfmPage.Arrival(state: .on, online: true, kept: nil), answer: nil)
    }

    @Test func anAnswerInsideTheWaitOrdersTheAlbums() {
        var visit = Self.waiting()
        #expect(visit.arrival.holding && !visit.albums.judged)
        visit.asking(pulled: false)
        visit.answered(Self.withAlbums)
        // placed in place (A1's), then judged by it
        #expect(visit.arrival.released && visit.arrival.place == .inPlace)
        #expect(visit.albums.albums == Self.withAlbums.topAlbums)
        // the wait running out after it changes nothing
        visit.waited(Self.otherAlbums)
        #expect(visit.albums.albums == Self.withAlbums.topAlbums)
    }

    @Test func anAnswerAfterTheWaitLeavesThemNewestFirst() {
        var visit = Self.waiting()
        visit.asking(pulled: false)
        visit.waited(nil)
        #expect(visit.arrival.released && visit.albums.judged && visit.albums.albums == nil)
        visit.answered(Self.withAlbums)
        // placed after the albums (A1's), and the albums not moved
        #expect(visit.arrival.place == .afterAlbums)
        #expect(visit.albums.albums == nil)
        // offered, so Most played can be chosen - then ordered at once
        #expect(visit.albums.offers(Self.withAlbums))
        visit.chose(Self.withAlbums)
        #expect(visit.albums.albums == Self.withAlbums.topAlbums)
    }

    @Test func onlyAPullJudgesAgain() {
        var visit = Self.waiting()
        visit.waited(nil)
        visit.answered(Self.withAlbums)
        // another ask that isn't a pull (who they are now known by their MusicBrainz id): still newest first
        visit.asking(pulled: false)
        visit.answered(Self.otherAlbums)
        #expect(visit.albums.albums == nil)
        // a pull: the answer it brings orders them
        visit.asking(pulled: true)
        #expect(visit.albums.albums == nil)
        visit.answered(Self.otherAlbums)
        #expect(visit.albums.albums == Self.otherAlbums.topAlbums)
        // a pull with albums in hand keeps them until its answer
        visit.asking(pulled: true)
        #expect(visit.albums.albums == Self.otherAlbums.topAlbums)
        visit.answered(Self.withAlbums)
        #expect(visit.albums.albums == Self.withAlbums.topAlbums)
    }

    @Test func aKeptAnswerOrNoAskDrawsTheAlbumsAtOnce() {
        // the session's answer: nothing waits, the albums drawn by it as the visit begins
        let kept = LastfmVisit(arrival: LastfmPage.Arrival(state: .on, online: true, kept: true), answer: Self.withAlbums)
        #expect(kept.arrival.released && kept.albums.judged && kept.albums.albums == Self.withAlbums.topAlbums)
        // waiting: nothing judged as it begins
        #expect(!Self.waiting().albums.judged)
        // no ask can be made (deadwax out of reach): released, drawn by what is in hand
        var unasked = Self.waiting()
        unasked.unasked(Self.withAlbums)
        #expect(unasked.arrival.released && unasked.albums.albums == Self.withAlbums.topAlbums)
        var none = Self.waiting()
        none.unasked(nil)
        #expect(none.albums.judged && none.albums.albums == nil)
    }

    /// (A2's review, finding 6) The answer asked by name has its albums; the one asked by MusicBrainz id after it lost
    /// them (its top_albums past the route's 4 s) and its similar artists. Kept part by part, the second leaves both in
    /// hand: the menu still offered, the rows still in Most played order, Similar Artists still listed.
    @Test func aLaterAnswersMissingPartsNeverTakeAwayWhatIsDrawn() {
        let byName = LastfmArtist(url: "https://www.last.fm/music/Tame+Impala", listeners: 2_300_000,
                                  topSongs: [LastfmTrack(title: "Let It Happen")],
                                  similar: [LastfmSimilarArtist(name: "Pond", mbid: SimilarArtistsTests.pond)],
                                  topAlbums: [Self.album("Lonerism", 800)])
        let byMbid = LastfmArtist(unavailable: true, url: "https://www.last.fm/music/Tame+Impala", listeners: 2_400_000,
                                  topSongs: [LastfmTrack(title: "The Less I Know the Better")])
        var visit = Self.waiting()
        visit.answered(byName)
        let kept = byMbid.keeping(byName)
        visit.answered(kept)
        #expect(kept.topAlbums == byName.topAlbums && kept.similar == byName.similar)
        // its own parts its own
        #expect(kept.listeners == 2_400_000 && kept.topSongs == byMbid.topSongs && kept.unavailable)
        #expect(visit.albums.offers(kept))
        let shown = AlbumPlays.shown(Self.rows, chosen: .played, visit: visit.albums.albums, albums: Self.albums)
        #expect(shown.order == .played && AlbumPlays.offered(kept) && SimilarArtists.listed(kept))
        // taken whole, the menu would have hidden over rows in Most played order - and Similar Artists gone
        #expect(!AlbumPlays.offered(byMbid) && !SimilarArtists.listed(byMbid))
    }

    @Test func anAnswerIsKeptPartByPart() {
        let earlier = LastfmArtist(url: "https://www.last.fm/music/A", listeners: 10,
                                   topSongs: [LastfmTrack(title: "One")],
                                   similar: [LastfmSimilarArtist(name: "B")], topAlbums: [Self.album("X", 5)])
        // every part missing: every part the earlier's
        let empty = LastfmArtist(unavailable: true).keeping(earlier)
        #expect(empty.url == earlier.url && empty.listeners == 10 && empty.topSongs == earlier.topSongs
            && empty.similar == earlier.similar && empty.topAlbums == earlier.topAlbums && empty.unavailable)
        // a part the answer has - none listed ([]) among them - is its own
        let listed = LastfmArtist(listeners: 20, topSongs: [], similar: [], topAlbums: []).keeping(earlier)
        #expect(listed.listeners == 20 && listed.topSongs == [] && listed.similar == [] && listed.topAlbums == [])
        // not enabled: taken whole (Last.fm off or refused) - and nothing kept over an earlier that wasn't
        let off = LastfmArtist(enabled: false, unavailable: true, why: "refused").keeping(earlier)
        #expect(off == LastfmArtist(enabled: false, unavailable: true, why: "refused"))
        let after = LastfmArtist(listeners: 30)
        #expect(after.keeping(LastfmArtist(enabled: false, topAlbums: [Self.album("X", 5)])) == after)
        #expect(after.keeping(nil) == after)
    }

    /// The recorded answers (Fixtures/lastfm/answers/artist.json): Tame Impala's fifty, ordered over a page of theirs.
    @Test func theRecordedAlbumsOrderAPage() throws {
        let (cases, _, _) = try LastfmDecodeTests.exported()
        let tame = try LastfmDecodeTests.named(cases, "Tame Impala, by MusicBrainz id").answer
        let lastfm = try #require(AlbumPlays.counted(tame))
        #expect(lastfm.count == 50 && lastfm.allSatisfy { (album: LastfmAlbum) -> Bool in album.counted == .plays })
        // Last.fm's order isn't by plays: Deadbeat before Innerspeaker, with fewer
        #expect(lastfm.prefix(5).map(\.title) == ["Currents", "The Slow Rush", "Lonerism", "Deadbeat", "Innerspeaker"])
        let page = [Self.mine("dbt", "Deadbeat", year: "2025"), Self.mine("slw", "The Slow Rush", year: "2020"),
                    Self.mine("cur", "Currents"), Self.theirs("lon", "Lonerism"),
                    Self.mine("inn", "InnerSpeaker", year: "2010"), Self.mine("dra", "Dracula", year: "2025")]
        let shown = AlbumPlays.shown(page, chosen: .played, visit: lastfm, albums: Self.albums)
        #expect(Self.keys(shown.rows) == ["album:cur", "album:slw", "group:lon", "album:inn", "album:dbt", "album:dra"])
        #expect(shown.plays["album:cur"] == "197M plays")
        #expect(shown.plays["album:dra"] == "7.9M plays")
    }
}
