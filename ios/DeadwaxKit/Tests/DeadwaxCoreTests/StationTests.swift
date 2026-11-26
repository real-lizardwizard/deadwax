import Foundation
import Testing
@testable import DeadwaxCore

// (Last.fm, slice A3 - deadwax-plans/lastfm.md 3.5) A station: the ask, its tries, what an answer makes, the songs it
// hands the queue, when the queue wants more, and which of the Queue's rows are Autoplay's.

/// A song of a station's answer, as the radio route passes it on (Navidrome's song).
func radioSong(_ id: String, title: String? = nil, artist: String = "Tame Impala", album: String = "Currents",
               albumId: String = "cur") -> Song {
    Song(id: id, title: title ?? "radio \(id)", album: album, albumId: albumId, artist: artist, duration: 200,
         suffix: "flac", contentType: "audio/flac", samplingRate: 44100, bitDepth: 16, channelCount: 2)
}

/// Songs "r1"..."rN".
func radioSongs(_ count: Int, _ prefix: String = "r") -> [Song] {
    (0..<count).map { radioSong("\(prefix)\($0 + 1)") }
}

/// The songs as the queue takes them (PlaylistPlay's, each with its own album).
func stationTracks(_ songs: [Song]) -> [QueueTrack] {
    songs.map { PlaylistPlay.track($0, level: nil) }
}

/// An album of `count` played from `start`, as a queue of id "q1".
func stationQueue(_ count: Int = 3, start: Int = 0) -> UpNextQueue {
    startUpNext(simAlbum(count), start: start, id: "q1")
}

/// A station with its answer in.
func answered(_ kind: Station.Kind, _ queue: UpNextQueue, _ songs: [Song]?) -> Station {
    var station = (kind == .radio ? Station.radio(queue) : Station.autoplay(queue))!
    station.began()
    station.answered(LastfmRadio(songs: songs), playing: queue.index, now: 0)
    return station
}

@Suite struct StationAskTests {
    @Test func theAskIsTheSongsIdTitleAndArtistTrimmed() throws {
        let ask = try #require(Station.Ask(songId: "so-1", title: "  Roads ", artist: "\tPortishead\n"))
        #expect(ask == Station.Ask(songId: "so-1", title: "Roads", artist: "Portishead"))
        // a song without one of them, or with one longer than the route takes, has no ask
        #expect(Station.Ask(songId: "", title: "Roads", artist: "Portishead") == nil)
        #expect(Station.Ask(songId: "so-1", title: "  ", artist: "Portishead") == nil)
        #expect(Station.Ask(songId: "so-1", title: "Roads", artist: "") == nil)
        let id = String(repeating: "a", count: Station.Ask.idMost)
        #expect(Station.Ask(songId: id, title: "Roads", artist: "Portishead") != nil)
        #expect(Station.Ask(songId: id + "a", title: "Roads", artist: "Portishead") == nil)
        let words = String(repeating: "é", count: Station.Ask.wordsMost)
        #expect(Station.Ask(songId: "so-1", title: words, artist: words) != nil)
        #expect(Station.Ask(songId: "so-1", title: words + "é", artist: "Portishead") == nil)
        #expect(Station.Ask(songId: "so-1", title: "Roads", artist: words + "é") == nil)
    }

    @Test func startRadiosSeedIsTheSongPlayingAndAutoplaysTheQueuesLast() throws {
        let queue = stationQueue(3, start: 1)
        let radio = try #require(Station.radio(queue))
        #expect(radio.kind == .radio && radio.seed.id == "2" && radio.queueId == "q1")
        let autoplay = try #require(Station.autoplay(queue))
        #expect(autoplay.kind == .autoplay && autoplay.seed.id == "3" && autoplay.queueId == "q1")
        #expect(radio.songs == nil && radio.asks == 0 && !radio.asking && radio.failure == nil)
        // a queue without Up Next's account, or with nothing in it, has none
        #expect(Station.radio(.empty) == nil && Station.autoplay(.empty) == nil)
        #expect(Station.radio(UpNextQueue(tracks: simAlbum(2), index: 0)) == nil)
        #expect(Station.autoplay(UpNextQueue(tracks: simAlbum(2), index: 0)) == nil)
    }

