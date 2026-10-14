/**
 * The bulk runs - Get covers · N, Get CD art · N, Get lyrics · N - pure, so both pages that run them
 * say the same thing about the same library: the main page's Library tab (components/LibraryView.tsx,
 * over the albums in view) and the app's Library care page on a desktop (app/LibraryCare.tsx,
 * 2.0.0-player.42, over the whole library or the albums a few typed words narrow it to). Pinned by
 * ui/test/care.sim.cjs.
 *
 * WHICH ALBUMS a run takes (`bulkTargets`), album folders as the scan lists them:
 *  - COVERS: a release id and no cover - the Archive is asked by the release the tags name, so an
 *    album with none has nothing to ask about, and a cover already there is never replaced (that is
 *    the metadata editor's, comparing the two).
 *  - CD ART: a release id and none of deadwax's own `disc*` images. A download's `cd.jpg` scan doesn't
 *    count: a fetched `disc.*` sits ahead of it in every reader's order (notes/library.md "CD art and
 *    embedded pictures"), and the route refuses an album that has one of deadwax's own.
 *  - LYRICS: no lyrics on disk at all - not "any track missing": an album with one instrumental track
 *    would be offered for ever, and every run would ask LRCLIB about it again. A partly-covered album
 *    is finished from its own Get lyrics button, which looks up only the tracks still without.
 *
 * HOW A RUN GOES (`runBulk`): one album at a time, through the route a single click uses - never a
 * loop on the server (notes/decisions.md: the bulk runs are driven from the client) - so it can be
 * watched and stopped, and the Cover Art Archive going away for a minute is one slow album rather
 * than thirty failures at once. Stop lands after the album being fetched. What each album came to is
 * counted apart (`addOutcome`): for covers and CD art, written, none to find (a 404 - a fact about the
 * release) and failed (anything else - worth trying again); for lyrics, in TRACKS, saved, not on
 * LRCLIB or instrumental, and failed. The words for a finished run are the main page's
 * (`bulkSummary`).
 */

/** What a bulk run reads of an album in the library's scan (api/types.ts LibraryAlbum). */
export interface BulkAlbum {
  path: string
  art: string
  release_mbid: string
  disc_art?: readonly string[] | undefined
  lyrics_count: number
  track_count: number
}

export type BulkKind = 'covers' | 'disc' | 'lyrics'

/** The three runs, in the order both pages draw them. */
export const BULK_KINDS: readonly BulkKind[] = ['covers', 'disc', 'lyrics']

/** Whether the album has CD art deadwax saved - a `disc*` image beside its tracks. */
export function hasOwnDiscArt(album: Pick<BulkAlbum, 'disc_art'>): boolean {
  return (album.disc_art ?? []).some((name) => name.toLowerCase().startsWith('disc'))
}

/** Albums a cover could be fetched for: a release to ask the Archive about, and no cover yet. */
export function coverTargets<T extends BulkAlbum>(albums: readonly T[]): T[] {
  return albums.filter((album) => !album.art && album.release_mbid)
}

/** Albums CD art could be fetched for: a release, and none of deadwax's own `disc*` images. */
export function discTargets<T extends BulkAlbum>(albums: readonly T[]): T[] {
  return albums.filter((album) => album.release_mbid && !hasOwnDiscArt(album))
}

/** Albums with no lyrics on disk at all. */
export function lyricsTargets<T extends BulkAlbum>(albums: readonly T[]): T[] {
  return albums.filter((album) => !album.lyrics_count)
}

/** The albums a run of `kind` takes, in the order given. */
export function bulkTargets<T extends BulkAlbum>(kind: BulkKind, albums: readonly T[]): T[] {
  return kind === 'covers' ? coverTargets(albums) : kind === 'disc' ? discTargets(albums) : lyricsTargets(albums)
}

/** A run under way, or the last one's result: how far it got, and what came of each album. For
 *  lyrics the three counts are tracks; for covers and CD art, albums. */
export interface BulkRun {
  total: number
  done: number
  written: number
  missing: number
  failed: number
  running: boolean
}

/** What one album came to (any count left out is none). */
export interface BulkOutcome {
  written?: number
  missing?: number
  failed?: number
}

export function startRun(total: number): BulkRun {
  return { total, done: 0, written: 0, missing: 0, failed: 0, running: true }
}

/** The run with one more album done, and what it came to. */
export function addOutcome(run: BulkRun, outcome: BulkOutcome): BulkRun {
  return {
    ...run,
    done: run.done + 1,
    written: run.written + (outcome.written ?? 0),
    missing: run.missing + (outcome.missing ?? 0),
    failed: run.failed + (outcome.failed ?? 0),
  }
}

/**
 * Run `step` over `targets`, one album at a time, in order. `stopped` is asked before each album - a
 * Stop pressed lands after the album being fetched. `progress` hears the run as it starts, after each
 * album, and as it ends (`running` false). A step is expected to settle with an outcome; one that
 * throws anyway counts that album failed (a track each, for lyrics - `failedAs`).
 */
export async function runBulk<T>(
  targets: readonly T[],
  step: (album: T) => Promise<BulkOutcome>,
  progress: (run: BulkRun) => void,
  stopped: () => boolean,
  failedAs: (album: T) => number = () => 1,
): Promise<BulkRun> {
  let run = startRun(targets.length)
  progress(run)
  for (const album of targets) {
    if (stopped()) break
    let outcome: BulkOutcome
    try {
      outcome = await step(album)
    } catch {
      outcome = { failed: failedAs(album) }
    }
    run = addOutcome(run, outcome)
    progress(run)
  }
  run = { ...run, running: false }
  progress(run)
  return run
}

const plural = (count: number, one: string, many = `${one}s`) => (count === 1 ? one : many)

/**
 * What a finished run did, in the main page's words (its status bar's). "None on the Archive" is kept
 * apart from "failed": the first is a fact about the release, the second worth trying again - and the
 * same split for lyrics, where "not on LRCLIB" is final.
 */
export function bulkSummary(kind: BulkKind, run: BulkRun): string {
  const stopped = run.done < run.total
  if (kind === 'lyrics') {
    return `saved lyrics for ${run.written} ${plural(run.written, 'track')}`
      + (run.missing ? `, ${run.missing} not on LRCLIB or instrumental` : '')
      + (run.failed ? `, ${run.failed} failed - try those again` : '')
      + (stopped ? ` (stopped at ${run.done} of ${run.total} albums)` : '')
  }
  const head = kind === 'covers'
    ? `fetched ${run.written} ${plural(run.written, 'cover')}`
    : `fetched CD art for ${run.written} ${plural(run.written, 'album')}`
  return head
    + (run.missing ? `, ${run.missing} ${kind === 'covers' ? 'had none on the Archive' : 'had none to find'}` : '')
    + (run.failed ? `, ${run.failed} failed - try those again` : '')
    + (stopped ? ` (stopped at ${run.done} of ${run.total})` : '')
}
