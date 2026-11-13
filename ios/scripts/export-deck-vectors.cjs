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
 *                   above, its inputs' and answer's bits (each voice run's count and order are in its own file)
 *   made.json       who made them: the Node, platform and arch (`made_on`), and this script's and its harness's
 *                   sha256 (`made_with`)
 *
 * Doubles are written as their IEEE bits in hex, then a space and the number as JavaScript writes it ("3ff8000000000000
 * 1.5"): the Swift reads the hex, a person the rest. Long runs of doubles are base64 of their little-endian bytes. Any
 * NaN is written as 0x7ff8000000000000 (setF64). Each file names the sources it was made from with their sha256
 * (`made_from`), so ui/test/iosdeck.sim.cjs - which runs this with --check - fails when one changes, in what it does
 * or only in its text, until the fixtures are written again and the Swift follows. The folder's budget is 3 MB
 * (iosdeck.sim checks it). Never edit a fixture by hand.
 *
 * --check makes everything again in memory. On the maker's Node, platform and arch (made.json) every file must be
 * the same byte for byte - a full check. On any other, the Math functions can answer otherwise, so a file whose
 * made_from is unchanged may differ by that alone and is listed, not failed - a sources-only check (`check`, below).
 * Write the fixtures on the maker's Node, so the files only its Math reaches stay as they are.
 *
 *   node ios/scripts/export-deck-vectors.cjs           write the fixtures (and make this Node their maker)
 *   node ios/scripts/export-deck-vectors.cjs --check   write nothing; exit 1 when a fixture differs where it must not
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
  'src/lib/deckClock.ts', 'src/lib/debugRows.ts', 'src/player/Turntable.tsx', 'src/player/NowPlaying.tsx', 'src/lab/motions.ts',
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
patch('player/deck.js', 'sleepDeckAudio();', 'globalThis.__deckTrace?.effect("sleep"); sleepDeckAudio();', 'setShowing\'s sleep')
patch('player/deck.js', 'closeDeckAudio();', 'globalThis.__deckTrace?.effect("close"); closeDeckAudio();', 'destroy\'s close')
patch('player/deck.js', 'function voiceReady() {', 'globalThis.__deckAudio = () => audio;\nfunction voiceReady() {', 'the audio, read')
//? the turntable's render, told what it drew - the press traces' (press/, below), and nothing else changed
patch('player/Turntable.js', 'const needle = (0, turntable_1.needleAt)(shown, length);', 'globalThis.__press?.rendered({ shown, handTurn, noAudio, position, length, track, flac: !!windows.current || (player.track ? (0, streamWrap_1.isFlac)(player.track) : false) });\n    const needle = (0, turntable_1.needleAt)(shown, length);', 'the render\'s values')

/* ===== a Math that records ===== */

const RECORDED = ['exp', 'log', 'sin', 'cos', 'atan2', 'hypot', 'pow', 'log10']
const REAL = Object.fromEntries(RECORDED.map((name) => [name, Math[name]]))
const ARITY = { exp: 1, log: 1, sin: 1, cos: 1, log10: 1, atan2: 2, hypot: 2, pow: 2 }
const maths = { on: true, table: Object.fromEntries(RECORDED.map((name) => [name, new Map()])), run: null }

const scratch = new DataView(new ArrayBuffer(8))
//? A NaN's bits are the CPU's - x64 makes 0xfff8000000000000 where arm64 makes 0x7ff8000000000000, and V8 passes
//? them through Math.min, Math.max and the arithmetic - and JavaScript can't see them. So every double and Float32 this
//? writes, in hex, base64 or a hash, goes through setF64 or setF32, which write any NaN as 0x7ff8000000000000 (a
//? Float32's as 0x7fc00000): the same bytes on every machine. The Swift tests write theirs the same way.
const NAN_HIGH = 0x7ff80000, NAN32 = 0x7fc00000
function setF64(view, at, x, little = false) {
  if (x !== x) {
    view.setUint32(at + (little ? 4 : 0), NAN_HIGH, little)
    view.setUint32(at + (little ? 0 : 4), 0, little)
  } else view.setFloat64(at, x, little)
}
function setF32(view, at, x, little = false) {
  if (x !== x) view.setUint32(at, NAN32, little)
  else view.setFloat32(at, x, little)
}
/** A view over a Buffer's own bytes. */
const viewOf = (bytes) => new DataView(bytes.buffer, bytes.byteOffset, bytes.length)
/** A double's bits, 16 hex digits. */
function hex(x) {
  setF64(scratch, 0, x)
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

/** A double from its bits, 16 hex digits. */
function fromHex(bits) {
  scratch.setUint32(0, parseInt(bits.slice(0, 8), 16))
  scratch.setUint32(4, parseInt(bits.slice(8), 16))
  return scratch.getFloat64(0)
}

//? The answers the committed fixtures were made with (maths.json), answered again to the same calls whichever Node
//? runs this: V8's Math is not the same in every version (sin and cos took glibc's code in 2023, behind a build
//? flag), and the fixtures are one V8's answers held together - the traces and the table the Swift replays them with.
//? Node's own answer is still worked out, and any that differs is counted (`drift`) and told. A call the table
//? doesn't hold - a new one, or one made while recording is off (the bench's motions, the harness's tone, the deck's
//? frames between a press trace's inputs: about 32,000, too many to keep) - is Node's, so a Node whose Math differs
//? still remakes those files otherwise, and --check fails naming the Math as why (the spec's 7.0).
const KEPT = keptAnswers()
const drift = Object.fromEntries(RECORDED.map((name) => [name, new Set()]))
function keptAnswers() {
  const kept = Object.fromEntries(RECORDED.map((name) => [name, new Map()]))
  const at = path.join(FIXTURES, 'maths.json')
  if (!fs.existsSync(at)) return kept
  let table
  try {
    table = JSON.parse(fs.readFileSync(at, 'utf8')).table
  } catch {
    return kept
  }
  for (const name of RECORDED) {
    const one = table && table[name]
    if (!one) continue
    const bytes = Buffer.from(one.bits, 'base64')
    const words = ARITY[name] + 1
    if (bytes.length !== one.calls * words * 8) continue
    for (let i = 0; i < one.calls; i++) {
      const bits = []
      for (let j = 0; j < words; j++) bits.push(bytes.readBigUInt64LE((i * words + j) * 8).toString(16).padStart(16, '0'))
      kept[name].set(bits.slice(0, -1).join(''), bits[words - 1])
    }
  }
  return kept
}

for (const name of RECORDED) {
  const real = REAL[name]
  const index = RECORDED.indexOf(name)
  const kept = KEPT[name]
  Math[name] = function recorded(...args) {
    let answer = real.apply(Math, args)
    const inputs = args.slice(0, ARITY[name])
    while (inputs.length < ARITY[name]) inputs.push(undefined)
    const key = inputs.map((x) => hex(Number(x))).join('')
    const was = kept.get(key)
    if (was !== undefined && was !== hex(answer)) {
      drift[name].add(key)
      answer = fromHex(was)
    }
    if (maths.on) {
      const table = maths.table[name]
      const had = table.get(key)
      if (had === undefined) table.set(key, hex(answer))
      else if (had !== hex(answer)) throw new Error(`Math.${name}(${inputs}) answered two ways`)
      const run = maths.run
      if (run) {
        //? the call's place in the run: the function, then each input's bits, little-endian - as the Swift hashes it
        callBytes[0] = index
        for (let i = 0; i < inputs.length; i++) {
          setF64(callView, 1 + 8 * i, Number(inputs[i]), true)
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
/** Each file's made_from, as written (maths.json's is all of theirs; --check compares them). */
const madeFrom = {}
const emit = (name, value, depth) => {
  if (!Buffer.isBuffer(value) && value.made_from) madeFrom[name] = value.made_from
  files[name] = Buffer.isBuffer(value) ? value : laid(value, depth) + '\n'
}
const MADE_BY = 'ios/scripts/export-deck-vectors.cjs - never edit by hand: change the TypeScript and run it again'
//? Who made the fixtures and with what (made.json): the Node, platform and CPU - the one thing besides the sources
//? that moves what they hold, through the Math functions' answers - and this script and its harness, by sha256.
const MADE_ON = { node: process.version, platform: process.platform, arch: process.arch }
const MADE_WITH = Object.fromEntries([
  ['ios/scripts/export-deck-vectors.cjs', __filename],
  ['ui/test/deckHarness.cjs', path.join(UI, 'test', 'deckHarness.cjs')],
].map(([name, at]) => [name, sha256(fs.readFileSync(at, 'utf8'))]))
//? The files no Math function's answer reaches - a check, the tokens, the windows' integer recipes, the handlers'
//? hashes - which must be the same on any machine.
const EXACT = new Set(['jsmath.json', 'tokens.json', 'voice/windows.json', 'press/handlers.json'])
const onText = (on) => `${on.node} ${on.platform}/${on.arch}`

/** Doubles as base64 of their little-endian bytes. */
function f64s(values) {
  const bytes = Buffer.alloc(values.length * 8)
  const view = viewOf(bytes)
  values.forEach((value, i) => setF64(view, i * 8, value, true))
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
    made_from: { 'ios/scripts/export-deck-vectors.cjs jsmathFixture': sha256(jsmathFixture.toString()) },
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
    //? the tokens read, not the whole file: theme.css is every page's, and a token the turntable doesn't use (2.1.8's,
    //? for You on a desktop) would otherwise make these fixtures stale - and fail iosdeck.sim on CI - with nothing in
    //? them moved. A change to any token here, or to what one aliases, still does.
    made_from: { 'interface/styles/theme.css, the tokens below': sha256(JSON.stringify(tokens)) },
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

/* ===== voice/: deckVoice.ts's four functions, run ===== */

//? THE WINDOWS, made from integer recipes both sides compute (the spec's 7.0): Int16 samples over 32768, two
//? different channels (or one), WINDOW_SECONDS long - never committed as PCM. Swift's DeckVoiceTests makes them the
//? same way and checks each against its hash here.
const WINDOW_SECONDS = 8
const windowCache = new Map()
function recipeChannel(kind, seed, ch, length) {
  const out = new Float32Array(length)
  let x = (seed * 2 + ch + 1) >>> 0
  let phase = 0
  const period = 2400 + seed * 7 + ch * 331
  const stepAt = Math.floor(length / 2) + ch * 9601
  for (let i = 0; i < length; i++) {
    let v = 0
    if (kind === 'noise' || kind === 'soft') {
      //? xorshift32
      x = (x ^ (x << 13)) >>> 0
      x = (x ^ (x >>> 17)) >>> 0
      x = (x ^ (x << 5)) >>> 0
      v = (x >>> 16) - 32768
      if (kind === 'soft') v >>= 3
    } else if (kind === 'sweep') {
      //? a triangle whose step rises every 128 samples, in integer steps
      phase = (phase + 1 + ((i >> 7) % 600) * (ch + 1)) & 0xffff
      v = phase < 32768 ? phase * 2 - 32768 : (65535 - phase) * 2 - 32767
    } else if (kind === 'clicks') {
      const at = i % period
      v = at === 0 ? 32767 : at === 1 ? -32768 : 0
    } else if (kind === 'step') {
      //? silence, then one full-scale step - for the DC blocker and the limiter
      v = i >= stepAt ? (ch === 0 ? 32767 : -32768) : 0
    }
    out[i] = v / 32768
  }
  return out
}
function recipeWindow(kind, seed, rate, channels) {
  const key = `${kind} ${seed} ${rate} ${channels}`
  if (!windowCache.has(key)) {
    const made = []
    for (let ch = 0; ch < channels; ch++) made.push(recipeChannel(kind, seed, ch, WINDOW_SECONDS * rate))
    const hash = [...FNV_START]
    for (const channel of made) fnvBytes(hash, new Uint8Array(channel.buffer))
    windowCache.set(key, { key: { kind, seed, rate, channels }, channels: made, hash: fnvHex(hash) })
  }
  return windowCache.get(key)
}

/** A case's message as the voice takes it: the window's channels made from its recipe. */
function toVoiceMessage(message) {
  if (message.type !== 'window') return message
  if (!message.window) return { type: 'window', channels: [], start: 0, rate: 48000 }
  const { kind, seed, channels, start, rate } = message.window
  return { type: 'window', channels: recipeWindow(kind, seed, rate, channels).channels, start, rate }
}
const messageOut = (m) => {
  const out = { post: d(m.post), type: m.type }
  for (const key of ['at', 'rate', 'accel', 'time', 'until', 'seconds']) if (key in m) out[key] = d(m[key])
  if (m.type === 'window') out.window = m.window ? { kind: m.window.kind, seed: m.window.seed, channels: m.window.channels, start: d(m.window.start), rate: d(m.window.rate) } : null
  return out
}

//? THE RUNS: each case at block sizes 128, 333, 512 and 1024 at 48 and 44.1 kHz, and in blocks of 1 over 2,000
//? frames from just before its first take; each block given `now` = its first frame over the rate, each message
//? applied before the first block whose `now` is at or past its post time, with that block's `now` (as a worklet
//? applies its port's messages between blocks)
const VOICE_CONFIGS = [[48000, 128], [48000, 333], [48000, 512], [48000, 1024], [44100, 128], [44100, 333], [44100, 512], [44100, 1024]]
const SPAN_FRAMES = 4096

function runVoice(messages, rate, block, from, frames, keep) {
  maths.run = { hash: [...FNV_START], calls: 0 }
  const state = voice.newVoiceState()
  const outs = [new Float32Array(block), new Float32Array(block)]
  const spans = []
  let span = [...FNV_START], inSpan = 0
  const reports = [], reportHash = [...FNV_START]
  let reportCount = 0
  //? `keep`: [first frame, how many] of the run's output to keep whole
  const kept = keep ? [new Float32Array(keep[1]), new Float32Array(keep[1])] : null
  const frameBytes = new Uint8Array(8), frameView = new DataView(frameBytes.buffer)
  const reportBytes = new Uint8Array(56), reportView = new DataView(reportBytes.buffer)
  const keepReports = rate === 48000 && block === 128
  let next = 0, done = 0
  while (done < frames) {
    const n = Math.min(block, frames - done)
    const now = (from + done) / rate
    while (next < messages.length && messages[next].post <= now) voice.voiceCommand(state, toVoiceMessage(messages[next++]), now, rate)
    voice.renderVoice(state, outs, n, rate, now)
    const heard = voice.voiceReport(state, n, rate, now, voice.REPORTS_PER_SECOND)
    for (let i = 0; i < n; i++) {
      setF32(frameView, 0, outs[0][i], true)
      setF32(frameView, 4, outs[1][i], true)
      fnvBytes(span, frameBytes)
      const k = done + i - (keep ? keep[0] : 0)
      if (kept && k >= 0 && k < keep[1]) {
        kept[0][k] = outs[0][i]
        kept[1][k] = outs[1][i]
      }
      if (++inSpan === SPAN_FRAMES) {
        spans.push(fnvHex(span))
        span = [...FNV_START]
        inSpan = 0
      }
    }
    if (heard) {
      const values = [heard.time, heard.pos, heard.rate, heard.gain, heard.held, heard.peaks, heard.lowest]
      reportCount += 1
      if (keepReports) reports.push(...values)
      values.forEach((value, i) => setF64(reportView, 8 * i, value, true))
      fnvBytes(reportHash, reportBytes)
    }
    done += n
  }
  if (inSpan) spans.push(fnvHex(span))
  const run = maths.run
  maths.run = null
  return {
    rate, block, from, frames, keep, spans,
    reports: { count: reportCount, hash: fnvHex(reportHash), whole: keepReports ? f64s(reports) : null },
    maths: { calls: run.calls, hash: fnvHex(run.hash) },
    kept,
  }
}

function voiceFixtures(cases) {
  const out = []
  for (const c of cases) {
    const messages = [...c.messages].sort((a, b) => a.post - b.post)
    const first = messages[0].post
    const takeAt = (messages.find((m) => m.type === 'take') ?? messages[0]).post
    const runs = []
    let wholeFile = null
    for (const [rate, block] of VOICE_CONFIGS) {
      const from = Math.floor((first - 0.01) * rate)
      //? at 48 kHz in blocks of 128, a stretch of the output kept whole for three of the cases
      const keep = c.whole && rate === 48000 && block === 128 ? [Math.floor(c.whole[0] * rate) - from, Math.round(c.whole[1] * rate)] : null
      const run = runVoice(messages, rate, block, from, Math.ceil((c.until - first + 0.01) * rate), keep)
      runs.push(run)
      if (keep) {
        wholeFile = `voice/${c.name}.f32`
        //? the first channel's Float32s, then the second's, little-endian
        const bytes = Buffer.alloc(keep[1] * 8)
        const view = viewOf(bytes)
        run.kept[0].forEach((value, i) => setF32(view, 4 * i, value, true))
        run.kept[1].forEach((value, i) => setF32(view, 4 * (keep[1] + i), value, true))
        out.push([wholeFile, bytes])
      }
    }
    runs.push(runVoice(messages, 48000, 1, Math.floor(takeAt * 48000) - 200, 2000, null))
    out.push([`voice/${c.name}.json`, {
      about: `lib/deckVoice.ts's newVoiceState, voiceCommand, renderVoice and voiceReport over the "${c.name}" case (${c.about}): each run makes a new state and renders \`frames\` frames from frame \`from\` in blocks of \`block\` at \`rate\`, each block's now its first frame over the rate, each message applied before the first block whose now is at or past its \`post\`, with that now. \`spans\`: an FNV-1a 64 hash of each ${SPAN_FRAMES} frames' output (each frame the first channel's Float32 bits and the second's, little-endian); \`reports\`: how many voiceReport made at ${'30'} a second, a hash of their doubles [time, pos, rate, gain, held, peaks, lowest] little-endian, and at 48 kHz in blocks of 128 those doubles whole (base64); \`maths\`: how many Math calls the run made and the FNV hash of them in order (maths.json says how). A run with \`whole\` wrote \`frames\` frames of its output from its own frame \`from\` to \`file\`, the first channel's Float32s then the second's.`,
      made_by: MADE_BY,
      made_from: Object.fromEntries([whole('lib/deckVoice.ts')]),
      name: c.name,
      messages: messages.map(messageOut),
      runs: runs.map((run) => ({ rate: run.rate, block: run.block, from: run.from, frames: run.frames, spans: run.spans, reports: run.reports, maths: run.maths, whole: run.keep ? { file: wholeFile, from: run.keep[0], frames: run.keep[1] } : null })),
    }, 3])
  }
  out.push(['voice/windows.json', {
    about: `The windows the voice cases read, made from integer recipes (export-deck-vectors.cjs recipeChannel; DeckVoiceTests makes them the same way): ${WINDOW_SECONDS} s at \`rate\`, each sample an Int16 over 32768 - noise (xorshift32 seeded seed * 2 + channel + 1, its top 16 bits less 32768; soft: that shifted right 3), sweep (a triangle whose step is 1 + ((i >> 7) % 600) * (channel + 1)), clicks (+32767 then -32768 every 2400 + 7 seed + 331 channel samples), step (silence, then 32767 on the first channel and -32768 on the second from half way, the second 9601 samples later). \`hash\`: FNV-1a 64 of the channels' Float32 bits in order, little-endian.`,
    made_by: MADE_BY,
    made_from: { 'ios/scripts/export-deck-vectors.cjs recipeChannel, recipeWindow': sha256(recipeChannel.toString() + recipeWindow.toString()) },
    windows: [...windowCache.values()].map((w) => ({ ...w.key, hash: w.hash })),
  }, 2])
  return out
}

//? THE CASES of the voice's own (the rules cases' messages join them, rulesVoiceCases): a hand turning back and forth
//? then let go to coast, a wind-down, a handover (a hand, the motor back to speed, held, faded), windows swapped
//? mid-block (none, and a mono one at another rate), a loud master the limiter must hold (a 96 kHz window turned at up
//? to 4x either way), a step for the DC blocker, a hand that rests, goes missing, repeats and comes out of order, and
//? a drive that runs out
function syntheticVoiceCases() {
  const was = maths.on
  maths.on = false
  const rng = seededLcg(2024)
  const jitter = (size) => (rng() - 0.5) * 2 * size
  const FRAME = 1 / 60
  const window = (post, kind, seed, start, rate, channels = 2) => ({ post, type: 'window', window: { kind, seed, channels, start, rate } })
  const take = (post, at, rate, time = post, until = Infinity) => ({ post, type: 'take', at, rate, time, until })
  const drive = (post, at, rate, accel, time = post, until = time + 0.12) => ({ post, type: 'drive', at, rate, accel, time, until })
  const hand = (post, at, time) => ({ post, type: 'hand', at, time })
  const fade = (post, seconds) => ({ post, type: 'fade', seconds })
  const stop = (post) => ({ post, type: 'stop' })
  //? a plan's drives a frame apart from `t0`, DRIVE_FOR_S ahead, as the deck posts them; returns its end
  const drives = (list, plan, t0, motorOn, target) => {
    for (let t = 0; t <= plan.duration + FRAME; t += FRAME) {
      const { x, v } = platter.planAt(plan, t)
      list.push(drive(t0 + t, x, v, platter.acceleration(v, motorOn, target)))
    }
    return t0 + plan.duration
  }
  //? a hand's samples at `hz` from `t0` for `seconds` at speed `speed(s)`, each delivered `late` after its time
  const hands = (list, at0, t0, seconds, hz, speed, late = 0.008, wobble = 0.0005) => {
    let at = at0, t = t0, v = 0
    while (t < t0 + seconds) {
      const step = 1 / hz + jitter(0.0015)
      v = speed(t - t0)
      at += v * step
      t += step
      list.push(hand(t + late, at + jitter(wobble), t))
    }
    return { at, t, v }
  }
  const cases = []
  {
    const m = [window(1.0, 'noise', 1, 0, 48000), take(1.0, 2, 0)]
    const end = hands(m, 2, 1.0, 1.5, 60, (s) => 1.5 * Math.sin(2 * Math.PI * 0.7 * s) + 0.4)
    const stopAt = drives(m, platter.coast(end.at, end.v, 425), end.t + 0.01, false, 1)
    m.push(fade(stopAt + 0.05, 0.04))
    cases.push({ name: 'hand-turns', about: 'a hand at 60 Hz turning back and forth, let go to coast, faded', messages: m, until: stopAt + 0.4, whole: [end.t - 0.2, 0.5] })
  }
  {
    const m = [window(1.0, 'sweep', 2, 140, 44100), take(1.0, 142, 1)]
    const stopAt = drives(m, platter.coast(142, 1, 425), 1.0, false, 1)
    m.push(fade(stopAt, 0.04))
    cases.push({ name: 'wind-down', about: 'the song taken at its own speed and wound down, a 44.1 kHz window', messages: m, until: stopAt + 0.4 })
  }
  {
    const m = [window(1.0, 'noise', 3, 50, 48000), take(1.0, 52, 0)]
    const end = hands(m, 52, 1.0, 0.8, 60, (s) => 2.5 * s)
    const planEnd = drives(m, platter.motor(end.at, end.v, 425, 1), end.t + 0.01, true, 1)
    const there = platter.planAt(platter.motor(end.at, end.v, 425, 1), 1e9).x
    for (let t = planEnd; t < planEnd + 0.3; t += FRAME) m.push(drive(t, there + (t - planEnd), 1, 0, t, t + 3))
    m.push(fade(planEnd + 0.3, 0.04))
    cases.push({ name: 'handover', about: 'a hand speeding up, let go on a playing record: the motor back to speed, held, faded over HANDOVER_FADE_S', messages: m, until: planEnd + 0.8, whole: [planEnd - 0.25, 0.5] })
  }
  {
    const m = [window(1.0, 'soft', 4, 0, 48000), take(1.0, 3, 1)]
    for (let t = 1.0; t < 2.8; t += FRAME) m.push(drive(t, 3 + (t - 1.0), 1, 0))
    m.push(window(1.5137, 'sweep', 5, 1, 48000), { post: 2.0011, type: 'window', window: null }, window(2.2003, 'soft', 6, 0, 44100, 1), stop(2.8))
    cases.push({ name: 'swap', about: 'a record at 1x under windows swapped mid-block: another, none, a mono one at 44.1 kHz', messages: m, until: 3.0, whole: [1.4, 0.5] })
  }
  {
    const m = [window(1.0, 'noise', 7, 0, 96000), take(1.0, 2, 1)]
    const end = hands(m, 2, 1.0, 1.5, 120, (s) => 4 * Math.sin(2 * Math.PI * 1.1 * s), 0.004)
    m.push(stop(end.t + 0.2))
    cases.push({ name: 'loud', about: 'a full-scale 96 kHz master turned at up to 4x either way by a 120 Hz hand: the limiter, the kernel at its widest', messages: m, until: end.t + 0.4 })
  }
  {
    const m = [window(1.0, 'step', 8, 0, 48000), take(1.0, 3.6, 0.5)]
    for (let t = 1.0; t < 2.6; t += FRAME) m.push(drive(t, 3.6 + 0.5 * (t - 1.0), 0.5, 0))
    m.push(stop(2.7))
    cases.push({ name: 'step', about: 'a full-scale step read at 0.5x: the DC blocker, the limiter coming down and back', messages: m, until: 3.0 })
  }
  {
    const m = [window(1.0, 'clicks', 9, 10, 48000), take(1.0, 12, 0)]
    let end = hands(m, 12, 1.0, 0.5, 60, () => 1)
    //? a rest, then on again with samples missing on the way
    end = hands(m, end.at, end.t + 0.2, 0.3, 60, () => 1)
    const t1 = end.t + 0.033
    m.push(hand(t1 + 0.008, end.at + 0.033, t1))
    //? a repeat of the same moment, and one out of order
    m.push(hand(t1 + 0.009, end.at + 0.0331, t1), hand(t1 + 0.010, end.at + 0.02, t1 - 0.01))
    end = hands(m, end.at + 0.033, t1, 0.3, 60, (s) => 1 - 2 * s)
    //? a coast's frames, then the hand catching the record before them
    const coastAt = end.t + 0.05
    const plan = platter.coast(end.at, end.v, 425)
    for (let k = 0; k < 6; k++) m.push(drive(coastAt + k * FRAME, platter.planAt(plan, k * FRAME).x, platter.planAt(plan, k * FRAME).v, platter.acceleration(platter.planAt(plan, k * FRAME).v, false, 1)))
    m.push(hand(coastAt + 6 * FRAME, end.at, coastAt + 2 * FRAME))
    hands(m, end.at, coastAt + 2 * FRAME + 0.001, 0.3, 60, () => 0.7)
    m.push(fade(coastAt + 0.5, 0.3))
    cases.push({ name: 'rests', about: 'a hand on clicks that rests, goes missing, repeats a moment, comes out of order, and catches a coast', messages: m, until: coastAt + 1.0 })
  }
  {
    const m = [window(1.0, 'soft', 10, 0, 48000), take(1.0, 1, 1, 1.0, 1.3), drive(1.1, 1.1, 1, -0.5, 1.1, 1.25), fade(2.0, 0.2)]
    cases.push({ name: 'runs-out', about: 'a take and a drive that run out with nothing after them, then a fade', messages: m, until: 2.4 })
  }
  maths.on = was
  return cases
}

/* ===== rules/: the real Deck, every input and every effect ===== */

//? The Deck is driven through deck.sim's own harness (ui/test/deckHarness.cjs) with its context's clock the page's
//? (`contextFollowsClock`), so every stamp is the page's time over 1000 but where the one mapping says otherwise - those
//? few are written down (`stamps`). Its world moves on one clock: the deck's timers, its frames on a 16 ms grid, and
//? the voice - lib/deckVoice.ts itself, fed every message the deck posts, rendering blocks of 128 at 48 kHz while the
//? context runs and handing each report back as the worklet does (`heard`), so what the deck hears is a real voice's.
//? INPUTS (base64: each an op byte, the page time in ms and the op's arguments, all little-endian doubles - a song
//? as its index in `songs`, a word as its index in `words`, true and false as 1 and 0):
const RULE_OPS = {
  new: [0, 'song playing at reduced ready made'], world: [1, 'song playing at ready made'], position: [2, 'at'],
  timer: [3, 'n'], frame: [4, ''], audio: [5, 'ready made'], heard: [6, 'pos rate gain'],
  answer: [7, 'ask first samples rate frames decodedRate bytes channels'], refuse: [8, 'ask status word'],
  live: [10, ''], taken: [11, ''], anchor: [12, ''], setShowing: [13, 'on'], setWindDown: [14, 'on'],
  speedChanged: [15, 'speed'], playingChanged: [16, 'on'], songChanged: [17, 'song'], pressed: [18, 'time'],
  holdStill: [19, 'held'], touched: [20, 'time turned offset'], takeOver: [21, 'time quick'], hand: [22, 'time turned at'],
  release: [23, 'time cancel'], pausing: [24, ''], resuming: [25, ''], armTaken: [26, ''], destroy: [27, ''], reduced: [28, 'on'],
}
const RULE_ARITY = (name) => (RULE_OPS[name][1] ? RULE_OPS[name][1].split(' ').length : 0)
const RETURNS = new Set(['live', 'taken', 'anchor', 'takeOver', 'release', 'pausing', 'resuming'])
const EFFECT_SPAN = 512
const EFFECTS_WHOLE = 400
const FRAME_MS = 16
const VOICE_BLOCK = 128
const CONTEXT_RATE = 48000
const RULES_SONG = { id: 'time', length: 425, flac: true, kind: 'FLAC' }

let rulesHarness = null
function rulesWorld() {
  if (rulesHarness) return rulesHarness
  const H = require(path.join(UI, 'test', 'deckHarness.cjs')).install(OUT)
  H.contextFollowsClock = true
  const { ApiError } = load('api/http.js')
  const T = { H, ApiError, on: false }
  const hSet = globalThis.setTimeout, hClear = globalThis.clearTimeout
  const hFrame = globalThis.requestAnimationFrame, hUnframe = globalThis.cancelAnimationFrame
  //? the deck's timers numbered as it makes them - but its clock's own tick (the phone's clock is its voice host's,
  //? and DeckRules has none), which runs here as it does on the page and is told to no one
  globalThis.setTimeout = (run, ms = 0) => {
    const id = hSet(run, ms)
    if (T.on && !(T.deck && run === T.deck.onClockTick)) {
      const n = T.timerCount++
      T.timerIds.set(id, n)
      T.effect(`timer ${n} ${hex(ms)}`)
    }
    return id
  }
  globalThis.clearTimeout = (id) => {
    if (T.on && T.timerIds.has(id) && H.timers.some((timer) => timer.id === id)) T.effect(`clear ${T.timerIds.get(id)}`)
    hClear(id)
  }
  globalThis.requestAnimationFrame = (run) => {
    const id = hFrame(run)
    if (T.on) {
      T.effect('raf')
      if (T.frameAskedAt === null) T.frameAskedAt = H.clock
    }
    return id
  }
  globalThis.cancelAnimationFrame = (id) => {
    if (T.on && H.frames.some((frame) => frame.id === id)) T.effect('unraf')
    hUnframe(id)
    if (!H.frames.length) T.frameAskedAt = null
  }
  const realPost = H.Deck.prototype.post
  H.Deck.prototype.post = function post(message, transfer) {
    if (T.on) {
      T.effect(postWords(message))
      T.voiceQueue.push(message)
    }
    return realPost.call(this, message, transfer)
  }
  const realStamp = H.Deck.prototype.stamp
  H.Deck.prototype.stamp = function stamp(time) {
    const stamped = realStamp.call(this, time)
    if (T.on && hex(stamped) !== hex(time / 1000)) T.stamps.push(time, stamped)
    return stamped
  }
  //? the window's bytes stand for what the answer said; decoded as the recipe's soft noise (the rules don't listen)
  const decodedChannels = new Map()
  H.decodeWith = (bytes, done) => {
    const info = T.windowsAnswered.get(bytes)
    if (!decodedChannels.has(info.frames)) decodedChannels.set(info.frames, [0, 1].map((ch) => recipeChannel('soft', 3, ch, info.frames)))
    const channels = decodedChannels.get(info.frames).slice(0, info.channels)
    done({ numberOfChannels: info.channels, sampleRate: info.decodedRate, length: info.frames, getChannelData: (c) => channels[c] })
  }
  globalThis.__deckTrace = {
    audio: () => {
      if (!T.on) return
      const world = T.world()
      T.record('audio', [world[3], world[4]])
      T.lastWorld = world
    },
    effect: (words) => { if (T.on) T.effect(words) },
  }
  rulesHarness = T
  return T
}

function postWords(m) {
  switch (m.type) {
    case 'window': return `post window ${hex(m.start)} ${hex(m.rate)} ${m.channels.length} ${m.channels[0]?.length ?? 0}`
    case 'take': return `post take ${hex(m.at)} ${hex(m.rate)} ${hex(m.time)} ${hex(m.until)}`
    case 'drive': return `post drive ${hex(m.at)} ${hex(m.rate)} ${m.accel === undefined ? '-' : hex(m.accel)} ${hex(m.time)} ${hex(m.until)}`
    case 'hand': return `post hand ${hex(m.at)} ${hex(m.time)}`
    case 'fade': return `post fade ${hex(m.seconds)}`
    case 'stop': return 'post stop'
  }
  throw new Error(`a voice message the rules trace doesn't know: ${m.type}`)
}

/** A new case: the world afresh, and the helpers that move it. */
function rulesCase() {
  const T = rulesWorld()
  const H = T.H
  H.timers = []
  H.frames = []
  H.portMessages = []
  H.clockReads = []
  //? the clock never goes back: the deck's audio and its clock's mapping are the page's, kept from case to case
  H.clock = Math.ceil(H.clock / 1000) * 1000 + 1000
  H.reduced = false
  Object.assign(T, {
    on: true, deck: null, host: null, inputs: [], effects: [], stamps: [], timerIds: new Map(), timerCount: 0,
    frameAskedAt: null, frameBase: H.clock, songs: [], words: [], asks: [], voice: null, voiceQueue: [], block: null,
    lastWorld: null, windowsAnswered: new WeakMap(), speed: 1, toldPlaying: null, destroyed: false,
  })
  //? each effect after the number of the input it came in: an effect at another input is another trace
  T.effect = (words) => T.effects.push(`${T.inputs.length - 1} ${words}`)
  T.songIndex = (song) => {
    if (!song) return -1
    let i = T.songs.findIndex((s) => s.id === song.id && s.length === song.length && s.flac === song.flac && s.kind === song.kind)
    if (i < 0) i = T.songs.push(song) - 1
    return i
  }
  T.wordIndex = (word) => {
    if (word === null || word === undefined) return -1
    let i = T.words.indexOf(word)
    if (i < 0) i = T.words.push(word) - 1
    return i
  }
  T.world = () => {
    const audio = globalThis.__deckAudio()
    const ready = audio.context?.state === 'running' && !!audio.voice?.ready
    const made = !!audio.voice?.ready && !!audio.context && audio.context.state !== 'closed'
    const host = T.host
    return [T.songIndex(host.songValue), host.isPlaying ? 1 : 0, host.at, ready ? 1 : 0, made ? 1 : 0]
  }
  T.record = (name, args) => {
    const op = RULE_OPS[name][0]
    if (op !== 0 && op !== 1) {
      const world = T.world()
      if (!T.lastWorld || world.some((value, i) => !Object.is(value, T.lastWorld[i]))) T.inputs.push({ op: 1, t: H.clock, args: world })
    }
    if (args.length !== RULE_ARITY(name)) throw new Error(`rules: ${name} takes ${RULE_ARITY(name)} arguments, not ${args.length}`)
    T.inputs.push({ op, t: H.clock, args: args.map(Number) })
  }
  //? an input: recorded, done, and the world as it left it noted - then the player told if its playing changed (the
  //? effect Turntable runs on player.playing, the deck's own hold and resume included)
  T.do = (name, args, run) => {
    T.record(name, args)
    const out = run()
    T.lastWorld = T.world()
    if (RETURNS.has(name)) T.effect(`return ${returnWords(out)}`)
    T.tellPlaying()
    return out
  }
  T.tellPlaying = () => {
    if (!T.deck || T.toldPlaying === null || T.host.isPlaying === T.toldPlaying) return
    T.toldPlaying = T.host.isPlaying
    T.call('playingChanged', [T.host.isPlaying])
  }
  T.call = (name, args = []) => {
    if (name === 'destroy') T.destroyed = true
    return T.callNow(name, args)
  }
  T.callNow = (name, args) => T.do(name, args.map((a) => (typeof a === 'boolean' ? (a ? 1 : 0) : a)), () => {
    switch (name) {
      case 'songChanged': return T.deck.songChanged(T.songs[args[0]]?.id ?? '')
      case 'release': return T.deck.release(args[0], args[1] ? 'cancel' : 'up')
      case 'takeOver': return T.deck.takeOver(args[0], !!args[1])
      case 'reduced': H.reduced = !!args[0]; return T.deck.onReduced()
      default: return T.deck[name](...args)
    }
  })
  T.make = async ({ song = RULES_SONG, playing = true, at = 60, reduced = false, wake = true, windDown = true, speed = 1 } = {}) => {
    T.host = rulesHost(T, song, playing, at)
    H.reduced = reduced
    const world = T.world()
    T.do('new', [world[0], world[1], world[2], reduced ? 1 : 0, world[3], world[4]], () => { T.deck = new H.Deck(T.host) })
    T.toldPlaying = playing
    if (!windDown) T.call('setWindDown', [false])
    if (speed !== 1) T.speedTo(speed)
    T.call('setShowing', [true])
    if (wake) await T.wake()
  }
  //? a gesture's wakeDeckAudio (Turntable's tap, the look button): the context made and resumed, the worklet loaded
  T.wake = async () => {
    H.wakeDeckAudio()
    for (let i = 0; i < 4; i++) await H.settle()
  }
  T.speedTo = (speed) => {
    T.speed = speed
    T.call('speedChanged', [speed])
  }
  T.position = (at) => T.do('position', [at], () => T.host.moveTo(at))
  T.setPlaying = (on) => {
    T.host.isPlaying = on
    T.tellPlaying()
  }
  T.setSong = (song, playing) => {
    T.host.songValue = song
    T.host.isPlaying = playing
  }
  //? deadwax's answer to the window asked `n`-th: from where it was asked, to the song's end at most, at 44.1 kHz,
  //? decoded at the context's rate
  T.answer = async (n = T.asks.length - 1, { seconds = 40, channels = 2 } = {}) => {
    const ask = T.asks[n]
    const length = ask.song.length
    const first = Math.round(ask.from * 44100)
    const samples = Math.round(Math.min(seconds, length > 0 ? Math.max(0, length - ask.from) : seconds) * 44100)
    const frames = Math.round((samples * CONTEXT_RATE) / 44100)
    const bytes = { byteLength: Math.round(seconds * 100000) }
    T.windowsAnswered.set(bytes, { frames, channels, decodedRate: CONTEXT_RATE })
    T.do('answer', [n, first, samples, 44100, frames, CONTEXT_RATE, bytes.byteLength, channels], () => ask.resolve({ bytes, first, samples, rate: 44100 }))
    for (let i = 0; i < 3; i++) await H.settle()
    T.lastWorld = T.world()
    T.tellPlaying()
  }
  T.answerAll = async () => {
    for (let n = 0; n < T.asks.length; n++) if (!T.asks[n].answered) await T.answer(n)
  }
  T.refuse = async (n, status, detail) => {
    const ask = T.asks[n]
    T.do('refuse', [n, status, T.wordIndex(detail)], () => ask.reject(status ? new T.ApiError(status, detail, 'refused') : new Error(detail)))
    for (let i = 0; i < 3; i++) await H.settle()
    T.lastWorld = T.world()
  }
  //? the world moved on to `ms`: the deck's timers, its frames and the voice's blocks, each at its own time
  T.until = async (ms) => {
    for (;;) {
      const timer = [...H.timers].sort((a, b) => a.at - b.at)[0]
      const asked = T.frameAskedAt ?? H.clock
      const frameAt = H.frames.length ? T.frameBase + (Math.floor((asked - T.frameBase) / FRAME_MS) + 1) * FRAME_MS : Infinity
      const running = T.world()[3] === 1
      if (running && T.block === null) T.block = Math.ceil((H.clock / 1000) * CONTEXT_RATE / VOICE_BLOCK)
      if (!running) T.block = null
      const blockAt = running ? (((T.block + 1) * VOICE_BLOCK) / CONTEXT_RATE) * 1000 : Infinity
      const at = Math.min(timer ? timer.at : Infinity, frameAt, blockAt)
      if (!(at <= ms)) break
      H.clock = Math.max(H.clock, at)
      if (timer && timer.at === at) {
        H.timers = H.timers.filter((t) => t !== timer)
        if (T.timerIds.has(timer.id)) T.do('timer', [T.timerIds.get(timer.id)], () => timer.run())
        else timer.run()
        await H.settle()
      } else if (blockAt === at) {
        T.renderBlock()
      } else {
        const frames = H.frames
        H.frames = []
        T.frameAskedAt = null
        T.do('frame', [], () => { for (const frame of frames) frame.run(H.clock) })
      }
    }
    H.clock = Math.max(H.clock, ms)
  }
  //? one block of the voice: the messages posted since applied, rendered, and its report handed back to the deck
  T.renderBlock = () => {
    if (!T.voice) T.voice = voice.newVoiceState()
    const now = (T.block * VOICE_BLOCK) / CONTEXT_RATE
    const was = maths.on
    maths.on = false
    for (const message of T.voiceQueue.splice(0)) voice.voiceCommand(T.voice, message, now, CONTEXT_RATE)
    const outs = [new Float32Array(VOICE_BLOCK), new Float32Array(VOICE_BLOCK)]
    voice.renderVoice(T.voice, outs, VOICE_BLOCK, CONTEXT_RATE, now)
    const heard = voice.voiceReport(T.voice, VOICE_BLOCK, CONTEXT_RATE, now, voice.REPORTS_PER_SECOND)
    maths.on = was
    T.block += 1
    //? what the deck reads of a report - its time, its limiter's counts go to Debug alone (the trace leaves them out)
    if (heard) T.do('heard', [heard.pos, heard.rate, heard.gain], () => T.deck.onHeard(heard))
  }
  //? the song playing on for `ms`: its position told every 250 ms while it plays, as the element's timeupdate does
  T.play = async (ms) => {
    const end = H.clock + ms
    while (H.clock < end) {
      await T.until(Math.min(end, H.clock + 250))
      if (T.host.isPlaying) T.position(T.host.at + 0.25 * T.speed)
    }
  }
  //? Turntable's release, as runMotion does it: the seek asked for, and the play when there is no coast to wait for
  T.release = (time, cancel = false) => {
    const { seek, play } = T.call('release', [time, cancel])
    if (seek !== null && T.host.songValue?.length) T.position(seek)
    if (play && !T.host.isPlaying) T.setPlaying(true)
  }
  return T
}

function returnWords(value) {
  if (value === null || value === undefined) return 'null'
  if (typeof value === 'boolean') return String(value)
  if (typeof value === 'number') return hex(value)
  return `${value.seek === null ? 'null' : hex(value.seek)} ${value.play}`
}

function rulesHost(T, song, playing, at) {
  const host = {
    songValue: song, isPlaying: playing, at, listeners: [],
    song: () => host.songValue,
    playing: () => host.isPlaying,
    position: () => host.at,
    onPosition(listener) {
      T.effect('listen')
      const entry = { listener }
      host.listeners.push(entry)
      return () => {
        T.effect('unlisten')
        host.listeners = host.listeners.filter((e) => e !== entry)
      }
    },
    hold() { T.effect('hold'); host.isPlaying = false },
    resume() { T.effect('resume'); host.isPlaying = true },
    turnFace(degrees) { T.effect(`face ${hex(degrees)}`) },
    show(at, scrubbing) { T.effect(at === null ? 'show null' : `show ${hex(at)} ${scrubbing}`) },
    grabbed() { T.effect('grabbed') },
    window(asked, from, seconds) {
      const n = T.asks.length
      T.effect(`ask ${n} ${T.songIndex(asked)} ${hex(from)} ${hex(seconds)}`)
      return new Promise((resolve, reject) => T.asks.push({ song: asked, from, seconds, resolve: (w) => { T.asks[n].answered = true; resolve(w) }, reject: (e) => { T.asks[n].answered = true; reject(e) } }))
    },
    moveTo(seconds) {
      host.at = seconds
      for (const entry of [...host.listeners]) entry.listener(seconds)
    },
  }
  return host
}

//? THE CASES. The bench's motions, as runMotion (lab/runner.ts:50) drives them: pressed and taken at the motion's
//? start, each sample handed over once the clock has passed its time (a page behind hands over all that came due),
//? the release RELEASE_AFTER_MS after the last - then the seek and the play it asks for, and the song played on.
async function motionCase(motion, hz, seed) {
  const T = rulesCase()
  await T.make({ at: 60 })
  await T.answerAll()
  await T.play(500)
  const from = T.H.clock
  const was = maths.on
  maths.on = false
  motions.MOTION_HZ = hz
  const samples = motions.motionSamples(motion, from, seededLcg(seed))
  motions.MOTION_HZ = 60
  maths.on = was
  const length = T.host.songValue.length
  T.call('pressed', [from])
  const anchor = T.call('takeOver', [from, false])
  let next = 1
  while (next < samples.length) {
    await T.until(T.H.clock + Math.max(1, samples[next].time - T.H.clock + 0.5))
    while (next < samples.length && samples[next].time <= T.H.clock) {
      const sample = samples[next++]
      T.call('hand', [sample.time, sample.turned, Math.max(0, Math.min(length || Infinity, anchor + sample.moved))])
    }
    await T.answerAll()
  }
  const lift = samples[samples.length - 1].time + 8
  if (lift > T.H.clock) await T.until(lift + 0.5)
  T.release(lift)
  await T.answerAll()
  await T.play(3000)
  T.call('destroy')
  return T
}

//? a hand turning the record by `turns` (seconds of the song) over `ms`, a sample every `every` ms from `from`
async function drag(T, from, ms, seconds, anchor, every = 8) {
  for (let t = every; t <= ms; t += every) {
    await T.until(from + t + 0.5)
    const moved = (seconds * t) / ms
    T.call('hand', [from + t, (moved / tt.SECONDS_PER_TURN) * 2 * Math.PI, anchor + moved])
  }
}

const RULE_CASES = [
  ['tap-pause-then-play', 'a tap on a playing record (Turntable\'s click): pausing() winds it down, the song paused and sought to where it stops; a tap later, resuming() plays it from what was heard', async (T) => {
    await T.make()
    await T.answerAll()
    await T.play(1000)
    const t0 = T.H.clock
    T.call('live')
    T.call('pressed', [t0])
    await T.until(t0 + 80)
    T.release(t0 + 80)
    const x = T.call('pausing')
    T.setPlaying(false)
    if (x !== null) T.position(x)
    await T.play(700)
    const back = T.call('resuming')
    if (back !== null) T.position(back)
    T.setPlaying(true)
    await T.play(1500)
  }],
  ['play-during-wind-down', 'a pause wound down, and played again half way: from what was heard, the platter pulled back up', async (T) => {
    await T.make({ at: 120 })
    await T.answerAll()
    await T.play(600)
    const x = T.call('pausing')
    T.setPlaying(false)
    if (x !== null) T.position(x)
    await T.play(300)
    const back = T.call('resuming')
    if (back !== null) T.position(back)
    T.setPlaying(true)
    await T.play(1200)
  }],
  ['wind-down-off', 'with "Pause winds the record down" off: a plain pause, sought nowhere, the platter spun down', async (T) => {
    await T.make({ windDown: false })
    await T.answerAll()
    await T.play(500)
    const x = T.call('pausing')
    T.setPlaying(false)
    if (x !== null) T.position(x)
    await T.play(1500)
  }],
  ['hold-and-let-go', 'a press that rests HOLD_MS takes the record (grabbed), held, let go from rest: the motor back to speed, the song played and handed over', async (T) => {
    await T.make()
    await T.answerAll()
    await T.play(750)
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 600)
    T.call('taken')
    T.call('anchor')
    T.release(t0 + 600)
    await T.answerAll()
    await T.play(3500)
  }],
  ['quick-grab-flick-back', 'a quick grab (the slop crossed, touched samples before it), a flick back, let go: the plan back to speed from the hand\'s speed', async (T) => {
    await T.make({ at: 90 })
    await T.answerAll()
    await T.play(1000)
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 8)
    T.call('touched', [t0 + 8, -0.004, -0.0011])
    await T.until(t0 + 16)
    T.call('touched', [t0 + 16, -0.009, -0.0024])
    await T.until(t0 + 24)
    const anchor = T.call('takeOver', [t0 + 24, true])
    await drag(T, t0 + 24, 100, -0.6, anchor, 8)
    T.release(T.H.clock + 4)
    await T.answerAll()
    await T.play(3500)
  }],
  ['paused-coast', 'a paused record flicked forward: a coast to a stop under friction, the song sought to where it stops and left paused', async (T) => {
    await T.make({ playing: false, at: 100 })
    await T.answerAll()
    await T.play(300)
    const t0 = T.H.clock
    T.call('live')
    T.call('pressed', [t0])
    await T.until(t0 + 10)
    const anchor = T.call('takeOver', [t0 + 10, true])
    await drag(T, t0 + 10, 150, 0.9, anchor, 10)
    T.release(T.H.clock + 2)
    await T.answerAll()
    await T.play(2500)
  }],
  ['backwards-coast-past-the-window', 'a paused record flicked hard backwards: the coast runs out of its window, the next asked at the release and sounded as it lands', async (T) => {
    await T.make({ playing: false, at: 64 })
    await T.answerAll()
    await T.play(300)
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 10)
    const anchor = T.call('takeOver', [t0 + 10, true])
    await drag(T, t0 + 10, 120, -2.5, anchor, 10)
    T.release(T.H.clock + 3)
    await T.play(400)
    await T.answerAll()
    await T.play(2500)
  }],
  ['cancel', 'a held record whose touch the system cancels: the voice stopped, the song it paused played on, nothing sought', async (T) => {
    await T.make()
    await T.answerAll()
    await T.play(500)
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 400)
    await drag(T, t0 + 400, 80, 0.2, T.call('anchor'), 8)
    T.release(T.H.clock + 1, true)
    await T.play(1500)
  }],
  ['play-during-coast', 'a coast of a paused record, and the transport\'s play half way: its sound stops, the platter pulled up from where it is', async (T) => {
    await T.make({ playing: false, at: 200 })
    await T.answerAll()
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 10)
    const anchor = T.call('takeOver', [t0 + 10, true])
    await drag(T, t0 + 10, 100, 1.2, anchor, 10)
    T.release(T.H.clock + 1)
    await T.play(250)
    const back = T.call('resuming')
    if (back !== null) T.position(back)
    T.setPlaying(true)
    await T.play(1500)
  }],
  ['arm-mid-coast', 'the arm taken during a coast, then the song sought elsewhere by it: quiet for the rest, its end still comes', async (T) => {
    await T.make({ playing: false, at: 150 })
    await T.answerAll()
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 10)
    const anchor = T.call('takeOver', [t0 + 10, true])
    await drag(T, t0 + 10, 100, 1.5, anchor, 10)
    T.release(T.H.clock + 1)
    await T.play(200)
    T.call('armTaken')
    await T.until(T.H.clock + 50)
    T.position(300)
    await T.answerAll()
    await T.play(2500)
  }],
  ['handover-sought-elsewhere', 'a let-go of a playing record, and the song sought far away as the handover waits: the record\'s sound fades', async (T) => {
    await T.make()
    await T.answerAll()
    await T.play(500)
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 300)
    await drag(T, t0 + 300, 60, 0.3, T.call('anchor'), 6)
    T.release(T.H.clock + 1)
    await T.play(1200)
    T.position(30)
    await T.answerAll()
    await T.play(1500)
  }],
  ['song-change-mid-hold', 'the song changed (Next) under a hand that took it from playing: everything of it dropped, the next played after SONG_CHANGE_SETTLE_MS', async (T) => {
    await T.make()
    await T.answerAll()
    await T.play(500)
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 300)
    T.setSong({ id: 'next', length: 300, flac: true, kind: 'FLAC' }, false)
    T.host.at = 0
    T.call('songChanged', [T.songIndex(T.host.songValue)])
    await T.play(600)
    await T.answerAll()
    await T.play(1000)
  }],
  ['song-change-mid-coast-back', 'Next during a run back to speed: dropped, and the next song played as the hand meant', async (T) => {
    await T.make()
    await T.answerAll()
    await T.play(300)
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 10)
    const anchor = T.call('takeOver', [t0 + 10, true])
    await drag(T, t0 + 10, 60, -0.5, anchor, 6)
    T.release(T.H.clock + 1)
    await T.play(200)
    T.setSong({ id: 'next', length: 300, flac: true, kind: 'FLAC' }, false)
    T.host.at = 0
    T.call('songChanged', [T.songIndex(T.host.songValue)])
    await T.play(800)
    await T.answerAll()
    await T.play(800)
  }],
  ['not-flac', 'an MP3: never asked for, refused in its own words, and a press is not the deck\'s', async (T) => {
    await T.make({ song: { id: 'mp3', length: 200, flac: false, kind: 'MP3' } })
    await T.play(500)
    T.call('live')
    await T.play(500)
  }],
  ['refused-415', 'deadwax refuses the window (415): the song refused for good, never asked again', async (T) => {
    await T.make()
    await T.refuse(0, 415, 'it is an MP4 deadwax can\'t cut')
    T.call('live')
    await T.play(2000)
    T.position(200)
    await T.play(500)
  }],
  ['past-the-end-416-then-retry', 'a 416, then a network failure: each retried only after RETRY_MS (under Reduce Motion, so its 21 s draw no frames)', async (T) => {
    await T.make({ at: 30, reduced: true })
    await T.refuse(0, 416, 'past the end')
    await T.play(10500)
    if (T.asks.length > 1) await T.refuse(T.asks.length - 1, 0, 'the network went away')
    await T.play(10500)
    await T.answerAll()
    T.call('live')
    await T.play(500)
  }],
  ['reduced-motion', 'Reduce Motion: no frames, and a let-go of a playing record plays the song in the gesture, the voice stopped', async (T) => {
    await T.make({ reduced: true })
    await T.answerAll()
    await T.play(500)
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 300)
    await drag(T, t0 + 300, 60, 0.4, T.call('anchor'), 6)
    T.release(T.H.clock + 1)
    await T.play(800)
    T.call('reduced', [false])
    await T.play(500)
    const x = T.call('pausing')
    T.setPlaying(false)
    if (x !== null) T.position(x)
    await T.play(1500)
  }],
  ['silent-press-then-wake', 'a press before any sound (no context yet): held still, let go, turning on - then a gesture wakes the sound and the window it wanted is asked for', async (T) => {
    await T.make({ playing: false, at: 30, wake: false })
    T.call('live')
    T.call('holdStill', [true])
    await T.play(300)
    T.call('holdStill', [false])
    await T.wake()
    await T.answerAll()
    T.call('live')
    await T.play(500)
  }],
  ['held-still-over-a-coast', 'a press the deck can\'t take over a coast it could not catch (hidden meanwhile): held still, the coast ended there', async (T) => {
    await T.make({ playing: false, at: 80 })
    await T.answerAll()
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 10)
    const anchor = T.call('takeOver', [t0 + 10, true])
    await drag(T, t0 + 10, 100, 1.0, anchor, 10)
    T.release(T.H.clock + 1)
    await T.play(150)
    T.call('setShowing', [false])
    await T.play(100)
    T.call('setShowing', [true])
    T.call('live')
    T.call('holdStill', [true])
    await T.play(300)
    T.call('holdStill', [false])
    await T.play(1000)
  }],
  ['hidden-mid-coast-back', 'the turntable hidden during a run back to speed: its end still plays the song, and shown again it turns', async (T) => {
    await T.make()
    await T.answerAll()
    await T.play(300)
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 10)
    const anchor = T.call('takeOver', [t0 + 10, true])
    await drag(T, t0 + 10, 80, 0.8, anchor, 8)
    T.release(T.H.clock + 1)
    await T.play(100)
    T.call('setShowing', [false])
    await T.play(2500)
    T.call('setShowing', [true])
    await T.answerAll()
    await T.play(1000)
  }],
  ['speed-changes', 'the player\'s speed changed while turning, during a spin-up, and a let-go at 2x: the motor heads for the new speed', async (T) => {
    await T.make({ playing: false, at: 50 })
    await T.answerAll()
    T.setPlaying(true)
    await T.play(150)
    T.speedTo(1.5)
    await T.play(600)
    T.speedTo(2)
    await T.play(500)
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 10)
    const anchor = T.call('takeOver', [t0 + 10, true])
    await drag(T, t0 + 10, 80, -0.3, anchor, 8)
    T.release(T.H.clock + 1)
    await T.answerAll()
    await T.play(2500)
    T.speedTo(0.5)
    await T.play(500)
  }],
  ['pause-from-elsewhere', 'paused by the lock screen, not the turntable: the platter spins down after PAUSE_SETTLE_MS; a pause shorter than that (a song change\'s) doesn\'t', async (T) => {
    await T.make()
    await T.answerAll()
    await T.play(500)
    T.setPlaying(false)
    await T.play(100)
    T.setPlaying(true)
    await T.play(500)
    T.setPlaying(false)
    await T.play(1800)
    T.setPlaying(true)
    await T.play(800)
  }],
  ['mono-short-window', 'a mono window cut short by deadwax\'s budget (a hi-res song): the margins shrink, the next window asked sooner', async (T) => {
    await T.make({ song: { id: 'hires', length: 300, flac: true, kind: 'FLAC' }, at: 20 })
    await T.answer(0, { seconds: 12, channels: 1 })
    await T.play(9000)
    await T.answerAll()
    await T.play(1000)
  }],
  ['tap-while-coasting', 'a press on a coasting record that stays a tap: the click resumes from what was heard', async (T) => {
    await T.make({ playing: false, at: 220 })
    await T.answerAll()
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 10)
    const anchor = T.call('takeOver', [t0 + 10, true])
    await drag(T, t0 + 10, 100, 1.4, anchor, 10)
    T.release(T.H.clock + 1)
    await T.play(200)
    const t1 = T.H.clock
    T.call('live')
    T.call('pressed', [t1])
    await T.until(t1 + 60)
    T.release(t1 + 60)
    const back = T.call('resuming')
    if (back !== null) T.position(back)
    T.setPlaying(true)
    await T.play(1500)
  }],
  //? three edges the cases above never reach, found by the Swift port's mutation checks: a margin at a speed under
  //? 1x, a report at the gain that counts, a lift exactly RELEASE_TAIL_MS after the last sample
  ['slow-short-window', 'at 0.5x, a window cut short (4 s): the next is asked its margin ahead in the song\'s own seconds - never less below 1x (under Reduce Motion: no frames)', async (T) => {
    await T.make({ song: { id: 'hires', length: 300, flac: true, kind: 'FLAC' }, at: 20, speed: 0.5, reduced: true })
    await T.answer(0, { seconds: 8 })
    await T.play(8000)
    await T.answerAll()
    await T.play(500)
  }],
  ['silent-coast-sounds-on-arrival', 'a hand that leaves its window, let go: the coast starts silent, and sounds from where it has got to as the next window lands', async (T) => {
    await T.make({ playing: false, at: 62 })
    await T.answerAll()
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 10)
    const anchor = T.call('takeOver', [t0 + 10, true])
    await drag(T, t0 + 10, 120, -6, anchor, 10)
    T.release(T.H.clock + 1)
    await T.play(150)
    await T.answerAll()
    await T.play(2500)
  }],
  ['handover-judged-closely', 'the song heard 0.015 s past where the handover waits, then 0.025 s: the record\'s sound fades at the second', async (T) => {
    await T.make()
    await T.answerAll()
    await T.play(400)
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 300)
    await drag(T, t0 + 300, 60, 0.3, T.call('anchor'), 6)
    T.release(T.H.clock + 1)
    const x = T.host.at
    while (!T.host.isPlaying) await T.until(T.H.clock + 16)
    T.position(x + 0.015)
    await T.until(T.H.clock + 16)
    T.position(x + 0.025)
    await T.play(600)
  }],
  ['heard-at-half-gain', 'what the voice says, fresh, just under the gain that counts and at it (0.45, 0.5), each a moment before a frame: only the second is shown', async (T) => {
    await T.make()
    await T.answerAll()
    await T.play(300)
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 300)
    for (const gain of [0.45, 0.5]) {
      const frameAt = T.frameBase + (Math.floor((T.H.clock - T.frameBase) / FRAME_MS) + 2) * FRAME_MS
      await T.until(frameAt - 1)
      const heard = { time: 0, pos: 61.25, rate: 0.5, gain, held: 0, peaks: 0, lowest: 0 }
      T.do('heard', [heard.pos, heard.rate, heard.gain], () => T.deck.onHeard(heard))
      await T.until(frameAt)
    }
    T.release(T.H.clock + 1)
    await T.play(500)
  }],
  ['release-at-the-tail', 'a let-go exactly RELEASE_TAIL_MS after the last sample: the plan still from that sample', async (T) => {
    await T.make({ playing: false, at: 140 })
    await T.answerAll()
    const t0 = T.H.clock
    T.call('pressed', [t0])
    await T.until(t0 + 10)
    const anchor = T.call('takeOver', [t0 + 10, true])
    await drag(T, t0 + 10, 80, 0.7, anchor, 8)
    const last = t0 + 10 + 80
    await T.until(last + 40)
    T.release(last + 40)
    await T.play(2000)
  }],
]

