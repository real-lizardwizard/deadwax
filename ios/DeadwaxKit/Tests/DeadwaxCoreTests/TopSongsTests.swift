import Testing
@testable import DeadwaxCore

/// Top Songs' rows (lastfm.md 3.2): each top song met with the page's albums' songs - the earliest album's take, each
/// library song once - or not in your library; rows that wait while the songs aren't in; what a tap plays; and which
/// album a song you don't have opens.
@Suite struct TopSongsTests {
    static func track(_ title: String) -> LastfmTrack { LastfmTrack(title: title) }

    static func song(_ id: String, _ title: String, album: String, disc: Int? = nil, track: Int? = nil) -> Song {
        Song(id: id, title: title, albumId: album, track: track, discNumber: disc)
    }

    // Currents (2015), Lonerism (2012), a live album after both (2016), and a compilation with no year
    static let currents = Album(id: "cur", name: "Currents", year: 2015, song: [
        song("c1", "Let It Happen", album: "cur", disc: 1, track: 1),
        song("c2", "The Less I Know the Better", album: "cur", disc: 1, track: 7),
        song("c3", "Eventually", album: "cur", disc: 1, track: 8),
    ])
    static let lonerism = Album(id: "lon", name: "Lonerism", year: 2012, song: [
        song("l1", "Elephant", album: "lon", disc: 1, track: 5),
        song("l2", "Feels Like We Only Go Backwards", album: "lon", disc: 1, track: 6),
    ])
    static let live = Album(id: "liv", name: "Live at Wembley", year: 2016, song: [
        song("v1", "Elephant (Live)", album: "liv", disc: 1, track: 1),
        song("v2", "Feels Like We Only Go Backwards - Live", album: "liv", disc: 1, track: 2),
        song("v3", "Let It Happen (Live)", album: "liv", disc: 1, track: 3),
    ])
    static let undated = Album(id: "und", name: "Odds", year: 0, song: [song("u1", "Eventually", album: "und")])
    /// The page's play order: newest first, undated last (ArtistPage.rows).
    static let albums = [live, currents, lonerism, undated]

    static func kinds(_ rows: [TopSongs.Row]) -> [String] {
        rows.map { (row: TopSongs.Row) -> String in
            switch row.kind {
            case .waiting: return "waiting"
            case .unknown: return "unknown"
            case .missing: return "missing"
            case .have(let song, let album): return "\(song.id)@\(album.id)"
            }
        }
    }

    @Test func aSongYouHaveIsTheEarliestAlbumsTake() {
        let top = ["Elephant", "Let It Happen - 2015 Remaster", "Feels Like We Only Go Backwards (feat. Someone)",
                   "Eventually", "Borderline"].map(Self.track)
        let rows = TopSongs.rows(top, albums: Self.albums)
        // Elephant: Lonerism's 2012 studio take, not 2016's live one - though the live album comes first in the page's
        // order; Let It Happen's remaster is Currents' take; the feature dropped; Eventually: dated before undated
        #expect(Self.kinds(rows) == ["l1@lon", "c1@cur", "l2@lon", "c3@cur", "missing"])
        // the library song's own title, its album and year
        #expect(rows[1].title == "Let It Happen")
        #expect(rows[1].line == "Currents · 2015")
        #expect(rows[4].title == "Borderline")
        #expect(rows[4].line == LastfmWords.notInLibrary)
    }

    @Test func anotherTitleIsNeverAMatch() {
        let top = ["Elephant (Max Cooper remix)", "Let It Happen - Radio Edit", "Elephants", "Eventually - Demo"]
            .map(Self.track)
        #expect(Self.kinds(TopSongs.rows(top, albums: Self.albums)) == ["missing", "missing", "missing", "missing"])
    }