    @Test func itIsAskedThreeTimesAtMostAndAgainOnlyLater() {
        var station = Station(kind: .radio, seed: simTrack("1"), queueId: "q1")
        #expect(station.mayAsk(playing: 0, now: 0) && station.againAt == nil)
        station.began()
        // one ask out at a time
        #expect(station.asking && station.asks == 1 && !station.mayAsk(playing: 0, now: 0))
        #expect(station.answered(nil, playing: 0, now: 10) == .failed)
        #expect(station.failure == Station.Failure(entry: 0, at: 10) && !station.exhausted)
        // the same song playing: again after 30 s; another song: at once
        #expect(!station.mayAsk(playing: 0, now: 39.9) && station.mayAsk(playing: 0, now: 40))
        #expect(station.mayAsk(playing: 1, now: 11))
        #expect(station.againAt == 40)
        station.began()
        #expect(station.againAt == nil)
        station.answered(LastfmRadio(unavailable: true, songs: nil), playing: 1, now: 20)
        #expect(station.mayAsk(playing: 2, now: 21))
        station.began()
        station.answered(nil, playing: 2, now: 30)
        // three tries made: no more, and nothing more will come of it
        #expect(station.asks == Station.tries && !station.mayAsk(playing: 3, now: 1000) && station.againAt == nil)
        #expect(station.exhausted)
    }

    @Test func aSeedWithoutAnAskIsNeverAsked() {
        let blank = QueueTrack(id: "so-1", title: "  ", artist: "Portishead", album: "Dummy", albumId: nil, coverArt: nil,
                               duration: 200, contentType: nil, suffix: nil, sampleRate: 0, bitDepth: 0, channels: 0)
        let station = Station(kind: .autoplay, seed: blank, queueId: "q1")
        #expect(station.ask == nil && !station.mayAsk(playing: 0, now: 0) && station.exhausted)
    }

    @Test func anAnswerIsSongsANothingOrAFailure() {
        var station = Station(kind: .radio, seed: simTrack("1"), queueId: "q1")
        station.began()
        #expect(station.answered(LastfmRadio(songs: radioSongs(150)), playing: 0, now: 0) == .songs)
        // a hundred at most kept; asked no more
        #expect(station.songs?.count == Station.most && station.songs?.last?.id == "r100")
        #expect(!station.asking && !station.mayAsk(playing: 1, now: 1000) && station.failure == nil)
        var none = Station(kind: .radio, seed: simTrack("1"), queueId: "q1")
        none.began()
        #expect(none.answered(LastfmRadio(songs: []), playing: 0, now: 0) == .nothing)
        #expect(none.songs == [] && none.exhausted && !none.mayAsk(playing: 0, now: 1000))
        // songs null - unavailable, refused or no key - is a failure, asked again by the rule
        var down = Station(kind: .radio, seed: simTrack("1"), queueId: "q1")
        down.began()
        #expect(down.answered(LastfmRadio(unavailable: true, songs: nil), playing: 0, now: 0) == .failed)
        #expect(down.songs == nil && !down.exhausted)
    }

    @Test func autoplayIsOffUntilTurnedOn() {
        #expect(Autoplay.storageKey == "deadwax-player-autoplay")
        #expect(!Autoplay.read(nil))
        for word in ["", "off", "On", "ON", "true", "1", "yes", " on"] { #expect(!Autoplay.read(word), "\(word)") }
        #expect(Autoplay.read("on"))
        #expect(Autoplay.stored(true) == "on" && Autoplay.stored(false) == "off")
        #expect(Autoplay.read(Autoplay.stored(true)) && !Autoplay.read(Autoplay.stored(false)))
    }
}

@Suite struct StationTakeTests {
    @Test func tenAtATimeFromWhereTheLastTakeStopped() throws {
        let queue = stationQueue(3)
        var station = answered(.radio, queue, radioSongs(25))
        #expect(station.take(queue).map(\.id) == (1...10).map { "r\($0)" })
        #expect(station.next == 10 && !station.exhausted)
        #expect(station.take(queue).map(\.id) == (11...20).map { "r\($0)" })
        #expect(station.take(queue).map(\.id) == (21...25).map { "r\($0)" })
        #expect(station.exhausted && station.take(queue).isEmpty)
        // a radio notes nothing for a heading: its songs are the list itself
        #expect(station.added.isEmpty && station.floor == nil)
        // nothing taken before an answer
        var waiting = try #require(Station.radio(queue))
        #expect(waiting.take(queue).isEmpty && waiting.next == 0)
    }

