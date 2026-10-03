/**
 * The music's feel (2.0.0-player.20) - lib/musicFeel.ts, the desktop visualizer's port of the canvas
 * board DesktopVisualizer.dc.html's musicFeel(), driven with the board's OWN synthetic songs.
 *
 * The board's "Mock signal" is not shipped (the real visualizer analyses a silent copy of the song,
 * player/vizAudio.ts); it lives on here, as the fixture: the board's analyse() taken across, making a
 * 64-band spectrum and a waveform each frame exactly as the board fed its own musicFeel - a slow,
 * smooth song (about 63 bpm: pads, a slow bass line, a soft kick, a gliding lead), an aggressive one
 * (about 180 bpm: double-kick 16ths, a snare on 2 and 4, distorted guitars and cymbals), and one that
 * builds from the first into the second around 60 s and falls back around 120 s. Only the signal
 * knows which it is; musicFeel reads only the spectrum and the waveform.
 *
 * What it pins:
 *  - the smooth song reads smooth (aggr low), the aggressive one aggressive (high), the one that
 *    builds rises past the middle once it has built, and falls back after;
 *  - the tempo: the aggressive song at its 180 (its fast pulse, not half-time 90), the smooth one at its
 *    63, and a plain click track at 120, 90 and 150 bpm read within a few bpm; the Mandala's `beats`
 *    halved or doubled into 0.9-2.2 a second; `tempo` within 0.65-1.5;
 *  - silence - and a pause, which is silence to the analyser - holds EVERYTHING: the feel, the tempo
 *    and how sure it is, exactly as they were;
 *  - while it is unsure of the tempo, the neutral pace the board keeps: 110 bpm, so `beats` settles at
 *    110/60 and `tempo` at 110/115;
 *  - the words under the style list, at their edges: smooth under 0.34, aggressive from 0.67, the bpm
 *    only once it is more than 0.35 sure.
 *
 * Run it with:  node ui/test/musicfeel.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-musicfeel-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/musicFeel.ts', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const { musicFeel, newFeel, feelWords, smooth } = require(path.join(OUT, 'musicFeel.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/* ===== the board's synthetic songs (its analyse(), taken across as a fixture) ===== */

const hash = (x) => {
  const s = Math.sin(x * 12.9898) * 43758.5453
  return s - Math.floor(s)
}

/**
 * The board's signal for one frame of `mode` at music time `mt`: the raw 64-band spectrum (0-1) and
 * the 384-point waveform, at sensitivity 1 and the music playing (level 1).
 */
