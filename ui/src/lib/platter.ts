/**
 * The turntable's platter (2.0.0-player.14): how it moves once a hand has flicked it, how its motor
 * brings it back to speed, and how it spins up and down on play and pause - pure, so
 * ui/test/deck.sim.cjs can hold it to an integration of the same equations.
 *
 * James, on the turntable of 2.0.0-player.11: "can we add momentum to the disc as well?", and then
 * "And the audio will speed up and slow down with it?". A flick keeps the record turning and it
 * coasts; the platter spins up and down like a real deck's; the sound follows (lib/deckVoice.ts).
 *
 * UNITS: the platter's SPEED is in its own speeds - 1 is 33 1/3 rpm, the song at its own pace, 0 is
 * still, negative is backwards - so it is also the rate the record's sound is read at (`voiceRate`).
 * POSITIONS are in seconds of the song, 1.8 s a turn (lib/turntable's SECONDS_PER_TURN): a turn of
 * the record by hand and a turn of it under the motor move the song by the same.
 *
 * THE EQUATIONS - each simple enough to have an exact answer, so where a flick lands, and where a
 * playing song is when the motor has it back at speed, are known the moment the finger lets go
 * (`coast`, `motor`). That is what lets the player seek the song there AT the release, with all of
 * the coast for the element to buffer in.
 *
 *  - Free (the song paused, or the motor off): friction, a constant part and a part that grows with
 *    the speed, dv/dt = -(FRICTION_DRY + FRICTION_VISCOUS * |v|) against the direction of travel.
 *    The two are set so that the record coming down from its own speed stops in SPIN_DOWN_S (1 s) -
 *    the pause's wind-down - and a hard flick (9 times its speed, five turns a second) coasts for
 *    about 1.8 s: "a hard flick coasts for about 1-2 s". Mostly the speed's part, so a flick slows
 *    quickly and then drifts, as a heavy platter does; the constant part is what stops it.
 *  - The motor (the song playing): from still up to its own speed it pulls with a constant torque,
 *    MOTOR_PULL, 1 / SPIN_UP_S - from still to speed in 0.4 s; above its speed it brakes as friction
 *    does plus that same pull, so a forward flick comes back down in under a second; and turning
 *    BACKWARDS both work against the travel - the pull and the whole of friction - so a backwards
 *    flick is stopped as quickly as a forward one is brought down (a hard one, -9, in about 0.86 s),
 *    then pulled up from still. (Until review the backwards stretch had the pull alone, and a
 *    playing record flicked back at -9 ran backwards for 3.6 s and rewound 16 s - longer than the
 *    same flick coasts with the motor off, the wrong way round.) It reaches its speed exactly, at a
 *    known moment: the moment the song carries on from the element.
 *  - The song's ends: a coast that would run back past the start stops at the start; one that would
 *    run on past the end stops END_MARGIN_S short of it, and the song ends from there as it would.
 *    A motor run back to the start stops there and spins up from it.
 *
 * THE MOTOR'S SPEED is the player's (2.0.0-player.39, lib/playSpeed): 0.25x to 2x, `target` in the
 * platter's own speeds - 1.5 is 50 rpm, the song at 1.5x. The same motor, the same equations with
 * `target` where they had 1: the same pull below it (so still to 2x takes twice SPIN_UP_S, and to 0.25x
 * a quarter), the same braking above it, and every phase still exact. Friction knows no target: a
 * coast is the same at any speed, and the wind-down starts from the song's own speed, whatever it is.
 */

import { SECONDS_PER_TURN } from './turntable'

/** From still to the platter's own speed under the motor, in seconds. */
export const SPIN_UP_S = 0.4
/** From its own speed to still with the motor off - the wind-down of a pause - in seconds. */
export const SPIN_DOWN_S = 1

/** The motor's pull below its own speed, in speeds per second: still to speed in SPIN_UP_S. */
export const MOTOR_PULL = 1 / SPIN_UP_S
/** Friction's part that grows with the speed, per second. With FRICTION_DRY it brings the platter
 *  down from its own speed in exactly SPIN_DOWN_S, and a flick of 9 in about 1.8 s. */
export const FRICTION_VISCOUS = 2.674
/** Friction's constant part, in speeds per second: what stops it rather than leaving it to drift.
 *  Worked out from FRICTION_VISCOUS so that ln(1 + VISCOUS / DRY) / VISCOUS is SPIN_DOWN_S. */
export const FRICTION_DRY = FRICTION_VISCOUS / (Math.exp(FRICTION_VISCOUS * SPIN_DOWN_S) - 1)

/** How far short of the song's end a coast running past it stops, in seconds - the song then ends
 *  from there by itself, as it would have. */
export const END_MARGIN_S = 0.25

/** How far back the hand's speed is taken from at a release, in ms - its last ~90 ms. */
export const VELOCITY_WINDOW_MS = 90

