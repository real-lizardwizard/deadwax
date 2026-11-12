import Foundation
import Testing
@testable import DeadwaxCore

// The queue kept on the phone (phase2-downloads.md 7.5, 7.6; ResumeController's KEPT ON THE PHONE): a save kept
// unsent until deadwax answers it, the order at the next open or return - deadwax asked first, a queue saved elsewhere
// since winning - an offline launch putting back the last queue this phone saved or took, and a 401 holding it. The
// phone's own rules: the web keeps nothing on disk, so these have no sim to follow.

/// A kept row of `ids` as this phone (ResumePage's device) would have kept it: playing `index`, `position` seconds in.
private func keptRow(_ ids: [String], _ index: Int, _ position: Double, rev: Int?, seen: String?, unsent: Bool) -> QueueKept {
    QueueKept(queue: startUpNext(queueOf(ids, level: .album), start: index), position: position, device: "phone-device-1",
              label: Resume.label, rev: rev, idsRev: nil, shared: false, seen: seen, unsent: unsent)
}

/// GET /queue answering with this phone's own save of `ids` (deadwax's record, rev `rev`).
private func ownAnswer(_ ids: [String], _ index: Int, _ position: Double, rev: Int) -> QueueAnswer {
    answerOf(ids, index, position, kept: keptOf(ids, index, position, rev: rev, device: "phone-device-1", label: Resume.label))
}

@Suite struct ResumeKeptTests {
    // MARK: kept as it is saved

    @Test func aSaveIsKeptUnsentUntilDeadwaxAnswersAndASentSaveClearsIt() {
        let keeper = FakeQueueKeeper()
        let p = ResumePage(keeper: keeper)
        p.set(startUpNext(queueOf(["a", "b", "c"]), start: 1))
        p.run(2_100)
        // kept before it went: the queue as a full save sends it, unsent
        #expect(p.asked(.full).count == 1)
        #expect(keeper.row?.unsent == true)
        #expect(keeper.row?.answer.kept?.ids == ["a", "b", "c"])
        #expect(keeper.row?.answer.kept?.index == 1)
        #expect(keeper.row?.answer.kept?.device == "phone-device-1")
        // nothing answered (the network gone): still kept, still unsent
        p.ask(.full, 0).refuse(.unanswered)
        p.run(0)
        #expect(keeper.row?.unsent == true)
        // tried again (going to the background, 30 s on) and answered: sent - the queue stays, for an offline launch
        p.run(30_000)
        p.controller.background()
        p.run(0)
        #expect(p.asked(.full).count == 2)
        p.ask(.full, 1).ok(7, 7)
        p.run(0)
        #expect(keeper.row?.unsent == false)
        #expect(keeper.row?.rev == 7)
        #expect(keeper.row?.seen == "kept:7")
        #expect(keeper.row?.answer.kept?.ids == ["a", "b", "c"])
    }

    @Test func anOlderSavesAnswerDoesntMarkANewerKeptSaveSent() {
        let keeper = FakeQueueKeeper()
        let p = ResumePage(keeper: keeper)
        p.set(startUpNext(queueOf(["a", "b"]), start: 0))
        p.run(2_100)
        let first = p.ask(.full, 0)
        // changed while the first is out, and sent at once as the app goes to the background
        p.set(startUpNext(queueOf(["a", "b", "c"]), start: 0))
        p.controller.background()
        p.run(0)
        let second = p.ask(.full, 1)
        first.ok(6, 6)
        p.run(0)
        #expect(keeper.row?.unsent == true)
        #expect(keeper.row?.answer.kept?.ids == ["a", "b", "c"])
        second.ok(7, 7)
        p.run(0)
        #expect(keeper.row?.unsent == false)
        #expect(keeper.row?.rev == 7)
    }

    @Test func aQueuePutBackFromDeadwaxIsKeptAsTaken() {
        let keeper = FakeQueueKeeper()
        let p = ResumePage(answer: answerOf(["1", "2", "3"], 1, 95, kept: keptOf(["1", "2", "3"], 1, 95, rev: 5)),
                           keeper: keeper)
        #expect(p.restored(0)?.ids == ["1", "2", "3"])
        #expect(keeper.row?.unsent == false)
        #expect(keeper.row?.rev == 5)
        #expect(keeper.row?.seen == "kept:5")
        #expect(keeper.row?.answer.kept?.ids == ["1", "2", "3"])
        #expect(keeper.row?.answer.kept?.position == 95)
        #expect(p.asked(.full).isEmpty && p.asked(.at).isEmpty)
    }

