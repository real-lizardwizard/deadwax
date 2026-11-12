#!/usr/bin/env node
/**
 * The iPhone app's turntable (notes/ios-specs/turntable.md, slice 1): its physics, its geometry, its speed, its words,
 * its deck's rules and its voice are ports of the web's TypeScript to Swift (ios/DeadwaxKit/Sources/DeadwaxCore/
 * DeckMaths, Platter, TurntableGeometry, PlaySpeed, TurntableWords, TurntablePalette, DeckVoice, DeckRules,
 * TurntablePress). This records what the TypeScript does, so the Swift tests can replay it and hold the ports to it -
 * the voice bit for bit. It compiles ui/src's own files with tsc into TMPDIR, as the sims do, and writes
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/deck/:
 *
 *   jsmath.json     Math.round, Math.min, Math.max, Math.fround and ToInt32 over the edge cases of the spec's 4.2, as
 *                   Node answers them
 *   tokens.json     the theme.css tokens the turntable is drawn in (2.14), and the colours read out of each
 *   platter.json    lib/platter.ts: deck.sim's 54 flicks at targets 0.25, 0.5, 1, 1.5 and 2 - each plan, planAt at 32
 *                   points, phaseAt - handSpeed and releaseSpeed over deck.sim's sample sets, acceleration
 *   turntable.json  lib/turntable.ts and lib/playSpeed.ts: the geometry at four plinth sizes, needleAt, armAngle,
 *                   armTimeAt, the drags, the previews, the fader; lib/deckClock.ts pointerSamples
 *   words.json      every word of the spec's 2.9 the web makes, with its inputs; lib/debugRows.ts turntableRows and
 *                   latencyNote over 40 DeckReports, speedRow; the two You notes
 *   rules/*.json    player/deck.ts's Deck, real, driven through ui/test/deckHarness.cjs (deck.sim's own harness): the
 *                   bench's eight motions (lab/motions.ts) at 60 and at 120 Hz with seeded jitter, the way
 *                   lab/runner.ts runMotion drives them, and deck.sim's kinds of case - every input with its time,
 *                   and every effect: each host call, each turnFace, each message posted with its stamped time, each
 *                   value returned, and the deck's own state after each input
 *   press/*.json    player/Turntable.tsx mounted (turntable.sim's stand-in for Preact) over the same harness and a
 *                   fake player, driven by pointer events and keys: every player call and deck call, in order, and
 *                   the silent line; with the handlers' source hashed piece by piece
 *   voice/*.json    lib/deckVoice.ts's four functions over the rules cases' messages (and a few of their own), at
 *   voice/*.f32     block sizes 128, 333, 512 and 1024 (and 1, over the first 2,000 frames), at 48 and 44.1 kHz, the
 *                   windows made from integer recipes both sides compute: a hash of every 4,096 frames' Float32 bits,
 *                   the reports, and three short cases' whole output
 *   maths.json      every exp, log, sin, cos, atan2, hypot, pow and log10 the ported code evaluated in all of the
 *                   above, its inputs' and answer's bits - and for each voice run, how many it made and a hash of
 *                   their order
 *
 * Doubles are written as their IEEE bits in hex, then a space and the number as JavaScript writes it ("3ff8000000000000
 * 1.5"): the Swift reads the hex, a person the rest. Long runs of doubles are base64 of their little-endian bytes.
 * Each file names the sources it was made from with their sha256, so ui/test/iosdeck.sim.cjs - which runs this with
 * --check - fails when one changes, in what it does or only in its text, until the fixtures are written again and
 * the Swift follows. The folder's budget is 3 MB (iosdeck.sim checks it). Never edit a fixture by hand.
 *
 *   node ios/scripts/export-deck-vectors.cjs           write the fixtures
 *   node ios/scripts/export-deck-vectors.cjs --check   write nothing; exit 1 when a fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURES = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'deck')
const CHECK = process.argv.includes('--check')
const BUDGET = 3 * 1024 * 1024
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-deck-vectors-'))

const SOURCES = [
  'src/lib/platter.ts', 'src/lib/deckVoice.ts', 'src/player/deck.ts', 'src/lib/turntable.ts', 'src/lib/playSpeed.ts',
  'src/lib/deckClock.ts', 'src/lib/debugRows.ts', 'src/player/Turntable.tsx', 'src/lab/motions.ts',
]
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES,
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

/* ===== the sources, and a few changes to the compiled JavaScript ===== */

const sha256 = (text) => crypto.createHash('sha256').update(text).digest('hex')
const source = (file) => fs.readFileSync(path.join(UI, 'src', file), 'utf8')
const whole = (file) => [`ui/src/${file}`, sha256(source(file))]
/** A piece of a source read out by `pattern`, hashed - the script stops, naming it, when it is gone. */
function piece(file, pattern, what) {
  const found = source(file).match(pattern)
  if (!found) throw new Error(`ui/src/${file}: ${what} is no longer where this script reads it - see what moved, and port it`)
  return { text: found[0], from: [`ui/src/${file} ${what}`, sha256(found[0])] }
}
/** Replace `from` with `to` in a compiled file, exactly once - or stop. */
function patch(file, from, to, what) {
  const at = path.join(OUT, file)
  const text = fs.readFileSync(at, 'utf8')
  const count = text.split(from).length - 1
  if (count !== 1) throw new Error(`compiled ${file}: ${what} found ${count} times, not once - the script's patch needs looking at`)
  fs.writeFileSync(at, text.replace(from, to))
}

//? playSpeed.ts raises with `**`, which no Math function records: written as Math.pow, the one place - V8 answers
//? both alike (checked below on every input the fixtures use)
patch('lib/playSpeed.js', '(exports.SPEED_MAX / exports.SPEED_MIN) ** at', 'Math.pow((exports.SPEED_MAX / exports.SPEED_MIN), at)', 'speedAt\'s **')
//? the deck's audio listener, its voice-ready reading and its window's arrival, told to the trace (rules/, below)
patch('player/deck.js', 'onAudio = () => {', 'onAudio = () => { globalThis.__deckTrace?.audio(this);', 'onAudio')

/* ===== a Math that records ===== */

const RECORDED = ['exp', 'log', 'sin', 'cos', 'atan2', 'hypot', 'pow', 'log10']
const REAL = Object.fromEntries(RECORDED.map((name) => [name, Math[name]]))
const ARITY = { exp: 1, log: 1, sin: 1, cos: 1, log10: 1, atan2: 2, hypot: 2, pow: 2 }
const maths = { on: true, table: Object.fromEntries(RECORDED.map((name) => [name, new Map()])), run: null }

