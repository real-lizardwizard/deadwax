/// The platter's physics - the web's ui/src/lib/platter.ts, ported line for line (notes/ios-specs/turntable.md 3.3,
/// 4.2): a hand's speed from its samples, and the closed-form plans a let-go makes - a coast to rest under friction,
/// or the motor pulling the record back to speed - with where each puts the record at any moment. Every expression
/// keeps the web's order of operations, and the one transcendental pair it uses (exp, log) goes through `DeckMaths`,
/// so with `RecordedMaths` it answers the web's very bits (Fixtures/deck/platter.json, PlatterTests).

/// platter.ts's constants, and its sums that need no transcendental function.
public enum Platter {
    /// The motor's pull from rest to speed takes this long (platter.ts:49).
    public static let spinUpS = 0.4
    /// A record let go at speed 1 with the motor off coasts to rest in this long (:51).
    public static let spinDownS = 1.0
    /// The motor's pull, speeds a second (:54).
    public static let motorPull = 1 / spinUpS
    /// The friction's viscous part, a second (:57).
    public static let frictionViscous = 2.674
    /// A plan stops this short of the song's end (:64).
    public static let endMarginS = 0.25
    /// The hand's speed is taken over its last this many milliseconds (:67).
    public static let velocityWindowMs = 90.0
    /// The fastest a hand or a plan moves the song, speeds (:71).
    public static let maxSpeed = 24.0
    /// The record's face turns this many degrees a second of song (:74).
    public static let degreesPerSecond = 360 / TurntableGeometry.secondsPerTurn
    /// A let-go this soon after the last sample takes the speed at it (:128).
    public static let releaseTailMs = 40.0

    /// The record's speed as the voice plays it: the plan's own (platter.ts:78).
    @inlinable public static func voiceRate(_ speed: Double) -> Double { speed }

    /// Degrees of the record's face for seconds of song (:83).
    @inlinable public static func degreesFor(_ seconds: Double) -> Double { seconds * degreesPerSecond }

    // ----- the hand's speed (platter.ts:87-145)

    /// How far the hand had turned at `time`, read between its samples (:99).
    static func turnedAt(_ samples: [HandSample], _ time: Double) -> Double {
        guard let first = samples.first else { return 0 }
        if time <= first.time { return first.turned }
        for i in 1..<samples.count {
            let before = samples[i - 1], after = samples[i]
            if time <= after.time {
                let span = after.time - before.time
                return span > 0 ? before.turned + ((after.turned - before.turned) * (time - before.time)) / span : after.turned
            }
        }
        return samples[samples.count - 1].turned
    }

    /// The hand's speed at `time`, in speeds (1 is the song's own), over the last `windowMs` (:118).
    public static func handSpeed(_ samples: [HandSample], _ time: Double, windowMs: Double = velocityWindowMs) -> Double {
        if samples.count < 2 || !(windowMs > 0) { return 0 }
        let turn = turnedAt(samples, time) - turnedAt(samples, time - windowMs)
        let speed = (turn / (2 * Double.pi)) * TurntableGeometry.secondsPerTurn / (windowMs / 1000)
        return JSMath.max(-maxSpeed, JSMath.min(maxSpeed, speed))
    }

    /// The speed a let-go at `time` throws the record with (:138): the samples' own speed up to the last of them, slowed
    /// in proportion to a rest longer than the tail before the lift.
    public static func releaseSpeed(_ samples: [HandSample], _ time: Double, windowMs: Double = velocityWindowMs,
                                    tailMs: Double = releaseTailMs) -> Double {
        if samples.count < 2 || !(windowMs > 0) { return 0 }
        let last = samples[samples.count - 1].time
        let gap = JSMath.max(0, time - last)
        if gap >= windowMs { return 0 }
        let rested = JSMath.max(0, gap - tailMs) / JSMath.max(1e-9, windowMs - tailMs)
        return handSpeed(samples, last, windowMs: windowMs) * (1 - rested)
    }

    /// The song's ends, less the margin (:234).
    static func limits(_ length: Double) -> (low: Double, high: Double) {
        if !(length > 0) { return (0, .infinity) }
        return (0, JSMath.max(0, length - endMarginS))
    }
}

/// One of the hand's samples: when, and how far it had turned the record since the press, radians.
public struct HandSample: Equatable, Sendable {
    public var time: Double
    public var turned: Double
    public init(time: Double, turned: Double) {
        self.time = time
        self.turned = turned
    }
}

