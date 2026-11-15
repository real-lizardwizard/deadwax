import Foundation

/// The bars' played part between the player's readings (James, 15 Nov: "Can we make the progress bar smooth instead of
/// updating every half second?"; notes/ios.md "The bars, smooth").
///
/// The player reads the engine twice a second (its ticker), and the play bar's seek line and Now Playing's scrubber
/// stepped with it. They are drawn every frame now, and in between they don't ask the engine: its position is a hop to
/// its own queue that waits behind whatever that queue is doing - measured at 3 us a read when it is idle, and up to
/// 1.9 ms behind a song's start being decoded, which thirty times a second would be the main thread's to wait out.
/// Instead the bars carry on from the last reading at the speed it was taken at, and each reading corrects them:
/// forward at once, and never backwards by less than `holdWithin` - a reading behind what they showed is waited for,
/// the line standing still until the song catches it up.
///
/// Pure, so it is tested on Linux; PlayerModel feeds it (its `barPosition(at:)`).
public enum PlayClock {
    /// How far past a reading the bars carry on without another: two of the ticker's half seconds. A reading later than
    /// that (the main thread held up) stops them there rather than letting them run on unchecked.
    public static let reach = 1.0

    /// The least time between two of the bars' frames while they run: 30 a second, a fraction of a point's move a frame
    /// on a phone's width even at 2x.
    public static let frame = 1.0 / 30

    /// A reading behind what the bars showed by less than this is held to, not jumped back to. Between readings that is
    /// a few milliseconds (the render's quanta, a speed changed between two readings); at a seek's landing, the engine's
    /// first reading may be short of the target the bars held, and Scrub lets the target go once a reading is within
    /// `Scrub.landedWithin` of it - so this is that, and a seek never lands with a jump back. Further behind is a real
    /// move (a new route's latency, AirPlay's 2 s), and the bars go to it.
    public static let holdWithin = Scrub.landedWithin

    /// One reading of the engine, as the bars carry it on.
    public struct Reading: Equatable, Sendable {
        /// The engine's entry it is of (the bars use it only while that entry is the one heard).
        public let entry: Int
        /// Seconds into it, as the engine said.
        public let seconds: Double
        /// When it was taken (monotonic seconds).
        public let at: Double
        /// Seconds of the song a second of the clock: the speed it was taken at.
        public let rate: Double
        /// The least the bars show from it: what they showed when it came if that was ahead of it by less than
        /// `holdWithin`, else `seconds`.
        public let floor: Double

        public init(entry: Int, seconds: Double, at: Double, rate: Double, floor: Double) {
            self.entry = entry
            self.seconds = seconds
            self.at = at
            self.rate = rate
            self.floor = floor
        }
    }

    /// The reading of `entry` at `seconds`, taken at `at` playing at `rate`, when the bars showed `shown` of it.
    public static func reading(entry: Int, seconds: Double, at: Double, rate: Double, shown: Double) -> Reading {
        let behind = shown - seconds
        let floor = behind > 0 && behind < holdWithin ? shown : seconds
        return Reading(entry: entry, seconds: seconds, at: at, rate: rate.isFinite && rate > 0 ? rate : 0, floor: floor)
    }

    /// What the bars show at `now` from `reading`: its seconds carried on at its rate for the time since (none before
    /// it was taken, and at most `reach`), never under its floor. Only goes forward as `now` does.
    public static func shown(_ reading: Reading, now: Double) -> Double {
        let since = now.isFinite ? min(max(now - reading.at, 0), reach) : 0
        return max(reading.floor, reading.seconds + since * reading.rate)
    }

    /// The speed changed (the fader, the readout, the ••• menu): the bars carry on from where they are at `now`, at the
    /// new `rate` - with no jump, and no wait for the next reading to take the speed up.
    public static func atRate(_ reading: Reading, rate: Double, now: Double) -> Reading {
        let here = shown(reading, now: now)
        return Reading(entry: reading.entry, seconds: here, at: now.isFinite ? now : reading.at,
                       rate: rate.isFinite && rate > 0 ? rate : 0, floor: here)
    }
}