const scratch = new DataView(new ArrayBuffer(8))
/** A double's bits, 16 hex digits. */
function hex(x) {
  scratch.setFloat64(0, x)
  return scratch.getUint32(0).toString(16).padStart(8, '0') + scratch.getUint32(4).toString(16).padStart(8, '0')
}
/** A double as the fixtures hold it: its bits, and then as JavaScript writes it. */
const d = (x) => (x === null || x === undefined ? null : `${hex(x)} ${Object.is(x, -0) ? '-0' : String(x)}`)

//? FNV-1a, 64 bits, in two 32-bit halves (BigInt is too slow for the voice's millions of bytes)
const FNV_START = [0xcbf29ce4, 0x84222325]
function fnvBytes(state, bytes) {
  let hi = state[0], lo = state[1]
  for (let i = 0; i < bytes.length; i++) {
    lo = (lo ^ bytes[i]) >>> 0
    const low = lo * 0x1b3
    const carry = Math.floor(low / 4294967296)
    const nextHi = (Math.imul(hi, 0x1b3) + carry + ((lo << 8) >>> 0)) >>> 0
    lo = low >>> 0
    hi = nextHi
  }
  state[0] = hi
  state[1] = lo
}
const fnvHex = (state) => state[0].toString(16).padStart(8, '0') + state[1].toString(16).padStart(8, '0')
const callBytes = new Uint8Array(17)
const callView = new DataView(callBytes.buffer)

for (const name of RECORDED) {
  const real = REAL[name]
  const index = RECORDED.indexOf(name)
  Math[name] = function recorded(...args) {
    const answer = real.apply(Math, args)
    if (maths.on) {
      const inputs = args.slice(0, ARITY[name])
      while (inputs.length < ARITY[name]) inputs.push(undefined)
      const key = inputs.map((x) => hex(Number(x))).join('')
      const table = maths.table[name]
      const had = table.get(key)
      if (had === undefined) table.set(key, hex(answer))
      else if (had !== hex(answer)) throw new Error(`Math.${name}(${inputs}) answered two ways`)
      const run = maths.run
      if (run) {
        //? the call's place in the run: the function, then each input's bits, little-endian - as the Swift hashes it
        callBytes[0] = index
        for (let i = 0; i < inputs.length; i++) {
          callView.setFloat64(1 + 8 * i, Number(inputs[i]), true)
        }
        fnvBytes(run.hash, callBytes.subarray(0, 1 + 8 * inputs.length))
        run.calls += 1
      }
    }
    return answer
  }
}

/* ===== output ===== */

const BACKSLASH = String.fromCharCode(92)
function ascii(text) {
  let out = ''
  for (let i = 0; i < text.length; i++) {
    const unit = text.charCodeAt(i)
    out += unit < 0x7f ? text[i] : BACKSLASH + 'u' + unit.toString(16).padStart(4, '0')
  }
  return out
}
const flat = (value) => ascii(JSON.stringify(value))
const primitive = (value) => value === null || typeof value !== 'object'
function laid(value, depth, indent = '') {
  if (primitive(value) || depth === 0 || (Array.isArray(value) && value.every(primitive))) return flat(value)
  const inner = indent + '  '
  if (Array.isArray(value)) {
    if (!value.length) return '[]'
    return '[\n' + value.map((item) => inner + laid(item, depth - 1, inner)).join(',\n') + '\n' + indent + ']'
  }
  const keys = Object.keys(value)
  if (!keys.length) return '{}'
  return '{\n' + keys.map((key) => inner + flat(key) + ': ' + laid(value[key], depth - 1, inner)).join(',\n') + '\n' + indent + '}'
}
const files = {}
const emit = (name, value, depth) => {
  files[name] = laid(value, depth) + '\n'
}
const MADE_BY = 'ios/scripts/export-deck-vectors.cjs - never edit by hand: change the TypeScript and run it again'

/** Doubles as base64 of their little-endian bytes. */
function f64s(values) {
  const bytes = Buffer.alloc(values.length * 8)
  values.forEach((value, i) => bytes.writeDoubleLE(value, i * 8))
  return bytes.toString('base64')
}

/* ===== the web's own modules ===== */

const load = (file) => require(path.join(OUT, file))
const platter = load('lib/platter.js')
const voice = load('lib/deckVoice.js')
const tt = load('lib/turntable.js')
const speed = load('lib/playSpeed.js')
const deckClock = load('lib/deckClock.js')
const debugRows = load('lib/debugRows.js')
const motions = load('lab/motions.js')

/* ===== jsmath.json: the helpers of 4.2 against Node ===== */

function jsmathFixture() {
  const cases = [0.5, -0.5, 1.5, -1.5, 2.5, -2.5, 0.49999999999999994, -0.49999999999999994, 2 ** 52 - 0.5, -(2 ** 52 - 0.5),
    2 ** 52, 2 ** 52 + 1, 2 ** 53, -(2 ** 53), 2 ** 53 + 2, 0, -0, NaN, Infinity, -Infinity, 1e-300, -1e-300, 0.1, -0.1, 0.7, -0.7,
    71.99999999999999, 72, 72.00000000000001, 4.5, 5.5, -4.5, 1.7976931348623157e308, -1.7976931348623157e308, 5e-324, -5e-324,
    3.4028234663852886e38, 3.4028235677973366e38, 1.401298464324817e-45, 7.006492321624085e-46, 0.1 + 0.2, 1 / 3, Math.PI, 123456.789]
  const pairs = []
  for (const a of [0, -0, 1, -1, NaN, Infinity, -Infinity, 0.5, 2 ** 53]) for (const b of [0, -0, 1, -1, NaN, Infinity, -Infinity, 0.5]) pairs.push([a, b])
  const indices = [0, 1, -1, 1023, 1024, -1024, 1025, -1025, 2 ** 31 - 1, 2 ** 31, -(2 ** 31), -(2 ** 31) - 1, 2 ** 32, 2 ** 32 + 5, -(2 ** 32) - 5,
    2 ** 53, 2 ** 53 + 2, 3.7, -3.7, 1e20, -1e20, NaN, Infinity, -Infinity, -0, 4294967295.5, 8191, 8192, -8193, 123456789012]
  return {
    about: 'Math.round, Math.fround over awkward numbers; Math.min and Math.max over pairs (NaN and -0 among them); ToInt32 (x | 0) and the masks the voice indexes with (x & 1023, x & 8191) - as Node answers them.',
    made_by: MADE_BY,
    round: cases.map((x) => [d(x), d(Math.round(x))]),
    fround: cases.map((x) => [d(x), d(Math.fround(x))]),
    minmax: pairs.map(([a, b]) => [d(a), d(b), d(Math.min(a, b)), d(Math.max(a, b))]),
    int32: indices.map((x) => [d(x), x | 0, x & 1023, x & 8191]),
  }
}

