/**
 * The release editor's words for what Apply will do and what it did (2.1.30) - pure, so ui/test/editwords.sim.cjs
 * holds them and the iPhone app's exporter can run them as they are (its Phase 8, notes/ios-specs/phase8-managing.md
 * on `ios`, section 12). Moved unchanged out of components/MetadataEditor.tsx, which draws each where it always did:
 * the preview's lines over the files' changes, the summary and the Apply button at its foot, the sentence an apply
 * leaves.
 */

import type { CoverSavedAnswer, RetagArtPlan, RetagPlan, RetagResults } from '../api/types'
import { asSentence } from './errorWords'
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

/** The line at the editor's foot over a preview with something to change: how many files, and the cover and folder.
 *  (cover words, 27 Nov) A cover replaced is said by coverLine, on a line of its own, not here. */
export function changeSummary(plan: Pick<RetagPlan, 'changed_file_count' | 'file_count' | 'art' | 'moves' | 'merge'>): string {
  return `${plan.changed_file_count} of ${filesWord(plan.file_count)} would change`
    + (plan.art.action === 'download' ? ', the cover would be downloaded' : '')
    + (plan.moves ? (plan.merge ? ', and the files would join the other disc' : ', and the folder would be renamed') : '')
}

/** Names said as one: "a", "a or b", "a, b or c". */
function orList(names: readonly string[]): string {
  return names.length < 2 ? names.join('') : `${names.slice(0, -1).join(', ')} or ${names[names.length - 1]}`
}

/** (cover removal, review) A replace that keeps the image there - one that isn't cover-named, or a link: said so. */
const COVER_STAYS = 'The image already there stays.'

/** (cover removal, final) A cover the server won't remove because it is a link (`removes_refused` "link"): why it stays,
 *  and nothing about deleting - the save may not happen at all (a link named cover.jpg is never written through). */
function coverLink(name: string | null): string {
  return `Your cover (${name}) is a link to somewhere else, so it stays.`
}

/**
 * (cover removal, review) Another cover file Apply leaves that will be shown before this pressing's, said before Apply:
 * the one the preview knows will be, or - when it can't know the new file's name (a cover at full size, its name
 * following its type) - the cover files that may be. Null with none, and from a server that doesn't say.
 */
export function coverShownFirst(art: Pick<RetagArtPlan, 'still_shown_first' | 'also_covers'>): string | null {
  const first = art.still_shown_first
  if (first === undefined) return null
  if (first !== null) return first.length > 0 ? `${first[0]} will still be the cover you see. It isn't removed.` : null
  const others = art.also_covers ?? []
  return others.length > 0 ? `${orList(others)} may still be the cover you see.` : null
}

/**
 * (cover words, 27 Nov) The cover's own line under the summary, whenever the album has a cover to lose: kept, or
 * replaced with the pressing's - said plainly, since a cover the folder came with may be one you chose. Null with no
 * cover there, where the summary says one would be downloaded. (cover removal, review) A replace that deletes nothing
 * (`removes` null, from a server that names it) keeps the image there - a link said as one; another cover still shown
 * first is said after.
 */
export function coverLine(plan: Pick<RetagPlan, 'art'>): string | null {
  if (!plan.art.existing) return null
  if (plan.art.action !== 'replace') return 'Your cover is kept.'
  const warning = coverShownFirst(plan.art)
  if (plan.art.removes !== undefined && !plan.art.removes) {
    if (plan.art.removes_refused === 'link') return coverLink(plan.art.existing) + (warning ? ` ${warning}` : '')
    return warning ? `${COVER_STAYS} ${warning}` : `This pressing's cover will be shown instead. The image already there (${plan.art.existing}) stays.`
  }
  return "Your cover will be replaced with this pressing's." + (warning ? ` ${warning}` : '')
}

/**
 * (cover words, review) Which cover the album has, as the cover's words see it: a cover file in the folder ('file'),
 * one only inside the music files ('embedded'), or none (''). A preview's own word for the file when there is one
 * for what the page shows (it read the folder just now); else - before the first, while one is redone, after one
 * failed - the scan's (`album.art`).
 */
export function coverThere(plan: Pick<RetagPlan, 'art'> | null, albumArt: string): 'file' | 'embedded' | '' {
  if (plan) return plan.art.existing ? 'file' : albumArt === 'embedded' ? 'embedded' : ''
  return albumArt === 'file' || albumArt === 'embedded' ? albumArt : ''
}

/**
 * (App Design, 27 Nov) Whether a replace takes the cover file there away: a file there, and no preview saying it stays
 * (coverKept) - the file named as the one removed or written over, a preview from before the removal, or none yet. The
 * labels say "Replace" only then: an image a replace keeps (a link, one under another name), a cover only inside the
 * files, or none, is saved beside or into the folder, and nothing is replaced.
 */