/* ===== press/: Turntable.tsx's handlers, through the real Turntable ===== */

//? The real Turntable (player/Turntable.tsx) mounted as ui/test/turntable.sim.cjs mounts it (its `mount`, :180: JSX as
//? plain objects, Preact's hooks as a cursor, a document whose stage is drawn 1:1) over the rules' harness - its clock,
//? timers, frames, audio context and window route - and a fake player, driven by what a browser sends it: pointer
//? events (a down; a move with its coalesced samples; on the record an up, then lostpointercapture, then the click; a
//? cancel), the arm's keys, and Now Playing's transport (NowPlaying.tsx, mounted the same way, its deck the
//? turntable's). TurntablePress.swift ports the handlers, so the trace is what they do, in order:
//?
//?   ["world", {...}]   what the handlers read, before an input - only what changed: the player's playing, the render's
//?                      length, track, drawnAt and shown, the clock (now), flac and noAudio (the silent line's), and the
//?                      deck's live(), taken() and anchor()
//?   an input           ["down", pointer, x, y, time] ["armDown", pointer, x, y] ["move", pointer, coalesced | null,
//?                      event] ["up", pointer, time] ["cancel", pointer, time] ["key", key] ["nowPlaying"] ["song", id]
//?                      ["grabbed"] (the deck's, between inputs: a press taken by resting)
//?   an effect          a call a handler makes: to the deck (pressed, holdStill, touched, takeOver, hand, release,
//?                      pausing, resuming, armTaken), to the player (seek, toggle) or wakeDeckAudio (wake) - its
//?                      arguments, then "->" and what it returned; each followed by ["after", {...}] when the player's
//?                      playing or the deck's live, taken or anchor moved under it
//?   ["turn", deg]      the record's turn as the render draws it (handTurn, Turntable.tsx:426), when it changes
//?   ["silent", words]  the silent line Now Playing is told (:288-290), when it changes
//?
//? A call the deck makes to the player inside another (its own hold and resume) is in "after" alone: DeckRules makes
//? it, not TurntablePress, and the rules traces hold it.
const PRESS_BOX = { left: 0, top: 0, width: 372, height: 368 }
const PRESS_CALLS = new Set(['pressed', 'holdStill', 'touched', 'takeOver', 'hand', 'release', 'pausing', 'resuming', 'armTaken'])
const PRESS_QUIET = ['live', 'taken', 'anchor', 'setShowing', 'playingChanged', 'setWindDown', 'speedChanged', 'songChanged', 'destroy']
const PRESS_FLAC = { id: 'time', title: 'Time', artist: 'Pink Floyd', album: 'The Dark Side of the Moon', albumId: 'dsotm', coverArt: 'cover-dsotm', suffix: 'flac', contentType: 'audio/flac', duration: 425 }
const PRESS_MP3 = { id: 'money', title: 'Money', artist: 'Pink Floyd', album: 'The Dark Side of the Moon', albumId: 'dsotm', coverArt: 'cover-dsotm', suffix: 'mp3', contentType: 'audio/mpeg', duration: 382 }
const PRESS_NEXT = { id: 'us-and-them', title: 'Us and Them', artist: 'Pink Floyd', album: 'The Dark Side of the Moon', albumId: 'dsotm', coverArt: 'cover-dsotm', suffix: 'flac', contentType: 'audio/flac', duration: 462 }

