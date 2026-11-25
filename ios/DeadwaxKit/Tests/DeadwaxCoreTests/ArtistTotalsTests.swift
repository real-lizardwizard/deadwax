import Foundation
import Testing
@testable import DeadwaxCore

/// An artist's totals from the album index (the redesign, slice R2): each album under its own artistId alone, a nil
/// played never a date, the Last played words by the calendar's days, the counts and the phone's row line.
@Suite struct ArtistTotalsTests {
    private static let utc = TimeZone(identifier: "UTC")!
    /// 25 Nov 2026, 15:00 UTC.
    private static let now: Int64 = AlbumTime.ms("2026-11-25T15:00:00Z")!
    private static let day: Int64 = 86_400_000

    private static func album(_ id: String, artist: String?, songs: Int? = nil, plays: Int? = nil,
                              played: String? = nil) -> IndexAlbum {
        IndexAlbum(id: id, name: id, artist: artist.map { "Name of \($0)" }, artistId: artist, played: played,
                   playCount: plays, songCount: songs)
    }

    @Test func eachAlbumCountsUnderItsOwnArtistAlone() {
        let albums = [
            Self.album("a1", artist: "acdc", songs: 10, plays: 40, played: "2026-11-20T10:00:00Z"),
            Self.album("a2", artist: "acdc", songs: 8, plays: 2, played: "2026-11-24T10:00:00Z"),
            Self.album("b1", artist: "bjork", songs: 12, plays: 7, played: "2026-11-25T09:00:00Z"),
            // the same name, another artist: two artists, never one
            IndexAlbum(id: "c1", name: "c1", artist: "Name of acdc", artistId: "acdc-2", playCount: 5, songCount: 3),
            // nobody's
            Self.album("d1", artist: nil, songs: 99, plays: 99, played: "2026-11-25T14:00:00Z"),
            Self.album("e1", artist: "", songs: 99, plays: 99),
        ]
        let totals = ArtistTotals.of(albums, zone: Self.utc)
        #expect(Set(totals.keys) == ["acdc", "bjork", "acdc-2"])
        #expect(totals["acdc"] == ArtistTotal(songs: 18, plays: 42, lastPlayed: AlbumTime.ms("2026-11-24T10:00:00Z")))
        #expect(totals["bjork"] == ArtistTotal(songs: 12, plays: 7, lastPlayed: AlbumTime.ms("2026-11-25T09:00:00Z")))
        #expect(totals["acdc-2"] == ArtistTotal(songs: 3, plays: 5, lastPlayed: nil))
    }

    /// (R2's review) The status bar's album total: the index's albums under the artists listed, each once - one per
    /// album id, an album nobody's never counted, another artist's never counted.
    @Test func theStatusBarCountsEachAlbumOnce() {
        let albums = [
            Self.album("a1", artist: "acdc"), Self.album("a2", artist: "acdc"), Self.album("b1", artist: "bjork"),
            // the index naming one album twice (a page boundary, a repeat): still one album
            Self.album("a1", artist: "acdc"),
            Self.album("c1", artist: "can"), Self.album("d1", artist: nil), Self.album("e1", artist: ""),
        ]
        #expect(ArtistTotals.albumCount(of: ["acdc", "bjork"], in: albums) == 3)
        #expect(ArtistTotals.albumCount(of: ["acdc"], in: albums) == 2)
        #expect(ArtistTotals.albumCount(of: [], in: albums) == 0)
        #expect(ArtistTotals.albumCount(of: ["acdc", "bjork", "can"], in: []) == 0)
        #expect(ArtistTotals.albumCount(of: ["nobody", ""], in: albums) == 0, "an album nobody's is never counted")
        // never the Albums column summed: Navidrome counts a split album under each of its artists, the index under one
        // (b's albumCount would hold s1 too, so the Albums column summed says 3)
        let split = [Self.album("s1", artist: "a"), Self.album("a2", artist: "a")]
        #expect(ArtistTotals.albumCount(of: ["a", "b"], in: split) == 2)
    }

