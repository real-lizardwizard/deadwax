/**
 * The desktop visualizer's pure parts (2.0.0-player.20) - lib/visualizer.ts, and its three choices
 * kept per device (state/persisted.ts).
 *
 * James: "the style selector shouldn't be random, it should be consistent". So:
 *  - the Ambient styles are a FIXED list in a FIXED order - Mandala, Waves, Liquid, then the Media
 *    Player family: Burst, Ribbons, Smoke, Rings, Embers - and "Rotate all" goes through them in it,
 *    each for 30 s of PLAYING time (a pause doesn't count), always starting on the first, wrapping to
 *    the first after the last, crossfading over 2.6 s and never starting another mid-fade; two runs
 *    give the same sequence. A style picked from the list holds; "Rotate all" carries on from what is
 *    showing, with a fresh 30 s. The list is drawn as the board draws it, the family under a heading.
 *  - the effects are Bars, Scope, Halo and Ambient; V steps forward through them and Shift+V back.
 *  - the choices are kept per device, each validated on read: anything else is the board's opening -
 *    Ambient, from the cover, the Mandala.
 *
 * And the rest of what can be held to an answer: the colours from a cover (in hue order, vivid, a grey
 * cover its own grey, deterministic), the purple, the Mandala's parts; the feedback styles' numbers and
 * the tempo carrying them; the analyser's bins as the board's 64 bands; the waveform's span, taper and
 * gain; the calm idle signal; the signal's shaping (and none of a kick under Reduced Motion); and the
 * canvases' size caps.
 *
 * Run it with:  node ui/test/visualizer.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-visualizer-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/visualizer.ts', 'src/state/persisted.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

//? persisted.ts imports Preact's hooks for components this sim never calls
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), 'exports.useState = () => []\nexports.useCallback = (f) => f\n')

const V = require(path.join(OUT, 'lib/visualizer.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
const round = (x, places = 3) => Math.round(x * 10 ** places) / 10 ** places

console.log('\nthe effects and the styles')
check('four effects, in the board\'s order and words', V.EFFECTS.map((id) => V.EFFECT_NAMES[id]), ['Bars', 'Scope', 'Halo', 'Ambient'])
check('V steps forward through them, wrapping; Shift+V back', [V.cycleEffect('bars', 1), V.cycleEffect('ambient', 1), V.cycleEffect('bars', -1), V.cycleEffect('halo', -1)],
  ['scope', 'bars', 'ambient', 'scope'])
check('the Ambient styles, in their ONE fixed order', V.AMBIENT_STYLES, ['mandala', 'waves', 'liquid', 'burst', 'ribbons', 'smoke', 'rings', 'embers'])
check('...named as the board names them', V.AMBIENT_CHOICES.map((id) => V.STYLE_NAMES[id]), ['Rotate all', 'Mandala', 'Waves', 'Liquid', 'Burst', 'Ribbons', 'Smoke', 'Rings', 'Embers'])
check('the list as the board draws it: Rotate all, the three originals, then the Media Player family under its heading',
  V.STYLE_ROWS.map((row) => (row.kind === 'heading' ? `# ${row.label}` : row.id)),
  ['rotate', 'mandala', 'waves', 'liquid', '# Media Player style', 'burst', 'ribbons', 'smoke', 'rings', 'embers'])
check('the family is drawn by the one feedback shader, a set of numbers each', [V.FEEDBACK_STYLES, Object.keys(V.FEEDBACK).sort()],
  [['burst', 'ribbons', 'smoke', 'rings', 'embers'], ['burst', 'embers', 'ribbons', 'rings', 'smoke']])
check('each style holds 30 s, and fades into the next over 2.6 s', [V.HOLD_MS, V.FADE_MS], [30000, 2600])
check('the next in the order, wrapping to the first after the last', V.AMBIENT_STYLES.map(V.nextStyle),
  ['waves', 'liquid', 'burst', 'ribbons', 'smoke', 'rings', 'embers', 'mandala'])

console.log('\n"Rotate all": the fixed order, always from the first')
/** Plays `seconds` of the rotation at 60 frames a second; the styles it started, and when (s). */
function rotate(A, seconds, playing = true, choice = 'rotate', from = 0) {
  const started = []
  for (let f = 0; f < seconds * 60; f++) {
    const style = V.rotationTick(A, 1000 / 60, playing, choice)
    if (style) started.push([style, Math.round(from + f / 60)])
  }
  return started
}
{
  const A = V.newRotation()
  const run = rotate(A, 8 * 30 + 5)
  check('it starts on the first, then each 30 s of playing the next, in the order, round to the first again',
    run, [['mandala', 0], ['waves', 30], ['liquid', 60], ['burst', 90], ['ribbons', 120], ['smoke', 150], ['rings', 180], ['embers', 210], ['mandala', 240]])
  const again = rotate(V.newRotation(), 8 * 30 + 5)
  check('...and a second run is exactly the same: nothing random', again, run)
}
{
  const A = V.newRotation()
  rotate(A, 10)
  const paused = rotate(A, 60, false, 'rotate', 10)
  check('paused time doesn\'t count: a minute paused starts nothing', paused, [])
  check('...and the hold carries on from where it was as it plays again', rotate(A, 25, true, 'rotate', 70), [['waves', 90]])
}
{
  const A = V.newRotation()
  rotate(A, 31)
  check('the change is a crossfade: the one before still drawn, in the other slot', [A.cur, A.from, A.curSlot], ['waves', 'mandala', 1])
  const B = V.newRotation()
  V.rotationTick(B, 1, true, 'rotate')
  V.startStyle(B, 'waves')
  const mixes = []
  for (let k = 0; k < 4; k++) {
    mixes.push(round(V.fadeMix(B), 2))
    V.rotationTick(B, 650, true, 'rotate')
  }
  check('...eased in over 2.6 s, then the one before let go', [mixes, V.fadeMix(B), B.from], [[0, 0.16, 0.5, 0.84], 1, null])
}
{
  //? a fade that hasn't ended holds the next back, however long the hold says
  const A = V.newRotation()
  V.rotationTick(A, 1, true, 'rotate')
  V.startStyle(A, 'waves')
  A.holdLeft = 0
  check('never another style mid-fade', [V.rotationTick(A, 16, true, 'rotate'), A.cur], [null, 'waves'])
}

