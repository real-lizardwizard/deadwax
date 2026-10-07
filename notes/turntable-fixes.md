# The turntable's sound: the fixes since (.27 to .35)

The warble, the handover's echo, the kernel, the first turn, the counted clock, the recorder and the limiter.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

#### The warble (2.0.0-player.27)

James, on his iPhone with 2.0.0-player.24: "I can hear the song when I scrub, but it's as if there's an
extra sound effect added as well" ... "it just kind of sounds warbly, like theres a dragonfly sound on top
of the music while scrubing".

- **Not reproducible with a steady hand, which is all .24's checks ever turned.** Recorded off the voice in
  the real page, a hand at an exact 1x gave one clean tone on both hosts, whole-pixel touches included
  (everything else 54-70 dB down, no clicks). The flutter appears when the hand's speed CHANGES, as every
  real hand's does: a hand at 1x give or take 10% (1.3 Hz) with a finger's jitter (1.5 ms of time, 1 ms of
  the song's place) read with a rate error of 2.2% rms at 4-12 Hz and 2.2% at 12-45 Hz - the buzz - where
  the same jitter on a steady hand gave 0.36 / 0.27 (the offline bench: the real voice fed a hand of known
  speed, `/home/tokay/deadwax-scratch/ttmeasure/bench.cjs`).
- **The cause**: .24's fit was adaptive. A steady hand got long straight lines; a changing one fell back to
  a 0.1 s parabola read at its NEWEST end (20 ms of samples after it), and the end of a curve carries
  jitter several times over into its slope. The 40 ms position steering then made what jitter was left in
  the knots' PLACES into rate as well.
- **The fix** (lib/deckVoice.ts; deck.ts and the hosts unchanged):
  - ONE fit for every hand sample, steady or not: a tricube-weighted parabola by least squares over the
    samples within `FIT_S` (0.12 s) either side of it, as many after as have come (`SMOOTH_AFTER_S` 0.09) -
    CENTRED, so its slope is as quiet as a line's and it still follows a hand speeding up, slowing or
    turning back. The lines, `SPANS`, `AGREE` and the measured-jitter estimate are gone. `knotSteady` is now
    only "a hand sample fitted to its neighbours" (1) or not (0).
  - `HAND_DELAY_S` 0.12 (was 0.05): the voice plays far enough behind that every sample a knot is fitted to
    has arrived by the time it is played. On the main-thread voice its lag is on top: 163 ms (was 93).
  - The fit's curvature is each knot's change of speed (`knotAccel`), fed AHEAD of the 10 ms rate smoothing
    (`desired = v + SMOOTH_S * g + ...`), so the smoothing doesn't lag a hand that speeds up or stops dead.
    Between two fitted hand knots the speed is theirs, interpolated - the chord between their places is only
    jitter; where a knot was SAID (a take, a drive, a rest) it is the cubic's own slope, exactly.
  - `FOLLOW_S` 0.1 (was 0.04): the steering to the path's place is slow enough not to turn place jitter
    into pitch. (Three smoothing poles in a row were tried first: quieter still above 12 Hz, but three poles lag
    a hand that stops dead; the feed-ahead doesn't.)
- **Measured after** (same bench): the changing hand 0.55% (4-12 Hz) and 0.10% (12-45 Hz); steady 0.53 /
  0.10; at 120 touches a second 0.34 / 0.10. In the real page (headless Chromium against the dev stand-ins,
  the record turned by real touch events at 1x give or take 10%, whole pixels, 2 ms and 0.3 px of jitter,
  the voice's output recorded and its rate read back): the 15-45 Hz band 0.06% on the worklet and 0.07% on
  the main-thread voice (1.6% before, in the harsher 8 ms / 1 px case; 0.25% now there).
- **The cost, and it is James's to judge**: the record's sound trails the hand by 120 ms (163 on plain
  http) instead of 50 (93) - coasts, the motor, the wind-down and the handover as far behind too; a steady
  hand's slow wobble is a little higher than .24's 0.4 s lines gave (the 60 px grip at 0.5x: 83-97% of
  cycles within 3% where it was 93-98%, held at 80%). Smoothness and delay pull against each other: less
  look-ahead means the fit sits nearer the end of its curve again.
- **The pin** (`decksound.sim.cjs`, "THE WARBLE"): hands whose speed changes (1x give or take 10% at 1.3 Hz;
  0.4x to 1.6x and back), a finger's jitter (Gaussian 1.5 ms / 1 ms; whole pixels), both hosts and both
  clocks, through the REAL Turntable, deck, clock and voice: the rate's error against the hand's own speed
  by band - 12-45 Hz under 0.15% (0.03-0.11 measured), 4-12 Hz under 1.1%, above 45 Hz under 0.01%. And
  2.0.0-player.24's voice, frozen in `ui/test/fixtures/deckVoice-2.0.0-player.24.cjs`, in the same harness:
  a buzz of 0.8-3.3%, past 0.5% on every hand. Checks that encoded the old numbers were re-measured, each
  saying its before and after (the delay's literal; a drive settling in 250 ms where it was 150; the sound
  stopping `HAND_DELAY_S` short of a release; three missed samples now inside the delay).
- **How it was built**: the orchestrator found the cause and the centred fit; a background agent reworked
  the smoothing (the feed-ahead in place of three poles) and the sims, and was cut off by the session's
  usage limit before the docs; the orchestrator audited its diff check by check, re-measured, wrote this
  and shipped it without the usual four-lens review - James: "I want to make sure the turntable fix gets
  pushed before I run out of usage for the week". **A review pass is still owed.**
- **NOT verified**: James's iPhone - whether the dragonfly is gone under a real finger, how real touch
  jitter compares with the 1.5 ms / 1 ms assumed, and how 120 ms (163 over plain http) feels.

#### The handover's echo, and what the phone says (2.0.0-player.28)

James, after 2.0.0-player.27: "the turntable player just feels like it hangs a lot, especially when
scrubbing", "And it still seems like there's an extra sound added when scrubbing that isn't part of the
song", and "would this be better in an actual app vs web app?"

- **Measured, and NOT reproduced here** (headless Chromium over plain http, so the main-thread voice):
  with the turntable showing and the song playing the page's main thread is 95% idle, 90% while a hand
  scrubs back and forth, and kept every frame in a run with the CPU slowed 8x (a 4x run, on a machine busy
  with other jobs, dropped 5%) - the deck, the voice and Preact together are a few per cent. What the voice ADDS to real music at a steady 0.25x and 0.5x (the
  interpolation's images above the slowed song's top) is 35-48 dB below the song; a hand that stops is 40
  dB down within 150 ms. So neither the page's own code nor the interpolation is the hang or the extra
  sound, on this machine. What an iPhone does differently can't be seen from here: painting the record
  each frame, the main-thread voice under real touch handling, and how long its audio element takes to
  start again after a seek.
- **One real added sound, found and cut: an echo after every let-go.** The handover (the record's sound
  holding speed 1 until the song is really playing, then fading) judged "really playing" only as the
  player REPORTED its position - about four times a second - so the record's sound played on up to a
  quarter of a second over the song it had handed back to, and since .27 it is 120 ms (163) behind it:
  after a release the two were heard together for about half a second. `handOver`'s test is now also
  asked every FRAME the platter turns (`handoverJudge`, from `onFrame`, on `host.position()`): measured in
  the real page, the overlap after an 8x flick fell from about 520 ms to about 330 as the recording tap
  reads it (which is itself ~100 ms late). What is left is the 40 ms fade, the main-thread voice's lag and
  the 20 ms the song must have moved. NOT done: starting the record's sound where the song IS at a grab
  rather than `HAND_DELAY_S` behind it (a repeat of 120 ms as you take a playing record, and the same
  skipped as you let go) - that moves what `heardNow`, the seeks and a dozen pins mean, and wants the
  full review.
- **The phone says the rest: Info > Debug's "Turntable timing"** (`DeckHealth` on the deck's report,
  `turntableTimingRow` in lib/debugRows.ts), counted since the turntable last showed: how long the song
  took to come back after the last let-go of a playing record and how much of that was the record's run
  back to speed (`noteBack`, from the release - `letGo` - to the song's position moving past where it was
  sought); for the main-thread voice, blocks asked for AFTER they were due (`context.currentTime` past
  the block's `playbackTime` - a gap in the sound) and the worst; frames under a hand, those more than
  `SLOW_FRAME_MS` (34) after the one before, and the longest gap; let-goes after which the song hadn't
  started within the handover's wait; and times the context went 'interrupted'. A report is made as a
  hold ends and as the song comes back, not per frame.
- **What a let-go costs by design** (said to James, his to change): the record's run back to speed is 0.4
  s from still and about 0.8 s after a hard flick - the momentum he asked for - and the song starts only
  then, plus however long the browser takes to start an element it has just sought. Scrubbed in short
  strokes, that is a wait after every stroke.
- **Native or web** (answered, not built): the two things a native app would do better are exactly these -
  the sound on a real-time audio thread whatever the page is doing, and no pause-seek-play of a media
  element at every grab and let-go. The first is available to the web app too, over HTTPS: an
  AudioWorklet needs a secure page, and James's `http://` address is why his phone runs the main-thread
  voice at all.
- **Verified**: deck.sim (the fade at the next frame without the player's report, and once; the let-go's
  timing; frames under a hand with a 136 ms stall counted; counted afresh as it shows), debug.sim (the
  row's words in four states); mutations of the frame judge, the timing and the slow-frame count each
  caught. **NOT verified**: anything on the iPhone - which is what the row is for.

#### A digital artifact on top (2.0.0-player.29)

James, after .28: "it might be an artifact due to the digital nature of the speed variation that I'm
hearing, would that make sense? it's not just the audio slowing or speeding up, but a digital artifact on
top". It does, and it was measurable all along - .28's notes called it "35-48 dB below the song" and
moved on, which was the wrong reading: in a band where the slowed song has NOTHING, 35 dB down is heard.

- **A record turned slower or faster than the song is the song RESAMPLED, sample by sample**, and since
  2.0.0-player.14 the window was read with a curve through four samples (Catmull-Rom). That is a poor
  filter for it. Slowed, it leaves mirror IMAGES of the song's top above where the slowed song ends: a 15
  kHz tone read at a quarter speed came out as 3.75 kHz with a second tone at 8.25 kHz only 16.6 dB under
  it. Sped up, nothing keeps out what no longer fits: a 15 kHz tone at twice the speed (30 kHz, above
  anything a speaker is sent) FOLDED BACK to 18 kHz at full level. On real music (two tracks, 4 s each,
  through the real renderVoice against soxr's VHQ resample of the same stretch): at 0.25x and 0.5x the
  sound above the slowed song's top was 35-37 dB under the song on a funk track and 48 on a metal one; at
  2x and 4x the top bands carried 3-8 dB more than the ideal - the fold.
- **The fix** (lib/deckVoice.ts): the window is read through a KERNEL - a sinc under a Kaiser window
  (beta 7, about 70 dB), 12 zero crossings either side, tabulated at 128 entries a crossing and read
  between them (`state.kernel`, built in newVoiceState, since the voice's functions name nothing outside
  themselves). At the song's speed or slower it joins the window's own samples up and lets nothing above
  the song's top through (25 taps a sample) - all but the top 10-15% of the band: its cutoff is at the
  window's Nyquist frequency, and its transition band images that back just above the slowed top (2.0.0-player.35's
  review: at a 44.1 kHz window 20 kHz at -20 dB, 18 kHz at -68 - see "The record's sound never clips"); for a
  record turning faster it is STRETCHED by how many of
  the window's samples go by in one of ours, so its cutoff comes down by as much and what would fold is
  left out - up to 4x (97 taps), past which everything is a squeal anyway. Each sample's weights are made
  once (`state.taps`) and summed per channel, normalised by their own sum, so a steady level reads as
  itself whatever the stretch. Nothing else moved: the path, the delay, the smoothing and the DC blocker
  are .27's.
- **Measured after**: the tones - the image at a quarter speed 80.9 dB under the tone (16.6 before), the
  fold at twice the speed 74 dB under (0 before), levels kept within a dB (2 dB at 8x). The music - above
  the slowed song's top, 57 dB under the song on the funk track and 89-92 on the metal one; at 2x and 4x
  the top bands within 0.3 dB of the ideal; at the song's own speed the top octave is no longer dulled
  (16-22 kHz: -22.2 dB against the ideal's -21.8, where four points gave -24.1). In the real page the
  recorded voice has no clicks and the rate follows the hand as in .27 (15-45 Hz: 0.06-0.07%).
- **The cost**: the main-thread voice's renderVoice is 1.7% of the main thread while scrubbing on this
  machine (0.4% before), 10% with the CPU slowed 6x, every frame still kept. On the audio thread it is
  nothing the page sees.
- **The pin** (`deck.sim.cjs`, "a record turned slower or faster than the song adds nothing of its own"):
  the two tones above through today's voice and through 2.0.0-player.24's frozen one (the same four
  points) - the image more than 60 dB under, the fold more than 50 dB under, levels within 1 dB (3 at 8x);
  the old voice fails both.
- **NOT verified**: James's ears, on his iPhone - whether this was the "extra sound". The gaps a busy main
  thread would put in the sound over plain http are a different artifact, and Debug's "Turntable timing"
  (.28) counts them.

#### The first turn, and the mini player's tap (2.0.0-player.30)

James: "the scrubbing audio doesn't seem to load ever until after the first scrub". Two rules met to make
that so, each defensible alone:

- **The deck's audio context was made only by a tap on the turntable itself** (the record's click and
  release, the transport, the look button switching TO the turntable); the mini player's tap opening Now
  Playing only RESUMED one that existed. So with "Now Playing opens as: Turntable" - James's setting - the
  turntable opened with no context, every press was .11's (silent, the song playing on under the finger),
  and only the release's `wakeDeckAudio()` made one. App's `openSheet` now calls `wakeDeckAudio()` when
  `opensAs` is the turntable (read through a ref: the callback is made once) and `resumeDeckAudio()`
  otherwise - the tap is a gesture WebKit counts. app-rules' list of call sites gains it, and pins the
  condition.
- **Nothing was fetched for a paused song until the record was turned** (a cost rule from .14, pinned as
  "nothing fetched for a paused song"): the first press of a paused record was .11's, which asked for the
  window, and only the next turn sounded. `keep()` now fetches a paused song's FIRST window - the one for
  where it is, `unmet`: nothing covering its position - as the turntable shows and as it is sought
  somewhere the window doesn't reach, and nothing more (no refreshing ahead: a paused song goes nowhere).
  A playing song is kept covered as before.
- **Verified in the real page** (headless Chromium over plain http, Now Playing opened from the mini player
  straight onto the turntable, no tap on it): the window was fetched before the first press, playing and
  paused alike, and the first turn took the record and played the song at the hand's speed (1071 and 1059
  cycles, median 1.000). deck.sim pins both (the paused song's window on showing and on moving, once; a
  press meanwhile asking nothing more; the first press the deck's), app-rules the tap's condition.
- **Cost**: one 40 s window (about 2.5 MB of CD FLAC) fetched for a paused song as the turntable shows,
  where before it cost nothing until touched.

#### The main-thread voice's clock (2.0.0-player.31)

James, after .30: "It's not saying there are any blocks late, but it still has that digital buzz sound
when scrubbing". No late blocks ruled the main thread's load out, and .29 had ruled the interpolation
out. What was left was something the lab's Chromium does differently from an iPhone on plain http.

- **The cause** (read in WebKit's ScriptProcessorNode, then shown offline): the main-thread voice took each
  block's time from the event's `playbackTime`. Chromium stamps that on the audio thread, exactly;
  WebKit's `fireProcessEvent` stamps it on the MAIN thread, from the hardware clock as of whenever the main
  thread got to the block, quantised to the hardware buffer - so from block to block it jitters by up to a
  buffer (21 ms on an iPhone). The voice read its path by that clock: the path's time jumped a block at a
  time, the steering turned each jump into rate, and the record's sound warbled at the block rate and its
  sub-harmonics. Offline, the real voice fed a steady 1x hand with its block clock jittered as WebKit's
  would be: the rate wobbled 6.9% rms with 29% of cycles within 3% (9.2% and 14% at 45 ms of jitter);
  with the clock counted, exactly 1x. My late-block count (`currentTime - playbackTime`) never saw it: a
  late stamp is still ahead of `currentTime`.
- **The fix** (deck.ts `startScript`): the main-thread voice COUNTS its clock - each block one block after
  the one before, anchored on the first block's stamp. A stamp that agrees with the count (within
  `SCRIPT_STAMP_TOLERANCE_S`, 1 ms - Chromium's exact clock) is followed as it is, so the lab's samples are
  unchanged to the bit; a stamp a step away (WebKit's jitter) leaves the count holding, eased toward the
  stamp's running mean (`SCRIPT_DRIFT_EASE`) by at most `SCRIPT_SLEW_S` (0.02 ms) a block - a drift from
  blocks the page never rendered is taken up in seconds without a step the ear could find; a stamp a whole
  `SCRIPT_REANCHOR_BLOCKS` (3) away anchors the count again (a resume, a long gap). Lateness is still
  counted against the stamp. The worklet's clock was always exact and is untouched.
- **The pin** (deck.sim, "the main-thread voice counts its own clock"): the same record taken and turned
  back for sixty blocks, once with exact stamps and once with stamps late by up to 1.4 blocks and
  quantised to a block (the first exact, so both anchor alike): the rate read cycle by cycle strays 0.05%
  rms from the exact run's, every cycle within 1%; with the stamp followed as before it strays 9.2% rms.
  The mirror check (every sample a block gives equal to renderVoice at the block's own time) still holds
  under exact stamps.
- **NOT verified**: James's iPhone. This is the third candidate for one complaint, and the first the lab
  could not have shown: the two before it were real but not his. If the buzz is still there with this,
  the next step is a recording from the phone itself, not another guess.

#### A recording of the record's sound (2.0.0-player.32)

James, after .31: "yeah it still has a pretty digital sound", and "there doesn't seem to be much of a
difference between mac and iphone" - Chromium on his Mac, over plain http, sounds the same as the
phone. Four fixes (.27 warble, .28 echo, .29 kernel, .31 clock) were each real and measurable and none
was what he hears; the lab's recordings (synthetic hands, headless Chromium, `work/hang`, `work/tt`)
show nothing left. So, rather than a fifth guess: a recorder in Info > Debug that brings back what HIS
device plays, with everything that made it.

- **What it records** (`recordDeckSound(seconds)` in deck.ts): a ScriptProcessorNode of 4096 (`tap`) on
  the VOICE'S OWN NODE (`audio.node` - the AudioWorkletNode or the script voice's node, kept since this
  slice), connected on to the destination so the browser pulls it; every block's two channels copied
  with its `playbackTime`; every message the deck sends the voice meanwhile (`noteForRecording` in
  `post()`: the takes, every hand sample as it came, the drives, fades, stops - a window as its start,
  rate and length, never its samples); and everything the voice says of where it is (`heard()`, the
  one wrapper both hosts now call). `finishRecording()` after `seconds` (or when asked) disconnects
  the tap, interleaves the blocks as 16-bit PCM, base64s them and offers one JSON file through a blob
  URL: `{recording, version: 1, when, userAgent, secure, voice, sampleRate, delaySeconds (HAND_DELAY_S),
  scriptLagSeconds, clock (deckClockMapping), report (the last DeckReport), pageTimeAtStart, tapBlock,
  blockTimes, audio: {format: 'int16le', channels, frames, base64}, messages, heard}` -
  `deadwax-turntable-<voice>-<time>.json`, about 5 MB for 20 s. It refuses while one is running, and
  before the sound has started (no running context, no READY voice: "turn the record once first").
  Nothing is uploaded: the file is the user's to send.
  - **base64 in pieces of a multiple of THREE bytes** (`PIECE` 32766). The first cut's 32768-byte pieces
    were each padded with `=` by btoa, and 20 s decoded to 29 bytes too many - Node's decoder stops at
    the first padding, a browser's atob throws. The sim pins the exact decode past one piece.
  - `closeDeckAudio` clears `audio.node` with the voice, so a stale node can't be tapped.
- **The row** (`recordingRow` in debugRows.ts, 'The turntable' section after Turntable timing; the
  `DebugRow.action` a button or a download link InfoSheet draws in an `app-kv-action` dd): "Shows the
  turntable first" off the turntable; **Record 20 s** (`onRecord`, App's `recordTurntable` ->
  `recordDeckSound(20)`); "Recording the record's sound for 20 s - turn the record as you would"; then
  `20 s recorded: save the file and send it` with **Save the recording (5.0 MB)** - an `<a download>`,
  which `app-rules.sim`'s links-open-beside rule exempts (`linksOut()`), since a download opens nothing.
  App keeps `turntableRecording` from `onDeckRecorded`. The button is reached from Info > Debug only.
- **Verified**: deck.sim's "a recording of the record's sound" (refused before the sound, the tap's
  node and connections, 'recording' then 'saved' with the name and size, the file's fields, three
  tapped blocks decoding to exactly their 49,152 bytes, the hand samples and reports carried); the
  piece-size mutation (32768) fails the decode check. In the real page over plain http
  (`work/hang/record.cjs`, headless Chromium as `deadwax.test`): Record 20 s during an 8 s synthetic
  scrub gave a 5.0 MB file of 958,464 frames (19.97 s), 234 contiguous 4096-frame blocks, the scrub's
  sound at -27 dBFS for 8 s and digital silence either side, 493 hand samples, 35 drives, 600 reports.
- **How to read one** (for the file James sends): decode `audio` (int16le, interleaved) and listen;
  the rate the voice played at is in `heard[].rate` 30 times a second, the hand in `messages` of type
  `hand` (`at` in song seconds, `time` on the audio clock); replay the messages through the real
  `lib/deckVoice.ts` (newVoiceState/voiceCommand/renderVoice at the script host's block timing) and
  compare with the recorded samples - a difference is the host or the device, agreement is the voice
  itself. `work/hang/recording.json` is the lab's own for comparison.

#### The record's sound never clips (2.0.0-player.35)

James, after five fixes (.27 warble, .28 echo, .29 kernel, .30 first turn, .31 clock): "yeah it still has a
pretty digital sound", "there doesn't seem to be much of a difference between mac and iphone". .32's
recorder brought back a file from his Mac (Chromium, plain http, so the main-thread voice, 44.1 kHz, 16 s of
one long scrub, 985 hand samples, no block late) - the session scratchpad's `ttmeasure/james/rec1.json`, with
the orchestrator's scripts beside it - and the spec is `uplan/slice-limiter.md`. What the file showed:

- **The voice did exactly what the lab's does**: his messages replayed through the real `lib/deckVoice.ts`
  (`replay.cjs`, the script host's lag, applied at the next block) match the 500 reports his browser's voice
  made to 0.001 ms and 0.00007 of rate. The speed is clean (0.13% above 20 Hz); nothing past the slowed
  song's top but the clips (`above.py` looks from 22.05 kHz x |speed| x 1.08 + 600 Hz up: -58 dB overall,
  mostly the clips, -79 dB in a median slowed frame); no gaps, repeated blocks or block-edge clicks. **Not
  quite "no imaging", though** (review): the kernel's cutoff is at the window's Nyquist frequency, and its
  transition band images the top 10-15% of the song's band back just above the slowed top - through the
  kernel, relative to the tone, at a 44.1 kHz window 21 kHz at -9.5 dB, 20 kHz -20, 19 kHz -35, 18 kHz -68
  (at 48 kHz: 22 kHz -17.7, 21 kHz -30, 20 kHz -50); the same at every speed, and at 0.5x the images of 20-22
  kHz land under that line, where `above.py` can't see them. In rec1's steady slowed frames the band from
  the slowed top + 300 Hz up to the line holds about -86 dB per bin of the frame - about 12 dB under the
  song just below the top, 25 dB over the floor past the line, and the kernel's images predict it to within
  2 dB (`work/verify/img/`): very likely inaudible on his song (bright: its 20-21 kHz 37-41 dB under its 1-4
  kHz). Left as it is - moving the cutoff under the window's Nyquist changes what is heard, James's call -
  and 2.0.0-player.29's "nothing above the song's top let through" corrected below and in renderVoice.
- **The output clipped**: 144 samples at exactly full scale over 16.5 s of sound (38 left, 106 right), on
  the loudest drum hits, at every speed - 0.2x to 1.5x, backwards too, 1x included. Counted as runs: 84
  channel by channel (23 left, 61 right; 1-13 samples each, 62 of them a single sample), 81 with the
  channels together - which come in **15 bursts** (runs within 50 ms joined; 8 of them only 1-4 samples at
  full scale), about one a second, one per loud drum hit: not "five a second", which is runs read as
  events (review). 10 of the 15 came at 0.8x or faster, either way, where the song's own treble is there to
  mask them. Slowed frames (0.05-0.9x: the only ones the method can look into, 41% of the sounding frames;
  the median speed was 0.94x) holding a clip carried a median -53 dB above the song's possible top, against
  -81 dB in frames without: in the slowed frames the clipping was the only non-song sound found. Whether it
  is the "digital sound" James hears is for his ears (NOT verified, below). Every lab measurement compared
  floats, where nothing over 1.0 is ever cut - which is why none showed it. Normal playback doesn't suffer it:
  the element sends the song's own samples.
- **Why it went over** (measured here, with the limiter out of the way): the kernel, reading between the
  song's samples, recreates the song's own intersample peaks and no more (its peak within -0.2 to +0.06 dB of
  the song's true peak over the stretch read, on every stand-in at 1x); **the 10 Hz DC blocker adds the
  rest**: a median +0.57 dB to the peak along the hand and at 1x over the stand-ins here (+0.51 at 1x and
  +0.71 along the hand over the transparency review's), up to about 3 dB on a hard-clipped master (its phase
  turn on the bass lifts the peaks that sit on it, and not only below 20 Hz: above it the same moment still
  peaks about 2 dB up). The most found: +2.9 dB to the whole run's peak on Harmful or Fatal +6 dB hard-clipped
  along his hand (+3.1 within 10 ms of the peak), at 0.16x between two of his reversals - where, on that
  master, the limiter turns the sound down deepest anywhere on his path, 3.7 dB (2.1 on its +9 dB alimiter
  master) - and +2.1 dB locally at 1x on Club Diver hard-clipped (review; `work/limiter-fixer/dclift.py`
  over `work/review-transparency/out/`). Not changed: it is what silences a record held still.

What was built: **a lookahead peak limiter at the end of `renderVoice`**, after the DC blocker, inside the
four self-contained functions (its rings made in `newVoiceState`), so both hosts have it by being the same
functions.

- **By construction**: each sample's NEED is the gain that brings its loudest channel to the ceiling (1 for
  most), made `SAFE` (1 - 2^-30) under it; a running minimum of the need over [n - D - H, n] (D the
  lookahead, H the hold, in samples) - a monotonic queue, each sample pushed and popped once at most,
  constant time however long the window; that minimum taken at once going down and brought back up over
  `RELEASE_S` (never above the minimum: the envelope is under it by induction), snapped to exactly 1 within
  2^-24 (a step a 32-bit float can't tell from 1); then two running-sum boxes whose lengths add up to D + 2 -
  a triangle - so the gain written with sample n - D is an average of envelope values each made with that
  sample's need in its minimum, never above it. The gain written is also held to that sample's own need
  (rounding only) - **and floored at 0** (review): the boxes' running sums carry rounding of about 1e-16 of
  the values near 1 they held, so a sample whose need is smaller than that - some 1e16 times full scale,
  nothing a decoded window holds - left a sum, and the gain, a hair under 0, and a huge sample times a tiny
  negative gain is any size (1.47 at 1e16, 1241 at 1e20, up to about 1e23 at 3.4e38, in the review's
  `work/review-correctness/h7.cjs`). With the gain between 0 and the sample's need, what is written is at
  most its loudest channel times its need, the ceiling; and the ceiling is a 32-bit float, so a 64-bit value
  under it stays under it in the output's 32 bits (rounding is monotonic). deck.ts reads a reported lowest
  gain of 0 or below as 120 dB down (`DEEPEST_GAIN_SAID`), so Debug never prints Infinity or NaN. One gain
  for every channel. A non-finite sample (nothing decodeAudioData makes) goes in as 0. Counted in samples,
  so it holds at any rate; the rings (1024, and 8192 for the minimum's queue - powers of two, indexed by
  mask) cover the lookahead and hold at 192 kHz, and past that both are only shorter in time. A box's
  running sum is made again from its values once a ring and set exactly when every value is 1, so it never
  drifts; at rest (need 1, envelope 1, both boxes all 1) a short path writes the same samples.
- **Transparent first**: wherever its gain is exactly 1 the output is the voice as it was, bit for bit, only
  later - `limiter.sim` holds that against the voice as it was (`fixtures/deckVoice-2.0.0-player.29.cjs`) at
  44.1-192 kHz, through a swinging hand and a coast: on a chord peaking about 3.5 dB under the ceiling, and
  (second review) the same chord turned up until the voice as it was peaks at 0.99999 of the ceiling in 64 bits,
  every report saying nothing held. With only the first, a limiter acting a little early - from -2.9 dBFS,
  a "gentler" knee - passed every sim, since nothing else there lies between the chord and the ceiling.
- **The numbers, each by measurement** (the scratchpad's `work/limiter-builder/`: stand-in masters made from
  six incompetech tracks - peak-normalised, +3 dB into ffmpeg's alimiter "mild", +9 dB "lim", and +6 dB
  hard-clipped - cut to his window and read along his own hand, `replay2.cjs`, and played at 1x a fraction of
  a sample off the song's samples):
  - **`CEILING` -0.5 dBFS** (`VOICE_CEILING`, 0.94406086 as a float). A sample-peak ceiling can't bound the
    true peak, so it was chosen so that the limited sound's own intersample peaks stay where plain playback's
    are: at -0.5 every peak-normalised master played at 1x stays under 0 dBTP (-0.19 to -0.50), and the
    limited sound's true peak is at or under the song's own on every peak-normalised and mild run but two -
    Pump's two masters along the hand (sped to 1.7x, the top crowding the Nyquist frequency: +0.90 against the
    song's +0.15 peak-normalised; still +0.40 at -1 dBFS). At -0.3 a third run is over, at -0.1 seven. The
    cost of the half decibel: on the peak-normalised masters the sound is turned down by more than 0.1 dB 7.3%
    of the time along the hand and 12.5% at 1x (median; -0.1 would be 1.6% / 2.3%, -1 dBFS 21% / 31%).
  - **`LOOKAHEAD_S` 1.5 ms, two boxes**: the gain's energy above 1 kHz (what would spread a partial into new
    bands) is -62 dB of its variation along the hand; one box would be -51, 1 ms -47, 0.5 ms -37, and 3 ms
    buys only 5 dB more for twice the latency. **That measure can't see what the attack does to a slowed
    record's bass** (review, under "Transparency where it acts"): a 1.5 ms edge times a 20-odd Hz wave near
    full scale is new sound at 100-500 Hz, which a 5 ms lookahead cuts by two thirds - for 3.5 ms more
    latency. Left at 1.5 ms; the trade is James's call.
  - **`HOLD_S` 20 ms, `RELEASE_S` 60 ms**: with no hold, a steady 25-50 Hz tone 1 dB over the ceiling had its
    gain move every cycle - harmonics at -49 dB (release 60 ms; -37 at 10 ms, -61 at 250) - where clipping the
    same tone at full scale leaves -37 dB at 50 Hz and -34 at 100 (at 25 Hz the DC blocker keeps it just under
    full scale). With a 20 ms hold (longer than half a 25 Hz cycle) none: below -140 dB from 25 Hz up, -86
    at 20 Hz; a 30 ms hold would cover 17 Hz, for more time turned down. Below about 20 Hz - a slowed record's
    deepest bass, a 40-60 Hz note at 0.2-0.3x - half a cycle outlasts the lookahead and hold together (21.5
    ms), the gain follows each crest, and the tone is shaped a little (review): 0.45 dB over the ceiling,
    where the voice as it was played it clean, harmonics -42.8 dB at 8 Hz, -45.6 at 10, -48.5 at 12, -54 at
    15, -59.5 at 17, odd ones, at 24-85 Hz (`limiter.sim` pins them). A 50 ms hold would make 10-15 Hz clean,
    at the cost of more time turned down: under -0.5 dB 43% of the time on Cool Rock's +9 dB master at 1x
    (31% now), 10% on Harmful or Fatal's (6.5%) - left at 20 ms. `limiter.sim` pins the hold both ways
    (second review: the release check alone let a hold up to about 28 ms through - a 25 ms hold passed): held at
    its lowest for 20 ms, and 2 ms after the hold the gain already 2% of the dip back up (a hold 1 ms longer
    leaves it at its lowest there); and the release's own rate, the dip left falling by e between 60 and
    120 ms after the hold, to 1% (the envelope's deficit falls exactly exponentially, whatever the hold).
    On the music: 7.3% of the time
    turned down >0.1 dB (5.7% with no hold), a mean of 0.029 dB, and the gain's energy above 20 Hz -12.9 dB
    of its variation (-10.4 with no hold, -14.9 with 30 ms and 120 ms).
- **The latency is kept, not taken out of the path's delay**: 1.5 ms, so hand to sound is 121.5 ms (about
  165 on the main thread). `HAND_DELAY_S` is the hand's fit's look-ahead and its margin (SMOOTH_AFTER_S and
  delivery); shaving 1.5 ms off it would cut that margin, and would move every pin held to positions (the read
  head, the heard reports, the handover, the wind-down, the release) for a difference a hand can't feel - the
  time line is drawn a frame at a time (16.7 ms). The reports still say where the read head is; what is heard
  of it is 1.5 ms later. Every existing pin holds unchanged (deck.sim, decksound.sim) - but deck.sim's list of
  a report's keys, which gained the limiter's three, and the recorder file's version (2), each on purpose.
- **Said in Debug**: each report (`voiceReport`, both hosts alike) carries what the limiter did since the
  last: `held` (samples over the ceiling it brought down), `peaks` (runs of them) and `lowest` (the lowest
  gain it wrote), counted afresh after each. deck.ts's `heard()` adds them into the health (`peaksHeld`,
  `samplesHeld`, `deepestHoldDb`, reset as the turntable shows), and **Turntable timing**'s note says "Peaks
  held under full scale: 36 since it showed (65 samples), the deepest 1.4 dB" - what Club Diver
  peak-normalised along his hand gives (none, or "under 0.1 dB" for a tiny dip; nothing until there is a
  voice). The health reaches Debug as a hold ends, as it always has - **and again once the voice has played
  the rest** (second review): it plays the hand's path `HAND_DELAY_S` behind (and the script lag more on the main
  thread), so the limiter's counts for a hold's last 120-165 ms, and for a whole coast, come in after the
  report the release makes, and a paused record has no later report of its own - a quick flick of a paused
  loud record read "none" or a handful while the voice held thousands of peaks through its coast, and went on
  saying so. deck.ts's `heard()` marks the health moved when a report brings a peak held or a dip deeper than
  any so far (not a gain still coming back up after one: that lasts up to a second after a deep dip, and
  would report every quarter second for nothing), and `onHeard` reports once the deck no longer steers the
  sound (`steering()`: no hand, no sounding plan, no handover) and `HEALTH_REPORT_MS` (250) have passed since
  the last report. Never while it steers: a report re-renders the page, which under a hand on the main
  thread is the voice's own time. Only the limiter's counts: a late block is the page being busy, and
  reporting for it could make more of them. A peak counted is a run of samples over
  the CEILING, not only over full scale: in the replays 5-38% of them reached full scale (about a third on
  the mild and limited masters), so the count is higher than the clips the voice as it was would have made.
- **The recorder** (version 2) adds `blockPeaks` - each tapped block's loudest sample, either channel, as a
  float, before the 16-bit file clamps it - and `limiter: {ceiling, lookaheadSeconds}`.
- **Cost**, renderVoice in 1024-sample blocks at 44.1 kHz, one version per process, the median of five runs,
  three times over. On headless Chromium's main thread (`benchpage/bench-page.cjs`: a page of its own per
  version, a synthetic loud window with a third of its samples over the ceiling, and the same 10 dB down):
  +25-28 ns a sample at 0.5-1x on the loud window (172 to 199 at 1x, +15%), +15 at 2x, +12-13 on the quiet one
  (the limiter at rest, +8%); a block at 1x takes 0.20 ms of its 23.2 ms (0.18 before). Under Node 20 on the
  hard-clipped Club Diver: +12 at rest, +24-32 at 0.5-1x, +31-36 at 2x.

Evidence (all in `work/limiter-builder/`):

- **His recording replayed** over the stand-ins (`summary.py`, `events.py`): no sample over the ceiling on
  any of 22 masters along his hand or at 1x, and none at full scale, where the voice as it was put up to
  67,378 samples at or over full scale along the hand (172,318 at 1x) - runs of them (either channel) 0.7 a
  second on Club Diver peak-normalised, 10 on its mild master, hundreds on the hard-clipped ones, and in
  bursts (runs within 50 ms joined) 0.2 and 3.7 a second: his song's 81 runs in 15 bursts (4.9 and 0.9 a
  second) between the two (`work/limiter-fixer/bursts.py`). Above the song's top in slowed frames that
  clipped, the limited sound has exactly what the unclipped sound has (within 0.1 dB, every master), where
  the clipped one added 1.3 to 34 dB; on the peak-normalised masters that is within about 5 dB of the clean
  frames (the louder frames carry a little more of the voice's own floor). How it turns the sound down
  there: on the peak-normalised masters 0.4-3.6 dips a second below -0.1 dB, 73-127 ms long (median; p95
  140-430 ms), the deepest 0.7-1.35 dB, peaks brought down a median 0.2-0.8 dB; on the mild masters the dips
  run together on the dense stretches (seconds at a time, ~1 dB).
- **At 1x with no hand** (the song itself): the same, 0.9-3.9 dips a second on the four peak-normalised
  masters that reach the ceiling often (the other two once or twice in 40 s), the deepest 0.4-1.6 dB.
- **Transparency where it acts** (`transp.py`): measured as the error's energy against the song's own in
  each third-octave band (100 Hz-16 kHz) of every 46 ms frame that went over FULL SCALE, along his hand and
  at 1x, since an error far under the music in its own band is masked by it. There the limiter's error is
  the song at another level: the same ratio in every band, 20 log10 of the dip (median worst band -19 to -24
  dB on the peak-normalised and mild masters, p95 -4 to -20 dB); clipping's is new sound in the bands where
  the song is quiet - worst band p95 +13 to +40 dB along the hand on every hard-clipped and limited master
  but Devastation and Revenge's (+4, its error spread wider: 13 bands within 20 dB of the song). Where its
  gain is 1 (65% of the samples replayed on Club Diver peak-normalised along the hand) it is the unlimited
  sound, bit for bit. **The exception, found in review: a slowed record's bass under the attack.**
  `transp.py` never looked at frames between the ceiling and full scale, nor at a record held at a steady
  slow speed. Dragged at a steady 0.25x, a very loud, bass-heavy master puts the slowed bass - a 20-odd Hz
  wave near full scale, over the ceiling but under full scale, which the voice as it was played clean -
  under the gain's 1.5 ms attack, and the attack's edge times that wave is new sound at 100-500 Hz, level
  with the slowed song there and 20-33 dB more than a plain level change would leave. Over the masking, by
  the transparency review's spread-masking estimate (`work/review-transparency/regress.py`, the gain above 5
  Hz): 40 of Breakdown's 1238 limited frames (worst +17 dB), 10 of Cool Rock's 735 (+8), 3 of Harmful or
  Fatal's 135 (+4.7), all three +9 dB into alimiter; by a PEAQ-flavoured model that counts the 22 Hz wave as
  a masker (`work/verify/splatter/peaq.py`, full scale 92 dB SPL), 3, 0 and 0 (+5 dB, at 503 Hz) with a
  noise masker's offset, 51 and 19 (+17.7) with a strict tonal one. None on the peak-normalised masters at
  0.25-0.5x, none at 1x, and 1 frame in 24 runs along James's own hand. A 5 ms lookahead cuts it to 12
  (+6.8) and 4 (+2.8), for 3.5 ms more latency; a 50 ms hold changes little (28, and the worst still +17):
  it is the attack's edge, not the release. Rare, small, and how often it is audible depends on the model;
  left at 1.5 ms (the lookahead bullet above).
- **In the real page** (headless Chromium, real touch input, a 14 s scrub at 0.26-1.74x through Info > Debug's
  recorder, against a copy of the stub library with Club Diver +9 dB into alimiter added - the builder's own
  instance, deadwax on 8104 and a stand-in Navidrome on 4544): over plain http (`deadwax.test`, the
  main-thread voice) and on localhost (the worklet), the file's loudest 16-bit sample -0.50 dBFS, no sample at
  full scale, every block peak at or under the ceiling (the loudest exactly it), and Debug's row "Peaks held
  under full scale: 1889 since it showed (8516 samples), the deepest 2.4 dB" (worklet: 1878, 8630, 2.5 dB) -
  what the file's own report says too (the worklet's, made a moment before, one peak fewer). Its hand
  replayed through the voice as it was over the same FLAC (`replay2.cjs`; the replay through today's voice
  matches what the page recorded, correlation 0.9996): 804 clips, 57 a second. **The late counts, after the
  second review** (`work/limiter-fixer2/latecount.cjs`, its own instance on 8104 and 4544 over a copy of the
  loud masters): Club Diver +9 dB paused from the transport, Debug read, the recorder started, one quick flick
  of the paused record into a coast, Debug read again 23 s later - its count rose by exactly what the voice's
  reports in the file add up to, 171 over plain http and 179 on localhost, every one of them reported after
  the hand's last sample; the same over plain http with the fix's report taken out rose by 35 of 171 (an
  incidental report caught some). The files' loudest sample -0.50 dBFS, none at full scale.
- **Also measured, not changed** - how much of a slowed record is deep bass: in his recording 40% of the
  energy is below 60 Hz at 0.3-0.6x (-4.0 dB), 12% at 0.6-0.9x, 6% at 1x. A second-order high-pass at 30 Hz
  would take 0.68 dB of a slowed record's sound (20 Hz: 0.25, 40 Hz: 1.19) and 0.05 dB of his song at 1x - but
  0.48 dB of Club Diver's sub-bass at 1x. Only 6.5% of a 0.3-0.6x record is below 30 Hz, so a gentle high-pass
  gains little where it would matter to a speaker; the case isn't overwhelming, and James hasn't said whether
  he listens on speakers or headphones.
- **Sims**: `limiter.sim.cjs` (new) - the guarantee (six full-scale windows x 17 rates from -24 to 24 x both
  hosts' paths; takes, fades, stops, a hand, windows swapped mid-block and one running out at 22.05-768 kHz in
  blocks of 1024, 128, 333 and 1; NaN-free; and, since the review, windows of +-1e16, +-1e20 and +-3.4e38
  under the ceiling with every report's lowest gain between 0 and 1), the transparency and the lookahead's
  latency at four rates (and, since the second review, right up to the ceiling), the attack's shape (never a
  step; a triangle's bend), the hold (no shorter and, since the second review, no longer) and the release
  (and its own rate), both channels alike, steady low tones turned down unshaped from 25 Hz up and, below 20 Hz, shaped no more than
  measured (8-17 Hz, each under its bound), the reports' counts, and self-containment; `deck.sim` - the
  report's keys, a loud window through the real deck and main-thread voice under the ceiling with its counts
  reaching the health exactly and counted afresh, a reported lowest gain of 0 or below read as 120 dB, and
  the recorder's block peaks and version - and, since the second review, frames and blocks on one clock: a
  60-frame hold reporting nothing, a cancelled hold's late counts told 250 ms or more after its release, a
  paused loud record's five-frame flick and coast told whole once the coast is over (4204 peaks held,
  where the report its release made had none of them), nothing more once the counts stop, and a deeper dip
  alone told; `debug.sim` - the row's
  words. Mutations (the scratchpad's
  `work/limiter-builder/mut/`, and after the review all of them again on the final code with the review's
  fixes added, `work/limiter-fixer/mutate.py` and `mut.log`), each file restored byte for byte (by hash): 33
  of 34 rules caught - the review's five (the gain not floored at 0; the deck taking a lowest gain of 0 or
  below as it is, or saying it as 240 dB rather than 120; a 15 ms hold and a 40 ms release, which shape the
  tones under 20 Hz past their bounds) and the builder's 29: the ceiling raised and above full scale, the
  lookahead, the minimum's window (caught by the smoothness check: the holding to each sample's need kept
  the guarantee), no hold, the release's time and none at all, no snap to 1, one box, the boxes a sample too
  long (with the holding to the need out too), the delay a sample short, one channel deciding, the rest path
  taking a new peak, NaN let through, each count, the reports not counted afresh, the report without its
  counts (by the type check, before the sim ran), the deck's health (peaks, deepest, reset), the recorder's
  block peaks (one channel; missing) and version, and Debug's three wording rules. The survivor is an
  equivalent mutant - the average not set to exactly 1 when every value in its box is, where the box's sum is
  already set to exactly its length then, so the average comes out 1 anyway - and three backups change no
  sample by design: the `SAFE` margin (rounding only, and only in 64 bits: a 32-bit output can't go past a
  32-bit ceiling by a 64-bit rounding); the rest path (an optimisation: the same samples); and the sums remade
  once a ring - as a box's exactly 1 (the reset sum and the average together), which the rest path gives too.
  The holding of each gain to its sample's need was one of them until the review: on a window far past full
  scale the boxes' rounding can carry the gain over a tiny need as well as under 0, and the review's case
  catches it out - it is the upper half of what the floor is the lower half of. Replayed over the builder's
  22 masters along his hand and at 1x, the final voice writes the very bytes the builder's did (44 of 44,
  `work/limiter-fixer/replay/`): the floor never acts on anything a decoded window holds. **The second
  review's** (`work/limiter-fixer2/mutate.py`, `mut.log`, each file restored by hash): 20 of 20 caught - the
  late counts (no report from `onHeard`, a report while steering, no throttle, a 50 ms one, the health moved
  by any gain under 1, a report not clearing it, a held count or a deeper dip not moving it, the report's
  time not kept), acting before the ceiling (from -2.9 dBFS - the review's - and -1.9, from 0.999 of the
  ceiling, a soft knee from 0.9), and the hold and release (25, 21 and 30 ms holds; 55, 58, 62 and 66 ms
  releases). Two first got past - a 50 ms throttle (the check read the constant it was testing) and a
  deeper dip alone - and gained the checks that catch them. The first two lists re-run on the final code
  (`work/limiter-fixer2/previous.py`, `previous.log`, on a copy of the worktree): 33 of 34 caught again (the
  deck forgetting the deepest rewritten for `heard()`'s new shape), the same equivalent survivor, and the same
  backups (holding to the need caught; the other three change no sample).
- **Verified**: 2373 Python tests (2371 passed, 2 skipped; none new - the change is the page's), pyflakes,
  tsc, the bundle, all 45 sims (`limiter` 30 new; `deck` 272, 13 new; `debug` 98, 3 new). The engine guard is
  empty, and `player.sim.cjs` untouched. The fixture `deckVoice-2.0.0-player.29.cjs` is tsc's compile of
  `lib/deckVoice.ts` as it was at 71c2f24, byte for byte under its header (checked).
- **NOT verified**: James's ears, on his Mac and iPhone - whether the clipping was the digital sound he
  hears, and all of it (a recording made with this build says, through its block peaks and Debug's count):
  it came in 15 short bursts about a second apart, 10 of them at 0.8x or faster, and was the only non-song
  sound found in the slowed frames - the only ones the method could look into - so a sound elsewhere isn't
  ruled out; the iPhone at all; his own master (the stand-ins are other music, made as loud or louder at the
  top). **For James to decide**: a 3-5 ms lookahead (above: less of the attack's 100-500 Hz on a slowed,
  bass-heavy master, for 1.5-3.5 ms more latency), and moving the kernel's cutoff a little under the
  window's Nyquist frequency (no images of the top octave, for a little of the song's own top).
