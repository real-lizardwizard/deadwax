# The turntable's sound following the hand (2.0.0-player.24)

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### The record's sound follows the hand (2.0.0-player.24)

James, 2026-10-03: "the audio played when seeking doesn't seem like it's from the song. in theory, I
should be able to rotate the turntable at the same speed as it plays at, and it should play the song.
but when i do, it doesn't sound like anything". A fix to .14/.16, not a feature; the spec is the session
scratchpad's `uplan/slice-turntable-sound.md`.

- **What was measured** (the orchestrator, headless Brave against the stubs, the worklet, real touch
  events along a circle at exactly play speed, the voice's output recorded off its node, a 440 Hz left
  channel): the playback rate cycle by cycle had median 1.22, sd 0.68, swinging 0.1 to 1.3 every few
  tens of ms; 0% of cycles within 3% of the hand's speed. The POSITION the drives carried was right;
  their TIMING wasn't. Four causes: (1) one drive a frame, `{at: press.at, ...}` - where the LAST
  sample put the song, up to a frame older - stamped with a fresh `context.currentTime`, which moves in
  steps of the audio's own render (5.8 ms in desktop Brave, ~21 ms on an iPhone, whose hardware takes
  1024 frames) and stands still between: the voice's target jumped by the hand's speed times that error
  every frame, and FOLLOW_S chased each jump - FM at the frame rate; (2) the drive's rate was
  `handSpeed` taken at the FRAME's time, after the last sample, the turn held flat past it - a hand at
  exactly 1.0 read 0.65 median, 0 to 2.8 frame to frame, smoothed only 10 ms; (3) each sample was timed
  by `performance.now()` in the handler, not its event's `timeStamp`, and `getCoalescedEvents()` was never
  read; (4) the coasts, the motor, the wind-down and the handover were stamped the same stepped way.
