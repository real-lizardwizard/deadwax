# The turntable's test bench (2.0.0-player.36)

The page at /player/lab/: the real turntable over signals it makes, beside an ideal one. Read it before changing the bench, or the deck's window source, recorder or analyser tap. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### A test bench for the turntable (2.0.0-player.36)

James, after seven turntable fixes (.24, .27, .28, .29, .30, .31, .35) and three blind renders of his own
hand path that didn't separate for him: "I'm not sure any of those have the same sound to be honest.
maybe my expectations are skewed, so a test suite may be in order ... I want to be able to use the
turntable on a few different samples. maybe a regular sine wave, a square wave, and maybe a few
variations or combinations, just as a sanity check". The spec is the session scratchpad's
`uplan/slice-turntable-lab.md`. **Nothing the app plays changes**: the bench only observes, and a fix
it points to is the next slice, measured with it. The guide's section is `docs/player.md#testing-the-turntable`.

- **A page of its own, `/player/lab/`** (`interface/player/lab/index.html` and `lab.css`; the entry
  `deadwax-lab`, `ui/src/lab/main.tsx`). Served by `stamped_page("player/lab/index.html")` (app.py now
  takes the page), so its links carry `?v=` and it is `no-cache` like `/player/`; not in the manifest,
  on no tab. **Built in a pass of its own** (`vite build --mode lab`, which `npm run build` - and so the
  image and CI - runs after the app's, `emptyOutDir` off, chunks named `lab-*`): built beside the app,
  rollup split the deck and the turntable into chunks the app's page then loaded, so the app's bundle
  changed. Alone, it carries its own copy: the app's pages load the same three files as before, and
  `deadwax-ui.js` and the shared chunk are byte for byte 0d97d07's (`deadwax-player.js` differs by the
  deck's, Turntable's and Info's few lines).
  `tests/test_pages.py` reads both passes' entries (`APP_INPUTS`, `LAB_INPUTS`), and
  `tests/test_lab_page.py` holds the page, the pass, the stylesheet (tokens only, 44px coarse targets,
  16px+ fields, a ring on every focusable control) and that nothing else of the bench is on the server.
  **Linked from Info > Debug's "The turntable"**: a row **Test bench** (`benchRow` in lib/debugRows.ts,
  `BENCH_ADDRESS`) whose action is a link that opens BESIDE the app (`DebugRow.action.beside`, drawn by
  InfoSheet with `target="_blank" rel="noopener"` - app-rules' links-out list gained InfoSheet.tsx).
- **The REAL turntable**: the bench renders `player/Turntable.tsx` with its real Deck and voice - the
  pointer handling, coalesced samples, the clock, both hosts, the window decode, the limiter and the
  wind-down are the app's. Three changes outside the bench make that possible, each one the app can't
  see: `TurntablePlayer` (a `Pick<Player>` of the eight fields Turntable reads; usePosition is handed it
  `as Player`, since it reads only position() and onPosition()); an OPTIONAL `DeckHost.window(song, from,
  seconds, signal)` used instead of `scrubWindow` when given, and a `windowSource` prop on Turntable that
  sets it (a song with one is a FLAC to the deck - the bench makes its windows); and in deck.ts a
  recording kept for the page (`recordDeckSound(seconds, keep)`, `deckRecordingData()` - floats, every
  channel, the messages, the reports, the clock and the saved file's own text, which is unchanged,
  version 2 - and `stopDeckRecording()`) and an AnalyserNode on the voice's node for the live spectrogram
  (`deckSoundAnalyser()`, on to the speakers through a gain of 0, `releaseDeckSoundAnalyser()`). The app
  passes no window source and asks for neither: `deck.sim`, `decksound.sim` and `limiter.sim` pass with
  no check changed, and app-rules holds App.tsx and NowPlaying.tsx to never naming `windowSource`.
- **Its own player** (`lab/benchPlayer.ts`): a TurntablePlayer backed by ONE `<audio>` of the bench's
  own playing a 24-bit WAV blob of the whole song (blob URLs work over plain http) - play, pause, a seek,
  a coast's handover back to the song and the element's own start-up behave as the app's. Never
  usePlayer, never Web Audio on it (app-rules: one `createElement('audio')`, nothing of `lab/` reaching
  the app's player). Its position is 0 until the element holds the song it is handed: Turntable's effects
  run before the hook's, and for that moment the element still holds the song before.
- **The signals** (`lab/signals.ts`, pure): seventeen, each a deterministic function of time defined
  ONCE - the song, the deck's windows (`signalWindow`: exactly the song's samples [first, first +
  samples), a 416 past the end) and the ideal reading (`exact(t, cutoff)`) all come from it - at 44.1,
  48 or 96 kHz, two minutes, -12 dBFS peak unless said. Band-limited by construction: every harmonic
  strictly under the source's Nyquist frequency (square, sawtooth and triangle by Clenshaw's recurrence),
  the clicks a Kaiser-windowed sinc at 0.46 of the rate. **Square 220 Hz, aliased on purpose** is a
  labelled reference, never deadwax's. A 24-bit PCM WAV (decodeAudioData takes it in Chromium, Firefox
  and WebKit; its quantization about -149 dBFS RMS, far under anything measured). A periodic signal is
  worked out over one stretch that repeats exactly and copied.
