/**
 * The speed fader (2.0.0-player.39): the player's speed, 0.25x to 2x, the pitch moving with it - lib/
 * playSpeed.ts (the numbers, the words, the fader's maths and its place on the plinth, what Debug reads),
 * the speed kept on the device (state/persisted.ts), the engine's wall-clock rules at 0.25x and 2x, the
 * fader and the chip rendered by a small stand-in for Preact (the turntable sim's), and the visualizer's
 * silent copy against a fake audio context. The engine itself is ui/test/player.sim.cjs's; the motor
 * and the deck at the speed are ui/test/deck.sim.cjs's; who may set it, ui/test/app-rules.sim.cjs's.
 *
 * What it pins:
 *  - THE RANGE: 0.25 to 2, in hundredths; held to it, 1x for what isn't a number; the detent within 2%.
 *  - THE FADER'S MATHS: by octaves (0.25, 0.5, 1, 2 a third of the way apart, 1x two thirds up), its
 *    inverse; keys a hundredth, a tenth, Home 0.25, End 2 - past the detent; a drag that takes hold only
 *    past a tap's few pixels, from where the speed is then (no jump), up faster, held to the ends,
 *    through the detent, another pointer changing nothing; the words ("1.25x", "1.25 times", "normal
 *    speed").
 *  - ITS PLACE: on the plinth, beside the platter - the knob's whole travel clear of the platter, of
 *    the arm's whole sweep and of the plinth's edge, and the readout clear of the platter.
 *  - THE STORED SPEED: a number 0.25 to 2, else 1 - storage that throws included.
 *  - WALL CLOCK AGAINST SONG TIME at 0.25x and 2x: the listening a step adds (and what the rate stops a
 *    missed seek adding), a change's back-dating, a join's split and its stall, the seek judged at a
 *    song's end.
 *  - WHAT DEBUG READS: the pitch switch by its name (the standard one, else a prefixed one), held only at
 *    1x; the measured pace over its window.
 *  - THE FADER RENDERED: a vertical slider, its value and words; a drag live - each move a setSpeed -
 *    nothing before a tap's few pixels, the pointer captured, a second finger nothing, measured in its
 *    own box; the detent; the readout's tap back to exactly 1x; the keys; the limits; the knob and the
 *    1x mark drawn where the maths says.
 *  - THE CHIP RENDERED: nothing at 1x; "1.25x" otherwise, named for what a tap does, which is 1x.
 *  - THE VISUALIZER'S COPY (player/vizAudio.ts against a fake audio context): started at the speed,
 *    never re-synced while the song plays at it, a change of speed carried on in place.
 *
 * Run it with:  node ui/test/playspeed.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-playspeed-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/playSpeed.ts', 'src/state/persisted.ts', 'src/lib/playQueue.ts', 'src/lib/gapless.ts', 'src/lib/scrub.ts',
  'src/lib/streamPlan.ts', 'src/player/SpeedFader.tsx', 'src/player/SpeedChip.tsx', 'src/player/vizAudio.ts',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor, as Preact's are - the turntable sim's stand-in. Effects
//? run after a render whose deps changed.
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
  render.unmount = () => { for (const s of root.slots) if (s && typeof s.cleanup === 'function') s.cleanup() }
  return render
}
`)

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
const round = (value, places = 4) => Math.round(value * 10 ** places) / 10 ** places
const define = (name, value) => Object.defineProperty(globalThis, name, { value, configurable: true, writable: true })

//? storage the page can read and write - or one that throws on every access, as a private window's can
const storage = new Map()
let storageThrows = false
define('localStorage', {
  getItem: (key) => { if (storageThrows) throw new Error('SecurityError'); return storage.get(key) ?? null },
  setItem: (key, value) => { if (storageThrows) throw new Error('QuotaExceededError'); storage.set(key, String(value)) },
  removeItem: (key) => storage.delete(key),
})
if (!('window' in globalThis)) define('window', globalThis)

const speedLib = require(path.join(OUT, 'lib/playSpeed.js'))
const {
  SPEED_MIN, SPEED_MAX, SPEED_NORMAL, SPEED_DETENT, SPEED_STEP, SPEED_PAGE, FADER, READOUT, roundSpeed, isSpeed, clampSpeed, detent,
  faderShare, speedAt, speedLabel, speedWords, speedKey, faderStart, faderMove, faderEnd, faderTravel, knobTop, pitchSwitch, pitchHeldAt,
  faderTarget, FADER_FROM,
  paceStep, paceOf, PACE_WINDOW_S, PACE_MIN_S,
} = speedLib
const tt = require(path.join(OUT, 'lib/turntable.js'))
const { STAGE, PLATTER, RECORD, ARM, ARM_PARTS, TAP_SLOP_PX } = tt

/* ===== the numbers ===== */