function boardSignal(mode, mt, raw, wave) {
  const x = mt % 180
  const heavy = mode === 'aggressive' ? 1 : mode === 'smooth' ? 0 : smooth(55, 65, x) * (1 - smooth(115, 125, x))
  const amp = 1
  const g = (i, c, w) => { const d = (i - c) / w; return Math.exp(-0.5 * d * d) }
  const N = wave.length, W = 0.028
  const e = new Float32Array(64), wv = new Float32Array(N)
  if (heavy < 1) {
    const w = 1 - heavy
    const beat = 60 / 63
    const bp = mt % beat
    const kick = Math.exp(-bp / 0.16) * 0.55
    const bar = Math.floor(mt / (beat * 4))
    const note = [0, 5, 3, 7][bar % 4]
    const since = mt - bar * beat * 4
    const bassAmp = (1 - Math.exp(-since / 0.5)) * (0.62 + 0.18 * Math.sin(mt * 0.37))
    const bassBand = 8 + note * 0.59
    const pad = 0.55 + 0.25 * Math.sin(mt * 0.43) + 0.2 * Math.sin(mt * 0.17 + 1)
    const leadBand = 31 + 2.5 * Math.sin(mt * 0.21) + 0.25 * Math.sin(mt * 31)
    const lead = 0.3 + 0.15 * Math.sin(mt * 0.13 + 2)
    const pb = note * 0.59
    for (let i = 0; i < 64; i++) {
      const n1 = hash(mt * 997.13 + i * 7.31)
      let v = kick * g(i, 3.2, 2.4)
      v += bassAmp * (0.9 * g(i, bassBand, 2.0) + 0.35 * g(i, bassBand + 7.1, 2.0))
      v += pad * 0.42 * (g(i, 16 + pb, 2.6) + 0.8 * g(i, 20 + pb, 2.6) + 0.65 * g(i, 23.5 + pb, 2.8))
      v += lead * (g(i, leadBand, 1.4) + 0.4 * g(i, leadBand + 7.1, 1.5))
      v += (0.035 + 0.02 * n1) * (1 - i / 70)
      e[i] += v * w
    }
    const fb = 55 * Math.pow(2, note / 12), fl = 15 * Math.pow(2, leadBand / 7.1)
    for (let j = 0; j < N; j++) {
      const tau = j / (N - 1) * W
      let y = kick * 0.7 * Math.sin(2 * Math.PI * (45 + 20 * kick) * tau)
      y += bassAmp * 0.6 * Math.sin(2 * Math.PI * fb * tau + mt * 1.1)
      y += pad * 0.25 * (Math.sin(4 * Math.PI * fb * tau + mt * 0.7) + Math.sin(6 * Math.PI * fb * tau + mt * 0.5))
      y += lead * 0.3 * Math.sin(2 * Math.PI * fl * tau + mt * 0.9)
      y += 0.01 * (hash(mt * 431.9 + j * 1.713) * 2 - 1)
      wv[j] += y * w
    }
  }
  if (heavy > 0) {
    const w = heavy
    const beat = 60 / 180, six = beat / 4
    const bi = Math.floor(mt / beat), bp = mt - bi * beat
    const si = Math.floor(mt / six), sp = mt - si * six
    const kick = Math.exp(-sp / 0.025) * (si % 4 === 0 ? 1 : 0.72)
    const snare = bi % 2 === 1 ? Math.exp(-bp / 0.09) : 0
    const note = [0, 0, 3, 5, 0, 0, 6, 5][bi % 8]
    const root = 12 + note * 0.59
    const chug = 0.55 + 0.45 * Math.exp(-sp / 0.04)
    const ride = Math.exp(-(mt % (beat / 2)) / 0.05)
    for (let i = 0; i < 64; i++) {
      const n1 = hash(mt * 997.13 + i * 7.31)
      const n2 = hash(mt * 613.7 + i * 3.17 + 5.5)
      let v = kick * (1.2 * g(i, 3.5, 2.0) + 0.3 * g(i, 30, 6))
      v += snare * (0.6 * g(i, 22, 4) + 0.55 * smooth(18, 40, i) * (0.6 + 0.8 * n1))
      v += chug * (0.85 * g(i, root, 1.6) + 0.6 * g(i, root + 7.1, 1.6) + (0.55 + 0.4 * n2) * smooth(12, 22, i) * (1 - 0.35 * smooth(50, 64, i)))
      v += (0.3 * (0.6 + 0.8 * n1) + 0.25 * ride) * smooth(38, 56, i)
      e[i] += v * w
    }
    const fr = 82.4 * Math.pow(2, note / 12)
    for (let j = 0; j < N; j++) {
      const tau = j / (N - 1) * W
      const s1 = 2 * ((fr * tau + mt * 0.5) % 1) - 1
      const s2 = 2 * ((fr * 1.5 * tau + mt * 0.37) % 1) - 1
      let y = kick * 0.9 * Math.sin(2 * Math.PI * (50 + 90 * kick) * tau)
      y += chug * 0.55 * Math.tanh(4 * (s1 + 0.7 * s2))
      y += (snare * 0.5 + 0.18) * (hash(mt * 431.9 + j * 1.713) * 2 - 1)
      wv[j] += y * w
    }
  }
  for (let i = 0; i < 64; i++) raw[i] = 1 - Math.exp(-e[i] * 1.5 * amp)
  for (let j = 0; j < N; j++) {
    const k = Math.min(j, N - 1 - j) / (N * 0.08)
    const edge = k >= 1 ? 1 : 0.5 - 0.5 * Math.cos(Math.PI * k)
    wave[j] = Math.tanh(wv[j] * amp * 0.9) * edge
  }
}

/** A busy click track: a tick on every 8th note, the one on the beat `accent` times as loud. */
function eighthsSignal(bpm, accent, mt, raw, wave) {
  const step = 60 / bpm / 2
  const since = mt % step, onBeat = Math.floor(mt / step) % 2 === 0
  const tick = Math.exp(-since / 0.02) * (onBeat ? accent : 1)
  for (let i = 0; i < 64; i++) raw[i] = 0.06 + 0.5 * tick * (1 - i / 120)
  for (let j = 0; j < wave.length; j++) wave[j] = 0.5 * tick * Math.sin(j * 0.9)
}

