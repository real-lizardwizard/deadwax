#!/usr/bin/env node
/**
 * Needs a look on the iPhone app (Phase 8, slice 6 - notes/ios-specs/phase8-managing.md 5): the review queue, its count
 * and the editor's queue mode - written as a fixture the Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/NeedsLook.swift,
 * ScanAlbums.swift's MetadataQueue, Managing.swift's asksQueueSummary and needsLook) replays in
 * Tests/DeadwaxCoreTests/CareVectorTests.swift.
 *
 * Compiles lib/needsLook.ts, lib/metadataQueue.ts and lib/permissions.ts with the repo's TypeScript and runs them AS
 * THEY ARE, on inputs from the plain to the awkward: albums under folded and accented names (localeCompare's order),
 * new imports clean and not, issues marked fine and since fixed, a code the server never described, two kinds of issue
 * with as many albums (their labels decide) - and with the same label too (the order each was first met in decides,
 * both ways round); every facet of each (and ones emptied, unknown or ''), the counts, the
 * marks; and sessions run step by step - writes to the current row and to others, renames, a disc folder merged into
 * another row's, deletes, steps past either end, to albums gone from the scan, and the end.
 * And reads out of app/NeedsALook.tsx what the page works out itself - the facets held and shown, the rows drawn,
 * the facet pressed, a session's ending held and let go, a read to trust, a chosen facet given up, a read again on
 * showing, a row's two lines and its words, the line at the top, the state and status ladders - out of
 * components/MetadataEditor.tsx the queue's buttons, out of app/You.tsx the Manage row's count and what VoiceOver
 * hears, out of app/useQueueSummary.ts the count's rules and out of app/App.tsx who the page is for - each by a
 * pattern, compiled and run as written; and every sentence those say that the phone says too. A pattern that no
 * longer matches stops this script, naming what moved.
 * Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/care/care-vectors.json.
 *
 * The file names each source it was made from with its sha256, so ui/test/ioscare.sim.cjs - which runs this with
 * --check - fails when one changes, in what it does or only in its text, until the fixture is written again and the
 * Swift port follows. The output is plain ASCII (anything else as a \u escape), so a run on any machine writes the same
 * bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-care-vectors.cjs           write the fixture
 *   node ios/scripts/export-care-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'care', 'care-vectors.json')
const CHECK = process.argv.includes('--check')
const MADE_BY = 'ios/scripts/export-care-vectors.cjs'
const SOURCES = ['lib/needsLook.ts', 'lib/metadataQueue.ts', 'lib/permissions.ts']
const PAGE = 'app/NeedsALook.tsx'
const EDITOR = 'components/MetadataEditor.tsx'
const YOU = 'app/You.tsx'
const COUNT = 'app/useQueueSummary.ts'
const APP = 'app/App.tsx'
const CARE = 'lib/libraryCare.ts'
const REQUESTS = 'lib/requestsView.ts'

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

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-care-vectors-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES.map((file) => `src/${file}`),
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const N = require(path.join(OUT, 'lib/needsLook.js'))
const Q = require(path.join(OUT, 'lib/metadataQueue.js'))
const P = require(path.join(OUT, 'lib/permissions.js'))
const ts = require(path.join(UI, 'node_modules/typescript'))
fs.rmSync(OUT, { recursive: true, force: true })

/** A TypeScript expression or body, its types stripped by TypeScript itself, as a function of `names`. */
function compiled(names, body) {
  const js = ts.transpileModule(`module.exports = function (${names.join(', ')}) {\n${body}\n}`, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
  }).outputText
  const module = { exports: null }
  new Function('module', 'exports', js)(module, module.exports)
  return module.exports
}

let seed = 8349
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const between = (low, high) => low + Math.floor(rand() * (high - low + 1))
const chance = (p) => rand() < p

/* ===== NeedsALook.tsx's own, read out of it ===== */

//? the list as drawn, and a session's rows as drawn (keyed by the path each was listed at)
const asRows = compiled([], `${piece(PAGE, /\n(const asRows = [^\n]+)\n/, 'the rows drawn')[1]}\nreturn asRows`)()
const sessionRows = compiled([], `${piece(PAGE, /\n(const sessionRows = [^\n]+)\n/, "a session's rows drawn")[1]}\nreturn sessionRows`)()
//? the facets held while a session lasts and while its rows are held
const chipsOf = compiled(['session', 'heldChips', 'ending', 'liveChips'],
  `return ${piece(PAGE, /\n\s*const chips = ([^\n]+)\n/, 'the facets held')[1]}`)
//? the facet the list is narrowed by
const showingOf = compiled(['session', 'liveChips', 'facet', 'facetShown'],
  `return ${piece(PAGE, /\n\s*const showing = ([^\n]+)\n/, 'the facet shown')[1]}`)
const albumsOf = compiled(['library', 'showing', 'facetAlbums'],
  `return ${piece(PAGE, /const albums = useMemo\(\(\) => (facetAlbums\(library\.albums, showing\)), \[library\.albums, showing\]\)/, 'the albums listed')[1]}`)
const rowsOf = compiled(['session', 'ending', 'albums', 'sessionRows', 'asRows'],
  `return ${piece(PAGE, /\n\s*const rows: DrawnRow\[\] = ([^\n]+)\n/, 'the rows')[1]}`)
const pressedOf = compiled(['session', 'ending', 'showing'],
  `return ${piece(PAGE, /\n\s*const pressed = ([^\n]+)\n/, 'the facet pressed')[1]}`)
const drawnOf = compiled(['chips'],
  `return chips.filter(${piece(PAGE, /\{chips\.filter\((\(chip\) => chip\.id === null \|\| chip\.count > 0)\)\.map/, 'the facets drawn')[1]})`)