console.log('\nthe range: 0.25x to 2x, in hundredths')
check('0.25 to 2, 1 the song as it is, the detent 2%, keys a hundredth and a tenth', [SPEED_MIN, SPEED_MAX, SPEED_NORMAL, SPEED_DETENT, SPEED_STEP, SPEED_PAGE], [0.25, 2, 1, 0.02, 0.01, 0.1])
check('in hundredths', [roundSpeed(1.234), roundSpeed(1.235), roundSpeed(0.999)], [1.23, 1.24, 1])
check('a speed is a number from 0.25 to 2, the ends included', [0.25, 2, 1, 0.249, 2.001, NaN, Infinity, '1', null].map(isSpeed), [true, true, true, false, false, false, false, false, false])
check('held to the range; not a number is 1x', [clampSpeed(5), clampSpeed(0.1), clampSpeed(-3), clampSpeed(NaN), clampSpeed(Infinity), clampSpeed(1.567)], [2, 0.25, 0.25, 1, 1, 1.57])
check('the detent: within 2% of 1x is 1x, further is itself', [detent(1.02), detent(0.98), detent(1.021), detent(0.979), detent(1.5)], [1, 1, 1.021, 0.979, 1.5])

console.log('\nthe fader: by octaves, 1x two thirds of the way up')
check('0.25x at the bottom, 0.5x a third up, 1x two thirds, 2x at the top', [0.25, 0.5, 1, 2].map((s) => round(faderShare(s), 6)), [0, round(1 / 3, 6), round(2 / 3, 6), 1])
check('...and back: each share its speed, through the detent', [0, 1 / 3, 2 / 3, 1, 0.7, 0.67].map(speedAt), [0.25, 0.5, 1, 2, 1.07, 1])
check('held to its ends', [speedAt(-0.5), speedAt(1.5), faderShare(9), faderShare(0)], [0.25, 2, 1, 0])
check('the knob on the stage for a speed: the slot\'s top at 2x, its bottom at 0.25x', [knobTop(2), knobTop(0.25), knobTop(1)],
  [`${round(FADER.top / STAGE.height * 100)}%`, `${round(FADER.bottom / STAGE.height * 100)}%`, `${round((FADER.bottom - (2 / 3) * (FADER.bottom - FADER.top)) / STAGE.height * 100)}%`])
check('the travel on screen, for a stage of a given height', [round(faderTravel(STAGE.height), 3), round(faderTravel(STAGE.height / 2), 3)], [FADER.bottom - FADER.top, (FADER.bottom - FADER.top) / 2])

console.log('\nthe words')
check('the readout and the chip: two places, always', [1, 1.25, 0.5, 2, 0.25, 1.234].map(speedLabel), ['1.00x', '1.25x', '0.50x', '2.00x', '0.25x', '1.23x'])
check('a screen reader\'s: normal speed, or so many times', [1, 1.25, 0.5, 2, 0.25].map(speedWords), ['normal speed', '1.25 times', '0.5 times', '2 times', '0.25 times'])

console.log('\nthe keys: a hundredth, a tenth, the ends - and past the detent')
check('arrows up and right faster, down and left slower, a hundredth', ['ArrowUp', 'ArrowRight', 'ArrowDown', 'ArrowLeft'].map((key) => speedKey(key, 1)), [1.01, 1.01, 0.99, 0.99])
check('Page Up and Page Down a tenth; Home the slowest, End the fastest', ['PageUp', 'PageDown', 'Home', 'End'].map((key) => speedKey(key, 1.25)), [1.35, 1.15, 0.25, 2])
check('held to the ends; another key is not the fader\'s', [speedKey('ArrowUp', 2), speedKey('ArrowDown', 0.25), speedKey('PageDown', 0.3), speedKey('Enter', 1), speedKey('a', 1)], [2, 0.25, 0.25, null, null])

