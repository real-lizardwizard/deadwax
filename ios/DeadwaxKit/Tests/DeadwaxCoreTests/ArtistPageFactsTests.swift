import Testing
@testable import DeadwaxCore

/// The redrawn artist page's counts and words (ArtistPageFacts, slice R6): the phone's "16 · 6 yours", the Mac band's
/// chips and status bar, an album's format, and which rows offer Get.
@Suite struct ArtistPageFactsTests {
    static func mine(_ id: String, yours: Bool) -> ArtistJoin.Row {
        .yours(ArtistPage.Row(key: "album:\(id)", title: id, year: "1979", albumId: id, coverArt: nil, yours: yours))
    }

    static func theirs(_ id: String, held: Bool?, yours: Bool? = nil, editions: Int = 0) -> MBArtistPage.Row {
        MBArtistPage.Row(key: "group:\(id)", title: id, year: "1976", group: ReleaseGroup(id: id, title: id),
                         held: held, yours: yours, editions: editions, releases: [], kind: nil)
    }

    static let rows: [ArtistJoin.Row] = [
        mine("a", yours: true), mine("b", yours: true), mine("c", yours: false),
        .theirs(theirs("d", held: false)), .theirs(theirs("e", held: false)), .theirs(theirs("f", held: nil)),
        .theirs(theirs("g", held: true, yours: true, editions: 2)), .theirs(theirs("h", held: true, yours: false)),
    ]

    @Test func theCountsAreTheRowsOwnMarks() {
        let personal = ArtistPageFacts.counts(Self.rows, personal: true)
        // yours: a, b and g; the collection's: c and h; to get: d and e - f, not yet said, none of them
        #expect(personal == ArtistPageFacts.Counts(albums: 8, yours: 3, collection: 2, toGet: 2))
        // without a library of your own every album held is in your library
        let shared = ArtistPageFacts.counts(Self.rows, personal: false)
        #expect(shared == ArtistPageFacts.Counts(albums: 8, yours: 5, collection: 0, toGet: 2))
    }

    @Test func thePhonesHeading() {
        #expect(ArtistPageFacts.heading(.init(albums: 16, yours: 6, collection: 0, toGet: 10)) == "16 · 6 yours")
        #expect(ArtistPageFacts.headingSpoken(.init(albums: 16, yours: 6, collection: 0, toGet: 10)) == "16 albums, 6 yours")
        // all yours, or none: the count alone; no album, nothing
        #expect(ArtistPageFacts.heading(.init(albums: 6, yours: 6, collection: 0, toGet: 0)) == "6")
        #expect(ArtistPageFacts.heading(.init(albums: 4, yours: 0, collection: 0, toGet: 4)) == "4")
        #expect(ArtistPageFacts.heading(.init(albums: 0, yours: 0, collection: 0, toGet: 0)) == "")
        #expect(ArtistPageFacts.headingSpoken(.init(albums: 1, yours: 1, collection: 0, toGet: 0)) == "1 album")
    }

    @Test func theBandsChipsAndTheStatusBar() {
        let counts = ArtistPageFacts.Counts(albums: 16, yours: 6, collection: 0, toGet: 10)
        #expect(ArtistPageFacts.chips(counts, mayGet: true).map(\.words) == ["6 in your library", "10 more to get"])
        #expect(ArtistPageFacts.chips(counts, mayGet: true).map(\.yours) == [true, false])
        // (R6's review) to someone who may not get albums, nothing is to get
        #expect(ArtistPageFacts.chips(counts, mayGet: false).map(\.words) == ["6 in your library"])
        let collection = ArtistPageFacts.chips(.init(albums: 3, yours: 0, collection: 3, toGet: 0), mayGet: true)
        #expect(collection.map(\.words) == ["3 in the collection"] && collection[0].yours == false)
        #expect(ArtistPageFacts.status(counts, songs: 59) == ["16 albums", "6 in your library", "59 songs"])
        #expect(ArtistPageFacts.status(.init(albums: 1, yours: 0, collection: 0, toGet: 1), songs: 0) == ["1 album"])
        #expect(ArtistPageFacts.status(.init(albums: 0, yours: 0, collection: 0, toGet: 0), songs: 0).isEmpty)
    }