/** The handlers' source, piece by piece (press/handlers.json, and each trace's made_from). */
function handlerPieces() {
  return [
    piece('player/Turntable.tsx', /\/\/\? \(2\.0\.7\) the silent record's line[\s\S]*?useEffect\(\(\) => \(\) => onSilent\?\.\(null\), \[\]\)/, 'the silent line (:286-290)'),
    piece('player/Turntable.tsx', /const pressable = [\s\S]*?const onArmKey = [\s\S]*?\n  }\n/, 'pressable, onRecordDown, onArmDown, onMove, onRelease, onRecordClick, onArmKey (:301-422)'),
    piece('player/Turntable.tsx', /grabbed: \(\) => \{[\s\S]*?\n      },\n/, 'the host\'s grabbed (:237)'),
    piece('player/Turntable.tsx', /const handTurn = [^\n]*\n/, 'the record\'s turn as drawn (:426)'),
    piece('player/NowPlaying.tsx', /const onToggle = \(\) => \{[\s\S]*?\n  }\n/, 'the turntable\'s toggle (:282)'),
  ]
}

function pressFixture() {
  return {
    about: 'The handlers TurntablePress.swift ports, each read out of the web\'s source and hashed: a change to one fails ui/test/iosdeck.sim.cjs until the port follows and this is written again - even where the traces beside it (press/*.json, the Turntable mounted and driven) don\'t move.',
    made_by: MADE_BY,
    made_from: Object.fromEntries(handlerPieces().map((p) => p.from)),
  }
}

