/**
 * The turntable's one time base (2.0.0-player.24): the page's clock - performance.now() and an event's
 * timeStamp, in ms - mapped onto the clock the record's voice renders by, its audio context's, in
 * seconds. Pure, so ui/test/deckclock.sim.cjs feeds it the readings a browser gives and holds what comes
 * out to the truth.
 *
 * James: "I should be able to rotate the turntable at the same speed as it plays at, and it should play
 * the song. but when i do, it doesn't sound like anything". Measured, the hand's place in the song was
 * right and its timing wasn't: each message to the voice was stamped with a fresh `context.currentTime`,
 * which doesn't run smoothly - it moves in steps of the audio's own render (5.8 ms in desktop Brave, 21 ms
 * on an iPhone, whose hardware takes 1024 frames at a time) and stands still between them. So every stamp
 * was off by anything up to a step, the voice's target jumped by the hand's speed times that each frame,
 * and the record's pitch swung with it.
 *
 * THE MAPPING: the context's time at page time `at` is `at / 1000 + offset`, with ONE offset - never a
 * reading per message. currentTime steps UP to the truth and lags it between steps, so of the readings
 * `currentTime - performance.now() / 1000` the highest is the closest to the truth: the offset is their
 * upper envelope over the last CLOCK_WINDOW_MS (a sliding maximum - amortised one step a reading). Its
 * steps can't move it: a reading taken just before a step is lower, and is outdone by the next taken
 * just after one. While readings keep coming it is never ahead of the truth, and within a step of it from
 * the first reading.
 *
 * HELD THROUGH A GESTURE: while the voice is steered by it (a hand on the record, a coast, a wind-down,
 * the handover - `held`), the offset in use moves towards the envelope by at most CLOCK_SLEW a second,
 * so nothing the voice is following jumps - a hundredth of a millisecond between two frames, at most -
 * WHATEVER the readings say meanwhile: a mapping still young, the readings kept through a rest let go of
 * as stale, a clock not yet moving (below). Any of those moved the offset in use straight to the
 * envelope until the second review of 2.0.0-player.24, and a gesture begun on a mapping just started -
 * the first grab of a paused record after its context was made or resumed, nothing having read the clock
 * meanwhile - had its stamps jump by up to a step (12-19 ms on an iPhone's) in its first readings, and
 * its pitch fell to a tenth or leapt to three times the hand's. Held, an error the mapping had when the
 * gesture began is kept for the gesture - a constant, so only latency - and put right as it ends. Only
 * a clock that stood still (CLOCK_RESET_S, below) moves it while held: the voice stood still with it.
 * Between gestures it takes the envelope as it is.
 *
 * SETTLED: a mapping is young until CLOCK_YOUNG readings have come since its envelope started
 * (`clockSettled`) - up to a step out, it settles in those - and the deck reads it every CLOCK_SETTLE_MS
 * until it isn't, and every CLOCK_TICK_MS after, while its turntable shows and the context runs, whatever
 * the record does (player/deck.ts), so a press finds it settled and its readings never go stale. The
 * envelope keeps the last CLOCK_KEEP readings however old, so a mapping nothing read for a while (a page
 * whose timers were held back) is still as settled as it was - unless a fresh reading says they have gone
 * stale: more than a step (and CLOCK_LATE_S) below them, which no step's lag explains, is the audio's
 * clock having drifted from the page's while nothing read it (a crystal 50 parts in a million slow is 15
 * ms in five minutes). They go, and the envelope settles on the fresh readings: not held, the mapping is
 * never more than a step ahead of the truth however long the rest; held, the gesture keeps the offset it
 * had - ahead by the drift at most, latency - and takes the fresh envelope as it ends (review of
 * 2.0.0-player.24: kept, they had it up to 50 ms ahead - and a reading late in a step then fell past
 * CLOCK_RESET_S and started it again in the middle of a gesture; the mapping made young again by them, as
 * the first review had it, was followed even held, until the second). A reading far below the envelope
 * (CLOCK_RESET_S) is the context's clock having stood still - suspended while the page was hidden, and
 * resumed - and starts again from it, held or not: the old offset is simply wrong then.
 *
 * NOTHING IS TRUSTED UNTIL THE CLOCK MOVES: a context just made or resumed may stand still a while
 * before it renders, and readings taken meanwhile - each higher than the truth will be once it runs - would
 * sit at the top of the envelope for a second and a half (review of 2.0.0-player.24: up to 20 ms ahead).
 * Until currentTime has moved since the mapping started, the offset is the latest reading's alone - a
 * stamp then is the clock's value as it stands, which is what the voice's first block will read - and the
 * envelope starts from the first reading after it moves. Held meanwhile (a gesture begun before the clock
 * moved), the offset stays as it was: following each reading would stamp every sample with the one time
 * the clock stands at, and its first move would then jump them all; ahead of the truth by what remained
 * of the standstill, it is latency, never a lurch.
 *
 * ITS STEP, for Debug: what the audio renders at a time - the largest step every move of currentTime
 * between two readings is a whole number of (`stepOf`, a greatest common divisor to within CLOCK_GRAIN_S).
 * The smallest move alone isn't it: read once a frame (16.7 ms), a 5.8 ms render moves 11.6 or 17.4 ms
 * between readings, never 5.8 (review of 2.0.0-player.24).
 *
 * WHY NOT getOutputTimestamp(): it answers the clock at the SPEAKER - which sample is being heard now -
 * and that runs behind the clock the voice renders by (currentTime, its own `now`) by the output's
 * latency: a few ms on a phone's speaker, a fifth of a second over AirPods. Stamped by it, every hand
 * sample would land that far in the voice's PAST - played past before it arrives, beyond what
 * HAND_DELAY_S keeps in hand - and on AirPods the voice would only ever be guessing. The render clock is
 * the one the voice plays by, so it is the one the page maps onto; how late the speaker is after that is
 * a constant, and only latency.
 *
 * And EVENT TIMES: a pointer sample's time is the event's own timeStamp - and each of
 * getCoalescedEvents()' (the in-between samples of the same motion iOS and Chrome keep), in order - not
 * when the handler happened to run. Some WebKit has given timeStamp on another clock (the epoch), so a
 * stamp more than EVENT_STALE_MS from the page's clock is taken as now (`eventTime`).
 */

