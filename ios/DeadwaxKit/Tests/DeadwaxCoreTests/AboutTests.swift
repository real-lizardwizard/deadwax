import Foundation
import Testing
@testable import DeadwaxCore

/// Info > About's cards: the web's aboutRows, held to the TypeScript's own answers (Fixtures/levels/info-vectors.json).
@Suite struct AboutTests {
    @Test func aboutIsTheWebsAboutRows() throws {
        let cases = try LevelVectors.info().aboutRows
        #expect(cases.count >= 45)
        for each in cases {
            let details = each.details.map { AboutDetails(song: $0.song, present: $0.store?.present) }
            let about = AboutCard.about(track: each.track.aboutTrack, album: each.album, details: details, folders: each.folders)
            #expect(about == each.about, "\(each.name)")
        }
    }

    @Test func theLinesAreTheWebs() throws {
        let info = try LevelVectors.info()
        for each in info.writtenBy {
            #expect(AboutCard.writtenBy(each.song) == each.words)
        }
        for each in info.playedLine {
            #expect(AboutCard.playedLine(each.count) == each.words, "\(String(describing: each.count))")
        }
        for each in info.labelLine {
            #expect(AboutCard.labelLine(each.labels) == each.words)
        }
        for each in info.trackTime {
            #expect(AboutCard.trackTime(each.seconds) == each.words, "\(String(describing: each.seconds))")
        }
        for each in info.sharedFormat {
            #expect(AboutCard.sharedFormat(each.songs) == each.format)
        }
        #expect(info.writtenBy.count >= 5 && info.playedLine.count >= 5 && info.trackTime.count >= 8)
    }

