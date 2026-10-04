/**
 * The record's sound follows the hand (2.0.0-player.24). James: "in theory, I should be able to rotate
 * the turntable at the same speed as it plays at, and it should play the song. but when i do, it doesn't
 * sound like anything". This plays the song - a 440 Hz tone - through the REAL page side: Turntable's
 * record button (rendered by the same stand-in for Preact as turntable.sim.cjs) given pointer events
 * with their own timeStamps (and getCoalescedEvents() in some runs), the real deck stamping each sample
 * through the real clock mapping (lib/deckClock.ts) and posting it, and the real voice (lib/deckVoice.ts)
 * rendering it - on an audio clock that steps as a browser's does, the worklet in bursts of the
 * hardware's render or the main-thread voice in blocks of 1024 - and listens to what comes out, cycle by
 * cycle (zero crossings), against a hand whose every moment is known.
 *
 * What it pins:
 *
 *  - THE SOUND IS THE SONG AT THE HAND'S SPEED: a hand at exactly 1x, 0.5x, 2x and backwards (-1x),
 *    touch samples 60 a second (120, coalesced, in some runs) delivered up to 3 ms either side of 4 ms
 *    late, half a pixel of jitter on each at 120 px from the spindle, with the audio's clock stepping
 *    5.8 ms (desktop Brave) and 21.3 ms (an iPhone), on the worklet and on the main thread: at least 90%
 *    of cycles within 3% of the hand's speed in the steady part, and the read position where the hand
 *    was HAND_DELAY_S before - within a few ms, plus the main thread's constant lag there. A hand that
 *    speeds up and slows down, and one that turns back and forth, followed within a few ms.
 *  - THE OLD WAY FAILS IN THE SAME HARNESS: the page side as it was before 2.0.0-player.24 - each sample
 *    timed when its handler ran, one drive a frame at the hand's speed over its last 40 ms taken at the
 *    frame's time, stamped with a fresh `currentTime` - into today's voice: nowhere near 90%.
 *  - WHAT TURNTABLE HANDS THE DECK: every sample a move carries - each of getCoalescedEvents(), in order
 *    - with its own time, never when the handler ran; the record taken at the time of the sample that
 *    crossed a tap's few pixels; and each sample reaching the voice as a 'hand' knot - no drive a frame.
 *  - THE PATH'S EDGES, in the voice itself: a hand that stops (it runs on EXTRAPOLATE_S, slows to
 *    still, and is silent), a sample that comes late (a short run-on, then caught up - never a
 *    run-away), a turn back (followed, the speed through zero continuous), the first samples after a
 *    take (no dip from the song's speed into the hand's), a press that rests (the record held where it
 *    was taken), a hand that rests and moves on, a release after a rest (nothing swung across the gap),
 *    the window's edge, a ring overrun by 240 samples a second, and samples out of order.
 *  - ITS REVIEW: harder hands - Gaussian jitter of 0.5 and 1 px, a grip 60 and 80 px from the spindle,
 *    whole-pixel positions - still at least 90% within 3%, the fit's lines kept by the jitter measured
 *    rather than a fixed threshold; a hand changing speed followed at 80%; letting go of a moving record
 *    0-30 ms after its last move with no stall (the plan from the last sample's moment), and 45-60 ms
 *    after with the sound still meanwhile and no swing back; letting go at 1x, the record's sound
 *    stopping HAND_DELAY_S short of where the song plays on; a coast caught by a sample older than its
 *    last frame resting where the hand caught it; and samples gone missing from a moving hand (a 50 ms
 *    gap) read as samples gone missing, not a rest.
 *  - THE CLOCK, from the deck: started again as its context's state changes, and its step in Debug - on
 *    the desktop's clock too, where it is only narrowed to 5.8 ms by a later reading and nothing else
 *    reports after it. Read on the deck's own timer while the turntable shows and its context runs, a
 *    still record too (every CLOCK_SETTLE_MS while it settles, then every CLOCK_TICK_MS; not while
 *    hidden). And the first grab of a still record after its context was suspended and resumed (second
 *    review of 2.0.0-player.24: nothing had read the clock since, and its young mapping jumped the grab's
 *    stamps 13-16 ms on an iPhone's clock, the sound 0.05x to 9x of the hand's): the mapping held steady
 *    from the take, the sound as any grab from still, and a press a second on finding it settled.
 *
 * Run it with:  node ui/test/decksound.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-decksound-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/player/Turntable.tsx', 'src/lib/deckClock.ts', 'src/lib/platter.ts', 'src/lib/deckVoice.ts', 'src/player/deck.ts', 'src/lib/turntable.ts',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor, as Preact's are - turntable.sim.cjs's stand-in
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
fs.writeFileSync(path.join(OUT, 'player/Cover.js'), 'exports.Cover = function Cover() { return null }\n')
fs.writeFileSync(path.join(OUT, 'player/usePlayer.js'), 'exports.usePosition = (player) => player.position()\n')

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
const round = (value, places = 3) => Math.round(value * 10 ** places) / 10 ** places
let seed = 23
const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648)

/* ===== a page: a document, the stage's box, a clock, frames and timers the run moves on ===== */

const BOX = { left: 0, top: 0, width: 372, height: 368 }
class FakeElement {
  constructor() { this.style = {} }
  getBoundingClientRect() { return { ...BOX, right: BOX.width, bottom: BOX.height } }
}
const define = (name, value) => Object.defineProperty(globalThis, name, { value, configurable: true, writable: true })
define('document', { visibilityState: 'visible', addEventListener() {}, removeEventListener() {} })
define('localStorage', { getItem: () => null, setItem: () => {}, removeItem: () => {} })

let real = 1000
let timers = []
let frames = []
let nextId = 1
define('performance', { now: () => real })
define('setTimeout', (run, ms = 0) => { const id = nextId++; timers.push({ id, at: real + ms, run }); return id })
define('clearTimeout', (id) => { timers = timers.filter((timer) => timer.id !== id) })
define('requestAnimationFrame', (run) => { const id = nextId++; frames.push({ id, run }); return id })
define('cancelAnimationFrame', (id) => { frames = frames.filter((frame) => frame.id !== id) })
define('matchMedia', () => ({ matches: false, addEventListener() {}, removeEventListener() {} }))
globalThis.URL.createObjectURL = () => 'blob:deck-voice'
const settle = async () => { for (let i = 0; i < 4; i++) await new Promise((resolve) => setImmediate(resolve)) }

/* ===== the audio: a clock that steps as a browser's does, and the two hosts ===== */

const voice = require(path.join(OUT, 'lib/deckVoice.js'))
const platter = require(path.join(OUT, 'lib/platter.js'))
const tt = require(path.join(OUT, 'lib/turntable.js'))
const deckModule = require(path.join(OUT, 'player/deck.js'))
const { Turntable } = require(path.join(OUT, 'player/Turntable.js'))
const DELAY = voice.HAND_DELAY_S

//? the run in progress: its audio clock and what came out of it
let world = null
const tones = new Map()
const toneAt = (rate) => {
  if (!tones.has(rate)) tones.set(rate, Float32Array.from({ length: 40 * rate }, (_, i) => 0.5 * Math.sin((2 * Math.PI * 440 * i) / rate)))
  return tones.get(rate)
}
const contexts = []
class FakeContext {
  constructor() {
    this.state = 'suspended'
    this.sampleRate = world.rate
    this.destination = { speakers: true }
    this.changes = []
    if (world.host === 'worklet') this.audioWorklet = { addModule: () => Promise.resolve() }
    contexts.push(this)
  }
  //? what the page reads: the frames the audio has rendered so far - a step at a time
  get currentTime() { return world.rendered / world.rate }
  addEventListener(name, listener) { if (name === 'statechange') this.changes.push(listener) }
  changed() { for (const listener of this.changes) listener() }
  //? suspended, the audio's clock stands still - no renders, currentTime where it stopped - and resumed,
  //? it runs on from there
  resume() {
    if (world.stoppedAt !== null && world.stoppedAt !== undefined) world.audio0 += real - world.stoppedAt
    world.stoppedAt = null
    this.state = 'running'
    this.changed()
    return Promise.resolve()
  }
  suspend() { if (this.state === 'running') world.stoppedAt = real; this.state = 'suspended'; this.changed(); return Promise.resolve() }
  close() { this.state = 'closed'; return Promise.resolve() }
  createScriptProcessor(size, inputs, outputs) {
    const node = { args: [size, inputs, outputs], onaudioprocess: null, connect() {}, disconnect() {} }
    world.script = node
    return node
  }
  decodeAudioData(bytes, done) {
    const tone = toneAt(world.rate)
    done({ numberOfChannels: 2, sampleRate: world.rate, length: tone.length, getChannelData: () => tone })
  }
}
class FakeNode {
  constructor() {
    this.port = { postMessage: (message) => { world.inbox.push(message); world.log?.push(message) }, onmessage: null }
    world.node = this
  }
  connect() {}
  disconnect() {}
}
define('fetch', async (url) => {
  const at = Number(new URL(String(url), 'http://x').searchParams.get('at'))
  const rate = world.rate
  return { ok: true, status: 200, headers: { get: (name) => (name === 'x-deadwax-window' ? `${Math.round(at * rate)}/${40 * rate}/${rate}` : null) }, arrayBuffer: async () => new ArrayBuffer(64) }
})
define('AudioContext', FakeContext)

