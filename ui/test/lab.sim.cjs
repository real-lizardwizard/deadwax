/**
 * The test bench for the turntable (2.0.0-player.36, ui/src/lab/), its pure parts and its one join with
 * the app - James: "a test suite may be in order ... I want to be able to use the turntable on a few
 * different samples ... just as a sanity check". What it pins:
 *
 *  - THE SIGNALS (lab/signals.ts): every band-limited one has no partial at or above the source's Nyquist
 *    frequency at 44.1, 48 and 96 kHz; the band-limited square's samples hold no aliases, and the aliased
 *    square's do (its partials past it, its aliases moving with the speed); the clicks' kernel and the
 *    bursts' edges leave nothing past it; the bursts and the chord as named; each at its level
 *    (-12 dBFS peak, pink noise -20 dBFS RMS, the full-scale sine at full scale, silence silent); made
 *    twice they are identical; a periodic one's copied samples are its definition, far into the song.
 *  - THE WAV: written and read back, every sample within half a 24-bit step; a window of the song, the
 *    deck's, is exactly the song's samples [first, first + samples), cut at its end, a 416 past it.
 *  - THE EXACT READER on a steady 1x path is the signal itself (analytic, and through the sinc for samples).
 *  - THE OFFLINE REPLAY of a recording the REAL deck made in this sim (the real Turntable's deck and voice,
 *    both hosts, a motion run by lab/runner.ts through the deck's own methods, the windows from the bench's
 *    source) reproduces what the voice played to a stated bound, lined up with it.
 *  - THE SMOOTH PATH is zero-phase: a steady hand with a finger's jitter within a stated distance of the
 *    truth, and a step in speed not lagged.
 *  - "THE SOUND THAT ISN'T THE SIGNAL": a tone at a drifting speed against itself a few ms off reads clean;
 *    the same with a 1% wobble at 40 Hz added reads its sidebands at their level.
 *  - THE ABX's chance of a score by guessing, and THE MOTIONS' samples (60 a second, on the grid, the
 *    path, the jitter's size).
 *  - What the review of the review found: THE RUNNER asks for the player at the release (the bench's is a
 *    new object each time it starts or stops); THE LISTENING ROOM's place never before its start; THE
 *    BENCH'S PLAYER's place 0 until its element holds the song rendered; a check run's BLOCKS counted on
 *    the main thread only; the transport's line back to Ready when the sound runs again; and a recording
 *    NOTHING TOOK said so, never as a stall of the page (lab/reading.ts).
 *  - THE DECK'S WINDOW SOURCE: given, the deck asks deadwax nothing and decodes the source's window; not
 *    given, it asks deadwax as ever. The in-page recording is kept only when asked, and stops early when
 *    told; the live spectrogram's analyser hangs off the voice's node and reaches the speakers through a
 *    gain of 0.
 *
 * Run it with:  node ui/test/lab.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-lab-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lab/signals.ts', 'src/lab/motions.ts', 'src/lab/analysis.ts', 'src/lab/compare.ts', 'src/lab/runner.ts', 'src/lab/listen.ts', 'src/lab/benchPlayer.ts', 'src/lab/check.ts', 'src/lab/watch.ts', 'src/lab/reading.ts', 'src/lab/library.ts', 'src/player/Turntable.tsx',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor - decksound.sim.cjs's stand-in for Preact
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

/* ===== a page: timers, frames and a clock the run moves on ===== */

const define = (name, value) => Object.defineProperty(globalThis, name, { value, configurable: true, writable: true })
define('document', { visibilityState: 'visible', addEventListener() {}, removeEventListener() {} })
define('localStorage', { getItem: () => null, setItem: () => {}, removeItem: () => {} })
let real = 1000
let timers = []
let frames = []
let nextId = 1
define('performance', { now: () => real })
define('setTimeout', (run, ms = 0) => { const id = nextId++; timers.push({ id, at: real + Math.max(0, ms), run }); return id })
define('clearTimeout', (id) => { timers = timers.filter((timer) => timer.id !== id) })
define('requestAnimationFrame', (run) => { const id = nextId++; frames.push({ id, run }); return id })
define('cancelAnimationFrame', (id) => { frames = frames.filter((frame) => frame.id !== id) })
define('matchMedia', () => ({ matches: false, addEventListener() {}, removeEventListener() {} }))
globalThis.URL.createObjectURL = () => 'blob:lab'
globalThis.URL.revokeObjectURL = () => {}
const settle = async () => { for (let i = 0; i < 4; i++) await new Promise((resolve) => setImmediate(resolve)) }

const signals = require(path.join(OUT, 'lab/signals.js'))
const motions = require(path.join(OUT, 'lab/motions.js'))
const analysis = require(path.join(OUT, 'lab/analysis.js'))
const compareModule = require(path.join(OUT, 'lab/compare.js'))
const { compare } = compareModule
const { runMotion } = require(path.join(OUT, 'lab/runner.js'))
const listen = require(path.join(OUT, 'lab/listen.js'))
const reading = require(path.join(OUT, 'lab/reading.js'))
const voice = require(path.join(OUT, 'lib/deckVoice.js'))
const deckModule = require(path.join(OUT, 'player/deck.js'))
const { Turntable } = require(path.join(OUT, 'player/Turntable.js'))
const tt = require(path.join(OUT, 'lib/turntable.js'))

/** The power spectrum of `data` (zero-padded to a power of two) through the lab's own FFT. */
function spectrum(data, size) {
  const re = new Float64Array(size), im = new Float64Array(size)
  for (let i = 0; i < Math.min(size, data.length); i++) re[i] = data[i]
  analysis.fft(re, im)
  return Float64Array.from({ length: size / 2 + 1 }, (_, k) => re[k] * re[k] + im[k] * im[k])
}

/** The modified Bessel function J of the first kind, order n, by its series - for FM sidebands. */
function besselJ(n, x) {
  let sum = 0, fact = 1
  for (let k = 0; k < 40; k++) {
    let kn = 1
    for (let j = 1; j <= k + n; j++) kn *= j
    sum += ((k % 2 ? -1 : 1) * Math.pow(x / 2, 2 * k + n)) / (fact * kn)
    fact *= k + 1
  }
  return sum
}

