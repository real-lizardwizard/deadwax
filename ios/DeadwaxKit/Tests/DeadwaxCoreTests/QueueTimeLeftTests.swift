import Foundation
import Testing
@testable import DeadwaxCore

/// (R3b) The Queue's time left and headings (QueueTimeLeft.swift), and Info's Played row (AboutCard.played) - notes/ios.md
/// "The redesign, slice R3b: the Queue, Info and the EQ inside".
@Suite struct QueueTimeLeftTests {
    static func song(_ id: String, _ seconds: Double, album: String = "Wilco (The Album)", artist: String = "Wilco") -> QueueTrack {
        QueueTrack(id: id, title: id, artist: artist, album: album, albumId: album, duration: seconds)
    }

    static func rows(_ tracks: [QueueTrack], from key: Int) -> [UpNextRow] {
        tracks.enumerated().map { UpNextRow(key: key + $0.offset, track: $0.element) }
    }

    /// iQueue's foot: One Wing (3:41) playing 1:00 in, then eight songs - 33 minutes and a bit, rounded up.
    @Test func eightSongsAndWhatIsLeftOfThePlayingOne() {
        let next = [339.0, 206, 261, 242, 184, 263, 253, 238].enumerated().map { Self.song("n\($0.offset)", $0.element) }
        let view = UpNextView(playing: Self.song("One Wing", 221), added: [],
                              list: UpNextList(title: "From Wilco (The Album)", rows: Self.rows(next, from: 1), more: 0),
                              then: nil, repeatOne: false)
        // 161 s left of One Wing, then 1986 s: 2147 s, 35.8 min - 36 min, said rounded up
        #expect(QueueTimeLeft.words(view, position: 60) == "8 songs · 36 min left")
        #expect(QueueTimeLeft.words(view, position: 221) == "8 songs · 34 min left")
        // a position past the song's end, or before its start, is held to it
        #expect(QueueTimeLeft.words(view, position: 9999) == "8 songs · 34 min left")
        #expect(QueueTimeLeft.words(view, position: -5) == QueueTimeLeft.words(view, position: 0))
    }

    /// History has played: it never counts, however long it is. And the song playing counts only what is left of it.
    @Test func historyNeverCountsNorTheSongPlayingWhole() {
        let played = Self.rows([Self.song("h1", 3600), Self.song("h2", 3600)], from: 0)
        let view = UpNextView(history: played, playing: Self.song("now", 600), added: Self.rows([Self.song("a", 120)], from: 3),
                              list: nil, then: nil, repeatOne: false)
        // 600 - 540 = 60 s left of it, and 120 s: 3 min - never 2 hr 3 min (History), never 12 min (the song whole)
        #expect(QueueTimeLeft.words(view, position: 540) == "1 song · 3 min left")
        #expect(QueueTimeLeft.words(view, position: 0) == "1 song · 12 min left")
    }

    @Test func playingNextAndTheListAndTheUndrawnOnes() {
        let view = UpNextView(playing: Self.song("now", 60), added: Self.rows([Self.song("a", 60)], from: 1),
                              list: UpNextList(title: "Still to play", rows: Self.rows([Self.song("b", 60)], from: 2), more: 40),
                              then: nil, repeatOne: false)
        // 42 songs to come; the 40 past the drawn ones have no length here, so the time is a least
        #expect(QueueTimeLeft.words(view, position: 0) == "42 songs · over 3 min left")
    }

    @Test func aSongOfUnknownLengthMakesItALeast() {
        let view = UpNextView(playing: Self.song("now", 0), added: Self.rows([Self.song("a", 120)], from: 1),
                              list: nil, then: nil, repeatOne: false)
        #expect(QueueTimeLeft.words(view, position: 0) == "1 song · over 2 min left")
    }

    @Test func repeatOneSaysTheSongsAlone() {
        let view = UpNextView(playing: Self.song("now", 200), added: Self.rows([Self.song("a", 120), Self.song("b", 1)], from: 1),
                              list: nil, then: nil, repeatOne: true)
        #expect(QueueTimeLeft.words(view, position: 10) == "2 songs")
    }

