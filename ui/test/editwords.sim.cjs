/**
 * Edit album's words, as pure functions (2.1.30): what the Release tab says of a preview and an apply
 * (lib/retagPlan.ts), what the tag editor says under a field (lib/tagEdit.ts fieldPlaceholder, fieldNote), and the
 * Artwork, Lyrics and Delete tabs' lines (lib/albumEdit.ts). Moved unchanged out of components/MetadataEditor.tsx,
 * components/TrackTagEditor.tsx, app/EditPanel.tsx and components/DeleteAlbumDialog.tsx, so the iPhone app's
 * exporter can run them as they are (its Phase 8, notes/ios-specs/phase8-managing.md on `ios`, section 12).
 *
 * What it pins:
 *
 *  - Each function's words, word for word, from the plain to the awkward: one file and many, one disc and several, a
 *    merge with files left behind, each way an apply pauses, a field emptied, mixed, a disc never tagged, a cover in
 *    the folder, inside the files or none, CD art deadwax saved, every track with lyrics or none, a delete with other
 *    files past the list.
 *  - The components draw them through these functions and constants, and keep none of the words themselves.
 *
 * Run it with:  TMPDIR=<somewhere writable> node ui/test/editwords.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const SRC = path.join(UI, 'src')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-editwords-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/retagPlan.ts', 'src/lib/tagEdit.ts', 'src/lib/albumEdit.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })
const R = require(path.join(OUT, 'lib/retagPlan.js'))
const T = require(path.join(OUT, 'lib/tagEdit.js'))
const E = require(path.join(OUT, 'lib/albumEdit.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` + (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const read = (file) => fs.readFileSync(path.join(SRC, file), 'utf8')
/** A file's code without its comments - so a comment can name the words it no longer says. (These files keep their
 *  line comments on lines of their own, and no string holds a slash-star.) */
const code = (file) => read(file).replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '')

