/**
 * The record's own sound (2.0.0-player.14): what the turntable plays while a hand turns the record,
 * while a flick coasts, and while a pause winds it down - pure, so ui/test/deck.sim.cjs and
 * ui/test/decksound.sim.cjs run it as it runs in the browser.
 *
 * A SEPARATE sound path. The player's own audio element is never connected to Web Audio - a
 * createMediaElementSource is what breaks locked playback on an iPhone - so normal playback is
 * exactly what it was, bit for bit. This sound is a stretch of the song round the playhead, decoded
 * from a FLAC window deadwax cuts (src/flac_window.py), and read here at a SIGNED, fractional rate: 1
 * is the song, 0 is silence - a record held still makes no sound - and negative runs it backwards.
 * Outside the window it is silent. What runs these functions is an AudioWorklet, on an audio thread of
 * its own, wherever the page can have one - or, where it can't (a page that isn't on HTTPS: the browser
 * gives AudioWorklet to secure pages only), a ScriptProcessorNode on the page's main thread
 * (player/deck.ts, 2.0.0-player.16). One DSP, two hosts: nothing about the sound differs but where it
 * runs - and, on the main thread, a constant 43 ms later (SCRIPT_LAG_BLOCKS, deck.ts's startScript) - 21 ms in
 * blocks of 512, where the hardware renders that few (2.0.0-player.40).
 *
 *  - THE PATH (2.0.0-player.24). What the voice follows is a path through time: where the record is in
 *    the song at each moment of the audio context's clock - the hand's own samples, each with the time
 *    the pointer event gives it (`hand`, as they come, never one a frame); a coast's, a wind-down's, the
 *    motor's and the handover's positions and speeds as the page works them out (`drive`); and where the
 *    sound was taken up (`take`). Every time on it is mapped onto the context's clock by ONE smooth
 *    mapping (lib/deckClock.ts) - never a `currentTime` read per message, whose steps were what made the
 *    sound warble. The voice keeps them as knots in a small ring and plays the path a FIXED delay behind
 *    (HAND_DELAY_S, 120 ms since 2.0.0-player.27: `delay`), so the next knot has always arrived, and the
 *    samples each knot is fitted to - it interpolates between real ones rather than guessing ahead.
 *    Between two knots the path's place is a cubic Hermite through their places and speeds - continuous
 *    in speed. A hand sample's place, speed and change of speed are fitted to its neighbours
 *    (voiceCommand's `place`): ONE weighted parabola over the samples within FIT_S either side of it,
 *    centred on it (2.0.0-player.27) - so a finger's jitter (a millisecond or so of the song, which
 *    straight through would be a few per cent of pitch) averages out, and a hand that speeds up, slows
 *    or turns back is followed, with the same fit for both. (2.0.0-player.24 took the longest straight
 *    line back that still agreed with the samples, else a parabola read at its NEWEST end - and an end
 *    of a curve carries jitter several times over into its slope: the pitch buzzed whenever the hand's
 *    speed changed, which any real hand's does - James's "dragonfly sound on top of the music".) A
 *    coast's knots are exact. The speed it reads at is the path's: its two knots' speeds between them -
 *    between two fitted hand samples (`knotSteady`) that alone, the chord between their places only
 *    jitter; wherever a knot was said (a take, a drive), also what that chord asks beyond them, the
 *    exact cubic. Past the last knot: a drive runs on along its own curve until it runs out
 *    (`until`); a hand runs on EXTRAPOLATE_S, slowing to still, then holds - a hand that stops sends
 *    nothing, and a record held still is silent. A hand that stayed still past REST_S and moves again
 *    starts from where the path stopped - unless it is where its speed would have had it, samples having
 *    gone missing (MISSED_S, KEPT_ON); a plan after a rest sets off from there too. A hand sample older
 *    than the record's own motion the path has after it (a coast's frames) takes the path from its moment.
 *  - The rate it reads at is steered to the path: the path's speed, how far the read head is from the
 *    path's place (FOLLOW_S, 0.1 s - slow enough that what is left of the jitter in the knots' places
 *    isn't made into pitch), and SMOOTH_S times how fast the path's speed is changing (the knots' own
 *    fitted change of speed, a drive's, or the cubic's - so the smoothing follows a hand that speeds up,
 *    slows or stops dead without lagging it: 2.0.0-player.27) - smoothed by a one-pole filter of
 *    SMOOTH_S (10 ms) a sample, so a change of speed never steps; and the read head is a running sum of
 *    it, so nothing ever jumps.
 *  - Its loudness fades in and out (`take`, `fade`, `stop`) rather than switching, and fades at the
 *    window's two edges (EDGE_S).
 *  - A DC blocker (10 Hz) on the way out: a record held still reads one sample over and over, a
 *    constant, which this takes down to silence - and anything a slow turn pitches down below
 *    hearing goes with it.
 *  - Read through a windowed sinc (2.0.0-player.29; four-point Catmull-Rom before - see newVoiceState's
 *    kernel), so the song at speed 1 - the handover after a
 *    coast, the start of a wind-down - sounds as the song does, not dulled.
 *  - A lookahead peak limiter last of all (2.0.0-player.35, VOICE_CEILING): no sample it writes is above
 *    -0.5 dBFS, whatever the window, the speed or the host. Reading a loud master between its samples
 *    recreates its intersample peaks, above full scale, and the DC blocker adds to them; the browser cuts
 *    whatever is over 1.0 at its output - a recording from James's Mac held 144 samples at full scale, in
 *    15 bursts about a second apart (one per loud drum hit), and in its slowed stretches that was the one
 *    sound no part of the song could make. One gain for both channels, coming down smoothly over the
 *    lookahead (VOICE_LOOKAHEAD_S, 1.5 ms) ahead of a peak, held 20 ms and back up over tens of ms - never
 *    a step, and a tone from about 20 Hz up turned down without being shaped (below that the gain follows
 *    each crest: slight harmonics, renderVoice) - and when nothing reaches the ceiling, the output is the
 *    sound exactly, delayed by the lookahead, bit for bit.
 *
 * The four functions the worklet runs - newVoiceState, voiceCommand, renderVoice and voiceReport - are
 * written SELF-CONTAINED (no imports, no module constants, no helpers outside themselves, nor one
 * another), because the worklet's module is made from their own source text (voiceWorkletSource): an
 * AudioWorklet runs in a scope of its own, and the page's bundle can't be imported into it. The
 * main-thread voice calls the very same four.
 */

/** The worklet's name, as registerProcessor() and new AudioWorkletNode() say it. */
export const VOICE_PROCESSOR = 'deadwax-deck-voice'

/** How many times a second the voice says where it is - either host (voiceReport). */
export const REPORTS_PER_SECOND = 30

