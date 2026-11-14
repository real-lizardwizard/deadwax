/**
 * Play history that lasts (2.1.15) - James, 2026-11-13: "I'd like it if the play history was persistent, so you can
 * always look back and see what you played yesterday." In Up Next, Apple Music's way: scrolled up past the song
 * playing, ONE CONTINUOUS LIST of everything played, newest nearest - no headings at all (no days, and no separate
 * one for the queue's own History), no times on rows, skips drawn like plays. Kept by deadwax per person
 * (src/routes/play_history.py, /deadwax/me/history), so the web's plays and the iPhone's show on both.
 * notes/play-history.md.
 *
 * A START is one song begun: the moment the engine tells Navidrome "now playing" (usePlayer's beginListen - a
 * listen's first sound, never a resume, a seek or a wait), dated by the listen's own `startedAt`, the very `time` its
 * counted scrobble carries. It is recorded with the song as the queue holds it - so a row reads, and plays again, with
 * nothing fetched - and with the queue's id and its entry's key, which is how each start is drawn exactly ONCE:
 *
 *   - while the queue still draws its entry - History (2.1.3: what Previous walks, the songs a tap passed included),
 *     the song playing, or a row still to play - it is the QUEUE's row;
 *   - (2.1.18) while one of the entries the queue's rows stand for holds it as a row brought back from the play
 *     history (a tap on an older row rolled the queue back to it: lib/upNext.ts broughtBack, Mark.starts, heldStarts),
 *     or its entry is ahead of the song playing up to the end of the furthest unit played (a roll-back or Previous moved
 *     it back down: `reached`, even past the list's limit), it is the queue's too - moved down into Up Next, never drawn
 *     above as history; it comes back into history as it plays again, a new start;
 *   - once its entry has fallen past History's 50, or isn't drawn ahead (a later time round, or past the list's first
 *     100 rows, Previous never having gone back across it), or the queue is another (an album tapped, a queue put back
 *     from another app), it is one of the older rows ABOVE History, in the order they were begun.
 *
 * Above History the older rows run oldest first, so the list read upwards from the song playing goes back in time
 * without a seam; a run of starts of one song (a restart, an hour of Repeat One) is one row, as History's unit is.
 *
 * Pure: nothing here fetches, touches the page or imports Preact (app-rules.sim.cjs holds that) - history.sim.cjs
 * holds every rule.
 */

import { current, type QueueTrack } from './playQueue'
import { bare } from './resume'
import { UP_NEXT_DRAWN, heldStarts, shownKeys, type UpNextQueue } from './upNext'

/** One start, as deadwax keeps it - GET /deadwax/me/history's `plays`, and what POST takes. */
export interface Played {
  /** when the listen began, ms since the epoch, by the device's clock - the counted scrobble's `time` */
  at: number
  /** whether it crossed the rule and counted as a play - kept, not drawn (skips are drawn like plays) */
  counted: boolean
  /** the queue it was begun in (UpNextState.id) and its entry's key there - how the queue's own rows are told */
  queue: string | null
  entry: number | null
  /** the song as the queue holds it, without its level (lib/resume.ts bare()) */
  song: QueueTrack
}

/** A page of them, newest first: `next` the last one's own moment and song, to ask for the page before it with. */
export interface HistoryPage {
  plays: Played[]
  next: { at: number; id: string } | null
  /** logins off: one history for everyone on this deadwax */
  shared: boolean
}

/** One older row of Up Next's list: the first start of a run of one song - its key - and the song; (2.1.18) the moments
 *  of every start of the run, oldest first, and the entry of the queue playing its first start was begun in, when it
 *  was - what a tap on it brings back (lib/upNext.ts Brought). */
export interface PastRow {
  key: string
  track: QueueTrack
  starts: number[]
  entry: number | null
}

/** The plays a page asks for - src/play_history.py HISTORY_PAGE. */
export const HISTORY_PAGE = 100
/** The starts one POST sends at most - HISTORY_POST_MAX. */
export const HISTORY_POST_MAX = 500
/** The starts this page keeps of its own, sent or not - drawn until a page of deadwax's holds them. */
export const OWN_KEPT = 500
/** How near the top of Up Next's scroller, in scroller heights, the next older page is asked for. */
export const LOAD_WITHIN = 1

