import Foundation

// The EQ's processing (eq.md 1.5-1.7): pure Swift on pointers, the same code in the player's unit, the deck's render
// (1.9) and the Linux tests. Everything `process` reaches was made by `make` - no allocation, no lock, no Array, no
// closure, and no global, static or class property read there (each is checked at run time, and a lazy one's first
// touch takes a lock): the constants it needs are copied into the state.

/// What the render counts, for Debug (1.5).
public struct EQRenderCounters: Equatable, Sendable {
    /// samples sent over full scale while filtering, and the largest
    public var overs = 0
    public var largest: Double = 0
    public var crossfades = 0
    /// banks that arrived mid-crossfade and waited for it to end
    public var waited = 0
    /// banks made for another rate, ignored
    public var otherRate = 0
    /// blocks of more than `maximumFrames`, answered with an error and left untouched
    public var refused = 0

    public init() {}
}

/// The render's own memory, made off the audio thread by `EQRender.make` for one rate, channel count and largest
/// block: three banks (live, incoming during a crossfade, and one waiting for a crossfade to end), each section's
/// state per channel for the live and the incoming bank, each channel's last two input samples, two Double scratch
/// buffers and the crossfade's weights.
public struct EQRenderState {
    public let rate: Double
    public let channels: Int
    public let maximumFrames: Int
    /// `round(0.020 × rate)`: a crossfade's length
    public let fadeFrames: Int
    let slots: Int
    let header: Int
    let slot: Int
    let packedCount: Int
    /// `w(n) = 0.5 - 0.5·cos(π(n+1)/N)`, ending at exactly 1
    let weights: UnsafeMutablePointer<Double>
    var live: UnsafeMutablePointer<Double>
    var incoming: UnsafeMutablePointer<Double>
    let pending: UnsafeMutablePointer<Double>
    /// x1, x2, y1, y2 for each channel's each section
    var liveStates: UnsafeMutablePointer<Double>
    var incomingStates: UnsafeMutablePointer<Double>
    /// each channel's last input sample and the one before it
    let history: UnsafeMutablePointer<Double>
    let scratch: UnsafeMutablePointer<Double>
    let scratch2: UnsafeMutablePointer<Double>
    /// made and not yet rendered: the first block installs the newest bank, states zeroed, no crossfade (1.6)
    var fresh = true
    var fading = false
    var fadePosition = 0
    var hasPending = false
    public var counters = EQRenderCounters()

    /// The live bank is the identity and no crossfade is running: a block passes through untouched.
    public var passesThrough: Bool { !fading && live[1] == 1 }

    /// A crossfade is under way (Debug's "In the graph: crossfading").
    public var isCrossfading: Bool { fading }
}

public enum EQRender {
    /// The render's memory for a rate (off the audio thread: at `allocateRenderResources`). Live is the identity.
    /// `fadeFrames` is a test's own crossfade length - 1 makes every change in one step (eq.md 1.7 test 3's control,
    /// which must click); left out, 20 ms.
    public static func make(rate: Double, channels: Int, maximumFrames: Int,
                            fadeFrames: Int? = nil) -> UnsafeMutablePointer<EQRenderState> {
        precondition((1...EQLimits.channels).contains(channels) && maximumFrames > 0)
        let slots = EQLimits.sectionsPerChannel
        let packed = EQBank.packedCount
        let fade = max(1, fadeFrames ?? Int((0.020 * rate).rounded()))
        func zeros(_ n: Int) -> UnsafeMutablePointer<Double> {
            let p = UnsafeMutablePointer<Double>.allocate(capacity: n)
            p.initialize(repeating: 0, count: n)
            return p
        }
        let weights = zeros(fade)
        for n in 0..<fade { weights[n] = 0.5 - 0.5 * cos(Double.pi * Double(n + 1) / Double(fade)) }
        let live = zeros(packed)
        EQBank.identity(rate: rate, key: "", version: 0).pack(into: live)
        let state = UnsafeMutablePointer<EQRenderState>.allocate(capacity: 1)
        state.initialize(to: EQRenderState(
            rate: rate, channels: channels, maximumFrames: maximumFrames, fadeFrames: fade, slots: slots,
            header: EQBank.header, slot: EQBank.slot, packedCount: packed, weights: weights, live: live,
            incoming: zeros(packed), pending: zeros(packed), liveStates: zeros(channels * slots * 4),
            incomingStates: zeros(channels * slots * 4), history: zeros(channels * 2),
            scratch: zeros(channels * maximumFrames), scratch2: zeros(channels * maximumFrames)))
        return state
    }

