/**
 * The now-playing screen's scrubber: where on the bar is what time, what a finger or a key does,
 * which position the bar shows, and the readout of where the last seek landed.
 *
 * It replaced a native <input type=range>, which on an iPhone moves only when dragged BY ITS THUMB
 * - a tap on the bar does nothing, and a drag that starts beside the thumb does nothing - so a
 * seek often didn't happen where the finger went. This one is the whole bar: a tap seeks there, a
 * drag follows the finger and seeks where it lets go.
 *
 * The readout is for the other half of "it doesn't seek where I put it", which is Safari's: asked
 * to seek in a FLAC whose bit rate changes through the song, AVFoundation lands seconds - on a
 * worst case, minutes - from the time asked, and its clock says the time asked all the same (see
 * "Seeking" in CLAUDE.md's phone-player section). The clock can't show that, but the song's END
 * can: the audio then runs out before the clock reaches the song's length, or plays on after the
 * clock has stopped at it, by exactly how far the seek was off. seekStep() watches for that.
 *
 * Pure, like the rest of lib/, so ui/test/scrub.sim.cjs can hold it to the answers.
 */

/** "3:07" - and "0:00" for nothing, which a clock should say where a track list says nothing. */
export function clock(seconds: number): string {
  const whole = Math.max(0, Math.floor(seconds || 0))
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`
}

/** Arrow keys move this far, in seconds - as VoiceOver's swipe up and down do, which WebKit sends as arrows. */
export const KEY_STEP_S = 5

/** Page Up and Page Down move this far, in seconds. */
export const PAGE_STEP_S = 30

/**
 * How long the bar goes on showing a seek's target while the element hasn't said it has landed, in
 * ms. A seek over a slow connection into a part of the song not yet downloaded can take several
 * seconds (8 s measured at 150 KB/s); one that never lands - a song that failed under it - must
 * not hold the bar still for good.
 */
export const PENDING_MAX_MS = 20_000

/** The clock this close to the song's length counts as having reached its end, in seconds. */
export const END_SLACK_S = 0.35

/** A seek's end judged less than this far off is taken to have landed where asked, in seconds. */
export const LANDED_WITHIN_S = 1.5

const clamp = (seconds: number, length: number) => Math.max(0, Math.min(seconds, length))

/**
 * The time at a point on the bar: how far across it the point is, as a share of the song. The
 * ends of the bar are the start and the end of the song, and a finger past either end is at it.
 */
export function timeAt(x: number, left: number, width: number, length: number): number {
  if (!(length > 0) || !(width > 0)) return 0
  return clamp(((x - left) / width) * length, length)
}

/** Where a key on the focused bar asks to go, or null for a key that isn't the bar's. */
export function keyTarget(key: string, from: number, length: number): number | null {
  if (!(length > 0)) return null
  const at = clamp(from, length)
  switch (key) {
    case 'ArrowRight':
    case 'ArrowUp':
      return clamp(at + KEY_STEP_S, length)
    case 'ArrowLeft':
    case 'ArrowDown':
      return clamp(at - KEY_STEP_S, length)
    case 'PageUp':
      return clamp(at + PAGE_STEP_S, length)
    case 'PageDown':
      return clamp(at - PAGE_STEP_S, length)
    case 'Home':
      return 0
    case 'End':
      return length
    default:
      return null
  }
}

/** A finger (or the mouse) on the bar: which pointer, which song it was put down on, and where it is. */
export interface Drag {
  pointer: number
  track: string
  time: number
}

export function dragStart(pointer: number, track: string, time: number): Drag {
  return { pointer, track, time }
}

/** The drag's pointer moved; any other pointer - a second finger - changes nothing. */
export function dragMove(drag: Drag | null, pointer: number, time: number): Drag | null {
  if (!drag || drag.pointer !== pointer) return drag
  return drag.time === time ? drag : { ...drag, time }
}

/**
 * The drag's pointer came off the bar. Let go ('up'), it seeks to where it was. Cancelled - the
 * system took the touch, or the pointer went away - it seeks nowhere: that isn't "let go here",
 * and the bar goes back to the song's own position rather than staying stuck where the finger was.
 */
export function dragEnd(drag: Drag | null, pointer: number, how: 'up' | 'cancel'): { drag: Drag | null; seek: number | null } {
  if (!drag || drag.pointer !== pointer) return { drag, seek: null }
  return { drag: null, seek: how === 'up' ? drag.time : null }
}

/** A drag begun on another song - the song changed under the finger - is let go of, seeking nowhere. */
export function dragFor(drag: Drag | null, track: string): Drag | null {
  return drag && drag.track !== track ? null : drag
}

/** What the bar and the clocks show: where the finger is while there is one, the song's position otherwise. */
export function shownTime(drag: Drag | null, position: number, length: number): number {
  const at = drag ? drag.time : position
  return length > 0 ? clamp(at, length) : Math.max(0, at || 0)
}

/** A seek on its way: its target, and when it was asked for (performance clock, ms). */
export interface PendingSeek {
  target: number
  since: number
}

/**
 * The position to tell the bar: a seek's target from the moment it is asked for until the element
 * says it has landed ('seeked' - the player clears `pending` then), so the thumb never goes back
 * to where the song was while the seek is on its way, and no update from before it can move it.
 */
export function reportedPosition(pending: PendingSeek | null, position: number, now: number): number {
  return pending && now - pending.since < PENDING_MAX_MS ? pending.target : position
}

/**
 * The last seek the listener made - from the bar or the lock screen - for the readout: what was
 * asked, what the element's clock said once it had landed, and, if the song then played to its
 * end with no other seek, how far off that end says the seek really was.
 */
export interface SeekReading {
  asked: number
  /** the song's length when the seek was asked for - what its end is judged against */
  length: number
  track: string
  /** the element's clock at 'seeked'; null until then */
  said: number | null
  /** still the latest seek in a song still playing, so its end can speak for it */
  judging: boolean
  /** when the clock first reached the song's end (performance ms), and what it read then */
  clockEnd: { at: number; position: number } | null
  /** seconds: + it really landed later in the song than asked, - earlier, 0 where asked; null unjudged */
  off: number | null
}

export type SeekEvent =
  | { kind: 'asked'; asked: number; length: number; track: string }
  | { kind: 'seeked'; position: number }
  /** a seek the listener didn't make with the bar - "previous" restarting, a failed song resumed */
  | { kind: 'other seek' }
  | { kind: 'song change' }
  /** paused, other than by the song ending: the wall clock is no measure of the end after that */
  | { kind: 'paused' }
  | { kind: 'clock'; position: number; at: number }
  | { kind: 'ended'; position: number; at: number; rate: number }

/**
 * The reading after an event, the same object when nothing changed.
 *
 * Judging the end (`ended`): the clock SHORT of the length when the song ended means the audio ran
 * out first - it was ahead of the clock, so the seek landed later than asked, by that much. (WebKit
 * then takes the clock as the song's length, and 'ended' carries it.) The song PLAYING ON after the
 * clock reached the end means the audio was behind - landed earlier - by how long it played on;
 * WebKit holds its clock at the length meanwhile (MediaPlayerPrivateAVFoundationObjC::currentTime
 * clamps it), so that is measured on the wall clock, from the first update that saw the end. In a
 * browser that lands where asked neither happens, and the reading says so.
 */
export function seekStep(reading: SeekReading | null, event: SeekEvent): SeekReading | null {
  if (event.kind === 'asked') {
    return { asked: event.asked, length: event.length, track: event.track, said: null, judging: event.length > 0, clockEnd: null, off: null }
  }
  if (!reading) return reading
  switch (event.kind) {
    case 'seeked':
      return reading.said === null ? { ...reading, said: event.position } : reading
    case 'other seek':
    case 'song change':
    case 'paused':
      return reading.judging ? { ...reading, judging: false } : reading
    case 'clock':
      if (!reading.judging || reading.said === null || reading.clockEnd) return reading
      return event.position >= reading.length - END_SLACK_S ? { ...reading, clockEnd: { at: event.at, position: event.position } } : reading
    case 'ended': {
      if (!reading.judging || reading.said === null) return reading
      const short = Math.max(0, reading.length - event.position)
      //? played on: the wall time since the clock reached the end, less what the clock still had to go then
      const on = reading.clockEnd
        ? Math.max(0, ((event.at - reading.clockEnd.at) / 1000) * (event.rate || 1) - (reading.length - reading.clockEnd.position))
        : 0
      //? to a tenth: the updates it comes from are a quarter of a second apart anyway
      const off = Math.round((short - on) * 10) / 10
      return { ...reading, judging: false, off: Math.abs(off) < LANDED_WITHIN_S ? 0 : off }
    }
  }
}

/**
 * The readout's line for the last seek. It is there before the first seek too, so the line doesn't
 * appear under the first one and move the controls up the screen under the finger.
 */
export function describeSeek(reading: SeekReading | null): string {
  if (!reading) return 'No seek yet'
  const asked = `Last seek: asked ${clock(reading.asked)}`
  if (reading.said === null) return `${asked}, seeking…`
  const said = `${asked}, the player said ${clock(reading.said)}`
  if (reading.off === null) return said
  if (reading.off === 0) return `${said} · the song ended on time, so it landed there`
  const by = Math.round(Math.abs(reading.off))
  const really = clock(Math.round(reading.asked + reading.off))
  return reading.off > 0
    ? `${said} · the song ran out ${by} s before its clock did, so it really landed at about ${really}`
    : `${said} · the song played on ${by} s after its clock ended, so it really landed at about ${really}`
}
