# The turntable's sound: the fixes since (.27 to .35, and .40)

The warble, the handover's echo, the kernel, the first turn, the counted clock, the recorder and the limiter - and
less delay between the hand and the sound (.40).

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

#### Less delay between the hand and the sound (2.0.0-player.40)

James (2026-10-08): "I do want to make sure that the delay in the turntable is reduced when scrubbing". He
listens on Bluetooth earbuds (150-250 ms of their own, which no page can reach), mostly on his iPhone, over plain
http - so his iPhone's Safari and his Mac's Chrome both run the main-thread voice - and he has confirmed, blind,
that the record's sound is as clean as an ideal turntable's, so nothing here may make it less clean. The spec is
`uplan/slice-delay.md`; the research it rests on is in `work/delay-chain/`, `delay-estimator/` and `delay-blocks/`
(summaries there). `HAND_DELAY_S`, the fit, `SMOOTH_S`, `FOLLOW_S`, the kernel and the limiter are as they were -
the estimator research found the fit already uses 75-84 of its 90 ms look-ahead, and the best estimator saved
only 10 ms. Nothing heard changes but WHEN - but for the hand's few pixels before a quick grab's take, which
were dropped (the record's place, and so where a let-go lands, counted from the crossing) and are now the hand's
like any other (the record's place counted from the press, as the face's turn always was, and a flick let go
within 90 ms of the press read at its speed over them too). The engine files have no diff.

- **A quick grab is heard from the press** (deck.ts `touched`, `takeOver(time, quick)`, Turntable's `onMove`).
  A press becomes the deck's take only past `TAP_SLOP_PX` (8 px) - it may yet be a tap - so a press that turns at
  once was heard from the slop's crossing: 35 ms after the press at 1x, about 70 at 0.5x, 94 at 0.25x. Now the
  deck keeps every sample inside the slop (`touched`: time, turn, offset - nothing sent, nothing moved), and a
  take by moving is stamped at the PRESS's own moment with the record where it was then, every sample since
  posted after it, in order; the voice, `HAND_DELAY_S` behind, still has them ahead of it. Where the record was:
  a still record's place; a coast's, by its plan at the press (and its voice's knots after the press let go of
  by the hand's first sample, as ever); a playing song's, its position less its speed times the time since the
  press - so the take is exactly where a take at the crossing would have the voice start, and the join with the
  song is as it was (the song still plays on under the slop - the tap's price - and pauses at the crossing). A
  press older than the voice can still be told of - by the time the page handles the move - is taken from its
  oldest sample within reach: `TAKE_BACK_S`, `HAND_DELAY_S` less 20 ms on the worklet (it applies a message up
  to 9 ms after its moment by the page's clock, delay-chain's measure), `SCRIPT_TAKE_BACK_S`, less 5 ms on the
  main thread (its lag holds what it is told two blocks on). Taken there, a still record is at the hand's place
  then; a MOVING one - a playing song, a plan the record follows (`planHasRecord`) - where it had got to on its
  own by that sample (the song's line there, the plan's place), the anchor that less the hand's turn by then,
  since the voice may already have played it on past the press (after review, below). So the join, and a
  coast's path, are as a take at the crossing had them, whatever the press's age, and a slower start keeps the
  part of the slop's delay that is out of reach. Turntable no longer resets the offset at the crossing - the
  record's place counts from the press - and the hand's samples since the press count toward the let-go's
  speed. The face carries straight on at the crossing (after review): the deck's angle is the platter's as the
  slop is crossed less the hand's turn so far (`angleNow() - turned`), since Turntable draws the deck's face
  inside the hand's turn since the press from then on - before the crossing the face is the platter's (a tap
  must leave it as it was), after it the hand's turn since. A tap stays a tap (nothing taken, sent, paused or
  moved), and a press that rests `HOLD_MS` is taken as it was.
  Re-based (each said in its sim): turntable.sim's flick sought from the press (56 degrees, not the 36 after the
  crossing) and its fake player's position played on under the slop; decksound's read-head check counting from
  the press for a quick grab, its stamped-samples check (the take at the press, the slop's samples after it) and
  its count of knots under the hand (31: the press and 30 samples, where the crossing's sample was sent twice).
  And, after review, deck.sim's face checks of a quick grab (a paused record, one playing at 0.5x and 2x): the
  face as drawn carrying straight on from the frame drawn at the crossing, where they had pinned it at the
  platter's angle at the press.
- **The main-thread voice's block follows the hardware** (deck.ts `scriptBlockFor`, `startScript`): 512 frames
  (`SCRIPT_BUFFER_SMALL`) where the context's `baseLatency` times its rate is 512 frames or fewer (within 2%;
  Chromium says exactly 128, 512 or 1024), 1024 where it is more or isn't said - and always 1024 on Apple's
  engine (`isAppleEngine`: `navigator.vendor` "Apple Computer, Inc." or a prefixed `webkitAudioContext`, so Safari
  on a Mac and every iPhone browser), whose `baseLatency` is its 128-frame render quantum whatever the hardware
  runs (WebKit's `AudioDestinationResampler::framesPerBuffer()` is its render bus's length, `renderQuantumSize`):
  it can't tell, so it keeps 1024 (a second review's finding; the first build read 128 there and started every
  Safari in blocks of 512). The lag stays `SCRIPT_LAG_BLOCKS` (2) blocks of
  whatever size: 21.3 ms where it was 42.7 - 142.8 ms from the hand to the sound in all, where 1024 gives
  164.2. The node is given up for one of 1024, at the voice's next silent moment (faded or stopped and heard no
  more, nothing held for it, no recording under way - its state and the window carried over, the next sound a
  take that starts its path at the new lag), and the page keeps 1024 after (`scriptBlockFloor`): where
  `SCRIPT_SHARED_OF` (8) of the last `SCRIPT_SHARED_WINDOW` (32) blocks share a stamp with the one before (a
  pair or a run counted once, after `SCRIPT_SHARED_AFTER`: the hardware renders more than one block at a time -
  the research: 512 on 1024-frame hardware plays a block before its stamp), or where a block of 512 is written
  after it began to play where the voice sounds (`SCRIPT_HEARD_LEVEL`, -80 dBFS over it and the two before it:
  a late block plays the one two before it again). That second rule came from the real page, not the spec: in
  headless Chromium at 128-frame renders, a let-go's own work on the main thread left 2 flicks in 5 with a
  2.7 ms stretch played twice in blocks of 512, never in blocks of 1024 (below) - a block of 512 has half the
  room for whatever else the page does. So 512 holds where the page keeps up, and goes the first time it doesn't
  where it can be heard.
- **The counted clock's constants are in seconds** (`countBlock`, pure and exported): `SCRIPT_STAMP_TOLERANCE_S`
  1 ms; `SCRIPT_REANCHOR_S` 64 ms (was `SCRIPT_REANCHOR_BLOCKS` 3); `SCRIPT_SLEW_PER_S` 0.9375 ms a second (was
  `SCRIPT_SLEW_S`, 0.02 ms a block); `SCRIPT_DRIFT_EASE_S` 1.067 s (was `SCRIPT_DRIFT_EASE`, 0.02 a block) -
  each the old value at 1024 frames and 48 kHz, so blocks of 1024 count as they did; in blocks of 512 the
  per-block constants would have eased twice as fast a second.
- **The counted clock after a stall** (`countBlock`). Reproduced first: after a main-thread stall Chromium runs
  the callbacks queued meanwhile back to back, every one stamped alike (inject logs of delay-chain's STALL=400
  runs, and every one of mine below); the stall's jump anchored the count and each burst callback added a
  block, re-anchored every four, so it came out of the burst up to 3 blocks AHEAD of the real playbackTime, eased
  back at 0.02 ms a block - for up to a minute. Over every research recording the k-th callback is the k-th block
  (each evenly spaced stamp sits on the count from the first). So now: a stamp no later than the one before is a
  BURST callback - counted on, nothing else; a stamp more than `SCRIPT_REANCHOR_S` later than the count is held
  (counted on) until two callbacks in a row are evenly spaced again (each stamp one block after the one before,
  to the tolerance) with every stamp since that far on, then anchored by the least of them - a stamp can be
  late, never early (Chromium computes it from the clock as the page runs the callback); one even callback alone
  wasn't enough: the research's 6x-throttled runs had the page late block after block, evenly; a stamp more
  than `SCRIPT_REANCHOR_S` EARLIER anchors it - at once where it is later than the stamp before, but one no
  later than the stamp before (as it is while the count agrees, a block being shorter than 64 ms) is first
  counted on as a burst's and anchored at the next callback (at once, until .40); a count not yet seen to agree with a stamp (the
  first, or one moved forward) is set back to any stamp earlier than it for `SCRIPT_PROVE_S` (1 s: a first block
  asked for a render late anchored it late); and a stamp a step away eases the count toward the stamps' LOWER
  edge (down at once, up over `SCRIPT_DRIFT_EASE_S`) - toward their mean, as before, a page late now and then
  eased it ahead of the truth. WebKit's jitter (stamps a step away, no bursts known) is still eased, never
  followed; WebKit's dropped blocks (a jump, then even stamps) are anchored two callbacks after the jump - two
  later than before, which anchored at the jump itself: 42.7 ms more of the path as it was in blocks of 1024
  (21.3 in 512) - by the least of the stamps waited on, and unproven again after (`SCRIPT_PROVE_S`).
