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
 * And the Mandala refined (2.0.0-player.34; James: "it just looks a bit busy", "a hard line that things
 * just appear out of"): its mirror count changing only by folding (MIRROR_COUNTS, mirrors, foldAngle -
 * every wedge like every other at every moment, the shader folding the same way); one figure with room
 * round it, the extra layers each there only some of the time; its tiles and the band's cells carrying
 * on into the next cell instead of being cut off along a straight edge; the rings in one colour; a
 * shorter trail; and the figure worked out only where it shows.
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

console.log('\nthe Mandala changes its mirror count by FOLDING (James: "a hard line that things just appear out of")')
{
  const shader = fs.readFileSync(path.join(UI, 'src/lib/vizShaders.ts'), 'utf8')
  const mandala = shader.slice(shader.indexOf('export const MANDALA'), shader.indexOf('export const WAVES'))
  const counts = V.MIRROR_COUNTS, n = counts.length
  check('the counts, in their one order, round and round', counts, [8, 4, 12, 6, 3, 9, 3, 6, 12, 4])
  check('...each to the next (and the last back to the first) twice or three times as many, or a half or a third',
    counts.map((a, k) => { const b = counts[(k + 1) % n]; return Math.max(a, b) / Math.min(a, b) }).every((r) => r === 2 || r === 3), true)
  const tri = (x) => Math.abs((((x + 0.5) % 1) + 1) % 1 - 0.5)
  //? an angle as atan measures it, in -pi..pi
  const wrap = (x) => x - 2 * Math.PI * Math.round(x / (2 * Math.PI))
  const whole = (a, N) => { const seg = 2 * Math.PI / N; return seg * tri(wrap(a) / seg) }
  const P = V.MIRROR_PHRASE, H = V.MIRROR_HOLD
  //? the clock at segment k, a share u of the way through its swing (u = 0 as the swing begins)
  const at = (k, u) => P * (k + H + (1 - H) * u)
  check('while a count holds it is that whole number, folded within the lower of it and the next',
    counts.map((a, k) => { const m = V.mirrors(P * k + 3); return m.count === a && m.outer === Math.min(a, counts[(k + 1) % n]) }).every(Boolean), true)
  //? a hair before the phrase ends - still this phrase's swing, so this is the count the shader draws
  //? just before the outer count changes (at the phrase's end itself the next phrase holds its own count)
  check('...and at the end of the swing it is the next count exactly, never a hair off',
    counts.map((a, k) => [1e-9, 1e-12].every((e) => V.mirrors(P * (k + 1) - e).count === counts[(k + 1) % n])).every(Boolean), true)
  check('...the phrase 16 beats, its count held for 62% of them and swung over the rest', [P, H], [16, 0.62])
  //? the swinging mirror's angle, pi / count, moves evenly over the eased swing: equal steps of the eased
  //? share (smoothstep) give equal steps of angle - a count glided straight from one to the other would
  //? rush the angle at the low count's end (3 to 9: nine times as fast there as at 9)
  check('...and the swinging mirror\'s angle (pi / count) moves evenly with the eased swing, never rushing at one end',
    counts.map((a, k) => { const b = counts[(k + 1) % n]; let worst = 0
      for (let u = 0; u <= 1.0001; u += 0.01) { const e = u * u * (3 - 2 * u); worst = Math.max(worst, Math.abs(Math.PI / V.mirrors(at(k, Math.min(u, 1))).count - (Math.PI / a + (Math.PI / b - Math.PI / a) * e))) }
      return worst < 1e-9 }).every(Boolean), true)
  check('through a swing the count moves only between the two, every step one way',
    counts.map((a, k) => { const b = counts[(k + 1) % n]; let last = a; let ok = true
      for (let u = 0; u <= 1.0001; u += 0.02) { const c = V.mirrors(at(k, u)).count; if (c < Math.min(a, b) - 1e-9 || c > Math.max(a, b) + 1e-9 || (b > a ? c < last - 1e-9 : c > last + 1e-9)) ok = false; last = c }
      return ok }).every(Boolean), true)
  //? at the fastest pace the clock runs (2.2 beats a second, 60 frames a second), the swinging mirror's
  //? angle (pi / count) moves a hair from one frame to the next: it swings, never jumps
  check('...and SWINGS: the mirror\'s angle moving under 0.02 rad from one frame to the next, at the fastest pace',
    counts.map((a, k) => { let worst = 0
      for (let u = 0; u <= 1; u += 0.001) { const c0 = at(k, u); worst = Math.max(worst, Math.abs(Math.PI / V.mirrors(c0 + 2.2 / 60).count - Math.PI / V.mirrors(c0).count)) }
      return worst < 0.02 }).every(Boolean), true)
  //? where a count hands over to the next (the clock crossing a phrase), the outer count can change - the
  //? count then is a whole multiple of both, so the picture either side is the same
  //? - the folds as they are, never rounded: a swing that stopped short of the next count (11.6 of 12) and
  //? then jumped to it at the phrase's end would be a cut, and rounding would hide it
  check('...and where the outer count changes, at a phrase\'s end, the fold is the same either side of it',
    counts.map((a, k) => { const before = V.mirrors(P * (k + 1) - 1e-9), after = V.mirrors(P * (k + 1) + 1e-9)
      let off = 0
      for (let j = 0; j < 720; j++) { const x = -Math.PI + j * 2 * Math.PI / 720; off = Math.max(off, Math.abs(V.foldAngle(x, before.outer, before.count) - V.foldAngle(x, after.outer, after.count))) }
      return off < 1e-6 }).every(Boolean), true)
  check('...nor does the swinging mirror move across it: under 0.002 rad from one frame to the next, at the fastest pace',
    counts.map((a, k) => Math.abs(Math.PI / V.mirrors(P * (k + 1) + 2.2 / 120).count - Math.PI / V.mirrors(P * (k + 1) - 2.2 / 120).count) < 0.002).every(Boolean), true)
  //? the fold through every swing, at eleven moments of it, sampled finely right round the circle
  const SAMPLES = 7200, step = 2 * Math.PI / SAMPLES
  const problems = { jump: [], wedge: [], mirror: [], ends: [] }
  counts.forEach((a, k) => {
    const b = counts[(k + 1) % n]
    for (let i = 0; i <= 10; i++) {
      //? the swing's end taken a hair before the phrase ends, while it is still this phrase's swing
      const u = i / 10, { count, outer } = V.mirrors(i === 10 ? P * (k + 1) - 1e-9 : at(k, u))
      const f = (x) => V.foldAngle(wrap(x), outer, count)
      let jump = 0, wedge = 0, mirror = 0
      for (let j = 0; j < SAMPLES; j++) {
        const x = -Math.PI + j * step
        //? continuous everywhere, the wrap from +pi round to -pi included: a fold never moves faster than the angle
        jump = Math.max(jump, Math.abs(f(x + step) - f(x)) - step)
        wedge = Math.max(wedge, Math.abs(f(x + 2 * Math.PI / outer) - f(x)))
        //? mirrored about every one of the outer count's mirror lines
        const line = Math.round(x / (Math.PI / outer)) * (Math.PI / outer), d = x - line
        mirror = Math.max(mirror, Math.abs(f(line + d) - f(line - d)))
      }
      if (jump > 1e-9) problems.jump.push([a, b, u, jump])
      if (wedge > 1e-9) problems.wedge.push([a, b, u, wedge])
      if (mirror > 1e-9) problems.mirror.push([a, b, u, mirror])
      if (i === 0 || i === 10) {
        const target = i === 0 ? a : b
        let off = 0
        for (let j = 0; j < SAMPLES; j++) { const x = -Math.PI + j * step; off = Math.max(off, Math.abs(f(x) - whole(x, target))) }
        if (off > 1e-9) problems.ends.push([a, b, u, off])
      }
    }
  })
  check('through every swing the folded angle never jumps - across every mirror line and round the wrap', problems.jump, [])
  check('...every wedge is like every other at every moment: the same a whole wedge round', problems.wedge, [])
  check('...mirrored about every mirror line of the count it swings within', problems.mirror, [])
  check('...and it starts as exactly the one count\'s fold and ends as exactly the next\'s (6 to 12 is 6 folded again)', problems.ends, [])
  //? the control: the old way, one fold at a count between whole numbers - one wedge round the circle
  //? unlike the others (it is where shapes were born out of a line)
  const old = (x, N) => { const seg = 2 * Math.PI / N; return seg * tri(wrap(x) / seg) }
  let oddOld = 0
  for (let j = 0; j < SAMPLES; j++) { const x = -Math.PI + j * step; oddOld = Math.max(oddOld, Math.abs(old(x + 2 * Math.PI / 6.5, 6.5) - old(x, 6.5))) }
  check('(the old way, 6.5 mirrors in one fold: a wedge unlike the rest - this is what it replaces)', oddOld > 0.1, true)
  check('the shader folds the same way: into uOuter wedges, then each again at the count as it swings',
    /float seg = 2\.0 \* PI \/ uOuter;\s*float fa = seg \* tri\(a \/ seg\);\s*float sub = 2\.0 \* PI \/ uFold\.x;\s*fa = sub \* tri\(fa \/ sub\);/.test(mandala), true)
  check('...the rings\' wobble by the count as it swings, read off the folded angle', /cos\(uFold\.x \* fa\)/.test(mandala), true)
  const gl = fs.readFileSync(path.join(UI, 'src/player/vizGl.ts'), 'utf8')
  check('...and the renderer hands it the outer count and the room', [/gl\.uniform1f\(u\['uOuter'\]!, M\.outer\)/.test(gl), /gl\.uniform4fv\(u\['uRoom'\]!, M\.room\)/.test(gl), /'uOuter'/.test(gl) && /'uRoom'/.test(gl)], [true, true, true])
  const M = V.newMandala(0)
  const figures = [3, 13, 29, 150].map((c) => { M.clock = c; M.shape = c; return [V.mandalaMorph(M, 0.5), V.mirrors(c)] })
  check('the figure carries the mirrors\' count and outer count', figures.every(([fig, m]) => fig.fold[0] === m.count && fig.outer === m.outer), true)
}