    public static func free(_ state: UnsafeMutablePointer<EQRenderState>) {
        let s = state.pointee
        for p in [s.weights, s.live, s.incoming, s.pending, s.liveStates, s.incomingStates, s.history, s.scratch, s.scratch2] {
            p.deallocate()
        }
        state.deinitialize(count: 1)
        state.deallocate()
    }

    /// One block, in place on each channel's samples: the bank offered at its start (the newest from the ring, packed,
    /// or nil) taken as 1.6 says, then the live bank - and, during a crossfade, the incoming one beside it. False, with
    /// the samples untouched, for a block of more than `maximumFrames` (the unit answers
    /// `kAudioUnitErr_TooManyFramesToProcess`).
    @discardableResult
    public static func process(_ state: UnsafeMutablePointer<EQRenderState>,
                               buffers: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int,
                               offered: UnsafePointer<Double>?) -> Bool {
        if frames > state.pointee.maximumFrames {
            state.pointee.counters.refused += 1
            return false
        }
        take(state, offered)
        guard frames > 0 else { return true }
        let channels = state.pointee.channels
        let stride = state.pointee.maximumFrames

        //? Off, or flat: nothing is multiplied, converted or copied - only the last two samples kept (1.7)
        if state.pointee.passesThrough {
            for c in 0..<channels {
                let b = buffers[c]
                let h = state.pointee.history + c * 2
                h[1] = frames >= 2 ? Double(b[frames - 2]) : h[0]
                h[0] = Double(b[frames - 1])
            }
            return true
        }

        let fading = state.pointee.fading
        let scratch = state.pointee.scratch
        let scratch2 = state.pointee.scratch2
        for c in 0..<channels {
            let b = buffers[c]
            let x = scratch + c * stride
            for n in 0..<frames { x[n] = Double(b[n]) }
            if fading { (scratch2 + c * stride).update(from: x, count: frames) }
            let h = state.pointee.history + c * 2
            h[1] = frames >= 2 ? x[frames - 2] : h[0]
            h[0] = x[frames - 1]
        }
        run(state, state.pointee.live, state.pointee.liveStates, scratch, frames)
        if fading { run(state, state.pointee.incoming, state.pointee.incomingStates, scratch2, frames) }

        var overs = 0
        var largest = state.pointee.counters.largest
        let fadeFrames = state.pointee.fadeFrames
        let position = state.pointee.fadePosition
        let weights = state.pointee.weights
        for c in 0..<channels {
            let b = buffers[c]
            let old = scratch + c * stride
            let new = scratch2 + c * stride
            for n in 0..<frames {
                var y = old[n]
                if fading {
                    let k = position + n
                    if k < fadeFrames {
                        let w = weights[k]
                        y = (1 - w) * old[n] + w * new[n]
                    } else {
                        y = new[n]
                    }
                }
                let f = Float(y)
                b[n] = f
                let a = Double(f.magnitude)
                if a > 1 { overs += 1 }
                if a > largest { largest = a }
            }
        }
        state.pointee.counters.overs += overs
        state.pointee.counters.largest = largest

        if fading {
            state.pointee.fadePosition = position + frames
            if position + frames >= fadeFrames {
                //? the incoming bank, its states carried through the whole block, is live now
                let bank = state.pointee.live
                state.pointee.live = state.pointee.incoming
                state.pointee.incoming = bank
                let states = state.pointee.liveStates
                state.pointee.liveStates = state.pointee.incomingStates
                state.pointee.incomingStates = states
                state.pointee.fading = false
            }
        }
        return true
    }

    // ------------------------------------------------------------ banks (1.6)

