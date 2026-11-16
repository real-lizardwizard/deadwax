#!/usr/bin/env node
/**
 * The iPhone app's Edit album, its other parts (Phase 8, slices 2-4 - notes/ios-specs/phase8-managing.md 3.4-3.6):
 * Tags - the fields, what a selection holds in each, the edits sent, what a value can't be, the line under a field, a
 * track's number, and a track's page (lib/tagEdit.ts, lib/trackInspector.ts over lib/trackFields.ts, lib/albumEdit.ts
 * trackLabel) - with the words components/TrackTagEditor.tsx and app/EditPanel.tsx's TagsList say, read out of their
 * sources by pattern; and Artwork and Lyrics (slice 3) - lib/getResults.ts and lib/lyrics.ts run over made errors and
 * summaries, albumEdit.ts's lines over made folders, and components/LibraryParts.tsx's three Get buttons (when each is
 * drawn, its words) read by pattern; written as a fixture the Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/
 * TagEdit.swift, TrackInspector.swift, GetResults.swift) replays in Tests/DeadwaxCoreTests/EditPartsVectorTests.swift.
 *
 * Compiles the libraries with the repo's TypeScript and runs them AS THEY ARE over made inputs, plain to awkward (a
 * value with JavaScript's own white space round it, digits that aren't ASCII, a date of "July 2022", 1000 characters
 * and 1001, a tag two files spell the same but with different code points, a file with no tags at all). Words the
 * components write inline are found by pattern - an expression stripped of its types by TypeScript's own transpiler
 * and evaluated as written, or a sentence's pieces put together as the JSX puts them. A pattern that no longer
 * matches stops this script, naming what moved.
 *
 * The phone has no scan copy of a track (it asks the scan without its tracks, server 2.1.28), so a track's page is
 * the file read just now and nothing else: the registry is handed a track made of the file's own number, disc,
 * length, format, size and name - what the web shows of a track once its file has been read.
 *
 * Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/edit/edit-parts-vectors.json. The file names each source it
 * was made from with its sha256, so ui/test/iosedit.sim.cjs - which runs this with --check, beside
 * export-edit-vectors.cjs - fails when one changes, until the fixture is written again and the Swift port follows.
 * The output is plain ASCII (anything else as a \u escape), so a run on any machine writes the same bytes. Never edit
 * the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-edit-parts-vectors.cjs           write the fixture
 *   node ios/scripts/export-edit-parts-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'edit', 'edit-parts-vectors.json')
const CHECK = process.argv.includes('--check')
const MADE_BY = 'ios/scripts/export-edit-parts-vectors.cjs'
const SOURCES = ['lib/tagEdit.ts', 'lib/trackInspector.ts', 'lib/trackFields.ts', 'lib/format.ts', 'lib/libraryTree.ts',
  'lib/albumEdit.ts', 'lib/errorWords.ts', 'lib/getResults.ts', 'lib/lyrics.ts']
const EDITOR = 'components/TrackTagEditor.tsx'
const PANEL = 'app/EditPanel.tsx'

const sha256 = (body) => crypto.createHash('sha256').update(body).digest('hex')
const source = (file) => fs.readFileSync(path.join(UI, 'src', file), 'utf8')
const madeFrom = Object.fromEntries(SOURCES.map((file) => [`ui/src/${file}`, sha256(source(file))]))

/** A piece read out of a source by `pattern`: its match, hashed - the script stops when it is gone. */
function piece(file, pattern, what) {
  const found = pattern.exec(source(file))
  if (!found) throw new Error(`couldn't read ${what} out of ui/src/${file} - the web app's code moved; change this script with it`)
  madeFrom[`ui/src/${file} ${what}`] = sha256(found[0])
  return found
}

/** A sentence the component says as written, hashed with what it is - the script stops when it is gone. */
function says(file, text, what) {
  if (!source(file).includes(text)) throw new Error(`ui/src/${file} no longer says ${JSON.stringify(text)} (${what})`)
  madeFrom[`ui/src/${file} ${what}`] = sha256(text)
  return text
}

/* ===== the web's code, compiled ===== */

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-edit-parts-vectors-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES.map((file) => `src/${file}`),
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const Tag = require(path.join(OUT, 'lib/tagEdit.js'))
const TI = require(path.join(OUT, 'lib/trackInspector.js'))
const E = require(path.join(OUT, 'lib/albumEdit.js'))
const W = require(path.join(OUT, 'lib/errorWords.js'))
const F = require(path.join(OUT, 'lib/format.js'))
const ts = require(path.join(UI, 'node_modules/typescript'))

/** A TypeScript expression or body, its types stripped by TypeScript itself, as a function of `names`. */
function compiled(names, body) {
  const js = ts.transpileModule(`module.exports = function (${names.join(', ')}) {\n${body}\n}`, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
  }).outputText
  const module = { exports: null }
  new Function('module', 'exports', js)(module, module.exports)
  return module.exports
}

