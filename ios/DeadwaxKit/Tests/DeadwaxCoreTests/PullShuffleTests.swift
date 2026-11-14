import Testing
@testable import DeadwaxCore

/// Pull to shuffle's machine (phase4-library.md 2.8): idle, pulling, armed at the line, disarmed under its slack,
/// released by a lift while armed and ready - the shuffle starting in that call - and at rest after; a bounce no finger
/// made never pulling; nothing arming while a release couldn't shuffle. Every mutating call is made before its
/// `#expect`, never inside one.
@Suite struct PullShuffleTests {
    /// Moves fed in order, the events they gave.
    private func drive(_ pull: inout PullShuffle, _ moves: [Double], touching: Bool = true,
                       ready: Bool = true) -> [PullShuffle.Event] {
        var events: [PullShuffle.Event] = []
        for move in moves {
            if let event = pull.moved(move, touching: touching, ready: ready) { events.append(event) }
        }
        return events
    }

    @Test func theLineAndItsSlack() {
        #expect(PullShuffle.line == 110 && PullShuffle.slack == 10)
    }

    @Test func pullingGrowsTowardsTheLineAndArmsAtIt() {
        var pull = PullShuffle()
        #expect(pull.phase == .idle && pull.progress == 0 && !pull.shown)
        var events = drive(&pull, [0, -4])
        #expect(events.isEmpty && pull.phase == .idle, "at rest, or pushed up: nothing")
        events = drive(&pull, [11])
        #expect(events.isEmpty && pull.phase == .pulling(0.1))
        #expect(pull.shown && pull.progress == 0.1)
        events = drive(&pull, [55])
        #expect(events.isEmpty && pull.phase == .pulling(0.5))
        events = drive(&pull, [109.9])
        #expect(events.isEmpty, "a point under the line: no tick")
        #expect(pull.progress < 1)
        events = drive(&pull, [110])
        #expect(events == [.armed] && pull.phase == .armed && pull.progress == 1)
        events = drive(&pull, [130, 160, 111])
        #expect(events.isEmpty, "one tick per arming, however far it goes")
        #expect(pull.phase == .armed)
    }

    @Test func pulledBackUnderTheSlackItDisarms() {
        var pull = PullShuffle()
        var events = drive(&pull, [50, 120])
        #expect(events == [.armed])
        events = drive(&pull, [100])
        #expect(events.isEmpty && pull.phase == .armed, "at line - slack: still armed")
        events = drive(&pull, [99.5])
        #expect(events.isEmpty && pull.phase == .pulling(99.5 / 110))
        events = drive(&pull, [105, 109])
        #expect(events.isEmpty, "back over the slack, under the line: no tick")
        events = drive(&pull, [110])
        #expect(events == [.armed], "the line again: a second tick")
        events = drive(&pull, [0])
        #expect(events.isEmpty && pull.phase == .idle, "back at rest with the finger down: idle")
    }

    @Test func aLiftWhileArmedShufflesAndRestsAfter() {
        var pull = PullShuffle()
        _ = drive(&pull, [40, 115])
        var lifted = pull.lifted(ready: true)
        #expect(lifted == .shuffle)
        #expect(pull.phase == .released && pull.progress == 1)
        lifted = pull.lifted(ready: true)
        #expect(lifted == nil, "a second lift shuffles nothing")
        var events = drive(&pull, [90, 40, 3], touching: false)
        #expect(events.isEmpty && pull.phase == .released, "released all the way back")
        events = drive(&pull, [200], touching: true)
        #expect(events.isEmpty && pull.phase == .released, "a new pull before it is at rest does nothing")
        events = drive(&pull, [0], touching: false)
        #expect(events.isEmpty && pull.phase == .idle)
        events = drive(&pull, [30, 120])
        #expect(events == [.armed], "and then pulls afresh")
    }

    @Test func aLiftBeforeTheLineShufflesNothing() {
        var pull = PullShuffle()
        _ = drive(&pull, [30, 80])
        let lifted = pull.lifted(ready: true)
        #expect(lifted == nil && pull.phase == .pulling(80 / 110))
        var events = drive(&pull, [60, 20], touching: false)
        #expect(events.isEmpty && pull.phase == .pulling(20 / 110), "the graphic follows the page back")
        events = drive(&pull, [130], touching: false)
        #expect(events.isEmpty && pull.phase == .pulling(1), "no finger: never armed, past the line or not")
        events = drive(&pull, [0], touching: false)
        #expect(events.isEmpty && pull.phase == .idle)
    }