/// One phase of a plan (platter.ts:160): the motor's pull, a decay (friction, or the motor's pull from above or
/// below), or rest.
public enum PlatterPhase: Equatable, Sendable {
    case pull(x0: Double, v0: Double, a: Double, duration: Double)
    case decay(x0: Double, v0: Double, base: Double, sign: Double, c: Double, k: Double, duration: Double)
    case rest(x0: Double, duration: Double)

    public var duration: Double {
        switch self {
        case .pull(_, _, _, let duration), .decay(_, _, _, _, _, _, let duration), .rest(_, let duration): return duration
        }
    }

    /// The same phase, its duration replaced (the web's `{ ...phase, duration }`).
    func lasting(_ duration: Double) -> PlatterPhase {
        switch self {
        case let .pull(x0, v0, a, _): return .pull(x0: x0, v0: v0, a: a, duration: duration)
        case let .decay(x0, v0, base, sign, c, k, _): return .decay(x0: x0, v0: v0, base: base, sign: sign, c: c, k: k, duration: duration)
        case let .rest(x0, _): return .rest(x0: x0, duration: duration)
        }
    }
}

/// Where a plan stopped short: the song's start, or its end less the margin.
public enum PlanClamp: String, Equatable, Sendable {
    case start, end
}

/// A let-go's plan (platter.ts:210): its phases, how long, where it ends and how fast, the speed it pulls to, and
/// whether it hit an end of the song.
public struct Plan: Equatable, Sendable {
    public var phases: [PlatterPhase]
    public var duration: Double
    public var x: Double
    public var v: Double
    public var target: Double
    public var clamped: PlanClamp?
}

/// The platter's plans, over a `DeckMaths`.
public struct PlatterPlans<M: DeckMaths> {
    public let maths: M
    /// The friction's dry part (platter.ts:60): FRICTION_VISCOUS / (e^(FRICTION_VISCOUS x SPIN_DOWN_S) - 1) -
    /// computed once, as the web computes it at load, through `maths`.
    public let frictionDry: Double

    public init(_ maths: M) {
        self.maths = maths
        frictionDry = Platter.frictionViscous / (maths.exp(Platter.frictionViscous * Platter.spinDownS) - 1)
    }

    // ----- the equations, one phase at a time (platter.ts:147-206)

    /// Where a phase has the record `t` seconds in, and how fast (:166).
    public func phaseAt(_ phase: PlatterPhase, _ t: Double) -> (x: Double, v: Double) {
        let time = JSMath.max(0, JSMath.min(t, phase.duration))
        switch phase {
        case let .pull(x0, v0, a, _):
            return (x0 + v0 * time + 0.5 * a * time * time, v0 + a * time)
        case let .decay(x0, v0, base, sign, c, k, _):
            let u0 = sign * (v0 - base)
            let q = c / k
            let e = maths.exp(-k * time)
            let u = (u0 + q) * e - q
            let travelled = ((u0 + q) * (1 - e)) / k - q * time
            return (x0 + base * time + sign * travelled, base + sign * u)
        case let .rest(x0, _):
            return (x0, 0)
        }
    }

    /// How long a decay from `u0` above its base takes to reach it (:186).
    func decayTime(_ u0: Double, _ c: Double, _ k: Double) -> Double {
        maths.log(1 + (k * u0) / c) / k
    }

    /// When a phase first reaches `bound`, by bisection (:195).
    func timeTo(_ phase: PlatterPhase, _ bound: Double, _ within: Double) -> Double {
        let start = phaseAt(phase, 0).x
        let rising = phaseAt(phase, within).x > start
        var lo = 0.0, hi = within
        var i = 0
        while i < 60 && hi - lo > 1e-9 {
            let mid = (lo + hi) / 2
            let x = phaseAt(phase, mid).x
            if rising ? x < bound : x > bound { lo = mid } else { hi = mid }
            i += 1
        }
        return hi
    }

    /// Where a plan has the record `t` seconds in (:223).
    public func planAt(_ plan: Plan, _ t: Double) -> (x: Double, v: Double) {
        var left = JSMath.max(0, t)
        for phase in plan.phases {
            if left <= phase.duration { return phaseAt(phase, left) }
            left -= phase.duration
        }
        return (plan.x, plan.v)
    }

