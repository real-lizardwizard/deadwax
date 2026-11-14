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
    /// run as an edit arrives, before it is judged - the audio thread moving on between two calls of the main one
    var asAnEditArrives: (() -> Void)?
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
        asAnEditArrives?()
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
    /// The key of the queue's `place`th entry (-1 for none: a key no row has).
    func key(at place: Int) -> Int { queue.upNext?.marks.dropFirst(place).first?.key ?? -1 }
    /// Where the `place`th entry came from (nil for none).
    func from(at place: Int) -> MarkFrom? { queue.upNext?.marks.dropFirst(place).first?.from }
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

    @Test func aRowsTapPlaysThatSongNowKeepingWhatItPasses() { // :4966-4981 (2.1.3)
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        engine.seconds = 2
        #expect(player.jumpTo(key: player.key("3")))
        // nothing to edit: a skip to it, song 2 kept behind it
        #expect(player.queue.current?.id == "3" && player.queue.ids == ["1", "2", "3"] && engine.current == "3" && engine.playing)
        #expect(engine.log.suffix(2) == ["skip 2", "resume"])
        player.previous()
        #expect(player.queue.current?.id == "2")
        player.previous()
        #expect(player.queue.current?.id == "1")
        player.next()
        #expect(player.queue.current?.id == "2")
    }

    @Test func jamesWalkTapEightWhileFivePlays() { // James, 2026-11-11: "Keep them, in order"
        let (player, engine) = rig()
        player.playTracks(simAlbum(12), start: 0)
        for _ in 0..<4 { player.next() }
        #expect(player.queue.current?.id == "5")
        player.jumpTo(key: player.key("8"))
        #expect(player.queue.current?.id == "8" && player.queue.ids == simAlbum(12).map(\.id) && engine.current == "8")
        #expect(player.view.history.map(\.track.id) == ["1", "2", "3", "4", "5", "6", "7"])
        var walk: [String] = []
        for _ in 0..<3 {
            player.previous()
            walk.append(player.queue.current?.id ?? "")
        }
        #expect(walk == ["7", "6", "5"] && engine.current == "5")
        player.next()
        #expect(player.queue.current?.id == "6")
    }

    @Test func aRowsTapFromAPausePlays() { // :4979-4981
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        player.intendsToPlay = false
        engine.seconds = 2
        player.jumpTo(key: player.key("3"))
        #expect(player.queue.current?.id == "3" && player.intendsToPlay && engine.log.suffix(2) == ["skip 2", "resume"])
        let before = engine.log
        #expect(!player.jumpTo(key: 999))
        #expect(player.queue.current?.id == "3" && engine.log == before)
    }

    @Test func aTapIntoTheListCarriesPlayingNextAfterIt() { // player.sim (2.1.3): song 9 still next after song 3
        let (player, engine) = rig()
        player.playTracks(simAlbum(4), start: 0)
        player.playNext([simTrack("9")])
        player.jumpTo(key: player.key("3"))
        #expect(player.queue.current?.id == "3" && player.queue.ids == ["1", "2", "3", "9", "4"] && player.after == ["9", "4"])
        #expect(engine.ids == player.queue.ids && engine.current == "3" && engine.log.suffix(3) == ["replaced", "skip 2", "resume"])
        // (2.1.18) History's song 1: rolled back to it - the same songs in the same order, 2, 3 and the song added to
        // come; the engine holds it, so a move, as Previous moves - nothing replaced
        let one = player.view.history.first { $0.track.id == "1" }!
        let songs = player.queue.tracks
        #expect(player.jumpTo(key: one.key))
        #expect(player.queue.current?.id == "1" && player.queue.index == 0 && player.queue.tracks == songs)
        #expect(player.after == ["2", "3", "9", "4"] && player.view.history.isEmpty && player.view.added.isEmpty)
        #expect(player.view.list?.rows.map(\.track.id) == ["2", "3", "9", "4"])
        #expect(engine.ids == player.queue.ids && engine.current == "1" && engine.playing && engine.log.suffix(2) == ["skip 0", "resume"])
        // Next, Next: song 3 again, a new play of it; Next: the song added, where it was (James: "keep their place")
        player.next()
        player.next()
        #expect(player.queue.current?.id == "3")
        player.next()
        #expect(player.queue.current?.id == "9")
    }

    @Test func aListTapInASongsLastSecondsIsASkip() { // D4: the next song already on a node - nothing to edit
        let (player, engine) = rig()
        player.playTracks(simAlbum(4), start: 0)
        engine.seconds = 198
        engine.nextScheduled = true
        player.jumpTo(key: player.key("4"))
        #expect(player.queue.current?.id == "4" && player.queue.ids == ["1", "2", "3", "4"] && !player.holdsAnEdit)
        #expect(engine.log == ["play 0", "skip 3", "resume"] && engine.current == "4" && engine.playing)
        player.previous()
        #expect(player.queue.current?.id == "3")
    }

    @Test func aTapWhoseEditIsRefusedIsPlayedAfresh() { // D4: Playing Next carried changes the song scheduled next
        let (player, engine) = rig()
        player.playTracks(simAlbum(4), start: 0)
        player.playNext([simTrack("9")])
        engine.seconds = 198
        engine.nextScheduled = true
        #expect(player.jumpTo(key: player.key("4")))
        #expect(player.queue.current?.id == "4" && player.queue.ids == ["1", "2", "3", "4", "9"] && player.intendsToPlay)
        #expect(engine.log.suffix(2) == ["refused", "play 3"] && engine.current == "4" && engine.playing && !player.holdsAnEdit)
        #expect(engine.ids == player.queue.ids && engine.entries.map(\.key) == player.queue.upNext?.marks.map(\.key))
        player.previous()
        #expect(player.queue.current?.id == "3")
    }

    @Test func aHistoryTapFromAPauseRollsBackEvenWithASeekOnItsWay() { // :5118, :5510 (2.1.18): never refused
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        player.next()
        player.intendsToPlay = false
        engine.seeking = true
        let one = player.view.history[0]
        #expect(player.jumpTo(key: one.key))
        // nothing to edit - the songs after the one playing are what they were - so nothing for the engine to refuse
        #expect(player.queue.current?.id == "1" && player.queue.ids == ["1", "2", "3"] && player.intendsToPlay)
        #expect(engine.log.suffix(2) == ["skip 0", "resume"] && engine.current == "1" && engine.playing && !player.holdsAnEdit)
        #expect(!engine.log.contains("refused"))
    }

    @Test func aRollBackThatLetsRepeatOnesCopiesGoIsPlayedAfresh() { // :5032-5048 (2.1.18)
        let (player, engine) = rig(.one)
        player.playTracks(simAlbum(3), start: 0)
        engine.join()
        player.engineChanged()
        player.setRepeat(.off)
        player.next()
        #expect(player.queue.current?.id == "2" && player.queue.ids == ["1", "1", "2", "3"] && player.view.history.map(\.track.id) == ["1"])
        #expect(player.jumpTo(key: player.view.history[0].key))
        // a row plays once with Repeat off: its copy gone - other entries, so the queue played afresh from it
        #expect(player.queue.current?.id == "1" && player.queue.ids == ["1", "2", "3"] && player.queue.index == 0)
        #expect(engine.log.last == "play 0" && engine.ids == ["1", "2", "3"] && engine.playing && !player.holdsAnEdit)
        #expect(engine.entries.map(\.key) == player.queue.upNext?.marks.map(\.key))
    }

    @Test func aChangeHeldThroughAHistoryTapThatLetsCopiesGoIsMadeAfterIt() { // review of the port: jump's runHeld
        // Play Next with the next song scheduled is held; History's row then tapped lets Repeat One's copy go - other
        // entries, played afresh - and the change held is made on the queue as it is then: 9 after the row tapped
        let (player, engine) = rig(.one)
        player.playTracks(simAlbum(3), start: 0)
        engine.join()
        player.engineChanged()
        player.setRepeat(.off)
        player.next()
        #expect(player.queue.current?.id == "2" && player.queue.ids == ["1", "1", "2", "3"])
        engine.seconds = 198
        engine.nextScheduled = true
        #expect(!player.playNext([simTrack("9")]))
        #expect(player.holdsAnEdit && player.after == ["3"])
        #expect(player.jumpTo(key: player.view.history[0].key))
        #expect(player.queue.current?.id == "1" && player.queue.ids == ["1", "9", "2", "3"] && !player.holdsAnEdit,
                "\(player.queue.ids)")
        #expect(engine.ids == ["1", "9", "2", "3"] && engine.log.suffix(2) == ["play 0", "replaced"], "\(engine.log)")
        #expect(engine.entries.map(\.key) == player.queue.upNext?.marks.map(\.key))
    }

    @Test func aRollBackUnderRepeatOneKeepsItsCopiesAndSkips() { // :5032-5048's other half: jumpedTo gets the device's Repeat
        let (player, engine) = rig(.one)
        player.playTracks(simAlbum(3), start: 0)
        engine.join()
        player.engineChanged()
        player.next()
        let before = player.queue.ids
        #expect(player.queue.current?.id == "2" && before.filter { $0 == "1" }.count > 1 && player.view.history.map(\.track.id) == ["1"],
                "\(before) \(player.view.history.map(\.track.id))")
        #expect(player.jumpTo(key: player.view.history[0].key))
        // Repeat One still on: the row's copies stay, so the same entries - a skip, nothing played afresh
        #expect(player.queue.current?.id == "1" && player.queue.ids == before && player.queue.index == 0, "\(player.queue.ids)")
        #expect(engine.log.suffix(2) == ["skip 0", "resume"] && engine.ids == before && engine.playing, "\(engine.log)")
        #expect(engine.entries.map(\.key) == player.queue.upNext?.marks.map(\.key))
    }

    @Test func aChangeHeldThroughARowsTapIsMadeAfterIt() {
        let (player, engine) = rig()
        player.playTracks(simAlbum(4), start: 0)
        engine.seconds = 198
        engine.nextScheduled = true
        player.playNext([simTrack("9")])
        #expect(player.holdsAnEdit && player.after == ["2", "3", "4"])
        player.jumpTo(key: player.key("4"))
        #expect(player.queue.current?.id == "4" && player.after == ["9"] && !player.holdsAnEdit)
        #expect(engine.ids == ["1", "2", "3", "4", "9"] && engine.log.suffix(3) == ["skip 3", "resume", "replaced"])
    }

    @Test func aRowsTapRefusedAsTheEngineJoinsIsFoundAgain() {
        let (player, engine) = rig()
        player.playTracks(simAlbum(4), start: 0)
        player.playNext([simTrack("9")])
        engine.nextScheduled = true
        engine.asAnEditArrives = { [unowned engine] in
            engine.asAnEditArrives = nil
            engine.join(after: 0.1)
        }
        player.jumpTo(key: player.key("4"))
        // song 9, run into meanwhile, is behind song 4 as song 1 would have been
        #expect(player.queue.current?.id == "4" && player.queue.ids == ["1", "9", "2", "3", "4"])
        #expect(engine.log == ["play 0", "replaced", "refused", "play 4"])
        #expect(engine.current == "4" && engine.ids == player.queue.ids && !player.holdsAnEdit)
    }

    @Test func previousBeforeWhereTheListBeganMovesHistorysFloor() { // player.sim (2.1.3)
        let (player, engine) = rig()
        player.playTracks(simAlbum(4), start: 2)
        player.previous()
        #expect(player.queue.current?.id == "2" && player.queue.upNext?.startedAt == 1 && player.view.history.isEmpty)
        #expect(engine.current == "2")
        player.next()
        #expect(player.queue.current?.id == "3" && player.view.history.map(\.track.id) == ["2"])
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
        let now = player.queue.current?.id
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
        #expect(player.queue.current?.id == "2" && player.from(at: index) == .one)
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
        #expect(one.queue.current?.id == "3" && one.from(at: one.queue.index) == .one)
    }

    @Test func repeatOneTurnedOnInASongsLastSecondsRepeatsTheNextSong() { // D4's hold: a divergence, recorded
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        engine.seconds = 198
        engine.nextScheduled = true
        player.setRepeat(.one)
        #expect(player.repeatMode == .one && player.after == ["2", "3"] && player.holdsAnEdit && engine.ids == ["1", "2", "3"])
        engine.join()
        player.engineChanged()
        #expect(player.queue.current?.id == "2" && player.queue.ids == ["1", "2", "2", "2", "3"] && !player.holdsAnEdit)
        #expect(engine.ids == player.queue.ids)
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

    @Test func aShortSongsTagsGiveItsLengthUntilItIsDecoded() { // songLength(): the tags' until the element knows
        var short = simTrack("1")
        short.duration = 1.5
        let (player, engine) = rig(.one)
        player.playTracks([short], start: 0)
        engine.join()
        player.engineChanged()
        player.tick(heard: 0.5)
        #expect(player.queue.ids == ["1", "1", "1"])
        player.tick(heard: 0.75)
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
        player.jumpTo(key: player.key(at: 3))
        #expect(player.queue.current?.id == "4")
        (player, engine) = joined()
        player.removeFromQueue(key: player.key(at: 2))
        #expect(player.queue.current?.id == "2" && player.after == ["4"] && engine.log.last == "replaced")
        (player, engine) = joined()
        player.moveInQueue(key: player.key(at: 3), to: 0)
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

/// (the web's 2.1.18) An older row's tap - a song played before, above History: rollBack, the web's jumpTo with the
/// rows brought back - it and every older row below it ahead of History's songs, and it plays: other entries, so the
/// queue played afresh from it, as the web's new stream made in the tap (player.sim :5050-5068).
@Suite struct QueueControllerRollBackTests {
    private func row(_ id: String, _ starts: [Int64], entry: Int? = nil) -> Brought {
        Brought(track: simTrack(id), starts: starts, entry: entry)
    }

    @Test func anOlderRowPlaysAtOnceAheadOfTheQueueItRollsBackThrough() {
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        engine.seconds = 30
        player.next()
        #expect(player.rollBack([row("8", [1_700_000_000_000])], floor: nil))
        #expect(player.queue.current?.id == "8" && player.queue.index == 0 && player.after == ["1", "2", "3"])
        #expect(player.queue.upNext?.marks[0].starts == [1_700_000_000_000] && player.from(at: 0) == .added)
        #expect(engine.log.last == "play 0" && engine.ids == ["8", "1", "2", "3"] && engine.current == "8" && engine.playing)
        #expect(engine.entries.map(\.key) == player.queue.upNext?.marks.map(\.key) && !player.holdsAnEdit)
        // ...Next: song 1 - the queue it rolled back through, as it played
        player.next()
        #expect(player.queue.current?.id == "1")
        // no rows: nothing
        let before = engine.log
        #expect(!player.rollBack([], floor: nil))
        #expect(player.queue.current?.id == "1" && player.queue.index == 1 && engine.log == before)
    }

    @Test func fromAPauseItPlays() {
        let (player, engine) = rig()
        player.playTracks(simAlbum(2), start: 0)
        player.intendsToPlay = false
        #expect(player.rollBack([row("x", [5])], floor: nil))
        #expect(player.queue.current?.id == "x" && player.intendsToPlay && engine.playing)
    }

    @Test func withTheNextSongScheduledItIsNeverRefused() { // D4: other entries, so played afresh - no edit to refuse
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        engine.seconds = 198
        engine.nextScheduled = true
        #expect(player.rollBack([row("x", [5])], floor: nil))
        #expect(player.queue.current?.id == "x" && player.queue.ids == ["x", "1", "2", "3"] && !player.holdsAnEdit)
        #expect(engine.log == ["play 0", "play 0"] && engine.current == "x" && engine.playing)
    }

    @Test func theFloorDrawnKeepsTheQueueFromThereThoughTheEngineRanOn() { // :5512-5530 (2.1.18 review)
        // History at its 50 (2-51, 52 playing): the rows were read against 2's - and the engine ran on into 53 before
        // the tap, so the controller's catch-up moves History's floor on (3); `floor` keeps 2, as drawn
        let (player, engine) = rig()
        player.playTracks(simAlbum(80), start: 0)
        for _ in 0..<51 { player.next() }
        #expect(player.queue.current?.id == "52" && player.view.history.first?.track.id == "2")
        let floor = player.view.history[0].key
        let rows = [row("1", [7], entry: player.key(at: 0))]
        engine.join()
        #expect(player.rollBack(rows, floor: floor))
        #expect(player.queue.current?.id == "1" && player.queue.ids == simAlbum(80).map(\.id))
        let (other, ran) = rig()
        other.playTracks(simAlbum(80), start: 0)
        for _ in 0..<51 { other.next() }
        ran.join()
        #expect(other.rollBack([row("1", [7], entry: other.key(at: 0))], floor: nil))
        #expect(!other.queue.ids.contains("2") && other.queue.ids.first == "1")
    }

    @Test func aChangeHeldThroughItIsMadeAfterIt() { // review of the port: jump's runHeld, an older row's tap
        // Play Next with the next song scheduled is held; an older row then tapped plays afresh from it, and the change
        // held is made on the queue as it is then: 9 after the row tapped, ahead of the queue rolled back through
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        engine.seconds = 198
        engine.nextScheduled = true
        #expect(!player.playNext([simTrack("9")]))
        #expect(player.holdsAnEdit && player.after == ["2", "3"])
        #expect(player.rollBack([row("x", [5])], floor: nil))
        #expect(player.queue.current?.id == "x" && player.after == ["9", "1", "2", "3"] && !player.holdsAnEdit, "\(player.queue.ids)")
        #expect(engine.ids == ["x", "9", "1", "2", "3"] && engine.log.suffix(2) == ["play 0", "replaced"], "\(engine.log)")
        #expect(engine.entries.map(\.key) == player.queue.upNext?.marks.map(\.key))
    }

    @Test func withNothingPlayingItDoesNothing() { // the web's jumpTo: broughtBack has no queue to bring them into
        let (fresh, engine) = rig()
        #expect(!fresh.rollBack([row("x", [5])], floor: nil))
        #expect(fresh.queue == .empty && engine.log.isEmpty && !fresh.intendsToPlay)
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
        //? bounded: a skip that never stops fails here by name rather than hanging the run
        while skips < 20, player.skipFailed() != nil { skips += 1 }
        #expect(skips == 3 && player.queue.tracks.count == 4 && !player.intendsToPlay)
    }

    @Test func aOneSongListThatFailsStops() { // :5117
        let (player, _) = rig(.all)
        player.playTracks([simTrack("x")], start: 0)
        var skips = 0
        while skips < 20, player.skipFailed() != nil { skips += 1 }
        #expect(skips == 2 && player.queue.tracks.count == 3 && !player.intendsToPlay)
    }

    @Test func aFailureWhilePausedWaitsForATap() { // playQueue.ts afterFailure: !intendsToPlay -> stop
        let (player, engine) = rig()
        player.playTracks(simAlbum(3), start: 0)
        player.intendsToPlay = false
        #expect(player.skipFailed() == nil)
        #expect(player.queue.index == 0 && !player.intendsToPlay && engine.log == ["play 0"])
        player.intendsToPlay = true
        #expect(player.skipFailed() == 1 && engine.log.last == "play 1")
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
