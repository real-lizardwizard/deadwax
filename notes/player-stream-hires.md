# The player: one stream for FLAC, and hi-res resampled to 48 kHz

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

#### One stream for FLAC (1.1.0-player.5)

James, with the second-player gapless still leaving ~100 ms on the iPhone: build "the method that
just worked on iOS" - a lab page (scratchpad, never in the repo) that played consecutive FLAC songs
through one ManagedMediaSource seamlessly on his iPhone, in Safari and in Arc, locked, fetching over
the network while locked. The second-player way stays, for every song the stream doesn't take. The
guide's section is `docs/player.md#one-stream-for-flac`.

- **The recipe is exactly the lab's; don't vary it without the phone.**
  - ManagedMediaSource on WebKit (the only MSE an iPhone has), plain MediaSource in Chromium, chosen
    once per page by `mediaSourceEngine()` (streamSource.ts). Type `audio/mp4; codecs="fLaC"` first
    (WebKit's ManagedMediaSource takes only the ISO fourcc), `"flac"` second.
  - Each song as a fragmented MP4 of its own FLAC frames, made by deadwax (`wrap=fmp4`).
  - Each song's init segment appended immediately before its media: without it WebKit clicked at
    the join.
  - Songs placed with `timestampOffset` = the run's earlier samples / rate. WebKit rounds it to the
    sample timescale (`roundTowardsTimeScaleWithRoundingMargin`), so a join lands on the exact
    sample however long the run.
  - `disableRemotePlayback = true` BEFORE attaching a ManagedMediaSource, or WebKit leaves it
    `closed` without a word (the open is deferred until AirPlay can't be asked of the element). It
    goes on as `srcObject`; Chromium refuses a MediaSource as srcObject, so a `blob:` URL there.
- **The server: `fmp4_layout()` in flac_mp4.py**, pure like the MP4 muxer and sharing its frame
  splitting: ftyp (iso5), a moov with mvex/trex, a sidx, then a moof and mdat per second of frames,
  every sample flagged sync (tfhd default flags 0x02000000). Byte for byte the lab's ffmpeg file,
  but for the sidx (added) and udta (left out). player_cache keeps them beside the MP4s as files of
  their own (`.f.mp4`, `FMP4_WRAP`, `FMP4_FORMAT_VERSION` in the key), with their own makes and
  refusals. `answer_fragmented()` answers byte ranges; a 415 JSON when this version can't be
  repackaged; a 503 with `scope` "song" (Retry-After 2) or "server" (30); never the FLAC, which a
  MediaSource can't take. The route takes `wrap=fmp4` only with `format=raw` (400 otherwise).
  **The If-Range pin** (`_pinned`, `PINS_KEPT` 1024): a range whose If-Range names the file the
  song was last served as is answered from it without asking Navidrome, so a Navidrome redeploy or
  a retag mid-song doesn't break the stream.
- **The page: `ui/src/player/streamSource.ts` owns the stream** (which songs are in it and where,
  fetching, appending, seeking, saying when it can't go on and for which song); usePlayer keeps the
  queue, the lock screen and the listening. The rules are pure in `lib/streamPlan.ts` (placing
  songs, what to fetch next, what an answer means, retries) and `lib/fmp4.ts` (reading a head),
  pinned by `stream.sim.cjs` and `fmp4.sim.cjs`; the wiring by `player.sim.cjs`, whose fake
  MediaSource parses the real fragmented MP4, places frames as WebKit does, evicts under Safari's
  cap, clamps seeks to `seekable` and waits at holes.
- **What the browser does NOT do for us**, each read in WebKit's or Chromium's source:
  - An iPhone holds about 5.26 MiB of audio in a SourceBuffer (Chromium 12 MiB). So pieces of at
    most 5 s or 1 MiB, fed 10 to 30 s ahead (`REFILL_BELOW_S`, `FILL_TO_S`) within 3 MiB (8 MiB
    plain); a QuotaExceededError clears what is behind (keeping a second), then splits the piece at
    a fragment boundary, then waits for the playhead - never on a playhead that is itself waiting.
  - What to fetch is worked out from `buffered` every time (`nextWant`), never from a cursor:
    eviction and seeks leave holes anywhere.
  - A seek is clamped to `seekable`, [0, duration] for a finite duration that grows only as data
    comes, so the duration is raised first; and Safari 27.0 evicts relative to where the playhead
    WAS, so a seek to unbuffered time removes every other range, appends only the target's piece,
    and appends nothing more until 'seeked' (the stages: wait, clear, place, append, land).
  - `endOfStream()` is a state: an append, a remove or a `timestampOffset` reopens an ended source,
    and an open one stalls at its end instead of ending - on a locked phone, the music stopping. It
    is called again whenever the run is all in.
  - An aborted append's 'updateend' arrives after whatever came next: nothing trusts an
    'updateend' while `updating` is true.
  - `srcObject` beats `src`, and any `load()` detaches a MediaSource for good: usePlayer's
    `detach()`, and `reload()` on a stream leaves the stream instead of reloading.
- **A new stream only in a gesture** (a tap, a lock-screen command): outside one - a song ending, a
  skip after a failure - a new MediaSource would have to open, fetch and append before iOS
  suspends a page that isn't playing. Those go the URL way, and the next tap streams again. No
  standby holds a song of the run (`standbyPlan`'s `live`).
- **What joins**: FLAC, up to 48 kHz, one or two channels, 16 or 24 bits (`formatStreamable`), in
  the same format as the song before (`joins`). A song kept out by its format only is `noStream`
  (it still gets its MP4 for Safari the URL way); one deadwax won't repackage, or whose bytes won't
  decode, is `refused` (the file as it is). A song that fails the stream plays the URL way from
  where it had got to, as the raw FLAC (`leaveStream`): deadwax relays that at once, where an MP4
  could mean a make first.
- **AirPlay**: a stream can't go to AirPlay. `showAirPlay()` leaves the stream in the same tap, then
  shows the picker (a Mac wants a second tap). Availability events are ignored while
  `disableRemotePlayback` is set - WebKit says "none" then - and no stream starts while wireless.
- **The readout**: a join reads `in one stream`, 0 ms, or the stall from 'waiting' to 'playing' if
  the stream waited there; the seek line ends ` · in one stream`.
- **Engine off**: three failures with no stream playing in between, or a 503 with scope "server",
  and no stream is tried for `ENGINE_OFF_MS` (10 minutes); the second player meanwhile.
- **Verified in the real page** (Chromium, the stub Navidrome, 8081): recorded through Web Audio, an
  album's signal ran 39.7776 s against 39.7777 expected, the largest residual 0.00004, no spikes;
  joins at 0 ms; the lock screen's title switched within 250 ms of each join; Mixed (FLAC then MP3)
  handed over to the MP3 on the standby in 46 ms and went on the URL way; hi-res went the URL way; a
  seek in song 2 landed exactly (19.100 = 16.3218 + 2.778); "previous" restarted at the song's own
  start on the same source; deadwax repackaged each song in about a millisecond; and, after the
  review, a 25 s pause then play carried on in the same stream.
- **NOT verified - the phone's to answer**: deadwax's own build on an iPhone at all (the lab proved
  the recipe, not this code); the lock screen's title and scrubber per song; seeks, Next and
  Previous from the lock screen; leaving for AirPlay; the fetching pattern against the real cache
  over WireGuard.
- **Play on the lock screen after a long pause does nothing until the app is opened** (James, on
  the lab and on the player as it was): iOS suspends a paused web page - WebKit releases the
  page's MediaPlayback assertion once nothing plays, and remote commands queue to the suspended
  web process until something wakes it. Not fixable cleanly from a page; the one loophole, never
  pausing (playing silence), keeps the phone awake and the lock screen claiming a song plays. So
  it's in troubleshooting, not worked around.

##### After review (the stream)

A review in four lenses (engine, player, server, tests), each finding checked by a skeptic who
wrote a failing scenario first. Everything confirmed was fixed:

- **A later song's trouble cut the song playing** (major). A piece of song N+1 answered changed,
  refused, fatal or engine-off, or an append error on its bytes, failed song N+1 at once, and
  usePlayer loaded it: up to ~28 s of song N lost. Now `pieceFailed` for a later song, while the
  playhead still has music (`!waitingOn`), ends the run before it (`endAt(index - 1)`) and removes
  whatever of it was appended (`cutAt`: `remove(start, Infinity)`), so `endOfStream` can't stretch
  the timeline over it; a 404 or 415 also marks it refused. An append error on a later song marks it
  refused and fails the song PLAYING as `'broken'`, which leaves the stream from where it was: both
  engines give up the whole source on an append error. `streamFailed` moves the queue on only with
  the playhead at the join (`songPosition() >= songLength() - 0.5`) and never for 'decode' - a
  second guard, which the engine fix means never fires. `endAt` now reports `runEnded` again
  whenever the end moves earlier; reported once, the standby kept the song after the OLD end.
- **A seek to a song's last moments stalled** when nothing was placed after it: both `covered()`
  checks asked for 50 ms past the song's end. Now `Math.min(target + 0.05, song.end)`.
- **Resuming after a pause was taken for stuck**: the watchdog's clock moved only with the
  position. `progressed()` refreshes while paused, and `play()` ticks the stream before
  `audio.play()`, for a locked phone whose timers haven't run.
- **The head's first fragments were fetched twice** for any CD song (the lead was used only when a
  whole piece fitted in it): they're appended from the lead, and the first ask starts after them.
- **A second split lost the first split's other half**: `rest` is a queue.
- **`get()` read a whole 200 before looking at it** (a changed song's entire file): the status
  first; only a 206, capped at what was asked, or a 503's first 4 KiB (its scope) is read.
- **"Three failed streams in a row" meant three without a crossing**: reset when the engine goes off
  and on 'playing' with a stream.
- **Next into the run's last song never readied the song after the run**, and `runEnded` started
  that download at once beside the stream's first fill: `preloadSoon()` in both.
- **The next song's head was asked a whole song early**, so with a small cap it looked idle (only
  its head served) when the song after it was made, was cleared, and its first piece got a 503.
  `lookAhead` now waits until the feeding is within `FILL_TO_S` of the last song's end, about a
  minute before the join; a song that can't join is still known at once.
- **Server: a made file bigger than its FLAC cleared the song being played.** Room is made at the
  FLAC's size, and `_evict` then trimmed the MP4's few KiB of boxes off whatever was served longest
  ago - with a small cap, the song on the playhead, and two songs played in turn re-made a whole song
  per piece. `_evict(over=)` never clears a song in use for that overhead.
- **Server: a disk short for ONE long song turned streaming off for 10 minutes and wiped the idle
  songs.** `Room.SHORT` (503, scope "song") when clearing every idle song still wouldn't be enough,
  and then nothing is cleared; `Room.DISK` (scope "server") only when even a small song
  (`SMALL_SONG_BYTES`, 16 MiB, or this one if smaller) wouldn't fit with everything cleared.
- **Kept as it was**: a first song whose head takes more than about 25 s is left for the URL way
  (the watchdog doesn't count a head on its way). Waiting out the 90 s header timeout would be longer
  silence, and on the NAS a make takes about a second.
- **Tests**: player.sim.cjs gained the skeptics' probes and a check per fix - a later song's 404,
  401, change and append error at two points in a 4-minute song, a run cut after its end was known,
  If-Range on every piece, a seek to the end with a minute left, pause and play just before a
  watch, slow first heads, when the next head is asked, moving inside the stream, the Opus song
  after a run, a last song too short to be seen, gestures, AirPlay, the lock screen, a stalled
  body, flaky pieces, 503s, failures not in a row, sample-exact joins, the lead, double splits -
  and `check()` shows a MediaSource by its kind instead of crashing on `JSON.stringify`. Sixteen
  mutations, one per fix, were each caught, three of them only together with a partner they back
  up: the seek's wait-stage check (the append stage), the append error's blame (`streamFailed`'s
  join rule), and the tick before play (progressed-while-paused, since the sim's timers run). Three
  new tests in test_player_cache.py catch the three server mutations.

#### Maximum quality: hi-res resampled to 48 kHz (1.1.0-player.6)

James, on 24/192 Dark Side of the Moon never going into the one stream (formatStreamable admitted 48
kHz and below): "let's transcode it down to 48khz and push that under one condition. I don't want to
lose any sound quality ... let's make it a setting in the app, a maximum stream quality." Then: "if
it's possible to keep 24/192, obviously that would be preferrable". The guide's section is
`docs/player.md#maximum-quality-hi-res-at-48-khz`. The design, the research and every measurement are
in the session scratchpad's `resample/` (SPEC.md, research_ios.md, research_libs.md, verify_audio.md,
review_confirmed.md); what matters is below.

- **The setting**: `deadwax-player-max-rate` ('48000', the default and anything invalid, or
  'original'), per device like the Gapless switch, in a sheet from the gear beside the Library title
  (`ui/src/player/Settings.tsx`, `role="radiogroup"`, focus kept and returned - WebKit doesn't focus a
  tapped button, so the gear focuses itself first). **Moved in 2.0.0-player.9** to You > Playback
  (`app/QualityChoice.tsx`, the same words, key and keys); the sheet and the gear are gone - see
  "The one app". It applies from the next song started or got ready; a stream keeps the setting
  it started with (its `urlOf`, `streamable` and format gate are fixed at `startStream`), and
  `fitStandby()` lets go of a standby readied at an address that changed.
- **What is resampled, and the one rule both sides share**: FLAC at 88.2/176.4/352.8 kHz -> 44.1 and
  96/192/384 -> 48 (whole ratios 2, 4, 8 only), 16 or 24 bits (libsndfile 1.2.2 can't open 20- or
  32-bit FLAC), 1-2 channels. `RESAMPLED_TO` exists in `src/resample.py` AND `ui/src/lib/streamWrap.ts`
  (`resamples()`); keep them in step. The page knows a song's rate from Navidrome's OpenSubsonic
  `samplingRate`/`bitDepth`/`channelCount` on getAlbum's songs (read in Navidrome's source:
  osChildFromMediaFile, sent to every client not listed as legacy) and asks with `max_rate=48000`:
  `wrap=mp4&max_rate=48000` in ANY browser (Chromium plays FLAC in MP4) and the stream's
  `wrap=fmp4&max_rate=48000`. A song with no rate from Navidrome is asked as before. The server reads
  STREAMINFO and decides; a song it doesn't resample is answered from the SAME file, same ETag, as
  without max_rate.
- **Why this keeps the condition (research_ios.md, with sources)**: Apple says an iPhone plays at most
  24/48 natively; speaker, AirPods (lossy AAC anyway), Apple's adapters and AirPlay run at 44.1/48, so
  iOS converts hi-res itself - and its conversion of a 96 kHz file was measured rolling off 3.5-4.5 dB
  near 20 kHz (older iOS). WebKit never calls setPreferredSampleRate, so whether a USB DAC ever gets a
  song's own rate from Safari is unknown - "Original" is for that. libsoxr VHQ in float64, measured
  independently (verify_audio.md): 20 Hz-20 kHz within 7e-9 dB and 6e-10 rad, no delay, polarity kept,
  -0.01 dB at 22.24 kHz (20.44 at 44.1), aliasing >= 184 dB down, 24-bit rounding +-0.5 LSB, matching
  a from-scratch float64 sinc and ffmpeg swr to the last bit. Undithered on purpose (deterministic,
  lowest total noise; spurs at -152 dBFS at worst, 30 dB under any DAC).
- **3 dB of headroom on every resampled song (`HEADROOM_DB`), never a per-song gain.** Removing the
  ultrasonics pushes a hard-clipped master's peaks past full scale: measured 0.77-1.73 dB at 6 dB of
  clipping, up to 2.87 at 12, one stretch of a real 24/192 recording clipped 18 dB at 3.11. The first
  cut lowered only the songs that went over, by exactly enough - and every join between a lowered
  song and an unlowered neighbour then stepped by that gain (about 11 % of the waveform at 1 dB, a
  tick). One fixed gain for every song keeps the joins exact and costs level only, which is what the
  phone's own float volume stage does when it converts hi-res itself. A song past even 3 dB gets a
  second pass, lowered exactly enough, and a WARNING naming the step at its joins. The headroom is in
  the cache key. Don't "tidy" it back to a per-song gain, and say so to James if he asks why 48 kHz
  is quieter: match levels before comparing.
- **The joins: context and one grid.** Resampling a song on its own treats the silence around it as
  music - measured -24 to -6 dB error at every join of continuous music. So each song is resampled
  with the last 16384 input samples of the album's song before and the first 16384 of the song after
  (enough at 8:1; 1024 does at 2 and 4), on ONE grid for the album: phase = `(-earlier) % ratio`
  (the NEGATIVE of the earlier same-rate tracks' total samples - the plus sign joins at -14.7 dB, one
  sample long), output count `ceil((N - phase)/ratio)` (soxr alone gives floor(N/ratio + 1/2), so
  zeros are flushed after), next phase `(phase - N) % ratio`. Then the songs concatenate to one
  resample of the whole album: -207 dB (float64), 31 of 32 joins 0 LSB within 10 ms, the rest 1 LSB.
  `src/album_context.py` finds the album through the client's internal calls (getSong, getAlbum,
  STREAMINFO by small range reads - NOT player routes; test_there_is_no_general_proxy is unchanged),
  single-flight per (version, cap), sticky when Navidrome hiccups, bounded on the cache's clock. A
  song Navidrome answers for but won't serve is off the grid; Navidrome not answering at all means
  the song is resampled alone, logged once.
- **A made file is keyed by the context it actually got.** The plan (phase, neighbours) is in the
  cache key; a neighbour read that failed during the make used to leave a clicking file under the key
  promising that context, for good, and a later re-make put different bytes under the same ETag.
  Now the file is stored under the plan with that side removed, and that make is remembered for
  `LOST_SECONDS` (10 minutes): every fresh start in that time is that file, with no context read,
  and a play after it tries again. Ten minutes, not VERSION_SECONDS, because the re-check found both
  ends of a 30 s memory wrong: a song got ready minutes ahead (the standby, the warm-up) began on
  the file made without the side, then the handover's readout probe made it again WITH the side and
  Safari's element carried on into the new file at the old offsets; and a neighbour whose reads
  always time out cost a 10 s wait at every song change. The pins keep up to `PIN_FILES_KEPT` (4)
  fragmented MP4s per URL, so two phones on the two files of one song each stay on their own. A
  stream copy that isn't whole (cut short) is cleared and the MP4 made the ordinary way, never
  refused for it.
- **Context decoding goes through soundfile's PUBLIC API**: whole frames found with flac_mp4's header
  rules plus next number plus CRC-16, put in a minimal FLAC of their own ('fLaC', STREAMINFO as the
  only block with total_samples = those frames' samples and the MD5 zeroed, the frames untouched and
  numbered wherever they are). A raw prefix or a tail with the original STREAMINFO fails in libsndfile
  ('lost sync', 'psf_fseek failed'); the rebuilt one was exact in 1120 randomised decodes. The frame
  search has a false-sync budget like flac_mp4's: without it a crafted neighbour made the search
  quadratic - measured 27 s at a 16 KB frame and days at what CONTEXT_READ_MAX allows, in worker
  threads that `wait_for` abandons but can't stop.
- **The make** (`src/player_cache.py`): download, context (outside both gates), the resample under its
  OWN lock (a resample holds a block, not the song, and can run a minute on a NAS - another phone's
  50 ms repackage mustn't wait behind it), then the repackage under the old gate; cancellable through
  a threading.Event set by `_to_the_end`. The resampled FLAC is written through Python's own file,
  since libsndfile by path raised RuntimeError mid-file on a full disk and NOTHING at the last frame
  (a truncated FLAC); refused writes surface as ENOSPC, so the old retry clears room and resamples once
  more. WRAP_MAX_BYTES and the cap's reservation are judged by the estimated OUTPUT (the source streams
  from disk). A song damaged part-way is refused and remembered. An MP4 of a resampled song whose fMP4
  is cached is made FROM the fMP4 ('fLaC' + dfLa STREAMINFO + the frames) - no download, no resample -
  which is what lets leaving the stream carry a resampled song on at the same level.
  `X-Deadwax-Resampled: 192000-48000` rides on every answer of a resampled file (200, 206, 416);
  `_answered`/`_pinned` are keyed by (song, cap), and Chromium's `bytes=0-` long after the URL's last
  answer is a fresh start, not a carry-on. numpy/soxr/soundfile are imported lazily: without them
  max_rate is ignored, logged once, and the resample tests skip - except one that fails when CI is
  set, so CI can't skip them silently.
- **The page**: the stream joins only across the same SOURCE rate (the header's `from`, else the head's
  own rate): a 96 kHz song and a 192 kHz one both come out 48 kHz with no context between them. Under
  "Original" hi-res FLAC (1-2 ch, 16/24, up to 384 kHz) joins the stream as it is - an iPhone holds
  ~8 s of 24/192, so it runs ~4-5 s ahead; a first-of-run decode failure at that rate keeps the song
  out of Original streams only, not refused. A resampled first song's pending head gets
  `RESAMPLE_HEAD_WAIT_MS` (60 s) before the stuck watchdog gives up. With the Gapless switch off or
  while AirPlaying, nothing got the next song ready, so every hi-res change waited for a whole make:
  `warmSoon()` holds a `bytes=0-1` ask for the next song's resampled copy from 3 s into each song
  (held, since a make nobody waits for is cancelled). The warm-up is kept while its song is next and
  resampled, whoever else asks for it, so the standby's download joins the same make; it is let go
  when a stream will play the song; and when AirPlay starts while the standby downloads, the warm-up
  takes the make over by asking AT ONCE (`warmSoon(0)` doesn't wait a tick), since deadwax may notice
  the standby's hang-up at any moment of its half-second check - the sim's `makeGraceMs: 0` pins that
  ordering. A refused resampled copy falls back to the
  song's ORIGINAL address (its MP4 in Safari), not the raw FLAC. Readout: ` · in one stream, 192 kHz
  resampled to 48 kHz`, ` · FLAC in MP4, 192 kHz resampled to 48 kHz`, ` · in one stream, 192 kHz`.
- **Found in the real page, fixed with it**: every album's LAST song fetched again the fragments its
  head had brought - lookAhead ends the run, endAt pumps, and the outer pump then acted on a stale
  want. `pump()` counts its calls and stops when another ran inside it; a sim check fails without it.
- **Reviewed**: four lenses and a skeptic per finding; 25 confirmed and fixed (the context-keyed
  files, the false-sync budget, the warm-ahead and the level jump on leaving the stream were the four
  major), each with a test that fails without it.
- **Verified in the real page** (Chromium, the stub Navidrome with a continuous 24/192 album split at
  non-multiples of 4 samples, deadwax with the audio libraries): under Up to 48 kHz every head asked
  `max_rate=48000` and came back `192000-48000`, each song resampled in about 0.1 s, the joins read
  0 ms, and recorded through Web Audio the tone came out at exactly -3 dB with the residual at both
  joins -93 dB, the same as mid-song (a click would be -10 to -30); under Original, full level, no
  header, joins -95.7 dB, the readout `in one stream, 192 kHz`. The settings sheet checked with real
  clicks and keys.
- **NOT verified - the phone's**: any of it on an iPhone; how long the first song waits on the NAS;
  whether an iPhone streams 24/192 FLAC at all under Original; the image's real size with the wheels
  (numpy 2.5.3, soxr 1.1.0, soundfile 0.14.0, cffi, pycparser: about 75 MB installed, measured
  outside docker - python:3.14-slim already has libstdc++6, libgcc-s1 and zlib1g).
