import Testing
@testable import DeadwaxCore

/// An artist's most-played songs (MostPlayedSongs, the Mac artist page's Your most played - slice R6): each song once
/// across its pressings, its plays one take's (never a sum), most first with ties in album order, the never-played left
/// out, and what a tap plays.
@Suite struct MostPlayedTests {
    static func song(_ id: String, _ title: String?, album: String, plays: Int?) -> Song {
        Song(id: id, title: title, albumId: album, playCount: plays)
    }

    // the page's play order: newest first - a deluxe pressing of 1979's album, the album itself, and an older one
    static let deluxe = Album(id: "dlx", name: "Highway to Hell (Deluxe)", year: 2003, song: [
        song("d1", "Highway to Hell - 2003 Remaster", album: "dlx", plays: 3),
        song("d2", "Touch Too Much", album: "dlx", plays: 9),
        song("d3", "Night Prowler", album: "dlx", plays: nil),
    ])
    static let highway = Album(id: "hth", name: "Highway to Hell", year: 1979, song: [
        song("h1", "Highway to Hell", album: "hth", plays: 12),
        song("h2", "Touch Too Much", album: "hth", plays: 9),
        song("h3", "Shot Down in Flames", album: "hth", plays: 0),
    ])
    static let powerage = Album(id: "pow", name: "Powerage", year: 1978, song: [
        song("p1", "Riff Raff", album: "pow", plays: 9),
        song("p2", "Sin City", album: "pow", plays: 1411),
        song("p3", nil, album: "pow", plays: 40),
    ])
    static let albums = [deluxe, highway, powerage]

    @Test func eachSongOnceItsPlaysOneTakesNeverASum() {
        let rows = MostPlayedSongs.rows(Self.albums)
        // Highway to Hell: the 1979 take's 12, not 12 + 3; Touch Too Much: a tie at 9, the deluxe's (first in album
        // order); Riff Raff's 9 after both in album order; the never-played and the untitled left out
        #expect(rows.map(\.song.id) == ["p2", "h1", "d2", "p1"])
        #expect(rows.map(\.plays) == [1411, 12, 9, 9])
        #expect(rows.map(\.rank) == [0, 1, 2, 3])
        // the take's own album, and its plays as its album's Plays cell says them
        #expect(rows[1].album.id == "hth" && rows[1].line == "Highway to Hell · 1979")
        #expect(rows[0].playsWords == "1,411" && rows[0].playsWords == MacAlbumFacts.plays(1411))
        #expect(rows[0].title == "Sin City")
    }

    @Test func aSongIsItsTopSongsKey() {
        // a remaster's dash take is the song; a remix is a song of its own
        let one = Album(id: "a", name: "A", year: 2015, song: [
            Self.song("a1", "Let It Happen", album: "a", plays: 2),
            Self.song("a2", "Let It Happen (Max Cooper remix)", album: "a", plays: 1),
        ])
        let two = Album(id: "b", name: "B", year: 2010,
                        song: [Self.song("b1", "Let It Happen - 2015 Remaster", album: "b", plays: 5)])
        let rows = MostPlayedSongs.rows([one, two])
        #expect(rows.map(\.song.id) == ["b1", "a2"])
        #expect(LastfmMatch.key("Let It Happen - 2015 Remaster") == LastfmMatch.key("Let It Happen"))
    }

    @Test func theTenMostAndASongOnce() {
        let songs = (0..<14).map { (n: Int) -> Song in Self.song("s\(n)", "Song \(n)", album: "x", plays: n + 1) }
        // a song twice in one answer is listed once
        let album = Album(id: "x", name: "X", song: songs + [songs[13]])
        let rows = MostPlayedSongs.rows([album])
        #expect(rows.count == MostPlayedSongs.most)
        #expect(rows.first?.song.id == "s13" && rows.last?.song.id == "s4")
        #expect(MostPlayedSongs.rows([]).isEmpty)
    }

    @Test func aTapPlaysTheListFromItsRow() {
        let rows = MostPlayedSongs.rows(Self.albums)
        let plan = MostPlayedSongs.play(rows, from: 2) { _ in true }
        #expect(plan?.songs.map(\.id) == ["p2", "h1", "d2", "p1"] && plan?.at == 2)
        // offline, only those on this device - and a row that doesn't play plays nothing
        let here: Set<String> = ["h1", "p1"]
        let offline = MostPlayedSongs.play(rows, from: 3) { here.contains($0.id) }
        #expect(offline?.songs.map(\.id) == ["h1", "p1"] && offline?.at == 1)
        #expect(MostPlayedSongs.play(rows, from: 0) { here.contains($0.id) } == nil)
    }
}