let pressStage = null
function pressWorld() {
  if (pressStage) return pressStage
  const T = rulesWorld()
  const H = T.H
  //? turntable.sim's stand-ins (:69-101): Preact as plain objects and a hook cursor, no covers or glyphs, and the
  //? position hook reading the player's position
  const stubs = {
    'node_modules/preact/jsx-runtime.js': 'exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })\nexports.Fragment = \'fragment\'\n',
    'node_modules/preact/hooks.js': [
      'let current = null',
      'function slot(init) { const i = current.cursor++; if (!(i in current.slots)) current.slots[i] = init(); return current.slots[i] }',
      'const changed = (a, b) => !a || !b || a.length !== b.length || a.some((v, i) => !Object.is(v, b[i]))',
      'exports.useState = (v) => { const s = slot(() => ({ v: typeof v === \'function\' ? v() : v })); return [s.v, (x) => { s.v = typeof x === \'function\' ? x(s.v) : x }] }',
      'exports.useMemo = (f, deps) => { const s = slot(() => ({})); if (changed(s.deps, deps)) { s.v = f(); s.deps = deps } return s.v }',
      'exports.useCallback = (f, deps) => exports.useMemo(() => f, deps)',
      'exports.useRef = (v) => slot(() => ({ current: v }))',
      'exports.useEffect = exports.useLayoutEffect = (f, deps) => { const s = slot(() => ({})); if (changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f } }',
      'exports.root = (component) => {',
      '  const root = { slots: [], cursor: 0, effects: [] }',
      '  const render = (props) => { const outer = current; current = root; root.cursor = 0; try { return component(props) } finally { current = outer } }',
      '  render.commit = () => { for (const s of root.effects.splice(0)) { if (typeof s.cleanup === \'function\') s.cleanup(); s.cleanup = s.f() } }',
      '  render.unmount = () => { for (const s of root.slots) if (s && typeof s.cleanup === \'function\') s.cleanup() }',
      '  return render',
      '}',
    ].join('\n') + '\n',
    'player/Cover.js': 'exports.Cover = function Cover() { return null }\n',
    'player/icons.js': 'module.exports = new Proxy({}, { get: (_, name) => { const f = function () { return null }; Object.defineProperty(f, \'name\', { value: String(name) }); return f } })\n',
    'player/usePlayer.js': 'exports.usePosition = (player) => player.position()\nexports.useSpeed = (player) => (player.speed ? player.speed() : 1)\n',
  }
  for (const [file, text] of Object.entries(stubs)) {
    const at = path.join(OUT, file)
    if (require.cache[at]) throw new Error(`press: ${file} was loaded before its stand-in was written`)
    fs.mkdirSync(path.dirname(at), { recursive: true })
    fs.writeFileSync(at, text)
  }
  //? a document that knows the stage's box (1:1 - a point of the drawing is a point on screen), and is showing
  class FakeElement {
    constructor(name) { this.name = name; this.style = {}; this.classList = { toggle() {} } }
    focus() { globalThis.document.activeElement = this }
    querySelector() { return null }
    getBoundingClientRect() { return { ...PRESS_BOX, right: PRESS_BOX.left + PRESS_BOX.width, bottom: PRESS_BOX.top + PRESS_BOX.height } }
  }
  globalThis.document = {
    body: new FakeElement('body'), documentElement: new FakeElement('html'), activeElement: null, visibilityState: 'visible',
    addEventListener() {}, removeEventListener() {},
  }
  globalThis.HTMLElement = FakeElement
  globalThis.localStorage = { getItem: () => null, setItem() {}, removeItem() {} }
  const S = { T, H, FakeElement, P: null }
  //? the render's own values, told as it draws (a patch to the compiled Turntable that reads and changes nothing)
  globalThis.__press = { rendered: (values) => { if (S.P) S.P.rendered = values } }
  S.hooks = load('node_modules/preact/hooks.js')
  S.Turntable = load('player/Turntable.js').Turntable
  S.NowPlaying = load('player/NowPlaying.js').NowPlaying
  //? wakeDeckAudio, as the handlers reach it (the module's export, read at each call)
  const realWake = H.deckModule.wakeDeckAudio
  S.wake = realWake
  H.deckModule.wakeDeckAudio = () => (S.P ? S.P.call('wake', [], () => realWake()) : realWake())
  //? a window that never comes, for a press before the record can sound
  const harnessFetch = globalThis.fetch
  globalThis.fetch = (url, init) => (S.P?.holdWindows ? new Promise(() => {}) : harnessFetch(url, init))
  pressStage = S
  return S
}