/* ===== tokens.json: the turntable's tokens, out of theme.css ===== */

const TOKENS = ['tt-plinth', 'tt-platter', 'tt-vinyl', 'tt-grooves', 'tt-sheen', 'tt-label', 'tt-label-edge', 'tt-spindle', 'tt-spindle-edge',
  'tt-arm', 'tt-arm-head', 'tt-arm-weight', 'tt-pivot', 'tt-pivot-edge', 'tt-handle-edge', 'track', 'border', 'text-3', 'green-icon',
  'accent', 'accent-text', 'toggled-bg', 'toggled-border', 'well', 'well-inset', 'highlight', 'secondary-bg', 'secondary-bg-active',
  'secondary-border', 'text-on-secondary', 'text-2']

function tokensFixture() {
  const css = fs.readFileSync(path.join(REPO, 'interface', 'styles', 'theme.css'), 'utf8')
  const valueOf = (name) => {
    const found = css.match(new RegExp(`--${name}:\\s*([^;]+);`))
    if (!found) throw new Error(`theme.css has no --${name}`)
    const value = found[1].trim()
    const alias = value.match(/^var\(--([\w-]+)\)$/)
    return alias ? valueOf(alias[1]) : value
  }
  //? every colour a value names, in order: #rrggbb and rgba(r, g, b, a), as [r, g, b, a] (a 1 for a hex)
  const colours = (value) => [...value.matchAll(/#([0-9a-fA-F]{6})\b|rgba\(\s*(\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\s*\)/g)].map((m) => (m[1]
    ? [parseInt(m[1].slice(0, 2), 16), parseInt(m[1].slice(2, 4), 16), parseInt(m[1].slice(4, 6), 16), 1]
    : [Number(m[2]), Number(m[3]), Number(m[4]), Number(m[5])]))
  const tokens = {}
  for (const name of TOKENS) {
    const value = valueOf(`dw-${name}`)
    tokens[`--dw-${name}`] = { value, colours: colours(value) }
  }
  return {
    about: 'interface/styles/theme.css: each token the turntable and the fader are drawn in (the spec\'s 2.14), its value (a var() followed), and the colours it names in order as [r, g, b, alpha].',
    made_by: MADE_BY,
    made_from: { 'interface/styles/theme.css': sha256(css) },
    tokens,
  }
}

/* ===== platter.json ===== */

const planOut = (plan) => ({
  phases: plan.phases.map((phase) => (phase.kind === 'pull' ? ['pull', d(phase.x0), d(phase.v0), d(phase.a), d(phase.duration)]
    : phase.kind === 'decay' ? ['decay', d(phase.x0), d(phase.v0), d(phase.base), phase.sign, d(phase.c), d(phase.k), d(phase.duration)]
      : ['rest', d(phase.x0), d(phase.duration)])),
  duration: d(plan.duration), x: d(plan.x), v: d(plan.v), target: d(plan.target), clamped: plan.clamped,
})