console.log('\na finger on the fader: a tap\'s few pixels first, from where the speed is, up faster')
{
  const TRAVEL = 168
  let drag = faderStart(7, 300)
  check('pressed: nothing yet', drag, { pointer: 7, y0: 300, from: null })
  let step = faderMove(drag, 7, 300 - (TAP_SLOP_PX - 1), TRAVEL, 1)
  check('a nudge short of a tap\'s few pixels: nothing changes - no jump, nothing taken', [step.drag === drag, step.speed], [true, null])
  step = faderMove(drag, 7, 300 - (TAP_SLOP_PX + 10), TRAVEL, 1.5)
  check('past them: taken at the slop\'s edge, from the speed as it is (1.5x) - 10 px up is 10/168 of the travel on from there, 1.7x',
    [step.drag.from.y, round(step.drag.from.share, 6), step.speed], [300 - TAP_SLOP_PX, round(faderShare(1.5), 6), speedAt(faderShare(1.5) + 10 / TRAVEL)])
  drag = step.drag
  check('up is faster, down slower - and held to the ends however far the finger goes',
    [faderMove(drag, 7, 300 - TAP_SLOP_PX - 40, TRAVEL, 1.5).speed > 1.5, faderMove(drag, 7, 300, TRAVEL, 1.5).speed < 1.5,
      faderMove(drag, 7, -2000, TRAVEL, 1.5).speed, faderMove(drag, 7, 4000, TRAVEL, 1.5).speed], [true, true, 2, 0.25])
  const toOne = 300 - TAP_SLOP_PX + (faderShare(1.5) - faderShare(1)) * TRAVEL
  check('the detent: the finger within 2% of 1x lands on 1x exactly - a pixel either side included',
    [faderMove(drag, 7, toOne, TRAVEL, 1.5).speed, faderMove(drag, 7, toOne - 1, TRAVEL, 1.5).speed, faderMove(drag, 7, toOne + 1, TRAVEL, 1.5).speed], [1, 1, 1])
  check('...and 3% off it is itself', faderMove(drag, 7, toOne - Math.log(1.03) / Math.log(8) * TRAVEL, TRAVEL, 1.5).speed, 1.03)
  check('another pointer changes nothing; nor a fader with no length', [faderMove(drag, 8, 0, TRAVEL, 1.5).speed, faderMove(drag, 7, 0, 0, 1.5).speed, faderMove(null, 7, 0, TRAVEL, 1).speed], [null, null, null])
  check('let go: over - but not by another pointer', [faderEnd(drag, 7), faderEnd(drag, 8) === drag, faderEnd(null, 7)], [null, true, null])
  const down = faderMove(faderStart(1, 100), 1, 100 + TAP_SLOP_PX + 5, TRAVEL, 1)
  check('taken going down: at the slop\'s edge below the press', [down.drag.from.y, down.speed], [100 + TAP_SLOP_PX, speedAt(faderShare(1) - 5 / TRAVEL)])
}

console.log('\nits place on the plinth: beside the platter, clear of the arm and the edge')
{
  const { knob } = FADER
  //? the platter's edge at a height, and how far right of it the knob's left side is - over its whole travel
  const platterEdge = (y) => PLATTER.x + Math.sqrt(Math.max(0, PLATTER.r ** 2 - (y - PLATTER.y) ** 2))
  let closest = Infinity
  for (let y = FADER.top - knob.height / 2; y <= FADER.bottom + knob.height / 2; y += 0.5) closest = Math.min(closest, FADER.x - knob.width / 2 - platterEdge(y))
  check('the knob never on the platter, over its whole travel - a few units of plinth between', [closest > 0, closest >= 2], [true, true])
  check('...nor off the plinth: its right side inside the edge, its travel inside the stage',
    [FADER.x + knob.width / 2 <= STAGE.width, FADER.top - knob.height / 2 > 0, FADER.bottom + knob.height / 2 < STAGE.height], [true, true, true])
  //? the arm over its whole sweep (the outer groove to the inner), its bar six units thick and its head
  //? 22: never as far right as the knob, at any height the knob travels
  let armRight = -Infinity
  for (const time of Array.from({ length: 21 }, (_, i) => i * 21.25)) {
    const angle = tt.armAngle(time, 425) * Math.PI / 180
    for (let along = 0; along <= ARM.reach + 20; along += 1) {
      const x = ARM.x + along * Math.cos(angle), y = ARM.y + along * Math.sin(angle)
      if (y >= FADER.top - knob.height / 2 && y <= FADER.bottom + knob.height / 2) armRight = Math.max(armRight, x + ARM_PARTS.head.thick / 2)
    }
  }
  check('the arm, over its whole sweep, never reaches the knob\'s side', armRight < FADER.x - knob.width / 2, true)
  const readoutTop = READOUT.y - 10
  //? the readout's face at a label's size is about 48 units wide and 20 tall ("1.00x" in 12px monospace,
  //? its padding and edge - the real page measured it): inside the plinth, clear of the platter
  check('the readout clear of the platter at the plinth\'s corner, under the fader, inside the plinth\'s edge',
    [READOUT.x - 24 > platterEdge(readoutTop), readoutTop > FADER.bottom + knob.height / 2, READOUT.y + 10 < STAGE.height, READOUT.x + 24 <= STAGE.width], [true, true, true, true])
  check('...and of the record', Math.hypot(READOUT.x - 24 - RECORD.x, readoutTop - RECORD.y) > RECORD.r, true)
  //? the fader's TARGET, not only its drawing, off the record (review of 2.0.0-player.39: centred on the
  //? slot, a 44px target covered 1.5-4 px of the record's rim on every phone, and took its taps and turns):
  //? at 44px and at the cap, on every plinth from a phone on its side to the widest, it starts right of
  //? the rim, holds the knob, and is the width app.css gives it
  const plinths = [45, 66, 120, 260, 300, 314, 316, 330, 346.8, 366, 390, 410, 440]
  const targets = plinths.map((stage) => faderTarget(stage))
  check('the fader\'s target never on the record, on any plinth - the record\'s rim and a unit more, or further',
    targets.filter(({ left }) => left < RECORD.x + RECORD.r + 1 - 1e-9).length, 0)
  check('...the knob inside it, on every one', targets.filter(({ left, right }) => left > FADER.x - knob.width / 2 || right < FADER.x + knob.width / 2).length, 0)
  check('...44px wide from a 315px plinth up, 14% of a smaller one', plinths.map((stage, i) => round((targets[i].right - targets[i].left) * stage / STAGE.width, 2)),
    plinths.map((stage) => round(Math.min(44, 0.14 * stage), 2)))
  check('...centred on the slot on a plinth wide enough (440px), from just past the rim on a phone\'s (366px)',
    [round(faderTarget(440).left + faderTarget(440).right, 6) === round(2 * FADER.x, 6), faderTarget(366).left, FADER_FROM], [true, FADER_FROM, 339])
  //? reaching past the plinth's right edge into the room round it (.app-tt's 12px), at most 17 px - the
  //? phone's own edge clips a few px of it on a 340-375px phone
  check('...past the plinth\'s edge by at most 17 px', round(Math.max(...plinths.map((stage, i) => (targets[i].right - STAGE.width) * stage / STAGE.width)), 1) <= 17, true)
}