//? a session's end, held on screen until a fresh read lands - and let go
const endingOf = compiled(['was', 'heldNow', 'libraryChips', 'sessionRows'],
  `return ${piece(PAGE, /setEnding\((\{ rows: sessionRows\(was\), chips: heldNow\.current \?\? libraryChips\.current, facet: was\.facet, read: false \})\)/, 'the ending held')[1]}`)
const releasedOf = compiled(['ending', 'library'],
  `return !!(${piece(PAGE, /if \((ending\?\.read && !library\.loading)\) \{\n\s*setEnding\(null\)\n\s*setHeldChips\(null\)/, 'the ending let go')[1]})`)
const realOf = compiled(['library'], `return !!(${piece(PAGE, /\n\s*const real = ([^\n]+)\n/, 'a read to trust')[1]})`)
const checkingOf = compiled(['library'], `return !!(${piece(PAGE, /\n\s*const checking = ([^\n]+)\n/, 'checking')[1]})`)
const givenUpOf = compiled(['allowed', 'shown', 'real', 'session', 'ending', 'facet', 'showing'],
  `return !!(${piece(PAGE, /if \((allowed && shown && real && !session && !ending && facet !== null && showing === null)\) onFacet\(null\)/, 'a facet given up')[1]})`)
const againOf = compiled(['allowed', 'shown', 'wasShown', 'library', 'sessionNow', 'ending'],
  `return !!(${piece(PAGE, /if \((allowed && shown && !wasShown\.current && library\.loaded && !sessionNow\.current && !ending)\) void library\.reload\(false\)/, 'read again on showing')[1]})`)
