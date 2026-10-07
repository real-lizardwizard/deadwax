/**
 * The record's sound never clips (2.0.0-player.35). James, after five fixes: "yeah it still has a pretty
 * digital sound". His recording (Info > Debug > Record 20 s) held 144 samples at full scale over 16 s, in
 * 15 bursts on the loudest drum hits, at every speed: reading a loud master between its samples recreates its
 * intersample peaks, above full scale, the voice's DC blocker adds to them, and the browser cuts what is
 * over 1.0 at its output. So the voice ends in a lookahead peak limiter (lib/deckVoice.ts, renderVoice).
 * This runs the real voice - its functions directly, and again as the AudioWorklet module the browser
 * loads, made from their own source - against the voice as it was (fixtures/deckVoice-2.0.0-player.29.cjs,
 * no limiter).
 *
 * What it pins:
 *
 *  - THE GUARANTEE: no sample the voice writes is above VOICE_CEILING (-0.5 dBFS), whatever it reads -
 *    full-scale square waves, impulses and doublets, full-scale noise, a tone at Nyquist - at every rate
 *    from -24 to 24, through takes, fades, stops, a hand, a window changed mid-block and a window running
 *    out, at 22.05 to 192 kHz (and 768 kHz, past what its rings were sized for), on the worklet's path
 *    (the module, 128 a block) and the main thread's (1024 a block). Never NaN: silence is silence, and a
 *    window holding NaN or Infinity writes only numbers.
 *  - TRANSPARENT: where nothing reaches the ceiling, the output is the voice as it was, sample for sample,
 *    bit for bit, only later by the lookahead - round(VOICE_LOOKAHEAD_S x the rate) samples at each rate -
 *    right up to the ceiling (the voice as it was peaking at 0.99999 of it), with nothing held; after a
 *    peak, once its gain is back up, bit for bit again.
 *  - HOW IT TURNS THE SOUND DOWN: ahead of a peak, over the lookahead, never a step - its gain's change
 *    from one sample to the next itself changes smoothly (two boxes: a triangle, not one box's corners);
 *    held at its lowest for the hold (HOLD_S, 20 ms) and no longer, then back up over the release
 *    (RELEASE_S, 60 ms) at the release's own rate;
 *    one gain for both channels, so a peak in one turns both down alike. A steady low tone over the
 *    ceiling, from about 20 Hz up, is turned down without being shaped (the hold outlasts half its cycle):
 *    no distortion, where clipping it is -37 dB of harmonics. Below that - a slowed record's deepest bass -
 *    half a cycle outlasts the lookahead and the hold, the gain follows each crest, and the harmonics it
 *    leaves are pinned as measured (-43 dB at 8 Hz, 0.45 dB over the ceiling, to -60 at 17).
 *  - WHAT IT SAYS: each report carries how many samples it brought down since the last, in how many runs,
 *    and the lowest gain it wrote - counted afresh after each, and adding up to the whole.
 *  - SELF-CONTAINED: the worklet's module, made from the four functions' own text, plays loud material
 *    exactly as the functions do and says the same; the functions name nothing outside themselves - not
 *    VOICE_CEILING nor VOICE_LOOKAHEAD_S, whose literals in renderVoice are held equal to them; and its
 *    rings are made in newVoiceState, sized for 192 kHz.
 *
 * ui/test/deck.sim.cjs holds the counts reaching the deck's health and the recorder's block peaks; and
 * ui/test/debug.sim.cjs Info > Debug's words for them.
 *
 * Run it with:  node ui/test/limiter.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path'), vm = require('vm')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-limiter-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/deckVoice.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable',
], { cwd: UI, stdio: 'inherit' })

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
const round = (value, places = 4) => Math.round(value * 10 ** places) / 10 ** places
let seed = 35
const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648)

const voice = require(path.join(OUT, 'lib/deckVoice.js'))
const before = require(path.join(__dirname, 'fixtures/deckVoice-2.0.0-player.29.cjs'))
const CEILING = voice.VOICE_CEILING
const lookaheadAt = (sr) => Math.round(voice.VOICE_LOOKAHEAD_S * sr)

/* ===== running a voice ===== */

/**
 * A voice run through a script of messages: `script(time, frame, blockSeconds)` gives the messages to say
 * at the start of each block (as a host applies them, at the block's own time), `seconds` of output at
 * `sr`, `block` frames a block, `channels` of output (64-bit with `float64`, to see what was written before
 * a 32-bit buffer rounds it). `host` 'functions' calls the functions; 'worklet' runs the module the
 * browser loads (voiceWorkletSource, in a scope of its own) - its process() 128 at a time, as a worklet is
 * called. Returns the output, channel by channel, and every report.
 */