    @Test func neverASongTheQueueHasNorTheSeed() {
        // the queue's 1, 2 and 3 ("song N" by Massive Attack), 1 playing - the seed
        let queue = stationQueue(3)
        let songs = [
            radioSong("2", title: "song 2", artist: "Massive Attack"),         // the queue's, by id
            radioSong("x1", title: "Song 3 (2011 Remaster)", artist: "MASSIVE ATTACK"), // the queue's, by title and artist
            radioSong("1"),                                                    // the seed's id
            radioSong("x2", title: "song 1", artist: "Massive Attack"),        // the seed's title and artist
            radioSong("y1", title: "song 3", artist: "Portishead"),            // another artist's song of that title
            radioSong("y2"), radioSong("y2"),                                  // one song twice in an answer
            radioSong("y3", title: "radio y2"),                                // the same title and artist as y2
            radioSong("y4", title: "  "),                                      // no title: told apart by its id
            radioSong("y5", title: "  "),
        ]
        var station = answered(.radio, queue, songs)
        #expect(station.take(queue).map(\.id) == ["y1", "y2", "y4", "y5"])
        #expect(station.exhausted)
    }

    @Test func twoSongsOfOneIdAreOneSong() {
        // (A3's review) the same id twice in an answer, under two titles: taken once
        var station = answered(.radio, stationQueue(3), [radioSong("d", title: "one"), radioSong("d", title: "two"),
                                                         radioSong("e")])
        #expect(station.take(stationQueue(3)).map(\.id) == ["d", "e"])
    }

    @Test func theSeedIsPassedEvenWhenTheQueueNoLongerHasIt() {
        let seed = simTrack("s")
        var station = Station(kind: .radio, seed: seed, queueId: "q1")
        station.began()
        station.answered(LastfmRadio(songs: [radioSong("s"), radioSong("z", title: "song s", artist: "Massive Attack"),
                                             radioSong("r1")]), playing: 0, now: 0)
        #expect(station.take(stationQueue(3)).map(\.id) == ["r1"])
    }

    @Test func historysSongsCountAsTheQueues() {
        // 1 and 2 played (History), 3 playing
        let queue = stationQueue(3, start: 2)
        var station = Station(kind: .radio, seed: simTrack("3"), queueId: "q1")
        station.began()
        station.answered(LastfmRadio(songs: [radioSong("1"), radioSong("2"), radioSong("r1")]), playing: 2, now: 0)
        #expect(station.take(queue).map(\.id) == ["r1"])
    }

