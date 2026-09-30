/**
 * Now Playing as a turntable (2.0.0-player.11): the record, the tonearm and what a finger does to
 * them - pure, so ui/test/turntable.sim.cjs can hold it to the answers.
 *
 * James: "the playhead moved toward the center of the disc as the song plays, tapping on the disc
 * and rotating it is how you seek" - and "as long as it has the disc art on the 'record'". The
 * geometry is the Turntable board's (the canvas's Turntable.dc.html), in the plinth's own units:
 * the plinth is STAGE, the record turns about its centre, and the arm pivots at ARM and reaches
 * ARM.reach to the needle. The needle rides from the outer groove to the inner one across the song.
 * The component draws every part from these same numbers (as percentages of the stage), so the
 * drawing and the finger's maths can't disagree.
 *
 * - The record turns at 33 1/3 rpm - SECONDS_PER_TURN a turn - while the song plays, and turning it
 *   by hand moves the song by the same, true vinyl speed: a whole turn is 1.8 seconds, backwards
 *   too. The song moves on RELEASE, never on the way (a seek per move would ask for every part of
 *   it) - the drag only turns the record and previews the time. The song PLAYS ON under a finger
 *   (only the record stops), so a turn is an OFFSET from wherever the song is when it lets go,
 *   never a time fixed at the press: a finger that rests a moment, or turns slower than the record
 *   would, would otherwise seek back behind what is playing.
 * - The arm goes anywhere in the song: dragged, the needle's groove says the time. It too seeks
 *   on release. Until the finger has travelled TAP_SLOP_PX it follows the song, and it is taken
 *   hold of where the song is at that moment - so what it shows is always where letting go goes,
 *   and a finger's jitter never seeks.
 * - A press that never travels TAP_SLOP_PX is a tap, which plays or pauses (the component does
 *   that from the click, in the tap); a press that does is a drag, and the click after it is not
 *   a tap.
 * - A cancel seeks nowhere and a drag begun on a song that has since changed is dropped - the
 *   scrubber's rules (lib/scrub.ts).
 * - The preview and the seek are one sum: letting go seeks to exactly the time the arm and the
 *   time line show (shownTime of preview), from the song's position as last drawn.
 */

import { clock } from './scrub'

/** Which Now Playing: the cover and the bar, or the turntable. */
export type Look = 'cover' | 'turntable'

export function otherLook(look: Look): Look {
  return look === 'turntable' ? 'cover' : 'turntable'
}

/** The look button's words: the look it switches TO, as the boards name it. */
export function lookButtonLabel(showing: Look): string {
  return showing === 'turntable' ? 'Show the cover' : 'Show as a turntable'
}

/** One turn of the record, in seconds: 60 seconds over 33 1/3 turns. The CSS spin is the same
 *  (--dw-record-turn in theme.css; the sim holds the two together). */
export const SECONDS_PER_TURN = 1.8

/** A press that travels less than this, in CSS px, is a tap - it plays or pauses, and seeks nothing. */
export const TAP_SLOP_PX = 8

/** Round the spindle, a turn means nothing (the angle swings wildly for a tiny move), so none is
 *  counted inside this share of the record's radius. */
export const SPINDLE_SHARE = 0.12

/* ===== the drawing: the Turntable board's, in the plinth's units ===== */

export const STAGE = { width: 372, height: 368 } as const
/** The mat the record sits on. */
export const PLATTER = { x: 178, y: 182, r: 168 } as const
export const RECORD = { x: 178, y: 182, r: 160 } as const
/** Where the needle rides: the outer groove at the start of the song, the inner at its end. */
export const GROOVES = { outer: 148, inner: 64 } as const
/** The tonearm's pivot, and how far it reaches to the needle. */
export const ARM = { x: 348, y: 32, reach: 205 } as const
/** The arm's parts along it, from the pivot (the board's): the bar, the head at the needle end,
 *  the counterweight behind the pivot, and the pivot's round base. */
export const ARM_PARTS = {
  bar: { thick: 6, radius: 3 },
  head: { from: 193, length: 28, thick: 22, radius: 4 },
  weight: { from: -52, length: 34, thick: 18, radius: 5 },
  /** the base's radius to its outside, and its ring's width */
  base: 22,
  baseEdge: 3,
  /** how far the head lifts off the record while the arm is held */
  lift: 5,
  /** the handle a finger takes the arm by, round the needle */
  handle: 56,
} as const

export interface Point {
  x: number
  y: number
}

