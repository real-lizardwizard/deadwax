/**
 * Looking after the library in the app (2.0.0-player.42): the pure rules - lib/bulkTargets.ts (which
 * albums each bulk run takes, how a run goes, what a finished one says - shared with the main page's
 * Library tab), lib/libraryCare.ts (the Library care page's words and its narrowing) and
 * lib/typedMatch.ts (typing to narrow a list of folders) - and the parts themselves, compiled with the
 * repo's TypeScript and rendered by the small stand-in for Preact the other page sims use: the runs'
 * store (app/useLibraryCare.ts, the REAL module against a faked deadwax), the page
 * (app/LibraryCare.tsx), Re-time saved lyrics (components/RetimeLyrics.tsx) and the Edit panel's
 * "Choose the folder" list (app/FolderPicker.tsx).
 *
 * What it pins:
 *
 *  - THE TARGETS: covers - a release and no cover; CD art - a release and none of deadwax's own disc*
 *    images (a download's cd.jpg doesn't count); lyrics - no lyrics at all. Held to the main page's own
 *    inline rules as they were before the move, over a library of every combination: the same albums,
 *    in the same order - the main page's Library tab is unchanged by taking them from here.
 *  - A RUN: one album at a time - the next asked only once the last has answered; Stop asked before
 *    each, landing after the album being fetched; what each came to counted apart (a 404 none to find,
 *    anything else failed; lyrics in tracks, a lookup that failed outright its album's tracks); and the
 *    main page's words for it, held to its status bar's template.
 *  - THE PAGE'S WORDS: the scan as the main page's status bar says it (albums grouped, tracks, size;
 *    "Saved scan from…", "Scanned … in …s", rescanning), the narrowing (every word, accents and case
 *    aside, in the artist, album, edition or folder), what each run will act on before it starts.
 *  - THE STORE: a run kept in the module (it outlives the page), one of a kind at a time, the library
 *    told once at its end and only when something was written - its kind then `behind` the disk -
 *    Stop's state, the narrowing kept.
 *  - THE PAGE: for anyone deadwax says isn't its admin a note, nothing asked (2.0.0-player.47: told
 *    `admin`, never the frame - a phone draws the page as a desktop does, where it drew a note pointing at
 *    the main page until then); the library read only once it shows and read again as it shows again; its states; Rescan the scan that ignores the cache, refused while one
 *    is out, the library told once it has answered; the runs offered only from a REAL scan, each saying
 *    what it acts on (in album folders), started over the targets in view, its Stop and its result kept
 *    until the next; a run that wrote holding its button back until a read of the library begun after
 *    it ended has landed (never drawn again over the albums it just did), a page drawn fresh holding
 *    nothing; told to draw again as a run moves and the narrowing changes (the store's listeners - the
 *    stand-in's draws are by hand, so the page's redraw counter is what says it), a page gone told
 *    nothing more; focus handed to a run's words when its button goes - also when the button is blurred
 *    AS it is removed, as Chromium does.
 *  - RE-TIME: refused while the lead is a draft; reading a REAL scan (never the saved one) of the albums
 *    with lyrics, one at a time through the re-time route; Stop; its words; a read that failed said;
 *    its run kept in its module, so a page gone and drawn again still shows it, Stop and all - and told
 *    to draw again as it moves; how a run ended said once (where it ended, or on coming back to it) and
 *    let go as the last thing drawing it goes, and as a new lead is typed - the prompt again after.
 *  - CHOOSE THE FOLDER: the scan's folders, narrowed by typing, what it says over them, each folder's
 *    path and tags, a click handing the folder on.
 *
 * Run it with:  node ui/test/care.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-care-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/bulkTargets.ts', 'src/lib/libraryCare.ts', 'src/lib/typedMatch.ts', 'src/app/useLibraryCare.ts', 'src/app/LibraryCare.tsx',
  'src/components/RetimeLyrics.tsx', 'src/app/FolderPicker.tsx',
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor whose effects run on commit - needslook.sim's stand-in
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/jsx-runtime.js'), `
exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })
exports.Fragment = 'fragment'
`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `
let current = null
function slot(init) { const i = current.cursor++; if (!(i in current.slots)) current.slots[i] = init(); return current.slots[i] }
const changed = (a, b) => !a || !b || a.length !== b.length || a.some((v, i) => !Object.is(v, b[i]))
exports.useState = (v) => { const s = slot(() => ({ v: typeof v === 'function' ? v() : v })); return [s.v, (x) => { s.v = typeof x === 'function' ? x(s.v) : x }] }
exports.useMemo = (f, deps) => { const s = slot(() => ({})); if (changed(s.deps, deps)) { s.v = f(); s.deps = deps } return s.v }
exports.useRef = (v) => slot(() => ({ current: v }))
exports.useEffect = exports.useLayoutEffect = (f, deps) => {
  const s = slot(() => ({}))
  if (changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f }
}
exports.root = (component) => {
  const root = { slots: [], cursor: 0, effects: [] }
  const render = (props) => {
    const outer = current; current = root; root.cursor = 0
    try { return component(props) } finally { current = outer }
  }
  render.commit = () => { for (const s of root.effects.splice(0)) { if (typeof s.cleanup === 'function') s.cleanup(); s.cleanup = s.f() } }
  render.unmount = () => { for (const s of root.slots) if (s && typeof s.cleanup === 'function') s.cleanup() }
  render.slots = root.slots
  return render
}
`)

const write = (file, body) => fs.writeFileSync(path.join(OUT, file), body)
//? deadwax, as the test says it answers: each call kept with its route and album, answered by hand
write('api/library.js', `
const C = () => globalThis.__care
const ask = (route, path, more) => new Promise((resolve, reject) => C().calls.push({ route, path, resolve, reject, ...more }))
exports.fetchCoverArt = (path, options) => ask('art', path, { options })
exports.fetchDiscArt = (path) => ask('disc', path)
exports.fetchLyrics = (path, options) => ask(options && options.retime ? 'retime' : 'lyrics', path, { options })
exports.listAlbums = () => new Promise((resolve, reject) => C().lists.push({ resolve, reject }))
exports.loadScan = (mode) => { C().snapshots.push(mode); return Promise.reject(new Error('not this way')) }
`)
write('hooks/useLibrary.js', `exports.useLibrary = (enabled) => { globalThis.__care.enabled.push(enabled); return globalThis.__care.library }\n`)
write('lib/libraryEvents.js', `exports.announceAlbumsFiled = () => { globalThis.__care.announced++ }\n`)
write('player/icons.js', `exports.ChevronLeftIcon = function Icon() { return null }\n`)
write('components/Loading.js', `exports.Loading = ({ label }) => ({ type: 'span', props: { class: 'loading-blocks', role: 'status', children: label } })\n`)

const C = globalThis.__care = { calls: [], lists: [], snapshots: [], enabled: [], announced: 0, library: null, reloads: [] }
function reset() {
  C.calls.length = 0; C.lists.length = 0; C.snapshots.length = 0; C.enabled.length = 0; C.announced = 0; C.reloads.length = 0
}

const B = require(path.join(OUT, 'lib/bulkTargets.js'))
const L = require(path.join(OUT, 'lib/libraryCare.js'))
const T = require(path.join(OUT, 'lib/typedMatch.js'))
const { ApiError } = require(path.join(OUT, 'api/http.js'))
const S = require(path.join(OUT, 'app/useLibraryCare.js'))
const { LibraryCare } = require(path.join(OUT, 'app/LibraryCare.js'))
const R = require(path.join(OUT, 'lib/appRoutes.js'))
const RT = require(path.join(OUT, 'components/RetimeLyrics.js'))
const { FolderPicker } = require(path.join(OUT, 'app/FolderPicker.js'))
const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))

/* ===== the tree ===== */

