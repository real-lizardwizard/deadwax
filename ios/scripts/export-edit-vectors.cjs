#!/usr/bin/env node
/**
 * The iPhone app's Edit album (Phase 8, slice 1 - notes/ios-specs/phase8-managing.md 3.1-3.3, 3.7): which folder an
 * album page's album is, choosing one from the library's scan, what the editor says without an album, following the
 * album after a write, what is wrong with it, and the Release editor - its two queries, both scores, the pressing's
 * payload, the fields a pick seeds, and every word of the preview and the apply - written as a fixture the Swift port
 * (ios/DeadwaxKit/Sources/DeadwaxCore/AlbumEdit.swift, ScanAlbums.swift, Retag.swift, RetagFlow.swift) replays in
 * Tests/DeadwaxCoreTests/EditVectorTests.swift.
 *
 * Compiles lib/albumEdit.ts, lib/release.ts, lib/retagPlan.ts, lib/metadataQueue.ts, lib/typedMatch.ts, lib/owned.ts,
 * lib/format.ts, lib/permissions.ts and lib/releasePayload.ts with the repo's TypeScript and runs them AS THEY ARE over
 * made inputs, plain to awkward (folded names, a scan with two folders of one release, credits of nobody, video
 * media, a sigma at a word's end, a merge with files kept back), and over the real pressings MusicBrainz answered
 * (tests/fixtures/pressings/). components/MetadataEditor.tsx's own rules and words - its constants, the payload it
 * lays the fields over, the fields a picked pressing seeds and the album seeds, its two search queries, a row's detail
 * and track count, the cover's lines, and its sentences - are read out of its source by pattern; the expressions are
 * stripped of their types by TypeScript's own transpiler and evaluated as written. A pattern that no longer matches
 * stops this script, naming what moved.
 * Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/edit/edit-vectors.json.
 *
 * The file names each source it was made from with its sha256 (the libraries whole, the component's pieces), so
 * ui/test/iosedit.sim.cjs - which runs this with --check - fails when one changes, until the fixture is written again
 * and the Swift port follows. The output is plain ASCII (anything else as a \u escape), so a run on any machine
 * writes the same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-edit-vectors.cjs           write the fixture
 *   node ios/scripts/export-edit-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'edit', 'edit-vectors.json')
const CHECK = process.argv.includes('--check')
const MADE_BY = 'ios/scripts/export-edit-vectors.cjs'
const SOURCES = ['lib/albumEdit.ts', 'lib/release.ts', 'lib/retagPlan.ts', 'lib/metadataQueue.ts', 'lib/typedMatch.ts',
  'lib/owned.ts', 'lib/format.ts', 'lib/permissions.ts', 'lib/releasePayload.ts']
const EDITOR = 'components/MetadataEditor.tsx'
const PRESSINGS = ['dummy', 'slow-rush', 'third', 'wish-you-were-here-experience']

const sha256 = (body) => crypto.createHash('sha256').update(body).digest('hex')
const source = (file) => fs.readFileSync(path.join(UI, 'src', file), 'utf8')
const madeFrom = Object.fromEntries(SOURCES.map((file) => [`ui/src/${file}`, sha256(source(file))]))
for (const name of PRESSINGS) {
  const file = `tests/fixtures/pressings/${name}.json`
  madeFrom[file] = sha256(fs.readFileSync(path.join(REPO, file), 'utf8'))
}

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

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-edit-vectors-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES.map((file) => `src/${file}`),
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const E = require(path.join(OUT, 'lib/albumEdit.js'))
const Rel = require(path.join(OUT, 'lib/release.js'))
const Plan = require(path.join(OUT, 'lib/retagPlan.js'))
const Q = require(path.join(OUT, 'lib/metadataQueue.js'))
const T = require(path.join(OUT, 'lib/typedMatch.js'))
const P = require(path.join(OUT, 'lib/permissions.js'))
const RP = require(path.join(OUT, 'lib/releasePayload.js'))
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

/* ===== MetadataEditor.tsx's own, read out of its source ===== */

const GROUPS_SEARCHED = Number(piece(EDITOR, /\nconst GROUPS_SEARCHED = (\d+)\n/, 'GROUPS_SEARCHED')[1])
const PREVIEW_DEBOUNCE_MS = Number(piece(EDITOR, /\nconst PREVIEW_DEBOUNCE_MS = (\d+)\n/, 'PREVIEW_DEBOUNCE_MS')[1])

//? the fields the editor opens with, seeded from the album on disk, and the cover box's first state
const seedFieldsOf = compiled(['album'], `return (${piece(EDITOR, /const \[fields, setFields\] = useState<Fields>\((\{[\s\S]*?\})\)\n/, 'the fields seeded from the album')[1]})`)
const fetchArtOf = compiled(['album'], `return (${piece(EDITOR, /const \[fetchArt, setFetchArt\] = useState\((!album\.art)\)/, 'the cover box seeded')[1]})`)

