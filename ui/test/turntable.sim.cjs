/**
 * Now Playing as a turntable (2.0.0-player.11): the pure rules (lib/turntable.ts), the turntable
 * itself (player/Turntable.tsx) and the look button on Now Playing (player/NowPlaying.tsx), compiled
 * with the repo's TypeScript and rendered by a small stand-in for Preact into plain objects - the
 * same stand-in as info.sim.cjs.
 *
 * What it pins:
 *
 *  - The arm: the needle in the outer groove at the start of the song and the inner one at its end,
 *    moving in as the song plays; dragged, the angle says the time (the same time back), and past
 *    either end of the grooves the song's start or end - never the circle's far side. Nudged under
 *    TAP_SLOP_PX it shows nothing it won't go to (it stays over the song); past it, it is taken
 *    hold of where the song is then, so it doesn't jump - to the finger or away from the song.
 *  - Turning the record: SECONDS_PER_TURN (1.8 s, 33 1/3 rpm) a whole turn, backwards too, the
 *    short way across the seam where the angle wraps, clamped to the song, and nothing counted at
 *    the spindle - an OFFSET from wherever the song has got to, since it plays on under the finger:
 *    held a moment, or turned slowly, a forward turn never lands behind the song. Another finger
 *    changes nothing - in the lib, and in the component, where a second finger starts nothing.
 *  - Letting go seeks to exactly what the arm and the time line show.
 *  - A tap is a press that never travels TAP_SLOP_PX: it seeks nowhere, and its click plays or
 *    pauses, IN the click. A drag seeks where it lets go - only there - and the click after it is
 *    not a tap, however it ends (a mouse's click after a turn the song changed under included). A
 *    cancel seeks nowhere; a drag begun on a song that has since changed is dropped. Both drags
 *    capture the pointer; the preview goes with the turntable when it unmounts.
 *  - The time line: "2:31 of 7:05", and what the drag says while there is one.
 *  - The speed fader (2.0.0-player.39): drawn on the stage when Now Playing hands the turntable its player
 *    (after the record, before the arm's handle), none for a player with no speed (the test bench's);
 *    the deck told the speed as the turntable mounts and as it changes, and no longer once it has gone;
 *    the speed's chip first in Now Playing's icon row, outside the grip.
 *  - The record turns - the deck's frame loop (player/deck.ts, 2.0.0-player.14), a turn in
 *    SECONDS_PER_TURN - while the song plays and Now Playing is open and the page is showing, and
 *    spins down when it pauses; never while closed or hidden; Turntable itself has no frame loop.
 *  - With the deck's sound running (an audio context made in a tap): a press is taken past a tap or
 *    after resting longer than one, pausing the song through the player's own toggle; letting go
 *    seeks where the motor will have the platter back at speed - or where a paused one stops - and
 *    the song plays at speed after the coast; a cancel plays on what it paused; a tap still plays or
 *    pauses, and a pause from it winds down, the song sought where that stops (and, with "Pause winds
 *    the record down" off, the same tap on a platter at speed doesn't - the control beside it); a play
 *    mid wind-down starts from where the record is; the arm stops the record's sound, and while held it
 *    and the time line follow the finger, not the coast; a hi-res song's window is asked at the cap the
 *    song plays at. Until the sound runs, every press is exactly 2.0.0-player.11's - the checks above
 *    it are those, the record stopped under a resting finger included.
 *  - The record's face: the playing song's disc's CD art, from the library route, the plain record
 *    with the cover as its label when that fails or there is no album - asked for again each time
 *    Now Playing opens, a turntable left mounted across the close included.
 *  - The arm is a slider to the keyboard, stepping as the scrubber does; the record is named for
 *    what a tap does; the look button for the look it switches to.
 *  - Now Playing opens in the setting's look every time, the button switches it for as long as it
 *    stays open, and the turntable is outside the sheet's grip.
 *
 * Run it with:  node ui/test/turntable.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const REPO = path.resolve(UI, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-turntable-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/turntable.ts', 'src/player/Turntable.tsx', 'src/player/NowPlaying.tsx',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor, as Preact's are - the same stand-in as the other
//? component sims. Effects (layout ones too) run after a render whose deps changed.
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
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
  return render
}
`)
//? covers and glyphs stand in; the engine's position hook reads the player's position
fs.writeFileSync(path.join(OUT, 'player/Cover.js'), 'exports.Cover = function Cover() { return null }\n')
fs.writeFileSync(path.join(OUT, 'player/icons.js'), `
const glyph = (name) => { const f = function () { return null }; Object.defineProperty(f, 'name', { value: name }); return f }
for (const name of ['ChevronRightIcon', 'ChevronDownIcon', 'AirPlayIcon', 'MoreIcon', 'NextIcon', 'PauseIcon', 'PlayIcon', 'PreviousIcon', 'CheckIcon', 'RecordIcon', 'SquareIcon']) exports[name] = glyph(name)
`)
fs.writeFileSync(path.join(OUT, 'player/usePlayer.js'), 'exports.usePosition = (player) => player.position()\n')

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
const near = (a, b, within = 1e-6) => Math.abs(a - b) <= within

/* ===== a document that knows what has focus, what listens, and whether the page is showing ===== */

//? the stage's box on screen: its own units, 1:1, so a point of the drawing is a point on screen
const BOX = { left: 0, top: 0, width: 372, height: 368 }
class FakeElement {
  constructor(name) {
    this.name = name
    this.style = {}
    this.classes = new Set()
    this.classList = { toggle: (c, on) => (on ? this.classes.add(c) : this.classes.delete(c)) }
  }
  focus() { document.activeElement = this }
  querySelector() { return null }
  getBoundingClientRect() { return { ...BOX, right: BOX.left + BOX.width, bottom: BOX.top + BOX.height } }
}
const listeners = new Map()
const document = {
  body: new FakeElement('body'),
  documentElement: new FakeElement('html'),
  activeElement: null,
  visibilityState: 'visible',
  addEventListener: (name, fn) => listeners.set(name, [...(listeners.get(name) ?? []), fn]),
  removeEventListener: (name, fn) => listeners.set(name, (listeners.get(name) ?? []).filter((f) => f !== fn)),
}
document.activeElement = document.body
const define = (name, value) => Object.defineProperty(globalThis, name, { value, configurable: true, writable: true })
define('document', document)
define('HTMLElement', FakeElement)
define('localStorage', { getItem: () => null, setItem: () => {}, removeItem: () => {} })
const fire = (name) => { for (const fn of [...(listeners.get(name) ?? [])]) fn({}) }

//? a clock, timers and frames the checks move on themselves - the deck's (player/deck.ts)
let clock = 1000
let timers = []
let frames = []
let nextId = 1
function advance(ms) {
  const until = clock + ms
  for (;;) {
    timers.sort((a, b) => a.at - b.at)
    const due = timers.find((timer) => timer.at <= until)
    if (!due) break
    clock = due.at
    timers = timers.filter((timer) => timer !== due)
    due.run()
  }
  clock = until
}
function runFrames(count) {
  for (let i = 0; i < count; i++) {
    advance(16)
    const now = frames
    frames = []
    for (const frame of now) frame.run(clock)
  }
}
define('performance', { now: () => clock })
define('setTimeout', (run, ms = 0) => { const id = nextId++; timers.push({ id, at: clock + ms, run }); return id })
define('clearTimeout', (id) => { timers = timers.filter((timer) => timer.id !== id) })
define('requestAnimationFrame', (run) => { const id = nextId++; frames.push({ id, run }); return id })
define('cancelAnimationFrame', (id) => { frames = frames.filter((frame) => frame.id !== id) })

/* ===== rendering ===== */

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))

function mount(component, name) {
  const render = hooks.root(component)
  const elements = new Map()
  let tree = null
  const walk = (node, where) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach((child, i) => walk(child, `${where}.${i}`)); return }
    if (typeof node.type === 'string') {
      const key = `${where}:${node.type}`
      if (!elements.has(key)) elements.set(key, new FakeElement(`${name} ${node.type} ${node.props.class ?? ''}`.trim()))
      node.element = elements.get(key)
      if (node.props.ref) node.props.ref.current = node.element
    }
    walk(node.props?.children, `${where}/`)
  }
  const find = (test, from = tree) => {
    const hits = []
    const visit = (node) => {
      if (!node || typeof node !== 'object') return
      if (Array.isArray(node)) { node.forEach(visit); return }
      if (test(node)) hits.push(node)
      visit(node.props?.children)
    }
    visit(from)
    return hits
  }
  return {
    render(props) {
      tree = render(props)
      walk(tree, '')
      render.commit()
      return tree
    },
    unmount: () => render.unmount(),
    find,
  }
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const named = (name) => (node) => typeof node.type === 'function' && node.type.name === name
const hasClass = (node, name) => byClass(name)(node)

/* ===== the rules ===== */