function platterFixture() {
  //? deck.sim's flicks (its "where it lands" check, :186-190): fourteen by hand, forty from its seeded generator
  const cases = [[100, 9, false], [100, -4, false], [100, 0.3, false], [100, 20, false], [100, 9, true], [100, -3, true], [100, 0, true],
    [100, 2.5, true], [100, -0.4, true], [100, 24, true], [0.3, -5, true], [1.2, -6, false], [423.5, 9, false], [424, 9, true]]
  let rng = 7
  const random = () => ((rng = (rng * 1103515245 + 12345) % 2147483648) / 2147483648)
  for (let i = 0; i < 40; i++) cases.push([random() * 425, (random() - 0.4) * 30, random() < 0.5])
  const flicks = []
  for (const [x, v, on] of cases) {
    for (const target of on ? [0.25, 0.5, 1, 1.5, 2] : [null]) {
      const plan = on ? platter.motor(x, v, 425, target) : platter.coast(x, v, 425)
      const times = [-0.1]
      for (let k = 0; k < 32; k++) times.push((plan.duration * k) / 28)
      flicks.push({
        x: d(x), v: d(v), motor: on, target: d(target), plan: planOut(plan),
        at: f64s(times.flatMap((t) => { const { x: at, v: speedThere } = platter.planAt(plan, t); return [t, at, speedThere] })),
        phases: plan.phases.map((phase) => f64s([0, phase.duration / 2, phase.duration, phase.duration + 1].flatMap((t) => { const r = platter.phaseAt(phase, t); return [t, r.x, r.v] }))),
      })
    }
  }
  //? the odd ends: lengths of none and NaN, speeds not finite, a start out of the song
  const odd = []
  for (const [x, v, length, target] of [[10, 5, 0, 1], [10, -5, 0, 1], [NaN, 3, 425, 1], [500, 3, 425, 1], [-5, -3, 425, 1], [10, Infinity, 425, 1], [10, NaN, 425, 1],
    [10, 1, 425, 1], [10, 0, 425, 1], [10, 30, 425, 1], [10, -30, 425, 2], [424.6, 0.5, 425, 1], [0.01, -0.5, 425, 0.25]]) {
    odd.push({ x: d(x), v: d(v), length: d(length), target: d(target), motor: planOut(platter.motor(x, v, length, target)), coast: planOut(platter.coast(x, v, length)) })
  }
  //? the hand's speed over deck.sim's sample sets (:270-294), each asked at its own times
  const turnPerSecond = (time) => ({ time, turned: (time / 1000) * 2 * Math.PI })
  const steady = [0, 16, 32, 48, 64, 80, 96, 112, 128].map(turnPerSecond)
  const sets = {
    steady,
    backwards: steady.map((s) => ({ ...s, turned: -s.turned })),
    slowThenFast: [{ time: 0, turned: 0 }, { time: 500, turned: 0.1 }, { time: 590, turned: 0.1 + Math.PI }],
    one: [{ time: 0, turned: 0 }],
    none: [],
    jump: [{ time: 0, turned: 0 }, { time: 1, turned: 100 }],
    repeated: [{ time: 0, turned: 0 }, { time: 10, turned: 0.2 }, { time: 10, turned: 0.3 }, { time: 30, turned: 0.25 }, { time: 31, turned: 0.25 }],
  }
  const speeds = []
  for (const [name, samples] of Object.entries(sets)) {
    const times = [-50, 0, 1, 10, 30, 45, 90, 128, 128 + 30, 128 + 40, 128 + 45, 128 + 65, 128 + 90, 128 + 400, 500, 545, 590, 600, 650, 700]
    speeds.push({
      name, samples: samples.map((s) => [d(s.time), d(s.turned)]),
      at: times.map((time) => [d(time), d(platter.handSpeed(samples, time)), d(platter.releaseSpeed(samples, time)), d(platter.handSpeed(samples, time, 45)), d(platter.releaseSpeed(samples, time, 45, 10))]),
    })
  }
  const acceleration = []
  for (const v of [-30, -2, -1e-9, -0, 0, 1e-9, 0.25, 0.5, 1, 1.5, 2, 3, 24]) {
    for (const [on, target] of [[false, 1], [true, 1], [true, 0.25], [true, 2]]) acceleration.push([d(v), on, d(target), d(platter.acceleration(v, on, target))])
  }
  return {
    about: 'lib/platter.ts: deck.sim\'s 54 flicks (14 by hand, 40 from its generator; with the motor at targets 0.25, 0.5, 1, 1.5 and 2, coasts once) - each plan (phases as [kind, ...fields]), planAt at -0.1 s and 32 points from 0 past the end (base64 doubles, t, x, v for each), phaseAt of each phase at 0, half way, its end and a second past (the same); plans at the odd ends; handSpeed and releaseSpeed over deck.sim\'s sample sets ([time, handSpeed, releaseSpeed, handSpeed with a 45 ms window, releaseSpeed with 45 and a 10 ms tail]); acceleration ([v, motor on, target, answer]).',
    made_by: MADE_BY,
    made_from: Object.fromEntries([whole('lib/platter.ts')]),
    constants: {
      SPIN_UP_S: d(platter.SPIN_UP_S), SPIN_DOWN_S: d(platter.SPIN_DOWN_S), MOTOR_PULL: d(platter.MOTOR_PULL), FRICTION_VISCOUS: d(platter.FRICTION_VISCOUS),
      FRICTION_DRY: d(platter.FRICTION_DRY), END_MARGIN_S: d(platter.END_MARGIN_S), VELOCITY_WINDOW_MS: d(platter.VELOCITY_WINDOW_MS), MAX_SPEED: d(platter.MAX_SPEED),
      DEGREES_PER_SECOND: d(platter.DEGREES_PER_SECOND), RELEASE_TAIL_MS: d(platter.RELEASE_TAIL_MS),
    },
    flicks, odd, speeds, acceleration,
  }
}

/* ===== turntable.json ===== */

