/**
 * Lyrics on Now Playing (2.1.6, notes/app-lyrics.md sections 2 and 3): the rules (lib/lyricsView.ts), the view
 * (player/Lyrics.tsx), the answers App keeps (app/useLyrics.ts), and the buttons that turn them on - Now Playing's
 * (player/NowPlaying.tsx) and the desktop bar's (player/PlayerBar.tsx) - compiled with the repo's TypeScript and drawn
 * by a small stand-in for Preact into plain objects, as info.sim.cjs draws the sheets. Every line of lyrics here is
 * invented.
 *
 * What it pins:
 *
 *  - The lit line (2.3): the lines whose time is the greatest not after the song's - none before the first, a shared
 *    stamp lighting every line written at it, a break lit as a line is, none at all in plain lyrics.
 *  - The clock (2.2): the element's own time, unless the reported position is further from it than a seek lands
 *    within - a seek on its way, and its target - so 2x speed's half second behind stays the element's.
 *  - The dots (2.4): only a lit break with the next line sung GAP_DOTS_S or more after it, in three steps by thirds; an
 *    outro none; an intro of 4 s or more given a break at 0, never a second one.
 *  - Following (2.5): held by the listener's own scroll for FOLLOW_AGAIN_MS while the song plays, paused held until it
 *    plays, held while the keyboard's focus is in the lines - never a tap's - and the lit line put at LYRICS_ANCHOR.
 *  - The words (2.1) verbatim, and the button's name and dimming for every row of 2.7.
 *  - The view: a tap on a line seeks there and plays when paused - in the tap - and lights it at once; the arrows move
 *    between the lines sung; one tab stop; the spinner, the failure (no Try again for a gone), none, nothing playing,
 *    plain lyrics' note.
 *  - The answers (2.6): asked at every song change; never while the page is hidden; a stale answer for the song before
 *    never drawn; what is kept drawn at once; a failure kept until Try again; the next song's asked once, near the end.
 *  - The buttons: Now Playing's on and off in place, pressed while on, dimmed off for a song with none (and a song with
 *    none, lyrics on, shows the cover); the bar's opening the panel, dimmed only while it is closed.
 *
 * Run it with:  node ui/test/lyrics.sim.cjs  (with a writable TMPDIR)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-lyrics-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/lyricsView.ts', 'src/player/Lyrics.tsx', 'src/app/useLyrics.ts', 'src/player/NowPlaying.tsx', 'src/player/PlayerBar.tsx',
  'src/api/http.ts',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor, as Preact's are - info.sim.cjs's stand-in, with useCallback.
//? Effects (layout ones too) run, in the order written, after a render whose deps changed.
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/jsx-runtime.js'), `
exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })
exports.Fragment = 'fragment'
`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `
let current = null
function slot(init) { const i = current.cursor++; if (!(i in current.slots)) current.slots[i] = init(); return current.slots[i] }
const changed = (a, b) => !a || !b || a.length !== b.length || a.some((v, i) => !Object.is(v, b[i]))
exports.useState = (v) => { const r = current; const s = slot(() => ({ v: typeof v === 'function' ? v() : v })); return [s.v, (x) => { const n = typeof x === 'function' ? x(s.v) : x; if (!Object.is(n, s.v)) r.asked = (r.asked ?? 0) + 1; s.v = n }] }
exports.useMemo = (f, deps) => { const s = slot(() => ({})); if (changed(s.deps, deps)) { s.v = f(); s.deps = deps } return s.v }
exports.useCallback = (f, deps) => exports.useMemo(() => f, deps)
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
  render.asked = () => root.asked ?? 0
  return render
}
`)
//? what is drawn inside is not what is tested here: covers and glyphs stand in, the engine's position hook reads 0,
//? the deck counts its wakes, and the lyrics' asks are answered by hand
fs.writeFileSync(path.join(OUT, 'player/Cover.js'), 'exports.Cover = function Cover() { return null }\n')
fs.writeFileSync(path.join(OUT, 'player/icons.js'), `
const glyph = (name) => { const f = function () { return null }; Object.defineProperty(f, 'name', { value: name }); return f }
module.exports = new Proxy({}, { get: (cache, name) => (cache[name] ??= glyph(String(name))) })
`)
fs.writeFileSync(path.join(OUT, 'player/usePlayer.js'), 'exports.usePosition = () => 0\n')
fs.renameSync(path.join(OUT, 'player/deck.js'), path.join(OUT, 'player/deck-real.js'))
fs.writeFileSync(path.join(OUT, 'player/deck.js'), `
module.exports = { ...require('./deck-real'), wakeDeckAudio: () => { globalThis.__wakes = (globalThis.__wakes ?? 0) + 1 } }
`)
fs.writeFileSync(path.join(OUT, 'player/api.js'), `
const asks = []
exports.asks = asks
exports.songLyrics = (id, signal) => new Promise((resolve, reject) => asks.push({ id, signal, resolve, reject }))
exports.discArtUrl = () => null
exports.playedAlbum = () => null
`)

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/* ===== a page: a clock, timers, frames, sizes, focus ===== */

