/**
 * The release editor's words for what Apply will do and what it did (2.1.30) - pure, so ui/test/editwords.sim.cjs
 * holds them and the iPhone app's exporter can run them as they are (its Phase 8, notes/ios-specs/phase8-managing.md
 * on `ios`, section 12). Moved unchanged out of components/MetadataEditor.tsx, which draws each where it always did:
 * the preview's lines over the files' changes, the summary and the Apply button at its foot, the sentence an apply
 * leaves.
 */

import type { RetagPlan, RetagResults } from '../api/types'
import { filesWord } from './format'

/** What the editor says while a preview is on its way: the tracklist arrives separately from the list of pressings,
 *  so "working out the changes" would be describing the wrong step while it loads. */
export function planningLabel(loadingRelease: boolean): string {
  return loadingRelease ? 'Fetching the tracklist…' : 'Working out the changes…'
}

/** A preview or an apply that failed, said through sayError (lib/errorWords.ts) as its fallback. */
export const PREVIEW_FAILED = "Couldn't work out the changes."
export const APPLY_FAILED = "Couldn't apply the changes."

/** The folder line's label: the files join another folder of the release, or this folder is renamed. */
export function moveLabel(plan: Pick<RetagPlan, 'merge'>): string {
  return plan.merge ? 'Merge' : 'Folder'
}

/**
 * The pause before the rename, said before the click so a paused Apply doesn't read as stuck (v1.0.1) - or null when
 * the apply doesn't both write the tags and rename. Asking Navidrome (v1.0.3) has no fixed length, so it gets no
 * number: the cap is a ceiling, and quoting it would make a few seconds' wait sound like ninety. A rename held back
 * earlier (no file to change) has its tags on disk already, and still waits for Navidrome to have scanned them (1.0.3
 * review).
 */
export function renameWaitWords(plan: Pick<RetagPlan, 'moves' | 'rename_wait' | 'rename_by' | 'changed_file_count'>): string | null {
  if (!plan.moves || !plan.rename_wait) return null
  if (plan.rename_by === 'navidrome') {
    return plan.changed_file_count === 0
      ? 'The tags were written by an earlier apply. Renames the folder once Navidrome '
        + "has scanned them, so Navidrome keeps this album's plays, ratings and favourites."
      : 'Writes the tags first and renames the folder once Navidrome has scanned them '
        + "(usually a few seconds), so Navidrome keeps this album's plays, ratings and favourites."
  }
  return `Writes the tags first and renames ${plan.rename_wait}s later, so Navidrome keeps `
    + `this album's plays, ratings and favourites.`
}

/** "disc 2", "discs 1, 2, 3" */
export function discWords(discs: readonly number[]): string {
  return `disc${discs.length > 1 ? 's' : ''} ${discs.join(', ')}`
}

/** The discs of one release stored one folder per disc (v0.9.13): what the merge moves where, and any file left
 *  behind because one of its name is there already - or null when the apply is no merge. */
export function mergeWords(plan: Pick<RetagPlan, 'merge' | 'merge_detail'>): string | null {
  const detail = plan.merge ? plan.merge_detail : null
  if (!detail) return null
  return `Moves ${discWords(detail.discs_here)} in beside `
    + `${discWords(detail.discs_there)}, which ${detail.discs_there.length > 1 ? 'are' : 'is'} `
    + 'already there as the same release, and removes this folder once it is empty.'
    + (detail.kept_back.length > 0 ? ` ${detail.kept_back.join(', ')} stays behind - there's one of that name already.` : '')
}

/** The preview of an album that already carries the release, as chosen. */
export const NOTHING_TO_CHANGE = 'Nothing to change.'

/** The line at the editor's foot over a preview with something to change: how many files, and the cover and folder. */
export function changeSummary(plan: Pick<RetagPlan, 'changed_file_count' | 'file_count' | 'art' | 'moves' | 'merge'>): string {
  return `${plan.changed_file_count} of ${filesWord(plan.file_count)} would change`
    + (plan.art.action === 'download' ? ', the cover would be downloaded' : '')
    + (plan.art.action === 'replace' ? ', the cover would be replaced' : '')
    + (plan.moves ? (plan.merge ? ', and the files would join the other disc' : ', and the folder would be renamed') : '')
}

/**
 * What the Apply button says while it works. A pause before the rename is named, so a button
 * busy for a while doesn't read as stuck: the seconds when it is a fixed wait, and no number when
 * it is waiting for Navidrome, which ends when Navidrome has scanned rather than on a clock.
 */
export function applyingLabel(plan: Pick<RetagPlan, 'rename_wait' | 'rename_by'> | null): string {
  if (!plan?.rename_wait) return 'Applying'
  return plan.rename_by === 'navidrome'
    ? 'Applying, waiting for Navidrome'
    : `Applying, renaming in ${plan.rename_wait}s`
}

/** An apply that couldn't write some of the files. */
export function writeFailedWords(failed: number): string {
  return `Couldn't write ${filesWord(failed)}.`
}

/**
 * What an apply did, as a sentence. "Updated the tags in 0 files" is a silly thing to say when only the folder
 * changed, which is exactly what happens if you edit nothing but the edition name. (2.0.8, UX batch 5) In words: it
 * said "Retagged 12 file(s)" and "re-filed the folder".
 */
export function appliedWords(results: Pick<RetagResults, 'tagged' | 'art_written' | 'merged' | 'moved_to'>): string {
  return [
    results.tagged ? `updated the tags in ${filesWord(results.tagged)}` : '',
    results.art_written ? `saved ${results.art_written}` : '',
    results.merged ? 'moved it in beside the other discs'
      : results.moved_to ? 'moved the folder to match its tags' : '',
  ].filter(Boolean).join(', ').replace(/^./, (c) => c.toUpperCase()) + '.'
}