/** turntable.sim's mount (:180): renders, gives each element a FakeElement (its ref's), and finds by class. */
function pressMount(S, component, name) {
  const render = S.hooks.root(component)
  const elements = new Map()
  let tree = null
  const walk = (node, where) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach((child, i) => walk(child, `${where}.${i}`)); return }
    if (typeof node.type === 'string') {
      const key = `${where}:${node.type}`
      if (!elements.has(key)) elements.set(key, new S.FakeElement(`${name} ${node.type}`))
      node.element = elements.get(key)
      if (node.props.ref) node.props.ref.current = node.element
    }
    walk(node.props?.children, `${where}/`)
  }
  const find = (className) => {
    const hits = []
    const visit = (node) => {
      if (!node || typeof node !== 'object') return
      if (Array.isArray(node)) { node.forEach(visit); return }
      if (typeof node.props?.class === 'string' && node.props.class.split(' ').includes(className)) hits.push(node)
      visit(node.props?.children)
    }
    visit(tree)
    return hits[0]
  }
  return {
    render(props) { tree = render(props); walk(tree, ''); render.commit(); return tree },
    unmount: () => render.unmount(),
    find,
  }
}

/** A new press case: the harness's world afresh, a fake player, and the helpers that drive the Turntable. */
function pressCase() {
  const S = pressWorld()
  const { T, H } = S
  T.on = false
  Object.assign(H, { decodeWith: null, decodeMode: 'now', answer: 'window', windowSeconds: 40, reduced: false, timers: [], frames: [], portMessages: [] })
  H.clock = Math.ceil(H.clock / 1000) * 1000 + 1000
  const P = {
    S, H, events: [], recording: false, inHandler: false, depth: 0, holdWindows: false, rendered: null, last: {},
    turn: null, told: null, said: null, frameAt: H.clock + 16, tickAt: H.clock + 250, points: new Map(), windDown: true,
  }
  S.P = P
  P.push = (entry) => { if (P.recording) P.events.push(entry) }
  const quiet = (run) => {
    const was = maths.on
    maths.on = false
    try { return run() } finally { maths.on = was }
  }
  //? a call a handler makes, recorded with what it returned and the state after it - one made inside another isn't
  P.call = (name, args, run, returned) => {
    if (!P.inHandler || P.depth > 0 || !P.recording) {
      P.depth++
      try { return quiet(run) } finally { P.depth-- }
    }
    P.depth++
    let out
    try { out = quiet(run) } finally { P.depth-- }
    P.push([name, ...args, ...(returned ? ['->', ...returned(out)] : [])])
    P.after()
    return out
  }
  const proto = H.Deck.prototype
  P.query = (name) => quiet(() => proto[name].call(P.deck))
  P.state = () => ({ playing: P.player.playing, live: P.query('live'), taken: P.query('taken'), anchor: d(P.query('anchor')) })
  const changed = (now) => {
    const out = {}
    for (const [key, value] of Object.entries(now)) if (P.last[key] !== value) out[key] = value
    Object.assign(P.last, now)
    return out
  }
  P.after = () => {
    const moved = changed(P.state())
    if (Object.keys(moved).length) P.push(['after', moved])
  }
  P.world = () => {
    const r = P.rendered
    const moved = changed({
      ...P.state(), length: d(r.length), track: r.track, drawnAt: d(r.position), shown: d(r.shown), now: d(H.clock), flac: r.flac, noAudio: r.noAudio,
    })
    if (Object.keys(moved).length) P.push(['world', moved])
  }
  P.props = () => ({
    player: P.player, open: true, discArt: null, onPreview() {}, deck: P.deckRef, windDown: P.windDown,
    onSilent: (note) => { P.told = note },
  })
  P.draw = () => quiet(() => P.view.render(P.props()))
  //? the turn and the silent line, as the render drew and told them - outside an input, with the world they came from
  P.results = (inside) => {
    const turn = d(P.rendered.handTurn)
    if (turn !== P.turn || P.told !== P.said) {
      if (!inside) P.world()
      if (turn !== P.turn) P.push(['turn', turn])
      if (P.told !== P.said) P.push(['silent', P.told])
      P.turn = turn
      P.said = P.told
    }
  }
  //? an input: the world it finds, the handler run (its own Math recorded), the render after it
  P.input = (entry, run) => {
    P.world()
    P.push(entry)
    P.inHandler = true
    maths.on = true
    try { run() } finally { maths.on = false; P.inHandler = false }
    P.draw()
    P.results(true)
  }
  //? the world moving on: the deck's timers at their own times, its frames every 16 ms, the song's position told every
  //? 250 ms while it plays (the element's timeupdate), the promises settled, and the turntable drawn
  P.wait = async (ms) => {
    const end = H.clock + ms
    while (H.clock < end) {
      const step = Math.min(end, P.frameAt, P.tickAt)
      quiet(() => H.advance(step - H.clock))
      if (H.clock === P.frameAt) {
        P.frameAt += 16
        const frames = H.frames
        H.frames = []
        quiet(() => { for (const frame of frames) frame.run(H.clock) })
      }
      if (H.clock === P.tickAt) {
        P.tickAt += 250
        if (P.player.playing) quiet(() => P.player.moveTo(P.player.at + 0.25))
      }
      for (let i = 0; i < 3; i++) await H.settle()
      P.draw()
    }
    P.results(false)
  }
  P.make = async ({ track = PRESS_FLAC, at = 60, playing = true, wake = true, windows = true } = {}) => {
    P.player = pressPlayer(P, track, at, playing)
    P.deckRef = { current: null }
    P.view = pressMount(S, S.Turntable, 'turntable')
    P.holdWindows = !windows
    P.draw()
    const deck = P.deck = P.deckRef.current
    //? the deck's calls, as the handlers make them
    for (const name of PRESS_CALLS) {
      const real = proto[name]
      deck[name] = (...args) => P.call(name, args.map(pressWord), () => real.apply(deck, args), PRESS_RETURNS[name])
    }
    for (const name of PRESS_QUIET) {
      const real = proto[name]
      deck[name] = (...args) => {
        P.depth++
        try { return quiet(() => real.apply(deck, args)) } finally { P.depth-- }
      }
    }
    const grabbed = deck.host.grabbed
    deck.host.grabbed = () => {
      if (P.inHandler) throw new Error('press: the deck grabbed the record inside a handler - the trace has no place for that')
      if (!P.recording) return grabbed()
      //? an input of its own (the deck's timer, the last thing it does): the world it finds, then the render after it
      P.world()
      P.push(['grabbed'])
      grabbed()
      P.draw()
      P.results(true)
    }
    //? the audio woken (a tap before the case) and the window let in
    if (wake) quiet(() => S.wake())
    await P.wait(400)
    P.recording = true
    //? the whole world, the first time
    P.last = {}
    P.world()
    //? a turntable mounted afresh: unturned and saying nothing (TurntablePressTests starts from there)
    if (P.rendered.handTurn !== 0 || P.told !== null) throw new Error('press: a fresh turntable drawn turned, or saying something')
    P.turn = d(P.rendered.handTurn)
    P.said = P.told
  }
  P.end = async () => {
    P.recording = false
    P.view.unmount()
    P.nowPlayingView?.unmount()
    for (let i = 0; i < 3; i++) await H.settle()
    S.P = null
  }
  //? a pointer event, a browser's
  const pointer = (id, point, time, extra = {}) => ({
    pointerId: id, isPrimary: true, pointerType: 'touch', button: 0, clientX: point.x, clientY: point.y, timeStamp: time,
    currentTarget: { setPointerCapture() {} }, ...extra,
  })
  const part = (which) => P.view.find(which === 'arm' ? 'app-tt-handle' : 'app-tt-record')
  P.down = (point, { id = 1, primary = true, at = H.clock } = {}) => {
    P.points.set(id, point)
    P.input(['down', id, d(point.x), d(point.y), d(at)], () => part('record').props.onPointerDown(pointer(id, point, at, { isPrimary: primary })))
  }
  P.armDown = (point, { id = 2, primary = true, at = H.clock } = {}) => {
    P.points.set(id, point)
    P.input(['armDown', id, d(point.x), d(point.y)], () => part('arm').props.onPointerDown(pointer(id, point, at, { isPrimary: primary })))
  }
  //? a move: its samples ({t, x, y}, the last the event's own), coalesced as iOS and Chrome keep them - or none
  P.move = (which, samples, { id = 1, primary = true, coalesced = true } = {}) => {
    const last = samples[samples.length - 1]
    P.points.set(id, last)
    const event = pointer(id, last, last.t, { isPrimary: primary })
    if (coalesced) event.getCoalescedEvents = () => samples.map((s) => pointer(id, s, s.t, { isPrimary: primary }))
    const triple = (s) => [d(s.t), d(s.x), d(s.y)]
    P.input(['move', id, coalesced ? samples.map(triple) : null, triple(last)], () => part(which).props.onPointerMove(event))
  }
  //? a lift: pointerup, then lostpointercapture (a cancel to the handlers, nothing after an up), then on the record
  //? the click - one call on the phone; a second finger, never captured and never primary, has the pointerup alone
  P.up = (which, { id = 1, primary = true, at = H.clock } = {}) => P.input(['up', id, d(at)], () => {
    const el = part(which)
    const event = pointer(id, P.points.get(id), at, { isPrimary: primary })
    el.props.onPointerUp(event)
    if (!primary) return
    el.props.onLostPointerCapture(event)
    if (which === 'record') el.props.onClick()
  })
  P.cancel = (which, { id = 1, at = H.clock } = {}) => P.input(['cancel', id, d(at)], () => {
    const el = part(which)
    const event = pointer(id, P.points.get(id), at)
    el.props.onPointerCancel(event)
    el.props.onLostPointerCapture(event)
  })
  P.key = (key) => P.input(['key', key], () => part('arm').props.onKeyDown({ key, preventDefault() {} }))
  //? Now Playing's transport, on the turntable, its deck the turntable's
  P.nowPlaying = () => {
    if (!P.nowPlayingView) {
      P.nowPlayingView = pressMount(S, S.NowPlaying, 'now playing')
      P.nowPlayingProps = { player: P.player, open: true, covered: false, opener: { current: null }, onClose() {}, onMore() {}, onAlbum() {}, openAs: 'turntable' }
      quiet(() => P.nowPlayingView.render(P.nowPlayingProps))
    }
    const tree = quiet(() => P.nowPlayingView.render(P.nowPlayingProps))
    const turntable = (function find(node) {
      if (!node || typeof node !== 'object') return null
      if (Array.isArray(node)) { for (const child of node) { const hit = find(child); if (hit) return hit } return null }
      if (node.type === S.Turntable) return node
      return find(node.props?.children)
    })(tree)
    turntable.props.deck.current = P.deck
    P.input(['nowPlaying'], () => P.nowPlayingView.find('is-main').props.onClick())
  }
  //? the song changes: the turntable drawn for it, its effect dropping a drag for the song before
  P.song = (track) => {
    P.player.track = track
    P.player.duration = track.duration
    P.player.at = 0
    P.draw()
    P.world()
    P.push(['song', track.id])
    P.results(true)
  }
  //? where things are: a point on the record `degrees` round from its right, `r` from the spindle; the arm's handle
  P.onRecord = (degrees, r = 100) => quiet(() => ({ x: tt.RECORD.x + r * Math.cos((degrees / 180) * Math.PI), y: tt.RECORD.y + r * Math.sin((degrees / 180) * Math.PI) }))
  P.handleAt = () => quiet(() => tt.needleAt(P.rendered.shown, P.rendered.length))
  //? a turn of the record from `from` to `to` degrees over `ms`, a sample every `every` ms, `per` to an event (a
  //? 120 Hz digitizer under 60 Hz events is 8 and 2)
  P.turnRecord = async (from, to, ms, { every = 8, per = 2, id = 1, r = 100 } = {}) => {
    const t0 = H.clock
    let batch = []
    for (let t = every; t <= ms; t += every) {
      batch.push({ t: t0 + t, ...P.onRecord(from + ((to - from) * t) / ms, r) })
      if (batch.length === per || t + every > ms) {
        await P.wait(batch[batch.length - 1].t - H.clock)
        P.move('record', batch, { id })
        batch = []
      }
    }
  }
  P.live = () => P.query('live')
  return P
}

