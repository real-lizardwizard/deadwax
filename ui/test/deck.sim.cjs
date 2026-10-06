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
 *  - THE SOUND ON A PAGE THAT ISN'T HTTPS (2.0.0-player.16): with no AudioWorklet (an insecure page),
 *    or one whose module is refused, the voice is a ScriptProcessorNode on the main thread - no inputs,
 *    two output channels, 1024 a block, connected to the speakers - running the very same functions
 *    (they are called: spied on, and its output held sample for sample to them fed the same messages),
 *    saying where it is as often as the worklet; ready once it has played a block. A press is the
 *    deck's (`live()`) only when the record can sound there: the context running, a voice ready AND a
 *    window covering it in the voice - not with no voice, a worklet still loading, a window still
 *    decoding, or none; a press it doesn't take asks for the window, so the next can be. With neither
 *    host, nothing is asked. The page's audio session is 'playback' from the wake until the turntable
 *    goes, then put back; where there is none, nothing is touched.
 *  - ITS REVIEW: a take applied after it was said starts where the record is by then; on the main
 *    thread, with the page's frames and the browser's blocks on one clock, a wind-down and a grab -
 *    either first - never read faster than the song, and a grab held still never swings far back
 *    (messages held to the next block, heard SCRIPT_LAG_BLOCKS blocks on, a window replacing every
 *    window before it); a coast or a run back to speed out of its window
 *    still the deck's - caught where the platter is, nothing played under the hand, sounded as the
 *    window lands; a press that IS .11's ending whatever the deck had going (a silent wind-down, a
 *    coast whose context a hide suspended - no leap at the release, the run back to speed's song
 *    played, its sound stopped); the first turn of a paused song before any tap asking once there is a
 *    voice, and only once; a hide while a tap's resume settles suspending it as it runs - but not the
 *    mini player's tap, nor a hide undone before it settled; each audio-session wake held to a context
 *    of its own.
 *  - THE RECORD'S SOUND FOLLOWS THE HAND (2.0.0-player.24): the voice plays its path HAND_DELAY_S behind
 *    - a take, a drive and a coast all heard that much later (the checks above say where); the release's
 *    speed taken by the samples' own times, up to the last of them (a still tail of RELEASE_TAIL_MS is no
 *    slowing, a rest is, a whole window of one no flick at all); and on the main thread every sample of a
 *    hand applied in order, its own time kept and the lag added - none replacing another. ITS REVIEW: a
 *    frame begun before the release (or the tap) it follows drives nothing; a window landing under the
 *    hand starts its path at the hand's last sample, not when it landed; and on the main thread every
 *    frame's drive of a coast is applied too, in order, as the worklet keeps each one. ITS SECOND REVIEW:
 *    the clock read on the deck's own timer while the turntable shows and its context runs, the record
 *    still too - started by a deck mounting on a context already running, quick only for its first
 *    CLOCK_SETTLE_TICKS readings while the mapping is young (a clock that never moves read slowly), slow
 *    once settled, stopped at the hide while a real suspend still settles, and gone with its deck (a
 *    grab on the next held through every reading).
 *    ui/test/decksound.sim.cjs listens to the result, and ui/test/deckclock.sim.cjs holds the clock.
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

console.log('\nthe release\'s speed (2.0.0-player.24): by the samples\' own times - a still tail is no slowing, a rest is')
{
  const turnPerSecond = (time) => ({ time, turned: (time / 1000) * 2 * Math.PI })
  const steady = [0, 16, 32, 48, 64, 80, 96, 112, 128].map(turnPerSecond)
  check('let go 30 ms after the last sample - a finger moving to the last sends its last move up to a frame before it lifts: the full speed, 1.8 (taken up to the release, 1.2 - a third slower)',
    [platter.RELEASE_TAIL_MS, round(platter.releaseSpeed(steady, 128 + 30), 6), round(platter.handSpeed(steady, 128 + 30), 6)], [40, 1.8, 1.2])
  check('...at the last sample itself, or a tail of RELEASE_TAIL_MS: the full speed', [round(platter.releaseSpeed(steady, 128), 6), round(platter.releaseSpeed(steady, 128 + 40), 6)], [1.8, 1.8])
  check('a finger that rested past the tail: slower in proportion - half way from the tail to a whole window, half the speed', round(platter.releaseSpeed(steady, 128 + 65), 6), 0.9)
  check('...a rest of the whole window (VELOCITY_WINDOW_MS) or more: no flick at all', [platter.releaseSpeed(steady, 128 + 90), platter.releaseSpeed(steady, 128 + 400)], [0, 0])
  check('...backwards the same; one sample, or none: no speed',
    [round(platter.releaseSpeed(steady.map((sample) => ({ ...sample, turned: -sample.turned })), 128 + 30), 6), platter.releaseSpeed([{ time: 0, turned: 0 }], 30), platter.releaseSpeed([], 30)], [-1.8, 0, 0])
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

//? the voice plays its path this far behind (2.0.0-player.24): the record's sound is that much later
//? than the hand, the coast, the wind-down - a constant
const DELAY = voice.HAND_DELAY_S

console.log('\nthe voice: its position is the sum of its rate')
{
  const state = voice.newVoiceState()
  check('it plays its path HAND_DELAY_S (120 ms since 2.0.0-player.27, 50 before) behind - the literal in newVoiceState, the voice naming nothing outside itself', [DELAY, state.delay], [0.12, 0.12])
  voice.voiceCommand(state, sine(30), 0, SR)
  voice.voiceCommand(state, { type: 'take', at: 12, rate: 1, time: 0, until: 100 }, 0, SR)
  render(state, 1, 0)
  check('at speed 1 for a second, taken at its own speed: a second on, exactly - from where the record was the delay before the take', round(state.pos, 9), round(13 - DELAY, 9))
  voice.voiceCommand(state, { type: 'drive', at: 13, rate: -1, time: 1, until: 100 }, 1, SR)
  render(state, 2, 1)
  check('then backwards at -1 for two: back past where it started, where the drive has the record the delay before', near(state.pos, 11 + DELAY, 1e-3), true)
  const free = voice.newVoiceState()
  voice.voiceCommand(free, sine(30), 0, SR)
  voice.voiceCommand(free, { type: 'take', at: 20, rate: 0.75, time: 0, until: 0.05 }, 0, SR)
  let summed = free.pos
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
  //? where the record is on the path at 0.2 - the voice is the delay behind it - turned to -1 there
  voice.voiceCommand(state, { type: 'drive', at: state.pos + DELAY, rate: -1, time: t, until: 100 }, t, SR)
  for (let i = 0; i < 2400 + DELAY * SR; i++) {
    voice.renderVoice(state, [new Float32Array(1), new Float32Array(1)], 1, SR, t)
    rates.push(state.rate)
    t += 1 / SR
  }
  const steps = rates.slice(1).map((r, i) => Math.abs(r - rates[i]))
  check('1 to -1 in an instant: the rate it reads at moves no more than a few thousandths a sample', Math.max(...steps) < 0.005, true)
  for (let i = 0; i < 9600; i++) {
    voice.renderVoice(state, [new Float32Array(1), new Float32Array(1)], 1, SR, t)
    rates.push(state.rate)
    t += 1 / SR
  }
  //? the drive moves the path it had already started playing (the take's straight line) onto the curve to
  //? -1, 38 ms of the song further on: the steering takes that up over FOLLOW_S - 0.1 s since
  //? 2.0.0-player.27 (0.04 before), so within 1% about 240 ms after reaching -1 on its path, where it was 150
  check('...and settles at -1 within about 250 ms of reaching it on its path (catching up the position it was told on the way)', near(rates.at(-1), -1, 0.01), true)
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
    voice.voiceCommand(swing, { type: 'drive', at: swing.pos + DELAY * swing.rate, rate, time: now, until: now + 1 }, now, SR)
    run(0.15)
  }
  check('through five changes of speed and direction: no step bigger than the signal\'s own at the fastest speed it was read at',
    biggestStep(Float32Array.from(joined.slice(20))) <= SIGNAL_STEP * fastest * 1.05, true)
}