const define = (name, value) => Object.defineProperty(globalThis, name, { value, configurable: true, writable: true })
let nowMs = 1_000_000
const timers = []
let timerIds = 0
define('performance', { now: () => nowMs })
define('setTimeout', (fn, ms = 0) => { const id = ++timerIds; timers.push({ id, at: nowMs + ms, fn }); return id })
define('clearTimeout', (id) => { const at = timers.findIndex((timer) => timer.id === id); if (at >= 0) timers.splice(at, 1) })
/** Time passing: every timer due runs, in order - one a timer sets inside the wait too. */
function wait(ms) {
  const until = nowMs + ms
  for (;;) {
    timers.sort((a, b) => a.at - b.at)
    const next = timers[0]
    if (!next || next.at > until) break
    timers.shift()
    nowMs = next.at
    next.fn()
  }
  nowMs = until
}
let frames = []
define('requestAnimationFrame', (fn) => { frames.push(fn); return frames.length })
define('cancelAnimationFrame', () => { frames = [] })
/** One frame: what asked for it runs (and asks for the next). */
function frame() { const now = frames; frames = []; for (const fn of now) fn(nowMs) }
const observers = []
define('ResizeObserver', class { constructor(fn) { this.fn = fn; observers.push(this) } observe(box) { this.box = box } disconnect() { this.gone = true } })
let reduced = false
define('matchMedia', (query) => ({ matches: reduced && /reduce/.test(query) }))

const LINE_PX = 40
const PAD_PX = 28
class FakeElement {
  constructor(tag) {
    this.tag = tag
    this.children = []
    this.dataset = {}
    this.listeners = new Map()
    this.scrolls = []
    this.scrollTop = 0
    this.clientHeight = 0
    this.classes = new Set()
    this.classList = { toggle: (c, on) => (on ? this.classes.add(c) : this.classes.delete(c)) }
  }
  focus() { document.activeElement = this }
  contains(other) { for (let at = other; at; at = at.parent) if (at === this) return true; return false }
  querySelector(tag) {
    for (const child of this.children) { if (child.tag === tag) return child; const deeper = child.querySelector(tag); if (deeper) return deeper }
    return null
  }
  addEventListener(name, fn) { this.listeners.set(name, [...(this.listeners.get(name) ?? []), fn]) }
  removeEventListener(name, fn) { this.listeners.set(name, (this.listeners.get(name) ?? []).filter((f) => f !== fn)) }
  //? an event from here, bubbling up through what holds it, as focusin, keydown and pointerdown do
  dispatch(name, event = {}) {
    for (let at = this; at; at = at.parent) for (const fn of [...(at.listeners.get(name) ?? [])]) fn({ target: this, ...event })
  }
  scrollTo(to) { this.scrolls.push(to); this.scrollTop = to.top }
}
const document = new FakeElement('#document')
document.visibilityState = 'visible'
document.body = new FakeElement('body')
document.documentElement = new FakeElement('html')
document.activeElement = document.body
define('document', document)
define('HTMLElement', FakeElement)

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))

/** A component drawn into plain objects: each element keeps one FakeElement across draws (a ref names it), knows its
 *  child elements, and sits LINE_PX under the one before it. Draws again while the last draw's effects changed state. */
