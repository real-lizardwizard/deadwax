# The turntable: the look, and momentum with its own sound

The turntable (2.0.0-player.11), part two (.14) and its fix after James's report (.16) - and the speed
fader beside it (.39), which is the player's speed: see "The speed fader (2.0.0-player.39)" at the end.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### The turntable (2.0.0-player.11)

(Part of this is superseded by 2.0.0-player.14 - see "The turntable, part two": the CSS spin and
`--dw-record-turn` are gone, the platter turned frame by frame by player/deck.ts; once the record can
sound where it is - the deck's audio context running, a voice ready to play it and a window of the song
there in it (2.0.0-player.16; until then it was only "the context runs", which was James's silent
turntable - see "After James's report") - a press pauses the song and its turn counts from where the
record was taken, the release lands where the platter's momentum says, and the record has its own
sound; a pause from the turntable winds down. Until it can, a press is exactly what is written below.)

James: "I would like to definitely build the turntable" - on the phone ("I don't think it makes a
lot of sense on desktop") - "as long as it has the disc art on the 'record'"; earlier, "the playhead
moved toward the center of the disc as the song plays, tapping on the disc and rotating it is how
you seek, and maybe the skip and other things are at the bottom", "a toggle somewhere to go between
the apple music style and the turntable style", and of the board's first-time hint, "the
instructions for how to use it are a little annoying". The boards are `NowPlaying.dc.html` and
`Turntable.dc.html` (its DCLogic is where the drag maths came from), and `You.dc.html`.

- **Two looks, one sheet.** A button at Now Playing's top right (`.app-look-button`, a 44px target
  holding the boards' 36px secondary box) switches the cover and the turntable - a record icon on
  the cover, a square on the turntable, labelled with the look it switches TO ("Show as a
  turntable" / "Show the cover", `lookButtonLabel`). You > Playback's **Now Playing opens as**
  (`app/LookChoice.tsx`, a radio group exactly like Maximum quality's, between Gapless and it) says
  which it opens as: Cover (the default) or Turntable, per device under `deadwax-player-opens-as`
  (`readPlayerOpensAs`: the turntable only when it says exactly that). **App keeps only the
  SETTING** (`opensAs`, handed to You and to Now Playing); **the look showing is Now Playing's own
  state**, reset to the setting by a layout effect as the sheet opens, every time - so the button
  never changes the setting, and switching re-renders the sheet and never App or the engine.
- **Gesture ownership: the record and the arm are OUTSIDE the grip.** On the turntable the grip is
  the top row alone (`.pl-sheet-grip.app-grip-top`, `flex: none`), and `<Turntable>` is drawn after
  the grip closes, as the grip's sibling - so neither starts the sheet's drag and the sheet's drag
  never starts from them, with no stopPropagation to forget. On the cover the grip is the top row
  and the cover, as before. `app-rules.sim.cjs` counts the divs to hold it; the turntable sim finds
  no Turntable inside the grip's tree.
- **The record's face is the album's CD art**: deadwax's own `disc.<ext>`, or `disc<N>.<ext>` for
  the playing song's disc (the disc number from the album answer the queue was played from -
  `playedAlbum`, `playingDisc`; 1 when unknown, since a one-disc album deadwax filed carries none),
  else the unnumbered `disc.*`. With none - a 404, or while it loads - plain black vinyl with the
  grooves and the album's COVER as the round label (the board's `discArt=false`). The label hides
  (`has-art`) only once the art has LOADED: CD art is often a transparent PNG, and the cover would
  show through its hole. An image that failed is remembered by ADDRESS, as `Cover` does, so the next
  disc's is still asked for - and only while Now Playing stays open: **each opening asks again**
  (an effect on `open`, not on mounting - with the setting on Turntable the turntable stays mounted
  across a close, and a failure kept by the mount alone made "close and open it again" in the docs
  untrue and latched a Navidrome blip until the look was switched twice).
  - **Only the `disc` stem, never a download's `cd.jpg`** (`disc_face` in src/disc_art.py): that is
    whatever its sharer scanned, and Get CD art is still offered beside it (a `cd*` file doesn't
    hide the button) - so the face is what Get CD art gives, and nothing else.
- **The route: `GET /deadwax/library/disc_art/navidrome?album=<Navidrome album id>&disc=<n>`**, with
  the library routes - NOT a Navidrome relay, and `test_there_is_no_general_proxy` is unchanged.
  The phone knows only Navidrome's id, so deadwax finds the file: getAlbum's `musicBrainzId` (the
  `musicbrainz_albumid` tag as Navidrome read it) through the internal `navidrome.call()`, as
  album_context.py calls it; every live folder the store index has for that release
  (`store.index_present` - two or more for a set stored one folder per disc, so disc N's own
  picture in any of them beats a shared one in an earlier one); and the picture from each folder's
  own listing. The id is only ever Navidrome's `id` parameter, never joined onto a path. Every guard
  `/disc_art` has - each folder `is_within` the library, resolved (a symlink out is refused), and
  only names `find_disc_art` counts, found in the listing - plus one: the chosen file must resolve
  inside its folder. **A folder the index has that is simply gone** (renamed or deleted outside
  deadwax, before a scan noticed) is NOT a refusal: the paths are deadwax's own index, never the
  caller's, and warning of one "outside the library" (as the first cut did, on every showing) sent
  whoever read the log hunting for a traversal. It is logged at debug and marked `missing`, as
  `held_copy` marks one (the next scan, or the folder coming back, revives it); only a folder that
  resolves OUTSIDE the library is warned of. **`/disc_art` itself follows a symlinked FILE out of the folder** (`_listed`
  takes `is_file()`, which follows links) - noticed here, a gap main has too, left for main per
  "a bug main has too is fixed on main first". Served by the same `_disc_art_answer` (typed by
  extension, `private, max-age=300`), and a media answer: `MEDIA_PATHS` in app.py (GuardMedia's
  headers, never gzipped). **404 for every "none"**: no LIBRARY_PATH, Navidrome unset or down or not
  knowing the album (a NavidromeError is caught), no release id, nothing indexed, no CD art - the
  page draws the plain record. A 404 carries no caching, so CD art saved meanwhile shows the next
  time Now Playing opens on the turntable (or the look is switched to it).
- **The drawing and the maths are one set of numbers** (`lib/turntable.ts`, pure): the board's
  geometry in the plinth's units (`STAGE` 372 x 368, `RECORD`, `PLATTER`, `GROOVES` 148 -> 64,
  `ARM` pivot and reach 205, `ARM_PARTS`), drawn as percentages inline and as two SVGs on the same
  viewBox (the platter under the record; the arm over it, `pointer-events: none`), with the record
  a real `<button>` and the arm's handle an HTML slider on top. The stage is as big as fits the room
  both ways (`container-type: size` on `.app-tt`, `min(100cqw, 100cqh * aspect, 440px)`, the aspect
  inline from `STAGE`), the width alone where container units aren't known.
- **The arm follows the song** (usePosition, like the scrubber - no timer of its own): the needle is
  where a circle of the groove's radius round the record's centre meets the arm's reach round its
  pivot (`needleAt`), about 99 to 122.5 degrees across a song. **Dragged, the angle says the time**
  (`armTimeAt`), held to the arm's sweep - past either end is the song's start or end, never the
  circle's far side where the reach meets the grooves again. The head lifts while held. **Nothing
  moves until the finger has travelled `TAP_SLOP_PX`**: the needle stays over the song as it plays
  (`time: null`), so a nudge shows nothing it won't go to. The first cut previewed the arm from the
  first move and seeked only past the slop - and the whole song is about 83 CSS px of needle on a
  390px phone, so 8px was 40 seconds shown and then silently dropped, the arm snapping back. **The
  move that crosses it takes hold** (`grab`): the song where it is THEN is put at the slop's edge
  along the finger's way, so the arm moves on from the song with no jump - not the 40 s a grab
  from the press would jump, and not losing the tens of px a quick finger's first move can cover
  (a grab at the crossing finger would). From there it keeps that grab, so it never jumps to the
  finger either.
