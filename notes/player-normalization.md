# The player: Normalization

### Normalization (2.0.0-player.62)

James, 2026-10-22: "Can I also get some settings for normalization? I'd like the default to be album-wide
normalization when an album is played, but when any single song is played, it should be song normalization."
He listens on AirPods with an iPhone, over plain http (WireGuard), from the home-screen app, and in Chromium on
a desktop. Approved as designed ("go for it"), every choice below his to overrule. The design and its
measurements: the session scratchpad's `uplan/slice-normalization.md` and `work/design-norm/proto*.py`.

His standing rule - no processing may cost sound quality - holds this way: levelling changes the samples by
design (he asked for that), so it costs NOTHING ELSE. No clipping, no lost resolution, an album's joins exact,
and **Off is bit for bit what deadwax sent before**.

#### Where the gain is applied - deadwax's server

- Not the element's `volume`: WebKit locks it on an iPhone (`defaultVolumeLocked()` is small-screen under
  PLATFORM(IOS); `setVolume()` stores the value until a queued task puts the old one back - HTMLMediaElement.cpp,
  read at main 2026-10-22). Chromium's goes only down, and two mechanisms would level desktop and phone differently.
- Not Web Audio: a GainNode on the playing element needs `createMediaElementSource`, banned.
- Not Navidrome: 0.64.2 applies no gain (its transcodings carry no volume filter, it measures nothing); it hands
  ReplayGain TAGS to OpenSubsonic clients to apply.
- So deadwax applies it, in the copy it already makes of a FLAC song for the player (src/resample.py: decode with
  libsndfile, float64, round to 24 bits, FLAC, then the MP4 or fragmented MP4). One more multiply; levelled AND
  resampled is quantised once.

#### The rule (lib/loudness.ts `levelFor`)

Automatic levels by album whatever was queued as an album, and song by song everything else; By song and By album
whatever was queued; Off asks for no level. "Queued as an album": an album page's Play/Shuffle/row, an album's own
••• Play Next/Last, a Search song's tap (`playSong` plays its album), a done request's ▶, an artist's Play.
"Songs": an artist's Shuffle, a playlist, the Library's Shuffle, a song's •••. Album gain is the song's OWN album
(Navidrome's: every disc). The setting is read at the tap (player/levelling.ts `queued()`, a synchronous storage
read) and the level rides ON the queue entry (`LevelledTrack = QueueTrack & { level?: Level }`, declared in
lib/loudness.ts so playQueue.ts has no diff): the engine keeps entries by reference, so every address built from
one carries it, a Repeat's copies and a reshuffle keep it, and a change of setting applies from the next thing
played. Under Off `levelled()` returns THE SAME ARRAY of the same objects.

- **The Library's Shuffle's feed** (not in the spec - found building it): its later pages are appended by
  app/useShuffleFeed.ts, which no tap reaches, so they would have played unlevelled. The level the first page got
  rides on the shuffle's paging (`Paged.level`, lib/upNext.ts - not an engine file; withMore spreads it on), and the
  feed queues every later page and a Repeat All's next round at THAT level (`atLevel`), never the setting as it is
  now. shuffle.sim pins both, and Off.
- Every playTracks/playNext/playLast call in the files app-rules allows passes its songs through `queued(`
  (ShuffleSongs a line before) - app-rules.sim's Normalization section; a forgotten one plays as under Off, never at
  a wrong level.

#### The address (player/api.ts)

`streamUrl`/`fragmentedUrl` append `levelParam()` LAST, after `&max_rate`; `asksForMp4`'s fourth argument is
`resampled || levelled` (its existing meaning, "deadwax sends it only repackaged"), so Chromium gets deadwax's MP4
of a levelled song as it already did of a resampled one. lib/streamWrap.ts has no diff. `scrubWindow(..., level)`
appends `&level=`. The turntable (Turntable.tsx DeckHost `song()`, deck.ts) and the visualizer (Visualizer.tsx
`syncSong`, vizSync's `SyncSong.level`, vizAudio.ts) ask their windows at the entry's level. Only FLAC asked as it
is (`format=raw`) is levelled (`levels()`): an MP3, Opus or a transcode never carries `level`.
loudness.sim's frozen table: 24 cases (FLAC 16/44.1, 24/96, 24/192, no rate, MP3, Opus x Chromium/iPhone x
48 kHz/Original) of [stream, fragment, window] address, recorded from 2.0.0-player.61's own api.ts (compiled from
git 3458dbf) - every unlevelled entry's address the same string.