/** The upper envelope is taken over the readings of this long, in ms - and, however old, the last
 *  CLOCK_KEEP of them: a record left still takes no readings (the frame loop rests), and the next press
 *  should find the mapping as settled as it was, not start from one reading. */
export const CLOCK_WINDOW_MS = 1500
export const CLOCK_KEEP = 90
/** Until this many readings are in since its envelope started, a mapping is young (`clockSettled`): up
 *  to a step out, it settles in its first few readings - which the deck takes quickly for it. Held, a
 *  young mapping is held like any other: a gesture's stamps never jump (second review of
 *  2.0.0-player.24 - a young mapping, and one made young by stale readings, followed the envelope even
 *  held). */
export const CLOCK_YOUNG = 12
/** How fast the offset in use may move while held, in seconds a second: 0.5 ms a second, so a frame
 *  apart (16.7 ms) two stamps disagree by under a hundredth of a millisecond. */
export const CLOCK_SLEW = 0.0005
/** A reading this far below the envelope, in seconds, is the context's clock having stood still
 *  (suspended, then resumed): the mapping starts again from it. Larger than any step (21 ms on an
 *  iPhone). */
export const CLOCK_RESET_S = 0.05
/** How late, in seconds, the page may see one of currentTime's steps: a reading lags the truth by a step
 *  and this at most, so kept readings more than that above a fresh one have gone stale (a drifting audio
 *  clock, over a rest). */
