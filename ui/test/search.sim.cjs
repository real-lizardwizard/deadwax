/**
 * The app's Search tab (app/Search.tsx), 2.0.0-player.13 - the component itself, compiled with the
 * repo's TypeScript and rendered by the small stand-in for Preact the other component sims use, with
 * Navidrome, MusicBrainz and /library/owned faked and the clock a fake one. Beside it, the store of
 * what the library holds (app/useOwned.ts, the real one) and the real prefetch in player/api.ts.
 *
 * What it pins, each a review's finding:
 *
 *  - What the library holds: one ask out at a time, one more after it when asked meanwhile; a
 *    refreshOwned() answered only once an ask made after it has landed; a filed album asking again
 *    once anything has asked - even after a first ask that failed - and never before.
 *  - The library half: Navidrome asked after the pause, the box no longer than the route takes, the
 *    songs' albums asked for KEPT, a song's tap playing its album from it (remembered first) only
 *    with the album in hand and opening the album otherwise, album rows prefetching as a tile does,
 *    and Navidrome failing drawn as the MusicBrainz half's problem is - the same 44px Try again.
 *  - The Navidrome gate: it wraps the library half alone, with App's status; MusicBrainz is searched
 *    with Navidrome down.
 *  - The MusicBrainz half: held albums left out (by the library's answer, waited for a moment), and
 *    an answer that lands later never taking a row away - it marks it "in your library" in place; a
 *    read as artist and album that finds nothing asked again as free text; and a box cut back below
 *    three characters dropping the longer text's answer (or calling off its search) and saying how to
 *    ask - and asking again when the text comes back.
 *  - The real prefetch: a press that turned into a scroll calls off a tile's own ask, never one Search
 *    keeps, whichever asked first; the album page still takes a kept ask once.
 *  - Get chips (2.0.0-player.15): on a MusicBrainz row the library doesn't hold, not on one it does;
 *    a tap takes its opener, asks for the album's pressings (busy meanwhile) through a latestOnly of
 *    its own - a newer tap calls the older off, and a late answer opens nothing - and opens the
 *    Sources sheet for the USUAL pressing, built by the one payload builder; MusicBrainz failing is
 *    the album as a whole, said so; a complete answer is kept for the session, so a second tap asks
 *    nothing, and a failure is not. And (review) a lookup still out is called off - the chip back to
 *    Get, its late answer opening nothing - the moment the tab's root stops being what shows (App's
 *    `active`) or the box changes.
 *
 * Run it with:  node ui/test/search.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-search-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/Search.tsx', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? the real prefetch, kept aside before player/api.js is faked for the component
fs.copyFileSync(path.join(OUT, 'player/api.js'), path.join(OUT, 'player/api.real.js'))

//? JSX as plain objects, and hooks with a cursor, as Preact's are - the stand-in group.sim.cjs uses
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\nexports.createContext = () => ({})\n`)
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
  return render
}
`)

/* ===== Navidrome, MusicBrainz and the library, faked: each answer is what the test says next ===== */

fs.writeFileSync(path.join(OUT, 'api/musicbrainz.js'), `
exports.fullySearch = (query, limit, releases, signal) => globalThis.__search.fullySearch(query, limit, releases, signal)
exports.getReleaseGroup = (id, signal) => globalThis.__search.getReleaseGroup(id, signal)
`)
//? You > Getting albums, asked as the tab shows; and the opener a chip's tap focuses
fs.writeFileSync(path.join(OUT, 'app/useGetSettings.js'), `
exports.useGetSettings = (ask) => { globalThis.__search.settingsAsked.push(ask); return { settings: null, canSave: true, problem: null } }
`)
fs.writeFileSync(path.join(OUT, 'app/useSheet.js'), `
exports.takeOpener = (event) => event.currentTarget
`)
fs.writeFileSync(path.join(OUT, 'api/library.js'), `
exports.owned = () => globalThis.__search.owned()
`)
fs.writeFileSync(path.join(OUT, 'player/api.js'), `
exports.searchLibrary = (text, signal) => globalThis.__search.searchLibrary(text, signal)
exports.prefetchAlbum = (id, keep) => globalThis.__search.prefetchAlbum(id, keep)
exports.dropPrefetch = (id) => globalThis.__search.calls.push(['dropPrefetch', id])
exports.rememberPlayed = (album) => globalThis.__search.calls.push(['rememberPlayed', album.id])
exports.toQueueTrack = (song, album) => ({ id: song.id, album: album.id })
`)
fs.writeFileSync(path.join(OUT, 'player/Cover.js'), `exports.Cover = function Cover() { return null }\n`)
fs.writeFileSync(path.join(OUT, 'player/icons.js'), `exports.PlayIcon = function PlayIcon() { return null }\nexports.SearchIcon = function SearchIcon() { return null }\n`)
fs.writeFileSync(path.join(OUT, 'app/ArchiveCover.js'), `exports.ArchiveCover = function ArchiveCover() { return null }\n`)
fs.writeFileSync(path.join(OUT, 'app/NeedsNavidrome.js'), `exports.NeedsNavidrome = function NeedsNavidrome() { return null }\n`)
fs.writeFileSync(path.join(OUT, 'app/context.js'), `exports.usePlayerActions = () => globalThis.__search.actions\n`)