    // MARK: the next open - deadwax asked first

    @Test func atOpenAQueueAnotherDeviceSavedSinceWinsOverTheKeptSave() {
        let keeper = FakeQueueKeeper(keptRow(["k1", "k2", "k3"], 1, 30, rev: 3, seen: "kept:3", unsent: true))
        let p = ResumePage(answer: answerOf(["m1", "m2"], 0, 12, kept: keptOf(["m1", "m2"], 0, 12, rev: 5)), keeper: keeper)
        #expect(p.player.restored.count == 1)
        #expect(p.restored(0)?.ids == ["m1", "m2"])
        #expect(p.said == ["Picked up from your Mac"])
        // the kept save let go: nothing sent over the Mac's
        #expect(p.asked(.full).isEmpty && p.asked(.at).isEmpty)
        #expect(keeper.row?.unsent == false)
        #expect(keeper.row?.answer.kept?.ids == ["m1", "m2"])
    }

    @Test func atOpenDeadwaxHoldingThisPhonesOlderSaveTheKeptOneIsPutBackAndSentAfterTheAsk() {
        let keeper = FakeQueueKeeper(keptRow(["k1", "k2", "k3"], 1, 30, rev: 5, seen: "kept:5", unsent: true))
        let p = ResumePage(answer: ownAnswer(["k1", "k2"], 0, 3, rev: 5), keeper: keeper)
        // the GET first, the kept save only after its answer
        #expect(p.server.asks.map(\.kind) == [.get, .full])
        #expect(p.restored(0)?.ids == ["k1", "k2", "k3"])
        #expect(p.restored(0)?.index == 1)
        #expect(p.restored(0)?.position == 30)
        #expect(p.player.queue.tracks.map(\.level) == [.album, .album, .album])
        #expect(p.said.isEmpty)
        let full = p.ask(.full, 0)
        #expect(full.full?.ids == ["k1", "k2", "k3"])
        #expect(full.full?.index == 1)
        #expect(full.full?.position == 30)
        full.ok(6, 6)
        p.run(0)
        #expect(keeper.row?.unsent == false)
        #expect(keeper.row?.rev == 6)
    }

    @Test func atOpenAnotherDevicesQueueThisPhoneHadAlreadySavedOverIsntNew() {
        // the Mac's rev 4 is older than this phone's last (5): the kept save goes
        let keeper = FakeQueueKeeper(keptRow(["k1", "k2"], 0, 10, rev: 5, seen: "kept:5", unsent: true))
        let p = ResumePage(answer: answerOf(["m1"], 0, 0, kept: keptOf(["m1"], 0, 0, rev: 4)), keeper: keeper)
        #expect(p.restored(0)?.ids == ["k1", "k2"])
        #expect(p.said.isEmpty)
        #expect(p.server.asks.map(\.kind) == [.get, .full])
    }

    @Test func atOpenAnotherAppsQueueWinsUnlessItIsTheOneThisPhoneTook() {
        let symfonium = answerOf(["s1", "s2"], 1, 40, changedBy: "Symfonium")
        let sign = "Symfonium|1|40.0|s1,s2"
        // taken before the phone went offline and played on: the phone's own goes
        let took = FakeQueueKeeper(keptRow(["k1", "k2"], 0, 10, rev: 2, seen: sign, unsent: true))
        let p = ResumePage(answer: symfonium, keeper: took)
        #expect(p.restored(0)?.ids == ["k1", "k2"])
        #expect(p.server.asks.map(\.kind) == [.get, .full])
        // saved by Symfonium since: it wins
        let other = FakeQueueKeeper(keptRow(["k1", "k2"], 0, 10, rev: 2, seen: "kept:2", unsent: true))
        let q = ResumePage(answer: symfonium, keeper: other)
        #expect(q.restored(0)?.ids == ["s1", "s2"])
        #expect(q.said == ["Picked up from Symfonium"])
        #expect(q.asked(.full).isEmpty)
        #expect(other.row?.unsent == false)
    }