//? the main-thread voice's renders, spied where deck.js reaches them, for where its read head is
const realRender = voice.renderVoice
voice.renderVoice = (state, outputs, frames, rate, now) => {
  realRender(state, outputs, frames, rate, now)
  if (world?.host === 'script') world.positions.push([now + frames / rate, state.pos])
}

/**
 * The hardware asks for `step` frames at a time - at the moment its clock reaches them, a little uneven.
 * The worklet renders them then, the messages posted since applied first, as of its `currentTime`; the
 * main-thread voice is asked for a block of 1024 each time the render passes 1024 more, to play a block
 * later (its `playbackTime`), a moment after on the main thread. What each renders is kept at the
 * context time it plays at.
 */
function burst() {
  const { rate, step } = world
  if (world.host === 'worklet') {
    for (const message of world.inbox.splice(0)) voice.voiceCommand(world.state, message, world.rendered / rate, rate)
    for (let q = 0; q < step; q += 128) {
      const now = world.rendered / rate
      const out = [new Float32Array(128), new Float32Array(128)]
      realRender(world.state, out, 128, rate, now)
      world.output.set(out[0], world.rendered)
      world.positions.push([now + 128 / rate, world.state.pos])
      const heard = voice.voiceReport(world.state, 128, rate, now, voice.REPORTS_PER_SECOND)
      if (heard) world.node?.port.onmessage?.({ data: heard })
      world.rendered += 128
    }
  } else {
    const before = world.rendered
    world.rendered += step
    for (let boundary = Math.ceil(before / 1024) * 1024; boundary < world.rendered; boundary += 1024) {
      const playbackTime = (boundary + 1024) / rate
      world.calls.push({ at: real + 0.5 + random(), playbackTime })
    }
  }
}
function scriptCall({ playbackTime }) {
  const script = world.script
  if (!script?.onaudioprocess) return
  const channels = [new Float32Array(1024), new Float32Array(1024)]
  script.onaudioprocess({ outputBuffer: { numberOfChannels: 2, length: 1024, getChannelData: (channel) => channels[channel] }, playbackTime })
  const at = Math.round(playbackTime * world.rate)
  if (at + 1024 <= world.output.length) world.output.set(channels[0], at)
}

/**
 * The page and the audio run together until page time `until`: frames every 16.7 ms, the audio's bursts,
 * the main thread's blocks, timers, and the pointer events `events` holds (each delivered at its `at`,
 * to the record's handler it names).
 */
async function runUntil(until, events = []) {
  let lastFrame = real
  while (real < until) {
    const nextBurst = world.stoppedAt != null ? Infinity : world.audio0 + (world.rendered / world.rate) * 1000 + world.jitter
    const due = Math.min(nextBurst, world.nextFrame, ...world.calls.map((call) => call.at), ...timers.map((timer) => timer.at), ...events.map((event) => event.at), until)
    real = Math.max(real, due)
    if (due === nextBurst) {
      burst()
      world.jitter = (random() - 0.5) * 0.4
      continue
    }
    const call = world.calls.find((one) => one.at <= real)
    if (call) {
      world.calls.splice(world.calls.indexOf(call), 1)
      scriptCall(call)
      continue
    }
    const timer = timers.find((one) => one.at <= real)
    if (timer) {
      timers = timers.filter((one) => one !== timer)
      timer.run()
      continue
    }
    const event = events.find((one) => one.at <= real)
    if (event) {
      events.splice(events.indexOf(event), 1)
      event.run()
      continue
    }
    if (due === world.nextFrame) {
      const now = frames
      frames = []
      for (const frame of now) frame.run(real)
      world.nextFrame += 1000 / 60
      if (real - lastFrame > 50) {
        lastFrame = real
        await settle()
      }
      continue
    }
  }
  await settle()
}

/* ===== the turntable, and a hand on it ===== */

function mount() {
  const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
  const render = hooks.root(Turntable)
  const elements = new Map()
  let tree = null
  const walk = (node, where) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach((child, i) => walk(child, `${where}.${i}`)); return }
    if (typeof node.type === 'string') {
      const key = `${where}:${node.type}`
      if (!elements.has(key)) elements.set(key, new FakeElement())
      node.element = elements.get(key)
      if (node.props.ref) node.props.ref.current = node.element
    }
    walk(node.props?.children, `${where}/`)
  }
  const find = (name) => {
    let hit = null
    const visit = (node) => {
      if (!node || typeof node !== 'object' || hit) return
      if (Array.isArray(node)) { node.forEach(visit); return }
      if (typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)) hit = node
      visit(node.props?.children)
    }
    visit(tree)
    return hit
  }
  return {
    render(props) { tree = render(props); walk(tree, ''); render.commit() },
    unmount: () => render.unmount(),
    record: () => find('app-tt-record'),
  }
}
function livePlayer() {
  const player = {
    track: { id: 'time', title: 'Time', coverArt: 'cover', albumId: 'dsotm', suffix: 'flac' },
    playing: true, duration: 425, at: 151, listeners: new Set(),
    seek(t) { this.at = t },
    toggle() { this.playing = !this.playing },
    position() { return this.at }, onPosition(listener) { this.listeners.add(listener); return () => this.listeners.delete(listener) },
  }
  for (const name of ['seek', 'toggle', 'position', 'onPosition']) player[name] = player[name].bind(player)
  return player
}

//? the clock's readings as the deck takes them - when, and whether it said the mapping was held
const clockModule = require(path.join(OUT, 'lib/deckClock.js'))
const readings = []
const realReading = clockModule.clockReading
clockModule.clockReading = (clock, at, contextTime, held) => {
  //? what Debug was showing as the reading came, and the step the reading before left
  const reportStep = deckModule.deckReport()?.clockStep, stepBefore = clock.step
  const result = realReading(clock, at, contextTime, held)
  readings.push({ at, held, offset: clock.offset, count: clock.count, reportStep, stepBefore })
  return result
}

//? the deck's own calls, watched: what Turntable hands it, and when - and what the deck was doing after
const calls = { hand: [], takeOver: [], release: [], pressed: [] }
for (const name of ['hand', 'takeOver', 'release', 'pressed']) {
  const own = deckModule.Deck.prototype[name]
  deckModule.Deck.prototype[name] = function (...args) {
    const result = own.apply(this, args)
    calls[name].push({ args, result, real, motion: this.motion })
    return result
  }
}

const CENTRE = { x: tt.RECORD.x, y: tt.RECORD.y }
const RADIUS_PX = 120
const RADIANS_PER_SECOND_OF_SONG = (2 * Math.PI) / tt.SECONDS_PER_TURN

/**
 * One run: a turntable on a page whose audio steps `step` frames at a time at `rate`, its voice on
 * `host`; the song tapped to pause and play (making the audio context in the tap), then the record
 * pressed and turned by a hand whose song position, from the press, is `songAt(ms)`, sampled `hz` times
 * a second (coalesced two to a frame at 120), for `ms`, then let go. Returns what came out, and what it
 * should have been.
 */
async function handRun({ host, rate, step, songAt, speedAt, hz = 60, ms = 3000, noise = 0.5, noiseKind = 'uniform', radius = RADIUS_PX, whole = false, paused = false, liftGap = null, rest = 0, cold = null }) {
  real += 500
  timers = []
  frames = []
  world = {
    host, rate, step, rendered: 0, inbox: [], calls: [], jitter: 0, node: null, script: null,
    audio0: real - 7.3, nextFrame: real + 3, positions: [], log: [],
    state: voice.newVoiceState(), output: new Float32Array(Math.round(((ms + 3000 + rest + (cold ? cold.idle : 0)) / 1000) * rate)),
  }
  define('AudioWorkletNode', host === 'worklet' ? FakeNode : undefined)
  for (const name of Object.keys(calls)) calls[name].length = 0
  const player = livePlayer()
  const deckRef = { current: null }
  const view = mount()
  const draw = (open = true) => view.render({ player, open, discArt: null, onPreview: () => {}, deck: deckRef })
  draw()
  //? two taps - pause, play - the first making the audio context, in its click
  view.record().props.onClick()
  await runUntil(real + 100)
  draw()
  view.record().props.onClick()
  await runUntil(real + 500)
  draw()
  if (paused) {
    //? and a third - the song paused, so a release coasts
    view.record().props.onClick()
    await runUntil(real + 300)
    draw()
  }
  //? the record left `rest` ms (still, once a pause has wound it down)
  if (rest) await runUntil(real + rest)
  let resumedAt = null
  if (cold) {
    //? then the screen closed - its context suspended, the audio's clock standing still - and opened again
    //? by the mini player's tap, which resumes it (App's resumeDeckAudio): its state changes, and the
    //? clock's mapping starts again. Pressed `cold.idle` ms on
    draw(false)
    await runUntil(real + 1000)
    draw(true)
    deckModule.resumeDeckAudio()
    resumedAt = real
    await runUntil(real + cold.idle)
  }
  const deck = deckRef.current
  const live = deck.live()
  //? the hand: a sample every 1000 / hz ms from the press, delivered 4 ms (+-3) later; coalesced at
  //? 120 Hz, two samples to an event, a frame apart
  const start = real + 7
  const angle0 = 0.3
  //? the finger's jitter on each axis: uniform within `noise` px either way, or Gaussian with `noise` px
  //? its spread; and positions in whole pixels where `whole` (as some browsers and synthesized touches give)
  const jitter = () => {
    if (noiseKind !== 'gauss') return (random() - 0.5) * 2 * noise
    let u = 0
    while (u === 0) u = random()
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * random()) * noise
  }
  const pixel = (value) => (whole ? Math.round(value) : value)
  const sample = (time) => {
    const theta = angle0 + songAt(time - start) * RADIANS_PER_SECOND_OF_SONG
    return {
      pointerId: 1, isPrimary: true, pointerType: 'touch', button: 0, timeStamp: time,
      clientX: pixel(CENTRE.x + radius * Math.cos(theta) + jitter()),
      clientY: pixel(CENTRE.y + radius * Math.sin(theta) + jitter()),
      currentTarget: { setPointerCapture() {} },
    }
  }
  const events = []
  const record = () => view.record()
  const first = sample(start)
  events.push({ at: start + 4, run: () => record().props.onPointerDown(first) })
  const every = 1000 / hz
  let pending = []
  for (let k = 1; start + k * every <= start + ms; k++) {
    const one = sample(start + k * every)
    if (hz > 60) {
      pending.push(one)
      if (pending.length < hz / 60) continue
      const batch = pending
      pending = []
      const event = Object.assign({}, batch[batch.length - 1], { getCoalescedEvents: () => batch })
      events.push({ at: event.timeStamp + 4 + (random() - 0.5) * 6, run: () => record().props.onPointerMove(event) })
    } else {
      events.push({ at: one.timeStamp + 4 + (random() - 0.5) * 6, run: () => record().props.onPointerMove(one) })
    }
  }
  events.sort((a, b) => a.at - b.at)
  //? the last move's own time, and the lift `liftGap` ms after it (by default as the page's next moment
  //? comes round: 8 ms or so)
  const lastMove = start + Math.floor(ms / every + 1e-9) * every
  await runUntil(liftGap === null ? start + ms + 10 : lastMove + liftGap + 2, events)
  const offset = deckModule.deckClockMapping().offset
  //? lifted 2 ms before its handler runs, as an event's own time always is
  const lift = sample(real - 2)
  record().props.onPointerUp(lift)
  record().props.onLostPointerCapture(lift)
  await runUntil(real + 300)
  const taken = calls.takeOver[0]
  const report = deckModule.deckReport()
  view.unmount()
  return { live, deck, start, ms, offset, taken, songAt, speedAt, report, world, first, lift, lastMove, player, resumedAt }
}