    /// (R2's review) Last played's now: a page reads it as it shows and at a day's change, never per cell - close to
    /// the clock's.
    @Test func nowIsTheClocksInMilliseconds() {
        let before = Int64(Date().timeIntervalSince1970 * 1000)
        let now = ArtistTotals.now()
        let after = Int64(Date().timeIntervalSince1970 * 1000)
        #expect(before <= now && now <= after)
    }

    @Test func aMissingCountIsNoneAndNeverLessThanNone() {
        let albums = [Self.album("a1", artist: "x"), Self.album("a2", artist: "x", songs: -4, plays: -1),
                      Self.album("a3", artist: "x", songs: 2, plays: 3)]
        #expect(ArtistTotals.of(albums)["x"] == ArtistTotal(songs: 2, plays: 3, lastPlayed: nil))
        #expect(ArtistTotals.of([]).isEmpty)
    }

    @Test func aNilPlayedIsNeverADate() {
        // never played, Navidrome's zero time, a value that isn't a date: no Last played at all
        for played in [nil, "0001-01-01T00:00:00Z", "", "never", "1970-01-01T00:00:00Z"] as [String?] {
            let album = Self.album("a", artist: "x", plays: 0, played: played)
            #expect(ArtistTotals.playedAt(album, zone: Self.utc) == nil, "\(String(describing: played))")
            #expect(ArtistTotals.of([album], zone: Self.utc)["x"]?.lastPlayed == nil)
        }
        #expect(ArtistTotals.lastPlayedWords(nil, now: Self.now, zone: Self.utc) == "")
        // and one played album among unplayed ones gives its own time
        let albums = [Self.album("a", artist: "x"), Self.album("b", artist: "x", played: "2026-11-25T08:00:00Z"),
                      Self.album("c", artist: "x", played: "0001-01-01T00:00:00Z")]
        #expect(ArtistTotals.of(albums, zone: Self.utc)["x"]?.lastPlayed == AlbumTime.ms("2026-11-25T08:00:00Z"))
    }

    @Test func lastPlayedIsWordedByTheCalendarsDays() {
        func words(_ text: String) -> String {
            ArtistTotals.lastPlayedWords(AlbumTime.ms(text), now: Self.now, zone: Self.utc)
        }
        #expect(words("2026-11-25T00:00:01Z") == "today")
        #expect(words("2026-11-25T14:59:00Z") == "today")
        #expect(words("2026-11-26T09:00:00Z") == "today", "a time after now - a clock set wrong - is today")
        #expect(words("2026-11-24T23:59:59Z") == "yesterday", "yesterday by the calendar, not 24 hours")
        #expect(words("2026-11-24T00:00:00Z") == "yesterday")
        #expect(words("2026-11-23T12:00:00Z") == "2 days ago")
        #expect(words("2026-11-22T12:00:00Z") == "3 days ago")
        #expect(words("2026-11-19T12:00:00Z") == "6 days ago")
        #expect(words("2026-11-18T12:00:00Z") == "last week")
        #expect(words("2026-11-12T12:00:00Z") == "last week")
        #expect(words("2026-11-11T12:00:00Z") == "11 Nov")
        #expect(words("2026-01-01T00:00:00Z") == "1 Jan")
        #expect(words("2025-11-12T12:00:00Z") == "12 Nov 2025", "another year's day says its year")
        #expect(words("1999-02-28T12:00:00Z") == "28 Feb 1999")
    }

    @Test func theDaysAreTheDevicesZones() {
        // 25 Nov 01:30 in Auckland (+13) is 24 Nov 12:30 UTC: today there, yesterday in London
        let auckland = TimeZone(identifier: "Pacific/Auckland")!
        let played = AlbumTime.ms("2026-11-24T12:30:00Z")!
        let now = AlbumTime.ms("2026-11-25T10:00:00Z")!
        #expect(ArtistTotals.lastPlayedWords(played, now: now, zone: auckland) == "today")
        #expect(ArtistTotals.lastPlayedWords(played, now: now, zone: Self.utc) == "yesterday")
        #expect(ArtistTotals.day(0, zone: Self.utc) == 0)
        #expect(ArtistTotals.day(-1, zone: Self.utc) == -1, "before 1970, the day before")
        func civil(_ days: Int64) -> String {
            let date = ArtistTotals.civil(days)
            return "\(date.year)-\(date.month)-\(date.day)"
        }
        #expect(civil(0) == "1970-1-1")
        #expect(civil(-1) == "1969-12-31")
        #expect(civil(ArtistTotals.day(Self.now, zone: Self.utc)) == "2026-11-25")
        #expect(civil(ArtistTotals.day(AlbumTime.ms("2024-02-29T12:00:00Z")!, zone: Self.utc)) == "2024-2-29")
    }

