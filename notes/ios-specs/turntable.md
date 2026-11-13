# The turntable and the speed fader, on the iPhone

Designed 2026-11-12 against the web at 2.1.4 (main 985b5d6; `ui/src` has no diff between main and ios) and the
app at ios 944d787 (app 0.2, Phase 2's Downloads merged). Line numbers are the code's at those commits. Nothing
here is built yet: the app is built to this spec, slice by slice (section 7), and reviewed against it. Reviewed
the same day against the code itself, not the citations ("Design review (2026-11-12)", at the end): its changes
are written into the sections they touch.

**What James decided** (`~/Desktop/Code/deadwax-ios-plan.md`, "The turntable on the iPhone (decided 2026-11-12;
overrules choice 22)", from the draft in `~/Desktop/Code/deadwax-plans/turntable.md`):

- Both the turntable and the speed fader (0.25x-2x) come to the phone.
- The turntable is Now Playing's second look, as on the web: the switch at its top right, You > Playback's
  "Now Playing opens as", and the wind-down switch.
- Its sound is the web's voice ported line for line, held to the web's own output within -100 dB (not byte for
  byte).
- The sound comes from the file on the phone - the stream cache, or a Phase 2 download. deadwax's `/scrub`
  windows are the fallback, for a part of a song still streaming in.
- The visualizer stays on the web.
- Four slices: (1) Core - the physics and the voice, held to the web's fixtures; (2) DeckEngine and the local
  window, tested on macOS; (3) the look, the touch view, the deck's rules, settings, Debug and docs/ios.md; (4)
  the fader, an engine change of its own.

And: "let's not cut corners on design, I like the direction things have been going." So this is written as
Phase 1's specs are: each part read from the web's own code and words, cited; every word verbatim; VoiceOver,
Dynamic Type and Reduce Motion for each part; errors in a listener's words; the app's own look; and, where the
web has no precedent, Apple's pattern, named, with how sure I am of it.

Where this spec departs from the web, it says so and why, in a line marked **Phone:**. Section 10's open
questions each carry a recommendation the build follows until James answers.

---

## 1. The foundation, checked

Everything below rests on these. Each was read, not remembered.

### 1.1 The web's turntable, file by file

| file | lines | what it holds |
| --- | --- | --- |
| `ui/src/lib/platter.ts` | 342 | The platter's exact physics: SPIN_UP_S 0.4 (:49), SPIN_DOWN_S 1 (:51), MOTOR_PULL 1/SPIN_UP_S (:54), FRICTION_VISCOUS 2.674 (:57), FRICTION_DRY from them (:60), END_MARGIN_S 0.25 (:64), VELOCITY_WINDOW_MS 90 (:67), MAX_SPEED 24 (:71), DEGREES_PER_SECOND 360/1.8 (:74), RELEASE_TAIL_MS 40 (:128); `handSpeed` (:118), `releaseSpeed` (:138), `phaseAt` (:166), `planAt` (:223), `coast` (:259), `motor(x, speed, length, target = 1)` (:281), `acceleration` (:331). Pure. |
| `ui/src/lib/deckVoice.ts` | 953 | The record's sound: four self-contained functions - `newVoiceState` (:246), `voiceCommand` (:298), `renderVoice` (:507), `voiceReport` (:813) - written so the AudioWorklet's source is made from them (`voiceWorkletSource`, :830). HAND_DELAY_S 0.12 (:95), VOICE_CEILING (:105), VOICE_LOOKAHEAD_S 0.0015 (:114), REPORTS_PER_SECOND 30 (:82). The DeckReport, DeckLatency and DeckHealth shapes Debug reads (:858 on). |
| `ui/src/lib/turntable.ts` | 415 | The geometry (STAGE 372x368 in the plinth's units, PLATTER, RECORD, GROOVES, ARM, ARM_PARTS), the drags (`recordStart`/`recordMove`, `armStart`/`armMove`, `dragEnd`, `preview`, `shownTime`), TAP_SLOP_PX 8, SECONDS_PER_TURN 1.8, the words (`lookButtonLabel` :47, `timeLine` :372, SILENT_WORDS :386-388), `playingDisc` (:405), `discArtPath` (:412). Pure. |
| `ui/src/lib/deckClock.ts` | - | The page's clock mapped onto the audio context's (2.0.0-player.24), and `pointerSamples` (:258): every coalesced sample of a pointermove, in order. |
| `ui/src/lib/playSpeed.ts` | 257 | The speed: SPEED_MIN 0.25, SPEED_MAX 2, SPEED_NORMAL 1, SPEED_DETENT 0.02, SPEED_STEP 0.01, SPEED_PAGE 0.1; `faderShare` by octaves, `speedAt`, `speedKey` (:83), the fader's drag, `faderTarget`, FADER and READOUT's place; `speedLabel` (:68), `speedWords` (:73); PACE_WINDOW_S 8. Pure. |
| `ui/src/player/deck.ts` | 2486 | The deck: the rules between a hand, the player and the voice - the Deck class (:1285 on), its constants (:113-190), its host (`DeckHost`, :217-237, with `window?()` the bench already injects), the windows (`keep` :2272), the handover (`handOver` :2014). |
| `ui/src/player/Turntable.tsx` | 537 | The look and the touches: the platter (:436), the record as a button (:441-443), the face turned by the deck (:454-470), the sheen (:474), the arm (:481-492), its handle as a slider (:499-506); the pointer handlers (:303, :316, :323, :363), the tap (:401), the arm's keys (:417); `TurntableTime` (:527). |
| `ui/src/player/SpeedFader.tsx`, `SpeedChip.tsx` | - | The fader as a slider (:111-118), its readout button (:139); the chip (:35). |
| `ui/src/player/NowPlaying.tsx` | - | The look button (:342-344), the switch waking the deck (:312), the disc's art address (:359), the silent line (:376), the time line in the scrubber's place (:391), the chip (:435), the grip on the top row alone on the turntable. |
| `ui/src/app/LookChoice.tsx`, `WindDownChoice.tsx`, `You.tsx:307-316` | - | You > Playback's two settings and their notes. Kept per device under `deadwax-player-opens-as` and `deadwax-player-wind-down` (`state/persisted.ts:48`, `:51`); the speed under `deadwax-player-speed` (`:62`). |
| `ui/src/lib/debugRows.ts` | - | Debug's turntable rows: `turntableRow` (:341), `turntableSoundFacts` (:368), `turntableTimingRow` (:389), `turntableTimingFacts` (:409), `turntableRows` (:442), `latencyNote` (:457), `recordingRow` (:474), `benchRow` (:497); and `speedRow` (:285). |
| `interface/styles/theme.css:640-655`, `interface/player/app.css:75-97`, `:1150-1420` | - | The turntable's colours (`--dw-tt-*`), its sizes (`--app-tt-*`) and its rules. |
| `ui/test/deck.sim.cjs` (3862), `decksound.sim.cjs`, `limiter.sim.cjs`, `lab.sim.cjs`, `turntable.sim.cjs`, `playspeed.sim.cjs`, `deckclock.sim.cjs` | - | What the web's turntable is held to. deck.sim's harness: `integrate` (:124), `render` (:305), `advance` (:626), `runFrames` (:638), `fakeHost` (:806), `posted` (:824), `flickBack` (:834). |
| `ui/src/lab/` | - | The bench (2.0.0-player.36): `signals.ts` (test tones, `seeded()` :262), `motions.ts` (MOTIONS :37 - steady 1x, 0.5x, 0.25x, 2x, backwards, a wobble, a ramp, a scratch; MOTION_HZ 60, JITTER_TIME_MS 1.5, JITTER_PLACE_S 0.001), `runner.ts` (`runMotion` :50: a motion handed to the real deck through the very methods a press drives). |
| `docs/player.md` | - | The user guide: "The turntable" (:1165), "The speed fader" (:1371), "Testing the turntable" (:1422). |
| `notes/turntable*.md` | - | The history: .11, .14, .16 (turntable.md), .24 (turntable-sound.md), .27-.35 and .40 (turntable-fixes.md), .36 (turntable-bench.md). |

### 1.2 The phone, as it is

- **The app** is SwiftUI, dark only (`.preferredColorScheme(.dark)`, `ios/App/DeadwaxApp.swift`), **portrait only**
  (Info.plist's UISupportedInterfaceOrientations), iPhone only (TARGETED_DEVICE_FAMILY 1), iOS 17.0
  (`ios/scripts/check_project.py`'s DEPLOYMENT_TARGET, `Package.swift`'s `.iOS(.v17)`). Its App folder is a
  synchronized folder in the .pbxproj, so a new file under `ios/App/` needs no project edit.
- **DeadwaxKit** (`ios/DeadwaxKit/Package.swift`, tools 6.0): DeadwaxCore is pure Swift and Foundation, built and
  tested on Linux; DeadwaxAudio is `#if canImport(AVFAudio)`, Swift 5 mode, built and tested on ios.yml's macOS
  runner. Core already holds the scrubber's rules (`Scrub.swift`: keyStep 5, pageStep 30, `adjusted(increment:)`).
- **Now Playing** (`ios/App/Player/NowPlayingView.swift`) is a `.fullScreenCover` (MainTabs.swift:22): the top row
  (the chevron, "Close", :43-53, the notice over it), the cover at 360 scaled 0.82 while paused (:66-71), the grip
  on the whole top half (:75-76, :193-203), the error line above the title (:79-84), ScrubberView (:93), the
  transport and the footer of AirPlay, Up Next and ••• (:169-189). No look button yet; Phase 1's screens.md 7 left
  the turntable button and SpeedChip out as "not native".
- **The engine** (`DeadwaxAudio/PlaybackEngine.swift`, 2165 lines): one AVAudioPlayerNode per format lane; a
  file's rate not the output's is converted by the lane's own AVAudioConverter, mastering, `.max`, prime method
  `.normal` (:1019-1030), one per lane, kept across its songs - which on a 48 kHz output is every 44.1 kHz CD
  (header :130-137). The level is GainedSource's multiply before it (:130). A pause stops the output at once
  (`idleStopSeconds` 0, :167); resume starts it again and schedules the song `startLead` ahead (:139-143,
  `playFromSilence` :1594). `position()` (:654) is the frame heard and is a hop onto the engine's queue
  (`queue.sync`). `debug()` gives `lastStartLead` and **`lastStartSeconds` - "From the last play (or resume)
  asked for to its first sample heard"** (:109-111, :674-675, set at :1644). The engine must not change in
  slices 1-3.
- **Every resume after a pause is a start from a stopped output** (read for this spec's review): a pause resets
  the lanes and lets the output sleep; a resume finds the engine asleep and begins the lane again from the held
  frame. `reset()` (:982-1000) lets go of every lane's converter (`resetConverter`), so a lane's converter starts
  afresh at whatever frame the lane begins at - a song's start, a seek's frame, the frame a pause held - and is
  kept only across the songs that follow it on the lane. A beginning lane decodes `startSeconds` (1.0 s) before its
  node starts, and a StreamSource reaches a frame by decoding from the song's top (StreamSource.swift's header).
  `lastStartSeconds` is worked out as the node is scheduled (:1642-1645): the engine's own estimate, in its own
  convention (the render's host time, then `latency()`), not a measurement of the sound.
- **`position()` waits on the engine's queue** (`queue.sync`), which a resume holds while it opens the file,
  decodes a second and starts the output. PlayerModel reads it twice a second (its ticker). **`isPlaying` is
  `.playing` or `.loading`**: true from a resume's tap, before a sample is heard.
- **The audio session** (`ios/App/AudioSessionController.swift`): `.playback`, long-form; `startLead()` and
  `latency()` are both `outputLatency + ioBufferDuration` (:65-84); it reports interruptions, the old device
  gone, and media services reset, each through one closure PlayerModel sets. **No preferred IO buffer is set**, so
  the IO buffer is iOS's own for long-form playback - 1024 frames (21.3 ms at 48 kHz) on the iPhones Safari has
  been read on (deckClock.ts's header: the audio's render moves "21 ms on an iPhone, whose hardware takes 1024
  frames at a time"); unmeasured in the app.
- **The files** (`ios/App/SongFiles.swift`, `Models/PlayerModel+Engine.swift:190-225`): an engine track opens
  from a download, else the stream cache's complete copy (`Caches/deadwax/stream/<id>.<suffix>`, 2 GB, LRU), else
  the stream; its level through `levels.open(key:level:song:source:)`.
- **The lock screen** (`ios/App/NowPlayingController.swift:52-53`): PlaybackRate 1.0 playing, 0.0 paused;
  DefaultPlaybackRate 1.0.
- **Settings** are kept in UserDefaults under the web's own keys where the web has one (`deadwax-player-repeat`,
  `deadwax-player-normalization` - UpNextTypes.swift:67, Levels.swift:21). You > Playback
  (`ios/App/You/PlaybackSection.swift`) is Gapless, then Normalization as radio rows (checkmark in
  Palette.accent, `.isSelected`), under YouWords.kept. Debug (`ios/App/You/DebugView.swift`) has Engine log,
  Downloads, Library, deadwax, Test sounds, Hi-res and Playing.
- **The routes**: the server's `GET /deadwax/navidrome/scrub/{song_id}` (`src/routes/navidrome.py:584-640`) takes
  `at` (0-86400, required), `seconds` (1-60, default 30), `max_rate` ("48000" or none), `level` (album, track or
  none) - anything else a 422 - and answers a FLAC window with `X-Deadwax-Window: <first>/<samples>/<rate>`, or
  415 (not FLAC), 416 (past the end), 503. `GET /deadwax/library/disc_art/navidrome?album=&disc=`
  (`src/routes/library.py:1243`; `album` 1-256 characters, `disc` 0-999, default 1) answers the picture or 404
  for every kind of none, kept `private, max-age=300`. Neither is in the app's `Routes.swift`;
  `tests/test_ios_contract.py:49` counts ROUTE_COUNT = 23, so each slice that adds one edits that test in the
  same commit.

### 1.3 What this spec found that the plan didn't say

1. **Swift's `Synchronization.Atomic` needs iOS 18 / macOS 15**; the app targets iOS 17.0 and the package macOS
   14. The real-time host (4.3) needs atomics: a small C11 target, or the targets raised (10, question 1).
2. **ProMotion needs a key**: on an iPhone, CADisplayLink is held to 60 Hz unless Info.plist has
   `CADisableMinimumFrameDurationOnPhone` = YES (Apple, "Optimizing ProMotion refresh rates for iPhone 13 Pro and
   iPad Pro"; sure). check_project.py checks Info.plist's keys, so slice 3 adds it there too.
3. **A queue track has no disc number** (`UpNextTypes.swift`, QueueTrack). The web doesn't take it from the track
   either: it reads the disc from the album the player knows (`playingDisc(playedAlbum(track.albumId)?.song, …)`,
   NowPlaying.tsx:359). The phone does the same through its PlayedAlbum, else disc 1.
4. **The engine's restart is the handover's problem.** A web audio element starts within its output latency; the
   phone's engine stops its output on every pause and takes `lastStartSeconds` to be heard again (0.2-0.4 s in
   notes/ios.md "The pause the lock screen didn't see") - longer for a song still streaming, whose resume decodes
   from the song's top (1.2). The web's handover would leave that much of a jump or a gap. 3.5 times the resume to
   it.
5. **Two clocks become one - but the anchor stays.** UITouch.timestamp, CADisplayLink.timestamp and an
   AudioTimeStamp's mHostTime are all on the host clock (mach_absolute_time), so deckClock.ts's mapping of a page
   clock onto an audio clock has nothing to map. What it also decides - where a rendered block sits on the page's
   clock: at its END, the offset being the upper envelope of currentTime less page time - is what gives
   HAND_DELAY_S's 30 ms over SMOOTH_AFTER_S wholly to delivery at any block size. 3.2 keeps that anchor.
6. **The web's in-gesture shortcut has no reason here.** RESUME_IN_GESTURE_S (deck.ts:171, :1810) exists for
   Safari's rule that play must start in a gesture; the phone has no such rule, and taking the shortcut would
   leave a gap the length of the engine's start (3.5).
7. **Safari at James's address has no AudioWorklet.** deadwax is opened over plain http (CLAUDE.md), and the
   browser gives AudioWorklet to secure pages only, so James's Safari plays the record's sound on the main-thread
   voice (deck.ts's ScriptProcessor, SCRIPT_LAG_BLOCKS: 43 ms more behind the hand in blocks of 1024). The A/B
   (8, check 23) is against that host, and says so.
8. **Turntable.tsx holds rules deck.ts doesn't.** Which press is the deck's (`live()` at the press), the silent
   scrub of 2.0.0-player.11 (`holdStill`), each coalesced sample through `recordMove` to `touched`, `takeOver` and
   `hand`, what a release seeks and whether it plays, the `turned` flag that makes the click after a turn no tap,
   and when the silent line starts (Turntable.tsx:288-420); and NowPlaying.tsx's Play/Pause on the turntable go
   through `pausing()` and `resuming()`. The bench's traces drive the Deck directly (lab/runner.ts), so none of
   this is in them: 3.1's TurntablePress ports it, hashed piece by piece (7.0).
9. **deck.ts reads audio state outside its host**: `voiceReady()`, `audio.context`, `audio.voice` are the module's
   (deck.ts:1418-1421, :2290-2296). On the phone they come in through the host, and "ready" means the deck engine
   is prepared - not running: it rests between sounds (3.3, 4.6).

---

## 2. The screen

### 2.1 The switch, and what moves

**The web.** A button at the top right of Now Playing, `.app-look-button` (NowPlaying.tsx:342-344): a record
(`RecordIcon`, `player/icons.tsx:126` - two circles, r 8.5 and 2.5, on a 24 grid) while the cover shows, a square
(`SquareIcon`, :133 - 15 by 15, radius 2) while the turntable shows; labelled `lookButtonLabel` (turntable.ts:47).
Every time Now Playing opens, it opens as You's "Now Playing opens as" says; the button switches only for as long as
the screen stays open, and never changes the setting (docs/player.md:1168-1172). Switching to the turntable is a
gesture that may start the deck's sound (NowPlaying.tsx:312).

On the turntable (NowPlaying.tsx:239 on, app.css:1150-1200):

- the plinth takes the cover's room - the room between the top row and the song's name - as big as fits it both
  ways (at most 440 pt, `--app-tt-max`), 24 pt clear above it (`--app-tt-clear`: the arm's counterweight reaches
  past the plinth's top edge) and 12 pt round it (`--app-tt-pad`);
- the title and "Artist — Album" stay in their rows but are **centred** under the record - "The song's name and the
  time line centred under the record, as the Turntable board sets them" (app.css:1142-1145,
  `.app-is-turntable .pl-sheet-titles, .pl-sheet-artist { text-align: center }`);
- the time line ("2:31 of 7:05") takes the scrubber's place (:391), one line whatever it says, so nothing below
  it moves;
- the transport and the footer stay;
- the grip is the top row alone - the record and the arm are outside it;
- a failure's line, and the silent line (2.8), are laid **over the foot of the plinth**, two lines at most, taking
  no touch, so the plinth's size never changes when one comes or goes (app.css:1150-1167);
- the backdrop (the blurred cover) stays.

**Phone.** The same, in `NowPlayingView`:

- **The look button** goes in the top row's right end, mirroring the chevron: a 44 by 44 pt target holding the
  web's face - "STYLE.md's secondary button drawn inside it at the boards' 36px" (app.css:1108-1127): a 36 pt
  rounded rectangle (radius 4, `--dw-radius-control`), a hairline Palette.secondaryEdge border (white at 0.1,
  `--dw-secondary-border`), Palette.secondaryFill (the web's gradient of white at 0.09 to 0.05,
  `--dw-secondary-bg`), a 1 pt top highlight (white at 0.06, `--dw-highlight`), pressed darker
  (`--dw-secondary-bg-active`, as a ButtonStyle). The glyph in it is 20 pt (`--app-look-icon`), Palette.onSecondary
  (#e8e8f0, `--dw-text-on-secondary`): the web's own icons drawn as SwiftUI Shapes (two stroked circles; a stroked
  rounded square) at the stroke the web's `thin()` gives, not SF Symbols - "opticaldisc" is a CD and
  "record.circle" means recording, and the web's are the boards' own. Its label is `lookButtonLabel`. Tapping it
  switches the look; it never writes the setting. (The chevron opposite it stays bare, as it is now: the web's
  close is bare too - a button with a face was the boards' choice for the switch alone. 10, question 18 has the
  bare alternative.)
- **The look is state of the screen**: `@State look`, set from the setting each time Now Playing appears (the
  web resets it as the sheet opens).
- **What moves**: only the cover's room. The cover (CoverImage, 360, the paused scale) and the plinth swap in
  the same frame - the cover's room is given a fixed height by the layout either way, so the title, the time
  line's row, the transport and the footer stay put. The swap is a crossfade of 0.2 s
  (`.transition(.opacity)`), none under Reduce Motion (Apple's Music crossfades its lyrics and artwork the same
  way; sure it reads as native, less sure 0.2 s is right - judged on the phone).
- **The titles**: leading on the cover, as now; centred on the turntable, as the web's are - the title and the
  byline each a full-width frame whose alignment follows the look, changed inside the same crossfade (a fade, not
  a slide: the text isn't animated across). The byline's tap target stays the whole width either way.
- **The scrubber row**: ScrubberView on the cover, the time line on the turntable, each in a row of the
  scrubber's height, so the swap moves nothing. **Phone:** the web's time line takes only its own line's height
  (the row below it moves up by the scrubber's height less a footnote line, about 19 pt, which the plinth gains);
  the phone keeps the scrubber's row, the line centred in it, so that the swap moves no row. On an SE (held by the
  height, 2.2) that costs the plinth about 19 pt (a 284 pt plinth for the web's 303) - the price of a swap in which
  the transport never jumps, which Apple's Music keeps the same way between its lyrics and artwork. Judged from
  the SE-sized render (7.3) and in the hand (8, check 3); the web's way is 10, question 20.
- **The error line**: on the cover, where it is now (above the title, in the flow). On the turntable, as the web
  lays it: an overlay at the plinth's foot, `.lineLimit(2)`, `.allowsHitTesting(false)`, Palette.quiet,
  `.footnote`, centred like the titles under it, its bottom `--pl-error-gap` above the title - stopping short of
  the readout's column (5.1) rather than passing under it. (The web draws the readout over the line, opaque,
  z-index 1 - app.css's note on 2.0.0-player.39's review; on the phone the overlay is simply laid where there's
  room.) Its text size stops at `.accessibility1` (`.dynamicTypeSize(...DynamicTypeSize.accessibility1)`): two
  lines over a plinth at the largest sizes would cover the record's lower half.
- **The grip**: on the cover, the top half as now; on the turntable, the top row alone (2.7).
- **The deck is made** when the turntable first shows and let go when the cover shows (the web's Deck is made and
  destroyed with the Turntable, deck.ts:1376 - and `destroy()` resumes a song the hand had taken). **Closing Now
  Playing on the turntable is not a destroy**: the web's Turntable stays mounted while the sheet closes (the sheet
  is hidden, not unmounted) and the deck is told `setShowing(false)` (:1436), so a coast or a run back to speed
  still ends by handing the song back. The phone's Now Playing is a `.fullScreenCover` whose view goes away, so the
  deck is owned by an app-level `DeckController` (made at the first turntable, kept for the app's run), told
  `setShowing(false)` as the cover closes and `destroy()` only when the look switches to the cover. Its windows
  are kept while it lives and let go after `setShowing(false)` (4.4). Its engine is prepared, not started (4.6).

### 2.2 The plinth: its size and its place

`STAGE` is 372 by 368 units (turntable.ts); the plinth is drawn in them, scaled to fit the room both ways:
`scale = min(roomWidth / 372, roomHeight / 368, 440 / 372)`. On a 393 pt wide phone, inside Now Playing's 24 pt
side padding and the plinth's 12 pt pad, that is 321 pt - about 0.86 pt a unit. The plinth: Palette.ttPlinth
(#19171e, `--dw-tt-plinth`), a hairline Palette.barEdge border (#2c2a36, `--dw-border`), corner radius 6
(`--dw-radius-card`), and the web's top highlight - a 1 pt line of white at 0.06 inside its top edge
(`--dw-highlight`, `box-shadow: inset 0 1px 0`; app.css:1192-1202), Palette.highlight, drawn as a 1 pt inset
stroke clipped to the top edge's run.

The room's height is what the screen leaves - the same room the 360 cover is drawn in. On the smallest phone the
app runs on (375 by 667 pt, an SE) the plinth is held by the height; that is the case to check - in the Mac's
render at the SE's size (7.3), and in the hand on James's phone (8, check 3).

The layout's numbers - the scale, every part's frame in points, the handle's and the fader's targets - come from
one pure function in Core (`TurntableLayout`), ported from turntable.ts and playSpeed.ts's placing, so they are
held to the web's on Linux (7.0).

### 2.3 The face

**The web.** The record's face is the album's CD art: `GET /deadwax/library/disc_art/navidrome?album=<id>&disc=<n>`
(`discArtPath`, turntable.ts:412), the disc being the playing song's on the album the player knows
(`playingDisc`, :405: the song's discNumber when it is a whole number of 1 or more, else 1). The server finds
`disc<N>.*`, then `disc.*`, in the album's folder; any none is a 404 (library.py:1243). The face is drawn
`has-art` only once the picture has loaded (Turntable.tsx:456); until then, and with no art, it is a plain black
record (`--dw-tt-vinyl` #141217) with the album's cover as its label (:457). A failed address is remembered while
the turntable is open; every opening asks again (docs/player.md:1190-1192: "CD art saved while the turntable is
showing appears the next time the now-playing screen opens").

**Phone.** The same rule, words and all:

- `discArt` is added to `Routes.swift`:
  `Endpoint(method: "GET", path: "/deadwax/library/disc_art/navidrome", query: ["album", "disc"])`, ROUTE_COUNT
  24 or 25 with `scrub` (slice 3).
- The disc: PlayedAlbum's songs, the playing song's discNumber, else 1 - Core's `TurntableGeometry.playingDisc`,
  held to the web's cases.
- The picture is asked at the face's pixel size, through the client with the session's cookie, and kept in
  memory under (server, session, album, disc) for as long as the app runs - as CoverCache keeps covers - with a
  404 remembered only while Now Playing stays open. Each opening of Now Playing asks again for one that wasn't
  there.
- Drawn only once decoded, over the whole face, clipped round (the web's `.app-tt-disc`, object-fit cover); the
  label under it hidden then.
- **Offline**, the face is what the app holds: art fetched earlier this run, else the plain record with the
  cover CoverImage gives offline (Phase 2's rule). Disc art isn't downloaded with an album (10, question 11).

### 2.4 The grooves, the label, the spindle and the sheen

From app.css:1238-1303 and the tokens at theme.css:640-655, in the face's own coordinates (the face is the
record's circle, RECORD r 160 units):

| part | drawing | turns with the face |
| --- | --- | --- |
| vinyl | #141217 (`--dw-tt-vinyl`), the record's circle | yes |
| label | the cover, round, 38.75% of the face's width, centred (30.625% in); a 2 pt ring of white at 0.3 (`--dw-tt-label-edge`); #141414 under a cover that hasn't come (`--dw-tt-label`) | yes |
| CD art | the whole face, once decoded; the label hidden | yes |
| grooves | a ring every 4 pt: clear to 2 pt, black at 0.2 at 3 pt, clear at 4 pt (`--dw-tt-grooves`, a repeating radial gradient in CSS px - so in points on the phone, not plinth units), over the face, CD art included | yes |
| spindle | 6.25% of the face, centred (46.875% in), #0e0c12 (`--dw-tt-spindle`), a 3 pt ring of white at 0.25 | yes |
| sheen | a conic gradient from 20°: white at 0.07 at 28°, clear at 56°, clear to 180°, white at 0.05 at 208°, clear at 236° (`--dw-tt-sheen`) | **no** - "the light across the record: it stays where it is while the record turns under it" |
| platter | PLATTER (178, 182, r 168), #2a2730 (`--dw-tt-platter`), under the record | no |

**Phone.** Drawn in Core Animation layers, not SwiftUI views, because the face turns every frame (2.6): a CALayer
for the face holding the vinyl, label, CD art, grooves and spindle as sublayers; the sheen a CAGradientLayer of
type `.conic` above it; the platter a CAShapeLayer under it. The grooves are one CGImage, made once per size and
scale with a CGContext - each ring a pair of `strokeEllipse` passes, or a CGShading per ring band, to the web's
stops - (a repeating radial gradient has no layer of its own; they are round, so turning the image shows nothing).
Sure of the approach: it is how anything is animated every frame without a layout pass.

**Only QuartzCore and CoreGraphics**, no UIKit, in the drawing: the layer tree is built by a `TurntableLayers` type
in a new DeadwaxKit target, `DeadwaxTurntable` (`#if canImport(QuartzCore)`; depends on DeadwaxCore), which takes a
`TurntableLayout` and a state (angle, arm angle, lifted, art, readout, fader) and sets the layers. The app's UIView
hosts its root layer. That is what lets slice 3 render the turntable on ios.yml's macOS runner without a Simulator
(7.3): `CALayer.render(in:)` into a CGBitmapContext, written as PNGs beside the web's own screenshots of the same
states.

**The sheen's angles**: CSS's conic gradient starts at the top and runs clockwise (`from 20deg` is 20° clockwise
of 12 o'clock); a `.conic` CAGradientLayer starts at its `startPoint`'s direction from the centre (the positive x
axis, 3 o'clock, by default) and its `locations` run clockwise in a flipped (UIKit) geometry and counter-clockwise
in an unflipped one. TurntableLayers maps them once - start direction from (20° - 90°) in the layer's own
geometry, each stop's location its CSS angle over 360 - and the render test (7.3) checks the brightest band lies at
48° (20° + 28°) clockwise of the top, within 2°, on the macOS render and on the web's screenshot alike.

### 2.5 The arm, and the arm as a seek

**The web.** The arm swings over the record from its pivot (ARM 348, 32; reach 205) so that the needle sweeps
the grooves from the outer (148) to the inner (64) as the song plays: `armAngle` of the song's share
(turntable.ts:142, :175 - an angle outside the grooves is held to them). Its parts (ARM_PARTS): the bar (6 thick,
radius 3, #c9c6d1 `--dw-tt-arm`), the head from 193 along it (28 long, 22 thick, radius 4, #d8d5de
`--dw-tt-arm-head`), the counterweight from -52 (34 long, 18 thick, radius 5, #8e8a96 `--dw-tt-arm-weight`), the
pivot's base (r 22, a 3-unit edge; #3a3642 with #56525f `--dw-tt-pivot`, `--dw-tt-pivot-edge`). The handle is a
dashed ring at the needle (handle 56 units; a 1 pt dashed ring of rgba(235, 235, 245, 0.18)
`--dw-tt-handle-edge`), at least 44 pt (`--pl-hit`) but never more than 30% of the plinth's width
(`--app-tt-handle-cap`), centred on the needle (app.css:1311-1330).

Taking the arm: a press on the handle, which takes hold only once the finger has gone TAP_SLOP_PX (8) - "so a
finger's jitter shows nothing it won't go to" (turntable.ts:283) - from where the song is then, so it doesn't
jump. While held, the time line says `Needle up · 2:31 of 7:05` and the arm shows where it would land; let go and
the song is sought there (`dragEnd`, :357; Turntable.tsx:363). Taking the arm quietens the record: a coast or a
run back to speed goes silent, its end still comes (`armTaken` deck.ts:1893, `quieten` :2044).

**Lifted while held**: from the press that takes the arm to its let-go, the head is drawn ARM_PARTS.lift (5 units)
up (its y less 5, in the arm's unrotated frame) (Turntable.tsx:428-486, `is-lifted`), and the handle is
`is-held` - the needle visibly up, as the time line's "Needle up" says.

**Phone.** The same, drawn as CAShapeLayers in a container turned round the pivot each frame; the head's lift a
change of its layer's position in that frame, with no animation (the web's is a jump, under the finger). The handle
a CAShapeLayer with `lineDashPattern`, 1 pt, Palette.ttHandleEdge; with Increase Contrast on
(`UIAccessibility.isDarkerSystemColorsEnabled`), Palette.text3 (#8e8ea3, `--dw-text-3`) instead - at white 0.18 on
the vinyl the ring is near invisible to anyone who has asked for more contrast (**new**; the web has no case: the
browser's `prefers-contrast` isn't read). Its touches are its own view's (3.1). Its maths - `needleAt`,
`armAngle`, `armTimeAt`, `armStart`, `armMove`, `dragEnd` - are Core's TurntableGeometry, held to turntable.sim's
answers.

### 2.6 Drawing at 120 Hz

**The web.** The deck's frame loop (`loop` deck.ts:2061, `onFrame`) runs only while something moves, the
turntable shows and motion is allowed; it writes the face's angle straight onto the element (`turnFace`, "written
straight onto it, never a render", deck.ts:224). Never while the screen is closed or the page hidden; not at all
under reduced motion (app.css:1234-1237).

**Phone.**

- A CADisplayLink on the main run loop, `preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120,
  preferred: 120)` (iOS 15), with `CADisableMinimumFrameDurationOnPhone` in Info.plist (1.3). Sure: Apple's
  documented way.
- **Running only when the web's loop would**: something moving (turning, a plan, a hand), Now Playing open on the
  turntable, the scene `.active`, and Reduce Motion off. Paused (`isPaused = true`) otherwise, so a still record
  costs nothing.
- **The frame's time** is `displayLink.timestamp` (the last vsync, host seconds) - the meaning of
  requestAnimationFrame's time, which the web's rules were written against. Sure enough; it's the documented
  meaning.
- **Each frame writes layers, never SwiftUI state**: the face's transform, the arm container's, the handle's
  position, under `CATransaction.setDisableActions(true)`. The time line, which changes a few times a second, is
  the one SwiftUI view that redraws, and only when its text changes.
- **The handover's judge never waits on the engine from a frame** (3.5). `position()` is a `queue.sync` onto the
  engine's queue, and a handover is exactly when that queue is busiest: the resume it just asked for is opening
  the file, decoding a second (all of the song up to there, for a stream) and starting the output on it (1.2) - a
  wait of tens or hundreds of milliseconds, on the main thread, during the one gesture that must not stutter. So
  while a handover is open, a serial `deck.position` queue (utility QoS) calls `engine.position()` in a loop paced
  at 120 Hz and publishes `(seconds, playing, hostTime of the read)` under an `os_unfair_lock`; the frame reads the
  last one published, and a reading older than 50 ms counts as no reading (the judge waits). The engine is reached
  read-only through PlayerModel (`engineForDeck`, a `position()`-only protocol), the engine itself unchanged.
  Debug: "Position read in" (worst, during the last handover).

### 2.7 The close drag, kept off the record

**The web.** "the sheet's drag to close starts here and nowhere else: the top row and the cover - and on the
turntable only the top row, the record and the arm being outside it" (NowPlaying.tsx's grip, `app-grip-top`).

**Phone.** `NowPlayingView.grip` is attached to the top row alone while the turntable shows (on the cover, the
whole top half as now). The turntable's touch views are not inside any view that carries the grip, so a SwiftUI
DragGesture never sees their touches (a gesture on an ancestor of a UIViewRepresentable can recognize alongside
its touches; on a sibling it can't - sure). A `.fullScreenCover` has no swipe of its own to close. Nothing on the
plinth is within the bottom edge's system gesture: the plinth ends above the title.

### 2.8 Every state, the web against the phone

| state | the web | the phone |
| --- | --- | --- |
| A song loading | The record still or turning as the player's state says; a press is the deck's only when it is `live()` (deck.ts:1418). | The same: `live()` ported. |
| Playing, its window in | The platter turns; a press takes the record with sound. | The same. |
| The window not yet in (just switched, just skipped, a seek far away) | A press scrubs silently - 2.0.0-player.11's way: the song plays on, the record stops under the finger, the song is moved by the turn when it is let go, no momentum (deck.ts:1575-1603; docs/player.md:1242-1252). Nothing said: "nothing for a silence that passes". | The same. A local window is usually in within a fraction of a second (4.4), so this is rarer. |
| Streaming, the part not yet on the phone | Every window comes from deadwax. | That window comes from deadwax's `/scrub` (4.5); the rest from the file. Debug says which. |
| Offline, the song neither downloaded nor all in the cache | n/a - the web has no offline. | If it plays at all (a stream that was under way), the record turns silently where no window can be made: Debug says "Off: no window - this phone is offline and the song isn't all on it yet". No line on screen: it is a silence that passes once the stream completes or the network comes back. |
| Not a FLAC | The record turns silently, no momentum; the first turn says `SILENT_WORDS.notFlac` until the song changes (turntable.ts:379-392, NowPlaying.tsx:376). Debug: "Off: it isn't a FLAC file (it is MP3)" (deck.ts:2286). | The same - FLAC only, though the phone could decode more (10, question 4). |
| No sound possible | `SILENT_WORDS.noAudio` - no Web Audio, or nothing to play it on. | The deck engine couldn't start (AVAudioEngine's `start()` threw): the noAudio line, with "phone" for "browser" (2.9). Debug: "Off: " and the error's own words. |
| AirPlay | The element plays to AirPlay; the voice plays wherever Web Audio goes. | **Phone:** iOS sends all the app's sound to the route, AirPlay included, about 2 s late (AudioSessionController's latency note). The record is silent on AirPlay, with a line (2.9), and turns as the silent record does (10, question 5). |
| Reduce Motion | No turning; a let-go seeks straight there; a pause stops at once; the hand still has its sound (2.12). | The same. |
| A call, Siri, another app's sound | The audio context is interrupted; counted in Debug. | The deck engine stops at once and goes quiet; a taken press ends as a cancel that **rests** - it doesn't ask the song to play into the call (3.1); `soundReady()` false until the interruption ends; counted ("Interruptions"). |
| A pause the turntable didn't ask for (the lock screen, Control Centre, the AirPods, headphones pulled out) | The deck sees it as `playingChanged(false)` (deck.ts:1497): after PAUSE_SETTLE_MS the platter runs down to rest, silently - only the turntable's own pause winds down with sound. | The same, and the deck engine, quiet, stops at once (4.6), so the lock screen sees the pause the way it does today. |
| The route changes (earbuds in or out, a car, Bluetooth) | Web Audio follows the device; nothing in the deck's rules. | The voice stops and the deck engine is prepared on the new route, `L` started again, the window made again if the rate changed (4.6). A press during the change scrubs silently. |
| The screen locks, the app goes to the background | The context is suspended; the loop stops; "It stops whenever the screen closes or the phone locks". | The deck engine stops; the display link pauses; a hand in progress is let go as a cancel (deck.ts `release(…, 'cancel')`, :1788-1798). |
| The song changes under a hand, a coast, a wind-down | `songChanged` (deck.ts:1536), SONG_CHANGE_SETTLE_MS 300. | The same. |

### 2.9 Every word

Every word is the web's, moved into Core as `TurntableWords` and held to fixtures exported from the web's own
functions (7.0). Where a word names the browser, the phone's says "phone", marked. New words, where the phone
has something the web hasn't, are marked new and written in the web's manner.

| where | words | source |
| --- | --- | --- |
| The look button, the cover showing | Show as a turntable | turntable.ts:47 |
| The look button, the turntable showing | Show the cover | turntable.ts:47 |
| The record, playing | The record: a tap pauses the song | Turntable.tsx:443 |
| The record, paused | The record: a tap plays the song | Turntable.tsx:443 |
| The arm | Tonearm: position in the song | Turntable.tsx:502 |
| The arm's value | `2:31 of 7:05` (`clock(shown) of clock(length)`) | Turntable.tsx:506 |
| The time line | `2:31 of 7:05`; just `2:31` with no length | turntable.ts:372-374 |
| …the arm taken | `Needle up · 2:31 of 7:05` | turntable.ts:374 |
| …the record turned, or a hand or flick moving it | `Scrubbing · 2:31 of 7:05` | turntable.ts:374 |
| The silent line, not a FLAC | The record makes sound for FLAC songs only - this one moves silently. | turntable.ts:386 |
| The silent line, no sound possible | This phone can't make the record's sound - turning it still moves through the song. (**phone**: "browser" in the web's) | turntable.ts:388 |
| The silent line, AirPlay | The record makes no sound over AirPlay - turning it still moves through the song. (**new**) | - |
| Debug, a window the phone couldn't make | `this phone couldn't make its window - <the error's words>` (**new**: the web's decode failure, said for the phone's own making) | deck.ts's window failures, :2348-2352, in their manner |
| Debug, a file of more than two channels | `it has 6 channels - the record plays two at most` (**new**) | - |
| Debug, offline with no whole copy | `no window - this phone is offline and the song isn't all on it yet` (**new**) | - |
| Debug, a song slow to start after a let-go | `The song took 3.4 s to start` (**new**, 3.5) | - |
| The ••• menu, off 1x at the accessibility sizes where the chip isn't drawn | `Speed 1.25x - back to normal speed` (**new**, 5.1) | the chip's label, SpeedChip.tsx:35, in a menu's form |
| The fader | Speed | SpeedFader.tsx:113 |
| The fader's value | normal speed; `1.25 times` | playSpeed.ts:73-76 |
| The readout's face | `1.00x`, `1.25x` (two places always) | playSpeed.ts:68-70 |
| The readout, at 1x | Speed: normal | SpeedFader.tsx:139 |
| The readout, off 1x | `Speed 1.25x: back to normal speed` | SpeedFader.tsx:139 |
| The chip's face | `1.25x` | SpeedChip.tsx |
| The chip | `1.25x, 1.25 times the song's speed: back to normal speed` | SpeedChip.tsx:35 |
| You > Playback | Now Playing opens as · Cover · Turntable | LookChoice.tsx:6-7, :35 |
| …its note | What you see first when you open Now Playing. The button at its top right switches between the two while it's open. | You.tsx:307-309, less its last sentence (below) |
| You > Playback | Pause winds the record down | WindDownChoice.tsx:26 |
| …its note | On the turntable, pausing slows the music to a stop over about a second, as a real record deck does. Turn it off to stop at once. Pausing from the cover always stops at once. | You.tsx:312-315, less its last sentence |
| Debug | section 6.2's rows | debugRows.ts |

The two notes each end with a sentence about the web's desktop frame - "For phones: a big screen has no Now
Playing view." and "For phones: a big screen has no turntable." - which the app has no case for. The phone drops
that sentence and nothing else; the words test asserts the phone's note is the web's with exactly that sentence
removed, so a change to the rest of the web's note fails it.

**When the silent line shows** (turntable.ts:379-400, NowPlaying.tsx:376): from the first turn that found the
record silent for good on this song, until the song changes; never before a turn; never for a silence that passes
(the sound starting, a window on its way). Not shown while a failure's line is.

### 2.10 VoiceOver

The web's answer first: the record is a button, the arm and the fader are sliders, the readout is a button, the
plinth's drawing is hidden (Turntable.tsx:441-506, SpeedFader.tsx:111-139). The phone gives each the same role,
words and steps, as UIAccessibilityElements of the turntable's UIKit view (its `accessibilityElements`, each with
`accessibilityFrameInContainerSpace` the web's target), in reading order:

1. **The look button** (SwiftUI, in the top row): a button, `lookButtonLabel`.
2. **The record**: `.button`, its label by the playing state. Activating it is the record's tap
   (`onRecordClick`, Turntable.tsx:401): pause with the wind-down, or play. Its frame is the record's circle.
3. **The arm**: `.adjustable`, "Tonearm: position in the song", its value the clock line. Increment and
   decrement move it 5 s (the web's KEY_STEP_S through `keyTarget`; Core's `Scrub.adjusted(increment:)`, which
   ScrubberView already uses - so the arm and the cover's scrubber step alike). While the length isn't known, its
   traits gain `.notEnabled` and it doesn't adjust (the web's aria-disabled).
4. **The fader** (slice 4): `.adjustable`, "Speed", its value `speedWords`; increment and decrement by
   SPEED_STEP, 0.01 - the web's arrow-key step, which is what I believe WebKit gives a VoiceOver swipe on an ARIA
   slider (not checked on a phone; if Safari steps otherwise, the phone follows what Safari does). The arrows step past the detent, as the web's keys do: an increment from 1x is 1.01x.
5. **The readout**: `.button`, its label by the speed; not enabled at 1x (`.notEnabled`), as the web's button is
   disabled there.
6. **The silent line**, when it shows: static text, read in place, before the title (it is in the error's place).

**Beyond the web** (Apple's pattern, `accessibilityCustomActions`; sure of the pattern, the choice is James's - 10,
question 9): on the record, "Back 5 seconds" and "Forward 5 seconds" (the arm's step, so a VoiceOver user can move
through the song from the record too); on the fader, "Slower by a tenth" and "Faster by a tenth" (the web's Page
Down and Page Up, SPEED_PAGE). The web's own behaviour comes first and is untouched by them.

Not announced: the time line's changes, the platter's turning, the handover (the web announces none of them; Apple
advises against announcing continuous change). Now Playing's existing chevron stays the way out; nothing here
changes it.

Looked at and not taken: `.allowsDirectInteraction` on the record, which would let a VoiceOver user turn it with a
finger as a sighted one does. With VoiceOver on, a finger landing on the record would then be a press, not
exploration - every pass across the screen could take and pause the song. The arm's adjustable steps and the
custom actions give the same reach without that hazard.

### 2.11 Dynamic Type

- **The plinth is drawn in its own units**, sized by the room, never by the text size - as the web's is.
- **The time line**: `.footnote.monospaced()` in Palette.quiet (the web's mono, `--dw-text-2`; 2.14), centred, one
  line - `.minimumScaleFactor(0.8)` first, then truncated at the tail - the web's "one line, whatever it says, so
  nothing below it moves". (ScrubberView's clocks are `.caption.monospacedDigit()`: they are the cover's, and stay.) Its row grows with the text size, so the line is never clipped vertically; at the
  accessibility sizes the plinth gets less room and is drawn smaller, which is the web's own trade (its
  container sizes the plinth by what is left).
- **The readout's text**: the web caps it at `min(--dw-text-label, 3.2cqw, 3.2cqh)` - the label size, but never
  more than 3.2% of the plinth - so it never spills over the record. The phone:
  `min(UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 12), 0.032 * plinthWidth)`, in
  `UIFont.monospacedSystemFont(ofSize:weight: .regular)` (the web's mono, tabular). It grows with Dynamic Type up
  to the cap.
- **The large content viewer** (Apple's pattern for a control that can't grow - the tab bar's; sure): the look
  button and the readout show theirs on a long press at the accessibility sizes (`.accessibilityShowsLargeContentViewer`
  on the SwiftUI button; `UILargeContentViewerInteraction` on the readout).
- **The silent and error lines**: `.footnote`, two lines at most over the plinth's foot, their size stopped at
  `.accessibility1` (2.1); VoiceOver reads all of it whatever is drawn.

### 2.12 Reduce Motion

**The web** reads `prefers-reduced-motion` itself and follows its changes (deck.ts:1366-1369, :2444): the
platter never turns (:1937, :2072); a let-go plays or rests straight where it is, with no coast or run back to
speed (:1810, :1825); a pause stops at once, with no wind-down (:1853). The hand's own sound is unchanged: a turn
is the user's own motion.

**Phone.** The same rules, read from `UIAccessibility.isReduceMotionEnabled` and its change notification, given
to the deck's rules as the web's `reduced`. Also: the look switch without its crossfade; the display link never
runs. And one difference (3.5; 10, question 21): under Reduce Motion a let-go of a playing record jumps the
record's sound to where the song goes - a `take` there, no motion - and hands over to the song from it, rather than
stopping the sound and starting the song, because the phone's song takes `lastStartSeconds` to be heard and
stopping first would leave that gap.

### 2.13 Landscape

None: the app is portrait only (1.2). The web's rules for a phone on its side - the handle's 30% cap, the fader's
14% cap, the chip shown on the turntable below 500 pt of height - are ported with the layout (they are part of
`TurntableLayout`, harmless at portrait sizes) but have no phone case to check.

### 2.14 The colours and type, as the app's

The app's Palette (`ios/App/DeadwaxApp.swift:74-104`) gains the turntable's tokens, named after the web's and
holding their values; nothing in the turntable's drawing is a raw value outside the Palette (the web's "tokens only"
rule, kept here as Phase 1 kept Palette).

| Palette | value | web token |
| --- | --- | --- |
| ttPlinth | #19171e | `--dw-tt-plinth` |
| ttPlatter | #2a2730 | `--dw-tt-platter` |
| ttVinyl | #141217 | `--dw-tt-vinyl` |
| ttGroove | black at 0.2 | `--dw-tt-grooves` |
| ttSheenHigh, ttSheenLow | white at 0.07, at 0.05 | `--dw-tt-sheen` |
| ttLabel | #141414 | `--dw-tt-label` |
| ttLabelEdge | white at 0.3 | `--dw-tt-label-edge` |
| ttSpindle | #0e0c12 | `--dw-tt-spindle` |
| ttSpindleEdge | white at 0.25 | `--dw-tt-spindle-edge` |
| ttArm | #c9c6d1 | `--dw-tt-arm` |
| ttArmHead | #d8d5de | `--dw-tt-arm-head` |
| ttArmWeight | #8e8a96 | `--dw-tt-arm-weight` |
| ttPivot | #3a3642 | `--dw-tt-pivot` |
| ttPivotEdge | #56525f | `--dw-tt-pivot-edge` |
| ttHandleEdge | rgba(235, 235, 245, 0.18) | `--dw-tt-handle-edge` |
| barTrack (exists) | #121117 | `--dw-track` (the fader's slot) |
| barEdge (exists) | #2c2a36 | `--dw-border` (the plinth's edge, the slot's, the readout's well) |
| textTertiary | #8e8ea3 | `--dw-text-3` (the fader's mark) |
| greenIcon | #34d399 | `--dw-green-icon` (the mark at exactly 1x) |
| accent (exists) | #C084FC | `--dw-accent` (focus rings only, as the web's) |
| accentText | #d8b4fe | `--dw-accent-text` (the readout off 1x, the chip's text) |
| toggledFill | rgba(168, 85, 247, 0.18) | `--dw-toggled-bg` (the readout's face off 1x, the chip's face) |
| toggledEdge | rgba(192, 132, 252, 0.45) | `--dw-toggled-border` |
| ttWell | black at 0.2, over ttPlinth | `--dw-well` (the readout's face at 1x) |
| wellInset | a 1 pt inner shadow, black at 0.5, 1 pt down | `--dw-well-inset` |
| highlight | white at 0.06, a 1 pt line inside the top edge | `--dw-highlight` (the plinth, the look button) |
| secondaryFill, secondaryFillPressed | white at 0.09 to 0.05 (a gradient); the web's active value | `--dw-secondary-bg`, `--dw-secondary-bg-active` (the look button) |
| secondaryEdge | white at 0.1 | `--dw-secondary-border` |
| onSecondary | #e8e8f0 | `--dw-text-on-secondary` (the look button's glyph) |
| quiet (exists) | Color.secondary | `--dw-text-2`, as Phase 1 mapped it (the time line, the silent line, the readout's text at 1x) |

Each value is read from theme.css by the port's exporter and checked (7.0), so a change to a web token fails the
phone's check rather than drifting.

Type: the system font throughout, as the app's other screens; the time line, the readout and the chip in the
system's **monospaced** face (`.monospaced()`, SF Mono) - the web sets all three in `--dw-font-mono` with tabular
figures, and the app already uses `.monospaced()` where the web has mono (ErrorNote, Info, SignIn), not
`.monospacedDigit()`, which keeps proportional letters and only evens the digits.

---

## 3. The hand and the deck's rules

### 3.1 The touch views

**The web.** The record, the arm's handle and the fader are separate elements, each capturing its own pointer
(`touch-action: none`), so two fingers can turn the record and move the fader at once. A pointermove hands the
deck every coalesced sample, in order, each with its own time, none earlier than the one before nor the same
twice (`pointerSamples`, deckClock.ts:258; Turntable.tsx:332).

**Phone.** Three UIViews in the turntable's view - `RecordTouchView`, `ArmTouchView`, `FaderTouchView` - each
following one touch (the first that lands; others ignored, as the web follows one pointer per element), framed
by the web's targets (the record's circle; the handle's ring; the fader's target, which never reaches the record -
`faderTarget`). In `touchesMoved`, each takes `event.coalescedTouches(for: touch)` - every sample the digitizer
made since the last event - and hands the deck each sample's `timestamp` and `location(in:)`, in order, deduped
by the web's rule (Core's `pointerSamples` port). Never `predictedTouches`: the voice plays the hand 120 ms late
so it never has to guess, and predicted samples would be guesses (sure; it's the web's own reasoning,
deckVoice.ts on the delay).

Sure of the approach: UIKit's coalesced touches are the iOS counterpart of getCoalescedEvents, and SwiftUI has
no access to them. How many samples a second an iPhone gives is a device question (9) and a Debug row (6.2).

The record's view is a UIAccessibilityElement's frame too (2.10), and it hit-tests round: a touch outside the
record's circle passes through.

**What a touch does is TurntablePress's, not the views'.** The web's rules between a pointer and the deck live in
Turntable.tsx's handlers, not in deck.ts (1.3, item 8): `onRecordDown` (:303 - forgets an unclicked turn, reads
`live()` once at the press, then `pressed` or `holdStill(true)`), `onArmDown` (:316 - only with a length;
`armTaken`), `onMove` (:323 - for a live press, every coalesced sample through `recordMove`, then `touched` and
`takeOver(time, true)` past the slop, then `hand`; for a silent one, `recordMove`, the `turned` flag and the first
silent turn of the song noted for the silent line), `onRelease` (:363 - a live press's `release`, then the seek and
the play it returns; a silent one's `holdStill(false)` and `dragEnd`'s seek), `onRecordClick` (:401 - a click after
a turn is no tap; `pausing()` then the pause then the seek to its landing; `resuming()` then the seek then the
play), `onArmKey` (:417 - `keyTarget`), and the silent line's rule (:288-290, `silentNote`). These are ported to
Core as `TurntablePress`, a state machine over DeckRules and a `PressHost` (seek, toggle, playing, length, the
song), each handler's Swift carrying the web's file:line, and hashed piece by piece into the port's record (7.0).
The UIViews only turn touches into its calls: `began`, `moved(samples)`, `ended(.up | .cancel)`, `tapped`. On the
phone two web events that are separate become one: UIKit has no click after a pointerup, so `ended(.up)` with no
turn past the slop and no take by rest is the tap (`onRecordClick`), in the same call, after the release's own
work - the order the web's events come in.

**Cancels the phone has and the web rarely sees**: a touch UIKit cancels (a call's full-screen interface, the
app leaving the front, Control Centre pulled over it, a system alert) is `ended(.cancel)`, the web's
`release(…, 'cancel')` - a song the press paused plays on, nothing is sought. An audio interruption (4.6) ends a
taken press as a cancel **with its intent set to rest first**, so the cancel doesn't ask the song to play into a
call.

**As built (slice 1, 2026-11-12).** `TurntablePress<M>` (TurntablePress.swift) over two protocols: `PressDeck`,
which DeckRules conforms to, and `PressHost` (`playing`, `length`, `track`, `seek`, `toggle`, `wake` - the web's
wakeDeckAudio - `box`, `drawnAt`, `shown`, `now`, `flac`, `noAudio`). Its calls are `recordDown`, `armDown`,
`moved(pointer:samples:)`, `ended(pointer:how:time:)` and `armKey`, with `grabbed()` (the host's, :237),
`songChanged` and the static `toggle(deck, host)` (NowPlaying's, :282). There is no `tapped`: a record's
`ended(.up)` runs onRecordClick's rule after the release's own work, as above; the arm's lift runs none (the web's
click handler is the record's alone). **Held by the press traces of 7.0** (TurntablePressTraceTests: 13 of them,
every call bit for bit with the web's Math and within 1e-9 with the platform's, the drawn turn and the silent line
after every input) and by hand-built cases (TurntablePressTests); the handlers' hashes fail iosdeck.sim on any change.

**Review (slice 1).** The traces found two places the port wasn't the web, both now kept by `following`, the touch
the turntable follows: **one pointer at a time** - the web's `pressable` (:301) takes the primary pointer only, so a
second finger, on the arm while the record is held or the other way round, starts nothing (this is the web's, and
contradicts 3.1's "two fingers can turn the record and move the fader at once": SpeedFader.tsx:61 asks isPrimary
too - a question for James, 10); and **the click follows the touch, not the drag** - a lift whose drag a song change
dropped (`songChanged`) still runs onRecordClick, as a browser's click still comes, so the new song is paused.
**Since 2.1.12, on both** (James: "Fix on both"): the song change sets `turned` when the drag it drops was the
record's, so that click is no tap and the new song is left as the change left it - see notes/ios.md "Main's 2.1.11 to
2.1.15 merged". Not kept: a browser's primary pointer is the first of a gesture with no other finger down, so a third finger landing
after the first lifted while the second stays is not primary there and is here - three fingers on a 372-point
turntable.

### 3.2 The clock

**The web.** The page and the audio context have two clocks; deckClock.ts (2.0.0-player.24) maps one onto the
other smoothly, and every message to the voice is stamped in the audio clock's time (`stamp`, deck.ts).

**Phone.** One clock. A touch's `timestamp`, the display link's `timestamp` and the render's `mHostTime` are all
the host clock, in seconds since boot. The deck's rules keep the web's milliseconds (`now()` =
`CACurrentMediaTime() * 1000`), and the stamp is `ms / 1000`: the voice's time is host seconds.

The voice's `now` - what the web's renderVoice is given as the context's `currentTime` at the block's start - is
the **render clock**, not the speaker's: the knots stamped "now" must have arrived when the voice renders "now"
(the web learned this with getOutputTimestamp, notes/turntable-sound.md). And where on the page's clock a block
sits matters as much as which clock: deckClock.ts takes the offset as the **upper envelope** of `currentTime` less
the page's time, read as the main thread sees each burst of blocks - so the page's "now" maps onto the **end** of
the block just rendered, and a knot stamped at page time `t` is in the ring before the block that renders voice
time `t` begins. That leaves the whole of HAND_DELAY_S less SMOOTH_AFTER_S (0.12 - 0.09 = 30 ms) for a sample to
travel from the digitizer to the ring, at any block size. Anchoring on the block's start instead - "where the
host clock was when the block began" - spends a block of that 30 ms: 21.3 ms at iOS's 1024 frames (1.2), leaving
about 9 ms, which a touch on the main run loop overruns whenever a frame is busy, and the fit then goes without
its last knot. So, in the render block:

- `hostOut` = the timestamp's mHostTime in seconds (valid on the device; when the block's first frame is
  presented, in the engine's convention - the one `lastStartSeconds` and `position()` add `latency()` to);
- `entry` = the host time read as the block is entered;
- `lead` = `hostOut + frames / rate - entry`: how far the block's **end** is ahead of the moment the voice
  renders it - a sample per block;
- `L` = the **largest** lead over the last CLOCK_WINDOW_MS (1.5 s) of blocks - the web's envelope, mirrored (an
  upper envelope of the page-to-audio offset is a largest lead) - so that for those blocks voice time never runs
  ahead of what could have arrived. A sliding maximum (a monotonic deque) in a ring made with the state, 2048
  entries - 1.5 s of iOS's smallest blocks (64 frames at 48 kHz is 1125) - so it never allocates;
- the voice's `now` = `hostOut - L`.

`L` moves as the web's offset does (deckClock.ts): freely while the voice is quiet (no hand, no plan, no
handover); under a sound, toward its target by at most CLOCK_SLEW (0.5 ms a second), so the voice's clock never
steps under a hand. Before the first block, `L` starts at `2 x ioBufferDuration`. It is kept across the deck
engine's stops and starts on the same route (the route's lead doesn't change because the engine rested) and
started again from that floor on a route change (4.6).

So `now` advances by the host time between blocks - the block's frames over the rate, less or more the device
clock's drift against the host's (parts per million) and the presentation time's jitter (microseconds); the
voice's steering absorbs both as it absorbs the web's. Offline (manual rendering, no host time), `now` is the
sample time over the rate plus a base the test sets, and `L` is the test's. Debug shows `L`, the latest lead and
the largest under the last hand (6.2).

The deck rules' `stamp(ms)` is `ms / 1000` - the page time **is** the voice's time, with no mapping, because both
are the host clock, and `L` lives inside the render. That is the one structural change from the web's clock:
deckClock.ts's slewed mapping moves into the voice's host instead of the page's.

**The decision I am least sure of** (still): it rests on mHostTime being smooth and the largest lead bounded and
steady on a phone - 9's first check, and Debug's clock row shows it.

### 3.3 The deck's rules, ported

`deck.ts`'s Deck class is ported to Core as `DeckRules`: the same state, the same methods, the same order of
effects, each method's Swift carrying the web's file:line in a comment. Its world comes in through a protocol
(`DeckHost`, the web's :217-237: `song()`, `playing()`, `position()`, `onPosition`, `hold()`, `resume()`,
`turnFace`, `show`, `grabbed`, `window`) and a clock (`now`, `stamp`, and its timers as deadlines the app's
main-queue timers call back - the web's setTimeouts). Its voice messages go out through `post`.

Two of the web's inputs come from outside its host, and come in through it on the phone:

- **`soundReady()`** - the web's module-level `voiceReady()` (deck.ts:1240), read by `live()` (:1420) and
  `sounding()` (:2207): true when the deck engine is **prepared and allowed** - made, its voice state made, not
  failed, not on AirPlay, not interrupted. It is **not** "running": the deck engine rests between sounds (4.6) and
  starts on the press that needs it, so a `soundReady()` that waited for a running engine would make every first
  press after a rest a silent scrub.
- **`window(song, from, seconds) async throws -> DeckWindow`** - the web's `fetchWindow` and `decode` as one: the
  bench's `window?()` hands back bytes the browser decodes, and the app's PCM is made by the phone (4.4) or decoded
  from `/scrub`'s FLAC (4.5), so the host answers decoded channels. `DeckWindow` is `{ channels: [[Float]] (1 or
  2), start: seconds, end: seconds, rate, from: .file | .server, bytes, madeIn: seconds }`. DeckRules keeps the
  web's handling of what comes back - the song's change while it was on its way, `covers`, the refresh timers -
  and maps the host's errors onto the web's words: `.notFlac` the 415's, `.pastTheEnd` the 416's, `.offline` "no
  window - this phone is offline and the song isn't all on it yet" (**new**), `.undecodable(words)` "this phone
  couldn't make its window - <words>" (**new**, the web's "this browser couldn't decode" in the phone's terms),
  anything else the web's retry after RETRY_MS. The 1-2 channel limit is the voice's (4.3): a 5.1 file is a
  `.notFlac`-like refusal with its own words, "it has <n> channels" (**new**).

The constants, kept as the web's:

| constant | value | source |
| --- | --- | --- |
| HOLD_MS | 250 - a press that stays put this long takes the record | deck.ts:113 |
| TAP_SLOP_PX | 8 (points on the phone: a CSS px is a point on an iPhone) | turntable.ts |
| TAKE_BACK_S | HAND_DELAY_S - 0.02 = 0.10 - how far back a take reaches | deck.ts:128 |
| SCRIPT_TAKE_BACK_S | -0.005 - the main-thread voice's; **never on the phone**, whose voice has its own thread | deck.ts:129 |
| WINDOW_S, WINDOW_BACK_S, WINDOW_GRID_S | 40, 4, 2 | deck.ts:134-136 |
| REFRESH_AHEAD_S, REFRESH_MIN_MS, RETRY_MS | 6, 3000, 10000 | deck.ts:139-144 |
| DRIVE_FOR_S | 0.12 | deck.ts:147 |
| HANDOVER_MAX_S, HANDOVER_FADE_S | 3, 0.04 | deck.ts:165-166 |
| SLOW_FRAME_MS | 34 (kept at the web's 60 Hz figure so Debug compares with Safari; 6.2) | deck.ts:169 |
| RESUME_IN_GESTURE_S | 0.05 - kept, so the web's traces replay with the lead at 0; with a lead, the phone's rule takes no shortcut (3.5) | deck.ts:171 |
| CLOCK_WINDOW_MS, CLOCK_SLEW | 1500, 0.0005 - the voice host's lead (3.2), not the rules' | deckClock.ts:85, :95 |
| PAUSE_SETTLE_MS, SONG_CHANGE_SETTLE_MS | 300, 300 | deck.ts:175, :180 |
| HEARD_FRESH_MS, HEALTH_REPORT_MS | 120, 250 | deck.ts:182, :186 |
| SOUGHT_ELSEWHERE_S | 0.75 | deck.ts:190 |
| the platter's | SPIN_UP_S 0.4, SPIN_DOWN_S 1, FRICTION_VISCOUS 2.674, MAX_SPEED 24, VELOCITY_WINDOW_MS 90, RELEASE_TAIL_MS 40, END_MARGIN_S 0.25 | platter.ts |

The behaviour, each as the web's (and docs/player.md:1205-1241 says it to a listener):

- **Take** (`pressed` :1575, `holdStill` :1603, `touched` :1635, `takeOver` :1668): a press on a live record
  takes it once the finger has gone TAP_SLOP_PX, or has stayed put HOLD_MS; taken from where it was as the finger
  went down, reaching back at most TAKE_BACK_S; a playing song is held (`hold()`) as it is taken, and plays on
  under those few points until then.
- **Hold** (`hand` :1756): every sample to the voice as a `hand` knot; a finger at rest is silence.
- **Release** (`release` :1778): the hand's speed from its samples' own times up to the last (`releaseSpeed`), the
  plan from that sample's moment when the lift came within RELEASE_TAIL_MS. A playing record: the motor's plan
  back to speed (`motor`, target the player's speed), the song sought to where the record will be, the sound
  handed over at its end. A paused record: a coast (`coast`), the song sought to where it stops, left paused. A
  cancel (the touch cancelled - a call, the app leaving the front) plays on, or rests, with no plan.
- **Coast**: the plan's curve, `drive` messages each frame (:1972), DRIVE_FOR_S ahead.
- **Wind-down** (`pausing` :1844): a pause asked for on the turntable winds the record down; with "Pause winds the
  record down" on, the window covering it and the sound running, the record's sound starts where the song is, at
  the song's own speed, and winds down with it; the caller seeks the song to where it stops. A pause from the
  cover always stops at once (NowPlaying.tsx's toggle).
- **Play during a coast or a wind-down** (`resuming` :1877): from where the record had got to - what was heard -
  not from where it was going to stop.
- **The arm** (`armTaken` :1893), a song change (`songChanged` :1536), a seek from elsewhere, the speed changing
  (`speedChanged` :1483), the player's state changing (`playingChanged` :1497), showing and hiding
  (`setShowing` :1436): as the web's.
- **The windows** (`keep` :2272): asked for round where the song is, on the 2 s grid, 4 s back, 36 ahead;
  refreshed within 6 s of the end, no more than every 3 s; a failure retried after 10 s; a 415 is the song refused
  for good (its words, deck.ts:2348), a 416 "deadwax said that is past the end of the song" (:2350).

**As built (slice 1, 2026-11-12).** Nearest to the above, where the web's code needed more:

- **`DeckHost` carries what the web reads off its module's audio** as well as the list above: `voiceMade()` (the
  voice's state made - handWindow's test), `sleepAudio()` and `closeAudio()` (setShowing's sleepDeckAudio and
  destroy's closeDeckAudio), and `post(DeckPost)`, the voice's messages as values. Its clock is a protocol of its
  own, `DeckClock`: `now`, `stamp`, `after(ms, run) -> Int`, `cancel`, `frame(run) -> Int`, `cancelFrame` - the
  web's setTimeout and requestAnimationFrame, numbered so a replay fires them by number. The deck's own clock timer
  and readings (keepClock, readClock, deck.ts:2156-2193) are not ported: the phone's clock is the voice host's (3.2).
- **`window` answers through a callback** with a `Result<DeckWindow, DeckWindowError>`, on the main queue, not
  `async throws`: Core has no concurrency, and a replay must answer each ask at the moment the web's trace did. A
  ticket drops the answer to an ask since superseded, as the web's request counter does.
- **The errors**: `.notFlac(words?)`, `.undecodable(words)` and `.channels(n)` refuse the song for good (the 415's
  path); `.pastTheEnd`, `.offline` and `.failed(words)` are retried after RETRY_MS (the 416's and a failed fetch's).
  `.offline` is retried because a phone back online, or a song that has finished downloading, can then have its
  window - the spec didn't say which.
- **`DeckSong`** is the deck's own `{ id, length, flac, kind }`; the album and the disc are the look's (2.3).
- **Inputs the web takes from elsewhere** come in as calls: `heard(VoiceHeard)` (the voice's report, the web's
  port.onmessage, deck.ts:585), `audioChanged()` (the module's audioChanged telling its listeners, :553) and
  `reducedChanged(_:)` (the reduced-motion query's change, :1367).

### 3.4 The player's part

James's rule: the deck touches the player only through **pause, seek and resume** - the web's own, whose
`holdSong` and `resumeSong` use the player's toggle. The phone's DeckHost is a thin adapter over PlayerModel:

| DeckHost | the phone |
| --- | --- |
| `song()` | PlayerModel.current: id, length (the engine's decoded length, else Navidrome's), kind (`suffix`, upper-cased as the web's `kindOf`, Turntable.tsx:46), album id, the disc (2.3) |
| `playing()` | PlayerModel.isPlaying - true from a resume's tap (`.loading`), as the web's `player.playing` is from its play() |
| `position()` | PlayerModel's last position (its ticker's, twice a second) - never a `queue.sync` from the main thread |
| `onPosition` | PlayerModel's position updates; and while a handover is judged, the `deck.position` queue's readings, one per frame (2.6) |
| `soundReady()` | the DeckController: deck engine prepared, voice made, not failed, not AirPlay, not interrupted (3.3) |
| `hold()` | PlayerModel.pause() (:320) |
| `resume()` | PlayerModel.resume() (:292) |
| seek (Turntable's, after a release or a wind-down) | PlayerModel.seek(to:) (:358) |
| `turnFace`, `show`, `grabbed` | the turntable's view (layers; the time line; the record's next tap ignored) |
| `window` | the window maker (4.4, 4.5) |

A pause and a resume do everything they do today - the lock screen's rate, the play queue's save, the plays rule -
as the web's toggle does. Nothing else of the player is touched. The one addition to PlayerModel is read-only:
`engineForDeck`, the engine behind a protocol with `position()` alone, for the `deck.position` queue (2.6); and the
`lastStartSeconds` the engine already reports in `debug()`, read off the main thread after each resume the deck
asked for (3.5).

**The deck's own resume isn't a foreign play.** The web's `planEnded` turns the motion to `turning` before it calls
`host.resume()`, so the `playingChanged(true)` that follows returns early (deck.ts:1985-1988, :1503). On the phone
the resume comes **before** the plan's end (3.5), while the motion is still the handover's plan - and the web's
`playingChanged(true)` in a handover plan reads as "played before the coast got back to speed" and fades the
sound at once (:1505-1514), which would leave the engine's whole start as a gap. So DeckRules notes the resume it
asked for (`resumeAsked`, set as it calls `host.resume()`, cleared by the next `playingChanged`), and a
`playingChanged(true)` that is that resume's is taken as the handover's own: nothing faded, the plan runs on to its
end. A play from anywhere else in that time (the transport, the lock screen) is still the web's case. With the
lead at 0 (every web trace, 7.0) the resume comes after the motion has turned to `turning`, as the web's does, the
flag changes nothing, and the port is the web's exactly.

### 3.5 The handover, timed by the engine's start

**The web** (`planEnded` deck.ts:1980, `handOver` :2014): at the plan's end the song is resumed; the voice holds
the song's speed from the plan's end until the player's position is past it by 0.02 s (or nowhere near it - sought
elsewhere), then fades over HANDOVER_FADE_S, at most HANDOVER_MAX_S later. The judge runs on each position report
and each frame (2.0.0-player.28: on reports alone the record's sound played on up to a quarter of a second over the
song). A plan of RESUME_IN_GESTURE_S or less, or any let-go under reduced motion, skips the handover: the sound
stops and the song plays in the gesture (:1810).

On the web this lines up nearly by itself: the element is heard within its output latency of the resume, about
what the voice's own 121.5 ms delay puts it behind. **On the phone it doesn't**: the engine is heard
`lastStartSeconds` after the resume - 0.2-0.4 s measured (1.3) - while the voice reaches the plan's end 121.5 ms
plus its own output latency after it. Resumed at the plan's end, the song would come in late and the fade would
jump the sound back by the difference: at 1x, up to a quarter of a second, heard as a stutter on every let-go.

**Phone.** The resume is moved earlier by what the engine's start takes. Every time below is host seconds, and
every "heard" is in **one convention** - the engine's: a render's host time plus `latency()`
(`outputLatency + ioBufferDuration`), which is how `lastStartSeconds` and `position()` reckon it (1.2). Whatever
that convention gets wrong about the speaker, it gets wrong for the song and the voice alike, and the difference -
the seam - is what matters.

- **`D`**, the voice's delay as heard: a knot stamped `t` is heard at `t + D`, with
  `D = HAND_DELAY_S + VOICE_LOOKAHEAD_S + L + latency()` = 0.1215 + `L` (3.2) + the deck engine's `latency()`,
  read from the deck engine's own session values as the plan is made.
- **`E`**, the song's resume-to-heard, **predicted**: the median of the last five `lastStartSeconds` of resumes of
  the same kind - **local** (a download or the cache's whole copy) or **streamed** - on this route, kept for the
  app's run. Before any, 0.3 s (notes/ios.md's 0.2-0.4 s). Not `startLead() + latency()`: that is the schedule's
  lead alone (about 50 ms), and leaves out the queue's hop, the lane's reset and begin, the second decoded before
  the node starts and the output's own start, which are most of it. A streamed song's resume decodes from the
  song's top (1.2), so its `E` grows with the position: for the streamed kind the prediction is `a + b x position`,
  fitted to its last five (b at least 0; before any, 0.3 s + position / 300).
- **The resume** is asked at `r = planEnd + D - E`, by a main-queue `DispatchSourceTimer` with the `.strict` flag
  and no leeway, so the song's first sample is heard as the voice sounds the plan's end. Its lateness - when it ran
  against `r` - is in Debug: the main thread is the one thing between the timer and the resume.
- **The target.** Early enough (`r` still ahead at the let-go): the song is sought to `plan.x`, as the web's release
  seeks it. Too late (a short plan, or a slow start - `r` already past): the song is resumed at once, at `r'`, and
  sought - before the resume, in the same call - to where the record will be when it is heard: the plan's position
  at `r' + E - D` (Core's `planAt`), carried on past the plan's end at the player's speed. Under the web's
  `RESUME_IN_GESTURE_S` (a plan of 0.05 s or less) this is always the case: the shortcut is **dropped**, and the
  general rule covers it - the song comes in where the voice is when it does.
- **The judge's `at` is the target the song was sought to**, not `plan.x`. With a moved target, a judge at
  `plan.x` would see the paused position (the moved target, already 0.02 s past `plan.x`) with `playing()` true
  from the resume's tap, and fade the voice before a sample of the song is heard.
- **The judge runs from the resume**, not from the plan's end, on the `deck.position` readings each frame (2.6), as
  the web's: the song heard past the target by 0.02 s (or sought elsewhere, or HANDOVER_MAX_S) fades the voice over
  HANDOVER_FADE_S. When it fires **before** the plan's end - a late resume heard while the voice is still in the
  plan's curve - it is the web's own case of a song played before the coast got back to speed
  (`playingChanged(true)` in a handover plan, deck.ts:1505-1514): the motion turns to `turning`, the voice fades,
  and `planEnded` finds nothing to hand over.
- **Reduce Motion** has no plan to wait out, but still no gap: the web stops the voice and plays from `plan.x` in
  the gesture (:1810), and the phone's song can't be heard for `E`. So at the let-go the deck posts a `take` at
  `plan.x` at the player's speed, stamped now - the record's sound jumps there, as the song does on the web - and
  the song is sought to `plan.x + speed x (E - D)`, where that take will be when the song is heard, and resumed
  at once; then the judge, as above. (The take reaches back as every take does: its first 0.12 s at speed come from
  just before `plan.x`.)
- **A song that can't start in time**: a predicted `E` over HANDOVER_MAX_S less the plan's length (a stream deep
  into a long song) is not held across. The voice holds to HANDOVER_MAX_S and fades, as the web's timer does, and
  the song comes in when it comes; Debug says "The song took 3.4 s to start".

In DeckRules all of this is one parameter, `handoverLead(kind, position)` (`E - D`, read at each let-go), and the
`resumeAsked` flag (3.4). Every trace exported from the web has the lead at 0 - so with it at 0 the port is the
web's exactly, and the phone's change is that parameter alone. `HandoverTimingTests` (7.2) runs it against two
engines rendering offline, in lockstep, where `E` is known from the offline engine's own accounting.

**What is still the web's, kept for parity and listened for**: once aligned, the judge waits until the song is
0.02 s past the target, plus up to a frame for the reading, and the fade is HANDOVER_FADE_S's exponential - so for
about 30 ms two coherent copies of the same music sound together, about 6 dB louder, before the voice is gone. The
web's seam is the same (its element and its voice); on the phone it is listened for in check 8, and the other way
is in 10, question 15.

Debug shows each let-go's predicted and actual `E`, the timer's lateness, the lead used and the seam - the song's
heard time less the voice's heard time for the same position, both in the engine's convention (6.2). If `E` proves
too uneven for this (the seam over 30 ms at 1x on the phone), the alternative is a hold that keeps the main output
running, so the song is heard within its output latency like the web's element - an engine change of its own (10,
question 2).

**As built (slice 1, 2026-11-12).** In DeckRules:

- `handoverLead: (DeckSong, Double) -> Double` - given the song and `plan.x`, the kind and position `E` is predicted
  from - read at each let-go of a playing record; 0 by default, when DeckRules is the web's exactly (every trace).
- A lead above 0 takes `releaseLed`. Under Reduce Motion: the web's stop, a take at `plan.x` at the player's speed
  stamped now, the song sought to `reducedTarget` and played in the gesture. Otherwise the handover plan starts as
  the web's, and either a timer (`DeckClock.after`; slice 3's host makes it the `.strict` DispatchSourceTimer) asks
  the resume at `planEnd - lead`, the release having sought the song to `plan.x` - or, that moment already past,
  the song is played in the gesture (`play: true`) and sought to `lateTarget`. The RESUME_IN_GESTURE_S shortcut is
  taken only with no lead.
- The judge runs from the resume (`handOver(…, judgeOnly: true)`: the plan's own drives go on). A plan resumed early
  (`resumed`) posts at its end only the hold drive (the song's speed from `plan.x`, HANDOVER_MAX_S), and only while
  the judge still waits; it asks no second resume. A judge that fires before the plan's end turns the motion to
  turning and fades - the web's play-before-speed case.
- `resumeAsked` is set as DeckRules calls `host.resume()` (in the web's planEnded too, where it changes nothing), and
  cleared by the next `playingChanged` **and by any new plan** (`startPlan`), so a resume asked for one plan is never
  taken as the next one's.
- `HandoverTiming` (DeckRules.swift) is the pure arithmetic: `voiceDelay` (`D`), `predictedLocal` (the median of the
  last five - the host keeps a list per kind and route), `predictedStream` (least squares over the last five, slope
  at least 0; one point, or all at one position, their mean; none, 0.3 + position / 300), `lead`, `holdsAcross`,
  `lateTarget`, `reducedTarget`. `holdsAcross` is for the host and Debug: DeckRules needs no rule of its own for a
  song that can't start in time - its lead runs past the plan, which is the late case, and the voice holds until the
  judge or HANDOVER_MAX_S, the web's timer.
- Held by HandoverPlanTests' hand-built cases only (the arithmetic; DeckRules with leads of 0.2, 5, and 0.15 under
  Reduce Motion; none, the web's shortcut). The two-engine HandoverTimingTests are 7.2's.

**Review (slice 1).** Read against the above and deck.ts, two things were wrong and are fixed: **Reduce Motion's
take held only a take's DRIVE_FOR_S** (0.12 s) - with the judge alone after it (no hold drive), the voice ran out
and slowed to still for the lead less 0.12 s before the song was heard, most of a second for a stream deep in a
song; it now holds the player's speed for HANDOVER_MAX_S, until the judge fades it. And **a plan silent at its early
resume whose window came before its end** got no judge (none was made at the resume) and so no hold at the end -
the voice ran out over the song, unfaded; the plan's end now makes the judge, at what the song was sought to, when
none runs, and posts the hold. Six tests added, each seen to fail on a mutation of the rule it holds: the Reduce
Motion take's hold and its judge; the late resume judged at its target (a judge at `plan.x` would fade a paused
song's voice) and ending the plan when it fires first (plan timer cleared, turning, no resume); a plan resumed early
holding at its end with one drive, stamped at the end, and no second resume; a resume asked for one plan not taken
by the next (`startPlan`); the plan that sounds only after its resume. **Left as it is, for James**: the judge's
HANDOVER_MAX_S runs from the resume, so with a lead over 3 s (a stream past about 14 minutes in) it fires before
the plan's end and cuts the coast short - turning at the player's speed early - where the web's runs from the end.

---

## 4. The sound

### 4.1 The voice, ported line for line

`deckVoice.ts`'s four functions become Core's `DeckVoice`: `newVoiceState`, `voiceCommand`, `renderVoice`,
`voiceReport`, line for line, in the same order, the web's line in a comment at each block. Everything they hold
comes with them:

- **The path**: knots in a ring of 64 (`KNOTS`, :249), played HAND_DELAY_S (0.12 s) behind; between two knots a
  Hermite cubic; each hand knot fitted with a tricube-weighted parabola over FIT_S 0.12 either side
  (SMOOTH_AFTER_S 0.09 after; :306-307); the rests and their edges: REST_S 0.04, MISSED_S 0.1, KEPT_ON 0.25,
  KEPT_S 0.003, EXTRAPOLATE_S 0.02, RESUME_S 0.017, QUICK_S 0.003 (:302-318).
- **The steering**: SMOOTH_S 0.01, FOLLOW_S 0.1, MAX_RATE 24, EDGE_S 0.004, QUIET 1e-5 (:511-519); a fade's
  `alpha(seconds / 4)` (:300).
- **The sinc**: a Kaiser-windowed sinc, ZEROS 12, STEPS 128, WIDEST 4, BETA 7 (:259), its table in a Float32Array
  (:260-273), its taps up to 2 x 12 x 4 + 2.
- **The DC blocker**: DC_HZ 10, its pole `exp(-2 pi DC_HZ / rate)` (:517, :523).
- **The limiter** (2.0.0-player.35): CEILING `fround(10^(-0.5/20))`, LOOKAHEAD_S 0.0015, HOLD_S 0.02, RELEASE_S
  0.06, SAFE `1 - 2^-30`, SNAP `2^-24`, its rings (RING 1024, MIN_RING 8192, two boxes) (:278-280, :561-592).
- **The messages**: `window {channels, start, rate}`, `take {at, rate, time, until}`,
  `drive {at, rate, accel?, time, until}`, `hand {at, time}`, `fade {seconds}`, `stop`.
- **The report**, REPORTS_PER_SECOND 30 (:82): where the sound is, and the health counters Debug reads.

**Two places where the Swift's form must differ from the web's, and its arithmetic mustn't.** Both allocate in JS,
where a worklet's garbage collector makes that harmless, and neither may on an audio thread:

- The `window` command (deckVoice.ts's window case) filters the channels it is given and makes a new window object.
  The Swift applies a fixed `VoiceWindow` struct of at most two channel pointers, a frame count, a start and a rate,
  made off the audio thread; the old window's pointers go back through the return ring (4.3).
- `renderVoice` grows the limiter's delay lines when it first meets more than two channels. The phone's voice is
  made for two (a mono window is played on both, as the web's is) and refuses more at the window's making (3.3),
  so the Swift makes both delay lines in `newVoiceState` and has no growing path.

Everything they compute is the web's, in the web's order; test A (7.0) covers both through the window swaps in its
traces.

### 4.2 The porting rules

So that the port can be held to the web's output exactly (7.0, test A), these are rules, not style:

- Every JS number is a Swift `Double`; every Float32Array is `Float` storage, read into a `Double` as JS reads it;
  every store into a Float32Array rounds to `Float` as JS does (both round to nearest, ties to even).
- No fused multiply-add: Swift doesn't fuse `a * b + c` unless asked, and the port never asks. The expressions
  keep the web's order of operations and parentheses, term by term.
- `Math.round(x)` is **not** `(x + 0.5).rounded(.down)`: that rounds 0.49999999999999994 to 1 (the sum rounds up
  to 1.0 in binary) and is wrong again near 2^52, where JS's is right. It is a helper written as the spec of
  Math.round reads - `let r = x.rounded(.up); return r - 0.5 > x ? r - 1 : r` - which is exact for every double
  (`r - 0.5` is exact wherever it matters), keeps -0 for x in [-0.5, -0] as JS does, and passes NaN and the
  infinities through. Its own test runs the JS cases (0.5, -0.5, 2.5, -2.5, 0.49999999999999994, 2^52 - 0.5,
  2^53, -0, NaN) against answers exported from Node.
- `Math.min` and `Math.max` are helpers with JS's meaning - NaN if either is NaN, and -0 below +0 - not Swift's
  `min`/`max` (which return whichever the comparison picks, so `max(.nan, 1)` is NaN but `max(1, .nan)` is 1, and
  `max(0.0, -0.0)` is -0.0; nor `Double.maximum`, IEEE's maxNum, which drops a NaN). The voice's NaN never comes from a valid message, but a test that replays the web's
  traces must agree with the web on every input it records. `Math.floor`, `Math.ceil`, `Math.abs`, `Math.sqrt`,
  `Math.sign` and `Math.trunc` map directly (IEEE-exact, signed zeros kept); `Math.fround` is `Double(Float(x))`.
- **Signed zeros are kept**, never "normalised" - a `-0` that JS carries into a division is an infinity of the
  other sign.
- An index made with JS's `| 0` or `& (n - 1)` is Swift's `Int32(truncatingIfNeeded:)` of JS's ToInt32 (truncate,
  then modulo 2^32) then the same mask - written once as a helper, tested on the large and negative cases.
- **No floating-point arithmetic in the C target.** The ring (4.3) moves indices and bytes only: clang's default
  `-ffp-contract=on` fuses `a * b + c` within a C expression, which Swift never does, so any maths that strayed into
  C would stop matching the web on an arm64 build.
- **The transcendentals go through one `DeckMaths` protocol**, the whole port generic over it: `exp`, `log`,
  `sin`, `cos`, `atan2`, `hypot`, `pow`, `log10` - every one the ported code calls, not only the voice's
  (`Math.exp`, `Math.sin`, `Math.pow` at deckVoice.ts:105, :271, :300, :522-523, :561-569, :592; platter.ts's `exp`
  and `log`; turntable.ts's `atan2`, `cos`, `sin`, `hypot`; playSpeed.ts's `log` and `pow`). Two conformances:
  `PlatformMaths` (Foundation's, in the app) and `RecordedMaths` (the web's own answers to every call a trace made,
  in the order made, in test A). Specialised at compile time - the render entry is a concrete, non-generic function
  over `PlatformMaths` - so it costs nothing at render.
- Nothing allocates after `newVoiceState`: every array the web makes once is made there as an
  `UnsafeMutableBufferPointer` and freed with the state; nothing the render calls makes an array, a string or a
  closure. The same code runs on Linux in the tests and on the audio thread on the phone.

**As built (slice 1, 2026-11-12).** `DeckMaths` is an instance protocol - a value the port is made with - not a
static one: `RecordedMaths` counts each test's calls, and Swift allows no static stored state in a generic type. So
constants that need no maths live in plain enums (`Platter`, `TurntableGeometry`, `PlaySpeed`, `DeckConstants`) and
the sums that do in small generic structs over a DeckMaths (`PlatterPlans`, `TurntableTrig`, `PlaySpeedScale`);
platter.ts's FRICTION_DRY, computed once at load, is computed once per PlatterPlans. `RecordedMaths` answers by the
input's bits, counts and hashes every call in order, and answers a call the web never made with NaN, recorded as
missed (a test fails on any).

### 4.3 Its host: an AVAudioSourceNode on a second AVAudioEngine

`DeadwaxAudio/DeckEngine.swift`: an AVAudioEngine of its own, an `AVAudioSourceNode` of two non-interleaved Float32
channels at the output's rate, into its main mixer at unity, to its output. Its render block calls the voice and
nothing else. A second engine because the song's engine stops its output on every pause (1.2), which is exactly
when the record's sound runs; one engine would mean changing it (James decided a second; the plan's risk 2).

**Real-time safe**, by construction and by test:

- **No allocation, no lock, no Objective-C message, no Swift reference counting** in the render block. It
  captures only an `UnsafeMutablePointer` to a host struct made beforehand; it reads and writes only through
  pointers. The voice's state is a struct reached through that pointer - no class reference, no Array, String,
  closure, existential or `print`/`os_log` anywhere the render reaches.
- **Non-generic at the render**: the render entry is one concrete function (`DeckRender.render(_:frames:now:)`) over
  `PlatformMaths`, with the voice's generic functions `@inlinable` and `@_specialize`d for it, so no generic
  metadata is looked up at render: a first use of a generic type's metadata can take the runtime's lock.
- **Warmed once, off the audio thread**: before the deck engine is first started, the host renders 1024 frames of
  silence and one of each message through the same entry on its own queue, so every lazy first-time thing (type
  metadata, the sinc's table pages faulted in, the converter's first call) happens there and never on the audio
  thread.
- **Messages in**: a single-producer, single-consumer ring of fixed-size message structs (a tag and its doubles),
  256 deep, written on the main thread, read at the top of each render; each message is applied with
  `voiceCommand` at the block's start, as the web's worklet applies its port's messages between blocks. **A full
  ring drops the message and counts it** ("Messages dropped", 6.2) - the producer never waits. 256 is 2 s of a
  hand's samples at 120 Hz with the drives beside them; a full ring means the render has stopped, and the stop
  will reset the voice anyway.
- **Windows**: allocated, filled and converted off the audio thread (4.4); a `window` message carries a
  `VoiceWindow` (4.1) by value. A window the voice has let go of goes back through a return ring of 8 - more than
  can ever be in flight (one in use, one on its way, a refresh) - and is freed on the window queue. A full return
  ring keeps the window (leaked until the engine stops, counted) rather than freeing it on the audio thread.
- **Reports out**: the voice's 30 reports a second, and the health counters, through a third ring, read on the
  main thread each frame (or each 33 ms when no frame runs). Full: the oldest report is overwritten, the counter
  kept.
- **The main thread never touches the voice's state** except while the deck engine is stopped (made, reset,
  freed) - every change while it runs is a message.
- **The atomics**: the rings' indices are C11 atomics (acquire on read, release on write) in a small C target,
  `CDeckRing` - Synchronization's `Atomic` needs iOS 18 (1.3; 10, question 1). No floating point in it (4.2).
- **The test**: slice 2's DeckRealTimeTests call the render entry 10,000 times over every message kind and two
  window swaps with an allocation hook installed (`malloc_logger`, the hook Instruments' allocation tracking uses,
  declared through a test-only C shim) that **counts only allocations on the rendering thread** (its thread id,
  taken as the run begins): the test runner allocates on its own threads throughout, and a process-wide count would
  fail for them. Before the run, the hook must see a **canary** - one deliberate `malloc` on the rendering thread -
  or the test fails as "the allocation detector saw nothing", naming the detector rather than passing on a hook
  that isn't called. No fallback to `malloc_zone_statistics`: a weaker check that passes is worse than a failure
  that says why. The test runs in a release build - `swift test -c release --filter DeckRealTimeTests`, a step of
  its own on ios.yml's macOS job - because a debug build's unspecialised generics and retain/release are not what
  the phone runs; it uses only the package's public and `@testable`-free API, so it builds in release.
- **A review rule**: the render file imports only `CDeckRing` and DeadwaxCore's voice. Swift's `@_noLocks`
  attribute (the compiler checking a function takes no locks and allocates nothing) was looked at: it is
  underscored and experimental in the toolchain the package builds with, so it is tried in slice 2 and kept only if
  it builds on both CI runners without flags.

How sure: the rules are the standard ones for a render callback (Apple's "real-time" guidance for AUs and
AVAudioSourceNode); the thread-filtered hook with its canary is sure as a test of what it sees, and what it can't see
- a lock taken without allocating - is the review rule's and the warm-up's.

### 4.4 The window from the file on the phone

**The web** fetches a window of the song from deadwax - cut from the very copy the phone plays, levelled as it
is - and decodes it with decodeAudioData, which resamples it to the context's rate: the voice always has a window
at its own rate (deck.ts `fetchWindow`, `decode`). Hi-res played as it is gets shorter windows (docs/player.md:1253-1256).

**Phone.** `DeadwaxAudio/DeckWindows.swift` makes it from the file the phone already has:

1. **The file**: the download, else the stream cache's complete copy - the order PlayerModel+Engine.swift:190
   opens a track from. A song whose copy isn't whole yet has neither: 4.5.
2. **Where it starts**: on the web's own 2 s grid - `keep()` places a window from `floor((where - back) / 2) x 2`
   (deck.ts:2272, WINDOW_GRID_S) - and is decoded from `P` = 0.2 s before that (or from 0, near the song's start).
   Both are whole numbers of frames at every rate a FLAC has, 11.025 and 22.05 kHz included (0.2 s is 2205 and
   4410 frames there; any rate that is a multiple of 5 Hz), and at every output rate. (This spec first said a 10 ms
   grid, which is half a frame at 22.05 kHz.) Decoded by the engine's own decoder (FileSource over AVAudioFile,
   whose `framePosition` is sample-exact for FLAC).
3. **Levelled** by GainedSource at the entry's factor - the same Float the lane multiplies by, from the same
   `levels.open(…)` - so the record is as loud as the song (the web's `level`).
4. **Converted**, when the file's rate isn't the output's, by an AVAudioConverter set as the lane's is - mastering,
   `.max`, prime method `.normal` (PlaybackEngine.swift:1019-1030) - and the pre-roll's output (`P` at the output's
   rate, whole) dropped. Slice 2 checks `P` is longer than the converter's filter reaches (its output for a
   pre-roll of `P` and of `2P` must agree past the pre-roll, bit for bit); if not, `P` grows to the next 0.2 s.
5. **In pieces**: decoded and converted one second of the file at a time into the window's own buffers, never the
   whole stretch at the file's rate at once - 40 s of a 192 kHz file decoded whole is 61 MB of Float32 before a
   frame is converted.
6. **Handed to the voice** as `window {channels, start, rate}` with `rate` the output's - as the web's always is.

Its size: 40 s at 48 kHz, two channels of Float32, is 15.4 MB; two while one replaces the other. At an output
faster than 48 kHz (a USB DAC), the same bytes - 20 s at 96 kHz, 10 s at 192 kHz - through deck.ts's own scaling
of the margins to a shorter window (`windowMargins`, :254). Made on a queue of its own at `.userInitiated`, the
newest asked only (the web's latestOnly rule); dropped and made again when the output's rate changes.

**How long it takes is measured, and shaped if it must be.** Decoding 40 s of FLAC is quick; converting it with
the mastering converter at `.max` may not be - the phone's figure is unknown. Debug shows "Window made in" for each
(6.2). If the phone's figure for a 44.1 kHz song is over 150 ms - long enough that a press soon after a skip finds
no window - the window is made in two steps: 8 s round the playhead first (4 back, 4 ahead, on the same grid),
handed to the voice at once, then the whole 40 s, which replaces it. Both start on the grid with the same `P`, so
over the stretch they share their frames are the same frames, and the swap under a sounding voice changes nothing
it plays.

**Equal to the song - where that means something.** A lane's converter starts afresh wherever the lane begins: at
a song's start, a seek's frame, the frame every pause held (1.2: `reset()` on every pause, resume and seek). Its
output frames sit on a grid fixed by that frame; the window's on a grid fixed by the 2 s grid. They are the same
frames only when the two grids coincide - a lane begun at 0, or at an input frame a whole number of the
conversion's cycles from it (147 frames, for 44.1 to 48 kHz), and after a handover (a seek and a resume) almost
never. The songs after a gapless join carry their lane's grid on, so theirs coincide only when every earlier
song's length is a whole number of cycles - which a CD rip's is (588-frame sectors are four cycles), and a
download from elsewhere may not be. None of this matters to what is heard - the voice reads the window through its
own sinc at a continuous position, never frame for frame - but it decides what a test can claim. So slice 2 has
two tests, not one:

- **(a) the window maker, on the grid**: a song rendered offline through the engine from 0, and a window of a
  stretch made here, compared frame by frame - bit-exact, or under -120 dBFS (10, question 3). This proves the
  decode, the level and the conversion are the lane's own.
- **(b) the seam, off the grid**: a FLAC made by the test of three tones (1, 5 and 12 kHz, each at -12 dBFS,
  44.1 kHz, so every sample's true value is known), played through the engine offline from a seek to an odd place
  (42.0123 s), and the voice, at rate 1 and still, reading a window of the same stretch. Each output is compared
  with the tones computed exactly at the song time of each of its frames - the lane's frame `n` at the seek's
  frame plus `n` output frames, the voice's at the position its report gives. The lane's error is its converter's,
  the voice's its sinc's (a Kaiser BETA of 7 is about -70 dB); a window placed a twentieth of a sample off shows as
  a phase error of about -44 dB at 1 kHz and -22 dB at 12 kHz, and fails it. This is the test of what the
  handover's seam depends on, and of the window's start time being where it says.

### 4.5 The /scrub fallback

For a song still streaming in - nothing downloaded, the cache's copy not whole yet - **every** window comes from
deadwax, as on the web, until the copy is whole; from then on, the file. James's "a part still streaming in" is
read as the song whose copy isn't whole yet, not only the stretch not yet arrived: the part that has arrived can't
be decoded from where the window starts - StreamSource reaches a frame by decoding from the song's top (1.2), and
a partial file has no seek table to do better - so a window from it would cost a decode of everything before it,
on the phone, on every refresh (10, question 14 has the other way).

- `scrub` added to Routes.swift: `GET /deadwax/navidrome/scrub/{song_id}` with `at` and `seconds` -
  **without** `max_rate` and `level`, so deadwax sends the original FLAC's own frames: the phone converts and
  levels them itself, the same way as a local file (4.4, steps 2-6).
- `at` is the window's grid start less `P`; `seconds` the window's length plus `P` plus 1 s, at most 60 (the
  route's bound) - the 1 s because deadwax starts the answer at a FLAC frame or a fragment at or before `at`
  (flac_window.py), up to about a second earlier.
- The answer is written to `Caches/deadwax/scrub/<song id>-<first>.flac`, read through FileSource like any file,
  and deleted once its window is made. `X-Deadwax-Window` (`first/samples/rate`) says where its first frame is in
  the song: the window maker skips `(gridStart - P) x rate - first` frames to reach the pre-roll, and takes **the
  window's end from `first + samples`, not from what was asked** - deadwax cuts a window at 8 MB
  (`WINDOW_MAX_BYTES`, src/player_cache.py:286), so a hi-res song's windows come back shorter (about 11 s for a
  192 kHz, 24-bit stereo FLAC) and the deck's refresh rules use the end it has (the web's "Hi-res played as it is
  gets shorter windows").
- 415 is the song refused for good, with deadwax's words (deck.ts:2348); 416 "deadwax said that is past the end
  of the song"; 204 (the server's answer to a request it saw go away) is no window and no error, as a cancel;
  anything else "deadwax didn't send it - " and its words, retried after RETRY_MS (:2350-2352) - Debug's words,
  all of them.
- A window made from a `/scrub` answer and one made from the local file over the same stretch are equal sample for
  sample (slice 2's test, through a fake server answering with flac_window.py's own output for a fixture): the
  server cuts the very frames of the same file.

What it costs shows in Debug's "Data used" (6.2). Offline, there is no fallback (2.8).

### 4.6 The audio session

- **Never changes the category, mode or options.** The app's AudioSessionController owns the session
  (`.playback`, long-form); the deck engine plays in whatever is active. Before it starts, the DeckController calls
  the controller's `activate()` (idempotent) - so a press on a **paused** record, with another app playing, takes
  the sound from that app as pressing Play would. Said here because it is a choice, and the right one: the record's
  sound is deadwax playing.
- **When it runs** (10, question 13): prepared (`prepare()`, its voice state made and warmed, 4.3) when the
  turntable shows; **running while the turntable shows and the song plays**, and **while the record sounds**
  (a hand, a coast, a wind-down, a handover) whatever the song is doing; stopped **at once** when the song stops
  with the record quiet (a pause from the lock screen, the AirPods, Control Centre), and **0.5 s after** the record's
  sound ends otherwise. While the song plays, the song's own output is running, so a second running output changes
  nothing iOS reads - and the press that matters most, on a playing record, finds the engine already running: no
  start in the voice's 121.5 ms, and a lead (`L`, 3.2) measured continuously instead of from a cold start. While
  the song is paused, the deck's output runs only while it sounds, so the deck is almost never why iOS thinks the
  app is playing - almost: see the lock screen below. A start that does happen (a press on a paused record) takes
  some milliseconds out of the voice's delay; one that takes longer than 100 ms loses the turn's first moment, and
  is counted in Debug ("Slow starts").
- **The lock screen after a wind-down.** A wind-down's sound runs about a second after the pause, then 0.5 s more,
  so for about 1.5 s after a pause the deck's output is running while the song's has stopped. iOS goes by the app's
  running output, not the PlaybackRate it is told (notes/ios.md, "The pause the lock screen didn't see") - and the
  fix for that was to stop the output at the pause, because an output that stops **later** wasn't always seen as a
  pause. So as the deck engine stops after a paused song, the DeckController asks NowPlayingController to publish
  the paused state again (its existing update, rate 0, the elapsed time), as the pause itself did. Whether that is
  enough is a phone question: check 21 (8). If it isn't, the fallback is to keep the deck silent while the song is
  paused (10, question 16).
- **Its own notifications.** AudioSessionController's three callbacks are single closures PlayerModel already sets,
  so the DeckController doesn't take them: it observes `AVAudioSession.interruptionNotification`,
  `routeChangeNotification` and `mediaServicesWereResetNotification`, and its own engine's
  `AVAudioEngineConfigurationChange`, through NotificationCenter, on the main queue.
  - **An interruption** (a call, Siri, an alarm): a taken press is ended as a cancel that rests (3.1); the deck
    engine stops; `soundReady()` is false until the interruption ends; counted ("Interruptions").
  - **A route change** (headphones in or out, Bluetooth, a car): the voice stops (a `stop`, then the engine), the
    window is dropped if the output's rate changed, `L` starts again from its floor, AirPlay is checked again, and
    the engine is prepared on the new route. A song that the route change paused (the old device gone - PlayerModel's
    rule) is, to the deck, a pause the turntable didn't ask for (2.8).
  - **Media services reset**: every AVAudio object is gone; the deck engine is made again from nothing, the voice
    state with it.
  - **The engine's configuration change**: it has stopped itself; prepared again, started at the next sound.
- **Stops when the app leaves the front**: scenePhase leaving `.active` stops it at once and tells the deck's
  rules it is hidden (the web's `setShowing(false)`): a hand is let go as a cancel; a plan's end still hands the
  song back, on its timer.
- **AirPlay**: not prepared while the route has an AirPlay output (2.8); `soundReady()` false.

### 4.7 What the delay adds up to

By design, 121.5 ms behind the hand (HAND_DELAY_S and the limiter's lookahead, the web's worklet figure,
debugRows.ts:451); then `L`, the render's lead (3.2: between one and two blocks - 21 to 43 ms at iOS's 1024
frames - by how far ahead of its presentation iOS asks for each block, which only the phone says: Debug's Clock
row); then the output's latency - a few ms on the speaker, 150-250 ms more on Bluetooth (docs/player.md:1280),
which no app can shorten. On the speaker, about 150-170 ms in all, against Safari-on-http's main-thread voice's
121.5 + 43 ms and its own (1.3, item 7). Debug's "Delay behind the hand" says all of it, as `D` (3.5) is made of it
(6.2).

The one part of it the app could shorten is the block: a `preferredIOBufferDuration` of 256 frames while the
turntable shows would take `L` to 5-11 ms. But it is a setting of the session, so the song's engine would run on
it too - four times the wake-ups, for a gain only the hand can feel - and the session's options are
AudioSessionController's, untouched here. Not done; measured first (10, question 22).

---

## 5. The fader

### 5.1 Its place, and its words

**The web** (playSpeed.ts, SpeedFader.tsx, SpeedChip.tsx, docs/player.md:1371-1420):

- **The fader** stands at the right of the platter, as a deck's pitch fader: FADER at x 359, from 150 to 318 in
  the plinth's units; its slot 6 wide, radius 2 (#121117 with a #2c2a36 edge); a knob 20 by 12, radius 3, in the
  arm's greys (#8e8a96 with a #56525f edge, #c9c6d1 while held) with a 1.5 grip line across it (#0e0c12), 3 from
  each end; a mark at 1x, two thirds of the way up, 2 thick, 2 past the slot each side, #8e8ea3, lit #34d399 while
  the speed is exactly 1x. **Up is faster**: logarithmic, by octaves - 0.25x, 0.5x, 1x and 2x evenly spaced.
- **A drag** takes hold once the finger has gone TAP_SLOP_PX, from where the speed is then, so a touch never
  jumps it; the speed changes as the finger moves; a drag that ends within SPEED_DETENT (0.02) of 1x lands on
  exactly 1x.
- **The readout** at the plinth's corner (READOUT 344, 349): the speed in a well, `1.00x`, `1.25x`; a tap on it
  back to exactly 1x. Its face (app.css:1392-1423): a hairline `--dw-border` edge, radius 4, the well (black at
  0.2) over the plinth with the well's inset shadow, mono with tabular figures, padded 0.15em by 0.4em, its text
  `--dw-text-2`. Off 1x it is the toggled face - `--dw-accent-text` (#d8b4fe), a `--dw-toggled-border` edge, the
  toggled fill over the plinth, no inset - the same face the chip has, so "not at normal speed" looks one way
  everywhere. Drawn over the error line (z-index 1).
- **Its target** never reaches the record: the record keeps every touch on itself (`faderTarget`; FADER_FROM is
  the record's rim plus 1); at least 44 pt wide unless the plinth is too small (`--app-tt-fader-cap` 14%).
- **The chip** on the cover: `1.25x` at the left end of the row under the transport, whenever the speed isn't 1x,
  a tap back to 1x; nothing at 1x, and nothing moves when it comes and goes (the web's footer holds its buttons at
  its right end, `justify-content: flex-end`, and the chip takes the left with `margin-right: auto`). STYLE.md's
  toggled chip in a 44 pt target: 28 pt tall, 8 pt padding, radius 4, the toggled edge and fill, `--dw-accent-text`,
  mono, footnote, semibold, tabular (app.css:1432-1459). **Not on the turntable**: the readout says it there
  (`.app-is-turntable .app-speed-chip { display: none }`, but for a phone on its side). The mini player doesn't
  show the speed.
- **It stays where you left it**, per device (`deadwax-player-speed`, '0.25' to '2' as text; anything else 1x).
- **The turntable follows it**: the platter turns at it (50 rpm at 1.5x); a take starts its sound at it; the motor
  brings the record back to it (`motor`'s target); a wind-down winds down from it. A turn of the hand is 1.8 s of
  the song at any speed.

**Phone.** All of it, in the same places and words (2.9): the fader's layers in the turntable's view, the
FaderTouchView over its target (3.1), the readout a UIKit control drawn as the web's face (Palette's ttWell,
wellInset, toggledFill, toggledEdge, accentText; 2.14), a layer above the overlay lines. Kept in UserDefaults under
`deadwax-player-speed`, read by the web's rule. The mini player doesn't show it.

**Phone: the chip's place.** The app's footer isn't the web's: it spreads AirPlay, Up Next and ••• across the row
(AirPlay | Spacer | Up Next | Spacer | •••, NowPlayingView.swift's footer), so there is no free left end, and a slot
"always there" before AirPlay would move AirPlay off the left edge for everyone, at 1x too. So the chip is an
**overlay in the gap between AirPlay and Up Next**, centred in it, the footer's buttons untouched: nothing moves
when it comes and goes, as the web's rule asks. At 393 pt that gap is about 100 pt and the widest chip (`0.25x`,
mono footnote, 8 pt padding) about 52 pt; at the accessibility sizes, where it wouldn't fit, the chip is not drawn
and the speed is said by the ••• menu's own line instead (**new**: "Speed 1.25x - back to normal speed", the
chip's action). Shown on the cover only, as the web's. Its face: the toggled chip above, as a ButtonStyle. (10,
question 19.)

**Phone: a tick at 1x** (**new**, Apple's pattern; 10, question 17): a drag that crosses into the detent gives one
`UIImpactFeedbackGenerator(style: .light)` tick - as a picker's wheel ticks on its rows - and a drag let go there
lands on exactly 1x, as the web's does. Not for the arrows' steps (VoiceOver's own sound says those), not for a
readout's tap (the speed jumping is feedback enough).

### 5.2 The engine change

The web's speed is the audio element's playbackRate with pitch preservation off - a record deck's pitch, not a
time-stretch - and "At 1x nothing is touched" (usePlayer.ts:43-56, :555-578). The phone's, as its own slice:

- **An AVAudioUnitVarispeed per lane**, after the player node, before the mixer: it resamples, so the pitch moves
  with the speed, as the web's does; its `rate` takes 0.25 to 4, the fader's whole range. The lane's converter
  (before the node) and GainedSource (before that) are unchanged. (Looked at and not taken: a second
  AVAudioConverter per lane at the speed's ratio, before the node. It would put the speed into what is scheduled,
  so a drag of the fader - a new ratio every frame - would mean rescheduling ahead of the playhead continuously,
  and the scheduled audio would be heard `aheadSeconds` late. A varispeed after the node changes what is heard
  next, at once.)
- **At 1x, out of the sound's path**: the varispeed bypassed (`bypass`, an AVAudioUnit's) or the lane connected
  without it - whichever is measured bit-exact against today's engine (5.3). "Nothing the app plays changes unless a
  change asks for it."
- **Positions in the song's time**: the player node's frames are the song's frames (at the output's rate, after
  the lane's converter) - the varispeed, after the node, consumes them `s` times as fast. So the heard position is
  the node's frame at the render's host time, less what is between the node and the speaker counted in the
  song's time: `latency()` times `s`, plus the varispeed's own delay (its resampler's group delay, in the song's
  frames - measured, 5.3, not assumed 0). A speed changed mid-song changes `s` from the render at which it took
  effect: the timeline keeps each stretch's speed and host time, so the position stays exact across it.
  `aheadSeconds` (what is scheduled ahead) stays counted in the node's frames, and the schedule's wall-clock
  reach is `aheadSeconds / s` - at 2x the decoder runs twice as fast to stay ahead, at 0.25x a quarter.
- **Joins at speed**: every lane's varispeed holds the same rate; gapless joins stay sample-continuous through it
  (one node, one varispeed, its songs back to back); a change of lane at speed starts the new lane at that rate.
- **The lock screen told the rate**: MPNowPlayingInfoPropertyPlaybackRate the speed while playing (0 paused),
  DefaultPlaybackRate 1.0 - the song's own speed - so the lock screen's scrubber moves at the speed (the web's
  "The lock screen's scrubber moves at the speed"). Fairly sure DefaultPlaybackRate should stay 1.0 (Apple's
  meaning: the normal rate); checked on the phone (8).
- **The motor's target** is the speed (DeckRules already takes it from slice 1: `speedChanged`, deck.ts:1483).
- **Plays** are counted by the song's time heard, which the timeline now gives at any speed: half the song (or
  four minutes) whatever the speed - "at 2x that comes in half the time".

### 5.3 What must be measured before anything is built on it

On ios.yml's macOS runner, in offline manual rendering, before the fader's view is written:

1. **1x is today's sound, bit for bit**: the Phase 1 render tests (EngineRenderTests, GainRenderTests,
   UpNextRenderTests, …) pass unchanged with the varispeed in the graph and bypassed - and, separately, connected
   and at rate 1 - and a 30 s file of noise and a sweep renders identically to the engine without it. Whichever
   of bypass or removal is exact is the one shipped (10, question 8).
2. **Its quality**: a -6 dBFS tone at 0.25x, 0.5x, 1.5x and 2x; the products that are not the tone measured, and
   a tone that 2x puts above the output's Nyquist measured for what folds back - the bar is the lane converter's
   own (EngineRenderTests' `theRateConversionMeasured`), reported to James with the numbers before it ships. Its
   render quality set to the most it has.
3. **The position at speed**: a click track at 1.5x - the heard position against the clicks heard, within one
   output frame.
4. **Joins at speed**: Test sounds 9 and 10 (one tone cut in two) at 2x and 0.25x - no break.
5. **A speed changed while playing**: no click, no position jump.
6. **Its cost**: render time at 2x on a 192 kHz file.
7. **Crossing 1x while playing, both ways**: a drag from 0.9x up through 1x to 1.1x and back, rendered. Bypassing a
   running varispeed takes its resampler, and that resampler's delay, out of the path at once - a jump of that
   many frames in the sound, heard as a click, unless the bypass is done on a frame boundary that hides it. If it
   clicks, the varispeed stays in the path (at rate 1, not bypassed) for the rest of that stretch, and is bypassed
   at the next point the engine starts a lane afresh anyway - a pause, a seek, a song that isn't a gapless join -
   so 1x is untouched from there on (10, question 8).
8. **Its own delay**: a click at 1x through the varispeed not bypassed, and at 1.5x, against the node's frame -
   the number item 3's position subtracts.

On the phone (8): the same 9-and-10 by ear at 2x, the lock screen's scrubber, and AirPlay at speed.

---

## 6. Settings and Debug

### 6.1 You > Playback

In the web's order (You.tsx:296-320): Gapless, **Now Playing opens as**, **Pause winds the record down**, then
Normalization (the phone has no Maximum quality: it decodes hi-res itself). PlaybackSection is a run of Sections,
one a setting, each with its own note as its footer - Gapless's (header "Playback") and Normalization's (its note,
then YouWords.kept) - and the two new ones are Sections of their own between them, the same way:

- **Now Playing opens as**: a Section headed "Now Playing opens as", radio rows as Normalization's are - "Cover",
  "Turntable", each a Button with the checkmark in Palette.accent, `.isSelected` on the chosen one,
  `.accessibilityElement(children: .ignore)` with its label - and the note (2.9) as its footer. Kept under
  `deadwax-player-opens-as`: 'turntable', or anything else for the cover (persisted.ts:46-48).
- **Pause winds the record down**: a Section with a Toggle of that name, on by default, its note as the footer.
  Kept under `deadwax-player-wind-down`: 'off', or anything else for on (persisted.ts:49-51).
- YouWords.kept ("This is kept on this phone. Normalization changes from the next thing you play.") stays
  Normalization's: it names Normalization. The two new notes don't add a kept line - the web's notes don't, and
  that each setting is this phone's is the section's own way.
- Both per device, as the web's are; read once at launch and written on change, as Repeat and Normalization are.

### 6.2 Debug's Turntable section

A section of its own, after Playing, drawn from Core's port of `turntableRows` (debugRows.ts:442) - one fact a row,
in the web's order - and held to the web's rows over exported reports (7.0). The web's words where the phone has
the same fact; new rows marked.

| row | the phone's value | the web's |
| --- | --- | --- |
| Turntable sound | "Off: the turntable isn't showing"; "Off: " and the engine's own words when it couldn't start; "Off: it isn't a FLAC file (it is MP3)"; "Off: still starting - a press scrubs silently until it has"; "Ready: 0:42-1:22, FLAC, decoded at 48 kHz" (the window ready, whether or not the engine is running - on the phone it rests between sounds by design); the window's failure; "Off: its window is loading - a press scrubs silently until it is in"; "Off: no window yet - …" | :341-358, verbatim. The web's "waiting for a tap" has no case: the phone has no gesture rule. "no Web Audio" and "neither an AudioWorklet…" have none either. |
| Window from (**new**) | "This phone's download" · "The copy kept on this phone" · "deadwax - the song is still coming in" · "Off: no window - this phone is offline and the song isn't all on it yet" | - |
| Voice | "On its own audio thread (an AVAudioSourceNode)" (**phone**: the web's says "an AudioWorklet") | :372 (:371 is the main thread's, no phone case) |
| Clock step | "21.3 ms at a time" - the render's block (1024 frames at 48 kHz, iOS's own for long-form playback; 1.2) | :373 |
| Clock (**new**) | "The record's clock runs 23.9 ms behind the render's time stamps; the largest lead under the last hand 24.6 ms" - `L` and the largest lead (3.2) | - |
| Data used | "1.4 MB a window; 4.2 MB fetched since the turntable showed, the last window 1:12 in" - `/scrub` windows only | :374-381, verbatim |
| Turntable timing | "The song was back 0.31 s after the last let-go - 0.24 s of it the record's run back to speed" | :389-400, verbatim |
| Handover (**new**) | "Resumed 0.17 s early for a start of 0.29 s (it took 0.31 s, the timer 2 ms late); the song came in 18 ms after the record's sound was there" - predicted and actual E, the timer's lateness, the seam, all in the engine's one convention (3.5) | - |
| Position read in (**new**) | "1.2 ms at worst during the last handover" - the `deck.position` queue's longest wait on the engine (2.6) | - |
| Window made in (**new**) | "0.21 s for 40 s of a 44.1 kHz song" - decode, level and conversion (4.4) | - |
| Messages dropped (**new**) | shown only when not 0: "3 of the record's messages were dropped" (4.3) | - |
| Limiter | the web's | :421-428, verbatim |
| Frames under a hand | the web's ("…, 3 late, the longest gap 41 ms") - late is the web's 34 ms | :429-432, verbatim |
| Touches under a hand (**new**) | "238 a second, from 120 events a second" - coalesced samples and their events | - |
| Not restarted | the web's | :433 |
| Interruptions | the web's ("The sound was interrupted once") | :434 |
| Delay behind the hand | "121.5 ms behind the hand by design (on its own thread), then what this device's audio adds - it says base 21.3 ms, output 8.1 ms" - base the IO buffer, output the output latency; and `L` in the Clock row | `latencyNote` :457-468, verbatim |
| Slow starts (**new**) | "2 presses whose sound started after its delay, the worst by 18 ms" - the deck engine's start from rest (4.6) | - |
| Recording | "Record 20 s"; then "20 s recorded: save the file and send it" with a share button (6.3) | :474-487; the save action "Save the recording (1.2 MB)" becomes the share sheet's button, **phone** |
| Speed (slice 4) | "Normal (1.00x) - the song as it is, nothing changed"; "1.25x, the pitch moving with it"; the note "The song moved at 1.25x over the last few seconds of playing" (PACE_WINDOW_S 8) | `speedRow` :285-297; the browser's refusals have no case |

The web's "Main-thread sound" and "Test bench" rows have no phone case and aren't drawn.

### 6.3 Recording

The web's Debug can record 20 s of the record's sound "with every touch and what the voice made of it, as a file
to send with a bug report" (`recordDeckSound`, debugRows.ts:474). The phone's records the same - the touches as the
deck had them, the messages it posted, the voice's output - into the same JSON shape
(`deadwax-turntable.json`), so one reader reads both; saved through the share sheet (ShareLink - Apple's way to
hand a file out of an app; sure). This is what makes the A/B against Safari (8, check 23) more than an ear's word:
two recordings of the same song, compared on the Mac. Recommended in slice 3 (10, question 7).

The web's recording (`DeckRecordingData`, deck.ts:851-920) carries the messages the voice was sent, what it was
heard to play (`heard`), its blocks, each block's time (`blockTimes`), the clock's mapping, `delaySeconds` and
`scriptLagSeconds`. That is enough to **replay** it: the same messages, at the same voice times, block by block,
through the Swift voice on the Mac, and compared with what Safari's voice made - within -100 dB, as test B (7.0).
So check 23's recording from Safari is also an objective test of the port on a real session, not only an ear's
(`ios/scripts/replay_deck_recording.swift`, a `swift run` target of the package, slice 3). The phone's recording
adds, under keys of its own the web's reader ignores: `L` per block, the touches' raw timestamps, and each
handover's predicted and actual `E`.

---

## 7. The slices

### 7.0 The fixtures, exported from the web

As Phase 1's (`ios/scripts/export-traces.cjs`, `export-level-vectors.cjs`, …): one script,
**`ios/scripts/export-deck-vectors.cjs`**, compiles the web's own TypeScript with tsc into TMPDIR (as the sims do)
and writes `ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/deck/`; **`ui/test/iosdeck.sim.cjs`** runs it with
`--check` (made again, compared byte for byte - on the Node that made them; see the as-built), so a change to a web rule the Swift mirrors fails tests.yml until
the vectors are written again, and the Swift then fails until it is ported. Never edited by hand. Doubles are
written as their IEEE bits in hex beside a readable decimal, so nothing is lost to JSON's printing.

| file | from | what |
| --- | --- | --- |
| `platter.json` | lib/platter.ts | deck.sim's 54 flicks at targets 0.25, 0.5, 1, 1.5 and 2: each plan, its landing, `planAt` at 32 points along it, `phaseAt`; `releaseSpeed` and `handSpeed` over deck.sim's sample sets (rests and tails included); `acceleration` |
| `turntable.json` | lib/turntable.ts, lib/playSpeed.ts | the geometry and layout (every part's place at four plinth sizes, the handle's and fader's targets); `needleAt`, `armAngle`, `armTimeAt`; the drags (record and arm, through the slop, round the spindle, past either end); `shownTime`, `preview`, `previewWords`, `dragEnd`; `playingDisc`, `discArtPath`; `faderShare`, `speedAt`, `detent`, `clampSpeed`, `speedKey`, the fader's drag; `pointerSamples` over coalesced lists with repeats and reversals |
| `words.json` | lib/turntable.ts, lib/playSpeed.ts, lib/debugRows.ts, app/LookChoice.tsx, app/WindDownChoice.tsx, app/You.tsx | every word of 2.9 as the web makes it, with its inputs; `turntableRows` and `latencyNote` over 40 DeckReport cases; `speedRow`; the two notes as the web has them (their last sentence dropped by the Swift, which the test asserts) |
| `rules/*.json` | player/deck.ts, through deck.sim's harness | the real Deck driven by the bench's motions (lab/motions.ts's eight, at MOTION_HZ 60 and at 120 Hz, with seeded jitter at JITTER_TIME_MS 1.5 and JITTER_PLACE_S 0.001 - 1 ms at 120 Hz) the way `runMotion` drives it (lab/runner.ts:50), and through deck.sim's own cases (taps, holds, flicks back, cancels, wind-downs, play during a coast, the arm taken mid-coast, a song change mid-hold, a 415 and a 416, reduced motion): every input with its time, and every effect - each host call and its arguments, each `turnFace` angle at each frame, each message posted with its `stamp`ed time |
| `press/*.json` | player/Turntable.tsx, player/NowPlaying.tsx's turntable toggle | the real Turntable mounted through turntable.sim's own `mount` (:207) over the deck harness and a fake player, driven by pointer events (down, coalesced moves, up, cancel, click) and arm keys: taps, a tap after a turn, holds, flicks, a silent press (no window), a silent turn on a non-FLAC song, an arm drag, a cancel, the record's tap while coasting - every player call (seek, toggle) and deck call, in order, and the silent line as it changes. And `made_from`: the sha256 of each handler's source text (:288-290, :303-420) and of NowPlaying's turntable toggle, so a change to any of them fails the check even where the traces don't move |
| `voice/*.json`, `voice/*.f32` | lib/deckVoice.ts | the four functions over each `rules` case's messages, at block sizes 128, 333, 512 and 1024 (and 1, over the first 2,000 frames), at 48 and 44.1 kHz; plus coasts, wind-downs, handovers, a window swapped mid-block, and a loud master the limiter must hold. Each block's `now` as the web gave it. An FNV-1a 64-bit hash of the output's Float32 bits **per 4,096-frame span** (a block's hash at block size 1 would be 2,000 entries a case for nothing a span's doesn't catch); the reports whole for one configuration (48 kHz, blocks of 128) and as a hash of their doubles' bits otherwise. Three short cases (0.5 s each) also as the whole output, Float32 |
| `maths.json` | a `vm` context whose `Math` records | every `exp`, `log`, `sin`, `cos`, `atan2`, `hypot`, `pow` and `log10` the ported code evaluated in all of the runs above - the voice's, the rules', the platter's, the geometry's, the speed's: its inputs' and its answer's bits, in order |
| `jsmath.json` | Node itself | `Math.round`, `Math.min`, `Math.max`, `Math.fround` and ToInt32 over the edge cases of 4.2 (halves, 0.49999999999999994, 2^52 - 0.5, 2^53, -0, NaN, the infinities, large and negative indices) |

**The windows** aren't committed as PCM: they are made from an integer recipe both sides compute - an xorshift
noise, a triangle sweep in integer steps, a click train, and silence with one full-scale step (for the DC blocker
and the limiter) - in Int16, two different channels, 8 s each; the fixture stores the recipe, its seed, and a hash
of each window as a cross-check. The folder's budget is 3 MB, checked by iosdeck.sim (Phase 1's largest is about
2.2); a case that would take it over is hashed, not dropped.

**The harness**: deck.sim.cjs's fake host and clock (`fakeHost` :806, `advance` :626, `runFrames` :638, `posted`
:824) move into `ui/test/deckHarness.cjs`, which deck.sim and the exporter both require - so the traces are made
by the harness the web's own tests trust. Its clock is set so the Deck's `stamp` is the identity (the stub
context's time is the page's), and the exporter records each `stamp` pair anyway; DeckRules' test injects the
recorded stamps.

**The tests**:

- **Test A - the port, exactly** (Linux and macOS): DeckVoice with `RecordedMaths` answering from `maths.json`
  (an input not recorded, or asked out of order, fails the test), each block given the web's own `now`. Every
  span's hash, every report, and the three whole outputs must match **bit for bit**. This catches what -100 dB
  would hide: a constant wrong by an ulp, an operation in another order, a Float stored where the web keeps a
  double, a JS rounding ported as Swift's. It is the stronger test, and it can be had: the web's arithmetic is
  IEEE doubles and Float32 stores in a fixed order, and the only answers that differ between engines are the
  transcendentals', which it replays.
- **Test B - James's bar** (Linux and macOS): the same cases run twice in Swift - once with `PlatformMaths`, once
  with `RecordedMaths` - and the two outputs compared: within **-100 dBFS**, sample for sample (20 log10 of the
  largest difference, at -100 or under), reports within 1e-9 s. Because test A proves the `RecordedMaths` run is
  the web's output bit for bit, this is the platform's voice against the web's own, without committing the web's
  PCM for every case - the three whole outputs are compared with it directly as well.
- **DeckRules and TurntablePress**: each `rules` and `press` case replayed with `RecordedMaths`; every effect equal
  - names and arguments bit for bit, the order exactly - with `handoverLead` 0; then again with `PlatformMaths`,
  doubles within 1e-9 relative. `jsmath.json` holds the helpers of 4.2 to Node's answers, exactly.
- **Platter, geometry, speed, words**: exact with `RecordedMaths`, within 1e-12 with the platform's; the 54
  flicks' landings within 1 ms (the plan's own bar) and in fact within 1e-9 s; every word equal.
- **Palette**: the tokens of 2.14 read out of theme.css by the exporter (`tokens.json`), and a Linux test holding
  `TurntablePalette`'s Core-side values (the RGBA each Palette colour is made from) to them.

**As built (slice 1, 2026-11-12).** 61 files, 2986 KB of the 3 MB - since its review 75, 3061 KB (the press
traces, made.json). Where it isn't the table above, and why:

- **`rules/`, 42 cases.** The eight motions at 60 Hz, and five of them (steady1, back1, wobble, ramp, scratch) at
  120 Hz - half, quarter and double not at 120 Hz, for the budget - each with 500 ms of play before and 3000 ms
  after, seeded 900 + its index + its rate; and 29 scenarios on deck.sim's lines (taps, a pause then a play, play
  during a wind-down, wind-down off, hold and let go, a quick grab flicked back, a paused coast, a coast back past
  the window, a cancel, play during a coast, the arm mid-coast, a handover sought elsewhere and one judged closely, a
  song change mid-hold and mid-coast-back, not a FLAC, a 415, a 416 then its retry, reduced motion, a silent press
  then the audio waking, held still over a coast, hidden mid-coast-back, the speed changing, a pause from elsewhere,
  a mono short window, a tap while coasting, a slow short window, heard at half gain, a release at the tail, a
  silent coast sounding on the window's arrival). The 416 case runs under reduced motion (its coast took the budget).
- **The format**: the inputs as an op byte and little-endian doubles, base64; the world (song, playing, position,
  ready, made) an input only when it changed; frames on a 16 ms grid; the real deckVoice.ts rendering 128-frame
  blocks at 48 kHz while the context runs, its reports the `heard` inputs - carrying pos, rate and gain only, the
  fields the rules read. **Each effect is numbered by the input it came in**: added when a mutation (the refresh's
  speed) passed with every effect in order and one ask at another position report. A case's effects are kept whole
  at 400 or fewer, else as the count and an FNV-1a 64 per 512 (the budget); the PlatformMaths replay compares a
  hashed case by its count only. The stamp pairs are recorded only where the stamp isn't the identity - none yet.
- **`press/`, 13 traces** (built in slice 1's review): the real Turntable and NowPlaying, compiled from the web's
  TypeScript, mounted through turntable.sim's own stand-in Preact over the deck harness and a fake player (seek and
  toggle as the player's), the real Deck under them, driven by pointer events - down, coalesced moves, up (then
  lostpointercapture and the click, as a browser sends them), cancel - and arm keys: a tap to pause and to play (and
  Now Playing's toggle), a turn then a tap, a hold then the let-go, a rest then a nudge (the take by rest, `grabbed`),
  a turn back past the song's start, a flick while paused and a tap while it coasts, a press while coasting back, a
  silent press (the window held back), a silent turn on an MP3 (the silent line, gone at the song change), the arm
  (slop, drag, lift, five keys, a cancel), a cancel of a taken press, a second finger, a song change under a press.
  Each input is followed by every call the handlers made - deck and player, arguments and returns - and the deck's
  state after each (live, taken, the anchor; the replay's deck is a script that answers with them); the world (playing, length, the
  song, drawnAt, shown, now, flac, noAudio, live, taken, anchor) only when it changed; the drawn turn and the silent
  line whenever they changed, after inputs and between them. The deck's own work between inputs (its frames, its
  timers, the position's ticks) is the world's, not the trace's. `press/handlers.json` still hashes the handlers
  (:286-290, :301-422, :426, :237, NowPlaying :282), and the press files the whole of deck.ts, turntable.ts,
  deckClock.ts and scrub.ts they ran over. Turntable.js gets one patch, at its render, to tell the exporter what it
  drew.
- **`voice/` is eight cases of its own**, not every rules case's messages (the budget): hand turns, the wind-down, a
  handover with its fade, a window swapped mid-block with a mono window and a missing one, a loud hand at 120 Hz, a
  step, rests and out-of-order samples, a song that runs out - each at 48 and 44.1 kHz in blocks of 128, 333, 512,
  1024 and 1 (72 runs); three keep 48 kHz stretches whole, as raw Float32 (`.f32`, one of test_source_bytes.py's
  binary suffixes - base64 would pass the budget). 880 KB.
- `tokens.json` (2.14's) and `jsmath.json` as planned; `maths.json` is written last, over every run above.
- **One Node's answers** (the review): the exporter answers every Math call `maths.json` already holds with the
  committed answer, worked out by the running Node too and told when it differs - so a Node whose V8 answers
  otherwise remakes the table the Swift replays unchanged, and says why. (V8 moved its sin and cos to glibc-derived
  code behind a build flag in 2023; whether CI's Node 22 has it is unchecked - only Node 20.12 is on this Mac.) It
  can't hold the rest: about 32,000 calls made with the recording off - the bench's motions (lab/motions.ts's
  sines and noise), the harness's tone, the deck's frames between a press trace's inputs - are the running Node's,
  and feed the traces' inputs and worlds; storing them would take about 600 KB.
- **The check, on any machine** (after the merge: CI's x64 Node 22 failed it, and Node 22 on arm64 differed in
  other files). Any NaN is written as 0x7ff8000000000000 (x64 makes 0xfff8...; JavaScript can't tell), and the Swift
  tests write and look up theirs the same way (`RecordedMaths.bits`). `made.json` records the maker - Node,
  platform, arch - and the exporter's and harness's sha256. --check on the maker compares every file byte for byte;
  anywhere else a file whose `made_from` is unchanged may differ by that Node's Math alone and is listed, not failed,
  while a changed source, a new, missing or stray file, a change to the exporter or harness, or a difference in a
  file no Math answer reaches (jsmath.json, tokens.json, voice/windows.json, press/handlers.json) fails. jsmath.json
  and voice/windows.json gained a `made_from` (their functions' own text), maths.json every other file's. The
  whole account: notes/ios.md's slice 1, "A check that holds on any machine".

### 7.1 Slice 1 - Core: the physics and the voice

- **Files**: `DeadwaxCore/DeckMaths.swift` (the protocol, `PlatformMaths`, `RecordedMaths`, and the JS helpers of
  4.2), `Platter.swift`, `TurntableGeometry.swift` (and `TurntableLayout`), `PlaySpeed.swift`,
  `TurntableWords.swift` (2.9, and Debug's rows), `TurntablePalette.swift` (2.14's values), `DeckVoice.swift`,
  `DeckRules.swift` (with the `DeckHost` protocol, `soundReady`, `window`, `handoverLead` and `resumeAsked`),
  `TurntablePress.swift` (3.1); their tests in DeadwaxCoreTests (JSMathTests, PlatterTests,
  TurntableGeometryTests, PlaySpeedTests, TurntableWordsTests, DeckVoiceTests A and B, DeckRulesTests,
  TurntablePressTests, HandoverPlanTests - 3.5's arithmetic: `D`, the predictor, the target, the late case, the
  Reduce Motion take, over hand-built cases); Fixtures/deck/;
  `ios/scripts/export-deck-vectors.cjs`; `ui/test/iosdeck.sim.cjs`; `ui/test/deckHarness.cjs` split out of
  deck.sim.cjs; notes/ios.md (the exporter table, "How the ports are kept in step", :817-833) and notes/sims.md
  (iosdeck's line).
- **Must not touch**: any of ui/src (the web's behaviour), deck.sim.cjs beyond moving its harness (it passes
  identically before and after, its output byte for byte), ios/App, DeadwaxAudio, the server.
- **Verified**: `ios/scripts/check-linux.sh` (Core built and tested with swift.org's Linux toolchain), ios.yml's
  ubuntu and macOS jobs, tests.yml's sims (iosdeck included, and deck.sim unchanged). No Simulator.

**As built (slice 1, 2026-11-12)**: every file above, with the departures written into 3.1, 3.3, 3.5, 4.2 and
7.0, and notes/ios.md's "The turntable". Verified on this Mac only (swift test, the Xcode device build, every sim,
iosdeck's --check); check-linux.sh and ios.yml were not run - Linux by reading.

### 7.2 Slice 2 - DeckEngine and the local window

- **Files**: `DeadwaxAudio/DeckEngine.swift` (the second engine, its source node, start and stop),
  `DeckVoiceHost.swift` (the render block and its rings), `DeckWindows.swift` (4.4, 4.5); `Sources/CDeckRing/`
  (the C11 ring, a C target in Package.swift - built on Linux too); Core: `Routes.swift`'s `scrub`, the client's
  scrub call and the `X-Deadwax-Window` reader (Linux-tested), and tests/test_ios_contract.py's ROUTE_COUNT 24
  in the same commit; DeadwaxAudioTests: DeckEngineRenderTests, DeckRealTimeTests, DeckWindowTests,
  HandoverTimingTests; FLAC fixtures from `ios/scripts/make-test-album.py` (a 22.05, a 44.1, a 48 and a 96 kHz
  file, and the three tones of 4.4 (b)); ios.yml's release-build step for DeckRealTimeTests.
- **And one thing James can hear before slice 3 is built on it**: Debug's Test sounds gains a row, "The record's
  engine beside the song" (**new**) - while a test sound plays on the song's engine, a second button starts the
  deck engine playing a fixed run of the voice (a hand's recorded trace from `rules/`, through the real render),
  stops it, and starts it again, with the clock row of 6.2 shown live. It answers checks 0a-0c (8): do two engines
  play together on his phone, does the deck's start or stop make any sound in the song, and does `L` hold steady.
  The one change slice 2 makes in ios/App.
- **The tests** (ios.yml's macOS job, offline manual rendering):
  - the source node's output bit-exact to Core's voice for the same messages (the mixer at unity adds nothing),
    over test A's cases;
  - zero allocations on the rendering thread, with the canary seen (4.3) - in a release build, its own step:
    `swift test -c release --filter DeckRealTimeTests`;
  - the window maker on the grid (4.4 (a)) at 44.1 to 48, 22.05 to 48, 96 to 48 and 48 to 48 (the last a copy
    times the gain); the gain the lane's Float exactly; the pre-roll long enough (`P` against `2P`); a
    `/scrub`-made window equal to a local one, through a fake server answering a fixture's flac_window.py output
    (made by the exporter with the server's own code, so the phone's reader is held to the real format);
  - the seam off the grid (4.4 (b)), the three tones after a seek to 42.0123 s;
  - the window made in pieces: peak memory while making a 40 s window of the 96 kHz fixture under the window's own
    size plus 2 MB (`task_info`'s resident size, before and after);
  - HandoverTimingTests: the song's engine and the deck engine both in offline manual rendering, rendered in
    lockstep on one shared sample clock, the song's engine paused and resumed at `r` as 3.5 says, with `E` taken
    from the offline engine's own accounting of its start (frames rendered before its first non-silent one) - the
    song's first sample lands where the voice sounds the target, within one render quantum. It tests the
    arithmetic and the order of the calls, not the device's `E`, which only the phone has (8).
- **Must not touch**: PlaybackEngine.swift, PCMSource.swift, GainedSource.swift, StreamSource.swift (used, not
  changed); AudioSessionController's category; ios/App but for that one Debug row; ui/.
- **Verified**: ios.yml (its macOS job runs these; its device build compiles them); check-linux.sh for the Core
  parts and the C target. The engine's existing tests pass unchanged. No Simulator.

#### Slice 2, built (2026-11-13)

**What was built.**

- **Core**:
  - `DeckScrub.swift`: the window's plan (4.4), and `/scrub`'s ask, query, `X-Deadwax-Window` reader and statuses
    (4.5).
  - `DeckLead.swift`: `L` (3.2). A monotonic deque of 2048 leads over 1.5 s. It moves freely while the voice is
    quiet and slews at 0.0005 s/s under a sound.
  - `DeckRender.swift`: the render's own entries, specialised over PlatformMaths in Core. `DeckSlot` is the
    message as plain numbers and pointers.
  - `DeckPCM`, in DeckRules.swift: a window's own memory, which the voice reads in place.
  - `Routes.scrub` and `DeadwaxClient.scrub`.
  - Debug's rows in TurntableWords.swift: Clock, Messages dropped, Window made in, and the trial's row.
- **CAudioRing** gains `audio_fifo`, an SPSC ring of slot indices. The payload lives in Swift's own POD slot
  arrays, and the C side only moves indices, with acquire and release.
- **DeadwaxAudio**:
  - `DeckVoiceHost.swift`: the render block - the clock, the messages, the voice, the report, then the deck's EQ.
  - `DeckEngine.swift`: the second engine.
  - `DeckWindows.swift`: windows from a file and from `/scrub`.
  - `DeckTrial.swift`: Debug's run.
- **ios/App**: one change only - DebugView's row "The record's engine beside the song", with `DeckTrialModel`
  beside it in the same file.
- **Scripts and checks**:
  - `ios/scripts/make-test-album.py --deck-fixtures` and `ios/scripts/export-scrub-window.py`.
  - tests/test_ios_install.py makes both again and checks them byte for byte.
  - ios.yml has a release step for DeckRealTimeTests.
  - ROUTE_COUNT is 27.

**Measured on this Mac (debug build, except where it says release).**

| What | Result |
| --- | --- |
| The source node against Core's voice | Bit for bit, over test A's 32 runs of 8 cases. The deck's EQ is EQRender after the voice, bit for bit. |
| Windows on the grid (22.05, 44.1, 48 and 96 kHz to 48 kHz) | Bit-exact against the lane's frames from 0. The 48 kHz one is the file times the gain, exactly. |
| `P` against `2P` | Bit for bit at all three converting rates, so `P` stays 0.2 s. |
| A `/scrub` window against the local one | Bit for bit. The answer was cut by src/flac_ranges.py and placed by its header. |
| The seam off the grid | The lane at -91.0 dB and the voice at -78.4 dB against the exact tones (bound -50). |
| A 40 s window from 96 kHz | The making thread held at most 15.80-16.12 MB over six runs, against a 14.65 MB window: about 0.5 MB under the bound. Made in 930-1060 ms (debug). |
| HandoverTimingTests | E was 300.0 ms in all three starts, D 142.8 ms. The song's first sample landed 0.53 ms from planEnd + D, and its 2.1 s click came out of both engines 28 frames apart (quantum 32). |
| Allocations, release | 0 allocations and 0 frees in 10,000 direct calls (every message kind, three window swaps, the report ring folding, the EQ crossfading in) and in 1,000 blocks of AVAudioEngine's own real-time manual render. The canary was seen first. |

- **The first release run's allocations.** It counted 6 allocations, all in the first call. They were the
  test's own first read of the host clock (AVAudioTime's first use): with that read moved before the count and
  the warm-up kept as it is, the count is 0. The warm-up now also renders each message kind on the host clock,
  because before this it never ran the live clock's path.
- **The direct test's `L`** reads 95.3 ms. That is its 10 ms host-time lead plus a 4096-frame block, because
  3.2's lead counts the block's own length.

**Departures, and why.**

- **No `CDeckRing`.** CAudioRing is already the C11-atomics target, built on Linux and used by the EQ's triple
  buffer. A second target would only have repeated its atomics, so the deck's three rings are `audio_fifo`s in it.
- **Reports: a full ring folds, it doesn't overwrite.** With one producer and one consumer, the producer can't
  safely take the oldest slot back from under the reader. A report that finds the ring full is folded into the
  next: the newest position, rate and gain are kept, with the counts summed and the lowest gain kept. Status
  counts the folds as `reportsFolded`.
- **"Sounding" for `L`'s slew is the voice's gain**: `gainTarget > 0 || gain > 1e-5`. The render can't see a
  hand or a plan, only what the voice is doing.
- **The offline clock** is `now = (sampleTime + offlineFrames) / rate - offlineLead`, written so that it is
  bit-exact with Core's `(from + done) / rate`. HandoverTimingTests sets the lead to `L`.
- **The memory bound is CAllocHook's byte count on the making thread, not `task_info`.** The suite shares its
  process with every other suite running at the same time, so the resident size is printed and not bounded.
  CAllocHook gained a per-thread byte count, with a 1 MB canary.
- **The seam's seek is to 2.0123 s, not 42.0123 s.** This keeps the fixtures small: 922 KB in all, since each
  is constant until just before the stretch a test reads.
- **HandoverTimingTests renders in quanta of 32 frames**, with the song's `startLead` at 0.3 s so that E > D. At
  a device's 512, a mistake of the limiter's 72 frames would hide inside the quantum.
- **Debug's run is made in code (`DeckTrial`), not replayed from `rules/`.** Bundling a test fixture would need
  resources added to the project or the package. The run is a 6 s chord taken from 1 s, then grabbed at speed at
  1.5 s and scratched twice. It is let go at 2.5 s at speed 1 and loops every 4 s, with hand samples at 120 Hz
  stamped with the host's now. It plays without the deck's EQ: slice 3 wires the output's curve into
  `DeckEngine.eqStart`, and the trial leaves EQModel's desk alone.
- **`DeckEngine.ioBuffer` and `latency` are hooks the app sets.** The trial sets them from
  AudioSessionController.
- **`stop()` keeps the voice and its window.** `reset()` works only while the engine is stopped. A new output
  rate remakes the source node and the voice.

**Mutations, each one alone, against the slice's tests**: six, all caught. The table is in notes/ios.md's
"Slice 2". It covers D's two terms, the offline clock's lead, the pre-roll's drop, the grid's start and the level.

**What only the phone shows** (checks 0a-0c, then 9):
- Whether two engines play together.
- Whether the deck's start or stop is ever heard in the song.
- `L` on the speaker and on earbuds.
- The phone's "Window made in" for a 40 s window of a 44.1 kHz song (4.4's 150 ms).
- The real `E`.

**Questions** (my recommendation first):
1. Should Debug's run play through the deck's EQ, as slice 3's deck will? **Leave it off until slice 3**: the
   checks are about two engines together, and the desk is the song's.
2. Should `reportsFolded` show in Debug beside Messages dropped? **Only if it is ever above 0 on the phone.**
   Folding means the main thread didn't read for 2 s, which the Clock row would show first.
3. The memory bound is the spec's, with about 0.5 MB to spare here. If it fails on ios.yml's runner, should the
   bound get more room, or the pieces get smaller (0.5 s)? **Smaller pieces first**: the margin is what 4.4 step 5
   promises.

**Review (2026-11-13).** Read against 4.1-4.7, eq.md 1.9 and deck.ts, and mutated. Four things were wrong and are
fixed, each with a test that fails without it:
- **The deck's EQ started from its last run.** `start()` made the EQ's render state only when there was none or the
  rate was new. So a stop and a start at the same rate kept the filters' old state and counts, and crossfaded from
  the old bank. eq.md 1.9 asks for the same install as the song's at the first block after the engine's own start,
  and an Off set while stopped wasn't bit-exact for the crossfade's 20 ms. The state is now made again at every
  start, as the song's EQUnit makes its own at every allocation (`theDecksEQStartsAfreshAtEveryStart`: the first
  block after a restart is a fresh EQRender's, bit for bit, and Off after a restart is the plain deck's).
- **`X-Deadwax-Window` could trap.** `first + samples` overflowed an Int64, and a large count or rate made a Double
  too big for the Int the plan converts it to. The reader now refuses what a FLAC can't say: samples under 2^36 and
  the rate under 2^20, STREAMINFO's widths. `end` saturates. `plan` holds every product under 2^40 before
  converting, so a number from outside gives a plan or nil
  (`aHeaderPastWhatAFLACCanSayIsRefusedAndNothingTraps`).
- **Reports nobody read piled up.** `collect()` appended to `heard` without bound, so a caller that seldom reads
  `reports()`, like Debug's trial, grew it by about 1.7 KB/s, 6 MB an hour. It now keeps the newest 64, the ring's
  depth (`unreadReportsDontPileUp`).
- **The memory and allocation counts could pass low.** CAllocHook watches one thread for the whole process, and
  Swift Testing runs suites in parallel. So EQRealTimeTests' count and DeckWindowTests' could overlap, and either
  could count the other's thread instead of its own. The 40 s window's bytes, 16.12 MB every time it ran alone, read
  as low as 15.80 in the full suite: the table's range above is probably that. Both now hold one lock round the
  hook.

New tests for what had none:
- full rings drop, keep and count (`fullRingsDropKeepAndCount`);
- the window given back is the old one, and only once the voice has let go (`aWindowIsGivenBackOnlyOnceTheVoiceLetsGoOfIt`,
  reading `live`, now `private(set)`);
- the render's `L` slews under a sound and moves freely in quiet (`theRendersClockSlewsUnderASound`).

Six mutations, each alone, are caught by these tests: the EQ state reused, reports unbounded, the new window given
back, never sounding, a drop not counted, and the header's bounds gone. One mutation is caught by nothing: a fold
that doesn't sum `held` and `peaks`. That count only feeds Debug's words, so it is left untested.

Judged and left as built:
- **The render is real-time safe.** Release counts 0 allocations in both tests. It takes no locks and makes no
  runtime calls. DeckLead and DeckVoice read static lets, which is fine in release once the warm-up has run.
- **DeckWindows' `@unchecked Sendable` holds.** `ticket` is behind its lock and the rest is `let`. `answer` is
  called only on the answers queue. DeckPCM is mutable behind its own `@unchecked`, which is safe only because a
  window is filled before it is posted. A write after posting would be a race that no type catches.
- **The second EQHost is eq.md 1.9's**: its own triple buffer and state, after the limiter. Off is bit-exact from
  the first block of a start.
- **The handover's arithmetic is 3.5's** (`r = planEnd + D - E`). The quantum of 32 proves it to 0.67 ms. On the
  phone the resume isn't quantized to blocks, so the bound there is tighter than the spec's.
- **ios.yml runs the release step** beside the EQ's. The must-not-touch files have no diff. ROUTE_COUNT is 27, and
  the `/scrub` client asks only `at` and `seconds`.
- **Swift 6.3.3 with the 26.5 SDK** (CI's Xcode 26.6) compiles Core and Audio. The test targets weren't checked
  under it: the Command Line Tools' Testing macros don't match their own framework. The review's closures state
  their types, except `#expect(throws:)`'s, a form CI already compiles in eight places.
- **The memory bound measures the right thing, with a 0.53 MB margin.** The overhead above the window is a constant
  1.47 MB at every length, and about 1.0-1.16 MB of that is AVAudioFile's own FLAC open. CI's load won't move it,
  but another OS's decoder could. Smaller pieces buy little: the pieces' own transient is about 0.4 MB, so 0.5 s
  pieces would save about 0.2 MB. That answers question 3 the other way. If the bound fails on CI, subtract the
  decoder's open cost, measured as a one-frame window's, rather than shrink the pieces or loosen the bound.

Questions for slice 3, and for James:
- **The live clock's fallback.** It falls back to sample time if the host time is ever invalid, but that is a
  different time base, so `L` would jump. Should it hold the last host time instead?
- **`L` on a route change.** 4.6 restarts `L` at every route change. DeckEngine restarts it only on a new rate,
  and has no call for a route change at the same rate.
- **A rate change drops messages.** Its `resetStopped()` drops what was posted while stopped, which `stop()`'s doc
  says is applied at the next start.
- **Messages posted while stopped.** They are applied at the next start with their old times, and enough of them
  fill the ring.
- **The EQ's banks.** When the deck's EQ is wired, EQModel must make each host's bank at that host's own rate.
- **Smaller gaps.** DeckTrial doesn't activate the session. The deck's EQ counters don't record its render's
  ticks. A `/scrub` fetch isn't cancelled by a newer ask.

### 7.3 Slice 3 - the look, the touch views, the deck's rules, settings, Debug, docs

- **Files**: `ios/App/Player/Turntable/` - `TurntableView.swift` (SwiftUI: the plinth's place, the time line, the
  silent line), `TurntableDeckView.swift` (UIKit: the layers, the display link, the three touch views, the
  accessibility elements), `DeckController.swift` (@MainActor, @Observable, made once by the app beside PlayerModel
  and put in the environment - it outlives Now Playing's cover, 2.1: DeckRules, TurntablePress, DeckEngine, the
  windows, the `deck.position` queue, its own session notifications, and PlayerModel as its host);
  `PlayerModel.swift`'s one read-only addition (`engineForDeck`, 3.4); `NowPlayingView.swift` (the look button, the
  titles' alignment, the grip, the scrubber row, the error line over the plinth); `DeadwaxApp.swift`'s Palette (2.14); `PlaybackSection.swift` (6.1); `DebugView.swift` (6.2, 6.3);
  Core's `discArt` route (ROUTE_COUNT 25 with its test); Info.plist's `CADisableMinimumFrameDurationOnPhone` and
  check_project.py requiring it; docs/ios.md - Playing (the turntable, after Now Playing), You (the two settings),
  Debug (the section), "What it can't do yet" (the fader, until slice 4; the visualizer, which stays on the web);
  notes/ios.md's write-up.
- **Must not touch**: the engine; the cover look's layout and behaviour (the same pixels and the same gestures
  when the cover shows); ui/.
- **Also**: `DeadwaxKit/Sources/DeadwaxTurntable/TurntableLayers.swift` (2.4: the layer tree, QuartzCore and
  CoreGraphics only) with `DeadwaxTurntableTests` on the macOS job: each state of 2.8 that changes the drawing (at
  rest; turned 90°; the arm lifted; CD art; no art, the cover as the label; the readout at 1x and at 1.25x; the
  fader held) rendered with `CALayer.render(in:)` at the iPhone 16's and the SE's plinth sizes, at 3x, written as
  PNGs to the job's artifacts; and pixel assertions that don't need an eye - the sheen's brightest band at 48°
  from the top (2.4), the label's ring where the web's is, the grooves' period 4 pt, the readout's colours the
  Palette's, the head 5 units up when lifted. `ui/test/` gains nothing: the web's screenshots of the same states
  are taken by hand once (notes/screenshots.md's way) and put beside the artifacts for the review.
- **Verified**: Core's rules for the screen (layout, words, rows, the disc, the states of 2.8 as a pure function
  of the deck's report and the song) on Linux; the drawing on the macOS job, rendered and asserted (above);
  ios.yml's unsigned device build compiles the app; and the screen in the hand on James's iPhone (8). Nothing in
  the slice needs a Simulator: what the macOS render can't show - touch, VoiceOver, Dynamic Type in SwiftUI, the
  120 Hz frame, the sound - is the phone's list.

#### Slice 3, built (2026-11-13)

**What was built.**

- **Core**:
  - `TurntableScreen.swift`: `TurntableFace`, the web's numbers in points (app.css, theme.css, icons.tsx), which
    tests/test_ios_turntable_face.py holds to the stylesheets and the icons. `TurntableFit`, the plinth as big as the
    cover's room allows both ways, at most 440 pt. `TurntableFaceParts`. 2.8's states as pure functions:
    `soundReady`, `noAudio`, `silentLine`, `framesRun` and `engineWant` (question 13's C, with its 0.5 s quiet
    hold). `TurntableSettings`: the two settings under the web's keys, and the look and lyrics taps. Debug's
    Turntable section: the web's rows in the web's order, with the phone's own beside them (Window from, Handover,
    Position read in, Touches under a hand, Slow starts), and `phoneReport`, the deck's report as the phone has it.
  - `TurntableLayout` places the label and the spindle on the record's centre, as the web's are, and
    `TurntableFaceParts` draws each ring inside its share of the face (the review's fix: the web's boxes are
    border-box).
  - `TurntablePress`: `handTurn`, the drawn turn round the deck's angle (Turntable.tsx:426), and
    `cancelFollowed()`, for an interruption, headphones out and Now Playing closing.
  - `DeckRules`: `interrupted()`, Debug's reads of the report (`reportWindow`, `fetchedBytes`, `lastFetchedAt`,
    `health(_:)`), `windowDropped()`, for the engine's route change, and (the review's) `outputGone()`.
  - The review's: `DeckStartFailure`, `TurntableScreen.windowRate`, `HandoverStarts` and
    `HandoverTiming.actualStart` (below, "Review fixes").
  - `Routes.discArt` and `DeadwaxClient.discArt` (nil for deadwax's 404). ROUTE_COUNT is 28.
- **DeadwaxAudio**: slice 2's six review questions, answered in DeckEngine, DeckVoiceHost, DeckWindows and
  EQStartDesk (below).
- **DeadwaxTurntable**, a new module (QuartzCore and CoreGraphics only, Swift 5 mode for CALayer's statics):
  `TurntableLayers`, 2.4's layer tree - the plinth with its top highlight, the platter, the face (the vinyl, the
  cover as the label with its ring, CD art over the whole face, the grooves as a per-pixel image of the web's
  gradient, the spindle), the conic sheen, the arm in a container turned round its pivot, the dashed handle, and
  slice 4's fader and readout, drawn and hidden. DeadwaxTurntableTests renders every state 7.3 names at the iPhone
  16's plinth (321 pt) and the SE's (284 pt) at 3x to `$TURNTABLE_RENDERS`, which ios.yml sets and uploads.
- **ios/App/Player/Turntable/**:
  - `DeckController.swift`: the deck, one per app run, in the environment. `DeckWorld` adapts Core's DeckHost,
    DeckClock and PressHost to the main actor. The clock is `CACurrentMediaTime()` in ms; timers are strict
    DispatchSourceTimers on the main queue; the frame is a CADisplayLink at 80-120 Hz, run as `framesRun` says.
    Windows come from the download, else the player's whole copy (`SongFiles.wholeCopy`), else `/scrub` while
    online, else none. The engine runs as `engineWant` says, checked by a 10 Hz rule that stops itself when there is
    nothing to watch. The song's position is read by `DeckPositionFeed`, a 120 Hz utility queue under an unfair lock,
    a reading older than 50 ms counting as none. The handover's `E` is predicted per kind (local or streamed) and
    per route from the last five starts. It follows interruptions, route changes, media resets, the scene, Reduce
    Motion and Increase Contrast, and loads the cover (CoverCache) and the disc's CD art.
  - `TurntableDeckView.swift`: the layers in a UIView; the record's and the arm's round touch views, which pass
    every coalesced sample in ms; and the two VoiceOver elements, the record a button and the arm adjustable.
  - `TurntableView.swift`: the plinth fitted to the cover's room, the time line, the foot line, and the look
    button with its own face (`LookFace`, 36 pt in a 44 pt target, the web's glyphs as Shapes).
- **The rest of ios/App**: NowPlayingView (2.1: the look button, the crossfade, the centred titles, the time line in
  the scrubber's row, the foot line, the grip, Play/Pause the deck's on the turntable); You > Playback's two settings
  (6.1); Debug's Turntable section (6.2), read 4x a second; DeadwaxApp's Palette additions (2.14);
  `PlayerModel.engineForDeck`, read-only (3.4); `AudioSessionController.activateShared()` and `onAirPlay()`;
  `NowPlayingController.republishPaused(elapsed:)` (4.6, question 16 A); `EQModel.attachDeck` (eq.md 1.9).
- **The project**: DeadwaxTurntable linked into the app, Info.plist's `CADisableMinimumFrameDurationOnPhone`, and
  check_project.py requiring both. App 0.6 (6).

**Slice 2's questions, answered** (80f1149, each with a test that fails without it):

1. **The live clock's fallback**: a render block with no host time follows the last one (its host time plus a
   block) at the `L` the clock has, and `L` isn't fed the guess. The sample clock is never mixed in.
2. **`L` on a route change**: `DeckEngine.routeChanged()` stops the engine and starts `L` again from its floor
   whatever the rate. A new hardware rate also remakes the voice and drops the window, said through
   `windowDropped`, which the app wires to `DeckRules.windowDropped()` to ask for it again.
3. and 4. **Messages across a stop**: a stop leaves the voice quiet with nothing timed waiting. What wasn't rendered
   is drained: the newest window is kept aside, and every timed message is dropped and counted as `stale`. A post
   while stopped does the same as it comes, so the ring can't fill while stopped and no old knot plays at the next
   start. 4.6 only stops the engine with the record quiet, so nothing heard changes.
5. **The EQ's banks**: `EQStartDesk.changed(hosts:)` makes one version and each host's bank at its own rate.
   `start(record:)` lets the deck's start install without becoming the song's "last start" in Debug.
6. **The smaller gaps**: the deck's EQ times its own process into the EQ counters; DeckWindows cancels the previous
   `/scrub` task when a newer window is asked for; and the session is made active before the deck engine starts,
   in the app and in Debug's trial - since the review by DeckEngine's own `activate`, first in every start and
   tested (below).

**Measured on this Mac.**

| What | Result |
| --- | --- |
| The plinth (TurntableFit) | 321 pt in a 393 pt phone's room (345 wide, tall enough); 440 at most; 284 pt in the SE's room, held by its height |
| The renders, asserted | The sheen brightest at 48 deg from the top, within 2 deg; the label's ring where the web's is; the grooves' period 4 pt; the readout's colours the Palette's; the head 5 units up when lifted; the face turning with the CD art over the label; the handle brighter under Increase Contrast |
| swift test | Core 953, DeadwaxAudio 139, DeadwaxTurntable 9: all passed |
| The unsigned Release device build | Builds, with no warnings in the app's sources |
| pytest tests/test_ios_*.py tests/test_source_bytes.py | 146 passed, 1 skipped |

Nothing about the app's timing was measured: every number that matters (the touch rate, `E`, the handover's lateness,
the frame rate, the delay behind the hand) comes from a phone, and Debug's section is there to show it.

**What the renders show** (20 PNGs, 10 states at both sizes, looked at): the plinth with the record and its platter
ring; the test cover upright as the label, grooves running across it as the web's do; the sheen brightest at the top
right and the lower left; the arm from its top-right pivot with the counterweight reaching past the plinth's top
edge, into the 24 pt kept clear for it; the head over the dashed handle's circle, larger when lifted; CD art over the
whole face, turned 90 deg with it; with no cover, the plain label colour with its ring; the fader's slot, knob and
mark and the purple `1.25x` readout at the corner (slice 4's, hidden in the app).

**Departures, and why.**

- **The readout's inset shadow isn't drawn, and its face is Menlo.** Both are slice 4's to judge, when the readout
  shows.
- **The pbxproj was edited by hand** to link DeadwaxTurntable: one build file and one product dependency, the
  same shape as DeadwaxAudio's. No Xcode was opened.
- **Two touch views, not three.** The fader's is slice 4's.
- **Under Reduce Motion the display link runs for a held record** (`framesRun`'s `held`). The web's loop asks for a
  frame for a held record whatever the motion setting (deck.ts:2074), to show the time line under the hand and
  count its frames. The platter still never turns by itself.
- **Recording (6.3) and the replay of a recording on the Mac aren't built** (question 7 had A, in slice 3). The
  slice was already the largest, and the recorder needs a tap on the deck engine's output, which is DeadwaxAudio's,
  not the app's. Check 23's A/B is by ear alone until it comes (question 23 below).
- **No custom actions** on the record (question 9's A comes after the web's own answer): the web's roles alone.
- **The Handover row's seam isn't measured** (nil). The song's first heard sample, against the record's sound,
  needs both engines' render times compared, which neither reports to the app. The row says how early the song was
  resumed, for what start, how long the start took and how late the timer fired.
- **The song engine's configuration change** (a hardware reset that AVAudioEngine notifies) is caught by the 10 Hz
  run rule, which sees the engine stopped, rather than by the notification: PlaybackEngine's AVAudioEngine isn't
  the app's to observe, and the engine is not to be touched.
- **The handover's actual `E` is the start seen after the let-go** (the review's fix: the slice read the previous
  start with a sync on the engine's queue at the let-go, on the main thread mid-gesture, which 2.6 forbids). The
  main thread counts the engine's starts from its phase; the `deck.position` queue reads the start at its run's end,
  and it counts only when that read began after the start was seen (`HandoverTiming.actualStart`). An `E` not read
  within twice the run's length is dropped.
- **Headphones out, the record rests** (question 27, the review's design call): the player pauses the song, as Apple
  asks, and `DeckRules.outputGone()` makes sure the deck resumes nothing on the speaker. The web's page plays on in
  whatever outputs next.
- **Debug's report stands while the deck lives**, as the web's does (deck.ts publishes null only at destroy): after
  Now Playing closes on the turntable, Debug still shows what it last did. On the phone Debug is under You, so the
  rows can only be read with Now Playing closed. Sound health is reset each time the turntable shows.
- **"Window made in"'s song rate is the track's sample rate** as Navidrome gives it.
- **Disc art is kept in memory, the last eight discs** (question 11's B). A disc with none is asked again at the
  next opening, as the web's is.
- **The look button is named for the look, not for what shows** (NowPlaying.tsx:382). Over the lyrics, the
  turntable's square still says a tap shows the cover, which it then does.
- **Linux wasn't run**: no swift.org toolchain on this Mac. Core's new code is Foundation-only, and ios.yml's
  ubuntu job is its first Linux build.

**Mutations, each one alone, against Core's tests**: six, all caught (scratchpad's mutate.py: applied to TurntableScreen.swift, DeadwaxCoreTests run,
restored).

| Mutation | Caught by |
| --- | --- |
| The silent line shown over the player's failure | theSilentLineIsAirPlaysFirstThenNoSoundThenNotAFLAC |
| No frames for a held record under Reduce Motion | framesRunOnlyWhenAskedShowingActiveAndMotionAllowed |
| A lock-screen pause, the record quiet, not resting the engine at once | theDeckEngineRunsAsQuestion13Says (2 issues) |
| Sound counted ready during an interruption | soundIsReadyOnlyPreparedAndAllowed |
| The plinth without its 24 pt clear | thePlinthFitsTheRoomBothWaysAtMost440 |
| The engine running with the scene in the background | theDeckEngineRunsAsQuestion13Says |

**What only the phone shows**: section 8's checks 1-24 (in docs/ios.md as "The turntable's checks (app 0.6)", 23 by
ear only) and section 9: the touch rate, the 120 Hz frame, the real `E` and the handover by ear, the window's making
on the phone, the lock screen after a wind-down with two engines, Bluetooth's delay, VoiceOver, Dynamic Type in
SwiftUI, and heat and battery over an album.

**Questions**, numbered on from section 10's (my recommendation first):

23. **Recording**: build Debug's Record 20 s and the Mac's replay as the first part of slice 4, before the fader, or
    leave the A/B by ear? **Build it first in slice 4**: the A/B against Safari is the question James is asking, and a
    recording is what makes it a test rather than an impression.
24. **The Handover row's seam**: give DeckEngine and PlaybackEngine a render-time stamp the app can read, or leave the
    seam to the ear? **To the ear first** (check 8): measuring it means touching the engine, and the timing the app
    does see (the start's `E` and the timer's lateness) may be enough to say whether question 2's B is needed.
25. (Dropped in the review: the web's label and spindle were never off centre - player.css makes every box
    border-box. See "Review fixes" below.)
26. **The kept disc art**: eight in memory, or on disk with the download (question 11's A)? **Eight in memory** until
    an offline album with CD art is seen showing the plain record.
27. **Headphones out mid-turn**: should the record rest with the song, or play on in the speaker as the web does? **Rest**
    (built): the player already pauses the song when an output goes, as Apple asks of a music app, and a deck that
    then resumed it - at a held press's let-go, a handover's end or its led timer - would start the song on the
    speaker in someone's pocket. The cost is one more difference from the web, which has no such notice.

#### Review fixes (2026-11-13)

The review of slice 3 found five bugs and nine smaller things. Each fix is its own commit on the branch, and each
new rule has a test that a mutation was shown to fail.

**The five bugs.**

1. **The time line asked for height** (c0b1bfd). Its `.frame(maxWidth: .infinity, maxHeight: .infinity)` made the
   scrubber's row as flexible as the cover's room above it. In a Mac probe of the same column the room fell from
   445 pt to 255.5 and the row grew from 66 to 255.5, so the plinth shrank and the titles moved at every swap. The
   frame is wide only now. The view can't be laid out from the package (UIKit, DeckController), so
   tests/test_ios_turntable_face.py holds the source to it: the row's ZStack and the time line ask for no
   `maxHeight`. Putting it back fails the test.
2. **An interruption with no "ended" silenced the record for good** (b66fa73). `interrupted` is now also cleared
   when the song plays again and when the app comes back to the front. A "began" whose reason is
   `appWasSuspended` (compared by its number, 1, deprecated since iOS 16) is ignored, and Debug's report says
   "interrupted" while it stands.
3. **A failed start silenced the record for good** (0a9b5ca). `DeckStartFailure` (Core) is forgotten at once by a
   route change, by the deck being made again and by an interruption's end. A press 2 s or more after the failure
   forgets it too, and the start is tried again. Nothing retries on a frame or a post, so a phone that can't make
   the sound tries once a press at most.
4. **The label's and the spindle's rings were outside their boxes** (062e7ce). player.css makes every box
   border-box (`*, *::before, *::after`, linked before app.css), so the web's rings are inside the 38.75 % and
   the 5.4 %. `TurntableFaceParts` now puts them inside: a 60 pt label in a 62 pt ring and a 7 pt spindle in a
   10 pt one at a 372 pt plinth's face. TurntableRenderTests reads both rings' pixels, and question 25's
   "departure" is dropped. One true difference is left: the plinth's own hairline is drawn outside its box, to keep
   the stage's exact shape, so it is 1 pt wider each side than the web's in the same room (TurntableLayers says so).
5. **The let-go waited on the song's engine** (658652a). `handoverLead` read
   `engineForDeck?.debug().lastStartSeconds`, a `queue.sync` on PlaybackEngine's queue, on the main thread during
   the gesture. **The choice: a count of starts**, not a read on the `deck.position` queue. `resumeSong` asks
   `player.resume()` before it starts the feed, so a read at the run's start would wait behind the resume and take
   the new start as the baseline. The main thread already watches `engineState` (through `isPlaying`), so
   `HandoverStarts` counts each change to `.playing` and when it was seen, with no sync. The feed's end-of-run read
   records when it began, and `HandoverTiming.actualStart` takes it only when a start was seen after the let-go and
   the read began no earlier. That holds because PlaybackEngine writes `lastStartSeconds` in `playFromSilence`
   before `publish(.playing)`, and `playAsked` is cleared only by that write (read from its source). Nothing was
   needed from the engine: PlaybackEngine, PCMSource, GainedSource, StreamSource and the EQ's render have no diff.
   tests/test_ios_turntable_deck.py holds that only DeckPositionFeed asks the engine for `position()` or `debug()`.

**The smaller ones.**

- **`active` in startEngine** (55e7b43): a tick's `.drive` as the app left could start the output in the
  background. Untested app code.
- **settleStopped restored an older window** (4e22a92). After the system stopped the output, a window posted
  meanwhile was kept aside. The next start's settle then put the ring's older window back over it and freed the
  newer one. A kept window is always newer than the ring's, so the ring's are now let go when one is kept.
  DeckReviewTests' `theWindowKeptAsideIsNewerThanTheRings` covers it.
- **The first window's rate** (5c46db0): before its first start the deck engine's rate is its 48 kHz guess, never
  0, so the session's rate was never used. On a 44.1 kHz route the first window was made at 48 kHz, dropped at the
  start and made again. `TurntableScreen.windowRate` takes the engine's rate only once it has started.
- **Slice 2's question 2, the rate-change half** (fc87819). DeckEngine reads the output's rate through
  `outputRateNow()`, with an internal `rateForTests` seam. `aNewRateDropsTheWindowAndSaysSo` covers a route at
  44.1 kHz (routeChanged() true, windowDropped once, the voice empty, the node made again with no second word) and
  a start that finds the rate moved by itself.
- **Question 6's "session active before the deck starts"** (3ed985a), as a testable rule. DeckEngine's `activate`
  runs first in every start, before the rate is read, and a throw there fails the start with nothing started. The
  app's deck engine and Debug's trial set it rather than calling `activateShared()` by hand.
  `theSessionIsActiveBeforeTheDeckStarts` holds the order, and the pytest holds that every deck engine the app
  makes is given it.
- **Reduce Motion's handover** (2f2fcc7): with no display link, the judge heard the song only at the 0.1 s tick,
  so Reduce Motion's held take could overlap the song for up to 100 ms. The feed now hands each reading to the main
  queue as it reads it, whenever the link isn't running. Untested app code; check 19.
- **CD art at the face's size** (37b2386): ImageIO's thumbnail off the main thread, its shorter side the face's
  pixels, in place of a full-size decode kept for the run. The function, run on the Mac: 3000x3000 to 1020x1020,
  3000x2000 to 1530x1020, and 600x600 untouched.
- **`closed()`** (8ab87be) lets go of a followed touch as a cancel, so a record held as Now Playing closes settles
  rather than staying held.
- **Headphones out** (5a9d735): `DeckRules.outputGone()`, question 27 above.
  `theOutputGoneResumesNothing` runs four cases (a held press, a led handover, a handover with no lead, a song
  change under the hand), each also without `outputGone()` to show that it resumes. The app calls it, and lets go
  of a followed touch, on `.oldDeviceUnavailable`.

**Mutations, each alone, all caught but one.**

| Mutation | Caught by |
| --- | --- |
| The time line's `maxHeight: .infinity` put back | test_the_scrubbers_row_never_asks_for_height |
| The face's parts content-box (rings outside) | theFacesPartsAreTheStylesheets, theLabelsRingIsWhereTheWebsIs, theSpindlesRingIsInsideItsShare, the pytest |
| Debug's report without the interrupted row | theTurntableSoundRowSaysThePhonesStates |
| A failed start forgotten at any press, not after 2 s | aFailedStartIsForgottenByARouteOrAPressNotByTime |
| The start read before it was seen | theHandoversStartIsReadOnlyOnceItWasSeen |
| A repeated "playing" counted as a start | theHandoversStartIsReadOnlyOnceItWasSeen |
| `debug()` put back at the let-go | test_only_the_position_queue_asks_the_songs_engine |
| The ring's older window kept over the newer | theWindowKeptAsideIsNewerThanTheRings |
| The engine's 48 kHz guess taken before its first start | aWindowIsMadeAtTheRateTheEngineWillRunAt |
| No windowDropped from routeChanged / from start | aNewRateDropsTheWindowAndSaysSo |
| The session activated after the rate is read | theSessionIsActiveBeforeTheDeckStarts |
| Debug's trial without `activate` | test_every_deck_engine_the_app_makes_activates_the_session_first |
| outputGone without the pause intent / the handover's conversion / the settle timer's clearing | theOutputGoneResumesNothing |
| outputGone without `clearLed()` | **not caught**: the led timer already does nothing once its plan is replaced (its own identity guard); the call stays as tidiness |

**Docs**: docs/ios.md and section 8 reword check 3 (the turntable about as wide as the cover was, a few points
narrower), check 15 (AirPods out holding the record and just after: the record rests and the song stays paused)
and check 21 (the pause with the AirPods' stem with the turntable in view, then the lock screen, in place of
"pause from the lock screen while the turntable shows", which no one can watch).

**Verified, after the last fix**:
- `swift test`: Core 957, DeadwaxAudio 142 and DeadwaxTurntable 10, all passed.
- The release DeckRealTimeTests: 3, passed.
- The unsigned Release device build, with no warnings in the app's sources.
- check_project.py.
- pytest tests/test_ios_*.py tests/test_source_bytes.py: 150 passed, 1 skipped.
- The ios sims weren't run: none reads a file these fixes touched.

**Not verified**: the app's wiring for every fix above is app code with no test on this Mac, built for a device
only. The order of the player's pause and the deck's on the same route notice is not known; either order resumes
nothing. Whether UIKit ever skips the cancel when Now Playing closes is also not known.

### 7.4 Slice 4 - the fader

- **Files**: PlaybackEngine.swift (5.2 - the change this slice is for, its own commit, measured first: 5.3);
  `ios/App/Player/Turntable/` (the fader and the readout), `NowPlayingView.swift` (the chip), PlayerModel (the speed,
  kept), NowPlayingController (the rate); Debug's Speed row; docs/ios.md; notes/ios.md.
- **The tests**: 5.3's eight, on the macOS job, written and run **before** the fader's view (the measurement is
  the gate, and its numbers go to James first); every existing engine render test unchanged and passing - the
  proof that 1x is today's sound.
- **Must not touch**: anything that plays at 1x - the measured gate decides how the varispeed is out of the path.
- **Verified**: ios.yml; the phone (8, checks 25-31).

#### Slice 4, first half, built (2026-11-13)

Two parts, each its own commit, stopped before the fader's view: Debug's recorder and its replay (6.3, question 23),
then the engine change (5.2), measured by 5.3's eight on the macOS job - and, after the review, a commit of fixes to
each. Nothing in the app sets a speed yet.

**What was built.**

- **The recorder** (ae84f26). Debug's "Record 20 s" writes the web's own file (deck.ts's version 3: int16 audio,
  blockTimes, blockPeaks, messages, heard) with the phone's keys under `phone`: each block's now, `L`, host and sample
  time, the windows before and after, the messages applied before it, float32 audio, and the touches and handovers.
  The deck engine's render taps every block and message into rings (32 blocks, 1,024 messages) made at the first
  start a recording asks for them, drained ten times a second; a full ring loses and counts, never waits. Saved
  through ShareLink; "Record 20 s again" under it starts another, deleting the files before it. It ends by the
  clock - `seconds` from its first block, rests included (below). `replay-deck-recording` (a `swift run` target)
  plays a recording through the Swift voice: the phone's from its applied messages, the web's at the timing the lab's
  planTiming finds. A phone recording replays to the bit; the web's (exported by deck.ts's own recorder,
  `ios/scripts/export-deck-recording.cjs`) with every 16-bit sample the same.
- **The engine change** (PlaybackEngine.swift):
  - **the speed's chain**: every lane in the path into one AVAudioMixerNode, through ONE AVAudioUnitVarispeed (render
    quality 127, the most), into the main mixer. Made the first time a lane needs it; hooked into the main mixer only
    while a lane is in it (`speedChain`, `unhookSpeedChain`); dropped and made again at a new output format;
  - at 1x **out of the path** - each lane's node straight into the main mixer, as before the speed - which item 1
    measured exact; with the speed never moved the chain is never made;
  - the path decided as a lane begins (its first buffer after a clear, `fitPath`): in it while the speed isn't 1, or
    when a lane in it is playing or has buffers on it (a join takes the path of the lane it follows); every clear at
    1x takes the lanes out and unhooks the chain;
  - `setSpeed(_:exact:)` (held to 0.25-4, not-a-number to 1) and `speed`, for the fader; the chain takes a new speed
    at the next render;
  - leaving 1x while a lane plays straight to the mixer: the lanes begun again in the chain from the frame the render
    reached (`renderedSpot`: the last render's reading and one IO buffer); paused, from the frame heard;
  - back at 1x the chain plays on at rate 1 (no gap mid-drag); **`setSpeed(1, exact: true)`** - the fader let go at
    1x, James's answer - begins the lanes again straight to the main mixer from the frame the chain gave out (the
    reading less its 48-frame delay and the one frame its resampler reads past it), the song's own samples from there;
  - while a lane begun again hasn't yet rendered what the output's latency holds, the position is still the song
    before it (`stillHeard`) - no jump at either restart;
  - positions in the song's time: the node's frame less the varispeed's 48 frames, less the latency in the song's
    time - over the speeds it was rendered at (`HeardEstimate.songSeconds`, Core, with `SpeedChange`; live by host
    time, offline by the render's own seconds). A reading keeps the speed it was read at and those song seconds
    (`HeardReading.speed`, `.behind`), so an estimate after iOS stops the output carries on at the reading's speed;
  - a change of lane at speed: both nodes in the chain's one time base, the new lane started at the sample the first
    ends at; starts from silence count the margin and the lead at the speed; the clock's backstop (`ranOut`, a
    quarter of a second) and the window that puts a converter's last frames on before a node runs out are counted in
    the output's time, so `speed` of the node's frames;
  - `Settings.varispeedAtOne` (`outOfPath`, `bypassed`, `atRateOne`), for the measurement only.
- **Tests**: VarispeedMeasuredTests (items 1-5, 7 and 8, a mono song at speed, 4x on a locked phone's buffer) and
  VarispeedCostTests (item 6), on the macOS job; every test engine reads `DEADWAX_VARISPEED_AT_ONE`, so the render
  suites run each way; ios.yml runs the cost again in a release build. DeckRecordingTests for the recorder.

**Measured (5.3).** On this Mac, offline, a debug build unless it says - after the review's fixes.

| item | what | bar | measured |
| --- | --- | --- | --- |
| 1 | 30 s of noise and a sweep (a 48 kHz FLAC) at 1x | the file's own samples, every bit | out of the path: all 1,440,000 frames the same, from the first. Bypassed: every sample exact, but 47 frames late. In the path at rate 1: 48 frames late, and filtered - up to 0.34 (-9.3 dB) off on the noise |
| 1 | the render suites (147 audio tests, before the review's) | all pass | out of the path: all pass. Bypassed: 62 fail. At rate 1: 64 fail |
| 2 | a -6 dBFS 1 kHz tone: what isn't the tone | over 60 dB under it | 140.4 dB at 0.25x, 140.7 at 0.5x, 132.8 at 1.5x, 144.7 at 2x; its level 0.0 dB at each |
| 2 | 20 kHz | - | 0.25x (5 kHz): 135.1 dB clean; 0.5x (10 kHz): 136.1 dB |
| 2 | what folds back past 24 kHz | under -40 dB | 20 kHz at 1.5x (30 kHz): -119.5 dB; at 2x (40 kHz): -116.6 dB; 15 kHz at 2x (30 kHz, the bar's own): -113.1 dB |
| 2 | a mono song at 1.5x and 0.5x | its level at 1x, on both channels | 133.7 and 141.1 dB clean, 0.0 dB from 1x on each channel; its position 0.00 frames off the clicks |
| 3 | the position against clicks heard, 1.5x | within 1 output frame | 0.00 frames off at 186 readings; with 0.1 s of latency 0.00 at 176; 0.25x, and 2x with latency, 0.00 too |
| 4 | test sounds 9 and 10 (one lane) | the join's largest stray under -50 dB | 2x: -135.8 dB (the tone 144.7 dB clean); 0.25x: -129.5 dB (139.3); 1x: -137.6 dB |
| 4 | a change of lane, 44.1 into 96 kHz, the phone's buffering | no worse than the same join at 1x (+3 dB) | see the table below: every speed -46.2 dB or under, against 1x's -46.6 |
| 4 | the same at 2x with 0.3 s ahead and 4,096-frame renders | not over the first lane | on time: no frame of silence at the join (the longest quiet is 1 frame, a zero crossing), -53.9 dB |
| 5 | 1.5x, 0.75x, 2x, 0.6x, a second apart | no click, no position jump | each change's largest step equals the faster tone's own; 0 jumps in 399 readings |
| 6 | a 192 kHz FLAC to a 48 kHz output, 2x | (release) median block under 15% | a 4,096-frame block: 0.04% of its time at 1x, 0.19% at 2x, 0.14% at 0.25x; release: 0.03% at 1x, 0.15% at 2x, 0.12% at 0.25x (the one chain). The 12 s file decoded, converted and scheduled in 0.81 s at 1x, 0.80 s at 2x (release) |
| 7 | a drag 0.9x-1.1x-0.9x, 0.01 every 10 ms | no click, no gap | the largest step the 1.1x tone's own (0.03167); no 10 ms under 0.4999 of the tone's 0.5. Then a pause and play at 1x: the song's own samples, bit for bit |
| 7 | begun at 1x, then 1.01x, the output's latency 0.1 s, a ramp for the song | on from the frame rendered | the song from frame 48000.00 - the frame the render had reached (the ear was at 43200); it comes in 48 frames after the change (the chain's delay, 48 / 1.01); the position 0.90000 s before and after, never back across it |
| 7 | held at 1x in the chain, then let go (`exact`) | the song's own samples again | the chain's last frame out the song's 76751, then the song from 76752 - bit for bit for 40,000 frames, no frame of silence offline; the position 1.49902 s before and after |
| 8 | the varispeed's own delay | measured, not assumed | 48.00 of the node's frames at 0.25x, 1x (in the path), 1.5x and 2x. Its kAudioUnitProperty_Latency says 0 |
| - | 4x, 4,096-frame IO buffer, a 44.1 kHz song whose next hasn't come | its end on time, as with nothing after it | its converter's last frames put on with 30,464 of the node's frames left; the render bit for bit the song alone's; the backstop past 1.5 IO buffers' clock error at 0.25x-4x |

**A change of lane at each speed** (44.1 kHz into 96 kHz, the phone's buffering; the largest stray sample within 50
ms of the join, the bar 1x's own +3 dB). Before the review's fix there was a varispeed per lane: each lane's own
fractional phase, so a change of lane was clean only where the two happened to agree (0.73x, 1.01x and 1.37x are the
review's numbers; the others were 05fb130's).

| speed | one varispeed (now) | a varispeed per lane (before) |
| --- | --- | --- |
| 1x | -46.6 dB (the bar) | -46.6 |
| 0.25x | -46.2 | -46.2 |
| 0.73x | -46.6 | -35.2 |
| 1.01x | -48.6 | -36.0 |
| 1.37x | -52.2 | -39.3 |
| 2x | -53.9 | -53.9 |
| 2.9x | -58.2 | - |
| 4x | -60.0 | -60.0 |

**Mutations, each caught**: bypassed at 1x (61 render tests, and items 1, 3 and 7); in the path at rate 1 at 1x (61
render tests, item 1); the delay not taken off (item 3); the latency not counted at the speed (item 3); the join not
put into the new lane's time (item 4); the speed not given to a lane playing (item 5). After the review: resuming
from the frame heard, not the frame rendered (crossingOneX: the ramp's frame, the position, the let-go); the let-go
doing nothing (its bit-for-bit samples); the chain's delay alone taken off at a let-go (one frame skipped); the flush
window and the backstop in the node's time (the 4x test); no `renderAtStart` at a reconnect (the position at the
let-go); the position not kept across a restart (both); a recording judged by its last block kept (the rest test).

**Departures, and why.**

- **Out of the path, not bypassed, at 1x**: item 1. Bypassed is every sample right, 47 frames late - every position,
  join and resume the render suites check moves. So item 7's "bypassed at the next fresh start" is "taken out of the
  path", and the other way can't be a flag: a node reconnected while it plays stops and drops its schedule. **The
  first move off 1x begins the lanes again** in the chain (James: take the short gap): offline 48 frames before the
  song comes in (the chain's delay); on the phone also the wait for the reconnected node's first render (one or two
  IO buffers: 5-20 ms unlocked, more locked). The spec's 7 put the click at bypassing back at 1x; here it is a short
  gap at leaving it - and, James's second answer, another at letting go at 1x.
- **One varispeed for every lane, not one per lane** (5.2 said per lane): the review measured a change of lane at
  speeds between round ones 7-11 dB worse than at 1x, each lane's resampler at its own fractional phase. One chain
  puts both nodes in one time base, so a join is the sample the first ends at, through one resampler.
- **From the frame rendered, not the one heard**: unlike a pause or a new route, the output still plays all it holds;
  begun again from the frame heard, the latency would play twice (0.2 s on AirPods).
- **`aheadSeconds` stays in the song's frames**, as 5.2 says: at 4x, 2 s ahead is 0.5 s of the clock.
- **A change of lane rings at a cut mid-waveform at 1x too** (-46.6 dB): each lane's converter takes its part as a
  song on its own. Today's engine, not the speed's; item 4's lane bar is held to it.
- **The lock screen's rate and plays at speed are the fader's half**: both are the app's. The engine's positions are
  the song's time at any speed (item 3), but `Plays.listenedStep` caps a step at the clock times its `rate`, which
  PlayReporter leaves at 1 - so at 2x it would count half. PlayerModel passes the speed there with the fader.
- **For the fader's half: the first move off 1x, and a let-go, publish `.loading` then `.playing`** - the lanes begun
  again go through `begin`. The fader's view and the transport mustn't flash a loading state for it.
- **The app stays 0.6 (6)**: a Debug feature and an engine API nothing calls yet.

**What only the phone shows.** A reconnected node's first live render time (offline it has none until rendered; live
it reads a stale one, which `renderAtStart` now refuses); the gaps at the first move off 1x and at a let-go, live;
whether the restart's frame is exact live (offline the reading is the render's end; live it is the last render's
start plus an IO buffer, and the varispeed's pulls needn't be IO buffers); the latency at speed on AirPods and
AirPlay (`songSeconds` over the speed's history); the chain's cost on the phone's chip; a rate changed under a live
render (offline it takes the next render exactly); the chain at 4x on a locked phone (offline its 4,096-frame renders
pulled 16,384 frames through the mixer without a refusal); the lock screen at speed (8).

**James's answers** (2026-11-13).

1. **The first move off 1x is a short gap**: take it.
2. **Exact again on let-go**: when the fader is let go at 1x, the chain comes out of the path (one short gap then),
   rather than staying filtered until the next pause, seek or song - in this engine nearly every song change is a
   join, so "until the next fresh start" could be a whole session of filtered 1x. Built in the engine
   (`setSpeed(1, exact: true)`), for the fader to call on release; mid-drag, crossing 1x stays in the chain at rate 1.

**After the review** (2026-11-13). The review of ae84f26 and the speed's commit confirmed 1x untouched in every path
while the speed is never moved, and found:

1. **The recorder never finished across a rest**: "done" was judged from the last block kept and blocks past the end
   were dropped, so a recording whose 20 s ended while the record rested kept its tap on and Debug's tick running.
   Now ended by the clock (a block at or past the end; live, host time while resting); "Record 20 s again" after a
   save; earlier files deleted; the tap's rings (about 1.1 MB) made at the first recording's start, not in every deck
   engine.
2. **A change of lane was clean only at the speeds tested** (above): one chain for every lane.
3. **The backstop and the flush window were in the node's frames**: at 4x a quarter second of them is 62 ms, under a
   locked IO buffer. In the output's time now.
4. **A reconnected node's stale render time** (of the base it left) could be taken for a time to start at:
   `renderAtStart` is set at every reconnect.
5. **The crossing test ran with no latency on a sine**, so resuming from the frame heard passed it: with 0.1 s of
   latency and a ramp it reads the frame resumed at off the sound. A mono lane at speed added.
6. **Smaller**: a reading's latency was kept divided by the speed then and read back at the speed now (the speed and
   the song's seconds kept instead); a join followed only a lane already started (a lane with buffers on it counts
   now); `nodeOffset` reads one render by its host time too; the trace's speed lines are a drag's every half second.

#### Slice 4, second half, built (2026-11-13)

The fader's view, its readout, the cover's chip and the ••• menu's line, the speed kept, and what the first half left
for this one: the lock screen's rate, plays counted at speed, and no flicker while the engine begins its lanes again.
App 0.7 (7). PlaybackEngine has no diff; nor have PCMSource, GainedSource, StreamSource, the EQ's render, ui/ and src/.

**What was built.**

- **Core** (PlaySpeed.swift). The kept speed - `deadwax-player-speed`, read by the web's rule (decimal text, a speed
  in 0.25-2, rounded to a hundredth; anything else 1x) and written as the web writes it. The pace measured for
  Debug (PACE_WINDOW_S 8, PACE_MIN_S 2, `paceStep`, `paceOf`). `ticks(from:to:)`, the tick's rule: into exactly 1x
  from any other speed. And three small machines the app runs:
  - `SpeedControl` - what the engine is told. A drag's every speed as it comes (`restarts` when it leaves 1x, the
    lanes begun again in the chain), through 1x at rate 1 in the chain; a let-go at 1x after a drag
    `setSpeed(1, exact: true)` (James's answer), the only time a let-go sends anything; a jump - the readout's tap,
    the chip, the menu's line, a VoiceOver step - exact when it lands on 1x; the kept speed at the engine's start
    (`atStart`, nil at 1x, so at 1x the chain is never made).
  - `SpeedRestartHold` - the `.loading` a restart publishes, shown as playing: armed by a send that may begin the
    lanes again while the entry plays, it hides that entry's loading for up to 1 s. Playing ends it, and so does any
    phase but loading (a pause, a failure, the end are never hidden); past the second, a loading still there shows.
  - `SpeedPublishing` - the lock screen told a new speed at once, then no more than every 0.25 s through a drag,
    the last change of a run always told at the end of its gap.
- **Plays** (Plays.swift). ListenTracker keeps the speed (`speedChanged`): a step is capped at the clock times the
  fastest speed it spanned, so at 2x the song's seconds count in full, and a step across a change from 2x down isn't
  cut to the slower speed. The speed outlives a stop, a new listen and a join.
- **The drawing.** DeadwaxTurntable's `TurntableReadout`: the readout's face as a layer tree of its own - the fill
  laid on the plinth's colour, the hairline edge, at 1x the well and its inset band (1 pt inside the top edge,
  following the corners), off 1x the toggled face - sized by its words (0.6 em a figure, 0.15 em by 0.4 em of
  padding). TurntableLayers draws it in the renders; the app hosts the same face in a control (`drawsReadout =
  false` there). `TurntableLayout.faderSpan` (the knob's travel, 6 past each end of the slot) and `readoutTarget`
  (min(44, 14% of the plinth)); `TurntableFace.chipFace` and `chipPad`; `TurntablePress.follows`.
- **The app.** TurntableDeckView: FaderTouchView over `faderTarget` by `faderSpan`, following one touch, refused
  while the record or the arm follows one (and the record and the arm refuse a touch while the fader is held - one
  counter numbers the three views' touches, as a browser numbers pointers); FaderElement and ReadoutElement, the
  reading order record, arm, fader, readout. DeckController: the fader's down, move and end (the web's faderMove over
  PlaySpeedScale), the light impact as a drag crosses into the detent, the readout's tap, VoiceOver's steps
  (`speedKey`'s ArrowUp and ArrowDown), the knob held while the drag has taken hold, Debug's Speed row last.
  TurntableView: `TurntableReadoutLayer` and `ReadoutControl` (below). NowPlayingView: the chip; NowPlayingMenu: the
  speed's line, first. PlayerModel: the speed - kept, sent, held, published, measured; NowPlayingController: the rate.

**Tests**: SpeedControlTests (10: the kept speed, a drag through 1x and its let-go, a jump to 1x, the tick, the hold
three ways, the publishing, the pace, the span and the target) and PlaysAtSpeedTests (4: half the song in half the
time at 2x, the same steps at 1x short of a play, a step across a change, the speed kept); one render test (the well's
inset at 1x, none off it, the readout not drawn when the app draws its own); `test_the_speed_chip_is_the_webs`
(chipFace and chipPad against app.css's tokens). DeadwaxCore 976, DeadwaxAudio 158, DeadwaxTurntable 11, all passing;
the release real-time and cost tests passing.

**Departures, and why.**

- **The readout is laid over Now Playing's column, not drawn in the plinth's layers.** 5.1 asks for it "a layer
  above the overlay lines", but the foot line is SwiftUI, laid over the titles' row below the plinth, so nothing in
  the plinth's UIView can be above it. The plinth gives its bounds as an anchor preference (`PlinthPlaceKey`), and
  the column's `overlayPreferenceValue` places a `ReadoutControl` (a UIControl drawing TurntableReadout) at READOUT
  in them: above the foot line, as the web's z-index puts it. Its VoiceOver element stays in the deck view, in the
  web's order after the fader; the control is hidden from VoiceOver. It fades with the look's swap.
- **The words' face**: the system's monospaced font in the app (2.11), Menlo in the Mac's renders - both 0.6 em a
  figure, so the face is the same size either way.
- **The inset's 1 px blur isn't drawn**: a 1 pt band of black at 0.5.
- **The restart's loading is hidden for up to a second** (`SpeedRestartHold`): on Play/Pause's spinner and on the
  lock screen, which would otherwise show the song paused for the few milliseconds the lanes take. A restart still
  loading past a second is a real wait, and shows. The platter needed nothing: it already turns through `.loading`.
- **The lock screen's rate is told four times a second at most through a drag**, the last always, each time with the
  position read afresh (MPNowPlayingInfoCenter is another process; a drag is a change a frame).
- **The chip's words stop growing at xxLarge.** 5.1 measured the gap at about 100 pt, but the footer has had Lyrics
  at its left since app 0.4: between AirPlay's and Up Next's 44 pt targets there are about 56 pt on a 393 pt phone
  and 50 on a 375 pt one (about 76 and 70 between their glyphs). The widest chip, `0.25x`, is about 55 pt at the
  default size, 67 at xxLarge and 73 at xxxLarge, past the glyphs on the smaller phone - so its text stops at
  xxLarge, and at the accessibility sizes the ••• menu says it (as 5.1). Its 44 pt target can overlap the
  neighbours' targets by a few points at their outer edges (the chip above), never their glyphs.
- **The ••• menu's speed line is its first section**: at those sizes it is the only place the cover says the speed.
- **No custom actions on the fader** (question 9's A comes after the web's own answer), as slice 3 left them off the
  record: the web's roles alone.
- **Smaller**: the recorder's write (the first half's) captured self strongly in its outer closure - Xcode's one
  warning in the app's sources; weak now. docs/ios.md's check 23 still said the app had no recorder; it asks for
  both recordings now, as 8's does.

**Mutations, each caught** (SpeedControlTests and PlaysAtSpeedTests, fifteen): the let-go at 1x not exact; a drag
not marking the chain (so its let-go sends nothing); the first move off 1x not a restart; the engine told 1x at its
start; a jump onto 1x not exact; the hold hiding any entry's loading; the hold never running out; the hold kept
through a pause (the one that first survived - a test of a pause during a hidden restart added); the lock screen told
every change; the last change of a drag's run dropped; the tick leaving 1x instead of entering it; the kept speed not
rounded; the pace's window unbounded; plays at the clock alone; plays at the speed now rather than the fastest a step
spanned.

**Left as it is**: Debug's handover timing counts the engine's starts by its phase (HandoverStarts), and a speed's
restart is a start - only a fader moved in the fraction of a second between a let-go of the record and the song
being heard could make the Handover row read the restart's start rather than the handover's.

**After the review** (2026-11-13). The review of the fader found the fidelity rules, plays at 2x and the lock screen
holding, and:

1. **The outer part of the fader's target took no touch** (medium): the target is centred on the fader and a tap wide,
   so it overhangs the plinth's right edge - by about 15.5 pt on a 393 pt phone (321 pt plinth) and on a 303 pt one,
   6.6 on a 440 - but the deck's UIView and its SwiftUI frame were the plinth's size, so a touch there never reached
   the touch view: 28.5 pt of 44 worked on the 393 pt phone. Now the view is `TurntableLayout.touchWidth` wide (the
   plinth, and as far as the target reaches), laid out in a plinth-wide frame with the rest overhanging its right,
   into the room's 12 pt and Now Playing's 24 pt margin - so the plinth is drawn where it was. Held by
   `theWholeFaderTargetIsInsideTheViewThatTakesTouches` (Core, five rooms) and a source test of the app's wiring.
2. **The fader was above the arm**, so at a song's start a few points of the handle's ring went to it: its touch view
   is under the arm's now, as the web draws the handle over the fader.
3. **A look switched mid-drag kept the fader held**: `destroy()` didn't let it go, as `closed()` does, and the touch
   view went with the turntable, its cancel perhaps never sent - every turntable touch would then be refused and a
   drag at 1x never get its exact let-go. `destroy()` lets it go first now.
4. **The join's speed went untested**: the join in theSpeedOutlivesAStopAndANewListen fitted 1x's cap too.
   aJoinAtTwoXCountsBothSidesInFull's doesn't (caught with `rate: pace()` taken out of the join).

Left as they are: the hold armed by a send that turns out not to restart (up to a second in which a real loading of
the same song would show late); and Debug's own Play/Pause, which reads the engine's phase directly, so it flashes
during a restart as Now Playing's no longer does.

**What only the phone shows.** All of the app's half: the fader under a thumb (its target, the slop, the speed
following, the knob lit while held), the tick and its timing, the readout's place over the plinth's corner and over
the foot line, its tap, the large content viewer, the chip's place and its fit at each text size, the menu's line,
VoiceOver's order and steps, the hold hiding the restart (live, the restart is 5-20 ms unlocked, more locked), the
lock screen's clock at the speed and its position across a drag, plays at 2x counted by Navidrome, the speed kept
across a launch, and the gaps at the first move off 1x and at a let-go, heard. Checks 25-38.

---

## 8. James's checks on his iPhone

Each: what to do, and what you should see or hear. Earbuds or the speaker unless it says. Answers through the
usual question buttons.

**After slice 2** (Debug > Test sounds > "The record's engine beside the song"):

0a. Play a test sound, then start the record's engine beside it: you hear both at once - the test sound unchanged,
    the record's run over it.
0b. Stop and start the record's engine five times while the test sound plays: nothing in the test sound - no
    click, no drop, no change of level.
0c. Watch the Clock row for a minute on the speaker, then on the earbuds: the first number moves by no more than
    a millisecond or two once it has settled. Tell me both numbers.

**After slice 3:**

1. You > Playback: Gapless, then **Now Playing opens as** (Cover ticked), then **Pause winds the record down**
   (on), then Normalization - each with its own note under it. Choose Turntable.
2. Play an album and open Now Playing: it opens on the turntable. The top-right button (a record, in a square
   face) switches to the cover and back; closing and opening again opens on the turntable, whatever you switched
   to.
3. On the turntable, compare with the cover: the title and the artist move to the middle; nothing moves up or
   down - the time line sits in the scrubber's row, the titles, the transport and the footer stay. The plinth is
   about as wide as the cover was (a few points narrower, never a small record in a tall gap); nothing overlaps.
   (The smallest phone's size is checked from the Mac's render, 7.3.)
4. An album you've saved CD art for (Get CD art): the record's face is the CD art. A two-disc album with
   `disc2.jpg`: a disc 2 song shows it. An album with none: a black record with the cover as its label.
5. The record turns once every 1.8 s (33⅓) while playing, smoothly - Debug > Turntable: "Frames under a hand"
   with few late.
6. Tap the record: the song pauses, the record's sound slowing to a stop over about a second with the platter.
   Tap again: it plays. Turn **Pause winds the record down** off: the pause is instant. Pause from the cover:
   always instant.
7. Hold the record while it plays: the song pauses under your finger. Turn it slowly, quickly, backwards: you hear
   it follow, a little more than an eighth of a second behind; resting your finger is silence.
8. Let go mid-turn: the record carries on at your hand's speed, the motor brings it back up, and the song carries
   on. Listen for the moment the song takes over: no jump back, no repeat, no gap - and no moment where it sounds
   doubled or briefly louder. Do it ten times, with a downloaded song and with one streaming; Debug's Handover row
   says each one's seam.
9. Pause, then flick the record: it coasts to a stop with its sound; the song stays paused where it stopped; play
   starts from there.
10. Drag the arm: the head lifts, the time line says "Needle up · …"; let go and the song plays from there.
11. An MP3: turn the record - silent, and the line "The record makes sound for FLAC songs only - this one moves
    silently." over the foot of the plinth, until the next song.
12. A song never played before (not downloaded, not cached), turned while it is still coming in: it has its sound
    (Debug: "Window from: deadwax - the song is still coming in"). Played again later: "The copy kept on this
    phone".
13. A downloaded album, in Airplane mode: the record has its sound (Debug: "This phone's download").
14. A 96 kHz album: let go at 1x - the record's sound and the song are the same loudness and tone across the
    handover. With Normalization on: the same.
15. While holding the record: have Siri speak, or take a call - the record's sound stops, nothing stuck, and the
    song doesn't start into the call. Take AirPods out mid-turn - holding the record, and just after letting go:
    no sound from the speaker, the record comes to rest, and the song stays paused until played (question 27).
16. Flick the record and go Home while it coasts: the sound stops at once. Come back: the song is where it was
    going.
17. AirPlay to a speaker: turning the record is silent, with the AirPlay line.
18. VoiceOver: the look button, the record ("The record: a tap pauses the song"), the arm ("Tonearm: position in
    the song", "2:31 of 7:05", swiping up and down moves 5 s), in that order.
19. Reduce Motion on: the record doesn't turn; a let-go goes straight on, no coast, and no gap before the song; a
    pause is instant. The hand still has its sound.
20. The largest text size: the time line on one line, the readout inside its corner; a long press on the look
    button shows its large version.
21. **The lock screen after a wind-down.** On the turntable, with the wind-down on, tap the record to pause and
    lock the phone straight away: within two seconds the lock screen shows the song paused (▶). Press the AirPods'
    stem (or the lock screen's play): it plays. Unlock with the turntable showing and pause with the AirPods' stem:
    the platter runs down silently; lock the phone then, and the lock screen shows the song paused. Then the same
    with the wind-down off.
22. Debug > Turntable: every row has a value; "Delay behind the hand" names the earbuds' extra on Bluetooth.
23. **The blind A/B against Safari.** Same iPhone, same song, both on the turntable: Safari at deadwax's address,
    and the app. Someone else tosses a coin and hands you the phone with one or the other open; eyes closed, take
    the record, scratch it, flick it, let it hand back, then say A or B. Ten times. Write down how many you got
    right, and anything that sounded different and in which. Then record 20 s in each (Debug > Record 20 s, the
    same song and a similar motion) and send both files. (Safari at a plain http address has no AudioWorklet, so
    its record plays on the page's own thread, about 43 ms later and a little less steady than the app's - a
    difference you may hear in the delay, not the sound. The Safari recording is also replayed through the app's
    voice on the Mac (6.3), which tests the sound itself.)
24. Leave the turntable showing while playing a whole album: no warmth beyond the cover's, battery as the cover's
    (it draws only while something moves; it turns while playing, and its engine runs beside the song's, so a
    little more).

**After slice 4:**

25. The fader: drag the knob up - the song speeds up and its pitch rises; the readout says `1.25x` in purple; the
    platter turns faster. Back near the mark it snaps to exactly 1x with one small tick under your thumb; the mark
    goes green. The knob takes a thumb a little either side of it, just past the plinth's right edge too (the
    review's fix); at a song's start the arm's handle beside it takes the arm.
26. Tap the readout: straight back to 1x.
27. Off 1x, switch to the cover: `1.25x` between AirPlay and Up Next; tap it - 1x. The mini player shows nothing.
28. At 1x everything sounds as before the fader existed (Test sounds 9 and 10 unbroken).
29. At 2x and at 0.5x: Test sounds 9 and 10 still unbroken; the lock screen's scrubber moves at the speed.
30. At 1.5x, take and let go of the record: it comes back to 1.5x (50 rpm), the song at 1.5x.
31. While a song plays, drag the fader slowly up through 1x and back down through it, several times: no click
    or jump at the mark either way. Then let go at the mark: one short gap (a few ms), then the song exactly as
    before the fader existed (James's answer: exact again on let-go). The first move off 1x has a short gap too.
32. No flicker: watch Play/Pause under the record while moving the fader off 1x and letting go at 1x, a few
    times - it stays a pause button, no spinner, no flash of play. Lock the phone at 1.25x: the lock screen shows
    the song playing, its clock at the speed; Control Center's clock agrees with Now Playing's.
33. Plays at 2x: a song of four minutes or more played at 2x to just past its half, then skipped, counts as played
    (Navidrome's play count) - about a minute of the clock for a four-minute song; at 1x the same minute doesn't.
34. The tick: drag slowly back and forth across the mark - one tick each time into it, none leaving it; none from
    the readout's tap, the chip or VoiceOver's steps.
35. Kept: set 1.25x, close the app from the app switcher, open it again - still 1.25x from the first note.
36. One finger at a time: holding the record, a finger on the fader moves nothing; holding the fader, a tap on the
    record doesn't pause. Close Now Playing while holding the fader: the speed stays where the finger had it.
37. VoiceOver: after the arm, the fader ("Speed", "normal speed"; a swipe up "1.01 times"), then the readout
    ("Speed 1.01x: back to normal speed"; a double-tap goes to 1x, then "Speed: normal", dimmed). On the cover off
    1x, the chip: "1.25x, 1.25 times the song's speed: back to normal speed".
38. An accessibility text size: the readout's words stay inside its corner; a long press on it shows `1.25x` large.
    On the cover off 1x, no chip: the ••• menu's first line is "Speed 1.25x - back to normal speed", and it goes
    back to 1x.

---

## 9. What only a device can tell

- **The touch rate**: how many samples a second the digitizer gives through coalesced touches, and whether events
  come at 120 a second with the display link running.
- **The clock**: whether mHostTime is smooth block to block, what the IO buffer really is in long-form playback,
  and whether the largest lead `L` is bounded and steady (3.2) - Debug's Clock row, checks 0c and 22.
- **The second engine**: how long its start takes on a press, whether it ever fails beside the song's engine, and
  whether starting or stopping it is ever heard in the song (checks 0a-0b; a handover has both running).
- **The handover**: `E`'s spread on the speaker, AirPods and wired, local and streamed, and how well the median of
  five predicts the next; the main-queue timer's lateness; whether `position()` ever waits long on the engine's
  queue during a resume; the seam and the overlap by ear and in Debug (3.5); whether the alternative (question 2)
  is needed.
- **The window's making**: how long 40 s of a 44.1 kHz song takes to decode and convert at `.max` on the phone,
  and so whether the two-step window (4.4) is needed.
- **The render**: whether the voice keeps up on the audio thread at 2x and at MAX_RATE flicks (no overloads), and
  at 120 Hz drawing alongside.
- **The look on the display**: the grooves' fineness at 3x, the sheen, the CD art at the face's size, the plinth on
  an SE's height.
- **The lock screen and Control Center with two engines**: whether the deck's output running about 1.5 s past a
  wind-down's pause leaves the lock screen showing playing, and whether publishing the paused state again as it
  stops puts it right (4.6, check 21).
- **Bluetooth**: what the earbuds add, and whether the record is still usable behind it.
- **The fader's varispeed** by ear: its tone at 0.25x and 2x; the lock screen's rate.
- **Heat and battery** over a whole album on the turntable.

---

## 10. Open questions

Each with what the build does until James answers.

| # | question | option A | option B | recommended |
| --- | --- | --- | --- | --- |
| 1 | The atomics the real-time host needs, on an iOS 17 target | a C11 target (`CDeckRing`), the targets kept - indices and bytes only, no floating point in C (4.2) | raise the app to iOS 18 and the package to macOS 15 for Swift's `Synchronization` | A - nothing else moves; B costs James nothing on iOS 27 and can come later |
| 2 | The handover, given the engine's slow restart | resume early by the engine's predicted start (3.5), the engine untouched | a hold that keeps the song's output running during a deck sound, so it restarts within its latency - an engine change | A; B if the seam measures over 30 ms at 1x on the phone, or if two engines misbehave together (checks 0a-0b) |
| 3 | The window's rate | converted to the output's rate by a converter set as the lane's (4.4), held to the lane on the grid and to the tones off it | kept at the file's rate, the voice's sinc converting | A - the voice gets what the web's gets, and the record at 1x is the song |
| 4 | Songs that aren't FLAC, when the file is on the phone | FLAC only, as the web | any file AVAudioFile decodes, when local (the stream's /scrub stays FLAC) | A - one rule everywhere, and only FLAC's seek is sample-exact, so only there is the window's place (and the handover's seam) proven; B later if James wants it |
| 5 | AirPlay | the record silent, with a line | its sound about 2 s late | A |
| 6 | The touch rate | every coalesced sample (120 Hz or more) | thinned to 60 Hz, as the web's fixtures mostly are | A - the voice's fit takes any rate, and the fixtures include 120 Hz |
| 7 | Debug's recorder | port "Record 20 s" (6.3), with the replay of a recording on the Mac | leave it out | A, in slice 3 - the A/B needs it, and the replay makes Safari's recording a test |
| 8 | The fader at 1x | the varispeed bypassed - and, if bypassing a running one clicks (5.3, item 7), left in at rate 1 until the next pause, seek or song change | the varispeed out of the graph | whichever measures bit-exact (5.3); A tried first |
| 9 | VoiceOver beyond the web | custom actions on the record (5 s back and forward) and the fader (a tenth) | the web's roles alone | A, after the web's own answer |
| 10 | "This browser can't make the record's sound" | "phone" for "browser" | the web's words as they are | A |
| 11 | Disc art with a download | kept on disk with the album | in memory, as fetched this run | B for these slices |
| 12 | The voice's clock | the render's host time less `L`, the largest end-of-block lead over the last 1.5 s, slewed under a sound (3.2) - the web's envelope, mirrored | deckClock.ts ported as it is, mapping the main thread's clock onto the render's sample clock | A - the clocks are already one; what is kept from deckClock.ts is where a block sits (its end) and how the offset moves (its slew) |
| 13 | When the deck engine runs | only from a press, stopped 0.5 s after its sound | while the turntable shows and the app is in front | **C, between them**: while the turntable shows and the song plays, and while the record sounds; stopped at once on a pause with the record quiet, 0.5 s after its sound otherwise (4.6) - no cold start for the common press, `L` measured continuously, and no running output of its own while the song is paused and quiet |
| 14 | A song still coming in | every window from `/scrub` until the copy is whole (4.5) | windows decoded on the phone from the part that has arrived, `/scrub` only past it | A - a partial copy is decoded from the song's top (StreamSource), so B costs a decode of everything before the window on every refresh |
| 15 | The handover's overlap, once aligned | the web's: the voice held until the song is heard 0.02 s past the target, then HANDOVER_FADE_S | the fade begun as the song is first heard (the predicted time), so the two never sound together at full level | A, for parity with what the web does and the A/B; B if check 8 hears a doubling or a lift |
| 16 | The lock screen after a deck sound past a pause | publish the paused state again as the deck engine stops (4.6) | no deck sound while the song is paused (a wind-down silent; a paused record's turn silent) | A; B only if check 21 fails with A |
| 17 | A tick at the fader's 1x detent | one light impact as a drag crosses into the detent (5.1) | none, as the web | A - Apple's pattern for a detent, and the web has no way to give one |
| 18 | The look button's face | the web's 36 pt secondary face in its 44 pt target (2.1) | a bare glyph, as the chevron is | A - the boards draw it so, and it is the control that has to be found |
| 19 | The chip's place on the cover | over the gap between AirPlay and Up Next, nothing moved (5.1) | a slot before AirPlay, always there | A - B would move AirPlay off the left edge for everyone, at 1x too |
| 20 | The time line's row | the scrubber's height, the line centred in it (2.1) | its own line's height, as the web's, the plinth about 19 pt larger on an SE | A - nothing below it moves when the look switches |
| 21 | A let-go under Reduce Motion | a `take` at where the song goes, then the handover (3.5) | the web's: the sound stopped and the song played at once | A - B leaves the engine's start, 0.2-0.4 s, as silence after every let-go |
| 22 | The IO buffer while the turntable shows | iOS's own (about 1024 frames), the session untouched | ask for 256 frames while it shows, cutting about 30 ms from the record's delay | A - B changes the song's engine's IO too; tried only if checks 7 and 23 find the record late against Safari's, with Debug's Clock row in hand |

---

## Design review (2026-11-12)

A second reading, as a designer and an audio engineer who knows both apps, of the code each claim rests on
(deckVoice.ts, deck.ts, deckClock.ts, Turntable.tsx, NowPlaying.tsx, app.css and theme.css on main; PlaybackEngine,
StreamSource, AudioSessionController, NowPlayingView, ScrubberView, PlaybackSection and PlayerModel on ios). What it
changed is in the sections above; this is the list.

**Changed**

- 3.2 - The voice's clock is anchored on the block's **end** (`L` the largest end-lead over 1.5 s, slewed under a
  sound), not its start (the 10th percentile of start-leads): the start anchor spent a 21 ms iOS block of the 30 ms
  the fit leaves for touch delivery, and had the voice's time ahead of the host clock in most blocks.
- 3.2 - "`now` advances by exactly the block's frames over the rate" corrected: it advances by host time, which
  differs by drift and jitter that the steering absorbs.
- 1.2, 6.2 - The IO buffer named as iOS's own (no preferred duration is set): about 21.3 ms, not the 5.3 ms Debug's
  examples assumed.
- 4.7 - The delay's sum includes `L` (one to two blocks, 21-43 ms), about 150-170 ms on the speaker in all; a
  smaller IO buffer recorded as the one lever, not pulled (question 22).
- 3.5 - `D` includes `L` and is taken in the engine's own convention (`latency()`), so the seam compares like with
  like.
- 3.5 - `E` predicted as the median of the last five resumes of the same kind on the route (a stream's growing with
  the position), 0.3 s before any - not `startLead() + latency()`, which is about 50 ms and leaves out most of a
  resume from a stopped output.
- 3.5 - The judge's `at` is the target the song was really sought to: with a moved target, a judge at `plan.x`
  faded the voice before the song was heard (`isPlaying` is true through `.loading`).
- 3.5 - The judge starts at the resume; a song heard before the plan's end is the web's own "played before the
  coast got back to speed" case.
- 3.4 - `resumeAsked`: the deck's own early resume isn't read by `playingChanged(true)` as a foreign play, which in
  a handover plan would have faded the voice the moment the resume was asked.
- 2.6, 3.4 - The judge never calls `position()` (a `queue.sync`) from a frame: a `deck.position` queue polls it
  during a handover - exactly when a resume holds the engine's queue for its decode and start.
- 3.5 - Reduce Motion's let-go given a mechanism (a `take` at where the song goes, the song sought ahead by
  `speed x (E - D)`); RESUME_IN_GESTURE_S's shortcut dropped, the general rule covering it.
- 3.5 - The aligned overlap (+0.02 s and the 40 ms fade: two coherent copies, about +6 dB for about 30 ms) named,
  kept for parity, and listened for (check 8, question 15).
- 4.4 - The window's grid is the web's 2 s grid with a 0.2 s pre-roll: the 10 ms grid claimed whole frames at
  every FLAC rate, and is half a frame at 22.05 kHz.
- 4.4 - "Equal to the song" split into (a) the window maker against a lane begun on the grid, bit-exact, and (b)
  a seam test off the grid against analytic tones: every pause, resume and seek resets the lane's converter, so
  after a handover its frames are almost never the window's frames, and only (b) tests what the seam needs.
- 4.4 - Decoded and converted a second at a time (40 s of 192 kHz decoded whole is 61 MB), its making timed in
  Debug, and a two-step window if the phone's figure is over 150 ms.
- 4.5 - `/scrub` windows take their end from `first + samples` (deadwax cuts at 8 MB, so hi-res comes back shorter),
  ask 1 s more for the frame `first` starts on, and treat 204 as a cancel.
- 4.5 - "A part still streaming in" read as a song whose copy isn't whole yet: StreamSource decodes from the
  song's top, so a window from a partial copy costs everything before it (question 14).
- 4.1 - The window command and the limiter's growing path allocate in JS; the Swift's form differs there (a fixed
  two-channel struct, both delay lines made up front) and its arithmetic doesn't.
- 4.2 - `Math.round` ported exactly (`(x + 0.5).rounded(.down)` is wrong at 0.49999999999999994 and near 2^52);
  `Math.min`/`max` with JS's NaN and -0 meaning; signed zeros kept; no floating point in the C target (clang
  contracts to FMA by default).
- 4.2, 7.0 - One `DeckMaths` for every transcendental the port calls (exp, log, sin, cos, atan2, hypot, pow,
  log10), not the voice's three: the platter, the geometry and the speed replay exactly too.
- 4.3 - Real-time rules made concrete: a non-generic specialised render entry, a warm-up off the audio thread, the
  state reached only by pointer, a full ring dropping and counting, a return ring that never frees on the audio
  thread, the main thread touching the state only while stopped.
- 4.3 - The allocation test counts only the rendering thread, proves itself with a canary, runs in a release build
  as its own CI step, and has no weaker fallback.
- 3.1 - TurntablePress added to Core: Turntable.tsx's handlers and NowPlaying's turntable toggle hold rules deck.ts
  doesn't (which press is live, the silent scrub, the tap after a turn, the release's seek and play), and the
  bench's traces never pass through them; exported by mounting the real Turntable, hashed into `made_from`.
- 3.3 - `soundReady()` (prepared and allowed, not running) and a decoded `window()` come in through the host:
  deck.ts reads its audio state from the module, and a "ready" meaning "running" would have made every first press
  after a rest silent.
- 2.1, 7.3 - The deck is owned by an app-level DeckController: closing Now Playing is `setShowing(false)`, not a
  destroy, so a coast still hands the song back, as the web's mounted Turntable does.
- 3.1, 2.8 - An audio interruption ends a taken press as a cancel that rests, so it doesn't ask the song to play
  into a call; UIKit's cancels mapped.
- 4.6 - When the deck engine runs: while the turntable shows and the song plays, and while it sounds (question
  13's C) - no cold start for the common press, `L` measured continuously.
- 4.6 - The lock screen after a wind-down: the deck's output runs about 1.5 s past a pause; the paused state is
  published again as it stops, checked on the phone (check 21), with a fallback (question 16).
- 4.6 - The deck takes the session's notifications itself (the controller's callbacks are single closures
  PlayerModel owns), activates the session before starting, and says what a press on a paused record does to
  another app's sound.
- 2.8 - States added: a pause the turntable didn't ask for (silent run-down, the engine stopped at once) and a
  route change.
- 2.1 - The titles are centred on the turntable, as the web's are; the spec had them staying put.
- 2.1 - The time line keeping the scrubber's row marked **Phone:** with its cost (about 19 pt of plinth on an SE).
- 2.1 - The look button keeps the web's 36 pt secondary face (the spec had dropped it without saying), question 18.
- 2.1 - The overlay lines stop at `.accessibility1`.
- 2.2 - The plinth's top highlight added.
- 2.4 - Grooves and layers in Core Graphics and Core Animation only, in a `DeadwaxTurntable` target, so the
  drawing renders on the macOS runner; the sheen's CSS angles mapped to a conic CAGradientLayer's, and tested.
- 2.5 - The arm's head lifts 5 units while held; the handle's ring at text-3 under Increase Contrast (**new**).
- 2.10 - The arm's `.notEnabled` without a length; direct interaction on the record considered and refused.
- 2.11, 2.14 - The time line, readout and chip in `.monospaced()` (the web's mono), the time line in
  Palette.quiet, centred, scaled before truncating.
- 2.14, 5.1 - The readout's off-1x face is the toggled face in accent-text (#d8b4fe), not the accent; Palette gains
  the toggled, well, highlight and secondary tokens, held to theme.css.
- 5.1 - The chip placed over the gap between AirPlay and Up Next (the app's footer spreads its buttons; a slot
  before AirPlay would move it for everyone), on the cover only, as the web's; question 19.
- 5.1 - A light tick at the fader's 1x detent (**new**), question 17.
- 5.2 - Position at speed made exact (the node's frames are the song's; latency scaled by the speed; the
  varispeed's own delay measured); the converter-at-the-ratio alternative recorded as not taken.
- 5.3 - Two measurements added: crossing 1x while playing, both ways (bypassing a running varispeed may click),
  and the varispeed's own delay; question 8 extended accordingly.
- 6.1 - Each new setting a Section of its own with its note as the footer, as PlaybackSection is built;
  YouWords.kept stays Normalization's.
- 6.2 - Debug rows added: Position read in, Window made in, Messages dropped; the Handover row in one convention.
- 6.3 - A recording replays through the Swift voice on the Mac, so check 23's Safari recording tests the sound,
  not only the ear.
- 7.0 - Fixtures: the press traces, the web's `now` per block, hashes per 4,096-frame span, reports whole for one
  configuration, `jsmath.json`, theme tokens; a 3 MB budget.
- 7.0 - Test B compares the platform's maths against the recorded maths in Swift, which test A proves is the web's
  output - so the web's PCM needn't be committed for every case.
- 7.2 - One Debug row in slice 2 so James hears two engines together, and their starts and stops, before slice 3
  is built on them (checks 0a-0c); HandoverTimingTests specified as two offline engines in lockstep.
- 7.3 - The look rendered and asserted on the macOS runner; nothing in any slice needs a Simulator.
- 8 - Checks 0a-0c, 21 (the lock screen after a wind-down) and 31 (crossing 1x) added; 8 listens for the overlap;
  23 says Safari on http has no AudioWorklet (1.3, item 7), so the A/B's delay is confounded and the recording's
  replay is its objective half.

**Looked at and kept**

- A second AVAudioEngine for the record (4.3): one engine would mean changing the song's, which stops its output on
  every pause, exactly when the record sounds - and question 2's B stays the way out if two misbehave together.
- The C11 ring (question 1): nothing else moves for it, and Swift's `Synchronization` can come with iOS 18.
- The voice ported line for line, its constants and its order (4.1): read against deckVoice.ts - the 120 ms delay,
  the tricube parabola fit, the Hermite path, the Kaiser sinc (12 zeros, 128 steps, beta 7, widest 4), the 10 Hz
  DC blocker and the lookahead limiter are the web's, and the review found nothing to change in what they compute.
- Test A by replay, bit for bit, with test B at -100 dB as James's bar (point 4): both are achievable, and A is the
  one that finds a constant wrong by an ulp.
- Converting the window on the phone rather than asking `/scrub` for `max_rate=48000` (4.5): the phone's output is
  not always 48 kHz, and one conversion path, the lane's own, for local and served windows alike.
- FLAC only (question 4): now also because only FLAC's seek is sample-exact, so only there is the window's place
  proven.
- AirPlay silent (question 5): a record 2 s behind the hand is not a record.
- Every coalesced touch, no predicted ones (3.1): the voice plays 120 ms behind precisely so it never guesses.
- The wind-down's take at the song's position (3.3): it starts the voice about 120 ms back, a short repeat - the web
  does the same, and the A/B is against the web.
- The close drag kept to the top row on the turntable (2.7): a gesture on a sibling of the record's view can't see
  its touches.
- `CADisableMinimumFrameDurationOnPhone` for 120 Hz (2.6): Apple's documented way, and check_project.py holds it.
- Swift's arithmetic without FMA (4.2): Swift never contracts `a * b + c` unless asked; only C does.
- The varispeed after the node, bypassed at 1x (5.2): it changes what is heard next at once, which a fader drag
  needs; a converter at the speed's ratio would put the speed into what is already scheduled.
- `AVAudioUnitVarispeed`'s range (0.25 to 4) covers the fader's 0.25x to 2x.
- iOS's own IO buffer (4.7, question 22): a smaller one would shorten the record's delay by a block, but it is the
  session's, so the song's engine would pay for it; measured before it is considered.
- DefaultPlaybackRate 1.0 at speed (5.2): Apple's meaning is the normal rate; checked on the phone.
- The four slices and their order: each has a test that fails if it is wrong (test A and B, the press and rules
  replays, the window's two tests, the allocation test with its canary, the render's pixel assertions, the
  fader's measurements before its view), and each runs on ubuntu or the macOS runner without a Simulator.