function turntableFixture() {
  const BOXES = [{ left: 0, top: 0, width: 372, height: 368 }, { left: 16, top: 120, width: 343, height: 339.31182795698925 }, { left: 20.5, top: 98, width: 288, height: 284.9032258064516 }, { left: -3, top: 7, width: 744, height: 736 }]
  const geometry = {
    STAGE: tt.STAGE, PLATTER: tt.PLATTER, RECORD: tt.RECORD, GROOVES: tt.GROOVES, ARM: tt.ARM, ARM_PARTS: tt.ARM_PARTS, TAP_SLOP_PX: tt.TAP_SLOP_PX,
    SPINDLE_SHARE: d(tt.SPINDLE_SHARE), SECONDS_PER_TURN: d(tt.SECONDS_PER_TURN), FADER: speed.FADER, READOUT: speed.READOUT, FADER_FROM: d(speed.FADER_FROM),
    places: {
      platter: tt.placeCircle(tt.PLATTER), record: tt.placeCircle(tt.RECORD), label: tt.placeCircle({ ...tt.RECORD, r: tt.GROOVES.inner - 4 }),
      spindle: tt.placeCircle({ ...tt.RECORD, r: tt.SPINDLE_SHARE * tt.RECORD.r }), pivot: tt.placePoint({ x: tt.ARM.x, y: tt.ARM.y }),
      readout: tt.placePoint(speed.READOUT), handle: tt.across(tt.ARM_PARTS.handle), reach: tt.across(tt.ARM.reach), base: tt.across(tt.ARM_PARTS.base),
    },
  }
  const plinths = [372, 343, 288, 200, 744, 1e-12].map((stage) => ({ stage: d(stage), faderTarget: mapD(speed.faderTarget(stage)), faderTarget60: mapD(speed.faderTarget(stage, 60, 0.2)), faderTravel: d(speed.faderTravel(stage * (368 / 372))) }))
  const toStage = []
  for (const box of [...BOXES, { left: 0, top: 0, width: 0, height: 100 }, { left: 0, top: 0, width: NaN, height: 100 }]) {
    for (const [x, y] of [[0, 0], [178, 182], [400, -20], [box.left + 10.25, box.top + 300.5]]) toStage.push([mapD(box), d(x), d(y), mapD(tt.toStage(x, y, box))])
  }
  const lengths = [425, 0, -1, NaN, 30.5, 7200]
  const times = [0, 1, 60.25, 212.5, 424, 425, 500, -3, NaN]
  const arm = []
  for (const length of lengths) for (const time of times) arm.push([d(time), d(length), d(tt.grooveRadius(time, length)), mapD(tt.needleAt(time, length)), d(tt.armAngle(time, length))])
  const armTimes = []
  for (const length of lengths) for (const angle of [-180, -135, -120, -110, -100, -95, -90, 0, 45, 90, 179.99, 180, 360, 725, -725, NaN]) armTimes.push([d(angle), d(length), d(tt.armTimeAt(angle, length))])
  const pivot = [[178, 182], [348, 32], [100, 300], [348, 400], [0, 32]].map(([x, y]) => [d(x), d(y), d(tt.angleFromPivot({ x, y }))])
  //? the drags: record and arm, through the slop, round the spindle, past either end - each step's drag, and the
  //? previews, words and ends read off it
  const drags = []
  const dragOut = (drag) => (drag ? (drag.kind === 'record'
    ? { kind: 'record', pointer: drag.pointer, track: drag.track, x0: d(drag.x0), y0: d(drag.y0), travel: d(drag.travel), angle: d(drag.angle), turned: d(drag.turned), offset: d(drag.offset) }
    : { kind: 'arm', pointer: drag.pointer, track: drag.track, x0: d(drag.x0), y0: d(drag.y0), travel: d(drag.travel), grab: d(drag.grab), time: d(drag.time) }) : null)
  const previewOut = (p) => (p ? (p.how === 'record' ? { how: 'record', offset: d(p.offset) } : p.how === 'arm' ? { how: 'arm', time: d(p.time) } : { how: 'deck', at: d(p.at), scrubbing: p.scrubbing }) : null)
  const rng = seededLcg(1234)
  for (let run = 0; run < 24; run++) {
    const box = BOXES[run % BOXES.length]
    const kind = run % 3 === 2 ? 'arm' : 'record'
    const length = [425, 425, 30, 0][run % 4]
    let position = [151, 0.2, 29.5, 10][run % 4]
    const scale = box.width / 372
    const start = kind === 'arm'
      ? { x: box.left + (tt.ARM.x + (tt.ARM.reach - 30) * Math.cos(2.1)) * scale, y: box.top + (tt.ARM.y + (tt.ARM.reach - 30) * Math.sin(2.1)) * scale }
      : { x: box.left + (tt.RECORD.x + (run % 5 === 4 ? 10 : 100) * Math.cos(run)) * scale, y: box.top + (tt.RECORD.y + (run % 5 === 4 ? 10 : 100) * Math.sin(run)) * scale }
    let drag = kind === 'arm' ? tt.armStart(1, 'song', start.x, start.y) : tt.recordStart(1, 'song', start.x, start.y, box)
    const steps = [{ op: 'start', x: d(start.x), y: d(start.y), drag: dragOut(drag) }]
    let x = start.x, y = start.y
    for (let k = 0; k < 30; k++) {
      x += (rng() - 0.45) * 14 * scale
      y += (rng() - 0.5) * 14 * scale
      if (k === 12 && run % 6 === 1) { x = box.left + tt.RECORD.x * scale; y = box.top + tt.RECORD.y * scale }
      const pointer = k === 20 && run % 7 === 3 ? 2 : 1
      if (k % 9 === 8) position += 0.25
      const next = kind === 'arm' ? tt.armMove(drag, pointer, x, y, box, length, position) : tt.recordMove(drag, pointer, x, y, box, length, position)
      const previewing = tt.preview(next)
      steps.push({
        op: 'move', pointer, x: d(x), y: d(y), position: d(position), same: next === drag, drag: dragOut(next), moved: tt.moved(next),
        preview: previewOut(previewing), shown: d(tt.shownTime(previewing, position, length)), words: tt.previewWords(previewing),
      })
      drag = next
    }
    const ends = ['up', 'cancel'].map((how) => { const end = tt.dragEnd(drag, 1, how, position, length); return { how, drag: dragOut(end.drag), seek: d(end.seek), wasDrag: end.wasDrag } })
    const other = tt.dragEnd(drag, 9, 'up', position, length)
    drags.push({ kind, box: mapD(box), length: d(length), steps, ends, otherPointer: { same: other.drag === drag, seek: d(other.seek), wasDrag: other.wasDrag }, dragFor: [tt.dragFor(drag, 'song') === drag, tt.dragFor(drag, 'other')] })
  }
  const previews = [null, { how: 'record', offset: 3.5 }, { how: 'record', offset: -500 }, { how: 'arm', time: null }, { how: 'arm', time: 12.5 }, { how: 'deck', at: 99.98, scrubbing: true }, { how: 'deck', at: -4, scrubbing: false }, { how: 'deck', at: 1000, scrubbing: false }]
  const shown = []
  for (const p of previews) for (const [position, length] of [[151, 425], [0, 0], [-2, 0], [NaN, 0], [500, 425], [12, NaN]]) shown.push([previewOut(p), d(position), d(length), d(tt.shownTime(p, position, length)), tt.previewWords(p)])
  const same = []
  for (const a of previews) for (const b of previews) same.push([previewOut(a), previewOut(b), tt.samePreview(a, b)])
  same.push([previewOut(previews[1]), previewOut({ how: 'record', offset: 3.5 }), tt.samePreview(previews[1], { how: 'record', offset: 3.5 })])
  const discs = [[[{ id: 'a', discNumber: 2 }, { id: 'b' }], 'a'], [[{ id: 'a', discNumber: 2 }, { id: 'b' }], 'b'], [[{ id: 'a', discNumber: 2.7 }], 'a'], [[{ id: 'a', discNumber: 0 }], 'a'],
    [[{ id: 'a', discNumber: NaN }], 'a'], [null, 'a'], [[], 'a'], [[{ id: 'a', discNumber: -3 }], 'a'], [[{ id: 'a', discNumber: Infinity }], 'a']]
    .map(([songs, id]) => [songs ? songs.map((s) => ({ id: s.id, discNumber: s.discNumber === undefined ? null : d(s.discNumber) })) : null, id, tt.playingDisc(songs, id)])
  const discArt = [['al-1', 1], ['al 2/é&?', 3], [null, 1], ['', 2], ['x', 0], ['x', 2.5], ['x', -1]].map(([album, disc]) => [album, d(disc), tt.discArtPath(album, disc)])
  //? the fader
  const speedsIn = [0.25, 0.2, 2, 2.5, 1, 1.02, 1.0200000001, 0.98, 0.979, 1.25, 0.5, 1.5, 0.333, 1.005, 1.015, 0.255, NaN, Infinity, -Infinity, 0, -1]
  const fader = {
    constants: { SPEED_MIN: d(speed.SPEED_MIN), SPEED_MAX: d(speed.SPEED_MAX), SPEED_NORMAL: d(speed.SPEED_NORMAL), SPEED_DETENT: d(speed.SPEED_DETENT), SPEED_STEP: d(speed.SPEED_STEP), SPEED_PAGE: d(speed.SPEED_PAGE) },
    speeds: speedsIn.map((s) => [d(s), d(speed.roundSpeed(s)), d(speed.clampSpeed(s)), d(speed.detent(s)), d(speed.faderShare(s)), speed.knobTop(s), speed.speedLabel(s), speed.speedWords(s)]),
    shares: [-1, 0, 0.001, 0.25, 0.3, 0.5, 0.6666, 0.75, 0.99, 1, 1.5, NaN].map((share) => [d(share), d(speed.speedAt(share))]),
    keys: [],
    drags: [],
  }
  for (const key of ['ArrowUp', 'ArrowRight', 'ArrowDown', 'ArrowLeft', 'PageUp', 'PageDown', 'Home', 'End', 'Enter', 'a']) for (const s of [1, 0.25, 2, 1.99, 0.3, 1.234]) fader.keys.push([key, d(s), d(speed.speedKey(key, s))])
  //? the speedAt `**` written as Math.pow above: the original operator gives the same on every share asked
  for (let i = 0; i <= 1000; i++) {
    const share = i / 1000
    if (Math.pow(8, share) !== 8 ** share) throw new Error(`Math.pow and ** differ at ${share}`)
  }
  for (let run = 0; run < 8; run++) {
    const r = seededLcg(77 + run)
    let drag = speed.faderStart(1, 200)
    let current = [1, 0.5, 2, 1.25, 0.25, 1, 1.5, 0.75][run]
    const travel = [168, 100, 0, 220, 168, -5, 168, 50][run]
    const steps = []
    let y = 200
    for (let k = 0; k < 20; k++) {
      y += (r() - 0.5) * 30
      const pointer = k === 7 && run === 3 ? 2 : 1
      const out = speed.faderMove(drag, pointer, y, travel, current)
      steps.push([pointer, d(y), d(travel), d(current), out.drag === drag, out.drag && out.drag.from ? [d(out.drag.from.y), d(out.drag.from.share)] : null, d(out.speed)])
      drag = out.drag
      if (out.speed !== null) current = out.speed
    }
    fader.drags.push({ steps, end: [speed.faderEnd(drag, 1) === null, speed.faderEnd(drag, 2) === drag] })
  }
  //? pointerSamples: coalesced lists with repeats, reversals, other pointers and stale stamps
  const pointerCases = []
  const prng = seededLcg(5)
  for (let run = 0; run < 30; run++) {
    const now = 5000 + run * 100
    const list = []
    let t = now - 40
    for (let k = 0; k < 6; k++) {
      t += prng() < 0.2 ? -3 : prng() < 0.3 ? 0 : 4
      const x = prng() < 0.3 && list.length ? list[list.length - 1].clientX : Math.round(prng() * 100)
      const y = prng() < 0.3 && list.length ? list[list.length - 1].clientY : Math.round(prng() * 100)
      list.push({ pointerId: prng() < 0.1 ? 2 : 1, timeStamp: run % 10 === 9 ? now - 2000 : run % 10 === 8 ? now + 5 : t, clientX: x, clientY: y })
    }
    const last = list[list.length - 1]
    const event = run % 4 === 3 ? { pointerId: 1, timeStamp: now, clientX: 50, clientY: 50 } : { ...last, pointerId: 1 }
    const withList = run % 5 === 4 ? { ...event } : { ...event, getCoalescedEvents: () => list }
    pointerCases.push({
      now: d(now), event: [event.pointerId, d(event.timeStamp), d(event.clientX), d(event.clientY)], coalesced: run % 5 === 4 ? null : list.map((s) => [s.pointerId, d(s.timeStamp), d(s.clientX), d(s.clientY)]),
      samples: deckClock.pointerSamples(withList, now).map((s) => [d(s.time), d(s.x), d(s.y)]),
    })
  }
  const eventTimes = [[1000, 1000], [1000.5, 1000], [1001, 1000], [1001.0001, 1000], [0, 1000], [-1, 999], [NaN, 1000], [null, 1000], [Infinity, 1000]].map(([stamp, now]) => [d(stamp), d(now), d(deckClock.eventTime(stamp, now))])
  return {
    about: 'lib/turntable.ts and lib/playSpeed.ts: the drawing\'s geometry (CSS percentages as the web writes them) and the fader\'s target at plinth sizes; toStage; grooveRadius, needleAt and armAngle ([time, length, radius, needle, angle]); armTimeAt ([angle, length, time]); angleFromPivot; 24 seeded drags (record and arm, through the slop, onto the spindle, another pointer) with each step\'s drag, preview, shownTime and previewWords, and both ends; shownTime and previewWords over previews; samePreview; playingDisc and discArtPath; the fader\'s speeds ([speed, roundSpeed, clampSpeed, detent, faderShare, knobTop, speedLabel, speedWords]), speedAt, speedKey and seeded fader drags ([pointer, y, travel, speed, unchanged, from, answer]); lib/deckClock.ts pointerSamples and eventTime.',
    made_by: MADE_BY,
    made_from: Object.fromEntries([whole('lib/turntable.ts'), whole('lib/playSpeed.ts'), whole('lib/deckClock.ts')]),
    geometry, plinths, toStage, arm, armTimes, pivot, drags, shown, same, discs, discArt, fader, pointerSamples: pointerCases, eventTimes,
    timeLines: [[0, 425, null], [151.9, 425, 'arm'], [151.9, 425, 'record'], [3600, 0, null], [59.99, 0, 'record'], [-1, 425, null]].map(([time, length, how]) => [d(time), d(length), how, tt.timeLine(time, length, how)]),
  }
  function mapD(object) {
    return Object.fromEntries(Object.entries(object).map(([key, value]) => [key, d(value)]))
  }
}
function seededLcg(seed) {
  let state = seed
  return () => (state = (state * 1103515245 + 12345) % 2147483648) / 2147483648
}

