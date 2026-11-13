import Foundation
import Testing
@testable import DeadwaxCore

/// The fader's half of slice 4 (notes/ios-specs/turntable.md 5.1, 5.2; James's answers, 2026-11-13): the speed kept as
/// the web keeps it, what the engine is told (exact again at 1x on a let-go), the engine's restart kept off the screen
/// and the lock screen, the lock screen told a drag's speed, the pace Debug measures, and plays counted at speed.
@Suite struct SpeedControlTests {
    // MARK: kept on the phone (persisted.ts readPlayerSpeed, writePlayerSpeed)

    @Test func theKeptSpeedIsReadByTheWebsRule() {
        #expect(PlaySpeed.storageKey == "deadwax-player-speed")
        #expect(PlaySpeed.read(nil) == 1 && PlaySpeed.read("") == 1 && PlaySpeed.read("   ") == 1)
        #expect(PlaySpeed.read("1.25") == 1.25 && PlaySpeed.read(" 0.5 ") == 0.5 && PlaySpeed.read("2") == 2 && PlaySpeed.read("0.25") == 0.25)
        //? in hundredths: what the readout shows is what plays
        #expect(PlaySpeed.read("1.234") == 1.23)
        //? not a speed the player takes: 1x
        #expect(PlaySpeed.read("3") == 1 && PlaySpeed.read("0.2") == 1 && PlaySpeed.read("-1") == 1)
        #expect(PlaySpeed.read("fast") == 1 && PlaySpeed.read("1.5x") == 1 && PlaySpeed.read("NaN") == 1 && PlaySpeed.read("Infinity") == 1)
        //? JavaScript's Number reads these too
        #expect(PlaySpeed.read(".5") == 0.5 && PlaySpeed.read("+1.5") == 1.5 && PlaySpeed.read("15e-1") == 1.5)
        //? what the phone writes, it reads back
        for speed in [0.25, 0.5, 0.99, 1, 1.01, 1.25, 1.5, 2] {
            #expect(PlaySpeed.read(PlaySpeed.stored(speed)) == speed, "\(speed)")
        }
        #expect(PlaySpeed.stored(1) == "1" && PlaySpeed.stored(1.25) == "1.25" && PlaySpeed.stored(0.5) == "0.5")
    }

    // MARK: what the engine is told

    @Test func aDragThroughOneXStaysInTheChainAndTheLetGoThereIsExact() {
        var control = SpeedControl(speed: 1)
        #expect(control.atStart == nil, "at 1x the engine is never told a speed: the chain is never made")
        //? the first move off 1x: the lanes begun again into the chain
        do {
            let got = control.dragged(to: 1.03)
            #expect(got == .init(speed: 1.03, exact: false, restarts: true))
        }
        do {
            let got = control.dragged(to: 1.03)
            #expect(got == nil, "the same speed again: nothing")
        }
        do {
            let got = control.dragged(to: 1.1)
            #expect(got == .init(speed: 1.1, exact: false, restarts: false))
        }
        //? back through the detent: 1x in the chain, at rate 1 - no gap mid-drag
        do {
            let got = control.dragged(to: 1)
            #expect(got == .init(speed: 1, exact: false, restarts: false))
        }
        #expect(control.chained)
        //? and on through it the other way: leaving 1x again, may restart (a clear at 1x takes the lanes out)
        do {
            let got = control.dragged(to: 0.95)
            #expect(got == .init(speed: 0.95, exact: false, restarts: true))
        }
        do {
            let got = control.letGo()
            #expect(got == nil, "let go off 1x: the speed stays, nothing more to tell")
        }
        //? a second drag, let go on the mark: exact again - the file's own samples from there
        do {
            let got = control.dragged(to: 1)
            #expect(got == .init(speed: 1, exact: false, restarts: false))
        }
        do {
            let got = control.letGo()
            #expect(got == .init(speed: 1, exact: true, restarts: true))
        }
        #expect(!control.chained)
        do {
            let got = control.letGo()
            #expect(got == nil, "once")
        }
        //? a touch that never moved it, at 1x out of the chain: nothing
        do {
            let got = control.letGo()
            #expect(got == nil)
        }
    }