let seed = 8330
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const between = (low, high) => low + Math.floor(rand() * (high - low + 1))
const chance = (p) => rand() < p

/* ===== Tags: TrackTagEditor.tsx's and TagsList's own words ===== */

//? the list's button and its line, as EditPanel's TagsList writes them
const editTracksOf = compiled(['count'], `return (${piece(PANEL, /\{(count \? `Edit \$\{count\} track\$\{count === 1 \? '' : 's'\}\u2026` : 'Edit all tracks\u2026')\}/, 'the Edit tracks button')[1]})`)
const selectedOf = compiled(['count', 'tracks'], `return (${piece(PANEL, /\{count \? (`\$\{count\} of \$\{tracks\.length\} selected`) : sheet/, 'the selected line')[1]})`)
const selectNote = piece(PANEL, /: sheet \? "(Select tracks to edit only those\. Tap a track's name to see everything in its file\.)"/, "the sheet's line")[1]
const selectAll = piece(PANEL, /aria-label=\{all \? '(Deselect every track)' : '(Select every track)'\}/, 'select every track')

//? the editor's sentences, put together as the JSX puts them
says(EDITOR, 'Only the fields you change are written{single ? \'\' : \', to every track above\'}.', 'the hint, its first sentence')
says(EDITOR, "{single ? '' : ' A field showing several values keeps each track\u2019s own unless you type over it.'}", 'the hint, the several values')
says(EDITOR, "{' '}Empty a field to remove that tag. No file is renamed and the folder stays where\n              it is - the Release tab moves an album's folder to where its tags say it belongs.", 'the hint, the rest')
const hintOf = (single) => `Only the fields you change are written${single ? '' : ', to every track above'}.`
  + (single ? '' : ' A field showing several values keeps each track\u2019s own unless you type over it.')
  + " Empty a field to remove that tag. No file is renamed and the folder stays where it is - the Release tab moves an album's folder to where its tags say it belongs."
const fixFirstOf = compiled(['problemCount'], `return \`Fix the marked field\${${piece(EDITOR, /Fix the marked field\{(problemCount === 1 \? '' : 's')\} first\./, 'fix the marked fields')[1]}} first.\``)
const nothingOf = compiled(['single'], `return \`Nothing to change - \${${piece(EDITOR, /Nothing to change - \{(single \? 'the track already says' : 'every track already says')\} that\./, 'nothing to change')[1]}} that.\``)
says(EDITOR, '{plan.changed_file_count} of {filesWord(plan.file_count)} would change', 'would change')
const wouldChangeOf = (plan) => `${plan.changed_file_count} of ${F.filesWord(plan.file_count)} would change`
const headingOf = compiled(['single', 'files', 'filenames'], `return (${piece(EDITOR, /const heading = (single\n\s*\? \(files\[0\]\?\.tags\['title'\] \?\? filenames\[0\] \?\? 'one track'\)\n\s*: `\$\{filenames\.length\} tracks`)/, 'the heading')[1]})`)
says(EDITOR, '<summary>Editing these {filenames.length} tracks</summary>', 'editing these')
//? what an apply says: "Saved 3 files." and each problem as a sentence, a file's name kept as it is on disk
says(EDITOR, 'const sentence = useMemo(() => asSentenceKeeping(filenames), [filenames])', 'the sentences keep file names')
says(EDITOR, '`Saved ${filesWord(results.written)}.`,\n        ...results.problems.map(sentence),\n      ].join(\' \')', 'saved')
says(EDITOR, 'if (results.failed) setError(said)', 'saved, failed')
const savedOf = (results, filenames) => ({
  text: [`Saved ${F.filesWord(results.written)}.`, ...results.problems.map(W.asSentenceKeeping(filenames))].join(' '),
  failed: Boolean(results.failed),
})
says(EDITOR, 'disabled={\n            !plan || plan.empty || plan.problems.length > 0 || planning || applying || problemCount > 0\n          }', 'Apply off')
const canApplyOf = (plan, planning, applying, problems) => !(!plan || plan.empty || plan.problems.length > 0 || planning || applying || problems > 0)