const tt = require(path.join(OUT, 'lib/turntable.js'))
const { SECONDS_PER_TURN, TAP_SLOP_PX, RECORD, ARM, GROOVES } = tt
const LENGTH = 425 // Time, on The Dark Side of the Moon: 7:05

//? a point on the record at an angle (degrees, clockwise from the right) and a distance from its centre
const onRecord = (degrees, r = 100) => ({ x: RECORD.x + r * Math.cos(degrees / 180 * Math.PI), y: RECORD.y + r * Math.sin(degrees / 180 * Math.PI) })
//? where the arm's reach lands at an angle from its pivot
const reachAt = (degrees) => ({ x: ARM.x + ARM.reach * Math.cos(degrees / 180 * Math.PI), y: ARM.y + ARM.reach * Math.sin(degrees / 180 * Math.PI) })
const fromCentre = (point) => Math.hypot(point.x - RECORD.x, point.y - RECORD.y)
//? a point turned round the arm's pivot by an arc of `units` (the stage's units are the BOX's px)
const aboutPivot = (point, units) => {
  const r = Math.hypot(point.x - ARM.x, point.y - ARM.y), a = Math.atan2(point.y - ARM.y, point.x - ARM.x) + units / r
  return { x: ARM.x + r * Math.cos(a), y: ARM.y + r * Math.sin(a) }
}

console.log('\nthe arm follows the song from the outer groove in')
{
  check('the needle in the outer groove at the start, the inner at the end, halfway between halfway',
    [near(fromCentre(tt.needleAt(0, LENGTH)), GROOVES.outer), near(fromCentre(tt.needleAt(LENGTH, LENGTH)), GROOVES.inner),
      near(fromCentre(tt.needleAt(LENGTH / 2, LENGTH)), (GROOVES.outer + GROOVES.inner) / 2)], [true, true, true])
  check('...every needle point at the arm\'s reach from its pivot',
    [0, 100, 212.5, 425].every((t) => near(Math.hypot(tt.needleAt(t, LENGTH).x - ARM.x, tt.needleAt(t, LENGTH).y - ARM.y), ARM.reach)), true)
  const angles = [0, 60, 151, 300, 425].map((t) => tt.armAngle(t, LENGTH))
  check('it swings one way the whole song through', angles.every((a, i) => i === 0 || a > angles[i - 1]), true)
  check('...from about 99 to about 122.5 degrees, as the board draws it', [Math.round(angles[0] * 10) / 10, Math.round(angles[4] * 10) / 10], [98.9, 122.5])
  check('past the end it stays at the end; a song with no length sits in the outer groove',
    [near(tt.armAngle(500, LENGTH), angles[4]), near(tt.armAngle(-5, LENGTH), angles[0]), near(tt.armAngle(30, 0), angles[0])], [true, true, true])
}

console.log('\nthe arm, dragged, says the time')
{
  check('an angle gives back the time it was drawn at',
    [0, 10, 151, 212.5, 400, 425].map((t) => near(tt.armTimeAt(tt.armAngle(t, LENGTH), LENGTH), t, 1e-6)), [true, true, true, true, true, true])
  const outer = tt.armAngle(0, LENGTH), inner = tt.armAngle(LENGTH, LENGTH)
  check('past the outer groove: the start; past the inner: the end',
    [tt.armTimeAt(outer - 30, LENGTH), tt.armTimeAt(inner + 20, LENGTH), tt.armTimeAt(inner + 60, LENGTH)], [0, LENGTH, LENGTH])
  //? where the reach meets the grooves a second time, past its nearest approach to the spindle
  const farSide = inner + 90
  check('never the far side of the circle, where the reach meets the grooves again', [0, LENGTH].includes(tt.armTimeAt(farSide, LENGTH)), true)
  check('...whichever way round an angle is written', near(tt.armTimeAt(tt.armAngle(151, LENGTH) - 360, LENGTH), 151, 1e-6), true)
  check('a song with no length has no time to go to', tt.armTimeAt(110, 0), 0)

  const needle = tt.needleAt(151, LENGTH)
  //? taken hold of a little off the needle, as a finger does
  const grab = { x: needle.x + 9, y: needle.y - 6 }
  let arm = tt.armStart(1, 'song', grab.x, grab.y)
  check('taken hold of off the needle: an arm drag, the needle up over the song', [arm.kind, tt.preview(arm)], ['arm', { how: 'arm', time: null }])
  check('...which plays on under it: the arm shows the song wherever it has got to',
    [tt.shownTime(tt.preview(arm), 151, LENGTH), tt.shownTime(tt.preview(arm), 154, LENGTH)], [151, 154])
  arm = tt.armMove(arm, 1, grab.x, grab.y, BOX, LENGTH, 151)
  check('...a move to where it was taken changes nothing, nor is it a drag yet', [tt.moved(arm), arm.time], [false, null])

  //? on a phone the whole song is about 83px of needle, so 8px is 40 seconds: a nudge under the
  //? slop must show nothing it won't go to
  let nudged = arm
  for (const units of [2, 5, TAP_SLOP_PX - 0.5]) {
    const at = aboutPivot(grab, units)
    nudged = tt.armMove(nudged, 1, at.x, at.y, BOX, LENGTH, 151)
  }
  check(`nudged ${TAP_SLOP_PX - 0.5} px along its arc: nothing moves - the arm stays over the song`,
    [tt.moved(nudged), nudged.time, tt.shownTime(tt.preview(nudged), 151, LENGTH)], [false, null, 151])
  check('...and letting go goes nowhere, which is what it showed', tt.dragEnd(nudged, 1, 'up', 151, LENGTH), { drag: null, seek: null, wasDrag: false })
  check('...the same backwards', tt.moved(tt.armMove(arm, 1, aboutPivot(grab, 0.5 - TAP_SLOP_PX).x, aboutPivot(grab, 0.5 - TAP_SLOP_PX).y, BOX, LENGTH, 151)), false)

  //? past the slop, three seconds of song later: taken hold of where the song is then
  const past = aboutPivot(grab, TAP_SLOP_PX + 0.5)
  let moving = tt.armMove(nudged, 1, past.x, past.y, BOX, LENGTH, 154)
  check('just past it (the song at 2:34 by then): it moves on from where the song is - no jump either way',
    [tt.moved(moving), moving.time > 154, moving.time < 157], [true, true, true])
  const further = aboutPivot(grab, TAP_SLOP_PX + 10.5)
  const before = moving.time
  moving = tt.armMove(moving, 1, further.x, further.y, BOX, LENGTH, 155)
  check('...and on with the finger, keeping its grab: in towards the middle is later', moving.time > before + 30, true)
  check('let go, whatever the song is doing: it seeks exactly what the arm and the time line show',
    [tt.dragEnd(moving, 1, 'up', 999, LENGTH).seek === moving.time, tt.shownTime(tt.preview(moving), 999, LENGTH) === moving.time], [true, true])

  //? a quick finger's first move can be tens of px: the arm still starts from the song, and moves by
  //? the rest of the way
  const quick = aboutPivot(grab, 40)
  const flung = tt.armMove(tt.armStart(1, 'song', grab.x, grab.y), 1, quick.x, quick.y, BOX, LENGTH, 151)
  const slow = [2, 5, 7.5, 8.5, 20, 30, 40].reduce((d, units) => tt.armMove(d, 1, aboutPivot(grab, units).x, aboutPivot(grab, units).y, BOX, LENGTH, 151), tt.armStart(1, 'song', grab.x, grab.y))
  check('a quick first move of 40 px: the arm moved by the 32 past the slop, as a slow one does', near(flung.time, slow.time, 1.5), true)

  const toEnd = reachAt(inner + 10)
  arm = tt.armMove(moving, 1, toEnd.x, toEnd.y, BOX, LENGTH, 155)
  check('dragged in past the inner groove: the end of the song', [tt.moved(arm), arm.time], [true, LENGTH])
  check('another finger moves nothing', tt.armMove(arm, 2, 0, 0, BOX, LENGTH, 155) === arm, true)
  check('let go: it seeks there, once, and it was a drag', tt.dragEnd(arm, 1, 'up', 155, LENGTH), { drag: null, seek: LENGTH, wasDrag: true })
  check('cancelled: it seeks nowhere', tt.dragEnd(arm, 1, 'cancel', 155, LENGTH).seek, null)
  const still = tt.armStart(1, 'song', needle.x, needle.y)
  check('pressed and let go without moving: nowhere', tt.dragEnd(still, 1, 'up', 151, LENGTH), { drag: null, seek: null, wasDrag: false })
  check('another finger letting go ends nothing', tt.dragEnd(still, 2, 'up', 151, LENGTH).drag === still, true)
}