console.log('\nthe Release tab: what Apply will do (lib/retagPlan.ts)')
{
  const plan = (more = {}) => ({
    moves: false, merge: false, merge_detail: null, changed_file_count: 3, file_count: 12,
    art: { action: '', reason: '', existing: null }, rename_wait: 0, rename_by: null, ...more,
  })
  check('while it works: the tracklist, or the changes', [R.planningLabel(true), R.planningLabel(false)], ['Fetching the tracklist…', 'Working out the changes…'])
  check('a preview or an apply that failed, for sayError', [R.PREVIEW_FAILED, R.APPLY_FAILED], ["Couldn't work out the changes.", "Couldn't apply the changes."])
  check('the folder line: Merge into another disc\'s folder, else Folder', [R.moveLabel(plan({ merge: true })), R.moveLabel(plan()), R.moveLabel({})], ['Merge', 'Folder', 'Folder'])
  check('the pause: nothing to say without a move, or with no wait',
    [R.renameWaitWords(plan({ rename_wait: 10, rename_by: 'timer' })), R.renameWaitWords(plan({ moves: true })), R.renameWaitWords(plan({ moves: true, rename_wait: 0, rename_by: 'navidrome' }))],
    [null, null, null])
  check('...waiting for Navidrome, with tags to write: no number - the cap is a ceiling',
    R.renameWaitWords(plan({ moves: true, rename_wait: 90, rename_by: 'navidrome' })),
    "Writes the tags first and renames the folder once Navidrome has scanned them (usually a few seconds), so Navidrome keeps this album's plays, ratings and favourites.")
  check('...a rename held back earlier: the tags on disk already, still waiting for the scan',
    R.renameWaitWords(plan({ moves: true, rename_wait: 90, rename_by: 'navidrome', changed_file_count: 0 })),
    "The tags were written by an earlier apply. Renames the folder once Navidrome has scanned them, so Navidrome keeps this album's plays, ratings and favourites.")
  check('...on the timer: its seconds',
    [R.renameWaitWords(plan({ moves: true, rename_wait: 10, rename_by: 'timer' })), R.renameWaitWords(plan({ moves: true, rename_wait: 5 }))],
    ["Writes the tags first and renames 10s later, so Navidrome keeps this album's plays, ratings and favourites.",
      "Writes the tags first and renames 5s later, so Navidrome keeps this album's plays, ratings and favourites."])
  check('discs named', [R.discWords([2]), R.discWords([1, 2, 3]), R.discWords([])], ['disc 2', 'discs 1, 2, 3', 'disc '])
  const merge = (here, there, kept = []) => plan({ moves: true, merge: true, merge_detail: { into: 'A/B (2000)', discs_here: here, discs_there: there, kept_back: kept } })
  check('a merge: one disc in beside one',
    R.mergeWords(merge([2], [1])), 'Moves disc 2 in beside disc 1, which is already there as the same release, and removes this folder once it is empty.')
  check('...several beside several, two files left behind',
    R.mergeWords(merge([2, 4], [1, 3], ['cover.jpg', 'rip.log'])),
    "Moves discs 2, 4 in beside discs 1, 3, which are already there as the same release, and removes this folder once it is empty. cover.jpg, rip.log stays behind - there's one of that name already.")
  check('...no merge, or one with no detail: nothing', [R.mergeWords(plan()), R.mergeWords(plan({ merge: true })), R.mergeWords({ merge: false, merge_detail: merge([2], [1]).merge_detail })], [null, null, null])
  check('nothing to change', R.NOTHING_TO_CHANGE, 'Nothing to change.')
  check('the summary: files, then the cover and the folder',
    [R.changeSummary(plan()), R.changeSummary(plan({ changed_file_count: 1, file_count: 1 })), R.changeSummary(plan({ changed_file_count: 0 }))],
    ['3 of 12 files would change', '1 of 1 file would change', '0 of 12 files would change'])
  check('...a cover downloaded and the folder renamed; a cover replaced (said on its own line) and the files joining the other disc',
    [R.changeSummary(plan({ art: { action: 'download' }, moves: true })), R.changeSummary(plan({ art: { action: 'replace', existing: 'cover.png' }, moves: true, merge: true }))],
    ['3 of 12 files would change, the cover would be downloaded, and the folder would be renamed',
      '3 of 12 files would change, and the files would join the other disc'])
  //? (cover words, 27 Nov) a cover the folder has: its own line, whether it stays or goes; none with no cover there
  check('the cover\'s line: kept with the box off (or nothing to fetch), replaced with it on; none with no cover there',
    [R.coverLine(plan({ art: { action: '', reason: '', existing: 'cover.jpg' } })),
      R.coverLine(plan({ art: { action: '', reason: 'no release to fetch art for', existing: 'cover.jpg' } })),
      R.coverLine(plan({ art: { action: 'replace', reason: '', existing: 'cover.jpg' } })),
      R.coverLine(plan()), R.coverLine(plan({ art: { action: 'download', reason: '', existing: null } }))],
    ['Your cover is kept.', 'Your cover is kept.', "Your cover will be replaced with this pressing's.", null, null])
  //? (cover words, review) the cover box: a preview's cover when there is one, else the scan's; the line following
  //? the preview - asked for and not planned says so - else what the tick does, by the cover there
  const file = { action: '', reason: '', existing: 'cover.jpg', size: '1200' }
  const none = { action: '', reason: '', existing: null, size: '1200' }
  check('the tick: your cover by the preview, else by the scan; a cover only inside the files, or none, is saved',
    [R.coverToggle(plan({ art: file }), ''), R.coverToggle(plan({ art: none }), 'file'), R.coverToggle(null, 'file'),
      R.coverToggle(null, 'embedded'), R.coverToggle(null, '')],
    ["Replace your cover with this pressing's", "Save this pressing's cover", "Replace your cover with this pressing's",
      "Save this pressing's cover", "Save this pressing's cover"])
  check('...its line, a cover file there: what the tick does (off or on) and its size; before a preview, the scan\'s cover',
    [R.coverHint(plan({ art: file }), false, 'file'), R.coverHint(plan({ art: { ...file, action: 'replace', size: 'full' } }), true, 'file'),
      R.coverHint(null, false, 'file')],
    ["This album already has a cover. With this on, Apply deletes it and saves this pressing's cover in its place — at 1200 × 1200. It can't be undone.",
      "This album already has a cover. With this on, Apply deletes it and saves this pressing's cover in its place — at full size. It can't be undone.",
      "This album already has a cover. With this on, Apply deletes it and saves this pressing's cover in its place. It can't be undone."])
  check('...a cover only inside the files: saved beside them and shown instead, the files keeping theirs; with none, downloaded',
    [R.coverHint(plan({ art: none }), false, 'embedded'), R.coverHint(null, false, 'embedded'), R.coverHint(plan({ art: { ...none, action: 'download' } }), true, '')],
    ["This album's cover is stored inside its music files. This one will be saved beside them — at 1200 × 1200 — and shown instead. The files keep theirs, so nothing is lost.",
      "This album's cover is stored inside its music files. This one will be saved beside them and shown instead. The files keep theirs, so nothing is lost.",
      'From the Cover Art Archive, saved into the album folder — at 1200 × 1200'])
  check('...asked for and not planned: no id to look one up by, or the files join a folder with a cover of its own',
    [R.coverHint(plan({ art: { ...file, reason: 'this release has no MusicBrainz id to look art up by' } }), true, 'file'),
      R.coverHint(plan({ art: none }), true, ''), R.coverHint(plan({ art: file, moves: true, merge: true }), true, 'file'),
      R.coverHint(null, true, 'file')],
    ['Your cover is kept: this pressing has none to save in its place.', 'This pressing has no cover to save.',
      'No cover is saved: the folder these files are joining keeps its own.',
      "This album already has a cover. With this on, Apply deletes it and saves this pressing's cover in its place. It can't be undone."])
  check('Compare covers\' button and its line, before a preview: a cover file replaced, a cover inside the files outshone, else saved',
    ['file', 'embedded', ''].map((art) => [R.coverOnlyLabel(null, art), R.coverOnlyHint(null, art)]),
    [['Replace your cover with this one', "Deletes your current cover and saves this one. Nothing else changes. It can't be undone."],
      ['Save this cover', "This album's cover is stored inside its music files. This one will be saved beside them and shown instead. The files keep theirs, so nothing is lost."],
      ['Save this cover', 'Save this cover into the album folder, and change nothing else.']])
  check('...and what it did: your cover replaced, named; one saved beside the files\' own; one saved beside a cover file; this pressing\'s, with none',
    [R.coverSaved({ written: 'cover.jpg', replaced: 'cover.png' }, 'file'), R.coverSaved({ written: 'cover.jpg', replaced: null }, 'embedded'),
      R.coverSaved({ written: 'cover.jpg', replaced: null }, 'file'), R.coverSaved({ written: 'cover.jpg', replaced: '' }, '')],
    ["Replaced your cover (cover.png) with this pressing's.",
      "Saved cover.jpg. This album's cover is stored inside its music files. This one is shown instead; the files keep theirs.", 'Saved cover.jpg.',
      "Saved this pressing's cover (cover.jpg)."])
  //? (cover removal, 27 Nov) the server names the file a replace deletes (plan.art.removes) and the one it did
  //? (`removed`, with its `problems`): "It can't be undone." and "Replaced your cover" follow them, and an answer from a
  //? server from before - no such fields - keeps the words it had
  const REPLACES = "This album already has a cover. With this on, Apply deletes it and saves this pressing's cover in its place"
  const replacing = { ...file, action: 'replace' }
  check('"deletes it" and "It can\'t be undone." only when the preview says the file goes - with the tick off too (the server\'s final: what a replace WOULD do); before one and from an older server, as before',
    [R.coverHint(plan({ art: { ...replacing, removes: 'cover.jpg' } }), true, 'file'),
      R.coverHint(plan({ art: replacing }), true, 'file'),
      R.coverHint(plan({ art: { ...file, removes: 'cover.jpg' } }), false, 'file'),
      R.coverHint(plan({ art: { ...file, existing: 'cdart.png', removes: null, removes_refused: 'not_a_cover_name', also_covers: [], still_shown_first: [] } }), false, 'file'),
      R.coverHint(plan({ art: file }), false, 'file'),
      R.coverHint(null, true, 'file')],
    [`${REPLACES} — at 1200 × 1200. It can't be undone.`, `${REPLACES} — at 1200 × 1200. It can't be undone.`,
      `${REPLACES} — at 1200 × 1200. It can't be undone.`,
      "This folder already has an image (cdart.png). This pressing's cover will be saved beside it, at 1200 × 1200, and shown instead. The image already there stays.",
      `${REPLACES} — at 1200 × 1200. It can't be undone.`, `${REPLACES}. It can't be undone.`])
  //? (cover removal, review) a replace that deletes nothing - the image there isn't cover-named, or is a link - keeps it
  const keeping = { ...replacing, existing: 'cdart.png', removes: null, removes_refused: 'not_a_cover_name', also_covers: [], still_shown_first: [] }
  check('...a replace that deletes nothing: the image there stays, and the new one is shown instead unless another still is',
    [R.coverHint(plan({ art: keeping }), true, 'file'), R.coverHint(plan({ art: { ...keeping, size: undefined } }), true, 'file'),
      R.coverHint(plan({ art: { ...keeping, still_shown_first: ['cover.jpg'] } }), true, 'file'),
      R.coverLine(plan({ art: keeping })), R.coverLine(plan({ art: { ...keeping, still_shown_first: ['cover.jpg'] } }))],
    ["This folder already has an image (cdart.png). This pressing's cover will be saved beside it, at 1200 × 1200, and shown instead. The image already there stays.",
      "This folder already has an image (cdart.png). This pressing's cover will be saved beside it and shown instead. The image already there stays.",
      "This folder already has an image (cdart.png). This pressing's cover will be saved beside it, at 1200 × 1200. The image already there stays.",
      "This pressing's cover will be shown instead. The image already there (cdart.png) stays.",
      "The image already there stays. cover.jpg will still be the cover you see. It isn't removed."])
  check('...at full size, and without a size, with another cover still the one you see',
    [R.coverHint(plan({ art: { ...keeping, size: 'full' } }), true, 'file'),
      R.coverHint(plan({ art: { ...keeping, size: undefined, still_shown_first: null, also_covers: ['cover.jpeg'] } }), true, 'file')],
    ["This folder already has an image (cdart.png). This pressing's cover will be saved beside it, at full size, and shown instead. The image already there stays.",
      "This folder already has an image (cdart.png). This pressing's cover will be saved beside it. The image already there stays."])
  check('...another cover still shown first, said before Apply: the one known, or - its name unknown - those that may be',
    [R.coverLine(plan({ art: { ...replacing, removes: 'cover.png', also_covers: ['cover.jpeg'], still_shown_first: ['cover.jpeg'] } })),
      R.coverLine(plan({ art: { ...replacing, removes: 'cover.png', also_covers: ['cover.jpeg', 'folder.jpg'], still_shown_first: null } })),
      R.coverLine(plan({ art: { ...replacing, removes: 'cover.png', also_covers: ['cover.jpeg'], still_shown_first: [] } })),
      R.coverLine(plan({ art: { ...replacing, removes: 'cover.png', also_covers: [], still_shown_first: null } })),
      R.coverLine(plan({ art: replacing }))],
    ["Your cover will be replaced with this pressing's. cover.jpeg will still be the cover you see. It isn't removed.",
      "Your cover will be replaced with this pressing's. cover.jpeg or folder.jpg may still be the cover you see.",
      "Your cover will be replaced with this pressing's.", "Your cover will be replaced with this pressing's.",
      "Your cover will be replaced with this pressing's."])
  check('...listed as one, by or',
    [['a'], ['a', 'b'], ['a', 'b', 'c']].map((names) => R.coverShownFirst({ still_shown_first: null, also_covers: names })),
    ['a may still be the cover you see.', 'a or b may still be the cover you see.', 'a, b or c may still be the cover you see.'])
  //? (cover removal, final) a link the server won't remove: why it stays, never "deletes" or "can't be undone" - under
  //? the tick (off or on), under the summary (with another cover still shown first after it) and in Compare covers
  const linking = { ...replacing, existing: 'folder.jpg', removes: null, removes_refused: 'link', also_covers: [], still_shown_first: [] }
  const LINKED = 'Your cover (folder.jpg) is a link to somewhere else, so it stays.'
  const linkWords = [R.coverHint(plan({ art: linking }), true, 'file'), R.coverHint(plan({ art: { ...linking, action: '' } }), false, 'file'),
    R.coverLine(plan({ art: linking })), R.coverLine(plan({ art: { ...linking, also_covers: ['cover.jpeg'], still_shown_first: ['cover.jpeg'] } })),
    R.coverOnlyHint(plan({ art: linking }), 'file'), R.coverOnlyHint(plan({ art: { ...linking, action: '' } }), '')]
  check('a cover that is a link: it stays, said why, wherever the cover is said',
    linkWords, [LINKED, LINKED, LINKED, `${LINKED} cover.jpeg will still be the cover you see. It isn't removed.`,
      `${LINKED} Nothing else changes.`, `${LINKED} Nothing else changes.`])
  check('...and none of them says it deletes, or that it can\'t be undone', linkWords.some((line) => /delet|undone/i.test(line)), false)
  check('Compare covers, its preview the retag preview\'s cover: the file goes (and another may still be shown); kept under another name; none there; an older server',
    [R.coverOnlyHint(plan({ art: { ...file, removes: 'cover.jpg', also_covers: [], still_shown_first: [] } }), 'file'),
      R.coverOnlyHint(plan({ art: { ...file, existing: 'Cover.jpg', removes: 'Cover.jpg', also_covers: ['cover.jpeg'], still_shown_first: ['cover.jpeg'] } }), 'file'),
      R.coverOnlyHint(plan({ art: keeping }), 'file'), R.coverOnlyHint(plan({ art: { ...keeping, action: '' } }), 'embedded'),
      R.coverOnlyHint(plan({ art: { ...keeping, still_shown_first: ['cover.gif'] } }), 'file'),
      R.coverOnlyLabel(plan({ art: keeping }), ''), R.coverOnlyLabel(plan({ art: none }), 'file'), R.coverOnlyHint(plan({ art: none }), 'file'),
      R.coverOnlyHint(plan({ art: file }), 'file')],
    ["Deletes your current cover and saves this one. Nothing else changes. It can't be undone.",
      "Deletes your current cover and saves this one. Nothing else changes. It can't be undone. cover.jpeg will still be the cover you see. It isn't removed.",
      'This folder already has an image (cdart.png). This one will be saved beside it and shown instead. The image already there stays.',
      'This folder already has an image (cdart.png). This one will be saved beside it and shown instead. The image already there stays.',
      'This folder already has an image (cdart.png). This one will be saved beside it. The image already there stays. cover.gif will still be the cover you see. It isn\'t removed.',
      'Save this cover', 'Save this cover', 'Save this cover into the album folder, and change nothing else.',
      "Deletes your current cover and saves this one. Nothing else changes. It can't be undone."])
  const shownFirst = "saved cover.jpg, but cover.jpeg is still shown first - another cover in the album's folder, left as it was"
  const linked = "saved cover.jpg, but the old folder.jpg is a link to somewhere else, which deadwax won't remove"
  check('...what the cover alone did, from a server that removes the old cover: replaced only once it is gone - removed, or written over',
    [R.coverSaved({ written: 'cover.jpg', replaced: 'folder.jpg', removed: 'folder.jpg', problems: [] }, 'file'),
      R.coverSaved({ written: 'cover.jpg', replaced: 'folder.jpg', removed: 'folder.jpg' }, 'file'),
      R.coverSaved({ written: 'cover.jpg', replaced: 'cover.jpg', removed: null, problems: [] }, 'file'),
      R.coverSaved({ written: 'cover.jpg', replaced: 'Cover.jpg', removed: null, problems: [] }, 'file'),
      R.coverSaved({ written: 'cover.png', replaced: 'cover.jpg', removed: null, problems: [] }, 'file'),
      R.coverSaved({ written: 'cover.jpg', replaced: null, removed: null, problems: [] }, 'embedded'),
      R.coverSaved({ written: 'cover.jpg', replaced: null, removed: null, problems: [] }, '')],
    ["Replaced your cover (folder.jpg) with this pressing's.", "Replaced your cover (folder.jpg) with this pressing's.",
      "Replaced your cover (cover.jpg) with this pressing's.", "Replaced your cover (Cover.jpg) with this pressing's.", 'Saved cover.png.',
      "Saved cover.jpg. This album's cover is stored inside its music files. This one is shown instead; the files keep theirs.",
      "Saved this pressing's cover (cover.jpg)."])
  //? (App Design, 27 Nov) the old one gone and another still shown first: both said, the replace first, the other cover
  //? named from the server's sentence and said as before Apply - its name as the server gives it, even at the
  //? sentence's start (App Design: on a disk that tells case apart, cover.jpeg and Cover.jpeg are two files)
  check('...the old one gone - removed, or written over - and another still shown first: both, in that order',
    [R.coverSaved({ written: 'cover.jpg', replaced: 'folder.jpg', removed: 'folder.jpg', problems: [shownFirst] }, 'file'),
      R.coverSaved({ written: 'cover.jpg', replaced: 'cover.jpg', removed: null, problems: [shownFirst] }, 'file'),
      R.coverSaved({ written: 'cover.png', replaced: 'cover.png', removed: 'cover.png',
        problems: ["saved cover.png, but Cover.gif is still shown first - another cover in the album's folder, left as it was"] }, 'file')],
    ["Replaced your cover (folder.jpg) with this pressing's. cover.jpeg will still be the cover you see. It isn't removed.",
      "Replaced your cover (cover.jpg) with this pressing's. cover.jpeg will still be the cover you see. It isn't removed.",
      "Replaced your cover (cover.png) with this pressing's. Cover.gif will still be the cover you see. It isn't removed."])
  check('...the name\'s case kept as it is on disk: cover.jpeg stays lower case, Cover.jpeg keeps its capital',
    ['cover.jpeg', 'Cover.jpeg'].map((shown) => R.coverSaved({ written: 'cover.jpg', replaced: 'Cover.jpg', removed: 'Cover.jpg',
      problems: [`saved cover.jpg, but ${shown} is still shown first - another cover in the album's folder, left as it was`] }, 'file')),
    ["Replaced your cover (Cover.jpg) with this pressing's. cover.jpeg will still be the cover you see. It isn't removed.",
      "Replaced your cover (Cover.jpg) with this pressing's. Cover.jpeg will still be the cover you see. It isn't removed."])
  check('...a sentence that isn\'t that one, or names another file written, said as the server says it after "Replaced"',
    [R.coverSaved({ written: 'cover.jpg', replaced: 'folder.jpg', removed: 'folder.jpg', problems: ['something else went wrong'] }, 'file'),
      R.coverSaved({ written: 'cover.png', replaced: 'folder.jpg', removed: 'folder.jpg', problems: [shownFirst] }, 'file'),
      R.coverSaved({ written: 'cover.jpg', replaced: 'folder.jpg', removed: 'folder.jpg',
        problems: ["saved cover.jpg, but  is still shown first - another cover in the album's folder, left as it was"] }, 'file')],
    ["Replaced your cover (folder.jpg) with this pressing's. Something else went wrong.",
      "Replaced your cover (folder.jpg) with this pressing's. Saved cover.jpg, but cover.jpeg is still shown first - another cover in the album's folder, left as it was.",
      "Replaced your cover (folder.jpg) with this pressing's. Saved cover.jpg, but  is still shown first - another cover in the album's folder, left as it was."])
  check('...the old one left where it was: what the answer has to say, said instead, never "replaced"',
    [R.coverSaved({ written: 'cover.jpg', replaced: 'folder.jpg', removed: null, problems: [linked, shownFirst] }, 'file'),
      R.coverSaved({ written: 'cover.png', replaced: 'cover.jpg', removed: null, problems: [shownFirst] }, 'file')],
    ["Saved cover.jpg, but the old folder.jpg is a link to somewhere else, which deadwax won't remove. Saved cover.jpg, but cover.jpeg is still shown first - another cover in the album's folder, left as it was.",
      "Saved cover.jpg, but cover.jpeg is still shown first - another cover in the album's folder, left as it was."])
  //? (cover removal, final) src/retag.py's own sentences for an old cover left where it was: a folder with no music of
  //? its own (the cover alone's alone - a retag refuses such a folder), one changed since the plan, one already gone; and
  //? an image under another name, kept, with nothing to say
  const noMusic = "saved cover.jpg, but the old front.jpg was left where it is - the folder holds no music of its own, so it isn't taken for an album"
  const changed = 'saved cover.jpg, but the old folder.jpg was left where it is - it changed while the new cover was being fetched'
  const gone = 'saved cover.jpg - the old folder.jpg was already gone, so there was nothing to remove'
  const leftWords = [noMusic, changed, gone].map((line) => R.coverSaved({ written: 'cover.jpg', replaced: 'folder.jpg', removed: null, problems: [line] }, 'file'))
  check('...the server\'s own sentence for a cover left where it was - no music in the folder, changed, already gone - and a kept image saved beside',
    [...leftWords, R.coverSaved({ written: 'cover.jpg', replaced: 'cdart.png', removed: null, problems: [] }, 'file')],
    ["Saved cover.jpg, but the old front.jpg was left where it is - the folder holds no music of its own, so it isn't taken for an album.",
      'Saved cover.jpg, but the old folder.jpg was left where it is - it changed while the new cover was being fetched.',
      'Saved cover.jpg - the old folder.jpg was already gone, so there was nothing to remove.', 'Saved cover.jpg.'])
  check('...never "Replaced"', leftWords.some((line) => /[Rr]eplaced/.test(line)), false)
  //? (App Design, 27 Nov) the labels say "Replace" only where the file goes - named as removed (or written over), or
  //? no preview that says - and never beside a line that says the old one stays
  const goes = { ...file, removes: 'cover.jpg', also_covers: [], still_shown_first: [] }
  const outsideAlbum = { ...keeping, existing: 'front.jpg', removes_refused: 'not_an_album' }
  const labelled = [goes, { ...goes, action: 'replace' }, keeping, { ...keeping, action: '' }, linking, { ...linking, action: '' }, outsideAlbum]
  check('the tick and Compare covers\' button: "Replace" where the file goes, "Save" where it stays (kept, a link, no music)',
    labelled.map((art) => [R.coverToggle(plan({ art }), 'file'), R.coverOnlyLabel(plan({ art }), 'file')]),
    [["Replace your cover with this pressing's", 'Replace your cover with this one'], ["Replace your cover with this pressing's", 'Replace your cover with this one'],
      ["Save this pressing's cover", 'Save this cover'], ["Save this pressing's cover", 'Save this cover'],
      ["Save this pressing's cover", 'Save this cover'], ["Save this pressing's cover", 'Save this cover'],
      ["Save this pressing's cover", 'Save this cover']])
  check('...no label says "Replace" beside a line that says the old one stays',
    labelled.flatMap((art) => [[R.coverToggle(plan({ art }), 'file'), R.coverHint(plan({ art }), true, 'file')],
      [R.coverToggle(plan({ art }), 'file'), R.coverHint(plan({ art }), false, 'file')],
      [R.coverOnlyLabel(plan({ art }), 'file'), R.coverOnlyHint(plan({ art }), 'file')]])
      .some(([label, line]) => /Replace/.test(label) && /stays/.test(line)), false)
  check('Apply while it works: plain, waiting for Navidrome (no number), or its seconds',
    [R.applyingLabel(null), R.applyingLabel(plan()), R.applyingLabel(plan({ rename_wait: 90, rename_by: 'navidrome' })), R.applyingLabel(plan({ rename_wait: 10, rename_by: 'timer' }))],
    ['Applying', 'Applying', 'Applying, waiting for Navidrome', 'Applying, renaming in 10s'])
}