/** Where something is on screen: a getBoundingClientRect's four numbers. */
export interface Box {
  left: number
  top: number
  width: number
  height: number
}

const pct = (value: number) => `${+(value * 100).toFixed(4)}%`
const clamp = (value: number, low: number, high: number) => Math.max(low, Math.min(high, value))
const DEG = 180 / Math.PI

/** A circle of the drawing as a box on the stage, in percentages - an inline style's four values. */
export function placeCircle(circle: { x: number; y: number; r: number }) {
  return {
    left: pct((circle.x - circle.r) / STAGE.width),
    top: pct((circle.y - circle.r) / STAGE.height),
    width: pct((2 * circle.r) / STAGE.width),
    height: pct((2 * circle.r) / STAGE.height),
  }
}

/** A point of the drawing on the stage, in percentages. */
export function placePoint(point: Point) {
  return { left: pct(point.x / STAGE.width), top: pct(point.y / STAGE.height) }
}

/** A length of the drawing as a share of the stage's width, in percent (the units are square). */
export function across(length: number): string {
  return pct(length / STAGE.width)
}

/** A point on screen in the stage's own units. */
export function toStage(x: number, y: number, box: Box): Point {
  if (!(box.width > 0) || !(box.height > 0)) return { x: 0, y: 0 }
  return { x: ((x - box.left) / box.width) * STAGE.width, y: ((y - box.top) / box.height) * STAGE.height }
}

/* ===== the arm ===== */

/** How far through the song a time is, 0 to 1 - 0 for a song with no length. */
function share(time: number, length: number): number {
  return length > 0 ? clamp(time / length, 0, 1) : 0
}

/** The groove the needle is in at a time: the outer at the start, the inner at the end. */
export function grooveRadius(time: number, length: number): number {
  return GROOVES.outer - (GROOVES.outer - GROOVES.inner) * share(time, length)
}

/** Where the needle is when it is in a groove of radius r: where a circle of that radius round the
 *  record's centre meets the arm's reach round its pivot (on the side the arm swings over). */
function needleOn(r: number): Point {
  const dx = ARM.x - RECORD.x, dy = ARM.y - RECORD.y
  const d = Math.hypot(dx, dy)
  const ux = dx / d, uy = dy / d
  const a = (r * r - ARM.reach * ARM.reach + d * d) / (2 * d)
  const h = Math.sqrt(Math.max(0, r * r - a * a))
  return { x: RECORD.x + a * ux - h * uy, y: RECORD.y + a * uy + h * ux }
}

export function needleAt(time: number, length: number): Point {
  return needleOn(grooveRadius(time, length))
}

/** The angle, in degrees, of a point seen from the arm's pivot (clockwise from the right, as the
 *  screen's y runs down). */
export function angleFromPivot(point: Point): number {
  return Math.atan2(point.y - ARM.y, point.x - ARM.x) * DEG
}

/** The arm's angle at a time in the song, degrees - what it is drawn rotated by. */
export function armAngle(time: number, length: number): number {
  return angleFromPivot(needleAt(time, length))
}

/** An angle in (-180, 180]. */
function wrapDegrees(angle: number): number {
  const turned = (((angle + 180) % 360) + 360) % 360 - 180
  return turned === -180 ? 180 : turned
}

/**
 * The time the needle is at with the arm at an angle: where its reach lands, and which groove that
 * is. The arm only sweeps the grooves - the outer's angle to the inner's - and an angle outside
 * that is taken to the nearer end, so dragging past either end holds the song at its start or end
 * (and never lands on the circle's far side, where the reach meets the grooves a second time).
 */
export function armTimeAt(angle: number, length: number): number {
  if (!(length > 0)) return 0
  const outer = angleFromPivot(needleOn(GROOVES.outer))
  const span = wrapDegrees(angleFromPivot(needleOn(GROOVES.inner)) - outer)
  let off = wrapDegrees(angle - outer)
  const inside = span >= 0 ? off >= 0 && off <= span : off <= 0 && off >= span
  if (!inside) off = Math.abs(off) <= Math.abs(wrapDegrees(off - span)) ? 0 : span
  const theta = (outer + off) / DEG
  const r = Math.hypot(ARM.x + ARM.reach * Math.cos(theta) - RECORD.x, ARM.y + ARM.reach * Math.sin(theta) - RECORD.y)
  return clamp((GROOVES.outer - r) / (GROOVES.outer - GROOVES.inner), 0, 1) * length
}

/* ===== a finger on the record, or on the arm ===== */

