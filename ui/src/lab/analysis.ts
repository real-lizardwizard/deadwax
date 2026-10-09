/**
 * What the test bench works out from a recording (2.0.0-player.36) - pure, so ui/test/lab.sim.cjs runs
 * it as the page does. James, after three blind renders didn't separate for him: "maybe my expectations
 * are skewed". So the bench puts what deadwax played (A) beside two ideal turntables turned the same way:
 *
 *  - B, ideal on deadwax's own path: the voice's messages replayed through the voice's very functions
 *    (lib/deckVoice.ts - imported, nothing added to them) at the host's own timing (`replay`), the read
 *    head read every sample, and the signal read EXACTLY there - its definition evaluated at that place,
 *    or for samples a long windowed sinc (readExactly) - at the voice's own loudness and delay. B against
 *    A is the voice's own reading of the song: its kernel, its DC blocker, its limiter, its host.
 *  - C, ideal on a smooth path: the hand's own samples joined by a smooth curve that looks both ways and
 *    has no real-time limits (smoothPath - or, for a motion, the motion's exact path), placed the same
 *    delay behind, and the signal read exactly along it. C against A is everything deadwax's real-time
 *    path adds: the fit, the feed-forward, the steering, the clock.
 *
 * And it measures: how far deadwax's read head strayed from the smooth path; the speed's wobble above
 * 20 Hz, for each path (speedWobble); and, for a tone, the sound in A that isn't the signal - by frame,
 * the energy away from B's own frequencies against the energy at them (stray), so a slow timing drift
 * counts for nothing.
 */

import { newVoiceState, renderVoice, voiceCommand, VOICE_LOOKAHEAD_S, type VoiceHeard, type VoiceMessage, type VoiceState } from '../lib/deckVoice'
import { SCRIPT_BUFFER } from '../player/deck'

/* ===== the FFT ===== */

const twiddles = new Map<number, { cos: Float64Array; sin: Float64Array; reverse: Uint32Array }>()

function plan(size: number) {
  let made = twiddles.get(size)
  if (made) return made
  const cos = new Float64Array(size / 2), sin = new Float64Array(size / 2)
  for (let i = 0; i < size / 2; i++) {
    cos[i] = Math.cos((2 * Math.PI * i) / size)
    sin[i] = -Math.sin((2 * Math.PI * i) / size)
  }
  const bits = Math.round(Math.log2(size))
  const reverse = new Uint32Array(size)
  for (let i = 0; i < size; i++) {
    let r = 0
    for (let b = 0; b < bits; b++) if (i & (1 << b)) r |= 1 << (bits - 1 - b)
    reverse[i] = r
  }
  made = { cos, sin, reverse }
  twiddles.set(size, made)
  return made
}

/** An FFT in place, of a power-of-two length; `inverse` without the 1/N. */
export function fft(re: Float64Array, im: Float64Array, inverse = false): void {
  const size = re.length
  const { cos, sin, reverse } = plan(size)
  for (let i = 0; i < size; i++) {
    const j = reverse[i]!
    if (j > i) {
      const r = re[i]!; re[i] = re[j]!; re[j] = r
      const m = im[i]!; im[i] = im[j]!; im[j] = m
    }
  }
  const sign = inverse ? -1 : 1
  for (let span = 2; span <= size; span *= 2) {
    const half = span / 2, step = size / span
    for (let start = 0; start < size; start += span) {
      for (let k = 0; k < half; k++) {
        const wr = cos[k * step]!, wi = sign * sin[k * step]!
        const a = start + k, b = a + half
        const xr = re[b]! * wr - im[b]! * wi
        const xi = re[b]! * wi + im[b]! * wr
        re[b] = re[a]! - xr
        im[b] = im[a]! - xi
        re[a] = re[a]! + xr
        im[a] = im[a]! + xi
      }
    }
  }
}

/** A minimum 4-term Blackman-Harris window: its sidelobes 92 dB down, its main lobe 4 bins either side. */
export function blackmanHarris(size: number): Float64Array {
  const out = new Float64Array(size)
  for (let i = 0; i < size; i++) {
    const x = (2 * Math.PI * i) / size
    out[i] = 0.35875 - 0.48829 * Math.cos(x) + 0.14128 * Math.cos(2 * x) - 0.01168 * Math.cos(3 * x)
  }
  return out
}

/** The power in each bin of a windowed frame of `data` from `start` (zeros past its end). */
function framePower(data: Float32Array, start: number, window: Float64Array, re: Float64Array, im: Float64Array, out: Float64Array): void {
  const size = window.length
  for (let i = 0; i < size; i++) {
    const n = start + i
    re[i] = n >= 0 && n < data.length ? data[n]! * window[i]! : 0
    im[i] = 0
  }
  fft(re, im)
  for (let k = 0; k <= size / 2; k++) out[k] = re[k]! * re[k]! + im[k]! * im[k]!
}

const nextPower = (n: number) => 2 ** Math.ceil(Math.log2(Math.max(2, n)))

/* ===== replaying the voice ===== */

/** A message as the deck's recorder notes it: when it was posted (page ms, `t`) and the message itself -
 *  a window by its shape only (start, rate, length). */
export type RecordedMessage = { t: number; type: string } & Record<string, unknown>

export interface ReplaySource {
  voice: 'worklet' | 'script'
  sampleRate: number
  messages: RecordedMessage[]
  heard: VoiceHeard[]
  /** the clock's mapping as the recording ended: context seconds less page seconds */
  offset: number
  scriptLagSeconds: number
  /** the frames the voice rendered at a time, as the recording says (2.0.0-player.40: the main-thread voice's
   *  512 or 1024) - a recording that doesn't say (one made before .40) rendered SCRIPT_BUFFER */
  block?: number
}

export interface VoiceWindowIn {
  channels: Float32Array[]
  start: number
  rate: number
}

export interface ReplayOptions {
  /** the block each message is told before (Timing's `told`), the messages taken in the order posted */
  told: number[]
  /** context seconds to render */
  from: number
  to: number
  /** the window the voice had as the recording began */
  windowAtStart?: VoiceWindowIn | null
  /** the channels of a window the recording says the deck sent */
  windowFor?: ((start: number, rate: number, length: number) => Float32Array[] | null) | null
}

export interface Replayed {
  /** context time of sample 0, the sample rate, how many samples */
  t0: number
  rate: number
  n: number
  /** where the read head read each sample (song s), how fast, and how loud it sounded (the voice's gain
   *  times its fade at the window's edges) */
  pos: Float64Array
  speed: Float64Array
  gain: Float64Array
  /** what the voice wrote, left channel - its lookahead later than what it read */
  audio: Float32Array
  /** the context time each sample was rendered at, as the voice had it (`now + i * dt` of its block) */
  time: Float64Array
  /** the limiter's lookahead, samples: what the voice writes is this much later than what it reads */
  lookahead: number
  /** the sample the first take was applied before (-1: none) */
  firstTake: number
}