console.log('\nwhat Debug reads: the pitch switch by its name, held only at 1x; the pace measured')
{
  check('the standard name where it is; a prefixed one only where that is all there is; none',
    [pitchSwitch((n) => ['preservesPitch', 'webkitPreservesPitch'].includes(n)), pitchSwitch((n) => n === 'webkitPreservesPitch'), pitchSwitch((n) => n === 'mozPreservesPitch'), pitchSwitch(() => false)],
    ['preservesPitch', 'webkitPreservesPitch', 'mozPreservesPitch', null])
  check('the switch held at 1x - the browser\'s own default - and let go at every other speed', [1, 0.25, 0.99, 1.01, 2].map(pitchHeldAt), [true, false, false, false, false])
  let window = []
  for (let i = 0; i < 4; i++) window = paceStep(window, { media: 0.375, wall: 0.25 })
  check('under PACE_MIN_S of playing: nothing said', [PACE_MIN_S, PACE_WINDOW_S, paceOf(window)], [2, 8, null])
  for (let i = 0; i < 60; i++) window = paceStep(window, { media: 0.375, wall: 0.25 })
  check('...then the song\'s seconds over the page\'s, over the last PACE_WINDOW_S only', [round(paceOf(window), 6), round(window.reduce((sum, s) => sum + s.wall, 0), 6)], [1.5, 8])
  for (let i = 0; i < 40; i++) window = paceStep(window, { media: 0.0625, wall: 0.25 })
  check('...so a new pace replaces the old within the window', round(paceOf(window), 6), 0.25)
  check('a step of no time, or backwards, is left out', [paceStep([], { media: 1, wall: 0 }).length, paceStep([], { media: -1, wall: 0.25 }).length], [0, 0])
}

/* ===== the stored speed ===== */

console.log('\nthe stored speed: a number from 0.25 to 2, else 1')
{
  const persisted = require(path.join(OUT, 'state/persisted.js'))
  const read = (value) => {
    storage.clear()
    if (value !== undefined) storage.set('deadwax-player-speed', value)
    return persisted.readPlayerSpeed()
  }
  check('its key', persisted.STORAGE_KEYS.playerSpeed, 'deadwax-player-speed')
  check('a number from 0.25 to 2, in hundredths', ['1.5', '0.25', '2', '1.234', '0.75'].map(read), [1.5, 0.25, 2, 1.23, 0.75])
  check('anything else is 1: nothing, a word, 0, 3, 0.2, -1, empty, spaces, NaN', [undefined, 'fast', '0', '3', '0.2', '-1', '', '   ', 'NaN'].map(read), [1, 1, 1, 1, 1, 1, 1, 1, 1])
  storage.clear()
  persisted.writePlayerSpeed(1.25)
  check('written as its number', storage.get('deadwax-player-speed'), '1.25')
  storageThrows = true
  let threw = false
  try {
    check('storage that throws: read as 1, and a write is skipped, never thrown', [persisted.readPlayerSpeed(), persisted.writePlayerSpeed(0.5)], [1, undefined])
  } catch {
    threw = true
  }
  storageThrows = false
  check('...nothing thrown', threw, false)
}

