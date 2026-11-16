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
  check('...a cover downloaded and the folder renamed; a cover replaced and the files joining the other disc',
    [R.changeSummary(plan({ art: { action: 'download' }, moves: true })), R.changeSummary(plan({ art: { action: 'replace' }, moves: true, merge: true }))],
    ['3 of 12 files would change, the cover would be downloaded, and the folder would be renamed',
      '3 of 12 files would change, the cover would be replaced, and the files would join the other disc'])
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
      'writeFailedWords(results.failed)', 'planningLabel(loadingRelease)', 'moveLabel(plan)', '{ failed: PREVIEW_FAILED }', '{ failed: APPLY_FAILED }'].map((call) => editor.includes(call)),
    Array(11).fill(true))
  check('...and none of their words, nor the helpers, kept there',
    [/would change|Nothing to change\.|Applying, |stays behind|renames the folder once|moved the folder to match|Couldn't write|Couldn't (?:work out|apply) the changes|Fetching the tracklist/.test(editor),
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
