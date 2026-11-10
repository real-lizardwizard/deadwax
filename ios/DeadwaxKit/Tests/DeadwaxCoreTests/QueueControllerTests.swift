import Foundation
import Testing
@testable import DeadwaxCore

// The queue's player rules - QueueController over a fake engine - as ui/test/player.sim.cjs checks usePlayer's (the
// sim's words in each test's comment). The fake keeps a queue of entries, an entry heard and how far in, and refuses
// what the real engine refuses (D4): an edit while the entry heard isn't the one the controller names (a join it
// hasn't seen, a seek on its way), or one that would change a next song already scheduled.

/// An engine as EngineLink describes one, with nothing to hear.
final class FakeEngine: EngineLink {
    private(set) var entries: [QueueEntry] = []
    var index = -1
    var seconds = 0.0
    private(set) var playing = false
    var ended = false
    /// the next entry is scheduled on a player node: a change to what it decodes to is refused
    var nextScheduled = false
    /// a seek on its way: every edit refused, as the web's stream refuses one
    var seeking = false
    private(set) var log: [String] = []

    var ids: [String] { entries.map(\.track.id) }
    var current: String? { entries.indices.contains(index) ? entries[index].track.id : nil }

    func play(_ entries: [QueueEntry], from index: Int, at seconds: Double) {
        load(entries, index, seconds)
        playing = true
        log.append("play \(index)")
    }

    func restore(_ entries: [QueueEntry], from index: Int, at seconds: Double) {
        load(entries, index, seconds)
        playing = false
        log.append("restore \(index) at \(seconds)")
    }

    func replaceUpcoming(_ entries: [QueueEntry], current: Int) -> Bool {
        guard !seeking, current == index, entries.indices.contains(current),
              entries[current] == self.entries[current] else {
            log.append("refused")
            return false
        }
        if nextScheduled {
            let next = current + 1
            let was = self.entries.indices.contains(next) ? self.entries[next].audio : nil
            let now = entries.indices.contains(next) ? entries[next].audio : nil
            if was != now {
                log.append("refused")
                return false
            }
        }
        self.entries = entries
        log.append("replaced")
        return true
    }

    func skip(to index: Int) {
        self.index = index
        seconds = 0
        ended = false
        nextScheduled = false
        log.append("skip \(index)")
    }

    func seek(to seconds: Double) {
        self.seconds = seconds
        log.append("seek \(seconds)")
    }

    func resume() {
        playing = true
        log.append("resume")
    }

    func stop() {
        entries = []
        index = -1
        playing = false
        log.append("stop")
    }

    func heard() -> EngineHeard? {
        entries.isEmpty ? nil : EngineHeard(index: index, seconds: seconds, ended: ended)
    }

    /// The engine ran into its next entry on its own.
    func join(after seconds: Double = 0) {
        index += 1
        self.seconds = seconds
        nextScheduled = false
    }

    /// The last entry played to its end.
    func playOut() {
        ended = true
        playing = false
    }

    private func load(_ entries: [QueueEntry], _ index: Int, _ seconds: Double) {
        self.entries = entries
        self.index = index
        self.seconds = seconds
        ended = false
        nextScheduled = false
    }
}

/// A controller over a fake engine, with every draw from one seeded generator.
private func rig(_ mode: Repeat = .off, seed: Int64 = 1) -> (QueueController, FakeEngine) {
    let engine = FakeEngine()
    return (QueueController(engine: engine, repeat: mode, random: Seeded(seed).next), engine)
}

private extension QueueController {
    var after: [String] { queue.after }
    func key(_ id: String, nth: Int = 0) -> Int { queue.key(id, nth: nth) ?? -1 }
}

@Suite struct QueueControllerStartTests {
    @Test func aListPlayedIsToppedUpOnceBeforeTheEngineStarts() { // :4768
        let (player, engine) = rig(.one)
        player.playTracks(simAlbum(3), start: 0)
        #expect(engine.ids == ["1", "1", "1", "2", "3"] && engine.index == 0 && engine.playing)
        #expect(engine.log == ["play 0"] && player.intendsToPlay && player.queue.ids == engine.ids)
        #expect(engine.entries.map(\.key) == player.queue.upNext?.marks.map(\.key))
    }