/**
 * What a run sounded like: each cycle of the tone (one upward zero crossing to the next), at the moment
 * of the hand it stands for - the voice plays the path HAND_DELAY_S behind, through the clock's mapping,
 * and the main-thread voice its lag on from that - and the read head against where the hand was then.
 */
function listen(run, { from = 500, to = 150 } = {}) {
  const { world, start, ms, offset, taken, songAt, speedAt } = run
  const lag = world.host === 'script' ? (deckModule.SCRIPT_LAG_BLOCKS * 1024) / world.rate : 0
  const handFor = (t) => (t - DELAY - lag - offset) * 1000
  const steady = (page) => page >= taken.args[0] + from && page <= start + ms - to
  const data = world.output
  const cycles = []
  let last = null
  for (let i = 1; i < data.length; i++) {
    if (data[i - 1] < 0 && data[i] >= 0) {
      const t = (i - 1 + -data[i - 1] / (data[i] - data[i - 1])) / world.rate
      if (last !== null) {
        const page = handFor((t + last) / 2)
        if (steady(page)) cycles.push({ rate: 1 / (440 * (t - last)), want: Math.abs(speedAt(page - start)) })
      }
      last = t
    }
  }
  const within = cycles.filter((cycle) => Math.abs(cycle.rate / cycle.want - 1) <= 0.03).length / Math.max(1, cycles.length)
  const anchor = taken.result
  const takenAt = songAt(taken.args[0] - start)
  let worst = 0
  for (const [t, pos] of world.positions) {
    const page = handFor(t)
    if (!steady(page)) continue
    worst = Math.max(worst, Math.abs(pos - (anchor + songAt(page - start) - takenAt)))
  }
  const errors = cycles.map((cycle) => cycle.rate / cycle.want - 1)
  const sd = Math.sqrt(errors.reduce((sum, e) => sum + e * e, 0) / Math.max(1, errors.length))
  return { cycles: cycles.length, within: round(within), sd: round(sd, 4), worstMs: round(worst * 1000, 2) }
}

/**
 * The record's sound through a let-go: its speed, render by render (block by block on the main thread),
 * at the moment of the path it plays - against what it should be then: the hand's speed up to its last
 * move, and the plan's after (the coast, or the motor's run back to speed, from where the deck started
 * it). Over `before` ms of the path before the last move to `after` ms after it: the lowest and highest
 * of the one over the other, and the lowest speed.
 */
function acrossRelease(run, { before = 30, after = 80 } = {}) {
  const { world, offset, lastMove, speedAt, start } = run
  const lag = world.host === 'script' ? (deckModule.SCRIPT_LAG_BLOCKS * 1024) / world.rate : 0
  const motion = calls.release[0].motion
  const want = (page) => {
    if (motion.kind !== 'plan' || page < motion.since) return speedAt(Math.min(page, lastMove) - start)
    return platter.planAt(motion.plan, (page - motion.since) / 1000).v
  }
  let low = Infinity, high = -Infinity, slowest = Infinity, resting = 0
  const release = calls.release[0].args[0]
  const positions = world.positions
  for (let i = 1; i < positions.length; i++) {
    const [t0, p0] = positions[i - 1], [t1, p1] = positions[i]
    const page = ((t0 + t1) / 2 - DELAY - lag - offset) * 1000
    if (page < lastMove - before || page > lastMove + after) continue
    const speed = (p1 - p0) / (t1 - t0)
    const wanted = want(page)
    slowest = Math.min(slowest, speed)
    //? from the run-on's end to the lift, the finger resting (when it does): how fast at most
    if (page > lastMove + 30 && page < release - 2) resting = Math.max(resting, Math.abs(speed))
    if (Math.abs(wanted) < 0.05) continue
    low = Math.min(low, speed / wanted)
    high = Math.max(high, speed / wanted)
  }
  return { low: round(low), high: round(high), slowest: round(slowest), resting: round(resting), kind: motion.kind === 'plan' ? motion.role : motion.kind }
}

/**
 * The first moments of a gesture: each cycle of the tone whose moment of the hand is `from` to `to` ms
 * after the take, its rate against the hand's speed - the lowest and highest of the one over the other,
 * and how many within 3% - and how far the clock's mapping in use moved from the take to the release,
 * the largest step between two readings and in all (ms).
 */
function gestureStart(run, { from = 30, to = 300 } = {}) {
  const { world, offset, speedAt, start } = run
  const lag = world.host === 'script' ? (deckModule.SCRIPT_LAG_BLOCKS * 1024) / world.rate : 0
  const took = calls.takeOver[0].args[0]
  const data = world.output
  let last = null, low = Infinity, high = -Infinity, n = 0, within = 0
  for (let i = 1; i < data.length; i++) {
    if (data[i - 1] < 0 && data[i] >= 0) {
      const t = (i - 1 + -data[i - 1] / (data[i] - data[i - 1])) / world.rate
      if (last !== null) {
        const page = ((t + last) / 2 - DELAY - lag - offset) * 1000
        if (page >= took + from && page <= took + to) {
          const ratio = 1 / (440 * (t - last)) / Math.abs(speedAt(page - start))
          low = Math.min(low, ratio)
          high = Math.max(high, ratio)
          n++
          if (Math.abs(ratio - 1) <= 0.03) within++
        }
      }
      last = t
    }
  }
  const taking = calls.takeOver[0].real, letting = calls.release[0].real
  const held = readings.filter((reading) => reading.at >= taking && reading.at <= letting && reading.offset !== null)
  let jump = 0
  for (let i = 1; i < held.length; i++) jump = Math.max(jump, Math.abs(held[i].offset - held[i - 1].offset))
  const offsets = held.map((reading) => reading.offset)
  const since = readings.filter((reading) => reading.at > (run.resumedAt ?? -Infinity) && reading.at < calls.pressed[0].real)
  return {
    low: round(low), high: round(high), within: round(within / Math.max(1, n)), cycles: n,
    jumpMs: round(jump * 1000, 4), movedMs: round((Math.max(...offsets) - Math.min(...offsets)) * 1000, 4),
    readingsBeforePress: since.length, countAtPress: since.at(-1)?.count ?? 0,
  }
}

