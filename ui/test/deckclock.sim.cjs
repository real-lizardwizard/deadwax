/**
 * The turntable's one time base (2.0.0-player.24): lib/deckClock.ts, fed the readings a browser gives
 * and held to the truth they come from.
 *
 * What it pins:
 *
 *  - THE MAPPING: `context.currentTime` moves in steps of the audio's own render and stands still
 *    between them - 5.8 ms in desktop Brave (256 frames at 44.1 kHz), 21.3 ms on an iPhone (1024 at 48
 *    kHz) - and reaches the page a moment late. Read at frame times and at pointer events, with random
 *    delays, the mapping is smooth - the offset in use moves well under a millisecond across a gesture,
 *    and by a hundredth of one between two readings - and never ahead of the truth, and within a step of
 *    it from the first reading (within a millisecond once a second of readings is in).
 *  - HELD THROUGH A GESTURE, settled between: held, the offset moves at most CLOCK_SLEW a second towards
 *    the envelope from the gesture's very first reading - on a mapping just started, young or its clock
 *    not yet moving, and on one whose kept readings went stale, alike (second review of 2.0.0-player.24:
 *    those moved it straight to the envelope, jumping a gesture's stamps by up to a step); an error it
 *    began with is held, behind by a step at most. Let go, it takes the envelope, settled
 *    (`clockSettled`) once CLOCK_YOUNG readings are in. A context whose clock stood still (suspended,
 *    resumed) starts again; a slowly drifting audio clock is followed - read ten times a second (the
 *    deck's timer) for five minutes, never started again - and, after a five-minute rest nothing read,
 *    readings kept through it that a fresh one shows stale are let go of (no jump in the gesture, never a
 *    millisecond ahead once let go, never a restart). A clock that stands still a while after the mapping
 *    starts: nothing it read meanwhile kept once it runs, and a gesture held meanwhile keeps its offset
 *    rather than stamping every sample with the one time the clock stands at.
 *  - ITS STEP: the step every move of currentTime between two readings is a whole number of - what the
 *    audio renders at a time, even read only once a frame; a clock that runs smoothly, its smallest move.
 *  - EVENT TIMES: a timeStamp on the page's clock is kept; one on another (the epoch, as some WebKit has
 *    given it), from the future, stale or not a number is taken as now.
 *  - A MOVE'S SAMPLES: getCoalescedEvents() in order, this pointer's only, the event itself when the
 *    list doesn't end with it, nothing out of order or twice, and the event alone where the browser has
 *    no such list - or refuses it.
 *
 * Run it with:  node ui/test/deckclock.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-deckclock-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/deckClock.ts',
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
const round = (value, places = 4) => Math.round(value * 10 ** places) / 10 ** places

const lib = require(path.join(OUT, 'lib/deckClock.js'))
const { newDeckClock, clockReading, clockSettled, contextTimeAt, resetDeckClock, eventTime, pointerSamples } = lib

let seed = 11
const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648)

/**
 * An audio context's clock as the page reads it: the truth runs on from `start` (context seconds at
 * page time `from`, ms) at `rate` (1, or a drifting crystal's), the render moves it `step` seconds at a
 * time, and the page sees each step up to `late` ms after it happens.
 */
function audioClock({ step, from = 1000, start = 3.217, rate = 1, late = 2 }) {
  const truth = (page) => start + ((page - from) / 1000) * rate
  //? when each step reaches the page, fixed per step so a reading is repeatable
  const seen = new Map()
  const currentTime = (page) => {
    let k = Math.floor(truth(page) / step)
    for (;;) {
      if (!seen.has(k)) seen.set(k, random() * late)
      //? step k happened at the page time the truth reached k * step; seen `late` after that
      const happened = from + ((k * step - start) / rate) * 1000
      if (page >= happened + seen.get(k)) return k * step
      k -= 1
    }
  }
  return { truth, currentTime }
}

/**
 * Readings as the deck takes them - once a frame (16.7 ms, a little uneven) and at each pointer event
 * (60 a second, landing anywhere between frames) - for `ms`, with `held` saying when a gesture is on.
 * What the mapping gives at each, against the truth.
 */