/** The voice's block, in samples: the main-thread voice's, as its recording says it (2.0.0-player.40 - read
 *  from the file, never the build replaying it: a recording made in blocks of 512 replays in blocks of 512;
 *  one that doesn't say was made in SCRIPT_BUFFER), and the worklet's render quantum. */
export function blockOf(source: Pick<ReplaySource, 'voice' | 'block'>): number {
  if (source.voice !== 'script') return 128
  return typeof source.block === 'number' && source.block > 0 ? source.block : SCRIPT_BUFFER
}

/** The blocks' times: the main-thread voice's from its own reports, the worklet's on the context's frame
 *  grid (its currentTime is a whole number of frames over the rate). */
function grid(source: ReplaySource, from: number) {
  const rate = source.sampleRate
  const frames = blockOf(source)
  const first = source.heard[0]?.time ?? from
  if (source.voice === 'script') {
    const seconds = frames / rate
    //? A block that reported says its own time - what the main-thread voice rendered it at: the stamp
    //? when it agreed with the count to a millisecond, the count otherwise (deck.ts's startScript). And
    //? a stamp need not move a block's length a block: a clock running a little fast or slow against the
    //? rate (headless Chromium's moves 1023 frames in 1024) is followed, so the reports are numbered as
    //? blocks one after another - each 1 block or more after the last - and the blocks between and
    //? around them timed along the line through them, never on a grid of the rate's
    const indices: number[] = [], times: number[] = []
    let index = 0
    source.heard.forEach((heard, i) => {
      if (i > 0) index += Math.max(1, Math.round((heard.time - source.heard[i - 1]!.time) / seconds))
      indices.push(index)
      times.push(heard.time)
    })
    const last = indices.length - 1
    const at = (b: number) => {
      if (last < 0) return first + b * seconds
      if (b <= indices[0]!) return times[0]! + (b - indices[0]!) * seconds
      if (b >= indices[last]!) return times[last]! + (b - indices[last]!) * seconds
      let lo = 0, hi = last
      while (hi - lo > 1) {
        const mid = (lo + hi) >> 1
        if (indices[mid]! <= b) lo = mid
        else hi = mid
      }
      if (indices[lo] === b) return times[lo]!
      return times[lo]! + ((b - indices[lo]!) * (times[hi]! - times[lo]!)) / (indices[hi]! - indices[lo]!)
    }
    //? the block whose time is the last at or before `t`
    const index_ = (t: number) => {
      let b = Math.floor((t - first) / seconds)
      while (at(b + 1) <= t) b++
      while (b > -1e7 && at(b) > t) b--
      return b
    }
    return { frames, at, index: index_, reported: (i: number) => indices[i]! }
  }
  const f0 = Math.round(first * rate)
  return { frames, at: (b: number) => (f0 + b * frames) / rate, index: (t: number) => Math.floor((t * rate - f0) / frames), reported: (i: number) => Math.round((source.heard[i]!.time * rate - f0) / frames) }
}

/** A message as the voice is told it - the main-thread voice hears what is timed its lag later
 *  (deck.ts's startScript) - or null for one the replay can't give (a window it doesn't have). */
function told(source: ReplaySource, message: RecordedMessage, windowFor: ReplayOptions['windowFor']): VoiceMessage | null {
  const lag = source.voice === 'script' ? source.scriptLagSeconds : 0
  const m = message as unknown as Record<string, number> & { type: string }
  if (message.type === 'window') {
    const channels = windowFor?.(m.start!, m.rate!, m.length!) ?? null
    return channels ? { type: 'window', channels, start: m.start!, rate: m.rate! } : null
  }
  if (message.type === 'take') return { type: 'take', at: m.at!, rate: m.rate!, time: m.time! + lag, until: m.until! + lag }
  if (message.type === 'drive') {
    return { type: 'drive', at: m.at!, rate: m.rate!, ...(typeof m.accel === 'number' ? { accel: m.accel } : {}), time: m.time! + lag, until: m.until! + lag }
  }
  if (message.type === 'hand') return { type: 'hand', at: m.at!, time: m.time! + lag }
  if (message.type === 'fade') return { type: 'fade', seconds: m.seconds! }
  if (message.type === 'stop') return { type: 'stop' }
  return null
}

/** The voice's fade at its window's edges (deck voice's EDGE_S) - what sounds of a sample it reads. */
const EDGE_S = 0.004
function edgeShape(state: VoiceState): number {
  const win = state.window
  if (!win || !(state.gain > 1e-5)) return 0
  const index = (state.pos - win.start) * win.rate
  const edge = Math.min(index, win.length - 1 - index) / (EDGE_S * win.rate)
  return edge <= 0 ? 0 : edge >= 1 ? 1 : edge
}

function starting(source: ReplaySource, from: number, to: number) {
  const g = grid(source, from)
  const startBlock = g.index(from)
  const endBlock = g.index(to) + 1
  const messages = source.messages.map((message) => ({ message, at: message.t / 1000 + source.offset })).sort((a, b) => a.at - b.at)
  return { g, startBlock, endBlock, messages }
}

/**
 * The voice played again from rest, the recording's messages told it at its host's timing (`told`) - and
 * its read head read EVERY sample, rendering one at a time: renderVoice over one sample is the same
 * arithmetic as over a block (its time `now + i * dt` handed over exactly), so what it writes is what the
 * host wrote. From rest: a recording begun while the voice was sounding is replayed rightly only from its
 * first take.
 */
export function replay(source: ReplaySource, options: ReplayOptions): Replayed {
  const rate = source.sampleRate
  const state = newVoiceState()
  const { g, startBlock, endBlock, messages } = starting(source, options.from, options.to)
  const n = Math.max(0, (endBlock - startBlock) * g.frames)
  const pos = new Float64Array(n), speed = new Float64Array(n), gain = new Float64Array(n)
  const audio = new Float32Array(n)
  const time = new Float64Array(n)
  const outs = [new Float32Array(1), new Float32Array(1)]
  const dt = 1 / rate
  let next = 0
  let firstTake = -1
  if (options.windowAtStart) voiceCommand(state, { type: 'window', ...options.windowAtStart }, g.at(startBlock), rate)
  let i = 0
  for (let b = startBlock; b < endBlock; b++) {
    const at = g.at(b)
    while (next < messages.length && (options.told[next] ?? Infinity) <= b) {
      const said = told(source, messages[next]!.message, options.windowFor ?? null)
      next++
      if (!said) continue
      if (said.type === 'take' && firstTake < 0) firstTake = i
      voiceCommand(state, said, at, rate)
    }
    for (let k = 0; k < g.frames; k++, i++) {
      renderVoice(state, outs, 1, rate, at + k * dt)
      time[i] = at + k * dt
      pos[i] = state.pos
      speed[i] = state.rate
      gain[i] = state.gain * edgeShape(state)
      audio[i] = outs[0]![0]!
    }
  }
  const lookahead = Math.max(1, Math.round(VOICE_LOOKAHEAD_S * rate))
  return { t0: g.at(startBlock), rate, n, pos, speed, gain, audio, time, lookahead, firstTake }
}