console.log('\nthe Release tab: what an apply did')
{
  const results = (more = {}) => ({ tagged: 0, art_written: null, merged: false, moved_to: null, ...more })
  check('everything it did, in one sentence',
    R.appliedWords(results({ tagged: 12, art_written: 'cover.jpg', moved_to: 'Portishead/Dummy (1994)' })),
    'Updated the tags in 12 files, saved cover.jpg, moved the folder to match its tags.')
  check('...a merge said as one, whatever moved_to says', R.appliedWords(results({ tagged: 1, merged: true, moved_to: 'x' })), 'Updated the tags in 1 file, moved it in beside the other discs.')
  check('...only the folder: no "0 files"', [R.appliedWords(results({ moved_to: 'x' })), R.appliedWords(results({ art_written: 'folder.jpg' }))],
    ['Moved the folder to match its tags.', 'Saved folder.jpg.'])
  check('...nothing at all, as it always said', R.appliedWords(results()), '.')
  check('files it couldn\'t write', [R.writeFailedWords(1), R.writeFailedWords(3)], ["Couldn't write 1 file.", "Couldn't write 3 files."])
}

console.log('\nthe tag editor: under each field (lib/tagEdit.ts)')
{
  const one = (value) => ({ value, mixed: false })
  const MIXED = { value: '', mixed: true }
  check('emptying a field removes the tag - only where there is one',
    [T.removesTag(one('Rock'), ''), T.removesTag(one('Rock'), '   '), T.removesTag(MIXED, ''), T.removesTag(one(''), ''), T.removesTag(one('Rock'), undefined), T.removesTag(one('Rock'), 'Pop')],
    [true, true, true, false, false, false])
  check('the placeholder: Several values over files that disagree, untouched; a disc\'s 1; else Not set',
    [T.fieldPlaceholder('genre', MIXED, false), T.fieldPlaceholder('genre', MIXED, true), T.fieldPlaceholder('discnumber', MIXED, true),
      T.fieldPlaceholder('discnumber', one(''), false), T.fieldPlaceholder('title', one(''), false), T.fieldPlaceholder('title', one('Roads'), true)],
    ['Several values', 'Not set', '1', '1', 'Not set', 'Not set'])
  check('the note: a problem as typed first',
    T.fieldNote('date', one('1994'), 'July 2022', T.tagProblem('date', 'July 2022')), 'Has to be a year or a date, like 2022 or 2022-07-29')
  check('...then a removal, then files that disagree left alone, then a disc never tagged',
    [T.fieldNote('genre', one('Rock'), '', null), T.fieldNote('genre', MIXED, undefined, null), T.fieldNote('discnumber', one(''), undefined, null)],
    ['Will be removed', 'Differs between tracks - left alone, each keeps its own', 'Not tagged - reads as disc 1'])
  check('...nothing for a field as the files have it, or typed over',
    [T.fieldNote('genre', one('Rock'), undefined, null), T.fieldNote('genre', MIXED, 'Trip hop', null), T.fieldNote('discnumber', one('2'), undefined, null),
      T.fieldNote('discnumber', one(''), '2', null), T.fieldNote('genre', one(''), '', null)],
    [null, null, null, null, null])
  check('...a mixed field emptied is a removal, not "differs"', T.fieldNote('genre', MIXED, '', null), 'Will be removed')
}