    @Test func theLastSongAndNothingPlaying() {
        let last = UpNextView(playing: Self.song("now", 200), added: [], list: nil, then: "Nothing after this song.",
                              repeatOne: false)
        #expect(QueueTimeLeft.words(last, position: 20) == "3 min left")
        #expect(QueueTimeLeft.words(UpNextView(playing: nil, added: [], list: nil, then: nil, repeatOne: false), position: 0) == nil)
    }

    @Test func theSpeedTheSongsPlayAt() {
        let view = UpNextView(playing: Self.song("now", 600), added: [], list: nil, then: nil, repeatOne: false)
        #expect(QueueTimeLeft.words(view, position: 0, speed: 2) == "5 min left")
        #expect(QueueTimeLeft.words(view, position: 0, speed: 0) == "10 min left")
        #expect(QueueTimeLeft.words(view, position: 0, speed: .nan) == "10 min left")
    }

    /// (R3b's review) Never "0 min left" nor "over 0 min left": under a minute known is "under 1 min left", none left
    /// says no time at all; a least is rounded down - never more than is known - and under a whole minute says none.
    @Test func neverNoMinutesLeft() {
        let last = UpNextView(playing: Self.song("now", 200), added: [], list: nil, then: "Nothing after this song.",
                              repeatOne: false)
        #expect(QueueTimeLeft.words(last, position: 140) == "1 min left")
        #expect(QueueTimeLeft.words(last, position: 141) == "under 1 min left")
        #expect(QueueTimeLeft.words(last, position: 199.5) == "under 1 min left")
        #expect(QueueTimeLeft.words(last, position: 200) == nil)
        #expect(QueueTimeLeft.words(last, position: 999) == nil)
        // the songs still to come are said with no time once none is left of the song playing and they have none
        let unknown = UpNextView(playing: Self.song("now", 0), added: [], list: nil, then: nil, repeatOne: false)
        #expect(QueueTimeLeft.words(unknown, position: 0) == nil)
        let short = UpNextView(playing: Self.song("now", 0), added: Self.rows([Self.song("a", 50)], from: 1), list: nil,
                               then: nil, repeatOne: false)
        #expect(QueueTimeLeft.words(short, position: 0) == "1 song")
        let longer = UpNextView(playing: Self.song("now", 0), added: Self.rows([Self.song("a", 150)], from: 1), list: nil,
                                then: nil, repeatOne: false)
        // 2.5 minutes known: "over 2", never "over 3"
        #expect(QueueTimeLeft.words(longer, position: 0) == "1 song · over 2 min left")
        // a least's lower bound at the rounding's edge
        let undrawn = UpNextView(playing: Self.song("now", 100), added: [],
                                 list: UpNextList(title: "Still to play", rows: [], more: 5), then: nil, repeatOne: false)
        #expect(QueueTimeLeft.words(undrawn, position: 0) == "5 songs · over 1 min left")
        #expect(QueueTimeLeft.words(undrawn, position: 41) == "5 songs")
        // at every moment of a song, none of them is ever said as none
        for view in [last, short, undrawn] {
            for tenth in 0...2100 {
                let words = QueueTimeLeft.words(view, position: Double(tenth) / 10) ?? ""
                #expect(!words.hasPrefix("0 min") && !words.contains(" 0 min") && !words.contains("over 0"))
            }
        }
    }

    /// (R3b's review) Repeat All counts the rows still to come of the one round the list draws - the rest of the round
    /// playing, or at its last song the next round, "again" - never the rounds after: the queue holds them, the view
    /// says them as its `then` line, and the time is what is left of that round, not of the music.
    @Test func repeatAllCountsTheRoundDrawnOnly() {
        let all = toppedUp(startUpNext(simAlbum(3), start: 0).at(1), .all)
        #expect(all.after.count > 1)
        let view = upNextView(all, .all)
        #expect(view.list?.rows.map(\.track.id) == ["3"] && view.list?.more == 0)
        #expect(view.then == "Then Mezzanine again from the top.")
        // song 2, 200 s, 50 s in, then song 3: 350 s - one song, never the next round's three
        #expect(QueueTimeLeft.words(view, position: 50) == "1 song · 6 min left")
        // at the round's last song the list drawn is the next round, whole, and only it
        let end = toppedUp(all.at(2), .all)
        let again = upNextView(end, .all)
        #expect(end.after.count >= 3)
        #expect(again.list?.title == "From Mezzanine, again" && again.list?.rows.count == 3)
        #expect(QueueTimeLeft.words(again, position: 150) == "3 songs · 11 min left")
    }