console.log('\nturning the record: 1.8 s a turn')
{
  check('33 1/3 rpm', [SECONDS_PER_TURN, near(60 / SECONDS_PER_TURN, 100 / 3, 1e-9)], [1.8, true])
  //? what a drag shows, with the song at `position`
  const showing = (drag, position) => tt.shownTime(tt.preview(drag), position, LENGTH)
  const turn = (drag, degrees, position, r) => tt.recordMove(drag, 1, onRecord(degrees, r).x, onRecord(degrees, r).y, BOX, LENGTH, position)
  let spin = tt.recordStart(1, 'song', onRecord(0).x, onRecord(0).y, BOX)
  for (let degrees = 30; degrees <= 360; degrees += 30) spin = turn(spin, degrees, 100)
  check('a whole turn clockwise: 1.8 s on, and the record turned a whole turn', [near(spin.offset, 1.8), near(showing(spin, 100), 101.8), near(spin.turned, 2 * Math.PI)], [true, true, true])
  for (let degrees = 330; degrees >= 180; degrees -= 30) spin = turn(spin, degrees, 100)
  check('half a turn back: 0.9 s back', near(showing(spin, 100), 100.9), true)

  let seam = tt.recordStart(1, 'song', onRecord(170).x, onRecord(170).y, BOX)
  seam = turn(seam, -170, 100)
  check('across the seam at the left, where the angle wraps: 20 degrees on, not 340 back', [near(seam.offset, 0.1), near(seam.turned, 20 / 180 * Math.PI)], [true, true])
  seam = turn(seam, 170, 100)
  check('...and back across it: back where it was', near(seam.offset, 0), true)

  let start = tt.recordStart(1, 'song', onRecord(0).x, onRecord(0).y, BOX)
  for (let degrees = -30; degrees >= -360; degrees -= 30) start = turn(start, degrees, 0.5)
  check('turned back past the start: held at 0:00', showing(start, 0.5), 0)
  start = turn(start, -330, 0.5)
  check('...and turning forward moves it straight away', near(showing(start, 0.5), 0.15), true)
  let end = tt.recordStart(1, 'song', onRecord(0).x, onRecord(0).y, BOX)
  for (let degrees = 30; degrees <= 360; degrees += 30) end = turn(end, degrees, LENGTH - 0.5)
  check('turned on past the end: held at the end', showing(end, LENGTH - 0.5), LENGTH)

  let spindle = tt.recordStart(1, 'song', onRecord(0).x, onRecord(0).y, BOX)
  spindle = turn(spindle, 90, 100, 8)
  spindle = turn(spindle, 270, 100, 8)
  check('at the spindle a turn means nothing: none counted', [spindle.offset, spindle.turned, spindle.angle], [0, 0, null])
  spindle = turn(spindle, 180, 100)
  spindle = turn(spindle, 210, 100)
  check('...out of it again, turns count from there', near(spindle.offset, 0.15), true)
  check('another finger turns nothing', tt.recordMove(spin, 2, 0, 0, BOX, LENGTH, 100) === spin, true)
  check('an arm drag isn\'t turned by the record\'s moves', tt.recordMove(tt.armStart(1, 's', 300, 200), 1, 0, 0, BOX, LENGTH, 0).kind, 'arm')
  let none = tt.recordStart(1, 'song', onRecord(0).x, onRecord(0).y, BOX)
  none = tt.recordMove(none, 1, onRecord(90).x, onRecord(90).y, BOX, 0, 30)
  check('a song with no length: the record turns, the song doesn\'t move', [none.offset, near(none.turned, Math.PI / 2)], [0, true])

  //? THE SONG PLAYS ON under the finger - only the record stops. Held three seconds at 2:31 before
  //? a quarter turn forward, and then let go at 2:34.45: a turn is an offset from the song as it is
  //? when it lets go, never a time fixed at the press, which seeked back three seconds
  let held = tt.recordStart(1, 'song', onRecord(0).x, onRecord(0).y, BOX)
  held = tt.recordMove(held, 1, onRecord(0).x + 3, onRecord(0).y, BOX, LENGTH, 151)
  held = tt.recordMove(held, 1, onRecord(0).x + 5, onRecord(0).y + 2, BOX, LENGTH, 154)
  check('held still a moment: a tap still, nothing shown in the song\'s place', [tt.moved(held), tt.preview(held)], [false, null])
  for (let degrees = 15; degrees <= 90; degrees += 15) held = turn(held, degrees, 154 + degrees / 200)
  check('then turned a quarter forward: shown a quarter turn ahead of the song as it is now', near(showing(held, 154.45), 154.9), true)
  const lands = tt.dragEnd(held, 1, 'up', 154.45, LENGTH)
  check('...and let go there: never behind the song - a forward turn went forward', [near(lands.seek, 154.9), lands.seek > 154.45], [true, true])
  //? half a turn over a second and a half - slower than the record turns itself
  let slowly = tt.recordStart(1, 'song', onRecord(0).x, onRecord(0).y, BOX)
  for (let degrees = 18; degrees <= 180; degrees += 18) slowly = turn(slowly, degrees, 151 + (degrees / 180) * 1.5)
  check('a half turn slower than the record turns: 0.9 s on from where the song is when it lets go', near(tt.dragEnd(slowly, 1, 'up', 152.5, LENGTH).seek, 153.4), true)
}

console.log('\na tap, a drag, a cancel')
{
  const at = onRecord(45)
  let press = tt.recordStart(1, 'song', at.x, at.y, BOX)
  press = tt.recordMove(press, 1, at.x + TAP_SLOP_PX - 1, at.y, BOX, LENGTH, 151)
  check(`under ${TAP_SLOP_PX} px: a tap - nothing to preview, no seek, the click is a tap`,
    [tt.moved(press), tt.preview(press), tt.dragEnd(press, 1, 'up', 151, LENGTH)], [false, null, { drag: null, seek: null, wasDrag: false }])
  press = tt.recordMove(press, 1, at.x, at.y, BOX, LENGTH, 151)
  check('back where it began: still a tap', tt.moved(press), false)
  const far = onRecord(80)
  press = tt.recordMove(press, 1, far.x, far.y, BOX, LENGTH, 151)
  const back = tt.recordMove(press, 1, at.x, at.y, BOX, LENGTH, 151)
  check('gone far and come back: a drag - how far it went counts, not where it ended', tt.moved(back), true)
  check('...previewed as a scrub, a turn ahead of the song', [tt.preview(press).how, near(tt.shownTime(tt.preview(press), 151, LENGTH), 151 + 35 / 360 * SECONDS_PER_TURN)], ['record', true])
  check('let go: it seeks exactly what it shows, and the click after it is not a tap',
    [tt.dragEnd(press, 1, 'up', 151, LENGTH).seek === tt.shownTime(tt.preview(press), 151, LENGTH), tt.dragEnd(press, 1, 'up', 151, LENGTH).wasDrag], [true, true])
  check('cancelled: it seeks nowhere', tt.dragEnd(press, 1, 'cancel', 151, LENGTH).seek, null)
  let straight = tt.recordStart(1, 'song', at.x, at.y, BOX)
  straight = tt.recordMove(straight, 1, onRecord(45, 140).x, onRecord(45, 140).y, BOX, LENGTH, 151)
  check('dragged straight out, turning nothing: a drag, but nothing to move', tt.dragEnd(straight, 1, 'up', 151, LENGTH), { drag: null, seek: null, wasDrag: true })
  check('the arm previews from the press - the needle is up, over the song', tt.preview(tt.armStart(1, 's', 300, 200)), { how: 'arm', time: null })
  check('a drag begun on another song is let go of', [tt.dragFor(press, 'another song'), tt.dragFor(press, 'song') === press], [null, true])
}

console.log('\nwhat the time line says')
{
  check('the song\'s time: "2:31 of 7:05"', tt.timeLine(151, LENGTH, null), '2:31 of 7:05')
  check('turning the record, the needle up', [tt.timeLine(151, LENGTH, 'record'), tt.timeLine(151, LENGTH, 'arm')], [`Scrubbing ${String.fromCharCode(0xb7)} 2:31 of 7:05`, `Needle up ${String.fromCharCode(0xb7)} 2:31 of 7:05`])
  check('no length known: the time alone', tt.timeLine(151, 0, null), '2:31')
  check('the shown time: the arm\'s needle, or the song\'s, within the song',
    [tt.shownTime({ how: 'arm', time: 90 }, 151, LENGTH), tt.shownTime(null, 151, LENGTH), tt.shownTime({ how: 'arm', time: 900 }, 151, LENGTH),
      tt.shownTime(null, -3, LENGTH), tt.shownTime({ how: 'arm', time: null }, 151, LENGTH)], [90, 151, LENGTH, 0, 151])
  check('...the record\'s turn from the song as it is, within the song',
    [tt.shownTime({ how: 'record', offset: 2 }, 151, LENGTH), tt.shownTime({ how: 'record', offset: 2 }, 160, LENGTH), tt.shownTime({ how: 'record', offset: -500 }, 151, LENGTH)], [153, 162, 0])
}