function run(lib, { script, seconds, sr = 48000, block = 128, channels = 2, host = 'functions', float64 = false }) {
  const frames = Math.round(seconds * sr)
  const Buffer = float64 ? Float64Array : Float32Array
  const out = Array.from({ length: channels }, () => new Buffer(frames))
  const reports = []
  let processor = null, scope = null
  const state = host === 'functions' ? lib.newVoiceState() : null
  if (host === 'worklet') {
    const registered = {}
    class AudioWorkletProcessor { constructor() { this.port = { postMessage: (m) => reports.push(m), onmessage: null } } }
    scope = { AudioWorkletProcessor, registerProcessor: (name, Processor) => { registered[name] = Processor }, sampleRate: sr, currentTime: 0, Math, Float32Array, Float64Array, Uint8Array }
    vm.createContext(scope)
    vm.runInContext(lib.voiceWorkletSource(), scope)
    processor = new registered[lib.VOICE_PROCESSOR]()
  }
  for (let at = 0; at < frames; at += block) {
    const n = Math.min(block, frames - at)
    const time = at / sr
    for (const message of script(time, at, n / sr) ?? []) {
      if (host === 'functions') lib.voiceCommand(state, message, time, sr)
      else { scope.currentTime = time; processor.port.onmessage({ data: message }) }
    }
    const bufs = Array.from({ length: channels }, () => new Buffer(n))
    if (host === 'functions') {
      lib.renderVoice(state, bufs, n, sr, time)
      const heard = lib.voiceReport(state, n, sr, time, lib.REPORTS_PER_SECOND)
      if (heard) reports.push(heard)
    } else {
      scope.currentTime = time
      processor.process([], [bufs])
    }
    for (let c = 0; c < channels; c++) out[c].set(bufs[c], at)
  }
  return { out, reports, state }
}

const peakOf = (out) => { let p = 0; for (const data of out) for (const v of data) { const a = Math.abs(v); if (a > p) p = a } return p }
const hasNaN = (out) => out.some((data) => data.some((v) => !Number.isFinite(v)))
const window = (channels, rate, start = 0) => ({ type: 'window', channels, start, rate })

/* ===== adversarial windows: everything at or near full scale ===== */

function fill(length, f) { const data = new Float32Array(length); for (let i = 0; i < length; i++) data[i] = f(i); return data }
const loud = (rate, seconds) => {
  const n = Math.round(rate * seconds)
  return {
    'full-scale square, 1 kHz': [fill(n, (i) => (Math.floor((i * 2000) / rate) % 2 ? -1 : 1))],
    'full-scale square, 97 Hz, the channels apart': [fill(n, (i) => (Math.floor((i * 194) / rate) % 2 ? -1 : 1)), fill(n, (i) => (Math.floor((i * 194) / rate + 0.5) % 2 ? 1 : -1))],
    'impulses and doublets at full scale': [fill(n, (i) => (i % 997 === 0 ? 1 : i % 997 === 1 ? -1 : i % 1499 === 0 ? -1 : 0))],
    'full-scale noise': [fill(n, () => 2 * random() - 1)],
    'full scale at Nyquist (+1, -1, ...)': [fill(n, (i) => (i % 2 ? -1 : 1))],
    'a full-scale tone at 0.45 of the rate': [fill(n, (i) => Math.sin(2 * Math.PI * 0.45 * i))],
  }
}
const RATES = [-24, -12, -4, -2, -1.5, -1, -0.5, -0.1, 0, 0.1, 0.5, 1, 1.5, 2, 4, 12, 24]

console.log('\nthe guarantee: no sample above the ceiling, whatever it reads, at every rate from -24 to 24')
{
  const results = []
  let worst = 0, nan = false, runs = 0
  for (const [name, channels] of Object.entries(loud(48000, 3))) {
    for (const rate of RATES) {
      for (const host of ['functions', 'worklet']) {
        const { out } = run(voice, {
          seconds: 0.25, sr: 48000, block: host === 'worklet' ? 128 : 1024, host,
          script: (time) => (time === 0 ? [window(channels, 48000), { type: 'take', at: 1.5, rate, time: 0, until: 100 }] : []),
        })
        worst = Math.max(worst, peakOf(out))
        nan = nan || hasNaN(out)
        runs++
      }
    }
    results.push(name)
  }
  check(`${results.length} full-scale windows x ${RATES.length} rates x both hosts (${runs} runs): the loudest sample written is at most the ceiling, ${round(CEILING, 6)} (-0.5 dBFS)`, [worst <= CEILING, nan], [true, false])
  const loudest = Math.max(...Object.values(loud(48000, 3)).map((channels) => {
    const { out } = run(before, { seconds: 0.25, sr: 48000, block: 1024, script: (time) => (time === 0 ? [window(channels, 48000), { type: 'take', at: 1.5, rate: 0.5, time: 0, until: 100 }] : []) })
    return peakOf(out)
  }))
  check(`...where the voice as it was wrote ${round(20 * Math.log10(loudest), 1)} dBFS at 0.5x alone`, loudest > 1, true)
}

