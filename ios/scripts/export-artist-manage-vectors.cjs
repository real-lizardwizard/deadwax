#!/usr/bin/env node
/**
 * The iPhone app's artist tools (Phase 8, slice 5 - notes/ios-specs/phase8-managing.md 4): Artist images\u2026, Which
 * artist is this? and Move albums to {name}\u2026 - written as a fixture the Swift port
 * (ios/DeadwaxKit/Sources/DeadwaxCore/ArtistManage.swift, ArtistManageFlow.swift) replays in
 * Tests/DeadwaxCoreTests/ArtistManageVectorTests.swift.
 *
 * Compiles lib/artistManage.ts (with what it imports: lib/artistPage.ts's mbidOf and everyOwned, lib/owned.ts's
 * foldName and buildOwnedIndex) with the repo's TypeScript and runs it AS IT IS, on inputs from the plain to the
 * awkward: the library's names for an artist (libraryNames - folded names, collaborations, folders with no id, a page
 * with and without an id), namesToMove, imagesFolder (one name, several, the current one among them or not, a summary
 * unread or with no folder), toggleChoice, byKind, slotLine, imageNotes, savedLine, matchLine, refileView over several
 * names' plans (two names planning one target), canMove, moveLine, moveButton, refileAfter, refileOutcome and listed.
 * And reads out of app/ArtistPanel.tsx what the panel works out itself - the Move albums subtitle, the names Move
 * applies (its loop's skip), a slot's other pictures, "Showing \u2026" - each by a pattern, compiled and run as written;
 * and every sentence the panel and app/ArtistPage.tsx say that the phone says too. A pattern that no longer matches
 * stops this script, naming what moved.
 * Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/artists/artist-manage-vectors.json.
 *
 * The file names each source it was made from with its sha256, so ui/test/iosartistmanage.sim.cjs - which runs this
 * with --check - fails when one changes, in what it does or only in its text, until the fixture is written again and
 * the Swift port follows. The output is plain ASCII (anything else as a \u escape), so a run on any machine writes the
 * same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-artist-manage-vectors.cjs           write the fixture
 *   node ios/scripts/export-artist-manage-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'artists', 'artist-manage-vectors.json')
const CHECK = process.argv.includes('--check')
const MADE_BY = 'ios/scripts/export-artist-manage-vectors.cjs'
const SOURCES = ['lib/artistManage.ts', 'lib/artistPage.ts', 'lib/owned.ts']
const PANEL = 'app/ArtistPanel.tsx'
const PAGE = 'app/ArtistPage.tsx'

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

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-artist-manage-vectors-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES.map((file) => `src/${file}`),
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const M = require(path.join(OUT, 'lib/artistManage.js'))
const owned = require(path.join(OUT, 'lib/owned.js'))
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

let seed = 8343
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const between = (low, high) => low + Math.floor(rand() * (high - low + 1))
const chance = (p) => rand() < p

/* ===== ArtistPanel.tsx's own, read out of it ===== */