    @Test func spansToTheMinuteRoundedUp() {
        #expect(QueueTimeLeft.span(0) == "0 min")
        #expect(QueueTimeLeft.span(1) == "1 min")
        #expect(QueueTimeLeft.span(60) == "1 min")
        #expect(QueueTimeLeft.span(61) == "2 min")
        #expect(QueueTimeLeft.span(3600) == "1 hr")
        #expect(QueueTimeLeft.span(4320) == "1 hr 12 min")
        #expect(QueueTimeLeft.span(.infinity) == "0 min")
    }

    @Test func theHeadings() {
        #expect(QueuePageWords.heading("From Wilco (The Album)") == "Next from Wilco (The Album)")
        #expect(QueuePageWords.heading("From Dummy, again") == "Next from Dummy, again")
        #expect(QueuePageWords.heading("Still to play") == "Still to play")
        #expect(QueuePageWords.heading(listTitle([Self.song("a", 1)], again: false)) == "Next from Wilco (The Album)")
    }

    @Test func rowsSayTheirAlbumOnlyWhereTheHeadingHasnt() {
        let one = Self.rows([Self.song("a", 1), Self.song("b", 1)], from: 0)
        #expect(!QueuePageWords.showsLines(one, title: "From Wilco (The Album)"))
        #expect(QueuePageWords.showsLines(one, title: "Still to play"))
        #expect(QueuePageWords.showsLines(one, title: UpNextWords.playingNext))
        let many = one + Self.rows([Self.song("c", 1, artist: "Feist")], from: 2)
        #expect(QueuePageWords.showsLines(many, title: "From Wilco (The Album)"))
    }
}

/// (R3b) Info's Played row: "19 times · today", the day only where the song's answer has a date.
@Suite struct InfoPlayedTests {
    static let utc = TimeZone(identifier: "UTC")!
    /// 25 Nov 2026, 12:00 UTC
    static let now: Int64 = AlbumTime.ms("2026-11-25T12:00:00Z")!
    static let track = AboutTrack(id: "s1", title: "One Wing", artist: "Wilco", album: "Wilco (The Album)", albumId: "al",
                                  coverArt: nil, duration: 221)

    static func played(_ details: SongDetails?, album: [SongDetails] = [], now: Int64 = now, zone: TimeZone = utc) -> String? {
        AboutCard.played(track: track, album: AboutAlbum(id: "al", name: "Wilco (The Album)", song: album),
                         details: AboutDetails(song: details), now: now, zone: zone)
    }

    @Test func timesAndTheDay() {
        #expect(Self.played(SongDetails(id: "s1", playCount: 19, played: "2026-11-25T09:14:03.117Z")) == "19 times · today")
        #expect(Self.played(SongDetails(id: "s1", playCount: 1, played: "2026-11-24T21:00:00Z")) == "once · yesterday")
        #expect(Self.played(SongDetails(id: "s1", playCount: 3, played: "2026-11-10T10:00:00Z")) == "3 times · 10 Nov")
    }

    /// A nil count is never said as 0, nor is a count of none; and a day is never said without a count.
    @Test func neverPlayedSaysNothing() {
        #expect(Self.played(SongDetails(id: "s1")) == nil)
        #expect(Self.played(SongDetails(id: "s1", played: "2026-11-25T09:00:00Z")) == nil)
        #expect(Self.played(SongDetails(id: "s1", playCount: 0, played: "2026-11-25T09:00:00Z")) == nil)
    }

    /// "today" only where the answer has a date: none, or one that can't be read, is the count alone.
    @Test func theDayOnlyWhereTheAnswerSaysWhen() {
        #expect(Self.played(SongDetails(id: "s1", playCount: 19)) == "19 times")
        #expect(Self.played(SongDetails(id: "s1", playCount: 19, played: "")) == "19 times")
        #expect(Self.played(SongDetails(id: "s1", playCount: 19, played: "not a date")) == "19 times")
    }

