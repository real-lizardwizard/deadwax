/**
 * The app's Search tab (app/Search.tsx) - one list in Apple Music's sections since 2.0.0-player.55 ("search like
 * Apple Music") - the component itself, compiled with the repo's TypeScript and rendered by the small stand-in for
 * Preact the other component sims use, with Navidrome, MusicBrainz and /library/owned faked and the clock a fake
 * one. Beside it, the store of what the library holds (app/useOwned.ts, the real one), the real prefetch in
 * player/api.ts and the real MusicBrainz client.
 *
 * The rows are app/SearchRows.tsx's - plain FUNCTIONS Search calls (topRow, sectionRow, slot, head), never mounted
 * as components, so the stand-in (whose `jsx` returns {type, props} and never renders a function component) sees
 * every one of them: no teaching the stand-in to expand components was needed.
 *
 * What it pins, each a part of the slice or a review's finding:
 *
 *  - What the library holds (app/useOwned.ts): one ask out at a time, one more after it when asked meanwhile; a
 *    refreshOwned() answered only once an ask made after it has landed; a filed album asking again once anything
 *    has asked - even after a first ask that failed - and never before.
 *  - THE LIST: the chips (the Library's, outside the form), the live region there from the first render, the
 *    asking line before the library lands; Top results at the library's moment ("portishead", "roads", "glory box"
 *    whole; "dummy" two rows and the place, then MusicBrainz's song in it; "third" nothing early); the sections
 *    found by app-search-artists/-albums/-songs, drawn at moment 2 in the asking line's place; the studio line.
 *  - THE INVARIANT, driven by timed answers (library 300 ms; artists 1.2 s, albums 1.5 s, songs 3 s; albums past
 *    the cap; each kind failing; all failing): after every answer, every tappable drawn before keeps its key and
 *    order, and every new tappable is inside a slot or after all of them.
 *  - The moments: the cap, a late kind folding into "Show N" with something below and drawing in when last,
 *    landing empty, Behind on and off (a superseded search never turning it on; Try again following its own
 *    moments), kept answers drawing whole, the library late and "Show them", Navidrome's status not known yet.
 *  - The chips: each kind view asks only its kind; Back to All draws whole, no phantom, late slots; MusicBrainz's
 *    rows waiting for the view's library rows; the Artists view under album-by-artist; under three characters;
 *    More from your library, More from MusicBrainz, More songs; See all with and without focus.
 *  - Taps: a MusicBrainz artist opens `mb:`; a library song in Top results plays in the tap; a MusicBrainz song in
 *    Top results opens its album with the song marked (no aria-expanded); Get on an album (the usual pressing) and
 *    on a song (a pressing with the song; the page when MusicBrainz can't list them).
 *  - Failures: per slot, the all-failed foot, busy words read from the body, a 422 refused (its words, no Try
 *    again, Behind left off), Try again asking only the failed kinds; no results; the gate above the list.
 *  - Logins on: yours before the store's, a whose not known yet as yours and never re-sorted, an Add re-marking a
 *    row in place; the frame kept at the draw; focus handed on as Show N, Show them, Try again and the last More go -
 *    on a stand-in DOM over what is drawn (`dom`: only what is drawn is found, focus falls to the body as a draw takes
 *    the focused element away, a selector holding a raw newline throws as a browser's does).
 *  - After review, each on a fresh Search (`remount`, the last one unmounted): the box cut back below three and the
 *    same words typed again; the box read once MusicBrainz is asked (an artist search3 names afterwards strands
 *    nothing; Enter reads it afresh); a letter typed and taken back arming the cap; "U2" and Search with MusicBrainz
 *    away; a kind view while Navidrome is away or its status unknown; a kind view's asking line and region; a text
 *    the library was once late for; an album held since its answer landed shown once; the library late then
 *    Navidrome away; a kind view's late place after a chip round trip; the desktop sidebar's field (the real
 *    app/searchBox.ts); More failing and its second tap; the rules nothing pinned (the chip back to All, Behind with
 *    nothing found, Navidrome back, the artist list asked again, the library's problem).
 *  - After the late recheck: Enter after a failure in All (a slot, the foot, the library) asking again AND drawing
 *    afresh; Navidrome back after the library failed; a kind view's library failing (no "No albums for" under it); the
 *    Artists view under album-by-artist with nothing named; the Albums view's held album its search3 didn't list;
 *    Back to All said; a 422 said as refused; More from the store; a late kind all held; kept answers refreshing
 *    holding; two characters' asking line.
 *  - Song search's own (2.0.0-player.53): the disclosure and its fold, an album you have opening the album you have
 *    (the id bridge, the pressings asked first for a pressing nothing vouches for), called off as the box changes.
 *  - The real client and the real prefetch.
 *
 * Run it with:  node ui/test/search.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const FIXTURES = path.resolve(__dirname, '../../tests/fixtures')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-search-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/Search.tsx', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? the real prefetch, kept aside before player/api.js is faked for the component
fs.copyFileSync(path.join(OUT, 'player/api.js'), path.join(OUT, 'player/api.real.js'))
//? ...and the real MusicBrainz client (its paths, the offset and quick it sends)
fs.copyFileSync(path.join(OUT, 'api/musicbrainz.js'), path.join(OUT, 'api/musicbrainz.real.js'))

//? JSX as plain objects, and hooks with a cursor, as Preact's are - a set state marks the root dirty, so a draw
//? renders and commits again until nothing an effect did is left undrawn
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
exports.useState = (v) => { const root = current; const s = slot(() => ({ v: typeof v === 'function' ? v() : v })); return [s.v, (x) => { const next = typeof x === 'function' ? x(s.v) : x; if (!Object.is(next, s.v)) root.dirty = true; s.v = next }] }
exports.useMemo = (f, deps) => { const s = slot(() => ({})); if (changed(s.deps, deps)) { s.v = f(); s.deps = deps } return s.v }
exports.useRef = (v) => slot(() => ({ current: v }))
exports.useEffect = exports.useLayoutEffect = (f, deps) => {
  const s = slot(() => ({}))
  if (changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f }
}
exports.root = (component) => {
  const root = { slots: [], cursor: 0, effects: [], dirty: false }
  const render = (props) => {
    const outer = current; current = root; root.cursor = 0; root.dirty = false
    try { return component(props) } finally { current = outer }
  }
  render.commit = () => { for (const s of root.effects.splice(0)) { if (typeof s.cleanup === 'function') s.cleanup(); s.cleanup = s.f() } }
  render.dirty = () => root.dirty
  //? leaving: every effect's cleanup run, as Preact's unmount runs them
  render.unmount = () => { for (const s of root.slots) if (s && typeof s.cleanup === 'function') { s.cleanup(); s.cleanup = null } }
  return render
}
`)

/* ===== Navidrome, MusicBrainz and the library, faked: each answer is what the test says next ===== */

fs.writeFileSync(path.join(OUT, 'api/musicbrainz.js'), `
const real = require('./musicbrainz.real.js')
exports.fullySearchPath = real.fullySearchPath
exports.searchSongsPath = real.searchSongsPath
exports.searchArtistsPath = real.searchArtistsPath
exports.fullySearch = (query, limit, releases, signal, offset, quick) => globalThis.__search.fullySearch(query, limit, releases, signal, offset, quick)
exports.getReleaseGroup = (id, signal) => globalThis.__search.getReleaseGroup(id, signal)
exports.searchSongs = (query, limit, signal, offset) => globalThis.__search.searchSongs(query, limit, signal, offset)
exports.searchArtists = (name, limit, signal, offset) => globalThis.__search.searchArtists(name, limit, signal, offset)
exports.searchSavedPath = real.searchSavedPath
exports.searchSaved = (words, signal) => globalThis.__search.searchSaved(words, signal)
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
exports.searchLibrary = (text, signal, page) => globalThis.__search.searchLibrary(text, signal, page)
exports.libraryArtists = () => globalThis.__search.libraryArtists()
exports.prefetchAlbum = (id, keep) => globalThis.__search.prefetchAlbum(id, keep)
exports.dropPrefetch = (id) => globalThis.__search.calls.push(['dropPrefetch', id])
exports.rememberPlayed = (album) => globalThis.__search.calls.push(['rememberPlayed', album.id])
exports.toQueueTrack = (song, album) => ({ id: song.id, album: album.id })
`)
//? the frame (app/useFrame.ts reads matchMedia): the test says which; your albums (app/useYourAlbums.ts asks
//? albumPage, which the faked player/api lacks): the test answers them, and moves their generation
fs.writeFileSync(path.join(OUT, 'app/useFrame.js'), `
exports.useFrame = () => ({ frame: globalThis.__search.frame, panel: globalThis.__search.frame === 'desktop' ? 'column' : 'sheet' })
`)
fs.writeFileSync(path.join(OUT, 'app/useYourAlbums.js'), `
exports.yourAlbums = () => globalThis.__search.yourAlbums()
exports.useYourAlbumsGeneration = () => globalThis.__search.generation
exports.forgetYourAlbums = () => { globalThis.__search.generation += 1 }
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
    if (drawing) draw()
  }
  now = end
  await settle()
  if (drawing) draw()
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
  await settle()
  for (let pending = asks.owned.filter((d) => !d.done); pending.length; pending = asks.owned.filter((d) => !d.done)) {
    for (const d of pending) d.resolve(answer)
    await settle()
  }
  if (drawing) draw()
}

const aborting = (d, signal) => {
  if (signal) signal.addEventListener('abort', () => { if (!globalThis.__search.abortRejects) return; const error = new Error('aborted'); error.name = 'AbortError'; d.reject(error) })
}
const asks = { owned: [], library: [], musicbrainz: [], artists: [], prefetch: [], pressings: [], songs: [], order: [], lists: [], yours: [], saved: [] }
//? what's saved (2.0.0-player.56): answered at once with nothing - every check before it is today's behaviour - unless a
//? check says what it holds (`savedHolds`, by the words) or answers it by hand (`savedByHand`)
const NOTHING_SAVED = { available: true, artists: { matches: [], count: 0 }, albums: { 'release-groups': [], count: 0 }, songs: { recordings: [], count: 0 } }
globalThis.__search = {
  calls: [],
  settingsAsked: [],
  frame: 'phone',
  generation: 0,
  //? false: an answer already on its way when it was called off still lands
  abortRejects: true,
  getReleaseGroup(id, signal) {
    const d = deferred()
    asks.pressings.push({ id, signal, ...d })
    aborting(d, signal)
    return d.promise
  },
  actions: { playTracks: (queue, at) => globalThis.__search.calls.push(['playTracks', queue.map((track) => track.id), at]) },
  owned() { const d = deferred(); asks.owned.push(d); return d.promise },
  searchLibrary(text, signal, page) { const d = deferred(); asks.library.push({ text, signal, page, ...d }); aborting(d, signal); return d.promise },
  libraryArtists() { const d = deferred(); asks.lists.push(d); return d.promise },
  yourAlbums() { const d = deferred(); asks.yours.push(d); return d.promise },
  fullySearch(query, limit, releases, signal, offset, quick) {
    const d = deferred()
    asks.musicbrainz.push({ query, limit, releases, signal, offset, quick, ...d })
    asks.order.push('albums')
    aborting(d, signal)
    return d.promise
  },
  searchArtists(name, limit, signal, offset) {
    const d = deferred()
    asks.artists.push({ name, limit, signal, offset, ...d })
    asks.order.push('artists')
    aborting(d, signal)
    return d.promise
  },
  prefetchAlbum(id, keep) { const d = deferred(); asks.prefetch.push({ id, keep, ...d }); return d.promise },
  savedHolds: null,
  savedByHand: false,
  searchSaved(words, signal) {
    const d = deferred()
    asks.saved.push({ words, signal, ...d })
    aborting(d, signal)
    if (!globalThis.__search.savedByHand) d.resolve(globalThis.__search.savedHolds?.(words) ?? NOTHING_SAVED)
    return d.promise
  },
  searchSongs(query, limit, signal, offset) {
    const d = deferred()
    asks.songs.push({ query, limit, signal, offset, ...d })
    asks.order.push('songs')
    aborting(d, signal)
    return d.promise
  },
}

let failures = 0
let checks = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  checks++
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
const { forgetAnswers } = require(path.join(OUT, 'app/searchAnswers.js'))
const Session = require(path.join(OUT, 'app/session.js'))
const { MusicBrainzUnavailable, ApiError } = require(path.join(OUT, 'api/http.js'))
//? (2.0.4) the library half failing as api/http.ts throws it: a 502 from the Navidrome routes - words fit for anyone
//? shown as they are, plumbing never (lib/errorWords.ts)
const navidromeSaid = (detail) => new ApiError(502, detail, 'GET /navidrome/search failed', false, null, null, '/navidrome/search')
const Access = require(path.join(OUT, 'app/access.js'))

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

/* ===== what is drawn, read the way a person sees it ===== */

const sectionOf = (id) => find((node) => node.type === 'section' && node.props['aria-labelledby'] === id)[0]
const top = () => sectionOf('app-search-top')
const kinds = () => find((node) => node.type === 'section' && /^app-search-(artists|albums|songs)$/.test(node.props['aria-labelledby'] ?? '')).map((node) => node.props['aria-labelledby'].slice(11))
const rowKeys = (within) => find((node) => node.type === 'button' && node.props['data-row'], within).map((node) => node.props['data-row'])
const topKeys = () => (top() ? rowKeys(top()) : [])
const lineOf = (row) => text(find(byClass('app-result-line'), row)[0])
const rowsOf = (kind) => {
  const section = sectionOf(`app-search-${kind}`)
  return section ? find((node) => node.type === 'button' && node.props['data-row'], section).map((node) => [text(find(byClass('app-result-title'), node)[0]), lineOf(node)]) : []
}
const keysOf = (kind) => (sectionOf(`app-search-${kind}`) ? rowKeys(sectionOf(`app-search-${kind}`)) : [])
const asking = () => find((node) => byClass('app-search-asking')(node))
const slotOf = (kind) => { const section = sectionOf(`app-search-${kind}`); return section ? find(byClass('app-search-slot'), section)[0] : undefined }
const slotText = (kind) => text(slotOf(kind))
const region = () => find((node) => node.props?.role === 'status' && node.props['aria-live'] === 'polite')
const said = () => text(region()[0])
const chipsOf = () => find(byClass('app-search-kinds'))[0]
const chip = (label) => find((node) => node.type === 'button' && text(node) === label, chipsOf())[0]
const seeAll = (kind) => find(byClass('app-search-see-all'), sectionOf(`app-search-${kind}`))[0]
const buttonText = (label, within = tree) => find((node) => node.type === 'button' && text(node) === label, within)[0]
const rowButton = (key) => find((node) => node.type === 'button' && node.props['data-row'] === key)[0]
const getOf = (key) => {
  const li = find((node) => (node.type === 'li' || node.type === 'div') && byClass('app-result-row')(node) && find((n) => n.type === 'button' && n.props['data-row'] === key, node).length)[0]
  return li ? find(byClass('app-result-get'), li)[0] : undefined
}

/**
 * A stand-in for the page's DOM over what is drawn (review: the focus checks answered any selector with an element and
 * moved focus off a control as it was tapped, so a hand-on spent on the old draw, or a selector no browser would take,
 * passed). An element is a drawn node known by what it is - its id, its row's key, else its tag, class and words in its
 * section - the same object draw after draw; focus() makes it document.activeElement, isConnected says whether the
 * latest draw holds it, and a draw that takes the focused element away leaves focus on the body, as a browser's does.
 * querySelector takes `.class`, `#id`, `[attr]` and `[attr="value"]`, and throws, as a browser does, on a selector
 * holding a raw newline.
 */
const dom = (() => {
  const elements = new Map()
  let drawnNow = []
  const body = { name: 'body', isConnected: true }
  const focused = []
  //? a state's class (is-on, is-busy) and a More's words (it says "Asking MusicBrainz…" while it asks) change nothing:
  //? Preact keeps the element and changes its class or words
  const stable = (cls) => (typeof cls === 'string' ? cls : '').split(' ').filter((name) => name && name !== 'is-on' && name !== 'is-busy').join('.')
  const identity = (node, section, parent) => node.props.id ? `#${node.props.id}`
    : node.props['data-row'] !== undefined ? `row:${node.props['data-row']}`
      : node.props['aria-label'] ? `${node.type}[${node.props['aria-label']}]|${section}`
        : byClass('app-search-more')(node) ? `${node.type}.${stable(node.props.class)}|${section}`
          : `${node.type}.${stable(node.props.class)}|${parent}|${section}|${text(node)}`
  const element = (key) => {
    if (!elements.has(key)) {
      const el = {
        key,
        node: null,
        focus() { document.activeElement = el; focused.push(key) },
        getAttribute(name) { const value = el.node?.props[name]; return value === undefined || value === null || value === false ? null : String(value) },
        get isConnected() { return drawnNow.some((each) => each.el === el) },
        scrollIntoView() {},
      }
      elements.set(key, el)
    }
    return elements.get(key)
  }
  const matches = (node, selector) => {
    const attr = /^\[([\w-]+)(?:="([^"]*)")?\]$/.exec(selector)
    if (attr) { const value = node.props[attr[1]]; return value !== undefined && value !== null && value !== false && (attr[2] === undefined || String(value) === attr[2]) }
    if (selector.startsWith('#')) return node.props.id === selector.slice(1)
    if (selector.startsWith('.')) return selector.slice(1).split('.').every((name) => byClass(name)(node))
    throw new Error(`the stand-in DOM doesn't read "${selector}"`)
  }
  const check = (selector) => { if (/\n/.test(selector)) throw new SyntaxError(`'${selector}' is not a valid selector`) }
  const api = {
    focused,
    body,
    /** what is drawn now: called as each draw is made, before its effects run */
    sync(tree) {
      const out = []
      const visit = (node, section, parent) => {
        if (!node || typeof node !== 'object') return
        if (Array.isArray(node)) { node.forEach((each) => visit(each, section, parent)); return }
        const drawnHere = typeof node.type === 'string' && node.type !== 'fragment'
        if (drawnHere) {
          const el = element(identity(node, section, parent))
          el.node = node
          out.push({ el, node })
        }
        visit(node.props?.children, node.type === 'section' ? (node.props['aria-labelledby'] ?? section) : section, drawnHere ? stable(node.props.class) : parent)
      }
      visit(tree, '', '')
      drawnNow = out
      if (globalThis.document?.activeElement && globalThis.document.activeElement !== body && !globalThis.document.activeElement.isConnected) globalThis.document.activeElement = body
    },
    /** the element a drawn node is */
    el(node) { return drawnNow.find((each) => each.node === node)?.el },
    querySelector(selector) { check(selector); return drawnNow.find((each) => matches(each.node, selector))?.el ?? null },
    querySelectorAll(selector) { check(selector); return drawnNow.filter((each) => matches(each.node, selector)).map((each) => each.el) },
    scrollIntoView() {},
    /** a page with focus on `node` (null: the body), Search's root and the chips reading this DOM */
    use(node = null) {
      api.sync(tree)
      globalThis.document = { activeElement: node ? api.el(node) : body, body }
      focused.length = 0
      const rootRef = find(byClass('app-search'))[0]?.props.ref
      if (rootRef) rootRef.current = api
      const chipsRef = find(byClass('app-search-kinds'))[0]?.props.ref
      if (chipsRef) chipsRef.current = api
    },
    /** a tap from the keyboard: focus on it, then its click, its own element the event's */
    press(node) { const el = api.el(node); globalThis.document.activeElement = el; node.props.onClick({ currentTarget: el }); draw() },
    leave() { delete globalThis.document; const rootRef = find(byClass('app-search'))[0]?.props.ref; if (rootRef) rootRef.current = null },
  }
  return api
})()

/**
 * Every tappable thing drawn, in reading order: its identity, and whether it sits in a slot (one place one fixed
 * height: what fills it may change, nothing outside it moves).
 */
function tappables() {
  const out = []
  const visit = (node, inSlot) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach((each) => visit(each, inSlot)); return }
    const slotted = inSlot || byClass('app-search-slot')(node) || byClass('app-search-top-place')(node)
    if (node.type === 'button') {
      const id = node.props['data-row'] ? `row:${node.props['data-row']}`
        : byClass('app-result-get')(node) ? `get:${node.props['aria-label']}`
          : byClass('app-search-see-all')(node) ? `see:${node.props['aria-label']}`
            : `button:${text(node)}`
      out.push({ id, slotted })
    }
    visit(node.props?.children, slotted)
  }
  visit(tree, false)
  return out
}
let before = null
/** The invariant: what was drawn tappable before keeps its identity and order, and anything new is in a slot or
 *  after it all. `label` names the moment. */
function invariant(label) {
  const after = tappables()
  if (before) {
    const was = before.filter((each) => !each.slotted).map((each) => each.id)
    const nowIds = after.filter((each) => !each.slotted).map((each) => each.id)
    const kept = nowIds.slice(0, was.length)
    const okay = JSON.stringify(kept) === JSON.stringify(was)
    if (!okay) check(`(invariant) ${label}: what was drawn stays in place, anything new below it or in a slot`, kept, was)
    else checks++
  }
  before = after
}
const freshInvariant = () => { before = null }

const DUMMY = { id: '48140466-cff6-3222-bd55-63c27e43190d', title: 'Dummy', 'primary-type': 'Album', 'first-release-date': '1994-08-22',
  'artist-credit': [{ name: 'Portishead', artist: { id: '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11', name: 'Portishead' } }] }
const THIRD = { id: '163339ab-813b-3d29-bba8-e1d5acf63cab', title: 'Third', 'primary-type': 'Album', 'first-release-date': '2008-04-28',
  'artist-credit': [{ name: 'Portishead', artist: { id: '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11', name: 'Portishead' } }] }
const ROSELAND = { id: 'ce61f4a8-db95-3608-93de-53f9ecb1b8d2', title: 'Roseland NYC Live', 'primary-type': 'Album', 'secondary-types': ['Live'], 'first-release-date': '1998-11-02',
  'artist-credit': [{ name: 'Portishead', artist: { id: '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11', name: 'Portishead' } }] }
const holding = (...groups) => ({ albums: groups.map((group) => ({ path: `Portishead/${group.title}`, artist: 'Portishead', album: group.title, release_group_mbid: group.id, release_mbid: `rel-${group.title.toLowerCase()}` })) })
//? held by group alone (no release id): what every screen holds an untagged-by-release folder by - it says it has the song
const byGroup = (...groups) => ({ albums: groups.map((group) => ({ path: `Portishead/${group.title}`, artist: 'Portishead', album: group.title, release_group_mbid: group.id })) })
const load = (name) => JSON.parse(fs.readFileSync(path.join(FIXTURES, `${name}.json`), 'utf8'))
const studio = load('search/rg-artist-portishead-studio')
const unfiltered = load('search/rg-artist-portishead')
const portisheadArtists = load('artists/portishead.route')
const kanyeArtists = load('artists/kanye-west.route')
const radioheadArtists = load('artists/radiohead.route')
const roadsRecorded = load('songs/roads-portishead')