/* ===== a clock the test moves ===== */

let now = 0
let nextTimer = 1
const timers = new Map()
globalThis.setTimeout = (fn, ms = 0) => { const id = nextTimer++; timers.set(id, { at: now + ms, fn }); return id }
globalThis.clearTimeout = (id) => { timers.delete(id) }
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))
async function advance(ms) {
  const end = now + ms
  for (;;) {
    const due = [...timers.entries()].filter(([, timer]) => timer.at <= end).sort((a, b) => a[1].at - b[1].at)[0]
    if (!due) break
    timers.delete(due[0])
    now = due[1].at
    due[1].fn()
    await settle()
  }
  now = end
  await settle()
}

function deferred() {
  const d = {}
  d.promise = new Promise((yes, no) => {
    d.resolve = (value) => { d.done = true; yes(value) }
    d.reject = (reason) => { d.done = true; no(reason) }
  })
  return d
}

/** Answer every ask of /library/owned out now, and the one each starts after it, until none is out. */
async function answerOwned(answer) {
  for (let pending = asks.owned.filter((d) => !d.done); pending.length; pending = asks.owned.filter((d) => !d.done)) {
    for (const d of pending) d.resolve(answer)
    await settle()
  }
}

const asks = { owned: [], library: [], musicbrainz: [], prefetch: [], pressings: [] }
globalThis.__search = {
  calls: [],
  settingsAsked: [],
  //? false: an answer already on its way when it was called off still lands
  abortRejects: true,
  getReleaseGroup(id, signal) {
    const d = deferred()
    asks.pressings.push({ id, signal, ...d })
    if (signal && globalThis.__search.abortRejects) signal.addEventListener('abort', () => { const error = new Error('aborted'); error.name = 'AbortError'; d.reject(error) })
    return d.promise
  },
  actions: { playTracks: (queue, at) => globalThis.__search.calls.push(['playTracks', queue.map((track) => track.id), at]) },
  owned() { const d = deferred(); asks.owned.push(d); return d.promise },
  searchLibrary(text, signal) { const d = deferred(); asks.library.push({ text, signal, ...d }); return d.promise },
  fullySearch(query, limit, releases, signal) {
    const d = deferred()
    asks.musicbrainz.push({ query, limit, releases, signal, ...d })
    if (signal) signal.addEventListener('abort', () => { const error = new Error('aborted'); error.name = 'AbortError'; d.reject(error) })
    return d.promise
  },
  prefetchAlbum(id, keep) { const d = deferred(); asks.prefetch.push({ id, keep, ...d }); return d.promise },
}

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const Owned = require(path.join(OUT, 'app/useOwned.js'))
const { Search, OWNED_WAIT_MS } = require(path.join(OUT, 'app/Search.js'))
const { NeedsNavidrome } = require(path.join(OUT, 'app/NeedsNavidrome.js'))
const { SEARCH_MAX_CHARS } = require(path.join(OUT, 'lib/searchQuery.js'))
const { announceAlbumsFiled } = require(path.join(OUT, 'lib/libraryEvents.js'))