console.log('\nhow fast the record turns')
{
  const platter = require(path.join(OUT, 'lib/platter.js'))
  check('the platter at its own speed: one turn in SECONDS_PER_TURN, 33 1/3 rpm', platter.DEGREES_PER_SECOND, 360 / SECONDS_PER_TURN)
  const theme = fs.readFileSync(path.join(REPO, 'interface/styles/theme.css'), 'utf8')
  check('...and no CSS spin of its own beside it any more', /--dw-record-turn:/.test(theme), false)
}

console.log('\nthe record\'s face, and the words')
{
  const songs = [{ id: 'd1t1', discNumber: 1 }, { id: 'd2t3', discNumber: 2 }, { id: 'x', discNumber: 0 }, { id: 'y' }]
  check('the playing song\'s disc, by the album it was played from', [tt.playingDisc(songs, 'd2t3'), tt.playingDisc(songs, 'd1t1')], [2, 1])
  check('...1 where that isn\'t known', [tt.playingDisc(songs, 'x'), tt.playingDisc(songs, 'y'), tt.playingDisc(songs, 'nope'), tt.playingDisc(null, 'd2t3')], [1, 1, 1, 1])
  check('where deadwax serves it: the library route, by album and disc',
    [tt.discArtPath('al 1/2', 2), tt.discArtPath('wywh', 0)], ['/library/disc_art/navidrome?album=al%201%2F2&disc=2', '/library/disc_art/navidrome?album=wywh&disc=1'])
  check('...and nothing for a song that names no album', [tt.discArtPath(null, 1), tt.discArtPath('', 1)], [null, null])
  check('the look button names the look it switches to',
    [tt.lookButtonLabel('cover'), tt.lookButtonLabel('turntable'), tt.otherLook('cover'), tt.otherLook('turntable')],
    ['Show as a turntable', 'Show the cover', 'turntable', 'cover'])
}

/* ===== the turntable itself ===== */

const { Turntable, TurntableTime } = require(path.join(OUT, 'player/Turntable.js'))

function fakePlayer(overrides = {}) {
  const player = {
    track: { id: 'time', title: 'Time', coverArt: 'cover-dsotm', albumId: 'dsotm' },
    playing: true, duration: LENGTH, at: 151,
    seeks: [], toggles: 0,
    seek(t) { this.seeks.push(Math.round(t * 1000) / 1000) }, toggle() { this.toggles += 1 },
    position() { return this.at }, onPosition: () => () => {},
    ...overrides,
  }
  return player
}
const pointer = (point, extra = {}) => ({
  pointerId: 1, isPrimary: true, pointerType: 'touch', button: 0, clientX: point.x, clientY: point.y, timeStamp: clock,
  currentTarget: { captured: null, setPointerCapture(id) { this.captured = id } }, ...extra,
})

console.log('\nthe speed fader (2.0.0-player.39): drawn where the player has one, the deck told the speed')
{
  const listeners = new Set()
  const speedPlayer = { now: 1.5, speed() { return this.now }, onSpeed(listener) { listeners.add(listener); return () => listeners.delete(listener) }, setSpeed() {} }
  const player = fakePlayer({ speed: () => speedPlayer.now, onSpeed: (listener) => speedPlayer.onSpeed(listener) })
  const deckRef = { current: null }
  const view = mount(Turntable, 'turntable with a speed')
  view.render({ player, open: true, discArt: null, onPreview() {}, deck: deckRef, fader: speedPlayer })
  check('given the fader\'s player: the fader drawn on the stage, after the record, before the arm\'s handle',
    (() => {
      const children = view.find(byClass('app-tt-stage'))[0].props.children.flat().filter(Boolean)
      const at = (test) => children.findIndex(test)
      return [!!view.find(named('SpeedFader'))[0], at(byClass('app-tt-record')) < at(named('SpeedFader')), at(named('SpeedFader')) < at(byClass('app-tt-handle'))]
    })(), [true, true, true])
  check('...the deck told the player\'s speed as it mounts', deckRef.current['speed'], 1.5)
  speedPlayer.now = 0.5
  listeners.forEach((listener) => listener(0.5))
  check('...and as it changes', deckRef.current['speed'], 0.5)
  view.unmount()
  check('...and no longer once it has gone', listeners.size, 0)
  const bench = mount(Turntable, 'the bench\'s turntable')
  const benchDeck = { current: null }
  bench.render({ player: fakePlayer(), open: true, discArt: null, onPreview() {}, deck: benchDeck })
  check('a player with no speed (the test bench\'s): no fader, and the deck at 1x', [bench.find(named('SpeedFader')).length, benchDeck.current['speed']], [0, 1])
  bench.unmount()
}

console.log('\nthe record: a tap plays or pauses, in the click; a turn seeks where it lets go')
{
  const player = fakePlayer()
  const previews = []
  const view = mount(Turntable, 'turntable')
  const draw = (props = {}) => view.render({ player, open: true, discArt: null, onPreview: (p) => previews.push(p), ...props })
  draw()
  const record = () => view.find(byClass('app-tt-record'))[0]
  const turnStyle = () => view.find(byClass('app-tt-turn'))[0].props.style.transform
  const face = () => view.find(byClass('app-tt-face'))[0]
  check('a button, named for what a tap does', [record().type, record().props['aria-label']], ['button', 'The record: a tap pauses the song'])
  check('...and so while paused', (draw({ player: { ...player, playing: false } }), record().props['aria-label']), 'The record: a tap plays the song')
  draw()

  const at = onRecord(0)
  const down = pointer(at)
  record().props.onPointerDown(down)
  record().props.onPointerUp(pointer(at))
  draw()
  check('pressed and let go where it was: no seek, the pointer was captured', [player.seeks, down.currentTarget.captured], [[], 1])
  const returned = record().props.onClick()
  check('...and its click plays or pauses by the time it returns', [player.toggles, returned === undefined], [1, true])

  record().props.onPointerDown(pointer(at))
  for (let degrees = 30; degrees <= 90; degrees += 30) record().props.onPointerMove(pointer(onRecord(degrees)))
  draw()
  check('turned a quarter: the record turned with the hand', turnStyle(), 'rotate(90deg)')
  check('...the time previewed, for the line under the song', [previews.at(-1).how, near(previews.at(-1).offset, 0.45)], ['record', true])
  check('...and no seek on the way', player.seeks, [])
  record().props.onPointerUp(pointer(onRecord(90)))
  record().props.onLostPointerCapture(pointer(onRecord(90)))
  draw()
  check('let go: one seek, to where it was turned', player.seeks, [151.45])
  check('...the record stays where the hand left it, nothing previewed', [turnStyle(), previews.at(-1)], ['rotate(90deg)', null])
  record().props.onClick()
  check('the click after the turn is not a tap', player.toggles, 1)
  record().props.onPointerDown(pointer(at))
  record().props.onPointerUp(pointer(at))
  record().props.onClick()
  check('...and the next tap is one again', player.toggles, 2)

  //? a turn that no click follows (WebKit sends none after a drag): the next press forgets it
  record().props.onPointerDown(pointer(at))
  record().props.onPointerMove(pointer(onRecord(60)))
  record().props.onPointerUp(pointer(onRecord(60)))
  record().props.onPointerDown(pointer(at))
  record().props.onPointerUp(pointer(at))
  record().props.onClick()
  check('a turn with no click after it doesn\'t swallow the next tap', player.toggles, 3)

  const seeks = player.seeks.length
  record().props.onPointerDown(pointer(at))
  record().props.onPointerMove(pointer(onRecord(90)))
  record().props.onPointerCancel(pointer(onRecord(90)))
  draw()
  check('a cancelled turn seeks nowhere, and previews nothing', [player.seeks.length === seeks, previews.at(-1)], [true, null])
  record().props.onPointerDown(pointer(at, { pointerType: 'mouse', button: 2 }))
  record().props.onPointerMove(pointer(onRecord(90), { pointerType: 'mouse', button: 2 }))
  record().props.onPointerUp(pointer(onRecord(90), { pointerType: 'mouse', button: 2 }))
  check('a right-click turns nothing', player.seeks.length === seeks, true)

  record().props.onPointerDown(pointer(at))
  record().props.onPointerMove(pointer(onRecord(90)))
  draw({ player: { ...player, track: { ...player.track, id: 'money' } } })
  record().props.onPointerUp(pointer(onRecord(90)))
  check('the song changed under the finger: the turn seeks nowhere', player.seeks.length === seeks, true)
  draw()

  //? The same with a MOUSE, on ONE player object (a copy would take the toggle out of sight): a
  //? mouse's click still comes after a drag - Chromium sends it to the element holding the pointer -
  //? and with the drag dropped by the song changing, no release said it was a turn
  const mouse = (point) => pointer(point, { pointerType: 'mouse' })
  const toggles = player.toggles
  record().props.onPointerDown(mouse(at))
  for (let degrees = 30; degrees <= 90; degrees += 30) record().props.onPointerMove(mouse(onRecord(degrees)))
  player.track = { ...player.track, id: 'money' }
  draw()
  record().props.onPointerUp(mouse(onRecord(90)))
  record().props.onLostPointerCapture(mouse(onRecord(90)))
  draw()
  record().props.onClick()
  check('a mouse turn the song changed under: its click is no tap - the new song plays on, and nothing seeks',
    [player.toggles - toggles, player.seeks.length === seeks], [0, true])
  record().props.onPointerDown(mouse(at))
  record().props.onPointerUp(mouse(at))
  record().props.onClick()
  check('...and the next click is a tap again', player.toggles - toggles, 1)
  player.track = { ...player.track, id: 'time' }
  draw()

  //? a second finger on the record while the first turns it starts nothing: the first finger's
  //? turn carries on, and lets go where it was turned to
  player.seeks.length = 0
  record().props.onPointerDown(pointer(at))
  record().props.onPointerDown(pointer(onRecord(200), { pointerId: 2, isPrimary: false }))
  for (let degrees = 30; degrees <= 90; degrees += 30) record().props.onPointerMove(pointer(onRecord(degrees)))
  record().props.onPointerMove(pointer(onRecord(300), { pointerId: 2, isPrimary: false }))
  record().props.onPointerUp(pointer(onRecord(200), { pointerId: 2, isPrimary: false }))
  record().props.onPointerUp(pointer(onRecord(90)))
  check('a second finger starts nothing: one seek, to where the first finger turned it', player.seeks, [151.45])

  //? the layout moving under a finger mid-drag (a line appearing above the song's name, say) moves
  //? nothing: the drag is measured in the stage's box as the press found it
  player.seeks.length = 0
  record().props.onPointerDown(pointer(at))
  record().props.onPointerMove(pointer(onRecord(45)))
  Object.assign(BOX, { left: 12, top: -24, width: 340, height: 336 })
  record().props.onPointerMove(pointer(onRecord(90)))
  record().props.onPointerUp(pointer(onRecord(90)))
  Object.assign(BOX, { left: 0, top: 0, width: 372, height: 368 })
  check('the stage moved and shrank mid-turn: the turn is what the finger did', player.seeks, [151.45])

  //? THE SONG PLAYS ON under a finger: held three seconds, then turned a quarter - it lands a
  //? quarter turn on from where the song has got to, never back at the press
  player.seeks.length = 0
  record().props.onPointerDown(pointer(at))
  draw()
  player.at = 154
  draw()
  for (let degrees = 30; degrees <= 90; degrees += 30) record().props.onPointerMove(pointer(onRecord(degrees)))
  draw()
  const line = mount(TurntableTime, 'line').render({ player, previewing: previews.at(-1) }).props.children
  record().props.onPointerUp(pointer(onRecord(90)))
  check('held a moment, then turned forward: shown and sought a quarter turn past the song, not behind it',
    [line, player.seeks], [`Scrubbing ${String.fromCharCode(0xb7)} 2:34 of 7:05`, [154.45]])
  player.at = 151
  draw()
}