    @Test func offlineOnlySongsOnTheDeviceAndTheRestKeptForLater() {
        let queue = stationQueue(3)
        var station = answered(.radio, queue, radioSongs(14))
        let here: (String) -> Bool = { !["r2", "r5"].contains($0) }
        #expect(station.take(queue, here: here).map(\.id) == ["r1", "r3", "r4", "r6", "r7", "r8", "r9", "r10", "r11",
                                                              "r12"])
        // (A3's review) passed only for not being on the device: kept for later, looked at first - back online, taken
        #expect(station.later.map(\.id) == ["r2", "r5"] && station.next == 12)
        #expect(station.take(queue).map(\.id) == ["r2", "r5", "r13", "r14"])
        #expect(station.later.isEmpty && station.exhausted)
    }

    @Test func oneOfflineTopUpNeverUsesTheAnswerUp() {
        // a hundred songs, two of them on the device: the offline take looks at all of them, takes the two, and keeps
        // the rest for later - not exhausted, so back online the next take is ten of them
        let queue = stationQueue(3)
        var station = answered(.autoplay, queue, radioSongs(100))
        let offline = station.take(queue) { ["r40", "r90"].contains($0) }
        #expect(offline.map(\.id) == ["r40", "r90"] && station.next == 100)
        #expect(station.later.count == 98 && !station.exhausted)
        // still offline, and nothing more on the device: nothing, and all still kept
        #expect(station.take(queue) { _ in false }.isEmpty && station.later.count == 98 && !station.exhausted)
        let grown = withStation(queue, stationTracks(offline), .off)
        #expect(station.take(grown).map(\.id) == (1...10).map { "r\($0)" })
        #expect(station.later.count == 88 && station.later.first?.id == "r11" && !station.exhausted)
        // a song kept for later that the queue has since got is passed for good
        var again = answered(.radio, queue, [radioSong("x"), radioSong("y")])
        _ = again.take(queue) { _ in false }
        #expect(again.later.map(\.id) == ["x", "y"])
        let has = withStation(queue, stationTracks([radioSong("x")]), .off)
        #expect(again.take(has).map(\.id) == ["y"] && again.later.isEmpty && again.exhausted)
    }

    @Test func aSongTakenOutOfTheQueueIsntAddedBack() throws {
        var queue = stationQueue(3)
        var station = answered(.radio, queue, radioSongs(15))
        queue = withStation(queue, stationTracks(station.take(queue)), .off)
        let key = try #require(queue.key("r4"))
        queue = withoutKey(queue, key)
        #expect(!queue.ids.contains("r4"))
        #expect(station.take(queue).map(\.id) == ["r11", "r12", "r13", "r14", "r15"])
    }

    @Test func autoplayNotesWhatItGaveForTheHeading() throws {
        let queue = stationQueue(3)
        var station = answered(.autoplay, queue, radioSongs(12))
        #expect(station.seed.id == "3")
        #expect(!station.inList)
        let first = station.take(queue)
        #expect(station.floor == queue.upNext?.nextKey && station.floor == 3)
        // (A3's review) where its songs begin in the list's source, for turning Autoplay off
        #expect(station.start == queue.upNext?.source.count && station.start == 3)
        #expect(station.added == Set(first.map(\.id)) && station.inList)
        let more = withStation(queue, stationTracks(first), .off)
        let rest = station.take(more)
        // the floor and the start stay where Autoplay first gave
        #expect(station.floor == 3 && station.start == 3 && station.added == Set((first + rest).map(\.id)))
        // a take of nothing notes nothing
        var empty = answered(.autoplay, queue, [])
        #expect(empty.take(queue).isEmpty && empty.floor == nil && empty.start == nil && empty.added.isEmpty)
        #expect(!empty.inList)
        // a radio's songs are the list itself: in it from the start, nothing noted
        var radio = answered(.radio, queue, radioSongs(3))
        #expect(radio.inList)
        _ = radio.take(queue)
        #expect(radio.start == nil && radio.floor == nil)
    }
}

@Suite struct StationTopUpTests {
    /// A station of the queue's own.
    static func own(_ queue: UpNextQueue) -> Station { Station(kind: .radio, seed: queue.current!, queueId: "q1") }