    @Test func atOpenWithTheKeptQueueSentDeadwaxsAnswerIsTakenAsBefore() {
        let keeper = FakeQueueKeeper(keptRow(["k1", "k2"], 0, 10, rev: 5, seen: "kept:5", unsent: false))
        let p = ResumePage(answer: ownAnswer(["k1", "k2"], 1, 50, rev: 6), keeper: keeper)
        #expect(p.restored(0)?.index == 1)
        #expect(p.restored(0)?.position == 50)
        #expect(p.asked(.full).isEmpty && p.asked(.at).isEmpty)
    }

    // MARK: opening with deadwax out of reach

    @Test func anOfflineLaunchPutsBackTheLastQueueThisPhoneSavedOrTookPaused() {
        let keeper = FakeQueueKeeper(keptRow(["k1", "k2", "k3"], 2, 75, rev: 9, seen: "kept:9", unsent: false))
        let p = ResumePage(keeper: keeper)
        p.ask(.get, 0).refuse(.unanswered)
        p.run(0)
        #expect(p.player.restored.count == 1)
        #expect(p.restored(0)?.ids == ["k1", "k2", "k3"])
        #expect(p.restored(0)?.index == 2)
        #expect(p.restored(0)?.position == 75)
        #expect(p.player.queue.upNext != nil)
        #expect(p.player.queue.tracks.map(\.level) == [.album, .album, .album])
        #expect(p.said.isEmpty)
        // a queue put back is the baseline: nothing saved for it, at the background or after
        p.controller.background()
        p.run(40_000)
        #expect(p.asked(.full).isEmpty && p.asked(.at).isEmpty)
    }

    @Test func anOfflineLaunchWithNothingKeptStartsEmpty() {
        let p = ResumePage(keeper: FakeQueueKeeper())
        p.ask(.get, 0).refuse(.unanswered)
        p.run(0)
        #expect(p.player.restored.isEmpty)
        #expect(p.player.queue.current == nil)
    }

    @Test func aKeptSaveNotSentWaitsForDeadwaxsAnswerAtTheNextReturn() {
        let keeper = FakeQueueKeeper(keptRow(["k1", "k2"], 0, 10, rev: 2, seen: "kept:2", unsent: true))
        let p = ResumePage(keeper: keeper)
        p.ask(.get, 0).refuse(.status(502))
        p.run(0)
        #expect(p.restored(0)?.ids == ["k1", "k2"])
        // not sent blind as the app goes to the background
        p.controller.background()
        p.run(16_000)
        #expect(p.asked(.full).isEmpty && p.asked(.at).isEmpty)
        // back: deadwax asked first, and the kept save only after
        p.focus()
        #expect(p.server.asks.map(\.kind) == [.get, .get])
        p.ask(.get, 1).answer(ownAnswer(["k1"], 0, 0, rev: 2))
        p.run(0)
        #expect(p.server.asks.map(\.kind) == [.get, .get, .full])
        #expect(p.ask(.full, 0).full?.ids == ["k1", "k2"])
        #expect(p.player.restored.count == 1)
        p.ask(.full, 0).ok(3, 3)
        p.run(0)
        #expect(keeper.row?.unsent == false)
    }

    @Test func aQueueSavedElsewhereWhileThePhoneWasOfflineWinsAtTheReturn() {
        let keeper = FakeQueueKeeper(keptRow(["k1", "k2"], 0, 10, rev: 2, seen: "kept:2", unsent: true))
        let p = ResumePage(keeper: keeper)
        p.ask(.get, 0).refuse(.unanswered)
        p.run(16_000)
        p.focus()
        p.ask(.get, 1).answer(answerOf(["m1", "m2"], 1, 20, kept: keptOf(["m1", "m2"], 1, 20, rev: 3)))
        p.run(0)
        #expect(p.restored(1)?.ids == ["m1", "m2"])
        #expect(p.said == ["Picked up from your Mac"])
        #expect(p.asked(.full).isEmpty && p.asked(.at).isEmpty)
        #expect(keeper.row?.unsent == false)
    }