function run(audio, { from = 1000, ms = 3000, held = () => false } = {}) {
  const clock = newDeckClock()
  const times = []
  for (let t = from; t < from + ms; t += 1000 / 60 + (random() - 0.5) * 2) times.push(t)
  for (let t = from + 5; t < from + ms; t += 1000 / 60) times.push(t + random() * 12)
  times.sort((a, b) => a - b)
  const out = []
  for (const at of times) {
    clockReading(clock, at, audio.currentTime(at), held(at))
    out.push({ at, offset: clock.offset, mapped: contextTimeAt(clock, at), truth: audio.truth(at) })
  }
  return { clock, out }
}

/** Over the readings from `after` ms on: how far the offset in use moved between two of them at most, how
 *  far it moved in all, and how far the mapping was from the truth, both ways (ms). */
function judge(out, after) {
  const kept = out.filter((reading) => reading.at >= after)
  let jump = 0
  for (let i = 1; i < kept.length; i++) jump = Math.max(jump, Math.abs(kept[i].offset - kept[i - 1].offset))
  const offsets = kept.map((reading) => reading.offset)
  const errors = kept.map((reading) => (reading.mapped - reading.truth) * 1000)
  return {
    jumpMs: jump * 1000,
    driftMs: (Math.max(...offsets) - Math.min(...offsets)) * 1000,
    aheadMs: Math.max(...errors),
    behindMs: -Math.min(...errors),
  }
}

console.log('\nthe mapping: smooth over currentTime\'s steps, never ahead of the truth, within a step of it')
{
  for (const [name, step] of [['desktop Brave, 256 frames at 44.1 kHz (5.8 ms)', 256 / 44100], ['an iPhone, 1024 frames at 48 kHz (21.3 ms)', 1024 / 48000]]) {
    const audio = audioClock({ step })
    //? a gesture from 0.5 s to 2.5 s, the rest between gestures
    const { out } = run(audio, { held: (at) => at > 1500 && at < 3500 })
    const first = (out[0].mapped - out[0].truth) * 1000
    const settled = judge(out, 2000)
    const gesture = judge(out.filter((reading) => reading.at > 1500 && reading.at < 3500), 1500)
    console.log(`    (${name}: first reading ${round(first, 2)} ms; settled ${JSON.stringify(Object.fromEntries(Object.entries(settled).map(([k, v]) => [k, round(v, 3)])))})`)
    check(`${name}: from the first reading, behind the truth by no more than a step and the page's lateness, never ahead`,
      [first <= 1e-9, -first <= step * 1000 + 2], [true, true])
    check(`...once a second of readings is in: within a millisecond of it, never ahead`, [settled.aheadMs <= 1e-6, settled.behindMs <= 1], [true, true])
    check(`...through a two-second gesture: the offset in use moves a hundredth of a millisecond between two readings at most, and well under one in all`,
      [gesture.jumpMs <= 0.01, gesture.driftMs <= 0.5], [true, true])
  }
}

console.log('\nwhat a raw reading would have been: the warble the old stamps had')
{
  const audio = audioClock({ step: 1024 / 48000 })
  const errors = []
  for (let at = 1000; at < 3000; at += 1000 / 60) errors.push((audio.currentTime(at) - audio.truth(at)) * 1000)
  const spread = Math.max(...errors) - Math.min(...errors)
  check('currentTime read per message (as the deck stamped every drive until 2.0.0-player.24): a stamp off by up to a whole 21 ms step, frame to frame',
    spread > 15, true)
  console.log(`    (raw readings off the truth by ${round(Math.min(...errors), 1)} to ${round(Math.max(...errors), 1)} ms)`)
}

