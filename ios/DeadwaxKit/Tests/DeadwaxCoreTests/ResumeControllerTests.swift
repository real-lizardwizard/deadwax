import Foundation
import Testing
@testable import DeadwaxCore

// The controller against resume.sim.cjs's checks of the web's hook (ui/src/app/useResume.ts), scenario for scenario
// and millisecond for millisecond where the phone does what the page does; the page's beacons, keepalive budget and
// focus grace have no phone counterpart (D5, notes/ios.md), and the phone asks for no album after a pick-up.

@Suite struct ResumeControllerTests {
    /// sim: a page that played two songs here and paused, both saves answered.
    static func playedThenPaused() -> ResumePage {
        let p = ResumePage()
        p.server.asks.removeAll()
        p.set(startUpNext(queueOf(["1", "2"]), start: 0), playing: true)
        p.play(2_250)
        p.ask(.full, 0).ok(7, 7)
        p.play(5_000)
        p.set(p.player.queue, playing: false)
        p.run(10)
        p.ask(.at, 0).ok(8, 7)
        p.run(20_000)
        return p
    }

    // MARK: putting back on open

    @Test func onOpenTheQueueIsPutBackPausedAndNothingSaved() {
        let p = ResumePage(answer: answerOf(["1", "2", "3"], 1, 95, kept: keptOf(["1", "2", "3"], 1, 95)))
        #expect(p.asked(.get).count == 1)
        #expect(p.player.restored.count == 1)
        #expect(p.player.restored.first?.ids == ["1", "2", "3"] && p.player.restored.first?.index == 1 && p.player.restored.first?.position == 95)
        p.draw()
        #expect(p.said == ["Picked up from your Mac"])
        p.run(120_000)
        p.draw()
        p.controller.background()
        p.controller.background()
        p.focus()
        p.run(10)
        #expect(p.asked(.full).count + p.asked(.at).count == 0, "nothing saved for a queue merely put back")
    }

    @Test func aQueuePutBackMidSongIsTheListenCarryingOn() { // useResume's take: continuing(kept && position > 0)
        // deadwax's own record, put back 95 s in: its next start of that entry is no new start (play history)
        let p = ResumePage(answer: answerOf(["1", "2", "3"], 1, 95, kept: keptOf(["1", "2", "3"], 1, 95)))
        #expect(p.player.continued.count == 1)
        let put = p.player.continued.first ?? nil
        #expect(put?.index == 1 && put?.upNext?.id == p.player.queue.upNext?.id && put?.upNext?.id.isEmpty == false)
        // put back at its start, or another app's queue (no record of deadwax's): none
        let atStart = ResumePage(answer: answerOf(["1", "2"], 0, 0, kept: keptOf(["1", "2"], 0, 0)))
        #expect(atStart.player.continued.count == 1 && atStart.player.continued[0] == nil)
        let elsewhere = ResumePage(answer: answerOf(["1", "2"], 0, 50, changedBy: "Symfonium"))
        #expect(elsewhere.player.restored.count == 1 && elsewhere.player.continued.count == 1 && elsewhere.player.continued[0] == nil)
    }

    @Test func thisDevicesOwnQueueBackSaysNothing() {
        let p = ResumePage(answer: answerOf(["1", "2"], 0, 10, kept: keptOf(["1", "2"], 0, 10, device: "phone-device-1")))
        #expect(p.player.restored.count == 1 && p.said.isEmpty)
    }

    @Test func aTapBeforeTheAnswerWins() {
        let p = ResumePage()
        let tapped = startUpNext(queueOf(["9"]), start: 0)
        p.set(tapped, playing: true)
        p.ask(.get, 0).answer(answerOf(["1", "2"], 0, 50, kept: keptOf(["1", "2"], 0, 50)))
        p.run(100)
        #expect(p.player.restored.isEmpty && p.said.isEmpty && p.player.queue == tapped)
    }

    @Test func nothingIsPutBackWhileMusicPlaysOrForAnEmptyAnswer() {
        let playing = ResumePage(answer: answerOf(["1"], 0, 5, changedBy: "Symfonium"), playing: true)
        #expect(playing.player.restored.isEmpty)
        let empty = ResumePage(answer: answerOf([], nil, 0, changedBy: ""))
        #expect(empty.player.restored.isEmpty && empty.said.isEmpty)
        let failed = ResumePage()
        failed.ask(.get, 0).refuse(.status(502))
        failed.run(10)
        #expect(failed.player.restored.isEmpty)
    }