console.log('\nthe song at its own speed is not dulled')
{
  //? a 12 kHz tone read at speed 1, half a sample off its own samples - where the tone itself is at
  //? 0.5 sin(45 degrees) at most: the kernel keeps it there (four points, until 2.0.0-player.29, kept 0.88
  //? of it), where reading straight between two samples would take it to 0.71
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

console.log('\na record turned slower or faster than the song adds nothing of its own (2.0.0-player.29)')
{
  //? James: "it's not just the audio slowing or speeding up, but a digital artifact on top". A record
  //? turned slower or faster is the song resampled, and until 2.0.0-player.29 the window was read with a
  //? curve through four samples - a poor filter: slowed, it left a mirror image of the song's top above
  //? where the slowed song ends; sped up, it folded the top back down over the rest. Tones through the
  //? voice, and through the voice as it was (2.0.0-player.24's, frozen in fixtures/ - the same four points)
  const before = require(path.join(__dirname, 'fixtures/deckVoice-2.0.0-player.24.cjs'))
  const tone = (hz) => {
    const data = new Float32Array(SR * 6)
    for (let i = 0; i < data.length; i++) data[i] = 0.5 * Math.sin((2 * Math.PI * hz * i) / SR)
    return data
  }
  const read = (lib, hz, rate) => {
    const state = lib.newVoiceState()
    lib.voiceCommand(state, { type: 'window', channels: [tone(hz)], start: 0, rate: SR }, 0, SR)
    lib.voiceCommand(state, { type: 'take', at: 1, rate, time: 0, until: 100 }, 0, SR)
    const out = [new Float32Array(SR)]
    lib.renderVoice(state, out, SR, SR, 0)
    return out[0]
  }
  //? how loud a tone of `hz` is in what was read: its amplitude, over the last three quarters of a second
  const level = (data, hz) => {
    const from = SR / 4, n = data.length - from
    let re = 0, im = 0
    for (let i = 0; i < n; i++) {
      const hann = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / n)
      re += data[from + i] * hann * Math.cos((2 * Math.PI * hz * i) / SR)
      im += data[from + i] * hann * Math.sin((2 * Math.PI * hz * i) / SR)
    }
    return (4 * Math.hypot(re, im)) / n
  }
  const db = (a, b) => Math.round(20 * Math.log10(Math.max(a, 1e-9) / b) * 10) / 10
  //? slowed to a quarter, a 15 kHz tone is a 3.75 kHz tone - and its mirror image falls at 12 - 3.75 = 8.25 kHz
  const slow = read(voice, 15000, 0.25), slowBefore = read(before, 15000, 0.25)
  check(`slowed to a quarter, a 15 kHz tone is heard at 3.75 kHz at its own level, within 1 dB (${db(level(slow, 3750), 0.5)} dB)`, Math.abs(db(level(slow, 3750), 0.5)) <= 1, true)
  check(`...and its mirror image at 8.25 kHz is more than 60 dB under it (${db(level(slow, 8250), level(slow, 3750))} dB) - four points left it at ${db(level(slowBefore, 8250), level(slowBefore, 3750))} dB, a tone of its own on top`,
    [db(level(slow, 8250), level(slow, 3750)) < -60, db(level(slowBefore, 8250), level(slowBefore, 3750)) > -30], [true, true])
  //? at twice the speed the same tone would be 30 kHz - nothing a speaker is sent - and folds back to 18 kHz
  const fast = read(voice, 15000, 2), fastBefore = read(before, 15000, 2)
  check(`at twice the speed the 15 kHz tone is left out, not folded back down to 18 kHz: more than 50 dB under the tone it was (${db(level(fast, 18000), 0.5)} dB) - four points played it at ${db(level(fastBefore, 18000), 0.5)} dB`,
    [db(level(fast, 18000), 0.5) < -50, db(level(fastBefore, 18000), 0.5) > -6], [true, true])
  check(`...while a 5 kHz tone at twice the speed is a 10 kHz tone at its own level, within 1 dB (${db(level(read(voice, 5000, 2), 10000), 0.5)} dB), and a 1 kHz tone at the song's own speed is itself, within a tenth (${db(level(read(voice, 1000, 1), 1000), 0.5)} dB)`,
    [Math.abs(db(level(read(voice, 5000, 2), 10000), 0.5)) <= 1, Math.abs(db(level(read(voice, 1000, 1), 1000), 0.5)) <= 0.1], [true, true])
  //? faster than the kernel stretches to (4x): what is left folds - but the tone itself, where it can be played, is there
  check(`at 8x a 2 kHz tone is a 16 kHz tone, within 3 dB of its level (${db(level(read(voice, 2000, 8), 16000), 0.5)} dB)`, Math.abs(db(level(read(voice, 2000, 8), 16000), 0.5)) <= 3, true)
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
  voice.voiceCommand(turned, { type: 'take', at: 15, rate: 1, time: 0, until: 0.12 }, 0, SR)
  //? turned at 1x, told a frame at a time as the deck tells it, then the finger rests at 0.2 s: where the
  //? record is then, still (told only once at 0.2, after the delay had started playing the take's own
  //? line past it, the path stepped onto the stop 19 ms of the song on - and the steering's creep back to it
  //? made a sound for as long as it took: unnoticed with 2.0.0-player.24's FOLLOW_S of 40 ms, not with
  //? 2.0.0-player.27's 0.1 s)
  for (let frame = 1; frame <= 12; frame++) {
    const time = frame / 60
    render(turned, 1 / 60, time - 1 / 60)
    voice.voiceCommand(turned, { type: 'drive', at: 15 + Math.min(time, 0.2), rate: time < 0.2 - 1e-9 ? 1 : 0, time, until: time + 0.12 }, time, SR)
  }
  const stopped = render(turned, 0.6, 0.2).left
  check('turned, then the finger rests: silent once it has stopped', peak(stopped, Math.round(0.4 * SR)) < 1e-4, true)
  const outside = voice.newVoiceState()
  voice.voiceCommand(outside, sine(2, 440, 10), 0, SR)
  voice.voiceCommand(outside, { type: 'take', at: 11.9, rate: 1, time: 0, until: 100 }, 0, SR)
  const across = render(outside, 0.4, 0).left
  //? taken 0.1 s short of the end, the delay behind: at the edge 0.1 s plus the delay on
  check('read on past the window\'s end: silent after it', peak(across, Math.round((0.15 + DELAY) * SR)) < 1e-4, true)
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
  check('a second of a hand at 2.5x: where the hand was the delay before, to a few ms, at its speed', [near(state.pos, 14 + 2.5 * (now - DELAY), 0.005), near(state.rate, 2.5, 0.01)], [true, true])
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
      //? where the platter was the delay before - or, before that, where the take had it moving
      const was = now >= DELAY ? platter.planAt(plan, now - DELAY).x : 20 + v0 * (now - DELAY)
      worst = Math.max(worst, Math.abs(follow.pos - was))
    }
    //? within a millisecond of real time behind, at the speed it goes: the rate's smoothing, no more
    behind.push(worst <= 0.001 + Math.abs(v0) * 0.001)
  }
  check('a coast or a run back to speed, driven a frame at a time: what is heard is where the platter was the delay before, within a ms of real time all the way', behind, [true, true, true, true])
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