/** A click track: a short broadband tick every beat over a quiet floor - nothing else. */
function clickSignal(bpm, mt, raw, wave) {
  const beat = 60 / bpm
  const since = mt % beat
  const tick = Math.exp(-since / 0.03)
  for (let i = 0; i < 64; i++) raw[i] = 0.06 + 0.7 * tick * (1 - i / 120)
  for (let j = 0; j < wave.length; j++) wave[j] = 0.8 * tick * Math.sin(j * 0.9) + 0.02 * Math.sin(j * 0.05)
}

const FPS = 60
/** Runs `seconds` of a signal through musicFeel at 60 frames a second; `at` is called each second. */
function run(F, signal, seconds, from = 0, at = () => {}) {
  const raw = new Float32Array(64), wave = new Float32Array(384), dt = 1 / FPS
  for (let f = 0; f < seconds * FPS; f++) {
    const mt = from + f * dt
    signal(mt, raw, wave)
    musicFeel(F, raw, wave, dt)
    if ((f + 1) % FPS === 0) at(Math.round(mt + dt), F)
  }
  return F
}

const round = (x, places = 2) => Math.round(x * 10 ** places) / 10 ** places

console.log('\nthe board\'s three songs: how aggressive each reads')
const smoothSong = run(newFeel(), (mt, r, w) => boardSignal('smooth', mt, r, w), 40)
const metal = run(newFeel(), (mt, r, w) => boardSignal('aggressive', mt, r, w), 40)
console.log(`    (smooth: aggr ${round(smoothSong.aggr)}, ${round(smoothSong.bpm, 1)} bpm, conf ${round(smoothSong.conf)}; aggressive: aggr ${round(metal.aggr)}, ${round(metal.bpm, 1)} bpm, conf ${round(metal.conf)})`)
check('the smooth song (like Comfortably Numb) reads smooth - under a third', smoothSong.aggr < 0.34, true)
check('the aggressive one (like metal) reads aggressive - over two thirds', metal.aggr > 0.67, true)
check('...and the words say so', [feelWords(smoothSong).split(' · ')[0], feelWords(metal).split(' · ')[0]], ['smooth', 'aggressive'])

const builds = newFeel()
const along = {}
run(builds, (mt, r, w) => boardSignal('builds', mt, r, w), 170, 0, (second, F) => { along[second] = F.aggr })
console.log(`    (the song that builds: aggr at ${[50, 60, 70, 80, 90, 115, 120, 125, 130, 135, 140, 150, 160].map((t) => `${t} s ${round(along[t])}`).join(', ')})`)
check('the song that builds: smooth before it builds, aggressive once it has, smooth again after it falls back',
  [along[50] < 0.34, along[90] > 0.67, along[115] > 0.67, along[160] < 0.34], [true, true, true, true])
const rising = [58, 60, 62, 64, 66].every((t) => along[t + 2] > along[t])
const falling = [124, 126, 128, 130, 132].every((t) => along[t + 2] < along[t])
check('...rising through the build (58-68 s) and falling as it falls back (124-134 s), second by second',
  [rising, falling], [true, true])

console.log('\nthe tempo')
check('the aggressive song at its 180 - felt at its fast pulse, never its half-time 90', Math.abs(metal.bpm - 180) <= 4, true)
check('the smooth song at its 63', Math.abs(smoothSong.bpm - 63) <= 3, true)
check('...both read with confidence', [metal.conf > 0.35, smoothSong.conf > 0.35], [true, true])
for (const bpm of [120, 90, 150]) {
  const F = run(newFeel(), (mt, r, w) => clickSignal(bpm, mt, r, w), 30)
  console.log(`    (a click at ${bpm}: read ${round(F.bpm, 1)} bpm, conf ${round(F.conf)}, beats ${round(F.beats)}/s, tempo ${round(F.tempo)})`)
  check(`a click track at ${bpm} bpm is read within 3 bpm`, Math.abs(F.bpm - bpm) <= 3, true)
}
{
  //? the onset envelope is smoothed over about 80 ms before it is autocorrelated, so a busy subdivision
  //? doesn't pull the reading to half-time: unsmoothed, this reads about 92
  const busy = run(newFeel(), (mt, r, w) => eighthsSignal(170, 1.5, mt, r, w), 30)
  console.log(`    (8th notes at 170, the beat accented: read ${round(busy.bpm, 1)} bpm)`)
  check('a busy click - every 8th note at 170 bpm, the beat accented - is read at its 170, not half-time', Math.abs(busy.bpm - 170) <= 3, true)
}
const click150 = run(newFeel(), (mt, r, w) => clickSignal(150, mt, r, w), 30)
const click120 = run(newFeel(), (mt, r, w) => clickSignal(120, mt, r, w), 30)
check('the Mandala\'s beats halved into 0.9-2.2 a second: 180 bpm (3 a second) is 1.5, 150 (2.5) is 1.25; 120 (2) and 63 (1.05) as they are',
  [round(metal.beats, 2), round(click150.beats, 2), round(click120.beats, 2), round(smoothSong.beats, 2)], [1.5, 1.25, 2, 1.05])