    // MARK: saving as it plays

    @Test func whatItSavesAsItPlays() throws {
        let p = ResumePage()
        p.server.asks.removeAll()
        let list = queueOf(["1", "2", "3", "4"])
        p.player.at = 0
        p.set(startUpNext(list, start: 0), playing: true)
        p.play(1_750)
        #expect(p.server.asks.isEmpty, "a tap played an album: nothing yet, 1.75 s on")
        p.play(500)
        let full = try #require(p.asked(.full).first?.full)
        #expect(p.asked(.full).count == 1)
        #expect(full.ids == ["1", "2", "3", "4"] && full.index == 0 && full.device == "phone-device-1" && full.label == "iPhone")
        #expect(full.snapshot != nil)
        p.ask(.full, 0).ok(1, 1)
        p.play(20_000)
        #expect(p.server.asks.count == 1, "nothing more for 20 s of playing")
        p.play(10_000)
        #expect(p.asked(.at).count == 1 && p.ask(.at, 0).at?.ids_rev == 1 && p.ask(.at, 0).at?.index == 0, "at 30 s")
        p.ask(.at, 0).ok(2, 1)

        p.player.at = 0
        p.set(p.player.queue.at(1))
        p.play(750, from: 0)
        #expect(p.asked(.at).count == 1, "a song change: nothing at once")
        p.play(500, from: 0.75)
        #expect(p.asked(.at).count == 2 && p.ask(.at, 1).at?.index == 1, "a second after it, naming the next song")
        p.ask(.at, 1).ok(3, 1)

        p.play(5_000, from: 1.25)
        p.set(p.player.queue, playing: false)
        p.run(10)
        #expect(p.asked(.at).count == 3 && p.ask(.at, 2).at?.position == 6.25, "a pause: at once, at its second")
        p.ask(.at, 2).ok(4, 1)
        p.run(60_000)
        #expect(p.server.asks.count == 4, "then nothing while paused")

        p.report(120)
        p.run(500)
        #expect(p.server.asks.count == 4, "a scrub while paused: nothing at once")
        p.run(700)
        #expect(p.asked(.at).count == 4 && p.ask(.at, 3).at?.position == 120, "a second after it")
        p.ask(.at, 3).ok(5, 1)

        p.set(withNext(p.player.queue, [list[3]]))
        p.run(1_000)
        p.set(withLast(p.player.queue, [list[2]]))
        p.run(1_900)
        #expect(p.asked(.full).count == 1, "two edits a second apart: nothing until 2 s after the second")
        p.run(200)
        #expect(p.asked(.full).count == 2 && p.ask(.full, 1).full?.ids == ["1", "2", "4", "3", "3", "4"])
    }

    @Test func thirtySecondsAreCountedByReportsNotATimer() {
        let p = ResumePage()
        p.server.asks.removeAll()
        p.set(startUpNext(queueOf(["1", "2"]), start: 0), playing: true)
        p.run(2_100)
        p.ask(.full, 0).ok(1, 1)
        p.player.at = 70
        p.run(90_000)
        #expect(p.asked(.at).isEmpty)
        p.report(70.25)
        p.run(10)
        #expect(p.asked(.at).count == 1)
    }

    @Test func oneAtATimeAndA409SavesInFull() {
        let p = ResumePage()
        p.server.asks.removeAll()
        p.set(startUpNext(queueOf(["1", "2", "3"]), start: 0), playing: true)
        p.play(2_250)
        p.ask(.full, 0).ok(1, 1)
        p.set(p.player.queue.at(1))
        p.play(1_250, from: 0)
        #expect(p.asked(.at).count == 1)
        p.set(p.player.queue.at(2))
        p.play(1_250, from: 0)
        #expect(p.asked(.at).count == 1 && p.asked(.full).count == 1, "another due while the first is out: it waits")
        p.ask(.at, 0).refuse(.status(409))
        p.run(10)
        #expect(p.asked(.full).count == 2 && p.ask(.full, 1).full?.index == 2 && p.asked(.at).count == 1)
    }

    @Test func a422SavesInFullToo() {
        let p = ResumePage()
        p.server.asks.removeAll()
        p.set(startUpNext(queueOf(["1", "2", "3"]), start: 0), playing: true)
        p.play(2_250)
        p.ask(.full, 0).ok(1, 1)
        p.set(p.player.queue.at(1))
        p.play(1_250, from: 0)
        p.ask(.at, 0).refuse(.status(422))
        p.run(10)
        #expect(p.asked(.full).count == 2 && p.ask(.full, 1).full?.index == 1)
    }