- **A - one time base, `lib/deckClock.ts` (pure).** The context's time at page time `p` is `p/1000 +
  offset`, ONE offset: the UPPER ENVELOPE of `currentTime - performance.now()/1000` over the readings (a
  sliding maximum - CLOCK_WINDOW_MS 1500, and however old the last CLOCK_KEEP 90, so a mapping
  nothing read for a while - a page whose timers were held back - is still settled when next read).
  currentTime steps UP to the truth and lags between steps, so the highest reading is the nearest: while
  readings keep coming never ahead of it, within a step from the first reading and within a millisecond
  once a second of readings is in. HELD through a gesture (`held` = a hand on the record, a sounding
  plan, the handover: the deck's `steering()`), the offset in use moves towards the envelope at most
  CLOCK_SLEW (0.5 ms a second - a hundredth of a ms between two frames), and no more than 100 ms' worth
  across a pause in readings - whatever the readings say meanwhile, young or not (since the second
  review, below); let go, it takes the envelope, and is settled (`clockSettled`) once CLOCK_YOUNG (12)
  readings are in. A reading more than CLOCK_RESET_S (50 ms) below the envelope is a clock that stood
  still (suspended, resumed) and starts it again - as do a new context and its every `statechange`
  (deck.ts). The deck reads it every frame while anything moves, at every stamp, and on a timer of its
  own while the turntable shows and its context runs, the record still too (`keepClock`, since the
  second review: until then "every frame, so a press finds it settled" held only for a record that
  moved). **Why not `getOutputTimestamp()`** (the spec's first choice "where it answers sensibly"): it
  answers the SPEAKER's clock, which runs behind the clock the voice renders by (its own `now` is
  `currentTime`, or a block's `playbackTime`) by the output latency - a few ms on a phone's speaker,
  150-250 ms over AirPods. Stamped by it, every sample would land that far in the voice's PAST - played
  past before it arrives, beyond what HAND_DELAY_S keeps in hand - and over AirPods the voice would only
  ever be guessing; the render clock is the one the voice plays by. What the speaker adds after that is
  a constant: latency. `eventTime(stamp, now)` takes an event's `timeStamp` unless it is off the page's
  clock (more than EVENT_STALE_MS 1000 from now, ahead of it, not a number - some WebKit gave the epoch,
  which is why .14 used `performance.now()`); `pointerSamples(event, now)` gives a move's samples: each
  of `getCoalescedEvents()` (this pointer's, in order, nothing earlier than the one before, nothing
  twice), the event itself when the list doesn't end with it, the event alone where there is no list or
  it throws. The step it has seen (`step`) is in Info > Debug's Turntable sound note: "Its clock moves
  21.3 ms at a time" (`DeckReport.clockStep`, optional; `turntableRow` puts it after the voice and
  before the cost) - how James's phone renders, read off it.
  - **After review (A)**, three ways the envelope was wrong. (1) A context just made or resumed can
    stand still a while before it renders; readings meanwhile are each above the truth it then runs on
    from, and topped the envelope for 1.5 s - 8-42 ms ahead in the sim, and a reading late in a step
    then fell past CLOCK_RESET_S and restarted it MID-GESTURE. Now nothing is trusted until currentTime
    has moved since the mapping started (`moving`): meanwhile the offset is the latest reading's alone
    (a stamp is the clock's value as it stands, what its first block reads), and the envelope starts
    from the first reading after it moves - never ahead, no restart, for stalls of 10-100 ms. (2) The
    readings KEPT through a rest (CLOCK_KEEP) sit the drift above the truth when the audio's clock runs
    slow against the page's (a Bluetooth output's crystal): 15 and 30 ms ahead after five minutes at 50
    and 100 parts in a million, and on an iPhone's step a restart mid-gesture. Kept readings outside the
    window that a fresh one is more than a step and CLOCK_LATE_S (3 ms) below - more than any step's lag
    explains - are now let go of, and the mapping was made young again (`youngUntil`, CLOCK_YOUNG
    readings more): never a millisecond ahead, never restarted, behind by no more than a young mapping
    is (a few ms on an iPhone, as on any first gesture). So "never ahead" holds while readings keep
    coming, and after a rest only to within a step. (Since the second review there is no "young again":
    a young mapping was followed even held, and a gesture made young that way jumped 7-24 ms - now it
    keeps what it began with until it ends, so `youngUntil` went; and the deck's timer keeps the readings
    from going stale while the turntable shows.) (3) The step was
    the smallest move between two readings, which read only once a frame on a 60 Hz screen is 11.6 ms
    for a 5.8 ms render (11.6 or 17.4 between frames, never 5.8): Debug said 11.6 on a desktop. It is
    now the step every move is a whole number of (`stepOf`, a greatest common divisor to within
    CLOCK_GRAIN_S 0.1 ms) - 5.8 from frames alone - or, for a clock with no common step of
    CLOCK_STEP_MIN_S (0.5 ms) or more (one that runs smoothly), its smallest move as before.
  - **After the second review (A)**: the first grab of a STILL record after its context was made or
    resumed. Nothing read the clock while a paused record stood still - `readClock` ran in `onFrame`,
    which runs only while something moves, and in `stamp` - and every `statechange` (the context made,
    the screen closed and reopened, the page hidden and shown) starts the mapping again. So that grab's
    own stamps were the mapping's first readings: the take's provisional (the clock not yet seen moving),
    the envelope restarting as it moved, and for CLOCK_YOUNG readings the offset set to the envelope
    even held. Measured in decksound (a paused record left still, its context suspended and resumed,
    pressed at once and a second on, turned at 1x and 2x): on an iPhone's 21.3 ms clock the stamps
    jumped 13-16 ms inside the gesture and the sound over its first 300 ms went from 0.05x to 9x of the
    hand's speed (5.8 ms: 2-5.5 ms jumps). A long rest on a drifting clock did the same: a stale reading
    made the mapping young mid-gesture, 7-24 ms jumps. Three fixes. (1) HELD, THE OFFSET NEVER MOVES
    FASTER THAN CLOCK_SLEW: young, stale readings just let go of, or a clock not yet moving (held then,
    the offset stays as it was rather than following each reading, which would stamp every sample with
    the one time the clock stands at, its first move then jumping them all); only CLOCK_RESET_S, a clock
    that stood still with the voice, starts it again. An error the mapping had when the gesture began is
    held through it - a constant, so latency, put right as the gesture ends: behind by up to a step on a
    young mapping (the delay that much shorter), ahead by what was left of a standstill or by a drift
    kept through a rest (longer). (2) THE DECK READS THE CLOCK ON A TIMER OF ITS OWN while the turntable
    shows and its context runs, whatever the record does (`keepClock`/`armClock`/`onClockTick`): every
    CLOCK_SETTLE_MS (15) while the mapping is young - for the first CLOCK_SETTLE_TICKS (40) readings at
    most, so a context said to run whose clock never moves isn't read 67 times a second for nothing -
    then every CLOCK_TICK_MS (100). Started afresh on a show (a deck mounting on a context the look
    button's click already woke never hears its state change) and on every state change (`onAudio`);
    stopped at the hide (a real suspend settles later) and as the deck goes (left running, the gone
    deck's reading - its `steering()` false, so never held - let go of the mapping the next turntable's
    hand held). Ten readings a second keep it settled and fresh: on a clock 100 ppm slow for five
    minutes, never a millisecond ahead nor 2 ms behind, never started again (deckclock). (3) Debug's step:
    the first review's 11.6 -> 5.8 ms was pinned only in deckclock's `stepOf`, not the deck's line that
    tells Debug as the step changes - decksound checked it on the iPhone's clock, whose first move
    between two frames is already the step, so deleting the line passed every sim (Debug then read 17.4
    on a desktop for good). decksound now also checks the desktop's: a playing record's context resumed
    (its state change reports a step of 0), read by frames and the timer with deadwax's window held back
    so nothing else reports, must end telling Debug 5.8 - and at every reading Debug already shows the
    step the reading before left. Now the cold grab's mapping moves 0.006 ms at most between two readings
    and no further in all than CLOCK_SLEW allows, its sound over the first 300 ms 0.97-1.18 of the hand's
    speed - what any grab from still is (0.98-1.17 with no suspend before it: the run up from rest) - and
    a press a second after a resume finds the mapping settled (21 readings meanwhile). The cost: a timer
    ten times a second while the turntable shows with its sound running. A reading at every press, which
    the review also suggested, was left out: the timer covers it, and no check could tell it was there.
- **B - the hand as a path.** Turntable's `onMove` runs every sample `pointerSamples` gives through
  `recordMove` (geometry unchanged) and hands each to `deck.hand(sample.time, ...)`; `takeOver(time)` is
  the crossing sample's time; `pressed` and `release` the events' own (`eventTime`). The deck posts
  each sample as it comes, `{type: 'hand', at, time: stamp(time)}` - no drive under the hand at all
  (`onFrame` only shows `heardNow`) - and a hand knot at the take (the record is where the hand has
  it; a press that rests sends no more) and at a window arriving under the hand (`handWindow`: take,
  then that knot - both at the hand's LAST SAMPLE's time since review, not when the window landed, so
  samples on their way since aren't older than it). A sample older than the last is dropped, the same
  moment replaces it, in the deck (`press.samples`) and the voice alike. **The voice**
  (`lib/deckVoice.ts`) keeps the path as KNOTS in a ring of 64 (`knotTime`/`knotAt`/`knotPos`/
  `knotRate`/`knotAccel`/`knotUntil`/`knotSteady` - Float64Arrays - and `knotHand`, a Uint8Array, all
  made in `newVoiceState`; `first`, `end`, `cursor` counted from the first ever) and plays it
  HAND_DELAY_S (50 ms then; 120 since 2.0.0-player.27 - "The warble" below - the literal `delay` in newVoiceState, held equal by deck.sim) behind: per sample
  `tau = t - delay`, the knot found by a MOVING cursor (`while kt[c] > tau c--; while kt[c+1] <= tau c++`
  - amortised O(1)), and between two knots a cubic HERMITE through their places and speeds. A take
  resets the ring; `pos` starts where the path was `delay` before (`at + rate * (now - delay - time)`) -
  so a grab of a playing record, and a wind-down, replay the song's last 50 ms as the record's sound
  starts. Before the first knot, the take's own motion. Past the last: a drive's quadratic until `until`
  (then nothing to follow - it slows to still where it is); a hand's sample runs on EXTRAPOLATE_S (20
  ms), its speed tapering to 0, then HOLDS (a record held still is silent; never a run-away).
  - **A finger's jitter is smoothed out of the pitch - the spec's "Catmull-Rom/Hermite or similar".**
    Plain Hermite through the raw samples (Catmull-Rom tangents) passed the timing (sd 0.03% with no
    jitter) but not the spec's sim: half a pixel of jitter at ~110 px is ~0.75 ms of the song, a few per
    cent of pitch at 60 samples a second - measured 78% of cycles within 3% at 1x, 47% at 0.5x. So each
    hand knot's place and speed (`knotPos`, `knotRate`) are FITTED (`place`), to it and its neighbours
    up to SMOOTH_AFTER_S (20 ms: one sample at 60 Hz) after it. **As reviewed**: the builder's fit took
    the longest of 0.3 and 0.15 s a line explained to within a fixed BEND_S (3 ms), else a 0.1 s
    parabola - a cliff: jitter a little past 3 ms (a heavier finger, a grip nearer the spindle, where a
    pixel is more of the song) fell to the parabola, and the chord between knots' places carried the
    rest into the pitch. Gaussian jitter of 0.5 px at 0.5x was 59-77% within 3%, of 1 px at 1x 37-52%,
    a 60 px grip at 0.5x 54-77%. Now, scale-free: a PARABOLA over CURVE_S (0.1 s) and least-squares LINES
    back over each of SPANS (0.1, 0.15, 0.2, 0.3, 0.4 s), shortest first, each kept while its place and
    speed lie within AGREE (3.5) spreads of every shorter one's and the parabola's - the intersection of
    those intervals, as it narrows (Lepski's rule) - the spread from the JITTER MEASURED IN THESE SAMPLES
    (each one's distance from the line between its neighbours, 1 + w^2 + (1 - w)^2 its variance for
    jitter alone; never below JITTER_FLOOR_S 0.1 ms). A steady hand keeps the longest line, whatever the
    jitter; one that changes stops at the stretch that still agrees, or the parabola. Lines sums are
    gathered newest sample first, so each longer stretch adds to the last. **And the speed it reads
    at**: the Hermite's slope is the two knots' speeds between them plus what the chord between their
    places asks beyond that (`ask`, 6s(1-s) times the chord less the mean of the speeds); each hand
    knot records how steady the hand was there (`knotSteady`: which of SPANS its line is, 0 for the
    shortest to 1 for the longest, 0 for the parabola and anything said), and the voice takes `ask` only
    as much as the less steady of the two knots wasn't (`v = lerp(rates) + (1 - min(steady)) * ask`) -
    where the hand was steady, `ask` is jitter, and the steering (FOLLOW_S) keeps the place. The place
    is still the Hermite; a drive's knots are never steady, so coasts follow the exact cubic as before.
    The blend vanishes at the knots, so the speed is continuous. The hand's OWN samples only - back no
    further than the knot its run began from (a take, a coast's frame), so a coast caught and held comes
    to rest where the hand caught it. Re-fitted as each later sample within SMOOTH_AFTER_S arrives. The
    50 ms covers a sample's spacing (16.7 ms), its fit's one sample after (16.7) and delivery (a few
    ms): the knots a moment needs have always arrived. Cost: per message, the knots re-fitted (two at 60
    Hz, three or four at 120) each walk their samples about seven times (the jitter, the parabola, the
    lines in one pass) - a few thousand flops; per audio sample nothing new.
  - **Rests.** A knot further than REST_S (40 ms) after a hand's last sample: the path ran on and
    stopped, so a still knot (kind 0) goes in where it stopped (`rested`) - what follows starts there,
    not from a cubic swung across the gap (it dipped 40 ms behind on a 0.3 s rest). A hand moving again
    also gets a set-off knot (kind 2) just before its first sample, its time SETTLED by that sample's
    fit (`settle`): as late as its place and speed allow without the path stepping back to reach it -
    at most RESUME_S (17 ms) before, at once if it hasn't moved on yet. **As reviewed**: (1) A hand sample
    no more than MISSED_S (0.1 s) on, where the last knot's speed would have it to within KEPT_ON (a
    quarter) of how far that is, or KEPT_S (3 ms), is NOT a rest: samples went missing (a busy page with
    no coalesced events - on plain http there are none) and the path runs on through the gap. Two missed
    at 1x read as a rest went 0.14x then 2.2x, 20 ms astray; now within 4%, 0.3 ms. Three missed (67
    ms) is longer than the delay holds - the run-on slows it and it is caught up at 1.17x, 9 ms astray
    (3.2x and 38 ms as a rest). MISSED_S keeps a hand that eased to rest and set off 0.3 s later a rest
    (its last speed times the gap happened to match). (2) A drive after a rest (a release in the rest
    band) gets the still knot where the run-on stopped and then a still knot AT ITS OWN MOMENT and that
    place: the plan sets off from where the sound stopped, the path stepping back to where the hand let
    go as it does, and the steering takes the step up going forward - never back (a curve across the
    rest to the plan's start ran it at -0.7 of the hand's speed; now -0.13, which is any dead stop's own
    settling in the final stage). `knotHand`: 1 a hand's sample, 0 said (take, drive, still, a plan's
    set-off), 2 a hand's set-off. **A hand sample older than the knots after it that are the record's own
    motion** (a coast's frames, posted at their frames' times while the move that crossed a tap's slop
    was on its way - which a touch's delivery makes common) cuts them away, as a drive cuts what is
    newer than it, and takes the path from its moment; it is dropped only when older than another HAND
    sample. Strictly newer: a take at the same moment as the hand's first sample stays. As built, it was
    dropped: the coast ran on under a still finger to its last drive's `until` (0.4-1 s of the song at
    3x-7x in the sim) and the next move rushed it back at -7x to -18x; now it rests where caught.
- **C - planned motion.** A sounding plan's drives are stamped at the moment their place was worked
  out - each frame's rAF `time` (`drive(motion, time)`, its place, speed and acceleration there), the
  plan's START at once (startPlan posts it - the knot the hand's path hands over to), the handover at
  the plan's END (`since + duration`, not when the timer fired). Drives are knots too: between two, the
  Hermite through their exact places and speeds (C1, and followed within ~1 ms of real time even told
  only every 40 ms at 9x - deck.sim's "within a ms" check still holds frame by frame); a drive earlier
  than the newest knot replaces what came after it (the handover after a frame's past the end), so
  knots stay in time order. The plan's timer is shortened by however long ago `motion.since` was. So
  coasts, the motor, the wind-down and the handover are 50 ms behind too. **As reviewed**: (1) the
  plan started at the RELEASE's time from `press.at` - where the LAST SAMPLE put the record, up to a
  frame or so earlier - while `releaseSpeed` counts that tail as the hand still moving: the Hermite
  between the last hand knot and the plan's start (same place, both moving) stood still for the gap,
  its slope down to -v/2 midway - 0.45x of the platter's speed 8 ms after the last move, 0.07x at a
  frame, backwards past that, on nearly every flick. `release` now starts the plan at the last
  sample's own time (`since`) when the lift is within RELEASE_TAIL_MS of it - the release drive then
  replaces the hand's last knot, from where and when the hand had it - and at the release's after a
  rest (the record was held still: D1b in the mutation run, which plays it on through the rest). (2) A
  frame's rAF time is when it BEGAN, and the release or the tap it follows can be later; driven, its
  place would be stamped before the plan began and the drive rule would erase the plan's start
  (`planAt` clamps a negative time to 0). `onFrame` drives only past `stampedTo`, the latest page time
  anything told the voice was stamped at (kept by `stamp`).
- **D - the release's speed** (`releaseSpeed` in platter.ts): `handSpeed` over VELOCITY_WINDOW_MS up to
  the LAST SAMPLE, by the samples' own times; a gap to the release up to RELEASE_TAIL_MS (40 ms - a
  frame and its delivery) is no slowing, a longer one a rest that takes it down in proportion, to 0 at a
  whole window (a finger that stopped before letting go doesn't flick). Before: a 30 ms still tail read
  a third slower.
- **E** - unchanged: the time line under the hand and during a coast shows the voice's `heard`
  (`heardNow`), now 50 ms behind the hand; the song's own playback, the seeks and the handover's landing
  are where they were. **What that costs at a let-go** (review): a release that plays the song in its
  own gesture (a playing record let go near 1x - James's own case - or under Reduce Motion) stops the
  record's sound in it, and the voice, 50 ms behind, hasn't played the hand's last 50 ms (93 ms on
  plain http): that stretch of the song is heard by neither, the song playing on from where the hand
  let go after its element's start-up. decksound pins it (44 ms of the song on the worklet, 62 on the
  main thread, lifted 8 ms after the last move: within 30-50, and the lag plus 0-50). The coast's handover is an overlap rather than a skip: the voice holds speed 1 until the
  song really plays. **F** - the script host shifts a hand sample's `time` by the same lag as a take or
  drive (SCRIPT_LAG_BLOCKS) and holds EVERY one, in order - and, since review, every drive too (it let
  a drive replace the drive held just before it, a knot the worklet kept and it didn't); only a window
  replaces every window before it. The four functions are still self-contained (the fit, the rest and
  the set-off are inner arrow functions of voiceCommand; SPANS an array literal in it; the vm-run module
  is held sample for sample to the functions through a hand's samples too). On the main thread the
  record is 50 + 43 ms behind the hand. **G** - a sample costs its `pointerSamples`, `recordMove`, one
  clock reading (a sliding maximum) and a postMessage; the voice's fit runs per message (B gives its
  cost), its per-sample work is the cursor and one cubic. **H** - unchanged: the look, the switch,
  Reduce Motion, a flick on a paused record landing paused, the handover, the song paused under the
  hand, the windows, no createMediaElementSource, one audio element, the visualizer; `HAND_SPEED_MS` is
  gone (nothing takes a hand's speed for the sound any more).
- **Measured** (`ui/test/decksound.sim.cjs`: the REAL Turntable, deck, clock and voice; a 440 Hz tone;
  touch samples 60 a second - 120 coalesced in the 1x iPhone runs - delivered 4 +-3 ms late, uniform
  +-0.5 px jitter on each axis at 120 px from the spindle; the audio's clock stepping 5.8 and 21.3 ms;
  the worklet in bursts of the hardware's render, the script voice in blocks of 1024 a block late): at
  1x, 2x and -1x 99.9-100% of cycles within 3% of the hand's speed on both hosts and clocks (sd
  0.15-0.47%), at 0.5x 97-100% (sd 0.7-1.2%; the builder's 94.5-96.8%, sd 1.5%); the read head within 2
  ms of where the hand was 50 ms before (plus 43 ms on the main thread). A hand swinging 0.4x-1.6x
  followed within 3.6 ms, 87-88% of cycles within 3% (75-76% as built), one turned back and forth at up
  to 1.5x once a second within 5.2. The page side as it was, in the same harness (each sample timed in
  its handler, a drive a frame at `handSpeed` over 40 ms at the frame's time, stamped by `currentTime`,
  into today's voice): under half. The HEAD code itself (.21's deck and voice, run in a scratch copy of
  the same harness): 5-8% within 3%, sd 34-39%, at every speed and both clocks - and with no finger
  jitter at all still 7% and 6%, sd 34-38%: the timing, not the finger. **The review's cases**, as built
  and now, in the same sim: Gaussian jitter 0.5 px at 0.5x 77-82% -> 95-100%; 1 px at 1x 40-50% ->
  96-100%; a 60 px grip at 0.5x 54-70% -> 92-99%; 80 px 79-85% -> 98-100%; whole pixels 90 px out at 0.5x
  89-92% -> 100% (a scratch harness over more seeds and hosts agrees: 32 runs each, never under 92%).
  Whole pixels sent only when they change (a desktop mouse) at 0.2-0.3x: 63-73% -> 72-87%, the most a
  pixel's resolution allows at 60 Hz with one sample of look-ahead. Letting go 0-30 ms after the last
  move: the sound over the platter's speed -0.33 to 1.09 -> 0.96 to 1.06; 45-60 ms after (a rest): the
  slowest -0.74 of the hand's speed -> -0.13. A coast caught by a sample older than its last frame:
  rested 0.4-1 s of the song past the catch and rushed back at -7x to -18x -> at the catch (on past it
  only the final stage's own 7.5 ms of song per 1x, as any dead stop), nothing back. Two samples missed
  in a steady hand: 2.2x and 20 ms astray at 1x -> 1.006x, 0.3 ms; three: 3.2x, 38 ms -> 1.17x, 9 ms.
  The clock: a context standing still 10-100 ms after it starts, 8-42 ms ahead and restarted
  mid-gesture -> never ahead, no restart; five minutes' rest at 50 and 100 ppm slow, 15 and 30 ms ahead
  (and on an iPhone's step restarted mid-gesture, a 12 ms jump) -> no restart, and since the second
  review no jump either (the gesture keeps what it began with - ahead by the drift at most, behind by a
  step at most - and once let go never a millisecond ahead); Debug's step read once a frame, 11.6 -> 5.8
  ms. The second review's cold grab (a paused record's context suspended and resumed, pressed at once
  and a second on, at 1x and 2x, both hosts and clocks; 96 runs in a scratch probe, 16 in the sim): the
  mapping in use moving 13-16 ms inside the gesture on the iPhone's clock (2-5.5 ms on the desktop's) ->
  0.006 ms between two readings at most, never more in all than CLOCK_SLEW; the sound over its first 300
  ms 0.05x-9x of the hand's speed on the iPhone's clock -> 0.97-1.18 (the same grab with no suspend
  before it, 0.98-1.17: a grab from still runs up to the hand's speed).
- **Verified**: 2227 Python tests (2101 run here, 126 skip without the audio libraries; none new - the
  change is the page's), pyflakes, tsc, and all 42 sims (`deckclock` 35 and `decksound` 67 new; `deck`
  241, 19 more - the delay in the voice's checks, the release's speed by the samples' times, the coast's
  start and the handover stamped by the one clock, a stray old sample dropped, a window under the hand
  starting the hand's path at its last sample, a hand's samples through the vm-run module, a frame begun
  before the release or a wind-down's tap driving nothing, and on the main thread all twenty of a
  stalled hand's samples and all six of a coast's frames applied in order with their own times and the
  lag, and the second review's four on the timer the clock is read on; `debug` 86, two new). Of the 21
  checks the review added, 19 fail on the builder's code; the other two pin what it kept (a smoothly
  running clock's step, and the let-go at 1x skipping the delay's stretch); the swing's new 80% and the
  release-after-a-rest's knots fail there too. Mutations, each restored byte for byte - the builder's 51
  and 27 for the review's rules. Of the builder's: 40 caught as written; 8 rewritten where the code they
  named has changed, 7 of them caught (never held, nothing kept through a rest, never young, short spans
  only, no parabola, no rest knot, a fit reaching back into the coast) and the builder's
  Hermite-over-a-line - place and speed - caught by the harder hands; 3 superseded by the review's own
  (the step, the bend test, the drive-replacing rule). The one that survives: the Hermite PLACE alone
  made a straight line, the speed left as it is - the speed carries the motion between knots, and a
  chord's sag between knots 16.7 ms apart is a fraction of a millisecond (on a coast told every 80 ms
  the line measures 1.9 ms of real time to the cubic's 2.3); kept as the spec asks. The review's 27 -
  the clock's provisional phase, its stale readings let go of and the mapping young again, its step
  (smallest move; a common step for a smooth clock), the feed-forward weighting (always the cubic's
  slope; always the knots' speeds), the agreement test (none; twice as loose; twice as strict), the
  jitter measured (the floor only), the curve held to, steadiness for any line, the longest span, missed
  samples (always a rest; however long the gap; no KEPT_ON), the frame guard (none; `stampedTo` never
  moved), a window's stamp, the script host's drives, the plan's start (the release's time; the last
  sample's however long the rest), the hand's cut (none; >=), and a drive's set-off after a rest (a
  curve; where the hand let go) - all caught. **The second review's**: 14 checks more (deckclock 3,
  decksound 7, deck 4) and 4 restated (deckclock's young-held check, now a gesture begun on a cold
  mapping never jumping; its stall and drifting-rest checks, now counted from the gesture's FIRST
  reading - the old exclusions, `at > runs + 400` and `n > CLOCK_YOUNG + 4`, were exactly the readings
  that jumped; decksound's frame count, the timer's readings now beside the frames'). 12 of them fail on
  the code before it; the other five pin what the fix must keep or what it already had: the timer
  stopped while hidden (twice), the deck's line telling Debug of a step change (its own mutation fails
  it), a mapping not held being the envelope, and ten readings a second following a drifting clock.
  Mutations, each restored byte for byte: the second review's 20 - the held rule (a young mapping
  following the envelope as built, following each reading while the clock stands still, its first move
  dropping the offset, stale readings dropping it), `clockSettled` always and never, the timer (none,
  never quick, quick for ever, its ticks never counted, a fresh start keeping the old count, not started
  on a show or on a state change, left running at the hide or regardless of showing, left running by
  `destroy`, a tick that reads nothing), stale readings never let go of, the first review's never-held
  rewritten, and the Debug step line - all caught. The earlier 88 re-run on the final code: 70 caught as
  written; 3 whose code changed rewritten and caught (never held; kept readings not kept through a rest;
  stale readings never let go of, the second review's own); 2 gone with `youngUntil` ("never young" is
  the rule now; "let go of but not young again" SURVIVED on the code before `youngUntil` went, which is
  why it went - being young again changed nothing any more); the same 11 already superseded in the first
  review's run; and the same survivor (V4' and V4''', one mutation written twice: the Hermite place
  alone made a straight line). The engine guard is empty and `player.sim.cjs` untouched.
- **Verified in the real page** (headless Brave against the stubs, `scratchpad/ttmeasure`: the song
  "Test Signal - Instrument", left a steady 440 Hz and right a sweep of 300 + 9t Hz, the record turned
  by real touch events along a circle at exactly 1x, 0.5x, 2x and backwards, ~60 a second, the voice's
  output recorded off its node and read cycle by cycle - rate from the left's pitch, place in the song
  from the right's): on the worklet (localhost) and the script host (plain http), and both again with
  `--audio-buffer-size=1024` (the audio clock stepping 23 ms, as an iPhone's does), 100% of cycles
  within 3% of the hand's speed in all ten runs, sd 0.001-0.005, the place read moving at exactly the
  hand's speed (1.000, 0.500, 2.000, -1.000 s a second) with 1-7 ms of scatter. With a pixel of random
  jitter on every touch: 98% (worklet) and 100% (script host) within 3%. Before, measured the same way
  on 2.0.0-player.21: 11-51% within 3% with that perfect finger (sd 0.04-0.11), 24% on the 23 ms clock.
  `ttcheck` (the turntable's 53 real-page checks) and the visualizer's 42 passed on this code.
- **NOT verified here**: everything on James's iPhone: the feel of 50 ms (93
  on plain http) under a finger, iOS's `getCoalescedEvents()` and `timeStamp` (both guarded; on plain
  http getCoalescedEvents is a secure-context API, so there the samples are the events alone), the clock
  step Debug reads there, how much a real finger jitters (the fit now measures it rather than assuming
  under a pixel), whether a real context stands still after it starts or resumes, how far a real
  output's clock drifts, and that the smoothing feels neither sluggish nor jittery under a real hand.
  From the second review: that a real context's clock is seen moving within the deck's first few quick
  readings after a resume (if not, the first grab holds an error of up to a step - latency, never a
  jump); what ten readings a second cost on a phone while the turntable shows; and the first grab of a
  paused record after reopening the screen, on James's iPhone over plain http.