console.log('\n...through takes, fades, stops, a hand, a window changed mid-block and one running out - at every rate a host can have')
{
  //? a loud window, a louder one swapped in mid-block, a hand swinging fast both ways, a fade, a stop, a take at
  //? 24x, a run past the window's end: everything the deck says, as it says it
  const story = (sr) => {
    const a = loud(sr, 2)['full-scale noise']
    const b = loud(sr, 2)['full-scale square, 1 kHz']
    const short = [fill(Math.round(sr * 0.3), (i) => (i % 2 ? -1 : 1))]
    return (time, at, span) => {
      const said = []
      const step = (t) => time <= t && time + span > t
      if (at === 0) said.push(window(a, sr), { type: 'take', at: 0.5, rate: 1, time: 0, until: 0.2 })
      if (step(0.05)) said.push(window(b, sr))
      if (time >= 0.06 && time < 0.3 && Math.floor(time * 240) !== Math.floor((time - span) * 240)) said.push({ type: 'hand', at: 0.6 + 0.4 * Math.sin(time * 40), time })
      if (step(0.3)) said.push({ type: 'drive', at: 0.8, rate: -3, accel: 6, time, until: time + 0.5 })
      if (step(0.42)) said.push({ type: 'fade', seconds: 0.04 })
      if (step(0.5)) said.push({ type: 'take', at: 0.3, rate: 24, time, until: time + 0.3 })
      if (step(0.56)) said.push({ type: 'stop' })
      if (step(0.6)) said.push(window(short, sr, 0), { type: 'take', at: 0.25, rate: 1.5, time, until: time + 1 })
      if (step(0.75)) said.push({ type: 'take', at: 0.1, rate: -24, time, until: time + 1 })
      return said
    }
  }
  const results = {}
  for (const sr of [22050, 44100, 48000, 96000, 192000, 768000]) {
    let worst = 0, nan = false
    //? a sample at a time only up to 48 kHz: it is the same samples (each is worked out from the state and
    //? its own time alone), and slow
    const hosts = [['functions', 1024], ['worklet', 128], ['functions', 333], ...(sr <= 48000 ? [['functions', 1]] : [])]
    for (const [host, block] of hosts) {
      const { out } = run(voice, { seconds: 0.9, sr, block, host, script: story(sr) })
      worst = Math.max(worst, peakOf(out))
      nan = nan || hasNaN(out)
    }
    results[sr] = worst <= CEILING && !nan
  }
  check('at 22.05, 44.1, 48, 96 and 192 kHz - and 768, past what its rings were sized for (the lookahead is held to them, in samples) - in blocks of 1024, 128 (the worklet\'s module) and 333, and a sample at a time up to 48 kHz: never above the ceiling, never NaN',
    results, { 22050: true, 44100: true, 48000: true, 96000: true, 192000: true, 768000: true })
}

console.log('\nnever NaN: silence is silence, and a window of what isn\'t a number writes only numbers')
{
  const silent = run(voice, { seconds: 0.2, script: (time) => (time === 0 ? [window([new Float32Array(48000)], 48000), { type: 'take', at: 0.2, rate: 1, time: 0, until: 100 }] : []) })
  check('a window of silence, read at speed: every sample written exactly 0', silent.out.every((data) => data.every((v) => v === 0)), true)
  const resting = run(voice, { seconds: 0.1, script: () => [] })
  check('a voice that has been told nothing: exactly 0 too', resting.out.every((data) => data.every((v) => v === 0)), true)
  const bad = fill(48000, (i) => (i % 500 === 0 ? NaN : i % 777 === 0 ? Infinity : 0.3 * Math.sin(i / 10)))
  const broken = run(voice, { seconds: 0.3, script: (time) => (time === 0 ? [window([bad], 48000), { type: 'take', at: 0.1, rate: 1, time: 0, until: 100 }] : []) })
  check('a window holding NaN and Infinity (nothing decodeAudioData gives): what is written is a number, under the ceiling', [hasNaN(broken.out), peakOf(broken.out) <= CEILING], [false, true])
}