async function main() {

  console.log('\nthe song at the hand\'s speed: at least 90% of cycles within 3% of it, the read head where the hand was HAND_DELAY_S before')
  const steadyHands = [['1x', 1], ['0.5x', 0.5], ['2x', 2], ['backwards, -1x', -1]]
  const clocks = [['desktop Brave\'s 5.8 ms steps', 44100, 256], ['an iPhone\'s 21.3 ms steps', 48000, 1024]]
  const table = []
  for (const host of ['worklet', 'script']) {
    for (const [clockName, rate, step] of clocks) {
      for (const [handName, speed] of steadyHands) {
        //? coalesced 120 Hz samples on the iPhone's clock, as a ProMotion iPhone gives them
        const hz = step === 1024 && speed === 1 ? 120 : 60
        const run = await handRun({ host, rate, step, hz, songAt: (ms) => (speed * ms) / 1000, speedAt: () => speed })
        const heard = listen(run)
        table.push({ host, clock: step, hand: speed, hz, ...heard })
        check(`${host === 'worklet' ? 'the worklet' : 'the main thread'}, ${clockName}, a hand at ${handName}${hz > 60 ? ' (120 Hz, coalesced)' : ''}: the press the deck's; >= 90% of ${heard.cycles} cycles within 3%; the read head within 5 ms of where the hand was`,
          [run.live, heard.within >= 0.9, heard.worstMs <= 5], [true, true, true])
      }
    }
  }
  console.log('    ' + table.map((row) => JSON.stringify(row)).join('\n    '))

  console.log('\nharder hands: a heavier finger, a grip nearer the spindle, whole pixels - the pitch still the hand\'s')
  {
    //? the jitter the line's place and speed are averaged over, measured in the samples, so the fit
    //? degrades with the finger rather than falling off a fixed threshold (review of 2.0.0-player.24:
    //? Gaussian jitter of 0.5 px at 0.5x was 59-77% within 3%, of 1 px at 1x 37-52%, a 60 px grip at
    //? 0.5x 54-77% - the line dropped for a 0.1 s parabola, and the chord between places carried the rest)
    const harder = [
      ['Gaussian jitter, 0.5 px each axis, at 0.5x', { speed: 0.5, noiseKind: 'gauss', noise: 0.5 }],
      ['Gaussian jitter, 1 px each axis, at 1x', { speed: 1, noiseKind: 'gauss', noise: 1 }],
      ['a grip 60 px from the spindle, at 0.5x', { speed: 0.5, radius: 60 }],
      ['a grip 80 px from the spindle, at 0.5x', { speed: 0.5, radius: 80 }],
      ['whole-pixel positions and no jitter, 90 px out, at 0.5x', { speed: 0.5, radius: 90, whole: true, noise: 0 }],
    ]
    const rows = []
    for (const host of ['worklet', 'script']) {
      for (const [rate, step] of [[44100, 256], [48000, 1024]]) {
        for (const [name, { speed, ...how }] of harder) {
          const run = await handRun({ host, rate, step, ...how, songAt: (ms) => (speed * ms) / 1000, speedAt: () => speed })
          rows.push({ name, host, step, ...listen(run) })
        }
      }
    }
    for (const [name] of harder) {
      const mine = rows.filter((row) => row.name === name)
      check(`${name}, both hosts and clocks: at least 90% of cycles within 3% of the hand's speed - ${mine.map((row) => Math.round(row.within * 100)).join(', ')}%`, mine.every((row) => row.within >= 0.9), true)
    }
  }

  console.log('\na hand that speeds up and slows down, and one that turns back and forth: followed')
  for (const host of ['worklet', 'script']) {
    //? 1x, swinging 0.6 either way twice a second... and 0, swinging 1.5 either way once a second
    const swing = await handRun({ host, rate: 48000, step: 1024, songAt: (ms) => ms / 1000 + (0.6 / Math.PI) * Math.sin((Math.PI * ms) / 1000), speedAt: (ms) => 1 + 0.6 * Math.cos((Math.PI * ms) / 1000) })
    const heardSwing = listen(swing)
    const scratch = await handRun({ host, rate: 48000, step: 1024, songAt: (ms) => (1.5 / (2 * Math.PI)) * Math.sin((2 * Math.PI * ms) / 1000), speedAt: (ms) => 1.5 * Math.cos((2 * Math.PI * ms) / 1000) })
    const heardScratch = listen(scratch)
    console.log(`    (${host}: speeding up and slowing down ${JSON.stringify(heardSwing)}; back and forth ${JSON.stringify(heardScratch)})`)
    check(`${host === 'worklet' ? 'the worklet' : 'the main thread'}: from 0.4x to 1.6x and back - the read head within 5 ms of where the hand was, and 80% of cycles within 3% of its speed (as it changes, the knots' own speeds from the stretch that still agrees, the chord between them where it isn't steady - 72-75% before review); turned back and forth at up to 1.5x, once a second - within 6`,
      [heardSwing.worstMs <= 5, heardSwing.within >= 0.8, heardScratch.worstMs <= 6], [true, true, true])
  }

  console.log('\nletting go of a moving record: the sound carries on with the platter as the finger lifts - no stall, and after a rest no swing back')
  {
    //? a finger turning at 1x or 3x on a paused song (a coast), or at 3x on a playing one (the motor's run
    //? back to speed), lifted 0-30 ms after its last move - a touch screen's lift comes a scan after it,
    //? 8-17 ms - or 45-60 ms after (a rest, the release's speed taken down by it)
    const rows = []
    for (const host of ['worklet', 'script']) {
      for (const [rate, step] of [[44100, 256], [48000, 1024]]) {
        for (const [speed, paused] of [[1, true], [3, true], [3, false]]) {
          for (const gap of [0, 8, 16, 30, 45, 60]) {
            const run = await handRun({ host, rate, step, ms: 1200, paused, liftGap: gap, songAt: (ms) => (speed * ms) / 1000, speedAt: () => speed })
            rows.push({ host, step, speed, paused, gap, ...acrossRelease(run) })
          }
        }
      }
    }
    const moving = rows.filter((row) => row.gap <= 30), rested = rows.filter((row) => row.gap > 30)
    console.log(`    (lifted while moving: the sound over what it should be ${Math.min(...moving.map((row) => row.low))} to ${Math.max(...moving.map((row) => row.high))}; after a rest, the slowest over the hand's speed ${round(Math.min(...rested.map((row) => row.slowest / row.speed)))})`)
    check('lifted 0, 8, 16 or 30 ms after the last move - at 1x and 3x, coasting or back to speed, both hosts and clocks: the record\'s sound through the let-go within 10% of the platter\'s speed - the plan carrying on from the hand\'s last sample, at its moment, where the hand had it (review of 2.0.0-player.24: started at the release\'s time from that place, it stood still for the gap - down to 0.07x a frame after the last move)',
      moving.filter((row) => !(row.low >= 0.9 && row.high <= 1.1)).map((row) => JSON.stringify(row)), [])
    check('...lifted 45 or 60 ms after it, the finger at rest meanwhile: the sound still while it rests (under 0.15 of the hand\'s speed from the run-on\'s end to the lift - the plan starts at the release then, not at the last move), and no swing back past what any dead stop\'s own settling has (-0.13 of the hand\'s speed, the voice\'s smoothing): the plan sets off from where the sound stopped, and the steering takes up the step to where the hand let go (review: -0.7 of it, back across the rest)',
      rested.filter((row) => !(row.resting <= 0.15 * row.speed && row.slowest >= -0.15 * row.speed)).map((row) => JSON.stringify(row)), [])
  }

  console.log('\nlet go of a playing record turned at its own speed: the song plays on from where the hand let go - and the record\'s sound, the delay behind, stops short of it')
  {
    //? James's own case: turned at 1x, let go. There is no coast to wait for, so the song plays in the
    //? release from where the hand let go (Turntable seeks it there) and the record's sound stops in the
    //? release too: HAND_DELAY_S behind the hand (and SCRIPT_LAG_BLOCKS more on the main thread), it has
    //? not yet played the hand's last stretch - so that stretch of the song is heard by neither. The
    //? delay is latency on the record's sound alone (the seek, the song, where it lands are as they were)
    const rows = []
    for (const host of ['worklet', 'script']) {
      const run = await handRun({ host, rate: 48000, step: 1024, ms: 1200, liftGap: 8, songAt: (ms) => ms / 1000, speedAt: () => 1 })
      const lag = host === 'script' ? (deckModule.SCRIPT_LAG_BLOCKS * 1024) / 48000 : 0
      const heardTo = host === 'worklet' ? run.world.state.pos : run.world.positions.at(-1)[1]
      const release = calls.release[0]
      rows.push({ host, kind: release.motion.kind, played: release.result.play, skippedMs: round((release.result.seek - heardTo) * 1000, 1), lagMs: round(lag * 1000, 1) })
    }
    console.log('    ' + rows.map((row) => JSON.stringify(row)).join('\n    '))
    check('turned at 1x and let go 8 ms after the last move: the song played from where the hand let go, in the release; the record\'s sound stopped there too, short of it by about HAND_DELAY_S less the 8 ms (30-50 ms of the song) - on the main thread, as much as its lag more (the stop waits for the next block, which plays a block on: 0-50 ms more than the lag)',
      rows.map((row) => [row.kind, row.played, row.skippedMs >= (row.lagMs ? 0 : 30) + row.lagMs && row.skippedMs <= 50 + row.lagMs]), rows.map(() => ['turning', true, true]))
  }

  console.log('\nthe first grab of a still record after its context was suspended and resumed: stamped steadily, sounding as any grab from still does')
  {
    //? second review of 2.0.0-player.24: a paused record runs no frames, so nothing read the clock between
    //? the resume - whose state change starts the mapping again - and the grab: the gesture's own stamps were
    //? the mapping's first readings, and a young mapping was followed even held. On an iPhone's 21.3 ms clock
    //? its stamps jumped 13-16 ms in the gesture, and the sound in its first 300 ms went from 0.05x to 9x of
    //? the hand's speed (5.8 ms: 2-5.5 ms jumps). Now the deck reads the clock on its own timer while the
    //? turntable shows and the context runs (keepClock), and a held mapping never jumps, young or not
    const rows = []
    for (const host of ['worklet', 'script']) {
      for (const [rate, step] of [[48000, 1024], [44100, 256]]) {
        for (const speed of [1, 2]) {
          for (const idle of [0, 1000]) {
            const run = await handRun({ host, rate, step, ms: 600, paused: true, rest: 2500, cold: { idle }, songAt: (ms) => (speed * ms) / 1000, speedAt: () => speed })
            const gestureMs = calls.release[0].real - calls.takeOver[0].real
            rows.push({ host, step, speed, idle, live: run.live, slewMs: round(clockModule.CLOCK_SLEW * gestureMs, 4), ...gestureStart(run) })
          }
        }
      }
    }
    //? and the same grab with no suspend before it, for what a grab from still sounds like anyway
    const warm = []
    for (const host of ['worklet', 'script']) {
      for (const speed of [1, 2]) {
        const run = await handRun({ host, rate: 48000, step: 1024, ms: 600, paused: true, rest: 2500, songAt: (ms) => (speed * ms) / 1000, speedAt: () => speed })
        warm.push(gestureStart(run))
      }
    }
    console.log('    ' + rows.map((row) => JSON.stringify(row)).join('\n    '))
    console.log(`    (with no suspend before it, the same grab: ${Math.min(...warm.map((row) => row.low))} to ${Math.max(...warm.map((row) => row.high))} of the hand's speed)`)
    check('pressed at the resume and a second after it, at 1x and 2x, both hosts and clocks: the deck\'s press; and from the take to the release the mapping in use moves a hundredth of a millisecond between two readings at most, and no further in all than CLOCK_SLEW allows (13-16 ms on the iPhone\'s clock before)',
      rows.filter((row) => !(row.live && row.jumpMs <= 0.01 && row.movedMs <= row.slewMs + 0.01)).map((row) => JSON.stringify(row)), [])
    check('...and the sound in the gesture\'s first 30-300 ms within 0.92-1.25 of the hand\'s speed - what a grab from still does anyway, its run up to the hand\'s speed (0.05-9x on the iPhone\'s clock before)',
      rows.filter((row) => !(row.low >= 0.92 && row.high <= 1.25)).map((row) => JSON.stringify(row)), [])
    check('...pressed a second after the resume: the clock read meanwhile on the deck\'s own timer - every CLOCK_SETTLE_MS until it settled, every CLOCK_TICK_MS after (no frames run: the record is still) - so the press found it settled (none read before)',
      rows.filter((row) => row.idle === 1000).map((row) => [row.countAtPress >= clockModule.CLOCK_YOUNG, row.readingsBeforePress >= clockModule.CLOCK_YOUNG + 1 && row.readingsBeforePress <= 1000 / deckModule.CLOCK_TICK_MS + clockModule.CLOCK_YOUNG + 6]),
      rows.filter((row) => row.idle === 1000).map(() => [true, true]))
  }

  console.log('\nwhat Turntable hands the deck: every sample, with its own time, as it comes')
  {
    const run = await handRun({ host: 'worklet', rate: 48000, step: 1024, hz: 120, ms: 600, songAt: (ms) => ms / 1000, speedAt: () => 1 })
    const handTimes = calls.hand.map((call) => call.args[0])
    const handled = calls.hand.map((call) => call.real)
    const every = 1000 / 120
    const onGrid = handTimes.every((time) => Math.abs(((time - run.start) / every) - Math.round((time - run.start) / every)) < 1e-6)
    check('each coalesced sample handed on with its OWN time (the 120 Hz grid the finger was sampled on), never when its handler ran - and in order, one after another',
      [onGrid, handTimes.every((time, i) => i === 0 || time > handTimes[i - 1]), handTimes.every((time, i) => time < handled[i])], [true, true, true])
    check('...two to each event, both handed on: about 72 in 600 ms', handTimes.length >= 68 && handTimes.length <= 72, true)
    check('the record taken at the time of the sample that crossed a tap\'s few pixels', Math.abs(((run.taken.args[0] - run.start) / every) - Math.round((run.taken.args[0] - run.start) / every)) < 1e-6, true)
    const posted = run.world.state
    check('...and each sample reached the voice as a knot of its path: no drive a frame under the hand', [posted.knotHand.some((h) => h === 1)], [true])
    const take = run.world.log.find((message) => message.type === 'take')
    const hands = run.world.log.filter((message) => message.type === 'hand').slice(1)
    const stamp = (time) => time / 1000 + run.offset
    check('...each stamped by the one clock at the sample\'s own time: the take, and every sample after it (within the half a millisecond a second the held mapping may move)',
      [Math.abs(take.time - stamp(run.taken.args[0])) < 3e-4, hands.length, hands.every((message, i) => Math.abs(message.time - stamp(calls.hand[i].args[0])) < 3e-4)], [true, calls.hand.length, true])
    check('the press and the release with their events\' own times too', [calls.pressed[0].args[0], calls.release[0].args[0]], [run.first.timeStamp, run.lift.timeStamp])
    const taking = calls.takeOver[0].real, letting = calls.release[0].real
    const between = readings.filter((reading) => reading.at > taking + 1 && reading.at < letting - 1)
    const before = readings.filter((reading) => reading.at > taking - 300 && reading.at < calls.pressed[0].real)
    check('the clock\'s mapping held steady from the take to the release - every reading meanwhile says so - and left to settle before it, while nothing was being followed',
      [between.length > 40 && between.every((reading) => reading.held), before.length > 10 && before.every((reading) => !reading.held)], [true, true])
  }
  {
    //? what reached the voice under the hand, message by message
    real += 500
    timers = []
    frames = []
    const kinds = []
    world = {
      host: 'worklet', rate: 48000, step: 1024, rendered: 0, inbox: { push: (m) => kinds.push(m.type) }, calls: [], jitter: 0, node: null, script: null,
      audio0: real - 7.3, nextFrame: real + 3, positions: [], state: voice.newVoiceState(), output: new Float32Array(48000 * 4),
    }
    world.inbox.splice = () => []
    define('AudioWorkletNode', FakeNode)
    const player = livePlayer()
    const deckRef = { current: null }
    const view = mount()
    const draw = () => view.render({ player, open: true, discArt: null, onPreview: () => {}, deck: deckRef })
    draw()
    view.record().props.onClick()
    await runUntil(real + 100)
    view.record().props.onClick()
    await runUntil(real + 500)
    draw()
    const at = (degrees) => ({ x: CENTRE.x + RADIUS_PX * Math.cos(degrees * Math.PI / 180), y: CENTRE.y + RADIUS_PX * Math.sin(degrees * Math.PI / 180) })
    const event = (degrees, time) => ({ pointerId: 1, isPrimary: true, pointerType: 'touch', button: 0, clientX: at(degrees).x, clientY: at(degrees).y, timeStamp: time, currentTarget: { setPointerCapture() {} } })
    view.record().props.onPointerDown(event(0, real))
    const before = kinds.length
    const moves = []
    for (let k = 1; k <= 30; k++) moves.push({ at: real + k * 16.7 + 3, run: ((time, degrees) => () => view.record().props.onPointerMove(event(degrees, time)))(real + k * 16.7, k * 3.3) })
    await runUntil(real + 30 * 16.7 + 10, moves)
    const under = kinds.slice(before)
    check('under the hand: a take, then one \'hand\' message a sample - 30 samples, 30 knots - and not one drive in the 30 frames between them',
      [under[0], under.filter((kind) => kind === 'hand').length, under.filter((kind) => kind === 'drive').length], ['take', 30, 0])
    view.unmount()
  }

  console.log('\nthe old way, in the same harness: nowhere near')
  {
    //? the page side before 2.0.0-player.24: each sample timed when its handler ran (performance.now()),
    //? one drive a frame - where the last sample put the song, at the hand's speed over its last 40 ms
    //? taken at the frame's time - stamped with currentTime as it was read; into today's voice
    const old = []
    for (const [name, rate, step] of clocks) {
      real += 500
      timers = []
      frames = []
      world = {
        host: 'worklet', rate, step, rendered: 0, inbox: [], calls: [], jitter: 0, node: null, script: null,
        audio0: real - 7.3, nextFrame: real + 3, positions: [], state: voice.newVoiceState(), output: new Float32Array(Math.round(4.5 * rate)),
      }
      world.state.window = { channels: [toneAt(rate)], start: 140, rate, length: toneAt(rate).length }
      const start = real + 7
      const box = BOX
      let drag = null, taken = false, anchor = 151, at = 151
      const samples = []
      const currentTime = () => world.rendered / rate
      const onFrame = (time) => {
        if (taken) {
          const speed = platter.handSpeed(samples, Math.max(time, samples[samples.length - 1].time), 40)
          world.inbox.push({ type: 'drive', at, rate: speed, time: currentTime(), until: currentTime() + 0.12 })
        }
        frames.push({ id: nextId++, run: onFrame })
      }
      frames.push({ id: nextId++, run: onFrame })
      const events = []
      for (let k = 0; k * (1000 / 60) <= 3000; k++) {
        const time = start + k * (1000 / 60)
        const theta = 0.3 + (time - start) / 1000 * RADIANS_PER_SECOND_OF_SONG
        const x = CENTRE.x + RADIUS_PX * Math.cos(theta) + (random() - 0.5)
        const y = CENTRE.y + RADIUS_PX * Math.sin(theta) + (random() - 0.5)
        events.push({ at: time + 4 + (random() - 0.5) * 6, run: () => {
          if (!drag) { drag = tt.recordStart(1, 'time', x, y, box); return }
          drag = tt.recordMove(drag, 1, x, y, box, 425, anchor)
          if (!taken && tt.moved(drag)) {
            taken = true
            drag = { ...drag, offset: 0 }
            world.inbox.push({ type: 'take', at: anchor, rate: 1, time: currentTime(), until: currentTime() + 0.12 })
          }
          if (taken) {
            samples.push({ time: real, turned: drag.turned })
            at = anchor + drag.offset
          }
        } })
      }
      events.sort((a, b) => a.at - b.at)
      await runUntil(start + 3010, events)
      frames = []
      const data = world.output
      let last = null
      const rates = []
      for (let i = 1; i < data.length; i++) {
        if (data[i - 1] < 0 && data[i] >= 0) {
          const t = (i - 1 + -data[i - 1] / (data[i] - data[i - 1])) / rate
          const page = world.audio0 + t * 1000
          if (last !== null && page > start + 600 && page < start + 2900) rates.push(1 / (440 * (t - last)))
          last = t
        }
      }
      const within = rates.filter((r) => Math.abs(r - 1) <= 0.03).length / rates.length
      old.push({ clock: step, cycles: rates.length, within: round(within) })
    }
    console.log(`    (${JSON.stringify(old)})`)
    check('a hand at exactly 1x, the old page side, on both clocks: under half the cycles within 3% - the warble James heard (today\'s: 90% and more, above)',
      old.map((row) => row.within < 0.5), [true, true])
  }

  console.log('\nthe clock, from the deck: read every frame, started again as its context stops and starts, and its step in Debug')
  {
    const run = await handRun({ host: 'worklet', rate: 48000, step: 1024, ms: 400, songAt: (ms) => ms / 1000, speedAt: () => 1 })
    check('Debug told how far the audio\'s clock moves at a time: an iPhone\'s 1024 frames, 21.3 ms', round((run.report?.clockStep ?? 0) * 1000, 1), 21.3)
    check('...the turntable gone, its context closed: the mapping forgotten', deckModule.deckClockMapping().count, 0)
  }
  //? a turntable on a page whose audio steps `step` frames at a time at `rate`, no hand on it
  const bare = (rate = 48000, step = 1024, seconds = 3) => {
    real += 500
    timers = []
    frames = []
    world = {
      host: 'worklet', rate, step, rendered: 0, inbox: [], calls: [], jitter: 0, node: null, script: null,
      audio0: real - 7.3, nextFrame: real + 3, positions: [], state: voice.newVoiceState(), output: new Float32Array(rate * seconds),
    }
    define('AudioWorkletNode', FakeNode)
    const player = livePlayer()
    const view = mount()
    const draw = (open = true) => view.render({ player, open, discArt: null, onPreview: () => {} })
    draw()
    return { view, draw, player }
  }
  {
    //? the desktop's 5.8 ms render, read once a frame (and on the deck's timer): its first moves between two
    //? readings can be 11.6 or 17.4 ms, and the step is narrowed to 5.8 only by a later reading. Measured
    //? across a resume - its state change starts the mapping again and reports a step of 0 - with deadwax's
    //? window held back, so nothing else reports after it: Debug is told 5.8 only if it is told as the step
    //? changes (second review of 2.0.0-player.24: without that, Debug read 17.4 for good on a desktop - and
    //? the iPhone's step, longer than a frame, never shows it: its first move is already the step)
    const realFetch = globalThis.fetch
    define('fetch', () => new Promise(() => {}))
    const { view, draw } = bare(44100, 256, 4)
    view.record().props.onClick()
    await runUntil(real + 100)
    draw()
    view.record().props.onClick()
    await runUntil(real + 300)
    draw()
    draw(false)
    await runUntil(real + 200)
    draw(true)
    deckModule.resumeDeckAudio()
    const from = readings.length
    const zero = deckModule.deckReport()?.clockStep
    await runUntil(real + 1000)
    const told = readings.slice(from)
    const report = deckModule.deckReport()
    check('a playing record on the desktop\'s clock, its context resumed (the step back to 0) and read by frames and the deck\'s timer, nothing else reporting (no window lands): Debug says 5.8 ms - told as the step was found and narrowed - and at every reading it already showed the step the reading before had left (to the 0.1 ms the deck tells a change by)',
      [zero, round((report?.clockStep ?? 0) * 1000, 1), round(deckModule.deckClockMapping().step * 1000, 1), told.length > 50 && told.every((reading) => Math.abs(reading.reportStep - reading.stepBefore) <= 1e-4)], [0, 5.8, 5.8, true])
    view.unmount()
    define('fetch', realFetch)
  }
  {
    //? a still record - its song paused, wound down - on a running context: no frame runs, and the deck's own
    //? timer reads the clock all the same; hidden (the context suspended) or not running, nothing reads it
    const { view, draw } = bare(48000, 1024, 12)
    view.record().props.onClick()
    await runUntil(real + 3000)
    const count = (from, to) => readings.filter((reading) => reading.at > from && reading.at <= to).length
    const still = real
    await runUntil(real + 3000)
    check('a still record on a running context: no frame asked for, and the clock read on the deck\'s own timer, CLOCK_TICK_MS apart - 30 readings in 3 s',
      [frames.length, deckModule.CLOCK_TICK_MS, Math.abs(count(still, real) - 3000 / deckModule.CLOCK_TICK_MS) <= 1], [0, 100, true])
    draw(false)
    const hidden = real
    await runUntil(real + 1000)
    draw(true)
    await runUntil(real + 1000)
    check('...hidden (its context suspended), and shown again with nothing to resume it yet: not read at all - the timer stopped with the sound', count(hidden, real), 0)
    deckModule.resumeDeckAudio()
    const resumed = real
    await runUntil(real + 220)
    const early = count(resumed, real)
    await runUntil(real + 1000)
    check('...resumed (the mini player\'s tap - the mapping started again by its state change): read every CLOCK_SETTLE_MS until it settles - 12 or more in its first 220 ms - then every CLOCK_TICK_MS',
      [deckModule.CLOCK_SETTLE_MS, early >= clockModule.CLOCK_YOUNG, Math.abs(count(real - 1000, real) - 1000 / deckModule.CLOCK_TICK_MS) <= 1], [15, true, true])
    view.unmount()
  }
  {
    //? a turntable showing a playing song, no hand on it: the clock read every frame regardless
    const { view } = bare()
    view.record().props.onClick()
    await runUntil(real + 100)
    view.record().props.onClick()
    await runUntil(real + 50)
    const before = deckModule.deckClockMapping().count
    await runUntil(real + 500)
    const read = deckModule.deckClockMapping().count - before
    check('the record turning with no hand on it: the clock read every frame anyway - 30 readings in half a second, and the deck\'s timer\'s besides', read >= 30 && read <= 31 + 500 / deckModule.CLOCK_TICK_MS, true)
    contexts.at(-1).changed()
    check('...its context\'s state changing (suspended, resumed - its clock stood still meanwhile): the mapping starts again', [deckModule.deckClockMapping().count, deckModule.deckClockMapping().offset], [0, null])
    view.unmount()
  }

  /* ===== the path's edges, in the voice itself ===== */

  const SR = 48000
  const tone = toneAt(SR)
  const windowed = (start = 10) => ({ type: 'window', channels: [tone, tone], start, rate: SR })
  const handAt = (state, at, time) => voice.voiceCommand(state, { type: 'hand', at, time }, time, SR)
  //? a voice taken at 20 s in the song at `rate`, the hand's first sample there - as the deck takes it
  const taken = (rate = 1) => {
    const state = voice.newVoiceState()
    voice.voiceCommand(state, windowed(), 0, SR)
    voice.voiceCommand(state, { type: 'take', at: 20, rate, time: 0, until: 0.12 }, 0, SR)
    handAt(state, 20, 0)
    return state
  }
  /**
   * The hand's samples (`at` in the song, at their own `time`) reaching the voice as a page delivers
   * them - each 4 ms after its own time unless it says when (`deliver`) - rendered 16 samples at a time
   * from `from` to `until`, `each` seeing the voice after every 16. What came out, as one array.
   */
  const feed = (state, samples, until, each, from = 0) => {
    const queue = samples.map((sample) => ({ deliver: sample.time + 0.004, ...sample })).sort((a, b) => a.deliver - b.deliver)
    const out = []
    for (let now = from; now < until; now += 16 / SR) {
      while (queue.length && queue[0].deliver <= now) {
        const sample = queue.shift()
        handAt(state, sample.at, sample.time)
      }
      const block = [new Float32Array(16), new Float32Array(16)]
      voice.renderVoice(state, block, 16, SR, now)
      for (let j = 0; j < 16; j++) out.push(block[0][j])
      each?.(now + 16 / SR, state)
    }
    return out
  }
  //? a hand's samples 60 a second over `seconds`, where `x(t)` puts the song
  const samplesOf = (x, seconds, hz = 60, from = 1 / hz) => {
    const list = []
    for (let time = from; time <= seconds + 1e-9; time += 1 / hz) list.push({ time, at: x(time) })
    return list
  }

  console.log('\nthe path\'s edges: a hand that stops, a late sample, a stall, a turn back, the first samples after a take')
  {
    //? 1x for half a second, then the finger stops dead: nothing more comes
    const state = taken()
    const rates = []
    const out = feed(state, samplesOf((t) => 20 + t, 0.5), 1.1, (t, s) => rates.push([t, s.rate]))
    const after = rates.filter(([t]) => t > 0.5 + DELAY + 0.2)
    check('a hand that stops dead: the record runs on EXTRAPOLATE_S past its last sample, slowing to still, and holds - still and silent within 200 ms of it, never more than 10 ms of the song past it',
      [after.every(([, rate]) => Math.abs(rate) < 0.01), round(state.pos - 20.5, 4) <= 0.0105, Math.max(...out.slice(-4800).map(Math.abs)) < 1e-3], [true, true, true])
    check('...the first samples after a take: no dip from the song\'s own speed into the hand\'s - within 3% the whole way',
      rates.filter(([t]) => t > 0.005 && t < 0.5 + DELAY - 0.01).every(([, rate]) => Math.abs(rate - 1) <= 0.03), true)
  }
  {
    //? 1x, its sample at 0.3 s coming 70 ms late - after the voice has played past its moment
    const state = taken()
    const samples = samplesOf((t) => 20 + t, 0.8).map((sample) => (Math.abs(sample.time - 0.3) < 1e-6 ? { ...sample, deliver: 0.37 } : sample))
    let worst = 0, fastest = 0, slowest = Infinity
    feed(state, samples, 0.8, (t, s) => {
      if (t > 0.1) {
        worst = Math.max(worst, Math.abs(s.pos - (20 + t - DELAY)))
        fastest = Math.max(fastest, s.rate)
        slowest = Math.min(slowest, s.rate)
      }
    })
    check('a sample that comes late, its neighbours on time: the path never strays - the read head within 2 ms of the hand, the speed within 5%',
      [worst <= 0.002, fastest <= 1.05, slowest >= 0.95], [true, true, true])
  }
  {
    //? the page stalls 80 ms: the samples of it, and the one after, all delivered at once at its end
    const state = taken()
    const samples = samplesOf((t) => 20 + t, 1).map((sample) => (sample.time > 0.3 && sample.time < 0.39 ? { ...sample, deliver: 0.394 } : sample))
    let fastest = 0, slowest = Infinity, worstAfter = 0
    feed(state, samples, 1, (t, s) => {
      fastest = Math.max(fastest, s.rate)
      slowest = Math.min(slowest, s.rate)
      if (t > 0.75) worstAfter = Math.max(worstAfter, Math.abs(s.pos - (20 + t - DELAY)))
    })
    check('a page that stalls 80 ms and then delivers it all: a short run-on, slowing to still - then caught up, never a run-away (under 1.6x) nor run back (above -0.2) - and back on the hand within a millisecond',
      [fastest < 1.6, slowest > -0.2, worstAfter <= 0.001], [true, true, true])
  }
  {
    //? samples missing from a steadily moving hand - a busy page dispatching only a move's newest sample,
    //? and on plain http no getCoalescedEvents() to bring the rest: two gone (a 50 ms gap), and three (67
    //? ms), at 0.5x, 1x and 2x
    const rows = []
    for (const speed of [0.5, 1, 2]) {
      for (const missing of [2, 3]) {
        const state = taken()
        const gone = (time) => Array.from({ length: missing }, (_, i) => 0.5 + i / 60).some((at) => Math.abs(time - at) < 1e-6)
        const samples = samplesOf((t) => 20 + speed * t, 1.2).filter((sample) => !gone(sample.time))
        let worst = 0, fastest = 0, slowest = Infinity
        feed(state, samples, 1.2, (t, s) => {
          if (t > 0.2) {
            worst = Math.max(worst, Math.abs(s.pos - (20 + speed * (t - DELAY))))
            fastest = Math.max(fastest, s.rate / speed)
            slowest = Math.min(slowest, s.rate / speed)
          }
        })
        rows.push({ speed, missing, worstMs: round(worst * 1000, 2), fastest: round(fastest), slowest: round(slowest) })
      }
    }
    console.log('    ' + rows.map((row) => JSON.stringify(row)).join('\n    '))
    check('two of a moving hand\'s samples gone missing (a 50 ms gap) at 0.5x, 1x and 2x: not a rest - the path runs on through the gap, the speed within 4% of the hand\'s and the read head within a millisecond of it (review of 2.0.0-player.24: read as a stop - 0.14x, then 2.2x, 20-40 ms astray)',
      rows.filter((row) => row.missing === 2 && !(row.worstMs <= 1 && row.fastest <= 1.04 && row.slowest >= 0.96)).map((row) => JSON.stringify(row)), [])
    check('...three (67 ms, longer than the delay holds): the voice runs out of path and its run-on slows it, but it is caught up gently - never faster than 1.2x the hand, never more than 10 ms of the song per 1x astray (as a stop: 3.2x, 38 ms at 1x)',
      rows.filter((row) => row.missing === 3 && !(row.fastest <= 1.2 && row.worstMs <= 10 * row.speed)).map((row) => JSON.stringify(row)), [])
    //? two gone from a hand speeding up, 1x to 3x in half a second: where the samples resume isn't where its
    //? speed at the last would have put it - 5 ms further - yet it kept moving (KEPT_ON: within a quarter of
    //? the way it went)
    const state = taken()
    const x = (t) => 20 + t + 2 * t * t
    const samples = samplesOf(x, 0.24).filter((sample) => Math.abs(sample.time - 0.2) > 1e-6 && Math.abs(sample.time - 0.2 - 1 / 60) > 1e-6)
    let worst = 0, slowest = Infinity
    feed(state, samples, 0.29, (t, s) => {
      const was = t - DELAY
      if (was > 0.1 && was < 0.24) {
        worst = Math.max(worst, Math.abs(s.pos - x(was)))
        slowest = Math.min(slowest, s.rate / (1 + 4 * was))
      }
    })
    check('...and two gone from a hand speeding up from 1x to 3x in half a second: still not a rest - the read head within 3 ms of the hand, its speed never below 0.85 of the hand\'s (taken for a rest: 76 ms astray, run back)',
      [round(worst * 1000, 2) <= 3, round(slowest, 3) >= 0.85], [true, true])
  }
  {
    //? turned forward and back: 1.2 sin(2 pi t) / 2 pi of the song, the speed through zero twice a second
    const state = taken(0)
    const x = (t) => 20 + (1.2 / (2 * Math.PI)) * Math.sin(2 * Math.PI * t)
    let worst = 0, step = 0, previous = null
    feed(state, samplesOf(x, 2), 2, (t, s) => {
      if (t > 0.3) {
        worst = Math.max(worst, Math.abs(s.pos - x(t - DELAY)))
        if (previous !== null) step = Math.max(step, Math.abs(s.rate - previous))
      }
      previous = s.rate
    })
    check('a turn back and forth, through zero twice a second at up to 1.2x: the read head within 4 ms of the hand, the speed continuous (no step over 0.01 in 16 samples)',
      [worst <= 0.004, step <= 0.01], [true, true])
  }

  console.log('\na press that rests, a hand that rests and moves on, a release after a rest, the window\'s edge')
  {
    //? taken from a playing song, the finger resting: the take at 1x and the hand's one sample, there
    const state = taken(1)
    let slowest = Infinity
    feed(state, [], 0.6, (t, s) => { slowest = Math.min(slowest, s.rate) })
    check('a press that rests on a playing record: it plays on to where it was taken, the delay later, and stops there - held within a millisecond of it, never swung back faster than -0.2',
      [Math.abs(state.pos - 20) <= 0.001, Math.abs(state.rate) < 0.001, slowest >= -0.2], [true, true, true])
  }
  {
    //? 1x, easing to rest over 0.15 s (at 20.475), resting 0.3 s, then off again at 1x from there at once
    const x = (t) => {
      if (t <= 0.4) return 20 + t
      if (t <= 0.55) return 20.4 + (t - 0.4) - (t - 0.4) ** 2 / 0.3
      if (t <= 0.85) return 20.475
      return 20.475 + (t - 0.85)
    }
    const samples = samplesOf(x, 1.3).filter((sample) => sample.time <= 0.55 || sample.time > 0.85)
    const state = taken()
    let furthest = 0, slowest = Infinity, worst = 0
    feed(state, samples, 1.3, (t, s) => {
      if (t > 0.5 && t < 0.85 + DELAY) furthest = Math.max(furthest, s.pos)
      if (t > 0.85 + DELAY - 0.02 && t < 1 + DELAY) slowest = Math.min(slowest, s.rate)
      if (t > 1.1) worst = Math.max(worst, Math.abs(s.pos - x(t - DELAY)))
    })
    check('a hand that eases to rest: it stops where the hand did - past it by no more than the voice\'s own smoothing lags a stop that brisk (3 ms) - not run on past it',
      round(furthest - 20.475, 4) <= 0.003, true)
    check('...rests 0.3 s and is off again at once: it moves on from where it rested - never back (a curve across the rest would dip 40 ms behind it) - and is on the hand again within a millisecond',
      [slowest >= -0.02, worst <= 0.001], [true, true])
  }
  {
    //? eased to rest at 20.475 by 0.55 s, then let go 0.2 s on, the song playing: the motor's plan from there
    const x = (t) => (t <= 0.4 ? 20 + t : 20.4 + (Math.min(t, 0.55) - 0.4) - (Math.min(t, 0.55) - 0.4) ** 2 / 0.3)
    const state = taken()
    feed(state, samplesOf(x, 0.55), 0.75 + 0.004)
    voice.voiceCommand(state, { type: 'drive', at: 20.475, rate: 0, accel: platter.MOTOR_PULL, time: 0.75, until: 0.87 }, 0.754, SR)
    let low = Infinity
    feed(state, [], 0.75 + DELAY + 0.1, (t, s) => { low = Math.min(low, s.pos) }, 0.754)
    const size = state.knotTime.length
    const stop = (state.end - 3) % size, off = (state.end - 2) % size
    check('let go after a rest, the song playing: the motor takes it on from where it rested - never back past it - a still knot where the path stopped, a still one where the plan sets off, and the plan\'s start',
      [round(low, 4) >= 20.4745, state.knotHand[stop], state.knotRate[stop], round(state.knotTime[stop], 4), state.knotHand[off], state.knotRate[off], round(state.knotTime[off], 4)],
      [true, 0, 0, round(0.55 + 0.02, 4), 0, 0, 0.75])
  }
  {
    const state = voice.newVoiceState()
    voice.voiceCommand(state, { type: 'window', channels: [tone.slice(0, SR)], start: 10, rate: SR }, 0, SR)
    voice.voiceCommand(state, { type: 'take', at: 10.8, rate: 1, time: 0, until: 0.12 }, 0, SR)
    handAt(state, 10.8, 0)
    const out = feed(state, samplesOf((t) => 10.8 + t, 0.5), 0.6)
    const at = Math.round((0.2 + DELAY + 0.01) * SR)
    let step = 0
    for (let i = 21; i < out.length; i++) step = Math.max(step, Math.abs(out[i] - out[i - 1]))
    check('a hand turning on past the window\'s end: silent after it, faded at it - no step bigger than the tone\'s own',
      [Math.max(...out.slice(at).map(Math.abs)) < 1e-3, step <= (0.5 * 2 * Math.PI * 440 / SR) * 1.2], [true, true])
  }

  console.log('\nthe path between a coast\'s frames, a coast caught, a take starting afresh, a drive out of order')
  {
    //? a hard flick back to speed (9x), the page dropping every other frame: told where the plan has it
    //? only every 40 ms - each told 4 ms after its moment. The path between two is a curve through their
    //? places and speeds, not a line between their places
    const plan = platter.motor(20, 9, 425)
    const state = voice.newVoiceState()
    voice.voiceCommand(state, windowed(), 0, SR)
    voice.voiceCommand(state, { type: 'take', at: 20, rate: 9, time: 0, until: 0.12 }, 0, SR)
    const told = []
    for (let time = 0.04; time <= plan.duration; time += 0.04) {
      const { x, v } = platter.planAt(plan, time)
      told.push({ deliver: time + 0.004, message: { type: 'drive', at: x, rate: v, accel: platter.acceleration(v, true), time, until: time + 0.12 } })
    }
    let worst = 0, step = 0, previous = null
    for (let now = 0; now < plan.duration; now += 16 / SR) {
      while (told.length && told[0].deliver <= now) voice.voiceCommand(state, told.shift().message, now, SR)
      voice.renderVoice(state, [new Float32Array(16)], 16, SR, now)
      const was = now + 16 / SR - DELAY
      if (was > 0.05 && was < plan.duration - 0.1) {
        //? how far behind in real time, at the speed it goes - as the coasts above are judged
        const { x, v } = platter.planAt(plan, was)
        worst = Math.max(worst, Math.abs(state.pos - x) / Math.max(1, Math.abs(v)))
        if (previous !== null) step = Math.max(step, Math.abs(state.rate - previous))
      }
      previous = state.rate
    }
    check('a coast back to speed from 9x told only every 40 ms (a page dropping frames): the read head on the platter\'s curve within 1.5 ms of real time - the voice\'s own smoothing lags a deceleration that hard by about one - its speed never stepping (under 0.02 in 16 samples)',
      [worst <= 0.0015, step <= 0.02], [true, true])
  }
  {
    //? coasting at 3x when the hand catches it - its first sample, where the platter was - and holds still
    const state = voice.newVoiceState()
    voice.voiceCommand(state, windowed(), 0, SR)
    voice.voiceCommand(state, { type: 'take', at: 20, rate: 3, time: 0, until: 0.12 }, 0, SR)
    for (let k = 1; k <= 18; k++) voice.voiceCommand(state, { type: 'drive', at: 20 + (3 * k) / 60, rate: 3, accel: 0, time: k / 60, until: k / 60 + 0.12 }, k / 60, SR)
    handAt(state, 20.3 + 3 / 60, 0.3 + 1 / 60)
    feed(state, [], 1.2, null, 0)
    check('a coast caught by the hand and held still: it comes to rest where the hand caught it, within a millisecond - the hand\'s own samples say where it is, not the coast before them',
      round(Math.abs(state.pos - 20.35), 4) <= 0.001, true)
  }
  {
    //? the same catch, at 3x and at 7x - but the sample that crossed a tap's few pixels was made before the
    //? coast's last frame and reached the page after it (a touch's delivery is often longer than the time
    //? to the next frame): its knot is OLDER than the drive the path ends with. Held still, then dragged
    //? on slowly half a second later
    const rows = []
    for (const speed of [3, 7]) {
      for (const older of [0.5, 2, 3, 10]) {
        const state = voice.newVoiceState()
        voice.voiceCommand(state, windowed(), 0, SR)
        voice.voiceCommand(state, { type: 'take', at: 20, rate: speed, time: 0, until: 0.12 }, 0, SR)
        const caughtAt = 0.3 - older / 1000, caught = 20 + speed * caughtAt
        //? each frame's drive told as its frame runs; takeOver's knot and the hand's own for the crossing
        //? sample both as its move is handled, 2 ms after that last frame
        const told = []
        for (let k = 1; k <= 18; k++) told.push({ deliver: k / 60, message: { type: 'drive', at: 20 + (speed * k) / 60, rate: speed, accel: 0, time: k / 60, until: k / 60 + 0.12 } })
        told.push({ deliver: 0.302, message: { type: 'hand', at: caught, time: caughtAt } }, { deliver: 0.302, message: { type: 'hand', at: caught, time: caughtAt } })
        let furthest = 0
        for (let now = 0; now < 0.9; now += 16 / SR) {
          while (told.length && told[0].deliver <= now) voice.voiceCommand(state, told.shift().message, now, SR)
          voice.renderVoice(state, [new Float32Array(16)], 16, SR, now)
          if (now > 0.25) furthest = Math.max(furthest, state.pos)
        }
        const rest = state.pos
        let back = 0
        feed(state, samplesOf((t) => caught + 0.2 * (t - 0.9), 1.3, 60, 0.9 + 1 / 60), 1.3, (t, s) => { back = Math.min(back, s.rate) }, 0.9)
        rows.push({ speed, older, restMs: round((rest - caught) * 1000, 2), pastMs: round((furthest - caught) * 1000, 1), back: round(back, 2) })
      }
    }
    console.log('    ' + rows.map((row) => JSON.stringify(row)).join('\n    '))
    check('a coast caught by a sample older than its last frame\'s drive (0.5-10 ms), at 3x and 7x: the hand\'s sample takes the path from its moment - the coast\'s frames after it cut away - so held still it rests where the hand caught it, within a millisecond, on past it no further than the voice\'s smoothing lags so hard a stop (under 10 ms of song for each 1x of the coast: a hand that stops dead does the same); and dragged on at 0.2x never runs back faster than -0.6 (review of 2.0.0-player.24: dropped as out of order, the coast ran on 0.12 s more under the finger - 0.2-0.4 s of the song - and then rushed back at -3.6x to -7x)',
      rows.filter((row) => !(Math.abs(row.restMs) <= 1 && row.pastMs <= row.speed * 10 && row.back >= -0.6)).map((row) => JSON.stringify(row)), [])
  }
  {
    const state = taken()
    feed(state, samplesOf((t) => 20 + t, 0.4), 0.5)
    voice.voiceCommand(state, { type: 'take', at: 60, rate: 1, time: 0.5, until: 0.62 }, 0.5, SR)
    check('a take starts the path afresh: the gesture before it gone, its one knot all there is', [state.end - state.first, state.knotAt[state.first % state.knotTime.length]], [1, 60])
    voice.voiceCommand(state, { type: 'drive', at: 60.2, rate: 1, time: 0.7, until: 0.82 }, 0.6, SR)
    voice.voiceCommand(state, { type: 'drive', at: 60.18, rate: 1, time: 0.68, until: 0.8 }, 0.6, SR)
    const size = state.knotTime.length
    check('a drive earlier than the newest knot (the handover, stamped at the plan\'s end, after a frame\'s past it): what came after it goes - the path\'s knots always in time order',
      [state.end - state.first, round(state.knotTime[(state.end - 1) % size], 3)], [2, 0.68])
  }

  console.log('\nthe ring: overrun by 240 samples a second, and samples out of order')
  {
    const state = taken()
    let worst = 0
    feed(state, samplesOf((t) => 20 + t, 1.5, 240), 1.5, (t, s) => { if (t > 0.4) worst = Math.max(worst, Math.abs(s.rate - 1)) })
    check('1.5 s of 240 samples a second, five times the ring\'s worth: it keeps the newest 64, the cursor among them, and reads within 1% of the hand',
      [state.end - state.first, state.cursor >= state.first && state.cursor < state.end, worst <= 0.01], [state.knotTime.length, true, true])
    const size = state.knotTime.length
    const before = [state.end, state.knotAt[(state.end - 1) % size]]
    handAt(state, 25, 1.2)
    check('a sample older than the newest the path has: no use to it, dropped', [state.end, state.knotAt[(state.end - 1) % size]], before)
    handAt(state, 21.6, state.knotTime[(state.end - 1) % size])
    check('...one of the same moment as the newest: it replaces it', [state.end, round(state.knotAt[(state.end - 1) % size], 3)], [before[0], 21.6])
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