console.log('\nheld through a gesture, settled between - and kept through a long rest')
{
  //? a gesture begun on a mapping just started - the first grab of a still record after its context was
  //? made or resumed, nothing having read the clock since: the take's reading (not held: nothing is followed
  //? yet), then the gesture's, at frames and pointer events. Second review of 2.0.0-player.24: a young
  //? mapping followed the envelope even held, and its first readings - the first provisional, until the
  //? clock moved, the envelope then climbing a step - jumped the stamps 7-19 ms on an iPhone's step
  const rows = []
  for (const [name, step] of [['5.8 ms', 256 / 44100], ['21.3 ms', 1024 / 48000]]) {
    let worstJump = 0, worstAhead = -Infinity, worstBehind = -Infinity, worstMoved = 0, settledEarly = 0, restarts = 0
    for (let trial = 0; trial < 200; trial++) {
      const audio = audioClock({ step, start: 3 + random() })
      const clock = newDeckClock()
      const take = 1000 + random() * 30
      clockReading(clock, take, audio.currentTime(take), false)
      const times = []
      for (let t = take + random() * 16; t < take + 1500; t += 1000 / 60 + (random() - 0.5) * 2) times.push(t)
      for (let t = take + 3; t < take + 1500; t += 1000 / 60) times.push(t + random() * 12)
      times.sort((a, b) => a - b)
      let last = clock.offset, first = clock.offset
      for (const at of times) {
        const before = clock.count
        clockReading(clock, at, audio.currentTime(at), true)
        if (clock.count < before && clock.moving && before > 1) restarts++
        if (clockSettled(clock) && clock.count < lib.CLOCK_YOUNG) settledEarly++
        worstJump = Math.max(worstJump, Math.abs(clock.offset - last) * 1000)
        worstMoved = Math.max(worstMoved, Math.abs(clock.offset - first) * 1000 - lib.CLOCK_SLEW * (at - take))
        last = clock.offset
        const error = (contextTimeAt(clock, at) - audio.truth(at)) * 1000
        worstAhead = Math.max(worstAhead, error)
        worstBehind = Math.max(worstBehind, -error)
      }
    }
    rows.push({ step: name, stepMs: round(step * 1000, 1), jumpMs: round(worstJump, 4), beyondSlewMs: round(worstMoved, 4), aheadMs: round(worstAhead, 2), behindMs: round(worstBehind, 2), settledEarly, restarts })
  }
  console.log('    ' + rows.map((row) => JSON.stringify(row)).join('\n    '))
  check('a gesture begun on a mapping just started (its take the first reading), held from there - 200 trials on each step, every reading counted from the first: never a jump - a hundredth of a millisecond between two readings at most, and no further in all than CLOCK_SLEW allows - never ahead of the truth, behind it by no more than a step and the page\'s lateness (an error held for the gesture, latency only), never restarted, and not settled before CLOCK_YOUNG readings',
    rows.map((row) => [row.jumpMs <= 0.01, row.beyondSlewMs <= 1e-6, row.aheadMs <= 1e-6, row.behindMs <= row.stepMs + 2, row.restarts, row.settledEarly]), rows.map(() => [true, true, true, true, 0, 0]))
}
{
  //? not held, a young mapping is the envelope itself, and settles in its first readings
  const audio = audioClock({ step: 1024 / 48000 })
  const clock = newDeckClock()
  const young = []
  const settled = []
  let at = 1000
  for (; at < 1400; at += 7.3) {
    clockReading(clock, at, audio.currentTime(at), false)
    young.push(clock.offset === clock.readings[0].offset)
    settled.push(clockSettled(clock) === (clock.moving && clock.count >= lib.CLOCK_YOUNG))
  }
  check('a mapping not held: the envelope itself at every reading - and settled (clockSettled) once its clock has moved and CLOCK_YOUNG (12) readings have come since',
    [lib.CLOCK_YOUNG, young.every(Boolean), settled.every(Boolean), clockSettled(clock)], [12, true, true, true])
  //? from here held: start it a step low, as a gesture begun on a cold mapping could find it
  clock.offset -= 0.02
  let jump = 0, last = clock.offset
  const settledFrom = clock.offset
  for (const end = at + 400; at < end; at += 7.3) {
    clockReading(clock, at, audio.currentTime(at), true)
    jump = Math.max(jump, Math.abs(clock.offset - last))
    last = clock.offset
  }
  check('...then, held, it climbs towards the envelope by at most CLOCK_SLEW (half a millisecond a second) - a few thousandths of a ms a reading',
    [lib.CLOCK_SLEW, round(jump * 1000, 4) <= round(lib.CLOCK_SLEW * 7.3, 4) + 1e-9, clock.offset - settledFrom <= lib.CLOCK_SLEW * (0.4 + 0.0073) + 1e-12, clock.offset > settledFrom], [0.0005, true, true, true])
  const envelope = clock.readings[0].offset
  clockReading(clock, at, audio.currentTime(at), false)
  check('...let go: it takes the envelope at once', round(clock.offset, 9), round(Math.max(envelope, audio.currentTime(at) - at / 1000), 9))
}
{
  //? two seconds of readings, then a record left still for five minutes - no frames, no readings - and
  //? pressed: the first reading after lands anywhere in a step
  const audio = audioClock({ step: 1024 / 48000 })
  const { clock } = run(audio, { ms: 2000 })
  const settled = clock.offset
  const back = 1000 + 2000 + 300_000
  let worst = 0
  for (let k = 0; k < 20; k++) {
    const probe = { ...clock, readings: clock.readings.map((reading) => ({ ...reading })) }
    const at = back + random() * 30
    clockReading(probe, at, audio.currentTime(at), false)
    worst = Math.max(worst, Math.abs(probe.offset - settled))
  }
  check('a record left still five minutes, then pressed: the mapping is as settled as it was (the last CLOCK_KEEP readings kept, however old) - not one fresh reading, up to a step out',
    [lib.CLOCK_KEEP, round(worst * 1000, 3) <= 0.5], [90, true])
}
{
  //? held, then two seconds with no reading (a page busy through a gesture), then one that wants the
  //? offset a step higher: no more than a tenth of a second's slew allowed for the gap
  const clock = newDeckClock()
  for (let at = 1000; at < 1300; at += 10) clockReading(clock, at, 5 + (at - 1000) / 1000 - 0.02, true)
  const before = clock.offset
  clockReading(clock, 3300, 5 + 2.3, true)
  check('held through two seconds with no readings: the next moves it no more than a tenth of a second\'s worth of CLOCK_SLEW (0.05 ms), not two seconds\' (1 ms)',
    round((clock.offset - before) * 1000, 4) <= round(lib.CLOCK_SLEW * 100, 4) + 1e-9, true)
}
{
  //? the context suspended for two seconds - its clock stood still - and resumed
  const clock = newDeckClock()
  for (let at = 1000; at < 2000; at += 16.7) clockReading(clock, at, 5 + (at - 1000) / 1000, true)
  const before = clock.offset
  clockReading(clock, 4000, 6.001, true)
  check('a reading far below the envelope (the clock stood still while suspended): the mapping starts again from it, held or not',
    [round(before, 6), round(clock.offset, 6), clock.count], [round(5 - 1, 6), round(6.001 - 4, 6), 1])
  resetDeckClock(clock)
  check('reset: nothing mapped until the next reading', [clock.offset, contextTimeAt(clock, 1234)], [null, null])
}
{
  //? a context just made (or resumed) whose clock stands still a while before it renders: read meanwhile,
  //? at frames and pointer events, each reading above the truth it then runs on from (review of
  //? 2.0.0-player.24: they topped the envelope for 1.5 s - up to 20 ms ahead - and a reading late in a step
  //? could then fall past CLOCK_RESET_S and start it again in the middle of a gesture)
  const rows = []
  for (const [name, step] of [['5.8 ms', 256 / 44100], ['21.3 ms', 1024 / 48000]]) {
    for (const stall of [10, 30, 45, 100]) {
      let worstAhead = -Infinity, worstBehind = -Infinity, worstJump = 0, restarts = 0, envelopeAhead = -Infinity, afterAhead = -Infinity
      for (let trial = 0; trial < 6; trial++) {
        const reset = 1000, runs = reset + stall
        const c0 = Math.round(7.1 / step) * step
        const audio = audioClock({ step, from: runs, start: c0 })
        const currentTime = (page) => (page < runs ? c0 : audio.currentTime(page))
        const clock = newDeckClock()
        const times = []
        for (let t = reset + random() * 16; t < reset + 3000; t += 1000 / 60 + (random() - 0.5) * 2) times.push(t)
        for (let t = reset + 5; t < reset + 3000; t += 1000 / 60) times.push(t + random() * 12)
        times.sort((a, b) => a - b)
        let last = null, free = reset
        for (const at of times) {
          //? a gesture held from 50 ms in to the end - begun before the clock runs, for the longer stalls
          const held = at > reset + 50
          if (!held) free = at
          const before = clock.count, moving = clock.moving
          clockReading(clock, at, currentTime(at), held)
          if (clock.count < before && moving) restarts++
          if (at > runs && clock.moving) envelopeAhead = Math.max(envelopeAhead, (at / 1000 + clock.readings[0].offset - audio.truth(at)) * 1000)
          if (held) {
            //? every reading of the gesture, from its first - the clock standing still or not
            if (at > runs) {
              //? ahead by what was left of the standstill at the last reading before the gesture, at most
              const error = (contextTimeAt(clock, at) - audio.truth(at)) * 1000
              worstAhead = Math.max(worstAhead, error - Math.max(0, runs - free))
              worstBehind = Math.max(worstBehind, -error)
            }
            if (last !== null) worstJump = Math.max(worstJump, Math.abs(clock.offset - last) * 1000)
            last = clock.offset
          }
        }
        //? let go: the next reading, not held
        const after = reset + 3010
        clockReading(clock, after, currentTime(after), false)
        afterAhead = Math.max(afterAhead, (contextTimeAt(clock, after) - audio.truth(after)) * 1000)
      }
      rows.push({ step: name, stepMs: round(step * 1000, 1), stall, envelopeAheadMs: round(envelopeAhead, 2), afterAheadMs: round(afterAhead, 2), beyondStandstillMs: round(worstAhead, 2), behindMs: round(worstBehind, 2), jumpMs: round(worstJump, 4), restarts })
    }
  }
  console.log('    ' + rows.map((row) => JSON.stringify(row)).join('\n    '))
  check('a clock that stands still 10, 30, 45 or 100 ms after the mapping starts (a context just made or resumed), read throughout, a gesture held from 50 ms in: once it runs, the envelope never ahead of the truth - nothing it read standing still kept - and let go after the gesture, the mapping not either; and through the gesture, from its first reading - standing still or not - never a jump (a hundredth of a millisecond between readings at most), never a restart, behind the truth by no more than a step, and ahead of it by no more than what was left of the standstill when the gesture began (latency: a gesture held before the clock moved keeps the offset it had - review: following the readings while it stood still stamped every sample with the one time, and its first move jumped them all)',
    rows.map((row) => [row.envelopeAheadMs <= 1e-6, row.afterAheadMs <= 1e-6, row.jumpMs <= 0.01, row.restarts, row.behindMs <= row.stepMs + 2, row.beyondStandstillMs <= 1]),
    rows.map(() => [true, true, true, 0, true, true]))
  //? standing still: the latest reading alone, so a stamp is the clock's value as it stands
  const still = newDeckClock()
  clockReading(still, 1000, 7, false)
  clockReading(still, 1016, 7, false)
  check('...meanwhile the offset is the latest reading\'s - a stamp then is what the clock reads - and the envelope waits for it to move',
    [round(contextTimeAt(still, 1016), 9), still.moving, still.count], [7, false, 1])
  //? ...unless a gesture holds it
  const gripped = newDeckClock()
  clockReading(gripped, 1000, 7, false)
  clockReading(gripped, 1016, 7, true)
  clockReading(gripped, 1033, 7, true)
  check('...held meanwhile (a gesture begun before it moves): the offset as it was - its stamps run on with the page\'s clock, never all the one time the clock stands at (second review of 2.0.0-player.24)',
    [round(contextTimeAt(gripped, 1016), 9), round(contextTimeAt(gripped, 1033), 9), gripped.moving], [7.016, 7.033, false])
}
{
  //? two seconds of readings, a five-minute rest, then a gesture - on an audio clock running slow (as a
  //? Bluetooth output's crystal may, against the page's): kept through the rest, the old readings sit
  //? the drift above the truth (review of 2.0.0-player.24: 15-30 ms ahead at 50-100 ppm - and on an
  //? iPhone's step a reading late in a step fell past CLOCK_RESET_S and restarted it mid-gesture)
  const rows = []
  for (const [name, step] of [['5.8 ms', 256 / 44100], ['21.3 ms', 1024 / 48000]]) {
    for (const ppm of [0, 50, 100]) {
      let worstAhead = -Infinity, worstBehind = -Infinity, worstJump = 0, restarts = 0, afterAhead = -Infinity, afterBehind = -Infinity
      for (let trial = 0; trial < 8; trial++) {
        const audio = audioClock({ step, rate: 1 - ppm * 1e-6 })
        const clock = newDeckClock()
        for (let at = 1000; at < 3000; at += 1000 / 60 + (random() - 0.5) * 2) clockReading(clock, at, audio.currentTime(at), false)
        const back = 3000 + 300_000 + random() * 30
        //? pressed: the take's reading not held, then the gesture's - frames and pointer events
        clockReading(clock, back, audio.currentTime(back), false)
        const times = []
        for (let t = back + 4; t < back + 3000; t += 1000 / 60 + (random() - 0.5) * 2) times.push(t)
        for (let t = back + 9; t < back + 3000; t += 1000 / 120) times.push(t + random() * 3)
        times.sort((a, b) => a - b)
        let last = clock.offset
        for (const at of times) {
          const before = clock.count
          clockReading(clock, at, audio.currentTime(at), true)
          if (clock.count < before) restarts++
          //? every reading of the gesture, its first included
          const error = (contextTimeAt(clock, at) - audio.truth(at)) * 1000
          worstAhead = Math.max(worstAhead, error)
          worstBehind = Math.max(worstBehind, -error)
          worstJump = Math.max(worstJump, Math.abs(clock.offset - last) * 1000)
          last = clock.offset
        }
        //? let go: the next reading, not held - the stale readings let go of meanwhile
        const after = back + 3010
        clockReading(clock, after, audio.currentTime(after), false)
        const error = (contextTimeAt(clock, after) - audio.truth(after)) * 1000
        afterAhead = Math.max(afterAhead, error)
        afterBehind = Math.max(afterBehind, -error)
      }
      rows.push({ step: name, stepMs: round(step * 1000, 1), ppm, driftMs: round(ppm * 1e-6 * 300_000, 1), aheadMs: round(worstAhead, 2), behindMs: round(worstBehind, 2), jumpMs: round(worstJump, 4), restarts, afterAheadMs: round(afterAhead, 2), afterBehindMs: round(afterBehind, 2) })
    }
  }
  console.log('    ' + rows.map((row) => JSON.stringify(row)).join('\n    '))
  check('a record nothing read for five minutes (the deck reads it ten times a second while its turntable shows - this is a page whose timers were held back) on an audio clock 0, 50 or 100 parts in a million slow, then turned: through the gesture, from its first reading, never a jump - a hundredth of a millisecond between readings at most - never restarted, never more than a step behind the truth, and ahead of it by no more than the drift the kept readings carried (latency, held for the gesture: second review - made young again by a stale reading, it jumped 7-24 ms in the gesture); let go, the stale readings gone, never a millisecond ahead nor a step behind',
    rows.map((row) => [row.jumpMs <= 0.01, row.restarts, row.behindMs <= row.stepMs + 2, row.aheadMs <= row.driftMs + 1, row.afterAheadMs <= 1, row.afterBehindMs <= row.stepMs + 2]),
    rows.map(() => [true, 0, true, true, true, true]))
}
{
  //? and what the deck does instead: a reading ten times a second (CLOCK_TICK_MS, the deck's timer on a still
  //? record) for five minutes on a clock 100 ppm slow - followed throughout, never started again
  const rows = []
  for (const [name, step] of [['5.8 ms', 256 / 44100], ['21.3 ms', 1024 / 48000]]) {
    const audio = audioClock({ step, rate: 1 - 1e-4 })
    const clock = newDeckClock()
    let worstAhead = -Infinity, worstBehind = -Infinity, young = 0
    for (let at = 1000; at < 301_000; at += 100 + (random() - 0.5) * 8) {
      clockReading(clock, at, audio.currentTime(at), false)
      if (at < 3000) continue
      const error = (contextTimeAt(clock, at) - audio.truth(at)) * 1000
      worstAhead = Math.max(worstAhead, error)
      worstBehind = Math.max(worstBehind, -error)
      if (!clockSettled(clock)) young++
    }
    rows.push({ step: name, aheadMs: round(worstAhead, 2), behindMs: round(worstBehind, 2), young })
  }
  console.log('    ' + rows.map((row) => JSON.stringify(row)).join('\n    '))
  check('read ten times a second for five minutes on an audio clock 100 ppm slow (the deck\'s timer, a still record): followed - never a millisecond ahead of the truth nor more than 2 ms behind it - and never started again, settled throughout',
    rows.map((row) => [row.aheadMs <= 1, row.behindMs <= 2, row.young]), rows.map(() => [true, true, 0]))
}
{
  //? a crystal 100 ppm slow against the page's
  const audio = audioClock({ step: 256 / 44100, rate: 1 - 1e-4 })
  const { out } = run(audio, { ms: 10_000 })
  const late = judge(out, 2000)
  check('an audio clock 100 ppm slow: followed - still within a millisecond of it over ten seconds, never more than a hair ahead',
    [late.behindMs <= 1, late.aheadMs <= 0.2], [true, true])
}