console.log('\n...nor for a window of samples far past full scale: the gain is never below 0 (review of 2.0.0-player.35)')
{
  //? 50 ms of a huge square-ish wave, then 50 ms at half scale, over and over (the review's case): with the
  //? huge stretch's need below the rounding left in the boxes' running sums by the values near 1 they held,
  //? a sum - and the gain - came out a hair under 0, and a huge sample times it was 1.469 at 1e16 and 1241
  //? at 1e20, past the ceiling. Never in a decoded window (its samples are within +-1), but the guarantee
  //? is for whatever the voice reads: the gain is floored at 0 too
  const results = {}
  for (const amp of [1e16, 1e20, 3.4e38]) {
    const n = 44100 * 4
    const data = fill(n, (i) => (Math.floor(i / (44100 * 0.05)) % 2 ? 0.5 : amp) * (i % 7 < 3 ? 1 : -1))
    const said = []
    for (const host of ['functions', 'worklet']) {
      const { out, reports } = run(voice, {
        seconds: 1, sr: 48000, block: host === 'worklet' ? 128 : 1024, host,
        script: (time) => (time === 0 ? [window([data, data], 44100), { type: 'take', at: 2, rate: 1, time: 0, until: 1e9 }] : []),
      })
      said.push(peakOf(out) <= CEILING, hasNaN(out), reports.every((r) => r.lowest >= 0 && r.lowest <= 1))
    }
    results[amp] = said
  }
  check('alternating 50 ms of +-1e16, +-1e20 and +-3.4e38 with 50 ms of +-0.5, on the functions (1024 a block) and the worklet\'s module (128): under the ceiling, never NaN, and every report\'s lowest gain between 0 and 1',
    results, { 1e16: [true, false, true, true, false, true], 1e20: [true, false, true, true, false, true], 3.4e38: [true, false, true, true, false, true] })
}

/* ===== transparent ===== */

console.log('\ntransparent: under the ceiling, the voice as it was, bit for bit - only later by the lookahead')
{
  const results = {}
  for (const sr of [44100, 48000, 96000, 192000]) {
    //? music under the ceiling - a chord and a little noise, peaking about -3.5 dBFS, read by a hand that
    //? swings back and forth, then coasts: everything the voice does but go near the ceiling
    const n = sr * 3
    const tone = fill(n, (i) => 0.25 * Math.sin((2 * Math.PI * 220 * i) / sr) + 0.2 * Math.sin((2 * Math.PI * 1375 * i) / sr) + 0.15 * Math.sin((2 * Math.PI * 7040 * i) / sr) + 0.05 * (random() - 0.5))
    const script = (time, at) => {
      const said = at === 0 ? [window([tone], sr), { type: 'take', at: 1, rate: 1, time: 0, until: 0.2 }] : []
      if (time > 0.1 && time < 0.6) said.push({ type: 'hand', at: 1.05 + 0.3 * Math.sin(time * 9), time })
      if (time >= 0.6 && time < 0.6 + 1024 / sr) said.push({ type: 'drive', at: 1.2, rate: 2, accel: -2, time, until: time + 2 })
      return said
    }
    const now = run(voice, { seconds: 1.2, sr, block: 1024, script }).out
    const was = run(before, { seconds: 1.2, sr, block: 1024, script }).out
    const D = lookaheadAt(sr)
    let same = Math.abs(peakOf(was)) < CEILING
    for (let c = 0; c < 2; c++) {
      for (let i = 0; i < D; i++) if (now[c][i] !== 0) same = false
      for (let i = D; i < now[c].length; i++) if (now[c][i] !== was[c][i - D]) same = false
    }
    results[sr] = [D, same]
  }
  check('at 44.1, 48, 96 and 192 kHz: silence for the lookahead (66, 72, 144, 288 samples - round(VOICE_LOOKAHEAD_S x the rate)), then every sample exactly the voice as it was',
    results, { 44100: [66, true], 48000: [72, true], 96000: [144, true], 192000: [288, true] })
  check('VOICE_LOOKAHEAD_S is 1.5 ms and VOICE_CEILING -0.5 dBFS as a 32-bit float - the literals renderVoice holds (it names nothing outside itself)',
    [voice.VOICE_LOOKAHEAD_S, CEILING === Math.fround(Math.pow(10, -0.5 / 20)), /const LOOKAHEAD_S = 0\.0015\b/.test(voice.renderVoice.toString()), /const CEILING = Math\.fround\(Math\.pow\(10, -0\.5 \/ 20\)\)/.test(voice.renderVoice.toString())],
    [0.0015, true, true, true])
}