const PRESS_RETURNS = {
  takeOver: (out) => [d(out)],
  release: (out) => [out.seek === null ? null : d(out.seek), out.play],
  pausing: (out) => [out === null ? null : d(out)],
  resuming: (out) => [out === null ? null : d(out)],
}
const pressWord = (value) => (typeof value === 'number' ? d(value) : value)

function pressPlayer(P, track, at, playing) {
  const player = {
    track, playing, duration: track.duration, at, listeners: new Set(),
    seek(t) { return P.call('seek', [d(t)], () => { player.at = t }) },
    toggle() { return P.call('toggle', [], () => { player.playing = !player.playing }) },
    position: () => player.at,
    onPosition(listener) { player.listeners.add(listener); return () => player.listeners.delete(listener) },
    moveTo(seconds) { player.at = seconds; for (const listener of [...player.listeners]) listener(seconds) },
    //? what Now Playing reads besides (turntable.sim's)
    buffering: false, error: null, airplay: false, gapless: false, previous() {}, next() {}, showAirPlay() {},
    shuffle: false, repeat: 'off', queue: { tracks: [], index: 0 }, setShuffle() {}, setRepeat() {},
  }
  return player
}

//? THE CASES: each the spec's 7.0 asks for, in as few inputs as says it
const PRESS_CASES = [
  ['tap-pause-then-play', 'a tap on a playing record pauses it in the click, winding down; a tap 0.1 s in plays from where the record is; then Now Playing\'s transport does both', async (P) => {
    await P.make()
    const at = P.onRecord(0)
    P.down(at)
    await P.wait(80)
    P.up('record')
    await P.wait(100)
    P.down(at)
    await P.wait(60)
    P.up('record')
    await P.wait(600)
    P.nowPlaying()
    await P.wait(100)
    P.nowPlaying()
    await P.wait(300)
  }],
  ['turn-then-tap', 'a turn past a tap, coalesced at 120 Hz: taken from the press, let go to the motor; its click no tap - and a tap after it plays or pauses again', async (P) => {
    await P.make()
    P.down(P.onRecord(0))
    await P.turnRecord(0, 50, 96)
    await P.wait(8)
    P.up('record')
    await P.wait(700)
    P.down(P.onRecord(50))
    await P.wait(70)
    P.up('record')
    await P.wait(200)
  }],
  ['hold-then-let-go', 'a press held still past HOLD_MS: the deck takes it (grabbed), and let go it spins back up - its click no tap', async (P) => {
    await P.make()
    P.down(P.onRecord(200))
    await P.wait(320)
    P.up('record')
    await P.wait(500)
  }],
  ['rest-then-nudge', 'a press nudged inside a tap\'s few pixels, then resting: taken (grabbed - the hand\'s turn counts from there), nudged again and let go: the record stays where the hand left it', async (P) => {
    await P.make({ playing: false })
    P.down(P.onRecord(90))
    await P.turnRecord(90, 91.5, 32, { every: 16, per: 1 })
    await P.wait(300)
    await P.turnRecord(91.5, 93, 32, { every: 16, per: 1 })
    P.up('record')
    await P.wait(300)
  }],
  ['turn-back-past-the-start', 'a playing record near the start of the song, pressed as its position is told, and turned back a whole turn: held at 0:00 from where the deck took it, not from where the song was last drawn', async (P) => {
    await P.make({ at: 0.6 })
    P.down(P.onRecord(0))
    await P.wait(120)
    await P.turnRecord(0, -400, 80, { every: 8, per: 2 })
    P.up('record')
    await P.wait(400)
  }],
  ['flick-paused-and-tap-while-coasting', 'a paused record flicked: let go it coasts, sought to where it stops, left paused; a tap while it coasts plays from where it is', async (P) => {
    await P.make({ playing: false, at: 120 })
    P.down(P.onRecord(-30))
    await P.turnRecord(-30, 60, 80, { every: 8, per: 2 })
    P.up('record')
    await P.wait(150)
    P.down(P.onRecord(60))
    await P.wait(50)
    P.up('record')
    await P.wait(400)
  }],
  ['press-while-coasting-back', 'a flick back on a playing record, then a press catching it as it comes back to speed, turned on and let go', async (P) => {
    await P.make({ at: 200 })
    P.down(P.onRecord(40))
    await P.turnRecord(40, -20, 64, { every: 8, per: 2 })
    P.up('record')
    await P.wait(120)
    P.down(P.onRecord(-20))
    await P.turnRecord(-20, -5, 48, { every: 16, per: 1 })
    P.up('record')
    await P.wait(800)
  }],
  ['silent-press', 'a FLAC before its window has come: .11\'s press - the record held still, the song playing on under the finger, sought where the turn lets go; its click no tap, the next a pause; no silent line (it will sound)', async (P) => {
    await P.make({ windows: false })
    P.down(P.onRecord(10))
    await P.turnRecord(10, 70, 64, { every: 16, per: 1 })
    P.up('record')
    await P.wait(100)
    P.down(P.onRecord(70))
    await P.wait(60)
    P.up('record')
    await P.wait(200)
  }],
  ['not-flac', 'an MP3 turned: silent, the line said from the first turn of the song; let go it is sought; a tap pauses; the song changing takes the line away', async (P) => {
    await P.make({ track: PRESS_MP3 })
    P.down(P.onRecord(0))
    await P.wait(30)
    P.move('record', [{ t: P.H.clock, ...P.onRecord(1) }], { coalesced: false })
    await P.turnRecord(1, 30, 48, { every: 16, per: 1 })
    P.up('record')
    await P.wait(100)
    P.down(P.onRecord(30))
    await P.wait(70)
    P.up('record')
    await P.wait(100)
    P.song(PRESS_NEXT)
    await P.wait(200)
  }],
  ['the-arm', 'the arm: no seek inside its slop, held past it round the pivot, let go and sought; its keys; and a cancel that seeks nowhere', async (P) => {
    await P.make({ at: 100 })
    const handle = P.handleAt()
    P.armDown(handle, { id: 2 })
    await P.wait(16)
    P.move('arm', [{ t: P.H.clock, x: handle.x + 3, y: handle.y + 2 }], { id: 2, coalesced: false })
    for (let step = 1; step <= 4; step++) {
      await P.wait(16)
      P.move('arm', [{ t: P.H.clock - 8, x: handle.x - 6 * step + 3, y: handle.y + 7 * step - 2 }, { t: P.H.clock, x: handle.x - 6 * step, y: handle.y + 7 * step }], { id: 2 })
    }
    P.up('arm', { id: 2 })
    await P.wait(100)
    for (const key of ['ArrowRight', 'PageDown', 'Home', 'End', 'a']) {
      P.key(key)
      await P.wait(50)
    }
    const again = P.handleAt()
    P.armDown(again, { id: 3 })
    await P.wait(16)
    P.move('arm', [{ t: P.H.clock, x: again.x - 20, y: again.y + 25 }], { id: 3, coalesced: false })
    P.cancel('arm', { id: 3 })
    await P.wait(100)
  }],
  ['cancel-a-taken-press', 'a press taken by a turn, then cancelled (the system took the touch): nothing sought, the song it paused plays on - and no click', async (P) => {
    await P.make()
    P.down(P.onRecord(120))
    await P.turnRecord(120, 135, 48, { every: 8, per: 2 })
    P.cancel('record')
    await P.wait(300)
  }],
  ['second-finger', 'a finger on the record, and a second on the arm meanwhile: the second starts nothing, moves nothing and lets go of nothing', async (P) => {
    await P.make()
    P.down(P.onRecord(0))
    await P.wait(20)
    const handle = P.handleAt()
    P.armDown(handle, { id: 2, primary: false })
    await P.wait(16)
    P.move('arm', [{ t: P.H.clock, x: handle.x - 30, y: handle.y + 30 }], { id: 2, primary: false, coalesced: false })
    P.up('arm', { id: 2, primary: false })
    await P.turnRecord(0, 20, 48, { every: 16, per: 1 })
    P.up('record')
    await P.wait(300)
  }],
  ['song-change-under-a-press', 'the song changes under a still press the deck can\'t take (its window not come): the drag goes, and the lift\'s click is a tap all the same - it pauses the new song', async (P) => {
    await P.make({ windows: false })
    P.down(P.onRecord(45))
    await P.wait(100)
    P.song(PRESS_NEXT)
    await P.wait(100)
    P.up('record')
    await P.wait(200)
  }],
]