/** How a timing fits: the path alone replayed a block at a time (no window - the path needs none), its
 *  read head at each block's end held against what the voice said of itself there - once it followed a
 *  take: the worst miss and the summed misses, song seconds, and how many reports. */
function fitOf(source: ReplaySource, told: number[], from: number, to: number): { worst: number; sum: number; reports: number } {
  const rate = source.sampleRate
  const state = newVoiceState()
  const { g, startBlock, endBlock, messages } = starting(source, from, to)
  const outs = [new Float32Array(g.frames), new Float32Array(g.frames)]
  const byBlock = new Map<number, VoiceHeard>()
  source.heard.forEach((heard, i) => byBlock.set(g.reported(i), heard))
  let next = 0
  let taken = false
  let worst = 0, sum = 0, reports = 0
  for (let b = startBlock; b < endBlock; b++) {
    const at = g.at(b)
    while (next < messages.length && (told[next] ?? Infinity) <= b) {
      const said = told_(source, messages[next]!.message)
      next++
      if (!said) continue
      if (said.type === 'take') taken = true
      voiceCommand(state, said, at, rate)
    }
    renderVoice(state, outs, g.frames, rate, at)
    const heard = byBlock.get(b)
    if (heard && taken) {
      const miss = Math.abs(state.pos - heard.pos)
      worst = Math.max(worst, miss)
      sum += miss
      reports++
    }
  }
  return { worst, sum, reports }
}

/** A message as the voice is told it, with no window (the path needs none). */
const told_ = (source: ReplaySource, message: RecordedMessage) => told(source, message, null)

/** Which messages' timing changes what is heard: a take places the read head as of when it is told, and a
 *  fade or a stop starts then. A hand's sample, a drive or a window says when it means, whatever block it
 *  reaches the voice in. */
const timed = (type: string) => type === 'take' || type === 'fade' || type === 'stop'

export interface Timing {
  /** the block each message is told before, in the order they were posted */
  told: number[]
  /** the lead the rest were told at: how long after a message is posted the voice is told it, seconds */
  lead: number
  /** the worst miss against the voice's own reports, song seconds (Infinity: none to hold it to), and how
   *  many reports */
  worst: number
  reports: number
}

/**
 * When the voice was told each message, worked out from what it said of itself. The main-thread voice
 * holds a message to the next block asked for, a block or so before it plays; the worklet takes one as
 * it arrives - so each message is told at the first block at least a LEAD after it was posted, the lead
 * that fits the reports best, of a few a host can have. Then each take, fade and stop - the messages whose
 * timing is heard - is moved to the block that fits best within a few either side, in the order posted:
 * one sent from a timer rather than a frame can reach the voice a block sooner or later than the rest.
 */
export function planTiming(source: ReplaySource, from: number, to: number): Timing {
  const block = blockOf(source) / source.sampleRate
  const { g, messages } = starting(source, from, to)
  const toldAt = (lead: number) => messages.map(({ at }) => {
    let b = g.index(at + lead)
    if (g.at(b) < at + lead - 1e-12) b++
    return b
  })
  const steps = source.voice === 'script' ? [0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3, 4] : [-1, 0, 1, 2, 3, 4, 6, 8, 12, 16]
  let best = { lead: block, told: toldAt(block), worst: Infinity, sum: Infinity, reports: 0 }
  for (const step of steps) {
    const told = toldAt(step * block)
    const fit = fitOf(source, told, from, to)
    if (fit.reports && fit.sum < best.sum - 1e-12) best = { lead: step * block, told, ...fit }
  }
  if (!best.reports) return { told: best.told, lead: best.lead, worst: Infinity, reports: 0 }
  const told = [...best.told]
  let sum = best.sum, worst = best.worst
  messages.forEach(({ message }, j) => {
    if (!timed(message.type)) return
    const low = j > 0 ? told[j - 1]! : -Infinity
    const high = j + 1 < told.length ? told[j + 1]! : Infinity
    const here = told[j]!
    for (let c = Math.max(low, here - 3); c <= Math.min(high, here + 3); c++) {
      if (c === told[j]) continue
      const trial = [...told]
      trial[j] = c
      const fit = fitOf(source, trial, from, to)
      if (fit.sum < sum - 1e-12) {
        told[j] = c
        sum = fit.sum
        worst = fit.worst
      }
    }
  })
  return { told, lead: best.lead, worst, reports: best.reports }
}

/* ===== reading the song exactly ===== */

/** What an ideal reader lets through at speed `v`, in the song's own Hz: what lands under the output's
 *  Nyquist frequency - an ideal (brick-wall) resampler. */
export function cutoffAt(speed: number, outRate: number): number {
  const v = Math.abs(speed)
  return v > 1e-9 ? outRate / 2 / v : Infinity
}

/**
 * The signal read exactly along a path: each output sample `exact(place, cutoff)` - at the place the read
 * head had `lookahead` samples before (the voice's own lag in writing), at the loudness it had then,
 * band-limited to what the output can hold at the speed it read at.
 */
export function readExactly(
  exact: (t: number, cutoff: number) => number, place: ArrayLike<number>, speed: ArrayLike<number>, gain: ArrayLike<number>, outRate: number, lookahead: number,
): Float32Array {
  const n = place.length
  const out = new Float32Array(n)
  for (let i = lookahead; i < n; i++) {
    const j = i - lookahead
    const g = gain[j]!
    if (!(g > 0)) continue
    out[i] = g * exact(place[j]!, cutoffAt(speed[j]!, outRate))
  }
  return out
}

/* ===== the smooth path ===== */

export interface PathPoint {
  x: number
  v: number
}

/**
 * A motion's exact path, in the stamped context time the deck's messages carry: the motion's own
 * definition - where it has the song, and how fast - with no finger's jitter, whatever the samples
 * carried. Its knots are its samples at the times the deck stamped them, as a smooth curve through the
 * stamps has them (the deck's clock mapping slews a little through a gesture, and moves C as it moves A -
 * but its stamps go up a few microseconds unevenly, frame to frame, and knots placed on them with the
 * definition's speeds kinked at every one: a 60 Hz ripple, sidebands 64 dB down, C dirtier than A -
 * review of 2.0.0-player.36). `at` is the definition itself at any moment, through the same curve.
 */
export interface ExactMotion {
  knots: { time: number; x: number; v: number }[]
  /** where the definition has the song at stamped time `tau`, and how fast - between the knots too */
  at?: (tau: number) => PathPoint
}

/** How far either side the curve through the deck's stamps looks, seconds: wide enough that a frame's
 *  unevenness counts for nothing, narrow enough to follow the mapping's slew within a gesture. */
export const STAMP_SMOOTH_S = 0.5

/** The cubic through two ends' places and speeds (Hermite), at `tau`: the place and the speed. */
function hermite(t0: number, x0: number, v0: number, t1: number, x1: number, v1: number, tau: number): PathPoint {
  const h = t1 - t0
  if (!(h > 0)) return { x: x1, v: v1 }
  const s = (tau - t0) / h
  const s2 = s * s, s3 = s2 * s
  return {
    x: (2 * s3 - 3 * s2 + 1) * x0 + (s3 - 2 * s2 + s) * h * v0 + (3 * s2 - 2 * s3) * x1 + (s3 - s2) * h * v1,
    v: ((6 * s2 - 6 * s) * x0 + (3 * s2 - 4 * s + 1) * h * v0 + (6 * s - 6 * s2) * x1 + (3 * s2 - 2 * s) * h * v1) / h,
  }
}

