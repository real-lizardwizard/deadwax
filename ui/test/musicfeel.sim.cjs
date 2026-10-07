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
 * knows which it is; musicFeel reads only the spectrum (since 2.0.0-player.34 not the waveform: its
 * crest factor told calm music from heavy not at all).
 *
 * And the TUNING, held to numbers from real music (2.0.0-player.34; James: "the feel seems to always say
 * 'in between'"): tests/fixtures/feel/real-tracks.json has, for 27 real tracks and 31 louder or quieter
 * copies of 16 of them, the readings musicFeel holds once a second (taken through the page's own pipeline
 * offline - numbers, never audio) and the share of time the full run spent in each word. This replays
 * the readings through feelScore and feelWords as they are now, and holds the answer to the pinned one
 * and to what the music is: calm tracks smooth, heavy ones aggressive, music between them between,
 * songs that build moving across, a level change hardly moving anything.
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
 *    only once it is more than 0.35 sure;
 *  - the onsets counted on a grid of 60 a second: the same music read at 60, 120 and 144 frames a second
 *    (a high-refresh screen) counts the same onsets and says the same word - checked on a made-up calm
 *    piece put through the analyser as the page sets it up (counted per frame, as before review, a
 *    120 Hz screen counted half as many again); read 30 times a second (a battery saver halving the
 *    frame rate) the same piece sees fewer, as the guide says; and how the onsets are counted pinned
 *    exactly, on the board's songs and a busy click, since the real tracks' numbers were taken with it;
 *  - `aggr` following its target over AGGR_FOLLOW_S;
 *  - the share above 2 kHz and the noisiness read in a window below the loudest band, so a record
 *    mastered louder or quieter reads the same - a spectrum falling away to the analyser's floor
 *    included, whose quietest bands cross the floor as the level moves (read against the floor, as
 *    before review, those bands moved both readings) - and continuous at the floor;
 *  - the real tracks, replayed: each as the full run read it (to 3 points in each word), calm ones
 *    smooth, heavy ones aggressive, music between them in between, the two that build moving across,
 *    a level change hardly moving anything, and the five kept out of the tuning as they read.
 *
 * Run it with:  node ui/test/musicfeel.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-musicfeel-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/musicFeel.ts', 'src/lib/visualizer.ts', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const { musicFeel, newFeel, feelWords, feelScore, smooth, FEEL_SCORE, LIFT_FLOOR, LEVEL_WINDOW, AGGR_FOLLOW_S } = require(path.join(OUT, 'musicFeel.js'))
const V = require(path.join(OUT, 'visualizer.js'))

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
    musicFeel(F, raw, dt)
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
//? (it reads aggressive right through the fall-back's 115-125 s - the board's metal is far heavier than any
//? real track, and the tuning on real music holds aggr at 1 for it - and falls once the heavy part has gone)
const falling = [126, 128, 130, 132, 134].every((t) => along[t + 2] < along[t])
check('...rising through the build (58-68 s) and falling once it has fallen back (126-136 s), second by second',
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

console.log('\nhow the onsets are counted (the real tracks\' numbers were taken with it: held exactly)')
{
  //? onsets a second carry 30% of the score, and FEEL_SCORE's range for them was fitted to the real
  //? tracks' readings - so how they are counted (the threshold, the window, the grid) is pinned to the
  //? number, on the board's two songs and a busy click whose count sits inside that range
  const eighths = run(newFeel(), (mt, r, w) => eighthsSignal(170, 1.5, mt, r, w), 30)
  check('onsets a second: the aggressive song 11.459, the smooth one 1.051, 8th notes at 170 bpm 5.680',
    [round(metal.density, 3), round(smoothSong.density, 3), round(eighths.density, 3)], [11.459, 1.051, 5.68])
}

console.log('\naggr follows its target over AGGR_FOLLOW_S')
{
  //? one frame of a steady sound from a fresh feel: aggr moves toward the score by exactly the share of the
  //? way AGGR_FOLLOW_S says - the same follow the real tracks' replay below uses, and the full runs used
  const F = newFeel(), before = F.aggr, dt = 1 / 60
  musicFeel(F, new Float32Array(64).fill(0.5), dt)
  check('a frame moves aggr by (score - aggr) x (1 - e^(-dt / AGGR_FOLLOW_S)), AGGR_FOLLOW_S 2 s',
    [AGGR_FOLLOW_S, round(F.aggr, 9)], [2, round(before + (feelScore(F) - before) * (1 - Math.exp(-dt / AGGR_FOLLOW_S)), 9)])
}

console.log('\nthe onsets counted on a grid of 60 a second, whatever the screen\'s frame rate')
{
  //? a made-up calm piece - soft notes at uneven times, a few a second, ringing on over a quiet hum and a
  //? breath of noise - put through the analyser exactly as the page sets it up (FFT 2048, a Blackman
  //? window, no smoothing, -90..-22 dB to bytes, then bandLayout and bandsFromBins), read at 60, 120 and
  //? 144 frames a second: a 120 Hz screen reads the analyser twice as often, and counting onsets per frame
  //? (as before review) counted half as many again on this piece, and it read in between
  const SR = 48000, N = V.FFT_SIZE, seconds = 30
  let seed = 3
  const rnd = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296 }
  const notes = []
  for (let t = 0.2; t < seconds; t += 0.25 + 0.6 * rnd()) notes.push([t, 220 * Math.pow(2, Math.floor(rnd() * 12) / 12), 0.3 + 0.4 * rnd()])
  const x = new Float32Array(seconds * SR)
  for (let n = 0; n < x.length; n++) {
    const t = n / SR
    let y = 0.05 * Math.sin(2 * Math.PI * 110 * t) * (1 + 0.5 * Math.sin(t * 0.4)) + 0.004 * (rnd() * 2 - 1)
    for (const [t0, f, a] of notes) {
      const d = t - t0
      if (d < 0 || d > 3) continue
      y += a * Math.exp(-d / 0.9) * (1 - Math.exp(-d / 0.004)) * (Math.sin(2 * Math.PI * f * d) + 0.4 * Math.sin(4 * Math.PI * f * d) + 0.2 * Math.sin(6 * Math.PI * f * d))
    }
    x[n] = y * 0.25
  }
  const win = Float64Array.from({ length: N }, (_, n) => 0.42 - 0.5 * Math.cos(2 * Math.PI * n / N) + 0.08 * Math.cos(4 * Math.PI * n / N))
  const cosT = Float64Array.from({ length: N / 2 }, (_, k) => Math.cos(-2 * Math.PI * k / N)), sinT = Float64Array.from({ length: N / 2 }, (_, k) => Math.sin(-2 * Math.PI * k / N))
  const re = new Float64Array(N), im = new Float64Array(N), bins = new Uint8Array(N / 2), layout = V.bandLayout(N, SR), scale = 255 / (V.MAX_DB - V.MIN_DB)
  const bandsAt = (end, out) => {
    for (let n = 0; n < N; n++) { re[n] = x[end - N + n] * win[n]; im[n] = 0 }
    for (let i = 0, j = 0; i < N; i++) {
      if (j > i) { let t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t }
      let m = N >> 1
      while (m >= 1 && (j & m)) { j ^= m; m >>= 1 }
      j |= m
    }
    for (let size = 2; size <= N; size *= 2) {
      const h = size / 2, st = N / size
      for (let s0 = 0; s0 < N; s0 += size) for (let k = 0; k < h; k++) {
        const c = cosT[k * st], sn = sinT[k * st], a = s0 + k, b = a + h
        const xr = re[b] * c - im[b] * sn, xi = re[b] * sn + im[b] * c
        re[b] = re[a] - xr; im[b] = im[a] - xi; re[a] += xr; im[a] += xi
      }
    }
    for (let k = 0; k < N / 2; k++) bins[k] = Math.max(0, Math.min(255, Math.floor(scale * (20 * Math.log10(Math.hypot(re[k], im[k]) / N || 1e-30) - V.MIN_DB))))
    V.bandsFromBins(bins, layout, out)
  }
  const at = (fps) => {
    const F = newFeel(), out = new Float32Array(64)
    for (let f = 0; f < Math.floor((x.length - N) / (SR / fps)); f++) { bandsAt(N + Math.round(f * SR / fps), out); musicFeel(F, out, 1 / fps) }
    return F
  }
  const rates = [60, 120, 144].map(at)
  console.log(`    (the calm piece: ${rates.map((F, i) => `${[60, 120, 144][i]} fps ${round(F.density, 2)} onsets a second, aggr ${round(F.aggr, 2)}`).join('; ')})`)
  check('the same calm piece at 60, 120 and 144 frames a second: onsets a second within 0.4 of each other (per frame it was 1.4 and 2.2 more), and it reads smooth at all three',
    [Math.max(...rates.map((F) => F.density)) - Math.min(...rates.map((F) => F.density)) < 0.4, rates.map((F) => feelWords(F).split(' · ')[0])], [true, ['smooth', 'smooth', 'smooth']])
  //? and held to the number, like the songs above: this piece's onsets sit near the threshold, so it is
  //? where the threshold's own terms (and how fast it follows the music on the grid) show
  check('...its onsets a second, held: 2.78, 2.97 and 2.88', rates.map((F) => round(F.density, 2)), [2.78, 2.97, 2.88])
  //? and BELOW 60 the grid can't help: the analyser is read only 30 times a second (a battery saver can
  //? halve a page's frame rate), and an onset between two reads is lost in their flux - on real music a
  //? third of them on most tracks, and heavy music reads in between. The guide says so; a compensation for
  //? it changes this check, and the guide's words with it
  const slow = at(30)
  console.log(`    (at 30 fps: ${round(slow.density, 2)} onsets a second)`)
  check('...but read 30 times a second it sees fewer: under 85% of what 60 sees (2.07 a second, held)',
    [slow.density < 0.85 * rates[0].density, round(slow.density, 2)], [true, 2.07])
}

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
  musicFeel(F, raw, 1 / 60)
  check('it keeps the last spectrum, for the next frame\'s flux', Array.from(F.prev.slice(0, 3)), [0.5, 0.5, 0.5])
  check('...and counts only music as time heard', round(F.clock, 4), round(1 / 60, 4))
  //? a frame two samples of the grid late (a screen dropping to 30) spreads its flux over the two: each
  //? sample of the onset envelope takes half of every band's rise, 0.1 x 64 bands
  musicFeel(F, new Float32Array(64).fill(0.6), 2 / 60)
  const n = F.env.length
  check('a frame two grid samples late gives the envelope two samples, each half its flux',
    [round(F.env[(F.envAt - 1 + n) % n], 4), round(F.env[(F.envAt - 2 + n) % n], 4), F.envAt], [3.2, 3.2, 3])
}