console.log('\na take applied after it was said starts where the record is by then (review of 2.0.0-player.16)')
{
  //? said as of 1 s - at 12 s in the song, at its own speed - and applied 43 ms on, as the main-thread
  //? voice may apply one, two of its blocks later
  const late = voice.newVoiceState()
  voice.voiceCommand(late, sine(20), 0, SR)
  voice.voiceCommand(late, { type: 'take', at: 12, rate: 1, time: 1, until: 1.2 }, 1.043, SR)
  const start = late.pos
  let fastest = 0
  for (let i = 0; i < 0.1 * SR; i++) {
    voice.renderVoice(late, [new Float32Array(1)], 1, SR, 1.043 + i / SR)
    fastest = Math.max(fastest, late.rate)
  }
  check('it starts at 12.043 less the delay - where a record at 12 s and its own speed is 43 ms later, the voice the delay behind it - and never reads faster than the record goes (started at 12, it raced to catch up at up to 1.8 times)',
    [round(start, 6), round(fastest, 4) <= 1], [round(12.043 - DELAY, 6), true])
  const early = voice.newVoiceState()
  voice.voiceCommand(early, { type: 'take', at: 12, rate: -2, time: 1, until: 1.2 }, 0.99, SR)
  check('...backwards too, and applied before its own time: where the record was then, the delay before', round(early.pos, 6), round(12.02 + 2 * DELAY, 6))
}

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
    //? a hand's samples too (2.0.0-player.24): the module fits and plays them as the functions do
    if (block >= 40 && block < 90 && block % 3 === 0) say({ type: 'hand', at: 12 + scope.currentTime * 0.8, time: scope.currentTime })
    if (block === 100) say({ type: 'drive', at: direct.pos, rate: -2, time: scope.currentTime, until: 100 })
    if (block === 250) say({ type: 'fade', seconds: 0.04 })
    const a = [new Float32Array(128), new Float32Array(128)], b = [new Float32Array(128), new Float32Array(128)]
    processor.process([], [a])
    voice.renderVoice(direct, b, 128, SR, scope.currentTime)
    where.set(scope.currentTime, direct.pos)
    if (a[0].some((v, i) => v !== b[0][i]) || a[1].some((v, i) => v !== b[1][i])) same = false
    scope.currentTime += 128 / SR
  }
  check('400 blocks through a take, a hand\'s samples, a reversal and a fade: sample for sample what the functions give', same, true)
  const heard = posted.filter((m) => m.type === 'heard')
  check('it says where it is ~30 times a second: 32 times in 400 blocks of 128', [heard.length, Object.keys(heard[0] ?? {}).sort()], [32, ['gain', 'pos', 'rate', 'time', 'type']])
  check('...and what it says is exactly where it was', heard.every((report) => report.pos === where.get(report.time)), true)
  check('the four functions it is made of name nothing outside themselves (they run in a scope of their own)',
    [voice.newVoiceState, voice.voiceCommand, voice.renderVoice, voice.voiceReport].map((fn) => /\b(exports|require|platter|turntable|REPORTS_PER_SECOND|HAND_DELAY_S)\b/.test(fn.toString())), [false, false, false, false])
  check('...nor one another: voiceReport counts, it doesn\'t render (the main-thread voice calls renderVoice itself)', /renderVoice|voiceCommand|newVoiceState/.test(voice.voiceReport.toString()), false)
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
//? whether the worklet's module refuses to load - or is held (its settlers kept here) as a slow one is
let workletFails = false
let workletHeld = null
//? a context with no AudioWorklet (a page that isn't on HTTPS), or with no ScriptProcessorNode either
let noWorklet = false
let noScript = false
//? resumes that settle only when the test says (their settlers kept here), not at once - and suspends
let resumesHeld = null
let suspendsHeld = null
//? decoded windows that hold a tone rather than silence, so what a voice plays can be compared
let decodeTone = false
//? the ScriptProcessorNodes made, and what is asked of them
const scripts = []
class FakeScript {
  constructor(context, args) { this.context = context; this.args = args; this.connected = false; this.disconnected = false; this.onaudioprocess = null; scripts.push(this) }
  connect(to) { this.connected = to === this.context.destination }
  disconnect() { this.disconnected = true }
}
//? the browser asking a script voice for `blocks` blocks of 1024, each to play two blocks ahead of the
//? context's clock, as a ScriptProcessorNode's are; what each was filled with comes back
const fill = (script, playbackTime) => {
  const channels = [new Float32Array(1024), new Float32Array(1024)]
  script.onaudioprocess?.({ outputBuffer: { numberOfChannels: 2, length: 1024, getChannelData: (channel) => channels[channel] }, playbackTime })
  return { channels, playbackTime }
}
const pump = (script, blocks = 1) => {
  const filled = []
  for (let block = 0; block < blocks; block++) {
    const context = script.context
    filled.push(fill(script, context.currentTime + 2048 / 48000))
    context.currentTime += 1024 / 48000
  }
  return filled
}
//? the browser asking for blocks, with nothing compared - the script voice made ready
const playBlocksQuietly = (script, blocks) => void pump(script, blocks)
//? a window's bytes say how long it is (100 kB a second), so the decode gives back that much audio
const BYTES_A_SECOND = 100_000
class FakeContext {
  constructor() {
    this.state = 'suspended'
    this.currentTime = 0
    this.calls = []
    this.sampleRate = 48000
    this.destination = { speakers: true }
    this.audioWorklet = noWorklet ? undefined : {
      addModule: () => (workletHeld ? new Promise((resolve, reject) => workletHeld.push({ resolve, reject }))
        : workletFails ? Promise.reject(new Error('SyntaxError: Unexpected token')) : Promise.resolve()),
    }
    if (noScript) this.createScriptProcessor = undefined
    contexts.push(this)
  }
  createScriptProcessor(size, inputs, outputs) { return new FakeScript(this, [size, inputs, outputs]) }
  addEventListener() {}
  resume() {
    this.calls.push('resume')
    //? a resume the test settles (`resumesHeld`), as a real one settles a moment after it is asked
    if (resumesHeld) return new Promise((resolve) => resumesHeld.push(() => { this.state = 'running'; resolve() }))
    this.state = 'running'
    return Promise.resolve()
  }
  suspend() {
    this.calls.push('suspend')
    if (suspendsHeld) return new Promise((resolve) => suspendsHeld.push(() => { this.state = 'suspended'; resolve() }))
    this.state = 'suspended'
    return Promise.resolve()
  }
  close() { this.calls.push('close'); this.state = 'closed'; return Promise.resolve() }
  decodeAudioData(bytes, done, failed) {
    decodes++
    const length = Math.round((bytes.byteLength / BYTES_A_SECOND) * 48000)
    const tone = () => Float32Array.from({ length }, (_, i) => 0.5 * Math.sin((2 * Math.PI * 440 * i) / 48000))
    const buffer = { numberOfChannels: 2, sampleRate: 48000, length, getChannelData: () => (decodeTone ? tone() : new Float32Array(length)) }
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
//? the clock's readings, counted where deck.js reaches them - when, and whether the mapping was held
const clockLib = require(path.join(OUT, 'lib/deckClock.js'))
const clockReads = []
const realClockReading = clockLib.clockReading
clockLib.clockReading = (...args) => {
  clockReads.push({ at: args[1], held: args[3] })
  return realClockReading(...args)
}
const readsBetween = (from, to) => clockReads.filter((read) => read.at > from && read.at <= to)

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
    check('wakeDeckAudio() - the record\'s tap, a release, the look button, the transport - makes it and resumes it; its worklet ready and the window round the song in it, a press is the deck\'s', [contexts.length, contexts[0].calls, deck.live()], [1, ['resume'], true])
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

  console.log('\nhidden while a tap\'s resume is still settling: suspended as soon as it runs (review of 2.0.0-player.16)')
  {
    resumesHeld = []
    const deck = new Deck(fakeHost())
    deck.setShowing(true)
    wakeDeckAudio()
    const context = contexts.at(-1)
    deck.setShowing(false)
    await settle()
    check('the first tap makes it, and the page is hidden before its resume settles: nothing to suspend yet', [context.state, context.calls], ['suspended', ['resume']])
    resumesHeld.splice(0).forEach((done) => done())
    await settle()
    check('...it settles: suspended at once - nothing of it runs on a hidden page (it ran on, the main-thread voice with it, until the next show and hide)', [context.state, context.calls], ['suspended', ['resume', 'suspend']])
    //? shown and closed again with no tap between - suspended still - then the mini player's tap
    deck.setShowing(true)
    deck.setShowing(false)
    deckModule.resumeDeckAudio()
    resumesHeld.splice(0).forEach((done) => done())
    await settle()
    deck.setShowing(true)
    check('the mini player\'s tap resuming it a moment before the turntable shows: left running - a gesture asking for the sound outweighs a hide before it', [context.state, context.calls.slice(2)], ['running', ['resume']])
    deck.setShowing(false)
    await settle()
    deck.setShowing(true)
    wakeDeckAudio()
    deck.setShowing(false)
    deck.setShowing(true)
    resumesHeld.splice(0).forEach((done) => done())
    await settle()
    check('a tap, hidden and shown again before its resume settles: running, as it shows', [context.state, context.calls.slice(3)], ['running', ['suspend', 'resume']])
    resumesHeld = null
    deck.destroy()
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

  console.log('\nthe clock read on the deck\'s own timer while the turntable shows and its context runs, the record still too (second review of 2.0.0-player.24)')
  {
    //? the context made and running before the deck is (the look button's click wakes it as the turntable
    //? mounts - its state change comes before there is a deck to hear it): shown, the deck reads the clock
    //? itself, a paused record running no frames. This fake's clock stands still - a context said to run
    //? that renders nothing - so its mapping never settles
    wakeDeckAudio()
    await settle()
    const host = fakeHost({ isPlaying: false })
    const deck = new Deck(host)
    deck.setShowing(true)
    const shown = clock
    advance(deckModule.CLOCK_SETTLE_MS * deckModule.CLOCK_SETTLE_TICKS)
    const quick = readsBetween(shown, clock).length
    const slowFrom = clock
    advance(1000)
    check('a paused record, the context already running as the deck mounts: no frame asked for, and the clock read on the deck\'s own timer - every CLOCK_SETTLE_MS while its mapping is young, but for its first CLOCK_SETTLE_TICKS (40) readings at most: a clock that never moves is then read every CLOCK_TICK_MS (10 in a second), not 67 times a second for nothing',
      [frames.length, deckModule.CLOCK_SETTLE_TICKS, Math.abs(quick - deckModule.CLOCK_SETTLE_TICKS) <= 1, Math.abs(readsBetween(slowFrom, clock).length - 1000 / deckModule.CLOCK_TICK_MS) <= 1], [0, 40, true, true])
    //? hidden and shown again, resumed by the mini player's tap - its clock moving from here, in an iPhone's
    //? steps: settled in its first few quick readings, then slow
    deck.setShowing(false)
    await settle()
    const base = clock
    Object.defineProperty(contexts.at(-1), 'currentTime', { configurable: true, get: () => Math.floor((clock - base) / (1024 / 48)) * (1024 / 48000) + 5 })
    deck.setShowing(true)
    deckModule.resumeDeckAudio()
    await settle()
    const moving = clock
    advance(1000)
    check('...its clock moving: the quick readings stop once it has settled (well inside the first 300 ms), then CLOCK_TICK_MS apart',
      [readsBetween(moving, moving + 300).length >= 13, readsBetween(moving + 300, moving + 1000).length <= 8], [true, true])
    //? hidden - a real suspend settles a moment later, its context running meanwhile
    suspendsHeld = []
    const hidden = clock
    deck.setShowing(false)
    advance(500)
    check('...hidden, its suspend still settling (a real one is asynchronous): not read meanwhile - the timer stops at the hide', [contexts.at(-1).state, readsBetween(hidden, clock).length], ['running', 0])
    suspendsHeld.splice(0).forEach((done) => done())
    suspendsHeld = null
    await settle()
    deck.destroy()
  }
  {
    //? a turntable gone and the next made at once (the look switched back, say): nothing of the first may read
    //? on - its reading, not held, would let go of the mapping the next one's hand holds
    wakeDeckAudio()
    await settle()
    const first = new Deck(fakeHost({ isPlaying: false }))
    first.setShowing(true)
    advance(50)
    first.destroy()
    const second = new Deck(fakeHost({ isPlaying: false }))
    second.setShowing(true)
    second.songChanged('time')
    wakeDeckAudio()
    await settle()
    await settle()
    second.pressed(clock)
    second.takeOver()
    const took = clock
    advance(1000)
    const during = readsBetween(took, clock)
    check('a deck gone, another made at once and its record grabbed: every reading through the grab held - the first deck\'s timer went with it', [second.taken(), during.length > 5, during.every((read) => read.held)], [true, true, true])
    second.release(clock, 'cancel')
    second.destroy()
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
    //? the audio's clock moving on with the page's, in an iPhone's 21.3 ms steps - so the one clock's
    //? stamps can be told from a currentTime read for the message
    const base = clock
    Object.defineProperty(contexts.at(-1), 'currentTime', { configurable: true, get: () => Math.floor((clock - base) / (1024 / 48)) * (1024 / 48000) + 5 })
    runFrames(40)
    deck.pressed(clock)
    const taken = deck.takeOver()
    check('taken by a move past a tap (Turntable calls takeOver): paused at once', [taken, host.calls], [60, ['hold']])
    //? a flick backwards, a turn a second for the last 100 ms
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, -(ms / 1000) * 2 * Math.PI, 60 - (ms / 1000) * SECONDS_PER_TURN)
    clock += 100
    const at = 60 - 0.1 * SECONDS_PER_TURN
    const speed = platter.handSpeed([{ time: clock - 100, turned: 0 }, { time: clock, turned: -0.1 * 2 * Math.PI }], clock)
    const plan = platter.motor(at, speed, 425)
    const releasedAt = clock
    const released = deck.release(clock, 'up')
    //? ...and Turntable seeks the song there in the release itself: the player's position is the seek's
    //? target from then on (the handover's test reads it every frame since 2.0.0-player.28)
    host.at = released.seek
    const start = portMessages.at(-1)
    check('the release says where to seek - where the motor has it back at speed - now; and not to play yet: there is a coast',
      [round(released.seek, 6), released.play], [round(plan.x, 6), false])
    check('...the coast starts on the voice\'s path at the release itself (2.0.0-player.24): a drive posted at once, where the hand let go, at its speed, stamped by the one clock at the release\'s own time - not the audio clock\'s step it happened to be on',
      [start.type, round(start.at, 6), round(start.rate, 6), round(start.time, 6), Math.abs(start.time - contexts.at(-1).currentTime) > 1e-4],
      ['drive', round(at, 6), round(speed, 6), round(releasedAt / 1000 + deckModule.deckClockMapping().offset, 6), true])
    check('...from backwards: later than the hand let go of it - stopped, then pulled up',
      [round(plan.duration, 3), plan.x < at], [round(Math.log(1 + (platter.FRICTION_VISCOUS * -speed) / (platter.MOTOR_PULL + platter.FRICTION_DRY)) / platter.FRICTION_VISCOUS + platter.SPIN_UP_S, 3), true])
    runFrames(3)
    const drive = posted('drive').at(-1)
    check('the record\'s sound follows the coast, a frame at a time', [drive.rate < 1, drive.until > drive.time], [true, true])
    check('...and the time line shows where it is, scrubbing', host.shown.at(-1)[1], true)
    advance(plan.duration * 1000 - 50)
    check('not at speed yet: the song still paused', host.calls, ['hold'])
    //? frames on past the end: the plan's timer comes due inside a frame, and runs late
    runFrames(4)
    check('at speed: the song plays (after the tap - the player\'s own toggle, through the host)', host.calls, ['hold', 'resume'])
    const hold = posted('drive').at(-1)
    check('...and the record\'s sound holds speed 1 from there until the song is really playing', [hold.rate, round(hold.at, 6), round(hold.until - hold.time, 9)], [1, round(plan.x, 6), deckModule.HANDOVER_MAX_S])
    check('...from the moment the plan ended - stamped at its end (the release\'s time and the plan\'s length), not whenever the timer fired',
      round(hold.time, 6), round((releasedAt + plan.duration * 1000) / 1000 + deckModule.deckClockMapping().offset, 6))
    Object.defineProperty(contexts.at(-1), 'currentTime', { configurable: true, writable: true, value: 0 })
    const fades = posted('fade').length
    host.moveTo(plan.x + 0.01)
    check('the song\'s clock not moving yet: no fade', posted('fade').length, fades)
    //? the song's clock moving - seen by the next FRAME, before the player's own report of it (which comes
    //? about four times a second): on the report alone the record's sound played on up to a quarter of a
    //? second over the song it had handed back to, the voice's delay behind it - an echo after every
    //? let-go (2.0.0-player.28)
    host.at = plan.x + 0.05
    check('the player hasn\'t reported it and no frame has run: still no fade', posted('fade').length, fades)
    runFrames(1)
    check('really playing: the record\'s sound fades out over a few tens of ms - at the next frame, not waiting for the player\'s report', [posted('fade').length - fades, posted('fade').at(-1)?.seconds], [1, deckModule.HANDOVER_FADE_S])
    host.moveTo(plan.x + 0.3)
    runFrames(2)
    check('...once: the report that follows, and the frames after, fade nothing more', posted('fade').length - fades, 1)
    const health = deckModule.deckReport().health
    check('Debug is told how long the song took to come back after the let-go, and how much of that was the record\'s run back to speed (2.0.0-player.28)',
      [health.backMs >= plan.duration * 1000 && health.backMs < plan.duration * 1000 + 400, Math.round(health.motorMs), health.notBack], [true, Math.round(plan.duration * 1000), 0])
    check('...and how the frames kept up while the hand held the record: counted, none late on this clock', [health.frames >= 0, health.slowFrames, typeof health.blocks], [true, 0, 'number'])
    deck.destroy()
  }

  console.log('\na page that stalls under the hand: counted for Debug (2.0.0-player.28)')
  {
    const { deck } = await fresh()
    runFrames(10)
    deck.pressed(clock)
    deck.takeOver()
    runFrames(5)
    //? the page busy for 120 ms: no frame in that time, then the next
    clock += 120
    runFrames(3)
    deck.release(clock, 'up')
    const health = deckModule.deckReport().health
    check('frames while the hand held the record: each counted, the one that came 136 ms after the one before counted late, and the longest gap kept - told as the hold ends',
      [health.frames, health.slowFrames, Math.round(health.worstFrameMs)], [7, 1, 136])
    deck.setShowing(false)
    deck.setShowing(true)
    check('...counted afresh each time the turntable shows', [deckModule.deckReport().health.frames, deckModule.deckReport().health.slowFrames, deckModule.deckReport().health.backMs], [0, 0, null])
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

  console.log('\nlet go 30 ms after the last move (2.0.0-player.24): the flick at the hand\'s speed, not a third slower')
  {
    const { host, deck } = await fresh({ isPlaying: false })
    deck.pressed(clock)
    deck.takeOver()
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, (ms / 1000) * 4 * Math.PI, 60 + (ms / 1000) * 2 * SECONDS_PER_TURN)
    clock += 130
    const at = 60 + 0.2 * SECONDS_PER_TURN
    const samples = [{ time: clock - 130, turned: 0 }, { time: clock - 30, turned: 0.4 * Math.PI }]
    const released = deck.release(clock, 'up')
    check('sought to where the hand\'s own speed (3.6) coasts - its samples\' times, the 30 ms after the last no slowing - not where 2.4 would (taken up to the release)',
      [round(released.seek, 6), round(released.seek, 6) === round(platter.coast(at, platter.handSpeed(samples, clock), 425).x, 6)],
      [round(platter.coast(at, 3.6, 425).x, 6), false])
    deck.destroy()
  }

  console.log('\na frame begun before the release or the tap it follows (review of 2.0.0-player.24): it drives nothing')
  {
    //? Chrome's frame time is when the frame began, and a pointerup or a tap handled in it can be later
    //? than that: driven, that frame's place on the plan would be stamped before the plan began - its start
    //? erased from the voice's path and set back to the frame's moment
    const runFrameAt = (time) => {
      const due = frames
      frames = []
      for (const frame of due) frame.run(time)
    }
    const { deck } = await fresh()
    //? the audio's clock running on with the page's, in a desktop's 5.8 ms steps
    const base = clock
    Object.defineProperty(contexts.at(-1), 'currentTime', { configurable: true, get: () => Math.floor((clock - base) / (256 / 44.1)) * (256 / 44100) + 5 })
    runFrames(20)
    deck.pressed(clock)
    deck.takeOver()
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, (ms / 1000) * 4 * Math.PI, 60 + (ms / 1000) * 2 * SECONDS_PER_TURN)
    clock += 100
    const from = portMessages.length
    deck.release(clock, 'up')
    const start = portMessages[from] ?? {}
    runFrameAt(clock - 5)
    const early = portMessages.slice(from + 1).filter((message) => message.type === 'drive')
    clock += 16
    runFrameAt(clock)
    const later = portMessages.slice(from + 1).filter((message) => message.type === 'drive')
    check('let go, and the next frame began 5 ms before the release: no drive from it - the plan\'s start the voice has stays its first knot - and the frame after drives as ever, later than it',
      [start.type, early.length, later.length, later.every((message) => message.time > start.time)], ['drive', 0, 1, true])
    deck.destroy()
  }
  {
    const { host, deck } = await fresh()
    const base = clock
    Object.defineProperty(contexts.at(-1), 'currentTime', { configurable: true, get: () => Math.floor((clock - base) / (256 / 44.1)) * (256 / 44100) + 5 })
    runFrames(20)
    const from = portMessages.length
    const landing = deck.pausing()
    host.isPlaying = false
    const take = portMessages.slice(from).find((message) => message.type === 'take')
    const due = frames
    frames = []
    for (const frame of due) frame.run(clock - 3)
    const early = portMessages.slice(from).filter((message) => message.type === 'drive' && message.time < take.time)
    check('...a pause winding down, its first frame begun 3 ms before the tap: nothing driven earlier than the take',
      [landing !== null, take !== undefined, early.length], [true, true, 0])
    deck.destroy()
  }

