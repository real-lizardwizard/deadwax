/**
 * The turntable, part two (2.0.0-player.14): momentum, and the sound following the record. The pure
 * physics (lib/platter.ts), the record's voice (lib/deckVoice.ts) - run directly, and run again as the
 * AudioWorklet module the browser loads, made from the same functions' source - and the deck
 * (player/deck.ts) against a fake audio context, fake timers and a fake deadwax.
 *
 * What it pins:
 *
 *  - THE PHYSICS: the motor from still to speed in SPIN_UP_S (0.4 s), friction from speed to still in
 *    SPIN_DOWN_S (1 s), a hard flick coasting about 1-2 s; through zero from a backwards flick; where a
 *    coast lands and where the motor has a playing song back at speed, given exactly at the release
 *    and matching a step-by-step integration of the same equations to within a millisecond, many
 *    flicks over; the song's ends - a coast back past the start stops there, one past the end stops
 *    END_MARGIN_S short of it, a motor run back to the start spins up from it; positions and speeds
 *    continuous from one phase to the next.
 *  - THE HAND'S SPEED: over its last ~90 ms, 0 for a finger that rested, backwards negative, held to
 *    MAX_SPEED; and the rate posted to the voice is the platter's speed over its own.
 *  - THE VOICE: its position integrates the rate exactly, forwards and backwards; a change of speed is
 *    smoothed (no step in the rate) and never jumps the sound beyond what the signal itself does;
 *    silence with the record held still, and outside the window; a drive that stops coming runs out;
 *    it steers to the position it is told and stays there; it fades in, out and stops.
 *  - THE WORKLET: its module is made from those functions' own source, and running it as the browser
 *    would gives the very same samples, and reports where it is ~30 times a second.
 *  - THE DECK: the audio context is made only by wakeDeckAudio() (a gesture), suspended when hidden,
 *    closed when gone; a press takes the record only past a tap or a rest longer than one - pausing a
 *    playing song through the host, the sound taking over at its position at speed 1; a release seeks
 *    to where the motor has it back at speed (or the coast stops), plays it at speed after the coast
 *    and holds the sound at speed 1 until the song really plays, then fades it; a paused song coasts
 *    and stays paused; a cancel seeks nowhere and plays on what it paused; a song change drops a
 *    coast; a pause winds down only with the setting on and the window there; reduced motion lands at
 *    once and plays in the release's own gesture; the window is fetched round the playhead on a grid,
 *    never for a song that isn't a FLAC, and a 415 is said and not asked again.
 *  - AFTER REVIEW: no window asked without an audio context and its worklet, one on its way at a time
 *    (a slow decode, a hide mid-decode), only the newest decode handed on; a hi-res song's short
 *    windows - margins in proportion, each moving on, at the page's cap (`max_rate`); the window a
 *    coast runs into asked at the release; the motor stopping a backwards flick with friction too; a
 *    song changed mid-coast played after a moment unless something else plays it (a tap, a press, a
 *    play of its own), and the turntable going mid-coast playing it on; a seek made elsewhere quieting
 *    the coast and ending the handover; a refused play spinning the platter down; a press before the
 *    sound holding the record still; the wind-down from the song's own speed and a play mid-way from
 *    where it got to; the arm quieting a coast; and the rules the docs state - the 10 s retry, a decode
 *    refused three ways, nothing for a paused song, a coast caught on its way back, a pause near the
 *    window's end, RESUME_IN_GESTURE_S, PAUSE_SETTLE_MS, a rested release 0.2 s on.
 *
 * Run it with:  node ui/test/deck.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path'), vm = require('vm')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-deck-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/platter.ts', 'src/lib/deckVoice.ts', 'src/player/deck.ts',
  '--rootDir', 'src', '--outDir', OUT,
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
const near = (a, b, within) => Math.abs(a - b) <= within
const round = (value, places = 4) => Math.round(value * 10 ** places) / 10 ** places

const platter = require(path.join(OUT, 'lib/platter.js'))
const voice = require(path.join(OUT, 'lib/deckVoice.js'))
const { SECONDS_PER_TURN } = require(path.join(OUT, 'lib/turntable.js'))

/* ===== the physics ===== */

/**
 * The equations stepped through (acceleration(), the plans' own equations written as equations),
 * with the song's ends as the plans have them - a ground truth the plans are held to. Steps of 10 us,
 * the last one cut where the speed reaches its target, so the time it takes is exact to a step.
 */
function integrate(x, v, motorOn, length, dt = 1e-5) {
  const low = 0, high = length > 0 ? Math.max(0, length - platter.END_MARGIN_S) : Infinity
  let t = 0
  let clamped = null
  const target = motorOn ? 1 : 0
  for (let i = 0; i < 2e7; i++) {
    if (v === target) return { t, x, v, clamped }
    const a = platter.acceleration(v, motorOn)
    let next = v + a * dt
    let step = dt
    if ((v < target && next >= target) || (v > target && next <= target)) {
      step = (target - v) / a
      next = target
    }
    let x2 = x + ((v + next) / 2) * step
    if (x2 < low && x >= low) {
      if (!motorOn) return { t: t + step * (x - low) / (x - x2), x: low, v: 0, clamped: 'start' }
      //? the motor stops at the start, and spins up from it, from still
      t += step * (x - low) / (x - x2)
      x = low
      v = 0
      clamped = 'start'
      continue
    }
    if (x2 > high && x <= high) return { t: t + step * (high - x) / (x2 - x), x: high, v: next, clamped: 'end' }
    x = x2
    v = next
    t += step
  }
  throw new Error('never got there')
}

console.log('\nthe platter: spin-up 0.4 s, spin-down 1 s, a hard flick 1-2 s')
{
  check('still to speed under the motor: SPIN_UP_S, and 0.2 s of the song on', [platter.SPIN_UP_S, round(platter.motor(100, 0, 425).duration), round(platter.motor(100, 0, 425).x - 100)], [0.4, 0.4, 0.2])
  check('speed to still, the motor off: SPIN_DOWN_S', [platter.SPIN_DOWN_S, round(platter.coast(100, 1, 425).duration)], [1, 1])
  const flicks = [0.5, 3, 9, 20].map((v) => round(platter.coast(100, v, 425).duration, 2))
  check('a small flick stops in under a second; a hard one (9, five turns a second) coasts about 1.8 s; harder, about 2', flicks, [0.77, 1.39, 1.8, 2.09])
  check('...backwards the same as forwards', round(platter.coast(100, -9, 425).duration, 2), 1.8)
  check('the motor brings a forward flick back down in under a second', [round(platter.motor(100, 9, 425).duration, 2), round(platter.motor(100, 2, 425).duration, 2)], [0.84, 0.27])
  const back = platter.motor(100, -3, 425)
  //? stopped by the pull AND friction together - a decay to still - then pulled up from still in 0.4 s
  const C = platter.MOTOR_PULL + platter.FRICTION_DRY, K = platter.FRICTION_VISCOUS
  const toStill = (v) => Math.log(1 + (K * -v) / C) / K
  check('from backwards: stopped by the motor\'s pull and friction together, then pulled up from still',
    [round(back.duration), round(back.x - 100), back.v, back.phases.length, back.phases[0].kind], [round(toStill(-3) + platter.SPIN_UP_S), -0.4013, 1, 2, 'decay'])
  //? a backwards flick on a playing record stopped no slower than friction alone stops it (review: the
  //? pull alone ran -9 back for 3.6 s, rewinding 16 s, where the same flick paused coasts 1.8 s)
  check('...the motor never lets a backwards record run longer than friction alone would, at any speed',
    [-0.5, -1, -3, -9, -24].map((v) => platter.motor(200, v, 425).phases[0].duration < platter.coast(200, v, 425).duration), [true, true, true, true, true])
  const hard = platter.motor(200, -9, 425)
  check('...a hard flick back (-9) stopped in about 0.86 s and back at speed in about 1.26, about 2.3 s of the song back - not 4 s and 16',
    [round(hard.phases[0].duration, 2), round(hard.duration, 2), round(hard.x - 200, 1)], [0.86, 1.26, -2.3])
  check('at its own speed already: nothing to wait for', [platter.motor(100, 1, 425).duration, platter.motor(100, 1, 425).x], [0, 100])
  check('the rate the voice reads at is the platter\'s speed over its own', [-2.5, 0, 1, 7].map(platter.voiceRate), [-2.5, 0, 1, 7])
  check('a turn of the record is 1.8 s of the song: 360 degrees, 200 a second at speed',
    [platter.degreesFor(SECONDS_PER_TURN), platter.DEGREES_PER_SECOND], [360, 200])
}

