/**
 * Home as it is finished (2.0.0-player.18): "Not played in a while" - the pure rule in lib/home.ts -
 * and Home itself (app/Home.tsx) drawing Pinned, Recently added and Not played in a while, compiled
 * with the repo's TypeScript and rendered by a small stand-in for Preact into plain objects, with
 * Navidrome's lists and the pins faked.
 *
 * What it pins:
 *
 *  - The rule (slices.md S7): from getAlbumList2 `recent` at 500, the albums whose OpenSubsonic
 *    `played` is MORE than 30 days old, the longest ago first (ties by id), up to 20 - and none at all
 *    with fewer than 4, or when no album carries `played` (a Navidrome that doesn't send it); an
 *    album without it, or with one that can't be read, or one in the future, is left out; an album
 *    listed twice counts once. The scratch stub's seeded plays (The Slow Rush 41 days, Dummy 64, Third
 *    95, Wish You Were Here 210, Donda 3) show exactly four, oldest first.
 *  - Home: Recently added asks `newest` at 20 and Not played asks `recent` at 500, both through the
 *    page; Not played draws its section only with something to show - no heading otherwise, nor
 *    after a failure - its tiles in the rule's order, each opening its album.
 *  - The order, as the board and James have it: Pinned at the top, then Recently added, then Not
 *    played in a while - all inside the Navidrome gate.
 *  - New in your library (2.0.0-player.51, logins on): under Pinned and over Recently added, its tiles
 *    opening their albums; none, no shelf; waited for as the pins are (null: not said yet), never past
 *    the wait; a Home handed nothing (logins off) draws none and waits for none.
 *  - (2.0.5, UX batch 2 - James: Home's Recently added shows the listener's OWN library) with a library of your
 *    own (`personal`) Recently added is YOURS: the Library's own list (app/albumIndex.ts `yours`, never getAlbumList2
 *    `newest`, which is the whole collection's), newest first by `created`, at most RECENT_COUNT; asked again as your
 *    albums' generation moves (an Add, a Remove, your library's count); empty, your library's own empty words. With
 *    logins off it is `newest` at 20, as it always was (the first case above).
 *  - The pins are asked afresh each time Home comes into view, and not while it doesn't show; the
 *    shelves are drawn only once the pins have answered (or failed, or PINNED_WAIT_MS has passed while
 *    Home showed - the wait counts only while it shows, afresh each time it comes into view until it
 *    has once run out) - Recently added asking all the while, out of sight - so Pinned landing never
 *    moves the shelves under a finger.
 *  - (2.0.15) Recently played: getAlbumList2 `recent` at RECENT_COUNT (never Not played's 500, which stays an ask of
 *    its own), an album once, in Navidrome's order; under New in your library and over Recently added (Pinned, New in
 *    your library, Recently played, Recently added, Not played in a while); its tiles opening their album, never
 *    playing it; waited for as the pins are. Its rules (lib/home.ts playedLanded) never move Recently added once Home
 *    is drawn: a slow answer holds the shelf's height (heading, and one tile's shape unseen) until it lands; an empty
 *    answer or a failure known before Home was drawn is no shelf at all, and after it one line in that same height
 *    (errorNote's words for a failure) until Home is next out of view; a shelf that wasn't there finding albums on
 *    screen appears only once Home is out of view; and (review) on the desktop, whose grid wraps six across, an answer
 *    on screen keeps the rows drawn - more albums than they hold wait for Home to be out of view, fewer leave the drawn
 *    tiles (lib/home.ts playedRows; the phone's one sideways row is always one). Asked again each time Home comes into view, the tiles kept
 *    meanwhile (no spinner, no held row) and a failed ask again leaving them; an unchanged answer the very state it
 *    found (so the memo holds); a download moving on Home (Arriving) asks nothing.
 *
 * A script for the same reason as the other sims: there is no JS test runner here.
 *
 * Run it with:  node ui/test/home.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-home-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/home.ts', 'src/app/Home.tsx', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor whose effects run on commit - artist.sim.cjs's stand-in
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
exports.useCallback = (f) => f
exports.useEffect = exports.useLayoutEffect = (f, deps) => {
  const s = slot(() => ({}))
  if (changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f }
}
exports.root = (component) => {
  const root = { slots: [], cursor: 0, effects: [] }
  const render = (props) => { const outer = current; current = root; root.cursor = 0; try { return component(props) } finally { current = outer } }
  render.commit = () => { for (const s of root.effects.splice(0)) { if (typeof s.cleanup === 'function') s.cleanup(); s.cleanup = s.f() } }
  return render
}
`)

//? Navidrome's album lists and the pins: every ask kept, each answered when the test says
const write = (file, body) => fs.writeFileSync(path.join(OUT, file), body)
write('player/api.js', `
exports.albumPage = (order, offset, signal, size) => globalThis.__home.ask('albums', order, size)
exports.albumIndexOf = (scope) => globalThis.__home.ask('index', scope)
exports.prefetchAlbum = (id) => { globalThis.__home.prefetched.push(id); return new Promise(() => {}) }
exports.dropPrefetch = () => {}
`)
write('player/Cover.js', `exports.Cover = function Cover() { return null }\n`)
write('app/usePins.js', `
exports.usePins = (ask) => { globalThis.__home.pinAsks.push(ask); return globalThis.__home.pins }
exports.movePin = (key, to) => globalThis.__home.moved.push([key, to])
exports.removePin = (key) => globalThis.__home.removed.push(key)
`)

const W = globalThis.__home = {
  asks: [], open: [], prefetched: [], pinAsks: [], moved: [], removed: [],
  pins: { pins: null, canSave: true, problem: null },
  ask(name, ...args) {
    W.asks.push([name, ...args])
    let resolve, reject
    const promise = new Promise((yes, no) => { resolve = yes; reject = no })
    W.open.push({ name, args, resolve, reject })
    return promise
  },
}
function answer(name, value, which = () => true) {
  const at = W.open.findIndex((one) => one.name === name && which(...one.args))
  if (at < 0) throw new Error(`nothing asked of ${name}`)
  const [one] = W.open.splice(at, 1)
  if (value instanceof Error) one.reject(value)
  else one.resolve(value)
}
//? the newest ask that matches - Recently played is asked again as Home comes into view, the older ask called off
function answerLast(name, value, which = () => true) {
  let at = -1
  W.open.forEach((one, i) => { if (one.name === name && which(...one.args)) at = i })
  if (at < 0) throw new Error(`nothing asked of ${name}`)
  const [one] = W.open.splice(at, 1)
  if (value instanceof Error) one.reject(value)
  else one.resolve(value)
}
function reset() {
  W.asks.length = 0; W.open.length = 0; W.prefetched.length = 0; W.pinAsks.length = 0; W.moved.length = 0; W.removed.length = 0
  W.pins = { pins: null, canSave: true, problem: null }
}

//? the shelves' wait (PINNED_WAIT_MS): a timer the test fires by hand
const timers = []
globalThis.setTimeout = (fn) => { const timer = { fn, live: true }; timers.push(timer); return timer }
globalThis.clearTimeout = (timer) => { if (timer) timer.live = false }
const waitOver = () => { for (const timer of timers.splice(0)) if (timer.live) timer.fn() }
const settle = () => new Promise((resolve) => setImmediate(resolve))

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const R = require(path.join(OUT, 'lib/home.js'))
const { Home, PINNED_WAIT_MS, RECENT_COUNT } = require(path.join(OUT, 'app/Home.js'))

let failures = 0
//? a check left waiting on an answer that never comes would end the script quietly, exit 0, with checks
//? unrun: the run has to reach its end to pass
let finished = false
process.on('exit', () => {
  if (!finished) {
    console.log('\nSTOPPED before the end - a check was left waiting')
    process.exitCode = 1
  }
})
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/* ===== a renderer that keeps each component's hooks from render to render, by its place ===== */