/* ===== the engine's wall-clock rules at 0.25x and 2x ===== */

console.log('\nwall clock against song time: every rule takes the element\'s rate, at 0.25x and at 2x')
{
  const { listenedStep } = require(path.join(OUT, 'lib/playQueue.js'))
  const { clockStep, startChange } = require(path.join(OUT, 'lib/gapless.js'))
  const { seekStep } = require(path.join(OUT, 'lib/scrub.js'))
  const { splitAcrossJoin, joinStallMs } = require(path.join(OUT, 'lib/streamPlan.js'))
  //? a locked phone sends its updates far apart: four seconds of the page's clock between two
  check('the listening a step adds: all of it at 2x (8 s of song in 4 s) and at 0.25x (1 s in 4 s)',
    [listenedStep({ previous: 10, now: 18, elapsed: 4, rate: 2, seeked: false }), listenedStep({ previous: 10, now: 11, elapsed: 4, rate: 0.25, seeked: false })], [8, 1])
  check('...and a jump the seek flag missed adds no more than the time at that pace: 4 s at 0.25x is 1.5 s at most, at 2x 8.5',
    [listenedStep({ previous: 10, now: 100, elapsed: 4, rate: 0.25, seeked: false }), listenedStep({ previous: 10, now: 100, elapsed: 4, rate: 2, seeked: false })], [1.5, 8.5])
  const change = startChange(1000, { kind: 'handover', source: 'memory' }, 4, 0)
  check('a song change back-dated by the clock: 0.5 s of song at 2x is 250 ms, at 0.25x 0.0625 s is 250 ms',
    [clockStep(change, { position: 0.5, at: 1300, playbackRate: 2, seeked: false }).reading.ms, clockStep(change, { position: 0.0625, at: 1300, playbackRate: 0.25, seeked: false }).reading.ms], [50, 50])
  check('a join\'s listening split at 2x: all of it when the clock allows (1 s of the old song and 1 of the new in 1 s)',
    splitAcrossJoin({ previous: 9, oldLength: 10, now: 1, elapsed: 1, rate: 2, seeked: false }), { before: 1, after: 1 })
  check('...at 0.25x, no more than the clock allows: 1 s of page clock is 0.75 s with the slack',
    splitAcrossJoin({ previous: 9, oldLength: 10, now: 1, elapsed: 1, rate: 0.25, seeked: false }), { before: 0.75, after: 0 })
  check('a join\'s stall: none when the media moved as fast as the clock at its rate', [joinStallMs({ elapsedMs: 250, media: 0.5, rate: 2 }), joinStallMs({ elapsedMs: 250, media: 0.0625, rate: 0.25 }), joinStallMs({ elapsedMs: 500, media: 0.0625, rate: 0.25 })], [0, 0, 250])
  //? the seek judged at a song's end: the song played on 7 s of SONG past its clock - 3.5 s at 2x, 28 s at 0.25x
  const judged = (rate, wall) => {
    let reading = seekStep(null, { kind: 'asked', asked: 10, length: 20, track: 's' })
    reading = seekStep(reading, { kind: 'seeked', position: 10 })
    reading = seekStep(reading, { kind: 'clock', position: 20, at: 1000 })
    return seekStep(reading, { kind: 'ended', position: 20, at: 1000 + wall, rate }).off
  }
  check('a seek\'s landing judged at the song\'s end: 7 s of song played on, whatever the speed', [judged(2, 3500), judged(0.25, 28000), judged(1, 7000)], [-7, -7, -7])
}

/* ===== the fader and the chip, rendered ===== */

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
function mount(component) {
  const render = hooks.root(component)
  let tree = null
  const find = (test) => {
    const hits = []
    const visit = (node) => {
      if (!node || typeof node !== 'object') return
      if (Array.isArray(node)) { node.forEach(visit); return }
      if (test(node)) hits.push(node)
      visit(node.props?.children)
    }
    visit(tree)
    return hits
  }
  return {
    render(props) { tree = render(props); render.commit(); return tree },
    unmount: () => render.unmount(),
    find,
    get tree() { return tree },
  }
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)