console.log('\na style picked from the list')
{
  const A = V.newRotation()
  check('picked before anything shows: it starts on that', rotate(A, 1, true, 'smoke'), [['smoke', 0]])
  check('...and holds - minutes of playing start nothing else', rotate(A, 300, true, 'smoke', 1), [])
  check('picked while another shows: it crossfades to it', [rotate(A, 1, true, 'liquid', 301), A.from], [[['liquid', 301]], 'smoke'])
  V.chooseStyle(A, 'rotate')
  check('"Rotate all" again: carries on from what is showing with a fresh 30 s, then the next in the order',
    [rotate(A, 29, true, 'rotate', 302), rotate(A, 2, true, 'rotate', 331)], [[], [['burst', 332]]])
}

console.log('\nthe choices, kept on this device')
{
  const stored = new Map()
  let refusing = false
  globalThis.localStorage = {
    getItem(key) { if (refusing) throw new Error('SecurityError'); return stored.has(key) ? stored.get(key) : null },
    setItem(key, value) { if (refusing) throw new Error('QuotaExceededError'); stored.set(key, String(value)) },
    removeItem(key) { stored.delete(key) },
  }
  const persisted = require(path.join(OUT, 'state/persisted.js'))
  check('their keys', [persisted.STORAGE_KEYS.playerVizEffect, persisted.STORAGE_KEYS.playerVizColours, persisted.STORAGE_KEYS.playerVizStyle],
    ['deadwax-player-viz-effect', 'deadwax-player-viz-colours', 'deadwax-player-viz-style'])
  check('nothing kept: the board\'s opening - Ambient, from the cover, the Mandala', [persisted.readVizEffect(), persisted.readVizColours(), persisted.readVizStyle()],
    ['ambient', 'cover', 'mandala'])
  persisted.writeVizEffect('halo')
  persisted.writeVizColours('purple')
  persisted.writeVizStyle('rotate')
  check('kept, and read back', [stored.get('deadwax-player-viz-effect'), persisted.readVizEffect(), persisted.readVizColours(), persisted.readVizStyle()],
    ['halo', 'halo', 'purple', 'rotate'])
  //? persisted.ts spells the lists out (it is in the main page's bundle too): held to lib/visualizer.ts's here
  check('every effect, colour and style it offers reads back as itself',
    [V.EFFECTS.every((id) => { persisted.writeVizEffect(id); return persisted.readVizEffect() === id }),
      V.COLOURS.every((id) => { persisted.writeVizColours(id); return persisted.readVizColours() === id }),
      V.AMBIENT_CHOICES.every((id) => { persisted.writeVizStyle(id); return persisted.readVizStyle() === id })], [true, true, true])
  stored.set('deadwax-player-viz-effect', 'Stars')
  stored.set('deadwax-player-viz-colours', 'rainbow')
  stored.set('deadwax-player-viz-style', 'random')
  check('...and anything it doesn\'t offer (stars was dropped: "stars is junk") is the default', [persisted.readVizEffect(), persisted.readVizColours(), persisted.readVizStyle()],
    ['ambient', 'cover', 'mandala'])
  refusing = true
  let threw = false
  try { persisted.writeVizEffect('bars') } catch { threw = true }
  check('storage refused: the defaults, and nothing thrown', [persisted.readVizEffect(), persisted.readVizStyle(), threw], ['ambient', 'mandala', false])
}

