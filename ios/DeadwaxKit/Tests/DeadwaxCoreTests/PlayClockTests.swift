import Testing
@testable import DeadwaxCore

// The bars drawn smooth between the player's readings (15 Nov, PlayClock): carried on at the speed, corrected at each
// reading, never back by less than a seek's landing.
@Suite struct PlayClockTests {
    @Test func betweenReadingsTheBarsCarryOnAtTheSpeed() {
        let one = PlayClock.reading(entry: 3, seconds: 10, at: 100, rate: 1, shown: 10)
        #expect(PlayClock.shown(one, now: 100) == 10)
        #expect(PlayClock.shown(one, now: 100.25) == 10.25)
        let half = PlayClock.reading(entry: 3, seconds: 10, at: 100, rate: 0.5, shown: 10)
        #expect(PlayClock.shown(half, now: 100.5) == 10.25)
        let double = PlayClock.reading(entry: 3, seconds: 10, at: 100, rate: 2, shown: 10)
        #expect(PlayClock.shown(double, now: 100.5) == 11)
    }

    @Test func withNoReadingTheyStopAtTheReach() {
        let one = PlayClock.reading(entry: 0, seconds: 10, at: 100, rate: 1, shown: 10)
        #expect(PlayClock.shown(one, now: 101) == 11)
        #expect(PlayClock.shown(one, now: 130) == 11)
    }

    @Test func aTimeBeforeTheReadingIsTheReading() {
        let one = PlayClock.reading(entry: 0, seconds: 10, at: 100, rate: 1, shown: 10)
        #expect(PlayClock.shown(one, now: 99) == 10)
        #expect(PlayClock.shown(one, now: .nan) == 10)
    }

    @Test func aReadingAheadIsGoneToAtOnce() {
        let one = PlayClock.reading(entry: 0, seconds: 10.6, at: 100.5, rate: 1, shown: 10.45)
        #expect(one.floor == 10.6)
        #expect(PlayClock.shown(one, now: 100.5) == 10.6)
    }

    @Test func aReadingBehindIsWaitedForNotJumpedBackTo() {
        // the bars had carried on to 10.52; the engine says 10.49
        let one = PlayClock.reading(entry: 0, seconds: 10.49, at: 100.5, rate: 1, shown: 10.52)
        #expect(PlayClock.shown(one, now: 100.5) == 10.52)
        #expect(PlayClock.shown(one, now: 100.52) == 10.52)
        // and on once the song has caught them up
        let later = PlayClock.shown(one, now: 100.6)
        #expect(abs(later - 10.59) < 1e-9)
    }

    @Test func aSeekLandingShortOfItsTargetHoldsTheTarget() {
        // the bars held the seek's target, 60; the engine's first reading there is 59.2
        let one = PlayClock.reading(entry: 0, seconds: 59.2, at: 200, rate: 1, shown: 60)
        #expect(PlayClock.shown(one, now: 200) == 60)
        #expect(PlayClock.shown(one, now: 200.5) == 60)
        #expect(abs(PlayClock.shown(one, now: 201) - 60.2) < 1e-9)
    }

    @Test func farBehindIsARealMoveAndGoneTo() {
        // a new route's latency, two seconds of it
        let one = PlayClock.reading(entry: 0, seconds: 30, at: 300, rate: 1, shown: 32)
        #expect(one.floor == 30)
        #expect(PlayClock.shown(one, now: 300) == 30)
    }

    @Test func aSpeedChangedGoesOnFromWhereTheyAre() {
        let one = PlayClock.reading(entry: 2, seconds: 10, at: 100, rate: 1, shown: 10)
        let faster = PlayClock.atRate(one, rate: 2, now: 100.25)
        #expect(faster.entry == 2)
        #expect(PlayClock.shown(faster, now: 100.25) == 10.25)
        #expect(PlayClock.shown(faster, now: 100.5) == 10.75)
        // standing still for a reading behind them: on from where they stand
        let held = PlayClock.reading(entry: 2, seconds: 59.2, at: 200, rate: 1, shown: 60)
        let slower = PlayClock.atRate(held, rate: 0.5, now: 200.2)
        #expect(PlayClock.shown(slower, now: 200.2) == 60)
        #expect(abs(PlayClock.shown(slower, now: 201) - 60.4) < 1e-9)
    }