- **Turn it for me** (`lab/motions.ts`, `lab/runner.ts`): steady 1x, 0.5x, 0.25x, 2x, backwards 1x, a 10%
  wobble at 1.3 Hz, a ramp 0.25x-2x-0.25x over 8 s and a scratch (1.5x at 2 Hz) - 60 samples a second on
  the page's clock, through the very methods a press drives (`pressed`, `takeOver`, `hand`, `release`, and
  the release's answer done as Turntable does - with the player as it is AT the release, `runMotion`
  taking a getter: the bench's player is a new object each time it starts or stops), with an optional
  finger's jitter (decksound's 1.5 ms and 1 ms, seeded). From its tap (`preparing`, its making ready
  included) the record is inert and the transport's Play refused; Stop stops it once it turns. A paused record sought where its
  window doesn't reach is pressed for a moment as a finger's that isn't the deck's (`holdStill`) to ask
  for one, and the motion waits for `deck.live()`.
- **Record, and compare** (`lab/compare.ts`, `lab/analysis.ts`, pure): **A** what the voice played; **B**
  the signal read EXACTLY (`readExactly`: the definition at the read head's place, band-limited by an
  ideal brick-wall resampler's rule, `cutoffAt` = output Nyquist / |speed|) along the read head's own
  path, every sample, from the recording's messages REPLAYED through the four voice functions
  (`replay`: renderVoice one sample at a time, which is the same arithmetic as a block); **C** the same
  along a zero-phase path, the delay (and the main-thread lag) behind - the hand's samples smoothed
  (`smoothPath`: a tricube-weighted parabola over them 0.15 s either side, worked out every 1/240 s and
  a natural cubic spline drawn through it, so its speed is its own rate of change), in runs split the
  way the voice splits them (a gap is a rest only when the hand didn't keep moving through it - the
  voice's REST_S, MISSED_S, KEPT_ON, KEPT_S), run on to still after a run (EXTRAPOLATE_S) and set off
  just before the next (RESUME_S) - or, for a motion, its own definition (`exactKnots`: at the times the
  deck stamped its samples, through a smooth curve of the stamps - a tricube fit 0.5 s either side and a
  natural spline - so the speeds agree with the places); and every part joined to the next with no step
  in place or speed (`joinPieces`: the take to the hand, a run to its rest and the next run, the hand to
  the coast it let go into, a coast to the hand that caught it - a difference in place let go of over
  JOIN_DECAY_S, 0.3 s, the speed carried over JOIN_BRIDGE_S, 30 ms). When the voice was told each message is
  fitted to what it said of itself (`planTiming`): one lead for all, then each take, fade and stop moved
  up to three blocks to where the reports put it. The main-thread voice's blocks are numbered by its own
  reports (headless Chromium's stamps move 1023 frames a block). Level-matched; the listening room
  (`lab/listen.ts`, an AudioContext of its own made only from the Play button's tap or Space's keyup)
  plays all three from one moment and switches through a moment's silence (`switchPoints`: every clip
  out over 5 ms, 40 ms silent, the chosen one in over 5 ms - never two heard at once, so every switch
  sounds alike); 1-3 and Space anywhere on the page while a comparison shows (not in a field, Space not
  on another button), the arrow keys among A, B and C (one tab stop). **ABX** with
  Math.random (a listening test's, not the visualizer's) and the binomial chance. **The numbers**:
  strayed from the smooth path (ms, most and typical), the speed's wobble above 20 Hz (both paths,
  forwards-and-back high-pass, 1 ms bins), and for a tone what isn't the signal (`stray`: per third of a
  second under Blackman-Harris, A's energy away from B's own content - within 85 dB of its loudest and
  8 Hz round - against the energy near it; the loudest stray component with its window's lobe), plus how
  well the replay reproduces the recording.
- **What the replay can't know** (found in the real page): it tells each message at one lead fitted
  to the reports (and each take, fade and stop where they put it), but a message reaches the voice when
  the page and the audio get to it - so where the speed changes the replay can be up to a tenth of a
  millisecond of the song off (replay -18 to -90 dB, on both voices, where it isn't to the bit) -
  harmless, since `stray` is by frame with an 8 Hz guard (the stray numbers of such runs sit with the
  rest). And a page held up for a few hundred ms - seen once in a headless device check of ten runs on
  the main thread: the hand's samples handed over late, the voice running short of its path, its own
  reports dipping to 0.23x on a 0.5x motion - is a run the replay can't follow at all (fit 9 ms, replay
  -5 dB, and a "stray" of -61 dB that was the stall's). `replayHeld()` (compare.ts, `REPLAY_HELD_MS`
  0.5) says so: such a run reads **Record it again** in place of A against B, in the comparison and in
  the device check's list (with why - `replayVerdict`, and the words in `lab/reading.ts`: a stall, a
  recording nothing took, or nothing reported after the take), which also counts the page's late frames while it turned (DeckHealth's
  `slowFrames` - a run's the difference, since the deck counts from the turntable showing).