console.log('\nthe Artwork and Lyrics tabs, and Delete (lib/albumEdit.ts)')
{
  check('the cover the folder has', [E.coverNote('file'), E.coverNote('embedded'), E.coverNote('')],
    ['A cover is saved beside the tracks.', 'The cover is inside the files, with none beside them.', 'No cover is saved with the album.'])
  check('...the viewer with none to show', E.COVER_MISSING, 'No cover on disk, and none on the Cover Art Archive for this release')
  check('under Get cover: a release first; replacing it in the Release tab; else nothing',
    [E.coverPointer({ release_mbid: '', art: '' }), E.coverPointer({ release_mbid: '', art: 'file' }), E.coverPointer({ release_mbid: 'r1', art: 'embedded' }), E.coverPointer({ release_mbid: 'r1', art: '' })],
    ['To get a cover, first match the album to a release in the Release tab.', 'To get a cover, first match the album to a release in the Release tab.',
      "To replace it, compare it with the release's in the Release tab (Compare full size…).", null])
  check('CD art: over the pictures, or in their place', [E.DISC_ART_BESIDE, E.NO_DISC_ART],
    ['Beside the tracks - what players show for a song with a disc number:', 'No picture of the disc beside the tracks.'])
  check('under Get CD art: a release first; deadwax\'s own never replaced (disc*, any case); else nothing',
    [E.discArtPointer({ release_mbid: '', disc_art: ['disc.jpg'] }), E.discArtPointer({ release_mbid: 'r1', disc_art: ['disc.jpg'] }),
      E.discArtPointer({ release_mbid: 'r1', disc_art: ['cd.png', 'Disc2.PNG'] }), E.discArtPointer({ release_mbid: 'r1', disc_art: ['cd.png'] }),
      E.discArtPointer({ release_mbid: 'r1', disc_art: [] }), E.discArtPointer({ release_mbid: 'r1' })],
    ['To get CD art, first match the album to a release in the Release tab.', 'deadwax never replaces CD art it saved.', 'deadwax never replaces CD art it saved.', null, null, null])
  check('Lyrics: how many of how many, one track and many',
    [E.lyricsLine(8, 12), E.lyricsLine(0, 1), E.lyricsLine(1, 1), E.lyricsLine(0, 0)],
    ['8 of 12 tracks have lyrics saved beside them, as a .lrc.', '0 of 1 track has lyrics saved beside it, as a .lrc.',
      '1 of 1 track has lyrics saved beside it, as a .lrc.', '0 of 0 tracks have lyrics saved beside them, as a .lrc.'])
  check('...every track with lyrics said, as the count reaches the tracks (none of none too)',
    [E.allLyricsNote({ lyrics_count: 12, track_count: 12 }), E.allLyricsNote({ lyrics_count: 13, track_count: 12 }), E.allLyricsNote({ lyrics_count: 11, track_count: 12 }), E.allLyricsNote({ lyrics_count: 0, track_count: 0 })],
    ['Every track has lyrics.', 'Every track has lyrics.', null, 'Every track has lyrics.'])
  check('...and where re-timing is', E.RETIME_POINTER, 'To shift when synced lyrics appear, or re-time the ones already saved, see Lyrics in Server settings (Library).')
  check('Delete: its title, its wait, its failures', [E.DELETE_TITLE, E.DELETE_CHECKING, E.DELETE_READ_FAILED, E.DELETE_FAILED],
    ['Delete this album?', "Checking what's in there…", "Couldn't read that folder.", "Couldn't delete it."])
  check('...what goes: tracks and the size',
    [E.deleteCounts({ audio_files: 1, total_bytes: 0 }), E.deleteCounts({ audio_files: 12, total_bytes: 300 * 1024 * 1024 }), E.deleteCounts({ audio_files: 0, total_bytes: 2.5 * 1024 ** 3 })],
    ['1 track', '12 tracks · 300 MB', '0 tracks · 2.5 GB'])
  check('...the other files by name, and more than it lists',
    [E.deleteOthers({ other_file_count: 0, other_files: [] }), E.deleteOthers({ other_file_count: 1, other_files: ['rip.log'] }),
      E.deleteOthers({ other_file_count: 4, other_files: ['a.cue', 'b.log'] }), E.deleteOthers({ other_file_count: 2, other_files: [] })],
    [null, { lead: 'and 1 other file:', names: 'rip.log' }, { lead: 'and 4 other files:', names: 'a.cue, b.log, …' },
      //? by the count, as the dialog always went - a list that names none still says there are some
      { lead: 'and 2 other files:', names: ', …' }])
  check('...the warning and the button', [E.DELETE_WARNING, E.DELETE_CONFIRM, E.DELETING],
    ['This deletes the folder and everything in it, permanently. There is no undo.', 'Delete permanently', 'Deleting…'])
}