function coverGoes(plan: Pick<RetagPlan, 'art'> | null, albumArt: string): boolean {
  return coverThere(plan, albumArt) === 'file' && !coverKept(plan, albumArt)
}

/** The cover box's words beside its tick: a cover file that goes is said to be yours, and what takes its place;
 *  else the pressing's cover saved (App Design, 27 Nov: never "Replace" where the line says the old one stays). */
export function coverToggle(plan: Pick<RetagPlan, 'art'> | null, albumArt: string): string {
  return coverGoes(plan, albumArt) ? "Replace your cover with this pressing's" : "Save this pressing's cover"
}

/** The size the cover would be saved at - chosen in the settings, so said: "at 1200 × 1200", or "at full size". */
function coverAt(size: string): string {
  return size === 'full' ? 'at full size' : `at ${size} × ${size}`
}

/** ...as the line says it: " — at 1200 × 1200", or none. */
function coverSize(size: string | undefined): string {
  return size ? ` — ${coverAt(size)}` : ''
}

/** A cover file there: what the tick does to it, and that it is for good (James, 27 Nov: the replace deletes the old
 *  file - its server change is its own commit). */
const COVER_REPLACES = "This album already has a cover. With this on, Apply deletes it and saves this pressing's cover in its place"
const COVER_FOR_GOOD = "It can't be undone."
/** A cover only inside the music files: a file beside them is shown first everywhere, and the files keep theirs
 *  (App Design's words, 27 Nov - before it, and the short form after). */
const COVER_INSIDE = "This album's cover is stored inside its music files."
const COVER_INSIDE_KEPT = 'The files keep theirs, so nothing is lost.'

/**
 * (cover removal) The preview's cover when it speaks for the file there: from a server that names the file a replace
 * deletes (`removes`) - with the tick off too, where it says what a replace WOULD do (its `action` alone says what this
 * Apply does). Null without one - none yet, one from a server from before the removal - when a cover file there is said
 * to go, as before.
 */
function coverPlanned(plan: Pick<RetagPlan, 'art'> | null): RetagArtPlan | null {
  return plan && plan.art.removes !== undefined ? plan.art : null
}

/** (cover removal, final) The preview's cover when a cover file is there that a replace keeps (`removes` null): a link,
 *  or an image under another name (cdart.png). Null when the file goes, or with no preview that says. */
function coverKept(plan: Pick<RetagPlan, 'art'> | null, albumArt: string): RetagArtPlan | null {
  const planned = coverPlanned(plan)
  return coverThere(plan, albumArt) === 'file' && planned && !planned.removes ? planned : null
}

/**
 * The line under the cover box's tick. (Review) Once a preview is in for what the page shows, it follows the preview's
 * cover: asked for and not planned - the release has no id to look a cover up by, or the files join a folder with a
 * cover of its own - it says so, rather than what the tick would do. Otherwise what the tick does, by the cover there:
 * a file replaced (and that it can't be undone), a cover inside the files outshone, or one downloaded - with its size.
 */
export function coverHint(plan: Pick<RetagPlan, 'art' | 'merge'> | null, fetchArt: boolean, albumArt: string): string {
  const there = coverThere(plan, albumArt)
  if (plan && fetchArt && !plan.art.action) {
    if (plan.merge) return 'No cover is saved: the folder these files are joining keeps its own.'
    return there === 'file' ? 'Your cover is kept: this pressing has none to save in its place.' : 'This pressing has no cover to save.'
  }
  const size = coverSize(plan?.art.size)
  //? (cover removal) "deletes it" and "It can't be undone." only where the file goes - said with the tick off too, from
  //? the preview's word for what a replace would do: one that deletes nothing keeps the image there, named - a link
  //? said as one - and the new one is shown instead unless another cover is still the one you see (App Design's words:
  //? the size between commas)
  const kept = coverKept(plan, albumArt)
  if (kept?.removes_refused === 'link') return coverLink(kept.existing)
  if (kept) {
    const at = kept.size ? `, ${coverAt(kept.size)}` : ''
    const instead = coverShownFirst(kept) ? '' : `${at ? ',' : ''} and shown instead`
    return `This folder already has an image (${kept.existing}). This pressing's cover will be saved beside it${at}${instead}. ${COVER_STAYS}`
  }
  if (there === 'file') return `${COVER_REPLACES}${size}. ${COVER_FOR_GOOD}`
  if (there === 'embedded') {
    return `${COVER_INSIDE} This one will be saved beside them${size ? `${size} —` : ''} and shown instead. ${COVER_INSIDE_KEPT}`
  }
  return `From the Cover Art Archive, saved into the album folder${size}`
}

/** Compare covers' button: a cover file that goes is replaced; else - an image a replace keeps, a cover inside the
 *  files, none - this one is saved (App Design, 27 Nov). The cover there as the preview read it, as the tick's words. */