console.log('\n...right up to the ceiling: the same chord turned up until the voice as it was peaks a hair under it')
{
  //? the chord above peaks about 3.5 dB under the ceiling, and nothing else here goes between that and the
  //? ceiling without going over it - so a limiter acting a little early (a "gentler" knee from -3 dBFS) passed
  //? every check (review of 2.0.0-player.35). The same material, scaled so the voice as it was peaks at
  //? 0.99999 of the ceiling in 64 bits: still the voice as it was, bit for bit, and nothing held
  const results = {}
  for (const sr of [44100, 48000, 96000, 192000]) {
    const n = sr * 3
    const chord = fill(n, (i) => 0.25 * Math.sin((2 * Math.PI * 220 * i) / sr) + 0.2 * Math.sin((2 * Math.PI * 1375 * i) / sr) + 0.15 * Math.sin((2 * Math.PI * 7040 * i) / sr) + 0.05 * (random() - 0.5))
    const scriptFor = (data) => (time, at) => {
      const said = at === 0 ? [window([data], sr), { type: 'take', at: 1, rate: 1, time: 0, until: 0.2 }] : []
      if (time > 0.1 && time < 0.6) said.push({ type: 'hand', at: 1.05 + 0.3 * Math.sin(time * 9), time })
      if (time >= 0.6 && time < 0.6 + 1024 / sr) said.push({ type: 'drive', at: 1.2, rate: 2, accel: -2, time, until: time + 2 })
      return said
    }
    const scale = (0.99999 * CEILING) / peakOf(run(before, { seconds: 1.2, sr, block: 1024, script: scriptFor(chord), float64: true }).out)
    const loud = Float32Array.from(chord, (v) => v * scale)
    const top = peakOf(run(before, { seconds: 1.2, sr, block: 1024, script: scriptFor(loud), float64: true }).out)
    const { out: now, reports } = run(voice, { seconds: 1.2, sr, block: 1024, script: scriptFor(loud) })
    const was = run(before, { seconds: 1.2, sr, block: 1024, script: scriptFor(loud) }).out
    const D = lookaheadAt(sr)
    let same = true
    for (let c = 0; c < 2; c++) {
      for (let i = 0; i < D; i++) if (now[c][i] !== 0) same = false
      for (let i = D; i < now[c].length; i++) if (now[c][i] !== was[c][i - D]) same = false
    }
    results[sr] = [top <= CEILING && top >= 0.9999 * CEILING, same, reports.length > 20 && reports.every((r) => r.held === 0 && r.peaks === 0 && r.lowest === 1)]
  }
  check('at 44.1, 48, 96 and 192 kHz: the voice as it was peaking within 0.0009 dB under the ceiling (in 64 bits), and the limited sound exactly it, the lookahead later - every report saying nothing held (no peaks, lowest gain 1)',
    results, { 44100: [true, true, true], 48000: [true, true, true], 96000: [true, true, true], 192000: [true, true, true] })
}

/* ===== how it turns the sound down ===== */

//? one loud click on a steady 4 kHz tone: the gain read back from what was written against the voice as it was
const SR = 48000
const D = lookaheadAt(SR)
function clicked({ clickAt = 0.3, size = 2, seconds = 2.5, channels = 1, right } = {}) {
  const n = SR * 4
  const left = fill(n, (i) => 0.3 * Math.sin((2 * Math.PI * 4000 * i) / SR))
  const click = Math.round((1 + clickAt) * SR)
  left[click] = size
  const chans = channels === 2 ? [left, right ?? fill(n, (i) => 0.3 * Math.sin((2 * Math.PI * 4000 * i) / SR + 1))] : [left]
  const script = (time) => (time === 0 ? [window(chans, SR), { type: 'take', at: 1 + 0.12, rate: 1, time: 0, until: 100 }] : [])
  const now = run(voice, { seconds, sr: SR, block: 128, script, channels: 2 })
  const was = run(before, { seconds, sr: SR, block: 128, script, channels: 2 })
  //? the sample of the voice's output the click is: the voice plays the path 0.12 s behind, so at the
  //? click's own place in the window, less the take's 1 s - found as the loudest
  let at = 0
  for (let i = 0; i < was.out[0].length; i++) if (Math.abs(was.out[0][i]) > Math.abs(was.out[0][at])) at = i
  const gain = (c, i) => (Math.abs(was.out[c][i]) > 0.05 ? now.out[c][i + D] / was.out[c][i] : null)
  return { now, was, at, gain, reports: now.reports }
}

