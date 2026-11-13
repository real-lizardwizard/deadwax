# The EQ, on the iPhone

Designed 2026-11-12 against the app at `ios` b03ac65 (app 0.3 (3), Phase 2's Downloads merged; main's 2.1.6 merged in)
and the server at main 47aed14 (2.1.6). Line numbers are the code's at those commits. Nothing here is built yet: the
app is built to this spec, slice by slice (section 5), and reviewed against it. Reviewed the same day ("Design review
(2026-11-12)", at the end): Equalizer APO's own source read and every filter form it plays pinned from it, the
render's denormals, bank handover and warm start, the preamp's search, the GraphicEQ fit and the click test measured
by simulation, AutoEq's data read at its commit, and the screens' words, pages and suggestion.

**What James decided** (`~/Desktop/Code/deadwax-plans/eq.md`, its "Decided (James, 2026-11-12)", binding; from
`~/Desktop/Code/deadwax-ios-plan.md`'s "EQ (decided 2026-11-12)"):

- The iPhone app only; the web stays untouched.
- Presets - the short set by purpose (Flat, Bass Boost, Bass Reduce, Treble Boost, Treble Reduce, Vocal, Loudness,
  Small Speakers, Spoken Word), plus your own - and a 10-band graphic EQ, and AutoEq corrections for headphones.
- An **Advanced** switch: a full parametric EQ, and Equalizer APO `.txt` import. **GraphicEQ: files are converted to
  filters** (close to the curve, not exact) - not refused.
- A setting **per output**, switched by itself when the phone's route changes.
- **The automatic preamp**: minus the curve's highest boost, the same for every song on an output; set by hand in
  Advanced.
- **Filters our own, in Core**: Equalizer APO's formulas (the RBJ cookbook) in Double, the same code in the player,
  the deck and the drawn curve.
- **Off is bit-exact in the graph**: the unit stays in and passes every sample through untouched, measured; taken out
  at the next stop only if that measurement fails.
- **AutoEq through deadwax's server**, a 2.1.x patch on main.
- Every other question at the plan's recommendation: a correction and a tone stacked as one curve; a new output starts
  Off, with an AutoEq suggestion when its name matches; `Channel:` L and R as two curves; Files, Paste and the share
  sheet; You > Playback plus Now Playing's •••; ±12 dB in 0.5 dB steps.
- **When**: next - after the turntable's slice 1 (being built now), before its slices 2-4.

And: "let's not cut corners on design, I like the direction things have been going." So this is written as the
turntable's and Phase 2's specs are: each part read from the code it touches, cited; every word verbatim; VoiceOver,
Dynamic Type and Reduce Motion for each part; errors in a listener's words; the app's own look; and, where the app has
no precedent, Apple's pattern, named, with how sure I am of it.

There is no web EQ to port, so there is no **Phone:** marker here. Where this spec departs from the plan it says so in
a line marked **Changed from the plan:**, with why. Section 8's open questions each carry the recommendation the build
follows until James answers.

---

## 0. The foundation, checked

Everything below rests on these. Each was read, not remembered, unless it says otherwise.

### 0.1 The engine as it is (`ios/DeadwaxKit/Sources/DeadwaxAudio/PlaybackEngine.swift`, 2165 lines)

| where | what it does, and what the EQ needs from it |
| --- | --- |
| header :122-156 | One AVAudioPlayerNode per format lane; GainedSource's multiply before it; the lane's own AVAudioConverter (mastering, `.max`, prime `.normal`) when the file's rate isn't the output's; "the main mixer at unity"; "Every node runs at the output's rate, so the mixer itself converts nothing." The EQ keeps all of this. |
| `Settings` :158-180 | `idleStopSeconds` 0 (:167: a pause stops the output at once), `changeSettleSeconds` 0.3 (:173), `offline` (:177: the tests' manual rendering format). |
| `configure` :569-581 | Manual rendering at 4096 frames (:571); touches `mainMixerNode`; observes `AVAudioEngineConfigurationChange` (:577-580). Called from `init` (:559-563) and again from `rebuild()` (:698) on a new engine. **The EQ unit is attached here**, so a rebuilt engine gets one too. |
| `rebuild` :688-714 | After media services reset: a new AVAudioEngine, configured again; play goes on from where it was heard. |
| `renderOffline` :719-771 | The tests' render, through the real graph; a stopped output renders silence (:749-757). |
| `ensureRunning` :911-940 | `matchOutput()`, `engine.prepare()`, `engine.start()` - the one place the output starts. **The EQ's curve for the route is put in here**, between prepare and start (1.8). |
| `sleep` :943-954 | `engine.stop()` - every pause, the queue's end, a stop, a failure. |
| `matchOutput` :956-978 | Connects the main mixer to the output at the hardware's rate, only when they differ (:965-971), with the mixer's channel count, or the hardware's capped at 2 (:966); lanes made for another rate are let go. Never offline (:961). **This becomes mixer -> EQ -> output.** |
| `reset` :982-1005 | Every pause, resume, seek and skip: the lanes cleared, each lane's converter reset. |
| `laneFor` :1014-1037 | The lane's node connected to the main mixer (:1032) - where the turntable's fader puts its varispeed (turntable.md 5.2). The EQ doesn't touch it. |
| `pauseNow` :1991-2006 | `reset()` then `sleep()`: the output off at once ("The pause the lock screen didn't see", notes/ios.md). |
| `configurationChanged` :2051-2087 | iOS stopped the engine (a new route or hardware format): lanes detached and made again, `matchOutput()`, `sleep()`, and play goes on after the 0.3 s settle, so the pause for the old device going wins (:2070-2086). |
| `publish` :2130-2163 | `outputRate` from the output node's format (:2156-2157). |

So: **every play after a pause, every route change and every media reset passes through `ensureRunning` with the
output stopped**, and nothing sounds while it is stopped. That is where a new output's curve goes in, with nothing to
click.

### 0.2 The app as it is

- **The audio session** (`ios/App/AudioSessionController.swift`, 89 lines): `.playback`, `.default`, `.longFormAudio`
  (:52-54); its route callback fires only for `.oldDeviceUnavailable` (:36-42) and is a single closure PlayerModel owns
  (`PlayerModel.swift:212-214`); `outputName` is `currentRoute.outputs.first?.portName` (:88), read for Hi-res
  (`PlayerModel.swift:691`). No preferred IO buffer is set. The EQ observes `routeChangeNotification` itself, as the
  turntable's DeckController does (turntable.md 4.6), and never changes the session.
- **You > Playback** (`ios/App/You/PlaybackSection.swift`, 66 lines): a Section for Gapless (header "Playback", the
  line as footer), then Normalization's radio rows (checkmark in `Palette.accent`, `.isSelected`,
  `.accessibilityElement(children: .ignore)`) with its note and `YouWords.kept` as the footer. The turntable's slice 3
  puts two Sections between them (turntable.md 6.1). `YouView` (`ios/App/You/YouView.swift:33-41`) draws Playback,
  Downloads, Account, About, This phone in a `List`.
- **Now Playing's •••** (`ios/App/Player/NowPlayingMenu.swift`, 79 lines): a SwiftUI `Menu` - Info, Go to album, then
  Phase 2's download section and Download Up Next; `.menuOrder(.fixed)`; its label `NowPlayingWords.more(hasAlbum:download:)`
  (`DeadwaxCore/Info.swift:422-424`): `"More: info, go to album, download"`. Now Playing presents Up Next and Info as
  `.sheet`s (`NowPlayingView.swift:36-37`).
- **Info** (`ios/App/Info/InfoView.swift`): About's Sound section (:147-155) - Core's three rows (Format, Gapless,
  Normalization; `LevelWords.soundRows`) and the phone's own Plays from (:154). Debug's "Sent to this device" ends with
  the engine's rows (`Info.swift:316-338`: Output, Conversion, Lane, Buffered ahead, Last start).
- **Debug** (`ios/App/You/DebugView.swift`, 372 lines): Engine log, Downloads, deadwax, Library, Test sounds, Hi-res,
  Playing - each a Section of `LabeledContent` rows.
- **The Palette** (`ios/App/DeadwaxApp.swift:73-107`): `accent` #C084FC, `quiet` (Color.secondary), `amber`, `danger`,
  `held`, `barTrack` #121117, `barEdge` #2c2a36, `barFill`, `off` 0.45 - each named for its web token. The app is dark
  only, portrait only, iPhone only, iOS 17.0.
- **Pages pushed** are `AppRoute` cases (`ios/App/Shared/Routes.swift:12-26`) drawn by `appRoutes()` (:135);
  `AppNavigation` (:78) holds each tab's path and `nowPlayingShown`.
- **The package** (`ios/DeadwaxKit/Package.swift`): iOS 17 / macOS 14; CSQLite, DeadwaxCore (pure, Linux-tested),
  DeadwaxAudio (Swift 5 mode, macOS-tested). No C target of our own yet: the turntable's `CDeckRing` (turntable.md
  4.3) is its slice 2's, not built.
- **The app's routes**: 23 `Endpoint` lines in `DeadwaxCore/Routes.swift`; `tests/test_ios_contract.py:49`
  `ROUTE_COUNT = 23` on `ios` - **24 at the review** (`ios` f92ecdb: the lyrics' route, 8ffe7ec, `ROUTE_COUNT` at
  :55), so every count below is "two more than it is when the slice lands". On main, Routes.swift is Phase 0's (7 lines) and the test has no count.
- **The server**: `src/__init__.py` says 2.1.6. Every route is decided in `tests/test_logins.py`'s `ROUTES` (:90 on;
  the describe routes, an outside source behind a signed-in user, are `"user"` at :207-208).
  `test_there_is_no_general_proxy` (`tests/test_navidrome.py:229`) holds the Navidrome routes to a fixed list.
  `src/api/wikipedia_endpoint.py` is the pattern for asking an outside service (one httpx client, deadwax's user agent
  per request, a 404 as "none", anything else `Unreachable`); `src/routes/describe.py` for keeping its answers.
- **SF Symbols** used here, each looked up in this Mac's
  `/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist`, as Phase 2 did: `iphone`
  14.0, `headphones` 13.0, `airpods` 14.0, `airpodspro` 14.0, `airpodsmax` 14.5, `beats.headphones` 15.0, `car` 13.1,
  `cable.connector` 15.0, `airplayaudio` 13.0, `tv` 13.0, `slider.vertical.3` 14.0, `wand.and.stars` 13.0,
  `magnifyingglass` 13.0, `doc.text` 13.0, `doc.on.clipboard` 13.0, `square.and.arrow.up` 13.0, `plus` 13.0, `trash`
  13.0, `checkmark` 13.0, `exclamationmark.triangle` 13.0. Not used: `airpods.pro` and `airplay.audio` (iOS 18.0).

### 0.3 Equalizer APO's syntax (its "Configuration reference", sourceforge.net/p/equalizerapo/wiki, read 2026-11-12)

- `Filter <n>: ON <Type> Fc <f> Hz Gain <g> dB Q <q>`, or `BW Oct <b>` in place of `Q`; the number `<n>` "is not
  interpreted and can be omitted".
- Types: PK (also written `Modal` - with a `T60 target` - and `PEQ`), LP, LPQ, HP, HPQ, BP ("a real band-pass" with no
  gain), NO, AP, LS and HS (a **centre** frequency; Q optional "since 1.2.1"), `LSC x dB`/`HSC x dB` (a slope in dB
  per octave), `LS 6dB`, `LS 12dB`, `HS 6dB`, `HS 12dB` (a **corner** frequency), and `IIR Order <m> Coefficients …`
  (raw coefficients, which "usually depend on sample rate"). **The page gives no default Q, slope or width for any
  type**, and doesn't say how a centre frequency becomes the formulas' own.
- `Preamp: <n> dB`; "since version 0.8, multiple preamps on the same channel are summed".
- `Channel: <positions>`: L, R, C, LFE, RL, RR, RC, SL, SR, or numbers from 1, or `all`.
- `Device:`, `Include:`, `Convolution:`, `Delay:`, `Copy:`, `Eval:`, `If:`/`ElseIf:`/`Else:`/`EndIf:`, `Stage:`, and
  `GraphicEQ: <f> <g>; <f> <g>; …` - "interpolated linearly on a logarithmic frequency axis between the given points,
  and the response is flat outside them".
- "Non-conforming lines and unsupported command names are silently ignored." The examples use a decimal point.

**And its source** (the review, 2026-11-12: github.com/mirror/equalizerapo - the SourceForge SVN's mirror - at
53d885f7f1, 2024-09-27; GPL, so read for its conventions and described here in words, never copied). Where the page
and the source differ, the source is what plays, and it is what deadwax follows:

- **A line** (FilterEngine.cpp): split at LF, one trailing CR dropped (so CRLF and LF; a CR alone is not a line end).
  Decoded as UTF-8, and again as the system's ANSI code page if that produced a U+FFFD. The text before the first `:`
  is the command, its spaces trimmed (indentation allowed); the rest, untrimmed, its parameters. A line with no `:`
  is nothing. **There is no comment syntax**: a `#` line does nothing only because no command begins with `#`, and a
  `#` partway along a line is read like any other text. **Commands are matched exactly, case and all**: `Preamp`,
  `Channel`, `GraphicEQ`; a filter's command is anything that *begins* `Filter` (`Filter`, `Filter 3`, `Filter3`).
  `preamp:` or `filter 1:` is a command APO doesn't know.