/** A start's key: its moment and its song - deadwax's own (user, started_at, song_id), within one person. */
export const playedKey = (played: Pick<Played, 'at' | 'song'>): string => `${played.at}:${played.song.id}`

/** The start of the song playing in `queue`, begun at `at` (the listen's `startedAt`) - the song as the queue holds it,
 *  without its level (lib/resume.ts bare()), its queue's id and its entry's key with it. */
export function startOf(track: QueueTrack, at: number, queue: UpNextQueue): Played {
  const entry = queue.upNext?.marks[queue.index]?.key
  return { at, counted: false, queue: queue.upNext?.id ?? null, entry: entry ?? null, song: bare(track) }
}

/** The entries of `queue` whose starts its own rows draw - its id, and lib/upNext.ts shownKeys(): History's, the song
 *  playing's, the songs added and the list's rows drawn (its first `limit`) - never a later time round or a row past
 *  the limit, whose starts are older rows above. None with nothing playing. */
export interface QueueShows {
  id: string | null
  keys: ReadonlySet<number>
  /** (2.1.18) the starts (playedKey) the queue holds as rows brought back from the play history - lib/upNext.ts
   *  heldStarts: of the entries its rows stand for (`keys`), whatever queue they were begun in */
  held: ReadonlySet<string>
}

export function queueShows(queue: UpNextQueue, limit: number = UP_NEXT_DRAWN): QueueShows {
  const state = queue.upNext
  if (!state?.id || !current(queue)) return { id: null, keys: new Set(), held: new Set() }
  return { id: state.id, keys: shownKeys(queue, limit), held: new Set(heldStarts(queue, limit).map(({ id, at }) => `${at}:${id}`)) }
}

/** Whether `played` is one of the queue's own rows - begun in this queue, its entry one the queue's rows stand for.
 *  Such a start is drawn there, never again above. */
export function shownByQueue(played: Pick<Played, 'queue' | 'entry'>, shows: QueueShows): boolean {
  return shows.id !== null && played.queue === shows.id && played.entry !== null && shows.keys.has(played.entry)
}

/** (2.1.18) Whether the queue holds `played`: one of its own rows (shownByQueue), or a row brought back from the play
 *  history that it holds (QueueShows.held) - moved down into Up Next. Either way never an older row above. */
export function heldByQueue(played: Pick<Played, 'queue' | 'entry' | 'at' | 'song'>, shows: QueueShows): boolean {
  return shownByQueue(played, shows) || shows.held.has(playedKey(played))
}

/** deadwax's pages and this page's own starts as one list, newest first, each start once - `counted` ORed, since a
 *  page may hold a start this page has since seen count. */
export function merged(pages: readonly Played[], own: readonly Played[]): Played[] {
  const byKey = new Map<string, Played>()
  for (const played of [...pages, ...own]) {
    const key = playedKey(played)
    const held = byKey.get(key)
    byKey.set(key, held ? { ...held, counted: held.counted || played.counted } : played)
  }
  return [...byKey.values()].sort((a, b) => b.at - a.at || (a.song.id < b.song.id ? 1 : a.song.id > b.song.id ? -1 : 0))
}

/** The older rows above History, oldest first: every start (newest first, as `merged` gives them) the queue doesn't
 *  hold itself (`limit` the list's rows Up Next draws - upNextView's; heldByQueue), a run of starts of one song one row -
 *  keyed by the run's first start, with every start's moment (2.1.18). */
export function pastRows(plays: readonly Played[], queue: UpNextQueue, limit: number = UP_NEXT_DRAWN): PastRow[] {
  const shows = queueShows(queue, limit)
  const rows: PastRow[] = []
  let last: string | null = null
  for (let at = plays.length - 1; at >= 0; at--) {
    const played = plays[at]!
    if (heldByQueue(played, shows)) continue
    if (played.song.id === last) {
      rows[rows.length - 1]!.starts.push(played.at)
      continue
    }
    last = played.song.id
    rows.push({ key: playedKey(played), track: played.song, starts: [played.at], entry: shows.id !== null && played.queue === shows.id ? played.entry : null })
  }
  return rows
}