/**
 * How far behind the record's path the voice plays, in seconds (2.0.0-player.24; 120 ms since
 * 2.0.0-player.27, 50 before): long enough that at 60 pointer samples a second the knot after any moment
 * it plays has always arrived, and with it every sample that knot is fitted to - SMOOTH_AFTER_S (90 ms)
 * of them after it, and their delivery - so it interpolates between real samples, fitted once and for
 * all, never guesses ahead of them; and short enough to be a latency, not an echo. A constant: the
 * record's sound is this much later than the hand, the coast and the wind-down alike (and on the main
 * thread SCRIPT_LAG_BLOCKS more: 163 ms in all in blocks of 1024, 141 in blocks of 512), and nothing else
 * moves. The literal is in newVoiceState (the voice's functions name nothing outside themselves); deck.sim
 * holds the two equal.
 */
export const HAND_DELAY_S = 0.12

/**
 * The limiter's ceiling (2.0.0-player.35): no sample the voice writes is above it, -0.5 dBFS as a 32-bit
 * float (0.94406086...). A sample-peak ceiling half a dB under full scale, so that the output's own
 * intersample peaks - what a reconstruction filter or a resampler downstream makes between its samples -
 * stay under full scale too on mastered music: measured on loud masters read along James's hand (see
 * CLAUDE.md, "The record's sound never clips"). The literal is in renderVoice; limiter.sim holds the two
 * equal.
 */
export const VOICE_CEILING = Math.fround(Math.pow(10, -0.5 / 20))

/**
 * How far ahead the limiter looks, in seconds (2.0.0-player.35): its gain comes down over this much ahead
 * of a peak, so the record's sound is this much later again than HAND_DELAY_S says - 1.5 ms, 121.5 ms
 * from hand to sound in all (about 164 on the main thread in blocks of 1024, 143 in blocks of 512). Kept as
 * latency rather than taken out of the path's delay, which is the hand's fit's look-ahead and its margin;
 * renderVoice's literal, which limiter.sim holds equal to this.
 */
export const VOICE_LOOKAHEAD_S = 0.0015

/** A stretch of the song, decoded: its channels at `rate` samples a second, from `start` (song s). */
export interface VoiceWindow {
  channels: Float32Array[]
  start: number
  rate: number
  length: number
}

export interface VoiceState {
  /** where the read head is, in seconds of the song - what is heard */
  pos: number
  /** how fast it reads, smoothed: 1 the song's own pace, negative backwards */
  rate: number
  /** how loud, smoothed, 0 to 1 - and where it is heading, how fast (per sample) */
  gain: number
  gainTarget: number
  gainAlpha: number
  /** whether it follows its path at all: a take starts it, a stop ends it */
  driving: boolean
  /** how far behind the path it plays, in seconds (HAND_DELAY_S) */
  delay: number
  /**
   * The path: its knots in a ring (as many as these arrays are long), the oldest at `first` and the
   * next free at `end` (both counted from the first ever, a slot being the count modulo the length),
   * and `cursor` the knot the path is on as the voice last played it. Each knot: its time (context s),
   * where the record is (song s) as said (`knotAt`) and as followed (`knotPos` - a hand sample's fitted
   * to its neighbours, a drive's as said), how fast (`knotRate`), how that is changing
   * (`knotAccel` - a drive's or a take's as said, a hand sample's from its fit) and until when it holds
   * (`knotUntil`); its kind (`knotHand`): 1 a hand's sample, 0 anything said (a take, a drive, where a
   * resting hand's path stopped or a plan after a rest set off), 2 where a resting hand set off again;
   * and whether it is a hand's sample fitted to its neighbours (`knotSteady`: 1 - its speed is the fit's,
   * and the chord to the next fitted one is only jitter - 0 for anything said, and for a run's first
   * sample until a second comes).
   */
  knotTime: Float64Array
  knotAt: Float64Array
  knotPos: Float64Array
  knotRate: Float64Array
  knotAccel: Float64Array
  knotUntil: Float64Array
  knotHand: Uint8Array
  knotSteady: Float64Array
  first: number
  end: number
  cursor: number
  window: VoiceWindow | null
  /**
   * What the window is read through (2.0.0-player.29): a sinc under a Kaiser window, `kernelZeros` zero
   * crossings either side, `kernelSteps` entries a crossing (one more at the end, and a zero after it,
   * for reading between entries) - and room for one sample's weights (`taps`).
   */
  kernel: Float32Array
  kernelZeros: number
  kernelSteps: number
  taps: Float32Array
  /** the DC blocker's last input and output, per channel */
  lastIn: number[]
  lastOut: number[]
  /**
   * THE LIMITER (2.0.0-player.35, renderVoice). Its rings are `limitRing` long - room for the
   * lookahead at the highest rate either host can have (192 kHz) and then some - indexed by the sample
   * count `limitN` masked (a power of two). `limitDelay`: the voice's samples, channel after channel,
   * waiting the lookahead before they are written out; `limitNeed`: the gain each sample needs to be under
   * the ceiling (1 for most); `limitMinAt`/`limitMinOf` a running minimum of that over the lookahead and
   * the hold - a double-ended queue in a ring of its own (`limitMinRing`, room for both at 192 kHz), oldest
   * at `limitMinHead`, next free at `limitMinTail`, its values rising, so it costs nothing to keep however
   * long the window; `limitEnv` that minimum, coming back up over the release; and two boxes (`limitBoxA`, `limitBoxB`, their sums and how many of their values are
   * under 1) averaging that over the lookahead - the gain written. `limitLength` the lookahead in samples
   * it is set up for (0: not yet), `limitChannels` for how many channels (its delay grows for more). And
   * what it has done since the voice last said where it is: how many samples it brought down
   * (`limitHeld`), in how many runs (`limitPeaks`, `limitWasOver` the last sample's), and the lowest gain
   * it wrote (`limitLowest`).
   */
  limitRing: number
  limitDelay: Float64Array
  limitNeed: Float64Array
  limitMinRing: number
  limitMinAt: Float64Array
  limitMinOf: Float64Array
  limitMinHead: number
  limitMinTail: number
  limitEnv: number
  limitBoxA: Float64Array
  limitBoxB: Float64Array
  limitSumA: number
  limitSumB: number
  limitLowA: number
  limitLowB: number
  limitN: number
  limitLength: number
  limitChannels: number
  limitHeld: number
  limitPeaks: number
  limitWasOver: boolean
  limitLowest: number
  /** samples played since it last said where it is (voiceReport) */
  counted: number
}