    @Test func noRateStandsStill() {
        let stopped = PlayClock.reading(entry: 0, seconds: 5, at: 0, rate: 0, shown: 5)
        #expect(PlayClock.shown(stopped, now: 0.5) == 5)
        let nonsense = PlayClock.reading(entry: 0, seconds: 5, at: 0, rate: .nan, shown: 5)
        #expect(PlayClock.shown(nonsense, now: 0.5) == 5)
    }

    @Test func aWaitHoldsTheBarsWhereTheyWere() {
        // a speed's restart still loading past its hold, at 2x: the bars had carried the last reading, 60, on to 60.5
        let reading = PlayClock.reading(entry: 2, seconds: 60, at: 10, rate: 2, shown: 60)
        let held = PlayClock.held(reading, now: 10.25)
        #expect(PlayClock.shown(held, now: 10.25) == 60.5)
        // and there they stay through the wait - never back to the reading's 60
        #expect(PlayClock.shown(held, now: 11) == 60.5)
        #expect(PlayClock.shown(held, now: 14) == 60.5)
        // held again, at each of the wait's ticks, it stays
        let again = PlayClock.held(held, now: 12)
        #expect(PlayClock.shown(again, now: 13) == 60.5)
    }

    @Test func throughAWaitAndAfterItTheyNeverGoBack() {
        // PlayerModel's way through a wait: each tick reads the engine stood at the restart's 60.125, a reading behind
        // what the bars drew, and holds it; after three, the song plays on from there at 2x
        var reading = PlayClock.held(PlayClock.reading(entry: 2, seconds: 60, at: 10, rate: 2, shown: 60), now: 10.25)
        var last = PlayClock.shown(reading, now: 10.25)
        var backwards = 0
        for tick in 1...6 {
            let at = 10.25 + Double(tick) * 0.5
            let shown = PlayClock.shown(reading, now: at)
            if shown < last { backwards += 1 }
            last = shown
            let waiting = tick <= 3
            let engine = waiting ? 60.125 : 60.125 + (at - 11.75) * 2
            reading = PlayClock.reading(entry: 2, seconds: engine, at: at, rate: 2, shown: shown)
            if waiting { reading = PlayClock.held(reading, now: at) }
            for frame in 1..<15 {
                let drawn = PlayClock.shown(reading, now: at + Double(frame) / 30)
                if drawn < last { backwards += 1 }
                last = drawn
            }
        }
        #expect(backwards == 0)
        // and on with the song after it: 63.125 at the last tick, carried on half a second's frames at 2x
        #expect(last > 63)
    }

    /// The engine as the ticker reads it - its heard position a few milliseconds either way of the truth, and its own
    /// clock 0.2 % slow against the phone's - and the bars drawn at 30 frames a second between: they never go back, and
    /// never stray from the song by more than a frame's worth and the readings' wobble.
    @Test func overManyReadingsTheyNeverGoBackAndKeepToTheSong() {
        let wobble: [Double] = [0.004, -0.006, 0.002, -0.003, 0.007, -0.005, 0.001, -0.007]
        var reading = PlayClock.reading(entry: 1, seconds: 0, at: 0, rate: 1, shown: 0)
        var last = 0.0
        var backwards = 0
        var worst = 0.0
        for tick in 1...240 {
            let at = Double(tick) * 0.5
            for frame in 0..<15 {
                let now = at - 0.5 + Double(frame) / 30
                let shown = PlayClock.shown(reading, now: now)
                if shown < last { backwards += 1 }
                worst = max(worst, abs(shown - now * 0.998))
                last = shown
            }
            let engine = at * 0.998 + wobble[tick % wobble.count]
            reading = PlayClock.reading(entry: 1, seconds: engine, at: at, rate: 1, shown: PlayClock.shown(reading, now: at))
        }
        #expect(backwards == 0)
        #expect(worst < 0.02)
    }
}
