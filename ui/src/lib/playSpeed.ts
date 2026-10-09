/**
 * The player's speed (2.0.0-player.39): 0.25x to 2x, the pitch moving with it - a record deck's pitch,
 * not a time-stretch. PURE: the numbers, the words, the fader's maths and its place on the plinth, and
 * what Info > Debug reads - so ui/test/playspeed.sim.cjs can hold every rule to its answers. The engine
 * (player/usePlayer.ts) puts the speed on its audio elements; the fader (player/SpeedFader.tsx, on the
 * turntable) and the chip (player/SpeedChip.tsx, on the cover and the desktop's player bar) set it.
 *
 * James (2026-10-08): "let's add the speed slider" - then "actually let's stick to .25-2x".
 *
 * - THE RANGE: SPEED_MIN to SPEED_MAX, in hundredths (roundSpeed) - what the readout says is what plays.
 * - THE FADER is a deck's pitch fader stood beside the platter: slow at the bottom, fast at the top,
 *   and LOGARITHMIC - each third of its travel an octave (0.25x, 0.5x, 1x, 2x evenly spaced), which is
 *   how the ear hears pitch - so 1x sits two thirds of the way up. Its DETENT: a drag that comes within
 *   SPEED_DETENT of 1x is 1x exactly (keys step past it: an arrow from 1x is 1.01x). A drag takes hold
 *   only once the finger has travelled TAP_SLOP_PX, the arm's rule, and from where the speed is then -
 *   so a press, or a nudge, never jumps the speed to the finger.
 * - THE WORDS: "1.25x" (the readout and the chip, two places always), "1.25 times" or "normal speed"
 *   (what a screen reader hears).
 */

import { RECORD, STAGE, TAP_SLOP_PX } from './turntable'

/** The slowest and fastest the player plays: a quarter of the song's speed, and twice it. */
export const SPEED_MIN = 0.25
export const SPEED_MAX = 2
/** The song at its own speed - nothing about playback changes from before the speed existed. */
export const SPEED_NORMAL = 1
/** A drag within this of 1x lands on 1x exactly - the fader's detent. */
export const SPEED_DETENT = 0.02
/** What an arrow key moves it by, and Page Up and Page Down. */
export const SPEED_STEP = 0.01
export const SPEED_PAGE = 0.1

/** The speed in hundredths - what the readout shows is exactly what plays. */
export function roundSpeed(speed: number): number {
  return Math.round(speed * 100) / 100
}

/** Whether a value is a speed the player takes: a number from SPEED_MIN to SPEED_MAX. */
export function isSpeed(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= SPEED_MIN && value <= SPEED_MAX
}

/** Any number as a speed: held to the range, in hundredths - and 1x for one that isn't a number. */
export function clampSpeed(speed: number): number {
  if (!Number.isFinite(speed)) return SPEED_NORMAL
  return roundSpeed(Math.max(SPEED_MIN, Math.min(SPEED_MAX, speed)))
}

/** The detent: a speed within SPEED_DETENT of 1x is 1x. */
export function detent(speed: number): number {
  return Math.abs(speed - SPEED_NORMAL) <= SPEED_DETENT + 1e-9 ? SPEED_NORMAL : speed
}

/** How far up the fader a speed is, 0 (the bottom, SPEED_MIN) to 1 (the top, SPEED_MAX): by octaves. */
export function faderShare(speed: number): number {
  const held = Math.max(SPEED_MIN, Math.min(SPEED_MAX, Number.isFinite(speed) ? speed : SPEED_NORMAL))
  return Math.log(held / SPEED_MIN) / Math.log(SPEED_MAX / SPEED_MIN)
}

/** The speed at a share of the fader's travel, in hundredths, through the detent. */
export function speedAt(share: number): number {
  const at = Math.max(0, Math.min(1, Number.isFinite(share) ? share : 0))
  return detent(clampSpeed(SPEED_MIN * (SPEED_MAX / SPEED_MIN) ** at))
}

/** "1.25x", "0.50x", "1.00x" - the readout's and the chip's words. */
export function speedLabel(speed: number): string {
  return `${roundSpeed(speed).toFixed(2)}x`
}