/* ===== words.json ===== */

function wordsFixture() {
  const turntableTsx = 'player/Turntable.tsx'
  const recordLabel = piece(turntableTsx, /aria-label=\{player\.playing \? '([^']+)' : '([^']+)'\}/, 'the record\'s aria-label')
  const armLabel = piece(turntableTsx, /aria-label="(Tonearm[^"]*)"/, 'the arm\'s aria-label')
  const armValue = piece(turntableTsx, /aria-valuetext=\{`\$\{clock\(shown\)\} of \$\{clock\(length\)\}`\}/, 'the arm\'s aria-valuetext')
  const readout = piece('player/SpeedFader.tsx', /aria-label=\{normal \? '([^']+)' : `Speed \$\{speedLabel\(speed\)\}: back to normal speed`\}/, 'the readout\'s aria-label')
  const chip = piece('player/SpeedChip.tsx', /aria-label=\{`\$\{speedLabel\(speed\)\}, \$\{speedWords\(speed\)\} the song's speed: back to normal speed`\}/, 'the chip\'s aria-label')
  const faderName = piece('player/SpeedFader.tsx', /aria-label="(Speed)"/, 'the fader\'s aria-label')
  const looks = piece('app/LookChoice.tsx', /\{ look: 'cover', label: '([^']+)' \},\s*\{ look: 'turntable', label: '([^']+)' \}/, 'LOOKS')
  const opensAs = piece('app/LookChoice.tsx', /class="app-choice-title">([^<]+)</, 'the choice\'s title')
  const windDown = piece('app/WindDownChoice.tsx', /class="app-check-label">([^<]+)</, 'the check\'s label')
  const note = (id) => {
    const found = piece('app/You.tsx', new RegExp(`<p id="${id}"[^>]*>([\\s\\S]*?)</p>`), `the ${id} paragraph`)
    return { text: found.text.match(/>([\s\S]*?)</)[1].replace(/\s+/g, ' ').trim(), from: found.from }
  }
  const lookNote = note('app-look-note'), windDownNote = note('app-wind-down-note')
  //? the DeckReports turntableRows reads: seeded, every branch reached
  const r = seededLcg(4040)
  const pick = (list) => list[Math.floor(r() * list.length)]
  const reports = [null]
  for (let i = 0; i < 40; i++) {
    const context = i < 6 ? ['none', 'starting', 'running', 'unsupported', 'no-voice', 'failed'][i] : pick(['none', 'starting', 'running', 'running', 'running', 'failed'])
    const voice = pick(['worklet', 'worklet', 'script', null])
    const ms = (scale) => Math.round(r() * scale * 1000) / 1000
    const report = {
      context, problem: r() < 0.5 ? null : pick(['the sound couldn\'t start - NotAllowedError', 'the AudioWorklet couldn\'t be made (x)', '']),
      voice, voiceWhy: voice === 'script' ? pick([null, "this page isn't on HTTPS, so the browser has no AudioWorklet"]) : null,
      window: r() < 0.6 ? { start: Math.floor(r() * 400), end: Math.floor(r() * 400) + 40.5, kind: pick(['FLAC', 'MP3', '']), decodedAt: pick([44100, 48000, 96000, 22050]), bytes: Math.floor(r() * 9e6) } : null,
      loading: r() < 0.3, refused: r() < 0.2 ? pick(["it isn't a FLAC file (it is MP3)", 'deadwax can\'t make it a window', '']) : null,
      failed: r() < 0.25 ? pick(['deadwax said that is past the end of the song', "deadwax didn't send it - Failed to fetch"]) : null,
      fetched: r() < 0.3 ? 0 : Math.floor(r() * 3e7), lastFetchAt: Math.floor(r() * 600000), clockStep: pick([undefined, 0, 0.0213333, 0.00266, 0.0106667]),
      health: r() < 0.15 ? undefined : {
        blocks: pick([0, 0, 1200]), lateBlocks: pick([0, 3, 1]), worstBlockMs: ms(40), frames: pick([0, 340, 1]), slowFrames: pick([0, 0, 12, 1]), worstFrameMs: ms(90),
        backMs: pick([null, 412.3, 1234.5, 15000]), motorMs: pick([null, 0, 400, 12000]), notBack: pick([0, 0, 1, 3]), interruptions: pick([0, 1, 2]),
        peaksHeld: pick([0, 1, 17, undefined]), samplesHeld: pick([0, 1, 233]), deepestHoldDb: pick([0, 0.04, 0.05, 2.37]),
      },
      latency: r() < 0.2 ? undefined : r() < 0.1 ? null : {
        base: pick([null, 0.0053, 0.01]), output: pick([null, 0.0213]), speaker: pick([null, 0.0425]), block: pick([null, 512, 1024, 128]), design: pick([null, 0.1215, 0.14283, 0.1642]),
      },
    }
    reports.push(report)
  }
  const reportOut = (report) => (report ? {
    ...report,
    window: report.window ? { ...report.window, start: d(report.window.start), end: d(report.window.end), decodedAt: d(report.window.decodedAt), bytes: d(report.window.bytes) } : null,
    fetched: d(report.fetched), lastFetchAt: d(report.lastFetchAt), clockStep: report.clockStep === undefined ? null : d(report.clockStep),
    health: report.health ? Object.fromEntries(Object.entries(report.health).map(([key, value]) => [key, d(value)])) : null,
    latency: report.latency ? Object.fromEntries(Object.entries(report.latency).map(([key, value]) => [key, d(value)])) : null,
  } : null)
  const rowOut = (row) => [row.label, row.value, row.note ?? null]
  const readings = [null, { speed: 1, rate: 1, pitch: 'moves', refused: null, measured: null }, { speed: 1.25, rate: 1.25, pitch: 'moves', refused: null, measured: 1.2468 },
    { speed: 1.25, rate: 1.25, pitch: 'held', refused: null, measured: null }, { speed: 0.5, rate: 0.5, pitch: 'no switch', refused: null, measured: 0.49 },
    { speed: 0.75, rate: 1, pitch: 'moves', refused: null, measured: null }, { speed: 2, rate: 2, pitch: 'moves', refused: 'NotSupportedError', measured: 1.98 },
    { speed: 1.5, rate: 1.5000001, pitch: 'moves', refused: '', measured: null }, { speed: 0.25, rate: 0.25, pitch: 'held', refused: null, measured: 0 }]
  return {
    about: 'Every word of the spec\'s 2.9 the web makes, with its inputs: the look button, the record and the arm (Turntable.tsx\'s labels, read out of its source), the time line, the silent words and note, the fader\'s words (playSpeed.ts, SpeedFader.tsx, SpeedChip.tsx), You > Playback\'s labels and notes; debugRows.ts turntableRows and latencyNote over 41 DeckReports (null first), and speedRow - rows as [label, value, note].',
    made_by: MADE_BY,
    made_from: Object.fromEntries([whole('lib/turntable.ts'), whole('lib/playSpeed.ts'), whole('lib/debugRows.ts'), recordLabel.from, armLabel.from, armValue.from,
      readout.from, chip.from, faderName.from, looks.from, opensAs.from, windDown.from, lookNote.from, windDownNote.from]),
    lookButton: { cover: tt.lookButtonLabel('cover'), turntable: tt.lookButtonLabel('turntable') },
    record: { playing: recordLabel.text.match(/'([^']+)'/g)[0].slice(1, -1), paused: recordLabel.text.match(/'([^']+)'/g)[1].slice(1, -1) },
    arm: armLabel.text.match(/"([^"]+)"/)[1],
    armValues: [[151.9, 425], [0, 0], [3725, 7200.5]].map(([shown, length]) => [d(shown), d(length), `${speedClock(shown)} of ${speedClock(length)}`]),
    timeLines: [[0, 425, null], [151.9, 425, 'arm'], [151.9, 425, 'record'], [3600, 0, null], [59.99, 0, 'record'], [-1, 425, null], [NaN, 425, 'arm']].map(([time, length, how]) => [d(time), d(length), how, tt.timeLine(time, length, how)]),
    silent: { words: tt.SILENT_WORDS, notes: [[false, false], [true, false], [true, true], [false, true]].map(([flac, noAudio]) => [flac, noAudio, tt.silentNote(flac, noAudio)]) },
    speeds: [0.25, 0.5, 1, 1.004, 1.25, 1.333, 2, 0.999, 1.005].map((s) => [d(s), speed.speedLabel(s), speed.speedWords(s), s === 1 ? 'Speed: normal' : `Speed ${speed.speedLabel(s)}: back to normal speed`,
      `${speed.speedLabel(s)}, ${speed.speedWords(s)} the song's speed: back to normal speed`]),
    readoutNormal: readout.text.match(/'([^']+)'/)[1],
    fader: faderName.text.match(/"([^"]+)"/)[1],
    looks: { title: opensAs.text.match(/>([^<]+)</)[1], cover: looks.text.match(/label: '([^']+)'/g)[0].slice(8, -1), turntable: looks.text.match(/label: '([^']+)'/g)[1].slice(8, -1) },
    windDown: windDown.text.match(/>([^<]+)</)[1],
    notes: { look: lookNote.text, windDown: windDownNote.text },
    reports: reports.map((report) => ({ report: reportOut(report), rows: debugRows.turntableRows(report).map(rowOut), latency: debugRows.latencyNote(report) })),
    speedRows: readings.map((reading) => ({ reading: reading ? { ...reading, speed: d(reading.speed), rate: d(reading.rate), measured: d(reading.measured) } : null, row: rowOut(debugRows.speedRow(reading)) })),
  }
  function speedClock(seconds) {
    return load('lib/scrub.js').clock(seconds)
  }
}