console.log('\nwhere it lands, given at the release, against the equations stepped through')
{
  const cases = [[100, 9, false], [100, -4, false], [100, 0.3, false], [100, 20, false], [100, 9, true], [100, -3, true], [100, 0, true],
    [100, 2.5, true], [100, -0.4, true], [100, 24, true], [0.3, -5, true], [1.2, -6, false], [423.5, 9, false], [424, 9, true]]
  let rng = 7
  const random = () => ((rng = (rng * 1103515245 + 12345) % 2147483648) / 2147483648)
  for (let i = 0; i < 40; i++) cases.push([random() * 425, (random() - 0.4) * 30, random() < 0.5])
  let worstX = 0, worstT = 0
  const disagree = []
  for (const [x, v, on] of cases) {
    const plan = on ? platter.motor(x, v, 425) : platter.coast(x, v, 425)
    const steps = integrate(x, Math.max(-platter.MAX_SPEED, Math.min(platter.MAX_SPEED, v)), on, 425)
    const dx = Math.abs(plan.x - steps.x), dt = Math.abs(plan.duration - steps.t)
    worstX = Math.max(worstX, dx)
    worstT = Math.max(worstT, dt)
    if (dx > 0.001 || dt > 0.001 || (plan.clamped ?? null) !== (steps.clamped ?? null)) disagree.push([x, v, on, plan.x, steps.x, plan.duration, steps.t, plan.clamped, steps.clamped])
  }
  check(`${cases.length} flicks, both ways, the motor on and off: every landing within a millisecond of the song, every time within a millisecond`, disagree, [])
  check('...the worst of them', [worstX < 0.001, worstT < 0.001], [true, true])
}

console.log('\nthe song\'s ends')
{
  const back = platter.coast(1.2, -6, 425)
  check('a coast back past the start stops AT the start, sooner than friction would', [back.x, back.clamped, back.duration < platter.coast(100, -6, 425).duration], [0, 'start', true])
  const on = platter.coast(423.5, 9, 425)
  check('one on past the end stops END_MARGIN_S short of it - the song ends from there by itself', [on.x, on.clamped, platter.END_MARGIN_S], [425 - 0.25, 'end', 0.25])
  const motorBack = platter.motor(0.3, -5, 425)
  check('the motor run back to the start stops there and spins up from it: 0.2 s in at speed', [round(motorBack.x, 9), motorBack.clamped, motorBack.v], [0.2, 'start', 1])
  const motorOn = platter.motor(424, 9, 425)
  check('...and on past the end stops short of it, where the song plays out', [motorOn.x, motorOn.clamped], [424.75, 'end'])
  check('a song with no length known: nothing stops it but friction', [round(platter.coast(3, 9, 0).x, 3), platter.coast(3, 9, 0).clamped], [round(3 + platter.coast(100, 9, 425).x - 100, 3), null])
  check('a start outside the song is brought inside it first', [platter.coast(-5, 0, 425).x, platter.coast(900, 0, 425).x], [0, 424.75])
}

console.log('\none phase into the next: no jump in position or speed')
{
  const plan = platter.motor(100, -3, 425)
  const join = plan.phases[0].duration
  const before = platter.planAt(plan, join - 1e-9), after = platter.planAt(plan, join + 1e-9)
  check('at the turn through zero', [near(before.x, after.x, 1e-6), near(before.v, after.v, 1e-6), near(after.v, 0, 1e-6)], [true, true, true])
  const end = platter.planAt(plan, plan.duration + 5)
  check('past its end: where it ended, at its end\'s speed', [end.x === plan.x, end.v], [true, 1])
  const coast = platter.coast(50, 6, 425)
  let jumps = 0, previous = platter.planAt(coast, 0)
  for (let t = 0.001; t <= coast.duration; t += 0.001) {
    const now = platter.planAt(coast, t)
    if (Math.abs(now.x - previous.x) > 0.01 || now.v > previous.v + 1e-9) jumps++
    previous = now
  }
  check('a coast only ever slows, a millisecond at a time, and never jumps', jumps, 0)
}

console.log('\nthe hand\'s speed: its last ~90 ms')
{
  const turnPerSecond = (time) => ({ time, turned: (time / 1000) * 2 * Math.PI })
  const steady = [0, 16, 32, 48, 64, 80, 96, 112, 128].map(turnPerSecond)
  check('a turn a second is 1.8 s of song a second: 1.8 of its own speed', round(platter.handSpeed(steady, 128), 6), 1.8)
  check('...backwards, the same less', round(platter.handSpeed(steady.map((s) => ({ ...s, turned: -s.turned })), 128), 6), -1.8)
  check('a finger that rested the whole window before letting go: 0', platter.handSpeed(steady, 128 + 90), 0)
  check('...half of it: half the speed', round(platter.handSpeed(steady, 128 + 45), 6), 0.9)
  const slowThenFast = [{ time: 0, turned: 0 }, { time: 500, turned: 0.1 }, { time: 590, turned: 0.1 + Math.PI }]
  check('a slow start then a flick: the flick, not the turn\'s average', round(platter.handSpeed(slowThenFast, 590), 6), round(0.5 * SECONDS_PER_TURN / 0.09, 6))
  check('one sample, or none: no speed', [platter.handSpeed([{ time: 0, turned: 0 }], 10), platter.handSpeed([], 10)], [0, 0])
  check('a jump in the samples is held to MAX_SPEED', platter.handSpeed([{ time: 0, turned: 0 }, { time: 1, turned: 100 }], 1), platter.MAX_SPEED)
}

/* ===== the voice ===== */

const SR = 48000
const sine = (seconds, hz = 440, start = 10) => {
  const data = new Float32Array(Math.round(seconds * SR))
  for (let i = 0; i < data.length; i++) data[i] = 0.5 * Math.sin((2 * Math.PI * hz * i) / SR)
  return { type: 'window', channels: [data, data], start, rate: SR }
}
function render(state, seconds, now, blocks = 128) {
  const frames = Math.round(seconds * SR)
  const left = new Float32Array(frames), right = new Float32Array(frames)
  for (let at = 0; at < frames; at += blocks) {
    const n = Math.min(blocks, frames - at)
    const out = [new Float32Array(n), new Float32Array(n)]
    voice.renderVoice(state, out, n, SR, now + at / SR)
    left.set(out[0], at)
    right.set(out[1], at)
  }
  return { left, right, end: now + frames / SR }
}
const peak = (data, from = 0, to = data.length) => { let p = 0; for (let i = from; i < to; i++) p = Math.max(p, Math.abs(data[i])); return p }
const biggestStep = (data) => { let p = 0; for (let i = 1; i < data.length; i++) p = Math.max(p, Math.abs(data[i] - data[i - 1])); return p }
//? the signal's own biggest step a sample, read at speed 1: 0.5 * 2 pi 440 / 48000
const SIGNAL_STEP = 0.5 * 2 * Math.PI * 440 / SR

console.log('\nthe voice: its position is the sum of its rate')
{
  const state = voice.newVoiceState()
  voice.voiceCommand(state, sine(30), 0, SR)
  voice.voiceCommand(state, { type: 'take', at: 12, rate: 1, time: 0, until: 100 }, 0, SR)
  render(state, 1, 0)
  check('at speed 1 for a second, taken at its own speed: a second on, exactly', round(state.pos, 9), 13)
  voice.voiceCommand(state, { type: 'drive', at: 13, rate: -1, time: 1, until: 100 }, 1, SR)
  render(state, 2, 1)
  check('then backwards at -1 for two: back past where it started, to the drive\'s position', near(state.pos, 11, 1e-3), true)
  const free = voice.newVoiceState()
  voice.voiceCommand(free, sine(30), 0, SR)
  voice.voiceCommand(free, { type: 'take', at: 20, rate: 0.75, time: 0, until: 0.05 }, 0, SR)
  let summed = 20
  for (let i = 0; i < SR / 2; i++) {
    voice.renderVoice(free, [new Float32Array(1)], 1, SR, i / SR)
    summed += free.rate / SR
  }
  check('driven, then the drive running out: the position is exactly the running sum of the rates it read at', near(free.pos, summed, 1e-9), true)
  check('...the rate decayed to still once the drive ran out', near(free.rate, 0, 1e-6), true)
}