#### The engine's seven lines (usePlayer.ts) - and what they don't reach

```ts
import { levels, unlevelled } from '../lib/loudness'
const levelledAt = (track, cap) => levels(track, streamFormat(track, canPlay)) && !state.refused.has(variantOf(track, askedAt(track, cap)))
// addressAt: a refused copy asked for as the file itself - WITHOUT its level
const plain = state.refused.has(variantOf(track, asked))
return streamUrl(plain ? unlevelled(track) : track, canPlay, pageWraps && !plain, asked)
// checkWrapped: resampled || levelledAt(track, cap)      - Info's probe in Chromium too
// warmAddress:  (resampledAt(...) || levelledAt(track, state.maxRate))  - the next song warmed with Gapless off
// startStream:  resamples: ... || levelledAt(song, cap)  - a levelled first head gets RESAMPLE_HEAD_WAIT_MS
```

The engine guard: `git diff --stat` on streamSource.ts and lib/{playQueue,gapless,scrub,streamWrap,streamPlan,fmp4}.ts
prints nothing; player.sim.cjs only gained lines. Two things those lines leave as they were, both found in the sim:

- **Leaving a stream mid-song** (`leaveStream`'s last branch) builds its address with `streamUrl(track, canPlay,
  false)` itself, not `addressAt` - so a levelled song that leaves the stream (AirPlay, a decode error, the switch)
  carries on as deadwax's levelled MP4, made from the stream's own copy (`_from_twin`, no download): the SAME LEVEL,
  no jump. Only after a decode error is that the copy just refused; the NEXT ask of the song (a tap, the standby, the
  warm-up) is the file itself, without its level (player.sim pins both). If that MP4 won't decode either, the song is
  skipped, as any song that won't play (a decode error isn't retried). And Safari's readout then says "sent as FLAC"
  for that one song though an MP4 came (the branch's `setWrapped`).
- The **refused set is by variant** (`variantOf`): a levelled CD song's variant is its id - so a refused levelled copy
  has the song asked for as the FILE ITSELF (no wrap even in Safari), where a refused resampled copy falls back to
  "Original"'s address. As the spec has it ("the file as it is"), and Safari's seeks in that one song can land off.

#### The server

- **Routes** (src/routes/navidrome.py): `/stream`'s `level: Literal["album","track"]` (DECLARED), needing format=raw
  and a wrap (400 "level needs format=raw and wrap=mp4 or wrap=fmp4: only a copy deadwax makes can be levelled");
  `/scrub` takes `level` (SCRUB_PARAMETERS). New: `GET /level/{song_id}?level=&max_rate=` (Info's answer, from
  what is measured - never measures or makes: `state` measured/measuring/unmeasured/not_levelled, `why`, the gain,
  wanted, loudness, peak, held, songs, measured_songs) after `_theirs()`; `POST /level/album/{album_id}` (202, an
  album page's "about to be played": a getAlbum AS THE ASKER, then `Levels.warm()` - `measuring`, or `busy`, dropped,
  while another album measures; `not_levelled` without the libraries or a cache folder). Both user routes, in
  test_logins.py's ROUTES and test_there_is_no_general_proxy's list - deadwax's own answers, not relays. The walk
  of test_player_as_you.py covers them: the asker's getSong/getAlbum FIRST, then the levels' reads as the shared
  account (LEVEL_CALLS); `src/levels.py` joined SHARED_ACCOUNT_USES, with its reason.
- **The plan** (src/resample.py): `ResamplePlan` is the plan of any copy deadwax makes, keeping its name: `level` and
  `gain_db` (rounded down to 0.01), defaulted. `material()` is EXACTLY the old list without a level (every resampled
  file keeps its key) and adds `[LEVEL_FORMAT_VERSION, level, f"{gain_db:+.2f}"]` with one - the gain in the key BY
  VALUE. `X-Deadwax-Resampled` only when resampled (`plan.resampled`); `X-Deadwax-Level: album -7.42` on every answer
  of a levelled copy. A levelled-only copy has `out_rate == source_rate`: `_level_pass()` reads float64 blocks and
  quantises through `_quantise()` - the resample pass's own `np.rint(y * scale)`, over check, clip, `<< 8`, factored
  out byte for byte (`scale = _FULL * gain`, the same float product as before). Resampled and levelled: `_pass` with
  the level's gain in place of HEADROOM_DB's. An over (the peak limit makes it impossible unless a measurement was
  wrong) is done again lowered by exactly enough, said as a WARNING. Always 24-bit, undithered, deterministic; 0.00
  dB is the source's samples shifted - so every levelled song of an album is 24-bit and `joins()` keeps them in one
  stream.
- **The measurement** (src/loudness.py): BS.1770-4 / EBU R128 as ReplayGain 2.0 uses it - K-weighting re-derived per
  rate (libebur128's coefficients), the biquads run once over a quarter-second impulse in plain Python and applied as
  float32 FFT overlap-add of the response cut at -120 dB (2362 taps at 44.1 kHz, 2561 at 48), segments cut at the
  overlap-add's own block boundaries however the input arrives (the same bytes for any read size - pinned); 400 ms
  blocks every 100 ms from 100 ms segment sums; mono as dual mono; libebur128's 1000-bin histogram (edges and centre
  energies as it computes them, the relative gate from centres, bins at or above it); hi-res decimated by its whole
  ratio with soxr HQ for the loudness, the peak the native samples'. `measure_file` streams BLOCK_FRAMES at a time,
  never holding a song, a stop event once a block.
- **Checked** (tests/test_loudness.py): the FFT against the biquads sample by sample on 5 s of noise at 44.1/48/96
  kHz - residual ~1.0e-6 of the signal, the -120 dB cut's own energy (bound 2e-6; the spec's "< 1e-6" is the cut
  itself, float32 adds a hair); EBU 3341 cases 1-5 within 0.1 LU at 44.1, 48, 96, 192 kHz (histogram mode reads the
  -23 tones as -22.95 or -23.05: a bin's centre), and through measure_file decimated at 96/192; histogram vs the
  exact block computation on 20 music-like stretches within 0.05 LU (0.034 at most - a few seconds of a TONE exactly
  at the relative gate can flip 0.2 LU, the histogram mode's nature; the spec's "random signals" test was written
  over music-like ones); pooled songs vs the whole album within 0.05 LU (the spec's "bin for bin when split on 100
  ms" can't hold: the three blocks straddling each join and each song's filter start are the whole's alone);
  mono = both channels, +3.01 dB over one; silence; the gain rule; the 24-bit bound over every peak; streamed in
  4096 = whole; the BLOB.
- **The gain**: `REFERENCE_LUFS - loudness`, held under `FULL_DB - peak_db - reserve` (FULL_DB the largest 24-bit
  sample; the reserve HEADROOM_DB when the copy is resampled - for album gain when ANY of the album's FLAC songs is
  one deadwax resamples under "Up to 48 kHz", WHATEVER cap the asking song carries (`_album_reserve()`, after review:
  see below)), rounded DOWN to 0.01 (`floor(round(g*100, 6))/100`, guarded never to pass the limit);
  `held = limit < wanted`; silence asks for nothing; no cap on a positive gain but the peak.
- **Where kept**: store.py's `loudness` table (audio_key, algorithm, peak, histogram BLOB of `<HI` pairs, blocks,
  seconds, measured_at), `loudness_get`/`loudness_put`, in /config. Keyed by the AUDIO: `s:` + sha256(STREAMINFO's
  34 bytes), or `v:` + Version.key for an all-zero MD5. In memory: LEVELS_KEPT measurements; the resolved gain per
  (version key, level, cap) for VERSION_SECONDS and kept beyond as what a failed lookup falls back on.
- **When measured** (src/levels.py): on demand - the song (track) or every FLAC song of its album, downloaded into
  the cache folder (`<key>.<token>.measure`, room found by clearing songs played longest ago if the disk is short,
  never one playing; the leftover sweep clears old ones), MEASURES_AT_ONCE (cpu-1, 1-4) at a time in worker threads,
  single flight per song and per album, one album at a time, shielded and finished even when every asker has gone;
  `LEVEL_WAIT_SECONDS = 50` (20, `LEVEL_WAIT_HIRES_SECONDS`, for a copy resampled too or above 48 kHz; 5,
  `STALE_WAIT_SECONDS`, with a gain kept from before) past which that answer is the song as it is, said once ("plays
  as it is this time"), the URL remembering the file it was served so a carry-on stays on it (`_mark(... or level is
  not None)`). Part A: the
  album page POSTs once its songs are in hand (not under Off, only with a FLAC among them). Part B: the poller's
  `_measure_later` after a real filing - each filed FLAC (companions and duplicates aside) keyed by the STREAMINFO read
  from its own head, measured on a thread of its own at nice 10 (a pooled thread would keep the nice), passed over when
  already kept or keyed by version. **Part C (the idle pass over the library) was cut**, as the spec allowed: A and B
  level everything, old albums measured on their first play.
- **The cache** (src/player_cache.py): `answer()`, `answer_fragmented()` and `answer_window()` take `level`; with one,
  `_plan()` asks `AlbumContexts.copy_plan()`, else `albums.plan()` exactly as before - so under Off none of the new
  code runs. `_answer_key(song, cap, level)` is today's for no level. `_kept_size` is the estimate for a levelled
  copy at its own rate (24-bit: bigger than a 16-bit source - not capped at the source's size as a resample is), and
  a make's disk room is judged at `max(size, kept)` (the same as before for every resampled song). `_levelling()`:
  numpy and soundfile (soxr only for a hi-res song's decimated loudness); missing, `level` is ignored, said once.
  No cache folder: nothing levelled, the level route says so.

#### Off is today's path - how it was proved

- A script ran the same 169 requests (relayed, wrap=mp4 and fmp4 with and without max_rate and four ranges, the
  turntable window with and without the cap) over a CD album, a 24/192 album, an MP3 and a 20-bit FLAC against
  BOTH the pre-change server (git 3458dbf's src, archived) and this one: status, body hash, ETag and every deadwax
  header identical, and the cache folder the same.
- tests/test_normalization.py pins the ETags by the formulas of 2.0.0-player.61 (Version.key, the fragmented key,
  the resampled key with the plan's material as it was), with nothing measured and nothing kept.
- player.sim.cjs: five sessions of an unlevelled queue (Chromium and iPhone, one element; iPhone and Chromium
  streams; a hi-res album under 48 kHz) - every address and range in order - recorded from the pre-change engine
  (the same scenarios, compiled from 3458dbf's ui/src) and pinned.

#### Measured here (Ryzen 7 PRO 5750GE; the streamed implementation, not the prototype)

| work | here |
|---|---|
| measure a 4-minute 16/44.1 song | 0.74 s (324x) |
| ... 24/96, 24/192 (loudness decimated to 48 kHz) | 1.03 s, 1.42 s |
| 12 x 4-minute CD songs | 7.7 s on 1 worker, 4.3 s on 2, 2.9 s on 4 |
| levelled make, 4-minute 16/44.1, 24/96, 24/192 | 0.54 s, 1.24 s, 2.44 s |
| size, 16/44.1 -> levelled 24-bit | 15.5 MB -> 24.4 MB (1.57x); 24/96 43.3 -> 39.8; 24/192 54.5 -> 48.4 |

The prototype's loudness of the same files agrees (24/96 and 24/192 decimated -24.786 LUFS).

#### On the page

- You > Playback: `app/NormalizationChoice.tsx`, a radio group like QualityChoice (its own state,
  `deadwax-player-normalization`, Automatic unless it says otherwise - state/persisted.ts), after Maximum quality
  with its footnote; the section's last note "All five are kept on this device..."; QualityChoice's "with
  Normalization off they are 3 dB quieter". Normalization's own root carries `.app-choice-follows` (a token's
  margin above it: no note sits between it and Maximum quality) - review found the first try, `.app-choice +
  .app-choice`, spaced Getting albums' three choices apart too; app-rules.sim pins it.
- Info > Debug: a **Normalization** row after Resampled (`describeLevel()`; the route's `plain` state, since review:
  "Played as it is this time - its album was still being measured"), from `useLevelAnswer()`
  (app/useInfoDetails.ts: only while Info is open, through latestOnly, again every 5 s while measuring); Resampled
  without ", 3 dB quieter" for a levelled song (kept when deadwax says it played unlevelled); **Sent as** says
  24-bit for a levelled copy (not in the spec - it said the file's 16 bits of a copy that is 24).

#### Found in review, and fixed

Nineteen findings, confirmed by skeptics; merged, eleven changes:

- **An album measured already waited behind another being measured** (`_measure_album` took the one-album gate
  before looking): its next song played unlevelled after the whole wait. Now it lists and checks what is known
  first, and takes the gate only to measure; `warm()`'s "busy" is the gate as before. And a gain kept from before
  (past VERSION_SECONDS) is answered within `STALE_WAIT_SECONDS` while it is worked out again, not after 50 s.
- **One album at two gains when a song couldn't be looked at just now** (`_album_songs` dropped a song whose
  STREAMINFO read timed out, and the rest were pooled): `_album_songs` now says whether it has the WHOLE album; a
  part is looked at again once, at once, and still in part the song plays as it is this time - never a gain pooled
  from part of the album. The rule that a song whose MEASURING failed just now leaves its album unlevelled was
  unpinned; pinned now.
- **A mixed-rate album at two gains** (the album's resample reserve followed the ASKING song's cap, and the page
  sends `max_rate` only with a song it resamples - so a CD song of a 24/96 album came uncapped and got no reserve):
  the reserve is now the album's, `_album_reserve()`: HEADROOM_DB when any of its songs is one deadwax resamples
  under 48 kHz, whatever cap is asked. The page-side fix (the cap on every levelled FLAC under 48 kHz) would have
  changed addresses player.sim pins, which this change may only add to. The cost, a deviation from the spec: under
  "Original", a PEAK-HELD album with a hi-res song in it is levelled up to 3 dB quieter than it could be (nothing
  is resampled there). Only the gain changes; nothing clips, nothing is lost. The old test asked the CD song with a
  cap the page never sends; it now asks each song as the page does.
- **The 50 s wait plus a hi-res make no longer fit the page's 60 s** for a first head: a copy resampled as well as
  levelled, or levelled above 48 kHz, waits `LEVEL_WAIT_HIRES_SECONDS` (20) for its gain, leaving the rest to the
  make (a hi-res resample can run most of a minute on a NAS).
- **Every song change waited 50 s while a big album was still being measured** (each song its own wait): once a
  request has waited the whole wait for its album, the album is `_overdue` - its other songs are answered as they
  are AT ONCE until its measurement ends (cleared with the album task).
- **Info said "Album, -7.42 dB" for a song that played as it is** (after the wait the measurement carried on, and
  the route said "measured"): what was answered as the song as it is is remembered (`_plain`, for the song's length
  and PLAIN_MARGIN_SECONDS) - the route answers `state: "plain"`, Debug says "Played as it is this time - ...", Sent
  as and Resampled read as unlevelled, and the turntable's and visualizer's windows of it are cut as without the
  level (`levelled(..., window=True)`: the window follows what is heard). A new play of it levelled clears it.
- Tests that couldn't fail: decimation (now spies on the meter's rate), the resample's room by song and Info's copy
  of the reserve rule, the Off window's samples (now compared; the docstring names what pins the resampled bodies),
  an old algorithm's row replaced, a filed song measured once, an unmeasurable song tried once.
- The `.app-choice` spacing (above), and the docs that said Chromium gets the FLAC as it is and the visualizer adds
  nothing to the cache - true now only with Normalization off.

#### Found in the second review, and fixed

Five findings, confirmed by skeptics:

- **A FLAC song Navidrome can't serve kept its whole album unlevelled** (its 4-byte look answered with a 404 or a
  500 - a file gone before a rescan, a permission error): `_album_songs` counted it as "not looked at just now",
  so every song of the album played as it is, and Info blamed a measurement. Now only a brief failure makes the
  album not WHOLE - its STREAMINFO not read in time (CannotPlan), Navidrome broken off (httpx.TransportError, which
  until then escaped the look and failed the listing), or a 429 or 503 (`BRIEF_REFUSALS`); any other error from
  Navidrome leaves the song out of the pool like one deadwax can't read (it can't be played either).
- **Album pages opened in quick succession both queued a whole album** (`warm()`'s "busy" was the gate alone, and
  since the first review the gate is taken only after the album is listed - hundreds of ms on a NAS): a play
  behind both could pass its wait. `warm()` now drops a page's warm-up while ANY album's measurement is live,
  listing included; a play's on-demand measurement still queues as before.
- **A long CD song whose levelled copy is over WRAP_MAX_BYTES went to Safari as the bare FLAC** (the 24-bit copy
  is about 1.5 times the file, so a FLAC between about 341 and 512 MiB fit as a plain MP4 and not levelled):
  `levelled()` now judges the copy's size FIRST (`_too_big()`, the same size the cache judges, whatever the gain)
  and, too big, gives back the plan without the level - the song goes exactly as Off sends it (plain MP4, plain
  fragmented MP4, plain windows), nothing is measured for it, it's said once in the log, and Info's route answers
  `not_levelled` with the cache's own words ("levelled it would be about N MiB, more than the 512 MiB...").
- Rules the notes state that no test pinned: the disk room judged at the copy's size (`max(version.size, kept)`),
  Info's route never pooling part of an album (`whole`), `_album_reserve()` keeping no room without soxr, and the
  single flight on resolving a gain - each pinned now, and each broken once to see its test fail.
- The scrub route's docstring, garbled where the `level` sentence went in.

#### Known limits (left, for a later engine change - James to decide)

- **With Gapless off (the iPhone's default), a levelled copy the browser can't decode is SKIPPED**, not played as
  the file itself: the engine's seven lines don't reach `onFailure()`, which retries a load failure once on the same
  address and skips a decode failure (`afterFailure()`, lib/playQueue). Only the stream paths add to `refused`. If
  24-bit FLAC in MP4 doesn't decode on the iPhone, every levelled CD song is passed over: Off is the way out.
  player.sim pins it as a KNOWN LIMIT (it flips when fixed). The fix: `onFailure()` adding the levelled variant to
  `refused` and reloading `addressOf(track)` - an engine change past this one's lines.
- **A levelled copy refused once poisons the song's Off address for the page session**: `variantOf()` of a song
  that isn't resampled is its bare id - the same key that means "deadwax won't repackage it as it is" - so after a
  415 or a decode failure of its levelled copy, Off asks it as the raw FLAC (no MP4 in Safari, seeks off) and never
  streams it until a reload. The fix: refusals keyed by level (`${id}~${level}`), an engine change.
- **A levelled copy the BROWSER couldn't decode still has its turntable windows asked at the level, and Info saying
  its gain**: the refused set is the engine's own, which Turntable, Visualizer and Info can't read. (A copy deadwax
  itself refused - a damaged file, say - has its windows cut as the song as it is, since the cache knows.)

#### Not verified - James's phone and server

24-bit FLAC in MP4 and fragmented MP4 on the iPhone for ordinary CD songs (now nearly every song); how long a first
play waits on the NAS over WireGuard, and whether the album page's warm-up hides it; whether -18 LUFS is loud enough
on AirPods; the lock screen and AirPlay with levelled copies (nothing in them changed).

#### Later: the 3 dB under Original (James, 2026-10-23)

Asked whether a peak-held album with a hi-res song in it may be levelled up to 3 dB quieter under "Original" (the
album-wide resample reserve above), James: "3db quieter is not ideal but it will work. Let's note that for later
development." So it stays for now. The fix when it's taken up: the page sends the cap (`max_rate`) with every levelled
FLAC under "Up to 48 kHz" - not only with a song it resamples - so the album's reserve can follow the device's actual
setting and drop under "Original". That changes stream addresses `ui/test/player.sim.cjs` pins, so it is an engine
change of its own (an address change in `streamWrap`/`api.ts`'s builders and the sim's recorded addresses), to be
asked for as one.
