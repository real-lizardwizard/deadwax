import Foundation
import Testing
@testable import DeadwaxCore

// (Last.fm, slice A3) withStation - a station's songs at the end of this time round's list, as the list's own - and
// QueueController.appendStation, the edit that makes it: marks and tracks in step, keys unique, the source counted
// right, nothing that was there moved, and the same queue for each guard. UpNext's web-traced vectors (UpNextTests,
// UpNextTraceTests, UpNextPropertyTests) run as they were: no existing function changed.

/// The invariants every Up Next queue keeps, checked of one a station grew.
func expectSound(_ queue: UpNextQueue, sourceLocation: SourceLocation = #_sourceLocation) {
    guard let state = queue.upNext else {
        Issue.record("no Up Next account", sourceLocation: sourceLocation)
        return
    }
    #expect(state.marks.count == queue.tracks.count, sourceLocation: sourceLocation)
    #expect(Set(state.marks.map(\.key)).count == state.marks.count, sourceLocation: sourceLocation)
    #expect(state.marks.allSatisfy { $0.key < state.nextKey }, sourceLocation: sourceLocation)
    for (place, mark) in state.marks.enumerated() where mark.from == .source {
        #expect(state.source.indices.contains(mark.at), sourceLocation: sourceLocation)
        #expect(state.source[mark.at] == queue.tracks[place], sourceLocation: sourceLocation)
    }
    // pass never goes down along the queue
    let passes = state.marks.filter { $0.from == .source }.map(\.pass)
    #expect(passes == passes.sorted(), sourceLocation: sourceLocation)
}

@Suite struct WithStationTests {
    @Test func theSongsJoinTheEndOfTheListAsItsOwn() throws {
        let queue = stationQueue(3)
        let songs = stationTracks(radioSongs(2))
        let grown = withStation(queue, songs, .off)
        #expect(grown.ids == ["1", "2", "3", "r1", "r2"] && grown.index == 0)
        let state = try #require(grown.upNext)
        let was = try #require(queue.upNext)
        #expect(state.marks.suffix(2) == [Mark(key: 3, from: .source, at: 3, pass: 0),
                                          Mark(key: 4, from: .source, at: 4, pass: 0)])
        #expect(state.source == was.source + songs && state.nextKey == 5)
        // nothing that was there moved
        #expect(Array(state.marks.prefix(3)) == was.marks && Array(grown.tracks.prefix(3)) == queue.tracks)
        #expect(state.id == was.id && state.shuffle == was.shuffle && state.startedAt == was.startedAt
            && state.left == was.left && state.paged == was.paged && state.reached == was.reached)
        expectSound(grown)
        // twice: keys still unique, the source counted on
        let again = withStation(grown, stationTracks([radioSong("r3")]), .off)
        #expect(again.ids.suffix(1) == ["r3"] && again.upNext?.marks.last == Mark(key: 5, from: .source, at: 5, pass: 0))
        expectSound(again)
        // Up Next draws them as the list's
        #expect(upNextView(again, .off).list?.rows.map(\.track.id) == ["2", "3", "r1", "r2", "r3"])
    }

    @Test func afterSongsAddedAndTheListsOwn() {
        let added = withNext(stationQueue(3), [simTrack("a")])
        let grown = withStation(added, stationTracks(radioSongs(2)), .off)
        #expect(grown.ids == ["1", "a", "2", "3", "r1", "r2"] && grown.froms == ["a", "s0", "s0", "s0", "s0"])
        expectSound(grown)
        let view = upNextView(grown, .off)
        #expect(view.added.map(\.track.id) == ["a"] && view.list?.rows.map(\.track.id) == ["2", "3", "r1", "r2"])
    }

    @Test func aShuffledListsLastRoundKeepsItsPass() throws {
        // Repeat All's rounds queued, then Repeat turned off while the second round plays: the songs join the round
        // of the list's last song, never a lower one
        let all = toppedUp(stationQueue(2), .all)
        let last = try #require(all.upNext?.marks.last(where: { $0.from == .source }))
        #expect(last.pass >= 1)
        let grown = withStation(all.at(2), stationTracks(radioSongs(1)), .off)
        #expect(grown.upNext?.marks.last?.pass == last.pass)
        expectSound(grown)
    }

    @Test func theSameQueueForEachGuard() {
        let queue = stationQueue(3)
        let songs = stationTracks(radioSongs(2))
        // Repeat All or One
        #expect(withStation(queue, songs, .all) == queue)
        #expect(withStation(queue, songs, .one) == queue)
        // no songs
        #expect(withStation(queue, [], .off) == queue)
        // nothing queued, or no Up Next's account
        #expect(withStation(.empty, songs, .off) == .empty)
        let plain = UpNextQueue(tracks: simAlbum(3), index: 0)
        #expect(withStation(plain, songs, .off) == plain)
        // nothing playing
        var ended = queue
        ended.index = 3
        #expect(withStation(ended, songs, .off) == ended)
        // a library's shuffle: its feed appends there
        let paged = startUpNext(simAlbum(3), start: 0,
                                paged: Paged(token: "t", total: 9, fetched: 3, scope: .yours, level: nil), id: "q1")
        #expect(withStation(paged, songs, .off) == paged)
    }
}