console.log('\ncolours')
/** RGBA pixels of solid colours, `count` pixels each. */
const pixels = (...blocks) => {
  const out = []
  for (const [r, g, b, count, a = 255] of blocks) for (let k = 0; k < count; k++) out.push(r, g, b, a)
  return Uint8ClampedArray.from(out)
}
const hueOf = ([r, g, b]) => {
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min
  if (!d) return 0
  let h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4
  h *= 60
  return h < 0 ? h + 360 : h
}
{
  const prism = pixels([232, 65, 60, 100], [245, 146, 47, 90], [247, 217, 66, 80], [76, 176, 80, 70], [59, 143, 217, 60], [139, 92, 246, 50], [10, 10, 10, 400])
  const six = V.coverPalette(prism)
  check('a cover of six colours on black: six, the black left out', six.length, 6)
  check('...in hue order, red through orange, yellow, green and blue to violet', six.map((c) => Math.round(hueOf(c) / 10) * 10), [0, 30, 50, 120, 210, 260])
  check('...each vivid enough to glow on black', six.every((c) => Math.max(...c) >= 199), true)
  check('...and the same picture always gives the same six', JSON.stringify(V.coverPalette(prism)), JSON.stringify(six))
  const red = V.coverPalette(pixels([200, 30, 30, 300], [5, 5, 5, 300]))
  check('one colour: six of it, deep to pale, its hue kept', [red.length, red.every((c) => c[0] >= c[1] && c[0] >= c[2]), red[0][0] < red[5][0] || red[0][1] < red[5][1]], [6, true, true])
  const grey = V.coverPalette(pixels([128, 128, 128, 300], [240, 240, 240, 100], [20, 20, 20, 200]))
  check('a black-and-white cover: its own grey, dark to light - not purple', [grey.every((c) => c[0] === c[1] && c[1] === c[2]), grey[0][0] < grey[5][0]], [true, true])
  check('nothing opaque: no colours (the purple stands in)', V.coverPalette(pixels([255, 0, 0, 50, 0])), null)
  const two = V.coverPalette(pixels([220, 40, 40, 200], [40, 60, 220, 200]))
  check('two colours: six along the gradient through them', [two.length, hueOf(two[0]) !== hueOf(two[5])], [6, true])
}
check('deadwax\'s purple, darkest to lightest, as the board has it', V.PURPLE.map((c) => `#${c.map((n) => n.toString(16).padStart(2, '0')).join('')}`),
  ['#6d28d9', '#8b3cf0', '#a855f7', '#b77af9', '#c084fc', '#dcbcfd'])
check('...and its Mandala parts the board\'s', V.PURPLE_ROLES, { core: [0.97, 0.9, 1.0], body: [0.7, 0.42, 1.0], body2: [0.82, 0.62, 1.0], ring: [0.95, 0.89, 1.0], flare: [0.42, 0.17, 0.85] })
{
  const lut = V.makeLut(V.PURPLE, false), ring = V.makeLut(V.PURPLE, true)
  check('a LUT runs 256 colours from the first to the last; a ring comes back round to the first',
    [lut.length, lut[0], lut[255], ring[255]], [256, [109, 40, 217], [220, 188, 253], [109, 40, 217]])
  check('a colour from it, as CSS', V.lutColour(lut, 0, 0.5), 'rgba(109,40,217,0.500)')
  const roles = V.rolesFrom(V.PURPLE)
  check('a cover\'s Mandala parts: a core near white, the rings paler than the body, every part in range',
    [roles.core.every((v) => v > 0.75), roles.ring[0] > roles.body2[0] - 0.01, Object.values(roles).flat().every((v) => v >= 0 && v <= 1)], [true, true, true])
  check('eighteen floats for the shaders', [V.palFloats(V.PURPLE).length, round(V.palFloats(V.PURPLE)[0])], [18, round(109 / 255)])
}