    static func take(_ state: UnsafeMutablePointer<EQRenderState>, _ offered: UnsafePointer<Double>?) {
        let count = state.pointee.packedCount
        if let bank = offered {
            if bank[0] != state.pointee.rate {
                state.pointee.counters.otherRate += 1
            } else if state.pointee.fresh {
                state.pointee.live.update(from: bank, count: count)
                state.pointee.liveStates.update(repeating: 0, count: state.pointee.channels * state.pointee.slots * 4)
                state.pointee.hasPending = false
            } else if state.pointee.fading {
                //? one crossfade at a time: it waits, and a newer one replaces it
                state.pointee.pending.update(from: bank, count: count)
                state.pointee.hasPending = true
                state.pointee.counters.waited += 1
            } else {
                state.pointee.hasPending = false
                begin(state, bank)
            }
        }
        if !state.pointee.fading && state.pointee.hasPending {
            state.pointee.hasPending = false
            begin(state, UnsafePointer(state.pointee.pending))
        }
        state.pointee.fresh = false
    }

    /// A bank equal to the live one, bit for bit, takes its ids and nothing else; any other starts a crossfade, its
    /// sections warm-started by id (1.6).
    static func begin(_ state: UnsafeMutablePointer<EQRenderState>, _ bank: UnsafePointer<Double>) {
        let live = state.pointee.live
        let header = state.pointee.header, slots = state.pointee.slots, slot = state.pointee.slot
        if sameSound(bank, live, header: header, slots: slots, slot: slot) {
            for list in 0..<3 {
                for s in 0..<Int(bank[5 + list]) {
                    let i = header + (list * slots + s) * slot
                    live[i + 5] = bank[i + 5]
                    live[i + 6] = bank[i + 6]
                }
            }
            return
        }
        let incoming = state.pointee.incoming
        incoming.update(from: bank, count: state.pointee.packedCount)
        let liveStates = state.pointee.liveStates
        let incomingStates = state.pointee.incomingStates
        for c in 0..<state.pointee.channels {
            let list = listOf(c)
            let n = Int(incoming[5 + list])
            let m = Int(live[5 + list])
            for s in 0..<n {
                let q = incoming + header + (list * slots + s) * slot
                let to = incomingStates + (c * slots + s) * 4
                var matched = false
                for j in 0..<m {
                    let r = live + header + (list * slots + j) * slot
                    if r[5] == q[5] && r[6] == q[6] {
                        to.update(from: liveStates + (c * slots + j) * 4, count: 4)
                        matched = true
                        break
                    }
                }
                if !matched {
                    //? as if it had been flat: x and y both the history of its own input - the previous section's
                    //? output in this bank, or the input's for the first
                    let h1: Double, h2: Double
                    if s == 0 {
                        h1 = state.pointee.history[c * 2]
                        h2 = state.pointee.history[c * 2 + 1]
                    } else {
                        let before = incomingStates + (c * slots + s - 1) * 4
                        h1 = before[2]
                        h2 = before[3]
                    }
                    to[0] = h1
                    to[1] = h2
                    to[2] = h1
                    to[3] = h2
                }
            }
        }
        state.pointee.fading = true
        state.pointee.fadePosition = 0
        state.pointee.counters.crossfades += 1
    }

    /// The same coefficients and levels, bit for bit (ids and kinds aside).
    static func sameSound(_ a: UnsafePointer<Double>, _ b: UnsafePointer<Double>, header: Int, slots: Int,
                          slot: Int) -> Bool {
        for i in 1..<header where a[i].bitPattern != b[i].bitPattern { return false }
        for list in 0..<3 {
            for s in 0..<Int(a[5 + list]) {
                let i = header + (list * slots + s) * slot
                for k in 0..<5 where a[i + k].bitPattern != b[i + k].bitPattern { return false }
            }
        }
        return true
    }

    /// Channel 0 the left's list, 1 the right's, the rest the shared one.
    @inline(__always)
    static func listOf(_ channel: Int) -> Int { channel < 2 ? channel : 2 }

    // ------------------------------------------------------------ Direct Form I, in Double (1.5)