/** The fastest the platter is taken to go, either way, in its own speeds: a flick faster than a
 *  finger can really turn it (a jump in the pointer's samples) is held to this. */
export const MAX_SPEED = 24

/** The platter's own speed as an angle a second, in degrees: a turn in SECONDS_PER_TURN. */
export const DEGREES_PER_SECOND = 360 / SECONDS_PER_TURN

/** The rate the record's sound is read at, for a platter turning at `speed`: the platter's speed over
 *  its own - which, in these units, is the speed itself. */
export function voiceRate(speed: number): number {
  return speed
}

/** How far the record turns, in degrees, while the song moves by `seconds` under it. */
export function degreesFor(seconds: number): number {
  return seconds * DEGREES_PER_SECOND
}

/* ===== the hand's speed ===== */

/** A pointer sample: when (ms, the event's timeStamp) and how far the hand had turned the record
 *  since the press (radians, clockwise - lib/turntable's RecordDrag.turned, which counts nothing at
 *  the spindle). */
export interface HandSample {
  time: number
  turned: number
}

/** How far the hand had turned the record at `time`, between the samples (or held at the nearest
 *  one outside them: a finger that rests sends no samples, and has turned no further). */
function turnedAt(samples: readonly HandSample[], time: number): number {
  if (!samples.length) return 0
  if (time <= samples[0]!.time) return samples[0]!.turned
  for (let i = 1; i < samples.length; i++) {
    const before = samples[i - 1]!, after = samples[i]!
    if (time <= after.time) {
      const span = after.time - before.time
      return span > 0 ? before.turned + ((after.turned - before.turned) * (time - before.time)) / span : after.turned
    }
  }
  return samples[samples.length - 1]!.turned
}

/**
 * The hand's speed at `time` (ms), in the platter's own speeds: how far it turned the record over
 * the `windowMs` before it, as song seconds a second. A finger that stopped before letting go has
 * turned nothing since, so its speed is what the stop leaves of the window - a rest of the whole
 * window is 0 - and a flick is its last ~90 ms, not the slow start of the turn. Held to MAX_SPEED.
 */
export function handSpeed(samples: readonly HandSample[], time: number, windowMs = VELOCITY_WINDOW_MS): number {
  if (samples.length < 2 || !(windowMs > 0)) return 0
  const turn = turnedAt(samples, time) - turnedAt(samples, time - windowMs)
  const speed = (turn / (2 * Math.PI)) * SECONDS_PER_TURN / (windowMs / 1000)
  return Math.max(-MAX_SPEED, Math.min(MAX_SPEED, speed))
}

/** How long a gap between the hand's last sample and its release is not a rest, in ms: a finger moving
 *  right up to lifting off sends its last move up to a frame or so before the release - a sample's
 *  spacing at 60 Hz, and its delivery. */
export const RELEASE_TAIL_MS = 40

/**
 * The platter's speed as the hand lets go at `time` (ms) - 2.0.0-player.24: the hand's speed over the
 * `windowMs` up to its LAST SAMPLE, by the samples' own times, not up to the release. A finger moving to
 * the last sends its last move up to a frame before it lifts, and taken up to the release that still
 * tail read as slowing - a fifth slower, a frame in 90 ms. A longer gap is a finger that rested before
 * letting go: past `tailMs` the rest takes the speed down in proportion, to none once it is a whole
 * window - as handSpeed has it - so a finger that stopped before letting go doesn't flick.
 */
export function releaseSpeed(samples: readonly HandSample[], time: number, windowMs = VELOCITY_WINDOW_MS, tailMs = RELEASE_TAIL_MS): number {
  if (samples.length < 2 || !(windowMs > 0)) return 0
  const last = samples[samples.length - 1]!.time
  const gap = Math.max(0, time - last)
  if (gap >= windowMs) return 0
  const rested = Math.max(0, gap - tailMs) / Math.max(1e-9, windowMs - tailMs)
  return handSpeed(samples, last, windowMs) * (1 - rested)
}

/* ===== the equations, one phase at a time ===== */

/**
 * One stretch of the platter's movement with one equation: from `x0` (song seconds) at `v0` (its own
 * speeds), for `duration` seconds.
 *  - 'pull': a constant acceleration `a` - the motor below its speed.
 *  - 'decay': du/dt = -(c + k u), with u how far the speed is past `base` in the direction `sign` - a
 *    constant deceleration `c` and one, `k`, that grows with the speed; so u = (u0 + c/k) e^(-k t) - c/k
 *    (backwards travel is the mirror of forwards) - friction, about 0; the motor braking a flick
 *    down to its speed, about 1; and the motor with friction stopping a backwards flick, about 0.
 *  - 'rest': still, at x0.
 *  - 'cruise': its own speed, 1.
 */