let tree = null
//? function components drawn through (Loading, the icon) - none of them holds state of its own
function expand(node) {
  if (node === null || node === undefined || typeof node !== 'object') return node
  if (Array.isArray(node)) return node.map(expand)
  if (typeof node.type === 'function') return expand(node.type(node.props))
  return { ...node, props: { ...node.props, children: expand(node.props?.children) } }
}
function find(test, within = tree) {
  const hits = []
  const visit = (node) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach(visit); return }
    if (test(node)) hits.push(node)
    visit(node.props?.children)
  }
  visit(within)
  return hits
}
function words(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(words).join('')
  if (typeof node.type !== 'string' && node.type !== 'fragment') return ''
  return words(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const classed = (name, within) => find(byClass(name), within)
const buttons = (within) => find((node) => node.type === 'button', within)
const button = (label, within) => buttons(within).find((node) => words(node).trim() === label)

function mount(component, props) {
  const render = hooks.root(component)
  const all = { ...props }
  const draw = (more = {}) => {
    Object.assign(all, more)
    tree = expand(render(all))
    render.commit()
    tree = expand(render(all))
    render.commit()
    return tree
  }
  //? how many times the page has been told to draw again - its first hook, the `redraw` counter the
  //? store's listener moves (the page's state is its module's: nothing else would draw it again)
  const redraws = () => render.slots[0]?.v ?? 0
  return { draw, all, redraws, unmount: () => render.unmount() }
}

/* ===== the albums ===== */

const album = (folder, more = {}) => ({
  path: folder, artist: folder.split('/')[0], album: folder.split('/')[1].replace(/ \(\d{4}\)$/, ''), edition: '', year: '2000',
  art: 'file', art_mtime: 1, release_mbid: 'mb', disc_art: [], lyrics_count: 1, track_count: 10, total_size: 100 * 1024 * 1024,
  duration: 2400, mixed_tags: false, needs_attention: false, severity: 0, formats: ['FLAC'], issues: [], ignored_issues: [], ...more,
})
const paths = (albums) => albums.map((one) => one.path)

console.log('\nwhich albums each run takes')
{
  const NOTHING = album('Bare/Rip (2001)', { art: '', release_mbid: '', disc_art: [], lyrics_count: 0 })
  const COVERLESS = album('Portishead/Dummy (1994)', { art: '', release_mbid: 'r-dummy' })
  const SCAN_ONLY = album('Portishead/Third (2008)', { disc_art: ['cd.jpg'] })
  const OWN_DISC = album('Radiohead/In Rainbows (2007)', { disc_art: ['Disc1.JPG', 'disc2.jpg'] })
  const EMBEDDED = album('Air/Moon Safari (1998)', { art: 'embedded', disc_art: ['disc.png'] })
  const LIBRARY = [NOTHING, COVERLESS, SCAN_ONLY, OWN_DISC, EMBEDDED]
  check('covers: a release and no cover (an embedded one is a cover; no release, nothing to ask)', paths(B.coverTargets(LIBRARY)), ['Portishead/Dummy (1994)'])
  check('CD art: a release and none of deadwax\'s own disc* images - a download\'s cd.jpg doesn\'t count, case aside',
    paths(B.discTargets(LIBRARY)), ['Portishead/Dummy (1994)', 'Portishead/Third (2008)'])
  check('lyrics: no lyrics at all - one track with some keeps it out', paths(B.lyricsTargets(LIBRARY)), ['Bare/Rip (2001)'])
  check('bulkTargets by kind, in the order both pages draw them', [B.BULK_KINDS, ...B.BULK_KINDS.map((kind) => paths(B.bulkTargets(kind, LIBRARY)))],
    [['covers', 'disc', 'lyrics'], ['Portishead/Dummy (1994)'], ['Portishead/Dummy (1994)', 'Portishead/Third (2008)'], ['Bare/Rip (2001)']])
  check('hasOwnDiscArt: disc*, any case - never cd*', [B.hasOwnDiscArt({ disc_art: ['DISC.jpg'] }), B.hasOwnDiscArt({ disc_art: ['cd1.jpg'] }), B.hasOwnDiscArt({}), B.hasOwnDiscArt({ disc_art: [] })],
    [true, false, false, false])

  //? the main page's own rules as they stood in LibraryView.tsx before the move, word for word: the
  //? lib's targets are those, in the same order, over every combination - the main page is unchanged
  const BEFORE = {
    covers: (albums) => albums.filter((one) => !one.art && one.release_mbid),
    lyrics: (albums) => albums.filter((one) => !one.lyrics_count),
    disc: (albums) => albums.filter((one) => one.release_mbid
      && !(one.disc_art ?? []).some((name) => name.toLowerCase().startsWith('disc'))),
  }
  const every = []
  for (const art of ['', 'file', 'embedded']) {
    for (const release of ['', 'r1']) {
      for (const disc of [undefined, [], ['cd.jpg'], ['disc.jpg'], ['Disc2.PNG', 'cd.jpg'], ['discography.txt']]) {
        for (const lyrics of [0, 1, 12]) every.push(album(`A/${every.length}`, { art, release_mbid: release, disc_art: disc, lyrics_count: lyrics }))
      }
    }
  }
  check(`the main page's targets as they were, over all ${every.length} combinations: the same albums, in the same order`,
    B.BULK_KINDS.map((kind) => JSON.stringify(paths(B.bulkTargets(kind, every))) === JSON.stringify(paths(BEFORE[kind](every)))), [true, true, true])
  check('...and each takes some and leaves some (the comparison means something)', B.BULK_KINDS.map((kind) => [B.bulkTargets(kind, every).length > 0, B.bulkTargets(kind, every).length < every.length]),
    [[true, true], [true, true], [true, true]])
}

console.log('\na run: one album at a time, Stop, what each came to')
async function runs() {
  const answers = []
  let inFlight = 0, most = 0
  const step = (album) => new Promise((resolve, reject) => {
    inFlight++; most = Math.max(most, inFlight)
    answers.push({ album, resolve: (value) => { inFlight--; resolve(value) }, reject: (error) => { inFlight--; reject(error) } })
  })
  const seen = []
  let stop = false
  const done = B.runBulk(['a', 'b', 'c', 'd'], step, (run) => seen.push({ ...run }), () => stop, (album) => (album === 'c' ? 7 : 1))
  await settle()
  check('it starts: the run said, the first album asked - and only the first', [seen[0], answers.map((one) => one.album)], [{ total: 4, done: 0, written: 0, missing: 0, failed: 0, running: true }, ['a']])
  answers[0].resolve({ written: 1 })
  await settle()
  check('...the next asked only once the last has answered', [answers.map((one) => one.album), seen.at(-1).done, seen.at(-1).written], [['a', 'b'], 1, 1])
  answers[1].resolve({ missing: 1 })
  await settle()
  answers[2].reject(new Error('the step threw anyway'))
  await settle()
  check('a step that throws counts its album failed - as many as failedAs says (a lyrics album\'s tracks)', seen.at(-1), { total: 4, done: 3, written: 1, missing: 1, failed: 7, running: true })
  stop = true
  answers[3].resolve({ written: 2, failed: 1 })
  const run = await done
  check('Stop pressed during the last album: it lands after that album, the run ended and said', [run, seen.at(-1)], [{ total: 4, done: 4, written: 3, missing: 1, failed: 8, running: false }, run])
  check('...never two albums at once', most, 1)

  const asked = []
  const stopped = await B.runBulk(['a', 'b', 'c'], async (album) => { asked.push(album); return { written: 1 } }, () => {}, () => asked.length >= 1)
  check('Stop asked before each album: pressed during the first, nothing more asked', [asked, stopped.done, stopped.total, stopped.running], [['a'], 1, 3, false])
  const empty = await B.runBulk([], async () => ({ written: 1 }), () => {}, () => false)
  check('nothing to do: a run of none, ended at once', empty, { total: 0, done: 0, written: 0, missing: 0, failed: 0, running: false })
  check('addOutcome: one more done, each count added, a count left out none', B.addOutcome(B.startRun(2), { missing: 3 }), { total: 2, done: 1, written: 0, missing: 3, failed: 0, running: true })

  //? the main page's status bar's template for each run, as it is in LibraryView.tsx
  const mainPage = {
    covers: (r) => `fetched ${r.written} cover${r.written === 1 ? '' : 's'}${r.missing ? `, ${r.missing} had none on the Archive` : ''}${r.failed ? `, ${r.failed} failed - try those again` : ''}${r.done < r.total ? ` (stopped at ${r.done} of ${r.total})` : ''}`,
    disc: (r) => `fetched CD art for ${r.written} album${r.written === 1 ? '' : 's'}${r.missing ? `, ${r.missing} had none to find` : ''}${r.failed ? `, ${r.failed} failed - try those again` : ''}${r.done < r.total ? ` (stopped at ${r.done} of ${r.total})` : ''}`,
    lyrics: (r) => `saved lyrics for ${r.written} track${r.written === 1 ? '' : 's'}${r.missing ? `, ${r.missing} not on LRCLIB or instrumental` : ''}${r.failed ? `, ${r.failed} failed - try those again` : ''}${r.done < r.total ? ` (stopped at ${r.done} of ${r.total} albums)` : ''}`,
  }
  const cases = [
    { total: 10, done: 10, written: 1, missing: 0, failed: 0, running: false },
    { total: 10, done: 10, written: 7, missing: 2, failed: 1, running: false },
    { total: 12, done: 4, written: 0, missing: 1, failed: 3, running: false },
    { total: 3, done: 3, written: 0, missing: 0, failed: 0, running: false },
  ]
  check('the words for a finished run are the main page\'s, for every run and outcome',
    B.BULK_KINDS.flatMap((kind) => cases.map((one) => B.bulkSummary(kind, one) === mainPage[kind](one))), Array(12).fill(true))
  check('...for instance', [B.bulkSummary('covers', cases[1]), B.bulkSummary('disc', cases[2]), B.bulkSummary('lyrics', cases[2])],
    ['fetched 7 covers, 2 had none on the Archive, 1 failed - try those again', 'fetched CD art for 0 albums, 1 had none to find, 3 failed - try those again (stopped at 4 of 12)',
      'saved lyrics for 0 tracks, 1 not on LRCLIB or instrumental, 3 failed - try those again (stopped at 4 of 12 albums)'])
}

function pageWords() {
  console.log('\nthe page\'s words, and typing to narrow')
  check('typing: every word somewhere, accents and case aside; nothing typed matches everything',
    [T.matchesTyped('Sigur Rós/( ) (2002)', 'sigur ros 2002'), T.matchesTyped('Björk/Homogenic', 'BJORK homo'), T.matchesTyped('Portishead/Dummy', 'portishead third'), T.matchesTyped('x', '   '), T.searchFold('Ÿ É ñ')],
    [true, true, false, true, 'y e n'])
  const LIB = [
    album('Portishead/Dummy (1994)'), album('Portishead/Third (2008)', { edition: 'Made in Germany' }),
    album('Sigur Rós/Takk (2005)'), album('Old Rips/Third rip', { artist: 'Portishead', album: 'Third' }),
  ]
  check('narrowAlbums: the artist, album, edition or folder holding every word',
    [paths(L.narrowAlbums(LIB, 'portishead third')), paths(L.narrowAlbums(LIB, 'germany')), paths(L.narrowAlbums(LIB, 'sigur ros')), paths(L.narrowAlbums(LIB, 'rips')), L.narrowAlbums(LIB, '').length, L.narrowAlbums(LIB, 'nothing like it').length],
    [['Portishead/Third (2008)', 'Old Rips/Third rip'], ['Portishead/Third (2008)'], ['Sigur Rós/Takk (2005)'], ['Old Rips/Third rip'], 4, 0])
  check('what the runs act on, said under the field',
    [L.scopeLine(4, 4, ''), L.scopeLine(2, 4, ' third '), L.scopeLine(0, 4, 'zz'), L.scopeLine(1, 1, '')],
    ['The runs act on the whole library: 4 album folders.', 'The runs act on 2 of 4 album folders: those matching “third”.', 'No album folder matches “zz”.', 'The runs act on the whole library: 1 album folder.'])
  check('what a run will do, said before it starts: how many, which, where, and what it writes',
    [L.planWords('covers', 12, ''), L.planWords('disc', 1, 'portishead'), L.planWords('lyrics', 3, '')],
    ["12 album folders with a release and no cover in the whole library. Each cover comes from the Cover Art Archive, by the release the album's tags name, and is saved beside its tracks - nothing else about the album changes.",
      "1 album folder with a release and no CD art of deadwax's own among the folders matching “portishead”. A picture of each disc, from the Cover Art Archive (or fanart.tv, with a key), is saved beside the tracks as disc.jpg (disc1.jpg, disc2.jpg… for a set with a picture per disc; .png when that's what the source has) - nothing else changes.",
      '3 album folders with no lyrics at all in the whole library. Each track is looked up on LRCLIB and saved as a .lrc beside it - nothing else changes. An album with some lyrics is finished from its own Get lyrics, in its Edit panel.'])
  check('...and with nothing to do, that', [L.planWords('covers', 0, ''), L.planWords('disc', 0, 'x'), L.planWords('lyrics', 0, '')],
    ['No album with a release is missing its cover in the whole library.', "Every album with a release has CD art of deadwax's own among the folders matching “x”.", 'Every album has some lyrics in the whole library.'])
  check('the buttons are the main page\'s words', B.BULK_KINDS.map((kind) => L.BULK_LABELS[kind]), ['Get covers', 'Get CD art', 'Get lyrics'])
  const editions = [album('Portishead/Third (2008)'), album('Portishead/Third (2008) [Deluxe]', { album: 'Third' }), album('Air/Moon Safari (1998)', { total_size: 0, track_count: 1 })]
  check('the scan as the main page\'s status bar counts it: an album held in two pressings once, tracks, size',
    [L.scanTotals(editions), L.scanTotals([album('A/B (2000)', { total_size: 0, track_count: 1 })]), L.scanTotals([])], ['2 albums · 21 tracks · 200 MB', '1 album · 1 track', '0 albums · 0 tracks'])
  //? (review: "7 albums" in the scan line, then "8 albums with no lyrics" - a run takes FOLDERS, and the
  //? two pressings are two of them)
  const bare = editions.map((one) => ({ ...one, lyrics_count: 0 }))
  check('...while a run counts what it takes - album folders - so the two never read as two counts of albums',
    [L.scanTotals(bare).split(' · ')[0], L.planWords('lyrics', B.lyricsTargets(bare).length, '').split(' with ')[0], L.scopeLine(3, 3, '')],
    ['2 albums', '3 album folders', 'The runs act on the whole library: 3 album folders.'])
  const now = 1_700_000_000_000
  const scan = (more) => ({ loaded: true, stale: false, loading: false, scannedAt: now / 1000 - 180, scanSeconds: 4, ...more })
  check('how old it is, as the main page\'s status bar says it - or what is under way',
    [L.scanAge(scan({}), false, now), L.scanAge(scan({ scanSeconds: 0 }), false, now), L.scanAge(scan({ stale: true }), false, now), L.scanAge(scan({ stale: true, loading: true, scannedAt: now / 1000 - 7200 }), false, now),
      L.scanAge(scan({ stale: true, scannedAt: null }), false, now), L.scanAge(scan({ loaded: false }), false, now), L.scanAge(scan({ loading: true }), true, now), L.scanAge(scan({ scannedAt: null }), false, now)],
    ['Scanned 3 min ago in 4s', 'Scanned 3 min ago', 'Saved scan from 3 min ago', 'Saved scan from 2 h ago · checking for changes', 'Saved scan from an earlier visit', 'Reading the library…', 'Rescanning - reading every file again…', ''])
}

/* ===== the store: app/useLibraryCare.ts, the real module ===== */

const call = (route) => C.calls.find((one) => one.route === route && !one.answered)
const answer = async (route, reply) => {
  const one = call(route)
  one.answered = true
  if (reply instanceof Error) one.reject(reply)
  else one.resolve(reply)
  await settle()
}
const lyricsSummary = (more) => ({ written: 0, replaced: 0, kept: 0, missing: 0, instrumental: 0, untagged: 0, failed: 0, synced: 0, retimed: 0, unchanged: 0, custom: 0, problem: null, ...more })

async function store() {
  console.log('\nthe runs\' store (the real useLibraryCare.ts, against a faked deadwax)')
  reset()
  S.forgetLibraryCare()
  const one = album('A/One (2000)', { art: '' }), two = album('A/Two (2000)', { art: '' }), three = album('A/Three (2000)', { art: '' })
  check('nothing yet: no run of any kind, nothing typed', [S.libraryCareNow().runs, S.libraryCareNow().narrow], [{ covers: null, disc: null, lyrics: null }, ''])
  const started = S.startBulk('covers', [one, two, three])
  await settle()
  check('a cover run started: the first album asked through Get cover\'s own call, nothing else', C.calls.map((c) => [c.route, c.path]), [['art', 'A/One (2000)']])
  check('...the run kept in the module, running', S.libraryCareNow().runs.covers, { total: 3, done: 0, written: 0, missing: 0, failed: 0, running: true })
  void S.startBulk('covers', [three])
  await settle()
  check('...a second of the same kind while it runs: nothing', C.calls.length, 1)
  await answer('art', { written: 'cover.jpg', replaced: null })
  check('one answered: counted written, the next asked', [S.libraryCareNow().runs.covers.written, C.calls.map((c) => c.path)], [1, ['A/One (2000)', 'A/Two (2000)']])
  await answer('art', new ApiError(404, 'the Cover Art Archive has no front cover for that release', 'x'))
  check('a 404: none on the Archive, apart from a failure', [S.libraryCareNow().runs.covers.missing, S.libraryCareNow().runs.covers.failed], [1, 0])
  S.stopBulk('covers')
  check('Stop: said at once, the album being fetched still fetched', [S.libraryCareNow().stopping.covers, C.calls.length], [true, 3])
  await answer('art', new ApiError(502, 'the Archive could not be reached', 'x'))
  await started
  check('...anything else failed; the run ended there - nothing more asked', [S.libraryCareNow().runs.covers, S.libraryCareNow().stopping.covers, C.calls.length],
    [{ total: 3, done: 3, written: 1, missing: 1, failed: 1, running: false }, false, 3])
  check('...and the library told once, at its end, since a cover was written', C.announced, 1)
  check('...its kind behind the disk as it ended (the page holds its button back until the library is read again) - only its kind',
    S.libraryCareNow().behind, { covers: true, disc: false, lyrics: false })
  const before = S.libraryCareNow()
  S.caughtUp(['disc', 'lyrics'])
  check('caughtUp of kinds not behind: nothing moves, nobody told', S.libraryCareNow() === before, true)
  S.caughtUp(['covers'])
  check('caughtUp once the library has been read again: behind no more', S.libraryCareNow().behind.covers, false)

  reset()
  const stopped = S.startBulk('disc', [one, two, three])
  await settle()
  S.stopBulk('disc')
  await answer('disc', { written: ['disc.jpg'], source: 'caa' })
  const asked = C.calls.map((c) => c.path)
  //? (were Stop ignored, the next album would be out: answered here so the sim goes on to say so)
  while (call('disc')) await answer('disc', new ApiError(404, 'no CD art', 'x'))
  await stopped
  check('Stop during the first of three: that album finished, nothing more asked, "stopped at 1 of 3"',
    [asked, S.libraryCareNow().runs.disc, B.bulkSummary('disc', S.libraryCareNow().runs.disc)],
    [['A/One (2000)'], { total: 3, done: 1, written: 1, missing: 0, failed: 0, running: false }, 'fetched CD art for 1 album (stopped at 1 of 3)'])
  check('...a stopped run that wrote is behind the disk too', S.libraryCareNow().behind.disc, true)
  S.caughtUp(['disc'])

  reset()
  const lyricsRun = S.startBulk('lyrics', [one, two])
  await settle()
  check('a lyrics run: the album asked through Get lyrics\' own call, not re-timing', [call('lyrics')?.path, call('lyrics')?.options], ['A/One (2000)', undefined])
  await answer('lyrics', lyricsSummary({ written: 6, replaced: 1, missing: 2, instrumental: 1, failed: 0 }))
  await answer('lyrics', new Error('LRCLIB went away'))
  await lyricsRun
  check('...counted in TRACKS: saved, not on LRCLIB or instrumental, failed - a lookup that failed outright, every track of its album',
    S.libraryCareNow().runs.lyrics, { total: 2, done: 2, written: 7, missing: 3, failed: 10, running: false })
  check('...the cover run\'s result kept beside it, untouched', S.libraryCareNow().runs.covers.done, 3)

  reset()
  const nothing = S.startBulk('disc', [one])
  await settle()
  await answer('disc', new ApiError(404, 'no CD art', 'x'))
  await nothing
  check('a run that wrote nothing: the library not told, its kind not behind', [S.libraryCareNow().runs.disc.missing, C.announced, S.libraryCareNow().behind.disc], [1, 0, false])
  check('a run of nothing is no run', [await S.startBulk('disc', []), C.calls.length, S.libraryCareNow().runs.disc.missing], [undefined, 1, 1])
  S.stopBulk('disc')
  check('Stop with nothing running: nothing', S.libraryCareNow().stopping.disc, false)

  S.setCareNarrow('portishead')
  check('the narrowing kept in the module too', S.libraryCareNow().narrow, 'portishead')
  reset()
  const late = S.startBulk('covers', [one])
  await settle()
  S.forgetLibraryCare()
  await answer('art', { written: 'cover.jpg' })
  await late
  check('a run from before a forget (a fresh page) draws nothing over it - its own latestOnly', S.libraryCareNow().runs.covers, null)
}

/* ===== the page: app/LibraryCare.tsx ===== */

function libraryOf(albums, more = {}) {
  C.library = {
    albums, problem: null, error: null, loading: false, loaded: true, stale: false, scannedAt: Date.now() / 1000 - 120, scanSeconds: 3,
    reload: (force) => new Promise((resolve) => C.reloads.push({ force, resolve })), ...more,
  }
}

async function page() {
  console.log('\nthe page: not the admin, a note - and nothing asked')
  {
    reset()
    S.forgetLibraryCare()
    libraryOf([album('A/B (2000)')])
    const refused = mount(LibraryCare, { admin: false, live: true, backLabel: 'You', onBack() {} })
    refused.draw()
    check('the note, and no link out (the phone\'s pointer at the main page went in 2.0.0-player.47)',
      [words(classed('app-placeholder-text')[0]), find((node) => node.type === 'a').length], [R.MANAGING_ADMINS_ONLY, 0])
    check('...the library never read, no Rescan, no run', [C.enabled.every((on) => on === false), !!button('Rescan'), classed('app-care-run').length], [true, false, 0])
    //? the page knows no frame: what was a desktop's is drawn for the admin, whatever App might hand it
    refused.draw({ admin: true, desktop: false })
    check('...the admin, told nothing of the frame: the library read, Rescan drawn', [C.enabled.at(-1), !!button('Rescan')], [true, true])
  }

  console.log('\nthe page: its states')
  {
    reset()
    libraryOf([], { loaded: false })
    const one = mount(LibraryCare, { admin: true, live: false, backLabel: 'You', onBack() {} })
    one.draw()
    check('not showing: the library not read', C.enabled.at(-1), false)
    one.draw({ live: true })
    check('showing: read; the spinner until the first answer', [C.enabled.at(-1), classed('pl-spinner').length, !!button('Rescan')], [true, 1, false])
    libraryOf([], { problem: 'LIBRARY_PATH is not set' })
    one.draw()
    check('LIBRARY_PATH not set: said plainly, nothing to press', [words(classed('app-care-state')[0]), !!button('Rescan'), classed('app-care-run').length], ['LIBRARY_PATH is not set', false, 0])
    libraryOf([], { error: 'HTTP 502' })
    one.draw()
    check('a failed read with nothing to show: said, with Try again', [words(classed('app-care-state')[0]).includes('HTTP 502'), !!button('Try again')], [true, true])
    button('Try again').props.onClick()
    check('...which reads the library again', C.reloads.map((r) => r.force), [false])
    //? (review: pinned) a read still out - this Try again's, or a Rescan's - is not read over: useLibrary
    //? draws only the newest answer, so a second plain read would drop the first one's
    libraryOf([], { error: 'HTTP 502', loading: true })
    one.draw()
    C.reloads.length = 0
    button('Try again').props.onClick()
    check('...but not while a read is still out: aria-disabled, and a press asks nothing over it', [button('Try again').props['aria-disabled'], C.reloads.length], ['true', 0])
  }

  console.log('\nthe page: Rescan')
  {
    reset()
    S.forgetLibraryCare()
    const LIB = [album('Portishead/Dummy (1994)', { art: '', release_mbid: 'r1' }), album('Portishead/Third (2008)', { lyrics_count: 0 })]
    libraryOf(LIB)
    const one = mount(LibraryCare, { admin: true, live: true, backLabel: 'You', onBack() {} })
    one.draw()
    check('what the scan holds and how old it is, as the main page says them - a status the screen reader hears',
      [words(classed('app-care-facts')[0]), classed('app-care-facts')[0].props.role], ['2 albums · 20 tracks · 200 MB · Scanned 2 min ago in 3s', 'status'])
    check('...and what Rescan is for: another program\'s retag doesn\'t move a folder\'s date', /another program/.test(words(classed('app-care-note')[0])), true)
    button('Rescan').props.onClick()
    one.draw()
    check('Rescan: the scan that ignores the cache (reload(true)), said while it runs', [C.reloads.map((r) => r.force), words(button('Rescanning…')), words(classed('app-care-facts')[0]).endsWith('Rescanning - reading every file again…')],
      [[true], 'Rescanning…', true])
    check('...refused while it is out: aria-disabled, and a second press asks nothing', [button('Rescanning…').props['aria-disabled'], (button('Rescanning…').props.onClick(), C.reloads.length)], ['true', 1])
    C.reloads[0].resolve(LIB)
    await settle()
    one.draw()
    check('...answered: Rescan again, and the library\'s listeners told once', [!!button('Rescan'), button('Rescan').props['aria-disabled'], C.announced], [true, undefined, 1])
    libraryOf(LIB, { stale: false, loading: true })
    one.draw()
    check('a plain scan under way is not a rescan - but Rescan waits for it', [words(classed('app-care-facts')[0]).includes('Rescanning'), button('Rescan').props['aria-disabled']], [false, 'true'])
    libraryOf(LIB, { stale: true, loading: true })
    one.draw()
    check('the saved scan in hand, the real one under way: said, and Rescan offered (as the main page offers it)', [words(classed('app-care-facts')[0]).includes('Saved scan from 2 min ago · checking for changes'), button('Rescan').props['aria-disabled']],
      [true, undefined])
    C.reloads.length = 0
    libraryOf(LIB, { stale: false })
    one.draw({ live: false })
    one.draw({ live: true })
    check('shown again later with nothing under way: the library read again underneath, once', C.reloads.map((r) => r.force), [false])
    //? (review: pinned) with a read still out - a Rescan pressed, the page left and come back to before it
    //? answered - nothing is read over it: useLibrary would draw the plain read, never the rescan's answer
    C.reloads.length = 0
    libraryOf(LIB, { stale: false, loading: true })
    one.draw({ live: false })
    one.draw({ live: true })
    check('...but not with a read still out (a Rescan\'s, say): nothing asked over it', C.reloads.length, 0)
    libraryOf(LIB, { error: 'HTTP 504' })
    one.draw()
    check('a refresh that failed with albums on screen: said with Try again beside the scan, the page kept',
      [words(classed('app-care-problem')[0]).startsWith("Couldn't read the library just now: HTTP 504"), !!button('Try again', classed('app-care-problem')[0]), !!button('Rescan')], [true, true, true])
    libraryOf(LIB, { error: 'HTTP 504', loading: true })
    one.draw()
    C.reloads.length = 0
    button('Try again', classed('app-care-problem')[0]).props.onClick()
    check('...its Try again refused while a read is out too: nothing asked over it', [button('Try again', classed('app-care-problem')[0]).props['aria-disabled'], C.reloads.length], ['true', 0])
  }

  console.log('\nthe page: the runs')
  {
    reset()
    S.forgetLibraryCare()
    const DUMMY = album('Portishead/Dummy (1994)', { art: '', release_mbid: 'r1', lyrics_count: 0 })
    const THIRD = album('Portishead/Third (2008)', { disc_art: ['cd.jpg'] })
    const TAKK = album('Sigur Rós/Takk (2005)', { art: '', release_mbid: 'r3', disc_art: ['disc.jpg'], lyrics_count: 0 })
    const LIB = [DUMMY, THIRD, TAKK]
    libraryOf(LIB, { stale: true })
    const one = mount(LibraryCare, { admin: true, live: true, backLabel: 'You', onBack() {} })
    one.draw()
    check('the saved scan in hand: no run offered yet - it can be behind what is on disk', [classed('app-care-run').length, buttons(classed('app-care-run')[0]).length, words(classed('app-care-note', classed('app-care-run')[0])[0])],
      [3, 0, 'Checking the library…'])
    libraryOf(LIB)
    one.draw()
    const runRow = (kind) => classed('app-care-run').find((row) => row.props['aria-labelledby'] === `app-care-${kind}`)
    check('the real scan in: each run with how many it takes, the main page\'s words',
      ['covers', 'disc', 'lyrics'].map((kind) => [words(classed('app-care-heading', runRow(kind))[0]), words(buttons(runRow(kind))[0])]),
      [['Covers', 'Get covers · 2'], ['CD art', 'Get CD art · 2'], ['Lyrics', 'Get lyrics · 2']])
    check('...each saying what it will act on before it starts, in album folders', words(classed('app-care-note', runRow('disc'))[0]).startsWith("2 album folders with a release and no CD art of deadwax's own in the whole library."), true)
    check('...and the whole library said under the field', words(classed('app-care-note')[1]), 'The runs act on the whole library: 3 album folders.')
    //? (2.0.0-player.47, review: at 17px on a phone "- empty for the whole library" was cut off mid-sentence -
    //? the line under the field says what an empty one means)
    check('...the field\'s placeholder short enough for a phone at 17px: what to type, nothing more',
      find((node) => node.type === 'input' && byClass('app-care-input')(node))[0].props.placeholder, 'Artist, album or folder')
    let told = one.redraws()
    find((node) => node.type === 'input' && byClass('app-care-input')(node))[0].props.onInput({ currentTarget: { value: 'portishead' } })
    check('words typed: the page told to draw again (the narrowing is the store\'s - nothing else would draw it)', one.redraws() > told, true)
    one.draw()
    check('words typed: kept, and every run narrowed to the albums they match',
      [S.libraryCareNow().narrow, words(classed('app-care-note')[1]), ['covers', 'disc', 'lyrics'].map((kind) => words(buttons(runRow(kind))[0]))],
      ['portishead', 'The runs act on 2 of 3 album folders: those matching “portishead”.', ['Get covers · 1', 'Get CD art · 2', 'Get lyrics · 1']])
    check('...said in each run too', words(classed('app-care-note', runRow('covers'))[0]).startsWith('1 album folder with a release and no cover among the folders matching “portishead”.'), true)

    told = one.redraws()
    buttons(runRow('disc'))[0].props.onClick()
    await settle()
    check('Get CD art pressed: the page told to draw again as the run starts', one.redraws() > told, true)
    one.draw()
    check('Get CD art pressed: the targets in view asked, one at a time, through Get CD art\'s call', C.calls.map((c) => [c.route, c.path]), [['disc', 'Portishead/Dummy (1994)']])
    check('...its button now Stop, with how far it has got; the run\'s words empty while it runs',
      [words(buttons(runRow('disc'))[0]), buttons(runRow('disc'))[0].props.class.includes('is-running'), classed('app-care-spin', runRow('disc')).length, words(classed('app-care-result', runRow('disc'))[0])],
      ['Stop · 0 of 2', true, 1, ''])
    check('...the other runs still offered - each kind runs on its own, as on the main page', words(buttons(runRow('covers'))[0]), 'Get covers · 1')
    told = one.redraws()
    await answer('disc', { written: ['disc.jpg'], source: 'caa' })
    check('...told again as each album answers', one.redraws() > told, true)
    one.draw()
    check('one done: Stop says so', words(buttons(runRow('disc'))[0]), 'Stop · 1 of 2')
    told = one.redraws()
    buttons(runRow('disc'))[0].props.onClick()
    check('...told again as Stop is pressed', one.redraws() > told, true)
    one.draw()
    check('Stop pressed: "Stopping after" the album being fetched, aria-disabled', [words(buttons(runRow('disc'))[0]), buttons(runRow('disc'))[0].props['aria-disabled']], ['Stopping after 2 of 2', 'true'])
    told = one.redraws()
    await answer('disc', new ApiError(404, 'no CD art', 'x'))
    check('...and as it ends', one.redraws() > told, true)
    one.draw()
    check('ended: its words, the main page\'s, kept on screen - a status the screen reader hears',
      [words(classed('app-care-result', runRow('disc'))[0]), classed('app-care-result', runRow('disc'))[0].props.role], ['fetched CD art for 1 album, 1 had none to find', 'status'])
    check('...and the library told once', C.announced, 1)

    //? (review: the scan in hand still listed Dummy as without CD art, so "Get CD art · 2" came back at
    //? once, where Stop had been - pressed again, every album asked again and refused, "2 failed")
    check('a run that wrote, ended: its button held back - never drawn again over the albums it just did - its plan saying the library is being checked, the library read again at once',
      [buttons(runRow('disc')).length, words(classed('app-care-note', runRow('disc'))[0]), C.reloads.map((r) => r.force)], [0, 'Checking the library…', [false]])
    check('...only its kind: the others still offered over the scan in hand', [words(buttons(runRow('covers'))[0]), words(buttons(runRow('lyrics'))[0])], ['Get covers · 1', 'Get lyrics · 1'])
    one.draw()
    check('...read once for it, however often the page draws meanwhile', C.reloads.length, 1)
    const AFTER = [{ ...DUMMY, disc_art: ['disc.jpg'] }, THIRD, TAKK]
    libraryOf(AFTER, { loading: true })
    C.reloads[0].resolve(AFTER)
    await settle()
    one.draw()
    check('...that read answered while a newer one is still out (only the newest is drawn): still held', buttons(runRow('disc')).length, 0)
    libraryOf(AFTER)
    one.draw()
    check('...answered, nothing newer out: offered again over the albums as they are now - the one the Archive had none for',
      [words(buttons(runRow('disc'))[0]), S.libraryCareNow().behind.disc, C.reloads.length], ['Get CD art · 1', false, 1])

    //? the page gone (the sidebar's Log, Back) and drawn again: the result still there
    one.unmount()
    const gone = one.redraws()
    const again = mount(LibraryCare, { admin: true, live: true, backLabel: 'You', onBack() {} })
    again.draw()
    check('the page left and come back to: the run\'s words still there, the words typed too',
      [words(classed('app-care-result', runRow('disc'))[0]), find((node) => node.type === 'input' && byClass('app-care-input')(node))[0].props.value], ['fetched CD art for 1 album, 1 had none to find', 'portishead'])
    buttons(runRow('lyrics'))[0].props.onClick()
    await settle()
    check('a page gone is told nothing more (its listener let go)', one.redraws(), gone)
    again.unmount()
    const third = mount(LibraryCare, { admin: true, live: true, backLabel: 'You', onBack() {} })
    third.draw()
    check('a run going on while the page was away: drawn running again, its Stop live', [words(buttons(runRow('lyrics'))[0]), (buttons(runRow('lyrics'))[0].props.onClick(), S.libraryCareNow().stopping.lyrics)],
      ['Stop · 0 of 1', true])
    await answer('lyrics', lyricsSummary({ written: 9, instrumental: 1 }))
    third.draw()
    check('...its result said there once it ends', words(classed('app-care-result', runRow('lyrics'))[0]), 'saved lyrics for 9 tracks, 1 not on LRCLIB or instrumental')

    //? a run that wrote while no page drew it: a page drawn after begins every read of its own after it
    buttons(runRow('covers'))[0].props.onClick()
    await settle()
    third.unmount()
    await answer('art', { written: 'cover.jpg' })
    check('a run that wrote, ended while the page was away: behind', S.libraryCareNow().behind.covers, true)
    C.reloads.length = 0
    libraryOf([{ ...DUMMY, art: 'file', disc_art: ['disc.jpg'], lyrics_count: 9 }, THIRD, TAKK])
    const fourth = mount(LibraryCare, { admin: true, live: true, backLabel: 'You', onBack() {} })
    fourth.draw()
    check('...a page drawn after it: nothing held (its reads all come after the run), no read asked for it - drawn from the scan it reads',
      [S.libraryCareNow().behind, C.reloads.length, words(classed('app-care-note', runRow('covers'))[0]).startsWith('No album with a release is missing its cover')],
      [{ covers: false, disc: false, lyrics: false }, 0, true])
    fourth.unmount()

    //? a run's button gone with focus on it (nothing left to fetch): focus to the run's words
    S.forgetLibraryCare()
    reset()
    libraryOf([DUMMY])
    const focus = mount(LibraryCare, { admin: true, live: true, backLabel: 'You', onBack() {} })
    focus.draw()
    const wordsElement = { focused: false, focus() { this.focused = true } }
    const buttonElement = { isConnected: true }
    let body = { tag: 'button' }
    globalThis.document = { get activeElement() { return body }, body: { tag: 'body' } }
    const startButton = buttons(runRow('covers'))[0]
    startButton.props.ref(buttonElement)
    classed('app-care-result', runRow('covers'))[0].props.ref(wordsElement)
    startButton.props.onFocus()
    startButton.props.onClick()
    await settle()
    focus.draw()
    body = globalThis.document.body
    focus.draw()
    check('focus fallen to the page while the run\'s button is still there (a click elsewhere): left where it went', wordsElement.focused, false)
    body = { tag: 'button' }
    await answer('art', { written: 'cover.jpg' })
    libraryOf([{ ...DUMMY, art: 'file' }])
    //? (review: Chromium blurs a focused button AS it removes it - still in the page as it does - and
    //? that blur was read as focus moving on, so focus fell to the page)
    buttons(runRow('covers'))[0].props.onBlur({ currentTarget: buttonElement })
    buttonElement.isConnected = false
    buttons(runRow('covers'))[0]?.props.ref(null)
    body = globalThis.document.body
    focus.draw()
    check('the run ended with nothing left: its button gone (blurred as it went, as Chromium does), focus handed to its words - never to the page', [buttons(runRow('covers')).length, wordsElement.focused], [0, true])
    await settle()
    //? its read of the library answered: nothing behind any more
    C.reloads.at(-1).resolve([{ ...DUMMY, art: 'file' }])
    await settle()
    focus.draw()

    //? focus moved on from the button while it was still there: nothing to hand on when it goes
    reset()
    libraryOf([DUMMY])
    focus.draw()
    const words2 = { focused: false, focus() { this.focused = true } }
    const button2 = { isConnected: true }
    body = { tag: 'button' }
    buttons(runRow('covers'))[0].props.ref(button2)
    classed('app-care-result', runRow('covers'))[0].props.ref(words2)
    buttons(runRow('covers'))[0].props.onFocus()
    buttons(runRow('covers'))[0].props.onBlur({ currentTarget: button2 })
    buttons(runRow('covers'))[0].props.onClick()
    await settle()
    focus.draw()
    await answer('art', { written: 'cover.jpg' })
    libraryOf([{ ...DUMMY, art: 'file' }])
    button2.isConnected = false
    buttons(runRow('covers'))[0]?.props.ref(null)
    body = globalThis.document.body
    focus.draw()
    check('...but not once focus had moved on from it before it went', words2.focused, false)
    delete globalThis.document
  }
}

/* ===== Re-time saved lyrics: components/RetimeLyrics.tsx ===== */

async function retime() {
  console.log('\nRe-time saved lyrics (the settings tab\'s, drawn by both settings pages)')
  reset()
  RT.forgetRetime()
  const one = mount(RT.RetimeLyrics, { unsaved: true })
  one.draw()
  const retimeButton = () => buttons()[0]
  check('the lead a draft: refused - disabled, and why', [retimeButton().props.disabled, words(classed('settings-retime-note')[0]), retimeButton().props.title.startsWith('Save the new lead first')],
    [true, 'Save the new lead first.', true])
  one.draw({ unsaved: false })
  check('the lead saved: offered, saying what it is for', [retimeButton().props.disabled, words(retimeButton()), words(classed('settings-retime-note')[0])],
    [false, 'Re-time saved lyrics', 'Lyrics saved before the lead changed keep their old timings until re-timed.'])
  let told = one.redraws()
  retimeButton().props.onClick()
  await settle()
  check('pressed: told to draw again (the run is the module\'s - nothing else would draw it, on either settings page)', one.redraws() > told, true)
  one.draw()
  check('pressed: a REAL scan read - never the saved one - and the button its Stop', [C.lists.length, C.snapshots, words(retimeButton())], [1, [], 'reading the library'])
  C.lists[0].resolve({ albums: [album('A/One (2000)', { lyrics_count: 4 }), album('A/None (2000)', { lyrics_count: 0 }), album('A/Two (2000)', { lyrics_count: 2 })] })
  await settle()
  one.draw()
  //? (its count shows from the first album done - "reading the library" until then, as on the main page before the move)
  check('...the albums with lyrics, one at a time, through the re-time route', [C.calls.map((c) => [c.route, c.path, c.options]), words(retimeButton())],
    [[['retime', 'A/One (2000)', { retime: true }]], 'reading the library'])
  told = one.redraws()
  await answer('retime', lyricsSummary({ retimed: 3, unchanged: 1 }))
  check('...told again as an album answers', one.redraws() > told, true)
  one.draw()
  check('...one done: the next asked, the count moved', [C.calls.map((c) => c.path), words(retimeButton())], [['A/One (2000)', 'A/Two (2000)'], 're-timing 1/2 albums · stop'])
  one.unmount()
  const gone = one.redraws()
  const back = mount(RT.RetimeLyrics, { unsaved: false })
  back.draw()
  check('the page gone and drawn again (its tab left, the app\'s page left): the run still drawn, Stop and all', words(buttons()[0]), 're-timing 1/2 albums · stop')
  buttons()[0].props.onClick()
  await answer('retime', lyricsSummary({ custom: 1, failed: 1 }))
  check('...the page gone told nothing more (its listener let go)', one.redraws(), gone)
  back.draw()
  const ended = "re-timed 3 tracks, 1 already at this lead, 1 left alone - not LRCLIB's timings any more, so edited by hand or from somewhere else, 1 failed - try again."
  check('...its words once it ends: re-timed, already at this lead, left alone, failed', words(classed('settings-retime-note')[0]), ended)
  const PROMPT = 'Lyrics saved before the lead changed keep their old timings until re-timed.'

  //? (review: kept in the module, an ended run's words outlived every later visit - the main page's tab
  //? left and come back to, a new lead saved meanwhile, still said "re-timed 3 tracks.")
  back.unmount()
  const later = mount(RT.RetimeLyrics, { unsaved: false })
  later.draw()
  check('an ended run said, then the tab left and come back to: the prompt again - as when the run was the component\'s', words(classed('settings-retime-note')[0]), PROMPT)
  later.unmount()

  //? a run that ends while nothing draws it says how it ended on coming back - once
  RT.forgetRetime()
  reset()
  const going = mount(RT.RetimeLyrics, { unsaved: false })
  going.draw()
  buttons()[0].props.onClick()
  await settle()
  C.lists[0].resolve({ albums: [album('A/One (2000)', { lyrics_count: 4 })] })
  await settle()
  going.unmount()
  await answer('retime', lyricsSummary({ retimed: 4 }))
  const comeBack = mount(RT.RetimeLyrics, { unsaved: false })
  comeBack.draw()
  check('a run that ended while nothing drew it: said on coming back', words(classed('settings-retime-note')[0]), 're-timed 4 tracks.')
  comeBack.unmount()
  const after = mount(RT.RetimeLyrics, { unsaved: false })
  after.draw()
  check('...once: the visit after says the prompt', words(classed('settings-retime-note')[0]), PROMPT)

  //? a new lead typed after a run ended: its words were at the old lead
  RT.forgetRetime()
  reset()
  after.draw()
  buttons()[0].props.onClick()
  await settle()
  C.lists[0].resolve({ albums: [album('A/One (2000)', { lyrics_count: 2 })] })
  await settle()
  await answer('retime', lyricsSummary({ retimed: 2 }))
  after.draw()
  check('ended, on screen', words(classed('settings-retime-note')[0]), 're-timed 2 tracks.')
  after.draw({ unsaved: true })
  check('...a new lead typed: "Save the new lead first."', words(classed('settings-retime-note')[0]), 'Save the new lead first.')
  after.draw({ unsaved: false })
  check('...saved: the prompt - never the old run\'s words, which were at the old lead', words(classed('settings-retime-note')[0]), PROMPT)

  //? a new lead typed while a run goes on, the run ending meanwhile: the same once it is saved
  RT.forgetRetime()
  reset()
  after.draw()
  buttons()[0].props.onClick()
  await settle()
  C.lists[0].resolve({ albums: [album('A/One (2000)', { lyrics_count: 2 })] })
  await settle()
  after.draw({ unsaved: true })
  await answer('retime', lyricsSummary({ retimed: 2 }))
  after.draw()
  after.draw({ unsaved: false })
  check('a new lead typed while it ran, the run ending meanwhile: once saved, the prompt', words(classed('settings-retime-note')[0]), PROMPT)

  //? (review: a new lead typed AND saved while it ran - the server reads the lead as each album is asked
  //? for, so the albums before the save moved to the old lead; "re-timed 5 tracks." under the new one
  //? read as though the whole library had been)
  RT.forgetRetime()
  reset()
  after.draw()
  buttons()[0].props.onClick()
  await settle()
  C.lists[0].resolve({ albums: [album('A/One (2000)', { lyrics_count: 2 }), album('A/Two (2000)', { lyrics_count: 3 })] })
  await settle()
  await answer('retime', lyricsSummary({ retimed: 2 }))
  after.draw({ unsaved: true })
  after.draw({ unsaved: false })
  check('a new lead typed and saved while it ran: the run goes on, Stop and all', words(buttons()[0]), 're-timing 1/2 albums · stop')
  await answer('retime', lyricsSummary({ retimed: 3 }))
  after.draw()
  check('...and as it ends, the prompt - never "re-timed 5 tracks.", part of which was at the lead no longer saved', words(classed('settings-retime-note')[0]), PROMPT)
  //? the next run starts clean: what it says is its own again
  buttons()[0].props.onClick()
  await settle()
  C.lists[1].resolve({ albums: [album('A/One (2000)', { lyrics_count: 2 })] })
  await settle()
  await answer('retime', lyricsSummary({ unchanged: 2 }))
  after.draw()
  check('...a run after it, nothing typed: its words, as ever', words(classed('settings-retime-note')[0]), 're-timed 0 tracks, 2 already at this lead.')
  //? the same however it ends: a lead typed and saved while the library was read, the read failing
  buttons()[0].props.onClick()
  await settle()
  after.draw({ unsaved: true })
  after.draw({ unsaved: false })
  C.lists[2].reject(new Error('HTTP 504'))
  await settle()
  after.draw()
  check('...a lead typed and saved while the library was read, the read failing: let go the same, the prompt', words(classed('settings-retime-note')[0]), PROMPT)
  after.unmount()
  const back2 = mount(RT.RetimeLyrics, { unsaved: false })
  RT.forgetRetime()
  reset()
  back2.draw()
  buttons()[0].props.onClick()
  await settle()
  C.lists[0].resolve({ albums: [album('A/One (2000)', { lyrics_count: 4 }), album('A/Two (2000)', { lyrics_count: 2 })] })
  await settle()
  back2.draw()
  buttons()[0].props.onClick()
  back2.draw()
  await answer('retime', new Error('LRCLIB went away'))
  back2.draw()
  check('Stop during the first album: it ends after it, said "stopped at" - a failed album counting its lyrics failed',
    [C.calls.length, words(classed('settings-retime-note')[0])], [1, 're-timed 0 tracks, 4 failed - try again (stopped at 1 of 2 albums)'])
  RT.forgetRetime()
  reset()
  back2.draw()
  buttons()[0].props.onClick()
  await settle()
  C.lists[0].reject(new Error('HTTP 504'))
  await settle()
  back2.draw()
  check('the library couldn\'t be read: said, nothing re-timed', [words(classed('settings-retime-note')[0]), C.calls.length], ["couldn't read the library - Error: HTTP 504", 0])
  back2.unmount()
  const back3 = mount(RT.RetimeLyrics, { unsaved: false })
  back3.draw()
  check('...said once too: the tab left and come back to, the prompt', words(classed('settings-retime-note')[0]), PROMPT)
  back3.unmount()
  RT.forgetRetime()
}

/* ===== Choose the folder: app/FolderPicker.tsx ===== */

function picker() {
  console.log('\nChoose the folder (the Edit panel\'s list over the scan)')
  const SCAN = [album('Portishead/Dummy (1994)'), album('Old Rips/Third rip', { artist: 'Portishead', album: 'Third', release_mbid: '' }), album('Björk/Homogenic (1997)', { artist: '', album: '' })]
  const typed = [], picked = []
  //? FolderPicker uses useMemo: drawn in a root
  const render = hooks.root(FolderPicker)
  const at = (text) => { tree = expand(render({ albums: SCAN, typed: text, onType: (value) => typed.push(value), onPick: (folder) => picked.push(folder) })); render.commit() }
  at('')
  check('every folder of the scan, by path, each with its tags under it - "no release" for an untagged one',
    classed('app-edit-pick-choice').map((choice) => [words(classed('app-edit-pick-path', choice)[0]), words(classed('app-edit-pick-sub', choice)[0])]),
    [['Björk/Homogenic (1997)', 'No artist or album tags'], ['Old Rips/Third rip', 'Portishead - Third · no release'], ['Portishead/Dummy (1994)', 'Portishead - Dummy']])
  check('...and how many, over them, as a status', [words(find((node) => node.props?.role === 'status')[0]), find((node) => node.type === 'input')[0].props['aria-controls']],
    ['3 folders - pick the one this album is.', 'app-edit-pick-list'])
  //? (2.0.0-player.47, review: the field is a phone's too now, in the Edit sheet - 262px for words at 17px at
  //? 320 wide, where "Type part of its name, artist or path" lost "path"; the status under it says the rest)
  check('...the field\'s placeholder short enough for a phone at 17px: what to type, nothing more',
    find((node) => node.type === 'input')[0].props.placeholder, 'Name, artist or path')
  find((node) => node.type === 'input')[0].props.onInput({ currentTarget: { value: 'portishead third' } })
  check('typing told to the panel', typed, ['portishead third'])
  at('portishead third')
  check('...the list narrowed to every word, and said', [classed('app-edit-pick-path').map(words), words(find((node) => node.props?.role === 'status')[0])],
    [['Old Rips/Third rip'], '1 folder matches - pick the one this album is.'])
  classed('app-edit-pick-choice')[0].props.onClick()
  check('a folder clicked: handed on, by its path', picked, ['Old Rips/Third rip'])
  at('nothing like it')
  check('nothing matching: said, no list (and the field points at none)', [classed('app-edit-pick-choice').length, words(find((node) => node.props?.role === 'status')[0]), find((node) => node.type === 'input')[0].props['aria-controls']],
    [0, "No folder in the library's scan matches that.", undefined])
}

//? a check waiting on an answer that never comes would let Node exit quietly, as if everything passed
let finished = false
process.on('exit', (code) => {
  if (!finished && code === 0) {
    console.log('\nFAIL  the sim ended before its last check - something it waited for never came')
    process.exitCode = 1
  }
})

runs()
  .then(pageWords)
  .then(store)
  .then(page)
  .then(retime)
  .then(picker)
  .then(() => {
    finished = true
    console.log(failures ? `\n${failures} FAILED` : '\nall passed')
    process.exit(failures ? 1 : 0)
  })
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