console.log('\nthe arm: a drag goes anywhere, a key steps; a slider to the keyboard')
{
  const player = fakePlayer()
  const previews = []
  const view = mount(Turntable, 'turntable')
  const draw = (props = {}) => view.render({ player, open: true, discArt: null, onPreview: (p) => previews.push(p), ...props })
  draw()
  const handle = () => view.find(byClass('app-tt-handle'))[0]
  check('a slider, as the scrubber is: its value and its words',
    [handle().props.role, handle().props.tabIndex, handle().props['aria-valuenow'], handle().props['aria-valuemax'], handle().props['aria-valuetext']],
    ['slider', 0, 151, LENGTH, '2:31 of 7:05'])
  const needle = tt.needleAt(151, LENGTH)
  check('taken by its head, round the needle', [handle().props.style.left, handle().props.style.top], [tt.placePoint(needle).left, tt.placePoint(needle).top])

  const armDown = pointer(needle)
  handle().props.onPointerDown(armDown)
  draw()
  check('held: the needle is up over the song, the head lifted, and the pointer captured',
    [previews.at(-1), hasClass(handle(), 'is-held'), view.find(byClass('app-tt-arm'))[0].props.class, armDown.currentTarget.captured],
    [{ how: 'arm', time: null }, true, 'app-tt-arm is-lifted', 1])
  //? a nudge under the slop along the arm's arc shows nothing it won't go to, and seeks nothing
  handle().props.onPointerMove(pointer(aboutPivot(needle, TAP_SLOP_PX - 1)))
  draw()
  check('nudged under the slop: the arm and its value stay the song\'s', [handle().props['aria-valuenow'], previews.at(-1)], [151, { how: 'arm', time: null }])
  handle().props.onPointerUp(pointer(aboutPivot(needle, TAP_SLOP_PX - 1)))
  draw()
  check('...and let go, nothing - what it showed', player.seeks, [])
  handle().props.onPointerDown(pointer(needle))
  const toEnd = reachAt(tt.armAngle(LENGTH, LENGTH) + 10)
  handle().props.onPointerMove(pointer(toEnd))
  draw()
  check('dragged past the inner groove: the end previewed, nothing asked yet', [near(previews.at(-1).time, LENGTH, 1e-6), player.seeks], [true, []])
  check('...and the arm drawn there', view.find(byClass('app-tt-arm'))[0].props.transform, `rotate(${+tt.armAngle(LENGTH, LENGTH).toFixed(3)} ${ARM.x} ${ARM.y})`)
  handle().props.onPointerUp(pointer(toEnd))
  check('let go: the seek, once', player.seeks, [LENGTH])
  draw()
  handle().props.onPointerDown(pointer(needle))
  handle().props.onPointerUp(pointer(needle))
  check('pressed and let go without moving: nothing', player.seeks, [LENGTH])

  const key = (name) => { let prevented = false; handle().props.onKeyDown({ key: name, preventDefault() { prevented = true } }); return prevented }
  player.seeks.length = 0
  check('arrows step 5 s, Page Up and Down 30, Home to the start',
    [key('ArrowRight'), key('ArrowLeft'), key('PageUp'), key('PageDown'), key('Home'), player.seeks], [true, true, true, true, true, [156, 146, 181, 121, 0]])
  check('...and another key is left alone', [key('a'), player.seeks.length], [false, 5])

  const silent = fakePlayer({ duration: 0 })
  view.render({ player: silent, open: true, discArt: null, onPreview: () => {} })
  handle().props.onPointerDown(pointer(needle))
  handle().props.onPointerMove(pointer(toEnd))
  handle().props.onPointerUp(pointer(toEnd))
  check('a song with no length: out of the tab order, disabled, and a drag seeks nothing', [handle().props.tabIndex, handle().props['aria-disabled'], silent.seeks], [-1, true, []])

  //? gone mid-drag (the look switched, the song ended with nothing after it): the preview goes too,
  //? or the time line would say "Needle up" when the turntable came back
  const gone = mount(Turntable, 'turntable')
  const said = []
  gone.render({ player: fakePlayer(), open: true, discArt: null, onPreview: (next) => said.push(next) })
  const goneHandle = gone.find(byClass('app-tt-handle'))[0]
  goneHandle.props.onPointerDown(pointer(needle))
  goneHandle.props.onPointerMove(pointer(toEnd))
  check('held and dragged: previewed', said.at(-1)?.how, 'arm')
  gone.unmount()
  check('...then gone: the last word is that nothing is previewed', said.at(-1), null)
}