export function coverOnlyLabel(plan: Pick<RetagPlan, 'art'> | null, albumArt: string): string {
  return coverGoes(plan, albumArt) ? 'Replace your cover with this one' : 'Save this cover'
}

/** ...and what it does. (cover removal, final) It has no preview of its own: the retag preview's cover is its preview
 *  (the server plans both from the same listing), so a cover file a replace keeps - a link, an image under another
 *  name - is said so, and "deletes" and "It can't be undone." only where the file goes. Another cover still shown
 *  first is said after: there is no line under a summary here to say it. Without a preview, the scan's cover, as before. */
export function coverOnlyHint(plan: Pick<RetagPlan, 'art'> | null, albumArt: string): string {
  const there = coverThere(plan, albumArt)
  const planned = coverPlanned(plan)
  const warning = there === 'file' && planned ? coverShownFirst(planned) : null
  const after = warning ? ` ${warning}` : ''
  const kept = coverKept(plan, albumArt)
  if (kept?.removes_refused === 'link') return `${coverLink(kept.existing)} Nothing else changes.${after}`
  if (kept) {
    return `This folder already has an image (${kept.existing}). This one will be saved beside it${warning ? '' : ' and shown instead'}. ${COVER_STAYS}${after}`
  }
  if (there === 'file') return `Deletes your current cover and saves this one. Nothing else changes. ${COVER_FOR_GOOD}${after}`
  if (there === 'embedded') return `${COVER_INSIDE} This one will be saved beside them and shown instead. ${COVER_INSIDE_KEPT}`
  return 'Save this cover into the album folder, and change nothing else.'
}

/** What the cover alone did, with no cover file replaced, by the album's `art` before it was saved: beside a cover inside
 *  the files, shown instead, the files keeping theirs; beside a cover file, the file saved; with none, this pressing's
 *  cover, named (App Design's, 27 Nov). */
function coverWritten(written: string | null, albumArt: string): string {
  if (albumArt === 'embedded') return `Saved ${written}. ${COVER_INSIDE} This one is shown instead; the files keep theirs.`
  return albumArt === 'file' ? `Saved ${written}.` : `Saved this pressing's cover (${written}).`
}

/** A cover file there, gone: deleted, or written over. */
function coverReplaced(name: string): string {
  return `Replaced your cover (${name}) with this pressing's.`
}

/** src/retag.py's sentence for a cover still shown before the one just written (remove_replaced_cover), around its name. */
const SHOWN_FIRST_TAIL = " is still shown first - another cover in the album's folder, left as it was"

/**
 * (App Design, 27 Nov) A problem the cover alone's answer gives once the old file is gone, said after "Replaced your
 * cover": another cover still shown first, named from the server's sentence ("saved cover.jpg, but cover.jpeg is still
 * shown first - …") and said as before Apply - "cover.jpeg will still be the cover you see. It isn't removed."; any
 * other, the server's sentence. The name is said as the server gives it, its case as it is on disk, even at the
 * sentence's start (App Design, 27 Nov): on a disk that tells case apart, cover.jpeg and Cover.jpeg are two files.
 */
function stillShownAfter(problem: string, written: string | null): string {
  const head = `saved ${written}, but `
  if (!written || problem.length <= head.length + SHOWN_FIRST_TAIL.length || !problem.startsWith(head)
    || !problem.endsWith(SHOWN_FIRST_TAIL)) return asSentence(problem)
  const name = problem.slice(head.length, problem.length - SHOWN_FIRST_TAIL.length)
  return `${name} will still be the cover you see. It isn't removed.`
}

/**
 * What the cover alone did, from its answer. (cover removal, 27 Nov) "Replaced your cover (…)" only when the old file
 * is gone: the one the answer says it removed, or the very file it wrote over (cover.jpg over cover.jpg - Cover.jpg
 * on a disk that doesn't tell case apart) - and then (App Design, 27 Nov) another cover still shown first said after
 * it, both in that order. With the old one left where it was (a link, a folder with no music of its own, one changed
 * while the new one was fetched), what the answer has to say about it is said instead, in the server's own sentences
 * (each begins "saved cover.jpg"), and never "replaced". A server from before the removal answers no `removed`: then
 * its `replaced`, as before.
 */
export function coverSaved(result: CoverSavedAnswer, albumArt: string): string {
  if (result.removed === undefined) return result.replaced ? coverReplaced(result.replaced) : coverWritten(result.written, albumArt)
  const problems = result.problems ?? []
  const over = !!result.replaced && !!result.written && result.written.toLowerCase() === result.replaced.toLowerCase()
  const gone = result.removed || (over ? result.replaced : null)
  if (gone) return [coverReplaced(gone), ...problems.map((problem) => stillShownAfter(problem, result.written))].join(' ')
  if (problems.length > 0) return problems.map((problem) => asSentence(problem)).join(' ')
  return coverWritten(result.written, albumArt)
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