export type VoiceMessage =
  /** a new stretch of the song; the read head stays where it is in the song */
  | { type: 'window'; channels: Float32Array[]; start: number; rate: number }
  /** start sounding where the record is - at `at` as of context time `time`, moving at `rate` (1 for
   *  a song that was playing) - already at that rate, faded in; the path starts again from it */
  | { type: 'take'; at: number; rate: number; time: number; until: number }
  /** the record is at `at`, moving at `rate` and changing it by `accel` a second (a coast's friction,
   *  the motor's pull), as of context time `time` - holding that until `until` if nothing comes after */
  | { type: 'drive'; at: number; rate: number; accel?: number; time: number; until: number }
  /** the hand had the record at `at` as of context time `time` - one pointer sample, as it came */
  | { type: 'hand'; at: number; time: number }
  /** fade out over `seconds`, then rest */
  | { type: 'fade'; seconds: number }
  /** silence now (a few ms), and rest */
  | { type: 'stop' }

/** What the voice says ~30 times a second. */
export interface VoiceHeard {
  type: 'heard'
  pos: number
  rate: number
  gain: number
  time: number
  /** since it last said (2.0.0-player.35): samples its limiter brought down under the ceiling, in how
   *  many runs, and the lowest gain it wrote (1: none) */
  held: number
  peaks: number
  lowest: number
}

/** A voice at rest: silent, nowhere in particular, nothing to play, no path. */
export function newVoiceState(): VoiceState {
  //? the path's knots: 64 is more than half a second of a hand sampled at 120 Hz - more than the fit (0.12
  //? s back, 0.09 on) and the delay ever look over; at 240 Hz a fit takes what the ring still holds
  const KNOTS = 64
  //? THE KERNEL the window is read through (renderVoice): a sinc, 12 zero crossings either side, under a
  //? Kaiser window (beta 7: what leaks past it is about 70 dB down), 128 entries a crossing and read
  //? between them. A record turned slower or faster than the song is the song RESAMPLED, sample by
  //? sample, and a short curve through four samples (2.0.0-player.14 to .28) is a poor filter for that:
  //? slowed, it left mirror images of the song's top above where the slowed song ends - 35-48 dB under
  //? the song, in a band with nothing else in it - and sped up it folded the top back down over the rest.
  //? James: "a digital artifact on top". WIDEST is how far the kernel is stretched for a record turning
  //? faster than the song (its cutoff lowered to keep the fold out): 4x, past which everything is a
  //? squeal anyway - and what `taps` has room for.
  const ZEROS = 12, STEPS = 128, WIDEST = 4, BETA = 7
  const bessel = (x: number) => {
    let sum = 1, term = 1
    for (let k = 1; k < 32; k++) {
      term *= (x / (2 * k)) * (x / (2 * k))
      sum += term
    }
    return sum
  }
  const kernel = new Float32Array(ZEROS * STEPS + 2)
  for (let i = 0; i <= ZEROS * STEPS; i++) {
    const x = i / STEPS
    const sinc = i === 0 ? 1 : Math.sin(Math.PI * x) / (Math.PI * x)
    const edge = x / ZEROS
    kernel[i] = sinc * (bessel(BETA * Math.sqrt(Math.max(0, 1 - edge * edge))) / bessel(BETA))
  }
  //? THE LIMITER's rings (renderVoice): room for its lookahead at 192 kHz, the highest rate either host
  //? can have (1.5 ms is 288 samples there), with plenty to spare - and a delay for two channels, which
  //? both hosts give it (a host asking for more grows it once, renderVoice)
  const RING = 1024, CHANNELS = 2
  //? and its running minimum's, longer: it covers the hold too (renderVoice's HOLD_S), at 192 kHz
  const MIN_RING = 8192
  const limitBoxA = new Float64Array(RING).fill(1), limitBoxB = new Float64Array(RING).fill(1)
  return {
    pos: 0, rate: 0, gain: 0, gainTarget: 0, gainAlpha: 0.01, driving: false, delay: 0.12,
    knotTime: new Float64Array(KNOTS), knotAt: new Float64Array(KNOTS), knotPos: new Float64Array(KNOTS),
    knotRate: new Float64Array(KNOTS), knotAccel: new Float64Array(KNOTS), knotUntil: new Float64Array(KNOTS),
    knotHand: new Uint8Array(KNOTS), knotSteady: new Float64Array(KNOTS), first: 0, end: 0, cursor: 0,
    window: null, kernel, kernelZeros: ZEROS, kernelSteps: STEPS, taps: new Float32Array(2 * ZEROS * WIDEST + 2),
    lastIn: [0, 0], lastOut: [0, 0],
    limitRing: RING, limitDelay: new Float64Array(RING * CHANNELS), limitNeed: new Float64Array(RING).fill(1),
    limitMinRing: MIN_RING, limitMinAt: new Float64Array(MIN_RING), limitMinOf: new Float64Array(MIN_RING), limitMinHead: 0, limitMinTail: 0,
    limitEnv: 1, limitBoxA, limitBoxB, limitSumA: 0, limitSumB: 0, limitLowA: 0, limitLowB: 0,
    limitN: 0, limitLength: 0, limitChannels: CHANNELS, limitHeld: 0, limitPeaks: 0, limitWasOver: false, limitLowest: 1,
    counted: 0,
  }
}

