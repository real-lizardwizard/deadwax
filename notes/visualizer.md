# The desktop visualizer, and the Mandala refined

(Since 2.0.0-player.39 the silent copy plays at the player's speed - `copyAt`/`reanchor` in lib/vizSync.ts:
see "The speed fader (2.0.0-player.39)" in notes/turntable.md.)

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### The desktop visualizer (2.0.0-player.20)

James, deciding the one-app structure (2026-09-29 to 09-30): the desktop gets "some sort of cool
fullscreen visualizer with a few options for effects" instead of a turntable. The spec is the session
scratchpad's `uplan/slice-visualizer.md` (there is no slices.md section); the reference implementation
is the canvas board `DesktopVisualizer.dc.html`, ported. Built beside 2.0.0-player.21 (editing an
album on desktop, S9), which is rebased onto this. His decisions, each binding: effects Bars, Scope,
Halo and Ambient ("stars is junk" - Stars was dropped); colours from the cover or purple; Ambient a
family of styles from a dropdown or "Rotate all" in a FIXED order ("the style selector shouldn't be
random, it should be consistent"); the ambient styles SHIFT AND FLOW, never pulse ("the mandala is
still pulsing, I'd like it to not pulse, just to shift, and a little bit quicker"); the Mandala MORPHS
like a kaleidoscope, never a crossfade; Waves fly toward you with the heading shifting; a Windows Media
Player-like family from one parametric shader, our own code and names ("stick to our own" - no
butterchurn or preset libraries); shapes follow the music's feel, speed its tempo.

- **THE SILENT COPY - and why createMediaElementSource is banned, everywhere.** The player's audio
  element is NEVER connected to Web Audio: a createMediaElementSource reroutes the song through Web
  Audio, which breaks locked playback on an iPhone and puts processing between the file and the
  speakers - James's rule is audio fidelity first, "the tap must be measured to change nothing".
  `app-rules.sim.cjs` holds EVERY file under ui/src (the old page's included) to never naming it in
  code. What the visualizer sees is its own copy (`player/vizAudio.ts`): the turntable's FLAC window
  (`GET /deadwax/navidrome/scrub/{id}?at=&seconds=40[&max_rate=48000]`, `player/api.ts` scrubWindow -
  the same route, untouched, cut from the very copy the page plays), decoded by decodeAudioData, played
  by an AudioBufferSourceNode into an AnalyserNode and on into a GainNode at 0 - connected to the
  destination only because a node nobody pulls is never run. Nothing of it is heard. app-rules pins
  the chain (source -> analyser -> a gain of 0 -> the one connection to the destination - however it
  is spelled: `destination` named once in the file, the gain written once, to 0) and that none
  of the visualizer's eight files touches a media element. deck.ts, deckVoice.ts and Turntable.tsx are
  untouched - the window logic is NOT shared: the deck's lives in its class beside the voice, and
  pulling it out would have changed the turntable; the visualizer's is its own pure module.
- **Keeping it in time** (`lib/vizSync.ts`, pure, `vizsync.sim.cjs`): each animation frame,
  `planSync` takes what the element is doing (song, playing and not buffering, position) and what is
  held (the decoded window, one on its way, the copy running and where it has got to) and answers
  stop / start-at / fetch-from. Paused or stalled: stopped. Playing inside the window: started at the
  playhead when none runs, it is another song's or window's (a fresh decode is taken up at once), or
  it is more than DRIFT_S (0.25 s) from the element - a seek, a stall; left alone otherwise. Outside
  the window, or within END_GUARD_S of its end: stopped. A window is VIZ_WINDOW_S (40 s) from
  VIZ_BACK_S (2 s) before the playhead on a 2 s grid, asked again VIZ_AHEAD_S (6 s) before its end
  (never past the song's end), one at a time (`pending`), and a refresh must move on from the window
  it replaces - with the margins shrinking for a window deadwax cut short (a hi-res song's), so a
  short window never asks for itself. A failure waits VIZ_RETRY_MS (10 s); a 415 or a window the
  browser couldn't decode is refused for that song for this opening - each song's refusal, failure
  and window length its own (`refused` and `failed` are lists, kept per song in the listener), so the
  next song's never stands for this one's. **The next song's first window** (`prefetch`, the queue's
  `nextIndex`) is asked in this one's last VIZ_AHEAD_S, once this one needs nothing and nothing is
  on its way - even while this one can't be seen - and held as `ahead` until its song starts
  (`takeAhead`): a gapless album's copy runs from the next song's first frame (the sim plays two
  songs back to back). Not for a next song that isn't a FLAC, is refused, failed under 10 s ago or is
  in hand. A skip or a seek still waits for its window. Only the newest fetch and the newest decode
  count (two latestOnly()s, pinned).
- **Cost**: 40 s fetched for every 32 s played while it shows (the sim plays a 4-minute song through
  it: eight windows), plus one window of each next song. ON THE SERVER, as built here, a window was cut
  from the MP4 the player's cache keeps (`_window_source`), so in a browser that plays the FLAC as it
  is - Chrome, Firefox or Edge with Gapless off, the default, a CD-rate song - the first window of each
  song had deadwax make that MP4: the whole song fetched from Navidrome again, kept in the cache and
  counted against PLAYER_CACHE_MB, clearing the songs played longest ago (an iPhone's MP4s among
  them), and that first window waited for the make. Found in review and documented, not changed then.
  **Changed in 2.0.0-player.23** (James: "yes, cut the windows straight from the FLAC"): with no MP4
  kept of the song as it is, the window is cut straight from the FLAC by byte ranges - the head once a
  version, then about the window's own size - with nothing made or kept, byte for byte the window the
  MP4 would give; see "Windows cut straight from the FLAC". The prefetch still hides a window's wait
  at a song change.
- **"Can't be seen"**: not a FLAC, a window that can't be had, a refusal, no Web Audio - the effects
  run from a calm idle signal (`idleSignal`: a soft slope across the bands and a gentle wave, changing
  slowly, no beat) and one plain note at the bottom right says why ("This song can't be seen - it isn't
  a FLAC file.", "...just now - deadwax couldn't send its sound.", "This browser can't analyse sound,
  so the song can't be seen."), no error styling - kept to its corner (a max-width clear of play/pause
  and so of the keys line at the left), a long one (deadwax's 415 reason for a FLAC it couldn't
  repackage) wrapping there. A context still starting (a resume on its way) says
  nothing; while a window is on its way the signal is silence. The feel is never read from the idle
  signal - it holds, so an unseen song never reads as "smooth".
- **Nothing needs a secure page** (James opens deadwax over plain http): an AudioContext, an
  AnalyserNode, decodeAudioData and requestFullscreen all work there; no AudioWorklet. app-rules fails
  on audioWorklet, AudioWorkletNode, randomUUID, crypto.subtle, clipboard, getUserMedia or a service
  worker in any of the visualizer's files.
- **The audio context** is made only in `wakeVisualizerAudio()`, called only from App's
  `openVisualizer` - the player bar's click, the gesture a browser lets it run from (pinned: made only
  there, the constructor looked up only there, nothing built from an expression, called from that one
  handler - over the WHOLE file, the listener's methods included, and nothing else made with `new`
  but typed arrays, maps and errors). Suspended while the page is hidden, resumed as it shows (and from a click or keyup in the
  visualizer, for a browser that wants a gesture), closed as the visualizer closes. It is the
  turntable's rule ("made in one place") widened to two: the deck's and this.
- **The port of the board.** `lib/musicFeel.ts` is its musicFeel() and tempoFromOnsets() unchanged in
  behaviour (onset density, centroid, high share, flatness, crest -> aggr; an 8 s onset envelope,
  smoothed over 80 ms, autocorrelated 60-200 bpm with a 100-130 preference and the "faster reading wins
  when dense" rule -> bpm, conf, tempo 0.65-1.5, beats halved into 0.9-2.2; silence or a pause below
  the 0.03 floor holds EVERYTHING). `musicfeel.sim.cjs` drives it with the board's own three
  synthetic songs - the "Mock signal", which ships nowhere else - taken across as a fixture: smooth
  reads 0.00 (63 bpm), aggressive 0.86 (180, its fast pulse), the song that builds rises second by
  second through 58-68 s and falls through 124-134; clicks at 90/120/150 and busy 8ths at 170 read
  within 3 bpm. `lib/visualizer.ts` holds the rest of the pure maths: the effects and styles, the
  rotation, the colours, feedbackStyles (Burst, Ribbons, Smoke, Rings, Embers - one shader, a set of
  numbers each, the tempo scaling warp and drift), mandalaFlow/mandalaMorph, wavesCamera, liquidFlow,
  hueStep, the signal's shaping and the size caps. `lib/vizShaders.ts` is the board's GLSL extracted
  byte for byte (WebGL 1). `player/vizDraw.ts` is Bars, Scope, Halo and the plain Ambient in Canvas
  2D, `player/vizGl.ts` the WebGL side (ping-pong feedback, two slots for a crossfade, a composite).
  The board's fixed 1440x900 became "900 units high, as wide as the screen's shape": x positions keep
  their share of the width, heights and radii are the board's.
  **Changed in 2.0.0-player.34**: musicFeel is tuned on real music now - the centroid and crest gone,
  the onsets counted on a grid of 60 a second, the sim's numbers moved (aggressive reads 1, the build
  falls through 126-136) - see "The Mandala refined, and the feel tuned".
- **What a real song gives that the board's synthetic one knew**: the 64 bands come from
  getByteFrequencyData (FFT 2048, -90..-22 dB, the analyser's own smoothing off - the effects smooth and
  the feel needs the raw flux) through `bandLayout`/`bandsFromBins` (log-spaced 30 Hz-16 kHz; the
  loudest bin a band covers, or read between bins for a band narrower than one); the waveform is the
  last 28 ms of getFloatTimeDomainData as 384 points, through a slow automatic gain (so a quiet
  recording still draws a line), tanh-limited and tapered; the KICK - the board's songs knew theirs -
  is the low bands jumping above their own 0.25 s level, dying over 120 ms (`shapeSignal`).
- **THE FIXED ROTATION** (`AMBIENT_STYLES`: mandala, waves, liquid, burst, ribbons, smoke, rings,
  embers; `rotationTick`): Rotate all starts on the first, holds each HOLD_MS (30 s) of PLAYING time,
  crossfades over FADE_MS (2.6 s) - the rotation itself lets the outgoing style go when the fade is
  done (in the board the composite pass did) - never starts another mid-fade, wraps to the first. A
  picked style holds; Rotate all again carries on from what shows with a fresh 30 s. app-rules fails on
  Math.random or getRandomValues in any of the visualizer's files; `visualizer.sim.cjs` holds the order,
  the 30 s steps, the paused time, the fade, two runs identical.
- **Colours**: `coverPalette` reads the playing album's cover (fetched as bytes and decoded by
  createImageBitmap - no image element - drawn 40x40): its strongest hues, each with its neighbours'
  colour, put in hue order from the widest gap, made vivid (saturation 0.45, value 0.78 at least); a
  black-and-white cover is a ramp of its own grey; no opaque pixels or no cover yet -> the purple. The
  Mandala's five parts are derived from it (`rolesFrom`); in purple they are the board's. Halo's record
  is the album's CD art (the turntable's `/library/disc_art/navidrome`) when deadwax has it, else a
  black record with the COVER as its label - the board's prism stand-in made real.
