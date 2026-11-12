/// The record's own sound - the web's ui/src/lib/deckVoice.ts, its four functions ported line for line, in the same
/// order (notes/ios-specs/turntable.md 4.1, 4.2): `newVoiceState`, `voiceCommand`, `renderVoice`, `voiceReport`.
/// Read the web's file for why each piece is as it is; each block here names its line there.
///
/// It is held to the web bit for bit (DeckVoiceTests, test A): every JS number a Double, every Float32Array `Float`
/// storage read into a Double as JS reads it and stored rounded as JS stores it; no fused multiply-add; the web's
/// order of operations and parentheses term by term; Math.round, min and max as JSMath has them; the transcendentals
/// through a `DeckMaths`, so the test replays V8's own answers.
///
/// Two places differ in form from the web, not in arithmetic (4.1): a window is a `VoiceWindow` of at most two
/// channel pointers made off the audio thread (the web filters and makes an object in its `window` case), and the
/// limiter's delay lines are made for two channels in `newVoiceState` with no growing path (the web grows them in
/// renderVoice for a host with more) - the phone's voice plays one or two. Nothing allocates after
/// `newVoiceState`; `deallocate()` frees what it made.

/// A stretch of the song, decoded (deckVoice.ts:117): one or two channels of `length` samples at `rate` a second,
/// from `start` (song seconds). The pointers are the window maker's; the voice only reads them.
public struct VoiceWindow {
    public var first: UnsafePointer<Float>
    public var second: UnsafePointer<Float>?
    public var length: Int
    public var start: Double
    public var rate: Double

    public init(first: UnsafePointer<Float>, second: UnsafePointer<Float>?, length: Int, start: Double, rate: Double) {
        self.first = first
        self.second = second
        self.length = length
        self.start = start
        self.rate = rate
    }

    /// How many channels: the web's `channels.length`.
    @inlinable public var channelCount: Int { second == nil ? 1 : 2 }

    /// Channel `c` (0 or 1).
    @inlinable public func channel(_ c: Int) -> UnsafePointer<Float> {
        c == 0 ? first : (second ?? first)
    }
}

/// A message from the deck to the voice (deckVoice.ts:215).
public enum VoiceMessage {
    /// A new stretch of the song - nil where the web's channels were none (its window then null).
    case window(VoiceWindow?)
    case take(at: Double, rate: Double, time: Double, until: Double)
    case drive(at: Double, rate: Double, accel: Double?, time: Double, until: Double)
    case hand(at: Double, time: Double)
    case fade(seconds: Double)
    case stop
}

/// What the voice says ~30 times a second (deckVoice.ts:232).
public struct VoiceHeard: Equatable, Sendable {
    public var pos: Double
    public var rate: Double
    public var gain: Double
    public var time: Double
    public var held: Double
    public var peaks: Double
    public var lowest: Double
    public init(pos: Double, rate: Double, gain: Double, time: Double, held: Double, peaks: Double, lowest: Double) {
        self.pos = pos
        self.rate = rate
        self.gain = gain
        self.time = time
        self.held = held
        self.peaks = peaks
        self.lowest = lowest
    }
}