    /// The day moves at midnight: played at 23:30, it is "today" until midnight and "yesterday" after - in the
    /// device's zone, never UTC's.
    @Test func todayAcrossMidnight() {
        let late = SongDetails(id: "s1", playCount: 2, played: "2026-11-25T23:30:00Z")
        let beforeMidnight = AlbumTime.ms("2026-11-25T23:59:00Z")!
        let afterMidnight = AlbumTime.ms("2026-11-26T00:01:00Z")!
        #expect(Self.played(late, now: beforeMidnight) == "2 times · today")
        #expect(Self.played(late, now: afterMidnight) == "2 times · yesterday")
        // 23:30 UTC is 12:30 the next day in Auckland: today there, at both
        let auckland = TimeZone(identifier: "Pacific/Auckland")!
        #expect(Self.played(late, now: afterMidnight, zone: auckland) == "2 times · today")
    }

    /// The song as Navidrome has it now, else as it was when the album was played from - as About's own line counts.
    /// (R3b's review) The album's songs as Info has them live: AboutAlbum(album:) of the routes' Album, each song
    /// SongDetails(song:) of a Song - which has no `played`, so the album's fallback is the count alone, never a day.
    @Test func theFreshAnswerFirstThenTheAlbums() {
        let routes = Album(id: "al", name: "Wilco (The Album)", song: [Song(id: "s1", title: "One Wing", playCount: 4)])
        let kept = AboutAlbum(album: routes).song ?? []
        #expect(kept.map(\.played) == [nil] && kept.first?.playCount == 4)
        #expect(Self.played(nil, album: kept) == "4 times")
        // the fresh answer, as Info's ask decodes it (getSong, passed on as it is), carries the day
        let fresh = try? JSONDecoder().decode(SongDetails.self, from: Data(
            #"{"id":"s1","playCount":5,"played":"2026-11-25T10:00:00Z"}"#.utf8))
        #expect(Self.played(fresh, album: kept) == "5 times · today")
        // another song's answer is never this one's
        #expect(Self.played(SongDetails(id: "s2", playCount: 9), album: kept) == "4 times")
        // and Played agrees with About's own count
        let about = AboutCard.about(track: Self.track, album: AboutAlbum(id: "al", name: "x", song: kept),
                                    details: AboutDetails(song: SongDetails(id: "s1", playCount: 5)))
        #expect(about.song.lines.first?.contains("played 5 times") == true)
        #expect(Self.played(SongDetails(id: "s1", playCount: 5), album: kept) == "5 times")
    }

    /// iInfo's two cards, from the same answers as About's lines and in its words - each fact only where About says it.
    @Test func theFactsAsRows() {
        let songs = [SongDetails(id: "s1", track: 1, discNumber: 1, duration: 221, suffix: "flac", playCount: 18,
                                 displayComposer: "Jeff Tweedy"),
                     SongDetails(id: "s2", track: 2, discNumber: 1, duration: 206, suffix: "flac")]
        let album = AboutAlbum(id: "al", name: "Wilco (The Album)", year: 2009, song: songs,
                               recordLabels: [AboutAlbum.Label(name: "Nonesuch")])
        let present = [PressingRow(path: "Wilco/Wilco (The Album) (2009)", edition: "Deluxe", year: "2009", formats: ["flac"])]
        // (R3b's review) the day from the fresh answer (getSong's, the whole song as Navidrome has it now), as Info has
        // it live - the album's own songs never carry one; the file's size and bit rate the player's song's
        let fresh = SongDetails(id: "s1", track: 1, discNumber: 1, duration: 221, suffix: "flac", playCount: 19,
                                displayComposer: "Jeff Tweedy", played: "2026-11-25T09:14:03Z")
        let facts = AboutCard.facts(track: Self.track, album: album, details: AboutDetails(song: fresh, present: present),
                                    folders: true, size: 25_270_000, bitRate: 921, now: Self.now, zone: Self.utc)
        #expect(facts.song.map(\.label) == ["Track", "Length", "Size", "Played", "Written by"])
        #expect(facts.song.map(\.value) == ["1 of 2", "3:41", "24 MB · 921 kbps", "19 times · today", "Jeff Tweedy"])
        #expect(facts.song.first { $0.label == "Size" }?.mono == true)
        // the album's format is the song's Format row's (Sound's, whole), as iInfo has one Format
        #expect(facts.album.map(\.label) == ["Released", "Label", "Songs", "This pressing", "Folder"])
        #expect(facts.album.map(\.value) == ["2009", "Nonesuch", "2", "Deluxe · 2009 · FLAC", "Wilco/Wilco (The Album) (2009)"])
        #expect(facts.line == "Wilco (The Album) · 2009")
        // an ordinary person sees no folder; a song never played no Played
        let theirs = AboutCard.facts(track: Self.track, album: AboutAlbum(id: "al", name: "x", song: [SongDetails(id: "s1")]),
                                     details: AboutDetails(present: present), now: Self.now, zone: Self.utc)
        #expect(!theirs.album.map(\.label).contains("Folder") && !theirs.song.map(\.label).contains("Played"))
        // About's own lines are as they were
        let about = AboutCard.about(track: Self.track, album: album, details: AboutDetails(song: fresh, present: present),
                                    folders: true)
        #expect(about.song.lines.first == "Track 1 of 2 · 3:41 · played 19 times")
        // no size or bit rate known, no Size row
        #expect(!AboutCard.facts(track: Self.track, album: album, now: Self.now).song.map(\.label).contains("Size"))
        #expect(!AboutCard.facts(track: Self.track, album: album, size: 0, bitRate: 0, now: Self.now).song.map(\.label)
            .contains("Size"))
    }

    /// (R3b's review) Size's value: the size in the web's words (Sources.size) and the bit rate Navidrome gives, in kbps -
    /// either alone, nothing for neither.
    @Test func theSizeRow() {
        #expect(AboutCard.sizeLine(size: 25_270_000, bitRate: 921) == "24 MB · 921 kbps")
        #expect(AboutCard.sizeLine(size: 25_270_000, bitRate: nil) == "24 MB")
        #expect(AboutCard.sizeLine(size: nil, bitRate: 320) == "320 kbps")
        #expect(AboutCard.sizeLine(size: 1_300_000_000, bitRate: 0) == "1.2 GB")
        #expect(AboutCard.sizeLine(size: nil, bitRate: nil) == "")
        #expect(AboutCard.sizeLine(size: 0, bitRate: -1) == "")
        #expect(AboutFactWords.size == "Size")
    }

    /// Go to artist: the song's own artist - as Navidrome has it now, else as its album had it - else the album's, only
    /// where that is the song's; none known, no way to go.
    @Test func whichArtistGoToArtistOpens() {
        func id(_ fresh: SongDetails?, album: AboutAlbum?) -> String? {
            AboutCard.facts(track: Self.track, album: album, details: AboutDetails(song: fresh), now: Self.now, zone: Self.utc).artistID
        }
        let kept = [SongDetails(id: "s1", artistId: "ar-kept")]
        let album = AboutAlbum(id: "al", name: "Wilco (The Album)", artist: "Wilco", song: kept, artistId: "ar-album")
        #expect(id(SongDetails(id: "s1", artistId: "ar-fresh"), album: album) == "ar-fresh")
        #expect(id(nil, album: album) == "ar-kept")
        let bare = AboutAlbum(id: "al", name: "Wilco (The Album)", artist: "Wilco", song: [SongDetails(id: "s1")], artistId: "ar-album")
        #expect(id(nil, album: bare) == "ar-album")
        // a compilation's artist is never the song's
        let various = AboutAlbum(id: "al", name: "Mix", artist: "Various Artists", song: [SongDetails(id: "s1")], artistId: "ar-va")
        #expect(id(nil, album: various) == nil)
        #expect(id(SongDetails(id: "s1", artistId: "  "), album: nil) == nil)
        // the line: the album and its year, or what is known of them
        #expect(AboutCard.facts(track: Self.track, album: nil, now: Self.now).line == "Wilco (The Album)")
    }

    @Test func navidromesPlayedIsRead() throws {
        let json = #"{"id":"s1","playCount":19,"played":"2026-11-25T09:14:03.117Z"}"#
        let song = try JSONDecoder().decode(SongDetails.self, from: Data(json.utf8))
        #expect(song.played == "2026-11-25T09:14:03.117Z" && song.playCount == 19)
        let none = try JSONDecoder().decode(SongDetails.self, from: Data(#"{"id":"s1","played":7}"#.utf8))
        #expect(none.played == nil)
    }
}