/** A natural cubic spline through (t, y) - t rising: its value and slope at any t (held flat past the ends). */
export function naturalSpline(t: number[], y: number[]): (at: number) => PathPoint {
  const n = t.length
  const m = new Float64Array(n)
  if (n > 2) {
    //? the second derivatives at the knots: a tridiagonal system, ends free (natural)
    const c = new Float64Array(n), d = new Float64Array(n)
    for (let i = 1; i < n - 1; i++) {
      const h0 = t[i]! - t[i - 1]!, h1 = t[i + 1]! - t[i]!
      const a = h0 / 6, b = (h0 + h1) / 3, cc = h1 / 6
      const rhs = (y[i + 1]! - y[i]!) / h1 - (y[i]! - y[i - 1]!) / h0
      const denom = b - a * c[i - 1]!
      c[i] = cc / denom
      d[i] = (rhs - a * d[i - 1]!) / denom
    }
    for (let i = n - 2; i >= 1; i--) m[i] = d[i]! - c[i]! * m[i + 1]!
  }
  return (at) => {
    if (n === 0) return { x: 0, v: 0 }
    if (n === 1 || at <= t[0]!) return { x: y[0]!, v: n > 1 ? (y[1]! - y[0]!) / (t[1]! - t[0]!) - ((t[1]! - t[0]!) * m[1]!) / 6 : 0 }
    if (at >= t[n - 1]!) {
      const h = t[n - 1]! - t[n - 2]!
      return { x: y[n - 1]!, v: (y[n - 1]! - y[n - 2]!) / h + (h * m[n - 2]!) / 6 }
    }
    const i = Math.max(0, lowerBound(t, at) - 1)
    const h = t[i + 1]! - t[i]!
    const a = (t[i + 1]! - at) / h, b = (at - t[i]!) / h
    return {
      x: a * y[i]! + b * y[i + 1]! + ((a * a * a - a) * m[i]! + (b * b * b - b) * m[i + 1]!) * (h * h) / 6,
      v: (y[i + 1]! - y[i]!) / h + ((-(3 * a * a - 1) * m[i]!) + (3 * b * b - 1) * m[i + 1]!) * h / 6,
    }
  }
}

/** A motion's exact path from the recording's own hand samples (after its take, in order) and the
 *  motion's samples (page ms, from the take): where the definition has the song at each, and how fast,
 *  through a smooth curve of the deck's stamps against the page's clock. Null when the two don't pair
 *  one to one. */
export function exactKnots(
  messages: RecordedMessage[], samples: { time: number }[], from: number, anchor: number, length: number,
  path: (t: number) => number, speed: (t: number) => number,
): ExactMotion | null {
  const take = messages.findIndex((m) => m.type === 'take')
  if (take < 0) return null
  const hands = messages.slice(take + 1).filter((m) => m.type === 'hand')
  if (hands.length < samples.length || !samples.length) return null
  const page = samples.map((sample) => (sample.time - from) / 1000)
  for (let k = 1; k < page.length; k++) if (!(page[k]! > page[k - 1]!) || !((hands[k]!.time as number) > (hands[k - 1]!.time as number))) return null
  //? how far each stamp is from the page's clock, smoothed (zero-phase, STAMP_SMOOTH_S either side), and
  //? a natural cubic spline through the smoothed values: its slope is the derivative of the very curve
  //? its places lie on, and its second derivative is continuous - a local fit's own slope is not, and a
  //? cubic between knots made to meet it wiggles at 60 Hz again
  const residual = page.map((t, k) => (hands[k]!.time as number) - t)
  const smoothed = page.map((t) => {
    const lo = lowerBound(page, t - STAMP_SMOOTH_S)
    const hi = Math.min(page.length - 1, lowerBound(page, t + STAMP_SMOOTH_S))
    return fitAt(page, residual, lo, hi, t, STAMP_SMOOTH_S).x
  })
  const curve = naturalSpline(page, smoothed)
  const clamp = (x: number) => Math.max(0, Math.min(length || Infinity, x))
  const point = (t: number, slope: number): PathPoint => {
    const x = anchor + path(t)
    const held = clamp(x)
    return { x: held, v: held === x ? speed(t) / (1 + slope) : 0 }
  }
  const knots = page.map((t, k) => ({ time: t + smoothed[k]!, ...point(t, curve(t).v) }))
  for (let k = 1; k < knots.length; k++) if (!(knots[k]!.time > knots[k - 1]!.time)) return null
  const knotTimes = knots.map((k) => k.time)
  const at = (tau: number): PathPoint => {
    if (tau <= knotTimes[0]!) return { x: knots[0]!.x, v: knots[0]!.v }
    if (tau >= knotTimes[knotTimes.length - 1]!) return { x: knots[knots.length - 1]!.x, v: knots[knots.length - 1]!.v }
    const k = Math.max(0, lowerBound(knotTimes, tau) - 1)
    //? the page time stamped `tau`, by Newton's method from the line between the knots
    let t = page[k]! + ((tau - knotTimes[k]!) * (page[k + 1]! - page[k]!)) / (knotTimes[k + 1]! - knotTimes[k]!)
    let r = curve(t)
    for (let i = 0; i < 4; i++) {
      t -= (t + r.x - tau) / (1 + r.v)
      r = curve(t)
    }
    return point(t, r.v)
  }
  return { knots, at }
}

/* ----- the hand's own samples ----- */

/** A gap between a hand's samples longer than this is a rest (the hand held still), seconds - the voice's
 *  own rule (lib/deckVoice.ts REST_S) - ... */
export const REST_GAP_S = 0.04
/** ...unless, no more than MISSED_GAP_S after the last, the next sample is where the hand's speed at the
 *  last would have it, to within KEPT_ON of how far that is (or KEPT_S): samples went missing (a busy page,
 *  no coalesced events on plain http) and the hand kept moving through them - the voice's MISSED_S,
 *  KEPT_ON and KEPT_S (review of 2.0.0-player.36: three missed frames read as a rest stalled C 67 ms and
 *  jumped it as far, where the voice ran on through them). */
export const MISSED_GAP_S = 0.1
export const KEPT_ON = 0.25
export const KEPT_S = 0.003
/** After a run's last sample the path runs on this long, slowing to still where the hand rests (the voice's
 *  EXTRAPOLATE_S), and a hand moving again set off at most this long before its first sample (RESUME_S). */
export const RUN_ON_S = 0.02
export const SET_OFF_S = 0.017
/** Where one part of the path hands over to the next - a hand's run to its rest, a rest to the next run,
 *  the hand to the coast it let go into, a coast to the hand that caught it - the next part's speed is
 *  reached over JOIN_BRIDGE_S, by the cubic through both ends' places and speeds, and any difference in
 *  place between the two let go of smoothly over JOIN_DECAY_S: no step in place or speed anywhere, so the
 *  ideal turntable never clicks where deadwax doesn't (review of 2.0.0-player.36: C jumped up to 2.3 ms of
 *  the song at a let-go, 5.4 with a motion's jitter, 8.8 at a resume - each a click in C alone). */