async function pressFixtures() {
  const made = []
  const from = () => Object.fromEntries([...handlerPieces().map((p) => p.from), whole('player/deck.ts'), whole('lib/turntable.ts'), whole('lib/deckClock.ts'), whole('lib/scrub.ts')])
  for (const [name, about, run] of PRESS_CASES) {
    const P = pressCase()
    await run(P)
    await P.end()
    made.push([`press/${name}.json`, {
      about,
      made_by: MADE_BY,
      made_from: from(),
      name,
      box: [d(PRESS_BOX.left), d(PRESS_BOX.top), d(PRESS_BOX.width), d(PRESS_BOX.height)],
      events: P.events,
    }, 2])
  }
  return made
}

function encodeInputs(inputs) {
  const bytes = []
  const scratch8 = new Uint8Array(8), view8 = new DataView(scratch8.buffer)
  for (const { op, t, args } of inputs) {
    bytes.push(op)
    for (const value of [t, ...args]) {
      setF64(view8, 0, value, true)
      for (const byte of scratch8) bytes.push(byte)
    }
  }
  return Buffer.from(bytes).toString('base64')
}

function effectsOut(effects) {
  const spans = []
  for (let i = 0; i < effects.length; i += EFFECT_SPAN) {
    const state = [...FNV_START]
    for (const words of effects.slice(i, i + EFFECT_SPAN)) fnvBytes(state, Buffer.from(words + '\n', 'utf8'))
    spans.push(fnvHex(state))
  }
  return { count: effects.length, spans, whole: effects.length <= EFFECTS_WHOLE ? effects : null }
}

