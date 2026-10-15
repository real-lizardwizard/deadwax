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
 *  - The desktop's search field (2.0.0-player.19, app/searchBox.ts): this box's text is shared for the
 *    sidebar's field to show, typing there is typing here, and its Enter asks both halves at once.
 *  - Songs on MusicBrainz (2.0.0-player.53): asked with the albums, by the same pause and the box read the
 *    same way (an artist alone asks nothing; a fielded read finding nothing asked again as the words typed
 *    taken as ONE title, `recording:"…"` - never free text, and free text never asked twice), one page of 25,
 *    the album half's own request first; drawn in a section of their own above the albums - which never wait
 *    for them (review): the albums are drawn the moment they and the library have answered, and songs landing
 *    after that come folded into the slot that was asking, one height whatever it holds ("Show songs", "No
 *    songs on MusicBrainz for …", the no-release words, More songs for a bare page, or one line with Try
 *    again), so nothing drawn below moves; a search finding no song draws no section unless the albums were
 *    already drawn; every take of a song one row (Dummy held said), a disclosure opening onto Dummy and the
 *    fold, which opens, a second tap closing each and a new answer closing them; a song on no album or EP
 *    listed at once under the fold's words; an album you don't have opening its page with the song's
 *    recordings, one you have the album you have (the id bridge, the row busy, Navidrome not having it or the
 *    bridge failing the album you don't have, a look called off as the box changes); and (second review) a
 *    pressing held that nothing says has the song - Dummy's 1994 CD, its Roads another recording - said as "a
 *    pressing in your library", its tap asking the album's pressings first (busy), the album you have when its
 *    tracklist has the song, the album you don't have when it hasn't or MusicBrainz fails, the answer kept so
 *    the song then reads held and the next tap asks nothing, and called off as the box changes; the library
 *    half playing the song from a pressing held vouching for it, its Navidrome album opened at once; a few
 *    rows, More showing the rest without asking and then the next page by offset, merged in, busy and
 *    refusing a second tap, MusicBrainz away said and asked again, said to VoiceOver, its last page handing
 *    focus on; the albums' Try again and Enter asking the songs nothing more unless they failed too; their own
 *    Try again asking them alone; a new search calling the old one off, and the box cut back emptying them;
 *    the real client's request.
 *  - More from MusicBrainz (2.0.0-player.50): under the rows, a secondary button asking for the same
 *    search's next twelve by offset (the words typed when a fielded read fell back to them), busy and
 *    refusing a second tap meanwhile; the page appended below with every row above as it was, the held
 *    albums left out and a group got twice drawn once, said to VoiceOver; a page all held said so;
 *    MusicBrainz away said, the rows kept and the same page asked again; no button once every answer is
 *    in, and none past the route's bound (said instead); a page still out called off by a new search or
 *    the box cut back, and its answer drawing nothing. After review: two held albums said with their
 *    number; a page of repeats or an empty one said as nothing new, never as albums you have; another
 *    failure's own reason; each page's count heeded, grown or shrunk; and the last page landing with
 *    focus on More handing it to the first row it brought, or to the note in its place.
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
//? ...and the real MusicBrainz client (2.0.0-player.50: the offset it sends)
fs.copyFileSync(path.join(OUT, 'api/musicbrainz.js'), path.join(OUT, 'api/musicbrainz.real.js'))

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
exports.fullySearch = (query, limit, releases, signal, offset) => globalThis.__search.fullySearch(query, limit, releases, signal, offset)
exports.getReleaseGroup = (id, signal) => globalThis.__search.getReleaseGroup(id, signal)
exports.searchSongs = (query, limit, signal, offset) => globalThis.__search.searchSongs(query, limit, signal, offset)
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
fs.writeFileSync(path.join(OUT, 'player/icons.js'), `exports.PlayIcon = function PlayIcon() { return null }\nexports.SearchIcon = function SearchIcon() { return null }\nexports.ChevronDownIcon = function ChevronDownIcon() { return null }\n`)
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

const asks = { owned: [], library: [], musicbrainz: [], prefetch: [], pressings: [], songs: [], order: [] }
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
  fullySearch(query, limit, releases, signal, offset) {
    const d = deferred()
    asks.musicbrainz.push({ query, limit, releases, signal, offset, ...d })
    asks.order.push('albums')
    if (signal) signal.addEventListener('abort', () => { const error = new Error('aborted'); error.name = 'AbortError'; d.reject(error) })
    return d.promise
  },
  prefetchAlbum(id, keep) { const d = deferred(); asks.prefetch.push({ id, keep, ...d }); return d.promise },
  //? the song search (2.0.0-player.53): answered at once with nothing, unless a check takes it in hand
  songsAuto: true,
  searchSongs(query, limit, signal, offset) {
    const d = deferred()
    asks.songs.push({ query, limit, signal, offset, ...d })
    asks.order.push('songs')
    if (signal) signal.addEventListener('abort', () => { const error = new Error('aborted'); error.name = 'AbortError'; d.reject(error) })
    if (globalThis.__search.songsAuto) d.resolve({ recordings: [], count: 0 })
    return d.promise
  },
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
  const songAlbums = []
  const props = { shown: true, active: true, status, onRetry() {}, onOpenAlbum: (album) => opened.push(album), onOpenGroup: (group) => groupsOpened.push(group),
    onOpenSongAlbum: (album, song) => songAlbums.push([album, song]), onGet: (request, opener) => gets.push([request, opener]) }
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

  console.log('\nthe desktop sidebar\'s field is this box (2.0.0-player.19, app/searchBox.ts)')
  {
    const Box = require(path.join(OUT, 'app/searchBox.js'))
    draw({ status })
    check('what the box says is shared, for the sidebar\'s field to show', Box.searchText(), 'massive attack')
    Box.typeSearch('portishead third')
    draw()
    draw()
    check('typing in the sidebar\'s field is typing here', [find((node) => node.type === 'input')[0].props.value, Box.searchText()], ['portishead third', 'portishead third'])
    const libraryBefore = asks.library.length
    const musicBefore = asks.musicbrainz.length
    Box.submitSearch()
    await settle()
    check('...and its Enter asks both halves at once, as this form\'s submit - no pause waited for',
      [asks.library.length - libraryBefore, asks.library.at(-1)?.text, asks.musicbrainz.length - musicBefore], [1, 'portishead third', 1])
  }

  console.log('\nMore from MusicBrainz (2.0.0-player.50): the next page of the same search, appended below')
  {
    const { MusicBrainzUnavailable } = require(path.join(OUT, 'api/http.js'))
    const more = () => find(byClass('app-search-more'), section())[0]
    const notes = () => find(byClass('app-search-more-note'), section()).map(text)
    const said = () => text(find((node) => node.props?.role === 'status' && byClass('app-visually-hidden')(node), section())[0])
    const albums = (from, to) => Array.from({ length: to - from }, (_, n) => ({
      id: `00000000-0000-4000-8000-${String(from + n).padStart(12, '0')}`, title: `Album ${from + n}`, 'primary-type': 'Album' }))
    type('bristol sound')
    await advance(700)
    const first = asks.musicbrainz.at(-1)
    check('(the first page asked as ever: no offset)', [first.query, first.offset], ['bristol sound', undefined])
    first.resolve({ 'release-groups': albums(0, 12), count: 30 })
    await answerOwned(holding(DUMMY))
    draw()
    const listed = find((node) => node.type === 'ul' && byClass('app-results')(node), section())[0]
    check('twelve drawn, and under them More from MusicBrainz - a secondary button, never a row',
      [rows().length, text(more()), more()?.type, more()?.props.class.split(' ').includes('app-button'), more()?.props.class.includes('app-result')], [12, 'More from MusicBrainz', 'button', true, false])
    check('...after the list in the section, with the live region there before any page lands', [!!listed, said()], [true, ''])
    more().props.onClick()
    draw()
    const second = asks.musicbrainz.at(-1)
    check('a tap asks for the same search\'s next twelve, by offset', [asks.musicbrainz.length, second.query, second.limit, second.releases, second.offset],
      [asks.musicbrainz.indexOf(first) + 2, 'bristol sound', 12, false, 12])
    check('...the button busy meanwhile, refusing a tap rather than dropping focus', [text(more()), more().props['aria-busy'], more().props['aria-disabled'], more().props.disabled],
      ['Asking MusicBrainz…', true, true, undefined])
    more().props.onClick()
    check('...a second tap asks nothing', asks.musicbrainz.at(-1) === second, true)
    const above = rows()
    //? one group the first page had already (relevance ties shift), and Dummy, which the library holds
    second.resolve({ 'release-groups': [...albums(11, 12), DUMMY, ...albums(12, 22)], count: 30 })
    await settle()
    draw()
    check('the page appended below: the held album left out, the repeat drawn once - every row above as it was',
      [rows().length, JSON.stringify(rows().slice(0, 12)) === JSON.stringify(above), rows().slice(12).map(([title]) => title)],
      [22, true, albums(12, 22).map((group) => group.title)])
    check('...said to VoiceOver, and the button back', [said(), text(more())], ['10 more albums from MusicBrainz', 'More from MusicBrainz'])
    more().props.onClick()
    draw()
    const third = asks.musicbrainz.at(-1)
    check('the next page starts past every answer got, the held one and the repeat included', third.offset, 24)
    third.reject(new MusicBrainzUnavailable('MusicBrainz is unreachable right now'))
    await settle()
    draw()
    check('MusicBrainz away: said, the rows kept, and the button tries again',
      [notes(), rows().length, text(more())], [["MusicBrainz isn't answering just now - it often goes away for a few minutes."], 22, 'Try again'])
    more().props.onClick()
    draw()
    const retried = asks.musicbrainz.at(-1)
    check('...the same page asked again', [retried !== third, retried.offset], [true, 24])
    retried.resolve({ 'release-groups': albums(22, 28), count: 28 })
    await settle()
    draw()
    check('every answer in: the last rows, and no button any more', [rows().length, more(), notes()], [28, undefined, []])

    //? a page whose albums the library holds every one of
    type('portishead live')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND], count: 2 })
    await answerOwned(holding(DUMMY))
    draw()
    more().props.onClick()
    draw()
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [DUMMY], count: 2 })
    await settle()
    draw()
    check('a page all held: nothing added, and said so - in the page and to VoiceOver', [rows().map(([title]) => title), notes(), said(), more()],
      [['Roseland NYC Live'], ['The next album MusicBrainz found is in your library already.'], 'The next album is in your library already', undefined])

    //? the first page all held: "Everything ... already", and More still offered under it
    type('portishead dummy remaster')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [DUMMY], count: 5 })
    await answerOwned(holding(DUMMY))
    draw()
    check('everything on the first page held: said, and More still offered', [text(find(byClass('app-search-empty'), section())[0]), text(more())],
      ['Everything MusicBrainz found is in your library already.', 'More from MusicBrainz'])

    //? a page out as a new search starts: called off, and its answer draws nothing
    more().props.onClick()
    const out = asks.musicbrainz.at(-1)
    //? (review: only later pages' offsets were pinned) the first page's held album counts too - every
    //? answer got, not the rows drawn, or each page after would start one early, its overlap hidden
    check('...its next page asked from past the held one: the first page\'s every answer counted', out.offset, 1)
    find((node) => node.type === 'form')[0].props.onSubmit({ preventDefault() {} })
    check('a new search calls a page still out off', out.signal.aborted, true)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [THIRD], count: 1 })
    await answerOwned(holding(DUMMY))
    out.resolve({ 'release-groups': albums(40, 45), count: 5 })
    await settle()
    draw()
    check('...only the new search drawn, with nothing more to ask for', [rows().map(([title]) => title), more()], [['Third'], undefined])

    //? the box cut back below three characters: a page out is called off with the rest
    type('massive')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': albums(50, 62), count: 40 })
    await answerOwned(holding(DUMMY))
    draw()
    more().props.onClick()
    const dropped = asks.musicbrainz.at(-1)
    type('ma')
    check('the box cut back: the page out called off too', dropped.signal.aborted, true)

    //? a fielded read that found nothing was asked again as the words typed: More pages THAT search
    type('portishead roseland')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [] })
    await settle()
    asks.musicbrainz.at(-1).resolve({ 'release-groups': albums(70, 82), count: 20 })
    await answerOwned(holding(DUMMY))
    draw()
    more().props.onClick()
    check('a search that fell back to the words typed: its next page is of the words typed', [asks.musicbrainz.at(-1).query, asks.musicbrainz.at(-1).offset], ['portishead roseland', 12])
    asks.musicbrainz.at(-1).resolve({ 'release-groups': albums(82, 90), count: 20 })
    await settle()
    draw()

    //? past the route's bound: narrowing is the way on
    type('various')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': albums(0, 12), count: 50000 })
    await answerOwned(holding(DUMMY))
    draw()
    const before = asks.musicbrainz.length
    let pages = 0
    while (more() && pages < 100) {
      more().props.onClick()
      const page = asks.musicbrainz.at(-1)
      page.resolve({ 'release-groups': albums(1000 + pages * 12, 1012 + pages * 12), count: 50000 })
      await settle()
      draw()
      pages++
    }
    check('a search with tens of thousands of answers pages up to the route\'s bound, never past it - then says to narrow it',
      [asks.musicbrainz.slice(before).every((ask) => ask.offset <= 1000), asks.musicbrainz.at(-1).offset, more(), notes()],
      [true, 996, undefined, ["That's as far into one search as deadwax goes - add a word to narrow it."]])

    //? (review) every new album of a page held, two of them: the number said, in the page and to VoiceOver
    type('portishead held twice')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND], count: 3 })
    await answerOwned(holding(DUMMY, THIRD))
    draw()
    more().props.onClick()
    draw()
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [DUMMY, THIRD], count: 3 })
    await settle()
    draw()
    check('a page of two albums, both held: said with their number - in the page and to VoiceOver', [rows().map(([title]) => title), notes(), said()],
      [['Roseland NYC Live'], ['The next 2 albums MusicBrainz found are all in your library already.'], 'The next 2 albums are all in your library already'])

    //? (review) a page of nothing but rows already drawn, then an empty one: never "in your library"
    type('portishead repeats')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': albums(100, 112), count: 20 })
    await answerOwned(holding(DUMMY))
    draw()
    more().props.onClick()
    draw()
    asks.musicbrainz.at(-1).resolve({ 'release-groups': albums(111, 112), count: 20 })
    await settle()
    draw()
    check('a page of a repeat alone: nothing added, said as nothing new - never as albums you have - and More still offered',
      [rows().length, notes(), said(), text(more())], [12, ['MusicBrainz sent nothing new.'], 'MusicBrainz sent nothing new', 'More from MusicBrainz'])
    more().props.onClick()
    draw()
    asks.musicbrainz.at(-1).resolve({})
    await settle()
    draw()
    check('...then an empty page (MusicBrainz\'s count ran ahead): nothing new said, never "the next 0", and the button gone',
      [rows().length, notes(), said(), more()], [12, ['MusicBrainz sent nothing new.'], 'MusicBrainz sent nothing new', undefined])

    //? (review) a failure that isn't MusicBrainz away: its own reason, and Try again
    type('portishead broken')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': albums(200, 212), count: 40 })
    await answerOwned(holding(DUMMY))
    draw()
    more().props.onClick()
    draw()
    asks.musicbrainz.at(-1).reject(new Error('MusicBrainz answered 502'))
    await settle()
    draw()
    check('a page failing for another reason: that reason said, the rows kept, and Try again', [notes(), rows().length, text(more())], [['MusicBrainz answered 502'], 12, 'Try again'])

    //? (review) each page's own count: a count grown keeps the button, one shrunk ends it
    type('portishead grows')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': albums(300, 312), count: 24 })
    await answerOwned(holding(DUMMY))
    draw()
    more().props.onClick()
    draw()
    asks.musicbrainz.at(-1).resolve({ 'release-groups': albums(312, 324), count: 60 })
    await settle()
    draw()
    check('the next page\'s count grown past the first\'s: the button stays for what more now match', [rows().length, text(more())], [24, 'More from MusicBrainz'])
    type('portishead shrinks')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': albums(400, 412), count: 40 })
    await answerOwned(holding(DUMMY))
    draw()
    more().props.onClick()
    draw()
    asks.musicbrainz.at(-1).resolve({ 'release-groups': albums(412, 424), count: 24 })
    await settle()
    draw()
    check('...shrunk to the answers already got: the button goes, no empty page asked for', [rows().length, more()], [24, undefined])

    //? (review) the last page lands with focus on the button: focus to the first row it brought, or to
    //? the note in the button's place - only when the button had it, and never over focus gone elsewhere
    const focused = []
    const body = { name: 'body' }
    const button = { name: 'More' }
    const note = { focus: () => focused.push('note') }
    const page = (n) => Array.from({ length: n }, (_, at) => ({ focus: () => focused.push(`row ${at}`) }))
    const standIn = (count) => {
      section().props.ref.current = {
        querySelector: (selector) => (selector === '.app-search-more' ? button : selector === '.app-search-more-note' ? note : null),
        querySelectorAll: (selector) => (selector === '.app-result' ? page(count) : []),
      }
    }
    const lastPage = async (title, first, next, focus, count) => {
      type(title)
      await advance(700)
      asks.musicbrainz.at(-1).resolve(first)
      await answerOwned(holding(DUMMY))
      draw()
      more().props.onClick()
      draw()
      globalThis.document = { activeElement: focus, body }
      standIn(count)
      asks.musicbrainz.at(-1).resolve(next)
      await settle()
      //? the button going takes the page's focus with it, as a browser does
      if (globalThis.document.activeElement === button) globalThis.document.activeElement = body
      draw()
    }
    await lastPage('portishead focus', { 'release-groups': albums(500, 512), count: 18 }, { 'release-groups': albums(512, 518), count: 18 }, button, 18)
    check('the last page landing with focus on More: the button gone, focus on the first row the page brought', [more(), focused], [undefined, ['row 12']])
    focused.length = 0
    await lastPage('portishead focus held', { 'release-groups': [ROSELAND], count: 2 }, { 'release-groups': [DUMMY], count: 2 }, button, 1)
    check('...a last page that brought no row: focus on the note said in the button\'s place', [more(), focused], [undefined, ['note']])
    focused.length = 0
    await lastPage('portishead focus tapped', { 'release-groups': albums(520, 532), count: 18 }, { 'release-groups': albums(532, 538), count: 18 }, body, 18)
    check('...More tapped by a finger on WebKit (which focuses nothing): focus left alone, so the page isn\'t scrolled', [more(), focused], [undefined, []])
    await lastPage('portishead focus elsewhere', { 'release-groups': albums(560, 572), count: 18 }, { 'release-groups': albums(572, 578), count: 18 }, { name: 'a Get' }, 18)
    check('...focus moved on from More before the page landed: left where it went', [more(), focused], [undefined, []])
    await lastPage('portishead focus stays', { 'release-groups': albums(540, 552), count: 40 }, { 'release-groups': albums(552, 564), count: 40 }, button, 24)
    check('...a page with more after it: the button stays, and keeps its focus', [text(more()), focused], ['More from MusicBrainz', []])
    delete globalThis.document
    section().props.ref.current = null
  }

  console.log('\nSongs on MusicBrainz (2.0.0-player.53): asked beside the albums, drawn above them')
  {
    const { MusicBrainzUnavailable } = require(path.join(OUT, 'api/http.js'))
    const SONGS = path.resolve(__dirname, '../../tests/fixtures/songs')
    const recorded = (name) => JSON.parse(fs.readFileSync(path.join(SONGS, `${name}.json`), 'utf8'))
    const roads = recorded('roads-portishead'), heyJudeFree = recorded('hey-jude-free'), misery = recorded('miss-misery-elliott-smith')
    const songsSection = () => find((node) => node.type === 'section' && node.props['aria-labelledby'] === 'app-search-songs')[0]
    const songRows = () => find(byClass('app-song-row'), songsSection()).map((row) => [text(find(byClass('app-result-title'), row)[0]), text(find(byClass('app-result-line'), row)[0])])
    const songButton = (n = 0) => find(byClass('app-song-row'), songsSection())[n]
    const albumsOf = (n = 0) => find(byClass('app-song-album'), find(byClass('app-song'), songsSection())[n]).map((row) => [text(find(byClass('app-result-title'), row)[0]), text(find(byClass('app-result-line'), row)[0])])
    const moreSongs = () => find(byClass('app-search-more'), songsSection())[0]
    const said = () => text(find((node) => node.props?.role === 'status' && byClass('app-visually-hidden')(node), songsSection())[0])
    const slot = () => find(byClass('app-song-slot'), songsSection())[0]
    const showSongs = () => find(byClass('app-song-show'), songsSection())[0]
    const listOf = (node) => find((each) => each.props?.id === node.props['aria-controls'])[0]
    //? Dummy's 1994 UK CD, one of the pressings the search found Roads on; and the 20th anniversary reissue, which this
    //? 12-recording fixture doesn't list (at the app's 25 a page it is on the first page - its 1994 XE CD is the one past it)
    const UK_CD = '87888070-1b25-4830-aebc-dee490058b74', REISSUE = 'f5804905-6e8d-45dc-bae9-b36c64ccc99b'
    draw({ status })
    globalThis.__search.songsAuto = false

    const songsBefore = asks.songs.length
    const musicBefore = asks.musicbrainz.length
    type('roads portishead')
    await advance(699)
    check('nothing asked while typing - the album half\'s pause', asks.songs.length - songsBefore, 0)
    await advance(1)
    const ask = asks.songs.at(-1)
    check('asked with the albums, the box read the same way: Roads by Portishead, one page of 25, no offset',
      [asks.songs.length - songsBefore, ask.query, ask.limit, ask.offset, asks.musicbrainz.length - musicBefore, asks.musicbrainz.at(-1).query],
      [1, 'recording:"roads" AND (artist:"Portishead" OR artistname:"Portishead")', 25, undefined, 1, 'releasegroup:"roads" AND (artist:"Portishead" OR artistname:"Portishead")'])
    check('...the album half\'s request first, as it always was - the songs\' after it', asks.order.slice(-2), ['albums', 'songs'])
    draw()
    check('"Asking MusicBrainz…" under "Songs on MusicBrainz", in the slot, before the albums\' section', [text(find((node) => node.type === 'h2', songsSection())[0]),
      text(find(byClass('app-asking'), slot())[0]), songsSection().props['aria-busy'],
      find((node) => node.type === 'section' && /app-search-(songs|musicbrainz)/.test(node.props['aria-labelledby'] ?? '')).map((node) => node.props['aria-labelledby'])],
      ['Songs on MusicBrainz', 'Asking MusicBrainz…', true, ['app-search-songs', 'app-search-musicbrainz']])
    ask.resolve(roads)
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    check('the songs land before the albums: every take of Roads one song, Dummy held (by its group) - drawn at once, the albums still asking',
      [songRows(), slot(), rows().length], [[['Roads', 'Portishead · 4:56 · Dummy · in your library']], undefined, 0])
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND] })
    await settle()
    draw()
    check('...then the albums drawn under them', [songRows().length, rows().map(([title]) => title)], [1, ['Roseland NYC Live']])
    check('...a disclosure, closed', [songButton().props['aria-expanded'], find(byClass('app-song-albums'), songsSection())[0].props.hidden], [false, true])
    songButton().props.onClick()
    draw()
    check('tapped: open, Dummy listed, the rest behind one fold', [songButton().props['aria-expanded'], albumsOf(), text(find(byClass('app-song-fold'), songsSection())[0])],
      [true, [['Dummy', 'Album · 1994 · in your library']], 'On 12 compilations, live albums and broadcasts'])
    const fold = () => find(byClass('app-song-fold'), songsSection())[0]
    check('...the fold closed, its list hidden', [fold().props['aria-expanded'], listOf(fold()).props.hidden], [false, true])
    fold().props.onClick()
    draw()
    check('...opened: every one listed after Dummy, the official ones first, a live take\'s length said', [fold().props['aria-expanded'], albumsOf().length, albumsOf()[2],
      albumsOf().find(([title]) => title === 'Only We')], [true, 13, ['Roseland NYC Live', 'Live album · 2023 · 5:30'], ['Only We', 'Live album · Bootleg · 1997 · 5:36']])
    //? (review) a second tap closes each again - "Tap the song again to close it"
    fold().props.onClick()
    draw()
    check('...the fold tapped again: closed, its list hidden', [fold().props['aria-expanded'], listOf(fold()).props.hidden], [false, true])
    songButton().props.onClick()
    draw()
    check('...the song tapped again: closed, its albums hidden', [songButton().props['aria-expanded'], listOf(songButton()).props.hidden], [false, true])
    songButton().props.onClick()
    draw()
    fold().props.onClick()
    draw()
    check('...and opened again: the song and its fold as they were', [songButton().props['aria-expanded'], fold().props['aria-expanded']], [true, true])

    //? an album you don't have: the album page, with the song's recordings on it; one you have: the album you have
    const row = (title) => find(byClass('app-song-album'), songsSection()).find((node) => text(find(byClass('app-result-title'), node)[0]) === title)
    row('Roseland NYC Live').props.onClick()
    check('an album you don\'t have opens on its page, with the song\'s recordings on it', songAlbums.at(-1),
      [{ id: 'ce61f4a8-db95-3608-93de-53f9ecb1b8d2', title: 'Roseland NYC Live' }, ['63f3cb71-10d1-40a3-91f6-b682cf47c85b']])
    row('Dummy').props.onClick()
    check('...and one held by its group alone, with no release to ask the id bridge about: its page too, as a held row opens', songAlbums.at(-1)[0].title, 'Dummy')
    const fetches = []
    const fetchBefore = globalThis.fetch
    globalThis.fetch = (url, init) => new Promise((resolve, reject) => {
      fetches.push({ url, answer: (body) => resolve({ ok: true, status: 200, json: async () => body }),
        fail: () => resolve({ ok: false, status: 500, json: async () => ({ detail: 'deadwax had a problem' }) }) })
      init?.signal?.addEventListener('abort', () => { const error = new Error('aborted'); error.name = 'AbortError'; reject(error) })
    })
    //? the library holding a release of Dummy the song is on: the album you have
    void Owned.refreshOwned()
    await answerOwned({ albums: [{ path: 'Portishead/Dummy', artist: 'Portishead', album: 'Dummy', release_group_mbid: DUMMY.id, release_mbid: UK_CD }] })
    draw()
    row('Dummy').props.onClick()
    draw()
    check('one you have: the id bridge asked about the release you hold, the row busy meanwhile', [fetches.length, fetches[0]?.url.includes(`release_mbid=${UK_CD}`), row('Dummy').props['aria-busy']],
      [1, true, true])
    fetches[0].answer({ navidrome_id: 'nd-dummy' })
    await settle()
    draw()
    check('...then the album you have, credited', [opened.at(-1), row('Dummy').props['aria-busy']], [{ id: 'nd-dummy', name: 'Dummy', artist: 'Portishead' }, false])
    //? (review) Navidrome not having found it yet, or the bridge failing: the album you don't have, never nothing
    const opensNow = songAlbums.length
    row('Dummy').props.onClick()
    fetches.at(-1).answer({ navidrome_id: null })
    await settle()
    draw()
    check('...Navidrome hasn\'t found it: the album you don\'t have, with the song\'s recordings, the row no longer busy',
      [songAlbums.length - opensNow, songAlbums.at(-1)[0].title, songAlbums.at(-1)[1], row('Dummy').props['aria-busy']], [1, 'Dummy', ['ef37de8d-8fab-42ed-82da-fbfe25715989'], false])
    row('Dummy').props.onClick()
    fetches.at(-1).fail()
    await settle()
    draw()
    check('...the bridge failing: the same', [songAlbums.length - opensNow, songAlbums.at(-1)[0].title, row('Dummy').props['aria-busy']], [2, 'Dummy', false])
    row('Dummy').props.onClick()
    type('roads portishead!')
    await settle()
    check('...a look still out called off as the box changes - it opens nothing', [opened.at(-1).id, songAlbums.length - opensNow, fetches.length], ['nd-dummy', 2, 4])

    //? (second review) a pressing of Dummy the search didn't find Roads on - its 1994 CD, the most common pressing, whose
    //? Roads is another recording (8a49dba0), only on the real search's second page: "a pressing in your library" - never
    //? the song, nor its absence - and its tap finds out from the album's pressings before it opens either page. (The
    //? library half's answer on hand, for "portishead", names no artist: it vouches for nothing.)
    const CD_1994 = '76df3287-6cda-33eb-8e9a-044b5e15ffdd'
    const roadsOn = (id, recording, title = 'Roads') => ({ id, title: 'Dummy', status: 'Official', date: '1994-08-22',
      media: [{ format: 'CD', position: 1, tracks: [{ number: '8', position: 8, title, length: 302000, recording: { id: recording, title } }] }] })
    void Owned.refreshOwned()
    await answerOwned({ albums: [{ path: 'Portishead/Dummy (1994)', artist: 'Portishead', album: 'Dummy', release_group_mbid: DUMMY.id, release_mbid: CD_1994 }] })
    draw()
    const opensBefore = songAlbums.length, openedBefore = opened.length, pressingAsks = asks.pressings.length, bridgeAsks = fetches.length
    check('a pressing held that nothing says has the song: the row claims nothing, Dummy\'s line says "a pressing in your library"', [songRows()[0][1], albumsOf()[0][1]],
      ['Portishead · 4:56 · Dummy', 'Album · 1994 · a pressing in your library'])
    row('Dummy').props.onClick()
    draw()
    check('...its tap asks for the album\'s pressings first, the row busy - nothing opened yet, the id bridge asked nothing',
      [asks.pressings.length - pressingAsks, asks.pressings.at(-1).id, row('Dummy').props['aria-busy'], songAlbums.length - opensBefore, opened.length - openedBefore, fetches.length - bridgeAsks],
      [1, DUMMY.id, true, 0, 0, 0])
    asks.pressings.at(-1).resolve({ id: DUMMY.id, problem: null, releases: [roadsOn(UK_CD, 'ef37de8d-8fab-42ed-82da-fbfe25715989'), roadsOn(CD_1994, '8a49dba0-253a-4535-b87f-78bb035336ce')] })
    await settle()
    draw()
    check('...the 1994 CD\'s tracklist has Roads (another recording, known by its title): the id bridge asked about THAT CD, the row still busy',
      [fetches.length - bridgeAsks, fetches.at(-1).url.includes(`release_mbid=${CD_1994}`), row('Dummy').props['aria-busy'], songAlbums.length - opensBefore], [1, true, true, 0])
    fetches.at(-1).answer({ navidrome_id: 'nd-dummy-94' })
    await settle()
    draw()
    check('...then the album you have - never the album you don\'t', [opened.at(-1), songAlbums.length - opensBefore, row('Dummy').props['aria-busy']],
      [{ id: 'nd-dummy-94', name: 'Dummy', artist: 'Portishead' }, 0, false])
    check('...its pressings kept, so the song now reads held: the row and Dummy\'s line', [songRows()[0][1], albumsOf()[0][1]],
      ['Portishead · 4:56 · Dummy · in your library', 'Album · 1994 · in your library'])
    row('Dummy').props.onClick()
    check('...a second tap asks no pressings - the bridge at once', [asks.pressings.length - pressingAsks, fetches.length - bridgeAsks, fetches.at(-1).url.includes(`release_mbid=${CD_1994}`)], [1, 2, true])
    fetches.at(-1).answer({ navidrome_id: 'nd-dummy-94' })
    await settle()

    //? ...the library half (Navidrome's search3, for the same words) playing Roads from a Dummy held: the song held, that
    //? album of Navidrome's opened at once - Dummy's 20th anniversary reissue held, which the kept pressings don't list
    const libraryAsk = asks.library.at(-1)
    check('(the library half\'s ask for these words, still out)', libraryAsk.text, 'roads portishead')
    libraryAsk.resolve({ artists: [], albums: [], songs: [{ id: 'nd-s-roads', title: 'Roads', artist: 'Portishead', album: 'Dummy', albumId: 'nd-dummy-20', coverArt: 'al-20' }] })
    await settle()
    void Owned.refreshOwned()
    await answerOwned({ albums: [{ path: 'Portishead/Dummy [20th Anniversary]', artist: 'Portishead', album: 'Dummy', release_group_mbid: DUMMY.id, release_mbid: REISSUE }] })
    draw()
    check('the library half playing Roads from a Dummy held: the row and Dummy\'s line say "in your library"', [songRows()[0][1], albumsOf()[0][1]],
      ['Portishead · 4:56 · Dummy · in your library', 'Album · 1994 · in your library'])
    const quick = [asks.pressings.length, fetches.length]
    row('Dummy').props.onClick()
    check('...and its tap opens that album at once - no pressings asked, no bridge', [opened.at(-1), asks.pressings.length - quick[0], fetches.length - quick[1]],
      [{ id: 'nd-dummy-20', name: 'Dummy', artist: 'Portishead' }, 0, 0])

    //? ...and a pressing WITHOUT the song: a Roseland NYC Live held that isn't one the song was found on
    const ROSELAND_SONG = 'ce61f4a8-db95-3608-93de-53f9ecb1b8d2', ROSELAND_HELD = 'eeeeeeee-0000-4000-8000-000000000001'
    const roseland = (id, recording, title = 'Roads') => ({ ...roadsOn(id, recording, title), title: 'Roseland NYC Live' })
    const roselandPressings = { id: ROSELAND_SONG, problem: null, releases: [roseland('450d91d8-13e5-4d4d-acd5-166ce9b7edd0', '63f3cb71-10d1-40a3-91f6-b682cf47c85b'),
      roseland(ROSELAND_HELD, '99999999-0000-4000-8000-000000000009', 'Humming')] }
    void Owned.refreshOwned()
    await answerOwned({ albums: [{ path: 'Portishead/Roseland NYC Live (DVD)', artist: 'Portishead', album: 'Roseland NYC Live', release_group_mbid: ROSELAND_SONG, release_mbid: ROSELAND_HELD }] })
    draw()
    check('a Roseland NYC Live held that nothing says has Roads: its line says "a pressing in your library"', albumsOf().find(([title]) => title === 'Roseland NYC Live')[1],
      'Live album · 2023 · 5:30 · a pressing in your library')
    const roselandOpens = songAlbums.length, roselandBridge = fetches.length
    row('Roseland NYC Live').props.onClick()
    asks.pressings.at(-1).reject(new MusicBrainzUnavailable('MusicBrainz is unreachable right now'))
    await settle()
    draw()
    check('...MusicBrainz failing to list its pressings: the album you don\'t have, with the song\'s recordings - the row no longer busy',
      [asks.pressings.at(-1).id, songAlbums.length - roselandOpens, songAlbums.at(-1), row('Roseland NYC Live').props['aria-busy']],
      [ROSELAND_SONG, 1, [{ id: ROSELAND_SONG, title: 'Roseland NYC Live' }, ['63f3cb71-10d1-40a3-91f6-b682cf47c85b']], false])
    const roselandAsks = asks.pressings.length
    row('Roseland NYC Live').props.onClick()
    check('...a failure isn\'t kept: the next tap asks again', asks.pressings.length - roselandAsks, 1)
    asks.pressings.at(-1).resolve(roselandPressings)
    await settle()
    draw()
    check('...the pressing held hasn\'t Roads: the album you don\'t have, on a pressing with it - the id bridge asked nothing',
      [songAlbums.length - roselandOpens, songAlbums.at(-1)[0].title, fetches.length - roselandBridge, row('Roseland NYC Live').props['aria-busy']], [2, 'Roseland NYC Live', 0, false])
    check('...still only "a pressing", now its pressings are kept', albumsOf().find(([title]) => title === 'Roseland NYC Live')[1], 'Live album · 2023 · 5:30 · a pressing in your library')
    row('Roseland NYC Live').props.onClick()
    check('...and kept: the next tap asks nothing, and opens at once', [asks.pressings.length - roselandAsks, songAlbums.length - roselandOpens], [1, 3])
    //? a look at the pressings still out, the box changing: called off, opening nothing
    const ONLY_WE = '5c6c3376-856f-4cc7-8c9f-87613eb07d41'
    void Owned.refreshOwned()
    await answerOwned({ albums: [{ path: 'Portishead/Only We', artist: 'Portishead', album: 'Only We', release_group_mbid: ONLY_WE, release_mbid: 'eeeeeeee-0000-4000-8000-000000000002' }] })
    draw()
    const onlyWeOpens = [songAlbums.length, opened.length]
    row('Only We').props.onClick()
    const look = asks.pressings.at(-1)
    check('(asked for Only We\'s pressings)', look.id, ONLY_WE)
    type('roads portishead!!')
    await settle()
    check('...called off as the box changes - the row no longer busy, nothing opened', [look.signal.aborted, row('Only We').props['aria-busy'], songAlbums.length - onlyWeOpens[0], opened.length - onlyWeOpens[1]],
      [true, false, 0, 0])
    //? ...and its answer already on its way when the box changed: it lands, and still opens nothing - nor asks the bridge
    globalThis.__search.abortRejects = false
    row('Only We').props.onClick()
    const late = asks.pressings.at(-1), lateBridge = fetches.length
    type('roads portishead!!!')
    late.resolve({ id: ONLY_WE, problem: null, releases: [roadsOn('eeeeeeee-0000-4000-8000-000000000002', 'ef5f969b-5a0e-4397-a220-ab4adf84cbb6')] })
    await settle()
    globalThis.__search.abortRejects = true
    check('...an answer landing after the box changed opens nothing, and asks the bridge nothing', [late !== look, songAlbums.length - onlyWeOpens[0], opened.length - onlyWeOpens[1], fetches.length - lateBridge],
      [true, 0, 0, 0])
    //? ...a list MusicBrainz broke off part way: never kept (the next tap asks again) - but what it does show still counts
    const brokeAsks = asks.pressings.length, brokeBridge = fetches.length
    row('Only We').props.onClick()
    asks.pressings.at(-1).resolve({ id: ONLY_WE, problem: 'MusicBrainz failed part way', releases: [roadsOn('eeeeeeee-0000-4000-8000-000000000002', 'ef5f969b-5a0e-4397-a220-ab4adf84cbb6')] })
    await settle()
    check('...a list broken off part way, showing the pressing held with the song: the bridge asked about it all the same',
      [asks.pressings.length - brokeAsks, fetches.length - brokeBridge, fetches.at(-1).url.includes('release_mbid=eeeeeeee-0000-4000-8000-000000000002')], [1, 1, true])
    fetches.at(-1).answer({ navidrome_id: 'nd-only-we' })
    await settle()
    check('...the album you have opened', opened.at(-1)?.id, 'nd-only-we')
    row('Only We').props.onClick()
    check('...and that list not kept: the next tap asks again', asks.pressings.length - brokeAsks, 2)
    asks.pressings.at(-1).reject(new MusicBrainzUnavailable('MusicBrainz is unreachable right now'))
    await settle()
    globalThis.fetch = fetchBefore
    void Owned.refreshOwned()
    await answerOwned(holding(DUMMY))

    //? the album half's Try again, and Enter on the same words, ask the songs nothing more
    type('portishead roads')
    await advance(700)
    asks.songs.at(-1).resolve(roads)
    asks.musicbrainz.at(-1).reject(new MusicBrainzUnavailable('MusicBrainz is unreachable right now'))
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    //? (review) a new answer closes every song, the one open before among them
    check('a new answer: its songs closed, whatever was open before (Roads and its fold were)', [songButton().props['aria-expanded'], listOf(songButton()).props.hidden], [false, true])
    songButton().props.onClick()
    draw()
    check('...its fold too, the song opened again', [songButton().props['aria-expanded'], fold().props['aria-expanded'], listOf(fold()).props.hidden], [true, false, true])
    const songAsks = asks.songs.length
    find((node) => node.type === 'button' && text(node) === 'Try again', section())[0].props.onClick()
    find((node) => node.type === 'form')[0].props.onSubmit({ preventDefault() {} })
    check('the albums\' Try again, and Enter on the same words, ask the songs nothing more', asks.songs.length - songAsks, 0)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND] })
    await answerOwned(holding(DUMMY))
    draw()
    //? (review) ...unless the songs failed too: then the albums' Try again asks them again
    type('glory box portishead')
    await advance(700)
    asks.songs.at(-1).reject(new MusicBrainzUnavailable('MusicBrainz is unreachable right now'))
    asks.musicbrainz.at(-1).reject(new MusicBrainzUnavailable('MusicBrainz is unreachable right now'))
    await settle()
    draw()
    const bothFailed = asks.songs.length
    find((node) => node.type === 'button' && text(node) === 'Try again', section())[0].props.onClick()
    check('both halves failing: the albums\' Try again asks the songs again too', [asks.songs.length - bothFailed, asks.songs.at(-1).query],
      [1, 'recording:"glory box" AND (artist:"Portishead" OR artistname:"Portishead")'])
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    await settle()
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [] })
    await answerOwned(holding(DUMMY))
    draw()

    console.log('\n...a few at first, More shows the rest, then asks for the next page')
    type('hey jude')
    await advance(700)
    check('words with no artist you have: asked as typed', asks.songs.at(-1).query, 'hey jude')
    asks.songs.at(-1).resolve(heyJudeFree)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [] })
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    check('eleven songs (each artist\'s cover its own), three shown, then More songs', [songRows().length, text(moreSongs())], [3, 'More songs'])
    const page2 = asks.songs.length
    moreSongs().props.onClick()
    draw()
    check('More shows the songs in hand first - nothing asked - and says how many', [songRows().length, asks.songs.length - page2, said()], [11, 0, '8 more songs'])
    check('...the button still there: MusicBrainz counts more', text(moreSongs()), 'More songs')
    moreSongs().props.onClick()
    draw()
    const next = asks.songs.at(-1)
    check('then the next page of the same search, from every recording got (12), busy meanwhile - a second tap refused',
      [next.query, next.offset, text(moreSongs()), moreSongs().props['aria-busy'], moreSongs().props['aria-disabled'], moreSongs().props.disabled], ['hey jude', 12, 'Asking MusicBrainz…', true, true, undefined])
    moreSongs().props.onClick()
    check('...', asks.songs.length - page2, 1)
    next.reject(new MusicBrainzUnavailable('MusicBrainz is unreachable right now'))
    await settle()
    draw()
    check('MusicBrainz away: said, the songs kept, Try again asks the same page', [text(find(byClass('app-search-more-note'), songsSection())[0]), songRows().length, text(moreSongs())],
      ["MusicBrainz isn't answering just now - it often goes away for a few minutes.", 11, 'Try again'])
    moreSongs().props.onClick()
    check('...', asks.songs.at(-1).offset, 12)
    const covers = [...heyJudeFree.recordings.slice(0, 2).map((r) => ({ ...r, id: `again-${r.id}` })), { ...heyJudeFree.recordings[3], id: 'new-1', 'artist-credit': [{ name: 'Somebody New', artist: { id: 'nobody' } }] }]
    asks.songs.at(-1).resolve({ recordings: covers, count: 15 })
    await settle()
    draw()
    check('a page merged in: takes of songs drawn add albums in place, a new song comes after - every row above as it was',
      [songRows().length, songRows()[0], songRows().at(-1)[1].startsWith('Somebody New'), said()],
      [12, ['Hey Jude (Hey Jude)', 'The Beatles Revival Band · 6:29 · Ein Flug in die DDR'], true, '1 more song from MusicBrainz'])
    check('...every answer in (15 of 15): no button', moreSongs(), undefined)

    console.log('\n...a song on no album or EP: its albums listed at once, under the fold\'s words')
    type('miss misery')
    await advance(700)
    asks.songs.at(-1).resolve(misery)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [] })
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    songButton().props.onClick()
    draw()
    check('no fold to open: the words as a caption, all eleven listed', [find(byClass('app-song-fold'), songsSection()).length, text(find(byClass('app-song-caption'), songsSection())[0]), albumsOf().length],
      [0, 'On 11 compilations, live albums and soundtracks', 11])

    console.log('\n...only the newest answer, and the album half\'s rules')
    type('roads portishead')
    await advance(700)
    const old = asks.songs.at(-1)
    type('glory box portishead')
    await advance(700)
    check('a new search calls the old one off', old.signal.aborted, true)
    old.resolve(roads)
    await settle()
    draw()
    check('...whose answer never draws', text(find(byClass('app-asking'), songsSection())[0]), 'Asking MusicBrainz…')
    const glory = asks.songs.at(-1)
    type('gl')
    check('the box cut back below three characters: the songs called off, and gone', [glory.signal.aborted, songsSection()], [true, undefined])
    type('portishead')
    await advance(700)
    draw()
    check('an artist\'s name alone: no songs asked, no songs section', [asks.songs.at(-1) === glory, songsSection()], [true, undefined])
    //? (review) the same words again after the box was cut back: asked again, never "already answered" with nothing drawn
    type('roads portishead')
    await advance(700)
    asks.songs.at(-1).resolve(roads)
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    const retyped = asks.songs.length
    type('ro')
    type('roads portishead')
    await advance(700)
    check('cut back and typed again: the songs asked again', asks.songs.length - retyped, 1)
    asks.songs.at(-1).resolve(roads)
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    check('...and drawn again', songRows().map(([title]) => title), ['Roads'])

    //? (review) a title beside an artist that finds no song: asked again as the words typed AS ONE TITLE - not the
    //? words loose, which matched strangers' songs titled after the artist above an album's words
    type('the slow rush portishead')
    await advance(700)
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    await settle()
    check('a title beside an artist that finds nothing: asked again as the words typed, as one title', asks.songs.at(-1).query, 'recording:"the slow rush portishead"')
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    check('...finding nothing either, before the albums are drawn: no section - the albums answer for the words', songsSection(), undefined)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [] })
    await settle()
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [] })
    await settle()
    draw()
    check('...nor after', [songsSection(), text(find(byClass('app-search-empty'), section())[0])], [undefined, 'Nothing on MusicBrainz for “the slow rush portishead”.'])
    const freeBefore = asks.songs.length
    type('zzyzx qwerty')
    await advance(700)
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    check('words with no artist you have, finding nothing: asked once - the same words aren\'t asked twice - and no section', [asks.songs.length - freeBefore, songsSection()], [1, undefined])
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [] })
    await answerOwned(holding(DUMMY))

    //? (review) recordings found, none of them on a release: said so - not "No songs" - and More when MusicBrainz counts more
    const bare = (n) => Array.from({ length: n }, (_, at) => ({ id: `bare-${at}`, title: `Roads (take ${at})`, 'artist-credit': [{ name: 'Portishead', artist: { id: 'P' } }], releases: [] }))
    const bareBefore = asks.songs.length
    type('roads remix portishead')
    await advance(700)
    asks.songs.at(-1).resolve({ recordings: bare(25), count: 40 })
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    check('a page of recordings on no release: said, no fallback asked, and More for the next page',
      [asks.songs.length - bareBefore, text(find(byClass('app-search-empty'), songsSection())[0]), songRows().length, text(moreSongs())],
      [1, 'MusicBrainz has songs for “roads remix portishead”, but on no release yet - nothing to get.', 0, 'More songs'])
    moreSongs().props.onClick()
    check('...which asks the next page', asks.songs.at(-1).offset, 25)
    asks.songs.at(-1).resolve({ recordings: roads.recordings.slice(3, 4), count: 40 })
    await settle()
    draw()
    check('...whose song is drawn', songRows().map(([title]) => title), ['Roads'])
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [] })
    await answerOwned(holding(DUMMY))

    type('only you portishead')
    await advance(700)
    asks.songs.at(-1).reject(new MusicBrainzUnavailable('MusicBrainz is unreachable right now'))
    await settle()
    draw()
    const albumAsks = asks.musicbrainz.length
    check('the songs failing: said, with their own Try again', [text(find(byClass('app-search-empty'), songsSection())[0]), text(find((node) => node.type === 'button', find(byClass('app-search-problem'), songsSection())[0])[0])],
      ["MusicBrainz isn't answering just now - it often goes away for a few minutes.", 'Try again'])
    find((node) => node.type === 'button', find(byClass('app-search-problem'), songsSection())[0])[0].props.onClick()
    check('...which asks the songs again, not the albums', [asks.songs.at(-1).query, asks.musicbrainz.length - albumAsks], ['recording:"only you" AND (artist:"Portishead" OR artistname:"Portishead")', 0])
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    await settle()
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    await settle()
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [] })
    await answerOwned(holding(DUMMY))

    console.log('\n...the songs slower than the albums: the albums drawn as they always were, the songs folded in the slot')
    type('sour times portishead')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND] })
    await answerOwned(holding(DUMMY))
    draw()
    check('the albums drawn the moment they and the library have answered - never waiting for the songs (review)', [rows().length, text(find(byClass('app-asking'), slot())[0])], [1, 'Asking MusicBrainz…'])
    asks.songs.at(-1).resolve(roads)
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    check('...the songs landing after them: folded into the slot - "Show songs", no rows - so nothing drawn below moves', [songRows().length, text(showSongs()), !!slot(), said()],
      [0, 'Show songs', true, '1 song on MusicBrainz - Show songs to see them'])
    showSongs().props.onClick()
    draw()
    check('...shown at a tap: the songs, the slot gone', [songRows().map(([title]) => title), slot()], [['Roads'], undefined])
    type('hey jude late')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND] })
    await answerOwned(holding(DUMMY))
    draw()
    asks.songs.at(-1).resolve(heyJudeFree)
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    showSongs().props.onClick()
    draw()
    check('...a few of them, as a search drawn at once shows, More for the rest', [songRows().length, text(moreSongs())], [3, 'More songs'])
    type('teardrop portishead')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND] })
    await answerOwned(holding(DUMMY))
    draw()
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    await settle()
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    check('...finding nothing, after the albums: said in the slot, which stays', [!!slot(), text(find(byClass('app-search-empty'), slot())[0])],
      [true, 'No songs on MusicBrainz for “teardrop portishead”.'])
    type('wandering star portishead')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND] })
    await answerOwned(holding(DUMMY))
    draw()
    asks.songs.at(-1).reject(new MusicBrainzUnavailable('MusicBrainz is unreachable right now'))
    await settle()
    draw()
    const lateRow = () => find(byClass('is-row'), songsSection())[0]
    check('...failing after the albums: said in the slot, with a Try again of its own', [text(find(byClass('app-search-empty'), lateRow())[0]), text(find((node) => node.type === 'button', lateRow())[0])],
      ["MusicBrainz isn't answering.", 'Try again'])
    const lateAsks = asks.songs.length
    find((node) => node.type === 'button', lateRow())[0].props.onClick()
    asks.songs.at(-1).resolve(roads)
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    check('...which asks them again - asked for, they open at once', [asks.songs.length - lateAsks, songRows().map(([title]) => title), slot()], [1, ['Roads'], undefined])
    type('roads take portishead')
    await advance(700)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND] })
    await answerOwned(holding(DUMMY))
    draw()
    asks.songs.at(-1).resolve({ recordings: bare(25), count: 40 })
    await settle()
    await answerOwned(holding(DUMMY))
    draw()
    check('...a late page on no release with more to come: More songs in the slot', [text(showSongs()), songRows().length], ['More songs', 0])
    showSongs().props.onClick()
    asks.songs.at(-1).resolve({ recordings: roads.recordings.slice(3, 4), count: 40 })
    await settle()
    draw()
    check('...which asks the next page and opens', [asks.songs.at(-1).offset, songRows().map(([title]) => title), slot()], [25, ['Roads'], undefined])

    console.log('\n...focus handed on as More songs, or Show songs, goes')
    {
      const focused = []
      const body = { name: 'body' }
      const button = { name: 'More songs' }
      const show = { name: 'Show songs' }
      const note = { focus: () => focused.push('note') }
      //? the section as the browser would have it, its song rows as many as are drawn
      const standIn = () => {
        songsSection().props.ref.current = {
          querySelector: (selector) => (selector === '.app-search-more' ? button : selector === '.app-song-show' ? show : selector === '.app-search-more-note' ? note
            : selector === '.app-song-row' ? { focus: () => focused.push('song 0') } : null),
          querySelectorAll: (selector) => (selector === '.app-song-row' ? Array.from({ length: songRows().length }, (_, at) => ({ focus: () => focused.push(`song ${at}`) })) : []),
        }
      }
      type('hey jude!')
      await advance(700)
      asks.songs.at(-1).resolve({ ...heyJudeFree, count: 12 })
      asks.musicbrainz.at(-1).resolve({ 'release-groups': [] })
      await settle()
      await answerOwned(holding(DUMMY))
      draw()
      standIn()
      globalThis.document = { activeElement: button, body }
      moreSongs().props.onClick()
      if (globalThis.document.activeElement === button) globalThis.document.activeElement = body
      draw()
      check('the songs in hand shown, the last of them: focus to the first song it showed', [moreSongs(), focused], [undefined, ['song 3']])
      focused.length = 0
      type('hey jude?')
      await advance(700)
      asks.songs.at(-1).resolve({ recordings: heyJudeFree.recordings.slice(0, 2), count: 4 })
      asks.musicbrainz.at(-1).resolve({ 'release-groups': [] })
      await settle()
      await answerOwned(holding(DUMMY))
      draw()
      standIn()
      globalThis.document = { activeElement: button, body }
      moreSongs().props.onClick()
      draw()
      //? the same two songs again, each on an album of its own: only albums - no new song
      const elsewhere = (r) => ({ ...r, id: `${r.id}-again`, releases: r.releases.map((release) => ({ ...release, id: `${release.id}-2`, 'release-group': { ...release['release-group'], id: `${release['release-group'].id}-2` } })) })
      asks.songs.at(-1).resolve({ recordings: heyJudeFree.recordings.slice(0, 2).map(elsewhere), count: 4 })
      await settle()
      if (globalThis.document.activeElement === button) globalThis.document.activeElement = body
      draw()
      check('a last page that brought only albums: focus to the note said in the button\'s place', [moreSongs(), focused, text(find(byClass('app-search-more-note'), songsSection())[0])],
        [undefined, ['note'], 'No new songs - 2 more albums for the songs above.'])
      focused.length = 0
      //? (review) a song whose take on the first page was on no release, back on the last page: after the song drawn - and focus to IT
      const free = recorded('roads-portishead-free').recordings
      type('breathe roads!')
      await advance(700)
      asks.songs.at(-1).resolve({ recordings: [free[4], free[0]], count: 3 })
      asks.musicbrainz.at(-1).resolve({ 'release-groups': [] })
      await settle()
      await answerOwned(holding(DUMMY))
      draw()
      standIn()
      globalThis.document = { activeElement: button, body }
      moreSongs().props.onClick()
      draw()
      asks.songs.at(-1).resolve({ recordings: [free[3]], count: 3 })
      await settle()
      if (globalThis.document.activeElement === button) globalThis.document.activeElement = body
      draw()
      check('...a song first seen bare, back on the last page: after the one drawn, and focus to it', [songRows().map(([, line]) => line.split(' · ')[0]), focused], [['The Last Embrace', 'DJ Tripp'], ['song 1']])
      focused.length = 0
      type('glory box portishead!')
      await advance(700)
      asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND] })
      await answerOwned(holding(DUMMY))
      draw()
      asks.songs.at(-1).resolve({ recordings: [], count: 0 })
      await settle()
      asks.songs.at(-1).resolve(roads)
      await settle()
      await answerOwned(holding(DUMMY))
      draw()
      standIn()
      globalThis.document = { activeElement: show, body }
      showSongs().props.onClick()
      if (globalThis.document.activeElement === show) globalThis.document.activeElement = body
      draw()
      check('"Show songs" tapped from the keyboard: focus to the first song as the button goes', focused, ['song 0'])
      focused.length = 0
      type('glory box portishead?')
      await advance(700)
      asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND] })
      await answerOwned(holding(DUMMY))
      draw()
      asks.songs.at(-1).resolve(roads)
      await settle()
      await answerOwned(holding(DUMMY))
      draw()
      standIn()
      globalThis.document = { activeElement: body, body }
      showSongs().props.onClick()
      draw()
      check('...tapped by a finger (WebKit focuses nothing): focus left alone', focused, [])
      delete globalThis.document
      songsSection().props.ref.current = null
    }

    console.log('\n...as far into one search as deadwax goes')
    {
      type('roads portishead far')
      await advance(700)
      const take = (n) => ({ ...roads.recordings[3], id: `far-${n}` })
      asks.songs.at(-1).resolve({ recordings: Array.from({ length: 25 }, (_, at) => take(at)), count: 5000 })
      asks.musicbrainz.at(-1).resolve({ 'release-groups': [] })
      await settle()
      await answerOwned(holding(DUMMY))
      draw()
      let pages = 1
      while (moreSongs() && pages < 50) {
        moreSongs().props.onClick()
        asks.songs.at(-1).resolve({ recordings: Array.from({ length: 25 }, (_, at) => take(pages * 25 + at)), count: 5000 })
        await settle()
        draw()
        pages++
      }
      check('More songs up to the route\'s bound (1,000 answers in), then said instead', [asks.songs.at(-1).offset, moreSongs(), text(find(byClass('app-search-more-note'), songsSection()).at(-1))],
        [1000, undefined, "That's as far into one search as deadwax goes - add a word to narrow it."])
    }
    globalThis.__search.songsAuto = true
  }

  console.log('\nthe real MusicBrainz client (api/musicbrainz.ts): an offset sent only past the first page')
  {
    const urls = []
    const fetchBefore = globalThis.fetch
    globalThis.fetch = (url) => { urls.push(url); return Promise.resolve({ ok: true, status: 200, json: async () => ({}) }) }
    const MB = require(path.join(OUT, 'api/musicbrainz.real.js'))
    await MB.fullySearch('artist:"Portishead"', 12, false)
    await MB.fullySearch('artist:"Portishead"', 12, false, undefined, 0)
    await MB.fullySearch('artist:"Portishead"', 12, false, undefined, 24)
    const query = (url) => Object.fromEntries(new URL(url, 'http://deadwax.test').searchParams)
    check('the first page asked as it always was - no offset, so the same request and cache entry; a later page by its offset',
      urls.map(query), [{ query: 'artist:"Portishead"', limit: '12', releases: 'false' }, { query: 'artist:"Portishead"', limit: '12', releases: 'false' },
        { query: 'artist:"Portishead"', limit: '12', releases: 'false', offset: '24' }])
    urls.length = 0
    await MB.searchSongs('recording:"roads"', 25)
    await MB.searchSongs('recording:"roads"', 25, undefined, 25)
    check('(2.0.0-player.53) the songs: /search_musicbrainz/songs, the limit asked, an offset only past the first page',
      urls.map((url) => [new URL(url, 'http://deadwax.test').pathname.replace(/^.*\/search_musicbrainz/, ''), query(url)]),
      [['/songs', { query: 'recording:"roads"', limit: '25' }], ['/songs', { query: 'recording:"roads"', limit: '25', offset: '25' }]])
    globalThis.fetch = fetchBefore
  }

  console.log('\nthe real prefetch (player/api.ts): a scroll calls off a tile\'s ask, never one Search keeps')
  {
    const fetches = []
    globalThis.fetch = (url, init) => new Promise((resolve, reject) => {
      const entry = { url, aborted: false, answer: () => resolve({ ok: true, status: 200, json: async () => ({ id: url.split('/').pop(), song: [] }) }),
        fail: () => resolve({ ok: false, status: 503, json: async () => ({ detail: 'Navidrome is busy' }) }) }
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
    //? 2.0.0-player.17: a FAILED kept ask is let go, so the next asks afresh - the artist page's Try
    //? again, or the album page opening - rather than being handed the same failure for 30 s
    const flaky = api.prefetchAlbum('flaky', true)
    flaky.catch(() => {})
    check('a kept ask still out is the one handed back', [api.prefetchAlbum('flaky', true) === flaky, fetches.length], [true, 6])
    fetches[5].fail()
    await settle()
    check('...and once it has failed, it is let go: the next asks afresh', [api.prefetchAlbum('flaky', true) === flaky, fetches.length], [false, 7])
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main()