- **The screen** (`player/Visualizer.tsx`): drawn by App over everything (`<Visualizer
  open={visualizerShown} ... />`, `visualizerShown = desktop && visualizing`; the screen and every part
  of it exist only while open). requestFullscreen on its own element (and the webkit spelling);
  refused, it is already a fixed layer over the window (z 50, over the pin notice's 40). Escape, Leave
  full screen, or leaving full screen (fullscreenchange after it was entered) closes it; focus goes in
  as it opens and back to the player bar's button as it closes (again once the browser has left full
  screen - until then Chromium keeps the page inert); Tab stays inside it; everything behind
  it is inert while it shows (`covered` gained `|| visualizerShown` - and a desktop's Sources, Info or
  (since .21) Edit panel left open beside it, outside that wrapper, takes `covered={visualizerShown}`
  as Now Playing takes what is over it); nothing behind it counts as watched (`watchingOf` gets `sheetOpen: sheetOpen
  || (desktop && visualizing)`, so Requests' 500 ms poll stops under it); the page behind doesn't
  scroll (`html.app-viz-open`, its own lock class, as each sheet has); a window narrowed to a phone's
  width closes it (in the crossing effect's Info branch) and it never reopens by itself. Its chrome is
  the board's - the song (cover, title, artist, album), the effect picker, the Style dropdown (only for
  Ambient with WebGL; "now:" and "feel:" under it from 1280px), the colours, Leave full screen,
  play/pause, the keys line, and the notes - fading after CHROME_IDLE_MS (3 s) of stillness while
  playing (never paused, over the controls or with the list open), the pointer hidden with it - and
  back on a move, a key or a PRESS: a tap on a touch screen fires no pointermove, so a still tap never
  woke it (an iPad on its side is a desktop frame); a press that wakes it has its click swallowed
  (`onClickCapture` within WAKE_CLICK_MS), so a tap where a hidden control was presses nothing. Space
  plays or pauses - `player.toggle()` called only in `onToggle`, from the button's click and the
  key, nothing awaited, a held key's repeats ignored (`event.repeat`: they played and paused it at the
  repeat rate), the file on app-rules' allowlist for `toggle` alone; V / Shift+V the effects. Focus
  never falls out of it: in Chromium a clicked button takes focus, and the style list's option (as the
  list closes) or the Style button (as Ambient goes) left it on <body>, where the root's key handlers
  never ran - Space, V and the fallback layer's Escape all dead until a click. A layout effect after
  every render puts focus back on the root when it is outside; a pick or Escape gives it to the Style
  button. The list is a listbox: it opens on the chosen style; the arrows, Home and End move in it.
  The cover's colours and Halo's record are asked for only as their own address changes (not per
  song), the last kept until the next has come - they flashed to purple and a plain record at every
  song change - and a CD-art 404 isn't asked again this opening.
  NOT drawn, on purpose: the board's previous/next, seek bar and Sensitivity slider (the spec lists
  the chrome without them, and only the toggle is allowed - skip and seek stay the player bar's).