    @Test func aShuffledListStartsAtTheSongTapped() {
        let (player, engine) = rig()
        player.playTracks(simAlbum(6), start: 4, shuffle: true)
        #expect(engine.current == "5" && player.shuffle && engine.ids.sorted() == ["1", "2", "3", "4", "5", "6"])
    }

    @Test func nothingToPlayStops() {
        let (player, engine) = rig()
        player.playTracks(simAlbum(2), start: 0)
        player.playTracks([], start: 0)
        #expect(player.queue == .empty && !player.intendsToPlay && engine.log.last == "stop")
    }

    @Test func theEntriesCarryTheirKeysAndWhatTheyDecodeTo() {
        var loud = simTrack("1")
        loud.level = .album
        let entries = QueueController.entries(toppedUp(startUpNext([loud, simTrack("2")], start: 0), .one))
        #expect(entries.map(\.audio) == ["1|album", "1|album", "1|album", "2|off"])
        #expect(entries.map(\.key) == [0, 2, 3, 1])
        #expect(QueueController.entries(UpNextQueue(tracks: simAlbum(2), index: 0)).map(\.key) == [0, 1])
    }

    @Test func everyChangeIsToldAndTheViewIsUpNexts() {
        let (player, _) = rig(.all)
        var told: [Int] = []
        player.onChange = { told.append($0.tracks.count) }
        player.playTracks(simAlbum(3), start: 2)
        player.removeFromQueue(key: player.key("1"))
        #expect(told == [6, 5])
        #expect(player.view == upNextView(player.queue, .all))
    }
}

@Suite struct QueueControllerEditTests {
    @Test func playNextMidSongIsQueuedAfterIt() { // :4787
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        engine.seconds = 2
        let started = player.playNext([simTrack("9")])
        #expect(!started && player.after == ["9", "2", "3"] && engine.ids == ["1", "9", "2", "3"])
        #expect(engine.log == ["play 0", "replaced"] && !player.holdsAnEdit)
        player.playLast([simTrack("8")])
        player.playNext([simTrack("7")])
        #expect(player.after == ["7", "9", "8", "2", "3"]) // :4864's order
    }

    @Test func playNextWithTheNextSongScheduledIsHeldTillTheJoin() { // :5159 (D4)
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        engine.seconds = 195
        engine.nextScheduled = true
        #expect(!player.playNext([simTrack("9")]))
        #expect(player.after == ["2", "3"] && engine.ids == ["1", "2", "3"] && player.holdsAnEdit)
        engine.join()
        player.engineChanged()
        #expect(player.queue.current?.id == "2" && player.after == ["9", "3"] && engine.ids == ["1", "2", "9", "3"])
        #expect(!player.holdsAnEdit)
    }

    @Test func aChangeThatLeavesTheScheduledSongAloneIsMadeAtOnce() {
        let (player, engine) = rig()
        player.playTracks(simAlbum(4), start: 0)
        engine.nextScheduled = true
        player.removeFromQueue(key: player.key("3"))
        #expect(player.after == ["2", "4"] && !player.holdsAnEdit && engine.log.last == "replaced")
        player.playLast([simTrack("9")])
        #expect(player.after == ["2", "4"] && player.holdsAnEdit && engine.log.last == "refused")
    }

    @Test func aRowOutMovedAndPlayingNextCleared() {
        let (player, engine) = rig()
        player.playTracks(simAlbum(4), start: 0)
        player.playLast([simTrack("a"), simTrack("b")])
        player.removeFromQueue(key: player.key("3"))
        #expect(player.after == ["a", "b", "2", "4"])
        player.moveInQueue(key: player.key("b"), to: 0)
        #expect(player.after == ["b", "a", "2", "4"])
        player.clearPlayingNext()
        #expect(player.after == ["2", "4"] && engine.ids == ["1", "2", "4"] && engine.index == 0)
        #expect(!engine.log.contains { $0.hasPrefix("skip") || $0.hasPrefix("seek") || $0 == "play 1" })
    }