    @Test func aTouchTheSystemTookNeverShuffles() {
        var pull = PullShuffle()
        let armed = drive(&pull, [40, 120])
        #expect(armed == [.armed])
        pull.interrupted()
        #expect(pull.phase == .idle && !pull.shown, "a call or Siri over an armed pull: nothing drawn")
        let lifted = pull.lifted(ready: true)
        #expect(lifted == nil, "and the finger's going shuffles nothing")
        // pulling, interrupted: the same
        var half = PullShuffle()
        _ = drive(&half, [60])
        half.interrupted()
        #expect(half.phase == .idle)
        // released already: the shuffle has started, and stays so until the page is at rest
        var done = PullShuffle()
        _ = drive(&done, [120])
        let started = done.lifted(ready: true)
        #expect(started == .shuffle)
        done.interrupted()
        #expect(done.phase == .released)
        // after it, a pull from rest starts afresh
        var again = PullShuffle()
        _ = drive(&again, [120])
        again.interrupted()
        let rest = drive(&again, [0])
        let afresh = drive(&again, [30, 115])
        #expect(rest.isEmpty && afresh == [.armed])
    }

    @Test func aBounceNoFingerMadeNeverPulls() {
        var pull = PullShuffle()
        var events = drive(&pull, [20, 140, 60], touching: false)
        #expect(events.isEmpty)
        #expect(pull.phase == .idle && !pull.shown, "nothing drawn while it bounces")
        events = drive(&pull, [0], touching: false)
        #expect(events.isEmpty)
        #expect(pull.phase == .idle && !pull.shown)
        let lifted = pull.lifted(ready: true)
        #expect(lifted == nil && pull.phase == .idle)
    }

    @Test func notReadyItNeverArms() {
        var pull = PullShuffle()
        let events = drive(&pull, [30, 110, 180], ready: false)
        #expect(events.isEmpty)
        #expect(pull.phase == .pulling(1), "the full ring, never the disc")
        let lifted = pull.lifted(ready: false)
        #expect(lifted == nil && pull.phase == .pulling(1))
        // ready again mid-pull: the next move arms
        var later = PullShuffle()
        _ = drive(&later, [120], ready: false)
        let armed = drive(&later, [121], ready: true)
        #expect(armed == [.armed])
        // armed, then a release that couldn't shuffle: nothing
        var lost = PullShuffle()
        _ = drive(&lost, [120])
        let lostLift = lost.lifted(ready: false)
        #expect(lostLift == nil && lost.phase == .pulling(1))
        // armed, and unready while still held: back to the full ring
        var unready = PullShuffle()
        _ = drive(&unready, [120])
        let held = drive(&unready, [125], ready: false)
        #expect(held.isEmpty && unready.phase == .pulling(1))
    }

    @Test func aMoveThatIsNoNumberIsRest() {
        var pull = PullShuffle()
        _ = drive(&pull, [50])
        var events = drive(&pull, [.nan])
        #expect(events.isEmpty && pull.phase == .idle)
        _ = drive(&pull, [50, 120])
        events = drive(&pull, [.infinity])
        #expect(events.isEmpty && pull.phase == .idle)
    }

    @Test func resetDrawsNothing() {
        var pull = PullShuffle()
        _ = drive(&pull, [120])
        pull.reset()
        let lifted = pull.lifted(ready: true)
        #expect(pull.phase == .idle && lifted == nil)
    }

    @Test func theGraphicsWords() {
        #expect(PullShuffleWords.line(.pulling(0.4), can: .ready) == "Pull to shuffle")
        #expect(PullShuffleWords.line(.idle, can: .ready) == "Pull to shuffle")
        #expect(PullShuffleWords.line(.armed, can: .ready) == "Release to shuffle")
        #expect(PullShuffleWords.line(.released, can: .ready) == "Shuffling")
        #expect(PullShuffleWords.line(.released, can: .downloads) == "Shuffling")
        #expect(PullShuffleWords.line(.pulling(0.4), can: .downloads) == "Pull to shuffle your downloads")
        #expect(PullShuffleWords.line(.armed, can: .downloads) == "Release to shuffle your downloads")
        #expect(PullShuffleWords.line(.pulling(1), can: .gettingReady) == "Getting ready\u{2026}")
        #expect(PullShuffleWords.line(.pulling(1), can: .failed("Couldn't get your songs ready to shuffle"))
                == "Couldn't get your songs ready to shuffle")
        #expect(PullShuffleWords.line(.pulling(0.2), can: .nothingHere) == "Nothing on this phone to shuffle")
        #expect(PullShuffleWords.line(.pulling(0.2), can: .none) == "", "nothing to shuffle: nothing drawn")
    }
}
