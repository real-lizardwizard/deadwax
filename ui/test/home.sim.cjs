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
 *  - The pins are asked afresh each time Home comes into view, and not while it doesn't show; the
 *    shelves are drawn only once the pins have answered (or failed, or PINNED_WAIT_MS has passed while
 *    Home showed - the wait counts only while it shows, afresh each time it comes into view until it
 *    has once run out) - Recently added asking all the while, out of sight - so Pinned landing never
 *    moves the shelves under a finger.
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
    check('Recently added asks newest at 20, and Not played recent at 500, out of sight all the while',
      W.asks.map((one) => one.slice(0, 3)), [['albums', 'newest', RECENT_COUNT], ['albums', 'recent', 500]])
    check('...and the wait has not started while Home doesn\'t show', timers.length, 0)
    tree = home.draw(props({ shown: true }))
    check('coming into view: the pins asked afresh', W.pinAsks.slice(-1), ['fresh'])
    check('...and the wait starts', [timers.length, PINNED_WAIT_MS], [1, 1500])
    W.pins = { pins: [], canSave: true, problem: null }
    tree = home.draw(props())
    check('the pins answered: the shelves drawn, no spinner in their place', [find(byClass('app-home-shelves'), tree)[0]?.props.hidden, outside(tree)], [false, 0])
    check('...Pinned at the top, then Recently added', headings(tree), ['Pinned', 'Recently added'])
    answer('albums', [{ id: 'nd-dummy', name: 'Dummy', artist: 'Portishead' }], (order) => order === 'newest')
    await settle()
    tree = home.draw(props())
    check('Recently added drawn', find(byClass('app-tile'), tree).length, 1)
    const stub = [played('donda', 3), played('slow-rush', 41), played('dummy', 64), played('third', 95), played('wywh', 210)]
    answer('albums', stub, (order) => order === 'recent')
    await settle()
    tree = home.draw(props())
    check('Not played in a while LAST, with the rule\'s four in its order', [headings(tree), find(byClass('app-tile-title'), tree).slice(1).map(words)],
      [['Pinned', 'Recently added', 'Not played in a while'], ['wywh', 'third', 'dummy', 'slow-rush']])
    find(byClass('app-tile'), tree)[2].props.onClick()
    find(byClass('app-tile'), tree)[2].props.onPointerDown()
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
    answer('albums', list, (order) => order === 'recent')
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
    check('PINNED_WAIT_MS on: drawn without them - no Pinned until they come', [find(byClass('app-home-shelves'), tree)[0]?.props.hidden, headings(tree)], [false, ['Recently added']])
    reset(); timers.length = 0
    const away = mount(Home)
    away.draw(props())
    away.draw(props({ shown: false }))
    tree = away.draw(props({ shown: true }))
    check('left mid-wait and come back to: the wait counts only while Home shows - afresh, so drawn out of sight it can\'t run out before the pins land',
      [timers.map((timer) => timer.live), find(byClass('app-home-shelves'), tree)[0]?.props.hidden], [[false, true], true])
    reset()
    W.pins = { pins: null, canSave: true, problem: "Couldn't get your pins: refused" }
    tree = mount(Home).draw(props())
    check('the pins failed: drawn at once, Pinned saying why', [find(byClass('app-home-shelves'), tree)[0]?.props.hidden, words(find(byClass('app-pinned-note'), tree))],
      [false, "Couldn't get your pins: refused"])
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