/// (A3's review) Autoplay turned off: withoutStation takes its songs out of the queue AND the list's source, so the
/// queue is as it was before Autoplay added anything - its heading, Repeat All's line and its next time round.
@Suite struct WithoutStationTests {
    /// Song 2 of Mezzanine's 3 playing, Autoplay's r1-r3 after it - the source's 3, 4 and 5.
    static func grown() -> UpNextQueue {
        withStation(stationQueue(3, start: 1), stationTracks(radioSongs(3)), .off)
    }

    @Test func theQueueAsItWasBeforeAutoplayAddedAnything() throws {
        let base = stationQueue(3, start: 1)
        let grown = Self.grown()
        let off = withoutStation(grown, from: 3)
        expectSound(off)
        #expect(off.ids == base.ids && off.index == base.index)
        let was = try #require(base.upNext)
        let now = try #require(off.upNext)
        #expect(now.marks == was.marks && now.source == was.source && now.left == was.left && now.reached == was.reached)
        #expect(now.id == was.id && now.shuffle == was.shuffle && now.startedAt == was.startedAt)
        // keys are never used twice
        #expect(now.nextKey == 6)
        // the heading: the album's again
        #expect(upNextView(off, .off) == upNextView(base, .off))
        #expect(upNextView(off, .off).list?.title == "From Mezzanine")
        // Repeat All's line names the album
        #expect(upNextView(off, .all).then == upNextView(base, .all).then)
        #expect(upNextView(off, .all).then == "Then Mezzanine again from the top.")
        // and Repeat All turned on at the last song queues the album's next time round, not Autoplay's songs with it
        let round = toppedUp(withRepeat(off.at(2), .all), .all)
        #expect(round.ids == toppedUp(withRepeat(base.at(2), .all), .all).ids)
        #expect(round.ids == ["1", "2", "3", "1", "2", "3"] && round.froms == ["s1", "s1", "s1"])
        // what the review found: the rows alone taken out, as before, left the songs in the source
        var rowsOnly = grown
        for id in ["r1", "r2", "r3"] { rowsOnly = withoutKey(rowsOnly, try #require(rowsOnly.key(id))) }
        #expect(upNextView(rowsOnly, .off).list?.title == "Still to play")
        #expect(upNextView(rowsOnly, .all).then == "Then the list again from the top.")
        #expect(toppedUp(withRepeat(rowsOnly.at(2), .all), .all).ids == ["1", "2", "3", "1", "2", "3", "r1", "r2", "r3"])
    }

    @Test func autoplaysSongPlayingStaysAndSoDoItsCopies() throws {
        // r1 playing under Repeat One, its copies after it
        let one = toppedUp(Self.grown().at(3), .one)
        #expect(one.ids == ["1", "2", "3", "r1", "r1", "r1", "r2", "r3"])
        let off = withoutStation(one, from: 3)
        expectSound(off)
        #expect(off.ids == ["1", "2", "3", "r1", "r1", "r1"] && off.index == 3)
        // the song playing keeps its place in the source; the ones to come go
        #expect(off.upNext?.source.map(\.id) == ["1", "2", "3", "r1"])
        // nothing at or before the song playing changed
        let was = try #require(one.upNext)
        let now = try #require(off.upNext)
        #expect(Array(now.marks.prefix(4)) == Array(was.marks.prefix(4)) && Array(off.tracks.prefix(4)) == Array(one.tracks.prefix(4)))
    }

    @Test func repeatAllsLaterRoundsLoseThemToo() throws {
        // Repeat All turned on keeps Autoplay's rows - queued songs then - and its next time round has them; turned off
        // later, Autoplay's songs go from every round
        let all = toppedUp(withRepeat(Self.grown().at(4), .all), .all)
        #expect(all.ids == ["1", "2", "3", "r1", "r2", "r3", "1", "2", "3", "r1", "r2", "r3"])
        let off = withoutStation(all, from: 3)
        expectSound(off)
        #expect(off.ids == ["1", "2", "3", "r1", "r2", "1", "2", "3"] && off.froms == ["s1", "s1", "s1"])
        // r1 played and r2 playing keep their places in the source; r3 goes
        #expect(off.upNext?.source.map(\.id) == ["1", "2", "3", "r1", "r2"])
    }

    @Test func rowsTakenOutBeforeGoFromTheSourceToo() throws {
        let grown = Self.grown()
        let swiped = withoutKey(grown, try #require(grown.key("r2")))
        #expect(swiped.upNext?.left == [LeftOut(pass: 0, at: 4)])
        let off = withoutStation(swiped, from: 3)
        expectSound(off)
        #expect(off.ids == ["1", "2", "3"] && off.upNext?.source.count == 3 && off.upNext?.left == [])
        // every song of Autoplay's taken out already: the source still loses them
        var none = grown
        for id in ["r1", "r2", "r3"] { none = withoutKey(none, try #require(none.key(id))) }
        let after = withoutStation(none, from: 3)
        expectSound(after)
        #expect(after.ids == ["1", "2", "3"] && after.upNext?.source == stationQueue(3).upNext?.source)
        #expect(after.upNext?.left == [])
        // one of the list's own taken out stays taken out of its round
        let own = withoutKey(grown, try #require(grown.key("3")))
        let kept = withoutStation(own, from: 3)
        #expect(kept.ids == ["1", "2"] && kept.upNext?.left == [LeftOut(pass: 0, at: 2)])
        #expect(kept.upNext?.source.count == 3)
    }

    @Test func aRollBacksFurthestSongTakenOutMovesBack() throws {
        // r2 played, then History's song 2 tapped: rolled back, r2 the furthest unit played
        let playing = Self.grown().at(4)
        let two = try #require(playing.upNext?.marks[1].key)
        let jump = try #require(jumpedTo(playing, two, .off))
        let back = jump.queue
        #expect(jump.back && back.index == 1 && back.upNext?.reached == playing.upNext?.marks[4].key)
        let off = withoutStation(back, from: 3)
        expectSound(off)
        // r1, r2 and r3 are to come again: they go, and the list runs on to song 3 now
        #expect(off.ids == ["1", "2", "3"] && off.upNext?.reached == back.upNext?.marks[2].key)
        #expect(upNextView(off, .off).list?.rows.map(\.track.id) == ["3"])
    }

    @Test func theSameQueueWithNothingOfTheStationsLeft() {
        let base = stationQueue(3)
        // nothing appended (the start is the source's end), or a start past it
        #expect(withoutStation(base, from: 3) == base && withoutStation(base, from: 5) == base)
        #expect(withoutStation(base, from: -1) == base)
        // no Up Next's account
        #expect(withoutStation(.empty, from: 0) == .empty)
        let plain = UpNextQueue(tracks: simAlbum(3), index: 0)
        #expect(withoutStation(plain, from: 0) == plain)
        // a library's shuffle: no station is made of one
        let paged = startUpNext(simAlbum(3), start: 0,
                                paged: Paged(token: "t", total: 9, fetched: 3, scope: .yours, level: nil), id: "q1")
        #expect(withoutStation(paged, from: 1) == paged)
        // made once, nothing more to take
        let off = withoutStation(withStation(base, stationTracks(radioSongs(2)), .off), from: 3)
        #expect(withoutStation(off, from: 3) == off)
    }
}

/// A controller over a fake engine (QueueControllerTests' rig is its file's own).
private func stationRig(_ mode: Repeat = .off) -> (QueueController, FakeEngine) {
    let engine = FakeEngine()
    return (QueueController(engine: engine, repeat: mode, random: Seeded(1).next), engine)
}

@Suite struct AppendStationTests {
    @Test func anEditLikeAddToQueues() {
        let (player, engine) = stationRig()
        player.playTracks(simAlbum(3), start: 2)
        player.appendStation(stationTracks(radioSongs(2)))
        #expect(engine.ids == ["1", "2", "3", "r1", "r2"] && engine.current == "3")
        #expect(engine.log == ["play 2", "replaced"] && player.queue.ids == engine.ids)
        #expect(engine.entries.map(\.key) == player.queue.upNext?.marks.map(\.key))
    }

    @Test func heldForASongsLastMomentsThenMade() {
        let (player, engine) = stationRig()
        player.playTracks(simAlbum(3), start: 2)
        // the engine has its end ready: a new next entry refused, held
        engine.nextScheduled = true
        player.appendStation(stationTracks(radioSongs(2)))
        #expect(engine.log.last == "refused" && player.holdsAnEdit && player.queue.ids == ["1", "2", "3"])
        player.tick(heard: 1)
        #expect(player.holdsAnEdit)
        engine.nextScheduled = false
        player.tick(heard: 2)
        #expect(!player.holdsAnEdit && engine.ids == ["1", "2", "3", "r1", "r2"] && engine.log.last == "replaced")
    }

    @Test func neverStartsTheMusic() {
        let (player, engine) = stationRig()
        player.playTracks(simAlbum(2), start: 1)
        engine.playOut()
        #expect(!player.queueEnded() && !player.intendsToPlay)
        player.appendStation(stationTracks(radioSongs(2)))
        #expect(!engine.playing && !player.intendsToPlay)
        #expect(!engine.log.dropFirst().contains { $0.hasPrefix("play") || $0 == "resume" })
    }

    @Test func autoplayOffIsAnEditHeldForTheJoinAndNeverAPlay() {
        let (player, engine) = stationRig()
        player.playTracks(simAlbum(3), start: 2)
        player.appendStation(stationTracks(radioSongs(2)))
        #expect(engine.ids == ["1", "2", "3", "r1", "r2"])
        // the engine has r1 ready after the song playing: the removal, which changes it, waits for the join
        engine.nextScheduled = true
        player.removeStation(from: 3)
        #expect(engine.log.last == "refused" && player.holdsAnEdit && engine.ids == ["1", "2", "3", "r1", "r2"])
        engine.nextScheduled = false
        player.tick(heard: 2)
        #expect(!player.holdsAnEdit && engine.ids == ["1", "2", "3"] && player.queue.upNext?.source.count == 3)
        #expect(!engine.log.dropFirst().contains { $0.hasPrefix("play") || $0 == "resume" })
    }

    @Test func nothingUnderRepeat() {
        for mode in [Repeat.all, .one] {
            let (player, engine) = stationRig(mode)
            player.playTracks(simAlbum(2), start: 0)
            let before = player.queue
            player.appendStation(stationTracks(radioSongs(2)))
            #expect(player.queue == before && !engine.ids.contains("r1"), "\(mode)")
        }
    }
}