export const JOIN_BRIDGE_S = 0.03
export const JOIN_DECAY_S = 0.3
/** The smooth path's half-width: each point a tricube-weighted parabola over the hand's samples this far
 *  either side - looking ahead as far as back, which no real-time voice can. */
export const SMOOTH_HALF_S = 0.15
/** The smooth curve is worked out this often, seconds, and a spline drawn through it. */
export const SMOOTH_GRID_S = 1 / 240

/** A part of a path: from `start` until the next part's, where it has the song at each moment. */
export interface PathPiece {
  start: number
  at: (tau: number) => PathPoint
  /** where the record was, and how fast, as this part began - joined from as the one before would be,
   *  when nothing came before it (a take: the record as the hand found it) */
  from?: PathPoint | undefined
}

/** The let-go of a difference in place: 1 to 0 over JOIN_DECAY_S, flat at both ends - and its slope. */
function letGo(u: number): [number, number] {
  if (u <= 0) return [1, 0]
  if (u >= JOIN_DECAY_S) return [0, 0]
  const a = (Math.PI * u) / JOIN_DECAY_S
  return [0.5 * (1 + Math.cos(a)), (-0.5 * Math.PI * Math.sin(a)) / JOIN_DECAY_S]
}

/**
 * Parts of a path joined with no step in place or speed: each part from where the one before had got to
 * (the first from its own `from`, if it has one) - the difference between them let go of over
 * JOIN_DECAY_S, smoothly - its speed reached over JOIN_BRIDGE_S by the cubic through both ends' places
 * and speeds. Null before the first part.
 */
export function joinPieces(pieces: PathPiece[]): (tau: number) => PathPoint | null {
  const sorted = [...pieces].sort((a, b) => a.start - b.start)
  const starts = sorted.map((piece) => piece.start)
  const joins: { left: PathPoint; shift: number }[] = []
  const own = (k: number, tau: number): PathPoint => {
    const point = sorted[k]!.at(tau)
    const join = joins[k]
    if (!join) return point
    const [d, slope] = letGo(tau - starts[k]!)
    return { x: point.x + join.shift * d, v: point.v + join.shift * slope }
  }
  const value = (k: number, tau: number): PathPoint => {
    const join = joins[k]
    const s = starts[k]!
    if (!join || tau >= s + JOIN_BRIDGE_S) return own(k, tau)
    const end = s + JOIN_BRIDGE_S
    const b = own(k, end)
    return hermite(s, join.left.x, join.left.v, end, b.x, b.v, tau)
  }
  //? the place let go of: the difference at the start - and what the speed's difference over the bridge
  //? leaves (half of it, the bridge carrying the speed over evenly), so the bridge never runs past the
  //? part's own speed to make up the place: that is let go of over JOIN_DECAY_S, gently
  const joinFrom = (left: PathPoint, k: number) => {
    const own = sorted[k]!.at(starts[k]!)
    return { left, shift: left.x - own.x + ((left.v - own.v) * JOIN_BRIDGE_S) / 2 }
  }
  const first = sorted[0]?.from
  if (first) joins[0] = joinFrom(first, 0)
  for (let k = 1; k < sorted.length; k++) joins[k] = joinFrom(value(k - 1, starts[k]!), k)
  return (tau) => {
    if (!sorted.length || tau < starts[0]!) return null
    return value(Math.max(0, lowerBound(starts, tau + 1e-12) - 1), tau)
  }
}

/** A weighted parabola through (t, x) samples [lo, hi] around `tau`: its place and slope there. */
function fitAt(times: number[], places: number[], lo: number, hi: number, tau: number, half: number): PathPoint {
  let s0 = 0, s1 = 0, s2 = 0, s3 = 0, s4 = 0, x0 = 0, x1 = 0, x2 = 0, used = 0
  const base = places[lo]!
  for (let j = lo; j <= hi; j++) {
    const u = (times[j]! - tau) / half
    const d = Math.abs(u)
    if (d >= 1) continue
    const w3 = 1 - d * d * d
    const w = w3 * w3 * w3
    const x = places[j]! - base
    const u2 = u * u
    s0 += w; s1 += w * u; s2 += w * u2; s3 += w * u2 * u; s4 += w * u2 * u2
    x0 += w * x; x1 += w * u * x; x2 += w * u2 * x
    used++
  }
  const m0 = s2 * s4 - s3 * s3, m1 = s1 * s4 - s2 * s3, m2 = s1 * s3 - s2 * s2
  const det = s0 * m0 - s1 * m1 + s2 * m2
  if (used >= 3 && Math.abs(det) > 1e-12 * s0 * s0 * s0) {
    const a = (x0 * m0 - s1 * (x1 * s4 - s3 * x2) + s2 * (x1 * s3 - s2 * x2)) / det
    const b = (s0 * (x1 * s4 - s3 * x2) - x0 * m1 + s2 * (s1 * x2 - x1 * s2)) / det
    return { x: base + a, v: b / half }
  }
  const lineDet = s0 * s2 - s1 * s1
  if (used >= 2 && lineDet > 1e-12) return { x: base + (s2 * x0 - s1 * x1) / lineDet, v: (s0 * x1 - s1 * x0) / lineDet / half }
  //? one sample, or none near: the nearest
  let best = lo
  for (let j = lo; j <= hi; j++) if (Math.abs(times[j]! - tau) < Math.abs(times[best]! - tau)) best = j
  return { x: places[best]!, v: 0 }
}

/** The first index whose time is at least `t`. */
export function lowerBound(times: ArrayLike<number>, t: number): number {
  let lo = 0, hi = times.length
  while (lo < hi) {
    const mid = (lo + hi) >> 1
    if (times[mid]! < t) lo = mid + 1
    else hi = mid
  }
  return lo
}

/** After `end` (a run's last moment, its place and speed): run on RUN_ON_S, slowing to still, and held. */
function runOn(end: number, last: PathPoint, tau: number): PathPoint {
  const stop = end + RUN_ON_S
  const there = last.x + (last.v * RUN_ON_S) / 2
  if (tau >= stop) return { x: there, v: 0 }
  return hermite(end, last.x, last.v, stop, there, 0, tau)
}

/**
 * The hand's samples as a smooth path: at any moment, a tricube-weighted parabola over the samples within
 * `half` either side of it - zero-phase, the samples after a moment counting as much as those before - in
 * runs the way the voice has them: a gap is a rest only when the hand didn't keep moving through it (the
 * voice's REST_S, MISSED_S, KEPT_ON, KEPT_S). After a run the path runs on to still and holds; the next
 * run sets off just before its first sample; and every part hands over to the next with no step in place
 * or speed (joinPieces). Null before the first sample.
 */