- **Debug's late-block count works** (`startScript`): a block counts late when `currentTime`, read once the
  block is written, is past the block's counted start - the research's slack model, which matched the replayed
  blocks. Until now it compared `currentTime` with the stamp, which Chromium makes from `currentTime` as the
  page runs the callback, a block ahead: it could never fire there. Both block sizes.
- **Debug says the device's own latencies** (`deckLatency`, `DeckReport.latency`, `latencyNote` in
  lib/debugRows.ts, on Turntable timing): the design (`HAND_DELAY_S`, the lag, the limiter's lookahead), the
  block in use, and what the context gives - `baseLatency`, `outputLatency` and the render clock's lead on the
  speaker by `getOutputTimestamp()` (the median of the last nine readings, taken as the deck reads its clock) -
  each only where the browser gives it: "The record's sound: 142.8 ms behind the hand by design (blocks of 512 on
  the main thread), then what this device's audio adds - it says base 2.7 ms, output 8.0 ms, 12.3 ms from render
  to speaker". The recorder's file (version 3) carries `block` and `latency`, and its `scriptLagSeconds` from the
  block; the bench's replay reads the block from the file (`blockOf(source)`, 1024 for a file that doesn't say).

- **Measured, the sims** (decksound.sim's new pin, "a quick grab heard from the press"; the REAL Turntable, deck,
  clock and voice, a 440 Hz tone, the hand's own samples): from the press to the sound half way to the hand's
  speed, less the delay the design gives it (`HAND_DELAY_S`, the main thread's lag, the limiter's 1.5 ms) - a
  still record, the hand at 1x, 0.5x and 0.25x (slop 33, 50 and 83 ms here), both hosts, an iPhone's clock and
  a Mac's: 7.7-14.2 ms (24.4 once, the main thread on the iPhone's clock at 0.25x: a cycle of the slowed tone lasts 9-18 ms there, the measure's grain); a record playing at 0.5x and 2x grabbed by a hand at half or a quarter its speed:
  6.8-12.5 ms. The same check run on HEAD's code (a copy, `work/delay40-builder/head/`): 42-43 ms at 1x, 64 at
  0.5x, 91-108 at 0.25x, and 57-97 for the playing grabs - the slop and the same rise. The join (where the voice
  starts against where the song paused, `repeatMs`) is the same before and after to 0.1 ms on every row of the
  same block size (116-156 ms of the song heard again as the record's sound takes over - the delay and the
  lag, by when the take lands), and the take's place carried on to the crossing's moment is where the song
  paused to 0.2 ms - past the reach too, since review (a hand at 0.1x or 0.15x on a record playing at 0.5x, 1x
  or 2x, crossing 117-217 ms after the press: 115-145 ms heard again, HEAD's to 0.1 ms on every row of the same
  block size).
- **Measured, the real page** (`work/delay40-builder/page/`: `drive40.cjs`, `analyze40.py`, `summary40.py`, built
  on delay-chain's `drive-app.cjs` and its tap on the voice's node; this change's build on 127.0.0.1:8110, HEAD's
  on 8111, a scratch database, a hard-linked copy of builder36's library, the shared stand-in Navidrome;
  headless Chromium as `deadwax.test` over plain http with `--audio-buffer-size=128` (a Mac-like device) and
  1024 (an iPhone-like one), and on `localhost` for the worklet; "Test Signal - Instrument", real touch events
  at 60 a second). Hand to sound on the render clock, ms - a start after a 0.5 s rest and its stop and turn back
  at 1x, quick grabs at 1x, 0.5x and 0.25x from the press, a record playing at 0.5x grabbed by a hand at 1x and
  one at 2x by a hand at 0.5x, each half way from the record's speed to the hand's; design 121.5 / 142.8 / 164.2:

  | | worklet: before → after | main thread, 128-frame renders: before (blocks of 1024) → after (512) | main thread, 1024-frame renders: before → after |
  | --- | --- | --- | --- |
  | start after a rest, 50% | 128.4 → 128.4 | 169.5 → 149.6 | 156.5* → 171.2 |
  | stop, 50% | 135.5 → 135.2 | 177.9 → 158.1 | 165.3* → 178.6 |
  | turn back | 128.7 → 129.2 | 168.8 → 146.9 | 157.4* → 168.4 |
  | quick grab, 1x | 162.4 → 128.1 | 204.1 → 153.3 | 199.9 → 173.6 |
  | quick grab, 0.5x | 188.8 → 131.2 | 231.6 → 152.5 | 233.9 → 174.2 |
  | quick grab, 0.25x | 226.5 → 167.9 | 269.7 → 169.2 | 267.6 → 189.3 |
  | playing at 0.5x, hand at 1x | 191.6 → 147.8 | 229.3 → 155.6 | 227.1 → 175.0 |
  | playing at 2x, hand at 0.5x | 179.2 → 127.5 | 238.8 → 149.0 | 237.1 → 170.4 |

  The slop crossed 34-35 ms after the press at 1x, 58-63 at 0.5x, 92-94 at 0.25x. Headless Chromium hands a
  move to the page 27-32 ms after its own time (median), so at 0.25x the press was 120-125 ms old when the page
  could take it: on the worklet past `TAKE_BACK_S`, taken from a sample 25 ms on (46 ms past the design where
  1x and 0.5x are 7-10); on the main thread within `SCRIPT_TAKE_BACK_S` once that was 115 ms (186.9 at 0.1, the
  first pass). A phone hands its moves on sooner. *The 1024-frame "before" ran with its counted clock AHEAD:
  replaying its own stamps (`clockcheck.cjs`) through the clock as it was, up to 21.3 ms ahead for 1010 of its
  2564 blocks after a burst no one forced - its sound that much early and its look-ahead that much short; after,
  never ahead, and every number there is the design plus the rise. The render clock's lead on the speaker
  (getOutputTimestamp, which Debug now says): 10-15 ms at 128-frame renders (output latency 8 ms), 92-97 at 1024
  (72-80), 40-55 on the worklet's default (32-40).
- **After a forced stall** (`STALL=400`: the page held 400 ms before each gesture): as it was, the start after a
  rest came 126.9-133.7 ms after the hand on the main thread - 30-37 ms EARLIER than the design - its clock up to
  42.6 ms ahead for 928-1221 blocks and 9.5-30.8 ms ahead still as each session ended; after, 170.0-171.6, in
  step: replayed through `countBlock`, never ahead of an evenly spaced stamp, in blocks of 512 or 1024, across
  every recording made here (16 sessions, 3-16 bursts each).
- **Late blocks** (Debug's count, which counts now; stale quanta found in the tap's recording by `staleq.py`):
  blocks of 1024 - at 1x and 4x CPU, none late but at the harness's own stalls (as it turns a recording into
  text), no stretch played twice over five flicks, before or after; HEAD's Debug said "0 of N blocks late" while
  28-29 blocks of a 4x session were late by the clock. Blocks of 512 at 128-frame renders - 15-26 late in a 1x
  session, most at the harness's stalls, and at let-goes (the page's own work then, 16-45 ms after the finger
  lifts): 2 flicks in 5 had a 2.7 ms stretch played twice (`after2-128`, the build before the rule below). So:
  the late-where-heard rule. With it (`after3-*`), blocks of 512 held for 11 s at 1x, 4 s at 4x and 10 s with
  forced stalls before a late block where the voice was heard (a let-go's own transient, below) moved the page
  to 1024 - and no stretch was played twice in the flicks after. Headless Chromium paints in software; how long
  512 holds on James's Mac is what its Debug will say.
- **Found, not changed**: a let-go after a rest gives a short transient - the stop's 3 ms fade on the level of
  the sample the still record sits on, through the 10 Hz DC blocker: 0.02-0.04 of full scale (-28 to -34 dBFS)
  within 50 ms of the lift, before and after alike, on both hosts. Heard as a soft tick, if at all; the voice's
  own, and James's to judge.
- **After review** (four reviewers; each finding below confirmed by skeptics, measured on copies of this tree and
  of HEAD - `work/review-*`, `work/verify/`; the fixes' own runs in `work/delay40-fixer/`):
  - *A moving record taken past the reach was put back where it was at the press.* The take was placed at the
    record's place at the press plus the hand's turn, stamped at a later sample - right for a still record, but
    a playing song or a coast had moved on under the finger meanwhile, and the voice, 120 ms behind, may have
    played it there already: a playing song's join came later (143-240 ms of it heard again where HEAD had
    115-145, in decksound's harness; 72 and 144 ms more in deck.sim's at slops of 160 and 240 ms, 90 on the
    main thread), and a sounding coast's path stepped back - the hand's first knot 132 and 242 ms of the song
    behind where the coast had the record, the voice rushing backwards at -1.15x and -2.03x under a near-still
    finger (HEAD: no step, -0.1x), the very artefact .24's review removed. Hit by a gentle grab, or a press that
    waits a moment before it turns, crossing the slop 100-250 ms after the press - or 70 ms, where a browser
    passes touches on 30 ms late. Fixed: past the reach a moving record is taken where it had got to on its own
    by the sample it is taken from, the anchor that less the hand's turn by then (`takeOver`, `planHasRecord`);
    within reach nothing changed. Pinned: deck.sim (a record playing at 1x and 2x, a hand a tenth of its speed,
    slops of 160 and 240 ms - the take's line carried to the crossing where the song paused, 0 ms; the same on
    the main thread at 200 ms; a sounding coast caught with the press 48, 96, 160 and 224 ms before the
    crossing - the first knot on the coast's line, the voice replayed never below -0.25x) and decksound (the
    join past the reach, both hosts and clocks, 16 rows).
  - *The face jumped back at the crossing.* Its angle was set to the platter's at the press, though the face had
    gone on turning under the slop (it may yet be a tap), so it snapped back by the platter's run under the slop
    less the hand's turn: 2 and 14 degrees in deck.sim's playing grabs at 0.5x and 2x, 20 and 38 on a coast,
    14 and 43 in turntable.sim's real Turntable at 1x with slops of 96 and 240 ms (87 at 2x with 240 ms, by the
    reviewers'); HEAD stepped on by the hand's turn in the slop, about 5 degrees. "What can't be had" was wrong:
    the face's angle is tied to nothing heard. Fixed: the angle at a quick take is the platter's as the slop is
    crossed less the hand's turn so far, so the face as drawn carries straight on. Pinned: deck.sim's three face
    checks re-based to the drawn face's continuity (frames run through the slop), the coast's, the slow hands'
    at 1x and 2x, and turntable.sim's real Turntable (a step of the platter's own turn since the last frame, 0
    more).
  - *The docs promised more than the reach gives*: docs/player.md, troubleshooting.md and the README now say the
    press is reached back to only about a tenth of a second, counted from when the page hears of the move, so a
    slower start keeps the rest (headless Chrome over HTTPS at a quarter of the record's speed: about 60 ms
    sooner, not 95).
  - *Rules nothing pinned*, each now caught by a check that fails without it: the counted clock started afresh
    at the switch to 1024 (dropped, the new node's first stamp, which real Chromium gives one block of 1024
    past the old count's next, is a step away - eased toward for 20-odd seconds, each block rendered 21 ms
    early, the sound that much later; now checked block by block at that placing); no switch while a recording
    runs (its tap is on the node and its file names the block); the late-where-heard rule's two blocks before
    (a silent late block after two loud ones changes it, one after two silent ones doesn't - and, after the
    second review, one after a loud block then a silent one, the block two before alone loud, changes it too:
    the first case had the block just before loud as well, so it couldn't tell the two apart); `outputLatency` in
    Debug (the fake context gains one: 8 and 76 ms read, none where it says none); and the drop's anchor by the
    LEAST of the stamps waited on and the count re-proved after a forward anchor (without both, 3 ms ahead for
    100 blocks, 2.1 s; the old check's stamps were exact, so neither could fail it).
  - *A second review* (findings confirmed by skeptics; fixes in `work/delay40-fixer2/`):
    - *Every Safari started in blocks of 512*: WebKit's `baseLatency` is its 128-frame render quantum on every
      device, so `scriptBlockFor` read "128 frames" on James's iPhone and every Mac Safari - against the spec's
      "can't tell keeps 1024" and these notes. Fixed: Apple's engine keeps 1024 (above); Debug's `base` and the
      docs say it is Safari's own 128-frame step there, not the hardware's. Pinned: deck.sim (`scriptBlockFor`
      on Apple's engine at 128-1024 frames, `isAppleEngine` by vendor and by the prefixed constructor and not
      for Chromium, Firefox or no navigator, and a Safari-like deck on a 128-frame context in blocks of 1024 at
      164.2 ms).
    - *Nothing checked that what taps the voice follows the new node after the switch to 1024* (`audio.node`):
      without it a recording or the bench's analyser started after the switch would hang off the old,
      disconnected node - a file of silence. Pinned: deck.sim records after the switch and checks the tap is on
      the new node, not the old.
    - *The heard rule's two blocks before* was pinned only together with the block just before (above).
    - *Wording*: docs/player.md and troubleshooting.md said an iPhone got 1024 "so far" (now: Safari and every
      iPhone browser, because they can't say); troubleshooting.md called `from render to speaker` the same as
      `output` - it is `base` and `output` together, read another way (the measurements above: 10-15 ms against
      2.7 + 8, 92-97 against 21.3 + 72-80), so what is heard is the design plus it, not plus all three; the
      comments on `DeckLatency` and `deckLatency` say the same now.
  - *Wording*: the clock's notes and comments said a far-earlier stamp anchors at once and a drop one callback
    later than before - corrected above (a burst's first, then the next callback; two callbacks later).
  - *Measured in the real page* (`work/delay40-fixer/page/`: the builder's drive40.cjs with three more gestures -
    a record playing at 1x grabbed by a hand at 0.15x, and a coast after a flick caught by a quick grab at 0.1x
    and 0.15x - the face as drawn read once each frame has painted, and `trace.py`, the tone's speed after the
    press; this tree on 127.0.0.1:8112, a copy with the first build's `takeOver` on 8113; headless Chromium on
    `localhost` (the worklet) and as `deadwax.test` with 128-frame renders (blocks of 512)). The face's largest
    step back in a frame, first build -> now, worklet / main thread: a record at 2x grabbed by a hand at 0.5x
    -27.6 / -28.1 -> 0 / 0 degrees; at 1x by 0.15x (slop 160 ms) -30.6 / -30.7 -> 0 / 0; a coast caught at
    0.15x (slop 154 ms) -25.6 / -25.9 -> 0 / 0, at 0.1x (221 ms) -34.8 / -34.4 -> 0 / 0. The coast's sound (a
    tone read forwards whichever way it plays, so a run back shows as its speed falling to 0 and rising again):
    first build, from the coast's 0.9x down to 0.15-0.25, back up to 0.47-0.48 and down again over 150 ms (0.15x
    hand), and down to 0.39 and back up to 0.96 (0.1x hand, worklet) - the record's sound running backwards
    under the finger; now, from
    the coast straight to the hand's 0.15x, or 0.10x, and held there. The grabs within reach as the builder
    measured them (quick grab at 1x 128.4 ms, 0.25x 168.0, a record at 2x by 0.5x 127.5, on the worklet).
- **Verified**: 2395 Python tests (2393 passed, 2 skipped; none new - the change is the page's), pyflakes, tsc,
  the bundle, all 47 sims (`deck` 353, 48 new over .39's 305 - 4 of them the second review's; `decksound` 73, 4 new; `turntable` 175, 1 new;
  `debug` 110, 2 new; `lab` 122, 1 new; `deckclock` 35 and `limiter` 30 as they were). Re-based, each on purpose: the
  recorder's version (2 to 3) in deck.sim and lab.sim, and the turntable.sim and decksound.sim literals named
  above; the fakes gained blocks of either size (deck.sim's `fill`/`pump`, decksound's and lab.sim's hosts), a
  context's `baseLatency` and a `getOutputTimestamp()`, and a player whose position plays on (decksound). The
  engine guard is empty. Mutation checks (`work/delay40-builder/mut/mut.py`, `mut.log`, each file restored to its
  sha256): 27 of 27 caught - the quick grab (from the press, the reach back on either host, the join's anchor,
  the face at the press, the slop's samples in the let-go's speed, Turntable's quick take and its `touched`),
  the clock (the burst, two evens, holding at all, unproven, the lower edge, the slew in seconds), Debug's late
  count, the block (from baseLatency, the shared-stamp and late-where-heard changes, the heard rule, switching
  only when silent - not when merely not driving - the page's floor, the lag of either size and after the
  change), the recorder's block, the speaker reading, the bench's block from the file and Debug's note. Two (the
  slop's samples in the let-go's speed, the lag after the change) first got past, and gained the checks that
  catch them. After review, on a copy of the tree rather than the tree itself (`work/delay40-fixer/mut/mut.py`,
  `mut.log`, each file restored to its sha256): 38 of 38 caught - those 27 as the code reads now (the face's
  now two: from the press as first built, and at the crossing without the hand's turn as HEAD had it), and the
  moving record past the reach (a plan's place, a playing song's line, the anchor less the hand's turn), the
  switch's own clock, no switch while recording, the heard rule's two blocks before, `outputLatency`, the
  drop's anchor by the least and its re-proving. After the second review (`work/delay40-fixer2/mut/mut.py`, `mut.log`): 45 of 45 - those 38, and Apple's engine kept at 1024 (the branch, its default, the vendor and the prefixed constructor), `audio.node` following the switch, and the heard rule's block two before alone (in the max, and its shift).
- **NOT verified**: James's devices - how long blocks of 512 hold on his Mac (Debug's "blocks of 512" or "of
  1024" says), what his iPhone's context says of its latencies (its block is 1024 whatever it says - WebKit's
  baseLatency is its render quantum; whether blocks of 512 would hold on a phone is untried, and wasn't wanted
  without it), how WebKit stamps after a stall (no bursts are known there; its dropped blocks are
  anchored two callbacks later than before, so 42.7 ms of the path as it was in blocks of 1024 after each), how
  a quick grab feels from the press on a real finger, and how a slow one does (a start that is still inside the
  slop a tenth of a second on is heard from the reach, not the press).
