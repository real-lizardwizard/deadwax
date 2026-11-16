#!/usr/bin/env node
/**
 * Library care on the iPhone app (Phase 8, slice 7 - notes/ios-specs/phase8-managing.md 6): Rescan, the bulk runs and
 * In nobody's library - written as a fixture the Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/LibraryCare.swift and
 * Managing.swift's careParts) replays in Tests/DeadwaxCoreTests/LibraryCareVectorTests.swift.
 *
 * Compiles lib/libraryCare.ts, lib/bulkTargets.ts, lib/myLibrary.ts and lib/permissions.ts with the repo's TypeScript
 * and runs them AS THEY ARE, on inputs from the plain to the awkward: albums under folded and accented names, two
 * pressings of one album (counted once by the scan's totals), folders with and without a cover, a release, deadwax's own
 * disc pictures or a download's cd.jpg, lyrics; words typed with spaces, accents and nothing at all; runs stepped album
 * by album through runBulk itself - stopped before the first album, midway, after the last, an album that threw - and
 * every summary. And reads out of app/LibraryCare.tsx, app/useLibraryCare.ts and app/HeldByNobody.tsx what the pages
 * work out themselves - a scan to trust, Rescan's busy, the facts line, the scope's note, each kind's albums, note,
 * buttons and result, the state ladder, who sees In nobody's library; each album's step (a cover's or CD art's 404 told
 * apart, lyrics in tracks); a run's guards and what it leaves behind; a flag's name, an album's row, what Add and
 * Dismiss say - each by a pattern, compiled and run as written; and every sentence those say that the phone says too. A
 * pattern that no longer matches stops this script, naming what moved.
 * Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/care/library-care-vectors.json.
 *
 * The file names each source it was made from with its sha256, so ui/test/ioscare.sim.cjs - which runs this with
 * --check - fails when one changes, in what it does or only in its text, until the fixture is written again and the
 * Swift port follows. The output is plain ASCII (anything else as a \u escape), so a run on any machine writes the same
 * bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-library-care-vectors.cjs           write the fixture
 *   node ios/scripts/export-library-care-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'care', 'library-care-vectors.json')
const CHECK = process.argv.includes('--check')
const MADE_BY = 'ios/scripts/export-library-care-vectors.cjs'
const SOURCES = ['lib/libraryCare.ts', 'lib/bulkTargets.ts', 'lib/myLibrary.ts', 'lib/permissions.ts', 'lib/format.ts',
  'lib/groupAlbums.ts', 'lib/typedMatch.ts']
const PAGE = 'app/LibraryCare.tsx'
const RUNS = 'app/useLibraryCare.ts'
const HELD = 'app/HeldByNobody.tsx'
const ROUTES = 'lib/appRoutes.ts'

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

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-library-care-vectors-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES.map((file) => `src/${file}`),
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const C = require(path.join(OUT, 'lib/libraryCare.js'))
const B = require(path.join(OUT, 'lib/bulkTargets.js'))
const M = require(path.join(OUT, 'lib/myLibrary.js'))
const P = require(path.join(OUT, 'lib/permissions.js'))
const F = require(path.join(OUT, 'lib/format.js'))
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

let seed = 3557
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const between = (low, high) => low + Math.floor(rand() * (high - low + 1))
const chance = (p) => rand() < p

/* ===== LibraryCare.tsx's own, read out of it ===== */

const adminOf = compiled(['parts'], `return ${piece(PAGE, /\n\s*const admin = (parts\.shown)\n/, 'who the page is for')[1]}`)
const realOf = compiled(['library'], `return !!(${piece(PAGE, /\n\s*const real = (library\.loaded && !library\.stale)\n/, 'a scan to trust')[1]})`)
const busyOf = compiled(['rescanning', 'library'],
  `return !!(${piece(PAGE, /\n\s*const scanBusy = (rescanning \|\| \(library\.loading && !library\.stale\))\n/, 'Rescan busy')[1]})`)
says(PAGE, 'if (scanBusy || library.problem) return', 'Rescan refused while busy')
says(PAGE, 'if (albums.length) announceAlbumsFiled()', 'a rescan tells the library')
says(PAGE, 'if (!library.loading) void library.reload(false)', 'Try again, never twice')
const factsOf = compiled(['scanTotals', 'scanAge', 'library', 'rescanning'],
  `return ${piece(PAGE, /\{(\[scanTotals\(library\.albums\), scanAge\(library, rescanning\)\]\.filter\(Boolean\)\.join\(' · '\))\}/, 'the facts')[1]}`)