/** (2.1.18) An older row's tap: the rows from it (by its key) down to History's, oldest first - what comes back into the
 *  queue, the tapped one first (lib/upNext.ts broughtBack). None for a key not among them. */
export function rowsFrom(rows: readonly PastRow[], key: string): PastRow[] {
  const at = rows.findIndex((row) => row.key === key)
  return at < 0 ? [] : rows.slice(at)
}

/** Where a page ends: its last play's moment and song - GET's `next`, the page before it asked for by it. */
export type Cursor = NonNullable<HistoryPage['next']>

/** What app/usePlayHistory.ts holds of deadwax's pages: every play they brought, newest first, each once; the cursor of
 *  the page before the oldest (`before` - null: there is none, or nothing asked yet); and whether a page has come. */
export interface Held {
  plays: Played[]
  before: Cursor | null
  asked: boolean
}

export const NOTHING_HELD: Held = { plays: [], before: null, asked: false }

/** Whether `a` comes after `b` in deadwax's order - its moment, then its song id (the page's ORDER BY). */
const after = (a: Played, b: Played): boolean => a.at > b.at || (a.at === b.at && a.song.id > b.song.id)

/** The newest page come (Up Next opened, or the page shown again): joined to what is held - the older pages kept, and
 *  where to ask from for them - unless it doesn't reach back to the newest held (more played elsewhere since than a
 *  page holds), when it starts again from it, the plays between never left out. */
export function withNewest(held: Held, page: HistoryPage): Held {
  const oldest = page.plays[page.plays.length - 1]
  const newestHeld = held.plays[0]
  //? nothing held yet - not asked, or an empty page came first (a first open after upgrading, a panel left open while
  //? the phone played): this page is all there is, and its `next` where to ask on from (2.1.15 review)
  if (!held.asked || !newestHeld || (page.next && oldest && after(oldest, newestHeld))) {
    return { plays: page.plays, before: page.next, asked: true }
  }
  return { plays: merged(page.plays, held.plays), before: page.next === null ? null : held.before, asked: true }
}

/** The page before the oldest held come, asked for from `from`: added below - unless what is held has moved on since
 *  (the newest page started again), when it is the same `held`. */
export function withOlder(held: Held, from: Cursor, page: HistoryPage): Held {
  if (!held.before || held.before.at !== from.at || held.before.id !== from.id) return held
  return { plays: merged(held.plays, page.plays), before: page.next, asked: true }
}

/** A start's `counted` set, when it is the one a counted play names (the scrobble's song and `time`). */
export function countedIn(own: readonly Played[], songId: string, at: number): Played[] {
  return own.some((played) => played.song.id === songId && played.at === at && !played.counted)
    ? own.map((played) => (played.song.id === songId && played.at === at ? { ...played, counted: true } : played))
    : (own as Played[])
}

/** What a failed send means for the starts it carried: 'retry' (deadwax unreachable, a 5xx, a 408 or a 429 - asked
 *  again later - or signed out, a 401, until a sign-in) or 'drop' (another 4xx: they will never be taken -
 *  DeadwaxCore's PendingPlays.after, the same). */
export function afterFailure(status: number | null): 'retry' | 'drop' {
  return status !== null && status >= 400 && status < 500 && ![401, 408, 429].includes(status) ? 'drop' : 'retry'
}

/** How long after the `failures`-th failed send in a row the outbox tries again: RETRY_MS doubling - 30 s, 1 min, 2,
 *  4, 8 - to RETRY_MAX_MS (10 min), so a deadwax without its database isn't sent the same starts every 30 s for ever. */
export const RETRY_MS = 30_000
export const RETRY_MAX_MS = 600_000
export function retryAfter(failures: number): number {
  return Math.min(RETRY_MAX_MS, RETRY_MS * 2 ** Math.max(0, Math.min(failures - 1, 20)))
}