export function smoothPath(samples: { time: number; at: number }[], half = SMOOTH_HALF_S): (tau: number) => PathPoint | null {
  const times = samples.map((s) => s.time)
  const places = samples.map((s) => s.at)
  if (!samples.length) return () => null
  //? the runs: a new one only where the hand rested
  const runs: [number, number][] = []
  let start = 0
  for (let i = 1; i < samples.length; i++) {
    const gap = times[i]! - times[i - 1]!
    if (gap <= REST_GAP_S) continue
    const last = fitAt(times, places, start, i - 1, times[i - 1]!, half)
    const moving = Math.abs(places[i]! - places[i - 1]!) > 1e-9
    if (moving && gap <= MISSED_GAP_S && Math.abs(places[i]! - last.x - last.v * gap) <= Math.max(KEPT_S, KEPT_ON * Math.abs(last.v * gap))) continue
    runs.push([start, i - 1])
    start = i
  }
  runs.push([start, samples.length - 1])
  const pieces: PathPiece[] = runs.map(([i0, i1], r) => {
    const begins = r === 0 ? times[i0]! : Math.max(times[runs[r - 1]![1]]! + RUN_ON_S, times[i0]! - SET_OFF_S)
    //? the run's smooth curve worked out every SMOOTH_GRID_S, and a natural cubic spline through it: the
    //? speed is then the curve's own rate of change - a local fit's slope isn't (it was a few per cent off
    //? where a finger's jitter is, so the place moved faster than the speed said)
    const grid: number[] = [], values: number[] = []
    const steps = Math.max(1, Math.ceil((times[i1]! - begins) / SMOOTH_GRID_S))
    for (let g = 0; g <= steps; g++) {
      const tau = g === steps ? times[i1]! : begins + g * SMOOTH_GRID_S
      if (grid.length && !(tau > grid[grid.length - 1]!)) continue
      const lo = Math.max(i0, lowerBound(times, tau - half))
      const hi = Math.min(i1, lowerBound(times, tau + half))
      grid.push(tau)
      values.push(fitAt(times, places, Math.min(lo, i1), Math.max(lo, hi), tau, half).x)
    }
    const curve = naturalSpline(grid, values)
    const end = curve(times[i1]!)
    return {
      start: begins,
      at: (tau) => (tau > times[i1]! ? runOn(times[i1]!, end, tau) : curve(tau)),
    }
  })
  return joinPieces(pieces)
}

/**
 * The whole path the recording's messages describe, in their own (stamped) time: the hand's samples
 * smoothed (smoothPath) - or a motion's exact path where `exact` is given - and a plan after a release
 * through its drives (the cubic through each pair's places and speeds, exact for the plan's own curve to
 * well under a millisecond), each part joined to the next with no step in place or speed (joinPieces: a
 * coast starts from where the ideal hand let go, not the hand's raw last sample, and the difference is let
 * go of smoothly). Null before anything took the record.
 */
export function pathFrom(messages: RecordedMessage[], exact: ExactMotion | null = null, half = SMOOTH_HALF_S): (tau: number) => PathPoint | null {
  type Drive = { time: number; at: number; rate: number; accel: number; until: number }
  const hands: { time: number; at: number }[][] = []
  const plans: Drive[][] = []
  let hand: { time: number; at: number }[] | null = null
  let plan: Drive[] | null = null
  const closeHand = () => {
    if (hand && hand.length) hands.push(hand)
    hand = null
  }
  const closePlan = () => {
    if (plan && plan.length) plans.push(plan)
    plan = null
  }
  for (const message of messages) {
    const m = message as unknown as Record<string, number> & { type: string }
    if (message.type === 'take') {
      closeHand()
      closePlan()
      hand = [{ time: m.time!, at: m.at! }]
    } else if (message.type === 'hand') {
      closePlan()
      if (!hand) hand = []
      const last = hand[hand.length - 1]
      if (last && m.time! < last.time) continue
      if (last && m.time === last.time) hand.pop()
      hand.push({ time: m.time!, at: m.at! })
    } else if (message.type === 'drive') {
      closeHand()
      if (!plan) plan = []
      //? a later word on a moment the plan has: what came after it goes, as the voice does it
      while (plan.length && plan[plan.length - 1]!.time >= m.time!) plan.pop()
      plan.push({ time: m.time!, at: m.at!, rate: m.rate!, accel: typeof m.accel === 'number' ? m.accel : 0, until: m.until! })
    }
  }
  closeHand()
  closePlan()
  const planAt = (drives: Drive[], tau: number): PathPoint => {
    let i = drives.length - 1
    while (i > 0 && drives[i]!.time > tau) i--
    const a = drives[i]!
    const b = drives[i + 1]
    if (b && tau >= a.time) return hermite(a.time, a.at, a.rate, b.time, b.at, b.rate, tau)
    const since = Math.max(0, Math.min(tau, a.until) - a.time)
    return { x: a.at + a.rate * since + 0.5 * a.accel * since * since, v: tau <= a.until ? a.rate + a.accel * since : 0 }
  }
  const pieces: PathPiece[] = []
  //? the record as each take found it - still, or turning at the speed it was taken at: what the hand (or a
  //? motion) sets off from where nothing came before, so the ideal turntable reaches the hand's speed over
  //? JOIN_BRIDGE_S, as a hand can, rather than at once (a motion's definition starts at its full speed:
  //? a click, in C alone)
  const takes = messages.filter((m) => m.type === 'take').map((m) => m as unknown as Record<string, number>)
  const fromTake = (start: number): PathPoint | undefined => {
    const take = takes.filter((m) => m.time! <= start + 1e-6).pop() ?? takes[0]
    return take ? { x: take.at! + (take.rate ?? 0) * (start - take.time!), v: take.rate ?? 0 } : undefined
  }
  const knots = exact?.knots ?? []
  const k0 = knots[0]?.time ?? Infinity, kN = knots[knots.length - 1]?.time ?? -Infinity
  for (const run of hands) {
    //? the hand of a motion whose exact path is known: that path in its place
    if (knots.length > 1 && run[0]!.time >= k0 - 1e-6 && run[0]!.time <= kN) continue
    const smooth = smoothPath(run, half)
    pieces.push({ start: run[0]!.time, at: (tau) => smooth(tau) ?? { x: run[0]!.at, v: 0 }, from: fromTake(run[0]!.time) })
  }
  if (knots.length > 1) {
    const between = exact?.at ?? ((tau: number): PathPoint => {
      //? between two of the motion's exact knots: the cubic through their places and speeds
      const i = Math.max(1, lowerBound(knots.map((k) => k.time), tau))
      const a = knots[i - 1]!, b = knots[i]!
      return hermite(a.time, a.x, a.v, b.time, b.x, b.v, tau)
    })
    const last = knots[knots.length - 1]!
    pieces.push({ start: k0, at: (tau) => (tau > kN ? runOn(kN, last, tau) : between(Math.max(k0, tau))), from: fromTake(k0) })
  }
  for (const drives of plans) pieces.push({ start: drives[0]!.time, at: (tau) => planAt(drives, tau) })
  return joinPieces(pieces)
}

/* ===== the measures ===== */

