/**
 * "Turn it for me" (2.0.0-player.36): a motion of lab/motions.ts handed to the deck through the very
 * methods a press drives - pressed, the take, a hand sample at a time, the release - as Turntable calls
 * them, and the release's answer done as Turntable's own release does it (seek, then play when there is
 * no coast to wait for) - with the player as it is AT the release, as Turntable reads it from the render
 * the release comes in: the bench's player is a new object each time it starts or stops (the take pauses
 * a playing song), and one kept from the motion's start says it is still playing, so the song was never
 * played again (review of 2.0.0-player.36). Each sample goes to the deck once the page's clock has passed its own time,
 * stamped with that time exactly (an event's timeStamp is always a moment before its handler runs);
 * a page that fell behind hands over every sample that came due together, as coalesced events come.
 */

import type { Deck } from '../player/deck'
import type { TurntablePlayer } from '../player/Turntable'
import { motionSamples, type Motion, type MotionSample } from './motions'

/** The release comes this long after the motion's last sample, ms - as a finger lifts the frame after. */
export const RELEASE_AFTER_MS = 8

export interface MotionResult {
  /** page ms the record was taken, and let go */
  from: number
  released: number
  /** where the song was taken */
  anchor: number
  samples: MotionSample[]
  /** what the release asked for */
  seek: number | null
  play: boolean
  /** stopped before its end */
  stopped: boolean
}

export interface MotionRun {
  stop(): void
  done: Promise<MotionResult>
}

const now = () => performance.now()

/** What the runner reads of the player. */
export type RunnerPlayer = Pick<TurntablePlayer, 'duration' | 'playing' | 'seek' | 'toggle'>

/**
 * Run `motion` on `deck` now. `player` gives the player as it is now - asked again at the release.
 * `onTurn` hears how far the hand has turned the record (radians), sample by sample - for the face, which
 * the deck holds still under a hand (Turntable turns it there). The deck must be able to take the press
 * (`live()`), as Turntable asks before a press is the deck's.
 */
export function runMotion(
  deck: Deck, player: () => RunnerPlayer, motion: Motion,
  options: { random?: (() => number) | null; onTurn?: (turned: number) => void } = {},
): MotionRun {
  const from = now()
  const samples = motionSamples(motion, from, options.random ?? null)
  const length = player().duration || 0
  deck.pressed(from)
  const anchor = deck.takeOver(from)
  let next = 1
  let timer: ReturnType<typeof setTimeout> | undefined
  let finished = false
  let settle: (result: MotionResult) => void = () => undefined
  const done = new Promise<MotionResult>((resolve) => { settle = resolve })

  const release = (time: number, stopped: boolean) => {
    if (finished) return
    finished = true
    clearTimeout(timer)
    const { seek, play } = deck.release(time, 'up')
    //? as Turntable's own release: sought now, while it coasts there - and played at once when there is
    //? no coast to wait for; the player as it is now, which the take may have paused
    const current = player()
    if (seek !== null && length) current.seek(seek)
    if (play && !current.playing) current.toggle()
    settle({ from, released: time, anchor, samples: samples.slice(0, next), seek, play, stopped })
  }

  const deliver = () => {
    if (finished) return
    const at = now()
    while (next < samples.length && samples[next]!.time <= at) {
      const sample = samples[next++]!
      deck.hand(sample.time, sample.turned, Math.max(0, Math.min(length || Infinity, anchor + sample.moved)))
      options.onTurn?.(sample.turned)
    }
    if (next < samples.length) {
      timer = setTimeout(deliver, Math.max(1, samples[next]!.time - now() + 0.5))
      return
    }
    const lift = samples[samples.length - 1]!.time + RELEASE_AFTER_MS
    const wait = lift - now()
    if (wait > 0) timer = setTimeout(() => release(lift, false), wait + 0.5)
    else release(lift, false)
  }
  timer = setTimeout(deliver, Math.max(1, (samples[1]?.time ?? from) - now() + 0.5))

  return {
    stop: () => release(Math.max(now(), samples[next - 1]!.time + 1), true),
    done,
  }
}