    /// (review of the roll-back's port) A server before 2.1.18 takes a v1 snapshot alone and answers a v2 with a 422: the
    /// save is sent once more, at once, without its snapshot - the same songs, index and second - and kept; a second
    /// 422 is the failure it always was (tried again 30 s on), and a v1's 422 is never sent again without it.
    @Test func aV2SnapshotRefusedIsSentOnceMoreWithoutIt() throws {
        let p = ResumePage()
        p.server.asks.removeAll()
        let played = startUpNext(queueOf(["1", "2", "3"]), start: 0).at(2)
        let first1 = try #require(played.upNext?.marks[0].key)
        let rolled = try #require(jumpedTo(played, first1, .off)).queue
        p.set(rolled, playing: true)
        p.play(2_250)
        let first = p.ask(.full, 0)
        #expect(first.full?.snapshot?.hasPrefix(#"{"v":2,"#) == true, "rolled back: v2")
        first.refuse(.status(422))
        #expect(p.asked(.full).count == 2, "sent once more at once")
        let plain = p.ask(.full, 1)
        #expect(plain.full?.snapshot == nil && plain.full?.ids == first.full?.ids && plain.full?.index == first.full?.index
                && plain.full?.position == first.full?.position)
        plain.ok(3, 3)
        p.set(p.player.queue.at(1))
        p.play(1_250, from: 0)
        #expect(p.asked(.at).count == 1 && p.ask(.at, 0).at?.ids_rev == 3, "kept: the next song change saved by its position")
        //? refused again without it: the failure it was
        let q = ResumePage()
        q.server.asks.removeAll()
        q.set(rolled, playing: true)
        q.play(2_250)
        q.ask(.full, 0).refuse(.status(422))
        q.ask(.full, 1).refuse(.status(422))
        q.play(29_000)
        #expect(q.asked(.full).count == 2, "nothing more inside 30 s")
        q.play(1_500)
        #expect(q.asked(.full).count == 3 && q.ask(.full, 2).full?.snapshot?.hasPrefix(#"{"v":2,"#) == true, "then in full again")
        //? a v1 refused: not sent again without it
        let r = ResumePage()
        r.server.asks.removeAll()
        r.set(startUpNext(queueOf(["1", "2", "3"]), start: 0), playing: true)
        r.play(2_250)
        #expect(r.ask(.full, 0).full?.snapshot?.hasPrefix(#"{"v":1,"#) == true)
        r.ask(.full, 0).refuse(.status(422))
        r.run(10)
        #expect(r.asked(.full).count == 1)
    }

    @Test func goingToTheBackgroundSendsWhatIsDueAtOnce() {
        let p = ResumePage()
        p.server.asks.removeAll()
        let list = queueOf(["1", "2"])
        p.set(startUpNext(list, start: 0), playing: true)
        p.play(2_250)
        p.ask(.full, 0).ok(1, 1)
        p.play(5_000)
        p.controller.background()
        p.controller.background()
        #expect(p.asked(.at).count == 1 && p.ask(.at, 0).at?.ids_rev == 1 && (p.ask(.at, 0).at?.position ?? 0) > 7,
                "once, though the app heard of the background twice")
        p.set(withNext(p.player.queue, [list[1]]))
        p.controller.background()
        #expect(p.asked(.full).count == 2, "an edit then the background: a full save at once, the position save still out")
    }

    @Test func a401StopsSavingUntilTheNextSignInAndNoRevForGood() {
        let p = ResumePage()
        p.server.asks.removeAll()
        p.set(startUpNext(queueOf(["1", "2"]), start: 0), playing: true)
        p.play(2_250)
        p.ask(.full, 0).refuse(.status(401))
        p.play(60_000)
        #expect(p.asked(.full).count == 1)
        p.session = 2
        p.play(500)
        #expect(p.asked(.full).count == 2)
        p.ask(.full, 1).ok(nil, nil)
        p.run(10)
        #expect(p.controller.off)
        p.set(p.player.queue.at(1))
        p.play(60_000, from: 0)
        p.set(p.player.queue, playing: false)
        p.run(16_000)
        p.focus()
        p.run(100)
        #expect(p.server.asks.count == 2, "nothing saved or asked again, back at the front included")
    }

    @Test func aFailureIsTriedAgainAtTheNextTriggerAfterThirtySeconds() {
        let p = ResumePage()
        p.server.asks.removeAll()
        p.set(startUpNext(queueOf(["1", "2"]), start: 0), playing: true)
        p.play(2_250)
        p.ask(.full, 0).refuse(.unanswered)
        p.play(29_000)
        #expect(p.asked(.full).count == 1, "nothing inside 30 s of the failure")
        p.play(1_500)
        #expect(p.asked(.full).count == 2, "then the next report sends it")
    }

    // MARK: coming back to the front

    @Test func theFrontAsksAgainAtMostEvery15Seconds() {
        let p = ResumePage()
        p.ask(.get, 0).refuse(.status(502))
        p.run(100)
        p.focus()
        #expect(p.asked(.get).count == 1)
        p.run(15_000)
        p.focus()
        #expect(p.asked(.get).count == 2)
        p.ask(.get, 1).answer(answerOf(["1", "2"], 1, 30, kept: keptOf(["1", "2"], 1, 30)))
        p.run(10)
        #expect(p.player.restored.count == 1 && p.restored(0)?.ids == ["1", "2"] && p.restored(0)?.index == 1
                    && p.restored(0)?.position == 30)
        p.draw()
        p.run(16_000)
        p.focus()
        p.ask(.get, 2).answer(answerOf(["1", "2", "3"], 2, 12, kept: keptOf(["1", "2", "3"], 2, 12, rev: 9)))
        p.run(10)
        #expect(p.player.restored.count == 2 && p.restored(1)?.ids == ["1", "2", "3"] && p.said.last == "Picked up from your Mac")
        p.draw()
        p.run(16_000)
        p.focus()
        p.ask(.get, 3).answer(answerOf(["1", "2", "3"], 2, 12, kept: keptOf(["1", "2", "3"], 2, 12, rev: 9)))
        p.run(10)
        #expect(p.player.restored.count == 2 && p.said.count == 2, "the same answer: not put back or said twice")
    }

    @Test func pausedAfterPlayingHereOnlyWhatIsNewerElsewhere() {
        let p = Self.playedThenPaused()
        p.focus()
        #expect(p.asked(.get).count == 1)
        p.ask(.get, 0).answer(answerOf(["1", "2"], 0, 7.25, kept: keptOf(["1", "2"], 0, 7.25, rev: 9, device: "phone-device-1")))
        p.run(10)
        #expect(p.player.restored.isEmpty, "its own save the newest: kept as it is")
        p.set(p.player.queue, playing: true)
        p.run(16_000)
        p.focus()
        #expect(p.asked(.get).count == 1, "never asked while playing")
        p.set(p.player.queue, playing: false)
        p.run(10)
        p.run(16_000)
        p.focus()
        #expect(p.asked(.get).count == 2, "asked again, paused")
        p.set(p.player.queue.at(1))
        p.ask(.get, 1).answer(answerOf(["7"], 0, 5, changedBy: "Symfonium"))
        p.run(10)
        #expect(p.player.restored.isEmpty, "a tap while the ask was out: its answer dropped")
        p.run(2_000)
        #expect(p.asked(.at).count == 2, "the tap's song change saved")
        p.ask(.at, 1).ok(10, 7)
        p.run(16_000)
        p.focus()
        p.asked(.get).last?.answer(answerOf(["2"], 0, 77, changedBy: "Symfonium"))
        p.run(10)
        #expect(p.player.restored.map(\.ids) == [["2"]] && p.said.last == "Picked up from Symfonium")
    }

    @Test func loginsOffAPausedPlayerNeverTakesSomebodyElses() {
        let p = Self.playedThenPaused()
        p.focus()
        p.asked(.get).last?.answer(answerOf(["1", "2", "3"], 2, 12, shared: true, kept: keptOf(["1", "2", "3"], 2, 12, rev: 12)))
        p.run(10)
        #expect(p.player.restored.isEmpty)
        p.run(16_000)
        p.focus()
        #expect(p.asked(.get).count == 1, "known to be shared: not even asked again")
        p.set(p.player.queue, playing: true)
        p.run(16_000)
        p.focus()
        #expect(p.asked(.get).count == 1)
        p.set(p.player.queue, playing: false)
        p.run(10)
        let fulls = p.asked(.full).count
        p.set(withNext(p.player.queue, queueOf(["1"])))
        p.run(10)
        p.focus()
        #expect(p.asked(.full).count - fulls == 1 && p.asked(.get).count == 1, "unsaved changes: saved at once, nothing asked")
    }

    @Test func theNoticeOnceForTheSamePickUp() {
        let p = ResumePage(answer: answerOf(["1", "2", "3"], 1, 95, kept: keptOf(["1", "2", "3"], 1, 95, label: "iPhone")))
        p.draw()
        p.run(16_000)
        p.focus()
        p.ask(.get, 1).answer(answerOf(["1", "2", "3"], 1, 125, kept: keptOf(["1", "2", "3"], 1, 125, rev: 6, label: "iPhone")))
        p.run(10)
        p.draw()
        #expect(p.player.restored.map(\.position) == [95, 125] && p.said == ["Picked up from your iPhone"])
        p.run(16_000)
        p.focus()
        p.ask(.get, 2).answer(answerOf(["1", "2", "3"], 2, 5, kept: keptOf(["1", "2", "3"], 2, 5, rev: 7, label: "iPhone")))
        p.run(10)
        p.draw()
        #expect(p.player.restored.count == 3 && p.said.count == 1, "the next song there: the same pick-up")
        p.run(16_000)
        p.focus()
        p.ask(.get, 3).answer(answerOf(["4", "5"], 0, 5, kept: keptOf(["4", "5"], 0, 5, rev: 8, label: "iPhone")))
        p.run(10)
        p.draw()
        #expect(p.player.restored.count == 4 && p.said == ["Picked up from your iPhone", "Picked up from your iPhone"])
        p.run(16_000)
        p.focus()
        p.ask(.get, 4).answer(answerOf(["4", "5"], 0, 50, kept: keptOf(["4", "5"], 0, 50, rev: 9, device: "desk-device-3", label: "Mac")))
        p.run(10)
        #expect(p.player.restored.count == 5 && p.said.last == "Picked up from your Mac")
    }

    @Test func pickedUpPlayedHereThenTheSameSongsAgainIsSaidAgain() {
        let p = ResumePage(answer: answerOf(["1", "2", "3"], 1, 95, kept: keptOf(["1", "2", "3"], 1, 95, label: "iPhone")))
        p.draw()
        p.set(p.player.queue, playing: true)
        p.play(3_000, from: 95)
        p.set(p.player.queue, playing: false)
        p.run(10)
        p.ask(.at, 0).ok(6, 4)
        p.run(16_000)
        p.focus()
        p.asked(.get).last?.answer(answerOf(["1", "2", "3"], 2, 5, kept: keptOf(["1", "2", "3"], 2, 5, rev: 9, label: "iPhone")))
        p.run(10)
        #expect(p.player.restored.count == 2 && p.said == ["Picked up from your iPhone", "Picked up from your iPhone"])
    }

    // MARK: the review's cases (7a-7e)

    @Test func aRepeatOneRecordPutBackUnderRepeatOffSavesInFull() throws {
        let one = toppedUp(withRepeat(startUpNext(queueOf(["1", "2", "3"]), start: 0), .one), .one)
        let saving = toSave(one, position: 40)
        let kept = KeptQueue(rev: 5, ids_rev: 4, ids: saving.ids, index: 0, position: 40, snapshot: saving.snapshot,
                             device: "desk-device-2", label: "Mac")
        let p = ResumePage(answer: answerOf(saving.ids, 0, 40, kept: kept))
        p.draw()
        #expect(saving.ids.count == 3 + UpNext.repeatAhead && p.player.restored.first?.ids == ["1", "2", "3"])
        p.server.asks.removeAll()
        p.set(p.player.queue.at(1))
        p.run(1_200)
        #expect(p.asked(.full).count == 1 && p.asked(.at).isEmpty && p.ask(.full, 0).full?.ids == ["1", "2", "3"])
    }

    @Test func thirtySecondsCountFromPlayingStarting() {
        let p = Self.playedThenPaused()
        p.run(40_000)
        let before = p.asked(.at).count
        p.set(p.player.queue, playing: true)
        p.play(25_000)
        #expect(p.asked(.at).count - before == 0)
        p.play(6_000)
        #expect(p.asked(.at).count - before == 1)
    }

    @Test func anEditThenASongChangeWhilePausedIsOneFullSave() {
        let p = Self.playedThenPaused()
        let fulls = p.asked(.full).count
        let ats = p.asked(.at).count
        p.set(withNext(p.player.queue, queueOf(["9"])))
        p.run(1_500)
        p.player.at = 0
        p.set(p.player.queue.at(1))
        p.run(1_900)
        #expect(p.asked(.full).count - fulls == 0 && p.asked(.at).count - ats == 0)
        p.run(200)
        #expect(p.asked(.full).count - fulls == 1 && p.asked(.full).last?.full?.ids == ["1", "9", "2"]
                    && p.asked(.full).last?.full?.index == 1 && p.asked(.at).count - ats == 0)
    }

    @Test func aScrubbedPutBackQueueIsKept() {
        let p = ResumePage(answer: answerOf(["1", "2"], 0, 10, kept: keptOf(["1", "2"], 0, 10, device: "phone-device-1")))
        p.draw()
        p.server.asks.removeAll()
        p.report(120)
        p.run(1_200)
        #expect(p.asked(.at).count == 1 && p.ask(.at, 0).at?.position == 120)
        p.ask(.at, 0).ok(6, 4)
        p.run(16_000)
        p.focus()
        p.ask(.get, 0).answer(answerOf(["1", "2"], 0, 30, kept: keptOf(["1", "2"], 0, 30, rev: 7, device: "phone-device-1")))
        p.run(10)
        #expect(p.player.restored.count == 1 && p.player.at == 120)
    }

    @Test func aPutBackQueueMovedMoreThanHalfASecondIsNoLongerUntouched() { // onPosition: > 0.5 s lets it go
        func pickedUp(movedBy: Double) -> ResumePage {
            let p = ResumePage(answer: answerOf(["1", "2", "3"], 1, 95, kept: keptOf(["1", "2", "3"], 1, 95)))
            p.draw()
            p.report(95 + movedBy)
            p.run(16_000)
            p.focus()
            p.ask(.get, 1).answer(answerOf(["1", "2", "3"], 2, 5, kept: keptOf(["1", "2", "3"], 2, 5, rev: 4)))
            p.run(10)
            return p
        }
        // half a second: still the queue put back and untouched - deadwax's answer taken, though it is no newer
        let still = pickedUp(movedBy: 0.5)
        #expect(still.player.restored.count == 2 && still.restored(1)?.index == 2)
        // a second (too little to save): moved here - paused after a change, it takes only what is newer elsewhere,
        // which rev 4 isn't (the Mac's rev 5 was taken)...
        let moved = pickedUp(movedBy: 1)
        #expect(moved.player.restored.count == 1 && moved.asked(.full).isEmpty && moved.asked(.at).isEmpty)
        // ...and rev 9 is
        moved.run(16_000)
        moved.focus()
        moved.ask(.get, 2).answer(answerOf(["1", "2", "3"], 2, 5, kept: keptOf(["1", "2", "3"], 2, 5, rev: 9)))
        moved.run(10)
        #expect(moved.player.restored.count == 2 && moved.restored(1)?.index == 2)
    }

    // MARK: the phone's own

    @Test func stopLetsGoOfEverything() {
        let p = ResumePage()
        p.controller.stop()
        p.ask(.get, 0).answer(answerOf(["1"], 0, 5, changedBy: "Symfonium"))
        p.set(startUpNext(queueOf(["1", "2"]), start: 0), playing: true)
        p.play(5_000)
        p.focus()
        #expect(p.player.restored.isEmpty && p.asked(.full).isEmpty && p.asked(.get).count == 1)
    }

    @Test func onlyTheNewestAskIsRead() {
        let p = ResumePage()
        p.ask(.get, 0).refuse(.unanswered)
        p.run(15_000)
        p.focus()
        p.run(15_000)
        p.focus()
        #expect(p.asked(.get).count == 3)
        //? the older answer comes last: never read
        p.ask(.get, 2).answer(answerOf(["2"], 0, 0, changedBy: "Symfonium"))
        p.ask(.get, 1).answer(answerOf(["1"], 0, 0, changedBy: "Symfonium"))
        p.run(10)
        #expect(p.player.restored.map(\.ids) == [["2"]])
    }

    @Test func positionsAreSentClamped() throws {
        let p = ResumePage()
        p.server.asks.removeAll()
        p.player.at = -3
        p.set(startUpNext(queueOf(["1", "2"]), start: 0), playing: true)
        p.run(2_100)
        #expect(try #require(p.asked(.full).first?.full).position == 0)
    }
}