check('...and the flowing styles\' tempo factor kept within 0.65-1.5', [metal.tempo, smoothSong.tempo].every((t) => t >= 0.65 && t <= 1.5), true)
check('...metal faster than the smooth song', metal.tempo > smoothSong.tempo, true)
check('before it is sure of anything, a neutral pace: "finding the tempo"', feelWords(newFeel()), 'in between · finding the tempo')
check('...and once it is, the bpm', feelWords(metal), `aggressive · ${Math.round(metal.bpm)} bpm`)

console.log('\nwhile it is unsure: the neutral pace')
{
  //? a steady sound - no onsets, so nothing to find a tempo in: it stays unsure, and the speeds go to
  //? the board's neutral 110 bpm (beats 110/60 a second, tempo 110/115) and stay there
  const F = run(newFeel(), (mt, r, w) => { r.fill(0.5); w.fill(0) }, 20)
  check('20 s of a steady sound: still unsure of the tempo, the bpm untouched', [round(F.conf, 3), F.bpm], [0, 110])
  check('...the Mandala\'s beats settled at 110/60 a second, the flowing styles\' tempo at 110/115',
    [round(F.beats, 3), round(F.tempo, 3)], [round(110 / 60, 3), round(110 / 115, 3)])
}

console.log('\nthe words, at their edges')
{
  const at = (aggr, conf, bpm = 123.4) => feelWords({ ...newFeel(), aggr, conf, bpm })
  check('smooth under 0.34, in between to 0.67, aggressive from there',
    [at(0.33, 0), at(0.35, 0), at(0.66, 0), at(0.68, 0)].map((w) => w.split(' · ')[0]), ['smooth', 'in between', 'in between', 'aggressive'])
  check('...the bpm only once more than 0.35 sure, rounded', [at(0.5, 0.34).split(' · ')[1], at(0.5, 0.36).split(' · ')[1]], ['finding the tempo', '123 bpm'])
}

console.log('\nsilence holds everything')
{
  const F = run(newFeel(), (mt, r, w) => boardSignal('aggressive', mt, r, w), 30)
  const before = { aggr: F.aggr, bpm: F.bpm, conf: F.conf, tempo: F.tempo, beats: F.beats, density: F.density, clock: F.clock }
  run(F, (mt, r, w) => { r.fill(0); w.fill(0) }, 20)
  const after = { aggr: F.aggr, bpm: F.bpm, conf: F.conf, tempo: F.tempo, beats: F.beats, density: F.density, clock: F.clock }
  check('20 s of silence after metal changes nothing - the feel, the tempo, how sure it is, its clock', after, before)
  //? a pause fades the analyser out: below the floor (an average band under 0.03) is silence too
  run(F, (mt, r, w) => { r.fill(0.02); w.fill(0.01) }, 10)
  check('...nor does a pause dying away under the floor', { aggr: F.aggr, bpm: F.bpm, conf: F.conf, tempo: F.tempo, beats: F.beats, density: F.density, clock: F.clock }, before)
  check('...so a stop never reads as smooth', feelWords(F).startsWith('aggressive'), true)
  const smoothAfter = run(newFeel(), (mt, r, w) => boardSignal('smooth', mt, r, w), 30)
  const held = smoothAfter.aggr
  run(smoothAfter, (mt, r, w) => { r.fill(0); w.fill(0) }, 20)
  check('...and a smooth song stays smooth through it, held exactly', smoothAfter.aggr, held)
}

console.log('\nwhat the board fed it is what it reads')
{
  const F = newFeel()
  check('a fresh feel: in between, 110 bpm, unsure, neutral tempo', [F.aggr, F.bpm, F.conf, F.tempo, F.beats], [0.45, 110, 0, 1, 1.83])
  const raw = new Float32Array(64).fill(0.5), wave = new Float32Array(384)
  musicFeel(F, raw, wave, 1 / 60)
  check('it keeps the last spectrum, for the next frame\'s flux', Array.from(F.prev.slice(0, 3)), [0.5, 0.5, 0.5])
  check('...and counts only music as time heard', round(F.clock, 4), round(1 / 60, 4))
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