//? a row's two lines
const titleOf = compiled(['album'], `return ${piece(PAGE, /<span class="app-queue-album">\{(album\.album \|\| album\.path)\}<\/span>/, "a row's title")[1]}`)
const bylineOf = compiled(['album'], `const edition = ${piece(PAGE, /const edition = (album\.disc_label \|\| album\.edition)\n/, "a row's edition")[1]}
return ${piece(PAGE, /<span class="app-queue-artist">\{(\[album\.artist, edition\]\.filter\(Boolean\)\.join\(' · '\))\}<\/span>/, "a row's byline")[1]}`)
//? a row's words: its mark, else New, each outstanding issue's label, and under Marked fine "Marked fine"
piece(PAGE, /\{mark \? \(\n\s*<span class="app-queue-mark">\{MARK_WORDS\[mark\]\}<\/span>/, "a row's mark")
const newWord = piece(PAGE, /\{isNewImport\(album\) && <span class="app-queue-chip is-new">([^<]+)<\/span>\}/, "a row's New")[1]
piece(PAGE, /\{outstandingIssues\(album\)\.map\(\(code\) => \([\s\S]*?\{issueLabel\(code, library\.issueTypes\)\}/, "a row's issues")
const ignoredWhen = compiled(['pressed', 'IGNORED_FACET', 'isIgnoredOnly', 'album'],
  `return !!(${piece(PAGE, /\{(pressed === IGNORED_FACET && isIgnoredOnly\(album\)) && \(/, "a row's Marked fine, when")[1]})`)
piece(PAGE, /\{MARKED_FINE\}\n\s*<\/span>/, "a row's Marked fine")
const markedFineTitleOf = compiled(['album', 'library', 'MARKED_FINE', 'markedFineIssues', 'issueLabel'],
  `return ${piece(PAGE, /title=\{(`\$\{MARKED_FINE\}: \$\{markedFineIssues\(album\)\.map\(\(code\) => issueLabel\(code, library\.issueTypes\)\)\.join\(', '\)\}`)\}/, "a row's Marked fine title")[1]}`)
//? (review, 16 Nov) their order as the page writes them, read from where each sits in the row's chips - the whole
//? block hashed, so moving one of them stops this script; a mark, written first, stands in for all of them
const chipsBlock = piece(PAGE, /<span class="app-queue-chips">\n([\s\S]*?)\n\s*<\/span>\n\s*<\/button>/, "a row's chips, in order")[1]
if (!/^\s*\{mark \? \(\n\s*<span class="app-queue-mark">\{MARK_WORDS\[mark\]\}<\/span>\n\s*\) : \(/.test(chipsBlock)) {
  throw new Error(`a row's mark no longer stands in for its chips in ui/src/${PAGE} - change this script with it`)
}
function chipAt(text, what) {
  const at = chipsBlock.indexOf(text)
  if (at < 0) throw new Error(`couldn't find ${what} among a row's chips in ui/src/${PAGE} - change this script with it`)
  return at
}
const chipParts = [
  { at: chipAt('{isNewImport(album) && ', 'New'), words: (album) => (Q.isNewImport(album) ? [newWord] : []) },
  { at: chipAt('{outstandingIssues(album).map(', 'the issues'),
    words: (album, pressed, issueTypes) => Q.outstandingIssues(album).map((code) => Q.issueLabel(code, issueTypes)) },
  { at: chipAt('{pressed === IGNORED_FACET && isIgnoredOnly(album) && (', 'Marked fine'),
    words: (album, pressed) => (ignoredWhen(pressed, N.IGNORED_FACET, N.isIgnoredOnly, album) ? [N.MARKED_FINE] : []) },
].sort((one, other) => one.at - other.at)
function rowChips(row, pressed, issueTypes) {
  if (row.mark) return [N.MARK_WORDS[row.mark]]
  return chipParts.flatMap((part) => part.words(row.album, pressed, issueTypes))
}
//? the line at the top, and NEEDS_EDIT under it without Edit albums
const leadOf = compiled(['canEdit', 'NEEDS_LOOK_LINE', 'NEEDS_LOOK_LINE_NO_EDIT'],
  `return ${piece(PAGE, /<p class="app-queue-line">\{(canEdit \? NEEDS_LOOK_LINE : NEEDS_LOOK_LINE_NO_EDIT)\}<\/p>/, 'the line')[1]}`)
const needsEditOf = compiled(['canEdit'],
  `return !!(${piece(PAGE, /\{(!canEdit) && <p class="app-queue-line app-queue-no-edit">\{NEEDS_EDIT\}<\/p>\}/, 'needs edit, when')[1]})`)
says(PAGE, '{ignoresUnsaved(library, tracking) && <p class="app-queue-warning">{IGNORES_UNSAVED}</p>}', 'the ignores warning')
says(PAGE, 'const navidrome = navidromeNote(library.navidromeCheck ?? null, seesDetail(accessNow()))', 'the Navidrome note')
//? the ladders: before the list, and the status line over it (always there, a line tall)
piece(PAGE, /\{library\.problem \? \(\n\s*<p class="app-queue-state">\{library\.problem\}<\/p>\n\s*\) : !library\.loaded \? \(\n\s*<div class="pl-spinner" aria-label="Reading the library" \/>\n\s*\) : library\.error && !library\.albums\.length \? \(/, 'the state')
const stateOf = (library) => library.problem ? 'problem' : !library.loaded ? 'reading' : library.error && !library.albums.length ? 'failed' : 'list'
const checkingWords = piece(PAGE, /<p class="app-queue-checking" role="status">\n\s*\{library\.error \? \([\s\S]*?\) : checking \? \(\n\s*'([^']+)'\n\s*\) : navidrome \? \(/, 'the status')[1]
const statusOf = (library, checking, navidrome) => library.error ? 'failed' : checking ? 'checking' : navidrome ? 'navidrome' : null
says(PAGE, '{errorNote(library.error, { failed: READ_FAILED, retry: true })}', 'a first read failed')
says(PAGE, "{sayError(library.error, '', { failed: CHECK_FAILED, retry: true })}", 'a read again failed')
//? a session: started on the list as shown, stepped by stepTarget over the page's own scan, each album left reviewed
says(PAGE, 'const begun = startSession(albums, path, showing)', 'a session begun')
says(PAGE, 'const paths = new Set(libraryNow.current.albums.map((album) => album.path))\n    const target = stepTarget(was, index, (path) => paths.has(path))', 'a step')
says(PAGE, 'path ? libraryApi.markReviewed(path).then(() => askQueueSummary(), () => undefined) : Promise.resolve()', 'an album left reviewed')
says(PAGE, 'const noted = reviewLeaving ? review(leavingAtEnd(was)) : marked', 'the end reviews the album left')
says(PAGE, 'const next = rowChanged(was, change)', 'a write heard')
says(PAGE, 'folder: at.rows[at.index]!.path,\n    reread,\n    queue: {\n      position: at.index + 1,\n      total: at.rows.length,', "the editor's request")
says(PAGE, 'if (ending) return', 'no session while rows are held')

const words = {
  title: piece(PAGE, /<h1 class="pl-large-title">([^<]+)<\/h1>/, 'the title')[1],
  nothing: piece(PAGE, /<p class="app-queue-state">(Nothing needs a look\.)<\/p>/, 'nothing')[1],
  reading: piece(PAGE, /<div class="pl-spinner" aria-label="([^"]+)" \/>/, 'reading')[1],
  tryAgain: piece(PAGE, /onClick=\{retry\}>\n\s*(Try again)\n/, 'try again')[1],
  show: piece(PAGE, /role="group" aria-label="([^"]+)"/, 'show')[1],
  checking: checkingWords,
  newWord,
  readFailed: piece(CARE, /export const READ_FAILED = "([^"]+)"/, 'READ_FAILED')[1],
  checkFailed: piece(CARE, /export const CHECK_FAILED = "([^"]+)"/, 'CHECK_FAILED')[1],
  line: N.NEEDS_LOOK_LINE,
  lineNoEdit: N.NEEDS_LOOK_LINE_NO_EDIT,
  needsEdit: P.NEEDS_EDIT,
  ignoresUnsaved: N.IGNORES_UNSAVED,
  markedFine: N.MARKED_FINE,
  marks: N.MARK_WORDS,
  newFacet: N.NEW_FACET,
  ignoredFacet: N.IGNORED_FACET,
  navidromeUnset: N.NAVIDROME_UNSET,
  navidromeScanning: N.NAVIDROME_SCANNING,
  navidromeWaiting: N.NAVIDROME_WAITING,
  noPermission: P.NO_PERMISSION,
  //? the editor's queue buttons, and the Manage row's words
  previous: piece(EDITOR, /title="(Previous album)"\n\s*aria-label="Previous album"/, 'previous')[1],
  skipHint: piece(EDITOR, /disabled=\{queue\.position >= queue\.total\}\n\s*title="([^"]+)"/, 'skip, its title')[1],
  skip: piece(EDITOR, /onClick=\{queue\.onNext\}\n\s*>\n\s*(Skip ▷)\n/, 'skip')[1],
  nextAlbum: piece(EDITOR, /<button type="button" id="metadata-apply-button" onClick=\{queue\.onNext\}>\n\s*(Next album ▷)\n/, 'next album')[1],
  row: piece(YOU, /<span class="app-row-label">(Needs a look)<\/span>/, 'the Manage row')[1],
}
says(EDITOR, '{queue.position} of {queue.total}', 'where it is')

//? the editor's queue buttons, as written
const backOf = compiled(['queue'], `return !(${piece(EDITOR, /disabled=\{(queue\.position <= 1)\}/, 'previous, when')[1]})`)
const onOf = compiled(['queue'], `return !(${piece(EDITOR, /disabled=\{(queue\.position >= queue\.total)\}/, 'skip, when')[1]})`)
const nextShownOf = compiled(['applied', 'queue'],
  `return !!(${piece(EDITOR, /\{(applied && queue && queue\.position < queue\.total) \? \(/, 'next album, when')[1]})`)

//? the Manage row: its value and what VoiceOver hears
const badgeText = compiled(['count'], piece(REQUESTS, /export function badgeText\(count: number\): string \{\n([\s\S]*?)\n\}/, 'badgeText')[1])
const valueOf = compiled(['needsLook', 'badgeText'],
  `return ${piece(YOU, /\{(badgeText\(needsLook \?\? 0\)) && \(\n\s*<span class="app-queue-badge" aria-hidden="true">/, 'the count')[1]}`)
const spokenOf = compiled(['needsLook', 'needsLookLabel', 'row'],
  `const attributes = ${piece(YOU, /\{\.\.\.\((needsLook \? \{ 'aria-label': needsLookLabel\('Needs a look', needsLook\) \} : \{\})\)\}/, 'the count spoken')[1]}
return attributes['aria-label'] ?? row`)
const allowedOf = piece(APP, /<NeedsALook\n\s*allowed=\{(perms\.has\('library'\))\}\n\s*canEdit=\{(perms\.has\('edit'\))\}/, 'who the page is for')
const pageOf = compiled(['perms'], `return { allowed: ${allowedOf[1]}, canEdit: ${allowedOf[2]} }`)

//? the count's own rules (useQueueSummary.ts)
const trackingOf = compiled(['answer'], `return ${piece(COUNT, /tracking = (answer\.tracking_enabled !== false)\n/, 'tracking')[1]}`)
says(COUNT, 'server = answer.total', 'the count')
says(COUNT, 'if (!asksQueueSummary(accessNow().permissions)) return', 'asked only with Look after the library')
says(COUNT, 'if (asking) again = true\n  else ask()', 'one request in flight')
says(COUNT, 'asking = false\n    if (again) {\n      again = false\n      ask()\n    }', 'one more after it')
says(COUNT, '//? kept as it was - the next change asks again', 'a failure keeps the count')
says(COUNT, 'return page ?? server', "the page's count")

/* ===== the cases ===== */

const CODES = ['no_release', 'no_artist_tag', 'mixed_tags', 'not_in_navidrome', 'split_discs', 'artist_split', 'misfiled',
  'no_original_year', 'no_year', 'untitled_tracks', 'unnumbered_tracks', 'no_art']
const SEVERITY = { no_release: 3, no_artist_tag: 3, mixed_tags: 3, not_in_navidrome: 2, split_discs: 2, artist_split: 2,
  misfiled: 2, no_original_year: 2, no_year: 2, untitled_tracks: 2, unnumbered_tracks: 1, no_art: 1, mystery_code: 1 }
const ISSUE_TYPES = {
  //? the server's labels (src/metadata_health.py ISSUE_TYPES), hints shortened; one code it never described
  plain: {
    no_release: { label: 'Not matched to MusicBrainz', hint: 'Find their release and apply it.', severity: 3 },
    no_artist_tag: { label: 'No artist tag', hint: 'Not one file names an artist.', severity: 3 },
    mixed_tags: { label: 'Mixed tags', hint: 'The files disagree about which album they belong to.', severity: 3 },
    not_in_navidrome: { label: 'Not in Navidrome', hint: "Navidrome doesn't list this album.", severity: 2 },
    split_discs: { label: 'Split across folders', hint: 'Some discs are in another folder.', severity: 2 },
    artist_split: { label: 'Artist under two names', hint: 'Move albums to … moves them.', severity: 2 },
    misfiled: { label: "Folder name doesn't match the tags", hint: 'Applying a release renames it.', severity: 2 },
    no_original_year: { label: 'No original year', hint: '', severity: 2 },
    no_year: { label: 'No year', hint: 'No file says when it was released.', severity: 2 },
    untitled_tracks: { label: 'Untitled tracks', hint: 'Some files have no title.', severity: 2 },
    unnumbered_tracks: { label: 'Unnumbered tracks', hint: 'Some files have no track number.', severity: 1 },
    no_art: { label: 'No cover art', hint: 'Get cover fetches one.', severity: 1 },
  },
  //? labels that tie and fold: localeCompare decides the facets' order between equal counts
  awkward: {
    no_release: { label: 'été', hint: 'accented', severity: 3 },
    no_artist_tag: { label: 'ete', hint: '', severity: 3 },
    mixed_tags: { label: 'Ete', hint: 'capital', severity: 3 },
    not_in_navidrome: { label: 'b', hint: 'b', severity: 2 },
    split_discs: { label: 'B', hint: 'B', severity: 2 },
    artist_split: { label: 'a', hint: 'a', severity: 2 },
    misfiled: { label: '10 things', hint: '', severity: 2 },
    no_original_year: { label: '9 things', hint: '', severity: 2 },
    no_year: { label: 'Æther', hint: '', severity: 2 },
    untitled_tracks: { label: 'aether', hint: '', severity: 2 },
    unnumbered_tracks: { label: 'z', hint: '', severity: 1 },
    no_art: { label: 'No cover art', hint: '', severity: 1 },
  },
  //? (review, 16 Nov) labels the same and counts the same: only the order each was first met in decides (the Map's)
  same: {
    no_release: { label: 'Same', hint: '', severity: 3 },
    no_artist_tag: { label: 'Same', hint: '', severity: 3 },
    mixed_tags: { label: 'Same', hint: '', severity: 3 },
  },
}
const ARTISTS = ['Tame Impala', 'tame impala', 'Björk', 'Bjork', 'Émile', 'Emile', 'ABBA', 'abba', 'The Beatles',
  '10cc', '2Pac', 'Sigur Rós', '日本', 'Ølafur', 'Zola', 'zola', '', 'a', 'B', 'Björk']
const TITLES = ['Currents', 'currents', 'Debut', 'Post', 'Été', 'Ete', 'Abbey Road', '', '1999', '99', 'Z', 'a',
  'æther', 'Aether', 'The Slow Rush']
const EDITIONS = ['', '', '', 'Deluxe', '2011 Remaster', 'Japan']
const DISCS = ['', '', '', '', 'Disc 2', 'Discs 1–2']

let made = 0
function makeAlbum(extra = {}) {
  made += 1
  const artist = pick(ARTISTS)
  const title = pick(TITLES)
  const issues = CODES.filter(() => chance(0.12))
  if (chance(0.05)) issues.push('mystery_code')
  //? marked fine: some of its issues - and now and then one since fixed (the stored list can name it)
  const ignored = issues.filter(() => chance(0.3))
  if (chance(0.08)) ignored.push(pick(CODES))
  const outstanding = issues.filter((code) => !ignored.includes(code))
  const imported = chance(0.3)
  const album = {
    path: `${artist || '(no artist)'}/${title || '(untitled)'} [${made}]`,
    artist,
    album: title,
    edition: pick(EDITIONS),
    disc_label: pick(DISCS),
    year: chance(0.8) ? String(between(1960, 2025)) : '',
    issues,
    ignored_issues: [...new Set(ignored)],
    //? the server's own: outstanding issues - now and then not, the rules read the field
    needs_attention: chance(0.04) ? !outstanding.length : outstanding.length > 0,
    imported,
    reviewed: imported ? chance(0.4) : chance(0.2),
    severity: chance(0.08) ? between(0, 3) : Math.max(0, ...outstanding.map((code) => SEVERITY[code] ?? 1)),
    ...extra,
  }
  return album
}
const albumSet = (low, high) => Array.from({ length: between(low, high) }, () => makeAlbum())
//? two albums the same but for their folders: the list's own order kept between them (a stable sort)
function twins() {
  const one = makeAlbum({ issues: ['no_art'], ignored_issues: [], needs_attention: true, imported: false, reviewed: false, severity: 1 })
  return [one, { ...one, path: `${one.path} (twin)` }]
}

const TYPE_NAMES = ['plain', 'awkward']
const lists = []
function listCase(name, albums, types) {
  const issueTypes = ISSUE_TYPES[types]
  const chips = N.facets(albums, issueTypes)
  const facetIds = [null, '', N.NEW_FACET, N.IGNORED_FACET, 'mystery_code', 'nope', ...CODES.filter(() => chance(0.25)),
    ...chips.map((chip) => chip.id).filter((id) => id !== null)]
  const seen = new Set()
  const facets = []
  for (const facet of facetIds) {
    const key = JSON.stringify(facet)
    if (seen.has(key)) continue
    seen.add(key)
    facets.push({ facet, albums: N.facetAlbums(albums, facet).map((album) => album.path), shown: N.facetShown(chips, facet) })
  }
  lists.push({
    name, types, albums,
    queue: Q.queueAlbums(albums, null).map((album) => album.path),
    total: N.summaryTotal(albums),
    chips,
    drawn: drawnOf(chips).map((chip) => chip.id),
    facets,
    rows: albums.map((album) => ({
      path: album.path,
      newImport: Q.isNewImport(album),
      ignoredOnly: N.isIgnoredOnly(album),
      title: titleOf(album),
      byline: bylineOf(album),
      chips: Object.fromEntries([['all', null], ['ignored', N.IGNORED_FACET], ['new', N.NEW_FACET]]
        .map(([key, pressed]) => [key, rowChips({ key: album.path, album, mark: null }, pressed, issueTypes)])),
      markedFineTitle: markedFineTitleOf(album, { issueTypes }, N.MARKED_FINE, Q.markedFineIssues, Q.issueLabel),
    })),
  })
}
listCase('nothing at all', [], 'plain')
listCase('only clean albums, none new', [makeAlbum({ issues: [], ignored_issues: [], needs_attention: false, imported: false }),
  makeAlbum({ issues: [], ignored_issues: [], needs_attention: false, imported: true, reviewed: true })], 'plain')
listCase('a clean new import', [makeAlbum({ issues: [], ignored_issues: [], needs_attention: false, imported: true, reviewed: false, severity: 0 }),
  makeAlbum({ issues: ['no_art'], ignored_issues: [], needs_attention: true, imported: false, severity: 1 })], 'plain')
listCase('marked fine, and one since fixed', [
  makeAlbum({ issues: ['no_art', 'no_year'], ignored_issues: ['no_art', 'no_year'], needs_attention: false }),
  makeAlbum({ issues: ['no_art'], ignored_issues: ['no_art', 'no_release'], needs_attention: false }),
  makeAlbum({ issues: [], ignored_issues: ['no_release'], needs_attention: false }),
  makeAlbum({ issues: ['no_art', 'no_year'], ignored_issues: ['no_art'], needs_attention: true, severity: 2 }),
], 'plain')
listCase('twins', [...twins(), ...twins()], 'plain')
listCase('ties, by label', [
  makeAlbum({ issues: ['no_release'], ignored_issues: [], needs_attention: true, severity: 3 }),
  makeAlbum({ issues: ['no_artist_tag'], ignored_issues: [], needs_attention: true, severity: 3 }),
  makeAlbum({ issues: ['mixed_tags'], ignored_issues: [], needs_attention: true, severity: 3 }),
  makeAlbum({ issues: ['not_in_navidrome', 'split_discs', 'artist_split'], ignored_issues: [], needs_attention: true, severity: 2 }),
  makeAlbum({ issues: ['misfiled', 'no_original_year', 'no_year', 'untitled_tracks'], ignored_issues: [], needs_attention: true, severity: 2 }),
], 'awkward')
//? (review, 16 Nov) two facets of the same label and count, met in one order and then the other - drawn on a seed of
//? their own, so every case after them is as it was
{
  const kept = seed
  const plain = (artist, issues) => ({ path: `${artist}/Same [${artist}]`, artist, album: 'Same', edition: '', disc_label: '',
    year: '', issues, ignored_issues: [], needs_attention: true, imported: false, reviewed: false, severity: 3 })
  listCase('ties of label and count, one met first', [plain('A', ['no_release']), plain('B', ['no_artist_tag']),
    plain('C', ['mixed_tags']), plain('D', ['mixed_tags'])], 'same')
  listCase('ties of label and count, the other met first', [plain('A', ['no_artist_tag']), plain('B', ['no_release']),
    plain('C', ['mixed_tags']), plain('D', ['mixed_tags'])], 'same')
  seed = kept
}
listCase('an empty album name', [makeAlbum({ album: '', artist: '', edition: '', disc_label: '', issues: ['no_art'], ignored_issues: [], needs_attention: true })], 'plain')
for (let n = 0; n < 70; n++) listCase(`seeded ${n}`, albumSet(0, 16), pick(TYPE_NAMES))

//? marks: an album as listed, and as a write left it
const markPairs = []
const variants = (album) => [
  album,
  { ...album, issues: [], ignored_issues: [] },
  { ...album, ignored_issues: [...album.issues] },
  { ...album, ignored_issues: album.issues.slice(0, 1) },
  { ...album, issues: album.issues.slice(1) },
  { ...album, issues: [...album.issues, 'no_art'] },
  { ...album, ignored_issues: [] },
  { ...album, issues: album.issues.slice(1), ignored_issues: album.issues.slice(0, 1) },
]
for (let n = 0; n < 40; n++) {
  const listed = makeAlbum()
  for (const after of variants(listed)) markPairs.push({ listed, after, mark: N.markFor(listed, after) })
}

/* ===== sessions, run step by step ===== */

const snapshot = (session) => ({
  index: session.index,
  facet: session.facet,
  rows: session.rows.map((row) => ({ path: row.path, album: row.album.path, listed: row.listed.path, mark: row.mark, heard: row.heard })),
})

function changeFor(session) {
  const here = session.rows[session.index]
  const roll = rand()
  const row = roll < 0.7 ? here : roll < 0.9 ? pick(session.rows) : null
  const from = row ? row.path : 'Nowhere/Not listed [0]'
  const base = row ? row.album : makeAlbum()
  const kind = pick(['fix', 'fix', 'ignore', 'partial', 'unignore', 'rename', 'rename', 'merge', 'deleted', 'lost', 'review'])
  let album = null, deleted = false
  switch (kind) {
    case 'fix': album = { ...base, issues: [], ignored_issues: [], needs_attention: false, severity: 0 }; break
    case 'ignore': album = { ...base, ignored_issues: [...base.issues], needs_attention: false }; break
    case 'partial': album = { ...base, issues: base.issues.slice(1) }; break
    case 'unignore': album = { ...base, ignored_issues: [] }; break
    case 'rename': album = { ...base, path: `${base.path} (renamed)`, ...(chance(0.5) ? { issues: [], ignored_issues: [] } : {}) }; break
    //? a disc folder merged into another row's folder: two rows then share a path
    case 'merge': album = { ...base, path: pick(session.rows).path, issues: [] }; break
    case 'deleted': deleted = true; break
    case 'lost': break
    case 'review': album = { ...base, reviewed: true }; break
  }
  return { kind, from, album, deleted }
}

const sessions = []
for (let n = 0; n < 90; n++) {
  const types = pick(TYPE_NAMES)
  const albums = n % 10 === 0 ? [...twins(), ...albumSet(2, 8)] : albumSet(3, 16)
  const chips = N.facets(albums, ISSUE_TYPES[types])
  const facet = chance(0.4) ? null : chance(0.1) ? 'nope' : pick(chips).id
  const list = N.facetAlbums(albums, facet)
  //? the path to start on: a listed one, else one that isn't (no session)
  const startPath = list.length && chance(0.95) ? pick(list).path : 'Nowhere/Not listed [0]'
  let session = N.startSession(list, startPath, facet)
  const run = { types, albums, facet, list: list.map((album) => album.path), start: startPath, begun: session ? snapshot(session) : null, ops: [] }
  sessions.push(run)
  if (!session) continue
  for (let step = 0; step < 10; step++) {
    const roll = rand()
    if (roll < 0.45) {
      const change = changeFor(session)
      session = N.rowChanged(session, change)
      run.ops.push({ op: 'change', change, after: snapshot(session) })
    } else if (roll < 0.92) {
      const choice = rand()
      const index = choice < 0.5 ? session.index + 1 : choice < 0.75 ? session.index - 1 : between(-1, session.rows.length)
      //? the page's own scan: some paths gone from it (deleted outside, renamed, or a write it hasn't read)
      const known = [...new Set(session.rows.flatMap((row) => [row.path, row.listed.path]))]
      const absent = known.filter(() => chance(0.2))
      const target = N.stepTarget(session, index, (p) => !absent.includes(p))
      const result = target.kind === 'stay' ? { kind: 'stay' } : { kind: target.kind, leaving: target.leaving }
      run.ops.push({ op: 'step', index, absent, result, ...(target.kind === 'step' ? { after: snapshot(target.session) } : {}) })
      if (target.kind === 'step') session = target.session
      if (target.kind === 'end') {
        run.ops.push({ op: 'ending', ...endingCase(session, chips, ISSUE_TYPES[types]) })
        break
      }
    } else {
      run.ops.push({ op: 'end', leaving: N.leavingAtEnd(session), ...endingCase(session, chips, ISSUE_TYPES[types]) })
      break
    }
  }
}

/** A session's end as the page holds it - the facets as it began, or (none held) the live ones. */
function endingCase(session, chips, issueTypes) {
  const live = N.facets([], issueTypes)
  const held = chance(0.5) ? chips : null
  const ending = endingOf(session, { current: held }, { current: live }, sessionRows)
  return {
    held: held !== null,
    ending: { rows: ending.rows.map((row) => ({ key: row.key, album: row.album.path, mark: row.mark })), chips: ending.chips.map((chip) => chip.id), facet: ending.facet, read: ending.read },
  }
}

/* ===== the page: what it holds, shows, presses and draws ===== */

const pages = []
for (let n = 0; n < 60; n++) {
  const types = pick(TYPE_NAMES)
  const albums = albumSet(0, 10)
  const liveChips = N.facets(albums, ISSUE_TYPES[types])
  const other = albumSet(1, 6)
  const otherChips = N.facets(other, ISSUE_TYPES[types])
  const facet = pick([null, null, N.NEW_FACET, N.IGNORED_FACET, 'nope', 'no_art', ...liveChips.map((chip) => chip.id)])
  //? a session over another list (as it began, before the scan moved), or none
  const sessionList = N.facetAlbums(other, null)
  const session = chance(0.4) && sessionList.length ? N.startSession(sessionList, pick(sessionList).path, pick([null, N.NEW_FACET, 'no_art'])) : null
  const heldChips = chance(0.5) ? otherChips : null
  const endingSession = sessionList.length ? N.startSession(sessionList, sessionList[0].path, pick([null, N.IGNORED_FACET])) : null
  const ending = !session && endingSession && chance(0.4) ? endingOf(endingSession, { current: heldChips }, { current: liveChips }, sessionRows) : null
  const chips = chipsOf(session, heldChips, ending, liveChips)
  const showing = showingOf(session, liveChips, facet, N.facetShown)
  const listed = albumsOf({ albums }, showing, N.facetAlbums)
  const rows = rowsOf(session, ending, listed, sessionRows, asRows)
  const pressed = pressedOf(session, ending, showing)
  pages.push({
    types, albums, other, facet,
    session: session ? { start: session.rows[session.index].path, facet: session.facet } : null,
    held: heldChips !== null,
    ending: ending ? { facet: endingSession.facet } : null,
    chips: chips.map((chip) => ({ id: chip.id, count: chip.count })),
    drawn: drawnOf(chips).map((chip) => chip.id),
    showing,
    albumsListed: listed.map((album) => album.path),
    rows: rows.map((row) => ({ key: row.key, album: row.album.path, mark: row.mark,
      chips: rowChips(row, pressed, ISSUE_TYPES[types]) })),
    pressed,
  })
}

/* ===== the small rules, every case ===== */

const flags = [false, true]
const reads = []
for (const loaded of flags) for (const stale of flags) for (const loading of flags) for (const error of flags) {
  const library = { loaded, stale, loading, error: error ? new Error('x') : null }
  reads.push({ loaded, stale, loading, error, real: realOf(library), checking: checkingOf(library) })
}
const released = []
for (const ending of [null, { read: false }, { read: true }]) for (const loading of flags) {
  released.push({ ending: ending === null ? null : ending.read, loading, released: releasedOf(ending, { loading }) })
}
const givenUp = []
for (const allowed of flags) for (const shown of flags) for (const real of flags) for (const session of flags) for (const ending of flags)
  for (const facet of [null, N.NEW_FACET]) for (const showing of [null, N.NEW_FACET]) {
    givenUp.push({ allowed, shown, real, session, ending, facet, showing,
      givenUp: givenUpOf(allowed, shown, real, session ? {} : null, ending ? {} : null, facet, showing) })
  }
const again = []
for (const allowed of flags) for (const shown of flags) for (const wasShown of flags) for (const loaded of flags)
  for (const session of flags) for (const ending of flags) {
    again.push({ allowed, shown, wasShown, loaded, session, ending,
      again: againOf(allowed, shown, { current: wasShown }, { loaded }, { current: session ? {} : null }, ending ? {} : null) })
  }
const states = []
for (const problem of [null, '', 'LIBRARY_PATH is not set, so there is no library to read.']) for (const loaded of flags)
  for (const error of flags) for (const count of [0, 2]) {
    states.push({ problem, loaded, error, albums: count, state: stateOf({ problem, loaded, error: error ? {} : null, albums: Array(count).fill({}) }) })
  }
const statuses = []
for (const error of flags) for (const loaded of flags) for (const stale of flags) for (const loading of flags)
  for (const navidrome of [null, N.NAVIDROME_UNSET]) {
    const checking = checkingOf({ loaded, stale, loading })
    statuses.push({ error, loaded, stale, loading, navidrome, status: statusOf({ error: error ? {} : null }, checking, navidrome) })
  }
const leads = flags.map((canEdit) => ({ canEdit, line: leadOf(canEdit, N.NEEDS_LOOK_LINE, N.NEEDS_LOOK_LINE_NO_EDIT), needsEdit: needsEditOf(canEdit) }))
const unsaved = []
for (const loaded of flags) for (const reviewTracking of flags) for (const summaryTracking of [null, false, true]) {
  unsaved.push({ loaded, reviewTracking, summaryTracking, warn: N.ignoresUnsaved({ loaded, reviewTracking }, summaryTracking) })
}
const navidrome = []
for (const check of [null, { state: 'unset' }, { state: 'failed', problem: 'Navidrome answered 401: Wrong username or password' },
  { state: 'failed', problem: null }, { state: 'failed', problem: '' }, { state: 'failed' }, { state: 'scanning' },
  { state: 'checking' }, { state: 'checked' }, { state: 'listed' }, { state: '' }, { state: 'UNSET' }]) {
  for (const detail of flags) navidrome.push({ check, detail, note: N.navidromeNote(check, detail) })
}
const labels = []
for (const label of ['Needs a look', '']) for (const count of [null, 0, 1, 2, 3, 99, 100, 1234, -1]) {
  labels.push({ label, count, text: N.needsLookLabel(label, count) })
}

//? the editor in queue mode: where it is, and the buttons
const navs = []
for (let total = 1; total <= 4; total++) for (let position = 1; position <= total; position++) for (const applied of flags) {
  const queue = { position, total }
  navs.push({ position, total, applied, back: backOf(queue), on: onOf(queue), nextAlbum: nextShownOf(applied, queue) })
}

//? the count: deadwax's answers, the row's value and what VoiceOver hears
const counts = []
for (const answer of [
  { known: true, needs_attention: 2, new_imports: 1, total: 3, unscanned_imports: 0, tracking_enabled: true },
  { known: true, needs_attention: 0, new_imports: 0, total: 0, unscanned_imports: 0, tracking_enabled: false },
  { known: false, needs_attention: 0, new_imports: 4, total: 4, unscanned_imports: 4, tracking_enabled: true },
  { total: 1 }, { total: 2, tracking_enabled: null }, { total: 99, tracking_enabled: 'false' }, { total: 100 }, { total: 1234 },
  { total: -2 }, {}, { total: null, tracking_enabled: false },
]) {
  //? as the hook keeps it: the server's number (page ?? server - the page's own never stands in on the phone)
  const server = answer.total
  const needsLook = null ?? server
  counts.push({ answer, total: server ?? null, tracking: trackingOf(answer),
    value: valueOf(needsLook, badgeText), spoken: spokenOf(needsLook, N.needsLookLabel, words.row) })
}
//? before any answer: nothing drawn, the row's words alone
const unknown = { value: valueOf(null, badgeText), spoken: spokenOf(null, N.needsLookLabel, words.row) }

//? who the page is for, and who the count is asked for: every set of permissions
const permissions = []
for (let bits = 0; bits < 64; bits++) {
  const list = P.PERMISSIONS.filter((_, at) => bits & (1 << at))
  const perms = new Set(list)
  const page = pageOf(perms)
  permissions.push({ permissions: list, asks: P.asksQueueSummary(perms), queue: P.managing(perms).queue, allowed: page.allowed, canEdit: page.canEdit })
}

/* ===== output: plain ASCII ===== */

const BACKSLASH = String.fromCharCode(92)
function ascii(json) {
  let out = ''
  for (let i = 0; i < json.length; i++) {
    const unit = json.charCodeAt(i)
    out += unit < 0x7f ? json[i] : BACKSLASH + 'u' + unit.toString(16).padStart(4, '0')
  }
  return out
}
const flat = (value) => ascii(JSON.stringify(value))

const fixture = {
  about: "Needs a look (lib/needsLook.ts, lib/metadataQueue.ts and lib/permissions.ts run as they are; app/NeedsALook.tsx's facets held, shown and pressed, its rows, its ending, its reads and its words, components/MetadataEditor.tsx's queue buttons, app/You.tsx's Manage row, app/useQueueSummary.ts's count and app/App.tsx's who, read out of their source).",
  made_by: MADE_BY,
  made_from: Object.fromEntries(Object.keys(madeFrom).sort().map((key) => [key, madeFrom[key]])),
  words,
  issueTypes: ISSUE_TYPES,
  unknown,
  lists,
  markPairs,
  sessions,
  pages,
  reads,
  released,
  givenUp,
  again,
  states,
  statuses,
  leads,
  unsaved,
  navidrome,
  labels,
  navs,
  counts,
  permissions,
}
const listedKeys = new Set(['lists', 'markPairs', 'sessions', 'pages', 'reads', 'released', 'givenUp', 'again', 'states', 'statuses',
  'leads', 'unsaved', 'navidrome', 'labels', 'navs', 'counts', 'permissions'])
const body = [
  '{',
  Object.entries(fixture).map(([key, value]) => listedKeys.has(key)
    ? `  ${flat(key)}: [\n${value.map((row) => `    ${flat(row)}`).join(',\n')}\n  ]`
    : `  ${flat(key)}: ${flat(value)}`).join(',\n'),
  '}',
  '',
].join('\n')

const steps = sessions.reduce((sum, run) => sum + run.ops.length, 0)
const counted = `${lists.length} lists, ${sessions.length} sessions (${steps} steps), ${pages.length} pages`
if (CHECK) {
  if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== body) {
    console.log(`Needs a look's fixture differs from what the web app's TypeScript answers now: ${path.relative(REPO, FIXTURE)}.`)
    console.log(`Run node ${MADE_BY}, and see what the Swift port must follow.`)
    process.exit(1)
  }
  console.log(`Needs a look's fixture matches the web app's TypeScript (${counted}).`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, body)
  console.log(`Wrote ${path.relative(REPO, FIXTURE)}: ${counted}, ${Math.round(body.length / 1024)} KB`)
}
