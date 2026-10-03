/**
 * Pins in the app (2.0.0-player.18): the pure rules (lib/pins.ts), the app's one store of them
 * (app/usePins.ts, the real one, against a faked deadwax), Home's Pinned with its Edit
 * (app/Pinned.tsx) and the pin on an album and an artist page (app/PinToggle.tsx) - compiled with the
 * repo's TypeScript and rendered by a small stand-in for Preact into plain objects.
 *
 * What it pins:
 *
 *  - Which pin is the thing on screen, as the server's toggle matches (src/routes/pins.py `same`): an
 *    album by its release, or by Navidrome's id where either side has none; an artist by MusicBrainz
 *    id where both have one, by a `name:` pin's folded name where the page has none (foldArtistName,
 *    held to tests/fixtures/name_folds.json, which test_pins.py holds the server's fold to), else by
 *    Navidrome's id. What a card says ("Artist", the album's artist, "Removed from the store", "Not on
 *    disk just now", "Not in Navidrome yet") and whether it opens. What a toggle sends - what the thing
 *    is, and only to pin, its card.
 *  - Edit's operations: a new pin first, an unpin by what it is, a move to a place, a removal by key,
 *    a drag landing where its rows say, and the PUT's whole list - never a pin not saved yet - with
 *    the list it was made from (`known`).
 *  - The store: nothing until asked; Home asks afresh every time, a page only when nothing recent is
 *    in hand; one ask at a time; a change shown at once and sent in turn, each answer - every pin -
 *    the server's word; a pin or an unpin refused put back and said in the app's notice, naming it
 *    (the menu's, which closes as it is tapped, says it worked too); one of Edit's refused put back,
 *    saying "Not saved: …" until the next change or a read; a move made into the PUT's list from the
 *    server's word as it stands when it goes, with that word as `known`, so it lands on what was saved
 *    before it and leaves a pin made on another device alone. `known` is true once the pins answered
 *    or failed to.
 *  - Pinned: two columns of cards - a card that opens is a button (an album asked for as the finger
 *    lands, opened as a tile opens it; an artist's page, by MusicBrainz id where the pin has one),
 *    one that doesn't is words; Edit makes rows with up, down and unpin, the ends' buttons
 *    aria-disabled, a row not saved yet not movable; moves and removals handed on by key and said
 *    aloud; focus kept - on a move's button where the row went, on the next row's unpin after an
 *    unpin, on Done with none left, on the heading once Done has gone; "Not saved" under the list; a
 *    drag by the grip lands where its distance says, the rows reordered under it as it goes, and
 *    nothing moves for a drag that comes back; Done goes back to the cards; nothing pinned says how.
 *  - The pin's control: pressed or not (aria-pressed), named "Pin to Home" on an album, "Pin" or
 *    "Pinned" on an artist; aria-disabled - its tap doing nothing - until what it pins is known, or
 *    while deadwax can't keep pins (a tap then saying why).
 *  - The notice: says what it is given, for PIN_NOTICE_MS, a newer one replacing it - and its region
 *    always in the page.
 *
 * A script for the same reason as the other sims: there is no JS test runner here.
 *
 * Run it with:  node ui/test/pins.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-pins-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/pins.ts', 'src/app/usePins.ts', 'src/app/Pinned.tsx', 'src/app/PinToggle.tsx', 'src/app/PinNotice.tsx', '--rootDir', 'src', '--outDir', OUT,
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

//? deadwax's pins routes, the album prefetch and the pictures: every ask kept, answered when the test says
const write = (file, body) => fs.writeFileSync(path.join(OUT, file), body)
write('api/me.js', `
exports.getPins = () => globalThis.__pins.ask('get')
exports.putPins = (body) => globalThis.__pins.ask('put', body)
exports.togglePin = (body) => globalThis.__pins.ask('toggle', body)
`)
write('player/api.js', `
exports.prefetchAlbum = (id) => { globalThis.__pins.prefetched.push(id); return new Promise(() => {}) }
exports.dropPrefetch = (id) => globalThis.__pins.dropped.push(id)
`)
write('player/Cover.js', `exports.Cover = function Cover(props) { return { type: 'img', props: { class: props.class, 'data-cover': props.id } } }\n`)

const W = globalThis.__pins = {
  asks: [], open: [], prefetched: [], dropped: [],
  ask(name, body) {
    W.asks.push(body === undefined ? [name] : [name, body])
    let resolve, reject
    const promise = new Promise((yes, no) => { resolve = yes; reject = no })
    W.open.push({ name, body, resolve, reject })
    return promise
  },
}
function answer(name, value) {
  const at = W.open.findIndex((one) => one.name === name)
  if (at < 0) throw new Error(`nothing asked of ${name}`)
  const [one] = W.open.splice(at, 1)
  if (value instanceof Error) one.reject(value)
  else one.resolve(value)
}
const settle = async () => { for (let i = 0; i < 6; i++) await new Promise((resolve) => setImmediate(resolve)) }

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const P = require(path.join(OUT, 'lib/pins.js'))
const S = require(path.join(OUT, 'app/usePins.js'))
const { Pinned, NOTHING_PINNED } = require(path.join(OUT, 'app/Pinned.js'))
const { PinToggle, PINS_UNSAVED } = require(path.join(OUT, 'app/PinToggle.js'))
const { PinNotice, PIN_NOTICE_MS } = require(path.join(OUT, 'app/PinNotice.js'))

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
  if (typeof node.type === 'function') return ''
  return words(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)

/* ===== the pins deadwax answers with ===== */