const tagWords = {
  readingFiles: piece(EDITOR, /<LoadingPanel label="(Reading the files\u2026)" \/>/, 'reading the files')[1],
  previewFailed: piece(EDITOR, /\{ failed: ("Couldn't work out the changes\.") \}/, 'the preview failed')[1].slice(1, -1),
  applyFailed: piece(EDITOR, /\{ failed: ("Couldn't save the tags\.") \}/, 'the apply failed')[1].slice(1, -1),
  readFailed: piece('hooks/useTrackDetails.ts', /\{ failed: ("Couldn't read the files\.") \}/, 'the files unread')[1].slice(1, -1),
  whatWouldChange: piece(EDITOR, /<h4 class="tags-preview-title">(What would change)<\/h4>/, 'what would change')[1],
  changeAField: piece(EDITOR, /tags-status">(Change a field to see what would be written\.)<\/p>/, 'change a field')[1],
  working: piece(EDITOR, /<Loading label="(Working out the changes\u2026)" \/>/, 'working')[1],
  saving: piece(EDITOR, /<Loading label="(Saving\u2026)" \/>/, 'saving')[1],
  apply: piece(EDITOR, /: '(Apply)'\}/, 'Apply')[1],
  undo: piece(EDITOR, /\n\s*(Undo)\n\s*<\/button>/, 'Undo')[1],
  undoHint: piece(EDITOR, /title="(Put back what the files say)"/, 'Undo, its hint')[1],
  removed: piece(EDITOR, /\{change\.to \|\| '(removed)'\}/, 'removed')[1],
  none: piece(EDITOR, /\{change\.from \|\| '(\u2014)'\}/, 'none')[1],
  title: piece(EDITOR, /aria-label="(Edit tags)"/, 'Edit tags')[1],
  selectNote,
  selectAll: selectAll[2],
  deselectAll: selectAll[1],
  hint: [true, false].map((single) => ({ single, words: hintOf(single) })),
  fixFirst: [0, 1, 2, 5].map((count) => ({ count, words: fixFirstOf(count) })),
  nothing: [true, false].map((single) => ({ single, words: nothingOf(single) })),
  editTracks: [0, 1, 2, 3, 12, 99].map((count) => ({ count, words: editTracksOf(count) })),
  selected: [[1, 1], [1, 12], [3, 12], [0, 12]].map(([count, total]) => ({ count, total, words: selectedOf(count, { length: total }) })),
  editingThese: [2, 12].map((count) => ({ count, words: `Editing these ${count} tracks` })),
}

/* ===== Tags: tagEdit.ts ===== */

const SPACES = [' ', '\t', '\n', '\u00a0', '\u2003', '\ufeff', '\u3000', '\u0085', '\u200b']
const VALUES = ['Rock', 'rock', 'Rock ', '', '\u00c9lectronique', 'E\u0301lectronique', 'Hip-Hop; Jazz', '2022', '3', '3/12', '\u03a9']

function files() {
  const count = between(0, 4)
  const keys = Tag.EDIT_FIELDS.map((field) => field.key)
  return Array.from({ length: count }, (_, at) => {
    const tags = {}
    for (const key of keys) if (chance(0.6)) tags[key] = chance(0.5) ? 'Same' : pick(VALUES)
    return { filename: `${String(at + 1).padStart(2, '0')} - Track.flac`, tags }
  })
}

function shared() {
  const out = []
  const keys = [...Tag.EDIT_FIELDS.map((field) => field.key), 'conductor']
  const fixed = [
    [], [{ tags: {} }], [{ tags: { genre: 'Rock' } }, { tags: { genre: 'Rock' } }],
    [{ tags: { genre: 'Rock' } }, { tags: {} }], [{ tags: { genre: '' } }, { tags: {} }],
    [{ tags: { genre: '\u00c9lectronique' } }, { tags: { genre: 'E\u0301lectronique' } }],
    [{ tags: { genre: 'Rock' } }, { tags: { genre: 'rock' } }],
  ]
  for (const list of fixed) out.push({ files: list, values: Object.fromEntries(keys.map((key) => [key, Tag.sharedValue(list, key)])) })
  for (let n = 0; n < 40; n++) {
    const list = files().map((file) => ({ tags: file.tags }))
    out.push({ files: list, values: Object.fromEntries(keys.map((key) => [key, Tag.sharedValue(list, key)])) })
  }
  return out
}

function edits() {
  const out = []
  const names = [[], ['01 - One.flac'], ['01 - One.flac', '02 - Two.flac', '03 - Three.flac']]
  const drafts = [{}, { genre: 'Rock' }, { genre: '  Rock  ' }, { genre: '' }, { genre: '   ' }, { title: '\u00a0\u03a9\ufeff' },
    { title: '\u0085x\u0085' }, { title: '\u200bx' }, { date: '2022', originaldate: ' 1999 ', composer: '' }]
  for (const filenames of names) for (const draft of drafts) out.push({ filenames, draft, edits: Tag.buildEdits(filenames, draft) })
  for (let n = 0; n < 20; n++) {
    const draft = {}
    for (const field of Tag.EDIT_FIELDS) if (chance(0.3)) draft[field.key] = pick(SPACES) + pick(VALUES) + (chance(0.5) ? pick(SPACES) : '')
    const filenames = pick(names)
    out.push({ filenames, draft, edits: Tag.buildEdits(filenames, draft) })
  }
  return out
}