    @Test func aJumpToOneXIsALetGo() {
        var control = SpeedControl(speed: 1.5)
        #expect(control.atStart == .init(speed: 1.5, exact: false, restarts: false), "the kept speed, before anything plays")
        #expect(control.chained)
        //? the readout's tap, or the chip's
        do {
            let got = control.set(1)
            #expect(got == .init(speed: 1, exact: true, restarts: true))
        }
        do {
            let got = control.set(1)
            #expect(got == nil, "already the song's own samples")
        }
        //? a VoiceOver step off 1x and back onto it
        do {
            let got = control.set(1.01)
            #expect(got == .init(speed: 1.01, exact: false, restarts: true))
        }
        do {
            let got = control.set(1)
            #expect(got == .init(speed: 1, exact: true, restarts: true))
        }
        //? a jump onto 1x left in the chain by a drag (the drag's let-go not come yet): exact
        _ = control.dragged(to: 1.2)
        _ = control.dragged(to: 1)
        do {
            let got = control.set(1)
            #expect(got == .init(speed: 1, exact: true, restarts: true))
        }
        //? held to the range, in hundredths
        do {
            let got = control.set(9)
            #expect(got == .init(speed: 2, exact: false, restarts: true))
        }
        do {
            let got = control.set(0.1)
            #expect(got == .init(speed: 0.25, exact: false, restarts: false))
        }
        do {
            let got = control.set(.nan)
            #expect(got == .init(speed: 1, exact: true, restarts: true))
        }
        #expect(SpeedControl(speed: 7).speed == 2)
    }

    @Test func aDragTicksAsItCrossesIntoTheDetent() {
        #expect(PlaySpeed.ticks(from: 1.03, to: 1))
        #expect(PlaySpeed.ticks(from: 0.97, to: 1))
        #expect(!PlaySpeed.ticks(from: 1, to: 1), "already there")
        #expect(!PlaySpeed.ticks(from: 1, to: 1.03), "leaving it")
        #expect(!PlaySpeed.ticks(from: 1.2, to: 1.1))
    }

    // MARK: the restart kept off the screen

    @Test func theRestartsLoadingIsShownAsPlaying() {
        var hold = SpeedRestartHold()
        //? nothing asked: a loading shows
        hold.phase(loading: true, playing: false, entry: 3, at: 0)
        #expect(!hold.hiding)
        hold.phase(loading: false, playing: true, entry: 3, at: 0.1)
        //? the first move off 1x while entry 3 plays: its .loading then .playing
        hold.asked(entry: 3, at: 10)
        hold.phase(loading: true, playing: false, entry: 3, at: 10.004)
        #expect(hold.hiding)
        hold.phase(loading: false, playing: true, entry: 3, at: 10.02)
        #expect(!hold.hiding && hold.entry == nil, "playing again: the hold is done")
        //? a later loading of the same song (a real wait) shows
        hold.phase(loading: true, playing: false, entry: 3, at: 10.5)
        #expect(!hold.hiding)
    }

    @Test func aRestartThatTakesTooLongShows() {
        var hold = SpeedRestartHold()
        hold.asked(entry: 1, at: 0)
        hold.phase(loading: true, playing: false, entry: 1, at: 0.01)
        #expect(hold.hiding)
        do {
            let got = hold.expired(at: 0.5)
            #expect(!got)
        }
        #expect(hold.hiding)
        do {
            let got = hold.expired(at: SpeedRestartHold.seconds)
            #expect(got)
        }
        #expect(!hold.hiding)
        do {
            let got = hold.expired(at: 2)
            #expect(!got, "once")
        }
        //? a loading after the hold's time isn't the restart's
        hold.asked(entry: 1, at: 5)
        hold.phase(loading: true, playing: false, entry: 1, at: 6.5)
        #expect(!hold.hiding)
    }

