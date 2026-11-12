# Phase 1 spec: the audio engine (app 0.2)

Scope: what DeadwaxAudio (and the parts of App/ and DeadwaxCore that feed it) must change for Phase 1 - gain, Up
Next edits under the engine, route changes and media resets, the streaming cache, seeks into what hasn't arrived,
the position everything reads, Shuffle/Repeat, and a queue put back paused. Read-only scouting; nothing in the repo
was changed.

**Baseline.** Branch `ios` = main at **2.1.0 (`1199330`)**. Read in full: `ios/DeadwaxKit/Sources/DeadwaxAudio/
{PlaybackEngine,StreamSource,StreamFetch,PCMSource}.swift`, `Tests/DeadwaxAudioTests/EngineRenderTests.swift`,
`ios/App/{AppModel,AudioSessionController,NowPlayingController,SongFiles}.swift`, Core's `LaneTimeline`, `StartPoint`,
`PlayQueue`, `Formats`, `Models`, `Routes`, `notes/ios.md` (all of it), the plan's sections 2-5 and 7. Web files read as
they are now: `ui/src/lib/upNext.ts` (changed since 85aa7be only by 7bb0a85 2.0.14, e04ac43 2.0.9, 92a58dc 2.0.7,
6452ff3 2.0.5 - words and Now Playing's buttons, no rule), `ui/src/player/usePlayer.ts` and `streamSource.ts` (no
commits since 85aa7be touch the edit/replan paths), `ui/src/lib/loudness.ts` and `player/levelling.ts` (2.0.1 changed
only NormalizationChoice's notes), `ui/src/lib/playQueue.ts` (listen rules), `ui/src/lib/streamPlan.ts:488-499`.

**Binding updates applied here**: Choice 14 is superseded - a pause stops the output at once (`idleStopSeconds = 0`,
PlaybackEngine.swift:81; notes/ios.md "The pause the lock screen didn't see"); the app is 0.2; the web app is followed
as it is at 2.0.15.

**The server**: nothing in this area needs the server. The gain *values* come from the loudness route, which goes on
main as 2.1.1 and is merged into `ios` (memory: server additions as 2.1.x patches; James's server runs
`:experimental`). Every engine change below is testable offline without it.

**Other Phase 1 specs this one meets** (same scratchpad, `specs/`): `levels.md` (the gain decision and `GainedSource`),
`upnext.md` (section 7, `replaceUpcoming`), `resume.md` (section 7, `restoreQueue`), `plays-words.md` (listen rules,
Debug rows). Where this spec disagrees with one, section 9 says so and why.

---

## 1. The engine today - the map an implementer works from

### 1.1 Types and settings (PlaybackEngine.swift)

| what | lines | today |
| --- | --- | --- |
| `EngineTrack {song, open: (StartPoint) throws -> PCMSource}` | 9-17 | no key, no gain |
| `EngineState {phase, index, fileRate, fileChannels, outputRate, lastStartLead}` | 20-43 | `Phase`: idle, loading, playing, paused, ended, failed(String) |
| `Settings.bufferSeconds` | 74 | **0.5** - one scheduled buffer (at least 1024 frames, :500) |
| `Settings.aheadSeconds` | 76 | **2.0** - kept scheduled past what is rendered (:491) |
| `Settings.startSeconds` | 78 | **1.0** - scheduled before a node starts from silence (`ready`, :728-730) |
| `Settings.idleStopSeconds` | 81 | **0** - a pause/end/stop/failure stops the output at once (`armIdle`, :938-950) |
| `Settings.changeSettleSeconds` | 85 | **0.3** - a route change waits, so the app's pause wins (:931-935) |
| `Settings.offline` | 87 | manual rendering format (tests) |
| `startLead` | 94 | app sets `outputLatency + ioBufferDuration` (AudioSessionController.swift:64-67) |
| retry delay | 767 | **0.05 s** after a `.waiting` read |
| `Lane` | 105-162 | node, songs' `format`, `nodeFormat` (output rate), `converter?` (mastering, `.max`, prime `.normal`, :449-458), `timeline`, `pending`, `started`, `nodeFrames`, `holding`, `lastSample`, `renderStart` |
| `Feed` | 176-201 | `index` (into `tracks`), `source`, `start`, `startFrame`, `decoded`, `lane`, `entry`, `parked` |
| `entryTrack: [entry id: track INDEX]` | 213 | written :559, :791; read :736, :808, :836 |

### 1.2 Calls and paths

- `play(tracks, from:, at:)` :250-256 (wantsPlay = true; `.seconds` when at > 0). `replaceTracks` :260-262 **only
  assigns `self.tracks`**. `pause` :264, `resume` :268, `skip(to:)` :273, `seek(to:)` :279-284 (`.seconds` into the song
  `heard()` names), `stop` :286-295, `position()` :298-303 (`queue.sync`, `(index, seconds)`), `rebuild()` :306-325.
- `begin` :383-402: `reset()`, `current = index`, `held = (index, start)`, opens `tracks[index].open(start)`, then
  `ensureRunning()` **even when paused** (:397), publishes `.loading` or `.paused`, `armIdle()` when paused, `pump()`.
- `pump` :488-528 decodes until the feed's lane holds `aheadSeconds` past `sample(of:)`; `.waiting` -> `scheduleRetry`;
  `.end` -> `endFeed`; a refused `schedule` parks the buffer (:516-523).
- `schedule` :535-571: flushes the lane scheduled last when another format begins (:538-541); refuses a song that
  would begin on a busy lane behind another (:542-545); `conform` (:547); begins the timeline entry and
  `entryTrack[id] = feeding.index` (:553-561); converts or enqueues.
- `endFeed` :661-685: closes the entry, opens `tracks[ended.index + 1]` from `.beginning` (**by index**), flushes the
  ended lane at the queue's end (:669) or when the next song's format is known to differ (:677-679).
- `startLanesIfReady` :689-714 (never on a stopped engine, :693), `playFromSilence` :717-725, `time(whenEnds:)`
  :741-756, `played` :772-829 (ran dry mid-song :781-797; lane done :798-821; `current` follows `heard()` :823-825),
  `heard()` :834-842 (node sample, else `lastSample`, else `held`, else `(current, .beginning)`), `pauseNow` :844-857,
  `resumeNow` :859-887, `resumeFrom` :889-902, `configurationChanged` :904-936, `finish` :952-961, `fail` :963-970,
  `publish` :972-990.

### 1.3 The app around it

- `AppModel.tracks` (AppModel.swift:273-283): a downloaded copy when asked and present, else `SongFiles.streamSource`.
- `AppModel.changed` :305-317 moves `queue` to `state.index` (an INDEX, delivered later on main), prefetches
  `queue.songs[next]` on every state change (:313-315); `tick` :326-333 reads `position()` every 0.5 s and keeps it only
  if `at.index == queue.index`; `showNowPlaying` :335-349 sets title, elapsed, rate 1/0, queue index and count.
- `AudioSessionController` :42-48: media services reset -> `configure()` (category only) -> `onReset` ->
  `engine.rebuild()` (AppModel.swift:68). No `setActive(true)`.

### 1.4 The tests that pin it (EngineRenderTests.swift, 13, macOS only)

`aJoinIsTheTwoSongsLaidEndToEnd`, `positionFollowsTheSongHeard`, `anotherFormatPlaysOnItsOwnLaneAfterTheFirst`,
`aShortSongInAnotherFormatPlaysBetweenNotOver`, `aCallGoesOnFromWhereTheSongWas`,
`aPauseStopsTheOutputAndPlayGoesOnFromWhereItWas`, `aNewRoutePlaysOnFromWhereItWas`,
`aRouteChangeThatPausesWinsOverPlayingOn`, `playAfterAFailureOrAStop`, `aSeekBeforeTheSongIsHeardIsAtItsOwnRate`,
`theRateConversionMeasured`, `aTwentyFourBitFileDecodesExactly`, `aStreamDecodesWhatTheFileDoes`. Helpers:
`MemorySource` :14-42, `GrowingBytes` :45-63, `signal` :66-74 (multiples of 1/32768, exact), `offlineEngine` :76-84
(**`aheadSeconds = 60`**, `startSeconds = 0`, `bufferSeconds = 0.1`), `tracksFromWhereAsked` :95-107, `firstDifference`
:123-137 (never `==` on sample arrays - a failed `==` killed the test process). Completions are handled only between
`renderOffline` calls: render a piece, `Thread.sleep(0.01)`, `settle()` (as :233-237). Every new test below follows
these rules; tests that need completions mid-song set `aheadSeconds` small (0.3) themselves.

---

## 2. (a) Per-song gain

### 2.1 Today

Nothing multiplies (notes/ios.md: Phase 0 is "Off"). The plan (section 3 "Gain") wants `vDSP_vsmul` by `10^(gain/20)` on
each decoded buffer before scheduling, any sign, fixed for the song, album gain one number for the album, Off no
multiply.

### 2.2 Where the multiply goes - in a source wrapper, not in `schedule()`

Recommended (and what `levels.md` 4.3 already plans): **`GainedSource: PCMSource`**, a new file
`ios/DeadwaxKit/Sources/DeadwaxAudio/GainedSource.swift` (inside `#if canImport(AVFAudio)`, `import Accelerate`), so it
is compiled and offline-tested on macOS rather than sitting untested in App/.

```swift
public final class GainedSource: PCMSource {
    public let factor: Float                 // the linear multiplier, never 1.0 (see wrap)
    let inner: PCMSource
    public var format: AVAudioFormat? { inner.format }
    /// nil, or a factor of exactly 1.0, gives back `source` ITSELF: no wrapper, no multiply.
    public static func wrap(_ source: PCMSource, factor: Float?) -> PCMSource
    public func read(maxFrames: AVAudioFrameCount) throws -> PCMRead   // .frames(b): each channel in place, then b
    public func close() { inner.close() }
}
// per channel c of a non-interleaved Float32 buffer, stride 1:
//   var m = factor; vDSP_vsmul(data[c], 1, &m, data[c], 1, vDSP_Length(buffer.frameLength))
```

Why here and not in `PlaybackEngine.schedule` (:546-547):

- **Exactly once per sample on every engine path.** A buffer refused by `schedule` is parked (:516-523) and scheduled
  later without a new read; a lane that runs dry keeps its feed (:781-797). A multiply at read time is done once for
  each; a multiply inside `schedule` must sit after the refusal (:542-545) or a parked buffer is multiplied twice.
- **Before the lane's converter** (`convert`, :593-626): the gain is applied at the file's own rate, so a converted lane
  converts the gained samples; the converter is linear, so the order changes nothing but rounding.
- **`PlaybackEngine.swift` needs no change for gain** (`levels.md`'s claim, checked): `EngineTrack.open` returns the
  wrapped source.

**The in-place contract** (add to the protocol's doc, PCMSource.swift:19-26): *a read returns a buffer the caller
owns; a source never reuses one it has returned.* True today - `FileSource.read` allocates per call (:61),
`StreamSource.read` (:91), the tests' `MemorySource` (:30) - and `GainedSource` depends on it.

### 2.3 The rules the wrapper must keep

1. **nil = no multiply at all.** `wrap(source, factor: nil)` returns `source` (`===`). Off, a non-FLAC song, "played as
   it is this time" and silence (a nil multiplier, `levels.md`) all reach it as nil. The output is then the decode
   bit for bit on a same-rate lane (pinned today by `aJoinIsTheTwoSongsLaidEndToEnd` at 44.1 kHz).
2. **A factor of exactly 1.0 is also no wrapper** (0.00 dB: `x * 1.0 == x` in IEEE, so the samples are the same either
   way; skipping it keeps "Off-like" songs off the multiply). Debug must still say the gain from the decision, not
   from whether a wrapper exists.
3. **The factor is a Float computed once**, in Core (`levels.md`'s `gainMultiplier(gainDb)`:
   `Float(pow(10.0, gainDb / 20))`, Double then one rounding), so the same dB is always the same Float everywhere. The
   engine never computes it.
4. **Fixed for the queue entry.** The decision (and so the factor) is made once per entry and reused by every later
   open of that entry: a seek, a pause's resume (`resumeFrom` -> `begin` re-opens, :889-902), a route change
   (:928), a failure's retry, a rebuild. The app keeps it by the entry's key (section 4), never recomputes it from the
   book on a re-open. A changed setting applies from the next thing queued.
5. **Album gain is one number for the album** (one factor for every album-level entry of it), so a join is the old
   join scaled: no step.
6. **No clamp, no limiter.** `gain_for` (src/loudness.py:403-424) holds `peak * m` at or under the largest 24-bit
   sample (`FULL_DB`, :63); the mixer runs at unity in float. The only place a sample can pass 1.0 is a lane's rate
   converter ringing on a peak-held song (plan R10) - measured by test 2.7 #7, not limited.
7. **Never mid-song.** No path changes the factor of a source being read.

### 2.4 Where the app wires it

`AppModel.tracks` (AppModel.swift:273-283) becomes (Phase 1 has no downloads; Phase 2 puts the downloaded copy first):

```swift
EngineTrack(key: entry.key, audio: entry.audio, song: entry.song) { start in
    let source = try files.streamSource(for: entry.song, client: client, start: start)   // cache file or stream
    return GainedSource.wrap(source, factor: decisions.factor(for: entry))              // nil under Off
}
```

`decisions.factor(for:)` is `levels.md`'s once-per-entry decision (a lock-protected read; the closure runs on the
engine's queue). The first-song gate (`levels.md` 4.3: `.waiting` while the album is measuring, at most 20 s) is
another wrapper around the same source; the engine already shows `.loading` and retries every 0.05 s (:509-512, :767).

### 2.5 Tests (EngineRenderTests, offline)

1. `noGainIsTheDecodeBitForBit` - `GainedSource.wrap(s, factor: nil) === s`; `wrap(s, factor: 1) === s`; two songs at 44.1
   kHz render to `a + b` exactly from frame 4096 (the start ramp) to the end.
2. `aGainIsOneMultiplyPerSample` - factor `m = gainMultiplier(-6.02)`; the render equals `a.map { $0 * m }` exactly
   (vDSP's single-precision multiply is IEEE-rounded like Swift's `*`; inputs are multiples of 1/32768, no denormals).
3. `anAlbumAtOneGainJoinsExactly` - three songs, one factor: `(a + b + c) * m` exactly across both joins.
4. `aParkedBufferIsMultipliedOnce` - `aShortSongInAnotherFormatPlaysBetweenNotOver`'s layout with factors m1/m2/m3:
   the third song is `third * m3` exactly (doubled it would be `m3 * m3`).
5. `aGainStaysThroughAPauseAndANewRoute` - pause/resume, then `systemStopped(change: true)`: the output after each is
   `song * m` from the frame left (`tracksFromWhereAsked` returning wrapped sources whose factor comes from a fixed
   per-key table, as the app's decisions do).
6. `aPositiveGainIsNotClipped` - `m = gainMultiplier(+6.02)` over a signal peaking at 0.457: exact, peak 0.912.
7. `theConverterOvershootMeasured` (prints, bounds only a broken result) - a peak-held signal (full-scale 11025 Hz at
   44.1 kHz phased to put inter-sample peaks between samples) through the 44.1 -> 48 kHz lane: print the largest output
   sample. This is R10's number, now measurable because the conversion is the app's own.

Core (Linux): `levels.md` 4.5's `gainMultiplier` vectors cover the factor.

---

## 3. (b) Up Next edits under the engine: `replaceUpcoming`

### 3.1 What happens today when the list after the song heard changes

`replaceTracks` (:260-262) swaps the array and nothing else. Everything the engine holds refers to tracks **by index**
(`Feed.index`, `entryTrack`, `current`, `held`). Lib/upNext's invariant (upnext.ts header; upnext.sim.cjs runs it over
2,000 random runs) keeps `tracks[0...index]` and `index` exactly, so indices up to the song heard stay right. After it:

- **The heard song's decode hasn't ended** (most of a song): nothing of the next song is open. `endFeed` (:667) later
  opens `tracks[index + 1]` of the NEW list. Correct.
- **The heard song's decode has ended** - which happens once its last buffer is scheduled, so within about
  `aheadSeconds` (2 s) + one buffer (0.5 s) of its end - the feed is already the OLD next song, maybe with up to 2 s
  of it scheduled (same lane, straight after the heard song; or another lane, already started with `play(at:)`). Then:
  1. the old next song still plays;
  2. its entry maps to index `i + 1`, so `EngineState.index` says `i + 1` and the app shows the NEW list's song there -
     the screen and the lock screen name a song that isn't playing;
  3. `endFeed` then opens `tracks[i + 2]` of the new list: the new next song is skipped altogether.
- **The heard song's decode ended with no next song** (the queue's end): `endFeed` set `feed = nil` (:668-671) and
  nothing ever looks again. A Play Last, or Repeat All's or One's top-up, landing then is **never played**; the
  queue ends (`finish`), and play after `.ended` restarts the heard song (`resumeNow`, :861-864), not the added one.
  Reachable whenever a top-up comes late: a song under ~4 s (TOP_UP_HEARD_S = 2 s, or half the song) can have its
  decode end before its top-up.
- `AppModel.changed` prefetches `queue.songs[next]` only on an engine state change (:313-315): after an edit the new
  next song's stream starts only at the next change.
- `EngineState.index` arrives on main later than the engine moved; an edit made from the app's stale index keeps the
  wrong prefix.

### 3.2 What can and can't be undone

An `AVAudioPlayerNode` can't drop some of its scheduled buffers: `stop()` drops them all, the heard song's included.
So an entry with **any frames scheduled on any node** is **committed**. Everything else - the feed's source, a parked
buffer, an entry begun with no frames, a feed whose stream header hasn't arrived - can be let go without touching any
node. The web cuts its MSE buffer up to the playhead (streamSource.ts:327-371, `replan`; player.sim.cjs:4797 "Play Next
in a song's last seconds": song 2's frames taken out 8 s before the join); the phone can match it except in the last
~2.5 s of a song.

### 3.3 The new call (aligned with `upnext.md` section 7's name)

```swift
/// Up Next changed what comes after the song heard. Sync on the engine's queue (like position()).
/// True: the engine follows `tracks` from here. False: nothing changed - the app holds the edit and makes it again
/// after the next song change (the web's heldEdit, usePlayer.ts:1442-1462), against the queue as it is then.
public func replaceUpcoming(_ tracks: [EngineTrack]) -> Bool
```

`EngineTrack` gains two fields (section 8): `key: Int` (Up Next's `Mark.key`, unique in the queue; what the engine
reports) and `audio: String` (what the entry decodes to: `"\(song.id)|\(level ?? "off")"` - two entries with the same
`audio` decode to the same samples at the same gain).

Algorithm, on the engine's queue:

1. **The song heard** = `heard()`'s entry (or, nothing heard yet, the feed's or `held`'s). Find it in `tracks` by
   **key**; if absent, or present with another `audio`, return **false** and change nothing (lib/upNext never does
   this; the web's answer, usePlayer.ts:1426-1430, is to play the new queue afresh - the app calls `play`).
2. **Walk what comes after it, in play order** (entry ids ascend in scheduling order, :554-555, across lanes; then the
   feed if its entry isn't among them): for the k-th later item, the new list's entry at `heardIndex + k` must have
   the same `audio`. Stop at the first that doesn't: the **cut**.
3. **No cut**: adopt the new list. Every kept item takes the new entry's key (Shuffle off re-keys the same songs -
   `withShuffle(off)` makes fresh marks, upnext.ts:313 - and must not cut). Return true.
4. **The cut is at a committed item** (frames on a node): return **false**. Nothing changed; the heard song untouched.
5. **The cut is at the feed** (not committed): close its source, drop its parked buffer, `feed = nil`, then open the
   new list's entry after the last kept item from `.beginning` (`endFeed`'s open, :672-674) and `pump()`. Return true.
6. **No feed, and the heard song's decode has ended** (the queue's end - 3.1's third case), and the new list has an
   entry after the last kept item: open it and `pump()`. If the heard lane still has buffers (`pending > 0`), the new
   song joins it as any next song (sample-exact if it is in time; a gap, never an overlap, if late). If the lane has
   already run out, `played` (:798-821) has called `finish()`: then `.ended` - the app's rule (web `addSongs`,
   usePlayer.ts:1478: a queue that has played out plays the songs from the first, as playTracks) takes over.
7. **Paused, asleep, or loading**: nothing is scheduled; remap `current`/`held` by key and return true.

Internal refactor this needs (mechanical): `entryTrack` maps entry id -> **key**; `Feed` carries `key`; `current` and
`held` carry the key; a `[key: index]` table is rebuilt on every `play`/`replaceUpcoming`; `endFeed`'s next is
`index(of: ended.key) + 1`; `laneHolding` (:733-738) and `heard()` (:836) look up by key. `EngineState` and `position()`
report both the key and the index in the CURRENT list, so the app never acts on an index from an older list.

**The converter on the heard lane** (converted lanes only): `endFeed` flushes the heard lane as soon as the next song's
format is known to differ (:677-679). If that next song is then cut before it is committed, and the new next song is
in the heard lane's format, it is appended after a flushed converter - a restarted filter at the join (well under a
millisecond of transient). Recommended: delete :677-679; `schedule` (:538-541) already flushes when the other format's
first buffer is scheduled, which for a FileSource is the same pump. Same-rate lanes have no converter and are exact
either way.

