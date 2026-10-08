/**
 * A recording set beside two ideal turntables (2.0.0-player.36) - the test bench's "Record, and compare":
 * A what the voice played, B the signal read exactly along deadwax's own read head, C the signal read
 * exactly along a smooth path through the hand's samples (or a motion's exact path) - level-matched,
 * lined up sample for sample, and measured. Pure: lab.sim.cjs runs it on a recording made by the real
 * deck in the sim. See lab/analysis.ts for each part.
 *
 * A song from the library (2.0.0-player.37) isn't defined anywhere the bench can read at will: B and C read
 * its samples along the path, from deadwax's windows covering where it went - asked for once the replay has
 * said where that is (`exactOver`, with pathExtent's answer). Where they can't be had - a path over more of
 * the song than the bench reads at once, or a window deadwax didn't send - A and the numbers that need only
 * the paths stand, and B and C are left out, saying why (`unread`).
 */

import {
  alignment, audibleRmsWhere, lowerBound, pathFrom, planTiming, readExactly, replay, rmsWhere, speedWobble, spectrograms, stray,
  type ExactMotion, type RecordedMessage, type SpectrogramImage, type Stray, type VoiceWindowIn,
} from './analysis'
import type { VoiceHeard } from '../lib/deckVoice'

/** What a recording gives the comparison: the deck's in-page recording (deck.ts DeckRecordingData). */
export interface RecordingIn {
  voice: 'worklet' | 'script'
  sampleRate: number
  channels: Float32Array[]
  tapBlock: number
  blockTimes: number[]
  messages: Record<string, unknown>[]
  heard: VoiceHeard[]
  clock: { offset: number | null }
  delaySeconds: number
  scriptLagSeconds: number
}

/** A song read exactly at song time t, nothing at or above `cutoff` Hz of its own in it (Signal.exact). */
export type Exact = (t: number, cutoff: number) => number

/** Where the paths B and C read along went: their lowest and highest places in the song (seconds), and the
 *  fastest either moved (the song's own speed is 1). */
export interface PathExtent {
  lowest: number
  highest: number
  fastest: number
}

export interface CompareInput {
  recording: RecordingIn
  /** the signal, exactly (lab/signals.ts's Signal.exact) - or none, for a library song read by `exactOver` */
  exact?: Exact | null
  /** a library song: its reader over where the paths went, made once the replay has said where that is -
   *  rejecting, with why, when it can't be had (B and C are left out then) */
  exactOver?: ((extent: PathExtent) => Promise<Exact>) | null
  /** what can be measured on it: the sound that isn't the signal, for a tone or tones; how loud anything
   *  is at all, for silence; neither, for something broadband */
  measure: 'tonal' | 'silence' | 'none'
  windowAtStart: VoiceWindowIn | null
  windowFor: (start: number, rate: number, length: number) => Float32Array[] | null
  /** a motion's exact path, for C - or null: the hand's own samples, smoothed */
  motion: ExactMotion | null
  /** the stretch to measure, in the messages' own (stamped) context seconds - or null: from the first
   *  take to the hand's last sample */
  span?: { from: number; to: number } | null
  /** draw the spectrograms */
  pictures?: boolean
  pause?: () => Promise<void>
}

export interface Numbers {
  /** how far deadwax's read head strayed from the smooth path, ms of the song: the most, and the median */
  strayed: { maxMs: number; typicalMs: number } | null
  /** the speed's wobble above 20 Hz as a share of the speed, per cent - deadwax's path, the smooth path's */
  wobble: { deadwax: number | null; smooth: number | null }
  /** for a tone: the sound in A that isn't the signal (A against B) */
  stray: Stray | null
  /** silence: how loud A is at all, dBFS RMS */
  silenceDb: number | null
  /** how closely the replay reproduces what was recorded, dB under it (lower is closer), and how well
   *  the two lined up (correlation) */
  replayDb: number | null
  alignScore: number
  /** the lead the replay found, ms, and its worst miss against the voice's own reports, ms of the song */
  leadMs: number
  fitMs: number | null
  /** whether anything took the record while it recorded - a take among its messages */
  taken: boolean
}

export interface Comparison {
  rate: number
  /** B and C null where the song couldn't be read along the path - `unread` says why */
  clips: { A: Float32Array; B: Float32Array | null; C: Float32Array | null }
  unread: string | null
  /** the stretch the numbers measure, in the clips' samples: from SETTLE_S after the take to the hand's
   *  last sample - or null */
  measured: { from: number; to: number } | null
  images: { A: SpectrogramImage; B: SpectrogramImage | null; C: SpectrogramImage | null } | null
  numbers: Numbers
}

const db = (ratio: number) => 20 * Math.log10(Math.max(ratio, 1e-12))

/** The measures start this long after the take, seconds: a start from rest is a transient of its own. */
export const SETTLE_S = 0.3