console.log('\na change of speed is smoothed, and never jumps the sound')
{
  const state = voice.newVoiceState()
  voice.voiceCommand(state, sine(30), 0, SR)
  voice.voiceCommand(state, { type: 'take', at: 15, rate: 1, time: 0, until: 100 }, 0, SR)
  render(state, 0.2, 0)
  //? from the rate it was reading at the moment the drive changes
  const rates = [state.rate]
  let t = 0.2
  voice.voiceCommand(state, { type: 'drive', at: state.pos, rate: -1, time: t, until: 100 }, t, SR)
  for (let i = 0; i < 2400; i++) {
    voice.renderVoice(state, [new Float32Array(1), new Float32Array(1)], 1, SR, t)
    rates.push(state.rate)
    t += 1 / SR
  }
  const steps = rates.slice(1).map((r, i) => Math.abs(r - rates[i]))
  check('1 to -1 in an instant: the rate it reads at moves no more than a few thousandths a sample', Math.max(...steps) < 0.005, true)
  for (let i = 0; i < 4800; i++) {
    voice.renderVoice(state, [new Float32Array(1), new Float32Array(1)], 1, SR, t)
    rates.push(state.rate)
    t += 1 / SR
  }
  check('...and settles at -1 within about 150 ms (catching up the position it was told on the way)', near(rates.at(-1), -1, 0.01), true)
  const swing = voice.newVoiceState()
  voice.voiceCommand(swing, sine(30), 0, SR)
  voice.voiceCommand(swing, { type: 'take', at: 15, rate: 1, time: 0, until: 100 }, 0, SR)
  let fastest = 0
  const joined = []
  let now = 0
  const run = (seconds) => {
    for (let i = 0; i < Math.round(seconds * SR); i++) {
      const out = [new Float32Array(1), new Float32Array(1)]
      voice.renderVoice(swing, out, 1, SR, now)
      joined.push(out[0][0])
      fastest = Math.max(fastest, Math.abs(swing.rate))
      now += 1 / SR
    }
  }
  run(0.15)
  for (const rate of [-1, 2.5, 0.2, -3, 1]) {
    voice.voiceCommand(swing, { type: 'drive', at: swing.pos, rate, time: now, until: now + 1 }, now, SR)
    run(0.15)
  }
  check('through five changes of speed and direction: no step bigger than the signal\'s own at the fastest speed it was read at',
    biggestStep(Float32Array.from(joined.slice(20))) <= SIGNAL_STEP * fastest * 1.05, true)
}

console.log('\nthe song at its own speed is not dulled')
{
  //? a 12 kHz tone read at speed 1, half a sample off its own samples - where the tone itself is at
  //? 0.5 sin(45 degrees) at most: four-point interpolation keeps it near that (0.88 of it), where reading
  //? straight between two samples would take it to 0.71
  const hz = 12000
  const data = new Float32Array(SR * 4)
  for (let i = 0; i < data.length; i++) data[i] = 0.5 * Math.sin((2 * Math.PI * hz * i) / SR)
  const state = voice.newVoiceState()
  voice.voiceCommand(state, { type: 'window', channels: [data], start: 0, rate: SR }, 0, SR)
  voice.voiceCommand(state, { type: 'take', at: 1 + 0.5 / SR, rate: 1, time: 0, until: 100 }, 0, SR)
  const out = render(state, 0.5, 0).left
  const level = peak(out, SR / 4) / (0.5 * Math.sin(Math.PI / 4))
  check('a 12 kHz tone, half a sample off: at 0.85 of its level or more (linear would be 0.71)', level >= 0.85, true)
}

console.log('\nsilence: held still, and outside the window')
{
  const held = voice.newVoiceState()
  voice.voiceCommand(held, sine(30), 0, SR)
  voice.voiceCommand(held, { type: 'take', at: 15.00123, rate: 0, time: 0, until: 100 }, 0, SR)
  const still = render(held, 0.4, 0).left
  check('a record taken while paused and held still: silent', peak(still, Math.round(0.2 * SR)) < 1e-4, true)
  check('...however loud the sample it rests on', Math.abs(held.window.channels[0][Math.round((held.pos - 10) * SR)]) > 0.01, true)
  const turned = voice.newVoiceState()
  voice.voiceCommand(turned, sine(30), 0, SR)
  voice.voiceCommand(turned, { type: 'take', at: 15, rate: 1, time: 0, until: 100 }, 0, SR)
  render(turned, 0.2, 0)
  voice.voiceCommand(turned, { type: 'drive', at: turned.pos, rate: 0, time: 0.2, until: 100 }, 0.2, SR)
  const stopped = render(turned, 0.6, 0.2).left
  check('turned, then the finger rests: silent once it has stopped', peak(stopped, Math.round(0.4 * SR)) < 1e-4, true)
  const outside = voice.newVoiceState()
  voice.voiceCommand(outside, sine(2, 440, 10), 0, SR)
  voice.voiceCommand(outside, { type: 'take', at: 11.9, rate: 1, time: 0, until: 100 }, 0, SR)
  const across = render(outside, 0.4, 0).left
  check('read on past the window\'s end: silent after it', peak(across, Math.round(0.2 * SR)) < 1e-4, true)
  check('...the edge faded, not cut: no step bigger than the signal\'s own', biggestStep(across.slice(20)) <= SIGNAL_STEP * 1.2, true)
  const none = voice.newVoiceState()
  voice.voiceCommand(none, { type: 'take', at: 5, rate: 1, time: 0, until: 100 }, 0, SR)
  check('no window at all: silent', peak(render(none, 0.1, 0).left), 0)
  const dc = voice.newVoiceState()
  voice.voiceCommand(dc, { type: 'window', channels: [new Float32Array(SR * 4).fill(0.6)], start: 0, rate: SR }, 0, SR)
  voice.voiceCommand(dc, { type: 'take', at: 1, rate: 1, time: 0, until: 100 }, 0, SR)
  const flat = render(dc, 1, 0)
  check('a constant, read at speed: the DC blocker takes it to silence, both channels from one', [peak(flat.left, SR / 2) < 1e-3, peak(flat.right, SR / 2) < 1e-3], [true, true])
}

console.log('\nit goes where it is driven, and stops when the drive does')
{
  const state = voice.newVoiceState()
  voice.voiceCommand(state, sine(30), 0, SR)
  voice.voiceCommand(state, { type: 'take', at: 14, rate: 0, time: 0, until: 100 }, 0, SR)
  //? a hand turning at 2.5x, posted 60 times a second as the page does
  let now = 0
  for (let frame = 0; frame < 60; frame++) {
    voice.voiceCommand(state, { type: 'drive', at: 14 + 2.5 * now, rate: 2.5, time: now, until: now + 0.12 }, now, SR)
    render(state, 1 / 60, now)
    now += 1 / 60
  }
  check('a second of a hand at 2.5x: where the hand is, to a few ms, at its speed', [near(state.pos, 14 + 2.5 * now, 0.005), near(state.rate, 2.5, 0.01)], [true, true])
  render(state, 0.4, now)
  check('the drive stops coming (a stalled page): it runs out by itself, still and silent - never a record left whirring', near(state.rate, 0, 1e-3), true)
  const behind = []
  for (const [v0, on] of [[4, false], [9, false], [9, true], [-3, true]]) {
    const plan = on ? platter.motor(20, v0, 425) : platter.coast(20, v0, 425)
    const follow = voice.newVoiceState()
    voice.voiceCommand(follow, sine(30), 0, SR)
    voice.voiceCommand(follow, { type: 'take', at: 20, rate: v0, time: 0, until: 0.12 }, 0, SR)
    now = 0
    let worst = 0
    while (now + 1 / 60 <= plan.duration) {
      const { x, v } = platter.planAt(plan, now)
      voice.voiceCommand(follow, { type: 'drive', at: x, rate: v, accel: platter.acceleration(v, on), time: now, until: now + 0.12 }, now, SR)
      render(follow, 1 / 60, now)
      now += 1 / 60
      worst = Math.max(worst, Math.abs(follow.pos - platter.planAt(plan, now).x))
    }
    //? within a millisecond of real time behind, at the speed it goes: the rate's smoothing, no more
    behind.push(worst <= 0.001 + Math.abs(v0) * 0.001)
  }
  check('a coast or a run back to speed, driven a frame at a time: what is heard is where the platter is, within a ms of real time all the way', behind, [true, true, true, true])
}

console.log('\nloudness: faded in, faded out, stopped')
{
  const state = voice.newVoiceState()
  voice.voiceCommand(state, sine(30), 0, SR)
  voice.voiceCommand(state, { type: 'take', at: 15, rate: 1, time: 0, until: 100 }, 0, SR)
  const start = render(state, 0.05, 0).left
  check('taken: faded in over a few ms, never switched on mid-wave', [Math.abs(start[0]) < 0.01, state.gain > 0.99], [true, true])
  voice.voiceCommand(state, { type: 'fade', seconds: 0.04 }, 0.05, SR)
  render(state, 0.04, 0.05)
  check('faded out over 40 ms: 35 dB down by then', state.gain < 0.02, true)
  voice.voiceCommand(state, { type: 'take', at: 16, rate: 1, time: 0.1, until: 100 }, 0.1, SR)
  render(state, 0.05, 0.1)
  voice.voiceCommand(state, { type: 'stop' }, 0.15, SR)
  render(state, 0.03, 0.15)
  check('stopped: silent within a few ms, nothing driven', [state.gain < 1e-3, state.driving], [true, false])
}