console.log('\nhow it turns the sound down: ahead of the peak, smoothly, held, then back up')
{
  const { was, now, at, gain } = clicked()
  const need = CEILING / Math.abs(was.out[0][at])
  //? the gain on each sample of the voice as it was, where the tone is loud enough to read it by: what was
  //? written for it, the lookahead later, over it (both 32-bit: a gain of exactly 1 reads exactly 1)
  const gains = Array.from({ length: was.out[0].length - D }, (_, i) => gain(0, i))
  check('the click, written: under the ceiling - turned down to what it needs, or a hair under', [Math.abs(now.out[0][at + D]) <= CEILING, now.out[0][at + D] / was.out[0][at] <= need * (1 + 1e-6)], [true, true])
  const early = gains.slice(at - D - 200, at - D).filter((v) => v !== null)
  check('...before the lookahead, the tone untouched: gain exactly 1', [early.length > 100, early.every((v) => v === 1)], [true, true])
  const ramp = gains.slice(at - D, at + 1).filter((v) => v !== null)
  check('...over the lookahead it comes down, never back up on the way', ramp.every((v, k) => k === 0 || v <= ramp[k - 1] + 1e-6), true)
  const lowest = Math.min(...gains.filter((v) => v !== null))
  const lengthA = Math.ceil((D + 2) / 2), lengthB = D + 2 - lengthA
  const depth = 1 - lowest
  //? the triangle's steepest slope is depth / lengthA a sample, and it bends by depth / (lengthA x lengthB);
  //? one box's ramp would turn its corners in one sample, a bend of depth / (D + 1)
  let steepest = 0, bend = 0
  for (let i = 2; i < gains.length; i++) {
    if (gains[i] === null || gains[i - 1] === null || gains[i - 2] === null) continue
    steepest = Math.max(steepest, Math.abs(gains[i] - gains[i - 1]))
    bend = Math.max(bend, Math.abs(gains[i] - 2 * gains[i - 1] + gains[i - 2]))
  }
  check(`never a step: from one sample to the next the gain moves at most depth / ${lengthA} (${round(depth / lengthA, 5)}), and how it moves changes smoothly - by at most depth / (${lengthA} x ${lengthB}), ${round(depth / (lengthA * lengthB), 6)}: a triangle (one box's corners would bend it ${round(depth / (D + 1), 5)})`,
    [round(steepest, 6) <= round((depth / lengthA) * 1.02, 6), bend <= (depth / (lengthA * lengthB)) * 1.1], [true, true])
  //? held: at its lowest from the click to the hold's end (20 ms: the samples the click's need stays the
  //? running minimum of, less the lookahead's ramp back up through the boxes at the end)
  const hold = Math.round(0.02 * SR)
  const held = gains.slice(at, at + hold).filter((v) => v !== null)
  check('held at its lowest for the hold, 20 ms', [held.length > hold / 2, held.every((v) => Math.abs(v - lowest) < 1e-6)], [true, true])
  //? after the hold the deficit falls by e over each RELEASE_S - from the middle of the boxes' window
  const near = (k) => { for (let j = 0; j < 50; j++) for (const i of [k + j, k - j]) if (gains[i] !== null && gains[i] !== undefined) return gains[i]; return null }
  const ratio = (1 - near(at + hold + Math.round(0.06 * SR) + D / 2)) / depth
  check(`...then back up over the release: 60 ms after the hold, about 1/e of the dip is left (${round(ratio, 3)})`, ratio > 0.33 && ratio < 0.42, true)
  //? ...and no longer than the hold (review of 2.0.0-player.35): 2 ms after it the gain has started back up -
  //? 2% of the dip, the triangle's slow start - where a hold even 1 ms longer would still have it at its
  //? lowest there. The release window above lets a hold of up to about 28 ms through on its own
  const risen = (near(at + hold + Math.round(0.002 * SR)) - lowest) / depth
  check(`...and no longer: 2 ms after the hold the gain is on its way back up (${round(risen * 100, 2)}% of the dip, at least 1%)`, risen > 0.01 && risen < 0.05, true)
  //? the release's own rate, apart from where it starts: the dip left falls by e over each RELEASE_S, so two
  //? points 60 ms apart hold the ratio 1/e whatever the hold - to 1% (a release 1% shorter or longer is not)
  const left = (ms) => 1 - near(at + hold + Math.round((ms / 1000) * SR) + D / 2)
  const fall = left(120) / left(60)
  check(`...at its own rate: from 60 to 120 ms after the hold, the dip left falls by e (${round(fall, 4)} against ${round(Math.exp(-1), 4)}, to 1%)`, Math.abs(fall / Math.exp(-1) - 1) < 0.01, true)
  const back = gains.slice(at + Math.round(1.1 * SR)).filter((v) => v !== null)
  check('...and 1.1 s on, exactly 1 again - not a hair under (snapped once within a 32-bit float\'s step of it)', [back.length > 1000, back.every((v) => v === 1)], [true, true])
}

console.log('\n...and bit for bit again once it is back up')
{
  const { now, was, at } = clicked({ seconds: 2.5 })
  let same = true
  for (let i = at + Math.round(1.2 * SR); i < now.out[0].length; i++) if (now.out[0][i] !== was.out[0][i - D] || now.out[1][i] !== was.out[1][i - D]) same = false
  check('after the release, every sample exactly the voice as it was (the gain snapped to 1 once within a 32-bit float\'s step of it)', same, true)
}