const P = { id: 'ar1', name: 'Portishead', albumCount: 3, musicBrainzId: '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11' }
const ndDummy = { id: 'nd-dummy', name: 'Dummy', artist: 'Portishead', artistId: 'ar1', year: 1994, musicBrainzId: 'rel-dummy' }
const libSong = (id, title, albumId = 'nd-dummy', album = 'Dummy') => ({ id, title, artist: 'Portishead', artistId: 'ar1', albumId, album })
const status = { configured: true, ok: true, server: 'Navidrome 0.64.2', problem: null }

let drawing = false
let render = null
const props = {}
function draw(more = {}) {
  Object.assign(props, more)
  for (let pass = 0; pass < 8; pass++) {
    tree = render(props)
    //? the page as this draw leaves it, before its effects run - focus off anything it took away
    if (globalThis.document) dom.sync(tree)
    render.commit()
    if (!render.dirty()) break
  }
  return tree
}
/** A fresh Search - Behind, its answers, its runs all gone with the last one (unmounted: everything called off) - over
 *  the same fakes, the full artist list answered as it asks. */
async function remount(more = {}, artistList = [P, { id: 'ar-teb', name: 'Third Eye Blind' }]) {
  await answerOwned(holding(DUMMY))
  render.unmount()
  timers.clear()
  forgetAnswers()
  render = hooks.root(Search)
  Object.assign(props, { status, active: true, shown: true }, more)
  draw()
  //? (null: the list's ask left for the test to answer)
  if (props.status?.ok && artistList) asks.lists.at(-1)?.resolve(artistList)
  await settle()
  draw()
}
const type = (value) => { find((node) => node.type === 'input')[0].props.onInput({ currentTarget: { value } }); draw() }
const enter = () => { find((node) => node.type === 'form')[0].props.onSubmit({ preventDefault() {} }); draw() }

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

  const opened = []
  const groupsOpened = []
  const gets = []
  const songAlbums = []
  const mbArtists = []
  const artistsOpened = []
  render = hooks.root(Search)
  Object.assign(props, { shown: true, active: true, status, onRetry() {}, onOpenAlbum: (album) => opened.push(album), onOpenGroup: (group) => groupsOpened.push(group),
    onOpenSongAlbum: (album, song) => songAlbums.push([album, song]), onOpenArtist: (artist) => artistsOpened.push(artist),
    onOpenMusicBrainzArtist: (artist) => mbArtists.push(artist), onGet: (request, opener) => gets.push([request, opener]) })
  drawing = true

  console.log('\nthe box, the region, the hint')
  draw()
  check('the box holds no more than the route takes', find((node) => node.type === 'input')[0].props.maxLength, SEARCH_MAX_CHARS)
  check('...which is the route\'s bound', SEARCH_MAX_CHARS, 200)
  check('the list\'s one live region is there from the first render, saying nothing yet (iOS reads only regions already in the page)', [region().length, said()], [1, ''])
  check('before typing: no chips, the hint saying what is searched', [chipsOf(), text(find(byClass('app-search-hint'))[0])],
    [undefined, "Artists, albums and songs: yours first, then MusicBrainz's."])
  check('the library\'s whole list of artists asked once as Search first shows, Navidrome OK', asks.lists.length, 1)
  asks.lists[0].resolve([P, { id: 'ar-teb', name: 'Third Eye Blind' }])
  await settle()
  draw()

  console.log('\n"portishead", held: Top results at the library\'s moment, the sections at moment 2')
  type('portishead')
  check('the chips once the box holds words: the Library\'s, verbatim - a group "Show", four chips, All pressed - outside the form',
    [chipsOf()?.props.class, chipsOf()?.props.role, chipsOf()?.props['aria-label'], find((node) => node.type === 'button', chipsOf()).map((node) => [text(node), node.props['aria-pressed'], node.props.class]),
      find(byClass('app-search-kinds'), find((node) => node.type === 'form')[0]).length],
    ['app-library-views app-search-kinds', 'group', 'Show', [['All', true, 'app-chip app-library-view is-on'], ['Artists', false, 'app-chip app-library-view'],
      ['Albums', false, 'app-chip app-library-view'], ['Songs', false, 'app-chip app-library-view']], 0])
  check('before the library lands: one asking line - "Searching your library and MusicBrainz…" - and no spinner', [text(asking()[0]), find(byClass('pl-spinner')).length],
    ['Searching your library and MusicBrainz…', 0])
  invariant('typed')
  await advance(199)
  check('Navidrome is asked once typing has paused', asks.library.length, 0)
  await advance(1)
  check('...200 ms after - All\'s counts, as ever (no page asked)', asks.library.map((ask) => [ask.text, ask.page]), [['portishead', undefined]])
  asks.library[0].resolve({
    artists: [P],
    albums: [ndDummy],
    songs: [libSong('s-roads', 'Roads'), libSong('s-glory', 'Glory Box'), libSong('s-rip', 'The Rip', 'nd-third', 'Third')],
  })
  await settle()
  draw()
  check('the library\'s moment: Top results - Portishead, Dummy, Roads (the mock) - all three decided, no place', [topKeys(), find(byClass('app-search-top-place')).length],
    [['top:artist:ar1', 'top:album:nd-dummy', 'top:song:s-roads'], 0])
  check('...each saying what it is first, its place in its own span', find((node) => node.type === 'button' && node.props['data-row'], top()).map(lineOf),
    ['Artist · 3 albums in your library', 'Album · Portishead · 1994 · in your library', 'Song · Portishead · Dummy · in your library'])
  check('...then one asking line where the sections will go, no region of its own', [kinds(), text(asking()[0]), asking()[0]?.props.role], [[], 'Asking MusicBrainz…', undefined])
  check('the region says what the library found', said(), 'In your library: 1 artist, 1 album, 3 songs.')
  check('the albums of Top results\' songs asked first, then the first songs\' - KEPT, so a scroll can\'t call them off',
    asks.prefetch.map((ask) => [ask.id, ask.keep]), [['nd-dummy', true], ['nd-third', true]])
  invariant('the library\'s moment')
  asks.prefetch[0].resolve({ id: 'nd-dummy', name: 'Dummy', song: [{ id: 's-glory', title: 'Glory Box' }, { id: 's-roads', title: 'Roads' }] })
  await settle()
  draw()
  const playMark = (key) => find((node) => node.type?.name === 'PlayIcon', rowButton(key)).length
  check('Roads in Top results shows ▶ once its album is in hand', playMark('top:song:s-roads'), 1)
  rowButton('top:song:s-roads').props.onClick()
  check('...and its tap remembers the album, then plays it from that song, in the tap', globalThis.__search.calls, [['rememberPlayed', 'nd-dummy'], ['playTracks', ['s-glory', 's-roads'], 1]])
  await advance(499)
  check('MusicBrainz is asked 700 ms after typing stops, not before', asks.musicbrainz.length + asks.artists.length + asks.songs.length, 0)
  await advance(1)
  check('...albums first - the studio clause for an artist you have, a quick search of twelve - then artists (the box, ten); no songs for an artist\'s name alone',
    [asks.order, asks.musicbrainz.map((ask) => [ask.query, ask.limit, ask.releases, ask.offset, ask.quick]), asks.artists.map((ask) => [ask.name, ask.limit, ask.offset])],
    [['albums', 'artists'], [['(artist:"Portishead") AND (primarytype:"Album" OR primarytype:"EP") AND -secondarytype:"Live" AND -secondarytype:"Compilation" AND -secondarytype:"Interview" AND -secondarytype:"Demo" AND -secondarytype:"Remix" AND -secondarytype:"DJ-mix"', 12, false, 0, true]],
      [['portishead', 10, undefined]]])
  check('...the library asked beside them', asks.owned.length, 6)
  asks.artists[0].resolve(portisheadArtists)
  await settle()
  draw()
  invariant('the artists landed')
  check('artists in, albums still out: the sections wait (moment 2 is every kind, or the cap)', kinds(), [])
  asks.musicbrainz[0].resolve(studio)
  await answerOwned(holding(DUMMY))
  draw()
  invariant('moment 2')
  check('moment 2: the three sections in the asking line\'s place - Apple\'s order', [kinds(), asking().length], [['artists', 'albums', 'songs'], 0])
  check('Artists: yours - MusicBrainz\'s Portishead is yours (by id), so no second row', keysOf('artists'), ['artist:ar1'])
  check('Albums: yours, then MusicBrainz\'s studio albums in the studio order, Dummy (held) left out, three on a phone',
    rowsOf('albums'), [['Dummy', 'Portishead · 1994 · in your library'], ['Portishead', 'Portishead · 1997'], ['Third', 'Portishead · 2008'], ['R.A.R.E (Reliving a Real Experience)', 'Mixtape · Nickelus F & Portishead · 2009']])
  check('...under them, the active filter: one quiet line', text(find(byClass('app-search-filter-note'), sectionOf('app-search-albums'))[0]),
    "MusicBrainz's studio albums and EPs - See all for everything they made.")
  check('Songs: yours, three on a phone', keysOf('songs'), ['song:s-roads', 'song:s-glory', 'song:s-rip'])
  check('each section headed, its See all always drawn - a text button labelled for its kind', ['artists', 'albums', 'songs'].map((kind) => seeAll(kind)?.props['aria-label']),
    ['See all artists', 'See all albums', 'See all songs'])
  check('the region says what MusicBrainz brought, once every kind asked has settled', said(), 'From MusicBrainz: 3 albums.')
  check('a MusicBrainz album has Get; one you have doesn\'t', [text(getOf(`group:${THIRD.id}`)), getOf('album:nd-dummy')], ['Get', undefined])


  console.log('\nSee all, and the chips: that kind in full')
  {
    const scrolled = []
    const focused = []
    const rootRef = () => find(byClass('app-search'))[0].props.ref
    const stand = () => {
      chipsOf().props.ref.current = { scrollIntoView: (how) => scrolled.push(how), querySelector: (selector) => (selector === '[aria-pressed="true"]' ? { focus: () => focused.push('pressed chip') } : null) }
      rootRef().current = { querySelector: () => null }
    }
    stand()
    const libraryAsks = asks.library.length, albumAsks = asks.musicbrainz.length, artistAsks = asks.artists.length, songAsks = asks.songs.length
    const button = seeAll('albums')
    globalThis.document = { activeElement: button, body: { name: 'body' } }
    button.props.onClick({ currentTarget: button })
    draw()
    stand()
    draw()
    check('See all pressed from the keyboard: the Albums chip pressed, the chips scrolled into view (nearest), focus to the chip it pressed',
      [find((node) => node.type === 'button' && node.props['aria-pressed'], chipsOf()).map(text), scrolled, focused], [['Albums'], [{ block: 'nearest' }], ['pressed chip']])
    delete globalThis.document
    check('...the region says so', said(), 'Showing albums.')
    check('the Albums view asks its own search3 - albums alone, fifty - and MusicBrainz unfiltered (one more request); nothing of another kind',
      [asks.library.slice(libraryAsks).map((ask) => [ask.text, ask.page]), asks.musicbrainz.slice(albumAsks).map((ask) => [ask.query, ask.quick]), asks.artists.length - artistAsks, asks.songs.length - songAsks],
      [[['portishead', { counts: { artistCount: 0, albumCount: 50, songCount: 0 } }]], [['artist:"Portishead"', true]], 0, 0])
    check('one section, headed Albums, no See all, no Top results', [kinds(), seeAll('albums'), top()], [['albums'], undefined, undefined])
    asks.musicbrainz.at(-1).resolve(unfiltered)
    await answerOwned(holding(DUMMY))
    draw()
    check('MusicBrainz\'s rows never draw before the view\'s library rows: they wait for its search3', keysOf('albums'), [])
    const fifty = Array.from({ length: 50 }, (_, at) => ({ id: `nd-a${at}`, name: `Album ${at}`, artist: 'Portishead', year: 2000 }))
    asks.library.at(-1).resolve({ artists: [], albums: [ndDummy, ...fifty.slice(0, 49)], songs: [] })
    await settle()
    draw()
    check('then the view\'s library rows, More from your library under them (a full page), then MusicBrainz\'s - all twelve, unfiltered',
      [keysOf('albums').slice(0, 2), keysOf('albums').length, text(find(byClass('app-search-more-library'))[0]), rowsOf('albums').slice(50).map(([title]) => title)],
      [['album:nd-dummy', 'album:nd-a0'], 62, 'More from your library', unfiltered['release-groups'].map((group) => group.title)])
    check('...More from MusicBrainz under them (the count says 90)', text(find((node) => byClass('app-search-more')(node) && !byClass('app-search-more-library')(node))[0]), 'More from MusicBrainz')
    find(byClass('app-search-more-library'))[0].props.onClick()
    draw()
    check('More from your library asks the next page of albums by offset, the other counts 0', asks.library.at(-1).page,
      { counts: { artistCount: 0, albumCount: 50, songCount: 0 }, offsets: { albumOffset: 50 } })
    asks.library.at(-1).resolve({ artists: [], albums: fifty.slice(49), songs: [] })
    await settle()
    draw()
    check('...its page appended, the button gone with a short page, said', [keysOf('albums')[50], find(byClass('app-search-more-library')).length, said()], ['album:nd-a49', 0, '1 more album from your library'])

    //? back to All: drawn whole at once from everything in hand - the studio answer kept from before, so nothing asked
    const kept = asks.musicbrainz.length
    chip('All').props.onClick()
    draw()
    check('Back to All: drawn whole at once - Top results and every section - the studio answer kept from before, nothing asked of MusicBrainz',
      [topKeys(), kinds(), asks.musicbrainz.length - kept, asking().length, said()], [['top:artist:ar1', 'top:album:nd-dummy', 'top:song:s-roads'], ['artists', 'albums', 'songs'], 0, 0,
        'Showing everything. In your library: 1 artist, 1 album, 3 songs. From MusicBrainz: 3 albums.'])
    freshInvariant()
    invariant('back to All')
  }


  //? a song MusicBrainz found, as its recording search answers it
  const recording = (id, title, artist, artistId, group) => ({ id, title, 'artist-credit': [{ name: artist, artist: { id: artistId, name: artist } }],
    releases: [{ id: `rel-${id}`, status: 'Official', date: group['first-release-date'] ?? '', 'release-group': { id: group.id, title: group.title, 'primary-type': group['primary-type'] ?? 'Album', 'secondary-types': group['secondary-types'] ?? [] },
      media: [{ position: 1, track: [{ id: `t-${id}`, number: '1', title, length: 240000 }] }] }] })
  const SOMEBODY = '00000000-0000-4000-8000-00000000b0d1'
  const SOMEONE_ALBUM = { id: '00000000-0000-4000-8000-0000000000a1', title: 'Somebody\'s Album', 'primary-type': 'Album', 'first-release-date': '2001' }
  const ARTISTS_NONE = { matches: [], count: 0 }
  /** Type `words` and let the library and MusicBrainz be asked: the library at 200 ms (answered with `library`), MusicBrainz
   *  at 700 - the asks returned, not yet answered. */
  async function search(words, library) {
    type(words)
    freshInvariant()
    invariant('typed')
    const from = { library: asks.library.length, albums: asks.musicbrainz.length, artists: asks.artists.length, songs: asks.songs.length, order: asks.order.length }
    await advance(200)
    if (library) {
      asks.library.slice(from.library).find((ask) => !ask.page).resolve(library)
      await settle()
      draw()
      //? the new text's moment 1 replaces the list whole (the finger is on the keyboard): what is kept from here
      freshInvariant()
      invariant('the library\'s moment')
    }
    return from
  }
  const newAsks = (from) => ({ albums: asks.musicbrainz.slice(from.albums), artists: asks.artists.slice(from.artists), songs: asks.songs.slice(from.songs), order: asks.order.slice(from.order) })

  console.log('\n"dummy": two decided, the place, then MusicBrainz\'s exact song in it')
  {
    const from = await search('dummy', { artists: [], albums: [ndDummy], songs: [libSong('s-sour', 'Sour Times')] })
    check('Dummy and Portishead decided, then one place - a row high, the sweep, no words, hidden from a screen reader', [topKeys(), find(byClass('app-search-top-place')).map((node) => [node.props['aria-hidden'], text(node)])],
      [['top:album:nd-dummy', 'top:artist:ar1'], [['true', '']]])
    await advance(500)
    const asked = newAsks(from)
    asked.artists[0].resolve(ARTISTS_NONE)
    asked.albums[0].resolve({ 'release-groups': [DUMMY], count: 1 })
    asked.songs[0].resolve({ recordings: [recording('r-dummy', 'Dummy', 'Somebody', SOMEBODY, SOMEONE_ALBUM)], count: 1 })
    await answerOwned(holding(DUMMY))
    invariant('moment 2')
    check('moment 2, in the render that draws the sections: the place filled by MusicBrainz\'s exact song "Dummy" - ahead of Sour Times',
      [topKeys(), find(byClass('app-search-top-place')).length, kinds()], [['top:album:nd-dummy', 'top:artist:ar1', 'top:mb-song:00000000-0000-4000-8000-00000000b0d1\ndummy'], 0, ['albums', 'songs']])
    check('...a MusicBrainz song in Top results opens its album, the song marked - not a disclosure (no aria-expanded)',
      [rowButton('top:mb-song:00000000-0000-4000-8000-00000000b0d1\ndummy').props['aria-expanded'], (() => { rowButton('top:mb-song:00000000-0000-4000-8000-00000000b0d1\ndummy').props.onClick(); return songAlbums.at(-1) })()],
      [undefined, [{ id: SOMEONE_ALBUM.id, title: 'Somebody\'s Album' }, ['r-dummy']]])
    check('...its line says what it is first; its Get names the album and the song', [lineOf(rowButton('top:mb-song:00000000-0000-4000-8000-00000000b0d1\ndummy')), getOf('top:mb-song:00000000-0000-4000-8000-00000000b0d1\ndummy')?.props['aria-label']],
      ['Song · Somebody · Somebody\'s Album', 'Get Somebody\'s Album, with Dummy'])
    check('in Songs, the same song is step 7\'s disclosure, Get beside it', [rowButton('mb-song:00000000-0000-4000-8000-00000000b0d1\ndummy')?.props['aria-expanded'], text(getOf('mb-song:00000000-0000-4000-8000-00000000b0d1\ndummy'))],
      [false, 'Get'])
  }

  console.log('\n"third", only Third Eye Blind held: nothing early, MusicBrainz\'s exact rows lead at moment 2')
  {
    const from = await search('third', { artists: [{ id: 'ar-teb', name: 'Third Eye Blind', albumCount: 2 }], albums: [], songs: [] })
    check('the library\'s moment: no Top results section at all (no heading, no place) - only the asking line', [top(), asking().length], [undefined, 1])
    await advance(500)
    const asked = newAsks(from)
    asked.artists[0].resolve(ARTISTS_NONE)
    asked.albums[0].resolve({ 'release-groups': [THIRD], count: 1 })
    asked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    invariant('moment 2')
    check('moment 2: Top results drawn whole above the sections - Third (exact), then its artist, then Third Eye Blind',
      [topKeys(), kinds()], [[`top:group:${THIRD.id}`, 'top:artist:ar1', 'top:artist:ar-teb'], ['artists', 'albums']])
  }

  console.log('\n"roads", Dummy held: Top results whole at the library\'s moment; the invariant through timed answers')
  {
    const from = await search('roads', { artists: [], albums: [], songs: [libSong('s-roads', 'Roads')] })
    check('Roads, then its album and artist (its family) - all three at the library\'s moment, no place', [topKeys(), find(byClass('app-search-top-place')).length],
      [['top:song:s-roads', 'top:album:nd-dummy', 'top:artist:ar1'], 0])
    invariant('the library\'s moment')
    await advance(500)
    const asked = newAsks(from)
    check('MusicBrainz at 700 ms: three requests, at most three at once - albums, then artists, then songs',
      [asked.order, asked.albums.map((ask) => ask.query), asked.artists.map((ask) => ask.name), asked.songs.map((ask) => ask.query)],
      [['albums', 'artists', 'songs'], ['roads'], ['roads'], ['roads']])
    //? artists at 1.2 s, albums at 1.5 s after the last key - songs at 3 s, past the cap (700 + 1500 = 2.2 s)
    await advance(500)
    asked.artists[0].resolve(ARTISTS_NONE)
    await answerOwned(holding(DUMMY))
    invariant('artists at 1.2 s')
    check('...nothing drawn for a kind until moment 2', kinds(), [])
    await advance(300)
    asked.albums[0].resolve({ 'release-groups': [{ id: '00000000-0000-4000-8000-0000000000r1', title: 'Roads', 'primary-type': 'Single', 'first-release-date': '1995', 'artist-credit': DUMMY['artist-credit'] }], count: 1 })
    await answerOwned(holding(DUMMY))
    invariant('albums at 1.5 s')
    check('...albums in, songs out: still waiting, under the cap', [kinds(), asking().length], [[], 1])
    await advance(699)
    check('...a moment before the cap: still the asking line', kinds(), [])
    await advance(1)
    invariant('the cap')
    check('the cap (1.5 s after MusicBrainz was asked): the sections drawn, Songs\' slot asking for MusicBrainz\'s songs - aria-busy',
      [kinds(), slotText('songs'), sectionOf('app-search-songs').props['aria-busy'], keysOf('songs')], [['albums', 'songs'], 'Asking MusicBrainz…', true, ['song:s-roads']])
    check('...a section with nothing to show left out (no artist anywhere)', sectionOf('app-search-artists'), undefined)
    await advance(800)
    asked.songs[0].resolve({ recordings: [recording('r-roads2', 'Roads', 'Someone', SOMEBODY, SOMEONE_ALBUM)], count: 1 })
    await answerOwned(holding(DUMMY))
    invariant('songs at 3 s')
    check('songs landing last, nothing tappable below them: drawn straight in, the slot gone', [keysOf('songs'), slotOf('songs'), sectionOf('app-search-songs').props['aria-busy']],
      [['song:s-roads', 'mb-song:00000000-0000-4000-8000-00000000b0d1\nroads'], undefined, false])
  }

  console.log('\nBehind, turned on by the songs missing the cap')
  {
    const from = await search('roads portishead', { artists: [], albums: [], songs: [libSong('s-roads', 'Roads')] })
    check('the next search draws at the library\'s moment: Top results from the library alone, a slot for each kind - Portishead leads Artists (the named artist)',
      [topKeys(), kinds(), keysOf('artists'), slotText('albums'), slotText('songs')],
      [['top:song:s-roads', 'top:album:nd-dummy', 'top:artist:ar1'], ['artists', 'albums', 'songs'], ['artist:ar1'], 'Asking MusicBrainz…', 'Asking MusicBrainz…'])
    await advance(500)
    const asked = newAsks(from)
    check('...album-by-artist: no artists asked - the artist is yours; albums and songs fielded', [asked.artists.length, asked.albums.map((ask) => ask.query), asked.songs.map((ask) => ask.query)],
      [0, ['releasegroup:"roads" AND (artist:"Portishead" OR artistname:"Portishead")'], ['recording:"roads" AND (artist:"Portishead" OR artistname:"Portishead")']])
    asked.albums[0].resolve({ 'release-groups': [DUMMY], count: 1 })
    asked.songs[0].resolve(roadsRecorded)
    await answerOwned(holding(DUMMY))
    invariant('Behind\'s kinds landing in time')
    check('...landing: Albums (not last) folds the album you hold that search3 didn\'t list - brought in (the held-groups rule extended); Songs, last, loses its slot - the MusicBrainz Roads is yours',
      [slotText('albums'), keysOf('songs'), slotOf('songs')], ['Show 1 album from MusicBrainz', ['song:s-roads'], undefined])
    const show = buttonText('Show 1 album from MusicBrainz')
    show.props.onClick({ currentTarget: show })
    draw()
    check('...shown: Dummy, marked "in your library", no Get - its tap opens the album you have', [rowsOf('albums'), getOf(`group:${DUMMY.id}`)], [[['Dummy', 'Portishead · 1994 · in your library']], undefined])
  }

  console.log('\na late kind with something below it folds; Behind')
  {
    const from = await search('glory box', { artists: [], albums: [ndDummy], songs: [libSong('s-glory', 'Glory Box')] })
    check('"glory box": Glory Box, Dummy, Portishead - Apple\'s own order, all at the library\'s moment', topKeys(), ['top:song:s-glory', 'top:album:nd-dummy', 'top:artist:ar1'])
    await advance(500)
    const asked = newAsks(from)
    asked.artists[0].resolve(ARTISTS_NONE)
    asked.songs[0].resolve({ recordings: [recording('r-gb', 'Glory Box (live)', 'Someone', SOMEBODY, SOMEONE_ALBUM)], count: 1 })
    await answerOwned(holding(DUMMY))
    await advance(1500)
    invariant('the cap, albums out')
    check('albums past the cap: Albums drawn with its slot, Songs below it', [kinds(), slotText('albums')], [['albums', 'songs'], 'Asking MusicBrainz…'])
    asked.albums[0].resolve({ 'release-groups': [ROSELAND, THIRD], count: 2 })
    await answerOwned(holding(DUMMY))
    invariant('albums landing late')
    check('...landing with something tappable below: folded into its slot - "Show 2 albums from MusicBrainz" - nothing below moves',
      [slotText('albums'), keysOf('albums'), said()], ['Show 2 albums from MusicBrainz', ['album:nd-dummy'], '2 albums from MusicBrainz - Show them to see them. From MusicBrainz: 2 albums, 1 song.'])
    const show = buttonText('Show 2 albums from MusicBrainz')
    show.props.onClick({ currentTarget: show })
    draw()
    check('...a tap opens them in place (your own act)', [keysOf('albums'), slotOf('albums')], [['album:nd-dummy', `group:${ROSELAND.id}`, `group:${THIRD.id}`], undefined])

    //? Behind is on: the next search draws at the library's moment, MusicBrainz's kinds in slots
    const next = await search('sour times', { artists: [], albums: [], songs: [libSong('s-sour', 'Sour Times')] })
    check('Behind: the next search draws at the library\'s moment - Top results from the library alone, every section with a slot for MusicBrainz\'s kinds',
      [topKeys(), kinds(), slotText('artists'), slotText('songs')], [['top:song:s-sour', 'top:album:nd-dummy', 'top:artist:ar1'], ['artists', 'albums', 'songs'], 'Asking MusicBrainz…', 'Asking MusicBrainz…'])
    invariant('Behind\'s draw')
    await advance(500)
    const behindAsked = newAsks(next)
    behindAsked.artists[0].resolve(ARTISTS_NONE)
    behindAsked.albums[0].resolve({ 'release-groups': [], count: 0 })
    behindAsked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    invariant('Behind\'s kinds landing')
    check('...kinds landing empty: Artists (no library rows, something below) keeps its slot saying why; Albums the same; Songs, last, loses its slot',
      [kinds(), slotText('artists'), slotText('albums'), slotOf('songs')],
      [['artists', 'albums', 'songs'], 'No artists on MusicBrainz for “sour times”.', 'No albums on MusicBrainz for “sour times”.', undefined])
    //? that search answered in time: Behind ends - the next draws by its moments again
    await search('sour', { artists: [], albums: [], songs: [libSong('s-sour', 'Sour Times')] })
    check('...that search answered in time: Behind ends - the next shows Top results and the asking line', [kinds(), asking().length], [[], 1])
    await advance(500)
    for (const ask of [asks.artists.at(-1), asks.musicbrainz.at(-1), asks.songs.at(-1)]) ask.resolve(ask === asks.artists.at(-1) ? ARTISTS_NONE : ask === asks.songs.at(-1) ? { recordings: [], count: 0 } : { 'release-groups': [], count: 0 })
    await answerOwned(holding(DUMMY))
  }


  const away = () => new MusicBrainzUnavailable('MusicBrainz is unreachable right now')
  const busy = () => new MusicBrainzUnavailable('MusicBrainz is busy just now - try again in a moment.', true)
  const refused = () => new ApiError(422, "MusicBrainz couldn't read that search - try other words", 'refused')

  console.log('\nMusicBrainz failing: per kind, all of them, busy, refused')
  {
    const from = await search('machine gun', { artists: [], albums: [ndDummy], songs: [] })
    await advance(500)
    const asked = newAsks(from)
    asked.artists[0].reject(away())
    asked.albums[0].resolve({ 'release-groups': [THIRD], count: 1 })
    asked.songs[0].resolve({ recordings: [recording('r-mg', 'Machine Gun', 'Portishead', '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11', THIRD)], count: 1 })
    await answerOwned(holding(DUMMY))
    invariant('one kind failed')
    const failed = slotOf('artists')
    check('one kind failed, the others answered: its own section, its slot one line with a text-button Try again (no foot block)',
      [kinds(), failed?.props.class, text(find(byClass('app-search-empty'), failed)[0]), text(find((node) => node.type === 'button', failed)[0]), find(byClass('app-search-foot')).length],
      [['artists', 'albums', 'songs'], 'app-search-slot is-row', "MusicBrainz isn't answering.", 'Try again', 0])
    const before = { albums: asks.musicbrainz.length, artists: asks.artists.length, songs: asks.songs.length }
    find((node) => node.type === 'button', failed)[0].props.onClick({ currentTarget: {} })
    draw()
    check('Try again asks only the failed kind again - and draws the list afresh for these words, following the moments',
      [asks.musicbrainz.length - before.albums, asks.artists.length - before.artists, asks.songs.length - before.songs, kinds(), asking().length],
      [0, 1, 0, [], 1])
    asks.artists.at(-1).resolve(ARTISTS_NONE)
    await answerOwned(holding(DUMMY))
    check('...its answer in: moment 2 again', kinds(), ['albums', 'songs'])

    //? every kind failing: one block at the foot - nothing can draw in above it later
    const all = await search('teardrop', { artists: [], albums: [ndDummy], songs: [] })
    await advance(500)
    const allAsked = newAsks(all)
    for (const ask of [allAsked.artists[0], allAsked.albums[0], allAsked.songs[0]]) ask.reject(away())
    await answerOwned(holding(DUMMY))
    invariant('every kind failed')
    const foot = find((node) => byClass('app-search-problem')(node) && byClass('app-search-foot')(node))[0]
    check('every kind asked failed by moment 2: one block at the foot - isn\'t answering, what\'s in your library is above, a full-width Try again',
      [kinds(), text(find((node) => node.type === 'p', foot)[0]), find((node) => node.type === 'button', foot)[0]?.props.class, said()],
      [['albums'], "MusicBrainz isn't answering just now - it often goes away for a few minutes. What's in your library is above.", 'app-button', "MusicBrainz isn't answering."])

    //? that turned Behind on; busy said as busy
    const busyFrom = await search('wandering star', { artists: [], albums: [], songs: [libSong('s-ws', 'Wandering Star')] })
    check('...which turned Behind on: the next search drawn at the library\'s moment, slots for MusicBrainz', kinds(), ['artists', 'albums', 'songs'])
    await advance(500)
    const busyAsked = newAsks(busyFrom)
    busyAsked.artists[0].reject(busy())
    busyAsked.albums[0].reject(busy())
    busyAsked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    invariant('busy')
    check('MusicBrainz shedding: its slots say busy, read from the 503\'s body (`busy`), never from its words', [slotText('artists'), slotText('albums')],
      ['MusicBrainz is busy just now - try again in a moment.Try again', 'MusicBrainz is busy just now - try again in a moment.Try again'])
    //? Try again while Behind is on follows its own moments: Top results decided, the asking line - not slots
    find((node) => node.type === 'button' && text(node) === 'Try again', slotOf('artists')).at(0).props.onClick({ currentTarget: {} })
    draw()
    check('Try again with Behind on follows its own moments: Top results and the asking line, no slots', [topKeys().length > 0, kinds(), asking().length], [true, [], 1])
    asks.artists.at(-1).resolve(ARTISTS_NONE)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [], count: 0 })
    await answerOwned(holding(DUMMY))

    //? refused: the words, no Try again, Behind left as it was, never "isn't answering"
    const refusedFrom = await search('ac/dc (', { artists: [], albums: [], songs: [] })
    await advance(500)
    const refusedAsked = newAsks(refusedFrom)
    for (const ask of [refusedAsked.artists[0], refusedAsked.albums[0], refusedAsked.songs[0]]) ask.reject(refused())
    await answerOwned(holding(DUMMY))
    check('a 422 with words: each kind\'s slot says them - no Try again - and no "isn\'t answering" foot',
      [kinds(), slotText('artists'), find((node) => node.type === 'button' && text(node) === 'Try again').length, find(byClass('app-search-foot')).length],
      [['artists', 'albums', 'songs'], "MusicBrainz couldn't read that search - try other words", 0, 0])
    check('...and the region says the refusal\'s words - never "MusicBrainz isn\'t answering." (late review)', said(), "MusicBrainz couldn't read that search - try other words")
  }

  console.log('\na text searched before: drawn whole at the library\'s moment, MusicBrainz asked nothing (kept answers)')
  {
    //? (Behind ended first: a search answered in time)
    const clear = await search('wild white horses', { artists: [], albums: [], songs: [] })
    await advance(500)
    const cleared = newAsks(clear)
    cleared.artists[0].resolve(ARTISTS_NONE)
    cleared.albums[0].resolve({ 'release-groups': [], count: 0 })
    cleared.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    const first = await search('nude', { artists: [], albums: [], songs: [libSong('s-nude', 'Nude', 'nd-irb', 'In Rainbows')] })
    await advance(500)
    const firstAsked = newAsks(first)
    firstAsked.artists[0].resolve(radioheadArtists)
    firstAsked.albums[0].resolve({ 'release-groups': [{ id: '00000000-0000-4000-8000-0000000000nd', title: 'Nude', 'primary-type': 'Single', 'first-release-date': '2008' }], count: 1 })
    firstAsked.songs[0].resolve({ recordings: [recording('r-nude', 'Nude', 'Radiohead', radioheadArtists.matches[0].mbid, { id: '00000000-0000-4000-8000-0000000000ir', title: 'In Rainbows', 'primary-type': 'Album', 'first-release-date': '2007' })], count: 1 })
    await answerOwned(holding(DUMMY))
    const firstDrawn = [topKeys(), kinds().map((kind) => [kind, keysOf(kind)])]
    //? backspace one letter's worth of searching away and back: another text, then "nude" again
    const other = await search('nudes', { artists: [], albums: [], songs: [] })
    await advance(500)
    const otherAsked = newAsks(other)
    otherAsked.artists[0].resolve(ARTISTS_NONE)
    otherAsked.albums[0].resolve({ 'release-groups': [], count: 0 })
    otherAsked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    const ownedAsks = asks.owned.length
    const again = await search('nude', { artists: [], albums: [], songs: [libSong('s-nude', 'Nude', 'nd-irb', 'In Rainbows')] })
    check('...the kept answers taken at the library\'s moment ask /library/owned again beside them, so their rows re-mark in place (late review)', asks.owned.length - ownedAsks, 1)
    check('"nude" again: Top results AND the sections, all at the library\'s moment - the list as it was drawn the first time, no place, no asking line',
      [[topKeys(), kinds().map((kind) => [kind, keysOf(kind)])], asking().length, find(byClass('app-search-top-place')).length], [firstDrawn, 0, 0])
    await advance(500)
    check('...and at the pause MusicBrainz is asked nothing', [newAsks(again).albums.length, newAsks(again).artists.length, newAsks(again).songs.length], [0, 0, 0])
  }

  console.log('\nthe library late, and Navidrome\'s status')
  {
    const from = await search('tom waits', null)
    await advance(500)
    const asked = newAsks(from)
    asked.artists[0].resolve(ARTISTS_NONE)
    asked.albums[0].resolve({ 'release-groups': [ROSELAND], count: 1 })
    asked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    check('MusicBrainz in, the library not: the previous words\' list still drawn - the new words\' rows never draw before the library has settled',
      [topKeys().includes('top:song:s-nude'), keysOf('albums').includes(`group:${ROSELAND.id}`)], [true, false])
    await advance(1000)
    freshInvariant()
    invariant('the library late')
    const placeKept = find((node) => byClass('app-search-slot')(node) && !find((n) => n.type === 'section', node).length)[0]
    check('LIBRARY_LATE_MS passed: drawn as if the library found nothing, one place kept at its top - "Searching your library…"',
      [text(placeKept), kinds()], ['Searching your library…', ['albums']])
    asks.library.at(-1).resolve({ artists: [{ id: 'ar-tw', name: 'Tom Waits', albumCount: 4 }], albums: [], songs: [] })
    await settle()
    draw()
    invariant('the library landing late')
    check('...its answer landing in that place: "1 in your library - Show them"', text(find(byClass('app-search-slot'))[0]), '1 in your library - Show them')
    const show = buttonText('1 in your library - Show them')
    show.props.onClick({ currentTarget: show })
    draw()
    check('...Show them: the list drawn afresh, whole - the library in it', [topKeys()[0], kinds()], ['top:artist:ar-tw', ['artists', 'albums']])

    //? Navidrome's status not known yet (the app's first check): no library ask, no spinner of its own, moment 1 waits for it
    draw({ status: null })
    const libraryAsks = asks.library.length
    const unknown = await search('massive attack', null)
    check('the status not known yet: the library not asked, no "Connecting" spinner, no gate - the list drawn before kept, moment 1 waiting for it',
      [asks.library.length - libraryAsks, find(byClass('pl-spinner')).length, find((node) => node.type === NeedsNavidrome).length, topKeys()[0]], [0, 0, 0, 'top:artist:ar-tw'])
    draw({ status })
    check('...the library asked the moment it says OK', asks.library.map((ask) => ask.text).slice(libraryAsks), ['massive attack'])
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await advance(500)
    for (const ask of Object.values(newAsks(unknown)).slice(0, 3)) ask[0]?.resolve(ask === newAsks(unknown).artists ? ARTISTS_NONE : { 'release-groups': [], recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))

    //? Navidrome away: its notice once, above the list - MusicBrainz's rows draw below it
    const down = { configured: true, ok: false, server: null, problem: 'connection refused' }
    draw({ status: down })
    const asksBefore = asks.library.length
    const awayFrom = await search('mezzanine', null)
    const gate = find((node) => node.type === NeedsNavidrome)[0]
    check('Navidrome away: its notice drawn once, above the list, with App\'s status and no children - the library not asked',
      [gate?.props.status === down, gate?.props.children, asks.library.length - asksBefore], [true, null, 0])
    await advance(500)
    const awayAsked = newAsks(awayFrom)
    awayAsked.artists[0].resolve(ARTISTS_NONE)
    awayAsked.albums[0].resolve({ 'release-groups': [{ id: '00000000-0000-4000-8000-00000000me22', title: 'Mezzanine', 'primary-type': 'Album', 'first-release-date': '1998' }], count: 1 })
    awayAsked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    check('...MusicBrainz still searched, its rows drawn: Top results and Albums MusicBrainz\'s alone', [topKeys(), kinds()],
      [['top:group:00000000-0000-4000-8000-00000000me22'], ['albums']])
    draw({ status })
  }

  console.log('\nunder three characters')
  {
    await search('po', { artists: [P], albums: [ndDummy], songs: [] })
    check('the library alone - MusicBrainz isn\'t asked - and the foot line where its rows would go; never "No results"',
      [topKeys(), text(find(byClass('app-search-foot'))[0]), find((node) => text(node) === 'No results for “po”').length], [['top:artist:ar1', 'top:album:nd-dummy'], 'Type a little more, or press Search, to ask MusicBrainz too.', 0])
    await advance(700)
    check('...nothing asked of MusicBrainz at the pause', asks.order.at(-1) !== undefined, true)
    const mbBefore = asks.musicbrainz.length
    enter()
    //? (2.0.0-player.56) what's saved is asked with it, and the fresh draw waits for its answer - milliseconds
    await settle()
    draw()
    check('Enter on words MusicBrainz hasn\'t been asked for: asked now, the list drawn afresh (its own moments)',
      [asks.musicbrainz.length - mbBefore, asks.musicbrainz.at(-1).query, kinds(), asking().length], [1, 'po', [], 1])
    asks.artists.at(-1).resolve(ARTISTS_NONE)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [], count: 0 })
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    await search('pq', { artists: [], albums: [], songs: [] })
    check('a one- or two-letter box finding nothing in the library: the foot line alone, no "No results"', [text(find(byClass('app-search-foot'))[0]), find((node) => /No results/.test(text(node))).length],
      ['Type a little more, or press Search, to ask MusicBrainz too.', 0])
    chip('Songs').props.onClick()
    draw()
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
    check('...a kind view the same: the foot line where MusicBrainz\'s rows would go', text(find(byClass('app-search-foot'))[0]), 'Type a little more, or press Search, to ask MusicBrainz too.')
    chip('All').props.onClick()
    draw()
  }


  console.log('\nthe kind views: Artists, Songs - and what each asks')
  {
    //? "portishead third": album-by-artist - the Artists view asks MusicBrainz nothing, and lists the artist the box named
    const from = await search('portishead third', { artists: [], albums: [], songs: [] })
    await advance(500)
    const asked = newAsks(from)
    check('"portishead third" in All: albums and songs fielded, no artists', [asked.artists.length, asked.albums.length, asked.songs.length], [0, 1, 1])
    asked.albums[0].resolve({ 'release-groups': [THIRD], count: 1 })
    asked.songs[0].resolve({ recordings: [], count: 0 })
    await settle()
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    check('...Artists in All led by the artist the box named (Navidrome needs every word, so its search found none)', keysOf('artists'), ['artist:ar1'])
    const artistAsks = asks.artists.length
    chip('Artists').props.onClick()
    draw()
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
    check('the Artists view under album-by-artist: the named artist as its library row, nothing asked of MusicBrainz, and no more said',
      [keysOf('artists'), asks.artists.length - artistAsks, find(byClass('app-asking'), sectionOf('app-search-artists')).length], [['artist:ar1'], 0, 0])
    chip('All').props.onClick()
    draw()

    //? "kanye west": the Artists view - MusicBrainz's artists, the library's Kanye West instead of Ye, More from MusicBrainz
    const kanyeLib = { id: 'ar-k', name: 'Kanye West', albumCount: 2, musicBrainzId: kanyeArtists.matches[0].mbid }
    asks.lists.length = 0
    const kanye = await search('kanye west', { artists: [kanyeLib], albums: [], songs: [] })
    chip('Artists').props.onClick()
    draw()
    check('a chip pressed after the pause\'s ask: its own search3 (artists, fifty), and nothing more of MusicBrainz yet', [asks.library.at(-1).page?.counts, newAsks(kanye).artists.length], [{ artistCount: 50, albumCount: 0, songCount: 0 }, 0])
    asks.library.at(-1).resolve({ artists: [kanyeLib], albums: [], songs: [] })
    await settle()
    draw()
    await advance(500)
    const kanyeAsked = newAsks(kanye)
    check('...the pause asks only the view\'s kind: artists', [kanyeAsked.artists.length, kanyeAsked.albums.length, kanyeAsked.songs.length], [1, 0, 0])
    kanyeAsked.artists[0].resolve({ ...kanyeArtists, count: 14 })
    await answerOwned(holding(DUMMY))
    check('the Artists view: your Kanye West (Ye is yours - by id), then MusicBrainz\'s, appended at the foot', rowsOf('artists').map(([title]) => title),
      ['Kanye West', '¥$', 'Kanye West Tribute Band', 'Kanye West & Hatsune Miku'])
    const more = find((node) => byClass('app-search-more')(node))[0]
    check('...More from MusicBrainz (MusicBrainz counts more)', text(more), 'More from MusicBrainz')
    more.props.onClick()
    draw()
    check('...which asks the next page of the same name by offset', [asks.artists.at(-1).name, asks.artists.at(-1).offset], ['kanye west', 4])
    asks.artists.at(-1).resolve({ matches: [{ mbid: '00000000-0000-4000-8000-0000000000k9', name: 'Kanye', disambiguation: '', country: '', type: '', matched_as: '' }], count: 14 })
    await settle()
    draw()
    check('...its page appended below, said', [rowsOf('artists').map(([title]) => title).at(-1), said()], ['Kanye', '1 more artist from MusicBrainz'])
    const rowMb = rowButton('mb-artist:00000000-0000-4000-8000-0000000000k9')
    rowMb.props.onClick()
    check('a MusicBrainz artist\'s tap: their page by MusicBrainz id (`mb:` - outside the Navidrome gate)', mbArtists.at(-1), { mbid: '00000000-0000-4000-8000-0000000000k9', name: 'Kanye' })
    rowButton('artist:ar-k').props.onClick()
    check('...a library artist\'s: their page by Navidrome id', artistsOpened.at(-1).id, 'ar-k')
    chip('All').props.onClick()
    draw()
    check('Back to All: everything at once, no phantom - the kind All needs and nobody asked for these words (albums: an artist you have, so no songs) in a slot',
      [topKeys()[0], kinds(), slotText('albums')], ['top:artist:ar-k', ['artists', 'albums'], 'Asking MusicBrainz…'])
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [], count: 0 })
    await answerOwned(holding(DUMMY))

    //? "roads portishead": the Songs view - its own search3, MusicBrainz's songs (the one you have dropped), More songs
    const roads = await search('roads portishead', { artists: [], albums: [], songs: [libSong('s-roads', 'Roads')] })
    chip('Songs').props.onClick()
    draw()
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [libSong('s-roads', 'Roads'), libSong('s-roads2', 'Roads (live)', 'nd-rose', 'Roseland NYC Live')] })
    await settle()
    draw()
    check('the Songs view\'s own search3: songs alone, a hundred; its first songs\' albums asked ahead, kept', [asks.library.at(-1).page.counts, asks.prefetch.slice(-2).map((ask) => [ask.id, ask.keep])],
      [{ artistCount: 0, albumCount: 0, songCount: 100 }, [['nd-dummy', true], ['nd-rose', true]]])
    await advance(500)
    const roadsAsked = newAsks(roads)
    check('...the pause asks songs only', [roadsAsked.songs.length, roadsAsked.albums.length, roadsAsked.artists.length], [1, 0, 0])
    roadsAsked.songs[0].resolve({ ...roadsRecorded, recordings: [...roadsRecorded.recordings, recording('r-other', 'Roads (Max Cooper remix)', 'Portishead', '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11', SOMEONE_ALBUM)], count: 60 })
    await answerOwned(holding(DUMMY))
    check('the Songs view: yours, then MusicBrainz\'s - its Roads dropped (yours is it), the remix kept - then More songs',
      [keysOf('songs'), text(find(byClass('app-search-more'))[0])], [['song:s-roads', 'song:s-roads2', 'mb-song:8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11\nroads (max cooper remix)'], 'More songs'])
    find(byClass('app-search-more'))[0].props.onClick()
    draw()
    check('...More songs asks the next page by offset', asks.songs.at(-1).offset, 13)
    const OTHER_ALBUM = { id: '00000000-0000-4000-8000-0000000000a2', title: 'Dub Album', 'primary-type': 'Album', 'first-release-date': '2003' }
    asks.songs.at(-1).resolve({ recordings: [recording('r-new', 'Roads (Dub)', 'Portishead', '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11', OTHER_ALBUM)], count: 60 })
    await settle()
    draw()
    check('...merged in below, said', [keysOf('songs').at(-1), said()], ['mb-song:8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11\nroads (dub)', '1 more song from MusicBrainz'])
    //? Get on a song row: the album it names, on a pressing with the song
    const remixKey = 'mb-song:8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11\nroads (max cooper remix)'
    const get = getOf(remixKey)
    check('a MusicBrainz song\'s Get names its album and the song', get?.props['aria-label'], "Get Somebody's Album, with Roads (Max Cooper remix)")
    get.props.onClick({ currentTarget: { chip: 'song' } })
    draw()
    check('...a tap asks for the album\'s pressings, the chip busy and aria-disabled - never disabled', [asks.pressings.at(-1).id, text(getOf(remixKey)), getOf(remixKey).props['aria-busy'], getOf(remixKey).props['aria-disabled'], getOf(remixKey).props.disabled],
      [SOMEONE_ALBUM.id, 'Get…', true, true, undefined])
    const track = (title, recordingId) => ({ title, position: 1, length: 240000, recording: { id: recordingId, title, length: 240000 } })
    asks.pressings.at(-1).resolve({ id: SOMEONE_ALBUM.id, problem: null, releases: [
      { id: 'rel-usual', title: 'Somebody\'s Album', status: 'Official', date: '2001-01-01', country: 'GB', media: [{ format: 'CD', position: 1, tracks: [track('Other Song', 'x-1')] }], 'release-group': { id: SOMEONE_ALBUM.id, title: 'Somebody\'s Album', 'first-release-date': '2001-01-01' }, 'artist-credit': [{ name: 'Somebody', artist: { id: SOMEBODY, name: 'Somebody' } }] },
      { id: 'rel-other', title: 'Somebody\'s Album', status: 'Official', date: '2001-01-01', country: 'GB', media: [{ format: 'CD', position: 1, tracks: [track('Other Song', 'x-1')] }], 'release-group': { id: SOMEONE_ALBUM.id, title: 'Somebody\'s Album', 'first-release-date': '2001-01-01' }, 'artist-credit': [{ name: 'Somebody', artist: { id: SOMEBODY, name: 'Somebody' } }] },
      { id: 'rel-with', title: 'Somebody\'s Album', status: 'Official', date: '2002-01-01', country: 'JP', media: [{ format: 'CD', position: 1, tracks: [track('Roads (Max Cooper remix)', 'r-other')] }], 'release-group': { id: SOMEONE_ALBUM.id, title: 'Somebody\'s Album', 'first-release-date': '2001-01-01' }, 'artist-credit': [{ name: 'Somebody', artist: { id: SOMEBODY, name: 'Somebody' } }] },
    ] })
    await settle()
    draw()
    check('...Sources opened on the pressing WITH the song, the group (and its year) from the pressings, the opener taken in the tap',
      [gets.at(-1)[0].release.release_mbid, gets.at(-1)[0].release.year, gets.at(-1)[0].subtitle, gets.at(-1)[1], text(getOf(remixKey))],
      ['rel-with', '2002', "Somebody's Album · CD · 2002 · JP", { chip: 'song' }, 'Get'])
    check('...the album\'s own year the group\'s, from the pressings (a recording search\'s group has none): what the folder is named by', gets.at(-1)[0].release.original_year, '2001')
    const pressingAsks = asks.pressings.length, getsBefore = gets.length
    getOf(remixKey).props.onClick({ currentTarget: {} })
    await settle()
    check('...the pressings kept for the session: another tap asks nothing, and opens at once', [asks.pressings.length - pressingAsks, gets.length - getsBefore, gets.at(-1)[0].release.release_mbid],
      [0, 1, 'rel-with'])
    //? MusicBrainz unable to list the pressings: the album page opens instead, the song marked, its Get taking over
    const opens = songAlbums.length, getsNow = gets.length
    const dubKey = 'mb-song:8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11\nroads (dub)'
    getOf(dubKey).props.onClick({ currentTarget: {} })
    asks.pressings.at(-1).reject(away())
    await settle()
    draw()
    check('...MusicBrainz unable to list them: the album page opens instead, the song marked - never a download filed without a year',
      [asks.pressings.at(-1).id, songAlbums.length - opens, songAlbums.at(-1), gets.length - getsNow, text(getOf(dubKey))],
      [OTHER_ALBUM.id, 1, [{ id: OTHER_ALBUM.id, title: 'Dub Album' }, ['r-new']], 0, 'Get'])

    //? the Songs view for an artist's name alone: MusicBrainz is asked no songs
    const alone = await search('portishead', { artists: [P], albums: [], songs: [] })
    asks.library.slice(alone.library).find((ask) => ask.page).resolve({ artists: [], albums: [], songs: [libSong('s-roads', 'Roads')] })
    await settle()
    draw()
    check('the Songs view for an artist\'s name alone: their songs in your library, then how to find theirs on MusicBrainz',
      [keysOf('songs'), text(find(byClass('app-search-foot'))[0])], [['song:s-roads'], "Type a song's title with the artist (“roads portishead”) to find their songs on MusicBrainz."])
    chip('All').props.onClick()
    draw()
  }


  console.log('\nfocus handed on as a control its own tap takes away goes (on the stand-in DOM: only what is drawn is found)')
  {
    const from = await search('only you', { artists: [], albums: [ndDummy], songs: [libSong('s-ou', 'Only You')] })
    await advance(500)
    const asked = newAsks(from)
    asked.artists[0].resolve(ARTISTS_NONE)
    asked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    await advance(1500)
    asked.albums[0].resolve({ 'release-groups': [THIRD], count: 1 })
    await answerOwned(holding(DUMMY))
    dom.use()
    dom.press(buttonText('Show 1 album from MusicBrainz'))
    check('Show N tapped from the keyboard: focus to the first row it brought', [dom.focused, document.activeElement?.key], [[`row:group:${THIRD.id}`], `row:group:${THIRD.id}`])
    //? a finger's tap on WebKit gives the control no focus: focus left alone, so the page isn't scrolled
    const second = await search('only you!', { artists: [], albums: [ndDummy], songs: [libSong('s-ou', 'Only You')] })
    await advance(500)
    const secondAsked = newAsks(second)
    secondAsked.artists[0].resolve(ARTISTS_NONE)
    secondAsked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    await advance(1500)
    secondAsked.albums[0].resolve({ 'release-groups': [ROSELAND], count: 1 })
    await answerOwned(holding(DUMMY))
    dom.use()
    const tapped = buttonText('Show 1 album from MusicBrainz')
    tapped.props.onClick({ currentTarget: dom.el(tapped) })
    draw()
    check('...tapped by a finger (WebKit focuses nothing): focus left alone', [dom.focused, document.activeElement === dom.body], [[], true])
    //? Try again from the keyboard: its redraw comes a render after the tap - the hand waits for the button to go (review:
    //? it was spent on the old draw, and focus fell to the body as the button went); at moment 1 its section isn't drawn
    //? yet, so Top results' heading, the list's first - never the body
    const failing = await search('only yours', { artists: [{ id: 'ar-oy', name: 'Only Yours', albumCount: 1 }], albums: [ndDummy], songs: [] })
    await advance(500)
    const failingAsked = newAsks(failing)
    //? (an artist you have: no songs asked)
    failingAsked.artists[0].reject(away())
    failingAsked.albums[0].resolve({ 'release-groups': [], count: 0 })
    await answerOwned(holding(DUMMY))
    dom.use()
    dom.press(find((node) => node.type === 'button' && text(node) === 'Try again', slotOf('artists'))[0])
    check('Try again from the keyboard: the button gone, focus to the heading the new draw holds - Top results\' at moment 1 - never the body',
      [dom.focused, document.activeElement?.key, asking().length], [['#app-search-top'], '#app-search-top', 1])
    asks.artists.at(-1).resolve(ARTISTS_NONE)
    await answerOwned(holding(DUMMY))
    //? with no heading drawn at all yet (nothing in the library: no Top results at moment 1), the hand waits for the draw
    //? that brings one - its own section's, at moment 2
    const bare = await search('only you??', { artists: [], albums: [], songs: [] })
    await advance(500)
    const bareAsked = newAsks(bare)
    bareAsked.artists[0].reject(away())
    bareAsked.albums[0].resolve({ 'release-groups': [THIRD], count: 1 })
    bareAsked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    dom.use()
    dom.press(find((node) => node.type === 'button' && text(node) === 'Try again', slotOf('artists'))[0])
    check('...no heading drawn yet at moment 1: nothing focused, the hand kept (focus on the body for now)', [dom.focused, top(), document.activeElement === dom.body], [[], undefined, true])
    asks.artists.at(-1).resolve(portisheadArtists)
    await answerOwned(holding(DUMMY))
    check('...then, at moment 2, its own section\'s heading', dom.focused, ['#app-search-artists'])
    //? every kind failing: the foot's Try again the same way
    const allFail = await search('only you!!', { artists: [], albums: [ndDummy], songs: [] })
    await advance(500)
    for (const ask of Object.values(newAsks(allFail)).slice(0, 3)) ask[0]?.reject(away())
    await answerOwned(holding(DUMMY))
    dom.use()
    dom.press(find((node) => node.type === 'button' && text(node) === 'Try again', find((node) => byClass('app-search-problem')(node) && byClass('app-search-foot')(node))[0])[0])
    check('the all-failed foot\'s Try again from the keyboard: no heading at moment 1 (a phantom first), so the hand waits', dom.focused, [])
    for (const ask of [asks.artists.at(-1), asks.musicbrainz.at(-1), asks.songs.at(-1)]) ask.resolve(ask === asks.artists.at(-1) ? ARTISTS_NONE : ask === asks.songs.at(-1) ? { recordings: [], count: 0 } : { 'release-groups': [], count: 0 })
    await answerOwned(holding(DUMMY))
    check('...then Top results\' heading as moment 2 draws it - never the body', dom.focused, ['#app-search-top'])
    //? the library's Show them: the first row it brought
    const lateLib = await search('only us', null)
    await advance(500)
    for (const ask of Object.values(newAsks(lateLib)).slice(0, 3)) ask[0]?.resolve(ask === newAsks(lateLib).artists ? ARTISTS_NONE : { 'release-groups': [], recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    await advance(1000)
    asks.library.at(-1).resolve({ artists: [], albums: [ndDummy], songs: [] })
    await settle()
    draw()
    dom.use()
    dom.press(buttonText('1 in your library - Show them'))
    check('the library\'s Show them from the keyboard: focus to the first row it brought', dom.focused, ['row:top:album:nd-dummy'])
    dom.leave()
  }

  console.log('\nthe desktop frame: Top results as six tiles, kept as drawn')
  {
    globalThis.__search.frame = 'desktop'
    draw()
    const from = await search('massive live', { artists: [P], albums: [ndDummy, { id: 'nd-rose', name: 'Roseland NYC Live', artist: 'Portishead', artistId: 'ar1', year: 1998 }], songs: [libSong('s-roads', 'Roads'), libSong('s-sour', 'Sour Times'), libSong('s-glory', 'Glory Box')] })
    await advance(500)
    const asked = newAsks(from)
    asked.artists[0].resolve(ARTISTS_NONE)
    asked.albums[0].resolve({ 'release-groups': [ROSELAND, THIRD], count: 2 })
    asked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    const tiles = find(byClass('app-top-tile'))
    check('on a desktop, up to six tinted lockups three across - each with the place on its own third line', [find(byClass('app-top-tiles')).length, tiles.length,
      find(byClass('app-top-place'), top()).map(text)], [1, 6, ['In your library', 'In your library', 'In your library', 'In your library', 'In your library', 'On MusicBrainz']])
    check('...and the sections\' previews the desktop\'s: albums 4 + 4', keysOf('albums').length, 4)
    //? (2.0.0-player.57 review) a song's tile has no room beside its cover and ▶ for a •••: the Songs row below has it
    const songTiles = tiles.filter((tile) => find((node) => typeof node.props?.['aria-label'] === 'string' && /^Play /.test(node.props['aria-label']), tile).length || /Roads|Sour Times|Glory Box/.test(text(tile)))
    check('...a song\'s tile carries no •••; the same song\'s row in Songs does', [songTiles.length > 0, find(byClass('app-row-more'), top()).length, find(byClass('app-row-more'), sectionOf('app-search-songs')).length > 0], [true, 0, true])
    globalThis.__search.frame = 'phone'
    draw()
    check('the window crossing to a phone after the draw: the list kept as drawn - six, tiles - until the next text redraws it', [find(byClass('app-top-tile')).length, topKeys().length], [6, 6])
  }

  console.log('\nlogins on, a library of your own: yours first, then the store\'s')
  {
    Session.setSessionMe({ user: 'ethan', admin: false, auth: 'on', version: '2.0.0-player.55' })
    draw()
    check('your albums asked as Search shows with a library of your own', asks.yours.length, 1)
    asks.yours[0].resolve([ndDummy])
    await settle()
    draw()
    const ndThird = { id: 'nd-third', name: 'Third', artist: 'Portishead', artistId: 'ar1', year: 2008, musicBrainzId: 'rel-third' }
    const storeOwned = { albums: [{ path: 'Portishead/Dummy', artist: 'Portishead', album: 'Dummy', release_group_mbid: DUMMY.id, release_mbid: 'rel-dummy', yours: true },
      { path: 'Portishead/Third', artist: 'Portishead', album: 'Third', release_group_mbid: THIRD.id, release_mbid: 'rel-third', yours: false }] }
    const from = await search('bristol albums', { artists: [P], albums: [ndThird, ndDummy], songs: [libSong('s-mg', 'Machine Gun', 'nd-third', 'Third')] })
    const atTheLibrary = said()
    await advance(500)
    const asked = newAsks(from)
    asked.artists[0].resolve(ARTISTS_NONE)
    asked.albums[0].resolve({ 'release-groups': [], count: 0 })
    asked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(storeOwned)
    check('the store\'s rows, yours first - Dummy (yours) before Third (in the store), each saying so', rowsOf('albums'),
      [['Dummy', 'Portishead · 1994 · in your library'], ['Third', 'Portishead · 2008 · in the store']])
    check('...a song by its album: on Third, "in the store"', rowsOf('songs'), [['Machine Gun', 'Portishead · Third · in the store']])
    check('...an artist\'s count your own', rowsOf('artists'), [['Portishead', '1 album in your library']])
    check('...the region says the store at the library\'s moment', atTheLibrary, 'In the store: 1 artist, 2 albums, 1 song.')
    //? an Add on Third's page: your albums asked again, and the rows re-marked in place - never moved
    globalThis.__search.generation += 1
    draw()
    check('an Add (your albums\' generation moving): your albums asked again', asks.yours.length, 2)
    asks.yours[1].resolve([ndDummy, ndThird])
    await settle()
    draw()
    check('...Third now "in your library", in its place: nothing re-sorted', rowsOf('albums'),
      [['Dummy', 'Portishead · 1994 · in your library'], ['Third', 'Portishead · 2008 · in your library']])
    check('...the hint before typing, with a library of your own', (() => { type(''); return text(find(byClass('app-search-hint'))[0]) })(),
      "Artists, albums and songs: yours first, then the store's, then MusicBrainz's.")
    Session.setSessionMe(null)
    draw()
  }


  console.log('\nGet on a MusicBrainz album (2.0.0-player.15): the usual pressing, in the Sources sheet')
  {
    const from = await search('roseland nyc', { artists: [], albums: [], songs: [] })
    await advance(500)
    const asked = newAsks(from)
    asked.artists[0].resolve(ARTISTS_NONE)
    asked.albums[0].resolve({ 'release-groups': [ROSELAND, THIRD], count: 2 })
    asked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY, THIRD))
    check('You > Getting albums asked as the tab shows', globalThis.__search.settingsAsked.at(-1), true)
    const chipOf = (group) => getOf(`group:${group.id}`)
    check('a row the library holds has no Get; one it doesn\'t has, beside the row\'s own button', [chipOf(THIRD), text(chipOf(ROSELAND)), chipOf(ROSELAND)?.props['aria-label']], [undefined, 'Get', 'Get Roseland NYC Live'])
    const track = (title, position) => ({ title, position, length: 300000 + position, recording: { title, length: 300000 + position, video: false } })
    const PRESSINGS = [
      { id: 'r-vinyl', title: 'Roseland NYC Live', status: 'Official', date: '1998-11-09', country: 'GB', media: [{ format: '12" Vinyl', position: 1, tracks: [track('Humming', 1), track('Cowboys', 2)] }] },
      { id: 'r-cd', title: 'Roseland NYC Live', status: 'Official', date: '1998-11-02', country: 'GB', 'label-info': [{ 'catalog-number': '559 424-2', label: { name: 'Go! Beat' } }], media: [{ format: 'CD', position: 1, tracks: [track('Humming', 1), track('Cowboys', 2)] }] },
    ]
    const tap = () => chipOf(ROSELAND).props.onClick({ currentTarget: { chip: true } })
    const getsBefore = gets.length
    tap()
    draw()
    check('a tap asks for the album\'s pressings, the chip busy meanwhile', [asks.pressings.at(-1)?.id, text(chipOf(ROSELAND)), chipOf(ROSELAND).props['aria-busy']], [ROSELAND.id, 'Get…', true])
    const first = asks.pressings.at(-1)
    tap()
    check('a second tap calls the first ask off', first.signal.aborted, true)
    await settle()
    asks.pressings.at(-1).reject(away())
    await settle()
    draw()
    check('MusicBrainz failing: the album as a whole, said so', [gets.length - getsBefore, gets.at(-1)[0].release.release_mbid, gets.at(-1)[0].subtitle, gets.at(-1)[1]?.chip, text(chipOf(ROSELAND))],
      [1, null, 'Roseland NYC Live · the album as a whole', true, 'Get'])
    tap()
    asks.pressings.at(-1).resolve({ id: ROSELAND.id, releases: PRESSINGS, problem: null })
    await settle()
    check('the usual pressing - a CD over the vinyl - built from the row\'s group', [gets.at(-1)[0].release.release_mbid, gets.at(-1)[0].release.release_group_mbid, gets.at(-1)[0].subtitle],
      ['r-cd', ROSELAND.id, 'Roseland NYC Live · CD · 1998 · GB · Go! Beat'])
    const asksNow = asks.pressings.length
    tap()
    await settle()
    check('kept for the session: another tap asks nothing, and opens at once', [asks.pressings.length - asksNow, gets.at(-1)[0].release.release_mbid], [0, 'r-cd'])
    //? a lookup still out when the tab's root stops showing, or the box changes: called off, opening nothing
    const GLORY = { id: '00000000-0000-4000-8000-0000000000aa', title: 'Glory Times', 'primary-type': 'Album', 'first-release-date': '1995' }
    const other = await search('glory times', { artists: [], albums: [], songs: [] })
    await advance(500)
    const otherAsked = newAsks(other)
    otherAsked.artists[0].resolve(ARTISTS_NONE)
    otherAsked.albums[0].resolve({ 'release-groups': [GLORY], count: 1 })
    otherAsked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    globalThis.__search.abortRejects = false
    const opened0 = gets.length
    getOf(`group:${GLORY.id}`).props.onClick({ currentTarget: {} })
    draw()
    const out = asks.pressings.at(-1)
    draw({ active: false })
    check('the tab\'s root no longer what shows: the lookup called off, the chip Get again', [out.signal.aborted, text(getOf(`group:${GLORY.id}`))], [true, 'Get'])
    out.resolve({ id: GLORY.id, releases: PRESSINGS.slice(0, 1), problem: 'MusicBrainz failed part way' })
    await settle()
    check('...its answer, landing anyway, opens no sheet over what you went to', gets.length, opened0)
    draw({ active: true })
    getOf(`group:${GLORY.id}`).props.onClick({ currentTarget: {} })
    draw()
    const typed = asks.pressings.at(-1)
    type('glory times!')
    check('the box changed: the lookup called off too', typed.signal.aborted, true)
    typed.resolve({ id: GLORY.id, releases: PRESSINGS, problem: null })
    await settle()
    check('...its answer opening nothing', gets.length, opened0)
    globalThis.__search.abortRejects = true
    await advance(200)
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await advance(500)
  }

  console.log('\nsong search\'s own (2.0.0-player.53): the disclosure, and an album you have opening the album you have')
  {
    const UK_CD = '87888070-1b25-4830-aebc-dee490058b74'
    //? (the answers kept from the earlier "roads portishead" let go, so these are asked)
    forgetAnswers()
    const from = await search('roads portishead', { artists: [], albums: [], songs: [] })
    await advance(500)
    const asked = newAsks(from)
    asked.albums[0].resolve({ 'release-groups': [ROSELAND], count: 1 })
    asked.songs[0].resolve(roadsRecorded)
    void Owned.refreshOwned()
    await answerOwned(byGroup(DUMMY))
    const songsSection = () => sectionOf('app-search-songs')
    const songRows = () => find(byClass('app-song-row'), songsSection()).map((row) => [text(find(byClass('app-result-title'), row)[0]), lineOf(row)])
    const songButton = (n = 0) => find(byClass('app-song-row'), songsSection())[n]
    const albumsOf = (n = 0) => find(byClass('app-song-album'), find(byClass('app-song'), songsSection())[n]).map((row) => [text(find(byClass('app-result-title'), row)[0]), lineOf(row)])
    const listOf = (node) => find((each) => each.props?.id === node.props['aria-controls'])[0]
    const fold = () => find(byClass('app-song-fold'), songsSection())[0]
    const row = (title) => find(byClass('app-song-album'), songsSection()).find((node) => text(find(byClass('app-result-title'), node)[0]) === title)
    check('every take of Roads one song, Dummy held (by its group) - its line\'s place in its own span', songRows(), [['Roads', 'Portishead · 4:56 · Dummy · in your library']])
    check('...a disclosure, closed - with no Get (held with the song)', [songButton().props['aria-expanded'], listOf(songButton()).props.hidden, getOf(songButton().props['data-row'])], [false, true, undefined])
    songButton().props.onClick()
    draw()
    check('tapped: open, Dummy listed, the rest behind one fold', [songButton().props['aria-expanded'], albumsOf(), text(fold())],
      [true, [['Dummy', 'Album · 1994 · in your library']], 'On 12 compilations, live albums and broadcasts'])
    fold().props.onClick()
    draw()
    check('...the fold opened: every one listed after Dummy', [fold().props['aria-expanded'], albumsOf().length], [true, 13])
    fold().props.onClick()
    draw()
    songButton().props.onClick()
    draw()
    check('...each tapped again: closed', [songButton().props['aria-expanded'], listOf(songButton()).props.hidden], [false, true])
    songButton().props.onClick()
    draw()
    fold().props.onClick()
    draw()
    row('Roseland NYC Live').props.onClick()
    check('an album you don\'t have opens on its page, with the song\'s recordings on it', songAlbums.at(-1),
      [{ id: 'ce61f4a8-db95-3608-93de-53f9ecb1b8d2', title: 'Roseland NYC Live' }, ['63f3cb71-10d1-40a3-91f6-b682cf47c85b']])
    const fetches = []
    const fetchBefore = globalThis.fetch
    globalThis.fetch = (url, init) => new Promise((resolve, reject) => {
      fetches.push({ url, answer: (body) => resolve({ ok: true, status: 200, json: async () => body }),
        fail: () => resolve({ ok: false, status: 500, json: async () => ({ detail: 'deadwax had a problem' }) }) })
      init?.signal?.addEventListener('abort', () => { const error = new Error('aborted'); error.name = 'AbortError'; reject(error) })
    })
    void Owned.refreshOwned()
    await answerOwned({ albums: [{ path: 'Portishead/Dummy', artist: 'Portishead', album: 'Dummy', release_group_mbid: DUMMY.id, release_mbid: UK_CD }] })
    draw()
    row('Dummy').props.onClick()
    draw()
    check('one you have: the id bridge asked about the release you hold, the row busy meanwhile', [fetches.length, fetches[0]?.url.includes(`release_mbid=${UK_CD}`), row('Dummy').props['aria-busy']], [1, true, true])
    fetches[0].answer({ navidrome_id: 'nd-dummy' })
    await settle()
    draw()
    check('...then the album you have, credited', [opened.at(-1), row('Dummy').props['aria-busy']], [{ id: 'nd-dummy', name: 'Dummy', artist: 'Portishead' }, false])
    const opensNow = songAlbums.length
    row('Dummy').props.onClick()
    fetches.at(-1).answer({ navidrome_id: null })
    await settle()
    draw()
    check('...Navidrome hasn\'t found it: the album you don\'t have, with the song\'s recordings', [songAlbums.length - opensNow, songAlbums.at(-1)[0].title, songAlbums.at(-1)[1]],
      [1, 'Dummy', ['ef37de8d-8fab-42ed-82da-fbfe25715989']])
    row('Dummy').props.onClick()
    fetches.at(-1).fail()
    await settle()
    draw()
    check('...the bridge failing: the same', [songAlbums.length - opensNow, row('Dummy').props['aria-busy']], [2, false])
    //? a pressing of Dummy the search didn't find Roads on - its 1994 CD: "a pressing in your library", and its tap looks first
    const CD_1994 = '76df3287-6cda-33eb-8e9a-044b5e15ffdd'
    const roadsOn = (id, recordingId, title = 'Roads') => ({ id, title: 'Dummy', status: 'Official', date: '1994-08-22',
      media: [{ format: 'CD', position: 1, tracks: [{ number: '8', position: 8, title, length: 302000, recording: { id: recordingId, title } }] }] })
    void Owned.refreshOwned()
    await answerOwned({ albums: [{ path: 'Portishead/Dummy (1994)', artist: 'Portishead', album: 'Dummy', release_group_mbid: DUMMY.id, release_mbid: CD_1994 }] })
    draw()
    check('a pressing held that nothing says has the song: the row claims nothing (and offers Get), Dummy\'s line says "a pressing in your library"',
      [songRows()[0][1], albumsOf()[0][1], text(getOf(songButton().props['data-row']))], ['Portishead · 4:56 · Dummy', 'Album · 1994 · a pressing in your library', 'Get'])
    const pressingAsks = asks.pressings.length, bridgeAsks = fetches.length
    row('Dummy').props.onClick()
    draw()
    check('...its tap asks for the album\'s pressings first, the row busy - the id bridge asked nothing yet', [asks.pressings.length - pressingAsks, asks.pressings.at(-1).id, row('Dummy').props['aria-busy'], fetches.length - bridgeAsks],
      [1, DUMMY.id, true, 0])
    asks.pressings.at(-1).resolve({ id: DUMMY.id, problem: null, releases: [roadsOn(UK_CD, 'ef37de8d-8fab-42ed-82da-fbfe25715989'), roadsOn(CD_1994, '8a49dba0-253a-4535-b87f-78bb035336ce')] })
    await settle()
    draw()
    check('...the 1994 CD\'s tracklist has Roads: the id bridge asked about THAT CD', [fetches.length - bridgeAsks, fetches.at(-1).url.includes(`release_mbid=${CD_1994}`)], [1, true])
    fetches.at(-1).answer({ navidrome_id: 'nd-dummy-94' })
    await settle()
    draw()
    check('...then the album you have; its pressings kept, so the song now reads held', [opened.at(-1).id, songRows()[0][1], albumsOf()[0][1]],
      ['nd-dummy-94', 'Portishead · 4:56 · Dummy · in your library', 'Album · 1994 · in your library'])
    //? a look still out, the box changing: called off, opening nothing
    const ONLY_WE = '5c6c3376-856f-4cc7-8c9f-87613eb07d41'
    void Owned.refreshOwned()
    await answerOwned({ albums: [{ path: 'Portishead/Only We', artist: 'Portishead', album: 'Only We', release_group_mbid: ONLY_WE, release_mbid: 'eeeeeeee-0000-4000-8000-000000000002' }] })
    draw()
    const before = [songAlbums.length, opened.length]
    row('Only We').props.onClick()
    const look = asks.pressings.at(-1)
    check('(asked for Only We\'s pressings)', look.id, ONLY_WE)
    type('roads portishead!!')
    await settle()
    check('...called off as the box changes - nothing opened', [look.signal.aborted, songAlbums.length - before[0], opened.length - before[1]], [true, 0, 0])
    globalThis.fetch = fetchBefore
    void Owned.refreshOwned()
    await answerOwned(holding(DUMMY))
    await advance(200)
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await advance(500)
  }

  console.log('\nthe rest of the moments: no results, an empty late kind going, a superseded search, a refusal, "va"')
  {
    const answerAll = (from, albums = { 'release-groups': [], count: 0 }, songs = { recordings: [], count: 0 }, artists = ARTISTS_NONE) => {
      const asked = newAsks(from)
      asked.artists[0]?.resolve(artists)
      asked.albums[0]?.resolve(albums)
      asked.songs[0]?.resolve(songs)
    }
    const none = await search('zzyzx qwerty', { artists: [], albums: [], songs: [] })
    await advance(500)
    answerAll(none)
    await answerOwned(holding(DUMMY))
    check('no results - the library found nothing and every kind asked answered empty: "No results for “…”", and what to do',
      find(byClass('app-search-foot')).map((node) => text(node)), ['No results for “zzyzx qwerty”Check the spelling or try a new search.'])
    chip('Albums').props.onClick()
    draw()
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
    check('...in a kind view: "No albums for “…”."', text(find(byClass('app-search-foot')).at(-1)), 'No albums for “zzyzx qwerty”.')
    chip('All').props.onClick()
    draw()

    //? a superseded search counts for nothing: Behind stays off
    const superseded = await search('aphex', { artists: [], albums: [], songs: [] })
    await advance(500)
    check('(a search asked of MusicBrainz)', newAsks(superseded).albums.length, 1)
    const next = await search('aphex twin', { artists: [], albums: [], songs: [] })
    await advance(500)
    check('a search superseded before its cap - you typed on - calls its asks off and turns no Behind on', newAsks(superseded).albums[0].signal.aborted, true)
    answerAll(next)
    await answerOwned(holding(DUMMY))
    await search('aphex twin selected', { artists: [], albums: [], songs: [libSong('s-x', 'Xtal', 'nd-saw', 'Selected Ambient Works')] })
    check('...the next draws by its moments (Top results and the asking line), not Behind\'s slots', [kinds(), asking().length], [[], 1])
    await advance(500)
    answerAll(newAsks({ library: 0, albums: asks.musicbrainz.length - 1, artists: asks.artists.length - 1, songs: asks.songs.length - 1, order: 0 }))
    await answerOwned(holding(DUMMY))

    //? a refusal: the words, no Try again - and Behind left as it was (off)
    const refusedFrom = await search('ac/dc ((', { artists: [], albums: [], songs: [] })
    await advance(500)
    const refusedAsked = newAsks(refusedFrom)
    refusedAsked.artists[0].resolve(ARTISTS_NONE)
    refusedAsked.albums[0].reject(refused())
    refusedAsked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    await search('acdc', { artists: [], albums: [], songs: [libSong('s-tnt', 'TNT', 'nd-hv', 'High Voltage')] })
    check('a refused search (a 422) turns no Behind on: the next draws by its moments', [kinds(), asking().length], [[], 1])
    await advance(500)
    answerAll(newAsks({ library: 0, albums: asks.musicbrainz.length - 1, artists: asks.artists.length - 1, songs: asks.songs.length - 1, order: 0 }))
    await answerOwned(holding(DUMMY))

    //? "va": Various Artists - today's query, unfiltered, no studio line
    const va = await search('va', { artists: [], albums: [], songs: [] })
    enter()
    const vaAsked = newAsks(va)
    check('"va" reads as Various Artists: asked unfiltered - never the studio clause (its records are compilations by nature)', vaAsked.albums.map((ask) => ask.query), ['artist:"Various Artists"'])
    vaAsked.albums[0].resolve({ 'release-groups': [{ id: '00000000-0000-4000-8000-0000000000c1', title: 'Pure Moods', 'primary-type': 'Album', 'secondary-types': ['Compilation'], 'first-release-date': '1994' }], count: 1 })
    vaAsked.artists[0]?.resolve(ARTISTS_NONE)
    await answerOwned(holding(DUMMY))
    check('...and no studio line under its albums', find(byClass('app-search-filter-note')).length, 0)

    //? Behind on, a late kind with no library rows landing empty and last: its section goes, head and all
    const lateFrom = await search('zz top', { artists: [], albums: [], songs: [] })
    await advance(500)
    const lateAsked = newAsks(lateFrom)
    lateAsked.artists[0].resolve(ARTISTS_NONE)
    lateAsked.albums[0].resolve({ 'release-groups': [{ id: '00000000-0000-4000-8000-0000000000e1', title: 'Eliminator', 'primary-type': 'Album', 'first-release-date': '1983' }], count: 1 })
    await answerOwned(holding(DUMMY))
    await advance(1500)
    check('(the songs past the cap: a Songs section with only its slot)', [kinds(), slotText('songs'), keysOf('songs')], [['albums', 'songs'], 'Asking MusicBrainz…', []])
    lateAsked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    invariant('an empty late kind, last')
    check('a late kind landing empty, nothing tappable below, no library rows: its section goes, head and all', kinds(), ['albums'])
  }

  console.log('\nthe studio line decided with the sections - never added under Albums as its late answer lands (the real page found it)')
  {
    forgetAnswers()
    const from = await search('portishead', { artists: [P], albums: [ndDummy], songs: [libSong('s-roads', 'Roads')] })
    await advance(500)
    const asked = newAsks(from)
    asked.artists[0].resolve(portisheadArtists)
    await answerOwned(holding(DUMMY))
    await advance(1500)
    invariant('the cap, albums out')
    const note = () => find(byClass('app-search-filter-note')).map(text)
    check('albums late at the cap: Albums drawn with its slot and - its request carrying the studio clause - the studio line already under it, Songs below',
      [kinds(), slotText('albums'), note()], [['artists', 'albums', 'songs'], 'Asking MusicBrainz…', ["MusicBrainz's studio albums and EPs - See all for everything they made."]])
    asked.albums[0].resolve(studio)
    await answerOwned(holding(DUMMY))
    invariant('the studio answer landing late')
    check('...the answer landing folds into the slot; the line was there all along - nothing below moved', [slotText('albums'), note().length], ['Show 3 albums from MusicBrainz', 1])
  }

  console.log('\nMore from MusicBrainz in the Albums view; See all without focus; Show them and the last More handing focus on')
  {
    const from = await search('bristol sound', { artists: [], albums: [], songs: [] })
    await advance(500)
    const asked = newAsks(from)
    const albums = (start, end) => Array.from({ length: end - start }, (_, n) => ({ id: `00000000-0000-4000-8000-${String(start + n).padStart(12, '0')}`, title: `Album ${start + n}`, 'primary-type': 'Album' }))
    asked.artists[0].resolve(ARTISTS_NONE)
    asked.albums[0].resolve({ 'release-groups': albums(0, 12), count: 18 })
    asked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    const focused = []
    const rootRef = () => find(byClass('app-search'))[0].props.ref
    chipsOf().props.ref.current = { scrollIntoView() {}, querySelector: () => ({ focus: () => focused.push('chip') }) }
    globalThis.document = { activeElement: { name: 'elsewhere' }, body: { name: 'body' } }
    seeAll('albums').props.onClick({ currentTarget: seeAll('albums') })
    draw()
    check('See all tapped by a finger (it never had focus): focus left alone', focused, [])
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
    check('the Albums view: the twelve, More from MusicBrainz under them', [keysOf('albums').length, text(find(byClass('app-search-more'))[0])], [12, 'More from MusicBrainz'])
    const more = find(byClass('app-search-more'))[0]
    dom.use()
    dom.press(more)
    check('More asks the same search\'s next page by offset, quick', [asks.musicbrainz.at(-1).query, asks.musicbrainz.at(-1).offset, asks.musicbrainz.at(-1).quick], ['bristol sound', 12, true])
    asks.musicbrainz.at(-1).resolve({ 'release-groups': albums(12, 18), count: 18 })
    await settle()
    draw()
    check('...its last page appended below, the button gone - focus (it had it) to the first album it brought', [keysOf('albums').length, find(byClass('app-search-more')).length, dom.focused, said()],
      [18, 0, [`row:group:${albums(12, 13)[0].id}`], '6 more albums from MusicBrainz'])
    dom.leave()
    void rootRef
    chip('All').props.onClick()
    draw()
  }

  //? what a list draws in its library's place at the top: a slot outside every section
  const libraryPlaceText = () => {
    const inSections = find((node) => node.type === 'section' && node.props['aria-labelledby']).flatMap((section) => find(byClass('app-search-slot'), section))
    return find(byClass('app-search-slot')).filter((node) => !inSections.includes(node)).map(text)
  }
  const PID = '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11'
  const down = { configured: true, ok: false, server: null, problem: 'connection refused' }
  const TYPE_MORE_WORDS = 'Type a little more, or press Search, to ask MusicBrainz too.'

  console.log('\na box cut back below three characters, and the same words typed again (the review trap, kept)')
  {
    await remount()
    const from = await search('portis', { artists: [], albums: [], songs: [] })
    await advance(500)
    const asked = newAsks(from)
    check('(MusicBrainz asked for "portis": every kind)', [asked.albums.length, asked.artists.length, asked.songs.length], [1, 1, 1])
    type('po')
    check('cut back below three characters: every kind still out called off at once', [asked.albums[0].signal.aborted, asked.artists[0].signal.aborted, asked.songs[0].signal.aborted], [true, true, true])
    await advance(200)
    asks.library.at(-1).resolve({ artists: [P], albums: [ndDummy], songs: [] })
    await settle()
    draw()
    check('...its own library settled: the short words\' list, no MusicBrainz row of the longer words - the foot saying how to ask',
      [find(byClass('app-search-list'))[0]?.props['data-text'], keysOf('albums').filter((key) => key.startsWith('group:')), text(find(byClass('app-search-foot'))[0])], ['po', [], TYPE_MORE_WORDS])
    const again = await search('portis', { artists: [], albums: [], songs: [] })
    await advance(499)
    check('the same words typed again: nothing asked before the pause', [newAsks(again).albums.length, newAsks(again).artists.length, newAsks(again).songs.length], [0, 0, 0])
    await advance(1)
    check('...then every kind asked again - words called off are never taken as answered (review: MusicBrainz\'s part sat empty)',
      [newAsks(again).albums.length, newAsks(again).artists.length, newAsks(again).songs.length], [1, 1, 1])
    newAsks(again).albums[0].resolve({ 'release-groups': Array.from({ length: 12 }, (_, n) => ({ id: `00000000-0000-4000-8000-0000000p${String(n).padStart(4, '0')}`, title: `Portis ${n}`, 'primary-type': 'Album' })), count: 30 })
    newAsks(again).artists[0].resolve(ARTISTS_NONE)
    newAsks(again).songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    //? a More page still out as the box is cut back: called off with the rest
    chip('Albums').props.onClick()
    draw()
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
    find(byClass('app-search-more-musicbrainz'))[0].props.onClick()
    draw()
    const page = asks.musicbrainz.at(-1)
    check('(More asked in the Albums view)', page.offset, 12)
    type('po')
    check('...the box cut back: the More page still out called off too', page.signal.aborted, true)
    chip('All').props.onClick()
    draw()
  }

  console.log('\nthe box read once MusicBrainz is asked: an artist the library names afterwards strands nothing asked (review)')
  {
    const TEB = { id: 'ar-teb', name: 'Third Eye Blind', albumCount: 1 }
    await remount()
    const from = { albums: asks.musicbrainz.length, artists: asks.artists.length, songs: asks.songs.length, library: asks.library.length, order: asks.order.length }
    type('third eye blind')
    await advance(700)
    const asked = newAsks(from)
    check('MusicBrainz asked before the library answered: the box read as free text - every kind',
      [asked.albums.map((ask) => ask.query), asked.artists.map((ask) => ask.name), asked.songs.map((ask) => ask.query)], [['third eye blind'], ['third eye blind'], ['third eye blind']])
    await advance(300)
    asks.library.at(-1).resolve({ artists: [TEB], albums: [], songs: [] })
    await settle()
    draw()
    asked.artists[0].resolve(ARTISTS_NONE)
    asked.albums[0].resolve({ 'release-groups': [THIRD], count: 1 })
    asked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    check('...search3 then naming the artist: the answers asked still in hand - the sections drawn, none asking, MusicBrainz\'s Third among the albums',
      [kinds(), ['artists', 'albums', 'songs'].map(slotText), keysOf('albums').includes(`group:${THIRD.id}`)], [['artists', 'albums'], ['', '', ''], true])
    await advance(20000)
    check('...and so it stays: nothing asked again, no slot left asking', [newAsks(from).albums.length, newAsks(from).artists.length, newAsks(from).songs.length, ['artists', 'albums', 'songs'].map(slotText)],
      [1, 1, 1, ['', '', '']])
    enter()
    const reread = newAsks(from)
    check('Enter reads the box afresh - now an artist you have: their studio albums asked, the artists already in hand, no songs; the list drawn afresh (your own act)',
      [reread.albums.length, reread.albums.at(-1).query.startsWith('(artist:"Third Eye Blind") AND'), reread.artists.length, reread.songs.length, kinds(), asking().length], [2, true, 1, 1, [], 1])
    reread.albums.at(-1).resolve({ 'release-groups': [{ id: '00000000-0000-4000-8000-0000000000b1', title: 'Third Eye Blind', 'primary-type': 'Album', 'first-release-date': '1997' }], count: 1 })
    await answerOwned(holding(DUMMY))
    check('...its answer drawn at moment 2', [kinds(), keysOf('albums')], [['artists', 'albums'], ['group:00000000-0000-4000-8000-0000000000b1']])

    //? Search pressed straight after typing - before the library answers - as a phone's keyboard does
    await remount()
    const quick = { albums: asks.musicbrainz.length, artists: asks.artists.length, songs: asks.songs.length, order: asks.order.length }
    type('third eye blind')
    enter()
    await advance(150)
    asks.library.at(-1).resolve({ artists: [TEB], albums: [], songs: [] })
    await settle()
    draw()
    const quickAsked = newAsks(quick)
    quickAsked.artists[0].resolve(ARTISTS_NONE)
    quickAsked.albums[0].resolve({ 'release-groups': [THIRD], count: 1 })
    quickAsked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    await advance(3000)
    check('Search pressed before the library answered, the artist named after: drawn, none asking, nothing asked again',
      [kinds(), ['artists', 'albums', 'songs'].map(slotText), keysOf('albums').includes(`group:${THIRD.id}`), [newAsks(quick).albums.length, newAsks(quick).artists.length, newAsks(quick).songs.length]],
      [['artists', 'albums'], ['', '', ''], true, [1, 1, 1]])
  }

  console.log('\na letter typed and taken back while a kind is out: the run\'s cap still counts (review)')
  {
    await remount()
    const from = await search('portishead', { artists: [P], albums: [ndDummy], songs: [libSong('s-roads', 'Roads')] })
    await advance(500)
    const asked = newAsks(from)
    asked.artists[0].resolve(portisheadArtists)
    await answerOwned(holding(DUMMY))
    await advance(300)
    type('portisheadx')
    await advance(50)
    type('portishead')
    check('(back to exactly what MusicBrainz was asked for: nothing asked again, moment 1 drawn afresh)', [newAsks(from).albums.length, newAsks(from).artists.length, kinds(), asking().length], [1, 1, [], 1])
    await advance(1499)
    check('...a moment before the cap, counted from the letter taken back: the asking line', kinds(), [])
    await advance(1)
    check('...the cap: the sections drawn, the albums still out in their slot - never waiting on the slowest kind',
      [kinds(), slotText('albums'), keysOf('artists'), keysOf('songs')], [['artists', 'albums', 'songs'], 'Asking MusicBrainz…', ['artist:ar1'], ['song:s-roads']])
    asked.albums[0].resolve(studio)
    await answerOwned(holding(DUMMY))
    check('...the albums landing in their slot', slotText('albums'), 'Show 3 albums from MusicBrainz')

    //? the library's own Try again for words MusicBrainz was asked for: its run's cap counts from the Try again too
    await remount()
    type('glory times')
    await advance(200)
    asks.library.at(-1).reject(navidromeSaid('Navidrome had a problem'))
    await settle()
    draw()
    await advance(500)
    asks.artists.at(-1).resolve(ARTISTS_NONE)
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    const slowAlbums = asks.musicbrainz.at(-1)
    await answerOwned(holding(DUMMY))
    await advance(1600)
    dom.leave()
    find((node) => node.type === 'button' && text(node) === 'Try again', find((node) => byClass('app-search-problem')(node) && !byClass('app-search-foot')(node))[0])[0].props.onClick({ currentTarget: {} })
    draw()
    asks.library.at(-1).resolve({ artists: [], albums: [ndDummy], songs: [] })
    await settle()
    draw()
    check('the library\'s Try again, the albums still out: moment 1 again (the asking line, no sections)', [kinds(), asking().length], [[], 1])
    await advance(1500)
    check('...the cap counted from the Try again: the sections drawn, the albums in their slot - never waiting on the slowest kind', [kinds(), slotText('albums')], [['albums'], 'Asking MusicBrainz…'])
    slowAlbums.resolve({ 'release-groups': [], count: 0 })
    await answerOwned(holding(DUMMY))
  }

  console.log('\n"U2" and Search, MusicBrainz away: said as away - never "No results" (review)')
  {
    await remount()
    type('U2')
    await advance(200)
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
    const from = { albums: asks.musicbrainz.length, artists: asks.artists.length, songs: asks.songs.length, order: asks.order.length }
    enter()
    const asked = newAsks(from)
    check('(Search pressed on two letters: every kind asked)', [asked.albums.length, asked.artists.length, asked.songs.length], [1, 1, 1])
    asked.albums[0].reject(away())
    await settle()
    draw()
    asked.artists[0].reject(away())
    asked.songs[0].reject(away())
    await answerOwned(holding(DUMMY))
    check('every kind failing at once: the foot says MusicBrainz isn\'t answering, with Try again - no "No results", no "Type a little more"',
      [find(byClass('app-search-foot')).map(text), find((node) => node.type === 'p' && /No results|Type a little more/.test(text(node))).length],
      [["MusicBrainz isn't answering just now - it often goes away for a few minutes.Try again"], 0])
    //? the albums failing first, the others answering: the failure in its own slot, the artist drawn
    const second = { albums: asks.musicbrainz.length, artists: asks.artists.length, songs: asks.songs.length, order: asks.order.length }
    type('U3')
    await advance(200)
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
    enter()
    const secondAsked = newAsks(second)
    secondAsked.albums[0].reject(away())
    await settle()
    draw()
    secondAsked.artists[0].resolve({ matches: [{ mbid: '00000000-0000-4000-8000-0000000000u3', name: 'U3', disambiguation: 'a band', country: 'IE', type: 'Group', matched_as: 'U3' }], count: 1 })
    secondAsked.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    check('...the albums failing alone: their slot says so with Try again, the artist MusicBrainz found drawn - never "No results"',
      [kinds(), slotText('albums'), keysOf('artists'), find((node) => node.type === 'p' && /No results/.test(text(node))).length],
      [['artists', 'albums'], "MusicBrainz isn't answering.Try again", ['mb-artist:00000000-0000-4000-8000-0000000000u3'], 0])
    //? Search pressed before the library settled, the albums failing at once: never "press Search" after Search was pressed
    const third = { albums: asks.musicbrainz.length, order: asks.order.length, artists: asks.artists.length, songs: asks.songs.length }
    type('U4')
    enter()
    newAsks(third).albums[0].reject(away())
    await settle()
    draw()
    asks.library.at(-1).resolve({ artists: [], albums: [ndDummy], songs: [] })
    await settle()
    draw()
    check('...Search pressed before the library settled, the albums failing first: no "Type a little more, or press Search"', find((node) => node.type === 'p' && text(node) === TYPE_MORE_WORDS).length, 0)
    newAsks(third).artists[0].resolve(ARTISTS_NONE)
    newAsks(third).songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
  }

  console.log('\nMore songs\' last page landing with focus: its first song, found by comparing keys - a song\'s key holds a newline no selector may (review)')
  {
    await remount()
    await search('roads portishead', { artists: [], albums: [], songs: [] })
    chip('Songs').props.onClick()
    draw()
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
    await advance(500)
    asks.songs.at(-1).resolve({ recordings: [recording('r1', 'Roads', 'Portishead', PID, ROSELAND)], count: 2 })
    await answerOwned(holding(DUMMY))
    dom.use()
    dom.press(find(byClass('app-search-more-musicbrainz'))[0])
    asks.songs.at(-1).resolve({ recordings: [recording('r2', 'Roads (Dub)', 'Portishead', PID, THIRD)], count: 2 })
    await settle()
    draw()
    check('...focus to the song it brought (the stand-in DOM throws on a selector holding a newline, as a browser does)', dom.focused, [`row:mb-song:${PID}\nroads (dub)`])
    dom.leave()
    chip('All').props.onClick()
    draw()
  }

  console.log('\na kind view while Navidrome is away, or its status not known: its own library asked the moment Navidrome is OK (review)')
  {
    await remount({ status: down })
    const asksBefore = asks.library.length
    type('teardrop')
    await advance(200)
    chip('Songs').props.onClick()
    draw()
    await advance(500)
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    check('Navidrome away: the Songs view MusicBrainz\'s alone - its library not asked, counted as empty', [asks.library.length - asksBefore, text(find(byClass('app-search-foot')).at(-1))],
      [0, 'No songs for “teardrop”.'])
    const before = asks.library.length
    //? the gate's Try again: the status put away while it checks, then OK
    draw({ status: null })
    draw({ status })
    check('Navidrome back: All\'s search3 and the Songs view\'s own both asked', asks.library.slice(before).map((ask) => [ask.text, ask.page?.counts ?? null]),
      [['teardrop', null], ['teardrop', { artistCount: 0, albumCount: 0, songCount: 100 }]])
    const teardrop = { artists: [], albums: [], songs: [libSong('s-tear', 'Teardrop', 'nd-mezz', 'Mezzanine')] }
    asks.library.slice(before).find((ask) => ask.page)?.resolve(teardrop)
    asks.library.slice(before).find((ask) => !ask.page)?.resolve(teardrop)
    await settle()
    draw()
    check('...its library\'s row drawn - and no "No songs for" said any more', [keysOf('songs'), find((node) => node.type === 'p' && /No songs for/.test(text(node))).length], [['song:s-tear'], 0])
    chip('All').props.onClick()
    draw()

    //? the status not known yet (the app's first check): the view waits for it, as All does - MusicBrainz's rows never first
    await remount({ status: null })
    type('protection')
    await advance(200)
    chip('Albums').props.onClick()
    draw()
    await advance(500)
    const PROTECTION = { id: '00000000-0000-4000-8000-0000000000p7', title: 'Protection', 'primary-type': 'Album', 'first-release-date': '1994' }
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [PROTECTION], count: 1 })
    await answerOwned(holding(DUMMY))
    check('the status not known yet: the Albums view\'s library waits - none asked - MusicBrainz\'s row not drawn before it, one asking line, busy',
      [asks.library.filter((ask) => ask.text === 'protection').length, keysOf('albums'), find(byClass('app-asking'), sectionOf('app-search-albums')).map(text), sectionOf('app-search-albums').props['aria-busy']],
      [0, [], ['Searching your library and MusicBrainz…'], true])
    draw({ status })
    check('...the status OK: All\'s search3 and the view\'s own asked', asks.library.filter((ask) => ask.text === 'protection').map((ask) => ask.page?.counts ?? null),
      [null, { artistCount: 0, albumCount: 50, songCount: 0 }])
    asks.library.filter((ask) => ask.text === 'protection').forEach((ask) => ask.resolve({ artists: [], albums: [{ id: 'nd-prot', name: 'Protection', artist: 'Massive Attack', year: 1994 }], songs: [] }))
    await settle()
    draw()
    check('...the view\'s library rows, then MusicBrainz\'s under them', keysOf('albums'), ['album:nd-prot', `group:${PROTECTION.id}`])
    chip('All').props.onClick()
    draw()

    //? ...and known not OK after all: the view's library counts as empty, MusicBrainz's rows drawn
    await remount({ status: null })
    type('heat miser')
    await advance(200)
    chip('Albums').props.onClick()
    draw()
    await advance(500)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [PROTECTION], count: 1 })
    await answerOwned(holding(DUMMY))
    draw({ status: down })
    check('...the status known not OK after all: counted as empty, MusicBrainz\'s row drawn, no asking line', [keysOf('albums'), find(byClass('app-asking'), sectionOf('app-search-albums')).length],
      [[`group:${PROTECTION.id}`], 0])
    chip('All').props.onClick()
    draw({ status })
  }

  console.log('\na kind view: one asking line while its library is asked, and the region saying what it found (review)')
  {
    await remount()
    await search('mezzanine', { artists: [], albums: [], songs: [] })
    chip('Albums').props.onClick()
    draw()
    check('the Albums view before its library lands: one asking line where its rows go - not its heading alone',
      [find(byClass('app-asking'), sectionOf('app-search-albums')).map(text), keysOf('albums'), said()], [['Searching your library and MusicBrainz…'], [], 'Showing albums.'])
    asks.library.at(-1).resolve({ artists: [], albums: [{ id: 'nd-mezz', name: 'Mezzanine', artist: 'Massive Attack', year: 1998 }], songs: [] })
    await settle()
    draw()
    check('...its rows drawn: the line gone, the region saying what the library found', [find(byClass('app-asking'), sectionOf('app-search-albums')).map(text), keysOf('albums'), said()],
      [['Asking MusicBrainz…'], ['album:nd-mezz'], 'Showing albums. In your library: 1 album.'])
    await advance(500)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [{ id: '00000000-0000-4000-8000-00000000me22', title: 'Mezzanine', 'primary-type': 'Album', 'first-release-date': '1998' }], count: 1 })
    await answerOwned(holding(DUMMY))
    check('...then MusicBrainz\'s, said as they draw', said(), 'From MusicBrainz: 1 album.')
    chip('All').props.onClick()
    draw()
  }

  console.log('\na text the library was once late for, typed again: drawn by its own clock (review)')
  {
    await remount()
    type('portishead')
    await advance(200)
    await advance(1500)
    asks.library.at(-1).resolve({ artists: [P], albums: [ndDummy], songs: [libSong('s-roads', 'Roads')] })
    await settle()
    draw()
    const other = await search('radiohead', { artists: [], albums: [], songs: [] })
    await advance(500)
    for (const ask of [newAsks(other).artists[0], newAsks(other).albums[0], newAsks(other).songs[0]]) ask?.resolve(ask === newAsks(other).artists[0] ? ARTISTS_NONE : { 'release-groups': [], recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    type('portishead')
    check('typed again: the list drawn before stays until its own library settles - never at once as if late', [find(byClass('app-search-list'))[0]?.props['data-text'], libraryPlaceText()], ['radiohead', []])
    await advance(200)
    asks.library.at(-1).resolve({ artists: [P], albums: [ndDummy], songs: [libSong('s-roads', 'Roads')] })
    await settle()
    draw()
    check('...its library answering in time: its rows drawn, never behind a Show them', [topKeys(), libraryPlaceText()], [['top:artist:ar1', 'top:album:nd-dummy', 'top:song:s-roads'], []])
  }

  console.log('\nan album found held after MusicBrainz\'s answer landed, the list drawn again: shown once (review)')
  {
    await remount()
    await search('bristol trip', { artists: [], albums: [], songs: [] })
    await advance(500)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [THIRD, DUMMY, ROSELAND], count: 3 })
    asks.artists.at(-1).resolve(ARTISTS_NONE)
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    check('(Dummy, held and not listed by search3, brought in; MusicBrainz\'s Third and Roseland)', keysOf('albums'), [`group:${DUMMY.id}`, `group:${THIRD.id}`, `group:${ROSELAND.id}`])
    //? Third filed meanwhile: what the library holds asked again
    void Owned.refreshOwned()
    await answerOwned(holding(DUMMY, THIRD))
    chip('Albums').props.onClick()
    draw()
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
    chip('All').props.onClick()
    draw()
    check('Back to All: each album once - Third, held since, kept in MusicBrainz\'s block and marked there, its Get gone',
      [keysOf('albums'), getOf(`group:${THIRD.id}`), getOf(`group:${ROSELAND.id}`) ? 'Get' : null], [[`group:${DUMMY.id}`, `group:${THIRD.id}`, `group:${ROSELAND.id}`], undefined, 'Get'])
    void Owned.refreshOwned()
    await answerOwned(holding(DUMMY))
  }

  console.log('\nthe library late, then Navidrome known away: its place never says it found nothing (review)')
  {
    await remount({ status: null })
    type('roads')
    await advance(200)
    await advance(1500)
    check('(the status not known: the list drawn as if the library found nothing, its place kept)', libraryPlaceText(), ['Searching your library…'])
    draw({ status: down })
    await settle()
    draw()
    check('...Navidrome known away: the place says the library can\'t be searched - not "Nothing in your library"', libraryPlaceText(), ["Your library can't be searched just now."])
    draw({ status })
    await settle()
    draw()
    check('...and Navidrome back fills it: the library asked', asks.library.at(-1).text, 'roads')
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [libSong('s-roads', 'Roads')] })
    await settle()
    draw()
    check('...its answer landing in that place', libraryPlaceText(), ['1 in your library - Show them'])
  }

  console.log('\na kind view whose library was late, after a chip round trip: drawn afresh from what is in hand (review)')
  {
    await remount()
    await search('bristol trip', { artists: [], albums: [], songs: [] })
    chip('Albums').props.onClick()
    draw()
    await advance(1600)
    asks.library.at(-1).resolve({ artists: [], albums: [ndDummy], songs: [] })
    await settle()
    draw()
    check('(the view\'s library late: its place says Show them)', slotText('albums'), '1 in your library - Show them')
    chip('All').props.onClick()
    draw()
    chip('Albums').props.onClick()
    draw()
    check('back to Albums: its library\'s row drawn, no place kept', [keysOf('albums')[0], slotText('albums')], ['album:nd-dummy', ''])
    chip('All').props.onClick()
    draw()
  }

  console.log('\nthe desktop sidebar\'s field is this box (2.0.0-player.19, app/searchBox.ts - the real one)')
  {
    const Box = require(path.join(OUT, 'app/searchBox.js'))
    await remount()
    Box.typeSearch('massive attack')
    draw()
    check('typing in the sidebar\'s field is typing here', [find((node) => node.type === 'input')[0].props.value, Box.searchText()], ['massive attack', 'massive attack'])
    const before = { library: asks.library.length, albums: asks.musicbrainz.length, artists: asks.artists.length, songs: asks.songs.length }
    Box.submitSearch()
    await settle()
    draw()
    check('...and its Enter is this box\'s: the library and MusicBrainz asked at once, no pause waited for',
      [asks.library.length - before.library, asks.library.at(-1)?.text, asks.musicbrainz.length - before.albums, asks.artists.length - before.artists, asks.songs.length - before.songs], [1, 'massive attack', 1, 1, 1])
  }

  console.log('\nMore failing, and a second tap while it asks')
  {
    await remount()
    const albums = (start, end) => Array.from({ length: end - start }, (_, n) => ({ id: `00000000-0000-4000-8000-0000000m${String(start + n).padStart(4, '0')}`, title: `Album ${start + n}`, 'primary-type': 'Album' }))
    const from = await search('bristol sounds', { artists: [], albums: [], songs: [] })
    await advance(500)
    newAsks(from).albums[0].resolve({ 'release-groups': albums(0, 12), count: 30 })
    newAsks(from).artists[0].resolve({ matches: Array.from({ length: 10 }, (_, n) => ({ mbid: `00000000-0000-4000-8000-0000000a${String(n).padStart(4, '0')}`, name: `Bristol ${n}`, disambiguation: '', country: '', type: '', matched_as: '' })), count: 20 })
    newAsks(from).songs[0].resolve({ recordings: Array.from({ length: 25 }, (_, n) => recording(`rb${n}`, `Bristol Song ${n}`, 'Someone', SOMEBODY, SOMEONE_ALBUM)), count: 60 })
    await answerOwned(holding(DUMMY))
    const moreButton = () => find(byClass('app-search-more-musicbrainz'))[0]
    const note = () => find(byClass('app-search-more-note')).map(text)
    for (const [kind, label, asked] of [['Albums', 'More from MusicBrainz', () => asks.musicbrainz], ['Artists', 'More from MusicBrainz', () => asks.artists], ['Songs', 'More songs', () => asks.songs]]) {
      chip(kind).props.onClick()
      draw()
      asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
      await settle()
      draw()
      const rows = keysOf(kind.toLowerCase()).length
      check(`(the ${kind} view: its rows, ${label} under them)`, text(moreButton()), label)
      moreButton().props.onClick()
      draw()
      const page = asked().at(-1)
      check(`${kind}: More asking - the button busy, aria-disabled, never disabled`, [text(moreButton()), moreButton().props['aria-busy'], moreButton().props['aria-disabled'], moreButton().props.disabled],
        ['Asking MusicBrainz…', true, true, undefined])
      moreButton().props.onClick()
      draw()
      check(`...a second tap while it asks asks nothing`, asked().at(-1) === page, true)
      page.reject(away())
      await settle()
      draw()
      check(`...MusicBrainz away: said, the rows kept, the button trying again`, [note(), keysOf(kind.toLowerCase()).length, text(moreButton())],
        [["MusicBrainz isn't answering just now - it often goes away for a few minutes."], rows, 'Try again'])
      moreButton().props.onClick()
      draw()
      check(`...Try again asks the same page`, [asked().at(-1) !== page, asked().at(-1).offset], [true, page.offset])
      asked().at(-1).reject(away())
      await settle()
      draw()
    }
    chip('All').props.onClick()
    draw()
  }

  console.log('\na kind view\'s Try again and Show them hand focus on, as All\'s do (review)')
  {
    await remount()
    await search('nude day', { artists: [], albums: [], songs: [] })
    chip('Albums').props.onClick()
    draw()
    asks.library.at(-1).reject(navidromeSaid('Navidrome had a problem'))
    await settle()
    draw()
    dom.use()
    dom.press(find((node) => node.type === 'button' && text(node) === 'Try again', sectionOf('app-search-albums'))[0])
    check('the Albums view\'s library Try again from the keyboard: focus to the view\'s heading as the button goes - never the body', dom.focused, ['#app-search-albums'])
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
    await advance(500)
    asks.musicbrainz.at(-1).reject(away())
    await answerOwned(holding(DUMMY))
    dom.use()
    dom.press(find((node) => node.type === 'button' && text(node) === 'Try again', sectionOf('app-search-albums'))[0])
    check('...its MusicBrainz Try again the same', dom.focused, ['#app-search-albums'])
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [], count: 0 })
    await answerOwned(holding(DUMMY))
    const late = await search('nude dawn', { artists: [], albums: [], songs: [] })
    await advance(1600)
    asks.library.slice(late.library).find((ask) => ask.page).resolve({ artists: [], albums: [ndDummy], songs: [] })
    await settle()
    draw()
    dom.use()
    dom.press(buttonText('1 in your library - Show them', sectionOf('app-search-albums')))
    check('...the view\'s late library\'s Show them: focus to the first row it brought', dom.focused, ['row:album:nd-dummy'])
    dom.leave()
    chip('All').props.onClick()
    draw()
  }

  console.log('\nthe rest of the slice\'s rules, each pinned (review)')
  {
    //? (a) the box emptied in a kind view: the chip back to All - words typed after open in All
    await remount()
    await search('mezzanine', { artists: [], albums: [], songs: [] })
    chip('Songs').props.onClick()
    draw()
    type('')
    type('teardrop')
    check('the box emptied in a kind view, then words typed: All pressed again', find((node) => node.type === 'button' && node.props['aria-pressed'] === true, chipsOf()).map(text), ['All'])
    await advance(200)
    asks.library.filter((ask) => ask.text === 'teardrop' && !ask.page).at(-1)?.resolve({ artists: [], albums: [], songs: [] })
    await advance(500)
    for (const ask of [asks.artists.at(-1), asks.musicbrainz.at(-1), asks.songs.at(-1)]) ask.resolve(ask === asks.artists.at(-1) ? ARTISTS_NONE : { 'release-groups': [], recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))

    //? (b) Behind on, a search the library finds nothing for: its own moments - nothing on screen to wait for
    await remount()
    const late = await search('cowboys', { artists: [], albums: [ndDummy], songs: [] })
    await advance(500)
    newAsks(late).artists[0].resolve(ARTISTS_NONE)
    newAsks(late).songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    await advance(1500)
    newAsks(late).albums[0].resolve({ 'release-groups': [], count: 0 })
    await answerOwned(holding(DUMMY))
    const nothingHere = await search('humming', { artists: [], albums: [ndDummy], songs: [] })
    check('(Behind on: the next search the library found something for, drawn at the library\'s moment with slots)', [kinds().length > 0, asking().length], [true, 0])
    await advance(500)
    for (const ask of Object.values(newAsks(nothingHere)).slice(0, 3)) ask[0]?.resolve(ask === newAsks(nothingHere).artists ? ARTISTS_NONE : { 'release-groups': [], recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    //? (that one answered in time - Behind off; turned on again by a late one)
    const lateAgain = await search('cowboys again', { artists: [], albums: [ndDummy], songs: [] })
    await advance(500)
    newAsks(lateAgain).artists[0].resolve(ARTISTS_NONE)
    newAsks(lateAgain).songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    await advance(1500)
    newAsks(lateAgain).albums[0].resolve({ 'release-groups': [], count: 0 })
    await answerOwned(holding(DUMMY))
    await search('mysterons', { artists: [], albums: [], songs: [] })
    check('Behind on, the library finding nothing: Behind doesn\'t apply - its own moments, the asking line, no slots', [kinds(), asking().length, find(byClass('app-search-slot')).length], [[], 1, 0])
    await advance(500)
    for (const ask of [asks.artists.at(-1), asks.musicbrainz.at(-1), asks.songs.at(-1)]) ask.resolve(ask === asks.artists.at(-1) ? ARTISTS_NONE : { 'release-groups': [], recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))

    //? (c) a list drawn while Navidrome was away, Navidrome back: drawn afresh, the library in it
    await remount({ status: down })
    const awayFrom = await search('glory times', null)
    await advance(500)
    for (const ask of Object.values(newAsks(awayFrom)).slice(0, 3)) ask[0]?.resolve(ask === newAsks(awayFrom).artists ? ARTISTS_NONE : { 'release-groups': [], recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    check('(drawn while Navidrome was away: no library in it)', topKeys(), [])
    draw({ status })
    asks.library.at(-1).resolve({ artists: [], albums: [ndDummy], songs: [] })
    await settle()
    draw()
    check('Navidrome back: the list drawn afresh for these words, the library\'s rows in it', [asks.library.at(-1).text, topKeys()[0], keysOf('albums')], ['glory times', 'top:album:nd-dummy', ['album:nd-dummy']])

    //? (d) the full artist list failing: asked again when Navidrome comes back
    const listAsks = asks.lists.length
    await remount({ status }, null)
    asks.lists.at(-1).reject(new Error('Navidrome is busy'))
    await settle()
    draw({ status: down })
    draw({ status })
    check('the full artist list failing: asked again as Navidrome comes back', asks.lists.length - listAsks, 2)

    //? (e) the library failing: its problem at the top, with a Try again that asks it again
    await remount()
    type('wandering stars')
    await advance(200)
    asks.library.at(-1).reject(navidromeSaid('Navidrome had a problem'))
    await settle()
    draw()
    const problem = find((node) => byClass('app-search-problem')(node) && !byClass('app-search-foot')(node))[0]
    check('the library failing: its problem at the top of the list, with Try again', [text(find((node) => node.type === 'p', problem)[0]), text(find((node) => node.type === 'button', problem)[0])],
      ['Navidrome had a problem', 'Try again'])
    //? (2.0.4) Navidrome's address and its error never to a listener: what is wrong, and what to do
    Access.noteAccess({ user: 'ethan', admin: false, auth: 'on', permissions: ['request'] })
    type('wandering starz')
    await advance(200)
    asks.library.at(-1).reject(navidromeSaid("Navidrome couldn't be reached at http://navidrome:4533: All connection attempts failed"))
    await settle()
    draw()
    const unreached = find((node) => byClass('app-search-problem')(node) && !byClass('app-search-foot')(node))[0]
    check('...a listener: the music server can\'t be reached, never its address', text(find((node) => node.type === 'p', unreached)[0]),
      "Can't reach the music server right now. If it keeps happening, tell whoever runs deadwax.")
    Access.forgetAccess()
    type('wandering stars')
    await advance(200)
    asks.library.at(-1).reject(navidromeSaid('Navidrome had a problem'))
    await settle()
    draw()
    const libraryAsks = asks.library.length
    find((node) => node.type === 'button', problem)[0]?.props.onClick({ currentTarget: {} })
    draw()
    check('...Try again asks the library again', [asks.library.length - libraryAsks, asks.library.at(-1).text], [1, 'wandering stars'])
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
  }

  console.log('\nthe late recheck: Enter after a failure, Navidrome back after one, a kind view\'s words, Back to All said, the held album in the Albums view, the rules nothing pinned (late review)')
  {
    const MEZZ = { id: '00000000-0000-4000-8000-00000000me55', title: 'Mezzanine', 'primary-type': 'Album', 'first-release-date': '1998' }
    const TEAR = { id: '00000000-0000-4000-8000-00000000te55', title: 'Teardrop', 'primary-type': 'Single', 'first-release-date': '1998' }
    const problemAtTop = () => find((node) => byClass('app-search-problem')(node) && !byClass('app-search-foot')(node)).map((node) => text(find((n) => n.type === 'p', node)[0]))
    const footBlock = () => find((node) => byClass('app-search-problem')(node) && byClass('app-search-foot')(node))
    const tryAgains = () => find((node) => node.type === 'button' && text(node) === 'Try again').length
    const asksNow = () => ({ library: asks.library.length, albums: asks.musicbrainz.length, artists: asks.artists.length, songs: asks.songs.length, order: asks.order.length })
    const answerAll = (from, albums = { 'release-groups': [], count: 0 }) => {
      const asked = newAsks(from)
      asked.albums[0]?.resolve(albums)
      asked.artists[0]?.resolve(ARTISTS_NONE)
      asked.songs[0]?.resolve({ recordings: [], count: 0 })
    }

    //? 1. Enter after a kind failed in All: the failed asked again AND the list drawn afresh - a drawn list is frozen, so
    //? an answer to an ask again landed nowhere (the slot kept failing, its busy words turned to "isn't answering")
    await remount()
    const failedSlot = await search('mezzanine', { artists: [], albums: [], songs: [libSong('s-ang', 'Angel', 'nd-mezz', 'Mezzanine')] })
    await advance(500)
    newAsks(failedSlot).albums[0].reject(busy())
    newAsks(failedSlot).artists[0].resolve(ARTISTS_NONE)
    newAsks(failedSlot).songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    check('(the albums failed busy, the others answered: Albums\' slot says so)', [kinds(), slotText('albums')], [['albums', 'songs'], 'MusicBrainz is busy just now - try again in a moment.Try again'])
    const enterFrom = asksNow()
    enter()
    check('Enter after a failed slot: only the failed kind asked again - and the list drawn afresh by its moments (the asking line), as Try again draws it',
      [newAsks(enterFrom).albums.length, newAsks(enterFrom).artists.length, newAsks(enterFrom).songs.length, kinds(), asking().length], [1, 0, 0, [], 1])
    newAsks(enterFrom).albums[0].resolve({ 'release-groups': [MEZZ], count: 1 })
    await answerOwned(holding(DUMMY))
    check('...its answer drawn: Mezzanine among the albums, no failure left', [keysOf('albums'), slotOf('albums'), tryAgains()], [[`group:${MEZZ.id}`], undefined, 0])

    //? ...after the all-failed foot
    await remount()
    const allFailed = await search('teardrop', { artists: [], albums: [ndDummy], songs: [] })
    await advance(500)
    for (const each of [newAsks(allFailed).albums[0], newAsks(allFailed).artists[0], newAsks(allFailed).songs[0]]) each.reject(away())
    await answerOwned(holding(DUMMY))
    check('(every kind failed: the foot\'s block)', footBlock().length, 1)
    const footFrom = asksNow()
    enter()
    check('Enter after the all-failed foot: every kind asked again, the foot gone, the list drawn afresh by its moments',
      [newAsks(footFrom).albums.length, newAsks(footFrom).artists.length, newAsks(footFrom).songs.length, footBlock().length, asking().length], [1, 1, 1, 0, 1])
    answerAll(footFrom, { 'release-groups': [TEAR], count: 1 })
    await answerOwned(holding(DUMMY))
    check('...their answers drawn: Teardrop under your Dummy, no failure left', [keysOf('albums'), footBlock().length, tryAgains()], [['album:nd-dummy', `group:${TEAR.id}`], 0, 0])

    //? ...after the library failed
    await remount()
    const libFailed = asksNow()
    type('wandering stars')
    await advance(200)
    asks.library.at(-1).reject(navidromeSaid('Navidrome had a problem'))
    await advance(500)
    answerAll(libFailed)
    await answerOwned(holding(DUMMY))
    check('(the library failed: its problem at the top of the list)', problemAtTop(), ['Navidrome had a problem'])
    const libEnter = asksNow()
    enter()
    check('Enter after the library failed: it is asked again (All\'s counts), MusicBrainz nothing more', [asks.library.slice(libEnter.library).map((ask) => [ask.text, ask.page]), newAsks(libEnter).albums.length],
      [[['wandering stars', undefined]], 0])
    asks.library.at(-1).resolve({ artists: [], albums: [ndDummy], songs: [] })
    await settle()
    draw()
    check('...its answer drawn: the list drawn afresh with the library in it, the problem gone', [problemAtTop(), topKeys()[0], keysOf('albums')], [[], 'top:album:nd-dummy', ['album:nd-dummy']])
    //? ...asked again and slow: its own late clock, as the library's Try again arms it - never the old failure standing
    await remount()
    const slowFrom = asksNow()
    type('wandering stair')
    await advance(200)
    asks.library.at(-1).reject(navidromeSaid('Navidrome had a problem'))
    await advance(500)
    answerAll(slowFrom)
    await answerOwned(holding(DUMMY))
    //? (long after the first ask's own clock ran out)
    await advance(3000)
    enter()
    await advance(1499)
    check('(asked again, not answered yet: the list drawn as it was)', problemAtTop(), ['Navidrome had a problem'])
    await advance(1)
    check('...asked again and LIBRARY_LATE_MS passing: drawn as if it found nothing, its place kept - the old failure gone', [problemAtTop(), libraryPlaceText()], [[], ['Searching your library…']])
    asks.library.at(-1).resolve({ artists: [], albums: [ndDummy], songs: [] })
    await settle()
    draw()
    check('...its answer landing in that place', libraryPlaceText(), ['1 in your library - Show them'])

    //? 2. Navidrome coming back after the library failed: asked again, and the list drawn afresh with it
    await remount()
    const backFrom = asksNow()
    type('wandering star')
    await advance(200)
    asks.library.at(-1).reject(navidromeSaid('Navidrome had a problem'))
    await advance(500)
    answerAll(backFrom)
    await answerOwned(holding(DUMMY))
    check('(the library failed: its problem at the top of the list)', problemAtTop(), ['Navidrome had a problem'])
    const backAsks = asks.library.length
    draw({ status: down })
    draw({ status })
    check('Navidrome back after the library failed: All\'s search3 asked again', asks.library.slice(backAsks).map((ask) => [ask.text, ask.page]), [['wandering star', undefined]])
    asks.library.at(-1).resolve({ artists: [], albums: [ndDummy], songs: [] })
    await settle()
    draw()
    check('...the list drawn afresh for these words, the library\'s rows in it, its problem gone', [problemAtTop(), topKeys()[0], keysOf('albums')], [[], 'top:album:nd-dummy', ['album:nd-dummy']])

    //? 3. a kind view whose own library failed: never "No albums for" under the failure - the library wasn't searched
    await remount()
    await search('zzqx', { artists: [], albums: [], songs: [] })
    chip('Albums').props.onClick()
    draw()
    asks.library.at(-1).reject(navidromeSaid('Navidrome had a problem'))
    await settle()
    draw()
    await advance(500)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [], count: 0 })
    await answerOwned(holding(DUMMY))
    const albumsSection = sectionOf('app-search-albums')
    check('a kind view whose library failed, MusicBrainz finding nothing: the failure with Try again and MusicBrainz\'s own words - no "No albums for" under them',
      [text(find((node) => node.type === 'p', find(byClass('app-search-problem'), albumsSection)[0])[0]), find((node) => node.type === 'p', albumsSection).map(text).filter((each) => /^No albums/.test(each))],
      ['Navidrome had a problem', ['No albums on MusicBrainz for “zzqx”.']])
    chip('All').props.onClick()
    draw()

    //? 4. the Artists view under album-by-artist, the artist the box named not in the library's lists: it says so
    await remount({}, null)
    const named = await search('portishead third', { artists: [], albums: [], songs: [] })
    await advance(500)
    newAsks(named).albums[0]?.resolve({ 'release-groups': [THIRD], count: 1 })
    newAsks(named).songs[0]?.resolve({ recordings: [], count: 0 })
    await settle()
    asks.songs.at(-1).resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    chip('Artists').props.onClick()
    draw()
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
    check('the Artists view under album-by-artist, the named artist in none of the library\'s lists: "No artists for …" drawn and said - never a heading alone',
      [keysOf('artists'), find((node) => node.type === 'p', sectionOf('app-search-artists')).map(text), said()],
      [[], ['No artists for “portishead third”.'], 'Showing artists. No artists for “portishead third”.'])
    chip('All').props.onClick()
    draw()
    //? ...the full list stale (they're not in it yet), All's search3 naming them, the view's own failing: they still lead
    await remount({}, [{ id: 'ar-teb', name: 'Third Eye Blind' }])
    await search('portishead third', { artists: [P], albums: [], songs: [] })
    chip('Artists').props.onClick()
    draw()
    asks.library.at(-1).reject(navidromeSaid('Navidrome had a problem'))
    await settle()
    draw()
    check('...an older full list without them: the artist All\'s search3 named leads, looked for among both (knownArtists, as All\'s pool does)', keysOf('artists'), ['artist:ar1'])
    chip('All').props.onClick()
    draw()

    //? 5. the Albums view: an album you have that its own search3 didn't list is among MusicBrainz's rows at its place -
    //? marked, no Get - and opens the album you have through the id bridge
    await remount()
    void Owned.refreshOwned()
    await answerOwned(holding(DUMMY, THIRD))
    draw()
    await search('bristol sound', { artists: [], albums: [ndDummy], songs: [] })
    chip('Albums').props.onClick()
    draw()
    asks.library.at(-1).resolve({ artists: [], albums: [ndDummy], songs: [] })
    await settle()
    draw()
    await advance(500)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND, THIRD, DUMMY], count: 3 })
    await answerOwned(holding(DUMMY, THIRD))
    check('the Albums view: Third (held, its search3 not listing it) among MusicBrainz\'s rows at its place, marked; Dummy (listed) once',
      [keysOf('albums'), rowsOf('albums').map(([, line]) => line)],
      [['album:nd-dummy', `group:${ROSELAND.id}`, `group:${THIRD.id}`], ['Portishead · 1994 · in your library', 'Live album · Portishead · 1998', 'Portishead · 2008 · in your library']])
    check('...no Get on the album you have; Get on the one you don\'t', [getOf(`group:${THIRD.id}`), text(getOf(`group:${ROSELAND.id}`))], [undefined, 'Get'])
    const bridged = []
    const fetchBefore = globalThis.fetch
    globalThis.fetch = (url) => { bridged.push(url); return Promise.resolve({ ok: true, status: 200, json: async () => ({ navidrome_id: 'nd-third' }) }) }
    rowButton(`group:${THIRD.id}`).props.onClick()
    await settle()
    draw()
    globalThis.fetch = fetchBefore
    check('...its tap: the album you have, through the id bridge', [bridged.length, bridged[0]?.includes('release_mbid=rel-third'), opened.at(-1)], [1, true, { id: 'nd-third', name: 'Third', artist: 'Portishead' }])
    chip('All').props.onClick()
    draw()

    //? 6. the rules nothing pinned: (a) More from the store, logins on
    Session.setSessionMe({ user: 'ethan', admin: false, auth: 'on', version: '2.0.0-player.55' })
    await remount()
    asks.yours.at(-1)?.resolve([ndDummy])
    await settle()
    draw()
    await search('store pages', { artists: [], albums: [], songs: [] })
    chip('Albums').props.onClick()
    draw()
    asks.library.at(-1).resolve({ artists: [], albums: Array.from({ length: 50 }, (_, at) => ({ id: `nd-s${at}`, name: `Store Album ${at}`, artist: 'Somebody', year: 2001 })), songs: [] })
    await settle()
    draw()
    check('logins on, a library of your own: a kind view\'s full page offers More from the store', text(find(byClass('app-search-more-library'))[0]), 'More from the store')
    chip('All').props.onClick()
    Session.setSessionMe(null)
    draw()

    //? (b) a late albums kind landing all held, something tappable below: its slot says so
    await remount()
    const heldLate = await search('glory box', { artists: [], albums: [ndDummy], songs: [libSong('s-glory', 'Glory Box')] })
    await advance(500)
    newAsks(heldLate).artists[0].resolve(ARTISTS_NONE)
    newAsks(heldLate).songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    await advance(1500)
    check('(albums past the cap: its slot, Songs below it)', [kinds(), slotText('albums')], [['albums', 'songs'], 'Asking MusicBrainz…'])
    newAsks(heldLate).albums[0].resolve({ 'release-groups': [DUMMY], count: 1 })
    await answerOwned(holding(DUMMY))
    check('a late albums kind landing with all it found held, something below: its slot says everything is in your library - not "No albums on MusicBrainz"',
      slotText('albums'), 'Everything MusicBrainz found is in your library already.')

    //? (d) under three characters, before the library answers: it alone is said to be searched
    await remount()
    type('po')
    check('two characters before the library answers: "Searching your library…" - MusicBrainz isn\'t asked for them', text(asking()[0]), 'Searching your library…')
    await advance(200)
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
  }

  console.log('\nsearch what\'s saved (2.0.0-player.56): saved rows first, MusicBrainz\'s added below, nothing moved')
  {
    //? what's saved, as /search_musicbrainz/saved answers it: each kind in its own route's shape
    //? (`credited`: the albums credited to exactly the words, in studio order - what the artist reading draws)
    const savedAnswer = ({ artists = [], groups = [], recordings = [], credited = [] } = {}) => ({ available: true, artists: { matches: artists, count: artists.length },
      albums: { 'release-groups': groups, count: groups.length }, songs: { recordings, count: recordings.length }, credited: { 'release-groups': credited, count: credited.length } })
    const PORTISHEAD_MATCH = { mbid: PID, name: 'Portishead', disambiguation: '', country: 'GB', type: 'Group', score: null, matched_as: 'Portishead' }
    const theRip = recording('r-rip', 'The Rip', 'Portishead', PID, THIRD)
    const RIP = `mb-song:${PID}\nthe rip`
    const OTHER_RIP = `mb-song:${SOMEBODY}\nthe rip`
    const nothing = { artists: [], albums: [], songs: [] }

    await remount()
    globalThis.__search.savedHolds = (words) => (words === 'the rip' ? savedAnswer({ recordings: [theRip] }) : null)
    const from = await search('the rip', nothing)
    check('asked as the words settle, beside the library - the box\'s words, once', asks.saved.filter((ask) => ask.words === 'the rip').length, 1)
    check('the library\'s moment, MusicBrainz not yet asked: a song seen only on a saved album page is Top results\' first - its album and its artist after it (Apple\'s family)',
      [topKeys(), find(byClass('app-search-top-place')).length, asking().length], [[`top:${RIP}`, `top:group:${THIRD.id}`, 'top:artist:ar1'], 0, 1])
    check('...marked as saved - its place words, the facts as MusicBrainz\'s row says them', lineOf(rowButton(`top:${RIP}`)), 'Song · Portishead · Third · saved')
    rowButton(`top:${RIP}`).props.onClick()
    check('...and its tap is a MusicBrainz song\'s: its album, the song marked', songAlbums.at(-1), [{ id: THIRD.id, title: 'Third' }, ['r-rip']])
    await advance(500)
    const asked = newAsks(from)
    check('MusicBrainz asked as ever at the pause - every kind', [asked.albums.length, asked.artists.length, asked.songs.length], [1, 1, 1])
    asked.artists[0].resolve(ARTISTS_NONE)
    asked.albums[0].resolve({ 'release-groups': [], count: 0 })
    asked.songs[0].resolve({ recordings: [recording('r-rip2', 'The Rip', 'Portishead', PID, THIRD), recording('r-rip3', 'The Rip', 'Somebody', SOMEBODY, SOMEONE_ALBUM)], count: 2 })
    await answerOwned(holding(DUMMY))
    invariant('moment 2, what\'s saved in hand')
    check('moment 2: Songs - what\'s saved first, then MusicBrainz\'s, its own take of the same song left out (by its key)',
      [kinds(), keysOf('songs'), topKeys()], [['songs'], [RIP, OTHER_RIP], [`top:${RIP}`, `top:group:${THIRD.id}`, 'top:artist:ar1']])
    check('...the region: what\'s saved, then what MusicBrainz added', said(), 'Saved from MusicBrainz: 1 song. More from MusicBrainz: 1 song.')
    check('...the saved row a MusicBrainz row, marked; MusicBrainz\'s not', [lineOf(rowButton(RIP)), lineOf(rowButton(OTHER_RIP))], ['Portishead · 4:00 · Third · saved', 'Somebody · 4:00 · Somebody\'s Album'])

    //? MusicBrainz's songs past the cap: the saved row drawn at the cap, MusicBrainz's landing below it - drawn in (last)
    const late = await search('the rip', null)
    asks.library.at(-1).resolve(nothing)
    await settle()
    draw()
    check('(the same words again: the kept answers draw at once)', keysOf('songs'), [RIP, OTHER_RIP])
    globalThis.__search.savedHolds = (words) => (words === 'rip portishead' ? savedAnswer({ recordings: [theRip], groups: [THIRD] }) : null)
    const capped = await search('rip portishead', nothing)
    await advance(500)
    const cappedAsks = newAsks(capped)
    //? (a title by an artist you have: no artists asked)
    check('(a title by an artist you have: albums and songs asked, no artists)', [cappedAsks.albums.length, cappedAsks.artists.length, cappedAsks.songs.length], [1, 0, 1])
    cappedAsks.albums[0].resolve({ 'release-groups': [THIRD, ROSELAND], count: 2 })
    await answerOwned(holding(DUMMY))
    await advance(1500)
    invariant('the cap, songs out')
    check('at the cap, songs still out: Albums - Third (saved) first, then MusicBrainz\'s Roseland, Third once; Songs - the saved row, its slot under it',
      [kinds(), keysOf('albums'), keysOf('songs'), slotText('songs')], [['artists', 'albums', 'songs'], [`group:${THIRD.id}`, `group:${ROSELAND.id}`], [RIP], 'Asking MusicBrainz…'])
    check('...the region says what\'s saved as the sections draw', said(), 'Saved from MusicBrainz: 1 album, 1 song.')
    cappedAsks.songs[0].resolve({ recordings: [recording('r-rip2', 'The Rip', 'Portishead', PID, THIRD), recording('r-rip3', 'The Rip', 'Somebody', SOMEBODY, SOMEONE_ALBUM)], count: 2 })
    await answerOwned(holding(DUMMY))
    invariant('songs landing after the cap')
    check('MusicBrainz\'s songs land last: drawn in BELOW the saved row, nothing above moved, the same song never twice',
      [keysOf('songs'), slotOf('songs')], [[RIP, OTHER_RIP], undefined])
    void late

    //? a late kind with something below: folded - and an answer adding nothing new says so, never "No albums on MusicBrainz"
    globalThis.__search.savedHolds = (words) => (words === 'third portishead' ? savedAnswer({ groups: [THIRD], recordings: [theRip] }) : null)
    const folded = await search('third portishead', nothing)
    await advance(500)
    const foldAsks = newAsks(folded)
    foldAsks.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    await advance(1500)
    check('(at the cap: Albums with the saved row and a slot, Songs below it)', [kinds(), keysOf('albums'), slotText('albums')], [['artists', 'albums', 'songs'], [`group:${THIRD.id}`], 'Asking MusicBrainz…'])
    foldAsks.albums[0].resolve({ 'release-groups': [THIRD], count: 1 })
    await answerOwned(holding(DUMMY))
    invariant('albums landing with nothing new')
    check('MusicBrainz\'s albums bring nothing that isn\'t drawn: its slot says so - never that MusicBrainz has none', [keysOf('albums'), slotText('albums')],
      [[`group:${THIRD.id}`], 'No more albums on MusicBrainz for “third portishead”.'])

    //? MusicBrainz away: what's saved stays, with one line saying so
    globalThis.__search.savedHolds = (words) => (words === 'the rip live' ? savedAnswer({ recordings: [recording('r-ripl', 'The Rip Live', 'Portishead', PID, ROSELAND)] }) : null)
    const gone = await search('the rip live', nothing)
    await advance(500)
    const goneAsks = newAsks(gone)
    for (const ask of [...goneAsks.albums, ...goneAsks.artists, ...goneAsks.songs]) ask.reject(new MusicBrainzUnavailable('MusicBrainz is unreachable right now'))
    await answerOwned(holding(DUMMY))
    invariant('MusicBrainz away')
    check('MusicBrainz away, every kind: what\'s saved stays drawn, and one line says MusicBrainz isn\'t answering and these are what deadwax has saved',
      [keysOf('songs'), text(find(byClass('app-search-foot'))[0]),
        find((node) => node.type === 'button' && text(node) === 'Try again', find(byClass('app-search-foot'))[0]).length],
      //? the whole line (after review) - "What's in your library is above." only because it is: the song's artist, Portishead,
      //? is the library's (Top results' third)
      [[`mb-song:${PID}\nthe rip live`], "MusicBrainz isn't answering just now - these are what deadwax has saved from it. What's in your library is above.Try again", 1])
    check('...the region says it the same way', said().includes("MusicBrainz isn't answering - these are what deadwax has saved."), true)
    //? (after review) nothing of the library's drawn - the artist isn't in it: the foot never says the library's is above
    await remount({}, [])
    const bare = await search('the rip live', nothing)
    await advance(500)
    const bareAsks = newAsks(bare)
    for (const ask of [...bareAsks.albums, ...bareAsks.artists, ...bareAsks.songs]) ask.reject(new MusicBrainzUnavailable('MusicBrainz is unreachable right now'))
    await answerOwned(holding(DUMMY))
    check('MusicBrainz away, only what\'s saved drawn (its artist not the library\'s): the foot one line - never "What\'s in your library is above."',
      [topKeys().every((key) => key.startsWith('top:mb-') || key.startsWith('top:group:')), text(find(byClass('app-search-foot'))[0])],
      [true, "MusicBrainz isn't answering just now - these are what deadwax has saved from it.Try again"])

    //? one kind failing under a saved row while another answers: its slot says these are saved (a fresh Search: no Behind)
    await remount()
    globalThis.__search.savedHolds = (words) => (words === 'roseland portishead' ? savedAnswer({ groups: [ROSELAND], recordings: [recording('r-ros', 'Roseland Intro', 'Portishead', PID, ROSELAND)] }) : null)
    const half = await search('roseland portishead', nothing)
    await advance(500)
    const halfAsks = newAsks(half)
    //? (album-by-artist: albums and songs asked)
    halfAsks.albums[0].reject(new MusicBrainzUnavailable('MusicBrainz is unreachable right now'))
    //? (its own take of the saved song: MusicBrainz's answer holding nothing new for Songs)
    halfAsks.songs[0].resolve({ recordings: [recording('r-ros2', 'Roseland Intro', 'Portishead', PID, ROSELAND)], count: 1 })
    await answerOwned(holding(DUMMY))
    check('one kind failing under its saved rows: its slot says MusicBrainz isn\'t answering and these are saved, with Try again',
      [keysOf('albums'), slotText('albums')], [[`group:${ROSELAND.id}`], 'Saved - MusicBrainz is away.Try again'])

    //? nothing saved for the words: today's behaviour exactly - the asks, the moments, the rows
    await remount()
    globalThis.__search.savedHolds = null
    const plain = await search('third', { artists: [{ id: 'ar-teb', name: 'Third Eye Blind', albumCount: 2 }], albums: [], songs: [] })
    check('nothing saved: the library\'s moment as before ("third": nothing early, only the asking line)', [top(), asking().length], [undefined, 1])
    await advance(500)
    const plainAsks = newAsks(plain)
    plainAsks.artists[0].resolve(ARTISTS_NONE)
    plainAsks.albums[0].resolve({ 'release-groups': [THIRD], count: 1 })
    plainAsks.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    check('...and moment 2 as before - no row marked saved, the region as before', [topKeys(), kinds(), lineOf(rowButton(`group:${THIRD.id}`)), said()],
      [[`top:group:${THIRD.id}`, 'top:artist:ar1', 'top:artist:ar-teb'], ['artists', 'albums'], 'Portishead · 2008', 'From MusicBrainz: 1 album.'])

    //? the artist reading: only their albums, the studio ones (the line under them says so), saved artists by id once
    globalThis.__search.savedHolds = (words) => (words === 'portishead' ? savedAnswer({
      artists: [PORTISHEAD_MATCH],
      groups: [ROSELAND, THIRD, { id: '00000000-0000-4000-8000-0000000000w1', title: 'Welcome to Portishead', 'primary-type': 'Album', 'first-release-date': '2003', 'artist-credit': [{ name: 'Somebody', artist: { id: SOMEBODY, name: 'Somebody' } }] }],
      credited: [THIRD, ROSELAND],
      recordings: [theRip],
    }) : null)
    const reading = await search('portishead', { artists: [P], albums: [ndDummy], songs: [] })
    await advance(500)
    const readingAsks = newAsks(reading)
    readingAsks.artists[0].resolve(portisheadArtists)
    readingAsks.albums[0].resolve(studio)
    await answerOwned(holding(DUMMY))
    check('an artist you have: Albums - yours, then what\'s saved of THEIRS that is a studio album (Third - not the live one, not somebody else\'s "Welcome to Portishead"), then MusicBrainz\'s',
      keysOf('albums').slice(0, 3), ['album:nd-dummy', `group:${THIRD.id}`, `group:${studio['release-groups'].find((group) => group.title === 'Portishead').id}`])
    check('...Third once, the studio line under them; no Songs (an artist\'s name alone asks none, so none saved drawn either)',
      [keysOf('albums').filter((key) => key === `group:${THIRD.id}`).length, kinds()], [1, ['artists', 'albums']])
    check('...their saved artist is the library\'s Portishead (by id): one row', keysOf('artists'), ['artist:ar1'])

    //? a saved artist only MusicBrainz knows: its tap opens their page by mb:, MusicBrainz's copy of them never twice
    const RADIOHEAD = radioheadArtists.matches[0]
    globalThis.__search.savedHolds = (words) => (words === 'radiohead' ? savedAnswer({ artists: [{ ...RADIOHEAD }] }) : null)
    const rh = await search('radiohead', nothing)
    check('a saved artist nobody\'s library has: Top results\' first at the library\'s moment, marked saved', [topKeys()[0], lineOf(rowButton(`top:mb-artist:${RADIOHEAD.mbid}`)).endsWith('· saved')],
      [`top:mb-artist:${RADIOHEAD.mbid}`, true])
    rowButton(`top:mb-artist:${RADIOHEAD.mbid}`).props.onClick()
    check('...its tap their page by mb: - a MusicBrainz artist\'s', mbArtists.at(-1), { mbid: RADIOHEAD.mbid, name: RADIOHEAD.name })
    await advance(500)
    const rhAsks = newAsks(rh)
    rhAsks.artists[0].resolve(radioheadArtists)
    rhAsks.albums[0].resolve({ 'release-groups': [], count: 0 })
    rhAsks.songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    check('...MusicBrainz\'s answer holding them too: Artists - the saved row first, MusicBrainz\'s others after it, Radiohead once',
      [keysOf('artists')[0], keysOf('artists').filter((key) => key === `mb-artist:${RADIOHEAD.mbid}`).length, keysOf('artists').length], [`mb-artist:${RADIOHEAD.mbid}`, 1, 2])

    //? the Albums view: what's saved after the view's library rows, MusicBrainz's below it
    await remount()
    globalThis.__search.savedHolds = (words) => (words === 'third portishead' ? savedAnswer({ groups: [THIRD] }) : null)
    const view = await search('third portishead', nothing)
    await advance(500)
    //? (album-by-artist, so All asked fielded albums and songs; the Albums view asks its own)
    chip('Albums').props.onClick()
    draw()
    const viewAsks = newAsks(view)
    asks.library.at(-1).resolve({ artists: [], albums: [], songs: [] })
    await settle()
    draw()
    check('the Albums view, MusicBrainz still out: what\'s saved drawn at once, the asking line under it',
      [keysOf('albums'), find(byClass('app-asking-text'), sectionOf('app-search-albums')).map(text)], [[`group:${THIRD.id}`], ['Asking MusicBrainz…']])
    viewAsks.albums.at(-1).resolve({ 'release-groups': [THIRD, ROSELAND], count: 2 })
    await answerOwned(holding(DUMMY))
    check('...MusicBrainz\'s added below it, Third once', keysOf('albums'), [`group:${THIRD.id}`, `group:${ROSELAND.id}`])
    chip('All').props.onClick()
    draw()

    //? only the newest answer draws; a slow one is given up and draws nothing - its answer landing even so (as one already
    //? on its way when called off can), never drawn
    globalThis.__search.savedByHand = true
    globalThis.__search.savedHolds = null
    globalThis.__search.abortRejects = false
    type('the ri')
    await advance(200)
    const first = asks.saved.at(-1)
    type('the rip')
    await advance(200)
    const second = asks.saved.at(-1)
    check('a new text calls the old saved ask off (latestOnly)', [first.words, first.signal.aborted, second.words], ['the ri', true, 'the rip'])
    first.resolve(savedAnswer({ recordings: [theRip] }))
    asks.library.at(-1).resolve(nothing)
    await settle()
    draw()
    check('...the library\'s moment waits for what\'s saved (asked, not answered): the old list stays', find(byClass('app-search-list'))[0]?.props['data-text'], 'third portishead')
    await advance(399)
    check('...for SAVED_WAIT_MS at most', find(byClass('app-search-list'))[0]?.props['data-text'], 'third portishead')
    await advance(1)
    check('...then it is given up: the list drawn without it (MusicBrainz alone) - the superseded answer drew nothing', [find(byClass('app-search-list'))[0]?.props['data-text'], topKeys(), second.signal.aborted],
      ['the rip', [], true])
    second.resolve(savedAnswer({ recordings: [theRip] }))
    await settle()
    draw()
    check('...and its answer, landing after, draws nothing for these words', topKeys(), [])
    globalThis.__search.abortRejects = true
    //? the box emptied: what's saved called off with everything else
    type('the ripper')
    await advance(200)
    const emptied = asks.saved.at(-1)
    type('')
    check('the box emptied: the saved ask still out called off', [emptied.words, emptied.signal.aborted], ['the ripper', true])
    globalThis.__search.savedByHand = false

    //? (after review) a kind view never moves what it drew: what's saved asked again after MusicBrainz's rows are drawn
    //? (Navidrome away, a letter typed and taken back - the kept answer draws at once) lands BELOW them, never above;
    //? MusicBrainz's row of a thing saved stays MusicBrainz's row, in its place, its line as it was
    await remount({ status: down })
    globalThis.__search.savedHolds = (words) => (words === 'zork live' ? savedAnswer({ groups: [THIRD] }) : null)
    type('zork live')
    await advance(200)
    chip('Albums').props.onClick()
    draw()
    await advance(500)
    asks.musicbrainz.at(-1).resolve({ 'release-groups': [ROSELAND, THIRD], count: 2 })
    await answerOwned(holding(DUMMY))
    check('(the Albums view, Navidrome away: what\'s saved first, MusicBrainz\'s below it, Third once)', keysOf('albums'), [`group:${THIRD.id}`, `group:${ROSELAND.id}`])
    globalThis.__search.savedByHand = true
    type('zork livex')
    await advance(300)
    type('zork live')
    const drawnBack = keysOf('albums')
    const linesBack = drawnBack.map((key) => lineOf(rowButton(key)))
    check('...a letter typed and taken back: MusicBrainz\'s kept answer drawn at once, what\'s saved not asked for the words yet',
      [drawnBack, asks.saved.at(-1).words], [[`group:${ROSELAND.id}`, `group:${THIRD.id}`], 'zork livex'])
    await advance(200)
    check('(what\'s saved asked again for the words, at the pause)', asks.saved.at(-1).words, 'zork live')
    asks.saved.at(-1).resolve(savedAnswer({ groups: [THIRD, SOMEONE_ALBUM] }))
    await settle()
    draw()
    check('...its answer landing after: nothing drawn moves or changes - Third MusicBrainz\'s row in its place, its line as it was; the new saved album BELOW',
      [keysOf('albums'), drawnBack.map((key) => lineOf(rowButton(key))), lineOf(rowButton(`group:${SOMEONE_ALBUM.id}`)).endsWith('· saved')],
      [[`group:${ROSELAND.id}`, `group:${THIRD.id}`, `group:${SOMEONE_ALBUM.id}`], linesBack, true])
    //? asked once for the words: a chip's tap, Enter and Try again never ask it again (the review's first catch)
    const savedAsks = asks.saved.length
    chip('Songs').props.onClick()
    draw()
    chip('Albums').props.onClick()
    draw()
    enter()
    await settle()
    draw()
    check('...what\'s saved asked once for the words: chip taps and Enter ask it nothing more', asks.saved.length, savedAsks)
    globalThis.__search.savedByHand = false
    chip('All').props.onClick()
    draw()
    //? ...and when it had nothing to search (no file yet, say: `available: false`), or was given up or failed, the same -
    //? never asked again for the words (the review's first catch: asked again on a chip's tap, its late answer moved rows)
    globalThis.__search.savedHolds = (words) => (words === 'zork gone' ? { ...savedAnswer(), available: false } : null)
    type('zork gone')
    await advance(200)
    const goneOnce = asks.saved.filter((ask) => ask.words === 'zork gone').length
    chip('Albums').props.onClick()
    draw()
    chip('Songs').props.onClick()
    draw()
    enter()
    await settle()
    draw()
    chip('All').props.onClick()
    draw()
    check('...nothing to search for the words: asked once, never again by a chip\'s tap or Enter', [goneOnce, asks.saved.filter((ask) => ask.words === 'zork gone').length], [1, 1])

    //? (after review) a kind view's own search3 answering before what's saved: MusicBrainz's rows held (the asking line)
    //? until it has answered - SAVED_WAIT_MS at most - then drawn together, what's saved first
    await remount()
    globalThis.__search.savedHolds = (words) => (words === 'zork live' ? savedAnswer({ groups: [THIRD] }) : null)
    const z = await search('zork live', nothing)
    await advance(500)
    newAsks(z).albums[0].resolve({ 'release-groups': [ROSELAND, THIRD], count: 2 })
    newAsks(z).artists[0].resolve(ARTISTS_NONE)
    newAsks(z).songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    chip('Albums').props.onClick()
    draw()
    asks.library.at(-1).resolve(nothing)
    await settle()
    draw()
    globalThis.__search.savedByHand = true
    type('zork livex')
    await advance(200)
    type('zork live')
    await advance(200)
    for (const ask of asks.library.filter((each) => each.text === 'zork live').slice(-2)) ask.resolve(nothing)
    await settle()
    draw()
    check('the view\'s library in, what\'s saved still asked: MusicBrainz\'s kept rows held - the asking line where they go',
      [keysOf('albums'), find(byClass('app-asking-text'), sectionOf('app-search-albums')).map(text)], [[], ['Asking MusicBrainz…']])
    asks.saved.at(-1).resolve(savedAnswer({ groups: [THIRD] }))
    await settle()
    draw()
    check('...what\'s saved in: drawn together, what\'s saved first, Third once', keysOf('albums'), [`group:${THIRD.id}`, `group:${ROSELAND.id}`])
    globalThis.__search.savedByHand = false
    chip('All').props.onClick()
    draw()

    //? (second review) MusicBrainz's FAILURE is held and kept as its rows are: drawn, a late saved answer goes BELOW it
    //? (its Try again never moved down under the finger); still being asked for, the failure waits behind the asking line
    const order = () => find((node) => byClass('app-search-problem')(node) || byClass('app-result')(node), sectionOf('app-search-albums'))
      .map((node) => (byClass('app-search-problem')(node) ? 'PROBLEM' : 'row'))
    await remount({ status: down })
    globalThis.__search.savedHolds = (words) => (words === 'zork fail' ? savedAnswer({ groups: [THIRD] }) : null)
    type('zork fail')
    await advance(200)
    chip('Albums').props.onClick()
    draw()
    await advance(500)
    asks.musicbrainz.at(-1).reject(away())
    await answerOwned(holding(DUMMY))
    await settle()
    draw()
    check('(the Albums view, Navidrome and MusicBrainz away: what\'s saved, then the failure)', [order(), keysOf('albums')], [['row', 'PROBLEM'], [`group:${THIRD.id}`]])
    globalThis.__search.savedByHand = true
    type('zork failx')
    await advance(300)
    type('zork fail')
    draw()
    check('...a letter typed and taken back: the kept failure drawn at once, what\'s saved not asked for the words yet',
      [order(), asks.saved.at(-1).words], [['PROBLEM'], 'zork failx'])
    await advance(200)
    check('(what\'s saved asked again for the words, at the pause - the failure still drawn)', [asks.saved.at(-1).words, order()], ['zork fail', ['PROBLEM']])
    asks.saved.at(-1).resolve(savedAnswer({ groups: [THIRD] }))
    await settle()
    draw()
    check('...its answer landing after: the failure and its Try again stay where they were, the saved album BELOW them',
      [order(), keysOf('albums')], [['PROBLEM', 'row'], [`group:${THIRD.id}`]])
    check('...the failure\'s words as they were drawn (nothing saved above it)', find(byClass('app-search-problem'), sectionOf('app-search-albums')).map(text).join(' ').includes('Saved -'), false)
    globalThis.__search.savedByHand = false
    chip('All').props.onClick()
    draw()
    //? ...and a failure in hand before what's saved has answered (the view's own search3 answering first): held behind
    //? the asking line as MusicBrainz's rows are, then drawn together, what's saved first
    await remount()
    globalThis.__search.savedHolds = (words) => (words === 'zork held' ? savedAnswer({ groups: [THIRD] }) : null)
    const zh = await search('zork held', nothing)
    await advance(500)
    newAsks(zh).albums[0].reject(away())
    newAsks(zh).artists[0].resolve(ARTISTS_NONE)
    newAsks(zh).songs[0].resolve({ recordings: [], count: 0 })
    await answerOwned(holding(DUMMY))
    chip('Albums').props.onClick()
    draw()
    asks.library.at(-1).resolve(nothing)
    await settle()
    draw()
    globalThis.__search.savedByHand = true
    type('zork heldx')
    await advance(200)
    type('zork held')
    await advance(200)
    for (const ask of asks.library.filter((each) => each.text === 'zork held').slice(-2)) ask.resolve(nothing)
    await settle()
    //? a failed answer isn't kept: the words back ask MusicBrainz again - and it fails again, before what's saved answers
    newAsks(zh).albums[1].reject(away())
    await settle()
    draw()
    check('MusicBrainz failing, the view\'s library in, what\'s saved still asked: no failure drawn yet - the asking line where it goes',
      [asks.saved.at(-1).words, order(), find(byClass('app-asking-text'), sectionOf('app-search-albums')).map(text)], ['zork held', [], ['Asking MusicBrainz…']])
    asks.saved.at(-1).resolve(savedAnswer({ groups: [THIRD] }))
    await settle()
    draw()
    check('...what\'s saved in: drawn with the failure, what\'s saved first', [order(), keysOf('albums')], [['row', 'PROBLEM'], [`group:${THIRD.id}`]])
    globalThis.__search.savedByHand = false
    chip('All').props.onClick()
    draw()

    //? the real client's address
    check('the real client: /search_musicbrainz/saved?words=…', require(path.join(OUT, 'api/musicbrainz.real.js')).searchSavedPath('björk & co'), '/search_musicbrainz/saved?words=bj%C3%B6rk+%26+co')
    await remount()
  }

  console.log('\nthe real MusicBrainz client (api/musicbrainz.ts): offsets past the first page only, `quick`, the artists, busy from the body')
  {
    const urls = []
    const fetchBefore = globalThis.fetch
    globalThis.fetch = (url) => { urls.push(url); return Promise.resolve({ ok: true, status: 200, json: async () => ({}) }) }
    const MB = require(path.join(OUT, 'api/musicbrainz.real.js'))
    await MB.fullySearch('artist:"Portishead"', 12, false)
    await MB.fullySearch('artist:"Portishead"', 12, false, undefined, 24)
    await MB.fullySearch('artist:"Portishead"', 12, false, undefined, 0, true)
    const query = (url) => Object.fromEntries(new URL(url, 'http://deadwax.test').searchParams)
    check('the first page asked as it always was; a later page by its offset; `quick` only from the app\'s Search',
      urls.map(query), [{ query: 'artist:"Portishead"', limit: '12', releases: 'false' }, { query: 'artist:"Portishead"', limit: '12', releases: 'false', offset: '24' },
        { query: 'artist:"Portishead"', limit: '12', releases: 'false', quick: 'true' }])
    urls.length = 0
    await MB.searchArtists('kanye west', 10)
    await MB.searchArtists('kanye west', 10, undefined, 10)
    await MB.searchSongs('recording:"roads"', 25, undefined, 25)
    check('(2.0.0-player.55) the artists: /search_musicbrainz/artists by name, the limit asked, an offset only past the first page',
      urls.map((url) => [new URL(url, 'http://deadwax.test').pathname.replace(/^.*\/search_musicbrainz/, ''), query(url)]),
      [['/artists', { name: 'kanye west', limit: '10' }], ['/artists', { name: 'kanye west', limit: '10', offset: '10' }], ['/songs', { query: 'recording:"roads"', limit: '25', offset: '25' }]])
    //? busy: the 503's body says `busy: true` beside its words - read from the body, never the words
    const answers = [{ status: 503, body: { detail: 'MusicBrainz is busy just now - try again in a moment.', busy: true } }, { status: 503, body: { detail: 'MusicBrainz is unreachable right now (busy)' } },
      { status: 422, body: { detail: "MusicBrainz couldn't read that search - try other words" } }]
    globalThis.fetch = () => { const next = answers.shift(); return Promise.resolve({ ok: false, status: next.status, json: async () => next.body }) }
    const caught = []
    for (let n = 0; n < 3; n++) await MB.searchArtists('x', 10).catch((error) => caught.push([error.constructor.name, error.status, error.busy]))
    check('a 503 whose body says busy: MusicBrainzUnavailable, busy; any other 503 not busy (whatever its words); a 422 an ApiError with its words',
      caught, [['MusicBrainzUnavailable', 503, true], ['MusicBrainzUnavailable', 503, false], ['ApiError', 422, false]])
    globalThis.fetch = fetchBefore
  }

  console.log('\nthe real prefetch (player/api.ts): a scroll calls off a tile\'s ask, never one Search keeps; the library\'s page')
  {
    const fetches = []
    globalThis.fetch = (url, init) => new Promise((resolve, reject) => {
      const entry = { url, aborted: false, answer: () => resolve({ ok: true, status: 200, json: async () => ({ id: url.split('/').pop(), song: [], artists: [], albums: [], songs: [] }) }),
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
    const flaky = api.prefetchAlbum('flaky', true)
    flaky.catch(() => {})
    check('a kept ask still out is the one handed back', [api.prefetchAlbum('flaky', true) === flaky, fetches.length], [true, 6])
    fetches[5].fail()
    await settle()
    check('...and once it has failed, it is let go: the next asks afresh', [api.prefetchAlbum('flaky', true) === flaky, fetches.length], [false, 7])
    //? (2.0.0-player.55) the library's search with a page: the two-argument call asks what it always did
    void api.searchLibrary('portishead')
    void api.searchLibrary('portishead', undefined, { counts: { artistCount: 0, albumCount: 50, songCount: 0 }, offsets: { albumOffset: 50 } })
    void api.searchLibrary('portishead', undefined, { counts: { artistCount: 50, albumCount: 0, songCount: 0 }, offsets: { artistOffset: 0 } })
    const query = (url) => Object.fromEntries(new URL(url, 'http://deadwax.test').searchParams)
    check('searchLibrary: two arguments ask SEARCH_COUNTS as ever; a page its counts, and an offset only past the first page',
      fetches.slice(-3).map((entry) => query(entry.url)),
      [{ q: 'portishead', artistCount: '5', albumCount: '8', songCount: '12' }, { q: 'portishead', artistCount: '0', albumCount: '50', songCount: '0', albumOffset: '50' },
        { q: 'portishead', artistCount: '50', albumCount: '0', songCount: '0' }])
  }

  console.log(failures ? `\n${failures} FAILED of ${checks}` : `\nall ${checks} passed`)
  process.exit(failures ? 1 : 0)
}

main()