function problems() {
  const values = ['', '   ', '3', '03', '3/12', '0003/0012', '12345', '3/', '/3', '3/12/1', '\u0663', '\uff13', ' 3 ', '3 / 12',
    'July 2022', '2022', '2022-07', '2022-07-29', '2024-13', '22', '2022-7-29', '2022-07-29T10:00', '2022/07/29', '20220',
    'a\tb', 'a\nb', '\tx\t', 'x\u007f', '\u0085x', '\u03a9', '3\u0085', '\u00a02022\u00a0']
  //? the long ones (by JavaScript's length: UTF-16 units) asked of a few fields, to keep the fixture small
  const long = ['x'.repeat(1000), 'x'.repeat(1001), ` ${'x'.repeat(1000)} `, '\u{1F3B5}'.repeat(500), '\u{1F3B5}'.repeat(501)]
  const out = []
  for (const field of [...Tag.EDIT_FIELDS, { key: 'comment' }]) for (const value of values) {
    out.push({ key: field.key, value, problem: Tag.tagProblem(field.key, value) })
  }
  for (const key of ['title', 'tracknumber', 'date']) for (const value of long) out.push({ key, value, problem: Tag.tagProblem(key, value) })
  return out
}

function notes() {
  const shares = [{ value: '', mixed: false }, { value: 'Rock', mixed: false }, { value: '', mixed: true }, { value: '1', mixed: false }]
  const drafts = [undefined, '', ' ', '\u00a0', 'x', 'July 2022', '3']
  const out = []
  for (const key of ['genre', 'discnumber', 'tracknumber', 'date']) for (const value of shares) for (const draft of drafts) {
    const problem = draft === undefined ? null : Tag.tagProblem(key, draft)
    out.push({
      key, shared: value, ...(draft === undefined ? {} : { draft }), problem,
      removes: Tag.removesTag(value, draft),
      placeholder: Tag.fieldPlaceholder(key, value, draft !== undefined),
      note: Tag.fieldNote(key, value, draft, problem),
    })
  }
  return out
}

function labels() {
  const out = []
  for (const position of [null, 0, 1, 9, 10, 100, 1234, -1]) for (const disc of [null, 0, 1, 2, 12]) for (const discs of [0, 1, 2, 3]) {
    out.push({ position, disc, discs, label: E.trackLabel({ position, disc }, discs) })
  }
  return out
}

/* ===== Tags: the editor's preview and apply, said ===== */

function plans() {
  const out = []
  const filenames = ['01 - One.flac', '02 - Two.flac']
  const made = [
    { file_count: 2, changed_file_count: 1, empty: false, problems: [] },
    { file_count: 1, changed_file_count: 0, empty: true, problems: [] },
    { file_count: 12, changed_file_count: 12, empty: false, problems: [] },
    { file_count: 2, changed_file_count: 2, empty: false, problems: ['01 - One.flac couldn\'t be read as audio'] },
  ]
  for (const plan of made) for (const planning of [false, true]) for (const applying of [false, true]) for (const problems of [0, 1]) {
    out.push({ plan, planning, applying, problems, canApply: canApplyOf(plan, planning, applying, problems), words: wouldChangeOf(plan) })
  }
  out.push({ plan: null, planning: false, applying: false, problems: 0, canApply: canApplyOf(null, false, false, 0), words: null })
  const saved = [
    { written: 1, failed: 0, problems: [] },
    { written: 3, failed: 0, problems: [] },
    { written: 0, failed: 1, problems: ['02 - Two.flac: could not save - disk full'] },
    { written: 2, failed: 1, problems: ['originaldate can\'t be written to 02 - Two.flac (MP4)', 'deadwax had a problem', 'slskd'] },
    { written: 2, failed: 0, problems: ['01 - One.flac has no room for originaldate.', '  extra space  '] },
  ].map((results) => ({ results, filenames, ...savedOf(results, filenames) }))
  const heading = [
    [['01 - One.flac'], [{ tags: { title: 'One' } }]], [['01 - One.flac'], [{ tags: {} }]], [['01 - One.flac'], [{ tags: { title: '' } }]],
    [['01 - One.flac'], []], [filenames, [{ tags: { title: 'One' } }, { tags: {} }]],
  ].map(([names, list]) => ({ filenames: names, files: list, words: headingOf(names.length === 1, list, names) }))
  return { states: out, saved, heading }
}

/* ===== a track's page: trackInspector.ts over trackFields.ts ===== */

/** The registry's track, as the phone has one: the file's own number, disc, length, format, size and name. */
function trackOf(details) {
  return {
    position: details.position, disc: details.disc, length: details.length, format: details.format, size: details.size,
    filename: details.filename, title: details.tags.title ?? details.filename, has_title_tag: Boolean(details.tags.title),
    artist: '', albumartist: '', album: '', date: '', originaldate: '', release_mbid: '',
  }
}