    @Test func navidromesAnswerIsReadLeniently() throws {
        //? an odd field is nil, an odd element of a list left out - the rest of the answer still read
        let text = #"""
        {"id": "al", "name": "Dummy", "artist": "Portishead", "year": "1994", "songCount": 11,
         "song": [{"id": "s1", "track": "1", "discNumber": 1, "duration": 308.4, "suffix": "flac", "playCount": 3,
                   "contributors": [{"role": "composer", "artist": {"id": "ar", "name": "Geoff Barrow"}}, 7, {"role": "composer"}]},
                  {"id": "s2", "track": 2}],
         "discTitles": [{"disc": "2", "title": "Bonus"}, {"disc": true, "title": "One"}, {"disc": "x", "title": "No"}, {"title": "None"}],
         "recordLabels": [{"name": "Go! Beat"}, {"name": 3}, "London"]}
        """#
        let album = try JSONDecoder().decode(AboutAlbum.self, from: Data(text.utf8))
        #expect(album.year == nil && album.songCount == 11)
        #expect(album.song?.count == 2)
        #expect(album.song?.first?.track == nil && album.song?.first?.discNumber == 1 && album.song?.first?.duration == 308.4)
        #expect(album.song?.first?.contributors == [SongDetails.Credit(role: "composer", name: "Geoff Barrow"), SongDetails.Credit(role: "composer", name: nil)])
        #expect(album.discTitles == [AboutDiscTitle(disc: 2, title: "Bonus"), AboutDiscTitle(disc: 1, title: "One"), AboutDiscTitle(disc: nil, title: "No"),
                                     AboutDiscTitle(disc: nil, title: "None")])
        #expect(album.recordLabels == [AboutAlbum.Label(name: "Go! Beat"), AboutAlbum.Label(name: nil)])
        #expect(AboutCard.labelLine(album.recordLabels) == "Go! Beat")
        #expect(AboutCard.writtenBy(album.song?.first) == "Geoff Barrow")
    }

    @Test func aStubOfTwoDiscsHasNoDiscLine() {
        //? the info vector "a playlist's stub of two discs", by hand: the album page would head the song "Disc 2 ·
        //? Unreleased Tracks", but a stub's songs aren't the album's - no disc line, as the web
        let track = AboutTrack(id: "d2t3", title: "x", artist: "Pink Floyd", album: "Wish You Were Here", albumId: "wywh", coverArt: nil, duration: 300)
        let songs = [SongDetails(id: "d1t1", track: 1, discNumber: 1), SongDetails(id: "d2t3", track: 3, discNumber: 2)]
        let whole = AboutAlbum(id: "wywh", name: "Wish You Were Here", song: songs, discTitles: [AboutDiscTitle(disc: 2, title: "Unreleased Tracks")])
        #expect(AboutCard.about(track: track, album: whole).song.lines == ["Track 3 \u{00B7} 5:00", "Disc 2 \u{00B7} Unreleased Tracks"])
        let stub = AboutAlbum(id: "wywh", name: "Wish You Were Here", song: songs, partial: true,
                              discTitles: [AboutDiscTitle(disc: 2, title: "Unreleased Tracks")])
        #expect(AboutCard.about(track: track, album: stub).song.lines == ["Track 3 \u{00B7} 5:00"])
    }

    @Test func aDiscWrittenAsTextIsReadAsJavaScriptReadsIt() {
        #expect(AboutDiscTitle.number("2") == 2)
        #expect(AboutDiscTitle.number(" 3 ") == 3)
        #expect(AboutDiscTitle.number("") == 0)
        #expect(AboutDiscTitle.number("1.5") == 1.5)
        #expect(AboutDiscTitle.number("Infinity") == nil)
        #expect(AboutDiscTitle.number("nan") == nil)
        #expect(AboutDiscTitle.number("0x10") == 16, "Number(\"0x10\") is 16 in JavaScript too")
        #expect(AboutDiscTitle.number("0x1p3") == nil)
        #expect(AboutDiscTitle.number("two") == nil)
    }

    @Test func aPressingsYearIsReadWhetherTextOrNumber() throws {
        let rows = try JSONDecoder().decode([PressingRow].self, from: Data(#"""
        [{"path": "P/Dummy (1994)", "edition": "", "year": "1994", "formats": ["flac"]},
         {"path": "P/Dummy", "edition": null, "year": 2014, "formats": null}]
        """#.utf8))
        #expect(rows == [PressingRow(path: "P/Dummy (1994)", edition: "", year: "1994", formats: ["flac"]),
                         PressingRow(path: "P/Dummy", edition: nil, year: "2014", formats: nil)])
    }

    @Test func aSongIsAnEntryAsTheWebMakesOne() {
        let song = Song(id: "s1", title: "Roads", albumId: "al", duration: 305, coverArt: "c")
        #expect(AboutTrack(song: song) == AboutTrack(id: "s1", title: "Roads", artist: "", album: "", albumId: "al", coverArt: "c", duration: 305))
        #expect(AboutTrack(song: Song(id: "x")).duration == 0)
    }

    @Test func theArtistCardIsTheSongsArtistsNameAlone() {
        //? D8: the name and nothing else - not even the web's "The album is by Various Artists" on a compilation
        let track = AboutTrack(id: "s1", title: "Roads", artist: "Portishead", album: "Dummy", albumId: "al", coverArt: nil, duration: 305)
        let album = AboutAlbum(id: "al", name: "Dummy", artist: "Various Artists", song: [SongDetails(id: "s1", artist: "Portishead", track: 4)])
        let about = AboutCard.about(track: track, album: album)
        #expect(about.artist == About.ArtistCard(name: "Portishead"))
        let encoded = try? JSONEncoder().encode(about.artist)
        #expect(encoded.map { String(decoding: $0, as: UTF8.self) } == #"{"name":"Portishead"}"#)
        //? a number past the album's count: no count; the length the queue's, the album sending none
        #expect(about.song.lines == ["Track 4 \u{00B7} 5:05"])
        #expect(about.album == About.AlbumCard(id: "al", title: "Dummy", coverArt: nil, line: "1 song", pressing: nil, folder: nil))
    }
}