console.log('\nwhen it turns, and what is on it')
{
  const view = mount(Turntable, 'turntable')
  const face = () => view.find(byClass('app-tt-face'))[0]
  const draw = (props = {}) => view.render({ player: fakePlayer(), open: true, discArt: null, onPreview: () => {}, ...props })
  //? the face's angle as the deck last wrote it straight onto the element
  const angle = () => Number(/rotate\(([-\d.]+)deg\)/.exec(face().element.style.transform ?? '')?.[1] ?? 0)
  frames = []
  draw()
  runFrames(10)
  const first = angle()
  runFrames(9)
  check('playing and open: the deck turns it, frame by frame, a turn in 1.8 s (144 ms: 28.8 degrees)', [first > 0, Math.round((angle() - first) * 10) / 10], [true, 28.8])
  check('...and Turntable never writes a style on the face itself, which a render would undo', face().props.style, undefined)
  draw({ player: fakePlayer({ playing: false }) })
  runFrames(10)
  const pausing = angle()
  runFrames(10)
  check('paused by something else (a song ending, the lock screen): it waits a moment - a song change pauses for one - then spins down', angle() > pausing, true)
  runFrames(80)
  const still = angle()
  runFrames(10)
  check('...and stops: no more frames asked for, the record still', [angle() === still, frames.length], [true, 0])
  draw()
  runFrames(30)
  const playing = angle()
  draw({ open: false })
  runFrames(5)
  check('Now Playing closed: no frame asked for, nothing drawn', frames.length, 0)
  draw()
  runFrames(2)
  document.visibilityState = 'hidden'
  fire('visibilitychange')
  draw()
  runFrames(5)
  check('the page hidden - a locked phone: no frame asked for, nothing drawn for nobody', [frames.length, angle() > playing], [0, true])
  document.visibilityState = 'visible'
  fire('visibilitychange')
  draw()
  const back = angle()
  runFrames(5)
  check('showing again: it turns again', angle() > back, true)
  //? a press before the deck's sound runs - .11's press, as every press in this section is (no audio
  //? context here): the record stops under the finger, as .11's spin paused, and turns on when let go
  const record = () => view.find(byClass('app-tt-record'))[0]
  runFrames(2)
  record().props.onPointerDown(pointer(onRecord(0)))
  const pressedAt = angle()
  runFrames(20)
  check('pressed and resting (.11\'s press, before the sound runs): the record stops under the finger - and no frame is asked for',
    [angle(), frames.length], [pressedAt, 0])
  record().props.onPointerMove(pointer(onRecord(30)))
  draw()
  runFrames(5)
  check('...turned: the face turns with the hand alone (on its wrapper), not on round under it as well', angle(), pressedAt)
  record().props.onPointerUp(pointer(onRecord(30)))
  runFrames(1)
  check('...let go: it turns on from where the finger held it, a frame\'s worth - no jump', Math.round((angle() - pressedAt) * 10) / 10, 3.2)
  const source = fs.readFileSync(path.join(UI, 'src/player/Turntable.tsx'), 'utf8')
  check('no frame loop of its own: the platter is the deck\'s (player/deck.ts)',
    [/requestAnimationFrame|setInterval|setTimeout/.test(source), /requestAnimationFrame/.test(fs.readFileSync(path.join(UI, 'src/player/deck.ts'), 'utf8'))], [false, true])

  const art = () => view.find((node) => node.type === 'img' && hasClass(node, 'app-tt-disc'))[0]
  draw({ discArt: '/deadwax/library/disc_art/navidrome?album=dsotm&disc=1' })
  check('the CD art on the record, over the plain one', [art()?.props.src, view.find(named('Cover')).length, hasClass(face(), 'has-art')],
    ['/deadwax/library/disc_art/navidrome?album=dsotm&disc=1', 1, false])
  check('...the cover the label under it', view.find(named('Cover'))[0].props, { id: 'cover-dsotm', size: 300, class: 'app-tt-label' })
  art().props.onLoad()
  draw({ discArt: '/deadwax/library/disc_art/navidrome?album=dsotm&disc=1' })
  check('come: the label goes under it', hasClass(face(), 'has-art'), true)
  art().props.onError()
  draw({ discArt: '/deadwax/library/disc_art/navidrome?album=dsotm&disc=1' })
  check('none to be had (a 404): the plain record, the cover its label', [art(), hasClass(face(), 'has-art'), view.find(named('Cover')).length], [undefined, false, 1])
  draw({ discArt: '/deadwax/library/disc_art/navidrome?album=dsotm&disc=1', open: false })
  check('...not asked again while Now Playing is closed', art(), undefined)
  draw({ discArt: '/deadwax/library/disc_art/navidrome?album=dsotm&disc=1' })
  draw({ discArt: '/deadwax/library/disc_art/navidrome?album=dsotm&disc=1' })
  check('...but asked again when it opens: CD art saved since (Get CD art), or a Navidrome back up, is found',
    art()?.props.src, '/deadwax/library/disc_art/navidrome?album=dsotm&disc=1')
  art().props.onError()
  draw({ discArt: '/deadwax/library/disc_art/navidrome?album=dsotm&disc=1' })
  draw({ discArt: '/deadwax/library/disc_art/navidrome?album=dsotm&disc=2' })
  check('...which is that address alone: the next disc\'s is asked for', art()?.props.src, '/deadwax/library/disc_art/navidrome?album=dsotm&disc=2')
  const hint = /Turn the record|Drag the arm|Got it/i.test(source)
  check('no hint and no coach mark', hint, false)
}

console.log('\nthe time line')
{
  const view = mount(TurntableTime, 'time')
  const player = fakePlayer()
  check('the song\'s time', view.render({ player, previewing: null }).props.children, '2:31 of 7:05')
  check('...or where letting go will go: the record\'s turn from the song, the arm\'s needle',
    [view.render({ player, previewing: { how: 'record', offset: -61 } }).props.children, view.render({ player, previewing: { how: 'arm', time: 90 } }).props.children],
    [`Scrubbing ${String.fromCharCode(0xb7)} 1:30 of 7:05`, `Needle up ${String.fromCharCode(0xb7)} 1:30 of 7:05`])
}

/* ===== with the deck's sound running (2.0.0-player.14) ===== */

//? an audio context that records what is asked of it, a worklet port, and deadwax's window route
const contexts = []
const port = []
class FakeContext {
  constructor() { this.state = 'suspended'; this.currentTime = 0; this.calls = []; this.audioWorklet = { addModule: () => Promise.resolve() }; contexts.push(this) }
  addEventListener() {}
  resume() { this.calls.push('resume'); this.state = 'running'; return Promise.resolve() }
  suspend() { this.calls.push('suspend'); this.state = 'suspended'; return Promise.resolve() }
  close() { this.calls.push('close'); this.state = 'closed'; return Promise.resolve() }
  decodeAudioData(bytes, done) { const length = 30 * 48000; done({ numberOfChannels: 2, sampleRate: 48000, length, getChannelData: () => new Float32Array(length) }) }
}
class FakeNode { constructor() { this.port = { postMessage: (message) => port.push(message), onmessage: null } } connect() {} disconnect() {} }
const windowsAsked = []
const settle = async () => { for (let i = 0; i < 4; i++) await new Promise((resolve) => setImmediate(resolve)) }

//? a player whose toggle plays and pauses, as the engine's does, and that hears its own position
function livePlayer() {
  const player = {
    track: { id: 'time', title: 'Time', coverArt: 'cover-dsotm', albumId: 'dsotm', suffix: 'flac' },
    playing: true, duration: LENGTH, at: 151, seeks: [], toggles: [], listeners: new Set(),
    seek(t) { this.seeks.push(Math.round(t * 1000) / 1000); this.at = t },
    toggle() { this.playing = !this.playing; this.toggles.push(this.playing ? 'play' : 'pause') },
    position() { return this.at }, onPosition(listener) { this.listeners.add(listener); return () => this.listeners.delete(listener) },
    moveTo(seconds) { this.at = seconds; for (const listener of [...this.listeners]) listener(seconds) },
  }
  for (const name of ['seek', 'toggle', 'position', 'onPosition', 'moveTo']) player[name] = player[name].bind(player)
  return player
}