    @Test func theQueueWantsMoreWithTwoOrFewerToCome() {
        let station = Self.own(stationQueue(4))
        // four songs, the first playing: three to come
        #expect(!Station.wantsMore(stationQueue(4), mode: .off, lastfm: true, station: station, autoplay: false))
        // three, the first playing: two
        #expect(Station.wantsMore(stationQueue(3), mode: .off, lastfm: true, station: Self.own(stationQueue(3)),
                                  autoplay: false))
        #expect(Station.wantsMore(stationQueue(4, start: 1), mode: .off, lastfm: true, station: station, autoplay: false))
        #expect(Station.wantsMore(stationQueue(4, start: 3), mode: .off, lastfm: true, station: station, autoplay: false))
        #expect(Station.following(stationQueue(4)) == 3 && Station.following(stationQueue(4, start: 3)) == 0)
    }

    @Test func eachGuardHoldsItBack() {
        let queue = stationQueue(3)
        let station = Self.own(queue)
        #expect(Station.wantsMore(queue, mode: .off, lastfm: true, station: nil, autoplay: true))
        // Last.fm off
        #expect(!Station.wantsMore(queue, mode: .off, lastfm: false, station: station, autoplay: true))
        // Repeat All or One
        #expect(!Station.wantsMore(queue, mode: .all, lastfm: true, station: station, autoplay: true))
        #expect(!Station.wantsMore(queue, mode: .one, lastfm: true, station: station, autoplay: true))
        // Autoplay off and no station of this queue's
        #expect(!Station.wantsMore(queue, mode: .off, lastfm: true, station: nil, autoplay: false))
        let other = Station(kind: .radio, seed: simTrack("1"), queueId: "q2")
        #expect(!Station.wantsMore(queue, mode: .off, lastfm: true, station: other, autoplay: false))
        // a library's shuffle: its feed tops it up
        let paged = startUpNext(simAlbum(3), start: 0,
                                paged: Paged(token: "t", total: 3, fetched: 3, scope: .yours, level: nil), id: "q1")
        #expect(!Station.wantsMore(paged, mode: .off, lastfm: true, station: station, autoplay: true))
        // nothing playing, or no Up Next's account
        #expect(!Station.wantsMore(.empty, mode: .off, lastfm: true, station: station, autoplay: true))
        #expect(!Station.wantsMore(UpNextQueue(tracks: simAlbum(3), index: 0), mode: .off, lastfm: true, station: station,
                                   autoplay: true))
        var ended = queue
        ended.index = 3
        #expect(!Station.wantsMore(ended, mode: .off, lastfm: true, station: station, autoplay: true))
    }

    @Test func repeatOnesCopiesDontCountAndEveryOtherEntryDoes() throws {
        // Repeat One's copies after the song playing: not songs to come
        let one = toppedUp(stationQueue(3), .one)
        #expect(one.froms.contains("o"))
        #expect(Station.following(one) == 2)
        // songs added count
        let added = withNext(stationQueue(3), [simTrack("a")])
        #expect(Station.following(added) == 3)
        // (A3's review) a later time round's songs count: the top-up is asked only under Repeat Off, where they play
        let all = toppedUp(stationQueue(2), .all)
        #expect(all.froms == ["s0", "s1", "s1"])
        #expect(Station.following(all) == 3)
    }

    @Test func aRollBackAcrossRoundsCountsWhatItMovedBackDown() throws {
        // Repeat All's second time round playing, rolled back to the first round's song 2, then Repeat turned off: the
        // songs moved back down - the rest of the first round and the second's - all play, so all count
        var queue = toppedUp(stationQueue(3), .all).at(2)
        queue = toppedUp(queue, .all).at(4)
        #expect(queue.ids == ["1", "2", "3", "1", "2", "3"] && queue.index == 4)
        let two = try #require(queue.upNext?.marks[1].key)
        let jump = try #require(jumpedTo(queue, two, .all))
        #expect(jump.back && jump.index == 1)
        // Repeat off keeps every round up to the furthest song played
        let off = withRepeat(jump.queue, .off)
        #expect(off.ids == ["1", "2", "3", "1", "2", "3"] && off.index == 1 && off.froms == ["s0", "s1", "s1", "s1"])
        #expect(Station.following(off) == 4)
        // so with four to come, the top-up isn't asked yet - before the review one was counted, and it was
        let station = Station(kind: .radio, seed: try #require(off.current), queueId: "q1")
        #expect(!Station.wantsMore(off, mode: .off, lastfm: true, station: station, autoplay: false))
        #expect(!Station.wantsMore(off.at(2), mode: .off, lastfm: true, station: station, autoplay: false))
        #expect(Station.wantsMore(off.at(3), mode: .off, lastfm: true, station: station, autoplay: false))
    }

    @Test func autoplaysRowsAreTheListsTailUnderItsOwnHeading() throws {
        var queue = stationQueue(3)
        var station = answered(.autoplay, queue, radioSongs(3))
        queue = withStation(queue, stationTracks(station.take(queue)), .off)
        let view = upNextView(queue, .off)
        let whole = try #require(view.list)
        #expect(whole.rows.map(\.track.id) == ["2", "3", "r1", "r2", "r3"])
        let split = Station.split(whole, queue, station)
        // the list's own rows under its own title - the album's, not "Still to play" for Currents' songs beside it
        #expect(split.list == UpNextList(title: "From Mezzanine", rows: Array(whole.rows.prefix(2)), more: 0))
        #expect(whole.title == "Still to play")
        #expect(split.autoplay.map(\.track.id) == ["r1", "r2", "r3"])
        // turning Autoplay off takes out exactly these rows
        let start = try #require(station.start)
        #expect(withoutStation(queue, from: start).ids == ["1", "2", "3"])
        // a row moved up out of the tail is drawn in the list
        let moved = movedKey(queue, try #require(queue.key("r2")), to: 0)
        let after = Station.split(upNextView(moved, .off).list, moved, station)
        #expect(after.list?.rows.map(\.track.id) == ["r2", "2", "3"])
        #expect(after.autoplay.map(\.track.id) == ["r1", "r3"])
        // the last of the list's own playing: every row Autoplay's, no list heading
        let last = queue.at(2)
        let all = Station.split(upNextView(last, .off).list, last, station)
        #expect(all.list == nil && all.autoplay.map(\.track.id) == ["r1", "r2", "r3"])
        // Autoplay's song playing: not one of the rows to take out
        #expect(withoutStation(queue.at(3), from: start).ids == ["1", "2", "3", "r1"])
    }

    @Test func nothingIsSplitButAutoplaysOwnDrawnWhole() throws {
        var queue = stationQueue(3)
        var station = answered(.autoplay, queue, radioSongs(3))
        queue = withStation(queue, stationTracks(station.take(queue)), .off)
        let whole = upNextView(queue, .off).list
        // a radio's songs are the list itself
        var radio = answered(.radio, stationQueue(3), radioSongs(3))
        let radioQueue = withStation(stationQueue(3), stationTracks(radio.take(stationQueue(3))), .off)
        let radioList = upNextView(radioQueue, .off).list
        #expect(Station.split(radioList, radioQueue, radio).autoplay.isEmpty)
        #expect(Station.split(radioList, radioQueue, radio).list == radioList)
        #expect(radio.start == nil)
        // another queue's station
        var other = queue
        other.upNext?.id = "q2"
        #expect(Station.split(whole, other, station).list == whole && Station.split(whole, other, station).autoplay.isEmpty)
        // no station, or no list
        #expect(Station.split(whole, queue, nil).list == whole && Station.split(nil, queue, station).list == nil)
        // a list with more than is drawn: its tail isn't drawn, so none of it is Autoplay's here
        let short = upNextView(queue, .off, limit: 3).list
        #expect(short?.more == 2)
        #expect(Station.split(short, queue, station).list == short && Station.split(short, queue, station).autoplay.isEmpty)
        // an Autoplay station that has given this queue nothing has no rows
        let fresh = Station(kind: .autoplay, seed: simTrack("3"), queueId: "q1")
        #expect(Station.split(whole, queue, fresh).autoplay.isEmpty && fresh.start == nil)
        // the list's own songs, played again by Play Next after Autoplay's floor, aren't Autoplay's: Autoplay off keeps
        // them
        let again = withLast(queue, [simTrack("2")])
        let off = withoutStation(again, from: try #require(station.start))
        #expect(off.ids == ["1", "2", "2", "3"] && off.key("2", from: .added) == again.key("2", from: .added))
    }
}