console.log('\nbrightness and noisiness read in a window below the loudest band: how loud a record is mastered moves neither')
{
  //? a made-up spectrum in the analyser's own scale (a band's value is its level in dB, -90 at 0, -22 at
  //? 1), falling away toward the highs, its loudest band at -30 dB; then the same 8 dB louder (8 dB is 8/68
  //? of the scale) and 10 dB quieter - neither pushing a band past the top of the scale, nor the loudest
  //? band under the 0.73 (about -40 dB) the window needs to stay clear of the floor
  const at = (i) => (i === 50 || i === 51 ? 0 : 0.845 - i * 0.007 + 0.04 * Math.sin(i * 1.7))
  const feelOf = (spectrum) => {
    const F = newFeel()
    for (let f = 0; f < 1800; f++) musicFeel(F, spectrum, 1 / 60)
    return F
  }
  const shifted = (shift) => Float32Array.from({ length: 64 }, (_, i) => (at(i) > 0 ? Math.min(1, Math.max(0, at(i) + shift)) : 0))
  const flat0 = feelOf(shifted(0)), loud = feelOf(shifted(8 / 68)), quiet = feelOf(shifted(-10 / 68))
  //? how the two readings are made is what the real tracks' numbers were taken with: held here
  check('...and they read it as the tuning was measured with (the share above band 43, the flatness of bands 20-63, in a window 0.7 deep)',
    [LEVEL_WINDOW, Math.round(flat0.high * 1000) / 1000, Math.round(flat0.flat * 1000) / 1000], [0.7, 0.124, 0.645])
  check('the share above 2 kHz and the noisiness: the same 8 dB louder and 10 dB quieter',
    [Math.abs(loud.high - flat0.high) < 0.002, Math.abs(quiet.high - flat0.high) < 0.002, Math.abs(loud.flat - flat0.flat) < 0.002, Math.abs(quiet.flat - flat0.flat) < 0.002], [true, true, true, true])
  //? the case the review found: a calm spectrum falling away INTO the analyser's floor, so that as the record
  //? is turned up or down its quietest bands cross the floor. Read against the floor (as before review)
  //? the bands crossing it moved both readings - a calm record turned up 3 dB began to read in between;
  //? read in a window below the loudest band, they are under the window's bottom whichever side of the
  //? floor they are
  const falling = (shift) => Float32Array.from({ length: 64 }, (_, i) => Math.min(1, Math.max(0, 0.85 - i * 0.014 + 0.02 * Math.sin(i * 1.3) + shift)))
  const base = feelOf(falling(0))
  const moved = [6, 3, -3].map((db) => feelOf(falling(db / 68)))
  console.log(`    (a spectrum falling into the floor: high ${round(base.high, 4)}, flat ${round(base.flat, 4)}; bands at the floor ${falling(0).filter((v) => v === 0).length}, 6 dB louder ${falling(6 / 68).filter((v) => v === 0).length}, 3 dB quieter ${falling(-3 / 68).filter((v) => v === 0).length})`)
  check('...a spectrum falling away into the floor reads the same 6 and 3 dB louder and 3 dB quieter, though bands cross the floor',
    moved.map((F) => [Math.abs(F.high - base.high) < 0.002, Math.abs(F.flat - base.flat) < 0.002]), [[true, true], [true, true], [true, true]])
  //? continuous at the floor: a band at it counts nothing, one just above it next to nothing - a quiet
  //? song's empty highs stay empty, never made into hiss, and nothing jumps as a band crosses the floor
  const empty = feelOf(Float32Array.from({ length: 64 }, (_, i) => (i < 30 ? 0.5 - i * 0.01 : LIFT_FLOOR * 0.9)))
  const above = feelOf(Float32Array.from({ length: 64 }, (_, i) => (i < 30 ? 0.5 - i * 0.01 : LIFT_FLOOR * 1.1)))
  check('a band at the analyser\'s floor counts nothing, and one just above it next to nothing: no jump as a band crosses the floor',
    [empty.high < 0.001, Math.abs(above.high - empty.high) < 0.001, Math.abs(above.flat - empty.flat) < 0.01], [true, true, true])
}