async function liveChecks() {
  console.log('\nwith the deck\'s sound running: the record is taken, the song paused, and let go it lands where the platter does')
  define('AudioContext', FakeContext)
  define('AudioWorkletNode', FakeNode)
  URL.createObjectURL = () => 'blob:deck-voice'
  define('fetch', async (url) => {
    windowsAsked.push(String(url))
    const at = Number(new URL(String(url), 'http://x').searchParams.get('at'))
    return { ok: true, status: 200, headers: { get: (name) => (name === 'x-deadwax-window' ? `${Math.round(at * 44100)}/${30 * 44100}/44100` : null) }, arrayBuffer: async () => new ArrayBuffer(3_000_000) }
  })
  const platter = require(path.join(OUT, 'lib/platter.js'))
  const player = livePlayer()
  const previews = []
  const view = mount(Turntable, 'live turntable')
  let windDown = true
  const draw = () => view.render({ player, open: true, discArt: null, onPreview: (next) => previews.push(next), windDown })
  draw()
  const record = () => view.find(byClass('app-tt-record'))[0]
  const at = onRecord(0)

  //? the first tap: still .11's world until it - and it makes the audio context, in the click
  record().props.onClick()
  await settle()
  draw()
  check('a tap plays or pauses in the click, and makes the deck\'s audio context there, running', [player.toggles, contexts.length, contexts[0]?.state], [['pause'], 1, 'running'])
  record().props.onClick()
  await settle()
  draw()
  check('...the next tap plays again; the context is made once', [player.toggles, contexts.length], [['pause', 'play'], 1])
  await settle()
  draw()
  check('the window asked for round the song as it plays', windowsAsked.at(-1), '/deadwax/navidrome/scrub/time?at=146&seconds=40')

  //? a drag past a tap: taken, paused
  player.seeks.length = 0
  player.toggles.length = 0
  record().props.onPointerDown(pointer(at))
  check('pressed: the song plays on for now - it may be a tap', player.toggles, [])
  advance(10)
  //? ...and it does: 10 ms of it by the move past a tap (2.0.0-player.40: the deck takes the record from the
  //? press, where the song was then - where it is now less what it played since)
  player.at = 151.01
  record().props.onPointerMove(pointer(onRecord(20)))
  draw()
  check('moved past a tap: the record taken, the song paused - the player\'s own toggle', player.toggles, ['pause'])
  check('...the record\'s sound takes over where the song was, at its own speed', [port.filter((m) => m.type === 'take').at(-1)?.at, port.filter((m) => m.type === 'take').at(-1)?.rate], [151, 1])
  //? a flick forward: a turn a second for its last 100 ms
  for (let step = 1; step <= 10; step++) {
    advance(10)
    record().props.onPointerMove(pointer(onRecord(20 + step * 3.6)))
  }
  //? the turn counted from the press (2.0.0-player.40): 56 degrees, the move that crossed a tap's few pixels
  //? included - until then from the crossing, 36
  const taken = 151 + (56 / 360) * SECONDS_PER_TURN
  const plan = platter.motor(taken, 1.8, LENGTH)
  record().props.onPointerUp(pointer(onRecord(56)))
  record().props.onLostPointerCapture(pointer(onRecord(56)))
  draw()
  check('let go: sought NOW to where the motor will have the platter back at speed - nothing played yet', [player.seeks.length, Math.abs(player.seeks[0] - plan.x) < 0.01, player.toggles], [1, true, ['pause']])
  record().props.onClick()
  check('...the click after it is no tap', player.toggles, ['pause'])
  runFrames(3)
  draw()
  check('while it comes back to speed the time line says where it is, scrubbing', [previews.at(-1)?.how, previews.at(-1)?.scrubbing], ['deck', true])
  advance(plan.duration * 1000 + 20)
  draw()
  check('at speed: the song plays - the player\'s own toggle, after the tap', player.toggles, ['pause', 'play'])
  player.moveTo(plan.x + 0.05)
  check('...and once it really plays, the record\'s sound fades out', port.filter((m) => m.type === 'fade').length, 1)

  //? a press that rests: taken after HOLD_MS, and let go it spins back up
  player.seeks.length = 0
  player.toggles.length = 0
  const rested = player.at
  record().props.onPointerDown(pointer(at))
  advance(300)
  draw()
  check('pressed and held still longer than a tap: taken, the song paused', player.toggles, ['pause'])
  record().props.onPointerUp(pointer(at))
  draw()
  check('let go without a turn: sought to where the spin-up has it at speed, 0.2 s on', player.seeks,
    [Math.round(platter.motor(rested, 0, LENGTH).x * 1000) / 1000])
  check('...which is 0.2 s on from where it was taken', Math.round((player.seeks[0] - rested) * 1000) / 1000, 0.2)
  record().props.onClick()
  check('...its click no tap', player.toggles, ['pause'])
  advance(platter.SPIN_UP_S * 1000 + 20)
  draw()
  check('...and played at speed, 0.4 s later', player.toggles, ['pause', 'play'])

  //? a cancel: nothing sought, the song plays on
  player.seeks.length = 0
  player.toggles.length = 0
  record().props.onPointerDown(pointer(at))
  advance(10)
  record().props.onPointerMove(pointer(onRecord(30)))
  record().props.onPointerCancel(pointer(onRecord(30)))
  draw()
  check('taken, then the system takes the touch: nothing sought, and the song it paused plays on', [player.seeks, player.toggles], [[], ['pause', 'play']])

  //? a tap pauses - and winds down, sought to where it stops; the setting off: a plain pause. The
  //? platter back at its own speed first (the cancel above set it spinning up again)
  advance(600)
  runFrames(2)
  draw()
  player.seeks.length = 0
  player.toggles.length = 0
  player.at = 152
  record().props.onPointerDown(pointer(at))
  record().props.onPointerUp(pointer(at))
  record().props.onClick()
  draw()
  const winding = platter.coast(152, 1, LENGTH)
  check('a tap pauses in the click, and the song is sought to where the record winds down to', [player.toggles, player.seeks], [['pause'], [Math.round(winding.x * 1000) / 1000]])
  check('...the record\'s sound starting there, at its own speed', [port.filter((m) => m.type === 'take').at(-1)?.at, port.filter((m) => m.type === 'take').at(-1)?.rate], [152, 1])
  //? a play tapped 0.1 s into the wind-down: from where the record has got to - what was heard - not
  //? from where the wind-down was sought to end
  advance(100)
  player.seeks.length = 0
  record().props.onPointerDown(pointer(at))
  record().props.onPointerUp(pointer(at))
  record().props.onClick()
  draw()
  check('a play mid wind-down: sought first to where the record is, then played - in the click',
    [player.seeks, player.toggles], [[Math.round(platter.planAt(winding, 0.1).x * 1000) / 1000], ['pause', 'play']])
  //? the switch: with it ON the same tap on a platter back at speed winds down (the control), OFF it doesn't
  const backAtSpeed = () => {
    advance(600)
    runFrames(2)
    draw()
  }
  backAtSpeed()
  player.seeks.length = 0
  player.at = 160
  record().props.onPointerDown(pointer(at))
  record().props.onPointerUp(pointer(at))
  record().props.onClick()
  draw()
  check('"Pause winds the record down" on, the platter at speed: the tap\'s pause sought to where the wind-down stops',
    [player.toggles.at(-1), player.seeks], ['pause', [Math.round(platter.coast(160, 1, LENGTH).x * 1000) / 1000]])
  record().props.onPointerDown(pointer(at))
  record().props.onPointerUp(pointer(at))
  record().props.onClick()
  backAtSpeed()
  windDown = false
  draw()
  player.seeks.length = 0
  player.at = 160
  record().props.onPointerDown(pointer(at))
  record().props.onPointerUp(pointer(at))
  record().props.onClick()
  draw()
  check('...off, the same tap: a plain pause, nothing sought', [player.toggles.at(-1), player.seeks], ['pause', []])
  windDown = true
  record().props.onClick()
  draw()

  //? the arm: the record's sound stops, and the arm and the time line follow the finger, not the coast
  backAtSpeed()
  const stops = port.filter((m) => m.type === 'stop').length
  record().props.onPointerDown(pointer(at))
  advance(10)
  record().props.onPointerMove(pointer(onRecord(40)))
  record().props.onPointerUp(pointer(onRecord(40)))
  runFrames(3)
  draw()
  check('a flick: coming back to speed, the deck shows where it is', previews.at(-1)?.how, 'deck')
  const handle = () => view.find(byClass('app-tt-handle'))[0]
  handle().props.onPointerDown(pointer(tt.needleAt(player.at, LENGTH)))
  draw()
  check('the arm taken while the record coasts: the record\'s sound stops', port.filter((m) => m.type === 'stop').length > stops, true)
  check('...and the time line says Needle up, over the song, no longer the coast', previews.at(-1), { how: 'arm', time: null })
  const toEnd = reachAt(tt.armAngle(LENGTH, LENGTH) + 10)
  handle().props.onPointerMove(pointer(toEnd))
  runFrames(3)
  draw()
  check('...dragged while the record is still coming back to speed: the arm, its value and the time line follow the finger',
    [previews.at(-1)?.how, near(previews.at(-1)?.time ?? 0, LENGTH), handle().props['aria-valuenow'],
      view.find(byClass('app-tt-arm'))[0].props.transform], ['arm', true, LENGTH, `rotate(${+tt.armAngle(LENGTH, LENGTH).toFixed(3)} ${ARM.x} ${ARM.y})`])
  player.seeks.length = 0
  handle().props.onPointerUp(pointer(toEnd))
  check('...let go: sought where the arm was shown', player.seeks, [LENGTH])
  advance(3000)
  draw()

  //? review of 2.0.0-player.40: a quick grab of a playing record, frames drawn through the slop - a slow start, its
  //? crossing 96 and 240 ms after the press: the face as drawn (the hand's turn round the deck's face) carries
  //? straight on at the crossing - from the last frame, only the platter's own turn since (as first built, it
  //? stepped back by the platter's run under the slop, 14 and 43 degrees here; before .40, on by the hand's
  //? turn in the slop, 5)
  {
    const angleOf = (node) => Number(/rotate\(([-\d.]+)deg\)/.exec(node?.props?.style?.transform ?? node?.element?.style?.transform ?? '')?.[1] ?? 0)
    const drawnFace = () => angleOf(view.find(byClass('app-tt-turn'))[0]) + angleOf({ element: view.find(byClass('app-tt-face'))[0].element })
    const steps = []
    for (const slopMs of [96, 240]) {
      //? the song back where its window is, playing, the record's sound ready (a press the deck's)
      player.at = 151
      if (!player.playing) player.toggle()
      draw()
      await settle()
      draw()
      runFrames(5)
      draw()
      record().props.onPointerDown(pointer(onRecord(0)))
      draw()
      let t = 0
      while (t + 16 < slopMs) {
        runFrames(1)
        t += 16
        player.at += 0.016
        record().props.onPointerMove(pointer(onRecord((4 * t) / slopMs)))
        draw()
      }
      const before = drawnFace()
      advance(slopMs - t)
      player.at += (slopMs - t) / 1000
      //? 5 degrees at a radius of 100: 8.7 px from the press, past the slop
      record().props.onPointerMove(pointer(onRecord(5)))
      draw()
      runFrames(1)
      draw()
      steps.push([player.toggles.at(-1), Math.round((drawnFace() - before - ((360 / tt.SECONDS_PER_TURN) * (slopMs - t)) / 1000) * 100) / 100])
      record().props.onPointerUp(pointer(onRecord(5)))
      record().props.onLostPointerCapture(pointer(onRecord(5)))
      draw()
      advance(3000)
      draw()
    }
    if (!player.playing) player.toggle()
    draw()
    check('a quick grab of a playing record, a slow start crossing the slop 96 and 240 ms after the press, frames drawn through it: taken (the song paused there), and the face as drawn carries straight on - its step at the crossing the platter\'s own turn since the last frame, no more', steps, [['pause', 0], ['pause', 0]])
  }

  //? a hi-res song under "Up to 48 kHz": its window asked at the cap the song is played at, so it is cut
  //? from the very copy the phone plays (its rate, its level)
  player.track = { id: 'hires', title: 'Shine On', coverArt: 'cover-wywh', albumId: 'wywh', suffix: 'flac', sampleRate: 192000, bitDepth: 24 }
  player.maxRate = '48000'
  draw()
  await settle()
  check('a hi-res song played resampled: the turntable asks for its window at the same cap', /\/scrub\/hires\?.*&max_rate=48000$/.test(windowsAsked.at(-1)), true)
  player.maxRate = 'original'
  player.track = { ...player.track, id: 'hires-as-is' }
  draw()
  await settle()
  check('...played as it is ("Original"): asked as it is', /\/scrub\/hires-as-is\?at=\d+&seconds=40$/.test(windowsAsked.at(-1)), true)

  view.unmount()
  check('gone: the audio context closed', contexts[0].calls.at(-1), 'close')
}