async function main() {

  console.log('\nthe FFT it measures with: one bin a naive DFT checks')
  {
    const data = Float64Array.from({ length: 64 }, (_, i) => Math.sin(i * 0.7) + 0.3 * Math.cos(i * 2.1))
    const re = Float64Array.from(data), im = new Float64Array(64)
    analysis.fft(re, im)
    let dr = 0, di = 0
    for (let i = 0; i < 64; i++) { dr += data[i] * Math.cos((2 * Math.PI * 5 * i) / 64); di -= data[i] * Math.sin((2 * Math.PI * 5 * i) / 64) }
    check('bin 5 equals the DFT\'s', [round(re[5], 9), round(im[5], 9)], [round(dr, 9), round(di, 9)])
  }

  console.log('\nthe signals: band-limited where they say, aliased where they say, at their levels, the same every time')
  {
    const seconds = 2
    for (const rate of signals.SOURCE_RATES) {
      const limited = []
      for (const id of ['square', 'saw', 'triangle', 'sine440', 'sine1k', 'sine100', 'sine5k', 'fifth', 'chord', 'sineFull', 'bursts']) {
        const made = await signals.makeSignal(id, rate, { seconds })
        limited.push([id, Math.max(...made.partials.map((p) => p.hz)) < rate / 2])
      }
      check(`${rate} Hz: no partial of a band-limited signal at or past the Nyquist frequency`, limited.filter(([, ok]) => !ok), [])
      const aliased = await signals.makeSignal('squareAliased', rate, { seconds })
      check(`${rate} Hz: the aliased square says so, and its partials run past it`, [aliased.aliased, Math.max(...aliased.partials.map((p) => p.hz)) > rate / 2], [true, true])
    }
    //? and in the samples: a second of the band-limited square, and of the naive one, at 44.1 kHz - the
    //? energy anywhere but the odd harmonics of 220 Hz (one bin each, a second's FFT: 1 Hz bins)
    const size = 65536
    const bh = analysis.blackmanHarris(44100)
    const inharmonic = (made) => {
      const p = spectrum(made.channels[0].subarray(0, 44100).map((v, i) => v * bh[i]), size)
      let lines = 0, away = 0
      for (let k = 1; k < p.length; k++) {
        const hz = (k * 44100) / size
        const nearest = Math.round(hz / 220)
        const onLine = nearest % 2 === 1 && Math.abs(hz - nearest * 220) < 6
        if (onLine) lines += p[k]
        else away += p[k]
      }
      return 10 * Math.log10(away / lines)
    }
    const clean = inharmonic(await signals.makeSignal('square', 44100, { seconds: 1.5 }))
    const dirty = inharmonic(await signals.makeSignal('squareAliased', 44100, { seconds: 1.5 }))
    console.log(`    (energy off the odd harmonics: the band-limited square ${round(clean, 1)} dB, the naive one ${round(dirty, 1)} dB)`)
    check('the band-limited square\'s samples hold nothing off its harmonics but the window\'s leak (under -80 dB); the naive one\'s hold aliases (over -35 dB)', [clean < -80, dirty > -35], [true, true])

    //? its aliases are IN the song, so turned at any speed they move with it, as everything in it does -
    //? read at 0.5x, 1x and 2x by the exact reader, its strongest line that isn't an odd harmonic of the
    //? fundamental (120 Hz at 1x: the 201st harmonic, 44,220 Hz, folded down by the 44.1 kHz it was made
    //? at) is at 0.5, 1 and 2 times it - and its note says so, not that they move the other way
    {
      const naive = await signals.makeSignal('squareAliased', 44100, { seconds: 4 })
      const n = 65536, out = 48000, window = analysis.blackmanHarris(n)
      const strongest = (v) => {
        const read = analysis.readExactly(naive.exact, Float64Array.from({ length: n }, (_, i) => 1 + (v * i) / out), new Float64Array(n).fill(v), new Float64Array(n).fill(1), out, 0)
        const p = spectrum(read.map((x, i) => x * window[i]), n)
        let best = 0, at = 0
        for (let k = 2; k < p.length - 1; k++) {
          const hz = (k * out) / n
          if (hz > 300 * v) break
          const h = hz / (220 * v)
          const harmonic = Math.abs(h - Math.round(h)) < 0.02 && Math.round(h) % 2 === 1
          if (!harmonic && p[k] > p[k - 1] && p[k] >= p[k + 1] && p[k] > best) { best = p[k]; at = hz }
        }
        return at
      }
      const [half, one, double] = [0.5, 1, 2].map(strongest)
      const note = signals.SIGNALS.find((one) => one.id === 'squareAliased').shows
      console.log(`    (the aliased square's strongest alias under 300 Hz: ${round(half, 1)} Hz at 0.5x, ${round(one, 1)} Hz at 1x, ${round(double, 1)} Hz at 2x)`)
      check('the aliased square\'s aliases are in the song: turned at 0.5x and 2x its strongest alias moves to half and twice where it is at 1x (within a bin) - and its note says they move with the speed',
        [Math.abs(half - one / 2) < 1, Math.abs(double - 2 * one) < 1, one > 50, /move with the speed/.test(note) && !/wrong way/.test(note)], [true, true, true, true])
    }

    //? the clicks, evaluated at 4 times the source rate: nothing past the source's Nyquist frequency
    for (const rate of [44100, 96000]) {
      const made = await signals.makeSignal('clicks', rate, { seconds: 1 })
      const over = rate * 4
      const data = Float64Array.from({ length: over / 2 }, (_, i) => made.exact(i / over, Infinity))
      const p = spectrum(data, 2 ** Math.ceil(Math.log2(data.length)))
      let below = 0, above = 0
      for (let k = 1; k < p.length; k++) ((k * over) / (2 * (p.length - 1)) < rate / 2 ? (below += p[k]) : (above += p[k]))
      check(`clicks at ${rate} Hz: what is past the Nyquist frequency at least 70 dB under the click (${round(10 * Math.log10(above / below), 1)} dB)`, 10 * Math.log10(above / below) < -70, true)
    }

    //? the bursts' edges, evaluated at 4 times the source rate: nothing past the source's Nyquist frequency
    //? (their raised-cosine ramps; hard gates would splatter there) - and the bursts and the chord as named:
    //? 50 ms on of every 500, the notes 220, 277.18, 329.63 and 440 Hz
    {
      const rate = 44100
      const made = await signals.makeSignal('bursts', rate, { seconds: 1 })
      const over = rate * 4
      const data = Float64Array.from({ length: over / 2 }, (_, i) => made.exact(i / over, Infinity))
      const p = spectrum(data, 2 ** Math.ceil(Math.log2(data.length)))
      let below = 0, above = 0
      for (let k = 1; k < p.length; k++) ((k * over) / (2 * (p.length - 1)) < rate / 2 ? (below += p[k]) : (above += p[k]))
      const on = (t) => Math.abs(made.exact(t, Infinity)) > 0
      const anyOn = (from, to) => { for (let t = from; t < to; t += 1 / 96000) if (on(t)) return true; return false }
      const chord = await signals.makeSignal('chord', rate, { seconds: 1 })
      check(`the bursts' edges: what is past the Nyquist frequency at least 100 dB under the bursts (${round(10 * Math.log10(above / below), 1)} dB); on for the first 50 ms of every 500, off from then; the chord's notes as named`,
        [10 * Math.log10(above / below) < -100, anyOn(0.0026, 0.0474), anyOn(0.0501, 0.4999), anyOn(0.5026, 0.5474), chord.partials.map((p) => p.hz)],
        [true, true, false, true, [220, 277.18, 329.63, 440]])
    }

    const db = (v) => 20 * Math.log10(v)
    const peaks = []
    for (const id of ['sine440', 'sine1k', 'sine100', 'sine5k', 'fifth', 'square', 'saw', 'triangle', 'bursts', 'clicks', 'sweep']) {
      const made = await signals.makeSignal(id, 48000, { seconds: 3 })
      peaks.push([id, Math.abs(db(made.peak) + 12) < 0.05])
    }
    check('-12 dBFS peak (within 0.05 dB): the sines, the fifth, the square, sawtooth and triangle, the bursts, the clicks, the sweep', peaks.filter(([, ok]) => !ok), [])
    const chord = await signals.makeSignal('chord', 48000, { seconds: 10 })
    check('the chord never past -12 dBFS, and near it', [db(chord.peak) <= -12, db(chord.peak) > -14], [true, true])
    const pink = await signals.makeSignal('pink', 48000, { seconds: 10 })
    const rms = Math.sqrt(pink.channels[0].reduce((s, v) => s + v * v, 0) / pink.length)
    check('pink noise -20 dBFS RMS', round(db(rms), 2), -20)
    const full = await signals.makeSignal('sineFull', 48000, { seconds: 1 })
    const silence = await signals.makeSignal('silence', 48000, { seconds: 1 })
    check('the full-scale sine at full scale; silence silent', [round(full.peak, 6), silence.peak], [1, 0])

    const hash = (array) => { let h = 0; for (let i = 0; i < array.length; i += 7) h = (h * 31 + Math.round(array[i] * 1e7)) | 0; return h }
    const twice = []
    for (const id of ['sweep', 'pink', 'chord', 'clicks', 'squareAliased']) {
      const a = await signals.makeSignal(id, 44100, { seconds: 2 }), b = await signals.makeSignal(id, 44100, { seconds: 2 })
      twice.push([id, hash(a.channels[0]) === hash(b.channels[0])])
    }
    check('made twice, the same samples', twice.filter(([, ok]) => !ok), [])

    //? a periodic signal's samples are copied from one stretch: far into the song, still its definition
    const saw = await signals.makeSignal('saw', 44100, { seconds: 60 })
    const bursts = await signals.makeSignal('bursts', 48000, { seconds: 60 })
    const far = [123457, 1000003, 2599999].map((n) => Math.abs(saw.channels[0][n] - Math.fround(saw.exact(n / 44100, Infinity))))
      .concat([1234567, 2800001].map((n) => Math.abs(bursts.channels[0][n] - Math.fround(bursts.exact(n / 48000, Infinity)))))
    check('a copied stretch is the definition, a minute in (within 1e-7)', far.every((d) => d < 1e-7), true)
    //? ...and every signal copied so, at a rate whose stretch differs (44.1 and 96 kHz), samples far past
    //? its first stretch the definition
    const wrong = []
    for (const id of ['sine440', 'sine1k', 'sine100', 'sine5k', 'sineFull', 'fifth', 'square', 'saw', 'triangle', 'bursts', 'clicks', 'silence']) {
      for (const rate of [44100, 96000]) {
        const made = await signals.makeSignal(id, rate, { seconds: 12 })
        for (const n of [rate * 3 + 1234, rate * 7 + 77777, rate * 12 - 5]) {
          if (Math.abs(made.channels[0][n] - Math.fround(made.exact(n / rate, Infinity))) > 1e-7) { wrong.push([id, rate, n]); break }
        }
      }
    }
    check('...every periodic signal, at 44.1 and 96 kHz: far past its first stretch, its definition (within 1e-7)', wrong, [])
  }

  console.log('\nthe WAV, and the deck\'s window of the song')
  {
    const made = await signals.makeSignal('sweep', 44100, { seconds: 5 })
    const back = signals.readWav(signals.wavBytes(made.channels, 44100))
    let worst = 0
    for (let i = 0; i < made.length; i++) worst = Math.max(worst, Math.abs(back.channels[0][i] - made.channels[0][i]))
    check('read back: its rate, its length, every sample within half a 24-bit step', [back.rate, back.channels[0].length, worst <= 2 ** -24 + 1e-12], [44100, made.length, true])
    const full = await signals.makeSignal('sineFull', 48000, { seconds: 0.1 })
    const fullBack = signals.readWav(signals.wavBytes(full.channels, 48000))
    check('full scale held to the largest 24-bit value, never wrapped', round(Math.max(...fullBack.channels[0]), 7), round(1 - 2 ** -23, 7))
    const window = signals.signalWindow(made, 1.5, 2)
    const got = signals.readWav(window.bytes)
    let same = true
    for (let i = 0; i < window.samples; i++) if (Math.abs(got.channels[0][i] - made.channels[0][window.first + i]) > 2 ** -24 + 1e-12) same = false
    check('a window: from the sample nearest `from`, exactly the song\'s samples [first, first + samples)', [window.first, window.samples, window.rate, same], [66150, 88200, 44100, true])
    const tail = signals.signalWindow(made, 4, 40)
    check('cut short at the song\'s end', [tail.first, tail.samples], [176400, made.length - 176400])
    let past = null
    try { signals.signalWindow(made, 5, 40) } catch (error) { past = error.status }
    check('past the end: a 416, as deadwax says it', past, 416)
  }

  console.log('\nthe exact reader on a steady 1x path is the signal')
  {
    for (const id of ['square', 'sweep', 'pink', 'squareAliased']) {
      const made = await signals.makeSignal(id, 48000, { seconds: 2 })
      const n = 48000
      const place = Float64Array.from({ length: n }, (_, i) => 0.5 + i / 48000)
      const speed = new Float64Array(n).fill(1), gain = new Float64Array(n).fill(1)
      const read = analysis.readExactly(made.exact, place, speed, gain, 48000, 0)
      let worst = 0
      for (let i = 0; i < n; i++) worst = Math.max(worst, Math.abs(read[i] - made.channels[0][24000 + i]))
      check(`${id}: every sample the song's (within 1e-6)`, worst < 1e-6, true)
    }
    //? between the samples too: a file of a sampled sine read at (n + 0.37) / rate by the windowed sinc is
    //? the sine itself (within 1e-5); and a sampled 15 kHz tone, band-limited to 10 kHz, is nothing (within 1e-5)
    {
      const rate = 48000
      const sampled = (hz) => Float32Array.from({ length: rate * 2 }, (_, n) => 0.25 * Math.sin((2 * Math.PI * hz * n) / rate))
      const file = await signals.makeSignal('file', rate, { file: { name: 'a sine', channels: [sampled(1000)] } })
      const high = await signals.makeSignal('file', rate, { file: { name: 'a high tone', channels: [sampled(15000)] } })
      let between = 0, cut = 0
      for (let n = 24000; n < 24400; n++) {
        const t = (n + 0.37) / rate
        between = Math.max(between, Math.abs(file.exact(t, Infinity) - 0.25 * Math.sin(2 * Math.PI * 1000 * t)))
        cut = Math.max(cut, Math.abs(high.exact(t, 10000)))
      }
      console.log(`    (the sinc between samples: ${between.toExponential(2)} off the sine; a 15 kHz tone cut at 10 kHz: ${cut.toExponential(2)})`)
      check('a file read between its samples is the signal they hold (a sampled sine within 1e-5), and band-limited where asked (a sampled 15 kHz tone cut at 10 kHz: within 1e-5 of nothing)',
        [between < 1e-5, cut < 1e-5], [true, true])
    }
    const made = await signals.makeSignal('sine1k', 44100, { seconds: 1 })
    const read = analysis.readExactly(made.exact, [0.2501, 0.2503], [1, 1], [1, 1], 48000, 1)
    check('...and written its lookahead later, as the voice writes: the first sample where the read head was a sample before',
      [read[0], Math.abs(read[1] - made.exact(0.2501, Infinity)) < 1e-7, Math.abs(made.exact(0.2501, Infinity) - made.exact(0.2503, Infinity)) > 0.01], [0, true, true])
    //? at twice the speed a partial that would pass the output's Nyquist frequency is left out: what is
    //? read is the odd harmonics of 440 Hz and nothing else - no alias of the square's top folded down
    const square = await signals.makeSignal('square', 44100, { seconds: 1 })
    const fast = analysis.readExactly(square.exact, Float64Array.from({ length: 48000 }, (_, i) => (2 * i) / 48000), new Float64Array(48000).fill(2), new Float64Array(48000).fill(1), 48000, 0)
    const window = analysis.blackmanHarris(48000)
    const p = spectrum(fast.map((v, i) => v * window[i]), 65536)
    let lines = 0, away = 0
    for (let k = 1; k < p.length; k++) {
      const hz = (k * 48000) / 65536
      const nearest = Math.round(hz / 440)
      if (nearest % 2 === 1 && Math.abs(hz - nearest * 440) < 6) lines += p[k]
      else away += p[k]
    }
    check('read at 2x: the odd harmonics of 440 Hz and nothing else (no alias of the square\'s top folded down: under -90 dB)', 10 * Math.log10(away / lines) < -90, true)
    //? the ideal (brick-wall) reader's rule for a sum of sines: a partial kept whole under the cutoff and
    //? left out at it - the 5 kHz sine, the chord's top two notes, the sweep where it is
    const t = 0.01234
    const s5 = await signals.makeSignal('sine5k', 48000, { seconds: 1 })
    const chord = await signals.makeSignal('chord', 48000, { seconds: 1 })
    const sweep = await signals.makeSignal('sweep', 48000, { seconds: 1 })
    const lower = (signals.LEVEL / 4) * (Math.sin(2 * Math.PI * 220 * t) + Math.sin(2 * Math.PI * 277.18 * t))
    const swept = 60.0001 //? where the sweep is about 707 Hz
    check('a partial kept whole under the cutoff and left out at it: the 5 kHz sine at 4999.9, 5000 and 5000.1 Hz; the chord under 300 Hz its two lower notes; the sweep at 707 Hz under 700 and 720',
      [s5.exact(t, 4999.9), s5.exact(t, 5000), s5.exact(t, 5000.1) === s5.exact(t, Infinity) && s5.exact(t, Infinity) !== 0,
        Math.abs(chord.exact(t, 300) - lower) < 1e-12 && chord.exact(t, 300) !== chord.exact(t, Infinity), sweep.exact(swept, 700), sweep.exact(swept, 720) === sweep.exact(swept, Infinity) && sweep.exact(swept, 720) !== 0],
      [0, 0, true, true, 0, true])
  }

  console.log('\nthe smooth path: zero-phase - a jittery steady hand within a stated distance of the truth, a step in speed not lagged')
  {
    const random = signals.seeded(7)
    const samples = []
    for (let k = 0; k <= 360; k++) {
      const t = k / 60
      samples.push({ time: t, at: 10 + t + (motions.gaussian(random) * 1.5) / 1000 + motions.gaussian(random) * 0.001 })
    }
    const pathOf = analysis.smoothPath(samples)
    const errors = []
    for (let t = 0.3; t <= 5.7; t += 0.001) errors.push(pathOf(t).x - (10 + t))
    const rms = Math.sqrt(errors.reduce((s, e) => s + e * e, 0) / errors.length)
    const worst = Math.max(...errors.map(Math.abs))
    console.log(`    (a steady 1x hand, 1.5 ms and 1 ms of Gaussian jitter: ${round(rms * 1000, 3)} ms RMS, ${round(worst * 1000, 3)} ms at most)`)
    check('a steady hand with a finger\'s jitter: within 0.8 ms RMS, 2.5 ms at most, of the truth (the jitter itself 1.8 ms RMS)', [rms < 0.0008, worst < 0.0025], [true, true])
    const step = []
    for (let k = 0; k <= 360; k++) {
      const t = k / 60
      step.push({ time: t, at: t < 3 ? t : 3 + 2 * (t - 3) })
    }
    const stepPath = analysis.smoothPath(step)
    let crossing = null
    for (let t = 2.5; t <= 3.5; t += 0.0005) if (crossing === null && stepPath(t).v >= 1.5) crossing = t
    check('a step from 1x to 2x at 3 s: the speed crosses 1.5 within 3 ms of it', Math.abs(crossing - 3) < 0.003, true)
    //? a rest: a hand's last sample, then nothing for most of a second - the path runs on to still as the
    //? voice's does (RUN_ON_S, slowing from its last speed: half of it as far) and holds there
    const rest = analysis.smoothPath([{ time: 0, at: 0 }, { time: 1 / 60, at: 1 / 60 }, { time: 2 / 60, at: 2 / 60 }, { time: 1, at: 0.5 }, { time: 1 + 1 / 60, at: 0.5 }])
    const ran = rest(2 / 60).x + (rest(2 / 60).v * analysis.RUN_ON_S) / 2
    check('a rest between runs: the path runs on to still from the last sample (RUN_ON_S, from its speed there) and holds',
      [round(rest(0.5).x, 9), rest(0.5).v, rest(2 / 60 + analysis.RUN_ON_S + 0.001).v], [round(ran, 9), 0, 0])
  }

  console.log('\nthe smooth path never steps: no jump in place or speed where the hand lets go, misses samples, or rests and sets off')
  {
    //? the path scanned at the output's rate: its largest step against what its own speed moves it in a
    //? sample, and its largest change of speed in a sample (a speed is reached over JOIN_BRIDGE_S at the
    //? least, so no change of a whole x in a sample)
    const dt = 1 / 48000
    const scan = (path, from, to) => {
      let step = 0, fastest = 0, dv = 0, prev = null
      for (let t = from; t <= to; t += dt) {
        const point = path(t)
        if (!point) { prev = null; continue }
        if (prev) { step = Math.max(step, Math.abs(point.x - prev.x)); dv = Math.max(dv, Math.abs(point.v - prev.v)) }
        fastest = Math.max(fastest, Math.abs(point.v))
        prev = point
      }
      return { stepped: step > fastest * dt * 1.02 + 1e-9, dv }
    }
    //? the let-go: a hand at 1x with a finger's jitter, then the coast the deck plans - from the hand's RAW
    //? last sample (Deck.release), at its own speed estimate - for a hand recording, and a motion's exact
    //? path with the jitter ticked; and the same with no jitter
    const letGo = (random) => {
      const messages = [{ type: 'take', at: 30, rate: 1, time: 10, until: 10.12 }, { type: 'hand', at: 30, time: 10 }]
      let last = null
      for (let k = 1; k <= 360; k++) {
        const t = k / 60
        const at = random ? 30 + t + motions.gaussian(random) * 0.0015 + motions.gaussian(random) * 0.001 : 30 + t
        messages.push({ type: 'hand', at, time: 10 + t })
        last = { at, time: 10 + t }
      }
      for (let f = 0; f < 30; f++) messages.push({ type: 'drive', at: last.at + (0.97 * f) / 60, rate: 0.97, accel: 0, time: last.time + f / 60, until: last.time + f / 60 + 0.12 })
      return { messages, last }
    }
    const knots = { knots: Array.from({ length: 361 }, (_, k) => ({ time: 10 + k / 60, x: 30 + k / 60, v: 1 })) }
    const results = []
    for (const seed of [1, 2, 3, 4, 5]) {
      const { messages, last } = letGo(signals.seeded(seed))
      const hand = scan(analysis.pathFrom(messages, null), last.time - 0.05, last.time + 0.4)
      const exact = scan(analysis.pathFrom(messages, knots), last.time - 0.05, last.time + 0.4)
      results.push(!hand.stepped && !exact.stepped && hand.dv < 1e-3 && exact.dv < 1e-3)
    }
    const clean = letGo(null)
    const plain = analysis.pathFrom(clean.messages, null)
    check('the let-go, with a finger\'s jitter (five hands, and a motion\'s exact path with it ticked) and without: no step in place, the speed eased over to the coast\'s - and the coast reached, where the deck planned it, once its start is let go of',
      [results.every(Boolean), scan(plain, clean.last.time - 0.05, clean.last.time + 0.4).stepped,
        Math.abs(plain(clean.last.time + analysis.JOIN_DECAY_S + 0.01).x - (clean.last.at + 0.97 * (analysis.JOIN_DECAY_S + 0.01))) < 1e-9],
      [true, false, true])
    //? missed samples: a steady 1x hand three frames short (67 ms, a busy page with no coalesced events) is
    //? no rest - the hand kept moving, so the path runs straight through, as the voice does
    const gap = [{ time: 0, at: 30 }]
    for (let k = 1; k <= 240; k++) if (k < 121 || k > 123) gap.push({ time: k / 60, at: 30 + k / 60 })
    const through = analysis.smoothPath(gap)
    let off = 0
    for (let t = 1.5; t <= 2.6; t += 0.001) off = Math.max(off, Math.abs(through(t).x - (30 + t)))
    check('three missed frames in a steady hand: the path runs straight through them (within 0.01 ms of the hand), with no step', [off < 1e-5, scan(through, 1.5, 2.6).stepped], [true, false])
    //? a rest and the hand off again (ramping 0 to 1.5x over 60 ms), with a finger's jitter and without:
    //? no step where it sets off - it does, just before its first sample (SET_OFF_S), from where it held
    const resumes = []
    for (const jittered of [false, true]) {
      const random = signals.seeded(21)
      const finger = () => (jittered ? motions.gaussian(random) * 0.0015 + motions.gaussian(random) * 0.001 : 0)
      const samples = []
      for (let k = 0; k <= 30; k++) samples.push({ time: k / 60, at: 30 + k / 60 + finger() })
      const t1 = 0.5 + 0.3
      const ramp = (u) => (u < 0.06 ? (1.5 * u * u) / 0.12 : 0.045 + 1.5 * (u - 0.06))
      for (let k = 0; k <= 40; k++) samples.push({ time: t1 + k / 60, at: 30.5 + ramp(k / 60) + finger() })
      const path = analysis.smoothPath(samples)
      const held = path(0.7).x
      resumes.push([scan(path, 0, 1.6).stepped, path(t1 - analysis.SET_OFF_S - 1e-6).x === held, path(t1 - analysis.SET_OFF_S + 0.01).x !== held])
    }
    check('a rest, then the hand off again - with a finger\'s jitter and without: no step anywhere, held until just before its first sample, moving from then on',
      resumes, [[false, true, true], [false, true, true]])
    //? the rules are the voice's own: lib/deckVoice.ts's REST_S, MISSED_S, KEPT_ON, KEPT_S, EXTRAPOLATE_S, RESUME_S
    const voiceSource = fs.readFileSync(path.join(UI, 'src/lib/deckVoice.ts'), 'utf8')
    const voiceConst = (name) => Number(new RegExp(`const ${name} = ([\\d.]+)`).exec(voiceSource)?.[1])
    check('the smooth path splits, runs on and sets off by the voice\'s own rules (REST_S, MISSED_S, KEPT_ON, KEPT_S, EXTRAPOLATE_S, RESUME_S)',
      [analysis.REST_GAP_S, analysis.MISSED_GAP_S, analysis.KEPT_ON, analysis.KEPT_S, analysis.RUN_ON_S, analysis.SET_OFF_S],
      ['REST_S', 'MISSED_S', 'KEPT_ON', 'KEPT_S', 'EXTRAPOLATE_S', 'RESUME_S'].map(voiceConst))
    //? a motion's exact path through stamps that slew (0.5 ms a second, then not) and go up unevenly a
    //? few microseconds a frame - as the deck's do: C's speed as smooth as the motion's own definition (its
    //? wobble above 20 Hz within 0.00005% of the definition's own), where knots on the raw stamps with the
    //? definition's speeds read 0.0127%
    const wobble = motions.MOTIONS.find((m) => m.id === 'wobble')
    const samples = motions.motionSamples(wobble, 1000)
    const uneven = signals.seeded(9)
    const messages = [{ type: 'take', at: 20, rate: 0, time: 5, until: 5.12 }]
    samples.forEach((sample, k) => {
      const t = (sample.time - 1000) / 1000
      messages.push({ type: 'hand', at: 20 + wobble.path(t), time: 5 + t + Math.min(t, 2) * 0.0005 + (k % 2 ? 1 : -1) * 3.5e-6 + (uneven() - 0.5) * 4e-6 })
    })
    const exact = analysis.exactKnots(messages, samples, 1000, 20, 120, wobble.path, wobble.speed)
    const n = Math.floor(5.9 * 48000)
    const v = Float64Array.from({ length: n }, (_, i) => analysis.pathFrom(messages, exact)(5.05 + i / 48000).v)
    const own = Float64Array.from({ length: n }, (_, i) => wobble.speed(0.05 + i / 48000))
    const span = [Math.round(0.3 * 48000), n - 4800]
    const c = analysis.speedWobble(v, 48000, ...span), d = analysis.speedWobble(own, 48000, ...span)
    const raw = analysis.pathFrom(messages, { knots: samples.map((sample, k) => ({ time: messages[k + 1].time, x: 20 + wobble.path((sample.time - 1000) / 1000), v: wobble.speed((sample.time - 1000) / 1000) })) })
    const rough = analysis.speedWobble(Float64Array.from({ length: n }, (_, i) => raw(5.05 + i / 48000).v), 48000, ...span)
    //? and its speed is its place's own rate of change, through the stamps' slew too (the speed the ideal
    //? reader band-limits by, and the wobble is measured on)
    const C = analysis.pathFrom(messages, exact)
    let disagree = 0
    for (let t = 5.4; t < 10.8; t += 0.0137) disagree = Math.max(disagree, Math.abs((C(t + 1e-5).x - C(t - 1e-5).x) / 2e-5 - C(t).v))
    console.log(`    (a motion through slewing, uneven stamps: C's wobble ${round(c, 6)}%, the definition's own ${round(d, 6)}%, knots on the raw stamps ${round(rough, 5)}%; its speed off its place's rate of change by ${disagree.toExponential(1)})`)
    check('a motion\'s exact path through slewing, uneven stamps: as smooth as the motion itself (wobble within 0.00005% of the definition\'s), where knots on the raw stamps aren\'t - and its speed its place\'s own rate of change (within 1e-6)',
      [Math.abs(c - d) < 5e-5, rough > 10 * d, disagree < 1e-6], [true, true, true])
  }

  console.log('\nthe sound that isn\'t the signal: a slow drift counts for nothing, a wobble\'s sidebands at their level')
  {
    const rate = 48000, n = rate * 6
    //? a tone read along a drifting speed (1x to 1.02x and back, every 10 s); and along the same a few ms
    //? off (3 ms at 0.3 Hz: a slow timing drift); and the same with a 1% wobble at 40 Hz in the speed
    const drift = (t) => t + (0.02 / (2 * Math.PI * 0.1)) * (1 - Math.cos(2 * Math.PI * 0.1 * t))
    const tone = (place) => Float32Array.from({ length: n }, (_, i) => 0.25 * Math.sin(2 * Math.PI * 1000 * place(i / rate)))
    const reference = tone(drift)
    const late = tone((t) => drift(t) + 0.003 * Math.sin(2 * Math.PI * 0.3 * t))
    const wobbled = tone((t) => drift(t) + (0.01 / (2 * Math.PI * 40)) * (1 - Math.cos(2 * Math.PI * 40 * t)))
    const clean = analysis.stray(late, reference, rate)
    const sidebands = analysis.stray(wobbled, reference, rate)
    //? a 1% wobble at 40 Hz on a 1 kHz tone: a deviation of 10 Hz, an index of 0.25
    const beta = 0.25
    const j0 = besselJ(0, beta), j1 = besselJ(1, beta), j2 = besselJ(2, beta), j3 = besselJ(3, beta)
    const first = 20 * Math.log10(j1 / j0)
    const total = 10 * Math.log10((2 * (j1 * j1 + j2 * j2 + j3 * j3)) / (j0 * j0))
    console.log(`    (a slow drift: ${round(clean.db, 1)} dB; a 1% wobble at 40 Hz: ${round(sidebands.db, 2)} dB in all, the loudest ${round(sidebands.loudest.db, 2)} dB at ${round(sidebands.loudest.hz, 1)} Hz - expected ${round(total, 2)} and ${round(first, 2)} dB)`)
    //? a perfect copy of a tone rich in harmonics reads clean too: every partial within STRAY_FLOOR_DB of
    //? the loudest counts as the signal - the triangle's falling as 1/n^2, its eleventh 42 dB down
    const perfect = []
    for (const [id, rateNow] of [['triangle', 44100], ['triangle', 48000], ['square', 48000], ['saw', 48000], ['chord', 48000]]) {
      const made = await signals.makeSignal(id, rateNow, { seconds: 2 })
      const read = analysis.readExactly(made.exact, Float64Array.from({ length: 96000 }, (_, i) => 0.3 + i / 48000), new Float64Array(96000).fill(1), new Float64Array(96000).fill(1), 48000, 0)
      perfect.push([id, rateNow, round(analysis.stray(read, read, 48000).db, 1)])
    }
    console.log(`    (a perfect copy against itself: ${perfect.map(([id, r, d]) => `${id} at ${r / 1000} kHz ${d} dB`).join(', ')})`)
    check('a perfect copy of the triangle (at 44.1 and 48 kHz), the square, the sawtooth and the chord against itself: clean (under -80 dB) - its harmonics are the signal, not stray',
      perfect.filter(([, , d]) => !(d < -80)), [])
    check('the same tone a few ms off, drifting: clean (under -80 dB)', clean.db < -80, true)
    check('a 1% wobble at 40 Hz: its sidebands in all within 1 dB of their level, the loudest within 1 dB of the first pair\'s',
      [Math.abs(sidebands.db - total) < 1, Math.abs(sidebands.loudest.db - first) < 1, sidebands.frames > 10], [true, true, true])
    const where = sidebands.loudest.hz
    check('...the loudest 40 Hz either side of the tone (at the drift\'s speeds, 1 to 1.02x)', (where > 952 && where < 975) || (where > 1032 && where < 1066), true)
    //? the speed's own wobble: a 1% wobble at 40 Hz reads its RMS (0.707%) through the 20 Hz high-pass
    //? taken forwards and back - |H(40)|^2 of a second-order Butterworth, 1 / (1 + (20/40)^4) - and the
    //? hand's slow drift (10% at 1.3 Hz) next to nothing
    const speedOf = (f) => Float64Array.from({ length: n }, (_, i) => f(i / rate))
    const fast = analysis.speedWobble(speedOf((t) => 1 + 0.01 * Math.sin(2 * Math.PI * 40 * t)), rate)
    const slow = analysis.speedWobble(speedOf((t) => 1 + 0.1 * Math.sin(2 * Math.PI * 1.3 * t)), rate)
    const expected = (100 * 0.01 / Math.SQRT2) / (1 + Math.pow(20 / 40, 4))
    console.log(`    (the speed's wobble: 1% at 40 Hz reads ${round(fast, 4)}% - expected ${round(expected, 4)}%; 10% at 1.3 Hz reads ${round(slow, 5)}%)`)
    check('the speed\'s wobble above 20 Hz: 1% at 40 Hz read within 5% of its level through the high-pass, the hand\'s 10% at 1.3 Hz under 0.01%',
      [Math.abs(fast / expected - 1) < 0.05, slow < 0.01], [true, true])
  }

  console.log('\nthe ABX test\'s chance of a score by guessing')
  check('10 of 10, 9, 8, 5 of 10, 0 of 10', [analysis.guessingChance(10, 10), analysis.guessingChance(9, 10), round(analysis.guessingChance(8, 10), 6), round(analysis.guessingChance(5, 10), 6), analysis.guessingChance(0, 10)],
    [1 / 1024, 11 / 1024, round(56 / 1024, 6), round(638 / 1024, 6), 1])

  console.log('\nthe bench\'s own player: said to be paused as soon as the song changes, as its element is')
  {
    //? an <audio> as a browser keeps one: play() and pause() queue their events; giving it an address runs
    //? its load, which drops whatever was queued (the 'pause' too), stops it with no 'pause', and fires
    //? 'emptied' - read in the HTML standard's load algorithm, and seen so in Chromium
    class FakeAudio {
      constructor() { this.paused = true; this.currentTime = 0; this.seeking = false; this.queued = []; this.listeners = {}; this.address = null; this.preload = '' }
      addEventListener(name, f) { (this.listeners[name] ??= new Set()).add(f) }
      removeEventListener(name, f) { this.listeners[name]?.delete(f) }
      flush() { for (const name of this.queued.splice(0)) for (const f of [...(this.listeners[name] ?? [])]) f() }
      play() { if (this.paused) { this.paused = false; this.queued.push('play') } return Promise.resolve() }
      pause() { if (!this.paused) { this.paused = true; this.queued.push('pause') } }
      load() { const had = this.address !== null || this.queued.length; this.queued = []; this.paused = true; this.currentTime = 0; if (had) this.queued.push('emptied') }
      set src(address) { this.address = address; this.load() }
      get src() { return this.address }
      removeAttribute() { this.address = null; this.load() }
    }
    const made = []
    const page = globalThis.document
    define('document', { ...page, createElement: (tag) => { const element = tag === 'audio' ? new FakeAudio() : {}; made.push(element); return element } })
    const { useBenchPlayer } = require(path.join(OUT, 'lab/benchPlayer.js'))
    const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
    const render = hooks.root(useBenchPlayer)
    const song = (n) => ({ id: `song-${n}`, title: `Song ${n}`, seconds: 120, rate: 44100, channels: 1, url: `blob:${n}` })
    let player = render(song(1)); render.commit(); player = render(song(1))
    const element = made.find((one) => one instanceof FakeAudio)
    player.toggle(); element.flush(); player = render(song(1))
    const before = [player.playing, element.paused]
    player = render(song(2)); render.commit(); player = render(song(2))
    const changed = [player.playing, element.paused, element.src]
    element.flush(); player = render(song(2))
    const settled = player.playing
    //? and any other load of it (the song's address let go of) says so too: 'emptied'
    player.toggle(); element.flush(); player = render(song(2))
    element.load(); element.flush(); player = render(song(2))
    check('playing, then another song: the player says paused at once, as the element is (whose load dropped the \'pause\'), and stays so - and an \'emptied\' alone says it too',
      [before, changed, settled, player.playing], [[true, false], [false, true, 'blob:2'], false, false])
    //? its place at a song change: the turntable's effects run before this hook's (a child's run first), so
    //? for that moment the element still holds the song before - at 45 s, no place in the new song, where
    //? the deck would ask for the new song's first window (review of 2.0.0-player.36: no check held it)
    element.currentTime = 45
    player = render(song(2))
    const onOld = player.position()
    player = render(song(3))
    const beforeLoad = player.position()
    render.commit()
    const afterLoad = [player.position(), element.src]
    element.currentTime = 7
    check('its place: the element\'s while it holds the song rendered (45 s); 0 once another song is rendered, until the element holds it - though the element still says 45 s; then the element\'s again',
      [onOld, beforeLoad, afterLoad, player.position()], [45, 0, [0, 'blob:3'], 7])
    render.unmount()
    define('document', page)
  }

  console.log('\nthe listening room\'s switch: the same whichever two clips it is between - so X is never given away by it')
  {
    //? A against C: the same tone, C a fraction of a millisecond off where deadwax's read head strays from
    //? the smooth path; against X when X is A's twin, the same tone exactly. Each switch rendered at 40
    //? moments of the tone's cycle: the level of the mix at its quietest through the switch, and the
    //? energy more than 150 Hz from the tone in the 85 ms round it (a click's) - for the room's switch, and
    //? for the crossfade it replaced (both gains moving over 5 ms together)
    const rate = 48000, hz = 1000, size = 4096
    const bh = analysis.blackmanHarris(size)
    const tone = (lag) => (t) => 0.25 * Math.sin(2 * Math.PI * hz * (t - lag))
    const crossfade = (gains, index, now) => gains.map((gain, i) => [[now, gain], [now + 0.005, i === index ? 1 : 0]])
    const render = (from, to, plan, at) => {
      const points = plan([1, 0], 1, at)
      const out = new Float64Array(size)
      for (let i = 0; i < size; i++) {
        const t = at - size / 2 / rate + i / rate
        out[i] = listen.gainAt(points[0], t) * from(t) + listen.gainAt(points[1], t) * to(t)
      }
      return out
    }
    const splatter = (data) => {
      const p = spectrum(data.map((v, i) => v * bh[i]), size)
      let near = 0, far = 0
      for (let k = 1; k < p.length; k++) (Math.abs((k * rate) / size - hz) > 150 ? (far += p[k]) : (near += p[k]))
      return 10 * Math.log10(far / near)
    }
    const quietest = (data) => {
      let low = Infinity
      for (let i = size / 2 - 48; i + 48 <= size / 2 + 48 * 12; i += 12) {
        let e = 0
        for (let k = i; k < i + 48; k++) e += data[k] * data[k]
        low = Math.min(low, Math.sqrt(e / 48) / (0.25 / Math.SQRT2))
      }
      return 20 * Math.log10(Math.max(low, 1e-9))
    }
    const worst = (plan, lag) => {
      let spill = -Infinity, dip = Infinity
      for (let m = 0; m < 40; m++) {
        const at = 1 + m / (40 * hz)
        const mix = render(tone(0), tone(lag), plan, at)
        spill = Math.max(spill, splatter(mix))
        dip = Math.min(dip, quietest(mix))
      }
      return { spill, dip }
    }
    const room = { twin: worst(listen.switchPoints, 0), pair: worst(listen.switchPoints, 0.00044) }
    const old = { twin: worst(crossfade, 0), pair: worst(crossfade, 0.00044) }
    console.log(`    (a switch to X's twin and to a clip 0.44 ms off - the room's: spill ${round(room.twin.spill, 1)} and ${round(room.pair.spill, 1)} dB; the crossfade's: dip ${round(old.twin.dip, 1)} and ${round(old.pair.dip, 1)} dB, spill ${round(old.twin.spill, 1)} and ${round(old.pair.spill, 1)} dB)`)
    check('a switch between two clips a fraction of a millisecond apart spills no more than a switch to X\'s twin (within 1 dB, at the worst of 40 moments) - and both fall silent between, never two heard at once; the crossfade it replaced dipped and spilled for the pair (10 dB more) where the twin had nothing',
      [Math.abs(room.pair.spill - room.twin.spill) < 1, room.pair.dip < -60 && room.twin.dip < -60, old.pair.spill > old.twin.spill + 10],
      [true, true, true])
    const points = listen.switchPoints([1, 0, 0], 2, 10)
    check('the switch: every clip out over SWITCH_FADE_S, the one chosen silent SWITCH_GAP_S more and then in over SWITCH_FADE_S - 5 ms, 40 ms, 5 ms',
      [listen.SWITCH_FADE_S, listen.SWITCH_GAP_S, round(listen.gainAt(points[0], 10.0025), 6), listen.gainAt(points[0], 10.005), listen.gainAt(points[2], 10.044), round(listen.gainAt(points[2], 10.0475), 6), listen.gainAt(points[2], 10.05), listen.gainAt(points[1], 10.05)],
      [0.005, 0.04, 0.5, 0, 0, 0.5, 1, 0])
  }

  console.log('\nthe listening room\'s place: never before where it started - a pause before the clips start, or on a clock not yet moving, leaves Play working')
  {
    //? an AudioContext as the standard has one: start() refuses a negative offset (a RangeError), and the
    //? clock stands still until the context runs and the test moves it
    const started = []
    let made = null
    class FakeRoomContext {
      constructor(options) { this.sampleRate = options?.sampleRate ?? 48000; this.state = 'suspended'; this.time = 0; this.destination = {}; made = this }
      get currentTime() { return this.time }
      resume() { this.state = 'running'; return Promise.resolve() }
      close() { this.state = 'closed'; return Promise.resolve() }
      createBuffer(channels, length, rate) { const data = Array.from({ length: channels }, () => new Float32Array(length)); return { duration: length / rate, getChannelData: (c) => data[c] } }
      createBufferSource() {
        return { buffer: null, loop: false, connect() {}, disconnect() {}, stop() {}, start(_at, offset) { if (!(offset >= 0)) throw new RangeError(`The offset provided (${offset}) is less than the minimum bound (0)`); started.push(offset) } }
      }
      createGain() { return { gain: { value: 1, cancelScheduledValues() {}, setValueAtTime() {}, linearRampToValueAtTime() {} }, connect() {}, disconnect() {} } }
    }
    define('AudioContext', FakeRoomContext)
    const room = new listen.ListeningRoom()
    const clip = () => new Float32Array(48000 * 10)
    room.load([clip(), clip(), clip()], 48000, 0)
    const press = () => { try { room.toggle(); return 'ok' } catch (error) { return error.constructor.name } }
    //? Play and Pause back to back, the clock not moved (a fresh context, or a quick second press): then
    //? Play again, twice
    const quick = [press(), room.playing, press(), room.playing, room.position(), press(), room.playing, press(), press(), room.playing]
    //? from the start again, playing - and a pause 10 ms after, before the clips' start 20 ms after it
    room.restart()
    made.time += 0.01
    press()
    const early = room.position()
    //? played on from there for 3 s, then the clock held (an interrupted phone's): a play and a pause don't
    //? walk the place back 20 ms a press
    press()
    made.time += 3.02
    press()
    const at3 = room.position()
    press(); press(); press(); press()
    const held = room.position()
    check('Play then Pause on a clock not yet moving, then Play again: every press works, the place never below 0 (it was -0.02, and every later Play threw); a pause before the clips start is at their start; a held clock leaves the place where it was',
      [quick, round(early, 9), round(at3, 9), round(held, 9), started.every((offset) => offset >= 0)],
      [['ok', true, 'ok', false, 0, 'ok', true, 'ok', 'ok', true], 0, 3, 3, true])
    room.close()
    define('AudioContext', undefined)
  }

  console.log('\nwhat a hidden page does to a run, and what a check that stops part way gives')
  {
    //? the hide watch: latched - hidden once, hidden, though it shows again - and told once
    const page = { visibilityState: 'visible', listeners: new Set(), addEventListener(_, f) { this.listeners.add(f) }, removeEventListener(_, f) { this.listeners.delete(f) } }
    const set = (state) => { page.visibilityState = state; for (const f of [...page.listeners]) f() }
    const { watchForHide } = require(path.join(OUT, 'lab/watch.js'))
    let told = 0
    const watch = watchForHide(() => told++, page)
    const before = watch.hidden
    set('hidden'); set('visible'); set('hidden')
    const latched = [watch.hidden, told]
    watch.stop()
    page.visibilityState = 'hidden'
    const already = watchForHide(() => told++, page).hidden
    check('a run the page was hidden through is known to be: hidden once is hidden though it shows again, told once; a watch begun hidden is hidden; stopped, it hears nothing',
      [before, latched, already, page.listeners.size], [false, [true, 1], true, 1])
    //? the check's line and its file, when it stops part way - by you, or failing a run
    const checkModule = require(path.join(OUT, 'lab/check.js'))
    const run = (n) => ({ signal: 'Sine 1 kHz', motion: `run ${n}`, voice: 'script', clockStepMs: 2.7, blocks: null, frames: null, replayHeld: true, numbers: {}, file: JSON.stringify({ recording: 'deadwax turntable', n }) })
    const state = (more) => ({ running: false, step: 'Stopped', runs: [run(1), run(2), run(3)], error: null, stoppedByYou: false, waiting: false, href: null, of: 10, ...more })
    check('the check\'s line: what it is doing; Done; stopped by you - "Stopped", never "Stopped - stopped" - with how many runs it finished and that Save results has them; a failure, with why',
      [checkModule.checkLine(state({ running: true, step: 'Sine 1 kHz: 0.5x' })), checkModule.checkLine(state({ step: 'Done' })), checkModule.checkLine(state({ stoppedByYou: true })),
        checkModule.checkLine(state({ stoppedByYou: true, runs: [] })), checkModule.checkLine(state({ error: "a run couldn't be recorded", runs: [run(1)] }))],
      ['Sine 1 kHz: 0.5x', 'Done', 'Stopped after 3 of 10 runs. Save results has the 3 runs done.', 'Stopped after 0 of 10 runs.', "Stopped - a run couldn't be recorded. Save results has the one run done."])
    const device = { deadwax: '2.0.0-player.36', when: 'now', userAgent: 'a phone', secure: false, voice: 'script', contextRate: 48000 }
    const partial = checkModule.checkFile([run(1), run(2)], device, { complete: false, why: 'stopped' })
    const whole = checkModule.checkFile([run(1)], device, { complete: true, why: null })
    check('the file of a check that stopped part way: every run it finished, each with its recording, the device - and that it is incomplete and why; a whole one says it is complete',
      [partial.complete, partial.stoppedBecause, partial.runs.length, partial.runs[1].recording.n, partial.runs[1].file, partial.userAgent, whole.complete, 'stoppedBecause' in whole, checkModule.checkRuns(2, 5)],
      [false, 'stopped', 2, 2, undefined, 'a phone', true, false, 10])
    //? a run's counts (review): blocks only for the main-thread voice - the worklet counts none (deck.ts),
    //? and a worklet's run read "0 of 0" - and each the difference, nothing where the deck's went back
    const health = (blocks, lateBlocks, frames, slowFrames, worstFrameMs) => ({ blocks, lateBlocks, worstBlockMs: 0, frames, slowFrames, worstFrameMs })
    const worklet = checkModule.runCounts('worklet', health(0, 0, 10, 0, 20), health(0, 0, 370, 2, 51))
    const script = checkModule.runCounts('script', health(100, 1, 10, 0, 51), health(380, 4, 370, 3, 40))
    const back = checkModule.runCounts('script', health(380, 4, 370, 3, 40), health(20, 0, 15, 0, 18))
    check('a run\'s counts: the worklet\'s blocks none ("None (an AudioWorklet)", never "0 of 0"); the main thread\'s the difference ("3 of 280"), "Not known" where its counts went back; the frames the difference, the longest gap only where it was the longest yet',
      [worklet.blocks, checkModule.blocksLine({ voice: 'worklet', ...worklet }), script.blocks, checkModule.blocksLine({ voice: 'script', ...script }), back.blocks, checkModule.blocksLine({ voice: 'script', ...back }),
        worklet.frames, checkModule.framesLine(worklet), script.frames, checkModule.framesLine(script), back.frames, checkModule.framesLine(back), checkModule.runCounts('script', null, health(1, 0, 1, 0, 0))],
      [null, 'None (an AudioWorklet)', { late: 3, of: 280 }, '3 of 280', null, 'Not known',
        { slow: 2, of: 360, worstMs: 51 }, '2 of 360, the longest gap 51 ms', { slow: 3, of: 360, worstMs: null }, '3 of 360', null, 'Not known', { blocks: null, frames: null }])
  }

  console.log('\nthe transport\'s line: Ready once the sound runs - after it was starting, or a hidden page had stopped it')
  {
    const line = reading.transportLine
    check('starting, then running: Ready; stopped by a hidden page: said so; then running again (Play, or the record\'s own tap, brought it back): Ready - not "stopped" still; a motion\'s own line left as it is; stopped while showing (the turntable going): nothing said',
      [line(reading.STARTING, 'none', 'running', false), line(reading.READY, 'running', 'none', true), line(reading.SOUND_STOPPED, 'none', 'running', false),
        line('Turning it: Steady 1x', 'none', 'running', false), line(reading.READY, 'running', 'none', false), line(reading.SOUND_STOPPED, 'running', 'running', false)],
      [reading.READY, reading.SOUND_STOPPED, reading.READY, 'Turning it: Steady 1x', reading.READY, reading.SOUND_STOPPED])
    //? (2.0.0-player.37) a song from the library takes the bench's own song's place on a turntable of its own,
    //? its deck made afresh: the line says a tap starts the sound again, and Ready once one has
    check('...and after the kind of song changed (a library song\'s turntable, or the bench\'s own again): Ready once the sound runs again',
      [line(reading.SOUND_AGAIN, null, 'running', false), line(reading.SOUND_AGAIN, 'none', 'running', false), line(reading.SOUND_AGAIN, 'running', null, false)],
      [reading.READY, reading.READY, reading.SOUND_AGAIN])
  }

  console.log('\nthe motions\' samples: 60 a second on the page\'s clock, along the path')
  {
    const steady = motions.MOTIONS.find((m) => m.id === 'steady1')
    const samples = motions.motionSamples(steady, 5000)
    const spacing = samples.slice(1).map((s, i) => s.time - samples[i].time)
    check('steady 1x: 361 samples, every 1000/60 ms from the take, along the path, turned 2π per 1.8 s of the song',
      [samples.length, spacing.every((d) => Math.abs(d - 1000 / 60) < 1e-9), round(samples[60].moved, 12), round(samples[90].turned, 9)],
      [361, true, 1, round((1.5 / tt.SECONDS_PER_TURN) * 2 * Math.PI, 9)])
    const speeds = []
    for (const motion of motions.MOTIONS) {
      let worst = 0
      for (let t = 0.01; t < motion.seconds - 0.01; t += 0.05) worst = Math.max(worst, Math.abs((motion.path(t + 1e-5) - motion.path(t - 1e-5)) / 2e-5 - motion.speed(t)))
      speeds.push([motion.id, worst < 1e-5])
    }
    check('every motion\'s speed is its path\'s rate of change', speeds.filter(([, ok]) => !ok), [])
    const ramp = motions.MOTIONS.find((m) => m.id === 'ramp')
    const scratch = motions.MOTIONS.find((m) => m.id === 'scratch')
    const wobble = motions.MOTIONS.find((m) => m.id === 'wobble')
    check('the ramp: 0.25x, 2x at 4 s, 0.25x at 8 s; the scratch back where it began each half second, at 1.5x most; the wobble 1x give or take 10%',
      [round(ramp.speed(0), 6), round(ramp.speed(4), 6), round(ramp.speed(8), 6), round(scratch.path(0.5), 9), round(scratch.speed(0.125), 6), round(wobble.speed(1 / (4 * 1.3)), 6)],
      [0.25, 2, 0.25, 0, 1.5, 1.1])
    //? where a motion takes the record: where it is, if the motion fits from there with room before
    //? and after; else 20 s in, or as near as fits; never past a short song's end
    const by = (id) => motions.MOTIONS.find((m) => m.id === id)
    const reach = (id) => { const r = motions.motionReach(by(id)); return [round(r.back, 3), round(r.ahead, 3)] }
    check('how far each goes: steady 1x 6 s on, backwards 1x 6 s back, 2x 12 s on, the scratch a quarter of a second on and back',
      [reach('steady1'), reach('back1'), reach('double'), reach('scratch')], [[0, 6], [6, 0], [0, 12], [0, round(1.5 / (2 * Math.PI), 3)]])
    check('where it starts: where the record is if it fits (30 s), 20 s in if not (119 s, 3 s backwards), as near as fits on a short song (13 s: 3 s; backwards on 12 s: 8 s) - and on a song too short for it (8 s for steady 1x, 17 s for 2x) none, with what it needs said',
      [motions.motionStart(steady, 120, 30), motions.motionStart(steady, 120, 119), motions.motionStart(by('back1'), 120, 3), motions.motionStart(steady, 13, 0),
        motions.motionStart(by('back1'), 12, 0), motions.motionStart(steady, 8, 0), motions.motionStart(by('double'), 17, 0), motions.motionNeeds(steady), motions.motionNeeds(by('double'))],
      [30, 20, 20, 3, 8, null, null, 12, 18])
    const jittered = motions.motionSamples(steady, 0, signals.seeded(11))
    const off = jittered.slice(1).map((s) => s.moved - steady.path(s.time / 1000))
    const sd = Math.sqrt(off.reduce((s, e) => s + e * e, 0) / off.length)
    //? decksound's finger, as stated: 1.5 ms of time (at 1x, 1.5 ms of the song) and 1 ms of place
    const expected = Math.hypot(0.001, 0.0015)
    check('with a finger\'s jitter: the take exact, the rest off by about 1.8 ms (1 ms and 1.5 ms at 1x, within 20%), and the same for the same seed',
      [jittered[0].moved, Math.abs(sd / expected - 1) < 0.2, JSON.stringify(jittered) === JSON.stringify(motions.motionSamples(steady, 0, signals.seeded(11)))], [0, true, true])
  }

  console.log('\nthe runner reads the player as it is at the release - a new object each time it starts or stops, as the bench\'s is')
  {
    //? useBenchPlayer's answer is made again whenever `playing` changes, so the one of the motion's start
    //? goes on saying what was so then. Handed that one, the runner took a playing song paused by the take
    //? (the hand's own pause) for playing still at a 1x release - and never played it again: the song
    //? silent, the platter turning on (review of 2.0.0-player.36)
    const steady = motions.MOTIONS.find((m) => m.id === 'steady1')
    const saved = timers
    timers = []
    const drive = async ({ pauses, play }) => {
      const log = []
      let current
      const make = (playing) => ({
        playing, duration: 120,
        seek: (t) => log.push(['seek', t]),
        toggle: () => { log.push(['toggle', current.playing]); current = make(!current.playing) },
      })
      current = make(true)
      const first = current
      const deck = {
        pressed() {}, hand() {},
        takeOver() { if (pauses && current.playing) current.toggle(); return 20 },
        release() { log.push(['release']); return { seek: 26, play } },
      }
      const run = runMotion(deck, () => current, steady)
      let result = null
      run.done.then((r) => { result = r })
      while (!result && timers.length) {
        const timer = timers.reduce((a, b) => (b.at < a.at ? b : a))
        timers = timers.filter((t) => t !== timer)
        real = Math.max(real, timer.at)
        timer.run()
        await settle()
      }
      return [log.slice(log.findIndex(([what]) => what === 'release')), current.playing, current === first]
    }
    check('a playing song the take paused, let go where the deck says play at once: played (the player asked as it is then, a new object); let go into a coast: sought, left paused; never paused by the take and let go to play: sought, not toggled',
      [await drive({ pauses: true, play: true }), await drive({ pauses: true, play: false }), await drive({ pauses: false, play: true })],
      [[[['release'], ['seek', 26], ['toggle', false]], true, false], [[['release'], ['seek', 26]], false, false], [[['release'], ['seek', 26]], true, true]])
    timers = saved
  }

  /* ===== the real deck, in a page whose audio steps as a browser's does ===== */

  /**
   * One run of the REAL Turntable and deck on the bench's song, its windows from the bench's source: the
   * worklet in bursts of `step`, or the main-thread voice a block of 1024 a block ahead - its stamps exact,
   * or (`drift`) moving 1023 frames a block, as headless Chromium's do (the voice follows a stamp within a
   * millisecond of its count, so it renders each block at the stamp's time while the audio plays on whole);
   * the song `playing` or paused; a motion run by lab/runner.ts and recorded with the deck's own recorder,
   * kept for the page. `probe` is handed the deck and the harness first, for the checks of its parts.
   */
  async function deckRun({ host, playing = false, drift = false, jitter = true, probe = null, library = null }) {
    const rate = 48000
    const song = await signals.makeSignal('sine1k', rate, { seconds: 40 })
    const step = host === 'worklet' ? 256 : 1024
    const world = { host, rate, rendered: 0, inbox: [], calls: [], node: null, script: null, taps: [], gains: [], output: new Float32Array(rate * 60), state: voice.newVoiceState(), audio0: real, connections: [], fetches: 0, served: [] }
    //? deadwax: none for a song the bench made - its windows are the bench's own - and, for a song from the
    //? library (2.0.0-player.37), its scrub route faked at fetch: the song's samples [first, first + samples)
    //? from where it is asked, as a WAV the fake context decodes, a 416 past the end
    define('fetch', async (address) => {
      world.fetches++
      if (!library) throw new Error('no deadwax here')
      world.served.push(address)
      const query = new URL(address, 'http://deadwax.test').searchParams
      try {
        const w = signals.signalWindow(song, Number(query.get('at')), Number(query.get('seconds')))
        return { ok: true, status: 200, headers: { get: (name) => (name.toLowerCase() === 'x-deadwax-window' ? `${w.first}/${w.samples}/${w.rate}` : null) }, arrayBuffer: async () => w.bytes }
      } catch {
        return { ok: false, status: 416, headers: { get: () => null }, json: async () => ({ detail: 'that is past the end of the song' }) }
      }
    })
    class FakeNode {
      constructor() { this.port = { postMessage: (message) => world.inbox.push(message), onmessage: null }; world.node = this }
      connect(to) { world.connections.push(['voice', to]) }
      disconnect(to) { if (to?.kind === 'analyser') world.connections.push(['voice', 'off the analyser']) }
    }
    define('AudioWorkletNode', host === 'worklet' ? FakeNode : undefined)
    class FakeContext {
      constructor() { this.state = 'suspended'; this.sampleRate = rate; this.destination = { speakers: true }; this.listeners = []; if (host === 'worklet') this.audioWorklet = { addModule: () => Promise.resolve() } }
      get currentTime() { return world.rendered / rate }
      addEventListener(name, listener) { if (name === 'statechange') this.listeners.push(listener) }
      resume() { this.state = 'running'; for (const l of this.listeners) l(); return Promise.resolve() }
      suspend() { this.state = 'suspended'; for (const l of this.listeners) l(); return Promise.resolve() }
      close() { this.state = 'closed'; return Promise.resolve() }
      createScriptProcessor(size, inputs, outputs) {
        const node = { size, inputs, outputs, onaudioprocess: null, connect(to) { world.connections.push([inputs ? 'tap' : 'script', to]) }, disconnect(to) { if (to?.kind === 'analyser') world.connections.push([inputs ? 'tap' : 'script', 'off the analyser']) } }
        if (inputs) world.taps.push(node)
        else world.script = node
        return node
      }
      createAnalyser() { return { kind: 'analyser', context: this, fftSize: 0, connect(to) { world.connections.push(['analyser', to]) }, disconnect() { world.connections.push(['analyser', 'off']) } } }
      createGain() { const node = { kind: 'gain', gain: { value: 1 }, connect(to) { world.connections.push(['gain', to]) }, disconnect() {} }; world.gains.push(node); return node }
      decodeAudioData(bytes, done) {
        const wav = signals.readWav(bytes)
        done({ numberOfChannels: wav.channels.length, sampleRate: wav.rate, length: wav.channels[0].length, getChannelData: (c) => wav.channels[c] })
      }
    }
    define('AudioContext', FakeContext)

    //? what plays is kept at the frame it plays at, contiguous - and the recorder's tap handed it 4096
    //? frames at a time as they pass
    const tapped = (upTo) => {
      for (const tap of world.taps) {
        tap.done ??= 0
        while (tap.onaudioprocess && tap.done + 4096 <= upTo - 1024) {
          const input = [world.output.slice(tap.done, tap.done + 4096), world.output.slice(tap.done, tap.done + 4096)]
          tap.onaudioprocess({ inputBuffer: { numberOfChannels: 2, getChannelData: (c) => input[c] }, playbackTime: (tap.done + 8192) / rate })
          tap.done += 4096
        }
        if (!tap.onaudioprocess) tap.done = Math.max(tap.done, Math.floor(upTo / 4096) * 4096)
      }
    }
    const burst = () => {
      if (host === 'worklet') {
        for (const message of world.inbox.splice(0)) voice.voiceCommand(world.state, message, world.rendered / rate, rate)
        for (let q = 0; q < step; q += 128) {
          const out = [new Float32Array(128), new Float32Array(128)]
          voice.renderVoice(world.state, out, 128, rate, world.rendered / rate)
          world.output.set(out[0], world.rendered)
          const heard = voice.voiceReport(world.state, 128, rate, world.rendered / rate, voice.REPORTS_PER_SECOND)
          if (heard) world.node?.port.onmessage?.({ data: heard })
          world.rendered += 128
        }
      } else {
        const before = world.rendered
        world.rendered += step
        for (let boundary = Math.ceil(before / 1024) * 1024; boundary < world.rendered; boundary += 1024) {
          //? the stamp: the frame it plays at - or, drifting, 1023 frames a block from the first
          const frame = boundary + 1024
          world.calls.push({ at: real + 0.7, frame, playbackTime: (drift ? frame * (1023 / 1024) : frame) / rate })
        }
      }
      tapped(world.rendered)
    }
    const scriptCall = ({ frame, playbackTime }) => {
      if (!world.script?.onaudioprocess) return
      const channels = [new Float32Array(1024), new Float32Array(1024)]
      world.script.onaudioprocess({ outputBuffer: { numberOfChannels: 2, length: 1024, getChannelData: (c) => channels[c] }, playbackTime })
      world.output.set(channels[0], frame)
    }
    let nextFrame = real + 3
    const runUntil = async (until) => {
      while (real < until) {
        const nextBurst = world.audio0 + ((world.rendered + step) / rate) * 1000
        const due = Math.min(nextBurst, nextFrame, ...world.calls.map((c) => c.at), ...timers.map((t) => t.at), until)
        real = Math.max(real, due)
        if (due === nextBurst) { burst(); continue }
        const call = world.calls.find((c) => c.at <= real)
        if (call) { world.calls.splice(world.calls.indexOf(call), 1); scriptCall(call); continue }
        const timer = timers.find((t) => t.at <= real)
        if (timer) { timers = timers.filter((t) => t !== timer); timer.run(); continue }
        if (due === nextFrame) {
          const now = frames
          frames = []
          for (const frame of now) frame.run(real)
          nextFrame += 1000 / 60
          await settle()
        }
      }
      await settle()
    }

    //? the turntable on a song the bench made: its own windows, its own player
    const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
    const render = hooks.root(Turntable)
    const name = library ? library.track.id : `lab-sine1k-${host}${playing ? '-playing' : ''}${drift ? '-drift' : ''}${jitter ? '' : '-still'}`
    const player = {
      track: library ? library.track : { id: name, title: 'Sine 1 kHz', artist: 'Test bench', album: '', albumId: null, coverArt: null, duration: 40, contentType: 'audio/wav', suffix: 'wav', sampleRate: rate, bitDepth: 24, channels: 1 },
      playing, duration: 40, maxRate: library ? library.maxRate : 'original', at: 12, listeners: new Set(),
      log: [],
      seek(t) { this.log.push(['seek', real, t]); this.at = t; for (const l of this.listeners) l(t) },
      toggle() { this.log.push(['toggle', real, this.playing]); this.playing = !this.playing },
      position() { return this.at }, onPosition(listener) { this.listeners.add(listener); return () => this.listeners.delete(listener) },
    }
    for (const fn of ['seek', 'toggle', 'position', 'onPosition']) player[fn] = player[fn].bind(player)
    const asked = []
    const windowSource = (songNow, from, seconds) => { asked.push([songNow.id, from, seconds]); return Promise.resolve(signals.signalWindow(song, from, seconds)) }
    const deckRef = { current: null }
    const draw = () => {
      //? a song from the library: no window source at all, as the bench's library turntable draws it
      const tree = render(library ? { player, open: true, discArt: null, onPreview: () => {}, deck: deckRef } : { player, open: true, discArt: null, onPreview: () => {}, deck: deckRef, windowSource })
      const walk = (node) => { if (!node || typeof node !== 'object') return; if (Array.isArray(node)) return node.forEach(walk); if (node.props?.ref) node.props.ref.current = { style: {}, getBoundingClientRect: () => ({ left: 0, top: 0, width: 372, height: 368 }) }; walk(node.props?.children) }
      walk(tree)
      render.commit()
    }
    draw()
    deckModule.wakeDeckAudio()
    await runUntil(real + 500)
    draw()
    const deck = deckRef.current
    if (probe) await probe({ deck, world, song, asked, rate, name })
    //? what the deck's release answered, and what the player was asked straight after, in the same moment
    const release = deck.release.bind(deck)
    deck.release = (...args) => {
      const answer = release(...args)
      player.log.push(['release', real, answer, player.playing])
      return answer
    }

    const windowAtStart = deckModule.deckReport().window
    const started = deckModule.recordDeckSound(12, true)
    const motion = { id: 'test', label: 'test', seconds: 2.5, path: (t) => t + (0.1 / (2 * Math.PI * 1.3)) * (1 - Math.cos(2 * Math.PI * 1.3 * t)), speed: (t) => 1 + 0.1 * Math.sin(2 * Math.PI * 1.3 * t) }
    const run = runMotion(deck, () => player, motion, { random: jitter ? signals.seeded(5) : null })
    let result = null
    run.done.then((r) => { result = r })
    await runUntil(real + 2600)
    const taken = deck.taken()
    //? a playing song's handover - the motor back to speed, then the record's sound faded - takes longer
    await runUntil(real + (playing ? 4200 : 1500))
    deckModule.stopDeckRecording()
    const data = deckModule.deckRecordingData()
    const decoded = (start, rateNow, length) => {
      const wav = signals.readWav(signals.signalWindow(song, start, 40).bytes)
      return wav.channels[0].length === length && rateNow === wav.rate ? wav.channels : null
    }
    const startWindow = windowAtStart ? { channels: decoded(windowAtStart.start, windowAtStart.decodedAt, Math.round((windowAtStart.end - windowAtStart.start) * windowAtStart.decodedAt)), start: windowAtStart.start, rate: windowAtStart.decodedAt } : null
    const exactMotion = data && result ? analysis.exactKnots(data.messages, result.samples, result.from, result.anchor, 40, motion.path, motion.speed) : null
    const compareWith = (exact, pictures, recording = data, exactOver = null) => compare({
      recording, exact, exactOver, measure: 'tonal', windowAtStart: startWindow, windowFor: decoded, motion: exactMotion,
      span: { from: exactMotion.knots[0].time, to: exactMotion.knots.at(-1).time }, pictures,
    })
    const compared = data && exactMotion ? await compareWith(song.exact, true) : null
    render.unmount()
    await runUntil(real + 200)
    const at = player.log.findIndex(([what]) => what === 'release')
    const released = at < 0 ? null : player.log[at]
    const after = at < 0 ? [] : player.log.slice(at + 1).filter(([, when]) => when === released[1])
    return { started, result, taken, data, exactMotion, compared, rate, compareWith, exact: song.exact, released, after, song, world }
  }

  console.log('\nthe deck\'s window source, the in-page recording, the live spectrogram\'s analyser - and a replay of what the real deck played')
  for (const host of ['worklet', 'script']) {
    const run = await deckRun({
      host,
      probe: async ({ deck, world, song, asked, rate, name }) => {
        const report = deckModule.deckReport()
        const window0 = signals.signalWindow(song, asked[0][1], 40)
        check(`${host}: with a window source the deck asks deadwax nothing and decodes the source's window - "WAV", where the source said`,
          [world.fetches, asked.length >= 1, asked[0]?.[0], report?.window?.kind, deck.live(), report?.window?.start === window0.first / rate, report?.window?.end === (window0.first + window0.samples) / rate],
          [0, true, name, 'WAV', true, true, true])
        if (host === 'worklet') check('...the voice\'s window the song\'s own samples', world.state.window.channels[0][100] === signals.readWav(window0.bytes).channels[0][100], true)
        //? the analyser for the live spectrogram: off the voice's node, on to the speakers through a gain of 0
        world.connections.length = 0
        const analyser = deckModule.deckSoundAnalyser()
        check(`${host}: the live spectrogram's analyser hangs off the voice's node, on to the speakers through a gain of 0 - and is the same while the node is`,
          [world.connections.map(([from, to]) => [from, to?.kind ?? (to?.speakers ? 'speakers' : 'node')]), analyser?.kind, world.gains.at(-1)?.gain.value, deckModule.deckSoundAnalyser() === analyser],
          [[[host === 'worklet' ? 'voice' : 'script', 'analyser'], ['analyser', 'gain'], ['gain', 'speakers']], 'analyser', 0, true])
        deckModule.releaseDeckSoundAnalyser()
        check(`${host}: ...and let go of: the voice's node off it, it off the speakers`,
          [world.connections.some(([from, to]) => from === (host === 'worklet' ? 'voice' : 'script') && to === 'off the analyser'), world.connections.some(([from, to]) => from === 'analyser' && to === 'off')], [true, true])
        //? a recording not asked to be kept leaves nothing for the page
        const before = deckModule.deckRecordingData()
        check(`${host}: Debug's recording (not kept) - started, then stopped early`, [deckModule.recordDeckSound(2), (deckModule.stopDeckRecording(), deckModule.deckRecorded()?.state), deckModule.deckRecordingData() === before], [null, 'saved', true])
      },
    })
    const { data, result, compared } = run
    check(`${host}: a kept recording starts; the motion took the record through the deck, and let go of it after its last sample`, [run.started, !!result, result?.stopped, run.taken], [null, true, false, false])
    check(`${host}: kept - the deck's own messages and reports, the file version 2 and the same audio`,
      [!!data, data.voice, data.messages.some((m) => m.type === 'take'), data.messages.filter((m) => m.type === 'hand').length >= 140, data.heard.length > 50, JSON.parse(data.file).version, JSON.parse(data.file).audio.frames === data.channels[0].length],
      [true, host, true, true, true, 2, true])
    check(`${host}: the motion's exact knots pair one to one with the deck's own hand samples`, [!!run.exactMotion, run.exactMotion?.knots.length], [true, result.samples.length])
    const nums = compared.numbers
    console.log(`    (${host}: replay ${round(nums.replayDb, 1)} dB under what was recorded, lined up at ${round(nums.alignScore, 6)}, lead ${round(nums.leadMs, 2)} ms, fit ${nums.fitMs === null ? 'none' : round(nums.fitMs, 6)} ms; strayed ${JSON.stringify(nums.strayed && { max: round(nums.strayed.maxMs, 3), typical: round(nums.strayed.typicalMs, 3) })} ms; wobble ${JSON.stringify(nums.wobble)}; A against B ${round(nums.stray?.db ?? NaN, 1)} dB, loudest ${JSON.stringify(nums.stray?.loudest)})`)
    check(`${host}: the offline replay reproduces what the voice played - more than 100 dB under it, lined up (correlation over 0.999), its timing fitting the voice's own reports to under a microsecond of the song`,
      [nums.replayDb < -100, nums.alignScore > 0.999, nums.fitMs !== null && nums.fitMs < 0.001], [true, true, true])
    check(`${host}: A, B and C as long as each other, level-matched, and their spectrograms on one scale`,
      [compared.clips.A.length === compared.clips.B.length && compared.clips.B.length === compared.clips.C.length, compared.clips.A.length > run.rate * 2,
        Math.abs(20 * Math.log10(analysis.rmsWhere(compared.clips.B, () => true) / analysis.rmsWhere(compared.clips.A, () => true))) < 0.5, compared.images.A.width === compared.images.C.width],
      [true, true, true, true])
    check(`${host}: the read head followed the motion's exact path (within 3 ms at most), deadwax's path wobbling less than 1% above 20 Hz, the exact path's next to nothing (under 0.05%: its knots at the times the deck stamped them)`,
      [nums.strayed.maxMs < 3, nums.wobble.deadwax < 1, nums.wobble.smooth < 0.05], [true, true, true])
    check(`${host}: a 1 kHz tone read by the voice: what isn't the signal well under it (A against B under -75 dB)`, nums.stray.db < -75, true)
    //? the release did what Turntable's own does with the deck's answer: sought there at once, and played
    //? in the same moment only when the deck said to and the song wasn't playing (runner.ts)
    const [, , answer, wasPlaying] = run.released
    check(`${host}: the motion's release sought the song where the deck said, in the same moment - and played it only if the deck said so (here ${answer.play})`,
      [answer.seek !== null, JSON.stringify(run.after[0]?.slice(0, 1).concat(run.after[0]?.[2])), run.after.some(([what]) => what === 'toggle'), run.after.length],
      [true, JSON.stringify(['seek', answer.seek]), answer.play && !wasPlaying, answer.play && !wasPlaying ? 2 : 1])
    //? C, the ideal on the smooth path, is as clean as A: its speed wobbling no more than deadwax's, and no
    //? click - its sharpest turn (largest second difference) no sharper than A's, where a step at the
    //? let-go made it 80 times A's
    const sharpest = (clip) => { let most = 0; for (let i = 1; i + 1 < clip.length; i++) most = Math.max(most, Math.abs(clip[i + 1] - 2 * clip[i] + clip[i - 1])); return most }
    console.log(`    (${host}: the sharpest turn - A ${round(sharpest(compared.clips.A), 5)}, B ${round(sharpest(compared.clips.B), 5)}, C ${round(sharpest(compared.clips.C), 5)})`)
    check(`${host}: C as clean as A - its speed's wobble no more than deadwax's, its sharpest turn no sharper than A's (a step in its path would be a click)`,
      [nums.wobble.smooth <= nums.wobble.deadwax, sharpest(compared.clips.C) <= 1.05 * sharpest(compared.clips.A)], [true, true])
    if (host === 'worklet') {
      //? an ideal turntable read 6 dB quieter than the voice played (the song's level as defined, against
      //? what reached the tap): B and C brought to A's level all the same, where the voice sounded
      const quieter = await run.compareWith((t, cutoff) => 0.5 * run.exact(t, cutoff), false)
      const level = (clip) => 20 * Math.log10(analysis.rmsWhere(clip, () => true) / analysis.rmsWhere(quieter.clips.A, () => true))
      check(`${host}: B and C level-matched to A however loud the definition reads them (within 0.5 dB, read 6 dB quiet)`, [Math.abs(level(quieter.clips.B)) < 0.5, Math.abs(level(quieter.clips.C)) < 0.5], [true, true])
    }
  }

  console.log('\nwith no finger\'s jitter, C (the smooth path) and B (deadwax\'s) are the same tone - C no dirtier than deadwax\'s own path')
  for (const host of ['worklet', 'script']) {
    const still = await deckRun({ host, jitter: false })
    const n = still.compared.numbers
    const span = still.compared.measured
    const cb = analysis.stray(still.compared.clips.C, still.compared.clips.B, still.rate, span.from, span.to)
    console.log(`    (${host}, no jitter: C against B ${round(cb.db, 1)} dB, loudest ${JSON.stringify(cb.loudest && { hz: round(cb.loudest.hz, 1), db: round(cb.loudest.db, 1) })}; A against B ${round(n.stray.db, 1)} dB; wobble ${JSON.stringify(n.wobble)})`)
    check(`${host}: a motion with no jitter - what C has that B hasn't, over the stretch measured, under -75 dB (it read -47 to -50 dB on knots placed on the raw stamps), its speed's wobble no more than deadwax's`,
      [cb.db < -75, n.wobble.smooth <= n.wobble.deadwax], [true, true])
  }

  console.log('\nthe replay\'s timing: a main-thread voice whose stamps move 1023 frames a block, and messages told off the lead')
  {
    //? headless Chromium's main-thread voice: its stamps move a frame short a block, and the voice renders
    //? each block at its stamp - the replay numbers its blocks by its reports and times the rest along them
    const drifting = await deckRun({ host: 'script', drift: true })
    const n = drifting.compared.numbers
    console.log(`    (drifting stamps: replay ${round(n.replayDb, 1)} dB, fit ${n.fitMs === null ? 'none' : round(n.fitMs, 6)} ms, lined up at ${round(n.alignScore, 6)})`)
    check('the main-thread voice\'s stamps drifting a frame a block: the replay still reproduces it (more than 100 dB under, its read head within a microsecond of the song)',
      [n.replayDb < -100, n.fitMs !== null && n.fitMs < 0.001], [true, true])
    //? a playing song taken and let go, each moved off the lead the rest were told at - the take two of
    //? the worklet's 128-frame blocks early, the stop two late, neither past a neighbour (the take goes
    //? out with the hand's first sample, the stop is the last thing said), so no one lead fits both. The
    //? stop is put back at the block the reports say. A take places the read head where the record is AS
    //? OF the moment it is applied (voiceCommand's own catch-up), so the block it is told at moves nothing
    //? the reports see - it is left where it was, the read head within a microsecond all the same
    const played = await deckRun({ host: 'worklet', playing: true })
    const data = played.data
    {
      const [, , answer, wasPlaying] = played.released
      check(`a playing song taken and let go: the release sought it where the deck said, and played it at once only if the deck said so (here ${answer.play}, the hand having paused it: ${!wasPlaying})`,
        [JSON.stringify(played.after[0]?.slice(0, 1).concat(played.after[0]?.[2])), played.after.some(([what]) => what === 'toggle'), !wasPlaying],
        [JSON.stringify(['seek', answer.seek]), answer.play, true])
    }
    const timedTypes = data.messages.filter((m) => m.type === 'take' || m.type === 'fade' || m.type === 'stop').map((m) => m.type)
    const source = (messages) => ({ voice: data.voice, sampleRate: data.sampleRate, messages, heard: data.heard, offset: data.clock.offset, scriptLagSeconds: data.scriptLagSeconds })
    const from = data.blockTimes[0] - 0.4, to = data.blockTimes.at(-1) + 0.25
    const original = analysis.planTiming(source(data.messages), from, to)
    const blocks = (2 * 128 * 1000) / data.sampleRate
    const moved = data.messages.map((m) => (m.type === 'take' ? { ...m, t: m.t - blocks } : m.type === 'stop' ? { ...m, t: m.t + blocks } : m))
    const inOrder = moved.every((m, i) => i === 0 || m.t >= moved[i - 1].t)
    const refit = analysis.planTiming(source(moved), from, to)
    const index = (type) => data.messages.map((m, i) => [m, i]).filter(([m]) => m.type === type).map(([, i]) => i)
    console.log(`    (told as it was: worst ${round(original.worst * 1000, 6)} ms; the take and stop moved: worst ${round(refit.worst * 1000, 6)} ms)`)
    check(`a playing song taken and let go (${timedTypes.join(', ')}): the stop told two blocks late put back at the block the voice's reports say, the take two blocks early left - its read head the same either way - and the read head within a microsecond, as told as it was`,
      [timedTypes.includes('take') && timedTypes.includes('stop') && inOrder, original.worst < 1e-6, refit.worst < 1e-6,
        index('stop').every((i) => refit.told[i] === original.told[i]), index('take').every((i) => Math.abs(refit.told[i] - original.told[i]) <= 2)],
      [true, true, true, true, true])

    //? a page held up while a hand turned it: the hand's samples handed to the voice late, all at once -
    //? which the voice played on time (this recording) but a replay told them when the page says can't
    //? follow. The replay is said not to hold, and the run to want recording again
    const hands = data.messages.filter((m) => m.type === 'hand')
    const t0 = hands[0].t
    const stalled = { ...data, messages: data.messages.map((m) => (m.type === 'hand' && m.t > t0 + 400 && m.t < t0 + 700 ? { ...m, t: t0 + 700 } : m)) }
    const kept = await played.compareWith(played.exact, false, data)
    const held = await played.compareWith(played.exact, false, stalled)
    console.log(`    (the replay's worst miss: as recorded ${round(kept.numbers.fitMs, 6)} ms, the hand's samples told 300 ms late ${round(held.numbers.fitMs, 3)} ms)`)
    check('a replay that can\'t follow - the hand\'s samples told 300 ms late, as a page held up hands them over - is said not to hold; as recorded, it holds; the rule is half a millisecond',
      [compareModule.replayHeld(kept.numbers), compareModule.replayHeld(held.numbers), compareModule.REPLAY_HELD_MS,
        compareModule.replayHeld({ fitMs: 0.5 }), compareModule.replayHeld({ fitMs: 0.51 }), compareModule.replayHeld({ fitMs: null })],
      [true, false, 0.5, true, false, false])

    //? a recording nothing took (review): Record pressed and the record not turned, or a turn already
    //? under way when it began - no take among its messages, so no report the replay could be held to.
    //? Not a stall of the page: said so, in place of the numbers - and a take with nothing reported after
    //? it said apart from both
    const untaken = await played.compareWith(played.exact, false, { ...data, messages: [] })
    const underWay = await played.compareWith(played.exact, false, { ...data, messages: data.messages.filter((m) => m.type !== 'take') })
    const rows = (numbers) => reading.numberRows(numbers).map((row) => [row.label, row.value === reading.NOT_TAKEN ? 'NOT_TAKEN' : row.value === reading.NOT_HELD ? 'NOT_HELD' : row.value === reading.NOT_REPORTED ? 'NOT_REPORTED' : 'numbers'])
    check('a recording nothing took - no messages, or a turn already under way - reads "Nothing took the record", never a stall; a stalled replay reads the stall; a held one its numbers; a take with nothing reported after it, its own line',
      [[untaken.numbers.taken, untaken.numbers.fitMs, compareModule.replayVerdict(untaken.numbers), rows(untaken.numbers)[0], reading.meaning(untaken.numbers) === reading.NOT_TAKEN],
        [underWay.numbers.taken, compareModule.replayVerdict(underWay.numbers), rows(underWay.numbers)[0]],
        [held.numbers.taken, compareModule.replayVerdict(held.numbers), rows(held.numbers)[0], reading.meaning(held.numbers) === reading.NOT_HELD],
        [kept.numbers.taken, compareModule.replayVerdict(kept.numbers), rows(kept.numbers)[0][1], reading.againLine(kept.numbers)],
        [compareModule.replayVerdict({ fitMs: null, taken: true }), reading.againLine({ fitMs: null, taken: true }) === reading.NOT_REPORTED],
        [compareModule.tookTheRecord([]), compareModule.tookTheRecord([{ type: 'hand' }, { type: 'take' }])]],
      [[false, null, 'untaken', ['Record it again', 'NOT_TAKEN'], true],
        [false, 'untaken', ['Record it again', 'NOT_TAKEN']],
        [true, 'stalled', ['Record it again', 'NOT_HELD'], true],
        [true, 'held', 'numbers', null],
        ['unreported', true],
        [false, true]])
  }


  /* ===== a song from your library (2.0.0-player.37) ===== */

  const library = require(path.join(OUT, 'lab/library.js'))
  const api = require(path.join(OUT, 'player/api.js'))
  const { ApiError } = require(path.join(OUT, 'api/http.js'))
  const wrap = require(path.join(OUT, 'lib/streamWrap.js'))

  console.log('\na song from your library: found by Navidrome\'s search, paced, only the newest answer said')
  {
    //? a search whose answers come back when told, and timers the run moves on
    const asked = []
    const answers = []
    const pending = []
    let clock = 0
    let waiting = []
    const search = library.librarySearch({
      search: (query, signal) => new Promise((resolve, reject) => {
        asked.push(query)
        pending.push({ query, resolve, reject, signal })
      }),
      onAnswer: (answer) => answers.push(answer.state === 'found' ? `${answer.query}: ${answer.songs.map((one) => one.title).join(', ')}` : `${answer.query}: ${answer.state}`),
      setTimer: (run, ms) => { const timer = { at: clock + ms, run }; waiting.push(timer); return timer },
      clearTimer: (timer) => { waiting = waiting.filter((one) => one !== timer) },
    })
    const pass = (ms) => {
      clock += ms
      for (const timer of waiting.filter((one) => one.at <= clock)) { waiting = waiting.filter((one) => one !== timer); timer.run() }
    }
    const answer = (query, titles) => pending.find((one) => one.query === query).resolve({ artists: [], albums: [], songs: titles.map((title) => ({ id: title, title })) })
    //? typed a letter at a time, faster than it settles: asked once, LIBRARY_SETTLE_MS after the last
    search.type('e'); pass(100); search.type('ey'); pass(100); search.type('eye'); pass(199)
    const beforeSettled = asked.length
    pass(1)
    const once = [...asked]
    //? then more, asked while the first answer is still out - and the NEWER answer comes back first
    search.type('eye in the sky'); pass(200)
    answer('eye in the sky', ['Eye in the Sky'])
    await settle()
    const newer = answers.at(-1)
    //? the older answer, slow, lands after it: dropped - and its fetch was called off
    answer('eye', ['Eye in the Sky', 'Eye of the Tiger'])
    await settle()
    const after = answers.at(-1)
    const calledOff = pending.find((one) => one.query === 'eye').signal?.aborted
    //? Enter asks at once; an empty box asks nothing, and nothing still out lands
    search.now('sky')
    search.type('')
    answer('sky', ['Sky'])
    await settle()
    check('the search: asked once typing has stopped for LIBRARY_SETTLE_MS (200 ms) - not for every letter; a slow older answer never lands over a newer one (and its fetch is called off); Enter asks at once; an empty box asks nothing and lets go of what was out',
      [library.librarySearch.length, beforeSettled, once, newer, after, calledOff, asked.at(-1), answers.at(-1), answers.includes('sky: Sky')],
      [1, 0, ['eye'], 'eye in the sky: Eye in the Sky', 'eye in the sky: Eye in the Sky', true, 'sky', ': idle', false])
    //? a failed search says why; a failure of a question superseded says nothing
    const failing = []
    const fails = library.librarySearch({ search: (query) => Promise.reject(new ApiError(503, "Navidrome isn't set up - fill in NAVIDROME_URL", 'failed')), onAnswer: (a) => failing.push(a), settleMs: 0 })
    fails.now('eye')
    await settle()
    check('...a search that fails says why, in deadwax\'s own words', failing.map((a) => a.state === 'failed' ? a.problem : a.state), ['asking', "Navidrome isn't set up - fill in NAVIDROME_URL"])
    check('...paced as the app\'s Search paces its library half: the same LIBRARY_SETTLE_MS', require(path.join(OUT, 'lib/searchQuery.js')).LIBRARY_SETTLE_MS, 200)
  }

  console.log('\na song from your library: played at the address the app\'s player asks for it at')
  {
    const song = (more) => ({ id: 'eye-in-the-sky', title: 'Eye in the Sky', artist: 'The Alan Parsons Project', album: 'Eye in the Sky', albumId: 'al-1', coverArt: 'al-1', duration: 276, contentType: 'audio/flac', suffix: 'flac', samplingRate: 44100, bitDepth: 16, channelCount: 2, ...more })
    const chromium = (playable) => ({ userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Safari/537.36', maxTouchPoints: 0, canPlayType: (type) => (playable(type) ? 'probably' : '') })
    const iphone = { userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1', maxTouchPoints: 5, canPlayType: (type) => (type === wrap.FLAC_IN_MP4 || type === 'audio/flac' ? 'maybe' : '') }
    const everything = chromium(() => true)
    const noOpus = chromium((type) => !type.includes('opus'))
    const address = (s, browser, cap) => library.libraryAddress(library.libraryTrack(s), browser, cap)
    //? the app's own helpers, asked as usePlayer asks them
    const apps = (s, browser, cap) => { const track = library.libraryTrack(s); return api.streamUrl(track, (type) => browser.canPlayType(type) !== '', wrap.wrapsFlac(browser), cap) }
    const cases = [
      [song({}), everything, '48000'], [song({}), iphone, '48000'],
      [song({ samplingRate: 96000, bitDepth: 24 }), everything, '48000'], [song({ samplingRate: 96000, bitDepth: 24 }), everything, 'original'],
      [song({ samplingRate: 96000, bitDepth: 24 }), iphone, '48000'],
      [song({ suffix: 'opus', contentType: 'audio/ogg' }), noOpus, '48000'], [song({ suffix: 'mp3', contentType: 'audio/mpeg' }), everything, '48000'],
    ]
    check('a CD-quality FLAC in Chromium as it is; in Safari (an iPhone) inside an MP4; a 96 kHz FLAC under "Up to 48 kHz" resampled (inside an MP4, in any browser), under "Original" as it is; an Opus song this browser can\'t play as Navidrome\'s MP3; an MP3 as it is',
      cases.map(([s, browser, cap]) => address(s, browser, cap)),
      ['/deadwax/navidrome/stream/eye-in-the-sky?format=raw', '/deadwax/navidrome/stream/eye-in-the-sky?format=raw&wrap=mp4',
        '/deadwax/navidrome/stream/eye-in-the-sky?format=raw&wrap=mp4&max_rate=48000', '/deadwax/navidrome/stream/eye-in-the-sky?format=raw',
        '/deadwax/navidrome/stream/eye-in-the-sky?format=raw&wrap=mp4&max_rate=48000',
        '/deadwax/navidrome/stream/eye-in-the-sky?format=mp3', '/deadwax/navidrome/stream/eye-in-the-sky?format=raw'])
    check('...each exactly what the app\'s helpers give for it (streamUrl, canPlayType, wrapsFlac, resamples)', cases.every(([s, browser, cap]) => address(s, browser, cap) === apps(s, browser, cap)), true)
    const track = library.libraryTrack(song({ samplingRate: 96000, bitDepth: 24 }))
    check('the app\'s own track for it (toQueueTrack): what the turntable reads of it, as of the app\'s - and the deck\'s cap Turntable\'s host\'s rule: 48000 for a hi-res FLAC under "Up to 48 kHz", none as it is or for a CD-quality song',
      [track, library.deckCap(track, '48000'), library.deckCap(track, 'original'), library.deckCap(library.libraryTrack(song({})), '48000'), library.formatLine(track), library.formatLine(library.libraryTrack(song({ samplingRate: undefined, bitDepth: undefined, channelCount: undefined })))],
      [{ id: 'eye-in-the-sky', title: 'Eye in the Sky', artist: 'The Alan Parsons Project', album: 'Eye in the Sky', albumId: 'al-1', coverArt: 'al-1', duration: 276, contentType: 'audio/flac', suffix: 'flac', sampleRate: 96000, bitDepth: 24, channels: 2 },
        48000, null, null, 'FLAC, 24-bit, 96 kHz, stereo', 'FLAC'])
  }

  console.log('\na song from your library, remembered: offered again once Navidrome has it, forgotten when it hasn\'t')
  {
    const kept = new Map()
    const storage = { getItem: (key) => kept.get(key) ?? null, setItem: (key, value) => kept.set(key, value), removeItem: (key) => kept.delete(key) }
    const eye = { id: 'eye', title: 'Eye in the Sky', artist: 'The Alan Parsons Project' }
    const nothing = await library.checkPick(async () => { throw new Error('never asked') }, storage)
    library.writePick(eye, storage)
    const keptAs = [library.PICK_KEY, JSON.parse(kept.get(library.PICK_KEY)), library.readPick(storage)]
    const found = await library.checkPick(async (id) => ({ ...eye, id, duration: 276 }), storage)
    const away = await library.checkPick(async () => { throw new ApiError(503, "Navidrome isn't answering", 'failed') }, storage)
    const stillKept = library.readPick(storage)
    const gone = await library.checkPick(async () => { throw new ApiError(404, 'Song not found', 'failed') }, storage)
    const afterGone = [kept.has(library.PICK_KEY), library.readPick(storage)]
    //? storage that can't be read, or holds something else: nothing remembered, nothing thrown
    const broken = { getItem: () => { throw new Error('denied') }, setItem: () => { throw new Error('full') }, removeItem: () => { throw new Error('denied') } }
    kept.set(library.PICK_KEY, '{not json')
    const odd = [library.readPick(broken), (library.writePick(eye, broken), 'no throw'), (library.forgetPick(broken), 'no throw'), library.readPick(storage), library.readPick(null)]
    check('nothing kept: nothing offered, Navidrome not asked; kept: its id, title and artist; Navidrome has it: offered; Navidrome away: kept, said; Navidrome hasn\'t it (a 404): forgotten; storage refusing or holding nonsense: nothing remembered, nothing thrown',
      [nothing.state, keptAs, [found.state, found.song?.duration], [away.state, away.problem], stillKept, gone.state, afterGone, odd],
      ['none', [library.PICK_KEY, eye, eye], ['found', 276], ['failed', "Navidrome isn't answering"], eye, 'forgotten', [false, null], [null, 'no throw', 'no throw', null, null]])
  }

  console.log('\nthe comparison on a library song: the windows over the path, decoded, read by the sinc from where each starts')
  {
    const rate = 44100
    const songNow = await signals.makeSignal('sweep', rate, { seconds: 120 })
    //? the long sinc from a window that starts at sample 220500 (5 s in) reads what it reads over the song
    //? held whole - the same samples placed by their first; outside the window, silence
    const whole = signals.sampledReader(songNow.channels[0], rate)
    const first = 220500
    const part = signals.sampledReader(songNow.channels[0].subarray(first, first + rate * 10), rate, first)
    const at = [5.5, 7.25, 9.123456]
    const diff = Math.max(...at.flatMap((t) => [22050, 8000, 3000].map((cutoff) => Math.abs(whole(t, cutoff) - part(t, cutoff)))))
    const unplaced = signals.sampledReader(songNow.channels[0].subarray(first, first + rate * 10), rate)
    check('the offset sampled reader: from a window starting 5 s in, the song\'s own reading at full band and with the cutoff lowered (within 1e-9); unplaced, it reads the wrong stretch; outside the window, silence',
      [diff < 1e-9, Math.abs(unplaced(7.25, 22050) - whole(7.25, 22050)) > 1e-3, part(2, 22050), part(30, 22050)], [true, true, 0, 0])
    //? where the paths went, and the span read: the lowest to highest place, plus the reach at the fastest,
    //? plus the margin - inside the song
    const pos = Float64Array.from([10, 10.5, 11, 99]), speed = Float64Array.from([1, 1, 2, 30]), gain = Float64Array.from([1, 1, 1, 0])
    const x = Float64Array.from([9.8, 11.2]), v = Float64Array.from([0.5, 1.5]), gainX = Float64Array.from([1, 1])
    const extent = compareModule.pathExtent(pos, speed, gain, x, v, gainX)
    const span = library.readSpan(extent, 48000, rate, 120)
    const reach = 48 * Math.max(1 / rate, 2 / 48000)
    check('where the paths went: only where they sound (a place with no gain left out), the lowest, highest and fastest over both; the span read covers it, the reader\'s reach at the fastest and half a second either side, inside the song',
      [extent, round(span.from, 9), round(span.to, 9), library.readSpan({ lowest: 0.2, highest: 119.9, fastest: 1 }, 48000, rate, 120), compareModule.pathExtent(pos, speed, Float64Array.from([0, 0, 0, 0]), x, v, Float64Array.from([0, 0]))],
      [{ lowest: 9.8, highest: 11.2, fastest: 2 }, round(9.8 - reach - library.READ_MARGIN_S, 9), round(11.2 + reach + library.READ_MARGIN_S, 9), { from: 0, to: 120 }, null])
    //? deadwax faked: a window from the frame at or before what was asked (here up to 0.1 s before), WINDOW_S
    //? long - or `budget` seconds, as a hi-res song's is cut short - and a 416 past the end
    const fake = (budget = 40) => {
      const asked = []
      const fetchWindow = async (at) => {
        asked.push(at)
        const begin = Math.max(0, Math.floor(at * 10) / 10 - 0.07)
        const w = signals.signalWindow(songNow, begin, Math.min(40, budget))
        return { bytes: w.bytes, first: w.first, samples: w.samples, rate: w.rate }
      }
      return { asked, fetchWindow }
    }
    const one = fake()
    const got1 = await library.readWindows({ from: 13.3, to: 30 }, one.fetchWindow)
    const two = fake()
    const got2 = await library.readWindows({ from: 13.3, to: 75 }, two.fetchWindow)
    const covered = (got, span) => got[0].first / rate <= span.from && got.every((w, i) => i === 0 || w.first <= got[i - 1].first + got[i - 1].samples) && (got.at(-1).first + got.at(-1).samples) / rate >= span.to
    const short = fake(13)
    const got3 = await library.readWindows({ from: 13.3, to: 45 }, short.fetchWindow)
    let tooMany = null, tooWide = null
    const many = fake(13)
    try { await library.readWindows({ from: 1, to: 60 }, many.fetchWindow) } catch (error) { tooMany = error.name }
    const wide = fake()
    try { await library.readWindows({ from: 1, to: 1 + 4 * 40 + 1 }, wide.fetchWindow) } catch (error) { tooWide = [error.name, error.message] }
    //? past the song's end: as far as it goes - a window that adds nothing, or deadwax's 416 for a start at
    //? or past the end (asked exactly where the last window ended, as deadwax answers it)
    const end = fake()
    const got4 = await library.readWindows({ from: 100, to: 125 }, end.fetchWindow)
    const strictAsked = []
    let got5 = null
    try {
      got5 = await library.readWindows({ from: 100, to: 125 }, async (at) => { strictAsked.push(at); const w = signals.signalWindow(songNow, at, 40); return { bytes: w.bytes, first: w.first, samples: w.samples, rate: w.rate } })
    } catch (error) {
      got5 = error.message
    }
    check('the windows read: one for a path within one, asked on the deck\'s grid; two for a path wider than one, the second from the grid point at or before where the first ended; three of a hi-res song\'s short windows for 31 s; more than COMPARE_WINDOWS_MAX (4) refused - a span past 4 windows\' worth before anything is asked; at the song\'s end, as far as it goes (a window that adds nothing ends it, as does deadwax\'s 416 past the end)',
      [[one.asked, covered(got1, { from: 13.3, to: 30 })], [two.asked, got2.length, covered(got2, { from: 13.3, to: 75 })], [short.asked.length, covered(got3, { from: 13.3, to: 45 })],
        [tooMany, many.asked.length], [tooWide?.[0], wide.asked.length, /more than 4 of deadwax's windows/.test(tooWide?.[1] ?? '')], [end.asked, got4.length, (got4.at(-1).first + got4.at(-1).samples) / rate],
        [strictAsked, Array.isArray(got5) ? got5.length : got5], library.COMPARE_WINDOWS_MAX],
      [[[12], true], [[12, 50], 2, true], [3, true], ['TooWide', 4], ['TooWide', 0, true], [[100, 120], 1, 120], [[100, 120], 1], 4])
    //? laid side by side by their first samples: the song's own samples over them, each sample the window's
    const decode = async (bytes, rateNow) => { const wav = signals.readWav(bytes); if (wav.rate !== rateNow) throw new Error('decoded at another rate'); return wav.channels }
    const stitched = await library.stitchWindows(got2, decode)
    const wav = signals.readWav(signals.signalWindow(songNow, stitched.first / rate, (stitched.samples.length + 1) / rate).bytes).channels[0]
    let worst = 0
    for (let i = 0; i < stitched.samples.length; i++) worst = Math.max(worst, Math.abs(stitched.samples[i] - wav[i]))
    check('...laid side by side by their first samples: the song\'s own samples from the first window\'s start to the last one\'s end, sample for sample',
      [stitched.first === got2[0].first, stitched.samples.length === got2.at(-1).first + got2.at(-1).samples - got2[0].first, worst, stitched.rate], [true, true, 0, rate])
    //? and the window the voice had, asked again: from the grid point it began within - its own start, or
    //? the next grid point when deadwax began it on a frame or fragment before
    check('the voice\'s window asked again from the grid point the deck asked it from',
      [library.voiceWindowFrom(0), library.voiceWindowFrom(38), library.voiceWindowFrom(37.95), library.voiceWindowFrom(36.2), library.voiceWindowFrom(1675800 / 44100), library.voiceWindowFrom(38 + 1e-12)],
      [0, 38, 38, 38, 38, 38])
    //? music has no "what isn't the signal": said so, where a tone has its number
    const numbers = { strayed: null, wobble: { deadwax: 0.01, smooth: 0.01 }, stray: null, silenceDb: null, replayDb: -100, alignScore: 1, leadMs: 0, fitMs: 0.0001, taken: true }
    const labels = (rows) => rows.map((row) => row.label)
    check('the numbers on music: the wobble, the read head, the replay - and "what isn\'t the signal" said not to be measured on music, with why; on a tone, its number, and no such line',
      [labels(reading.numberRows(numbers, true)), reading.numberRows(numbers, true).find((row) => row.value === 'Not measured on music') === reading.NOT_ON_MUSIC, labels(reading.numberRows(numbers)),
        labels(reading.numberRows({ ...numbers, stray: { db: -80, loudest: null } }, true))],
      [['Read head off the smooth path', 'Speed wobble above 20 Hz', "What isn't the signal", 'The replay'], true, ['Read head off the smooth path', 'Speed wobble above 20 Hz', 'The replay'],
        ['Read head off the smooth path', 'Speed wobble above 20 Hz', "What isn't the signal (A against B)", 'The replay']])
  }

  console.log('\nthe library song\'s player: the app\'s track and setting, what its element can play, a song that won\'t load, the element\'s own length')
  {
    class FakeAudio {
      constructor() { this.paused = true; this.currentTime = 0; this.seeking = false; this.listeners = {}; this.address = null; this.preload = ''; this.duration = NaN; this.error = null; this.loads = 0 }
      addEventListener(name, f) { (this.listeners[name] ??= new Set()).add(f) }
      removeEventListener(name, f) { this.listeners[name]?.delete(f) }
      fire(name) { for (const f of [...(this.listeners[name] ?? [])]) f() }
      play() { this.paused = false; return Promise.resolve() }
      pause() { this.paused = true }
      load() { this.loads++; this.error = null; this.duration = NaN }
      set src(address) { this.address = address; this.load() }
      get src() { return this.address }
      getAttribute(name) { return name === 'src' ? this.address : null }
      removeAttribute() { this.address = null; this.load() }
      canPlayType(type) { return type === 'audio/flac' ? 'probably' : '' }
    }
    const made = []
    const page = globalThis.document
    define('document', { ...page, createElement: (tag) => { const element = tag === 'audio' ? new FakeAudio() : {}; made.push(element); return element } })
    const { useBenchPlayer, loadProblem } = require(path.join(OUT, 'lab/benchPlayer.js'))
    const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
    const render = hooks.root(useBenchPlayer)
    const track = library.libraryTrack({ id: 'eye', title: 'Eye in the Sky', artist: 'The Alan Parsons Project', duration: 276, suffix: 'flac', contentType: 'audio/flac', samplingRate: 96000, bitDepth: 24, channelCount: 2 })
    const songOf = (n) => ({ id: `library-eye-${n}`, title: 'Eye in the Sky', seconds: 276, rate: 96000, channels: 2, url: '/deadwax/navidrome/stream/eye?format=raw&wrap=mp4&max_rate=48000', library: { track, maxRate: '48000' } })
    let player = render(songOf(1)); render.commit(); player = render(songOf(1))
    const element = made.find((one) => one instanceof FakeAudio)
    const first = [player.track === track, player.maxRate, player.duration, player.canPlayType('audio/flac'), player.problem, element.src]
    element.duration = 275.62; element.fire('durationchange'); player = render(songOf(1))
    const length = player.duration
    element.error = { code: 4 }; element.fire('error'); player = render(songOf(1))
    const failed = [player.problem, player.playing]
    //? the same song picked again: a new id, the same address - loaded again, the problem let go of
    const loadsBefore = element.loads
    player = render(songOf(2)); render.commit(); player = render(songOf(2))
    check('a library song: the app\'s own track and its Maximum quality to the turntable; Navidrome\'s length until the element knows its own (as usePlayer\'s songLength); what its one element can play; a song that won\'t load said plainly; picked again, asked for again',
      [first, length, failed, element.loads > loadsBefore, player.problem, loadProblem(2), loadProblem(undefined)],
      [[true, '48000', 276, 'probably', null, '/deadwax/navidrome/stream/eye?format=raw&wrap=mp4&max_rate=48000'], 275.62,
        ["deadwax or Navidrome didn't send it, or this browser can't play what they sent", false], true, null, 'the connection broke off while it loaded', 'the browser gave no reason'])
    //? a song the bench made keeps its own length whatever its element says - nothing about it changed
    const wav = { id: 'lab-1', title: 'Sine', seconds: 120, rate: 44100, channels: 1, url: 'blob:1' }
    player = render(wav); render.commit(); player = render(wav)
    element.duration = 119.5; element.fire('durationchange'); player = render(wav)
    check('...a song the bench made: its own length, its own track, "Original" - as before', [player.duration, player.track.suffix, player.maxRate], [120, 'wav', 'original'])
    render.unmount()
    define('document', page)
  }

  console.log('\nthe real deck on a library song: no window source - it asks deadwax\'s scrub route, as the app\'s does - and B and C read from deadwax\'s windows')
  for (const host of ['worklet', 'script']) {
    const track = library.libraryTrack({ id: 'eye in the sky/1', title: 'Eye in the Sky', artist: 'The Alan Parsons Project', duration: 40, suffix: 'flac', contentType: 'audio/flac', samplingRate: 96000, bitDepth: 24, channelCount: 1 })
    const run = await deckRun({
      host, library: { track, maxRate: '48000' },
      probe: async ({ deck, world, asked }) => {
        const report = deckModule.deckReport()
        check(`${host}: with no window source the deck asks deadwax's scrub route for the song's window - its id, on the deck's grid, 40 s, at the cap Turntable's host works out (48000 for a hi-res FLAC under "Up to 48 kHz") - and plays it`,
          [asked.length, world.served.length >= 1, /^\/deadwax\/navidrome\/scrub\/eye%20in%20the%20sky%2F1\?at=\d*[02468]&seconds=40&max_rate=48000$/.test(world.served[0] ?? ''), library.deckCap(track, '48000'), report?.window?.kind, deck.live()],
          [0, true, true, 48000, 'FLAC', true])
      },
    })
    //? B and C read from the song's windows over the path - the windows asked of the scrub route as the
    //? deck asks them, at its cap, laid side by side - against B and C read from the song's own definition
    const cap = library.deckCap(track, '48000')
    const decodeWav = async (bytes) => signals.readWav(bytes).channels
    const asked = []
    const exactOver = async (extent) => {
      const span = library.readSpan(extent, run.rate, run.rate, 40)
      const windows = await library.readWindows(span, (at) => { asked.push(at); return api.scrubWindow(track.id, at, 40, undefined, cap) })
      const stitched = await library.stitchWindows(windows, decodeWav)
      return signals.sampledReader(stitched.samples, stitched.rate, stitched.first)
    }
    const fromWindows = await run.compareWith(null, false, run.data, exactOver)
    const fromDefinition = await run.compareWith(run.exact, false)
    const gap = (a, b) => { let d = 0, e = 0; for (let i = 0; i < a.length; i++) { d += (a[i] - b[i]) ** 2; e += b[i] ** 2 } return 10 * Math.log10(d / e) }
    console.log(`    (${host}: B from the windows against B from the definition ${round(gap(fromWindows.clips.B, fromDefinition.clips.B), 1)} dB, C ${round(gap(fromWindows.clips.C, fromDefinition.clips.C), 1)} dB; asked at ${JSON.stringify(asked)})`)
    check(`${host}: B and C read from deadwax's windows over the path are the song read exactly (within -100 dB of reading its definition), with nothing left out; the numbers that need only the paths the same either way`,
      [fromWindows.unread, gap(fromWindows.clips.B, fromDefinition.clips.B) < -100, gap(fromWindows.clips.C, fromDefinition.clips.C) < -100,
        JSON.stringify(fromWindows.numbers.wobble) === JSON.stringify(fromDefinition.numbers.wobble), fromWindows.numbers.replayDb === fromDefinition.numbers.replayDb, asked.length >= 1, asked.every((at) => at % 2 === 0)],
      [null, true, true, true, true, true, true])
    //? where the windows can't be had - too wide, or deadwax not sending one - A and the paths' numbers stand,
    //? B and C left out with why
    const refused = await run.compareWith(null, false, run.data, async () => { throw new library.TooWide(300) })
    check(`${host}: windows that can't be had: no B or C, said why; A, the wobble, the read head and the replay all the same`,
      [refused.clips.B, refused.clips.C, /more than 4 of deadwax's windows/.test(refused.unread ?? ''), refused.clips.A.length === fromDefinition.clips.A.length,
        JSON.stringify(refused.numbers.wobble) === JSON.stringify(fromDefinition.numbers.wobble), JSON.stringify(refused.numbers.strayed) === JSON.stringify(fromDefinition.numbers.strayed), refused.numbers.stray],
      [null, null, true, true, true, true, null])
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