    @Test func theCountsMarkTheirThousands() {
        #expect(ArtistTotals.albums(140) == "140 albums")
        #expect(ArtistTotals.albums(1) == "1 album")
        #expect(ArtistTotals.songs(1612) == "1,612 songs")
        #expect(ArtistTotals.songs(0) == "0 songs")
        #expect(ArtistTotals.artists(1) == "1 artist")
        #expect(ArtistTotals.artists(48) == "48 artists")
        #expect(ArtistTotals.plays(1411) == "1,411")
        #expect(ArtistTotals.plays(0) == "", "no plays: an empty cell")
        #expect(ArtistTotals.oneSelected == "1 selected")
        // a column's count: its thousands marked, nothing for one Navidrome didn't give, never below none
        #expect(ArtistTotals.number(1612) == "1,612")
        #expect(ArtistTotals.number(0) == "0")
        #expect(ArtistTotals.number(nil) == "")
        #expect(ArtistTotals.number(-3) == "0")
    }

    @Test func theMacsColumnsAreTheDrawingsWords() {
        #expect([LibraryColumnWords.album, LibraryColumnWords.artist, LibraryColumnWords.year, LibraryColumnWords.songs]
                == ["Album", "Artist", "Year", "Songs"])
        #expect([LibraryColumnWords.artist, LibraryColumnWords.albums, LibraryColumnWords.songs, LibraryColumnWords.plays,
                  LibraryColumnWords.lastPlayed] == ["Artist", "Albums", "Songs", "Plays", "Last played"])
        #expect(LibraryColumnWords.sort == "Sort")
        #expect(LibraryColumnWords.playing == "Playing")
    }

    /// (R2's review, finding 2) Play's help while it has nothing to play: Grid selects nothing, so the way is List.
    @Test func playSaysHowToHaveSomethingToPlay() {
        #expect(LibraryColumnWords.playHelp(list: false, selected: false, artist: false) == "Select an album in List to play it.")
        #expect(LibraryColumnWords.playHelp(list: false, selected: true, artist: false) == "Select an album in List to play it.",
                "Grid: whatever was selected is not")
        #expect(LibraryColumnWords.playHelp(list: true, selected: false, artist: false) == "Select an album to play it.")
        #expect(LibraryColumnWords.playHelp(list: true, selected: true, artist: false) == "", "its songs coming: nothing")
        #expect(LibraryColumnWords.playHelp(list: false, selected: false, artist: true) == "Select an artist in List to play them.")
        #expect(LibraryColumnWords.playHelp(list: true, selected: false, artist: true) == "Select an artist to play them.")
        #expect(LibraryColumnWords.playHelp(list: true, selected: true, artist: true) == "")
    }

    @Test func thePhonesRowSaysTheSongsOnceTheyAreInHand() {
        #expect(ArtistTotals.rowLine(albums: 6, songs: 59) == "6 albums · 59 songs")
        #expect(ArtistTotals.rowLine(albums: 1, songs: 1) == "1 album · 1 song")
        #expect(ArtistTotals.rowLine(albums: 2, songs: 1200, place: Whose.inTheCollection)
                == "2 albums · 1,200 songs \(Whose.inTheCollection)")
        // no songs in hand: the row's words as they were
        for place in ["", Whose.inTheCollection] {
            #expect(ArtistTotals.rowLine(albums: 6, songs: nil, place: place) == ArtistWords.albumCountLine(6, place: place))
            #expect(ArtistTotals.rowLine(albums: 6, songs: 0, place: place) == ArtistWords.albumCountLine(6, place: place))
        }
        #expect(ArtistTotals.rowLine(albums: nil, songs: nil) == "")
        #expect(ArtistTotals.rowLine(albums: 0, songs: 4) == "4 songs")
    }
}
