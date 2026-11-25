import Foundation
import Testing
@testable import DeadwaxCore

/// An album's and a playlist's facts on the Mac's pages (the redesign, slice R5): a nil play count never 0, the size of
/// every disc or none, "Played yesterday · 12 times" by the calendar's days (midnight crossed both ways), Album info's
/// Played row the page's own words, Properties, the status bars, and a playlist's Whose and Changed.
@Suite struct MacAlbumFactsTests {
    private static let utc = TimeZone(identifier: "UTC")!
    /// 25 Nov 2026, 15:00 UTC.
    private static let now: Int64 = AlbumTime.ms("2026-11-25T15:00:00Z")!

    private static func song(_ id: String, disc: Int? = nil, size: Int64? = nil, plays: Int? = nil,
                             duration: Double = 200) -> Song {
        Song(id: id, title: id, discNumber: disc, duration: duration, suffix: "flac", size: size, bitDepth: 16,
             playCount: plays)
    }

    @Test func aNilPlayCountIsABlankNeverNought() {
        #expect(MacAlbumFacts.plays(nil) == "")
        #expect(MacAlbumFacts.plays(0) == "")
        #expect(MacAlbumFacts.plays(12) == "12")
        #expect(MacAlbumFacts.plays(1411) == "1,411")
    }