export type Phase =
  | { kind: 'pull'; x0: number; v0: number; a: number; duration: number }
  | { kind: 'decay'; x0: number; v0: number; base: number; sign: 1 | -1; c: number; k: number; duration: number }
  | { kind: 'rest'; x0: number; duration: number }

/** Where a phase has the platter `t` seconds into it, and how fast it is going. */
export function phaseAt(phase: Phase, t: number): { x: number; v: number } {
  const time = Math.max(0, Math.min(t, phase.duration))
  switch (phase.kind) {
    case 'pull':
      return { x: phase.x0 + phase.v0 * time + 0.5 * phase.a * time * time, v: phase.v0 + phase.a * time }
    case 'decay': {
      //? in the phase's own direction, relative to its base speed: u = s (v - base), du/dt = -(c + k u)
      const u0 = phase.sign * (phase.v0 - phase.base)
      const q = phase.c / phase.k
      const e = Math.exp(-phase.k * time)
      const u = (u0 + q) * e - q
      const travelled = ((u0 + q) * (1 - e)) / phase.k - q * time
      return { x: phase.x0 + phase.base * time + phase.sign * travelled, v: phase.base + phase.sign * u }
    }
    case 'rest':
      return { x: phase.x0, v: 0 }
  }
}

/** How long a decay takes to bring u0 (> 0) down to 0: from (u0 + c/k) e^(-k T) = c/k, T = ln(1 + k u0 / c) / k. */
function decayTime(u0: number, c: number, k: number): number {
  return Math.log(1 + (k * u0) / c) / k
}

/**
 * When x(t) of a monotonic stretch of a phase first reaches `bound` - by bisection, to a microsecond,
 * which is far inside the millisecond the sim holds the landing to. Only ever asked of a stretch the
 * bound is known to be crossed in.
 */
function timeTo(phase: Phase, bound: number, within: number): number {
  const start = phaseAt(phase, 0).x
  const rising = phaseAt(phase, within).x > start
  let lo = 0, hi = within
  for (let i = 0; i < 60 && hi - lo > 1e-9; i++) {
    const mid = (lo + hi) / 2
    const x = phaseAt(phase, mid).x
    if (rising ? x < bound : x > bound) lo = mid
    else hi = mid
  }
  return hi
}

/** A whole movement: its phases in order, how long they take altogether, where it ends and how fast
 *  it is going then - still for a coast, its own speed for the motor - and whether it hit an end. */
export interface Plan {
  phases: Phase[]
  duration: number
  x: number
  v: number
  /** the speed it heads for: 0 for a coast, the motor's speed for the motor (2.0.0-player.39) */
  target: number
  /** 'start' or 'end' when it was stopped by the song's end; null when it ran its course */
  clamped: 'start' | 'end' | null
}

/** Where a plan has the platter `t` seconds into it, and how fast. After its end: where it ended, at
 *  its end's speed. */
export function planAt(plan: Plan, t: number): { x: number; v: number } {
  let left = Math.max(0, t)
  for (const phase of plan.phases) {
    if (left <= phase.duration) return phaseAt(phase, left)
    left -= phase.duration
  }
  return { x: plan.x, v: plan.v }
}

/** The song's playable stretch for a coast: 0 to END_MARGIN_S short of its end (all of it when it is
 *  shorter than that, or has no length known - then nothing stops a coast but friction). */
function limits(length: number): { low: number; high: number } {
  if (!(length > 0)) return { low: 0, high: Infinity }
  return { low: 0, high: Math.max(0, length - END_MARGIN_S) }
}

/** A phase cut short where it reaches a bound, if it does within its duration. */
function clampPhase(phase: Phase, low: number, high: number): { phase: Phase; hit: 'start' | 'end' | null } {
  const end = phaseAt(phase, phase.duration).x
  //? each phase here moves one way only, so its extreme is at one of its ends
  if (end < low && phaseAt(phase, 0).x >= low) return { phase: { ...phase, duration: timeTo(phase, low, phase.duration) }, hit: 'start' }
  if (end > high && phaseAt(phase, 0).x <= high) return { phase: { ...phase, duration: timeTo(phase, high, phase.duration) }, hit: 'end' }
  return { phase, hit: null }
}

function finish(phases: Phase[], clamped: Plan['clamped'], v: number, bounds: { low: number; high: number }, target: number): Plan {
  const last = phases[phases.length - 1]
  //? stopped by an end: exactly at it, never the bisection's last nanosecond either side
  const x = clamped === 'start' ? bounds.low : clamped === 'end' ? bounds.high : last ? phaseAt(last, last.duration).x : 0
  return { phases, duration: phases.reduce((sum, phase) => sum + phase.duration, 0), x, v, clamped, target }
}

/**
 * The platter let go of with the song PAUSED: it coasts under friction to a stop - where the song
 * lands, and stays paused. From `x` (song seconds) at `speed`; clamped to the song (see the module).
 */