    @Test func aRowsTapPlaysThatSongNow() { // :4966-4981
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        engine.seconds = 2
        player.jumpTo(key: player.key("3"))
        #expect(player.queue.current?.id == "3" && player.queue.ids == ["1", "3"] && engine.current == "3" && engine.playing)
        player.previous()
        #expect(player.queue.current?.id == "1")
    }

    @Test func aRowsTapFromAPausePlays() { // :4979-4981
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        player.intendsToPlay = false
        engine.seconds = 2
        player.jumpTo(key: player.key("3"))
        #expect(player.queue.current?.id == "3" && player.intendsToPlay && engine.log.suffix(2) == ["skip 1", "resume"])
        let before = engine.log
        player.jumpTo(key: 999)
        #expect(player.queue.current?.id == "3" && engine.log == before)
    }

    @Test func aRowsTapTheEngineCantTakeIsNotMade() {
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        player.intendsToPlay = false
        engine.seeking = true
        player.jumpTo(key: player.key("3"))
        #expect(player.queue.current?.id == "1" && !player.intendsToPlay && !player.holdsAnEdit && engine.log.last == "refused")
    }

    @Test func shuffleMidSongLeavesTheSongPlayingAlone() { // :4998-5006
        let (player, engine) = rig(seed: 4)
        player.playTracks(simAlbum(8), start: 2)
        engine.seconds = 3
        player.setShuffle(true)
        #expect(player.shuffle && player.queue.current?.id == "3" && engine.index == 2 && engine.seconds == 3)
        #expect(Array(engine.ids.prefix(3)) == ["1", "2", "3"] && engine.log == ["play 2", "replaced"])
        // songs 1 and 2 were never heard (the list started at 3): shuffled in with the rest
        #expect(player.after.sorted() == ["1", "2", "4", "5", "6", "7", "8"])
        engine.join()
        player.engineChanged()
        let now = player.queue.current!.id
        player.setShuffle(false)
        #expect(!player.shuffle && player.after == simAlbum(8).map(\.id).drop { $0 != now }.dropFirst().map { $0 })
        #expect(!engine.log.contains { $0.hasPrefix("seek") || $0.hasPrefix("skip") })
    }

    @Test func aLibrarysShuffleExtendsAsAnEdit() {
        let (player, engine) = rig()
        player.playTracks(simAlbum(3, "p"), start: 0, paged: Paged(token: "t1", total: 450, fetched: 3, scope: .yours))
        #expect(player.paged?.scope == .yours && player.shuffle)
        player.extendQueue(token: "t1", tracks: simAlbum(2, "q"))
        #expect(player.after == ["p2", "p3", "q1", "q2"] && engine.ids.count == 5 && player.paged?.fetched == 5)
        player.setShuffle(false)
        #expect(player.shuffle)
    }
}

@Suite struct QueueControllerRepeatTests {
    @Test func repeatOneNextGoesOnAndRepeatsTheNextSong() { // :5056-5061
        let (player, engine) = rig(.one)
        player.playTracks(simAlbum(3), start: 0)
        engine.seconds = 1
        player.next()
        #expect(player.queue.current?.id == "2" && engine.current == "2" && player.after == ["3"])
        player.tick(heard: 2)
        #expect(Array(player.after.prefix(3)) == ["2", "2", "3"])
        engine.join()
        player.engineChanged()
        let index = player.queue.index
        #expect(player.queue.current?.id == "2" && player.queue.upNext?.marks[index].from == .one)
        engine.seconds = 0.4
        player.previous()
        #expect(player.queue.current?.id == "1")
    }