- **A filter** (filters/BiQuadFilterFactory.cpp): every comma in the parameters becomes a point first (so `Gain 6,5
  dB` is 6.5 dB). Then, each found anywhere after the type, first match wins: the type is the letters after `ON` and
  a space (so `OFF` plays nothing, and `LS 6dB` is the type `LS` followed by `6dB`); `Fc <n> Hz` (the **Hz is
  required**, a space allowed inside it; a non-breaking space in the number dropped; and a number of five or more
  characters with no exponent whose fourth character from the end is a point is **read as thousands** - REW's
  `1.000` is 1000 Hz); `Gain <n> dB` (the **dB is required**); `Q <n>`; `BW Oct <n>`; and, only straight after the
  type, `<n> dB` - a slope. Numbers are C's `wcstod` of a run of `-+0-9.eE`. Type names are exact: `PK`, `PEQ`,
  `Modal`, `LP`, `LPQ`, `HP`, `HPQ`, `BP`, `LS`, `HS`, `LSC`, `HSC`, `NO`, `AP`; `None` is nothing; anything else
  (`IIR` is another factory's) is logged and left out.
- **What each type takes, and its defaults**: Modal is a **peak** - its `T60 target` is never read. A gain is read
  for PK, the shelves and BP (where nothing uses it) and ignored for LP, HP, NO and AP. Q is read, then BW Oct
  replaces it (except on a shelf, where BW is ignored), then a slope replaces both (shelves only). **With no width,
  or a width of exactly 0**: PK and AP are left out; LP, HP and BP take Q = 1/√2; NO takes Q 30; a shelf takes
  **S = 0.9** ("found out by experimentation with RoomEQWizard"). **But a `BW Oct 0` keeps its kind** (corrected in
  slice 1, 2026-11-12): the BW match sets the bandwidth flag (BiQuadFilterFactory.cpp:150-151) and the default only
  replaces the number (:177-189, the flag left as it was), so `BW Oct 0` on LP, HP or BP is a bandwidth of 1/√2
  **octaves** (BiQuad.cpp:41-42 - a Q of about 2.0, a 6 dB resonance), and on NO a bandwidth of **30 octaves**
  (nearly everything notched). A shelf's slope in dB becomes S = slope / 12 ("Maximum
  S is 1 for 12 dB"). A filter with no frequency, or a PK or shelf with no gain, is left out (logged) - the rest of
  the file plays.
- **Centre or corner** (filters/BiQuadFilter.cpp): a shelf whose type name doesn't end in `C` **and** that was given
  a Q or a slope (`LS … Q 0.7`, `LS 6dB`, `HS 12dB`) is read by its **corner** frequency, moved to the cookbook's
  f0 ("frequency adjustment for DCX2496"): S from the slope, or from a Q as S = 1 / ((1/Q² − 2) / (A + 1/A) + 1);
  then f0 = Fc · 10^(|gain| / 80 / S) for a low shelf, Fc / that for a high shelf. Every other shelf - `LSC`/`HSC` with
  anything, and `LS`/`HS` with nothing (S 0.9) - is the cookbook's at **f0 = Fc**.
- **The formulas** (filters/BiQuad.cpp) are the cookbook's, in double: `A = 10^(g/40)` for PK and the shelves; alpha
  `sin w0 / 2Q` for a Q, `sin w0 / 2 · √((A + 1/A)(1/S − 1) + 2)` for a shelf's S, `sin w0 · sinh(ln 2 / 2 · BW · w0 /
  sin w0)` for BW; BP is the constant-0-dB-peak band pass. Normalised by a0.
- **How it plays**: each filter is its own Direct Form I in double, but **its output is rounded to Float32 before the
  next filter** takes it; denormal states are zeroed after each block.
- **Preamp** (filters/PreampFilterFactory.cpp): commas to points, then a number (the `dB` after it optional).
- **GraphicEQ** (filters/GraphicEQFilter*.cpp): commas become points only if the line has no point at all; every run
  of `-+0-9.eE` is a number, taken in pairs (a last odd one dropped); **the points are sorted by frequency**. It plays
  as a **minimum-phase FIR of 16,384 taps** (the magnitude interpolated as the page says, made minimum phase by the
  cepstrum, half-Hann windowed) - so, like deadwax's filters, its phase follows its magnitude.

### 0.4 AutoEq (github.com/jaakkopasanen/AutoEq, read 2026-11-12)

- **The code is MIT.** Its biquads (`autoeq/peq.py`, `Peaking`, `LowShelf`, `HighShelf .biquad_coefficients`) are the
  RBJ cookbook's, exactly: `A = 10 ** (gain / 40)`, `w0 = 2 * pi * fc / fs`, `alpha = sin(w0) / (2 * q)`, the shelves'
  `2 * sqrt(A) * alpha` terms - with `fc` used as the cookbook's `f0` directly, and no other frequency adjustment. So
  **an AutoEq file's `LSC`/`HSC` with a `Q` is the cookbook's shelf at f0 = Fc**: that is the curve AutoEq computes and
  publishes for it - and what APO plays for it too (0.3: `LSC` is never moved to a corner). peq.py has no low or high
  pass. Its `DEFAULT_FS` (autoeq/constants.py) is 44100.
- **A result folder** (`results/<source>/<rig>/<name>/`, e.g. `results/crinacle/711 in-ear/Apple AirPods Pro/`) holds
  `<name> FixedBandEQ.txt`, `<name> GraphicEQ.txt`, `<name> ParametricEQ.txt`, `<name> minimum phase 44100Hz.wav`,
  `<name> minimum phase 48000Hz.wav`, `<name>.png` and `README.md`. **crinacle's folders have no CSV; others' do**
  (the review: oratory1990's `Sennheiser HD 650.csv` - `frequency, raw, smoothed, error, …, parametric_eq,
  fixed_band_eq, …`). Its `parametric_eq` is AutoEq's curve for its filters **before they were rounded** for the
  .txt: the cookbook over the HD 650's file at 44.1 kHz is within 0.11 dB of it (at 34 Hz, where a Q 3.96 peak at 37
  Hz was rounded), 0.03 dB on average - a cross-check, not a tight reference.
- **A FixedBandEQ.txt** (the review: the HD 650's) is ten peaks at 31, 62, 125, 250, 500, 1000, 2000, 4000, 8000 and
  16000 Hz, **Q 1.41**, with its own `Preamp:`.
- **A GraphicEQ.txt** is one `GraphicEQ:` line of 127 points from 20 Hz to about 19.9 kHz, AutoEq's preamp already in
  its gains (the HD 650's run from -16.0 to -0.2 dB).
- **A ParametricEQ.txt** (the AirPods Pro's, crinacle's):

  ```
  Preamp: -6.0 dB
  Filter 1: ON LSC Fc 105 Hz Gain 2.6 dB Q 0.70
  Filter 2: ON PK Fc 514 Hz Gain -4.4 dB Q 0.68
  …
  Filter 6: ON HSC Fc 10000 Hz Gain -0.5 dB Q 0.70
  …
  Filter 10: ON PK Fc 618 Hz Gain -0.5 dB Q 0.86
  ```

  Ten filters; Fc whole hertz, Gain one decimal, Q two.
- **The list**: `results/INDEX.md` - at master's 7ae0f56 (the review), 851,757 bytes, 8,850 results - "# Index", one
  line per result: `- [Apple AirPods Pro](./crinacle/711%20in-ear/Apple%20AirPods%20Pro) by crinacle on 711`. Only
  spaces are percent-encoded: parentheses, `&` and `+` appear raw (`…/1MORE%20Aero%20(ANC%20Off))`,
  `./HypetheSonics/Bruel%20&%20Kjaer%205128%20in-ear/…`, `Apple%20AirPods%20Pro%202%20(51dB%20+%20ANC)`); the rig
  folder carries the form (`711 in-ear`, `HMS II.3 over-ear`); "the target appears in parentheses when one source has
  multiple targets". The AirPods Pro appear from crinacle, Super Review, HypetheSonics and Rtings - and crinacle's
  **AirPods Pro 2** as fourteen rows of their own (corrected in slice 1, read again in INDEX.md at 7ae0f56: eleven
  listening levels with ANC, `Apple AirPods Pro 2 (51dB + ANC)` to `(91dB + ANC)`, and the ANC, passive and
  transparency modes) - beside HypetheSonics', Harpo's and Filk's `Apple Airpods Pro 2` and Rtings' `Apple AirPods Pro2`.
  The largest sources: crinacle 2,036, Innerfidelity 933, Super Review 885, Rtings 795, oratory1990 736.
- **Terms**: the repository's LICENSE is MIT ("Copyright (c) 2018-2022 Jaakko Pasanen"), and covers what is in it,
  results included; the measurements behind them are their sources' (crinacle's own data isn't published there).
  The README says the precomputed results are not meant for "normal users" now that autoeq.app exists (the plan's
  reading, kept). The default branch is `master`.

### 0.5 What this spec found that the plan didn't say

1. **AutoEq's CSV is no tight reference** (and crinacle's results have none): its `parametric_eq` is the curve of the
   filters before rounding, 0.11 dB from the file's own (0.4). So "AutoEq's own computed curve (from its result CSV)"
   is a cross-check at 0.15 dB, and the tight reference is AutoEq's own biquad code (peq.py's three functions, MIT,
   copied with its notice into the fixture script) over real ParametricEQ.txt files (5.1).
2. **Every form APO plays is pinned, from its source** (0.3, read in the review - the plan, and this spec's first
   draft, had only the documentation, which gives no defaults and no centre-to-corner rule). PK with Q, and LSC/HSC
   with Q, are the cookbook's at f0 = Fc - what AutoEq computes and APO plays. The rest follow APO's code: Modal is a
   peak; LP, HP, BP default to Q 1/√2, NO to Q 30 (a `BW Oct 0` to as many octaves), a shelf to S 0.9; a slope in
   dB is S = slope / 12; `LS`/`HS` with a Q or a slope (and so `LS 6dB`, `HS 12dB`) are moved from a corner to the
   cookbook's f0. Only `IIR` stays refused
   (3.9). The import's rule is still "play it as APO does, or say so" - and now nothing is a guess.
3. **`Device:` can't simply be skipped**: a file with two `Device:` sections holds two devices' filters, and skipping
   the lines would play both at once. One leading `Device:` line is skipped; several are refused (3.9).
4. **Unknown commands are ignored by APO**, so skipping them (with a note) plays the file as APO does; the commands APO
   does play and deadwax can't (`Include:`, `Convolution:`, …) are refused.
5. **The engine's start is the place to choose the curve.** Every pause stops the output and every route change stops
   the engine (0.1), so `ensureRunning` - between `prepare()` and `start()` - puts in the curve of the route as it
   starts. The route notification and the engine's change arrive in no set order (notes/ios.md, "A configuration
   change waits"), and this makes the order not matter.
6. **The C11 atomics the real-time handover needs don't exist yet** (turntable.md 1.3, item 1: `Synchronization.Atomic`
   needs iOS 18). The EQ comes first, so it makes the C target, and the turntable's slice 2 uses it (8, question 1).
7. **The turntable's route counts move**: the EQ's two routes add two to `ROUTE_COUNT` (24 at the review, after the
   lyrics' route), so the turntable's `scrub` and `discArt` (turntable.md 7.2, 7.3, written as 24 and 25 against 23)
   take the next numbers after them - whichever slice lands later counts from what the earlier left.
8. **The deck's EQ goes after its limiter, not before** (1.9; 8, question 2): the voice stays the web's port untouched,
   and the record's path matches the song's.
9. **AutoEq's own `FixedBandEQ.txt`** is ten peaks an octave apart at Q 1.41 (read in the review, 0.4) - the shape of
   the graphic here. It imports like any APO file, as a correction.
10. **APO is stricter and looser than its page**: commands and keywords are matched with their case (`filter 1:` and
    `Fc 100 hz` play nothing in APO); `Hz` after Fc and `dB` after Gain are required; a comma is a decimal point
    (`6,5`), and `1.000 Hz` is a thousand; a GraphicEQ's points are sorted, not refused out of order. deadwax reads each
    the same way (3.9), so a file plays here as it does there - and says, line by line, what APO leaves out too.
11. **deadwax is more exact than APO**, which rounds to Float32 between filters (0.3). So a file plays here as APO
    plays it within Float32's rounding - about -140 dB of the signal - not bit for bit; nothing needs more.

---

## 1. The engine

### 1.1 Where the EQ goes

**Once, between the main mixer and the output, at the output's rate.** The path becomes:

1. GainedSource: Normalization's one multiply, at the file's own rate.
2. The lane's AVAudioConverter, when the file's rate isn't the output's.
3. (The turntable's slice 4: the lane's AVAudioUnitVarispeed, out of the path at 1x.)
4. The lane's AVAudioPlayerNode.
5. The main mixer, at unity.
6. **The EQ** - one unit, every channel of the mix.
7. The output.

Why there, and not per lane or in the source:

- **One filter state, one continuous signal.** A gapless join on a lane, and a song starting on another lane, are both
  already sample-exact in the mixer's output; the EQ carries no state from song to song and cuts off no lane's tail.
- **Hi-res is untouched.** Every lane reaches the mixer at the output's rate, so the EQ always runs at the output's:
  48 kHz on the speaker and AirPods, a USB DAC's own. Its coefficients are made for that rate, and again for each new
  one.
- **The fader doesn't move the curve.** The varispeed is before the mixer (turntable.md 5.2); a headphone's resonance
  doesn't move when the record speeds up.
- **Not per lane**: several copies of the filters, cold states at every change of lane, one curve changed in several
  places - for nothing.
- **Not beside GainedSource**: decoded audio is scheduled 2 s ahead (`aheadSeconds`), so a drag would be heard 2 s
  late, or everything ahead scheduled again at every move.

**It adds no delay.** IIR filters have no latency of their own; the unit reports `latency` 0, and `startLead()`,
`latency()`, positions, the lock screen and plays are unchanged (proved: RouteAndPositionTests pass unchanged, 1.7).

### 1.2 The unit: an in-process AUAudioUnit

`DeadwaxAudio/EQUnit.swift`: `final class EQUnit: AUAudioUnit`, an effect with one input bus and one output bus,
registered once per process with
`AUAudioUnit.registerSubclass(EQUnit.self, as: EQUnit.component, name: "deadwax: EQ", version: 1)`. Its component:
type `kAudioUnitType_Effect` (`aufx`), subtype `dweq`, manufacturer `Dwax` (Apple keeps all-lowercase manufacturer
codes for itself).

- **Made** as `AVAudioUnitEffect(audioComponentDescription: EQUnit.component)` - synchronous, so `configure` stays
  synchronous. Slice 2's first test proves this hands back our subclass (`unit.auAudioUnit is EQUnit`) on macOS; if it
  doesn't, `AVAudioUnit.instantiate(with:options: .loadInProcess)` is used, waited for with a 1 s bound. In-process
  registration needs no app extension, so a free account has it. *Fairly sure* for iOS (it is how Apple's own AUv3
  sample hosts its unit in-process); proved on macOS, then on the phone by check 0a (6).
- **Attached and connected in `configure`** (both modes): `engine.attach(eq)`, then
  `connect(mainMixerNode, to: eq, format: f)` and `connect(eq, to: outputNode, format: f)`, with `f` the mixer's output
  format - offline, the manual rendering format. `matchOutput()` makes the same two connections at the hardware's rate
  where it now makes one (:968) - **when the mixer's output rate or the unit's differs from the hardware's** (today's
  test reads the mixer's alone). An `AVAudioEngineConfigurationChange` leaves every connection at its old format
  (Apple: "the nodes remain attached and connected with previously set formats"), so after a new route both are
  made again, never one. The two busses always carry one format, so AVAudioEngine converts nothing around the unit.
- **Its busses accept** Float32, non-interleaved, any rate, 1 to 8 channels (`channelCapabilities` `[-1, -1]`: as many
  out as in). `canProcessInPlace` true; `latency` 0; `tailTime` 0 (a pause stops the output at once, 0.1, so a filter's
  ring-out is cut with the song's own last samples either way); no AUParameterTree - changes come through the ring
  (1.6), never as AU parameters, which would bring Objective-C observation onto the render. `shouldBypassEffect` and
  `AVAudioUnitEffect.bypass` are never set: the identity bank (1.7) is the unit's bypass, measured bit-exact.
- **`maximumFramesToRender` is set to 4,096** on the unit in `configure`, before anything is allocated (offline, the
  manual rendering maximum, also 4,096 at :571). AUAudioUnit's own default is 512, and with the screen locked iOS
  renders in blocks of up to 4,096 frames; whether AVAudioEngine raises a hosted v3 unit's maximum itself isn't
  documented, so it is never left to it. The render answers a larger block with `kAudioUnitErr_TooManyFramesToProcess`
  and counts it (Debug's Render row) - never a silent overrun.
- **`allocateRenderResources`** (off the audio thread; AVAudioEngine calls it at `prepare`/`start` - and `engine.stop()`
  releases it, so **every play after a pause allocates afresh**, 0.1): reads the busses' format and
  `maximumFramesToRender`, makes the render's buffers (`EQRender.make(rate:channels:maximumFrames:)`, 1.5: the Double
  scratch, both banks' coefficients and states, the input history, the crossfade's weight table for that rate) and
  marks the state **fresh**: its first block installs the newest bank without a crossfade (1.8).
  `deallocateRenderResources` frees the buffers. The host object (`EQHost`, 1.6) outlives them: it holds the newest
  bank for the next start.
- **`internalRenderBlock`** is made once in `init` (AUAudioUnit caches it), capturing only an `UnsafeMutablePointer`
  to the render state's **header** - made in `init`, freed in `deinit`, never moved - whose fields point at the
  buffers `allocateRenderResources` makes. The host never calls the block while unallocated, so the header always
  points at live buffers when it runs (1.5).
- **If the unit can't be made** (registration or instantiation fails): the engine connects mixer -> output as today,
  plays on, and says so - Debug's "Unit" row, and the EQ screen's line (3.3, state 11). Nothing else changes.
- **Looked at and not taken**: a render-notify callback on the output unit (`AudioUnitAddRenderNotify`), changing the
  output's buffer in place after it renders - no AU to register, but there is no output unit in offline manual
  rendering, so nothing of it could be measured on macOS; and Apple's `AVAudioUnitEQ` (the plan's question 2: its
  bandwidth in octaves, its shelves undocumented, its precision and bypass unmeasured, and the deck would need a second
  one kept in step).

### 1.3 The filters: types, formulas, and their Q

Core's `EQFilter` is a kind (peak, low shelf, high shelf, low pass, high pass, band pass, notch, all pass), a
frequency `fc` (Hz), a gain `g` (dB), a width - `.q(Double)`, `.bandwidth(octaves)`, `.slope(dB per octave)` or
`.none`, kept as written so it is worked out at every rate as APO does - for a shelf whether its `fc` is a **centre or a
corner** (0.3), the type as the file wrote it (`LSC`, `LS 6dB`, `PEQ`, `Modal`: an export writes it back the same), a
channel (`all`, `left`, `right`) and `on`.

**The formulas** are the RBJ cookbook's (W3C's "Audio EQ Cookbook"), as APO's BiQuad.cpp computes them (0.3), in
`Double`, normalised by `a0` into five coefficients `b0, b1, b2, a1, a2`:

- `A = 10^(g/40)` for peaks and shelves; `w0 = 2π·f0/fs`; `c = cos w0`; `s = sin w0`.
- `alpha = s / (2Q)` for a Q; `alpha = s · sinh(ln 2 / 2 · BW · w0 / s)` for `BW Oct`; for a shelf's S,
  `alpha = s / 2 · √((A + 1/A)(1/S − 1) + 2)` - APO's three, read.
- **Peak**: `b = [1 + alpha·A, -2c, 1 - alpha·A]`, `a = [1 + alpha/A, -2c, 1 - alpha/A]`.
- **Low shelf**: `b0 = A((A+1) - (A-1)c + 2√A·alpha)`, `b1 = 2A((A-1) - (A+1)c)`, `b2 = A((A+1) - (A-1)c - 2√A·alpha)`;
  `a0 = (A+1) + (A-1)c + 2√A·alpha`, `a1 = -2((A-1) + (A+1)c)`, `a2 = (A+1) + (A-1)c - 2√A·alpha`.
- **High shelf**: `b0 = A((A+1) + (A-1)c + 2√A·alpha)`, `b1 = -2A((A-1) + (A+1)c)`, `b2 = A((A+1) + (A-1)c - 2√A·alpha)`;
  `a0 = (A+1) - (A-1)c + 2√A·alpha`, `a1 = 2((A-1) - (A+1)c)`, `a2 = (A+1) - (A-1)c - 2√A·alpha`.
- **Low pass**: `b = [(1-c)/2, 1-c, (1-c)/2]`; **high pass**: `b = [(1+c)/2, -(1+c), (1+c)/2]`; **band pass** (0 dB
  peak): `b = [alpha, 0, -alpha]`; **notch**: `b = [1, -2c, 1]`; **all pass**: `b = [1-alpha, -2c, 1+alpha]`; each with
  `a = [1 + alpha, -2c, 1 - alpha]`.
- **A shelf by its corner**: `S` from the slope (`slope / 12`) or from the Q (`S = 1 / ((1/Q² − 2) / (A + 1/A) + 1)`),
  then `f0 = Fc · 10^(|g| / 80 / S)` for a low shelf and `Fc / 10^(|g| / 80 / S)` for a high one; the filter is then
  made at f0 with its own Q or S, as written. Every other filter's f0 is its Fc.

The three AutoEq uses are byte for byte its peq.py's (0.4), and APO's for the same lines.

| APO writes | deadwax plays (APO's rule, 0.3) | needs | with no width (or a width of 0) |
| --- | --- | --- | --- |
| `PK`, `PEQ`, `Modal` | Peak (Modal's `T60 target` unread, as APO) | Fc, Gain | left out, as APO (a note, 3.9) |
| `LSC`, `HSC` | Low or high shelf, f0 = Fc; a Q, or `LSC <x> dB` as S = x/12 | Fc, Gain | S 0.9, f0 = Fc |
| `LS`, `HS` with a Q, or `LS 6dB`, `LS 12dB`, `HS 6dB`, `HS 12dB` (any `<x> dB`) | Low or high shelf, **by its corner** (above) | Fc, Gain | - |
| `LS`, `HS` with neither | Low or high shelf, f0 = Fc | Fc, Gain | S 0.9 |
| `LP`, `LPQ`, `HP`, `HPQ` | Low or high pass, Q or BW Oct (a gain ignored) | Fc | Q 1/√2; `BW Oct 0`: BW 1/√2 oct |
| `BP` | Band pass, 0 dB peak, Q or BW Oct (a gain ignored) | Fc | Q 1/√2; `BW Oct 0`: BW 1/√2 oct |
| `NO` | Notch, Q or BW Oct (a gain ignored) | Fc | Q 30; `BW Oct 0`: BW 30 oct |
| `AP` | All pass, Q or BW Oct (a gain ignored) | Fc | left out, as APO |
| `IIR` | - | - | refused: its coefficients are for one rate, and the phone plays at several |

A BW Oct given to a shelf is ignored, as APO ignores it (and with no Q or slope the shelf takes S 0.9). Where a line
gives several widths, the last kind APO reads wins: a slope over BW Oct over Q. **A shelf too steep for its gain** -
an S above 1 where `(A + 1/A)(1/S − 1) + 2` isn't positive, as `LSC 24 dB` with 23 dB of gain - has no filter (APO
would compute the root of a negative number and play nothing sensible), so it is refused (3.9). **Only a slope can
make one** (corrected in slice 1): a shelf given a Q is made with that Q (BiQuad.cpp:37-38 - its S is never under a
root), and a corner shelf's S from a Q, used only to move its frequency (BiQuadFilter.cpp:49-58), makes that
expression exactly 1/Q², always positive.

**How sure**: sure, every row - read from APO's source (0.3), and each held by fixtures the script computes from those
rules written out again in Python (5.1).

**Q's meaning** follows the cookbook, as AutoEq's and APO's do: for a peak, Q sets the bandwidth between the
frequencies where the gain is half the peak's (in dB). The graphic's bands (3.5) are one octave wide: Q = √2 =
1.4142…, **written and played as 1.41** - so an export (3.11) plays exactly what you heard, and a band is as wide as
AutoEq's FixedBandEQ writes its own (Q 1.41, read, 0.4).

**At the output's rate**: a filter whose `f0` is at or above 0.49 × the rate is left out at that rate (counted, and said
in Debug and in its Advanced row - 3.8), since the formulas fold over past Nyquist. A peak or a shelf at 0 dB is left
out too: it is exactly flat, and leaving it out is what lets a flat curve pass through untouched (1.7) - kept in, its
section would compute `x + b1·x1 + … − a1·y1 − …` with partial sums that don't cancel exactly, so not the identity.

**Precision, at every rate the phone plays** (44.1 to 384 kHz): the coefficients in Double, worked out from `cos` and
`sin` of `w0`. The worst case is the lowest frequency at the highest rate - 1 Hz at 384 kHz, the import's floor (3.9),
w0 = 1.6e-5: a Double's rounding moves its pole angle by about 4e-7 of itself and its radius by 1e-9 of its distance
from the unit circle, and the recursion's own rounding stays near -170 dB. In Float32 the same filter's pole angle
would be wrong by a factor of hundreds - which is why every coefficient and state is a Double, never a Float.

### 1.4 The curve, its response and the preamp

**One curve per channel**: the correction's filters for that channel (`all` and its own), the tone's ten bands, and a
level. Core's `EQResponse` gives a curve's dB at any frequency for a given rate, exactly:
`20·log10 |H(e^{jw})|`, summed over the sections, each `|b0 + b1·z⁻¹ + b2·z⁻²| / |1 + a1·z⁻¹ + a2·z⁻²|` at
`z = e^{jw}`, in Double. The same function draws the screen's curve, finds the preamp and is held to scipy's `freqz`
(5.1). There is no second formula for "what the curve looks like".

**The automatic preamp** (James's decision), Core's `EQPreamp.automatic`:

- The curve's **top**: its largest dB over every channel, at the rate it plays at (as built, after slice 1's review:
  over the two ears' curves, each with its offset, for the preamp; channels 2 and up play the shared list, and where
  that isn't one of the ears' curves at its level - per-ear filters, or both ears' offsets below 0 - its own top is
  counted for it alone, so its level is the preamp or lower and the ears aren't lowered for channels a stereo output
  hasn't got) (48 kHz while an output isn't
  connected). Found in two steps: the curve at DC, every 1/48 octave from 10 Hz to just below Nyquist, each filter's
  own `f0`, and Nyquist; then **each local maximum among those points refined** - a golden-section search on log
  frequency between its two neighbours, 80 rounds (to well under 1e-6 dB), deterministic. A lone peak's top is at
  its `f0` exactly and a shelf's at DC or Nyquist, but **a sum's top is often at no filter's frequency**: measured in
  the review (numpy, the cookbook at 48 kHz), the grid and the `f0`s alone fall short by 0.045 dB for two Q 30 peaks
  1/30 octave apart, 0.042 dB for two Q 10 peaks 1/8 octave apart, 0.073 dB for two Q 100 peaks 1/100 octave apart -
  enough to round the preamp 0.1 dB short. Refined, each lands on the true top (a 4-million-point search) to 1e-5
  dB. A few hundred evaluations of a few dozen sections: well under a millisecond, off the audio thread.
- `preamp = -ceil(top × 10) / 10` when the top is above 0 dB - so a top of 6.32 dB gives -6.4 dB - and **0 when it
  isn't**: the automatic preamp never boosts (8, question 10). So the curve's top sits at 0 dB, or below it when the
  curve only cuts.
- One preamp for both ears, so a per-ear correction keeps its balance.
- The file's own `Preamp:` lines: in **automatic**, the part they share is replaced by deadwax's own (a correction's
  level is headroom); a difference between the ears (`Preamp:` after `Channel: L`) is the correction's own and is
  kept in that ear's curve. In **hand-set** (Advanced, 3.8), the preamp is yours, and an import sets it to the file's
  shared part - so an imported file plays as APO plays it (to Float32's rounding, 0.5 item 11).
- AutoEq's `Preamp:` is its own version of the same idea; a test holds deadwax's within 0.5 dB of it for each fixture
  profile and prints both (5.1).

**Normalization is untouched**: its gain stays per song, at the source; the preamp is per curve, the same for every
song on that output, so an album never steps in level. What you hear is Normalization's gain, the preamp and the curve.

**It isn't a guarantee.** A curve's phase can lift a peak above what its magnitude says, and a 44.1 kHz lane already
carries a full-scale tone's inter-sample peak to +3.01 dBFS (notes/ios.md, R10). The unit counts the samples it sends
over full scale while filtering (Debug, 3.1), so we know how often, instead of guessing. The fix, if it's ever heard, is
more preamp, never a limiter (the fidelity rule).

### 1.5 The render, and its real-time rules

Core's `EQRender` is the processing, pure Swift on pointers, the same code in three places: the player's unit, the
deck's render (1.9), and the Linux tests.

- **Direct Form I, in Double**: each section keeps `x1, x2, y1, y2` per channel;
  `y = b0·x + b1·x1 + b2·x2 - a1·y1 - a2·y2`, written out in that order (Swift doesn't contract `a·b + c` into a
  fused multiply-add unless asked, and this never asks, so Linux and the phone compute the same bits). Float32 in,
  Double through every section and the preamp, rounded to Float32 once at the end (APO rounds after every filter, 0.3;
  this is the more exact of the two). DF1 is chosen over the transposed form (TDF2, which is also what scipy's `lfilter`
  runs) because its state is the signal itself - the last inputs and outputs - which is what lets a section carry on
  across a change of coefficients with only the change's own transient (1.6); a TDF2 state is a mix of terms made
  with the old coefficients. In Double both are far below anything audible at any rate (1.3's precision: a 20 Hz shelf
  at 192 kHz has poles within 0.0007 of 1, which is why Float32 won't do); the cost is the same.
- **Section-major, channels paired**: the block is converted once into a Double scratch buffer
  (`maximumFramesToRender` × channels, made at allocation), and each section runs over it in place, both channels of a
  pair in one loop, so the two recursions interleave; cost is in 1.10.
- **Up to 80 sections a channel** (64 for the correction, 10 for the tone, room to spare), up to 8 channels; channel 0
  takes the left's list, 1 the right's, the rest the shared list (`Channel: all`). A one-channel output plays the left
  ear's.
- **Denormals: none flushed.** A Double's subnormals start at 2.2e-308 - 260 orders of magnitude under the smallest
  Float32 the output can hold (1.4e-45) - so they never reach a sample, and ARM64 (the phone, and the macOS runner's
  Apple silicon) computes them at full speed in hardware (*fairly sure*; measured, 1.7 test 9). The first draft's
  flush - any state under 1e-30 set to 0 at each block's end - is gone: it made the output depend on where blocks
  fall (a state zeroed after a block of 512 isn't zeroed in the middle of a block of 4,096), which breaks the
  block-size test's bit-for-bit promise (5.1), and it didn't stop subnormals either (a fast-decaying section crosses
  from 1e-30 to 1e-308 inside one block). **If test 9 shows a cost**, the fallback is per sample and so independent of
  blocks: each section's output `y` is stored as `(y + 2^-900) - 2^-900`, which turns anything under about 1e-287 into
  0 and changes nothing a Float32 can hold.
- **Counters** (written by the render, read by Debug): samples over full scale while filtering and the largest,
  crossfades made, banks waited for (one arriving mid-crossfade), banks for another rate, render time per block (mean
  and worst, from `mach_absolute_time`, a read, not a call into the kernel).

**Real-time safe, by construction and by test** - the turntable's rules (turntable.md 4.3), which this slice builds
first:

- **No allocation, no lock, no Objective-C message, no Swift reference counting** in the render. The render block
  captures one `UnsafeMutablePointer<EQRenderState>`; everything it reads - both banks, the input history, the weight
  table, the slots - was made in `allocateRenderResources` as `UnsafeMutableBufferPointer`s. No Array, String,
  closure, existential, `print` or `os_log` anywhere the render reaches. **No global, `static` or class stored property
  is read there either**: Swift checks each access to one at run time (`swift_beginAccess`), and a lazy global's first
  touch runs `swift_once`, a lock; the constants the render needs (the 1/√2, the weight table) are copied into the
  render state at allocation. The `pullInputBlock` call is a block call, as every AU makes - Swift may retain and
  release that block around it, an atomic count with no allocation and no lock, which the allocation test can't see
  and this rule accepts.
- **Non-generic at the render**: one concrete entry, `EQRender.process(_:input:output:frames:)`, in Core, called once
  a block across the module boundary; its loops are inside it, so nothing per sample crosses a module.
- **Warmed once off the audio thread**: before the unit's first start, the host renders `maximumFramesToRender`
  (4,096) frames of silence through the same entry, with a bank change, on its own queue - so type metadata and every
  page of every buffer are touched there, never first on the audio thread.
- **The test**: slice 2's EQRealTimeTests call the AU's render block directly (not through AVAudioEngine, whose own
  render machinery allocates on that thread) 10,000 times over pass-through, filtering, a crossfade, a bank for another
  rate and a bank arriving mid-crossfade, with the allocation hook of turntable.md 4.3 - `malloc_logger`, counting only
  the rendering thread, proved by a canary `malloc` before the run, no weaker fallback - **in a release build**, a step
  of its own on ios.yml's macOS job (`swift test -c release --filter EQRealTimeTests`).
- **A review rule**: `EQUnit.swift`'s render closure and `EQRender.swift` import nothing but the C target and Core.

### 1.6 Changes: banks, handed over and crossfaded

**A bank** (Core's `EQBank`, a value made on the main thread or the engine's queue, never the audio thread): the rate
it was made for, the output key and settings version it was made from, each channel list's sections as normalised
coefficients, each list's level (the preamp and that ear's offset, as one linear Double), and whether it is the
identity (no sections, level exactly 1).

**Handing it over** (`DeadwaxAudio/EQHost.swift`, over the C target - 1.5's ring, 8, question 1):

- **Three slots** made up front - a triple buffer. A producer writes the back slot, then exchanges back and middle with
  a "fresh" bit in one C11 atomic word (`atomic_exchange_explicit`, acquire-release). The render, at a block's start,
  if the bit is set, exchanges front and middle the same way and takes the front. The newest bank always wins; banks
  in between are never seen - a drag's 120 a second coalesce into what the render can take.
- **Producers are serialised** by an `os_unfair_lock` the render never touches: the main thread (a change), and the
  engine's queue (a start, 1.8).
- **One output at a time** (the review: the first draft's "newer version, or as new and for the same output" let a
  slider's bank for the old route, made a moment after the start had read the new one, land last). The host keeps
  **the output key now**, written under that lock by whichever learns of a route first - the start hook (from
  `AVAudioSession.currentRoute`, read as the output starts) or EQModel's route handler (the same, as it handles the
  notification) - and a producer's bank is published only if it was made for that key and from a settings version at
  least the last one published. A bank for another output is dropped and counted ("banks for another output",
  Debug). EQModel, hearing the route, makes the new output's bank and publishes it; until then nothing for the old
  output can land.
- **No floating point in C** (turntable.md 4.2's rule: clang contracts `a·b + c` by default). The C target moves
  indices and bits; the slots' Doubles are written and read in Swift.

**In the render:**

- **A bank taken is copied** at once into the render's own memory - its coefficients and levels into the render
  state's incoming bank - so its slot goes back to the producers at the next exchange while the render still needs it
  (with three slots, the one a crossfade fades *from* would otherwise be the producers' to overwrite).
- **The first block after an allocation** (every start, 1.2) installs the newest bank: states zeroed, no crossfade -
  the output has just started, and nothing was heard before it.
- A bank for another rate is ignored and counted (a new rate always comes with a stop, 1.8).
- A bank whose coefficients and levels equal the live one's, bit for bit, is taken with nothing done.
- **Otherwise, a crossfade**: the new bank runs beside the live one on the same input for **20 ms** (`round(0.020 ×
  rate)` frames), and the output moves from the old's to the new's by a raised cosine,
  `w(n) = 0.5 - 0.5·cos(π(n+1)/N)`, from a table made for the rate - smooth at both ends, so nothing in the weight
  itself makes a click; it ends at exactly 1. The two are summed `(1 - w)·old + w·new`: equal gain, right for two
  filters of one signal. Then the new bank is the live one. A crossfade starts at a block's start, so the output
  during one depends on where blocks fall; without one it never does (5.1's block test).
- **One crossfade at a time.** A bank arriving mid-crossfade waits in the middle slot - replaced by any newer one -
  until it ends, then crossfades from the bank that just became live. A drag is heard following the finger within one
  crossfade and one IO block (20 + 21 ms at 48 kHz's 1,024 frames); while it lasts both banks run, so the render costs
  double (1.10).
- **Warm start, by identity**: each section carries a stable id - `.band(0…9)` for a tone band, or `.filter(id)`, a
  correction filter's own id (kept in the settings, 4) - never its place in the list, which an added filter (3.8: kept
  in frequency order) would shift for every filter after it. A section of the new bank whose id, kind and channel list
  match a live one takes that section's `x1, x2, y1, y2`; so a drag of one slider leaves every other band carrying on
  exactly, and the moved band starts from its own history, which is close. **Any other section starts as if it had
  been flat**: its `x` and `y` history both **the history of its own input** - the previous section's output history
  in the new bank (the bank's input history for its first section; the first draft said the bank's input for every
  section, which is only right for the first).
- **What the crossfade buys, measured** (the review: the same arithmetic in numpy - DF1 in Double, the warm start,
  the 20 ms raised cosine - on a tone at -6 dBFS at 48 kHz, each change made in one step against crossfaded; the click
  is the largest sample of the output after an 8th-order Butterworth high-pass far above the tone):

  | change | tone | high-pass | one step | crossfaded |
  | --- | --- | --- | --- | --- |
  | 1 kHz band 0 -> +12 dB | 1 kHz | 8 kHz | -58 dBFS | -129 dBFS |
  | 1 kHz band 0 -> -12 dB | 1 kHz | 8 kHz | -58 dBFS | -142 dBFS |
  | 125 Hz band 0 -> +12 dB | 100 Hz | 2 kHz | -73 dBFS | -102 dBFS |
  | 63 Hz band 0 -> +12 dB | 40 Hz | 2 kHz | -87 dBFS | -119 dBFS |
  | 31 Hz band 0 -> +12 dB | 40 Hz | 2 kHz | -93 dBFS | -102 dBFS |
  | 31 Hz band 0 -> -12 dB | 40 Hz | 2 kHz | -93 dBFS | -108 dBFS |

  So the crossfade takes a mid or high band's click from plainly audible to nothing; a low band barely clicks either
  way. What a low band does is **settle**: the 31 Hz band's +12 dB on a 40 Hz tone overshoots its new level by 1.3 dB
  and is within 0.5 dB of it after 50 ms - the same in one step or crossfaded, warm or cold: it is the filter's own
  time constant (2AQ/ω0 = 29 ms), which no handover can shorten. (**Changed from the plan:** its section 7's "-80 dB
  of an ideal crossfade", which nothing meets at 31 Hz; 1.7 test 3 holds what was measured.)
- **Off and On** are a crossfade to and from the identity, so the switch is a 20 ms A/B.

### 1.7 Off, untouched - and proved so

"Nothing the app plays changes unless a change asks for it." Off - every new output's setting - and any curve that is
flat (no sections left at this rate, level exactly 1) make the identity bank, and **with the identity live and no
crossfade running, the render pulls the mixer's samples straight into the output buffer and returns** - in place:
when the host hands buffers, `pullInputBlock` renders into them; when it hands none, the output is pointed at the unit's
own input buffers and the pull renders there. Nothing is multiplied, converted or copied through a Double. Only the
last two input samples of each channel are read and kept, for the next warm start.

**Measured, on ios.yml's macOS runner, in offline manual rendering, before anything is built on it** (slice 2):

1. **Every Phase 1 render test passes unchanged** with the unit in the graph and Off (EngineRenderTests, GainRenderTests,
   UpNextRenderTests, RouteAndPositionTests, StartsAtASampleTimeTests, …).
2. **A 30 s song of noise and a log sweep** (made in the test - seeded noise, then a 20 Hz-20 kHz sweep, both channels
   different - written by RenderHelpers' `flacFile(_:rate:)` at 44.1 kHz, as the other render tests make theirs, and
   rendered to a 48 kHz offline output, so the lane's converter runs too) renders **bit for bit the same** with the
   unit Off, with the unit On at a flat curve, and with no unit at all (`Settings.eq = false`, the test's own engine).
3. **No clicks** (the thresholds from 1.6's measurement, each with its margin): a tone at -6 dBFS through each change
   - a band from 0 to +12 dB and back in one step, a preset swapped for another, On to Off and back, another output's
   curve put in while playing. **The click** is the largest sample of the render, after an 8th-order Butterworth
   high-pass run in the test in Double, in the 200 ms after the change: **under -110 dBFS** above 8 kHz for a 1 kHz
   tone through the 1 kHz band (measured -129/-142), **under -95 dBFS** above 2 kHz for a 100 Hz tone through the 125 Hz
   band and a 40 Hz tone through the 31 and 63 Hz bands (measured -102 to -119); and before each change, the same
   measure's floor (-150 dBFS and below). **The same changes made in one step** - the test's own bank with the
   crossfade's length set to one frame - **must fail it** (measured -58 and -73 dBFS), so the test is shown able to hear
   a click. **The settle**, for the 40 Hz tone and the 31 Hz band at ±12 dB: the tone's level (its RMS over each period,
   ×√2) within 0.5 dB of its new steady level by 80 ms after the change (measured 50 ms), overshooting the larger
   level by at most 1.5 dB (measured 1.3) - printed, with the whole envelope, for the review.
4. **Joins unbroken**: Test sounds 9 and 10 (one tone cut in two), and a lane change from a 44.1 kHz song to a 96 kHz
   one, through a curve that boosts - and **the unit's output equals Core's `EQRender` run over the engine's own render
   with no unit, sample for sample**. The filter is time-invariant and its state carries across blocks, so this proves
   the EQ changes nothing about a join that the curve itself doesn't.
5. **No allocation on the render** (1.5).
6. **The response**: an impulse and a log sweep through the unit at outputs of 44.1, 48, 88.2, 96, 176.4, 192, 352.8 and
   384 kHz (offline manual rendering takes any rate; a USB DAC may run at any of them), against Core's `EQResponse`
   for the same bank - within 0.01 dB from 20 Hz to 20 kHz. The impulse is rendered until the slowest section has
   decayed below -120 dB (its pole radius says how long), so truncation costs nothing at 0.01 dB.
7. **A rebuilt engine** (`rebuild()`, media services reset) has a new unit with the curve back in before its first
   sample.
8. **Its cost** (1.10).
9. **No cost in silence** (1.5's denormals; `EQRender.process` called directly, in the release build): a +12 dB, Q 10
   peak at 20 Hz and a high pass at 0.45 × the rate, at 192 kHz, given a burst and then 5 minutes of exact zeros - the
   peak decays by e every 0.32 s (2AQ/ω0), so its states pass 2.2e-308 into the subnormals in under 4 minutes, and the
   high pass's within a block - and the slowest block's render time no more than twice a block's over noise. On
   failure, 1.5's per-sample fallback, and this test again.
10. **The screen-locked block**: blocks of 4,096 frames (iOS's when the screen is locked) render, and 4,097 is answered
   with `kAudioUnitErr_TooManyFramesToProcess`, counted, the output untouched (1.2).

**If 1 or 2 fails** (the plan's question 3's B): Off takes the unit out of the graph at the output's next stop -
`matchOutput()` connects mixer -> output while the output's EQ is Off, and mixer -> EQ -> output while it is On; turning
it On while playing then restarts the output from the frame heard (a gap of about 0.3 s, the line "The EQ comes in after
a moment's pause." under the switch), and Off while playing passes through until the next stop. Not built unless the
measurement says so.

### 1.8 A route change, a new rate, a reset

The sequence when AirPods connect mid-song (the same for the car, a DAC, AirPlay):

1. iOS stops the engine and posts its configuration change (on AVAudioEngine's thread) and the session's route change
   (on the main queue), in no set order.
2. `configurationChanged` (:2051): the lanes made again, `matchOutput()` - now both connections, at the new rate -
   `sleep()`, and the 0.3 s settle.
3. **EQModel** (the app's, 3.12) hears `routeChangeNotification`: works out the output now (`EQOutputs.key`), sets it
   as the host's output key (1.6), records it as met if it is new (Off), bumps the settings version and publishes its
   bank (the unit is stopped: the start below supersedes it, or it is the same).
4. **The start**: `ensureRunning` -> `matchOutput()` -> `engine.prepare()` -> **`eqStart(rate, channels)`** - a
   `nonisolated` closure the app sets, as it sets `latency` and `startLead` (`PlayerModel.swift:601-602`, from AudioSessionController's
   `nonisolated static` functions) - reads `AVAudioSession.currentRoute` and EQModel's snapshot (a lock-protected value the main thread
   replaces on each change, holding every output's settings, so a route EQModel hasn't heard of yet still gets its
   own - Off when it is new; the engine's queue isn't real time, so a lock is fine there), sets the host's output key,
   makes that output's bank at the unit's rate and **publishes it through the ring**. Then `engine.start()`; the
   render's first block after the allocation installs it - states zeroed, no crossfade (1.6). The engine's queue never
   writes into the render state, even stopped. The first sample on the new route already has its curve, and nothing
   sounded at the switch.
5. AirPods taken out: `.oldDeviceUnavailable` pauses, as now. At the next play, step 4 puts the speaker's curve in.

- **Every play after a pause is a start**, so the start hook runs then too - a few microseconds to make 80 sections'
  coefficients - and, since `engine.stop()` released the unit's resources, so does the allocation (1.2): a few
  hundred kilobytes, on the engine's queue, inside the 0.2-0.4 s the output already takes to start (notes/ios.md,
  "The pause the lock screen didn't see").
- **A route that changes without stopping the engine** (not seen anywhere yet): step 3's publish crossfades it, 20 ms.
- **A new rate** (a USB DAC at 96 kHz, AirPlay at 44.1 kHz): `allocateRenderResources` makes the state and weight table
  for it; banks are made for it from step 4; a bank made for the old rate and still in the ring is ignored.
- **Media services reset**: `rebuild()` makes a new engine and `configure` a new unit; the start puts the curve in.
- **AirPlay**: the app's engine renders what is sent, so the EQ applies, and a change is heard about 2 s later
  (AirPlay's own delay, iOS's `outputLatency`). The screen says so (3.3).
- **CarPlay**: the car's port; the car's own EQ still applies after ours.

### 1.9 The deck (the turntable) and the fader

- **The deck's engine** (turntable.md 4.3, its slice 2 - which lands after the EQ) plays the record's sound on a
  second AVAudioEngine that this unit doesn't reach. Without the EQ there too, the sound would jump from EQ'd to plain as
  a hand takes the record. So the deck's render calls **the same `EQRender.process`** on its two channels, with a state
  of its own, fed by a second `EQHost` that EQModel publishes to beside the player's: the same banks, the same
  crossfades, the same install at its first block after the deck engine's own start. Its slice adds those lines,
  `DeckController` registering its host with EQModel (the same output key, set by the same two hands, 1.6), and one
  test: the deck's output with a curve equals the voice's output run through `EQRender` for the same bank, bit for
  bit. turntable.md 4.3's review rule then reads: the deck's render file imports only `CAudioRing` and Core (its voice
  and `EQRender`). On AirPlay the deck isn't prepared at all (turntable.md 4.6), so there is nothing to match.
- **After the voice's limiter**, not before it. **Changed from the plan** ("before its peak limiter, so the limiter
  still has the last word"), because: the voice stays the web's port untouched, so turntable.md's tests A and B hold
  with the EQ on as well as off; the record's path then ends as the song's does - the EQ last - so the handover's seam
  compares like with like; and the automatic preamp already keeps the curve's top at or below 0 dB, so the record's
  peaks stay about the limiter's ceiling. The cost: a filter whose response never passes 0 dB can still raise a
  sample's peak (its impulse response's absolute sum is more than its largest gain), so a curve can take the record a
  little past the ceiling - typically a fraction of a dB - as it can the song; the render's over count (1.5) says how
  often. (8, question 2.)
- **The fader's varispeed** (turntable.md 5.2) sits per lane before the mixer; the EQ after it. Neither touches the
  other's code: the EQ changes `configure`, `matchOutput` and `ensureRunning`; the fader `laneFor` and the timeline.

### 1.10 What it costs

The worst case: 74 sections a channel, two channels, at 192 kHz, during a crossfade (both banks running) - about 0.5
Gflop a second, the recursions latency-bound at roughly 7-8 cycles a section a sample (a multiply and an add on the
`y` chain) with the two channels interleaved: about 6% of a performance core, for the 20 ms a crossfade lasts - and
for as long as a drag goes on, which is a crossfade after another (1.6); half that steady. At 384 kHz, twice that. At
48 kHz with AutoEq's ten and the tone's ten, under 1%. **iOS may run the audio thread on an efficiency core**, at
about two-thirds the clock with longer latencies: the worst case there is nearer 15% at 192 kHz, still inside one
block's time many times over. Measured on the macOS runner (render time per block, printed and bounded at 10% of the
block's duration at 192 kHz) and shown on the phone in Debug's Render row (check 22), where the efficiency-core case is
whatever the phone does.

---

## 2. The server: AutoEq through deadwax (a 2.1.x patch on main)

### 2.1 What it serves, and from where

The phone never talks to GitHub: deadwax keeps AutoEq's list, searches it, and fetches one profile's text when asked.

- **The list**: `results/INDEX.md` (0.4) at **one commit** - deadwax asks GitHub for `master`'s commit
  (`GET https://api.github.com/repos/jaakkopasanen/AutoEq/commits/master` with `Accept: application/vnd.github.sha`, a
  bare 40-hex answer) and fetches `https://raw.githubusercontent.com/jaakkopasanen/AutoEq/<sha>/results/INDEX.md`. A
  profile is fetched from the **same commit**, so the list and its files always agree and a profile's address never
  changes under it.
- **A profile**: `https://raw.githubusercontent.com/jaakkopasanen/AutoEq/<sha>/results/<path>/<name> ParametricEQ.txt`,
  `<path>` from the list's line and `<name>` its last segment. The list's path is **decoded once** when the list is
  read (it encodes only spaces, 0.4) and kept decoded; the address is made by encoding each segment whole
  (`urllib.parse.quote(segment, safe="")`, so `&`, `+`, `(` and `)` are encoded too) - never the list's own encoding
  passed through, which would turn a `%20` into `%2520`. Never a path from the request.