/// The voice's state (deckVoice.ts:124) - every field the web's, its typed arrays as buffers made in
/// `newVoiceState` and freed by `deallocate()`.
public struct VoiceState {
    public var pos: Double
    public var rate: Double
    public var gain: Double
    public var gainTarget: Double
    public var gainAlpha: Double
    public var driving: Bool
    public var delay: Double
    public var knotTime: UnsafeMutableBufferPointer<Double>
    public var knotAt: UnsafeMutableBufferPointer<Double>
    public var knotPos: UnsafeMutableBufferPointer<Double>
    public var knotRate: UnsafeMutableBufferPointer<Double>
    public var knotAccel: UnsafeMutableBufferPointer<Double>
    public var knotUntil: UnsafeMutableBufferPointer<Double>
    public var knotHand: UnsafeMutableBufferPointer<UInt8>
    public var knotSteady: UnsafeMutableBufferPointer<Double>
    public var first: Int
    public var end: Int
    public var cursor: Int
    public var window: VoiceWindow?
    public var kernel: UnsafeMutableBufferPointer<Float>
    public var kernelZeros: Int
    public var kernelSteps: Int
    public var taps: UnsafeMutableBufferPointer<Float>
    /// The DC blocker's last input and output, per channel (two).
    public var lastIn: UnsafeMutableBufferPointer<Double>
    public var lastOut: UnsafeMutableBufferPointer<Double>
    public var limitRing: Int
    public var limitDelay: UnsafeMutableBufferPointer<Double>
    public var limitNeed: UnsafeMutableBufferPointer<Double>
    public var limitMinRing: Int
    public var limitMinAt: UnsafeMutableBufferPointer<Double>
    public var limitMinOf: UnsafeMutableBufferPointer<Double>
    public var limitMinHead: Int
    public var limitMinTail: Int
    public var limitEnv: Double
    public var limitBoxA: UnsafeMutableBufferPointer<Double>
    public var limitBoxB: UnsafeMutableBufferPointer<Double>
    public var limitSumA: Double
    public var limitSumB: Double
    public var limitLowA: Int
    public var limitLowB: Int
    public var limitN: Int
    public var limitLength: Int
    public var limitChannels: Int
    public var limitHeld: Int
    public var limitPeaks: Int
    public var limitWasOver: Bool
    public var limitLowest: Double
    public var counted: Double

    /// Frees every buffer `newVoiceState` made. The window's channels are the window maker's, not freed here.
    public func deallocate() {
        for buffer in [knotTime, knotAt, knotPos, knotRate, knotAccel, knotUntil, knotSteady, lastIn, lastOut, limitDelay, limitNeed,
                       limitMinAt, limitMinOf, limitBoxA, limitBoxB] {
            buffer.deallocate()
        }
        knotHand.deallocate()
        kernel.deallocate()
        taps.deallocate()
    }
}

public enum DeckVoice {
    /// How many times a second the voice says where it is (deckVoice.ts:82).
    public static let reportsPerSecond = 30.0
    /// How far behind the record's path the voice plays (:95) - newVoiceState's literal.
    public static let handDelayS = 0.12
    /// How far ahead the limiter looks (:114) - renderVoice's literal.
    public static let lookaheadS = 0.0015
    /// The limiter's ceiling (:105): -0.5 dBFS as a Float32.
    public static func ceiling<M: DeckMaths>(_ maths: M) -> Double {
        JSMath.fround(maths.pow(10, -0.5 / 20))
    }

    @inlinable static func filled<T>(_ count: Int, _ value: T) -> UnsafeMutableBufferPointer<T> {
        let buffer = UnsafeMutableBufferPointer<T>.allocate(capacity: count)
        buffer.initialize(repeating: value)
        return buffer
    }

    // MARK: - newVoiceState (deckVoice.ts:246)