    /// A phase cut short where it would leave the song (:240).
    func clampPhase(_ phase: PlatterPhase, _ low: Double, _ high: Double) -> (phase: PlatterPhase, hit: PlanClamp?) {
        let end = phaseAt(phase, phase.duration).x
        if end < low && phaseAt(phase, 0).x >= low { return (phase.lasting(timeTo(phase, low, phase.duration)), .start) }
        if end > high && phaseAt(phase, 0).x <= high { return (phase.lasting(timeTo(phase, high, phase.duration)), .end) }
        return (phase, nil)
    }

    func finish(_ phases: [PlatterPhase], _ clamped: PlanClamp?, _ v: Double, _ bounds: (low: Double, high: Double), _ target: Double) -> Plan {
        let x: Double
        if clamped == .start { x = bounds.low }
        else if clamped == .end { x = bounds.high }
        else if let last = phases.last { x = phaseAt(last, last.duration).x }
        else { x = 0 }
        var duration = 0.0
        for phase in phases { duration = duration + phase.duration }
        return Plan(phases: phases, duration: duration, x: x, v: v, target: target, clamped: clamped)
    }

    /// The record let go with the motor off: friction to rest (:259).
    public func coast(_ x: Double, _ speed: Double, _ length: Double) -> Plan {
        let bounds = Platter.limits(length)
        let (low, high) = bounds
        let start = JSMath.max(low, JSMath.min(high, x.isFinite ? x : low))
        if speed == 0 || !speed.isFinite { return finish([.rest(x0: start, duration: 0)], nil, 0, bounds, 0) }
        let sign: Double = speed > 0 ? 1 : -1
        let u0 = Swift.abs(speed)
        let phase = PlatterPhase.decay(x0: start, v0: speed, base: 0, sign: sign, c: frictionDry, k: Platter.frictionViscous,
                                       duration: decayTime(u0, frictionDry, Platter.frictionViscous))
        let (kept, hit) = clampPhase(phase, low, high)
        return finish([kept], hit, 0, bounds, 0)
    }

    /// The record let go with the motor on: pulled to `target` from above, or from below - through rest, from
    /// backwards (:281).
    public func motor(_ x: Double, _ speed: Double, _ length: Double, _ target: Double = 1) -> Plan {
        let bounds = Platter.limits(length)
        let (low, high) = bounds
        var at = JSMath.max(low, JSMath.min(high, x.isFinite ? x : low))
        var v = speed.isFinite ? JSMath.max(-Platter.maxSpeed, JSMath.min(Platter.maxSpeed, speed)) : 0
        var phases: [PlatterPhase] = []
        var clamped: PlanClamp?
        let pull = Platter.motorPull, viscous = Platter.frictionViscous
        if v > target {
            let phase = PlatterPhase.decay(x0: at, v0: v, base: target, sign: 1, c: pull, k: viscous, duration: decayTime(v - target, pull, viscous))
            let (kept, hit) = clampPhase(phase, low, high)
            phases.append(kept)
            return finish(phases, hit, hit != nil ? phaseAt(kept, kept.duration).v : target, bounds, target)
        }
        if v < target {
            if v < 0 {
                let toStill = PlatterPhase.decay(x0: at, v0: v, base: 0, sign: -1, c: pull + frictionDry, k: viscous,
                                                 duration: decayTime(-v, pull + frictionDry, viscous))
                let (kept, hit) = clampPhase(toStill, low, high)
                phases.append(kept)
                if let hit { clamped = hit }
                at = hit == .start ? low : phaseAt(kept, kept.duration).x
                v = 0
            }
            let up = PlatterPhase.pull(x0: at, v0: v, a: pull, duration: (target - v) / pull)
            let (kept, hit) = clampPhase(up, low, high)
            phases.append(kept)
            if let hit { return finish(phases, hit, phaseAt(kept, kept.duration).v, bounds, target) }
            var ended = finish(phases, nil, target, bounds, target)
            ended.clamped = clamped
            return ended
        }
        return finish([.rest(x0: at, duration: 0)], nil, target, bounds, target)
    }

    /// The record's acceleration at a speed, the motor on or off (:331) - the equations the plans solve, which the
    /// voice's drives carry.
    public func acceleration(_ speed: Double, _ motorOn: Bool, _ target: Double = 1) -> Double {
        let pull = Platter.motorPull, viscous = Platter.frictionViscous
        if motorOn {
            if speed < 0 { return pull + frictionDry + viscous * -speed }
            if speed < target { return pull }
            if speed > target { return -(pull + viscous * (speed - target)) }
            return 0
        }
        if speed > 0 { return -(frictionDry + viscous * speed) }
        if speed < 0 { return frictionDry + viscous * -speed }
        return 0
    }
}