/** A 2nd-order Butterworth high-pass's coefficients at `hz` for samples at `rate`. */
function highPass(hz: number, rate: number) {
  const w = (2 * Math.PI * hz) / rate
  const alpha = Math.sin(w) / (2 * Math.SQRT1_2)
  const c = Math.cos(w)
  const a0 = 1 + alpha
  return { b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0, a1: (-2 * c) / a0, a2: (1 - alpha) / a0 }
}

function filter(data: Float64Array, f: ReturnType<typeof highPass>): Float64Array {
  const out = new Float64Array(data.length)
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0
  for (let i = 0; i < data.length; i++) {
    const x = data[i]!
    const y = f.b0 * x + f.b1 * x1 + f.b2 * x2 - f.a1 * y1 - f.a2 * y2
    x2 = x1; x1 = x; y2 = y1; y1 = y
    out[i] = y
  }
  return out
}

/** Where the speed's wobble is measured from: this many Hz up. */
export const WOBBLE_FROM_HZ = 20

/**
 * The speed's wobble above WOBBLE_FROM_HZ, as a share of the speed (per cent): the speed averaged to a
 * millisecond, high-passed there forwards and back (no phase), its RMS over the mean |speed| - the edges'
 * first and last 0.1 s left out, where the filter settles. Null over too little, or a record barely
 * moving.
 */
export function speedWobble(speed: ArrayLike<number>, rate: number, from = 0, to = speed.length): number | null {
  const bin = Math.max(1, Math.floor(rate / 1000))
  const binRate = rate / bin
  const count = Math.floor((to - from) / bin)
  if (count < 0.5 * binRate) return null
  const binned = new Float64Array(count)
  for (let i = 0; i < count; i++) {
    let sum = 0
    for (let k = 0; k < bin; k++) sum += speed[from + i * bin + k]!
    binned[i] = sum / bin
  }
  const f = highPass(WOBBLE_FROM_HZ, binRate)
  const forward = filter(binned, f)
  forward.reverse()
  const both = filter(forward, f)
  both.reverse()
  const edge = Math.round(0.1 * binRate)
  let energy = 0, mean = 0, used = 0
  for (let i = edge; i < count - edge; i++) {
    energy += both[i]! * both[i]!
    mean += Math.abs(binned[i]!)
    used++
  }
  if (!used || mean / used < 0.05) return null
  return (100 * Math.sqrt(energy / used)) / (mean / used)
}

export interface Stray {
  /** the energy away from the reference's frequencies against the energy at them, dB */
  db: number
  /** the loudest single stray component: its frequency, and its level against its frame's signal, dB */
  loudest: { hz: number; db: number } | null
  frames: number
}

/** What "isn't the signal" leaves out: below this, and above this or the Nyquist frequency. */
export const STRAY_BAND: readonly [number, number] = [20, 20000]
/** A frame's reference content: every bin within this of the frame's loudest (dB), and this far round
 *  it (Hz) - wide enough that the same tone a hair late isn't stray, narrow enough that sidebands a
 *  wobble of 20 Hz or more makes are. */
export const STRAY_FLOOR_DB = -85
export const STRAY_GUARD_HZ = 8
/** The Blackman-Harris window's main lobe, bins either side of a component's own. */
const LOBE = 4

/**
 * The sound in `a` that isn't the signal: frame by frame (a third of a second, half overlapping, under a
 * Blackman-Harris window whose sidelobes are 92 dB down), the energy of `a` away from where `reference`
 * has anything (STRAY_FLOOR_DB of its loudest, and STRAY_GUARD_HZ round that) against the energy of `a`
 * where it has - so the same tone a little early or late, or a slow drift of timing, counts for nothing,
 * while what the reading adds - images, aliases, a wobble's sidebands, clicks - does. Over the audible band.
 */
export function stray(a: Float32Array, reference: Float32Array, rate: number, from = 0, to = Math.min(a.length, reference.length)): Stray {
  const size = nextPower(0.3 * rate)
  const hop = size / 2
  const window = blackmanHarris(size)
  const re = new Float64Array(size), im = new Float64Array(size)
  const pa = new Float64Array(size / 2 + 1), pr = new Float64Array(size / 2 + 1)
  const binHz = rate / size
  const low = Math.ceil(STRAY_BAND[0] / binHz)
  const high = Math.min(size / 2, Math.floor(Math.min(STRAY_BAND[1], rate / 2) / binHz))
  const guard = Math.ceil(STRAY_GUARD_HZ / binHz)
  const mask = new Uint8Array(size / 2 + 1)
  type Frame = { near: number; away: number; loud: number; loudBin: number; total: number }
  const frames: Frame[] = []
  for (let start = from; start + size <= to; start += hop) {
    framePower(reference, start, window, re, im, pr)
    framePower(a, start, window, re, im, pa)
    let peak = 0, total = 0
    for (let k = low; k <= high; k++) {
      if (pr[k]! > peak) peak = pr[k]!
      total += pr[k]!
    }
    mask.fill(0)
    const floor = peak * Math.pow(10, STRAY_FLOOR_DB / 10)
    for (let k = 0; k <= size / 2; k++) {
      if (pr[k]! >= floor && peak > 0) for (let j = Math.max(0, k - guard); j <= Math.min(size / 2, k + guard); j++) mask[j] = 1
    }
    let near = 0, away = 0, peakAway = 0, loudBin = -1
    for (let k = low; k <= high; k++) {
      if (mask[k]) near += pa[k]!
      else {
        away += pa[k]!
        if (pa[k]! > peakAway) { peakAway = pa[k]!; loudBin = k }
      }
    }
    //? the loudest component's energy: its bin and the window's main lobe round it (4 bins either side),
    //? what of that isn't the reference's - one bin alone holds about half of a component's energy
    let loud = 0
    if (loudBin >= 0) for (let k = Math.max(low, loudBin - LOBE); k <= Math.min(high, loudBin + LOBE); k++) if (!mask[k]) loud += pa[k]!
    frames.push({ near, away, loud, loudBin, total })
  }
  const most = frames.reduce((m, f) => Math.max(m, f.total), 0)
  let near = 0, away = 0, used = 0
  let loudest: { hz: number; db: number } | null = null
  for (const frame of frames) {
    //? frames where the reference is quiet - between bursts, before a take - say nothing
    if (!(frame.total > most * 1e-3) || !(frame.near > 0)) continue
    near += frame.near
    away += frame.away
    used++
    if (frame.loudBin >= 0) {
      const db = 10 * Math.log10(frame.loud / frame.near)
      if (!loudest || db > loudest.db) loudest = { hz: frame.loudBin * binHz, db }
    }
  }
  const floorDb = -140
  return { db: near > 0 ? Math.max(floorDb, 10 * Math.log10(away / near || 1e-30)) : floorDb, loudest: loudest && loudest.db > floorDb ? loudest : null, frames: used }
}