/* ===== the worklet, as the browser runs it ===== */

console.log('\nthe worklet: made from the same functions, it plays the very same samples')
{
  const source = voice.voiceWorkletSource()
  const registered = {}
  const posted = []
  class AudioWorkletProcessor { constructor() { this.port = { postMessage: (m) => posted.push(m), onmessage: null } } }
  const scope = { AudioWorkletProcessor, registerProcessor: (name, Processor) => { registered[name] = Processor }, sampleRate: SR, currentTime: 0, Math, Float32Array }
  vm.createContext(scope)
  vm.runInContext(source, scope)
  check('it registers the one processor, by the name the page asks for', Object.keys(registered), [voice.VOICE_PROCESSOR])
  const processor = new registered[voice.VOICE_PROCESSOR]()
  const direct = voice.newVoiceState()
  const say = (message) => { processor.port.onmessage({ data: message }); voice.voiceCommand(direct, message, scope.currentTime, SR) }
  say(sine(10))
  say({ type: 'take', at: 12, rate: 1, time: 0, until: 100 })
  let same = true
  const where = new Map()
  for (let block = 0; block < 400; block++) {
    if (block === 100) say({ type: 'drive', at: direct.pos, rate: -2, time: scope.currentTime, until: 100 })
    if (block === 250) say({ type: 'fade', seconds: 0.04 })
    const a = [new Float32Array(128), new Float32Array(128)], b = [new Float32Array(128), new Float32Array(128)]
    processor.process([], [a])
    voice.renderVoice(direct, b, 128, SR, scope.currentTime)
    where.set(scope.currentTime, direct.pos)
    if (a[0].some((v, i) => v !== b[0][i]) || a[1].some((v, i) => v !== b[1][i])) same = false
    scope.currentTime += 128 / SR
  }
  check('400 blocks through a take, a reversal and a fade: sample for sample what the functions give', same, true)
  const heard = posted.filter((m) => m.type === 'heard')
  check('it says where it is ~30 times a second: 32 times in 400 blocks of 128', [heard.length, Object.keys(heard[0] ?? {}).sort()], [32, ['gain', 'pos', 'rate', 'time', 'type']])
  check('...and what it says is exactly where it was', heard.every((report) => report.pos === where.get(report.time)), true)
  check('the three functions it is made of name nothing outside themselves (they run in a scope of their own)',
    [voice.newVoiceState, voice.voiceCommand, voice.renderVoice].map((fn) => /\b(exports|require|platter|turntable)\b/.test(fn.toString())), [false, false, false])
}

/* ===== the deck, against fakes ===== */

//? a clock, timers and frames the test moves on
let clock = 1000
let timers = []
let frames = []
let nextId = 1
const advance = (ms) => {
  const until = clock + ms
  for (;;) {
    timers.sort((a, b) => a.at - b.at)
    const due = timers.find((timer) => timer.at <= until)
    if (!due) break
    clock = due.at
    timers = timers.filter((timer) => timer !== due)
    due.run()
  }
  clock = until
}
const runFrames = (count = 1) => {
  for (let i = 0; i < count; i++) {
    clock += 16
    advanceTimersOnly()
    const now = frames
    frames = []
    for (const frame of now) frame.run(clock)
  }
}
function advanceTimersOnly() {
  for (;;) {
    timers.sort((a, b) => a.at - b.at)
    const due = timers.find((timer) => timer.at <= clock)
    if (!due) break
    timers = timers.filter((timer) => timer !== due)
    due.run()
  }
}
globalThis.performance = { now: () => clock }
globalThis.setTimeout = (run, ms = 0) => { const id = nextId++; timers.push({ id, at: clock + ms, run }); return id }
globalThis.clearTimeout = (id) => { timers = timers.filter((timer) => timer.id !== id) }
globalThis.requestAnimationFrame = (run) => { const id = nextId++; frames.push({ id, run }); return id }
globalThis.cancelAnimationFrame = (id) => { frames = frames.filter((frame) => frame.id !== id) }
let reduced = false
globalThis.matchMedia = () => ({ get matches() { return reduced }, addEventListener() {}, removeEventListener() {} })
globalThis.URL.createObjectURL = () => 'blob:deck-voice'

//? an audio context that records what is asked of it
const contexts = []
const portMessages = []
class FakeNode {
  constructor() { this.port = { postMessage: (message) => portMessages.push(message), onmessage: null } }
  connect() {}
  disconnect() {}
}
//? how the fake browser decodes: at once ('now'), 300 ms later ('slow'), when the test says ('held' - the
//? callbacks kept in `decodesHeld`), or refusing: the callback with null, with an Error, or by throwing
let decodeMode = 'now'
const decodesHeld = []
let decodes = 0
//? whether the worklet's module refuses to load
let workletFails = false
//? a window's bytes say how long it is (100 kB a second), so the decode gives back that much audio
const BYTES_A_SECOND = 100_000
class FakeContext {
  constructor() {
    this.state = 'suspended'
    this.currentTime = 0
    this.calls = []
    this.audioWorklet = { addModule: () => (workletFails ? Promise.reject(new Error('SyntaxError: Unexpected token')) : Promise.resolve()) }
    contexts.push(this)
  }
  addEventListener() {}
  resume() { this.calls.push('resume'); this.state = 'running'; return Promise.resolve() }
  suspend() { this.calls.push('suspend'); this.state = 'suspended'; return Promise.resolve() }
  close() { this.calls.push('close'); this.state = 'closed'; return Promise.resolve() }
  decodeAudioData(bytes, done, failed) {
    decodes++
    const length = Math.round((bytes.byteLength / BYTES_A_SECOND) * 48000)
    const buffer = { numberOfChannels: 2, sampleRate: 48000, length, getChannelData: () => new Float32Array(length) }
    if (decodeMode === 'null') return failed(null)
    if (decodeMode === 'error') return failed(new Error('EncodingError: Decoding failed'))
    if (decodeMode === 'throw') throw new TypeError('Not enough arguments')
    if (decodeMode === 'slow') return void setTimeout(() => done(buffer), 300)
    if (decodeMode === 'held') return void decodesHeld.push(() => done(buffer))
    done(buffer)
  }
}
globalThis.AudioContext = FakeContext
globalThis.AudioWorkletNode = FakeNode

//? deadwax, answering the window route - windows of `windowSeconds` (40, or less for a hi-res song cut
//? short by deadwax's budget), from where they were asked
const asked = []
let answer = 'window'
let windowSeconds = 40
globalThis.fetch = async (url) => {
  asked.push(String(url))
  if (answer === 'not flac') return { ok: false, status: 415, headers: { get: () => null }, json: async () => ({ detail: "it isn't a FLAC file" }) }
  if (answer === 'down') return { ok: false, status: 503, headers: { get: () => null }, json: async () => ({ detail: 'its MP4 couldn\'t be made just now', scope: 'song' }) }
  const at = Number(new URL(String(url), 'http://x').searchParams.get('at'))
  const seconds = windowSeconds
  return { ok: true, status: 200, headers: { get: (name) => (name === 'x-deadwax-window' ? `${Math.round(at * 44100)}/${Math.round(seconds * 44100)}/44100` : null) }, arrayBuffer: async () => new ArrayBuffer(seconds * BYTES_A_SECOND) }
}
const settle = () => new Promise((resolve) => setImmediate(resolve))

const deckModule = require(path.join(OUT, 'player/deck.js'))
const { Deck, wakeDeckAudio, deckReport, windowMargins } = deckModule