    /// A voice at rest: silent, nowhere in particular, nothing to play, no path.
    public static func newVoiceState<M: DeckMaths>(_ maths: M) -> VoiceState {
        //? :249 the path's knots
        let knots = 64
        //? :259 the kernel: a sinc, 12 zero crossings either side, under a Kaiser window, 128 entries a crossing
        let zeros = 12, steps = 128, widest = 4, beta = 7.0
        //? :260 the Bessel function's series, 31 terms
        func bessel(_ x: Double) -> Double {
            var sum = 1.0, term = 1.0
            for k in 1..<32 {
                let half = Double(2 * k)
                term *= (x / half) * (x / half)
                sum += term
            }
            return sum
        }
        //? :268
        let kernel = filled(zeros * steps + 2, Float(0))
        for i in 0...(zeros * steps) {
            let x = Double(i) / Double(steps)
            let sinc = i == 0 ? 1 : maths.sin(Double.pi * x) / (Double.pi * x)
            let edge = x / Double(zeros)
            kernel[i] = Float(sinc * (bessel(beta * JSMath.max(0, 1 - edge * edge).squareRoot()) / bessel(beta)))
        }
        //? :278 the limiter's rings: its lookahead at 192 kHz with room to spare, a delay for two channels, and its
        //? running minimum's, longer (it covers the hold)
        let ring = 1024, channels = 2
        let minRing = 8192
        return VoiceState(
            pos: 0, rate: 0, gain: 0, gainTarget: 0, gainAlpha: 0.01, driving: false, delay: 0.12,
            knotTime: filled(knots, 0.0), knotAt: filled(knots, 0.0), knotPos: filled(knots, 0.0),
            knotRate: filled(knots, 0.0), knotAccel: filled(knots, 0.0), knotUntil: filled(knots, 0.0),
            knotHand: filled(knots, UInt8(0)), knotSteady: filled(knots, 0.0), first: 0, end: 0, cursor: 0,
            window: nil, kernel: kernel, kernelZeros: zeros, kernelSteps: steps, taps: filled(2 * zeros * widest + 2, Float(0)),
            lastIn: filled(channels, 0.0), lastOut: filled(channels, 0.0),
            limitRing: ring, limitDelay: filled(ring * channels, 0.0), limitNeed: filled(ring, 1.0),
            limitMinRing: minRing, limitMinAt: filled(minRing, 0.0), limitMinOf: filled(minRing, 0.0), limitMinHead: 0, limitMinTail: 0,
            limitEnv: 1, limitBoxA: filled(ring, 1.0), limitBoxB: filled(ring, 1.0), limitSumA: 0, limitSumB: 0, limitLowA: 0, limitLowB: 0,
            limitN: 0, limitLength: 0, limitChannels: channels, limitHeld: 0, limitPeaks: 0, limitWasOver: false, limitLowest: 1,
            counted: 0)
    }

    // MARK: - voiceCommand (deckVoice.ts:298)