    @Test func eachLibrarySongMeetsOneTopSongAtMost() {
        // two top songs with one key (the server folds them, the app never leans on it): the higher takes the earliest
        // take, the next the next take - and with no take left, it is not in your library
        let top = ["Elephant", "Elephant - Live", "Elephant (Live)"].map(Self.track)
        #expect(Self.kinds(TopSongs.rows(top, albums: Self.albums)) == ["l1@lon", "v1@liv", "missing"])
        // one album holding a song twice (the same id in two places) counts it once
        let twice = Album(id: "two", name: "Twice", year: 2001, song: [Self.song("t1", "Roads", album: "two"),
                                                                     Self.song("t1", "Roads", album: "two")])
        #expect(Self.kinds(TopSongs.rows(["Roads", "Roads"].map(Self.track), albums: [twice])) == ["t1@two", "missing"])
    }

    @Test func tiesGoByPlayOrderThenDiscThenTrack() {
        let a = Album(id: "a", name: "A", year: 1994, song: [Self.song("a2", "Roads", album: "a", disc: 2, track: 1),
                                                              Self.song("a1", "Roads", album: "a", disc: 1, track: 9)])
        let b = Album(id: "b", name: "B", year: 1994, song: [Self.song("b1", "Roads", album: "b", disc: 1, track: 1)])
        // the same year: the page's order first (b before a), then within an album disc 1 before disc 2
        let rows = TopSongs.rows(["Roads", "Roads", "Roads"].map(Self.track), albums: [b, a])
        #expect(Self.kinds(rows) == ["b1@b", "a1@a", "a2@a"])
        let tracks = Album(id: "t", name: "T", year: nil, song: [Self.song("t9", "Roads", album: "t", track: 9),
                                                                 Self.song("tx", "Roads", album: "t"),
                                                                 Self.song("t2", "Roads", album: "t", track: 2)])
        #expect(Self.kinds(TopSongs.rows(["Roads", "Roads", "Roads"].map(Self.track), albums: [tracks]))
            == ["t2@t", "t9@t", "tx@t"])
    }

    @Test func rowsWaitUntilEveryAlbumsSongsAreIn() {
        let top = ["Elephant", "Borderline"].map(Self.track)
        let waiting = TopSongs.rows(top, albums: nil)
        #expect(Self.kinds(waiting) == ["waiting", "waiting"])
        // Last.fm's title, a blank line, and nothing to play
        #expect(waiting.map(\.title) == ["Elephant", "Borderline"])
        #expect(waiting.map(\.line) == ["", ""])
        #expect(waiting.allSatisfy { $0.song == nil })
        #expect(TopSongs.play(waiting, from: 0) { _ in true } == nil)
    }

    /// (The review of A1) An album of theirs whose songs aren't in hand - offline, one neither the page nor this device
    /// has; online, one that didn't load - may have a top song: it is never "Not in your library".
    @Test func aSongOnAnAlbumNotInHandIsNeverNotInYourLibrary() {
        let top = ["The Less I Know the Better", "Elephant", "Borderline"].map(Self.track)
        let rows = TopSongs.rows(top, albums: [Self.lonerism], unknown: true)
        #expect(Self.kinds(rows) == ["unknown", "l1@lon", "unknown"])
        #expect(rows[0].title == "The Less I Know the Better" && rows[0].line == "" && rows[0].song == nil)
        #expect(TopSongs.play(rows, from: 0) { _ in true } == nil)
        #expect(TopSongs.play(rows, from: 1) { _ in true }?.songs.map(\.id) == ["l1"])
        // every album in hand: a song none of them has is not in your library
        #expect(Self.kinds(TopSongs.rows(top, albums: [Self.lonerism], unknown: false)) == ["missing", "l1@lon", "missing"])
    }

    @Test func offlineTheAlbumsInHandAreThePagesOrThisDevicesAndAnyOtherIsUnknown() throws {
        // Tame Impala opened online, then again offline: a new page (no asks), Last.fm's answer the session's, only
        // Lonerism downloaded - Currents' songs aren't in hand, so "The Less I Know the Better" may be yours
        let order = ["cur", "lon"]
        let fresh = ArtistAlbumAsks<Album>()
        let library = try #require(TopSongs.library(order: order, asks: fresh, online: false) { (id: String) -> Album? in
            id == "lon" ? Self.lonerism : nil
        })
        #expect(library.albums.map(\.id) == ["lon"] && library.unknown)
        let top = ["The Less I Know the Better", "Elephant"].map(Self.track)
        #expect(Self.kinds(TopSongs.rows(top, albums: library.albums, unknown: library.unknown)) == ["unknown", "l1@lon"])
        // both on the device: every album in hand, nothing unknown
        let both = try #require(TopSongs.library(order: order, asks: fresh, online: false) { (id: String) -> Album? in
            id == "lon" ? Self.lonerism : Self.currents
        })
        #expect(both.albums.map(\.id) == ["cur", "lon"] && !both.unknown)
        #expect(Self.kinds(TopSongs.rows(top, albums: both.albums, unknown: both.unknown)) == ["c2@cur", "l1@lon"])
        // the page's own answers first, offline too
        var asks = ArtistAlbumAsks<Album>()
        let sent = asks.want(order)
        _ = asks.answered(try #require(sent.first { $0.id == "cur" }), with: Self.currents)
        let mixed = try #require(TopSongs.library(order: order, asks: asks, online: false) { _ in nil })
        #expect(mixed.albums.map(\.id) == ["cur"] && mixed.unknown)
    }

    @Test func onlineAnAlbumThatDidntLoadMakesItsSongsUnknown() throws {
        let order = ["cur", "lon"]
        var asks = ArtistAlbumAsks<Album>()
        // before the asks are for these albums, and until each has answered or failed: every row waits
        #expect(TopSongs.library(order: order, asks: asks, online: true) { _ in nil } == nil)
        let sent = asks.want(order)
        #expect(TopSongs.library(order: order, asks: asks, online: true) { _ in nil } == nil)
        _ = asks.answered(try #require(sent.first { $0.id == "lon" }), with: Self.lonerism)
        #expect(TopSongs.library(order: order, asks: asks, online: true) { _ in nil } == nil)
        // Currents didn't come: its songs aren't known - and online this device's copy isn't asked
        _ = asks.failed(try #require(sent.first { $0.id == "cur" }))
        let library = try #require(TopSongs.library(order: order, asks: asks, online: true) { _ in Self.currents })
        #expect(library.albums.map(\.id) == ["lon"] && library.unknown)
        let top = ["The Less I Know the Better", "Elephant"].map(Self.track)
        #expect(Self.kinds(TopSongs.rows(top, albums: library.albums, unknown: library.unknown)) == ["unknown", "l1@lon"])
        // Try again, and it comes: known
        for ask in asks.again() where ask.id == "cur" { _ = asks.answered(ask, with: Self.currents) }
        let whole = try #require(TopSongs.library(order: order, asks: asks, online: true) { _ in nil })
        #expect(whole.albums.map(\.id) == ["cur", "lon"] && !whole.unknown)
    }

    @Test func aSongYouDontHaveIsSearchedForByItsTitleAsKeyed() {
        #expect(TopSongs.searchQuery(title: "Let It Happen - 2015 Remaster", artist: "Tame Impala")
            == SongSearch.fieldedQuery(title: "Let It Happen", artist: "Tame Impala"))
        #expect(TopSongs.searchQuery(title: "Lost in Yesterday (feat. X)", artist: "Tame Impala")
            == SongSearch.fieldedQuery(title: "Lost in Yesterday", artist: "Tame Impala"))
        // a song of its own is asked for as itself
        #expect(TopSongs.searchQuery(title: "Roads (Max Cooper remix)", artist: "Portishead")
            == SongSearch.fieldedQuery(title: "Roads (Max Cooper remix)", artist: "Portishead"))
        #expect(TopSongs.searchQuery(title: "Let It Happen - Radio Edit", artist: "Tame Impala")
            == SongSearch.fieldedQuery(title: "Let It Happen - Radio Edit", artist: "Tame Impala"))
        // a title that strips to nothing is asked as written
        #expect(TopSongs.searchQuery(title: " - Live", artist: "X") == SongSearch.fieldedQuery(title: " - Live", artist: "X"))
        #expect(TopSongs.searchQuery(title: "Let It Happen - 2015 Remaster", artist: "Tame Impala")
            != SongSearch.fieldedQuery(title: "Let It Happen - 2015 Remaster", artist: "Tame Impala"))
    }

    @Test func theListIsLastfmsFirstTen() {
        let top = (1...14).map { Self.track("Song \($0)") }
        let rows = TopSongs.rows(top, albums: [])
        #expect(rows.count == 10)
        #expect(rows.map(\.rank) == Array(0..<10))
        #expect(rows.last?.title == "Song 10")
    }

    @Test func aTapPlaysThePlayableTopSongsFromThisOne() throws {
        let top = ["Elephant", "Borderline", "Let It Happen", "Eventually"].map(Self.track)
        let rows = TopSongs.rows(top, albums: Self.albums)
        let played = try #require(TopSongs.play(rows, from: 2) { _ in true })
        #expect(played.songs.map(\.id) == ["l1", "c1", "c3"])
        #expect(played.at == 1)
        // offline, only those on this device - and one that isn't plays nothing
        let here = try #require(TopSongs.play(rows, from: 3) { $0.id != "c1" })
        #expect(here.songs.map(\.id) == ["l1", "c3"])
        #expect(here.at == 1)
        #expect(TopSongs.play(rows, from: 2) { $0.id != "c1" } == nil)
        // a song you don't have plays nothing
        #expect(TopSongs.play(rows, from: 1) { _ in true } == nil)
    }

    // MARK: the album a song you don't have opens

    static let tame = "63aa26c3-d59b-4da4-84ac-716b54f1ef4d"

    static func found(_ title: String, credit: String, artists: [String], albums: [String]) -> FoundSong {
        FoundSong(key: "\(title)|\(credit)", title: title, credit: credit,
                  artists: artists.map { SongArtist(id: $0, name: credit) },
                  albums: albums.map { SongAlbum(id: $0, title: $0, kind: "Album", band: .album) })
    }

    @Test func theAlbumIsTheFirstOfTheirSong() {
        let found = [
            Self.found("Borderline", credit: "Someone Else", artists: ["11111111-1111-1111-1111-111111111111"],
                       albums: ["other"]),
            Self.found("Borderline (Live)", credit: "Tame Impala", artists: [Self.tame], albums: ["live-album"]),
            Self.found("Borderline", credit: "Tame Impala", artists: [Self.tame], albums: ["the-slow-rush", "single"]),
        ]
        // by their id: another artist's Borderline is never theirs; the first of theirs in MusicBrainz's order is taken,
        // a take of the song ("(Live)") being the song as LastfmMatch.key has it
        #expect(TopSongs.album(found, title: "Borderline", mbid: Self.tame, name: "Tame Impala")?.id == "live-album")
        #expect(TopSongs.album(Array(found.suffix(1)), title: "Borderline", mbid: Self.tame, name: "Tame Impala")?.id
            == "the-slow-rush")
        // the id known but not among anyone's: none, whatever the credit says
        #expect(TopSongs.album(found, title: "Borderline", mbid: "22222222-2222-2222-2222-222222222222",
                               name: "Tame Impala") == nil)
        // with no id: their name as the credit, folded
        #expect(TopSongs.album(Array(found.prefix(1)) + Array(found.suffix(1)), title: "Borderline", mbid: nil,
                               name: "tame  impala")?.id == "the-slow-rush")
        #expect(TopSongs.album(Array(found.prefix(1)), title: "Borderline", mbid: nil, name: "Tame Impala") == nil)
        // another title is no match
        #expect(TopSongs.album(found, title: "Borderlines", mbid: Self.tame, name: "Tame Impala") == nil)
        #expect(TopSongs.album(found, title: "", mbid: Self.tame, name: "Tame Impala") == nil)
    }

    @Test func aFailedSearchIsSaidInAListenersWords() {
        let away = APIFailure.answered(.init(status: 503, method: "GET", path: "/deadwax/search_musicbrainz/songs"))
        #expect(TopSongs.trouble(away, admin: false) == LastfmWords.away)
        #expect(TopSongs.trouble(away, admin: true) == LastfmWords.away)
        let broken = APIFailure.answered(.init(status: 500, method: "GET", path: "/deadwax/search_musicbrainz/songs",
                                               detail: "boom"))
        #expect(TopSongs.trouble(broken, admin: false) == ErrorWords.of(broken, admin: false).said)
        #expect(TopSongs.trouble(broken, admin: false) != LastfmWords.away)
    }
}