### 3.4 The window, and an optional refinement

With today's settings the next song is committed when the heard song has at most `aheadSeconds` (2 s) left, plus up to
one buffer (completions every 0.5 s). Edits inside it are held (one song late: a Play Next plays after the committed
song; a removal of the committed song does nothing, as the web's held edit does once its playhead has passed the
join). **Optional** (not needed for Phase 1): decode the next song ahead but **schedule** it only when the heard song
has `joinSeconds` (1.0) left - staged buffers in memory can always be dropped - halving the window. Listen first: if
held edits are never felt, don't build it.

### 3.5 Tests (offline; `aheadSeconds = 0.3`, `bufferSeconds = 0.1`, rendered in 4096-frame pieces with `settle()`)

1. `anEditBeforeTheNextSongIsCommittedPlaysTheNewNext` - A (1 s), B, C at 44.1 kHz; at 0.2 s `replaceUpcoming([A, C, B])`
   -> true; output A, C, B, both joins sample-exact (`firstDifference` from 4096).
2. `anEditOfACommittedSongIsHeldAndTheSongHeardUntouched` - at 0.85 s (B's first buffer scheduled)
   `replaceUpcoming([A, C])` -> false; output is A then B exactly; A's every sample equal to the decode.
3. `aSongAddedAfterTheQueuesEndJoins` - queue [A]; render until A's decode has ended (A's last 0.3 s);
   `replaceUpcoming([A, B])` -> true; B joins A sample-exact. Fails today (3.1, third case).