//? the player as the fader and the chip see it: the speed, who is told of it, and every setSpeed
function fakePlayer(start = 1) {
  const listeners = new Set()
  const player = {
    now: start, sets: [],
    speed: () => player.now,
    onSpeed(listener) { listeners.add(listener); return () => listeners.delete(listener) },
    setSpeed(speed) {
      player.sets.push(speed)
      const next = clampSpeed(speed)
      if (next === player.now) return
      player.now = next
      listeners.forEach((listener) => listener(next))
    },
  }
  return player
}
//? the fader's box on screen: the knob's whole travel and a knob's height, at the board's own size
const SPAN = FADER.bottom - FADER.top + FADER.knob.height
const box = { height: SPAN, top: 100, left: 300, width: 44 }
const pointer = (y, extra = {}) => ({
  pointerId: 1, isPrimary: true, pointerType: 'touch', button: 0, clientX: 320, clientY: y,
  currentTarget: { captured: null, setPointerCapture(id) { this.captured = id }, getBoundingClientRect: () => ({ ...box }) }, ...extra,
})

console.log('\nthe fader rendered: a vertical slider, live as it is dragged')
{
  const { SpeedFader } = require(path.join(OUT, 'player/SpeedFader.js'))
  const player = fakePlayer(1)
  const view = mount(SpeedFader)
  const draw = () => view.render({ player })
  draw()
  const fader = () => view.find(byClass('app-tt-fader'))[0]
  const readout = () => view.find(byClass('app-tt-readout'))[0]
  const knob = () => view.find(byClass('app-tt-fader-knob'))[0]
  const mark = () => view.find(byClass('app-tt-fader-mark'))[0]
  const aria = () => [fader().props['aria-valuenow'], fader().props['aria-valuetext']]
  check('a vertical slider named Speed, 0.25 to 2, in the tab order', [fader().props.role, fader().props['aria-label'], fader().props['aria-orientation'], fader().props['aria-valuemin'], fader().props['aria-valuemax'], fader().props.tabIndex],
    ['slider', 'Speed', 'vertical', 0.25, 2, 0])
  check('...at 1x: "normal speed", the readout "1.00x", plain, and the mark at 1x lit', [aria(), readout().props.children.props.children, readout().props.class, mark().props.class], [[1, 'normal speed'], '1.00x', 'app-tt-readout', 'app-tt-fader-mark is-on'])
  check('the knob drawn at 1x: two thirds up the slot', round(knob().props.children[0].props.y + FADER.knob.height / 2, 3), round(FADER.bottom - (2 / 3) * (FADER.bottom - FADER.top), 3))
  check('placed over the slot: its whole travel, a knob\'s height included - centred on it, never left of the record\'s rim',
    [fader().props.style['--app-tt-fader-x'], fader().props.style['--app-tt-fader-from'], fader().props.style.top, fader().props.style.height],
    [`${round(FADER.x / STAGE.width * 100)}%`, `${round(FADER_FROM / STAGE.width * 100)}%`, `${round((FADER.top - FADER.knob.height / 2) / STAGE.height * 100)}%`, `${round(SPAN / STAGE.height * 100)}%`])

  const down = pointer(300)
  fader().props.onPointerDown(down)
  draw()
  fader().props.onPointerMove(pointer(300 - (TAP_SLOP_PX - 2)))
  check('pressed and nudged: the pointer captured, and nothing set', [down.currentTarget.captured, player.sets], [1, []])
  fader().props.onPointerMove(pointer(300 - TAP_SLOP_PX - 20))
  draw()
  const first = player.now
  check('past a tap\'s few pixels: live - set as the finger moves, up faster, from where it was (no jump)', [player.sets.length, first > 1, first, fader().props.class],
    [1, true, speedAt(faderShare(1) + 20 / (FADER.bottom - FADER.top)), 'app-tt-fader is-held'])
  fader().props.onPointerMove(pointer(300 - TAP_SLOP_PX - 40))
  draw()
  check('...and again as it goes on', [player.sets.length, player.now > first], [2, true])
  fader().props.onPointerMove(pointer(300 - TAP_SLOP_PX - 40, { pointerId: 2 }))
  check('another finger moves nothing', player.sets.length, 2)
  fader().props.onPointerMove(pointer(300 - TAP_SLOP_PX + 1))
  draw()
  check('back to within 2% of 1x: the detent - exactly 1x', player.now, 1)
  fader().props.onPointerMove(pointer(-5000))
  draw()
  check('pushed past the top: 2x, and no further', [player.now, aria()], [2, [2, '2 times']])
  fader().props.onPointerMove(pointer(5000))
  draw()
  check('...past the bottom: 0.25x', [player.now, aria(), knob().props.children[0].props.y + FADER.knob.height / 2], [0.25, [0.25, '0.25 times'], FADER.bottom])
  fader().props.onPointerUp(pointer(5000))
  draw()
  const sets = player.sets.length
  fader().props.onPointerMove(pointer(0))
  check('let go: the drag is over - a move after it sets nothing', [player.sets.length - sets, fader().props.class], [0, 'app-tt-fader'])
  check('...off 1x: the readout purple, saying it, its mark unlit', [readout().props.class, readout().props.children.props.children, mark().props.class], ['app-tt-readout is-off', '0.25x', 'app-tt-fader-mark'])
  readout().props.onClick()
  draw()
  check('the readout\'s tap: back to exactly 1x in one', [player.sets.at(-1), player.now, aria()], [1, 1, [1, 'normal speed']])

  //? the keys
  const key = (name) => {
    let prevented = false
    fader().props.onKeyDown({ key: name, preventDefault: () => { prevented = true } })
    draw()
    return [player.now, prevented]
  }
  check('keys: an arrow up a hundredth - past the detent - Page Up a tenth, End 2x, Home 0.25x, down and left',
    [key('ArrowUp'), key('PageUp'), key('End'), key('ArrowDown'), key('Home'), key('ArrowRight'), key('PageDown'), key('ArrowLeft')],
    [[1.01, true], [1.11, true], [2, true], [1.99, true], [0.25, true], [0.26, true], [0.25, true], [0.25, true]])
  check('...another key is left to the browser', key('Tab'), [0.25, false])

  //? a mouse's other buttons and a second finger start nothing; capture lost ends the drag
  const sets2 = player.sets.length
  fader().props.onPointerDown(pointer(300, { pointerType: 'mouse', button: 2 }))
  fader().props.onPointerMove(pointer(100, { pointerType: 'mouse', button: 2 }))
  fader().props.onPointerDown(pointer(300, { isPrimary: false, pointerId: 5 }))
  fader().props.onPointerMove(pointer(100, { pointerId: 5 }))
  check('a right-click, or a second finger: nothing started, nothing set', player.sets.length - sets2, 0)
  fader().props.onPointerDown(pointer(300))
  fader().props.onPointerMove(pointer(250))
  fader().props.onLostPointerCapture(pointer(250))
  const sets3 = player.sets.length
  fader().props.onPointerMove(pointer(200))
  check('capture lost: the drag is over', player.sets.length - sets3, 0)

  //? measured in its own box as the press found it: half the size on screen, twice the speed of change
  box.height = SPAN / 2
  player.now = 1
  draw()
  fader().props.onPointerDown(pointer(300))
  fader().props.onPointerMove(pointer(300 - TAP_SLOP_PX - 10))
  check('a fader half the size: 10 px up is twice as far up its travel', player.now, speedAt(faderShare(1) + 20 / (FADER.bottom - FADER.top)))
  fader().props.onPointerUp(pointer(0))
  box.height = SPAN
  view.unmount()
}