    @Test func repeatOneOffMidSongTheAlbumCarriesOn() { // :5071
        let (player, engine) = rig(.one)
        player.playTracks(simAlbum(2), start: 0)
        engine.seconds = 3
        player.tick(heard: 3)
        player.setRepeat(.off)
        #expect(player.after == ["2"] && engine.ids == ["1", "2"] && engine.log == ["play 0", "replaced"])
    }

    @Test func repeatAllsLastSongBegunLatelyStillGoesRound() { // :5426-5455
        let (player, engine) = rig(.all)
        player.playTracks(simAlbum(3), start: 0)
        player.next()
        player.next()
        #expect(player.queue.current?.id == "3" && player.after == [])
        player.next()
        #expect(player.queue.current?.id == "1" && player.queue.index == 3 && engine.index == 3)

        let (ended, endedEngine) = rig(.all)
        ended.playTracks(simAlbum(3), start: 0)
        ended.next()
        ended.next()
        endedEngine.playOut()
        #expect(ended.queueEnded())
        #expect(ended.queue.current?.id == "1" && ended.queue.index == 3 && ended.intendsToPlay && endedEngine.log.last == "play 3")

        let (one, oneEngine) = rig(.one)
        one.playTracks(simAlbum(3), start: 0)
        one.next()
        one.next()
        #expect(one.after == [])
        oneEngine.playOut()
        #expect(one.queueEnded())
        #expect(one.queue.current?.id == "3" && one.queue.upNext?.marks[one.queue.index].from == .one)
    }

    @Test func theQueuePlayedOutStops() { // :3311
        let (player, engine) = rig()
        player.playTracks(simAlbum(2), start: 1)
        engine.playOut()
        #expect(!player.queueEnded() && !player.intendsToPlay && player.queue.current?.id == "2")
    }

    @Test func repeatTopsUpOnlyOnceTwoSecondsAreHeard() {
        let (player, _) = rig(.all)
        player.playTracks(simAlbum(3), start: 2)
        let first = player.queue
        player.tick(heard: 1.9)
        #expect(player.queue == first)
        player.tick(heard: 2)
        #expect(player.queue == first) // three queued after the song already: nothing to add
        player.next()
        player.next()
        player.next()
        let lastOfRound = player.queue
        player.tick(heard: 1.99)
        #expect(player.queue == lastOfRound)
        player.tick(heard: 2)
        #expect(player.after.count > lastOfRound.after.count)
        let (off, _) = rig()
        off.playTracks(simAlbum(1), start: 0)
        off.tick(heard: 100)
        #expect(off.after == [])
    }

    @Test func aShortSongIsToppedUpOnceHalfOfItIsHeard() { // :5479
        let (player, engine) = rig(.one)
        player.playTracks([simTrack("1")], start: 0)
        #expect(player.queue.ids == ["1", "1", "1"])
        engine.join()
        player.engineChanged()
        player.tick(heard: 0.5, length: 1.5)
        #expect(player.queue.ids == ["1", "1", "1"])
        player.tick(heard: 0.75, length: 1.5)
        #expect(player.queue.ids == ["1", "1", "1", "1"])
    }

    @Test func repeatIsKeptOnTheDevice() { // :5277
        let (player, _) = rig()
        var kept: [String] = []
        player.onRepeatChange = { kept.append($0.rawValue) }
        player.setRepeat(.one)
        player.setRepeat(.one)
        player.setRepeat(.all)
        #expect(kept == ["one", "all"] && player.repeatMode == .all)
        #expect(Repeat.read(kept.last) == .all)
        #expect(player.queue == .empty)
    }
}

@Suite struct QueueControllerMovingTests {
    @Test func nextAndPreviousKeepAPause() { // D4
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        player.intendsToPlay = false
        player.next()
        #expect(player.queue.current?.id == "2" && engine.log.last == "skip 1")
        engine.seconds = 1
        player.previous()
        #expect(player.queue.current?.id == "1" && engine.log.last == "skip 0" && !engine.log.contains("resume"))
        player.intendsToPlay = true
        player.next()
        #expect(engine.log.suffix(2) == ["skip 1", "resume"])
    }