- **Choices per device** (`state/persisted.ts`; configuration.md's per-device table, now nine
  settings): `deadwax-player-viz-effect`, `-colours`, `-style`,
  each validated against what is offered; anything else is the board's opening - Ambient, From the
  cover, the Mandala. persisted.ts spells the lists out rather than importing lib/visualizer.ts: it is
  shared by the main page's bundle, and the import put the visualizer's tables in the chunk both
  entries load (seen in a local rolldown build); `visualizer.sim.cjs` holds every effect, colour and
  style offered to reading back as itself.
- **Cost on screen**: the frame loop runs only while it shows and the page is visible (hidden: stopped
  and the context suspended - pinned); the 2D canvas is drawn at no more than 2880x1800 pixels and
  the WebGL at no more than 1800x1125 (`backingScale`, MAX_2D_PIXELS and MAX_GL_PIXELS: a 1440x900
  laptop at 2x is sharp, a 5K screen isn't asked for 5K); the WebGL context is let go on close. No
  WebGL (or a shader that won't build) -> Ambient is the board's plain 2D version, said in one line
  while Ambient shows (tried once per opening).
  **Reduced Motion**: every clock at CALM_PACE (0.35), the bands rising and falling slowly, no kick,
  the tempo held under 0.8 - a calm, slow version, stated in the guide.
- **Style**: the colours are theme.css section 10's `--dw-viz-*`, the sizes `--app-viz-*` in
  app-desktop.css's own block at its end (every rule from 1024px under `.app-desk`, as the frame's);
  `test_app_desktop_css.py` holds the layer, the fade (a token on section 7's duration, so reduced
  motion collapses it), the pointer only on controls, the wrap below 1280 and the readout from it.
  The song is `flex: 1 1 0` (with its 200px minimum) and the choices `0 1 auto`: the song takes what
  the choices leave, so they hold one row wherever that minimum allows - from 1280px always. Both at
  `0 1 auto` shrank in proportion, and a long title (a classical movement) wrapped the choices at 1280
  and over, "feel:" drawing over Leave full screen. A coarse pointer gets a finger's targets in a
  coarse block of its own AFTER the visualizer's (the frame's earlier one would lose to it): the
  pickers' well, Style, Leave, the options and play/pause at 44px, the readout and the list hung
  under the taller button.
- **Verified**: 2207 Python tests (five new in `test_app_desktop_css.py`, the visualizer's lock in
  `test_app_css.py`), pyflakes, tsc, and all 40 sims (`musicfeel` 28, `vizsync` 54 and `visualizer` 72
  new; `app-rules` 206 - the visualizer's section, the allowlist, `covered`, the context made in two
  places). 68 mutations, one or more per
  rule pinned, each restored byte for byte: 65 caught at once; three first got past and gained checks
  - a context built from an expression (`new (contextClass())()`, past the `new Context(` regex), the
  envelope's 80 ms smoothing (the board's songs read the same without it; a busy 8th-note click reads
  half-time), and the song check on a running copy (window numbers never repeat, so the case is
  defensive). The engine guard is empty and `player.sim.cjs`, `deck.sim.cjs` and `turntable.sim.cjs`
  pass untouched.