interface Press {
  pointer: number
  /** the song it was put down on */
  track: string
  /** where it went down, and the furthest it has been from there, in CSS px */
  x0: number
  y0: number
  travel: number
}

export interface RecordDrag extends Press {
  kind: 'record'
  /** the finger's last angle round the record's centre, radians - null at the spindle */
  angle: number | null
  /** how far the record has been turned by hand, radians, clockwise */
  turned: number
  /** how far the turn moves the song, seconds - from wherever the song is when it lets go */
  offset: number
}

export interface ArmDrag extends Press {
  kind: 'arm'
  /** the arm's angle less the finger's, taken as it began to move - so it doesn't jump to the
   *  finger. Null until the finger has travelled TAP_SLOP_PX. */
  grab: number | null
  /** the time the needle is over, once the arm has moved - null until then: it follows the song */
  time: number | null
}

export type Drag = RecordDrag | ArmDrag

/** What a drag shows in place of the song's position: the record's turn as an offset from the song
 *  (it plays on), or the time the arm's needle is over (null: the song's, as it hasn't moved yet). */
export type Preview = { how: 'record'; offset: number } | { how: 'arm'; time: number | null }

function travelled(press: Press, x: number, y: number): number {
  return Math.max(press.travel, Math.hypot(x - press.x0, y - press.y0))
}

/** The song's position, within the song. */
function songAt(position: number, length: number): number {
  return length > 0 ? clamp(position, 0, length) : Math.max(0, position || 0)
}

/** The finger's angle round the record's centre, radians - or null inside the spindle's share. */
function recordAngle(x: number, y: number, box: Box): number | null {
  const at = toStage(x, y, box)
  const dx = at.x - RECORD.x, dy = at.y - RECORD.y
  return Math.hypot(dx, dy) < SPINDLE_SHARE * RECORD.r ? null : Math.atan2(dy, dx)
}

export function recordStart(pointer: number, track: string, x: number, y: number, box: Box): RecordDrag {
  return { kind: 'record', pointer, track, x0: x, y0: y, travel: 0, angle: recordAngle(x, y, box), turned: 0, offset: 0 }
}

/**
 * The record's finger moved: the turn since the last move - the short way round, so crossing the
 * left of the record (where the angle jumps from +pi to -pi) is a small turn and not a whole one -
 * turns the record by as much and the song by SECONDS_PER_TURN a turn, forwards clockwise. The
 * offset is kept within the song from where the song is now (`position`): a turn back past the
 * start holds it at 0:00, and turning forward again moves it straight away. Any other pointer
 * changes nothing.
 */
export function recordMove(
  drag: Drag | null, pointer: number, x: number, y: number, box: Box, length: number, position: number,
): Drag | null {
  if (!drag || drag.kind !== 'record' || drag.pointer !== pointer) return drag
  const angle = recordAngle(x, y, box)
  let delta = 0
  if (angle !== null && drag.angle !== null) {
    delta = angle - drag.angle
    if (delta > Math.PI) delta -= 2 * Math.PI
    if (delta < -Math.PI) delta += 2 * Math.PI
  }
  const at = songAt(position, length)
  const offset = length > 0 ? clamp(drag.offset + (delta / (2 * Math.PI)) * SECONDS_PER_TURN, -at, length - at) : drag.offset
  return { ...drag, travel: travelled(drag, x, y), angle, turned: drag.turned + delta, offset }
}

export function armStart(pointer: number, track: string, x: number, y: number): ArmDrag {
  return { kind: 'arm', pointer, track, x0: x, y0: y, travel: 0, grab: null, time: null }
}

/**
 * The arm's finger moved. Inside TAP_SLOP_PX nothing moves - the needle stays over the song as it
 * plays, so a finger's jitter shows nothing it won't go to. The move that takes it past takes hold
 * of the arm: the song where it is then (`position`) is put at the edge of the slop along the
 * finger's way, so the arm moves on from there with no jump, however far that first move went (a
 * quick finger's first move can be tens of px); from there it follows the finger round its pivot,
 * keeping that grab.
 */
export function armMove(
  drag: Drag | null, pointer: number, x: number, y: number, box: Box, length: number, position: number,
): Drag | null {
  if (!drag || drag.kind !== 'arm' || drag.pointer !== pointer) return drag
  const travel = travelled(drag, x, y)
  if (travel < TAP_SLOP_PX) return { ...drag, travel }
  const finger = angleFromPivot(toStage(x, y, box))
  let grab = drag.grab
  if (grab === null) {
    //? first past the slop, so this move is at least TAP_SLOP_PX from the press
    const share = TAP_SLOP_PX / Math.max(TAP_SLOP_PX, Math.hypot(x - drag.x0, y - drag.y0))
    const edge = toStage(drag.x0 + (x - drag.x0) * share, drag.y0 + (y - drag.y0) * share, box)
    grab = armAngle(songAt(position, length), length) - angleFromPivot(edge)
  }
  return { ...drag, travel, grab, time: armTimeAt(finger + grab, length) }
}