const CD = '11111111-1111-4111-8111-111111111111'
const VINYL = 'f5804905-0000-4000-8000-000000000000'
const PORTISHEAD = '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11'
const albumPin = (ref, more = {}) => ({ kind: 'album', ref, label: 'Dummy', sub: 'Portishead', state: 'present', navidrome_id: 'nd-cd', cover: 'al-nd-cd', release_mbid: CD, ...more })
const artistPin = (ref, more = {}) => ({ kind: 'artist', ref, label: 'Portishead', sub: '', state: 'present', navidrome_id: 'ar-p', cover: 'ar-p', mbid: PORTISHEAD, ...more })
const DUMMY = { kind: 'album', release_mbid: CD, navidrome_id: 'nd-cd', label: 'Dummy', sub: 'Portishead', cover: 'al-nd-cd' }
const ARTIST = { kind: 'artist', mbid: PORTISHEAD, navidrome_id: 'ar-p', name: 'Portishead', cover: 'ar-p' }

console.log('\nwhich pin is the thing on screen')
{
  const pins = [albumPin('store:1'), artistPin(`mb:${PORTISHEAD}`)]
  check('an album by its release', [P.pinOf(pins, DUMMY)?.ref, P.pinOf(pins, { ...DUMMY, release_mbid: VINYL })?.ref ?? null], ['store:1', null])
  check('...whatever Navidrome\'s id says, where both have a release (another pressing\'s pin is not this one)',
    P.pinOf([albumPin('store:2', { release_mbid: VINYL })], DUMMY), null)
  check('...and by Navidrome\'s id where either side has none - a page whose bridge hasn\'t answered yet',
    [P.pinOf(pins, { ...DUMMY, release_mbid: null })?.ref, P.pinOf([albumPin('store:3', { release_mbid: null })], { ...DUMMY, navidrome_id: 'nd-cd' })?.ref], ['store:1', 'store:3'])
  check('an artist by MusicBrainz id where both have one', [P.pinOf(pins, ARTIST)?.ref, P.pinOf(pins, { ...ARTIST, mbid: '87c5dedd-371d-4a53-9f7f-80522fb7f3cb' }) ?? null], [`mb:${PORTISHEAD}`, null])
  check('...else by Navidrome\'s id (a pin made by name always has one)',
    [P.pinOf([artistPin('name:bjork', { mbid: null, navidrome_id: 'ar-b' })], { ...ARTIST, mbid: null, navidrome_id: 'ar-b' })?.ref,
      P.pinOf([artistPin('name:bjork', { mbid: null, navidrome_id: 'ar-b' })], { ...ARTIST, mbid: PORTISHEAD, navidrome_id: 'ar-b' })?.ref,
      P.pinOf([artistPin('name:bjork', { mbid: null, navidrome_id: 'ar-b' })], { ...ARTIST, mbid: null, navidrome_id: null }) ?? null],
    ['name:bjork', 'name:bjork', null])
  check('...and a pin made by name is the artist whose name folds to it, where the page has no MusicBrainz id - as the server\'s key makes them one',
    [P.pinOf([artistPin('name:bjork', { mbid: null, navidrome_id: 'ar-1' })], { ...ARTIST, mbid: null, navidrome_id: 'ar-2', name: 'Björk' })?.ref,
      P.pinOf([artistPin('name:bjork', { mbid: null, navidrome_id: 'ar-1' })], { ...ARTIST, mbid: null, navidrome_id: null, name: ' BJORK ' })?.ref,
      P.pinOf([artistPin('name:bjork', { mbid: null, navidrome_id: 'ar-1' })], { ...ARTIST, mbid: PORTISHEAD, navidrome_id: 'ar-2', name: 'Björk' }) ?? null,
      P.pinOf([artistPin('name:bjork', { mbid: null, navidrome_id: 'ar-1' })], { ...ARTIST, mbid: null, navidrome_id: 'ar-2', name: 'Bjorn' }) ?? null],
    ['name:bjork', 'name:bjork', null, null])
  check('...two artists with their own MusicBrainz ids are two, whatever Navidrome\'s id says',
    P.pinOf([artistPin(`mb:${PORTISHEAD}`, { navidrome_id: 'ar-x' })], { ...ARTIST, mbid: '87c5dedd-371d-4a53-9f7f-80522fb7f3cb', navidrome_id: 'ar-x' }), null)
  const folds = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../tests/fixtures/name_folds.json'), 'utf8')).cases
  check('names fold as the server folds them - every case test_pins.py holds the server to',
    folds.filter(([name, folded]) => P.foldArtistName(name) !== folded).map(([name]) => name), [])
  check('an album is never an artist\'s pin, nor the other way', [P.pinOf([artistPin('x', { navidrome_id: 'nd-cd' })], DUMMY), P.pinOf([albumPin('y', { navidrome_id: 'ar-p' })], ARTIST)], [null, null])
  check('nothing in hand, nothing to match', [P.pinOf(null, DUMMY), P.pinOf(pins, null)], [null, null])
}

console.log('\nwhat a card says, and whether it opens')
{
  const lines = [artistPin('a'), albumPin('b'), albumPin('c', { state: 'gone', navidrome_id: null }), albumPin('d', { state: 'missing', navidrome_id: null }), albumPin('e', { navidrome_id: null })]
  check('"Artist", the album\'s artist, or why it won\'t open', lines.map(P.pinLine),
    ['Artist', 'Portishead', 'Removed from the store', 'Not on disk just now', 'Not in Navidrome yet'])
  check('...and whether each opens', lines.map(P.pinOpens), [true, true, false, false, false])
  check('an artist opens by MusicBrainz id alone', P.pinOpens(artistPin('f', { navidrome_id: null })), true)
}