console.log('\nits step: what the audio renders at a time')
{
  for (const [frames, rate] of [[256, 44100], [1024, 48000]]) {
    const audio = audioClock({ step: frames / rate })
    const { clock } = run(audio, { ms: 1000 })
    check(`${frames} frames at ${rate / 1000} kHz: ${round((frames / rate) * 1000, 1)} ms`, round(clock.step * 1000, 3), round((frames / rate) * 1000, 3))
  }
  //? read once a frame and at nothing else - a record turning with no hand on it, on a 60 Hz screen: a 5.8 ms
  //? render moves 11.6 or 17.4 ms between two readings, never 5.8 (review of 2.0.0-player.24: Debug said
  //? 11.6 on a desktop until a hand happened to straddle a step)
  {
    const audio = audioClock({ step: 256 / 44100 })
    const clock = newDeckClock()
    let smallest = Infinity, previous = null
    for (let at = 1000; at < 4000; at += 1000 / 60 + (random() - 0.5) * 2) {
      const read = audio.currentTime(at)
      if (previous !== null && read > previous) smallest = Math.min(smallest, read - previous)
      previous = read
      clockReading(clock, at, read, false)
    }
    check('read only once a frame at 60 Hz, a 5.8 ms render whose smallest move between two readings is 11.6 ms: its step still 5.8 ms - the step every move is a whole number of',
      [round(smallest * 1000, 2) >= 11, round(clock.step * 1000, 3)], [true, round((256 / 44100) * 1000, 3)])
    const smooth = newDeckClock()
    for (let at = 1000, c = 2; at < 2000; at += 16.7) clockReading(smooth, at, (c += 0.0167 + (random() - 0.5) * 0.0004), false)
    check('...a clock that runs smoothly, no step common to its moves: the smallest move it made', round(smooth.step * 1000, 1) >= 16 && smooth.step <= 0.0172, true)
  }
  const fresh = newDeckClock()
  clockReading(fresh, 1000, 2, false)
  check('...0 until it has been seen to move', fresh.step, 0)
}