async function rulesFixtures() {
  const made = []
  const finish = (name, about, T) => {
    T.on = false
    made.push([`rules/${name}.json`, {
      about,
      made_by: MADE_BY,
      made_from: Object.fromEntries([whole('player/deck.ts'), whole('lib/platter.ts'), whole('lib/deckVoice.ts'), whole('lab/motions.ts')]),
      name,
      songs: T.songs.map((song) => [song.id, d(song.length), song.flac, song.kind]),
      words: T.words,
      inputs: { count: T.inputs.length, bytes: encodeInputs(T.inputs) },
      stamps: f64s(T.stamps),
      effects: effectsOut(T.effects),
    }, 2])
  }
  //? all eight at 60 Hz; at 120 Hz the five whose shapes differ - the steady 0.5x, 0.25x and 2x are steady1's at
  //? another speed, and the folder's 3 MB had no room for them twice (the spec's 7.0 budget; a departure, written there)
  for (const hz of [60, 120]) {
    for (const [i, motion] of motions.MOTIONS.entries()) {
      if (hz === 120 && ['half', 'quarter', 'double'].includes(motion.id)) continue
      const T = await motionCase(motion, hz, 900 + i + hz)
      finish(`motion-${motion.id}-${hz}`, `the bench's "${motion.label}" (lab/motions.ts) at ${hz} Hz with seeded jitter, driven as lab/runner.ts runMotion drives it: taken at its start, let go ${8} ms after its last sample, the seek and play its release asks for, the song played on 3 s`, T)
    }
  }
  for (const [name, about, run] of RULE_CASES) {
    const T = rulesCase()
    await run(T)
    if (T.deck && !T.destroyed) T.call('destroy')
    finish(name, about, T)
  }
  return made
}

/* ===== the run ===== */

async function main() {
  emit('jsmath.json', jsmathFixture(), 2)
  emit('tokens.json', tokensFixture(), 3)
  emit('platter.json', platterFixture(), 3)
  emit('turntable.json', turntableFixture(), 3)
  emit('words.json', wordsFixture(), 3)
  for (const [name, value, depth] of voiceFixtures(syntheticVoiceCases())) emit(name, value, depth)
  for (const [name, value, depth] of await rulesFixtures()) emit(name, value, depth)
  emit('press/handlers.json', pressFixture(), 2)
  for (const [name, value, depth] of await pressFixtures()) emit(name, value, depth)
  maths.on = false
  emit('maths.json', mathsFixture(), 2)
  emit('made.json', {
    about: 'Who made these fixtures, and with what. Each file names the web sources it was made from (`made_from`); besides them only the Math functions\' answers move what a file holds, and those are the Node\'s, the platform\'s and the CPU\'s (V8 is not the same everywhere; nor is a NaN\'s sign, which the files write as one). So iosdeck.sim\'s --check, run on `made_on`, compares every file byte for byte; on any other Node, platform or arch it checks the sources: a file whose made_from is unchanged may differ by that Node\'s Math alone, and is listed rather than failed - except the files no Math answer reaches (jsmath.json, tokens.json, voice/windows.json, press/handlers.json), which must match anywhere. `made_with`: this script and its harness - a change to either fails the check everywhere until the fixtures are written again.',
    made_by: MADE_BY,
    made_on: MADE_ON,
    made_with: MADE_WITH,
  }, 2)

  fs.rmSync(OUT, { recursive: true, force: true })
  const total = Object.values(files).reduce((sum, body) => sum + Buffer.byteLength(body), 0)
  if (CHECK) {
    check(total)
    return
  }
  drifted()
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

/**
 * --check: everything made again in memory, and held to what is committed. On the Node, platform and arch that made
 * them (made.json's `made_on`) every file must be the same byte for byte - a full check. On any other, the Math
 * functions may answer otherwise (V8's own code differs between versions; x64 and arm64 differ in a NaN's sign, which
 * is written as one now, but not only there), so a file whose sources are unchanged may differ by that alone: it is
 * listed, not failed - a sources-only check. Either way, a file whose sources changed, a new or missing one, a stray,
 * one of EXACT's, or a change to this script or its harness fails.
 */
function check(total) {
  const kept = readJson(path.join(FIXTURES, 'made.json'))
  const maker = kept && kept.made_on
  const full = !!maker && onText(maker) === onText(MADE_ON)
  const toolsMoved = !kept || JSON.stringify(kept.made_with) !== JSON.stringify(MADE_WITH)
  console.log(full
    ? `Check: full, on the maker's Node (${onText(MADE_ON)})`
    : `Check: sources only, on Node ${onText(MADE_ON)} (made on ${maker ? onText(maker) : 'an unknown Node'})`)
  drifted()
  const failed = [], mathOnly = []
  let same = 0
  for (const [name, body] of Object.entries(files)) {
    const at = path.join(FIXTURES, name)
    if (!fs.existsSync(at)) {
      failed.push(`${name} (missing)`)
      continue
    }
    if (name === 'made.json' && !full) continue
    const committed = fs.readFileSync(at)
    if (committed.equals(Buffer.isBuffer(body) ? body : Buffer.from(body))) {
      same += 1
      continue
    }
    if (full || toolsMoved || name === 'made.json') failed.push(name)
    else if (EXACT.has(name)) failed.push(`${name} (no Math answer reaches it)`)
    else if (!sameSources(name, committed)) failed.push(`${name} (its sources changed)`)
    else mathOnly.push(name)
  }
  const stray = listFiles(FIXTURES).filter((name) => !(name in files))
  if (failed.length || stray.length) {
    if (failed.length) console.log(`The turntable's fixtures differ from what the web's TypeScript does now: ${failed.join(', ')}.`)
    if (stray.length) console.log(`Fixtures/deck holds files this script no longer writes: ${stray.join(', ')}.`)
    //? written again on the maker's Node, the files only its Math moves stay as they are
    const where = maker ? ` (on ${onText(maker)}, the Node that made them, or every file its Math reaches moves too)` : ''
    if (toolsMoved) console.log(`This script or ui/test/deckHarness.cjs changed since the fixtures were written (made.json): run node ios/scripts/export-deck-vectors.cjs again${where}, and see what the Swift ports must follow.`)
    else console.log(`The web's code changed: port it to the Swift, run node ios/scripts/export-deck-vectors.cjs${where}, and see what the Swift ports must follow.`)
    process.exit(1)
  }
  if (total > BUDGET) {
    console.log(`The turntable's fixtures are ${Math.round(total / 1024)} KB, over their ${BUDGET / 1024} KB budget.`)
    process.exit(1)
  }
  const size = `${Math.round(total / 1024)} KB of ${BUDGET / 1024}`
  if (full) {
    console.log(`The turntable's ${Object.keys(files).length} fixtures match the web's TypeScript (${size}).`)
    return
  }
  console.log(`The turntable's ${Object.keys(files).length - 1} fixtures match the web's TypeScript in their sources (${size}): ${same} byte for byte${mathOnly.length ? `, ${mathOnly.length} differing only by this Node's Math (made on ${maker ? onText(maker) : 'an unknown Node'}, checked on ${onText(MADE_ON)}): ${mathOnly.join(', ')}` : ''}.`)
}

/** Says which recorded Math calls this Node answers otherwise than maths.json, if any. */
function drifted() {
  const counts = RECORDED.filter((name) => drift[name].size).map((name) => `${name} ${drift[name].size}`)
  if (!counts.length) return
  console.log(`Node ${process.version}'s Math answers some calls otherwise than the Node that made maths.json (${counts.join(', ')}). The committed answers were used where maths.json holds them; the calls it doesn't hold are this Node's, so a file made from them can differ for that alone.`)
}

/** A committed file's sources the same as the ones it would be made from now: its made_from, or for a voice
 *  stretch (.f32) its case's. */
function sameSources(name, committed) {
  const json = name.endsWith('.f32') ? name.replace(/\.f32$/, '.json') : name
  const had = json === name ? parseJson(committed) : readJson(path.join(FIXTURES, json))
  return !!had && !!madeFrom[json] && JSON.stringify(had.made_from) === JSON.stringify(madeFrom[json])
}

function parseJson(bytes) {
  try {
    return JSON.parse(bytes.toString('utf8'))
  } catch {
    return null
  }
}

function readJson(at) {
  return fs.existsSync(at) ? parseJson(fs.readFileSync(at)) : null
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
  const from = {}
  for (const name of Object.keys(madeFrom).sort()) Object.assign(from, madeFrom[name])
  return {
    about: 'Every exp, log, sin, cos, atan2, hypot, pow and log10 the web\'s ported code evaluated while the other fixtures were made - each entry its inputs\' and its answer\'s bits, as base64 of little-endian 64-bit words ([input, answer] or [a, b, answer]), sorted by input. How many calls each voice run made, and their order, is in its own voice/*.json (`maths`). `made_from`: every other file\'s.',
    made_by: MADE_BY,
    made_from: Object.fromEntries(Object.keys(from).sort().map((key) => [key, from[key]])),
    functions: RECORDED,
    table,
  }
}

main().catch((caught) => {
  console.error(caught && caught.stack)
  process.exit(1)
})
