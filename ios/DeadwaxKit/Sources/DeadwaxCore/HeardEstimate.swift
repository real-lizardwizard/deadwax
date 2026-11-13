import Foundation

/// A reading of where the engine's render had got to: the frame on a lane's own sample count (in
/// the songs' frames), when it was read (host seconds; nil offline, where there is no clock), and the
/// output's latency then - how far the ear was behind the render.
public struct HeardReading: Sendable, Equatable {
    public var frame: Int64
    public var at: Double?
    public var latency: Double

    public init(frame: Int64, at: Double?, latency: Double) {
        self.frame = frame
        self.at = at
        self.latency = latency
    }
}

/// What the listener HEARS, from what the engine has rendered (notes/ios.md, "One heard position").
///
/// The render runs ahead of the ear by the output's latency (an IO buffer and the route's own:
/// tens of ms on the speaker, more on AirPods, about 2 s on AirPlay). Everything that reads a
/// position - the lock screen, the scrubber, the plays rule, a pause's resume point, resume's saves -
/// reads the heard one, so a pause and play goes on from the last sample heard, and the title changes
/// with the sound.
///
/// When iOS stops the output itself (a new route, a call, media services reset), the node's clock is
/// gone before the engine hears of it: where the ear was is estimated from the last reading - on from
/// it at the song's rate for the time since (never past what was scheduled, and not at all after more
/// than a second, when the reading is too old to say), less the OLD route's latency, whose samples
/// went with it.
///
/// Pure, so it is tested on Linux; the engine (DeadwaxAudio) only feeds it.
public enum HeardEstimate {
    /// Past this many seconds since a reading, it isn't carried on: the reading itself is used.
    public static let maxExtrapolation: Double = 1.0

    /// `seconds` at `rate`, to the nearest frame.
    public static func frames(_ seconds: Double, rate: Double) -> Int64 {
        guard seconds.isFinite, rate > 0 else { return 0 }
        return Int64((seconds * rate).rounded())
    }

    /// The frame heard while the render is at `rendered`: the output's latency behind it, never below 0.
    public static func heard(rendered: Int64, latency: Double, rate: Double) -> Int64 {
        max(rendered - frames(max(latency, 0), rate: rate), 0)
    }

    /// Where the render had got to by `now`: the reading carried on at `rate` for the time since (at
    /// most `maxExtrapolation` seconds - past it, the reading as it is), never past `end`, the end of
    /// what was scheduled. With no clock (`now` or the reading's time nil) it is the reading.
    public static func rendered(_ reading: HeardReading, now: Double?, rate: Double, end: Int64) -> Int64 {
        var frame = reading.frame
        if let now, let at = reading.at, rate > 0 {
            let since = now - at
            if since > 0, since <= maxExtrapolation {
                frame += Int64((since * rate).rounded(.down))
            }
        }
        return max(min(frame, max(end, reading.frame)), 0)
    }

    /// The frame heard when iOS stopped the output: `rendered`, less the latency of the route the
    /// reading was taken on.
    public static func atStop(_ reading: HeardReading, now: Double?, rate: Double, end: Int64) -> Int64 {
        heard(rendered: rendered(reading, now: now, rate: rate, end: end), latency: reading.latency, rate: rate)
    }

    /// The song's seconds that `latency` of output holds, rendered up to a reading at host time `at` (notes/ios-specs/
    /// turntable.md 5.2): each output second carries the speed it was rendered at, so the span is the speed summed
    /// over the latency before the reading - `changes` oldest first, each from its moment on, `before` the speed
    /// before the first.
    public static func songSeconds(latency: Double, at: Double, changes: [SpeedChange], before: Double) -> Double {
        guard latency > 0, latency.isFinite else { return 0 }
        let from = at - latency
        var speed = before
        for change in changes where change.at <= from { speed = change.speed }
        // the whole latency at the speed it began at, and each change within it from its moment to the reading
        var total = latency * speed
        for change in changes where change.at > from && change.at < at {
            total += (at - change.at) * (change.speed - speed)
            speed = change.speed
        }
        return total
    }
}

/// The speed a song plays at from host time `at` on (notes/ios-specs/turntable.md 5.2): `speed` of the song's seconds
/// to the output's second.
public struct SpeedChange: Sendable, Equatable {
    public var at: Double
    public var speed: Double

    public init(at: Double, speed: Double) {
        self.at = at
        self.speed = speed
    }
}