    @Test func previousPastThreeSecondsRestarts() {
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 1)
        engine.seconds = 3.5
        player.previous()
        #expect(player.queue.current?.id == "2" && engine.log.last == "seek 0.0")
        let (first, firstEngine) = rig()
        first.playTracks(simAlbum(3), start: 0)
        firstEngine.seconds = 1
        first.previous()
        #expect(firstEngine.log.last == "seek 0.0")
    }

    @Test func nextAtTheEndWithRepeatOffDoesNothing() {
        let (player, engine) = rig()
        player.playTracks(simAlbum(2), start: 1)
        player.next()
        #expect(player.queue.index == 1 && engine.log == ["play 1"])
    }

    @Test func aJoinNoChangeHasSeenIsCaughtUpWithFirst() { // :5189, :5360-5374
        func joined() -> (QueueController, FakeEngine) {
            let (player, engine) = rig()
            player.playTracks(simAlbum(4), start: 0)
            engine.join(after: 0.2)
            return (player, engine)
        }
        var (player, engine) = joined()
        player.playNext([simTrack("9")])
        #expect(player.queue.current?.id == "2" && player.after == ["9", "3", "4"])
        (player, engine) = joined()
        player.next()
        #expect(player.queue.current?.id == "3" && engine.current == "3")
        (player, engine) = joined()
        player.previous()
        #expect(player.queue.current?.id == "1" && player.queue.index == 0)
        (player, engine) = joined()
        player.jumpTo(key: player.queue.upNext!.marks[3].key)
        #expect(player.queue.current?.id == "4")
        (player, engine) = joined()
        player.removeFromQueue(key: player.queue.upNext!.marks[2].key)
        #expect(player.queue.current?.id == "2" && player.after == ["4"] && engine.log.last == "replaced")
        (player, engine) = joined()
        player.moveInQueue(key: player.queue.upNext!.marks[3].key, to: 0)
        #expect(player.queue.current?.id == "2" && player.after == ["4", "3"])
    }

    @Test func aChangeHeldThroughASeekIsMadeAtTheJoinComposed() { // :5396-5403
        let (player, engine) = rig(.all)
        player.playTracks(simAlbum(3), start: 0)
        engine.seeking = true
        player.playNext([simTrack("9")])
        player.playLast([simTrack("8")])
        #expect(player.queue.current?.id == "1" && player.after == ["2", "3"] && player.holdsAnEdit)
        player.tick(heard: 5)
        #expect(player.after == ["2", "3"])
        engine.seeking = false
        engine.join()
        player.engineChanged()
        #expect(player.queue.current?.id == "2" && player.after == ["9", "8", "3"] && !player.holdsAnEdit)
        player.tick(heard: 2)
        #expect(player.after == ["9", "8", "3"])
    }

    @Test func aChangeHeldIsMadeAtTheNextTickWhenNothingMoved() { // :5202
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        engine.seeking = true
        player.playNext([simTrack("9")])
        #expect(player.after == ["2", "3"])
        engine.seeking = false
        player.tick(heard: 1)
        #expect(player.after == ["9", "2", "3"] && !player.holdsAnEdit)
    }

    @Test func aNewQueueDropsAChangeHeldForTheOldOne() { // :5412
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        engine.seeking = true
        player.playNext([simTrack("9")])
        player.playTracks([simTrack("4"), simTrack("5")], start: 0)
        #expect(!player.holdsAnEdit)
        engine.seeking = false
        player.tick(heard: 3)
        engine.join()
        player.engineChanged()
        #expect(player.queue.ids == ["4", "5"] && engine.ids == ["4", "5"])
    }

    @Test func playNextAfterTheQueuePlayedOutStartsTheMusic() { // :5216-5231
        let (player, engine) = rig()
        player.playTracks([simTrack("1")], start: 0)
        engine.playOut()
        player.queueEnded()
        let started = player.playNext([simTrack("9")])
        #expect(started && player.queue.ids == ["9"] && player.intendsToPlay && engine.log.last == "play 0")
        let (fresh, _) = rig()
        #expect(fresh.playLast([simTrack("9")]) && fresh.queue.ids == ["9"])
        #expect(!fresh.playNext([]))
    }
}