/* ===== the run ===== */

async function main() {
  emit('jsmath.json', jsmathFixture(), 2)
  emit('tokens.json', tokensFixture(), 3)
  emit('platter.json', platterFixture(), 3)
  emit('turntable.json', turntableFixture(), 3)
  emit('words.json', wordsFixture(), 3)
  if (globalThis.__deckExtra) await globalThis.__deckExtra()
  maths.on = false
  emit('maths.json', mathsFixture(), 2)

  fs.rmSync(OUT, { recursive: true, force: true })
  const total = Object.values(files).reduce((sum, body) => sum + Buffer.byteLength(body), 0)
  if (CHECK) {
    const differ = []
    for (const [name, body] of Object.entries(files)) {
      const at = path.join(FIXTURES, name)
      if (!fs.existsSync(at)) differ.push(`${name} (missing)`)
      else if (!fs.readFileSync(at).equals(Buffer.isBuffer(body) ? body : Buffer.from(body))) differ.push(name)
    }
    const kept = listFiles(FIXTURES)
    const stray = kept.filter((name) => !(name in files))
    if (differ.length || stray.length) {
      if (differ.length) console.log(`The turntable's fixtures differ from what the web's TypeScript does now: ${differ.join(', ')}.`)
      if (stray.length) console.log(`Fixtures/deck holds files this script no longer writes: ${stray.join(', ')}.`)
      console.log('Run node ios/scripts/export-deck-vectors.cjs, and see what the Swift ports must follow.')
      process.exit(1)
    }
    if (total > BUDGET) {
      console.log(`The turntable's fixtures are ${Math.round(total / 1024)} KB, over their ${BUDGET / 1024} KB budget.`)
      process.exit(1)
    }
    console.log(`The turntable's ${Object.keys(files).length} fixtures match the web's TypeScript (${Math.round(total / 1024)} KB of ${BUDGET / 1024}).`)
    return
  }
  fs.rmSync(FIXTURES, { recursive: true, force: true })
  for (const [name, body] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(FIXTURES, name)), { recursive: true })
    fs.writeFileSync(path.join(FIXTURES, name), body)
  }
  console.log(`Wrote ${Object.keys(files).length} fixtures to ${path.relative(REPO, FIXTURES)}, ${Math.round(total / 1024)} KB of a ${BUDGET / 1024} KB budget`)
  if (total > BUDGET) {
    console.log('...over the budget: hash a case rather than drop it (the spec\'s 7.0).')
    process.exit(1)
  }
}