- **Parsing a line** (`src/autoeq.py`, pure): the name between `- [` and the first `](./`; the path from there to the
  **last** `) by ` (names and paths may hold parentheses, 0.4); the source and rig from ` by <source>[ on <rig>]`. The
  rig folder (the path's second segment) gives the form: `in-ear`, `over-ear` or `earbud` when it says one, else none;
  the rig shown is the folder less that word (`711 in-ear` -> `711`). A line that doesn't parse is skipped and counted
  (deadwax's log, info level).
- **An id** for each result: the first 16 hex digits of SHA-1 of `"autoeq:" + path` (the decoded path) - stable while
  AutoEq keeps the path, and nothing a person types.
- **Searching**: folded - NFKD, marks dropped, lowercased, every run of anything not a letter or digit one space. A
  result matches when **every word of the query is found in its folded name with the spaces taken out**: "hd650" and
  "hd 650" both find "Sennheiser HD 650". Ranked: names where every query word starts a word of the name first, then
  shorter names, then by name.
- **One row per headphone**: results with the same folded name are one row - the best source first, by AutoEq's own
  order of trust as its README states it when the slice is built; if it states none, `oratory1990`, `crinacle`,
  `Super Review`, `HypetheSonics`, `Rtings`, `Innerfidelity`, `Headphone.com Legacy`, then the rest by name (the
  constant `SOURCE_ORDER`, with the source of the order in its comment) - and the others under it.

### 2.2 The two routes

Both in `src/routes/eq.py`, included with `current_user` (any signed-in person; with logins off, everyone), the
describe routes' kind of route: an outside source, read for one person's listening.

**`GET /deadwax/eq/autoeq?q=<words>&limit=<n>`** - `q` 1-100 characters, `limit` 1-50 (default 30); anything else a
422. Answers:

```json
{
  "results": [
    {"id": "3f2c9a0d1b7e4c55", "name": "Apple AirPods Pro", "source": "crinacle", "rig": "711", "form": "in-ear",
     "others": [{"id": "…", "source": "Super Review", "rig": "…", "form": "in-ear"}, …]}
  ],
  "total": 4,
  "list_from": "2026-11-10T04:12:00Z"
}
```

`total` is the number of rows before `limit`; `list_from` when the list was fetched.

**`GET /deadwax/eq/autoeq/{id}`** - `id` 16 lowercase hex digits, else 422. Answers
`{"id", "name", "source", "rig", "form", "text"}`, `text` the ParametricEQ.txt as AutoEq wrote it (at most 64 KB,
UTF-8). `Cache-Control: private, max-age=86400`.

**Failures, in words for whoever reads them** (`detail`, so the app's ErrorWords say them - 3.17):

- No list ever fetched and GitHub can't be reached, or answers anything but the list: **503**
  `"deadwax can't reach AutoEq just now."`
- An id not in the list: **404** `"AutoEq doesn't have that measurement any more."` - and the same when GitHub answers
  404 for the file.
- The file can't be fetched (anything else): **503**, the same words as above.
- deadwax's log (info level, never the event log a listener's page could show) says what GitHub answered.

### 2.3 Keeping it

- In deadwax's database (`store.py`, beside `descriptions`): `autoeq_list` (id primary, name, source, rig, form, path,
  folded), `autoeq_meta` (the commit and when it was fetched), `autoeq_profile` (id primary, the commit, the text, when).
- **The list** is read into memory at the first ask after a start. **Older than 7 days**, it is fetched again in the
  background (one at a time, an `asyncio.Lock`), and the old one answers meanwhile; **none at all**, it is fetched
  before answering (15 s at most). **When `master`'s commit is the one kept**, nothing more is fetched and nothing
  dropped - only the time moves (the list is 851 KB; most weeks AutoEq's results don't change). A new list replaces
  the old in one transaction, **and every kept profile goes with it** - each is fetched again, at the new commit, when
  next asked (one small request) - so a profile answered is always the list's commit's, as 2.1 promises. (The first
  draft dropped only the profiles of ids no longer listed, which left a kept profile at an older commit than its
  list.) The phone keeps its own copy of what it uses (4), so nothing playing changes.
- **A profile** is kept once fetched: at a commit it can't change. Asked again, it is answered from the database without
  asking GitHub.
- **Sizes**: the list is refused past 8 MB, a profile past 64 KB (as "can't reach AutoEq", logged with the size).
- **Asking GitHub**: `src/api/autoeq_endpoint.py`, one `httpx.AsyncClient`, 15 s (10 s to connect), the user agent
  **`deadwax/<version>`** on every request (GitHub's API refuses requests with none). **Not**
  `Config.musicbrainz_user_agent()`, as Wikipedia's client sends (wikipedia_endpoint.py): that one carries the contact
  address MUSICBRAINZ_EMAIL gives it (config.py's `build_user_agent`), which MusicBrainz and Wikimedia ask callers for
  and GitHub doesn't - so GitHub is told nothing more than the program and its version. Redirects not followed. Three
  outcomes kept apart, as `wikipedia_endpoint.py` does: an answer, a definite 404, and `Unreachable`. About one
  request a week for the list and one per new profile: far inside GitHub's 60 an hour for an unsigned caller.

### 2.4 Terms and credit

- AutoEq's repository is MIT, its results included; the measurements behind them are their sources' (0.4). deadwax
  **fetches one correction at a time, for the person listening, and never bundles or hands out the set** - the
  gentlest use, and the plan's.
- **Credit** wherever a profile shows: the app's profile page names the measurer and AutoEq, with a link to the
  project (3.7); the README and docs/ios.md name AutoEq, Jaakko Pasanen, and that the measurements are oratory1990's,
  crinacle's and the other sources'.
- The test fixtures copy a dozen ParametricEQ.txt files (5.1) - with a README in their folder naming AutoEq (its MIT
  notice) and each file's measurer.

### 2.5 The fixed lists, and the tests

- `tests/test_logins.py` `ROUTES`: `("GET", "/deadwax/eq/autoeq"): "user"` and
  `("GET", "/deadwax/eq/autoeq/{id}"): "user"` - so `test_every_route_but_the_public_ones_needs_a_session` and the
  permission walk cover them.
- `test_there_is_no_general_proxy` (`tests/test_navidrome.py:229`) is about Navidrome's routes; these aren't. But the
  same principle is held by a test of their own: **GitHub is asked only for the commit, the list, and paths taken from
  deadwax's own list** - never anything from the request.
- `tests/test_autoeq.py`, with an httpx `MockTransport` for GitHub and fixtures beside it (an INDEX.md excerpt of about
  40 lines - the AirPods Pro from four sources and the AirPods Pro 2's four, the HD 650 from several, a name with
  parentheses, a path with `&` and `+` raw (HypetheSonics' `Bruel & Kjaer 5128` rig, `(51dB + ANC)`), a line that
  doesn't parse - and two ParametricEQ.txt files):
  - parsing: names, paths (decoded once), sources, rigs, forms, the unparsed line counted;
  - each profile's address with every segment encoded exactly once (`%20`, `%26`, `%2B`, `%28`, never `%2520`);
  - GitHub's user agent `deadwax/<version>`, with no contact address in it even when MUSICBRAINZ_EMAIL is set;
  - a new list drops every kept profile; the next ask fetches it at the new commit; an unchanged commit fetches
    nothing more and drops nothing;
  - folding and search: "hd650", "HD 650", "airpods pro", accents, punctuation, no match, the ranking;
  - one row per headphone, sources in SOURCE_ORDER, `others`;
  - the list fetched once, kept, answered from the database after a restart; older than 7 days refreshed while the old
    answers; none and GitHub down -> 503 in its words; the commit's files asked at that commit;
  - a profile fetched once and then answered without asking; an unknown id 404; GitHub's 404 -> 404; GitHub's 500 ->
    503; a file past 64 KB refused; a list past 8 MB refused;
  - only GitHub's three kinds of address asked, never a path from `q` or `id`;
  - `q` and `limit` bounds (422s); the answer's fields (what the app's models need, so `test_ios_contract.py` can hold
    them when the phone's Routes gain these, slice 4).
- `tests/test_ios_contract.py` on `ios`: `ROUTE_COUNT` up by two (24 -> 26 at the review) in slice 4's phone commit, with its models
  (`AutoEqResults`, `AutoEqProfile`) held to these answers.

### 2.6 Docs, version, and what it must not touch

- **Version**: the next patch on main (2.1.7 as this is written), bumped in the same commit, README current.
- **README**: the iPhone app's EQ in its features, and one line that deadwax fetches AutoEq's list from GitHub once a
  week when someone searches it, so the server needs to reach api.github.com and raw.githubusercontent.com.
- **docs/troubleshooting.md**: "AutoEq can't be reached" - what the app says, and what to do: deadwax's container needs
  outbound HTTPS to those two hosts; deadwax's log says what GitHub answered.
- **docs/configuration.md**: no new setting.
- **CLAUDE.md**'s map: `src/autoeq.py` (pure: the list's parsing, folding, search) and `routes/eq.py` lines, as every
  module has; the write-up in notes/ios.md ("The EQ").
- **Must not touch**: any other route, the web (`ui/`), the describe and MusicBrainz caches.
- If James tags it, its release notes are written with the tag (his rule); his server runs `:experimental`, which the
  push to main publishes.

---

## 3. The screens

### 3.1 Where it's reached

- **You > Playback**: an **EQ** Section after Normalization's (after the turntable's two as well, when they are in):
  one row, a `NavigationLink` to the EQ screen.
  - The row: "EQ", and under it in `.footnote` `Palette.quiet` the output now ("James's AirPods Pro"); at its right the
    setting's short name (3.13: "Off", "Bass Boost", "AutoEq + Bass Boost", …).
  - Its footer: "Each output keeps its own EQ - your headphones, the speaker, the car - and the EQ switches by itself
    when the output changes. This is kept on this phone." - the last sentence Normalization's own (`YouWords.kept`,
    YouLines.swift:32), so the section's two footers say it the same way.
  - Apple's pattern: a Settings row with its value at the right, pushing its page (sure).
- **Now Playing's •••**: a last section, one item - **"EQ"**, `slider.vertical.3`, with the setting's short name as its
  subtitle (a second `Text` in the item's label, which iOS menus draw as a subtitle - fairly sure on iOS 17; if not,
  the title alone). It opens the EQ screen as a **sheet over Now Playing**, in its own NavigationStack, with "Done" at
  its top right - as Info and Up Next open (`NowPlayingView.swift:49-50` at the review, after the lyrics; 36-37 at
  b03ac65). Since the lyrics (app 0.4) `LyricsView` takes `covered: showsUpNext || showsInfo` and stops its clock
  while a sheet hides it (`Lyrics.clockRuns`); the EQ sheet is a third, so it joins them (`|| showsEQ`) - lyrics behind
  the EQ don't run on unseen. The ••• button's name becomes
  `"More: info, go to album, download, EQ"` (`NowPlayingWords.more` gains `eq: true`). **Changed from the plan:**
  "EQ", not "EQ…" - Apple's ellipsis is for an item that needs more from you to finish an action; this opens a page,
  as Info does. (8, question 12.)
- **Info**: About's Sound section gains a phone-only row after Plays from, **only while the EQ is on**: "EQ", e.g.
  "AutoEq + Bass Boost on James's AirPods Pro, preamp -6.4 dB". Debug's Sent to this device gains "EQ" after the
  engine's rows: "Filtering: 20 filters at 48 kHz, preamp -6.4 dB" / "Off: every sample passed through untouched" /
  "Changing: crossfading to the new curve".
- **You > Debug**: an **EQ** Section (3.13's Debug rows).
- **Another app's share sheet**: "deadwax", for a `.txt` (3.9).
- **Not** on the lock screen, the mini player, or Now Playing itself - no chip: the EQ is a setting of the output, not of
  the song, and Info says what you hear.

### 3.2 The EQ screen, top to bottom

A `List` (inset grouped, as You), titled **"EQ"** (large title when pushed from You; inline in the sheet). A
toolbar `•••` (`ellipsis.circle`) holds "Rename…". In the sheet, "Done" at the top right as well.

1. **The output** (a Section with no header):
   - A row: the output's symbol (3.12) in `.title2`, `Palette.quiet`, 32 pt wide; its name in `.headline`; under it
     in `.footnote` `Palette.quiet`: "Connected now", or "Not connected". One accessibility element with the header
     trait: "James's AirPods Pro, connected now".
   - A row: a `Toggle` **"EQ"**, tinted `Palette.accent` (the app's `.tint`). VoiceOver: "EQ for James's AirPods Pro".
   - When the output is AirPlay: a footer "Over AirPlay, a change is heard about 2 seconds later."
2. **The curve** (a Section, the row's insets zero): what you hear on this output (3.4), 150 pt tall. Under it, one
   line in `.footnote` (3.3 says which): "Preamp -6.4 dB, so loud songs don't clip." in `Palette.quiet`, or the state's
   line.
3. **Correction** (header "Correction"):
   - A row: "Correction", value at the right: "None" or the correction's name; under the label, in `.footnote`
     `Palette.quiet`, where it's from: "AutoEq, measured by crinacle", "AutoEq, measured by crinacle - changed", "From
     HD650 ParametricEQ.txt", "Your own filters". Pushes the correction picker (3.7).
   - When it applies, **the suggestion** row (3.7).
   - Footer: for headphones (Bluetooth, wired, USB): "Evens out what these headphones do to the sound, so they sound
     neutral. Your tone goes on top." For the speaker, a car, AirPlay, HDMI or line out: "Evens out what this output
     does to the sound. Your tone goes on top."
   - In Advanced, the section grows (3.8).
4. **Tone** (header "Tone"):
   - A row: "Preset", value the preset's name or "Custom"; pushes the presets (3.6).
   - **The ten sliders** (3.5) - or, at the accessibility sizes, ten stepper rows (3.15).
   - "Save as Preset…", a button row in `Palette.accent`, only while the tone is Custom.
   - Footer: "Shapes the sound to your taste, on top of any correction. A preset moves the sliders; move them yourself
     to make your own."
5. **Preamp** - only in Advanced (3.8).
6. **Other outputs** (header "Other outputs"), when the phone has met any (3.12). Not shown on the page of an output
   that isn't connected.
7. **Advanced** (no header): a `Toggle` "Advanced", footer "Build a correction from filters of your own, set the
   preamp yourself, and import or export Equalizer APO files."
8. On the page of an output that isn't connected (and isn't the speaker): a last Section with one destructive button,
   "Forget This Output", asking first with a confirmation dialog - "Forget James's AirPods Pro? Its EQ is deleted. It
   starts Off next time it connects." - "Forget" (destructive) and "Cancel". Apple's own "Forget This Device"
   (Settings > Bluetooth) (sure).

"Rename…" opens an alert with a text field: title "Rename Output", the field's placeholder the name iOS gives it,
"Save" and "Cancel". An empty name puts iOS's back. The name shows here, in You's row, Info and Other outputs.

**While Off, every control still works, and any change turns the EQ on** - the switch moves, and VoiceOver hears "EQ
on". Nobody edits an EQ they don't want to hear, and a change you can't hear is a trap. Apple Music's own EQ works this
way: choosing a preset is turning it on (fairly sure).

**The screen follows the route** - the page opened from You or the ••• is "the output now" - but **only the EQ page
itself, only while it is on top, and never under a finger**:

- While a finger is down on any of its controls (a slider, a stepper, a handle), the page keeps the output it began on
  and switches when it is let go (Phase 2's "The root never swaps under a finger", phase2-downloads.md).
- **Every page pushed from it is bound to the output it was opened for**, and stays so: the presets, the correction
  picker, a profile's page ("Use for James's AirPods Pro" must do what it says, whatever connects while you read), the
  filter editor, and the Rename and Save as Preset alerts. Choices made there go to that output - heard if it is still
  the one playing, kept if not. When that output is no longer connected, each pushed page shows one line at its top in
  `.footnote` `Palette.quiet`: "James's AirPods Pro isn't connected: changes are kept for when it is." (The review: the
  first draft followed the route on every page, so a profile opened for the AirPods and used after they were taken out
  would have gone on the speaker.)
- The EQ page under them switches **when it is shown again** (Back): the header's name crossfades (0.2 s; at once
  under Reduce Motion) and VoiceOver hears "EQ for James's AirPods Pro" as an announcement.
- A page opened from Other outputs, or from the import's "For", stays on its output.

### 3.3 Every state

| # | state | the curve | the line under it | the rest |
| --- | --- | --- | --- | --- |
| 1 | Off | flat at 0, drawn at `Palette.off` | "Off: nothing changes the sound." | everything usable; a change turns it on |
| 2 | On, flat (no correction, Flat, preamp 0) | flat | "Flat: nothing changes the sound yet." | the unit passes every sample through (1.7) |
| 3 | On, tone only | the tone | "Preamp -4.2 dB, so loud songs don't clip." | - |
| 4 | On, correction only | the correction | the preamp line | the correction drawn as the one line |
| 5 | On, both | the sum, and the correction alone as a thin dashed line | the preamp line | - |
| 6 | On, a correction per ear | "Left" and "Right" as two lines, labelled at their right ends | the preamp line | - |
| 7 | An output not connected | its curve, at 48 kHz | its line, and "Not connected: this is what it plays when it is." in the header's place | changes kept, not heard |
| 8 | Advanced, preamp by hand, enough | as 3-6 | "Preamp -6.0 dB, set by you." | - |
| 9 | Advanced, preamp by hand, too little | as 3-6 | "Loud songs may clip: the curve boosts 2.4 dB more than this preamp takes away." in `Palette.amber` | - |
| 10 | A filter above this output's top | as 3-6 | the preamp line | its Advanced row says "Above what this output plays, so it's left out." |
| 11 | The unit couldn't be made | flat | "The EQ can't play on this phone just now, so the sound is as it is. Closing deadwax and opening it again may help." in `Palette.danger`, and for an admin the engine's own words under it in `.footnote.monospaced()` | the settings still editable |
| 12 | AirPlay | as 3-6 | the preamp line | the AirPlay footer under the switch |
| 13 | Offline, or deadwax not answering | as 3-6 | as 3-6 | only AutoEq's search can't work (3.7); everything else is on the phone |
| 14 | The accessibility sizes | as 3-6 | as 3-6 | stepper rows for the sliders (3.15) |

### 3.4 The curve

Drawn with SwiftUI's `Canvas` from points Core makes (`EQChart.points`: 1/24 octave, 22 Hz to 22.6 kHz - ten octaves
centred on the bands, 3.5 - plus each filter's own `fc`, so a narrow peak is drawn at its height). The points are the
response of 1.4 at the output's rate (48 kHz while it isn't connected), **with the preamp added** - what you hear,
relative to the song: the top at 0 dB or below it.

- **The axes**: x by octaves (log); y in dB, ±15 by default, growing to ±18 or ±24 when the curve goes further (so
  nothing is ever cut off), animated over 0.25 s (at once under Reduce Motion). Gridlines: 0 dB in `Palette.textTertiary`,
  1 pt; ±6 and ±12 dB, and 100 Hz, 1 kHz and 10 kHz, in `Palette.barEdge`, a hairline. Labels in `.caption2`
  `Palette.quiet`: "+12", "0", "-12" at the left inside the plot; "100", "1k", "10k" along the foot.
- **The line**: the curve, 2 pt, `Palette.accent`, round joins; a fill from it to the 0 dB line in `Palette.toggledFill`
  (boosts above, cuts below), so the shape reads at a glance.
- **With a correction and a tone** (state 5): the correction alone as a 1 pt dashed line in `Palette.quiet` (dashed,
  so it's told apart without colour); in Advanced, the tone alone too, 1 pt dotted.
- **Per ear** (state 6): two lines, the left in `Palette.accent`, the right in `Palette.accentText`, each labelled
  "Left", "Right" in `.caption2` at its right end; the fill under the left only.
- **Moves**: a preset, a correction, On/Off or an output's change morph the line over 0.25 s (`.easeInOut`), at once
  under Reduce Motion; a drag moves it with the finger, never animated.
- No touch in the simple face; in Advanced, the handles (3.8).

### 3.5 The ten sliders

The tone's bands an octave apart, **at exactly 1000 · 2^k Hz** (k = -5 … 4: 31.25, 62.5, 125, 250, 500, 1000, 2000,
4000, 8000 and 16000 Hz), labelled with the ISO octaves' names (31, 63, 125 … 16k) - each a peak one octave wide (Q
1.41, 1.3), ±12 dB in 0.5 dB steps. Exact octaves, so the ten overlap the same way everywhere and an export writes the
frequency that plays (`Fc 31.25 Hz`, 3.11); the ISO nominals (31.5, 63) and AutoEq's FixedBandEQ (31, 62) differ from
them by under 1/50 of an octave, which nobody hears - the point is one number, pinned by Core's test (8, question 24).

**What a slider means**: each slider is its own band's gain, and **the curve is their sum** - bands an octave apart and
an octave wide overlap. Measured at 48 kHz: one band at +12 dB adds 2.5 dB an octave either side and 0.5 dB two
octaves away; all ten at +12 dB make +18.4 dB at 500 Hz, falling to +5.9 dB at 20 Hz and +2.5 dB at 20 kHz. That is a
graphic EQ's nature (APO's, AutoEq's FixedBandEQ, Apple Music's), and the curve above (3.4) is where you read what you
hear; the bands aren't "compensated" so that the curve passes through each slider's value, which would make what an
export writes differ from what the sliders say (8, question 23).

**The look** (a row of its own, insets zero, 236 pt tall):

- Ten columns sharing the width equally - 36 pt each on a 393 pt phone (34 on an SE, 40 on a Pro Max). Apple's 44 pt
  minimum is for a target's smaller side; these are 36 by 200, and a touch anywhere in a column takes its knob (below),
  so only across do they need care. Deliberately below 44: ten bands across is the point of a graphic EQ, and every
  phone EQ draws them so.
- In each column: a track, 4 pt wide, the full 200 pt, `Palette.barTrack` with a `Palette.barEdge` hairline; a fill
  from the 0 dB mark to the knob in `Palette.accent` (up for a boost, down for a cut); the knob, a 24 pt circle,
  white, with the iOS slider's own shadow (black at 0.3, 2 pt down, 3 pt blur) - the system slider's thumb, which is
  how a slider looks on iOS (sure).
- Across all ten: a 1 pt line at 0 dB in `Palette.textTertiary`; at the left edge, inside the first column, "+12", "0",
  "-12" in `.caption2` `Palette.quiet`.
- Under each column its band in `.caption2.monospacedDigit()` `Palette.quiet`: "31", "63", "125", "250", "500", "1k",
  "2k", "4k", "8k", "16k".
- While a knob is held, its value above it in `.caption.monospacedDigit()` `.semibold`, on a capsule of
  `Palette.barTrack`: "+3.5 dB", "0 dB", "-6 dB".
- **Changed from the plan:** the curve isn't drawn behind the sliders. It is drawn once, above (3.4), as what you hear:
  behind the sliders it would be a second copy of the same line when there's no correction, and a different line from
  the one above when there is. (8, question 4.)

**A drag:**

- **It takes hold wherever the knob is**: a touch anywhere in a column grabs that column's knob without moving it; the
  knob then follows the finger's movement (24 dB over the track's 200 pt: 8.3 pt a dB), so a touch never makes it jump -
  as the turntable's fader takes hold (turntable.md 5.1). A drag that starts sideways scrolls nothing and moves no knob
  until it has gone 6 pt up or down (the column's gesture wins vertically, the List's scroll otherwise).
- The value is the finger's position rounded to 0.5 dB, and **the sound follows it**: each new value is a new bank,
  crossfaded (1.6).
- **A light tick** (`UIImpactFeedbackGenerator(style: .light)`) as the value crosses into 0 dB - the fader's detent's
  (turntable.md 5.1; Apple's pattern for a detent, as a picker's wheel ticks; sure). Let go there and it is 0.
- **Double-tap** a column: back to 0 dB.
- Moving any slider makes the tone **Custom** ("Preset" says "Custom"), keeping where you left them.
- A preset chosen moves the knobs over 0.25 s (at once under Reduce Motion).

**VoiceOver**: each column is one adjustable element - label "125 hertz" ("1 kilohertz", "16 kilohertz"), value "plus
3.5 decibels" / "0 decibels" / "minus 6 decibels"; swipe up or down moves it 1 dB (as Core's `Scrub.swift` steps the scrub bar for VoiceOver's adjust); a custom
action "Reset to 0"; the ten in frequency order, after the Preset row. The tick isn't given to VoiceOver's steps (its
own sound says them).

### 3.6 Presets

