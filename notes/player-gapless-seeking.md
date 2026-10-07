# The player: gapless and seeking (1.1.0-player.2)

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

#### Gapless (experimental, 1.1.0-player.2)

(Since 2.0.0-player.10 the switch below is a checkbox in You > Playback, and the readouts are
Info > Debug's rows, off the now-playing sheet: see "Now Playing as designed, with Info". The
engine it describes is unchanged.)

James, after a week on the iPhone: the player works, locked included, "except for a pause between
songs" - about a second on EVERY change, even between two songs both played before, so it is not a
first-load cost. It is the one-element design's own cost: on `ended` the element gets a new `src`,
and Safari asks for bytes 0-1 and then the rest - two round trips over WireGuard, through deadwax to
Navidrome - before AVFoundation starts from nothing. A research pass read WebKit's source (main, and
the Safari 17.4/18/18.5 branches) for what iOS allows, and the switch is built on what it found. The
guide's section is `docs/player.md#gapless-playback-experimental`.

- **Off by default, and off is the old player exactly.** `deadwax-player-gapless` ('on' or 'off',
  `readPlayerGapless` in persisted.ts) is the player's own, like its order: a home-screen app keeps
  its storage apart from Safari's, so a switch in the settings tab would never reach it. With it off
  no second element is made, `live()` is always the first, `handOver()` answers "off" and the song
  change is `load()` as it was. The only new work is timing the change for the readout. **The
  one-element rule still holds with the switch off**, and it isn't broken with it on either: the
  second element is unlocked by a tap too, and there are only ever those two.
- **Two elements that swap roles** (`usePlayer.ts`; the rules in `lib/gapless.ts`, pinned by
  `ui/test/gapless.sim.cjs`). The second is made by the switch (or at start, when it was left on). It
  is put through `load()` in the first tap that plays - `playTracks`, `toggle`, `next`, `previous` -
  or in the switch's own tap (`unlockSpare`, once), BEFORE the playing element's `play()`. A few
  seconds into each song (`PRELOAD_DELAY_MS`, 3s after `playing`) the STANDBY is given the next
  song, muted. On `ended`, `handOver()` swaps `state.active` (`activeAfter()`), mutes the outgoing,
  unmutes the incoming, calls `play()` on it in the same turn, and then `empty()`s the outgoing
  (`removeAttribute('src')` + `load()`, its blob handed back), which becomes the next standby.
  "Next" hands over the same way when the standby holds the next song and the music is playing.