console.log('\nthe editors draw them, and keep none of the words themselves')
{
  const editor = code('components/MetadataEditor.tsx')
  const tags = code('components/TrackTagEditor.tsx')
  const panel = code('app/EditPanel.tsx')
  const dialog = code('components/DeleteAlbumDialog.tsx')
  check('the release editor: each line through lib/retagPlan.ts',
    ['renameWaitWords(plan)', 'mergeWords(plan)', '{NOTHING_TO_CHANGE}', 'changeSummary(plan)', 'applyingLabel(plan)', 'appliedWords(results)',
      'writeFailedWords(results.failed)', 'planningLabel(loadingRelease)', 'moveLabel(plan)', '{ failed: PREVIEW_FAILED }', '{ failed: APPLY_FAILED }',
      '{coverLine(plan)}', '{coverToggle(coverPlan, album.art)}', '{coverHint(coverPlan, fetchArt, album.art)}',
      'title={coverOnlyHint(coverPlan, album.art)}', ': coverOnlyLabel(coverPlan, album.art)}', 'setArtResult(coverSaved(result, album.art))',
      'const coverPlan = planning ? null : plan'].map((call) => editor.includes(call)),
    Array(18).fill(true))
  check('...and none of their words, nor the helpers, kept there',
    [/would change|Nothing to change\.|Applying, |stays behind|renames the folder once|moved the folder to match|Couldn't write|Couldn't (?:work out|apply) the changes|Fetching the tracklist|Your cover (?:is kept|will be replaced)|[Yy]our cover|Download cover art|saved into the album folder|cover only|music files|It can't be undone|is a link to somewhere|already has an image|Saved \$\{/.test(editor),
      /function (?:discWords|applyingLabel)\b/.test(editor)],
    [false, false])
  check('the tag editor: the placeholder and the note through lib/tagEdit.ts, and none of their words',
    [tags.includes('fieldPlaceholder(field.key, shared, edited)'), tags.includes('fieldNote(field.key, shared, draft, problem)'),
      /Several values|Will be removed|Differs between tracks|reads as disc 1|'Not set'/.test(tags)],
    [true, true, false])
  check('the Artwork and Lyrics tabs: through lib/albumEdit.ts, and none of their words',
    ['coverNote(album.art)', 'coverPointer(album)', 'discArtPointer(album)', '{DISC_ART_BESIDE}', '{NO_DISC_ART}', 'missing: COVER_MISSING',
      'lyricsLine(album.lyrics_count, album.track_count)', 'allLyricsNote(album)', '{RETIME_POINTER}'].map((call) => panel.includes(call)).concat(
      /cover is saved|inside the files|first match the album|To replace it|never replaces CD art|picture of the disc|Beside the tracks|lyrics saved beside|Every track has lyrics|re-time the ones/.test(panel)),
    Array(9).fill(true).concat(false))
  check('Delete: through lib/albumEdit.ts, and none of its words',
    ['{DELETE_TITLE}', 'label={DELETE_CHECKING}', '{ failed: DELETE_READ_FAILED }', '{ failed: DELETE_FAILED }', 'deleteCounts(summary)', 'deleteOthers(summary)',
      '{DELETE_WARNING}', 'label={DELETING}', ': DELETE_CONFIRM'].map((call) => dialog.includes(call)).concat(
      /Delete this album|what's in there|read that folder|delete it\.|other file|There is no undo|Delete permanently|Deleting…/.test(dialog)),
    Array(9).fill(true).concat(false))
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