console.log('\nthe Media Player family\'s numbers')
{
  const s = { t: 10, bass: 0.5, kick: 0.4, energy: 0.3 }
  //? Smoke has every number of the warp and the drift non-zero at this moment, so each one's scaling
  //? shows (Burst's turbulence and its drift x/y are 0, which no factor can change)
  const slow = V.feedbackFrame('smoke', s, 0.65), fast = V.feedbackFrame('smoke', s, 1.5)
  check('(Smoke at this moment: every number of its warp and drift non-zero)', [...slow.warp, ...slow.drift].every((v) => v !== 0), true)
  check('the tempo carries the picture: zoom, turn and swirl per frame scale with it, turbulence does not',
    [round(fast.warp[0] / slow.warp[0], 4), round(fast.warp[1] / slow.warp[1], 4), round(fast.warp[2] / slow.warp[2], 4), fast.warp[3] === slow.warp[3]],
    [round(1.5 / 0.65, 4), round(1.5 / 0.65, 4), round(1.5 / 0.65, 4), true])
  check('...and the drift with it - its x and y - but not where the zoom is centred',
    [round(fast.drift[0] / slow.drift[0], 4), round(fast.drift[1] / slow.drift[1], 4), fast.drift[2] === slow.drift[2], fast.drift[3] === slow.drift[3]],
    [round(1.5 / 0.65, 4), round(1.5 / 0.65, 4), true, true])
  const emberSlow = V.feedbackFrame('embers', s, 0.65), emberFast = V.feedbackFrame('embers', s, 1.5)
  check('...Embers\' turbulence (its whole warp) the same at any tempo', [emberSlow.warp[3] !== 0, emberFast.warp[3] === emberSlow.warp[3]], [true, true])
  check('Rings strikes its circle on a kick; Embers is the spectrum as bars', [V.feedbackFrame('rings', s, 1).ring[3], V.feedbackFrame('embers', s, 1).bars[2]], [1.2, 40])
  check('a style that isn\'t the family\'s has no numbers', V.feedbackFrame('mandala', s, 1), null)
  check('one hue at a time: resting on each, sliding to the next over its last third',
    [round(V.hueStep(0, 10, 0)), round(V.hueStep(5, 10, 0)), round(V.hueStep(10, 10, 0))], [0, 0, round(1 / 6)])
}

console.log('\nthe Mandala, Waves and Liquid move by the clock and the feel')
{
  const M = V.newMandala(151)
  check('the morph starts from the song\'s position', [M.clock, M.shape], [226.5, 226.5])
  const spec = new Float32Array(64).fill(0.4)
  const before = M.clock
  V.mandalaFlow(M, spec, 1.5, 0.5, 1, 1)
  check('the mirrors\' clock counts beats: 1.5 a second for one second', round(M.clock - before), 1.5)
  const paused = V.newMandala(0)
  V.mandalaFlow(paused, spec, 1.5, 0.5, 0, 1)
  check('...a fifth as fast once a pause has died away', round(paused.clock), 0.3)
  const smooth = V.mandalaMorph(V.newMandala(100), 0), metal = V.mandalaMorph(V.newMandala(100), 1)
  check('aggressive music: few sides and sharp, starry; smooth: many sides, round', [metal.src[2] < smooth.src[2], metal.src[3] > smooth.src[3], smooth.form[1] > metal.form[1]], [true, true, true])
  const W = { x: 0 }
  const cam = V.wavesCamera(10, W, 1, 1, 0.3, 0, 1 / 60)
  check('the Waves camera heads where the clock says, and the same clock says the same', JSON.stringify(V.wavesCamera(10, { x: 0 }, 1, 1, 0.3, 0, 1 / 60)), JSON.stringify(cam))
  const L = V.newLiquid()
  V.liquidFlow(L, 5, spec, 0.8, 1, 1)
  check('Liquid travels with the bass, its brightness untouched by it (only its motion moves)', [L.x !== 0 || L.y !== 0, Object.keys(L).includes('bright')], [true, false])
  //? one second's travel: (0.3 + 2.2 x the bass, followed over 0.35 s) x the tempo x 0.14 - in silence
  //? it still drifts; with the bass it goes about six times as far
  const travel = (bass) => {
    const W = V.newLiquid()
    V.liquidFlow(W, 5, spec, bass, 1, 1)
    return round(Math.hypot(W.x, W.y), 4)
  }
  const followed = 0.8 * (1 - Math.exp(-1 / 0.35))
  check('...as far as the bass says: with none, its slow drift; with 0.8, that much further',
    [travel(0), travel(0.8)], [round(0.3 * 0.14, 4), round((0.3 + 2.2 * followed) * 0.14, 4)])
}