console.log('\none gain for both channels: a peak in one turns both down alike - the stereo image holds')
{
  const right = fill(SR * 4, (i) => 0.3 * Math.sin((2 * Math.PI * 4000 * i) / SR + 1))
  const { at, gain } = clicked({ channels: 2, right })
  const pairs = []
  for (let i = at - D + 10; i < at + 400; i += 7) if (gain(0, i) !== null && gain(1, i) !== null) pairs.push(Math.abs(gain(0, i) - gain(1, i)))
  check('the click only in the left: the right turned down by the very same gain, sample for sample', [pairs.length > 20, Math.max(...pairs) < 1e-6, gain(1, at) < 0.6], [true, true, true])
}

console.log('\na steady low tone over the ceiling: turned down, not shaped - from about 20 Hz up')
{
  //? 25 Hz - a slowed record's bass - 1 dB over the ceiling: the hold (20 ms) outlasts half its cycle, so the
  //? gain holds still through it; clipped at full scale, or limited with no hold, it is shaped every cycle
  const thd = (y, hz, sr) => {
    const n = sr, from = y.length - n
    const a = [0.35875, 0.48829, 0.14128, 0.01168]
    const amp = (f) => { let re = 0, im = 0; for (let i = 0; i < n; i++) { const t = i / n; const w = a[0] - a[1] * Math.cos(2 * Math.PI * t) + a[2] * Math.cos(4 * Math.PI * t) - a[3] * Math.cos(6 * Math.PI * t); re += y[from + i] * w * Math.cos((2 * Math.PI * f * i) / sr); im += y[from + i] * w * Math.sin((2 * Math.PI * f * i) / sr) } return Math.hypot(re, im) }
    const f1 = amp(hz)
    let h = 0
    for (let k = 2; k <= 20; k++) h += amp(k * hz) ** 2
    return 10 * Math.log10(h / (f1 * f1) + 1e-30)
  }
  const sr = 44100
  const results = []
  for (const hz of [25, 50, 120]) {
    const level = (CEILING * Math.pow(10, 1 / 20)) / (hz === 25 ? 0.93 : 0.98)
    const data = fill(sr * 5, (i) => level * Math.sin((2 * Math.PI * hz * i) / sr))
    const script = (time) => (time === 0 ? [window([data], sr), { type: 'take', at: 1, rate: 1, time: 0, until: 100 }] : [])
    const limited = run(voice, { seconds: 3, sr, block: 1024, script }).out[0]
    const clipped = run(before, { seconds: 3, sr, block: 1024, script }).out[0].map((v) => Math.max(-1, Math.min(1, v)))
    results.push([hz, peakOf([limited]) <= CEILING, thd(limited, hz, sr) < -90, thd(clipped, hz, sr) > -50])
  }
  check('25, 50 and 120 Hz, 1 dB over the ceiling: under it, with harmonics more than 90 dB down - where clipping the same tone at full scale leaves them within 50 dB',
    results, [[25, true, true, true], [50, true, true, true], [120, true, true, true]])
  //? below about 20 Hz - a slowed record's deepest bass, a 40-60 Hz note at 0.2-0.3x - half a cycle outlasts
  //? the lookahead and the hold (21.5 ms together), so the gain moves with each crest: the tone IS shaped,
  //? a little (review of 2.0.0-player.35). Pinned as measured, 0.45 dB over the ceiling (a tone the voice as
  //? it was played under full scale): harmonics -42.8 dB at 8 Hz (the 3rd -44.5), -45.6 at 10, -48.5 at
  //? 12, -54 at 15, -59.5 at 17 - odd harmonics (a gain moving at twice the tone), mostly at 24-85 Hz
  const low = []
  for (const [hz, bound] of [[8, -40], [10, -43], [12, -46], [15, -51], [17, -57]]) {
    const unit = fill(sr * 5, (i) => Math.sin((2 * Math.PI * hz * i) / sr))
    const script = (data) => (time) => (time === 0 ? [window([data], sr), { type: 'take', at: 1, rate: 1, time: 0, until: 100 }] : [])
    //? the DC blocker turns a tone this low down: the level that makes the voice as it was peak 0.45 dB over
    const plain = run(before, { seconds: 3, sr, block: 1024, script: script(unit) }).out[0]
    const level = (CEILING * Math.pow(10, 0.45 / 20)) / peakOf([plain.slice(plain.length - sr)])
    const data = unit.map((v) => v * level)
    const was = run(before, { seconds: 3, sr, block: 1024, script: script(data) }).out[0]
    const limited = run(voice, { seconds: 3, sr, block: 1024, script: script(data) }).out[0]
    const measured = thd(limited, hz, sr)
    low.push([hz, peakOf([limited]) <= CEILING, thd(was, hz, sr) < -100, round(measured, 1), measured < bound])
  }
  check('8, 10, 12, 15 and 17 Hz, 0.45 dB over the ceiling: under it, the voice as it was clean there (harmonics under -100 dB) - and the limited tone\'s harmonics as measured, each under its bound (-40, -43, -46, -51, -57 dB)',
    low.map((row) => [row[0], row[1], row[2], row[4]]), [[8, true, true, true], [10, true, true, true], [12, true, true, true], [15, true, true, true], [17, true, true, true]])
  console.log(`    (measured: ${low.map((row) => `${row[0]} Hz ${row[3]} dB`).join(', ')})`)
}