    @Test func twoDiscsAreTwoHeadingRowsTheTitledOneWithItsTitle() {
        // (R5's review) a disc's heading row above its first song - the second disc's with its title - and the songs'
        // own track numbers, never "2-1"
        let songs = [Song(id: "a", title: "a", track: 1, discNumber: 1), Song(id: "b", title: "b", track: 2, discNumber: 1),
                     Song(id: "c", title: "c", track: 1, discNumber: 2), Song(id: "d", title: "d", track: 10, discNumber: 2)]
        let titles = [DiscTitle(disc: 2, title: "Live at the Roundhouse")]
        let lines = MacAlbumFacts.songLines(songs, headings: DiscHeadings.headings(songs, titles))
        #expect(lines == [.group("Disc 1"), .row("0|a"), .row("1|b"),
                          .group("Disc 2 · Live at the Roundhouse"), .row("2|c"), .row("3|d")])
        #expect(MacTable.rows(lines) == ["0|a", "1|b", "2|c", "3|d"])
        #expect(songs.map(AlbumPageLines.number) == ["1", "2", "1", "10"])
        // the stripes start again under each heading, as Requests' do
        #expect(MacTable.stripes(lines) == [false, false, true, false, false, true])
        // one disc with no title: no heading at all; one disc with a title: its heading
        let one = Array(songs.prefix(2))
        #expect(MacAlbumFacts.songLines(one, headings: DiscHeadings.headings(one, nil)) == [.row("0|a"), .row("1|b")])
        #expect(MacAlbumFacts.songLines(one, headings: DiscHeadings.headings(one, [DiscTitle(disc: 1, title: "Side A")]))
                    == [.group("Disc 1 · Side A"), .row("0|a"), .row("1|b")])
        // a song twice is two rows
        #expect(MacAlbumFacts.lineID(0, songs[0]) != MacAlbumFacts.lineID(4, songs[0]))
    }

    @Test func theSizeIsEveryDiscsOrNone() {
        let both = [Self.song("1", disc: 1, size: 100), Self.song("2", disc: 1, size: 200), Self.song("3", disc: 2, size: 300),
                    Self.song("4", disc: 2, size: 400)]
        #expect(MacAlbumFacts.size(both) == 1000)
        // a song that doesn't say its size: no size at all, never a part drawn as the whole
        let missing = both + [Self.song("5", disc: 2)]
        #expect(MacAlbumFacts.size(missing) == nil)
        #expect(MacAlbumFacts.size([]) == nil)
        // the status bar's and Properties' sizes are the same sum
        #expect(MacAlbumFacts.status(both).last == DeadwaxCore.Bytes.words(1000))
        let album = Album(id: "a", name: "A", year: 1980, song: both)
        let facts = MacAlbumFacts.properties(album, songs: both, folder: nil, zone: Self.utc)
        #expect(facts.first { $0.label == MacAlbumFacts.Words.size }?.value == DeadwaxCore.Bytes.words(1000))
    }

    @Test func playedIsTheCalendarsDayAcrossMidnight() {
        // ten minutes past midnight, played twenty minutes before: yesterday, though not an hour has passed
        let justAfter = AlbumTime.ms("2026-11-25T00:10:00Z")!
        #expect(MacAlbumFacts.playedWords("2026-11-24T23:50:00Z", count: 12, now: justAfter, zone: Self.utc)
                    == "yesterday · 12 times")
        // ten to midnight, played just after the midnight before: today, though nearly a day has passed
        let justBefore = AlbumTime.ms("2026-11-25T23:50:00Z")!
        #expect(MacAlbumFacts.playedWords("2026-11-25T00:10:00Z", count: 1, now: justBefore, zone: Self.utc)
                    == "today · once")
        // and the day before that, nearly two days on: yesterday
        #expect(MacAlbumFacts.playedWords("2026-11-24T00:10:00Z", count: 3, now: justBefore, zone: Self.utc)
                    == "yesterday · 3 times")
        // the device's own day, not UTC's: 23:50 UTC on the 24th is the 25th in Auckland
        let auckland = TimeZone(identifier: "Pacific/Auckland")!
        #expect(MacAlbumFacts.playedWords("2026-11-24T23:50:00Z", count: nil, now: justAfter, zone: auckland) == "today")
    }

    @Test func playedIsLastPlayedsWordsAndNothingForNever() {
        let album = Album(id: "a", name: "A", played: "2026-11-24T20:00:00Z", playCount: 12)
        #expect(MacAlbumFacts.played(album, now: Self.now, zone: Self.utc) == "Played yesterday · 12 times")
        // R2's words, not a second set: the same day words Artists' Last played says
        let ms = AlbumTime.ms("2026-11-12T20:00:00Z")!
        let older = Album(id: "b", name: "B", played: "2026-11-12T20:00:00Z", playCount: 2)
        #expect(MacAlbumFacts.played(older, now: Self.now, zone: Self.utc)
                    == "Played \(ArtistTotals.lastPlayedWords(ms, now: Self.now, zone: Self.utc)) · 2 times")
        // never played: Navidrome's zero time, or none
        for played in [nil, "0001-01-01T00:00:00Z", ""] as [String?] {
            let never = Album(id: "c", name: "C", played: played, playCount: nil)
            #expect(MacAlbumFacts.played(never, now: Self.now, zone: Self.utc) == nil, "\(String(describing: played))")
            #expect(MacAlbumFacts.playedRow(never, now: Self.now, zone: Self.utc) == nil)
        }
        // no count: when alone
        let uncounted = Album(id: "d", name: "D", played: "2026-11-25T08:00:00Z", playCount: nil)
        #expect(MacAlbumFacts.played(uncounted, now: Self.now, zone: Self.utc) == "Played today")
    }

    @Test func albumInfosPlayedRowIsThePagesWords() {
        // check 555: Albums' Info and the album page agree - one rule, the row the page's line after "Played"
        let album = Album(id: "a", name: "A", played: "2026-11-24T20:00:00Z", playCount: 1411)
        let row = MacAlbumFacts.playedRow(album, now: Self.now, zone: Self.utc)
        #expect(row?.label == "Played")
        #expect(row.map { "Played \($0.value)" } == MacAlbumFacts.played(album, now: Self.now, zone: Self.utc))
        #expect(row?.value == "yesterday · 1,411 times")
        // the row is last in Album info's The album; with none (the iPhone, or never played) The album is as it was
        let named = Album(id: "a", name: "A", artist: "AC/DC", year: 1980, played: "2026-11-24T20:00:00Z", playCount: 1411,
                          song: [Self.song("1", size: 100), Self.song("2", size: 200)])
        let mac = AlbumInfo.local(album: named, onPhone: nil, device: .mac, played: row)
        let phone = AlbumInfo.local(album: named, onPhone: nil, device: .iPhone)
        let macAlbum = mac.first { $0.title == AlbumInfoWords.albumTitle }
        let phoneAlbum = phone.first { $0.title == AlbumInfoWords.albumTitle }
        #expect(macAlbum?.rows.last == row)
        #expect(phoneAlbum?.rows == AlbumInfo.theAlbum(named))
        #expect(!(phoneAlbum?.rows.isEmpty ?? true))
        #expect(macAlbum.map { Array($0.rows.dropLast()) } == phoneAlbum?.rows)
    }

    @Test func propertiesSayWhatTheAppHasAndLeaveOutWhatItHasnt() {
        let songs = [Self.song("1", disc: 1, size: 1_000_000), Self.song("2", disc: 2, size: 2_000_000)]
        let album = Album(id: "a", name: "A", year: 1980, created: "2025-11-12T23:30:00Z", played: "2026-11-25T08:00:00Z",
                          playCount: 4, song: songs)
        let folder = AlbumInfoRow(label: "Folder", value: "AC_DC/Back in Black (1980)")
        let facts = MacAlbumFacts.properties(album, songs: songs, folder: folder, zone: Self.utc)
        #expect(facts.map(\.label) == ["Released", "Added", "Format", "Size", "Folder"])
        #expect(facts[0].value == "1980")
        #expect(facts[1].value == "12 November 2025")
        #expect(facts[2].value == AlbumInfo.quality(songs).first?.value)
        #expect(facts[4].value == "AC_DC/Back in Black (1980)")
        // (R5's review) Album info's own row, its word as Album info says it: "Folders" for an album in two
        let store = StoreAlbum(present: [StoreRow(id: 1, path: "AC_DC/Back in Black (1980)"),
                                         StoreRow(id: 2, path: "AC_DC/Back in Black (1980) [Deluxe]")])
        let two = MacAlbumFacts.properties(album, songs: songs, folder: AlbumInfo.server(store: store, folders: true).first,
                                           zone: Self.utc)
        #expect(two.last?.label == "Folders")
        #expect(two.last?.value == AlbumInfo.server(store: store, folders: true).first?.value)
        #expect(MacAlbumFacts.properties(album, songs: songs, folder: AlbumInfo.server(store: store, folders: false).first,
                                         zone: Self.utc).map(\.label) == ["Released", "Added", "Format", "Size"])
        // Added is the day in the device's own zone
        let auckland = TimeZone(identifier: "Pacific/Auckland")!
        let there = MacAlbumFacts.properties(album, songs: songs, folder: nil, zone: auckland)
        #expect(there.first { $0.label == "Added" }?.value == "13 November 2025")
        // no folder for whoever may not see it, no year, no time, no play: each left out
        let bare = Album(id: "b", name: "B", song: [Self.song("3")])
        let few = MacAlbumFacts.properties(bare, songs: [Self.song("3")], folder: nil, zone: Self.utc)
        #expect(few.map(\.label) == ["Format"])
    }

    @Test func theStatusBarCountsTheSongsTheirLengthAndSize() {
        let songs = [Self.song("1", size: 100, duration: 1200), Self.song("2", size: 200, duration: 1320)]
        #expect(MacAlbumFacts.status(songs) == ["2 songs", Format.formatDuration(2520), DeadwaxCore.Bytes.words(300)])
        #expect(MacAlbumFacts.status([Self.song("1", duration: 60)]) == ["1 song", Format.formatDuration(60)])
        #expect(MacAlbumFacts.status([]) == [])
    }

    @Test func aPlaylistsWhoseAndChanged() {
        let yours = Playlist(id: "1", name: "Late night", changed: "2026-11-25T08:00:00Z", owner: "james", mine: true,
                             editable: true)
        let theirs = Playlist(id: "2", name: "Sunday", changed: "2026-11-21T08:00:00Z", owner: "Ethan")
        let nameless = Playlist(id: "3", name: "Odd", owner: " ")
        #expect(MacAlbumFacts.whose(yours) == "Yours")
        #expect(MacAlbumFacts.whose(theirs) == "Ethan")
        #expect(MacAlbumFacts.whose(nameless) == "Somebody")
        #expect(MacAlbumFacts.changed(yours, now: Self.now, zone: Self.utc) == "today")
        #expect(MacAlbumFacts.changed(theirs, now: Self.now, zone: Self.utc) == "4 days ago")
        #expect(MacAlbumFacts.changed(nameless, now: Self.now, zone: Self.utc) == "")
        #expect(MacAlbumFacts.playlistLine(yours, now: Self.now, zone: Self.utc) == "Yours · changed today")
        #expect(MacAlbumFacts.playlistsStatus([yours, theirs]) == ["2 playlists", "1 yours", "1 shared with you"])
        // (R5's review) none listed - offline with none here, or Find finding none: nothing, never "0 playlists"
        #expect(MacAlbumFacts.playlistsStatus([]) == [])
        #expect(MacAlbumFacts.playlistsStatus([theirs]) == ["1 playlist", "1 shared with you"])
    }

    @Test func playlistsColumnsFitBesideTheSidePanel() {
        // (R5's review) the narrowest page - a 1280 window beside the sidebar and the side panel's column, 589 - keeps
        // Playlist its least; the smallest window's page (880 less the sidebar, 660) keeps every column
        let narrowest = MacFrame.columnMin - MacLook.sidebarWidth - MacFrame.panelWidth - 1
        #expect(narrowest == 589)
        let beside = MacAlbumFacts.playlistColumns(width: narrowest)
        #expect(beside == [.playlist, .songs, .length, .onDevice])
        #expect(narrowest - MacAlbumFacts.fixedWidth(beside) >= MacAlbumFacts.playlistLeast)
        let smallest = MacFrame.smallestWidth - MacLook.sidebarWidth
        #expect(MacAlbumFacts.playlistColumns(width: smallest) == MacAlbumFacts.PlaylistColumn.allCases)
        #expect(smallest - MacAlbumFacts.fixedWidth(MacAlbumFacts.PlaylistColumn.allCases) >= MacAlbumFacts.playlistLeast)
        // at every page from the narrowest up, Playlist is left its least: Whose and Changed go before it would be
        for width in stride(from: narrowest, through: 1400.0, by: 1.0) {
            let shown = MacAlbumFacts.playlistColumns(width: width)
            #expect(width - MacAlbumFacts.fixedWidth(shown) >= MacAlbumFacts.playlistLeast, "\(width)")
        }
        #expect(MacAlbumFacts.playlistTitle(.onDevice, device: .mac) == "On this Mac")
    }
}