let tree = null
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
function text(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(text).join('')
  if (typeof node.type !== 'string' && node.type !== 'fragment') return ''  // a component, not drawn here
  return text(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)

const DUMMY = { id: '48140466-cff6-3222-bd55-63c27e43190d', title: 'Dummy', 'primary-type': 'Album', 'first-release-date': '1994-08-22' }
const THIRD = { id: '0d4b7b3b-6b4b-4c7a-9d43-9b4f0c3f4b8e', title: 'Third', 'primary-type': 'Album', 'first-release-date': '2008-04-28' }
const ROSELAND = { id: '5d1b0c5c-0ffa-3f1e-bc3e-0b7e1b4c9f20', title: 'Roseland NYC Live', 'primary-type': 'Album', 'secondary-types': ['Live'], 'first-release-date': '1998-11-02' }
const holding = (...groups) => ({ albums: groups.map((group) => ({ path: `Portishead/${group.title}`, artist: 'Portishead', album: group.title, release_group_mbid: group.id })) })

async function main() {
  console.log('what the library holds (app/useOwned.ts)')
  {
    const probe = hooks.root((props) => Owned.useOwned(props.ask))
    const show = (ask) => { const held = probe({ ask }); probe.commit(); return held }
    show(false)
    check('not asked while nothing that reads it has shown', asks.owned.length, 0)
    announceAlbumsFiled()
    check('...nor when an album is filed before anything has asked', asks.owned.length, 0)
    show(true)
    check('asked when a screen that reads it shows', asks.owned.length, 1)
    asks.owned[0].reject(new Error('deadwax restarting'))
    await settle()
    check('a failed first ask: nothing held, and nothing claimed', [Owned.ownedNow(), show(true)], [null, null])
    announceAlbumsFiled()
    check('...and a filed album asks again even so (something has asked)', asks.owned.length, 2)
    asks.owned[1].resolve(holding(DUMMY))
    await settle()
    check('...whose answer is what it holds now', Owned.ownedNow()?.artists, ['Portishead'])

    let answered = false
    void Owned.refreshOwned()
    Owned.refreshOwned().then(() => { answered = true })
    check('one ask out at a time: asked meanwhile, it waits', asks.owned.length, 3)
    asks.owned[2].resolve(holding(DUMMY))
    await settle()
    check('...and asks once more when the one out lands', [asks.owned.length, answered], [4, false])
    asks.owned[3].resolve(holding(DUMMY, THIRD))
    await settle()
    check('...answered only once an ask made after it has landed, with that answer', [answered, Owned.ownedNow()?.index.byGroup.has(THIRD.id)], [true, true])
    //? leave it holding Dummy alone for the Search below
    void Owned.refreshOwned()
    asks.owned[4].resolve(holding(DUMMY))
    await settle()
  }

  console.log('\nthe library half')
  const status = { configured: true, ok: true, server: 'Navidrome 0.64.2', problem: null }
  const opened = []
  const groupsOpened = []
  const render = hooks.root(Search)
  const gets = []
  const props = { shown: true, active: true, status, onRetry() {}, onOpenAlbum: (album) => opened.push(album), onOpenGroup: (group) => groupsOpened.push(group),
    onGet: (request, opener) => gets.push([request, opener]) }
  const draw = (more = {}) => { Object.assign(props, more); tree = render(props); render.commit(); return tree }
  const type = (value) => { find((node) => node.type === 'input')[0].props.onInput({ currentTarget: { value } }); draw(); draw() }
  const section = () => find((node) => node.type === 'section' && node.props['aria-labelledby'] === 'app-search-musicbrainz')[0]
  const rows = () => find(byClass('app-result'), section()).map((row) => [text(find(byClass('app-result-title'), row)[0]), text(find(byClass('app-result-line'), row)[0])])
  draw()
  check('the box holds no more than the route takes', find((node) => node.type === 'input')[0].props.maxLength, SEARCH_MAX_CHARS)
  check('...which is the route\'s bound', SEARCH_MAX_CHARS, 200)

  type('portishead')
  await advance(199)
  check('Navidrome is asked once typing has paused', asks.library.length, 0)
  await advance(1)
  check('...200 ms after', asks.library.map((ask) => ask.text), ['portishead'])
  asks.library[0].resolve({
    artists: [{ id: 'ar1', name: 'Portishead', albumCount: 3 }],
    albums: [{ id: 'nd-dummy', name: 'Dummy', artist: 'Portishead', year: 1994 }],
    songs: [{ id: 's1', title: 'Sour Times', albumId: 'nd-dummy', album: 'Dummy' }, { id: 's2', title: 'Roads', albumId: 'nd-dummy', album: 'Dummy' },
      { id: 's3', title: 'The Rip', albumId: 'nd-third', album: 'Third' }],
  })
  await settle()
  check('the songs\' albums are asked for as the answer lands - KEPT, so a scroll can\'t call them off',
    asks.prefetch.map((ask) => [ask.id, ask.keep]), [['nd-dummy', true], ['nd-third', true]])
  asks.prefetch[0].resolve({ id: 'nd-dummy', name: 'Dummy', song: [{ id: 's1', title: 'Sour Times' }, { id: 's2', title: 'Roads' }] })
  await settle()
  draw()
  const song = (id) => find((node) => node.type === 'li' && node.key === `song:${id}`)[0]
  const playMark = (id) => find((node) => node.type?.name === 'PlayIcon', song(id)).length
  check('a song whose album is in hand shows the play mark; one whose album isn\'t, none', [playMark('s1'), playMark('s3')], [1, 0])
  find((node) => node.type === 'button', song('s2'))[0].props.onClick()
  check('its tap remembers the album, then plays it from that song, in the tap', globalThis.__search.calls, [['rememberPlayed', 'nd-dummy'], ['playTracks', ['s1', 's2'], 1]])
  find((node) => node.type === 'button', song('s3'))[0].props.onClick()
  check('a song whose album isn\'t in hand opens the album instead', [opened.map((album) => album.id), globalThis.__search.calls.length], [['nd-third'], 2])
  const albumRow = find((node) => node.type === 'li' && node.key === 'album:nd-dummy')[0]
  const albumButton = find((node) => node.type === 'button', albumRow)[0]
  albumButton.props.onPointerDown()
  albumButton.props.onPointerCancel()
  check('an album row asks for its songs as the finger lands, as a tile does - not kept - and lets go on a scroll',
    [asks.prefetch.at(-1).id, asks.prefetch.at(-1).keep, globalThis.__search.calls.at(-1)], ['nd-dummy', undefined, ['dropPrefetch', 'nd-dummy']])

  console.log('\nthe Navidrome gate wraps the library half alone')
  {
    const gate = find((node) => node.type === NeedsNavidrome)[0]
    check('with App\'s status', gate?.props.status === status, true)
    check('...and the MusicBrainz half outside it', [!!section(), find((node) => node.props?.['aria-labelledby'] === 'app-search-musicbrainz', gate).length], [true, 0])
  }

  console.log('\nthe MusicBrainz half: what the library holds is left out, and never taken away once drawn')
  await advance(500)
  check('MusicBrainz is asked 700 ms after typing stops, as the artist\'s albums', asks.musicbrainz.map((ask) => ask.query), ['artist:"Portishead"'])
  check('...the library asked beside it', asks.owned.length, 6)
  asks.musicbrainz[0].resolve({ 'release-groups': [DUMMY, THIRD, ROSELAND] })
  await settle()
  draw()
  check('MusicBrainz answered, the library not yet: still asking, nothing drawn to be taken away', [text(find(byClass('app-asking'), section())[0]), rows().length],
    ['Asking MusicBrainz…', 0])
  asks.owned[5].resolve(holding(DUMMY))
  await settle()
  draw()
  check('the library answered: drawn, the album it holds left out', rows().map(([title]) => title), ['Third', 'Roseland NYC Live'])
  find((node) => node.type === 'button', section())[0].props.onClick()
  check('a row opens the album you don\'t have', groupsOpened.map((group) => group.title), ['Third'])

  //? Enter on the same words: the library slow to answer this time, past the wait
  find((node) => node.type === 'form')[0].props.onSubmit({ preventDefault() {} })
  draw()
  asks.musicbrainz[1].resolve({ 'release-groups': [DUMMY, THIRD, ROSELAND] })
  await settle()
  await advance(OWNED_WAIT_MS - 1)
  draw()
  check('waiting on the library, a moment at most', rows().length, 0)
  await advance(1)
  draw()
  check('...then drawn with the last answer', rows().map(([title]) => title), ['Third', 'Roseland NYC Live'])
  asks.owned[6].resolve(holding(DUMMY, THIRD))
  await settle()
  draw()
  check('an answer landing after never takes a row away: it says so in place', rows(),
    [['Third', 'Album · 2008 · in your library'], ['Roseland NYC Live', 'Live album · 1998']])

  console.log('\nGet chips (2.0.0-player.15): the usual pressing, in the Sources sheet')
  {
    check('You > Getting albums asked as the tab shows', globalThis.__search.settingsAsked.at(-1), true)
    const rowOf = (title) => find((node) => node.type === 'li' && byClass('app-result-row')(node), section()).find((li) => text(find(byClass('app-result-title'), li)[0]) === title)
    const chipOf = (title) => find(byClass('app-result-get'), rowOf(title))[0]
    check('a row the library holds has no chip; one it doesn\'t has', [!!chipOf('Third'), !!chipOf('Roseland NYC Live')], [false, true])
    check('...beside the row\'s own button, which still opens the album', [find((node) => node.type === 'button' && byClass('app-result')(node), rowOf('Roseland NYC Live')).length, text(chipOf('Roseland NYC Live'))], [1, 'Get'])
    const track = (title, position) => ({ title, position, length: 300000 + position, recording: { title, length: 300000 + position, video: false } })
    const PRESSINGS = [
      { id: 'r-vinyl', title: 'Roseland NYC Live', status: 'Official', date: '1998-11-09', country: 'GB', media: [{ format: '12" Vinyl', position: 1, tracks: [track('Humming', 1), track('Cowboys', 2)] }] },
      { id: 'r-cd', title: 'Roseland NYC Live', status: 'Official', date: '1998-11-02', country: 'GB', 'label-info': [{ 'catalog-number': '559 424-2', label: { name: 'Go! Beat' } }], media: [{ format: 'CD', position: 1, tracks: [track('Humming', 1), track('Cowboys', 2)] }] },
    ]
    const tap = () => chipOf('Roseland NYC Live').props.onClick({ currentTarget: { chip: true } })
    tap()
    draw()
    check('a tap asks for the album\'s pressings, the chip busy meanwhile', [asks.pressings.length, asks.pressings[0]?.id, text(chipOf('Roseland NYC Live')), chipOf('Roseland NYC Live').props['aria-busy']],
      [1, ROSELAND.id, 'Get…', true])
    tap()
    check('a second tap calls the first ask off', [asks.pressings.length, asks.pressings[0].signal.aborted], [2, true])
    await settle()
    asks.pressings[1].reject(new Error('MusicBrainz is unreachable right now'))
    await settle()
    draw()
    check('MusicBrainz failing: the album as a whole, said so - nothing opened for the call that was called off',
      [gets.length, gets[0]?.[0].release.release_mbid, gets[0]?.[0].release.tracks.length, gets[0]?.[0].subtitle, gets[0]?.[1]?.chip, text(chipOf('Roseland NYC Live'))],
      [1, null, 0, 'Roseland NYC Live · the album as a whole', true, 'Get'])
    //? two more taps, the first's answer already on its way when the second called it off
    globalThis.__search.abortRejects = false
    tap()
    tap()
    check('a failure isn\'t kept: the next taps ask again, the first of them called off', [asks.pressings.length, asks.pressings[2].signal.aborted], [4, true])
    asks.pressings[3].resolve({ id: ROSELAND.id, releases: PRESSINGS.slice(0, 1), problem: 'MusicBrainz failed part way' })
    await settle()
    check('a list MusicBrainz broke off is the album as a whole - never a short list passing for its pressings',
      [gets.length, gets[1]?.[0].release.release_mbid, gets[1]?.[0].subtitle], [2, null, 'Roseland NYC Live · the album as a whole'])
    tap()
    check('...and isn\'t kept: the next tap asks again', asks.pressings.length, 5)
    asks.pressings[2].resolve({ id: ROSELAND.id, releases: PRESSINGS, problem: null })
    await settle()
    check('the call called off, its answer landing anyway, opens nothing', gets.length, 2)
    asks.pressings[4].resolve({ id: ROSELAND.id, releases: PRESSINGS, problem: null })
    await settle()
    globalThis.__search.abortRejects = true
    check('the usual pressing - a CD over the vinyl - built from the row\'s group', [gets.length, gets[2]?.[0].release.release_mbid, gets[2]?.[0].release.release_group_mbid, gets[2]?.[0].subtitle],
      [3, 'r-cd', ROSELAND.id, 'Roseland NYC Live · CD · 1998 · GB · Go! Beat'])
    tap()
    await settle()
    check('kept for the session: another tap asks nothing, and opens at once', [asks.pressings.length, gets.length, gets[3]?.[0].release.release_mbid], [5, 4, 'r-cd'])

    //? A lookup takes seconds (every pressing with its tracklist, at MusicBrainz's pace); meanwhile
    //? the person opens Now Playing, another tab or a row's page, or types. Its answer landing then
    //? must open nothing - not the sheet over Now Playing, not over another tab (review)
    const GLORY = { id: '00000000-0000-4000-8000-0000000000aa', title: 'Glory Times', 'primary-type': 'Album', 'first-release-date': '1995' }
    find((node) => node.type === 'form')[0].props.onSubmit({ preventDefault() {} })
    draw()
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [THIRD, ROSELAND, GLORY] })
    await settle()
    await answerOwned(holding(DUMMY, THIRD))
    await settle()
    draw()
    check('(a row whose pressings nothing has asked for yet)', !!chipOf('Glory Times'), true)
    globalThis.__search.abortRejects = false
    const opened = gets.length
    const tapGlory = () => chipOf('Glory Times').props.onClick({ currentTarget: { chip: true } })
    tapGlory()
    draw()
    const out = asks.pressings.at(-1)
    check('a tap asks for its pressings, the chip busy', [out.id, text(chipOf('Glory Times'))], [GLORY.id, 'Get…'])
    draw({ active: false })
    draw()
    check('the tab\'s root no longer what shows (Now Playing, another tab, a page over it): the lookup called off, the chip Get again',
      [out.signal.aborted, text(chipOf('Glory Times')), chipOf('Glory Times').props['aria-busy']], [true, 'Get', false])
    //? (an answer MusicBrainz broke off, so it isn't kept and the next tap asks again)
    out.resolve({ id: GLORY.id, releases: PRESSINGS.slice(0, 1), problem: 'MusicBrainz failed part way' })
    await settle()
    check('...and its answer, landing anyway, opens no sheet over what you went to', gets.length, opened)
    draw({ active: true })
    tapGlory()
    draw()
    const typed = asks.pressings.at(-1)
    check('(asked afresh)', typed !== out, true)
    type('portishead live')
    check('the box changed: the lookup called off too, the chip Get again', [typed.signal.aborted, text(chipOf('Glory Times'))], [true, 'Get'])
    typed.resolve({ id: GLORY.id, releases: PRESSINGS, problem: null })
    await settle()
    check('...its answer opening nothing', gets.length, opened)
    type('portishead')
    globalThis.__search.abortRejects = true
  }

  console.log('\na box cut back below three characters')
  type('po')
  check('drops what the longer text found, and says how to ask', [rows().length, text(find(byClass('app-search-empty'), section())[0])],
    [0, 'Type a little more, or press Search, to ask MusicBrainz.'])
  type('portishead')
  await advance(700)
  const out = asks.musicbrainz.at(-1)
  type('po')
  check('...and calls off a search still out for it', out.signal?.aborted, true)
  await settle()
  draw()
  check('...which never draws', rows().length, 0)
  const before = asks.musicbrainz.length
  type('por')
  await advance(700)
  check('the text coming back asks again', [asks.musicbrainz.length - before, asks.musicbrainz.at(-1).query], [1, 'por'])
  asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND] })
  await answerOwned(holding(DUMMY))
  draw()
  //? the trap in the fix: cut back from what WAS asked, then back to it - it must ask again, not
  //? keep an idle half that says nothing because it thinks that text is already answered
  type('po')
  type('por')
  await advance(700)
  check('cut back from what was asked and typed again: asked again', [asks.musicbrainz.length - before, asks.musicbrainz.at(-1).query], [2, 'por'])
  asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND] })
  await answerOwned(holding(DUMMY))
  draw()
  check('...and drawn', rows().map(([title]) => title), ['Roseland NYC Live'])

  console.log('\nan artist and an album that finds nothing is asked again as the words typed')
  type('portishead third')
  await advance(700)
  const fielded = asks.musicbrainz.at(-1)
  check('first as Third by Portishead', fielded.query, 'releasegroup:"third" AND (artist:"Portishead" OR artistname:"Portishead")')
  fielded.resolve({ 'release-groups': [] })
  await settle()
  check('...then, finding nothing, as the words', asks.musicbrainz.at(-1).query, 'portishead third')
  asks.musicbrainz.at(-1).resolve({ 'release-groups': [THIRD] })
  await answerOwned(holding(DUMMY))
  draw()
  check('...and that answer drawn', rows().map(([title]) => title), ['Third'])

  console.log('\nNavidrome failing: the same problem, the same Try again, as MusicBrainz\'s')
  type('zzz')
  await advance(200)
  asks.library.at(-1).reject(new Error('Navidrome answered 500'))
  await settle()
  draw()
  {
    const gate = find((node) => node.type === NeedsNavidrome)[0]
    const problem = find(byClass('app-search-problem'), gate)[0]
    const retry = find((node) => node.type === 'button', problem)[0]
    check('the reason, and a full-width 44px Try again', [text(find((node) => node.type === 'p', problem)[0]), retry?.props.class, text(retry)],
      ['Navidrome answered 500', 'app-button', 'Try again'])
    check('...no bare text button left', find(byClass('pl-text-button')).length, 0)
    const asked = asks.library.length
    retry.props.onClick()
    check('...which asks again', asks.library.length - asked, 1)
  }

  console.log('\nwith Navidrome down, MusicBrainz is still searched')
  draw({ status: { configured: true, ok: false, server: null, problem: 'connection refused' } })
  const libraryAsks = asks.library.length
  type('massive attack')
  await advance(700)
  check('Navidrome not asked, MusicBrainz asked', [asks.library.length - libraryAsks, asks.musicbrainz.at(-1).query], [0, 'massive attack'])

  console.log('\nthe real prefetch (player/api.ts): a scroll calls off a tile\'s ask, never one Search keeps')
  {
    const fetches = []
    globalThis.fetch = (url, init) => new Promise((resolve, reject) => {
      const entry = { url, aborted: false, answer: () => resolve({ ok: true, status: 200, json: async () => ({ id: url.split('/').pop(), song: [] }) }) }
      init?.signal?.addEventListener('abort', () => { entry.aborted = true; const error = new Error('aborted'); error.name = 'AbortError'; reject(error) })
      fetches.push(entry)
    })
    const api = require(path.join(OUT, 'player/api.real.js'))
    const ready = new Set()
    api.prefetchAlbum('kept', true).then((album) => ready.add(album.id), () => {})
    api.prefetchAlbum('kept')
    api.dropPrefetch('kept')
    check('Search\'s kept ask, then a press on its row turned into a scroll: one fetch, not called off', [fetches.length, fetches[0].aborted], [1, false])
    fetches[0].answer()
    await settle()
    check('...and the album reaches Search', ready.has('kept'), true)
    api.prefetchAlbum('pressed')
    api.prefetchAlbum('pressed', true)
    api.dropPrefetch('pressed')
    check('a tile\'s ask that Search then keeps: not called off either', fetches[1].aborted, false)
    api.prefetchAlbum('tile')
    api.dropPrefetch('tile')
    check('a tile\'s own ask is still called off by its scroll', fetches[2].aborted, true)
    const kept = api.prefetchAlbum('page', true)
    check('the album page takes a kept ask once, asking nothing more', [api.album('page') === kept, fetches.length], [true, 4])
    api.album('page')
    check('...and asks afresh after', fetches.length, 5)
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main()
