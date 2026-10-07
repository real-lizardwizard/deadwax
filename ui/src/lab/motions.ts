/**
 * "Turn it for me" (2.0.0-player.36): movements without a hand, for the test bench - each a path through
 * the song from where the record is taken, sampled 60 times a second on the page's clock as a pointer's
 * events are stamped, with no jitter - or with a finger's (decksound.sim's: a Gaussian 1.5 ms off in
 * time, read as where the path was then, and 1 ms off in the song's place). Pure; lab/runner.ts hands
 * the samples to the deck through the very methods a press does.
 */

import { SECONDS_PER_TURN } from '../lib/turntable'

export type MotionId = 'steady1' | 'half' | 'quarter' | 'double' | 'back1' | 'wobble' | 'ramp' | 'scratch'

export interface Motion {
  id: MotionId
  label: string
  /** how long it turns, seconds */
  seconds: number
  /** how far it has moved the song at `t` seconds since it took the record, seconds of the song */
  path(t: number): number
  /** how fast, in the song's own speeds (1 the song playing) */
  speed(t: number): number
}

/** The hand's drift: 10% either way, 1.3 times a second. */
const WOBBLE = 0.1
const WOBBLE_HZ = 1.3
/** A slow ramp: 0.25x to 2x and back, over 8 s. */
const RAMP_LOW = 0.25
const RAMP_HIGH = 2
const RAMP_SECONDS = 8
/** A scratch: back and forth, at most 1.5x, twice a second. */
const SCRATCH = 1.5
const SCRATCH_HZ = 2

const steady = (id: MotionId, label: string, k: number): Motion => ({ id, label, seconds: 6, path: (t) => k * t, speed: () => k })

export const MOTIONS: readonly Motion[] = [
  steady('steady1', 'Steady 1x', 1),
  steady('half', '0.5x', 0.5),
  steady('quarter', '0.25x', 0.25),
  steady('double', '2x', 2),
  steady('back1', 'Backwards 1x', -1),
  {
    id: 'wobble', label: '1x with a slow wobble', seconds: 6,
    path: (t) => t + (WOBBLE / (2 * Math.PI * WOBBLE_HZ)) * (1 - Math.cos(2 * Math.PI * WOBBLE_HZ * t)),
    speed: (t) => 1 + WOBBLE * Math.sin(2 * Math.PI * WOBBLE_HZ * t),
  },
  {
    id: 'ramp', label: 'A slow ramp (0.25x to 2x and back)', seconds: RAMP_SECONDS,
    path: (t) => RAMP_LOW * t + (RAMP_HIGH - RAMP_LOW) * (t / 2 - (RAMP_SECONDS / (4 * Math.PI)) * Math.sin((2 * Math.PI * t) / RAMP_SECONDS)),
    speed: (t) => RAMP_LOW + (RAMP_HIGH - RAMP_LOW) * Math.sin((Math.PI * t) / RAMP_SECONDS) ** 2,
  },
  {
    id: 'scratch', label: 'A scratch (back and forth, 1.5x at 2 Hz)', seconds: 6,
    path: (t) => (SCRATCH / (2 * Math.PI * SCRATCH_HZ)) * (1 - Math.cos(2 * Math.PI * SCRATCH_HZ * t)),
    speed: (t) => SCRATCH * Math.sin(2 * Math.PI * SCRATCH_HZ * t),
  },
]

/** Samples a second, as a 60 Hz screen's touch events come. */
export const MOTION_HZ = 60
/** A finger's jitter, as decksound.sim gives it: in time (read as where the path was then) and in place. */
export const JITTER_TIME_MS = 1.5
export const JITTER_PLACE_S = 0.001

export interface MotionSample {
  /** page ms - the event's own time */
  time: number
  /** how far the song has moved since the take, seconds */
  moved: number
  /** how far the hand has turned the record since the press, radians (lib/turntable's `turned`) */
  turned: number
}

/** A Gaussian from a uniform source (Box-Muller). */
export function gaussian(random: () => number): number {
  let u = 0
  while (u === 0) u = random()
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * random())
}

/**
 * The motion's samples from page time `t0` (ms): the first at t0 itself, where the record is taken, then
 * one every 1000/MOTION_HZ ms to the end - each stamped exactly on that grid. With `random`, each carries
 * a finger's jitter (not the first: the take is where the record is).
 */
export function motionSamples(motion: Motion, t0: number, random: (() => number) | null = null): MotionSample[] {
  const every = 1000 / MOTION_HZ
  const count = Math.floor(motion.seconds * MOTION_HZ + 1e-9)
  const out: MotionSample[] = []
  for (let k = 0; k <= count; k++) {
    const time = t0 + k * every
    let moved = motion.path((k * every) / 1000)
    if (random && k > 0) moved = motion.path((k * every + gaussian(random) * JITTER_TIME_MS) / 1000) + gaussian(random) * JITTER_PLACE_S
    out.push({ time, moved, turned: (moved / SECONDS_PER_TURN) * 2 * Math.PI })
  }
  return out
}

/** Room a motion keeps from the song's start, and from its end (the coast after it lets go, and the
 *  deck's window ahead), seconds. */
export const ROOM_BEFORE_S = 2
export const ROOM_AFTER_S = 4
/** Where a motion starts when the record isn't somewhere it fits: this far in, if the song has room. */
export const MOTION_START_S = 20

/** How far back and forward of where it took the record a motion goes, seconds of the song. */
export function motionReach(motion: Motion): { back: number; ahead: number } {
  let low = 0, high = 0
  for (let k = 0; k <= 600; k++) {
    const moved = motion.path((k / 600) * motion.seconds)
    low = Math.min(low, moved)
    high = Math.max(high, moved)
  }
  return { back: -low, ahead: high }
}

/**
 * Where to take the record for `motion` on a song `length` seconds long, the record now at `at`: there,
 * if the motion fits from there with ROOM_BEFORE_S before it and ROOM_AFTER_S after; else MOTION_START_S
 * in, or as near it as fits; null when the song is too short for the motion at all (a short file) - it
 * would run off the song's end (review of 2.0.0-player.36: an 8 s file started a motion at its end, and
 * read a wobble of 114%).
 */
export function motionStart(motion: Motion, length: number, at: number): number | null {
  const { back, ahead } = motionReach(motion)
  const earliest = ROOM_BEFORE_S + back, latest = length - ROOM_AFTER_S - ahead
  if (!(latest >= earliest)) return null
  if (at >= earliest && at <= latest) return at
  return Math.max(earliest, Math.min(latest, MOTION_START_S))
}

/** How long a song must be for `motion`, seconds - what a short file is told. */
export function motionNeeds(motion: Motion): number {
  const { back, ahead } = motionReach(motion)
  return ROOM_BEFORE_S + back + ahead + ROOM_AFTER_S
}