const scopeNoteOf = compiled(['real', 'scopeLine', 'inScope', 'library', 'care'],
  `return ${piece(PAGE, /\{(real \? scopeLine\(inScope\.length, library\.albums\.length, care\.narrow\) : 'Checking the library…')\}/, 'the scope note')[1]}`)
const inScopeOf = compiled(['narrowAlbums', 'library', 'care'],
  `return ${piece(PAGE, /\n\s*const inScope = (narrowAlbums\(library\.albums, care\.narrow\))\n/, 'the albums in scope')[1]}`)
const targetsOf = compiled(['real', 'care', 'kind', 'bulkTargets', 'inScope'],
  `return ${piece(PAGE, /\n\s*const targets = (real && !care\.behind\[kind\] \? bulkTargets\(kind, inScope\) : null)\n/, "a kind's albums")[1]}`)
const planNoteOf = compiled(['targets', 'planWords', 'kind', 'care'],
  `return ${piece(PAGE, /\{(targets \? planWords\(kind, targets\.length, care\.narrow\) : 'Checking the library…')\}/, "a kind's note")[1]}`)
const stopLabelOf = compiled(['stopping', 'run'],
  `return ${piece(PAGE, /\{(stopping \? `Stopping after \$\{run\.done \+ 1\} of \$\{run\.total\}` : `Stop after this album · \$\{Math\.min\(run\.done \+ 1, run\.total\)\} of \$\{run\.total\}`)\}/, 'Stop, its words')[1]}`)
