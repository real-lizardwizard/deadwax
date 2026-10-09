/**
 * Keeping the visualizer's silent copy in time with the song (2.0.0-player.20). PURE: what the
 * player's element is doing goes in, what to do with the analysed copy comes out - player/vizAudio.ts
 * does it, ui/test/vizsync.sim.cjs drives it.
 *
 * THE PLAYER'S AUDIO ELEMENT IS NEVER CONNECTED TO WEB AUDIO. A createMediaElementSource reroutes the
 * song through Web Audio and breaks locked playback on an iPhone, and James's rule is audio fidelity
 * first - so what the visualizer sees is a SEPARATE, silent copy of the stretch playing: the
 * turntable's FLAC window from deadwax (GET /deadwax/navidrome/scrub/{id}, player/api.ts scrubWindow),
 * decoded, played through an AnalyserNode into a gain of 0. It is started where the element is, paused
 * with it, started again where a seek put it, and re-synced if it drifts further than DRIFT_S; the next
 * window is asked for before this one runs out (AHEAD_S), one at a time.
 *
 * The rules, for one look (each animation frame):
 *  - Nothing playing, no Web Audio, not a FLAC, or this song's windows refused (415, or a window the
 *    browser couldn't decode): the copy stops, nothing is asked for this song (each song's refusals
 *    and failures are its own), and the screen says the song can't be seen - the effects run from a
 *    calm idle signal. An audio context not yet running (its resume on
 *    the way, the page hidden): the copy stops and nothing is asked, and nothing is said.
 *  - The element paused or buffering: the copy stops with it, and nothing is asked.
 *  - Playing: a window covering the playhead and AHEAD_S after it (less near the song's end) is asked
 *    for when there isn't one, unless one is on its way that will, or the last ask failed under
 *    RETRY_MS ago; a refresh ahead must start further on than the window it replaces (so a short window
 *    - a hi-res song deadwax cut short - never loops on itself), its margins shrinking with it.
 *  - Playing, inside the window: the copy is started at the playhead - when none is running, it is
 *    another song's or another window's (a fresh one just decoded), or it has drifted more than DRIFT_S
 *    from the element (a seek, a stall) - else left alone. Outside the window: stopped until one is.
 *  - THE NEXT SONG'S FIRST WINDOW is asked for in this one's last VIZ_AHEAD_S (`prefetch`), when this
 *    song needs nothing and nothing is on its way - so at a song change, a gapless album's above all,
 *    the copy carries straight on instead of standing still while a window is fetched. Not for a next
 *    song that isn't a FLAC, is refused, failed under VIZ_RETRY_MS ago, or is already in hand
 *    (`ahead`; player/vizAudio.ts takes it up as the song changes - takeAhead below). Asked even while
 *    this song can't be seen itself (not a FLAC, refused): the next may be.
 *  - THE PLAYER'S SPEED (2.0.0-player.39): the copy plays at it - its AudioBufferSourceNode's
 *    playbackRate - so it keeps the element's pace and the drift rule never has a speed to re-sync it
 *    for; where it has got to is `copyAt` of its anchor, at that rate, re-anchored where the speed
 *    changes (`reanchor`). What it shows follows - a song at 2x reads twice the tempo, which is right.
 */

/** How much of the song a window holds, how far before the playhead it starts and on what grid -
 *  the turntable's WINDOW_S and grid, with a shorter back margin: nothing here goes backwards. */
export const VIZ_WINDOW_S = 40
export const VIZ_BACK_S = 2
export const VIZ_GRID_S = 2
/** The next window is asked for once the playhead is this close to the end of the one held, s. */
export const VIZ_AHEAD_S = 6
/** The copy is started again where the element is once they are this far apart, s. */
export const DRIFT_S = 0.25
/** A window that couldn't be had is asked again after this long, ms. */
export const VIZ_RETRY_MS = 10_000
/** The copy isn't started this close to its window's end, s - there's nothing left to see. */
export const END_GUARD_S = 0.1