//? the search: what it asks first, when the loose words are asked, and what they are
const firstSearch = piece(EDITOR, /const first = await musicbrainz\.fullySearch\((query\.trim\(\) \|\| fielded), (\d+), false\)/, 'the first search')
const firstQueryOf = compiled(['query', 'fielded'], `return (${firstSearch[1]})`)
const SEARCH_LIMIT = Number(firstSearch[2])
const looseWhen = piece(EDITOR, /if \((!groups\.length && !query\.trim\(\))\) \{\n\s*const loose = await musicbrainz\.fullySearch\((`[^`]*`\.trim\(\)), (\d+), false\)/, 'the loose search')
const looseWhenOf = compiled(['groups', 'query'], `return (${looseWhen[1]})`)
const looseQueryOf = compiled(['fields'], `return (${looseWhen[2]})`)
if (Number(looseWhen[3]) !== SEARCH_LIMIT) throw new Error('the two searches ask different limits - the port asks one')
const fieldedOf = compiled(['fieldedAlbumQuery', 'fields'], `return (${piece(EDITOR, /const fielded = (fieldedAlbumQuery\(fields\.album, fields\.artist\))\n/, 'the fielded query')[1]})`)
const groupTarget = piece(EDITOR, /const target = \{\n\s*album: fields\.album,\n\s*year: fields\.year,\n\s*original_year: fields\.originalYear,\n\s*\}/, 'the groups ranked against the fields')
const autoSearch = compiled(['album'], `if (${piece(EDITOR, /if \((!album\.artist\.trim\(\) && !album\.album\.trim\(\))\) return\n/, 'the search at open')[1]}) return false\nreturn true`)

//? what Apply sends, and what a pick seeds
const payloadOf = compiled(['selected', 'fields', 'album', 'buildRetagRelease'],
  piece(EDITOR, /const payload = useMemo\(\(\): RetagRelease => \{\n([\s\S]*?)\n  \}, \[selected, fields, album\]\)/, 'the payload')[1])
const seeding = piece(EDITOR, /if \(seedFields\) \{\n([\s\S]*?)\n      \}\n    \} catch/, 'the fields a pick seeds')[1]
const seedOf = compiled(['full', 'album', 'groupMbid', 'firstReleaseDate', 'buildRetagRelease', 'currentName', 'setFields'], seeding)

//? a row of the list: its detail line, its track count, whether it differs from the folder's
const detailOf = compiled(['release', 'describeRelease'], `return (${piece(EDITOR, /\{(\[release\.date\?\.substring\(0, 4\), describeRelease\(release\)\]\.filter\(Boolean\)\.join\(' · '\))\}/, "a row's detail")[1]})`)
const trackWords = piece(EDITOR, /\n\s*\{(\(release\.media \?\? \[\]\)\.length > 1 \? `\$\{\(release\.media \?\? \[\]\)\.length\} discs · ` : '')\}\n\s*\{(tracks \? `\$\{tracks\} \$\{tracks === 1 \? 'track' : 'tracks'\}` : '\? tracks')\}/, "a row's track count")
const trackWordsOf = compiled(['release', 'tracks'], `return (${trackWords[1]}) + (${trackWords[2]})`)
const mismatchOf = compiled(['tracks', 'album'], `return Boolean(${piece(EDITOR, /class=\{`metadata-release-tracks\$\{(tracks && tracks !== album\.track_count) \? ' mismatch' : ''\}`\}/, "a row's count differing")[1]})`)

//? the cover's lines
const coverToggleOf = compiled(['plan'], `return (${piece(EDITOR, /\{(plan\?\.art\.existing \? `Replace \$\{plan\.art\.existing\}` : 'Download cover art')\}/, 'the cover box')[1]})`)
const coverHint = piece(EDITOR, /\{(plan\?\.art\.existing\n\s*\? '[^']*'\n\s*: '[^']*')\}\n\s*\{\/\*[^*]*\*\/\}\n\s*\{(plan\?\.art\.size\n\s*\? ` — \$\{plan\.art\.size === 'full' \? 'at full size' : `at \$\{plan\.art\.size\} × \$\{plan\.art\.size\}`\}`\n\s*: '')\}/, "the cover box's line")
const coverHintOf = compiled(['plan'], `return (${coverHint[1]}) + (${coverHint[2]})`)
const coverOnlyOf = compiled(['album'], `return (${piece(EDITOR, /: (album\.art \? 'Replace cover only' : 'Save cover only')\}/, 'the cover alone')[1]})`)
const coverOnlyHintOf = compiled(['album'], `return (${piece(EDITOR, /title=\{\n\s*(album\.art\n\s*\? '[^']*'\n\s*: '[^']*')\n\s*\}/, "the cover alone's line")[1]})`)
const coverSavedOf = compiled(['result'], `return (${piece(EDITOR, /setArtResult\((`Saved \$\{result\.written\}\$\{result\.replaced \? `, replacing \$\{result\.replaced\}` : ''\}\.`)\)/, 'the cover saved')[1]})`)
const editionPlaceholderOf = compiled(['plan'], `return (${piece(EDITOR, /placeholder=\{(plan\?\.edition_label \|\| '[^']*')\}/, "the edition's placeholder")[1]})`)
const originalPlaceholderOf = compiled(['fields'], `return (${piece(EDITOR, /placeholder=\{(fields\.year \|\| '[^']*')\}/, "the original year's placeholder")[1]})`)

//? the release whose cover the comparison shows, and the cover alone fetches
const incomingOf = compiled(['selectedId', 'album'], `return (${piece(EDITOR, /const incomingId = (selectedId \?\? \(album\.release_mbid \|\| null\))\n/, "the comparison's release")[1]})`)

//? what an apply leaves: its problems that weren't the preview's
const newProblemsOf = compiled(['results', 'plan'], `return (${piece(EDITOR, /setAppliedProblems\((results\.problems\.filter\(\(problem\) => !plan\?\.problems\.includes\(problem\)\))\)/, "an apply's own problems")[1]})`)
//? Apply's button: what turns it off
const applyOff = piece(EDITOR, /disabled=\{(!plan \|\| plan\.empty \|\| planning \|\| applying \|\| loadingRelease)\}/, "Apply's off")[1]

const stringOf = (expression) => new Function(`return (${expression})`)()
const searchAway = stringOf(piece(EDITOR, /\? ("MusicBrainz is unreachable right now, so there's nothing to match against\. " \+\s*'[^']*')/, 'the search with MusicBrainz away')[1])
const tracklistAway = stringOf(piece(EDITOR, /\? ("MusicBrainz couldn't be reached for that release's tracklist, so it can't be " \+\s*'[^']*')/, 'the tracklist with MusicBrainz away')[1])
const fieldsHint = piece(EDITOR, /<span class="text white-tertiary metadata-hint">\n((?:\s+[^<{\n]+\n)+)\s*<\/span>/, 'the fields hint')[1]
  .split('\n').map((line) => line.trim()).filter(Boolean).join(' ')

const words = {
  searching: says(EDITOR, 'Searching MusicBrainz…', 'searching'),
  noReleases: says(EDITOR, 'No releases found for that search.', 'no releases'),
  currentMissing: says(EDITOR, "The release this album is matched to isn't in these results.", 'the current one missing'),
  notSearched: piece(EDITOR, /<h4 class="text default-muted metadata-status">\n\s*(Search to match[^\n]*)\n\s*<\/h4>/, 'not searched')[1],
  searchAway,
  tracklistAway,
  searchFailed: piece(EDITOR, /\{ failed: ("The search didn't work\.") \}/, 'the search failed')[1].slice(1, -1),
  releaseFailed: piece(EDITOR, /\{ failed: ("Couldn't load that release\.") \}/, 'a release failed')[1].slice(1, -1),
  coverFailed: piece(EDITOR, /\{ failed: ("Couldn't save the cover\.") \}/, 'the cover failed')[1].slice(1, -1),
  fieldsHint,
  current: piece(EDITOR, /title="This album is matched to this release">(Current)<\/span>/, 'Current')[1],
  apply: piece(EDITOR, /\? <Loading label=\{applyingLabel\(plan\)\} \/>\n\s*: '(Apply)'\}/, 'Apply')[1],
  fine: piece(EDITOR, /: "(It's fine as it is)"\}/, "It's fine as it is")[1],
  markingFine: piece(EDITOR, /<Loading label="(Marking it fine…)" \/>/, 'marking it fine')[1],
  askAgain: piece(EDITOR, /\n\s*(Ask about it again)\n\s*<\/button>/, 'ask about it again')[1],
  markedFine: says(EDITOR, 'Marked fine: {markedFine.map((code) => issueLabel(code, issueTypes)).join(\', \')}', 'marked fine'),
  compare: {
    current: piece(EDITOR, /label: '(Current)',\n\s*sources: album\.art/, "the comparison's current")[1],
    noCover: piece(EDITOR, /missing: '(No cover on disk)'/, "the comparison's none")[1],
    fromThis: piece(EDITOR, /label: selectedId \? '(From this release)' : "([^"]*)"/, "the comparison's release")[1],
    fromTagged: piece(EDITOR, /label: selectedId \? '[^']*' : "([^"]*)"/, "the comparison's tagged")[1],
    archiveNone: piece(EDITOR, /\? '(The Cover Art Archive has no front cover for this release, or is unreachable)'/, "the comparison's archive none")[1],
    pick: piece(EDITOR, /: '(Pick a release to see its cover)'/, "the comparison's pick")[1],
  },
  //? Edit album's own words for the library unread and a 403 (EditWords.readFailed, noPermission): libraryCare.ts's
  //? READ_FAILED as EditPanel says it, and permissions.ts's NO_PERMISSION as every Managing page says it
  READ_FAILED: says('app/EditPanel.tsx', "sayError(library.error, '', { failed: READ_FAILED, retry: true })", 'the library unread')
    && piece('lib/libraryCare.ts', /export const READ_FAILED = "(Couldn't read the library\.)"/, 'READ_FAILED')[1],
  NO_PERMISSION: P.NO_PERMISSION,
  PREVIEW_FAILED: Plan.PREVIEW_FAILED,
  APPLY_FAILED: Plan.APPLY_FAILED,
  NOTHING_TO_CHANGE: Plan.NOTHING_TO_CHANGE,
  planning: [true, false].map((loading) => ({ loading, label: Plan.planningLabel(loading) })),
  applyOff,
  EDIT_TABS: E.EDIT_TABS,
  FOLDER_CHOICES_SHOWN: E.FOLDER_CHOICES_SHOWN,
  EDIT_SETTLE_MS: E.EDIT_SETTLE_MS,
  FOLLOW_LOOKS_MS: E.FOLLOW_LOOKS_MS,
  GROUPS_SEARCHED,
  PREVIEW_DEBOUNCE_MS,
  SEARCH_LIMIT,
}
if (applyOff !== '!plan || plan.empty || planning || applying || loadingRelease') {
  throw new Error("Apply's button is turned off by something new - RetagFlow.canApply must follow")
}

/* ===== seeded randomness ===== */

let seed = 8320
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const between = (low, high) => low + Math.floor(rand() * (high - low + 1))
const chance = (p) => rand() < p

/* ===== which folder ===== */

const RELEASE_A = '6b3b9e1a-6f8c-4c4a-9b0e-2d1f9a7c3e11'
const RELEASE_B = 'b2f1c9d0-1e2a-4b3c-8d4e-5f6a7b8c9d0e'
const NAMES = ['Third', 'third', 'The Third', 'Third (Deluxe)', 'Third [2008]', 'Thírd', 'Third ', 'Dummy', '', 'Sigur Rós',
  '( )', 'Homogenic', 'Rock & Roll', "Rock 'n' Roll", 'Rock ’n’ Roll', 'ΣΟΦΟΣ']
const ARTISTS = ['Portishead', 'portishead', 'The Portishead', 'Björk', 'Bjork', '', 'Sigur Rós', 'Simon & Garfunkel',
  'Simon and Garfunkel']
const RELEASES = ['', RELEASE_A, RELEASE_A.toUpperCase(), ` ${RELEASE_A} `, RELEASE_B]

function scanOf(n) {
  return [...Array(n).keys()].map((at) => ({
    path: pick([`Portishead/Third (2008)`, `Portishead/Third (2008)/CD ${at}`, `Björk/Homogenic (1997)`, `A/B ${at}`,
      `Sigur Rós/( ) (2002)`, `Portishead/Third (2008) [Deluxe]`, `x${at}`]) + (chance(0.3) ? ` ${at}` : ''),
    album: pick(NAMES),
    artist: pick(ARTISTS),
    release_mbid: pick(RELEASES),
    track_count: pick([0, 1, 11, 12, 19]),
  }))
}

function navidromeAlbum() {
  const album = { id: pick(['al-1', 'al-2', '']), name: pick(NAMES) }
  if (chance(0.7)) album.artist = pick(ARTISTS)
  if (chance(0.6)) album.songCount = pick([0, 11, 12, 19])
  if (chance(0.5)) album.musicBrainzId = pick([...RELEASES, '   '])
  return album
}

function bridge() {
  if (chance(0.25)) return null
  return {
    release_mbid: pick([null, ...RELEASES]),
    present: chance(0.5) ? [] : [...Array(between(1, 3)).keys()].map(() => ({ path: pick(['Portishead/Third (2008)', '', 'Portishead/Third (2008)/CD 2']) })),
  }
}

function folders() {
  const out = []
  for (let n = 0; n < 160; n++) {
    const scan = scanOf(between(0, 7))
    const raw = navidromeAlbum()
    const album = E.editAlbum(raw)
    const answer = bridge()
    const found = E.editFolders(answer, scan, album)
    out.push({ raw, album, answer, scan, folders: found, needsChoice: E.needsChoice(found) })
  }
  return out
}

/* ===== choose the folder ===== */

function choices() {
  const scan = [
    { path: 'Sigur Rós/( ) (2002)', artist: 'Sigur Rós', album: '( )', release_mbid: '', track_count: 8 },
    { path: 'Portishead/Third (2008)', artist: 'Portishead', album: 'Third', release_mbid: RELEASE_A, track_count: 11 },
    { path: 'Portishead/Dummy (1994)', artist: 'Portishead', album: 'Dummy', release_mbid: '', track_count: 11 },
    { path: 'portishead/Third (2008) [Deluxe]', artist: 'Portishead', album: 'Third', release_mbid: RELEASE_B, track_count: 19 },
    { path: 'Björk/Homogenic (1997)', artist: 'Björk', album: 'Homogenic', release_mbid: '', track_count: 10 },
    { path: 'Bjork/Homogenic (1997)', artist: 'Bjork', album: 'Homogenic', release_mbid: '', track_count: 10 },
    { path: 'Ωmega/ΣΟΦΟΣ', artist: 'Ωmega', album: 'ΣΟΦΟΣ', release_mbid: '', track_count: 3 },
    { path: 'A/B', artist: 'A', album: 'B', release_mbid: '', track_count: 1 },
    { path: 'A/B', artist: 'A', album: 'B again', release_mbid: '', track_count: 2 },
    { path: 'Z/z', artist: '', album: '', release_mbid: '', track_count: 0 },
  ]
  const typed = ['', ' ', 'sigur ros 2002', 'SIGUR', 'portishead third', 'bjork', 'björk', 'homogenic 1997', 'xyz', 'a b',
    'σοφος', 'ΣΟΦΟΣ', '  third  deluxe ', 'é', 'Ро']
  const out = []
  for (const words of typed) {
    for (const limit of [50, 3, 1, 0, -1]) {
      const { shown, matching } = E.folderChoices(scan, words, limit)
      out.push({ typed: words, limit, shown: shown.map((album) => scan.indexOf(album)), matching,
        words: E.folderChoicesWords(shown.length, matching, words) })
    }
  }
  return { scan, cases: out, many: [[0, 0, ''], [0, 0, 'x'], [1, 1, ''], [1, 1, 'x'], [2, 2, ''], [2, 2, 'x'], [50, 120, ''],
    [50, 120, 'por'], [3, 7, ' ']].map(([shown, matching, typed]) => ({ shown, matching, typed, words: E.folderChoicesWords(shown, matching, typed) })) }
}

function typedMatches() {
  const hays = ['Sigur Rós/( ) (2002) Sigur Rós ( )', 'Björk Homogenic', 'ΣΟΦΟΣ', 'Ǆemal', 'ﬁve', 'ｆｕｌｌ', 'İstanbul', 'a\tb', '']
  const typed = ['', 'ros', 'ROS 2002', 'bjork homo', 'σοφος', 'σοφοσ', 'dž', 'fi', 'full', 'i̇stanbul', 'istanbul', 'a b', 'b a']
  const out = []
  for (const hay of hays) for (const words of typed) out.push({ hay, typed: words, matches: T.matchesTyped(hay, words), fold: T.searchFold(words) })
  return out
}

/* ===== what the editor says ===== */

function statuses() {
  const out = []
  const FOLDERS = [null, { paths: [], from: 'none' }, { paths: ['A/B'], from: 'release' }, { paths: ['A/B', 'A/C'], from: 'name' },
    { paths: ['A/B', 'A/C'], from: 'release' }, { paths: ['A/B'], from: 'folder' }, { paths: ['A/B'], from: 'store' }]
  for (let n = 0; n < 220; n++) {
    const facts = {
      deleted: pick([null, null, null, '', 'Portishead/Third (2008)']),
      problem: pick([null, null, null, '', 'LIBRARY_PATH is not set, so there is no library to read.']),
      error: pick([null, null, '', "Can't connect to deadwax. Check your connection."]),
      albums: pick([0, 0, 3]),
      loaded: chance(0.7),
      stale: chance(0.3),
      asked: chance(0.7),
      folders: pick(FOLDERS),
      holding: chance(0.25),
      release: pick([null, '', RELEASE_A]),
    }
    if (chance(0.5)) facts.listed = chance(0.5)
    out.push({ facts, status: E.editStatus(facts) })
  }
  return out
}

/* ===== following the album ===== */

function follow() {
  const releases = [null, undefined, '', '  ', RELEASE_A, RELEASE_A.toUpperCase(), ` ${RELEASE_B} `]
  const rel = []
  for (const before of releases) for (const after of releases) rel.push({ before: before ?? null, after: after ?? null, follow: E.followRelease(before, after) })
  const to = []
  for (const page of ['al-1', '']) for (const found of [null, undefined, '', 'al-1', 'al-2']) to.push({ page, found: found ?? null, to: E.followsTo(page, found) })
  const runs = []
  const IDS = ['a', 'b', 'c', 'd']
  for (let n = 0; n < 40; n++) {
    const moves = new Map()
    const steps = [...Array(between(1, 6)).keys()].map(() => [pick(IDS), pick(IDS)])
    for (const [from, toId] of steps) E.noteMove(moves, from, toId)
    runs.push({ steps, moves: [...moves.entries()].sort(), ends: IDS.map((id) => [id, E.movedTo(moves, id)]) })
  }
  return { releases: rel, to, runs }
}

/* ===== the editor's parts, what is wrong ===== */

function parts() {
  const out = []
  for (const editors of [true, false]) for (const remove of [true, false]) out.push({ editors, remove, tabs: E.editTabs(editors, remove).map((tab) => tab.id) })
  const fine = []
  for (let mask = 0; mask < 1 << P.PERMISSIONS.length; mask++) {
    const perms = new Set(P.PERMISSIONS.filter((_, bit) => mask & (1 << bit)))
    fine.push({ permissions: [...perms], marksFine: E.marksFine(perms) })
  }
  return { tabs: out, fine }
}

function queue() {
  const CODES = ['no_release', 'no_art', 'missing_tracks', 'mixed_formats', 'no_year']
  const types = { no_release: { label: 'No release', hint: 'Match it to a release.', severity: 3 }, no_art: { label: 'No cover', hint: '', severity: 1 } }
  const out = []
  for (let n = 0; n < 40; n++) {
    const issues = CODES.filter(() => chance(0.4))
    const ignored = CODES.filter(() => chance(0.3))
    const album = { issues, ignored_issues: ignored }
    out.push({ issues, ignored, outstanding: Q.outstandingIssues(album), markedFine: Q.markedFineIssues(album),
      labels: issues.map((code) => Q.issueLabel(code, types)) })
  }
  return { types, cases: out }
}

/* ===== the queries ===== */

function queries() {
  const strings = ['', 'Third', 'Portishead', 'Wish You Were Here', 'He said "hi"', 'back\\slash', 'both \\" at once', '  padded  ',
    'Björk', 'Ye', 'AC/DC', 'a\tb', '﻿bom']
  const out = []
  for (let n = 0; n < 60; n++) {
    const fields = { artist: pick(strings), album: pick(strings), year: '', originalYear: '', editionLabel: '' }
    const query = pick(['', '   ', 'typed words', ' padded '])
    const fielded = fieldedOf(Rel.fieldedAlbumQuery, fields)
    out.push({
      fields, query,
      fielded,
      plain: Rel.plainAlbumQuery(fields.album, fields.artist),
      first: firstQueryOf(query, fielded),
      loose: looseWhenOf([], query) ? looseQueryOf(fields) : null,
      looseWithGroups: looseWhenOf([{ id: 'x' }], query),
    })
  }
  const opens = [['', ''], [' ', '\t'], ['a', ''], ['', 'b'], ['Third', 'Portishead']].map(([artist, album]) => ({ artist, album, searches: autoSearch({ artist, album }) }))
  return { cases: out, opens }
}

/* ===== made groups and pressings ===== */

const CREDITS = [
  undefined, [],
  [{ name: 'Portishead', joinphrase: '', artist: { id: '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11', name: 'Portishead' } }],
  [{ name: 'Kanye West', joinphrase: '', artist: { id: '164f0d73-1234-4e2c-8743-d77bf2191051', name: 'Ye' } }],
  [{ name: 'Simon', joinphrase: ' & ', artist: { id: 'a1', name: 'Paul Simon' } }, { name: 'Garfunkel', joinphrase: '', artist: { id: 'a2', name: 'Art Garfunkel' } }],
  [{ name: '', artist: { id: 'a3', name: 'Named By The Artist' } }],
  [{ name: '  Padded  ' }],
  [{ name: '', joinphrase: '' }],
]
const FORMATS = [undefined, null, '', 'CD', 'Digital Media', '12" Vinyl', 'DVD', 'DVD-Video', 'Blu-ray']
const DISC_TITLES = [undefined, null, '', '   ', ' Bonus ', 'Disc 2: Live']
const TITLES = [undefined, '', 'Silence', 'Hunter', 'Élégie']
const DATES = [undefined, null, '', '2008', '2008-04-28', '199', 'N/A', '1975-09-12']
const ALBUMS = [undefined, '', 'Third', 'THIRD', 'Third (Deluxe Edition)', 'Super Deluxe', 'Remastered', 'ΣΟΦΟΣ', 'σοφος', 'Box Set', ' Third ']
const SECONDARY = [undefined, null, [], ['Live'], ['Compilation'], ['Remix', 'Live'], ['Soundtrack'], ['Mixtape/Street'], ['live']]

function madeTrack() {
  const track = {}
  if (chance(0.8)) track.position = pick([null, 1, 2, 3, 7])
  if (chance(0.7)) track.title = pick(TITLES)
  if (chance(0.7)) track.length = pick([null, 0, 214000, 2.5])
  if (chance(0.3)) track['artist-credit'] = pick(CREDITS)
  if (chance(0.8)) {
    const recording = {}
    if (chance(0.7)) recording.title = pick(TITLES)
    if (chance(0.7)) recording.length = pick([null, 0, 213999])
    if (chance(0.3)) recording.video = pick([true, false, null])
    if (chance(0.3)) recording['artist-credit'] = pick(CREDITS)
    track.recording = recording
  }
  return track
}

function madeRelease(at, withTracks) {
  const release = { id: pick([`release-${at}`, RELEASE_A, RELEASE_B]) }
  if (chance(0.85)) release.title = pick(ALBUMS)
  if (chance(0.7)) release.date = pick(DATES)
  if (chance(0.5)) release.country = pick([null, '', 'GB', 'XE'])
  if (chance(0.6)) release.disambiguation = pick([null, '', 'deluxe edition', 'remaster', 'boxset'])
  if (chance(0.4)) release.packaging = pick([null, 'Box', 'Jewel Case'])
  if (chance(0.7)) {
    release['release-events'] = pick([
      [], [{ date: '2008-04-28', area: { 'iso-3166-1-codes': ['GB'] } }], [{ date: '', area: { 'iso-3166-1-codes': [] } }],
      [{ area: null }], [{ date: '1999', area: { 'iso-3166-1-codes': ['XE', 'XW'] } }, { date: '2001', area: { 'iso-3166-1-codes': ['US'] } }],
      [{ date: null, area: { 'iso-3166-1-codes': [''] } }], [{ date: '2014-03' }],
    ])
  }
  if (chance(0.6)) {
    release['label-info'] = pick([
      [], [{ 'catalog-number': 'CID 8018', label: { name: 'Island' } }],
      [{ 'catalog-number': null }, { 'catalog-number': '' }, { 'catalog-number': 'ABC 1' }, { 'catalog-number': 'ABC 2' }],
    ])
  }
  if (chance(0.7)) release['artist-credit'] = pick(CREDITS)
  if (chance(0.9)) {
    release.media = [...Array(between(0, 3)).keys()].map(() => {
      const medium = {}
      if (chance(0.7)) medium.position = pick([null, 1, 2, 3])
      if (chance(0.8)) medium.format = pick(FORMATS)
      if (chance(0.6)) medium.title = pick(DISC_TITLES)
      if (chance(0.8)) medium['track-count'] = pick([null, 0, 1, 4, 11, 12])
      if (withTracks && chance(0.95)) medium.tracks = [...Array(between(0, 4)).keys()].map(madeTrack)
      return medium
    })
  }
  return release
}

function madeGroup(at) {
  const group = { id: `group-${at}` }
  if (chance(0.85)) group.title = pick(ALBUMS)
  if (chance(0.8)) group['first-release-date'] = pick(DATES)
  if (chance(0.8)) group['primary-type'] = pick([null, 'Album', 'Single', 'EP'])
  if (chance(0.7)) group['secondary-types'] = pick(SECONDARY)
  if (chance(0.8)) group.score = pick([null, 0, 100, 98, 41.5])
  return group
}

const FIELD_YEARS = ['', '2008', '1975', ' 2008 ', '199']
function madeFields() {
  return {
    artist: pick(['Portishead', '', 'Ye']),
    album: pick(['Third', 'third', '', ' Third ', 'ΣΟΦΟΣ', 'Wish You Were Here']),
    year: pick(FIELD_YEARS),
    originalYear: pick(FIELD_YEARS),
    editionLabel: pick(['', 'Deluxe', '  ', ' Deluxe ']),
  }
}

function madeScanAlbum() {
  return {
    path: 'Portishead/Third (2008)',
    artist: pick(['Portishead', '', 'Kanye West']),
    album: pick(['Third', 'THIRD', '', 'σοφος', 'ΣΟΦΟΣ']),
    year: pick(['', '2008', '1999', '2014']),
    original_year: pick(['', '2008', '1975']),
    edition: pick(['', 'Standard', 'Deluxe', 'standard']),
    release_mbid: pick(['', RELEASE_A, `release-3`]),
    art: pick(['', 'file', 'embedded']),
    track_count: pick([0, 4, 11, 12]),
  }
}

function groupScores() {
  const out = []
  for (let n = 0; n < 40; n++) {
    const fields = madeFields()
    const groups = [...Array(between(0, 6)).keys()].map((at) => madeGroup(`${n}-${at}`))
    const target = { album: fields.album, year: fields.year, original_year: fields.originalYear }
    const scores = groups.map((group) => Rel.scoreReleaseGroupMatch(group, target))
    const ranked = [...groups].sort((a, b) => Rel.scoreReleaseGroupMatch(b, target) - Rel.scoreReleaseGroupMatch(a, target))
    out.push({ fields, groups, scores, ranked: ranked.map((group) => groups.indexOf(group)) })
  }
  return out
}

function releaseScores() {
  const out = []
  for (let n = 0; n < 40; n++) {
    const album = madeScanAlbum()
    const releases = [...Array(between(0, 6)).keys()].map((at) => madeRelease(`${n}-${at}`, false))
    const found = [...releases].sort((a, b) => Rel.scoreReleaseMatch(b, album) - Rel.scoreReleaseMatch(a, album))
    out.push({
      album, releases,
      rows: releases.map((release) => {
        const tracks = Rel.releaseTrackCount(release)
        return {
          score: Rel.scoreReleaseMatch(release, album),
          tracks,
          described: Rel.describeRelease(release),
          detail: detailOf(release, Rel.describeRelease),
          trackWords: trackWordsOf(release, tracks),
          mismatch: mismatchOf(tracks, album),
          current: Rel.isCurrentRelease(release, album.release_mbid),
        }
      }),
      ranked: found.map((release) => releases.indexOf(release)),
    })
  }
  return out
}

/* ===== the payload ===== */

//? A pressing as the editor holds it: its tracklist fetched, the group it was found in carried across by hand
function held(release, group) {
  return { ...release, _groupMbid: group ? group.id : null, _firstReleaseDate: group ? (group['first-release-date'] ?? null) : null }
}

function payloads() {
  const out = []
  for (let n = 0; n < 140; n++) {
    const album = madeScanAlbum()
    const fields = chance(0.3) ? seedFieldsOf(album) : madeFields()
    const group = chance(0.8) ? madeGroup(n) : null
    const release = chance(0.8) ? madeRelease(n, true) : null
    const selected = release ? held(release, group) : null
    const payload = payloadOf(selected, fields, album, Rel.buildRetagRelease)
    let seeded = null
    if (selected) seedOf(selected, album, selected._groupMbid, selected._firstReleaseDate, Rel.buildRetagRelease, Rel.currentName, (next) => { seeded = next })
    const context = { artist: album.artist, album: album.album, releaseGroupMbid: selected?._groupMbid ?? null, firstReleaseDate: selected?._firstReleaseDate ?? null }
    out.push({
      album, fields, group, release,
      payload,
      built: release ? Rel.buildRetagRelease(release, context) : null,
      //? what a Get would send for the same pressing (releasePayload.ts) - the differences the port must keep
      download: release ? RP.releasePayload(release, RP.groupContext(group ?? { id: '' })) : null,
      seeded,
    })
  }
  return out
}

function realPressings() {
  const out = []
  for (const name of PRESSINGS) {
    const fixture = JSON.parse(fs.readFileSync(path.join(REPO, 'tests/fixtures/pressings', `${name}.json`), 'utf8'))
    const group = { id: fixture.group.id, title: fixture.group.title, 'first-release-date': fixture.releases.map((r) => r.date).filter(Boolean).sort()[0] ?? null }
    const releases = fixture.releases
    const album = { path: `x/${name}`, artist: fixture.group.artist ?? '', album: fixture.group.title ?? '', year: '', original_year: '', edition: 'Standard',
      release_mbid: releases[Math.floor(releases.length / 2)]?.id ?? '', art: '', track_count: Rel.releaseTrackCount(releases[0] ?? {}) }
    const found = [...releases].sort((a, b) => Rel.scoreReleaseMatch(b, album) - Rel.scoreReleaseMatch(a, album))
    const fields = seedFieldsOf(album)
    out.push({
      name, group, album, releases,
      ranked: found.map((release) => release.id),
      built: releases.map((release) => {
        let seeded = null
        const selected = held(release, group)
        seedOf(selected, album, selected._groupMbid, selected._firstReleaseDate, Rel.buildRetagRelease, Rel.currentName, (next) => { seeded = next })
        return { id: release.id, payload: payloadOf(selected, fields, album, Rel.buildRetagRelease), seeded,
          described: Rel.describeRelease(release), detail: detailOf(release, Rel.describeRelease) }
      }),
    })
  }
  return out
}

function seeds() {
  const out = []
  for (let n = 0; n < 30; n++) {
    const album = madeScanAlbum()
    out.push({ album, fields: seedFieldsOf(album), fetchArt: fetchArtOf(album), unselected: payloadOf(null, seedFieldsOf(album), album, Rel.buildRetagRelease) })
  }
  return out
}

/* ===== the preview's and the apply's words ===== */

const FILES = ['01 Silence.flac', '02 Hunter.flac', '10 Threads.flac']
const TAGS = ['title', 'artist', 'tracknumber', 'date', 'originaldate', 'album', 'musicbrainz_albumid', 'discnumber', 'discsubtitle', 'albumartist']

function madePlan() {
  const moves = chance(0.6)
  const merge = moves && chance(0.3)
  const fileCount = pick([0, 1, 3, 12])
  const files = FILES.slice(0, between(0, 3)).map((filename) => {
    const changes = {}
    //? in an order of their own, never sorted: the server's order is the one drawn
    for (const tag of TAGS.filter(() => chance(0.35)).reverse()) changes[tag] = { from: pick(['', 'Old', 'Ünï']), to: pick(['New', '', '2008']) }
    return { filename, matched: chance(0.8), track_title: pick(['Silence', '']), changes }
  })
  return {
    album_path: 'Portishead/Third (2008)',
    source: '/music/Portishead/Third (2008)',
    target: moves ? '/music/Portishead/Third (2008) [Deluxe]' : null,
    target_path: moves ? 'Portishead/Third (2008) [Deluxe]' : null,
    moves, merge,
    merge_detail: merge ? { into: 'Portishead/Third (2008)', discs_here: pick([[2], [2, 3], []]), discs_there: pick([[1], [1, 3], []]), kept_back: pick([[], ['cover.jpg'], ['cover.jpg', 'notes.txt']]) } : pick([null, undefined]),
    edition_label: pick(['', 'Deluxe']),
    files,
    changed_file_count: pick([0, 1, 3, 11]),
    file_count: fileCount,
    matched_tracks: fileCount,
    expected_tracks: fileCount,
    art: { action: pick(['', 'download', 'replace']), reason: pick(['', 'no release to fetch art for']), existing: pick([null, 'cover.jpg', 'folder.png']), size: pick([undefined, '250', '500', '1200', 'full', '']) },
    problems: pick([[], ['the release has 12 tracks, the folder 11'], ['a', 'b']]),
    empty: chance(0.15),
    rename_wait: pick([undefined, 0, 5, 30, 90, 2.5]),
    rename_by: pick([undefined, null, 'navidrome', 'timer']),
  }
}

function madeResults() {
  return {
    mode: 'apply', dry_run: false,
    tagged: pick([0, 1, 11]), failed: pick([0, 0, 1, 2]),
    moved_to: pick([null, '/music/Portishead/Third (2008) [Deluxe]']),
    merged: pick([undefined, false, true]),
    art_written: pick([null, 'cover.jpg', '']),
    problems: pick([[], ['the release has 12 tracks, the folder 11'], ['renamed later: Navidrome had not scanned']]),
  }
}

function plans() {
  const out = []
  for (let n = 0; n < 120; n++) {
    const plan = madePlan()
    const body = JSON.stringify(plan)
    out.push({
      body,
      order: plan.files.map((file) => Object.keys(file.changes)),
      moveLabel: Plan.moveLabel(plan),
      renameWait: Plan.renameWaitWords(plan),
      merge: Plan.mergeWords(plan),
      summary: Plan.changeSummary(plan),
      applying: Plan.applyingLabel(plan),
      coverToggle: coverToggleOf(plan),
      coverHint: coverHintOf(plan),
      editionPlaceholder: editionPlaceholderOf(plan),
    })
  }
  const results = []
  for (let n = 0; n < 60; n++) {
    const result = madeResults()
    const plan = chance(0.8) ? madePlan() : null
    results.push({ results: result, plan, applied: Plan.appliedWords(result), writeFailed: Plan.writeFailedWords(result.failed),
      newProblems: newProblemsOf(result, plan) })
  }
  const discs = [[], [1], [2], [1, 2], [1, 2, 3], [10, 2]].map((list) => ({ discs: list, words: Plan.discWords(list) }))
  const noPlan = { applying: Plan.applyingLabel(null), coverToggle: coverToggleOf(null), coverHint: coverHintOf(null), editionPlaceholder: editionPlaceholderOf(null) }
  const covers = [{ art: '' }, { art: 'file' }, { art: 'embedded' }].map((album) => ({ art: album.art, label: coverOnlyOf(album), hint: coverOnlyHintOf(album) }))
  const saved = [{ written: 'cover.jpg', replaced: null }, { written: 'cover.png', replaced: 'cover.jpg' }, { written: 'cover.jpg', replaced: '' }]
    .map((result) => ({ ...result, said: coverSavedOf(result) }))
  const originals = ['', '2008', ' '].map((year) => ({ year, placeholder: originalPlaceholderOf({ year }) }))
  const incoming = []
  for (const selectedId of [null, RELEASE_B]) for (const release of ['', RELEASE_A]) incoming.push({ selectedId, release, incoming: incomingOf(selectedId, { release_mbid: release }) })
  return { plans: out, results, discs, noPlan, covers, saved, originals, incoming }
}

/* ===== output: plain ASCII ===== */

const out = {
  folders: folders(),
  choices: choices(),
  typed: typedMatches(),
  statuses: statuses(),
  follow: follow(),
  parts: parts(),
  queue: queue(),
  queries: queries(),
  groupScores: groupScores(),
  releaseScores: releaseScores(),
  payloads: payloads(),
  pressings: realPressings(),
  seeds: seeds(),
  plans: plans(),
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
  about: "Edit album (lib/albumEdit.ts, lib/release.ts, lib/retagPlan.ts, lib/metadataQueue.ts, lib/typedMatch.ts, lib/releasePayload.ts run as they are; components/MetadataEditor.tsx's rules and words read out of its source): which folder, choosing it, what the editor says, following the album, what is wrong, and the Release editor's queries, scores, payload, seeds and words.",
  made_by: MADE_BY,
  made_from: Object.fromEntries(Object.keys(madeFrom).sort().map((key) => [key, madeFrom[key]])),
  words,
  ...out,
}
const listed = new Set(['folders', 'typed', 'statuses', 'groupScores', 'releaseScores', 'payloads', 'pressings', 'seeds'])
const body = [
  '{',
  Object.entries(fixture).map(([key, value]) => listed.has(key)
    ? `  ${flat(key)}: [\n${value.map((row) => `    ${flat(row)}`).join(',\n')}\n  ]`
    : `  ${flat(key)}: ${flat(value)}`).join(',\n'),
  '}',
  '',
].join('\n')

const counted = `${out.folders.length} folder cases, ${out.statuses.length} statuses, ${out.payloads.length} payloads, ${out.plans.plans.length} plans`
if (CHECK) {
  if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== body) {
    console.log(`Edit album's fixture differs from what the web app's TypeScript answers now: ${path.relative(REPO, FIXTURE)}.`)
    console.log(`Run node ${MADE_BY}, and see what the Swift port must follow.`)
    process.exit(1)
  }
  console.log(`Edit album's fixture matches the web app's TypeScript (${counted}).`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, body)
  console.log(`Wrote ${path.relative(REPO, FIXTURE)}: ${counted}, ${Math.round(body.length / 1024)} KB`)
}