- **Check this device**: the 1 kHz and 440 Hz sines, each motion of steady 1x, 0.5x, 2x, backwards 1x
  and the wobble, recorded and compared; **Save results** is one JSON of the user agent, secure, the voice,
  the rate, deadwax's version (`/deadwax/health`), every number and every recording (`lab/check.ts`'s
  `checkFile`) - a check stopped part way (**Stop the check**, or a run failing) gives one too, of the runs
  it finished, `complete: false` with `stoppedBecause`. A run the page was hidden through (`lab/watch.ts`)
  is thrown away and the check waits for **Carry on** - the tap that brings the sound back - to make it
  again; the page says to keep it in view and the screen awake.
- **The live spectrogram**: the analyser above, drawn while the record sounds and the page shows.
- **Gestures**: the deck's context only from the bench's Play, Start the sound, a motion, Record, the
  device check's and Carry on's clicks (app-rules' list gained the six on purpose) and the record's own;
  the deck's recording once its sound runs - Record wakes it in the tap and waits - or from a motion once
  the deck is live.
- **The local rolldown workaround** (Tooling, for the Mac's old Node) needs the third entry too:
  `'deadwax-lab': 'src/lab/main.tsx'`, in a config of its own like the second pass.
- **Not built, on purpose**: any change to what the app plays (the bench only observes - a fix it
  points to is the next slice); the bench on any tab or in the manifest; a server route of its own (it
  reads only `/deadwax/health`, for the version in Save results); a sim of Bench.tsx rendered - it is
  checked in the real page (the sims hold the pure parts - since the review the bench's own player too,
  against an element that drops its queued 'pause' on a load as a browser's does - the real deck driven
  with the bench's window source, and app-rules the gestures and the wiring).
- **The baseline** - "Check this device" in headless Chromium, 48 kHz, on both voices (the main thread
  over plain http as `deadwax.test`, the worklet on localhost), every run on the 1 kHz and 440 Hz sines
  at 44.1 kHz: the clock moving 2.7 ms at a time, no block late; the speed's wobble above 20 Hz
  0.0002-0.0021% at steady speeds and on the 440 Hz wobble, 0.013% on the 1 kHz wobble over the main
  thread (the motion's exact path 0.008-0.018% as built - its knots on the deck's raw stamps, the
  review's finding; measured again after it, in the same page, 0.0002-0.0004%: the motion's own
  definition, and deadwax's 0.0002-0.0031%); what isn't the signal
  -82 to -89 dB, its loudest component -84 to -93 dB; the read head within 0.16-0.84 ms of the motion's
  exact path at most, 0.01-0.27 ms typically. Against that, James's second recording wobbled about 0.9%
  above 20 Hz along his own hand. A real-touch turn at 1x over the 440 Hz sine was heard at 1.000x on
  both voices, the replay -63 dB with its read head within 0.002 ms.
- **After review** (23 findings confirmed - two of them the same C path, merged - every one fixed, in the
  bench's own files, the docs and the sims; nothing the app plays changed, the engine guard and `deck.sim`,
  `decksound.sim`, `limiter.sim` untouched):
  - **C stepped where deadwax doesn't** (major, two findings): at a let-go it switched from the smoothed
    hand to the coast the deck planned from the hand's RAW last sample (up to 2.3 ms of the song, 5.4 with a
    motion's jitter); a gap of three missed frames was read as a rest (C stalled 67 ms, then jumped as far,
    "Read head off the smooth path" 66.67 ms); a resume jumped up to 8.8 ms (6.7 on James's own rec2); and
    a motion's knots sat on the deck's stamps - which go up a few microseconds unevenly frame to frame -
    with the definition's speeds, so the cubic kinked at every knot: sidebands 64 dB down, C's wobble
    0.013-0.04% against deadwax's 0.0015% (C against B -47 to -50 dB with no jitter). Now the rest rule
    and run-on are the voice's, every part is joined with no step in place or speed (`joinPieces`, from
    the take's own speed too: a motion's definition starts at full speed, a click in C alone), the hand's
    curve and the stamps' are splined so their speeds are their own rate of change, and C's wobble on a
    motion is the definition's own (0.00025%, sim) - C against B -98 dB with no jitter, C's sharpest turn
    no sharper than A's, and continuous over James's rec1 and rec2.
  - **The ABX switch gave X away** (major): a 5 ms crossfade between two clips the same tone a fraction of
    a millisecond apart (A and C) dipped up to 19.6 dB and clicked, where a switch to X's twin was
    seamless. Now every switch fades out, is silent 40 ms, and fades in (`switchPoints`) - the same
    whichever two clips (spill -33.4 dB for both, where the crossfade's was -29 against -100).
  - **The bench's player kept saying playing after a song change** (major): pause() then a new address
    runs the element's load, which drops the queued 'pause' - the record spun over a silent song, and
    Pause, a hand on the record or the check's own toggle then played it, two sounds at once.
    `setPlaying(false)` with the new song, and 'emptied' heard as a pause.
  - **A hidden page** (major): the run it cut short was listed as whole, the next run waited for a sound
    nothing would resume, and the check died with nothing to save - and James's iPhone locks after 30 s or
    a minute untouched, the check taking 93 s. Now a hide stops the run or recording and throws it away
    (`lab/watch.ts`, latched), the check waits for **Carry on** (a tap, which brings the sound back) and
    makes the run again, and the page and guide say to keep the screen awake. A run whose replay didn't
    hold shows only **Record it again** and the replay's own row - its numbers were the stall's.
  - **A check stopped part way gave no file and said "Stopped - stopped"** (minor): now `checkFile` of
    every run finished, `complete: false` and why; "Stopped after N of 10 runs. Save results has ...".
  - **Changing the song mid-recording measured against the old one** (minor): the song's controls and
    Check this device are locked while anything records (`locked`), and a recording whose song changed
    anyway is thrown away. **A short file ran a motion off its end** (minor): `motionStart` takes the
    motion's reach, and refuses a file too short ("it needs N s").
  - **Keys and focus** (three findings, one of them 2 to 1): Space and 1-3 now work anywhere on the page
    while a comparison shows (not in a field; Space presses any other focused button), the comparison's own
    controls `data-room`; busy buttons aria-disabled, never disabled; what the blind test takes away hands
    focus to its next control and a comparison landing takes it to its Play; the A/B/C chips one tab stop
    moved by the arrows; "Stop the motion", "Stop the check", "Play the comparison", "Play the trial".
  - **Smaller**: the record's label marked so it can be seen to turn (`--lab-label-mark`); `.lab-status`
    reserving its line (its min-height read a unitless line-height token); Record waiting for the sound to
    run (its first tap on a cold page was refused); the aliased square's note (its aliases are in the song,
    so they move WITH the speed - the spec's "the wrong way" was a physics slip; a sim reads them at 0.5x,
    1x and 2x); the guide's pink-noise level, its Debug table's Test bench row, its switch claim; the
    migration doc's third entry and why it is a pass of its own; this file's and tests.yml's build lines.
  - **Tests that couldn't fail** (four findings): the runner's release (seek, play) now checked in the deck
    runs; the sampled reader read between samples and band-limited (a file of a sine, a 15 kHz tone cut at
    10 kHz); the stray floor on a perfect triangle, square, sawtooth and chord (-90 to -98 dB) and the
    voice's 1 kHz check tightened to -75 dB; the bursts' edges, timing and the chord's notes pinned.
- **Verified**: 2387 Python tests (2385 passed, 2 skipped; 14 new - `test_lab_page.py` 12, two cases in
  `test_pages.py`), pyflakes, tsc, the bundle (two passes; the app's pages load the same three files),
  and all 46 sims (`lab` 68 new; `app-rules` 277, 8 new; `debug` 100, 2 new; `info` 134, 1 new;
  `deck`, `decksound`, `limiter` and `player` with no diff). 53 mutations, one or more per rule (the
  signals, the WAV and its window, the exact reader, the replay's grid, lag and timing, the smooth path,
  the wobble and stray measures, the ABX, the motions, the level-matching, the replay-holds rule, the
  deck's window source, kept recording, stop and analyser, Turntable's guard, the bench's gestures,
  Info's link, the served page and the build's pass), each file restored by hash: all caught - six only
  once their checks were tightened (a partial's cutoff, every copied stretch, the lookahead, the jitter's
  stated size, the analyser's release, and one that first broke the build and was remade valid).
  **In the real page** (this worktree's own deadwax on 8104, headless Chromium, real touch and clicks):
  29 of 29 on both hosts - every signal made at 44.1 and 96 kHz and a picked file, the voice said, a
  real-touch turn at the hand's speed, Record and A/B/C with 1-3 and Space, ABX scored, every motion,
  inert while one runs and Stop, the live spectrogram moving and stilling, Check this device finishing
  (93 s) and Save's file, no overflow at 390x844, 375x667, 844x390 and 1440x900, no console errors; Info
  > Debug's row opening the bench in a tab of its own with the app's song playing on (6 of 6). The app's
  own turntable checks (`ttcheck`) 51 of 53 on both hosts - the two that fail (a held record's tail
  decaying 0.008 -> 0.0003, and Next during a coast back to speed) fail the same way on the unchanged
  2.0.0-player.35 at 8081.
- **Verified after the review**: 2390 Python tests (2388 passed, 2 skipped; 3 new in
  `test_lab_page.py`), pyflakes, tsc, the bundle (the app's two files byte for byte as before), and all
  46 sims (`lab` 92, 24 new; `app-rules` 280, 3 new; `deck`, `decksound`, `limiter` and `player`
  still with no diff). 49 mutations, one or more per fix (the smooth path's rest rule, set-off, run-on,
  let-go of place, speed bridge, the bridge's speed term, the take's join, the run's spline; the stamps'
  spline and the exact path's speed; the measured stretch; the switch's silence; the aliased square's
  note; the bench player's two ways of hearing a load; a motion's start; the check's line and file; the
  hide watch; the release's seek and play; the sampled reader's three rules; the stray floor; the bursts'
  edges and timing and the chord's notes; fourteen of Bench's wiring through app-rules; four of the
  stylesheet and its buttons), each file restored by hash: all caught - two only once remade or a check
  added (the stamps' mutation first touched only the knots C's span is read from, and was remade as the
  code it replaced; the exact path's speed without the stamps' slope survived until a check that the
  speed is its place's own rate of change). **In the real page** (this worktree's own deadwax on 8104,
  headless Chromium, real touch, clicks and keys): the builder's 29 of 29 on both hosts again - the
  device check's numbers within the baseline's ranges, but for the smooth path's - and 17 of 17 of the review's own on both (the
  label's mark; Record from a cold page; the song locked while it records; a recording the page was
  hidden through thrown away; a song changed while playing leaving Play and a still record; a comparison
  taking the focus; Space and 3 from the page itself; the chips by the arrows and Space on one; focus
  through the blind test; a short file refused; a check stopped part way saved and said; a check hidden
  mid-run waiting for Carry on and carrying on; no console errors); Info > Debug's link 6 of 6.
- **After a second review** (11 findings confirmed, two of them the same - every one fixed in the bench's
  own files, the docs and the sims; nothing the app plays changed, the engine guard and `deck.sim`,
  `decksound.sim`, `limiter.sim` and `deckVoice.ts` untouched):
  - **A motion on a playing song never played it again** (major): the runner kept the player object of the
    motion's start, and `useBenchPlayer` makes a new one each time `playing` changes - so after the take
    paused the song (the hand's own pause) the runner still read "playing", and a release the deck answered
    `play: true` (Steady 1x, the wobble: the motor back to speed in 50 ms or less) played nothing: the song
    silent and paused, the platter turning at 33 1/3 for ever. `runMotion(deck, () => playerRef.current,
    ...)` now asks for the player at the release, as Turntable reads it from the render the release comes
    in. The sim's fake player had changed itself in place, so it never showed; a check whose player is a
    new object after every toggle does.
  - **Play under a motion or the check** (minor): the transport wasn't locked - played under the hand, the
    song and the record's sound were heard together, the release sought the PLAYING song on over the coast,
    and the record stood still beside it after. Play is refused (aria-disabled) while `busy`, and `busy`
    now covers a motion from its tap (`preparing`, a ref against a second tap): before, a second motion
    tap while the first got ready started a second motion.
  - **The comparison's Play could die** (minor): a pause before the clips' start (20 ms after the tap) or
    on a context's clock not yet moving left a negative place, and every later `start()` threw - Play dead
    until From the start, a source and gain left connected each time. `position()` never reads before
    where it started.
  - **A recording nothing took was told as a stall of the page** (minor): Record pressed and the record
    not turned (or a turn already under way when it began) has no take, so nothing to hold the replay to -
    and that read as `NOT_HELD`. Numbers now say `taken`; `replayVerdict` tells held, stalled, untaken and
    unreported apart; a recording nothing took isn't compared at all (`NOT_TAKEN` in its place), and the
    guide's Record it again says all three.
  - **"Turn it for me" wrote its turn into Turntable's transform** (nit): the next hand's turn wrote over
    it, the record jumping back by the motion's whole turn. Kept in `--lab-motion-turn` on the bench's own
    box and turned by lab.css's individual `rotate` on `.app-tt-turn`, added to Turntable's transform.
  - **Smaller**: the worklet's blocks "0 of 0" (only the main-thread voice counts them - `runCounts`,
    `blocksLine` and `framesLine` in check.ts: "None (an AudioWorklet)", "Not known" on the main thread
    where the deck's counts went back); "The sound stopped while the page was hidden" left up after Play
    brought it back (`transportLine`); the guide's "with no filter at all" for B (it is band-limited, and a
    file or the noise read through a long windowed sinc); this file's sims list (app-rules' bench section,
    debug's Test bench row); and the bench player's place at a song change - 0 until the element holds
    the song rendered - which no check held.
- **Verified after the second review**: 2391 Python tests (2389 passed, 2 skipped; 1 new in
  `test_lab_page.py`), pyflakes, tsc, the bundle (`deadwax-ui.js` byte for byte as before), and all 46
  sims (`lab` 98, 6 new; `app-rules` 283, 3 new; `deck`, `decksound`, `limiter` and `player` still with
  no diff). 28 mutations, one or more per fix (the runner asking for the player of the start, and Bench
  handing it that; Play not refused, nor said to be, while busy, `busy` without the making ready, a second
  motion tap, the making ready never let go of; the room's place before its start, and by its old rule;
  the motions' turn not on `.app-tt-turn`, written into Turntable's transform again, and with no starting
  value; blocks counted for the worklet, its line a count, a main thread with no count called a worklet,
  the frames' longest gap always, and Bench counting and saying them itself; the transport's line left at
  "stopped", "stopped" with the page showing, and Bench's old rule; a null fit always a stall, `taken`
  always, untaken said as a stall, `tookTheRecord` on any message, Bench comparing a recording nothing
  took, the check's row always the stall; the bench player's place without its guard), each file restored
  by hash: all caught, each on its own check. The two earlier lists run again on this code: the first
  review's 49 all caught (its two release mutations re-aimed at the runner's `current`); the builder's
  53, 51 caught - three, as in its own run, by the sim stopping on an error where the deck asked nothing - and 2 not
  applied, their code (the smooth path's first form) rewritten by the first review and held by its own.
  **In the real page** (this worktree's own deadwax on 8109, headless Chromium, real touch, clicks and
  keys): 11 of 11 of the second review's own on both hosts - Play refused while a motion gets ready and
  while it turns; a playing song played again after Steady 1x and after the wobble; a hand's 20 degree
  turn after the motions moving the record 20.0 degrees; Record 10 s untouched saying "Nothing took the
  record" and comparing nothing; the comparison's Play and Pause back to back, then Play, playing; a
  hide's "The sound stopped" turning to Ready on Play; the check's blocks "None (an AudioWorklet)" on the
  worklet and "0 of 299" on the main thread; no console errors - and again the builder's 29 of 29 (the
  device check's numbers within the baseline, its file's blocks null on the worklet), the first review's
  17 of 17 and Info > Debug's link 6 of 6.
- **NOT verified**: James's iPhone and Mac - that WebKit decodes the bench's 24-bit WAV windows (believed:
  CoreAudio reads 24-bit integer WAV), the main-thread voice on the phone, the numbers his device gives,
  and above all whether A and C sound alike to him; Safari's ScriptProcessorNode stamps against the
  replay's timing (Chromium's move 1023 frames a block, which the grid follows); an iPad's or a phone's
  coarse targets under a real finger.
