/**
 * The app's Log page (2.0.0-player.33, app/EventLog.tsx) - its pure rules, pinned by
 * ui/test/settingslog.sim.cjs.
 *
 * deadwax keeps the last 500 lines meant for the page (src/logger.py), numbered from 1 each time it
 * starts and named by the run (`boot`). The page reads that history (GET /interface_logs/recent),
 * then opens the stream from the last number it has, and the stream sends the kept lines after it
 * first; EventSource reconnecting by itself asks from that same number again. So a line can come
 * twice - from the history and the stream, or a reconnect - and is shown once: a line of this run
 * at or below the newest number the page has is dropped (`joinLine`). A line of ANOTHER run
 * (deadwax restarted) starts again from its own numbers. Clear empties the view and keeps the
 * number, so nothing cleared comes back from the history.
 *
 * When the history couldn't be read, the stream is opened from now, and the run's first line heard
 * leaves a GAP below it: the lines of that run deadwax kept from before it, which the page never had.
 * The next history read fills it (`joinHistory`), under the run's lines and above any older run's;
 * without it those lines, all at or below the newest number, would be dropped as "had" for good.
 */

import type { LogLine, RecentLog } from '../api/logs'

/** The most lines the page keeps: the oldest go - as many as deadwax keeps. */
export const LOG_KEPT = 500

export interface LogState {
  /** newest first, as the main page draws its log */
  lines: readonly LogLine[]
  /** the run the newest number is of (null: none heard yet) */
  boot: string | null
  /** the newest number heard of that run: a line at or below it is one the page has had */
  last: number
  /** this run's lines below this number were never had: its first line came with no history of it */
  gap: number | null
  /** the view was emptied by Clear (and nothing has come since): said, not taken for a quiet deadwax */
  cleared: boolean
}

export const emptyLog = (): LogState => ({ lines: [], boot: null, last: 0, gap: null, cleared: false })

/** One line in. A line of the run in hand at or below what the page has had is dropped; another
 *  run's starts again from its own number; a line with no number (an older deadwax) is taken. */
export function joinLine(state: LogState, line: LogLine): LogState {
  const seq = typeof line.seq === 'number' ? line.seq : null
  if (seq === null) return { ...state, cleared: false, lines: [line, ...state.lines].slice(0, LOG_KEPT) }
  const run = line.boot ?? state.boot
  if (run === state.boot && seq <= state.last) return state
  //? a run's first line: whatever of that run came before it the page hasn't had - unless it is the
  //? first line deadwax logged (joinHistory closes the gap a history leaves: it is all there is)
  const gap = run === state.boot ? state.gap : seq > 1 ? seq : null
  return { lines: [line, ...state.lines].slice(0, LOG_KEPT), boot: run, last: seq, gap, cleared: false }
}

/** A gap filled from the history: the run's lines below it, oldest at the bottom, under the run's own
 *  lines (the newest, at the top) and above any older run's. */
function fillGap(state: LogState, recent: RecentLog): LogState {
  const gap = state.gap
  if (gap === null || state.boot !== recent.boot) return state
  const below = recent.lines.filter((line) => typeof line.seq === 'number' && line.seq < gap)
  if (!below.length) return { ...state, gap: null }
  const older = below.map((line) => ({ boot: recent.boot, ...line })).reverse()
  const at = state.lines.findIndex((line) => (line.boot ?? state.boot) !== state.boot)
  const cut = at < 0 ? state.lines.length : at
  return { ...state, gap: null, lines: [...state.lines.slice(0, cut), ...older, ...state.lines.slice(cut)].slice(0, LOG_KEPT) }
}

/** The kept history (oldest first) joined: every line the page hasn't had, in order. */
export function joinHistory(state: LogState, recent: RecentLog): LogState {
  let next = fillGap(state, recent)
  for (const line of recent.lines) next = joinLine(next, { boot: recent.boot, ...line })
  //? lines at or below what the history ends with were all in it: nothing older is new any more, and
  //? nothing older is left to have (a gap a line of the history opened is all deadwax kept) - and a
  //? history of another run (deadwax restarted, nothing logged yet) is that run's from now
  if (next.boot !== recent.boot) return { ...next, boot: recent.boot, last: recent.last, gap: null }
  return { ...next, last: Math.max(next.last, recent.last), gap: null }
}

/** Clear: the view emptied, the number kept - nothing cleared comes back from the history, nor
 *  anything older it never had. */
export const clearLog = (state: LogState): LogState => ({ ...state, lines: [], gap: null, cleared: true })

/** What an empty log says: nothing yet, or emptied by Clear (lines were logged; deadwax still has them). */
export const EMPTY_WORDS = {
  never: 'Nothing logged yet.',
  cleared: 'Cleared. New lines show here as deadwax logs them.',
} as const

/** How a line's level is drawn: errors red, warnings amber, the rest plain. */
export function levelOf(type: string): 'error' | 'warning' | 'info' {
  const upper = type.toUpperCase()
  if (upper === 'ERROR' || upper === 'CRITICAL') return 'error'
  if (upper === 'WARNING' || upper === 'WARN') return 'warning'
  return 'info'
}

/** The time a line was logged, as the main page draws it: HH:MM:SS, this device's clock. */
export function lineTime(line: LogLine): string {
  if (typeof line.time !== 'number' || !Number.isFinite(line.time)) return ''
  return new Date(line.time * 1000).toTimeString().slice(0, 8)
}

/** Where the stream stands, said in one line above the log - never a line of the log itself. */
export type StreamState = 'connecting' | 'live' | 'lost'

/** How long after the browser gives up on the stream for good (an answer that wasn't the stream - a
 *  reverse proxy's 502 while deadwax restarts) the page asks again by hand, the history first. After a
 *  network error EventSource tries again by itself and this isn't needed. */
export const STREAM_RETRY_MS = 5000

export const STREAM_WORDS: Readonly<Record<StreamState, string>> = {
  connecting: 'Connecting…',
  live: 'Live',
  lost: 'The stream was lost - trying again',
}

/** What the page says on a phone, before its link to the main page. */
export const LOG_PHONE = 'The log needs a wider screen for now - or'