/** A message from the page, applied as of context time `now`. */
export function voiceCommand(state: VoiceState, message: VoiceMessage, now: number, sampleRate: number): void {
  //? a one-pole filter's step for a time constant, per sample
  const alpha = (seconds: number) => 1 - Math.exp(-1 / (Math.max(seconds, 1e-4) * sampleRate))
  //? a fade in or a stop: a few milliseconds, so it never clicks
  const QUICK_S = 0.003
  //? a hand sample is fitted to the samples within FIT_S of it either side - after it, up to
  //? SMOOTH_AFTER_S, which have all come by the time the voice plays it (the delay, less a sample's
  //? spacing and its delivery) - weighted the nearer the more (`place`)
  const SMOOTH_AFTER_S = 0.09
  const FIT_S = 0.12
  //? a hand sample further than this after the one before it: the hand rested between them - unless, no
  //? more than MISSED_S after it, it is where the hand's speed would have it by then, to within KEPT_ON of
  //? how far that is (or KEPT_S): then samples went missing, and the hand kept moving through them
  const REST_S = 0.04
  const MISSED_S = 0.1
  const KEPT_ON = 0.25
  const KEPT_S = 0.003
  //? how far the path runs on past a hand's last sample, slowing to still (renderVoice's own)
  const EXTRAPOLATE_S = 0.02
  //? a hand moving again after a rest started off within this of its first sample: a sample's spacing
  const RESUME_S = 0.017
  const size = state.knotTime.length
  const t = state.knotTime, at = state.knotAt, pos = state.knotPos, rate = state.knotRate
  const accel = state.knotAccel, until = state.knotUntil, hand = state.knotHand, steady = state.knotSteady
  //? a knot added at the end - the oldest let go of when the ring is full
  const add = (time: number, where: number, speed: number, change: number, end: number, isHand: number) => {
    if (state.end - state.first >= size) state.first += 1
    const k = state.end % size
    t[k] = time
    at[k] = where
    pos[k] = where
    rate[k] = speed
    accel[k] = change
    until[k] = end
    hand[k] = isHand
    steady[k] = 0
    state.end += 1
    if (state.cursor < state.first) state.cursor = state.first
  }
  //? a hand sample's place and speed, from it and its neighbours (`place`) - and where a resting hand set
  //? off from, when it is the first sample after the rest (`settle`)
  const fit = (i: number) => {
    place(i)
    settle(i)
  }
  //? where a resting hand set off from (a knot of kind 2, just before the first sample after the rest):
  //? still until as late as that sample's place and speed allow without the path ever stepping back to
  //? reach it - a sample's spacing before it at most (RESUME_S), at once if it hasn't moved on yet
  const settle = (i: number) => {
    const j = i - 1
    if (j - 1 < state.first || hand[j % size] !== 2) return
    const k = i % size
    const ahead = pos[k]! - pos[j % size]!
    const lead = rate[k]! * ahead > 0 ? Math.min(RESUME_S, (3 * ahead) / rate[k]!) : 0
    t[j % size] = Math.max(t[(j - 1) % size]!, t[k]! - lead)
  }
  //? A hand sample's place, speed and change of speed, from it and its neighbours - the hand's own
  //? samples only: back no further than the knot its run began from (a take, a coast's last frame - the
  //? record's motion before the hand). Re-fitted as each later sample within SMOOTH_AFTER_S comes, so it
  //? is final by the time the voice plays it. Marked fitted (`knotSteady` 1) - but a run's first sample,
  //? alone, which is still until more come
  const place = (i: number) => {
    const k = i % size
    const ti = t[k]!
    let from = i
    for (let j = i - 1; j >= state.first && hand[j % size] === 1 && ti - t[j % size]! <= FIT_S; j--) from = j
    let to = i
    for (let j = i + 1; j < state.end && hand[j % size] === 1 && t[j % size]! - ti <= SMOOTH_AFTER_S; j++) to = j
    steady[k] = 0
    if (to === from) {
      //? its run's only sample (the hand's first, as it takes the record): still, until more come
      pos[k] = at[k]!
      rate[k] = 0
      accel[k] = 0
      return
    }
    //? ONE fit, the same for a steady hand and a changing one (2.0.0-player.27): x = a + b u + c u^2 by
    //? weighted least squares over the samples within FIT_S either side (as many after as have come -
    //? by the time the voice plays this sample, all of them), each weighted by how near it is (tricube),
    //? u the time from this sample in FIT_S. Centred, a curve's slope is as quiet as a line's (on even
    //? ground the u^2 term takes nothing from it) and still follows a hand speeding up, slowing or
    //? turning back; and its curvature is how fast the hand's speed is changing, which renderVoice feeds
    //? ahead of its smoothing. 2.0.0-player.24 fell back from long straight lines to a 0.1 s parabola
    //? read at its NEWEST end whenever the hand's speed changed - and the end of a curve carries a
    //? finger's jitter several times over into its slope: 2% of pitch, buzzing at 12-45 Hz (James:
    //? "warbly, like there's a dragonfly sound on top of the music"; 0.1% now)
    let s0 = 0, s1 = 0, s2 = 0, s3 = 0, s4 = 0, x0 = 0, x1 = 0, x2 = 0
    for (let j = from; j <= to; j++) {
      const u = (t[j % size]! - ti) / FIT_S
      const d = Math.abs(u)
      if (d >= 1) continue
      const w3 = 1 - d * d * d
      const w = w3 * w3 * w3
      const x = at[j % size]! - at[k]!
      const u2 = u * u
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
    const m0 = s2 * s4 - s3 * s3, m1 = s1 * s4 - s2 * s3, m2 = s1 * s3 - s2 * s2
    const det = s0 * m0 - s1 * m1 + s2 * m2
    const lineDet = s0 * s2 - s1 * s1
    accel[k] = 0
    if (to - from + 1 >= 4 && Math.abs(det) > 1e-9 * s0 * s0 * s0) {
      pos[k] = at[k]! + (x0 * m0 - s1 * (x1 * s4 - s3 * x2) + s2 * (x1 * s3 - s2 * x2)) / det
      rate[k] = (s0 * (x1 * s4 - s3 * x2) - x0 * m1 + s2 * (s1 * x2 - x1 * s2)) / det / FIT_S
      accel[k] = (2 * (s0 * (s2 * x2 - s3 * x1) - s1 * (s1 * x2 - s2 * x1) + x0 * m2)) / det / (FIT_S * FIT_S)
    } else if (lineDet > 1e-12) {
      //? two or three samples: the line through them
      pos[k] = at[k]! + (s2 * x0 - s1 * x1) / lineDet
      rate[k] = (s0 * x1 - s1 * x0) / lineDet / FIT_S
    } else {
      pos[k] = at[k]!
      rate[k] = 0
    }
  }
  //? a knot coming after a hand's last sample, further on than REST_S: the hand rested since. The path ran
  //? on from that sample and stopped (renderVoice's run-on, exactly) - a knot there says so, so what comes
  //? next starts from where it stopped, not from a curve swung across the gap; and what set off again did
  //? so from there, still until then - a hand moving again just before its first sample (a knot of kind 2,
  //? its time settled by `settle`), a plan (the release after a rest) at its own moment. That plan starts
  //? where the hand let go, which the run-on went past: the path steps back to it as it sets off, and the
  //? steering takes that up as it goes on (FOLLOW_S) - the record slower for a moment, never back (review
  //? of 2.0.0-player.24: a curve from the run-on's end back to the plan's start, across the rest, ran the
  //? sound backwards at -0.7x on a release 45 ms after the last move). Not a rest at all: a hand sample
  //? where the hand's speed at the last would have it by then - samples went missing (a busy page, no
  //? coalesced events) and the hand kept moving, so the path runs on through the gap (review: two missed
  //? samples at 1x read as a stop - 0.14x, then 2.2x)
  const rested = (time: number, where: number, moving: boolean) => {
    const last = state.end - 1
    if (last < state.first || hand[last % size] !== 1) return
    const k = last % size
    const gap = time - t[k]!
    if (gap <= REST_S) return
    const p = pos[k]!, v = rate[k]!
    if (moving && gap <= MISSED_S && Math.abs(where - p - v * gap) <= Math.max(KEPT_S, KEPT_ON * Math.abs(v * gap))) return
    const stopped = t[k]! + EXTRAPOLATE_S, there = p + (v * EXTRAPOLATE_S) / 2
    add(stopped, there, 0, 0, Infinity, 0)
    if (moving) add(Math.max(stopped, time - RESUME_S), there, 0, 0, Infinity, 2)
    else add(Math.max(stopped, time), there, 0, 0, Infinity, 0)
  }
  if (message.type === 'window') {
    const channels = message.channels.filter((channel) => channel && channel.length)
    state.window = channels.length ? { channels, start: message.start, rate: message.rate, length: channels[0]!.length } : null
  } else if (message.type === 'take') {
    //? where the record is on its path by `now`, the delay behind: it was at `at` as of context time
    //? `time`, moving at `rate` - and a host may apply it later than that (the main-thread voice holds it
    //? to its next block, which plays a block or two on). Started there, it has nothing to catch up;
    //? started at `at`, the steering would race it to where the record had got to - a chirp, half an
    //? octave up (review of 2.0.0-player.16)
    state.pos = message.at + message.rate * (now - state.delay - message.time)
    state.rate = message.rate
    state.gain = 0
    state.gainTarget = 1
    state.gainAlpha = alpha(QUICK_S)
    state.driving = true
    //? the path starts again from here
    state.first = state.end
    state.cursor = state.end
    add(message.time, message.at, message.rate, 0, message.until, 0)
  } else if (message.type === 'drive') {
    //? newer word on a moment the path already has, or an earlier one: what came after it goes
    while (state.end > state.first && t[(state.end - 1) % size]! >= message.time) state.end -= 1
    rested(message.time, message.at, false)
    add(message.time, message.at, message.rate, message.accel ?? 0, message.until, 0)
    state.driving = true
  } else if (message.type === 'hand') {
    //? the hand caught the record before the record's own motion the path has after it - a coast's frames,
    //? posted at their frames' times, while the event that crossed a tap's few pixels was on its way: from
    //? the hand's sample on the path is the hand's, as a drive's is the drive's (review of 2.0.0-player.24:
    //? dropped as out of order, the coast ran on under a still finger and then rushed back)
    while (state.end > state.first && hand[(state.end - 1) % size] !== 1 && t[(state.end - 1) % size]! > message.time) state.end -= 1
    const last = state.end - 1
    if (last >= state.first) {
      const lastTime = t[last % size]!
      //? out of order: an older sample than the hand's newest is no use to the path
      if (message.time < lastTime) return
      if (message.time === lastTime && hand[last % size] === 1) state.end -= 1
      else rested(message.time, message.at, true)
    }
    add(message.time, message.at, 0, 0, Infinity, 1)
    //? this sample and the ones it is now among the after of
    for (let j = state.end - 1; j >= state.first && hand[j % size] === 1 && message.time - t[j % size]! <= SMOOTH_AFTER_S; j--) fit(j)
  } else if (message.type === 'fade') {
    //? an exponential fade: four time constants in `seconds`, about 35 dB down by then
    state.gainTarget = 0
    state.gainAlpha = alpha(message.seconds / 4)
  } else if (message.type === 'stop') {
    state.driving = false
    state.gainTarget = 0
    state.gainAlpha = alpha(QUICK_S)
  }
  if (state.cursor > state.end - 1) state.cursor = Math.max(state.first, state.end - 1)
}

/**
 * `frames` samples of the record's sound into `outputs` (one Float32Array a channel), from context
 * time `now`. Each sample: where the path has the record `delay` before it, how fast, and how fast that
 * is changing; the rate steered towards that and smoothed, the read head moved by it, the window read
 * there through the kernel - a windowed sinc, stretched for a record turning faster than the song -
 * (silence outside it, faded at its edges), the gain smoothed, the DC blocker - and the limiter, which
 * writes each sample out its lookahead later, never above the ceiling.
 */
export function renderVoice(state: VoiceState, outputs: Float32Array[], frames: number, sampleRate: number, now: number): void {
  //? the rate's smoothing, and the steering to the path's place - slow (2.0.0-player.27: 0.04 s before),
  //? so what jitter is left in the knots' places isn't made into pitch; the path's change of speed is fed
  //? ahead of the smoothing instead, so it doesn't lag a hand that speeds up, slows or stops
  const SMOOTH_S = 0.01
  const FOLLOW_S = 0.1
  //? the fastest it reads, either way, in the song's own speeds
  const MAX_RATE = 24
  //? the fade at the window's edges, and the DC blocker's corner
  const EDGE_S = 0.004
  const DC_HZ = 10
  //? below this loudness nothing is read: silence
  const QUIET = 1e-5
  //? how far the path runs on past a hand's last sample, slowing to still, before it holds
  const EXTRAPOLATE_S = 0.02
  const rateAlpha = 1 - Math.exp(-1 / (SMOOTH_S * sampleRate))
  const pole = Math.exp((-2 * Math.PI * DC_HZ) / sampleRate)
  const dt = 1 / sampleRate
  const win = state.window
  const count = outputs.length
  const size = state.knotTime.length
  const kt = state.knotTime, kp = state.knotPos, kr = state.knotRate, ka = state.knotAccel, ku = state.knotUntil, kh = state.knotHand
  const ks = state.knotSteady
  const kernel = state.kernel, taps = state.taps, zeros = state.kernelZeros, steps = state.kernelSteps
  //? THE LIMITER (2.0.0-player.35). Reading a loud master between its samples recreates its intersample
  //? peaks - above full scale - and the DC blocker adds to them, and the browser cuts anything over 1.0 at
  //? its output: James's recording held 144 samples at full scale over 16 s, in 15 bursts (one per loud
  //? drum hit; 84 runs, counted channel by channel), at every speed (1x included) - and in its slowed
  //? stretches, the only ones where a sound the song can't make can be told apart, that was the one there.
  //? So each sample waits LOOKAHEAD_S before it is written, and is written times a gain that came down
  //? smoothly, ahead of it, to whatever keeps it under CEILING - one gain for every channel, so the stereo
  //? image holds - held there for HOLD_S and brought back up over RELEASE_S. Never a step: a sample that
  //? never reaches the ceiling, with none near it, is written exactly as it was, only later. By construction:
  //?  - each sample's NEED: the gain that keeps its loudest channel under the ceiling (1 for most) - just
  //?    under it (SAFE), so no rounding can carry it over;
  //?  - the lowest need over the lookahead and the hold - the window [n - D - H, n], D and H the two in
  //?    samples: a running minimum (a queue whose values rise, so each sample is pushed and popped once at
  //?    most, however long the window). The hold keeps the gain still through a low note's cycle: shorter,
  //?    and a steady 25-50 Hz tone over the ceiling was shaped every cycle (harmonics -49 dB; none now).
  //?    Below about 20 Hz - a slowed record's deepest bass - half a cycle outlasts the lookahead and the
  //?    hold together, so the gain follows each crest and shapes the tone a little: harmonics -46 dB at
  //?    10 Hz and -60 at 17, 0.45 dB over the ceiling (limiter.sim pins them);
  //?  - that brought back up towards 1 over RELEASE_S - never above the minimum it follows;
  //?  - averaged by two boxes whose lengths add up to D + 2, so the gain written with sample n - D is a
  //?    smooth (triangular) average of values each made with that sample's need in their minimum: never
  //?    above that need. And never above it by rounding either: the gain written is also held to it - and
  //?    never below 0 (a running sum's rounding could take it there only for a sample some 1e16 times full
  //?    scale), so what is written is at most the sample's loudest channel times its need: the ceiling.
  //? Its ceiling is a 32-bit float, so a value under it in 64 bits stays under it written into the output.
  //? Counted in samples, so it holds at any rate; past 192 kHz (what newVoiceState's rings are sized for)
  //? the lookahead and hold are only shorter in time.
  //? CEILING, LOOKAHEAD_S, HOLD_S and RELEASE_S chosen by measurement on loud masters along James's own
  //? hand (CLAUDE.md, "The record's sound never clips"); the module's exported ceiling and lookahead say
  //? the first two outside (limiter.sim holds them equal - this function names nothing outside itself).
  const CEILING = Math.fround(Math.pow(10, -0.5 / 20))
  const LOOKAHEAD_S = 0.0015
  const HOLD_S = 0.02
  const RELEASE_S = 0.06
  //? a need is made this much under the ceiling, so the products and quotients' rounding never carry a
  //? sample over it (2^-30: 0.00000001 dB)
  const SAFE = 1 - Math.pow(2, -30)
  //? a gain this near 1 coming back up is 1: a step smaller than a 32-bit float can tell from 1
  const SNAP = Math.pow(2, -24)
  //? its rings' length is a power of two (newVoiceState's): a slot is the sample count masked
  const ring = state.limitRing, mask = ring - 1
  const lookahead = Math.min(ring - 2, Math.max(1, Math.round(LOOKAHEAD_S * sampleRate)))
  const minMask = state.limitMinRing - 1
  const span = Math.min(state.limitMinRing - 2, lookahead + Math.round(HOLD_S * sampleRate))
  if (state.limitLength !== lookahead || state.limitChannels !== count) {
    //? set up for this rate and these channels (once: a host's rate and channels never change) - at rest:
    //? nothing waiting, every gain 1
    state.limitLength = lookahead
    state.limitChannels = count
    if (state.limitDelay.length < ring * count) state.limitDelay = new Float64Array(ring * count)
    else state.limitDelay.fill(0)
    state.limitNeed.fill(1)
    state.limitBoxA.fill(1)
    state.limitBoxB.fill(1)
    state.limitMinHead = state.limitMinTail = 0
    state.limitEnv = 1
    state.limitLowA = state.limitLowB = 0
    state.limitN = 0
    state.limitWasOver = false
  }
  const lengthA = Math.ceil((lookahead + 2) / 2), lengthB = lookahead + 2 - lengthA
  const releaseAlpha = 1 - Math.exp(-1 / (RELEASE_S * sampleRate))
  const delayLine = state.limitDelay, needs = state.limitNeed, minAt = state.limitMinAt, minOf = state.limitMinOf
  const boxA = state.limitBoxA, boxB = state.limitBoxB
  //? its running values, kept here for the block and put back after it
  let limitN = state.limitN, head = state.limitMinHead, tail = state.limitMinTail, env = state.limitEnv
  let lowA = state.limitLowA, lowB = state.limitLowB
  let sumA = lowA === 0 ? lengthA : state.limitSumA, sumB = lowB === 0 ? lengthB : state.limitSumB
  let heldCount = state.limitHeld, peakCount = state.limitPeaks, wasOver = state.limitWasOver, lowestGain = state.limitLowest
  for (let i = 0; i < frames; i++) {
    const t = now + i * dt
    let desired = 0
    if (state.driving && state.end > state.first) {
      //? the moment of the path it plays, and the knot that is on - by a moving index, never a search
      const tau = t - state.delay
      let c = state.cursor
      while (c > state.first && kt[c % size]! > tau) c--
      while (c + 1 < state.end && kt[(c + 1) % size]! <= tau) c++
      state.cursor = c
      const a = c % size
      const ta = kt[a]!
      //? where the path has the record, how fast, and how fast that is changing
      let x = 0, v = 0, g = 0, follow = true
      if (tau < ta) {
        //? before its first knot: where the take's motion had it
        x = kp[a]! + kr[a]! * (tau - ta)
        v = kr[a]!
      } else if (c + 1 < state.end) {
        //? between two knots: the cubic through their places and speeds - its place. Its speed: between two
        //? fitted hand samples, their two speeds between them, and its change of speed theirs - what the
        //? chord between their places asks beyond that is a finger's jitter (a fraction of a ms of place a
        //? sample's spacing apart - a few per cent of pitch), and the steering keeps the place (review of
        //? 2.0.0-player.24); anywhere a knot was said (a take, a drive, a rest), the cubic's own slope and
        //? its change, exactly
        const b = (c + 1) % size
        const h = kt[b]! - ta
        const s = (tau - ta) / h
        const s2 = s * s, s3 = s2 * s
        x = (2 * s3 - 3 * s2 + 1) * kp[a]! + (s3 - 2 * s2 + s) * h * kr[a]! + (3 * s2 - 2 * s3) * kp[b]! + (s3 - s2) * h * kr[b]!
        if (ks[a] === 1 && ks[b] === 1) {
          v = (1 - s) * kr[a]! + s * kr[b]!
          g = (1 - s) * ka[a]! + s * ka[b]!
        } else {
          const chord = (kp[b]! - kp[a]!) / h - (kr[a]! + kr[b]!) / 2
          v = (1 - s) * kr[a]! + s * kr[b]! + 6 * (s - s2) * chord
          g = (kr[b]! - kr[a]! + 6 * (1 - 2 * s) * chord) / h
        }
      } else if (kh[a] === 1) {
        //? past a hand's last sample: on along its speed, slowing to still over EXTRAPOLATE_S, then held
        const since = Math.min(tau - ta, EXTRAPOLATE_S)
        x = kp[a]! + kr[a]! * (since - (since * since) / (2 * EXTRAPOLATE_S))
        v = kr[a]! * (1 - since / EXTRAPOLATE_S)
        g = since < EXTRAPOLATE_S ? -kr[a]! / EXTRAPOLATE_S : 0
      } else if (tau <= ku[a]!) {
        //? past a drive: along its own curve, until it runs out
        const since = tau - ta
        x = kp[a]! + kr[a]! * since + 0.5 * ka[a]! * since * since
        v = kr[a]! + ka[a]! * since
        g = ka[a]!
      } else {
        //? run out (a page stalled, a tab hidden): nothing to follow - it slows to still where it is
        follow = false
      }
      if (follow) {
        //? the path's speed, SMOOTH_S ahead (what the one-pole smoothing would lag by), and the steering
        desired = v + SMOOTH_S * g + (x - state.pos) / FOLLOW_S
        if (desired > MAX_RATE) desired = MAX_RATE
        else if (desired < -MAX_RATE) desired = -MAX_RATE
      }
    }
    state.rate += (desired - state.rate) * rateAlpha
    state.pos += state.rate * dt
    state.gain += (state.gainTarget - state.gain) * state.gainAlpha
    let shape = 0
    let index = 0
    if (win && state.gain > QUIET) {
      index = (state.pos - win.start) * win.rate
      const last = win.length - 1
      const edge = Math.min(index, last - index) / (EDGE_S * win.rate)
      shape = edge <= 0 ? 0 : edge >= 1 ? 1 : edge
    }
    //? this sample's weights: the kernel centred on where the read head is, over the window's samples
    //? either side - as it is for a record at the song's speed or slower (the window's own samples
    //? joined up, nothing above the song's top let through but the top 10-15% of the band's images - the
    //? cutoff is at the window's Nyquist frequency: at a 44.1 kHz window 20 kHz images at -20 dB, 18 kHz at
    //? -68, review of 2.0.0-player.35), stretched for one turning faster (how many
    //? of the window's samples go by in one of ours: the cutoff comes down by as much, so what would
    //? fold back is left out), no further than the taps have room for. Normalised by their sum, so a
    //? steady level reads as itself whatever the stretch
    let first = 0, used = 0, norm = 0
    if (shape > 0 && win) {
      const stride = (Math.abs(state.rate) * win.rate) / sampleRate
      const widest = (taps.length - 2) / (2 * zeros)
      const squeeze = stride > 1 ? Math.max(1 / stride, 1 / widest) : 1
      const reach = zeros / squeeze
      const scale = squeeze * steps
      first = Math.ceil(index - reach)
      used = Math.floor(index + reach) - first + 1
      let total = 0
      for (let j = 0; j < used; j++) {
        const u = Math.abs(index - (first + j)) * scale
        const whole = Math.floor(u)
        const weight = kernel[whole]! + (kernel[whole + 1]! - kernel[whole]!) * (u - whole)
        taps[j] = weight
        total += weight
      }
      norm = total !== 0 ? (shape * state.gain) / total : 0
    }
    const n = limitN
    const slot = n & mask
    let loudest = 0
    for (let c = 0; c < count; c++) {
      let value = 0
      if (used > 0 && win) {
        const data = win.channels[c % win.channels.length]!
        const last = win.length - 1
        //? past either end of the window there is nothing: silence, which the fade at its edges meets
        const from = first < 0 ? -first : 0
        const to = first + used - 1 > last ? last - first + 1 : used
        let sum = 0
        for (let j = from; j < to; j++) sum += data[first + j]! * taps[j]!
        value = sum * norm
      }
      //? the DC blocker: y = x - x[-1] + pole y[-1]
      const out = value - (state.lastIn[c] ?? 0) + pole * (state.lastOut[c] ?? 0)
      state.lastIn[c] = value
      state.lastOut[c] = out
      //? into the limiter's delay - anything that isn't a number (nothing the voice makes) as silence
      const held = out > -Infinity && out < Infinity ? out : 0
      delayLine[c * ring + slot] = held
      const size = held < 0 ? -held : held
      if (size > loudest) loudest = size
    }
    //? this sample's need: the gain that keeps its loudest channel under the ceiling
    const need = loudest > CEILING ? (CEILING / loudest) * SAFE : 1
    needs[slot] = need
    const outSlot = (slot - lookahead) & mask
    let gain = 1
    if (need === 1 && env === 1 && lowA === 0 && lowB === 0 && minOf[head & minMask] === 1) {
      //? at rest - nothing under the ceiling's need within the lookahead, nothing coming back up: every
      //? value it keeps is 1, so its running minimum is this sample alone, its boxes take a 1 each, and
      //? the gain is 1 - which is all the long way below would come to
      wasOver = false
      minAt[head & minMask] = n
      tail = head + 1
      boxA[slot] = 1
      boxB[slot] = 1
    } else {
      if (need < 1) {
        heldCount += 1
        if (!wasOver) peakCount += 1
        wasOver = true
      } else wasOver = false
      //? the lowest need over the lookahead: drop what this one undercuts from the back, what has left
      //? the window from the front
      while (tail > head && minOf[(tail - 1) & minMask]! >= need) tail -= 1
      minAt[tail & minMask] = n
      minOf[tail & minMask] = need
      tail += 1
      while (minAt[head & minMask]! < n - span) head += 1
      const lowest = minOf[head & minMask]!
      //? held, and back up over the release - never above the minimum it follows
      if (lowest < env) env = lowest
      else {
        env += (lowest - env) * releaseAlpha
        if (lowest === 1 && 1 - env <= SNAP) env = 1
      }
      //? the two boxes, each a running sum (made again from its values once a ring, so rounding never
      //? builds up) - and exactly 1 whenever every value in it is
      const leaveA = boxA[(slot - lengthA) & mask]!
      boxA[slot] = env
      sumA += env - leaveA
      lowA += (env < 1 ? 1 : 0) - (leaveA < 1 ? 1 : 0)
      if (lowA === 0) sumA = lengthA
      else if (slot === 0) {
        sumA = 0
        for (let k = 0; k < lengthA; k++) sumA += boxA[(ring - k) & mask]!
      }
      const averaged = lowA === 0 ? 1 : sumA / lengthA
      const leaveB = boxB[(slot - lengthB) & mask]!
      boxB[slot] = averaged
      sumB += averaged - leaveB
      lowB += (averaged < 1 ? 1 : 0) - (leaveB < 1 ? 1 : 0)
      if (lowB === 0) sumB = lengthB
      else if (slot === 0) {
        sumB = 0
        for (let k = 0; k < lengthB; k++) sumB += boxB[(ring - k) & mask]!
      }
      //? the gain written with the sample the lookahead ago - held to that sample's own need, which it
      //? is under already but for rounding - and never below 0: the boxes' running sums carry rounding
      //? of about 1e-16 of the values near 1 they held, so a sample so loud its need is smaller than that
      //? (1e16 times full scale: nothing a decoded window holds) could leave a sum, and so the gain, a
      //? hair under 0 - and a huge sample times a tiny negative gain is any size at all (review of
      //? 2.0.0-player.35). With both, the sample written is at most its loudest channel times its need.
      gain = lowB === 0 ? 1 : sumB / lengthB
      const due = needs[outSlot]!
      if (gain > due) gain = due
      if (!(gain >= 0)) gain = 0
      if (gain < lowestGain) lowestGain = gain
    }
    for (let c = 0; c < count; c++) outputs[c]![i] = delayLine[c * ring + outSlot]! * gain
    limitN = n + 1
  }
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

/**
 * After `frames` samples played from context time `now`: what the voice says of where it is, when
 * `perSecond` times a second come round (exactly - the count carries its remainder), or null. Both
 * hosts call it after renderVoice, so the worklet and the main-thread voice say it alike.
 */
export function voiceReport(state: VoiceState, frames: number, sampleRate: number, now: number, perSecond: number): VoiceHeard | null {
  state.counted += frames
  const every = sampleRate / perSecond
  if (state.counted < every) return null
  state.counted -= every
  //? and what its limiter did since it last said (2.0.0-player.35), counted afresh from here
  const heard = { type: 'heard' as const, pos: state.pos, rate: state.rate, gain: state.gain, time: now, held: state.limitHeld, peaks: state.limitPeaks, lowest: state.limitLowest }
  state.limitHeld = 0
  state.limitPeaks = 0
  state.limitLowest = 1
  return heard
}

/**
 * The worklet's module, made from the four functions' own source - so what the browser runs is
 * exactly what the sim runs, the page's build or not. Loaded through a Blob URL (player/deck.ts).
 */
export function voiceWorkletSource(): string {
  return [
    `const newVoiceState = ${newVoiceState.toString()};`,
    `const voiceCommand = ${voiceCommand.toString()};`,
    `const renderVoice = ${renderVoice.toString()};`,
    `const voiceReport = ${voiceReport.toString()};`,
    `class DeckVoice extends AudioWorkletProcessor {`,
    `  constructor() {`,
    `    super();`,
    `    this.state = newVoiceState();`,
    `    this.port.onmessage = (event) => voiceCommand(this.state, event.data, currentTime, sampleRate);`,
    `  }`,
    `  process(inputs, outputs) {`,
    `    const out = outputs[0];`,
    `    if (out && out.length) {`,
    `      renderVoice(this.state, out, out[0].length, sampleRate, currentTime);`,
    `      const heard = voiceReport(this.state, out[0].length, sampleRate, currentTime, ${REPORTS_PER_SECOND});`,
    `      if (heard) this.port.postMessage(heard);`,
    `    }`,
    `    return true;`,
    `  }`,
    `}`,
    `registerProcessor(${JSON.stringify(VOICE_PROCESSOR)}, DeckVoice);`,
  ].join('\n')
}

/* ===== what Info > Debug says of it ===== */

/** Where the turntable's sound is, for Info > Debug's "Turntable sound" row (lib/debugRows.ts). */
export interface DeckReport {
  /**
   * The audio context: 'none' - no tap has started it yet, or it is suspended (the turntable hidden,
   * the screen closed, the page in the background) - 'starting' (running, its voice not yet playing),
   * 'running'; or why there is none: 'unsupported' (no Web Audio), 'no-voice' (neither an AudioWorklet
   * nor a ScriptProcessorNode to play it on), 'failed' (`problem` says why).
   */
  context: 'none' | 'starting' | 'running' | 'unsupported' | 'no-voice' | 'failed'
  /** the browser's own words, for 'failed' */
  problem: string | null
  /**
   * What plays it (2.0.0-player.16): 'worklet' - an AudioWorklet, on an audio thread of its own - or
   * 'script' - a ScriptProcessorNode on the page's main thread, where the page has no AudioWorklet or
   * it wouldn't load; null while there is neither.
   */
  voice: 'worklet' | 'script' | null
  /** why the main thread, for 'script': "this page isn't on HTTPS, so the browser has no AudioWorklet" */
  voiceWhy: string | null
  /** the window decoded and in the voice: the stretch of the song (s), its kind, the rate it was
   *  decoded at, and its size as fetched */
  window: { start: number; end: number; kind: string; decodedAt: number; bytes: number } | null
  /** a window on its way (fetched, or waiting to be decoded) */
  loading: boolean
  /** why this song has no sound: deadwax's words (a 415) or the page's (not a FLAC) */
  refused: string | null
  /** a window that couldn't be fetched or decoded: the reason, the browser's own for a decode */
  failed: string | null
  /** what fetching windows has cost since the turntable showed: bytes - and how many ms after it
   *  showed the last of them landed, which is what that is measured to (the report is made as things
   *  change, not as time passes) */
  fetched: number
  lastFetchAt: number
  /** how far the audio context's clock moves at a time, as the page reads it, in seconds (2.0.0-player.24,
   *  lib/deckClock's `step`): the audio's own render - about 21 ms on an iPhone, 5.8 in desktop Brave -
   *  which the one clock maps smoothly over; 0 or absent until it has been seen to move twice */
  clockStep?: number
  /** how the turntable is keeping up on this device (2.0.0-player.28) - see DeckHealth */
  health?: DeckHealth
  /** what this device's audio adds after the voice (2.0.0-player.40) - see DeckLatency; null with no context */
  latency?: DeckLatency | null
}

/**
 * What the device's audio adds after the voice, as its audio context says it (2.0.0-player.40, deck.ts
 * deckLatency) - Info > Debug's "Turntable timing", so a phone says it, Bluetooth included where the browser
 * knows it. Seconds, or null where the browser doesn't say.
 */
export interface DeckLatency {
  /** the context's baseLatency: in Chromium the hardware's own render; in WebKit only its 128-frame render
   *  quantum, whatever buffer the hardware runs */
  base: number | null
  /** its outputLatency: from the hardware's buffer to the speaker (an older Safari may not say) */
  output: number | null
  /** read from getOutputTimestamp(): how far the render clock is ahead of what is at the speaker - base and
   *  output together, read another way (not a third delay to add to them) */
  speaker: number | null
  /** the frames the voice renders at a time: the main-thread voice's block (512 or 1024), the worklet's 128 */
  block: number | null
  /** the record's sound behind the hand by design, before any of the above: HAND_DELAY_S, the main-thread
   *  voice's lag (2 blocks) and the limiter's lookahead - null with no voice */
  design: number | null
}

/**
 * How the turntable is keeping up on this device, counted since it last showed - what Info > Debug's
 * "Turntable timing" says, so a phone can report what a lab can't see (James: "the turntable player just
 * feels like it hangs a lot, especially when scrubbing").
 */
export interface DeckHealth {
  /** the main-thread voice's blocks: how many it has been asked for, how many were asked for after they
   *  were due to play (the page was busy: a gap in the sound), and the worst of those, ms late */
  blocks: number
  lateBlocks: number
  worstBlockMs: number
  /** frames drawn while a hand held the record: how many, how many came more than two frames after the
   *  one before (34 ms), and the longest gap, ms */
  frames: number
  slowFrames: number
  worstFrameMs: number
  /** the last let-go of a playing record: ms from the release to the song's own playback moving again,
   *  and how much of that the record's run back to speed was; null until one has been measured */
  backMs: number | null
  motorMs: number | null
  /** let-goes after which the song hadn't started within the handover's wait (a play the browser
   *  refused, or a song that took that long to load) */
  notBack: number
  /** times the browser interrupted the sound's audio context (a call, another app's audio) */
  interruptions: number
  /** what the voice's limiter held under the ceiling (2.0.0-player.35): how many peaks (runs of samples
   *  that would have gone over the ceiling - some of them over full scale too), how many samples, and the
   *  deepest it turned the sound down, dB (0: never) */
  peaksHeld: number
  samplesHeld: number
  deepestHoldDb: number
}