console.log('\nwhat a toggle sends')
{
  check('pinning an album: what it is, and its card', P.toggleBody(DUMMY, true),
    { kind: 'album', pinned: true, navidrome_id: 'nd-cd', release_mbid: CD, label: 'Dummy', sub: 'Portishead', cover: 'al-nd-cd' })
  check('unpinning: what it is, nothing more', P.toggleBody(DUMMY, false), { kind: 'album', pinned: false, navidrome_id: 'nd-cd', release_mbid: CD })
  check('an artist: their ids and name', [P.toggleBody(ARTIST, true), P.toggleBody({ ...ARTIST, mbid: null }, false)],
    [{ kind: 'artist', pinned: true, navidrome_id: 'ar-p', mbid: PORTISHEAD, name: 'Portishead', cover: 'ar-p' }, { kind: 'artist', pinned: false, navidrome_id: 'ar-p', name: 'Portishead' }])
  check('nothing empty sent, and nothing past the server\'s limit',
    [P.toggleBody({ ...DUMMY, release_mbid: null, sub: '  ', cover: null }, true), P.toggleBody({ ...DUMMY, label: 'x'.repeat(300) }, true).label.length],
    [{ kind: 'album', pinned: true, navidrome_id: 'nd-cd', label: 'Dummy' }, P.LABEL_MAX])
}

console.log('\nEdit\'s operations')
{
  const list = [albumPin('store:1'), artistPin('mb:x', { mbid: 'x' }), albumPin('store:3', { release_mbid: VINYL, navidrome_id: 'nd-v' })]
  const refs = (pins) => pins.map((pin) => pin.ref)
  check('a new pin goes first, drawn as not saved yet', [refs(P.applyPinOp(list, { type: 'pin', target: { ...DUMMY, release_mbid: '22222222-2222-4222-8222-222222222222', navidrome_id: 'nd-r' }, ref: 'pending:1' })),
    P.applyPinOp(list, { type: 'pin', target: { ...DUMMY, release_mbid: '22222222-2222-4222-8222-222222222222', navidrome_id: 'nd-r' }, ref: 'pending:1' })[0].pending],
    [['pending:1', 'store:1', 'mb:x', 'store:3'], true])
  check('...unless it is pinned already', refs(P.applyPinOp(list, { type: 'pin', target: DUMMY, ref: 'pending:2' })), ['store:1', 'mb:x', 'store:3'])
  check('an unpin by what it is', refs(P.applyPinOp(list, { type: 'unpin', target: DUMMY })), ['mb:x', 'store:3'])
  check('a move to a place, and to past either end', [refs(P.applyPinOp(list, { type: 'move', key: 'album:store:3', to: 0 })), refs(P.applyPinOp(list, { type: 'move', key: 'album:store:1', to: 9 })), refs(P.applyPinOp(list, { type: 'move', key: 'album:store:1', to: -4 }))],
    [['store:3', 'store:1', 'mb:x'], ['mb:x', 'store:3', 'store:1'], ['store:1', 'mb:x', 'store:3']])
  check('a move of a pin no longer there changes nothing', refs(P.applyPinOp(list, { type: 'move', key: 'album:store:9', to: 0 })), ['store:1', 'mb:x', 'store:3'])
  check('a removal by key', refs(P.applyPinOp(list, { type: 'remove', key: 'artist:mb:x' })), ['store:1', 'store:3'])
  check('the keys: kind and ref', P.pinKey(list[1]), 'artist:mb:x')
  check('a drag lands where its distance says, rows 60px apart', [P.dropIndex(1, 0, 60, 5), P.dropIndex(1, 29, 60, 5), P.dropIndex(1, 31, 60, 5), P.dropIndex(1, 130, 60, 5), P.dropIndex(1, -100, 60, 5), P.dropIndex(3, 999, 60, 5)],
    [1, 1, 2, 3, 0, 4])
  check('...and nowhere new with nothing to measure by', [P.dropIndex(2, 300, 0, 5), P.dropIndex(2, 300, NaN, 5)], [2, 2])
  check('while it drags: the dragged row follows the finger, the rows it passed make way', [0, 1, 2, 3, 4].map((index) => P.dragOffset(index, 1, 3, 130, 60)), [0, 130, -60, -60, 0])
  check('...going up, the other way', [0, 1, 2, 3, 4].map((index) => P.dragOffset(index, 3, 1, -110, 60)), [0, 60, 60, -110, 0])
  check('the PUT\'s whole list, never a pin not saved yet', P.orderBody([{ ...albumPin('pending:1'), pending: true }, ...list]),
    { pins: [{ kind: 'album', ref: 'store:1' }, { kind: 'artist', ref: 'mb:x' }, { kind: 'album', ref: 'store:3' }] })
  check('...and, made from the server\'s word, that word\'s list as `known`', P.orderBody(list.slice(1), list),
    { pins: [{ kind: 'artist', ref: 'mb:x' }, { kind: 'album', ref: 'store:3' }], known: [{ kind: 'album', ref: 'store:1' }, { kind: 'artist', ref: 'mb:x' }, { kind: 'album', ref: 'store:3' }] })
}

/* ===== the store ===== */

const answerOf = (pins, can_save = true) => ({ pins, can_save })