console.log('\nthe chip rendered: nothing at 1x; "1.25x", and a tap back to 1x')
{
  const { SpeedChip } = require(path.join(OUT, 'player/SpeedChip.js'))
  const player = fakePlayer(1)
  const view = mount(SpeedChip)
  check('at 1x: nothing at all', view.render({ player }), null)
  player.setSpeed(1.25)
  const chip = view.render({ player })
  check('off 1x: a button saying it, its name starting with what it shows (label in name), then what a tap does',
    [chip.type, chip.props.class, chip.props.children.props.children, chip.props['aria-label']],
    ['button', 'app-speed-chip', '1.25x', '1.25x, 1.25 times the song\'s speed: back to normal speed'])
  //? the button as a tap finds it: in its row, the next button after it, and whether it has focus
  const row = (focused) => {
    const doc = { activeElement: null }
    const next = { focused: false, focus() { this.focused = true; doc.activeElement = this } }
    const button = { ownerDocument: doc, nextElementSibling: next }
    if (focused) doc.activeElement = button
    return { button, next, doc }
  }
  const tapped = row(false)
  chip.props.onClick({ currentTarget: tapped.button })
  check('its tap (a finger\'s, no focus on it): back to exactly 1x - and gone, focus moved nowhere', [player.sets.at(-1), player.now, view.render({ player }), tapped.next.focused, tapped.doc.activeElement], [1, 1, null, false, null])
  player.setSpeed(0.5)
  const keyed = row(true)
  view.render({ player }).props.onClick({ currentTarget: keyed.button })
  check('...pressed with focus on it (a keyboard, VoiceOver): focus on to the next button in its row, which stays - never the page',
    [player.now, view.render({ player }), keyed.next.focused, keyed.doc.activeElement === keyed.next], [1, null, true, true])
  view.unmount()
}