/**
 * The replay holds when its read head stays within this of where the voice said it was, ms of the song.
 * On the main thread a hand's samples reach the voice when the page gets to them; a page held up for a
 * moment (seen in headless Chromium, now and then: one run of ten in a device check) hands them over late, the
 * voice runs short of its path and slows - and the replay, which can't know when the page was held up,
 * follows a path the voice didn't. Then B isn't deadwax's path, and what A has that B hasn't is the
 * stall's: the run is said to need recording again rather than measured.
 */
export const REPLAY_HELD_MS = 0.5

/** Whether the replay followed what the voice did closely enough to set B, and so A against B, by it. */
export function replayHeld(numbers: Pick<Numbers, 'fitMs'>): boolean {
  return numbers.fitMs !== null && numbers.fitMs <= REPLAY_HELD_MS
}

/** Whether anything took the record while it recorded: a press the deck took, its own sound from then. */
export function tookTheRecord(messages: readonly Record<string, unknown>[]): boolean {
  return messages.some((m) => m.type === 'take')
}

/**
 * What became of the replay: it held; it didn't follow - a stall of the page (a worst miss over
 * REPLAY_HELD_MS); or there was nothing to hold it to, because nothing took the record while it recorded
 * (Record pressed and the record not turned, or a turn already under way - review of 2.0.0-player.36: that
 * was told as a stall of the page), or because the voice said nothing of where it was after the take (the
 * recording ending just after it).
 */
export type ReplayVerdict = 'held' | 'stalled' | 'untaken' | 'unreported'

export function replayVerdict(numbers: Pick<Numbers, 'fitMs' | 'taken'>): ReplayVerdict {
  if (numbers.fitMs !== null) return numbers.fitMs <= REPLAY_HELD_MS ? 'held' : 'stalled'
  return numbers.taken ? 'unreported' : 'untaken'
}

/**
 * Where B's and C's paths went - deadwax's read head where the voice sounded, and the smooth path where it
 * reads: the lowest and highest places and the fastest speed - or null when neither went anywhere.
 */
export function pathExtent(
  pos: Float64Array, speed: Float64Array, gain: Float64Array, x: Float64Array, v: Float64Array, gainX: Float64Array,
): PathExtent | null {
  let lowest = Infinity, highest = -Infinity, fastest = 0
  const take = (place: number, moving: number) => {
    if (place < lowest) lowest = place
    if (place > highest) highest = place
    if (Math.abs(moving) > fastest) fastest = Math.abs(moving)
  }
  for (let i = 0; i < pos.length; i++) if (gain[i]! > 0) take(pos[i]!, speed[i]!)
  for (let i = 0; i < x.length; i++) if (gainX[i]! > 0) take(x[i]!, v[i]!)
  return lowest <= highest ? { lowest, highest, fastest } : null
}

const words = (error: unknown) => (error instanceof Error ? error.message : String(error))

/** The middle value. */
function median(values: number[]): number {
  if (!values.length) return 0
  const sorted = [...values].sort((a, b) => a - b)
  const mid = sorted.length >> 1
  return sorted.length % 2 ? sorted[mid]! : (sorted[mid - 1]! + sorted[mid]!) / 2
}