- **Turning the record: 1.8 s a turn** (`SECONDS_PER_TURN`, 33 1/3 rpm), forwards clockwise and
  backwards too; each move's turn is the short way round (the atan2 seam at the left is a small
  turn, not a whole one); nothing counts inside `SPINDLE_SHARE` of the centre, where the angle
  swings wildly. The record turns with the hand (an inline rotate on `.app-tt-turn`, kept where the
  hand left it on release) around the CSS spin. **A turn is an OFFSET** (`offset`, seconds) **from
  wherever the song is when it lets go**, because the song PLAYS ON under the finger - only the
  record stops. The board anchored to the time at the press, which works on the board because its
  clock stops while the record is held; here it seeked back behind what was playing - three
  seconds for a finger that rested three seconds before turning, and short of the song for any
  forward turn slower than 33 1/3 rpm, which is most of them. The offset is clamped at each move
  against the song as it is then (turning back past 0:00 holds it there, and forward moves it at
  once - the board's behaviour).
- **Letting go seeks exactly what is shown**: `dragEnd` seeks `shownTime(preview(drag), position)`,
  the same sum the arm and the time line draw, from the song's position as last drawn
  (`drawnAt`, the render's usePosition). A record turned by nothing (round the spindle, or dragged
  straight out) seeks nowhere. **A drag is measured in the stage's box as the press found it**
  (`pressBox`): anything that moves the layout under a still finger moves nothing.
- **Seek on RELEASE only** (and, since 2.0.0-player.14, as a tap's pause winds down - to where it stops), through the player's own `seek` (the scrubber's path): the drag previews
  the time (the time line, "Scrubbing · 2:31 of 7:05" or "Needle up · ...") and turns the record,
  and the audio does not scrub - that is a later slice. Keys on the arm step as the scrubber's
  (`keyTarget`). A cancel seeks nowhere and a drag begun on a song that has since changed is
  dropped (`dragEnd`/`dragFor`); another finger moves and ends nothing (`recordMove`/`armMove`/
  `dragEnd` compare pointer ids) and STARTS nothing - `recordStart`/`armStart` take any pointer, so
  that rule is the component's (`pressable`: `isPrimary`, and no right-click). Both drags capture
  the pointer. `app-rules.sim.cjs` holds `player.seek` to `onRelease` and `onArmKey` alone.
- **A tap plays or pauses, from the CLICK, in the tap** - the transport's way, and the one new file
  on `app-rules.sim.cjs`'s allowlist (`player/Turntable.tsx: toggle`). A press that never travels
  `TAP_SLOP_PX` (8, the furthest it got, not where it ended) is a tap: it seeks nothing. A press that
  does is a drag, and the click after it is NOT a tap (`turned`). **The flag is set by the MOVE that
  takes a turn past the slop**, not only by its release: a drag dropped because the song changed
  under it has no release that says so, and a mouse's click still comes (Chromium sends it to the
  element holding the pointer) - so the first cut paused the new song. **It is cleared by the next
  primary press**, because not every drag has a click after it (WebKit synthesises none after a
  moved touch): cleared only by a click, it would swallow the next real tap. A second finger is no
  press, and doesn't clear it.
- **No per-frame work while the page is hidden.** (2.0.0-player.14 turned the platter frame by frame
  in player/deck.ts instead, under the same rule - no frame while closed or hidden.) The spin is a CSS animation on `.app-tt-face`,
  `animation-play-state: paused` unless `is-spinning`, which is `spinning()`: playing AND Now
  Playing open AND the page showing (`useVisible`, on `visibilitychange` - a locked phone) AND no
  finger holding the record. Paused, it stays where it is. Nothing runs from the engine's clock and
  there is no rAF loop (the sim fails on rAF, setInterval or setTimeout in Turntable.tsx). Reduced
  motion: `animation: none`. **`--dw-record-turn: 1.8s` is its own token**, never a section 7
  duration: reduced motion collapses those to 1ms, which would spin the record 1800 times faster
  instead of stopping it (theme.css's universal rule also clamps any animation to 1ms and one
  iteration). The sim holds the token to `SECONDS_PER_TURN`.
- **The time line replaces the scrubber** (`TurntableTime`, mono, centred, one `nowrap` line - the
  body sits against the bottom, so its height must not change), the title and album line centred as
  the board sets them; the transport and the icon row are the cover look's. Now Playing holds the
  preview (`onPreview`), which Turntable clears as it unmounts (pinned: unmounted mid-drag, the last
  word is null). **The failure line is laid over the plinth's foot on the turntable**
  (`.app-is-turntable .pl-sheet-error`: absolute above the title, two lines at most,
  `pointer-events: none`). In the flow, above the title, it took its height from `.app-tt`, and the
  stage (`100cqh`) shrank with it - on any height-limited phone (375x667, Safari with its bars, on
  its side) the record and the arm resized and moved when the skipped-song note came or cleared
  itself, and a finger holding the arm jumped about 14% of the song. On the cover that room is the
  cover, which no finger goes to; here it is controls.
- **The arm's handle is a tap target unless the plinth is too small to hold one**:
  `min-width: min(var(--pl-hit), var(--app-tt-handle-cap))`, the cap 30% of the stage. On a phone on
  its side (844x390) the plinth is about 45px and a 44px ring covered 52-85% of the record, its
  middle included: a tap there neither paused nor played, and a small turn dragged the arm and
  seeked minutes away. The cap bites only below a 147px plinth. A real landscape layout is still
  not built.
- **Accessibility**: the record is a `<button>` named for what a tap does ("The record: a tap pauses
  the song" / "plays"), Enter and Space included; the arm's handle is `role="slider"` with the
  scrubber's value and words, out of the tab order and disabled with no length; the look button is
  named for the look it switches to; You's radio group is described by the note under it
  (`app-look-note`: the button switches only until Now Playing closes - why the two can disagree),
  as Gapless is by its own.
- **No hint and no coach mark** (James, above): the board's `firstTime` tweak is not built, and the
  sim fails on its words.
- **Deliberately left out**: audible scrubbing (a later slice - built in 2.0.0-player.14); the desktop (James: phone only - the
  app has one layout until slice 8's desktop frame, which is where the button stays out); the
  board's Lyrics and Up next icons, as on the cover.
- **Verified**: 1853 Python tests (`test_turntable_disc_art.py` new: found for disc 1 and 2 of a set,
  the shared fallback, a one-disc album with no disc number, a set stored per disc, a `cd.jpg`
  refused, every 404, the id only ever Navidrome's, a folder and a file linking out refused and
  warned of, a folder gone since the last scan quiet and tombstoned, served as `/disc_art` serves
  one; four new CSS tests), pyflakes, tsc, and all 26 sims (`turntable` new, 127 checks;
  `settings`, `you`, `info` and `app-rules` extended); 51 mutations, one per rule pinned, each
  caught and restored byte for byte - and after the review, 20 more for its fixes (the arm's slop
  and its grab, the record's offset, the flag set on the move, the art asked for on opening, the
  quiet tombstone, the overlaid failure line, the handle's cap, the look note, the arm's capture,
  a second finger, the preview cleared on unmount, the press's box), all caught. The engine guard
  is empty and `player.sim.cjs` untouched.
  **NOT verified here**: the real page (the build workaround and a check against the stubs come
  after this change) and everything on the iPhone - the drags under a real finger with the sheet
  staying put, the spin's smoothness and its stopping while locked, whether VoiceOver drives the
  arm, and whether Navidrome 0.64.2 sends the album's `musicBrainzId` for James's albums (Info >
  Debug's Navidrome sent row answers that).

### The turntable, part two: momentum and its own sound (2.0.0-player.14)

James, on the turntable of 2.0.0-player.11: "can we add momentum to the disc as well?", then "And the
audio will speed up and slow down with it?". Agreed with him: a flick keeps the record turning and it
coasts; the platter spins up and down on play and pause like a real deck; the sound follows the hand
and the coast, backwards too; a pause on the turntable winds the sound down over about a second, with
a switch in You to turn that off. The cover look is unchanged - its pause instant, nothing of this
running while it shows. PHONE ONLY, like the turntable. The spec is the session scratchpad's
`uplan/slice-turntable2.md`.

- **A SEPARATE SOUND PATH, and why.** The player's own audio element is NEVER connected to Web Audio
  and never touched by any of this but through the player's own actions: Turntable's `holdSong` and
  `resumeSong` (the player's toggle) and its seeks of what the deck returns. `createMediaElementSource`
  is what breaks locked playback on an iPhone (the audio-fidelity memory note), and normal playback
  had to stay exactly what it was. So the record's sound is its own: a decoded WINDOW of the song
  round the playhead, read by an AudioWorklet (`lib/deckVoice.ts`; since 2.0.0-player.16, on a page
  with no AudioWorklet, a ScriptProcessorNode running the same functions - see "After James's report")
  on an AudioContext of its own
  (`player/deck.ts`), and used only while the record is not at its own speed - under the hand, coasting,
  winding down. `app-rules.sim.cjs` holds `deck.ts`, `deckVoice.ts` and `Turntable.tsx` to touching no
  media element at all (no createMediaElementSource, no element looked up, nothing set, loaded, played
  or paused on one) and the deck to calling no playback action.
- **The voice** (`lib/deckVoice.ts`, pure): reads the window at a SIGNED, fractional rate with
  four-point (Catmull-Rom) interpolation (a windowed sinc since 2.0.0-player.29 - "A digital artifact on
  top") - 1 the song, 0 silence, negative backwards - steering towards
  a position and a rate the deck posts each frame (`drive`: where the record is, how fast, and for a
  coast how fast that changes, `accel`, so it follows a curve between frames). (**Corrected by
  2.0.0-player.24**: that was the HAND's sound too, one drive a frame, each stamped with a fresh
  `currentTime` - which steps - and the hand's speed taken at the frame's time: the warble James heard.
  Since then a hand's samples go to the voice as they come, with their own times, every time it is told
  is mapped by one smooth clock, and it plays the path through them HAND_DELAY_S behind - see "The
  record's sound follows the hand". A coast's drives are still a frame apart.) The rate is smoothed per
  sample (SMOOTH_S 10 ms) and the steering is FOLLOW_S 40 ms, critically damped together, so what is
  heard stays within about a millisecond of real time of where the platter is (the sim measures it at
  four speeds; since 2.0.0-player.24 of where it was HAND_DELAY_S before - coasts, the motor and the
  wind-down are played the delay behind, like the hand). A drive runs out by itself (`until`, DRIVE_FOR_S 0.12 s): a stalled page never leaves
  a record whirring. A DC blocker at 10 Hz makes a record held still silent (it reads one sample over
  and over), fades at the window's edges and on take/fade/stop keep it from clicking; and since
  2.0.0-player.35 a lookahead peak limiter at its end keeps every sample under -0.5 dBFS ("The record's
  sound never clips" - its ceiling and lookahead literals in renderVoice, `VOICE_CEILING` and
  `VOICE_LOOKAHEAD_S` outside, held equal by limiter.sim). Its three
  functions (four since 2.0.0-player.16, with `voiceReport`) are SELF-CONTAINED - no imports, no module
  constants, nor one another - because the worklet module is made
  from their own `toString()` (`voiceWorkletSource()`, loaded from a Blob URL): a worklet runs in a scope
  of its own. A minified rolldown build of it was run in a fake worklet scope and plays (checked once,
  not in CI; again for .16's four - `deckVoice.ts` alone through rolldown, minified: its module played
  the same samples as its functions, with 32 reports in 400 blocks); `deck.sim.cjs` runs the module as
  the browser would and holds it sample for sample to the functions. It reports where it is 30 times a second (exactly: the count carries its remainder -
  `voiceReport`, shared by both hosts since 2.0.0-player.16), and the
  needle and time line show that - extrapolated - while it sounds.
- **The physics** (`lib/platter.ts`, pure): speeds in the platter's own (1 = 33 1/3 rpm = the rate the
  voice reads at, `voiceRate`), positions in song seconds. Free: friction, a constant part and a part
  that grows with the speed (FRICTION_DRY, FRICTION_VISCOUS), set so speed 1 stops in SPIN_DOWN_S
  (1 s, the wind-down) and a flick of 9 (five turns a second) coasts about 1.8 s. The motor: a constant
  pull from still up to speed (MOTOR_PULL, still to speed in SPIN_UP_S 0.4 s), braking above it (the
  pull and friction's speed part), and BACKWARDS the pull and the whole of friction together, a decay
  to still before the pull up - so a hard flick back (-9) is stopped in 0.86 s, as a forward one is
  braked in 0.84 (until review it had the pull alone: 3.6 s backwards, 16 s of the song rewound, longer
  than the same flick coasts with the motor off). Each phase has an exact answer, so where a coast lands and where a playing song is when the
  motor has it back at speed are known AT THE RELEASE (`coast`, `motor`); `deck.sim.cjs` integrates the
  same equations (`acceleration`) step by step for 54 flicks and holds every landing and every time to
  within a millisecond. A coast back past the start stops there; on past the end stops END_MARGIN_S
  (0.25 s) short and the song ends from there; a motor run back to the start spins up from it. The
  hand's speed is over its last VELOCITY_WINDOW_MS (90) ending at the RELEASE, so a finger that rested
  has none (`handSpeed`), held to MAX_SPEED (24). (Since 2.0.0-player.24 it ends at the LAST SAMPLE, by
  the samples' own times - the frame between the last move and the lift read as a third slower - with a
  rest past RELEASE_TAIL_MS taking it down in proportion, to none at a whole window: `releaseSpeed`.)
- **The window, and where it comes from** - option (a) of the spec, a server route:
  `GET /deadwax/navidrome/scrub/{song_id}?at=&seconds=` (`answer_window()` in player_cache.py, cut by the
  new pure `src/flac_window.py`). A STANDALONE FLAC of the frames covering the stretch: 'fLaC', STREAMINFO
  alone and rewritten (total samples, its frames' smallest and largest sizes, MD5 zeroed; the song's block
  sizes, rate, channels, depth), the frames untouched and RENUMBERED from 0 - frame numbers, or sample
  numbers in a variable-block stream - each header's CRC-8 and each frame's CRC-16 made again. The CRC-16
  is carried over by arithmetic, not summed again: FLAC's is linear (zero start, nothing reflected), so a
  new header changes it by an amount that depends only on the two headers and the length after them
  (`_crc16_after`, multiplication by x^(8n) mod the polynomial) - 4 ms for 330 frames where re-summing in
  Python would be a quarter of a second. Renumbered because deadwax's own `find_frames()` refuses a first
  frame that isn't 0 and Apple's decoder wasn't known; macOS's AudioToolbox (afconvert - the family an
  iPhone's decodeAudioData is) turned out to decode both the renumbered window and one with the song's
  own numbers bit-exactly, as did libFLAC and ffmpeg (measured, not in CI; libFLAC is in the tests where
  `flac` is installed). It is cut from the copy of the song the PAGE PLAYS, from whichever MP4 of it the
  cache holds - Safari's plain one (its sample tables give every frame) or the gapless player's
  fragmented one (its sidx gives every fragment, a fragment's trun its frames): with `max_rate=48000` -
  which the page sends exactly when streamUrl() and fragmentedUrl() would (`resamples()`, Turntable's
  host `maxRate`) - the RESAMPLED copy, under the plan's key, the plan a neighbour-less make was kept
  under (`_lost_side`), or a fragmented MP4 this URL was served (`_pinned`), so its frames are what the
  phone hears: 48 kHz and HEADROOM_DB lower, the same level as the song; with none of those, the
  resampled plain MP4 made as Safari's would be; refused resampled (the page then plays it as it is),
  the song as it is. Without `max_rate` (or no audio libraries), the song as it is the same way. So an
  iPhone's songs cost nothing to make again. (Since 2.0.0-player.23 the song as it is with no MP4 held
  is cut straight from the FLAC by ranges, nothing made - see "Windows cut straight from the FLAC" - and
  a song too big to hold has its windows cut that way too; the plain MP4 is made, and the 415 for one
  too big given, only where the FLAC can't be cut by ranges.) (Review: the first cut looked only for the song as it is,
  so under the default "Up to 48 kHz" every hi-res window downloaded the whole original again, kept a
  second full-size copy beside the phone's, and sounded 3 dB louder than the song.)
  `X-Deadwax-Window: <first sample>/<samples>/<rate>` says exactly where it sits (it starts on a frame or
  fragment at or before `at`). WINDOW_MAX_BYTES (8 MiB) bar the frame `at` falls in: 40 s of CD audio
  whole, about 13 s of 24/192 as it is. Only `at` (0 to a day), `seconds` (1-60, default 30) and
  `max_rate` (48000 or nothing, as the stream's) - anything else a 422, as out of bounds is; 415 for a
  song that isn't a FLAC ("it isn't a FLAC file", the cache's own words) - and, only for a window that
  falls back from the FLAC path to the MP4 (since 2.0.0-player.23, "Windows cut straight from the
  FLAC"), for one too big to hold (WRAP_MAX_BYTES, judged before the song is fetched whole - `_mp4()`
  holds no cap itself, each caller does) or whose MP4 was refused, the windows the FLAC path can cut
  being 200s for either; 416 past the end; 503 with `scope` when the cache can't. A media path
  (`MEDIA_PREFIXES`): never gzipped, under GuardMedia. On the fixed route list ON PURPOSE (`test_there_is_no_general_proxy` and its
  copy in test_turntable_disc_art.py edited); like the stream's wrap paths it asks Navidrome through the
  cache's own client, so step 6 checks a user's access at the route (`test_every_navidrome_route_asks_
  through_client_for` counts it). MP3 is NOT given a window (the spec's "can"): its time can't be placed
  without an ID3 size and a Xing table - a VBR MP3 lands seconds off - so non-FLAC songs are silent on the
  turntable (and since 2.0.0-player.16 have no momentum either: a press is .11's) and Debug says why. No server setting.
- **Kept ready while the turntable shows and the song plays** - once a tap has started the sound: no window
  is asked for without an audio context and a voice ready to put it in (`keep()`: the worklet, or since
  2.0.0-player.16 the script voice once it has played a block), since a window that can't
  be decoded is only fetched again (review: with no context - Now Playing opened onto the turntable from
  the mini player - it fetched a fresh 40 s window every 2 s; with the worklet failed it did the same and
  decoded each). `onAudio` asks once there is somewhere to put it. WINDOW_S (40) from WINDOW_BACK_S (4)
  before the playhead, on a WINDOW_GRID_S (2) grid so the phone's cache (`private, max-age=300`) answers a
  window asked again, refreshed once the playhead is within REFRESH_AHEAD_S (6) of its end (6 s of listening:
  faster than 1x, that times the speed - see "The speed fader (2.0.0-player.39)"), and fetched on
  demand when a hand or a coast goes outside it - and AT THE RELEASE over the whole of where a coast will go
  (`keepPath`: a backwards flick runs back past the window's start, and a sounding coast used to go silent
  there). ONE window is on its way at a time, from the ask until it is in the voice (`pending`, 'fetch'
  then 'held' while it decodes), so nothing asks for it again meanwhile; only the newest decode is handed
  on (`decodes`, a latestOnly); a hide lets go of a window still being fetched and keeps one in hand. A
  window deadwax cut short (a hi-res song as it is, at WINDOW_MAX_BYTES) shrinks the margins in proportion
  (`windowMargins`: 1.3 and 1.95 s for a 13 s window), so each new one still moves on by about three
  quarters of its length; a refresh ahead of a playhead the window still covers must start further on than
  it, and comes no more often than REFRESH_MIN_MS (3 s - a backstop: the move-on rule stops every loop
  first, so no check can show the floor alone). **Cost**: a window is fetched whole, so 40 s over the 30
  the playhead crosses before the next - a third more than the song's own stream while the turntable shows
  and plays; for a hi-res song played as it is about half as much again (13 s windows: about 7 a minute,
  where the first cut asked 29). At 2x a window moves on by 24 s, not 30 (the margin ahead doubled to keep
  6 s of listening to fetch and decode in): 40/24, two thirds more than the song's own stream. **Measured** with the deck's own rules over the server's real cuts of a generated 4-minute
  CD-quality FLAC (pink noise and a tone, 500 kbps): 6 windows of 2.5 MB in 3 minutes, 5.0 MB a minute
  against the song's own 3.75 (1.33x; 1.36x cut from the fragmented MP4, whose cuts are whole fragments).
  A typical 900 kbps CD FLAC would be about 9 MB a minute. Info > Debug's row says what windows have cost
  since the turntable showed - how to read it off the phone. A failure is asked again after RETRY_MS (10 s); a 415 or a window the
  browser couldn't decode is never asked again for that song.
- **The audio context, only from a gesture** (WebKit counts click, pointerup and keyup - not pointerdown):
  `wakeDeckAudio()` makes it (once) and resumes it, from the record's click and release, the transport's
  three buttons and the look button switching TO the turntable - and, since 2.0.0-player.30, the mini
  player's tap when Now Playing opens as the turntable; `resumeDeckAudio()` resumes one that
  exists, from that tap otherwise (App's openSheet). `app-rules.sim.cjs` pins
  exactly those call sites by the handler each is in, and that the context is constructed only inside
  wakeDeckAudio. Suspended when the screen closes or the page hides - nothing of it runs on a locked
  phone - and closed when the turntable unmounts (the look switched to the cover). Never resumed without
  a gesture, so after a hide the next tap brings it back. Until it runs - since 2.0.0-player.16, until the
  record can SOUND where it is (a voice ready and a window there in it) - a press is EXACTLY 2.0.0-player.11's
  (`deck.live()` false at the press: silent, the song playing on under the finger, moved where it lets go,
  no momentum - and the record STOPPED under the finger, `deck.holdStill()`, as .11's paused CSS spin was;
  review: the first cut left the deck turning the face under a still finger) - the spec's "until it is
  running a press scrubs silently, exactly as .11 does".
- **What the hand does, live** (`Deck`): a press lets the song play on for a moment, so a tap is still a
  tap (play/pause from the click). The record is TAKEN as the press moves past TAP_SLOP_PX or rests longer
  than HOLD_MS (250): a playing song pauses (`holdSong`), the record's sound takes over at its position at
  speed 1 (or 0 if paused) and follows the hand - silent when it rests; the hand's turn counts from where
  it was taken (`anchor`), the click after it is no tap. A press on a coasting or winding-down record is
  also a possible tap (a quick double-tap pause-play works); taken, it is caught where the platter is.
  RELEASE (`release()`): the hand's speed becomes the platter's. A song that was playing: the motor plan;
  Turntable SEEKS AT THE RELEASE to where the platter will be at speed; at speed (a timer, not the frame
  loop, so a hidden page still gets there) `resumeSong` plays it, and the voice holds speed 1 until the
  song's own position has moved past that point (`onPosition`), then fades over HANDOVER_FADE_S (40 ms) -
  HANDOVER_MAX_S (3 s) at most. **Expect a short repeat at the handover**: the element starts where it was
  sought, while the record's sound has run on by the element's start-up latency; the spec accepts it.
  (Since 2.0.0-player.24 the record's sound is HAND_DELAY_S behind the platter, so the repeat is that
  latency less 50 ms - an overlap while it fades, if the element starts sooner. And a release that plays
  in its own gesture stops the record's sound in it, so that last 50 ms of the hand, 93 on plain http,
  is heard by neither - see "The record's sound follows the hand", E.) A
  coast back to speed of RESUME_IN_GESTURE_S (50 ms) or less plays in the release's own gesture. A song that
  was paused: the coast plan, sought at the release to where it stops, staying paused. A cancel drops it and
  seeks nowhere - a song it paused plays on (`resumeSong`, outside a gesture). A song change drops a press,
  a coast and the window, seeking nothing - and when the hand had taken the song from PLAYING (a press, or a
  coast back to speed: `meantToPlay`), the next song is played (`resumeSong`): usePlayer loads it paused,
  since the hand's pause cleared intendsToPlay, and the hand only scrubbed. Played SONG_CHANGE_SETTLE_MS
  (300 ms) later, and only if nothing has played it meanwhile: a song started some other way in that
  moment (a tap in Search) has its own play under way, and the player's `playing` follows the element's
  'play' a moment after - an immediate toggle would have paused it. A tap in that moment owns the play
  (`resuming()` and `pausing()` cancel the timer), and a press takes the song as meant to play. The turntable going mid-coast
  (the look switched to the cover: `destroy`) plays the song on from where the release sought it, the same
  way. The turntable mounting on the song already playing is no change (`songChanged` compares ids), so the
  window it began asking for isn't superseded and asked again. The arm, or the song sought by anything
  else meanwhile (a position more than SOUGHT_ELSEWHERE_S, 0.75 s, from where the deck had it sought:
  Previous restarting it, a key on the arm), makes the rest of a coast, run back to speed or wind-down
  QUIET (`quieten`): no sound, nothing shown, the arm's preview the time line's while it is held - and the
  handover's sound never holds speed 1 over a song playing from somewhere else (review: Previous mid-coast
  played two parts of the song together for 3 s). A coast back to speed still plays the song when it gets
  there, from wherever that put it.
- **That play() comes after the tap**, on an element a tap already started; usePlayer.ts's header says iOS
  allows it. If WebKit refuses, usePlayer's own refusal path says "Tap play to start" and the song stays
  paused where it was sought - and HANDOVER_MAX_S after it the platter spins down (planEnded's timer),
  rather than turning on beside a paused song - the fallback, unverified until James's iPhone says.
- **Pause on the turntable** (`pausing()`, from the record's tap and the transport's pause on this look) with
  "Pause winds the record down" on, the window covering the playhead and the voice ready: the song pauses in
  the tap as ever, the record's sound starts there at the SONG's own speed - what was heard, whatever the
  platter's 0.4 s spin-up had reached (review: it started at the platter's, an octave down mid spin-up) -
  and winds down with it over about a second (friction's braking curve - exponential with a constant part,
  not linear), and the song is SOUGHT to where the wind-down stops, so play carries on from there rather
  than repeating 0.3 s. A play in the tap while the record still coasts or winds down with its sound is
  sought first to where the record is (`resuming()`, from the record's tap and the transport's play), so
  nothing heard is skipped (review: it skipped up to 0.3 s, seconds after a hard coast). Otherwise a plain
  pause: nothing sought, never a wait - the platter still spins down visually. The lock screen's pause, the
  cover's and a song ending never wind down (only those two callers ask). Play: the toggle in the tap as
  ever; the platter spins up over 0.4 s - the sound starts as it always has (an audible spin-up would need
  play() after the tap; not in this slice).
- **The platter is turned by the deck**, frame by frame (requestAnimationFrame), writing the face's
  transform straight onto the element (never a render, never a style in Turntable's JSX): 33 1/3 rpm
  (DEGREES_PER_SECOND 200) while playing, the plans' angles while coasting, held while a hand has it (the
  hand's own turn stays on the wrapper as in .11). It stops when nothing moves, when Now Playing closes and
  when the page hides; a pause the deck didn't ask for (a song ending, the lock screen) spins it down only
  after PAUSE_SETTLE_MS (300), since a song change pauses for a moment. The CSS spin and `--dw-record-turn`
  are gone (test_app_css holds both gone). Reduced motion (`matchMedia`, read by the deck): it doesn't turn
  at all, a release lands at once - a playing song played in the release's own gesture - and nothing winds
  down; scrubbing under the hand still sounds.
- **The setting**: You > Playback's "Pause winds the record down" (`app/WindDownChoice.tsx`), a checkbox,
  on by default, beside "Now Playing opens as", with a note saying it is the turntable's only. App keeps it
  (`deadwax-player-wind-down`, `readPlayerWindDown`: off only when it says exactly 'off') and hands it to You
  and Now Playing. It governs the SOUND; the platter's visual spin-down is the deck's either way.
- **Info > Debug's "Turntable sound"** (`turntableRow` in debugRows.ts, a new section "The turntable"): ready,
  "0:42-1:22, FLAC, decoded at 48 kHz", or off and why - the turntable isn't showing; no Web Audio; no
  AudioWorklet (since 2.0.0-player.16: nothing to play it on, and the note names the voice); the sound
  couldn't start (the browser's words); "it isn't a FLAC file (it is MP3)" or
  deadwax's 415; "this browser couldn't decode its window - <its words>"; waiting for a tap to start the
  sound; deadwax didn't send it; past the end; loading; no window yet. A note with what windows have cost
  since the turntable showed, and when the last of them came (`lastFetchAt`: the report is made as things
  change, not as time passes, so that is the time the bytes are measured to - review: it read "fetched in
  0:00" for the first half minute). App is told of report changes (`onDeckReport`), never a frame at a
  time. This row is how James tells us what WebKit does.
- **NOT verified - until James's iPhone says**: that WebKit decodes the window (decodeAudioData on iOS -
  AudioToolbox on a Mac does); that an AudioWorklet from a Blob URL loads in the home-screen app; the
  out-of-tap play() at speed (and the "Tap play to start" fallback if refused); that the record's sound is
  heard with the ringer switch on silent (iOS has muted Web Audio there unless a media element plays - it
  is paused under the hand); that suspending the context leaves locked playback, the lock screen's
  controls and AirPods as they were; the feel of the physics under a real finger; and the bytes a minute
  over WireGuard. Nor the real page, which the orchestrator checks after this change.
- **Verified**: 1998 Python tests (76 in `test_scrub_window.py`: the coding of numbers, the carried
  CRC-16 against a re-sum, renumbering by frame and by sample, STREAMINFO rewritten, windows from both
  kinds of MP4 covering what was asked from a boundary, the budget, past the end, a foreign layout refused,
  libFLAC decoding a window to the song's own samples, and through `start()`: audio/flac never gzipped
  under the media headers, Safari's and the gapless player's MP4s cut from with nothing made, the plain one
  made once, a resampled song's window cut from the phone's resampled copy - either kind, or the one kept
  without a neighbour - with nothing downloaded, made resampled when there is none, the song as it is when
  that is refused or there are no audio libraries, the cap's 415 with nothing fetched, a refused MP4's
  415, 416/422/503); pyflakes; tsc; all 32 sims (`deck` new, 159 checks; `turntable` 167, `app-rules` 106,
  `settings` 61, `debug` 79, `info` 85, `you` 23 extended). Mutations, each restored byte for byte - one per
  rule the build made (79: 74 caught at once, four gained tests, one backed up by another) and one per rule
  the review's fixes made (41, server and page: 35 caught at once; four first got past and gained checks -
  a resampled make refused as it is tried falling back, a refresh that must move on (windows of 2 s),
  `resuming()` claiming its own seek, and a paused coast's window asked at the release; two are backed up
  by another layer: the refresh floor behind the move-on rule, and Turntable's arm-wins preview behind the
  deck going quiet as the arm is taken).
  Not every documented rule has its own check - the 3 s floor above has none that could show it alone. The
  engine guard is empty and `player.sim.cjs` untouched.

#### After review (2.0.0-player.14)

A review of the build found these, each confirmed by reproducing it against the real code, and each
fixed with a check that fails without the fix (the bullets above say the rules as they now are):

- **Windows fetched over and over** - with no audio context (the common first open, from the mini
  player, onto the turntable), with the worklet failed, and while a decode ran: the keeper counted a
  window only once it was IN the worklet. Now one is on its way from the ask to the worklet, nothing is
  asked without a worklet to put it in, and only the newest decode counts.
- **A hi-res song**: the server ignored the phone's resampled copy, downloaded the whole original again
  for the first window and kept a second full-size copy, cut 192 kHz windows 3 dB louder than the song,
  and the page re-fetched its 13 s windows 29 times a minute (about 230 MB). Now `max_rate` and the copy
  the page plays, and margins that shrink with a short window.
- **A sounding coast never asked for the window it ran into**, so backwards flicks went silent: now
  asked at the release, over the whole coast.
- **The motor ran a backwards flick back for seconds** (the pull alone, no friction): now both.
- **Outside the deck during a coast back to speed**: Next loaded the next song paused, switching to the
  cover left the song paused, Previous (restart) or a key on the arm played two parts at once for 3 s,
  and a refused play() left the platter turning beside a paused song.
- **The record turned under a still finger** before the sound ran: .11 stopped it.
- **The arm during a coast**: the needle and the time line followed the coast, not the finger.
- **The wind-down** started at the platter's spin-up speed, and a play mid wind-down skipped what was
  heard.
- **Debug's cost** read a time frozen at the last report: now named as the last window's.
- **Tests that could not fail**: the switch-off check (a zero-length wind-down made it pass whatever the
  setting) and the rested release's value (compared with itself) - both now hold a real value, with a
  control; and the deck's documented rules that no check held (the 10 s retry, a decode refused in three
  ways, nothing fetched for a paused song, a coast caught on its way back to speed, a pause near the
  window's end, RESUME_IN_GESTURE_S, PAUSE_SETTLE_MS), the route's cap and refused-MP4 415s, and the
  cover's previous and next waking nothing.
- **Not changed**: an outside PAUSE during a coast back to speed (a headset sending 'pause' to an element
  already paused) is invisible to the deck - no event fires, and seeing it would need the engine - so the
  coast still plays the song at speed. Rare: the lock screen and AirPods offer play then, as the Media
  Session says paused.

#### After James's report (2.0.0-player.16)

James, on his iPhone and then his Mac: "the audio doesn't follow the turntable when scrubbing", "it
doesn't work on my mac either". A fix to .14, not a feature; the spec is the session scratchpad's
`uplan/slice-turntable-fix.md`.

- **The cause, reproduced before anything changed.** `BaseAudioContext.audioWorklet` is a
  [SecureContext] API: a browser exposes it only on HTTPS or localhost, and James opens deadwax at a
  plain `http://` address on his network. So the worklet was never there, deck.ts set
  `missing = 'no-worklet'` and made no voice - and `Deck.live()` was only "the context runs", so a
  press still TOOK the record and paused the song, with nothing to sound: silence under the hand, the
  song back on release. Reproduced in headless Brave by loading the app as `http://deadwax.test:8081`
  (`--host-resolver-rules=MAP deadwax.test 127.0.0.1`); over `http://localhost` every check passes,
  which is why .14's verification never saw it. **The review of .14 raised exactly this** - "a press
  takes the record and pauses the song whenever the context runs, even when the record can't make a
  sound" - and its skeptics dropped it. It was this bug.
- **A second host for the same voice.** Where the context has no `audioWorklet` (or no
  `AudioWorkletNode`), or the worklet can't be made (the Blob URL), won't load (`addModule` refused)
  or its node won't construct, the deck makes a **ScriptProcessorNode** instead
  (`startScript`: `createScriptProcessor(SCRIPT_BUFFER 1024, 0, 2)`, to the destination) that runs
  THE SAME four functions of `lib/deckVoice.ts` on the main thread - `newVoiceState`, `voiceCommand`
  (each message applied to its state - held to the next block, see below), `renderVoice` and the new
  `voiceReport`. `voiceReport` is the worklet's report count moved out of its source string into a
  fourth self-contained function (the counter is `VoiceState.counted`), so both hosts say where they
  are REPORTS_PER_SECOND times a second by one rule. One DSP, two hosts. ScriptProcessorNode is
  deprecated, but it is in every current browser, iOS Safari included, and needs no secure page - which
  is the whole reason it is here; the worklet stays the first choice wherever it exists (its own audio
  thread: a busy page doesn't glitch it). Each block is rendered as of `event.playbackTime` - the
  context time it will play at, a block ahead of `currentTime` as the browser asks for it. A script
  voice is **ready only once it has played its first block**: a browser that never calls it stays not
  ready, and every press stays .11's rather than pausing the song over silence. Debug says "still
  starting" then. The buffer size is 1024 unmeasured on a phone.
  - **How its messages are timed (review of this slice).** The first cut applied each message straight
    to the state as of `currentTime` and rendered at `playbackTime`, a block or two on - and a `take`
    sets the read head, so every take started that far BEHIND the record and the steering raced to
    catch it up: measured with the real functions, 1.39x for one 1024-block's lead, 1.78x for two, for
    20-80 ms - a chirp of 6-10 semitones on every grab of a playing record and at the start of every
    wind-down (on by default), where the worklet's own lead gives 1.05x. "Sounds the same" was false
    on exactly the path James uses. Three parts, none of them a second DSP: (1) `voiceCommand`'s take
    now starts where the record IS as of the `now` it is applied at - `at + rate * (now - time)` - not
    at `at` (its `now` argument was unused; since 2.0.0-player.24, where it was the delay before that:
    `at + rate * (now - delay - time)`); the worklet's own catch-up goes with it. (2) The script
    host HOLDS messages and applies them just before the next block, as of that block's `playbackTime`
    - the moment they are first heard - as the worklet applies each on the audio clock. (3) Every take
    and drive is heard `SCRIPT_LAG_BLOCKS` (2) blocks after it was said, its `time` and `until` both
    moved on by 43 ms: the most a message waits for the block it is first heard in. Without (3) the take
    was placed where the record had got to, and a grab's still hand - whose drives say the record
    stopped where it was taken - then pulled it BACK as far (-0.86x); with it, a take and the drives
    after it keep the spacing they were said with, and the voice plays what the worklet would, 43 ms
    later. Measured in `deck.sim` with frames and blocks on one clock: a wind-down and a grab, each with
    the take's block first and a frame first, never past 1.02x (1.41x before), and a grab's backward
    swing -0.15 at worst. A drive replaces the drive before it in the hold and a window every window
    before it, so a stalled page holds a handful, not a pile. (Since 2.0.0-player.24 a hand's samples
    are held too, shifted by the same lag - and every one is applied, in order, none replacing another:
    each is a knot of the path the voice plays. Since its review the drives are too: a drive that
    replaced the one held before it dropped a knot the worklet kept, so only windows replace windows.
    A stalled page has no frames to make drives anyway.) NOT measured: what a real browser's
    `playbackTime` lead is (Chrome's is a block at the event, by its source; WebKit's is computed the
    same way) - a larger one only skips the first few ms of a take, still without a chirp.
- **`live()` needs the sound** - the context running AND a voice ready (`voiceReady()`) AND a window
  of this song covering where the record is (`recordAt()`: the platter for a coast, a run back to speed
  or a sounding wind-down, else the song - one rule, shared with `takeOver`). Anything less - no voice,
  a worklet still loading, a window still decoding or not yet asked, a refused one, an MP3 - is .11's
  path: the song plays on under the finger and is sought on release, no momentum. So an MP3 lost the
  silent momentum .14 gave it. Windows are asked once a VOICE is ready (`keep()`'s gate is
  `audio.voice?.ready`); the wind-down needs one too (`sounding()` is `voiceReady() && covers`). A
  paused song has no window until the record is turned, and its first press is now .11's - so a press
  the deck doesn't take asks for the window where the record is (`holdStill(true)` calls `keep`; the
  held record counts as busy), and the next press there is the deck's.
  - **Except a coast or a run back to speed (review of this slice).** The first cut judged those by
    the platter too, so once a flick ran it out of the window - a backwards flick past the window's 4 s
    back margin, the next window still being fetched and decoded, which is ordinary flick-and-catch -
    a press went .11's way, and `holdStill` only knew the spin's motions: the coast's timer ran on under
    the still finger (the face leapt up to 417 degrees at the release, the time line froze on the
    coast's last time, a window landing mid-hold sounded a burst of the coast's rate under a still
    hand), and a run back to speed's end PLAYED the song under the held finger. But .11's premise - the
    song plays on under the hand - can't hold there: the flick paused the song already. So `live()` is
    true for a coast or a run back to speed whenever a voice is ready, as .14 had it: `takeOver` catches
    it where the platter is, silently, and `handWindow` sounds it as the window arrives. Only those two
    roles - a wind-down with no sound (an MP3, the setting off) must stay .11's, or an MP3 would get
    silent momentum back. And `holdStill(true)` now ends whatever plan the deck still has when a press
    IS .11's (a silent wind-down; a coast whose context a hide suspended since): `quieten` it, then its
    end at once (`planEnded`) - still where it is held, or, a run back to speed, the song played now
    (.11's song playing on under the finger, from where the release sought it), the sound stopped
    rather than held at speed 1 for it.
  - **The first turn of a paused song before any tap (review).** With no context yet - Now Playing
    opened onto the turntable from the mini player, which only resumes one - the press's `keep` found
    no voice, and by the time the release's `wakeDeckAudio` had one ready, `holdStill(false)` had let
    go of the press: nothing asked, so it took two silent turns, not one, and the docs' "the next turn
    has its sound" was wrong. `keep` now remembers a held press refused for want of a voice
    (`wanted`, the song's id), counts it busy, and asks as soon as `onAudio` has a voice; the first pass
    of the voice gate lets it go, so it is one ask, not a paused song kept in windows.
- **The silent switch** (part three of the spec): while the record's sound plays the song's element
  is paused, and WebKit then gives the page's Web Audio the 'ambient' kind, which an iPhone's ring/
  silent switch mutes. `holdAudioSession()` sets `navigator.audioSession.type = 'playback'` (Safari
  16.4+) as wakeDeckAudio makes the context - in the gesture - and `releaseAudioSession()` puts the
  kind it found back in closeDeckAudio, as the turntable goes; only a kind it really changed is put
  back, and both are guarded (absent elsewhere: nothing; a set that throws: nothing).
  `app-rules.sim.cjs` holds `createScriptProcessor` and `audioSession` to deck.ts alone.
- **A hide while a tap's resume is still settling (review, a nit older than this slice).**
  `sleepDeckAudio` only suspended a context already 'running', and nothing looked again once the
  resume settled, so a tap followed at once by the page hiding left the context running, hidden, until
  the next show and hide - on the script voice that is `renderVoice` and `voiceReport` on the main
  thread ~47 times a second for nothing. A hide that finds the context not running now marks it
  (`sleepOnceRunning`) and `audioChanged` suspends it the moment it runs; a gesture asking for the
  sound (`resumeDeckAudio`, which every wake goes through) and the turntable showing again let the mark
  go - the mini player's tap resumes the context a moment BEFORE the turntable shows, and must not be
  suspended for a hide that came before it.
- **Debug's "Turntable sound"**: the report gained `voice` ('worklet' | 'script' | null) and
  `voiceWhy`; the context state 'no-worklet' became 'no-voice' (neither host). The note names the
  voice - "On its own audio thread (an AudioWorklet)", or "On the main thread - this page isn't on
  HTTPS, so the browser has no AudioWorklet" (or "this browser has no AudioWorklet", or "the
  AudioWorklet wouldn't load (<its words>)") - before the cost. Every way the record can't sound reads
  Off, since a press then is .11's: "Off: still starting - …", "Off: its window is loading - …", "Off:
  no window yet - …" (they were "Starting:", "Loading the sound", "No window yet:").
- **NOT verified - James's iPhone list**: that WebKit calls a ScriptProcessorNode with no inputs
  (if it never does, Debug stays on "still starting" and every press is .11's - say so); the record
  heard over plain http on the phone; that 'playback' keeps the silent switch from muting it; and that
  setting it leaves locked playback, the lock screen's controls and AirPods as they were after a
  scrub. The real page (the orchestrator, from `http://localhost` - worklet - and
  `http://deadwax.test:8081` - script) is checked after this change.
- **Verified**: 2048 Python tests (none new: the change is the page's), pyflakes, tsc, and all 34 sims,
  3232 checks (`deck` 222 - 30 of them from the review, below; before it 192, 33 more than .15: the script voice made where there is no AudioWorklet and where
  `addModule` is refused, its arguments and connection, ready only after a block; its output held
  sample for sample, block by block, to `renderVoice` fed the same messages at each block's
  `playbackTime` through a take, a turn and a flick, with the four functions spied on where deck.js
  reaches them; 32 reports in 50 blocks of 1024 as the worklet's 32 in 400 of 128, each reaching the
  deck; `live()` false with no voice, a worklet loading, a window decoding, outside the window, a
  suspended context, neither host, a paused song, an MP3, a 415 - and judged by the platter on a coast
  (until the review: a coast is the deck's whenever a voice is ready);
  a press the deck doesn't take asking for the window; the audio session set, kept, put back, a stubborn
  one and an absent one; `debug` 84, 5 new and the changed words; `app-rules` 121, one new; `info`'s
  fixture given the new fields). Mutations, each restored byte for byte - 33, every one caught: 31 by a
  failing check (one, a Debug branch, first written as a comparison tsc refused as impossible and redone
  as a wording change), two by the sim crashing (the worklet's module made without `voiceReport`, and
  `voiceReport` reaching a module constant - the vm throws, as a worklet scope would). Not pinned: that a
  session set which throws isn't put back (harmless either way). The engine guard is empty and
  `player.sim.cjs` untouched.
- **Its review** found the four things above marked "review" - the script voice's chirp, a .11 press
  leaving a coast running under the finger (raised four times), the paused song's two
  silent turns, the hide mid-resume - and two weak checks, both fixed: the audio-session checks read
  `contexts.at(-1)`, which was the PREVIOUS block's context closed the same way, so with the session's
  try/catch removed (no context made at all, the turntable silent) they still passed - each wake is
  held to a context of its own now, running, the report not 'failed'; and the script voice's teardown
  compared `onaudioprocess` through `check()`'s JSON, which writes a function as null - a boolean now.
  The 30 checks: a late take's anchor (and an early, backwards one); the script voice's takes with
  frames and blocks on one clock (`together()`: a frame every 16 ms, a block every 1024 samples
  played a block later), a wind-down and a grab, each with its block first and a frame first - never
  past 1.03x (the first cut gave 1.41x here), a grab's backward swing above -0.3 (-0.86x without the
  lag); drives held as the last over twenty frames with no block, the newer of two windows held, a
  drive heard 43 ms on for its whole 0.12 s; a coast out of the window caught where the platter is,
  silently, nothing played in 3 s held, sounded as the window lands, sought where caught; a run back
  to speed out of the window caught and nothing played under the hand; .11 presses on a coast and a
  run back to speed whose context a hide suspended (no leap at the release; the song played, the sound
  stopped, not held) and on an MP3's silent wind-down (no leap - it was 20-35 degrees); the paused first
  turn with the worklet and on the main thread, asking once and only once; a hide mid-resume suspended
  as it runs, the mini player's tap and a hide undone before it settled left running. Mutations, each
  restored byte for byte on a copy: the first cut's lists rerun on the fixed code, all caught but one -
  `live()` by the song's position rather than the platter's, equivalent now (they differ only on a
  coast or a run back to speed, which the review's rule makes the deck's before either is asked, and on
  a sounding wind-down, whose whole path its window covers) - three re-aimed at code the fixes moved;
  and 22 for the fixes, every one caught (one - a drive's `until` not moved with its `time` - only once
  a check for it was added). NOT measured anywhere but the harness: the chirp's absence and the 43 ms
  lag by ear, on a phone - James's list.

### The speed fader (2.0.0-player.39)

James (2026-10-08), once the turntable's scrub sound was settled (blind, he can't tell deadwax's from an
ideal turntable's): "let's add the speed slider" - then "actually let's stick to .25-2x". First proposed
on 2026-10-07 as an RPM slider: a pitch fader beside the turntable, the pitch moving with the speed as on
a record deck, kept per device, done with the song's own playbackRate (an engine change). He listens on
Bluetooth earbuds, mostly on his iPhone, over plain http. The spec is the scratch's `uplan/slice-speed.md`.

- **The speed is the PLAYER's** (`player/usePlayer.ts`, the one engine change): 0.25x to 2x in
  hundredths (`lib/playSpeed.ts`, pure: `SPEED_MIN`/`SPEED_MAX`, `clampSpeed`, the words), kept per device
  as `deadwax-player-speed` (`readPlayerSpeed` in `state/persisted.ts`: a number 0.25 to 2, else 1; every
  read and write in try/catch). Not React state: `speed()`, `onSpeed()` and the `useSpeed()` hook beside
  `usePosition()`, so a fader moving it 60 times a second re-renders the fader and the chip, never App.
  `setSpeed()` (held to the range) puts it on EVERY element at once - the standby too - writes it, tells
  the lock screen (`updatePositionState`, which already carried `audio.playbackRate`), restarts the
  measured pace - from the update AFTER the change (`paceFrom = false`): the step from the update before
  it to the next is part old speed, part new, and counted it read 2x to 0.25x as 0.39x for seconds
  (review) - and tells the listeners.
- **How it is put on an element** (`applySpeed`): its `playbackRate` AND its `defaultPlaybackRate`, and
  the pitch switch let go. A load puts playbackRate back to the default - the media element load
  algorithm's step 7, WebKit `HTMLMediaElement.cpp:1733` and Chromium `html_media_element.cc:1243` (both
  read at main on 2026-10-08) - so with the default set too, every load keeps the speed: a new song, a
  reload of a failed one (`audio.load()`), the stream attaching its MediaSource (`element.src =` a blob:
  address, or `srcObject`), the standby's preload, AirPlay's leave of the stream. The pitch switch is kept
  by the element across loads (WebKit passes `m_preservesPitch` to the new player, `:2092`; Chromium
  `SetPreservesPitch`, `:1821`). And `applySpeed(audio)` again just before every `play()` - a handover's
  standby included - belt and braces for an engine that forgot the default (seen in neither engine's
  source; player.sim holds it with a hypothetical one). The page's element gets it as the engine starts,
  the spare as it is made. Only what differs is written.
- **1x is untouched - read from the source, not assumed.** Chromium resamples whenever pitch preservation
  is OFF, even at rate 1 (`AudioRendererAlgorithm::ChooseBufferMode`, `audio_renderer_algorithm.cc:341-
  349`: "Always resample when we don't care about pitch"), through a SincResampler whose kernel is a
  low-pass at 0.9 of Nyquist - not a passthrough; with it ON, rate 1 is a straight copy (`kPassthrough`,
  `:355-361`). WebKit chooses AVFoundation's Varispeed at rate 1 whatever preservesPitch says
  (`MediaSessionManagerCocoa.mm:252`: `if (!preservesPitch || !rate || rate == 1.) return
  AVAudioTimePitchAlgorithmVarispeed`), so there it makes no difference. So the switch is let go only
  while the speed isn't 1 - BEFORE the rate going off 1x, and held again AFTER it coming back, so no
  render quantum plays a time-stretch at the new rate - and at 1x on an element that never had another
  speed not one property is written (player.sim counts the writes: none, through handovers, a reload and
  a stream). Firefox reads its samples unprocessed when the rate is 1 either way (`AudioStream.cpp:766-
  770`).
- **What browsers do at 0.25-2x.** Chromium takes 0.0625-16 (`html_media_element.h:128-129`,
  `IsValidPlaybackRate` `:338-340`), throwing NotSupportedError outside it from playbackRate and silently
  ignoring it from defaultPlaybackRate (`:2930`, `:2949`); its renderer no longer mutes any rate (the
  header's "muted to preserve quality" comment is stale - FillBuffer has no range check). Firefox clamps
  to 1/16-16 and MUTES outside 1/threshold..threshold, the pref `media.audio.playbackrate.muting_threshold`
  8 (`HTMLMediaElement.cpp:185-200`, `:7883`; `StaticPrefList.yaml:14293`) - none of 0.25-2. WebKit takes
  any rate (no range check, `HTMLMediaElement.cpp:4464-4490`; HLS-only quirks cap 2) and hands it to
  `[AVPlayer setRate:]` (`MediaPlayerPrivateAVFoundationObjC.mm:1721`) or the MSE renderer's synchronizer
  (`AudioVideoRendererAVFObjC.mm:518-532`), with Varispeed off 1x when preservesPitch is false.
  AVFoundation: Varispeed takes 1/32-32 (`AVAudioProcessingSettings.h:43-45`, iOS 17.5 SDK); an
  AVPlayerItem ready to play plays 1.0-2.0 "even if canPlayFastForward is NO", and 0-1 only where
  `canPlaySlowForward` says so (`AVPlayerItem.h:277-283`) - WebKit caches canPlayFastForward but never
  clamps a rate to it (only scanning uses maxFastForwardRate). So 1-2x is promised on an iPhone, and
  0.25-1x depends on the item - NOT VERIFIED. And `AVSampleBufferAudioRenderer.h:136`: the renderer
  "may flush enqueued media data" when the rate changes - a change of speed during the one stream may
  drop a moment of audio on an iPhone (NOT VERIFIED). None of it is hidden: **Info > Debug's "Speed"
  row** (`speedRow` in `lib/debugRows.ts`, after Gapless) says the speed, whether the pitch switch reads
  let go or held (`speedReading()` reads the live element's switch by `pitchSwitch`: the standard name,
  else `webkitPreservesPitch`, else `mozPreservesPitch`, else "no switch"), a rate the browser threw at
  (its words), a rate that reads back as another, and - because WebKit's playbackRate getter returns the
  rate asked for whatever AVFoundation does (`m_requestedPlaybackRate`) - the song's OWN pace measured
  against the page's clock over the last `PACE_WINDOW_S` (8 s) of playing (`paceStep`/`paceOf`, steps
  from an update that followed another while playing: never across a seek, a pause, a load or a change of
  speed - each held by a player.sim check, the change of speed with a fake clock that runs at the old rate
  until the write, as a real one does). A browser that says yes and plays 1x shows there. The row is live
  while Debug shows (review: it was read only when Info drew, so on a desktop, whose panel isn't modal, it
  said 1.50x beside a song the bar's chip had put back to 1x, and a pace that came after Debug opened never
  appeared): InfoSheet listens on `onSpeed` and reads again every `SPEED_READ_MS` (1 s) while the Debug
  tab is open, asking for a redraw only when the reading changes - the pace to the hundredth the row
  says; nothing on About or closed (info.sim). Firefox's muting can't be read back (none in range).
- **AirPlay** (read in WebKit): nothing AirPlay-specific touches the rate. The AVPlayer carries it while
  `externalPlaybackActive`, the same `setRate:`; the newer wireless media engine rebuild carries
  `playbackRate()` across in its `RemotePlaybackConfiguration` and puts it back (`HTMLMediaElement.cpp:
  1488`, `:3327-3335`). deadwax's side: AirPlay always plays the URL way (the stream leaves in the same
  tap, `leaveStream` → `setSource` → a load, which keeps the default) - player.sim holds it. Whether an
  AirPlay speaker plays a rate other than 1, and with Varispeed's pitch, is the receiver's - NOT VERIFIED.
- **The wall-clock rules already took the element's rate** - `listenedStep` (`rate`), `clockStep`'s
  back-dating, `splitAcrossJoin`/`joinStallMs`, `seekStep`'s end judgement (`event.rate`) - so none of
  the engine's lib files changed. Pinned at 0.25x and 2x: the pure numbers in `playspeed.sim`, and through
  the real engine in `player.sim` (a play counted at 2x, a handover's gap a few ms at 0.25x and 0.8x, a
  7 s early landing judged as 7 s at 2x and 2 s as 2 s at 0.25x). `streamSource.ts` buffers in media
  seconds, so at 2x a stream needs twice the bytes a second and its cushion lasts half as long in wall
  time - unchanged, unmeasured on WireGuard.
- **The fader** (`player/SpeedFader.tsx`, drawn by Turntable inside its stage - so OUTSIDE Now Playing's
  grip, as the record and the arm - only when handed a player: Now Playing's `fader={player}`; the test
  bench gives none and has none). The board has no fader, so it is designed in its style from the theme's
  tokens: a sunken slot (STYLE.md's track: `--dw-track`, `--dw-border`), a knob in the arm's greys
  (`--dw-tt-arm-weight`, lighter while held) with a grip line, a mark across the slot at 1x lit
  `--dw-green-icon` while the speed is exactly 1x, and under it a readout in a well (`1.00x`, monospace)
  that turns STYLE.md's toggled purple off 1x. Its place is `FADER`/`READOUT` in `lib/playSpeed.ts`, in
  the plinth's units: x 359, the knob's centre from y 150 (2x) to 318 (0.25x), 20 x 12 - clear of the
  platter (widest at x 346), of the arm over its whole sweep (never right of x 345 there) and of the
  plinth's edge; the readout at (344, 349), the plinth's bottom right corner. The drawing is an SVG layer
  on the stage's viewBox, like the arm; the target an HTML `role="slider"` over the slot (the knob's whole
  travel, a knob's height included), before the arm's handle in the DOM so the handle wins their few px
  of overlap at a song's start.
  - **The target never reaches the record** (review: centred on the slot, x 359 is only 21 units from the
    record's rim at x 338, so a 44px target covered 1.5-4 px of the rim on every phone - a tap there did
    nothing, a scratch started there set the speed - and the capped one 5 units; playspeed.sim held only
    the drawn knob). app.css places it `left: max(var(--app-tt-fader-from), calc(var(--app-tt-fader-x) -
    width / 2))`, no translate: centred on the slot while that keeps clear, else from `FADER_FROM` (the rim
    and `FADER.clear`, 1 unit) and reaching right, past the plinth's edge into `.app-tt`'s 12px padding -
    at most 17 px past it, so on a 340-375px phone whose plinth fills the width the phone's own edge
    clips up to about 3 px of the 44 (the sheet's `overflow: hidden`; no page scroll). Centred only from a
    410px plinth up. The two places come inline as custom properties; `faderTarget()` (pure) computes the
    same, and playspeed.sim holds it at 13 plinths from 45 to 440px: never left of the rim and a unit, the
    knob inside, 44px from 315px up. The real page (fix-check below): not one point of the rim's outer
    6 px is the fader's at 390x844, 375x667, 393x659, 375x553 or 320x568, a real tap a pixel inside the
    rim pauses the song, a drag from there leaves the speed alone. (On a phone on its side, a 57px record,
    `elementFromPoint` still gave the fader 4 sampled points within a pixel of the rim - its integer-ish
    hit-test rounding at a unit of a fifth of a pixel; three units' clearance gave the same 4, so it stayed
    one.) Keyboard focus draws its ring round the whole target, so the ring hangs past the plinth's edge.
  - **The readout is drawn over a failure line** (review): on the turntable the line is laid over the
    plinth's foot (two lines, `pointer-events: none` - "The turntable (2.0.0-player.11)"), and on a phone
    short of height it reaches the readout's corner - 5.1-5.9 px into its face at 393x659, 390x664,
    375x667 and 360x640 (Safari with its bars), 7.7-8.1 at 320x568 and 375x553 - red words through purple
    ones. An inset on the line would need about 50-80 px each side and push a 75-character message past
    its two-line clamp; moving the readout up runs into the fader's slot. So the readout has
    `z-index: var(--app-z-tt-readout)` (1) and an opaque well - its tint laid on `--dw-tt-plinth`
    (`linear-gradient(tint, tint), var(--dw-tt-plinth)`), the same pixels as before on the plinth - and the
    line's few px under its face are hidden instead (at 393x659 only ascender tips; at 375x553 the top of a
    word's x-height under 42 px of face). It reaches over the line because nothing between it and the
    sheet makes a stacking context: the stage none, and `.app-tt`'s `container-type: size` applies style
    and size containment only, not layout (WebKit `StyleComputedStyle.cpp:458-468`, `usedContain()`, read
    at main 2026-10-08; Chromium the same on the real page) - test_app_css.py holds both, and that the line
    has no z-index of its own.
  - **By octaves**: `faderShare` is log(speed/0.25)/log(8), so 0.25x, 0.5x, 1x and 2x are a third apart
    and 1x sits two thirds up - pitch is heard in octaves. ~168 units of travel: about 1.3% a pixel.
  - **The drag** (`faderStart`/`faderMove`/`faderEnd`, pure): nothing until the finger has travelled
    `TAP_SLOP_PX` (lib/turntable's 8), then taken at the slop's edge FROM THE SPEED AS IT IS - the arm's
    rule - so a press or a nudge never jumps it; up is faster; held to the ends (a finger past the end
    must come back to the knob); LIVE - each move a `setSpeed`. The detent: a drag landing within
    `SPEED_DETENT` (2%) of 1x is exactly 1x (about 1.5 px either side). Measured in the fader's own box
    as the press found it; pointer captured; a second finger and a mouse's other buttons start nothing;
    capture lost ends it; a cancel keeps the speed it had reached (it was live).
  - **Keys**: arrows 0.01 (up and right faster), Page Up/Down 0.1, Home 0.25, End 2 - with NO detent (an
    arrow from 1x is 1.01x; a detent would snap it back). `aria-valuetext` "1.25 times" / "normal speed",
    `aria-orientation="vertical"`.
  - **The readout's tap** is exactly 1x (`aria-disabled` at 1x).
  - **44px targets with the arm handle's cap**: `min(var(--pl-hit), var(--app-tt-fader-cap))`, the cap
    14% of the plinth's width - 44px from a 315px plinth up (a 390 phone's is 366), and on a phone on its
    side (a 66px plinth) a 9px fader, which starts past the record's rim like every other (the first cut
    said it "never covers the record"; centred, it covered 5 units of it - see above). The readout's words are
    `--app-tt-readout-text: min(12px, 3.2cqw, 3.2cqh)` of `.app-tt`, the size container - smaller with the
    plinth. (The first cut put `var(--app-tt-aspect)` in that token: a custom property's var() is filled
    in where it is DEFINED, `:root`, where the stage's aspect isn't, so the whole token was invalid and the
    readout inherited the sheet's 17px - the real page showed it spilling off the plinth; the test now
    holds the token.)
- **The chip** (`player/SpeedChip.tsx`): nothing at 1x; otherwise `1.25x` in a 44px button with
  STYLE.md's toggled chip drawn inside (28px), its tap exactly 1x. At the START of Now Playing's icon row
  (`margin-right: auto` in a row that is `height: var(--pl-hit)` and `justify-content: flex-end`), so it
  moves nothing coming and going - the rule from the sheet; and first in the desktop player bar's tools
  (right-aligned, the tools' 32px height, a 24px face) - so a speed set on the phone is never stuck unseen
  in the desktop frame an iPad turns into. On the turntable look it is drawn too and hidden
  (`.app-is-turntable .app-speed-chip { display: none }`) except under `@media (max-height: 500px)` - a
  phone on its side, where the readout is too small to read. Not on the mini player (the spec named the
  cover and the bar) - the guide and troubleshooting say so, rather than "wherever the fader isn't
  showing" (review). Its name starts with what it shows - "1.25x, 1.25 times the song's speed: back to
  normal speed" - for Voice Control (review: WCAG 2.5.3, label in name; it was "Playing at 1.25 times...",
  which said "Playing" while paused too). Its press takes it away, so focus on it (a keyboard's,
  VoiceOver's - `ownerDocument.activeElement` is the chip) goes on to its next sibling, which stays (AirPlay,
  •••, the bar's Info) before the speed is set - never to the page (review; the app's rule since
  ServerSettings, Pinned, NeedsALook). A finger's tap gives a button no focus in WebKit and moves none.
- **The turntable follows the speed** (`player/deck.ts`; Turntable tells it with `speedChanged` as it
  mounts and on every `onSpeed` - the deck's own speed, so the old one is there to re-anchor from). The
  motor's target is the speed (`lib/platter.ts`'s `motor(x, speed, length, target = 1)` and
  `acceleration(speed, motorOn, target = 1)`, every exact phase with `target` where it had 1, `Plan.target`
  saying what a plan heads for: the motor's, or a coast's 0): the platter turns at `DEGREES_PER_SECOND *
  speed` (re-anchored mid-turn, no jump); a hand takes a playing record at the speed (`take`); a let-go of
  a playing record runs back to the speed and is sought where that lands; the handover holds the speed
  until the song plays; a pause winds down from it (`coast(at, speed)`); a spin-up runs to it (and a change
  mid spin-up re-plans from where it had got to); a pause from elsewhere spins down from it; a cancel spins
  back up to it. `plan.v >= 1` tests became `plan.target > 0` (a spin-up to 0.25x is still the motor's). The
  same motor pull: still to 2x takes 0.8 s, to 0.25x 0.1 s; the wind-down from 2x about 1.25 s, from 0.25x
  0.55 s. A run back to speed after a let-go keeps the speed it was let go at (the song was sought where
  that lands) and turns at the new one once there. Debug's "back after the let-go" allows the song's
  speed. **The window is asked ahead by listening time** (review): `keep()`'s margin ahead was 6 s of the
  SONG - time for a fetch and a decode, so at 2x 3 s of listening, and a hi-res song's 13 s window about
  1 s; a hand taking the record in the gap was silent until the late window landed. It is now
  `ahead * max(1, speed)` while the song plays (12 s of the song at 2x; slower than 1x, as it was), the
  move-on rule still holding (a 40 s window at 2x moves on 24 s; a 13 s one about 6) - deck.sim holds the
  ask at 5.75 s before the end at 1x, 11.5 at 2x and 5.875 at 0.5x, and windows of 13 s and 2 s moving on
  at 2x. **The record's sound needed no change** (`lib/deckVoice.ts` untouched): it reads at whatever
  rate it is driven at.
- **The visualizer** (desktop): its silent copy's AudioBufferSourceNode plays at the speed
  (`node.playbackRate.value`, set before `start`), and where it has got to is `copyAt(anchor, now)` - the
  anchor's place plus its rate times the context time since (`lib/vizSync.ts`, pure) - re-anchored in place
  where the speed changes (`reanchor`), the same node carrying on. Without it the drift rule re-synced the
  copy over and over (vizsync.sim shows a copy left at 1x under a song at 1.5x restarted more than four
  times a window). Its tempo reading follows: a song at 2x reads twice the bpm, which is right.
- **The allowlist** (`app-rules.sim.cjs`): `setSpeed` is a player action - not gesture-gated - reached by
  name from exactly `player/SpeedFader.tsx` and `player/SpeedChip.tsx` (Turntable and Now Playing hand the
  player on without naming it), each from its handler with nothing awaited; and no file but the engine
  sets a rate, a default rate or a pitch switch on an element (the copy's `.playbackRate.value` is an
  AudioParam of its own node).
- **Verified**: 2395 Python tests (2393 passed, 2 skipped; 3 new - the fader's and readout's targets, the
  token, the drawing's tokens; the chip that moves nothing and shows on the turntable only on its side;
  the bar's chip), pyflakes, tsc, the build, and all 47 sims, 4898 checks after the review below (4879
  before it) - `playspeed` new (80: the numbers, the fader's maths and place - its target off the record
  at 13 plinths - the stored speed, the wall-clock rules at 0.25x and 2x, what Debug reads, the fader and
  the chip rendered, the chip's focus, the visualizer's copy against a fake context); `player` 474 -> 521
  (its fake elements taught playbackRate, defaultPlaybackRate, the pitch switch by name and the load
  algorithm's reset, every write the page makes kept, and - `net.rateAtWrite`, off unless a check asks -
  a clock that runs at the old rate until the page writes a new one; every check before them unchanged);
  `deck` 272 -> 305 (the integration at 0.25x, 0.5x, 1.5x and 2x over 30 flicks each, the deck at the
  speed, its windows asked by listening time); `vizsync` 54 -> 59, `turntable` 167 -> 174, `app-rules`
  286 -> 293, `debug` 100 -> 108, `info` 134 -> 143 (the Speed row live). Mutations, each restored byte for byte
  (by hash): 77, 76 caught - the one not, `speedNow()`'s turning branch returning 1, is unreachable
  (playingChanged returns before it for a turning platter), equivalent. Two first got past and gained
  checks: the measure across a load (it needed a second song - a page's first starts unmeasured anyway)
  and a spin-up to 0.5x that ended still; three more gained checks before the run, found by reading
  which rules nothing held (the drives' acceleration about the speed, Debug's back-after-let-go at 2x,
  reduced motion's spin-up to a slow speed). The engine guard: only `usePlayer.ts` and `player.sim.cjs` changed, as the spec allows.
  **The real page** (the builder's own deadwax on 8110, headless Chromium, real touch and mouse, over
  plain http as deadwax.test - the main-thread voice - and on localhost - the worklet; 35 + 5 checks each,
  all passed): the fader dragged to 0.5x (live, finger still down) and 1.5x with playbackRate,
  defaultPlaybackRate and preservesPitch read back, the song moving at 0.5x; the detent; the readout's tap;
  the keys; the chip on the cover (`1.50x`, a 44px target at the row's start, its tap 1x, nothing moved
  as it went) and on the 1440 player bar (its click 1x); Next keeping the speed; a reload keeping it; the
  Debug row (`1.50x, the pitch moving with it`, measured 1.49x); a scrub at 0.5x - the platter at 100
  degrees a second, taken (the song paused under the hand), turned, let go, the song playing on at 0.5x
  from past where it was taken and the platter back at 100 degrees a second; Gapless's stream across a join
  at 1.5x with both elements carrying it; the visualizer's copy at 1.5x, started once; 375x667 and 844x390
  (the fader capped to 9px of a 66px plinth, the chip shown on the turntable); no overflow, no console
  errors, no createMediaElementSource.
- **The review** (fifteen findings - two of them found twice - each confirmed by a majority of skeptics;
  all fixed): the
  fader's target on the record's rim; Debug's pace counting the old speed across a jump; the Speed row
  stale while Debug was open; the window asked ahead by song time at 2x; the readout under a failure line;
  the chip dropping focus and named without its text; the guide's turntable figures true only at 1x and
  its "wherever the fader isn't showing" (the mini player shows nothing); sims.md's lines; and three checks
  that couldn't fail or weren't there - deck.sim's "told the same speed again" read the angle without a
  frame (a deck stopping dead there passed), and nothing held the pace's seek guard or the second
  spin-down (a refused handover play, `coast(0, this.speed, 0)` after HANDOVER_MAX_S) - so "76 of 77"
  had missed those three rules. 21 more mutations, every one caught: the pace's restart and its seek guard
  (player), the Speed row's listener, timer, tab and rounding (info), the window margin unscaled and
  scaled below 1x, the refused handover's spin-down from 1x, the same-speed guard gone or stopping the
  platter (deck), the chip's focus dropped or moved on a finger's tap, its old name, the target centred,
  from the rim exactly, or handed no rim (playspeed), and the target's CSS centred, the readout's z-index
  and opaque well, and a stacking context on the stage (test_app_css.py). The real page (the fixer's own
  deadwax on 8112, headless Chromium, real touch and mouse, deadwax.test and localhost, `fix-check.cjs`:
  14 checks each, all passed): the rim as above; the readout on top where a line meets it at 393x659 and
  375x553, opaque on the plinth's colour; Debug opened straight after End then Home showing the pace
  unprompted at 0.25x; on the 1440 desktop the open Debug reading 2x and then, after the bar's chip, 1x
  without a tab switch; the chips' names, and focus on to ••• and to the bar's Info after a keyboard
  press. The builder's own 35 + 35 + 5 real-page checks run again on 8112: all passed.
- **NOT verified - James's iPhone**: that the pitch moves with the speed on the phone (Varispeed), that
  0.25x and 0.5x play at all (`canPlaySlowForward` - Debug's measured pace answers it), a change of speed
  during the one stream (the renderer's flush), the lock screen's scrubber at the speed, AirPlay at a speed,
  the fader under a real finger beside the record and the arm, and VoiceOver on it.
- **Left out**: the chip on the mini player; any speed control on the desktop but the chip (no fader
  there - the turntable is the phone's); the stream's buffering scaled to the speed; the visualizer's
  window margin (`VIZ_AHEAD_S`, song seconds like the deck's was - a late window there stops the picture a
  moment, nothing heard).
