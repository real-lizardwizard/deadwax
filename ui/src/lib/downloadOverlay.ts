import type { DownloadJob } from '../api/types'
import { isActive } from './jobs'

/**
 * Optimistic overlays for the downloads panel.
 *
 * WHAT PROBLEM THIS SOLVES
 *
 * Both actions in that panel cost two sequential round-trips before anything could change on
 * screen: one to deadwax - which itself calls on to slskd - and then a poll to see the
 * result. Until both landed, the row was pixel-identical to how it looked before the click.
 * That is the "latency": not that the app was slow, but that it showed nothing at all while
 * it waited for the server to agree.
 *
 * An overlay is a prediction laid over the polled data. The polled data stays authoritative
 * and is never edited, which is what makes this safe - the worst case is a prediction that
 * turns out wrong, and both of the functions below exist to make that case end quickly.
 *
 * Pure, and separate from the hook, for the reason everything else in lib/ is: this is the
 * part with the interesting edge cases, and it can be exercised without a browser or a
 * server. See ui/test/downloads.sim.cjs.
 */

/**
 * A download asked for and not yet a job (v0.9.9, asked for: "I would like it if the downloads
 * showed up in the downloads pane a bit quicker").
 *
 * A job is only recorded once slskd accepts the enqueue, and slskd doesn't answer until it has
 * looked the peer up and connected to them - seconds, more for a firewalled peer - so the pane
 * had nothing to show for all of that. This is shown instead, from the click. It becomes the
 * real row when the job appears in a poll (`jobId` set and seen), or says why when slskd
 * refuses (`error` set) and then stays, like any finished row, until "clear finished".
 */
export interface PendingDownload {
  key: string
  artist: string
  album: string
  username: string
  jobId?: number
  error?: string
}

export interface Overlays {
  /** Cancels asked for but not yet confirmed by the server. */
  cancelling: ReadonlySet<number>
  /** Finished jobs optimistically removed by "clear finished". */
  cleared: ReadonlySet<number>
  /** Downloads asked for that aren't jobs yet, newest first. */
  pending: readonly PendingDownload[]
  /**
   * Failed or cancelled jobs moving to the next peer (v0.9.12), until a poll shows them
   * active again - "trying next peer…" from the click, like cancelling.
   */
  retrying: ReadonlySet<number>
}

export const NO_OVERLAYS: Overlays = { cancelling: new Set(), cleared: new Set(), pending: [], retrying: new Set() }

/** A pending download still waiting on slskd - it counts as active, a refused one doesn't. */
export function isWaiting(pending: PendingDownload): boolean {
  return pending.error === undefined
}

export function withPending(overlays: Overlays, pending: PendingDownload): Overlays {
  return { ...overlays, pending: [pending, ...overlays.pending] }
}

/** Record slskd's answer on one pending download. */
export function settlePending(
  overlays: Overlays, key: string, outcome: { jobId: number } | { error: string },
): Overlays {
  return {
    ...overlays,
    pending: overlays.pending.map((p) => (p.key === key ? { ...p, ...outcome } : p)),
  }
}

/** "Clear finished" takes the refused ones with it; the ones still waiting stay. */
export function withoutRefused(overlays: Overlays): Overlays {
  const pending = overlays.pending.filter(isWaiting)
  return pending.length === overlays.pending.length ? overlays : { ...overlays, pending }
}

/**
 * The jobs the panel should render, with the overlays applied.
 *
 * Cleared rows disappear outright. A cancelling row STAYS - the transfer really is still
 * running until slskd stops it, and removing it would claim something that hasn't happened -
 * but it stops counting as active, so the toolbar summary and the toggle badge both drop on
 * the click rather than a poll later.
 */
export function visibleJobs(jobs: readonly DownloadJob[], overlays: Overlays): DownloadJob[] {
  return overlays.cleared.size ? jobs.filter((job) => !overlays.cleared.has(job.id)) : [...jobs]
}

export function activeCount(jobs: readonly DownloadJob[], overlays: Overlays): number {
  return jobs.filter((job) => isActive(job)
    ? !overlays.cancelling.has(job.id)
    //? a failed job moving to its next peer is about to be active again - count it from the click
    : overlays.retrying.has(job.id)).length
    + overlays.pending.filter(isWaiting).length
}

/**
 * The pending downloads to draw: not yet a job in the list. One whose job has turned up is
 * dropped here as well as by reconcile, so the poll that brings the job can never draw both.
 */
export function visiblePending(jobs: readonly DownloadJob[], overlays: Overlays): PendingDownload[] {
  if (!overlays.pending.length) return []
  const ids = new Set(jobs.map((job) => job.id))
  return overlays.pending.filter((p) => p.jobId === undefined || !ids.has(p.jobId))
}

/**
 * Drop any overlay the freshly polled data now agrees with.
 *
 * Reconciled against the DATA rather than against the request completing, and the difference
 * matters: a cancel request returns before the job's status has necessarily changed, so
 * clearing the overlay on completion would flip the row back to "downloading" for one poll
 * before it finally read "cancelled". Waiting for the server's own answer to match removes
 * that flicker entirely.
 *
 * Returns the SAME set objects when nothing changed, so callers can use identity to skip a
 * re-render.
 */
export function reconcile(jobs: readonly DownloadJob[], overlays: Overlays): Overlays {
  const byId = new Map(jobs.map((job) => [job.id, job]))

  let cancelling = overlays.cancelling
  if (cancelling.size) {
    const next = new Set(cancelling)
    for (const id of cancelling) {
      const job = byId.get(id)
      //? Confirmed when the job stops being active, or disappears entirely.
      if (!job || !isActive(job)) next.delete(id)
    }
    if (next.size !== cancelling.size) cancelling = next
  }

  let cleared = overlays.cleared
  if (cleared.size) {
    const next = new Set(cleared)
    //? Confirmed when the job is gone from the server's list.
    for (const id of cleared) if (!byId.has(id)) next.delete(id)
    if (next.size !== cleared.size) cleared = next
  }

  let retrying = overlays.retrying
  if (retrying.size) {
    const next = new Set(retrying)
    //? Confirmed when the job is moving again - or gone, cleared from under it
    for (const id of retrying) {
      const job = byId.get(id)
      if (!job || isActive(job)) next.delete(id)
    }
    if (next.size !== retrying.size) retrying = next
  }

  let pending = overlays.pending
  if (pending.some((p) => p.jobId !== undefined && byId.has(p.jobId))) {
    //? Confirmed when its job is in the list - the real row takes over from here
    pending = pending.filter((p) => p.jobId === undefined || !byId.has(p.jobId))
  }

  return cancelling === overlays.cancelling && cleared === overlays.cleared
    && pending === overlays.pending && retrying === overlays.retrying
    ? overlays
    : { cancelling, cleared, pending, retrying }
}

/** The finished jobs "clear finished" would remove. */
export function finishedIds(jobs: readonly DownloadJob[]): number[] {
  return jobs.filter((job) => !isActive(job)).map((job) => job.id)
}

export function withAdded(set: ReadonlySet<number>, ids: readonly number[]): Set<number> {
  const next = new Set(set)
  for (const id of ids) next.add(id)
  return next
}

export function withRemoved(set: ReadonlySet<number>, ids: readonly number[]): Set<number> {
  const next = new Set(set)
  for (const id of ids) next.delete(id)
  return next
}