console.log('\nthe analyser\'s bins as the board\'s 64 bands')
{
  const layout = V.bandLayout(2048, 48000)
  const binHz = 48000 / 2048
  check('64 bands, 30 Hz to 16 kHz, each starting where the last ended', [layout.length, round(layout[0].lo * binHz, 1), round(layout[63].hi * binHz, 0),
    layout.every((band, i) => i === 0 || Math.abs(band.lo - layout[i - 1].hi) < 1e-9)], [64, 30, 16000, true])
  const bins = new Uint8Array(1024)
  const at1k = Math.round(1000 / binHz)
  bins[at1k] = 255
  const out = new Float32Array(64)
  V.bandsFromBins(bins, layout, out)
  const loud = [...out].map((v, i) => [v, i]).filter(([v]) => v > 0.5).map(([, i]) => i)
  const edge = (b) => 30 * Math.pow(16000 / 30, b / 64)
  check('a tone at 1 kHz lights the band that covers 1 kHz', loud.every((b) => edge(b) <= 1000 * 1.05 && edge(b + 1) >= 1000 * 0.95) && loud.length >= 1, true)
  const low = new Uint8Array(1024)
  low[1] = 200
  low[2] = 100
  V.bandsFromBins(low, layout, out)
  check('the lowest bands, narrower than a bin, read between the bins round them', [out[0] > 0, out[0] <= 200 / 255, round(out[0], 2) !== round(out[10], 2)], [true, true, true])
}

console.log('\nthe waveform')
{
  const rate = 48000
  const samples = new Float32Array(2048)
  for (let k = 0; k < samples.length; k++) samples[k] = 0.05 * Math.sin(k * 0.05)
  const wave = new Float32Array(V.WAVE_POINTS)
  const agc = { peak: 0.05 }
  V.waveFromSamples(samples, rate, agc, 1, 1 / 60, wave)
  check('384 points across the board\'s 28 ms, tapered to nothing at both ends', [wave.length, V.WAVE_SPAN_S, wave[0], wave[383]], [384, 0.028, 0, 0])
  const peak = Math.max(...wave.map(Math.abs))
  //? 0.05 at its loudest wants a gain of 14 (0.7 / 0.05): held to 4, through the 0.9 and the tanh
  check('a quiet recording is lifted to a line worth seeing - the gain at most 4x - softly limited', round(peak, 3), round(Math.tanh(0.05 * 0.9 * 4), 3))
  V.waveFromSamples(samples, rate, agc, 0, 1 / 60, wave)
  check('...and nothing at all once a pause has died away', Math.max(...wave.map(Math.abs)), 0)
}

console.log('\nthe calm idle signal')
{
  const a = new Float32Array(64), b = new Float32Array(64), wa = new Float32Array(384), wb = new Float32Array(384)
  V.idleSignal(20, a, wa)
  V.idleSignal(20 + 1 / 60, b, wb)
  const step = Math.max(...a.map((v, i) => Math.abs(v - b[i])))
  check('soft and low - no band above 0.35 - and changing slowly from frame to frame', [Math.max(...a) <= 0.35, Math.min(...a) >= 0, step < 0.01], [true, true, true])
  const again = new Float32Array(64)
  V.idleSignal(20, again, new Float32Array(384))
  check('...the same at the same moment: nothing random in it', [...again], [...a])
}