/** Whether the press has gone far enough to be a drag rather than a tap. */
export function moved(drag: Drag | null): boolean {
  return !!drag && drag.travel >= TAP_SLOP_PX
}

/**
 * What the drag says in place of the song's position, for the time line and the arm: the record's
 * once it has turned past a tap (before that it may yet be a tap), the arm's from the moment it is
 * held - the needle is up, and over the song until it moves. Null while there is nothing to preview.
 */
export function preview(drag: Drag | null): Preview | null {
  if (!drag) return null
  if (drag.kind === 'record') return moved(drag) ? { how: 'record', offset: drag.offset } : null
  return { how: 'arm', time: drag.time }
}

/** The time the arm and the time line show: the preview's while there is one - the song's position
 *  plus the record's turn, or the arm's needle - the song's otherwise; within the song. */
export function shownTime(previewing: Preview | null, position: number, length: number): number {
  const song = songAt(position, length)
  if (!previewing) return song
  const at = previewing.how === 'record' ? song + previewing.offset : previewing.time ?? song
  return songAt(at, length)
}

/**
 * The drag's pointer came off. Let go ('up') after travelling, it seeks to exactly what it shows -
 * shownTime of its preview, from `position`, the song's position as last drawn - and the click that
 * may follow is not a tap (`wasDrag`). A record turned by nothing (round the spindle, or straight
 * in) has nothing to move and seeks nowhere. Let go without travelling, it seeks nowhere - on the
 * record that is a tap, which the click plays or pauses; on the arm, nothing. Cancelled - the
 * system took the touch - it seeks nowhere.
 */
export function dragEnd(
  drag: Drag | null, pointer: number, how: 'up' | 'cancel', position: number, length: number,
): { drag: Drag | null; seek: number | null; wasDrag: boolean } {
  if (!drag || drag.pointer !== pointer) return { drag, seek: null, wasDrag: false }
  const went = moved(drag)
  if (how !== 'up' || !went || (drag.kind === 'record' && drag.offset === 0)) return { drag: null, seek: null, wasDrag: went }
  return { drag: null, seek: shownTime(preview(drag), position, length), wasDrag: true }
}

/** A drag begun on another song - the song changed under the finger - is let go of, seeking nowhere. */
export function dragFor(drag: Drag | null, track: string): Drag | null {
  return drag && drag.track !== track ? null : drag
}

/** The line under the song's name: "2:31 of 7:05", saying so while the record is turned or the
 *  needle is up - the time then is where letting go will go. */
export function timeLine(time: number, length: number, how: Drag['kind'] | null): string {
  const at = length > 0 ? `${clock(time)} of ${clock(length)}` : clock(time)
  return how === 'arm' ? `Needle up · ${at}` : how === 'record' ? `Scrubbing · ${at}` : at
}

/**
 * Whether the record turns: while the song plays and Now Playing is open, and not while a finger
 * holds it still - and NEVER while the page is hidden (a locked phone), so nothing is drawn frame
 * by frame for nobody. The CSS spin is paused then, where it is; reduced motion stops it in CSS.
 */
export function spinning(state: { playing: boolean; open: boolean; visible: boolean; held: boolean }): boolean {
  return state.playing && state.open && state.visible && !state.held
}

/** The disc the playing song is on, by the album answer it was played from - 1 when that isn't
 *  known (no answer, no disc number: a one-disc album deadwax filed carries none). */
export function playingDisc(songs: { id: string; discNumber?: number }[] | null | undefined, trackId: string): number {
  const disc = songs?.find((song) => song.id === trackId)?.discNumber
  return typeof disc === 'number' && Number.isFinite(disc) && disc >= 1 ? Math.floor(disc) : 1
}

/** Where deadwax serves the record's face for an album's disc (routes/library.py's
 *  /disc_art/navidrome) - null for a song that names no album, which draws the plain record. */
export function discArtPath(albumId: string | null | undefined, disc: number): string | null {
  if (!albumId) return null
  return `/library/disc_art/navidrome?album=${encodeURIComponent(albumId)}&disc=${disc >= 1 ? Math.floor(disc) : 1}`
}