/* ===== Now Playing's two looks ===== */

const { NowPlaying } = require(path.join(OUT, 'player/NowPlaying.js'))
const api = require(path.join(OUT, 'player/api.js'))

console.log('\nNow Playing opens as the setting says; the button switches it while it is open')
{
  const player = {
    ...fakePlayer(), buffering: false, error: null, airplay: false, gapless: false,
    previous() {}, next() {}, showAirPlay() {},
    track: { id: 'd2t3', title: 'Wish You Were Here (Live at Wembley)', artist: 'Pink Floyd', album: 'Wish You Were Here', albumId: 'wywh', coverArt: 'cover-wywh', duration: 308 },
  }
  //? the album the queue was played from, as the album page remembers it in the tap
  api.rememberPlayed({ id: 'wywh', name: 'Wish You Were Here', song: [{ id: 'd1t1', discNumber: 1 }, { id: 'd2t3', discNumber: 2 }] })
  const view = mount(NowPlaying, 'now playing')
  const draw = (open, openAs = 'cover') => view.render({
    player, open, covered: false, opener: { current: null }, onClose() {}, onMore() {}, onAlbum() {}, openAs,
  })
  const button = () => view.find(byClass('app-look-button'))[0]
  const grip = () => view.find(byClass('pl-sheet-grip'))[0]
  const turntable = () => view.find(named('Turntable'))[0]
  const looks = () => [button().props['aria-label'], !!turntable(), !!view.find(named('Scrubber'))[0], !!view.find(named('TurntableTime'))[0]]

  draw(false)
  draw(true)
  draw(true)
  check('the cover: the button offers the turntable, the bar is there', looks(), ['Show as a turntable', false, true, false])
  check('...its icon a record', view.find((node) => byClass('app-look-face')(node))[0].props.children.type.name, 'RecordIcon')
  button().props.onClick()
  draw(true)
  check('pressed: the turntable, the time line in the bar\'s place, the button back to the cover', looks(), ['Show the cover', true, false, true])
  check('...its icon a square', view.find((node) => byClass('app-look-face')(node))[0].props.children.type.name, 'SquareIcon')
  check('the record and the arm are not in the grip the sheet is dragged by',
    [view.find(named('Turntable'), grip()).length, hasClass(grip(), 'app-grip-top'), view.find(byClass('app-look-button'), grip()).length], [0, true, 1])
  check('the playing song\'s disc of the album it was played from', turntable().props.discArt, '/deadwax/library/disc_art/navidrome?album=wywh&disc=2')
  //? the speed fader (2.0.0-player.39): Now Playing hands the turntable its player for the fader; the chip
  //? sits in the icon row on either look (app.css shows it on the turntable only on a phone on its side)
  check('the turntable handed the player for its speed fader; the speed\'s chip first in the icon row, outside the grip',
    [turntable().props.fader === player, view.find(byClass('pl-sheet-footer'))[0].props.children[0].type.name, view.find(named('SpeedChip'), grip()).length], [true, 'SpeedChip', 0])
  turntable().props.onPreview({ time: 90, how: 'arm' })
  draw(true)
  check('...and the time line shows what the turntable previews', view.find(named('TurntableTime'))[0].props.previewing, { time: 90, how: 'arm' })
  turntable().props.onPreview(null)
  draw(true)

  draw(false)
  draw(true)
  draw(true)
  check('closed and opened again: as the setting says, not as the button left it', looks(), ['Show as a turntable', false, true, false])
  draw(false, 'turntable')
  draw(true, 'turntable')
  draw(true, 'turntable')
  check('set to the turntable: it opens as one', looks(), ['Show the cover', true, false, true])
  //? set to the turntable, a close leaves it mounted - what makes it look for the CD art again is
  //? being told the sheet opened (checked on the turntable itself above)
  draw(false, 'turntable')
  const closed = turntable()?.props.open
  draw(true, 'turntable')
  check('...and it stays drawn across a close, told it is closed and then open again', [closed, turntable()?.props.open], [false, true])
  button().props.onClick()
  draw(true, 'turntable')
  check('...and the button still switches it', looks(), ['Show as a turntable', false, true, false])
  check('...the cover\'s icon row keeps the speed\'s chip at its start', view.find(byClass('pl-sheet-footer'))[0].props.children[0].type.name, 'SpeedChip')
  const nowPlaying = fs.readFileSync(path.join(UI, 'src/player/NowPlaying.tsx'), 'utf8')
  check('the button leaves the setting alone: Now Playing has no way to change it', /onOpensAs|writePlayerOpensAs|setOpensAs/.test(nowPlaying), false)

  //? the turntable's pause from the transport winds down as the record's tap does (2.0.0-player.14);
  //? the cover's is always the plain toggle
  const transport = () => view.find(byClass('pl-transport-button'))[1]
  draw(false)
  draw(true, 'cover')
  draw(true, 'cover')
  const seeksBefore = player.seeks.length
  const togglesBefore = player.toggles
  transport().props.onClick()
  check('on the cover, the transport\'s pause is the plain toggle, nothing sought', [player.toggles - togglesBefore, player.seeks.length - seeksBefore], [1, 0])
  view.render({ player, open: true, covered: false, opener: { current: null }, onClose() {}, onMore() {}, onAlbum() {}, openAs: 'turntable', windDown: false })
  view.render({ player, open: true, covered: false, opener: { current: null }, onClose() {}, onMore() {}, onAlbum() {}, openAs: 'turntable', windDown: false })
  button().props.onClick()
  view.render({ player, open: true, covered: false, opener: { current: null }, onClose() {}, onMore() {}, onAlbum() {}, openAs: 'turntable', windDown: false })
  check('the turntable is handed You\'s "Pause winds the record down", and a place to put its deck', [turntable()?.props.windDown, typeof turntable()?.props.deck], [false, 'object'])
  //? the deck as the turntable hands it: its pause says where the wind-down stops
  turntable().props.deck.current = { pausing: () => 200.3 }
  transport().props.onClick()
  check('on the turntable, the transport\'s pause asks the deck, pauses in the tap, and seeks where the wind-down stops',
    [player.toggles - togglesBefore, player.seeks.slice(seeksBefore)], [2, [200.3]])
  turntable().props.deck.current = { pausing: () => null }
  transport().props.onClick()
  check('...a plain pause when the deck says so: nothing sought', [player.toggles - togglesBefore, player.seeks.slice(seeksBefore)], [3, [200.3]])
  //? and its play while the record coasts or winds down: from where the record is, sought in the tap first
  player.playing = false
  turntable().props.deck.current = { resuming: () => 199.9 }
  transport().props.onClick()
  check('on the turntable, the transport\'s play mid wind-down: sought to where the record is, then played',
    [player.toggles - togglesBefore, player.seeks.slice(seeksBefore)], [4, [200.3, 199.9]])
  turntable().props.deck.current = { resuming: () => null }
  transport().props.onClick()
  check('...nothing sought when the deck says so', [player.toggles - togglesBefore, player.seeks.slice(seeksBefore)], [5, [200.3, 199.9]])
  player.playing = true
}

liveChecks().then(() => {
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}, (error) => {
  console.error(error)
  process.exit(1)
})