    /// A message from the page, applied as of context time `now`.
    public static func voiceCommand<M: DeckMaths>(_ state: inout VoiceState, _ message: VoiceMessage, _ now: Double, _ sampleRate: Double,
                                                  _ maths: M) {
        //? :300 a one-pole filter's step for a time constant, per sample
        func alpha(_ seconds: Double) -> Double {
            1 - maths.exp(-1 / (JSMath.max(seconds, 1e-4) * sampleRate))
        }
        //? :302-318
        let quickS = 0.003
        let smoothAfterS = 0.09
        let fitS = 0.12
        let restS = 0.04
        let missedS = 0.1
        let keptOn = 0.25
        let keptS = 0.003
        let extrapolateS = 0.02
        let resumeS = 0.017
        let size = state.knotTime.count
        let t = state.knotTime, at = state.knotAt, pos = state.knotPos, rate = state.knotRate
        let accel = state.knotAccel, until = state.knotUntil, hand = state.knotHand, steady = state.knotSteady

        //? :323 a knot added at the end - the oldest let go of when the ring is full
        func add(_ time: Double, _ whereAt: Double, _ speed: Double, _ change: Double, _ endAt: Double, _ isHand: UInt8) {
            if state.end - state.first >= size { state.first += 1 }
            let k = state.end % size
            t[k] = time
            at[k] = whereAt
            pos[k] = whereAt
            rate[k] = speed
            accel[k] = change
            until[k] = endAt
            hand[k] = isHand
            steady[k] = 0
            state.end += 1
            if state.cursor < state.first { state.cursor = state.first }
        }
        //? :346 where a resting hand set off from
        func settle(_ i: Int) {
            let j = i - 1
            if j - 1 < state.first || hand[j % size] != 2 { return }
            let k = i % size
            let ahead = pos[k] - pos[j % size]
            let lead = rate[k] * ahead > 0 ? JSMath.min(resumeS, (3 * ahead) / rate[k]) : 0
            t[j % size] = JSMath.max(t[(j - 1) % size], t[k] - lead)
        }
        //? :359 a hand sample's place, speed and change of speed, from it and its neighbours
        func place(_ i: Int) {
            let k = i % size
            let ti = t[k]
            var from = i
            var j = i - 1
            while j >= state.first && hand[j % size] == 1 && ti - t[j % size] <= fitS {
                from = j
                j -= 1
            }
            var to = i
            j = i + 1
            while j < state.end && hand[j % size] == 1 && t[j % size] - ti <= smoothAfterS {
                to = j
                j += 1
            }
            steady[k] = 0
            if to == from {
                pos[k] = at[k]
                rate[k] = 0
                accel[k] = 0
                return
            }
            //? :384 one weighted parabola over the samples within FIT_S either side
            var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0, x0 = 0.0, x1 = 0.0, x2 = 0.0
            for j in from...to {
                let u = (t[j % size] - ti) / fitS
                let d = Swift.abs(u)
                if d >= 1 { continue }
                let w3 = 1 - d * d * d
                let w = w3 * w3 * w3
                let x = at[j % size] - at[k]
                let u2 = u * u
                s0 += w
                s1 += w * u
                s2 += w * u2
                s3 += w * u2 * u
                s4 += w * u2 * u2
                x0 += w * x
                x1 += w * u * x
                x2 += w * u2 * x
            }
            steady[k] = 1
            let m0 = s2 * s4 - s3 * s3, m1 = s1 * s4 - s2 * s3, m2 = s1 * s3 - s2 * s2
            let det = s0 * m0 - s1 * m1 + s2 * m2
            let lineDet = s0 * s2 - s1 * s1
            accel[k] = 0
            if to - from + 1 >= 4 && Swift.abs(det) > 1e-9 * s0 * s0 * s0 {
                //? :408
                let p1 = x0 * m0
                let p2 = s1 * (x1 * s4 - s3 * x2)
                let p3 = s2 * (x1 * s3 - s2 * x2)
                pos[k] = at[k] + (p1 - p2 + p3) / det
                let r1 = s0 * (x1 * s4 - s3 * x2)
                let r2 = x0 * m1
                let r3 = s2 * (s1 * x2 - x1 * s2)
                rate[k] = (r1 - r2 + r3) / det / fitS
                let a1 = s0 * (s2 * x2 - s3 * x1)
                let a2 = s1 * (s1 * x2 - s2 * x1)
                let a3 = x0 * m2
                accel[k] = (2 * (a1 - a2 + a3)) / det / (fitS * fitS)
            } else if lineDet > 1e-12 {
                //? :413 two or three samples: the line through them
                pos[k] = at[k] + (s2 * x0 - s1 * x1) / lineDet
                rate[k] = (s0 * x1 - s1 * x0) / lineDet / fitS
            } else {
                pos[k] = at[k]
                rate[k] = 0
            }
        }
        //? :339
        func fit(_ i: Int) {
            place(i)
            settle(i)
        }
        //? :432 a knot coming after a hand's last sample, further on than REST_S: the hand rested since
        func rested(_ time: Double, _ whereAt: Double, _ moving: Bool) {
            let last = state.end - 1
            if last < state.first || hand[last % size] != 1 { return }
            let k = last % size
            let gap = time - t[k]
            if gap <= restS { return }
            let p = pos[k], v = rate[k]
            if moving && gap <= missedS && Swift.abs(whereAt - p - v * gap) <= JSMath.max(keptS, keptOn * Swift.abs(v * gap)) { return }
            let stopped = t[k] + extrapolateS, there = p + (v * extrapolateS) / 2
            add(stopped, there, 0, 0, .infinity, 0)
            if moving { add(JSMath.max(stopped, time - resumeS), there, 0, 0, .infinity, 2) }
            else { add(JSMath.max(stopped, time), there, 0, 0, .infinity, 0) }
        }

        switch message {
        case .window(let window):
            //? :445
            state.window = window
        case let .take(atWhere, speed, time, endAt):
            //? :454 where the record is on its path by `now`, the delay behind
            state.pos = atWhere + speed * (now - state.delay - time)
            state.rate = speed
            state.gain = 0
            state.gainTarget = 1
            state.gainAlpha = alpha(quickS)
            state.driving = true
            state.first = state.end
            state.cursor = state.end
            add(time, atWhere, speed, 0, endAt, 0)
        case let .drive(atWhere, speed, change, time, endAt):
            //? :466 newer word on a moment the path already has, or an earlier one: what came after it goes
            while state.end > state.first && t[(state.end - 1) % size] >= time { state.end -= 1 }
            rested(time, atWhere, false)
            add(time, atWhere, speed, change ?? 0, endAt, 0)
            state.driving = true
        case let .hand(atWhere, time):
            //? :475
            while state.end > state.first && hand[(state.end - 1) % size] != 1 && t[(state.end - 1) % size] > time { state.end -= 1 }
            let last = state.end - 1
            if last >= state.first {
                let lastTime = t[last % size]
                //? out of order: an older sample than the hand's newest is no use to the path (the web returns here,
                //? before the cursor's check below)
                if time < lastTime { return }
                if time == lastTime && hand[last % size] == 1 { state.end -= 1 }
                else { rested(time, atWhere, true) }
            }
            add(time, atWhere, 0, 0, .infinity, 1)
            //? :486 this sample and the ones it is now among the after of
            var j = state.end - 1
            while j >= state.first && hand[j % size] == 1 && time - t[j % size] <= smoothAfterS {
                fit(j)
                j -= 1
            }
        case .fade(let seconds):
            //? :489
            state.gainTarget = 0
            state.gainAlpha = alpha(seconds / 4)
        case .stop:
            //? :492
            state.driving = false
            state.gainTarget = 0
            state.gainAlpha = alpha(quickS)
        }
        //? :496
        if state.cursor > state.end - 1 { state.cursor = Swift.max(state.first, state.end - 1) }
    }