export interface SyncSong {
  id: string
  /** seconds; 0 when not known */
  length: number
  flac: boolean
  /** the cap the player asks for this song at (48000 for a hi-res song under "Up to 48 kHz"), so the
   *  window is cut from the very copy it plays - as the turntable asks */
  maxRate: number | null
}

/** A window decoded and in hand: which song, where in it (s), and which window it is. */
export interface HeldWindow {
  song: string
  start: number
  end: number
  key: number
}

/** A song whose windows can't be had at all, and why. */
export interface Refusal {
  song: string
  why: string
}

/** A song whose last ask failed: not asked again until `until`. */
export interface Failure {
  song: string
  why: string
  until: number
}

export interface SyncInput {
  song: SyncSong | null
  /** the song after it in the queue (lib/playQueue nextIndex), whose first window is asked for ahead */
  following: SyncSong | null
  /** the element plays - and isn't stalled buffering */
  running: boolean
  /** the element's position, s */
  position: number
  /** a clock for the retry, ms */
  now: number
  /** the audio context: none (no Web Audio, or it couldn't be made), there but not yet running (a
   *  resume on its way, or the page hidden), or running - to decode with and play on */
  audio: 'none' | 'starting' | 'running'
  held: HeldWindow | null
  /** the next song's first window, fetched ahead and in hand */
  ahead: HeldWindow | null
  /** a window on its way - fetched or being decoded - and the stretch it will cover */
  pending: { song: string; from: number; to: number } | null
  /** the analysed copy running: its song, its window, and where it has got to, s */
  source: { song: string; key: number; at: number } | null
  /** the songs whose windows can't be had at all, and why - each song its own */
  refused: readonly Refusal[]
  /** the songs whose last ask failed - each song its own */
  failed: readonly Failure[]
  /** how long this song's windows come back: shorter than VIZ_WINDOW_S for a hi-res one */
  span: { song: string; seconds: number } | null
}

export type Seeing = 'nothing' | 'seen' | 'waiting' | 'paused' | 'unseen'

/** Where the copy was started (or last re-anchored): its place in the song, the audio context's time
 *  then, and the rate it plays at (2.0.0-player.39 - the player's speed). */
export interface CopyAnchor {
  at: number
  time: number
  rate: number
}

/** Where the copy has got to at context time `now`: from its anchor, at its rate. */
export function copyAt(anchor: CopyAnchor, now: number): number {
  return anchor.at + anchor.rate * (now - anchor.time)
}

/** The anchor moved to `now` at a new rate - where it has got to, from here at `rate` - so a change of
 *  speed never jumps it. */
export function reanchor(anchor: CopyAnchor, now: number, rate: number): CopyAnchor {
  return { at: copyAt(anchor, now), time: now, rate }
}

export interface SyncPlan {
  /** stop the copy running (it is wrong, or not wanted) */
  stop: boolean
  /** start it at this song position (in the held window), stopping any other first */
  start: number | null
  /** ask for a window from here, s */
  fetch: number | null
  /** ask for the NEXT song's window from here, s (its first, so 0) */
  prefetch: number | null
  seeing: Seeing
  /** why the song can't be seen - one plain line for the screen */
  why: string | null
}

/** The back and ahead margins for windows of `span` seconds: whole for a whole window, in proportion
 *  for one cut short - so each new window still moves on by most of its length. */
export function vizMargins(span: number): { back: number; ahead: number } {
  const scale = Math.max(0, Math.min(1, span / VIZ_WINDOW_S))
  return { back: VIZ_BACK_S * scale, ahead: VIZ_AHEAD_S * scale }
}

/** Where a window asked for to cover `position` starts: `back` before it, on the grid, never below 0. */
export function windowFrom(position: number, back: number): number {
  return Math.max(0, Math.floor((position - back) / VIZ_GRID_S) * VIZ_GRID_S)
}