console.log('\nevent times: the event\'s own, on the page\'s clock')
{
  check('a timeStamp a few ms before now: kept', eventTime(9_990.5, 10_000), 9_990.5)
  check('on another clock - the epoch, as some WebKit has given it: now', eventTime(1_727_000_000_000, 10_000), 10_000)
  check('from the future, stale past a second, not a number, absent: now',
    [eventTime(10_050, 10_000), eventTime(8_000, 10_000), eventTime(NaN, 10_000), eventTime(undefined, 10_000)], [10_000, 10_000, 10_000, 10_000])
}

console.log('\na move\'s samples: each of getCoalescedEvents() with its own time, in order')
{
  const pointer = (timeStamp, x, y, extra = {}) => ({ pointerId: 1, timeStamp, clientX: x, clientY: y, ...extra })
  const a = pointer(980, 10, 10), b = pointer(988, 12, 11), c = pointer(996, 14, 12)
  const event = pointer(996, 14, 12, { getCoalescedEvents: () => [a, b, c] })
  check('the coalesced samples in order, the event itself last among them (iOS and Chrome keep it there)',
    pointerSamples(event, 1000), [{ time: 980, x: 10, y: 10 }, { time: 988, x: 12, y: 11 }, { time: 996, x: 14, y: 12 }])
  const other = pointer(984, 99, 99, { pointerId: 2 })
  const notLast = pointer(1000, 16, 13, { getCoalescedEvents: () => [a, other, b] })
  check('...another pointer\'s left out, and the event added when the list doesn\'t end with it',
    pointerSamples(notLast, 1001).map((sample) => sample.time), [980, 988, 1000])
  const twice = pointer(996, 14, 12, { getCoalescedEvents: () => [a, a, pointer(970, 1, 1), b, c] })
  check('...nothing twice, nothing earlier than the sample before it', pointerSamples(twice, 1000).map((sample) => sample.time), [980, 988, 996])
  check('a browser with no list (older WebKit): the event alone', pointerSamples(pointer(990, 5, 6), 1000), [{ time: 990, x: 5, y: 6 }])
  const refusing = pointer(990, 5, 6, { getCoalescedEvents: () => { throw new Error('not allowed') } })
  check('...or one that refuses it: the event alone', pointerSamples(refusing, 1000), [{ time: 990, x: 5, y: 6 }])
  const epoch = pointer(1_727_000_000_000, 5, 6, { getCoalescedEvents: () => [pointer(1_727_000_000_000, 5, 6)] })
  check('...each time on the page\'s clock: one on another is now', pointerSamples(epoch, 1000), [{ time: 1000, x: 5, y: 6 }])
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