4. `theSameAudioUnderANewKeyIsKept` - B committed under key 1; the new list has B under key 7 -> true, nothing
   dropped, `position()` then reports key 7 for B.
5. `aNextSongNotYetOnANodeIsLetGo` - A at 44.1, B a 96 kHz stream over gated bytes (header not arrived); replace B by
   C (44.1) -> true; A joins C exactly on one lane.
6. `anEditWithoutTheSongHeardChangesNothing` - false; output as before.
7. `theIndexReportedIsInTheNewList` - [A, B] with A heard; `replaceUpcoming([A, X, B])`; after the join
   `position()` = (index 1, key of X).

Mirrors: upnext.sim.cjs's invariant (the app's side); player.sim.cjs:4778 "Play Next mid-song in one stream" (same
result here), :4797 "in a song's last seconds" (a documented deviation: held within the window), :4838 "remove, move
and Clear while streaming".

---

## 4. (c) Route changes and media services reset

### 4.1 Today

- **`configurationChanged`** (:904-936), on `AVAudioEngineConfigurationChange` (observer :240-244, hopped to the queue):
  `at = heard()` - the engine is already stopped, so `sample(of:)` is nil and `heard()` uses the lane's `lastSample`,
  the render position **last read while playing** (every completion's `ahead()`, and the app's 0.5 s ticker) - up to
  ~0.5 s old; then `reset()`, detach every lane node, `lanes.removeAll()`, `asleep = true`, `held = at`; not playing ->
  publish `.idle` or `.paused` (an `.ended` or `.failed` phase becomes `.paused`); playing -> `.loading`, and after
  `changeSettleSeconds` (0.3 s) `resumeFrom(held)` unless a pause/skip/seek came first (`generation`). Lanes are
  remade at `engine.mainMixerNode.outputFormat(forBus: 0).sampleRate` (:446). The mixer->output connection is never
  remade.
