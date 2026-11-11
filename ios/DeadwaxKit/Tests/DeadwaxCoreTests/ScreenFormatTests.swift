import Foundation
import Testing
@testable import DeadwaxCore

/// Fixtures/screens/format.json: lib/format.ts's trackTime, formatDuration and sharedFormat, lib/scrub.ts's clock and
/// lib/titles.ts's long title over awkward numbers and strings; the album page's meta line, footer, rows, its ••• and
/// spinner names, and player/levelling.ts's warm - each as the TypeScript answered it.
@Suite struct ScreenFormatTests {
    let fixture = try! Web.load("format")

    @Test func theFixtureIsThere() {
        #expect(fixture["trackTime"].list.count > 250)
        #expect(fixture["sharedFormat"].list.count > 20)
        #expect(fixture["album"]["footers"].list.count == 80)
        expectMadeFrom(fixture, ["ui/src/lib/format.ts", "ui/src/lib/titles.ts", "ui/src/player/levelling.ts", "ui/src/lib/scrub.ts",
                                 "ui/src/player/AlbumPage.tsx the meta line", "ui/src/player/AlbumPage.tsx the footer"])
    }

    @Test func trackTimeIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["trackTime"].list {
            let seconds = row[0].num
            diffs.text("trackTime(\(row[0]))", Format.trackTime(seconds), row[2])
        }
        diffs.done()
    }

    @Test func formatDurationIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["formatDuration"].list {
            diffs.text("formatDuration(\(row[0]))", Format.formatDuration(row[0].num!), row[1])
        }
        diffs.done()
    }

    @Test func clockIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["clock"].list {
            diffs.text("clock(\(row[0]))", Format.clock(row[0].num!), row[1])
            diffs.text("Scrub.clock(\(row[0]))", Scrub.clock(row[0].num!), row[1])
        }
        diffs.done()
    }

    @Test func sharedFormatIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["sharedFormat"].list {
            //? "undefined": a song that sent no suffix
            let suffixes: [String?] = row["suffixes"].list.map { $0.string == "undefined" ? nil : $0.string }
            diffs.text("sharedFormat(\(row["suffixes"]))", Format.sharedFormat(suffixes: suffixes), row["format"])
            let songs = suffixes.enumerated().map { Song(id: "s\($0.offset)", suffix: $0.element) }
            diffs.text("sharedFormat(songs \(row["suffixes"]))", Format.sharedFormat(songs), row["format"])
        }
        diffs.done()
    }

    @Test func aLongTitleIsTheWebs() {
        let album = fixture["album"]
        #expect(Format.longTitle == album["longTitle"].int)
        let diffs = ScreenDiffs()
        for row in album["longTitles"].list {
            let title = row["title"].string == "undefined" ? nil : row["title"].string
            diffs.flag("isLongTitle(\(row["title"]))", Format.isLongTitle(title), row["long"])
        }
        diffs.done()
    }

    @Test func theAlbumPagesMetaLineIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["album"]["meta"].list {
            let year = row["year"].int
            let line = AlbumPageLines.meta(genre: row["genre"].string, year: year, format: row["format"].string)
            diffs.text("meta(\(row["genre"]), \(row["year"]), \(row["format"]))", line, row["line"])
        }
        diffs.done()
        //? and from an album answer: its genre, year and its songs' one format
        let album = Album(id: "al", year: 1994, genre: "Trip Hop", song: [Song(id: "a", suffix: "flac"), Song(id: "b", suffix: "FLAC")])
        #expect(AlbumPageLines.meta(album) == "Trip Hop · 1994 · FLAC")
        #expect(AlbumPageLines.meta(nil) == "")
    }

    @Test func theAlbumPagesFooterIsTheWebs() {
        let diffs = ScreenDiffs()
        for (index, row) in fixture["album"]["footers"].list.enumerated() {
            let songs = row["durations"].list.enumerated().map { Song(id: "s\($0.offset)", duration: $0.element.num) }
            diffs.number("footer \(index)'s total", AlbumPageLines.total(songs), row["total"])
            diffs.text("footer \(index)", AlbumPageLines.footer(songs), row["footer"])
        }
        diffs.done()
    }

    @Test func theAlbumPagesRowsAreTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["album"]["rows"].list {
            let song = Song(id: "s", title: "Roads", artist: row["artist"].string, track: row["track"].int)
            //? `shownMissing`: the album's answer not in yet - no album artist to compare with
            let albumArtist = row["shownMissing"].bool == true ? nil : row["albumArtist"].string
            diffs.text("number(\(row["track"]))", AlbumPageLines.number(song), row["number"])
            diffs.text("artistShown(\(row["artist"]), album \(row["albumArtist"]))", AlbumPageLines.artistShown(song, albumArtist: albumArtist),
                       row["artistShown"])
        }
        diffs.done()
        let words = fixture["album"]["words"]
        #expect(AlbumPageLines.moreForSong("Roads") == (words["moreForSong"].string ?? "") + "Roads")
        #expect(AlbumPageLines.moreForAlbum == words["moreForAlbum"].string)
        #expect(AlbumPageLines.loading == words["loading"].string)
    }

    @Test func theWarmIsTheWebs() {
        let diffs = ScreenDiffs()
        for row in fixture["album"]["warms"].list {
            let setting = Normalization(rawValue: row["setting"].string!)!
            let songs: [Song]? = row["songs"].isNull ? nil : row["songs"].list.enumerated().map {
                Song(id: "s\($0.offset)", suffix: $0.element["suffix"].string, contentType: $0.element["contentType"].string)
            }
            diffs.flag("warms(\(setting), \(row["songs"]))", AlbumPageLines.warms(setting, songs: songs), row["warmed"])
        }
        diffs.done()
    }

    /// About's own trackTime and sharedFormat (About.swift, Info's port) fold into these when About is next touched;
    /// until then they must agree - on every finite length (About writes Infinity as Swift does, "inf:nan", where the
    /// web and Format write "Infinity:NaN").
    @Test func aboutsCopiesAgreeWithThese() throws {
        for row in fixture["trackTime"].list {
            let seconds = row[0].num
            if let seconds, !seconds.isFinite { continue }
            #expect(AboutCard.trackTime(seconds) == Format.trackTime(seconds), "trackTime(\(row[0]))")
        }
        #expect(AboutCard.trackTime(.infinity) == "inf:nan" && Format.trackTime(.infinity) == "Infinity:NaN",
                "About's one known difference, outside every length Navidrome sends")
        for row in fixture["sharedFormat"].list {
            let suffixes: [String?] = row["suffixes"].list.map { $0.string == "undefined" ? nil : $0.string }
            let details = suffixes.map { SongDetails(suffix: $0) }
            #expect(AboutCard.sharedFormat(details) == Format.sharedFormat(suffixes: suffixes), "sharedFormat(\(row["suffixes"]))")
        }
    }
}