async function run() {
  console.log('\nthe store: asked, and only when asked')
  {
    S.forgetPins(); W.asks.length = 0; W.open.length = 0
    check('nothing until asked', [S.pinsNow(), W.asks, hooks.root(S.usePins)(false).known], [null, [], false])
    const first = S.askPins(false)
    const again = S.askPins(true)
    await settle()
    check('one ask at a time: a second shares the first', [first === again, W.asks], [true, [['get']]])
    answer('get', answerOf([albumPin('store:1')]))
    await settle()
    check('answered: the pins', S.pinsNow().map((pin) => pin.ref), ['store:1'])
    S.askPins(false)
    await settle()
    check('a page asking with a recent answer in hand: nothing asked', W.asks.length, 1)
    S.askPins(true)
    await settle()
    check('Home asks afresh whatever is in hand', W.asks.length, 2)
    answer('get', new Error('Failed to fetch'))
    await settle()
    check('a failed ask with an answer in hand: the answer stands, nothing said', [S.pinsNow().map((pin) => pin.ref), hooks.root(S.usePins)(false).problem], [['store:1'], null])
    S.forgetPins(); W.open.length = 0
    S.askPins(true)
    await settle()
    answer('get', new Error('Failed to fetch'))
    await settle()
    const render = hooks.root(S.usePins)
    check('...with none: the hook says why there are none - and they count as known, so no pin waits for ever', [render(false).problem, render(false).known],
      ["Couldn't get your pins: Failed to fetch", true])
  }

  console.log('\nthe store: the hook asks as it turns on')
  {
    S.forgetPins(); W.asks.length = 0; W.open.length = 0
    const render = hooks.root(S.usePins)
    render(false); render.commit()
    check('off: nothing asked', W.asks.length, 0)
    render('fresh'); render.commit()
    await settle()
    check('\'fresh\': asked', W.asks, [['get']])
    answer('get', answerOf([artistPin('mb:x')], false))
    await settle()
    const now = render('fresh'); render.commit()
    check('...the pins, and whether deadwax can keep them', [now.pins.map((pin) => pin.ref), now.canSave], [['mb:x'], false])
    render(true); render.commit()
    await settle()
    check('true, a recent answer in hand: nothing more asked', W.asks.length, 1)
  }

  console.log('\nthe store: a change shown at once, sent in turn, the answer the server\'s word')
  {
    S.forgetPins(); W.asks.length = 0; W.open.length = 0
    S.askPins(true); await settle(); answer('get', answerOf([albumPin('store:1', { release_mbid: VINYL, navidrome_id: 'nd-v' })])); await settle()
    const pinning = S.setPinned(DUMMY, true)
    check('pinned: on screen at once, first, not saved yet', [S.pinsNow().map((pin) => [pin.ref, !!pin.pending]), P.pinOf(S.pinsNow(), DUMMY) !== null],
      [[['pending:1', true], ['store:1', false]], true])
    await settle()
    check('...the toggle sent: what it is, and its card', W.asks.slice(-1), [['toggle', P.toggleBody(DUMMY, true)]])
    const unpinning = S.setPinned(DUMMY, false)
    check('unpinned straight after: off the screen at once', P.pinOf(S.pinsNow(), DUMMY), null)
    await settle()
    check('...and not sent until the pin has answered', W.asks.length, 2)
    answer('toggle', answerOf([albumPin('store:7'), albumPin('store:1', { release_mbid: VINYL, navidrome_id: 'nd-v' })]))
    await settle()
    check('...then sent, in turn', [W.asks.length, W.asks.slice(-1)[0]], [3, ['toggle', P.toggleBody(DUMMY, false)]])
    check('...the screen still the newest wish', P.pinOf(S.pinsNow(), DUMMY), null)
    answer('toggle', answerOf([albumPin('store:1', { release_mbid: VINYL, navidrome_id: 'nd-v' })]))
    await Promise.all([pinning, unpinning])
    check('both answered: the server\'s word', S.pinsNow().map((pin) => pin.ref), ['store:1'])
  }

  console.log('\nthe store: a change refused goes back, saying so where it was made')
  {
    S.forgetPins(); W.asks.length = 0; W.open.length = 0
    S.askPins(true); await settle(); answer('get', answerOf([albumPin('store:1')])); await settle()
    const going = S.setPinned(ARTIST, true)
    await settle()
    answer('toggle', new Error('Home holds up to 50 pins - unpin one first'))
    await going
    const render = hooks.root(S.usePins)
    check('a pin refused: gone again, said in the app\'s notice naming it - and not left on Home, naming nothing',
      [S.pinsNow().map((pin) => pin.ref), S.pinNotice()?.text, render(false).problem],
      [['store:1'], "Couldn't pin Portishead: Home holds up to 50 pins - unpin one first", null])
    const unpinning = S.setPinned(DUMMY, false)
    await settle()
    answer('toggle', new Error('Failed to fetch'))
    await unpinning
    check('...an unpin refused: back, and said', [S.pinsNow().map((pin) => pin.ref), S.pinNotice()?.text], [['store:1'], "Couldn't unpin Dummy: Failed to fetch"])
    const quiet = S.pinNotice().id
    const next = S.setPinned(ARTIST, true)
    await settle()
    answer('toggle', answerOf([artistPin('mb:p'), albumPin('store:1')]))
    await next
    check('a page\'s pin that worked says nothing: its control shows it', S.pinNotice().id, quiet)
    const menu = S.setPinned(DUMMY, false, true)
    await settle()
    answer('toggle', answerOf([artistPin('mb:p')]))
    await menu
    check('the menu\'s, which closes as it is tapped, says it worked', S.pinNotice().text, 'Unpinned Dummy from Home')
    const pinnedFromMenu = S.setPinned(DUMMY, true, true)
    await settle()
    answer('toggle', answerOf([albumPin('store:1'), artistPin('mb:p')]))
    await pinnedFromMenu
    check('...either way', S.pinNotice().text, 'Pinned Dummy to Home')
    const id = S.pinNotice().id
    S.clearPinNotice(id - 1)
    check('a notice is cleared only by its own end - a newer one stays', S.pinNotice()?.id, id)
    S.clearPinNotice(id)
    check('...and its own end clears it', S.pinNotice(), null)

    //? Edit's: said on Home, under the list, until the next change or a read
    const moving = S.movePin('album:store:1', 1)
    await settle()
    answer('put', new Error('deadwax couldn\'t save that'))
    await moving
    check('one of Edit\'s refused: back, and "Not saved: …" for Home', [S.pinsNow().map((pin) => pin.ref), render(false).problem], [['store:1', 'mb:p'], "Not saved: deadwax couldn't save that"])
    S.askPins(true); await settle(); answer('get', answerOf([albumPin('store:1'), artistPin('mb:p')])); await settle()
    check('...until a read: the server\'s word, read afresh, is what shows', render(false).problem, null)
    const again = S.removePin('artist:mb:p')
    await settle()
    answer('put', new Error('refused'))
    await again
    const later = S.movePin('album:store:1', 0)
    check('...or the next change', render(false).problem, null)
    await settle()
    answer('put', answerOf([albumPin('store:1'), artistPin('mb:p')]))
    await later
  }

  console.log('\nthe store: a move made into the PUT\'s list as it goes')
  {
    S.forgetPins(); W.asks.length = 0; W.open.length = 0
    const three = [albumPin('store:1'), artistPin('mb:x', { mbid: 'x', navidrome_id: 'ar-x' }), albumPin('store:3', { release_mbid: VINYL, navidrome_id: 'nd-v' })]
    S.askPins(true); await settle(); answer('get', answerOf(three)); await settle()
    const removing = S.removePin('album:store:1')
    const moving = S.movePin('album:store:3', 0)
    check('both on screen at once', S.pinsNow().map((pin) => pin.ref), ['store:3', 'mb:x'])
    await settle()
    const three_ = [{ kind: 'album', ref: 'store:1' }, { kind: 'artist', ref: 'mb:x' }, { kind: 'album', ref: 'store:3' }]
    check('the first sent alone: the whole list without it, and the list it was made from', W.asks.slice(-1),
      [['put', { pins: [{ kind: 'artist', ref: 'mb:x' }, { kind: 'album', ref: 'store:3' }], known: three_ }]])
    //? the server's answer holds a pin made on another device meanwhile, which the screen didn't know of
    const elsewhere = albumPin('store:9', { label: 'Third', release_mbid: '33333333-3333-4333-8333-333333333333', navidrome_id: 'nd-t' })
    answer('put', answerOf([...three.slice(1), elsewhere]))
    await settle()
    check('the move made from what the server said to the first - Third first, and the other device\'s pin kept, not unpinned',
      W.asks.slice(-1), [['put', { pins: [{ kind: 'album', ref: 'store:3' }, { kind: 'artist', ref: 'mb:x' }, { kind: 'album', ref: 'store:9' }],
        known: [{ kind: 'artist', ref: 'mb:x' }, { kind: 'album', ref: 'store:3' }, { kind: 'album', ref: 'store:9' }] }]])
    answer('put', answerOf([three[2], three[1], elsewhere]))
    await Promise.all([removing, moving])
    check('answered: the server\'s word', S.pinsNow().map((pin) => pin.ref), ['store:3', 'mb:x', 'store:9'])

    //? and the other way round: a removal after a move, its list made from the move's answer
    const moved = S.movePin('artist:mb:x', 0)
    const removed = S.removePin('album:store:3')
    await settle()
    const another = albumPin('store:11', { label: 'Roseland', release_mbid: '44444444-4444-4444-8444-444444444444', navidrome_id: 'nd-r' })
    answer('put', answerOf([three[1], three[2], elsewhere, another]))
    await settle()
    check('a removal made from what the server said to the move before it - the other device\'s new pin kept',
      W.asks.slice(-1), [['put', { pins: [{ kind: 'artist', ref: 'mb:x' }, { kind: 'album', ref: 'store:9' }, { kind: 'album', ref: 'store:11' }],
        known: [{ kind: 'artist', ref: 'mb:x' }, { kind: 'album', ref: 'store:3' }, { kind: 'album', ref: 'store:9' }, { kind: 'album', ref: 'store:11' }] }]])
    answer('put', answerOf([three[1], elsewhere, another]))
    await Promise.all([moved, removed])
  }

  /* ===== Pinned ===== */

  const mountPinned = (props) => {
    const render = hooks.root(Pinned)
    const opened = [], artists = [], moved = [], removed = []
    const all = { pins: null, problem: null, onOpenAlbum: (album) => opened.push(album), onOpenArtist: (artist) => artists.push(artist),
      onMove: (key, to) => moved.push([key, to]), onRemove: (key) => removed.push(key), ...props }
    const draw = (more = {}) => { Object.assign(all, more); const tree = render(all); render.commit(); return tree }
    return { draw, opened, artists, moved, removed }
  }
  const four = [albumPin('store:1'), artistPin(`mb:${PORTISHEAD}`), albumPin('store:2', { label: 'Third', state: 'gone', navidrome_id: null }), albumPin('store:3', { label: 'Mezzanine', sub: 'Massive Attack', release_mbid: VINYL, navidrome_id: 'nd-m' })]

  console.log('\nPinned: two columns of cards')
  {
    const view = mountPinned({ pins: four })
    const tree = view.draw()
    check('the heading and Edit', [words(find((node) => node.type === 'h2', tree)), words(find(byClass('app-pinned-edit'), tree))], ['Pinned', 'Edit'])
    const cards = find(byClass('app-pin-card'), tree)
    check('a card each: a button where it opens, words where it doesn\'t', cards.map((card) => [card.type, words(card)]),
      [['button', 'DummyPortishead'], ['button', 'PortisheadArtist'], ['div', 'ThirdRemoved from the store'], ['button', 'MezzanineMassive Attack']])
    check('an artist\'s picture round, an album\'s square', find(byClass('app-pin-thumb'), tree).map((node) => node.props.class), ['app-pin-thumb', 'app-pin-thumb is-round', 'app-pin-thumb', 'app-pin-thumb'])
    cards[0].props.onPointerDown(); cards[0].props.onClick(); cards[1].props.onPointerDown(); cards[1].props.onClick()
    check('an album opens as a tile does, its songs asked for as the finger lands; an artist\'s page by their MusicBrainz id (Navidrome\'s, kept since the pin was made, may name nobody now) - nothing plays',
      [view.opened, W.prefetched, view.artists],
      [[{ id: 'nd-cd', name: 'Dummy', artist: 'Portishead', coverArt: 'al-nd-cd' }], ['nd-cd'], [{ mbid: PORTISHEAD, name: 'Portishead', coverArt: 'ar-p' }]])
    const byName = mountPinned({ pins: [artistPin('name:bjork', { label: 'Björk', mbid: null, navidrome_id: 'ar-b', cover: null })] })
    find(byClass('app-pin-card'), byName.draw())[0].props.onClick()
    check('...one pinned by name, by Navidrome\'s id', byName.artists, [{ navidrome: 'ar-b', name: 'Björk', coverArt: null }])
    cards[3].props.onPointerCancel()
    check('a press that becomes a scroll calls its album\'s ask off', W.dropped, ['nd-m'])
  }

  console.log('\nPinned: nothing yet, nothing pinned, something not saved')
  {
    check('not answered: nothing drawn', mountPinned({}).draw(), null)
    const empty = mountPinned({ pins: [] }).draw()
    check('nothing pinned: how to pin, and no Edit', [words(find(byClass('app-pinned-empty'), empty)), find(byClass('app-pinned-edit'), empty).length], [NOTHING_PINNED, 0])
    const failed = mountPinned({ pins: four, problem: 'Not saved: refused' }).draw()
    const section = failed.props.children.flat(Infinity).filter((node) => node && typeof node === 'object')
    const at = (test) => section.findIndex(test)
    check('a change not saved: said UNDER the list - so its arriving and going move no row - in a region read out',
      [words(find(byClass('app-pinned-note'), failed)), at(byClass('app-pinned-note')) > at(byClass('app-pins')), find(byClass('app-pinned-note'), failed)[0].props.role],
      ['Not saved: refused', true, 'status'])
    const quiet = mountPinned({ pins: four }).draw()
    check('...its region always in the page, taking room only while it says something',
      [find(byClass('app-pinned-note'), quiet).length, find(byClass('is-said'), quiet).length, find(byClass('is-said'), failed).length], [1, 0, 1])
    const unread = mountPinned({ pins: null, problem: "Couldn't get your pins: refused" }).draw()
    check('the first read failed: the heading, and why', [words(find((node) => node.type === 'h2', unread)), words(find(byClass('app-pinned-note'), unread))], ['Pinned', "Couldn't get your pins: refused"])
  }

  console.log('\nPinned: Edit')
  {
    const view = mountPinned({ pins: four })
    let tree = view.draw()
    find(byClass('app-pinned-edit'), tree)[0].props.onClick()
    tree = view.draw()
    check('Edit: rows, and Done', [find(byClass('app-pin-row'), tree).length, find(byClass('app-pin-card'), tree).length, words(find(byClass('app-pinned-edit'), tree))], [4, 0, 'Done'])
    const disabled = (which) => find(byClass(`app-pin-${which}`), tree).map((node) => node.props['aria-disabled'])
    check('the first row can\'t go up, the last can\'t go down', [disabled('up'), disabled('down')], [[true, false, false, false], [false, false, false, true]])
    check('each named for its row', find(byClass('app-pin-move'), tree).slice(0, 3).map((node) => node.props['aria-label']), ['Move Dummy up', 'Move Dummy down', 'Unpin Dummy'])
    check('a row that won\'t open says why in two lines, as its card does', find(byClass('app-pin-row'), tree).map((node) => node.props.class.includes('is-closed')), [false, false, true, false])
    //? the page the browser would have drawn: each row's buttons, focus recorded
    const focused = []
    const button = (key, which) => ({ focus: () => focused.push(`${key} ${which}`), which })
    const fakeRow = (key, disabled = []) => ({
      dataset: { pin: key },
      querySelector: (selector) => {
        const which = selector.match(/app-pin-(up|down|remove)/)[1]
        return selector.includes(':not([aria-disabled') && disabled.includes(which) ? null : button(key, which)
      },
    })
    const lay = (keys) => {
      find(byClass('app-pins-edit'), tree)[0].props.ref.current = { querySelectorAll: () => keys.map((key) => fakeRow(key)) }
      find(byClass('app-pinned-edit'), tree)[0].props.ref.current = { focus: () => focused.push('done') }
      find((node) => node.type === 'h2', tree)[0].props.ref.current = { focus: () => focused.push('heading') }
    }
    lay(four.map((pin) => P.pinKey(pin)))
    find(byClass('app-pin-down'), tree)[1].props.onClick()
    tree = view.draw()
    check('a move by a button: focus back on that button, in the row where it went', focused, [`artist:mb:${PORTISHEAD} down`])
    find(byClass('app-pin-up'), tree)[0].props.onClick()
    lay(four.map((pin) => P.pinKey(pin)))
    find(byClass('app-pin-remove'), tree)[2].props.onClick()
    tree = view.draw()
    check('a move handed on by key and place - and the end\'s refused - and an unpin by key', [view.moved, view.removed], [[[`artist:mb:${PORTISHEAD}`, 2]], ['album:store:2']])
    check('...said aloud', words(find((node) => node.props?.role === 'status', tree)), 'Third unpinned')
    check('an unpin: focus to the next row\'s unpin - its own row, and button, have left the page', focused.slice(-1), ['album:store:3 remove'])
    lay(four.map((pin) => P.pinKey(pin)))
    find(byClass('app-pin-remove'), tree)[3].props.onClick()
    tree = view.draw()
    check('...the last row\'s: to the unpin of the row before', focused.slice(-1), ['album:store:2 remove'])
    const alone = mountPinned({ pins: [four[0]] })
    let aloneTree = alone.draw()
    find(byClass('app-pinned-edit'), aloneTree)[0].props.onClick()
    aloneTree = alone.draw()
    const aloneFocus = []
    const layAlone = () => {
      find(byClass('app-pinned-edit'), aloneTree)[0].props.ref.current = { focus: () => aloneFocus.push('done') }
      find((node) => node.type === 'h2', aloneTree)[0].props.ref.current = { focus: () => aloneFocus.push('heading') }
      const list = find(byClass('app-pins-edit'), aloneTree)[0]
      if (list) list.props.ref.current = { querySelectorAll: () => [] }
    }
    layAlone()
    find(byClass('app-pin-remove'), aloneTree)[0].props.onClick()
    aloneTree = alone.draw({ pins: [] })
    check('...the only row\'s: to Done, still there', [aloneFocus, words(find(byClass('app-pinned-edit'), aloneTree))], [['done'], 'Done'])
    layAlone()
    find(byClass('app-pinned-edit'), aloneTree)[0].props.onClick()
    aloneTree = alone.draw()
    check('...and Done with nothing pinned: the button goes, focus to the heading - never the page',
      [aloneFocus, find(byClass('app-pinned-edit'), aloneTree).length, find((node) => node.type === 'h2', aloneTree)[0].props.tabIndex], [['done', 'heading'], 0, -1])
    const live = mountPinned({ pins: [{ ...albumPin('pending:1', { label: 'Roseland' }), pending: true }, ...four] })
    let liveTree = live.draw()
    find(byClass('app-pinned-edit'), liveTree)[0].props.onClick()
    liveTree = live.draw()
    const row = find(byClass('app-pin-row'), liveTree)[0]
    find(byClass('app-pin-remove'), row)[0].props.onClick()
    find(byClass('app-pin-down'), row)[0].props.onClick()
    check('a pin not saved yet can\'t be moved or unpinned until it is', [find(byClass('app-pin-move'), row).map((node) => node.props['aria-disabled']), live.moved, live.removed, row.props.class.includes('is-pending')],
      [[true, true, true], [], [], true])
    find(byClass('app-pinned-edit'), tree)[0].props.onClick()
    tree = view.draw()
    check('Done: the cards again', [find(byClass('app-pin-card'), tree).length, words(find(byClass('app-pinned-edit'), tree))], [4, 'Edit'])
  }

  console.log('\nPinned: a drag by the grip')
  {
    const view = mountPinned({ pins: four })
    let tree = view.draw()
    find(byClass('app-pinned-edit'), tree)[0].props.onClick()
    tree = view.draw()
    //? the rows the browser would have laid out, 60px apart
    const rowAt = (index) => ({
      offsetTop: index * 60, offsetHeight: 52,
      get nextElementSibling() { return index < 3 ? rowAt(index + 1) : null },
      get previousElementSibling() { return index > 0 ? rowAt(index - 1) : null },
    })
    const captured = []
    const grip = (index) => find(byClass('app-pin-grip'), tree)[index]
    const pointer = (y, index = 1) => ({ button: 0, pointerId: 7, clientY: y, preventDefault() {}, currentTarget: { closest: () => rowAt(index), setPointerCapture: (id) => captured.push(id) } })
    check('only the grip takes the drag - hidden from a screen reader, which has the buttons', [find(byClass('app-pin-grip'), tree).length, grip(0).props['aria-hidden']], [4, 'true'])
    grip(1).props.onPointerDown(pointer(100))
    tree = view.draw()
    grip(1).props.onPointerMove(pointer(170))
    tree = view.draw()
    const order = () => find(byClass('app-pin-row'), tree).map((node) => node.key)
    const offsets = () => find(byClass('app-pin-row'), tree).map((node) => node.props.style?.transform ?? null)
    check('dragged down a row and a bit: the row it passed makes way, the pointer captured', [offsets(), captured],
      [[null, 'translateY(70px)', 'translateY(-60px)', null], [7]])
    check('...the row under the finger raised, following it - and the list\'s own order unchanged, so the grip keeps the pointer',
      [find(byClass('is-dragging'), tree).map((node) => node.key), order()],
      [[`artist:mb:${PORTISHEAD}`], ['album:store:1', `artist:mb:${PORTISHEAD}`, 'album:store:2', 'album:store:3']])
    grip(1).props.onPointerMove(pointer(-10))
    tree = view.draw()
    check('...and up past the first: it makes way the other way', offsets(), ['translateY(60px)', 'translateY(-110px)', null, null])
    grip(1).props.onPointerMove(pointer(170))
    tree = view.draw()
    check('nothing saved while it moves', view.moved, [])
    grip(1).props.onPointerUp(pointer(170))
    tree = view.draw()
    check('let go: handed on, by key and the place it landed', [view.moved, find(byClass('is-dragging'), tree).length], [[[`artist:mb:${PORTISHEAD}`, 2]], 0])
    grip(1).props.onPointerDown(pointer(100))
    tree = view.draw()
    grip(1).props.onPointerUp(pointer(110))
    check('a drag that comes back to where it began saves nothing', view.moved.length, 1)
    tree = view.draw()
    grip(0).props.onPointerDown({ ...pointer(100, 0), button: 2 })
    tree = view.draw()
    check('...nor does a press of another button', find(byClass('is-dragging'), tree).length, 0)
    grip(1).props.onPointerDown(pointer(100))
    tree = view.draw()
    grip(1).props.onPointerCancel(pointer(300))
    tree = view.draw()
    check('a drag the browser takes back (a cancel) puts it back and saves nothing', [view.moved.length, offsets()], [1, [null, null, null, null]])
  }

  /* ===== the notice ===== */

  console.log('\nthe app\'s one notice for pins')
  {
    S.forgetPins()
    const realTimeout = globalThis.setTimeout, realClear = globalThis.clearTimeout
    const timers = []
    globalThis.setTimeout = (fn, ms) => { const timer = { fn, ms, live: true }; timers.push(timer); return timer }
    globalThis.clearTimeout = (timer) => { if (timer) timer.live = false }
    try {
      const render = hooks.root(PinNotice)
      let node = render(); render.commit()
      check('nothing to say: its region in the page all the same, empty, clipped away', [node.props.role, node.props['aria-live'], node.props.class, words(node)],
        ['status', 'polite', 'app-pin-notice', ''])
      S.sayPins('Pinned Dummy to Home')
      node = render(); render.commit()
      check('something said: shown, for PIN_NOTICE_MS', [node.props.class, words(node), timers.filter((t) => t.live).map((t) => t.ms)],
        ['app-pin-notice is-shown', 'Pinned Dummy to Home', [PIN_NOTICE_MS]])
      S.sayPins('Couldn\'t pin Third: refused')
      node = render(); render.commit()
      check('a newer one replaces it, its own time starting', [words(node), timers.filter((t) => t.live).length], ["Couldn't pin Third: refused", 1])
      timers.filter((t) => t.live)[0].fn()
      node = render(); render.commit()
      check('...and goes when that is over', [node.props.class, words(node)], ['app-pin-notice', ''])
    } finally {
      globalThis.setTimeout = realTimeout
      globalThis.clearTimeout = realClear
    }
  }

  /* ===== the pin's control ===== */

  console.log('\nthe pin on an album page and an artist page')
  {
    const pressed = []
    const toggle = (props) => hooks.root(PinToggle)({ onToggle: () => pressed.push(props.look), ...props })
    const icon = toggle({ look: 'icon', pinned: false, ready: true })
    check('an album\'s: an icon button "Pin to Home", not pressed', [icon.props['aria-label'], icon.props['aria-pressed'], icon.props.class], ['Pin to Home', false, 'app-pin-toggle is-icon'])
    icon.props.onClick()
    check('...its tap toggles', pressed, ['icon'])
    const chip = toggle({ look: 'chip', pinned: true, ready: true })
    check('an artist\'s: a chip saying "Pinned", pressed, toggled', [words(chip), chip.props['aria-pressed'], chip.props.class, chip.props['aria-label']], ['Pinned', true, 'app-pin-toggle is-chip is-on', undefined])
    check('...or "Pin"', words(toggle({ look: 'chip', pinned: false, ready: true })), 'Pin')
    const waiting = toggle({ look: 'icon', pinned: false, ready: false })
    waiting.props.onClick()
    const unsaved = toggle({ look: 'chip', pinned: false, ready: true, unsaved: true })
    unsaved.props.onClick()
    check('what it pins not known yet, or deadwax unable to keep pins: aria-disabled, its tap doing nothing (and saying why)',
      [waiting.props['aria-disabled'], unsaved.props['aria-disabled'], unsaved.props.title, pressed], [true, true, PINS_UNSAVED, ['icon']])
    const refused = []
    toggle({ look: 'chip', pinned: false, ready: true, unsaved: true, onRefused: () => refused.push('unsaved') }).props.onClick()
    toggle({ look: 'chip', pinned: false, ready: false, onRefused: () => refused.push('waiting') }).props.onClick()
    check('...a tap while deadwax can\'t keep pins asks for why to be said - a title never shows on a phone; one while it waits, nothing',
      [refused, pressed], [['unsaved'], ['icon']])
  }

  finished = true
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

run()