const TAG_KEYS = ['title', 'artist', 'albumartist', 'album', 'date', 'originaldate', 'genre', 'composer', 'conductor', 'lyricist',
  'discsubtitle', 'label', 'organization', 'catalognumber', 'barcode', 'isrc', 'releasecountry', 'media', 'bpm', 'language',
  'copyright', 'comment', 'musicbrainz_trackid', 'musicbrainz_releasetrackid', 'musicbrainz_albumid',
  'musicbrainz_releasegroupid', 'musicbrainz_artistid']
const LABELS = ['Front cover', 'Back cover', 'Media (e.g. label side of CD)', 'Cover', 'Type 21']

function details() {
  const out = [{
    filename: '01 - One.flac', format: 'flac', size: 31457280, length: 245.4, bitrate: 1024000, sample_rate: 44100,
    bits_per_sample: 16, channels: 2, codec: 'FLAC', position: 1, disc: null,
    tags: { title: 'One', artist: 'Them', label: 'Warp', organization: 'Other' }, raw: [['title', 'One'], ['artist', 'Them']],
    pictures: [{ index: 0, type: 3, label: 'Front cover', mime: 'image/jpeg', size: 62_000, description: '' }],
  }, {
    filename: 'untitled.mp3', format: 'mp3', size: 0, length: 0, bitrate: null, sample_rate: null, bits_per_sample: null,
    channels: null, codec: 'MP3', position: null, disc: null, tags: {}, raw: [], pictures: [],
  }, {
    filename: '2-07 Seven.m4a', format: 'm4a', size: 1610612736, length: 59.5, bitrate: 256000, sample_rate: 48000,
    bits_per_sample: null, channels: 6, codec: 'mp4a.40.2', position: 7, disc: 2,
    tags: { title: '', organization: 'Only organisation' }, raw: [['\u00a9nam', '']],
    pictures: [{ index: 0, type: null, label: 'Cover', mime: 'image/png', size: 2_500_000, description: '' },
      { index: 1, type: null, label: 'Cover', mime: 'image/png', size: 100, description: 'x' }],
  }]
  for (let n = 0; n < 30; n++) {
    const tags = {}
    for (const key of TAG_KEYS) if (chance(0.35)) tags[key] = pick(['x', '\u03a9', '2022-07-29', '12', 'a; b', ''])
    const pictures = Array.from({ length: between(0, 3) }, (_, index) => ({
      index, type: chance(0.2) ? null : between(0, 20), label: pick(LABELS), mime: pick(['image/jpeg', 'image/png', 'image/webp', 'image/image/x']),
      size: pick([0, 1, 511, 512, 1023, 1024, 1536, 65_536, 1_048_575, 1_048_576, 5_000_000]), description: '',
    }))
    out.push({
      filename: `${String(n).padStart(2, '0')} - ${pick(['A', '\u03a9', 'x y'])}.${pick(['flac', 'mp3', 'ogg', 'm4a'])}`,
      format: pick(['flac', 'mp3', 'ogg', 'm4a', 'opus']), size: pick([0, 1, 524_288, 1_048_576, 535_822_336, 1_073_741_824]),
      length: pick([0, 0.4, 0.5, 59.5, 60, 119.5, 3599.6]), bitrate: pick([null, 0, 128_000, 320_499, 320_500, 1_411_200]),
      sample_rate: pick([null, 0, 44_100, 48_000, 88_200, 96_000, 22_050, 11_025]), bits_per_sample: pick([null, 0, 16, 24, 32]),
      channels: pick([null, 0, 1, 2, 4, 6, 8]), codec: pick(['', 'FLAC', 'MP3', 'Vorbis']), position: pick([null, 0, 1, 9, 10, 123]),
      disc: pick([null, 0, 1, 2]), tags, raw: Object.entries(tags).map(([key, value]) => [key, value]), pictures,
    })
  }
  return out
}

function inspector() {
  return details().map((file) => {
    const track = trackOf(file)
    return {
      file,
      groups: TI.inspectorGroups(track, file, false).map((group) => ({
        name: group.name, fields: group.fields.map(({ id, label, value, mono, inferred }) => ({ id, label, value, mono, inferred })),
      })),
      untitled: TI.untitled(track, file),
      title: TI.trackTitle(track, file),
      places: [1, 2, 3].map((discs) => ({ discs, words: TI.trackPlace({ disc_count: discs }, track) })),
      raw: TI.rawTagsTitle(file),
      pictures: file.pictures.map((picture) => ({ picture, bytes: TI.pictureBytes(picture.size),
        facts: [undefined, '500 \u00d7 500'].map((pixels) => ({ ...(pixels ? { pixels } : {}), words: TI.pictureFacts(picture, pixels) })) })),
    }
  })
}