export const CLOCK_LATE_S = 0.003
/** Two moves of currentTime are taken as whole numbers of one step to within this, in seconds (stepOf);
 *  and a step finer than CLOCK_STEP_MIN_S is no step at all - a clock that runs smoothly, whose smallest
 *  move is then the most that can be said. */
export const CLOCK_GRAIN_S = 0.0001
export const CLOCK_STEP_MIN_S = 0.0005
/** An event's timeStamp further than this from performance.now(), in ms, is on some other clock. */
export const EVENT_STALE_MS = 1000

export interface DeckClock {
  /** the readings in the window that could still be the highest: page ms, offset (offsets falling) and
   *  which reading it was (`count` then) */
  readings: { at: number; offset: number; n: number }[]
  /** the offset in use, seconds - null until the first reading */
  offset: number | null
  /** page ms the offset in use was last moved at */
  movedAt: number
  /** the last context time read, and the step every move between two readings has been a whole number of
   *  - what the audio's render steps by (for Debug, `stepOf`); 0 until it has moved */
  lastContext: number | null
  step: number
  /** readings taken since the envelope last started - how settled it is (CLOCK_YOUNG, clockSettled) */
  count: number
  /** whether currentTime has moved since the mapping started: until it has, the latest reading alone */
  moving: boolean
}

export function newDeckClock(): DeckClock {
  return { readings: [], offset: null, movedAt: 0, lastContext: null, step: 0, count: 0, moving: false }
}

/** Forget everything: a new context, or one whose clock stood still. */
export function resetDeckClock(clock: DeckClock): void {
  clock.readings.length = 0
  clock.offset = null
  clock.movedAt = 0
  clock.lastContext = null
  clock.step = 0
  clock.count = 0
  clock.moving = false
}

/** The largest step two moves of a clock (seconds) are both whole numbers of, to within CLOCK_GRAIN_S - a
 *  greatest common divisor: 11.6 and 17.4 ms have 5.8 ms in common. */
export function stepOf(a: number, b: number): number {
  let x = Math.max(a, b), y = Math.min(a, b)
  for (let i = 0; i < 16 && y > CLOCK_GRAIN_S; i++) {
    let rest = x % y
    if (y - rest < CLOCK_GRAIN_S) rest = 0
    x = y
    y = rest
  }
  return x
}

/**
 * A reading: `contextTime` (context.currentTime) read at page time `at` (performance.now(), ms). `held`
 * when the voice is being steered by the mapping - the offset in use then moves only slowly.
 */