- **After review** (27 findings, merged to 19, every one fixed or documented): the server-side cost
  above (documented); Space's repeats; a tap waking the controls, and the tap only waking them; focus
  falling to <body>; the panels and the poll behind it; the pictures flashing per song; the next
  song's window fetched ahead; the song/choices row and the note's corner; coarse targets; the scroll
  lock; configuration.md's three per-device rows ("nine settings"); "Rotate all" carrying on rather
  than "always starting on the Mandala" in the guide; and the tests that claimed more than they held,
  strengthened - app-rules' context pin over the WHOLE vizAudio.ts (a method making `new C()` got
  past the function scan), the destination named once and the gain written once (other spellings got
  past), `visualizer.sim`'s tempo scaling on Smoke (Burst's turbulence and drift are 0), Liquid's
  travel against the bass and the waveform's exact 4x cap, `vizsync.sim` holding each song's refusal,
  failure, span, pending and held window to their own song, `musicfeel.sim`'s word edges and neutral
  110 bpm pace. 50 mutations of the fixes and the strengthened checks (the sims) and 6 of the CSS
  (the Python tests), each restored byte for byte: all 56 caught. One more found while checking them:
  closed while still full screen (Leave full screen, V..., an Escape the page gets), focus never went
  back to the player bar's button - Chromium keeps everything outside the full-screen element inert
  until it has left, so it goes back again on that `fullscreenchange` (FULL_SCREEN_LEAVE_MS at most).
  **Checked in headless Brave** (driven over `--remote-debugging-pipe`, no port, with real mouse, key
  and touch input, against a file:// harness of the real Visualizer, the real stylesheets and a fake
  player - no server): the list opening on the chosen style, the arrows and End in it, a mouse pick
  leaving focus on the Style button and Space and V working after it, V leaving Ambient with focus
  kept, a held Space toggling once, the page behind not scrolling (full screen and refused), a still
  click and a still TAP on play/pause bringing the controls back and pressing nothing (the second
  pressing it), Escape and Leave full screen closing it with focus back on the opener, Escape after a
  pick in the refused layer, a long title keeping the choices to one row at 1280 and 1440 with "feel:"
  over nothing (two rows and the song at 200px at 1024), and a long note wrapping in its corner clear
  of the keys and of play/pause at 1024 and 1440 - 30 checks.
- **Verified in the real page** (headless Brave against the stubs on :8081, real mouse and keys,
  42 checks, then again on `http://deadwax.test:8081`, not a secure context - 42 there too): it opens
  from the bar into real full screen covering the window, the page behind inert and focus inside; the
  silent copy fetches a scrub window and the picture moves; a FLAC is seen; Bars, Scope, Halo and
  Ambient each chosen and moving; the list offering the eight styles and Rotate all, Escape in it
  closing only the list; every style picked by mouse with focus kept and moving; Rotate all saying
  "now:" and "feel:" at 1440; Purple; the controls fading after a still moment while playing and back
  on a move; Space pausing and playing with nothing but `pause` reaching the element (no waiting,
  seeking or emptied) and one audio element throughout; V to the next effect; Escape and Leave full
  screen closing it with focus back on the bar's button and the song carrying on; everything inside the
  window at 1280 and 1024; no button on a phone; no console errors. The phone screens matched .19's
  (the group page's Archive cover arrives from a different archive.org mirror run to run).
  **The Mandala tore** along the left horizontal whenever its mirror count was between whole numbers
  - every morph from one count to the next. The board's shader added the spin and twist AFTER
  `atan`, which moved atan's wrap at +-pi off a mirror line; the fold is even, so measured from a
  plane turned first (`rot(spin + twist) * w`, then `atan`) it meets itself there and whole counts draw
  exactly as before. Measured by comparing the rows 3px either side of the centre line on the left
  with the same rows on the right over 24 frames: up to 6.5x more difference on the left before, 1.35x
  at most after. `visualizer.sim.cjs` pins the turned measurement and shows the old way jump at 6.5
  mirrors (it fails with the old line put back). **Changed in 2.0.0-player.34**: the count no longer
  glides between whole numbers - it changes only by a fold, a mirror swinging inside every wedge at once
  - and the Mandala is one figure with room round it; see "The Mandala refined, and the feel tuned".
- **NOT verified here**: that a real FLAC's analysis looks like the board's synthetic songs (the dB
  range and the kick were chosen, not tuned against James's music - the stub library is tones);
  WebKit's requestFullscreen from the layout effect after the click (Chrome and Firefox allow it for
  5 s after a click); an iPad on its side, which is a desktop frame and so draws the button - whether a
  second AudioContext there leaves the element's playback as it was is unknown, and whether WebKit's
  synthetic click after a waking tap lands inside WAKE_CLICK_MS; the next song's window arriving
  before a real gapless join; a song that can't be seen (the stub library is all FLAC; the sims hold
  it); and how it feels with James's music.

### The Mandala refined, and the feel tuned (2.0.0-player.34)

