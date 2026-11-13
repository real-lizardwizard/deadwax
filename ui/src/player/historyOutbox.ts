/**
 * The songs this page starts, on their way to deadwax (2.1.15) - notes/play-history.md. The engine's one line in
 * beginListen hands each start to api.ts started(), which tells Navidrome "now playing" as before and puts the start
 * here; app/usePlayHistory.ts draws them in Up Next at once, before deadwax has them.
 *
 *  - KEPT: this page's starts, the newest OWN_KEPT, sent or not - drawn until a page of deadwax's holds them (the page
 *    in hand may be older than they are).
 *  - SENT at once, each start - every one pending in one POST /deadwax/me/history, at most HISTORY_POST_MAX, one POST
 *    at a time. No answer, a 5xx, a 408 or a 429: tried again later - 30 s after the first failure, doubling to 10 min
 *    (lib/playHistory.ts retryAfter: a deadwax without its database isn't sent the same 500 every 30 s for ever) - and
 *    at the next start; a 401 (signed out - the sign-in comes over the app, and a different person reloads the page):
 *    held for the next start, which the same person carrying on makes; another 4xx - they will never be taken
 *    (afterFailure, the phone's PendingPlays.after) - let go. A send taken starts the waits again from 30 s.
 *  - PENDING at most OWN_KEPT: past it the oldest waiting are let go (they are still drawn here while kept). Held in
 *    memory only: a reload while deadwax can't be reached loses them, and nothing plays then anyway.
 *  - COUNTED: a counted play (api.ts scrobble with `submission` and its `time`) sets `counted` on its start here too -
 *    deadwax's scrobble route marks the start it holds, and a start still on its way carries it itself (the insert
 *    ORs it in), so a count that reaches deadwax before its start isn't lost.
 *  - A CONTINUATION (app/useResume.ts): a queue of deadwax's own put back mid-song was begun before - perhaps
 *    yesterday, perhaps on the phone - so its first start, if it is of that queue's entry, isn't one. Any other start,
 *    and another put back, ends it.
 *
 * Not the engine's: it fetches, so it is no pure rule either (history.sim.cjs drives it against a fake fetch).
 */

import { ApiError, post } from '../api/http'
import { HISTORY_POST_MAX, OWN_KEPT, afterFailure, countedIn, retryAfter, type Played } from '../lib/playHistory'
import type { UpNextQueue } from '../lib/upNext'

/** This page's starts, newest first - kept, sent or not. */
let own: Played[] = []
/** Those deadwax hasn't taken yet, oldest first. */
let pending: Played[] = []
let sending = false
let retry: ReturnType<typeof setTimeout> | undefined
/** Failed sends in a row - how long the next wait is (retryAfter). */
let failures = 0
let continuation: { queue: string; entry: number } | null = null
const listeners = new Set<() => void>()

function changed(): void {
  for (const listener of listeners) listener()
}

/** This page's starts, newest first. */
export function ownStarts(): readonly Played[] {
  return own
}

/** The starts not yet taken, oldest first (the sims). */
export function pendingStarts(): readonly Played[] {
  return pending
}

/** Told whenever this page's starts change - a start, or one counted. */
export function onStarts(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** A song begun (api.ts started()) - kept and sent, unless it is the continuation's. */
export function record(played: Played): void {
  const went = continuation
  continuation = null
  if (went && played.queue === went.queue && played.entry === went.entry) return
  own = [played, ...own].slice(0, OWN_KEPT)
  pending = [...pending, played].slice(-OWN_KEPT)
  changed()
  send()
}

/** A counted play: `counted` set on its start, the song's at the listen's start time (the scrobble's `time`). */
export function counted(songId: string, at: number): void {
  const kept = countedIn(own, songId, at)
  const waiting = countedIn(pending, songId, at)
  if (kept === own && waiting === pending) return
  own = kept
  pending = waiting
  changed()
  //? a start sent before it counted is marked by the scrobble route; one still waiting goes with it, at its next send
}

/** A queue of deadwax's own put back paused mid-song (app/useResume.ts): its next start, if it is of the song put back,
 *  is the same listen carrying on. Null - any other queue put back - ends one. */
export function continuing(queue: UpNextQueue | null): void {
  const id = queue?.upNext?.id
  const entry = queue?.upNext?.marks[queue.index]?.key
  continuation = id !== undefined && entry !== undefined ? { queue: id, entry } : null
}

/** Every start pending, sent - one POST at a time, at most HISTORY_POST_MAX of them. */
function send(): void {
  if (sending || !pending.length) return
  clearTimeout(retry)
  retry = undefined
  sending = true
  const batch = pending.slice(0, HISTORY_POST_MAX)
  post<{ taken: number; skipped: number }>('/me/history', { starts: batch }).then(
    () => {
      //? taken: every one sent goes - one counted while it was on its way is a new object, and goes again with it
      pending = pending.filter((played) => !batch.includes(played))
      sending = false
      failures = 0
      send()
    },
    (error: unknown) => {
      sending = false
      const status = error instanceof ApiError ? error.status : null
      if (afterFailure(status) === 'drop') {
        console.warn('deadwax player: deadwax would not keep these songs played', error)
        pending = pending.filter((played) => !batch.includes(played))
        send()
        return
      }
      //? signed out: held for the next start - asking again every 30 s would only bring the sign-in back each time
      if (status === 401) return
      failures += 1
      retry ??= setTimeout(() => {
        retry = undefined
        send()
      }, retryAfter(failures))
    },
  )
}

/** Everything forgotten (the sims, between cases). */
export function forgetStarts(): void {
  clearTimeout(retry)
  retry = undefined
  own = []
  pending = []
  sending = false
  failures = 0
  continuation = null
  changed()
}