/** What a screen reader hears: "normal speed", or "1.25 times", "0.5 times", "2 times". */
export function speedWords(speed: number): string {
  const rounded = roundSpeed(speed)
  return rounded === SPEED_NORMAL ? 'normal speed' : `${String(rounded)} times`
}

/**
 * A key on the fader: the arrows a hundredth (up and right faster), Page Up and Page Down a tenth, Home
 * the slowest, End the fastest - or null for a key that isn't the fader's. No detent here: an arrow
 * from 1x goes to 1.01x, which a detent would put straight back.
 */
export function speedKey(key: string, speed: number): number | null {
  switch (key) {
    case 'ArrowUp':
    case 'ArrowRight':
      return clampSpeed(speed + SPEED_STEP)
    case 'ArrowDown':
    case 'ArrowLeft':
      return clampSpeed(speed - SPEED_STEP)
    case 'PageUp':
      return clampSpeed(speed + SPEED_PAGE)
    case 'PageDown':
      return clampSpeed(speed - SPEED_PAGE)
    case 'Home':
      return SPEED_MIN
    case 'End':
      return SPEED_MAX
    default:
      return null
  }
}

/* ===== the fader on the plinth: the Turntable board has none, so it is drawn in its style ===== */

/**
 * The fader's slot in the plinth's own units (lib/turntable's STAGE): stood at the right of the platter
 * like a deck's pitch control, its knob's centre travelling from `top` (SPEED_MAX) to `bottom`
 * (SPEED_MIN), clear of the platter (whose widest point is x 346), of the arm (which never swings right of
 * x 345 down there) and of the plinth's edge (372). The knob is `knob` wide and tall; the slot runs the
 * knob's whole travel. Its target (faderTarget) starts `clear` right of the record's rim, never on it.
 */
export const FADER = {
  x: 359, top: 150, bottom: 318, clear: 1,
  /** the slot: its width and corners */
  slot: 6, slotRadius: 2,
  /** the knob, its corners, and the grip line across it */
  knob: { width: 20, height: 12, radius: 3, grip: 1.5, gripInset: 3 },
  /** the mark at 1x across the slot: how far past the knob's sides it shows, and how thick */
  mark: { overhang: 2, thick: 2 },
} as const
/** The readout under it, at the plinth's bottom right corner - clear of the platter there. */
export const READOUT = { x: 344, y: 349 } as const

/** Where the fader's target may start, in the plinth's units: the record's rim (lib/turntable's RECORD)
 *  and FADER.clear more - the record takes every touch on itself. */
export const FADER_FROM = RECORD.x + RECORD.r + FADER.clear

/**
 * The fader's target across the plinth, in its units, as app.css's .app-tt-fader places it on a plinth
 * `stage` CSS px wide: a tap target wide (`hit`, 44px), no wider than `cap` of the plinth (a phone on its
 * side), centred on the slot - unless that would reach the record, which a 44px target does on any plinth
 * under about 410px (every phone's): then it starts at FADER_FROM and reaches past the slot to the right, into the room round
 * the plinth (review of 2.0.0-player.39: centred, it covered the record's rim, whose taps and turns it
 * took). The knob is inside it either way.
 */
export function faderTarget(stage: number, hit = 44, cap = 0.14): { left: number; right: number } {
  const width = Math.min((hit / Math.max(stage, 1e-9)) * STAGE.width, cap * STAGE.width)
  const left = Math.max(FADER_FROM, FADER.x - width / 2)
  return { left, right: left + width }
}

const pct = (value: number) => `${+(value * 100).toFixed(4)}%`

/** The knob's centre for a speed, as a share of the stage's height from its top. */
export function knobTop(speed: number): string {
  return pct((FADER.bottom - faderShare(speed) * (FADER.bottom - FADER.top)) / STAGE.height)
}

/** How far the knob travels on screen, in CSS px, for a stage `height` px tall. */
export function faderTravel(height: number): number {
  return ((FADER.bottom - FADER.top) / STAGE.height) * Math.max(0, height)
}

/* ===== a finger on the fader ===== */

export interface FaderDrag {
  pointer: number
  /** where it went down, CSS px */
  y0: number
  /** where it took hold - the slop's edge, along the finger's way - and the share the speed was at
   *  then; null until the finger has travelled TAP_SLOP_PX */
  from: { y: number; share: number } | null
}

export function faderStart(pointer: number, y: number): FaderDrag {
  return { pointer, y0: y, from: null }
}