- **`rebuild()`** (:306-325), on media services reset: `at = heard()` (same `lastSample` fallback), `reset()` (which
  calls `node.stop()` on every lane, :427), `engine.detach` each node, old `engine.stop()`, a new `AVAudioEngine`,
  `configure` (observer moved to the new engine), `asleep = true`, `resumeFrom(at, playing:)` at once (no settle).
  The app called only `configure()` (the category), never `setActive(true)` (AudioSessionController.swift:45).

### 4.2 What is missing to go on from the exact sample

1. **The position is stale.** Going on from `lastSample` repeats up to ~0.5 s. Fix: keep with each read the host time
   it was read at (`lastRead = (frame, hostSeconds, latency)`); at the change, estimate the frame the render reached:
   `lastRead.frame + (noticeSeconds - lastRead.hostSeconds) * rate`, capped at 1.0 s of extrapolation (beyond it, use
   `lastRead.frame`) and at the entry's end. Pure arithmetic, in Core: `HeardEstimate.atStop(...)` (8.3).
2. **What was rendered is not what was heard** (section 6): the samples between the ear and the render are dropped with
   the old route. Go on from the **heard** frame: subtract the OLD route's latency, read at `lastRead` (the session's
   `outputLatency` at the notification is already the new route's). Speaker -> AirPods: ~tens of ms. **AirPlay -> the
   speaker: about 2 s skipped today** (inferred from AirPlay's ~2 s latency, unmeasured; Phase 1 check 8).
3. **The output's rate can change** (AirPlay, a USB DAC). The lanes must convert to the hardware's rate:
   `engine.outputNode.outputFormat(forBus: 0).sampleRate`, and the mixer must be reconnected to the output at that
   format (`engine.connect(engine.mainMixerNode, to: engine.outputNode, format: hardware)`) before the lanes are made;
   else iOS's output unit converts a second time after the lane's own converter. Unverified when the mixer follows
   on its own - only the phone (the readout's "-> X kHz output") shows it.
4. **Keep `.ended` and `.failed`** through a change while not playing (:916 turns both into `.paused`; play after an
   `.ended` must still restart the queue's rule, and a `.failed` must keep its words).
5. **Media reset**: the old engine and its nodes are dead; `node.stop()`/`detach` on them risk an Objective-C
   exception. Clear the lanes' bookkeeping without calling into the old nodes (a `forget()` beside `clear()`), drop the
   old engine. The app must `try session.activate()` before `rebuild()` when it meant to play
   (AudioSessionController's reset handler, :42-48). Re-publish now-playing after the first state change (it does).

### 4.3 Tests

1. `aNewRouteGoesOnFromTheFrameHeard` - offline with a test latency of 0.1 s (section 6): after `systemStopped(change:
   true)` the output goes on from `rendered - 4800` frames, sample-exact (`aNewRoutePlaysOnFromWhereItWas` stays,
   with latency 0).
2. `aNewRouteKeepsAnEndedQueueEnded` - queue played out, `systemStopped(change: true)`: phase stays `.ended`.
3. `aMediaResetGoesOnInANewEngine` - `rebuild()` mid-song: phase `.playing`, output sample-exact from the frame left.
4. Core: `HeardEstimate` - extrapolation, the cap, the entry's end, the latency subtracted (Linux).
5. Optional: `aNewRouteAtAnotherRateConvertsToIt` - a test hook that re-enables manual rendering at 44.1 kHz inside
   `systemStopped`; the song goes on at the right frame and pitch.

Offline renders have no clock: extrapolation is off when `settings.offline` is set (completions keep `lastSample`
exact there anyway, since they run before `systemStopped`'s `queue.sync` block).

---

## 5. (d) The streaming cache

### 5.1 Today (SongFiles.swift, StreamFetch.swift)

- Folder `Caches/deadwax/stream`, **deleted and remade at every launch** (SongFiles.swift:26-29). Name
  `LocalFiles.name(songID:suffix: StreamFormat.suffix(for:))` = `<id>.<suffix>` (`mp3` for a transcode; ids filtered to
  `[A-Za-z0-9_-]`, at most 128; suffix `[a-z0-9]`, at most 10; else `song.bin`).
- `fetches: [song id: StreamFetch]` in memory for the app's life, never pruned; a failed fetch is replaced at the next
  ask (:56). No fetch is ever cancelled (a skipped 1 GB hi-res song keeps arriving). `onFinish` is never set.
- `StreamFetch.start` (:43-63) **truncates** any file at the path (`createFile`, :46); ephemeral session, cookies off,
  `timeoutIntervalForRequest = 20`, a serial delegate queue. Anything but 200 fails: 401 -> `deadwax says this phone
  isn't signed in (401). Check again, and sign in.`, else `deadwax answered <status> for this song.` (:101-103).
- **Complete** = the task ended without error (:131-138). The length is never checked against Content-Length
  (`expectedLength`, :106, recorded and unused) or the song's `size`.
- `streamSource(for:)` (:38-45): the fetch's file as a `FileSource` once complete (sample-exact seeks), else a
  `StreamSource` over the fetch. No file protection set (iOS's default class, which check 6 showed works locked).
- `header(of:)` (:67-75) reads only a fetch in memory (or a download) - a song cached on an earlier launch would have
  no header for the readout's bits.

### 5.2 Phase 1 (plan section 4: `Caches/deadwax/stream/<song-id>.<suffix>`, LRU, its own limit, 2 GB)

1. **Write into `<name>.part`**; on a verified completion, `synchronize`, rename to `<name>` (atomic on APFS; readers
   holding the fetch's `FileHandle` keep reading the same inode), then mark complete. `StreamFetch` gets the final URL
   and the part URL; `fileURL` (what `FileSource` opens) is the final one.
2. **Verified** = bytes written == `expectedLength` when the server sent one, and, for `format=raw`, ==
   `song.size` when Navidrome gave one (`LocalFiles.lengthMatches`, Formats.swift:70-73). Otherwise the fetch fails with
   `The song arrived cut short (<written> of <expected> bytes).` (new words) and the part is deleted.
3. **Create the part with `.protectionKey: .completeUntilFirstUserAuthentication`** explicitly (plan section 4), so a
   locked phone keeps writing the next song.
4. **At launch**: delete every `*.part` and anything not named as the cache names files; keep complete files (do not
   delete the folder).
5. **Reuse**: `streamSource(for:)` first checks `<name>` on disk: present and (raw) its size == `song.size` when known ->
   set its modification date to now (the "last played" mark) and return `FileSource(url:start:)`. A size mismatch (the
   file replaced or retagged on the server) -> delete it and stream afresh. A transcode (`mp3`) is kept on length > 0.
6. **A partial is discarded**: a failed fetch deletes its part; the next ask streams from 0 (a `Range:` resume is
   later, with the plan's FLAC frame index).
7. **Eviction, least recently played first**, after every completed fetch and at launch: complete files only, oldest
   modification date first, until their total is at or under **2,000,000,000 bytes** (Open question 4), never a file
   of a song in use (the heard song, the next one, any with a live fetch). Deleting a file a `FileSource` still has
   open is harmless on APFS, but would refetch it.
8. **Fetches in memory**: drop an entry once complete (it is on disk now). On a `play` or skip, cancel fetches for songs
   that are neither the heard nor the next song, and delete their parts. A cancelled fetch must leave `fetches` (today
   `startFetch` would hand back a cancelled one forever, :56: `failure == nil` and never complete).
9. `header(of:)` also reads a cached complete file.
10. **Prefetch** after every `replaceUpcoming` that changed the next song, not only on a state change (:313-315).
11. Sign-out does not clear it (the audio is the store's, not the person's). Phase 2 adds the "Streaming cache 2 GB"
    and "Keep a stream's copy" settings (plan section 4's table); Phase 1 hard-codes 2 GB and keeps copies.

The pure part goes in Core (Foundation's FileManager works on Linux): `StreamCache` - names (`partName`), the launch
sweep, the reuse check, `evictions(files: [(name, bytes, lastPlayed)], limit:, keep: Set<String>) -> [String]`.
`isExcludedFromBackup` and `.protectionKey` stay in DeadwaxAudio/App (Apple-only).

### 5.3 Tests

- Core (Linux, a temp folder): `partialsAreDeletedAtLaunch`, `aCompleteFileIsReused`, `aFileOfAnotherSizeIsDropped`,
  `theLeastRecentlyPlayedGoesFirst`, `aSongInUseIsNeverEvicted`, `theTotalEndsAtOrUnderTheLimit`, `aTranscodeIsKept`.
- DeadwaxAudio (macOS): `aFetchCutShortIsNotComplete` - needs a `URLProtocol` stub, so `StreamFetch` takes its
  `URLSessionConfiguration` from the caller (default: today's ephemeral one).

---

## 6. (e) A seek past what has arrived

### 6.1 Today - it already waits

`seek(to:)` (:279-284) -> `begin(at: heard index, from: .seconds(s))` -> `reset()` -> the song's source: a complete
fetch is a `FileSource` (`framePosition = min(frame, length)`, PCMSource.swift:53 - a seek past the end is `.end`, so
the next song); otherwise a new `StreamSource(start: .seconds(s))`, which decodes from the top and drops `skip =
start.frame(at: file rate)` frames (:116-121, :190). When the bytes run out it returns `.waiting` (:114); `pump` retries
every 0.05 s (:509-512) and the phase is `.loading`; `position()` answers `held`, the target - so the scrubber and
`tick` show where the listener asked for. Exactness: `aStreamDecodesWhatTheFileDoes` (`sought`, :492-494). A failed
fetch throws through `.broken` (:101-103) -> `fail(...)`.

### 6.2 What changes

1. **A seek in bytes that have arrived waits needlessly.** `read` gives up after 64 converter fills (:95, :124) and says
   `.waiting` even though it only dropped frames - 64 x 0.5 s = 32 s of audio per call, then 0.05 s idle. A seek to
   60:00 of a long stream spends ~5.6 s in retries on top of decoding. Fix: a `busy` flag on `PCMSource` (default
   false; `StreamSource`: frames still to drop and bytes or packets in hand); `pump`'s `.waiting` branch re-pumps with
   `queue.async` at once when `busy`, after 0.05 s otherwise. The per-call cap stays, so `position()`'s `queue.sync`
   and a pause never wait long behind a decode.
2. **A fetch that completes mid-skip** should finish the seek as a `FileSource` (an exact `framePosition`, no decoding):
   `SongFiles` returns a small `CachedStreamSource` wrapper (DeadwaxAudio) that, while it has returned no frames yet,
   swaps to `FileSource(url, start)` once its fetch is complete. Optional; worth it for long hi-res songs on WireGuard.
3. **The app sends a seek on the scrubber's release** (and the lock screen's one event), never per drag step - every
   seek reopens and re-decodes from the top.
4. Not in Phase 1: a `Range:` request from the seek point (plan section 3, "Later").

### 6.3 Tests

1. `aSeekPastWhatHasArrivedWaitsThenLandsExactly` - a FLAC over `GatedBytes` (released only when the test says): seek
   to 0.75 s -> `.loading`, `position().seconds == 0.75`; release -> the render starts at frame 0.75 x rate exactly.
   (Skipped with a printed line when the Mac can't write FLAC, as :466-468.)
2. `aDeepSeekInArrivedBytesSaysBusy` - `StreamSource(bytes: all at once, start: .frame(441_000, rate: 44_100))` over
   a 12 s FLAC, `read(maxFrames: 4410)`: each `.waiting` before the seek frame comes with `busy == true` (64 x 4410 =
   282,240 < 441,000, so the first read is one), the first `.frames` starts exactly at frame 441,000; over
   `GatedBytes` with nothing more released, `.waiting` comes with `busy == false`. The engine-level wait is then
   pinned by #1.
3. Optional: `aSeekWhoseFetchCompletesUsesTheFile`.

---

## 7. (f) The position the lock screen, the scrubber and the plays rule read

### 7.1 Today

`position()` (:298-303) = `heard()` = the heard lane's node `playerTime(forNodeTime: lastRenderTime)` (the **render**
position) -> `songFrames` (:136-139, the rate ratio, rounded down) -> `timeline.locate` -> the entry's song frame ->
seconds at the file's rate. Read by `AppModel.tick` every 0.5 s (elapsed, the scrubber) and by `showNowPlaying` on each
state change (`MPNowPlayingInfoPropertyElapsedPlaybackTime`, rate 1 when `.playing` else 0; iOS runs the clock).
`EngineState.index` moves in `played` (:823-825), at a buffer's `.dataRendered` completion after the render crosses a
join. Nothing reads it for plays yet.

The render is ahead of the ear by the output's latency (one IO buffer plus `outputLatency`: tens of ms on the speaker,
more on AirPods, about 2 s on AirPlay). So today: the title and lock screen change before the join is heard; **a pause
followed by play skips that latency's worth of the song** (`pauseNow` keeps the render position, :846, and the samples
rendered but unheard are thrown away with the output); a route change from AirPlay skips ~2 s. (Inferred from the
code; the phone has never been asked - check 6's "on from the very frame" is the engine's own count.)

### 7.2 Phase 1: one "heard" position for every reader

1. **`heard()` subtracts the output's latency**: frame = `songFrames(nodeSample) - latency x songRate`, located on the
   timeline (before the first entry's start it is that entry's offset, as now). `ahead()`, `ready()` and
   `time(whenEnds:)` keep the render position: they are about scheduling.
2. **`latency`** is a new closure like `startLead` (:94): the app sets `{ session.outputLatency +
   session.ioBufferDuration }` (the same sum as the start lead; refine on the phone). Read on each position read and
   kept in `lastRead` (4.2). Offline: 0 unless a test sets it.
3. **`pauseNow`, `armIdle`, `fail`, `configurationChanged`, `rebuild`** all keep the heard frame, so play goes on from
   what was last heard - no skip, no repeat.
4. **The song change is published when it is heard**: when a completion finds the render past a join, arm a one-shot
   work item for `(latency - framesPast / rate)` seconds that publishes the new key and index (cancelled by
   `reset()`'s `generation`). The lock screen's title then changes with the sound.
5. **The queue's end lets the last samples be heard**: `finish()` stops the output after `latency + 0.1 s`, not at once
   (a pause stays immediate). On AirPods today the last ~0.2 s of an album that ends abruptly may be cut (unverified).
6. **Cross-lane joins** (another format) keep a known limit: the old lane is cleared at its last completion, so the
   new song is reported up to `latency` early there.

### 7.3 What `position()` returns

```swift
public struct EnginePosition: Equatable {
    public let key: Int          // the heard entry (Up Next's Mark.key)
    public let index: Int        // its index in the CURRENT tracks
    public let seconds: Double   // heard, in the song's own seconds
    public let length: Double?   // the entry's exact length once its decode ended ((songOffset + frames) / rate), else nil
}
```

- **The scrubber and the lock screen** read `seconds`; while a seek waits it is the target (`held`). Set the lock
  screen's elapsed again when the phase becomes `.playing` (it is, via `changed` -> `tick` -> `showNowPlaying`).
- **The plays rule** (`plays-words.md`; playQueue.ts:97-181, streamPlan.ts:488-499) counts time HEARD from successive
  readings: same key -> `listenedStep(previous, now, elapsed wall seconds, rate 1, seeked)`; a new key with no seek ->
  `splitAcrossJoin(previous, oldLength: length ?? song.duration, now, ...)`. The app sets `seeked` itself on every
  `seek` it sends (the lock screen's included); the engine's own continuations (a route change, a failure's retry) are
  not seeks. `length` gives the exact length where Navidrome's `duration` is whole seconds.
- **Resume's saves** read `seconds` (`resume.md`).
- `position()` stays `queue.sync` from main; 6.2's cap keeps the wait short.

### 7.4 Tests

1. `positionIsWhatIsHeard` - latency 0.1 s: `position()` = render - 0.1 s; the key changes 0.1 s after the render
   crosses the join (render in 1024-frame pieces with `settle()`).
2. `aPauseGoesOnFromWhatWasHeard` - latency 0.1 s, pause at render frame R, resume: the output starts at R - 4800.
3. Core (Linux): the plays rules are `plays-words.md`'s (`playqueue.sim.cjs`, `stream.sim.cjs`).

---

## 8. (g) Shuffle, Repeat and the queue changing under the engine - and a queue put back paused

### 8.1 What would break, and the rule for each

| case | today | Phase 1 |
| --- | --- | --- |
| Repeat One: copies of the heard song after it (`toppedUp`, upnext.ts:192-211; 2 ahead, `REPEAT_AHEAD`) | the same song again by index; fine | the same `audio`, new keys: a loop is a join on one lane, sample-exact; the shared fetch/cache file serves every copy |
| Repeat One/All turned on, or a top-up, in the commit window | old next plays; new list skipped (3.1) | held; made after the join against the then-current song (the web's held edit does the same past its playhead) |
| Repeat off (`withRepeat`, :244-261) removes copies/rounds after the heard song | as above | a cut, held if committed |
| Shuffle on/off (`withShuffle`, :280-334): reorders after the heard song; OFF re-keys | as above | compared by `audio`, so a re-keyed same next song is kept (3.3 step 3) |
| A top-up after the decode reached the queue's end (a song under ~4 s, or Play Last at the end) | never played | 3.3 step 6 opens it |
| The Library's Shuffle feed: pages appended (`withMore`, :484) | appended by index; fine | appended past the last kept item: never a cut |
| One lane for a whole shuffle or an endless Repeat One | `timeline.entries` and `entryTrack` grow for ever (`LaneTimeline.forget`, LaneTimeline.swift:75-77, is never called) | call `timeline.forget(before: renderedFrame)` in `played`, and drop `entryTrack` entries forgotten |
| `queue.index` the app holds vs the engine's | index-based, arrives late | key-based; the app catches up with `position()` before Next, Previous and every edit (the web's `catchUp`, usePlayer.ts:1406-1413) |
| Lock screen queue index/count (NowPlayingController.swift:50-51) | Phase 0's | Repeat's unrolled copies make them meaningless: stop setting them (`upnext.md` OQ 3) |

### 8.2 A queue put back paused (Resume), and a skip or seek while paused

Today `begin` (:383-402) opens the source and **starts the output** (`ensureRunning`, :397) even while paused, decodes
`aheadSeconds`, then `armIdle` (0 s) stops it all again: a moment of running output (iOS counts it as playing, and a
`.playback` session interrupts another app's audio) and a fetch begun for nothing. The web's `restoreQueue`
(usePlayer.ts:1680-1713; `resume.md` section 7): "Nothing here loads, fetches or plays".

- **`begin` while `!wantsPlay`**: `reset()`, set `current` and `held = (key, start)`, publish `.paused` - no open, no
  `ensureRunning`, the engine stays asleep (and stops if it was running). Play goes through `resumeNow`'s rebuild path
  (`asleep`, :868-875), which opens from `held` - `StartPoint.seconds` lands right at any rate.
- **`restoreQueue(_ tracks:, at index:, seconds:)`** = set tracks, `wantsPlay = false`, that `begin`. The app does not
  activate the session (`AppModel.play` does, :211).
- Test changes: `aSeekBeforeTheSongIsHeardIsAtItsOwnRate` must check `opens.frames.last == 96_000` **after** `resume()`
  (nothing opens while paused). New: `aQueuePutBackPausedLoadsNothing` - `restoreQueue(..., seconds: 1.5)`:
  `outputRunning == false`, no opens, `position().seconds == 1.5`; `resume()` opens at frame 1.5 x rate and the render
  starts there.

### 8.3 Debug and the log (plan R8)

- `public func debug() -> EngineDebug` (`queue.sync`): per lane `rate`, `channels`, `nodeRate`, `converting`,
  `scheduledAheadSeconds`, `pendingBuffers`, `started`; `outputRate`, `latency`, `lastStartLead`, and the time from
  the last play call to its first heard sample (`plays-words.md`'s proposed rows: Output, Lane, Buffered ahead, Last
  start). Source rows (`Streaming, 4.2 of 31.0 MB` / `From the stream cache`) are SongFiles', not the engine's.
- Make `trace` public (`public var trace: ((String) -> Void)?`), each line stamped with the host time when not
  offline, so Debug can keep the last 500 lines for a "Copy log" (the check-6 diagnosis was a logging build of exactly
  this, never committed).

### 8.4 Words the engine and its sources say today (reach the listener through `AppModel.playWords`, :309)

`The song stopped arriving.` / `The song stopped arriving: <reason>` (StreamSource.swift:102, StreamFetch.swift:128);
`iOS couldn't decode this song (AudioConverter <n>).` (:105); `iOS couldn't find audio it can play in this file.`
(:85); `iOS can't decode this kind of file (AudioConverterNew <n>).` (:183); `iOS has no float format for <rate> Hz.`
(:176); `iOS couldn't start reading the stream (AudioFileStreamOpen <n>).` (:57); `No memory for a buffer of <n>
frames.` (:92, PCMSource.swift:62); `iOS couldn't open <file> to play: <reason>` (PCMSource.swift:51); `iOS wouldn't
start the audio: <reason>` (PlaybackEngine.swift:415); `iOS couldn't make a new audio engine: <reason>` (:319); the
StreamFetch words in 5.1; `The phone couldn't make a file to stream into (<name>).` (StreamFetch.swift:50); `The
phone couldn't write the stream to its disk: <reason>` (:119). Two must change for 0.2: **`This song has <n>
channels; Phase 0 plays mono and stereo only.`** (StreamSource.swift:173 - proposed `This song has <n> channels; deadwax
for iPhone plays mono and stereo only.`) and **`... Check again, and sign in.`** (StreamFetch.swift:102 - Phase 1 has no
Check button; proposed `deadwax says this phone isn't signed in (401). Sign in again.`). The listener's sentence for
each should come from the error-words port (CLAUDE.md "Errors in a listener's words"; `plays-words.md`), these words
kept for Debug.

---

## 9. Where this spec differs from the other Phase 1 specs

1. **`upnext.md` section 7 step 3 / OQ 1** recommends, for a committed next song on the heard lane, "stop that node and
   go on from the exact frame reached - a short gap". This spec recommends **holding the edit** instead (3.3 step 4):
   the brief says the song heard must be untouched, and the restart is not clean - `stop()` drops what is scheduled,
   the re-schedule of the heard song's remainder needs either a re-decode (a `StreamSource` decodes from the top: a gap
   of up to a second) or copies of the scheduled buffers, and the node is silent for the render cycles between stop
   and play (5-20 ms) somewhere in the song's last 2 s. Open question 1.
2. **`upnext.md` step 2 compares by id; 3.3 compares by `audio` (id plus level)** - the same thing when levels agree;
   it differs only when the same song is queued at another level (a Play Next of an album's own next song): by id the
   entry already decoded at album gain would be kept under the song-level entry.
3. **`upnext.md` step 1 refuses when "the engine's heard index != current"**; this spec finds the heard entry by key in
   the new list, which also covers the app's index being stale. Same outcome otherwise.
4. **`levels.md` 4.3** decides the gain at the entry's first open (and lets the first song wait up to 20 s); the brief
   says "fixed per song when it is queued". The engine is the same either way (the factor arrives with the source and
   never changes for that entry); the timing is `levels.md`'s to settle. Open question 2.

---

## 10. The API after Phase 1 (DeadwaxAudio)

```swift
public struct EngineTrack {
    public let key: Int                 // NEW: Up Next's Mark.key - unique in this queue
    public let audio: String            // NEW: "\(song.id)|\(level ?? "off")" - same audio, same samples
    public let song: Song
    public let open: (StartPoint) throws -> PCMSource   // returns GainedSource.wrap(source, factor:)
}
public struct EngineState: Equatable {   // + key: Int?  (the heard entry's); index stays, in the current list
    ...; public var key: Int?; public var latency: Double?
}
public final class PlaybackEngine {
    public var startLead: () -> TimeInterval          // unchanged
    public var latency: () -> TimeInterval            // NEW (7.2)
    public var trace: ((String) -> Void)?             // now public (8.3)
    public func play(_ tracks: [EngineTrack], from index: Int, at seconds: Double = 0)
    public func restoreQueue(_ tracks: [EngineTrack], at index: Int, seconds: Double)      // NEW (8.2)
    public func replaceUpcoming(_ tracks: [EngineTrack]) -> Bool                            // NEW (3.3), sync
    public func pause(), resume(), skip(to index: Int), seek(to seconds: Double), stop()   // unchanged
    public func position() -> EnginePosition?                                               // NEW shape (7.3)
    public func rebuild()                                                                   // fixed (4.2)
    public func debug() -> EngineDebug                                                      // NEW (8.3)
}
public protocol PCMSource: AnyObject { var format; func read(maxFrames:); func close(); var busy: Bool { get } }  // busy: default false
public final class GainedSource: PCMSource                  // NEW (2.2)
public final class CachedStreamSource: PCMSource            // optional (6.2)
```

`replaceTracks` goes (its one caller is none yet). `Settings` gains nothing required (`joinSeconds` only with 3.4's
refinement). Core gains `HeardEstimate` (4.2) and `StreamCache` (5.2); `levels.md` brings `gainMultiplier`.

---

## 11. Risks, and what only the phone can tell

| | risk | how it shows | Phase 1 check |
| --- | --- | --- | --- |
| E1 | `outputLatency` on AirPods and AirPlay isn't what iOS says | the title changes before/after the join; a pause/resume repeats or skips | 2 (a continuous album: title change at the join), 6, 8 |
| E2 | AirPods connecting / AirPlay may not post a configuration change, or the hardware rate changes and the mixer doesn't follow | play stops; or the readout says the old rate | 8 (connect mid-song: on from the same place; AirPlay and back) |
| E3 | Calling into a dead engine after a media reset raises | a crash | Settings > Developer > Reset Media Services while playing, if iOS 27 still has it |
| E4 | Held edits feel wrong in a song's last ~2.5 s | Play Next lands one song late | 5 |
| E5 | The engine's queue delayed in the background (an hour locked) | a lane runs dry: a gap, then Loading | 9 |
| E6 | The converter's inter-sample overshoot on brought-up albums (R10) | distortion on peaks | 4 (and 2.5 #7's number) |
| E7 | A deep seek in a long hi-res stream over WireGuard | seconds of Loading | 2/8, by hand |
| E8 | iOS purging Caches while suspended; 2 GB of a small phone | refetches; nothing breaks | none needed |
| E9 | The queue's end cut on AirPods (7.2 item 5) | an abrupt album ending clipped | 2 (end of an album) |
| E10 | Index-to-key refactor regressing Phase 0's paths | any of the 13 tests | all 13 must still pass |

Unverified from here: every DeadwaxAudio change (compiled and tested only on ios.yml's macOS job and James's Mac);
`vDSP_vsmul` in place equal to Swift's `*` (expected: IEEE single-precision multiply); `AVAudioPlayerNode` playerTime
after `pause()` (relied on already by `armIdle`); the mixer's format after a configuration change.

---

## Open questions

1. **A committed next song and an edit**: hold the edit (one song late, the song heard untouched) or restart the heard
   node from its frame (`upnext.md`: a 5-20 ms gap, or a re-decode)? **Recommended: hold**, measure on the phone
   (check 5); build 3.4's staging only if held edits are felt.
2. **When an entry's gain is fixed**: at the tap (the brief), or at its first open with a short wait (`levels.md`)?
   **Recommended: `levels.md`'s** (more songs levelled on a first play; still never mid-song, still one number per
   album) - the engine is identical either way.
3. **Subtract the output latency from every position** (7.2)? It changes the lock screen's timing and the pause/resume
   point on AirPods and AirPlay. **Recommended: yes**, with `outputLatency + ioBufferDuration`, checked by ear on a
   spoken or continuous track (check 2/6/8).
4. **The streaming cache's 2 GB**: 2,000,000,000 bytes (what iOS's Storage screen counts) or 2 GiB? **Recommended:
   2,000,000,000.**
5. **Cancel fetches of songs skipped past** (5.2 item 8), or let them finish into the cache? **Recommended: cancel**
   (bandwidth on WireGuard; the cache keeps what was heard).
6. **Phase 0's `Application Support/deadwax/phase0` downloads** (SongFiles.swift:27): Phase 1 has no downloads.
   **Recommended: delete the folder at 0.2's first launch** unless the Test sounds screen survives in Debug.