function fakeHost(overrides = {}) {
  const host = {
    calls: [], shown: [], angle: 0, at: 60, isPlaying: true, listeners: new Set(),
    song: () => ({ id: 'time', length: 425, flac: true, kind: 'FLAC' }),
    playing() { return this.isPlaying },
    position() { return this.at },
    onPosition(listener) { this.listeners.add(listener); return () => this.listeners.delete(listener) },
    hold() { this.calls.push('hold'); this.isPlaying = false },
    resume() { this.calls.push('resume'); this.isPlaying = true },
    turnFace(degrees) { this.angle = degrees },
    show(at, scrubbing) { this.shown.push(at === null ? null : [Math.round(at * 100) / 100, scrubbing]) },
    grabbed() { this.calls.push('grabbed') },
    moveTo(seconds) { this.at = seconds; for (const listener of [...this.listeners]) listener(seconds) },
    ...overrides,
  }
  for (const name of ['playing', 'position', 'onPosition', 'hold', 'resume', 'turnFace', 'show', 'grabbed', 'moveTo']) host[name] = host[name].bind(host)
  return host
}
const posted = (type) => portMessages.filter((message) => message.type === type)
//? the song playing on: its position told every `every` ms, as the element's timeupdate tells it
const play = async (host, seconds, every = 250) => {
  for (let t = 0; t < seconds * 1000; t += every) {
    advance(every)
    host.moveTo(host.at + every / 1000)
    await settle()
  }
}
//? a flick of the hand backwards, a turn a second for its last 100 ms, from the song at `from`
const flickBack = (deck, from = 60) => {
  for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, -(ms / 1000) * 2 * Math.PI, from - (ms / 1000) * SECONDS_PER_TURN)
  clock += 100
}