function mount(Component) {
  const roots = new Map()
  let tree = null
  const expand = (node, at) => {
    if (Array.isArray(node)) return node.map((child, index) => expand(child, `${at}.${child && child.key != null ? child.key : index}`))
    if (!node || typeof node !== 'object') return node
    if (typeof node.type === 'function') {
      const id = `${at}:${node.type.name}`
      if (!roots.has(id)) roots.set(id, hooks.root(node.type))
      return expand(roots.get(id)(node.props), id)
    }
    const children = node.props.children
    return children === undefined ? node : { ...node, props: { ...node.props, children: expand(children, at) } }
  }
  const draw = (props) => {
    tree = expand({ type: Component, props, key: null }, 'root')
    for (const root of roots.values()) root.commit()
    return tree
  }
  return { draw, tree: () => tree }
}

function find(test, within) {
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
  return words(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const headings = (tree) => find((node) => node.type === 'h2', tree).map(words)
//? one shelf's section, by its heading's id
const shelfOf = (tree, id) => find((node) => node.props?.['aria-labelledby'] === id, tree)[0]
const PLAYED_ID = 'app-played-title', ADDED_ID = 'app-recent-title', NOT_PLAYED_ID = 'app-not-played-title'
const tilesIn = (tree, id) => find(byClass('app-tile-title'), shelfOf(tree, id)).map(words)
//? the asks of `recent`: Recently played's at RECENT_COUNT, Not played's at 500
const PLAYED_ASK = (order, size) => order === 'recent' && size === 20
const NOT_PLAYED_ASK = (order, size) => order === 'recent' && size === 500

/* ===== the rule ===== */

const NOW = Date.parse('2026-10-03T12:00:00Z')
const DAY = 86_400_000
const ago = (days) => new Date(NOW - days * DAY).toISOString()
const played = (id, days) => ({ id, name: id, artist: 'x', ...(days === undefined ? {} : { played: ago(days) }) })

console.log('\nNot played in a while: which albums')
{
  check('the constants: recent at 500, more than 30 days, up to 20, at least 4', [R.RECENT_LISTED, R.NOT_PLAYED_DAYS, R.NOT_PLAYED_SHOWN, R.NOT_PLAYED_FEWEST], [500, 30, 20, 4])
  //? the scratch stub's seeded plays, in recent's own order (the most recent first)
  const stub = [played('donda', 3), played('slow-rush', 41), played('dummy', 64), played('third', 95), played('wywh', 210)]
  check('the scratch stub\'s plays: exactly four, the longest ago first', R.notPlayedInAWhile(stub, NOW).map((a) => a.id), ['wywh', 'third', 'dummy', 'slow-rush'])
  check('fewer than four: no shelf', R.notPlayedInAWhile(stub.slice(0, 4), NOW).map((a) => a.id), [])
  check('no album carries played: no shelf', R.notPlayedInAWhile(stub.map(({ played: _, ...rest }) => rest), NOW), [])
  const edge = [played('a', 30), played('b', 31), played('c', 40), played('d', 50), played('e', 60)]
  check('exactly 30 days is not MORE than 30', R.notPlayedInAWhile(edge, NOW).map((a) => a.id), ['e', 'd', 'c', 'b'])
  const justOver = { id: 'just', played: new Date(NOW - 30 * DAY - 1).toISOString() }
  check('...a moment past it is', R.notPlayedInAWhile([justOver, ...edge.slice(1)], NOW).map((a) => a.id), ['e', 'd', 'c', 'b', 'just'])
  check('an album without played, or one that can\'t be read, or in the future, is left out',
    R.notPlayedInAWhile([...edge.slice(1), played('none'), { id: 'junk', played: 'last tuesday' }, { id: 'later', played: new Date(NOW + DAY).toISOString() }, { id: 'blank', played: '  ' }], NOW).map((a) => a.id),
    ['e', 'd', 'c', 'b'])
  const many = Array.from({ length: 30 }, (_, i) => played(`n${String(i).padStart(2, '0')}`, 40 + i))
  const shown = R.notPlayedInAWhile(many, NOW)
  check('more than twenty: the twenty played longest ago, oldest first', [shown.length, shown[0].id, shown[19].id], [20, 'n29', 'n10'])
  check('the same moment: by id, so the order holds still', R.notPlayedInAWhile([played('z', 50), played('y', 50), played('x', 50), played('w', 50)], NOW).map((a) => a.id), ['w', 'x', 'y', 'z'])
  check('an album listed twice counts once (and four distinct are needed)',
    R.notPlayedInAWhile([played('a', 50), played('a', 50), played('b', 60), played('c', 70)], NOW).map((a) => a.id), [])
  check('when it was played, read as Navidrome writes it', [R.playedAt({ id: 'x', played: '2026-08-23T12:00:00.000Z' }), R.playedAt({ id: 'x' }), R.playedAt({ id: 'x', played: 'soon' })],
    [Date.parse('2026-08-23T12:00:00Z'), null, null])
}

console.log('\nRecently played: which albums, and what the shelf draws (2.0.15)')
{
  const tile = (id, more = {}) => ({ id, name: id, artist: 'x', ...more })
  check('recent\'s order, an album once, up to the count',
    [R.recentlyPlayed([tile('b'), tile('a'), tile('b'), tile('c')], 20).map((a) => a.id), R.recentlyPlayed(Array.from({ length: 30 }, (_, i) => tile(`p${i}`)), 20).length],
    [['b', 'a', 'c'], 20])
  const two = [tile('a'), tile('b')]
  const ASKING = R.PLAYED_ASKING, NONE = { shelf: { kind: 'none' }, later: null }
  const kinds = (state) => [state.shelf.kind, state.later?.kind ?? null]
  check('before Home is drawn: albums are tiles, nothing played and a failure are no shelf at all',
    [kinds(R.playedLanded(ASKING, { albums: two }, false, 20)), kinds(R.playedLanded(ASKING, { albums: [] }, false, 20)), kinds(R.playedLanded(ASKING, { error: new Error('x') }, false, 20))],
    [['tiles', null], ['none', null], ['none', null]])
  check('the held row on screen: albums are tiles in its place; nothing played one line in it, a failure its words - each gone once Home is out of view',
    [kinds(R.playedLanded(ASKING, { albums: two }, true, 20)), kinds(R.playedLanded(ASKING, { albums: [] }, true, 20)), kinds(R.playedLanded(ASKING, { error: new Error('x') }, true, 20))],
    [['tiles', null], ['nothing', 'none'], ['failed', 'none']])
  check('no shelf on screen finding albums: still none until Home is out of view, then the tiles',
    [kinds(R.playedLanded(NONE, { albums: two }, true, 20)), kinds(R.playedOutOfView(R.playedLanded(NONE, { albums: two }, true, 20))),
      kinds(R.playedLanded(NONE, { albums: two }, false, 20))],
    [['none', 'tiles'], ['tiles', null], ['tiles', null]])
  const drawn = R.playedLanded(ASKING, { albums: two }, true, 20)
  check('an unchanged answer is the very state it found - the memo holds, the tiles aren\'t redrawn',
    [R.playedLanded(drawn, { albums: [tile('a'), tile('b')] }, true, 20) === drawn, R.playedLanded(drawn, { albums: [tile('a'), tile('b')] }, false, 20) === drawn], [true, true])
  check('...a new order, a new cover or a new name is a new answer', [
    R.playedLanded(drawn, { albums: [tile('b'), tile('a')] }, true, 20).shelf.albums.map((a) => a.id),
    R.playedLanded(drawn, { albums: [tile('a', { coverArt: 'c' }), tile('b')] }, true, 20) === drawn,
    R.playedLanded(drawn, { albums: [tile('a', { name: 'A' }), tile('b')] }, true, 20) === drawn], [['b', 'a'], false, false])
  check('a failed ask again leaves the tiles; tiles finding nothing played on screen keep their height',
    [R.playedLanded(drawn, { error: new Error('x') }, true, 20) === drawn, kinds(R.playedLanded(drawn, { albums: [] }, true, 20)), kinds(R.playedLanded(drawn, { albums: [] }, false, 20))],
    [true, ['nothing', 'none'], ['none', null]])
  check('out of view with nothing waiting: the very state', R.playedOutOfView(drawn) === drawn, true)
  //? (review) a failure heard by a shelf not asking - none, or the held row's one line - changes nothing: a failed ask
  //? again after an empty first answer never puts a heading over Recently added
  const NOTHING = R.playedLanded(ASKING, { albums: [] }, true, 20)
  check('a failure heard by no shelf, or by the held row saying nothing was played: the very state, on screen or not',
    [R.playedLanded(NONE, { error: new Error('x') }, true, 20) === NONE, R.playedLanded(NONE, { error: new Error('x') }, false, 20) === NONE,
      R.playedLanded(NOTHING, { error: new Error('x') }, true, 20) === NOTHING], [true, true, true])
  check('...a new artist line, or more albums after the same ones, is a new answer too', [
    R.playedLanded(drawn, { albums: [tile('a', { artist: 'y' }), tile('b')] }, true, 20).shelf.albums[0].artist,
    R.playedLanded(drawn, { albums: [tile('a'), tile('b'), tile('c')] }, true, 20).shelf.albums.map((a) => a.id),
    R.samePlayed([tile('a'), tile('b')], [tile('a')])], ['y', ['a', 'b', 'c'], false])

  //? (review) the desktop's shelf is a grid six across that wraps: on screen what lands keeps the ROWS drawn
  const many = (n) => Array.from({ length: n }, (_, i) => tile(`d${i}`))
  const ids = (state) => state.shelf.kind === 'tiles' ? state.shelf.albums.length : state.shelf.kind
  const later = (state) => state.later?.kind === 'tiles' ? state.later.albums.length : state.later?.kind ?? null
  check('how many rows: the held row one, no shelf none, tiles by the row - and the phone\'s sideways row always one',
    [R.playedRows({ kind: 'asking' }, 6), R.playedRows({ kind: 'none' }, 6), R.playedRows({ kind: 'tiles', albums: many(6) }, 6),
      R.playedRows({ kind: 'tiles', albums: many(7) }, 6), R.playedRows({ kind: 'tiles', albums: many(20) }, 6), R.playedRows({ kind: 'tiles', albums: many(20) }, Infinity)],
    [1, 0, 1, 2, 4, 1])
  const late = R.playedLanded(ASKING, { albums: many(20) }, true, 20, 6)
  check('a slow answer of twenty landing on the desktop\'s held row: six now (one row, the held row\'s), all twenty once Home is out of view',
    [ids(late), later(late), ids(R.playedOutOfView(late))], [6, 20, 20])
  check('...the phone\'s row (and before Home is drawn, any frame): all twenty at once',
    [ids(R.playedLanded(ASKING, { albums: many(20) }, true, 20)), later(R.playedLanded(ASKING, { albums: many(20) }, true, 20)),
      ids(R.playedLanded(ASKING, { albums: many(20) }, false, 20, 6))], [20, null, 20])
  const six = R.playedLanded(ASKING, { albums: many(6) }, false, 20, 6)
  const seven = R.playedLanded(six, { albums: [tile('new'), ...many(6)] }, true, 20, 6)
  check('six played (one row), a seventh landing on screen: the first row\'s six now - the new one first - all seven out of view',
    [ids(seven), seven.shelf.albums[0].id, later(seven), ids(R.playedOutOfView(seven))], [6, 'new', 7, 7])
  const four = R.playedLanded(ASKING, { albums: many(4) }, false, 20, 6)
  check('...four going to five on screen stays one row: drawn at once', [ids(R.playedLanded(four, { albums: many(5) }, true, 20, 6)), later(R.playedLanded(four, { albums: many(5) }, true, 20, 6))], [5, null])
  const twenty = R.playedLanded(ASKING, { albums: many(20) }, false, 20, 6)
  const fewer = R.playedLanded(twenty, { albums: many(7) }, true, 20, 6)
  check('fewer rows on screen (four going to two): the drawn tiles stay, the new ones out of view',
    [fewer.shelf === twenty.shelf, later(fewer), ids(R.playedOutOfView(fewer))], [true, 7, 7])
  const emptied = R.playedLanded(twenty, { albums: [] }, true, 20, 6)
  check('...four rows finding nothing played on screen: the tiles stay, no shelf out of view; one row says it in the row',
    [emptied.shelf === twenty.shelf, later(emptied), kinds(R.playedLanded(six, { albums: [] }, true, 20, 6))], [true, 'none', ['nothing', 'none']])
  const again = R.playedLanded(late, { albums: many(20) }, true, 20, 6)
  check('the first row drawn and the same twenty again on screen: the very tiles kept (the memo holds), twenty still waiting',
    [again.shelf === late.shelf, later(again)], [true, 20])
}

/* ===== Home ===== */

const OK = { configured: true, ok: true, server: 'Navidrome 0.64.2', problem: null }
const props = (more = {}) => ({ status: OK, onRetry() {}, onOpen: (album) => W.opened.push(album), arriving: [], onSeeAll() {}, shown: true, ...more })

async function run() {
  console.log('\nHome: what it asks, and when the shelves are drawn')
  {
    reset(); W.opened = []
    const home = mount(Home)
    let tree = home.draw(props({ shown: false }))
    check('not showing: the pins aren\'t asked', W.pinAsks.every((ask) => ask === false), true)
    const outside = (tree) => find(byClass('pl-spinner'), tree).length - find(byClass('pl-spinner'), find(byClass('app-home-shelves'), tree)[0]).length
    check('...and the shelves wait out of sight, a spinner in their place', [find(byClass('app-home-shelves'), tree)[0]?.props.hidden, outside(tree)], [true, 1])
    check('Recently played asks recent at 20, Recently added newest at 20, and Not played recent at 500, out of sight all the while',
      W.asks.map((one) => one.slice(0, 3)), [['albums', 'recent', RECENT_COUNT], ['albums', 'newest', RECENT_COUNT], ['albums', 'recent', 500]])
    check('...and the wait has not started while Home doesn\'t show', timers.length, 0)
    tree = home.draw(props({ shown: true }))
    check('coming into view: the pins asked afresh', W.pinAsks.slice(-1), ['fresh'])
    check('...and the wait starts', [timers.length, PINNED_WAIT_MS], [1, 1500])
    W.pins = { pins: [], canSave: true, problem: null }
    tree = home.draw(props())
    check('the pins answered, Recently played not yet: the shelves still wait (2.0.15)', [find(byClass('app-home-shelves'), tree)[0]?.props.hidden, outside(tree)], [true, 1])
    answerLast('albums', [{ id: 'nd-third', name: 'Third', artist: 'Portishead' }], PLAYED_ASK)
    await settle()
    tree = home.draw(props())
    check('...and it answered: the shelves drawn, no spinner in their place', [find(byClass('app-home-shelves'), tree)[0]?.props.hidden, outside(tree)], [false, 0])
    check('...Pinned at the top, then Recently played, then Recently added', headings(tree), ['Pinned', 'Recently played', 'Recently added'])
    answer('albums', [{ id: 'nd-dummy', name: 'Dummy', artist: 'Portishead' }], (order) => order === 'newest')
    await settle()
    tree = home.draw(props())
    check('Recently added drawn', tilesIn(tree, ADDED_ID), ['Dummy'])
    const stub = [played('donda', 3), played('slow-rush', 41), played('dummy', 64), played('third', 95), played('wywh', 210)]
    answer('albums', stub, NOT_PLAYED_ASK)
    await settle()
    tree = home.draw(props())
    check('Not played in a while LAST, with the rule\'s four in its order', [headings(tree), tilesIn(tree, NOT_PLAYED_ID)],
      [['Pinned', 'Recently played', 'Recently added', 'Not played in a while'], ['wywh', 'third', 'dummy', 'slow-rush']])
    find(byClass('app-tile'), shelfOf(tree, NOT_PLAYED_ID))[1].props.onClick()
    find(byClass('app-tile'), shelfOf(tree, NOT_PLAYED_ID))[1].props.onPointerDown()
    check('a tile opens its album, asking for its songs as the finger lands - it plays nothing', [W.opened.map((a) => a.id), W.prefetched], [['third'], ['third']])
    W.pinAsks.length = 0
    tree = home.draw(props({ shown: false }))
    tree = home.draw(props({ shown: true }))
    check('leaving and coming back into view: no ask while away, afresh as it comes back', W.pinAsks, [false, 'fresh'])
  }

  console.log('\nHome: Not played in a while with nothing to say draws nothing')
  for (const [label, list] of [
    ['three old ones', [played('a', 40), played('b', 50), played('c', 60)]],
    ['a Navidrome that sends no played', [played('a'), played('b'), played('c'), played('d'), played('e')]],
    ['nothing played at all', []],
    ['Navidrome failing', new Error('Navidrome isn\'t answering')],
  ]) {
    reset()
    W.pins = { pins: [], canSave: true, problem: null }
    const home = mount(Home)
    home.draw(props())
    answer('albums', list, NOT_PLAYED_ASK)
    await settle()
    const tree = home.draw(props())
    check(`${label}: no section, no heading`, headings(tree).includes('Not played in a while'), false)
  }

  console.log('\nHome: the wait, when the pins are slow')
  {
    reset()
    const home = mount(Home)
    let tree = home.draw(props())
    check('the pins not in yet: the shelves wait', find(byClass('app-home-shelves'), tree)[0]?.props.hidden, true)
    waitOver()
    tree = home.draw(props())
    check('PINNED_WAIT_MS on: drawn without them - no Pinned until they come (Recently played, unanswered too, holding its place)',
      [find(byClass('app-home-shelves'), tree)[0]?.props.hidden, headings(tree)], [false, ['Recently played', 'Recently added']])
    reset(); timers.length = 0
    const away = mount(Home)
    away.draw(props())
    away.draw(props({ shown: false }))
    tree = away.draw(props({ shown: true }))
    check('left mid-wait and come back to: the wait counts only while Home shows - afresh, so drawn out of sight it can\'t run out before the pins land',
      [timers.map((timer) => timer.live), find(byClass('app-home-shelves'), tree)[0]?.props.hidden], [[false, true], true])
    reset()
    W.pins = { pins: null, canSave: true, problem: "Couldn't get your pins: refused" }
    const failedPins = mount(Home)
    failedPins.draw(props())
    answerLast('albums', [], PLAYED_ASK)
    await settle()
    tree = failedPins.draw(props())
    check('the pins failed: drawn at once, Pinned saying why', [find(byClass('app-home-shelves'), tree)[0]?.props.hidden, words(find(byClass('app-pinned-note'), tree))],
      [false, "Couldn't get your pins: refused"])
  }

  console.log('\nHome: New in your library (2.0.0-player.51, logins on)')
  {
    reset(); W.opened = []
    W.pins = { pins: [], canSave: true, problem: null }
    const home = mount(Home)
    home.draw(props({ newAlbums: null }))
    answerLast('albums', [], PLAYED_ASK)
    await settle()
    let tree = home.draw(props({ newAlbums: null }))
    check('what is new not said yet: the shelves wait for it, as for the pins', find(byClass('app-home-shelves'), tree)[0]?.props.hidden, true)
    const fresh = [{ id: 'nd-third', name: 'Third', artist: 'Portishead', coverArt: 'nd-third' }]
    tree = home.draw(props({ newAlbums: fresh }))
    check('said: under Pinned, over Recently added', [find(byClass('app-home-shelves'), tree)[0]?.props.hidden, headings(tree)],
      [false, ['Pinned', 'New in your library', 'Recently added']])
    find(byClass('app-tile'), tree)[0].props.onClick()
    check('...its tile opens the album', W.opened.map((a) => a.id), ['nd-third'])
    tree = home.draw(props({ newAlbums: [] }))
    check('nothing new: no shelf, no heading', headings(tree).includes('New in your library'), false)
    reset(); timers.length = 0
    W.pins = { pins: [], canSave: true, problem: null }
    const slow = mount(Home)
    slow.draw(props({ newAlbums: null }))
    answerLast('albums', [], PLAYED_ASK)
    await settle()
    waitOver()
    tree = slow.draw(props({ newAlbums: null }))
    check('...and never said: drawn without it once the wait is over', [find(byClass('app-home-shelves'), tree)[0]?.props.hidden, headings(tree)], [false, ['Pinned', 'Recently added']])
    reset()
    W.pins = { pins: [], canSave: true, problem: null }
    const handedNothing = mount(Home)
    handedNothing.draw(props())
    answerLast('albums', [], PLAYED_ASK)
    await settle()
    tree = handedNothing.draw(props())
    check('a Home handed nothing (logins off): no shelf, and nothing waited for',
      [headings(tree).includes('New in your library'), find(byClass('app-home-shelves'), tree)[0]?.props.hidden], [false, false])
  }

  console.log('\nHome: Recently added is YOURS with a library of your own (2.0.5, UX batch 2)')
  {
    reset()
    W.pins = { pins: [], canSave: true, problem: null }
    const home = mount(Home)
    let tree = home.draw(props({ personal: true }))
    check('it asks the Library\'s own list of your albums - never the collection\'s newest - beside Recently played and Not played',
      W.asks.map((one) => one.slice(0, 3)), [['albums', 'recent', RECENT_COUNT], ['index', 'yours'], ['albums', 'recent', 500]])
    answerLast('albums', [], PLAYED_ASK)
    await settle()
    const mine = (id, created, starred) => ({ id, name: id, artist: 'x', ...(created ? { created } : {}), ...(starred ? { starred } : {}) })
    const many = Array.from({ length: RECENT_COUNT + 5 }, (_, i) => mine(`m${String(i).padStart(2, '0')}`, `2026-0${1 + (i % 9)}-1${i % 10}T00:00:00Z`,
      `2026-0${1 + (i % 9)}-1${i % 10}T12:00:00Z`))
    //? (2.0.11) `justAdded` the collection has had since 2019, starred into your library last: it leads; `newest`, the
    //? collection's newest, you added long ago
    answer('index', { albums: [mine('undated'), mine('older', '2025-01-02T00:00:00Z', '2025-01-03T00:00:00Z'),
      mine('newest', '2026-10-01T00:00:00Z', '2026-10-02T00:00:00Z'), mine('justAdded', '2019-05-05T00:00:00Z', '2026-10-23T08:00:00Z'), ...many], truncated: false })
    await settle()
    tree = home.draw(props({ personal: true }))
    const titles = find(byClass('app-tile-title'), find((node) => node.props?.['aria-labelledby'] === 'app-recent-title', tree)[0]).map(words)
    check('...newest first by when it was added to YOUR library (2.0.11: its star, not the collection\'s created), at most RECENT_COUNT, the undated never ahead of a dated one',
      [titles.length, titles[0], titles[1], titles.includes('undated'), titles.includes('older')], [RECENT_COUNT, 'justAdded', 'newest', false, false])
    const Y = require(path.join(OUT, 'app/useYourAlbums.js'))
    Y.forgetYourAlbums()
    tree = home.draw(props({ personal: true }))
    check('your albums changing (an Add, a Remove, your count moving) asks your list again - the tiles kept meanwhile',
      [W.asks.filter((one) => one[0] === 'index').length, find(byClass('app-tile-title'), find((node) => node.props?.['aria-labelledby'] === 'app-recent-title', tree)[0]).length],
      [2, RECENT_COUNT])
    answer('index', { albums: [], truncated: false })
    await settle()
    tree = home.draw(props({ personal: true }))
    check('...your library empty: its own words, never the collection\'s albums',
      words(find(byClass('app-library-empty'), tree)[0]), 'Nothing in your library yet.Look through All music and add the albums you like, or find new ones in Search and Get them.')
    check('...and nothing ever asked of the collection\'s newest', W.asks.some((one) => one[0] === 'albums' && one[1] === 'newest'), false)
    reset()
    W.pins = { pins: [], canSave: true, problem: null }
    const off = mount(Home)
    off.draw(props({ personal: false }))
    answer('albums', [], (order) => order === 'newest')
    answerLast('albums', [], PLAYED_ASK)
    await settle()
    tree = off.draw(props({ personal: false }))
    check('logins off: the collection IS your library - newest at 20, as ever, and its empty words',
      [W.asks.map((one) => one.slice(0, 3)).find((one) => one[1] === 'newest'), words(find((node) => node.props?.['aria-labelledby'] === 'app-recent-title', tree)[0]).endsWith('No albums yet.')],
      [['albums', 'newest', RECENT_COUNT], true])
  }

  console.log('\nHome: Recently played (2.0.15)')
  {
    reset(); W.opened = []
    W.pins = { pins: [], canSave: true, problem: null }
    const home = mount(Home)
    home.draw(props({ newAlbums: null }))
    check('it asks recent at RECENT_COUNT, through the page - Not played\'s 500 an ask of its own',
      W.asks.filter((one) => one[1] === 'recent').map((one) => one.slice(0, 3)), [['albums', 'recent', RECENT_COUNT], ['albums', 'recent', 500]])
    const list = [{ id: 'nd-dummy', name: 'Dummy', artist: 'Portishead' }, { id: 'nd-third', name: 'Third', artist: 'Portishead' }, { id: 'nd-dummy', name: 'Dummy', artist: 'Portishead' }]
    answerLast('albums', list, PLAYED_ASK)
    await settle()
    let tree = home.draw(props({ newAlbums: null }))
    check('...its answer in, what is new not yet: still waiting', find(byClass('app-home-shelves'), tree)[0]?.props.hidden, true)
    tree = home.draw(props({ newAlbums: [{ id: 'nd-new', name: 'New', artist: 'x' }] }))
    answer('albums', [{ id: 'nd-added', name: 'Added', artist: 'x' }], (order) => order === 'newest')
    answer('albums', [played('a', 40), played('b', 50), played('c', 60), played('d', 70)], NOT_PLAYED_ASK)
    await settle()
    tree = home.draw(props({ newAlbums: [{ id: 'nd-new', name: 'New', artist: 'x' }] }))
    check('the order: Pinned, New in your library, Recently played, Recently added, Not played in a while', headings(tree),
      ['Pinned', 'New in your library', 'Recently played', 'Recently added', 'Not played in a while'])
    check('...Navidrome\'s order, an album once', tilesIn(tree, PLAYED_ID), ['Dummy', 'Third'])
    const tiles = find(byClass('app-tile'), shelfOf(tree, PLAYED_ID))
    tiles[1].props.onPointerDown()
    tiles[1].props.onClick()
    check('a tile opens its album, its songs asked for as the finger lands - a button that plays nothing',
      [W.opened.map((a) => a.id), W.prefetched, tiles[1].type, Object.keys(tiles[1].props).filter((key) => key.startsWith('on')).sort()],
      [['nd-third'], ['nd-third'], 'button', ['onClick', 'onPointerCancel', 'onPointerDown']])

    const asksBefore = W.asks.length
    tree = home.draw(props({ newAlbums: [{ id: 'nd-new', name: 'New', artist: 'x' }], arriving: [{ id: 1 }] }))
    check('a download moving on Home (Arriving) asks nothing again', W.asks.length, asksBefore)
    home.draw(props({ shown: false, newAlbums: [{ id: 'nd-new', name: 'New', artist: 'x' }] }))
    check('out of view: nothing asked', W.asks.length, asksBefore)
    tree = home.draw(props({ shown: true, newAlbums: [{ id: 'nd-new', name: 'New', artist: 'x' }] }))
    check('coming into view: asked again - the tiles kept meanwhile, no spinner, no held row',
      [W.asks.slice(asksBefore).map((one) => one.slice(0, 3)), tilesIn(tree, PLAYED_ID), find(byClass('pl-spinner'), shelfOf(tree, PLAYED_ID)).length, find(byClass('app-shelf-held'), tree).length],
      [[['albums', 'recent', RECENT_COUNT]], ['Dummy', 'Third'], 0, 0])
    answerLast('albums', [{ id: 'nd-third', name: 'Third', artist: 'Portishead' }, { id: 'nd-dummy', name: 'Dummy', artist: 'Portishead' }], PLAYED_ASK)
    await settle()
    tree = home.draw(props({ newAlbums: [{ id: 'nd-new', name: 'New', artist: 'x' }] }))
    check('...a play moved the list: the new order lands in place', tilesIn(tree, PLAYED_ID), ['Third', 'Dummy'])
    home.draw(props({ shown: false, newAlbums: [{ id: 'nd-new', name: 'New', artist: 'x' }] }))
    home.draw(props({ shown: true, newAlbums: [{ id: 'nd-new', name: 'New', artist: 'x' }] }))
    answerLast('albums', new Error("Navidrome isn't answering"), PLAYED_ASK)
    await settle()
    tree = home.draw(props({ newAlbums: [{ id: 'nd-new', name: 'New', artist: 'x' }] }))
    check('...a failed ask again leaves the tiles as they were', [tilesIn(tree, PLAYED_ID), headings(tree)[2]], [['Third', 'Dummy'], 'Recently played'])
  }

  //? what Home's shelves draw, as the sections' order (Recently added's place is the count of sections over it) and
  //? the held row's shape: one tile's, the cover and both lines, unseen
  const place = (tree) => headings(tree).indexOf('Recently added')
  const heldShape = (tree) => {
    const held = find(byClass('app-shelf-held'), shelfOf(tree, PLAYED_ID))[0]
    if (!held) return null
    const ghost = find(byClass('app-shelf-ghost'), held)[0]
    return [ghost?.type, ghost?.props['aria-hidden'], find(byClass('app-shelf-item'), ghost).length, find(byClass('app-tile-cover'), ghost).length,
      find(byClass('app-tile-title'), ghost).map(words), find(byClass('app-tile-artist'), ghost).map(words)]
  }
  const SHAPE = ['ul', 'true', 1, 1, ['\u00a0'], ['\u00a0']]

  console.log('\nHome: Recently played never moves Recently added once Home is drawn')
  {
    //? slow: the wait ran out before it answered
    reset(); timers.length = 0
    W.pins = { pins: [], canSave: true, problem: null }
    const slow = mount(Home)
    slow.draw(props())
    waitOver()
    let tree = slow.draw(props())
    const before = place(tree)
    check('slow: Home drawn without its answer - its heading over a row held at a tile\'s shape, a spinner in it',
      [find(byClass('app-home-shelves'), tree)[0]?.props.hidden, headings(tree), heldShape(tree), find(byClass('pl-spinner'), shelfOf(tree, PLAYED_ID)).length, shelfOf(tree, PLAYED_ID)?.props['aria-busy']],
      [false, ['Pinned', 'Recently played', 'Recently added'], SHAPE, 1, true])
    answerLast('albums', [{ id: 'nd-dummy', name: 'Dummy', artist: 'Portishead' }], PLAYED_ASK)
    await settle()
    tree = slow.draw(props())
    check('...its answer lands in the held row\'s place: Recently added where it was', [place(tree), before, tilesIn(tree, PLAYED_ID), shelfOf(tree, PLAYED_ID)?.props['aria-busy']], [2, 2, ['Dummy'], false])

    //? empty after it was drawn
    reset(); timers.length = 0
    W.pins = { pins: [], canSave: true, problem: null }
    const empty = mount(Home)
    empty.draw(props())
    waitOver()
    empty.draw(props())
    answerLast('albums', [], PLAYED_ASK)
    await settle()
    tree = empty.draw(props())
    check('nothing played, said after Home was drawn: one line in the held row - Recently added where it was',
      [place(tree), heldShape(tree), words(find(byClass('app-shelf-held-say'), tree)[0])], [2, SHAPE, R.NOTHING_PLAYED])
    empty.draw(props({ shown: false }))
    tree = empty.draw(props({ shown: false }))
    check('...gone once Home is out of view', headings(tree).includes('Recently played'), false)
    tree = empty.draw(props({ shown: true }))
    check('...and coming back, drawn without it from the start, asked again', [headings(tree).includes('Recently played'), W.asks.filter((one) => PLAYED_ASK(one[1], one[2])).length], [false, 2])
    answerLast('albums', [{ id: 'nd-first', name: 'First', artist: 'x' }], PLAYED_ASK)
    await settle()
    tree = empty.draw(props())
    check('...the first play found on screen: no shelf appears over Recently added under a finger', [headings(tree).includes('Recently played'), place(tree)], [false, 1])
    empty.draw(props({ shown: false }))
    tree = empty.draw(props({ shown: false }))
    check('...it appears once Home is out of view', [headings(tree), tilesIn(tree, PLAYED_ID)], [['Pinned', 'Recently played', 'Recently added'], ['First']])

    //? an ask that lands while Home is out of view is drawn at once - nothing is under a finger there
    reset(); timers.length = 0
    W.pins = { pins: [], canSave: true, problem: null }
    const away = mount(Home)
    away.draw(props())
    answerLast('albums', [], PLAYED_ASK)
    await settle()
    away.draw(props())
    away.draw(props({ shown: false }))
    away.draw(props({ shown: true }))
    away.draw(props({ shown: false }))
    answerLast('albums', [{ id: 'nd-played', name: 'Played', artist: 'x' }], PLAYED_ASK)
    await settle()
    tree = away.draw(props({ shown: true }))
    check('an answer landing while Home is out of view: drawn as it comes back, nothing waiting for another visit',
      [headings(tree), tilesIn(tree, PLAYED_ID)], [['Pinned', 'Recently played', 'Recently added'], ['Played']])

    //? a failure after it was drawn
    reset(); timers.length = 0
    W.pins = { pins: [], canSave: true, problem: null }
    const failing = mount(Home)
    failing.draw(props())
    waitOver()
    failing.draw(props())
    //? a listener reading: someone who doesn't run deadwax (access.ts seesDetail) - the error's own words are never theirs
    const Access = require(path.join(OUT, 'app/access.js'))
    Access.noteAccess({ auth: 'on', user: 'ethan', admin: false, permissions: ['request'] })
    const raw = new Error("Navidrome isn't answering: ConnectError http://127.0.0.1:4533")
    answerLast('albums', raw, PLAYED_ASK)
    await settle()
    tree = failing.draw(props())
    const note = find(byClass('pl-notice'), find(byClass('app-shelf-held-say'), tree)[0])
    const E = require(path.join(OUT, 'lib/errorWords.js'))
    check('a failure after Home was drawn: errorNote\'s words in the held row - never the raw error - Recently added where it was',
      [place(tree), heldShape(tree), note.length, words(note[0]), /ConnectError|http|127\.0/.test(words(note[0]))],
      [2, SHAPE, 1, E.said(E.errorWords(raw, { service: 'music', admin: false })), false])
    Access.forgetAccess()
    failing.draw(props({ shown: false }))
    tree = failing.draw(props({ shown: false }))
    check('...gone once Home is out of view', headings(tree).includes('Recently played'), false)

    //? known before Home was drawn
    for (const [label, value] of [['nothing played', []], ['a failure', new Error('refused')]]) {
      reset(); timers.length = 0
      const early = mount(Home)
      early.draw(props())
      answerLast('albums', value, PLAYED_ASK)
      await settle()
      early.draw(props())
      W.pins = { pins: [], canSave: true, problem: null }
      tree = early.draw(props())
      check(`${label}, known before Home was drawn: no shelf at all, heading included`, [find(byClass('app-home-shelves'), tree)[0]?.props.hidden, headings(tree)],
        [false, ['Pinned', 'Recently added']])
    }
  }

  console.log('\nHome: all of it inside the Navidrome gate')
  {
    reset()
    const tree = mount(Home).draw(props({ status: { configured: true, ok: false, server: null, problem: 'refused' } }))
    check('Navidrome down: no Pinned and no shelves, the gate\'s words instead', [headings(tree).filter((h) => ['Pinned', 'Recently added'].includes(h)), headings(tree).includes("Can't reach Navidrome")], [[], true])
  }

  finished = true
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

run()