//? Move albums' subtitle: the names whose albums move and where - the page's name otherwise
const subtitleOf = compiled(['request', 'listed'], `return (${piece(PANEL, /\(request\.mode === 'refile' && (request\.currentName && request\.moveNames\.length \? `\$\{listed\(request\.moveNames\)\} \u2192 \$\{request\.currentName\}` : request\.name)\)/, 'the subtitle')[1]})`)
//? Move's loop: a name none of whose albums the preview shows moving isn't applied
const skip = piece(PANEL, /const moving = new Set\(view!\.moves\.map\(\(move\) => move\.path\)\)\n\s*for \(const \{ name, plan \} of plans\) \{\n\s*(if \(!plan\.moves\.some\(\(move\) => moving\.has\(move\.path\)\)\) continue)\n/, 'the names Move applies')[1]
const namesAppliedOf = compiled(['plans', 'view'], `const moving = new Set(view.moves.map((move) => move.path))\nconst out = []\nfor (const { name, plan } of plans) {\n${skip}\nout.push(name)\n}\nreturn out`)
//? a slot's other pictures: every picture found of another kind
const othersOf = compiled(['preview', 'kind'], `${piece(PANEL, /(const others = preview\.candidates\.filter\(\(candidate\) => candidate\.kind !== kind\))\n/, "a slot's other pictures")[1]}\nreturn others`)
says(PANEL, "Showing {who}{preview.facts?.disambiguation ? ` (${preview.facts.disambiguation})` : ''}", 'showing')
const showingOf = (who, disambiguation) => `Showing ${who}${disambiguation ? ` (${disambiguation})` : ''}`
//? Save's guard and the pictures' order, as the flow holds them
says(PANEL, "const canSave = !!preview?.mbid && !!Object.keys(chosen).length && loading === null && !problem", 'canSave')
says(PANEL, '{[...options, ...(more ? others : [])].map((candidate) => {', "a slot's pictures, its own first")
says(PANEL, '{options.length === 0 && !more && existing && preview.path && (', 'the picture on disk, when none was found')
says(PANEL, "setChosen(bestUrls(found))", 'a look chooses the best')
says(PANEL, "if (!found.mbid) {\n          setSearchOpen(true)\n          setMatches(found.matches)", 'no id opens the search')

/* ===== the words ===== */

const titles = piece(PANEL, /const TITLES: Readonly<Record<ArtistManageMode, string>> = \{\n\s*images: '([^']+)',\n\s*refile: '([^']+)',\n\s*who: '([^']+)',\n\}/, 'the titles')
const words = {
  imagesTitle: titles[1],
  refileTitle: titles[2],
  whoTitle: titles[3],
  noFolder: piece(PANEL, /setProblem\("(There's no one folder for their pictures\.)"\)/, 'no folder')[1],
  lookFailed: piece(PANEL, /setProblem\(message\(caught, "(Couldn't look for pictures just now\.)"\)\)/, 'the look failed')[1],
  searchFailed: piece(PANEL, /setSearchNote\(message\(caught, "(MusicBrainz couldn't be reached\.)"\)\)/, 'the search failed')[1],
  saveFailed: piece(PANEL, /setSaved\(message\(caught, "(That couldn't be saved\.)"\)\)/, "the save failed")[1],
  notThem: piece(PANEL, /onClick=\{\(\) => setSearchOpen\(true\)\}>\n\s*(Not them\?)\n/, 'not them')[1],
  searchLabel: piece(PANEL, /for="app-artist-images-query">(Search MusicBrainz for an artist)<\/label>/, 'the search label')[1],
  search: piece(PANEL, /disabled=\{!query\.trim\(\)\}>(Search)<\/button>/, 'search')[1],
  replace: piece(PANEL, /<span>(Replace pictures that are already there)<\/span>/, 'replace')[1],
  saving: piece(PANEL, /\{saving \? '(Saving\u2026)' : '(Save)'\}/, 'saving, save')[1],
  save: piece(PANEL, /\{saving \? '(Saving\u2026)' : '(Save)'\}/, 'saving, save')[2],
  fewer: piece(PANEL, /\{more \? '(Fewer)' : `Use another picture \(\$\{others\.length\}\)`\}/, 'use another picture')[1],
  whichArtist: piece(PANEL, /label="(Which artist the pictures are of)"/, 'which artist the pictures are of')[1],
  searching: piece(PANEL, /<span class="app-asking-text">(Searching MusicBrainz\u2026)<\/span>/, 'searching')[1],
  artistsGoingBy: piece(PANEL, /label="(Artists going by this name)"/, 'artists going by this name')[1],
  working: piece(PANEL, /<span class="app-asking-text">(Working out the moves\u2026)<\/span>/, 'working out the moves')[1],
  albumsThatMove: piece(PANEL, /aria-label="(Albums that move)"/, 'albums that move')[1],
  albumsThatStay: piece(PANEL, /aria-label="(Albums that stay)"/, 'albums that stay')[1],
  nothingCanMove: piece(PANEL, /\? '(Nothing can move - every album stays where it is, for the reason beside it\.)'/, 'nothing can move')[1],
  previewFailed: piece(PANEL, /setError\(message\(caught, "(Couldn't work out the moves\.)"\)\)/, "couldn't work out the moves")[1],
  moveFailed: piece(PANEL, /problem = message\(caught, "(The move didn't work\.)"\)/, "the move didn't work")[1],
  moving: piece(PANEL, /\{applying \? '(Moving\u2026)' : moveButton\(view\?\.moves\.length \?\? 0\)\}/, 'moving')[1],
  done: piece(PANEL, /onClick=\{onClose\}>\n\s*(Done)\n/, 'done')[1],
  cancel: piece(PANEL, /<button type="button" class="pl-pill" onClick=\{onClose\}>\n\s*(Cancel)\n/, 'cancel')[1],
  imagesItem: piece(PAGE, /\n\s*(Artist images\u2026)\n\s*<\/button>/, 'the Artist images button')[1],
  whoItem: piece(PAGE, /\n\s*(Which artist is this\?)\n\s*<\/button>/, 'the Which artist is this? button')[1],
  chosen: piece(PAGE, /\n\s*(You chose who this is, for this visit\.)\{' '\}/, 'you chose who this is')[1],
}
says(PANEL, '<span class="app-asking-text">Looking for pictures of {loading}\u2026</span>', 'looking for pictures')
says(PANEL, 'if (!found.matches.length) setSearchNote(`Nothing in MusicBrainz goes by "${wanted}".`)', 'nothing goes by')
says(PANEL, 'if (!found.matches.length) setNote(`Nothing in MusicBrainz goes by "${text}".`)', 'nothing goes by, who')
says(PANEL, 'aria-label={`${candidate.label}, from ${candidate.source}`}', "a picture's name")
says(PANEL, 'alt={`${label} on disk`}', 'the picture on disk')
says(PANEL, `MusicBrainz knows several artists by names like this, or none from your files. Choose who {request.name} is,
        and the page shows their albums and who they are - for this visit. The release editor writes who an album is
        by into its files.`, 'the who note')
says(PANEL, `Each album moves into <strong>{view.toFolder}/</strong> keeping its own folder name, and its album artist
              tag becomes {view.currentName} - where a download filed today would put it. Each track's own artist is
              what the sleeve credited, and stays.`, 'the move note')
says(PANEL, '<span class="app-artist-move-line is-warning">stays - {refused.reason}</span>', 'stays')
says(PANEL, '<span class="app-artist-move-to">\u2192 {move.target_path}</span>', 'moves to')
says(PANEL, ": `Nothing to move - every album is already filed under ${view.currentName}.`}", 'nothing to move')
says(PAGE, 'Move albums to {facts.name}', 'the Move albums button')
const sentences = {
  looking: ['Ye', 'Kanye West', 'Sigur R\u00f3s'].map((name) => ({ name, text: `Looking for pictures of ${name}\u2026` })),
  nothingGoesBy: ['Nirvana', 'kanye  west', '"Weird" Al'].map((query) => ({ query, text: `Nothing in MusicBrainz goes by "${query}".` })),
  whoNote: ['Nirvana', 'Ye'].map((name) => ({ name, text: `MusicBrainz knows several artists by names like this, or none from your files. Choose who ${name} is, and the page shows their albums and who they are - for this visit. The release editor writes who an album is by into its files.` })),
  moveNote: [['Ye', 'Ye'], ['Sigur R\u00f3s', 'Sigur R\u00f3s']].map(([toFolder, currentName]) => ({ toFolder, currentName,
    lead: 'Each album moves into ', folder: `${toFolder}/`, rest: ` keeping its own folder name, and its album artist tag becomes ${currentName} - where a download filed today would put it. Each track's own artist is what the sleeve credited, and stays.` })),
  nothingToMove: ['Ye', 'Prince'].map((name) => ({ name, text: `Nothing to move - every album is already filed under ${name}.` })),
  stays: ['already in Ye/', "another album moves to 'Ye/Graduation (2007)'"].map((reason) => ({ reason, text: `stays - ${reason}` })),
  movesTo: ['Ye/Donda (2021)'].map((target) => ({ target, text: `\u2192 ${target}` })),
  moveItem: ['Ye', 'Prince'].map((name) => ({ name, web: `Move albums to ${name}` })),
  option: [{ label: 'Square image', source: 'fanart.tv' }, { label: 'Banner', source: 'TheAudioDB' }].map((one) => ({ ...one, text: `${one.label}, from ${one.source}` })),
  onDisk: ['Banner', 'Square image'].map((label) => ({ label, text: `${label} on disk` })),
  useAnother: [0, 1, 7].map((count) => ({ count, text: `Use another picture (${count})` })),
}

/* ===== the cases ===== */

const mb = (n) => `${String(n).padStart(8, '0')}-0000-4000-8000-${String(n).padStart(12, '0')}`
const ART = { ye: mb(1), nirvana: mb(2), nirvana2: mb(3), bjork: mb(4), prince: mb(5), jay: mb(6) }
const REL = (n) => mb(100 + n)
const folder = (path, artist, extra = {}) => ({ path, artist, album: path.split('/').pop(), ...extra })

//? the library's names: one artist under two names, a collaboration, folders with no ids, folded and spaced names,
//? the same name twice, upper-case ids, nothing at all
const FOLDERS = [
  folder('Kanye West/Graduation (2007)', 'Kanye West', { albumartist_mbids: [ART.ye], release_mbid: REL(1) }),
  folder('Kanye West/808s', 'Kanye West', { release_mbid: REL(2) }),
  folder('Ye/Donda (2021)', 'Ye', { albumartist_mbids: [ART.ye.toUpperCase()], release_mbid: REL(3) }),
  folder('Ye/Bully (2025)', 'Ye', { albumartist_mbids: [` ${ART.ye} `] }),
  folder('Kanye West & Jay-Z/Watch the Throne', 'Kanye West & Jay-Z', { albumartist_mbids: [ART.ye, ART.jay], release_mbid: REL(4) }),
  folder('Kanye/Yeezus', 'Kanye', { release_mbid: REL(5) }),
  folder('kanye west/Late Registration', 'kanye west', {}),
  folder('Nirvana/Nevermind', 'Nirvana', { albumartist_mbids: [ART.nirvana], release_mbid: REL(6) }),
  folder('Nirvana (60s)/Local Anaesthetic', 'Nirvana', { albumartist_mbids: [ART.nirvana2] }),
  folder('Nirvana/Bleach', 'Nirvana', {}),
  folder('Bj\u00f6rk/Debut', 'Bj\u00f6rk', { albumartist_mbids: [ART.bjork] }),
  folder('Bjork/Post', 'Bjork', {}),
  folder('The Prince/Purple Rain', 'The Prince', { release_mbid: REL(7) }),
  folder('Prince/1999', 'Prince', { albumartist_mbids: ['not an id'] }),
  folder('  /Untitled', '  ', {}),
  folder('Various Artists/Mix', 'Various Artists', { albumartist_mbids: [] }),
]
const WHO = [
  { mbid: ART.ye, name: 'Ye', releases: [REL(1)] },
  { mbid: ART.ye, name: 'Kanye West', releases: [REL(2), REL(5)] },
  { mbid: null, name: 'Kanye West', releases: [] },
  { mbid: null, name: 'kanye west', releases: [REL(5)] },
  { mbid: ART.nirvana, name: 'Nirvana', releases: [] },
  { mbid: null, name: 'Nirvana', releases: [] },
  { mbid: ART.nirvana2, name: 'Nirvana', releases: [] },
  { mbid: ART.bjork, name: 'Bjork', releases: [] },
  { mbid: null, name: 'Bj\u00f6rk', releases: [] },
  { mbid: null, name: 'Prince', releases: [REL(7)] },
  { mbid: ` ${ART.prince.toUpperCase()} `, name: 'Prince', releases: [] },
  { mbid: 'nonsense', name: null, releases: [REL(1)] },
  { mbid: null, name: null, releases: [] },
  { mbid: null, name: '', releases: ['also nonsense'] },
]
const names = []
for (const who of WHO) {
  names.push({ who, folders: FOLDERS, names: M.libraryNames(owned.buildOwnedIndex(FOLDERS), who) })
}
names.push({ who: WHO[0], folders: null, names: M.libraryNames(null, WHO[0]) })
names.push({ who: WHO[0], folders: [], names: M.libraryNames(owned.buildOwnedIndex([]), WHO[0]) })
//? seeded: folders drawn from a pool of names, ids and releases
const POOL_NAMES = ['Ye', 'Kanye West', 'kanye west', 'KANYE WEST', 'Kanye  West', 'The Kanye', 'Kanye', 'Bj\u00f6rk', 'Bjork', 'BJ\u00d6RK', '\u00c9mile', 'Emile', 'a', 'B', '\u00df', 'ss', ' ', '']
const POOL_IDS = [ART.ye, ART.ye.toUpperCase(), ART.jay, ART.bjork, 'x']
for (let n = 0; n < 60; n++) {
  const folders = Array.from({ length: between(0, 9) }, (_, at) => {
    const ids = Array.from({ length: pick([0, 0, 1, 1, 1, 2]) }, () => pick(POOL_IDS))
    return folder(`F${n}/${at}`, pick(POOL_NAMES), {
      ...(chance(0.7) ? { albumartist_mbids: ids } : {}),
      ...(chance(0.5) ? { release_mbid: REL(between(1, 6)) } : {}),
    })
  })
  const who = {
    mbid: chance(0.5) ? pick(POOL_IDS) : null,
    name: chance(0.85) ? pick(POOL_NAMES) : null,
    releases: Array.from({ length: between(0, 3) }, () => REL(between(1, 6))),
  }
  names.push({ who, folders, names: M.libraryNames(owned.buildOwnedIndex(folders), who) })
}

const toMove = []
for (const [list, current] of [
  [['Kanye West', 'Ye'], 'Ye'], [['Kanye West', 'Ye'], ' Ye '], [['Kanye West'], 'Ye'], [['Ye'], 'Ye'], [[], 'Ye'],
  [['Kanye West', 'Ye'], null], [['Kanye West', 'Ye'], ''], [['Kanye West', 'Ye'], '   '], [['ye', 'Ye'], 'Ye'],
  [['Bj\u00f6rk', 'Bjo\u0308rk'], 'Bj\u00f6rk'], [['A', 'B', 'C'], 'B'],
]) toMove.push({ names: list, current, toMove: M.namesToMove(list, current) })

const summary = (artist, folderPath, problem = null, art = {}) => ({
  artist, path: folderPath, folder_problem: problem, album_count: 2, track_count: 20, total_size: 1234567890,
  first_year: '2007', last_year: '2021', art,
})
const folders = []
for (const [list, current, said] of [
  [[], 'Ye', []],
  [['Ye'], 'Ye', [['Ye', summary('Ye', 'Ye')]]],
  [['Ye'], 'Ye', []],
  [['Ye'], null, [['Ye', summary('Ye', 'Ye')]]],
  [['Kanye West'], 'Ye', [['Kanye West', summary('Kanye West', 'Kanye West')]]],
  [['Kanye West', 'Ye'], 'Ye', [['Kanye West', summary('Kanye West', 'Kanye West')], ['Ye', summary('Ye', 'Ye')]]],
  [['Kanye West', 'Ye'], ' Ye ', [['Ye', summary('Ye', 'Ye')]]],
  [['Kanye West', 'Kanye'], 'Ye', []],
  [['Kanye West', 'Kanye'], null, []],
  [['Kanye West', 'Kanye'], '', []],
  [['Ye'], 'Ye', [['Ye', null]]],
  [['Ye'], 'Ye', [['Ye', summary('Ye', null, 'their albums are in more than one folder: Ye, Ye 2')]]],
  [['Ye'], 'Ye', [['Ye', summary('Ye', '', null)]]],
  [['Ye'], 'Ye', [['Ye', summary('Ye', null, '')]]],
  [['Ye'], 'Ye', [['Ye', summary('Ye', null, '\u00e9tait ailleurs')]]],
  [['Ye'], 'Ye', [['Ye', summary('Ye', null, '\ud83c\udfb5 somewhere')]]],
  [['Kanye West', 'Ye'], 'Ye', [['Ye', null], ['Kanye West', summary('Kanye West', 'Kanye West')]]],
]) {
  folders.push({ names: list, current, summaries: said, folder: M.imagesFolder(list, current, new Map(said)) })
}

//? the pictures: candidates as the preview sends them
const cand = (kind, n, source = 'fanart.tv', label = null) => ({
  kind, url: `https://assets.fanart.tv/fanart/music/${kind}-${n}.jpg`, preview: `https://assets.fanart.tv/fanart/music/${kind}-${n}.jpg`,
  source, label: label ?? `${kind} ${n}`,
})
const CANDIDATES = [cand('thumb', 1), cand('thumb', 2, 'TheAudioDB'), cand('banner', 1), cand('fanart', 1, 'Wikimedia Commons'),
  cand('logo', 1), cand('thumb', 3, 'Wikimedia Commons', 'Square image'), cand('clearart', 1)]
const kinds = [
  { candidates: CANDIDATES, byKind: M.byKind(CANDIDATES) },
  { candidates: [], byKind: M.byKind([]) },
  { candidates: [cand('thumb', 1), cand('thumb', 1)], byKind: M.byKind([cand('thumb', 1), cand('thumb', 1)]) },
]
const others = []
for (const kind of ['thumb', 'banner', 'fanart', 'logo', 'landscape', 'clearart', 'nothing']) {
  others.push({ candidates: CANDIDATES, kind, others: othersOf({ candidates: CANDIDATES }, kind) })
}
const best = { thumb: cand('thumb', 1), banner: cand('banner', 1) }
const bests = [{ best, urls: M.bestUrls({ best }) }, { best: {}, urls: M.bestUrls({ best: {} }) }]
const choices = []
let chosen = M.bestUrls({ best })
for (const [kind, url] of [['thumb', cand('thumb', 2).url], ['thumb', cand('thumb', 2).url], ['banner', cand('banner', 1).url],
  ['fanart', cand('thumb', 3).url], ['logo', cand('logo', 1).url], ['logo', cand('logo', 1).url], ['thumb', cand('thumb', 1).url]]) {
  const next = M.toggleChoice(chosen, kind, url)
  choices.push({ chosen, kind, url, next })
  chosen = next
}
const slots = [[null, 0], [null, 3], ['artist.jpg', 0], ['banner.png', 2], ['', 0], ['', 1]].map(([existing, found]) => ({ existing, found, line: M.slotLine(existing, found) }))
const notes = [[false, undefined], [false, { fanarttv: true, theaudiodb: true }], [true, undefined], [true, { fanarttv: false, theaudiodb: true }],
  [true, { fanarttv: true, theaudiodb: false }], [true, { fanarttv: true, theaudiodb: true }]].map(([has_key, sources]) => ({
  has_key, sources: sources ?? null, notes: M.imageNotes(sources === undefined ? { has_key } : { has_key, sources }),
}))
const saved = [[[], []], [['artist.jpg'], []], [['artist.jpg', 'banner.jpg'], ['the logo could not be fetched']], [[], ['the logo could not be fetched', 'b']], [[], ['']]]
  .map(([written, problems]) => ({ written, problems, line: M.savedLine({ written, problems }) }))
const match = (name, extra = {}) => ({ mbid: mb(900), name, disambiguation: '', country: '', type: '', score: 100, matched_as: null, ...extra })
const matches = [match('Nirvana'), match('Nirvana', { disambiguation: '90s US grunge band', type: 'Group', country: 'US', matched_as: 'Nirvana' }),
  match('Ye', { matched_as: 'Kanye West', type: 'Person' }), match('Ye', { matched_as: 'Ye' }), match('Bj\u00f6rk', { country: 'IS' }),
  match('X', { type: 'Group' }), match('Y', { matched_as: '' }), match('Bj\u00f6rk', { matched_as: 'Bjo\u0308rk' })]
  .map((one) => ({ match: one, line: M.matchLine(one) }))
const showing = [['Nirvana', '90s US grunge band'], ['Ye', ''], ['Ye', null]].map(([who, disambiguation]) => ({ who, disambiguation, text: showingOf(who, disambiguation) }))

//? Move albums: each name's plan as the route answers it
const move = (from, to, files, retagged) => ({ album: from.split('/').pop(), path: from, target_path: to, files,
  retag: Array.from({ length: retagged }, (_, n) => ({ filename: `${n + 1}.flac`, changes: { albumartist: ['Kanye West', 'Ye'] } })) })
const plan = (current, toFolder, moves, refused = [], problems = []) => ({
  current_name: current, to_folder: toFolder, artist_mbid: ART.ye, moves, refused, problems, empty: !moves.length,
})
const PLANS = {
  plain: [{ name: 'Kanye West', plan: plan('Ye', 'Ye', [move('Kanye West/Graduation (2007)', 'Ye/Graduation (2007)', 13, 13), move('Kanye West/808s', 'Ye/808s', 12, 0)]) }],
  twoNames: [
    { name: 'Kanye', plan: plan('Ye', 'Ye', [move('Kanye/Graduation (2007)', 'Ye/Graduation (2007)', 1, 1)]) },
    { name: 'Kanye West', plan: plan('Ye', 'Ye', [move('Kanye West/Graduation (2007)', 'Ye/Graduation (2007)', 2, 2), move('Kanye West/Yeezus', 'Ye/Yeezus', 10, 10)], [{ album: 'Late Registration', path: 'Kanye West/Late Registration', reason: "'Ye/Late Registration' is there already" }]) },
  ],
  problems: [
    { name: 'Kanye', plan: plan('', '', [], [], ['MusicBrainz could not be reached just now']) },
    { name: 'Kanye West', plan: plan('', '', [], [], ['MusicBrainz could not be reached just now']) },
  ],
  allStay: [{ name: 'Kanye West', plan: plan('Ye', 'Ye', [], [{ album: 'Donda', path: 'Kanye West/Donda', reason: 'a file in it could not be read' }]) }],
  nothing: [{ name: 'Kanye West', plan: plan('Ye', 'Ye', []) }],
  moveAndProblem: [{ name: 'Kanye West', plan: plan('Ye', 'Ye', [move('Kanye West/808s', 'Ye/808s', 1, 0)], [], ['something']) }],
  none: [],
}
const ok = (moves, extra = {}) => ({ moved: moves.map((one) => ({ from: one.path, to: one.target_path })), failed: [], pictures_moved: [], removed_folders: [], ...extra })
const refile = []
function refileCase(name, plans, appliedOf) {
  const view = M.refileView(plans)
  const applied = view ? appliedOf(plans, view) : []
  refile.push({
    name, plans,
    view, canMove: M.canMove(view),
    button: M.moveButton(view?.moves.length ?? 0),
    lines: view ? view.moves.map((one) => M.moveLine(one)) : [],
    namesApplied: view ? namesAppliedOf(plans, view) : [],
    applied,
    after: view ? M.refileAfter(plans, applied, view) : null,
    outcome: view ? M.refileOutcome(applied.map((one) => one.results), view.toFolder) : null,
  })
}
refileCase('one name, everything moves', PLANS.plain, (plans) => plans.map(({ name, plan }) => ({ name, plan, results: ok(plan.moves, { pictures_moved: ['artist.jpg'], removed_folders: ['Kanye West'] }) })))
refileCase('two names planning one folder', PLANS.twoNames, (plans) => [
  { name: 'Kanye', plan: plans[0].plan, results: ok(plans[0].plan.moves) },
  { name: 'Kanye West', plan: plan('Ye', 'Ye', [move('Kanye West/Yeezus', 'Ye/Yeezus', 10, 10)], [{ album: 'Graduation (2007)', path: 'Kanye West/Graduation (2007)', reason: "'Ye/Graduation (2007)' is there already" }]), results: ok([move('Kanye West/Yeezus', 'Ye/Yeezus', 10, 10)], { removed_folders: [] }) },
])
refileCase('an album the preview moved stays at the apply', PLANS.twoNames, (plans) => [
  { name: 'Kanye', plan: plans[0].plan, results: ok(plans[0].plan.moves) },
  { name: 'Kanye West', plan: plan('Ye', 'Ye', [], [{ album: 'Yeezus', path: 'Kanye West/Yeezus', reason: "'Ye/Yeezus' came since" }, { album: 'Late Registration', path: 'Kanye West/Late Registration', reason: 'still there' }]), results: ok([]) },
])
refileCase('a failure part way', PLANS.plain, (plans) => [{ name: 'Kanye West', plan: plans[0].plan,
  results: { moved: [{ from: 'Kanye West/808s', to: 'Ye/808s' }], failed: [{ album: 'Graduation (2007)', reason: 'Permission denied' }], pictures_moved: [], removed_folders: [] } }])
refileCase('the first name refused', PLANS.twoNames, () => [])
refileCase('problems', PLANS.problems, () => [])
refileCase('every album stays', PLANS.allStay, () => [])
refileCase('nothing to move', PLANS.nothing, () => [])
refileCase('a move and a problem', PLANS.moveAndProblem, () => [])
refileCase('no plans', PLANS.none, () => [])
refileCase('three removed, pictures', PLANS.plain, (plans) => [{ name: 'Kanye West', plan: plans[0].plan,
  results: ok(plans[0].plan.moves, { pictures_moved: ['artist.jpg', 'fanart.jpg'], removed_folders: ['Kanye West', 'Kanye', 'kanye west'] }) }])
refileCase('a single album, one track', [{ name: 'Kanye', plan: plan('Ye', 'Ye', [move('Kanye/Yeezus', 'Ye/Yeezus', 1, 1)]) }],
  (plans) => [{ name: 'Kanye', plan: plans[0].plan, results: ok(plans[0].plan.moves, { removed_folders: ['Kanye'] }) }])
refileCase('the same target within one name', [{ name: 'Kanye', plan: plan('Ye', 'Ye', [move('Kanye/A', 'Ye/A', 1, 0), move('Kanye/A (2)', 'Ye/A', 2, 1)]) }],
  (plans) => [{ name: 'Kanye', plan: plans[0].plan, results: ok([plans[0].plan.moves[0]]) }])

const listed = [[], ['a'], ['a', 'b'], ['a', 'b', 'c'], ['Kanye West/', 'Kanye/', 'kanye west/', 'K/']].map((items) => ({ items, text: M.listed(items) }))
const subtitles = [
  [['Kanye West'], 'Ye', 'Ye'], [['Kanye West', 'Kanye'], 'Ye', 'Kanye West'], [[], 'Ye', 'Ye'], [['Kanye West'], null, 'Kanye West'],
  [['Kanye West'], '', 'Ye'], [['A', 'B', 'C'], 'D', 'D'],
].map(([moveNames, currentName, name]) => ({ moveNames, currentName, name,
  subtitle: subtitleOf({ mode: 'refile', moveNames, currentName, name }, M.listed) }))
fs.rmSync(OUT, { recursive: true, force: true })

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
  about: "The artist tools (lib/artistManage.ts run as it is; app/ArtistPanel.tsx's subtitle, the names Move applies, a slot's other pictures and its words, and app/ArtistPage.tsx's buttons, read out of their source).",
  made_by: MADE_BY,
  made_from: Object.fromEntries(Object.keys(madeFrom).sort().map((key) => [key, madeFrom[key]])),
  words,
  sentences,
  names,
  toMove,
  folders,
  kinds,
  others,
  bests,
  choices,
  slots,
  notes,
  saved,
  matches,
  showing,
  refile,
  listed,
  subtitles,
}
const listedKeys = new Set(['names', 'toMove', 'folders', 'kinds', 'others', 'bests', 'choices', 'slots', 'notes', 'saved', 'matches', 'showing', 'refile', 'listed', 'subtitles'])
const body = [
  '{',
  Object.entries(fixture).map(([key, value]) => listedKeys.has(key)
    ? `  ${flat(key)}: [\n${value.map((row) => `    ${flat(row)}`).join(',\n')}\n  ]`
    : `  ${flat(key)}: ${flat(value)}`).join(',\n'),
  '}',
  '',
].join('\n')

const counted = `${names.length} name cases, ${folders.length} folders, ${refile.length} moves`
if (CHECK) {
  if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== body) {
    console.log(`The artist tools' fixture differs from what the web app's TypeScript answers now: ${path.relative(REPO, FIXTURE)}.`)
    console.log(`Run node ${MADE_BY}, and see what the Swift port must follow.`)
    process.exit(1)
  }
  console.log(`The artist tools' fixture matches the web app's TypeScript (${counted}).`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, body)
  console.log(`Wrote ${path.relative(REPO, FIXTURE)}: ${counted}, ${Math.round(body.length / 1024)} KB`)
}