function listFiles(root, prefix = '') {
  if (!fs.existsSync(root)) return []
  const out = []
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (entry.isDirectory()) out.push(...listFiles(path.join(root, entry.name), `${prefix}${entry.name}/`))
    else out.push(`${prefix}${entry.name}`)
  }
  return out.sort()
}

/* ===== maths.json ===== */

function mathsFixture() {
  const table = {}
  for (const name of RECORDED) {
    const entries = [...maths.table[name].entries()].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    const bytes = Buffer.alloc(entries.length * 8 * (ARITY[name] + 1))
    entries.forEach(([key, answer], i) => {
      const words = [...key.match(/.{16}/g), answer]
      words.forEach((word, j) => bytes.writeBigUInt64LE(BigInt(`0x${word}`), (i * words.length + j) * 8))
    })
    table[name] = { calls: entries.length, bits: bytes.toString('base64') }
  }
  return {
    about: 'Every exp, log, sin, cos, atan2, hypot, pow and log10 the web\'s ported code evaluated while the other fixtures were made - each entry its inputs\' and its answer\'s bits, as base64 of little-endian 64-bit words ([input, answer] or [a, b, answer]), sorted by input. `runs`: for each voice run (voice/*.json, by its file and configuration), how many calls it made and an FNV-1a 64 hash of them in order (the function\'s number in exp, log, sin, cos, atan2, hypot, pow, log10, then each input\'s little-endian bytes).',
    made_by: MADE_BY,
    functions: RECORDED,
    table,
    runs: mathsRuns,
  }
}
const mathsRuns = {}

main().catch((caught) => {
  console.error(caught && caught.stack)
  process.exit(1)
})