  console.log('\na sample older than the hand\'s last (2.0.0-player.24): dropped - nothing measured or sought from it')
  {
    const { host, deck } = await fresh({ isPlaying: false })
    deck.pressed(clock)
    deck.takeOver()
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, (ms / 1000) * 4 * Math.PI, 60 + (ms / 1000) * 2 * SECONDS_PER_TURN)
    const hands = posted('hand').length
    //? a stray, timed before the last sample, somewhere else entirely
    deck.hand(clock + 50, 9, 99)
    clock += 100
    const released = deck.release(clock, 'up')
    check('the release measured and sought from the samples in order - as though the stray never came - and the voice not told of it',
      [round(released.seek, 6), posted('hand').length - hands], [round(platter.coast(60 + 0.2 * SECONDS_PER_TURN, 3.6, 425).x, 6), 0])
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
    //? 2.0.0-player.16: the worklet refused - the same voice on the main thread instead, and the window
    //? asked for once it plays (review of .14: nothing asked, nothing decoded, and the record silent)
    workletFails = true
    const host = fakeHost()
    const deck = new Deck(host)
    deck.setShowing(true)
    const before = asked.length
    wakeDeckAudio()
    await settle()
    const script = scripts.at(-1)
    check('the worklet that plays it wouldn\'t load: a ScriptProcessorNode instead - no inputs, two output channels, 1024 a block, to the speakers - and Debug says why',
      [script?.context === contexts.at(-1), script?.args, script?.connected, deckReport().voice, deckReport().voiceWhy],
      [true, [1024, 0, 2], true, 'script', "the AudioWorklet wouldn't load (SyntaxError: Unexpected token)"])
    await play(host, 1)
    check('...not ready until it has played a block: nothing asked, and a press is .11\'s', [asked.length - before, deck.live(), deckReport().context], [0, false, 'starting'])
    pump(script, 1)
    await settle()
    check('...its first block played: the window asked for, and in it - a press is the deck\'s',
      [asked.length - before, deck.live(), deckReport().context, deckReport().window?.start], [1, true, 'running', 56])
    deck.destroy()
    //? its handler compared as a boolean: check() compares JSON, which writes a function as null
    check('...gone: the script voice let go of with the context - disconnected, its handler gone', [script.disconnected, script.onaudioprocess === null, contexts.at(-1).state], [true, true, 'closed'])
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
    //? 2.0.0-player.30: a paused song's first window - for where it is - is asked for as the turntable
    //? shows (nothing was, until the record was turned: its first turn was always silent)
    check('a paused song, the turntable showing: the window for where it is asked for once, and nothing more as it stays paused', asked.slice(before), ['/deadwax/navidrome/scrub/time?at=56&seconds=40'])
    deck.destroy()
  }

  /* ===== 2.0.0-player.16: the sound on a page that isn't HTTPS ===== */

  console.log('\n2.0.0-player.16: a page that isn\'t on HTTPS - no AudioWorklet, and the record\'s sound on the main thread')
  {
    noWorklet = true
    globalThis.isSecureContext = false
    decodeTone = true
    //? the four functions spied on where deck.js reaches them (the module's own exports), and every
    //? message mirrored onto a state of their own - so what the speakers get from the script voice can be
    //? held to them, block by block, as the worklet's is above
    const real = { newVoiceState: voice.newVoiceState, voiceCommand: voice.voiceCommand, renderVoice: voice.renderVoice, voiceReport: voice.voiceReport }
    const called = { newVoiceState: 0, voiceCommand: 0, renderVoice: 0, voiceReport: 0, heard: 0 }
    let mirror = null
    let lastHeard = null
    voice.newVoiceState = () => { called.newVoiceState++; mirror = real.newVoiceState(); return real.newVoiceState() }
    const applied = []
    const appliedMessages = []
    voice.voiceCommand = (state, said, at, rate) => { called.voiceCommand++; applied.push(said.type); appliedMessages.push(said); real.voiceCommand(mirror, said, at, rate); return real.voiceCommand(state, said, at, rate) }
    voice.renderVoice = (...args) => { called.renderVoice++; return real.renderVoice(...args) }
    voice.voiceReport = (...args) => { called.voiceReport++; const heard = real.voiceReport(...args); if (heard) { called.heard++; lastHeard = heard } return heard }
    const same = []
    let pumped = 0
    let loudest = 0
    //? how fast, and how fast backwards, the voice read at any sample while it was sounding: the mirror
    //? is rendered a sample at a time - the very same samples a block gives (each is worked out from the
    //? state and its own time alone) - so nothing between two block ends is missed
    let fastest = -Infinity, slowest = Infinity
    const playBlocks = (script, blocks) => pump(script, blocks).forEach(heardBlock)
    const heardBlock = (block) => {
      {
        pumped++
        const expected = [new Float32Array(1024), new Float32Array(1024)]
        for (let i = 0; i < 1024; i++) {
          const one = [new Float32Array(1), new Float32Array(1)]
          real.renderVoice(mirror, one, 1, 48000, block.playbackTime + i * (1 / 48000))
          expected[0][i] = one[0][0]
          expected[1][i] = one[1][0]
          if (mirror.gain > 0.05) {
            fastest = Math.max(fastest, mirror.rate)
            slowest = Math.min(slowest, mirror.rate)
          }
        }
        same.push(block.channels.every((data, c) => data.every((value, i) => value === expected[c][i])))
        loudest = Math.max(loudest, peak(block.channels[0]))
      }
    }

    const host = fakeHost()
    const deck = new Deck(host)
    deck.setShowing(true)
    decodeMode = 'held'
    decodesHeld.length = 0
    const before = asked.length
    wakeDeckAudio()
    await settle()
    const script = scripts.at(-1)
    check('no AudioWorklet on the context (an insecure page): a ScriptProcessorNode instead - no inputs, two output channels, 1024 a block, to the speakers - and Debug says why',
      [script?.context === contexts.at(-1), script?.args, script?.connected, deckReport().voice, deckReport().voiceWhy],
      [true, [1024, 0, 2], true, 'script', "this page isn't on HTTPS, so the browser has no AudioWorklet"])
    check('...the context running, its voice yet to play a block: no window asked, and a press is .11\'s', [contexts.at(-1).state, asked.length - before, deck.live()], ['running', 0, false])
    playBlocks(script, 1)
    await settle()
    check('its first block played: the window asked for - and while it is still decoding, a press is .11\'s, never the deck\'s over silence',
      [asked.slice(before), deckReport().loading, deck.live()], [['/deadwax/navidrome/scrub/time?at=56&seconds=40'], true, false])
    decodesHeld[0]()
    decodeMode = 'now'
    check('...decoded and in the voice: a press is the deck\'s', [deckReport().window?.start, deckReport().context, deck.live()], [56, 'running', true])
    host.at = 120
    check('...but not where the window doesn\'t reach (2:00): .11\'s there', deck.live(), false)
    host.at = 60

    //? the record taken, turned back, let go and brought to speed: the same messages to both
    deck.pressed(clock)
    deck.takeOver()
    playBlocks(script, 2)
    for (let frame = 1; frame <= 12; frame++) {
      deck.hand(clock, -frame * 0.06, 60 - (frame * 0.06 / (2 * Math.PI)) * SECONDS_PER_TURN)
      runFrames(1)
      playBlocks(script, 1)
    }
    deck.release(clock, 'up')
    for (let frame = 0; frame < 30; frame++) {
      runFrames(1)
      playBlocks(script, 1)
    }
    check('taken, turned and flicked back: what the speakers got from it is, block for block, renderVoice fed the same messages at the time each block plays',
      [same.length, same.every(Boolean), loudest > 0.1], [pumped, true, true])
    check('...the very functions, called - not a copy: a state made by newVoiceState, every message through voiceCommand, every block through renderVoice and voiceReport',
      [called.newVoiceState, called.voiceCommand > 10, called.renderVoice, called.voiceReport], [1, true, pumped, pumped])
    const heardBefore = called.heard
    playBlocks(script, 50)
    check('it says where it is as often as the worklet: 32 times in 50 blocks of 1024 (the worklet, 32 in 400 of 128) - and the deck hears each',
      [called.heard - heardBefore, deck.heard?.pos === lastHeard?.pos, deck.heard?.time === lastHeard?.time], [32, true, true])
    //? a browser that asks for no block for a while, its clock running on (a busy page): every sample of
    //? a hand waits for the next block, and is applied - in order, none replacing another, each a knot of
    //? the path the voice plays (2.0.0-player.24: a drive a frame replaced the one before it, and the
    //? hand's own samples were never sent at all)
    deck.pressed(clock)
    deck.takeOver()
    playBlocks(script, 1)
    applied.length = 0
    appliedMessages.length = 0
    const pages = []
    for (let frame = 0; frame < 20; frame++) {
      deck.hand(clock, -frame * 0.01, deck.anchor() - frame * 0.003)
      pages.push(clock)
      runFrames(1)
      contexts.at(-1).currentTime += 0.016
    }
    playBlocks(script, 1)
    const hands = appliedMessages.filter((said) => said.type === 'hand')
    const offset = deckModule.deckClockMapping().offset
    check('...no block asked for over twenty frames of a hand: all twenty of its samples applied, in order, where the hand had the record',
      [applied, hands.map((said) => round(said.at, 6))], [Array(20).fill('hand'), pages.map((_, frame) => round(deck.anchor() - frame * 0.003, 6))])
    //? (the clock's offset held through the gesture moves at most half a millisecond a second towards its
    //? envelope - lib/deckClock's CLOCK_SLEW - so over these 0.32 s each stamp is within 0.16 ms of the last)
    check('...each heard SCRIPT_LAG_BLOCKS blocks (43 ms) after its own time, as the one clock has it - 16 ms apart, as they were',
      [hands.every((said, i) => near(said.time - (pages[i] / 1000 + offset), (2 * 1024) / 48000, 2e-4)), hands.slice(1).every((said, i) => near(said.time - hands[i].time, 0.016, 1e-5))], [true, true])
    deck.release(clock, 'cancel')
    playBlocks(script, 1)
    applied.length = 0
    host.isPlaying = true
    host.moveTo(200)
    await settle()
    await settle()
    host.moveTo(300)
    await settle()
    await settle()
    const start = deckReport().window?.start
    playBlocks(script, 1)
    check('...nor over two windows arriving: the newer held, the older let go of', [start, applied, round(mirror.window?.start ?? 0, 3)], [296, ['window'], 296])
    //? and the same of a coast's frames, after a flick: every frame's drive applied, in order, the lag
    //? added - each a knot of the path, as the worklet keeps every one (review of 2.0.0-player.24: a drive
    //? replaced the drive held before it, so the main thread's path lost knots the worklet's had)
    deck.pressed(clock)
    deck.takeOver()
    playBlocks(script, 1)
    const flicked = clock
    for (let ms = 10; ms <= 100; ms += 10) {
      clock += 10
      contexts.at(-1).currentTime += 0.01
      deck.hand(clock, -((clock - flicked) / 1000) * 4 * Math.PI, deck.anchor() - ((clock - flicked) / 1000) * 2 * SECONDS_PER_TURN)
    }
    playBlocks(script, 1)
    applied.length = 0
    appliedMessages.length = 0
    const frameTimes = []
    deck.release(clock, 'up')
    for (let frame = 0; frame < 6; frame++) {
      runFrames(1)
      frameTimes.push(clock)
      contexts.at(-1).currentTime += 0.016
    }
    playBlocks(script, 1)
    const drives = appliedMessages.filter((said) => said.type === 'drive')
    const mapped = deckModule.deckClockMapping().offset
    check('...nor over six frames of a coast after a flick: the plan\'s start and all six frames\' drives applied, in order, each heard SCRIPT_LAG_BLOCKS blocks after its own time - none replacing another',
      [applied, drives.slice(1).every((said, i) => near(said.time - (frameTimes[i] / 1000 + mapped), (2 * 1024) / 48000, 2e-4)), drives.every((said, i) => i === 0 || said.time > drives[i - 1].time)],
      [Array(7).fill('drive'), true, true])
    deck.destroy()

    //? the page and the browser on one clock, for `ms`: a frame every 16 ms, and a block of the script
    //? voice asked for every 1024 samples to play a block later (as a browser asks), in the order they
    //? fall - the first of them a block, or a frame
    const together = (script, ms, blockFirst) => {
      const context = script.context
      const start = clock, base = context.currentTime
      let nextBlock = clock + (blockFirst ? 1 : 2), nextFrame = clock + (blockFirst ? 2 : 1)
      while (Math.min(nextBlock, nextFrame) <= start + ms) {
        const block = nextBlock < nextFrame
        clock = block ? nextBlock : nextFrame
        advanceTimersOnly()
        context.currentTime = base + (clock - start) / 1000
        if (block) {
          heardBlock(fill(script, context.currentTime + 1024 / 48000))
          nextBlock += (1000 * 1024) / 48000
        } else {
          const due = frames
          frames = []
          for (const frame of due) frame.run(clock)
          nextFrame += 16
        }
      }
    }
    //? a take on it - a pause's wind-down, the hand grabbing a playing record and holding it still - its
    //? first block asked for before the first frame's drive, and after it
    const takes = {}
    for (const first of ['block', 'frame']) {
      for (const what of ['wind-down', 'grab']) {
        const taker = fakeHost()
        const taking = new Deck(taker)
        taking.setShowing(true)
        wakeDeckAudio()
        await settle()
        const script = scripts.at(-1)
        playBlocks(script, 1)
        await settle()
        await settle()
        const inWindow = deckReport().window?.start
        fastest = -Infinity
        slowest = Infinity
        if (what === 'wind-down') {
          taking.pausing()
          taker.isPlaying = false
        } else {
          taking.pressed(clock)
          taking.takeOver()
        }
        together(script, 300, first === 'block')
        takes[`${what}, ${first === 'block' ? 'its block' : 'a frame'} first`] = [inWindow, round(fastest, 2), round(slowest, 2)]
        taking.destroy()
      }
    }
    const what = Object.values(takes)
    check('a take on it - a pause winding down, a playing record grabbed and held still - never reads faster than the song: it starts where the record is when its block is heard, not a block or two behind (review: it raced to catch up, at up to 1.8 times the speed for 20-80 ms - in this harness, 1.41)',
      [Object.keys(takes), what.every(([start]) => start === 56), what.map(([, fast]) => fast <= 1.03)], [Object.keys(takes), true, [true, true, true, true]])
    check('...and a grab held still never runs the sound back past where the hand has it by more than the frame between them would: every message heard SCRIPT_LAG_BLOCKS blocks on, keeping its spacing (placed where the record had got to, a still hand pulled it back at up to -0.86)',
      [deckModule.SCRIPT_LAG_BLOCKS, takes['grab, its block first'][2] > -0.3, takes['grab, a frame first'][2] > -0.3], [2, true, true])
    console.log(`    (fastest and slowest, by case: ${JSON.stringify(takes)})`)
    Object.assign(voice, real)
    noWorklet = false
    delete globalThis.isSecureContext
    decodeTone = false
  }

  console.log('\nthe main-thread voice counts its own clock (2.0.0-player.31): a stamp that jitters by whole blocks changes nothing it plays')
  {
    //? WebKit stamps a block's playbackTime from the main thread, from the hardware clock as of whenever the
    //? main thread got to it, quantised to the hardware buffer: block to block it jitters by up to a buffer.
    //? The same record, taken and turned the same way, pumped with exact stamps and with jittering ones:
    //? what the speakers get must be the same samples (James: "that digital buzz sound when scrubbing", with
    //? no block late - the voice reading its path by a clock that jumped a block at a time)
    noWorklet = true
    globalThis.isSecureContext = false
    decodeTone = true
    const BLOCK = 1024 / 48000
    const scrub = async (stampOf) => {
      const host = fakeHost()
      const deck = new Deck(host)
      deck.setShowing(true)
      deck.songChanged(host.song().id)
      wakeDeckAudio()
      await settle()
      const script = scripts.at(-1)
      const context = script.context
      const blocks = []
      let index = 0
      const block = () => {
        const exact = context.currentTime + 2 * BLOCK
        blocks.push(fill(script, stampOf(exact, index++)).channels[0])
        context.currentTime += BLOCK
      }
      block()
      await settle()
      await settle()
      await settle()
      deck.pressed(clock)
      deck.takeOver()
      block()
      for (let frame = 1; frame <= 60; frame++) {
        deck.hand(clock, -frame * 0.04, 60 - (frame * 0.04 / (2 * Math.PI)) * SECONDS_PER_TURN)
        runFrames(1)
        block()
      }
      deck.release(clock, 'cancel')
      deck.destroy()
      return blocks
    }
    const exact = await scrub((stamp) => stamp)
    //? late by up to 1.4 blocks, quantised to a block - the first block's stamp exact, as both runs anchor on it
    let seed = 99
    const next = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
    const jittered = await scrub((stamp, index) => (index === 0 ? stamp : Math.round((stamp + next() * 1.4 * BLOCK) / BLOCK - 0.5) * BLOCK))
    const loud = exact.filter((data) => peak(data) > 0.05).length
    //? the rate each run read at, cycle by cycle (the tone's rising zero crossings), over the turn's steady
    //? part - and how far the jittered run's strays from the exact run's
    const rates = (blocks) => {
      const data = Float32Array.from(blocks.slice(12, 60).flatMap((block) => Array.from(block)))
      const crossings = []
      for (let i = 1; i < data.length; i++) if (data[i - 1] < 0 && data[i] >= 0) crossings.push((i - 1 + -data[i - 1] / (data[i] - data[i - 1])) / 48000)
      return crossings.slice(1).map((t, i) => 1 / (t - crossings[i]) / 440)
    }
    const a = rates(exact), b = rates(jittered)
    const n = Math.min(a.length, b.length)
    const stray = Math.sqrt(a.slice(0, n).reduce((sum, r, i) => sum + (b[i] - r) ** 2, 0) / n)
    const within = a.slice(0, n).filter((r, i) => Math.abs(b[i] - r) < 0.01).length / n
    check(`sixty blocks of a hand turning the record back, their stamps jittering by whole blocks: read at the rate the exact stamps give - within 1% on every cycle (stray ${(stray * 100).toFixed(2)}% rms; followed as stamped, the rate wobbled 7-9% rms, a third of cycles within 3%)`,
      [exact.length, loud > 40, n > 200, within === 1 && stray < 0.003], [62, true, true, true])
    noWorklet = false
    delete globalThis.isSecureContext
    decodeTone = false
  }

  console.log('\nlive() only when the record can sound there: a running context alone is not enough')
  {
    workletHeld = []
    const host = fakeHost()
    const deck = new Deck(host)
    deck.setShowing(true)
    const before = asked.length
    wakeDeckAudio()
    await settle()
    await play(host, 2)
    check('the worklet still loading, the context running: nothing asked, a press .11\'s - and Debug says it is starting',
      [contexts.at(-1).state, asked.length - before, deck.live(), deckReport().context], ['running', 0, false, 'starting'])
    const loading = workletHeld
    workletHeld = null
    loading[0].resolve()
    await settle()
    check('...loaded: the window asked for, and in it - a press is the deck\'s', [asked.length - before, deck.live(), deckReport().voice, deckReport().voiceWhy], [1, true, 'worklet', null])
    deck.setShowing(false)
    await settle()
    deck.setShowing(true)
    check('...hidden and shown again, its context suspended until a tap: .11\'s again - and a pause plain, though the window is in',
      [deck.live(), deckReport().window?.start, deck.pausing()], [false, 58, null])
    deck.destroy()
  }
  {
    noWorklet = true
    noScript = true
    const host = fakeHost()
    const deck = new Deck(host)
    deck.setShowing(true)
    wakeDeckAudio()
    await settle()
    const before = asked.length
    await play(host, 5)
    check('neither an AudioWorklet nor a ScriptProcessorNode: the context running, and nothing asked in 5 s of play, every press .11\'s, Debug saying why',
      [contexts.at(-1).state, asked.length - before, deck.live(), deckReport().context, deckReport().voice], ['running', 0, false, 'no-voice', null])
    check('...and a pause is plain: no wind-down to seek to', deck.pausing(), null)
    deck.destroy()
    noWorklet = false
    noScript = false
  }
  {
    const before = asked.length
    const { deck } = await fresh({ isPlaying: false })
    check('a paused song, its voice ready: its window asked for as the turntable shows (2.0.0-player.30), and once it is in the first press is the deck\'s - no silent turn first', [asked.slice(before), deck.live()], [['/deadwax/navidrome/scrub/time?at=56&seconds=40'], true])
    deck.holdStill(true)
    deck.holdStill(false)
    check('...a press meanwhile asking for nothing more', asked.length - before, 1)
    deck.destroy()
    const mp3 = await fresh({ song: () => ({ id: 'mp3', length: 200, flac: false, kind: 'MP3' }) })
    mp3.deck.holdStill(true)
    await settle()
    check('an MP3: no window ever, so every press is .11\'s - no momentum without its sound', [mp3.deck.live(), asked.some((url) => url.includes('/mp3'))], [false, false])
    mp3.deck.holdStill(false)
    mp3.deck.destroy()
    answer = 'not flac'
    const refused = await fresh()
    refused.deck.holdStill(true)
    await settle()
    check('a window deadwax refused (415): .11\'s too', [refused.deck.live(), deckReport().refused], [false, "it isn't a FLAC file"])
    refused.deck.holdStill(false)
    refused.deck.destroy()
    answer = 'window'
  }

  {
    //? where the press is, for a record that coasts: where the PLATTER is, not where the song was
    //? sought to land - a paused record flicked back from 0:57.8, its window 0:56-1:36, landing at 0:53.5
    const { host, deck } = await fresh({ isPlaying: false })
    deck.pressed(clock)
    deck.takeOver()
    await settle()
    for (let ms = 0; ms <= 500; ms += 20) deck.hand(clock + ms, (((60 - ms / 500) - 60) / SECONDS_PER_TURN) * 2 * Math.PI, 60 - ms / 500)
    for (let ms = 520; ms <= 600; ms += 20) {
      const at = 59 - (1.2 * (ms - 500)) / 100
      deck.hand(clock + ms, ((at - 60) / SECONDS_PER_TURN) * 2 * Math.PI, at)
    }
    clock += 600
    decodeMode = 'held'
    decodesHeld.length = 0
    const released = deck.release(clock, 'up')
    host.moveTo(released.seek)
    await settle()
    advance(50)
    check('a press on it as it coasts, the platter still in the window and the song sought outside it: the deck\'s',
      [released.seek < 56, deck.live()], [true, true])
    advance(250)
    check('...once the platter is past the window\'s start, the next window still decoding: still the deck\'s - the flick paused the song already, and there is nothing for .11\'s path to play on (review: taken down it, the coast ran on under the finger)',
      deck.live(), true)
    const timersBefore = timers.length
    const pressedAt = clock
    deck.pressed(clock)
    const caught = deck.takeOver()
    const takes = posted('take').length
    check('...pressed: caught where the platter is, outside the window - silently, nothing more of the coast to come',
      [deck.taken(), caught < 56, caught > released.seek, timers.length <= timersBefore, posted('take').length - takes], [true, true, true, true, 0])
    advance(3000)
    runFrames(2)
    check('...held 3 s: nothing played, the face where the hand has it, and the time line where it was caught',
      [host.calls, round(host.shown.at(-1)[0], 1), host.shown.at(-1)[1]], [[], round(caught, 1), true])
    decodesHeld.at(-1)()
    decodeMode = 'now'
    const sounded = posted('take').at(-1)
    check('...that window in, under the hand: it sounds from where it was caught, held still', [posted('take').length - takes, round(sounded.at, 6), sounded.rate], [1, round(caught, 6), 0])
    const after = portMessages.slice(portMessages.indexOf(sounded))
    check('...the hand\'s path starting there with it (2.0.0-player.24): the take, then a sample of the hand where it holds the record, at the same moment',
      [after[1]?.type, round(after[1]?.at ?? 0, 6), after[1]?.time === sounded.time], ['hand', round(caught, 6), true])
    const mappedNow = deckModule.deckClockMapping().offset + clock / 1000
    check('...and that moment the hand\'s last sample (here the press itself, 3 s before), not when the window landed: samples on their way since go on from it rather than being older than it (review of 2.0.0-player.24)',
      near(mappedNow - sounded.time, (clock - pressedAt) / 1000, 1e-6), true)
    check('...let go where it was caught: sought there', round(deck.release(clock, 'up').seek, 6), round(caught, 6))
    deck.destroy()
  }
  {
    //? a playing record flicked back out of its window, caught as the motor brings it back to speed: the
    //? deck's - and nothing plays the song under the hand
    const { host, deck } = await fresh()
    deck.pressed(clock)
    deck.takeOver()
    decodeMode = 'held'
    decodesHeld.length = 0
    for (let ms = 0; ms <= 800; ms += 20) deck.hand(clock + ms, -((ms / 100) / SECONDS_PER_TURN) * 2 * Math.PI, 60 - ms / 100)
    clock += 800
    await settle()
    const released = deck.release(clock, 'up')
    host.moveTo(released.seek)
    await settle()
    runFrames(5)
    check('a run back to speed out of its window, the window it runs into still decoding: a press is the deck\'s', [released.seek < 56, deck.live()], [true, true])
    deck.pressed(clock)
    deck.takeOver()
    advance(2000)
    check('...caught and held 2 s: the song stays paused under the hand (review: .11\'s path let the coast\'s end play it under a held finger)', [host.calls, host.isPlaying], [['hold'], false])
    decodesHeld.at(-1)()
    decodeMode = 'now'
    deck.destroy()
  }
  {
    //? the same coast with its voice gone meanwhile - the page hidden and shown, its context suspended
    //? until a tap: .11's press, which ends it where the finger holds it
    const { host, deck } = await fresh({ isPlaying: false })
    deck.pressed(clock)
    deck.takeOver()
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, -(ms / 1000) * 6 * Math.PI, 60 - (ms / 1000) * 3 * SECONDS_PER_TURN)
    clock += 100
    host.moveTo(deck.release(clock, 'up').seek)
    runFrames(3)
    deck.setShowing(false)
    await settle()
    deck.setShowing(true)
    runFrames(3)
    const takes = posted('take').length
    check('a coast whose context a hide suspended: a press is .11\'s', [contexts.at(-1).state, deck.live()], ['suspended', false])
    deck.holdStill(true)
    const held = host.angle
    check('...pressed: the coast ends where the finger holds it - its timer gone, nothing shown of it', [timers.some((timer) => timer.at > clock + 50), host.shown.at(-1)], [false, null])
    advance(2000)
    runFrames(3)
    deck.holdStill(false)
    runFrames(1)
    check('...let go 2 s on: the record doesn\'t move - no leap to where the coast would have got to - nothing sounded, nothing played', [round(host.angle - held, 3), posted('take').length - takes, host.calls], [0, 0, []])
    deck.destroy()
  }
  {
    const { host, deck } = await fresh()
    deck.pressed(clock)
    deck.takeOver()
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, -(ms / 1000) * 6 * Math.PI, 60 - (ms / 1000) * 3 * SECONDS_PER_TURN)
    clock += 100
    host.moveTo(deck.release(clock, 'up').seek)
    runFrames(3)
    deck.setShowing(false)
    await settle()
    deck.setShowing(true)
    runFrames(3)
    check('a run back to speed whose context a hide suspended, its sound running: a press is .11\'s', [contexts.at(-1).state, deck.live(), host.calls, deck.motion.sounding], ['suspended', false, ['hold'], true])
    const drives = posted('drive').length
    const stops = posted('stop').length
    deck.holdStill(true)
    const held = host.angle
    check('...pressed: the song plays now, as .11\'s does under the finger - from where the release sought it - and the record\'s sound stops, rather than holding speed 1 for it under the finger',
      [host.calls, host.isPlaying, host.shown.at(-1), posted('drive').length - drives, posted('stop').length - stops], [['hold', 'resume'], true, null, 0, 1])
    deck.playingChanged(true)
    runFrames(5)
    check('...the record still under the finger', round(host.angle - held, 3), 0)
    deck.holdStill(false)
    runFrames(1)
    check('...let go: it turns on from there - a frame\'s worth, no leap', round(host.angle - held, 3), 3.2)
    deck.destroy()
  }
  {
    //? an MP3 paused from the turntable: the platter spins down with no sound - and a press on it then
    const mp3 = await fresh({ song: () => ({ id: 'mp3', length: 200, flac: false, kind: 'MP3' }) })
    runFrames(5)
    check('an MP3 paused on the turntable: a plain pause, the platter winding down silently', mp3.deck.pausing(), null)
    mp3.host.isPlaying = false
    mp3.deck.playingChanged(false)
    runFrames(10)
    check('...pressed as it winds down: .11\'s', mp3.deck.live(), false)
    mp3.deck.holdStill(true)
    const held = mp3.host.angle
    advance(300)
    runFrames(3)
    mp3.deck.holdStill(false)
    runFrames(3)
    check('...let go 300 ms on: the wind-down ended where it was held - not a degree further (review: it ran on underneath, and the face leapt 33 degrees)', [round(mp3.host.angle - held, 3), frames.length], [0, 0])
    mp3.deck.destroy()
  }
  for (const kind of ['worklet', 'script']) {
    //? the first turn of a paused song before the sound has ever started (Now Playing opened onto the
    //? turntable from the mini player, which only resumes a context): the release starts the sound, and
    //? the window where the record is is asked for as soon as there is a voice to put it in
    noWorklet = kind === 'script'
    if (noWorklet) globalThis.isSecureContext = false
    const host = fakeHost({ isPlaying: false })
    const deck = new Deck(host)
    deck.setShowing(true)
    deck.songChanged(host.song().id)
    const before = asked.length
    const first = deck.live()
    deck.holdStill(true)
    //? the release, in Turntable's order: the sound woken in its gesture, .11's press let go, the song
    //? sought where the turn put it
    wakeDeckAudio()
    deck.holdStill(false)
    host.moveTo(65)
    await settle()
    if (kind === 'script') playBlocksQuietly(scripts.at(-1), 1)
    await settle()
    await settle()
    check(`a paused song, its sound not yet started (${kind === 'script' ? 'on the main thread' : 'the worklet'}): the first press .11's, and its window asked for once the voice is there - so the next press has its sound (review: the release let go of the press first, and the ask was lost)`,
      [first, asked.slice(before), deck.live()], [false, ['/deadwax/navidrome/scrub/time?at=60&seconds=40'], true])
    //? the arm moving the paused song well away: the window for there asked for (2.0.0-player.30: a paused
    //? song's first window follows where it is) - and the screen closed and opened again asks nothing more
    host.moveTo(150)
    await settle()
    deck.setShowing(false)
    deck.setShowing(true)
    await settle()
    check('...the paused song moved elsewhere: the window for there asked for, once; the screen opened again, nothing more', asked.slice(before), ['/deadwax/navidrome/scrub/time?at=60&seconds=40', '/deadwax/navidrome/scrub/time?at=146&seconds=40'])
    deck.destroy()
    noWorklet = false
    delete globalThis.isSecureContext
  }

  console.log('\nthe page\'s audio session: \'playback\' while the deck lives, put back as the turntable goes - untouched where there is none')
  {
    const original = Object.getOwnPropertyDescriptor(globalThis, 'navigator')
    const setNavigator = (value) => Object.defineProperty(globalThis, 'navigator', { value, configurable: true, writable: true })
    const session = { type: 'auto' }
    setNavigator({ audioSession: session })
    const deck = new Deck(fakeHost())
    deck.setShowing(true)
    check('before the wake: as it was', session.type, 'auto')
    wakeDeckAudio()
    check('woken, in the gesture: \'playback\' - WebKit gives Web Audio the \'ambient\' kind, which the silent switch mutes, while the song\'s element is paused', session.type, 'playback')
    await settle()
    deck.setShowing(false)
    await settle()
    deck.setShowing(true)
    wakeDeckAudio()
    await settle()
    check('...still, while the deck lives: hidden, shown and woken again', session.type, 'playback')
    deck.destroy()
    check('the turntable gone: put back as it was', session.type, 'auto')
    session.type = 'ambient'
    const again = new Deck(fakeHost())
    again.setShowing(true)
    wakeDeckAudio()
    check('...whatever it was', session.type, 'playback')
    again.destroy()
    check('...\'ambient\' put back as \'ambient\'', session.type, 'ambient')
    //? each wake below is held to a context of its OWN - made by it, running, the deck's report not
    //? 'failed' - since the last one made before it was closed the same way (review: the checks read
    //? that one, and passed with no sound made at all)
    const woken = async (deck) => {
      const made = contexts.length
      let threw = null
      let running = null
      try {
        wakeDeckAudio()
        await settle()
        running = [contexts.length - made, contexts.at(-1).state, deckReport()?.context]
        deck.destroy()
      } catch (error) {
        threw = error
      }
      return [threw, running, contexts.length > made ? contexts.at(-1).calls : null]
    }
    setNavigator({ audioSession: { get type() { return 'auto' }, set type(value) { throw new TypeError('read-only') } } })
    const stubborn = new Deck(fakeHost())
    stubborn.setShowing(true)
    check('a session that won\'t be set: nothing thrown, the sound made as ever', await woken(stubborn), [null, [1, 'running', 'running'], ['resume', 'close']])
    setNavigator({})
    const none = new Deck(fakeHost())
    none.setShowing(true)
    check('no audioSession at all (anything but Safari 16.4 and later): nothing set, nothing thrown, the sound made as ever', await woken(none), [null, [1, 'running', 'running'], ['resume', 'close']])
    if (original) Object.defineProperty(globalThis, 'navigator', original)
    else delete globalThis.navigator
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
