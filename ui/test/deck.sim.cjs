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
 *  - THE SPEED FADER (2.0.0-player.39): the motor's own speed the player's - the plans at 0.25x, 0.5x,
 *    1.5x and 2x held to the equations stepped through, flick by flick; the platter turning at the speed
 *    and carried on without a jump as it changes; a hand taking a playing record at it, the motor bringing
 *    a let-go back to it (its drives' acceleration about it), the handover holding it, the wind-down, the
 *    spin-up (re-planned mid-way), the spin-down and a cancel's spin-up at it, reduced motion included;
 *    and Debug's "back after the let-go" allowing the song's speed.
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
function integrate(x, v, motorOn, length, dt = 1e-5, speed = 1) {
  const low = 0, high = length > 0 ? Math.max(0, length - platter.END_MARGIN_S) : Infinity
  let t = 0
  let clamped = null
  //? the motor's own speed - the player's (2.0.0-player.39): 1 unless the fader says otherwise
  const target = motorOn ? speed : 0
  for (let i = 0; i < 2e7; i++) {
    if (v === target) return { t, x, v, clamped }
    const a = platter.acceleration(v, motorOn, speed)
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

  //? the speed fader (2.0.0-player.39): the motor's own speed the player's - the same flicks, the motor
  //? bringing each back to 0.25x, 0.5x, 1.5x and 2x, each plan held to the equations stepped through
  for (const speed of [0.25, 0.5, 1.5, 2]) {
    let worst = 0
    const off = []
    for (const [x, v, on] of cases) {
      if (!on) continue
      const plan = platter.motor(x, v, 425, speed)
      const steps = integrate(x, Math.max(-platter.MAX_SPEED, Math.min(platter.MAX_SPEED, v)), true, 425, 1e-5, speed)
      const dx = Math.abs(plan.x - steps.x), dt = Math.abs(plan.duration - steps.t)
      worst = Math.max(worst, dx, dt)
      if (dx > 0.001 || dt > 0.001 || (plan.clamped ?? null) !== (steps.clamped ?? null) || plan.target !== speed) off.push([x, v, plan.x, steps.x, plan.duration, steps.t])
    }
    check(`the motor at ${speed}x: ${cases.filter(([, , on]) => on).length} flicks back to it, every landing and time within a millisecond of the equations`, [off, worst < 0.001], [[], true])
  }
}

console.log('\nthe motor at the player\'s speed (2.0.0-player.39): the same motor, its own speed the fader\'s')
{
  check('still to 2x: twice SPIN_UP_S, the same pull - and 0.8 s of the song on; still to 0.25x a quarter of it',
    [round(platter.motor(100, 0, 425, 2).duration), round(platter.motor(100, 0, 425, 2).x - 100), round(platter.motor(100, 0, 425, 0.25).duration), platter.motor(100, 0, 425, 2).v, platter.motor(100, 0, 425, 0.25).v],
    [0.8, 0.8, 0.1, 2, 0.25])
  check('...at its own speed already: nothing to wait for, at any speed', [0.25, 0.5, 1.5, 2].map((speed) => [platter.motor(100, speed, 425, speed).duration, platter.motor(100, speed, 425, speed).v]),
    [[0, 0.25], [0, 0.5], [0, 1.5], [0, 2]])
  check('a let-go at 1x on a record running at 1.5x is pulled UP to it; at 0.5x braked DOWN to it',
    [platter.motor(100, 1, 425, 1.5).phases[0].kind, platter.motor(100, 1, 425, 0.5).phases[0].kind, platter.motor(100, 1, 425, 0.5).phases[0].base], ['pull', 'decay', 0.5])
  check('...a backwards flick stopped as before - the speed is only where it pulls up to', round(platter.motor(200, -9, 425, 2).phases[0].duration, 3), round(platter.motor(200, -9, 425).phases[0].duration, 3))
  check('the plan says the speed it heads for: the motor\'s, and a coast\'s none', [platter.motor(100, 3, 425, 1.5).target, platter.motor(100, 3, 425).target, platter.coast(100, 3, 425).target], [1.5, 1, 0])
  check('...and the acceleration the equations give, about that speed', [platter.acceleration(1, true, 1.5), platter.acceleration(1.5, true, 1.5), platter.acceleration(2, true, 1.5)],
    [platter.MOTOR_PULL, 0, -(platter.MOTOR_PULL + platter.FRICTION_VISCOUS * 0.5)])
  check('the wind-down from each speed: friction as ever - from 2x about 1.25 s, from 1x SPIN_DOWN_S, from 0.25x about 0.55 s',
    [2, 1, 0.25].map((speed) => round(platter.coast(100, speed, 425).duration, 2)), [1.25, 1, 0.55])
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
  check('it says where it is ~30 times a second: 32 times in 400 blocks of 128 - and, since 2.0.0-player.35, what its limiter held down since it last said (held, peaks, lowest)', [heard.length, Object.keys(heard[0] ?? {}).sort()], [32, ['gain', 'held', 'lowest', 'peaks', 'pos', 'rate', 'time', 'type']])
  check('...and what it says is exactly where it was', heard.every((report) => report.pos === where.get(report.time)), true)
  check('the four functions it is made of name nothing outside themselves (they run in a scope of their own)',
    [voice.newVoiceState, voice.voiceCommand, voice.renderVoice, voice.voiceReport].map((fn) => /\b(exports|require|platter|turntable|REPORTS_PER_SECOND|HAND_DELAY_S|VOICE_CEILING|VOICE_LOOKAHEAD_S)\b/.test(fn.toString())), [false, false, false, false])
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
  constructor() { this.port = { postMessage: (message) => portMessages.push(message), onmessage: null }; this.connections = [] }
  connect(to) { this.connections.push(to) }
  disconnect(from) { this.connections = from === undefined ? [] : this.connections.filter((to) => to !== from) }
}
//? how the fake browser decodes: at once ('now'), 300 ms later ('slow'), when the test says ('held' - the
//? callbacks kept in `decodesHeld`), or refusing: the callback with null, with an Error, or by throwing
let decodeMode = 'now'
const decodesHeld = []
let decodes = 0
//? whether the worklet's module refuses to load - or is held (its settlers kept here) as a slow one is
let workletFails = false
let workletHeld = null
//? a context with no AudioWorklet (a page that isn't on HTTPS), or with no ScriptProcessorNode either - and
//? the base latency a context says (2.0.0-player.40: its hardware's render), none unless a check sets one
let noWorklet = false
let noScript = false
let baseLatency
//? and, where it is set, a getOutputTimestamp() saying the render clock is that far ahead of the speaker - and
//? an outputLatency (none unless a check sets one)
let outputTimestampLead = null
let outputLatency
//? resumes that settle only when the test says (their settlers kept here), not at once - and suspends
let resumesHeld = null
let suspendsHeld = null
//? decoded windows that hold a tone rather than silence, so what a voice plays can be compared - or, set
//? to 'loud', a full-scale square wave
let decodeTone = false
//? the ScriptProcessorNodes made, and what is asked of them
const scripts = []
class FakeScript {
  constructor(context, args) { this.context = context; this.args = args; this.connected = false; this.disconnected = false; this.onaudioprocess = null; this.connections = []; scripts.push(this) }
  connect(to) { this.connections.push(to); if (to === this.context.destination) this.connected = true }
  disconnect(from) { if (from === undefined) { this.disconnected = true; this.connections = [] } else this.connections = this.connections.filter((to) => to !== from) }
}
//? the browser asking a script voice for `blocks` blocks of its size (1024, or 512 since 2.0.0-player.40), each
//? to play two blocks ahead of the context's clock, as a ScriptProcessorNode's are; what each was filled with
//? comes back
const fill = (script, playbackTime) => {
  const size = script.args[0]
  const channels = [new Float32Array(size), new Float32Array(size)]
  script.onaudioprocess?.({ outputBuffer: { numberOfChannels: 2, length: size, getChannelData: (channel) => channels[channel] }, playbackTime })
  return { channels, playbackTime }
}
const pump = (script, blocks = 1) => {
  const filled = []
  for (let block = 0; block < blocks; block++) {
    const context = script.context
    filled.push(fill(script, context.currentTime + (2 * script.args[0]) / 48000))
    context.currentTime += script.args[0] / 48000
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
    if (baseLatency !== undefined) this.baseLatency = baseLatency
    if (outputLatency !== undefined) this.outputLatency = outputLatency
    if (outputTimestampLead !== null) {
      const lead = outputTimestampLead
      this.getOutputTimestamp = () => ({ contextTime: this.currentTime - lead, performanceTime: performance.now() })
    }
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
    //? 'loud' (2.0.0-player.35): a full-scale square wave, which the voice reads over full scale
    const square = () => Float32Array.from({ length }, (_, i) => (Math.floor((i * 880) / 48000) % 2 ? -1 : 1))
    const buffer = { numberOfChannels: 2, sampleRate: 48000, length, getChannelData: () => (decodeTone === 'loud' ? square() : decodeTone ? tone() : new Float32Array(length)) }
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

  console.log('\nthe speed fader (2.0.0-player.39): the platter, a hand, the motor and the wind-down at the player\'s speed')
  {
    const { host, deck } = await fresh()
    runFrames(5)
    deck.speedChanged(1.5)
    let before = host.angle
    runFrames(5)
    check('turning at 1.5x: 80 ms on, 24 degrees - 300 a second, 50 rpm', round(host.angle - before, 3), 24)
    const at = host.angle
    deck.speedChanged(0.5)
    runFrames(0)
    check('...changed mid-turn: carried on from where it was, no jump', round(deck['angleNow']() - at, 3), 0)
    before = host.angle
    runFrames(5)
    check('...then at 0.5x: 8 degrees in 80 ms', round(host.angle - before, 3), 8)
    //? the same speed again (Turntable tells it as it mounts): nothing - the motion as it was, the
    //? platter turning on at it (review of 2.0.0-player.39: the check read the angle without a frame,
    //? so a deck that stopped dead here passed it)
    const motion = deck['motion']
    deck.speedChanged(0.5)
    before = host.angle
    runFrames(5)
    check('told the same speed again: nothing changes - the same turn, 8 degrees in the next 80 ms', [deck['motion'] === motion, round(host.angle - before, 3)], [true, 8])
    deck.destroy()
  }
  {
    //? a hand takes a playing record at the speed, and the motor brings it back to it
    const { host, deck } = await fresh()
    deck.speedChanged(1.5)
    runFrames(10)
    deck.pressed(clock)
    advance(deckModule.HOLD_MS + 1)
    const take = posted('take').at(-1)
    check('a press resting on a playing record at 1.5x: taken, the record\'s sound starting at 1.5x where the song was', [host.calls.slice(-2), take.at, take.rate], [['hold', 'grabbed'], 60, 1.5])
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, (ms / 1000) * 2 * Math.PI, 60 + (ms / 1000) * SECONDS_PER_TURN)
    clock += 100
    const speed = platter.handSpeed([{ time: clock - 100, turned: 0 }, { time: clock, turned: 0.1 * 2 * Math.PI }], clock)
    const plan = platter.motor(60 + 0.1 * SECONDS_PER_TURN, speed, 425, 1.5)
    const released = deck.release(clock, 'up')
    host.at = released.seek
    check('let go at a turn a second (1.8x): the motor brings it DOWN to 1.5x - sought where that lands',
      [round(released.seek, 6), released.play, plan.phases[0].kind, plan.v], [round(plan.x, 6), false, 'decay', 1.5])
    runFrames(2)
    check('...the coast\'s sound follows the platter towards 1.5x', posted('drive').at(-1).rate > 1.5, true)
    advance(plan.duration * 1000)
    runFrames(2)
    const hold = posted('drive').at(-1)
    check('at speed: the song played, the record\'s sound holding 1.5x - the song\'s own speed - until it plays', [host.calls.at(-1), hold.rate, round(hold.at, 6)], ['resume', 1.5, round(plan.x, 6)])
    deck.destroy()
  }
  {
    //? paused at 0.5x: the wind-down starts from 0.5x
    const { deck } = await fresh()
    deck.speedChanged(0.5)
    runFrames(5)
    const takes = posted('take').length
    const landing = deck.pausing()
    const plan = platter.coast(60, 0.5, 425)
    check('a pause on the turntable at 0.5x: the wind-down from 0.5x - its sound starting there, the song sought where it stops',
      [round(landing, 6), posted('take').length - takes, posted('take').at(-1).rate, round(plan.duration, 3)], [round(plan.x, 6), 1, 0.5, round(platter.coast(0, 0.5, 0).duration, 3)])
    deck.destroy()
  }
  {
    //? a play spins it up to the speed; a pause from elsewhere spins it down from it
    const host = fakeHost({ isPlaying: false })
    const deck = new Deck(host)
    deck.setShowing(true)
    deck.songChanged(host.song().id)
    deck.speedChanged(2)
    host.isPlaying = true
    deck.playingChanged(true)
    advance(0.4 * 1000)
    runFrames(1)
    check('played at 2x: still spinning up after SPIN_UP_S - twice as far to go', deck['motion'].kind, 'plan')
    advance(0.4 * 1000 + 50)
    runFrames(2)
    let before = host.angle
    runFrames(5)
    check('...at speed after 0.8 s: 400 degrees a second', [deck['motion'].kind, round(host.angle - before, 3)], ['turning', 32])
    host.isPlaying = false
    deck.playingChanged(false)
    advance(deckModule.PAUSE_SETTLE_MS + 1)
    check('a pause from elsewhere (the lock screen): spun down from 2x - friction\'s 1.25 s from there, not 1x\'s 1 s',
      [deck['motion'].plan.v0 ?? deck['motion'].plan.phases[0].v0, round(deck['motion'].plan.duration, 3)], [2, round(platter.coast(0, 2, 0).duration, 3)])
    deck.destroy()
  }
  {
    //? a play at 0.5x: spun up to it, and then turning at it - not stopped where the spin-up ended
    const host = fakeHost({ isPlaying: false })
    const deck = new Deck(host)
    deck.setShowing(true)
    deck.songChanged(host.song().id)
    deck.speedChanged(0.5)
    host.isPlaying = true
    deck.playingChanged(true)
    advance(0.2 * 1000 + 50)
    runFrames(2)
    const before = host.angle
    runFrames(5)
    check('played at 0.5x: spun up in 0.2 s, then turning on at it - 100 degrees a second', [deck['motion'].kind, round(host.angle - before, 3)], ['turning', 8])
    deck.destroy()
  }
  {
    //? the speed changed while it spins up: it heads for the new one from where it has got to
    const host = fakeHost({ isPlaying: false })
    const deck = new Deck(host)
    deck.setShowing(true)
    deck.songChanged(host.song().id)
    host.isPlaying = true
    deck.playingChanged(true)
    advance(200)
    runFrames(1)
    const v = deck['speedNow']()
    deck.speedChanged(2)
    const motion = deck['motion']
    check('the speed changed mid spin-up: a fresh spin-up from where it had got to, to the new speed', [motion.kind, motion.role, round(motion.plan.phases[0].v0, 3), motion.plan.target], ['plan', 'spin', round(v, 3), 2])
    deck.destroy()
  }
  {
    //? a cancel of a hand that took a playing record: the song plays on, the platter spun back up to the speed
    const { host, deck } = await fresh()
    deck.speedChanged(0.25)
    deck.pressed(clock)
    deck.takeOver()
    deck.release(clock + 20, 'cancel')
    check('a cancel: the song plays on, the platter spun up to 0.25x', [host.calls.at(-1), deck['motion'].plan?.target], ['resume', 0.25])
    deck.destroy()
  }
  {
    //? the coast back to the speed drives the voice with the motor's own acceleration about THAT speed
    const { host, deck } = await fresh()
    deck.speedChanged(1.5)
    runFrames(5)
    deck.pressed(clock)
    deck.takeOver()
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, (ms / 1000) * 2 * Math.PI, 60 + (ms / 1000) * SECONDS_PER_TURN)
    clock += 100
    const released = deck.release(clock, 'up')
    host.at = released.seek
    runFrames(2)
    const drive = posted('drive').at(-1)
    check('...the coast\'s drives carry the motor\'s acceleration about 1.5x, not about 1x', round(drive.accel, 6), round(platter.acceleration(drive.rate, true, 1.5), 6))
    //? Debug's "the song was back" after the let-go - the song moving at 2x from where it was sought, reported
    //? late (a quiet page): still counted as the song coming back, its 2x allowed for
    deck.speedChanged(2)
    advance(3_000)
    host.moveTo(released.seek + 2 * 2.6)
    check('...and Debug\'s "back after the let-go" counts a song moving at 2x from there, reported 3 s late', deckModule.deckReport().health.backMs !== null, true)
    deck.destroy()
  }
  {
    //? reduced motion: a play spins it "up" to a slow speed - turning, not left still
    reduced = true
    const host = fakeHost({ isPlaying: false })
    const deck = new Deck(host)
    deck.setShowing(true)
    deck.songChanged(host.song().id)
    deck.speedChanged(0.25)
    host.isPlaying = true
    deck.playingChanged(true)
    check('reduced motion, played at 0.25x: the platter counted as turning at once (it is not drawn turning)', deck['motion'].kind, 'turning')
    deck.destroy()
    reduced = false
  }
  {
    //? reduced motion: a release lands at once; the platter "turns" at the speed - still - as ever
    reduced = true
    const { deck } = await fresh()
    deck.speedChanged(1.5)
    deck.pressed(clock)
    deck.takeOver()
    deck.hand(clock + 50, 2, 62)
    clock += 60
    const released = deck.release(clock, 'up')
    check('reduced motion at 1.5x: landed where the motor at 1.5x says, played in the release', [round(released.seek, 6), released.play],
      [round(platter.motor(62, platter.releaseSpeed([{ time: clock - 60, turned: 0 }, { time: clock - 10, turned: 2 }], clock), 425, 1.5).x, 6), true])
    deck.destroy()
    reduced = false
  }
  {
    //? a play iOS refuses after a run back to 2x ("Tap play to start"): after HANDOVER_MAX_S the platter
    //? spins down FROM 2x - friction's 1.25 s - not dropped to 1x and stopped in 1 s (review of
    //? 2.0.0-player.39: nothing held this second spin-down)
    const { host, deck } = await fresh({ resume() { this.calls.push('resume (refused)') } })
    deck.speedChanged(2)
    deck.pressed(clock)
    deck.takeOver()
    flickBack(deck)
    deck.release(clock, 'up')
    for (let i = 0; i < 400 && !host.calls.includes('resume (refused)'); i++) runFrames(1)
    const held = deck['motion'].kind
    const at = host.angle
    runFrames(5)
    const turned = round(host.angle - at, 3)
    advance(deckModule.HANDOVER_MAX_S * 1000 + 1)
    const spin = deck['motion']
    check('a play refused at 2x: back at speed, turning at 2x (32 degrees in 80 ms) - then spun down from 2x, coast(0, 2)\'s 1.25 s',
      [host.calls.at(-1), held, turned, spin.kind, spin.role, spin.plan?.phases[0].v0, round(spin.plan?.duration ?? 0, 3)],
      ['resume (refused)', 'turning', 32, 'plan', 'spin', 2, round(platter.coast(0, 2, 0).duration, 3)])
    deck.destroy()
  }
  {
    //? the window asked again ahead of the playhead: a fetch and a decode's time in hand at any speed -
    //? at 2x 12 s of the song before this window ends, 6 s of listening, where it had 6 s of the song, 3 of
    //? listening (review of 2.0.0-player.39); at 0.5x as at 1x. Still moving on: from 80, past 56
    const askedAt = async (speed) => {
      const before = asked.length
      const { host, deck } = await fresh()
      deck.speedChanged(speed)
      let at = null
      for (let t = 0; t < 80_000 && at === null; t += 250) {
        advance(250)
        host.moveTo(host.at + 0.25 * speed)
        await settle()
        if (asked.length - before > 1) at = host.at
      }
      const from = Number(new URL(asked.at(-1), 'http://x').searchParams.get('at'))
      deck.destroy()
      return [at === null ? null : round(96 - at, 3), from]
    }
    check('the window 56-96 asked again at 1x 5.75 s before its end, at 2x 11.5 s (5.75 of listening), at 0.5x 5.875 s - each from further on',
      [await askedAt(1), await askedAt(2), await askedAt(0.5)], [[5.75, 86], [11.5, 80], [5.875, 86]])
    //? a hi-res song's shorter windows at 2x, and windows of 2 s: each still moves on, none asked twice
    const starts = []
    for (const seconds of [13, 2]) {
      windowSeconds = seconds
      const before = asked.length
      const { host, deck } = await fresh()
      deck.speedChanged(2)
      for (let t = 0; t < 30_000; t += 250) {
        advance(250)
        host.moveTo(host.at + 0.5)
        await settle()
      }
      const list = asked.slice(before).map((url) => Number(new URL(url, 'http://x').searchParams.get('at')))
      starts.push([list.length > 3, list.every((at, i) => i === 0 || at > list[i - 1])])
      deck.destroy()
    }
    windowSeconds = 40
    check('...windows of 13 s and of 2 s at 2x: a minute of the song, each window further on than the last', starts, [[true, true], [true, true]])
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

  console.log('\na recording of the record\'s sound (2.0.0-player.32): what the voice plays, tapped, with every message and report, as one file')
  {
    //? James hears "a pretty digital sound" that no lab recording has shown: the recorder gives him a file of
    //? what HIS device plays, with the hand samples that made it, to replay here. Pinned: the tap on the
    //? voice's node, the file's shape, and that its audio decodes to exactly the frames tapped - the first
    //? cut's base64 came in 32768-byte pieces, each padded by btoa, and 20 s decoded to 29 bytes too many
    noWorklet = true
    globalThis.isSecureContext = false
    const { recordDeckSound, deckRecorded, onDeckRecorded } = deckModule
    const states = []
    const stopListening = onDeckRecorded((state) => states.push(state?.state ?? null))
    let captured = null
    const makeUrl = globalThis.URL.createObjectURL
    globalThis.URL.createObjectURL = (blob) => { captured = blob; return 'blob:deck-recording' }
    check('before the sound has started: refused, and told what to do', recordDeckSound(1), 'the sound has not started - turn the record once first')
    const host = fakeHost()
    const deck = new Deck(host)
    deck.setShowing(true)
    deck.songChanged(host.song().id)
    wakeDeckAudio()
    await settle()
    const voiceNode = scripts.at(-1)
    pump(voiceNode, 1)
    await settle()
    await settle()
    const made = scripts.length
    const problem = recordDeckSound(1)
    const tap = scripts.at(-1)
    check('asked with the voice ready: a tap of 4096 a block, two in and two out, the voice\'s node into it and it to the speakers; the state \'recording\' and told',
      [problem, scripts.length - made, tap.args, voiceNode.connections.includes(tap), tap.connected, deckRecorded(), states],
      [null, 1, [4096, 2, 2], true, true, { state: 'recording', seconds: 1 }, ['recording']])
    check('...asked again meanwhile: refused as already recording', recordDeckSound(1), 'already recording')
    //? three blocks tapped, 49152 bytes of samples: past one base64 piece, so a padded piece would show;
    //? values that survive 16 bits exactly, the right channel the left's negative
    const frames = 4096
    const expected = []
    const peaks = []
    for (let block = 0; block < 3; block++) {
      const left = new Float32Array(frames), right = new Float32Array(frames)
      for (let i = 0; i < frames; i++) { const k = ((block * frames + i) * 7) % 32767 - 16383; left[i] = k / 32767; right[i] = -k / 32767; expected.push(k, -k) }
      //? one sample over full scale in the last block (2.0.0-player.35): the 16 bits clamp it, the block's
      //? peak says how far over it went
      if (block === 2) { left[7] = 1.25; expected[(2 * frames + 7) * 2] = 32767 }
      //? and the right louder than the left in another: a block's peak is its loudest channel's
      if (block === 1) { right[11] = -0.75; expected[(frames + 11) * 2 + 1] = Math.round(-0.75 * 32767) }
      peaks.push(Math.max(...left.map(Math.abs), ...right.map(Math.abs)))
      tap.onaudioprocess({ inputBuffer: { numberOfChannels: 2, getChannelData: (c) => (c === 0 ? left : right) }, playbackTime: 1.5 + block * frames / 48000 })
    }
    //? a hand sample and a report during it, so the file carries both
    deck.pressed(clock)
    deck.takeOver()
    for (let frame = 1; frame <= 6; frame++) {
      deck.hand(clock, -frame * 0.04, 60 - (frame * 0.04 / (2 * Math.PI)) * SECONDS_PER_TURN)
      runFrames(1)
    }
    pump(voiceNode, 2)
    advance(1000)
    await settle()
    const saved = deckRecorded()
    check('a second on: saved - the tap let go of (the voice\'s node still to the speakers), a file named for the voice and the time, its size told, and told',
      [saved?.state, tap.disconnected, voiceNode.connections.includes(tap), voiceNode.connected, /^deadwax-turntable-script-\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d\.json$/.test(saved?.name ?? ''), saved?.href, saved?.bytes > 60000, states.at(-1)],
      ['saved', true, false, true, true, 'blob:deck-recording', true, 'saved'])
    const text = await captured.text()
    const file = JSON.parse(text)
    const pcm = Buffer.from(file.audio.base64, 'base64')
    const samples = Array.from(new Int16Array(pcm.buffer, pcm.byteOffset, pcm.length / 2))
    check('the file: what it is, the voice, the rate, the delays, the tap\'s block, three block times, and the audio\'s frames and channels',
      [file.recording, file.version, file.voice, file.secure, file.sampleRate, file.delaySeconds, file.scriptLagSeconds, file.tapBlock, file.blockTimes, file.audio.format, file.audio.channels, file.audio.frames],
      ['deadwax turntable sound', 3, 'script', false, 48000, voice.HAND_DELAY_S, 2048 / 48000, 4096, [1.5, 1.5 + 4096 / 48000, 1.5 + 8192 / 48000], 'int16le', 2, 3 * frames])
    //? version 3 (2.0.0-player.40): the block the voice rendered at a time - what its lag is made of, which a
    //? replay reads from here - and what the device's audio adds after the voice, as its context says it
    check('...since 2.0.0-player.40 (version 3): the voice\'s block, 1024 on a context that says nothing of its hardware, and the latencies it says - none here but the design',
      [file.block, file.latency && Object.keys(file.latency).sort(), file.latency?.base, file.latency?.output, file.latency?.speaker, file.latency?.block, file.latency && Math.round(file.latency.design * 1e6) / 1e6],
      [1024, ['base', 'block', 'design', 'output', 'speaker'], null, null, null, 1024, Math.round((voice.HAND_DELAY_S + 2048 / 48000 + voice.VOICE_LOOKAHEAD_S) * 1e6) / 1e6])
    check('...each block\'s loudest sample, either channel, as a float, past the 16 bits\' clamp (2.0.0-player.35: the middle block\'s right -0.75, the last block\'s 1.25), and the limiter\'s ceiling and lookahead',
      [file.blockPeaks, file.limiter], [peaks, { ceiling: voice.VOICE_CEILING, lookaheadSeconds: voice.VOICE_LOOKAHEAD_S }])
    check('...its audio decodes to exactly the frames tapped, interleaved, 16-bit', [pcm.length, samples.length === expected.length && samples.every((v, i) => v === expected[i])], [3 * frames * 2 * 2, true])
    check('...and carries the hand sample the deck sent and what the voice said meanwhile',
      [file.messages.some((m) => m.type === 'take'), file.messages.filter((m) => m.type === 'hand').length >= 6, file.heard.length >= 1, typeof file.when, file.report?.voice, typeof file.clock],
      [true, true, true, 'string', 'script', 'object'])
    deck.release(clock, 'cancel')
    deck.destroy()
    stopListening()
    globalThis.URL.createObjectURL = makeUrl
    delete globalThis.isSecureContext
    noWorklet = false
  }
  console.log('\n2.0.0-player.35: a loud window on the main thread - never above the ceiling, and what the limiter held reaches Debug')
  {
    //? James's recording held 144 samples at full scale, in 15 bursts on the loudest drum hits: the voice read
    //? his loud master over full scale and the browser cut it. A full-scale square wave decoded, the record taken and turned back and forth
    //? through the real deck and the real main-thread voice: every sample the speakers get under the ceiling,
    //? and the deck's health counting the peaks held, and the deepest - for Info > Debug's "Turntable timing"
    noWorklet = true
    globalThis.isSecureContext = false
    decodeTone = 'loud'
    const host = fakeHost()
    const deck = new Deck(host)
    deck.setShowing(true)
    deck.songChanged(host.song().id)
    wakeDeckAudio()
    await settle()
    const voiceNode = scripts.at(-1)
    pump(voiceNode, 1)
    await settle()
    await settle()
    check('the window in, the main-thread voice ready: a press is the deck\'s - and nothing held down yet',
      [deck.live(), deckReport().voice, deckReport().health.peaksHeld, deckReport().health.samplesHeld, deckReport().health.deepestHoldDb], [true, 'script', 0, 0, 0])
    let loudest = 0, blocks = 0
    //? every report the voice makes, where deck.js reaches voiceReport - what the health must add up to
    const realReport = voice.voiceReport
    const said = []
    voice.voiceReport = (...args) => { const heard = realReport(...args); if (heard) said.push(heard); return heard }
    const listen = (count) => pump(voiceNode, count).forEach((block) => { blocks++; for (const data of block.channels) for (const v of data) loudest = Math.max(loudest, Math.abs(v)) })
    deck.pressed(clock)
    deck.takeOver()
    listen(2)
    for (let frame = 1; frame <= 40; frame++) {
      deck.hand(clock, Math.sin(frame / 6) * 0.8, 60 + Math.sin(frame / 6) * 0.25)
      runFrames(1)
      listen(1)
    }
    const saidByRelease = said.length
    deck.release(clock, 'cancel')
    //? as the hold ended, a report: the health as it stood then - every report the voice had made
    const health = deckReport().health
    listen(10)
    check(`${blocks} blocks of a full-scale square wave, taken and turned both ways: the loudest sample the speakers got is under the ceiling (${round(voice.VOICE_CEILING, 6)})`,
      [loudest > 0.5, loudest <= voice.VOICE_CEILING], [true, true])
    voice.voiceReport = realReport
    const upTo = said.slice(0, saidByRelease)
    const total = (key) => upTo.reduce((sum, heard) => sum + heard[key], 0)
    const deepest = Math.max(...upTo.map((heard) => -20 * Math.log10(heard.lowest)))
    check('...and the deck\'s health has what its limiter held under it, told as the hold ended: peaks (runs of samples), the samples, the deepest it turned the sound down - exactly what the voice\'s reports added up to by then',
      [health.peaksHeld > 0, health.samplesHeld > health.peaksHeld, health.deepestHoldDb > 0.4 && health.deepestHoldDb < 12, health.peaksHeld === total('peaks'), health.samplesHeld === total('held'), Math.abs(health.deepestHoldDb - deepest) < 1e-12],
      [true, true, true, true, true, true])
    deck.setShowing(false)
    deck.setShowing(true)
    check('...counted afresh as the turntable shows again', [deckReport().health.peaksHeld, deckReport().health.samplesHeld, deckReport().health.deepestHoldDb], [0, 0, 0])
    //? a report whose lowest gain is below 0, or 0 (what the voice floors its gain at - only for a window some
    //? 1e16 times full scale): -20 log10 of it is NaN or Infinity, which Debug would print. The deck reads it as
    //? 120 dB down at most (review of 2.0.0-player.35)
    for (const injected of [-4.4e-16, 0]) {
      deck.setShowing(false)
      deck.setShowing(true)
      voice.voiceReport = (...args) => { const heard = realReport(...args); return heard ? { ...heard, held: 1, peaks: 1, lowest: injected } : heard }
      deck.pressed(clock)
      deck.takeOver()
      listen(8)
      deck.release(clock, 'cancel')
      voice.voiceReport = realReport
      const deepest = deckReport().health.deepestHoldDb
      check(`...a report's lowest gain of ${injected}: the deepest said as 120 dB, a number`, [Number.isFinite(deepest), Math.abs(deepest - 120) < 1e-9], [true, true])
      listen(10)
    }
    deck.destroy()
    delete globalThis.isSecureContext
    noWorklet = false
    decodeTone = false
  }
  console.log('\n...and what it held after the hold ended - its last moments, a coast - reaches Debug too, once the deck no longer steers the sound (review of 2.0.0-player.35)')
  {
    //? the voice plays the hand's path HAND_DELAY_S behind (and the script lag more, here on the main thread),
    //? so the limiter's counts for a hold's last moments come in after the report its end makes - and a paused
    //? record's coast has no later report of its own: a quick flick of a loud paused record read "none since it
    //? showed" (or a handful) while the voice held thousands of peaks through the coast. Frames and blocks on one
    //? clock, the clock's step settled first (a real browser's settles; a step changing makes reports of its own)
    noWorklet = true
    globalThis.isSecureContext = false
    decodeTone = 'loud'
    const host = fakeHost({ isPlaying: false })
    const deck = new Deck(host)
    deck.setShowing(true)
    deck.songChanged(host.song().id)
    wakeDeckAudio()
    await settle()
    const voiceNode = scripts.at(-1)
    pump(voiceNode, 1)
    await settle()
    await settle()
    const context = voiceNode.context
    const base = clock - context.currentTime * 1000
    const tick = async (count = 1) => {
      for (let k = 0; k < count; k++) {
        runFrames(1)
        while (context.currentTime * 1000 + base < clock) pump(voiceNode, 1)
        await settle()
      }
    }
    await tick(150)
    const realReport = voice.voiceReport
    const said = []
    voice.voiceReport = (...args) => { const heard = realReport(...args); if (heard) said.push(heard); return heard }
    const told = []
    const stopListening = deckModule.onDeckReport((report) => { if (report) told.push({ at: clock, peaks: report.health.peaksHeld }) })
    const totals = () => ({
      peaks: said.reduce((sum, heard) => sum + heard.peaks, 0),
      held: said.reduce((sum, heard) => sum + heard.held, 0),
      deepest: Math.max(0, ...said.filter((heard) => heard.lowest < 1).map((heard) => -20 * Math.log10(heard.lowest))),
    })
    //? a long, slow scrub first: held through 60 frames (nearly a second) of loud sound - nothing reported while
    //? the hand steers it, however much the limiter holds meanwhile
    deck.pressed(clock)
    deck.takeOver()
    await tick(2)
    const toldBefore = told.length
    for (let frame = 1; frame <= 60; frame++) {
      deck.hand(clock, Math.sin(frame / 8) * 0.6, 60 + Math.sin(frame / 8) * 0.18)
      await tick(1)
    }
    check('a hand holding a loud record for 60 frames, its limiter holding peaks all the while: Debug told nothing until the hold ends - a report re-renders the page, and under a hand that is the main-thread voice\'s own time',
      [totals().peaks > 50, told.length - toldBefore], [true, 0])
    //? let go with no coast (cancel): the release reports at once, the voice's last blocks' counts after it -
    //? told once HEALTH_REPORT_MS have passed since that report, not at the next of the voice's reports
    const cancelAt = clock
    const toldAtCancel = told.length
    deck.release(clock, 'cancel')
    const atCancel = deckReport().health.peaksHeld
    await tick(60)
    const late = told.slice(toldAtCancel).filter((report) => report.at > cancelAt)
    check(`...let go with no coast: Debug ends with the peaks held after the release too (${atCancel} at the release, ${totals().peaks} in all), told 250 ms (HEALTH_REPORT_MS) or more after the release's own report - four times a second at most`,
      [totals().peaks > atCancel, deckReport().health.peaksHeld, deckReport().health.samplesHeld, late.length, late.every((report) => report.at - cancelAt >= 250), deckModule.HEALTH_REPORT_MS],
      [true, totals().peaks, totals().held, 1, true, 250])
    //? then one quick flick of the paused record, five frames, let go into a coast
    const flickFrom = told.length
    const beforeFlick = totals().peaks
    deck.pressed(clock)
    deck.takeOver()
    for (let frame = 1; frame <= 5; frame++) {
      deck.hand(clock, -frame * 0.4, 60 - frame * 0.06)
      await tick(1)
    }
    deck.release(clock, 'up')
    const atRelease = deckReport().health.peaksHeld
    const releasedAt = clock
    await tick(300)
    const all = totals()
    const health = deckReport().health
    check(`a quick flick of the paused loud record (five frames) and its coast: Debug ends with every peak the voice held - the flick's ${all.peaks - beforeFlick}, where the report its release made had ${atRelease - beforeFlick} of them`,
      [all.peaks - beforeFlick > 100, atRelease - beforeFlick < (all.peaks - beforeFlick) / 10, health.peaksHeld, health.samplesHeld, Math.abs(health.deepestHoldDb - all.deepest) < 1e-12], [true, true, all.peaks, all.held, true])
    const after = told.slice(flickFrom).filter((report) => report.at > releasedAt)
    check(`...told once, after the coast - not while it coasted (the deck steering the sound), nor at every one of the voice's ${voice.REPORTS_PER_SECOND} reports a second after it, nor for its gain still coming back up`,
      [after.length, after[0]?.peaks], [1, all.peaks])
    const quiet = told.length
    await tick(120)
    check('...and once its counts stop moving, nothing more: the voice\'s reports carry on, and nothing is told for them', told.length - quiet, 0)
    //? a dip deeper than any so far, in a report holding no new samples - the dip's deepest gain is written the
    //? lookahead after its loudest sample was counted, so it can fall in the next report: news too
    let once = true
    voice.voiceReport = (...args) => { const heard = realReport(...args); if (heard && once) { once = false; return { ...heard, held: 0, peaks: 0, lowest: 0.1 } } return heard }
    const deeper = told.length
    await tick(30)
    check('...a report with nothing new held but a deeper dip (a gain of 0.1): Debug told the deepest, 20 dB, once', [round(deckReport().health.deepestHoldDb, 6), told.length - deeper], [20, 1])
    voice.voiceReport = realReport
    stopListening()
    deck.destroy()
    delete globalThis.isSecureContext
    noWorklet = false
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

  console.log('\n2.0.0-player.40: less delay between the hand and the record\'s sound - the counted clock after a stall, in seconds')
  {
    const { countBlock, newScriptClock, scriptBlockFor, SCRIPT_REANCHOR_S, SCRIPT_STAMP_TOLERANCE_S } = deckModule
    const RATE = 48000
    //? the counted clock as it was until 2.0.0-player.40 - constants a block, a stamp three blocks away anchoring
    //? it at once, a burst counted a block a callback - for "reproduce it first"
    const countAsWas = (stamps, size) => {
      const block = size / RATE
      let counted = null, drift = 0
      return stamps.map((reported) => {
        let at
        const off = counted === null ? Infinity : reported - counted
        if (Math.abs(off) > 3 * block) { at = reported; drift = 0 }
        else if (Math.abs(off) <= 0.001) at = reported
        else { drift += (off - drift) * 0.02; at = counted + Math.max(-0.00002, Math.min(0.00002, drift)) }
        counted = at + block
        return at
      })
    }
    const countNow = (stamps, size) => {
      const clock = newScriptClock()
      return stamps.map((stamp) => countBlock(clock, stamp, size / RATE))
    }
    check('the main-thread voice\'s block from what the context says of its hardware: 512 where it renders 128, 256, 480 or 512 frames at a time (baseLatency times the rate - exact in Chromium; 0.0107 s, 513.6 frames, a rounded 512), 1024 where it renders 960 or 1024 - and where it says nothing, 0 or nonsense',
      [128, 256, 480, 512, 513.6, 960, 1024].map((frames) => scriptBlockFor({ baseLatency: frames / RATE, sampleRate: RATE }))
        .concat([scriptBlockFor({ baseLatency: 512 / 44100, sampleRate: 44100 }), scriptBlockFor({ sampleRate: RATE }), scriptBlockFor({ baseLatency: 0, sampleRate: RATE }), scriptBlockFor({ baseLatency: NaN, sampleRate: RATE })]),
      [512, 512, 512, 512, 512, 1024, 1024, 512, 1024, 1024, 1024])
    //? review of 2.0.0-player.40's fixes: WebKit's baseLatency is its render quantum - 128 frames whatever buffer the
    //? hardware runs (AudioDestinationResampler::framesPerBuffer() is its render bus's length) - so on Apple's engine
    //? the voice can't tell, and keeps 1024
    check('...and on Apple\'s engine (Safari, every iPhone browser) 1024 whatever it says - its 128 frames are its render quantum, not the hardware\'s buffer',
      [128, 256, 512, 1024].map((frames) => scriptBlockFor({ baseLatency: frames / RATE, sampleRate: RATE }, true)).concat([scriptBlockFor({ sampleRate: RATE }, true)]),
      [1024, 1024, 1024, 1024, 1024])
    {
      const { isAppleEngine } = deckModule
      const original = Object.getOwnPropertyDescriptor(globalThis, 'navigator')
      const setNavigator = (value) => Object.defineProperty(globalThis, 'navigator', { value, configurable: true, writable: true })
      const seen = []
      for (const [vendor, prefixed] of [['Apple Computer, Inc.', false], ['Google Inc.', false], ['', false], ['', true]]) {
        setNavigator({ vendor })
        if (prefixed) globalThis.webkitAudioContext = function webkitAudioContext() {}
        seen.push([isAppleEngine(), scriptBlockFor({ baseLatency: 128 / RATE, sampleRate: RATE })])
        delete globalThis.webkitAudioContext
      }
      if (original) Object.defineProperty(globalThis, 'navigator', original)
      else delete globalThis.navigator
      seen.push([isAppleEngine(), scriptBlockFor({ baseLatency: 128 / RATE, sampleRate: RATE })])
      check('...Apple\'s engine told by navigator.vendor ("Apple Computer, Inc.") or the prefixed webkitAudioContext still given - Chromium\'s "Google Inc.", Firefox\'s "" and no navigator at all aren\'t, and keep 512 on a context saying 128 frames',
        seen, [[true, 1024], [false, 512], [false, 512], [true, 1024], [false, 512]])
    }

    //? A STALL, as Chromium has it (the delay-chain research's STALL=400 recordings): the main thread held 400 ms,
    //? the audio thread meanwhile asking for a block at each wrap; then the callbacks queued run back to back,
    //? every one stamped alike - the playbackTime of the last of them - and the ones after evenly spaced again.
    //? The k-th callback is the k-th block (measured: every evenly spaced stamp of every recording sits on it)
    const stall = (size, blocksBefore = 40, after = 800) => {
      const block = size / RATE
      const behind = Math.round(0.4 / block)
      const truth = [], stamps = []
      for (let k = 0; k < blocksBefore + behind + 1 + after; k++) {
        truth.push(1 + (k + 1) * block)
        stamps.push(k >= blocksBefore && k <= blocksBefore + behind ? 1 + (blocksBefore + behind + 1) * block : 1 + (k + 1) * block)
      }
      return { truth, stamps, burst: behind + 1, from: blocksBefore }
    }
    const ahead = (ats, truth, from = 0) => {
      let most = 0, blocks = 0
      for (let k = from; k < ats.length; k++) {
        const by = ats[k] - truth[k]
        most = Math.max(most, by)
        if (by > SCRIPT_STAMP_TOLERANCE_S) blocks++
      }
      return { mostMs: round(most * 1000, 3), blocks }
    }
    for (const size of [1024, 512]) {
      const { truth, stamps, burst, from } = stall(size)
      const was = ahead(countAsWas(stamps, size), truth, from + burst)
      const now = countNow(stamps, size)
      const afterBurst = now.slice(from + burst)
      check(`a 400 ms stall in blocks of ${size} - a burst of ${burst} callbacks stamped alike, then evenly spaced again: reproduced as it was, the count AHEAD of the real playbackTime after the burst by up to ${was.mostMs} ms for ${was.blocks} of the ${afterBurst.length} blocks after it (eased back at 0.02 ms a block); now never ahead by more than SCRIPT_STAMP_TOLERANCE_S, every block counted where it really plays - through the burst too - and the stamps followed exactly after it`,
        [was.mostMs > 20 && was.blocks > 600, ahead(now, truth).blocks, now.every((at, k) => Math.abs(at - truth[k]) < 1e-9), afterBurst.every((at, k) => at === stamps[from + burst + k])], [true, 0, true, true])
    }

    //? blocks the page was never asked for (WebKit drops them while its main thread is busy - the hardware played
    //? on without them): a jump of ten, and evenly spaced from there
    {
      const size = 1024, block = size / RATE
      const stamps = [], truth = []
      for (let k = 0; k < 60; k++) {
        const real = 1 + (k + 1 + (k >= 20 ? 10 : 0)) * block
        truth.push(real)
        stamps.push(real)
      }
      const now = countNow(stamps, size)
      check('ten blocks never asked for (WebKit\'s drop): counted on through the jump and the next block, and anchored at the one after - two evenly spaced in a row, each as far on - by the least of them; exact from there (as it was, at once)',
        [[20, 21].map((k) => round((truth[k] - now[k]) / block, 6)), now.slice(22).every((at, k) => Math.abs(at - truth[22 + k]) < 1e-9), countAsWas(stamps, size)[20] === truth[20]], [[10, 10], true, true])
    }
    //? review of 2.0.0-player.40: the drop's anchor by the LEAST of the stamps waited on, and the count re-proved
    //? after it - the held stamp on time and the three after it 3 ms late (the page late with them, evenly), or all
    //? of them 3 ms late; then on time. Anchored by the least, it lands on the truth; anchored forward by late
    //? stamps, it is unproven, and the next stamp - earlier than the count - sets it back at once
    {
      const size = 1024, block = size / RATE
      const run = (lateMs) => {
        const stamps = [], truth = []
        for (let k = 0; k < 160; k++) {
          const real = 1 + (k + 1 + (k >= 20 ? 10 : 0)) * block
          truth.push(real)
          stamps.push(real + (k >= 20 && k < 20 + lateMs.length ? lateMs[k - 20] / 1000 : 0))
        }
        const now = countNow(stamps, size)
        return [now.findIndex((at, k) => k >= 20 && Math.abs(at - truth[k]) < 1e-9), ahead(now, truth).blocks, round(ahead(now, truth).mostMs, 3)]
      }
      check('ten blocks dropped, the held stamp on time and the three after it 3 ms late, evenly: anchored by the least of them - on the truth, never ahead; and all three 3 ms late: anchored 3 ms ahead for that block alone, the next stamp (on time) setting the count back - unproven after a forward anchor (without both rules, 3 ms ahead for 100 blocks of the first, 2.1 s; without the second, of the second)',
        [run([0, 3, 3, 3]), run([3, 3, 3])], [[23, 0, 0], [23, 1, 3]])
    }
    //? the page late with block after block (a throttled CPU - the research's 6x runs): its stamps late by 5 to 11
    //? blocks, coming unevenly - never evenly spaced AND all that far on - then on time again
    {
      const size = 512, block = size / RATE
      const late = [0, 0, 6, 6, 7, 5, 9, 9, 11, 8, 8, 7, 10, 10, 6, 5, 5, 11, 9, 8, 6, 7, 7, 5, 9, 10, 11, 6, 5, 0, 0]
      const stamps = [], truth = []
      let dispatched = 0
      for (let k = 0; k < 200; k++) {
        const wrap = k * block
        const lateness = k >= 20 && k < 20 + late.length ? late[k - 20] : 0
        dispatched = Math.max(dispatched, wrap + lateness * block)
        truth.push(1 + wrap + block)
        stamps.push(1 + dispatched + block)
      }
      const now = countNow(stamps, size), was = countAsWas(stamps, size)
      check('the page late with block after block, its stamps 5-11 blocks late and uneven: never anchored forward - every block counted where it plays (as it was, anchored to a late stamp and ahead by up to 11 blocks)',
        [ahead(now, truth).blocks, round(ahead(was, truth).mostMs, 1) > 50], [0, true])
    }
    //? the first block asked for late - its stamp a 128-frame render late, the rest on time
    {
      const size = 512, block = size / RATE, quantum = 128 / RATE
      const truth = Array.from({ length: 100 }, (_, k) => 1 + (k + 1) * block)
      const stamps = truth.map((at, k) => (k === 0 ? at + quantum : at))
      const now = countNow(stamps, size)
      check('the first block asked for a render late: the count, unproven yet, set back to the next stamp - earlier than it, as a stamp never is - and exact from there (as it was, 2.7 ms ahead until eased: 133 blocks of 512)',
        [round((now[0] - truth[0]) * 1000, 3), now.slice(1).every((at, k) => at === truth[k + 1]), ahead(countAsWas(stamps, size), truth).blocks > 60], [2.667, true, true])
    }
    //? a stamp far earlier than the count, and no later than the stamp before it (as it is while the count agrees
    //? with the stamps, a block being shorter than SCRIPT_REANCHOR_S): first counted on as a burst's, and anchored
    //? at the next callback (until 2.0.0-player.40, at once)
    {
      const size = 1024, block = size / RATE
      const stamps = Array.from({ length: 30 }, (_, k) => 1 + (k + 1) * block - (k >= 15 ? 5 * block : 0))
      const now = countNow(stamps, size)
      check('a stamp five blocks EARLIER than the count (past SCRIPT_REANCHOR_S): counted on as a burst\'s (it is no later than the stamp before it), and anchored at the next - one block on from it - and from there',
        [SCRIPT_REANCHOR_S, now[15] === stamps[14] + block, now.slice(16).every((at, k) => at === stamps[16 + k])], [0.064, true, true])
    }
    //? stamps never on time and never early - each 2-20 ms late, as a page busy now and then makes them, or a clock
    //? stamped late by its own grain - for 20 s: the count eased toward their LOWER edge stays by the truth; toward
    //? their running mean (as it was), it drifted that far ahead
    {
      const size = 1024, block = size / RATE
      let seed = 3
      const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648)
      const n = Math.round(20 / block)
      const truth = Array.from({ length: n }, (_, k) => 1 + (k + 1) * block)
      const stamps = truth.map((at, k) => (k === 0 ? at : at + 0.002 + random() * 0.018))
      const now = countNow(stamps, size), was = countAsWas(stamps, size)
      const end = (ats) => round((ats[n - 1] - truth[n - 1]) * 1000, 2)
      check(`stamps 2-20 ms late, never on time, for 20 s: the count eased toward their lower edge - ${end(now)} ms ahead of the truth at the end, within 5 (as it was, toward their mean: ${end(was)} ms ahead)`,
        [end(now) >= 0 && end(now) <= 5, end(was) > 8], [true, true])
    }
    //? the constants in seconds: stamps evenly 10 ms late of the count (WebKit's - not within the tolerance, not
    //? far enough to anchor) for a second of sound, in blocks of 1024 and of 512 - the count eased the same
    {
      const moved = (size) => {
        const block = size / RATE
        const n = Math.round(1 / block)
        const stamps = Array.from({ length: n + 1 }, (_, k) => 1 + (k + 1) * block + (k === 0 ? 0 : 0.01))
        const ats = countNow(stamps, size)
        return (ats[n] - (1 + (n + 1) * block)) * 1000
      }
      const big = moved(1024), small = moved(512)
      check(`the counted clock\'s easing in seconds: stamps 10 ms late for a second of sound move it ${round(big, 3)} ms in blocks of 1024, ${round(small, 3)} in blocks of 512 - SCRIPT_SLEW_PER_S a second (0.9375 ms) either way (with the constants a block, 512 moved it twice as far)`,
        [Math.abs(big - small) < 0.03, Math.abs(big - 0.9375) < 0.05], [true, true])
    }
  }
  console.log('\n2.0.0-player.40: the main-thread voice in blocks of 512 where the hardware renders that few - its lag, a stall through the deck, and Debug\'s late blocks')
  {
    noWorklet = true
    globalThis.isSecureContext = false
    const realRender = voice.renderVoice, realCommand = voice.voiceCommand
    const rendered = []
    const told = []
    voice.renderVoice = (state, outputs, frames, rate, now) => { rendered.push(now); return realRender(state, outputs, frames, rate, now) }
    voice.voiceCommand = (state, said, now, rate) => { told.push({ said, now }); return realCommand(state, said, now, rate) }
    const start = async (frames, speakerLead = null, output = undefined) => {
      baseLatency = frames === undefined ? undefined : frames / 48000
      outputTimestampLead = speakerLead
      outputLatency = output
      const host = fakeHost()
      const deck = new Deck(host)
      deck.setShowing(true)
      deck.songChanged(host.song().id)
      wakeDeckAudio()
      await settle()
      const script = scripts.at(-1)
      playBlocksQuietly(script, 1)
      for (let i = 0; i < 4; i++) await settle()
      return { host, deck, script, context: script.context }
    }
    //? and its outputLatency, where it says one (Chromium's 8 ms at 128-frame renders, 72-80 at 1024 - the real
    //? page's; a Bluetooth headset's is most of it) - none where it doesn't, as Safari before 18.4 doesn't
    for (const [frames, size, output] of [[128, 512, 0.008], [512, 512, undefined], [1024, 1024, 0.076], [undefined, 1024, undefined]]) {
      const { deck, script } = await start(frames, null, output)
      check(`a context whose hardware renders ${frames ?? 'it doesn\'t say how many'} frames at a time${output ? `, its output latency ${output * 1000} ms` : ', saying nothing of its output latency'}: the main-thread voice in blocks of ${size} - and Debug told so, with what the context says`,
        [script.args, deckReport().latency?.block, deckReport().latency?.base, deckReport().latency?.output, round(deckReport().latency?.design ?? 0, 6)],
        [[size, 0, 2], size, frames === undefined ? null : frames / 48000, output ?? null, round(voice.HAND_DELAY_S + (2 * size) / 48000 + voice.VOICE_LOOKAHEAD_S, 6)])
      deck.destroy()
    }
    outputLatency = undefined
    {
      //? what the device's audio adds, as getOutputTimestamp() says it where a browser has it: the render clock
      //? 11.7 ms ahead of what is at the speaker - read as the clock is, and Debug told the median
      const { deck, script } = await start(128, 0.0117)
      pump(script, 8)
      advance(1000)
      deck.setShowing(false)
      deck.setShowing(true)
      check('where the browser has getOutputTimestamp(): the render clock\'s lead on the speaker read as the deck reads its clock, and Debug told it - 11.7 ms here',
        round((deckReport().latency?.speaker ?? 0) * 1000, 3), 11.7)
      deck.destroy()
      outputTimestampLead = null
    }
    {
      //? the lag: a take, and the hand's samples after it, each heard two blocks of 512 after its own time
      const { host, deck, script } = await start(128)
      told.length = 0
      deck.pressed(clock)
      deck.takeOver()
      for (let ms = 16; ms <= 64; ms += 16) deck.hand(clock + ms, (ms / 1000) * 2 * Math.PI, 60 + (ms / 1000) * SECONDS_PER_TURN)
      pump(script, 2)
      const take = told.find(({ said }) => said.type === 'take')?.said
      const stamp = (time) => time / 1000 + deckModule.deckClockMapping().offset
      check('in blocks of 512: a take heard SCRIPT_LAG_BLOCKS blocks of 512 after its own time - 21.3 ms, half the 1024 blocks\' lag - and the hand\'s samples after it the same',
        [round((take.time - stamp(clock)) * 1000, 3), told.filter(({ said }) => said.type === 'hand').map(({ said }, i) => round((said.time - stamp(clock + (i === 0 ? 0 : i * 16))) * 1000, 3))],
        [round((2 * 512 / 48000) * 1000, 3), [21.333, 21.333, 21.333, 21.333, 21.333]])
      deck.release(clock, 'cancel')
      deck.destroy()
      void host
    }
    //? stamps as the browser gives them, and the clock as the handler reads it after its block: `stamp` the
    //? block's playbackTime, `clockAfter` currentTime once it is written
    const ask = (script, stamp, clockAfter) => {
      script.context.currentTime = clockAfter
      return fill(script, stamp)
    }
    for (const size of [1024, 512]) {
      //? A STALL through the deck: blocks as ever, then 400 ms with none run, then the burst Chromium runs -
      //? every callback stamped alike - and evenly spaced from there; each rendered at its counted time
      const { deck, script, context } = await start(size === 512 ? 128 : 1024)
      const block = size / 48000
      const t0 = context.currentTime + 2 * block
      let k = 0
      for (; k < 20; k++) ask(script, t0 + k * block, t0 + (k - 2) * block)
      rendered.length = 0
      const behind = Math.round(0.4 / block)
      const from = k
      for (; k <= from + behind; k++) ask(script, t0 + (from + behind) * block, t0 + (from + behind - 1) * block)
      for (; k < from + behind + 31; k++) ask(script, t0 + k * block, t0 + (k - 2) * block)
      const wanted = Array.from({ length: behind + 31 }, (_, i) => t0 + (from + i) * block)
      check(`a 400 ms stall in blocks of ${size} - ${behind + 1} callbacks run back to back, stamped alike: each rendered at the time its block really plays (the k-th callback the k-th block), through the burst and every block after it - as it was, the burst's stamp anchored the count and each callback after it added a block, ${size === 1024 ? 'up to 64 ms' : 'up to 21 ms'} ahead for a minute`,
        [rendered.length, rendered.every((at, i) => Math.abs(at - wanted[i]) < 1e-9)], [behind + 31, true])
      deck.destroy()
    }
    //? DEBUG'S LATE BLOCKS, against a browser that replays: the hardware renders 128 frames at a time; the audio
    //? thread asks for each block as it wraps, the page runs the ask when it is free - and Chromium stamps the
    //? block from the clock as the page runs it (playbackTime = currentTime + a block), so as it was the count
    //? (currentTime as the ask ran, against the stamp) could never fire. A block written once the clock has
    //? passed its start played the block before it again - that is what is counted now (currentTime once the
    //? block is written, against its counted start). In 128-frame renders, as the clock moves
    for (const size of [1024, 512]) {
      noWorklet = true
      //? 128-frame renders said (blocks of 512) - or not said at all (blocks of 1024)
      baseLatency = size === 512 ? 128 / 48000 : undefined
      const host = fakeHost()
      const deck = new Deck(host)
      deck.setShowing(true)
      wakeDeckAudio()
      await settle()
      const script = scripts.at(-1)
      const quanta = size / 128, q = 128 / 48000
      let replayed = 0, asWas = 0, seed = 7, done = 0
      const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648)
      for (let k = 0; k < 200; k++) {
        const wrap = k * quanta
        //? the page busy now and then: the ask run up to a block and a half after its wrap, never before the
        //? one before it is done; the render now and then spanning a 128-frame render
        const late = k > 0 && k % 7 === 3 ? Math.floor(random() * 1.5 * quanta) + 1 : 0
        const runs = Math.max(wrap + late, done)
        done = runs + (random() < 0.2 ? 1 : 0)
        if (done > wrap + quanta) replayed++
        if (runs * q > (runs + quanta) * q) asWas++
        ask(script, (runs + quanta) * q, done * q)
      }
      deck.release(clock, 'cancel')
      deck.songChanged('another')
      const health = deckReport().health
      check(`Debug's late blocks in blocks of ${size}, a browser that replays a block written after its start: ${replayed} replayed, ${health.lateBlocks} counted - every one, and no other (as it was, currentTime as the ask ran against Chromium's stamp: ${asWas})`,
        [replayed > 5, health.lateBlocks, health.blocks, asWas], [true, replayed, 200, 0])
      deck.destroy()
    }
    voice.renderVoice = realRender
    voice.voiceCommand = realCommand
    baseLatency = undefined
    noWorklet = false
    delete globalThis.isSecureContext
  }

  console.log('\n2.0.0-player.40: a quick grab is taken from the press - heard from when the finger went down')
  {
    const { TAKE_BACK_S, HOLD_MS } = deckModule
    const stamp = (time) => time / 1000 + deckModule.deckClockMapping().offset
    const near = (a, b, within = 1e-9) => Math.abs(a - b) <= within
    const since = () => portMessages.length
    const sent = (from) => portMessages.slice(from).filter((m) => m.type !== 'window')
    //? the face as Turntable draws it: the deck's angle, inside the hand's turn since the press once the record is
    //? taken (or the slop crossed) - and a frame drawn at this very moment, the clock not moved
    const DEG = 180 / Math.PI
    const drawNow = () => {
      const due = frames
      frames = []
      for (const frame of due) frame.run(clock)
    }
    {
      //? a tap: moves inside the slop kept, nothing else - nothing sent, nothing paused, nothing taken
      const { host, deck } = await fresh()
      runFrames(2)
      const before = since()
      const t0 = clock
      deck.pressed(t0)
      deck.touched(t0 + 16, 0.01, 0.003)
      deck.touched(t0 + 33, 0.02, 0.006)
      advance(60)
      const released = deck.release(clock, 'up')
      check('a tap - its moves inside a tap\'s few pixels kept by the deck: nothing sent the voice, nothing paused, nothing taken, nothing sought',
        [sent(before), host.calls, deck.taken(), released], [[], [], false, { seek: null, play: false }])
      deck.destroy()
    }
    {
      //? a quick grab of a paused record: the take at the press's moment and place, then the samples since
      const { host, deck } = await fresh()
      host.isPlaying = false
      deck.playingChanged(false)
      advance(400)
      runFrames(1)
      const before = since()
      const t0 = clock
      deck.pressed(t0)
      //? frames drawn under the slop: the platter still winding down from the pause, the finger not past a tap
      runFrames(1)
      deck.touched(t0 + 16, 0.01, 0.0029)
      advance(1)
      runFrames(1)
      const drawn = host.angle
      deck.touched(t0 + 33, 0.03, 0.0086)
      const anchor = deck.takeOver(t0 + 33, true)
      deck.hand(t0 + 33, 0.03, anchor + 0.0086)
      const out = sent(before)
      check('a quick grab of a paused record - past a tap\'s pixels 33 ms on: taken FROM THE PRESS - its take at the press\'s own moment and place, still, then every sample since at its own time (the one that crossed sent once, by the hand\'s own call)',
        [out.map((m) => m.type), anchor, out[0].at, out[0].rate, near(out[0].time, stamp(t0)), out.slice(1).map((m) => round(m.at, 4)), out.slice(1).every((m, i) => near(m.time, stamp([t0, t0 + 16, t0 + 33][i])))],
        [['take', 'hand', 'hand', 'hand'], 60, 60, 0, true, [60, 60.0029, 60.0086], true])
      drawNow()
      check('...its turn counting from the press - the record where the hand has it - and the face, as Turntable draws it (the deck\'s angle inside the hand\'s turn), carrying straight on from the frame drawn as the slop was crossed: no jump (review of 2.0.0-player.40 - it stepped back by the platter\'s run under the slop)',
        [deck.anchor(), round(host.angle + 0.03 * DEG, 6)], [60, round(drawn, 6)])
      deck.release(clock, 'cancel')
      deck.destroy()
    }
    for (const speed of [0.5, 2]) {
      //? a playing record at the fader's speed, grabbed quickly: the song played on under the slop and pauses at
      //? the crossing; the take is where it was at the press, at its speed - the place a take at the crossing
      //? would have the voice start from, so the record's sound joins the song as it did
      const { host, deck } = await fresh()
      deck.speedChanged(speed)
      runFrames(3)
      const before = since()
      const t0 = clock
      deck.pressed(t0)
      advance(24)
      deck.touched(t0 + 24, 0.02, 0.006)
      //? a frame drawn under the slop at the crossing's moment: the platter turning on at the record's speed
      runFrames(1)
      const drawn = host.angle
      host.at = 60 + speed * 0.04
      deck.touched(t0 + 40, 0.04, 0.012)
      const anchor = deck.takeOver(t0 + 40, true)
      deck.hand(t0 + 40, 0.04, anchor + 0.012)
      const out = sent(before)
      const take = out.find((m) => m.type === 'take')
      //? where the voice starts, HAND_DELAY_S behind, by the take as it is now and as a take at the crossing was
      const startNow = take.at + take.rate * (stamp(clock) - voice.HAND_DELAY_S - take.time)
      const startWas = host.at + speed * (stamp(clock) - voice.HAND_DELAY_S - stamp(t0 + 40))
      drawNow()
      check(`a quick grab of a record playing at ${speed}x: paused at the crossing (the song played on under the slop); taken from the press - where the song was then, at its speed, stamped then - so the voice starts where a take at the crossing would have it (the join as it was); the face, drawn with the hand's turn, carrying straight on from the frame before - no jump (as first built, from the platter's angle at the press, it stepped back ${speed === 2 ? '14' : '2'} degrees here)`,
        [host.calls, round(anchor, 9), take.rate, near(take.time, stamp(t0)), near(startNow, startWas, 1e-9), round(host.angle + 0.04 * DEG, 6)],
        [['hold'], round(60, 9), speed, true, true, round(drawn, 6)])
      deck.release(clock, 'cancel')
      deck.destroy()
    }
    {
      //? a press older than the voice can still be told of (TAKE_BACK_S): taken from its oldest sample within it
      const { host, deck } = await fresh()
      host.isPlaying = false
      deck.playingChanged(false)
      advance(400)
      const before = since()
      const t0 = clock
      deck.pressed(t0)
      for (const [ms, offset] of [[40, 0.002], [80, 0.004], [120, 0.006]]) deck.touched(t0 + ms, offset * 3, offset)
      advance(130)
      const anchor = deck.takeOver(t0 + 120, true)
      const out = sent(before)
      check(`a press older than TAKE_BACK_S (${round(TAKE_BACK_S * 1000, 1)} ms) by the time it is taken (130 ms on): taken from its oldest sample within it - 40 ms after the press, where the hand had it then - the turn still counting from the press`,
        [round(TAKE_BACK_S, 6), out.map((m) => m.type), round(out[0].at, 6), near(out[0].time, stamp(t0 + 40)), out.slice(1).map((m) => round(m.at, 6)), anchor],
        [round(voice.HAND_DELAY_S - 0.02, 6), ['take', 'hand', 'hand'], 60.002, true, [60.002, 60.004], 60])
      deck.release(clock, 'cancel')
      deck.destroy()
    }
    {
      //? on the main thread the voice holds what it is told SCRIPT_LAG_BLOCKS blocks on, so it can be told of a
      //? moment further back: SCRIPT_TAKE_BACK_S - a press 110 ms old taken from the press, one 130 ms old from
      //? its oldest sample within 115
      noWorklet = true
      globalThis.isSecureContext = false
      const taken = []
      for (const age of [110, 130]) {
        const host = fakeHost({ isPlaying: false })
        const deck = new Deck(host)
        deck.setShowing(true)
        deck.songChanged(host.song().id)
        wakeDeckAudio()
        await settle()
        const script = scripts.at(-1)
        playBlocksQuietly(script, 1)
        for (let i = 0; i < 4; i++) await settle()
        const told = []
        const own = voice.voiceCommand
        voice.voiceCommand = (state, said, at, rate) => { told.push(said); return own(state, said, at, rate) }
        const t0 = clock
        deck.pressed(t0)
        for (const [ms, offset] of [[10, 0.001], [40, 0.002], [80, 0.004], [age - 10, 0.006]]) deck.touched(t0 + ms, offset * 3, offset)
        advance(age)
        deck.takeOver(t0 + age - 10, true)
        pump(script, 1)
        voice.voiceCommand = own
        const take = told.find((said) => said.type === 'take')
        taken.push([round(deckModule.SCRIPT_TAKE_BACK_S, 6), round((take.time - (deckModule.SCRIPT_LAG_BLOCKS * 1024) / 48000 - stamp(t0)) * 1000, 3), round(take.at, 6)])
        deck.release(clock, 'cancel')
        deck.destroy()
      }
      check('on the main thread (its lag holding what it is told two blocks on): a press 110 ms old taken from the press itself; 130 ms old, from its oldest sample within SCRIPT_TAKE_BACK_S (115 ms) - 40 ms in',
        taken, [[0.115, 0, 60], [0.115, 40, 60.002]])
      noWorklet = false
      delete globalThis.isSecureContext
    }
    {
      //? the hand's samples inside the slop count toward the let-go's speed: a finger still for 20 ms, then fast
      //? past the slop, let go 70 ms later - the speed over its last 90 ms reads the still start from the
      //? samples themselves, not a straight line from the press to the crossing
      const { host, deck } = await fresh()
      host.isPlaying = false
      deck.playingChanged(false)
      advance(400)
      const t0 = clock
      deck.pressed(t0)
      deck.touched(t0 + 10, 0, 0)
      deck.touched(t0 + 20, 0, 0)
      deck.touched(t0 + 30, 0.1, 0.1 / (2 * Math.PI) * SECONDS_PER_TURN)
      advance(30)
      const anchor = deck.takeOver(t0 + 30, true)
      const samples = [{ time: t0, turned: 0 }, { time: t0 + 10, turned: 0 }, { time: t0 + 20, turned: 0 }, { time: t0 + 30, turned: 0.1 }]
      for (let ms = 30; ms <= 100; ms += 10) {
        const turned = 0.1 + ((ms - 30) / 1000) * 4 * Math.PI
        if (ms > 30) samples.push({ time: t0 + ms, turned })
        deck.hand(t0 + ms, turned, anchor + (turned / (2 * Math.PI)) * SECONDS_PER_TURN)
      }
      advance(70)
      const released = deck.release(t0 + 100, 'up')
      const at = anchor + (samples.at(-1).turned / (2 * Math.PI)) * SECONDS_PER_TURN
      const wanted = platter.coast(at, platter.releaseSpeed(samples, t0 + 100), 425).x
      const straight = platter.coast(at, platter.releaseSpeed([samples[0], ...samples.slice(3)], t0 + 100), 425).x
      check('a quick flick let go 100 ms after the press: its speed read over the hand\'s own samples since the press, the still start inside the slop included - not a line from the press to the crossing',
        [round(released.seek, 6), round(released.seek, 6) !== round(straight, 6)], [round(wanted, 6), true])
      deck.destroy()
    }
    {
      //? a press that rests HOLD_MS is taken as it was - at its own moment, where the song is then
      const { host, deck } = await fresh()
      const before = since()
      const t0 = clock
      deck.pressed(t0)
      deck.touched(t0 + 30, 0.001, 0.0003)
      advance(HOLD_MS + 1)
      const out = sent(before)
      check('a press that rests HOLD_MS (a move inside the slop meanwhile): taken as it was - at the timer\'s moment, where the song is then, at its speed', [host.calls, out.map((m) => m.type), out[0].at, out[0].rate, near(out[0].time, stamp(t0 + HOLD_MS)), deck.anchor()],
        [['hold', 'grabbed'], ['take', 'hand'], 60, 1, true, 60])
      deck.release(clock, 'cancel')
      deck.destroy()
    }
    {
      //? a record coasting with its sound, caught by a quick grab: where the plan had it at the press
      const { host, deck } = await fresh()
      host.isPlaying = false
      deck.playingChanged(false)
      advance(400)
      deck.pressed(clock)
      deck.takeOver()
      flickBack(deck, 60)
      deck.release(clock, 'up')
      runFrames(4)
      const motion = deck.motion
      const before = since()
      const t0 = clock
      deck.pressed(t0)
      runFrames(2)
      deck.touched(clock, 0.05, 0.014)
      const crossing = clock
      deck.takeOver(crossing, true)
      const out = sent(before)
      const hand = out.find((m) => m.type === 'hand')
      check('a coasting record caught by a quick grab: its sound followed from the press - the hand\'s first knot where the plan had the record as the finger went down, at that moment (the coast\'s frames after it let go of, in the voice)',
        [motion.kind, motion.role, out.some((m) => m.type === 'take'), round(hand.at, 9), near(hand.time, stamp(t0))],
        ['plan', 'coast', false, round(platter.planAt(motion.plan, (t0 - motion.since) / 1000).x, 9), true])
      deck.release(clock, 'cancel')
      deck.destroy()
    }
    //? review of 2.0.0-player.40: a MOVING record whose press is past the reach - a slow hand, or a press that waits
    //? a moment before it turns, crossing the slop 100-250 ms on - was put back where it was at the press though the
    //? voice had played it on since: a playing song's join came later (more of it heard again) and a sounding coast's
    //? path stepped back, the voice rushing backwards under a near-still finger. Now it is taken where it had got to
    //? on its own by the sample it is taken from, and the hand carries on from there
    {
      const lines = []
      for (const speed of [1, 2]) {
        for (const age of [160, 240]) {
          const { host, deck } = await fresh()
          deck.speedChanged(speed)
          runFrames(3)
          const before = since()
          const t0 = clock
          deck.pressed(t0)
          //? a slow hand, a tenth of the record's speed: a sample a frame, the frames drawn, the platter turning on
          const hand = 0.1 * speed
          const samples = []
          for (let ms = 16; ms <= age; ms += 16) {
            runFrames(1)
            const offset = (hand * ms) / 1000
            samples.push({ time: clock, turned: (offset / SECONDS_PER_TURN) * 2 * Math.PI, offset })
            deck.touched(clock, samples.at(-1).turned, offset)
          }
          const crossing = samples.at(-1)
          //? handled 5 ms after the sample's own time, the song playing on to then
          advance(5)
          drawNow()
          const drawn = host.angle
          host.at = 60 + (speed * (clock - t0)) / 1000
          const anchor = deck.takeOver(crossing.time, true)
          deck.hand(crossing.time, crossing.turned, anchor + crossing.offset)
          drawNow()
          const out = sent(before)
          const take = out.find((m) => m.type === 'take')
          const from = samples.find((sample) => sample.time >= clock - TAKE_BACK_S * 1000)
          //? the take's line (its place at its speed) carried to the crossing's moment, against where the song paused
          //? there: HEAD's take, at the crossing, was on that very line - so the voice starts where it did
          const joinMs = ((take.at + take.rate * (stamp(crossing.time) - take.time) - host.at) / speed) * 1000
          const knots = out.filter((m) => m.type === 'hand')
          lines.push([speed, age, near(take.time, stamp(from.time)), take.time > stamp(t0), round(joinMs, 6),
            round(anchor + from.offset - take.at, 9), round(knots.at(-1).at - take.at - (crossing.offset - from.offset), 9),
            round(host.angle + crossing.turned * DEG - drawn, 6)])
          deck.release(clock, 'cancel')
          deck.destroy()
        }
      }
      check('a record playing at 1x and 2x, a slow hand (a tenth of its speed) crossing the slop 160 and 240 ms after the press - past TAKE_BACK_S: taken from its oldest sample within reach, on the song\'s own line there - the take carried to the crossing is where the song paused (the join as a take at the crossing had it, 0 ms), the hand\'s turn carrying on from the take - and the face, drawn, carrying straight on (as first built, at the press\'s place: 72 and 144 ms more of the song heard again)',
        lines, [[1, 160, true, true, 0, 0, 0, 0], [1, 240, true, true, 0, 0, 0, 0], [2, 160, true, true, 0, 0, 0, 0], [2, 240, true, true, 0, 0, 0, 0]])
    }
    {
      //? the same on the main thread, its reach SCRIPT_TAKE_BACK_S: a press 200 ms old
      noWorklet = true
      globalThis.isSecureContext = false
      const lines = []
      for (const speed of [1, 2]) {
        const host = fakeHost({})
        const deck = new Deck(host)
        deck.setShowing(true)
        deck.songChanged(host.song().id)
        deck.speedChanged(speed)
        wakeDeckAudio()
        await settle()
        const script = scripts.at(-1)
        playBlocksQuietly(script, 1)
        for (let i = 0; i < 4; i++) await settle()
        const told = []
        const own = voice.voiceCommand
        voice.voiceCommand = (state, said, at, rate) => { told.push(said); return own(state, said, at, rate) }
        const t0 = clock
        deck.pressed(t0)
        const samples = []
        for (let ms = 20; ms <= 200; ms += 20) {
          const offset = (0.1 * speed * ms) / 1000
          samples.push({ time: t0 + ms, turned: (offset / SECONDS_PER_TURN) * 2 * Math.PI, offset })
          deck.touched(t0 + ms, samples.at(-1).turned, offset)
        }
        advance(205)
        host.at = 60 + (speed * 205) / 1000
        const crossing = samples.at(-1)
        const anchor = deck.takeOver(crossing.time, true)
        pump(script, 1)
        voice.voiceCommand = own
        const lag = (deckModule.SCRIPT_LAG_BLOCKS * 1024) / 48000
        const take = told.find((said) => said.type === 'take')
        const from = samples.find((sample) => sample.time >= clock - deckModule.SCRIPT_TAKE_BACK_S * 1000)
        const joinMs = ((take.at + take.rate * (stamp(crossing.time) + lag - take.time) - host.at) / speed) * 1000
        lines.push([speed, round((take.time - lag - stamp(t0)) * 1000, 3), round((from.time - t0), 3), round(joinMs, 6), round(anchor + from.offset - take.at, 9)])
        deck.release(clock, 'cancel')
        deck.destroy()
      }
      check('...and on the main thread (SCRIPT_TAKE_BACK_S), a press 200 ms old at 1x and 2x: taken from its oldest sample within reach (100 ms in), on the song\'s line - the join as a take at the crossing had it (as first built: 90 ms more heard again)',
        lines, [[1, 100, 100, 0, 0], [2, 100, 100, 0, 0]])
      noWorklet = false
      delete globalThis.isSecureContext
    }
    {
      //? a record coasting with its sound, caught by a quick grab whose press is 48, 96, 160 and 224 ms before the
      //? crossing (a hand all but still): the hand's first knot on the coast's own line at its moment - the press,
      //? within reach; past it, the oldest sample within it - so the path doesn't step; the voice, replayed as the
      //? worklet would run it, never rushing backwards; and the face, drawn, carrying straight on from the frame
      //? before (as first built: the knot 132 and 242 ms of song behind the coast past the reach, the voice running
      //? at -1.15x and -2.03x; the face stepping back 20 and 38 degrees within it)
      const lines = []
      for (const age of [48, 96, 160, 224]) {
        const posts = []
        const ownPush = portMessages.push
        portMessages.push = (...messages) => {
          for (const message of messages) posts.push({ message, clock })
          return ownPush.apply(portMessages, messages)
        }
        const { host, deck } = await fresh()
        host.isPlaying = false
        deck.playingChanged(false)
        advance(400)
        deck.pressed(clock)
        deck.takeOver()
        //? a forward flick, a turn and a half a second for its last 100 ms
        for (let ms = 0; ms <= 100; ms += 10) deck.hand(clock + ms, (ms / 1000) * 2 * Math.PI * 1.5, 60 + (ms / 1000) * SECONDS_PER_TURN * 1.5)
        clock += 100
        deck.release(clock, 'up')
        runFrames(4)
        const motion = deck.motion
        const t0 = clock
        deck.pressed(t0)
        let turned = 0
        const samples = []
        for (let i = 1; i <= Math.floor(age / 16); i++) {
          runFrames(1)
          turned += 0.001
          samples.push({ time: clock, turned, offset: (turned / (2 * Math.PI)) * SECONDS_PER_TURN })
          deck.touched(clock, turned, samples.at(-1).offset)
        }
        const crossing = samples.at(-1)
        const drawn = host.angle
        const firstPost = posts.length
        deck.takeOver(crossing.time, true)
        deck.hand(crossing.time, crossing.turned, deck.anchor() + crossing.offset)
        drawNow()
        const face = host.angle + crossing.turned * DEG - drawn
        //? the hand holding still for 300 ms, a sample a frame
        for (let i = 0; i < 18; i++) {
          runFrames(1)
          deck.hand(clock, crossing.turned, deck.anchor() + crossing.offset)
        }
        portMessages.push = ownPush
        const knot = posts.slice(firstPost).find(({ message }) => message.type === 'hand').message
        const from = age <= 96 ? t0 : samples.find((sample) => sample.time >= crossing.time - TAKE_BACK_S * 1000).time
        //? the voice as the worklet runs it: each message applied at the first 128-frame render at or after it was posted
        const toContext = (ms) => ms / 1000 + deckModule.deckClockMapping().offset
        const state = voice.newVoiceState()
        let k = 0
        let now = toContext(posts[0].clock)
        let slowest = Infinity
        const heardFrom = toContext(t0) + voice.HAND_DELAY_S - 0.03, heardTo = toContext(crossing.time) + voice.HAND_DELAY_S + 0.25
        while (now < toContext(clock) + 0.3) {
          while (k < posts.length && toContext(posts[k].clock) <= now) voice.voiceCommand(state, posts[k++].message, now, SR)
          voice.renderVoice(state, [new Float32Array(128), new Float32Array(128)], 128, SR, now)
          if (now >= heardFrom && now <= heardTo) slowest = Math.min(slowest, state.rate)
          now += 128 / SR
        }
        lines.push([age, motion.role, motion.sounding, near(knot.time, stamp(from)), round(knot.at - platter.planAt(motion.plan, (from - motion.since) / 1000).x, 9), slowest > -0.25, round(face, 6)])
        deck.release(clock, 'cancel')
        deck.destroy()
      }
      check('a sounding coast caught by a quick grab, the press 48, 96, 160 and 224 ms before the crossing: the hand\'s first knot on the coast\'s own line at its moment (the press within TAKE_BACK_S, the oldest sample within it past it) - no step - the voice never below -0.25x under a near-still finger, and the face, drawn, carrying straight on',
        lines, [48, 96, 160, 224].map((age) => [age, 'coast', true, true, 0, true, 0]))
    }
  }
  console.log('\n2.0.0-player.40: a recording in blocks of 512, and blocks that share a stamp - the hardware asking for two at once')
  {
    noWorklet = true
    globalThis.isSecureContext = false
    {
      //? the recorder's file says the block, and the lag it makes - a replay reads them there
      baseLatency = 128 / 48000
      let captured = null
      const makeUrl = globalThis.URL.createObjectURL
      globalThis.URL.createObjectURL = (blob) => { captured = blob; return 'blob:deck-recording' }
      const host = fakeHost()
      const deck = new Deck(host)
      deck.setShowing(true)
      deck.songChanged(host.song().id)
      wakeDeckAudio()
      await settle()
      const script = scripts.at(-1)
      playBlocksQuietly(script, 1)
      for (let i = 0; i < 4; i++) await settle()
      check('recording in blocks of 512: started', deckModule.recordDeckSound(1), null)
      const tap = scripts.at(-1)
      deck.pressed(clock)
      deck.takeOver()
      pump(script, 3)
      for (let i = 0; i < 2; i++) tap.onaudioprocess({ inputBuffer: { numberOfChannels: 2, getChannelData: () => new Float32Array(4096) }, playbackTime: 1 + i * 4096 / 48000 })
      advance(1100)
      await settle()
      const file = JSON.parse(await captured.text())
      check('...its file (version 3) says the voice rendered blocks of 512 - its lag two of them, 21.3 ms - and what the context said of its own latency',
        [file.version, file.block, round(file.scriptLagSeconds, 9), file.latency?.block, file.latency?.base, deckModule.deckRecordingData()], [3, 512, round(1024 / 48000, 9), 512, 128 / 48000, null])
      deck.release(clock, 'cancel')
      deck.destroy()
      globalThis.URL.createObjectURL = makeUrl
    }
    {
      //? review of 2.0.0-player.40's fixes: a Safari - its context saying 128 frames, as every WebKit does - starts in
      //? blocks of 1024, Debug saying so and the design figure 164.2 ms
      const original = Object.getOwnPropertyDescriptor(globalThis, 'navigator')
      Object.defineProperty(globalThis, 'navigator', { value: { vendor: 'Apple Computer, Inc.' }, configurable: true, writable: true })
      baseLatency = 128 / 48000
      const host = fakeHost()
      const deck = new Deck(host)
      deck.setShowing(true)
      deck.songChanged(host.song().id)
      wakeDeckAudio()
      await settle()
      const script = scripts.at(-1)
      playBlocksQuietly(script, 1)
      for (let i = 0; i < 4; i++) await settle()
      const latency = deckReport().latency
      check('a Safari (Apple\'s engine, its context saying 128 frames): the main-thread voice in blocks of 1024 - Debug says so, 164.2 ms by design',
        [script.args, latency?.block, round((latency?.design ?? NaN) * 1000, 1)], [[1024, 0, 2], 1024, 164.2])
      deck.destroy()
      if (original) Object.defineProperty(globalThis, 'navigator', original)
      else delete globalThis.navigator
    }
    {
      //? a block of 512 written after it began to play: while the voice is silent, nothing heard of it; while it
      //? sounds, a stretch heard twice - the page can't keep up with blocks that short, and the voice changes to
      //? blocks of 1024 as it next falls silent. In a module of its own: the change is for the page
      decodeTone = true
      const own = path.join(OUT, 'player/deck.js')
      delete require.cache[require.resolve(own)]
      const page = require(own)
      delete require.cache[require.resolve(own)]
      require.cache[require.resolve(own)] = { id: own, filename: own, loaded: true, exports: deckModule }
      baseLatency = 128 / 48000
      const host = fakeHost()
      const deck = new page.Deck(host)
      deck.setShowing(true)
      deck.songChanged(host.song().id)
      page.wakeDeckAudio()
      await settle()
      const small = scripts.at(-1)
      const block = 512 / 48000
      let t = small.context.currentTime + 2 * block
      const on = (count, late = false) => {
        for (let i = 0; i < count; i++) {
          small.context.currentTime = late ? t + 0.004 : t - 2 * block
          fill(small, t)
          t += block
        }
      }
      on(4)
      for (let i = 0; i < 4; i++) await settle()
      on(1, true)
      on(6)
      const silentLate = scripts.at(-1) === small
      //? a playing record taken and let go: the sound follows the run back to speed, then the handover - and
      //? the song played meanwhile fades it out, the voice still following what is left of its path, silent
      deck.pressed(clock)
      deck.takeOver()
      //? the player says it paused, as it does when the hand takes the record
      deck.playingChanged(false)
      for (let ms = 10; ms <= 100; ms += 10) deck.hand(clock + ms, (ms / 1000) * 2 * Math.PI, 60 + (ms / 1000) * SECONDS_PER_TURN)
      clock += 100
      on(3)
      on(1, true)
      on(10)
      deck.release(clock, 'up')
      on(4)
      const keptWhileSounding = scripts.at(-1) === small
      host.isPlaying = true
      deck.playingChanged(true)
      for (let i = 0; i < 20 && scripts.at(-1) === small; i++) on(1)
      const big = scripts.at(-1)
      //? review of 2.0.0-player.40: the new node's clock is its own, counted afresh from its first stamp - which real
      //? Chromium gives one block of 1024 past where the old count had its next block of 512 (21.3 ms on: a step
      //? away, which the old count, kept, would have eased toward for 20-odd seconds, rendering each block that
      //? much early - the sound that much later than the design). Each block rendered at its own stamp
      const renderedAt = []
      const ownRender = voice.renderVoice
      voice.renderVoice = (state, outputs, frames, rate, now) => { renderedAt.push(now); return ownRender(state, outputs, frames, rate, now) }
      let tb = t + 1024 / 48000
      const stampsBig = []
      for (let i = 0; i < 6; i++) { big.context.currentTime = tb - 2 * 1024 / 48000; fill(big, tb); stampsBig.push(tb); tb += 1024 / 48000 }
      voice.renderVoice = ownRender
      check('...the new node of 1024 counting its own clock from its first stamp (one block of 1024 past the old count\'s next, as Chromium gives it): every block rendered at its own playbackTime, to SCRIPT_STAMP_TOLERANCE_S',
        renderedAt.map((at, i) => Math.abs(at - stampsBig[i]) <= deckModule.SCRIPT_STAMP_TOLERANCE_S), stampsBig.map(() => true))
      //? and from there what it is told is heard two blocks of 1024 on: a take now, its time as the voice has it
      const toldBig = []
      const ownCommand = voice.voiceCommand
      voice.voiceCommand = (state, said, at, rate) => { toldBig.push(said); return ownCommand(state, said, at, rate) }
      const takeAt = clock
      deck.pressed(takeAt)
      deck.takeOver()
      for (let i = 0; i < 2; i++) { big.context.currentTime = tb - 2 * 1024 / 48000; fill(big, tb); tb += 1024 / 48000 }
      voice.voiceCommand = ownCommand
      const lagAfter = round(((toldBig.find((said) => said.type === 'take')?.time ?? NaN) - (takeAt / 1000 + page.deckClockMapping().offset)) * 1000, 3)
      deck.release(clock, 'cancel')
      check('...and after the change, what it is told is heard two blocks of 1024 on: a take 42.7 ms after its own time', lagAfter, round((2 * 1024 / 48000) * 1000, 3))
      check('a block of 512 written after it began to play: where the voice was silent (nothing played again that anyone hears) nothing changed; where it sounded - a hand, then a let-go\'s run back to speed - the voice kept its blocks until the song played and faded it out (the voice still following its path, silent), then changed to 1024 - Debug told',
        [silentLate, keptWhileSounding, big !== small, big.args, small.disconnected, page.deckReport().latency?.block], [true, true, true, [1024, 0, 2], true, 1024])
      deck.destroy()
      decodeTone = false
    }
    {
      //? blocks of 512 asked for two at a time, stamped alike - the hardware renders 1024 frames at once though
      //? its context said 128 - the voice changes to blocks of 1024 at its next silent moment, never while it
      //? sounds, and keeps them on this page
      baseLatency = 128 / 48000
      const host = fakeHost()
      const deck = new Deck(host)
      deck.setShowing(true)
      deck.songChanged(host.song().id)
      wakeDeckAudio()
      await settle()
      const small = scripts.at(-1)
      const block = 512 / 48000
      let t = small.context.currentTime + 2 * block
      //? in pairs: the second of each stamped as the first
      const pairs = (script, count) => {
        for (let i = 0; i < count; i++) {
          fill(script, t)
          fill(script, t)
          t += 2 * block
        }
      }
      pairs(small, 2)
      for (let i = 0; i < 4; i++) await settle()
      deck.pressed(clock)
      deck.takeOver()
      pairs(small, 30)
      const sounding = scripts.at(-1) === small
      deck.release(clock, 'cancel')
      pairs(small, 6)
      const big = scripts.at(-1)
      check(`blocks of 512 asked for in pairs, stamped alike (${deckModule.SCRIPT_SHARED_OF} of ${deckModule.SCRIPT_SHARED_WINDOW} at least): the voice kept them while it sounded, and changed to blocks of 1024 as it fell silent - the new node to the speakers, the old let go of - and Debug told`,
        [sounding, big !== small, big.args, big.connected, small.disconnected, small.onaudioprocess, deckReport().latency?.block], [true, true, [1024, 0, 2], true, true, null, 1024])
      //? its state carried over: the window still in it, so the record sounds without asking again
      const asked0 = asked.length
      t = big.context.currentTime + 2 * 1024 / 48000
      for (let i = 0; i < 3; i++) { fill(big, t); t += 1024 / 48000 }
      check('...the voice\'s state carried over - the window still in it, nothing asked again - and a press the deck\'s', [asked.length - asked0, deck.live()], [0, true])
      //? review of 2.0.0-player.40's fixes: what taps the voice follows the new node - a recording started after the
      //? change hangs off it, not the old one (disconnected, its onaudioprocess gone: a file of silence)
      const startedAfter = deckModule.recordDeckSound(1)
      const tapAfter = scripts.at(-1)
      check('...a recording started after the change taps the new node of 1024, not the old one let go of',
        [startedAfter, tapAfter !== big && tapAfter !== small, big.connections.includes(tapAfter), small.connections.includes(tapAfter)], [null, true, true, false])
      deckModule.stopDeckRecording()
      deck.destroy()
      //? and the next context on this page starts there, whatever it says of its hardware
      const again = new Deck(fakeHost())
      again.setShowing(true)
      wakeDeckAudio()
      await settle()
      check('...and the next turntable on this page starts in blocks of 1024, though its context says 128 frames', scripts.at(-1).args, [1024, 0, 2])
      again.destroy()
    }
    //? a page of its own (the change to 1024 is the page's): a deck in blocks of 512 on a context saying 128 frames,
    //? and `on`, the browser asking for its blocks one at a time - on time, or written after it began to play
    const pageOf512 = async () => {
      const own = path.join(OUT, 'player/deck.js')
      delete require.cache[require.resolve(own)]
      const page = require(own)
      delete require.cache[require.resolve(own)]
      require.cache[require.resolve(own)] = { id: own, filename: own, loaded: true, exports: deckModule }
      baseLatency = 128 / 48000
      const host = fakeHost()
      const deck = new page.Deck(host)
      deck.setShowing(true)
      deck.songChanged(host.song().id)
      page.wakeDeckAudio()
      await settle()
      const small = scripts.at(-1)
      const block = 512 / 48000
      let t = small.context.currentTime + 2 * block
      const on = (count, late = false) => {
        for (let i = 0; i < count; i++) {
          small.context.currentTime = late ? t + 0.004 : t - 2 * block
          fill(small, t)
          t += block
        }
      }
      on(4)
      for (let i = 0; i < 4; i++) await settle()
      return { page, host, deck, small, on }
    }
    {
      //? review of 2.0.0-player.40: the late-where-heard rule looks at the two blocks before a late one too - the
      //? one played again in its place. A silent block written late right after two loud ones (the tail of a stop,
      //? say) changes the voice to 1024 - here at once, the voice idle; one after two silent blocks doesn't
      //? and (review of 2.0.0-player.40's fixes) the block two before ALONE loud - loud, silent, then the late one:
      //? that is the block played again in its place, so heard too; the case above, the block just before loud as
      //? well, couldn't tell the two before from the one before
      const results = []
      for (const [before, count] of [[0.5, 2], [0, 2], [0.5, 1]]) {
        const { deck, small, on } = await pageOf512()
        let loud = 0
        const ownRender = voice.renderVoice
        voice.renderVoice = (state, outputs, frames, rate, now) => {
          const done = ownRender(state, outputs, frames, rate, now)
          if (loud > 0) {
            loud--
            for (const data of outputs) data.fill(before)
          }
          return done
        }
        loud = count
        on(2)
        on(1, true)
        voice.renderVoice = ownRender
        results.push([before, count, scripts.at(-1) !== small, scripts.at(-1).args])
        deck.destroy()
      }
      check('a silent block of 512 written after it began to play, right after two blocks at 0.5 (-6 dBFS): heard - the block two before it is played again in its place - so the voice changes to 1024; after two silent blocks, nothing heard and nothing changed; after one at 0.5 then a silent one (the block two before alone loud): heard, changed',
        results, [[0.5, 2, true, [1024, 0, 2]], [0, 2, false, [512, 0, 2]], [0.5, 1, true, [1024, 0, 2]]])
    }
    {
      //? review of 2.0.0-player.40: no change of node while a recording is under way - its tap is on this node and
      //? its file says this block. Recording in blocks of 512: a block late while the hand's sound is heard, the
      //? let-go (a cancel) and silence after - the node kept; the recording done, it changes at the next block
      decodeTone = true
      const makeUrl = globalThis.URL.createObjectURL
      globalThis.URL.createObjectURL = () => 'blob:deck-recording'
      const { page, deck, small, on } = await pageOf512()
      const started = page.recordDeckSound(1)
      const tap = scripts.at(-1)
      deck.pressed(clock)
      deck.takeOver()
      for (let ms = 10; ms <= 100; ms += 10) deck.hand(clock + ms, (ms / 1000) * 2 * Math.PI, 60 + (ms / 1000) * SECONDS_PER_TURN)
      clock += 100
      on(3)
      on(1, true)
      on(3)
      deck.release(clock, 'cancel')
      on(12)
      const whileRecording = [scripts.at(-1) === tap, small.disconnected, small.connections.includes(tap), page.deckReport().latency?.block]
      advance(1100)
      await settle()
      const recorded = page.deckRecordingData() === null && tap.onaudioprocess === null
      on(2)
      const after = scripts.at(-1)
      check('recording in blocks of 512, a block written late while the hand\'s sound was heard, then silence: the node kept while the recording runs - its tap still on it, its block still 512 - and changed to 1024 at the first block after it is done, the old one let go of',
        [started, whileRecording, recorded, after !== small && after !== tap, after.args, small.disconnected, page.deckReport().latency?.block],
        [null, [true, false, true, 512], true, true, [1024, 0, 2], true, 1024])
      deck.destroy()
      globalThis.URL.createObjectURL = makeUrl
      decodeTone = false
    }
    baseLatency = undefined
    noWorklet = false
    delete globalThis.isSecureContext
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