    /// A bank over the scratch, section-major, the channels in pairs so their recursions interleave; then each
    /// channel's level.
    static func run(_ state: UnsafeMutablePointer<EQRenderState>, _ bank: UnsafeMutablePointer<Double>,
                    _ states: UnsafeMutablePointer<Double>, _ scratch: UnsafeMutablePointer<Double>, _ frames: Int) {
        let channels = state.pointee.channels
        let stride = state.pointee.maximumFrames
        let header = state.pointee.header, slots = state.pointee.slots, slot = state.pointee.slot
        var c = 0
        while c < channels {
            let a = listOf(c)
            let na = Int(bank[5 + a])
            let xa = scratch + c * stride
            if c + 1 < channels {
                let b = listOf(c + 1)
                let nb = Int(bank[5 + b])
                let xb = scratch + (c + 1) * stride
                for s in 0..<max(na, nb) {
                    let qa = bank + header + (a * slots + s) * slot
                    let qb = bank + header + (b * slots + s) * slot
                    let sa = states + (c * slots + s) * 4
                    let sb = states + ((c + 1) * slots + s) * 4
                    if s < na && s < nb {
                        df1Pair(qa, sa, xa, qb, sb, xb, frames)
                    } else if s < na {
                        df1(qa, sa, xa, frames)
                    } else {
                        df1(qb, sb, xb, frames)
                    }
                }
            } else {
                for s in 0..<na {
                    df1(bank + header + (a * slots + s) * slot, states + (c * slots + s) * 4, xa, frames)
                }
            }
            c += 2
        }
        for c in 0..<channels {
            let level = bank[2 + listOf(c)]
            let x = scratch + c * stride
            for n in 0..<frames { x[n] = x[n] * level }
        }
    }

    /// One section over one channel: `y = b0·x + b1·x1 + b2·x2 - a1·y1 - a2·y2`, in that order (Swift contracts nothing
    /// into a fused multiply-add unless asked, so every platform computes the same bits).
    @inline(__always)
    static func df1(_ q: UnsafePointer<Double>, _ st: UnsafeMutablePointer<Double>, _ x: UnsafeMutablePointer<Double>,
                    _ frames: Int) {
        let b0 = q[0], b1 = q[1], b2 = q[2], a1 = q[3], a2 = q[4]
        var x1 = st[0], x2 = st[1], y1 = st[2], y2 = st[3]
        for n in 0..<frames {
            let xn = x[n]
            let y = b0 * xn + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = xn
            y2 = y1
            y1 = y
            x[n] = y
        }
        st[0] = x1
        st[1] = x2
        st[2] = y1
        st[3] = y2
    }

    /// Two sections over two channels in one loop: the same arithmetic as `df1` for each, interleaved.
    @inline(__always)
    static func df1Pair(_ qa: UnsafePointer<Double>, _ sa: UnsafeMutablePointer<Double>, _ xa: UnsafeMutablePointer<Double>,
                        _ qb: UnsafePointer<Double>, _ sb: UnsafeMutablePointer<Double>, _ xb: UnsafeMutablePointer<Double>,
                        _ frames: Int) {
        let ab0 = qa[0], ab1 = qa[1], ab2 = qa[2], aa1 = qa[3], aa2 = qa[4]
        let bb0 = qb[0], bb1 = qb[1], bb2 = qb[2], ba1 = qb[3], ba2 = qb[4]
        var ax1 = sa[0], ax2 = sa[1], ay1 = sa[2], ay2 = sa[3]
        var bx1 = sb[0], bx2 = sb[1], by1 = sb[2], by2 = sb[3]
        for n in 0..<frames {
            let ax = xa[n]
            let bx = xb[n]
            let ay = ab0 * ax + ab1 * ax1 + ab2 * ax2 - aa1 * ay1 - aa2 * ay2
            let by = bb0 * bx + bb1 * bx1 + bb2 * bx2 - ba1 * by1 - ba2 * by2
            ax2 = ax1
            ax1 = ax
            ay2 = ay1
            ay1 = ay
            bx2 = bx1
            bx1 = bx
            by2 = by1
            by1 = by
            xa[n] = ay
            xb[n] = by
        }
        sa[0] = ax1
        sa[1] = ax2
        sa[2] = ay1
        sa[3] = ay2
        sb[0] = bx1
        sb[1] = bx2
        sb[2] = by1
        sb[3] = by2
    }
}