    @Test func aSaveDeadwaxDidntAnswerWaitsForTheAskAtTheReturnToo() {
        // the same rule within one run of the app: a save that failed is sent at the next return only after the GET
        let keeper = FakeQueueKeeper()
        let p = ResumePage(keeper: keeper)
        p.set(startUpNext(queueOf(["a", "b"]), start: 0))
        p.run(2_100)
        p.ask(.full, 0).refuse(.unanswered)
        p.run(16_000)
        p.focus()
        #expect(p.server.asks.map(\.kind) == [.get, .full, .get])
        p.ask(.get, 1).answer(answerOf(["a"], 0, 0, changedBy: ""))
        p.run(0)
        #expect(p.server.asks.map(\.kind) == [.get, .full, .get, .full])
        #expect(p.ask(.full, 1).full?.ids == ["a", "b"])
    }

    // MARK: a 401

    @Test func a401HoldsTheKeptSaveForTheSamePerson() {
        let keeper = FakeQueueKeeper(keptRow(["k1", "k2"], 0, 10, rev: 2, seen: "kept:2", unsent: true))
        let p = ResumePage(answer: ownAnswer(["k1"], 0, 0, rev: 2), keeper: keeper)
        p.ask(.full, 0).refuse(.status(401))
        p.run(0)
        #expect(keeper.row?.unsent == true)
        // signed out under this session: a return asks, and sends nothing
        p.run(16_000)
        p.focus()
        p.ask(.get, 1).answer(ownAnswer(["k1"], 0, 0, rev: 2))
        p.run(0)
        #expect(p.asked(.full).count == 1)
        #expect(keeper.row?.unsent == true)
        // signed in again as the same person (the session moves): the next return sends it, and it is cleared
        p.session = 2
        p.run(16_000)
        p.focus()
        p.ask(.get, 2).answer(ownAnswer(["k1"], 0, 0, rev: 2))
        p.run(0)
        #expect(p.asked(.full).count == 2)
        #expect(p.ask(.full, 1).full?.ids == ["k1", "k2"])
        p.ask(.full, 1).ok(3, 3)
        p.run(0)
        #expect(keeper.row?.unsent == false)
    }

    @Test func theBreakGlassAdminKeepsNothing() {
        let keeper = FakeQueueKeeper()
        let p = ResumePage(keeper: keeper)
        p.set(startUpNext(queueOf(["a"]), start: 0))
        p.run(2_100)
        p.ask(.full, 0).ok(nil, nil)
        p.run(0)
        #expect(keeper.row == nil)
    }

    // MARK: the row

    @Test func theKeptQueueRoundTripsThroughTheStoreAndPutsBackExactly() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deadwax-kept-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let db = try DownloadDatabase(path: folder.appendingPathComponent("downloads.sqlite").path)
        // an album with a song added to play next, a song in: Up Next's account must come back whole
        let queue = withNext(startUpNext(queueOf(["1", "2", "3"], level: .album), start: 1), queueOf(["x"], level: .track))
        let kept = QueueKept(queue: queue, position: 61.5, device: "phone-device-1", label: Resume.label, rev: 4,
                             idsRev: 3, shared: false, seen: "kept:4", unsent: true, size: { $0 == "2" ? 31_000_000 : nil })
        try db.keepResume(kept, at: 1)
        #expect(try db.keptQueue()?.kind == QueueKept.unsentKind)
        let read = try #require(try db.keptResume())
        #expect(read == kept)
        #expect(read.answer.tracks.first { $0.id == "2" }?.size == 31_000_000)
        let back = try #require(resumed(read.answer, setting: .auto, device: "phone-device-1"))
        #expect(queueDifference(back.queue, queue) == nil)
        #expect(back.position == 61.5)
        #expect(back.from == nil)
        // sent: the same row, another kind
        var sent = read
        sent.unsent = false
        try db.keepResume(sent, at: 2)
        #expect(try db.keptQueue()?.kind == QueueKept.sentKind)
        #expect(try db.keptResume()?.unsent == false)
        // forgotten; and a row another build wrote is let go, not misread
        try db.keepResume(nil, at: 3)
        #expect(try db.keptResume() == nil)
        try db.keepQueue(kind: "queue", body: Data([1]), at: 4)
        #expect(try db.keptResume() == nil)
    }
}