/* ===== what it says ===== */

console.log('\nwhat it says: each report, what its limiter did since the last')
{
  //? clicks of 1.5 every 0.1 s on a quiet tone, a few of them doublets, as heard by the reports
  const n = SR * 4
  const data = fill(n, (i) => 0.2 * Math.sin((2 * Math.PI * 300 * i) / SR))
  const marks = []
  for (let k = 0; k < 20; k++) {
    const i = Math.round((1.2 + k * 0.1) * SR)
    data[i] = 1.5
    if (k % 5 === 0) data[i + 1] = -1.5
    marks.push(i)
  }
  const script = (time) => (time === 0 ? [window([data, data], SR), { type: 'take', at: 1.12, rate: 1, time: 0, until: 100 }] : [])
  for (const host of ['functions', 'worklet']) {
    const { reports } = run(voice, { seconds: 3.4, sr: SR, block: host === 'worklet' ? 128 : 1024, host, script })
    const was = run(before, { seconds: 3.4, sr: SR, block: 1024, script, float64: true }).out
    //? what the voice as it was put over the ceiling: samples, and runs of them - what the limiter brought down
    let held = 0, runs = 0, over = false
    for (let i = 0; i < was[0].length; i++) {
      const loudest = Math.max(Math.abs(was[0][i]), Math.abs(was[1][i]))
      if (loudest > CEILING) { held++; if (!over) runs++; over = true } else over = false
    }
    const total = reports.reduce((sum, r) => sum + r.held, 0)
    const peaks = reports.reduce((sum, r) => sum + r.peaks, 0)
    const lowest = Math.min(...reports.map((r) => r.lowest))
    check(`${host === 'worklet' ? 'the worklet\'s module, 128 a block' : 'the functions, 1024 a block'}: its reports add up to every sample the voice as it was put over the ceiling (${held}), in as many runs (${runs}); the lowest gain under what the loudest needed`,
      [total, peaks, lowest < 1, lowest <= CEILING / 1.4], [held, runs, true, true])
    check('...counted afresh after each report: most say nothing (and no runs), and the last, the gain long back up, a lowest of exactly 1',
      [reports.filter((r) => r.held === 0).length > reports.length / 2, reports.filter((r) => r.held === 0).every((r) => r.peaks === 0), reports.at(-1).lowest], [true, true, 1])
  }
}

/* ===== self-contained ===== */

console.log('\nself-contained: the worklet made from the functions\' own text plays loud material exactly as they do')
{
  const channels = loud(48000, 2)['full-scale noise']
  const script = (time) => (time === 0 ? [window([channels[0], channels[0].map((v) => -0.8 * v)], 48000), { type: 'take', at: 0.3, rate: 0.7, time: 0, until: 100 }]
    : time > 0.2 && time < 0.21 ? [{ type: 'drive', at: 0.45, rate: -1.8, time, until: time + 1 }] : [])
  const a = run(voice, { seconds: 0.5, sr: 48000, block: 128, host: 'worklet', script })
  const b = run(voice, { seconds: 0.5, sr: 48000, block: 128, host: 'functions', script })
  check('full-scale noise, limited all the way: the module\'s samples are the functions\' samples, and its reports theirs',
    [a.out.every((data, c) => data.every((v, i) => v === b.out[c][i])), JSON.stringify(a.reports) === JSON.stringify(b.reports), peakOf(a.out) <= CEILING, a.reports.some((r) => r.held > 0)], [true, true, true, true])
  check('the four functions name nothing outside themselves - VOICE_CEILING and VOICE_LOOKAHEAD_S included',
    [voice.newVoiceState, voice.voiceCommand, voice.renderVoice, voice.voiceReport].map((fn) => /\b(exports|require|VOICE_CEILING|VOICE_LOOKAHEAD_S|HAND_DELAY_S|REPORTS_PER_SECOND)\b/.test(fn.toString())), [false, false, false, false])
  const state = voice.newVoiceState()
  check('its rings are made in newVoiceState, sized for 192 kHz: the lookahead (288 samples there) and the lookahead and hold together (4128)',
    [state.limitRing >= lookaheadAt(192000) + 2, state.limitMinRing >= lookaheadAt(192000) + Math.round(0.02 * 192000) + 2, (state.limitRing & (state.limitRing - 1)) === 0, (state.limitMinRing & (state.limitMinRing - 1)) === 0],
    [true, true, true, true])
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