console.log('\nthe signal shaped as the effects read it')
{
  const S = V.newShaped()
  const loud = new Float32Array(64).fill(0.8)
  V.shapeSignal(S, loud, 1 / 60, false)
  const risen = S.spec[0]
  check('a band rises fast (30 ms)', round(risen, 2), round(0.8 * (1 - Math.exp(-1 / 60 / 0.03)), 2))
  for (let k = 0; k < 30; k++) V.shapeSignal(S, loud, 1 / 60, false)
  V.shapeSignal(S, new Float32Array(64), 1 / 60, false)
  check('...and falls slower (160 ms); its peak cap falls 0.3 a second', [round(S.spec[0], 2), round(S.peaks[0], 3)], [round(0.8 * Math.exp(-1 / 60 / 0.16), 2), round(0.8 - 0.3 / 60, 3)])
  check('the bass is the low twelve bands, the energy all 64', [round(S.bass, 3), round(S.energy, 3)], [round(S.spec[0], 3), round(S.spec[0], 3)])
  const K = V.newShaped()
  const quiet = new Float32Array(64).fill(0.1)
  for (let k = 0; k < 60; k++) V.shapeSignal(K, quiet, 1 / 60, false)
  const thump = Float32Array.from(quiet, (v, i) => (i < 8 ? 0.7 : v))
  V.shapeSignal(K, thump, 1 / 60, false)
  const struck = K.kick
  for (let k = 0; k < 12; k++) V.shapeSignal(K, quiet, 1 / 60, false)
  check('a kick: the low bands jumping above their own level - and gone again within a fifth of a second', [struck > 0.8, K.kick < struck * 0.25], [true, true])
  const C = V.newShaped()
  for (let k = 0; k < 60; k++) V.shapeSignal(C, quiet, 1 / 60, true)
  V.shapeSignal(C, thump, 1 / 60, true)
  check('Reduced Motion: no kick at all, and everything rises slowly', [C.kick, C.spec[0] < 0.2], [0, true])
}

console.log('\ndrawn at a size the screen can afford')
check('a 1440x900 laptop at 2x: the 2D effects sharp at 2x, the WebGL styles at 1.25x as the board draws them',
  [V.backingScale(1440, 900, 2, V.MAX_2D_PIXELS), V.backingScale(1440, 900, 2, V.MAX_GL_PIXELS)], [2, 1.25])
check('a 5K screen (2560x1440 at 2x): neither asked for 5K pixels',
  [round(V.backingScale(2560, 1440, 2, V.MAX_2D_PIXELS), 2), round(V.backingScale(2560, 1440, 2, V.MAX_GL_PIXELS), 2)], [1.19, 0.74])
check('a plain 1024x768 screen at 1x: as it is; never under half; no ratio reads as 1',
  [V.backingScale(1024, 768, 1, V.MAX_GL_PIXELS), V.backingScale(8000, 8000, 1, V.MAX_GL_PIXELS), V.backingScale(800, 600, 0, V.MAX_GL_PIXELS)], [1, 0.5, 1])
check('Reduced Motion runs every clock at about a third of its pace', V.CALM_PACE, 0.35)

console.log('\nthe Mandala folds with no seam (found in the real page: a tear along the left horizontal)')
{
  const shader = fs.readFileSync(path.join(UI, 'src/lib/vizShaders.ts'), 'utf8')
  const mandala = shader.slice(shader.indexOf('export const MANDALA'))
  check('the plane is turned by the spin and twist, and only then measured',
    [/vec2 wt = rot\(uFold\.y \+ uFold\.z \* log\(r \+ 0\.02\)\) \* w;\s*float a = atan\(wt\.y, wt\.x\);/.test(mandala), /atan\([^)]*\) \+ uFold\.y/.test(mandala)],
    [true, false])
  //? why: the fold is even, so measured from a turned plane it meets itself where atan wraps at +-pi;
  //? an offset added after atan moves the wrap off the mirror, and a count between whole numbers tears
  const tri = (x) => Math.abs(((x + 0.5) % 1 + 1) % 1 - 0.5)
  const fold = (x, y, spin, n, turnFirst) => {
    const seg = 2 * Math.PI / n
    const a = turnFirst ? Math.atan2(Math.sin(spin) * x + Math.cos(spin) * y, Math.cos(spin) * x - Math.sin(spin) * y) : Math.atan2(y, x) + spin
    return seg * tri(a / seg)
  }
  const jump = (turnFirst) => Math.max(...[0.3, 1.1, 2.4].map((spin) => Math.abs(fold(-1, 1e-7, spin, 6.5, turnFirst) - fold(-1, -1e-7, spin, 6.5, turnFirst))))
  check('6.5 mirrors, spun: no jump either side of the left horizontal; the old way jumps', [jump(true) < 1e-5, jump(false) > 0.05], [true, true])
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