export async function compare(input: CompareInput): Promise<Comparison> {
  const pause = input.pause ?? (() => Promise.resolve())
  const rec = input.recording
  const rate = rec.sampleRate
  const messages = rec.messages as RecordedMessage[]
  const source = { voice: rec.voice, sampleRate: rate, messages, heard: rec.heard, offset: rec.clock.offset ?? 0, scriptLagSeconds: rec.scriptLagSeconds }
  const lag = rec.voice === 'script' ? rec.scriptLagSeconds : 0
  const recorded = rec.channels[0] ?? new Float32Array(0)
  const firstBlock = rec.blockTimes[0] ?? 0
  const from = firstBlock - (2 * rec.tapBlock) / rate - 0.25
  const to = (rec.blockTimes[rec.blockTimes.length - 1] ?? firstBlock) + 0.25

  //? when the voice was told each message - fitted to what it said of itself - then the replay, every sample
  const timing = planTiming(source, from, to)
  await pause()
  const played = replay(source, { told: timing.told, from, to, windowAtStart: input.windowAtStart, windowFor: input.windowFor })
  await pause()
  const n = played.n
  const L = played.lookahead

  //? the recorded sound placed on the replay's timeline: guessed from the tap's first block, found by
  //? cross-correlation within a second of that
  const guess = Math.round((firstBlock - (2 * rec.tapBlock) / rate - played.t0) * rate)
  const found = alignment(recorded, played.audio, guess, Math.round(rate))
  const shift = found.score > 0.3 ? found.lag : guess
  const A = new Float32Array(n)
  for (let i = 0; i < n; i++) {
    const j = i - shift
    if (j >= 0 && j < recorded.length) A[i] = recorded[j]!
  }
  const aFrom = Math.max(0, shift), aTo = Math.min(n, shift + recorded.length)
  await pause()

  //? C's path: the smooth one, the delay (and the main-thread lag) behind, as the voice plays its own
  const path = pathFrom(messages, input.motion)
  const xC = new Float64Array(n), vC = new Float64Array(n), gainC = new Float64Array(n)
  for (let i = 0; i < n; i++) {
    const point = path(played.time[i]! - rec.delaySeconds - lag)
    if (point) {
      xC[i] = point.x
      vC[i] = point.v
      gainC[i] = played.gain[i]!
    }
  }
  //? what B and C read: the signal's own definition - or, for a library song, its samples along the paths,
  //? from deadwax's windows over where they went (or nothing, and why)
  let exact: Exact | null = input.exact ?? null
  let unread: string | null = null
  if (!exact && input.exactOver) {
    const extent = pathExtent(played.pos, played.speed, played.gain, xC, vC, gainC)
    if (!extent) unread = 'the record never sounded while it recorded, so there was nothing of the song to read'
    else {
      try {
        exact = await input.exactOver(extent)
      } catch (error) {
        unread = words(error)
      }
    }
  } else if (!exact) unread = 'there is nothing to read the song from'
  const B = exact ? readExactly(exact, played.pos, played.speed, played.gain, rate, L) : null
  await pause()
  const C = exact ? readExactly(exact, xC, vC, gainC, rate, L) : null
  await pause()

  //? level-matched to A where the voice sounded, on what can be heard (above MATCH_FROM_HZ: B and C keep
  //? the sub-20 Hz energy the voice's DC blocker takes out, and matched on it they played quieter)
  const sounding = (i: number) => i >= aFrom && i < aTo && i >= L && played.gain[i - L]! > 0.5
  const rmsA = audibleRmsWhere(A, rate, sounding)
  for (const clip of [B, C]) {
    if (!clip) continue
    const rms = audibleRmsWhere(clip, rate, sounding)
    if (rmsA > 1e-7 && rms > 1e-9) {
      const scale = rmsA / rms
      for (let i = 0; i < n; i++) clip[i] = clip[i]! * scale
    }
  }

  //? the stretch measured: the movement, from SETTLE_S after the take (the voice's steering and the smooth
  //? path both settling from a start - three of the voice's FOLLOW_S, and twice the path's half-width) to
  //? the hand's last sample - in read samples, and written ones (L later)
  const takes = messages.filter((m) => m.type === 'take')
  const hands = messages.filter((m) => m.type === 'hand')
  const span = input.span ?? (takes.length && hands.length ? { from: takes[0]!.time as number, to: hands[hands.length - 1]!.time as number } : null)
  //? by the voice's own time for each sample, which a clock running fast or slow keeps off any grid
  const readIndex = (t: number) => lowerBound(played.time, t + rec.delaySeconds + lag)
  const r0 = span ? Math.max(0, readIndex(span.from + SETTLE_S)) : 0
  const r1 = span ? Math.min(n - L, readIndex(span.to)) : 0
  let strayed: Numbers['strayed'] = null
  const off: number[] = []
  for (let i = r0; i < r1; i++) if (played.gain[i]! > 0.5 && gainC[i]! > 0) off.push(Math.abs(played.pos[i]! - xC[i]!))
  if (off.length) strayed = { maxMs: 1000 * off.reduce((most, value) => Math.max(most, value), 0), typicalMs: 1000 * median(off) }
  const wobble = {
    deadwax: r1 > r0 ? speedWobble(played.speed, rate, r0, r1) : null,
    smooth: r1 > r0 ? speedWobble(vC, rate, r0, r1) : null,
  }
  const w0 = Math.max(aFrom, r0 + L), w1 = Math.min(aTo, r1 + L)
  const strayNow = input.measure === 'tonal' && B && w1 > w0 ? stray(A, B, rate, w0, w1) : null
  const silenceDb = input.measure === 'silence' && w1 > w0 ? db(rmsWhere(A, (i) => i >= w0 && i < w1)) : null
  let residual = 0, energy = 0
  for (let i = aFrom; i < aTo; i++) {
    if (!sounding(i)) continue
    const d = A[i]! - played.audio[i]!
    residual += d * d
    energy += A[i]! * A[i]!
  }
  const replayDb = energy > 0 ? 10 * Math.log10(Math.max(residual, 1e-30) / energy) : null
  await pause()

  const clips = { A: A.slice(aFrom, aTo), B: B ? B.slice(aFrom, aTo) : null, C: C ? C.slice(aFrom, aTo) : null }
  let images: Comparison['images'] = null
  if (input.pictures) {
    const drawn = spectrograms([clips.A, ...(clips.B && clips.C ? [clips.B, clips.C] : [])], rate)
    images = { A: drawn[0]!, B: drawn[1] ?? null, C: drawn[2] ?? null }
  }
  return {
    rate, clips, unread, images, measured: w1 > w0 ? { from: w0 - aFrom, to: w1 - aFrom } : null,
    numbers: {
      strayed, wobble, stray: strayNow, silenceDb, replayDb, alignScore: found.score,
      leadMs: timing.lead * 1000, fitMs: Number.isFinite(timing.worst) ? timing.worst * 1000 : null,
      taken: tookTheRecord(messages),
    },
  }
}