/** The chance of `right` or more of `trials` by guessing each (a coin), as an ABX test's score is read. */
export function guessingChance(right: number, trials: number): number {
  if (right <= 0) return 1
  if (right > trials) return 0
  let term = Math.pow(0.5, trials)
  let sum = 0
  for (let i = 0; i <= trials; i++) {
    if (i >= right) sum += term
    term = (term * (trials - i)) / (i + 1)
  }
  return Math.min(1, sum)
}

/* ===== lining up, levels ===== */

/**
 * Where the recorded sound sits on the replay's timeline: the lag (replay index less recorded index) of
 * the strongest cross-correlation within `reach` of `guess`, and how strong (-1 to 1). By FFT.
 */
export function alignment(recorded: Float32Array, replayed: Float32Array, guess: number, reach: number): { lag: number; score: number } {
  const size = nextPower(recorded.length + replayed.length)
  const ar = new Float64Array(size), ai = new Float64Array(size)
  const br = new Float64Array(size), bi = new Float64Array(size)
  ar.set(recorded)
  br.set(replayed)
  fft(ar, ai)
  fft(br, bi)
  for (let k = 0; k < size; k++) {
    const r = ar[k]! * br[k]! + ai[k]! * bi[k]!
    const i = ar[k]! * bi[k]! - ai[k]! * br[k]!
    ar[k] = r
    ai[k] = i
  }
  fft(ar, ai, true)
  let energyA = 0, energyB = 0
  for (const v of recorded) energyA += v * v
  for (const v of replayed) energyB += v * v
  let best = guess, bestValue = -Infinity
  for (let lag = guess - reach; lag <= guess + reach; lag++) {
    if (lag <= -recorded.length || lag >= replayed.length) continue
    const value = ar[((lag % size) + size) % size]! / size
    if (value > bestValue) { bestValue = value; best = lag }
  }
  const norm = Math.sqrt(energyA * energyB)
  return { lag: best, score: norm > 0 ? bestValue / norm : 0 }
}

/** Where A, B and C are level-matched from: this many Hz up (2.0.0-player.38). */
export const MATCH_FROM_HZ = 20

/**
 * The RMS of `data` over the samples `where` says, counting only what can be heard: high-passed at
 * MATCH_FROM_HZ first (4th order). The voice's DC blocker takes out what the ideal turntables keep below
 * 20 Hz - a slowed record's deepest bass, the offset of a record held still - and matched on plain RMS that
 * inaudible energy turned B and C down by up to 1.4 dB in everything that could be heard (2.0.0-player.38).
 */
export function audibleRmsWhere(data: ArrayLike<number>, rate: number, where: (i: number) => boolean): number {
  const f = highPass(MATCH_FROM_HZ, rate)
  return rmsWhere(filter(filter(Float64Array.from(data), f), f), where)
}

/** The RMS of `data` over the samples `where` says. */
export function rmsWhere(data: ArrayLike<number>, where: (i: number) => boolean): number {
  let sum = 0, count = 0
  for (let i = 0; i < data.length; i++) {
    if (!where(i)) continue
    sum += data[i]! * data[i]!
    count++
  }
  return count ? Math.sqrt(sum / count) : 0
}

/* ===== the pictures ===== */

export interface SpectrogramImage {
  width: number
  height: number
  /** RGBA, a row at a time, top row the highest frequency */
  data: Uint8ClampedArray<ArrayBuffer>
}

/** The spectrograms' range: 20 Hz up, and how far down the colours go, dB. */
export const SPECTROGRAM_FROM_HZ = 20
export const SPECTROGRAM_RANGE_DB = 110

const RAMP: readonly [number, number, number, number][] = [
  [0, 0, 0, 4], [0.13, 28, 16, 68], [0.25, 79, 18, 123], [0.38, 129, 37, 129], [0.5, 181, 54, 122],
  [0.63, 229, 80, 100], [0.75, 251, 135, 97], [0.88, 254, 194, 135], [1, 252, 253, 191],
]

/** A colour for 0 (quiet) to 1 (loud), along a perceptual ramp from black through purple to pale yellow. */
export function heat(x: number): [number, number, number] {
  const v = Math.max(0, Math.min(1, x))
  let i = 1
  while (i < RAMP.length - 1 && RAMP[i]![0] < v) i++
  const [p0, r0, g0, b0] = RAMP[i - 1]!
  const [p1, r1, g1, b1] = RAMP[i]!
  const f = (v - p0) / (p1 - p0 || 1)
  return [r0 + (r1 - r0) * f, g0 + (g1 - g0) * f, b0 + (b1 - b0) * f]
}

/**
 * Spectrograms of several clips, all on one scale: time across (at most `width` columns), frequency up on
 * a log axis from 20 Hz to 20 kHz (or the Nyquist frequency), SPECTROGRAM_RANGE_DB of colour below the
 * loudest point of any of them. Blackman-Harris frames, so a stray line 80 dB down shows.
 */
export function spectrograms(clips: Float32Array[], rate: number, width = 720, height = 220): SpectrogramImage[] {
  const size = nextPower(0.085 * rate)
  const window = blackmanHarris(size)
  const re = new Float64Array(size), im = new Float64Array(size)
  const power = new Float64Array(size / 2 + 1)
  const length = Math.max(...clips.map((clip) => clip.length), size)
  const columns = Math.max(1, Math.min(width, Math.floor((length - size) / (size / 8)) + 1))
  const hop = Math.max(1, (length - size) / Math.max(1, columns - 1))
  const top = Math.min(20000, rate / 2)
  const binHz = rate / size
  //? each row's band of bins
  const rows: [number, number][] = []
  for (let r = 0; r < height; r++) {
    const f0 = SPECTROGRAM_FROM_HZ * Math.pow(top / SPECTROGRAM_FROM_HZ, r / height)
    const f1 = SPECTROGRAM_FROM_HZ * Math.pow(top / SPECTROGRAM_FROM_HZ, (r + 1) / height)
    const k0 = Math.max(1, Math.round(f0 / binHz))
    rows.push([k0, Math.max(k0, Math.round(f1 / binHz))])
  }
  const grids = clips.map((clip) => {
    const grid = new Float64Array(columns * height)
    for (let c = 0; c < columns; c++) {
      framePower(clip, Math.round(c * hop), window, re, im, power)
      for (let r = 0; r < height; r++) {
        const [k0, k1] = rows[r]!
        let most = 0
        for (let k = k0; k <= k1; k++) if (power[k]! > most) most = power[k]!
        grid[c * height + r] = most
      }
    }
    return grid
  })
  const loudest = grids.reduce((m, grid) => grid.reduce((n, v) => Math.max(n, v), m), 1e-30)
  return grids.map((grid) => {
    const data = new Uint8ClampedArray(columns * height * 4)
    for (let c = 0; c < columns; c++) {
      for (let r = 0; r < height; r++) {
        const db = 10 * Math.log10(grid[c * height + r]! / loudest + 1e-30)
        const [red, green, blue] = heat(1 + db / SPECTROGRAM_RANGE_DB)
        const at = ((height - 1 - r) * columns + c) * 4
        data[at] = red
        data[at + 1] = green
        data[at + 2] = blue
        data[at + 3] = 255
      }
    }
    return { width: columns, height, data }
  })
}