    @Test func onlyTheEntryThatPlayedIsHeldAndOnlyItsLoading() {
        var hold = SpeedRestartHold()
        hold.asked(entry: 1, at: 0)
        //? another song loading (a skip in the same moment): shows
        hold.phase(loading: true, playing: false, entry: 2, at: 0.01)
        #expect(!hold.hiding)
        //? a pause, a failure or the end are never hidden, and end the hold
        hold.asked(entry: 1, at: 1)
        hold.phase(loading: false, playing: false, entry: 1, at: 1.01)
        #expect(!hold.hiding && hold.entry == nil)
        hold.phase(loading: true, playing: false, entry: 1, at: 1.02)
        #expect(!hold.hiding)
        //? a pause that comes while the restart's loading is hidden: shown at once, the hold over
        hold.asked(entry: 1, at: 2)
        hold.phase(loading: true, playing: false, entry: 1, at: 2.01)
        #expect(hold.hiding)
        hold.phase(loading: false, playing: false, entry: 1, at: 2.02)
        #expect(!hold.hiding && hold.entry == nil)
    }

    // MARK: the lock screen told the speed

    @Test func aDragsSpeedIsToldAtMostFourTimesASecondAndItsLastAlways() {
        var publishing = SpeedPublishing()
        do {
            let got = publishing.changed(at: 10)
            #expect(got == .now)
        }
        publishing.told(at: 10)
        do {
            let got = publishing.changed(at: 10.05)
            #expect(got == .at(10.25))
        }
        do {
            let got = publishing.changed(at: 10.1)
            #expect(got == .waiting)
        }
        do {
            let got = publishing.changed(at: 10.2)
            #expect(got == .waiting)
        }
        //? the waiting one tells them all
        publishing.told(at: 10.25)
        do {
            let got = publishing.changed(at: 10.6)
            #expect(got == .now)
        }
        publishing.told(at: 10.6)
        //? a pause told in between counts as told
        publishing.told(at: 11)
        do {
            let got = publishing.changed(at: 11.1)
            #expect(got == .at(11.25))
        }
    }

    // MARK: the pace (playSpeed.ts paceStep, paceOf)

    @Test func thePaceIsTakenOverTheLastEightSeconds() {
        var window: [PlaySpeed.PaceSample] = []
        window = PlaySpeed.paceStep(window, .init(media: 0.75, wall: 0.5))
        #expect(PlaySpeed.paceOf(window) == nil, "under two seconds of it")
        for _ in 0..<3 { window = PlaySpeed.paceStep(window, .init(media: 0.75, wall: 0.5)) }
        #expect(PlaySpeed.paceOf(window) == 1.5)
        //? steps that aren't playing are left out
        #expect(PlaySpeed.paceStep(window, .init(media: 1, wall: 0)) == window)
        #expect(PlaySpeed.paceStep(window, .init(media: -1, wall: 0.5)) == window)
        //? past eight seconds the oldest go: a change of speed shows within the window
        for _ in 0..<20 { window = PlaySpeed.paceStep(window, .init(media: 0.25, wall: 0.5)) }
        #expect(PlaySpeed.paceOf(window) == 0.5)
        let wall = window.reduce(0) { (sum: Double, step: PlaySpeed.PaceSample) -> Double in sum + step.wall }
        #expect(wall < PlaySpeed.paceWindowS + 0.5 && wall >= PlaySpeed.paceWindowS - 0.5)
    }

    // MARK: the fader's places in points