    @Test func onlyAnAlbumNobodyHoldsOffersGet() {
        #expect(ArtistPageFacts.offersGet(Self.theirs("d", held: false), mayGet: true))
        #expect(!ArtistPageFacts.offersGet(Self.theirs("g", held: true, yours: true), mayGet: true))
        #expect(!ArtistPageFacts.offersGet(Self.theirs("h", held: true, yours: false), mayGet: true))
        #expect(!ArtistPageFacts.offersGet(Self.theirs("f", held: nil), mayGet: true))
        // (R6's review) and only to someone who may get albums
        #expect(!ArtistPageFacts.offersGet(Self.theirs("d", held: false), mayGet: false))
        #expect(ArtistPageFacts.pressings(Self.theirs("g", held: true, yours: true, editions: 2)) == "2 pressings")
        #expect(ArtistPageFacts.pressings(Self.theirs("h", held: true, yours: false, editions: 1)) == "")
    }

    @Test func anAlbumsFormatIsAlbumInfos() {
        let songs = [Song(id: "1", title: "A", suffix: "flac", samplingRate: 96_000, bitDepth: 24),
                     Song(id: "2", title: "B", suffix: "flac", samplingRate: 96_000, bitDepth: 24)]
        let album = Album(id: "x", song: songs)
        let said = AlbumInfo.quality(songs).first { $0.label == "Format" }?.value
        #expect(said != nil && ArtistPageFacts.format(album) == said)
        #expect(ArtistPageFacts.format(Album(id: "y")) == "" && ArtistPageFacts.format(nil) == "")
    }

    @Test func theFactsLineKeepsItsRoomOnceAsked() {
        let mbid = "8e66ea2b-b57b-47d9-8df0-df4630aeb8e5"
        // who they are known and deadwax in reach: being asked - the room held before the answer
        #expect(ArtistPageFacts.holdsFacts(mbid: mbid, online: true, facts: nil))
        // in hand: held, online or not
        let facts = MBArtistFacts(name: "Midnight Oil")
        #expect(ArtistPageFacts.holdsFacts(mbid: mbid, online: false, facts: facts))
        // not asked: no MBID, or out of reach with nothing in hand
        #expect(!ArtistPageFacts.holdsFacts(mbid: nil, online: true, facts: nil))
        #expect(!ArtistPageFacts.holdsFacts(mbid: "not-one", online: true, facts: nil))
        #expect(!ArtistPageFacts.holdsFacts(mbid: mbid, online: false, facts: nil))
    }

    @Test func aMacRowIsSpokenAsItsCells() {
        let low: ArtistJoin.Row = .yours(ArtistPage.Row(key: "album:low", title: "Low", year: "1977", albumId: "low",
                                                        coverArt: nil, yours: true))
        #expect(ArtistPageFacts.spoken(low, personal: true, format: "FLAC") == "Low, 1977, in your library, FLAC")
        #expect(ArtistPageFacts.spoken(.theirs(Self.theirs("Powerage", held: false)), personal: true, format: "")
            == "Powerage, 1976, not in your library")
        #expect(ArtistPageFacts.spoken(.theirs(Self.theirs("Heroes", held: true, yours: false, editions: 2)),
                                       personal: true, format: "") == "Heroes, 1976, in the collection, 2 pressings")
        // not yet said of: its title and year alone
        #expect(ArtistPageFacts.spoken(.theirs(Self.theirs("f", held: nil)), personal: true, format: "") == "f, 1976")
    }

    @Test func theWords() {
        #expect(ArtistPageFacts.Words.everything == "Everything" && ArtistPageFacts.Words.studioOnly == "Studio only")
        #expect(ArtistPageFacts.Words.moveAlbums == "Move albums\u{2026}")
        #expect(ArtistPageFacts.Words.getLabel("Powerage") == "Get Powerage")
        #expect(ArtistPageFacts.Words.plays(1) == "1 play" && ArtistPageFacts.Words.plays(1411) == "1,411 plays")
    }
}
