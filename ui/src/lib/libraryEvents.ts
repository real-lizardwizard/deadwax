import type { DownloadJob, JobStatus } from '../api/types'

/**
 * "An album just landed in the library" - said by the downloads poll, heard by the library view
 * and the tab badge.
 *
 * Without it a filed album did not appear until you pressed Rescan or reloaded the page. The
 * library loads once, when its tab is first opened, and deliberately never on a timer (a scan
 * stats every folder); the badge polled once a minute. Meanwhile the downloads poll - which
 * runs in the background whenever anything is downloading - watched the job turn `organized`
 * and told nobody. This is the telling.
 *
 * A module rather than a bridge entry: every Preact root is rendered from this one bundle, so
 * they share this module's state, and the window bridge is for reaching the VANILLA half. Pure
 * apart from the listener set, so ui/test/downloads.sim.cjs can hold it to account.
 */

type Listener = () => void

const listeners = new Set<Listener>()

/** Hear about filed albums. Returns the unsubscribe, which is what an effect wants back. */
export function onAlbumsFiled(listener: Listener): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/**
 * The vanilla search view hears it as a window event instead - it can't import this module,
 * and marking a search result as held is a one-way notice, not a call it needs an answer from,
 * so it doesn't earn a bridge entry either. Guarded, because the sims run this in Node.
 */
export const ALBUMS_FILED_EVENT = 'deadwax:albums-filed'

export function announceAlbumsFiled(): void {
  //? a copy, so a listener that unsubscribes while being told cannot skip the next one
  for (const listener of [...listeners]) listener()
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent(ALBUMS_FILED_EVENT))
}

/**
 * The jobs that became `organized` since the previous poll.
 *
 * `organized` and nothing else: it is the one status meaning files reached the library.
 * `complete` also appears BEFORE filing starts - the poller marks a job complete and only then
 * organizes it - so reacting to it would scan the library for an album that isn't there yet.
 *
 * `previous` is null on the first poll after the page loads, which only SEEDS: every job
 * organized before you arrived would otherwise announce itself on every page load, and scan a
 * library nobody has asked to see.
 */
export function newlyOrganized(
  previous: ReadonlyMap<number, JobStatus> | null,
  jobs: readonly DownloadJob[],
): number[] {
  if (previous === null) return []
  return jobs
    .filter((job) => job.status === 'organized' && previous.get(job.id) !== 'organized')
    .map((job) => job.id)
}

/** What newlyOrganized() compares the next poll against. */
export function statusesOf(jobs: readonly DownloadJob[]): Map<number, JobStatus> {
  return new Map(jobs.map((job) => [job.id, job.status]))
}