    @Test func theFadersSpanAndTheReadoutsTargetAreTheWebs() {
        let layout = TurntableLayout(width: 321)
        let span = layout.faderSpan
        //? the knob's whole travel and a knob's height: SpeedFader.tsx's SPAN_TOP and SPAN, of the stage's height
        #expect(abs(span.top - (150 - 6) / 368 * layout.height) < 1e-9 && abs(span.bottom - (318 + 6) / 368 * layout.height) < 1e-9)
        #expect(abs((span.bottom - span.top) - (layout.faderTravel + 12 / 368 * layout.height)) < 1e-9)
        #expect(layout.readoutTarget == 44, "a 321 pt plinth holds a tap's target")
        #expect(abs(TurntableLayout(width: 200).readoutTarget - 28) < 1e-9, "14% of a small one")
    }
}

/// Plays counted at the speed (turntable.md 5.2, "at 2x that comes in half the time"): the step is capped at the clock
/// times the speed, as the web's `rate: audio.playbackRate`.
@Suite struct PlaysAtSpeedTests {
    @Test func atTwoXHalfTheSongComesInHalfTheTime() {
        var tracker = ListenTracker()
        tracker.speedChanged(2)
        tracker.newListen(songID: "a", at: 0)
        _ = tracker.began(wallMs: 1)
        //? 100 s of a 200 s song in 50 s of the clock, read every second (a locked phone's sparse readings)
        var reports: [PlayReport] = []
        var position = 0.0, clock = 0.0
        while position < 100 - 1e-9 {
            position += 2
            clock += 1
            if let report = tracker.tick(position: position, monotonic: clock, duration: 200) { reports.append(report) }
        }
        #expect(tracker.listen.heard == 100)
        #expect(reports == [.played(songID: "a", atMs: 1)])
    }

    @Test func atOneXTheSameStepsCountLess() {
        //? what 2x would count without the speed: the cap at the clock (and its slack), which is why it is given
        var tracker = ListenTracker()
        tracker.newListen(songID: "a", at: 0)
        _ = tracker.began(wallMs: 1)
        var reports: [PlayReport] = []
        var position = 0.0, clock = 0.0
        while position < 100 - 1e-9 {
            position += 2
            clock += 1
            if let report = tracker.tick(position: position, monotonic: clock, duration: 200) { reports.append(report) }
        }
        #expect(tracker.listen.heard == 50 * (1 + PlayRule.slack))
        #expect(reports.isEmpty, "75 s heard of the 100 it needs")
    }

    @Test func aStepAcrossAChangeIsCappedAtTheFastestItSpanned() {
        var tracker = ListenTracker()
        tracker.speedChanged(2)
        tracker.newListen(songID: "a", at: 0)
        _ = tracker.began(wallMs: 1)
        _ = tracker.tick(position: 1, monotonic: 0.5, duration: 200)
        //? 2x, then back to 1x mid-step: the step played most of its half second at 2x - 1.4 s of the song, which 1x's
        //? cap (1 s with the slack) would cut
        tracker.speedChanged(1)
        _ = tracker.tick(position: 2.4, monotonic: 1, duration: 200)
        #expect(abs(tracker.listen.heard - 2.4) < 1e-9)
        //? and the next step is the new speed's
        _ = tracker.tick(position: 3.9, monotonic: 1.5, duration: 200)
        #expect(abs(tracker.listen.heard - (2.4 + 0.5 + PlayRule.slack)) < 1e-9)
    }

    @Test func theSpeedOutlivesAStopAndANewListen() {
        var tracker = ListenTracker()
        tracker.speedChanged(1.5)
        tracker.stop()
        #expect(tracker.rate == 1.5)
        tracker.newListen(songID: "b", at: 0)
        _ = tracker.began(wallMs: 1)
        _ = tracker.tick(position: 1.5, monotonic: 1, duration: 200)
        #expect(tracker.listen.heard == 1.5)
        //? a join across songs counts at the speed too
        let reports = tracker.join(into: "c", oldLength: 2.5, newPosition: 0.5, monotonic: 2, newDuration: 100, wallMs: 5)
        #expect(tracker.listen.heard == 0.5, "the new song's start")
        #expect(reports == [.nowPlaying(songID: "c")])
    }
}