James (2026-10-04): "I'd also like to get a bit more refinement on the mandala visualizer ... right now it
just looks a bit busy", "and I'd like it to morph a bit better as opposed to how it currently has a hard
line that things just appear out of", "and the feel seems to always say 'in between' if we can tune that
up a bit as well". The spec is the session scratchpad's `uplan/slice-mandala-feel.md`; two builders were
cut off by usage limits part way, the third audited and finished their work, and a review then found
thirteen problems and a second review eight more, every one fixed (below, "After review" and "After a
second review"). The spec named it 2.0.0-player.31; player-spike took .31 to .33 meanwhile, so it ships as
.34. The frames, the harnesses and every measurement are in the scratchpad (`work/builder/b31/`,
`work/viz/shots/`, `work/builder/feel/`, the first review's fixes in `work/fixer31/`, the second's in
`work/fixer31b/`).

- **Busy, as frames showed it**: a lattice of tiles filling the whole screen behind the figure, lines
  burnt to white with a wide glow, a flare across the middle, every layer (the echoes of the lines, the
  band of cells, three rings) at once - and, found looking closer, three more: each line dragging a stack
  of about seven echoes (the trail's feedback kept 74% a frame and moved outward 0.9%), a rainbow fringe
  on every ring, and the tiles cut off along their square cells' edges (below).
- **One figure with room round it** (`uRoom`, `mandalaMorph`'s `room`): the figure fills a disc of the
  screen - `room[0]` 0.43 of its height for smooth music, 0.39 for aggressive (of its width, on a screen
  taller than it is wide), faded from 0.9 to 1.15 of it, so it has gone by 0.49 of the height, inside the
  screen's top and bottom (review) - and beyond it the pattern carries on only at 0.11 of the deep colour
  (`uFlare`), and only some of the time; the echoes and the band of cells each come and go on slow curves
  of their own. Across ten minutes of the clocks: the faint pattern beyond 30% of the time, the echoes
  34%, the band 29%, none of them 37%, 0.92 at once on average (`visualizer.sim.cjs` holds the numbers -
  each under half, the average under one - and since review the shader to scaling each layer by its own).
  The lines: a base width of 0.0038 (was 0.0046) times 1.2 to 1.5 as the feel rises (was 1.3 to 1.0),
  and a glow tail of 0.25 to 0.12 (was 0.45 to 0.06) - so as the feel rises a line is drawn wider with
  less glow beside it, harder, never fainter (review). Against before, smooth music's lines are thinner
  (0.0046 against 0.0060) with less glow, and aggressive music's WIDER (0.0057 against 0.0046) with more
  (a tail of 0.12 against 0.06); the rings two not three and in one colour, the core
  smaller, the flare gone, the polygon's fill fainter (0.08 to 0.03, was 0.14 to 0.05) and read from the
  polygon's own outline (review), and a pile of glow scaled down in all three channels together
  (`col *= (1 - exp(-1.5 peak)) / peak`), so it keeps the cover's colour instead of burning to white. The
  trail keeps 60% a frame less 0.018 (74% less 0.012), so a line drags three or four echoes, not seven -
  it still flows. It still leans with the feel: smooth music wide, round and soft; aggressive tighter,
  pointed and harder.
- **The hard line: the mirror count.** It glided between whole numbers (`glide([6, 8, 5, 12, 7, 10, 4,
  9])`) through one fold, `seg * tri(a / seg)` with `seg = 2 pi / N`; between whole numbers the wedges
  don't close round the circle, so one partial wedge sat at atan's wrap - 2.0.0-player.20 took the TEAR out
  of it, but it stayed a radial line shapes were born out of or vanished into, for every glide. Now the
  count changes only by a FOLD (`MIRROR_COUNTS` 8, 4, 12, 6, 3, 9, 3, 6, 12, 4, round and round - each step
  twice or three times as many, or a half or a third; 5, 7 and 10 went, no fold reaches them): the angle is
  folded into `uOuter` whole wedges (the lower of the two counts), then each wedge folded AGAIN at the
  count as it swings (`uFold.x`). The second fold reads only the first's answer, so the picture is mirrored
  about every outer mirror line and every wedge is like every other at every moment, and it is exactly the
  whole count's fold at each end. In between, a new mirror swings inside every wedge at once, from the
  outer wedge's half line in to its place, or back out to it as the count halves (its angle, pi / count,
  moving evenly - `mirrors()`, eased over the last 38% of a 16-beat phrase): what meets it meets its own
  reflection, as in a kaleidoscope, never an unmirrored edge. `foldAngle()` is the shader's fold in
  TypeScript; `visualizer.sim.cjs` holds the two to each other, the folded angle continuous across every
  mirror line and the wrap for every moment of every swing (7,200 points round the circle, eleven moments
  each), equal to the whole fold at both ends - the end taken a hair before the phrase does, while the
  swing is still its own (review) - the same either side of a phrase's end where the outer count changes,
  the swinging mirror's angle moving evenly with the eased swing, the 16 and the 62% themselves, and the old
  way (6.5 in one fold) failing. Not the spec's other suggestion, `mix(fa, fa2, t)`: at t = 0.5 it maps half
  of each wedge to a single angle - radial streaks.
- **Proved in rendered frames** (the real `GlAmbient` and shaders in a file:// harness, the clocks driven,
  nine frames through every one of the ten swings, the picture sampled round circles at six radii;
  `measure2.cjs`): with the trail cleared, the worst of the outer wedges against the typical one, over
  the circle's contrast, was at most 0.061 mid-swing (median 0.005) against 0.93 median and 1.26 at worst
  for the old glide 6 to 8; the picture either side of every mirror line - outer and swinging - 0.02
  median (0.34 at worst, at one radius of one frame) against 1.5. With the trail on (it
  turns and swirls in screen space, so no line is a mirror of it) the odd-wedge median is 0.02-0.06
  against 0.98. Measured again on the shader as the review left it (four radii, the ten swings): odd
  wedge 0.003 median, 0.081 at worst; mirror lines 0.019 median, 0.20 at worst. In the real page the
  2.0.0-player.20 seam check (the rows either side of the centre line, left against right) read 1.13 at
  most over 20 frames, on localhost and on a non-secure origin.
- **The tiles were cut off too**: each cell of the source's tile pattern held one polygon, turning
  (`rot(t * 0.07)`), and a corner or a star's spike reaches up to 0.86 of a cell from its centre - past
  the cell's edge, where it was cut along a straight line, and spikes appeared out of that line as the
  tiles turned (worst for aggressive music, which brings stars and triangles). Each tile is now the union
  (a signed min) of its own polygon and the three in the cells round the corner the point is nearest, and
  the band's cells the nearer of the cell's and the next one along. `visualizer.sim.cjs` ports the
  polygon and both fields to JavaScript (held to the shader's lines) and measures a line's brightness a
  hair either side of every cell edge, over sides 3 to 8, stars, rounding and turns: a jump of 0.00003
  (0.0001 for the band) against 1.25 cut off. Across a cell's midline, where the four tiles chosen change,
  it moves under 0.0001.
- **The cost, in one pass as before**: three more polygons a pixel cost about 13% in SwiftShader (CPU
  WebGL, 1440x900); the rings in one colour (the fringe split each into three) save about the same, and
  the figure is worked out only where it or the faint pattern shows (`if (inside > 0.0 || faint > 0.0)` -
  exact: every colour it adds is scaled by one of them, and `visualizer.sim.cjs` checks that line by
  line). Averaged over twelve moments of a song: 65.0 ms a frame against 69.4 before. Uniform branches
  were tried for the band and saved nothing in SwiftShader, so there are none; a GPU was not measured. The
  review's fixes add nothing a pixel (the fill's field is a copy kept, the disc's reach one `min`).
- **The feel: always "in between", and why.** The board tuned its weights and ranges on three synthetic
  songs. Through the page's real pipeline, offline - the copy decoded at 48 kHz and down-mixed as 0.5 (L +
  R), the analyser emulated as `player/vizAudio.ts` sets it (FFT 2048, Blackman, no smoothing, -90..-22 dB
  to bytes, read 60 times a second), `bandLayout`/`bandsFromBins`, then `musicFeel` - 27 Kevin MacLeod
  tracks (incompetech.com, CC BY 4.0; seven calm, six between, seven heavy, two that build, five more kept
  out) and 17 louder or quieter copies (+3 to +8 dB, -10 dB) put 98% of the old score between 0.03 and
  0.76: calm 100% smooth, between 70% in between, heavy only 28% aggressive. **The emulation was checked
  against Chromium's own AnalyserNode** (an OfflineAudioContext, four tracks, 474 frames each): 100.0% of
  the bytes equal at the right alignment, none more than 1 off; and the down-mix within 2e-7 of 0.5 (L + R).
- **The readings, as the review left them** (`musicFeel`): onsets a second, counted on a grid of 60
  samples a second whatever the screen's frame rate (the flux between the spectra held at each sample,
  the threshold and its rising edge run once a sample, a frame late by n samples spreading its flux over
  the n); the share of the sound above about 2 kHz (band 43 up); and the flatness of bands 20-63 - the last
  two read in a window `LEVEL_WINDOW` 0.7 (about 48 dB) deep below the loudest band, each band by how far
  it stands above the window's bottom, the bottom never below the analyser's floor (`LIFT_FLOOR` 0.03).
  `aggr` follows its target over `AGGR_FOLLOW_S` 2 s. The crest factor (a 28 ms, gain-controlled waveform:
  it told calm from heavy not at all) and the centroid (nothing the share above 2 kHz didn't) went, and
  with them `musicFeel`'s waveform argument.
- **The new score** (`FEEL_SCORE`, `feelScore`): each reading followed over 5 s, then a smoothstep between
  [counts nothing, counts in full] with a weight - onsets a second [2.9, 5.5] 0.31; the share above 2 kHz
  [0.025, 0.17] 0.5; flatness [0.025, 0.23] 0.19. What real music gives (each track's middle): calm 2.7-4.9
  onsets a second, 0.00-0.04 above 2 kHz, flatness 0.02-0.23; between 2.8-6.3, 0.02-0.11, 0.11-0.55; heavy
  3.5-6.1, 0.09-0.17, 0.43-0.82 - flatness tells calm from the rest, the share above 2 kHz heavy from
  between, onsets lean both. The window and the ranges were searched together (random sampling and then
  refinement, windows 0.5 to 0.8, scored on calm reading smooth, heavy aggressive, between in between and a
  level change moving nothing) on the twenty calm, between and heavy tracks and their copies at realistic
  loudness (never the five kept out, nor the two that build), held wide, then rounded. The thresholds stay
  0.34 and 0.67.
- **How real music reads now** (share of time smooth / in between / aggressive, after the first 10 s):
  calm 98-100% smooth (96% at worst, Immersed 8 dB louder); between - Funkorama 0/68/32, Funky Chunk
  0/86/14, Happy Alley 11/89/0, Surf Inspector 0/80/20, Werq 18/74/8, and Bummin on Tremelo 100/0/0 (a
  sparse, clean tremolo guitar); heavy 87% aggressive on average (Pump and Club Diver 100, Burn The World
  Waltz and Summon the Rawk 99, Neolith 91, Harmful or Fatal 63, Metalmania 55 - its onsets are its only
  difference from Funky Chunk); the two that build cross words (Devastation and Revenge 42/38/20, Long
  Time Coming 0/51/49). **Kept out of the tuning**: Summer Day and Ether Vox (calm) 100% smooth; Chill Wave
  (a relaxed synth groove) 67/27/6; and the two heavy ones read mostly IN BETWEEN - Breakdown 0/97/3, with
  less above 2 kHz (0.04) than any heavy track tuned on (0.09-0.17); Cool Rock 23/74/3, whose top end and
  flatness are heavy music's but whose onsets are sparse (3.7 a second) for its top end (0.11, the low edge
  of heavy). They are reported, not tuned to (review: an earlier version gave Cool Rock's reason as
  little top end too, and the sim required both to stay in between).
- **A level change, and the screen's frame rate**: 3 dB louder or quieter moves a track's middle aggr
  0.01 on average (0.04 at most); 6 dB either way 0.025 on average, 0.11 at most (Metalmania 6 dB louder,
  at the analyser's top - 0.09 at most 6 dB quieter); 10 dB quieter 0.05 (0.15, quieter reading smoother)
  - against 0.11, 0.17 and 0.28 at most before review, when the brightness and noisiness were read
  against the floor.
  It isn't nothing: where the loudest band is quieter than about -40 dB the window stops at the floor
  (quiet music, or a quiet passage of it, reads a little smoother), and where a loud record's loudest
  bands pass the analyser's -22 dB top they read as -22 and it reads a little more aggressive (Metalmania 6
  dB louder, 0.68 to 0.79). A track standing on a word's edge still changes word with a few dB (Chill Wave
  89% smooth 6 dB quieter, 44% 6 dB louder). Read at 120 and 144 frames a second, every track's middle aggr
  moves 0.01 on average, 0.08 at most (counted per frame, before review: Dreamer 99% smooth at 60 fps, 3%
  at 120). **Below 60 the grid can't help, and at 30 it reads a long way off** (second review): the
  analyser is read half as often and an onset between two reads is lost in their flux - 31% of them on
  the median track (9% Bummin on Tremelo to 53% Gymnopedie; Club Diver 5.29 a second to 3.42) - so heavy
  tracks fall from 87% aggressive on average to 59% (Burn The World Waltz 99% to 26%, Club Diver 100% to
  63%, Metalmania 55% to 0%), between ones drift smooth (22/66/12 to 43/56/1; Happy Alley 89% in between
  to all smooth), calm ones stay smooth; the share above 2 kHz and the flatness don't move. 30 is
  ordinary on a laptop: Chrome's Energy Saver halves a page's frame rate (whether Arc offers it isn't
  known). Not compensated: the variant tried - a late frame's whole flux tested in its first grid sample,
  0 in the rest, the envelope as it is - brings heavy music back at 30 (Burn, Club Diver, Summon 100%,
  Metalmania 67%) but reads between music more aggressive than 60 does (28% against 12%; Funkorama 90%)
  and calm a little less smooth (Dreamer 87%, Immersed 91%), and changes nothing at 60 or above; a
  choice for James, not made. The guide and the troubleshooting page say what 30 does, and
  `musicfeel.sim.cjs` holds the made-up calm piece read 30 times a second to seeing fewer (2.07 onsets a
  second against 2.78), so a compensation has to change that check and those words together. Reads
  aligned to 128- or 512-sample renders, as a real page reads the analyser between them, move the middle
  aggr 0.01 on average, 0.09 at most.
- **The fixture**: `tests/fixtures/feel/real-tracks.json` holds the numbers (never audio) - per track its
  kind, whether held out, its loudness, the readings once a second, and the shares under this tuning and
  (for the tracks it held before) the board's - for the 27 tracks and 31 copies of 16 of them: the
  builder's (louder calm tracks, quieter and louder heavy ones) and every track that stands near the floor
  - Dreamer, Chill Wave, Late Night Radio and Bummin on Tremelo - 3 and 6 dB either way (review).
  `musicfeel.sim.cjs` replays the readings through `feelScore` (following over `AGGR_FOLLOW_S`) and holds
  every track to its shares within 3 points, the classes to what they are, a level change to 0.04 on
  average and 0.12 at most, and the held-out five only in the direction that matters (calm smooth, heavy
  never mostly smooth, the groove never mostly aggressive). Retuning means making the fixture again (the
  sim checks its tuning - `FEEL_SCORE`, `LIFT_FLOOR`, `LEVEL_WINDOW`, `AGGR_FOLLOW_S` - is this one); how
  onsets are counted is held by the numbers themselves (the board's songs, a busy click and a made-up calm
  piece, to the third and second decimal).
- **Only the Mandala takes the feel** - `mandalaMorph`'s A and `mandalaFlow`'s twist, as since
  2.0.0-player.20; Waves, Liquid and the five feedback styles take the tempo alone (the spec supposed
  otherwise; their frames at A 0 and 1 are identical). The README and the guide say so.
- **After review** (thirteen findings, each confirmed by skeptics; every one fixed):
  - **The polygon's fill had hard edges fill appeared out of** (major). `dPoly` became the nearer of the
    polygon's outline and the tiles', with its own sign - and where the two were as far away with opposite
    signs (a curve on no drawn line) the fill went from full to nothing in one pixel: a flat brown disc with
    rectangular bites, the bites changing shape as the tiles turned - the most visible hard line left once
    the bloom was gone. The fill is read from the polygon's own field, kept before the tiles are taken in
    (`dCore`), and fainter, since it now fills the whole polygon: the fill's own contribution jumping by
    over 0.1 between neighbouring pixels at smooth feel, 1440x900, songs at 455, 210 and 140 s - 2025, 1897
    and 847 pairs before, 0, 0 and 0 after. The sim walks lines across the tiles: 113 jumps from the
    nearer outline, 0 from the polygon's own.
  - **Aggressive music went nearly empty and dim** (major): thinner lines (1.2 to 0.95) broke into faint
    dashes. Over ten minutes of the clocks from two places (480x300, the share of the screen brighter than
    0.25): at full aggression the middle share 10.0-10.5% and under 5% lit 10-12% of the time, stretches of
    11 s - now 13.7%, 3.5-4.0%, 5 s at most; at 0.8, 7.3-8.7% of the time became 2.5-3.5%. The lines are
    wider as the feel rises (`edge[1]` 1.2 to 1.5) with less glow (0.25 to 0.12).
  - **At smooth feel the figure ran off the top and bottom** (minor): its fade ended at 0.6 of the height,
    the edges at 0.5, so lines crossed them at 70% of their brightness while the sides faded to black -
    cropped, not room. The fade now runs 0.9 to 1.15 of `room[0]` (0.43 smooth, 0.39 aggressive), scaled to
    the width on a portrait screen; the brightest pixel in the top and bottom 3% (centre square) over ten
    minutes, 0.79-0.81 at worst, is 0.35 - the faint pattern beyond. The cost, stated: the outer ring the
    sides used to show is gone, so a smooth figure lights 12.8-13.2% of the screen (16.1-16.6% before) and
    is under 5% lit 7-8% of the time (3-5%) - its sparse moments, a ring or a faint hexagon while the kind
    of figure changes, were there before, a little brighter.
  - **The feel moved with the level** (major): the brightness and noisiness counted how many high bands
    cleared the analyser's -90 dB floor, so a calm record turned up read in between (Dreamer 85% smooth 3 dB
    louder, 39% at 6; Chill Wave 51% to 27%), and a hi-res song - analysed from its resampled copy, 3 dB
    lower - read differently by the quality setting. Now the window (above), and the numbers above.
  - **The feel moved with the frame rate** (major): onsets were counted per animation frame, so a 120 Hz
    screen (Arc and Chrome draw at the display's rate) counted half as many again - Dreamer 3/97/0, Funky
    Chunk 0/8/92. Now on the 60-a-second grid; `musicfeel.sim.cjs` puts a made-up calm piece through the
    analyser emulation at 60, 120 and 144 fps (2.78, 2.97, 2.88 onsets a second; per frame 2.78, 4.18,
    5.03).
  - **Tests that held less than they said**: the echoes and the band now pinned to `uRoom.z` and `uRoom.w`
    in the shader (removing either left every check green); the phrase-boundary checks could not fail (one
    ended in a clause always true, one rounded the count it tested, the ends were sampled at the next
    phrase's start) - a swing stopping 98.5% or 99.7% of the way and cutting at the phrase's end passed
    them all, and fails now; the even swing and the 16 and 62% were unpinned (a straight count glide
    passed); the real-track replay followed over its own 2 s, not `musicFeel`'s (`AGGR_FOLLOW_S`, and a
    check of one frame's follow); how onsets are counted was unpinned (a 3 s window, a 1.2 threshold, a
    0.04 floor all passed); and the held-out heavy tracks were required to read in between - a tuning that
    read them aggressive would have failed.
  - **Words**: the guide's "most pop, funk and lighter rock in between" - no pop was measured, and the one
    light guitar track reads smooth; the old trail given as 72% a frame (it was 74%); Cool Rock's reason.
- **After a second review** (eight findings, each confirmed by skeptics; every one fixed):
  - **The version** (major): the spec's 2.0.0-player.31 was taken on player-spike by then (the voice's
    counted clock, then .32 and .33), so this change carries .34 everywhere it names itself - `__version__`,
    this section, the troubleshooting page, the source comments, both sims and the fixture's `about`
    (free text, read by no test; the fixture's numbers unchanged).
  - **The guide called the drop at 30 frames a second "a little smoother"** (minor): heavy music falls
    from 87% aggressive to 59% (Metalmania to 96% in between), and between music drifts smooth - the
    numbers and the variant tried are under "A level change, and the screen's frame rate". player.md, troubleshooting.md and musicFeel.ts now say what 30
    does and what brings it on, and `musicfeel.sim.cjs` holds the calm piece at 30 to seeing fewer.
  - **The figure's disc was not pinned on the main lines** (minor): the skip check asked only that each
    line adding colour named `inside` or `faint`, and the main lines' one line adds two terms, so
    `(uBody * 1.5 + uFlare * faint)` - the figure off its disc, a hard edge at 1.15 of its reach or
    full-strength lines across the screen - passed every sim. The check is term by term now (each
    additive term a product with `inside` or `faint` as a factor, or a bracketed sum each term of which
    is; a function's arguments never count), with its own cases; that mutation and three like it fail.
  - **Words**: the 6 dB level figure (it said 0.09 at most, either way: 0.11 louder, 0.09 quieter, 0.025
    on average); the shader's header claiming thinner lines with less glow (true of smooth music only:
    aggressive music's are wider than before, and carry more glow); the held-out check's comment (it
    described the check the first review removed); a blank line missing before the next section; and
    pointers from the 2.0.0-player.20 section to this one, where its feel and its gliding count are
    described as they were.
- **Verified**: 2354 Python tests (none new), pyflakes, tsc, the bundle, all 43 sims (`visualizer` - the
  fold, the swing's even angle and its ends, the room and its layers in the shader, the disc inside the
  screen, the tiles and cells, the fill from the polygon's own field, the clean lines - and `musicfeel` -
  the grid, the window, the follow, the onsets held, the real tracks - extended). Mutations, each on a
  scratch copy and restored byte for byte: the builder's 17 that still apply (adapted to the code as it
  is), 16 for the visualizer's fixes and 15 for the feel's - every one caught (three first got past - the
  polygon's field reassigned after the tiles, the onset threshold's 0.02 made 0.04, the grid's follow
  taken from the frame's own dt - and gained the checks that catch them). After the second review those 48
  were run again on the final code (all caught), with 7 more for its fixes, all caught: the main lines'
  figure term and their faint term each left unscaled, `inside` moved into a function's argument, an
  unscaled term added to the band's line (the old per-line check let the first through; reverted alone,
  with the shader right, it changes nothing, as it should), the term rule letting a function's arguments
  scale, and a late frame's flux tested whole in its first sample or not divided at all (the 30-frames
  check). The engine guard is empty. **In the real page** (this worktree's deadwax on :8097, headless
  Chromium with SwiftShader): a song plays, the visualizer opens on Ambient > Mandala, the silent copy
  fetches a scrub window, an AudioContext runs (48 kHz, its clock moving), the WebGL Mandala draws and
  moves inside the screen, the seam rows hold, the readout says the feel, no console errors - on localhost
  and on `http://deadwax.test:8097`.
- **NOT verified - James's eyes and James's music**: whether it now reads as calm and rich, not empty
  (smooth music lights less of the screen than before review, by design); the morph in motion at real
  speed on his GPU (the frames are a clock driven by hand); the cost on a real GPU; how his library reads
  (the tuning saw incompetech's library music, not Metallica or Portishead - and modern masters, louder
  than these, crowd the analyser's -22 dB top more often); WebKit's analyser (Safari's FFT scaling, never
  checked here); a 44.1 kHz context (the bands are the same frequencies, the bins a little narrower); and
  whether Arc on his laptop's battery draws at 30 frames a second (where heavy music reads in between).