- **The WebKit facts it rests on** (HTMLMediaElement.cpp, MediaElementSession.cpp, Document.cpp):
  - `<audio>` has no restrictions on iOS (MediaSessionManagerIOS `resetRestrictions()`; WebKit's own
    iOS expectation has `mediaSessionRestrictions["audio"] = ""`), and an element unlocked by a tap
    stays unlocked: `removeBehaviorRestrictionsAfterFirstUserGesture()` runs from `prepareForLoad()`
    - which `load()` and a `src` change both call - whenever `processingUserGestureForMedia()`. So
    `load()` in the tap is the unlock, with no play-then-pause blip.
  - An element unlocked by a tap that fires `ended` starts a one-second grace
    (`userActivatedMediaFinishedPlaying`; `maxIntervalForUserGestureForwardingAfterMediaFinishesPlaying
    { 1_s }`), in which the document counts as handling a tap. So `play()` on the standby from the
    `ended` handler is allowed twice over.
  - **Why the standby is MUTED.** The lock screen's Now Playing is elected by
    `preferMediaControlsForCandidateSessionOverOtherCandidateSession` - main content first, then the
    most recent user interaction, and NOT whether the element is playing - and
    `removeBehaviorRestriction(RequireUserGestureToControlControlsManager)` re-stamps
    `m_mostRecentUserInteractionTime` on every gesture-time load or play, the grace second included.
    Emptying the outgoing inside that second would stamp it newer than the song playing. A muted
    element is never a candidate (`canShowControlsManager()` returns false for `muted()`), so a muted
    standby can't take the lock screen whatever its stamp. At most one element is ever unmuted: the
    outgoing is muted before the incoming is unmuted, in the refusal path too.
  - **Why the next song goes into MEMORY.** iOS preloads before `play()` only after a tap, and only
    from Safari 18.5 (292087@main removed `AutoPreloadingNotPermitted` with the first gesture;
    cherry-picked to safari-7621, 18.5); and a paused element in a hidden document - a locked phone -
    gets `MakeResourcesPurgeable` (`MediaElementSession::preferredBufferingPolicy`), so what it
    buffered may be thrown away. A `blob:` copy is there whatever iOS does, and costs no trip.
  - Timers in a hidden page are aligned to a second (`DOMTimer::hiddenPageAlignmentInterval`) and
    `timeupdate` comes every ~250ms, so the handover is on `ended`, never a timer just before the end
    (Feishin plays the next track 65ms early and has two tracks playing at once after a wake, #2290).
- **What goes into memory** (`memoryPlan`): a file asked for as it is (`streamFormat()` 'raw'), typed
  `audio/*` or `application/ogg`, no bigger than `MEMORY_MAX_BYTES` (64 MiB: ten minutes of CD FLAC,
  few hi-res files) - a size not declared is counted as it arrives (`overMemoryMax`). Two are held at
  the peak, the song playing and the next. Anything else hands the standby the ADDRESS (stage
  'stream'), to buffer as iOS allows. A transcode is left out because its length is Navidrome's
  estimate and it may end short - and, since the review, is never FETCHED ahead either:
  `download()` sees `streamFormat()` isn't 'raw' before asking and goes straight to the address.
  (It used to fetch, start a transcode on Navidrome, read the headers, abandon it, and have the
  standby start a second.) iOS reloads a page that uses too much memory, which stops the music.
- **Nothing is got ready while AirPlaying** (review): `standbyPlan(..., wireless)` answers `none` or
  `clear` then, so `preloadSoon`/`preloadNow` do nothing, `download()` lets the standby go if AirPlay
  began while it waited (`wanted()`, after every await), and `webkitcurrentplaybacktargetiswirelesschanged`
  on the playing element re-fits the standby (dropped when AirPlay starts, got ready again 3s after
  it stops). It used to get every next song ready by address anyway, which `handoverDecision` then
  never used: each song asked for three times, a Navidrome transcode each for songs that need one.
  That also means a speaker is never handed a `blob:` it can't fetch, so `memoryPlan` lost its own
  AirPlay rule.
- **When it can't hand over, the one-element way** (`handoverDecision`): the switch off; "next" while
  paused; AirPlay (`webkitCurrentPlaybackTargetIsWireless` - AirPlay keeps the one element it has
  always worked with); nothing ready; another song ready (index AND id are compared, so a new album
  at the same position isn't handed over to); the standby's own `error` ("failed to get ready").
  **A standby still DOWNLOADING exactly the next song hands over BY ADDRESS** (source `'unfinished'`,
  review): `handOver` aborts the download, gives the standby `streamUrl` and plays it, as stage
  'stream' does - one fresh request, what the one-element way costs. It used to go the one-element way,
  which aborted the download (`fitStandby` then wanted the song after) and asked for the song again on
  the live element: the same gap, with part of every song sent twice. On a link where a whole song
  can't download while the one before plays, the switch still sends part of every song twice and
  closes nothing; the guide says so and says to turn it off when the readout keeps saying
  `download unfinished`. A standby holding the right song that failed is KEPT (`standbyPlan`), or every
  `playing` would download it again. `play()` refused on the standby (`NotAllowedError`) goes to
  `refusedHandover()`: back to the element that was playing, `load()`, the readout saying
  "refused". A song that fails FROM MEMORY is asked for from Navidrome at once, where it stopped,
  without using its one retry (`afterPlaybackFailure` 'stream'): a decode error would otherwise skip
  a song whose copy on Navidrome plays. `reload()` always goes to Navidrome for an element holding a
  `blob:`. After that, retry-then-skip is exactly as before.
- **Events** (`routeEvent`): everything from the element playing; from the standby only `error`
  (marks it failed); the rest is dropped, so its `pause`, `durationchange` or `timeupdate` can't
  stop the lock screen, shorten the song or count listening nobody did. **AirPlay availability is
  the exception, from EITHER element** (route `'availability'`, `airplayShown()`): WebKit keeps it
  PER ELEMENT (`MediaElementSession::m_hasPlaybackTargets`, false until a change is broadcast; a
  session made after monitoring started is never seeded; a broadcast reaches only a session whose
  answer it changes) and every element repeats its own value on each load (`createMediaPlayer`,
  `EnqueueBehavior::Always`). Each element's last answer is kept, and the button shows if EITHER
  says available. An answer can only be stale one way - "none" - so that is right both ways. Two
  wrong versions came first, each found by review: routing the standby's answer to the player hid
  the button as the switch went on (the new standby's first event said `not-available`) and made
  it come and go between songs; taking only the live element's then missed a speaker leaving
  while the SECOND element played, since only the first (now the standby) was told.
  `player.sim.cjs` models per-element sessions for both. Every other handler reads `live()`. The duration is set from the incoming element
  at the handover, since its `durationchange` came while it was standing by.
- **The standby lets go** when the queue moves to anything whose next song it doesn't hold
  (`fitStandby`, which also restarts the 3s wait from the new song's `playing`), when the switch goes
  off (whichever element is playing carries on alone: `activeAfter('switch off')`), and at a
  handover (the outgoing is emptied).
- **The readout** (`describeGaps`, at the TOP of the sheet's body since the review - see "After
  review" below - and hidden below 500px tall; since 2.0.0-player.10 it is off the sheet
  altogether, Info > Debug's **Gap** row - see "Now Playing as designed, with Info"): each song
  change that happened by itself, with the switch on or off, the last `GAPS_KEPT` (5), and how it was
  made - including the incoming element's `readyState` at a handover of what it held, where below
  HAVE_FUTURE_DATA (3) reads "had to load" (pinned at 3 and 2 in the sim). **Timed on the incoming
  song's media CLOCK** (`clockStep`, review): from `ended` (performance clock) to the first
  `timeupdate` whose `currentTime` has moved past where the song started (`Change.from`: 0, or where
  a seek landed), BACK-DATED by `(position - from) / playbackRate`, since `timeupdate` comes every
  ~250ms and further apart on a locked phone. Not to `playing`: WebKit queues `playing` from inside
  `play()` for an element with data (HTMLMediaElement::playInternal, `m_readyState >
  HAVE_CURRENT_DATA`), before session admission and before AVFoundation makes a sound, so every
  handover read 1-7ms whatever the silence - a purged buffer included, which is what the readout is
  for - while the one-element way's `playing` waited for the network. The same rule in both modes.
- **Only a change that goes straight from `ended` to sound is timed** (review). `state.change` is
  dropped wherever `intendsToPlay` goes false without `pause()` - `play()`'s `NotAllowedError`, the
  unasked `pause` handler (a call at the change), `onFailure`'s stop - and by the listener: `toggle()`
  to play, the lock screen's play, a seek from the scrubber or lock screen (`actions.seek`; the
  internal `seek()` a failed song's resume uses re-anchors `from` through `state.seeked` instead),
  next, previous, a new album. `CHANGE_MAX_MS` (30s) drops anything older, clock or no clock. Before,
  a refused next song tapped a minute later read as a 60,940ms gap. A song that FAILS before its clock
  moves marks the change `failed` ("…, failed before playing"), since the time then includes the
  reload, retry or skip.
- **Verified in the real page** (Chromium, 390x844, the pane hidden - audio and `timeupdate` run
  there) against a copy of the stub Navidrome serving 6-second FLACs, timed on the clock: switch off,
  one element, 142-149ms a change, and 262-275ms with 150ms added to every stream answer; switch on,
  every change a handover from memory at 95-99ms, delay or not (the download is long done). The
  first-`playing` figure the readout used to show was 3ms for those handovers and 22-64ms for the
  one element; most of the ~98ms left is Chromium starting its audio output, which every device
  does at its own speed - so the guide tells James to compare on and off, not read either alone.
  Fix by fix: a `play` hook pausing the incoming element at once (a call at the change) and
  `play()` patched to reject `NotAllowedError` (twice with the switch on - the standby and the
  fallback - once off) each left the readout unchanged through 3s of silence and a tap on play, in
  both modes, and the next change was timed as normal (99, 98, 144, 142ms); a broken last song that
  failed twice and stopped the queue, fixed and played 3s later, was not timed, while one whose
  retry played 1.5s later read "one element, failed before playing" at 1650ms; a synthetic `error` on the incoming
  element at its `play` read "handed over, from memory, failed before playing" at 144ms (it reloaded
  from Navidrome), the next 96ms; with `webkitCurrentPlaybackTargetIsWireless` stubbed true no
  download or standby source at all and "one element (airplay)", the standby got ready again 3s into
  a song after the change event said AirPlay stopped, and emptied at once when it said it started;
  with the stub trickling whole-file answers (no Range) over 20s, every change read "handed over,
  streamed (download unfinished)" at 143-147ms, the elements alternating on stream addresses, each
  download hung up part-way and each song asked for once by address.
  **From the first build** (its timings were on `playing`): handovers after a reload with the switch
  left on and a real tap as well as after turning it on; the elements alternate, the outgoing is
  muted and emptied, and the Media Session title, artist, album, artwork, position state
  and `playing` state follow each song; "now playing" and the submission once each per song (36s
  songs at 4x); Next while the standby held the next song handed over; "previous" restarted on the
  same element keeping the standby, then went back a song dropping it and getting the right one;
  a standby whose download failed was handed the address and handed over "streamed"; a refusal
  (`play()` patched to reject `NotAllowedError` once) fell back to the element that was playing in
  61ms; a failure from memory (a synthetic `error` on the playing element) moved to Navidrome's copy
  on the same element and played on, with no skip notice and no second "now playing"; with the
  switch on, a Broken song got ready failed quietly, went the one-element way and was retried then
  skipped, and a Flaky one failing three times was retried and played; switching off mid-album,
  whichever element was playing (the first, and in another run the second) played the rest alone,
  Broken and Flaky behaving as before.
- **Seen on the phone (1.1.0-player.2, James):** song changes on the iPhone read 96 ms and 94 ms;
  on his Mac, in Arc, "Last song change 236 ms, handed over, from memory · before: 581, 511, 2867,
  218 ms". Whether the phone's were locked, and how they were made, he didn't say.
- **NOT verified - the phone's to answer**, and the guide lists them for James: that `load()` in a tap
  unlocks the second element as read; whether a download or a buffer survives while locked (the
  readout's "had to load" and big numbers say no); the lock screen during a swap; AirPlay with the
  switch on; memory with hi-res albums (a page reload is iOS taking it back); Safari against the
  home-screen app; a call or Siri during a handover; whether AVFoundation plays FLAC from a `blob:`
  as it does from the address (WebKit serves ranges of a blob, so it should). WebKit bug 295518 (an
  iOS 26 home-screen app silent after reopening) is known and unrelated; don't blame this for it.
- ~~Not built~~ **Built in 1.1.0-player.5, after a lab page proved it on the iPhone** - see "One
  stream for FLAC". What this entry said then: ManagedMediaSource with FLAC repackaged as fragmented MP4 is the only
  sample-exact route that isn't Web Audio, but whether iOS plays FLAC through it at all is unknown
  (Safari has played FLAC-in-MP4 MSE as silence before, WebKit bug 198583, Shaka #2355), it needs
  `disableRemotePlayback` (so no AirPlay from it), and it evicts. Web Audio keeps playing locked only
  with `navigator.audioSession.type = 'playback'`, has regressed there before (bug 261554, 17.2-17.3),
  and a decoded 5-minute track is ~110 MB; Gapless-5 tells iOS users to turn it off for background
  play. None of Feishin, Gapless-5, jellyfin-web, Navidrome's web UI or Plex web is gapless on a
  locked iPhone.

#### Seeking (1.1.0-player.2)

James, on `:player` before gapless: "the seek bar seems a bit messed up, but worse on mobile. it
doesn't seem to always seek to where you put it." Two causes, measured before anything changed:
one in the page, fixed; one in Safari's engine, which deadwax can't fix yet and now shows.

- **How it was measured.** A test library (`scratchpad/seek/library`, served by
  `scratchpad/seek/navidrome_stub_seek.py`, the gapless stub plus `/arm-rate?kbps=N` to pace every
  audio answer) of FLACs whose audio SAYS what time it is: a sine at 300 + 5t Hz under noise
  high-passed above 3-4 kHz. "Varied" (300 s: the pilot alone for a minute, loud noise to 180 s,
  quiet after - frames 346 to 1956 bytes) and "Steady" (240 s), made with `flac -8`, each copy
  with a table from `metaflac --add-seekpoint=10s` and without, and one with an ID3v2 tag in front.
  In Chromium, Web Audio's analyser read the pilot 1.3 s after each seek; for Safari's engine,
  `scratchpad/seek/avlab.swift` plays the same stream through AVPlayer and reads it with an
  MTAudioProcessingTap. (swiftc needs `-sdk .../MacOSX26.5.sdk`: the CLT's 27.0 SDK is newer
  than its compiler.)
- **Chromium lands exactly, whatever the file.** Every seek, with and without a table, ID3 in front
  or not, fast or at 150 KB/s: `currentTime` at 'seeked' was the target and the audio matched the
  clock to 0.01 s. Without a table it bisects (its buffered ranges show the probes), costing 1-8 s
  a seek at 150 KB/s, against 0.3-3.5 s with one.
- **AVFoundation doesn't land, and says it did.** Seeking as WebKit's `currentTime` setter asks
  (`seekWithTolerance(time, 0, 0)`, then `seekToTime:toleranceBefore:toleranceAfter:` - read in
  `scratchpad/wk`): on Varied, up to 50 s early from a file, 32 s over HTTP through deadwax, 159 s
  on a first seek at 150 KB/s and up to 40 s LATE on later ones; on a song-like swing (about 1.3x
  in bit rate, quiet intro then verses and choruses) 2-8 s early; on Steady within 0.3 s.
  `currentTime` read exactly the target throughout, and so did the tap's own source time range.
  **A SEEKTABLE changed nothing** - runs with and without were identical error for error - so the
  troubleshooting entry explains tables without offering one as the fix. The errors depend on what
  it has read (the same target lands differently after other seeks), which fits estimating the
  byte offset from the bit rate parsed so far and taking the frame there to be the target: 90 s
  asked 0.5 s into the 15 KB/s intro landed at 64.4 s, where 90 x 15 KB/s falls in the file. The
  same FLAC frames in MP4 (`ffmpeg -c:a copy -f mp4`) and a CBR MP3 landed exactly. This is the
  Mac's AVFoundation; iOS shares CoreMedia, but no phone was measured.
- **The page's half was iOS's native range.** The scrubber was `<input type=range>`, which on iOS
  moves only when dragged BY ITS THUMB - the old CSS said so and made the thumb 28px to help - so a
  tap on the bar, or a drag begun beside the thumb, did nothing. Chromium's range takes both, and
  there the old scrubber measured right in everything asked of it: a tap, a drag, a drag while a
  seek was in flight, a seek straight after a song change with gapless on and off, the lock
  screen's `seekto` on the live element. The thumb never went back to the old time.
- **The new scrubber** (`Scrubber` in NowPlaying.tsx; the rules are `lib/scrub.ts`, pinned by
  `scrub.sim.cjs`, whose assertions fail under each of seven mutations tried): a `role="slider"` div,
  the full width and `--pl-hit` (44px) tall, with the track drawn across its middle.
  `touch-action: none`, no callout, no selection. `setPointerCapture` on pointerdown, so a drag
  that wanders off the bar (onto the cover, say) still follows and seeks. A tap seeks where it
  lands; a drag follows the finger and seeks ONLY on release. A cancel (pointercancel, or capture
  lost without an up) seeks nowhere and lets go - the old range's `dragging` stayed set for good
  if `change` never came. A second finger does nothing, and a drag begun on a song that has since
  changed is dropped. The drag lives in a ref as well as state, so a release arriving before the
  render after the last move seeks where that move put it. Arrows move 5 s, Page Up/Down 30,
  Home/End to the ends - WebKit sends VoiceOver's swipe up and down as arrow keys, and each key
  steps from what the bar SHOWS, so three quick presses go 15 s. `.pl-clocks` is drawn 8px up over
  the bar's tap target with `pointer-events: none`, which keeps the track and clocks where the
  28px range had them. The sheet's drag-to-close is on the grip, a sibling, and doesn't move.
- **The bar shows a seek's target until the element says it has landed** (`state.pendingSeek`,
  `reportedPosition()`): set by a seek that MOVES the element (readyState >= HAVE_METADATA and a
  target other than `currentTime` - see "After review" below), cleared on a 'seeked' with
  `seeking` false, by a new song and by a failure, and ignored after `PENDING_MAX_MS` (20 s) in
  case one never lands. Both engines already
  answer `currentTime` with the target while seeking (Chromium measured; WebKit sets
  `m_lastSeekTime` synchronously in `seekWithTolerance`), so it changes nothing there today; it is
  the guarantee, and what the keys step from.
- **The readout's "Last seek" line** (`seekStep()`, `describeSeek()`), under the gapless one (both
  at the top of the sheet's body since the review; Info > Debug's **Last seek** row since
  2.0.0-player.10):
  asked, and what the element's clock said at 'seeked' - which in Safari is the time asked, so on
  its own it proves nothing. The END of the song is what can: WebKit clamps its clock to the
  duration (`MediaPlayerPrivateAVFoundationObjC::currentTime`, `std::min(..., m_cachedDuration)`),
  so a seek that landed EARLY leaves the clock sitting at the end while the song plays on, until
  AVFoundation's end-of-item brings 'ended'; one that landed LATE brings 'ended' with the clock
  short of the length. (Its progress timer only schedules 'timeupdate'; 'ended' comes from
  `mediaPlayerTimeChanged`, which the player calls at the end of the item - read in
  `scratchpad/wk`, not seen on a phone.) So it notes when an update first sees the clock within
  `END_SLACK_S` of the length, and at 'ended' works out `short - played on` (the wall clock
  since, less what the clock still had to go), rounded to a tenth, "on time" within
  `LANDED_WITHIN_S` (1.5 s). Only the listener's own seeks (bar, lock screen) are followed; any
  other seek, a pause other than the end's own (both engines send 'pause' just before 'ended'),
  or a song change stops the judging. The line is there from the start ("No seek yet"): appearing
  under the first tap, it moved the bar 16px up the screen, and a quick second tap landed below
  it. (That fixed only 0-to-1 lines; the review found the 1-to-3 - see below.)
- **Verified in the real page** (Chromium, the pane displayed, real pointer events from the
  computer tool) at 800x600 and 390x844, against the seek stub at 150 KB/s: a tap at 60% seeked to
  179.74 and the bar held it through the 2.4 s seek; a tap at the bar's lower edge (18px below
  the track) seeked; a drag begun away from the thumb followed it (70.5 mid-drag) and seeked on
  release, one ending 130px above the bar included, with the sheet unmoved; a drag made while a
  tap's seek was still in flight landed where the drag let go; ArrowRight x3 went 128.13 -> 143.13 in steps of 5,
  then PageDown and Home; the lock screen's `seekto` (the handler, reached through Preact's hook
  state) showed "seeking…" and landed; Next then an immediate tap seeked the new song, one element
  (before its metadata, as a start position) and with gapless on (the handed-over element, from
  memory); a seek to 4:54 read "ended on time" at the end, into a handover too; and with the
  element's `currentTime` patched to act as WebKit's would after landing 7 s early or late, the
  line read "played on 7 s ... at about 3:38" and "ran out 7 s ... at about 3:52". At 844x390 both
  readouts hide, the bar stays 44px and the cover clears the title.
- **Not verified - the phone's to answer**: a tap and a drag under a real finger (the tool's
  pointers are a mouse's); where Safari on an iPhone lands (the readout is how James sees it);
  whether WebKit sends VoiceOver's adjustments to a custom slider as arrow keys in this version.
- ~~Not built: sending FLAC to Safari in an MP4~~ **Built in 1.1.0-player.3**, without ffmpeg -
  see "FLAC in an MP4, for Safari". (A CBR MP3 transcode lands exactly too, but Navidrome's
  transcodes carry no ranges and aren't lossless, so it was never the fix.)
- **Seen on the iPhone (1.1.0-player.2, James):** FLAC seeks landed 3 s and 8 s off by the
  readout's end-of-song judgement ("the song ended 8 seconds early the first time and 3 seconds
  early the second time") - the Mac's AVFoundation measurements, confirmed on the phone.

#### After review (gapless and seeking, 1.1.0-player.2)

An adversarial review of the two commits above confirmed seven findings, all fixed together:

- **The readouts moved the bar under the finger (the major one).** The sheet's body is
  `flex: none` against the bottom of a flex column (the grip takes the rest), so a change in the
  height of anything in it moves everything ABOVE that thing and nothing below. The two readouts
  were its last children and run 1-3 lines (a seek asked, then judged at its song's end; song
  changes piling up; 4 at 320px in the worst case), so a tap after a judged line dropped the bar
  and the transport 16-32px as the finger lifted, and a quick corrective tap landed above the
  bar. The "No seek yet" placeholder had fixed only 0-to-1. **They are the FIRST children of the
  body now** (`.pl-readouts`, above the title): nothing a finger goes to is above them, so their
  height moves only the cover (by half of it upright, where the cover is width-limited; on a
  320x568 phone, where it is height-limited, it shrinks instead - 197px to 116px in the 7-line
  worst case). Chosen over a reserved fixed height with an ellipsis, which on a phone would cut
  off the judgement ("...really landed at about 2:03") with no hover to read it; nothing is cut
  short. **Measured in the real page** with a MutationObserver recording the geometry at every
  real text change, and by setting every text variant directly (8 seek lines x 7 gapless lines,
  the longest real forms): the bar's top was ONE value per size across all 56 - 642 at 390x844,
  465 at 375x667, 366 at 320x568, 566 at 1024x768 - and so were the transport, the footer and the
  title, with no overflow anywhere. The review's own sequence, for real: "ended on time" (2
  lines) then a tap, "seeking…" then "said" (1 line), bar at 642.00 throughout. At 844x390
  `.pl-readouts` is `display: none` and the bar stays 44px. **Anything added to the sheet's body
  whose height can change goes above the title**, or reserves its height. (2.0.0-player.10 took
  the readouts off the sheet, into Info > Debug, and moved the failure line above the title by
  this rule.)
- **A seek the listener didn't make filled in "the player said".** `seekStep`'s 'other seek' only
  stopped the judging, so "previous" during a pending seek to 2:00 (which restarts: `currentTime`
  answers the target while seeking) had its seek to 0 fill `said` - "asked 2:00, the player said
  0:00". `SeekReading.closed` now: 'other seek', 'song change' and the new 'failed' close a
  reading, and a closed reading takes no 'seeked'. The element answers only the newest seek, so a
  later 'seeked' is never the closed one's.
- **A seek that never landed said "seeking…" for good** (a song change or a failure first).
  A closed reading with `said === null` reads "Last seek: asked 1:30, interrupted". `onFailure`
  raises 'failed' (and clears `pendingSeek`): a seek on its way never lands in a song that failed.
- **"previous", or a tap at 0:00, on a song still loading froze the bar at 0:00 for 20 s.** At
  HAVE_NOTHING a `currentTime` write is only kept as the default start position, and both engines
  seek there at the metadata only if it is past 0 - so neither 'seeking' nor 'seeked' ever came
  and nothing cleared `pendingSeek`. `seek()` now sets it only for a seek that moves the element
  (readyState >= HAVE_METADATA and a target other than `currentTime`; it clears a stale one
  otherwise), and returns whether a 'seeked' will answer (loaded, or a start past 0). The
  listener's seek that none will answer is `'other seek'` to the readout - it takes the place of
  the one before, so Home after a tap at 0:30 during a load reads "asked 0:30, interrupted" - and
  never 'asked'. `loadedmetadata` and `playing` also clear `pendingSeek` when no seek is in
  flight: a SECOND guard, reached by no current path (a failure clears it first), so no sim can
  make it matter - removing it alone passes everything, which is expected.
- **A transcoded next song was fetched and thrown away** - see "What goes into memory".
- **The standby's AirPlay availability drove the button** - see "Events". The first fix (the
  element playing only) left the button up after a speaker left while the second element played,
  and could still hide it when the second element reloaded; a verification pass found both. Each
  element's own answer, shown if either says available, closes both - an answer is only ever
  stale in the "none" direction. From WebKit's source; not seen on a phone either way.
- **No sim reached the wiring.** `ui/test/player.sim.cjs` drives the REAL `usePlayer.ts`,
  compiled with the repo's TypeScript beside a small preact/hooks with a cursor (rendering calls
  the hook again, so state is read through its own return value, not by slot index), through fake
  audio elements on a virtual clock: loads, play() refused without a tap or the grace second,
  seeks that take time, an optional clock that lags a seek and keeps sending updates, an engine
  that answers every seek, WebKit's start-position rule, a clock held at the song's length while
  a song that landed early plays on, failures in Chromium's order (error, then pause), blobs and a
  Navidrome that answers late. 56 checks: what the bar hears through a seek with updates of the
  old time and after it lands; a stray 'seeked' mid-seek; previous, next, a decode failure that
  stops the queue and a dropped connection that resumes, all during a seek; the readout across an
  on-time end and a 7 s early landing; the three load-time seeks; a gapless handover from memory
  (AirPlay button untouched by the standby) and one of a transcode (nothing fetched ahead).
  **Mutations**: dropping `state.pendingSeek = null` from 'seeked' fails 3 checks (the bar on the
  target a second after landing, twice, and after a resume); the 'seeked' guard, each of fixes 2,
  3, 4 (whole), 5 and 6, a failure not closing the reading, `load()` not closing it and `restart()`
  not closing it each fail at least one.
- **Also re-checked in the real page** (Chromium, 390x844 and 1024x768, the short-song stub): a
  real tap at 75% landed at 27.06 s of 36 and a drag to 50% at 18.01, on the handed-over element;
  at desktop size 14.43 and 9.00 (40% and 25% asked); arrows, Page Up/Down and Home stepped as
  before, including across a song's end; the switch turned on by a real click, and Seven handed
  over to Eight "from memory" at 97 ms, the first element muted and emptied; with the stub's
  stream answers slowed to 3 s, "previous" on Long One still loading left the bar following the
  clock (1.57 -> 1, 3.07 -> 3, 6.07 -> 6). NOT checked in a page: the AirPlay routing and the
  transcode path (Chromium sends no AirPlay events and plays every file in the stub) - the sim
  covers both; and nothing on an iPhone.
