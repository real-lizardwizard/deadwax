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

/* (The main page's search heard it as a window event, deadwax:albums-filed, until that page retired in
 * 2.0.0-player.66; nothing else listened, so the event went with it.) */
export function announceAlbumsFiled(): void {
  //? a copy, so a listener that unsubscribes while being told cannot skip the next one
  for (const listener of [...listeners]) listener()
}

/**
 * "An album went into your library from the store" (2.0.0-player.51, Add to my library) - said by
 * whichever store line added it (the album page's, or the Sources panel's beside it), heard by the album
 * page, which asks the store again so its line says "Already in your library", and by your library's
 * store (app/useMyLibrary.ts). Apart from announceAlbumsFiled: nothing was filed, so the library view,
 * the badge and the owned marks have nothing to learn from it.
 */
const added = new Set<Listener>()

export function onAddedToLibrary(listener: Listener): () => void {
  added.add(listener)
  return () => {
    added.delete(listener)
  }
}

export function announceAddedToLibrary(): void {
  for (const listener of [...added]) listener()
}

/**
 * "An album went out of your library" (2.0.0-player.52, Remove from my library) - said by the album page that
 * removed it, heard by your library's store (app/useMyLibrary.ts) and your albums (app/useYourAlbums.ts), so
 * the count and the Library's own views follow. Nothing left the store, so the store's views, the badge and
 * the owned marks' store half have nothing to learn from it - but whose it is did change, and the owned marks
 * hear it for that (app/useOwned.ts).
 */
const removed = new Set<Listener>()

export function onRemovedFromLibrary(listener: Listener): () => void {
  removed.add(listener)
  return () => {
    removed.delete(listener)
  }
}

export function announceRemovedFromLibrary(): void {
  for (const listener of [...removed]) listener()
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