/**
 * The next song's first window, held ahead, taken up as that song starts playing: it becomes the
 * window held. Anything held for a song that is neither playing nor next (a skip passed it by) is let go.
 */
export function takeAhead<W extends HeldWindow>(held: W | null, ahead: W | null, song: string | null, following: string | null): { held: W | null; ahead: W | null } {
  if (ahead && song !== null && ahead.song === song && held?.song !== song) return { held: ahead, ahead: null }
  if (ahead && ahead.song !== song && ahead.song !== following) return { held, ahead: null }
  return { held, ahead }
}

/** Whether the next song's first window is to be asked for now: this song's last VIZ_AHEAD_S, its
 *  length known, nothing on its way, and the next song one that can be seen and isn't in hand. */
function wantsNext(input: SyncInput, song: SyncSong): boolean {
  const after = input.following
  if (!after || !after.flac || after.id === song.id || !input.running || input.pending) return false
  if (!(song.length > 0) || input.position < song.length - VIZ_AHEAD_S) return false
  if (input.ahead?.song === after.id) return false
  if (input.refused.some((r) => r.song === after.id)) return false
  return !input.failed.some((f) => f.song === after.id && input.now < f.until)
}

export function planSync(input: SyncInput): SyncPlan {
  const { song, held, source } = input
  const quiet = (seeing: Seeing, why: string | null, prefetch: number | null = null): SyncPlan =>
    ({ stop: source !== null, start: null, fetch: null, prefetch, seeing, why })
  if (!song) return quiet('nothing', null)
  if (input.audio === 'none') return quiet('unseen', "This browser can't analyse sound, so the song can't be seen.")
  if (input.audio === 'starting') return quiet('waiting', null)
  //? this song can't be seen - but the next may be, and is asked for ahead all the same
  if (!song.flac) return quiet('unseen', "This song can't be seen - it isn't a FLAC file.", wantsNext(input, song) ? 0 : null)
  const refusal = input.refused.find((r) => r.song === song.id)
  if (refusal) return quiet('unseen', `This song can't be seen - ${refusal.why}.`, wantsNext(input, song) ? 0 : null)
  if (!input.running) return quiet('paused', null)

  const position = input.position
  const mine = held && held.song === song.id ? held : null
  const covers = (x: number, need: number) => !!mine && x >= mine.start && x + Math.max(0, need) <= mine.end

  //? the window: asked for when the one held won't cover the playhead and what comes next
  const span = input.span?.song === song.id ? input.span.seconds : VIZ_WINDOW_S
  const { back, ahead } = vizMargins(span)
  const room = song.length > 0 ? Math.max(0, song.length - position - 0.5) : Infinity
  const need = Math.min(ahead, room)
  let fetch: number | null = null
  const failure = input.failed.find((f) => f.song === song.id && input.now < f.until) ?? null
  const pending = input.pending?.song === song.id ? input.pending : null
  const coming = !!pending && position >= pending.from && position + need <= pending.to
  if (!covers(position, need) && !coming && !failure) {
    const from = windowFrom(position, back)
    //? a refresh ahead of a playhead the window still covers must move on from it
    if (!(covers(position, 0) && mine && from <= mine.start)) fetch = from
  }
  //? the next song's first window, once this one needs nothing more
  const prefetch = fetch === null && wantsNext(input, song) ? 0 : null

  //? the copy: started at the playhead when it isn't running right, stopped outside the window
  let stop = false
  let start: number | null = null
  if (covers(position, END_GUARD_S)) {
    const right = !!source && source.song === song.id && source.key === mine!.key && Math.abs(source.at - position) <= DRIFT_S
    if (!right) start = position
  } else if (source) {
    stop = true
  }

  const running = start !== null || (source !== null && !stop)
  const seeing: Seeing = running ? 'seen' : failure && !pending ? 'unseen' : 'waiting'
  const why = seeing === 'unseen' ? `This song can't be seen just now - ${failure!.why}.` : null
  return { stop, start, fetch, prefetch, seeing, why }
}