/**
 * The finger moved to `y` on a fader `travel` px long, the speed `speed` before it. Nothing changes
 * until it has travelled TAP_SLOP_PX; then it takes hold at the slop's edge, from where the speed is -
 * so nothing jumps - and from there the knob follows the finger (up is faster), held to the fader's
 * ends and through its detent. `speed` is null while nothing changes. Any other pointer changes
 * nothing.
 */
export function faderMove(drag: FaderDrag | null, pointer: number, y: number, travel: number, speed: number): { drag: FaderDrag | null; speed: number | null } {
  if (!drag || drag.pointer !== pointer || !(travel > 0)) return { drag, speed: null }
  let held = drag
  if (!held.from) {
    const moved = y - held.y0
    if (Math.abs(moved) < TAP_SLOP_PX) return { drag, speed: null }
    held = { ...held, from: { y: held.y0 + Math.sign(moved) * TAP_SLOP_PX, share: faderShare(speed) } }
  }
  const from = held.from!
  return { drag: held, speed: speedAt(from.share + (from.y - y) / travel) }
}

/** The finger let go (or the system took it): the drag is over - unless it is another pointer's. */
export function faderEnd(drag: FaderDrag | null, pointer: number): FaderDrag | null {
  return drag && drag.pointer === pointer ? null : drag
}

/* ===== what the browser does with it - Info > Debug ===== */

/** The three names browsers have given pitch preservation, the standard one first. */
export type PitchSwitch = 'preservesPitch' | 'webkitPreservesPitch' | 'mozPreservesPitch'
const PITCH_SWITCHES: readonly PitchSwitch[] = ['preservesPitch', 'webkitPreservesPitch', 'mozPreservesPitch']

/** Which of them an element has - the standard one where it has it, a prefixed one only where that is
 *  all it has - or null for none. */
export function pitchSwitch(has: (name: PitchSwitch) => boolean): PitchSwitch | null {
  return PITCH_SWITCHES.find((name) => has(name)) ?? null
}

/**
 * The speed's pitch switch: held (the browser's own default, which a time-stretch keeps) at 1x - where
 * deadwax leaves it untouched - and let go at any other speed, so the pitch moves with it.
 */
export function pitchHeldAt(speed: number): boolean {
  return speed === SPEED_NORMAL
}

/** What the player knows of the speed for Info > Debug (usePlayer's speedReading). */
export interface SpeedReading {
  /** the speed asked for */
  speed: number
  /** the element's playbackRate as it reads back */
  rate: number
  /** whether the element's pitch switch says the pitch moves, is held, or it has none */
  pitch: 'moves' | 'held' | 'no switch'
  /** the browser's words, when it refused the rate */
  refused: string | null
  /** the song's own clock against the page's while it played - seconds of song a second - over the
   *  last PACE_WINDOW_S; null until there is PACE_MIN_S of it */
  measured: number | null
}

/* ===== the song's own pace, measured: whether the browser plays the speed it was given ===== */

/** How much playing the measured pace is taken over, in seconds of the page's clock, and how much it
 *  needs before it says anything. */
export const PACE_WINDOW_S = 8
export const PACE_MIN_S = 2

/** One step of playing: seconds of song, over seconds of the page's clock. */
export interface PaceSample {
  media: number
  wall: number
}

/** The window with a step added, its oldest steps let go past PACE_WINDOW_S of the page's clock. The
 *  caller leaves out a step across a seek, a pause or a song change - nothing to measure there. */
export function paceStep(window: readonly PaceSample[], sample: PaceSample): PaceSample[] {
  if (!(sample.wall > 0) || !(sample.media >= 0)) return [...window]
  const kept = [...window, sample]
  let wall = kept.reduce((sum, step) => sum + step.wall, 0)
  while (kept.length > 1 && wall - kept[0]!.wall >= PACE_WINDOW_S) wall -= kept.shift()!.wall
  return kept
}

/** Seconds of song a second of the page's clock over the window - null under PACE_MIN_S of it. */
export function paceOf(window: readonly PaceSample[]): number | null {
  const wall = window.reduce((sum, step) => sum + step.wall, 0)
  if (wall < PACE_MIN_S) return null
  return window.reduce((sum, step) => sum + step.media, 0) / wall
}