async function main() {
  console.log('\nthe audio context: made only in a gesture, suspended when hidden, closed when gone')
  {
    const host = fakeHost()
    const deck = new Deck(host)
    deck.setShowing(true)
    check('no context until a gesture asks for one: a press is .11\'s', [contexts.length, deck.live()], [0, false])
    wakeDeckAudio()
    await settle()
    check('wakeDeckAudio() - the record\'s tap, a release, the look button, the transport - makes it and resumes it', [contexts.length, contexts[0].calls, deck.live()], [1, ['resume'], true])
    wakeDeckAudio()
    check('...once: a second gesture finds it running and does nothing more', [contexts.length, contexts[0].calls], [1, ['resume']])
    deck.setShowing(false)
    await settle()
    check('hidden (the screen closed, the page in the background): suspended - nothing runs on a locked phone', [contexts[0].calls.at(-1), deck.live()], ['suspend', false])
    deck.setShowing(true)
    await settle()
    check('shown again: still suspended until the next gesture - never resumed by itself', [contexts[0].state, contexts[0].calls.length], ['suspended', 2])
    deckModule.resumeDeckAudio()
    await settle()
    check('resumeDeckAudio() (the mini player\'s tap opening the screen) resumes it', contexts[0].state, 'running')
    deck.destroy()
    check('gone: closed, and Info told no turntable shows', [contexts[0].calls.at(-1), deckReport()], ['close', null])
  }

  console.log('\nmounting on the song playing: told the same song, the deck keeps what it began')
  {
    const host = fakeHost()
    wakeDeckAudio()
    await settle()
    const deck = new Deck(host)
    const before = asked.length
    deck.setShowing(true)
    deck.songChanged(host.song().id)
    await settle()
    check('one window asked for, not one superseded by a second', asked.length - before, 1)
    deck.songChanged('next')
    await settle()
    check('a song that really changed asks again', asked.length - before, 2)
    deck.destroy()
  }

  console.log('\na press: a tap is a tap; the record is taken past a tap, or after resting longer than one')
  const fresh = async (overrides) => {
    const host = fakeHost(overrides)
    const deck = new Deck(host)
    deck.setShowing(true)
    deck.songChanged(host.song().id)
    wakeDeckAudio()
    await settle()
    await settle()
    await settle()
    return { host, deck }
  }
  {
    const { host, deck } = await fresh()
    check('the window asked for round the playhead as the turntable shows, on the grid, 40 s long', asked.at(-1), '/deadwax/navidrome/scrub/time?at=56&seconds=40')
    check('...decoded, and handed to the worklet: its stretch of the song', [round(posted('window').at(-1).start, 3), deckReport().window?.start, deckReport().window?.kind], [56, 56, 'FLAC'])
    deck.pressed(clock)
    advance(deckModule.HOLD_MS - 50)
    check('pressed: the song plays on for now - it may be a tap', [host.calls, deck.taken()], [[], false])
    deck.release(clock, 'up')
    advance(500)
    check('let go before HOLD_MS without moving: a tap - nothing taken, nothing paused, for the click to play or pause', [host.calls, deck.taken()], [[], false])
    deck.pressed(clock)
    advance(deckModule.HOLD_MS + 1)
    check('pressed and rested longer than a tap: the record is taken - the song paused through the host, and the click after it no tap',
      [host.calls, deck.taken(), deck.anchor()], [['hold', 'grabbed'], true, 60])
    const take = posted('take').at(-1)
    check('...the record\'s sound takes over where the song was, at its own speed (it was playing)', [take.at, take.rate], [60, 1])
    deck.release(clock, 'cancel')
    check('a cancel: nothing sought, and the song it paused plays on', host.calls.slice(-1), ['resume'])
    deck.destroy()
  }

  console.log('\nlet go of a playing record: back to speed, the song sought at the release and played at speed')
  {
    const { host, deck } = await fresh()
    deck.pressed(clock)
    const taken = deck.takeOver()
    check('taken by a move past a tap (Turntable calls takeOver): paused at once', [taken, host.calls], [60, ['hold']])
    //? a flick backwards, a turn a second for the last 100 ms
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, -(ms / 1000) * 2 * Math.PI, 60 - (ms / 1000) * SECONDS_PER_TURN)
    clock += 100
    const at = 60 - 0.1 * SECONDS_PER_TURN
    const speed = platter.handSpeed([{ time: clock - 100, turned: 0 }, { time: clock, turned: -0.1 * 2 * Math.PI }], clock)
    const plan = platter.motor(at, speed, 425)
    const released = deck.release(clock, 'up')
    check('the release says where to seek - where the motor has it back at speed - now; and not to play yet: there is a coast',
      [round(released.seek, 6), released.play], [round(plan.x, 6), false])
    check('...from backwards: later than the hand let go of it - stopped, then pulled up',
      [round(plan.duration, 3), plan.x < at], [round(Math.log(1 + (platter.FRICTION_VISCOUS * -speed) / (platter.MOTOR_PULL + platter.FRICTION_DRY)) / platter.FRICTION_VISCOUS + platter.SPIN_UP_S, 3), true])
    runFrames(3)
    const drive = posted('drive').at(-1)
    check('the record\'s sound follows the coast, a frame at a time', [drive.rate < 1, drive.until > drive.time], [true, true])
    check('...and the time line shows where it is, scrubbing', host.shown.at(-1)[1], true)
    advance(plan.duration * 1000 - 50)
    check('not at speed yet: the song still paused', host.calls, ['hold'])
    advance(60)
    check('at speed: the song plays (after the tap - the player\'s own toggle, through the host)', host.calls, ['hold', 'resume'])
    const hold = posted('drive').at(-1)
    check('...and the record\'s sound holds speed 1 from there until the song is really playing', [hold.rate, round(hold.at, 6), hold.until - hold.time], [1, round(plan.x, 6), deckModule.HANDOVER_MAX_S])
    const fades = posted('fade').length
    host.moveTo(plan.x + 0.01)
    check('the song\'s clock not moving yet: no fade', posted('fade').length, fades)
    host.moveTo(plan.x + 0.05)
    check('really playing: the record\'s sound fades out over a few tens of ms', [posted('fade').length - fades, posted('fade').at(-1).seconds], [1, deckModule.HANDOVER_FADE_S])
    deck.destroy()
  }

  console.log('\nlet go of a paused record: it coasts to a stop, sought there, and stays paused')
  {
    const { host, deck } = await fresh({ isPlaying: false })
    deck.pressed(clock)
    deck.takeOver()
    check('a paused song isn\'t paused again', host.calls, [])
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, (ms / 1000) * 4 * Math.PI, 60 + (ms / 1000) * 2 * SECONDS_PER_TURN)
    clock += 100
    const at = 60 + 0.2 * SECONDS_PER_TURN
    const plan = platter.coast(at, platter.handSpeed([{ time: clock - 100, turned: 0 }, { time: clock, turned: 0.4 * Math.PI }], clock), 425)
    const released = deck.release(clock, 'up')
    check('sought now to where it will stop', [round(released.seek, 6), released.play], [round(plan.x, 6), false])
    advance(plan.duration * 1000 + 100)
    check('...it stops there, and nothing plays it', host.calls, [])
    check('...the record\'s sound stopped with it', posted('stop').length > 0, true)
    deck.destroy()
  }

  console.log('\nthe song changes under a coast back to speed (Next mid-coast): the coast dropped - and the next song plays')
  {
    const { host, deck } = await fresh()
    deck.pressed(clock)
    deck.takeOver()
    deck.hand(clock + 50, 1, 61)
    clock += 60
    deck.release(clock, 'up')
    const stops = posted('stop').length
    deck.songChanged('next')
    check('the coast\'s sound stops at once', posted('stop').length > stops, true)
    advance(deckModule.SONG_CHANGE_SETTLE_MS - 20)
    check('...and the next song - loaded paused, as the hand had paused this one - waits a moment for a play of its own', host.calls, ['hold'])
    advance(40)
    check('...then, nothing having played it, is played: the hand only scrubbed', host.calls, ['hold', 'resume'])
    advance(3000)
    check('...and nothing more is done for the song before when its coast would have ended', host.calls, ['hold', 'resume'])
    deck.destroy()
    //? a song started some other way in that moment (a tap in Search) is playing already: never toggled
    const elsewhere = await fresh()
    elsewhere.deck.pressed(clock)
    elsewhere.deck.takeOver()
    elsewhere.deck.hand(clock + 50, 1, 61)
    clock += 60
    elsewhere.deck.release(clock, 'up')
    elsewhere.deck.songChanged('chosen')
    elsewhere.host.isPlaying = true
    advance(3000)
    check('a song started some other way as the coast ran (its own play): left playing - nothing toggled', elsewhere.host.calls, ['hold'])
    elsewhere.deck.destroy()
    //? a tap in that moment plays it itself (the click asks resuming() first): nothing toggles after it
    const tapped = await fresh()
    tapped.deck.pressed(clock)
    tapped.deck.takeOver()
    tapped.deck.hand(clock + 50, 1, 61)
    clock += 60
    tapped.deck.release(clock, 'up')
    tapped.deck.songChanged('next')
    advance(100)
    check('a play tapped a moment after: the deck has no seek to ask', tapped.deck.resuming(), null)
    advance(3000)
    check('...and plays nothing over the tap\'s own play', tapped.host.calls, ['hold'])
    tapped.deck.destroy()
    //? the record grabbed in that moment: taken as a song meant to play, so let go it plays at speed
    const grabbed = await fresh()
    grabbed.deck.pressed(clock)
    grabbed.deck.takeOver()
    grabbed.deck.hand(clock + 50, 1, 61)
    clock += 60
    grabbed.deck.release(clock, 'up')
    grabbed.deck.songChanged('next')
    advance(100)
    grabbed.deck.pressed(clock)
    grabbed.deck.takeOver()
    const regrabbed = grabbed.deck.release(clock + 300, 'up')
    advance(1000)
    check('the record grabbed a moment after: let go, it is brought to speed and played', [regrabbed.play, grabbed.host.calls], [false, ['hold', 'resume']])
    grabbed.deck.destroy()
    const paused = await fresh({ isPlaying: false })
    paused.deck.pressed(clock)
    paused.deck.takeOver()
    paused.deck.hand(clock + 50, 1, 61)
    clock += 60
    paused.deck.release(clock, 'up')
    paused.deck.songChanged('next')
    advance(3000)
    check('a paused song\'s coast, the song changing under it: nothing played', paused.host.calls, [])
    paused.deck.destroy()
    const held = await fresh()
    held.deck.pressed(clock)
    held.deck.takeOver()
    held.deck.songChanged('next')
    advance(deckModule.SONG_CHANGE_SETTLE_MS + 20)
    check('a playing song held under the finger as the song changes: the next one plays too', held.host.calls, ['hold', 'resume'])
    held.deck.destroy()
  }

  console.log('\nthe turntable going mid-coast (the look switched to the cover): the song plays on from where it was sought')
  {
    const { host, deck } = await fresh()
    deck.pressed(clock)
    deck.takeOver()
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, -(ms / 1000) * 2 * Math.PI, 60 - (ms / 1000) * SECONDS_PER_TURN)
    clock += 100
    deck.release(clock, 'up')
    advance(200)
    deck.destroy()
    check('gone 0.2 s into a coast back to speed: the song played, not left paused', host.calls, ['hold', 'resume'])
    advance(10_000)
    check('...once', host.calls, ['hold', 'resume'])
    const paused = await fresh({ isPlaying: false })
    paused.deck.pressed(clock)
    paused.deck.takeOver()
    paused.deck.hand(clock + 50, 1, 61)
    clock += 60
    paused.deck.release(clock, 'up')
    paused.deck.destroy()
    check('a paused song\'s coast: it stays paused', paused.host.calls, [])
  }

  console.log('\na pause on the turntable winds down - with the setting on, and the window there')
  {
    const { host, deck } = await fresh()
    const takes = posted('take').length
    const landing = deck.pausing()
    const plan = platter.coast(60, 1, 425)
    check('it says where the wind-down stops, for the song to be sought there, and the sound starts at speed 1 where the song is',
      [round(landing, 6), posted('take').length - takes, posted('take').at(-1).at, posted('take').at(-1).rate], [round(plan.x, 6), 1, 60, 1])
    runFrames(5)
    check('...winding down with the platter: slower each frame', posted('drive').at(-1).rate < 1, true)
    deck.destroy()
    const off = await fresh()
    off.deck.setWindDown(false)
    const before = posted('take').length
    check('the setting off: a plain pause, nothing sought, no sound', [off.deck.pausing(), posted('take').length - before], [null, 0])
    off.deck.destroy()
    answer = 'down'
    const away = await fresh({ at: 200 })
    check('no window (deadwax couldn\'t send one): a plain pause, never a wait - and the failure said', [away.deck.pausing(), deckReport().failed], [null, "deadwax didn't send it - its MP4 couldn't be made just now"])
    answer = 'window'
    away.deck.destroy()
  }

  console.log('\nreduced motion: the record lands at once, and a playing song plays from there in the release')
  {
    reduced = true
    const { host, deck } = await fresh()
    deck.pressed(clock)
    deck.takeOver()
    deck.hand(clock + 50, 2, 62)
    clock += 60
    const released = deck.release(clock, 'up')
    check('the landing worked out as ever - and played in this very gesture, no coast to wait for', [released.seek !== null, released.play], [true, true])
    check('...nothing winds down', deck.pausing(), null)
    deck.destroy()
    reduced = false
  }

  console.log('\nthe window: round the playhead, kept ready, never for what isn\'t a FLAC')
  {
    const { host, deck } = await fresh()
    const before = asked.length
    host.moveTo(85)
    check('the playhead inside the window, well short of its end: nothing asked', asked.length, before)
    host.moveTo(91)
    await settle()
    check('within REFRESH_AHEAD_S of its end: the next asked, from a little before the playhead, on the grid', asked.slice(before), ['/deadwax/navidrome/scrub/time?at=86&seconds=40'])
    deck.destroy()
    answer = 'not flac'
    const refused = await fresh()
    await settle()
    const tries = asked.length
    refused.host.moveTo(100)
    await settle()
    check('a 415: said, in deadwax\'s words, and not asked again', [deckReport().refused, asked.length], ["it isn't a FLAC file", tries])
    refused.deck.destroy()
    answer = 'window'
    const mp3 = await fresh({ song: () => ({ id: 'mp3', length: 200, flac: false, kind: 'MP3' }) })
    check('a song that isn\'t a FLAC is never asked for: the turntable is silent for it, and says why', [asked.some((url) => url.includes('/mp3')), deckReport().refused], [false, "it isn't a FLAC file (it is MP3)"])
    mp3.deck.destroy()
  }

  console.log('\nthe platter: turned frame by frame while it plays, and only while it shows')
  {
    const { host, deck } = await fresh()
    runFrames(10)
    check('playing: it turns', host.angle > 0, true)
    const before = host.angle
    runFrames(5)
    check('...at its own speed: 80 ms on, 16 degrees on - 200 a second, a turn in 1.8 s', round(host.angle - before, 3), 16)
    deck.setShowing(false)
    const waiting = frames.length
    check('hidden: no frame asked for', waiting, 0)
    host.isPlaying = false
    deck.playingChanged(false)
    advance(deckModule.PAUSE_SETTLE_MS + 50)
    deck.songChanged('next')
    check('...nor while hidden as the song pauses (the spin-down begins) or changes', frames.length, 0)
    deck.destroy()
  }


  console.log('\nno window asked for until there is somewhere to put it - and one on its way never asked again')
  {
    //? no audio context: Now Playing opened onto the turntable from the mini player, no tap since
    const host = fakeHost()
    const deck = new Deck(host)
    deck.setShowing(true)
    const before = asked.length
    await play(host, 5)
    check('showing, playing, no tap yet: nothing asked in 5 s of play (review: a 40 s window every 2 s)', [asked.length - before, deckReport().context, deckReport().loading], [0, 'none', false])
    wakeDeckAudio()
    await settle()
    await settle()
    await settle()
    check('...the first tap starts the sound, and the window is asked for then - once', [asked.length - before, deckReport().window?.start], [1, 60])
    deck.destroy()
  }
  {
    workletFails = true
    const host = fakeHost()
    const deck = new Deck(host)
    deck.setShowing(true)
    wakeDeckAudio()
    await settle()
    const before = asked.length, decoded = decodes
    await play(host, 5)
    check('the worklet that plays it wouldn\'t load: nothing asked, nothing decoded - and Debug says why', [asked.length - before, decodes - decoded, deckReport().context], [0, 0, 'failed'])
    deck.destroy()
    workletFails = false
  }
  {
    decodeMode = 'slow'
    const before = asked.length
    const { host, deck } = await fresh()
    await play(host, 1.5)
    check('a decode slower than the position\'s ticks (300 ms): asked once, not again while it decodes', [asked.length - before, deckReport().window?.start], [1, 56])
    decodeMode = 'now'
    deck.destroy()
  }
  {
    decodeMode = 'held'
    decodesHeld.length = 0
    const { host, deck } = await fresh({ isPlaying: false })
    deck.pressed(clock)
    deck.takeOver()
    await settle()
    deck.hand(clock + 10, 30, 120)
    await settle()
    check('a window being decoded, and the hand gone far past it: the one it is in now asked for', asked.slice(-2), ['/deadwax/navidrome/scrub/time?at=56&seconds=40', '/deadwax/navidrome/scrub/time?at=116&seconds=40'])
    decodesHeld[1]()
    decodesHeld[0]()
    check('...the older decode landing last never replaces the newer (only the newest counts)', [posted('window').at(-1).start, deckReport().window?.start], [116, 116])
    decodeMode = 'now'
    deck.release(clock, 'cancel')
    deck.destroy()
  }
  {
    decodeMode = 'held'
    decodesHeld.length = 0
    const before = asked.length
    const { host, deck } = await fresh()
    deck.setShowing(false)
    deck.setShowing(true)
    await settle()
    check('a window being decoded as the screen closes and opens again: kept, not asked for again', asked.length - before, 1)
    decodesHeld[0]()
    check('...and handed on when its decode lands', deckReport().window?.start, 56)
    decodeMode = 'now'
    deck.destroy()
  }

  console.log('\na hi-res song\'s windows, cut short by deadwax\'s budget: the margins shrink, so each still moves on')
  {
    const scaled = windowMargins(13)
    check('the margins for a whole window, and in proportion for a 13 s one', [windowMargins(40), round(scaled.back, 6), round(scaled.ahead, 6)], [{ back: 4, ahead: 6 }, 1.3, 1.95])
    const counts = []
    const starts = []
    for (const seconds of [40, 21, 13]) {
      windowSeconds = seconds
      const before = asked.length
      const { host, deck } = await fresh()
      await play(host, 60)
      counts.push(asked.length - before)
      starts.push(asked.slice(before).map((url) => Number(new URL(url, 'http://x').searchParams.get('at'))))
      deck.destroy()
    }
    windowSeconds = 40
    check('a minute of play: 2 windows of 40 s, 5 of 21 s, 8 of 13 s (review: 29 a minute of 13 s, about 230 MB) - about a third more than the song either way',
      counts, [2, 5, 8])
    check('...each starting further on than the last', starts.map((list) => list.every((at, i) => i === 0 || at > list[i - 1])), [true, true, true])
    //? windows of 2 s (a budget nothing real comes near): a refresh must still move on from the window it
    //? has - never the same window asked again and again while the playhead sits in it
    windowSeconds = 2
    const tinyBefore = asked.length
    const tiny = await fresh()
    await play(tiny.host, 10)
    const tinyAsked = asked.slice(tinyBefore)
    check('windows of 2 s: none asked twice, each further on', [new Set(tinyAsked).size === tinyAsked.length, tinyAsked.length <= 12], [true, true])
    tiny.deck.destroy()
    windowSeconds = 40
    const capped = await fresh({ song: () => ({ id: 'hires', length: 425, flac: true, kind: 'FLAC', maxRate: 48000 }) })
    check('a hi-res song played resampled: its window asked at the same cap, so it is cut from the copy the song plays from',
      asked.at(-1), '/deadwax/navidrome/scrub/hires?at=56&seconds=40&max_rate=48000')
    capped.deck.destroy()
  }

  console.log('\na flick back past the window\'s start: the window it runs into is asked for at the release')
  {
    const { host, deck } = await fresh()
    deck.pressed(clock)
    deck.takeOver()
    //? back from 1:00 to 0:57.5, then a hard flick on back
    for (let ms = 0; ms <= 500; ms += 20) deck.hand(clock + ms, ((-2.5 * ms) / 500 / SECONDS_PER_TURN) * 2 * Math.PI, 60 - (2.5 * ms) / 500)
    for (let ms = 520; ms <= 600; ms += 20) {
      const at = 57.5 - (1.1 * (ms - 500)) / 100
      deck.hand(clock + ms, ((at - 60) / SECONDS_PER_TURN) * 2 * Math.PI, at)
    }
    clock += 600
    const before = asked.length
    const released = deck.release(clock, 'up')
    const plan = platter.motor(57.5 - 1.1, platter.handSpeed([{ time: clock - 80, turned: ((57.5 - 0.88 - 60) / SECONDS_PER_TURN) * 2 * Math.PI }, { time: clock, turned: ((56.4 - 60) / SECONDS_PER_TURN) * 2 * Math.PI }], clock), 425)
    const lowest = Math.min(...plan.phases.map((phase) => platter.phaseAt(phase, phase.duration).x))
    const asking = Number(new URL(asked.at(-1), 'http://x').searchParams.get('at'))
    check('it runs back below where the window starts (0:56) - and the one that covers it is asked at once, before a frame has run',
      [lowest < 56, asked.length - before, asking <= lowest, released.seek !== null], [true, 1, true, true])
    await settle()
    check('...and handed to the record\'s sound as it coasts, its sound carrying on from there', [posted('window').at(-1).start, posted('window').at(-1).start <= lowest], [asking, true])
    deck.destroy()
  }

  {
    //? the same with the song paused: the coast, under friction alone, runs back further still
    const { host, deck } = await fresh({ isPlaying: false })
    deck.pressed(clock)
    deck.takeOver()
    await settle()
    for (let ms = 0; ms <= 500; ms += 20) deck.hand(clock + ms, ((-2.5 * ms) / 500 / SECONDS_PER_TURN) * 2 * Math.PI, 60 - (2.5 * ms) / 500)
    for (let ms = 520; ms <= 600; ms += 20) {
      const at = 57.5 - (1.1 * (ms - 500)) / 100
      deck.hand(clock + ms, ((at - 60) / SECONDS_PER_TURN) * 2 * Math.PI, at)
    }
    clock += 600
    const before = asked.length
    const released = deck.release(clock, 'up')
    const asking = Number(new URL(asked.at(-1), 'http://x').searchParams.get('at'))
    check('a paused record flicked back past the window\'s start: the window it coasts into asked at the release',
      [released.seek < 56, asked.length - before, asking <= released.seek], [true, 1, true])
    deck.destroy()
  }

  console.log('\nthe song sought by something else mid-coast (Previous restarting it, a key on the arm)')
  {
    const { host, deck } = await fresh()
    deck.pressed(clock)
    deck.takeOver()
    flickBack(deck)
    const released = deck.release(clock, 'up')
    host.moveTo(released.seek)
    runFrames(2)
    const stops = posted('stop').length, drives = posted('drive').length, fades = posted('fade').length
    //? Previous more than 3 s in: the same song, restarted - paused - at 0:00
    host.moveTo(0)
    check('the record\'s sound stops, and the coast is shown no more', [posted('stop').length - stops, host.shown.at(-1)], [1, null])
    runFrames(3)
    check('...nor driven, frame after frame', posted('drive').length, drives)
    advance(5000)
    check('at the coast\'s end the song plays from where it was put - and the record\'s sound never holds speed 1 over it', [host.calls, posted('drive').length, posted('fade').length - fades], [['hold', 'resume'], drives, 0])
    deck.destroy()
  }
  {
    const { host, deck } = await fresh()
    deck.pressed(clock)
    deck.takeOver()
    flickBack(deck)
    const released = deck.release(clock, 'up')
    host.moveTo(released.seek)
    advance(3000)
    const fades = posted('fade').length
    host.moveTo(10)
    check('the handover under way and the song turning up somewhere else as it starts: the record\'s sound fades at once', posted('fade').length - fades, 1)
    deck.destroy()
  }

  console.log('\na play iOS refuses at speed ("Tap play to start"): the platter spins down, not turning beside a paused song')
  {
    const { host, deck } = await fresh({ resume() { this.calls.push('resume (refused)') } })
    deck.pressed(clock)
    deck.takeOver()
    flickBack(deck)
    deck.release(clock, 'up')
    advance(3000)
    check('played at speed - and refused', [host.calls, host.isPlaying], [['hold', 'resume (refused)'], false])
    runFrames(200)
    const still = host.angle
    runFrames(10)
    check('...spun down and stopped: no more frames asked for, the record still', [host.angle === still, frames.length], [true, 0])
    deck.destroy()
  }

  console.log('\na press the deck doesn\'t take (before its sound runs): the record stops under the finger, as .11\'s did')
  {
    const host = fakeHost()
    const deck = new Deck(host)
    deck.setShowing(true)
    runFrames(5)
    deck.holdStill(true)
    const held = host.angle
    runFrames(30)
    check('held: not a degree further, and no frame asked for while it rests', [host.angle, frames.length], [held, 0])
    deck.holdStill(false)
    runFrames(1)
    check('let go: it turns on from where it was held - a frame\'s worth, no jump', round(host.angle - held, 3), 3.2)
    deck.destroy()
  }

  console.log('\nthe wind-down follows what is heard: from the song\'s own speed, and a play mid-way from where it got to')
  {
    const { host, deck } = await fresh()
    host.isPlaying = false
    deck.playingChanged(false)
    advance(deckModule.PAUSE_SETTLE_MS + 1100)
    host.isPlaying = true
    deck.playingChanged(true)
    advance(150)
    const landing = deck.pausing()
    check('paused 0.15 s into the spin-up: the sound winds down from the song\'s speed - which is what was heard - not the third of it the platter had reached',
      [posted('take').at(-1).rate, round(landing, 6)], [1, round(platter.coast(60, 1, 425).x, 6)])
    host.isPlaying = false
    host.moveTo(landing)
    advance(100)
    const stops = posted('stop').length
    const from = deck.resuming()
    check('a play 0.1 s into the wind-down: from where the record is, what was heard - not the wind-down\'s end',
      [round(from, 6), from < landing], [round(platter.planAt(platter.coast(60, 1, 425), 0.1).x, 6), true])
    host.moveTo(from)
    check('...the seek to it is the deck\'s own: nothing taken for the song moved elsewhere', posted('stop').length, stops)
    deck.destroy()
    //? the same on a paused record flicked hard forward, 0.1 s into a coast that lands seconds on: the
    //? play's seek, far from the landing, is the deck's own - its sound stops only as the song plays
    const flung = await fresh({ isPlaying: false })
    flung.deck.pressed(clock)
    flung.deck.takeOver()
    await settle()
    for (let ms = 0; ms <= 100; ms += 10) flung.deck.hand(clock + ms, (ms / 1000) * 10 * Math.PI, 60 + (ms / 1000) * 5 * SECONDS_PER_TURN)
    clock += 100
    const released = flung.deck.release(clock, 'up')
    flung.host.moveTo(released.seek)
    advance(100)
    runFrames(1)
    const flungStops = posted('stop').length
    const flungFrom = flung.deck.resuming()
    flung.host.moveTo(flungFrom)
    runFrames(1)
    check('a play 0.1 s into a hard coast: from where the record is, seconds short of the landing - and still sounding, still shown',
      [released.seek - flungFrom > 1, posted('stop').length - flungStops, flung.host.shown.at(-1)?.[1]], [true, 0, true])
    flung.deck.destroy()
    const silent = await fresh()
    silent.deck.setWindDown(false)
    silent.deck.pausing()
    advance(100)
    check('a wind-down without its sound (the switch off): the song is where it paused - nothing to seek on a play', silent.deck.resuming(), null)
    silent.deck.destroy()
  }

  console.log('\nthe arm taken while the record coasts: no sound, and nothing shown of the coast from then')
  {
    const { host, deck } = await fresh({ isPlaying: false })
    deck.pressed(clock)
    deck.takeOver()
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, (ms / 1000) * 4 * Math.PI, 60 + (ms / 1000) * 2 * SECONDS_PER_TURN)
    clock += 100
    deck.release(clock, 'up')
    runFrames(2)
    check('coasting: its place shown, scrubbing', host.shown.at(-1)?.[1], true)
    deck.armTaken()
    const shown = host.shown.length
    runFrames(5)
    check('the arm taken: shown no more - the arm shows where the finger has it', [host.shown.at(-1), host.shown.length], [null, shown])
    check('...and a play now is from where the arm puts it: the deck asks no seek', deck.resuming(), null)
    deck.destroy()
  }

  console.log('\nreview: what the docs say of the deck, held')
  {
    const { host, deck } = await fresh()
    deck.pressed(clock)
    advance(deckModule.HOLD_MS + 1)
    const released = deck.release(clock, 'up')
    check('rested past a tap and let go without a turn: sought 0.2 s on - where the spin-up has the platter at speed - and not played yet',
      [round(released.seek, 6), released.play], [60.2, false])
    advance(platter.SPIN_UP_S * 1000 - 20)
    check('...not at speed yet', host.calls, ['hold', 'grabbed'])
    advance(40)
    check('...played at speed, 0.4 s on', host.calls, ['hold', 'grabbed', 'resume'])
    deck.destroy()
  }
  {
    const { host, deck } = await fresh()
    deck.pressed(clock)
    deck.takeOver()
    flickBack(deck)
    const first = deck.release(clock, 'up')
    advance(200)
    deck.pressed(clock)
    advance(deckModule.HOLD_MS + 1)
    const caught = deck.anchor()
    const again = deck.release(clock, 'up')
    check('caught on its way back to speed and let go: sought where the motor lands it from where it was caught, not the first landing',
      [round(again.seek, 6), round(again.seek, 3) !== round(first.seek, 3), again.play], [round(caught + 0.2, 6), true, false])
    advance(500)
    check('...and played at speed: the song was meant to play', host.calls, ['hold', 'grabbed', 'resume'])
    deck.destroy()
  }
  {
    const { host, deck } = await fresh()
    deck.pressed(clock)
    deck.takeOver()
    //? a hand at about the record's own speed
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, (0.99 * ms / 1000 / SECONDS_PER_TURN) * 2 * Math.PI, 60 + 0.99 * ms / 1000)
    clock += 100
    const released = deck.release(clock, 'up')
    check('let go at about its own speed (a coast back of RESUME_IN_GESTURE_S or less): played in the release\'s own gesture', [released.play, host.calls], [true, ['hold']])
    deck.destroy()
  }
  {
    const { host, deck } = await fresh()
    host.at = 95.9
    const takes = posted('take').length
    check('a pause whose wind-down would run past the window\'s end (0:96): a plain pause, never a wait', [deck.pausing(), posted('take').length - takes], [null, 0])
    deck.destroy()
  }
  {
    const { host, deck } = await fresh()
    runFrames(2)
    host.isPlaying = false
    deck.playingChanged(false)
    const before = host.angle
    runFrames(10)
    check('paused by something else: for PAUSE_SETTLE_MS it turns on at its own speed (a song change pauses for a moment)', round(host.angle - before, 3), 32)
    runFrames(100)
    const still = host.angle
    runFrames(5)
    check('...then spins down and stops', [host.angle === still, frames.length], [true, 0])
    deck.destroy()
  }
  {
    answer = 'down'
    const { host, deck } = await fresh()
    const tries = asked.length
    await play(host, 9)
    check('a window deadwax couldn\'t send: not asked again for RETRY_MS', asked.length, tries)
    await play(host, 1.5)
    check('...then asked again, once', asked.length - tries, 1)
    answer = 'window'
    deck.destroy()
  }
  for (const [mode, words] of [['null', 'it gave no reason'], ['error', 'EncodingError: Decoding failed'], ['throw', 'Not enough arguments']]) {
    decodeMode = mode
    const { host, deck } = await fresh()
    const tries = asked.length
    await play(host, 15)
    check(`a window this browser can't decode (${mode === 'null' ? 'the callback given null' : mode === 'error' ? 'its error' : 'thrown'}): said in its words, and never asked again`,
      [deckReport().refused, asked.length - tries], [`this browser couldn't decode its window - ${words}`, 0])
    deck.destroy()
  }
  decodeMode = 'now'
  {
    const before = asked.length
    const { host, deck } = await fresh({ isPlaying: false })
    await play(host, 5)
    check('a paused song, the turntable showing: nothing asked until it plays or the record is turned', asked.length, before)
    deck.destroy()
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
