/// The record's clock (notes/ios-specs/turntable.md 3.2): `L`, the largest end-of-block lead over the last
/// CLOCK_WINDOW_MS of blocks, which the voice's `now` (`hostOut - L`) is kept behind - the web's deckClock.ts envelope,
/// mirrored. Each block's lead is `hostOut + frames / rate - entry`: how far the block's END is ahead of the moment the
/// render runs, so a knot stamped at host time `t` has arrived before the block that renders voice time `t` begins.
///
/// A sliding maximum over 1.5 s - a monotonic deque in a ring made with it (2048 entries, 1.5 s of iOS's smallest
/// blocks), so it never allocates - followed freely while the voice is quiet, and under a sound slewed toward by at
/// most CLOCK_SLEW (0.5 ms a second), so the voice's clock never steps under a hand. Called on the audio thread; made
/// and freed off it. Pure: no clock of its own, every time handed in.
public struct DeckLead {
    /// deckClock.ts CLOCK_WINDOW_MS, in seconds
    public static let windowS = 1.5
    /// deckClock.ts CLOCK_SLEW: seconds of `L` a second of host time, under a sound
    public static let slew = 0.0005
    /// 1.5 s of 64-frame blocks at 48 kHz is 1125
    public static let capacity = 2048

    /// the deque: each entry's host time and lead, oldest at `head`
    let at: UnsafeMutablePointer<Double>
    let of: UnsafeMutablePointer<Double>
    var head = 0
    var count = 0
    /// the host time of the last block, for the slew
    var last: Double?

    /// `L`, seconds - what the voice's now is kept behind
    public private(set) var value: Double
    /// the last block's own lead
    public private(set) var latest: Double = 0
    /// the largest lead over the window: what `L` moves toward
    public private(set) var target: Double = 0
    /// the largest lead seen while the voice sounded, since it last began to (Debug's "under the last hand")
    public private(set) var largestSounding: Double = 0
    var wasSounding = false
    /// blocks seen
    public private(set) var blocks = 0

    /// `L` before the first block: 2 x the IO buffer's duration (3.2).
    public init(floor: Double) {
        at = .allocate(capacity: Self.capacity)
        at.initialize(repeating: 0, count: Self.capacity)
        of = .allocate(capacity: Self.capacity)
        of.initialize(repeating: 0, count: Self.capacity)
        value = floor
    }

    /// Frees the deque (off the audio thread).
    public func deallocate() {
        at.deallocate()
        of.deallocate()
    }

    /// From the floor again, the window emptied: a route change (4.6).
    public mutating func restart(floor: Double) {
        head = 0
        count = 0
        last = nil
        value = floor
        latest = 0
        target = 0
        largestSounding = 0
        wasSounding = false
    }

    /// A block of `frames` at `rate`, first presented at host time `hostOut`, entered at host time `entry`, the voice
    /// `sounding` or not: `L` for this block.
    @discardableResult
    public mutating func block(hostOut: Double, frames: Int, rate: Double, entry: Double, sounding: Bool) -> Double {
        let lead = hostOut + Double(frames) / rate - entry
        latest = lead
        blocks += 1
        // older than the window, from the front
        while count > 0 && at[head] < hostOut - Self.windowS {
            head = (head + 1) & (Self.capacity - 1)
            count -= 1
        }
        // no larger than this one, from the back
        while count > 0 && of[(head + count - 1) & (Self.capacity - 1)] <= lead { count -= 1 }
        if count == Self.capacity {
            head = (head + 1) & (Self.capacity - 1)
            count -= 1
        }
        let slot = (head + count) & (Self.capacity - 1)
        at[slot] = hostOut
        of[slot] = lead
        count += 1
        target = of[head]

        if sounding {
            if !wasSounding { largestSounding = lead }
            largestSounding = Swift.max(largestSounding, lead)
            let step = Self.slew * Swift.max(0, hostOut - (last ?? hostOut))
            value += Swift.min(Swift.max(target - value, -step), step)
        } else {
            value = target
        }
        wasSounding = sounding
        last = hostOut
        return value
    }
}