**The built-in set** (James's decision), each a position of the ten sliders - so a preset is nothing you couldn't set
yourself, and choosing one sets the sliders there:

| preset | 31 | 63 | 125 | 250 | 500 | 1k | 2k | 4k | 8k | 16k | its note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Flat | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | "Nothing changed." |
| Bass Boost | +5 | +4.5 | +3 | +1 | 0 | 0 | 0 | 0 | 0 | 0 | "More low end." |
| Bass Reduce | -5 | -4.5 | -3 | -1 | 0 | 0 | 0 | 0 | 0 | 0 | "Less low end." |
| Treble Boost | 0 | 0 | 0 | 0 | 0 | 0 | +1 | +2.5 | +3.5 | +4.5 | "More sparkle and air." |
| Treble Reduce | 0 | 0 | 0 | 0 | 0 | 0 | -1 | -2.5 | -3.5 | -4.5 | "Softer highs, for bright recordings or headphones." |
| Vocal | -2 | -1.5 | -1 | 0 | +1 | +2 | +2.5 | +2 | +0.5 | 0 | "Voices brought forward." |
| Loudness | +5 | +4 | +2 | +0.5 | 0 | 0 | 0 | +1 | +2.5 | +3 | "For listening quietly: the lows and highs lifted, as ears hear less of them at low volume." |
| Small Speakers | -4 | -1 | +2.5 | +2.5 | +1 | 0 | 0 | +1 | +1.5 | 0 | "For small speakers that can't play deep bass: the upper bass lifted instead." |
| Spoken Word | -6 | -4.5 | -2.5 | -1 | 0 | +1 | +2.5 | +3 | +1.5 | -1 | "For podcasts and audiobooks: rumble cut, voices clearer." |

Neighbouring bands overlap (3.5), so a preset's curve goes a little past its largest slider - the drawn curve says by
how much, and the automatic preamp takes it away. Measured (the review, the cookbook at 48 kHz; 44.1 kHz within 0.07
dB):

| preset | the curve's top | its lowest | automatic preamp |
| --- | --- | --- | --- |
| Bass Boost | +6.0 dB at 62.5 Hz | 0 | -6.1 dB |
| Bass Reduce | 0 | -6.0 dB at 62.5 Hz | 0 |
| Treble Boost | +4.8 dB at 16 kHz | 0 | -4.8 dB |
| Treble Reduce | 0 | -4.8 dB at 16 kHz | 0 |
| Vocal | +3.3 dB at 2 kHz | -2.3 dB at 32 Hz | -3.3 dB |
| Loudness | +5.9 dB at 32 Hz | 0 | -5.9 dB |
| Small Speakers | +3.1 dB at 247 Hz | -4.1 dB at 31 Hz | -3.1 dB |
| Spoken Word | +3.7 dB at 3.9 kHz | -7.0 dB at 32 Hz | -3.7 dB |

So Bass Boost's +5 dB slider makes +6.0 dB of bass, and every song on that output plays 6.1 dB quieter - check 4's
"everything a little quieter". **These values are a starting point, tuned by James's ear in check 9** (6); whatever
he settles is what Core's test pins, with this table recomputed by the fixture script.

**The presets page** ("Preset", pushed): Apple's own pattern - Settings > Apps > Music > EQ is a pushed list of
presets with a checkmark (sure). Rows as Normalization's (`PlaybackSection.swift`): the name, its note under it in
`.footnote` `Palette.quiet`, a checkmark in `Palette.accent` on the chosen one, `.isSelected`, one element each. A tap
chooses it and the page stays (as Normalization's rows), so you can listen through several; Back returns.

- First, while the tone is Custom: "Custom", note "Where you left the sliders.", checked.
- The nine built-ins, in the table's order.
- **"Your presets"** (a Section, when you have any): your names, no note; swipe actions "Rename" and "Delete"
  (destructive); the same as VoiceOver custom actions. Deleting one an output uses leaves that output's sliders where
  they were, as Custom.

**Save as Preset…** (the Tone section's button, while Custom): an alert, title "Save as Preset", a text field
(placeholder "Name"), "Save" and "Cancel". A name is 1-40 characters, trimmed. Refused, the alert comes back with a
message: an empty name - "Give it a name."; a name taken (case and accents folded, the built-ins included) -
"There's already a preset called "Bass Boost"." Saved, the Preset row shows its name. "Rename Preset" is the same
alert with the name filled in.

Presets are shared by every output; each output keeps which one it uses (or its Custom gains).

### 3.7 The correction: AutoEq's picker, a profile, and the suggestion

**The picker** ("Correction", pushed from the Correction row):

- `.searchable` with the prompt "Find your headphones", always showing (`.navigationBarDrawer(displayMode: .always)`).
  A search is asked 0.3 s after typing stops, and only the newest answer draws (the app's latest-only rule).
- **First section**: "None" (checked when there's no correction) and, when there is one, its row (checked), so it can
  be chosen back after looking around. Choosing "None" takes the correction away at once (crossfaded) and goes back.
- **"Suggested for James's AirPods Pro"** (a Section, when 3.7's suggestion has an answer): its one row - or, when
  the suggestion matched several, those rows, with the field already holding the cleaned name.
- **The results** (header "AutoEq"): each row the headphone's name in `.body`, under it in `.footnote` `Palette.quiet`
  "crinacle · in-ear" - and, with other measurements, " · 3 more measurements" ("1 more measurement"). A tap pushes
  that profile's page.
- With an empty field, under the first sections: "Search by name or model - "hd650" finds the Sennheiser HD 650.
  Corrections come from AutoEq, which works out one for each headphone it has a measurement of." in `.footnote`
  `Palette.quiet`.
- Searching: a `ProgressView` with "Searching…" in the results' place.
- No match: "AutoEq has no headphones called "xyz"." and under it "Try the model alone, like "hd650"."
- A failure: the app's `ErrorNote` in a listener's words, with "Try again" (3.17).
- In Advanced, two more rows at the foot of the first section: "Import from Files…" (`doc.text`) and the system's Paste
  button (3.9).

**A profile's page** (pushed; title the headphone's name, inline):

- The curve of the correction alone (3.4's drawing, at 48 kHz, its own automatic preamp).
- "Measured by crinacle, on a 711 rig (in-ear)." - without a rig, "Measured by crinacle." - and "10 filters, preamp
  -6.0 dB", in `.footnote` `Palette.quiet`.
- A full-width `.borderedProminent` button: **"Use for James's AirPods Pro"**. Once used: "Used for James's AirPods
  Pro", disabled, with a checkmark. Using it copies the profile's text and filters into the output's setting (4), sets
  it as the correction (crossfaded), turns the EQ on if it was off, and goes back to the EQ screen.
- **"Other measurements"** (a Section, when there are others): rows "Super Review · in-ear", each pushing its own page.
- Footer: "From AutoEq, which works out a correction from each measurement to make headphones sound neutral. It's a
  starting point: how in-ears sit in your ears changes what you hear." and a `Link` "AutoEq on GitHub" (opens in Safari;
  the music keeps playing).
- Loading: a `ProgressView`; a failure: `ErrorNote` (3.17), with "Try again"; a 404: "AutoEq doesn't have that
  measurement any more." and the button gone.
- A profile the reader refuses (AutoEq changed its format): "deadwax couldn't read this correction." in
  `Palette.danger`; for an admin, the reader's words under it.

**The suggestion**: when the EQ screen shows a **Bluetooth or USB** output with **no correction**, EQModel searches
AutoEq once per output per launch with the output's name cleaned (`EQOutputs.suggestionQuery`: an owner's
`"James's "` / `"James’s "` taken off the front, then the words) and looks at the rows (2.1: one per headphone) whose
names hold **every word of the cleaned name**:

- **Exactly one**: it is offered. "Sennheiser HD 650" asks "Sennheiser HD 650" and is offered that one.
- **Several**: none is picked for you - the row offers the choice. "James's AirPods Pro" asks "AirPods Pro", which
  matches "Apple AirPods Pro" and crinacle's fourteen "Apple AirPods Pro 2 (…)" rows (0.4) - and **iOS names AirPods Pro 2
  "AirPods Pro" too**, so the name can't say which generation is in your ears. (The review: the first draft offered the
  first row, which is the first generation's, to a Pro 2's owner.)
- **None**: nothing. "JBL Flip 6" is offered nothing (AutoEq measures headphones).

The row, in the Correction section: `wand.and.stars` in `Palette.accent`, a chevron, and

- for one: "AutoEq has a correction for Apple AirPods Pro", under it "Measured by crinacle" in `.footnote`
  `Palette.quiet`; a tap pushes that profile's page.
- for several: "AutoEq has corrections for AirPods Pro", under it "5 models - pick yours" in `.footnote`
  `Palette.quiet`; a tap pushes the picker with "AirPods Pro" already searched, under the header "Suggested for
  James's AirPods Pro".

Never applied without you.

- A swipe action "Not now" (and the same as a VoiceOver custom action) hides it for that output for good (kept, 4).
- Gone once the output has a correction; not shown offline or when the search failed (it is an offer, not an error).
- The search asks deadwax, which searches its own copy of the list (2.1): the cleaned name never reaches GitHub.
- docs/ios.md says to pick AirPods by generation and, for the Pro 2, by the listening level and ANC crinacle measured.

### 3.8 Advanced

One switch, per phone (4). With it on:

**The curve grows** to 220 pt and gains **handles** - one for each correction filter that is on, at its `fc` and its
own gain on the curve of the correction alone (a pass or a notch at 0 dB): a 14 pt circle in `Palette.accent` with a
1.5 pt `Palette.barTrack` edge, the selected one 18 pt and white. GarageBand's and Logic Pro for iPad's own EQ is
dragged this way (fairly sure, remembered): drag sideways for frequency (snapped to 1 Hz under 1 kHz, 10 Hz above),
up and down for gain (0.1 dB), **pinch** for Q (0.01; 0.1-20 on a handle, wider in the editor). A touch takes the
nearest handle within 22 pt; a touch nowhere near one scrolls. The selected filter's numbers show in a capsule above
the plot: "Peak · 8903 Hz · +6.0 dB · Q 1.66". The handles are hidden from VoiceOver: each filter has a row just
below, with the same reach through number fields and steps (Apple's advice to offer another way than a pinch; 3.14).

**The Correction section** becomes its filter list, under the Correction row:

- **Rows by frequency**, low to high - as the handles run left to right. Each: the type ("Peak", "Low shelf", "High
  shelf", "Low pass", "High pass", "Band pass", "Notch", "All pass") in `.body`; under it in
  `.footnote.monospacedDigit()` `Palette.quiet` "105 Hz · +2.6 dB · Q 0.70" (no gain for a pass, notch or all pass;
  "BW 1.0 oct" for a width in octaves, "12 dB/oct" for a slope, "S 0.9" for a shelf with none); "Left" or "Right"
  after it when the filter is one ear's; at the right a `Toggle` for on and off (APO's ON/OFF). A filter left out at
  this rate shows "Above what this output plays, so it's left out." in `Palette.amber`. **Changed from the plan:** no
  reordering by drag - the order of these filters changes nothing in the sound, and the list in frequency order reads
  against the curve; an export writes them in this order. (8, question 5.)
- A tap pushes **the filter's editor**; a swipe "Delete".
- **"Add Filter"** (`plus`): a Peak at 1000 Hz, 0 dB, Q 1.00, pushed into its editor. At most 64 filters to an ear:
  past that, the button is disabled and says "64 filters is the most deadwax plays".
- Editing an AutoEq correction makes it yours to change: its row reads "AutoEq, measured by crinacle - changed", and
  the Correction row gains a menu item "Back to AutoEq's" (its text was kept, 4).
- "Import from Files…", Paste (3.9) and **"Export…"** (3.11).

**The filter's editor** (a `Form`, title "Filter 3" - its place in the list):

- The filter's own curve at the top (3.4's drawing, 120 pt, its handle draggable).
- "Type", a `Picker` (menu style) of the eight types. Changing it keeps the frequency, and the gain and Q where the new
  type has them.
- "Frequency", a `TextField` with "Hz" after it, and under it a slider on a log scale, 20 Hz to 20 kHz.
- "Gain" (peaks and shelves), a `TextField` with "dB" after it and a `Stepper` of 0.1 dB.
- "Q", a `TextField` and a `Stepper` (×1.1 a step) - or "Width" in octaves for a filter written with `BW Oct`, or
  "Slope" in dB an octave for a shelf written with one (`LSC 12 dB`, `LS 6dB`), each with a menu item "Use Q instead"
  that converts it at 48 kHz (the width as it is kept, 1.3, so a filter is changed only when you change it). A filter
  given no width shows its type's default as the field's placeholder ("0.71", "30", or "S 0.9" for a shelf, 1.3);
  typing a value gives it one.
- A shelf read **by its corner** (1.3: `LS`/`HS` with a Q or a slope) says so under Frequency, in `.footnote`
  `Palette.quiet`: "Its corner frequency, as Equalizer APO reads this shelf - it is centred at 131 Hz." - the f0 it
  plays at, so the handle (drawn at f0, where its gain is half) and the number agree.
- "Ear" (only when the correction has per-ear filters): "Both", "Left", "Right".
- "On", a `Toggle`.
- "Delete Filter", destructive, at the foot.
- The fields use the phone's own number format (a decimal comma where the phone's region writes one), the keyboard
  `.numbersAndPunctuation` - `.decimalPad` has no minus. A value out of range stays in the field, in `Palette.danger`,
  with its line under it: "Between 1 and 22000 Hz.", "Between -30 and 30 dB.", "Between 0.01 and 100." - and, for a shelf's
  slope too steep for its gain (1.3: a Q can't be), "Too steep for this gain - at most 19.6 dB an octave." - and nothing
  changes until it is in range.

**The Preamp section** (header "Preamp"):

- A `Toggle` "Automatic", on by default. On: a row "Preamp" with the value ("-6.4 dB") and the footer "Takes away the
  curve's highest boost, so loud songs don't clip."
- Off: a row "Preamp" with a `Stepper` of 0.1 dB, -30 to +12 dB, its value in `.monospacedDigit()`; the footer "Yours,
  for every song on this output." - and, when it takes away less than the curve's top, state 9's line in
  `Palette.amber` under it.

### 3.9 Import: three ways in, the preview, and what is read

**Three ways in** (the plan's question 11, A):

- **From Files**: "Import from Files…" opens `.fileImporter` for `.plainText` (a `.txt`), one file; read through its
  security-scoped URL.
- **Paste**: SwiftUI's `PasteButton(payloadType: String.self)` - its own "Paste" label and look; iOS asks no permission
  for it (sure). Disabled by iOS when the clipboard holds no text.
- **From another app**: "deadwax" in the share sheet for a `.txt` - Info.plist's `CFBundleDocumentTypes` gains
  `public.plain-text` with `LSHandlerRank` `Alternate` (so deadwax is offered, never the default for text), and
  `LSSupportsOpeningDocumentsInPlace` false (iOS hands a copy). No extension, so a free account has it. `.onOpenURL`
  takes the file, sets `AppNavigation.eqImport`, and whichever is on top - Now Playing's cover, or the tabs - shows the
  EQ screen as a sheet with the preview over it. **When a sheet is already up**: the EQ sheet itself shows the preview
  over it as it stands; any other (Info, Up Next, an import preview not yet answered) is closed first - its own Cancel,
  so nothing it held is applied - and then the EQ sheet opens. One import at a time: a second file arriving while a
  preview is up replaces it. The copy iOS made (`Documents/Inbox`) is deleted once read. `check_project.py` requires
  both keys.

**Reading the text** (Core's `APOReader`, pure, every case tested) - **as APO's source reads it** (0.3), so a file
plays here as it plays there, and where APO would leave something out, deadwax leaves it out too and says so:

- **Size and encoding**: at most 256 KB. UTF-8, a byte-order mark allowed; text that isn't valid UTF-8 is read as
  Windows-1252 (APO falls back to the PC's own code page, Windows-1252 on a Western PC; only comments are ever outside
  ASCII, so nothing that plays depends on which). **UTF-16 with a byte-order mark** (Notepad's "Unicode") is read too,
  with a note - APO reads such a file as nothing at all, and saying so beats playing nothing (8, question 26).
- **Lines**: split at LF, one CR before it dropped - LF and CRLF, as APO. A CR alone isn't a line end in APO, so a
  file whose lines end that way (an old Mac's) is one long line there; deadwax refuses it rather than play that
  (below).
- **A command** is the text before a line's first `:`, its spaces and tabs trimmed. Commands are **matched exactly,
  case and all**, as APO: `Preamp`, `Channel`, `GraphicEQ`, `Device`, the ones refused below, and any command
  *beginning* `Filter` (`Filter`, `Filter 3`, `Filter3`). **There is no comment syntax** in APO: a line beginning `#`
  is a command it doesn't know, and is skipped here without a note (it is a comment by intent); a `#` later in a line
  is ordinary text - keywords are searched for, so words after a filter's numbers change nothing. A blank line is
  nothing; any other line with no `:` is skipped with a note, as APO ignores it.
- **A number** is the longest start of a run of `-+0-9.eE` that reads as a decimal number - C's `wcstod`, as APO:
  `6.5.1` is 6.5, `1e3` is 1000, and a run that starts no number reads as 0.
- **`Preamp: <n> [dB]`**: commas become points first; the number, after any spaces - and whatever follows it, `dB`
  or anything else, is not read (corrected in slice 1: APO's `swscanf_s(value, L" %lf dB")` counts only the number,
  PreampFilterFactory.cpp:39-40, so `Preamp: -6 dB headroom` plays -6 dB); a line with no number there is skipped,
  as APO makes nothing of it; -30 to +30 dB. Several add
  up, for the channels then selected (APO's rule).
- **`Filter…: ON <type> …`**: commas become points first (so `Gain 6,5 dB` is 6.5 dB). The type is the letters
  straight after `ON` and a space; `OFF <type>` is kept, switched off (3.8) - APO plays nothing for it, and neither
  does an Off filter. Then, each searched for after a space anywhere in the line, the first match winning: `Fc <n> Hz`
  (**the `Hz` required**; a number of five or more characters, no exponent, with a point fourth from its end, is
  thousands - REW writes `1.000 Hz` for 1000 Hz), `Gain <n> dB` (**the `dB` required**), `Q <n>`, `BW Oct <n>`, and,
  straight after the type, `<n> dB`, a shelf's slope. Keywords and types with their case, as APO. What each type
  takes, its defaults, and which width wins are 1.3's table.
- **`Channel: …`**: words split at spaces, in any case (APO upper-cases them): `all`; `L` or `1`; `R` or `2`; several
  (`L R`). Filters and preamps after it apply to those channels until the next `Channel:`. Positions a phone doesn't
  have (`C`, `LFE`, `RL`, `RR`, `RC`, `SL`, `SR`, 3 and up): what follows a line naming only them is skipped, with a
  note; a line naming L or R with others keeps its L or R.
- **`GraphicEQ: <f> <g>; …`**: commas become points only when the line has no point at all (APO's rule, so
  `20 -3,5; 21 -3,4` is read the European way); every run of `-+0-9.eE` is a number, taken in pairs, a last odd one
  dropped; **the points sorted by frequency**, as APO sorts them. Converted (3.10).
- **One `Device:` line before any other command** is skipped, with a note.
- **Anything else APO doesn't play** - a command it doesn't know (`Volume:`, a lowercase `preamp:`), a filter with an
  unknown type, no `ON`/`OFF`, or without what its type needs - is skipped with a note (below): APO leaves it out
  too, so the file plays the same. The note says so when only the case or a unit is what APO tripped on, because
  that is the one a person can't see by looking.

**The preview** (a sheet, title "Import", "Cancel" at the top left and **"Import"** at the top right, bold):

- "From "HD650 ParametricEQ.txt"" or "From the clipboard", in `.footnote` `Palette.quiet`.
- "For", a `Picker` (menu style) of the outputs - the one connected now first and chosen - so a file for headphones not
  connected can be put on them.
- The curve of what is read, alone (3.4, 150 pt; two lines when per ear).
- One line: "10 filters, preamp -6.4 dB"; "11 filters for both ears, 2 more for the left, preamp -6.0 dB"; for a
  GraphicEQ, 3.10's line. Then the preamp as it will play: "Preamp: set by deadwax, -6.1 dB with this output's tone."
  (automatic) or "Preamp: the file's, -6.4 dB." (by hand).
- What it replaces, when there's a correction: "It replaces the correction for James's AirPods Pro (Apple AirPods Pro,
  from AutoEq)."
- **"Skipped"** (a Section, when anything was): one line each.
- **Import** sets it as the output's correction (crossfaded when it is the output playing), turns the EQ on, and closes
  the sheet; the EQ screen under it shows the new curve.

**Refused** - the whole file, and the preview says so instead: a title "Can't import this file" in `.headline`, the
reason in `.body`, and only "Done". These are what would play differently here than in Equalizer APO - what APO plays
and deadwax can't, or what has no sound to match - so the import offers nothing rather than something different:

| what | the words |
| --- | --- |
| nothing to play | "There's no EQ in this file: no Preamp, Filter or GraphicEQ lines." (pasted: "There's no EQ in what you pasted: no Preamp, Filter or GraphicEQ lines.") - also when every one was skipped |
| too big | "This file is too big to be an EQ file (2.3 MB)." (`Bytes.words`) |
| couldn't be read | "deadwax couldn't read this file." (for an admin, iOS's words under it) |
| lines ending in a CR alone | "This file's lines end the old Mac way, which Equalizer APO reads as one long line. Save it again from a text editor and import that." |
| `Include:` | "Line 3 includes another file (bass.txt). Import that file itself." |
| `Convolution:`, `Delay:`, `Copy:`, `Eval:`, `If:`, `ElseIf:`, `Else:`, `EndIf:`, `Stage:`, `VSTPlugin:`, `LoudnessCorrection:` | "Line 3 uses Convolution, which deadwax can't play." (the command as the file writes it) |
| several `Device:` lines, or one after a filter | "This file has settings for more than one device (line 12). deadwax keeps a setting for each output itself - import the part for these headphones as a file of its own." |
| `IIR` | "Line 5 gives a filter as raw coefficients, made for one sample rate - deadwax plays at several, so it can't play it." |
| a frequency out of range | "Line 5: 30000 Hz is higher than this phone plays - the highest a filter can be is 22000 Hz." / "Line 5: a filter's frequency must be at least 1 Hz." |
| a gain out of range | "Line 5: a gain of 45 dB is more than deadwax plays - at most 30 dB either way." (a filter's, or - added in slice 1, where this table was silent - a GraphicEQ point's: past it the fit's sums overflow to NaN, and APO has no sound to match. An overflowing number, `1e999`, is `wcstod`'s infinity in APO and here, so it is refused by its range: "inf Hz") |
| a Q, width or slope out of range | "Line 5: Q -2 won't make a filter - it must be between 0.01 and 100, or left out." / "Line 5: a width of 12 octaves won't make a filter - it must be between 0.01 and 10, or left out." / "Line 5: a slope of -6 dB won't make a filter - it must be above 0." (A width or slope of exactly 0 is the type's default, as APO: 1.3.) |
| a shelf too steep for its gain (1.3) | "Line 5: a low-shelf filter this steep (24 dB an octave) can't have 23 dB of gain - Equalizer APO can't play it either." (only a slope can make one: 1.3) |
| a preamp out of range | "Line 1: a preamp of 45 dB is more than deadwax plays - at most 30 dB either way." |
| too many filters | "This file has 90 filters for one ear - deadwax plays up to 64." |
| a GraphicEQ line with no pairs | "Line 2: a GraphicEQ line needs at least one frequency and its gain." (corrected in slice 1: APO plays one with no points as flat - GainIterator.cpp:74-77 gives 0 dB with no nodes - so it changes nothing there; refused here all the same, as the spec decided, for James to confirm) |
| a GraphicEQ frequency at or below 0 | "Line 2: a GraphicEQ's frequencies must be above 0 Hz (0 is there)." (its curve is on a log axis) |

The frequency range is 1 Hz to 22000 Hz on every output - just under half of 44.1 kHz, the lowest rate the phone
plays at - so a file is never refused for one output and taken for another (8, question 14). It is checked on the Fc
written; a corner shelf's moved f0 (1.3) is held by 1.3's 0.49 rule like any other.

**Skipped, with a note** (in "Skipped", one line each; the rest of the file plays):

- "Line 1 (Device: …) chooses a device in Equalizer APO - deadwax keeps a setting for each output itself."
- "Lines 12-20 are for the centre channel (C), which a phone doesn't have." - "the subwoofer channel (LFE)", "the rear
  channels (RL, RR)", "the rear centre channel (RC)", "the side channels (SL, SR)", "channel 3"; "Line 12 is" for one.
- "Line 9 isn't something Equalizer APO plays either (Volume: 5)." - the line's first 40 characters. When the case is
  all that differs from a command APO knows: "Line 1 isn't something Equalizer APO plays either (preamp: -6 dB) - it
  reads "Preamp" only as written, capital and all."
- A filter APO leaves out: "Line 5 (a peak filter) is left out, as Equalizer APO leaves it out: it has no gain." - "no
  frequency", "no width (a Q or a BW Oct; 0 counts as none, as in APO)" (a peak or all pass, 1.3), "no ON or OFF", "an
  unknown type ("XYZ")". When a near miss explains it, the note adds it: "- it says "gain 6", and Equalizer APO reads
  only "Gain 6 dB"." / "- its frequency has no "Hz" after it, which Equalizer APO needs." / "- Equalizer APO knows the
  type as "PK"."
- "This file is saved as UTF-16, which Equalizer APO doesn't read - deadwax read it anyway." (8, question 26)

### 3.10 GraphicEQ, converted

James's decision: a `GraphicEQ:` line - AutoEq's GraphicEQ.txt, Wavelet's, APO's own graphic - becomes filters,
close to its curve, not exact. Core's `GraphicEQFit`, pure and deterministic:

1. **The target**: the points (sorted, 3.9) and their gains, linear between them on a log-frequency axis, flat
   outside them at the end points' gains (APO's own rule, 0.3); several `GraphicEQ:` lines add up, as APO plays them
   one after another.
2. **Its level**: the median of the target over 20 Hz-20 kHz becomes the correction's own preamp (in automatic,
   replaced like any file's, 1.4; by hand, the file's), so the filters fit only the shape - AutoEq writes its preamp
   into the GraphicEQ's gains (the HD 650's median is -6.3 dB).
3. **The filters**: 61 peaks at 1/6-octave centres from 20 Hz to 20.2 kHz (`1000 · 2^(k/6)`, k = -34 … 26, rounded
   to whole hertz, as an export writes them), each a third of an octave wide (Q = 1 / (2 sinh(ln 2 / 6)) = 4.32),
   their gains solved together by Gauss-Newton on the 1/48-octave grid from 20 Hz to 21 kHz at 48 kHz, from all zero:
   each round solves `(JᵀJ / n + λI) Δ = -(Jᵀr / n + λg)` with **λ = 1e-4** (a whisper of damping against a singular
   step, nothing more), until no gain moves by more than 0.001 dB or 50 rounds; gains held within ±30 dB. Gains
   rounded to 0.1 dB; bands under 0.05 dB dropped.
4. **Its fit is measured** after rounding, at 48 kHz on the same grid: the mean and the largest difference up to 16
   kHz, and the largest above it, with where.

**Measured** (the review, numpy, on AutoEq's GraphicEQ.txt for the HD 650 and the AirPods Pro): the problem is well
conditioned - the Jacobian's condition number is 15.6 - and converges in 4-5 rounds, to 54 and 60 filters. Up to 16
kHz the fit is within 0.045 dB on average (0.065 RMS) and 0.47 dB at most; above 16 kHz, where the cookbook's peaks
crowd against Nyquist, it is off by up to 3.8 dB at 19 kHz at 48 kHz, and up to 6.6 dB at 19.3 kHz when the same
filters play at 44.1 kHz. (The first draft's Tikhonov weight of 0.01 pulled every gain toward zero and missed its own
test's bound; with a low and a high shelf added, the condition number goes to 227 for 0.1 dB better above 16 kHz -
not taken.)

The preview's line says both: "Converted from a GraphicEQ curve: 54 filters, within 0.1 dB of it on average and 0.5
dB at most up to 16 kHz; above that, up to 3.8 dB." (rounded up to 0.1 dB; "above that" left off when it is within
1 dB). The correction is then filters like any other - drawn, edited and exported as filters, its row saying "From
Wavelet.txt, converted".

**What differs from APO**, said plainly: APO plays a GraphicEQ as a minimum-phase FIR (0.3), and these are
minimum-phase peaks - so their phase follows their level, and where the levels agree the phases nearly do too. What
differs is level, as measured: next to nothing up to 16 kHz, a few dB at the very top, where most adults hear little
and AutoEq's own corrections are least sure. The preview says "close", in numbers.

**Looked at and not taken**: a greedy parametric fit as AutoEq makes its ParametricEQ (fewer filters, but which
filters come out depends on the optimiser's path, and it can stall); an FIR, played as written (the plan's C - a
larger build and a delay of its own, against the rule that the EQ adds none); fitting again at each output's rate
(the top would match at every rate, but the correction would no longer be one set of filters to edit and export).
(8, question 7.)

### 3.11 Export

"Export…" (Advanced, in the Correction section) is a `Menu` of two: **"The Whole Curve"** and **"The Correction
Alone"** - each a `ShareLink` of a file made then, `<output name> EQ.txt` (the name with `/` and `:` taken out), in
Equalizer APO's syntax and AutoEq's shape:

```
# deadwax EQ for James's AirPods Pro, 2026-11-12
# Correction: Apple AirPods Pro (AutoEq, measured by crinacle)
# Tone: Bass Boost
Preamp: -7.1 dB
Filter 1: ON LSC Fc 105 Hz Gain 2.6 dB Q 0.70
…
Filter 11: ON PK Fc 31.25 Hz Gain 5.0 dB Q 1.41
…
```

- The whole curve: the correction's filters (by frequency), then the tone's bands that aren't at 0 (`PK … Q 1.41`),
  and the preamp as it plays. The correction alone: its filters and its own preamp (its automatic one, or yours).
- Per ear: `Channel: all` and the shared filters, then `Channel: L` and the left's (with its `Preamp:` offset when it
  has one), then `Channel: R`.
- Off filters as `OFF`. A converted GraphicEQ as its filters, with `# Converted from a GraphicEQ curve`.
- Numbers in AutoEq's decimals - Fc whole hertz, Gain one, Q two - and more where the value kept needs them to be read
  back the same: Swift's shortest round-trip form, trailing zeros trimmed to AutoEq's minimum (the bands' `31.25` and
  `62.5`). Never a comma. And an `Fc` is never written as five or more characters with a point fourth from its end -
  APO reads that as thousands (3.9), so `12.345 Hz` would come back as 12345 Hz: such a value gains a trailing zero
  (`12.3450`), which reads back the same in both. A Core test writes and reads every such case.
- **Read back, an export gives the same filters, bit for bit** (a Core test, for every fixture and every built-in
  preset on top of each). The share sheet is Apple's way to hand a file out of an app (sure): Files, AirDrop, Mail.

### 3.12 Per output: naming, listing, switching

**What an output is** (Core's `EQOutputs`, from `AVAudioSession.sharedInstance().currentRoute.outputs`):

| port type | the output's key | its name | its symbol |
| --- | --- | --- | --- |
| `.builtInSpeaker` | `speaker` | "iPhone speaker" | `iphone` |
| `.headphones` | `wired` - every wired pair is one: iOS can't tell them apart | "Headphones" | `headphones` |
| `.bluetoothA2DP`, `.bluetoothLE` | `bluetooth:<uid>` | its `portName` ("James's AirPods Pro") | by name: `airpodsmax` (AirPods Max), `airpodspro` (AirPods Pro), `airpods` (AirPods), `beats.headphones` (Beats), else `headphones` |
| `.usbAudio` | `usb:<uid>` | its `portName` | `cable.connector` |
| `.carAudio` | `car:<uid>` | its `portName` | `car` |
| `.airPlay` | `airplay:<uid>`; several at once (multi-room) `airplay:<uids, sorted, joined by +>` | its `portName`; several "Kitchen + Living Room" | `airplayaudio` |
| `.HDMI` | `hdmi:<uid>` | its `portName` | `tv` |
| `.lineOut` | `line:<uid>` | its `portName` | `cable.connector` |
| anything else | `other:<portType>:<uid>` | its `portName` | `speaker.wave.2` |

- **The UID is the key**, believed stable - a Bluetooth address for Bluetooth, the device's for USB and AirPlay; Debug
  shows it raw so the phone confirms it (check 15). Whether AirPods' A2DP and LE ports give the same UID, and whether a
  USB DAC's is its model's or its own, only the phone says (7); the key takes the UID as iOS gives it until then (8,
  question 15).
- **On a USB-C iPhone, wired headphones through Apple's adapter are the adapter**: one output, whatever is plugged into
  it - as every pair in the jack was one. Whether iOS reports it as `.headphones` (key `wired`) or `.usbAudio` (key
  `usb:<uid>`, named "USB-C to 3.5mm Headphone Jack Adapter" or so) is the phone's to say (7); the table takes
  whichever it is, and Rename gives it a better name.
- **A new output starts Off** (the plan's question 8, A). Nothing changes until you ask; a Bluetooth or USB one may
  offer an AutoEq correction (3.7).
- **The speaker is always there**, met or not.
- **Other outputs** (the EQ screen's Section): every other output the phone has met, the most recent first; each row
  its symbol, its name, its short setting at the right ("Off", "Bass Boost", …), a chevron to its page. Swipe:
  "Rename" and "Forget" (destructive; not the speaker). Forgetting deletes its setting; met again, it starts Off.
- **Switching**: by itself, at every start of the output (1.8) - and nothing to tap. When AirPods connect mid-song, the
  first sound in them has their curve.

### 3.13 Every word

Core's `EQWords`, every one tested. Title case for menu items and buttons that name a command, as the app's are
("Play Next", "Download Again"); sentence case in rows and lines.

| where | words |
| --- | --- |
| You's row | EQ · the output's name under it · the short setting at the right |
| You's footer | Each output keeps its own EQ - your headphones, the speaker, the car - and the EQ switches by itself when the output changes. This is kept on this phone. |
| the short setting | Off · Flat · Bass Boost (any preset's name) · Custom · AutoEq (with no tone) · From a file · Your filters · AutoEq + Bass Boost · From a file + Custom · Your filters + Vocal (`<correction> + <tone>`) |
| Now Playing's ••• | EQ (subtitle: the short setting) |
| the ••• button's name | More: info, go to album, download, EQ (each part only as today, ", EQ" always) |
| Info, Sound | EQ · `<short setting> on <output name>, preamp -6.4 dB` (no preamp part at 0) |
| Info, Debug | EQ · Filtering: 20 filters at 48 kHz, preamp -6.4 dB · Off: every sample passed through untouched · Changing: crossfading to the new curve |
| the screen's title | EQ |
| the toolbar | Rename… · Done (in the sheet) |
| the output's row | `<name>` · Connected now · Not connected |
| the switch | EQ (VoiceOver: EQ for `<name>`) |
| the AirPlay footer | Over AirPlay, a change is heard about 2 seconds later. |
| the line under the curve | Off: nothing changes the sound. · Flat: nothing changes the sound yet. · Preamp -6.4 dB, so loud songs don't clip. · Preamp -6.0 dB, set by you. · Loud songs may clip: the curve boosts 2.4 dB more than this preamp takes away. · Not connected: this is what it plays when it is. |
| the unit couldn't be made | The EQ can't play on this phone just now, so the sound is as it is. Closing deadwax and opening it again may help. |
| the fallback's line (1.7, only if built) | The EQ comes in after a moment's pause. |
| the curve's labels | +12 · 0 · -12 · 100 · 1k · 10k · Left · Right |
| Correction | Correction · None · AutoEq, measured by crinacle · AutoEq, measured by crinacle - changed · From HD650 ParametricEQ.txt · From Wavelet.txt, converted · Your own filters · Back to AutoEq's |
| its footer (headphones) | Evens out what these headphones do to the sound, so they sound neutral. Your tone goes on top. |
| its footer (other outputs) | Evens out what this output does to the sound. Your tone goes on top. |
| the suggestion | AutoEq has a correction for Apple AirPods Pro · Measured by crinacle · AutoEq has corrections for AirPods Pro · 5 models - pick yours · Not now |
| a pushed page, its output gone | James's AirPods Pro isn't connected: changes are kept for when it is. |
| the picker | Correction · Find your headphones · None · Suggested for `<name>` · AutoEq · crinacle · in-ear · 3 more measurements · 1 more measurement · Searching… |
| the picker, empty | Search by name or model - "hd650" finds the Sennheiser HD 650. Corrections come from AutoEq, which works out one for each headphone it has a measurement of. |
| the picker, no match | AutoEq has no headphones called "xyz". · Try the model alone, like "hd650". |
| a profile | Measured by crinacle, on a 711 rig (in-ear). · Measured by crinacle. · 10 filters, preamp -6.0 dB · Use for `<name>` · Used for `<name>` · Other measurements · Super Review · in-ear · AutoEq on GitHub |
| a profile's footer | From AutoEq, which works out a correction from each measurement to make headphones sound neutral. It's a starting point: how in-ears sit in your ears changes what you hear. |
| a profile not read | deadwax couldn't read this correction. |
| Tone | Tone · Preset · Custom · Save as Preset… |
| its footer | Shapes the sound to your taste, on top of any correction. A preset moves the sliders; move them yourself to make your own. |
| the bands | 31 · 63 · 125 · 250 · 500 · 1k · 2k · 4k · 8k · 16k; held: +3.5 dB · 0 dB · -6 dB |
| the bands, VoiceOver | 31 hertz … 1 kilohertz … 16 kilohertz; plus 3.5 decibels · 0 decibels · minus 6 decibels; Reset to 0 |
| the presets page | Preset · Custom · Where you left the sliders. · the nine names and notes (3.6) · Your presets · Rename · Delete |
| saving | Save as Preset · Rename Preset · Name · Save · Cancel · Give it a name. · There's already a preset called "Bass Boost". |
| Advanced | Advanced · Build a correction from filters of your own, set the preamp yourself, and import or export Equalizer APO files. |
| the filters | Peak · Low shelf · High shelf · Low pass · High pass · Band pass · Notch · All pass · 105 Hz · +2.6 dB · Q 0.70 · BW 1.0 oct · 12 dB/oct · S 0.9 · Left · Right · Above what this output plays, so it's left out. · Add Filter · 64 filters is the most deadwax plays · Delete |
| the editor | Filter 3 · Type · Frequency · Hz · Gain · dB · Q · Width · octaves · Slope · dB an octave · Use Q instead · Its corner frequency, as Equalizer APO reads this shelf - it is centred at 131 Hz. · Ear · Both · Left · Right · On · Delete Filter · Between 1 and 22000 Hz. · Between -30 and 30 dB. · Between 0.01 and 100. · Between 0.01 and 10. · Too steep for this gain - at most 19.6 dB an octave. |
| the handles' capsule | Peak · 8903 Hz · +6.0 dB · Q 1.66 |
| Preamp | Preamp · Automatic · Takes away the curve's highest boost, so loud songs don't clip. · Yours, for every song on this output. |
| import | Import from Files… · Paste (the system's) · Import · Cancel · From "HD650 ParametricEQ.txt" · From the clipboard · For · 10 filters, preamp -6.4 dB · 11 filters for both ears, 2 more for the left, preamp -6.0 dB · Preamp: set by deadwax, -6.1 dB with this output's tone. · Preamp: the file's, -6.4 dB. · It replaces the correction for `<name>` (Apple AirPods Pro, from AutoEq). · Skipped · Can't import this file · Done |
| import, refused and skipped | 3.9's tables, verbatim |
| GraphicEQ | Converted from a GraphicEQ curve: 54 filters, within 0.1 dB of it on average and 0.5 dB at most up to 16 kHz; above that, up to 3.8 dB. |
| export | Export… · The Whole Curve · The Correction Alone · 3.11's comment lines |
| outputs | iPhone speaker · Headphones · Other outputs · Rename Output · Rename · Forget · Forget This Output · Forget `<name>`? Its EQ is deleted. It starts Off next time it connects. · Forget · Cancel |
| VoiceOver only | the curve: "The EQ's curve" with 3.14's summary; the route's announcement "EQ for `<name>`"; "EQ on" / "EQ off" when a change turns it on |
| Debug | its rows, below |

**Debug's EQ Section** (You > Debug, after Playing), a row a fact, in this order (new words, in Debug's manner):

| row | value |
| --- | --- |
| Output | "Bluetooth (A2DP) · James's AirPods Pro · 60:F8:1D:…-tacl" - the port type, its name, its UID raw; several outputs one line each |
| Key | the output's key |
| Unit | "In the graph: passing every sample through" · "In the graph: filtering" · "In the graph: crossfading" · "Not made: <iOS's words>" · (fallback only) "Out of the graph while Off" |
| Curve | "10 filters for both ears + 10 tone bands; its top +6.3 dB at 8.9 kHz; preamp -6.4 dB (automatic)" |
| At this rate | "48 kHz: 20 sections a channel" · "…; 1 left out (above 23.5 kHz)" |
| Changes | "112 crossfades; 3 waited for the one before; 0 made for another rate" |
| Started with | "AirPods Pro's curve, put in 0.1 ms before the output started" - the last start's install |
| Over full scale | "None since the output started" · "14 samples since the output started, the loudest +0.8 dBFS" |
| Render | "0.04 ms a block on average, 0.19 ms at worst - of 21.3 ms; refused blocks: 0" - the last part the blocks over 4,096 frames answered `TooManyFramesToProcess` (1.2) |
| Kept | "eq.json: 3 outputs, 2 presets of yours, 4.1 KB" · "eq.json couldn't be read, so it was set aside as eq-unreadable-2026-11-12.json" |
| EQ test (slice 2) | a Toggle "Muffle what plays" - a -24 dB high shelf at 2 kHz through the real unit, for check 0 |

### 3.14 VoiceOver

Reading order on the EQ screen: the output (one element, header trait), the switch, the curve, the line under it, the
Correction rows, the suggestion, the Preset row, the ten bands, Save as Preset…, the Preamp rows (Advanced), Other
outputs' rows, Advanced, Forget.

- **The curve is an audio graph** (`.accessibilityChartDescriptor`, iOS 15's `AXChartDescriptor`; sure of the API):
  title "EQ curve for James's AirPods Pro"; the x axis `AXNumericDataAxisDescriptor` "Frequency", 20-20,000, log10
  scale, gridlines at 100, 1,000 and 10,000, values said "125 hertz", "2.5 kilohertz"; the y axis "Gain", the drawn
  range, values "plus 3 decibels"; one continuous series "What you hear" of 61 points (1/6 octave), and in Advanced
  "Correction" and "Tone" as well. VoiceOver's rotor then offers "Play Audio Graph", which plays the curve as a rising
  and falling tone. Its label "The EQ's curve"; its value the **summary** (Core's `EQWords.curveSummary`):
  - the curve's largest boost of at least 1 dB and its largest cut of at least 1 dB, each with its region - "the bass"
    (under 250 Hz), "the lower mids" (250 Hz-1 kHz), "the upper mids" (1-4 kHz), "the treble" (above 4 kHz) - rounded
    to 0.5 dB: "Up to 5.5 decibels louder in the bass; up to 2 decibels quieter in the upper mids." Then "Preamp minus
    6.5 decibels." when it isn't 0. "Flat." when neither. "Off." when off.
- **The bands**: 3.5. **The steppers** at the accessibility sizes: each row's `Stepper` is one adjustable element with the
  band's label and value, the same words.
- **The filter rows**: one element each, label "Filter 3: peak at 8903 hertz, plus 6 decibels, Q 1.66" ("…, left ear
  only"), value "On" or "Off"; its switch a separate element "Filter 3 on"; custom actions "Delete", "Turn Off"/"Turn
  On". The handles are hidden (3.8): every handle's reach is in its row and editor.
- **The presets, the picker's rows, Other outputs**: as Normalization's rows - one element, its name, its note as the
  hint, `.isSelected` on the chosen one; swipe actions as custom actions.
- **Announced**: a route change on the screen ("EQ for James's AirPods Pro"), and a change that turns the EQ on ("EQ
  on"). Not announced: a drag's values as they go (VoiceOver says the value at each step), the curve's morphing.
- **Not given**: `.allowsDirectInteraction` on the curve - a finger exploring would move handles.

### 3.15 Dynamic Type

- **The curve** is a picture sized by the screen (150 pt, 220 in Advanced), never by the text size; its labels are
  `.caption2`, stopped at `.xxxLarge` (`.dynamicTypeSize(...DynamicTypeSize.xxxLarge)`), and the audio graph says
  everything they say.
- **The sliders**: their column labels and held value are stopped at `.xxxLarge` too. **At the accessibility sizes
  (`.accessibility1` and up) the ten sliders become ten rows** - Apple's pattern for a number set exactly at large
  sizes is a `Stepper` row, which grows with the text (sure): "31 Hz" at the left, "+3.5 dB" in `.monospacedDigit()`, a
  `Stepper` of 0.5 dB from -12 to +12 at the right; the label and value wrap above the stepper when they don't fit
  beside it. Ten rows reading down keep the bands in order; two rows of five would break the curve's left to right.
  The curve above still shows the shape. (8, question 13.)
- **Rows, footers, the preview, the editor**: system text styles throughout, wrapping, no line limits - as You's.
- **The handles' capsule** stops at `.xxxLarge` and truncates in the middle; the filter row says the same in full.

### 3.16 Reduce Motion, and the other settings

- **Reduce Motion**: no morph of the curve, no knob animation on a preset, no axis animation, no crossfade of the
  header's name - each jumps. **The sound's 20 ms crossfade stays**: it isn't motion, it is what keeps a change from
  clicking.
- **Increase Contrast**: the gridlines go from `Palette.barEdge` to `Palette.textTertiary`; the dashed correction line
  from `Palette.quiet` at full strength (it already is) to 1.5 pt.
- **Differentiate Without Colour**: the correction is dashed and the tone dotted already; the per-ear lines carry their
  labels; the clip warning starts with "Loud songs may clip" whatever its colour.
- **Bold Text**, **Smart Invert** (the curve's Canvas is marked `.accessibilityIgnoresInvertColors()`, as a picture).

### 3.17 Errors in a listener's words

The EQ itself needs no network and has almost nothing that can fail in front of a listener; what can is said through
Core's ErrorWords (CLAUDE.md's rule), with the app's `ErrorNote`:

Both AutoEq pages draw their own "Try again", so they ask `ErrorWords.of(_:admin:gone:retry: true)` - the advice
then leaves trying again to the button (ErrorWords.swift:152-188, read in the review; the first draft quoted the
advice given when there is no button).

- **Offline** (no network, or deadwax not answering, Phase 2's `Reachability`): AutoEq's search and a profile say
  `ErrorWords`' own - "Can't connect to deadwax." and "Check your connection." (`offlineRetry`) - beside "Try again".
  The picker's empty state still shows; "None" and the current correction still work; the suggestion isn't shown.
- **deadwax can't reach AutoEq** (the server's 503): its words as sent - "deadwax can't reach AutoEq just now." - with
  ErrorWords' own advice for a refusal of 500 and up with no `why` (`ErrorWords.swift:181-182`): for an ordinary
  person "If it keeps happening, tell whoever runs deadwax."; for an admin, none.
- **A profile not found** (404): `gone` "AutoEq doesn't have that measurement any more." - no advice; the button goes.
- **A timeout**: "That took too long." - ErrorWords', with no advice beside the button.
- **An import refused**: 3.9's words - each says which line and why, in the listener's words; for an admin the reader's
  own detail (the line's text) under it.
- **The unit couldn't be made**: 3.3, state 11.
- **The kept file unreadable**: no listener-facing words - the phone starts with Off everywhere and Debug's Kept row
  says what was set aside (the setting is lost, which is what the listener would find anyway; nothing to act on).

### 3.18 The look

The Palette (`DeadwaxApp.swift:73-107`) gains, each named for its web token and holding its value (as turntable.md 2.14
names them, so its slice finds them there):

| Palette | value | web token | where |
| --- | --- | --- | --- |
| textTertiary | #8e8ea3 | `--dw-text-3` | the 0 dB lines; gridlines under Increase Contrast |
| accentText | #d8b4fe | `--dw-accent-text` | the right ear's line |
| toggledFill | rgba(168, 85, 247, 0.18) | `--dw-toggled-bg` | the fill under the curve |

And uses `accent` (the curve, the sliders' fill, handles, the suggestion's symbol, checkmarks), `quiet`, `barTrack` and
`barEdge` (tracks, gridlines), `amber` (state 9, a filter left out), `danger` (state 11, an editor's field out of
range), `off` (the curve while Off). Nothing in the EQ's drawing is a raw value outside the Palette.

Type: the system font throughout, as the app's screens; numbers that line up (band labels, held values, filter rows,
the preamp) in `.monospacedDigit()` - they are figures beside words, not code, so not `.monospaced()`.

---

## 4. Storage, and export

**Per output, on this phone - not per person, not on the server.**

- The outputs are this phone's own hardware - its AirPods, its car, its speaker. Another phone has other outputs, and
  the web has no EQ to share it with.
- So it is the phone's, as Normalization is ("This is kept on this phone"): signing out keeps it, and another person
  signing in on this phone hears the phone's EQ. Nothing goes to deadwax.

**The file**: `Application Support/deadwax/eq.json` (backed up with the phone, so a restore keeps it), written
atomically (`Data.write(options: .atomic)`) 0.5 s after the last change (a drag writes once, at its end), and at the
app leaving the front. Read once at launch; EQModel keeps it in memory and gives the engine's queue a snapshot (1.8).

```json
{
  "version": 1,
  "advanced": false,
  "presets": [{"id": "p-7d1c…", "name": "Late night", "gains": [0, 0, 1.5, 0, 0, 0, 0, -1, -2, -3]}],
  "outputs": [
    {
      "key": "bluetooth:60:F8:1D:…", "type": "bluetoothA2DP", "uid": "60:F8:1D:…", "name": "James's AirPods Pro",
      "renamed": null, "seen": "2026-11-12T10:41:00Z", "suggestion": "shown",
      "on": true,
      "correction": {
        "kind": "autoeq", "id": "3f2c9a0d1b7e4c55", "name": "Apple AirPods Pro", "source": "crinacle",
        "rig": "711", "form": "in-ear", "text": "Preamp: -6.0 dB\nFilter 1: ON LSC …", "changed": false,
        "preamp": {"all": -6.0, "left": 0, "right": 0},
        "nextFilterID": 11,
        "filters": [{"id": 1, "kind": "lowShelf", "written": "LSC", "fc": 105, "gain": 2.6, "width": {"q": 0.7},
                     "corner": false, "channel": "all", "on": true}, …]
      },
      "tone": {"preset": "bassBoost"},
      "preamp": {"automatic": true}
    }
  ]
}
```

- `correction.kind`: `autoeq`, `file` (with the file's name and text) or `built`; `null` for none. The text is kept so
  "Back to AutoEq's" works and so a correction's source is never lost; the filters are what plays.
- **A filter** is 1.3's `EQFilter` as written: `kind`, `written` (the type as the file had it, so an export writes it
  back), `fc`, `gain`, `width` (`{"q": …}`, `{"bandwidth": …}`, `{"slope": …}` or `null`), `corner` (a shelf read by
  its corner), `channel` (`all`, `left`, `right`) and `on`. **Its `id`** is the correction's own counter
  (`nextFilterID`), given when the filter is read or added, kept through every edit, never reused within that
  correction: the engine's warm start (1.6) matches a section by it, so adding a filter below another never restarts
  the ones above it. "Back to AutoEq's" and an import start the count again - a new correction, crossfaded whole. A
  section's id in the bank is `.filter(id)` or `.band(0…9)` - two kinds of id, so a band and a filter never match.
- `tone`: `{"preset": "<id>"}` for a built-in (ids `flat`, `bassBoost`, `bassReduce`, `trebleBoost`, `trebleReduce`,
  `vocal`, `loudness`, `smallSpeakers`, `spokenWord`), `{"yours": "<id>"}`, or `{"custom": [ten gains]}`.
- `preamp`: `{"automatic": true}` or `{"automatic": false, "dB": -6.0}`.
- `suggestion`: `null`, `"shown"`, or `"notNow"`.
- **A version this build doesn't know, or a file it can't read**: set aside as `eq-unreadable-<date>.json` beside it,
  and the phone starts with every output Off (Debug says so). Never overwritten in place, never guessed at.
- **Size**: an AutoEq correction is about 1 KB of text and filters; a hundred outputs are a few hundred KB. The file is
  never read on the audio thread.

**Export** is 3.11's - Equalizer APO's syntax through the share sheet, so a curve made here plays the same in APO on
a PC, and comes back the same through Import.

---

## 5. The slices

Five, each merged on `ios`, each leaving everything before it working. The app's version moves at the EQ's merge (to the
next minor: 0.5 at the review, the lyrics having taken 0.4 - Base.xcconfig's `MARKETING_VERSION` - unless the
turntable's slices take it first), with check_project.py, ios.yml and tests/test_ios_install.py
pinned with it, as 0.3 was. The server's version moves only for slice 4's routes, on main. **No Simulator anywhere**
(James's rule): Core on Linux, the engine on ios.yml's macOS runner in offline rendering, and the screens on his phone.

### 5.1 Slice 1 - Core, on Linux

- **Files** (`ios/DeadwaxKit/Sources/DeadwaxCore/`): `EQFilter.swift` (the types, the cookbook in Double, the ranges),
  `EQResponse.swift` (the response, the grid, the top), `EQPreamp.swift`, `EQGraphic.swift` (the bands, the presets and
  their notes), `EQSettings.swift` (the model of 4, Codable, its defaults), `EQOutputs.swift` (3.12's table, the
  suggestion's query), `APOReader.swift`, `APOWriter.swift`, `GraphicEQFit.swift`, `EQBank.swift`, `EQRender.swift`,
  `EQWords.swift`, `EQChart.swift` (the drawn points, the audio graph's points, the summary).
- **APO's source is already read** (the review, 0.3, at 53d885f7f1): 1.3's table pins every form APO plays, so slice 1
  builds them all, and only `IIR` is refused. If the slice finds APO doing anything 0.3 doesn't say, this file is
  corrected first, in its own commit, citing the source line.
- **Fixtures**: `ios/scripts/make-eq-fixtures.py` (numpy and scipy; run with `python -I`), which writes
  `Tests/DeadwaxCoreTests/Fixtures/eq/`:
  - **The cookbook and APO's filter rules written out again in Python**, independently of the Swift - every row of
    1.3's table: centre and corner shelves, S from a slope and from a Q, BW Oct, the defaults, which width wins - at
    **44.1, 48, 88.2, 96, 176.4, 192, 352.8 and 384 kHz**, over a spread of `fc` from **1 Hz** to 0.45 × the rate (and
    one each side of 0.49), gains ±0.1 to ±30 dB, Q 0.01 to 100, BW 0.1 to 4 octaves and slopes 3 to 24 dB: the five
    coefficients; the response on the 1/48-octave grid by `scipy.signal.freqz`; and the first samples of the impulse
    response, until it decays below -120 dB, through **the script's own Direct Form I loop in Python floats** - Double,
    1.5's order of operations, so **the bit-exact reference**. `scipy.signal.lfilter` is Transposed Direct Form II, so
    it rounds differently: it is run over the same as a cross-check, within 1e-9 of the impulse's peak, never as the
    reference (the first draft's "within 1e-12 of lfilter" compared two different roundings).
  - **APO's reading rules written out again** (0.3: case, `Hz` and `dB`, commas, thousands, numbers by `wcstod`'s
    prefix, the defaults, the corner, GraphicEQ's sorting) as a small Python reader, run over `Fixtures/eq/apo/` - a
    few dozen hand-made files, one or more for each case of 3.9 - into the filters each plays, so the Swift reader is
    held to an independent reading rather than to itself.
  - AutoEq's three biquad functions copied from peq.py with its MIT notice, over a dozen real ParametricEQ.txt files
    (`Fixtures/eq/autoeq/`, with a README naming AutoEq and each measurer) - crinacle's AirPods Pro and one AirPods Pro
    2 among them - and, for those with one (oratory1990's HD 650 at least), the result CSV's `parametric_eq` column.
  - The two GraphicEQ.txt files of 3.10 (the HD 650's and the AirPods Pro's), their targets on the grid, and 3.10's
    solve run in NumPy: its unrounded gains, rounded gains and fit.
  - 3.6's preset table and 1.4's close pairs with their true tops (a 4-million-point search).
  - `tests/test_ios_eq_fixtures.py` runs the script into a temporary folder and compares with what is committed
    (skipped where scipy isn't installed); tests.yml's install step gains `scipy` pinned, so CI runs it - a new Python
    test dependency, added there (CLAUDE.md).
- **Tests** (Swift Testing, `ios/scripts/check-linux.sh` and ios.yml's ubuntu job):
  - EQFilterTests: every fixture's coefficients within **1e-13 absolute** (coefficients are of order 1; a relative
    bound means nothing for one near zero, as a band pass's `b1`), the response within 0.001 dB; 0 dB peaks and
    shelves left out; the 0.49 × rate rule; each default and precedence of 1.3; the corner's f0; a too-steep shelf
    refused.
  - AutoEqProfileTests: each fixture profile read, its response against peq.py's within 0.001 dB at 44.1 and 48 kHz,
    and against the CSV's `parametric_eq` within 0.15 dB at 44.1 kHz where there is one (0.4: that curve is the
    unrounded filters'); deadwax's preamp within 0.5 dB of the file's `Preamp:` (both printed).
  - EQPreampTests: never a boost; rounded to 0.1 dB toward quieter; DC and Nyquist counted; 1.4's close pairs found
    within 1e-5 dB of their true tops (the grid alone misses by 0.04-0.07); one for both ears; the file's shared and
    per-ear parts (4); 3.6's preset table.
  - APOReaderTests: every accepted, skipped and refused case of 3.9 with its exact words and line numbers, and every
    reader fixture read to the same filters as the Python reader; UTF-8 with and without a mark, UTF-16 LE and BE (with
    its note), Windows-1252; LF and CRLF, a CR alone refused; `#` lines silent, a `#` mid-line ordinary text; commands
    and keywords with their case (`preamp:` skipped with its note, `Channel: l r` read); `Hz` and `dB` required; commas;
    `1.000 Hz` as 1000; `6.5.1` as 6.5; `OFF` kept off; keywords in any order; several `Preamp:` lines adding up per
    channel; GraphicEQ's points sorted and its comma rule.
  - APOWriterTests: every fixture and every preset on top of each, written and read back - the same filters, bit for
    bit; AutoEq's shape; per ear; an `Fc` of 12.345 Hz written so it reads back as itself (3.11).
  - GraphicEQFitTests: the two fixtures fitted within **0.15 dB RMS and 0.8 dB at most from 20 Hz to 16 kHz**
    (measured 0.065 and 0.47 at worst - the first draft's 0.5 and 1.0 would pass a fit with its Q wrong); the unrounded
    gains within 1e-6 dB of NumPy's, the rounded ones equal (a gain within 1e-6 of a rounding boundary may go either
    way: none in the fixtures, and the test says so if one appears). The same answer every run; between Linux and
    macOS, libm's `sin`, `cos` and `pow` may differ by an ulp, so the two platforms are held to that 1e-6, not to
    each other's bits.
  - EQBankTests: identity exactly when it should be; per-channel lists; the rate's recompute; the version-and-key rule
    of 1.6; `.band` and `.filter` ids never matching each other.
  - EQRenderTests (run over the fixtures' own coefficients, so Swift's and Python's libm can't differ underneath):
    the identity leaves a buffer's bytes untouched; **filtering equals the script's Direct Form I bit for bit**, the
    Float32 output too - which also proves Swift fused no `a·b + c` into one rounding; **blocks of 1, 7, 512 and 4096
    frames give the same output, bit for bit**; a crossfade's weights; a bank mid-crossfade waits and the newest wins;
    a bank for another rate ignored; warm starts by id (a filter added below others leaves their states as they
    were); the counters; one and eight channels. (No denormal flush to test: 1.5 has none.)
  - EQOutputsTests: 3.12's table, AirPlay sets, the suggestion's query ("James's AirPods Pro", "James’s AirPods Pro" ->
    "AirPods Pro").
  - EQSettingsTests: Codable round trip, filter ids and `nextFilterID` kept; defaults Off; a version not known refused.
  - EQWordsTests: every word of 3.13 and 3.9; EQChartTests: the summaries.
- **Mutations**, as Phase 1's (each must fail a test): `alpha = s / Q`; `A = 10^(g/20)` for a peak; the shelf's `+ 2√A·alpha`
  sign swapped; BW's `w0 / s` dropped; a slope's S as slope / 6; the corner's move skipped (`LS … Q` at f0 = Fc); a
  comma refused rather than read; `1.000 Hz` read as 1; a keyword matched without its case; GraphicEQ's points left
  unsorted; the preamp's refinement skipped; the preamp rounded up; Channel R's filters on the left; the crossfade's
  weight linear; the identity test passing a 0.0001 dB peak; the warm start skipped; the warm start by index rather
  than id; a `Device:` line skipped when there are two.
- **Must not touch**: DeadwaxAudio, ios/App, the server, ui/.
- **Verified**: check-linux.sh; ios.yml's ubuntu and macOS jobs; tests.yml (the fixture test). No Simulator.

#### Slice 1, built (2026-11-12)

Built on `ios`, in a spec correction and six commits: the four corrections from APO's source (0.3, 3.8, 3.9, 0.4 -
each with its source line in its commit), then the fixtures and their script; the filters, the response and the
preamp; the GraphicEQ fit; APO's files read and written; the bank and the render; settings, outputs, words and the
chart. The files are 5.1's, and `EQFixtures.swift`, the tests' readers of the fixtures. Nothing under DeadwaxAudio,
ios/App, src/ or ui/ changed, and no version moved.

- **Tests**: DeadwaxCore 655 tests in 86 suites before, **745 in 98** after - 12 suites, 90 tests: EQFilterTests 8,
  AutoEqProfileTests 3, EQPreampTests 8, APOReaderTests 18, APOWriterTests 6, GraphicEQFitTests 4, EQBankTests 6,
  EQRenderTests 12, EQOutputsTests 4, EQSettingsTests 6, EQWordsTests 11, EQChartTests 4. DeadwaxAudio's 93 unchanged.
  `tests/test_ios_eq_fixtures.py`, 9 tests: the script run into a temporary folder, byte for byte what is committed
  (10 since the review, and byte for byte only on the machine that wrote them - see its Review).
- **The fixtures**: 1.5 MB - filters.json 740 KB (171 cases: 59 at 48 kHz, 16 at each other rate), render.json
  256 KB, profiles.json 97 KB, apo.json 83 KB (52 hand-made files of `apo/`), graphic.json 16 KB, preamp.json 5 KB, and
  AutoEq's own files at 7ae0f56 (16 .txt, 2 .csv, its MIT licence and a README naming each measurer).
- **The cookbook**: every coefficient **bit-identical** to the script's Python (the 1e-13 bound holds with nothing
  used); the response within **7.2e-6 dB** of `freqz`.
- **AutoEq's profiles**: within **2.4e-7 dB** of peq.py; against the CSV's `parametric_eq`, the HD 650 within
  **0.107 dB** and the AirPods Max **0.072 dB** (bound 0.15). The preamps, the file's and deadwax's: crinacle's AirPods
  Pro -6.0/-6.0, AirPods Pro 2 (ANC) -3.3/-3.3; oratory1990's HD 650 -6.1/**-6.4** (its top 6.4 dB at DC, the shelves'
  gains summed), its FixedBandEQ -7.4/-7.5, AirPods Max -4.7/-4.8, ER2XR -5.6/-5.6; Super Review's AirPods Pro
  -3.2/-3.3; HypetheSonics' -5.8/-5.8; Rtings' -3.2/-3.2 and DT 770 Pro -6.4/-6.3; crinacle's HD 650 -6.3/-6.3;
  Innerfidelity's -6.3/**-6.7**, Headphone.com's -6.2/**-6.6**, Kuulokenurkka's HD 6XX -6.3/**-6.6** - all within
  0.5 dB. The four gaps over 0.1 dB are each a top at DC (0 Hz), where 1.4 has deadwax look and, it seems, AutoEq's
  preamp doesn't - inferred from the numbers, not read in AutoEq's code.
- **The preamp's close pairs** (1.4): the grid and the f0s alone fall short by 0.057, 0.039 and 0.135 dB (two Q 30
  peaks 1/30 octave apart, Q 10 at 1/8, Q 100 at 1/100 - the spec said 0.045/0.042/0.073); refined, off by 2.5e-11,
  5.9e-12 and 4.0e-12.
- **The presets** at 48 kHz, top and preamp: Bass Boost 6.03/-6.1, Treble Boost 4.77/-4.8, Vocal 3.26/-3.3, Loudness
  5.85/-5.9, Small Speakers 3.08/-3.1, Spoken Word 3.69/-3.7 (3.6's table, held).
- **GraphicEQ, converted** (3.10): the HD 650 in 5 rounds, 54 filters, RMS 0.063 and at most 0.473 dB to 16 kHz,
  4.94 dB above it (at 20.8 kHz; 8.22 dB at 44.1 kHz); the AirPods Pro in 4 rounds, 60 filters, RMS 0.056 and at most
  0.350 dB, 3.76 dB above (6.04 at 44.1 kHz). The unrounded gains within 2.6e-8 and 6.1e-8 dB of NumPy's.
- **The render**: bit for bit with the script's Direct Form I, Float32 out included, at blocks of 1, 7, 512 and 4096 -
  stereo (5000 frames, its largest sample 0.7595), eight channels and one (1500 frames each, 0.7860 and 0.7647), none
  over full scale; 148 impulses, 18944 samples, bit for bit.
- **APO's files**: 440 exports (every fixture, and every preset on top of each) read back to the same filters bit for
  bit, and 10 refused as more than 64 an ear; each of the 14 AutoEq profiles (13 ParametricEQ, one FixedBandEQ) read
  and written back byte for byte.
- **Mutations** (each applied by an exact replace, the whole Core suite run, the file restored byte for byte): all 18
  fail, none by failing to compile - with Channel R's done twice, in the bank and in the reader. What each failed:
  `alpha = s / Q`, 12 tests (the fixtures' coefficients, the profiles, the presets, the fit, the summaries);
  `A = 10^(g/20)` for a peak, 14; the low shelf's `+ 2√A·alpha` as `-`, 6 (the fixtures, DC and Nyquist counted, the
  profiles); BW's `w0 / s` dropped, the fixtures; S as slope / 6, 4 (the corner, too steep, the defaults, the
  fixtures); the corner's move skipped, 3 (the corner, the 0.49 rule, the fixtures); a comma not read, 3 (the comma
  test, the reader's fixtures, the writer's round trips); `1.000 Hz` as 1, 2 (thousands, the reader's fixtures); a
  keyword matched in any case, 3 (case, the fixtures, the round trips); GraphicEQ unsorted, 2 (sorted, the fixtures);
  the refinement skipped, 3 (a sum's top where no filter is, the files' preamps, the presets); the preamp rounded
  toward louder, 5 (rounded toward quieter, one for both ears, the presets, the files' preamps, the export); Channel R
  on the left in the bank, each channel's list; in the reader, 5 (Channel lines, preamps per channel, case, the
  fixtures, the round trips); the crossfade linear, 4 (the weights, warm starts, Off and On, the newest wins); the
  identity at 0.0001 dB, a ten-thousandth of a decibel; the warm start skipped (every incoming state zeroed), 2
  (warm starts by id, Off and On); by index, warm starts by id; a second `Device:` skipped, its own test.
- **Decided where the spec was silent** (James to confirm; 8's answers otherwise taken as recommended):
  - a GraphicEQ point's gain outside +-30 dB is refused with the gain's words (3.9's table; past it the fit's sums
    overflow), and `1e999` - `wcstod`'s infinity - is refused by its range ("inf Hz");
  - the automatic preamp's top is the left's and the right's, with their offsets; the shared list (channels 3 and up)
    plays at the same preamp and isn't looked at separately - a correction with per-ear cuts could leave it louder
    (changed in the review: its own top is counted for it);
  - several ports that aren't all AirPlay are their first; AirPlay rooms are named in their UIDs' order;
  - the chart's range past 24 dB is the next multiple of 6; "decibel" is singular at exactly 1; the summary is over
    every ear's shape, without the preamp or the ears' offsets;
  - a preset's name over 40 characters is cut, not refused; Debug's port names other than "Bluetooth (A2DP)" are mine,
    as are the export's comments for a file or built correction;
  - an export over 64 filters an ear (a converted GraphicEQ and a tone) is written, but its import refuses it; and a
    whole curve topping 30 dB writes an automatic preamp under -30 dB, which import refuses the same way.
- **Not verified**: Swift on Linux - everything above ran on macOS (`swift test`, and check-linux.sh's other two
  steps); ios.yml's ubuntu job is the first Linux run. glibc's `sin`, `cos` and `pow` may differ from Apple's by an
  ulp, which the 1e-13 coefficient bound allows; the render's tests run on the fixtures' own coefficients, so libm
  can't differ underneath them. ios.yml itself. Any real AVAudioSession route (the output table is 3.12's, by enum,
  never by a live `portType`).
- **Review** (2026-11-12, after merging ios at 91c2dab - the turntable's slice 1 and the lyrics; one conflict, in
  notes/ios.md, both sections kept). Read against 5.1, 0.3-0.4, 1.3-1.7, 3.5-3.13, 4 and 8, and APO's source at
  53d885f7f1: the four spec corrections hold (BiQuadFilterFactory.cpp:142-189, PreampFilterFactory.cpp:39-40,
  BiQuad.cpp:37-42 and BiQuadFilter.cpp:47-58, GainIterator.cpp:74-77), and the render keeps 1.5's rules (DF1 in
  Double in 1.5's order, nothing allocated, locked or read from a static per block, the weights and constants copied
  into the state at allocation, the newest bank waiting, warm starts by id, the identity untouched). Changed:
  - **The fixture test holds on any machine.** Run with every libm and numpy result moved by up to three ulps (a
    stand-in for CI's x64 Linux), the script's output failed the old comparison in two places: the GraphicEQ fit's
    unrounded gains moved by up to 9e-8 dB (its Jacobian is a finite difference over 0.001 dB, which magnifies the
    curve's last bit 500 times; the old bound was 5e-9 of the gain), and Treble Reduce's top at 44.1 kHz moved from
    DC to Nyquist (a tie at 0 dB). Now, as the turntable's fixtures do (notes/ios.md), `made.json` records the
    machine (platform, Python, numpy, scipy) and the script's sha256: the sha is checked everywhere, every file byte
    for byte where the machine is the maker's, and elsewhere numbers within 5e-9 of themselves, unrounded gains
    within 1e-6 dB (GraphicEQFitTests' own bound; the script refuses a gain that close to a rounding boundary, and
    the rounded ones are compared exactly), Float64 arrays within 1e-9 of their largest value, Float32 within two of
    their ulps (a curve's dB also within 1e-5 - a 1 Hz filter at 192 kHz moves by 6e-7 dB), the render's input bit
    for bit, and where a top is only where it is clear of 0 dB. The stand-in passes at one ulp and at three; a 10%
    change to the fit's lambda, a peak's A changed by 2.5e-8 of itself, and a level by 1e-6 dB each fail it; a
    change at the last bit (DF1's order, pi to 15 digits) fails only the maker's byte check and the sha. numpy is
    pinned by requirements.txt (2.5.3) and scipy by tests.yml (1.18.1). The project's own .venv has no scipy, so on
    this Mac the test runs (and the full check with it) only in a venv that has - the fixtures were written in one.
  - **No channel over 0 dB under the automatic preamp.** Channels 2 and up played the shared list at the ears'
    preamp, unlooked-at: a shared +6 dB peak that each ear's own filter cancels gave a 0 dB preamp and a channel
    6 dB over full scale. `EQBank.make` now counts the shared list's own top for it when it isn't one of the ears'
    curves at its level (1.4, above); EQBankTests.noChannelGoesOverFullScale (it fails with the change taken out).
  - **Closures typed for Xcode 26.6's Swift**: the multi-statement closures in APOReader, EQBank, GraphicEQFit and
    five tests say their types, as `keptQueue`'s did (17dc79d) - the runner's compiler can't infer some that 6.3
    can; two of these (EQPreampTests' `let sections`, GraphicEQFitTests' `.map { … }.sorted`) were the same shape.
  - **A preset's name is folded without `String.folding(options:locale:)`** - Fold's NFKD less its marks, then
    lower-cased, the way Fold.swift already runs on Linux - since what the Linux Foundation makes of that call isn't
    tested anywhere in Core.
  - Not changed, agreed: every other decision above. Left for James: an export of more than 64 filters an ear (a
    converted GraphicEQ's 60 and a tone) is written, and deadwax's own import refuses it - the import's limit could
    be 70 (the render's 80 less the tone's 10), so every export reads back, or the export could say so first.

### 5.2 Slice 2 - the engine, on macOS

- **Files**: `Sources/CAudioRing/` (a C target: the triple buffer's atomic word and the counters, C11 `stdatomic`,
  indices and bits only - 1.6; built on Linux too); `DeadwaxAudio/EQUnit.swift` (1.2), `EQHost.swift` (1.6);
  `PlaybackEngine.swift` - `configure` attaches the unit, `matchOutput` connects through it, `ensureRunning` calls
  `eqStart`, `Settings.eq` (true; false only for the tests' "no unit" engine), `debug()` gains the unit's status; a
  test-only C shim for the allocation hook (turntable.md 4.3's, built here first); `Package.swift`; ios.yml's
  release-build step.
- **The tests** (DeadwaxAudioTests, offline manual rendering): 1.7's ten, written and run **before** anything is
  built on the unit, their numbers reported to James with the slice; every existing engine test unchanged and passing.
- **And one thing James can hear before slice 3**: Debug's EQ Section with the unit's row and the toggle "Muffle what
  plays" (3.13) - a -24 dB high shelf at 2 kHz through the real unit, so a phone with only this slice answers check 0.
  The one change slice 2 makes in ios/App, with `PlayerModel.swift` (beside :601-602) setting `eqStart` to install that test curve or
  nothing.
- **Must not touch**: the lanes, the sources, GainedSource, StreamSource, the timeline, AudioSessionController; any sound
  with the EQ off (the tests are the proof).
- **Verified**: ios.yml's macOS job runs these; its device build compiles the app; check-linux.sh for the C target and
  Core. No Simulator.

#### Slice 2, built (2026-11-12)

Built on `ios` from 48d3d56 (slice 1 reviewed), in five commits: 1.7's tests first, then CAudioRing, EQUnit and EQHost
(with the few Core additions they use), the engine's wiring, Debug and PlayerModel, and these notes. Measured on an
Apple M2, macOS 27.2, Swift 6.3.3, offline manual rendering; nothing on a phone, and no Simulator. The app's version
didn't move.

- **Files**: `Sources/CAudioRing/` (`audio_triple` - the triple buffer's one atomic word, `atomic_exchange` acq_rel,
  a fresh bit beside the index - and `audio_counters`, relaxed 64-bit words; C11 `stdatomic` only, nothing Apple's);
  `DeadwaxAudio/EQUnit.swift` (the unit, its header and its render, `EQUnitRender`), `EQHost.swift` (the ring's three
  slots, the producers' lock and 1.6's publish rule, the warm-up, `EQUnitStatus` and its Debug rows, `EQTestCurve`);
  `PlaybackEngine.swift` (`Settings.eq`, `eq`, `eqStart`, `insertEQ` in `configure`, both connections in
  `matchOutput`, `startEQ` between prepare and start, `debug().eq`); `Tests/CAllocHook/` (the allocation hook,
  test-only); four test files; `Package.swift`; ios.yml's release step. In Core: `EQRender.make(…, fadeFrames:)` (nil:
  20 ms, as before; 1 is test 3's one-step control), `EQRenderState.isCrossfading`, `EQRenderCounters.init()` made
  public, and Debug's words for this slice. In ios/App: DebugView's EQ section and PlayerModel's `muffle`, `eqStatus()`
  and `eqTest` (beside `lead`). Nothing else of the engine moved: the lanes, sources, GainedSource, StreamSource, the
  timeline and AudioSessionController have no diff.
- **Tests**: DeadwaxAudio 93 tests in 3 suites before, **107 in 7** after - EQEngineTests 6, EQClickTests 1,
  EQRealTimeTests 4, EQDebugTests 3; Core 808 in 110 before, 809 after (EQWordsTests' slice-2 words). The release run
  (`swift test -c release --filter EQRealTimeTests`, ios.yml's new step) passes too, as does every EQ engine suite with
  `DEADWAX_TEST_SCHEDULE_LAG=0.010` (ios.yml's late-buffers step).

1.7's ten, in its order:

1. **The unit is ours, in-process**: `AVAudioUnitEffect(audioComponentDescription:)` hands back `EQUnit` (latency 0,
   tail 0, in place, largest block 4,096) - so 1.2's fallback (`AVAudioUnit.instantiate`, waited for 1 s) is built but
   never ran. **The 93 existing DeadwaxAudio tests pass unchanged** with the unit in every engine's graph, Off.
2. **Off, bit for bit**: 30 s (1,440,000 frames x 2 at 48 kHz) of seeded noise then a log sweep, written as a 44.1 kHz
   16-bit FLAC, rendered with no unit, with the unit Off, and with the unit On at a flat curve (put in at the start and
   again every 5 s): **the same bits, all three**. The unit passed every one of 352 blocks through (0 crossfades: a
   flat bank is the identity, and an identity offered over the identity is taken with nothing done, 1.6).
3. **No clicks** - the click (the largest sample after the 8th-order Butterworth high-pass, in the 200 ms after the
   change), the floor before it, and Core's render of the same changes in one step:

   | change | 1 kHz tone, 1 kHz band (> 8 kHz) | 100 Hz, 125 Hz band (> 2 kHz) | 40 Hz, 63 Hz band | 40 Hz, 31 Hz band |
   | --- | --- | --- | --- | --- |
   | band 0 -> +12 dB | **-129.3** (one step -58.0) | **-110.6** (-75.0) | -111.8 (-87.3) | -102.0 (-93.3) |
   | +12 -> 0 dB | -129.6 (-28.5) | -100.2 (-6.5) | -107.6 (-13.9) | -101.1 (-7.4) |
   | 0 -> -12 dB | -141.7 (-58.0) | -110.3 (-83.6) | -110.3 (-88.2) | -109.3 (-94.2) |
   | -12 -> 0 dB | -141.5 (-40.5) | -118.2 (-25.2) | -110.0 (-41.8) | -110.3 (-16.6) |
   | a preset put in | -146.7 (-47.5) | -111.8 (-18.2) | -114.9 (-21.1) | -114.9 (-21.1) |
   | swapped for another | -127.7 (-37.9) | -110.4 (-16.5) | -109.3 (-15.5) | -109.3 (-15.5) |
   | On -> Off | -144.6 (-34.6) | -122.6 (-29.4) | -114.2 (-20.7) | -114.2 (-20.7) |
   | Off -> On | -131.7 (-38.7) | -113.4 (-87.2) | -113.4 (-92.1) | -113.4 (-92.1) |
   | another output's curve | -147.0 (-67.9) | -120.0 (-41.7) | -121.9 (-28.5) | -121.9 (-28.5) |

   dBFS; limits -110 (the 1 kHz column) and -95 (the rest), every change under its limit. 1.6's numpy said -129/-142,
   -102 and -119/-102/-108 crossfaded and -58/-73/-87/-93 in one step: within a dB or two of each, but for the 63 Hz
   band's +12 dB (-111.8 here, -119 there). The floors: -138.2 to -157.8 dBFS - -150 and below with the tone at -6
   dBFS, -138 to -144 after a +12 dB band, the tone 12 dB louder and its own leak through the high-pass with it. The
   one-step control hears the first change of the 1 kHz and 125 Hz cases (-58.0 and -75.0), so the measure can hear
   a click. The unit's output is Core's 20 ms render of the same changes, bit for bit. **The settle** (the 31 Hz band,
   a 40 Hz tone): 0 -> +12 dB within 0.5 dB of its new level after **50 ms**, overshooting by **1.20 dB** (1.6: 50 ms,
   1.3); the other three settle in 25 ms with no overshoot. Each 25 ms of +12 dB's envelope: 0.36 2.96 2.13 1.59 1.68
   1.78 1.78 1.76 … dB.
4. **Joins**: one 440 Hz tone cut in two near a peak (test sounds 9 and 10's shape), and a 44.1 kHz song into a 96 kHz
   one, through Loudness at 0 dB of preamp (it boosts): the unit's output is **Core's render over the no-unit engine's
   own render, bit for bit** (91,904 and 43,904 frames - to a block before the songs end, where the output stops on
   its own clock).
5. **No allocation**: the unit's render block called as the framework calls it, 10,000 times (blocks of 512, every
   100th 4,096; passing through, a crossfade in, filtering, a bank for another rate, a bank arriving mid-crossfade, Off,
   On again, and 1,000 calls with no buffers handed): **0 allocations and 0 frees** on that thread, release, the hook's
   canary seen first. 5 crossfades, 1 waited, 1 for another rate - the run covered what it says.
6. **The response**: an AutoEq-shaped correction and Bass Boost (8 sections, automatic preamp -8.6 dB), an impulse at
   each of 44.1, 48, 88.2, 96, 176.4, 192, 352.8 and 384 kHz, rendered past the slowest section's -120 dB (11,669
   samples at 44.1 kHz to 101,606 at 384): within **5.6e-7 dB** of `EQResponse` from 20 Hz to 20 kHz at every rate.
   And a 1 s log sweep at each rate is Core's render, bit for bit.
7. **A rebuilt engine** (`rebuild()`): the new unit's output, from its first sample, is Core's render of the curve
   from a fresh start, bit for bit; 0 crossfades, 2 allocations. And **a pause** frees the unit's memory (Debug: "the
   output is stopped") and play allocates it again with the curve put back before the first sample, no crossfade -
   1.2's "every play after a pause allocates afresh", seen offline.
8. **The cost**: 74 sections a channel, stereo, 192 kHz, a new bank every block of 4,096 (always crossfading): **1.83
   ms a block, 8.6% of its 21.3 ms** (worst 2.03 ms), release - under 1.10's 10%, but above its estimate of 6%, and
   with 1.4 points to spare on this M2; the runner's cores are their own question.
9. **Silence**: the +12 dB Q 10 peak at 20 Hz and a high pass at 86.4 kHz at 192 kHz, a second of full-scale noise,
   then 5 minutes of zeros: the output exactly 0 from 25.4 s; **every 10 s of silence cost 1.00x a block of noise**
   (0.0352-0.0353 ms against 0.0352 ms, medians), through the states' fall into the subnormals. No fallback needed.
10. **The locked screen's block**: 4,096 frames render; 4,097 is answered -10874
    (`kAudioUnitErr_TooManyFramesToProcess`), counted (refused 1), nothing pulled, the output untouched.

And Debug's **Muffle what plays** through the real engine: an 8 kHz tone **-23.458 dB**, a 200 Hz one -0.081 dB - each
its response in `EQResponse` to the thousandth - and turned off while it plays, every sample after the crossfade as
it went in.

- **Departures from the spec, and why**:
  - **The render block reaches the framework through the Objective-C runtime**, not a Swift
    `override var internalRenderBlock`. Measured in release: with the override, **one allocation and one free on every
    render** (10,000 of each in test 5) - the framework is handed a block around a Swift closure, and on each call that
    block turns its pull block into a Swift closure, which needs a context on the heap. Now the block is
    `@convention(block)` with the pull typed `@convention(block)` too (`EQRenderBlock`, `EQPullBlock`), made once in
    `init` capturing only the header, as 1.2 says, and handed out by an `internalRenderBlock` getter that
    `EQUnit.register()` adds with `class_addMethod` and `imp_implementationWithBlock` before registering the subclass.
    Nothing on the render sends a message: the getter is asked as the unit is made and at each allocation, never on
    the render (three times a start, the Review measured). Test 5 checks the framework's view of the getter
    (`value(forKey: "internalRenderBlock")`) is this block.
  - **`.loadInProcess` is macOS's alone** (iOS's SDK marks it unavailable): the fallback asks for it on macOS and for
    no options on iOS, where a subclass registered in-process is made in-process anyway. Never run (test 1 passed).
  - **Test 9's bound** is each 10 s stretch's median block against the median noise block - not the single slowest
    block, printed beside it: 0.10-0.12 ms (2.9-3.3x) here, at 134.8 s in one run and 278.4 s in the next, never where
    the states go subnormal - the scheduler, which a denormal slowdown (lasting as long as the states are subnormal)
    can't hide behind.
  - **Test 8 bounds the mean** of the unit's own timing (`EQRender.process` per block - what Debug's Render row
    shows), the worst printed (the Review made it the median, at 15%); tests 5, 8 and 9 bound only in the release build - in debug, Core's unoptimised loops
    allocate (about 6,000 a 512-frame block) and cost 3x the block at 192 kHz. That is the build `install.sh --debug`
    makes: **a Debug build of the app is no test of the EQ's real-time behaviour.**
  - **Test 6's sweep** is held bit for bit to Core's render over the no-unit engine rather than turned into a
    response (stronger, and the impulse already gives the response).
  - **Test 3's floor** is required to be 15 dB under each limit (it is 28 dB or more) and printed, rather than held to
    -150 dBFS (above).
  - **Debug's new words** (3.13 didn't have them): "In the graph: the output is stopped" (the unit holds no render
    memory between a pause and the next play), "No audio engine yet: it's made when something first plays", and
    Started with's "The test curve, put in …", "Off, put in …", "Nothing put in: the output started passing every
    sample through" and "The output hasn't started yet"; the section's header "EQ" and the toggle's footer. The rows
    shown are the unit's - Unit, At this rate, Changes, Started with, Over full scale, Render; Output, Key, Curve and
    Kept come with slice 3's settings. At this rate's "left out" never shows yet: the host has sections, not filters.
  - **Muffle off puts in Off** (the identity), so "the test curve or nothing" is the test curve or Off - the same
    sound, and Debug's Started with says which.
  - **The warm-up** (1.5) runs once a process when the first host is made - the engine's init, on the main thread -
    rather than on a queue of its own.
- **What only the phone can know** (6's check 0, and 7): whether iOS also hands back `EQUnit` in-process from
  `AVAudioUnitEffect` (0a's "In the graph"; if not, Debug's "Not made: …" and the music plays on), and whether iOS's
  framework asks the added getter as macOS's does (Debug's Render block row, 0a); Muffle heard (0a), toggled across a join (0b), nothing changed with
  it off (0c), the lock screen and AirPods with it on and off (0d); the render's time on the phone's cores (Debug's
  Render row), and whether a locked screen asks for more than 4,096 frames (its refused count).
- **Not verified**: Linux - CAudioRing and Core's changes compiled and ran only on macOS (check-linux.sh can't run
  here; ios.yml's ubuntu job is the first); ios.yml's Xcode 26.6 Swift (every multi-statement closure in the new code
  says its type); ios.yml itself, and test 8's 10% on the runner's cores.
- **Review** (2026-11-12, on 48d3d56's five commits). Read against 5.2, 1.1-1.10, 3.13, checks 0/0a, 7 and the
  Design review, the code before the account; measured on the same M2 in release, through the build lock. The
  render keeps 1.5's rules: CAudioRing is plain C11 (`atomic_exchange_explicit` acq_rel on the triple's word, relaxed
  counters), the bank is copied into the slot under the producers' lock and the render takes the newest by one
  exchange, a bank for another rate is ignored and counted, and nothing on the render allocates, locks, sends a
  message or reads a static or a Swift class. Changed:
  - **The render block's delivery, measured three ways** (1,000 renders each, the hook's canary seen): an `override
    var internalRenderBlock` returning a stored Swift closure, **1 allocation a render**; the override returning a
    stored `@convention(block)`, **3**; the builder's getter added with `class_addMethod`, **0**. No plainer way
    measures 0, so it stays. What a render costs beyond the arithmetic: one `_Block_copy`/`_Block_release` of the
    framework's pull (an `__NSMallocBlock__`, measured, so a reference count, not a copy) and one retain/release of
    the block's context - atomics, no allocation. The framework asks for the getter through `-[AUAudioUnit
    renderBlock]` (AudioToolboxCore; the same Objective-C message on iOS - there is no Swift path to it), never on
    the render: twice as the unit is made and attached, once at each allocation (3 a start; a pause and play 1 more;
    a rebuild's new unit 3 of its own). Registration is once a process (a `static let`, so thread-safe). The getter
    is now added with **AUAudioUnit's own type encoding** (`@?16@0:8`, read from the inherited method) rather than
    `@@:`, which named the result an object rather than a block - harmless to `objc_msgSend`, but what KVC and
    method signatures read. **Debug says whether it was asked**: a "Render block" row ("iOS asked for it 3 times";
    "iOS hasn't asked for it, so no sound can go through the EQ"), counted by the getter outside the render and kept
    across allocations; and the Unit row's new "waiting for its first block of sound" - between an allocation and
    the first block, where it said "passing" before any sound had passed.
  - **Through AVAudioEngine's own real-time render** (new, EQRealTimeTests.theFrameworksOwnRenderAllocatesNothing):
    a realtime manual-rendering engine, a looping player through the main mixer and the unit, 50 blocks to warm
    then 1,000 counted (512, every 100th 4,096), Bass Boost, a vocal preset and the identity put in at 200, 500 and
    800: **0 allocations and 0 frees** with the unit and without it, 3 crossfades, 1,050 blocks, the getter asked 3
    times. Test 5 called the block by hand; this is the framework calling it.
  - **Two crashes found and stopped.** An output of **more than 8 channels** (a big USB interface): AVAudioEngine
    answers the unit's refusal of the format with an Objective-C exception (-10868) nothing in Swift can catch -
    measured with ten channels. `insertEQ` now leaves the unit out ("Not made: this output has 10 channels, and the
    EQ takes at most 8"), mixer -> output as before (EQHostTests, ten channels rendered). And **a reconnect after a
    failed start**: an engine left prepared holds the unit's render memory, and the unit refuses a new format
    while it does (AUAudioUnit's rule) - the same exception, measured; the mixer alone takes it. `matchOutput` now
    stops the engine first when the unit is allocated (EQHostTests pins the mechanism: prepared, `shouldChange`
    false, stopped, reconnected at 44.1 kHz, started).
  - **A bank for the old rate could push out the start's.** A settings change that read the rate just before a
    start at a new one made its bank second, at the same version: `publish` took it (not older), the ring offered a
    bank the render only ignores, and the settings would play Off until the next change. Now a bank of the last
    published version, made for another rate when that one was made for the unit's, is dropped and counted as
    older; a newer version always goes in (EQHostTests).
  - **Muffle can't be left on.** It was off at each launch, but a launch can be days apart: it now goes off as
    Debug closes (`onDisappear` - back out, or another tab). Locking the phone doesn't close Debug, so E0d still
    runs with it on. docs/ios.md's E0a-E0d say so, and E0a asks for the Render block row's number.
  - **Test 8 bounds the median at 15%** (was the mean at 10%, with 1.4 points to spare): measured 1.83-1.85 ms,
    8.6-8.7%, worst 2.0-2.2 ms. A shared runner's preemptions move a mean and not a median; 15% still fails the 2x
    slowdown (17%) the test is there to catch. Test 9 is medians already (1.00-1.07x against 2x) and stays.
  - **Closures**: the warm-up's `withUnsafeBufferPointer` says its type; the others in the new code already did.
    ios.yml's release step (`swift test -c release --filter EQRealTimeTests`) is right as it is.
  - Not changed, agreed: Off is untouched on every path - configure, matchOutput, a configuration change, rebuild,
    pause and play, a new rate (tests 2, 4 and 7, and the 93 older tests with the unit in every graph); startLead,
    latency and positions don't read the unit (latency 0, tail 0); the fallback to mixer -> output when the unit
    can't be made. Left for slice 3: `eqStart` makes its bank, the automatic preamp's search with it, on the start's
    path.
  - **Tests** after it: DeadwaxAudio **111 in 8 suites** (EQRealTimeTests 5, EQHostTests 3, both new or grown), Core
    809, in debug and in release; the unsigned device build; check_project.py; pytest's iOS files.

### 5.3 Slice 3 - the simple face

- **Files**: `ios/App/EQ/` - `EQModel.swift` (`@MainActor @Observable`, made once in DeadwaxApp beside PlayerModel and
  put in the environment: the settings, the store, the route observed, the snapshot, publishing to every host),
  `EQStore.swift` (4), `EQScreen.swift` (3.2-3.3), `EQCurveView.swift` (3.4, the audio graph), `EQSliders.swift` (3.5,
  and 3.15's stepper rows), `EQPresetsScreen.swift` (3.6), `EQOutputs.swift` views (3.12), `EQRoute` (an enum of the
  EQ's pages, drawn by a `navigationDestination` in You's stack and in the sheet's own); `PlaybackSection.swift` (the
  row); `NowPlayingMenu.swift` and `NowPlayingView.swift` (the item, the sheet); `NowPlayingWords.more`; `InfoView.swift`
  and Core's Info (the two rows); `DebugView.swift` (3.13's rows); `DeadwaxApp.swift` (the Palette's three, EQModel);
  `PlayerModel.swift` (`eqStart` from EQModel's snapshot); docs/ios.md (You > Playback > EQ, Playing's •••,
  Info, Debug, "What it can't do yet": AutoEq until slice 4, Advanced until slice 5); notes/ios.md ("The EQ").
- **Core additions**: `EQScreenRules` (which output the page shows and when it may switch - only the EQ page, only on
  top, never under a finger, a pushed page bound to its output, 3.2; a change while Off turns it on; the short
  setting; Other outputs' order), tested on Linux - with a mutation letting a pushed page follow the route, which must
  fail.
- **Must not touch**: the engine (slice 2's), Normalization's rows, Now Playing's layout but for the one menu item and
  the sheet.
- **Verified**: Core's rules on Linux; the unsigned device build on ios.yml; the screen in the hand on James's phone
  (checks 1-16). Nothing here needs a Simulator: what the runner can't show - touch, VoiceOver, Dynamic Type, the
  sound - is the phone's list.

#### Slice 3, built (2026-11-12)

Built on `ios` from 6664261 (slice 2's review), in six commits: the rules in Core with the start's bank made ahead,
EQModel and EQStore, the screens, the ways in, app 0.5 (5), and these notes. Measured on the same M2; nothing drawn or
heard on a phone, and no Simulator, so every look, touch and sound here is checks E1-E16's (docs/ios.md).

- **Files**: in Core, `EQScreenRules.swift` (EQPage, EQSound, the settings' changes, EQLine, EQPlaying, the rules,
  EQSliderRules), `EQDrawing.swift` (the curve with its preamp, its summary and audio graph), `EQStartBook.swift`
  (EQStartBook, EQStartDesk, EQTaker, EQTicket, EQStartTime), and words in `EQWords` and `Info`
  (`InfoDebug.Engine.eq`, `NowPlayingWords.more(…, eq:)`); `EQSettings.unreadableName(day:attempt:)`. In ios/App/EQ:
  `EQModel`, `EQStore`, `EQRouteReader`, `EQScreen`, `EQCurveView`, `EQSliders` (with `EQStepperRow`),
  `EQPresetsScreen`, `EQOutputViews`, `EQNameAlert`, `EQRoute`. Changed: PlayerModel (Muffle and the slice-2 hook out,
  `eq?.attach(engine)` in), DeadwaxApp (EQModel, the Palette's three), Routes (`AppRoute.eq`), RootView (saved as the
  app goes to the back), PlaybackSection, NowPlayingMenu, NowPlayingView, InfoView and InfoDetails, DebugView. The
  engine (DeadwaxAudio), Normalization's rows and Now Playing's layout have no diff but the one item and the sheet.
- **Tests**: DeadwaxCore 809 in 110 suites before, **849 in 113** after (EQScreenRulesTests 22, EQDrawingTests 9,
  EQStartBookTests 9, and expects added to EQSettingsTests and EQWordsTests); DeadwaxAudio 111 in 8 before, **114 in
  9** (EQStartTests 3, against the real EQHost and engine).

**Slice 2's review, item 1 - the start's bank made ahead.** The start made its output's bank on the engine's queue,
the automatic preamp's golden-section search and all. Now EQStartBook keeps, for every output that is on, its bank
made ahead - off the main thread, as settings change and outputs are met - at the rates it has started at (the last
three) and at 48 and 44.1 kHz; the start looks its curve up and stamps it with its own version. A rate never seen is
made then, and Debug's Start took says so. EQStartTests on the real EQHost, 200 starts each:

| a start | debug, median / worst | release, median / worst |
| --- | --- | --- |
| slice 2's hook (the test curve made at the start) | 0.810 / 2.057 ms | 0.059 / 0.116 ms |
| Bass Boost, made at the start | 1.371 / 1.615 ms | 0.121 / 0.274 ms |
| Bass Boost, made ahead | **0.001 / 0.012 ms** | **0.000 / 0.011 ms** |
| ten bands, made at the start | 2.751 / 3.018 ms | 0.238 / 0.408 ms |
| ten bands, made ahead | **0.001 / 0.019 ms** | **0.000 / 0.003 ms** |
| ten bands and a 10-filter correction, made at the start | 5.286 / 6.083 ms | 0.435 / 0.590 ms |
| the same, made ahead | **0.001 / 0.031 ms** | **0.000 / 0.002 ms** |

Through the offline engine's own start (prepare, `eqStart`, start): "0.016 ms, its curve made ahead" in debug, 0.004
ms in release - Debug's Start took row, which check E8 reads on the phone. (Run inside the whole suite, with tests in
parallel, the debug numbers double: 2.09 ms for Bass Boost made at the start, 0.001 made ahead.)

**Item 2 - a new version on a route or rate change.** EQHost drops a bank of the last published version made for
another rate while the newest is at the unit's rate (slice 2's review), so a change racing a start at a new rate could
have left the old bank in. Every change, every route change and every start now takes a version of its own from one
counter (EQStartDesk, under its lock), and the main thread takes it **before** reading the host's rate. EQStartBookTests
plays all 20 orders of a change and a start at a new rate against a model of the host's two rules; EQStartTests the
same against the real EQHost: each ends with the new settings at the unit's rate. Mutations: a change that takes no
version of its own fails theRightBankLandsInEveryOrder; a start that takes none fails versionsOnlyRise and three
more; each restored byte for byte.

**5.3's mutation**: `maySwitch` with `kind != .output` (a pushed page following the route) fails
aPushedPageStaysOnItsOutput with 6 issues. Restored.

- **Departures from the spec, and why**:
  - **Correction, Preamp and Advanced aren't drawn** (slices 4 and 5), and nothing stands in their place: the page is
    3.2's sections 1, 2, 4, 6 and 8, in that order, so slice 4 adds Correction between the curve and Tone, slice 5
    Preamp after Tone and Advanced after Other outputs. 3.14's reading order skips Correction until then, and the
    audio graph has the one series, "What you hear".
  - **The App's file is `EQOutputViews.swift`**, not 5.3's `EQOutputs.swift`: Core has an `EQOutputs` already, and one
    name for two things in two modules misleads whoever reads either.
  - **The sliders' row is about 255 pt**, not 236: the 200 pt track, 14 pt above and below it for the knob's half and
    the held value's capsule, the band names and the row's padding. The columns are 3.5's width (the row's insets are
    zero).
  - **The presets page keeps Custom for its own life** once the tone has been Custom while it's open, and tapping it
    puts back those gains - so trying a few presets never loses where you left the sliders. 3.6 had Custom only while
    the tone is Custom, which would have dropped it at the first preset tapped.
  - **The swipe Forget in Other outputs asks first**, with Forget This Output's dialog: 3.12 named no confirmation,
    and a swipe deletes more easily than a button at a page's foot.
  - **"Done" is on every page of the sheet**, closing the sheet (the sheet's own dismiss, carried in the environment):
    3.1 put it at the sheet's top; from the presets page, a Done that only went Back would have been a trap.
  - **The pushed page's line** (3.2) and state 7's "Not connected: this is what it plays when it is." sit in their
    section's header, in `.footnote` `quiet`, case kept; the line under the curve is the curve section's footer.
  - **"On top" includes Now Playing**: the EQ page on You's stack counts as covered while Now Playing is over it (and
    while an alert or the dialog is up, and while its tab isn't shown), so it never switches, and VoiceOver never
    hears "EQ for …", where nobody is looking. The sheet's own page follows the route as 3.2 says.
  - **Steppers hold through their own `onEditingChanged`**: a stepper's press is a hold, so the page doesn't switch
    under it - no heuristic needed.
  - **New words** (each in EQWords and tested): Debug's Curve row "Off" while the output's EQ is; the toolbar •••'s
    name "More for this output" (as the album page's "More for this album"); Debug's "Start took" ("0.031 ms, its
    curve made ahead" / "1.90 ms, its curve made then, for 44.1 kHz"); the stepper rows' "31 Hz" … "16 kHz"; and
    Muffle's footer, whose "Off, the unit passes every sample through untouched" (slice 2's) is now "Off, the
    output's own EQ plays again".
  - **The speaker sorts last in Other outputs when it was never met** (its `seen` is empty), the others most recent
    first, ties by name. Renaming a never-met speaker keeps its setting first, as it would start, without counting it
    as met.
  - **Off is drawn in `quiet` at `Palette.off`** (the spec's "grey").
  - **Lines of different lengths don't morph**: they can't, point for point. While there is no correction a line is
    always the grid's 241 points (`EQChart.grid`, the ten bands' centres on it), so every simple-face change morphs -
    EQDrawingTests' everyToneIsDrawnOnTheGrid holds it for every preset, Custom, each band alone and Off; slice 4's
    corrections add their own f0s, and a line whose length changes is drawn at once.
  - **Muffle, and the unit's status, moved from PlayerModel to EQModel**, through the same door as every change: on,
    the test curve on its own key; off, the route's own curve (no longer Off).
  - **EQModel reads the route again before each publish**, so a change never lands on an output that has just gone
    (the notification can trail the route by a moment).
  - **eq.json is never written over when it can't be read as it should**: one that couldn't be moved aside, and one
    that is there but can't be opened yet - a background launch before the phone's first unlock, under data
    protection - which EQModel reads again at `protectedDataDidBecomeAvailable`. Without that, a locked launch would
    have started every output Off and saved it over the real file half a second later. A second unreadable file the
    same day is set aside as `eq-unreadable-<day>-2.json`, never over the first.
  - **A page whose output is forgotten keeps its name while it goes** (EQModel remembers each output as last read).
  - **The host clock**: EQModel times the start with `AVAudioTime.seconds(forHostTime: mach_absolute_time())`,
    `PlaybackEngine.hostSeconds()` itself being internal to DeadwaxAudio, which this slice doesn't touch.
  - **"EQ on" is said by EQModel**, after the change that turned it on (a preset chosen, a slider moved), wherever
    the change was made.
- **What only the phone can show**, by check: You's row and its footer (E1); the page's look - the curve, the grey Off,
  the sliders' columns and knob, the list's spacing (E2, E4); the route followed, and not under a finger (E3); a
  preset heard, and its preamp (E4); a drag heard as it goes, the tick, the knob not jumping, the double-tap (E5);
  the name alerts and their refusals coming back (E6); On/Off clean (E7); the start's curve from the first sound
  and Start took on the phone's cores (E8); the presets by ear (E9); the menu item's subtitle - whether iOS 17 draws
  the second Text - and the sheet's Done (E10); Info's rows (E11); a locked album, refused blocks (E12); the two rates
  (E13); VoiceOver's reading, the audio graph, the adjustable bands (E14); the outputs' UIDs (E15); the stepper rows
  and wrapping at the largest size (E16). And beyond the checks: where the toolbar puts ••• beside Done, whether the
  sliders' drag ever loses to the List's scroll, whether `routeChangeNotification` arrives for every switch, and
  whether a Forget from the dialog pops the page cleanly.
- **Not verified**: anything on a phone; ios.yml's Xcode 26.6 Swift on the App's new files (every multi-statement
  closure says its type, but the App target is only built on this Mac's Xcode 27.1); each commit building alone - the
  model-and-store commit was not built by itself (it holds no file the later ones change but DeadwaxApp.swift's
  Palette lines, which came with the screens).
- **Review** (2026-11-12, on 6664261..6ee2eca's six commits). Read against 3.1-3.6, 3.12-3.18, 4, 5.3, 6's E1-E16 and
  the Design review, the code before the account, and Core's rules mutated: 25 mutations of EQScreenRules, EQStartBook
  and EQDrawing, of which 5 passed every test (now each fails one, below). Changed:
  - **A slider's knob jumped as the finger passed back over where it came down.** The drag took its engaging side
    (6 pt up or down) from the finger's side of the touch-down point at every move, so a drag engaged downward and
    brought back up past that point moved the knob 12 pt - 1.44 dB, heard as a step - at once, the wrong way. The
    drag's state is Core's now (`EQSliderDrag`: the side kept from the moment it engaged), and EQSliders draws it;
    `aDragNeverJumps` walks a finger back over the point both ways in 0.1 pt steps and fails on the old rule.
  - **A page could change another output.** `EQModel.output(key)` fell back to the output now for a key it didn't
    know, and never remembered an output while it was the route - so a page bound to the AirPods, drawn while they
    played, then forgotten from another page, would have read and written the car's setting: the one thing 3.2's
    binding is for. The rule is Core's (`EQScreenRules.output`: as kept, the route's own, the speaker, as the page
    last drew it, else named by its key - never another output), every answer remembered; `aPageIsAlwaysItsOwnOutput`
    fails with the old fallback.
  - **eq.json could stay unwritten for the rest of a locked launch's process.** The first unlock's observer was added
    after the read, so an unlock between the two was never heard - and an app suspended in the background when the
    phone unlocks may not hear it at all. EQModel now reads again once the observer is in, and whenever the app
    comes to the front still waiting (RootView's `.active`, `EQModel.becameActive`) - the phone is unlocked if the app
    is in front. Still never written over while it can't be opened.
  - **A hold could outlive its slider.** EQSliders lets go when it disappears with a finger down (a second finger on
    Back, the text size crossing into the stepper rows), so the page and EQModel aren't left holding - which kept
    eq.json unwritten until the app went to the back.
  - **For CI's compiler**: EQStartTests' `host.newest.map { b in var c = b; … }` says its type.
  - **Five tests that passed with the code broken** now fail: the clip warning's edge (a hand preamp taking away
    exactly the curve's top is enough), a band moved to where it already is (a preset stays itself, Off stays Off - a
    VoiceOver step at the range's end), a route with no output leaving the page connected, a change's bank kept for
    the next start at that rate, and every part of a sound - the switch, the tone, the correction, the hand preamp -
    dropping the banks made from it.
  - **Agreed, not changed**: the one version counter and its two orders - every mutation of the desk tried (banks
    never dropped, kept unchecked, unstamped, a start's bank not kept, Muffle ignored, rates not noted) fails a test,
    and no stale bank can be published (`keep` checks the sound under the lock, a bank is a function of its sound and
    rate alone, and is stamped at use); the store otherwise (a file there but unreadable is never written, a garbled
    or newer one is moved aside under a name never used, writes are atomic); a route change mid-drag (the page and
    the drag keep their output, the sound follows the route, the file waits for the finger); Off, presets, Custom and
    Forget as 3.2, 3.6 and 3.12 have them; no diff in DeadwaxAudio; no newer-only syntax or API in the App's or Core's
    new files, and no other multi-statement closure whose result type is inferred.
  - **The departures**: 17 sound as given. Two were incomplete as written: "a page whose output is forgotten keeps its
    name" (the route's own wasn't remembered - fixed above), and "lines of different lengths don't morph", which holds
    for slice 3 (every simple-face line is the grid's 241 points) but not as EQVector is: its `-` of two lengths is
    `.zero`, so the animation would draw the old values against the new frequencies for 0.25 s and then jump - slice
    4, whose corrections add their own f0s, must draw such a change without the animation.
  - **James's to decide** (design, not changed): the presets page keeping Custom for its life (3.6: only while the
    tone is Custom); the swipe Forget asking first (3.12 named no dialog); Done on every page of the sheet (3.1: the
    sheet's top); the tick only when a drag lands on 0 - a fast one stepping over 0 gives none (3.5's "crosses into");
    the "+12", "0", "-12" scale inside the first column, under its knob's travel (3.5's place).
  - **For the phone**: a route with no outputs, if iOS ever reports one mid-switch, is the speaker (EQRouteReader, on
    the main thread and the start's) - EQPage's rule would leave the last output standing, but EQModel never hands it
    one; E3 and E8 show whether the page flickers to "iPhone speaker" as AirPods come and go.
  - **Tests**: Core **853 in 113** (`aDragNeverJumps`, `aPageIsAlwaysItsOwnOutput`, `everyPartOfTheSoundDropsItsBanks`,
    `aChangesBankIsKeptForTheNextStart`, and expects added to four more), Audio 114 in 9; the unsigned device build
    (Xcode 27.1); check_project.py; pytest's iOS files; the ios sims. Not verified: ios.yml's Xcode 26.6 Swift, and
    anything on a phone.

### 5.4 Slice 4 - AutoEq

- **On main first** (2.1.7): `src/autoeq.py`, `src/api/autoeq_endpoint.py`, `src/routes/eq.py`, the router included in
  `src/api/app.py` with `current_user`, the three tables in `store.py`, `tests/test_autoeq.py` and its fixtures,
  `tests/test_logins.py` ROUTES, README, docs/troubleshooting.md, CLAUDE.md's map lines, notes/ios.md - one commit,
  the patch bumped in it. Then main merged into ios.
- **On ios**: `Routes.swift`'s `autoEqSearch` (`GET /deadwax/eq/autoeq`, `["q", "limit"]`) and `autoEqProfile`
  (`GET /deadwax/eq/autoeq/{id}`, `[]`); `tests/test_ios_contract.py` ROUTE_COUNT up by two and the models held, in the same
  commit; Core's `AutoEqResults`, `AutoEqProfile` and the client's two calls (Linux-tested against the server's
  answers, exported by the test as fixtures); Core's `EQSuggestion` (3.7's one, several or none, over the rows -
  Linux-tested with the AirPods Pro's five, the HD 650's one and a speaker's none; a mutation offering the first of
  several must fail); `EQCorrectionScreen.swift` (the picker), `EQProfileScreen.swift`, the suggestion in EQModel and
  the Correction section; docs/ios.md (AutoEq, and picking AirPods by generation).
- **Must not touch**: the engine; the reader (used as it is); any other route.
- **Verified**: pytest (main and ios); Core on Linux; the device build; checks 17-21.

#### Slice 4, built (2026-11-12)

The phone's half, built on `ios` from 37e6ce1 (slice 3 and main's 2.1.7 merged), in three commits: the contract, the
answers and the suggestion's rule in Core; the screens; the docs and these notes. Nothing drawn or heard on a phone,
and no Simulator: every look, touch and sound here is checks E17-E21's (docs/ios.md, 6's 17-21).

- **Files**: in Core, `AutoEq.swift` (AutoEqMeasurement, AutoEqResult, AutoEqResults, AutoEqProfile and its
  `correction()` through APOReader as it is, AutoEqPage, AutoEqAsk - the limit 50, the longest query 100 scalars,
  the 0.3 s pause - and DeadwaxClient's `autoEq(search:limit:)` and `autoEqProfile(id:)`), `EQSuggestion.swift`
  (EQSuggestion, EQSuggestionRules, `EQSettings.use` and `.mark`, `EQOutputSetting.uses`, `EQDrawing.profile`), the
  two Routes, and words (`Picker.tryAgain`, `Picker.tooOld`, `Profile.gitHubAddress`; `models` says "1 model"). In
  ios/App/EQ: `EQCorrectionScreen`, `EQProfileScreen`, EQModel's suggestion, `use` and `mark`, EQScreen's Correction
  section and `EQSuggestionRow`, EQRoute's `.correction` and `.profile` (and `isPage`), `EQSheetStack` (the sheet's
  path, in its environment), AppNavigation's `backToEQPage()`, and EQCurveView's crossfade. The project file is
  unchanged: the App folder is synchronised. No diff in DeadwaxAudio or src/.
- **The answers the tests read are the server's**: `ios/scripts/autoeq_answers.py` asks the whole app (start(), a real
  store) over tests/test_autoeq.py's own fake GitHub and fixtures, the routes' clock held at 2026-11-12T09:30:00Z, and
  writes `Fixtures/autoeq/answers.json` (18 KB, ASCII): seven searches, two profiles, two 404s (a result GitHub has no
  file for, an id not in the list), a 503 for a profile (GitHub gone after the list was kept) and one for a search (no
  list). test_ios_contract.py holds the file to what the helper makes now (as lyrics'), every answer in it to the
  models, the models' fields to `row_answer`, `profile_answer` and the search's literal, and AutoEqAsk's two numbers to
  the route's bounds; ROUTE_COUNT 24 -> 26 in the Routes' commit. AutoEqTests asks DeadwaxClient each case's path and
  query and reads back what the server sent, and says each failure through ErrorWords as 3.17 has it.
- **Measured** (on the fixture's 46 lines of the list at 7ae0f56, which hold every AirPods Pro and HD 650 row 0.4
  names): "Sennheiser HD 650" finds 6 rows (the name, and "(2020)", "(balanced)", "(2020, worn earpads)",
  "(pre-2020, worn earpads)", "(pre-2020, semi-worn earpads)"); "AirPods Pro" 17, 16 of them with both words whole
  (Rtings' "Apple AirPods Pro2" isn't); "apple" 18 with a limit of 3. Five mutations of EQSuggestion each fail
  EQSuggestionTests: several offering the first (3 tests), the other-model check dropped, a part answer picked from,
  the server's run-together words (3), and 3.7's exactly-one rule as written (the HD 650's).
- **Departures, and why**:
  1. **One is one headphone, not one row.** 3.7's "exactly one row holds every word" offers its own example, the HD
     650, nothing: the real list has six HD 650 rows. Now one is offered when every row holding the words is that
     headphone - its name alone, or its name with a qualifier in parentheses (Fold.key drops a bracketed aside) - and
     exactly one is the name alone; or when one row holds them at all. A row with another word outside parentheses is
     another model, so "Apple AirPods Pro" (an output renamed with its maker) is still the choice, never the first
     generation. And only from a whole answer: when deadwax found more than the limit let through, a row not seen
     could be another model. James's to confirm (design question 1).
  2. **16 models, not 5**: 3.7 and 6's check 17 were written from the 40-line fixture's four Pro 2 rows; crinacle
     measured the Pro 2 fourteen ways (0.4). The words count what is there; docs/ios.md says "16" with "or however
     many AutoEq has". `models` says "1 model" - only a part answer with one row seen can make it.
  3. **Whole words, folded as the Library folds** (Fold.findText: marks off, `&` as "and"), so "aur audio" holds
     "AüR Audio Aure"; `EQOutputs.suggested` (slice 1's, hand rows) now asks the same `holdsEveryWord`, so there is
     one rule. deadwax's own search runs words together ("hd650" finds the HD 650); the suggestion doesn't - an
     output named "HD650" is offered nothing, and the picker still finds it.
  4. **The picker's AutoEq section leaves out the rows "Suggested for …" shows** (one list, not the same rows twice);
     Rtings' "Pro2" is under them. **The correction there is goes back** when tapped (3.7 says only that it can be
     "chosen back"): nothing in the picker takes it away but None, which goes back itself.
  5. **The picker opens searched from the suggestion's own answer**, kept by EQModel for the launch, so a choice
     never asks twice - and only while the suggestion shows (no correction, not Not now, online).
  6. **Once per launch counts answers, not tries**: a failed suggestion (offline, a 503, an older deadwax's 404) keeps
     nothing and is asked again the next time the page shows - and when deadwax comes back in reach (the page's
     `.task` is keyed on the output, reach and the correction) - never on a timer.
  7. **None leaves the switch alone.** 3.2's "any change turns it on" is for a change you'd want to hear; taking the
     correction away with the EQ Off turns nothing on. Using a profile turns it on, as 3.7 says.
  8. **The suggestion's query is the name iOS gives**, not yours from Rename ("Gym buds" would find nothing).
  9. **"10 filters, preamp -6.0 dB" is the file's own preamp** (`Preamp:`), the profile's fact; the curve above it
     plays deadwax's automatic one (within 0.5 dB, AutoEqProfileTests).
  10. **A 404 to the search is an older deadwax** (no AutoEq routes before 2.1.7): FastAPI's "Not Found" would have
     been said as ErrorWords' "It isn't there any more." - so the picker says "This deadwax is too old for AutoEq's
     corrections: they need deadwax 2.1.7 or later." (new words, design question 3). A 404 on either page has no Try
     again: asking again won't bring it back.
  11. **The curve crossfades when its frequencies change** (EQCurveView: `.id(drawing.frequencies)` on the plot), as
     slice 3's review asked: a correction chosen or taken away, and On/Off with one, crossfade over the same 0.25 s
     instead of morphing; presets with or without a correction still morph (the tone's f0s are on the grid).
  12. **"shown" is kept when the row is first drawn** (4's field), as `EQSettings.mark` - never over Not now, which is
     for good. Nothing reads "shown" yet; neither mark publishes a curve.
  13. **The Preamp is slice 5's**: 3.2 puts the Preamp section only in Advanced, so this slice adds no Preamp line.
  14. **The app's version stays 0.5 (5)**: one minor per feature (0.3 downloads, 0.4 lyrics), and 5's "the version
     moves at the EQ's merge" - slice 3 took 0.5 (5) for the EQ, and slices 1 and 2 didn't move it.
- **Design questions for James** (built as recommended; each a word to change):
  1. One headphone, not one row (departure 1) - or offer the HD 650's six as a choice too.
  2. The Pro 2's fourteen under one "pick yours" with the first generation and the other sources' Pro 2s (16 rows),
     or group them - the picker would need a level of its own.
  3. The older-deadwax sentence (departure 10), said to everyone - or ErrorWords' own for a listener and this for
     whoever runs deadwax.
- **Only the phone shows**: the Correction section in its place and the suggestion row (its symbol, the swipe's Not
  now and VoiceOver's action); the picker's search field always showing, its 0.3 s pause as you type, "Searching…",
  and the field opening searched; a profile's curve, the full-width button and its checkmark; Use popping back to the
  EQ page in one move on You's stack and in the sheet; the correction heard (E18); the crossfade when a correction
  comes or goes (E18 asks); AutoEq on GitHub opening Safari with the music playing; and whether the real list gives
  the AirPods Pro the 16 rows the fixture does.
- **Tests**: Core **871 in 116** (AutoEqTests 6, EQSuggestionTests 8, EQCorrectionChoiceTests 4 - all new), Audio 114
  in 9; pytest's iOS files, test_autoeq.py and test_source_bytes.py; the unsigned Release device build; check_project.py;
  the ios sims. Not verified: ios.yml's Xcode 26.6 Swift (every multi-statement closure's type is spelled out), a real
  deadwax or AutoEq, and anything on a phone.
- **Review** (2026-11-12, on 37e6ce1..24a83e9's three commits). Read against 2.2, 3.2-3.4, 3.7, 3.13, 3.14, 3.17, 4,
  5.4, 6's 17-21, the Design review and slice 3's review, the code before the account; the server's half (src/routes/
  eq.py, src/autoeq.py) read for what the phone is answered. Changed:
  - **The one row was offered even when it was another model.** Departure 1 says a word outside parentheses is
    another model, but held it only among several rows: a list with the Pro 2's "(ANC mode)" and no first generation
    offered it to "AirPods Pro", "Samsung Galaxy Buds 2 Pro" to "Galaxy Buds Pro", and AüR Audio's one model to an
    output named by the maker alone. The one row is offered now only when it is this headphone - its name, or its name
    after a maker's ("Apple AirPods Max" for "AirPods Max"), a qualifier in parentheses aside - else it is a choice
    ("1 model - pick yours"). `theOnlyRowIsOfferedOnlyWhenItIsThisHeadphone`; the AüR test asks by the model's name.
  - **A `+` was folded away**, by Fold (and by deadwax's search), so Apple's "Beats Studio Buds +" would have been
    offered the Beats Studio Buds. The suggestion reads a `+` as the word "plus" (`EQSuggestion.folded`), so "T2+"
    is the "T2 Plus" too. `aPlusIsAWordOfTheName`.
  - **An older deadwax's sentence was said to everyone** (departure 10; the coordinator's project rule, design
    question 3 settled): a listener reads ErrorWords' own words for what didn't work ("Something went wrong." and
    "If it keeps happening, tell whoever runs deadwax."), and whoever runs deadwax the version it needs, folded under
    "For whoever runs deadwax" - `AutoEqAsk.failure`, as Lyrics.failure does for the lyrics. It tells the two 404s
    apart by their words, not by route: FastAPI's bare "Not Found" (or none) is a deadwax with no AutoEq routes, on the
    picker and a profile's page alike; deadwax's own "AutoEq doesn't have that measurement any more." is the
    measurement gone, with no Try again. An older deadwax now has Try again beside it, as the lyrics do.
  - **The phone gave up before deadwax did**: the search may wait 15 s for deadwax's first fetch of AutoEq's list
    (src/autoeq.py FIRST_FETCH_SECONDS) and a profile 15 s for its file (PROFILE_DEADLINE_SECONDS), and both were
    asked with the transport's 8 s - "That took too long." where deadwax would have answered. `Routes.timeouts` gives
    them 20 s; test_ios_contract.py's `test_the_app_waits_for_autoeq_as_long_as_deadwax_does` holds them above the
    server's, ClientTests the requests.
  - **The curve's crossfade would have stacked two plots**: `.id` inside the VStack leaves the plot going and the plot
    coming both laid out for the 0.25 s, the row twice as tall; the plot is in a ZStack of its own now (not seen on a
    phone - E18 asks).
  - **Tests**: the correction kept in eq.json and read back the same after a relaunch, and one of an unknown kind or
    garbled refusing the file (4: set aside); mutations - the one row offered as before, offered only by an equal
    name, matched mid-word, the `+` dropped, the failure passed through or every 404 taken for an older deadwax, the
    timeouts as before, two rows each the name alone offered, a part answer picked from - each fails a test; and the
    contract's (a byte of answers.json, AutoEqAsk.longest at 101, a route's path) fail pytest.
    ios/scripts/autoeq_answers.py writes the same file twice running, byte for byte the committed one.
  - **Agreed, not changed**: the picker's latest-only (`.task(id:)` cancels the last ask, which draws nothing once
    cancelled; a query come back to is the answer there, not asked again), its bounds (50, 100 scalars, trimmed, an
    empty or blank field asking nothing), offline as ErrorWords' own; "Use for …" copying the profile's text and
    filters into the bound output's setting through `EQModel.output(key)`, crossfaded, the EQ turned on, back to the EQ
    page in one move on either stack (`EQSheetStack` read optionally, so You's stack never finds one); the contract
    (ROUTE_COUNT 26, the models held to `row_answer`, `profile_answer` and the search's literal); the credit; no
    newer-only API, `@Observable` and the optional `@Environment` both iOS 17's, and every multi-statement closure's
    type stated. Departures 2-9 and 11-14 sound as given; 7 is listed below for James.
  - **Left, for the server** (src/ not touched): deadwax's fold drops a `+`, so two models named apart only by one
    ("Beats Studio Buds" and "Beats Studio Buds +") would be one row, the other's measurement under "Other
    measurements" with nothing to say it's another model; and "&" and "and" are kept apart there.
  - **James's to decide** (design, not changed): one row of another model as "1 model - pick yours" rather than no
    row; None leaving the EQ Off (departure 7 - 3.2 says any change turns it on); Other measurements showing source and
    form only, so one source measuring a headphone on two rigs draws two rows alike.
  - **Tests**: Core **873 in 116** (`theOnlyRowIsOfferedOnlyWhenItIsThisHeadphone`, `aPlusIsAWordOfTheName`, and
    expects added to five more - the timeouts' renamed `theAlbumIndexAndAutoEqAreGivenLonger…`), Audio 114 in 9; pytest's iOS files, test_autoeq.py and test_source_bytes.py (210, 1
    skipped); the unsigned Release device build (Xcode 27.2); check_project.py; the ios sims and vocabulary. Not
    verified: ios.yml's Xcode 26.6 Swift, a real deadwax or AutoEq, and anything on a phone.

### 5.5 Slice 5 - Advanced

- **Files**: the Advanced parts of `EQScreen.swift` (3.8), `EQFilterEditor.swift`, the handles in `EQCurveView.swift`,
  `EQImport.swift` (the three ways in, the preview, 3.9), `EQExport.swift` (3.11); `Info.plist`'s document type and
  `check_project.py` requiring it; `.onOpenURL` in the root and `AppNavigation.eqImport`; docs/ios.md (Advanced, import,
  export, the syntax it reads and what it refuses, Headphone Accommodations).
- **Must not touch**: the engine; Core's reader and writer except for a bug found here (with its test first).
- **Verified**: Core (already); the device build; checks 22-30.

#### Slice 5, built (2026-11-12)

Built on `ios` from e797aa4 (slices 1-4 and main's 2.1.9 merged), in four commits: Core's rules (58e31be); the share
sheet's document type and its check; the App; these notes and the guide. Nothing drawn, touched or heard on a phone,
and no Simulator: every look, touch and sound is checks E22-E30's (docs/ios.md, 6's 22-30).

- **Files**: in Core, `EQAdvanced.swift` (EQFilterRow and EQAdvancedRules - the rows, 64 an ear, Add Filter's peak,
  the hand preamp's rounding; EQSettings' `addFilter`, `editFilter`, `setFilter`, `deleteFilter`, `backToAutoEq`,
  `setAutomaticPreamp`, `setHandPreamp`, `importCorrection`; EQHandle, EQHandleRules and EQHandleDrag; EQField and
  EQEditorRules; `EQDrawing.filter`) and `EQImportRules.swift` (the preview's lines, For's outputs, the text kept, a
  refused line found), and words (`Import.pasted`, `Import.what`, `Editor.slopeRange`; a paste's source and value).
  In ios/App: `EQ/EQFilterEditor.swift`, `EQ/EQImport.swift` (EQImportItem, EQImportReading, EQImportRows, the preview
  and its sheet), `EQ/EQExport.swift` (the menu and its Transferable file); the handles and the capsule in
  `EQCurveView.swift` (EQHandles, EQHandleCapsule, EQHandleLayer, EQHandleReach, and `height`); EQScreen's Advanced
  switch, filter rows (`EQFilterRowView`), Add Filter, the import and export rows, "Back to AutoEq's" and the Preamp
  section; EQModel's `advanced` and the eight operations; EQRoute's `.filter(EQFilterPage)` and EQSheet's preview;
  AppNavigation's import slot (`eqImport`, `eqImportPage`, `eqImportSheet`, `eqPreviewUp`, `share`, `importOnPage`,
  `importAnswered`); RootView's `.onOpenURL`; MainTabs' EQ sheet; Now Playing opening its own. Info.plist's document
  type and check_project.py's check of it. The project file is unchanged (the App folder is synchronised); no diff in
  DeadwaxAudio, APOReader, APOWriter or src/.
- **Measured** (EQImportRulesTests, on the fixture's AutoEq profiles): every profile, with the preamp automatic and by
  hand (-7.5 dB), exported and imported again plays the same - the response within 1e-9 dB at every grid point and the
  same preamp - the whole curve imported over a Flat tone, the correction alone under Bass Boost. "Use Q instead" gives
  the same coefficients at 48 kHz for a width in octaves, and at every rate for a shelf's slope (its S has no rate in
  it). Fourteen mutations of Core's new rules each fail a test (unsorted rows, Add Filter at 64, a drag snapping the
  axis not moved, a jump on engaging, the hand preamp to +30, Use Q's analog width, a peak left with no width by a type
  change, the last of your own filters kept, a slope of 0 taken, an edit not marked changed, a pinch not stretched to
  where it began, a touch taking any handle, the import's hand preamp in the preview and in the setting).
- **Departures, and why**:
  1. **The pinch keeps the width's own form.** 3.8 says "pinch for Q"; a filter written with a width in octaves stays
     one (to 0.01, up to 10), a shelf with a slope a slope (to 0.1 dB an octave, never too steep), so a filter is
     changed only in what you change - 3.8's own rule for the editor. A filter given no width starts from the Q it
     plays as. A pinch is taken anywhere on the plot (its second finger lands where it likes): the filter being dragged,
     else the nearest within 44 pt of the fingers' middle, else the selected one; a drag under it waits until its finger
     is up.
  2. **A drag moves only the axis the finger moved along**, so an imported 31.25 Hz isn't rounded to 31 by a drag up;
     its frequencies are the slider's 20 Hz-20 kHz, stretched to take in where the filter began; a corner shelf's Fc
     moves with its f0, so it keeps its corner; a shelf with a slope stops where the slope would be too steep.
  3. **Handles at f0, their own gain** - a corner shelf's at its centre, where its gain is half (3.8's own corner line
     says so), and not on the line drawn, which carries the preamp and the tone. A pass or a notch at 0 dB.
  4. **The capsule's room is kept** above the plot whether or not a handle is selected, so selecting one never moves
     the curve under the finger.
  5. **A filter row is a button and a switch, no chevron**: a NavigationLink round a Toggle takes the switch's tap.
     Its editor is pushed on the stack the page is on (the sheet's, or You's).
  6. **"Back to AutoEq's" is in the Correction row's context menu and the toolbar's •••**: a NavigationLink row has no
     menu of its own but a long press, which nobody finds unaided.
  7. **"Use Q instead" is a button row** under the field (3.8: "a menu item"): there is no menu there to hold it. The
     Q it gives is rounded to three significant figures (0.707, 4.32).
  8. **A field is applied when it is submitted or left**, and its line shows only once it was applied and refused
     (then until the text is in range) - not on every keystroke, where "-" on its way to "-3" would flash red.
  9. **Steps**: the gain 0.1 dB, a Q and a width in octaves x1.1 (at least 0.01 a step), a slope 1 dB an octave (3.8
     gives the Q's only); each from the value the filter plays, held to its range, the stepper's half disabled at an end.
  10. **The Type picker's carry-over**: the frequency kept; the gain when both types have one; a width in octaves dropped
     on a shelf (APO ignores it there) and a slope off one; written as the new type is by default (a shelf by its centre,
     `LSC`/`HSC`); and a peak or an all pass left with no width given Add Filter's Q 1, as it would play nothing.
  11. **A slope of 0 or less says "Above 0 dB an octave."** - 3.8 has no words for it (3.9's refusal says it must be
     above 0).
  12. **Your own filters, the last deleted, are None** - a correction of no filters is no correction; the switch is left
     as None leaves it (slice 4's departure 7). Delete Filter and the swipe ask nothing: one filter, its row there to
     add it back, as Apple's own list rows delete.
  13. **A paste has no name**: its correction reads "Pasted", "From the clipboard" under it; the preview "From the
     clipboard"; what an import replaces "from the clipboard".
  14. **For starts on the page's output** for an import from an EQ page (its own Files and Paste) - the page of
     Other outputs' AirPods is about the AirPods - and on the output now for a shared file. For lists the output now
     and then every output Other outputs lists.
  15. **A preamp set by hand taken from a file is held to -30...+12 dB**, the stepper's range (8, question 18); a
     file's own may be +30.
  16. **A shared file over a preview already up takes its place there**, never closing it first (3.9 says both; one
     import at a time is the rule that holds). Over any other sheet - Up Next, Info - Now Playing closes it and opens
     its EQ sheet once it has gone; over the tabs MainTabs opens an EQ sheet; the preview comes up 0.4 s after an EQ
     sheet it opens, as a sheet presented while another slides in isn't shown.
  17. **The correction picker (3.7) gets no import rows**: 3.8 puts Import from Files…, Paste and Export… in Advanced's
     Correction section, and the picker is AutoEq's.
  18. **The Automatic row shows the preamp that would play while the EQ is Off** (every control works while Off, 3.2),
     where the drawing - flat - has none.
  19. **"Back to AutoEq's" gives the filters their ids as they came**: an editor open on a filter of it lands on that
     filter as AutoEq wrote it.
- **Check 26 holds only over a Flat tone** (or for The Correction Alone): The Whole Curve writes the tone's ten
  filters into the file, so importing it on the output that plays that tone plays the tone twice. docs/ios.md says to
  set the tone to Flat first. And a converted GraphicEQ (up to 61 peaks, 3.10, the zeros dropped) with a tone's 10
  makes more than 64 to an ear: the export writes it, and deadwax's own import refuses it ("This file has 71 filters
  for one ear - deadwax plays up to 64.") - **still open, James's to answer**: raise the import's limit to 70 (the
  render's 80 less the tone's 10; slice 1's "Left for James", the brief's question 15 - eq.md section 8's own 15 is
  the Bluetooth UIDs), which reads back every export but one whose GraphicEQ kept all 61, or have the export say so
  first. The 64 stays as the spec has it, by decision.
- **Design questions for James** (built as recommended; each a word or a line to change):
  1. An edited file correction still reads "From HD650 ParametricEQ.txt" - only AutoEq's says "- changed" (3.2). Say
     "- changed" for a file too, or call it "Your own filters" once it is edited? Recommended: "- changed", as AutoEq's.
  2. Delete with no confirmation (departure 12) - or Undo-less deletes asked first. Recommended: as built.
  3. The pinch keeping the width's form (departure 1) - or every pinch making a Q, as 3.8 reads. Recommended: as built.
  4. The 64/70 limit above.
- **Only the phone shows**: the handles' feel - 22 pt reach, 4 pt engage, the pinch - and whether the pinch's
  full-plot gesture leaves a one-finger drag on the curve scrolling the page (it should: only the handles' circles take
  one finger); the capsule's place; the editor's fields with the phone's decimal comma and `.numbersAndPunctuation`;
  Paste without a prompt; "deadwax" in the share sheet, the Inbox copy gone after; the preview over the tabs, over Now
  Playing, over Up Next or Info, and replacing a preview up; a shared file arriving while an alert or the Files picker
  is up (nothing here makes room for them); Export's share sheet and the file in Files; and the sound of each (E22-E30).
- **Tests**: Core **907 in 118** (EQAdvancedTests 28, EQImportRulesTests 6 - both new), Audio 114 in 9; pytest's iOS
  files and test_source_bytes.py (137, 1 skipped; the new `test_an_eq_file_can_be_shared_to_deadwax_and_only_as_a_copy`);
  the unsigned Release device build (Xcode 27.2), its warnings read - only AppIntents' usual line; check_project.py; the
  ios sims but iosdeck, which fails on `ios` before this slice (2.1.8's theme.css token not re-exported into the deck's
  tokens.json, ios/scripts/export-deck-vectors.cjs, on the Node that made them). Not verified: ios.yml's Xcode 26.6
  Swift (every multi-statement closure's type is spelled out), and anything on a phone.
- **Review** (2026-11-12, on 58e31be..35f4161's four commits). Read against 5.5, 3.2-3.4, 3.8-3.11, 3.13-3.18, 0.3, 4,
  6's 22-30, the Design review and the earlier slices' reviews, the code before the account; the import read as
  untrusted input, with probes of 256 KB files of every shape and of absurd numbers. Changed:
  - **A run of spaces made the reader quadratic** (slice 1's, found here): `APOReader.search` tried each start, and
    from each space of a run walked to its end, so a line of n spaces with no "Gain" after them cost n squared - 20,000
    took 11 s, a 256 KB file of them hours, the import hung. A pattern beginning with whitespace that fails from a
    space fails from every later space of that run (each reaches the same end and the same rest, with less of it), so
    the search steps over the run; 256 KB of any shape tried now reads in at most a second, 8,000 GraphicEQ lines
    aside (8.5 s in a debug build, off the main thread). `aLongRunOfSpacesIsReadInOnePass`, failing first.
  - **A slope so gentle its S overflows played NaN** (slice 1's): `LSC 1e-310 dB` - 1/S past the largest Double -
    made b0 and a2 NaN in the bank. The reader refuses it as a slope, "Line 1: a slope of 1e-310 dB is too gentle to
    make a filter."; the editor's field "Too gentle to make a filter.". `aSlopeTooGentleToMakeAFilterIsRefused`,
    failing first; `aSlopeTooGentleIsRefusedByItsField`.
  - **A band pass's infinite gain stopped every save** (slice 1's): a band pass plays no gain, so its `Gain` went
    unchecked, and `Gain 1e999 dB` - wcstod's infinity - was kept; eq.json can't hold an infinity, and EQStore's
    `try? written()` then dropped every save until the correction was replaced. Refused now by the gain's own words;
    a finite one is kept as before. `anInfiniteGainIsRefusedOnABandPassToo`, failing first, also writing every
    fixture's reading to eq.json.
  - **An `LS` given a Q moved when exported**: a shelf read with no width plays by its centre, and its field, step or
    pinch gave it a Q still written `LS` - which APO, and deadwax's import, read by its corner (100 Hz played, 117 Hz
    read back). editFilter writes such a shelf `LSC`/`HSC`, by its centre as it plays; one read by its corner keeps
    `LS`. `aShelfGivenAWidthPlaysTheSameExported` (export, read again, the same f0 and coefficients).
  - **No edit is left that the reader would refuse** (`EQAdvancedRules.takes`, held by editFilter): Fc 1-22000 Hz, a
    peak's or shelf's gain within 30 dB (a band pass's, which plays none, kept as a file wrote it), a Q, a width or a
    slope in range, every number finite - so no NaN reaches the bank, the file or eq.json from a handle, a field or a
    step. `anEditNeverLeavesAFilterTheReaderWouldRefuse` (a file's band pass of 45 dB still switched off);
    `everyFilterAFileGivesCanBeEdited` (every fixture's and AutoEq profile's filter passes it).
  - **A drag made NaN of a corner shelf with no centre**: `HS Fc 1000 Hz Gain 30 dB Q 0.01` is centred at 0 Hz
    (`LS`: infinity), and a drag across divided by it. It is dragged from its Fc then. `aCornerWithNoCentreIsDraggedFromItsFc`.
  - **The one-axis drag held only for a finger moved exactly straight** (departure 2): any wobble sideways rounded
    31.25 Hz to 31. Each axis now engages on its own once the finger has gone 4 pt along it, and follows from there
    without a jump; 3 pt each way is still a tap. `aDragUpThatWobblesKeepsItsFrequency`.
  - **Opening a far-moved corner shelf's editor crashed**: its line turned f0 into an Int, which traps past Int.max -
    `LS 0.1 dB` at 30 dB is centred at 1e47 Hz, with Q 0.01 at infinity - and a file can say either. It is written as
    a number now ("centred at inf Hz"). `aCornerFarAwaySaysWhereWithoutTrapping` (traps on the old code).
  - **A file of no reported size was read whole** (`Data(contentsOf:)` when `fileSizeKey` is nil): read now through a
    FileHandle to one byte past 256 KB, its size from the end where iOS can say. And the preview's summary rows were
    identified by their text, which two ears converted alike share; by place now.
  - **Tests** for what the suite let through: an edit taking an ear past 64, Add Filter and a delete each marking
    AutoEq's "changed", a 0 dB filter not "left out", UTF-16 big-endian text, and the Advanced state - the switch,
    every width's form, a corner, an ear's own, one off, the counter, "changed" and the hand preamp - read back from
    eq.json the same. Seventeen mutations - each Core fix above undone (twelve ways, the reader's three among them,
    the guard's gain held for a band pass too), the 64 guard, either "changed", the left-out rule, the big-endian
    order - each fails a test (the corner line's Int by trapping). The two App fixes have no test of their own (the App has none).
  - **Agreed, not changed**: departures 1, 3-15, 17-19 sound as given; EQModel's operations write only the bound
    output's setting; the closures' types stated and nothing newer than iOS 17; VoiceOver's rows, handles and
    actions and Dynamic Type's stacking as 3.18 has them; the document type and check_project.py; `.onOpenURL`'s copy
    deleted from Documents/Inbox only, after a security-scoped read; the refused line for whoever runs deadwax alone.
  - **Left, noted**: the Python mirror (make-eq-fixtures.py) lacks the two reader refusals added here - no fixture
    reaches them, and the fixtures can't be made again without scipy, so it is for whoever next makes them; the 0.4 s
    before a preview over a fresh EQ sheet has no retry if a slow phone isn't ready; a shared file arriving over the
    Files picker or an alert (the builder's own note); typed text not submitted is dropped when the editor is left;
    EQStore's failed save says nothing (only this one cause of it is gone); an admin's refused line shown uncut, a
    256 KB line included; `LSC 1e-300 dB` (just short of the overflow) and a corner centred at 0 Hz play their
    degenerate sections as APO does; the row's "BW %.1f" rounds 0.04 octaves to 0.0; an Arabic decimal mark isn't
    read.
  - **James's to decide** (design, not changed): the words "a slope of … dB is too gentle to make a filter." and
    "Too gentle to make a filter.", and "centred at inf Hz" / "1e+47 Hz" for a corner moved past any frequency; an
    `LS` given a width written `LSC` (it stays where it plays) rather than made a corner (as APO would read `LS … Q`,
    the handle jumping); 4 pt an axis before it moves; a grouping mark read as a decimal ("1,000" is 1 Hz on a phone
    writing a point, "1.000" on one writing a comma); two ears' "Converted from a GraphicEQ curve…" lines naming no
    ear; and the four above, with check 26 over a Flat tone only.
  - **Tests**: Core **921 in 118** (EQAdvancedTests 39, APOReaderTests 21, EQImportRulesTests' text test grown),
    Audio 114 in 9; pytest's iOS files and test_source_bytes.py (137, 1 skipped); the unsigned Release device build
    (Xcode 27.2), only AppIntents' usual warning; check_project.py; the ios sims and vocabulary but iosdeck (as above).
    Not verified: ios.yml's Xcode 26.6 Swift, and anything on a phone - the per-axis drag's feel and the bounded read
    of a shared file among them.

### 5.6 With the turntable

The deck's few lines (1.9) go in with the turntable's slice 2, which lands after this; that slice uses `CAudioRing`
and the allocation hook made here, and its route counts move (0.5, item 7). The fader's slice 4 doesn't touch the EQ.

---

## 6. James's checks on his iPhone

Each: what to do, and what you should see or hear. AirPods unless it says. Answers through the usual question buttons.

**After slice 2** (You > Debug > EQ):

0a. Debug's EQ: "Unit: In the graph: passing every sample through". Play test sound 1, then turn on **Muffle what
    plays**: the beeps sound muffled at once, with no click; off, they're as before.
0b. Play songs 9 into 10 (one tone cut in two) and switch Muffle on and off ten times as it plays: no click, no drop, no
    break at the join.
0c. With Muffle off, play an album you know well: it sounds exactly as it did before this build.
0d. Pause from the lock screen, then press the AirPods' stem: the lock screen shows ▶ after the pause, and the press
    plays - Muffle on, then off.

**After slice 3:**

1. You > Playback: after Normalization, **EQ**, with "iPhone speaker" under it and "Off" at the right; its note below.
2. Open it on the speaker: "iPhone speaker", "Connected now", the EQ switch off, a flat curve in grey, "Off: nothing
   changes the sound."
3. Connect the AirPods and play: the page changes to "James's AirPods Pro" by itself (if your finger isn't on a
   slider). The speaker is now under **Other outputs**, Off.
4. Choose **Bass Boost** (Preset): the switch turns on, the sliders move, the curve shows the bass lifted, and the line
   says the preamp. You hear more bass - and everything a little quieter, which the volume buttons give back.
5. Drag the 125 slider up and down while a song plays: the sound follows your finger, smoothly, never clicking; a small
   tick under your thumb at 0. Double-tap it: back to 0. "Preset" now says "Custom".
6. **Save as Preset…**, call it "Mine": it's under "Your presets"; rename it, then delete it - the sliders stay.
7. Flip the EQ switch on and off while a song plays, a dozen times: a clean A/B, no click.
8. Take the AirPods out mid-song: it pauses, as before. Play: the speaker plays Off - flat. Put them back in and play:
   Bass Boost again from the first sound.
9. **Tune the presets**: try each of the nine on two albums you know. Tell me any that sound wrong, and which way
   (too much, too little, the wrong place) - the numbers move to what you settle.
10. Now Playing > •••: **EQ**, with "Bass Boost" under it; it opens the same page over Now Playing; Done closes it.
11. Info: Sound shows "EQ - Bass Boost on James's AirPods Pro, preamp -…"; turn the EQ off: the row goes.
12. With the EQ on, lock the phone and play a whole album: nothing different from off but the sound - no drop-outs,
    no silence; pause and play from the lock screen and the AirPods: ▶/⏸ right every time. Unlock and open Debug's EQ:
    the Render row's "refused blocks: 0" (iOS never asked for more than 4,096 frames at once, 1.2).
13. Play a hi-res album and a 44.1 kHz album back to back with the EQ on: no break between them; Debug's EQ "At this
    rate" says 48 kHz.
14. VoiceOver: the page reads the output, the switch, "The EQ's curve" with its summary (try the rotor's Play Audio
    Graph), the line, Correction, Preset, then "31 hertz, 0 decibels, adjustable" … - swipe up: "plus 1 decibel".
15. Debug's EQ, Output row: tell me the AirPods' UID; switch the phone off and on, and tell me again - and for the car,
    and a USB DAC if you have one.
16. The largest text size: the sliders are ten rows with steppers; everything else wraps.

**After slice 4:**

17. AirPods with no correction: the suggestion "AutoEq has corrections for AirPods Pro", "5 models - pick yours".
    Tap it: the picker, "AirPods Pro" searched, the first-generation row and the Pro 2's. Open the one for your
    generation (for the Pro 2, the listening level and ANC you use): "Measured by …", the curve, Other measurements -
    **Use for James's AirPods Pro**. Then take the AirPods out on that page before tapping: the button still says
    James's AirPods Pro, the line at the top says they aren't connected, and using it puts it on them, not the
    speaker.
18. Listen with the tone Flat, then flip the EQ off and on: the correction's difference (more neutral: often a little
    less bass bloom and more treble detail on AirPods). With Bass Boost on top: both, one curve.
19. Search "hd650", "hd 650" and "airpods": each finds what you'd expect. Search "zzz": "AutoEq has no headphones
    called "zzz"."
20. Airplane mode, then search: "Can't connect to deadwax." - and the correction still plays.
21. If you use Headphone Accommodations (Settings > Accessibility > Audio & Visual), turn it off with a correction on:
    the two stack otherwise.

**After slice 5:**

22. Turn **Advanced** on: the curve grows, with handles; the Correction section lists the filters by frequency; Preamp
    shows "Automatic". Debug's Render row: tell me both numbers.
23. Drag a handle sideways, up and down, and pinch it: the sound follows, its numbers show above the curve; its row
    changes too, and the Correction row says "- changed". "Back to AutoEq's" puts it back.
24. **Add Filter**: a peak at 1000 Hz; set it to +6 dB, Q 4: you hear it; switch its row off and on.
25. Turn Automatic off and set -2 dB with a big boost on: the amber line says it may clip.
26. Export **The Whole Curve** to Files; then **Import from Files…** that file: the preview shows the same curve and
    numbers; Import - nothing changes in the sound.
27. AirDrop a ParametricEQ.txt from your Mac (or save one from Safari) and share it to deadwax: the preview opens over
    whatever is showing, "For" set to the output now.
28. Import a GraphicEQ.txt from AutoEq: "Converted from a GraphicEQ curve: … filters, within … dB"; compare it by ear
    with the same headphone's ParametricEQ.txt.
29. Paste an Equalizer APO config with `Include:` in it: "Can't import this file" and its line.
30. VoiceOver on the filter rows: "Filter 3: peak at … hertz …", its switch, the Delete action.

---

## 7. What only a device can tell

- **The in-process unit on iOS**: that `registerSubclass` and `AVAudioUnitEffect` give the unit on the phone as on
  macOS, with no extension (check 0a).
- **The outputs' UIDs**: Bluetooth's across a restart and a re-pairing, AirPods' A2DP against LE, a USB DAC's (its
  model's or its own), AirPlay's, how CarPlay and a car's Bluetooth name themselves (check 15).
- **Whether every route change stops the engine** (so the start puts the curve in), or some switch while it runs (and
  the crossfade covers it) - the engine log shows which.
- **The crossfade by ear**: 20 ms on a big bass change on AirPods, where a low band's settling is slowest (checks 5, 7).
- **The cost on the phone**: Debug's Render row at 48 kHz, and at 96 or 192 kHz on a USB DAC (check 22) - and
  whether iOS runs the audio thread on an efficiency core with the screen locked, which only the worst-case number on
  a locked phone shows (1.10's 15% is an estimate).
- **The largest block iOS asks for**: 4,096 frames with the screen locked is the documented figure the unit is set to
  (1.2); a phone, a USB DAC at 192 kHz or AirPlay asking more would show as Debug's refused blocks (check 12) - and
  silence, which the fix (a larger `maximumFramesToRender`) would then follow.
- **Apple's USB-C to 3.5 mm adapter**: whether iOS reports it as `.headphones` or `.usbAudio` with its own UID - the
  key follows whichever (3.12), and Debug's Output row says which (check 15).
- **Overs in real music**: Debug's count after an album with Bass Boost - whether the automatic preamp is ever not
  enough.
- **The AirPods' own processing**: Adaptive EQ (Pro models), Spatialize Stereo and Headphone Accommodations all apply
  after the app; AutoEq's AirPods measurements include the AirPods' own EQ. Whether a correction sounds right with
  Spatialize Stereo on is an ear's question (check 18).
- **AirPlay's delay** for a change, and that the EQ applies there at all.
- **The haptic tick**, the audio graph's sound, Dynamic Type's stepper rows, Paste without a prompt, and the share
  sheet's "deadwax".
- **The ••• item's subtitle**: that iOS draws a menu item's second Text as its subtitle (iOS 17 and up, fairly sure; else the title alone).

---

## 8. Open questions

Each with what the build follows until James answers.

| # | question | option A | option B | recommended |
| --- | --- | --- | --- | --- |
| 1 | The C11 atomics both the EQ and the turntable need | one C target made by the EQ, `CAudioRing`, used by the turntable's slice 2 in place of its own `CDeckRing` | the turntable's name kept for a target the EQ builds | A - one target, a name for what it is; the turntable spec's `CDeckRing` read as this |
| 2 | The deck's EQ | after the voice's limiter: the voice untouched, the record's path ending as the song's | before it, as the plan said: the limiter has the last word | A - the port stays exact with the EQ on, and the handover compares like with like |
| 3 | The crossfade | 20 ms, raised cosine, one at a time, the newest waiting | longer (50 ms) for big changes and banks with low filters | A; B only if check 5 or 7 hears anything |
| 4 | The curve and the sliders | the curve drawn once, above, as what you hear | the curve also drawn behind the sliders (the plan) | A |
| 5 | The correction's filter list | in frequency order, no reordering | the file's own order, reordered by drag (the plan) | A - the order changes nothing in the sound |
| 6 | APO's filter forms beyond AutoEq's (LS/HS with a Q or a slope, `LS 6dB`, `LSC x dB`, Modal, the Q-less defaults) | played as APO's source plays them - read in the review (0.3, 1.3), every form pinned | refused until pinned (the first draft) | A - **settled by the review**: nothing is a guess now, so nothing APO plays is refused but `IIR` |
| 7 | GraphicEQ's conversion | 61 fixed 1/6-octave peaks (Q 4.32), gains by Gauss-Newton with λ 1e-4, no shelves - predictable, measured within 0.5 dB to 16 kHz, its fit shown | a greedy parametric fit as AutoEq's (fewer filters, path-dependent); or a low and a high shelf added (0.1 dB better above 16 kHz, condition 227 against 15.6) | A |
| 8 | Info while Off | no EQ row (the plan) | "EQ - Off" | A - Off changes nothing, and Info's rows say what's changed |
| 9 | A change while Off | turns the EQ on | does nothing audible until you switch it on | A - Apple Music's way; a change you can't hear is a trap |
| 10 | The automatic preamp for a curve that only cuts | 0 - it never boosts | a boost, so the curve's top is always exactly 0 dB | A - a boost past the curve's edges could clip where the grid didn't look |
| 11 | The graphic's Q | 1.41, so what's written is what's played - and AutoEq's FixedBandEQ's own (read) | √2 exactly | A |
| 12 | The menu item's name | "EQ" | "EQ…" (the plan) | A - Apple's ellipsis is for an action needing more input |
| 13 | The sliders at the accessibility sizes | ten stepper rows | two rows of five | A |
| 14 | The import's frequency range | 1-22000 Hz on every output | up to each output's own half-rate | A - a file is never refused for one output and taken for another |
| 15 | Bluetooth UIDs | as iOS gives them, until the phone shows (check 15) | suffixes stripped, so A2DP and LE are one | A, then B if check 15 shows the same AirPods under two |
| 16 | `Device:` lines | one leading line skipped; several refused | all skipped (the plan) | A - skipping several plays two devices' filters at once |
| 17 | Commands APO doesn't know | skipped, with a note (APO ignores them too) | refused | A |
| 18 | The hand-set preamp's range | -30 to +12 dB, with the clip warning | -30 to 0 dB | A - as APO allows, and the warning says when it matters |
| 19 | Where the EQ is kept | on this phone, per output | per person, on the server | A - outputs are the phone's, and the web has no EQ |
| 20 | Which outputs get the AutoEq suggestion | Bluetooth and USB with no correction | every output | A - AutoEq measures headphones; the speaker and the car would only ever be offered nothing |
| 21 | AutoEq's list | read at one commit, refreshed weekly | `master` each time | A - the list and its files always agree |
| 22 | Off, if the bit-exact measurement fails | out of the graph at the next stop, On while playing restarting the output (1.7) | - (James decided A of the plan's question 3, and this B only on failure) | built only if 1.7's test 1 or 2 fails |
| 23 | What a slider means | each band's own gain, the curve their sum (one band at +12 dB adds 2.5 dB an octave away; the curve above shows it) | bands compensated so the curve passes through each slider's value | A - what an export writes is what the sliders say, as every graphic EQ |
| 24 | The bands' frequencies | exactly 1000 · 2^k (31.25, 62.5 … 16000), labelled with ISO's names | the ISO nominals (31.5, 63 …) or AutoEq's FixedBandEQ (31, 62 …) | A - exact octaves, one number pinned; the others differ by under 1/50 octave |
| 25 | APO's case, `Hz` and `dB` | as APO: `preamp:` and `Fc 100` (no Hz) play nothing there, so they're skipped here, with a note naming what tripped | read in any case, units optional (the first draft) | A - a file plays as it does in APO; the note says the one thing a person can't see |
| 26 | A UTF-16 file (Notepad's "Unicode") | read, with a note that APO doesn't read it | refused, as APO plays nothing from it | A - the file's intent is plain, and the note keeps it honest |
| 27 | The suggestion when several AutoEq rows match (AirPods Pro: the first generation and four Pro 2s) | "pick yours": the picker, searched for the name | the first row offered | A - iOS names both generations "AirPods Pro", so the first row is a guess |
| 28 | Denormals | none flushed: Double's range takes a decay minutes to reach them, held by 1.7's silence test, a per-sample offset only if it fails | a flush per block (the first draft) | A - a per-block flush made the output depend on where blocks fall, which the block test forbids |
| 29 | GitHub's user agent | `deadwax/<version>`, no contact | the MusicBrainz agent, with MUSICBRAINZ_EMAIL's address | A - GitHub needs an agent, not an address; nothing about the person goes where it isn't needed |
| 30 | A route change while an EQ page is pushed | the pushed page stays bound to its output, the EQ page switches when shown again | every page follows the route | A - "Use for James's AirPods Pro" must do what it says |
| 31 | A new AutoEq list and the profiles kept | every kept profile dropped, fetched again at the new commit when asked | profiles kept at their older commit | A - a profile is always its list's commit's (2.1); the phone keeps its own copy, so nothing playing changes |

---

## Design review (2026-11-12)

Read as a designer and a DSP and audio engineer who reads the code, not the citations: Equalizer APO's source (the
SourceForge SVN's GitHub mirror, 53d885f7f1), AutoEq at master 7ae0f56 (peq.py, constants.py, INDEX.md, two result
folders), the engine and app at `ios` (PlaybackEngine, AudioSessionController, PlaybackSection, NowPlayingMenu, Info,
ErrorWords, YouLines, the Palette) and main 2.1.6 (config.py, wikipedia_endpoint.py, test_ios_contract.py). Every
number below marked measured was computed in the review (numpy, the cookbook in Double) and is reproduced by the
fixture script in slice 1.

**Changed** (one line each, and why):

- 0.3: APO's source read and its rules set down - the wiki gives no defaults, no corner rule, and nothing of case,
  units, commas, thousands or how it rounds.
- 0.4: AutoEq's data read at its commit - crinacle has no CSV, the CSV's curve is the unrounded filters', FixedBandEQ
  is Q 1.41, INDEX.md encodes only spaces, the Pro 2 has rows of its own; the results are MIT (the draft: "not stated").
- 0.5 item 1: the CSV demoted to a 0.15 dB cross-check, peq.py the tight reference - the CSV is 0.11 dB off the file.
- 0.5 item 2, 1.3: every form APO plays is played (Modal, the defaults, S from a slope or a Q, the corner's move);
  only `IIR` refused - the draft refused forms APO plays only because it hadn't read the code.
- 0.5 items 10-11: APO's strictness, and its Float32 rounding between filters - so "plays as APO" is claimed to the
  precision it holds (about -140 dB).
- "AutoEQ" -> "AutoEq" throughout - the project's own spelling.
- 1.2: `matchOutput` remakes both connections whenever the mixer's or the unit's rate isn't the hardware's - a
  configuration change keeps old formats, and the draft compared the mixer's alone.
- 1.2: `maximumFramesToRender` set to 4,096, a larger block refused and counted - AUAudioUnit's default is 512 and a
  locked screen asks 4,096.
- 1.2: allocation on every start (`engine.stop()` releases), marking the state fresh - the draft assumed one.
- 1.2: the render block captures a header made in `init` - AUAudioUnit caches the block before any buffer exists.
- 1.2: `tailTime` 0 argued; `shouldBypassEffect` and `bypass` never set - the identity bank is the bypass, measured.
- 1.3: `EQFilter` keeps its width as written and whether it is a corner, so every rate recomputes as APO does; one
  table of every type, its needs and defaults; BW ignored on shelves; which width wins; a too-steep shelf refused.
- 1.3: precision stated - 1 Hz at 384 kHz holds in Double, and would be wrong by a factor of hundreds in Float32.
- 1.4: the preamp's top refined by golden-section search - the grid and the f0s alone missed by up to 0.073 dB
  (measured), enough to round the preamp 0.1 dB short.
- 1.5: Direct Form I in Double named against TDF2 (scipy's `lfilter`), its scratch in Double.
- 1.5: no denormal flush - the draft's per-block 1e-30 flush made the output depend on where blocks fall, failing its
  own block-size test; a test of silence instead, with a per-sample offset only if it fails.
- 1.5: no global, static or class property touched in the render (lazy initialisation and exclusivity checks take
  locks); one concrete entry across the module boundary; a 4,096-frame warm-up.
- 1.6: the output-key rule - the draft's "newer, or the same output" let a slider's bank for the old route land last.
- 1.6: a bank taken is copied into the render's memory - with three slots, the bank faded from was the producers' to
  overwrite.
- 1.6: the first block after an allocation installs the newest bank, with no crossfade; a crossfade starts at a
  block's start; one at a time, the newest waiting.
- 1.6: warm start by stable id, a new section from its own input's history - the draft matched by place in the list
  (an added filter shifts every later one) and fed every section the bank's input.
- 1.6: the crossfade's worth measured (-58 to -129 dBFS at 1 kHz); the plan's "-80 dB of an ideal crossfade" dropped,
  as nothing meets it at 31 Hz, where the filter's own 29 ms settle is what you hear.
- 1.7 test 2: noise and a sweep synthesised in the test through `flacFile` - no fixture audio to commit.
- 1.7 test 3: the click defined (a fixed 2 or 8 kHz 8th-order high-pass, 200 ms), bounds from the measurement, and
  the same change in one step must fail - a high-pass at 8x the tone had measured the crossfade's own skirt.
- 1.7 test 6: eight rates to 384 kHz, the impulse run until it decays below -120 dB.
- 1.7 tests 9 and 10: no cost in silence; 4,096-frame blocks rendered and 4,097 refused.
- 1.8: the start sets the output key and publishes through the ring; the engine's queue never writes the render state.
- 1.9: the deck installs at its first block, keyed the same; the turntable's real-time review rule covers CAudioRing
  and Core; no deck on AirPlay.
- 1.10: cost re-estimated as latency-bound (7-8 cycles a section a sample), a drag as back-to-back crossfades, 384 kHz
  and efficiency cores counted; bounded at 10% at 192 kHz on the runner.
- 2.1: the list's path decoded once, each segment encoded whole - the list encodes only spaces, so passing it on
  sent `&` and `+` raw and turned `%20` into `%2520`.
- 2.3: GitHub is sent `deadwax/<version>`, no contact - the MusicBrainz agent carries the operator's address.
- 2.3: a new list drops every kept profile, and an unchanged commit fetches nothing - the draft kept profiles at an
  older commit than their list, and fetched 851 KB a week for nothing.
- 2.5: tests for the encoding (`Bruel & Kjaer 5128`, `(51dB + ANC)`), the agent, the drop and the unchanged commit.
- 3.1, 3.13: You's footer ends with Normalization's own "This is kept on this phone."
- 3.1: the EQ sheet joins the lyrics' `covered` flag - the lyrics (app 0.4) landed after the draft, and their clock
  would have run on behind it.
- 0.2, 0.5 item 7, 2.5, 5, 5.4: route counts and the app's version re-based on the lyrics (`ROUTE_COUNT` 24, app
  0.4) - written as "two more" and "the next minor", so the next slice to land doesn't stale them again.
- 3.2: only the EQ page follows the route, and only on top; pushed pages stay bound to their output - "Use for
  James's AirPods Pro" could have put the correction on the speaker.
- 3.5: the bands at exactly 1000 · 2^k with ISO's names, and what a slider means (the curve is their sum, measured).
- 3.6: "the sliders show exactly what it does" corrected; each preset's top and preamp measured (Bass Boost: +6.0 dB,
  -6.1 dB).
- 3.7: one match is offered, several are "pick yours" - the first row was the first-generation AirPods Pro, offered
  to a Pro 2's owner, as iOS names both alike.
- 3.8: the editor shows a slope and a default width, says when a shelf is read by its corner, and refuses a too-steep
  one - each imported form can be seen and edited as it plays.
- 3.9: a share-sheet import with a sheet already up.
- 3.9: reading from APO's source - case, `Hz` and `dB` required, commas, thousands, `wcstod`, no comment syntax, LF
  and CRLF, GraphicEQ sorted; UTF-16 read, with a note.
- 3.9: no longer refused - Modal, the shelf forms, commas, an unsorted GraphicEQ; unknown types and incomplete filters
  skipped with a note, as APO leaves them out; newly refused - CR-only lines, too-steep shelves, a GraphicEQ with no
  pairs or a frequency at 0; a width of 0 is the default.
- 3.10: the fit's damping 1e-4 (the draft's 0.01 missed its own bound), its numbers measured, the preview split at 16
  kHz, and "what is lost is phase" corrected - APO's GraphicEQ is minimum-phase too, so what differs is level, above
  16 kHz.
- 3.11: `Fc 31.25 Hz`; never a comma; the thousands trap avoided with a trailing zero.
- 3.12, 7: the USB-C adapter's port type left to the phone.
- 3.17: the advice beside a page's own "Try again" is `ErrorWords`' retry form - the draft quoted the one without.
- 4: filters kept as written, with a stable id from the correction's counter; `.band` and `.filter` ids never collide.
- 5.1: the source-reading step is done; fixtures at eight rates from 1 Hz; the script's own DF1 the bit-exact
  reference (lfilter a cross-check); coefficients to 1e-13 absolute, not relative; an independent Python reader of
  APO's rules; the presets and close pairs; GraphicEQ bounds tightened to what a mutation fails; libm's ulps allowed
  across platforms; the flush test gone; eight new mutations.
- 5.2: ten engine tests. 5.3: `EQScreenRules` holds the pushed page's binding. 5.4: Core's `EQSuggestion`.
- 6: check 12 reads the refused blocks; check 17 is "pick yours", and a pushed page kept on its output.
- 7: efficiency cores, the largest block, the adapter.
- 8: question 6 settled by the source; 7 and 11 brought up to date; 23-31 added.

**Looked at and kept** (and why):

- The filters in Direct Form I, in Double: its state is the signal's own history, so it survives a coefficient
  change and the warm start; Double is what makes 1 Hz at 384 kHz exact enough.
- The 20 ms raised-cosine, equal-gain crossfade: measured to take a mid or high band's click below -129 dBFS; a
  longer one buys nothing at 31 Hz, whose settle is the filter's (question 3).
- An in-process AUAudioUnit between the main mixer and the output: one place every lane passes, no extension, and
  testable offline on the runner; AVAudioUnitEQ and a render-notify set aside for 1.2's reasons.
- Off as the identity bank, in the graph (James's decision), proved by test 2, the fallback built only if it fails.
- The triple buffer's atomics in one C target, no floating point in C.
- The automatic preamp: never a boost, rounded toward quieter, one for both ears; and no limiter, ever.
- Q 1.41 for the bands - AutoEq's FixedBandEQ writes the same.
- ±12 dB in 0.5 dB steps; ten stepper rows at the accessibility sizes; "EQ" without an ellipsis.
- The server's design: one commit for the list and its files, the phone never talking to GitHub, a "user" route as
  describe's, well inside GitHub's 60 requests an hour.
- Storage per phone, per output, in one file written atomically and set aside, never guessed at, when unreadable.
- `Device:` (one leading line skipped, several refused): APO's source confirms skipping both would play both.
- 1-22000 Hz on every output; 64 filters an ear; the filter list in frequency order, without dragging.
- 61 fixed peaks for a GraphicEQ, no shelves: adding them takes the condition from 15.6 to 227 for 0.1 dB above 16
  kHz.
- The search's folding, one row per headphone, and SOURCE_ORDER.
- Bluetooth UIDs as iOS gives them until check 15 (question 15).
- No Simulator anywhere: Core on Linux, the engine offline on the macOS runner, the screens in James's hand.