    // MARK: - renderVoice (deckVoice.ts:507)

    /// `frames` samples of the record's sound into `outputs` (one or two channels, each at least `frames` long),
    /// from context time `now`.
    public static func renderVoice<M: DeckMaths>(_ state: inout VoiceState, _ outputs: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>>,
                                                 _ frames: Int, _ sampleRate: Double, _ now: Double, _ maths: M) {
        //? :511-521
        let smoothS = 0.01
        let followS = 0.1
        let maxRate = 24.0
        let edgeS = 0.004
        let dcHz = 10.0
        let quiet = 1e-5
        let extrapolateS = 0.02
        //? :522
        let rateAlpha = 1 - maths.exp(-1 / (smoothS * sampleRate))
        let pole = maths.exp((-2 * Double.pi * dcHz) / sampleRate)
        let dt = 1 / sampleRate
        let win = state.window
        let count = outputs.count
        precondition(count <= 2, "the voice plays one or two channels (the spec's 4.1)")
        let size = state.knotTime.count
        let kt = state.knotTime, kp = state.knotPos, kr = state.knotRate, ka = state.knotAccel, ku = state.knotUntil, kh = state.knotHand
        let ks = state.knotSteady
        let kernel = state.kernel, taps = state.taps, zeros = state.kernelZeros, steps = state.kernelSteps
        let kernelCount = kernel.count, tapCount = taps.count
        //? :561 THE LIMITER
        let ceiling = JSMath.fround(maths.pow(10, -0.5 / 20))
        let lookaheadS = 0.0015
        let holdS = 0.02
        let releaseS = 0.06
        let safe = 1 - maths.pow(2, -30)
        let snap = maths.pow(2, -24)
        //? :571
        let ring = state.limitRing, mask = ring - 1
        let lookahead = Int(JSMath.min(Double(ring - 2), JSMath.max(1, JSMath.round(lookaheadS * sampleRate))))
        let minMask = state.limitMinRing - 1
        let span = Int(JSMath.min(Double(state.limitMinRing - 2), Double(lookahead) + JSMath.round(holdS * sampleRate)))
        if state.limitLength != lookahead || state.limitChannels != count {
            //? :576 set up for this rate and these channels, at rest (the delay made for two in newVoiceState)
            state.limitLength = lookahead
            state.limitChannels = count
            state.limitDelay.update(repeating: 0)
            state.limitNeed.update(repeating: 1)
            state.limitBoxA.update(repeating: 1)
            state.limitBoxB.update(repeating: 1)
            state.limitMinHead = 0
            state.limitMinTail = 0
            state.limitEnv = 1
            state.limitLowA = 0
            state.limitLowB = 0
            state.limitN = 0
            state.limitWasOver = false
        }
        //? :591
        let lengthA = Int((Double(lookahead + 2) / 2).rounded(.up)), lengthB = lookahead + 2 - lengthA
        let releaseAlpha = 1 - maths.exp(-1 / (releaseS * sampleRate))
        let delayLine = state.limitDelay, needs = state.limitNeed, minAt = state.limitMinAt, minOf = state.limitMinOf
        let boxA = state.limitBoxA, boxB = state.limitBoxB
        var limitN = state.limitN, head = state.limitMinHead, tail = state.limitMinTail, env = state.limitEnv
        var lowA = state.limitLowA, lowB = state.limitLowB
        var sumA = lowA == 0 ? Double(lengthA) : state.limitSumA, sumB = lowB == 0 ? Double(lengthB) : state.limitSumB
        var heldCount = state.limitHeld, peakCount = state.limitPeaks, wasOver = state.limitWasOver, lowestGain = state.limitLowest
        for i in 0..<frames {
            let t = now + Double(i) * dt
            var desired = 0.0
            if state.driving && state.end > state.first {
                //? :605 the moment of the path it plays, and the knot that is on
                let tau = t - state.delay
                var c = state.cursor
                while c > state.first && kt[c % size] > tau { c -= 1 }
                while c + 1 < state.end && kt[(c + 1) % size] <= tau { c += 1 }
                state.cursor = c
                let a = c % size
                let ta = kt[a]
                var x = 0.0, v = 0.0, g = 0.0, follow = true
                if tau < ta {
                    //? :616 before its first knot
                    x = kp[a] + kr[a] * (tau - ta)
                    v = kr[a]
                } else if c + 1 < state.end {
                    //? :625 between two knots: the cubic through their places and speeds
                    let b = (c + 1) % size
                    let h = kt[b] - ta
                    let s = (tau - ta) / h
                    let s2 = s * s, s3 = s2 * s
                    let h00 = (2 * s3 - 3 * s2 + 1) * kp[a]
                    let h10 = (s3 - 2 * s2 + s) * h * kr[a]
                    let h01 = (3 * s2 - 2 * s3) * kp[b]
                    let h11 = (s3 - s2) * h * kr[b]
                    x = h00 + h10 + h01 + h11
                    if ks[a] == 1 && ks[b] == 1 {
                        v = (1 - s) * kr[a] + s * kr[b]
                        g = (1 - s) * ka[a] + s * ka[b]
                    } else {
                        let chord = (kp[b] - kp[a]) / h - (kr[a] + kr[b]) / 2
                        v = (1 - s) * kr[a] + s * kr[b] + 6 * (s - s2) * chord
                        g = (kr[b] - kr[a] + 6 * (1 - 2 * s) * chord) / h
                    }
                } else if kh[a] == 1 {
                    //? :640 past a hand's last sample: on along its speed, slowing to still, then held
                    let since = JSMath.min(tau - ta, extrapolateS)
                    x = kp[a] + kr[a] * (since - (since * since) / (2 * extrapolateS))
                    v = kr[a] * (1 - since / extrapolateS)
                    g = since < extrapolateS ? -kr[a] / extrapolateS : 0
                } else if tau <= ku[a] {
                    //? :646 past a drive: along its own curve, until it runs out
                    let since = tau - ta
                    x = kp[a] + kr[a] * since + 0.5 * ka[a] * since * since
                    v = kr[a] + ka[a] * since
                    g = ka[a]
                } else {
                    follow = false
                }
                if follow {
                    //? :656
                    desired = v + smoothS * g + (x - state.pos) / followS
                    if desired > maxRate { desired = maxRate }
                    else if desired < -maxRate { desired = -maxRate }
                }
            }
            //? :661
            state.rate += (desired - state.rate) * rateAlpha
            state.pos += state.rate * dt
            state.gain += (state.gainTarget - state.gain) * state.gainAlpha
            var shape = 0.0
            var index = 0.0
            if let win, state.gain > quiet {
                index = (state.pos - win.start) * win.rate
                let last = Double(win.length - 1)
                let edge = JSMath.min(index, last - index) / (edgeS * win.rate)
                shape = edge <= 0 ? 0 : edge >= 1 ? 1 : edge
            }
            //? :680 this sample's weights
            var first = 0, used = 0, norm = 0.0
            if shape > 0, let win {
                let stride = (Swift.abs(state.rate) * win.rate) / sampleRate
                let widest = Double(tapCount - 2) / Double(2 * zeros)
                let squeeze = stride > 1 ? JSMath.max(1 / stride, 1 / widest) : 1
                let reach = Double(zeros) / squeeze
                let scale = squeeze * Double(steps)
                first = Int((index - reach).rounded(.up))
                used = Int((index + reach).rounded(.down)) - first + 1
                var total = 0.0
                for j in 0..<used {
                    let u = Swift.abs(index - Double(first + j)) * scale
                    let whole = u.rounded(.down)
                    let w = Int(whole)
                    //? a read past the kernel's end is JS's undefined: NaN
                    let k0 = w >= 0 && w < kernelCount ? Double(kernel[w]) : .nan
                    let k1 = w + 1 >= 0 && w + 1 < kernelCount ? Double(kernel[w + 1]) : .nan
                    let weight = k0 + (k1 - k0) * (u - whole)
                    if j < tapCount { taps[j] = Float(weight) }
                    //? the sum takes the weight as computed, a double - not the Float32 the taps keep
                    total += weight
                }
                norm = total != 0 ? (shape * state.gain) / total : 0
            }
            //? :699
            let n = limitN
            let slot = n & mask
            var loudest = 0.0
            for c in 0..<count {
                var value = 0.0
                if used > 0, let win {
                    let data = win.channel(c % win.channelCount)
                    let last = win.length - 1
                    let from = first < 0 ? -first : 0
                    let to = first + used - 1 > last ? last - first + 1 : used
                    var sum = 0.0
                    var j = from
                    while j < to {
                        let tap = j < tapCount ? Double(taps[j]) : .nan
                        sum += Double(data[first + j]) * tap
                        j += 1
                    }
                    value = sum * norm
                }
                //? :715 the DC blocker: y = x - x[-1] + pole y[-1]
                let out = value - state.lastIn[c] + pole * state.lastOut[c]
                state.lastIn[c] = value
                state.lastOut[c] = out
                //? :719 into the limiter's delay - anything that isn't a number as silence
                let held = out > -Double.infinity && out < Double.infinity ? out : 0
                delayLine[c * ring + slot] = held
                let magnitude = held < 0 ? -held : held
                if magnitude > loudest { loudest = magnitude }
            }
            //? :725 this sample's need
            let need = loudest > ceiling ? (ceiling / loudest) * safe : 1
            needs[slot] = need
            let outSlot = (slot - lookahead) & mask
            var gain = 1.0
            if need == 1 && env == 1 && lowA == 0 && lowB == 0 && minOf[head & minMask] == 1 {
                //? :733 at rest
                wasOver = false
                minAt[head & minMask] = Double(n)
                tail = head + 1
                boxA[slot] = 1
                boxB[slot] = 1
            } else {
                if need < 1 {
                    heldCount += 1
                    if !wasOver { peakCount += 1 }
                    wasOver = true
                } else { wasOver = false }
                //? :746 the lowest need over the lookahead
                while tail > head && minOf[(tail - 1) & minMask] >= need { tail -= 1 }
                minAt[tail & minMask] = Double(n)
                minOf[tail & minMask] = need
                tail += 1
                while minAt[head & minMask] < Double(n - span) { head += 1 }
                let lowest = minOf[head & minMask]
                //? :753 held, and back up over the release
                if lowest < env { env = lowest }
                else {
                    env += (lowest - env) * releaseAlpha
                    if lowest == 1 && 1 - env <= snap { env = 1 }
                }
                //? :760 the two boxes
                let leaveA = boxA[(slot - lengthA) & mask]
                boxA[slot] = env
                sumA += env - leaveA
                lowA += (env < 1 ? 1 : 0) - (leaveA < 1 ? 1 : 0)
                if lowA == 0 { sumA = Double(lengthA) }
                else if slot == 0 {
                    sumA = 0
                    for k in 0..<lengthA { sumA += boxA[(ring - k) & mask] }
                }
                let averaged = lowA == 0 ? 1 : sumA / Double(lengthA)
                let leaveB = boxB[(slot - lengthB) & mask]
                boxB[slot] = averaged
                sumB += averaged - leaveB
                lowB += (averaged < 1 ? 1 : 0) - (leaveB < 1 ? 1 : 0)
                if lowB == 0 { sumB = Double(lengthB) }
                else if slot == 0 {
                    sumB = 0
                    for k in 0..<lengthB { sumB += boxB[(ring - k) & mask] }
                }
                //? :785
                gain = lowB == 0 ? 1 : sumB / Double(lengthB)
                let due = needs[outSlot]
                if gain > due { gain = due }
                if !(gain >= 0) { gain = 0 }
                if gain < lowestGain { lowestGain = gain }
            }
            for c in 0..<count { outputs[c][i] = Float(delayLine[c * ring + outSlot] * gain) }
            limitN = n + 1
        }
        //? :794
        state.limitN = limitN
        state.limitMinHead = head
        state.limitMinTail = tail
        state.limitEnv = env
        state.limitLowA = lowA
        state.limitLowB = lowB
        state.limitSumA = sumA
        state.limitSumB = sumB
        state.limitHeld = heldCount
        state.limitPeaks = peakCount
        state.limitWasOver = wasOver
        state.limitLowest = lowestGain
    }

    // MARK: - voiceReport (deckVoice.ts:813)

    /// After `frames` samples played from context time `now`: what the voice says of where it is, when
    /// `perSecond` times a second come round, or nil.
    public static func voiceReport(_ state: inout VoiceState, _ frames: Int, _ sampleRate: Double, _ now: Double, _ perSecond: Double) -> VoiceHeard? {
        state.counted += Double(frames)
        let every = sampleRate / perSecond
        if state.counted < every { return nil }
        state.counted -= every
        let heard = VoiceHeard(pos: state.pos, rate: state.rate, gain: state.gain, time: now, held: Double(state.limitHeld),
                               peaks: Double(state.limitPeaks), lowest: state.limitLowest)
        state.limitHeld = 0
        state.limitPeaks = 0
        state.limitLowest = 1
        return heard
    }
}
