import type { NavidromeStatus } from '../player/api'
import { latestOnly } from './latest'

/**
 * Asking Navidrome whether it answers, once for every gate (App hands the status to each NeedsNavidrome).
 * Two ways to ask, since 2.0.0-player.47's review:
 *
 *  - `check()` - as the app starts, and from a gate's Try again: the status put away first, so every gate
 *    shows its spinner until the answer lands (a gate that isn't open has nothing under it to lose).
 *  - `recheck()` - after a save on Server settings that touched Navidrome's settings (a first run set up
 *    from Connections opens its gates by itself). QUIET while the gates are open: the status drawn stays
 *    until the answer lands, so a working setup's pages - the Library with its loaded pages, its scroll and
 *    its sort, an album page on top of any tab - are never thrown away and fetched again for a password
 *    retyped. An answer that isn't ok still closes them. A gate not open yet shows its spinner while it
 *    asks, as Try again does.
 *
 * Either way only the newest answer draws (lib/latest.ts): an ask still out when the next begins - an
 * address that doesn't answer waits out the server's 10 s connect timeout, and a fix can be saved inside
 * it - is called off, so its late "can't reach" never closes the gates on settings that work.
 */
export interface NavidromeChecks {
  check: () => void
  recheck: () => void
  /** calls off the ask still out, drawing nothing of it */
  stop: () => void
}

export function navidromeChecks(
  ask: (signal?: AbortSignal) => Promise<NavidromeStatus>,
  show: (next: (now: NavidromeStatus | null) => NavidromeStatus | null) => void,
): NavidromeChecks {
  const asks = latestOnly()
  const run = (quiet: boolean): void => {
    const ticket = asks.begin()
    show((now) => (quiet && now?.ok ? now : null))
    ask(ticket.signal).then(
      (status) => {
        if (ticket.current()) show(() => status)
      },
      (reason: unknown) => {
        if (ticket.current()) show(() => ({ configured: true, ok: false, server: null, problem: String(reason) }))
      },
    )
  }
  return { check: () => run(false), recheck: () => run(true), stop: asks.supersede }
}
