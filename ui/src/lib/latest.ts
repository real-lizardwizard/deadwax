/**
 * Only the newest answer counts - the Preact half's copy of interface/scripts/latest.mjs, which
 * says why at length. In short: pick one pressing in the metadata editor, then another before
 * the first's tracklist arrived, and the FIRST one's tracklist landed last and became what Apply
 * would write, under the second one's highlight. Every fetch that draws goes through one of
 * these, and asks `current()` before it writes anything.
 *
 * Kept in step with the vanilla copy by ui/test/latest.sim.cjs, which runs both.
 */

export interface Ticket {
  signal: AbortSignal | undefined
  current: () => boolean
}

export interface Latest {
  begin: () => Ticket
  supersede: () => void
}

export function latestOnly(): Latest {
  let newest = 0
  let controller: AbortController | null = null

  function supersede(): void {
    newest += 1
    controller?.abort()
    controller = null
  }

  return {
    begin() {
      supersede()
      const ticket = newest
      controller = typeof AbortController === 'function' ? new AbortController() : null
      return {
        signal: controller?.signal,
        current: () => ticket === newest,
      }
    },
    supersede,
  }
}

/** Whether `error` is only a fetch being called off - never worth reporting. */
export function isAbort(error: unknown): boolean {
  return (error as { name?: unknown } | null)?.name === 'AbortError'
}