piece(PAGE, /\{run\?\.running \? \(\n\s*<button[\s\S]*?\) : targets && targets\.length > 0 \? \(\n\s*<button/, 'Stop, else Start with albums to take')
says(PAGE, '{BULK_LABELS[kind]} · {targets.length}', 'Start, its words')
says(PAGE, "aria-disabled={stopping ? 'true' : undefined}", 'Stop pressed once')
const resultOf = compiled(['run', 'bulkSummary', 'kind'],
  `return ${piece(PAGE, /\{(run && !run\.running \? bulkSummary\(kind, run\) : '')\}/, "a kind's result")[1]}`)
const heldShownOf = compiled(['me', 'parts'],
  `return !!(${piece(PAGE, /\{(sessionMe\(\)\?\.auth === 'on' && parts\.held) && <HeldByNobody live=\{live\} \/>\}/, 'In nobody\'s library, when')[1].replace('sessionMe()', 'me')})`)
//? the ladder before the sections: LIBRARY_PATH's problem, reading, a first read failed, else the sections
piece(PAGE, /\{library\.problem \? \(\n\s*<p class="app-care-state">\{library\.problem\}<\/p>\n\s*\) : !library\.loaded \? \(\n\s*<div class="pl-spinner" aria-label="Reading the library" \/>\n\s*\) : library\.error && !library\.albums\.length \? \(/, 'the state')
const stateOf = (library) => library.problem ? 'problem' : !library.loaded ? 'reading' : library.error && !library.albums.length ? 'failed' : 'list'
says(PAGE, '{errorNote(library.error, { failed: READ_FAILED, retry: true })}', 'a first read failed')
says(PAGE, "{sayError(library.error, '', { failed: REREAD_FAILED, retry: true })}", 'a read again failed')
says(PAGE, '{parts.rescan && <section', 'Rescan, by its part')
says(PAGE, '{parts.bulk && <section', 'the runs, by their part')
says(PAGE, '{careLine(parts)}', 'the line, by the parts')
says(PAGE, '<p class="app-placeholder-text">{MANAGING_ADMINS_ONLY}</p>', 'neither part')
says(PAGE, 'if (admin && live && !wasLive.current && library.loaded && !library.loading) void library.reload(false)', 'read again on showing')

/* ===== useLibraryCare.ts's own ===== */

class ApiError extends Error {
  constructor(status) { super(`status ${status}`); this.status = status }
}
const pictureOutcomeOf = compiled(['caught', 'ApiError'],
  `${piece(RUNS, /\n\s*(return caught instanceof ApiError && caught\.status === 404 \? \{ missing: 1 \} : \{ failed: 1 \})\n/, "a picture's step, failed")[1]}`)
says(RUNS, "await route(album.path)\n    return { written: 1 }", "a picture's step, written")
const lyricsOutcomeOf = compiled(['summary'],
  `${piece(RUNS, /\n\s*(return \{ written: summary\.written \+ summary\.replaced, missing: summary\.missing \+ summary\.instrumental, failed: summary\.failed \})\n/, "lyrics' step")[1]}`)
const failedAsOf = compiled(['kind'],
  `return ${piece(RUNS, /\n\s*(kind === 'lyrics' \? \(album\) => album\.track_count : undefined),\n/, "a step that threw, counted")[1]}`)
says(RUNS, 'if (kept.runs[kind]?.running || !targets.length) return', 'one run of a kind, never of none')
says(RUNS, 'if (kept.runs[kind]?.running && !kept.stopping[kind]) keep({ stopping: { ...kept.stopping, [kind]: true } })', 'Stop, once')
const behindOf = compiled(['now'], `return !!(${piece(RUNS, /behind: (now\.written > 0) \? \{ \.\.\.kept\.behind, \[kind\]: true \} : kept\.behind,/, 'a run that wrote, behind')[1]})`)
says(RUNS, '() => kept.stopping[kind] || !ticket.current(),', 'stopped, asked before each album')
says(RUNS, 'if (run.written > 0) announceAlbumsFiled()', 'a run that wrote tells the library')

/* ===== HeldByNobody.tsx's own ===== */

const heldShown = Number(piece(HELD, /export const HELD_SHOWN = (\d+)\n/, 'how many are listed')[1])
const flagNameOf = compiled(['flag'],
  `return ${piece(HELD, /const flagName = \(flag: HeldAnswer\['flags'\]\[number\]\): string => (\[flag\.album \|\| 'Unknown album', flag\.artist\]\.filter\(Boolean\)\.join\(' · '\))\n/, "a flag's name")[1]}`)
const albumNameOf = compiled(['album'],
  `return ${piece(HELD, /<span class="app-care-held-name" dir="auto">\{(\[album\.album \|\| 'Unknown album', album\.artist\]\.filter\(Boolean\)\.join\(' · '\))\}<\/span>/, "an album's name")[1]}`)
says(HELD, '<span class="app-care-held-path">{album.path}</span>', "an album's folder")
says(HELD, '<span class="app-care-held-path">{flagWords(flag)}</span>', "a flag's words")
const nameOf = compiled(['flag', 'flagName'], `return ${piece(HELD, /\n\s*const name = (flag \? flagName\(flag\) : 'The flag')\n/, 'the name said')[1]}`)
const saidOf = compiled(['how', 'users', 'name'],
  `return ${piece(HELD, /setSaid\((how === 'add' \? \(users\.length \? `\$\{name\}: given to \$\{users\.join\(', '\)\}` : `\$\{name\}: nobody to give it to`\) : `\$\{name\}: dismissed`)\)/, 'what a write says')[1]}`)
const showLabelOf = compiled(['all', 'albums'],
  `return ${piece(HELD, /\{(all \? 'Show fewer' : `Show all \$\{albums\.length\}`)\}/, 'Show all, Show fewer')[1]}`)
says(HELD, '{albums.length > HELD_SHOWN && (', 'Show all, when')
says(HELD, 'const shown = all ? albums : albums.slice(0, HELD_SHOWN)', 'the albums listed')
says(HELD, 'if (acting.current !== null) return', 'one write at a time')
says(HELD, 'load()\n    }\n    ;(how === \'add\' ? addFlagged(flagId) : dismissFlag(flagId)).then(', 'read again after each write')
says(HELD, '{answer.flags.length > 0 && (', 'the flags, when')
says(HELD, "{refused || problem ? <p class=\"app-care-problem\">{refused || problem}</p> : said && <p class=\"app-visually-hidden\">{said}</p>}", 'what is said, and what is shown')

const words = {
  title: piece(PAGE, /<h1 class="pl-large-title">([^<]+)<\/h1>/, 'the title')[1],
  reading: piece(PAGE, /<div class="pl-spinner" aria-label="([^"]+)" \/>/, 'reading')[1],
  tryAgain: piece(PAGE, /onClick=\{retry\}>\n\s*(Try again)\n/, 'try again')[1],
  rescanTitle: piece(PAGE, /<h2 id="app-care-rescan" class="app-care-title">([^<]+)<\/h2>/, "Rescan's heading")[1],
  rescan: piece(PAGE, /\{rescanning \? '[^']+' : '([^']+)'\}/, 'Rescan')[1],
  rescanning: piece(PAGE, /\{rescanning \? '([^']+)' : '[^']+'\}/, 'Rescanning')[1],
  runsTitle: piece(PAGE, /<h2 id="app-care-runs" class="app-care-title">([^<]+)<\/h2>/, "the runs' heading")[1],
  narrowTo: piece(PAGE, /<span class="app-care-label">([^<]+)<\/span>/, 'Narrow to')[1],
  narrowPrompt: piece(PAGE, /placeholder="([^"]+)"/, "Narrow to's prompt")[1],
  checking: piece(PAGE, /\{targets \? planWords\(kind, targets\.length, care\.narrow\) : '([^']+)'\}/, 'checking')[1],
  readFailed: C.READ_FAILED,
  checkFailed: C.CHECK_FAILED,
  rereadFailed: C.REREAD_FAILED,
  careLine: C.CARE_LINE,
  rescanWords: C.RESCAN_WORDS,
  labels: C.BULK_LABELS,
  titles: C.BULK_TITLES,
  kinds: B.BULK_KINDS,
  noPermission: piece(ROUTES, /export const MANAGING_ADMINS_ONLY = (NO_PERMISSION)\n/, 'neither part, its words')[1] === 'NO_PERMISSION' ? P.NO_PERMISSION : null,
  //? In nobody's library
  heldTitle: piece(HELD, /class="app-care-title" tabIndex=\{-1\}>([^<]+)<\/h2>/, "In nobody's library")[1],
  heldLoading: piece(HELD, /<p class="app-care-note">(Loading…)<\/p>/, 'loading')[1],
  heldFailed: piece(HELD, /\{ failed: "(Couldn't read who has which albums\.)" \}/, "the list couldn't be read")[1],
  flagged: piece(HELD, /<h3 class="app-care-heading">([^<]+)<\/h3>/, 'Flagged downloads')[1],
  addForThem: piece(HELD, /onClick=\{\(\) => act\(flag\.id, 'add'\)\}>\n\s*([^\n]+)\n/, 'Add for them')[1],
  dismiss: piece(HELD, /onClick=\{\(\) => act\(flag\.id, 'dismiss'\)\}>\n\s*([^\n]+)\n/, 'Dismiss')[1],
  addFailed: piece(HELD, /how === 'add' \? "(Couldn't add it for them\.)" : "[^"]+"/, "Add, failed")[1],
  dismissFailed: piece(HELD, /how === 'add' \? "[^"]+" : "(Couldn't dismiss it\.)"/, 'Dismiss, failed')[1],
  heldShown,
}

/* ===== the cases ===== */

const ARTISTS = ['Sigur Rós', 'sigur rós', 'Björk', 'Bjork', 'Émile', 'ABBA', 'abba', 'The Beatles', '10cc', '日本', 'Ølafur',
  '', 'a', 'Σίσυφος', 'ΣΊΣΥΦΟΣ']
const TITLES = ['( )', 'Ágætis byrjun', 'Debut', 'Post', 'Été', 'Abbey Road', '', '1999', 'Æther', 'aether', 'The Slow Rush']
const EDITIONS = ['', '', 'Standard', 'Deluxe', '2011 Remaster', 'Japan']
const DISC_NAMES = [[], [], ['disc.jpg'], ['Disc2.png'], ['cd.jpg'], ['cd.jpg', 'disc1.jpg'], ['DISC.webp'], ['discography.png'], ['cover-disc.jpg']]
const MBIDS = ['', '', 'f1c3a4b2-0000-4000-8000-000000000001', 'f1c3a4b2-0000-4000-8000-000000000002', '   ']

let pathNo = 0
function album(over = {}) {
  pathNo++
  const artist = pick(ARTISTS)
  const title = pick(TITLES)
  const edition = pick(EDITIONS)
  const tracks = pick([0, 1, 2, 9, 12, 24])
  return {
    path: `${artist || 'Unknown'}/${title || 'Untitled'}${edition ? ` [${edition}]` : ''} #${pathNo}`,
    artist,
    album: title,
    edition,
    art: pick(['', '', 'file', 'embedded']),
    release_mbid: pick(MBIDS),
    disc_art: pick(DISC_NAMES),
    lyrics_count: pick([0, 0, 1, tracks]),
    track_count: tracks,
    total_size: pick([0, 1, 1048575, 1048576, 1572864, 524288000, 1073741823, 1073741824, 1610612736, 25 * 1073741824 + 123]),
    //? the rest of a LibraryAlbum that the scan's totals (groupAlbums) read
    year: '', duration: 0, formats: [], issues: [], ignored_issues: [], severity: 0, needs_attention: false, mixed_tags: false,
    ...over,
  }
}
const asPaths = (list) => list.map((each) => each.path)

//? the scan's albums, from the plain to the awkward - two pressings of one album, case and accents apart
const LIBRARIES = []
LIBRARIES.push([])
LIBRARIES.push([album({ artist: 'Sigur Rós', album: '( )', edition: '', path: 'Sigur Rós/( ) (2002)', art: '', release_mbid: MBIDS[2], disc_art: [], lyrics_count: 0, track_count: 8, total_size: 412 * 1048576 })])
LIBRARIES.push([
  album({ artist: 'Björk', album: 'Post', edition: 'Standard', path: 'Björk/Post (1995)' }),
  album({ artist: 'björk', album: 'POST', edition: 'Deluxe', path: 'Björk/Post (1995) [Deluxe]' }),
  album({ artist: 'Bjork', album: 'Post', edition: 'Japan', path: 'Bjork/Post (1995) [Japan]' }),
  album({ artist: 'ΣΊΣΥΦΟΣ', album: 'Α', path: 'Σίσυφος/Α' }),
  album({ artist: 'σίσυφος', album: 'α', path: 'Σίσυφος/α (2)' }),
])
for (let n = 0; n < 9; n++) LIBRARIES.push(Array.from({ length: between(1, 14) }, () => album()))

const TYPED = ['', ' ', '\u00a0\t', 'sigur', 'SIGUR ROS', ' sigur  rós ', 'bjork post', 'Björk Deluxe', 'Post 1995', 'japan',
  'ﬁ', 'σίσυφος', 'ΣΙΣΥΦΟΣ', 'nothing at all', '#3', '/', 'Unknown', 'é', 'e\u0301']

//? narrowing, the scope's words and line, over every library and words typed
const narrows = []
for (const [library, albums] of LIBRARIES.entries()) {
  for (const typed of TYPED) {
    const inScope = C.narrowAlbums(albums, typed)
    narrows.push({ library, typed, inScope: asPaths(inScope), scopeWords: C.scopeWords(typed),
      scopeLine: C.scopeLine(inScope.length, albums.length, typed) })
  }
}

//? what a run will do, said before it starts
const plans = []
for (const kind of B.BULK_KINDS) {
  for (const count of [0, 1, 2, 37]) {
    for (const typed of ['', '  ', 'Björk', ' sigur  rós ']) plans.push({ kind, count, typed, words: C.planWords(kind, count, typed) })
  }
}

//? which albums each kind takes, and deadwax's own disc art
const targets = []
for (const [library, albums] of LIBRARIES.entries()) {
  targets.push({ library, covers: asPaths(B.bulkTargets('covers', albums)), disc: asPaths(B.bulkTargets('disc', albums)),
    lyrics: asPaths(B.bulkTargets('lyrics', albums)) })
}
const ownDisc = []
for (const names of [...DISC_NAMES, ['Disc'], ['DİSC.jpg'], ['ＤＩＳＣ.jpg'], ['dis'], [''], ['x.jpg', 'DiSc 2.jpg']]) {
  ownDisc.push({ names, own: B.hasOwnDiscArt({ disc_art: names }) })
}
ownDisc.push({ names: null, own: B.hasOwnDiscArt({}) })

//? the scan's totals, and how old it is
const totals = LIBRARIES.map((albums, library) => ({ library, words: C.scanTotals(albums) }))
const NOW = 1763300000000
const ages = []
for (const loaded of [false, true]) {
  for (const stale of [false, true]) {
    for (const loading of [false, true]) {
      for (const scannedAt of [null, 0, NOW / 1000, NOW / 1000 - 59.4, NOW / 1000 - 59.6, NOW / 1000 - 61, NOW / 1000 - 3599,
        NOW / 1000 - 3600, NOW / 1000 - 86399, NOW / 1000 - 86400, NOW / 1000 - 2 * 86400 - 5, NOW / 1000 + 30]) {
        for (const scanSeconds of [0, 4, 12.347]) {
          for (const rescanning of [false, true]) {
            ages.push({ scan: { loaded, stale, loading, scannedAt, scanSeconds }, rescanning, now: NOW,
              words: C.scanAge({ loaded, stale, loading, scannedAt, scanSeconds }, rescanning, NOW) })
          }
        }
      }
    }
  }
}
const formatAges = []
for (const unix of [null, 0, NOW / 1000, NOW / 1000 - 0.4, NOW / 1000 - 0.5, NOW / 1000 - 30, NOW / 1000 - 59.5, NOW / 1000 - 60,
  NOW / 1000 - 119, NOW / 1000 - 3600, NOW / 1000 - 7199.5, NOW / 1000 - 86400, NOW / 1000 - 172799, NOW / 1000 - 172800,
  NOW / 1000 - 400 * 86400, NOW / 1000 + 5000]) {
  formatAges.push({ unix, now: NOW, words: F.formatAge(unix, NOW) })
}
const sizes = []
for (const bytes of [0, 1, 524287, 524288, 1048576, 1073217535, 1073217536, 1073741824, 1127428915.2, 1181116006, 1288490188.8,
  25 * 1073741824 + 123, 1099511627776]) {
  sizes.push({ bytes, words: F.formatSize(bytes) })
}

//? what the page says it is for, by the parts drawn
const careLines = []
for (const rescan of [false, true]) for (const bulk of [false, true]) careLines.push({ rescan, bulk, words: C.careLine({ rescan, bulk }) })

//? a run's summary, over runs of every shape
const summaries = []
const shapes = [
  { total: 0, done: 0, written: 0, missing: 0, failed: 0 },
  { total: 1, done: 1, written: 1, missing: 0, failed: 0 },
  { total: 1, done: 0, written: 0, missing: 0, failed: 0 },
  { total: 2, done: 2, written: 0, missing: 1, failed: 1 },
  { total: 3, done: 3, written: 2, missing: 2, failed: 2 },
  { total: 60, done: 14, written: 13, missing: 1, failed: 0 },
  { total: 60, done: 14, written: 0, missing: 0, failed: 1 },
  { total: 5, done: 5, written: 0, missing: 0, failed: 0 },
]
for (let n = 0; n < 16; n++) {
  const total = between(1, 40)
  const done = chance(0.5) ? total : between(0, total)
  shapes.push({ total, done, written: between(0, 30), missing: pick([0, 0, 1, between(2, 12)]), failed: pick([0, 0, 1, between(2, 9)]) })
}
for (const kind of B.BULK_KINDS) {
  for (const shape of shapes) summaries.push({ kind, run: { ...shape, running: false }, words: B.bulkSummary(kind, { ...shape, running: false }) })
}

//? runs through runBulk itself: each album's outcome (or a throw), Stop asked before each album
async function runs() {
  const out = []
  const OUTCOMES = [{ written: 1 }, { missing: 1 }, { failed: 1 }, {}, { written: 3, missing: 2, failed: 1 }, 'throw']
  const cases = [
    { kind: 'covers', tracks: [12, 9, 1], outcomes: [{ written: 1 }, { missing: 1 }, { failed: 1 }], stopBefore: null },
    { kind: 'covers', tracks: [12, 9, 1], outcomes: [{ written: 1 }, 'throw', { written: 1 }], stopBefore: 0 },
    { kind: 'disc', tracks: [12, 9, 1], outcomes: [{ written: 1 }, 'throw', { written: 1 }], stopBefore: 2 },
    { kind: 'lyrics', tracks: [12, 9, 1], outcomes: [{ written: 10, missing: 2 }, 'throw', { failed: 1 }], stopBefore: null },
    { kind: 'lyrics', tracks: [0, 24], outcomes: ['throw', 'throw'], stopBefore: 1 },
    { kind: 'covers', tracks: [5], outcomes: [{ written: 1 }], stopBefore: 1 },
  ]
  for (let n = 0; n < 24; n++) {
    const length = between(1, 9)
    cases.push({ kind: pick(B.BULK_KINDS), tracks: Array.from({ length }, () => pick([0, 1, 7, 12])),
      outcomes: Array.from({ length }, () => pick(OUTCOMES)), stopBefore: chance(0.5) ? null : between(0, length) })
  }
  for (const each of cases) {
    const albums = each.tracks.map((tracks, at) => ({ path: `album ${at}`, track_count: tracks }))
    const progress = []
    let asked = 0
    const final = await B.runBulk(
      albums,
      async (album) => {
        const outcome = each.outcomes[albums.indexOf(album)]
        if (outcome === 'throw') throw new Error('no answer')
        return outcome
      },
      (run) => progress.push({ ...run }),
      () => asked++ >= (each.stopBefore ?? Infinity),
      failedAsOf(each.kind),
    )
    out.push({ ...each, progress, final, summary: B.bulkSummary(each.kind, final), behind: behindOf(final), result: resultOf(final, B.bulkSummary, each.kind) })
  }
  return out
}

//? each album's step: a picture's answer or refusal, lyrics' summary or refusal
const steps = []
for (const status of [404, 400, 403, 409, 422, 500, 502, 503, null]) {
  const caught = status === null ? new TypeError('Failed to fetch') : new ApiError(status)
  steps.push({ kind: 'picture', status, outcome: pictureOutcomeOf(caught, ApiError) })
}
for (const summary of [
  { written: 3, replaced: 1, missing: 2, instrumental: 1, failed: 0 },
  { written: 0, replaced: 0, missing: 0, instrumental: 0, failed: 0 },
  { written: 0, replaced: 0, missing: 0, instrumental: 4, failed: 2 },
]) {
  steps.push({ kind: 'lyrics', summary, outcome: lyricsOutcomeOf(summary) })
}
const failedAs = []
for (const kind of B.BULK_KINDS) {
  const as = failedAsOf(kind)
  for (const tracks of [0, 1, 12]) failedAs.push({ kind, tracks, failed: as ? as({ track_count: tracks }) : 1 })
}

//? the page as drawn: a scan to trust, Rescan's busy, the facts, the scope, each kind's albums, note, button and result
const pages = []
for (let n = 0; n < 60; n++) {
  const index = between(0, LIBRARIES.length - 1)
  const albums = LIBRARIES[index]
  const library = {
    loaded: chance(0.85), stale: chance(0.25), loading: chance(0.3), albums, problem: chance(0.08) ? 'LIBRARY_PATH is not set' : null,
    error: chance(0.15) ? 'boom' : null, scannedAt: pick([null, NOW / 1000 - 30, NOW / 1000 - 4000]), scanSeconds: pick([0, 3.2]),
  }
  const rescanning = chance(0.2)
  const care = { narrow: pick(TYPED), behind: { covers: chance(0.2), disc: chance(0.2), lyrics: chance(0.2) } }
  const real = realOf(library)
  const inScope = inScopeOf(C.narrowAlbums, library, care)
  const kinds = {}
  for (const kind of B.BULK_KINDS) {
    const found = targetsOf(real, care, kind, B.bulkTargets, inScope)
    const run = pick([null, null, { total: 7, done: 3, written: 2, missing: 1, failed: 0, running: true },
      { total: 7, done: 7, written: 5, missing: 1, failed: 1, running: false }])
    const stopping = !!(run && run.running && chance(0.5))
    kinds[kind] = {
      targets: found === null ? null : asPaths(found),
      note: planNoteOf(found, C.planWords, kind, care),
      run, stopping,
      stop: run && run.running ? stopLabelOf(stopping, run) : null,
      start: !(run && run.running) && found && found.length > 0 ? `${C.BULK_LABELS[kind]} · ${found.length}` : null,
      result: resultOf(run, B.bulkSummary, kind),
    }
  }
  pages.push({
    library: { ...library, albums: index }, rescanning, care, now: NOW,
    state: stateOf(library), real, busy: busyOf(rescanning, library),
    facts: factsOf(C.scanTotals, (scan, busy) => C.scanAge(scan, busy, NOW), library, rescanning),
    inScope: asPaths(inScope), scopeNote: scopeNoteOf(real, C.scopeLine, inScope, library, care), kinds,
  })
}

//? who sees what: every set of permissions, with logins on and off
const permissions = []
for (let bits = 0; bits < 64; bits++) {
  const list = P.PERMISSIONS.filter((_, at) => bits & (1 << at))
  const perms = new Set(list)
  const parts = P.careParts(perms)
  permissions.push({ permissions: list, parts, shown: adminOf(parts), care: P.managing(perms, true).care,
    heldOn: heldShownOf({ auth: 'on' }, parts), heldOff: heldShownOf({ auth: 'off' }, parts), heldNone: heldShownOf(undefined, parts) })
}

//? In nobody's library: its line, a flag's words and name, an album's name, what Add and Dismiss say, Show all
const held = { lines: [], flags: [], albums: [], said: [], show: [] }
for (const count of [0, 1, 2, 21, 1000]) held.lines.push({ count, words: M.heldByNobodyLine(count) })
for (const users of [[], ['ana'], ['ana', 'ben'], ['ana', 'ben', 'cy'], ['ana', 'ben', 'cy', 'dee']]) {
  for (const flagPath of [null, '', 'Björk/Post (1995)']) {
    for (const [album, artist] of [[null, null], ['', ''], ['Post', null], [null, 'Björk'], ['Post', 'Björk'], ['', 'Björk']]) {
      const flag = { id: 7, album_id: 3, artist, album, path: flagPath, release_mbid: null, users, created_at: 1763300000 }
      held.flags.push({ flag, words: M.flagWords(flag), name: flagNameOf(flag), said: nameOf(flag, flagNameOf) })
    }
  }
}
held.flags.push({ flag: null, name: null, said: nameOf(undefined, flagNameOf) })
for (const [albumTitle, artist] of [['', ''], ['Post', ''], ['', 'Björk'], ['Post', 'Björk']]) {
  held.albums.push({ album: albumTitle, artist, name: albumNameOf({ album: albumTitle, artist }) })
}
for (const how of ['add', 'dismiss']) {
  for (const users of [[], ['ana'], ['ana', 'ben', 'cy']]) {
    for (const name of ['Post · Björk', 'The flag']) held.said.push({ how, users, name, words: saidOf(how, users, name) })
  }
}
for (const all of [false, true]) for (const count of [21, 300]) held.show.push({ all, count, words: showLabelOf(all, { length: count }) })

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

async function main() {
  const ran = await runs()
  const fixture = {
    about: "Library care (lib/libraryCare.ts, lib/bulkTargets.ts, lib/myLibrary.ts, lib/permissions.ts and lib/format.ts run as they are; app/LibraryCare.tsx's page, app/useLibraryCare.ts's steps and runs and app/HeldByNobody.tsx's words, read out of their source).",
    made_by: MADE_BY,
    made_from: Object.fromEntries(Object.keys(madeFrom).sort().map((key) => [key, madeFrom[key]])),
    words,
    libraries: LIBRARIES,
    narrows,
    plans,
    targets,
    ownDisc,
    totals,
    ages,
    formatAges,
    sizes,
    careLines,
    summaries,
    runs: ran,
    steps,
    failedAs,
    pages,
    permissions,
    held: [held],
  }
  const listedKeys = new Set(['libraries', 'narrows', 'plans', 'targets', 'ownDisc', 'totals', 'ages', 'formatAges', 'sizes', 'careLines', 'summaries',
    'runs', 'steps', 'failedAs', 'pages', 'permissions', 'held'])
  const body = [
    '{',
    Object.entries(fixture).map(([key, value]) => listedKeys.has(key)
      ? `  ${flat(key)}: [\n${value.map((row) => `    ${flat(row)}`).join(',\n')}\n  ]`
      : `  ${flat(key)}: ${flat(value)}`).join(',\n'),
    '}',
    '',
  ].join('\n')

  const counted = `${narrows.length} narrowings, ${ran.length} runs, ${summaries.length} summaries, ${pages.length} pages`
  if (CHECK) {
    if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== body) {
      console.log(`Library care's fixture differs from what the web app's TypeScript answers now: ${path.relative(REPO, FIXTURE)}.`)
      console.log(`Run node ${MADE_BY}, and see what the Swift port must follow.`)
      process.exit(1)
    }
    console.log(`Library care's fixture matches the web app's TypeScript (${counted}).`)
  } else {
    fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
    fs.writeFileSync(FIXTURE, body)
    console.log(`Wrote ${path.relative(REPO, FIXTURE)}: ${counted}, ${Math.round(body.length / 1024)} KB`)
  }
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