function mount(component) {
  const render = hooks.root(component)
  const elements = new Map()
  let tree = null
  const walk = (node, where, parent) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach((child, i) => walk(child, `${where}.${i}`, parent)); return }
    if (typeof node.type === 'string') {
      const key = `${where}:${node.type}`
      if (!elements.has(key)) elements.set(key, new FakeElement(node.type))
      const element = node.element = elements.get(key)
      element.parent = parent
      element.children = []
      element.dataset = node.props['data-line'] === undefined ? {} : { line: String(node.props['data-line']) }
      if (parent) {
        element.offsetTop = PAD_PX + parent.children.length * LINE_PX
        parent.children.push(element)
      }
      if (node.props.ref) node.props.ref.current = element
    }
    walk(node.props?.children, `${where}/`, node.element ?? parent)
  }
  const view = {
    props: null,
    render(props = view.props) {
      view.props = props
      for (let pass = 0; pass < 8; pass += 1) {
        const asked = render.asked()
        tree = render(props)
        for (const element of elements.values()) element.parent = undefined
        walk(tree, '', null)
        render.commit()
        if (render.asked() === asked) break
      }
      return tree
    },
    find(test) {
      const hits = []
      const visit = (node) => {
        if (!node || typeof node !== 'object') return
        if (Array.isArray(node)) { node.forEach(visit); return }
        if (test(node)) hits.push(node)
        visit(node.props?.children)
      }
      visit(tree)
      return hits
    },
    one(test) { return view.find(test)[0] },
  }
  return view
}
function text(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(text).join('')
  if (typeof node.type !== 'string' && node.type !== 'fragment') return ''
  return text(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
/** a promise's then() has run */
const settle = () => new Promise((resolve) => setImmediate(resolve))

const V = require(path.join(OUT, 'lib/lyricsView.js'))
const { Lyrics } = require(path.join(OUT, 'player/Lyrics.js'))
const { useLyrics } = require(path.join(OUT, 'app/useLyrics.js'))
const { NowPlaying } = require(path.join(OUT, 'player/NowPlaying.js'))
const { PlayerBar } = require(path.join(OUT, 'player/PlayerBar.js'))
const { ApiError } = require(path.join(OUT, 'api/http.js'))
const api = require(path.join(OUT, 'player/api.js'))

//? invented lines - no song's
const at = (time, words) => ({ time, text: words })
const SONG = [at(5, 'Paper boats along the gutter'), at(10, 'Counting every streetlight twice'), at(15, ''), at(25, 'Morning finds the kettle singing'), at(30, 'Nobody remembers why')]

async function main() {
  console.log('\nthe words (2.1), verbatim')
  check('the button, the spinner, none, nothing playing, plain, a failure, a gone, the phone\'s hint and action',
    [V.LYRICS, V.LYRICS_NONE, V.LYRICS_NOT_KEPT, V.LOADING_LYRICS, V.NO_LYRICS, V.NOTHING_PLAYING, V.NOT_SYNCED, V.LYRICS_FAILED, V.SONG_GONE, V.LINE_HINT, V.GO_TO_LIT],
    ['Lyrics', 'Lyrics - none for this song', 'Lyrics - not on this phone', 'Loading lyrics', 'No lyrics for this song.', 'Nothing playing',
      "These lyrics aren't synced to the song.", "Couldn't load the lyrics.", "This song isn't here any more - it may have been moved or deleted.",
      'Plays from here.', 'Go to the line being sung'])
  check('the numbers: the anchor, following again, the dots\' gap, the next song\'s ask, how many kept',
    [V.LYRICS_ANCHOR, V.FOLLOW_AGAIN_MS, V.GAP_DOTS_S, V.NEXT_LYRICS_S, V.LYRICS_KEPT], [0.3, 4000, 4, 20, 50])
  check('a line\'s time to a screen reader, and the lit one\'s', [V.lineValue(83, false), V.lineValue(83, true)], ['1:23', '1:23, now'])

  console.log('\nthe button\'s states (2.7): named the same off and on, dimmed only while off and known to open nothing')
  const HAVES = ['unknown', 'some', 'none', 'not-kept']
  check('its name, by what is known', HAVES.map(V.lyricsLabel), ['Lyrics', 'Lyrics', 'Lyrics - none for this song', 'Lyrics - not on this phone'])
  check('dimmed while off', HAVES.map((have) => V.lyricsDimmed(have, false)), [false, false, true, true])
  check('never while on - a button that is on can always be turned off', HAVES.map((have) => V.lyricsDimmed(have, true)), [false, false, false, false])
  check('what an answer says: none is an answer with no lines; no answer is not known',
    [V.lyricsHave(null), V.lyricsHave(undefined), V.lyricsHave({ synced: true, lines: SONG }), V.lyricsHave({ synced: false, lines: [at(null, 'Plain words')] }), V.lyricsHave({ synced: false, lines: [] })],
    ['unknown', 'unknown', 'some', 'some', 'none'])

  console.log('\nthe lit line (2.3)')
  const shared = [at(5, 'One voice'), at(10, 'Both at once'), at(10, 'Both at once, the other'), at(15, ''), at(22, 'After the break')]
  check('none before the first line; on a stamp exactly; between; after the last',
    [V.litRange(shared, 0), V.litRange(shared, 4.99), V.litRange(shared, 5), V.litRange(shared, 7.5), V.litRange(shared, 100)],
    [null, null, { first: 0, last: 0 }, { first: 0, last: 0 }, { first: 4, last: 4 }])
  check('a shared stamp lights every line written at it; a break is lit as a line is', [V.litRange(shared, 10), V.litRange(shared, 14.9), V.litRange(shared, 15)],
    [{ first: 1, last: 2 }, { first: 1, last: 2 }, { first: 3, last: 3 }])
  check('none at all in plain lyrics, or with no lines', [V.litRange([at(null, 'Plain'), at(null, 'Words')], 30), V.litRange([], 30)], [null, null])
  check('a moment draws the same as another only with the same lines and dots',
    [V.sameLit(V.litAt(SONG, 6), V.litAt(SONG, 9)), V.sameLit(V.litAt(SONG, 9), V.litAt(SONG, 10)), V.sameLit(V.litAt(SONG, 15), V.litAt(SONG, 19))], [true, false, false])

  console.log('\nthe clock (2.2)')
  check('a seek on its way: its target, until it lands', [V.lyricsClock(30, 60), V.lyricsClock(59.9, 60)], [60, 59.9])
  check('2x speed\'s half second behind is still the element\'s own time', V.lyricsClock(30.5, 30), 30.5)
  check('it runs only while they show, play, are uncovered and in view',
    [V.clockRuns({ shows: true, playing: true, covered: false, visible: true }), V.clockRuns({ shows: false, playing: true, covered: false, visible: true }),
      V.clockRuns({ shows: true, playing: false, covered: false, visible: true }), V.clockRuns({ shows: true, playing: true, covered: true, visible: true }),
      V.clockRuns({ shows: true, playing: true, covered: false, visible: false })],
    [true, false, false, false, false])

  console.log('\nbreaks and the dots (2.4)')
  const short = [at(5, 'Before'), at(10, ''), at(13.9, 'After')]
  const long = [at(5, 'Before'), at(10, ''), at(16, 'After')]
  check('a gap of 3.9 s draws none', [V.gapDots(short, 1, 10), V.gapDots(short, 1, 12)], [0, 0])
  check('a gap of 4 s or more: one at the break, two a third of the way, three two thirds, none once the line comes',
    [V.gapDots(long, 1, 10), V.gapDots(long, 1, 11.9), V.gapDots(long, 1, 12), V.gapDots(long, 1, 13.9), V.gapDots(long, 1, 14), V.gapDots(long, 1, 15.99), V.gapDots(long, 1, 16)],
    [1, 1, 2, 2, 3, 3, 0])
  check('...only for a break: a sung line draws none', V.gapDots(long, 0, 7), 0)
  check('an outro - a break with nothing sung after it - draws none', V.gapDots([at(5, 'Last words'), at(40, '')], 1, 50), 0)
  check('an intro of 4 s or more gets a break at 0; of less, or one already there, not',
    [V.withIntro([at(4, 'Late')]), V.withIntro([at(3.9, 'Soon')]), V.withIntro([at(0, ''), at(9, 'Late')])],
    [[at(0, ''), at(4, 'Late')], [at(3.9, 'Soon')], [at(0, ''), at(9, 'Late')]])
  check('...and plain lyrics are never given one', V.withIntro([at(null, 'Plain')]), [at(null, 'Plain')])
  check('...whose dots then count to the first line', [V.litAt(V.withIntro([at(9, 'Late')]), 0), V.litAt(V.withIntro([at(9, 'Late')]), 6.5)],
    [{ range: { first: 0, last: 0 }, dots: 1 }, { range: { first: 0, last: 0 }, dots: 3 }])

  console.log('\nfollowing (2.5)')
  check('following until held', V.follows(nowMs, null, true), true)
  check('held: 3,999 ms after the last input still held, 4,000 following again', [V.follows(5999, 2000, true), V.follows(6000, 2000, true)], [false, true])
  check('paused, held past 4 s - and playing again, following', [V.follows(60000, 2000, false), V.follows(60000, 2000, true)], [false, true])
  check('keyboard focus in the lines holds it, held or not', [V.follows(60000, null, true, true), V.follows(60000, 2000, true, true)], [false, false])
  check('the lit line to the anchor: the top before it can reach it, a third of the way down after', [V.followTop(28, 400), V.followTop(500, 400), V.followTop(120, 400)], [0, 380, 0])
  check('the room after the last line lets it reach the anchor too', [V.endRoom(400), V.endRoom(0), V.endRoom(-5)], [280, 0, 0])

  console.log('\nthe keyboard (3.6)')
  const drawn = V.withIntro(SONG)
  check('one tab stop: the focused line, else the lit one, else the first sung',
    [V.tabStop(drawn, { first: 2, last: 2 }, 4), V.tabStop(drawn, { first: 2, last: 2 }, null), V.tabStop(drawn, { first: 0, last: 0 }, null), V.tabStop(drawn, null, null), V.tabStop([], null, null)],
    [4, 2, 1, 1, null])
  check('Up and Down to the line sung before and after - a break skipped; Home and End; nowhere, nothing',
    [V.lineAfterKey(drawn, 2, 'ArrowDown'), V.lineAfterKey(drawn, 4, 'ArrowUp'), V.lineAfterKey(drawn, 4, 'Home'), V.lineAfterKey(drawn, 1, 'End'),
      V.lineAfterKey(drawn, 1, 'ArrowUp'), V.lineAfterKey(drawn, 5, 'ArrowDown'), V.lineAfterKey(drawn, 2, 'Enter')],
    [4, 2, 1, 5, null, null, null])
  check('the keys that hold following - never Space, which plays from a line', [V.SCROLL_KEYS.includes('PageDown'), V.SCROLL_KEYS.includes(' ')], [true, false])

  console.log('\nasking and keeping (2.6)')
  check('the next song asked for with 20 s left, never with an unknown length', [V.asksAhead(179.9, 200), V.asksAhead(180, 200), V.asksAhead(10, 0)], [false, true, false])
  {
    const kept = new Map()
    for (const id of ['a', 'b', 'c']) V.keepLyrics(kept, id, { synced: false, lines: [] }, 2)
    const firstGone = [...kept.keys()]
    V.keptLyrics(kept, 'b')
    V.keepLyrics(kept, 'd', { synced: false, lines: [] }, 2)
    check('kept: the least recently used goes first, a read making it the most recent', [firstGone, [...kept.keys()], V.keptLyrics(kept, 'zz')], [['b', 'c'], ['b', 'd'], null])
  }

  console.log('\nthe view: the lit line, following, a tap, the keyboard')
  {
    const reported = new Set()
    const state = { position: 0, playing: true }
    const seeks = []
    let toggles = 0
    const player = {
      track: { id: 'song-1' },
      get playing() { return state.playing },
      position: () => state.position,
      onPosition: (fn) => { reported.add(fn); return () => reported.delete(fn) },
      seek: (seconds) => seeks.push(seconds),
      toggle: () => { toggles += 1 },
    }
    const answers = { song: 'song-1', lyrics: { synced: true, lines: SONG }, asking: false, error: null, retry() {} }
    const view = mount(Lyrics)
    const props = () => ({ player: { ...player, playing: state.playing }, answers, shows: true, covered: false, place: 'face' })
    view.render(props())
    const box = view.one(byClass('app-lyrics')).element
    box.clientHeight = 200
    for (const observer of observers) if (observer.box === box) observer.fn()
    view.render(props())
    const lines = () => view.find((node) => node.type === 'button' && byClass('app-lyric')(node))
    const lit = () => lines().filter((node) => node.props['aria-current'] === 'true').map((node) => node.props['data-line'])
    const dots = () => view.find(byClass('app-lyric-dot')).map((node) => byClass('is-lit')(node))
    const scrolls = () => box.scrolls.length
    const lastScroll = () => box.scrolls[box.scrolls.length - 1]
    //? the player reporting where the song is (its timeupdate, a moment behind) - and the frame after it
    const report = (seconds) => { for (const fn of reported) fn(seconds) }
    const run = (seconds) => { state.position = seconds; report(seconds - 0.25); frame(); view.render(props()) }

    check('a section named Lyrics, a phone\'s face; a button a line sung, a break between them, the room after the last line',
      [view.one(byClass('app-lyrics')).props['aria-label'], view.one(byClass('app-lyrics')).props.class, lines().length, view.find(byClass('app-lyric-break')).length,
        view.one(byClass('app-lyrics-end')).props.style['--app-lyrics-room']],
      ['Lyrics', 'app-lyrics is-face', 4, 2, '140px'])
    check('each line says its time to a screen reader, after its words, and reads its own direction',
      [text(lines()[0]), lines()[0].props.dir], ['Paper boats along the gutter, 0:05', 'auto'])
    check('the intro: its break lit, one dot of three - and no line lit', [lit(), dots()], [[], [true, false, false]])
    run(3.4)
    check('...three dots two thirds of the way to the first line', dots(), [true, true, true])
    run(5)
    check('the first line lit as its time comes - followed toward the anchor, smoothly, as far as the top allows', [lit(), dots(), lastScroll()], [[1], [], { top: PAD_PX + LINE_PX - 60, behavior: 'smooth' }])
    run(10)
    check('the next lit, and followed to the anchor: its top a third of the way down', [lit(), lastScroll()], [[2], { top: PAD_PX + 2 * LINE_PX - 60, behavior: 'smooth' }])
    check('one tab stop, on the lit line', lines().map((node) => node.props.tabIndex), [-1, 0, -1, -1])
    state.position = 24
    report(24)
    view.render(props())
    state.position = 25
    frame()
    view.render(props())
    check('the clock: once a frame, the element\'s own time - the next line lit between two reports', lit(), [4])
    run(10)
    report(60)
    view.render(props())
    check('...but a seek on its way: its target, until it lands', lit(), [5])
    frame()
    view.render(props())
    check('...a frame later too - nothing flickers back', lit(), [5])

    reduced = true
    run(16)
    run(25)
    check('Reduce Motion: following jumps', lastScroll(), { top: PAD_PX + 4 * LINE_PX - 60, behavior: 'auto' })
    reduced = false
    run(10)

    //? the listener's own scroll holds it
    box.dispatch('wheel')
    const held = scrolls()
    run(25)
    check('a wheel holds it: the next line lit, not followed', [lit(), scrolls()], [[4], held])
    wait(3999)
    check('...3,999 ms on, still held', scrolls(), held)
    wait(1)
    check('...4,000 ms after it, following again - smoothly, to the lit line', [scrolls(), lastScroll()], [held + 1, { top: PAD_PX + 4 * LINE_PX - 60, behavior: 'smooth' }])

    box.dispatch('touchmove')
    state.playing = false
    view.render(props())
    const paused = scrolls()
    wait(10_000)
    check('paused, held past 4 s: it stays where the listener put it', scrolls(), paused)
    state.playing = true
    view.render(props())
    check('...and the song playing again brings it back at once', scrolls(), paused + 1)

    box.dispatch('keydown', { key: 'PageDown' })
    const keyed = scrolls()
    run(30)
    check('a scroll key holds it as a wheel does', scrolls(), keyed)
    wait(4000)
    check('...and following comes back after it', scrolls(), keyed + 1)

    //? keyboard focus in the lines holds it, for as long as it is there
    run(10)
    box.dispatch('keydown', { key: 'Tab' })
    //? (review) focused as a browser focuses it - the page's focus on it, then its focusin
    lines()[1].element.focus()
    lines()[1].element.dispatch('focusin')
    const focusedAt = scrolls()
    run(25)
    wait(30_000)
    check('keyboard focus on a line holds it, however long it stays', [lit(), scrolls()], [[4], focusedAt])
    check('...and the tab stop stays on the line focus is on', lines().map((node) => node.props.tabIndex), [-1, 0, -1, -1])
    lines()[1].element.dispatch('focusout', { relatedTarget: document.body })
    view.render(props())
    check('focus leaving: held FOLLOW_AGAIN_MS more, then following', [scrolls(), (wait(4000), scrolls())], [focusedAt, focusedAt + 1])
    check('...and the tab stop back on the lit line', lines().map((node) => node.props.tabIndex), [-1, -1, 0, -1])

    //? a tap or a click puts focus on a line too (Chromium) - which never holds it
    lines()[0].element.dispatch('pointerdown')
    lines()[0].element.dispatch('focusin')
    const clicked = scrolls()
    run(30)
    check('focus a click put on a line doesn\'t hold it', scrolls(), clicked + 1)
    box.dispatch('pointerdown', { target: box })
    const bar = scrolls()
    run(10)
    check('...but a press on the scroller itself - its scroll bar - does', scrolls(), bar)
    wait(4000)

    //? a tap on a line: from there, playing
    state.playing = false
    view.render(props())
    const before = scrolls()
    lines()[1].props.onClick()
    view.render(props())
    check('a tap on a line, paused: a seek to it and play, in the tap - lit at once, followed', [seeks, toggles, lit(), scrolls()], [[10], 1, [2], before + 1])
    state.playing = true
    view.render(props())
    lines()[3].props.onClick()
    view.render(props())
    check('...playing: the seek alone', [seeks, toggles, lit()], [[10, 30], 1, [5]])
    const again = scrolls()
    lines()[3].props.onClick()
    view.render(props())
    check('...the line already lit: followed all the same, once', [seeks, scrolls()], [[10, 30, 30], again + 1])
    box.dispatch('wheel')
    lines()[2].props.onClick()
    view.render(props())
    check('...and a tap while held follows again at once', lastScroll(), { top: PAD_PX + 4 * LINE_PX - 60, behavior: 'smooth' })
    seeks.length = 0

    //? the arrows
    let prevented = false
    lines()[1].props.onKeyDown({ key: 'ArrowDown', preventDefault() { prevented = true } })
    check('Down from a line: focus to the next line sung, past the break', [prevented, document.activeElement === lines()[2].element], [true, true])
    lines()[1].props.onKeyDown({ key: 'End', preventDefault() {} })
    check('End: the last line', document.activeElement === lines()[3].element, true)

    //? a seek reported while paused lights its line
    state.playing = false
    view.render(props())
    report(5)
    view.render(props())
    check('paused, a seek reported lights its line - no clock running', [lit(), frames.length], [[1], 0])

    //? a new song starts at its top
    state.playing = true
    box.scrollTop = 300
    answers.song = 'song-2'
    answers.lyrics = { synced: true, lines: [at(1, 'A second song begins'), at(6, 'And carries on')] }
    state.position = 0
    view.render(props())
    check('a new song: its lines from their top, nothing lit yet', [box.scrollTop, lit(), lines().length], [0, [], 2])
  }

  console.log('\nthe view: waiting, failing, none, plain, nothing playing')
  {
    const player = { track: { id: 'song-3' }, playing: false, position: () => 0, onPosition: () => () => {}, seek() {}, toggle() {} }
    const view = mount(Lyrics)
    let retries = 0
    const draw = (answers, track = player.track) =>
      view.render({ player: { ...player, track }, answers: { song: 'song-3', lyrics: null, asking: false, error: null, retry: () => { retries += 1 }, ...answers }, shows: true, covered: false, place: 'panel' })
    draw({ asking: true })
    check('asking: the spinner, named, centred', [view.one(byClass('pl-spinner')).props['aria-label'], view.one(byClass('app-lyrics')).props.class], ['Loading lyrics', 'app-lyrics is-panel is-waiting'])
    draw({ error: new ApiError(500, 'boom', 'GET /navidrome/lyrics/song-3 failed', false, null, null, '/navidrome/lyrics/song-3') })
    const failed = view.one(byClass('app-lyrics-error'))
    check('a failure: in the lyrics\' words, and Try again', [text(failed).startsWith("Couldn't load the lyrics."), text(view.one(byClass('app-button')))], [true, 'Try again'])
    view.one(byClass('app-button')).props.onClick()
    check('...which asks again', retries, 1)
    draw({ error: new ApiError(500, 'boom', 'x', false, null, null, '/navidrome/lyrics/song-3'), asking: true })
    check('...asking again: the spinner, not the failure', [!!view.one(byClass('pl-spinner')), view.find(byClass('app-lyrics-error')).length], [true, 0])
    draw({ error: new ApiError(404, 'Not found', 'x', false, null, null, '/navidrome/lyrics/song-3') })
    check('a gone: said so, and no Try again - there is nothing to try', [text(view.one(byClass('app-lyrics-error'))).startsWith("This song isn't here any more"), view.find(byClass('app-button')).length], [true, 0])
    draw({ lyrics: { synced: false, lines: [] } })
    check('none: said so where a place must say something', text(view.one(byClass('app-lyrics-none'))), 'No lyrics for this song.')
    draw({ lyrics: { synced: false, lines: [at(null, 'Plain words, the first'), at(null, ''), at(null, 'Plain words, the second')] } })
    check('plain: the note above, every line lit, no buttons - the section itself a tab stop, so a keyboard can scroll it',
      [text(view.one(byClass('app-lyrics-note'))), view.find(byClass('is-plain')).length, view.find((node) => node.type === 'button').length, view.one(byClass('app-lyrics')).props.tabIndex,
        view.one(byClass('app-lyrics')).props.class],
      ["These lyrics aren't synced to the song.", 2, 0, 0, 'app-lyrics is-panel'])
    draw({ lyrics: { synced: true, lines: SONG } }, null)
    check('nothing playing: said so, as the bar does', text(view.one(byClass('app-lyrics-none'))), 'Nothing playing')
    check('...and synced lyrics\' section no tab stop of its own - its lines are', (draw({ lyrics: { synced: true, lines: SONG } }), view.one(byClass('app-lyrics')).props.tabIndex), undefined)
  }

  console.log('\nthe view, after review: plain lyrics never followed; a press over; focus that has gone')
  {
    const reported = new Set()
    const state = { position: 0, playing: true }
    const player = {
      track: { id: 'song-r' },
      position: () => state.position,
      onPosition: (fn) => { reported.add(fn); return () => reported.delete(fn) },
      seek() {},
      toggle() {},
    }
    const answers = { song: 'song-r', lyrics: { synced: false, lines: [at(null, 'Plain words, the first'), at(null, 'Plain words, the second')] }, asking: false, error: null, retry() {} }
    const view = mount(Lyrics)
    const props = () => ({ player: { ...player, playing: state.playing }, answers, shows: true, covered: false, place: 'face' })
    view.render(props())
    const box = view.one(byClass('app-lyrics')).element
    box.clientHeight = 200
    const resized = () => { for (const observer of observers) if (observer.box === box && !observer.gone) observer.fn() }
    resized()
    view.render(props())
    const scrolls = () => box.scrolls.length
    const lines = () => view.find((node) => node.type === 'button' && byClass('app-lyric')(node))
    const report = (seconds) => { for (const fn of reported) fn(seconds) }
    const run = (seconds) => { state.position = seconds; report(seconds - 0.25); frame(); view.render(props()) }

    //? plain lyrics: scrolled down to read, then the wait run out, a pause and a play, a change of size
    const plain = scrolls()
    box.scrollTop = 300
    box.dispatch('wheel')
    wait(4000)
    state.playing = false
    view.render(props())
    state.playing = true
    view.render(props())
    resized()
    view.render(props())
    check('plain lyrics stay where the listener scrolled them: never "followed" back to their top - not after the wait, a play, or a change of size',
      [scrolls(), box.scrollTop], [plain, 300])

    //? synced lyrics from here
    const LINES = [at(1, 'A first line'), at(6, 'A second line'), at(11, 'A third line'), at(16, 'A fourth line')]
    answers.song = 'song-s'
    answers.lyrics = { synced: true, lines: LINES }
    state.position = 0
    view.render(props())
    run(1)

    //? a finger resting on the scroller's own padding - its sides, the top fade - is no scroll bar
    box.dispatch('pointerdown', { target: box, pointerType: 'touch' })
    box.dispatch('pointercancel', { target: box, pointerType: 'touch' })
    const thumb = scrolls()
    run(6)
    check('a finger on the scroller\'s own padding holds nothing: the next line followed', scrolls(), thumb + 1)

    //? a press on the scroller (its scroll bar) and its click: the press is over - Safari focused nothing
    box.dispatch('pointerdown', { target: box, pointerType: 'mouse' })
    box.dispatch('click', { target: box })
    wait(4000)
    lines()[1].element.focus()
    lines()[1].element.dispatch('focusin')
    const tabbed = scrolls()
    run(6)
    run(11)
    check('a press over - its click come - then a Tab into the lines from outside: held, as keyboard focus holds', scrolls(), tabbed)

    //? ...then a click on another line, its focus there
    lines()[3].element.dispatch('pointerdown')
    lines()[3].element.focus()
    lines()[3].element.dispatch('focusin')
    lines()[3].element.dispatch('click')
    const clicked = scrolls()
    run(16)
    check('...then a click on a line: the keyboard\'s hold let go - following again', scrolls(), clicked + 1)

    //? keyboard focus on a line, and the next song's lines not in hand: the spinner where they were. The line focus was
    //? on goes with them, which leaves the page's focus on its body with no focusout (Safari's own) - modelled here
    box.dispatch('keydown', { key: 'Tab' })
    lines()[0].element.focus()
    lines()[0].element.dispatch('focusin')
    answers.song = 'song-t'
    answers.lyrics = null
    answers.asking = true
    state.position = 0
    view.render(props())
    document.activeElement = document.body
    answers.lyrics = { synced: true, lines: LINES }
    answers.asking = false
    view.render(props())
    const gone = scrolls()
    run(6)
    check('keyboard focus on a line taken away with the last song\'s lines holds nothing: the next song is followed', scrolls(), gone + 1)
    check('...and its tab stop is the lit line, not where focus was', lines().map((node) => node.props.tabIndex), [-1, 0, -1, -1])
  }

  console.log('\nthe answers (2.6): asked at every song change, the newest alone drawn')
  {
    api.asks.length = 0
    const listeners = new Set()
    const onPosition = (fn) => { listeners.add(fn); return () => listeners.delete(fn) }
    const song = (id) => ({ id })
    const view = mount((props) => useLyrics(props.player, props.showing, props.shown))
    let queue = { tracks: [song('a'), song('b'), song('c'), song('d')], index: 0 }
    const draw = (track, { showing = false, shown = true, duration = 200 } = {}) =>
      view.render({ player: { track, queue, duration, onPosition }, showing, shown })
    const last = () => view.render()
    const asked = () => api.asks.map((ask) => ask.id)
    const answer = async (index, lines) => { api.asks[index].resolve({ synced: true, lines }); await settle() }

    let got = draw(song('a'))
    check('a song: asked at once, Now Playing open or not - asking', [asked(), got.song, got.lyrics, got.asking], [['a'], 'a', null, true])
    got = draw(song('b'))
    check('the next song before it answered: asked, the first ask called off', [asked(), api.asks[0].signal.aborted], [['a', 'b'], true])
    await answer(0, [at(1, 'The first song\'s words')])
    got = last()
    check('the first song\'s answer, late: never drawn under the second', [got.song, got.lyrics, got.asking], ['b', null, true])
    await answer(1, [at(1, 'The second song\'s words')])
    got = last()
    check('the second\'s: drawn', [got.song, got.lyrics.lines[0].text, got.asking], ['b', "The second song's words", false])
    got = draw(song('a'))
    check('back to a song kept: drawn at once while it is asked again', [got.lyrics?.lines[0].text, got.asking, asked().length], ["The first song's words", true, 3])
    await answer(2, [at(1, 'The first song\'s words')])

    got = draw(song('c'), { shown: false })
    check('the page hidden: nothing asked, nothing kept to draw', [asked().length, got.song, got.lyrics, got.asking], [3, 'c', null, false])
    got = draw(song('c'), { shown: true })
    check('...shown again: asked', [asked().slice(3), got.asking], [['c'], true])
    api.asks[3].reject(new ApiError(500, 'boom', 'x'))
    await settle()
    got = last()
    check('a failure: kept, nothing drawn, not asking', [got.lyrics, got.asking, got.error?.status], [null, false, 500])
    got = draw(song('c'), { showing: true })
    check('...the lyrics opened again: asked again', [asked().slice(4), got.asking], [['c'], true])
    await answer(4, [at(1, 'The third song\'s words')])
    got.retry()
    check('Try again asks again', asked().slice(5), ['c'])
    await answer(5, [at(1, 'The third song\'s words')])
    got = last()
    got.retry()
    got.retry()
    await answer(7, [at(1, 'The newer words')])
    await answer(6, [at(1, 'The older words')])
    got = last()
    check('two asks for one song: the newer answer drawn, the older never over it, however late', [asked().length, got.lyrics.lines[0].text], [8, 'The newer words'])

    queue = { tracks: [song('c'), song('d')], index: 0 }
    draw(song('c'), { showing: true })
    for (const fn of listeners) fn(150)
    check('the next song: not asked with more than 20 s left', asked().length, 8)
    for (const fn of listeners) fn(181)
    for (const fn of listeners) fn(182)
    check('...asked once, with 20 s left, while the lyrics show', asked().slice(8), ['d'])
    await answer(8, [at(1, 'The fourth song\'s words')])
    got = draw(song('d'), { showing: true })
    check('...and in hand at the join', [got.lyrics?.lines[0].text], ["The fourth song's words"])
    draw(song('d'), { showing: false })
    check('...never while they don\'t show', listeners.size, 0)
    got = draw(null)
    check('nothing playing: nothing', [got.song, got.lyrics, got.asking, got.error], [null, null, false, null])
  }

  console.log('\nNow Playing\'s Lyrics: on and off in place, dimmed off for a song with none')
  {
    const player = {
      track: { id: 'song-1', title: 'An invented song', artist: 'Nobody', album: 'Invented', albumId: 'al-1', coverArt: 'cv', duration: 200 },
      playing: true, buffering: false, duration: 200, error: null, airplay: false, shuffle: false, repeat: 'off', queue: { tracks: [], index: 0 },
      toggle() {}, previous() {}, next() {}, showAirPlay() {}, seek() {}, setShuffle() {}, setRepeat() {}, position: () => 0, onPosition: () => () => {},
    }
    const view = mount(NowPlaying)
    const turned = []
    const answers = (lyrics) => ({ song: 'song-1', lyrics, asking: false, error: null, retry() {} })
    const draw = (lyricsOn, lyrics, openAs = 'cover') => view.render({
      player, open: true, covered: false, opener: { current: null }, onClose() {}, onMore() {}, onAlbum() {}, openAs, pinnable: false,
      onUpNext() {}, lyrics: answers(lyrics), lyricsOn, onLyrics: (on) => turned.push(on),
    })
    const button = () => view.one(byClass('app-np-lyrics'))
    const shown = () => view.find((node) => node.type === Lyrics).map((node) => [node.props.place, node.props.shows])
    const cover = () => view.find(byClass('pl-sheet-art')).length
    const SOME = { synced: true, lines: SONG }
    const NONE = { synced: false, lines: [] }

    draw(false, null)
    check('off, not known yet: enabled, "Lyrics", not pressed - the cover', [button().props['aria-label'], button().props['aria-pressed'], button().props['aria-disabled'], cover(), shown()],
      ['Lyrics', false, false, 1, []])
    button().props.onClick()
    check('...a tap turns them on', turned, [true])
    draw(true, SOME)
    check('on: pressed, in the accent - the lyrics in the cover\'s place, the grip its top row alone',
      [button().props['aria-pressed'], byClass('is-on')(button()), cover(), shown(), byClass('app-grip-top')(view.one(byClass('pl-sheet-grip')))],
      [true, true, 0, [['face', true]], true])
    draw(true, null)
    check('on, asking: the view, for its spinner', shown(), [['face', true]])
    draw(true, NONE)
    check('on, a song with none: the cover, "Lyrics - none for this song", still pressed and enabled',
      [cover(), shown(), button().props['aria-label'], button().props['aria-pressed'], button().props['aria-disabled']], [1, [], 'Lyrics - none for this song', true, false])
    button().props.onClick()
    check('...a tap turns them off', turned, [true, false])
    draw(false, NONE)
    check('off, a song with none: dimmed, and its tap nothing', [button().props['aria-disabled'], (button().props.onClick(), turned.length)], [true, 2])

    globalThis.__wakes = 0
    view.render({ ...view.props, open: false })
    draw(true, SOME, 'turntable')
    check('over the turntable: the lyrics, and no record mounted beneath them',
      [shown(), view.find((node) => typeof node.type === 'function' && node.type.name === 'Turntable').length], [[['face', true]], 0])
    button().props.onClick()
    check('...off: back to the record - a gesture its sound starts from', [turned.slice(-1), globalThis.__wakes], [[false], 1])
    view.one(byClass('app-look-button')).props.onClick()
    check('the look button with lyrics on: they give way to the look asked for', turned.slice(-1), [false])
    const order = view.one(byClass('pl-sheet-footer')).props.children.flat(Infinity).filter((node) => node && node.type === 'button').map((node) => node.props.class.split(' ')[1] ?? node.props.class)
    check('the icon row: Lyrics before Up Next, ••• last', order.slice(0, 2), ['app-np-lyrics', 'app-upnext-button'])
  }

  console.log('\nthe desktop bar\'s Lyrics: the panel, dimmed only while it is closed')
  {
    const player = {
      track: { id: 'song-1', title: 'An invented song', artist: 'Nobody', album: 'Invented', coverArt: 'cv' },
      playing: true, error: null, shuffle: false, repeat: 'off', queue: { tracks: [], index: 0 }, airplay: false,
      toggle() {}, previous() {}, next() {}, setShuffle() {}, setRepeat() {}, position: () => 0, onPosition: () => () => {},
    }
    const view = mount(PlayerBar)
    let clicks = 0
    const draw = (lyricsOpen, lyrics) => view.render({
      player, onAlbum: null, onInfo() {}, infoOpen: false, onVisualizer() {}, onUpNext() {}, upNextOpen: false, onAddToPlaylist() {},
      onLyrics: () => { clicks += 1 }, lyricsOpen, lyrics,
    })
    const button = () => view.one(byClass('app-playbar-lyrics'))
    draw(false, 'unknown')
    check('closed: "Lyrics", enabled, not expanded', [button().props['aria-label'], button().props['aria-disabled'], button().props['aria-expanded']], ['Lyrics', false, false])
    button().props.onClick({})
    check('...its click opens the panel', clicks, 1)
    draw(false, 'none')
    check('closed, a song with none: dimmed, named so - its click nothing', [button().props['aria-label'], button().props['aria-disabled'], (button().props.onClick({}), clicks)],
      ['Lyrics - none for this song', true, 1])
    draw(true, 'none')
    check('open, a song with none: lit, enabled - its click closes it', [byClass('is-on')(button()), button().props['aria-expanded'], button().props['aria-disabled'], (button().props.onClick({}), clicks)],
      [true, true, false, 2])
    const tools = view.find((node) => node.type === 'button' && node.props.class?.startsWith('app-playbar-button')).map((node) => node.props['aria-label'])
    check('Lyrics before Up Next', tools.slice(tools.indexOf('Lyrics - none for this song'), tools.indexOf('Up Next') + 1), ['Lyrics - none for this song', 'Up Next'])
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