const inspectorWords = {
  NO_PICTURES: TI.NO_PICTURES,
  pictures: piece('app/TrackInspector.tsx', /<h4 class="app-inspect-heading">(Pictures in this file)<\/h4>/, 'pictures in this file')[1],
  noTitle: piece('app/TrackInspector.tsx', /<p class="app-inspect-note">(No title tag - this is the file's name\.)<\/p>/, 'no title tag')[1],
  editThis: piece('app/TrackInspector.tsx', /\n\s*(Edit this track\u2026)\n\s*<\/button>/, 'edit this track')[1],
  pictureLabel: compiled(['picture'], `return (${piece('app/TrackInspector.tsx', /aria-label=\{(`\$\{picture\.label\} - see it full size`)\}/, "a picture's label")[1]})`)({ label: 'Front cover' }),
}

/* ===== Artwork and Lyrics: lib/getResults.ts, lib/lyrics.ts, albumEdit.ts's lines, and LibraryParts.tsx's buttons ===== */

const PARTS = 'components/LibraryParts.tsx'
const { ApiError } = require(path.join(OUT, 'api/http.js'))

//? when each button is drawn, and what a 404 is - read as LibraryParts writes them
says(PARTS, 'if (album.art || !album.release_mbid) return null', 'Get cover offered')
const offersCoverOf = (album) => !(album.art || !album.release_mbid)
says(PARTS, 'if (!mine && album.lyrics_count >= album.track_count) return null', 'Get lyrics offered')
const offersLyricsOf = (album, ran) => !(!ran && album.lyrics_count >= album.track_count)
const hasOwnOf = compiled(['album'], `return ${piece(PARTS, /const hasOwn = (\(album\.disc_art \?\? \[\]\)\.some\(\(name\) => name\.toLowerCase\(\)\.startsWith\('disc'\)\))/, 'own CD art')[1]}`)
says(PARTS, 'if (!album.release_mbid || hasOwn) return null', 'Get CD art offered')
const offersDiscOf = (album) => !(!album.release_mbid || hasOwnOf(album))
const noneOn404 = "const state = caught instanceof ApiError && caught.status === 404 ? 'none' : 'failed'"
if (source(PARTS).split(noneOn404).length !== 3) throw new Error(`ui/src/${PARTS} no longer says a 404 is none for both covers`)
madeFrom[`ui/src/${PARTS} a 404 is none`] = sha256(noneOn404)

//? the buttons' words, as the JSX picks them
says(PARTS, "{state === 'working' ? <Loading label={GETTING.cover} /> : state === 'none' ? 'Look again' : state === 'failed' ? 'Try again' : 'Get cover'}", 'the cover button')
says(PARTS, "{mine?.state === 'working'\n          ? <Loading label={GETTING.lyrics} />\n          : summary\n            ? `Lyrics \u00b7 ${lyricsOnDisk(summary)} of ${album.track_count}`\n            : mine?.state === 'failed' ? 'Try again' : 'Get lyrics'}", 'the lyrics button')
says(PARTS, "{mine?.state === 'working'\n          ? <Loading label={GETTING.disc} />\n          : mine?.state === 'none' ? 'Look again' : mine?.state === 'failed' ? 'Try again' : 'Get CD art'}", 'the CD art button')
const G = require(path.join(OUT, 'lib/getResults.js'))
const L = require(path.join(OUT, 'lib/lyrics.js'))
function labelOf(kind, state, summary, tracks) {
  if (kind === 'cover') return state === 'working' ? G.GETTING.cover : state === 'none' ? 'Look again' : state === 'failed' ? 'Try again' : 'Get cover'
  if (kind === 'disc') return state === 'working' ? G.GETTING.disc : state === 'none' ? 'Look again' : state === 'failed' ? 'Try again' : 'Get CD art'
  return state === 'working' ? G.GETTING.lyrics : summary ? `Lyrics \u00b7 ${L.lyricsOnDisk(summary)} of ${tracks}` : state === 'failed' ? 'Try again' : 'Get lyrics'
}

const artworkWords = {
  GETTING: G.GETTING,
  GET_FAILED: G.GET_FAILED,
  COVER_MISSING: E.COVER_MISSING,
  DISC_ART_BESIDE: E.DISC_ART_BESIDE,
  NO_DISC_ART: E.NO_DISC_ART,
  RETIME_POINTER: E.RETIME_POINTER,
  cover: piece(PANEL, /<h3 id="app-edit-cover" class="app-edit-heading">(Cover)<\/h3>/, 'the cover heading')[1],
  discArt: piece(PANEL, /<h3 id="app-edit-disc" class="app-edit-heading">(CD art)<\/h3>/, 'the CD art heading')[1],
  lyrics: piece(PANEL, /<h3 id="app-edit-lyrics" class="app-edit-heading">(Lyrics)<\/h3>/, 'the lyrics heading')[1],
  seeCover: piece(PANEL, /aria-label="(See the cover full size)"/, 'the cover full size')[1],
  seeDiscArt: compiled(['name'], `return (${piece(PANEL, /aria-label=\{(`\$\{name\} - see it full size`)\}/, 'a CD art picture full size')[1]})`)('disc2.png'),
}

const ART = ['', 'file', 'embedded']
const DISC_ART = [[], ['disc.jpg'], ['cd.jpg'], ['Disc2.PNG'], ['cd.jpg', 'disc1.png'], ['DISC.jpg'], ['xdisc.jpg'],
  ['d\u0130sc.jpg'], ['\u0130disc.png'], ['disc'], ['cdart.png', 'disc10.webp'], ['Disc.Jpg', 'disc2.jpg']]
const COUNTS = [[0, 0], [0, 1], [1, 1], [3, 12], [11, 12], [12, 12], [13, 12], [0, 12], [1, 2]]
function artAlbums() {
  const out = []
  for (const art of ART) for (const release_mbid of ['', 'b84ee12a-09ef-421b-82de-0441a926375b']) for (const disc_art of DISC_ART) {
    const [lyrics_count, track_count] = COUNTS[out.length % COUNTS.length]
    out.push({ art, release_mbid, disc_art, lyrics_count, track_count })
  }
  for (const [lyrics_count, track_count] of COUNTS) out.push({ art: 'file', release_mbid: 'x', disc_art: [], lyrics_count, track_count })
  return out.map((album) => ({
    album,
    coverNote: E.coverNote(album.art),
    coverPointer: E.coverPointer(album),
    discArtPointer: E.discArtPointer(album),
    lyricsLine: E.lyricsLine(album.lyrics_count, album.track_count),
    allLyricsNote: E.allLyricsNote(album),
    offersCover: offersCoverOf(album),
    hasOwnDiscArt: hasOwnOf(album),
    offersDiscArt: offersDiscOf(album),
    offersLyrics: [false, true].map((ran) => offersLyricsOf(album, ran)),
  }))
}

/** An error as the web meets it - its own ApiError (message `detail || "METHOD path failed"`), fetch's TypeError,
 *  a TimeoutError, or any other Error - and the spec the Swift remakes it from. */
function madeError(spec) {
  if (spec.answer) {
    const a = spec.answer
    return new ApiError(a.status, a.detail ?? null, `POST ${a.path} failed`, false, null, a.why ?? null, a.path)
  }
  if ('offline' in spec) return new TypeError(spec.offline)
  if ('timeout' in spec) return Object.assign(new Error(spec.timeout), { name: 'TimeoutError' })
  return new Error(spec.other)
}
const answered = (status, detail, route, why) => ({ answer: { status, path: route, ...(detail === null ? {} : { detail }), ...(why ? { why } : {}) } })
const GET_ERRORS = [
  answered(404, 'the Cover Art Archive has no front cover for that release', '/library/art/fetch'),
  answered(404, 'no CD art on the Cover Art Archive for this release - a fanart.tv key in Server settings adds another source', '/library/disc_art/fetch'),
  answered(404, 'no CD art on the Cover Art Archive for this release, or on fanart.tv for the album', '/library/disc_art/fetch'),
  answered(502, "the Cover Art Archive couldn't be reached - try again", '/library/art/fetch'),
  answered(502, "the CD art couldn't be downloaded from fanart.tv - try again", '/library/disc_art/fetch'),
  answered(400, 'this album already has CD art: disc.jpg', '/library/disc_art/fetch'),
  answered(400, 'not tagged with a MusicBrainz release - match it to one first', '/library/disc_art/fetch'),
  answered(400, 'that album is not inside the library', '/library/lyrics/fetch'),
  answered(400, 'LIBRARY_PATH is not set', '/library/art/fetch'),
  answered(500, 'Error fetching the cover art: [Errno 28] No space left on device', '/library/art/fetch'),
  answered(500, null, '/library/lyrics/fetch'),
  answered(504, null, '/library/lyrics/fetch'),
  answered(502, null, '/library/disc_art/fetch'),
  answered(403, "That needs Edit albums, which an admin hasn't given you.", '/library/art/fetch'),
  answered(401, 'Sign in to use deadwax.', '/library/lyrics/fetch'),
  answered(404, 'Not Found', '/library/lyrics/fetch'),
  answered(422, 'album_path: Field required', '/library/disc_art/fetch'),
  { offline: 'Failed to fetch' },
  { offline: 'Load failed' },
  { timeout: 'signal timed out' },
  { other: 'Unexpected token < in JSON at position 0' },
]
function getProblems() {
  const out = []
  for (const error of GET_ERRORS) for (const kind of ['cover', 'disc', 'lyrics']) for (const admin of [false, true]) {
    out.push({ error, kind, admin, said: G.getProblem(madeError(error), kind, admin) })
  }
  return out
}

function summaries() {
  const fixed = [
    { written: 0, replaced: 0, kept: 0, instrumental: 0, missing: 0, failed: 0, untagged: 0, synced: 0 },
    { written: 1, replaced: 0, kept: 0, instrumental: 0, missing: 0, failed: 0, untagged: 0, synced: 1 },
    { written: 3, replaced: 2, kept: 4, instrumental: 1, missing: 2, failed: 1, untagged: 1, synced: 5 },
    { written: 0, replaced: 0, kept: 12, instrumental: 0, missing: 0, failed: 0, untagged: 0, synced: 0 },
    { written: 0, replaced: 0, kept: 0, instrumental: 0, missing: 0, failed: 3, untagged: 0, synced: 0 },
    { written: 2, replaced: 0, kept: 0, instrumental: 0, missing: 0, failed: 0, untagged: 0, synced: 1 },
  ]
  for (let n = 0; n < 40; n++) {
    const summary = {}
    for (const key of ['written', 'replaced', 'kept', 'instrumental', 'missing', 'failed', 'untagged']) summary[key] = pick([0, 0, 1, 2, 7])
    summary.synced = between(0, summary.written + summary.replaced)
    fixed.push(summary)
  }
  return fixed.map((summary) => ({
    summary,
    described: L.describeLyrics(summary),
    result: G.lyricsResult(summary),
    onDisk: L.lyricsOnDisk(summary),
  }))
}

function buttonLabels() {
  const out = []
  for (const kind of ['cover', 'disc', 'lyrics']) {
    const states = kind === 'lyrics' ? ['idle', 'working', 'done', 'failed'] : ['idle', 'working', 'none', 'failed']
    for (const state of states) for (const tracks of [1, 12]) {
      const summary = state === 'done' ? { written: 2, replaced: 1, kept: 4, instrumental: 0, missing: 1, failed: 0, untagged: 0, synced: 2 } : undefined
      out.push({ kind, state, tracks, ...(summary ? { summary } : {}), label: labelOf(kind, state, summary, tracks) })
    }
  }
  return out
}

/* ===== written ===== */

const out = {
  tags: {
    fields: Tag.EDIT_FIELDS,
    words: tagWords,
    shared: shared(),
    edits: edits(),
    problems: problems(),
    notes: notes(),
    labels: labels(),
    plans: plans(),
  },
  inspector: { words: inspectorWords, tracks: inspector() },
  artwork: {
    words: artworkWords,
    albums: artAlbums(),
    problems: getProblems(),
    summaries: summaries(),
    labels: buttonLabels(),
  },
}
fs.rmSync(OUT, { recursive: true, force: true })

const BACKSLASH = String.fromCharCode(92)
function ascii(json) {
  let text = ''
  for (let i = 0; i < json.length; i++) {
    const unit = json.charCodeAt(i)
    text += unit < 0x7f ? json[i] : BACKSLASH + 'u' + unit.toString(16).padStart(4, '0')
  }
  return text
}
const flat = (value) => ascii(JSON.stringify(value))

const fixture = {
  about: "Edit album's other parts (lib/tagEdit.ts, lib/trackInspector.ts, lib/trackFields.ts, lib/albumEdit.ts run as they are; components/TrackTagEditor.tsx's, app/EditPanel.tsx's and app/TrackInspector.tsx's words read out of their sources): Tags - the fields, shared values, edits, problems, notes, numbers and a track's page; Artwork and Lyrics (lib/getResults.ts, lib/lyrics.ts, components/LibraryParts.tsx's buttons) - when each Get is offered, its words, what it came to, and the pages' lines.",
  made_by: MADE_BY,
  made_from: Object.fromEntries(Object.keys(madeFrom).sort().map((key) => [key, madeFrom[key]])),
  ...out,
}
const body = [
  '{',
  Object.entries(fixture).map(([key, value]) => value && typeof value === 'object' && !Array.isArray(value) && key !== 'made_from'
    ? `  ${flat(key)}: {\n${Object.entries(value).map(([inner, rows]) => Array.isArray(rows)
      ? `    ${flat(inner)}: [\n${rows.map((row) => `      ${flat(row)}`).join(',\n')}\n    ]`
      : `    ${flat(inner)}: ${flat(rows)}`).join(',\n')}\n  }`
    : `  ${flat(key)}: ${flat(value)}`).join(',\n'),
  '}',
  '',
].join('\n')

const counted = `${out.tags.problems.length} problems, ${out.tags.notes.length} notes, ${out.tags.edits.length} edits, ${out.inspector.tracks.length} tracks, `
  + `${out.artwork.albums.length} albums, ${out.artwork.problems.length} Get problems, ${out.artwork.summaries.length} lyrics summaries`
if (CHECK) {
  if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== body) {
    console.log(`Edit album's parts' fixture differs from what the web app's TypeScript answers now: ${path.relative(REPO, FIXTURE)}.`)
    console.log(`Run node ${MADE_BY}, and see what the Swift port must follow.`)
    process.exit(1)
  }
  console.log(`Edit album's parts' fixture matches the web app's TypeScript (${counted}).`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, body)
  console.log(`Wrote ${path.relative(REPO, FIXTURE)}: ${counted}, ${Math.round(body.length / 1024)} KB`)
}