console.log('\nthe Mandala calmed (James: "right now it just looks a bit busy")')
{
  const shader = fs.readFileSync(path.join(UI, 'src/lib/vizShaders.ts'), 'utf8')
  const mandala = shader.slice(shader.indexOf('export const MANDALA'), shader.indexOf('export const WAVES'))
  check('no flare across the middle any more', /flare/.test(mandala.replace(/uFlare/g, '')), false)
  check('the glow is scaled down all three channels together, so it keeps the cover\'s colour instead of burning to white',
    /float peak = max\(col\.r, max\(col\.g, col\.b\)\);\s*col \*= \(1\.0 - exp\(-[\d.]+ \* peak\)\) \/ max\(peak, 0\.0001\);/.test(mandala), true)
  check('ONE figure in a disc of the screen, the pattern beyond it only faint',
    [/float reach = uRoom\.x \* min\(1\.0, uRes\.x \/ uRes\.y\);\s*float inside = 1\.0 - smoothstep\(reach \* 0\.9, reach \* 1\.15, r0\);/.test(mandala), /float faint = \(1\.0 - inside\) \* uRoom\.y \* 0\.1\d;/.test(mandala)], [true, true])
  //? the disc fades out before the screen's edge whatever the feel - r0 is in screen heights, so the top and
  //? bottom edges are at 0.5 (and a portrait screen's sides nearer: the reach scales with the width there).
  //? Until review it faded from 0.75 to 1.2 of 0.5 for smooth music: lines ran off the top and bottom at
  //? 70% of their brightness while the sides faded to black - cropped, not room round it
  const fadeEnd = (A, aspect = 16 / 10) => V.mandalaMorph(V.newMandala(100), A).room[0] * Math.min(1, aspect) * 1.15
  check('...faded out before the screen\'s top and bottom (and a portrait screen\'s sides) at every feel - never cut off by them',
    [[0, 0.25, 0.5, 0.75, 1].every((A) => fadeEnd(A) < 0.5), [0, 1].every((A) => fadeEnd(A, 9 / 16) < 0.5 * 9 / 16)], [true, true])
  //? and the echoes and the band of cells each scaled by their own coming and going, as the faint pattern
  //? is by uRoom.y: without it a layer would show all the time
  check('...the echoes scaled by uRoom.z and the band of cells by uRoom.w, so each comes and goes on screen',
    [/col \+= uBody2 \* exp\([^;]*glowLine\(dn, [^;]*uRoom\.z[^;]*;/.test(mandala), /col \+= uBody2 \* band [^;]*uRoom\.w[^;]*;/.test(mandala)], [true, true])
  //? across ten minutes of the clocks: how often each extra layer shows, and how many at once
  const M = V.newMandala(0)
  let layers = 0, none = 0, frames = 0
  const on = [0, 0, 0]
  for (let c = 0; c < 1100; c += 0.5) {
    M.clock = c
    M.shape = c * 1.13
    const room = V.mandalaMorph(M, 0.5).room
    const shown = room.slice(1).map((w) => w > 0.5)
    shown.forEach((v, i) => { if (v) on[i] += 1 })
    layers += shown.filter(Boolean).length
    if (!shown.some(Boolean)) none += 1
    frames += 1
  }
  const share = on.map((v) => Math.round((100 * v) / frames))
  console.log(`    (over ten minutes: the faint lattice beyond the figure ${share[0]}% of the time, the echoes ${share[1]}%, the band of cells ${share[2]}%, ${Math.round((100 * none) / frames)}% none of them; ${(layers / frames).toFixed(2)} at once on average)`)
  check('the faint lattice, the echoes and the band each come and go - each there under half the time', share.every((v) => v > 5 && v < 50), true)
  check('...so on average fewer than one of them shows at once', layers / frames < 1, true)
  const smooth = V.mandalaMorph(V.newMandala(100), 0), metal = V.mandalaMorph(V.newMandala(100), 1)
  //? harder, never fainter: aggressive music's lines carry less glow but are drawn wider - thinner as well,
  //? they broke into faint dashes and the figure went nearly empty for seconds at a time (found in review)
  check('smooth music: the figure wide and its lines soft; aggressive: tighter and harder - less glow, lines no thinner',
    [smooth.room[0] > metal.room[0], smooth.edge[0] > metal.edge[0], metal.edge[1] >= smooth.edge[1]], [true, true, true])
}

console.log('\nthe Mandala\'s tiles and cells carry on into the next cell (no straight line a spike appears out of)')
{
  const shader = fs.readFileSync(path.join(UI, 'src/lib/vizShaders.ts'), 'utf8')
  const mandala = shader.slice(shader.indexOf('export const MANDALA'), shader.indexOf('export const WAVES'))
  //? the shader's own distance fields, in JavaScript: sdPoly with the numbers every shape shares made once
  //? (k: the side's angle, a spike's reach), GLSL's rot() (column-major: (c, s) and (-s, c))
  const fract = (x) => x - Math.floor(x), tri = (x) => Math.abs(fract(x + 0.5) - 0.5)
  const rot = (a, [x, y]) => [Math.cos(a) * x - Math.sin(a) * y, Math.sin(a) * x + Math.cos(a) * y]
  const mixf = (a, b, t) => a + (b - a) * t
  const sdPoly = ([x, y], r, n, star, rnd) => {
    const seg = (2 * Math.PI) / n, la = seg * tri(Math.atan2(y, x) / seg)
    const edge = r / Math.cos(la), spike = mixf(r * 0.5, r * (1.35 / Math.cos(0.5 * seg)), (2 * la) / seg)
    return Math.hypot(x, y) - mixf(mixf(edge, spike, star), r * 1.08, rnd)
  }
  const glow = (d, w, tail) => Math.exp(-(d * d) / (w * w)) + tail * Math.exp(-d / (3 * w))
  const C = 0.3
  //? the tiles as the shader works them out: this cell's polygon and the three round the corner the point
  //? is nearest (the union: a signed min); the old way, this cell's alone
  const tiles = ([sx, sy], turn, n, star, rnd, four) => {
    const g = [fract(sx / C), fract(sy / C)], h = [(g[0] - 0.5) * C, (g[1] - 0.5) * C]
    const o = [(g[0] >= 0.5 ? 1 : -1) * C, (g[1] >= 0.5 ? 1 : -1) * C]
    const at = (dx, dy) => sdPoly(rot(turn, [h[0] - dx, h[1] - dy]), C * 0.32, n, star, rnd)
    return four ? Math.min(at(0, 0), at(o[0], 0), at(0, o[1]), at(o[0], o[1])) : at(0, 0)
  }
  //? the band's cells along their arc: the cell's polygon and the next one along, the nearer
  const cw = 0.06
  const band = (x, y, turn, n, star, rnd, two) => {
    const cell = [(fract(x / cw) - 0.5) * cw, y]
    const at = (dx) => sdPoly(rot(turn, [cell[0] - dx, cell[1]]), cw * 0.3, n, star * 0.5, rnd * 0.5)
    return two ? Math.min(at(0), at(Math.sign(cell[0]) * cw)) : at(0)
  }
  //? across every cell edge, through every shape (sides 3 to 8, any number; stars; rounded) and turn: the
  //? largest jump in a line's brightness (its core and its glow's tail at their widest), a hair either side
  const e = 1e-7, w = 0.01, tail = 0.25
  const worst = { tiles: [0, 0], band: [0, 0] }
  for (const n of [3, 3.5, 4, 5, 6.5, 8]) for (const star of [0, 0.5, 1]) for (const rnd of [0, 0.5]) for (let k = 0; k < 12; k++) {
    const turn = 0.1 + (k * Math.PI) / 6
    for (let j = 0; j <= 60; j++) {
      const y = (j / 60) * C
      if (Math.abs(y - C / 2) < 1e-3) continue
      for (const four of [true, false]) {
        //? a vertical cell edge and a horizontal one
        const jx = Math.abs(glow(Math.abs(tiles([C - e, y], turn, n, star, rnd, four)), w, tail) - glow(Math.abs(tiles([C + e, y], turn, n, star, rnd, four)), w, tail))
        const jy = Math.abs(glow(Math.abs(tiles([y, C - e], turn, n, star, rnd, four)), w, tail) - glow(Math.abs(tiles([y, C + e], turn, n, star, rnd, four)), w, tail))
        worst.tiles[four ? 0 : 1] = Math.max(worst.tiles[four ? 0 : 1], jx, jy)
      }
      const by = (j / 60 - 0.5) * cw
      for (const two of [true, false]) {
        const jb = Math.abs(glow(Math.abs(band(cw - e, by, turn, n, star, rnd, two)), w * 0.3, tail) - glow(Math.abs(band(cw + e, by, turn, n, star, rnd, two)), w * 0.3, tail))
        worst.band[two ? 0 : 1] = Math.max(worst.band[two ? 0 : 1], jb)
      }
    }
  }
  console.log(`    (the largest jump in brightness across a cell's edge: tiles ${round(worst.tiles[0], 5)}, cut off as before ${round(worst.tiles[1], 2)}; the band's cells ${round(worst.band[0], 5)}, before ${round(worst.band[1], 2)})`)
  check('a tile\'s corners and spikes carry on into the next cell: no jump across a cell\'s edge (the old way, cut off, jumps)', [worst.tiles[0] < 1e-3, worst.tiles[1] > 0.5], [true, true])
  check('...and the band\'s cells the same', [worst.band[0] < 1e-3, worst.band[1] > 0.5], [true, true])
  check('the shader works the tiles out so: this cell\'s and the three round its nearest corner, as one shape',
    [/vec2 h = \(g - 0\.5\) \* C;/.test(mandala), /vec2 o = \(step\(0\.5, g\) \* 2\.0 - 1\.0\) \* C;/.test(mandala),
      /float dTile = min\(min\(sdPoly\(tr \* h, C \* 0\.32, pk, uSrc\.w, uForm\.y\), sdPoly\(tr \* \(h - vec2\(o\.x, 0\.0\)\), C \* 0\.32, pk, uSrc\.w, uForm\.y\)\),\s*min\(sdPoly\(tr \* \(h - vec2\(0\.0, o\.y\)\), C \* 0\.32, pk, uSrc\.w, uForm\.y\), sdPoly\(tr \* \(h - o\), C \* 0\.32, pk, uSrc\.w, uForm\.y\)\)\);/.test(mandala)],
    [true, true, true])
  check('...and the band\'s cells: the cell\'s and the next one along, the nearer',
    [/float dNext = sdPoly\(br \* \(cell - vec2\(sign\(cell\.x\) \* cw, 0\.0\)\), cw \* 0\.3, pk, uSrc\.w \* 0\.5, uForm\.y \* 0\.5\);/.test(mandala), /float band = glowLine\(abs\(min\(dCell, dNext\)\),/.test(mandala)],
    [true, true])
  //? the polygon's fill comes from its OWN field, never from the nearer of it and the tiles: the nearer
  //? outline changes sides wherever the two are as far away as each other with opposite signs - a curve on
  //? no drawn line - and a fill read from it went from full to nothing across it in one pixel, bites taken
  //? out of a flat disc (found in review). Along lines across the tiles, wherever the field changes sign a
  //? line-width or more from any outline, the fill jumps
  {
    const lw = 0.004, fill = (d) => 1 - (d <= -lw ? 0 : d >= lw ? 1 : ((d + lw) / (2 * lw)) ** 2 * (3 - 2 * (d + lw) / (2 * lw)))
    let jumpsSelect = 0, jumpsOwn = 0
    for (const [n, star, rnd, turn] of [[5, 0, 0, 0.3], [4, 0.5, 0, 1.1], [6, 0, 0.5, 2.0], [3, 1, 0, 0.7]]) for (let row = 0; row < 12; row++) {
      const y = -0.5 + row * 0.083
      let last = null
      for (let x = -0.6; x <= 0.6; x += 2e-4) {
        const core = sdPoly([x, y], 0.42, n, star, rnd), tile = tiles([x, y], turn, n, star, rnd, true)
        const select = Math.abs(core) < Math.abs(tile) ? core : tile
        if (last) {
          if (Math.abs(fill(select) - fill(last.select)) > 0.5 && Math.min(Math.abs(select), Math.abs(last.select)) > lw) jumpsSelect++
          if (Math.abs(fill(core) - fill(last.core)) > 0.5 && Math.min(Math.abs(core), Math.abs(last.core)) > lw) jumpsOwn++
        }
        last = { core, select }
      }
    }
    console.log(`    (the fill across lines over the tiles: ${jumpsOwn} jumps from the polygon's own field; ${jumpsSelect} from the nearer outline, as before)`)
    check('the polygon\'s fill read from its own field: it never jumps off an outline (read from the nearer of it and the tiles, it does)', [jumpsOwn, jumpsSelect > 20], [0, true])
    check('...and the shader fills it so: the polygon\'s field kept before the tiles are taken in, the fill read from that',
      [(() => { const made = mandala.indexOf('float dPoly = sdPoly(s, 0.42'), kept = mandala.indexOf('float dCore = dPoly;'), chosen = mandala.indexOf('dPoly = abs(dPoly) < abs(dTile)'); return made >= 0 && made < kept && kept < chosen && (mandala.match(/\bdCore\s*=[^=]/g) || []).length === 1 })(),
        /float fill = uForm\.x \* \(1\.0 - smoothstep\(-lw, lw, dCore\)\)/.test(mandala)], [true, true])
  }
  check('...with the polygon the JavaScript here draws (the same fold, edge, spike and rounding)',
    [/float la = k\.x \* tri\(atan\(p\.y, p\.x\) \/ k\.x\);/.test(mandala), /float spike = mix\(r \* 0\.5, r \* k\.y, 2\.0 \* la \/ k\.x\);/.test(mandala),
      /return length\(p\) - mix\(mix\(edge, spike, star\), r \* 1\.08, round\);/.test(mandala), /vec2 pk = vec2\(pSeg, 1\.35 \/ cos\(0\.5 \* pSeg\)\);/.test(mandala)],
    [true, true, true, true])
}

console.log('\nthe Mandala\'s lines kept clean: rings in one colour, a shorter trail, and nothing worked out where nothing shows')
{
  const shader = fs.readFileSync(path.join(UI, 'src/lib/vizShaders.ts'), 'utf8')
  const mandala = shader.slice(shader.indexOf('export const MANDALA'), shader.indexOf('export const WAVES'))
  check('the rings in the cover\'s colour alone - no rainbow fringe splitting each into three',
    [/float glowRing\(float r, float R, float w\)/.test(mandala), /\brr\b/.test(mandala), /float rings = 0\.0;/.test(mandala), /uniform vec3 uEdge;/.test(mandala)], [true, false, true, true])
  const gl = fs.readFileSync(path.join(UI, 'src/player/vizGl.ts'), 'utf8')
  const fig = V.mandalaMorph(V.newMandala(100), 0.5)
  check('...so the line\'s look is three numbers - glow tail, width, the trail\'s fringe - handed over as three',
    [fig.edge.length, /gl\.uniform3fv\(u\['uEdge'\]!, M\.edge\)/.test(gl), /float cab = uEdge\.z;/.test(mandala)], [3, true, true])
  check('the trail behind the lines about half as long: a line drags no stack of echoes', /vec3 fb = max\(prev \* 0\.6 - 0\.018, 0\.0\);/.test(mandala), true)
  //? the figure is worked out only where it or the faint pattern beyond it shows - and that is exact: every
  //? colour it adds is scaled by `inside` or `faint`, so where both are 0 it would have added nothing. Judged
  //? TERM by term, not line by line: a line can add two things at once (the main lines, `(uBody * inside *
  //? 1.5 + uFlare * faint) * ...`), and one term unscaled is the figure off its disc while the line still
  //? names the other word (review)
  const open = mandala.indexOf('  if (inside > 0.0 || faint > 0.0) {'), close = mandala.indexOf('\n  }\n', open)
  const block = open < 0 ? '' : mandala.slice(open, close)
  const adds = block.split('\n').filter((line) => /^\s*col \+?= /.test(line))
  /** `expr` split at `sep` where it isn't inside brackets (a sign at the start, or after an operator, isn't
   *  a split: it is a number's own). */
  const split = (expr, sep) => {
    const parts = []
    let depth = 0, from = 0
    for (let i = 0; i < expr.length; i++) {
      const c = expr[i]
      if (c === '(') depth++
      else if (c === ')') depth--
      else if (depth === 0 && sep.includes(c) && expr.slice(from, i).trim() && !/[*/+\-(,]\s*$/.test(expr.slice(0, i))) {
        parts.push(expr.slice(from, i))
        from = i + 1
      }
    }
    parts.push(expr.slice(from))
    return parts.map((part) => part.trim())
  }
  /** Whether every term of `expr` is scaled by `inside` or `faint`: a term is a product, scaled when one
   *  of its factors is either word, or a bracketed sum every term of which is (a function's arguments
   *  never scale what it returns). */
  const scaled = (expr) => split(expr, '+-').every((term) => split(term, '*/').some((factor) =>
    /^(inside|faint)$/.test(factor) || (factor.startsWith('(') && factor.endsWith(')') && scaled(factor.slice(1, -1)))))
  const rhs = (line) => line.replace(/^\s*col \+?= /, '').replace(/;\s*$/, '')
  check('the figure skipped only where it and the faint pattern both show nothing: every colour it adds is scaled by one of them, term by term',
    [open > 0, adds.length >= 5, adds.filter((line) => !scaled(rhs(line))).map((line) => line.trim())], [true, true, []])
  check('...which the rule can see: a term left unscaled is caught, the main lines\' or another line\'s',
    [scaled('(uBody * inside * 1.5 + uFlare * faint) * glowLine(d, lw, uEdge.x) * dense'), scaled('(uBody * 1.5 + uFlare * faint) * glowLine(d, lw, uEdge.x) * dense'),
      scaled('(uBody * inside * 1.5 + uFlare) * glowLine(d, lw, uEdge.x) * dense'), scaled('uBody2 * band * (1.0 - smoothstep(cw * 0.35, cw * 0.55, abs(r - uLat.z))) * 0.6 * dense'),
      scaled('x * inside + glowLine(d, inside, faint)'), scaled('-x * inside - y * faint')], [true, false, false, false, false, true])
  check('...and the core\'s glow, which reaches everywhere, drawn outside it', mandala.slice(close).includes('col += uCore * '), true)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