/* ===== the visualizer's silent copy, against a fake audio context ===== */

async function visualizer() {
  console.log('\nthe visualizer\'s copy: at the speed, never re-synced for it, a change carried on in place')
  let contextTime = 0
  const nodes = []
  class FakeParam { constructor(value) { this.value = value } }
  class FakeContext {
    constructor() { this.state = 'suspended'; this.sampleRate = 48000; this.destination = {} }
    get currentTime() { return contextTime }
    resume() { this.state = 'running'; return Promise.resolve() }
    suspend() { this.state = 'suspended'; return Promise.resolve() }
    close() { this.state = 'closed'; return Promise.resolve() }
    createAnalyser() { return { fftSize: 0, frequencyBinCount: 1024, smoothingTimeConstant: 0, minDecibels: 0, maxDecibels: 0, connect() {}, disconnect() {} } }
    createGain() { return { gain: new FakeParam(1), connect() {}, disconnect() {} } }
    createBufferSource() {
      const node = { buffer: null, playbackRate: new FakeParam(1), onended: null, connect() {}, disconnect() {}, started: null, stopped: false,
        start(when, offset) { node.started = { when, offset, rate: node.playbackRate.value } }, stop() { node.stopped = true } }
      nodes.push(node)
      return node
    }
    decodeAudioData(bytes, done) { done({ duration: 40, length: 40 * 48000, sampleRate: 48000, numberOfChannels: 2, getChannelData: () => new Float32Array(1) }) }
  }
  define('AudioContext', FakeContext)
  define('fetch', async (address) => ({
    ok: true, status: 200,
    headers: { get: (name) => (name.toLowerCase() === 'x-deadwax-window' ? `${Math.round(Number(/at=([\d.]+)/.exec(address)[1]) * 44100)}/${40 * 44100}/44100` : null) },
    arrayBuffer: async () => new ArrayBuffer(8),
  }))
  const settle = () => new Promise((resolve) => setImmediate(resolve))
  const viz = require(path.join(OUT, 'player/vizAudio.js'))
  viz.wakeVisualizerAudio()
  await settle()
  const listener = new viz.VizListener(() => {})
  const song = { id: 's', length: 300, flac: true, maxRate: null }
  //? the song at 1.5x from 10 s: the window asked for, decoded, and the copy started at the playhead
  listener.tick(song, null, true, 10, 1.5)
  await settle(); await settle(); await settle()
  listener.tick(song, null, true, 10, 1.5)
  const started = nodes.filter((node) => node.started)
  check('started at the playhead, at the speed: its playbackRate 1.5', [started.length, started[0]?.started.rate, started[0]?.playbackRate.value, round(started[0]?.started.offset ?? -1, 3)], [1, 1.5, 1.5, 2])
  //? two seconds of the song at 1.5x: 3 s of it - the copy where the element is, never started again
  for (let frame = 1; frame <= 120; frame++) {
    contextTime = frame / 60
    listener.tick(song, null, true, 10 + 1.5 * frame / 60, 1.5)
  }
  check('2 s on, at 1.5x with the song: never re-synced (the drift rule has nothing to correct)', [nodes.filter((node) => node.started).length, nodes[0].stopped], [1, false])
  //? the speed changed to 0.5x: carried on in place - the same node, its rate changed - and still in time
  listener.tick(song, null, true, 13, 0.5)
  for (let frame = 121; frame <= 240; frame++) {
    contextTime = frame / 60
    listener.tick(song, null, true, 13 + 0.5 * (frame - 120) / 60, 0.5)
  }
  check('the speed changed to 0.5x: the same copy carried on at it, never started again', [nodes.filter((node) => node.started).length, nodes[0].playbackRate.value, nodes[0].stopped], [1, 0.5, false])
  //? a copy left at its old rate would drift a whole second a second at 1.5x: the next start would be at
  //? the playhead with the new rate - a seek is the way to see that start
  listener.tick(song, null, true, 30, 0.5)
  const again = nodes.filter((node) => node.started)
  check('...a seek starts it again where the element is, at the speed it plays at', [again.length, again.at(-1).started.rate, round(again.at(-1).started.offset, 3)], [2, 0.5, 22])
  listener.destroy()
  viz.closeVisualizerAudio()
}

visualizer().then(() => {
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}, (error) => {
  console.error(error)
  process.exit(1)
})