export function coast(x: number, speed: number, length: number): Plan {
  const bounds = limits(length)
  const { low, high } = bounds
  const start = Math.max(low, Math.min(high, Number.isFinite(x) ? x : low))
  if (speed === 0 || !Number.isFinite(speed)) return finish([{ kind: 'rest', x0: start, duration: 0 }], null, 0, bounds, 0)
  const sign: 1 | -1 = speed > 0 ? 1 : -1
  const u0 = Math.abs(speed)
  const phase: Phase = {
    kind: 'decay', x0: start, v0: speed, base: 0, sign, c: FRICTION_DRY, k: FRICTION_VISCOUS,
    duration: decayTime(u0, FRICTION_DRY, FRICTION_VISCOUS),
  }
  const { phase: kept, hit } = clampPhase(phase, low, high)
  return finish([kept], hit, 0, bounds, 0)
}

/**
 * The platter let go of with the song PLAYING: the motor takes it back to its own speed - pulling
 * it up from below (stopping it first, from backwards), braking it down from above - and the song carries
 * on from where it is then (`x` of the plan, at `duration`). A run back past the start stops there and
 * spins up from it; one on past the end stops short of it, and the song plays out from there. Its own
 * speed is `target` - the player's speed (2.0.0-player.39), 1 unless the speed fader says otherwise.
 */
export function motor(x: number, speed: number, length: number, target = 1): Plan {
  const bounds = limits(length)
  const { low, high } = bounds
  let at = Math.max(low, Math.min(high, Number.isFinite(x) ? x : low))
  let v = Number.isFinite(speed) ? Math.max(-MAX_SPEED, Math.min(MAX_SPEED, speed)) : 0
  const phases: Phase[] = []
  let clamped: Plan['clamped'] = null
  if (v > target) {
    //? braked down to speed: the motor's pull, and friction's speed part, against the overspeed
    const phase: Phase = {
      kind: 'decay', x0: at, v0: v, base: target, sign: 1, c: MOTOR_PULL, k: FRICTION_VISCOUS,
      duration: decayTime(v - target, MOTOR_PULL, FRICTION_VISCOUS),
    }
    const { phase: kept, hit } = clampPhase(phase, low, high)
    phases.push(kept)
    return finish(phases, hit, hit ? phaseAt(kept, kept.duration).v : target, bounds, target)
  }
  if (v < target) {
    if (v < 0) {
      //? backwards: brought to a stop first - the motor's pull and all of friction against the travel,
      //? a decay towards still - then pulled on up; unless the start comes first
      const toStill: Phase = {
        kind: 'decay', x0: at, v0: v, base: 0, sign: -1, c: MOTOR_PULL + FRICTION_DRY, k: FRICTION_VISCOUS,
        duration: decayTime(-v, MOTOR_PULL + FRICTION_DRY, FRICTION_VISCOUS),
      }
      const { phase: kept, hit } = clampPhase(toStill, low, high)
      phases.push(kept)
      if (hit) clamped = hit
      //? stopped at the start, or still: either way the spin-up begins there, from still
      at = hit === 'start' ? low : phaseAt(kept, kept.duration).x
      v = 0
    }
    const up: Phase = { kind: 'pull', x0: at, v0: v, a: MOTOR_PULL, duration: (target - v) / MOTOR_PULL }
    const { phase: kept, hit } = clampPhase(up, low, high)
    phases.push(kept)
    if (hit) return finish(phases, hit, phaseAt(kept, kept.duration).v, bounds, target)
    //? a stop at the start on the way doesn't move where it ends: the spin-up from there does
    const ended = finish(phases, null, target, bounds, target)
    return { ...ended, clamped }
  }
  return finish([{ kind: 'rest', x0: at, duration: 0 }], null, target, bounds, target)
}

/* ===== the equations as equations, for the sim to integrate ===== */

/**
 * dv/dt for a platter at `speed`, the motor on or off - the equations the plans above solve, written
 * out so ui/test/deck.sim.cjs can integrate them step by step and hold the plans to within a
 * millisecond of what the steps give. The motor's own speed is `target` (2.0.0-player.39).
 */
export function acceleration(speed: number, motorOn: boolean, target = 1): number {
  if (motorOn) {
    //? backwards: the pull and the whole of friction, both against the travel
    if (speed < 0) return MOTOR_PULL + FRICTION_DRY + FRICTION_VISCOUS * -speed
    if (speed < target) return MOTOR_PULL
    if (speed > target) return -(MOTOR_PULL + FRICTION_VISCOUS * (speed - target))
    return 0
  }
  if (speed > 0) return -(FRICTION_DRY + FRICTION_VISCOUS * speed)
  if (speed < 0) return FRICTION_DRY + FRICTION_VISCOUS * -speed
  return 0
}