console.log('\nreal music: the tuning held to numbers from real tracks (tests/fixtures/feel/real-tracks.json)')
{
  const fixture = JSON.parse(fs.readFileSync(path.join(UI, '../tests/fixtures/feel/real-tracks.json'), 'utf8'))
  check('the fixture\'s shares were made under this tuning (retuning means making the fixture again)', fixture.tuning, { FEEL_SCORE, LIFT_FLOOR, LEVEL_WINDOW, AGGR_FOLLOW_S })
  const q = (a, p) => { const sorted = a.slice().sort((x, y) => x - y); return sorted[Math.floor(p * (sorted.length - 1))] }
  /** The readings replayed once a second through feelScore, aggr followed over AGGR_FOLLOW_S as musicFeel
   *  follows it, and the words read off it after the first 10 s: the share of time in each, and aggr's
   *  5/50/95%. */
  const replay = (track) => {
    let aggr = newFeel().aggr
    const words = [0, 0, 0], seen = []
    track.readings.density.forEach((density, i) => {
      const score = feelScore({ density: density / 100, high: track.readings.high[i] / 1000, flat: track.readings.flat[i] / 1000 })
      aggr += (score - aggr) * (1 - Math.exp(-1 / AGGR_FOLLOW_S))
      if (i + 1 <= 10) return
      seen.push(aggr)
      const word = feelWords({ ...newFeel(), aggr, conf: 0 }).split(' · ')[0]
      words[word === 'smooth' ? 0 : word === 'aggressive' ? 2 : 1] += 1
    })
    return { words: words.map((n) => Math.round((100 * n) / seen.length)), aggr: [q(seen, 0.05), q(seen, 0.5), q(seen, 0.95)] }
  }
  const all = fixture.tracks.map((track) => ({ track, name: `${track.title}${track.gainDb ? ` ${track.gainDb > 0 ? '+' : ''}${track.gainDb} dB` : ''}`, ...replay(track) }))
  check(`all ${all.length} tracks read as the full run read them, to 3 points in every word`,
    all.filter((x) => x.words.some((v, i) => Math.abs(v - x.track.full.words[i]) > 3)).map((x) => [x.name, x.words, x.track.full.words]), [])
  const plain = all.filter((x) => !x.track.gainDb)
  const show = (sel) => sel.map((x) => `${x.track.title} ${x.words.join('/')}`).join(', ')
  const mean = (a) => a.reduce((t, v) => t + v, 0) / a.length
  const of = (kind, heldOut) => plain.filter((x) => x.track.kind === kind && x.track.heldOut === heldOut)
  for (const kind of ['calm', 'between', 'heavy', 'builds']) for (const heldOut of [false, true]) {
    const sel = of(kind, heldOut)
    if (sel.length) console.log(`    (${kind}${heldOut ? ', held out of the tuning' : ''} - smooth/in between/aggressive %: ${show(sel)})`)
  }
  const before = (kind, word) => Math.round(mean(of(kind, false).map((x) => x.track.before.words[word])))
  console.log(`    (the tuning before: calm ${before('calm', 0)}% smooth, between ${before('between', 1)}% in between, heavy ${before('heavy', 2)}% aggressive)`)
  check('every calm track, held out, louder or not, reads smooth at least 85% of the time',
    all.filter((x) => x.track.kind === 'calm' && x.words[0] < 85).map((x) => x.name), [])
  const heavy = of('heavy', false)
  check('the heavy tracks read aggressive - each at least half the time, 85% on average',
    [heavy.filter((x) => x.words[2] < 50).map((x) => x.track.title), mean(heavy.map((x) => x.words[2])) >= 85], [[], true])
  const between = of('between', false)
  check('music between them reads in between - 60% of the time on average, aggressive under a fifth of it',
    [mean(between.map((x) => x.words[1])) >= 60, mean(between.map((x) => x.words[2])) <= 20], [true, true])
  check('a song that builds moves across: a fair share of its time in two words or more, and aggr ranging at least 0.25',
    of('builds', false).map((x) => [x.words.filter((v) => v >= 15).length >= 2, x.aggr[2] - x.aggr[0] >= 0.25]), [[true, true], [true, true]])
  const shifts = all.filter((x) => x.track.gainDb).map((x) => Math.abs(x.aggr[1] - all.find((y) => y.track.title === x.track.title && !y.track.gainDb).aggr[1]))
  console.log(`    (a level change moved a track's middle aggr ${round(mean(shifts), 3)} on average, ${round(Math.max(...shifts), 3)} at most)`)
  check('a track made 3 to 10 dB louder or quieter hardly moves - the four that stand near the floor too, 3 and 6 dB either way: its middle aggr within 0.12, 0.04 on average',
    [Math.max(...shifts) <= 0.12, mean(shifts) <= 0.04, ['Dreamer', 'Chill Wave', 'Late Night Radio', 'Bummin on Tremelo'].every((t) => [-6, -3, 3, 6].every((g) => all.some((x) => x.track.title === t && x.track.gainDb === g)))], [true, true, true])
  //? held out of the tuning: what they read is reported (above), and held only in the direction that matters -
  //? a calm track smooth, a heavy one never mostly smooth, the relaxed groove never mostly aggressive. The two
  //? heavy tracks kept out read mostly in between (Breakdown has little top end; Cool Rock sparse onsets,
  //? its top end at the low edge of heavy music's), and are held only to never reading mostly smooth: a
  //? tuning that read them aggressive passes here, as it should (they are heavy music)
  const held = Object.fromEntries(plain.filter((x) => x.track.heldOut).map((x) => [x.track.title, x.words]))
  check('held out: the two calm tracks smooth; the two heavy ones never mostly smooth; the relaxed groove never mostly aggressive',
    [held['Summer Day'][0] >= 85, held['Ether Vox'][0] >= 85, held['Breakdown'][0] < 50, held['Cool Rock'][0] < 50, held['Chill Wave'][2] < 20], [true, true, true, true, true])
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