export function clockReading(clock: DeckClock, at: number, contextTime: number, held: boolean): void {
  if (!Number.isFinite(at) || !Number.isFinite(contextTime)) return
  const offset = contextTime - at / 1000
  const top = clock.readings[0]
  //? the context's clock stood still (suspended and resumed) - or went back: start again from here
  if (top && offset < top.offset - CLOCK_RESET_S) resetDeckClock(clock)
  const moved = clock.lastContext === null ? 0 : contextTime - clock.lastContext
  clock.lastContext = contextTime
  if (moved > 1e-6) {
    //? the step every move has been a whole number of - or, a clock that runs smoothly, its smallest move
    const common = clock.step === 0 ? moved : stepOf(clock.step, moved)
    clock.step = common >= CLOCK_STEP_MIN_S ? common : Math.min(clock.step, moved)
    if (!clock.moving) {
      //? its first move since the mapping started: what was read while it stood still was all above the
      //? truth it runs on from now - the envelope starts here (the offset in use, if a gesture holds it,
      //? stays, and slews to it)
      clock.moving = true
      clock.readings.length = 0
      clock.count = 0
    }
  }
  if (!clock.moving) {
    //? standing still since it started (a context just made or resumed, not yet rendering): the latest
    //? reading alone - a stamp now is the clock's value as it stands, what its first block will read -
    //? unless a gesture holds the offset: then it stays
    clock.readings.length = 0
    clock.readings.push({ at, offset, n: 1 })
    clock.count = 1
    if (clock.offset === null || !held) clock.offset = offset
    clock.movedAt = at
    return
  }
  clock.count += 1
  const readings = clock.readings
  //? a sliding maximum: what this reading outdoes can never be the highest again
  while (readings.length && readings[readings.length - 1]!.offset <= offset) readings.pop()
  readings.push({ at, offset, n: clock.count })
  //? the oldest go once outside the window and CLOCK_KEEP readings on - or, kept through a rest, as soon as
  //? a fresh reading is further below them than a step's lag explains: the audio's clock drifted from the
  //? page's meanwhile, and they are stale - the envelope settles on the fresh readings
  const stale = clock.step > 0 ? clock.step + CLOCK_LATE_S : Infinity
  while (readings.length > 1 && readings[0]!.at < at - CLOCK_WINDOW_MS) {
    if (clock.count - readings[0]!.n >= CLOCK_KEEP || readings[0]!.offset - offset > stale) readings.shift()
    else break
  }
  const envelope = readings[0]!.offset
  //? held, never more than CLOCK_SLEW - young, or its kept readings just let go of as stale, alike
  if (clock.offset === null || !held) {
    clock.offset = envelope
  } else {
    //? (a pause in the readings allows no more than a tenth of a second's worth)
    const most = (CLOCK_SLEW * Math.min(100, Math.max(0, at - clock.movedAt))) / 1000
    clock.offset += Math.max(-most, Math.min(most, envelope - clock.offset))
  }
  clock.movedAt = at
}

/** Whether the mapping has settled: CLOCK_YOUNG readings have come since its envelope started - which
 *  waits for its clock to move (until then the count stays at one). */
export function clockSettled(clock: DeckClock): boolean {
  return clock.count >= CLOCK_YOUNG
}

/** The context's time at page time `at` (ms), in seconds - null before the first reading. */
export function contextTimeAt(clock: DeckClock, at: number): number | null {
  return clock.offset === null ? null : at / 1000 + clock.offset
}

/** An event's own time (ms) - its timeStamp - unless that is on some other clock than the page's
 *  (further than EVENT_STALE_MS from `now`, ahead of it, or not a number): then `now`. */
export function eventTime(stamp: number | null | undefined, now: number): number {
  if (typeof stamp !== 'number' || !Number.isFinite(stamp) || stamp > now + 1 || stamp < now - EVENT_STALE_MS) return now
  return stamp
}

/** What a pointer event says of where it was: its time, and where. */
export interface PointerSample {
  time: number
  x: number
  y: number
}

interface PointerLike {
  pointerId: number
  timeStamp: number
  clientX: number
  clientY: number
  getCoalescedEvents?: () => readonly PointerLike[]
}

/**
 * The samples a pointermove carries, in order: each of getCoalescedEvents() where the browser has it
 * (iOS and Chrome keep the in-between samples of one motion there, the event itself last) - this
 * pointer's only - and the event itself when they don't end with it; each with its own time
 * (`eventTime`), and none earlier than the one before it nor the same twice.
 */
export function pointerSamples(event: PointerLike, now: number): PointerSample[] {
  let list: readonly PointerLike[] = []
  try {
    list = event.getCoalescedEvents?.() ?? []
  } catch {
    //? a browser that has the method and refuses it: the event alone
    list = []
  }
  const own = list.filter((sample) => sample && sample.pointerId === event.pointerId)
  const last = own[own.length - 1]
  if (!last || last.timeStamp !== event.timeStamp || last.clientX !== event.clientX || last.clientY !== event.clientY) own.push(event)
  const samples: PointerSample[] = []
  for (const sample of own) {
    const time = eventTime(sample.timeStamp, now)
    const before = samples[samples.length - 1]
    if (before && (time < before.time || (time === before.time && sample.clientX === before.x && sample.clientY === before.y))) continue
    samples.push({ time, x: sample.clientX, y: sample.clientY })
  }
  return samples
}