@Suite struct QueueControllerFailureTests {
    @Test func repeatOnesFailingSongIsSkippedPastItsCopies() { // :5097
        let (player, engine) = rig(.one)
        player.playTracks(simAlbum(2), start: 0)
        #expect(player.skipFailed() == 3)
        #expect(player.queue.current?.id == "2" && engine.log.last == "play 3" && player.intendsToPlay)
    }

    @Test func repeatAllWithEverySongFailingStopsWithinTheRoundQueued() { // :5107
        let (player, _) = rig(.all)
        player.playTracks([simTrack("a"), simTrack("b")], start: 0)
        var skips = 0
        while player.skipFailed() != nil { skips += 1 }
        #expect(skips == 3 && player.queue.tracks.count == 4 && !player.intendsToPlay)
    }

    @Test func aOneSongListThatFailsStops() { // :5117
        let (player, _) = rig(.all)
        player.playTracks([simTrack("x")], start: 0)
        var skips = 0
        while player.skipFailed() != nil { skips += 1 }
        #expect(skips == 2 && player.queue.tracks.count == 3 && !player.intendsToPlay)
    }
}

@Suite struct QueueControllerRestoreTests {
    private func saved(_ mode: Repeat, at index: Int) -> UpNextQueue {
        toppedUp(startUpNext(simAlbum(4), start: 0).at(index), mode)
    }

    @Test func aQueuePutBackIsShownPausedNothingPlayed() { // :5844-5847
        let (player, engine) = rig()
        let back = player.restoreQueue(startUpNext(simAlbum(4), start: 2), position: 50)
        #expect(back == player.queue && back?.index == 2 && engine.log == ["restore 2 at 50.0"] && !engine.playing)
        #expect(!player.intendsToPlay)
        #expect(player.restoreQueue(startUpNext(simAlbum(4), start: 0), position: 900) != nil && engine.log.last == "restore 0 at 200.0")
        #expect(player.restoreQueue(startUpNext([], start: 0), position: 5) == nil)
        _ = player.restoreQueue(startUpNext(simAlbum(2), start: 0), position: -3)
        #expect(engine.log.last == "restore 0 at 0.0")
        _ = player.restoreQueue(startUpNext(simAlbum(2), start: 0), position: .nan)
        #expect(engine.log.last == "restore 0 at 0.0")
    }

    @Test func notWhileTheMusicIsMeantToBePlaying() {
        let (player, engine) = rig()
        player.playTracks(simAlbum(2), start: 0)
        #expect(player.restoreQueue(startUpNext(simAlbum(4), start: 2), position: 50) == nil)
        #expect(player.queue.ids == ["1", "2"] && engine.log == ["play 0"])
    }

    @Test func fittedToThisDevicesRepeat() { // :5909-5916
        let (all, _) = rig(.all)
        #expect(all.restoreQueue(saved(.off, at: 3), position: 0)?.ids == ["1", "2", "3", "4", "1", "2", "3", "4"])
        let (off, _) = rig()
        #expect(off.restoreQueue(saved(.all, at: 3), position: 0)?.ids == ["1", "2", "3", "4"])
        let (one, _) = rig(.one)
        #expect(one.restoreQueue(saved(.off, at: 1), position: 0)?.ids == ["1", "2", "2", "2", "3", "4"])
    }

    @Test func aChangeHeldIsLetGoByAQueuePutBack() { // :6006
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        engine.seeking = true
        player.playNext([simTrack("9")])
        player.intendsToPlay = false
        _ = player.restoreQueue(startUpNext(simAlbum(4), start: 2), position: 50)
        engine.seeking = false
        player.tick(heard: 1)
        #expect(!player.holdsAnEdit && player.queue.ids == ["1", "2", "3", "4"])
    }
}
