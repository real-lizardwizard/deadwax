# The native iPhone app (ios/)

James's request of 2026-10-23: "let's get started on the iOS app". The plan (written the same day,
kept outside the repo) and James's answers to it set what follows; this file is the project's memory
of it. The user guide is docs/ios.md.

Built on the `ios` branch. **Phase 0 merged into main as deadwax 2.1.0 (2026-11-10)**, James: "go ahead
and merge those to 2.1 on main"; the next phases are built on `ios` again.

## James's decisions (binding)

- A **native SwiftUI app**, not the web app in a shell. **A free Apple account** only: each install
  runs 7 days, at most 3 of the team's apps on the phone, no push, iCloud, TestFlight or extensions.
- Built with **Xcode 27.1** on his MacBook Air M2 (8 GB) with **no iOS Simulator** (the Mac can't run
  one); tested on his **iPhone on iOS 27.0**, over plain http on his LAN and WireGuard.
- Audio fidelity first; normalization and gapless matter; offline downloads with settings, and
  auto-download of his library. **Two download settings he must be able to change in the app**
  (Settings > Downloads, from Phase 2): *Download over* Wi-Fi only (default) / Wi-Fi and cellular
  (`allowsCellularAccess`), and *Storage limit* (5 / 10 / 20 default / 50 / 100 GB / No limit; the
  streaming cache apart), each shown with what's used now.
- Bundle id **`net.lizardlounge.deadwax`** (James chose it 2026-10-23, in place of the plan's first
  `io.github.real-lizardwizard.deadwax`). Never change it once installed: a new id is a new, empty app.
- The app talks **only to deadwax**, never to Navidrome.
- Phases: **0** toolchain and audio proven on the phone; **1** the player; **2** downloads; **3**
  auto-download; **4** playlists, artists, songs; **5** Search; **6** Get and Requests; **7** managing
  as links into the web app. The turntable, speed fader and visualizer stay in the web app.

## Phase 0 - "Hello, iPhone" (app 0.1, build 1; the server unchanged at 2.0.0)

One screen: the address and **Check** (`/deadwax/health`, `/deadwax/me`: logins on or off, and who),
**Sign in** when logins are on, **Test sounds** (the beep album, "Start test" by "deadwax test", ten
songs, found through `/navidrome/search`; streamed, or downloaded and played from the copy), a
**Hi-res** row (the best FLAC above 48 kHz, preferring 24/192, paging every song up to 10,000), what's
playing with its readout ("24-bit 192 kHz FLAC file -> 48 kHz output (AirPods)"), the lock screen and
remote controls, and the install's expiry from the app's own `embedded.mobileprovision`.

### The layout

```
ios/
  Deadwax.xcodeproj/        committed: objectVersion 77, ONE app target, ONE synchronized folder (App/),
                            one local package reference (DeadwaxKit), configs based on Config/*.xcconfig;
                            a shared scheme (xcodebuild -scheme Deadwax needs it) and the workspace file
  Config/                   Base.xcconfig (bundle id, MARKETING_VERSION 0.2, CURRENT_PROJECT_VERSION 2 - 0.1 (1) until Phase 1,
                            iOS 17.0, Swift 5 mode, signing Automatic, `#include? "Local.xcconfig"`),
                            Debug/Release.xcconfig (each includes Base), Local.xcconfig.example (the team
                            id; Local.xcconfig and `device` are gitignored), Info.plist (a plain file)
  App/                      the SwiftUI app (Phase 0's AppModel and ContentView became these in 0.2 - see
                            "Phase 1: the app (0.2)"): DeadwaxApp (and Palette), Models/ (ServerModel,
                            PlayerModel and its +Engine/+Resume, LoudnessBook, PlayReporter, LibraryModel,
                            AlbumIndexStore, AlbumModel, DebugModel), Root/ (the gates, MainTabs), Shared/
                            (Routes, CoverImage, ErrorNote, Notice), Library/, Album/, Player/, UpNext/,
                            Info/, You/ (the Settings tab since 16 Nov, its root and pages; DebugView is
                            Phase 0's test screen), EQ/ (app 0.5: EQModel,
                            EQStore, EQRouteReader, and the screens - EQScreen, EQCurveView (and slice 5's
                            handles), EQSliders, EQPresetsScreen, EQOutputViews, EQNameAlert, EQRoute;
                            slice 4's EQCorrectionScreen and EQProfileScreen; slice 5's EQFilterEditor,
                            EQImport, EQExport); URLSessionTransport,
                            SessionKeychain, AudioSessionController, NowPlayingController, SongFiles (stream
                            cache, downloads); Icon/ loose PNGs; Fonts/ Noto Sans's four faces and OFL.txt
  DeadwaxKit/               Package.swift (tools 6.0; iOS 17, macOS 14)
    Sources/DeadwaxCore/    pure Swift + Foundation, Swift 6 mode, tested on Linux
    Sources/DeadwaxAudio/   the engine; every file inside #if canImport(AVFAudio); Swift 5 mode - and the EQ's
                            unit between the mixer and the output (EQUnit, EQHost: eq.md 1.2, 1.6; slice 2)
    Sources/CAudioRing/     C11 stdatomic only: the EQ's triple buffer and its counters (indices and bits, no
                            floating point, nothing Apple's - built on Linux too)
    Tests/DeadwaxCoreTests/ Swift Testing, 64 tests in Phase 0, 508 in 69 suites at app 0.2, 633 in 83 at 0.3,
                            745 in 98 with the EQ's slice 1 (its fixtures in Fixtures/eq/, 1.5 MB), 809 in
                            110 at its slice 2 (the turntable's slice 1 between), 849 in 113 at its slice 3
                            (853 after its review), 873 in 116 at its slice 4, 907 in 118 at its slice 5
    Tests/DeadwaxAudioTests/  offline-render tests, macOS only (12 in Phase 0, 54 at app 0.2, 93 at 0.3, 111 in 8
                            suites with the EQ's slice 2 and its review - EQRealTimeTests bounded in a release build;
                            114 in 9 at its slice 3, EQStartTests the start's bank made ahead)
    Tests/CAllocHook/       test-only C: malloc_logger counting one thread's allocations, proved by a canary
                            (turntable.md 4.3, built first for the EQ)
  scripts/                  install.sh (James's), install_helper.py (its JSON/plist reading, in Xcode's
                            python3), check-linux.sh, check_project.py, make-icon.py, make-test-album.py,
                            make-eq-fixtures.py (the EQ's fixtures; numpy and scipy, run with python -I),
                            make-fonts.py (App/Fonts from the web's Noto Sans; fontTools and brotli)
  README.md                 a pointer to docs/ios.md and this file
.github/workflows/ios.yml   branches '**' + paths: ios/** and itself (never a tag: GitHub applies no paths
                            filter to a tag push) - linux (swift:6.4.1-noble), project (check_project.py),
                            macos (swift test with the engine's renders, the EQ's render in release, then the
                            UNSIGNED device build)
tests/test_ios_contract.py  the routes, fields and bounds the app relies on, against the server (8 tests)
tests/test_ios_install.py   install_helper.py, check_project.py, install.sh against stand-ins, and the
                            test album, on Linux (18 tests)
tests/test_ios_eq_fixtures.py  make-eq-fixtures.py run into a temporary folder against what is committed:
                            byte for byte on the machine made.json names, within a float's last bits
                            elsewhere (10 tests; skipped without scipy, which tests.yml installs pinned)
```

`ios` is in .dockerignore: the image never carries the app.

### DeadwaxCore (tested on Linux)

- **HTTP without URLRequest**: `HTTPRequest`/`HTTPResponse`/`HTTPTransport`, because URLRequest is in
  FoundationNetworking on Linux. The app's URLSessionTransport converts. A transport throws only when
  nothing answered; every status is an answer.
- **`Routes`**: every route the app calls as one `Endpoint(method:path:query:)` line - the form
  tests/test_ios_contract.py reads. Query names not declared on the endpoint are never sent
  (`DeadwaxClient.url`), mirroring the server's own "declared, every one" rule.
- **`DeadwaxClient`**: health (a 503 is still read - the poller stopped), me (a 401 is `.signedOut`),
  signIn (sent with NO cookie; a wrong password is `.refused(401, words)`, not a sign-out), signOut
  (200 or 401 both fine), search, and the stream and cover requests. Errors carry deadwax's own
  `detail` (string, or FastAPI's list of `msg`).
- **`SessionCookie`**: the `deadwax_session` value out of Set-Cookie (URLSession joins several with
  commas; a name merely ending the same isn't it; an empty value is a sign-out's clearing). Kept in the
  Keychain (`AfterFirstUnlockThisDeviceOnly`), sent as `Cookie:`; URLSessions have cookies off. The
  password is never stored. The same-origin guard lets the app's POSTs through: they carry no Origin.
- **`ServerAddress`**: what's typed -> `http://host[:port]`; no scheme means http; a pasted
  `/player/` link is the same server; refusals in words. An IPv6 literal (`[::1]:8090`) works:
  `DeadwaxClient.url` builds on the base's own URLComponents, because `URL.host` drops the brackets
  and a host set without them makes no URL (found in review: every route then went to `/`). `parse`
  refuses an address no route's URL can be built on.
- **Words, not dumps**: an HTML answer where deadwax's health should be says something else answered
  at the address (check the port); a 503 page says the status; a JSON answer missing a field names
  the field (`DeadwaxClient.what`), never DecodingError's text.
- **`CheckReport`**, **`TestSounds.pick`**, **`HiRes.best`**, **`InstallExpiry`** /
  **`ProvisioningProfile.parse`** (the XML plist out of the CMS envelope; dates in en_US_POSIX,
  "Fri 30 Oct, 14:02", the phone's zone), **`PlayQueue`** (previous restarts past 3 s, as
  `RESTART_AFTER_SECONDS`; the first song only restarts), **`StreamFormat`** (`raw` unless iOS can't
  decode it: ogg, oga, opus, wma -> `mp3`), **`RateWords`**, **`LocalFiles`** (safe names, length
  against Navidrome's `size`), **`FLACStreamInfo`** (STREAMINFO, an ID3v2 tag skipped; Phase 2 checks
  MD5 with it).
- **`StartPoint`**: where a song starts - an exact frame at the rate it was counted at, or seconds when
  the song's rate isn't known yet. The source turns it into a frame at the file's own rate
  (`frame(at:)`), and the engine computes the entry's offset with the same function at the decoded
  rate, so they agree. A seek is always seconds (so a seek before the song is heard - paused after a
  skip, or loading - lands where it says at 192 kHz too; it used to assume 44.1 kHz); going on from
  where a song was is the exact frame, never a round trip through seconds.
- **`LaneTimeline`**: the engine's arithmetic, pure: where each song sits on one player node's sample
  count, so `playerTime` -> (song, frame). A sample at an entry's end belongs to the next song.

### DeadwaxAudio (compiled and tested only on macOS)

The plan's section 3, as Phase 0 needs it:

- **Sources** decode to Float32 non-interleaved **at the file's own rate and channels** (16/24-bit
  int -> float is exact). `FileSource` is AVAudioFile (seek = `framePosition`, sample-exact).
  `StreamSource` is AudioFileStream (packets) + AudioConverter (PCM) over a `ByteSource` read at its own
  offset, so a seek before the bytes arrive is a new reader that decodes and drops the frames before
  it. FLAC needs a **flush** at the end (`AudioFileStreamParseBytes(stream, 0, nil, [])` - its last
  packet ends at the next sync word, which never comes; AudioStreaming does the same). The input proc
  returns `'more'` when bytes haven't arrived (the converter hands back what it decoded) and `'brkn'`
  when the fetch failed. Mono and stereo only in Phase 0.
- **`StreamFetch`**: one URLSession (cookies off) writing the song into the stream cache file, read by
  any number of sources; complete -> later opens are FileSources.
- **`PlaybackEngine`**: AVAudioEngine, one AVAudioPlayerNode per **lane** (a file format: rate x
  channels), its node connected to the main mixer at the output's rate (see "The rate conversion").
  About 2 s scheduled ahead in 0.5 s buffers, refilled from each buffer's `.dataRendered` completion
  (see "First run on macOS"). **The next song in the same format is scheduled straight after the last
  buffer on the same node** (sample-exact; nothing trimmed or crossfaded). Another format goes on its
  own lane, started with `play(at:)` the SAMPLE time the first lane's last sample plays (a host time until
  fix/engine-hold, which overlapped the two by 5-15 ms - see "Starts at a sample time"). A song that would begin on a lane still holding songs that play before the
  one scheduled last (44.1 kHz, a short 96 kHz song, 44.1 kHz again) waits, its first buffer parked,
  until that lane has run out - see "After review, again". **The output starts once and keeps running while something plays**; a song
  started from silence on an output just started is scheduled `startLead` ahead (AVAudioSession's
  outputLatency + ioBufferDuration) - on one already running, not (since fix/engine-hold: "The hold on the
  callbacks");
  a pause (or the queue's end, a stop, a failure) stops the engine at once - iOS counts a running output
  as playing, see "The pause the lock screen didn't see" (it was 60 s until then) - and the next play
  rebuilds from the frame left. A lane that runs dry mid-song
  (a stream behind) is stopped and restarted from the frame it reached. Configuration changes (a new
  route or hardware format) reconnect the lanes and go on from the frame reached; a media-services
  reset makes a new engine. **No gain** (Phase 0 is "Off": nothing multiplies).
- **When iOS stops the engine itself** (a call, a new route, media services reset) it does so before
  the app hears of it, and a stopped engine's `lastRenderTime` - so `playerTime` - is nil. So each lane
  keeps `lastSample`, the node's sample count whenever it was last read playing (every buffer's
  completion and the app's 0.5 s ticker read it), and `heard()` falls back to it: play goes on from
  where the song was, to within half a second, not from its start or the last seek (review finding;
  it used to restart the song). A pause with the engine already stopped resets the lanes and marks it
  asleep, so play rebuilds from there.
- **A configuration change waits `changeSettleSeconds` (0.3 s) before playing on**, and a pause in that
  time wins: AirPods taken out post the engine's change on AVAudioEngine's queue and the session's
  `.oldDeviceUnavailable` on the main queue, in no set order, and the song must not go on out of the
  speaker before the pause lands.
- **Nothing plays a node on a stopped engine**: `startLanesIfReady` returns unless `engine.isRunning`
  (a node's play on a stopped engine is an Objective-C exception that ends the app, reachable from a
  retry or a completion between iOS stopping the engine and its notification). Not adopted: the
  reviewer's report that iOS 27's SDK deprecates `play(at:)` for a throwing `playAudio(at:)` - not
  verifiable here; a deprecation is a warning (nothing treats warnings as errors), and ios.yml's
  macOS job will show it.
- **Play after a failure or a stop**: a failure keeps where the song was (`held`), so play opens it
  again from there; with nothing to go on from (after stop, as at sign-out) play stays idle and lets
  the output stop - it used to sit at Loading for good with the output running.
- **The rate conversion is each lane's own AVAudioConverter** (since the first macOS run; it was the
  main mixer's, which failed - see "First run on macOS"): when a file's rate isn't the output's (48 kHz
  on the speaker and AirPods: a 44.1 kHz CD, a 96/192 kHz file) the lane converts with the
  **mastering** algorithm at quality **`.max`**, primed `.normal` (output frame 0 is input frame 0,
  nothing ahead of the song), one converter per lane kept across its songs so a join within a format
  stays continuous, and its node is connected at the output's rate, so the mixer converts nothing.
  When the rates agree there is no converter at all. The input is handed over as the converter asks
  for it; what its filter still holds is **flushed** (end of stream, then reset) when the lane's last
  song for now has been decoded - at the end of the queue, when the next song is known to be in
  another format, when another lane's first buffer is decoded, or when the lane's buffers run out with
  it still holding. A lane's end, for the next lane's start, is the node's exact frame count once
  flushed. Positions stay in the songs' own frames (the node's count at the rates' ratio). A lane that
  runs dry mid-song keeps its converter, so the song goes on unbroken. (What it holds is not "under a
  millisecond", as this said: 576 song frames at 44.1 kHz and 1152 at 96 kHz, 12-13 ms, which the position
  read ahead until fix/engine-hold counted them - see "The hold on the callbacks".) A configuration change makes the lanes again, since the
  output's rate may be another. `theRateConversionMeasured` renders 1 kHz (192/96/44.1 kHz -> 48 kHz)
  and a 30 kHz tone (aliasing) and prints the numbers (bounds 60 dB and -40 dB catch only a broken
  conversion): see "First run on macOS" for them. (The words used to say iOS converted "after the
  app"; corrected in review.) `conform` copies a
  buffer into the lane's own AVAudioFormat object when only the channel layout differs - a player node
  throws on any other format.
- The **app** owns AVAudioSession (`.playback`, `.default`, `.longFormAudio`, active at the first play),
  interruptions (pause; resume on `.shouldResume` if it was playing), route changes
  (`.oldDeviceUnavailable` pauses), MPNowPlayingInfoCenter and MPRemoteCommandCenter (play, pause,
  toggle, next, previous, the lock screen's scrubber; skip/seek/repeat/shuffle disabled).
- The closures the engine calls on its own queue are made in `nonisolated static` functions
  (`AppModel.tracks`, `lead`) so they belong to no actor.

### The project without Xcode

- **Written by hand once**, with fixed ids `DA00…01`-`DA00…19`. Settings live in the xcconfigs; the
  .pbxproj changes only when a target, folder or package does. A new Swift file in App/ needs no
  project change (a synchronized folder compiles what's in it); PNGs there are copied to the bundle's
  root (the icons).
- **No asset catalog, storyboard, xib or entitlements** anywhere under ios/ (actool and ibtool need a
  Simulator runtime - the plan's R2). `UILaunchScreen` is an empty dictionary; colours are in code
  (`Palette`); the icon is `CFBundleIconFiles: [AppIcon60x60]` with @2x/@3x opaque RGB PNGs drawn by
  make-icon.py from theme.css's colours.
- **Info.plist**: `NSAllowsArbitraryLoads` ALONE (beside NSAllowsLocalNetworking, or ...ForMedia /
  ...InWebContent, iOS ignores it - from Apple's docs as remembered, unverified on iOS 27, check 3),
  `NSLocalNetworkUsageDescription`, `UIBackgroundModes: [audio]`, portrait, dark.
- **Simulator runtimes on CI**: GitHub's macOS runners come with them, and ios.yml prints them and leaves them
  alone. Until 2026-11-12 it deleted them before the device build, so that a tool needing one would fail there as
  on James's Mac. But `simctl runtime delete all` returns before the deletion is done (the list after it still
  shows every runtime), and a deletion finishing a few seconds later, while the build resolved its destination,
  failed it with "iOS 26.5 is not installed" - a runner glitch only in appearance. R2 was settled on James's Mac
  instead: Phase 0's check 1 (2026-11-10) built and installed with no Simulator runtime at any point, and
  check_project.py refuses the asset catalogs, storyboards and xibs that would need one.
- **check_project.py** parses the .pbxproj (an old-style plist; its own small parser), checks every
  referenced id exists, one app target and no extension, the synchronized folder and package paths,
  the linked products against Package.swift, the configs' xcconfigs, no committed team, the scheme's
  target, the xcconfig values, Info.plist's keys and the icons' sizes, and no catalogs. Run by
  check-linux.sh, ios.yml and tests/test_ios_install.py.

### install.sh (James's Mac)

bash 3.2-safe (macOS's /bin/bash). DEVELOPER_DIR defaults to /Applications/Xcode.app; refuses Xcode
< 16. **The team**: with no Local.xcconfig it reads Xcode's defaults (`IDEProvisioningTeamByIdentifier`,
or the older `IDEProvisioningTeams`) for the teams, a free Personal Team first, asks, writes the
file - and **stops there** (exit 0), saying the next step is the first install from Xcode: a free team
has no iPhone registered before it, so a build could only fail on signing. **Before the pull**, a
changed `ios/Deadwax.xcodeproj` (a team picked in Xcode's Signing & Capabilities, written into the
committed project) stops it with `git checkout ios/Deadwax.xcodeproj` to run, rather than git's
fast-forward error. `git pull --ff-only` (or `--no-pull`); asks GitHub's API (no sign-in, the repo is public) for
ios.yml's run on the commit, and asks before building a failed or running one; `xcodebuild ... Release
-destination generic/platform=iOS -derivedDataPath ~/Library/Caches/deadwax-build
-allowProvisioningUpdates -allowProvisioningDeviceRegistration build`; reads the built app's profile
(`security cms -D`) for its expiry; `xcrun devicectl list devices --json-output` for the paired
iPhones (iPads and unpaired left out; the saved one, `ios/Config/device`, first); `devicectl device
install app` (over the old app: its data stays) and `process launch`. A paired phone whose
`connectionProperties.tunnelState` is `unavailable` (no cable, not on the network) isn't found, so the
message is to connect it rather than devicectl's failure and advice about trust. JSON and plists are read by
install_helper.py in **Xcode's own python3** (`xcrun --find python3`), so nothing is installed.
tests/test_ios_install.py runs it against stand-ins for xcodebuild, xcrun, defaults, plutil and curl
(the first run saving the team and stopping; a changed project file named before the pull). Also
exercised on Linux with stubbed xcodebuild/xcrun/defaults/plutil/security/curl (first run writing the
team and choosing the phone, a saved phone, CI failed and declined, a failed build) - the real tools'
output shapes (devicectl's JSON, Xcode's defaults) are from memory and unverified until James runs it.

### The test album

"Start test" (2026) by "deadwax test", the ten songs checks 4, 5 and 6 play, is made by
`ios/scripts/make-test-album.py <music folder>` - standard library only, so the Mac's `xcrun python3`
(or the server's python3) runs it with nothing installed. Same signals as the album made for the web
player's start-of-song work (work/startskip's make.py: beeps at -12 dBFS, track 7's 20 s of exact
zeros, track 8's -80 dBFS TPDF noise), written by a small FLAC encoder of its own: fixed 4096-frame
blocks, CONSTANT subframes for silence and VERBATIM for the rest, the frame CRCs and STREAMINFO's MD5
(about 6 MB). Songs 9 and 10 (added in review) are one steady 440 Hz tone cut in two, the cut a
quarter-period past a whole number of cycles so it falls near a peak: the beeps meet in digital
silence, where a gap or a misplaced sample can't be heard, and the tone makes either a plain click
(check 5). The test checks the join's samples are the very next ones of the one tone. Checked against `flac -t` (CRCs and MD5) and ffmpeg once; tests/test_ios_install.py reads
it back with libsndfile and mutagen (rates, tags, the beeps' times, the zeros, the MD5). Its samples
are within 1 LSB of make.py's (libsndfile's float scaling); the noise differs (another generator).

### What was compiled where (Phase 0, 2026-10-23)

- **Linux (tokay-gecko)**: swift.org's **Swift 6.4.1 for Debian 13** (`swift-6.4.1-RELEASE-debian13`,
  the tarball's signature checked against swift.org's all-keys.asc: "Swift 6.x Release Signing Key"),
  unpacked into `~/.local/swift` with no sudo. `swift test` builds DeadwaxCore and its 64 tests (all
  pass); DeadwaxAudio and its tests compile to nothing. Swift 6.4.1 is what Xcode 27.0 ships
  (swift.org's release list); 27.1's is assumed the same or close.
- **Not compiled here**: everything in App/ (SwiftUI, UIKit, MediaPlayer, Security) and DeadwaxAudio
  (AVFAudio, AudioToolbox). Their first compile is ios.yml's macOS job after the push - read failures
  with `gh run view --log-failed`. The engine's 12 offline-render tests run there too.

### First run on macOS (ios.yml, 2026-10-24)

The engine's tests and the app's device build had never run before the push. What the first runs
found, each fixed:

- **A failed `==` on two arrays killed the test process** (no message, exit 1, the remaining tests
  never run): Swift Testing diffs two collections to report the failure, quadratic in time and
  memory, and the short-song test compared runs of 18,000 samples. Every sample comparison goes
  through `firstDifference()` now (the first sample that parts, and both values), and the short-song
  test prints its output's energy per 2048 frames and the engine's trace, so a failure shows where
  each song landed. ios.yml prints macOS's crash reports when the tests fail, and builds the app
  whether or not a test failed (one run shows both).
- **The main mixer's conversion from 192 kHz aliased**: a 30 kHz tone came out at **-21.8 dB** (96 kHz
  -64.7 dB; 1 kHz 154.9 / 148.0 / 100.9 dB clean from 192 / 96 / 44.1 kHz). With each lane's own
  converter (above): 30 kHz at **-160.4 dB** from 192 kHz and **-167.5 dB** from 96 kHz; 1 kHz **153.5 /
  151.9 / 146.6 dB** clean from 192 / 96 / 44.1 kHz.
- **A lane's start given in another rate's samples**: offline, the next lane's start is a sample time
  at the render's rate, and a node running at its file's 96 kHz took it as its own - the 96 kHz song
  began at frame 10129, not 22050, over the first. With every node at the output's rate a node's
  sample time is the render's (on the phone starts are host times, which this never touched).
- **`.dataPlayedBack` came late** - offline, the third song started at the start of a render (45056),
  not 44100: it is scheduled from the first lane's last completion, and that can only have come after
  the half second the song between lasted (inferred from where it began; the trace came after the fix).
  Completions are **`.dataRendered`** now: the render has taken the buffer, which is what the
  bookkeeping needs (the lane fed, the next lane started in time, a lane known to be done); nothing
  is stopped before it is rendered. The trace shows each completion in the render that took it.
- The join test: **largest difference 0.0 in the first 4096 frames** on both channels (no start ramp,
  offline). The device build: Xcode 26.6 (17F113) on macOS 26.6.2, Swift 6.3.3, the iphoneos26.5 SDK;
  the icons copied to the app's root (`AppIcon60x60@2x.png`, `@3x.png`, by copypng), no `Assets.car`.
  The runner's Simulator runtimes could not be deleted (`simctl runtime delete all` left all of them),
  so the build ran with them present - no stand-in for check 1 on James's Mac.

### Gotchas found building it

- **Swift Testing**: `#expect(optionalInt64 == 44_100 * 60 + 100)` reported false with both sides
  printed as 2646100 - the literal arithmetic was typed apart from the optional's Int64. Give the
  expected value a type (`let expected: Int64 = ...`).
- **`NSLock.lock()` is unavailable from async contexts** in Swift 6 mode: use `withLock { }`.
- **Offline rendering has no clock**: a lane switch can't be timed from `lastRenderTime`'s host time
  before the render runs, so the engine remembers each lane's start on the render's sample count
  (`manualRenderingSampleTime`). (Since "Starts at a sample time" every lane's start is remembered so, live
  too, as `Lane.origin`: the sample time it was started at.)
- **AVAudioPlayerNode takes only buffers in its connection's exact format**: decoders that agree on
  rate and channels can still differ in layout - `conform` copies.

### Unverified until the phone (the eight checks, docs/ios.md)

1. install.sh with no Simulator runtime; time and disk. 2. The loose-PNG icon on iOS 27. 3. ATS by IP and
by name, the Local Network prompt, WireGuard. 4. The start on AirPods and the speaker, cold, warm and
after a 2-minute pause (AVAudioPlayerNode's start ramp, R3 - the offline test prints the first 4096
frames' largest difference). 5. The join of songs 9 and 10 (one tone), no gap or click. 6. Locked:
songs 7-10 opening one after another, the hi-res song to its end, and play after 2 minutes paused (the
engine asleep) from the lock screen; its controls and the AirPods' (background audio on a free account,
R4). Phase 0 has nothing that plays for ten minutes, as the plan's check had it. 7. A call or Siri, an AirPod out. 8. The
24/192 readout.

### Left for later phases

Normalization (gain in the engine, Phase 1, with the one new server route for album loudness - on main as
deadwax 2.1.1: notes/player-normalization.md "The iPhone app's loudness route (2.1.1)"),
Up Next and resume (ported from lib/upNext.ts and lib/resume.ts with cross-language traces), plays,
the library screens, the background download session and its settings (Phase 2, with James's two),
the streaming cache's own limit (Phase 0 empties it at each launch), the start-on-zeros workaround if
check 4 hears a ramp, and AirPlay's route picker.

### After review (Phase 0)

- **The bundle id** became `net.lizardlounge.deadwax`, James's choice in the plan's answers (the first
  build had the plan's earlier `io.github.real-lizardwizard.deadwax`), set in Base.xcconfig and pinned
  by check_project.py, ios.yml and tests/test_ios_install.py.
- **The engine**: the position kept when iOS stops it, a configuration change that waits for a pause,
  no node played on a stopped engine, play after a failure or a stop, seeks before a song is heard,
  and the rate conversion said to be the mixer's and measured (see "DeadwaxAudio").
- **The client**: IPv6 addresses, and words instead of decoding dumps (see "DeadwaxCore"). HiRes's
  "176.4 kHz and up" tier was dropped: ranked by rate after the 24/192 test, it never changed an
  answer (a mutation removing it passed every test, and could only).
- **install.sh**: stops after saving the team; names a team Xcode wrote into the project before the
  pull; leaves out phones it can't reach. docs/ios.md: the branch to clone (`ios`), the team only in
  Local.xcconfig, the test album's script. ios/README.md points at both.
- **ios.yml**: `branches: ['**']` (tags no longer run it), one icon test a line (bash -e doesn't stop
  inside an `&&` list - reproduced), and the runner's Simulator runtimes deleted before the device build.
- **The contract test** also checks the sign-in's own answer (and that its cookie's value, read by
  SessionCookie's rule, is a session the server takes back) and the numbers the app sends against the
  server's bounds (search's page sizes and offset, the lock screen's cover size, `CoverSize.lockScreen`).

### After review, again (Phase 0)

- **A short song in another format between two of the first** (44.1 kHz, a 1 s 96 kHz or mono
  interlude, 44.1 kHz): while the middle lane hadn't started, its "ahead" read as all of it, so the
  whole interlude was decoded at once, the third song opened in the same pass, and went straight on
  the first lane - after the first song, ahead of the interlude, whose start was then timed from the
  first lane's end, third song included: the interlude played over the third. Now `schedule` refuses a
  song that would begin on a lane still holding songs when the lane scheduled last (`tail`) is another
  and isn't empty; the buffer is parked on the feed, and the first lane's last completion (which
  clears it) pumps again, so the third goes on it timed from the interlude's end. Phase 0's queues are
  one format each, so its checks never reached it; Phase 1's albums would. Offline test
  `aShortSongInAnotherFormatPlaysBetweenNotOver` (44.1 / 0.5 s at 96 / 44.1, rendered a piece at a time
  so completions land between): by tracing, without the fix the third song sits at 0.5-1.0 s and the
  interlude at 1.0-1.5 s, so its checks fail. It hasn't run: macOS only. A song shorter than the
  completion's own latency could still start a few ms late (a gap, never an overlap).
- **The test album's songs 9 and 10**, a tone across the join, so check 5 can hear one (see "The test
  album"); **check 6** rewritten for what Phase 0 can play (songs 7-10 locked, the hi-res song to its
  end, play after 2 minutes paused).
- Checked: the engine and its 12 tests type-check against the stand-ins again; the album's test
  (tests/test_ios_install.py) fails with song 10 a sample late, and with the cut on a zero crossing;
  `flac -t` passes on all ten. Python's count is unchanged (3657: the album's test grew, no new one).

### Verified (Phase 0, before the push)

- Python 3657 collected (3655 passed, 2 skipped; 26 more than 2.0.0's 3631: tests/test_ios_contract.py 8,
  tests/test_ios_install.py 18); pyflakes clean; tsc clean; all 62 sims; `npm run build`. The server, the
  interface and the engine files have no diff.
- Swift on Linux: 64 Core tests pass (`ios/scripts/check-linux.sh`, which also runs check_project.py and
  parses the scripts). Every Apple-only file parses (`swiftc -parse`), and DeadwaxAudio, its tests and the
  app's non-view files were type-checked against small type-only stand-ins for AVFAudio, AudioToolbox,
  MediaPlayer, UIKit and Security written from memory of Apple's signatures (kept out of the repo) - which
  caught EngineState's missing public init. ContentView and DeadwaxApp (SwiftUI) were not type-checked.
  After review the same was done again: DeadwaxAudio, its tests (then 11) and the app's non-view files
  type-check against the stand-ins.
- Mutation checks (each broken, its test seen failing, restored byte for byte): the timeline's join
  frame, previous's 3 s, the cookie's name boundary, opus as undecodable, undeclared query names dropped,
  a sign-in sending no cookie, the hi-res 48 kHz floor, STREAMINFO's bits, the expiry warning, a 401 as
  signed out; in Python, a renamed route, an undeclared query parameter, a renamed sign-in field, a new
  required answer field, the cookie name, NSAllowsLocalNetworking beside NSAllowsArbitraryLoads, no
  background audio, a dangling .pbxproj id, an extension target, another bundle id, an asset catalog,
  unpaired iPhones let through, and the free team not first. After review: in Swift, IPv6's URL built the
  old way, health's words, the 24/192 rank and the bits' rank, StartPoint's seconds at 44.1 kHz and its
  frame through seconds; in Python, an unreachable phone let through, install.sh building after saving
  the team, its project-file check, the album's CRC-16 and its sample count, Hi-res's page size and the
  cover's size past the server's bounds, and the sign-in's answer without `admin`.
- install.sh run end to end on Linux against stubbed Apple tools (see "install.sh").
- NOT run anywhere yet (at the push): the engine's 12 offline-render tests and the app's device build.
  They have since, on ios.yml's macOS job - see "First run on macOS". Everything on the phone is still
  to run.

## Phase 0 on James's iPhone (2026-11-10)

docs/ios.md's eight checks, run on the phone. **The Mac**: MacBook Air M2 (8 GB), macOS 27.2, **Xcode 27.1
(27A9275)**, no Simulator runtime at any point (`xcrun simctl runtime list`: 0 disk images, before and after).
**The phone**: "Green Anole", an iPhone 17 Pro on **iOS 27.2 (24B119)** - updated since the 27.0 the plan
names. Built from `1d9b295`, ios.yml green on it. The repo was cloned to `~/Desktop/Code/deadwax`, not
`~/Developer/deadwax`, with iCloud's Desktop & Documents sync **on**: install.sh printed its note, and nothing
failed on a file that wasn't on the Mac. (Moved to `~/Code/deadwax`, off iCloud, on 2026-11-13 - see
notes/tooling.md.) The Once steps were begun on 2026-10-27 (Xcode's first launch, the
Apple ID, the team) and finished on 2026-11-10 (the first Run from Xcode, then the checks).

1. **Install without a Simulator - pass.** `install.sh` on its own (Xcode not needed) pulled, found ios.yml had
   passed, built Release into an empty `~/Library/Caches/deadwax-build`, installed over the app Xcode's Run
   had put there, and opened it: **24 s** in all. Its words: `Installed deadwax 0.1 (1), runs until Tue 17
   Nov, 15:30`, and `Space: 34Gi free of 228Gi before, 36Gi free of 228Gi now` (the rise is the Mac's, not the
   build's). `** BUILD SUCCEEDED **` with no Swift warning (one line from appintentsmetadataprocessor:
   metadata skipped, no AppIntents.framework); the app is 1.2 MB, `AppIcon60x60@2x.png` and `@3x.png` at its
   root, no `Assets.car`, signed Apple Development for `net.lizardlounge.deadwax`. The first install before
   it was Xcode's Run with the cable (Once step 5), not timed. Disk over the whole setup: 57 GB free on
   2026-10-27 before Xcode's first launch, 34 GB on 2026-11-10; Xcode holds 7.3 GB of that
   (`~/Library/Developer/Xcode/iOS DeviceSupport` 6.8 GB - the phone's debug symbols from its first
   connection - and DerivedData 0.3 GB), the rest isn't Xcode's.
2. **The icon - pass.** The record shows on the home screen: the loose PNGs through `CFBundleIconFiles`, no
   asset catalog, work on iOS 27.2.
3. **The connection - pass on home Wi-Fi; WireGuard not done yet.** Check said OK by IP and by name, logins
   on, and James signed in. The Local Network question came once, and he allowed it. So
   `NSAllowsArbitraryLoads` alone lets plain http through on iOS 27.2, by IP and by name. Test sounds listed
   all ten songs once Navidrome had scanned the album, and Hi-res found a 24/192 FLAC. **Away from home over
   WireGuard: not done yet.**
4. **AirPods, from silence - pass.** All three beeps, the first as loud as the other two, every time: song 1
   from cold, song 3 tapped while 1 played, song 2 after 2 minutes paused - on AirPods and on the speaker,
   Streamed and Downloaded (Download all 10). No start lost even on song 1 (its first beep at 0.0 s), so
   AVAudioPlayerNode's start ramp (R3) isn't heard, and "Left for later phases"' start-on-zeros workaround
   isn't needed.
5. **The join - pass.** Song 9 into song 10 is one unbroken tone, no gap, click or blip: AirPods and the
   speaker, Streamed and Downloaded.
6. **Locked - FAIL on one point: play after a pause, from the AirPods; fixed the same day.** The rest passed: songs 7, 8, 9 and
   10 played one after another locked; the hi-res song played locked to its end; paused from the lock
   screen, 2 minutes, played from the lock screen, it carried on from where it was (the engine asleep and
   rebuilt from the frame left); the lock screen showed each song. Background audio works on a free account
   (R4). **But a press of an AirPod's stem paused, and a second press never played again** - every time,
   locked and unlocked, after a few seconds paused and after more than a minute. Nothing else (another app,
   Siri) answered the press. **After any pause - the AirPods', or the app's own button - the lock screen
   still shows Pause**: iOS still counts deadwax as playing. So the second press is sent as a pause, which
   does nothing to a paused engine (`pauseNow`'s `guard wantsPlay`); on the lock screen, tapping its Pause
   first (which only flips its button) and then Play resumes it. Check 6's lock-screen pause and play passed
   only because there the pause was the lock screen's own tap. **Diagnosed with a logging build and fixed the
   same day** - a pause stops the output at once - and James re-checked it on the phone: see "The pause the
   lock screen didn't see" below.
7. **Interruptions - pass for Siri and an AirPod out; a phone call not done yet.** Siri paused it and it came
   back afterwards; taking an AirPod out paused it. **A phone call: not done yet.**
8. **Hi-res - pass.** The 24/192 song played, and the line under Playing read, word for word: `24-bit 192 kHz
   FLAC file → 48 kHz output (AirPods Pro)`.

Still open from Phase 0: **check 3 over WireGuard** and **check 7 with a phone call**.

### What went wrong on the way

- **install.sh found no team at first**: "Xcode knows no Apple ID yet", with the Apple ID already added in
  Xcode > Settings > Accounts and a Personal Team showing. Xcode 27.1's defaults held only
  `DVTDeveloperAccountManagerAppleIDLists`, and there was no signing certificate. Once James made one
  (Accounts > the Personal Team > Manage Certificates… > + > Apple Development),
  `IDEProvisioningTeamByIdentifier` was there in the shape install_helper.py reads (`teamID`, `teamName`,
  `isFreeProvisioningTeam`, `teamType` "Personal Team"), and install.sh wrote Local.xcconfig and stopped as
  designed. Whether opening the team or making the certificate wrote the key wasn't told apart. Not changed
  here: docs/ios.md's step 3, or install.sh's message, could say to make the certificate.
- `security find-identity -v -p codesigning` listed the new identity as matching but **0 valid**, while
  `security verify-cert -p codeSign` passed on its certificate (issued by WWDR G3). Signing worked anyway,
  in Xcode's Run and in install.sh's build: noted only.
- **Xcode's first Run re-sorted `ios/Config/Info.plist`**: `CFBundleIcons` moved up into alphabetical order,
  nothing else (the two files' content compared equal through plutil). Restored with `git checkout
  ios/Config/Info.plist`. install.sh checks only `ios/Deadwax.xcodeproj` before its pull, so this would stop
  only a pull that brings an Info.plist change, with git's own "would be overwritten". Left open with the
  project, Xcode did it again later, when files in App/ changed under it: close the project in Xcode once the
  first Run is done (install.sh doesn't need Xcode open). The project file was never changed: the team only
  in Local.xcconfig, Signing & Capabilities never touched.
- **make-test-album.py refuses a folder that doesn't exist** ("There's no folder ..."), where docs/ios.md says
  to make the album "in an empty folder": `mkdir` it first. It then made the ten songs (5.8 MB) in 2.7 s with
  Xcode's python3 3.9.6, into `~/Desktop/Code/deadwax-test-album`, which James copied into his library.
- xcode-select points at the Command Line Tools on this Mac and was left so: install.sh's own
  `DEVELOPER_DIR` found Xcode, as designed. Xcode's first launch installed its own components (James's
  password, in Xcode); nothing else was installed, and nothing ran with sudo.

### The pause the lock screen didn't see (fixed 2026-11-10)

Check 6's failure above: after any pause the lock screen kept Pause, and the AirPods' next press did nothing.

**Found with a logging build** (never committed; its patch was kept out of the repo): every remote command,
pause, play and engine phase printed to stdout, read on the Mac with `xcrun devicectl device process launch
--console --device <phone> net.lizardlounge.deadwax` - no Xcode, no sudo; `--console` bridges the app's
stdout, and `fflush` after each line keeps it prompt. A temporary "Pause test" picker chose how a pause
stopped the audio. James pressed the AirPods in each; the log and the lock screen said:

| pause mode | the lock screen after an AirPods pause | the next press arrived as | result |
| --- | --- | --- | --- |
| Today: the nodes paused, the output on for 60 s | ⏸ | `pause` (the app at rate 0 already) | nothing |
| Stop: the output stopped at once, the session left active | ▶ | `play`, 1.3 s later | on from the very frame (80.8 s), sounding 0.27 s after the press |
| Stop + session deactivated | ▶ | `play`, 3 min later | on from 9.0 s, cleanly; the deactivation itself raised no error |

So **iOS 27.2 goes by the app's running output, not by `MPNowPlayingInfoPropertyPlaybackRate`** - the app
did set rate 0 at every pause - and a stopped output is enough; the session can stay active. The same was
reported on Apple's forums for AVAudioEngine apps (developer.apple.com/forums/thread/773870: pausing only
the player node left the pause icon, and `playbackState` "does nothing on iOS"). The earlier "after more than
a minute failed too" isn't explained by this; not seen again once the output stopped at once.

**The fix**: `PlaybackEngine.Settings.idleStopSeconds` 60 -> **0**, so a pause - and the queue's end, a stop,
a failure, a skip or seek while paused, which arm the same stop - stops the output at once, through the
path a pause longer than a minute always took (`held` = the exact frame, `reset`, `engine.stop()`, asleep;
play rebuilds from `held`). Already proved on the phone before the fix: check 4's song 2 after 2 minutes
paused and check 6's play after 2 minutes are that path. The cost: play after a pause sounds 0.2-0.4 s after
the tap (the output starting again), against about 15 ms with the output left running. A skip or seek while
paused records the new song's start before stopping (`begin` sets `held`, and `reset` clears the lane
`heard()` would read), so play goes to the new song.

- **Tests** (on James's Mac, `swift test --package-path ios/DeadwaxKit` with Xcode 27.1's toolchain, the
  build in `~/Library/Caches`): 64 Core and 13 engine tests pass. New: `aPauseStopsTheOutputAndPlayGoesOnFromWhereItWas`
  (the output off after a pause, on again with play, the song sample-exact from the frame left) - with 60 s
  put back it fails on `!engine.outputRunning`. `renderOffline` (tests only) now renders silence for a
  stopped output, as the phone plays nothing then: `aShortSongInAnotherFormatPlaysBetweenNotOver` renders on
  past the queue's end, and the stopped engine's render threw `-80802` (AVAudioEngine's "not running").
- **On the phone** (James, the fixed build): AirPods pause, locked and unlocked - the lock screen shows ▶ and
  the next press plays on from where it was; the app's own pause - ▶; song 10 run to its end - ▶, and a
  press plays it again; song 1 tapped after a pause - all three beeps, the first as loud.
- docs/ios.md says how a pause works now (it said the output stopped after a minute, to save battery).

## Phase 1: the Core (app 0.2)

Phase 1 is the player. Its Core - everything in DeadwaxKit that isn't a screen - was built first, as six slices
in parallel, each in a worktree of its own: the server's loudness route, Up Next and resume (one slice, p1/queue),
the Library's rules (p1/library), Normalization, plays and Info's words (p1/levels), the engine (p1/engine), and
the API layer (p1/api). Each was built from a spec read off the web app and the server at 2.1.0, reviewed
adversarially (every finding checked against the code and the source it ports, mutations included) and fixed.
The server's slice is on main as **deadwax 2.1.1** (the route) and **2.1.2** (the review's tests), merged into
`ios` (40bd97e) before the rest; notes/player-normalization.md "The iPhone app's loudness route (2.1.1)" has it.
The five Swift slices were merged into one branch, `p1/merge` from 40bd97e: p1/api, p1/engine, p1/library and
p1/levels with no conflict, then p1/queue (`--no-ff`, none either) - see "The merge" below.

**Not built yet: the screens** (built since, as app 0.2 - see "Phase 1: the app (0.2)" at the end; what follows
was true of the Core alone) (the specs' screens.md: the tab bar, sign-in, the Library, the album page, the
queue menu, Now Playing and the mini player, Info, You). The Phase 0 app runs on the new engine (its own keys,
unique across plays; the streaming cache kept across launches; Normalization Off, no factor; the lock screen
without the queue's index and count), but nothing in it calls Up Next, resume, the Library's rules or
Normalization's yet, and `MARKETING_VERSION` is still 0.1 (ios.yml and check_project.py pin it) - 0.2 comes
with the screens.

**The decisions** that settled the specs' open questions, binding on all of it (D1-D13):

- **D1** Two tabs, Library and You, Library first. Debug sits under You for `isAdmin` (a Navidrome admin,
  break-glass, or anyone with logins off), and Phase 0's test screen moves there, its downloads folder kept.
- **D2** The Library opens on Albums ("Your albums", or "Albums" with logins off); a personal user also gets an
  "All music" heading with one "All albums" row (the store's scope). Five sorts with the web's ids
  (`alphabeticalByArtist` the default, `alphabeticalByName`, `newest`, `byYearDesc`, `byYearAsc`); grid or list
  per device, grid by default; the index (letters for Artist and Title, decades for Year) only at 50 albums or
  more and never while finding; New marks. The last album_index answer and its ETag are kept on disk per
  (server, user, scope); album_index gets 30 s to answer.
- **D3** Normalization is the web's rule. An entry's gain is fixed at its first open, waiting at most 20 s for
  the first song of a play (a join never waits); every album-level entry of one album shares ONE decision for
  the queue's life; FLAC only; Navidrome's replayGain is not used; the "no answer in time" words as levels.md
  proposed; Off's note without the "Maximum quality" clause; the loudness answer carries `algorithm`
  (loudness.ALGORITHM_VERSION); raw values over the wire, and the phone applies gain_for with reserve 0.
- **D4** Up Next: an edit that would change a next song already scheduled on a player node is HELD (the engine's
  replaceUpcoming answers false) and made at the next song change - the song being heard is never touched.
  Paged state and withMore are ported, with no shuffle feed in Phase 1; Next and Previous while paused keep the
  pause, as the web's do; the lock screen no longer gets the queue's index and count, and its shuffle and repeat
  commands stay disabled; "Shuffling your whole library" is ported as it is.
- **D5** Resume: the label "iPhone"; the device id as the web makes it (16 characters), kept in UserDefaults
  under `deadwax-player-device`; no album fetch after a pick-up; an unsent save retried at the next trigger, at
  most every 30 s; `paged` and `pagedRounds` carried through.
- **D6** Plays: a ListenTracker as plays-words.md has it; failures dropped as the web drops them, through one
  PlayReporter, with `time` always set on a submission.
- **D7** Errors: an APIFailure (status, method, path, detail, why, kind, busy - or offline, timeout, other) and a
  port of ErrorWords; a 401 on a stream stops the queue at that song and asks /me; a player failure's raw words
  only in Debug's "Last failure".
- **D8** Info: the decision applied to the song playing; the artist card the name only; the Gapless row always
  "On"; "Set it up in Server settings" opens /player/ in Safari.
- **D9** The engine: the output latency subtracted from every position; the stream cache's limit 2,000,000,000
  bytes, the least recently played out first; fetches of songs skipped past cancelled and their parts deleted; a
  seek past what has arrived waits (busy).
- **D10** At launch, /me failing without a 401 shows a can't-reach screen (the UNREACHED words, Try again, Change
  address, the detail for seesDetail).
- **D11** The Play Next / Play Last notice: a capsule above the mini player for 5 s.
- **D12** The id bridge is asked only when `hasLibrary`.
- **D13** ui/test/iostraces.sim.cjs runs ios/scripts/export-traces.cjs --check, so a change to the TypeScript
  rules the Swift ports mirror fails in tests.yml too.

D1, D2's screen, D8's, D10 and D11 are the screens'; the Core holds only the rules they draw by.

### Up Next and the queue

**Ported**: lib/upNext.ts and the queue parts of playQueue.ts are UpNextTypes.swift, UpNext.swift and
UpNextView.swift - every type, function and word (startUpNext, toppedUp, withRepeat, withShuffle, withNext,
withLast, withoutKey, movedKey, withoutAdded, jumpedTo, onward, backward, pastCopies, withMore, upNextView).
Randomness is passed in (`random`, a number in [0, 1)) and drawn in the TypeScript's order, so the same numbers
make the same queue. `QueueTrack(song:albumId:albumName:...)` is the web's toQueueTrack, its album filling in
what the song leaves out - never the title, which is the song's own ("" where Navidrome left it out, the web's
undefined; not Song.name's id - see "Review fixes"); `Repeat` is the device's own setting
(`deadwax-player-repeat`), never saved with the queue. Phase 0's PlayQueue.swift is untouched (the Phase 0 app still uses it).

**QueueController** is usePlayer.ts's queue rules over an `EngineLink` protocol (play, restore,
replaceUpcoming, skip, seek, resume, stop, heard): catching up with the engine, held edits, the top-up after 2 s
(half a short song's length - its decoded length, else its tags'), Next and Previous, the queue's end, a failed
song's skip, putting a saved queue back. Tested against a fake engine (pure Core, so Linux can run it too); it
replays no traces.

**D4 under the engine** has two consequences, both pinned by tests:
- A row's tap is the exception. A jump the engine refuses as an edit (in a song's last ~2.5 s, when the next
  song is already on a node - and during a seek on its way, where the web's jumpTo does nothing) plays the queue
  afresh from the row, catching up first in case the engine joined meanwhile, and makes a change already held
  after it: the jump leaves the song heard anyway.
- Repeat One turned on in a song's last ~2.5 s, with the next song scheduled, applies after the join and repeats
  the NEXT song; Repeat turned off there lets the scheduled copy play once more. The web repeats, or stops
  repeating, the song being heard.

**Failures**: `skipFailed()` acts only while `intendsToPlay` (afterFailure's stop): a paused phone stays paused,
and the retry of a load failure stays the app's.

**Held to the TypeScript**: ios/scripts/export-traces.cjs compiles upNext.ts and playQueue.ts and records 150
seeded traces (the state after every op), each scenario upnext.sim.cjs checks plus more, and digests of
upnext.sim's 2,000 property runs; UpNextTraceTests replay all of it, and the Swift port runs 2,000 wider property
runs of its own (lists of 1-12). **Found and left on main**: every one of upnext.sim.cjs's 2,000 property runs
starts from a ONE-song list - `seeded(run + 1)`'s first number is under 0.016 for every seed up to 2,000, so
`1 + pick(6)` is always 1. The fix is the web's (seed from spread values, or drop the first draw), then the
exporter run again so property.json follows.

### Resume

**Ported**: lib/resume.ts is Resume.swift - windowOf, toSave, relevel, savedLevels, fromSnapshot (every check in
the web's order), resumed (every branch), shuffledTrack, pickedUpWords, changedSince, saveDue. The snapshot is
written and read by hand (SnapshotJSON.swift's `WebJSON`) as JSON.stringify and JSON.parse do it - escapes,
Number-to-String, array-index keys first, Object.prototype's names, the cap counted in UTF-16 units - because the
phone's text must be the web's unit for unit (a queue saved on one is put back by the other) and JSONEncoder drops
nils, writes `\/` and writes 200.0. The reader keeps a stack of its own: recursing overflowed a 512 KB test thread
below 900 levels of nesting in a debug build. ResumeModels.swift is the wire (QueueAnswer, KeptQueue,
QueueSaveBody, QueueAtBody, SavedQueue), each property named as its JSON key, as SignInBody is. DeviceID.swift
makes and reads the device id (D5).

**ResumeController** is useResume.ts's createResume as a state machine over ResumePlayer, ResumeServer and
ResumeClock protocols, so Linux can test it too: observe, position, start, background, foreground, stop. Its
tests replay resume.sim.cjs's hook checks scenario by scenario, at the sim's timings. It replays no traces.

**Held to the TypeScript**: the exporter records 1,741 resume cases (each recorded snapshot also checked against
a reference writer) and resume.sim's 500-run round trip (40 kept whole, all 500 digested); the Swift tests write
every snapshot exactly as the web does and read every text the web wrote as the web reads it, and the Swift port
of the run generator makes the web's texts at every one of the 12,500 steps.

**Lessons**: Swift Testing dies with "Index out of range" (signal 5) and names no test, so the resume tests read
requests through `ResumePage.ask(kind, n)`, which records an issue instead; bound every loop that calls a
function under test (an unbounded one hung the run under a mutation); `x[key] = try #require(...)` picks the
wrong overload and warns - bind to a let first; write `#require(v as Bool?)` for an optional Bool.

**Mutations** (the review's, 42): 36 caught at first; the two real gaps (M40, tick's fallback to the tags'
duration; M36, the 0.5 s a queue put back is let go at) have tests now, as do four on the refused jump. Left
alive as near-equivalent, with no test: M34 (newer()'s `>` against `>=`), M35 (`idsRev` set on a position save -
/queue/at answers the unchanged ids_rev) and M39 (`countFrom` not reset in take).

### The Library's rules

DeadwaxCore holds the web Library's rules as Sendable value types on Foundation alone: `Fold` (foldName and
findText), `AlbumTime` (Date.parse and the month headers), `Shelf` and `ShelfIndex` (five sorts, the two readings
of Recently added, the headers, Find, the index), `AlbumIndexState` (albumIndex.ts's one list per scope, plus the
phone's own pieces - the 304 against the ETag sent, a list restored from disk, and `clear()` with an epoch so
nothing asked before a sign-out lands after it), `NewMarks` and `MyLibraryState` (the New marks and
"cleared when you open it"), `StarredCountWatch`, `LibraryWords` and LibraryModels.swift (`IndexAlbum` read
leniently - only `id` required, since the dev stand-in's `created` is a float and synthesized decoding would
lose the whole Library over it).

- **Comparing like JS**: fold keys compare as UTF-16 code units (`FoldKey`). Swift's String `<` and `contains`
  work on canonical Characters: they order Hangul jamo and astral ideographs the other way, and can't find "바"
  in "방탄". Final_Sigma is done by hand (`JSText.lowercase`).
- **Dates follow V8's ISO parser**: offset hours 0-23 and minutes 0-59; 24:00 only with every fraction digit 0;
  the fraction read as V8's ReadMilliseconds reads it (nine significant digits, scaled by at most nine:
  ".0123456789" is 123 ms); a time with no zone is local, with V8's "former" rule at the clock changes; days
  proleptic Gregorian, month headers from the UTC month. A space in the T's place goes to V8's LEGACY parser,
  which reads a year 0-99 otherwise ("0012-05-06 00:00Z" is 5 December 2006), so the port reads a space only after
  a whole date with a year outside 0-99 and says nil ("Date unknown") wherever the legacy parser alone would read
  it. Navidrome sends RFC 3339 with a T. A differential of 20,068 strings in four zones (80,272 comparisons)
  against Node 20.12.2's Date.parse found no string read to a different value; 7,176 that V8's legacy parser reads
  are nil here, each of a kind AlbumTime's comment names (dates.json's `legacy` lists them, with what V8 makes of
  each).
- **Recently added, yours**: stars chain into moments - a star at most 30,000 ms before the previous one joins its
  moment, 30,001 ms starts a new one.
- **Held to the TypeScript**: ios/scripts/export-library-vectors.cjs compiles lib/shelves.ts, owned.ts's
  foldName, myLibrary.ts, appFrame.ts and yourLibrary.ts with tsc, runs albumIndex.ts and useMyLibrary.ts as real
  modules against stand-ins for the network, and writes Fixtures/library/ (dates, fold, index, marks, seen,
  shelves, store, words: seeded, ASCII, never edited by hand) - 2,634 fold names (with Mc, Nl and No as they stand
  after NFKD; no Lt survives NFKD), 1,410 date strings in UTC, New York, London and Lord Howe plus 16 legacy
  kinds, 21 lists with 5 sorts and both readings plus Finds, 84 index fits, the 30,000/30,001 ms moments, and
  traces of the real store and seen modules.
- **Contract**: tests/test_ios_library_contract.py holds the models to INDEX_FIELDS (only id required),
  album_index's `{albums, truncated}`, AlbumScope and SCOPE_LIST, `_entry`'s keys (artist and album never null),
  my_library's answers, `Seen`, and the break-glass name.
- **Mutations**: the review's 16 and 8 more on the date code, all 24 caught.

### Normalization, plays and Info's words

The web asks deadwax for a levelled copy (`&level=`); the phone plays the original and multiplies every decoded
sample by one Float. So DeadwaxCore takes the web's setting and rule and the server's gain rule, as pure Swift.

- **The setting** (`Normalization`, Levels.swift): auto, song, album, off; Automatic by default, UserDefaults key
  `deadwax-player-normalization`, read as the web reads it (`read`: "song", "album", "off", anything else
  Automatic); the web's labels and notes, Off's without "unless Maximum quality converts it" (D3). `QueuedAs`,
  `Level` (album, track), `levelFor`, `relevel` and `Song.isFlac` are the web's.
- **The gain** (`gainFor`): src/loudness.py gain_for line for line, reserve 0, Python's `round(x, 6)` before the
  floor, FULL_DB written as Python's repr of it. `gainMultiplier` is worked in Double and rounded to a Float
  once; `AppliedLevel.multiplier` is nil for Off, a song that isn't FLAC, anything played as it is and exactly
  0 dB, so those play bit for bit. A measured loudness with a NULL peak plays as it is (the phone's own rule: a
  peak of 0 would mean no limit, and the engine has no limiter).
- **When** (D3): `LevelDecisions`, one per queue, keyed by Up Next's key. An entry is decided at its first open
  and keeps it; an album's album-level entries are all decided from the answer in hand when the first was (none
  included), so an album never steps. `settled(key:level:song:)` says what an entry will play at before it is
  opened, and Info reads that - never a fresh decision on the live answer. Only the first song waits
  (`LevelWait`, at most 20 s, never for a song the answer doesn't list or one not levelled); `LoudnessAsking`
  reads, warms when unmeasured, reads every 5 s while measuring, and reads once more after a warm says
  not_levelled (the read says why). LoudnessModels.swift is the route's answer (`AlbumLoudness` with its
  `AlbumLevel` and `SongLoudness`; a state this app doesn't know decodes as unmeasured), the warm's (`WarmAnswer`)
  and `LevelAnswer`, the shape Info's words are written against, which the phone makes from what it applied
  (`levelAnswer`).
- **Words**: Debug's `describeLevel`, About's `aboutLevel`, `soundRows` and `formatWords`, verbatim; every toFixed
  through `jsFixed` (JS rounds an exact tie away from zero, printf to even); Info's numbers rounded as levels.py
  rounds its own (half-even: +0.125 reads "+0.12"); D3's two lines for no answer in time; Gapless always On (D8).
  `AboutCard.about` is aboutRows' cards, the artist card the name only (D8); `AboutDiscTitle` reads `disc` as
  JS's Number() does (" 2 ", "2.0", "0x2" and true are discs), apart from the routes' Int-reading `DiscTitle`.
- **Plays** (D6): the web's rule, `Listen`, `PlayReport` (now playing, or a play with its time in whole
  milliseconds) and `ListenTracker`, usePlayer's bookkeeping: nothing counted before `began()`, and at a join the
  old song's rest counts to it, the clock restarting there.
- **Held to their sources**: ios/scripts/export-level-vectors.cjs compiles the web's TypeScript and runs
  ios/scripts/level_vectors.py (44 gain_for cases: the spec's 41, the route's example album, a hi-res album played
  by the phone and by the web), writing Fixtures/levels/ (levels-vectors, info-vectors, plays-vectors), which the
  Swift tests, tests/test_ios_levels.py and ui/test/ioslevels.sim.cjs read.
- **libm**: the vectors are made on macOS; CI's pytest runs on Linux, whose glibc log10 isn't correctly rounded
  (five peaks' dB an ulp apart, by an emulation of e_log10.c). So pytest compares what log10 and pow make within
  a few ulps, and each case carries `log10_stable` (its gain and held unchanged with log10 1 to 4 ulps off). Only
  the 24-bit largest sample isn't (its limit is exactly 0): Swift holds it to the rule's property, and both
  suites pin that set. Under the emulation, 6 of test_ios_levels.py's tests failed before that and all pass now.
- **Mutations**: 15 (the review's 11 and four on the fixes), all caught.
- **Left from the first review, not changed**: just after a warm the book holds `unmeasured` for up to 5 s and
  `LevelWait.shouldWait` doesn't wait on that, so the first play of a never-measured album would be fixed as
  unmeasured - the app's LoudnessBook should record the warm's 202 `measuring` as measuring, or shouldWait take
  a warming flag; `gainFor` and `jsFixed` can give -0.0, which nothing shows today.

### The engine

From specs/engine.md with D4 and D9, then the review's fixes (DeadwaxAudio; its pure arithmetic in Core).

- **Gain** is a source wrapper: `GainedSource.wrap(source, factor:)` returns the source itself for nil or exactly
  1.0 (Off is the decode, bit for bit), else a `vDSP_vsmul` of each channel of each buffer as it is read, so every
  reopen carries the entry's one factor. No limiter. Measured: the 44.1 -> 48 kHz lane carries a full-scale tone's
  inter-sample peak to +3.01 dBFS (R10).
- **Keys**: `EngineTrack {key, audio, song, open}`, `audio` = `"<id>|<level or off>"`. `replaceUpcoming(tracks)
  -> Bool` (synchronous) replaces Phase 0's replaceTracks: refused unless the song heard keeps its index, its
  audio and the keys before it; items kept while their audio matches, re-keyed; a next song not yet on a node let
  go and the new one opened after the last kept; one already on a node holds the edit (false, D4); a song added
  after the queue's end opened.
- **One heard position**: the render less `latency()` (D9). Pauses, route changes, media resets and failures go on
  from the heard frame. A song change is published when it is heard, on its own timer between completions;
  entries are forgotten a second and the latency behind the render; the queue's end stops the output after
  latency + 0.1 s. `EnginePosition {key, index, seconds, length?}` - length the whole song's, after a seek too.
- **Routes and resets** go on from Core's `HeardEstimate.atStop`: the last reading carried on for at most 1 s,
  capped, less the OLD route's latency; the mixer reconnected at the hardware rate. Ended stays ended and failed
  keeps its words through a new route and through `rebuild()`, which never calls into the dead engine.
- **Paused loads nothing**: restoreQueue, or a skip or seek while paused, opens nothing and reports no
  fileRate/fileChannels until play opens the song; a pause keeps its own song's rate.
- **Seeks** past what has arrived wait (Loading); a deep seek says `busy` and is read again at once.
- **Failures**: `AudioFailure {description, kind, status}` (network, decode, unsupported, signedOut, other). A
  next song's 401 waits for the song heard to end, then stops the queue there (D7).
- **The streaming cache** (Core's `StreamCache` and `StreamCacheFolder`, the app's SongFiles):
  `Caches/deadwax/stream/<id>.<suffix>`, kept across launches now. A `layout-1` marker records the layout, and the
  folder 0.1 left (its fetches wrote under the song's own name) is emptied once. A fetch writes `.part`, renamed
  only when Content-Length is met; a cancel before `start()` makes nothing. Past 2,000,000,000 bytes the least
  recently played go first - never the song heard, the next, or a live fetch. Fetches of songs skipped past are
  cancelled from the EARLIER of the state's index and the engine's own (`StreamCache.kept`): a state reaching the
  main thread late, after a quick Previous, used to cancel the fetch the engine had just opened (reasoned from
  the code, never reproduced). Sizes are read as NSNumber or as UInt, which Linux's swift-foundation gives.
- **Tests**: StreamFetchTests wait by suspending, not blocking - nine blocking in parallel stalled every fetch on
  this 8-core Mac, and a 3- or 4-core runner would have stalled on the original six. 13 mutations (the review's 8
  and reverts of the five fixes), all caught.
- **Not built**: the spec's CachedStreamSource (6.2), 3.4's staging, 4.3 #5's rate-change test, and 5.2 #10 (a
  prefetch after every replaceUpcoming that changes the next song - for when Up Next is wired). Minor and left:
  `stop()` calls `files.keep([])` on main while the engine's stop is still queued, so a next-song fetch opened in
  that gap runs to the end and is cached.

### The API, models and errors in the listener's words

- **Routes.swift** names all 26 routes the app calls (`lyrics` the 24th, since app 0.4; the EQ's `autoEqSearch` and `autoEqProfile` since its slice 4), one `Endpoint(method:path:query:)` a line in the form
  tests/test_ios_contract.py reads, all listed in `Routes.all`. `Routes.timeouts` gives album_index 30 s (D2),
  AutoEq's two 20 s (deadwax waits up to 15 s for AutoEq's list or a file - EQ slice 4's review), everything else the
  transport's 8 s; `CoverSize` is row 128, tile 400, hero 1024 (and the lock screen's 1024).
- **Models.swift** reads Navidrome's pass-through answers leniently: a field of another type is absent, and a song
  that can't be read is left out rather than losing the album. Me's version, permissions and
  permissions_unverified are optional, so an older server still reads. `NavidromeStatus` was added at the merge
  (below).
- **APIFailure** replaces Phase 0's DeadwaxError (kept as a typealias, so Phase 0's screen reads as it did). It
  keeps everything api/http.ts's ApiError keeps - status, method, the route with its query, detail, why, kind,
  busy, FastAPI's 422 list - and when nothing answered it is `.offline`, `.timeout` or `.other`. A cancelled task
  is a CancellationError, never a failure. The client tells `onSignedOut` of a 401 from any route but the
  sign-in's, with the session the request went out under. `fetch(..., ifNoneMatch:)` returns `.unchanged` on a
  304; URLSessionTransport keeps no cache of its own, so the 304 reaches it.
- **Offline is narrower than the web's, deliberately**: only the codes meaning no network or no host (-1009,
  -1005, -1004, -1003, -1006, -1020, -1018). TLS failures, an answer that isn't HTTP and ATS's refusal are
  `.other`, told to tell whoever runs deadwax - checking the connection can't fix a certificate. The web says
  "Can't connect" for all of them only because fetch's TypeError can't tell them apart. D10's can't-reach screen
  gets every /me failure but a 401 either way. ClientTests.whichTransportFailuresAreOffline pins every code.
- **ErrorWords.swift** ports lib/errorWords.ts, signIn.ts's sentences and the media errors' words, its patterns
  written so ICU matches what JavaScript matches: `\b` as ASCII lookarounds, `/i` as both cases of each letter,
  JavaScript's own `\s` set, `$` as the end of input; trim and `===` on JavaScript's terms; `upperFirst`
  upper-cases only a BMP first character, as charAt(0) does (U+10428 stays U+10428).
- **Access.swift** ports access.ts (can, isAdmin, seesDetail, isBreakGlass, hasLibrary - D12) and signIn.ts's
  afterSignIn.
- **Held to the TypeScript**: ios/scripts/export-error-words.cjs compiles errorWords.ts and signIn.ts and writes
  Fixtures/errors/error-words.json (77 errors in 10 ways, 105 plumbing strings, 40 job reasons, the sentence
  cases), which ErrorWordsTests replays.
- **Mutations**: four gaps in the first commit (the server's required query names unchecked, two offline codes
  untested, the BMP guard) found by mutation and closed; six mutations, all caught.

### How the ports are kept in step with the web

Every pure rule the phone shares with the web is held to the web's own TypeScript, compiled and run - never to a
reading of it - by a committed exporter that writes the fixtures the Swift tests replay, and a sim that runs the
exporter with `--check` so tests.yml (which runs every sim, each on its own) fails when the web moves:

| exporter (ios/scripts/) | what it runs | fixtures (Tests/DeadwaxCoreTests/Fixtures/) | sim (ui/test/) |
| --- | --- | --- | --- |
| export-traces.cjs | upNext.ts, playQueue.ts, resume.ts; hashes 23 pieces of usePlayer.ts (upnext/'s `made_from`) and useResume.ts's createResume (resume/'s) | upnext/, resume/ | iostraces.sim.cjs (D13) |
| export-library-vectors.cjs | shelves.ts, owned.ts's foldName, myLibrary.ts, appFrame.ts, yourLibrary.ts; albumIndex.ts and useMyLibrary.ts as modules; Node's Date.parse | library/ | ioslibrary.sim.cjs |
| export-level-vectors.cjs | loudness.ts, resume.ts's relevel, streamWrap.ts's isFlac, the words, aboutRows, the play rule, toFixed; src/loudness.py through level_vectors.py | levels/ | ioslevels.sim.cjs |
| export-error-words.cjs | errorWords.ts, signIn.ts | errors/ | ioserrorwords.sim.cjs |
| export-screen-vectors.cjs | SignIn.tsx, SignOutRow.tsx, QueueMenu.tsx, MiniPlayer.tsx, signIn.ts, whose.ts, scrub.ts, discTitles.ts, format.ts; lines of AlbumPage.tsx, NowPlaying.tsx and signInGate.tsx read out by pattern | screens/ | iosscreens.sim.cjs |
| export-you-vectors.cjs | You.tsx's expressions and words, read out of the source and evaluated as written (136 cases) | you/ | iosyou.sim.cjs |
| export-gate-vectors.cjs | NeedsNavidrome.tsx, access.ts, errorWords.ts, navidromeCheck.ts, the gate rendered against a Preact stand-in (35 cases) | gate/ | iosgate.sim.cjs |
| export-lyrics-vectors.cjs (app 0.4) | lyricsView.ts - every rule of notes/app-lyrics.md 2.2-2.7 and the words - with lyrics.ts's lyricTime and scrub.ts's LANDED_WITHIN_S; the server's answers (src/lyrics.py song_lyrics()) through lyrics_answers.py, held by test_ios_contract.py | lyrics/ | ioslyrics.sim.cjs |
| export-deck-vectors.cjs | platter.ts, turntable.ts, playSpeed.ts, deckClock.ts's pointerSamples, debugRows.ts, deckVoice.ts, and the real deck.ts driven through ui/test/deckHarness.cjs (deck.sim's own fakes) with deckVoice.ts rendering beside it; theme.css's turntable tokens; the words of Turntable.tsx, SpeedFader.tsx, SpeedChip.tsx, LookChoice.tsx, WindDownChoice.tsx and You.tsx; every Math call recorded (maths.json, its committed answers reused); the real Turntable.tsx and NowPlaying.tsx mounted over it and driven by pointer events and keys (press/, 13 traces), its handlers hashed; made.json, who made them | deck/ (75 files, 3 MB budget) | iosdeck.sim.cjs - byte for byte on the maker's Node, platform and arch, the sources elsewhere |

`--check` makes everything again in memory and compares it byte for byte with what is committed, so a hand edit
fails too. **A web rule changed**: its sim fails; run the exporter and commit what it writes; that touches ios/,
so ios.yml's Swift run says whether the port still agrees - and fails until the Swift is changed to match. **The
two controllers replay nothing** (QueueController and ResumeController are ported by hand), so their pieces of
usePlayer.ts and useResume.ts are hashed into the fixtures' `made_from`, function by function, each found exactly
once: a change fails naming the piece and the Swift file - port it first, then run the exporter. The server's
side is the Python suite's: tests/test_ios_contract.py, test_ios_library_contract.py and test_ios_levels.py read
the Swift source and hold it to the routes, models and constants it relies on, so a server change that would
break the app fails where the server is changed.

### The merge (p1/merge)

- **Folded**: `Level` (p1/queue's Level.swift and p1/levels' Levels.swift) and `Normalization` with `relevel`
  (p1/queue's Normalization.swift and Levels.swift) were each declared twice. The queue slice's copies were the
  levels slice's to the character (CaseIterable included, after its review), so Level.swift and
  Normalization.swift were deleted and Levels.swift's kept: the same cases and raw values, the same default, the
  same storage key and the same reading of a stored value; resume's callers (fromSnapshot, resumed, savedLevels,
  the tests) compile against it unchanged. A scan of every type and function name declared in Sources/ (by
  nesting, comments and strings blanked) found no other name declared twice.
- **Added**: `NavidromeStatus` (Models.swift), the status route's `{configured, ok, server, problem}`, so the route
  Routes.swift names has a model the contract checks (ClientTests decodes its three shapes).
- **The contract, extended** (tests/test_ios_contract.py: 36 tests after the api slice, 46 now): resume's models
  against play_queue.answer and kept_view (and the store's schema: every nullable column optional in KeptQueue),
  QueueSave and QueueAt (both `extra="forbid"`: exactly their fields, the server's required ones non-optional),
  the saves' answers, the device id's alphabet and length and the label against DEVICE_PATTERN and LABEL_PATTERN,
  and Resume's window, caps and client name against play_queue's; AlbumLoudness, AlbumLevel and SongLoudness
  against levels._loudness_answer, _album_level and _song_entry (with `algorithm` required and the states the
  server says); LevelAnswer against describe()'s answer and Level against the route's Literal; NavidromeStatus
  against each of the status route's three answers; a PlayReport's query read from Plays.swift and sent through
  the real scrobble route; SeenBody's two shapes posted to /me/library/seen. Required fields are a model's
  non-optional lets wherever in DeadwaxCore it is declared (test_ios_library_contract.py reads every Core file now
  too). The route count is checked by name: every `static let X = Endpoint(` is in `Routes.all`, once. 29
  mutations, one or more per model (a field renamed, an optional made required, a raw value renamed, a route left
  out of `all`), each restored byte for byte: all 29 fail.
- **Near-duplicates left**, each read the same way where both apply:
  - `AboutTrack(song:)` and `QueueTrack(song:albumId:albumName:...)` (the web's toQueueTrack): the same for a song
    that carries its own artist, album, album id and cover; for one that doesn't, QueueTrack falls back to the
    album's, AboutTrack to "" and nil. A title is the song's own in both ("" for none). The web's About is drawn
    from the queue's entry, so the screens should make About's track from the QueueTrack (an
    `AboutTrack(track:)`), not from the Song.
  - `AboutAlbum` / `PressingRow` (About's, all optional, numbers as Double, read by JS's rules) and `Album` /
    `StoreRow` (the routes', `id` required - and `path` for a row - numbers as Int): the same bytes read the same
    for every answer the server sends; they differ only on malformed ones (a year of 1975.5, a disc written
    " 2 ", a row without an id). `AboutDiscTitle` (JS's Number()) and `DiscTitle` (Int) likewise.
  - `AboutCard.trackTime` and `discHeadings`/`discTitleMap` (format.ts and discTitles.ts, About's) have no second
    copy in Core; the album page will need the same headings and should call these.
  - `PersonalLibrary.has(me)` and `Access(me:).hasLibrary`: the same rule (logins on, not break-glass), each with
    its own `breakGlassUser = "deadwax"`, both pinned to auth.BREAK_GLASS_USER.
  - Three JS trims (`WebText.trim`, `JSText.trim`, `ErrorWords.trim`) over the same set of scalars, and two
    `same` (UTF-16 equality): identical answers. `WebText.number` and `WebJSON.number` (both JS's String(n)) agree
    from 1e-4 to 1e16; outside it only WebJSON lays the digits out as JS does (WebText's callers are rates and
    disc numbers).
  - DeadwaxClient's private `LevelWarmed {state?}` and LoudnessModels' `WarmAnswer {state}`: the client hands the
    state on as a String ("" for none), which the app wraps in a WarmAnswer for `LoudnessAsking.afterWarm`.
  - `DeadwaxClient.scrobble(songID:submission:time:)` builds its own query; `PlayReport.query` builds the same
    one (a play always with its time, which the client's signature leaves optional).
  - Phase 0's `PlayQueue` (still the Phase 0 app's) and Up Next's `previousAction`: the same 3 s rule.

### Review fixes (p1/merge, after the merge's two reviews)

Two reviews of p1/merge at 43c11d5: the merge's (every slice's files and both folds checked by script, 82
contract mutations) and a Linux reading of everything new in Core (no Linux toolchain on the Mac).

- **GET /queue's songs hold every field the phone resumes from.** The route trims each song to
  navidrome.SHUFFLE_FIELDS, and shuffledTrack makes every resumed entry from what is left - but the contract
  only held Song's one required field (`id`) to that list. Without `suffix` and `contentType` every song put back
  would read as no FLAC, so the queue would play unlevelled; without `duration` every length would be 0. (The
  review dropped suffix: the contract and the 1,182 tests of the 19 files that touch the route or its fields all
  passed.) test_ios_contract.py now reads shuffledTrack's `song.<name>` reads out of Resume.swift, by Song's JSON
  names, and holds them to SHUFFLE_FIELDS (guarded: the reads found include id, title, duration, contentType,
  suffix and samplingRate). Dropping suffix, duration, contentType, samplingRate or title from SHUFFLE_FIELDS
  each fails it, naming the field. The web's toQueueTrack reads the same fields and has the same gap on main's
  side (a test for main, not this branch).
- **`QueueTrack(song:)`'s title is the song's own**, `song.title ?? ""`, as the web's toQueueTrack (`title:
  song.title`) and the phone's own shuffledTrack have it. It was `song.name`, which falls back to the id, and
  the notes called it the web's toQueueTrack: a phone-saved snapshot carries an entry outside the saved window
  whole (resume.ts toSave's `extra`), so a song with no title would have reached the web with its id for one.
  UpNextTests' aQueueEntrysTitleIsTheSongsOwn holds a missing and an empty title to "" (both fail under
  `song.name`), and shuffledTrack's too.
- **One way to find a fixture, the same on both platforms.** LevelVectors and LibraryFixtures found their files
  with `Bundle.module.url(forResource:withExtension:subdirectory:)` and nothing to fall back on; ErrorFixture
  fell back to the bundle's `resourceURL`, the Up Next and resume traces used only that. Whether CFBundle's
  subdirectory search reads Linux's flat `.resources` folder as the Mac's bundle is read had never been tried
  (at 40bd97e no Core test read a resource). All four now go through `Fixtures.url` (FixtureFiles.swift): the
  checkout's Fixtures/ beside the file, found from `#filePath` - `swift test` runs from the checkout on the Mac
  and in ios.yml's ubuntu job, and no Bundle is involved - else the bundle's copy by `resourceURL`, else a
  `Fixtures.Missing` naming the path (the plain error replaces LevelVectors' CocoaError). FixtureFilesTests holds
  each area's file to the checkout's path (fails with the bundle looked in first) and a missing one to its
  error (fails when the checkout's path is given without looking).
- **Rejected, with why**:
  - *The resource accessor might not compile on Linux in Swift 6 mode*: it has. ebb2ad8 declared
    `resources: [.copy("Fixtures")]` on both test targets, and ios.yml's run at 9f5a78a (the merge of 2.1.1,
    after it) built DeadwaxCoreTests on swift:6.4.1-noble in Swift 6 mode and passed (64 tests) - so SwiftPM's
    generated `Bundle.module` compiled there. Nothing changed in Package.swift but its comment.
  - *URLError.Code members missing on Linux*: every one Core and its tests name - isOffline's seven
    (`.dataNotAllowed` and `.internationalRoamingOff` among them), the four ClientTests expects to be `.other`
    (`.secureConnectionFailed`, `.serverCertificateUntrusted`, `.badServerResponse`, `.cannotParseResponse`) and
    `.timedOut` - is a case of swift-corelibs-foundation's `URLError.Code` (Sources/Foundation/NSError.swift, read
    on its main branch), none inside an `#if`.
  - *glibc's log10 an ulp off*: already allowed for - the one case that hangs on log10's last bit is marked
    `log10_stable: false` and held to the rule's property; `fullDB`'s formula check is within 1e-18, far wider
    than its ulp.
  - *tzdata, NFKD, NSRegularExpression, JSONEncoder on Linux*: nothing to change before the ubuntu job says
    otherwise (the zones are four whose rules tzdata has long agreed on; the fold fixtures' code points are old;
    the patterns spell their classes out over ICU on both; the encoder is swift-foundation's on both). A
    pattern's `try!` failing would crash at its first use with the error in the log - a test that built each
    pattern first would crash the same way.

### The screens' own rules (p1/screens-core, merged on ios)

Every decision the web's sign-in screen, album page, queue menu, mini player and Now Playing make is a pure
DeadwaxCore port, so the SwiftUI views only draw. Built on 790037d (before the Up Next slice), then merged into
ios after it.

- **SignInRules.swift**:
  - SignInForm: the name trimmed with JS's trim, the password as typed and cleared after any answer, busy, the
    problem and its fold, the reason never said twice.
  - launchReason, from signInGate.tsx.
  - endsSession(failure, sentUnder:current:), http.ts's noteSignedOut over the phone's cookies:
    `failure.isSignedOut && sentUnder == current`. DeadwaxClient's onSignedOut passes the cookie the request
    carried; the web's session counter is not ported.
  - SignOutRow: any answer from deadwax starts the app again; no answer keeps you signed in; a cancelled task
    leaves the row as it was and says nothing (the phone's own call - the web's sign-out can't be cancelled).
- **Whose.swift**: albumMine, heldLabel, the six words, the mine button, and
  albumMine(personal:album:albumFailed:store:storeFailed:changed:), wired the way AlbumPage.tsx wires it.
  badgeShown, placeholderShown and mineBlockShown are the page's three display conditions; `bridgeAsked: false`
  (Phase 1 without a library) draws the badge at once, which the web never does because it always asks.
- **DiscTitles.swift** (DiscHeadings) and **Format.swift** (trackTime, formatDuration, clock, sharedFormat,
  isLongTitle; AlbumPageLines: the meta line, footer, row number and artist, the warm).
- **Scrub.swift**: all of scrub.ts (an engine file, read only), with JS's Math.max/min for NaN and -0; and the
  phone's own landed and settled - a pending seek is let go of once the engine reports a position less than
  1.5 s from the target, or after 20 s, since the engine has no 'seeked' event. Those two are hand-tested, with
  no TypeScript behind them.
- **PlayerWords.swift**: the mini player's and Now Playing's words, the hairline (progress), a failure's words
  by its kind (AudioFailure.Kind mapped to the web's media codes; signedOut is 4), the engine's own description
  for Debug only. afterFailure gives retry, skip or stop; where a skip goes is QueueController.skipFailed's
  (past Repeat One copies, nil at the end), so the web's nextIndex is not ported.
- **QueuePick.swift**: Play Next and Play Last as a choice, and the level each song is queued at. At the merge
  `QueueChoice` became a typealias of the Up Next port's `QueuedHow` (which took the menu's `label` and
  CaseIterable), and the notice is `queuedWords` - one copy of each.

**Vectors**: ios/scripts/export-screen-vectors.cjs compiles the TS with ui's tsc and drives SignIn.tsx,
SignOutRow.tsx, QueueMenu.tsx and MiniPlayer.tsx (with its Progress) against stand-ins. The lines that live
inside AlbumPage.tsx, NowPlaying.tsx and signInGate.tsx are read out by pattern and evaluated as written, each
hashed in made_from; a pattern that stops matching stops the script. It writes Fixtures/screens/{signin, whose,
discs, format, scrub, player, queue}.json (plain ASCII, seeded, special numbers as strings); `--check` compares
byte for byte, and ui/test/iosscreens.sim.cjs runs it. The Screen*Tests replay every vector and fail when a
replay compared nothing.

**Reviewed**: seven findings, all real, all fixed in 679c69a - the session rule moved onto cookies (it had been
ported over a counter the client can't supply), the frozen scrubber (landed/settled), the queue picks' albums,
the readout's `rate || 1`, the album page's display rules, afterFailure's skip left to skipFailed, and the
hand-off note. Mutations: 33 at review (29 caught, 3 real gaps since fixed, 1 equivalent), 22 after the fixes
(21 caught, 1 equivalent).

**Known differences**: About.swift's own trackTime writes 'inf:nan' for Infinity where the web and Format write
'Infinity:NaN' - they agree on every finite length, and About's trackTime, sharedFormat and disc headings fold
into Format and DiscHeadings when About.swift is next touched. The DiscTitle model reads disc as an Int or a
digit string, narrower than JS's Number(), and agrees on everything Navidrome sends. isSignedOut uses hasPrefix
where http.ts uses startsWith; they agree on every ASCII path, and every route is ASCII.

### A stop is not the song ending (found by ios.yml, fixed on ios)

The first push of Phase 1's Core (87024cd) failed ios.yml's macOS job (macos-26-arm64, Xcode 26.6) twice.
Both times positionFollowsTheSongHeard failed. The first time aCallGoesOnFromWhereTheSongWas also failed, with
the pause held at 2.0 s (the song's end, not the 1.0 s it had reached), and then crashed indexing past the
song. Both tests passed on this Mac and at 9f5a78a, so the failures were races, and one of them is a real phone
bug.

- **The bug.** When the engine is stopped, AVAudioEngine calls back the completion of EVERY buffer still
  scheduled, at once, with the output not running. A trace with the stop marked showed it: two came in before
  the pause and eight after. played() took each as rendered, so a lane whose callbacks all arrived before the
  pause ran dry. The song "ended" at the last frame scheduled, and finish() was called. On the phone, iOS stops
  the engine for a call before the app hears of the interruption, so the callbacks would win that race nearly
  every time: the call would come back to the queue's end, or to a song a minute on. Before this, nothing
  stopped the engine from outside but tests.
- **The fix.** played() returns while `!engine.isRunning`: the samples were let go, not heard. Every way on from
  such a stop - play (resumeNow sees the output stopped), a new route (configurationChanged), a media services
  reset (rebuild) - calls reset(), which lets the lanes go and starts again from the frame heard, so no count
  waits on the dropped callbacks. The engine's own stops either reset first (pauseNow, armIdle, stop) or come
  with nothing left scheduled (finish).
- **The tests.** aCallGoesOnFromWhereTheSongWas now waits 0.1 s after iOS's stop before the interruption, the
  order the phone has. It checks the engine still says playing at the frame it was at, and that it goes on from
  inside the song (a `#require`, so a regression fails rather than crashing the run). With the fix taken out it
  fails on this Mac every time, with CI's crash. positionFollowsTheSongHeard waits (RenderHelpers' waitFor) for
  the first song's completions, which come on AVAudioEngine's thread after the render - settle() alone can run
  first, as it did on the runner with the Core suites running beside it. aPauseStopsTheOutputAndPlayGoesOnFromWhereItWas
  has the same `#require`.
- **On the phone:** Phase 0's "a phone call" check (not done yet) is where this shows; also check that a call
  that comes in mid-song goes back to the same place in the same song.

### The engine's tests under load (fix/engine-ci)

ios.yml's macOS job (macos-26-arm64, 3 vCPU, Swift 6.3.3) failed at 70cbef6 on two engine tests that pass on
this Mac:
- aJoinIsTheTwoSongsLaidEndToEnd: on both channels the first difference was at frame 4096, the first frame it
  checks, and the largest difference in the first 4096 frames was 0.45767212 and 0.45776367. Those are the
  song's own peaks there, so the render was silent from frame 0. Its next check, silence after the last song,
  passed: nothing of the song came late, so the render was silent throughout, not a node started late.
- aNextSongNotYetOnANodeIsLetGo: `sample 0 of 22050 is 0.0, expected -0.44799805`. A was whole, but C wasn't
  straight after it.

Swift 6.3 builds ONE test bundle, so on the runner Core's 452 tests run in the engine's process. Swift 6.4 here
builds one bundle per target. To run it as CI does, a scratch package (not committed) symlinked both targets'
test files into one test target, and that ran under `perl -e 'alarm shift; 1 while 1' 600` CPU hogs, 5 or 7 of
them on this 8-core Mac.

**Before any change.**
- One process, 5 hogs: 2 of 10 runs failed.
- One process, 7 hogs: 7 of 10 failed, 1 crashed (SIGTRAP) and 2 passed.
- One process with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`, 5 hogs: 2 of 6 failed.
- The Audio suites alone, 5 hogs: 0 of 10 failed.
- No load: 2 of 2 passed.

Every failure was aNewRouteGoesOnFromTheFrameHeard, neither of CI's two. What was found:

- **A new route went on from the frame rendered (an engine race; it can happen on the phone).**
  - The test expected position 0.4 after iOS stopped the engine for a new route, and got 0.5 (all 9 times),
    the frame rendered.
  - sample(of:) kept each reading with `lastLatency`, the latency read the time before. Offline that is 0 until a
    buffer's completion has read one, so with the position read ahead of the completions (load) the reading
    carried 0. The stop then went on from the reading's frame less no latency.
  - With no load, 10 of 100 runs of it alone failed in a loop.
  - On the phone a play reads the latency as it starts (playFromSilence), so a session's first reading is
    right. But after a new route the engine goes on by itself, and its first reading there carried the old
    route's latency. A call or another route change before the next reading then went on off by the two routes'
    difference. A listener would hear a fraction of a second skipped or played again, between Bluetooth's
    latency (about 0.2 s) and the speaker's (a few ms).
  - The fix: the reading carries the latency read with it (`currentLatency()` in sample(of:)). heardFrame and
    followHeard use that same read (`lastLatency`) rather than reading it twice.
  - The test, aNewRouteBeforeAnyCompletionGoesOnFromTheFrameHeard, renders 4000 frames (short of the first
    buffer, so no completion can come), reads the position, then has iOS stop the engine. It wants 1600
    (0.0333 s) and the song bit-exact from there. Without the fix it gets 0.0833 s, the frame rendered.
- **The render helper's 10 ms sleep stood in for "the completions came" (test timing: CI's
  aNextSongNotYetOnANodeIsLetGo).**
  - The engine tops its node up from each buffer's completion (played()). Offline nothing paces the render, and
    the completions come on AVAudioPlayerNode's own queue after it, at no set time. So a starved completion
    thread lets the next piece render past what was scheduled: silence.
  - Made certain with `completionLag`, a tests-only hook that handles each completion N s after AVAudioEngine
    calls it back. With the old sleep, a lag of 25 ms or more broke the song (A at frame 9134) and 20 ms or less
    passed. Holding the completions 40 ms only from A's fourth buffer on made CI's failure exactly: A whole, and
    `sample 0 of 22050 is 0.0, expected -0.44799805`.
  - The fix: `render()` and the tests' other piecewise loops now call `completionsHandled`. It waits (1 ms
    polls, bounded at 5 s) until `completionsDue` is 0 - the buffers the render has passed whose completions
    the engine hasn't handled - then `#require`s it.
  - The test, aNextSongNotYetOnANodeIsLetGoWithItsCompletionsLate, is the same test with every completion 50 ms
    late. It passes now and fails with the sleep back.
  - On the phone the output paces the render and keeps 2 s ahead, so a completion would have to be about 2 s
    late. That is any starved player, heard as a gap where the next song should join, not a logic race. The
    engine is unchanged for it.
- **A crash (SIGTRAP), test-only, fixed in the engine.**
  - The crash report puts it on AVAudioPlayerNodeImpl.CompletionHandlerQueue: -[AVAudioEngine dealloc],
    DetachNode, AVAudioPlayerNodeImpl::StopImpl, then dispatch_assert_queue_not.
  - The completion closure promoted the engine there. A test that let go of its engine with completions still on
    their way made that the last reference, so AVAudioEngine was deallocated on its own completion queue,
    stopping its nodes there, which traps.
  - The fix: nothing on that queue holds the engine. The completion, and likewise the configuration-change
    observer, captures the engine's queue and promotes `self` only on it.
  - The test, anEngineLetGoWithCompletionsOnTheirWayGoesAtOnce, holds completions 30 s away and wants the engine
    gone once the test lets go of it. It fails with the strong capture back.
  - On the phone the app holds one engine for its whole life, so this can't happen there.
- **The other sleeps (test timing).** These were not seen failing, but they had the same shape:
  - positionFollowsTheSongHeard, aShortSong… and theQueuesEndIsHeard… now call `completionsHandled`.
  - aCallGoesOnFromWhereTheSongWas waits for `callbacksOutstanding` to be 0, then `#require`s it. That counts
    every buffer scheduled less every completion handled, ignored or not, which is what a stop lets go.
  - theSongChange… waits on its own condition (stateNow.key == 1, the engine's own 0.95 s timer) and checks only
    A's buffer called back, in place of sleep(1.2).
- **aJoinIsTheTwoSongsLaidEndToEnd: not reproduced.**
  - It passed in every run here: 31 one-process runs before the fixes and every package run after, a
    200-iteration loop of it under spinners and delays, and 300 runs of its first engine in a fresh process.
  - It renders in one call, with no completion involved, so the helper isn't its cause. A render silent
    throughout means the node wasn't playing, or the output wasn't running, when it rendered.
  - It now `#require`s phase `.playing` and the output running before the render. On a difference it prints
    where the song begins in the render (`whereItBegins`: silent throughout, or the frame its first 64 frames
    are at), the phase, the output's state and the engine's trace. Since the reviews the trace says "the output
    started", "the output stopped", every configuration change (the output's state, and whether it was
    playing), and "rendered N of M frames as silence: the output is stopped" when renderOffline fills with
    silence because the output is stopped. The next CI failure will say which.
  - A lead, not followed up: in both of CI's runs the first tests took 5 s and 10.5 s even when trivial
    (aFetchLetGoBeforeItStartsMakesNothing), and the log's lines there came about 10 ms apart, as if the
    output were paced. Whether the whole process was held, or only its output, is not known.
- **A fetch's own timeout raced a starved test (test timing; first seen here with the pool cut to one thread,
  and by the second review without it - see "After the two reviews").**
  - After the fixes, a harsher run than ios.yml's: one process with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`
    under 7 hogs. aSkippedFetchIsCancelledAndItsPartDeleted failed in 1 of 6 runs, then 4 of 6: its part was gone
    before the skip, and the test took about 30-37 s.
  - StreamFetch's request fails after 20 s without a byte (timeoutIntervalForRequest). The test holds a fetch
    open, and its task waited longer than that for the one thread. Once the test named it, the failure read "The
    song stopped arriving: The request timed out."
  - A scratch test holding its task 21 s after the bytes saw the same: at 21.0 s, the part deleted. With a 600 s
    idle, nothing ended the fetch.
  - The fix: StreamFetch's `idleTimeout` (internal, 20 s, set before start), and the test holds its fetch open
    for 600. Its wait now asserts the 4000 bytes, and that nothing ended the fetch before the skip.
  - On the phone, nothing changes: 20 s without a byte still ends a stream as a network failure.
- **70cbef6's `guard engine.isRunning` in played(), re-checked: sound.**
  - Every stop the engine makes resets first (or comes with nothing scheduled), and every way on from iOS's stop
    resets the lanes, so nothing waits on the completions it ignores.
  - `callbacksHandled` counts them before the generation guard.
  - Taking the guard out still fails aCallGoesOnFromWhereTheSongWas.

**Mutations**, each restored byte for byte, and all four fail:
- the reading's latency put back to the one read before (aNewRouteBeforeAnyCompletion…);
- the completion holding the engine (anEngineLetGo…);
- the render helper's sleep put back (aNextSongNotYetOnANodeIsLetGoWithItsCompletionsLate: A broken at 9134, C
  not straight after it);
- the stop guard taken out (aCallGoes…).

**After.** All 509 tests (Core 452, Audio 57) passed:
- one process, 7 hogs: 15 of 15;
- the real package (two bundles), 7 hogs: 15 of 15;
- the Audio suites alone, 7 hogs: 15 of 15;
- the package with no load.

With the fetch's idle timeout too (the final code), all 509 passed again:
- one process, 7 hogs: 15 of 15;
- the Audio suites alone, 7 hogs: 15 of 15;
- one process with the strict pool, 7 hogs: 6 of 6, where it had failed in 4 of 6;
- the real package and the one process, each once with no load.

**After the two reviews.** Two adversarial reviews of abf5587 (one on the race, one on the phone) ran their own
load here: 20 of 20 runs passed in one process, in the real package and in the Audio suites alone, under 5 hogs
each. Their findings, all four accepted:

- **A lane run dry, its last completion still to come, was counted straight on (an engine race; it can happen
  on the phone).**
  - AVAudioPlayerNode's clock runs on through the silence once it has played all on it, and a buffer put on it
    then plays after the silence. The engine counted it straight after the last (`nodeFrames`, the lane's
    timeline): the position, the frame a pause, a call or a new route goes on from, and the moment the next
    lane starts were all ahead of the ear by the silence, for the rest of the lane.
  - Two ways in. A stream behind whose retry (every 50 ms) finds the bytes before the lane's last completion is
    handled. Or every completion held longer than what is scheduled ahead (2 s on the phone, 0.3 s in the
    tests), when the first one's pump tops up a node that has run out. Only the designed order was right: the
    last completion first, which starts the lane again from the frame it reached (played()'s ran-dry path).
  - Made certain with `completionLag` and `GatedFrames` (a decoded song whose frames past N haven't come, in
    RenderHelpers.swift). Without the fix: the late last completion put the position at 34112 where 33600 was
    heard, and a pause and play skipped the 512 frames; the stall, 48000 where 24000 was heard; and a 96 kHz
    song after a 48 kHz one run dry started 4800 frames early, over the first song's end.
  - A listener would hear it only after a stall: a pause, a call or a new route skipping the silence's length
    of the song, and the next song in another format starting over the end of this one.
  - The fix: schedule() holds the buffer (`Wait.ranOut`; "entry N held: its lane's node has played all on it"
    in the trace) while the lane's node has played all on it by its own clock and a completion is still to
    come. (The clock was the wrong thing to ask: it is not exact, and on a real output it reads "played all"
    with frames still to play. Since fix/engine-hold the hold is told by AVAudioEngine's callbacks - see "The
    hold on the callbacks".) That completion starts the lane again from the frame it reached, the path that was there. The check
    comes after the earlier-songs one, so that wait is still said as it was ("parked").
  - The tests, in RanDryTests.swift: aLaneThatRunsDryMidSongGoesOnFromTheFrameItReached (the designed order),
    aLaneRunDryWhoseLastCompletionIsLateGoesOnFromTheFrameHeard (lag 0.25 s), aStallLongerThanWhatIsAheadGoes…
    (lag 1 s) and aSongInAnotherFormatStartsWhereALaneRunDryReallyEnds. Each wants the song bit-exact from the
    frame heard, the position that frame, and a pause and play bit-exact from it; the last wants the first
    song's second half alone to its very end. The last three fail without the fix.
  - Left as it was: a lane's converter (a song whose rate isn't the output's) keeps its last frames until the
    lane's last completion, and they go on then (`flush`), after a node that has run out by then. Not tested.
    (They are 12-13 ms, not "under 1 ms" as this said; fix/engine-hold counts them where they play - "The hold
    on the callbacks".)
- **A lane started with nothing on it (an engine fault, found by the first new test).** `ready()` let a lane
  start once `startSeconds` were scheduled - the tests' 0 - so the lane begun again after running dry started
  empty: its clock ran ahead of what then went on it, the phase said playing over silence, and the position
  ran on. It now also wants something on the lane. On the phone (`startSeconds` 1 s) only a lane begun again
  whose song then had no more frames could have started empty.
- **The aJoin diagnostics (review 1).** The trace lines above (the output stopped, configuration changes,
  silence rendered because the output is stopped). Review 1 also read CI's log: the "silence after the last
  song" check passed, so the render was silent throughout (corrected above).
- **A fetch held off by a busy process (review 2; on the phone in principle).**
  - StreamFetch's URLSession delegate queue was an `OperationQueue()` at the default QoS. With every core busy
    at the default QoS its work waits until that stops: a scratch program fetching 1000 bytes from the tests'
    stub while 16 `.medium` tasks spun for 6 s saw the old StreamFetch finish after 5.684, 5.685 and 5.685 s,
    and the new one after 0.006, 0.005 and 0.006 s. A second probe, from a default-QoS thread under the same
    load: an `OperationQueue()` operation and a `DispatchQueue.global()` block waited 3.687 s of a 4 s spell,
    `.userInitiated` queues and AVAudioPlayerNode's completion queue (which runs at userInitiated) 0 ms.
  - The fix: the queue runs at `.userInitiated`, the engine's own QoS. On the phone this needed the app to
    keep every core busy at the default QoS for longer than what is buffered: heard as the song stopping to
    load.
  - The tests: in 2 of the review's 17 runs of its own one-process package under hogs, every fetch test that waits
    for its fetch failed at once, unfinished when the helper's 10 s timeout fired. In the second, the review's
    probe saw a cooperative-pool task held 12.5 s (the stub's answers seem to need a free thread of it, as the
    helper's comment says). In ios.yml's second failing run they passed after 12 s. The helper's bound is now a
    minute and its timeout runs at `.userInitiated`; the skipped fetch waits up to 60 s for its 4000 bytes.
- **aRouteChangeThatPausesWinsOverPlayingOn passed without the race decided (review 2).** It slept 0.4 s past
  a 0.2 s settle and checked the phase; a test held off past the settle passed whichever way it went. The
  change now waits 5 s, the test `#require`s the restart waiting (`restartWaiting`) before the pause, then
  expects it let go, the phase paused, the output stopped and the position held.
- **theQueuesEndIsHeardBeforeTheOutputStops slept 0.1 s and expected the output still running**: a test held
  off longer than the 0.6 s linger would have failed. It now waits for the stop and compares the engine's own
  times of the end and the stop (`endedAt`, `outputStoppedAt`): at least 0.599 s apart.
- **Not changed.** `completionsHandled`'s and `waitFor`'s 5 s bounds: the completions come on
  AVAudioPlayerNode's queue at userInitiated and the engine's queue is userInitiated, which the default-QoS
  load that held the fetch didn't hold (0 ms above). ios.yml still runs the whole package together.

**Mutations** on the final code, each restored byte for byte, all failing:
- the `ranOut` hold taken out (the late last completion, the stall, the next song in another format);
- `ready()` without "something on the lane" (aLaneThatRunsDryMidSong…: the phase playing over silence);
- the pause no longer letting a waiting restart go (aRouteChange…: `restartWaiting` still true);
- the end's linger taken out (theQueuesEnd…: 0 s between the end and the stop);
- the first round's four again: the reading's latency, the completion holding the engine, the helper's sleep,
  the stop guard.

**After the reviews' fixes.** All 513 tests (Core 452, Audio 61) passed:
- one process, 5 hogs: 15 of 15;
- the real package (two bundles), 5 hogs: 15 of 15;
- the Audio suites alone, 5 hogs: 15 of 15;
- one process, 7 hogs: 10 of 10;
- one process with the strict pool, 7 hogs: 6 of 6;
- the real package and the one process, each with no load.
The iOS sims and tests/test_source_bytes.py and tests/test_ios_contract.py pass. Swift 6.3, CI's, wasn't run
here: ios.yml is its first run of this code.

### A node's buffers, taken late (the CI cause, fix/engine-hold)

ios.yml's macOS job failed again at 307384f: theQueuesEndIsHeardBeforeTheOutputStops waited out
completionsHandled's 5 s with one completion due and none called back. An investigation and a challenge of it
(both on this Mac, raw AVAudioPlayerNode and the engine) agree on the cause, and it is also 70cbef6's "not
reproduced" aJoinIsTheTwoSongsLaidEndToEnd above.

**What was found.**
- **AVAudioPlayerNode performs scheduleBuffer asynchronously**, on a serial dispatch queue of its own: a sample
  of a soak run shows `AVAudioPlayerNodeImpl::BufferCommand::Perform` on a GCD worker in a per-node queue named
  CommandQueue, handing the slice to the audio unit, and `StopImpl` doing `dispatch_sync` onto the same queue.
  It is so for a node attached while the engine runs (attached before the first start: 0 of 300 late), and
  every lane is one: laneFor runs in pump, after the output has started - on the phone too. play() takes
  effect at once.
- **A render begun before that block has run plays the buffer a render (or more) late**, while the node's
  clock (`playerTime`) counts it as on time; the `.dataRendered` completion follows the audio, not the clock.
  A raw node scheduled, played and rendered at once: 165 of 200 late here, the first sound at frame 2400 or
  4800 while the clock read 7200 after 7200 rendered; with 2 ms before the render, 0 of 200. Nothing tried is a
  fence: reading isPlaying, playerTime or volume, prepare, a zero-frame render, a zero-length buffer.
- **The window is however long GCD takes to run that block**: microseconds on this idle Mac, which is why it
  never failed here; on ios.yml's loaded 3-vCPU runner, completions have been seen more than 10 ms late. Apple
  documents only that a buffer with no time, on a playing node, "plays in the very near future". Measured since
  (fix/ci-settle, below): a fresh engine's node takes its first buffer 0.26 ms after the call at the median and
  under 0.4 ms at worst in 150 trials here, idle; over many runs its worst was 7 ms with CPU hogs, 10 ms under
  `taskpolicy -b` and 16 ms under both.
- **Emulated, it is CI's failures to the digit.** Each scheduleBuffer performed 0.5 ms late (`scheduleLag`,
  below): theQueuesEnd's shape stuck 40 of 40 with CI's numbers (one due, ends [4800, 9600], the clock at
  4800, nothing called back); 37 of EngineRenderTests' 53 failed, aJoinIsTheTwoSongsLaidEndToEnd with 70cbef6's
  signature (first difference at frame 4096, 0.45767212 and 0.45776367, silent throughout with the
  silence-after check passing), and aNextSongNotYetOnANodeIsLetGo's "C not straight after A" fits it too.

**What changed.**
- **Offline only, the engine waits for the node's queue before it renders**: renderOffline sleeps until
  `offlineScheduleSettle` after the last buffer put on a node or node started (`lastScheduledAt`, stamped in
  enqueue, in playFromSilence and at the next lane's start). The live path is untouched: the phone's output paces
  its renders. It was 10 ms, not the 2 ms first proposed (the runner has shown GCD stalls past 10 ms, and the 2 ms
  settle failed 40 of 40 at a 3 ms lag); it was 30 ms from the third commit: the verifiers measured 10 ms covering
  only about 5 ms of a node's queue held off - each emulated lag is due at enqueue plus the lag, so the render
  waits the settle less the lag, and what ate 2-5 ms of what was left was put down to AVAudioPlayerNode's own
  queue and the thread wake-ups. **That was wrong**: it was the hook's own Thread.sleep running late (by up to
  half its interval, here); the node's queue takes well under a millisecond (fix/ci-settle, below). At an 8 ms lag
  the 10 ms settle failed every run (8-12 tests, 7 of 40 for theQueuesEnd alone), at 15 ms 53 of 83; 5 ms passed 4
  of 4, 2 ms 8 of 8. 30 ms cost about 7 s on the Audio suite here (29.2 s at 10 ms, 36.7 s at 30 ms). **It is 100
  ms since fix/ci-settle**, waited on a strict timer (below). It is a bound, not a fence (there is none: see "What
  was found").
- **`scheduleLag`, a tests-only hook beside `completionLag`**: each scheduleBuffer performed that long later, in
  order, on a queue of the engine's, drained before any node or engine stops (as StopImpl does), and skipped for a
  node detached meanwhile (timed on a strict timer since fix/ci-settle; a Thread.sleep before).
  `DEADWAX_TEST_SCHEDULE_LAG` sets it on every engine the tests make (`offlineEngine`, `liveEngine`), and ios.yml
  runs the Audio tests a second time with it - at 0.0005 s in the first commit, which a settle cut back to 2 ms
  would most likely still have passed (it held the paths stamped, not the bound); at **0.010 s** since the third
  commit, which the old 10 ms settle fails across the suite and the 30 ms one passed here "with 20 ms to spare" -
  which the runner showed it didn't have (below).
- **completionsHandled says which it is**: with every callback AVAudioEngine made handled, "the node's clock
  has passed a buffer it hasn't called back: AVAudioPlayerNode took the buffer late"; otherwise both counts; and
  each lane's buffers scheduled and called back, its ends, frames and clock (`lanesSaid`).

**What the tests hold** (BuffersTakenLateTests.swift): aJoinWithItsBuffersTakenLateIsStillTheTwoSongsEndToEnd
(CI's aJoin with every buffer 0.5 ms late: the two songs end to end, bit-exact, silence after) and
theQueuesEndWithItsBuffersTakenLateIsHeard (CI's theQueuesEnd: the song whole and on time, the queue's end);
since fix/ci-settle's second commit, aJoinWhoseFirstCallTheHookHoldsUpPastTheSettleIsStillTheTwoSongsEndToEnd too
(the verifier's finding 1, below). With the settle taken out both fail, and the helper's message names
AVAudioPlayerNode; the whole Audio suite at
`DEADWAX_TEST_SCHEDULE_LAG=0.0005` without the settle fails 49 of its 79, and passes with it. (Since the third
commit: at 0.010 with the settle back at 10 ms - see "The verifiers' findings". At fix/ci-settle, the settle set
to 0: both fail, the second naming AVAudioPlayerNode, and the Audio suite at 0.010 fails 65 of its 87, 37 of them
naming it.)

**What only the phone can tell.** Not "never", as first written: a start from silence on an output just
started is the start lead ahead (milliseconds), and a node's CommandQueue later than that would start the song
that late after a moment of silence, the count ahead by it. Top-ups go on 2 s ahead and the next lane is
scheduled seconds ahead, so they aren't exposed. Nothing here has run on an iPhone or on macOS 26. And one
found offline since (fix/ci-settle, below): scheduleBuffer CALLED on one thread while a render runs on
another blocks the caller - 5-6 ms in 1 of 50 trials here, 5-164 ms in 38 of 50 under `taskpolicy -b`, the
shape of a timed wait the system coalesces. The engine's own calls never meet it offline - they are made on the
queue its renders are; the tests' late-buffer hook's call, made off it, did once (184 ms, the verifier's finding 1,
below), and renderOffline now waits for one. The phone's engine queue calls scheduleBuffer while the IO thread
renders all the time. Whether a live render has the same wait, and what a backgrounded app's coalesced timers
would make of it (the queue held, a start late), only the phone can say.

**ios.yml's runner at 09781a5: 12 of 87, and the settle at 100 ms (fix/ci-settle).** The plain run passed
(87 of 87 Audio, 511 Core); the second run, every buffer 10 ms late, failed 12 of 87 - 30 ms of settle less a
10 ms lag left 20 ms, and something on the runner took more. Seven failed in completionsHandled with
"AVAudioPlayerNode took the buffer late"; the other five on what they heard, each the shape of a buffer taken
late: RanDryTests.swift:73 and :112 (the song not going on from the frame heard), HoldOnTheCallbacksTests.swift:423
and :438 (C nowhere after B) and StartsAtASampleTimeTests.swift:79 (C at 52800, a render after B's end). On this
Mac the same run passed 3 of 3, 7 CPU hogs included.
- **What was found: timer coalescing, not the node's queue.** Every ordinary wait in the test process - a
  Thread.sleep, usleep, mach_wait_until, a semaphore's timeout - is let run late here by half its interval, up to
  10 ms (a 10 ms sleep woke 10.2-15 ms after it began, 30 and 100 ms ones up to 10 ms late); under `taskpolicy -b`
  (the process run as background) a 10 ms sleep woke 17-210 ms after (up to about 240 ms over the verifier's
  runs). A strict dispatch timer with no leeway woke within about 0.1-0.6 ms idle here - but not under load: with 7
  CPU hogs, 622 of 1,401 of the hook's wakes were over 1 ms late, 104 over 5 ms, and up to 12 ms over many runs;
  under -b up to 17 ms (the settle's own wait 87 and 119 ms late once each, where late is harmless). The hook
  (scheduleLag) and the settle (renderOffline) both waited on Thread.sleep: so at a 10 ms lag the hook's buffer
  reached the node 10-15 ms after it was asked for, here - the "2-5 ms" the third commit put down to the node's
  queue - and on a machine that coalesces harder, past 30 ms. The node's own queue was never the slow part: 0.26 ms at the median,
  under 0.4 ms at worst idle, and over many runs 7 ms at worst with hogs, 10 ms under -b (BufferTakeMeasuredTests,
  below) - against the hook's 10 ms sleep, which took up to about 240 ms under -b.
- **Reproduced, under `taskpolicy -b`** (the CI's 12 run alone, each run once unless said): at 09781a5 the plain
  run passed 12 of 12 and the lagged run failed 8 of 12 with the CI's message - the runner's pattern (6-9 of 12
  over four runs, the verifier's included). With both waits on a strict timer the lagged run passed 12 of 12 at a
  30 ms settle and 12 of 12 twice at 100 ms; with the settle at 100 ms but the hook back on Thread.sleep it failed
  9 of 12. First written here as "the strict timer is the fix; the 100 ms is margin" - which overstated it (the
  verifier's finding 3, below): the strict timer takes out what the hook's own wait added, but under load the
  strict timer runs late too, and the margin is what carries it. **And -b is not the runner**: under -b
  playAfterAPauseWaitsForThisRunsFirstRender fails in most runs - all 7 of the verifier's full ones, 09781a5's
  plain run included, and 1 of 2 at the second commit (the engine's wait for this run's first render looks every
  2 ms on an ordinary GCD timer; three looks run past its 100 ms bound and it starts at a host time) - while the
  runner passed it in both of its runs at 09781a5; and CPU hogs alone (7 or 16, 5 runs) never failed 09781a5's
  lagged run here at all. So -b is harsher than the runner, coalescing is the likeliest cause there but not a seen
  one, and the runner's own measured line (below) is what will say.
- **What changed.** `PlaybackEngine.waitStrictly(until:)` (`sleep(until:)` in the first commit, renamed: the
  engine's own `sleep()` stops the phone's output): the calling thread held until a host time on a strict
  DispatchSource timer (leeway 0), never before it - used only by renderOffline's settle and the scheduleLag
  hook (the phone's path is untouched). `offlineScheduleSettle` is **100 ms**: before, the plain run's wait was
  30 ms plus whatever the machine's coalescing added, so the margin a runner had was never known; now it is
  the settle itself, 100 ms over the node's queue and 90 ms over ios.yml's 10 ms hook. The cost: the Audio
  suite took 38.3 s at 30 ms (as at 09781a5), 60.4 s at 100 ms on the strict timer, 61.8 s at 100 ms on
  Thread.sleep - so the strict timer saves 1.3 s here, and on a machine that coalesces harder, up to as much
  again as the wait. Not done, though considered: skipping the wait when no render could reach the new buffer
  (one put on behind a second already taken) - knowing what a node has taken means reading its clock, which is
  what a buffer taken late makes wrong (the hold's finding 1), so it could let a render reach a buffer the node
  hasn't taken; and skipping it for a render while the output is stopped - sound, but such renders are rare.
- **The measurement, `howLateANodeTakesABufferIsMeasured`** (BufferTakeMeasuredTests.swift, one of
  EngineRenderTests so it runs alone): about a second, printing one line and asserting nothing - a measurement
  that can fail would be one more flaky test on the very machine it is for. ios.yml's two macOS runs each print
  it; find it in the log by "AVAudioPlayerNode taking a buffer, measured". Its parts, each as trials, min /
  median / p90 / p99 / max in ms, and the share over some limits:
  - **asked at once**: 150 trials, a fresh offline engine each, a node attached while it runs (as every lane
    is), a buffer scheduled and played at once, then rendered 64 frames at a time (0.2 ms apart, on the strict
    timer) until the output carries it - the time from the call to that render. What the plain run's settle
    must cover; its share over the settle (100 ms) should be 0.0%. A fresh engine is the worse case (median
    0.26 ms here; 0.00 for a node on an engine long running).
  - **behind a 10 ms scheduleLag hook**: 50 trials as the hook does it, the time from its due time to the first
    render carrying the buffer, rendering only once the hook's call has returned (as in the engine, whose
    render comes the settle after, and waits for a call still under way then) - what the lagged run's settle
    less the lag (90 ms) must cover. Then **the hook's own block past its due time**: how late the strict timer
    runs on that machine; and **the hook's call into the node, how long it took** (since the second commit):
    how often that call itself blocks - 184 ms once under -b, which the engine now waits out (finding 1, below).
  - **never taken within 500 ms**: a count; anything but 0 is a node that never took its buffer.
  - **a 10 ms Thread.sleep past its time**: how hard that machine coalesces timers - what made 30 ms fail.
  If "asked at once" and "behind the hook" stay within a few ms over several runs, the settle could come down
  (each 10 ms off is about 3 s off the suite here); any share over the settle is a machine the settle doesn't
  cover. Measured by the verifier, idle, over 10 runs: asked at once median 0.25-0.26 / max 0.27-0.35 ms; behind
  the hook max 0.17-0.65 ms; the hook's block max 0.13-0.55 ms; a 10 ms Thread.sleep 1.8-2.5 ms late at the
  median. With 5-7 CPU hogs, about 40 runs: at once max up to 7 ms, behind the hook max up to 19.3 ms, the hook's
  block up to 12 ms, a Thread.sleep up to 10 ms. Under `taskpolicy -b`, about 20 runs: at once max 0.5-10.2 ms
  (16.3 ms with hogs too), behind the hook max up to 17.7 ms, a 10 ms Thread.sleep 33-188 ms late at the median
  and up to 228 ms. At the 100 ms settle every share over it was 0.0%; at a 30 ms one, a 20 ms lag and 7 hogs,
  2.0% of one run's trials passed the 10 ms left - the setting that failed 1 run of 2.
- **One the longer settle brought out: the hold tests' bytes before AVAudioEngine's callbacks.** The settle is
  waited inside the engine's queue, so whatever falls due meanwhile runs the moment the render ends - and at 100
  ms the stream's retry (every 50 ms) always has. With 5 CPU hogs,
  aSongInAnotherFormatStartsWhereALaneRunDryReallyEnds failed once: the retry read A's last bytes the instant the
  render ended, before AVAudioEngine (on its own thread, at no set time) had called back A's buffers, so `ranOut`
  couldn't say A had run out and the bytes went straight on - no "entry 0 held", B over A's end. The engine did as
  built (it goes by the callbacks, never the clock); the test had taken the callbacks for granted, and at 30 ms
  the next retry had come about 20 ms after the render. Seven tests in six places let bytes come to a lane run
  dry, its completions handled late, and look for them held:
  aLaneRunDryWhoseLastCompletionIsLateGoesOnFromTheFrameHeard,
  aSongInAnotherFormatStartsWhereALaneRunDryReallyEnds, aRaceOnThePhonesBufferingIsHeldThenGoesOnExactly,
  aResampledLaneBegunAgainCountsFromTheFrameItGaveOut (its 0.25 s half),
  aConverterTailAfterTheNodeRanOutIsCountedWhereItPlays and anotherFormatLate's two with completionLag. They now
  wait for those callbacks first (`runOutCalledBack`, bounded and required), as their comments assumed ("every
  callback arrives"); anotherFormatLate's callbackLag variant doesn't, its callbacks held off on purpose. Not
  changed: that a phone's callbacks can come after a stream's bytes the same way (the hold review accepted that
  race, with the clock's 0.25 s backstop).
- **The verifier's findings on 1490ad7, and fix/ci-settle's second commit.** A verifier ran the Audio suite on
  1490ad7, on 1490ad7 with the settle back at 30 ms and on 09781a5, idle, with 7 and 16 CPU hogs, at lags of 0.010,
  0.020 and 0.040, and under `taskpolicy -b` (about 60 runs), and an instrumented copy timing every hook call
  (2,933 of them). The tip passed every hog run (15); at 30 ms a 20 ms lag with 7 hogs failed 1 of 2. All six
  findings held:
  - **1 (medium-low): the hook's own call into the node could be held up past the settle, which the engine's
    call can't.** Under -b, alone, aJoinWithItsBuffersTakenLateIsStillTheTwoSongsEndToEnd failed 1 run of 8 ("the
    render is silent throughout"): the hook's first `scheduleBuffer` blocked for 183.98 ms, from 0.1 ms after its
    due time - about 100 ms before the render - into the render, and the buffers queued behind it on the hook's
    serial queue reached the node only after. The engine makes its own call on its queue, which renderOffline
    waits for (`queue.sync`), and stamps the settle after the call returns, so no buffer is missed that way; the
    hook's call is made off it. **Fixed**: the hook counts its blocks by due time and says when one is inside its
    call (`HookCalls`); when the settle ends with one under way, renderOffline waits for it and every block due by
    then (at most 5 s, then it renders anyway and says so), then the settle again - what the engine's own queue
    would have done. A block still waiting on its own timer is left alone: that is the late take the hook is
    there to make. Held by aJoinWhoseFirstCallTheHookHoldsUpPastTheSettleIsStillTheTwoSongsEndToEnd: the hook's
    first call held 150 ms inside the call (`scheduleCallHeld`, tests only), the join bit-exact and the trace
    saying it waited; with the wait taken out it fails 3 of 3, silent throughout - the -b failure's signature.
    And the measured line prints the hook call's own duration.
  - **2 (low): -b over-emulates the runner** - above, "And -b is not the runner". Noted here and in ios.yml.
  - **3 (low): single runs stated as bounds** - the node's "1.3 ms at worst, -b included" and the strict timer's
    "within about 0.1 ms (7 ms once in a few hundred)": both corrected above to the ranges of many runs, and "the
    strict timer is the fix; the 100 ms is margin" to what they show, that under load the margin carries it.
  - **4 (low): "every one in completionsHandled"** - seven were; the other five on what they heard. Corrected
    above, and "8 of 12" under -b to 6-9.
  - **5 (nit): two `sleep`s on one type** - the static `sleep(until:)` beside the engine's own `sleep()`, which
    stops the phone's output: renamed `waitStrictly(until:)`.
  - **6 (nit, reasoned): runOutCalledBack's timeout couldn't point at a late take** - a buffer taken late has
    its clock passed while its callback can't come before the next render, which that wait never makes. Its
    message now says so, in completionsHandled's words (`takenLate`, shared).
  Verified at the second commit, on this Mac: the whole package twice (511 Core, 89 Audio - the 88 and finding
  1's test); the Audio suite at `DEADWAX_TEST_SCHEDULE_LAG=0.010` 4 of 4, with 5 hogs 2 of 2 and with 7 hogs 1 of
  1; under -b, the BuffersTakenLate three alone 10 of 10, CI's 12 at 0.010 2 of 2, the Audio suite at 0.010 1 of 1
  and plain 1 of 2 (playAfterAPauseWaitsForThisRunsFirstRender, finding 2). The wait taken out: finding 1's test
  fails 3 of 3, the other two pass. The settle at 0: all three fail 3 of 3, theQueuesEnd naming
  AVAudioPlayerNode. The measured line's new part, here: the hook's call 0.00-0.04 ms, -b included. Not seen: the
  184 ms call again - 1 in about 2,900 under -b, so 10 clean runs of the three say little; finding 1's test is
  what holds the fix.

### The hold on the callbacks (fix/engine-hold)

98a9d9e's hold ("A lane run dry, its last completion still to come", above) was reviewed through three lenses,
each finding judged by a skeptic; three designs followed, and two judges. All eleven findings were real. The
root of the worst: **the node's clock is not exact**, and the hold read it as if it were.

**What was found.**
- **1, the clock.** 98a9d9e held a buffer while the node's clock said it had played all on it
  (`playerTime >= nodeFrames`). On a real output a node started with play(at:) a host time counts from the
  time asked while its first sample lands on a render's edge: its clock ran 245-651 frames ahead of its
  samples on this Mac's output, and read "played all" with frames still to come. Bytes found then (a stream
  catching up) were held, and a join that was seamless became a rebuffer: 21.7 ms of silence on this Mac's
  output, 0.5 s and more on the phone's settings. A buffer taken late (above) puts the clock ahead the same way.
- **3 and 6, a converter lane's count.** A lane converting (a 44.1 or 96 kHz song on the 48 kHz output) begun
  again after running dry counted from what went INTO its converter, but the converter holds the last 576 song
  frames at 44.1 kHz and 1152 at 96 kHz (about 627 and 576 of the output's, 12-13 ms), and those play first.
  The position, and every pause, call or new route after, was that far ahead: a pause skipped 576 frames
  (1516 with the completion late). The notes said "under a millisecond" (corrected above).
- **4 and 10, a converter's tail.** A converter lane whose stream ran dry at the song's very last frame, its
  end said only after, had only its converter's tail left: 98a9d9e never started it again (nothing counted on
  it), silent for good, the queue never ending. `ready()` counted frames on the timeline, not on the node.
- **2 and 11, nothing left.** The same at the output's rate (no converter): nothing of the song anywhere.
  70cbef6 played silence saying playing; 98a9d9e said loading; both for good with the output running. A seek or
  a resume at a song's very end did the same.
- **5, another format started in the past.** A song in another format whose bytes came after the heard lane
  had played all on it was started at that lane's end, a time the render had passed: a node played at a time
  past counts from it, so its count ran ahead by the silence and the song after it started early, over its
  end (B's position 25024 for 24000, C at 23488).
- **7 and 9, the lead.** The start lead (output latency and an IO buffer: about 0.2 s on AirPods; for AirPlay,
  whatever its route reports - the 2 s once written here was never measured) was taken on every start from
  silence - a lane begun again after running dry, a skip, a seek while playing - on an output that was already
  live: silence before the song, as much of the lead as the render's timestamps don't already run ahead (this
  Mac's own lead saved nothing; a 0.2 s one did - the verifiers' ninth finding, "The verifiers' findings").
- **8, the race.** Bytes read after AVAudioEngine has called the lane's last buffer back and before the engine
  has handled it. With 98a9d9e's clock they were held; laid on the node that had run out (70cbef6) they played
  after the silence, counted straight on.

**What changed** (PlaybackEngine.swift).
- **`ranOut` is told by the callbacks.** Each lane counts the buffers put on its node since it began
  (`scheduled`) and the callbacks AVAudioEngine makes of them, on its own thread (`Calls`), for that beginning
  only: an epoch bumped at each `clear`, since a stop lets every buffer go and their callbacks come later and
  mustn't count for what goes on next. Played all = every one called back, its completion not yet handled.
  One backstop reads the clock, past any error it has: 0.25 s past all on the node (`ranOutBackstopSeconds`),
  for AVAudioEngine's completion thread held off longer than what is ahead, whose callbacks then come in a
  burst and the first one handled pumps before the rest are counted.
- **A lane begun again counts its converter's frames** (`converterHolds`): it begins at the frame they start
  at, and they are counted on its timeline.
- **A converter lane run dry with only its tail left** (played()'s tail path) begins again with those frames,
  counted from where they begin, flushed onto its node; `ready()` wants something on the NODE (`nodeFrames`).
- **`moveOnFromNothingLeft`**: with nothing of the song `current` names on a node, in a converter or counted,
  its decode over, and no lane playing, the queue goes on to the first song scheduled, the one decoding, or
  ends (`endIfNothingLeft`, pump's end factored out).
- **The next lane never starts at an end already rendered**: not while the heard lane has run out
  (`!ranOut(heard)`), and not at an end the render has passed (offline the render's count, live the node's
  clock short of its end). It starts from silence once the heard lane's completions are handled.
- **The lead only on an output just started** (`outputFresh`, set by ensureRunning's start, cleared by the
  first start from silence and by sleep): play after a pause and a new route take it.
- **The race goes the designed way**: its bytes are held ("entry N held"), and that completion begins the
  lane again from the frame it reached once `startSeconds` are buffered, as after any run dry.

**Where the judges differed, and what was taken.**
- **Not taken: beginning the lane again at once with the bytes held** (one judge's `parkedWhole`). On the
  phone the completion is queued right behind the retry, so the race's window is microseconds; and a stream
  that has just run dry may still be slow, so starting with what little was held risks a scrap of sound and a
  second gap where the wait gives one. Every restart waits for `startSeconds`.
- **Kept: `!ranOut(heard)` at the next lane's start**, which the other judge found redundant. Offline it is
  (its mutation survives: the end guard sees it), but live every callback can be in while the node's
  `lastRenderTime` is not yet past the end, and the next lane would start in the past. (Held by a test since the
  third commit: `joinRenderBehind` reads the render time behind the end - see "The verifiers' findings".)
- **Not taken**: a pool of spare nodes, settling run-outs before a start, a position-aware settle, a race
  bound in seconds - each more machinery than the finding needs.

**What the tests hold** (HoldOnTheCallbacksTests.swift, each a review's or a judge's probe with its prints made
expectations, each failing without its change - see the mutations):
- bytesFoundWhileTheNodeStillPlaysGoStraightOnWhateverItsClockSays (1): `clockAhead` starts the node 600
  frames in the past, its clock that far ahead; the bytes go straight on, nothing held, bit-exact.
- aRaceOnThePhonesBufferingIsHeldThenGoesOnExactly (8): `phoneLikeEngine` (2 s ahead, 1 s to start), the
  completion 0.25 s late; held, then bit-exact from 48000, a pause and play exact from 57600.
- aBurstOfLateCallbacksAfterAStallGoesOnFromTheFrameHeard: AVAudioEngine's callbacks 1 s late (`callbackLag`),
  then a burst; the backstop holds, on from 14400.
- lateCallbacksOfBuffersLetGoDontCountForTheNext: three seeks with the let-go callbacks 0.15 s late; nothing
  held, nothing run dry (the epoch).
- aResampledLaneBegunAgainCountsFromTheFrameItGaveOut (3, 6): 44.1 and 96 kHz, both orders, the position within
  1.5 song frames of the ear and a pause exact.
- aResampledSongsLastFramesAfterARunDryArePlayedAndTheQueueEnds, …ThenTheNextSongStraightAfter,
  aConverterTailAfterTheNodeRanOutIsCountedWhereItPlays (4, 10).
- aLaneBegunAgainWithNothingLeftEndsTheQueue, …ThenASongInAnotherFormat,
  aLaneBegunAgainEmptyThenTheSameFormatBehindCountsFromItsOwnStart, aSeekOrAResumeAtASongsVeryEndPlaysTheNext
  (2, 11).
- anotherFormatLateAfterTheLaneRanOutStartsWhereItIsHeard and anotherFormatAfterAnEndAlreadyRenderedWithCallbacksLate
  (5): B from the frame heard, C straight after B's last frame, alone.
- theLeadIsTakenOnlyOnAnOutputJustStarted (7, 9): the lead at the first start, after a pause and on a new route;
  none on a run-dry restart, a skip, a seek.
- RanDryTests' four, unchanged, still pass: the designed order and 98a9d9e's three races.

**Mutations**, each restored byte for byte (sha-256 checked), the Audio tests run through the build lock:
the clock put back as `ranOut` (fails bytesFound…); the hold taken out (7 tests); the backstop out (aBurst…); the
epoch out (lateCallbacks…); `ready()` as 70cbef6 had it (7) and as 98a9d9e had it (2); the converter's frames
uncounted (aResampledLaneBegunAgain…); `moveOnFromNothingLeft` out (3); the old tail flush (aConverterTail…); the
end guards out (anotherFormatAfterAnEndAlreadyRendered…); both join guards out (both anotherFormat… tests); the
lead always taken (theLeadIs…); the settle at 0 (both BuffersTakenLate tests; 49 of 79 at a 0.5 ms lag). The
one that survived is `!ranOut(heard)` alone, offline, as said above (it fails a test of its own since the third
commit).

**What only the phone can tell.**
- That a real output's `.dataRendered` callbacks come after the render that took a buffer's last sample, never
  before it - the hold now rests on that, where it rested on the clock.
- A real stall (the network gone mid-song): one rebuffer of about a second, and the position, a pause and a call
  right after it.
- That the backstop never fires in normal playback (it needs the clock a quarter of a second past all on the
  node with a callback still to come).
- A 44.1 kHz album over a bad connection: a pause after a rebuffer going on from the frame heard.

### Starts at a sample time (fix/engine-hold, its second commit)

The third design's two timing changes, which the judges took apart from the hold, in a commit of their own so it
can be reverted alone if the phone disagrees. (Reverted alone, the first commit's play() at once comes back for
every start on a running output - a skip, a seek, a run-dry restart - two render cycles later than 307384f: a
revert puts a start at the last render + one IO buffer, or 307384f's host-time lead, in its place. Finding 10 in
"The verifiers' findings".)

**What was found** (real output, this Mac, mixer volume 0, print-only probes in scratch copies).
- **A start from silence at a host time counts ahead of its samples.** play(at:) a host time puts the node's
  count at that time while its first sample lands on a render's edge: the count was 245-651 frames (5-14 ms)
  ahead, so the position, and the frame a pause, a call or a new route goes on from, were that far past the ear.
- **A song in another format started at a host time overlapped the one before.** The next lane was started at
  the host time the heard lane's clock said it ends: B's first sample 238-723 frames over A's end, in 8 of 8
  trials. Started at the SAMPLE time of A's end, read as A's start plus what is on it: straight after A's last
  sample in 24 of 24, a node attached before the start or while running, A started at once or at a sample time.
- **A sample-time start lands exactly, its count with it**: the first sample at the time asked, and the node's
  clock origin the time asked (attached before the start or while running, k from 0 to 1536 frames past the
  last render).
- **Just after engine.stop() and start() of the same engine, the render times are left from the last run.**
  A node's `lastRenderTime` read 18944, its host time 505 ms old, until this run's first render 5-12 ms later;
  a node started at that time + 512 played at once, its count 23040 frames (0.48 s) ahead of its samples. And
  the nodes' time runs on across the stop (43520 twenty ms later) while the main mixer's starts from 0 again
  (1024): a start from the mixer's time, which the third design fell back to, would be half a second in the
  past. Once a render of this run is there, a start from the node's own time (+512) and a join at its end
  landed exactly, after a 0.3 s stop and a 0.03 s one, 6 of 6. Offline the render's count runs on across a
  stop (12288 before and after) and is the nodes' time: a node started at count + 1000 sounds at 1000.
- **Found by this commit's own test, there before it: a song in a third format played over the second.** With
  three formats queued and the second shorter than what is scheduled ahead (2 s on the phone), the third was
  decoded while the first was still heard, and every lane waiting started at the first's end: the 96 kHz song
  and the 48 kHz one after it both at 24000, together.

**What changed.**
- **A start from silence is a sample time**: the lane's node's render time plus the start lead on an output just
  started, or plus one IO buffer (`ioBuffer`, AVAudioSession's ioBufferDuration, set by the app beside
  `startLead`; none offline) on one already running, so the start is never in a render under way. The lane's
  count begins there (`Lane.origin`, in place of `renderStart`, which was offline only). Offline the lead is now
  taken too, as the phone takes it. (Since the third commit the lead counts from when the start was asked, on the
  render's own host timeline, not from the render's sample time, which is already ahead of now.)
- **The next lane starts at a sample time**: the heard lane's `origin` plus what is on its node (its clock, when
  it has no origin), and only when that is at least one IO buffer past the render (offline, not behind it);
  otherwise it is said ("not started at N: the render is at M already") and the lane starts from silence once
  the heard lane's completions are handled. `time(whenEnds:)` is gone.
- **A render time is one of this run of the output** (`ofThisRun`): not the reading the node had as the output
  started (`renderAtStart`, read just after engine.start()), not stamped before the start (`outputStartedAt`),
  and the lane's own node's, never the mixer's.
- **With no such render time** (an output just started that hasn't rendered yet) a start from silence is as it
  was: the lead ahead at a host time, or at once, with no origin ("started from silence at a host time: no
  render time yet"). Nothing retries or waits. A node a pause left paused (`idleStopSeconds`) goes on at once,
  with no origin, as before. (Since the third commit it waits for this run's first render, up to 0.1 s, and only
  then falls back - every play after a pause landed here.)
- **Only the lane whose song comes next starts at the heard lane's end**, one at a time; a lane after it waits
  for that one to be heard.
- **The app** (PlayerModel.lead, AudioSessionController.ioBuffer): `engine.ioBuffer` reads
  `ioBufferDuration` on the engine's queue, as `startLead` and `latency` do. This and the starts are the only
  changes to what the phone runs.

**Where this differs from the judges' synthesis**: the main mixer is not a fallback for a node's render time
(the probe above: after a restart it counts from 0 while the nodes run on), and a render time left from before a
stop is refused (it read 505 ms old, and a start there was half a second in the past). The third-format overlap
was not in any finding.

**What the tests hold** (StartsAtASampleTimeTests.swift):
- aStartFromSilenceLandsWhereItsCountSays: a 0.05 s lead offline, silence for 2400 frames then the song bit-exact,
  "started from silence at 2400", the position the frame heard; a pause and play take the lead again and go on
  from 9600, the frame heard.
- aSongInAnotherFormatJoinsAtTheSampleTheHeardLaneEnds: 48 kHz started 2400 in, 96 kHz at 26400 (A whole to its
  last frame, no gap), 48 kHz straight after; then 44.1 kHz (its converter's 24000 frames), 96 kHz at its end,
  and the third format straight after the 96 kHz song, alone.
- startWithNoRenderTimeFallsBack (`noRenderTime`): the song at once, said, and a 96 kHz song after a 22222-frame
  one joined at 22222 by the clock, the queue ending.
- aRenderTimeLeftFromBeforeAStopIsNoTimeToStartAt: `ofThisRun` with the probe's own readings.
- Every earlier test passes unchanged; RanDryTests and HoldOnTheCallbacksTests included.

**Mutations**, each restored byte for byte (sha-256 checked), all nine failing:
- the lead not taken offline (aStartFromSilence…, aSongInAnotherFormatJoins…);
- the lane's count from the render's time, not the time it starts at (the same two: B 2400 frames over A);
- the join read off the heard lane's clock, not its `origin` (anotherFormatPlaysOnItsOwnLaneAfterTheFirst and
  both anotherFormat… tests: a clock needs a render first, so a join planned before the heard node has rendered -
  a short song, a lane begun again - came late or not at all);
- the fallback not playing, and the fallback's join with no clock to read (startWithNoRenderTime…);
- `ofThisRun` without the reading-at-start check, and without the host-time check (aRenderTimeLeft…);
- every waiting lane started at the heard lane's end (aSongInAnotherFormatJoins…: the third format over the
  second);
- the render guard taken out (anotherFormatAfterAnEndAlreadyRenderedWithCallbacksLate).
Not mutated: the margin, which is 0 offline - its one IO buffer is the phone's to show.

**What only the phone can tell.**
- That a sample-time start and join land exactly on the phone's output as on this Mac's: a 44.1 kHz album into a
  96 kHz one, gapless, with no click or overlap at the change; and the position after a start no longer ahead.
- That the phone's render times after a pause and play behave as this Mac's (left from the last run until its
  first render); since the third commit the start waits up to 0.1 s for this run's first, then falls back to the
  host time.
- That one IO buffer past the last render is enough on the phone, the screen locked (larger buffers) included.

### The verifiers' findings (fix/engine-hold, its third commit)

The two commits above (efb8b6a on 307384f) were checked by verifiers: ten findings. Each was reproduced against
the code (real output on this Mac, a 44.1 kHz device, mixer volume 0, probes in a scratch copy; or offline), then
fixed with a test that fails without the fix, or rejected with why. Eight hold and are fixed (one in these notes
alone); two are rejected as code changes.

**1 (high): after a pause and play, every start fell back to the host time.** Held. ensureRunning calls
engine.start() and the start from silence comes straight after it, while the node's `lastRenderTime` is still the
last run's (see "Starts at a sample time"): `ofThisRun` refused it every time, so every play after a pause started
"at a host time: no render time yet", with no origin, its count ahead of its samples, and a song in another format
joined by the clock over the one before. On this Mac's output, A then B (the same rate, another lane): after a
0.3 s pause B overlapped A by 803-851 frames (18-19 ms), after 1.5 s by 515-544 (12 ms), 6 of 6; with no pause
the join was exact (but for a cold first start, below).
- **Fixed: the start waits for a render of this run.** With no render time of this run, playFromSilence says so
  once ("no render of this run of the output yet, waiting for one"), leaves the phase at loading, and asks again
  every 2 ms on the engine's queue (`waitForRender`, generation-checked, cancelled by reset) for up to
  `renderWaitBound()` - 0.1 s, or four IO buffers if that is longer. It then starts at a sample time and says
  "this run's first render after N ms"; past the bound the fallback is as it was ("started from silence at a host
  time: no render of this run in 100 ms"). The lead counts from when the start was first asked (`startAsked`), so
  the wait is inside it, not added to it.
- **Test**: playAfterAPauseWaitsForThisRunsFirstRender. `staleRenderReads` (tests only) makes the offline render
  time read, for its first N reads after the output starts, a reading left from before the stop - 12000 frames
  behind and equal to the reading at the start, as the real one is. Play, pause, play: it waits, then starts at
  14400 (the 0.05 s lead from the ask), 2400 frames of silence then A from 9600 bit-exact, the position the frame
  heard (19200), A whole to 40800 and the 96 kHz song joined at 52800, straight after A's last sample.
  startWithNoRenderTimeFallsBack now expects the wait, then the fallback.
- **On this Mac's output after the fix** (the verifiers' one-stream probe, every lane through one tapped mixer):
  after a 0.3 s and a 1.5 s pause the join was exact (gap 0) 6 of 6, A going on from the very frame it paused at,
  its first sample at its origin; the start waited 3.1-21.2 ms for the run's first render (in one of the six it
  was there already). With a 0.2 s lead, the first frame was presented 202.0-202.5 ms after play (finding 8's
  fix) and after a pause 213.6-216.3 ms after resume was called: the lead counts from the start asked, after
  engine.start() has returned, as 307384f's play(at:) did. (The verifiers' other device probe, a tap on each
  node, reads a gap of 17-19 thousand frames across a pause both before this commit and after: its taps are
  not contiguous across the stop, so it doesn't measure the join; the one-stream probe does.)

**2 (medium): the test of a render time left from before a stop held only the pure rule.**
aRenderTimeLeftFromBeforeAStopIsNoTimeToStartAt called `ofThisRun` with the probe's readings; nothing held that
the engine asks it, and offline the render time never went through it (offline it was always fresh). Held.
- **Fixed**: the offline render time goes through `ofThisRun` as the live one does, and `staleRenderReads` gives
  it a stale reading to refuse (finding 1's test). `renderTime` returns the sample and its host time
  (`RenderTime`), for finding 8.

**3 (low): a resampled song's last 13 ms were cut off after a dropout, when the next song in the same format was
late.** Held, offline (live engine, 0.3 s ahead, and the phone's buffering): a 44.1 kHz song's stream on time to its
end, the next song's late. Its converter keeps the song's last 576 frames (627 of the output's) until it is
flushed, and a song in the same format coming next leaves them in it; the node played out what was on it, ran dry,
and those frames came after the run-dry restart: A silent at 23373-23552, then its last 627 frames as a scrap, then
silence until B. Not the hold's finding 4 (a tail found after the node had run out): here the converter still had
it while the node played.
- **Fixed: `flushBeforeRunningOut`**, called where pump finds the next song's bytes not there yet (`.waiting`):
  with the tail lane's song decoded to its end (no entry open on the feed), its converter holding frames, the node
  not run out, and what is left on it within the retry interval, two IO buffers and 20 ms, the converter's last
  frames are flushed onto the node, said ("about to play out all on it, the next song not here: its converter's
  last frames on now"). The song ends whole, on time. The cost: a next song that comes in that last stretch, the
  node still playing, is still laid end to end on it, but through a fresh converter - as after a rebuffer or a
  change of format - not one resample across the join. Without the flush that song joined through the one
  converter, but a song later than that got the scrap. Assumed inaudible; a phone check.
- **Test**: aResampledSongsEndIsHeardOnTimeWhenTheNextIsLate: A (22050 frames at 44.1 kHz) rendered in pieces of
  512 with B held back, bit-equal to A rendered alone, nothing "converter holding"; B, let go, plays from its start.
  It renders to 22016 and waits for the flush before rendering on: the check is made on each retry, in wall time,
  and an offline render runs many times faster than that - the verifiers' probe, rendering straight through, still
  shows the scrap (the render past the window between two retries). Its renders paced at real time, as the phone's
  are, with the IO buffer told: A whole to its last frame (23999), no scrap, 9 of 9 (pieces of 512, live and the
  phone's buffering, and pieces of 4800 with a 0.1 s IO buffer). Paced without the IO buffer told, the 4800-frame
  renders still left it: the window's two IO buffers are what cover a render larger than a retry.

**4 (low): the 10 ms settle failed from an 8 ms lag.** Held (measured above, "A node's buffers, taken late").
- **Fixed: 30 ms** (`offlineScheduleSettle`), the verifiers' second choice (25-50 ms) - 100 ms since
  fix/ci-settle, on a strict timer ("A node's buffers, taken late"). Still a bound. Their first, a fence, isn't
  there to be had: nothing tried tells when the node's queue has taken a buffer (above, "A node's
  buffers, taken late": isPlaying, playerTime, prepare, a zero-frame render, a zero-length buffer), and a dummy
  buffer's `.dataConsumed` would come only once a render has read it - the render this waits to make (reasoned,
  not tried). Not taken either: nodes attached before the engine starts offline (their scheduleBuffer is not
  deferred) - the tests would then run another path than the phone's.

**5 (low): a rebuffer waits the whole `startSeconds`.** Holds as described: bytes only just behind (20-50 ms, or
coming just as the node runs out) give 80 ms to 1.08 s of silence where 70cbef6 and 98a9d9e gave 50-430 ms - with
the position exact, where theirs ran 2400-8640 frames ahead. It is the hold's design ("Where the
judges differed": every restart waits for `startSeconds`; a stream just run dry may still be slow, and starting
with less risks a scrap and a second gap). **Rejected** as a change here: what the phone's dropouts sound like
decides it, and the position after one is now exact. If a shorter restart is wanted it is a setting of its own,
not this commit.

**6 (low): CI's 0.5 ms lag could not tell the settle's bound.** Held: a 2 ms settle passes at 0.5 ms.
- **Fixed**: ios.yml's second Audio run is at `DEADWAX_TEST_SCHEDULE_LAG=0.010`, which the old 10 ms settle fails
  across the suite and the 30 ms one passes (3 runs of 3 at 0.010, 87 of 87 each, 38.1-38.4 s; and 1 at 0.0005).
  The verifiers proposed 0.005, which the old 10 ms settle passes (4 of 4): it would guard the 30 ms only against
  falling under about 10.

**7 (low): `!ranOut(heard)` at the next lane's start was held by no test** (its mutation survived, "The hold on
the callbacks"). Held.
- **Fixed**: `joinRenderBehind` (tests only) reads the join's render time that many frames behind the render, as a
  live node's is (its last render time is the FIRST sample of that render): every callback can be in while the end
  is still ahead of it, and the end guard passes. anotherFormatLateWhileTheRenderTimeReadsBehindTheEnd is
  anotherFormatLate with the completions 0.25 s late and the render read 4800 behind; without the guard B starts at
  A's end, already rendered.

**8 (medium): the lead was added to the render's sample time, which is already ahead of now.** Held: a node's
`lastRenderTime` is stamped with the time its samples are presented, ahead of now, so every start on an output just
started (the first play, play after a pause, a call, a new route) was heard later than 307384f's by the lesser of
that and the lead: 1.5 ms with this Mac's own lead, 24.8 ms with a 0.2 s one (a 200 ms lead at a host time
presented 200.0 ms after the call; at render + lead, 224.8 ms). On the phone, at most the output's latency, if
its render timestamps run ahead as this Mac's do.
- **Fixed: the lead counts from when the start was asked, on the render's own host timeline**: the start is at the
  render's sample plus (asked + lead - the render's host time) x rate, never before the render plus the margin. A
  lead shorter than how far the render runs ahead starts at the render plus the margin; with no host time
  (offline, unless a test stamps one) the lead is added to the sample, as before.
- **Test**: theLeadCountsFromWhenTheStartWasAskedOnTheRendersTimeLine: `renderHostAhead` (tests only) stamps the
  offline render's host time that far ahead of now; at 0.02 s a 0.05 s lead starts at 1440 (0.03 s), at 0.08 s at
  0; silence to it, the song bit-exact from it, its count from it.

**9 (low): the lead's silence (the hold's findings 7 and 9) is the lead less how far the render runs ahead, and
"2 s on AirPlay" was never measured.** Held. **Fixed in these notes** ("The hold on the callbacks" corrected): no
test can hold it, as nothing here has an AirPlay route. Each route's start against 307384f's is a phone check.

**10 (low): play() at once starts two render cycles later than 307384f.** Holds as measured: play() put the
first sample at the last render + 1536 (59.4-59.7 ms after the call, 12 of 12), where 307384f's host-time lead
and efb8b6a's sample-time start put it at + 512 (36.4 ms); its count exact. Two places start so:
- **The first commit alone** (if the second is reverted, as "Starts at a sample time" offers): every skip, seek
  and run-dry restart on a running output - 23 ms here, by the same count about 43 ms at 1024 frames and 170 ms
  at 4096 (locked) on the phone. **Fixed in the revert plan**: a revert of the second commit puts a sample-time
  start at the last render + one IO buffer, or 307384f's host-time lead, in place of that play(), never play()
  alone (said where the second commit offers its revert).
- **efb8b6a's fallback on a running output**, with no render time of this run. **Rejected as a change**: rare here
  (a node attached while running had a render time at once), rarer since finding 1's wait, which covers play
  after a pause; and the start that needs no render and is 512 frames sooner, play(at:) a host time, puts the
  count 245-651 frames ahead of the samples (the hold's finding 1), where play()'s is exact. 23 ms, once, in a
  path the trace names ("no render of this run in 100 ms"); if the phone says it often, that is when to weigh 23
  ms against a count ahead.

**Mutations**, each restored byte for byte (sha-256 checked), the Audio tests run through the build lock:
all seven failing.
- no wait for this run's first render, straight to the fallback (playAfterAPause…, startWithNoRenderTime…);
- the render time not through `ofThisRun` (playAfterAPause…: started at 1924, off the reading left from before
  the stop, with the render at 12000 - a start in the past);
- `ofThisRun` without the reading-at-start check (aRenderTimeLeft…, playAfterAPause…);
- the lead from the render's sample, as efb8b6a counted it (theLeadCounts…);
- the join without `!ranOut(heard)` (anotherFormatLateWhileTheRenderTimeReadsBehindTheEnd);
- no flush before the node runs out (aResampledSongsEndIsHeard…);
- the settle back at 10 ms with every buffer 10 ms late, ios.yml's new second run (18 of 87).

**Seen and not fixed**: on this Mac's output, before this commit, the first start in the test process (a node
never played) began 419 frames (9.5 ms) after the sample time it was given - most likely a cold node's queue - so
its count was that far ahead and the join after it overlapped A by 419 frames; every later start was exact. After
this commit the same: 224 frames late in the first trial of both device probes (their engines started together,
the first in the process), exact in every later one. It is not from these starts (the sample time asked
was right; the node's first sample came after it), and 307384f's host-time starts were further off on every start.

**What only the phone can tell.**
- How long after play the phone's first render of the run comes ("this run's first render after N ms"), and that
  the fallback ("no render of this run in 100 ms", finding 10's play() at once) is never said.
- A 44.1 kHz album over a bad connection: each song's end whole and on time, the next joined after it.
- How long a rebuffer is (finding 5).
- The very first start of a run on the phone: exact, or late as on this Mac once.
- Each route's start lead against how far its render runs ahead (finding 9), AirPlay included.

### Verified (Phase 1's Core, p1/merge, 2026-11-10)

All on James's Mac (8 GB; heavy builds one at a time), Xcode 27.1's toolchain:
- `swift test --package-path ios/DeadwaxKit`, from a clean build: **DeadwaxCore 392 tests in 54 suites,
  DeadwaxAudio 54 tests in 2 suites**, all passing, no compiler warning (Phase 0 ended at 64 and 13; the merge
  at 389 in 53, before the review fixes' title test and FixtureFilesTests' two). With the screens' own rules
  merged and the stop fixed (ios): **DeadwaxCore 452 tests in 61 suites, DeadwaxAudio 54 in 2**, all passing.
- xcodebuild, the Deadwax scheme, Debug, `generic/platform=iOS`, CODE_SIGNING_ALLOWED=NO: BUILD SUCCEEDED (one
  line from appintentsmetadataprocessor, none from the code).
- The full Python suite: **4004 passed** (2.1.2's 3909, and 95 from Phase 1: test_ios_contract.py 8 -> 46,
  test_ios_library_contract.py 8, test_ios_levels.py 49); pyflakes clean on the contract tests.
- Every ui/test/*.sim.cjs on its own (72), the four ios*.sim.cjs among them: all pass.
- `python3 ios/scripts/check_project.py` ok; `bash -n` on ios/scripts/*.sh.
- Each slice's own mutations, above; the contract's 29 at the merge; the review fixes' nine, each restored byte for
  byte: suffix, duration, contentType, samplingRate and title each dropped from SHUFFLE_FIELDS (each fails the
  queue-answer contract, naming the field), QueueTrack(song:)'s and shuffledTrack's titles made `song.name`
  (aQueueEntrysTitleIsTheSongsOwn; shuffledTrack's also ResumeCaseTests' trace), the bundle looked in before the
  checkout and the checkout's path given without looking (FixtureFilesTests) - all nine fail.

### Not verified

- **DeadwaxCore on Linux** - since checked: ios.yml's ubuntu job built and passed all of Phase 1's Core at
  87024cd on its first run, and tests.yml ran every ios*.sim.cjs on Node 22 with the fixtures written on Node
  20.12.2, all passing. What follows was written before that run.
  No Linux toolchain here, and none of Phase 1's Core has been compiled on Linux.
  Everything new was written for swift-corelibs / swift-foundation (no Apple-only import; file sizes read as
  NSNumber or UInt, TimeZone, Unicode.Scalar properties, decomposedStringWithCompatibilityMapping, classic
  URLError codes, each found in corelibs' URLError.Code), but ios.yml's ubuntu job (swift:6.4.1-noble) is the
  first real compile. What is known from it: the test targets' declared resources, and so SwiftPM's generated
  `Bundle.module`, built there in Swift 6 mode at 9f5a78a; the fixtures are read from the checkout, so none
  leans on CFBundle's resource search, and only the missing-fixture test makes Bundle.module at all, reading its
  `resourceURL` (Review fixes).
- **Nothing ran on the phone**: the engine's risks E1-E9, the late-state race and its fix, a 304 through
  URLSession for a request carrying its own If-None-Match (with `urlCache` nil), the per-session and per-request
  timeouts holding together. Phone checks to add with the screens: turn Repeat One on in a song's last 2 s
  (the next song repeats - D4's consequence); tap an Up Next row in a song's last 2 s (it plays).
- **The fixtures were written on Node 20.12.2; CI runs Node 22.** If Node 22's ICU or tz data differ (the
  Library's fold names and dates are the likeliest), a sim fails on the first CI run and its fixtures need
  writing once on Node 22.
- **libm**: the glibc check is an emulation of e_log10.c, not glibc; tests.yml's pytest on ubuntu is the test.
- **A real Navidrome**: every Navidrome in the suites is a fake, as before - the loudness route included.

## Phase 1: the app (0.2)

The screens, on the Core above, built as six branches. **p1/app** first, the shell (f736efe): the models, the
gates, two tabs and a compiling stub for every screen, with the names the parts keep. Then five parts in parallel
worktrees on it: **p1/app-player**, **-you**, **-library**, **-album** and **-nowplaying**. Each part owned its
own files, so the five `--no-ff` merges into p1/app had no conflict (a6170b6, 5684244, 14982ed, eb82b6d,
c75a378). A last commit settled what the parts left to each other. The rule throughout is that the **screens
draw and Core decides**. A rule a part needed and Core lacked went into DeadwaxCore, tested against the web where
the web has it. The views draw and call the models from the tap. The app is **0.2 (2)**: Base.xcconfig,
check_project.py, ios.yml and test_ios_install.py all pin it.

### The shell (p1/app)

Phase 0's one model and one screen are split into models the screens read from the environment.

- **ServerModel** holds:
  - the address (UserDefaults `address`);
  - the client;
  - the session, in the Keychain per server;
  - /me and Access;
  - the launch: needsAddress, checking, unreachable (D10), signedOut, ready.
- **A 401 mid-use.** One under the session in hand (SignInRules.endsSession) brings the sign-in over the app, and
  the music plays on. One sent under an older session is ignored. Signing in again carries on for the same person.
  Anyone else starts again through `whenPersonChanges`, which the other models reset on.
- **/me** is asked again as the app comes to the front and after a song fails. With logins off, a 401 asks again
  at most once a minute.
- **PlayerModel** is the player's whole public surface, each member doc-commented with the Core call it makes.
- **Phase 0's test screen** is now DebugModel and You > Debug, for `isAdmin` (D1).
- **RootView** runs the gates in order. **MainTabs** has Library and You:
  - a second tap on the tab shown pops it to its root;
  - the mini player sits above the tab bar;
  - the notice capsule shows for 5 s and is announced to VoiceOver (D11).
- **Shared/** holds Routes (AppRoute, AlbumRoute, AppNavigation), CoverImage, ErrorNote (ErrorWords; the raw
  words only for seesDetail) and Notice.

### The player's wiring (p1/app-player)

- **The queue** is QueueController over `PlayerEngineLink` (PlayerModel+Engine.swift), Core's EngineLink on
  PlaybackEngine.
  - Engine keys are `generation << 32 | Up Next key`. Up Next's keys restart at 0 with each queue, so a state of
    another generation is dropped.
  - The generation moves only with a new queue (`beginStart`/`endStart`) and a stop, never with the controller's
    own replays.
  - `replaceUpcoming` is the engine's own synchronous answer (false: held, D4). `heard()` is `engine.position()`.
- **Listens.** An action runs inside `act {}`, and its song change is a new listen. A change found by catching up
  is the engine running on (`PlayReporter.join`).
- **Levels.** There is one LevelStore per queue. Each entry is decided at its first open, from LoudnessShelf, and
  wrapped by `GainedSource.wrap(source, factor:)`; Off and as-it-is are the source itself.
  - The entry a play, skip or jump named may wait at a LevelGate, for up to 20 s. A join, or a queue put back,
    never waits.
  - When the engine takes an edit, the kept entries' decisions follow them (`LevelDecisions.carry`).
- **LoudnessBook** (main):
  - It wants the queue's albums and the last 2 album pages shown.
  - It reads, warms, and reads again every 5 s.
  - A read's "unmeasured" is held off the shelf until the warm answers - and past a "busy" warm (review fixes).
  - While a gate waits, it reads that album every second.
- **Failures.**
  - The raw words go to `lastFailure`, and /me is asked once per song.
  - Then `PlayerWords.afterEngineFailure` decides: retry after 1.5 s, skip with its notice, or stop (a 401, or the
    phone's own failure).
- **Resume.** There is a ResumeController per `server.person` once /me answered, labelled "iPhone". The put-back is
  `restoreQueue`, paused, and fetches nothing. Saves run inside background tasks.
- **The lock screen** shows the entry's fields, with no index or count; its shuffle and repeat stay off.
  Interruptions, routes and resets are Phase 0's.
- **Streams** are asked through `ClientBox`, so a sign-in mid-queue streams the next song under the new session.

### The gates and You (p1/app-you)

- **Server address.** Phase 0's field and words, verbatim. What is typed reaches ServerModel only at Check.
- **Can't reach (D10).** The web's launch sentence (ErrorWords.signInProblem):
  - UNREACHED when nothing answered, deadwax's own words when it did;
  - Try again and Change address;
  - the detail folded under "For whoever runs deadwax". It shows while nobody is known, then only for
    seesDetail.
- **Sign in.** The web's elements and order, all from SignInForm, with the password manager's content types. Return
  moves to the password, then submits. The reason and the problem are announced.
- **You.**
  - The headline.
  - Playback: Gapless On; Normalization's four choices, Off without "Maximum quality".
  - Account: Sign out and its footnote.
  - About.
  - This phone: the address, and Debug for isAdmin.
  - The app's own version (About's App row since the review fixes; it was a footer).
- **In Core.** YouLines decides You from /me, held to You.tsx by Fixtures/you/ (export-you-vectors.cjs, 136
  cases, iosyou.sim.cjs). UnreachedLines is the phone's own, hand-tested.

### The Library (p1/app-library)

- **Albums.** The tab opens on "Your albums", or "Albums" with logins off and for break-glass. "All music" and
  its "All albums" row lead to the store's scope.
- **Sorts and layout.** Five sorts, saved under `deadwax-player-order`. Grid or list, per device.
- **Find** filters in place.
- **Headers and the index.** Headers sit in the flow. The trailing index shows letters or decades, at 50+ albums
  and never while finding.
- **New marks** come from GET /me/library. A starred count that moves forgets your albums.
- **The album index.**
  - One ask per generation, shared by every screen.
  - If-None-Match with the kept ETag; a 304 keeps the list.
  - 30 s to answer.
  - refreshIfOld as a screen shows, and pull to refresh.
- **Kept on disk** per (server, user, scope), excluded from backup, and drawn before the first ask. Core's
  KeptAlbumIndex decides which bytes may be drawn for whom.
- **At 3,000 albums.** Each Shelf is built once, off the main actor, on lazy stacks. Covers are asked at exactly
  400 and 128.

### The album page and the queue menu (p1/app-album)

- **The hero** is drawn at once from what opened the page, with the cover asked at 1024.
- **The badge** has its place held until whose it is is known.
- **Play and Shuffle.**
- **The mine block**: Add / Remove, with the placeholder that keeps the songs from moving.
- **The songs**, with their disc headings and playing bars, then the footer, and the bar's ••• for the album.
- **AlbumModel** asks for the album, and for the id bridge only with a library (D12). Only the newest answer
  draws, and a pull to refresh keeps what is shown when it fails.
- **The queue menu** is a confirmationDialog (Play Next, Play Last, Cancel), carried out in the tap.
- **New in Core:** AlbumPageRules.swift.
  - PlayingBars.
  - AlbumGone: a `{}` answer or a 404 draws the gone line alone.

### The player's screens (p1/app-nowplaying)

- **The mini player.** Cover, title, a second line (the failure, else the artist), Play/Pause, Next and the
  hairline.
- **Now Playing.**
  - The cover over its own blur.
  - "Artist - Album", which goes to the album.
  - The scrubber (Core's Scrub; a VoiceOver slider moving 5 s).
  - Shuffle, Previous, Play/Pause, Next, Repeat, AirPlay, Up Next.
  - ••• with Info, Go to album and Cancel.
  - A drag down past 110 pt closes it.
- **Up Next** draws upNextView:
  - the song playing and Repeat One's line;
  - the chips;
  - Playing Next with Clear;
  - "And N more songs.";
  - Edit (moves, with Move up/down as VoiceOver actions, and removes; VoiceOver's focus goes where the web's goes).
- **Info.** About (AboutCard, LevelWords.soundRows) and an admin's Debug: The file, Sent to this device, and
  Fields from Navidrome. The song's details and the bridge are held 0.5 s for each other.
- **In Core:** Info.swift.

### The merge (p1/app)

- **Go to album.** The shell's `openAlbum` pushed on the current tab. Now Playing's `goToPlayedAlbum` pushed on
  Library. One `openAlbum` is kept: it closes Now Playing and doesn't push the album on top again. The merge had it
  select Library; the review fixes put it on the tab shown, as screens.md 7 and the web's goToAlbum have it.
- **All albums** is `AppRoute.albums(AlbumScope)`, a value link. It stacks with album pages and pops with the
  tab's tap. A second tap on the tab scrolls the root only.
- **Add/Remove** calls `LibraryModel.libraryChanged()` directly. The album part's notification is gone.
- **The album page's lifecycle.**
  - It marks itself opened (`library.opened`: its New mark cleared, `seen` posted) on appear and when marks
    arrive.
  - It calls `albumShown` and `albumLeft` for LoudnessBook's pages, and wants them again on reappear.
- **Info's Conversion** is `PlayerModel.conversion`. The output's name had shown twice.
- **Debug** gained:
  - the Library's lists (albums, status, the last fetch's time);
  - Up Next's held edit (`holdsAnEdit`);
  - the version.
- **Palette** holds every colour, each named for its theme.css token.
- **CoverCache** is bounded at 96 MB of decoded bytes, and cancels a fetch nobody waits for.
- **The Navidrome gate** (NeedsNavidrome.tsx; the nowplaying part left it, with D8).
  - Core's NavidromeGate holds the rule, held to the web by Fixtures/gate/ (export-gate-vectors.cjs, 35 cases,
    iosgate.sim.cjs).
  - `LibraryModel.checkNavidrome` asks GET /deadwax/navidrome/status quietly, and only the newest answer counts.
  - The Library root draws the gate in place of its albums.
  - The phone's own call: the Library draws until a check finds Navidrome missing, where the web shows a spinner.
  - Set up Navidrome opens /player/ in Safari.
  - Only the root has the gate. A page above it shows its own ErrorNote.
- **Read as one piece.** Every screen is reachable, no stub is left, and no view decides a rule Core decides.

### Review fixes (p1/app, after the app's three reviews)

Three reviews read the merge (d2d52da): the screens against the web, the player's wiring, and the app as iOS runs
it. Every finding was checked against the code and the specs. All are fixed but one, rejected below with part of
another.

- **The album page's meta line** no longer jumps. AlbumRoute carries the genre (IndexAlbum's, Album's), so the
  line drawn before the album answers is genre and year, and only gains the format.
- **The sign-in shown alone asks /me again** as the app comes to the front (signInGate.tsx asks while the sign-in
  shows). Only a 200 changes anything: logins turned off elsewhere take the sign-in away.
- **Go to album opens on the tab shown** (screens.md 7), no longer always on Library.
- **The retry's 1.5 s shows Play, busy**, as the web's does. `isPlaying` leaves `retrying` out; a call during
  the retry still asks for the song again after it.
- **The mini player's buttons** are at least 44 pt and grow with the text size; Play/Pause keeps its room under the
  spinner.
- **The app's version is About's App row** ("0.2 (2)", screens.md 8.5), not This phone's footer.
- **A failure's words go when the song is asked for again**: the retry, and Play after a failure or after iOS
  refused the session (the web's reload()). A skip's notice is left alone.
- **A "busy" warm keeps the read's "unmeasured" off the shelf** (Core's `LoudnessAsking.keepsHeldRead`): the first
  song goes on waiting, at most 20 s, while the book warms again 5 s on, rather than the album being fixed as it is
  for the queue's life. A read's "unmeasured" is now always held until its warm answers, not only when the warm
  goes at once.
- **Answers gone stale.** The shelf keeps when each answer was kept. An album wanted again with no fresh answer is
  read first (`readsFirst`, levels.md 4.2), not warmed on a step left from before. A first song's wait counts an
  answer only when it is fresh or was read since the wait began (`believed`); once the wait is over it is decided
  from what is in hand, as before.
- **A paused seek, and Previous's restart, are read back** (`tick()`), so the clock keeps them after Scrub's 20 s.
- **Play Next and Play Last in a retry's 1.5 s** keep the retry unless the music started from them.
- **Songs a held Play Next added keep their Navidrome song**: the shelf is pruned only when a new queue started.
- **A failure met again is said again.** EngineState gains `failures`, one more at each `fail()`, so the same phase,
  key and words are a new state. The model takes a new count as a new failure (and a failure said again, on a new
  route, as none). EngineRenderTests' `aFailureMetAgainIsSaidAgain` fails with the count taken out.
- **Covers.** CoverImage keeps the image a load gave only while on screen and draws what the cache holds; a load for
  a cover the view has left draws nothing. Covers are decoded off the main thread (`byPreparingForDisplay`). A
  fetch and its failure are the session's (by its hash), a view's task id carries the session too, and coming to
  the front forgets every failure, so covers come back after signing in again or a tunnel coming back.
- **The lock screen's artwork**: only the answer for the song showing is drawn; a failure is asked again at the
  next change, no sooner than 15 s on.
- **The ticker and the book's 1 s timer run in the common run-loop modes**, so they don't stop while a list
  scrolls.
- **Rejected: the empty Your albums' words** ("…or find new ones in Search and Get them."). The phone has no Search
  or Get in Phase 1, but the words are the web's, verbatim, as library.md gives them, and held to yourLibrary.ts by
  the Library's vectors (Fixtures/library/words.json). Changing them is James's call.
- **Rejected in part: a hurried album warmed every second.** levels.md 4.2 says no warm sooner than 5 s after the
  last; the wait is bounded by LevelWait's 20 s either way.

### Verified (p1/app, 2026-11-11)

- **xcodebuild** (Debug, `generic/platform=iOS`, unsigned): BUILD SUCCEEDED. Its one warning is
  appintentsmetadataprocessor's own; none comes from the code.
- **swift test**: DeadwaxCore 508 tests in 69 suites, DeadwaxAudio 54 in 2, all passing (after the review fixes:
  511 and 55).
- **pytest**: 4004 passed.
- **The sims**: all 75 `ui/test/*.sim.cjs`, each run on its own, pass.
- **check_project.py** ok, and the project file is unchanged.
- **Each part's own mutations:**
  - KeptAlbumIndex: 6, each failing;
  - YouLines' identity rule: fails.

### What only the phone can tell

- **Nothing has been drawn.** There is no Simulator, so no view has been seen by anyone or read by VoiceOver. The
  checks are in the order of the plan's and screens.md 14's.
- **Unseen live:**
  - the engine's hold on the callbacks and its sample-time starts and joins (fix/engine-hold): the checks at the
    end of "The hold on the callbacks" and "Starts at a sample time";
  - the level wait against a measuring server;
  - plays reaching Navidrome;
  - resume across devices;
  - the lock screen;
  - a 304 through URLSession;
  - scrollTo under the bar;
  - disk reads and Shelf builds at James's size;
  - the drag to close;
  - the scrubber under a finger;
  - AirPlay's picker;
  - Edit's drag.
- **Left:**
  - the Library's Shuffle (Paged; no feed, D4);
  - Debug's Source row;
  - About.swift's older trackTime;
  - docs/ios.md and ios/README.md, which still describe Phase 0;
  - the engine test `aNewRouteGoesOnFromTheFrameHeard`, which failed once on timing under load;
  - later, **the play queue picked up live** between the phone and the web app, which James wants eventually
    (decided 2026-11-11: the on-open and on-front rule of "Resume" stays for now). The two ways put to him: the
    phone alone, asking deadwax every ~15 s while the app is on screen and paused (GET /queue reads Navidrome's
    queue, so another Navidrome app's save shows too); or deadwax sending each change over an SSE stream the
    app holds open while it runs (not Apple push, which a free account doesn't get; shaped like the event log's
    stream, but each person's own, not the `server` permission's), server work on main as a 2.1.x patch. A
    stream sees only the saves made through deadwax: another app's, saved straight to Navidrome, would reach it
    only if deadwax itself polled Navidrome's queue.

## Phase 1 on James's iPhone (app 0.2 (2), 2026-11-11)

James ran Phase 1's checks on his iPhone 17 Pro (iOS 27.2). What came of them was fixed on `fix/p1-phone`, one
commit each; nothing here has been drawn or played anywhere yet, so each part ends with what only the phone shows.

### The ••• menus open from the •••

**What James saw.** On Up Next's check: "the dialog for play next and play last shows up in the wrong spot" - the
••• menu.

**Why.** The queue menu was a `.confirmationDialog` applied to the whole album page (`.queueMenu($menu)` on
AlbumView's List), opened by a state the row's ••• and the bar's ••• set. Since iOS 26 a confirmation dialog is
drawn as a popover from the view it is attached to, so it came up from the page, away from the ••• tapped. (That
it anchors to the page is from what James saw on iOS 27.2, not from Apple's documentation.)

**What changed.**
- **QueueMenu** is a view now, not a modifier: a SwiftUI `Menu` whose label is the ••• itself, as Apple's own •••
  are. The row's ••• (TrackRow) and the bar's (AlbumView's toolbar) each hold one, so each opens from itself. Its
  items, words and actions are the dialog's: Play Next, then Play Last, each `PlayerModel.choose` in the tap, so the
  levels, the album remembered and the notice after ("Playing next: Roads", none when the music started from it)
  are unchanged. The title the dialog showed (QueuePick.title) is the menu's one Section's header.
- **No Cancel row.** A menu closes with a tap anywhere else, and Apple's menus have none. QueuePickWords.cancel
  stays in Core: it is the web's word, held to queue.json.
- **`menuOrder(.fixed)`** (iOS 16+): left to itself iOS puts the first item nearest the tap, so a menu opening
  upward from a row low on the screen would have shown Play Last first.
- **The bar's ••• is dimmed** until the album's songs are in (QueueMenu disables itself with no request), as the
  button was. QueueMenuRequest lost its UUID: nothing presents it by identity any more.
- **NowPlayingMenu** was a confirmationDialog too, attached to its own button, so it already came from its •••;
  it is a Menu now as well, so every ••• in the app works one way: Info, then Go to album for a song that names its
  album, no Cancel, the order fixed.
- VoiceOver's names are the same strings on the same controls ("More for Roads", "More for this album", "More:
  info, go to album").

**Verified**: the app builds for iOS 17 with it (xcodebuild, unsigned). **Assumed**, for the phone: that a
Section's title shows as the menu's header on iOS 17 and 27; that the row's ••• opens only its menu inside a List
row whose song button is beside it (both plain-styled, as the button was). After review, the row's QueueMenu and
NowPlayingMenu carry `.menuStyle(.button)` (iOS 16+) before `.buttonStyle(.plain)`: Apple pairs ButtonMenuStyle with
a button style, and doesn't say whether the automatic menu style reads one - the project's rule is that two
automatic-styled buttons in one List row both fire, so the plain style must surely reach the menu's own button. It
also keeps Now Playing's ••• drawn untinted, as the plain button was. The bar's ••• is left to the toolbar's own
style. NowPlayingWords.menu ("More"), the dialog's hidden title, went with the dialog: nothing used it.

**On the phone**: open an album, tap a song's •••: the menu opens from that •••, with the song's name over Play Next
and Play Last. Try it on a song near the bottom of the screen too - Play Next still first. Tap away: it closes and
nothing is queued. The ••• at the top right does the same for the whole album, and Now Playing's ••• opens Info and
Go to album from itself.

### Up Next: one tap to take a song out

**What James asked.** "swiping doesn't work to take one out", then, asked whether removing should stay Edit-only:
"leave it edit only, but add swipe to remove in edit mode so I don't have to tap two different places per song".
Until now Edit's removal was the List's own (`onDelete` only while editing): the red (-), then Delete.

**Can a List row be swiped while Edit is on? No - iOS doesn't offer it.** Apple doesn't say so in one sentence;
what it does document puts a swipe and Edit in different modes:
- SwiftUI's `EditMode.transient` is the mode SwiftUI may engage "over the duration of a swipe gesture" - a mode of
  its own, apart from `.active`, which is Edit (developer.apple.com/documentation/swiftui/editmode/transient).
- UIKit's table views, which SwiftUI's List stood on until iOS 16 (a collection view list since), describe a swipe
  as entering a "swipe to delete" mode of its own, in which the editing and reordering controls are not shown
  (Apple's Table View Programming Guide for iOS, "Inserting and Deleting Rows and Sections").
- In Edit, the delete control's job is to bring out what a swipe would: tapping the minus "reveals the cell's
  trailing swipe actions" (Matt Neuburg, "Collection View Lists in iOS 14, Part 2", BiTE Interactive) - the
  two-step James found.
- Developers report the rest: "enabling EditMode ... disables navigation & swipe actions" (Stack Overflow 73889241,
  September 2022, on iOS 16).
- The most direct (found by the review, and read again for this note): in Apple's developer forums (thread 756765,
  June 2024) a developer asked for a List's swipe actions to show while it is in editMode, for people who find the
  swipe hard; an Apple DTS engineer answered that there is currently no way to bring a swipe action out in code, and
  suggested a visible control on the row that deletes - what was built.
The review could open neither the Stack Overflow question nor Neuburg's article; Apple's three are read. Not tried on
iOS 27: there is no Simulator, and the phone hasn't been asked. If a swipe in Edit ever worked there, it would be
news.

**The option not taken**: a swipe of deadwax's own - a drag gesture on each row in Edit, taking the song out past a
threshold. iOS doesn't stop an app drawing one, but it would contend with the List's scrolling and the drag handles
for the same finger, and nothing here can try it; James can ask for it if one tap isn't enough.

**What changed**, then, is the other way the request allowed for: Edit gives each row ONE action. Its own red (-) at the leading edge
takes the song out at once (`UpNextScreen.editRow`), in place of the system's two-step control, and the List's drag
handles stay (`onMove` while editing). There is no `onDelete` at all now: out of Edit it would be a swipe that loses
a song, in it the two-step (-). Out of Edit nothing changes - no swipe, no (-), so no stray removal.
- **VoiceOver**: the row is one element with its words read as before ("Roads, Portishead · Dummy") and the same
  actions: Move up, Move down (none past a group's end) and Remove. The (-) is hidden from VoiceOver and the row's
  children are ignored, so a double tap on a row in Edit does nothing - VoiceOver can't take a song out by landing
  on it. Remove's focus move is the one the screen made already (the next row, the one before at the end, else
  Done), and what changed is still read out ("Roads removed").
- The (-) is drawn as the system's: `minus.circle.fill`, white on red, a 44 pt target, borderless so it takes its
  own tap inside the row.

**Verified**: builds. **Assumed**: that a borderless button in a List row takes its tap while Edit is on (controls
in rows do; not seen here), and that with no onDelete the List draws no delete control of its own in Edit.

**Two things to know, from the review.** One tap a song is what James asked for, and there is no undo: a quick double
tap on a (-) can take out the song that slides up under the finger as well. And the (-) being hidden from
accessibility, Voice Control has no "Tap Remove…" name or number for it, as it had for the system's control: Show
grid reaches it (by place, not by the accessibility tree), and VoiceOver keeps Remove among the row's actions.
Neither was changed - a pause after each removal, or the (-) as an element of its own, would be James's call.

**On the phone**: open Up Next with songs added, tap Edit: each row has a red minus on the left and a drag handle
on the right, and nothing else. One tap on a minus takes that song out - no Delete to confirm. Drag a song by its
handle. Try swiping a row in Edit and out of it: nothing happens either way. Done ends Edit.

### Debug's engine log

**Why.** The engine's checks on the phone (the hold on the callbacks, the sample-time starts and joins) can only be
read from what the engine says, and nothing listened: PlaybackEngine's `trace` (called on the engine's queue for
every note it makes) was nil - the app never set it, so the engine built no line at all.

**What changed.**
- **Core's EngineLog** keeps the last 500 lines in memory, a ring behind one NSLock: the engine's queue appends,
  Debug's screen reads; nothing on disk. EngineLogTests (the ring, its numbering, the scrub, four writers and a
  reader at once) run on macOS here; ios.yml runs them on Linux too, once the branch is pushed - only APIs
  swift-corelibs-foundation has as well.
- **The app's EngineTrace** sets `trace` as PlayerModel makes the engine (beside `lead`, outside the main actor for
  the same reason: the engine calls it on its own queue). Each line is scrubbed, kept, and sent to os_log through
  `Logger(subsystem: "net.lizardlounge.deadwax", category: "engine")`, at the info level since the review (the
  default level stores every message in the phone's log store - about 170,000 lines a day of playing, crowding it
  and riding into any sysdiagnose; info messages stay in memory, stored only around a fault) and `.public` - it was
  scrubbed already, and a private string shows as `<private>` once no debugger is attached. Console.app on the Mac,
  with the iPhone chosen and Action > Include Info Messages on, streams it (search
  `subsystem:net.lizardlounge.deadwax`). Whether `xcrun devicectl device process launch --console` shows os_log
  lines, as it does the app's stdout and stderr, wasn't tried; Console is the sure way.
- **You > Debug > Engine log** (Debug is an admin's, so this is too): Copy (the whole log as it is at the tap) and
  Share (as text, as last read), the line count, and the lines in a 320 pt scroll box, monospaced, selectable,
  anchored at the bottom so the newest line, last, is in view. Drawn lazily (a LazyVStack keyed by each line's
  number), and read again once a second only while the log's row is on screen and the app is active - a
  `.task(id: scenePhase)` on the log's row, which the Form cancels when it scrolls away or Debug closes, and which
  stops when the scene leaves `.active` (a locked phone left on Debug with music playing fires no onDisappear) - and
  only when the count has moved. (It was on the Copy and Share row at first, which scrolls off the top while the
  320 pt box is still in view.) Once 500 lines are kept, each read drops lines at the top as it adds them at the
  bottom, so the lines move under someone scrolled up reading; the footer says so, and Copy keeps them still.

**What reaches the log - every `note()` read.** PlaybackEngine has 31 `note(...)` calls and nothing else calls
`trace`. All but three interpolate only numbers and flags: entry keys, lane rates and channel counts, frame and
sample counts, milliseconds, "running"/"playing". The three strings are an AudioFailure's `description` (the next
song failed, and `fail()`) and AVAudioConverter's error's `localizedDescription`, an OSStatus's words; `fail()` is
also handed AudioFailures made from AVAudioEngine's start and remake errors' `localizedDescription`, the same kind
of words. An AudioFailure's words are the engine's and StreamFetch's own sentences with: an http status; a URLError's or a file error's `localizedDescription` (iOS's sentence, never the URL); a file's
`lastPathComponent`, which is the cache's `<song id>.<suffix>`; byte counts; and, for an error that isn't an
AudioFailure, `String(describing:)` - only an NSError's description could carry a URL, and the only URL the phone
streams from is `/deadwax/navidrome/stream/<song id>?format=<format>`. **The session is never in a URL**: it goes as
the request's `Cookie:` header (DeadwaxClient.request, StreamFetch with cookies off), and no failure repeats a header.
The phone never sees Subsonic's u/t/s/p at all - deadwax adds them talking to Navidrome. So no secret reaches the log
today; **the scrub is the guard against a new note changing that**: before a line is kept or sent to os_log,
EngineLog.scrub takes out everything after a Cookie, Set-Cookie or Authorization header, a Bearer token, a URL's
user:password@, and the value of a key whose name is a secret's (u, t, s, p, apiKey, token, salt, password, session,
deadwax_session...) standing on its own, given with "=" or (since the review) ":" - `t=abc`, `token: abc`,
`x-deadwax-session: abc`, JSON's `"password":"hunter2"`, a quoted value all of it. A secret in bare words
("password hunter2") isn't recognised: the guard is for a note quoting a URL, a header or a request, not prose - so
docs/ios.md says what the engine writes and what the log takes out, not "never". A line with no "=" or "@", no ":"
right after a secret's key, and none of those names - every line the engine writes now, each with its ":" after
"Hz" or "failed" - skips the patterns after one pass over its bytes.

**What it costs the engine's queue - measured.** A benchmark on James's MacBook Air (M2, `swiftc -O`, the median
of 7 runs of 100,000 - the iPhone 17 Pro's cores assumed no slower, not measured), with EngineLog as committed:
- building a line as note() does (the host time through `String(format:)`, then the words): 1.4-1.6 µs;
- EngineLog.append for a line the scrub has nothing to take out (every line today): 0.085 µs - the first look is one
  pass over the UTF-8. Its first version used Foundation's `contains` and `range(of:options: .caseInsensitive)` and
  cost 17 µs a line, so it was rewritten before this commit;
- a line the scrub does rewrite (none today): 19 µs;
- `Logger.log` with a public string: 0.26-0.39 µs (nothing streaming; Console streaming costs more, on its side);
- all of it together: **1.9 µs a line**.
Measured again after the review, the same way, with its ":" look-back, its two quoted-value patterns and the info
level: a plain engine line's append 0.10 µs, a failure line with three ":" 0.19 µs, a line the scrub rewrites 50 µs
(six patterns over the line where there were four; none today), `Logger.info` 0.41 µs against `Logger.log`'s 0.35,
and all of it together **2.1 µs a line**.
At the engine's steadiest rate, 2 lines a second while playing, that is about 4 µs a second, 0.0004 % of the queue's
time (were every line rewritten, 100 µs a second, 0.01 %); the bursts (a skip, a new route, a failure) are a few
lines each. The engine's queue isn't the render thread, which never writes a line. The app's Debug build (-Onone)
is slower than this; install.sh builds Release. Debug's own read, a snapshot of 500 lines once a second while shown,
is 3 µs, and the text for Share 22 µs.

**On the phone**: You > Debug > Engine log, after playing an album for a minute: lines like `48210.112 lane 44100 Hz:
a buffer rendered, 3 to go`, the newest at the bottom, about two a second while it plays, none while paused.
Copy, and paste it into Notes: the whole log. Share opens the share sheet with it as text. In Console on the Mac,
with the iPhone chosen, Action > Include Info Messages on and `subsystem:net.lizardlounge.deadwax` searched, the same
lines arrive as they happen. Lock the phone on Debug with music playing and unlock it: the lines carry on from where
the log is, nothing lost (the reading stops while locked, the keeping doesn't).

### The lock screen's next cover, fetched ahead

**What James saw.** The lock screen's art "takes a moment to render" at each song change. He said "Yes, fetch it
ahead".

**Why.** The lock screen's cover (`PlayerModel.showNowPlaying`, which sets MPNowPlayingInfoCenter's artwork) was
fetched only once the new song was heard, straight from deadwax and outside the cover cache - the info centre was
set without art first and again when it came. An album's songs often share a cover id, but Navidrome gives a song
with its own embedded art its own (`mf-...`), so a change could mean a fetch every song.

**What changed.**
- **coverAhead()**: the next song is known as soon as the queue or the engine moves (`nextIndex(queue)`, with
  Repeat's copies unrolled into the queue - the same next the stream prefetch uses, `keepAndPrefetch`). Its cover is
  fetched into the app's CoverCache at the lock screen's size (CoverSize.lockScreen, 1024) while the song before
  plays: one ahead, one fetch at a time, not when it is this song's cover too or already kept, and not
  while the player isn't meaning to play. The fetch is never called off (an unstructured task, a waiter that never
  leaves) - it is the next song's whatever screen is shown.
- **showNowPlaying()** looks in CoverCache first: a cover kept there is set with the song's title, in the same
  `nowPlayingInfo`, at once. Only a cover not kept is fetched then, and through the cache too
  (`CoverCache.load`), so the lock screen and Now Playing's 360 pt cover (also asked at 1024 on a 3x phone) share
  one fetch and one decoded image, where they had two.
- **Its failure rule is kept**: a lock screen cover that failed is asked again at the next change no sooner than
  15 s on. CoverCache's own is a minute, so `load` gained `againAfter` (default a minute; the lock screen passed its
  15 s at first, 0 since the review - below), the failure kept per session as before.
- **Memory**: a 1024 px cover decoded is 4 MB of CoverCache's 96 MB limit (NSCache, by cost). The next one is one
  more of those, and the cache may let it go under pressure (a big grid flung), when the change fetches it then, as
  before. The lock screen still holds its own reference to the cover it shows.

**After review**, three changes to it:
- **The cover asked ahead is let go once its fetch lands** (`coverAheadAsked` cleared then, and by `stop()`): it had
  stayed marked for good, so a cover fetched ahead once was never asked ahead again - with Repeat All over two
  albums, the second time round to a cover the cache had let go meanwhile, the change lagged again; and a fetch ahead
  that failed once (a WireGuard blip) was never tried again while it stayed next. Now the guard is only "not while its
  fetch is out": a kept cover isn't asked again (the cache check), and one that failed waits out the cache's minute.
- **The next cover waits for this one's.** At a change where neither cover is kept, the two 1024 px fetches ran at
  once over WireGuard - just the moment the lock screen was waiting. `coverAhead()` now runs once this song's cover is
  drawn (straight away when it was kept, or when the song has none; else from its fetch's landing, which calls
  showNowPlaying again), or once its fetch failed.
- **The change's own fetch passes `againAfter: 0`.** The cache's failure memory is shared by the session's fetches, so
  a fetch ahead that failed shortly before the change held the change's own back for 15 s (the lock screen's window,
  counted from the other's failure). The lock screen's rule is `coverFailed` - its own failure, its own 15 s - and the
  cache's minute no longer counts for it, as before this branch, when it asked deadwax straight.

**Verified**: builds; the next song and the cover id come from the same queue the stream prefetch reads.
**Assumed**: that MPNowPlayingInfoCenter shows artwork given with the song at once (it showed it at once when set
later, so it should).

**On the phone**: play an album whose songs have their own covers, or a few albums with Play Last, lock the phone,
and let one song run into the next: the lock screen's cover changes with the title, not a moment after. Skip with
Next on the lock screen too (the song after next has had less time - a skip two ahead may still take a moment).

### The mini player over the last row (fix/player-inset)

**What James saw.** "the playbar at the bottom covers the bottom row of whatever is on screen. so to select "debug" i
have to kind of catch it as I'm scrolling." With something queued, no list scrolled far enough for its last row
(You's Debug) to clear the mini player.

**Why.** MainTabs gave each tab's NavigationStack `.safeAreaInset(edge: .bottom) { PlayerInset() }`. That draws the
player in the right place, above the tab bar, but the inset never reaches the pages inside the stack: their lists
end at the tab bar, under the player. Reported to Apple as FB23732628 (developer.apple.com/forums/thread/837946, July
2026, no reply): a `safeAreaInset` or `safeAreaBar` on a NavigationStack doesn't update the content insets of the
views in it, root or pushed. The report measures that against the inset the same modifier gives on the stack's
content, but doesn't show that working: that is the modifier's documented job, not something the report tested. That
it is the stack hosting each page apart from the SwiftUI around it is our reading, not Apple's word; that it is so on
27.2 is what James saw.

**What changed** (MainTabs.swift, Routes.swift):
- Each tab is a **TabStack**: its NavigationStack with the player as an `.overlay(alignment: .bottom)` - the same
  notice-over-mini-player, the same 8 pt padding, in the same place (an overlay sits inside the stack's safe area,
  the tab bar's and the keyboard's, as the inset did). Being an overlay, it adds to no safe area.
- The player says its height as drawn (`onGeometryChange`, iOS 16+), so the room follows the text size and the
  notice coming and going; with nothing drawn the room is 0, whatever was measured last.
- **Every page in the stack takes that room itself**: `clearsPlayer()`, a `safeAreaInset(edge: .bottom)` of a clear
  frame that tall (no hit testing, hidden from VoiceOver), read from the environment (`playerClearance`). The roots
  get it in TabStack, every pushed page in `appRoutes()`. The pages under it: the Library's root (AlbumsScreen's
  ScrollView, or the Navidrome gate's), All albums pushed, the album page's List, You's List, Server address's Form,
  Debug's Form. The Library's letter index is an overlay on the ScrollView, laid out in its safe area, so it stops
  above the player too. Now Playing, Up Next and Info are over the tabs, not under the player.
- Nothing else moves: the mini player isn't redrawn per page, so it stays put as pages push and pop. Not
  `tabViewBottomAccessory` (a new look, and iOS 26+).

**Verified**: the unsigned device build (no new Swift warnings), DeadwaxKit's tests, check_project.py, the source-bytes
and contract tests. **Assumed**, since nothing is drawn here: that a `safeAreaInset` on a page inside the stack
reaches its List, Form and ScrollView on iOS 17-27 (its documented behaviour; FB23732628 takes it as the baseline
but doesn't show it); that the overlay sits where the inset drew the player; that `onGeometryChange` reports the first
height as it appears; that a change to `playerClearance`, an environment value set on the stack, reaches a page
already pushed (the album page you start playing from, with nothing playing before).

**On the phone**: with nothing playing, open an album, play its first song, and scroll the same page to its end
without leaving it: the last song clears the mini player that has just come up (the room reaching a page already
open). With something playing, scroll You to the bottom and tap Debug without chasing it; the same at the end of an
album, of Your albums and All albums (the letter index's last letter above the player), and in Server
address with the keyboard up and down. Play Next something, and while its line shows, scroll a list to the end: the
last row clears the line too. Big text (Settings > Accessibility > Larger Text): the last row still clears. Nothing
playing: no gap at a list's foot. Push and pop pages: the mini player stays still.

### Up Next's History, and a tap that keeps what it passes (port/upnext-history, the web's 2.1.3)

**What James chose**, testing 0.2: tapping song 8 while 5 plays dropped 6 and 7, so Previous from 8 went to 5. He
chose "Keep them, in order" - 6 and 7 stay behind 8, Previous from 8 plays 7, then 6 - and History in Up Next, "Both
apps, now". The web has it as 2.1.3 (notes/app.md); this is the phone's port, held to the same vectors.

**Core** (DeadwaxCore, pure, ported function by function from ui/src/lib/upNext.ts and resume.ts):
- `UpNext.swift`: `unitEnd`/`unitStart`/`unitsIn` (a UNIT is an entry and its Repeat One copies - one row, one song),
  `layout`'s `listEnd` (the list runs through songs added among its songs after Previous - the bug 2.1.3 fixed on the
  way); `groupOf`, `withoutKey`, `movedKey` by units; `withoutAdded` only Playing Next; `withShuffle`'s and
  `withRepeat`'s list songs take their copies with them; `jumpedTo` returns `Jump { queue, index }` (a list row: the
  rows above it kept behind it, Playing Next carried after it; a Playing Next row: the same queue at a new index; a
  History row: a new 'added' entry of its song after the song playing's copies); `historyRows(_:back:)`;
  `wentBack` (Previous before where listening began moves `startedAt` down). `UpNext.historyBack = 50`, equal to
  `Resume.before` (tested), so History after a pick-up is History before it.
- `UpNextView.swift`: `history` first; `added` and `list` by units; words `history`, `playAgain`, `playing`.
- `Resume.swift fromSnapshot`: a `startedAt` past the song playing's run - as 0.2 and the web's 2.1.2 saved it after
  Previous before where an album began - is lowered to the run. The saved format is unchanged.

**QueueController**: `jumpTo` catches up, takes the jump, and - the edit taken, or nothing to edit - sets
intendsToPlay and moves to `jump.index` (`engine.skip(to:)`); refused (D4, a seek on its way), it finds the row again
and plays afresh from it, as before. It returns whether the jump was made (`@discardableResult`), so the screen says
what started only then. `previous` moves by `wentBack`. **The engine is unchanged**: `skip(to:)` is
`begin(at:from: .beginning)`, which resets and opens any entry - forward over several as Previous goes back over one.
A tap with nothing to edit (no Playing Next to carry, a row of Playing Next) is now a plain skip, so in a song's last
seconds it no longer plays afresh.

**The exporter** (ios/scripts/export-traces.cjs): jumpedTo recorded with its `index`, the move a `setIndex` after
it (never `onward`); a `wentBack` op and a `historyRows` query; `history` in every view; HISTORY_BACK in the
constants; the traces' Previous by wentBack and a tap of History's now and then; scenarios for every 2.1.3 case of
upnext.sim (and Previous across songs added); the property digests from the sim's new loop (pick(14), ops 12 and
13); the round trip's tap of History's and Previous half by wentBack, half as before; resume's cases: the old
Previous case's startedAt lowered, the 0.2 pick-up, wentBack's save. UpNextPropertyTests runs the sim's new per-step
checks (History equal to Previous's walk by place and by song, every copy its run's song, every drawn row reached by
its tap); ResumeRoundTripTests holds History the same after every round trip.

**UpNextScreen**: History is a Section above the card, headed "History" (a heading), hidden in Edit, with no moves or
removals; its rows are "{title}, play again", a tap playing the song again with VoiceOver's focus kept on the row and
"Playing {title}" said - only when the jump took. An Up Next row's focus goes to what plays next (after a list row,
Playing Next's head) - only when it took. The card's title is a heading. It opens scrolled to the card, and puts the
card back at the top when the entry playing changes or Edit goes on or off - not after a History tap, and never for
Shuffle, Repeat, Clear or Edit's moves. **Unlike the web**, which puts back exactly what was in view when the song
playing changes, the phone puts the card at the top (a List gives no first visible row to hold to); scrolled down the
list as a song ends, the view goes to the card. A bottom content margin - the height less lower bounds of the card
(120 pt) and each row after it (56 pt) - lets the card reach the top near an album's end; it can leave a little more
blank than needed, never too little. **Also unlike the web**, which holds the row tapped under the finger by
measuring it: once History is at its 50 entries, a History tap moves the window on (the song again is a new entry), so
the oldest row drops off the top and the phone, which only leaves the scroll alone, shows the rows a row higher.

**After review** (same branch): an Up Next row's tap sets VoiceOver's focus on what plays next only after the card is
back at the top (`focusAtCard`, taken by the playing key's onChange and set after toCard's scrollTo) - set at once, as
first cut, the row was pushed down by History's new rows, maybe out of the List's drawn cells, before the scroll; and
a History tap's focus and "Playing {title}" come after the redraw (one Task), as the web says them from the draw.
Both assumed, as the rest of VoiceOver here.

**Verified**: the whole DeadwaxKit suite (the traces, scenarios, property digests and round trip re-exported, and
iostraces.sim's check); the unsigned device build, no new warnings; check_project.py; the ios sims, upnext.sim and
resume.sim. **Assumed**: List's scrollTo to the card after a change lands as asked (`Task` then an instant
transaction, as AlbumsScreen does); that inserting History's new row above the card leaves the tapped row in place
(UICollectionView keeps its offset); the bottom margin's lower bounds at the largest text sizes; VoiceOver reading 50
History rows and the announcement after a History tap.

**On the phone**:
- Play an album from song 5, tap 8 in Up Next, then Previous three times: 7, 6, 5.
- Scroll up: History; tap a row: it plays, the row stays under the finger; tap the same row again: it plays again.
- Play Next a song, Previous back across it: Up Next lists it among the album's songs, not under Playing Next.
- As songs end, through Shuffle and Repeat, and Edit on and off, the list keeps its place (the card at the top).
- An album's last two songs: Up Next still opens with the card at the top.
- VoiceOver: History's heading, then its rows, then the song playing's title as a heading.

## Phase 2: downloads (app 0.3)

The spec is notes/ios-specs/phase2-downloads.md. Built in two parts on `p2/downloads`: the machinery first (below),
then the screens.

### Part 1: the machinery (p2/downloads)

**Core** (pure, tested on Linux and macOS): `DownloadModels` (a song's state, the waits, the failures as codes, the
origins, `DownloadRecord`, the two settings `DownloadOver` and `StorageLimit`, `NetworkPath`, `DownloadTaskName`),
`DownloadRules` (every transition of 2.1, the album's state of 2.2, the menus' items of 2.5, what Remove takes),
`DownloadPlan` (8.5), `DownloadWords` (every line of the spec; the vocabulary sim's ban list ported, over
`DownloadWords.everyLine`), `Bytes.words` (8.6), `FLACMD5` (RFC 1321 MD5 and FLAC's packing), `Offline` (`OfflineRule`,
`PendingPlays`, `LibraryRoot`, `AlbumList`, `DownloadedAlbums`, the gate's two rules; `AddedBy.phone`) and
`DownloadDatabase` over the `CSQLite` system library (8.2's schema, `user_version` 1, WAL). **DeadwaxAudio**:
`FLACVerifier`, the one addition - it reads, never plays.

**The App** (`App/Downloads/`, `App/Models/Reachability.swift`):
- `DownloadStore` - one person's folder, database and files: protection (`completeUntilFirstUserAuthentication` on
  every folder, file and the database), backups off, free space, other accounts, Phase 0's folder retired.
- `DownloadSession` - the one background session. The delegate moves a finished file to `music/<name>.part` before
  it returns, from the task's name alone, and tells the model on the main thread synchronously, so the store has every
  event before `urlSessionDidFinishEvents` lets `.backgroundTask(.urlSession(...))` end (capped at 25 s).
- `DownloadModel` - what the screens bind to (below), and everything in step: the plan run at every ask, finish,
  failure, setting, path and reachability change and coming to the front; tasks made, cancelled and re-adopted after a
  relaunch; the length check and rename (`done(unchecked)` plays at once); the sound check one song at a time at
  utility priority inside `beginBackgroundTask` (a check iOS stops is checked again later, never a try); albums' answers,
  covers (1024) and loudness kept; plays kept and sent.
- `Reachability` - NWPathMonitor, the transport's every answer or silence (`URLSessionTransport.listen`), the 3 s probe
  on its own ephemeral session, a 5 s tick for the 30 s probe.
- Wired in: the engine plays `SongFiles.downloads` (a `PlayableCopies` index the model keeps) before any stream, and
  prefetches nothing for a song on the phone; Phase 0's downloads and the link's `copies` are gone; Debug's test songs
  download through the model, its Streamed/Downloaded picker is "Stream even when downloaded"; PlayReporter keeps a
  play it can't send (not online, or no answer); LoudnessBook puts a downloaded album's kept loudness on the shelf at
  `at` 0 and fails a read at once while deadwax can't be reached (7.3); CoverCache draws a kept cover from the phone
  first (8.8); ServerModel keeps every good /me as `me.json` and opens from it, /me asked behind (7.5).

**The model's surface** (`DownloadModel`, in the environment):
- reading: `state(_ songID) -> SongDownload`, `album(_ songs) / album(id:) -> AlbumDownload`, `choices(song:)`,
  `choices(songs:gone:)`, `upNextCount(_:paged:)`, `isHere(_:)`, `anythingHere`, `downloadedAlbums: [IndexAlbum]` (the
  Library's Downloaded, `AlbumList.downloaded`), `song(_:)` and `keptAlbum(_:)` (rows' names from the kept answers),
  `downloading` / `failed` / `downloaded` (You > Downloads' sections, in the order they go), `summary` (You's row),
  `bytesHere`, `otherBytes`, `forceQuitShown`, `storeProblem`, `playsWaiting`; Debug's `log`, `checkSeconds`,
  `debugTasks()`.
- the settings: `downloadOver`, `storageLimit` (UserDefaults, the spec's defaults), `streamEvenWhenDownloaded`.
- acting, in the tap: `download(_ song)`, `download(album:)`, `download(songs:)`, `remove(_ songID)`,
  `remove(album:)`, `remove(songs:)`, `tryAgain(_:)`, `tryAllAgain()`, `removeAll()`, `removeOthers()`.
- progress: a screen that shows it runs `await downloads.followProgress()` in its `.task`; read four times a second
  from the session, never kept (a song with no byte yet shows its wait).
- `Reachability` (in the environment too): `reach`, `online`, `path`, `probing`, `tryNow()` (the banner's Try again,
  a pull).

**Departures from the spec, and why**:
- `song` gains a `duration REAL` column: a transcode's estimate (8.5) is its duration at 320 kbps, and the row is all
  the planner reads.
- The task's name is `<server>|<person>|<song id>|<suffix>`, each part `safeName`d: the delegate names the `.part`
  from it before any store is open (a background relaunch knows no one yet).
- `DownloadStore` is a class used on the main actor, not an actor: every write is ordered with the model's state, and
  the delegate's one file move needs no store at all.
- **Download over changed: the tasks out are made again from the start, not from resume data.** Resume data carries
  the request it was made from, its network flags included, so a task resumed from it would keep the old setting (Wi-Fi
  only still waiting for Wi-Fi, or "Wi-Fi only" still using mobile data). At most the three songs fetching lose their
  bytes; the rest hadn't started.
- The planner makes tasks under the network waits (with the request's own flags, so iOS holds them until the network
  allows) but never under deadwax's or the sign-in's; a task out stays out under any wait but a sign-out's; at most 100
  tasks out.
- A download answered 401 asks /me (the background session never goes through DeadwaxClient's 401 hook) and holds
  every download under that session for a minute - else the plan would make the refused task again at once.
- Resume data is spent on the task made from it (cleared from the row at once), so data that won't resume can't loop.
- `OfflineRule`: a failed probe while deadwax already isn't online is unreachable at once (the path back, a pull).

**Verified here**: the whole DeadwaxKit package on macOS (Core's new suites; the offline renders: a downloaded copy
plays the samples its stream does, Off and at -6.02 dB, an album of copies joins sample-exact, the verifier matches
the 16/44.1 and 24/96 fixtures, finds the changed sample, says "by size" with no MD5, and hashes exactly what FileSource
decodes); the unsigned device build with no new warning; check_project.py; the sims; tests/test_source_bytes.py,
test_ios_contract.py (no route added) and test_ios_install.py (the verifier's fixtures are make-test-album.py's, and
libsndfile hears what their MD5s say). **Not run**: Linux (no toolchain on this Mac) - ios.yml installs
libsqlite3-dev first. **Nothing of the App half has run**: no simulator, no phone.

**What only the phone can tell** (the spec's checks 1-12 and section 11, plus): whether the relaunch delivers a force
quit's cancels with `NSURLErrorBackgroundTaskCancelledReasonKey` and resume data; whether Navidrome's raw stream sends
a validator (no resume data without one - then the 2.1.x patch on main is a strong ETag on the raw relay, not built);
whether a resumed task's `countOfBytesExpectedToReceive` is the rest (progress adds what came before on that
assumption); how long a check takes on a 24/192 album (Debug's `checkSeconds`); that a locked phone opens a downloaded
next song (file protection); the kept /me launch in Airplane Mode.

**Left for part 2**: every screen - the album page's control, ring, hero line, rows, menus, footer and notices; Now
Playing's ••• (Download, Download Up Next) and its notices; Info's Plays from; the Library's Downloaded list and the
offline root swap, the gate's Downloaded row, the marks on every Albums screen; You > Downloads and its row; the
offline banner (`showsOfflineBanner()`, after the inset round); Debug's Downloads section (the model has its data);
the player's offline skip (`PlayerWords.afterEngineFailure`'s `notOnPhone`, its notice words are in DownloadWords) and
no prefetch offline; the album page reading its kept answer offline (3.7); Up Next's marks (after its round);
`queue_pending` (7.6's queue saves kept - the table is there, ResumeController isn't wired to it yet).

### Part 2: the screens (p2/downloads)

Every place a download is asked for or shown, on part 1's model, to the spec's sections 1 and 3-7.

**What was built**:
- **The marks** (`App/Downloads/DownloadControl.swift`): `DownloadRing` (drawn - SwiftUI's circular ProgressView is a
  spinner on iOS whatever its value - a quiet track, the accent arc from twelve o'clock, round caps, a quarter
  second's move, none with Reduce Motion; the control's stop square), `DownloadMark` (one slot: a symbol, or the ring
  in the frame that symbol takes at the font, so a state changing moves nothing beside it and grows with Dynamic
  Type), `DownloadBar` (the Requests board's: --dw-track, its inset shade, --dw-border, --dw-bar-purple; amber and full
  over the limit), `AlbumDownloadControl` (the bar's control: the accent arrow downloads at once, every other state a
  menu from the control titled in words, `menuOrder(.fixed)`, VoiceOver "Download" with the album's line as its value,
  `.updatesFrequently` while fetching, the Large Content Viewer) and `DownloadMenuSection` (2.5's items with their
  symbols, a failed song's reason as the section's header). Palette gains `amberIcon`, `off` (0.45), `barTrack`,
  `barEdge`, `barFill`.
- **The album page** (3): the control before the •••; the hero's line under the badge (amber for didn't); each row's
  slot before its time - on every row once any song has a state, on none otherwise - with its words for VoiceOver and
  the song's download items as its actions; the menus' download section; the footer's "on this phone" line; the end
  of a download asked from the page announced while it is on top. **Offline (3.7)**: the kept answer drawn first (an
  album with songs here opens at once, online too), songs not here dimmed and their play disabled, Play and Shuffle
  and a row's tap and Play Next/Last taking only what is here, the mine block hidden, "This album isn't on this phone"
  in place of the songs; a pull asks Reachability; coming back asks deadwax again. An album gone from the collection
  with songs here keeps its kept answer, says so under the hero, and offers only Remove (`AlbumModel.goneButHere`).
- **Now Playing** (4): its ••• gains the playing song's items and Download Up Next (two or more, never paged), every
  item with its symbol, the button's name "More: info, go to album, download"; `player.notice` drawn in its top row as
  an overlay on the chevron's row. `PlayerModel.say` announces (Notice only draws). **Info** (4.4): Sound's "Plays
  from" (what is heard: streamed with "Stream even when downloaded"), Debug's "On this phone".
- **The Library** (5): `AlbumsScreen(list:root:)` (`AlbumList.downloaded` beside `.scope`) - Downloaded drawn by
  `LibraryModel.drawnDownloaded` from `DownloadModel.downloadedAlbums`, its own empty note, no load, a pull asking
  Reachability; the root's places (`PlaceGroup`/`PlaceRow`: All music, and On this phone > Downloaded with its count
  once anything is asked for); every tile and row's mark at the end of its artist line, outside the artist's Text;
  Downloaded's third line; the dim and "Not on this phone" offline; RefreshProblemNote not drawn offline.
  `LibraryView` keeps Core's `LibraryRoot` (changed only off screen: another tab, a page pushed, the app in the
  background) and consults the gate only while deadwax answers; the gate's screen gains the Downloaded row.
- **You** (6): `DownloadsRow` between Playback and Account; Account's footnote gains "Your downloads stay..." with
  anything here; **You > Downloads** (`App/Downloads/DownloadsScreen.swift`) - Storage (the amount and its rest in one
  Text, the bar, the usage line, the amber over-limit line, the limit's menu Picker, other accounts with Remove asking
  first, the store's problem), Download over (Normalization's radio group; the footer's now line amber while something
  waits for the network), Downloading (by album, the bar while fetching), Didn't download (the reason, Try again, Try
  all again as a row), Downloaded (largest first, the verdict trailing, under the size line at accessibility sizes),
  Remove All (its dialog from the button), the empty state, the last footer. Each album row is one VoiceOver element
  ("Dummy, Portishead, 12 songs · 412 MB, Checked"), its swipe Remove; Try again a row's action. **Debug** (6.9): a
  Downloads section; "Stream even when downloaded" moved into it.
- **Offline** (7): `OfflineBanner` (`showsOfflineBanner()`, beside `clearsPlayer()` on every tab root and pushed
  page: one line in MainTabs.swift, one in Routes.swift); the player's skip (7.3): `PlayerModel.failed` asks first
  whether deadwax is out of reach and the song not here (`playsHere`: a download, or a whole stream-cache copy), then
  Core's `OfflinePlay.after` - skip to the next song here with the run-counted notice, else stop paused on it with
  "Not on this phone - it plays once deadwax is back." as its error line; the engine link's `ReachBox` makes a song
  with no copy fail at once offline (no 8 s wait for a request nothing answers); no prefetch offline.

**Departures from the spec, and why**:
- **The ring is drawn in the hidden symbol's frame**, not at a fixed 9 or 13 pt: the dotted mark, the ring and the
  filled mark then take one frame at every text size, and nothing beside them moves as a state changes.
- **`notOnPhone` is not a `PlayerWords.Failure` case** (the spec's 7.3): `Failure` mirrors the engine's
  `AudioFailure.Kind` by raw value, and its `allCases` is pinned to the engine's five by ScreenPlayerTests. The rule is
  `OfflinePlay` (Core, tested), consulted by the app before the engine's failure words.
- **The song tapped in Up Next stops on itself** offline rather than being passed over (`chosenKey`): passing it would
  play something the listener didn't ask for.
- **A whole stream-cache copy plays offline too** (the player's `playsHere`): it is the same file. The album page's
  dims and Play still go by downloads alone - the cache may be emptied at any moment.
- **Downloaded lists albums on their way too** (5.1's tile states need them), their Recently added the moment they
  were asked for until their first song arrives.
- **A kept album answer whose song sizes changed** on deadwax (a re-tag, a new file) drops that song's copy and asks
  for it again, so the copy and the length check never disagree (`DownloadModel.albumAnswered`).
- **The root's first look waits for the phone's path** (`Reachability.pathKnown`, with a 1.5 s fallback): the app
  opening in Airplane Mode must start on Downloaded, and `LibraryRoot` holds whatever it first draws while on screen.
- **The gate isn't consulted on a check that failed because deadwax didn't answer** (`Checked.offline`), even once
  deadwax is back - the albums kept on disk draw while it is asked again (`libraryShown` on coming back).
- **The banner has a chevron** (rotating as it opens): a tap opening it needs a sign that it opens.
- **The root's row while it is Downloaded reads "Albums" without a library of your own** (the spec: "All albums"):
  it is named as the page it opens is titled.
- **Other accounts' bytes sit under the row's name**, not as its trailing value: the trailing edge is Remove's, and
  three things on one line wrap badly at large sizes.
- **Didn't download's reason is drawn as ErrorNote's split, not ErrorNote itself**: the row is one VoiceOver element
  (the reason in its label, Try again its action), and the raw words for whoever runs deadwax are their own
  disclosure under it, as ErrorNote draws them.
- **With the store unreadable**, You > Downloads draws no lists (not "Nothing downloaded yet", which would be wrong).

**Not built** (here): Up Next's marks and dimming (4.3: they waited for the Up Next round's merge); `queue_pending`
and the offline launch's kept queue (7.5's last bullet, 7.6's queue saves). Both built in the finishing round, below.
Server additions named, not built (a 2.1.x patch on main): a strong ETag on the raw stream relay, should the phone
find no resume data after a force quit (check 5).

**Verified here**: the whole DeadwaxKit package on macOS (603 Core tests, OfflinePlayTests among them; 93 engine
tests, the downloaded copy rendering its stream's samples); the unsigned device build, BUILD SUCCEEDED with no new
warning (appintents' "Metadata extraction skipped" is the app's as before); check_project.py; the ios sims;
tests/test_source_bytes.py, test_ios_contract.py, test_ios_install.py. **Assumed, not seen**: everything drawn -
nothing has run on a simulator or a phone. What only the phone can tell is the spec's section 10 (checks 1-17) and
section 11, and docs/ios.md's "Phase 2's checks".

### Part 3: the review (p2/downloads)

An adversarial pass over parts 1 and 2 (`b4ee591..76ebf0e`) against the spec and Apple's documented behaviour of a
background `URLSession`, file protection, `NWPathMonitor` and the request's network flags. What held, fixed in
`DownloadModel` unless named:

- **Mobile data under Wi-Fi only, from resume data.** Part 1 remade the tasks out when Download over changed, but a
  song waiting with resume data (one cancelled, or stopped by a force quit) kept it - and resume data carries the
  request it was archived from, `allowsCellularAccess` and the rest, so its next task resumed under the old setting.
  Changing the setting now lets every waiting song's resume data go first (`dropResumeData`), and resume data that
  arrives from a task made under the other setting (a cancel racing the change) isn't kept (`madeUnder`).
- **A session's cookie on disk.** The same archived request carries the `Cookie:` header. Signing out kept it in the
  rows (plaintext, under `completeUntilFirstUserAuthentication`); signing in again tried it, was refused, and held
  every download a minute for the 401. Now `close` drops every row's resume data with the person (one transaction),
  and the same person signed in under a new session drops what the old one made (`resumeSession`). A song's bytes
  so far are the cost; its download starts again.
- **The limit overrun by songs asked from the queue.** A queue entry carries no size, so Now Playing's Download and
  Download Up Next made records the planner counted at a transcode's 320 kbps estimate - a FLAC is about three times
  that - and whose copy was checked against no length. Now a new record takes its size from the kept album's answer;
  without one, its task waits for that answer (`sizeComing`, never past it: no answer lets it go at the estimate),
  and `keepAlbum` keeps its answer through `albumAnswered`, which fills a size that was never known as well as one
  that changed. A kept copy whose length isn't deadwax's size is fetched again; one whose size was merely unknown is
  left alone.
- **The streaming cache's copies ignored the limit.** They were copied in as they were asked, past the planner -
  over the storage limit and into the phone's last 2 GB. They are now copied when the plan lets the song go, in
  `plan()`, in place of making its task; one that doesn't hold (its length, its move) is simply downloaded.
- **A copy here set back to wanted.** A cancel (the plan letting a task go, or Download over's remake) awaited
  `session.cancel` and then wrote every song it named as cancelled - including one whose file had arrived meanwhile,
  which was then fetched again (and its `done` row lost). The writes now leave a song that isn't fetching any more.
- **An older task's whole file thrown away.** After a relaunch, a song can have a new task while an old one's end is
  still to be delivered (iOS delivers a finished task's event when it relaunches the app, possibly after the
  launch's settle asked again). Its file was deleted and the song fetched twice. A whole file of the right length is
  now taken and the newer task cancelled; anything else is dropped as before.
- **`live` cleared by another person's task**: a task of another account on the phone ending removed the signed-in
  person's task id for the same song (two people downloading one album). Only the current store's events touch it.
- **A check that never ran.** `queueCheck` started the sound check at once, from inside `arrive`, before the record it
  returns was written: the check found no `done` record and dropped it, leaving the copy "Checking…" until the next
  launch. It starts on the next turn now.
- **An album removed while its answer was out** was kept anyway (its cover written, its row back); a cover written
  after a sign-out landed in the next person's store. Both guarded; a kept cover is now drawn at once (`reload`).
- **"Used" left the covers out**: 6.3 and 8.5 say used is the songs' bytes and their covers'. `bytesHere` adds each
  kept cover's length (read once).
- **Plays waiting counted from the wrong store**: a send that outlived a sign-out wrote the old person's count over
  the new one's.
- **Covers asked of a deadwax that can't be reached** (`CoverCache`, wired in `DeadwaxApp`): every tile not on the
  phone asked and waited for its answer, the transport's silence feeding the banner. Offline, a cover is the phone's,
  the in-memory cache's, or the empty square (5.4, Open question 13); those that failed are asked again once deadwax
  is back, the next time they are shown.
- **VoiceOver's Downloading row** said "..., 4 of 12 songs, Downloading, 40 percent"; 6.8's is "Dummy, Portishead, 4
  of 12 songs, 40 percent" - its section already says it. `DownloadWords.percent` (tested).

**Left as they are**:
- **A kept play may be sent twice**: 7.6 forgets a play only on a 200, so a send that reached deadwax but whose
  answer was lost goes again. Taking a scrobble of the same song at the same `time` once would be a server-side guard,
  a 2.1.x patch on main - named, not built.
- `chosenKey` (the Up Next song that stops on itself offline) is cleared only by the next failure or skip, not by
  a jump that played - harmless: it names a song the listener chose.
- Several screens following progress at once each poll the session four times a second (cheap; the session answers
  from memory).
- The album's answer, cover and loudness are asked over mobile data under Wi-Fi only: small foreground requests on
  the app's own session, as 8.3 has the cover; only the songs' tasks carry the setting's flags.
- `queue_pending` and the offline launch's kept queue: part 2's "Not built" (built in the finishing round).
- `iostraces.sim.cjs` fails here as it does on `b4ee591` (`export-traces.cjs`'s `stateOf`, under Node 20.12 - below
  the repo's `^20.19`); nothing it reads changed on this branch.

**Verified here**: the whole DeadwaxKit package (603 Core tests, 93 engine tests); the unsigned device build, BUILD
SUCCEEDED, no new warning; check_project.py; the ios sims but iostraces (above); tests/test_source_bytes.py,
test_ios_contract.py, test_ios_install.py. **Assumed**: Apple's documented behaviour each fix rests on (resume data
archives the request, cookies and network flags included; a relaunch delivers an old task's end) - none of it has run
on a phone.

### Merged into ios with Up Next's History

One change in the merge itself, in `PlayerModel.jump(to:)`: Phase 2 marks the song a listener taps in Up Next
(`chosenKey`), so that offline a tapped song not on the phone is stopped on with its reason rather than passed over
(OfflinePlay.chosen). Up Next's History, merged first, plays a History row's song again as a new entry under a new
key - so after a jump that took, `chosenKey` is read from the controller's queue (the entry now playing), not taken
from the row tapped. Reasoned from the code; not seen on a phone.

### The finishing round: the queue kept on the phone

Part 2's first "Not built" (7.5's last bullet, 7.6's queue saves), built in Core's ResumeController - the rule, tested
on Linux - with the App only wiring it.

- **What is kept** (`QueueKept`, Core): the queue this phone last saved or took, as GET /queue would answer it had
  deadwax kept this phone's save - the window a full save sends, its songs (`Song(track:)`, with the size the player
  holds), this phone's own record - so `resumed()` puts it back exactly (Up Next's account, the levels, the second)
  and says nothing. Plus the rev and the answer's signature this phone last knew, and `unsent`. One `queue_pending`
  row in the person's download store: `kind` `unsent` or `sent`, the body its JSON. Written as each save is sent
  (unsent - the app may be closed, or the network gone, before the answer), as a save is answered (sent - only while
  the row is still that save's: a newer one kept meanwhile stays unsent), and as a queue is put back (taken). The
  break-glass admin's first save answering no rev forgets it.
- **Departure: a sent save doesn't delete the row; it marks it sent.** 7.5 needs "the last queue this phone saved or
  took" for an offline launch, and a deleted row would leave Airplane Mode starting empty whenever the last save had
  gone through - nearly always. The unsent save is what's cleared.
- **The open** (`start`, as before: the queue empty, deadwax asked). Not answered - whatever the failure: offline,
  deadwax or Navidrome away, a 401 - the kept queue is put back paused, no notice, as the baseline (nothing saved for
  it until it is played or changed; its ids_rev not believed, so the first save after is full). Answered, with a save
  kept unsent: a queue another device or app saved since this phone last saved or took - `newer()` with the kept rev,
  and not the answer it already took (the kept signature; so a Symfonium queue this phone picked up before playing on
  offline isn't "new") - wins, taken as resume takes one, and the kept save is let go; else the phone's own is put
  back and sent at once, after the GET. Answered with nothing unsent: taken as Phase 1 takes it.
- **The return** (`front`): with a save kept unsent and none out, deadwax is asked FIRST - before Phase 1's "changes
  not yet saved are saved, nothing asked" - and the same rule decides. Within one run too: a save that failed offline
  isn't sent blind at the next return; a Mac that played since wins. Only open and return wait for the ask: a save
  due while playing, at a pause, a wait or the background goes as Phase 1's do (the queue playing here is the
  present) - so a phone paused offline, then put in the background once deadwax is back, sends its save there without
  asking. Named, left: asking first there would need the GET inside the background task.
- **A 401** holds it: the row stays unsent in that person's store; a return asks and sends nothing while the session
  is the one refused; the same person signed in again (the session moves) sends it at the next return. Someone else
  has their own store, so their controller never sees it.
- **The App** (`ResumeKeep`, PlayerModel+Resume.swift): reaches the store through `DownloadModel.keptQueue/keepQueue`
  by the (server, person) the controller was made for - `DownloadModel.store(server:person:)` opens it aside when the
  model hasn't yet (the two watch the server separately, in no set order). Sizes come from the player's shelf, and a
  row read is shelved, so after a relaunch Info has its songs and the stream cache's whole-copy check its sizes.
  `DownloadStore.person(_:)` names whose store /me means, for both.

**Verified here**: ResumeKeptTests (16: kept unsent and sent; an older save's answer leaving a newer kept save unsent;
a queue taken kept; the open with the Mac newer, with this phone's own older save, with the Mac older than this
phone's last, with another app's queue taken before and saved since, with the kept queue already sent; an offline
launch with and without one kept; the return after an offline launch, ours and the Mac's; a save that failed within
one run asked about first; the 401; the break-glass; the row's round trip through DownloadDatabase and back through
`resumed()` exactly) and every ResumeControllerTests case unchanged (no keeper: the web's rules). **Not seen**: any
of it on the phone - Phase 2's checks 17 and 18 (docs/ios.md).

### The finishing round: Up Next's marks and dimming

Part 2's other "Not built", designed first as the spec's 4.3.1 (the design, in full) and built to it, in
`UpNextScreen.swift` alone - no Core change: the rules it draws are 3.3's (`DownloadWords.mark`, `songLine`,
`notOnPhone`, `SongDownload.isHere`), already tested.

- **The mark**: the album row's `DownloadMark` at `.caption`, at the end of the row's line ("Portishead · Dummy"),
  outside its words and fixed - the Library row's `ArtistLine` pattern, because Up Next's rows have that shape (cover,
  title, line) and no time column; so no slot is held on rows without a state. After the title when there's no line.
  On every song Up Next shows - History, the card, Playing Next, the list - in Edit too.
- **Dimmed offline**: by downloads alone, as the album page's rows (the player's `playsHere` also takes a whole
  stream-cache copy, but its check reads the disk and touches the copy's date - not for a row as it draws). Out of
  Edit, a dimmed row is disabled; in Edit only its words and mark dim, its minus and handle work. The card is never
  dimmed.
- **VoiceOver**: the state as the row's value after its unchanged name ("Roads, play now, Downloaded"; "Not on this
  phone" and iOS's "dimmed" offline); Edit's element the same; the card's its state. No download action anywhere.
- **Cheap**: `UpNextSongMark` (a View) and `UpNextDownload` (a ViewModifier, in four parts: a tappable row, an Edit
  row's look, its words, the card) each read the models for one song, so progress and arrivals redraw only them, never
  the body that builds `upNextView`; one `followProgress()` for the sheet in its `.task`.

**Verified here**: the unsigned device build, BUILD SUCCEEDED, no new warning; the sims; check_project.py; the iOS
pytest files. **Not seen**: anything drawn - no simulator, no phone. What only the phone can tell: the spec's checks
18 and 19 (docs/ios.md's 19 and 20) - the mark's place at the largest text size and in Edit beside the handle, that a
dimmed disabled row still takes VoiceOver's focus and reads "dimmed", and whether the List redraws only the marks
while a download's ring fills (assumed from Observation's per-view tracking, not measured).

### The finishing round: app 0.3 (3)

The app is **0.3 (3)**, Phase 2's downloads, as the spec planned for its merge (its section 1): `Base.xcconfig`'s
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, pinned with it in `check_project.py` (MARKETING_VERSION, BUILD),
`ios.yml`'s check of the built Info.plist and `tests/test_ios_install.py`'s read of the real xcconfig - as 0.2 was.
The guide (its opening, install.sh's line, About's App row), ios/README.md and the two doc comments giving About's
row as an example say 0.3; the comments naming "James's check of 0.2 (2)" are history and stay. `src/__init__.py`'s
`__version__` is the server's and wasn't touched.

**Review** (the finishing round's three commits). Two fixes. (1) **Resume was never made at a launch from the kept
/me** (part 2's 7.5): ServerModel is `.ready` from it before PlayerModel watches, and /me answering the same - the
`@Observable` setter skips an equal `Equatable` value (checked in this Xcode's macro expansion) - or not at all
offline changes nothing PlayerModel watches, so no queue was put back at any launch after the first, and the offline
launch's kept queue never could be. PlayerModel now runs `serverChanged()` once at the end of `connect(downloads:)` -
there, not in `init`, so the controller reads the person's kept queue through `downloads`. Build only; App code has no
test target. (2) **`settleKept` let the kept save go when `take` declined** - logins off with this phone's queue
paused here, the player refusing, an answer `resumed()` can't read: the row said sent, nothing was sent, nothing
taken. Now only a queue put back lets it go (`take` says whether it did); otherwise the phone's own is sent, as
Phase 1's return would have saved it (ResumeKeptTests, logins off: fails before, passes after). Measured, left: the
row's rewrite at 2000 songs (700 KB), a debug build on this Mac, is ~12 ms at a send (toSave 5, encode 6.5, write 1)
and ~7 ms at its answer, on the main thread, and ~13 ms to read as the controller is made; an album's queue is a
hundredth of it. Held as built: the `write == keptWrites` guard, the store opened aside by (server, person), Up Next
against 4.3.1 / 3.3 / 7.4 (a progress tick redraws every visible mark and modifier - Observation tracks `received`
whole - never the list's body). For James: within one run, one failed save (online too) makes the next return ask
first, so a queue another device saved since wins even over edits made here after it, which Phase 1's return would
have saved; a phone with no rev yet counts any other device's record as newer; an offline launch's queue appears only
once the open's GET fails - at once in Airplane Mode, up to the transport's 8 s with a network up and deadwax out of
reach (Reachability isn't asked).

## Lyrics (app 0.4)

The spec, its design review, and what was built with every departure from it are in **notes/app-lyrics.md** (section
4, and "Built on the iPhone (app 0.4)"); here, the map. Built on `ios` after Phase 2's finishing round and the merge
of main's 2.1.4-2.1.6 (the route, 2.1.5; the web's view as reviewed, 2.1.6), in four commits: Core with its fixtures,
the store, the App, the version.

- **Core** (`DeadwaxCore/Lyrics.swift`): `LyricLine`, `SongLyrics` and `LyricsAnswer` (the route's answer, and its
  body as it came); `LyricsWords` (2.1, verbatim); `Lyrics`, lib/lyricsView.ts's rules ported - the clock, the lit
  range (a binary search), the intro, the dots, following, the end room, a line's VoiceOver value, the next song's
  ask - plus the phone's own: the button offline (`have(_:online:)`), what the face shows (`face`, `shows`), the
  backdrop and dim-line opacities, and `failure(_:)` (a deadwax with no lyrics route); `LyricsKept` (the 50, least
  recently used first); `LyricsHold` (the listener's scroll phases and VoiceOver's focus as one value, and the wait).
  `Routes.lyrics` (24 routes); `DeadwaxClient.lyrics(songID:ifNoneMatch:)`.
- **The store**: `DownloadDatabase` version 2 - the `lyrics` table and the `song_lyrics_go` trigger on `song`;
  `putLyrics` keeps nothing for a song no longer in the table. `DownloadModel` asks as each song's file arrives and
  fills in at every settle while deadwax can be reached; `keptLyrics(_:)` and `lyricsAnswered(_:body:etag:)` are the
  player's way in.
- **The App**: `Models/LyricsModel.swift` (made in DeadwaxApp beside the other models, reset with them when the person
  changes); `Player/LyricsView.swift`; Now Playing's footer button, face and backdrop; `PlayerModel.clock()`, a read.
  Nothing under `DeadwaxAudio/` changed, and nothing on the lock screen.
- **Held to the web and the server**: export-lyrics-vectors.cjs and ioslyrics.sim.cjs (the table in "How the ports
  are kept in step with the web"); `ios/scripts/lyrics_answers.py` writes `Fixtures/lyrics/answers.json` from
  src/lyrics.py's `song_lyrics()`, which tests/test_ios_contract.py holds case by case, with `SongLyrics`' fields.

Nothing of it has been seen on a phone: notes/app-lyrics.md section 6's P1-P12 (in docs/ios.md as "Lyrics' checks")
and section 7 are what James's iPhone answers.

**The version: 0.4 (4)** (the spec's Open question 11 - a version says what shipped, not which phase; the plan's
Phase 3 ships as 0.5). Pinned as 0.3 was: `Base.xcconfig`'s `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`,
`check_project.py`'s MARKETING_VERSION and BUILD, `ios.yml`'s check of the built Info.plist, and
`tests/test_ios_install.py`'s read of the real xcconfig; the guide's title, opening, install.sh's line and About's App
row, ios/README.md, and the two doc comments giving About's row as an example. `src/__init__.py` wasn't touched.

## The turntable

The turntable and the speed fader, on the iPhone: the design spec is notes/ios-specs/turntable.md, built in four
slices (its 7.1-7.4) on the `ios` branch. Each slice's departures are written into the spec's own sections as **As
built** paragraphs; this is the account of what was built and what was seen.

### Slice 1: Core (2026-11-12)

The physics, the deck's rules and the voice, in DeadwaxCore, held to the web's own TypeScript run by
`ios/scripts/export-deck-vectors.cjs` (the table in "How the ports are kept in step with the web"). No screen, no
audio host, nothing in ios/App or DeadwaxAudio; ui/src untouched; deck.sim.cjs changed only by its fakes moving into
ui/test/deckHarness.cjs, its output byte for byte what it was.

**What was built** (ios/DeadwaxKit/Sources/DeadwaxCore/):

- `DeckMaths.swift` - the eight transcendentals behind an instance protocol: `PlatformMaths` (libm, with JavaScript's
  pow edge cases) and `RecordedMaths` (the web's answers by input bits, every call counted and hashed, one the web
  never made answering NaN and failing the test); `JSMath`'s round, min, max, fround, ToInt32, sign (spec 4.2).
- `Platter.swift` (platter.ts: the plans, phases, the hand's speed, the release), `TurntableGeometry.swift`
  (turntable.ts: the drawing, arm, drags, previews, the disc; `TurntableLayout`; deckClock.ts's pointerSamples),
  `PlaySpeed.swift` (playSpeed.ts), `TurntableWords.swift` (the spec's 2.9 and Debug's rows),
  `TurntablePalette.swift` (2.14, each colour named with its token).
- `DeckVoice.swift` - deckVoice.ts line for line: the messages, the follow filter, the Hermite read, the fit, the
  squeeze, the DC blocker, the limiter, the reports; rendering into the caller's buffers, allocating nothing per block.
- `DeckRules.swift` - deck.ts's Deck class method for method, over `DeckHost` and `DeckClock`; the phone's handover
  lead (`handoverLead`, `resumeAsked`, `releaseLed`) and `HandoverTiming`, the spec's 3.5 arithmetic.
- `TurntablePress.swift` - Turntable.tsx's handlers and NowPlaying's turntable toggle, over `PressDeck` (DeckRules)
  and `PressHost`.

Tests (DeadwaxCoreTests): JSMathTests, PlatterTests, TurntableGeometryTests, PlaySpeedTests, TurntableWordsTests,
TurntablePaletteTests, DeckFixturesTests, DeckVoiceTests (A and B), DeckRulesTests, HandoverPlanTests,
TurntablePressTests. Fixtures/deck/: 61 files, 2986 KB of the 3 MB.

**Departures** (each in the spec's section, as built):

- **Press traces not exported** (7.0, 3.1): `press/` holds only the handlers' hashes; TurntablePress is held by eight
  hand-built cases. The traces through a mounted Turntable are still owed - built in the review, below.
- **The budget** (7.0): 120 Hz for five of the eight motions; the motions' play trimmed to 500 ms before and 3 s
  after; the 416 case under reduced motion; a case's effects hashed per 512 when over 400; the voice's eight cases
  its own, not every rules case's messages.
- **Effects numbered by their input** (7.0): a mutation (the refresh's speed) passed with every effect in order and
  one ask at another position report; numbered, it fails.
- **`heard` carries pos, rate and gain only** (7.0) - the fields the rules read.
- **DeckHost and DeckClock** (3.3): the host carries `voiceMade`, `sleepAudio`, `closeAudio` and `post`; the clock
  is its own protocol; `window` answers through a `Result` callback, not `async throws`; `.offline` is retried,
  `.undecodable` and `.channels` refused.
- **The lead's paths** (3.5): `resumeAsked` also cleared by any new plan; `holdsAcross` left to the host and Debug;
  the resumed plan's end posts only the hold drive.
- **DeckMaths an instance protocol** (4.2), the maths-free constants in enums and the sums in small generic structs.

**Verified** (this Mac, Xcode's toolchain):

- DeckVoiceTests A: 72 runs (8 cases x 48 and 44.1 kHz x blocks of 128, 333, 512, 1024 and 1) bit for bit - each
  span's hash, each report, the three whole stretches, the Math calls in the web's order. B: the platform's libm
  gave the web's output exactly (worst 0, so -inf dBFS; the bound is -100).
- DeckRulesTests: 42 cases, 39,929 effects, equal to the web's with RecordedMaths; with the platform's libm the whole
  cases' doubles within 4.2e-16 relative (the bound 1e-9), the hashed cases by count.
- HandoverPlanTests 7/7, TurntablePressTests 8/8, and the pure suites.
- Mutations, each alone: the voice's 6 and the platter's and geometry's 2, all caught; DeckRules' 11 against the
  replay, 8 caught - the 3 survivors TAKE_BACK_S written as 0.1 (it is 0.09999999999999999; equal at the traces'
  magnitudes), `>=` for `>` against stampedTo (unreachable: frames run before inputs at the same ms) and the
  angle's product regrouped (exact for these speeds); the lead path's 5 and TurntablePress's 3, all caught.
- iosdeck.sim's `--check`: the 61 files are what the web's code makes now.
- The whole package (`swift test`: 685 tests in 94 suites, and DeadwaxAudio's 93 in 3), the app's device build
  (`xcodebuild … generic/platform=iOS`, no warning from the code; check_project.py ok), all 76 sims, and the five
  iOS pytest files (125 passed). Their first run caught two things the earlier commits broke: debugRows' health was
  `struct Health`, which test_ios_contract.py's reader takes for the server's (renamed `DeckHealth`, the web's own
  name), and the three .f32 stretches failed test_source_bytes.py (`.f32` added to its binary suffixes: raw Float32
  audio, base64 would pass the 3 MB).

**Assumed, not seen**: Linux - by reading (the files import only libm), with ios.yml's ubuntu job to say; that
glibc's libm keeps test B inside -100 dBFS (Darwin's happened to equal V8's for the voice, not for all the
platter's); CI's Node 22 answering V8's Math as Node 20.12 did; the order TurntablePress makes its calls in, beyond
the hand-read cases; the lead path against a real engine (slice 2's HandoverTimingTests).

**For a reviewer**: the lead path in DeckRules (`releaseLed`, the `resumed` branch of `planEnded`, the judge's early
fire in `handOver`'s `done`) is in no web trace; TurntablePress has no trace at all; the dropped 120 Hz motions.

**Review** (2026-11-12, one reviewer, the same day). What was asked: the press traces, the lead path, the dropped
120 Hz motions, test_source_bytes.py's `.f32`, and the rest - Linux, the JS helpers, `DeckHealth`, Node 22.

- **The press traces, built** (spec 7.0's as-built): `press/` now holds 13 traces made by mounting the real
  Turntable and NowPlaying over the deck harness and a fake player and driving them with pointer events and keys,
  every call the handlers make recorded in order with what it returned and the deck's state after it, and the drawn
  turn and the silent line as they change. TurntablePressTraceTests replays them: every call bit for bit with the
  web's Math, again with the platform's (within 1e-9), the drawn turn and the silent line checked after every
  input. 74 files, 3056 KB of the 3072 - 16 KB left. The one patch to the compiled web is at Turntable's render, to
  tell the exporter what it drew.
- **Two places TurntablePress wasn't the web, found by the traces and fixed** (spec 3.1's review): a second finger
  started a press of its own (the web takes the primary pointer only), and a lift whose drag a song change dropped
  ran no click (a browser's click still comes, pausing the new song). Both are `following`, the touch the turntable
  follows. A hand test added for a release asking to play a song already playing (the web's never does, so no trace
  can say it), which a mutation had passed.
- **The lead path, two fixes** (spec 3.5's review): Reduce Motion's take held a take's 0.12 s where the song can
  take most of a second to be heard - it now holds HANDOVER_MAX_S until the judge; a plan silent at its early resume
  and sounding by its end had no judge and no hold - the plan's end now makes both. HandoverPlanTests 7 -> 12.
- **Mutations**, each alone against the new tests, all caught: TurntablePress's 7 (the grabbed offset, the clamp
  from drawnAt, the second finger, the click after a song change, the silent line, the hand's turn, the play
  asked of a playing song - the last by the hand test only) and the lead path's 6 (the take's hold, the late judge,
  `startPlan`'s clearing, the late judge at `plan.x`, `done` leaving the plan, a second resume at the end).
- **The 120 Hz half, quarter and double: not brought back.** They are steady1 at other speeds, which 60 Hz holds
  for all three and 120 Hz for steady1; nothing in the rules branches on the frame rate and the speed together. They
  can't come back hashed: what makes them big is their inputs (each hand sample, about 53 KB a case), which the
  replay must have whole - the effects already hash past 400. Room for them would come from porting
  lab/motions.ts and its seeded generator to the Swift test (the inputs made on both sides, like the windows), or
  from trimming turntable.json's 24 drags (438 KB).
- **`.f32`** in test_source_bytes.py narrowed from a binary suffix anywhere to `.f32` in
  Fixtures/deck/voice/ alone (`BINARY_IN`); a `.f32` anywhere else is read as text and fails on its bytes, which a
  new test holds.
- **Node 22**: the exporter recomputed every Math answer with whatever Node ran it, so a V8 answering otherwise
  would fail iosdeck's --check on CI with nothing in the TypeScript changed. It now answers each call maths.json
  holds with the committed answer, and says when Node's own differs - which keeps maths.json and every file made
  only from recorded calls the same on any Node. About 32,000 calls are made with the recording off (the bench's
  motions, the harness's tone, the deck's frames between press inputs) and stay Node's: tried with sin, cos and exp
  one ulp off on half their inputs, --check failed on 22 files (48 without the guard), now naming the Math as why.
  Not seen on Node 22 then - since seen, and the check made to hold on any machine (below).
- **Read and found right**: JSMath's six helpers against 4.2 and ECMAScript (round's halves and -0, min's and
  max's zeros and NaN, ToInt32's modulo, fround through Float); `DeckHealth`, the web's own name, which keeps
  test_ios_contract.py's `struct Health` reader on the server's. Linux: the slice's Core files import only libm, but
  TurntableWords' `range(of:)` and `replacingCharacters` are Foundation's, compiling only because other files import
  it - it now imports Foundation itself.

**Checked** after the review: `swift test` 694 tests in 95 suites, and DeadwaxAudio's 93 in 3; the device build
(`** BUILD SUCCEEDED **`, no warning from the code) and check_project.py ok; all 76 sims (iosdeck: 74 fixtures,
3056 KB of 3072); the five iOS pytest files, 126 passed. **Still assumed**: Linux (ios.yml's ubuntu job, not run
here); Node 22's Math; the lead path against an engine (slice 2).

**A check that holds on any machine** (2026-11-12, after the merge into ios). CI's tests.yml failed iosdeck.sim on
ubuntu x64 with Node v22.23.4: jsmath.json, turntable.json and maths.json differed. The same Node on this Mac
(arm64, fetched into the scratchpad) changed a different set: maths.json, press/turn-back-past-the-start.json and
rules/motion-{ramp,scratch}-{60,120}.json. So what the exporter writes depends on the CPU as well as on the Node,
and byte-equal regeneration can't hold on every machine. The Swift passed either way: it replays maths.json.

- **A NaN is written as one.** x64's arithmetic makes 0xfff8000000000000, arm64's 0x7ff8000000000000, and V8 passes
  them through Math.min, Math.max and the arithmetic, but JavaScript can't see a NaN's sign. The exporter writes
  every double and Float32 through `setF64` and `setF32` - the hex, the base64, the hashes of the voice's output and
  reports, the Math table's keys and its run hashes - and they write any NaN as 0x7ff8000000000000 (a Float32's as
  0x7fc00000). The Swift tests write theirs the same way (`RecordedMaths.bits`, which also looks up and hashes a call
  by it, so a NaN made on x64 Linux finds the table's; `DeckFixtures.bits` for a Float32; TraceWorld's `hex`), held
  by DeckFixturesTests' `everyNaNIsOne`. On this Mac it changed no committed byte. A stand-in for x64 (a preload
  giving every Math function's NaN the sign bit) reproduced CI's failure exactly with the old exporter - jsmath.json,
  turntable.json, maths.json - and passes the full check with the new.
- **The maker, recorded**: `made.json` holds the Node, platform and arch that made the fixtures (`made_on`: v20.12.2
  darwin/arm64, this Mac's /usr/local/bin/node) and the sha256 of the exporter and ui/test/deckHarness.cjs
  (`made_with`). Writing the fixtures makes the running Node their maker - so write them on it.
- **Two kinds of check.** --check still makes everything again in memory. On the maker's Node, platform and arch,
  every file must be the same byte for byte (a full check). Anywhere else, a differing file fails if its sources
  (`made_from`) changed, if it is new, missing or stray, or if no Math answer reaches it (EXACT: jsmath.json,
  tokens.json, voice/windows.json, press/handlers.json); a change to the exporter or the harness (`made_with`)
  fails everywhere. Otherwise it differs only by that Node's Math: listed, not failed (a sources-only check).
  iosdeck's PASS line names the kind that ran.
- **tokens.json is made from the tokens it reads, not from theme.css whole** (2026-11-13): its `made_from` is the
  sha256 of the tokens and their values. theme.css is every page's, and main's 2.1.8 added a token for You on a desktop
  that the turntable never reads - which made tokens.json and maths.json "stale" with nothing in them moved, and
  failed iosdeck.sim on CI (the second time; 06c4485 was the first). A token the turntable reads, or one it aliases,
  changing still fails it: tried both ways, an unused token added (passes) and --dw-tt-arm changed (stale).
- **Files that had no `made_from`** got one rather than being taken for Math's: jsmath.json the sha256 of
  `jsmathFixture`'s own text, voice/windows.json that of `recipeChannel` and `recipeWindow`, and maths.json every
  other file's together. jsmath.json and windows.json are also EXACT - nothing in them is a Math function's answer,
  and ECMAScript defines the rest - so a difference in them on any machine is a failure, not a note. The .f32
  stretches are judged by their case's .json.
- **Verified**: on Node 20.12.2 (the maker) the full check passes; on Node v22.23.4 arm64 it passes sources-only,
  with 68 files byte for byte and 6 differing by its Math alone (maths.json, press/turn-back-past-the-start.json,
  rules/motion-{ramp,scratch}-{60,120}.json) - V8 22 answers 13 of the recorded calls otherwise (exp 3, log 1, sin
  6, cos 2, atan2 1); with the x64 stand-in on Node 22 as well, the same. lib/platter.ts's MAX_SPEED changed from 24
  to 25: both Nodes fail (the maker's on every file it reaches, Node 22's as "its sources changed"); a comment added
  to the exporter: both fail. **Not seen**: x64 itself - Rosetta isn't installed here, so node-v22.23.4-darwin-x64
  wasn't run; CI's next run is the first.

### Slice 2: the deck engine and the window (2026-11-13)

The record gets its own engine (spec 4.3): a second AVAudioEngine whose AVAudioSourceNode renders Core's voice and
nothing else, into the main mixer at unity. It is separate because the song's engine stops its output on every pause,
which is exactly when the record sounds. The pieces:

- `DeckVoiceHost`, the render: plain numbers and pointers only. Messages come in through an SPSC ring (CAudioRing's
  new `audio_fifo`), windows go back through a return ring, and reports fold when their ring is full. The clock `L`
  is Core's `DeckLead`, and the deck's own EQRender runs after the limiter (eq.md 1.9).
- `DeckEngine`, the second engine, warmed once off the audio thread.
- `DeckWindows`: a window from a local file or from `/scrub`, on the 2 s grid with a 0.2 s pre-roll, converted the
  way the lane converts.
- `DeckTrial`: the run Debug plays.

The one change in ios/App is Debug's **The record's engine beside the song** (docs/ios.md, checks 0a-0c). Core gained
`DeckScrub`, `DeckLead`, `DeckRender`, `DeckPCM` and the `scrub` route (ROUTE_COUNT 27). The FLAC fixtures are in
DeadwaxAudioTests/Fixtures/deck (922 KB): make-test-album.py `--deck-fixtures`, and export-scrub-window.py for the
`/scrub` answer, cut by src/flac_ranges.py itself. tests/test_ios_install.py makes them again and checks them byte for
byte. The spec's "Slice 2, built" (under 7.2) has what was measured, each departure and why, and its questions.

**Measured here.**
- The source node is Core's voice bit for bit, over 32 runs of 8 cases.
- Windows at 22.05, 44.1, 48 and 96 kHz are the lane's frames bit for bit, and `P` against `2P` agree bit for bit.
- A `/scrub` window is the local file's, bit for bit.
- The seam off the grid: the lane at -91 dB and the voice at -78 dB against the exact tones.
- A 40 s window from 96 kHz peaks at 15.8-16.1 MB on the making thread, over six runs, against a bound of the
  window's 14.65 MB plus 2 MB. That leaves about 0.5 MB, so a CI runner whose AVFoundation buffers more would fail
  it there first.
- HandoverTimingTests: the song comes in 0.53 ms after planEnd + D, and its click comes out of both engines 28 frames
  apart, at a quantum of 32.
- Release: 0 allocations in 10,000 direct calls and in 1,000 framework blocks, with the canary seen.

**Mutations, each alone** (scratchpad's mutate.py: applied, the suite run, `git checkout`). All caught:

| Mutation | Caught by |
| --- | --- |
| D without the limiter's lookahead | The handover's clicks 68 frames apart |
| D without `L` | 996 frames apart |
| The offline clock without its lead | 1050 frames apart |
| The pre-roll's drop a frame long | The grid's bits, the length, and the seam (the voice at -0.9 dB) |
| The grid start a file frame late | The window's start, and the grid's bits |
| The window not levelled | The grid's bits, and 48 to 48's exact copy |

The grid-start mutation passes the seam test, at -79 dB. That is right: the window still says where it starts. The
seam test catches a window that is placed off from where it says.

**Verified**:
- `swift test`: 934 Core tests and 129 Audio tests.
- `swift test -c release --filter DeckRealTimeTests`.
- The unsigned iPhone Release build. It found a missing `import AVFAudio` that macOS doesn't need.
- check_project.py, the iOS pytest files, and every ios sim, with iosdeck's full check on Node 20.12.2.

**Not run**: check-linux.sh, which needs swift.org's Linux toolchain; Core's new files are Foundation-only, and ios.yml's
ubuntu job is their first Linux build. ios.yml itself hasn't run either: nothing was pushed.

**Only the phone can show**: checks 0a-0c, the real `E`, and the phone's "Window made in".

**Review (2026-11-13).** Four fixes, each with its own test:
- The deck's EQ state is made again at every start, so a restart is eq.md 1.9's fresh install and Off is bit-exact
  from its first block.
- `X-Deadwax-Window` refuses what a FLAC can't say, and the plan can't trap on a number from outside.
- Unread reports are capped at the ring's 64.
- The allocation hook is held by one suite at a time. Run alongside EQRealTimeTests, the window's 16.12 MB had read
  15.80, so the "15.8" above is probably that.

New tests cover full rings, a window's give-back and `L`'s slew in the render. The judgement on each area asked about,
and the questions left for slice 3, are in the spec's "Slice 2, built", under Review.

### Slice 3: the turntable on Now Playing (2026-11-13)

The record on Now Playing, as the web's turntable has it (spec section 2, 3, 4.6 and 6). It takes the hand and sounds
through slice 2's engine, and it hands the song back where the hand left it. App 0.6 (6).

- **Core**: `TurntableScreen.swift`, the screen's rules as pure functions. `TurntableFace` holds the web's numbers in
  points, held to the stylesheets by tests/test_ios_turntable_face.py. `TurntableFit` sizes the plinth. 2.8's states
  are `soundReady`, `silentLine`, `framesRun` and `engineWant`. `TurntableSettings` holds the two settings and the
  look and lyrics taps, and Debug's section has the web's rows in its order with the phone's own beside them. Also
  `TurntablePress.handTurn` and `cancelFollowed()`, `DeckRules.interrupted()` and Debug's reads, and the `discArt`
  route (ROUTE_COUNT 28).
- **DeadwaxTurntable**, a new module: the layer tree (`TurntableLayers`, QuartzCore only), rendered by its tests at
  the iPhone 16's plinth and the SE's to PNGs that ios.yml uploads, with pixel assertions for what needs no eye.
- **The app**: `ios/App/Player/Turntable/`, with DeckController, the deck for the app's run, which outlives Now
  Playing so a coast still hands the song back after a close. TurntableDeckView holds the layers, the two touch
  views and the VoiceOver elements, and TurntableView fits the plinth and draws the lines and the look button.
  NowPlayingView gains the look button and the swap. You > Playback gains **Now Playing opens as** and **Pause winds
  the record down**, and Debug gains a Turntable section. PlayerModel gains only `engineForDeck`, read-only, and the
  engine and DeckEngine have no diff in the app's commit.
- **Slice 2's six questions** are answered in the deck engine, each with a test that fails without it: the
  clock's fallback holds the host time, a route change restarts `L` and drops a window of the wrong rate, a stop
  leaves nothing timed waiting, each EQ host gets its bank at its own rate, the deck's EQ counts its ticks, a newer
  `/scrub` ask cancels the older, and the session is active before the deck engine starts.

The full account - what was built, the renders, every departure and why, and the questions - is the spec's
"Slice 3, built", under 7.3. In brief:

**Departures**: recording (6.3) not built, so check 23's A/B is by ear; the Handover row without its seam, which
needs both engines' render times; two touch views, the fader's being slice 4's; no custom VoiceOver actions; the song
engine's reset caught by the 10 Hz rule rather than its notification; disc art kept in memory, the last eight; the
pbxproj edited by hand; and (the review's) headphones out rests the record, where the web's page plays on (question
27).

**Mutations, each alone** (scratchpad's mutate.py: applied to TurntableScreen.swift, Core's tests run, restored):
| Mutation | Caught by |
| --- | --- |
| The silent line over the player's failure | theSilentLineIsAirPlaysFirstThenNoSoundThenNotAFLAC |
| No frames for a held record under Reduce Motion | framesRunOnlyWhenAskedShowingActiveAndMotionAllowed |
| A lock-screen pause not resting the engine at once | theDeckEngineRunsAsQuestion13Says |
| Sound ready during an interruption | soundIsReadyOnlyPreparedAndAllowed |
| The plinth without its 24 pt clear | thePlinthFitsTheRoomBothWaysAtMost440 |
| The engine running in the background | theDeckEngineRunsAsQuestion13Says |

All six caught. The app's own code (DeckController, the views) has no tests on this Mac: it is the device build and
the phone's checks.

**Verified**:
- `swift test`: Core 953, DeadwaxAudio 139 and DeadwaxTurntable 9, with the 20 renders looked at.
- The unsigned iPhone Release build, with no warnings in the app's sources. It found the missing `import
  DeadwaxTurntable` that the package's own build couldn't.
- check_project.py, the iOS pytest files (146 passed, 1 skipped), and every ios sim, with iosdeck's full check on
  Node 20.12.2.

**Not run**: check-linux.sh (no swift.org toolchain here), and ios.yml, since nothing was pushed.

**Only the phone can show** the screen in the hand: the spec's section 8, checks 1-24 (docs/ios.md's "The
turntable's checks (app 0.6)").

**Review fixes (2026-11-13)**, one commit each, written up in the spec's "Review fixes" under "Slice 3, built":

- **The five bugs**:
  - the time line no longer asks for height, which had shrunk the plinth and moved the titles at every swap;
  - an interruption with no "ended", and a failed start, no longer silence the record for good;
  - the label's and the spindle's rings are inside their boxes, as the web's border-box ones are (question 25
    dropped);
  - the let-go no longer waits on the song's engine: the main thread counts the engine's starts from its phase,
    and the `deck.position` queue's read counts only once the start was seen.
- **The smaller ones**:
  - the deck engine never starts in the background;
  - a stop never puts an older window back over a newer one;
  - the first window is made at the route's rate;
  - a route at a new rate is tested through a rate seam;
  - the session is made active by DeckEngine's own `activate`, first in every start;
  - Reduce Motion's handover hears the song as it is read;
  - CD art is decoded at the face's size;
  - closing Now Playing lets go of a held record;
  - headphones out rests the record (`DeckRules.outputGone()`, question 27).
- **Tests**: each new rule's test was shown to fail under a mutation, but one: `clearLed()` in outputGone, which
  the led timer's own guard already makes redundant.
- **Docs**: checks 3, 15 and 21 reworded.
- **Verified after the last fix**:
  - `swift test`: Core 957, DeadwaxAudio 142 and DeadwaxTurntable 10;
  - the release DeckRealTimeTests;
  - the device build;
  - check_project.py;
  - the iOS pytest files: 150 passed, 1 skipped.

**The version: 0.6 (6)**, pinned where 0.5 was: `Base.xcconfig`, `check_project.py`, `ios.yml`'s check of the built
Info.plist, `tests/test_ios_install.py`; the guide's title, opening, install.sh's line and About's row, ios/README.md,
and YouView's doc comment. `src/__init__.py` wasn't touched.

### Slice 4, first half: the recorder, and the speed measured (2026-11-13)

The turntable spec's slice 4 up to the fader's view (notes/ios-specs/turntable.md "Slice 4, first half, built", with
the numbers). Two commits, then one of the review's fixes to each; the app stays 0.6 (6), since nothing calls the
speed yet.

- **Debug's recorder and its replay** (ae84f26, spec 6.3): "Record 20 s" writes deck.ts's own recording file with
  the phone's keys beside it, from rings the deck engine's render fills (no allocation on that thread, release-built;
  the rings made at the first recording's start); `swift run replay-deck-recording` plays a phone or a web recording
  through the Swift voice. Both replay exactly. It ends by the clock - a rest across its end ends it too - and
  "Record 20 s again" follows a save, the earlier file deleted.
- **The speed in PlaybackEngine** (spec 5.2): **one** AVAudioUnitVarispeed for every lane - lanes into a mixer, through
  it, into the main mixer - and **out of the sound's path at 1x**: each node straight into the main mixer, the chain
  not even hooked up, so every sample at 1x is today's. `setSpeed(_:exact:)`, 0.25 to 4, is the fader's API;
  `exact` at 1x (the fader let go, James's answer) takes the lanes out of the chain again, the song's own samples
  from the frame the chain gave out. Positions stay in the song's time at any speed: the varispeed's own delay (48 of
  the node's frames, measured) and the output's latency counted at the speeds it was rendered at
  (`HeardEstimate.songSeconds`) come off the node's frame, and stay put across a restart (`stillHeard`).

#### The speed, measured

5.3's eight, as tests on ios.yml's macOS job (VarispeedMeasuredTests, and VarispeedCostTests again in a release
build). The short of it:

- **1x is bit for bit**, the varispeed out of the path: 30 s of noise and a sweep from a FLAC, every sample the file's
  own. Bypassed in the path it was every sample right but 47 frames late, failing 62 of the 147 audio tests; at rate 1,
  48 frames late and filtered, failing 64. Every test engine reads `DEADWAX_VARISPEED_AT_ONE` (`outOfPath`,
  `bypassed`, `atRateOne`), so that comparison can be run again.
- **Its quality** is far past the lane converter's bar: a 1 kHz tone 133-145 dB above everything else at 0.25x-2x,
  and what 1.5x and 2x put past 24 kHz left at -113 to -120 dB. A mono song at speed is at its 1x level on both
  channels.
- **The position** is within 0.00 output frames of the clicks heard, with latency and without.
- **Joins at speed** are exact on a lane (-130 dB and under); a change of lane is no worse than at 1x (-46.6 dB, the
  two converters ringing at a cut mid-waveform, in today's engine too) at 0.25x, 0.73x, 1.01x, 1.37x, 2x, 2.9x and
  4x: -46.2 to -60.0 dB. With a varispeed per lane, as first built, 0.73x-1.37x were 7-11 dB worse (the review).
- **A speed changed while playing**, and a drag through 1x, make no click and no jump. Leaving 1x resumes at the
  very frame the render had reached (with 0.1 s of latency, read off a ramp); a let-go at 1x is the song's own
  samples again from the frame after the chain's last.
- **Its cost** is 0.15% of a block at 2x on a 192 kHz file (release).
- **4x on a locked phone's 4,096-frame buffer**: a song's end is on time when the next is late - the windows that
  watch a node's clock count the output's time.

The departures (the first move off 1x and a let-go at 1x each begin the lanes again, a short gap; one varispeed, not
one per lane) and what only the phone shows are in the spec's section. **Left for the fader's half**: the lock
screen's rate (NowPlayingController) and plays at speed - `Plays.listenedStep` caps a step at the clock times its
`rate`, which PlayReporter leaves at 1 - and the `.loading` the engine publishes while it begins the lanes again.

### Slice 4, second half: the fader (app 0.7, 2026-11-13)

The turntable spec's 5.1 on the phone (notes/ios-specs/turntable.md "Slice 4, second half, built", with every
departure). App 0.7 (7); PlaybackEngine untouched.

- **The fader** at the plinth's right: FaderTouchView over its target, one touch at a time across the record, the arm
  and the fader; the web's faderMove (the slop, the octave scale, the detent at 1x) and a light impact as a drag
  crosses into the detent. A drag sends every speed to the engine as it comes; a let-go at 1x is
  `setSpeed(1, exact: true)`, the song's own samples again; a jump to 1x (the readout, the chip, the ••• line,
  VoiceOver) is exact too. Core's `SpeedControl` is that rule.
- **The readout** is TurntableReadout (DeadwaxTurntable), the web's face as a layer tree: drawn in the renders by
  TurntableLayers, and in the app by a UIControl laid over Now Playing's column at the plinth's anchor - the only way
  to sit above the foot line, which is SwiftUI. Its VoiceOver element stays in the deck view's order.
- **The chip** on the cover is an overlay between AirPlay's and Up Next's anchors, its text stopped at xxLarge (the
  footer's gap is about 56 pt, not the spec's 100, since Lyrics came); at the accessibility sizes the ••• menu's
  first line says the speed instead.
- **Kept** under the web's key; given to the engine before any lane begins, so at 1x the chain is never made.
- **What the first half left**: the lock screen's rate is the speed while playing (told four times a second at
  most through a drag, `SpeedPublishing`), its elapsed time the song's; plays cap a step at the clock times the
  fastest speed it spanned (`ListenTracker.speedChanged`), so 2x counts in full; and the restart's `.loading` is
  shown as playing for up to a second (`SpeedRestartHold`), on Play/Pause's spinner and the lock screen.
- **Debug's Speed row**, last in the Turntable section, with the song's pace measured over the last 8 s.

**The version: 0.7 (7)**, pinned where 0.6 was: `Base.xcconfig`, `check_project.py`, `ios.yml`'s check of the built
Info.plist, `tests/test_ios_install.py`, About's doc comment, `ios/README.md` and docs/ios.md (the title, the opening,
install.sh's line, About's row, "The speed" under the turntable, the cover's chip, Debug's Speed row, the lock screen,
plays, "The speed's checks (app 0.7)", and the fader gone from "What it can't do yet"). `src/__init__.py` untouched.

**After the review**: the fader's target overhangs the plinth's right edge (about 15.5 pt on a 393 pt phone), and the
plinth-sized view took no touch there - the view is `touchWidth` wide now, the plinth drawn where it was; the fader's
touch view is under the arm's; a look switched mid-drag lets the fader go (`destroy()`, as `closed()`); a join at 2x
tested. Details in the spec's "After the review" under "Slice 4, second half, built".

Phone-only, all of it: checks 25-38.

## The EQ, slice 1: Core (2026-11-12)

The design is notes/ios-specs/eq.md. Its slice 1 (5.1) is the EQ's pure part, in DeadwaxCore and tested like the rest
of it: the cookbook as Equalizer APO computes it (`EQFilter`), the response and the automatic preamp (`EQResponse`,
`EQPreamp`), the ten bands and the presets (`EQGraphic`), a GraphicEQ curve fitted as filters (`GraphicEQFit`), APO's
files read and written (`APOReader`, `APOWriter`), the bank and its Direct Form I render (`EQBank`, `EQRender`),
eq.json's model (`EQSettings`), the outputs (`EQOutputs`), every word (`EQWords`) and the chart (`EQChart`) - held to
`ios/scripts/make-eq-fixtures.py`, which writes the cookbook, APO's reading rules and the fit again in Python. What was
built, measured and decided, and what wasn't verified: eq.md's "Slice 1, built". Nothing in the App or DeadwaxAudio
uses it yet (slice 2), and the app's version didn't move.

## The EQ, slice 2: the engine (2026-11-12)

eq.md's slice 2 (5.2): the EQ's unit in the player's graph - `EQUnit`, an in-process AUAudioUnit registered with
`registerSubclass` and made as `AVAudioUnitEffect`, between the main mixer and the output in every engine
(`Settings.eq`, false only for the tests' engine with no unit); `EQHost`, the triple buffer over CAudioRing's one
atomic word that hands it banks and reads back its counters; `PlaybackEngine.eqStart`, called between prepare and start
so a start's curve is in before its first sample. Off, the unit passes every sample through untouched - the 93 render
tests before it pass unchanged with it in the graph, and a 30 s render is the same bits with it Off, flat or absent.
The render block reaches the framework through an `internalRenderBlock` getter added with the Objective-C runtime,
because a Swift override costs an allocation on every render (measured). The one thing to hear yet is Debug's EQ
section (You > Debug): the unit's rows and **Muffle what plays**, a -24 dB high shelf at 2 kHz through the real unit,
for docs/ios.md's checks E0a-E0d - and its Render block row, whether iOS asked for the unit's render block as macOS
does (the review's: with it, a "waiting" state, Muffle off when Debug closes, the unit left out of an output of more
than 8 channels, and a reconnect after a failed start that no longer throws). Every number, every departure from the
spec, the review and what wasn't verified: eq.md's "Slice 2, built". A Debug build of the app (`install.sh --debug`) is no test of the EQ's real-time behaviour: its
unoptimised Core allocates on the render. The app's version didn't move.

## The EQ, slice 3: the simple face (app 0.5, 2026-11-12)

eq.md's slice 3 (5.3): the EQ as a listener uses it. **EQModel** (App/EQ/, `@MainActor @Observable`, made in
DeadwaxApp before the player and handed to it; never reset when the person changes - the EQ is the phone's) holds
every output's setting and your presets, read once from **EQStore** (`Application Support/deadwax/eq.json`, written
whole 0.5 s after the last change and never under a finger; an unreadable file set aside as `eq-unreadable-<day>.json`,
a protected one left alone until the phone's first unlock), follows the route (`routeChangeNotification`, through
**EQRouteReader**, a new output met Off) and puts each change in through Core's **EQStartDesk**: one version counter
for changes, route changes and starts, raised before the host's rate is read, and every output's banks made ahead off
the main thread, so the engine's start (`eqStart`, EQModel's `startHook`) only looks its curve up. Debug's Muffle and
the unit's rows moved from PlayerModel to it.

The screens draw Core's **EQScreenRules** (which output a page shows and when it may switch - only the EQ page, only on
top, never under a finger; a pushed page bound to its output; a change while Off turning it on; the short setting;
Other outputs' order; the line under the curve; a slider's drag) and **EQDrawing** (the curve with its preamp, and its
audio graph): `EQScreen` (3.2-3.3), `EQCurveView` (3.4), `EQSliders` and the stepper rows (3.5, 3.15),
`EQPresetsScreen` (3.6), `EQOutputViews` (3.12), `EQNameAlert`, and `EQRoute` - the pages on You's stack as
`AppRoute.eq` and on the sheet's own over Now Playing. The ways in: You > Playback's EQ row, Now Playing's ••• item
and its sheet (the lyrics' `covered` joined by `showsEQ`), Info's Sound and Debug rows. Correction (slice 4), Preamp
and Advanced (slice 5) aren't drawn yet. The start's time, measured, the departures, and what only the phone can show:
eq.md's "Slice 3, built". docs/ios.md's EQ section and checks E1-E16 are James's.

## The EQ's AutoEq routes (2.1.7)

The server half of the EQ's slice 4 (notes/ios-specs/eq.md on `ios`: section 2, 5.4's server bullet, 3.17's words),
on main as 2.1.7, before the phone's half: the phone finds a correction for its headphones in AutoEq's list, and
fetches it, through deadwax - it never talks to GitHub.

- **`src/autoeq.py`** (pure): INDEX.md's lines parsed - the name between `- [` and the first `](./`, the path to the
  LAST `) by `, the source and rig from ` by <source>[ on <rig>]`, the form from the rig folder (`in-ear`, `over-ear`,
  `earbud`, else none), the rig shown as the folder less that word. The path is decoded once (`unquote`) and kept
  decoded; an address encodes each segment whole (`quote(segment, safe="")`). The id is 16 hex of SHA-1 of
  `"autoeq:" + path`. Folding, search, the ranking, one row per headphone in `SOURCE_ORDER`, the answers' shapes, the
  size caps and the times (7 days; 15 s for a first list) are all here.
- **`src/api/autoeq_endpoint.py`**: one `httpx.AsyncClient` (15 s, 10 to connect, no redirects), `deadwax/<version>`
  as the user agent on every request - never `Config.musicbrainz_user_agent()`, which carries MUSICBRAINZ_EMAIL's
  address. An answer, a 404 (None, a profile only) and `Unreachable` kept apart. Each answer is read a piece at a
  time and refused past its cap (8 MB the list, 64 KB a profile, 1 KB the commit).
- **`src/routes/eq.py`**: `GET /deadwax/eq/autoeq?q&limit` and `GET /deadwax/eq/autoeq/{id}`, included with
  `current_user` (tests/test_logins.py ROUTES, both "user"). The list lives in `app.state.autoeq` (`KeptList`), read
  from the database at the first ask after a start; refreshed when a week old by a background task under an
  `asyncio.Lock`, the old list answering meanwhile; fetched before answering when there is none. 503 "deadwax can't
  reach AutoEq just now." and 404 "AutoEq doesn't have that measurement any more." in `detail`, the spec's sentences.
  What GitHub answered goes to deadwax's log at info level, never the event log (no `frontend`).
- **`store.py`**, beside `descriptions`: `autoeq_list`, `autoeq_meta` (one row: the commit, when), `autoeq_profile`.
  A new list replaces the old, its commit, AND drops every kept profile, in one transaction (`autoeq_list_put`); an
  unchanged commit only moves the time (`autoeq_list_seen`).
- The app's shutdown cancels a refresh under way and closes the client (src/api/app.py lifespan).

### The source order

The spec asks for AutoEq's own order of trust "as its README states it when the slice is built". Its README (master,
read 2026-11-12, the same file as at 7ae0f56) states none: it lists where the measurements come from (oratory1990,
crinacle, Innerfidelity, Rtings and the legacy headphone.com ones) without ranking them, and results/README.md says
its recommended list keeps "the one with the highest accuracy" without naming the order. So `SOURCE_ORDER` is the
spec's fallback - oratory1990, crinacle, Super Review, HypetheSonics, Rtings, Innerfidelity, Headphone.com Legacy,
then the rest by name - and its comment says so.

### What AutoEq's list turned out to hold

- **More than spaces is encoded.** eq.md 0.4 says only spaces are percent-encoded; a letter outside ASCII is too
  (`./Kazi/in-ear/A%C3%BCR%20Audio%20Aure`, `R%C3%98DE`), while `(`, `)`, `&`, `+` and `,` stay raw. Decoding the
  whole path with `unquote` covers both, as the spec's "decoded once" meant; the fixture holds the AüR Audio Aure.
- **Every one of the 8,850 lines at 7ae0f56 parses** by these rules (checked over the whole file, fetched by hand):
  each path is exactly `<source>/<rig folder>/<name>`, the line's source is always the path's first segment, its
  ` on <rig>` always the folder less the form, its bracketed name always the last segment. 6,017 rows (headphones by
  folded name); the whole list parses in 0.06 s and a search over it takes about 2 ms.
- One name ends in a zero-width space (Rtings' `Bose QuietComfort 35 II Gaming Headset`): folding drops it.

### Decided here (the spec didn't say)

- **"Every query word starts a word of the name"** is read in the compact name: a query word counts when it is found
  where one of the name's words begins, so "hd650" ranks Sennheiser HD 650 first as "hd 650" does.
- **A query with no letter or digit** (`!!!`) finds nothing, rather than every row.
- **Lowercased with `casefold()`**, so `ß` folds to `ss`.
- **Strict lines**: a path that isn't exactly three segments, has an empty, `.` or `..` segment, or a name that folds
  to nothing, doesn't parse (counted). A path listed twice is one result. Only lines starting `- ` are results; the
  heading and its paragraph aren't counted.
- **A list that holds no results** (GitHub answering 200 with a page that isn't INDEX.md), and a list or a profile
  that isn't UTF-8, is "anything but the list": Unreachable.
- **A failed background refresh is not tried again for 15 minutes** (`RETRY_SECONDS`) while the old list answers -
  otherwise every search would ask GitHub again while it is down or limiting. With no list at all, a failed fetch is
  not tried again for a minute (the review's - see "Review").
- **The first list's 15 s** bound the ask, not the fetch: the fetch is a task the ask waits on through
  `asyncio.shield`, so a slow GitHub costs that ask a 503 and the next ask finds the list.
- **A kept profile is answered only at the list's own commit** - besides the drop, a profile fetch that crossed a new
  list (and kept its text at the old commit) is fetched again rather than answered.
- **The kept list is read under the lock**, so a second ask at the start waits for it rather than reading it again.

### Letters NFKD keeps whole (the review's)

Built as the spec has it, NFKD left letters that aren't a base and a mark - `Ø`, `Æ`, `Ł`, `Đ`, `Þ` - so "rode" didn't
find the RØDE NTH-100 ("røde" did). Added in the review, asked for: folding makes them plain after casefold, from a
small table (`LETTERS` in src/autoeq.py) - `æ` ae, `ð` d, `đ` d, `ħ` h, `ı` i, `ł` l, `ø` o, `œ` oe, `ŧ` t, `þ` th -
so "rode", "røde" and "RØDE" find it alike, and a RØDE and a RODE of one name are one row. `ß` is still casefold's
`ss`; `ŋ` and `ĸ`, with no one plain spelling, are left as they are. A step beyond eq.md 2.1's "NFKD, marks dropped,
lowercased".

### Verified, and not

- **pytest**: tests/test_autoeq.py, 53 tests, through start() with a real SQLite store and an httpx MockTransport
  for GitHub (fixtures: tests/fixtures/autoeq/ - 46 real lines of INDEX.md at 7ae0f56 and one written not to parse,
  and two ParametricEQ.txt copied unchanged from ios's fixtures, with a README and AutoEq's LICENSE). Eight mutations
  tried by hand (profiles kept on a new list, the MusicBrainz agent, redirects followed, the refresh awaited inline, a
  kept profile at any commit, `&+()` left unencoded, the first `) by `, an unchanged commit fetched again) - each
  fails a test.
- **By hand with curl, 2026-11-12** (not deadwax): master's commit with `Accept: application/vnd.github.sha` answers
  the bare `7ae0f56d53074872b028649617a22bbb4232feb7`; profile addresses built by `profile_url` - with `%26`, with
  `%28`/`%2B`/`%29`, and with `%C3%BC` - answer 200, the HypetheSonics one byte for byte ios's fixture; the same
  address double-encoded (`%2520`) answers 404.
- **Not seen**: deadwax itself has never talked to GitHub - every answer it has read is the MockTransport's. GitHub's
  rate limiting, a gzip'd raw answer read through httpx, and how long the 851 KB takes from James's server are
  unwatched.

### Review

The same day, read against eq.md 2.1-2.6, 3.17 and the design review; no version bump (still 2.1.7). Fixed, each with
a test in tests/test_autoeq.py that fails without it (74 tests now, 21 new):

1. **A kept list was searched by the fold it was kept with.** `autoeq_list` keeps each name's `folded`, and the list
   read back after a start trusted it - so a change to fold() (the letter table above) would not reach a kept list
   until AutoEq's master moved, and an unchanged commit keeps a list for months: "rode" would find nothing, and nor
   would "røde", now folded to "rode". The kept list is folded again as it is read (`kept_results`, on a worker
   thread - about 40 ms for 8,850 names); `folded` is still written, as 2.3's table has it. A kept list with no
   results left is no list, and the first ask fetches one - as a fetched list with none is "anything but the list".
2. **The troubleshooting page said deadwax asks api.github.com "once per new correction"**: corrections come from
   raw.githubusercontent.com. It says so now, and that the weekly ask is once deadwax has the list.

Three the review raised as questions, decided as fixes:

3. **With no list, a failed fetch is waited on for a minute** (`NO_LIST_RETRY_SECONDS`, 60). Every ask in that
   minute - a search or a profile - is the 503 at once, GitHub not asked; the next ask after it tries again. 2.3's
   "fetched before answering" had every ask try, so a picker that searches as it's typed into, while GitHub refused,
   spent one api.github.com request a search out of the 60 an hour. A kept list's failed refresh still waits
   `RETRY_SECONDS` behind the list, which answers.
4. **A deadline on each whole fetch**, not only httpx's 15 s between pieces, under which an answer trickling in
   could hold a fetch open as long as it trickled: 60 s for the list, master's commit asked first and counted in it
   (`LIST_DEADLINE_SECONDS`, `AutoEqClient.latest_list`), 15 s for a profile (`PROFILE_DEADLINE_SECONDS`). Past it,
   Unreachable (`within()` in autoeq_endpoint.py): the same 503, and the same log line, naming the deadline -
   "AutoEq's list couldn't be fetched - GitHub took more than 60 s for AutoEq's list". The first ask still waits
   15 s at most; the fetch carries on to its 60 for the next.
5. **A refresh that fails in any way** - any Exception, not only Unreachable - is said in deadwax's log at warning
   with its traceback (never `frontend`), starts the wait (the 15 minutes behind a kept list, the minute with
   none), and comes out of `_fetch` as Unreachable, so the old list answers, a first ask is the 503 rather than a
   500, and `_settled` only retrieves it. `stop_refreshing` lets nothing out of the shutdown, whatever the refresh
   ends with, so the clients after it are still closed. Before, a fault left `failed_at` unset (the next search
   would fetch again) and could escape the shutdown.

Tests that passed with the code broken, now caught (each mutation tried): the size caps checked only after the whole
answer was read (a 64 MB list and a 1 MB profile sent in pieces, refused at the piece that passes the cap); a
redirect followed per request (a profile's 302 to an address that answers 200); stopping deadwax not cancelling a
refresh under way; the path decoded twice (`%2541` is `%41`, never `A`); a list or a profile that isn't UTF-8
accepted; the default `limit` (30, over forty rows); the 15 s first wait and the 15 min retry (asserted). The three
fixes' tests move the recorded failure as age() moves the list's time, trickle answers a piece every 50 ms past a
shortened deadline (and the commit's and the list's answers 0.3 s each past 0.5 s together), and fault the parser
with a plain RuntimeError.

Looked at and kept: the parsing (the first `](./`, the last `) by `, three segments, the source from the path when
the line starts with it), the id, the address (`quote(segment, safe="")`, the name's segment whole), search, the
ranking and SOURCE_ORDER; the routes' bounds, shapes, status codes and the two sentences; GitHub asked only for the
commit, the list and paths from the list; no redirects; the agent; the shield, the lock, the background refresh,
the drop on a new commit and the guard on a profile fetched across one; the store's five methods, which use SQLite
as `descriptions` does (a worker thread each, failures logged and swallowed).

Left, and why:

- **The lock is belt and braces.** `refresh()` hands back the task under way, so two fetches never overlap without
  it; it only keeps two first asks from reading the database twice. Harmless; the spec asks for it.
- **The rig is the folder's, not the line's ` on <rig>`** (2.1 names both): every line at 7ae0f56 says the same in
  each.
- **`folded` is still written** to `autoeq_list`, though read back it is folded again: 2.3's table has it.
- **A gzip'd answer is measured after each piece is decoded**: one compressed piece can decode to about a thousand
  times its size before the cap sees it. Accepted, as the only host deadwax asks is GitHub's.

### `+` and `&` as words (2.1.9)

The fold read `+` and `&` as punctuation, so "Beats Studio Buds +" and the Beats Studio Buds folded to one name and
became one row - the other model's measurements under "Other measurements", with nothing saying it's another
headphone. Found by EQ slice 4's review on `ios`, whose suggestion already read `+` as "plus" and `&` as "and"
(EQSuggestion.folded). `fold()` now does too (SYMBOL_WORDS, after LETTERS): "T2+" finds the "T2 Plus", "Bang &
Olufsen" and "Bang and Olufsen" are one name. A kept list is folded again as it's read (the review's), so an install
upgrading needs nothing fetched. One ranking moved: "(51dB + ANC)" now folds longer than "(ANC mode)", so crinacle's
two modes come before his listening levels for "airpods pro". test_plus_and_ampersand_are_words_of_the_name.

## The EQ, slice 4: AutoEq on the phone (app 0.5, 2026-11-12)

eq.md's slice 4 (5.4), the phone's half of the 2.1.7 routes above: a correction for your headphones from AutoEq,
through deadwax. **Core**: `AutoEq.swift` - the two answers as models (held by test_ios_contract.py to `row_answer`,
`profile_answer` and the search's literal; ROUTE_COUNT 26), `AutoEqProfile.correction()` (APOReader as it is), the
pages' `AutoEqPage`, `AutoEqAsk` (limit 50, query 100 scalars, the 0.3 s pause) and DeadwaxClient's two calls - and
`EQSuggestion.swift`: 3.7's one, several or none, the rules for when it is asked and shown, and the settings' `use`
(a correction, or None) and `mark` (Not now, for good; shown). The Swift tests read the server's own answers:
`ios/scripts/autoeq_answers.py` drives the real routes over tests/test_autoeq.py's fake GitHub into
`Fixtures/autoeq/answers.json`, which the contract test holds to what it makes now, as lyrics'. **App**: the EQ page's
Correction section and the suggestion row (asked once a launch per Bluetooth or USB output with no correction),
`EQCorrectionScreen` (the picker) and `EQProfileScreen` (a profile, "Use for …"), both bound to their output; "Use"
goes back to the EQ page (`AppNavigation.backToEQPage()`, the sheet's own stack, `EQSheetStack`); and the curve
crossfades rather than morphs when its frequencies change. The suggestion offers one headphone, not one row - the real
list has six HD 650 rows - and never the first of several (the AirPods Pro's 16); that and every other departure, the
mutations tried and what only the phone shows: eq.md's "Slice 4, built". docs/ios.md's AutoEq section and checks
E17-E21 are James's. The app's version stays 0.5 (5).

## The EQ, slice 5: Advanced (app 0.5, 2026-11-12)

eq.md's slice 5 (5.5): building a correction yourself, the preamp by hand, and Equalizer APO files in and out. **Core**
holds every rule the views follow, so Linux tests them: `EQAdvanced.swift` - the filter rows in frequency order (the
export's, so a row's number is the file's), 64 an ear for Add Filter and every edit, Add Filter starting "Your own
filters", an edit marking AutoEq's correction changed and "Back to AutoEq's" reading its kept text again, the preamp by
hand (0.1 dB, -30 to +12, beginning at the one playing), the handles (at f0, their own gain; the nearest within 22 pt;
a drag engaging at 4 pt, moving only the axis it moved along; a pinch in the width's own form), the editor's fields,
steps, type change and "Use Q instead" - and `EQImportRules.swift`, the import preview's lines. **App**: the Advanced
switch (per phone; it publishes nothing, as nothing heard changes), the 220 pt curve with its handles and capsule
(`EQCurveView`'s EQHandleLayer: only the handles' 22 pt reach takes one finger, so the curve still scrolls the page;
a pinch anywhere on the plot), the filter rows, Add Filter, `EQFilterEditor` (pushed as `EQRoute.filter`, bound to its
output and the filter's id), the Preamp section, `EQImport` (Files, Paste, and a file shared to deadwax through
`.onOpenURL` - Info.plist's plain-text document type, Alternate, handed a copy, which check_project.py requires) and
`EQExport` (ShareLinks of a file Core's APOWriter writes when it is shared). AppNavigation holds one import at a time:
an EQ page's own is previewed over that page, a shared file over whatever is on top (Now Playing opens its EQ sheet,
closing Up Next or Info first; the tabs get one from MainTabs; a preview already up takes it in place). Exporting the
whole curve and importing it back plays the same within 1e-9 dB, over a Flat tone - over any other the tone plays twice
(docs/ios.md says so). The 64-an-ear limit stays as the spec has it; whether the import's should be 70, so a converted
GraphicEQ with a tone reads back, is James's to answer. Every departure, the mutations tried and what only the phone
shows: eq.md's "Slice 5, built". docs/ios.md's Advanced section and checks E22-E30 are James's. The app's version stays
0.5 (5).

## The EQ's follow-ups (back-home 15, 15a, 15l; 2026-11-13)

James's answers to three of slices 3 and 5's questions (`~/Desktop/Code/deadwax-plans/back-home.md` 15, 15a, 15l), on
the `eq-followups` branch from `ios`. The app's version stays 0.6 (6): small follow-ups don't move it (slices 4 and 5
didn't), and the turntable already took 0.6.

**15, the import's limit: 74 an ear, not 70.** James chose "raise it to 70, so deadwax reads back its own exports".
The Whole Curve writes a correction's filters and the tone's moved bands as ten more filters (APOWriter.curve), so the
most it writes for an ear is **the most a correction holds, plus 10** - and an import is a correction, so no single
limit can cover every export: at 70 for imports and edits, a correction of 70 under a full tone writes 80. 70 would
not even cover the two cases that are ordinary: a converted GraphicEQ keeping all 61 of its peaks under a Custom tone
with all ten bands moved (71 - every built-in preset moves at most nine, Spoken Word's), and 64 filters you added
(Add Filter's limit, unchanged) under any tone of seven or more bands (up to 74). So the limits now are two:

- **`EQLimits.filtersPerEar` = 64**, what you make: Add Filter stops there ("64 filters is the most you can add",
  was "... deadwax plays", now untrue) and **no edit grows an ear past 64, or past what that ear already had**
  (`EQAdvancedRules.fits(_:before:)` - per ear, so moving a filter between the ears can't creep one up; a file's
  extra filters stay editable, switchable, deletable and movable).
- **`EQLimits.importPerEar` = 74** = 64 + the tone's ten: what a file may hold (APOReader; "This file has 90
  filters for one ear - deadwax plays up to 74."). So every whole curve of a correction within 64 an ear - all you
  can build, every AutoEq profile, every converted GraphicEQ (at most 61), every file of up to 64 - reads back under
  any tone, and The Correction Alone always does.
- **`EQLimits.sectionsPerChannel` = 84** (was 80) = a file's 74 + the tone's 10, so the render plays an imported 74
  under a full tone with nothing dropped (EQBank's `prefix` would have cut the last tone bands silently, with the
  automatic preamp worked out from sections that didn't play). Everything sized by it follows: `EQBank.packedCount`
  (8 + 3 x 84 x 8 doubles), EQRender's slots and states, EQHost's three slots, EQUnit's and DeckVoiceHost's copies.

**The true maximum the exporter writes for an ear is therefore 84** - only for a correction over 64, which only a
file brings, under a tone again: in practice a whole curve read back (its tone already in it, so it plays twice -
docs/ios.md already says to set the tone Flat first) and exported again. That one is refused ("84 filters"); over
Flat it reads back. Every other export is at most 74 and reads back. Going higher can't close this - each step up adds
ten to the next export - and 74 keeps the render's growth to four sections.

**The cost**: 1.10's worst case grows from 74 sections a channel (64 + 10) to 84 (74 + 10). EQRealTimeTests' test 8
now runs 74 correction filters and the tone's ten at 192 kHz, crossfading every block: **2.050 ms a block's median,
9.6% of its 21.3 ms** (9.7% on average, 2.246 ms at worst), release, on this M2 - it measured 8.5-8.6% at 74, so
about what ten more sections cost. Its bound (the median block at 15%) is unchanged.

**15a, a curve that only cuts**: its automatic preamp is 0 (it never boosts, 3.2), and the line under the curve said
"Preamp 0.0 dB, so loud songs don't clip." Now it says **"Cuts only: nothing gets louder."**, in Flat's plain form,
with no preamp - `EQScreenRules.line` when the preamp is automatic and the one playing is 0 (`EQPreamp.automatic`
gives exactly 0 when the curve's top is at or under 0 dB, else -0.1 or lower). A preamp set by hand at 0 still says
"Preamp 0.0 dB, set by you.". Info's Sound row already left a 0 dB preamp out. Bass Reduce and Treble Reduce are the
built-in presets that only cut.

**15l, "- changed" for a file**: Add Filter, an edit, a switch or a delete marks a file's correction changed, as
AutoEq's (`kind != .built`), and the Correction row reads "From HD650 ParametricEQ.txt - changed" ("From the clipboard
- changed" for a paste; "From Wavelet.txt, converted - changed"). The export's comment says the same (`Export.comments`
uses `Correction.source`). There is no "Back to the file's" - importing it again is that, and an import comes in
unchanged. eq.json already kept `changed` for any kind; your own filters never get it.

**Tests** (Core): EQImportRulesTests `theMostAnExportWritesReadsBack` - three worst cases exported through the real
`APOWriter.export` and read back bit for bit: 64 for both ears by Add Filter itself; 60 shared and four for each
ear's own (78 lines, 74 an ear); a GraphicEQ alternating +1 and -1 dB at the 61 centres (all 61 kept, 71 under the tone)
with three filters added - each under a Custom tone of ten moved bands, so 74 an ear. Each, imported over Flat, plays
as before within 1e-9 dB at the same preamp; under the tone again the render plays all 84 sections; and that,
exported, is refused at 84 while over Flat it reads back. `anImportTakesSeventyFourAnEar` holds the boundary (74
reads, 75 refused, shared counted for both ears). APOWriterTests' every-fixture-and-preset export now reads back all
450 (it refused ten at 64; the largest is 69 an ear). EQAdvancedTests: a file's 74 edited but never grown, and
`anEditMarksAFileChanged` (four ways, a paste, a converted one, the export's comment, eq.json, a new import, your own
filters never). EQScreenRulesTests: the line's cases, and every built-in preset's real bank at 44.1 and 48 kHz. The
Python mirror (make-eq-fixtures.py's MOST_FILTERS and refusal) moved with it; the fixtures written again changed only
a34's refusal text and made.json's sha.

**Verified** (2026-11-13, this Mac, Xcode's toolchain):
- `swift test`: Core 967, DeadwaxAudio 158, DeadwaxTurntable 10 - all pass;
- the release EQRealTimeTests (test 8's 9.6%, above);
- seven mutations, each undoing one part (the import's 74 back to 64, the render's 84 back to 80, an edit allowed to
  grow an ear to 74, an edit held to 64 whatever the ear had, only AutoEq's marked changed, a file's source without
  "- changed", the preamp line at 0 again) - each fails at least one of the new tests;
- the unsigned Release device build; check_project.py;
- the iOS pytest files and test_source_bytes.py, and test_ios_eq_fixtures.py byte for byte (in the venv with scipy
  that wrote the fixtures; the project's .venv skips it).

**Not verified**: anything on the phone - docs/ios.md's checks E31-E33 (Bass Reduce's line; a file's "- changed"; a
GraphicEQ with all ten sliders moved, exported whole and read back) are James's; and ios.yml's runner (Linux's
`swift test`, its release cost on slower cores).

## Main's 2.1.11 to 2.1.15 merged (2026-11-13)

Main at 330476a merged into ios, and what the phone needs of it ported. The app stays **0.7 (7)**: small
follow-ups don't move it. `src/__init__.py` came in at main's 2.1.15 with the merge, and nothing here moved it.

### 2.1.11, the lyrics' wait: nothing to port

The web's wait now counts from where the listener's scroll stops, a fling's coast included (`scrollHolds`, a
movement while their scroll holds moving the hold on). That was already the phone's way: `LyricsHold.phase` holds
through `interacting` and `decelerating` (a finger down, `tracking`, too) and starts the wait at `idle`. `follows`
and FOLLOW_AGAIN_MS are unchanged, so the lyrics vectors are current (ioslyrics.sim passed on the merged tree
untouched), and nothing on the phone changed.

### 2.1.12, the record's let-go after a song change (James: "Fix on both")

`TurntablePress.songChanged` now sets `turned` when the drag it drops is the record's - the web's song-change effect
(Turntable.tsx:269-280) - so the click the lift runs (the phone runs onRecordClick's rule after every lift of a touch
that came down on the record) is no tap: the new song is left as the change left it, playing or not. Before, a still
press the song ended under - .11's (a song the record can't sound: not a FLAC, its window not come) or the deck's
inside a tap - paused the new song as the finger lifted. The arm's drag sets nothing, as on the web, where the flag
would swallow the record's next keyboard click; on the phone every click on the record follows a press, which clears
it, and VoiceOver's activate is `toggle`, so the arm's half is parity only. `turned` is still cleared by the next
press.

The deck's export hashes the song-change effect into handlers.json now (`handlerPieces`: before, iosdeck.sim's
sources-only check passed on Node 22 with the change merged), and the trace `press/song-change-under-a-press`
changed with it: the lift wakes and nothing else - no pausing, no toggle. Written again on Node 20.12.2, the maker's
(made.json, maths.json, handlers.json and every press trace's made_from). TurntablePressTests: a still press and the
deck's, the song changed under each, then the lift - only the click's wake, the deck asked nothing more - and the next
tap a tap again; the arm held as the song changes, then the record's click and its next press, both taps. Mutations:
the line taken out (the new test and both replays of the trace fail), and set for the arm's drag too (the arm's test
fails). docs/ios.md says it under Tap the record, in the words docs/player.md uses.

### 2.1.13, the filing refusals' words

errorWords.ts's JOB_ERRORS gained the two refusals filing makes now before anything moves (src/poller.py
READ_ONLY_DOWNLOADS, slskd's folder read-only to deadwax, and FOLDERS_OVERLAP, slskd's folder and the library
overlapping), and the dry run's sentence was reworded for a row written before 2.1.13 ("back then, deadwax only
rehearsed adding albums") rather than removed: the server no longer writes it, but an old job still says it.
`ErrorWords.jobErrors` follows, in the web's order: a listener reads "It downloaded, but deadwax can't move its files
into your library yet." and "It downloaded, but deadwax isn't set up to add it to your library yet.", each with the
tell (only whoever runs deadwax can put it right), and the server's own words only as the detail for them.
error-words.json written again (its job table and job cases); the gate's navidrome.json changed only its hash of
errorWords.ts. Nothing else on the phone named ORGANIZE_MODE or a dry run.

### 2.1.14 and 2.1.15, play history: the fixtures kept current, the phone's resume unchanged

Play history itself is the phone's next piece (`~/Desktop/Code/deadwax-plans/play-history.md` section 5), not this
one. What the merge changed under the phone: `UpNextState` gained `id`, the queue's identity, minted by
`startUpNext` (queueId(): the time and random bytes) and carried by every edit, and toSave writes it second in
snapshot v1 (`{"v":1,"id":"...",`); fromSnapshot reads a valid one (`[A-Za-z0-9_-]`, 1 to 64) and otherwise mints one
(or, in the web's take(), keeps the page's - `holding`). So export-traces.cjs's snapshots came out different every
run.

**The vectors the phone must write stay the phone's form.** The resume vectors hold the phone's toSave to the web's
text to the unit, and the phone keeps no id until its port, so a fixed id in those texts would have needed the port
itself. The export now records toSave of each queue as the phone has it - without its id (`phoneForm`), which toSave
then leaves out: v1 exactly as the phone writes it, and as the web did before 2.1.15. Every one of those texts is
byte for byte as before (only made_from moved). `saved()` also holds the web's own text of the same queue to that
text with the id put second (`withQueueId`), so a change in where or how the web writes the id stops the export.

**The web's own text is now read back by the phone**: 18 more fromSnapshot cases (188, from 170) - the web's 2.1.15
snapshot with a fixed queue id (`QUEUE_ID`, 'mhyx7k2c-a1b2c3d4', in queueId's form) under all four settings, and ids
of every other shape (64 and 65 characters, empty, a space, a dot, an escaped emoji pair, a number, null, an object,
an array, true, first before `v`, last, twice). The web reads each as the same queue, the id aside, and the phone
does too - its SnapshotJSON already passed over keys it doesn't know. ResumeUnitTests
`aSnapshotWithTheWebsQueueIdReadsAsTheSameQueue` says it directly, and that the phone's own snapshot still has none.
The upnext traces, scenarios and property digests never recorded an id (queueRecord, canonical), so they changed only
their made_from; `--check` made twice gives the same files.

**The resume controller**: useResume.ts's createResume changed (its hash moved) for play history alone - take()
passes the page's queue to resumed() (`holding`) and tells the history outbox a queue put back mid-song is no new
start (`continuing`). Neither applies to a phone with no queue id and no starts; ResumeController.swift says so in its
header, and the phone puts back exactly what it did. Until the port, the web picking up a phone's snapshot mints a new
id, so a song played in that queue before the pick-up can show twice on the web (play-history.md says so too).

### Verified, and not

Verified (2026-11-13, this Mac, Xcode's toolchain, on the merged tree with the three ports):
- `swift test`: Core 986, DeadwaxAudio 158, DeadwaxTurntable 11 - all pass; the release EQRealTimeTests,
  DeckRealTimeTests and VarispeedCostTests;
- the unsigned Release device build (0.7 (7)); check_project.py;
- the full pytest: 4341 passed, 1 skipped (CLAUDE.md's count);
- `npm run build` on Node 22 (into this worktree's own `npm ci` of ui/ on Node 22 - the main checkout's node_modules,
  installed on 20.12.2, has no rolldown binding: notes/tooling.md), and every sim, 79, on Node 22 with a scratch
  TMPDIR; iosdeck.sim's full check on Node 20.12.2 too;
- the 2.1.12 mutations above; export-traces.cjs `--check` made again gives the same files.

Not verified: anything on the phone - the let-go after a song change (a finger resting on the record as an MP3 ends),
and a web-saved queue (with its id) picked up on the phone and played on.

## Play history on the phone (app 0.8, 2026-11-13)

The design's section 5 (`~/Desktop/Code/deadwax-plans/play-history.md`), with section 9's answers (James): kept for
ever, ONE continuous list with no headings (History's own heading is gone too), no times, skips drawn like plays, no
Clear. The server (2.1.14) and the web (2.1.15) are notes/play-history.md's; this is the phone's port of the web's
rules and its own sending and drawing. App **0.8 (8)**; the engine untouched.

### What a start is, on the phone

A listen's first sound: PlayReporter's `.nowPlaying` report, out of ListenTracker's `began`/`join` - the moment
Navidrome is told "now playing", as on the web. `PlayReporter.onStart(entry, atMs)` gives the listen's `startedAt`
and the engine's entry; `PlayerModel.started(entry:at:)` records `PlayHistory.startOf(current.track, at:, queue:)` -
the song `bare()` (without its level), the queue's id and the entry's key - only when that entry is still the one
playing (`link.engineKey(current.key)`). Pause and play, a seek, the turntable's handover, a wait, a retry and the
speed restart (same engine key, no `songChanged`) make no `.nowPlaying`, so are never starts; Previous, a restart,
each Repeat One copy and a tap in Up Next each are. `.played` (the counted play) marks its start counted
(`onCounted`): in this run's outbox, among the waiting, and in the store - deadwax ORs it in.

**A continuation** is the web's way (useResume.ts), not section 5's `from > 0`: ResumeController's take() and
putBack() call `ResumePlayer.continuing(kept && position > 0 ? put : nil)` (deadwax's own queue, put back mid-song -
a QueueKept row's answer always carries `kept`), and `HistoryOutbox.record` drops the next start when it is that
queue's id and entry. Any start, or any other restore, ends it. The queue's id itself came with the earlier part of
this work: `UpNextState.id` (queueId, startUpNext(id:)), written second by toSave and read back by
`fromSnapshot(holding:newId:)` - a snapshot without one (the web before 2.1.15, this app before 0.8) keeps the held
queue's when `sameQueue` says it is the same queue, else gets a new one. ResumeController's header says it.

### Core (DeadwaxCore, tested on Linux)

- **PlayHistory.swift**, the port of `lib/playHistory.ts` and `player/historyOutbox.ts`'s rules: `Played` (a start,
  read leniently - a song's id is all it needs - and written as the web writes one: every field, nil as null),
  `HistorySong` (the song's twelve names), `HistoryCursor`, `HistoryPage`, `HistoryPost`, `HistoryTaken`, `PastRow`,
  `QueueShows`, `HistoryHeld`, `Continuation`; `merged`, `pastRows` (every start the queue's own rows draw left out,
  a run of one song one row), `withNewest`, `withOlder`, `countedIn`, `after(status:)`, `retryAfter`, `startOf`;
  `HistoryOutbox` (this run's own newest 500, the continuation, counted).
- **WebText equality.** Swift's `==` on String is canonical equivalence (`"\u{e9}" == "e\u{301}"`); the web's `===`
  compares UTF-16 units. Every id compared here - in PlayHistory, the outbox, `Resume.sameQueue` - goes through
  `WebText.same`, and `merged`'s keys are `[UInt16]`, so the phone tells apart exactly what the web does. The vectors'
  ids include pairs that differ only that way.
- **Routes**: `history` (GET, `limit`, `before_at`, `before_id`) and `recordHistory` (POST) - 30 routes;
  `DeadwaxClient.historyPage(before:limit:)` and `recordStarts`.
- **DownloadDatabase version 3: `start_pending`** in the person's download store - the starts deadwax hasn't taken,
  oldest first (`keepStart`, `keptStarts(limit:)`, `keptStartCount`, `forgetStarts` - each start only while its
  `counted` is as it was read, see "After review" below - `countStart`). `removeAll` keeps
  them (they are the person's plays, not downloads); a version 2 file gains the table with its kept plays intact. The
  newest page is kept in `meta` (`PlayHistory.keptPageKey`, JSON) for Up Next offline.
- **KeptSend.swift** (after review): `KeptSender`, the send loop's decisions - whose (`KeptOwner`), the starts first in
  batches, what is forgotten after which answer, the 401 hold, the wait after a failure, one send at a time, the
  starts held with no store - over a world of closures (`KeptSendWorld`: the open store, the line, the retry timer,
  the log, the counts), callback-based and on one thread like ResumeController. The App's DownloadModel only wires it.
- **`HistoryAsking`** (PlayHistory.swift, after review): what Up Next's history may ask and which failure it says -
  the newest page and the older pages each latest-only by ask number, their failures kept apart, the newest not
  asked for offline nor its failure said, `asksAgain` (a page landed with the first 10 rows still in view).
- **`QueueController.playAgain`**: an older row's tap as ONE edit - `withNext` then `jumpedTo` the key it was given,
  through `jump` like a row's tap, so it is never held for the join and never waits as Playing Next (the web's Play
  Next then jumpTo, as one change). With nothing to play next to (`playsAlone()`: nothing playing, no Up Next, or a
  queue played out) the song plays alone, as Play Next would start it.

### The app

- **HistoryModel** (`@Observable`): `plays` = `merged(held.asked ? held.plays : kept, outbox.own + waiting)`.
  `opened()` reads the person's kept page and waiting starts once (per person, once their store is open), draws, and
  asks for the newest page (`refresh()`, latest-only by ask number and person; kept to `meta`; not offline); `older()`
  one page at a time from `held.before`, not after an older page's failure until Try again; `failure` is said with
  ErrorWords and Try again (`retry()`, the ask that failed) - an older page's always, the newest's only online;
  `reset()` on another person. The asking itself is Core's `HistoryAsking`.
- **Sending** (`DownloadModel.sendKeptPlays`, Core's `KeptSender` since review): the starts first, so a play's count
  finds its start - batches of at most `PlayHistory.postMax` (500), oldest first; taken (any 2xx) or refused with
  another 4xx, forgotten - each only as it was read; a 401 holds them for the same person's next sign-in; no answer,
  a 5xx, a 408 or a 429 stops them until 30 s on, doubling to 10 min (`retryAfter`, a DispatchWorkItem), or the next
  start - then the plays as before. One send at a time: one asked for meanwhile is made once it ends. Nothing goes
  while the store open isn't the person a request would go as. A start is sent as it is made (`keepStart` asks a
  send). Debug > Downloads: **Starts waiting to be sent** (the store's and any held with no store); the downloads log
  notes a backlog sent, a refusal or starts that counted on their way, not each start.
- **Up Next** (UpNextScreen): above the card, one Section with no header - the failure (ErrorNote with Try again), the
  older rows (`PlayHistory.pastRows`), then the queue's own History; none in Edit. The newest page is asked for as Up
  Next opens, as the app comes to the front with it open (`scenePhase`) and as the network comes back with it open
  (`reachability.online`). The next older page is asked for when one of the list's first 10 rows comes into view
  after the sheet was placed at the song playing (`toCard`) - and again when a page lands with one of them still in
  view (`history.landed`, `askAgainNearTop`). Its spinner
  is an OVERLAY over the list's top ("Loading earlier songs" to VoiceOver), never a row: a row would move the list.
  **The hold**: SwiftUI's List keeps its content offset when rows land above, which would carry the view away; so
  each row's onAppear/onDisappear keeps the rows in view in a plain class (`Seen`, not observed - scrolling redraws
  nothing), and when what is above changes with the same song playing and Edit unchanged, the topmost row that was
  in view is scrolled back to the top, without animation - unless it is an older row whose place didn't change. An
  older row's tap: `player.playAgain` (levelled as a song played alone, `follow()`, a new queue's keys when it plays
  alone), `holdAt` so the change of song keeps the scroll, VoiceOver's focus kept on the row, "Playing {title}" said.
  Each row's name is the History row's, "{title}, play again", and a song not on the phone is dimmed offline as
  every row is.

### After review (0f1ab03's, the same day)

The review found nothing serious; these were its points, each fixed in Core where a test reaches it:

1. **A play counted while its start's batch was on its way lost "counted".** The scrobble's mark can reach deadwax
   before the batch's insert, finding no row; forgetting the batch by id then deleted the start marked meanwhile.
   `forgetStarts` now takes the starts as read and deletes `WHERE id = ? AND (counted != 0) = ?`: one counted
   mid-flight stays and goes again, counted, and deadwax ORs it in (historyOutbox.ts's own rule). The log says
   "starts counted on their way".
2. **A send under the next person's session.** The App's change of person is a hop on the main queue
   (serverChanged), while sign-in has already set the new client: a retry, a reachability change or the app coming
   to the front in that hop sent the last person's starts and plays as the new one. KeptSender compares the line's
   owner (who a request goes as, asked again before EVERY request) with the open store's, and sends nothing while
   they differ; a start made in the hop is held for its own person until their store opens.
3. **Starts lost with no store** (it couldn't be read, a failed migration, a start before it opens): held by the
   sender per person (`loose`, the newest 500), put into their store once it opens, or - while none will - sent from
   there as the web sends its own, by the same rules. Counted marks reach them too.
4. **A 2xx whose body didn't decode wedged the outbox** (decode threw with no status, read as no answer: the same
   batch again for ever). `recordStarts` takes any 2xx as taken and decodes `HistoryTaken` with `try?`.
5. **A newest-page failure blocked the older pages, and was shown offline.** Up Next offline always failed its
   refresh, and then scrolling up loaded nothing. The two failures are now kept apart (`HistoryAsking`): only an
   older page's stops the older pages; offline, the newest page isn't asked for and its failure isn't said; it is
   asked for again when the network comes back with Up Next open.
6. **A page that brought no row into view stalled loading** (asked for only as a row newly appeared). After an
   older page lands with more to come and one of the first 10 rows still in view, the next is asked for
   (`HistoryAsking.asksAgain`, `askAgainNearTop`).
7. **History's word.** UpNextWords.history's comment said it names the region for VoiceOver; nothing uses it, and
   James wants no heading. The comment was corrected rather than a hidden header added: a played row already says
   "{title}, play again", the song playing's title is the next heading, and a hidden header's effect on the List's
   layout and the hold couldn't be checked here. The word stays, the web's, held by the vectors.

Tests: KeptSenderTests (18: the order and the batches, any 2xx, the other 4xx, the 401 hold, the backoff and its
reset, counted mid-flight both through the sender and at the store, a send asked for meanwhile, offline, another
person's store, a change of person or a closed store mid-send, the starts held with no store - sent from there, put
into their store, capped - a start into another person's store held, the status read, a taken batch whatever its
body); HistoryAskingTests (4); the version 2 upgrade now fills every table (songs, origins, albums, loudness, lyrics
and their trigger, plays, queue_pending, meta) and proves each survives; and HistoryVectorTests' property run asserts
"each start drawn exactly once" on the phone's own answers at every step (history.sim's check, ported), not only
replaying the TypeScript's lines.

### The fixtures

- **ios/scripts/export-history.cjs** (new, `--check` by **ui/test/ioshistory.sim.cjs**): lib/playHistory.ts with
  upNext.ts, playQueue.ts and resume.ts compiled and run; crypto stubbed to throw, so nothing reaches queueId's
  random. **Fixtures/history/vectors.json** (514 KB): UpNext.tsx's six words; the seven numbers; a start's key;
  `merged` over 160 seeded pools; `withNewest`/`withOlder` over history.sim's cases and seeded ones (209 steps);
  `countedIn` 80; `afterFailure` 21; `retryAfter` 28; and EACH START DRAWN ONCE - 300 seeded runs of 50 moves (9,596
  starts: songs ending, Previous, taps on Up Next's, History's and older rows, Play Next and Last, Shuffle, Repeat, a
  reload through the snapshot, another queue), a line per step of what `queueShows` and `pastRows` answer, each run's
  lines as an FNV-1a digest and run 0's in full. **HistoryVectorTests** replays it all, the property through
  DeadwaxCore's own Up Next from the same Park-Miller numbers.
- **export-traces.cjs**: `phoneForm` and `withQueueId` dropped - every snapshot is written with its id second, as the
  phone now writes it; queueId's clock and random bytes are a counter while recording, so a queue made without an id
  given has the same one every run, and a queue read back that was given a new one is recorded as `"id": null`.
  `withoutId` cases (a snapshot as written before the id, read as a new queue - or as the held one's, `holding`).
  Resume cases 1,819 (from 1,765).
- **tests/test_ios_contract.py**: 30 routes; `Played`'s and `HistorySong`'s names are the route's `HistoryStart`'s and
  `HistorySong`'s (both ways) and `SONG_COLUMNS`'; page, cursor and the POST's answer against `page()` and the route;
  the phone's exact JSON (PlayHistoryTests' own text) taken by the real route and paged back; the page and the batch
  within the route's bounds.
- Swift: PlayHistoryTests (the outbox, a continuation, counted, a start's song, a send's answer, the JSON both ways),
  StartPendingTests (the table, kept across a launch and through removeAll, a version 2 file upgraded),
  QueueControllerPlayAgainTests (5), ResumeControllerTests' continuation, and the resume and trace tests on the ids.

### Docs

docs/ios.md: the title and opening, Up Next's "What you've played", a new "What you've played" section (what goes in,
not a new song, a continuation, offline and the batches, the newest 100 kept, no Clear), Offline, Debug's row, check
5's words, and "Play history's checks (app 0.8)", 39-49 (49 since review: offline Up Next, and back in reach). docs/player.md and docs/troubleshooting.md: the native app's
plays are sent since its 0.8 (they said "not yet"). notes/play-history.md points here.

**The version: 0.8 (8)**, where 0.7 was: `Base.xcconfig`, `check_project.py`, `ios.yml`'s Info.plist check,
`tests/test_ios_install.py`, About's doc comment, `ios/README.md` and docs/ios.md. `src/__init__.py` untouched.

### Verified, and not

Verified (2026-11-13, this Mac, Xcode's toolchain):
- `swift test`: Core 1011 (from 986), DeadwaxAudio 158, DeadwaxTurntable 11 - all pass; the release EQRealTimeTests,
  DeckRealTimeTests and VarispeedCostTests, one at a time;
- the unsigned Release device build (0.8 (8) in its Info.plist, no warnings); check_project.py; the .xcodeproj
  unchanged (App/ is a synchronized folder);
- `pytest tests/test_ios_*.py tests/test_source_bytes.py` (160 passed, 1 skipped) and the full pytest: 4347 passed,
  1 skipped (from 4341: the contract's four new tests and its two new routes);
- every ios*.sim (10, ioshistory's new among them) on Node 22 with a scratch TMPDIR, into this worktree's own `npm
  ci` of ui/, deleted afterwards.

After review (the same day, the same checks): `swift test` Core 1033 (from 1011: KeptSenderTests 18, HistoryAskingTests
4), DeadwaxAudio 158, DeadwaxTurntable 11 - all pass; the release real-time tests one at a time; the unsigned Release
device build (0.8 (8), no compiler warnings); check_project.py and the .xcodeproj unchanged; pytest iOS 160 passed, 1
skipped, and the full 4347 passed, 1 skipped; the ten ios*.sim on Node 22 (a fresh `npm ci`, deleted after). Not run:
the Core suites on Linux (ios.yml's ubuntu job will).

Not verified: anything on a phone - checks 39-49 in docs/ios.md: the view held as a page lands above (SwiftUI's List
and `scrollTo` with no animation are the whole mechanism, unseen), the next page asked for near the top, an older
row's tap under the finger with VoiceOver, the newest page on coming back to the app, offline starts drawn and sent
on reconnect before the plays, a long backlog in batches, a pick-up mid-song making no start, another person's
history.

## Phase 3, slice 1: following your library (read-only, 2026-11-13)

Phase 3 is "auto-download your library" (the plan's section 5, James's answers at its top). Its spec is
notes/ios-specs/phase3-autodownload.md: the words, the rules (2.1-2.9), the screens, the server (nothing needed),
the machinery, three slices, tests, the checks and 16 open questions with what is built until James answers. This is
its first slice: **the phone follows your library and works out what would fit, and nothing downloads or is
deleted** - no origin is written and the planner is untouched. It exists to prove the rules against James's real
library and to measure the first read of every album's songs (the plan's R13) before anything depends on it. Built
on branch `phase3-autodownload` from ios at 305f6a8 (app 0.8); the app's version stays 0.8 (8) until the phase is
done (0.9, slice 3). Nothing in DeadwaxAudio changed.

### Core (DeadwaxCore, tested on Linux)

- **LibraryFollow.swift**: `FollowedSong` (a song as the fill reads it - id, disc, track, size, suffix, content type,
  duration; its `format` and `bytes` as the planner counts a song asked for), `FollowedAlbum` (the list's entry, its
  place, its songs once read, and the marks missing since, removed here, kept off), `LibraryCheck` (the seven
  reasons), and `LibraryFollow`: `sync` (2.3 - added, changed, back, missing, removed; a list's absences held back when
  it is empty, drops more than half and more than 10, or is truncated, and a 304 after a held list held too), `due`
  (2.2), `placedAt` and `ordered` (2.5: the later of the star - `created` without one, or for the collection - and a
  play within 30 days), `toRead` (2.4) and `songsChanged`.
- **LibraryFill.swift**: `plan` (2.6 - hand downloads first, the limit's and the phone's budgets, `room`,
  `phoneFull` holding its room under the limit, `unread`, `keptOff`, give-way of albums with bytes here, N of M) and
  `albums` (the fill's `AlbumFacts` from the library in order, songs wanted by hand left out). Named `AlbumFacts`, not
  `Album`: tests/test_ios_contract.py finds Core's `struct Album` by name and requires one.
- **LibraryFollowWords.swift**: Debug's lines and the downloads log's library lines, and `LibraryCheckRecord`.
- **DownloadDatabase version 4: `library`** (5.1) - `library()`, `putLibrary(_:replacing:)` (rows gone deleted, only
  rows that differ written, one transaction), `setLibrarySongs`, `setRemovedHere`, `forgetLibrary`; the meta keys
  `library_scope`, `library_etag`, `library_held`, `library_checked_at` and Debug's `library_first_read`. `removeAll`
  keeps the table (it isn't downloads); a version 3 file gains it with every other row kept.
- **StreamFormat.format(suffix:contentType:)**, so a `FollowedSong` is counted as its stream would be fetched.

### The app

- **LibraryFollower** (App/Downloads/, `@MainActor @Observable`), owned by DownloadModel and given its store as it
  opens (`opened`, `closed`): checks for `opened`, `front` (DownloadModel.becameActive), `timer` (a 60 s loop while the
  app is alive, a check when 15 minutes have passed), `changedHere`, `byHand` (Debug's Check now) and `back`
  (reachability coming back online); one thing at a time - a check, then the reads, a check asked for during the reads
  made after the batch in hand. A check: `album_index?scope=` (AlbumScope.albums(for: me)) with the last list's ETag
  (none while the library is empty), `LibraryFollow.sync` on the answer dated by the request's send time, the result
  written in one transaction with the ETag, the held reason and the time, then `ordered`. A check that fails, or
  can't ask (offline, signed out, the launch not ready), changes nothing - not even `lastBegan`, so the next minute's
  timer is due. The reads: `toRead` in order, four at a time (`GET /navidrome/albums/{id}` in a task group), each
  album's songs written as they come; a batch wholly refused stops the reads until the next check, and an album that
  failed isn't asked again until then.
- **Debug's switch** "Follow your library" (`debugFollowLibrary`, per phone, off by default): nothing runs without it.
  Turned off, the library and its meta are forgotten (L0a's "off and on reads again from nothing").
- **DownloadModel**: `follower`; `libraryChanged(album:removed:)`, called by AlbumModel.change (now given the
  downloads) when Add or Remove answers - a Remove marks `removed_here` at the answer's time, so the next list
  without it removes it at once, and a list asked before the answer can't clear it; `handBytes()` (the hand
  downloads' bytes here and to come, and their songs) for the fill.
- **DebugView**: "Your library" after Downloads - the switch, Following, Albums, Songs read, Missing, Held back, Last
  check, First read, the fill's "N of M fit in 20 GB" and its detail (at the storage limit and the free space, read
  every 5 s), the store's problem, Check now. Its log lines are the Downloads section's ("library <reason>: ...").

### Decided here (the spec was silent)

Written into the spec's 6.4 too:
- **Another scope** under the same store (logins switched on or off): the kept list is the other scope's, so it is
  forgotten and followed afresh, its ETag with it.
- **A missing album stays in the fill** until two checks agree it is gone.
- **An unread album's bytes here aren't counted as the phone's to give** - it is never given way while its songs are
  read again.
- **A play dated ahead of now counts as now** in the order (the spec's test list had said "ignored").
- **The first read's time** runs from the check that listed albums into an empty library to the last listed album
  read; it is kept in meta. Time in the background counts, and a relaunch mid-read never records one.
- **Not built in slice 1**: the album page refreshing an album's kept songs (2.4's last point - nothing is planned from
  the songs yet), the `background` reason (slice 3).

### Tests

Core 1084 (from 1033): **LibraryFollowTests** 25 (every rule of 2.2-2.5 in the spec's section 7, the drop's edges -
exactly half, exactly 10 - removed-here before and after a check's send time, a pending mark surviving a held list,
the held reasons' words), **LibraryFillTests** 13, **LibraryDatabaseTests** 7 (every mark kept, a list replaced, only
changed rows written, removeAll and forgetLibrary, a version 3 file upgraded), **LibraryFollowWordsTests** 6; the two
tests pinned to version 3 now read `DownloadDatabase.version` / open with `upTo: 3`. The spec's mutations, each run
against the suites and each caught: the ten minutes as `>`, confirming at the first absence, a 304 not confirming, an
empty list marking, the drop without "more than 10", a play of any age, the fill skipping hand bytes, a phone-full
album not holding its room, give-way of an album with nothing here.

### The server

Nothing. The one route the spec names - `GET /deadwax/navidrome/album_songs?ids=` (permission user, up to 50 ids,
getAlbum as the asker, `{"albums": [{"id", "songs": [...]}], "missing": [ids]}`) - is built on main as a 2.1.x patch
only if L0a's first read over WireGuard takes more than 10 minutes.

### Verified, and not

Verified (2026-11-13, this Mac, Xcode's toolchain): `swift test` - Core 1084, DeadwaxAudio 158, DeadwaxTurntable 11,
all pass; the unsigned Release device build (0.8 (8), net.lizardlounge.deadwax, no warnings); check_project.py, the
.xcodeproj unchanged (App/ is a synchronized folder); `pytest tests/test_ios_*.py tests/test_source_bytes.py` 160
passed, 1 skipped (nothing outside ios/, notes/ and docs/ changed, so not the full suite); the ten ios*.sim on Node 22
with a scratch TMPDIR (a fresh `npm ci` in ui/, deleted after). Not run: Core on Linux (ios.yml's ubuntu job will).

Not verified: anything on a phone - checks L0a-L0g in docs/ios.md: the first read's time at home and over WireGuard
(R13), a star and an unstar elsewhere reaching the phone, the 304, Remove here at once, the fill following the limit,
nothing else moving; and what a 200 of a 3,000-album list costs on the phone (Debug's Last check times it). Nothing
drawn has been seen.

## Phase 3, slice 2: downloading your library (2026-11-13)

The spec's slice 2 (notes/ios-specs/phase3-autodownload.md, 6.2): **the library downloads, and lets go**. Built on
branch `phase3-autodownload` from slice 1's merge (481c736). The app stays 0.8 (8) until slice 3; nothing in
DeadwaxAudio changed; no server change. This is the slice that deletes files, so its rules were built as Core rules
first, each tested with a mutation that breaks it:

1. **Nothing wanted another way is ever removed by the library.** The library takes only its own origin
   (`LibraryDownloads.gives == [.library]`), only from songs that carry it, and every delete is Phase 2's:
   `DownloadDatabase.removeOrigins` deletes a song only when no origin is left. A song downloaded by hand (`.song`,
   `.album`), one in a downloaded playlist (`.other("playlist:...")`, for Phase 4) or with any other origin keeps it,
   and the song. A kept play, start or queue is never the downloads' to remove (Remove All keeps them too).
2. **An empty or suspicious list deletes nothing.** Slice 1's held lists (empty while albums are kept, a drop of more
   than half and more than 10, a truncated list) change no album, so the library takes nothing; a 304 of a held list
   is held too. An album that is neither in the library nor removed by a check keeps its songs - nothing goes on a
   guess.
3. **A removal is acted on only after two checks at least 10 minutes apart agree** (slice 1's `missingSince` and
   `confirmAfterMs`): a missing album still fits and is still the library's; only `removed` (an album a check took
   out) is let go. The one exception is an album removed in this app (`removedHere`, open question 9), which goes when
   the next list confirms it.
4. **Every delete goes through the same guarded path as Phase 2's Remove** (`DownloadModel.removeOrigins` -> the
   database's `removeOrigins` -> `DownloadRules.afterRemoving`): the library's takes, the switch turned off, Remove
   All, an album's Remove Download.

### Core (DeadwaxCore)

- **DownloadModels**: `DownloadOrigin.library` (`.other("library")`, stored as `library`), and `onlyLibrary(origins)`
  (the library and nothing else).
- **LibraryDownloads.swift** (new): `StoreSong` (a store song as the rules read it: id, album, origins - none kept
  reads as `[.song]`, never the library's - state, bytes), and `LibraryDownloads`:
  - `songs(records, origins:, library:)` - each song read on the library album whose read songs have it (else its
    record's album), so a song asked for with another album is still counted;
  - `fillInputs` - the songs wanted by hand (their bytes are the hand downloads'), each album's library-only bytes
    here, and their total (`libraryHere`);
  - `turn(ordered, removed:, songs:, bytesHere:, handToCome:, limit:, freeSpace:, reserve:, readsPending:)` - the fill
    (`LibraryFill.plan`, after the hand downloads here and to come) and `actions`;
  - `actions` - **takes**: of the library's songs only, for an album `removed`; for the fill's `keptOff`; for
    `room`/`phoneFull` (`gaveWay` if any of its library songs are here, `waits` if only asked); and a song no longer
    on its album (`notOnAlbum`). An `unread` album keeps everything. **Asks**: the albums that fit, in order, that are
    listed (not missing), not removed here and read, for their songs not yet the library's - at most
    `albumsAtOnce` (10) albums on their way at once, none taken this turn, and none below the first album still to
    read while reads are pending (so an album read late never makes one asked before it give way);
  - `switchedOff` (every song with the origin, why `.switchedOff`), `deleted` (what Phase 2's rule would delete of
    the takes - always library-only songs; the tests compare it with the database), `listed` (the Library's
    Downloaded: an album only the library wants is listed once a song of it is here or on its way), `progress`
    (Downloading's row: albums that fit and aren't all here, of all that fit, bytes to come; an album whose missing
    songs all failed isn't counted), `mark` (the album page's: `downloaded`, `waits`, `keptOff`).
  - `AutoDownload`: the switches' keys - `autoDownloadLibrary`, `autoDownloadOnlyWhileCharging` (slice 3's),
    `autoDownloadAsked`.
- **DownloadPlan**: `Asked.libraryRank`; a song only the library wants (`isLibrary`) is planned in a unit
  `library:<album>` after every hand unit, by the fill's order. The planner was rebuilt on one `walk`: library units
  are checked against the phone's reserve only (the fill already held them to the limit), and a hand unit's room
  credits the library's bytes here (`Facts.libraryHere`) - they are the library's to give back, so a hand download is
  never held for them. `handToCome` - what the hand downloads that fit have yet to receive - feeds the fill.
- **LibraryFollow**: `sync(..., believing:)` - you answered Remove to the question, so a held empty list's or drop's
  absences are believed, marked missing and **still removed only by a second check 10 minutes on**; `keepsBelieving`
  (a list that wasn't held on its own ends it, as does one leaving nothing missing); `asks(held, keptThem:)` (the
  question shows for an empty list or a drop, until Keep Them; never for a truncated list); `FollowedSong.song`.
- **DownloadRules**: `DownloadChoice.forSong(_:keptByLibrary:)` and `forSongs(_:gone:keptByLibrary:)` - no song-level
  Remove Download for a song your library keeps (it would come back at the next turn; remove its album instead).
- **DownloadDatabase**: `setKeptOff(album:at:)`; meta `library_believe`, `library_held_kept`, `library_removed` (the
  albums the last checks removed whose downloads haven't been let go - written with the list, cleared only after the
  takes succeed), all forgotten with the library.
- **AutoDownloadWords.swift** (new): the spec's 1.2 lines - the switch and its note, the fit and reading lines,
  Checked and Couldn't check, the question and its buttons, Downloading's row, You's footer, the album page's lines,
  the menu titles, the mine block's line, Remove All's addition, the first ask. LibraryFollowWords lost Debug's switch
  line.

### The app

- **LibraryFollower**: the switch is `on` (AutoDownload.libraryKey, per phone; slice 1's `debugFollowLibrary` key is
  removed). Off stops it and lets go of everything the library downloaded (`switchedOff`), **keeping the list**, so
  turning it on again says what fits at once. A check also works out `removed` (the albums to let go, kept until
  DownloadModel acts), `believing` and `keptThem`, all written in the check's one transaction; `fresh` is false until
  a check answers after the store opens or the switch goes on - until then nothing new is asked for from a list that
  may be days old (its removals stand). `changed` asks DownloadModel for a plan after each check and each batch of
  reads; Keep Them, Remove (believe, the ETag dropped so the next check is a 200, a check at once) and `setKeptOff`.
- **DownloadModel**: every plan, with the switch on, builds the store's songs and the turn, publishes the fill and
  the progress, acts (takes through `removeOrigins(LibraryDownloads.gives, ...)`, then `wantLibrary`: the asks in
  one transaction, `addOrigin(.library)`, each album's answer, cover and loudness kept as a hand download's) - and
  plans again after. The planner's facts carry `libraryHere` and each song's `libraryRank`. An album's Remove
  Download takes `.song`, `.album(id)` and `.library` and marks it kept off; an album's Download clears the mark;
  Remove All turns the switch off first. Downloaded and the albums count list only `listed` albums; Downloading's
  albums leave out the library-only ones (the one row has them).
- **You > Downloads**: "Your library" ("The collection") after Storage - the switch and its note, the fit line with
  a bar (amber when not all fit) or the reading line, the question with Keep Them and Remove, and "Checked ..." or
  "Couldn't check with deadwax" under it. Downloading's first row is the library's (a tap opens the Library's
  Downloaded); pull to refresh checks now. Remove All's message adds the switch. A failed row of a library album
  swipes to `remove(failed:album:)`: those songs' origins taken, the library's too, and the album kept off (the rest
  of it goes at the next turn; its songs downloaded by hand stay).
- **The Library**: the first-ask card at the top of the root (3.2) - shown once per phone, while the switch is off and
  the Library has albums and is online; Turn On or Not Now puts it away for good.
- **The album page**: the menu headed "Downloaded with your library" for an album it downloaded; a line under the
  title for one that waits for room or that you removed; the mine block's "Its download goes from this phone too."
  on Remove from my library when the library downloaded it and you didn't.
- **You's Downloads row** falls back to the library's footer ("Your library: 38 of 412 albums to go").
- **Debug**: no switch (it's You > Downloads'); Held back says "believing (Remove)" or "kept them", "Removed, to let
  go" counts `removed`, and the fill shown is DownloadModel's.

### Decided here (the spec was silent, or this departs from it)

Written into the spec's 6.5 too:
- **Remove on the question still waits for a second check.** The spec's 2.3 has Remove act on the held list; built,
  Remove makes the next checks believe such a list (`believing`), and its absences go by the same two-checks rule -
  so one bad answer never deletes, even after a tap. The question stays until a list isn't held.
- **Removed here goes when the next list confirms it** (open question 9's "at once"): a check is made straight after
  Remove from my library answers, so in practice within seconds.
- **Another scope now drops only the ETag**, not the list (slice 1 forgot it): the next 200's absences are judged by
  the drop rule, and a scope change that empties the list is held like any other.
- **Nothing new is asked from a kept list until a check answers** (`fresh`).
- **10 albums on their way at once**, and **nothing asked below an album still to read** - the spec didn't say how
  much to hand over at once; a library of thousands asked in one go would keep thousands of answers, covers and
  loudness fetches and tasks in flight.
- **A song your library keeps has no Remove Download of its own** (it would come back); a failed library song's
  swipe lets it go and keeps its album off (its songs downloaded by hand stay).
- **The Library's Downloaded lists a library album once a song of it is here or downloading** - not while it only
  waits its turn (open question 15's "nowhere but the fit line").
- **Debug's switch is retired**; the switch is You > Downloads'.

### Tests

Core 1136 (from 1084): **LibraryDownloadsTests** 35 - each strict rule as its own test (the origin taken, a hand,
album, playlist or other origin never deleted, the switch off, every delete equal to Phase 2's rule, and one in a
real store: a library-only song deleted and the hand, album and playlist songs, kept plays, starts and the queue all
kept; an empty list, a drop and a truncated list deleting nothing, then or an hour later or as a 304; an album absent
for any other reason keeping its songs; two checks ten minutes apart, nine not enough, back before the second keeping
everything, removed here, believing still waiting and ending), then the fill's give-way, kept off, a song no longer on
its album, an unread album, the asks, Downloaded, progress, the page's mark and the song-level Remove. Most run the
pipeline whole - `LibraryFollow.sync`, then `ordered`, then `turn`. **LibraryPlanTests** 8 (the planner's library
units), **AutoDownloadWordsTests** 8 (every line, and the words never used), **LibraryDatabaseTests** +1 (kept off).

**Mutations, 31, each caught by a failing test** (scratchpad mutate2.py, every file restored after): the library
giving `.song` too; deleting over every origin; takes from any song; the switch off taking from any song; the fill
counting hand songs as the library's; no origin read as the library's; an album absent from the table taken; an
empty list not held; a drop not held; a truncated list believed; believing never ending; Keep Them asked again; a
missing album taken; ten minutes as `>`; nine minutes; kept off not given back; a song no longer on its album kept;
an unread album given way; hand bytes taken as room; asking past an album still to read; no limit on albums at once;
asking for an album removed here, or a missing one; asking only songs not in the store; library units before hand; a
hand unit not crediting the library's bytes; library units held to the limit; hand-to-come counting the library's;
progress counting failed albums; Downloaded listing waiting albums; a library song's own Remove offered.

### Verified, and not

Verified (2026-11-13, this Mac, Xcode's toolchain): `swift test` - Core 1136, DeadwaxAudio 158, DeadwaxTurntable 11,
all pass; the 31 mutations; the unsigned Release device build (0.8 (8)); check_project.py with the .xcodeproj
unchanged; `pytest tests/test_ios_*.py tests/test_source_bytes.py`; the ios sims on Node 22. Not run: Core on Linux
(ios.yml's ubuntu job will).

Not verified: anything on a phone - checks 50-53 and 55-60 in docs/ios.md (54 and 61-63 are slice 3's): an
overnight fill and its time, a star and an unstar elsewhere, Add and Remove here, the limit lowered, a hand download
on a full phone, Remove Download kept off, the first ask, Remove All, an empty list asked. Nor whether the phone's
free-space reading agrees with Settings near the 2 GB floor, nor what a library of thousands costs the plan, which
now builds the store's songs at every turn. Nothing drawn has been seen.

## Phase 3, after the review of slices 1-2 (2026-11-13)

The review of 481c736 and 5fa6cf4 found nothing that breaks the hard rules: only `[.library]` is ever taken, the
empty, drop and truncated lists hold, two checks 10 minutes apart, the migration is safe, nothing crosses people. It
found thirteen real problems in the fill, the planner and the edges. Each is fixed below, and each that can be is a
Core rule with a test seen failing with the rule broken. The spec's 6.6 says what changed against its sections;
docs/ios.md says it for James.

### What was wrong, and the fix

1. **An album's own cover pushed it out of the fill, in a loop (HIGH).** `bytesHere` counts every kept cover; the
   fill counted the bytes here minus the library's songs as hand bytes. So an album that fit with less than its
   cover to spare was asked for, its cover kept (keepAlbum), and then didn't fit. It was given way (audio deleted,
   cover removed), fit again, and was asked again: a loop that deleted audio and asked deadwax for the album, cover,
   level and loudness each time. Fix: `LibraryDownloads.inputs` counts an album that only the library wants with its
   own cover, in what it takes and what it has here (`LibraryFill.albumAllowance`, 1 MB, until its answer is kept;
   DownloadModel's `keptCoverBytes` from reload). An album with a hand song leaves its cover to the hand download.
   And **hysteresis**: a new album fits only with `margin` spare (50 MB, or 1% of the limit if more); a held one
   (`AlbumFacts.held`: a song of it asked or here under the library) keeps its place while it fits at all. **A
   deliberate variant**: the review suggested a held album keep its place until the shortfall passes the margin
   (over the limit). This puts the same band below the limit, so the limit is never exceeded.
   `anAlbumAtTheEdgeIsNeverAskedAndGivenWayInALoop` runs the store turn after turn (a `Store` simulation: takes by
   Phase 2's rule, covers written as keepAlbum writes them, a 3 MB cover - more than the allowance). Inside the
   margin, the album is asked for once and never taken in six turns. With only 200 KB to spare it waits `room`
   every turn, never asked.
2. **The phone's budget evicted albums here while it had room (MEDIUM).** It credited the library's bytes here as
   room, so a new star above albums here could push them out on one reading of the free space (2.5 GB free, b and c
   here at 5 GB each, a 1 GB star above them: c went). Fix (LibraryFill.plan's second pass): new albums fit into
   `free - handToCome - reserve`, less what the held albums have yet to receive (their claim first), with the
   margin. Held albums are never judged against the phone. Only `deficit = reserve - (free - handToCome)`, when
   positive, makes albums here give way: from the bottom, only until the deficit is freed, and only with
   `deficitConfirmed` - two plans at least `deficitConfirmMs` (3 minutes) apart both saw a deficit
   (`deficitSince`/`deficitConfirmed`, kept by DownloadModel on `ProcessInfo.systemUptime`, a plan asked for when it
   can be confirmed). A plan without a deficit forgets it.
3. **Hand downloads queued behind the library's tasks (MEDIUM).** Outs were kept and counted against the 100, so 100
   library tasks out left a hand album none. Fix: `DownloadPlan.libraryMaxOut = 20`. Hand outs are counted first, as
   Phase 2 counts them. The library's share is min(20, 100 - hand outs). Its outs beyond that, after the first in the
   fill's order, are let go with their resume data kept.
4. **A song "no longer on its album" went on one read, even an empty one (MEDIUM).** Fix: `LibraryFollow.read`
   takes in an answer only if it has songs (nil otherwise: the album stays as it was, a failed read). It marks each
   library song the answer hasn't got in `FollowedAlbum.left` with the first read without it (store version 5's
   `left_songs`). `actions` takes `notOnAlbum` only for `leftAgreed`: a read 10 minutes or more after that mark
   still without it. Until then the song is read on that album (`LibraryDownloads.songs` maps the left marks). One
   back on the album loses its mark. The old test that expected the deletion on `songs: []` now expects agreed marks.
5. **Bulk deletes without a confirmation (LOW-MEDIUM).** The switch off (and VoiceOver's action) now asks when
   `switchOffLoses` finds anything here: "Remove the 412 albums downloaded with your library?", "They go from this
   phone (12.4 GB). What you downloaded yourself stays.", Turn Off and Remove, Cancel. The switch stays on until the
   answer. Didn't download's swipe on a library album keeps its behaviour (the failed songs go, the album is kept
   off). When `keptOffLoses` > 0 it asks first ("Leave Dummy off this phone?" - "Its 9 songs already here go too"),
   its button red without the destructive role, so a full swipe doesn't take the row before the answer
   (`FailedRow`, split out of FailedSection, whose body the type checker gave up on).
6. **Kept song lists were never refreshed (LOW-MEDIUM).** Fix: `toRead(now:refreshing:)` adds, after the unread and
   the second reads due (`secondReadAt`), up to `refreshesPerCheck` (20) albums whose songs are `refreshAfterMs`
   (7 days) old, the oldest first, within the four-at-a-time reads. An album page's fresh answer reads its album
   again (`LibraryFollower.pageRead`, from DownloadModel.albumAnswered, before its guard). Songs that left go only by
   fix 4's rule.
7. **Remove on the question could be undone by a check in flight (LOW).** `keepsBelieving` keeps it on a 304 of a
   held list, and `removeThem` bumps `believeToken`: a check out when Remove was answered keeps believing and drops
   its ETag, so the next list is asked afresh.
8. **Removing your last album here asked the empty-list question (LOW).** The empty list is held only while an album
   not removed here is kept, and counts only those. This is a little stricter than the review's
   `isListed && removedHere == nil`: a missing album removed here doesn't hold an empty list either.
9. **A removed album's songs matched by album id only (LOW).** The follower keeps each removed album with the songs
   it was last read with (and its left marks) - `removedSongIDs`, meta `library_removed` as JSON via
   `LibraryFollow.removedRaw` / `removed(raw:)`, slice 2's lines still read. `actions` takes `removedSongs` by id,
   but not a song read on an album still in the library (a retag that moved it).
10. **Four unreadable albums stalled every later read (LOW).** Failed reads are skipped and the reads go on, up to
   `readFailuresPerRun` (12) a run. An album fails at most once a check (`failed`). One that failed at an earlier
   check is read after the rest (`retryLast`, the follower's `failedBefore`).
11. **A hand download could go below the floor (LOW).** The planner credited the library's bytes the fill never
   gives back. Fix: `LibraryFill.givable(albums)`, the bytes here of read or kept-off albums, is the one number: the
   planner's `Facts.libraryHere` and the fill's fixed bytes (`bytesHere - givable`). And a hand unit taken on with
   that credit, but short of the phone's room as it is, waits `phoneFull` with no task (still in `handToCome`, so the
   fill makes room): a hand download never takes the phone under its reserve waiting for the library. So on a full
   phone it waits the deficit's 3 minutes.
12. **Phase 2's paths, run far more often by the library (LOW).** removeOrigins forgets kept albums only from a read
   of the songs that answered (a failed read had read as no song left, deleting every kept answer, cover and
   loudness). settle sweeps `DownloadRules.unnamedFiles`: song names (`StreamCache.isSongName`, never a part) in the
   store's own music folder that no row names, only after a read of the rows that answered.
13. **lastBegan and the wall clock (LOW / docs).** The notes said a failed check changes nothing, not even
   `lastBegan`; the code set it before the fetch. Now it is set as the check goes out (a moment meanwhile doesn't
   ask another) and put back when it fails. The 10-minute rules stay on the wall clock: a clock moved forward between
   two checks could agree early. Noted (docs/ios.md), not built. The deficit's 3 minutes are on the uptime clock.

### Core

- **LibraryFill** rewritten: `AlbumFacts.toCome`/`held`, `Facts.deficitConfirmed`, `margin(limit:)`,
  `albumAllowance`, `deficitConfirmMs`, `deficit`, `deficitSince`, `deficitConfirmed`, `givable`; `Plan.deficit`.
  The two passes as above.
- **LibraryDownloads**: `inputs(ordered, songs:, covers:)` -> `Inputs { albums, hand, givable }` (`fillInputs`
  retired); `turn` from songs and covers, or from inputs, with `removedSongs` and `deficitConfirmed`; `actions` with
  `removedSongs` and `leftAgreed`; `switchOffLoses`, `keptOffLoses`; `songs` reads left marks onto their album.
- **DownloadPlan**: `libraryMaxOut`; `walk` returns the units `taken`; `handToCome` sums those; a credited unit short
  of the phone's room waits `phoneFull`; the library's share of tasks out.
- **LibraryFollow**: `FollowedAlbum.left`, `leftAgreed`, `secondReadAt`; `read`, `unread`,
  `toRead(failed:retryLast:now:refreshing:)`; `refreshAfterMs`, `refreshesPerCheck`, `readFailuresPerRun`; the 304
  in `keepsBelieving`; the empty list's count; `removedRaw`/`removed(raw:)`.
- **DownloadDatabase** version 5: `left_songs`, read and written by `library()`, `putLibrary` and
  `setLibrarySongs(album:songs:left:at:)`; `execute` internal for the migration test. **DownloadRules.unnamedFiles.**
  **AutoDownloadWords**: `offTitle`, `offMessage`, `offAndRemove`, `keepOffTitle`, `keepOffMessage` (in `everyLine`).
  **LibraryFollowWords**: Debug's `underReserve`, `leaving`.

### The app

DownloadModel: `keptCoverBytes`, the inputs built once per plan (their `givable` the planner's `libraryHere`), the
deficit clock and its replan (`deficitConfirmed(_:)`, `libraryDeficitConfirmed` for Debug), `removedSongs` passed,
`librarySongs(of:)` given to the follower, `pageRead` from `albumAnswered`, the guarded cleanup in removeOrigins, the
sweep in settle, `switchOffLoses` and `keptOffLoses(album:)` for the confirmations. LibraryFollower: the removed map,
the reads through `LibraryFollow.read`, failures skipped and capped, stale and second reads, `failedBefore`,
`believeToken`, `lastBegan` put back, `pageRead`. DownloadsScreen: the switch's confirmation, `FailedRow` and its
confirmation, `removable(asks:ask:)`. Debug: Leaving their albums, and the deficit under the fit line.

### Tests

Core 1160 (from 1136): **LibraryReviewTests** 22, one or more for each fix (the cover loop run turn after turn;
a new star never pushing an album here out; the deficit only, and only once confirmed; its state machine; the
planner's credit and the hand hold; a hand album's tasks with a hundred of the library's out; reads marking what left,
a second read 10 minutes on agreeing, an empty read refused; the second read due; stale lists read a few a check,
the oldest first; failures last; a 304 keeping Remove; the last album removed here; removed songs by id and not from
an album still in the library; the removed map's codec; what the confirmations count and say; Debug's words; the
sweep's names), **LibraryDatabaseTests** +2 (`left_songs` round trip; a version-4 file migrated, its row kept).
Slice 2's tests changed where the rules did: the notOnAlbum cases take agreed marks, the phone's give-way takes a
confirmed deficit (and a once-seen case gives nothing), the credited hand unit waits `phoneFull`, 50 hand songs with
120 of the library's make 50 + 20 tasks, the fit lines leave the margin.

**Mutations, 36, each caught by a failing test, none by a build error** (scratchpad mutate_review.py, every file
restored byte for byte, sha-256 checked): a new album needing no margin; a held one needing it too; an album's cover counted as the hand downloads'; no cover in an album's need; a held album judged against the phone like a new one; the held albums' claim not first; new albums fitting without the hand downloads to come; the deficit giving way unconfirmed; everything here giving way rather than the deficit; a plan without the deficit not forgetting it; no library cap on tasks out; every library task out kept; library outs counted against the hand's; not on its album on one read; an empty read taken in; agreed at the first read; the first read's time not kept; a left song read on its record's album; stale lists read again uncapped; stale lists newest first; the second read before it is due; an album that failed before read first; a 304 of the held list ending believing; the empty check counting albums removed here; the removed albums' songs ignored; taken by id from an album still in the library; slice 2's removed lines not read; givable counting an album being read again; a credited hand unit's tasks made at once; handToCome counting units not taken on; any file no row names swept; named files swept; turning off counting songs wanted by hand; keeping off counting them; `left_songs` not written; a read's left marks not written.

### Verified, and not

Verified (2026-11-13, this Mac, Xcode's toolchain): `swift test` - Core 1160, DeadwaxAudio 158, DeadwaxTurntable
11, all pass; the mutations; the unsigned Release device build with no warnings; check_project.py with the .xcodeproj
unchanged; `pytest tests/test_ios_*.py tests/test_source_bytes.py`; the ios sims on Node 22. Not run: Core on Linux.

Not verified: anything on a phone, and the App-side wiring that has no Core test: the deficit's replan firing 3
minutes on, the sweep at settle, the guarded cleanup, `pageRead` from an album page, the failure cap and the
`retryLast` order in the run, `believeToken` with a check really in flight, `lastBegan` put back. Nor are the two
confirmations, as drawn and spoken: a full swipe on a row that asks should spring back while the question shows.

## Phase 3, slice 3: only while charging, and in the background (2026-11-13)

The spec's 2.8 and 2.9 and open question 11, taken literally, on branch `phase3-autodownload` from db805b2 (slices 1-2
with the review's fixes). **App 0.9 (9)**, the phase's version: Base.xcconfig, check_project.py, ios.yml's Info.plist
check, tests/test_ios_install.py, YouView's comment, ios/README.md and docs/ios.md, as 0.8 did. src/__init__.py
untouched; no server change. The spec's 6.7 says what the build decided; docs/ios.md says it for James.

### Core (DeadwaxCore)

- **`DownloadWait.charging`** (raw `charging`): a setting's wait (`isTheSettings`), so an album's download menu names
  it - "Waiting for the phone to charge", "Only while charging is on - in You > Downloads."
- **DownloadPlan**: `Facts.onlyWhileCharging` and `charging`, and `libraryWaitsToCharge` (on, and not charging). In
  the walk, a library unit then waits `charging` after the shared waits and before the room, started or not, and
  holds no room. In the plan, its tasks out are let go - `charging`, no task - so the app cancels them with their
  resume data. With Only while charging on, **one album at a time**: the batch is the first library unit with a task
  out, else the first reached that may make one. Only its outs are kept, within the library's 20. No other library
  unit makes a task, so a big album is handed over 20 at a time, never beside another.
- **LibraryBackground**: the two identifiers (`identifiers`, which check_project.py reads), `refreshAfterMs` (15 min),
  `readsPerRun` (20), `openWaitMs` (10 s), and `asks(on:onlyWhileCharging:waits:)`: the refresh with the switch on,
  the charger's too with Only while charging on and a song waiting `charging`. `Run` and `Outcome` (ran, off,
  couldntAsk, expired), `keep` (newest first, 5), `raw`/`runs` (JSON for UserDefaults, an unreadable list read as
  none). **PowerState** (unknown, unplugged, charging, full): `charging` is charging or full, never unknown.
- **Words**: AutoDownloadWords' `onlyWhileCharging` and `chargingNote(scope)`, both in `everyLine` (the ban list
  over them); LibraryFollowWords' `power`, `backgroundRun`, `noBackgroundRun` (Debug).

### The app

- **DownloadModel**: `onlyWhileCharging` (UserDefaults `autoDownloadOnlyWhileCharging`, a replan on change), `power`
  (UIDevice.batteryState with monitoring on; its notification, and `readPower()` at becoming active, every background
  run and every relaunch for the session's events), both passed to the planner's Facts. The plan's existing let-go
  does the unplug's cancel, with resume data. `askBackgroundTasks(always:)` asks BackgroundWork for
  `LibraryBackground.asks(...)` - always at the move to the background and after a run, and when a plan in the
  background changes the set. `backgroundRun(task:)` reads the power, runs the follower's `background(reads: 20)`,
  waits for the plan to settle (5 s at most), keeps the Run (UserDefaults `libraryBackgroundRuns`) and logs it.
  `eventsHandled()` waits for a plan after a relaunch's events, so the next batch is handed over before suspension.
  `libraryAlbumsOut` for Debug.
- **LibraryFollower.background(reads:)**: waits up to 10 s for the store and `canAsk`; makes `check(.background)`
  unless a check began within the minute (`due(.front)` - a launch for the task already made the opening check),
  else starts the reads; caps the reads at 20 albums (`readCap`, lifted as it returns); waits for the run to end or
  the task to be cancelled; answers whether a check that stands for the run answered, and how many albums it read.
- **BackgroundWork** (App/Downloads, `import BackgroundTasks`, never in Core): registers both identifiers on the main
  queue from the app delegate's didFinishLaunching; `ask(_:)` submits the BGAppRefreshTaskRequest (earliestBeginDate
  15 minutes on) and the BGProcessingTaskRequest (requiresExternalPower, requiresNetworkConnectivity) and cancels
  what isn't asked; a run is DownloadModel's in a Task, its expiration cancelling it, setTaskCompleted called exactly
  once (`Completion`).
- **DeadwaxApp**: `@UIApplicationDelegateAdaptor(AppDelegate.self)`; `BackgroundWork.shared.downloads` set in init,
  before the delegate registers; the `.backgroundTask(.urlSession)` closure awaits `eventsHandled()` after
  `eventsDelivered()`.
- **You > Downloads**: Only while charging under the fit line while the switch is on (`ChargingToggle`), read by
  VoiceOver as one switch with its note as the hint. **Debug > Your library**: Power, Albums out, and In the
  background (the five runs, or "No background runs yet").
- **Info.plist**: UIBackgroundModes `audio`, `fetch`, `processing` (audio first: ios.yml reads `.0`), and
  BGTaskSchedulerPermittedIdentifiers with both identifiers. **check_project.py** checks the modes and that the
  identifiers are exactly LibraryBackground.swift's, in order, under the bundle id: for a missing one
  BGTaskScheduler.register returns false and its task never runs (after the review; it said "crash" here). **ios.yml** asserts the built Info.plist's `UIBackgroundModes.1/.2` and
  `BGTaskSchedulerPermittedIdentifiers.0/.1`, and 0.9.

### Decided here (the spec was silent, or this departs from it)

Written into the spec's 6.7 too:
- **One album at a time within the library's 20**, not 2.8's "its songs, or 20, whichever is more": the review's cap
  stands, and an album over 20 songs goes 20 at a time, never beside another.
- **The batch is the first album with a task out**, so a new star above doesn't displace what iOS may be fetching.
- **The batch rule holds whenever Only while charging is on**, plugged in or not.
- **The charging wait holds no room and the fill doesn't see it**: Only while charging never makes anything go.
- **`unknown` power is not charging.**
- **A background run checks only if no check began within the minute**, and reads at most 20 albums.
- **The deficit is never confirmed by a run that launched the app**: deficitSince is per process, on the uptime clock,
  and 3 minutes outlast the ~30 s iOS gives - conservative, and the same rule as in front.
- **The tasks are asked at the move to the background, after each run, and when a background plan changes the set**;
  a relaunch for the session's events waits up to 5 s for a plan.
- **Debug keeps the last five runs**, per phone.

### Tests

Core 1171 (from 1160): **LibraryChargingTests** 11 - the library waits unplugged and a hand download doesn't (nor a
song you and the library both want), plugged in or off it goes; the shared waits first; an unplug lets the library's
tasks go and keeps the hand's (and `handToCome` is the hand's alone); one album at a time, and off the library's 20
across albums; the batch the first album with a task out, the others' let go; a big album 20 at a time beside a hand
album's 10; an album waiting for the phone isn't the batch; PowerState; the asks; the runs kept and their codec; every
word. DownloadWordsTests' every-wait map has `charging`. **tests/test_ios_install.py**: 0.9 (9), and
`test_your_library_may_run_in_the_background` - the real Info.plist's modes and identifiers, and each missing,
reordered or renamed one (in the plist or in LibraryBackground.swift) named by check_project.py.

**Mutations, 17, each caught by a failing test, none by a build error** (scratchpad mutate_s3.py, every file restored
byte for byte, sha-256 checked): the charging wait gone; hand downloads waiting too; the library waiting while
charging; an unplug keeping the tasks as queued; the charging wait before the shared ones; new tasks spanning albums;
no batch from the tasks out; the batch the first album rather than the first with a task out; the other albums'
tasks out kept; the charger's task asked with nothing waiting; tasks asked with the switch off; runs kept oldest
first; six runs kept; full not charging; unknown charging; the wait not a setting's; the wait's words.

### Verified, and not

Verified (2026-11-13, this Mac, Xcode's toolchain): `swift test` - Core 1171, DeadwaxAudio 158, DeadwaxTurntable 11,
all pass; the 17 mutations; the unsigned Release device build with no warnings, its Info.plist 0.9 (9) with audio,
fetch, processing and both identifiers; check_project.py with the .xcodeproj unchanged; `pytest
tests/test_ios_*.py tests/test_source_bytes.py` 161 passed, 1 skipped; the ios sims (10) on Node 22. Not run: Core on
Linux (ios.yml's ubuntu job will).

Not verified - only the phone can tell, and none of the App's wiring has a test:
- Checks 54 and 61-63 in docs/ios.md: an unplug's wait and its resume, a hand download not waiting; whether iOS runs
  the refresh at all for a free-account install, and how often; an overnight unplug costing at most one album, and
  whether the charger's BGProcessingTask runs overnight; VoiceOver and the largest text on both switches, the card and
  Downloading's row.
- **Whether `@UIApplicationDelegateAdaptor` leaves SwiftUI's `.backgroundTask(.urlSession)` delivering the session's
  events** (the delegate doesn't implement handleEventsForBackgroundURLSession). Phase 2's background downloads
  depend on it: a download finishing with the app suspended must still land.
- That registering from didFinishLaunching under SwiftUI's lifecycle is in time (a registration after the launch
  ends raises; one for an identifier not in Info.plist returns false, and its task never runs).
- Whether the battery-state notification arrives promptly in front and playing, and what a background launch reads
  before it.
- Whether a relaunch for the session's events comes after each batch, or only once every task of the session (hand
  downloads included) has ended, and whether 5 s is enough for the plan to hand over the next batch.
- How long the discretionary tasks iOS makes in the background wait for power and Wi-Fi.
- That the store and UserDefaults read in a background launch with the phone locked (after the first unlock).
- What BGTaskScheduler.submit says with Background App Refresh off or in Low Power Mode (a "background: couldn't ask"
  line in the downloads log).
- Nothing drawn has been seen.

## Phase 3, slice 3, after its review (2026-11-13)

The review of 953b8e5 found nothing that breaks Phase 2 and nothing that deletes what the front wouldn't. It checked
the biggest risk against the iOS 27.2 SwiftUI binary: SwiftUI's own app delegate implements
handleEventsForBackgroundURLSession, and reaches the adaptor only through forwardingTarget for what it doesn't
implement - so `.backgroundTask(.urlSession)` keeps its events, and the adaptor stays (as Apple DTS recommends). Eight
fixes, each below; the spec's 6.8 says them against its sections. The app stays 0.9 (9).

### What was wrong, and the fix

1. **An expired run lost the next refresh, and runs had no deadline.** A refresh's request is used up when it runs,
   and the next was asked for only at the run's end. Fix: BackgroundWork.run asks first
   (`askBackgroundTasks(always: true, ran:)`). The run has its own deadline: the follower is waited for
   `followMs` (15 s, the store's 10 s opening wait within it), then stopped, and the plan settles within `runMs`
   (20 s). The expiration handler still cancels the run, and `Completion` tells the task once.
2. **The background read cap let the plan ask below unread albums** (6.5's rule): with the cap's stop, `running` went
   false and so did `readsPending`. Fix: `LibraryFollow.readsPending(running:cutShort:ordered:)` and
   `cutShort(after:was:)` - a cut (the cap, or a run's end) holds until a run reads to the end. Too many failures
   still moves on, as 6.6 decided, and a run that couldn't ask changes nothing. The follower keeps `cutShort` and
   sets it from each run's `ReadsEnd`, and `cameToFront` carries cut reads on at once, due or not.
3. **A shared wait hid the charging wait**, so the charger's task was never asked for (Wi-Fi only on cellular, deadwax
   unreachable, no network). Fix: `LibraryBackground.asks(readable:on:onlyWhileCharging:libraryToCome:ran:)` answers
   ask, cancel or leave for each request. The charger's is asked with the switch and Only while charging on and songs
   only the library wants still to come (`libraryToCome`), whatever wait they show. That holds plugged in too - the
   review said "and not charging", but an unplug while the app is suspended is never told, and a request needing
   power costs a run at most. With the store not open it is left as it is.
4. **One stuck task pinned the batch** (a background task can take days to time out). Fix: DownloadModel reads each
   library task's bytes from the session at each plan with Only while charging on (`readStalls`, the continuous
   clock, so a locked phone's sleep counts). It passes `idleMs` on `DownloadPlan.Asked`. A task out with nothing
   for `stallMs` (30 min) is `stalled`: with Only while charging on it is let go with its resume data and made
   again at the next plan, and an album whose every task out has stalled isn't the batch. A task first seen now,
   or made again, starts from now, so a short background launch never finds one stalled. Off, nothing changes.
5. **The relaunch's handling could run past 30 s** (25 s of events, then 5 s of plan). Fix: one budget,
   `eventsMs` (25 s), from the closure's start: the plan gets `LibraryBackground.left(...)` of it.
6. **Work went on after expiry**, and two runs shared one cap. Fix: a run that ends with the follower's run still
   under way, the app still in the background, stops it (`stopBackgroundRun`: the generation bumped, as a closed
   store's are). Its check still out is dropped as a failed one is, `lastBegan` put back. Each run has its own
   `BackgroundReads` (cap and count); the reads stop at the least any run has left.
7. **check_project.py** requires UIBackgroundModes exactly `audio, fetch, processing` (ios.yml's `.0`-`.2`). Its words
   are corrected: a missing identifier makes `register` return false and the task never run - not a crash.
8. **A launch before the phone's first unlock** reads UserDefaults as empty: the switch off, so a run would have
   recorded "off" and cancelled both requests. Fix: `LibraryBackground.stateReadable(kept:protectedDataAvailable:)`.
   Every readable launch leaves a mark (`libraryStateReadable`); a launch is readable if it found the mark, or the
   phone is unlocked at didFinishLaunching (a first launch ever). Unreadable: every request is left as it is (but
   the one the run used up, put back), no run is kept, nothing is asked. `isProtectedDataAvailable` alone wouldn't
   do: it is false whenever the phone is locked, when nearly every run happens.

### Core

`LibraryFollow.ReadsEnd`, `cutShort(after:was:)`, `readsPending(running:cutShort:ordered:)`. `LibraryBackground.Ask`,
the new `asks`, `libraryToCome`, `stateReadable`, `readableKey`, `followMs`, `runMs`, `eventsMs`, `left`.
`DownloadPlan.stallMs`, `Asked.idleMs` and `stalled`, the batch's choice and its outs.

### The app

LibraryFollower: `background(reads:until:stop:)`, `BackgroundReads`, `cutShort`, `stopBackgroundRun`, `cameToFront`
carrying cut reads on, a stopped check putting `lastBegan` back. DownloadModel: `stateReadable` and
`settleReadable`, `askBackgroundTasks(always:ran:)` on Core's asks, `backgroundRun` on its deadlines and the
readable guard, `eventsHandled(until:)`, `planSettled(until:)`, `readStalls` and `progressSeen`. BackgroundWork:
`ask` of each request's Ask, the asks first in `run`, `settleReadable` in `register`, `eventsHandled(began:)`.
DeadwaxApp: the closure's start passed on.

### Tests

Core 1178 (from 1171): **LibraryBackgroundReviewTests** 7. They cover reads cut short holding the asks below them,
through LibraryDownloads.actions; the cut's table; the charger's asked under deadwax's wait, and each case of the
asks; an unreadable launch leaving everything but the request used up, and `stateReadable`; the budgets; a stalled
album not the batch, and 29 minutes still the batch; a stalled task in a moving batch let go and made again, and
nothing changed with Only while charging off. LibraryChargingTests' asks test now takes the new rule.
test_ios_install.py takes the exact order (three wrong orders named) and the new words.

**Mutations, 19, each caught by a failing test, none by a build error** (scratchpad mutate_r.py, every file restored
byte for byte, sha-256 checked):
- a cut not holding the asks; the cap's stop not a cut;
- reading to the end not clearing it; failures not clearing it; a run that couldn't ask clearing it;
- the charger's asked with nothing to come; never asked; cancelled before the store opens;
- any song counted as the library's;
- an unreadable launch read as readable; the request used up not put back;
- readable only by the mark; readable only unlocked;
- what's left going below nothing; a run's budget past 20 s;
- stalled only past 30 minutes; a stalled album still the batch;
- a stalled task kept in the batch; a stalled task let go with Only while charging off.

### Verified, and not

Verified (2026-11-13, this Mac, Xcode's toolchain): `swift test` - Core 1178, DeadwaxAudio 158, DeadwaxTurntable 11,
all pass; the mutations; the unsigned Release device build with no warnings; check_project.py with the .xcodeproj
unchanged; `pytest tests/test_ios_*.py tests/test_source_bytes.py`; the ios sims on Node 22. Not run: Core on Linux.

Not verified - none of the App's wiring has a test, and only a phone can tell:
- Whether iOS launches the app for a BGTask (or the session's events) before the first unlock at all.
- Whether `isProtectedDataAvailable` is true at didFinishLaunching on a first launch ever.
- Whether a stopped follower's dropped check costs anything at the next front.
- Whether the session's `countOfBytesReceived` moves as the bytes do, which the stall rule reads.
- The new budgets against what iOS really gives.

## Phase 4, slice 1: playlists, read and play (2026-11-13)

The first of Phase 4's five slices (notes/ios-specs/phase4-library.md, written first; the plan's section 5), on
branch `phase4-library` from `ios` b4cf8e0 (Phase 3 done, app 0.9). **The app stays 0.9 (9)** until the phase is
done (0.10 with slice 5); src/__init__.py untouched; **no server change**: the two read routes the web's Playlists
use (GET /deadwax/navidrome/playlists and /playlists/{id}, as the asker) answer everything slice 1 needs. Navidrome's
own playlists, read and played; no writes, and no playlist downloads (slices 2 and 3).

### Core (DeadwaxCore)

- **Playlists.swift**: `Playlist` (src/playlists.py's summary(): id, name, comment, songCount, duration, created,
  changed, owner, public as `isPublic`, coverArt - an empty one nil - mine, editable; read leniently, every field but
  the id defaulting), `PlaylistList`, `PlaylistWithSongs` (playlist, songs, hidden - below 0 read as 0).
  **PlaylistRules**, the web's lib/playlists.ts ported: `group(of:)` (not mine: shared; mine and editable: yours;
  mine and read-only: files), `groups` (Navidrome's order kept in each), `songCount`, `lengthText` (whole minutes by
  JS Math.round, "1h 5m" from 60), `songsLine`, `rowLine`, `ownerLine`, `readOnlyWords`, `canEdit` (slice 2's),
  `hiddenWords`, `total` (the songs' own durations, the footer's), `songLine` (a row's artist · album); the limits
  (name 200, comment 1000, 2,000 songs), PLAYLISTS_FRESH_MS (30 s) and PLAYLISTS_KEPT (8). **PlaylistWords**: the
  web's lines and the TSX's, and the phone's own (`offlineList`, `offlinePage`); `playlistsEmpty` and
  `playlistEmptyNow` (the first sentence of PLAYLIST_EMPTY) until slice 2 (question 6).
- **PlayedAlbums.swift**: the web's lib/playedAlbums.ts, generic over the album - `remember` (an album's Play: floor
  0, the last 8), `rememberQueue` (every album of a queue kept, up to 64, until the next queue; put in reverse so the
  first to play is the newest), `also` (in as the newest, letting go of nothing held, up to 64), `get`, and the
  phone's `forget` (an album gone).
- **PlaylistPlay.swift**: a playlist's songs as the queue (the web's `toQueueTrack(song, stubFor(song))`): each song
  with its own album, `albumId` nil when the song names none; `songsLevel` (`levelFor(setting, .songs)`: Automatic
  levels each song as a song); `albums` (the web's playlistAlbums: one stub per album in the order its first song
  plays, the playlist's songs of it, the album artist else the song's, a cover and year only when there is one,
  `partial`); `withHeld` (an album held whole kept as it is; an earlier stub's songs kept beside the new ones);
  `plan(songs, setting:, held:)`; `pick(name:songs:)` (the bar's •••) and `pick(song:)` (a row's).
- **`Album.partial`** (never decoded - deadwax never sends it), and Info's `AboutAlbum(album:)` passing it, so Info's
  About counts nothing of the album from a stub: "Track 5", no "of 12", no disc line, no song count.
- **Routes** `playlists` and `playlist` (Routes.all 32), and the client's `playlists()` and `playlist(id:)` (a 404
  thrown, read as `.notFound`). Models.swift's lenient `looseField`/`looseList` are now module-wide, not fileprivate,
  for the playlists' decoding.

### The app

- **PlaylistsModel** (environment, one per person, reset by whenPersonChanges): the list (asked afresh each time the
  screen shows, else not within 30 s; the newest answer only; an answer for a person no longer signed in dropped), the
  last failure, and the last 8 pages' answers (`kept`, `keep`, `forget`, `playsOffline`). **PlaylistPageModel**: the
  kept answer drawn first, then deadwax's; a 404 is gone (the kept answer let go); a refresh that fails keeps what is
  drawn; nothing asked while deadwax can't be reached.
- **The Library's root**: a **Playlists** row (music.note.list), the first of the places after the first-ask card, in
  every scope - and on the Downloaded root the Library shows while deadwax can't be reached, under the way back to the
  albums.
- **PlaylistsScreen**: a plain List - Yours and Shared with you under LibraryHeader, From files folded in a
  DisclosureGroup ("From files (3)", the screen's own state); each row the mosaic at the rows' size (or the playlist
  mark on the empty-cover square), the name, its line, read as one; pull to refresh; ErrorNote for a failure (Try
  again with no list). Offline: the list in hand draws, a row dimmed and disabled unless its kept page has a song on
  this phone; with none in hand, "Your playlists show here once deadwax is back."
- **PlaylistView**: the album page's layout - the mosaic at AlbumHero's side, the name, `ownerLine`, `readOnlyWords`,
  the comment, `songsLine`, **Play and Shuffle** (AlbumHero's PlayButtons, now internal); the hidden line; the rows,
  each with its own cover (a waveform over it for the song playing), title, artist · album, its download mark and
  time, and its ••• (the song's Play Next, Play Last and download items); the footer; the name in the bar once
  scrolled. The bar's ••• is the whole playlist's Play Next and Play Last, **with no download items**
  (`QueueMenuRequest.offersDownload` false - question 7). Offline: the songs not on this phone dimmed, Play and
  Shuffle taking those that are, a row's tap counted among them.
- **PlayerModel**: its played albums are `PlayedAlbums<Album>`; `play(playlist:at:shuffle:)` plans with PlaylistPlay
  (the held albums from `played.get`), `rememberQueue`s the albums, and starts the queue in the tap; Play Next and
  Play Last take an optional album (nil: the songs each with their own, the stubs `also`); an album page's album is
  `also` (question 8); an album gone is `forget`.
- **Routes**: `.playlists` and `.playlist(PlaylistRoute)` (the id, and the row's playlist as a preview for the hero).

### Decided here (the spec was silent, or this departs from it)

- **Questions 6, 7 and 8 built as recommended**: the empty lines' first sentences alone; no download items on the
  bar's ••• until slice 3 (so slice 3 never meets a playlist's songs downloaded as loose ones); the album page's album
  kept as `also` - which, the review found, DID let go of a playlist's albums mid-play once the floor reached 64
  (fixed: "after its review", below).
- **A row is dimmed offline unless its kept page has a song on this phone**: the list's answer says nothing of the
  songs, so only a page opened this run can open with no connection (question 5's in-memory answer).
- **The Playlists row is on the Downloaded root too**: offline the Library's root is Downloaded, and without it a
  playlist in hand could be reached only if its screen was already open.
- **The Library's Playlists row carries no count**: the list isn't asked until the screen opens (the web's phone row
  asks nothing either).
- **The lenient decoding helpers made internal** rather than copied into Playlists.swift.

### Tests

Core 1196 (from 1178): **PlaylistVectorTests** 8 - the web's own answers replayed from
`Fixtures/playlists/playlist-vectors.json` (ios/scripts/export-playlist-vectors.cjs compiles src/lib/playlists.ts and
src/lib/playedAlbums.ts; `ui/test/iosplaylists.sim.cjs` runs it with `--check`): the words and limits, the empty
line's first sentence, groups and every line over 15 playlists at 0, 1, 12, 2,000 and 2,001 songs, the groups'
order over five lists, counts, lengths (negatives too), stubs, `withHeld`, and seven PlayedAlbums runs at the bounds.
**PlaylistPlayTests** 10, by hand: each song its own album, the songs level under each setting, a plan keeping an
album held whole, the picks, the length, the row line, the screen's words and the banned vocabulary, a stub never
sent and Info's partial, the list read (an empty `{}` too), one playlist read (odd fields leniently) and the 404's
kind. InfoTests' cards take `partial` stubs; ClientTests' route count 32. **tests/test_ios_contract.py**: ROUTE_COUNT
32, and `test_the_playlist_answers_are_what_the_app_decodes` - Playlist's fields exactly summary()'s keys (only the
cover optional), a bare summary decoding, with_songs()'s three keys, and the routes sending them so.

**Mutations, 26, each caught by a failing test, none by a build error** (scratchpad mutate.py, each file restored
from its own bytes): the groups swapped; shared as yours; lengths floored; an hour at 61; no owner unnamed; public not
said; 2,000 songs refused; hidden's verb; hidden at none; hidden below none; an empty cover kept; the songs level made
the album's; no album id kept as ""; a stub over a whole album; an earlier stub's songs dropped; stubs not partial;
year 0 kept; the song artist over the album artist; a song with no album id stubbed; the queue's floor none and
unbounded; the queue played first last; `also` letting go; `remember` keeping the floor; `put` not refreshing; Info's
partial lost.

### Verified, and not

Verified (2026-11-13, this Mac, Xcode's toolchain): `swift test` - Core 1196, DeadwaxAudio 158, DeadwaxTurntable 11,
all pass; the 26 mutations; the unsigned Release device build with no warnings; check_project.py with the .xcodeproj
unchanged; `pytest tests/test_ios_*.py tests/test_source_bytes.py`, and the full suite (4351 passed, 1 skipped); the
11 ios sims on Node 22, iosplaylists among them. Not run: Core on Linux (ios.yml's ubuntu job will).

Not verified - none of the App's wiring has a test, and only a phone can tell (docs/ios.md's checks 64-69):
- That the mosaic covers (`pl-<id>_<hash>`) come through deadwax's cover route at the rows' and the hero's sizes.
- That a playlist of a few hundred songs draws and scrolls smoothly (a plain List, each row its own cover).
- That the lock screen and the mini player show each song's own album's cover as a playlist plays across albums.
- That Navidrome's real `owner` (its case, an admin's view) and `readonly` group the playlists as the web does.
- Nothing drawn has been seen: the From files fold, the dimmed rows offline, VoiceOver's reading of a row.

## Phase 4, slice 1, after its review (2026-11-13)

The review of c69f42b found no HIGH, one MEDIUM, four LOW and some gaps in the tests; all fixed in one commit on
`phase4-library`. The app stays 0.9 (9); src/__init__.py untouched; no server change; **the web unchanged** (the
MEDIUM's eviction is there too, more narrowly - below - for the coordinator to decide about on main).

### What was wrong, and the fix

- **MEDIUM - an album page shown let go of a playlist's album still to play.** PlayerModel's `albumShown` called
  `played.also(album)`, and `also` raises the floor by one for each album not held, up to 64; past it the trim lets
  the oldest album go - and `rememberQueue` puts a playlist's albums in reverse, so the oldest is the playlist's LAST
  album, still to play. A 30-album playlist lost its last album at the 35th distinct page shown; a 64-album one lost
  one at every page. Those songs' Info > About then had only the queue track (check 65 fails), Go to album the thin
  preview, Debug its album. **Fix, in Core: an album the queue names is never let go.** PlayedAlbums' `remember`,
  `rememberQueue` and `also` take `keeping` (ids), and the trim passes over every one of them - and over the album
  just put - letting the oldest of the rest go; with all that's left kept, the store holds more than its bound until
  the queue no longer names them. `QueueAlbums.named(tracks)` is the queue's ids (none for a track naming none).
  PlayerModel passes the new queue's to `rememberQueue` (so a playlist of more than 64 albums keeps them all), the
  queue's and the ones being added to Play Next and Play Last, and the queue's to `albumShown`'s `also`. Chosen over
  a separate store for pages because it states the rule itself, and covers Play Next and Play Last too.
  **A change from the web's createPlayedAlbums**, the phone's own: with `keeping` empty the store answers exactly as
  the web's (the fixture's runs pass none, and a test holds empty and left out alike). **The web has the same
  eviction**, but narrower: it calls `also` only for Play Next, Play Last (rememberAdded) and resume, never for a page
  shown, so its floor climbs only with albums added to Up Next - a queue's last album goes once 64 are held that way
  (a 64-album artist Play or playlist and one Play Next; a 30-album playlist and 35 albums Play Nexted). Not changed
  on the web here.
- **LOW - a page's answer kept under the next person.** `PlaylistPageModel.load` kept its answer in PlaylistsModel
  without asking who had asked; a load run from `onChange(of: reachability.online)` is an unstructured Task that the
  navigation's reset doesn't cancel, so one person's playlist (their mine/editable, their songs for `playsOffline`)
  could be kept under the next after a sign-out. **Fix**: PlaylistsModel's `generation`, moved on by `reset`;
  the page captures it before its await, and `keep(_:asked:)` refuses (false) an older one's answer - the page then
  draws nothing of it either, and a failure from an older one says nothing. The list's own ask checks it beside the
  person.
- **LOW - not asked again when the app came back to the front.** The web counts the app in front as shown; the
  Library's root and Up Next already react to scenePhase. **Fix**: on `.active` (deadwax reachable), the Playlists
  screen asks `fresh` and a playlist's page loads again.
- **LOW - the refresh's note lost its advice.** RefreshFailedNote passed `retry: true` to ErrorWords, but draws no Try
  again, so the line lost "Try again." and the advice of its other cases. **Fix**: `retry: false` there
  (OpenFailedNote's, which draws the button, keeps true).
- **LOW - Routes.swift**: the two playlist routes had gone in between warmLevels' `///` comment and its declaration;
  moved above the comment.

### Core

- PlayedAlbums: `keeping:` on `remember`, `rememberQueue` and `also` (default none); `trim(keeping:)`; the type's
  comment says what is the phone's own. `QueueAlbums.named`.
- `PlaylistPlay.offlineStart(row:songs:here:)` - a row's tap while deadwax can't be reached, moved out of
  PlaylistView: the row's place among the songs on this phone, counted (a song listed twice is two rows), nil for a
  row not here or not there.

### The app

PlayerModel passes `keeping` at four of its five writes (an album's own Play needs none: its queue is that album, kept
as the one just put); PlaylistsModel's generation and `keep(_:asked:)`; PlaylistView and
PlaylistsScreen on scenePhase; RefreshFailedNote; PlaylistView's `play(row:)` through `offlineStart`.

### Tests

Core 1204 (from 1196): **PlaylistReviewTests** 8 - the review's two cases (pages shown never letting go of a 30-
or a 64-album playlist, against the web's store, which does); a queue of 70 kept whole; Play Next keeping the
queue's and the added album, back within the bound once the queue names none, a kept album in the middle, remember's
own album; `keeping` empty the web's store; `forget` (gone at once, the order kept, nothing for one not held, put again
as new, a queue's album forgotten leaving the rest); the queue's ids; a row's offline start (a song listed twice, rows
not here, rows not there, every song here). **The fixture**: every album of a played run now carries the step that put
it (`s3`, `s3.1` for a queue's second), and each step records WHICH answer `get` returns for every id held - so a put
that left an old answer (a stub never replaced) fails, on both sides (the exporter records it from the web's store,
PlaylistVectorTests compares it); two new runs, an empty `rememberQueue([])` (after a queue, and with nothing) and the
same album put again by each operation; and a shared-with-you playlist with no length ("sam · 3 songs").

**Mutations, 12, each caught by a failing test, none by a build error** (scratchpad mutate_review.py, each file restored
byte for byte, sha-256 checked): the trim keeping nothing; `also`, and `remember`, letting their own album go; a queue
keeping only the web's 64; the trim letting the newest go first; a put keeping the old answer (also caught by the
fixture's tags alone, run against PlaylistVectorTests by itself); `forget` leaving the order, and forgetting nothing;
the queue naming an empty id; an offline row not on the phone starting, a start counting the row itself, and one looked
up by id.

### Verified, and not

Verified (2026-11-13, this Mac, Xcode's toolchain): `swift test` - Core 1204, DeadwaxAudio 158, DeadwaxTurntable 11, all pass; the mutations; the unsigned
Release device build with no warnings; check_project.py with the .xcodeproj unchanged; `pytest tests/test_ios_*.py
tests/test_source_bytes.py`; the 11 ios sims on Node 22. Not run: Core on Linux.

Not verified - only the phone can tell:
- That `scenePhase` reaches a page pushed under another (a page in the stack asks too: one request, harmless).
- Check 65's new step: a dozen album pages opened while a playlist plays, and Info still naming its last songs'
  albums.

## Phase 4, slice 2: Add to a playlist, New, Edit, Delete (2026-11-13)

The second of Phase 4's five slices (notes/ios-specs/phase4-library.md 2.4 and 6.2; 6.7 points here), on
`phase4-library` from `ios` 7cb2f2b (slice 1 and its review merged). **The app stays 0.9 (9)**; src/__init__.py
untouched; **no server change**: the web's four write routes (src/routes/navidrome.py's create, add, edit and delete;
notes/playlists.md) answer everything the phone needs, asked as the person signed in (the session's cookie, as every
route). **The owner check is the server's** (`_writable`: 404 GONE, 403 NOT_YOURS, 403 FROM_FILE); the phone reads
only a playlist's `editable`, to offer Edit and to list it in the picker. **Nothing is optimistic**: every write is
drawn from its answer, and a refusal leaves what is drawn as the server last said it was.

### Core (DeadwaxCore)

- **PlaylistChanges.swift** (new). The writes' bodies, each matching the extra="forbid" model it is posted to:
  `NewPlaylistBody` {name, song_ids}, `PlaylistAddBody` {song_ids, duplicates} and `PlaylistEditBody` {base, song_ids,
  tried?, name?, comment?, public?}. A nil is left out of the JSON, and `trying(_:)` puts `tried` on. `PlaylistDuplicates`
  (ask, add, skip) is the route's Literal. Their answers: `PlaylistAddAnswer` (`done` required; `already` read
  leniently and at least 0; `added` and `asked` leniently) and `PlaylistDeleted`.
- **PlaylistRules**, the web's adding half (lib/playlists.ts):
  - `picker` (pickerPlaylists): mine and editable, `changed` newest first, ties by name (see "Decided here").
  - `pickLine`, `addedWords`, `madeWords`, `hiddenEditWords` and `deleteQuestion`.
  - `duplicateQuestion`: a `PlaylistQuestion` - the text and two choices, each its label and the mode it sends (nil
    for Cancel).
  - The phone's `outcome(of:mode:pick:name:)`: an answer as `.asks(already:asked:)` (`asked` the answer's, else the
    songs sent) or `.added(words)`.
  - `PlaylistPick`, a label and the songs (each its id, title and artist), made from a QueuePick of songs or from the
    song playing.
- **PlaylistEdit**, the web's Edit half:
  - `start` keys the rows `index:id`, so a song listed twice is two rows.
  - `move` (moveRow) clamps the target into the rows. A move to where the row already is, or from outside the rows,
    leaves the rows as they were.
  - `remove` (removeRow) and `changed` (editChanged).
  - `body` (editBody): `base` is the ids as Edit began and `song_ids` the ids now. The name, description and sharing
    are sent only when they changed, trimmed as JS trims. nil when nothing changed.
  - `isRearrangement`.
  - The phone's own:
    - `Refusal` and `refusal(of:)`: a 409 is changed elsewhere, a 404 gone, the rest refused.
    - `needsName`.
    - `trimmed` (WebText.trim, JS's `.trim()`).
    - `clamped`: within a bound counted in UTF-16 units, as an HTML field's maxLength counts, never splitting a
      character.
- **PlaylistWords**:
  - From lib/playlists.ts: PLAYLIST_CHANGED, SHARED_NOTE, "A playlist needs a name." and "Discard your changes?".
  - From the web's TSX:
    - the picker's lines;
    - the menus' "Add to a playlist…";
    - NewPlaylistForm's;
    - PlaylistsPage's "Made Late night";
    - PlaylistPage's Edit, Done, Saving…, Description, Shared with everyone, Discard, Keep editing, Delete playlist,
      Keep it, Deleting… and "Deleted Late night".
  - The phone's own two: the New playlist sheet's title and Edit's "Songs".
- **Playlists.swift**: `playlistEmptyNow` and `firstSentence` are gone. The empty lines are whole now (question 6,
  done): "No playlists yet." with PLAYLISTS_EMPTY_HOW under it, and the whole PLAYLIST_EMPTY.
- **Routes** `createPlaylist`, `addToPlaylist`, `editPlaylist` and `deletePlaylist`, each a POST (Routes.all 36).
- **The client**:
  - `createPlaylist(name:songIDs:)`, `addToPlaylist(id:songIDs:duplicates:)` and `editPlaylist(id:body:)`;
  - `deletePlaylist(id:)`, with no body, since the route takes none.
- **Info.swift**: `more(…playlist:)`. Now Playing's ••• label says "add to a playlist" when the menu has the row.

### The app

- **PlaylistsModel's four writes**: `create`, `add`, `edit` and `delete`.
  - Each is asked as the person signed in, through one `write` - an unstructured Task, so leaving a screen never
    calls a write off.
  - `Superseded` is thrown when the person or the generation changed meanwhile, so nothing of that write is kept or
    said.
  - A written answer goes through `changed`, the web's announcePlaylistChanged:
    - the kept page is given the answer, or let go of;
    - the list is asked afresh;
    - `lastChange` moves on, so a page showing that playlist draws it (`PlaylistPageModel.changedHere`).
  - An add that wrote nothing (`done` false) changes nothing. `gone(_:)` is called for a 404 from any write.
- **PlaylistPicker** (new; the web's PlaylistPicker), a sheet. Where it opens:
  - MainTabs' `navigation.playlistPick`, from QueueMenu's "Add to a playlist…": the album page's bar and rows, and a
    playlist's bar and rows. Only for songs, never for a gone album's, and only while deadwax can be reached.
  - Now Playing's own sheet, from its ••• ("Add to a playlist…" after Info).

  What it shows:
  - The head is `pickLine`; "No playlists yet - make one:" when there are none.
  - New playlist… opens `NewPlaylistFields` in its row's place: Name, Create / Creating… and Cancel. The name is
    trimmed and clamped at 200.
  - Then `PlaylistRules.picker`'s rows, "Adding…" on the one being written. The list is asked afresh as the sheet
    opens.

  How it behaves:
  - **One write at a time** (question 13): every row and New playlist… wait for the write that is out.
  - Written: the sheet closes and the notice says `addedWords` or `madeWords`.
  - Some songs there already: the question takes the list's place, with two choices and Cancel back to the list.
  - Refused: ErrorNote under the head, also announced. A 404 asks the list again.
  - Closed while an add is out: the add goes on, and the notice says how it went - "Nothing added - some are in X
    already" for the question it can no longer ask, or "Couldn't add to X." and why.
- **PlaylistsScreen**:
  - The bar's + (dimmed offline) opens a sheet of NewPlaylistFields (medium and large detents).
  - Create makes an empty playlist and opens its page once the sheet has gone. If the screen isn't showing by then,
    the notice says it was made instead.
  - Empty, the screen shows PLAYLISTS_EMPTY_HOW and a New playlist button.
- **PlaylistView's Edit**, through PlaylistPageModel:
  - **Edit in the bar**, for an editable playlist, can be tapped only once this page's own ask has answered (`fresh`)
    and deadwax can be reached (`canBegin`).
  - **In Edit**: `editMode` is active; the hero stays, its Play and Shuffle dimmed (the web's), and the hidden line,
    the bar's ••• and the back button are put away. (This said the hero was put away too; corrected after the
    review.)
  - **The form**:
    - Name, with "A playlist needs a name." under a blank one;
    - Description, two to six lines;
    - Shared with everyone, SHARED_NOTE as its hint;
    - `hiddenEditWords`.
  - **Songs**: each row its title and artist.
    - One tap on the red minus removes it; the drag handle moves it.
    - VoiceOver's Move up, Move down and Remove.
    - Each change is said ("Roads: 3 of 12", "Roads removed") and the focus is kept on the row, as Up Next's Edit
      does.
  - **Delete playlist** last.
  - **Cancel** asks "Discard your changes?" when something changed.
  - **Done**:
    - nothing changed: Edit closes;
    - a blank name: nothing is sent;
    - otherwise it sends `body.trying(tried)`, showing Saving….
    - Saved: the server's answer is drawn and kept, and the list told.
    - **409**: Edit closes and nothing is saved. PLAYLIST_CHANGED shows over the page, scrolled to its top, and the
      playlist is asked again, so the next Edit's base is the fresh one.
    - **404**: the gone line, and the list forgets it.
    - **Anything else** (403 not yours or from a file, 422 only rearranges, 502 part saved or saved unread, no
      connection): Edit stays open with why at the form's top - ErrorWords, the server's own words.
      - The next Done sends `tried`, the songs this one sent, as the web does (notes/playlists.md, the review's
        "A Done refused can't be retried as it stood").
      - Leaving Edit after such a failure asks the playlist again before Edit is offered again.
  - **Delete**: `deleteQuestion` (Delete playlist / Keep it), then Deleting….
    - Deleted: the notice says "Deleted X", the page is popped if it is still on top (`navigation.leavePlaylist`),
      and the list is told.
    - Refused: why, under the button, with Edit still open.
- **AppNavigation**: `playlistPick` and `leavePlaylist(_:)`, both cleared on reset.

### Decided here (the spec was silent, or this departs from it)

- **Questions 9-13 built as recommended** (the spec's section 10):
  - one tap on the minus, not a swipe;
  - no writes offline, none queued;
  - Delete inside Edit, last;
  - New as a sheet from +, and in place in the picker;
  - one write at a time in the picker.
- **Name ties in the picker.** The web breaks a `changed` tie with ICU's `localeCompare`. The phone compares by:
  - first, the names with case and accents folded (Fold.findText), by UTF-16;
  - then the whole name, by UTF-16;
  - then the list's order.

  They agree on every tie the fixture holds. They differ only for names equal once folded: the web puts "same"
  before "Same", the phone "Same" first. That needs two of your playlists changed in the same millisecond.
  PlaylistChangeTests pins the phone's rule.
- **A gone album's songs get no Add row** (the album page's `goneButHere`): they may not be Navidrome's any more.
- **Every 409 is "changed elsewhere"**, TOO_LONG included (a playlist grown past 2,000 songs in another app since Edit
  began), as on the web. Nothing is saved and the page is drawn as it is now - which then says why there is no Edit.
- **Typed text is clamped by UTF-16 units**, as the web's maxLength counts (200 and 1,000), so the server never
  refuses a name the phone sends for its length.
- **The picker over Now Playing is Now Playing's own sheet**: a sheet on MainTabs doesn't show over its full-screen
  cover.
- **A deleted page pops only while it is on top**; under another page, it shows the gone line when you come back to
  it.
- **No write is called off by leaving**: Navidrome may have it already, and the notice says how it went.

### Tests

Core 1224 (from 1204):
- **PlaylistChangeVectorTests**, 8: the web's own answers replayed from the slice 1 fixture file, which
  ios/scripts/export-playlist-vectors.cjs now also fills with slice 2's vectors:
  - the words;
  - `hiddenEditWords` at -1, 0, 1, 2 and 10;
  - `pickerPlaylists` over six lists: none, every slice 1 playlist, changed to the millisecond, one never changed,
    ties by name with case and accents folded, a whole tie keeping the list's order, and shared, from-a-file and
    not-mine-but-editable playlists left out;
  - `pickLine`, `madeWords`, `addedWords` (ten answers, every mode) and `duplicateQuestion` (nine already-of-asked
    pairs) over seven picks;
  - `startEdit` over four songs, one listed twice;
  - every `moveRow` from -1 to 4, to -2 to 5;
  - every `removeRow`;
  - `editBody` and `editChanged` over fifteen changes from three starts, each body's JSON keys among them. The
    changes include spaces round a name (a BOM, a no-break space, a tab), U+0085 (which JS keeps), a song's two rows
    swapped, and everything at once;
  - `isRearrangement` over nine pairs.
- **PlaylistChangeTests**, 13, by hand:
  - the bodies' JSON keys, none sent for nil;
  - the add's three answers decoded, leniently, `already` below 0 read as 0;
  - the four calls: POST, the cookie, the paths, the delete with no body;
  - a refusal's words through ErrorWords (409, 403, 422);
  - `outcome`, a done false never read as written;
  - `refusal`;
  - the picker's tie on names equal once folded;
  - the picks from a QueuePick and from the song playing;
  - Edit's rows;
  - `needsName` and `trimmed`: a BOM and a no-break space trimmed, U+0085 kept;
  - `clamped`: at the bound, and a character of two UTF-16 units across it;
  - the words and Now Playing's ••• label.
- PlaylistVectorTests loses slice 1's empty-line test, and PlaylistPlayTests' vocabulary check takes the phone's
  four own lines. ClientTests' route count is 36.
- **tests/test_ios_contract.py**: ROUTE_COUNT 36, and two new tests:
  - `test_the_playlist_writes_send_what_the_server_declares`:
    - the three bodies' keys are exactly the extra="forbid" models' fields;
    - every required field is sent, and only fields with a default are optional;
    - the duplicates are the route's Literal;
    - the name, description and song bounds are the server's.
  - `test_the_playlist_writes_answer_what_the_app_decodes`:
    - the add's three answers and the delete's are within what the app decodes;
    - create and edit answer a playlist with its songs;
    - 409 CHANGED, 404 GONE and 403 NOT_YOURS are where the routes raise them.

**Mutations: 42, each caught by a failing test, none by a build error.** The scratchpad's mutate_s2.py applied each
alone and ran `swift test --filter Playlist`, then put the file back byte for byte, checked by sha-256.
- The picker:
  - newest last;
  - others' playlists offered;
  - read-only ones offered;
  - the folded names left out;
  - the whole name left out;
  - the last tie reversed.
- The words:
  - a lone song's empty artist said;
  - a song's title for one of many;
  - nothing added read as added;
  - "already" said for Add them again;
  - was and were swapped;
  - all there read as some;
  - one asked read as many;
  - "Skip that one" for many;
  - made counting two.
- An add's answer:
  - the question asking one when the answer names none;
  - no `added` read as all;
  - a done false read as done when none was there;
  - `already` below 0 kept;
  - a song with no title named by its id.
- Edit:
  - `hiddenEditWords`' verb, and its none;
  - a row keyed by its id;
  - a move past the end, or above the top, not clamped;
  - remove taking the next row;
  - a removed last row not seen;
  - rows compared by id, not key;
  - the base taken from now;
  - the name and the description sent untrimmed;
  - the name compared untrimmed;
  - sharing always sent;
  - a body for nothing changed;
  - `trying` dropping `tried`.
- A refused Done:
  - a 409 read as refused;
  - a 404 read as refused.
- `isRearrangement`: a song added, or repeated.
- A name of spaces passing.
- `clamped`: counting characters, and stopping one short.

The first pass missed four, and each was fixed:
- No test reached the raw-name tie: PlaylistChangeTests pins it.
- No answer had done false with none there already.
- No answer had `already` below 0.
- One mutation crashed on an empty pick: reworded.

### Verified, and not

Verified (2026-11-13, this Mac, Xcode's toolchain):
- `swift test`: Core 1224, DeadwaxAudio 158 and DeadwaxTurntable 11, all pass.
- The 42 mutations.
- The unsigned Release device build, with no warnings but appintentsmetadataprocessor's "Metadata extraction
  skipped".
- check_project.py, with the .xcodeproj unchanged.
- `pytest tests/test_ios_*.py tests/test_source_bytes.py` (170 passed, 1 skipped) and the full suite (4357 passed,
  1 skipped).
- The 11 ios sims on Node 22, iosplaylists' `--check` of the regenerated fixture among them.

Not run: Core on Linux (ios.yml's ubuntu job will).

Not verified - none of the App's wiring has a test, and only a phone can tell (docs/ios.md's checks 70-76):
- That TextFields and a Toggle take typing and taps inside a List in edit mode.
- That the red minus (a borderless button in an edit-mode row) takes one tap and doesn't open the row.
- That a sheet opens from a Menu's action (the picker from every •••), and over Now Playing's full-screen cover.
- That the confirmation dialogs from the bar's Cancel and from Delete playlist show where they should.
- That the notice over Now Playing shows.
- That Navidrome's real `changed` moves on every write, so the picker's order and the 409 behave as they do against
  the fakes.
- That an add's notice, made after the sheet has closed, is seen.

## Phase 4, slice 2, after its review (2026-11-14)

The review of d95b9e1 found one HIGH, one LOW-MEDIUM and six LOW, and that none of the App's safety rules had a test.
All are fixed in one commit on `phase4-library`. The app stays 0.9 (9); src/__init__.py untouched; no server change.

### What was wrong, and the fix

- **HIGH - "one write at a time" didn't last past closing the picker.**
  - The bug: each opening made its own PlaylistPickerModel, whose gate (`writing`) began false. There are two sheets,
    MainTabs' and Now Playing's. The web has one PlaylistPicker whose `writing` lasts across openings and openers
    (App.tsx).
  - On a slow Navidrome:
    - Late night tapped ("Adding…"), the sheet closed, opened again (or Now Playing's), and Late night tapped again;
    - the second ask-add read the playlist before the first had written;
    - the server's add route reads, then writes, so both appended - the songs twice, the question never asked;
    - and the reopened picker didn't say "Adding…".
  - **Fix, in Core: `PlaylistWrites`**, held once by PlaylistsModel (`writes`, reset with the person). It is the
    picker's write out - an add (to which playlist, how) or New playlist… - and at most one.
    - `begin` answers nil while one is out, so nothing is sent.
    - Every opening's rows and New playlist… wait on `writes.busy`.
    - The row, or the question's button, says "Adding…" from `writes.adding(id)`, in any opening.
  - Its tickets also hold who each write was asked as. `end` says whether the answer counts: PlaylistsModel.write's
    `Superseded`, until now an App check of its own.
  - Edit's Done, Delete and the Playlists screen's New take ungated tickets, which never open or shut the picker's
    gate.
- **LOW-MEDIUM - a refused Done didn't scroll to its reason.** `proxy.scrollTo(Place.problem)` ran in the same turn
  that set the failure, before its row existed.
  - **Fix**: `PlaylistEditFlow.refusals` goes up by one for each refusal that leaves Edit open.
  - The page's `onChange(of: refusals)` scrolls in a task, once the row is drawn. A second refusal with the same words
    scrolls too.
- **LOW - a Delete answered 404 left Edit open on a playlist that had gone.**
  - **Fix**: `deleteRefused` reads it as gone: Edit closed, gone, `playlists.gone`.
  - The page leaves as a delete does, the notice saying it had gone (PLAYLIST_GONE).
- **LOW - the name and description bindings cut text already over the bound.** One keystroke in a 250-letter name
  (made in another app) cut it to 200, and Done saved the cut.
  - **Fix, in Core: `PlaylistEdit.typed(_:was:max:)`**, maxLength's rule:
    - text within the bound, or no longer than it was, is taken as it is;
    - text that grows past it keeps what was there and takes as much of what was put in as fits, found between the
      start and end the two share, so a paste in the middle keeps what follows the cursor;
    - nothing is taken when nothing fits.
  - The bindings now take the text as typed, and each field's `onChange` puts it back with `typed`. That is a change
    of its own, so the field shows what was kept; a setter refusing the text would change nothing, and the field would
    go on showing it.
  - NewPlaylistFields works the same way.
- **LOW - tapping the current tab again threw Edit's changes away.**
  - **Fix**: AppNavigation's `editingPlaylist`, set by the page as Edit opens and closes, and let go once no page of
    it is left.
  - A tab tapped again keeps every page up to the topmost page of that playlist (`PlaylistEdit.pagesKept`). From Go
    to album over an Edit, it comes back to the Edit.
  - Chosen over asking: Cancel's question stays the one place changes are thrown away.
- **LOW - New playlist's sheets shared one `making`.** A slow Create answering after its sheet was swiped away and
  another opened closed the new sheet and lost its name.
  - **Fix**: each opening is its own (`NewSheet`, a UUID, `sheet(item:)`).
  - `PlaylistEdit.made(sentFrom:up:shown:)` decides what follows:
    - the sheet that sent it still up: it closes, and the playlist opens once it has gone;
    - none up and the screen on top: the playlist opens;
    - otherwise: the notice says it was made, and nothing closes.
- **LOW - NewPlaylistFields' announcement left out `admin`**, while its ErrorNote drew the admin's words. **Fix**:
  `admin: server.access.seesDetail`.
- **LOW, docs - the hero.** This file and spec 3.3 said the hero is put away in Edit. It stays, Play and Shuffle
  dimmed, as on the web. Corrected.

### Core: the App's safety rules as state machines (the review's gap)

PlaylistFlows.swift (new):
- `PlaylistWrites` (above).
- `PlaylistPickerFlow`, one opening of the picker: New playlist…'s name, the question, the failure, `finished` and
  `shown`. PlaylistPickerModel now wraps it.
  - `answered`: while shown, the question is drawn; once closed, the notice says "Nothing added - some are in X
    already". Added: said, and the sheet closed while shown.
  - `failed`: while shown, why under the head and to VoiceOver; once closed, the notice. Whoever runs deadwax gets the
    admin's words, and a 404 lets the playlist go.
  - `made`, `sending` and `back`.
- `PlaylistEditFlow`, the page's Edit. PlaylistPageModel now holds one and forwards to it.
  - `fresh`: set by this page's own answer (`answered`, dropped while Edit is open), cleared by `madeOld` (an add's
    change); `notFound` for a 404.
  - `canBegin`, `begin`, and `leave` (asking again after a refusal).
  - `move` and `remove`, which do nothing while a write is out.
  - `done`: `.unchanged(askAgain:)`, `.notSent`, or `.send(body)` with `tried`.
  - `saved`, `notSent`, and `refused` (each refusal's transition).
    - A save is this page's own answer, so `fresh`, even after an add's change landed while Done was out.
    - If that add was written after the edit, the answer drawn lacks it, and Edit may begin from it. The next Done's
      `base` is then old, and the server refuses it with a 409: Edit closes and the playlist is asked again. Nothing
      is lost; the cost is one Done refused.
  - `beginDelete`, `deleted`, `deleteRefused` and `deleteNotSent`.
- `PlaylistEdit.made` and `pagesKept`.

PlaylistChanges.swift: `typed`, with `clamped` now its cut of what was put in.

### Tests

Core 1239 (from 1224). **PlaylistFlowTests**, 15. Every mutating call is made before its `#expect`, never inside one.
- The gate:
  - one write out;
  - Done never opening it;
  - an answer ended twice;
  - a reset;
  - another person.
- The review's case: a second opening sees the add out, its rows waiting, and the first's answer is said in the
  notice.
- The picker:
  - its answers, shown and closed;
  - its refusals, with and without admin;
  - a 404 let go;
  - a made playlist.
- Edit waiting for the page's own answer:
  - a kept answer;
  - an add's change;
  - an answer while open dropped;
  - gone, and a 404 with Edit open closing it;
  - a save after an add's change counting as the page's own.
- A refused Done:
  - Edit open, why, and `tried` the songs it sent;
  - the next Done sending them;
  - a second refusal keeping its own.
- 409 and 404 closing Edit.
- Leaving after a refusal asking again, including a refused Done undone by hand.
- Done sending nothing it shouldn't: a blank name, one already out, moves held.
- Delete: closed, out, deleted, 404 gone, refused.
- `made`, `pagesKept` and `typed`:
  - a keystroke past the bound;
  - pastes at the end, in the middle and at the start;
  - a selection replaced;
  - nothing fitting;
  - a two-unit character at the edge;
  - a name already over the bound - kept, shortened, never grown.

**Mutations: 55**, each a rule broken alone in PlaylistFlows.swift or `typed`, then `swift test --filter Playlist`:
- the gate, 8;
- the picker, 8;
- Edit, Done and Delete, 30;
- `made` and `pagesKept`, 4;
- `typed`, 5.

All 55 are caught. The first pass caught 53. No test reached either of the two misses:
- "saved not fresh" - a save with `fresh` already false;
- "the page's 404 leaves Edit open" - `notFound()` with Edit open.

Two cases in `editWaitsForThisPagesOwnAnswer` now catch both.

### Verified, and not

Verified (2026-11-14, this Mac, Xcode's toolchain):
- `swift test`: Core 1239, DeadwaxAudio 158 and DeadwaxTurntable 11, all pass.
- The mutations.
- The unsigned Release device build, with no warnings but appintents' "Metadata extraction skipped".
- check_project.py, with the .xcodeproj unchanged.
- `pytest tests/test_ios_*.py tests/test_source_bytes.py`.
- The 11 ios sims on Node 22, ui/node_modules deleted afterwards.

Not run: Core on Linux.

Not verified - only the phone can tell (docs/ios.md's checks 71, 73 and 75 now ask):
- The scroll to why, from `onChange(of: refusals)` and a task, on a real List.
- That a field's `onChange` correction shows the kept text, SwiftUI's usual pattern for a bound.
- The tab tapped again during Edit.
- New playlist's sheet swiped away and opened again.
- A second opening of the picker saying "Adding…" over Now Playing.

## Phase 4, slice 3: Download a playlist (2026-11-14)

The third of Phase 4's five slices (notes/ios-specs/phase4-library.md 2.5 and 6.3; 6.8 points here), on
`phase4-library` from `ios` 2fb2ecb (slice 2, its review and main's 2.1.16-2.1.17 merged). **The app stays 0.9 (9)**;
src/__init__.py untouched; **no server change**: slice 1's two read routes (the list, and one playlist with its
songs) answer everything keeping a playlist in step needs. ROUTE_COUNT stays 32.

This section is slice 3 as first built. Its review changed the planner's playlist unit, the Edit's takes, songs
Navidrome is hiding, the keeper's order (now Core's PlaylistKeeping) and smart playlists: "Phase 4, slice 3, after
its review", after the turntable's section below.

### Core (DeadwaxCore)

- **PlaylistDownloads.swift** (new):
  - **`DownloadOrigin.playlist(id)`** is `.other("playlist:<id>")`, the raw Phase 2 reserved - one representation,
    so every switch over DownloadOrigin and every row a store already holds read as before. `playlistID`,
    `playlists(_:)` (sorted), `keptInStep` (only the library's or playlists'), `onlyPlaylists`.
  - **`DownloadRemoval`**: what each Remove Download takes - a song's `[.song, .album(its album)]`, an album's those
    and `.library`, a playlist's its own origin alone - and `stays(origins, removing:)` (none kept reads as `[.song]`,
    as the store's rules read it).
  - **`KeptPlaylist`**: a row of the store's `playlist` table - the last answer (nil when it can't be read) and its
    body as deadwax sent it, `readAt`, `missingSince`, `left` (song id to the first read without it), `askedAt`;
    `songIDs` (each once), `leftAgreed`, `secondReadAt`.
  - **`PlaylistDownloads`**, the rules: `started`; `listed` (listed: no longer missing, read when its `changed`
    moved or its answer couldn't be read; not listed: marked, let go once a list 10 minutes on agrees; an empty list
    believes nothing and reads every one; one downloaded after the list was asked is left alone); `missing` (a read's
    404 is a list without it); `read` (a song carried and not in the answer marked by its first read; `here` - this
    phone's Edit - marks it agreed already; a song back unmarked; an emptied answer not taken in while a mark is
    unagreed); `actions` (ask the songs not carrying the origin, each once, in order; take the agreed-left ones the
    answer doesn't list; nothing from an unreadable answer); `orphans`; `dueReads`, `nextLook`, `due` (the library
    follower's cadence, and on the minute when a second read or a missing mark is due); and for the screens
    `shelf`, `keeping`, `state`, `choices`, `progress`.
  - **`PlaylistDownloadWords`** (spec 6.3's words, and `heroLine`, `downloadingRow`, `count`, `removeAllToo`).
- **DownloadPlan**: `Asked.unit` is `playlist:<id>` (the first by id) for a song a downloaded playlist wants and no
  album download does - **planned whole**, the storage limit and the 2 GB reserve checked for all of it at once
  (question 14). Hand units, as before: never given way, never evicted.
- **DownloadRules**: `DownloadChoice.forSong(_:staying:)` and `forSongs(_:gone:staying:)`, Phase 3's `keptByLibrary`
  forms now calling them.
- **DownloadDatabase version 6**: the `playlist` table (id, json, read_at, missing_since, left_songs, asked_at);
  `playlists()` (in the order downloaded; a row whose answer can't be read, or is another playlist's, kept with no
  answer - never left out, or its songs' origin would read as an orphan's), `putPlaylist`, `deletePlaylist`; Remove
  All takes the table with the songs.
- **Playlists.swift**: `PlaylistWithSongs` is Codable (it encodes back to what reads the same). **DeadwaxClient**:
  `playlistAnswered(id:)` - the answer and its body as sent; `playlist(id:)` through it.

### The app

- **PlaylistKeeper** (App/Downloads, new): DownloadModel's `playlists`, beside the library's follower, opened and
  closed with the store. It holds the downloaded playlists in memory; everything it asks for and lets go goes through
  DownloadModel's own `want` (origin `.playlist(id)`) and `removeOrigins` (DownloadRemoval.playlist). At open: the
  rows read back, orphans' origins taken, each playlist's asks and takes made, a look. A look (PlaylistDownloads.due)
  lists the playlists, saves the marks, lets go what two lists agree on, then reads those the list says to and those
  due a second read - one at a time, each once a run, only while deadwax can be asked; a 404 is `missing`. A timer
  every minute while the app lives. **Download**: the row written, then the songs asked for, then a read. **Remove**:
  the row deleted, then the origin taken. **A write here** (PlaylistsModel's new `wrote`): an add or a write's 404
  reads it; Edit's Done takes in the answer it was given with `here`; a delete (or a Delete answered 404) lets it go
  at once. **A page's answer** (PlaylistPageModel's new `heard`) is taken in as a read - so opening the playlist twice
  ten minutes apart agrees on a song gone - and its 404 reads it. A read answered after a newer answer was taken in
  is dropped (`takenIn`), or a read sent before an Edit here would bring back what the Edit took out.
- **DownloadModel**: `playlists`, wired in init; `staysAfterRemove(_:album:)` (DownloadRemoval.stays) for the
  choices - a song's Remove Download offered only when it would take something, an album's only when a song of it
  would go - and `keepingPlaylist(_:album:)`, the header's name; Remove Download's sets are DownloadRemoval's; the
  playlist's `download`, `remove`, `tryAgain`, `carrying`, `playlistState`, `keptPlaylist`, `playlistPlaysOffline`,
  `playlistProgress`, `playlistHere`, `playlistAnswered`, `playlistGone`, `playlistWritten`; the keeper told of
  open, close, the front, deadwax back and Remove All.
- **DownloadControl.swift**: **PlaylistDownloadControl** (the arrow; downloaded, the mark opening a menu titled with
  the playlist's line - "This playlist is downloaded - it plays with no connection." and its size once all are here)
  and **PlaylistDownloadMenuSection** (Download, or Download Again and Remove Download), also the bar •••'s second
  section (QueueMenuRequest's new `playlist`). DownloadMenuSection's header says "Downloaded with Late night" for
  songs a downloaded playlist keeps with nothing to remove; the album control's title too.
- **PlaylistView**: the control beside the •••; the hero's download line (AlbumHero's DownloadLine, made internal;
  `heroLine`); the page drawn first from the stored answer (`stored` ?? the page kept in memory), so a downloaded
  playlist opens with no connection after a launch.
- **Downloaded playlists** (question 15): AppRoute `.downloadedPlaylists`, DownloadedPlaylistsScreen (PlaylistsScreen.
  swift) - the downloaded ones by name, a pull looking now. Its row is on the Downloaded screen, pushed or as the
  root, with a count ("3 playlists" to VoiceOver; PlaceRow's new `counted`) - not a place of its own above the
  albums. The root's On this phone shows with only a playlist downloaded; Downloaded's "nothing downloaded" note
  doesn't show under a downloaded playlist's row. The Playlists screen, offline with no list in hand, lists the
  downloaded ones; offline, a downloaded playlist's row is never dimmed while a song of it is here.
- **You > Downloads**: Downloading's album rows leave out songs only the library and playlists want (`keptInStep`),
  each downloaded playlist with songs to come having its own row ("3 of 12 songs to go", or its wait; the bar while
  fetching); Downloaded's album rows leave out songs only playlists want (`onlyPlaylists`), each downloaded playlist
  with songs here listed first ("12 songs · 412 MB"); a playlist row opens its page and swipes to Remove. Didn't
  download's row has no swipe when its Remove would take nothing. Remove All's question adds `removeAllToo`. The
  pull looks at the playlists too. Storage's counts still count every song.

### Decided here (the spec was silent, or this departs from it)

- **The place** (question 15): Downloaded > Downloaded playlists, as the coordinator relayed James's redesign of the
  Library (slice 3b, the Library's switch, moves Downloaded into the Library's •••): not On this phone > Playlists.
- **Planned whole** (question 14), as an album is.
- **Remove Download elsewhere**: a song's or an album's is never offered when it would take nothing (it would look
  like it did nothing); "Downloaded with …" says why instead. A song your library keeps keeps Phase 3's rule.
- **The page's answers count as reads**, and the Edit's own answer is taken in rather than asked for again.
- **A Delete answered 404 here** lets the download go at once, as a Delete answered (`gone(_:deletedHere:)`); a 404
  anywhere else waits for two answers 10 minutes apart. The page says it has gone meanwhile; its songs stay.
- **Crash order**: Download writes the row before asking; Remove deletes the row before taking - an origin left
  without its row is an orphan, taken as the store opens. A just-downloaded playlist isn't judged by a list asked
  before it (`askedAt`).
- **The mosaic isn't kept** (question 15): it is a cover of its own on Navidrome with no file to keep; offline, the
  cover cache's or the empty cover.
- **An empty playlist** can be downloaded: it is "downloaded", and gains songs as they come.

### Tests

- **PlaylistDownloadTests** (new, 24): the origin's raw form and reading it back (an empty id none); kept in step and
  only playlists; the library's `gives` never a playlist's; what each Remove takes and what stays; the staying
  choices; the planner's unit and a playlist planned whole under the limit and the reserve; listed (changed moved,
  unreadable, missing twice 10 minutes apart and at the bound, downloaded after the list, an empty list); a 404; a
  song gained asked once in order; a song lost agreed at 10 minutes and not a millisecond before, back in it
  unmarked, two marks' second read; an Edit here at once; an emptied answer held, agreed, emptied here (an empty or
  unreadable kept one replaced at once); only a read
  takes, a song the kept answer lists never; orphans; due, next look; keeping and the shelf by folded name; the
  control's state, items and hero line; Downloading's progress and words; the words' banned list; the body kept as
  sent.
- **PlaylistDatabaseTests** (new, 5): written and read back in order; an unreadable row kept; Remove All; a
  playlist's origin taken alone; **a real version-5 file** (made with `upTo: 5`, every table holding rows - song,
  origin with a raw `playlist:p1`, album and its cover, loudness, lyrics, play, start, queue, library with its left
  songs, meta) brought to 6 with every row kept, and the orphan it holds found.
- LibraryDatabaseTests' version check is `DownloadDatabase.version`; LibraryDownloadsTests and DownloadRulesTests
  use `.playlist(_:)`.
- **Mutations**: 74, over PlaylistDownloads, DownloadRemoval, the planner's unit, the staying choices and the store's
  version 6 - all caught. The first run missed 6: two were equivalent (`listed` and `read` asked the same thing twice,
  so the code was made plainer), and four were closed by tests - no origins kept reading as a song's, the second read
  due from the latest mark, a song the kept answer still lists never taken, and an unreadable row (whose test crashed
  on an index rather than failing, so it `#require`s the count first). A rerun missed one more - an emptied answer held
  whatever the kept one was - closed by a kept answer that was empty, or couldn't be read, being replaced at once.

### Verified, and not

Verified: `swift test` - Core 1268 (1239 + 29), Audio 158, Turntable 11; the unsigned Release device build (Xcode,
`generic/platform=iOS`), so the App's wiring compiles; `check_project.py` ok; the iOS pytest files and
test_source_bytes, 170 passed and 1 skipped; the 11 ios sims on Node 22.

Not verified - none of the App's wiring has a test, and only a phone can tell (docs/ios.md's checks 77-83):
- That a downloaded playlist plays offline after a force quit, from the stored answer, each song with its own cover.
- That Navidrome's real `changed` moves on a change in another app, so a look reads the playlist (the page's own ask
  takes it in either way).
- That a menu with a header and no items (a song's download section with only "Downloaded with …") shows its header.
- That the control sits beside the ••• as the album's does, and its menu's title reads as the album's.
- That a playlist's songs from many albums download in the background and locked, as an album's do; how long a
  playlist of a few hundred songs takes to be asked for and planned.
- The swipes on You > Downloads' playlist rows, and Remove All's longer question.

## The turntable's head stays on the arm (2026-11-14)

James, on 0.9: "in the turntable, when you tap on the play head, it looks like it dislocates." Its own commit on
`phase4-library`, after slice 3 (4c89833) and before slice 3's review fixes. The app stays 0.9 (9); src/__init__.py
untouched; no server change.

**Cause.** The phone ported the web's `is-lifted` (Turntable.tsx:492): while the arm was held, TurntableLayers
moved the head `-TurntableGeometry.armLift` (5 units) along the arm's y axis. The arm's container is turned, so that
is sideways off the bar, and a quick tap popped the head off the arm and back.

**Fix** (turntable spec 2.5, "The lift changed"):
- The head stays on the bar always: its layer is now its own size with its middle on the bar, and nothing moves it.
- The lift is the head coming toward the viewer: grown `TurntableGeometry.headLift.scale` (1.08) about its middle,
  with a soft shadow round it - `TurntablePalette.ttHeadShadow` (`--dw-shadow`'s black at 0.5), a blur of
  `headLift.shadow` (3 units across the stage) and no offset, so it doesn't turn with the arm.
- Both are eased each way over `headLift.seconds` on `headLiftEase`: the app's one motion token, `--dw-duration`
  (0.14 s) on `--dw-ease` (cubic-bezier(0.16, 1, 0.3, 1)), as the web's lift. The coordinator's first ask was 0.12 s
  ease-in-out, changed to the token so the two apps match. The easing runs from the presentation layer's values, so a
  tap that sets the head down mid-lift turns back rather than flickering. This is the only eased thing in the
  drawing, by explicit animations; `noActions` still keeps every implicit one off, and now covers the shadow's keys.
- Reduce Motion: `TurntableLook.still` (DeckController's `reduced`) makes the two states a step.
- `ttHeadShadow` isn't in TurntablePalette.tokens: tokens.json has no `--dw-shadow`, and adding it to
  export-deck-vectors.cjs's list changes `made_with` and so writes every fixture again. (Since main's 2.1.19 merge it
  is: the web gave it a token of its own, `--dw-tt-head-shadow`, and the deck fixtures were made again then.)

**The web** makes the same change on main, in branch web-tonearm, shipping as 2.1.19: the head on the bar, 1.08
about its middle, a shadow of blur 3 at rgba(0, 0, 0, 0.5) with no offset, on `--dw-duration` and `--dw-ease`. There
`ARM_PARTS.lift = { scale: 1.08, shadow: 3 }` takes the place of `lift: 5`.

Until main merges, `armLift` (5) stays in TurntableGeometry, held to turntable.json's `ARM_PARTS.lift` by
TurntableGeometryTests. **iosdeck.sim exports it**: it runs export-deck-vectors.cjs --check, which reads `ARM_PARTS`
out of ui/src/lib/turntable.ts. So it wasn't regenerated here. The deck vectors are made again at that merge, and
`armLift` can then give way to the web's numbers. (Done at main's 2.1.19 merge: `headLift` is held to
`ARM_PARTS.lift` and `armLift` is gone - see "Going back in Up Next, ported - and main's 2.1.18-2.1.21 merged".)

**Tests** (TurntableRenderTests):
- `theHeadIsFiveUnitsUpWhenLifted` is now `theHeadStaysOnTheBarAndComesTowardTheViewerWhenLifted`, rendered over a
  white plinth with everything but the arm hidden:
  - the head's middle doesn't move (within 0.35 pt);
  - its area grows by `scale` squared (within 0.06);
  - a pixel 2 units off its long side is clear set down and shadowed lifted.
- `theLiftIsEasedButAStepUnderReduceMotion`:
  - the lift's two animations are there each way unless `still`;
  - the duration is `seconds`, on `headLiftEase`'s control points, pinned at 0.14 s and (0.16, 1, 0.3, 1);
  - the model ends grown with its shadow (zero offset, the blur scaled), then back;
  - a frame that changes nothing of the lift leaves the easing alone.
- **Mutations:** 14, all caught:
  - the web's 5 units up again;
  - grown about its end;
  - not grown;
  - no shadow, and the shadow left on;
  - an offset shadow, and no blur;
  - eased under Reduce Motion, never eased, and eased every frame;
  - the wrong duration;
  - the shadow not eased;
  - the old ease-in-out, and the curve's points swapped.

**Verified:**
- `swift test`: Core 1268, Audio 158, Turntable 12 (11 + 1). The shadow is checked in pixels, so `render(in:)` does
  draw it.
- The unsigned Release device build.
- `check_project.py`.
- test_source_bytes.
- The 11 ios sims on Node 22, iosdeck's exporter check included. They ran before the move to the motion token, which
  touches nothing they read.

**Not verified (only the phone can tell; docs/ios.md check 10):**
- That it reads as the head lifting toward you, rather than only growing.
- That the shadow shows at all over the dark vinyl.
- That a quick tap, and taps in a row, look smooth.
- That Reduce Motion's step is right.

## Phase 4, slice 3, after its review (2026-11-14)

The review of 4c89833 found two HIGH, one MEDIUM, five LOW and five test gaps. All are fixed in one commit on
`phase4-library`, after the turntable's head (bfc7bb8). The app stays 0.9 (9); src/__init__.py untouched.

The server needs one field: `smart` in each playlist summary (src/playlists.py `summary()`), from Navidrome. That is
James's, on main as its own 2.1.x. The phone reads it ahead of the server (below), so nothing here waits for it.

### What was wrong, and the fix

- **HIGH 1 - one started song let a whole playlist past the limit and the reserve.**
  - The bug: the planner's `started` is per unit, and a started unit skips the room and reserve checks. A playlist
    was one unit (`playlist:<id>`), so a song of it already fetching made the whole playlist "started". Three ways
    that happened:
    - a song downloaded by hand (`[.song, .playlist]`) or your library's (`[.library, .playlist]`), still fetching
      as the playlist was downloaded;
    - a song mid-fetch shared with another downloaded playlist, which went in the playlist sorting first by id;
    - a song added to a playlist that was still downloading.
  - **Fix** (`DownloadPlan.Asked.unit`): a playlist's song that has started (a task out, bytes in, resume data) is
    a unit of its own, `song:<id>`. It carries on. The playlist's unit holds only its songs not yet started, and the
    limit and the 2 GB reserve are checked for them as one.
- **HIGH 2 - smart playlists** (James: "No Download for them").
  - Navidrome's smart playlists (made from rules, an `.nsp`) are worked out again each time they are read. A
    download of one would chase a list that moves on every look.
  - Ordinary playlists, and those kept in step with an .m3u, download as built.
  - **A smart playlist offers no Download.**
    - The control in the bar isn't drawn, and the bar's ••• has no download section.
    - It plays only online. Its page says why, under the count: "Smart playlists are worked out again each time, so
      this one plays only while deadwax can be reached." (`PlaylistDownloadWords.smartOnline`).
  - **One downloaded before deadwax said it was smart stays as it was.**
    - It keeps the songs last taken in, and its marks are dropped. It is never read again, and nothing is asked for
      or taken by it.
    - That holds whether a read's answer or a list says it is smart (`PlaylistDownloads.frozen`).
    - It keeps Download Again and Remove Download, and its line says "Smart playlists are worked out again each
      time, so this download stays as it was when you made it." (`smartKept`).
    - Remove Download works as for any playlist: the row is deleted, then its origin is taken from every song
      carrying it, and a song kept any other way stays. It is reachable from the control's menu, the bar's •••, the
      You > Downloads swipe, and Remove All.
    - It is still let go once two lists ten minutes apart agree it has gone from Navidrome.
  - **`Playlist.smart`** is read loosely, false when it is absent, so today's server reads as no playlist smart.
    tests/test_ios_contract.py exempts it (`PLAYLIST_AHEAD`) only while summary() leaves it out. Once main sends it,
    the same equality holds it like any other field. (Main sends it since 2.1.21; the exemption went at that merge.)
  - **Until main ships it, the phone can't tell any playlist is smart.** summary() keeps only `editable` (mine and
    not `readonly`), and Navidrome's `readonly` is true for a smart playlist, an .m3u-synced one and anyone else's
    alike. So nothing is treated as smart before then.
  - **Navidrome's field** (read at 46c4327, server/subsonic/helpers.go buildOSPlaylist): `validUntil` is set only
    when `p.IsSmartPlaylist()` (Rules and their Expression non-nil) and `p.EvaluatedAt != nil`. Its value is
    EvaluatedAt + the refresh delay.
    - `readonly` is true for every smart playlist, but not only for them.
    - A smart playlist never yet worked out has no `validUntil` in getPlaylists. getPlaylist works it out as it
      answers (notes/playlists.md "Hidden songs"), so its answer should carry one. That is read from the source, not
      seen on a real Navidrome.
    - Its `changed` moves on every evaluation, which is why a smart one is never read again.
- **MEDIUM - an Edit took every song its answer lacked.** `here` marked agreed every song carried that Done's answer
  didn't list, so a Done that changed only the name took a song Navidrome was hiding (a file being moved).
  - **Fix**: Done passes the songs it took out (`PlaylistEditBody.removed`: in `base`, and nowhere in the songs now)
    to `read(…, edited:)`, and only those are taken at once (`PlaylistsModel.Wrote.edited(_, removed:)`).
  - **And the hidden hold**: while an answer's `hidden` is at least the songs carried that it lacks (the Edit's own
    aside), any of them may be a hidden one. So none is marked, and an earlier mark is dropped, so a hiding read is
    never the second read that agrees. An emptied answer is held then too.
  - Once a read lacks more songs than Navidrome is hiding, they are all marked, since it can't say which. `hidden` is
    0 for anything but an editable playlist (notes/playlists.md), so this touches only yours.
- **LOW 1 - a failed write acted anyway.** `letGo` did `try? deletePlaylist`, then took; the put paths did
  `try? putPlaylist`, then asked or took.
  - **Fix**: every change goes through `PlaylistKeeping.run` (below): its write first, and on a throw nothing
    else - not memory, not the songs.
- **LOW 2 - Remove All could leave the playlists in memory.** If the database emptied but making a folder again threw,
  `removedAll` was never reached.
  - **Fix**: `DownloadStore.removeEverything(emptied:)` tells DownloadModel the moment `database.removeAll()`
    succeeds, and the keeper is cleared then.
- **LOW 3 - a list that failed waited 15 minutes.** `lastBegan` was set before `await list`.
  - **Fix**: the follower's rule. It is set as the list goes out, and put back when the list fails or the store
    changed meanwhile (`list` answers Bool), so the next minute's timer looks again.
- **LOW 4 - a read asked again while its run was out waited for the next tick.** A run tries each id once.
  - **Fix**: the run's `defer` starts another when reads it had already tried are left, while deadwax can be asked.
- **LOW 5 - polish.**
  - The Downloaded screen's "N playlists" row and Remove All's count read `kept.count`, which counts rows whose answer
    can't be read. Both now count the shelf (`PlaylistDownloads.shelf`), which is what Downloaded playlists lists.
  - A song carrying a playlist's origin that its kept answer doesn't list (marked, hidden, or still coming) was in no
    You > Downloads row: album rows left it out, and the playlist's row counts only its answer's songs. Now
    `PlaylistDownloads.inDownloadingAlbumRow` and `inDownloadedAlbumRow` draw it under its album unless your
    library's row or a downloaded playlist's row draws it (`drawnWithPlaylists`, over a `listing` made once a draw).

### Core: the keeper's order (the review's gap)

**PlaylistKeeping.swift** (new) is PlaylistKeeper's (App) every moment without its I/O: the kept playlists and each
answer's serial (in place of `takenIn`).
- Each moment gives a **Change**: its one write (`.put` or `.delete`, or none), its effects in order (`.take`, then
  `.ask`), and whether it takes an answer in.
- The moments: `opened` (orphans by id first, then each playlist's), `download` (nil when kept already, or smart),
  `remove`, `took` (`edited:`), `answered` (nil when the serial moved since the read went out), `gone` (marked, or let
  go), and `listed` (the entries whose marks moved, those let go, and those to read).
- `apply` puts in place or last, deletes, and moves a serial. `clear` empties it.
- `run` makes a change: the write; on a throw, false and nothing else. Then `apply`, then the effects, a take that
  fails (the store couldn't be written) stopping the asks after it.
  - `apply` is a closure, not a mutating call, so nothing of the keeper is held while the takes and asks run.

PlaylistKeeper keeps a `PlaylistKeeping` and performs every change through `run`, with the store's put and delete
as the write. Its reads are a set (`here` is gone). An Edit's Done still reads the playlist again after its answer is
taken in, as before. The smart guards on the screens are DownloadModel's `playlistIsSmart` (`PlaylistDownloads.isSmart`:
the answer in hand, or the one kept, says so), read by PlaylistDownloadControl, PlaylistDownloadMenuSection (an empty
list of choices draws no section) and the page's hero.

### Tests

- **PlaylistDownloadTests**: 24 to 29.
  - `aStartedSongNeverLetsItsPlaylistPastTheLimitOrTheReserve`: a `[.song, .playlist]` and a `[.library, .playlist]`
    song out, against the limit and the reserve. A song added to a playlist still downloading.
  - `aSongTwoPlaylistsShareGoesOnAloneAndEachPlaylistIsJudgedOnItsOwn`.
  - `anEditTakesOnlyWhatItTookOutAndASongNavidromeIsHidingStays`: a rename with a song hidden; an Edit's removal with
    another hidden; two hiding reads ten minutes apart and an old mark dropped; hidden at the count and below it;
    `removed` with a song listed twice.
  - `aMarkFromTheFutureIsTheReadsAndAListAtTheMomentOfADownloadSpeaksForIt`: the `min(…, at)` clamp, and `listed`'s
    `askedAt > at` at the same moment.
  - `aSongIsDrawnWithItsPlaylistOnlyWhileItsAnswerListsIt`: the listing and both rows' rules.
  - The unit test's started cases. `here:` became `edited:`.
- **PlaylistKeepingTests** (new, 12):
  - a download's row before its asks;
  - a failed write touching nothing;
  - a remove's delete before its take;
  - a failed take stopping the asks;
  - an older answer dropped, and an older 404;
  - a 404 marked, then let go ten minutes on;
  - a list writing only what moved, and letting go what two lists agree on;
  - an opening's orphans first;
  - apply's place and serial;
  - a smart playlist never downloaded (and `isSmart`, and the field read when absent, sent, and kept);
  - a downloaded one found smart, kept as it was with Remove still offered;
  - a list saying smart, not read again, but let go once gone.
- **tests/test_ios_contract.py**: `PLAYLIST_AHEAD`, `assert_decodes(…, ahead)`, and the Swift reading an ahead field
  from its absence.
- **Mutations**: 53 over the review's changes, all caught:
  - the planner's started rule, both ways;
  - the Edit's songs: every one taken, or none at once, and `removed` as the whole base;
  - the hidden hold: dropped, counting the Edit's songs, only past the count, with nothing lacking, keeping old marks,
    and an emptied answer taken while hiding;
  - the clamp, and `askedAt >=`;
  - smart playlists: read, `frozen`'s marks, missing, count and body, the list's branch, frozen again, missing kept,
    actions, choices, both lines, `downloadable`, `isSmart`, and the field read when absent or never;
  - the rows: the listing, `drawnWithPlaylists`, and each rule of both rows;
  - PlaylistKeeping: a failed write going on, applied before the write, a failed take going on, asks before takes,
    serials (none moved, an older answer and an older 404 taken, a took moving none), a smart or a kept one
    downloaded, a remove deleting no row, the orphans' order and place, a list writing everything or letting nothing
    go, a 404 let go at once, a put appended, a clear keeping serials.
  - The first run missed two, closed by tests: a smart one found by a read or a list was left missing (it is found),
    and one kept smart was frozen again on every list (a later list now writes nothing).
- Slice 3's own 74 were run again, the 11 whose code the review changed aimed at it as it is now: all 74 caught.

### Verified, and not

Verified:
- `swift test`: Core 1285 (1268 + 17), Audio 158, Turntable 12.
- The unsigned Release device build.
- `check_project.py`.
- The iOS pytest files and test_source_bytes: 170 passed, 1 skipped.
- The 11 ios sims on Node 22.

Not verified - the keeper's wiring has no test beyond its Core order, and only a phone and a real Navidrome can tell
(docs/ios.md's checks 77-84):
- That a smart playlist's page shows its line and no control once main sends `smart`.
- That Navidrome's real getPlaylists and getPlaylist carry `validUntil` for a smart playlist, and getPlaylists for
  one never yet worked out.
- That a hand-downloaded song mid-fetch, then its playlist's Download, leaves the rest of the playlist waiting for
  room.
- That a rename's Done with a song's file being moved keeps that song.

## Now Playing's bar, squared off (2026-11-14)

James: "maybe instead of the thin bar, a squared off thicker bar for the play progress in the play page?" Shown
today's 4 pt capsule beside squared-off 8, 12 and 16 pt bars, he chose **12 pt, on both apps**. ScrubberView's bar
is now two `Rectangle`s (the track white at 0.2, the fill white at 0.85, as before) 12 pt tall, 16 while a finger is
on it (the same eased grow, 0.15 s), no knob - as the web's phone bar since main's 2.1.20 (notes/app.md "Now
Playing's bar, squared off and thicker"). The target is still the whole 44 pt row; nothing about how it seeks
changed. Verified: CI's device build (ios.yml). Not seen: on the phone - with the next install.

## Phase 4, slice 3b: the Library's switch, pull to shuffle, the Play button (2026-11-14)

James's, of 2026-11-14 (notes/ios-specs/phase4-library.md 2.8, 3.1, 3.5 and 6.3b; 6.9 points here): "I'm not a huge fan
of the weird section of buttons at the top of the library page. I like just opening library to your albums" - a switch
at the top, Albums | Playlists | Artists | Songs, "and I would also like to be able to swipe left and right between
them, and maybe a way to rearrange the order"; a pull that shuffles ("if you drag down far enough there can be a cool
little shuffle graphic that changes as you pull down, and then once you go far enough, it changes, and starts shuffling
when you release"), the Library's pull never refreshing; and "the color of the play button on the album page doesn't
show the play icon." On `phase4-library` from `ios` 5aeb89a. **The app stays 0.9 (9)**; src/__init__.py untouched;
**no server change**: the Library's Shuffle reads the web's two routes, `GET /deadwax/navidrome/shuffle` and
`/shuffle/{token}` (2.0.0-player.57). ROUTE_COUNT 38. Artists and Songs join the switch in slices 4 and 5.

### Core (DeadwaxCore)

- **LibrarySwitch.swift** (new): `LibraryPage` (albums, playlists; its switch word); `LibraryPages` - the order kept
  per phone under `deadwax-library-pages` ("playlists,albums"), `read` with care (a name unknown or a page twice left
  out, every page not named added after in the standard order, so never empty), `saved`, `moved` (a List's own
  offsets and destination, clamped), `first`; `ShuffleCan` (ready, downloads, gettingReady, failed(words),
  nothingHere, none - `of(online:ready:empty:failed:songsHere:)`, `starts`); `LibraryMenuItem` (its words, `enabled`)
  and `LibraryMenu.sections` - Shuffle; then Downloaded or, offline where the Albums page is Downloaded, the way back to
  the scope's albums; All music (a library of your own, online); then Refresh and Edit order; `LibrarySwitchWords`.
- **PullShuffle.swift** (new): the pull's machine, as TurntablePress, Scrub and LyricsHold are - idle, pulling(progress),
  armed at `line` (110 pt) once per arming (the haptic's event), back under `line - slack` (100) pulling, a lift while
  armed and ready `.shuffle` (released until the page is at rest), a bounce no finger began idle, never armed unready
  (the full ring, `pulling(1)`), a pull that is no number rest. `PullShuffleWords.line(_:can:)`.
- **Shuffle.swift** (new), ShuffleSongs.tsx and useShuffleFeed.ts ported: `ShuffleStart` and `ShufflePage` (the two
  answers, decoded leniently), `ShuffleWords` (the web's three, and `unready(status:detail:)` - a 413's own words);
  **`ShuffleAhead`**, the first page asked ahead (`shown` - asked when none was, the last failed, or more than
  `freshSeconds`, 600, ago; `answered`, `failed`, `take` - the tap's tracks at the songs level, `paged`, the next ask
  naming the order played until one gets through; `reset`; another scope starts afresh; an older ask's answer
  dropped); **`ShuffleFeed`** (`below` 50, `retrySeconds` 30, `track`, `startingElsewhere`, `songsAhead`), **`FeedAsk`**,
  **`FeedStep`**, and **`ShuffleFeedRun`** - one ask at a time, keyed on the order and how far it has got, the newest
  only: `look`, `page`, `gone` (a 404: a fresh claimed order, as the rest of this round), `fresh` (Repeat as it is
  now), `failed` and `retried`, `reset`; **`ShuffleHere`** (offline: every song on the phone, each once).
- **PrimaryButton.swift** (new): `PrimaryButton` - theme.css's --dw-primary-* (top #a24ef2, bottom #8a2ee0, edge
  #7c3aed, the highlight, the white label, pressed 0.92, the 4 pt corners, the pill's 48 pt) and `fill(at:)`; and
  `Contrast` - WCAG 2's relative luminance and ratio, `mix`, `brightness`.
- **Routes**: `shuffle` (scope, playing, claim) and `shufflePage` (offset) - 38. **DeadwaxClient**:
  `shuffleStart(scope:playing:claim:)`, `shufflePage(token:offset:)` (a 404 thrown, for the feed to read).
- **Playlists.swift**: `PlaylistRules.found` - Find on the Playlists page (every word, Find's folding).

### The app

- **LibraryView**, rewritten at its top: the bar's principal slot holds the switch (a segmented Picker over the order,
  animated unless Reduce Motion), its trailing slot the page's own buttons (Albums: the order and Grid or list;
  Playlists: New playlist's +) and the Library's ••• (LibraryMenu; "More for the Library"); Find under it, its binding
  the page shown's own; under them the pages side by side - a horizontal ScrollView of `containerRelativeFrame` pages,
  `.scrollTargetBehavior(.paging)`, `.scrollPosition(id: $page)`, so the swipe and the switch set the one `page` (the
  ForEach identified by the page itself, `id: \.self`: scrollPosition matches the views' ids against its binding's
  type, and LibraryPage's `id` is a String - found by reading, not by the build). The
  page is nil until the first draw (then the order's first) and set to the first for a new person, Find cleared. As
  the Library comes into view (first, the tab, the app back in front on it, back online, a new person) - `shown()`:
  LibraryModel's libraryShown and ShuffleModel's `shown(scope)`; and again when the scope comes in. Edit order: a sheet,
  a List in edit mode, each move saved through LibraryPages at once. The •••'s Refresh: your albums and the playlists
  asked now and the Shuffle's `shown` (a failure tried again); offline, a probe. The Shuffle (the •••'s, the pull's
  release): `.ready` - ShuffleModel's `take` then `player.play(shuffled:)`; `.downloads` - DownloadModel's `songsHere`
  through the playlist path, shuffled. The Navidrome gate is drawn in the switch's place, unchanged.
- **AlbumsScreen** draws two ways: as the Albums page (`Page`: the switch's Find, whether it is the page shown, the
  pull) - no title, toolbar or refreshable of its own, the albums from the top, the pull's graphic over the top anchor;
  or pushed (All albums, Downloaded), as before, with pull to refresh. Downloaded's top: its heading when it is the
  page (offline), the **FirstAskCard** (question 17: moved here from over the albums; online, with albums to download),
  Downloaded playlists' row, and offline the note. AppRoute's `.playlists` is gone (the switch's page).
- **PlaylistsPage** (PlaylistsScreen.swift) replaces PlaylistsScreen: a ScrollView of rows (PlaylistRow's `inList:
  false` draws its own chevron and divider), Find by `PlaylistRules.found` (From files opened while it finds, "No
  playlists match “…”."), asked when it becomes the page shown and when the app comes back to it, the graphic and the
  pull, New playlist's sheet driven by the bar's +.
- **PullShuffleView.swift** (new): `ShufflePull` (the page's PullShuffle, the ticks, the finger from the scroll's
  phase), `PullShuffling`, `.pullsToShuffle(_:)` - iOS 18's `onScrollGeometryChange` (the pull is
  `-(contentOffset.y + contentInsets.top)`) and `onScrollPhaseChange` (`.interacting` is the finger; its end is the
  lift, and the shuffle starts in that call), `.sensoryFeedback(.impact(weight: .light))` on each arming, reset when the
  page stops being the one shown; nothing on iOS 17. `PullShuffleGraphic`: the 40 pt ring and mark, the armed disc in
  the primary's purple, the release's turn, its line; Reduce Motion keeps the mark still; hidden from VoiceOver.
- **ShuffleModel** (new, an environment object made with the server): ShuffleAhead's asks made as the person signed in
  in unstructured tasks; reset for a new person (DeadwaxApp's whenPersonChanges).
- **PlayerModel**: `play(shuffled:)` (the songs shelved for Info and the stream cache, `playTracks(..., paged:)`, no
  album remembered - each track names its own); the feed - `feedLook()` after every queue change and Repeat change,
  `feedSend` (a page, or a fresh claimed order), `carry` (extend: shelved, `controller.extendQueue`, the notice said;
  ask; a retry 30 s on, `retried()` then a look; nothing), `feedStop()` in `stop()`.
- **DownloadModel**: `songsHere` (ShuffleHere over the songs downloaded, a playlist's kept answer standing in for a
  song with no album row) and `songsHereCount`.
- **ButtonFaces.swift** (new): `PrimaryFace` and `SecondaryPill` (ButtonStyles over one face: semibold, 16 by 6, 36 pt
  or the 48 pt pill, the 4 pt corners, the highlight inside the top edge, the 1 pt edge; pressed, the primary
  multiplied by 0.92 - CSS's brightness - and the secondary's pressed face; disabled faded to Palette.off) and the
  Palette's primary colours. Every `.borderedProminent` takes PrimaryFace - the album's and the playlist's Play
  (large), Add to my library (MineBlock, twice), the EQ's Use for, the picker's Create, Sign in, Try again on the
  unreachable screen, the Navidrome gate's Try again and Set up Navidrome, the first ask's Turn On; the `.bordered`
  beside one takes SecondaryPill - the hero's Shuffle (large), Change address, the picker's Cancel, Not Now - and the
  empty Playlists' New playlist.

### Decided here (the spec was silent, or this departs from it)

Questions 17-26 in the spec, each built to its recommendation: the first ask at the top of Downloaded (17); no row
swipes on the switch's pages (18); the same switch offline, its Albums page Downloaded (19); the •••'s Shuffle for
VoiceOver and Switch Control (20); every page pulls the same shuffle (21); offline, the downloads shuffled (22); Edit
order a sheet, a page added later joining at the end (23); the feed's behaviour held by hand, its numbers and words
by the contract test (24); the web's button shape, the `.bordered` beside it the secondary pill (25); slices 4-5 to
move the order and layout into the ••• when four pages crowd the bar (26, nothing built). And:

- **From files is open while Find finds**, so a match folded away doesn't read as none.
- **The library's shuffle remembers no album** for Info, as resume's queue doesn't: each track names its album and Info
  asks for the rest.
- **Refresh asks the Shuffle again** (`shown`), so a failed first page is tried again from the •••.
- **The Playlists page asks when it becomes the page shown**, not as it is built beside Albums.
- **A failed page waits out its 30 s** (`retried`): the first build cleared its key at once, so the next song asked
  again - the web's effect isn't run again by a song changing, so it waits; the feed now waits too.
- **Made plainer by the mutation runs** (each an equivalent mutant): the order the last tap played let go on any newest
  answer (the web's "if it is still the one named" is always true behind the serial); the feed's key without Repeat,
  and no token of its own (another shuffle, or none, already lets an ask go through `look` or `letGo`); the pull's
  `towards` without its cap and floor (it is only asked between the top and the line).

### Tests

- **LibrarySwitchTests** (8): the order read from every kind of value and written back; every move of the List's (a
  destination or offsets out of range clamped); the first page; ShuffleCan from every state; the •••'s sections and
  words, online and off, with and without a library of your own; Find on playlists.
- **PullShuffleTests** (10): the line and slack; pulling to the line and arming at it, not a point before; one tick per
  arming; disarmed under the slack and not at it; a lift while armed shuffling, then released until at rest; a lift
  before the line nothing; a bounce no finger made never drawn; never armed unready (the full ring), ready again
  mid-pull arming; a pull that is no number at rest; the graphic's words.
- **ShuffleTests** (20): the numbers and words; a song as the queue takes it; `startingElsewhere` and `songsAhead`
  over shuffle.sim.cjs's own cases; the feed through a whole order (199 and 50 ahead nothing, 49 the next page from
  `fetched`, one ask whatever changes meanwhile, a failure asked again only when its retry is due, a late answer
  dropped, the whole order in nothing under Off and One and a fresh claimed round under All never starting with the
  song ending); a short last page asking the next round at once; a page at the shuffle's level; a 404 starting over
  said once; an empty fresh order; another shuffle or none letting an ask go; a retry due after another ask letting
  nothing go; Repeat turned off with a round on its way; ShuffleAhead (asked as shown, the 600 s bound, the tap and the
  next ask naming it until one gets through - then no more, a failure asked again, another scope or person, total 0);
  the answers decoded leniently; the two calls; ShuffleHere.
- **PrimaryButtonTests** (5): WCAG's own pairs; the colours the web's, the mix rounded per channel; the label on the
  gradient; pressed; against black, and the old fill.
- **tests/test_ios_contract.py**: ROUTE_COUNT 38; the shuffle answers within what the app decodes (the token required,
  the songs `shuffledTrack` reads within SHUFFLE_FIELDS); `PagedScope` the route's Literal; `claim` a bool sent as
  "true"; the offset's bounds; the 404 and the 413 where the routes raise them; and the numbers and words read from
  ShuffleSongs.tsx and useShuffleFeed.ts - SHUFFLE_FRESH_MS (and the route's SHUFFLE_LIST_TTL_S), FEED_BELOW,
  FEED_RETRY_MS, SHUFFLE_GETTING_READY, SHUFFLE_UNREADY, SHUFFLE_STARTED_OVER, and SHUFFLE_TOO_BIG.
- **tests/test_ios_palette.py** (new): PrimaryButton's numbers theme.css's and player.css's (the gradient, edge,
  highlight, label, pressed, radius, the pill's height); `.pl-pill.is-primary` drawn from them; no
  `.borderedProminent` left in ios/App; ButtonFaces reading every PrimaryButton field.
- **Mutations**: the final run, 67 over LibrarySwitch, PullShuffle, ShuffleAhead, the feed, ShuffleHere,
  PlaylistRules.found and Contrast: 65 caught by a failing test, and 2 (a move's offsets and destination left
  unclamped) trapping in the test that gives them out of range. The first run, 61, missed 10: those 2 traps (the
  harness counted only recorded issues), 4 equivalent (made plainer - "Decided here"), and 4 closed by tests - a bounce
  drawn while it bounces, the order played still named after its ask got through, a page queued without the
  shuffle's level, the gradient's mix truncated. The code made plainer was mutated again: the feed's key without how
  far the order had got was missed, and closed by a short last page that leaves the music near its end asking the
  next round at once. The 30 s wait (`retrying`, `retried`) came with four of its own, all caught.

### The contrast, measured

`Contrast` (WCAG 2), white on the primary: #8a2ee0 (the foot) 5.92:1; the gradient's middle 5.05:1; a fifth of the way
down - the top of a label's line on the 48 pt pill - 4.57:1, and every tenth below it over 4.5:1; #a24ef2 at the very
top edge, where no glyph is drawn, 4.28:1. Pressed (brightness 0.92): 4.92:1 at the top, 6.72:1 at the foot. The edge
against white 5.70:1. So the label is AA (4.5:1) wherever it is drawn, and the play glyph (a graphic, 3:1) everywhere.
The old fill, the tint #C084FC, under white: 2.64:1 - what James couldn't see. Against the black page the button
itself is 4.91:1 at its top and 3.55:1 at its foot.

### Verified, and not

Verified:
- `swift test`: Core 1328 (1285 + 43), Audio 158, Turntable 12.
- The unsigned Release and Debug device builds (Xcode, `generic/platform=iOS`): no warnings.
- `check_project.py` ok.
- The iOS pytest files and test_source_bytes: 179 passed, 1 skipped (test_ios_palette.py new).
- The 11 ios sims and shuffle.sim.cjs.

Not verified - only the phone can tell (the spec's section 9; docs/ios.md's checks 92-101):
- That a horizontal paging ScrollView of two pages, each its own vertical ScrollView, swipes and scrolls as hoped: a
  vertical scroll never pages, and whether a sideways drag that begins on the letter index pages (question 18).
- That iOS 18's scroll geometry reads the pull as 0 at rest under Find's drawer and the inline bar, inside the pager;
  that the scroll's phase leaves `.interacting` the moment the finger lifts, so the music starts then; the tick once
  per arming; the graphic in the room the pull opens at every text size.
- How the bar collapses and Find's drawer behaves with nested scroll views; that `.scrollPosition(id:)` keeps the
  page shown across an Edit order and a rotation.
- The feed's asks answered on a locked phone mid-shuffle; Repeat All's next round past the end of a real library.
- The primary's purple on James's screen beside the web's; the pressed darkening (colorMultiply standing in for CSS's
  brightness - since its review, the fill and edge darkened instead, the label left white).
- iOS 17: no pull (by design), only the •••'s Shuffle - not run on one.

## Phase 4, slice 3b, after its review (2026-11-14)

The review of 50f60b6 found one MEDIUM, seven LOW and a test gap, all fixed here in one commit on
`phase4-library`. It also found finding 1, left alone as asked: a paged shuffle's resume snapshot outgrows
`snapshotMax` after about 750 songs (Resume.swift). Resume.swift was being changed by the History roll-back's port at
the time, so that fix is the port's. The app stays 0.9 (9), and src/__init__.py is untouched.

### What was wrong, and the fix

- **MEDIUM 2 - the page flipped as soon as a sliver of the next one showed.**
  - The bug: `.scrollPosition(id: $page)` with no anchor reports the view at the leading edge. So a backward swipe
    made the previous page "the page" the moment any of it showed. Mid-swipe, that flipped the switch, the bar's
    buttons, Find's binding and the pulls' reset, and it ran Playlists' `.task` again. A half swipe let go flickered
    twice.
  - The fix keeps `page` as the settled page; it does more than add the anchor:
    - The pager binds a value of its own, `scrolled`, with `anchor: .center`.
    - `page` is what the switch, the bar, Find and the pulls read. It follows `scrolled` only while the pager is at
      rest. iOS 18's `onScrollPhaseChange` keeps `paging` true for any phase but `.idle`, and at `.idle` `page` takes
      `scrolled`.
    - While at rest, a move no finger made (a layout's) is followed at once.
    - The switch's tap, the first draw and a new person set both values (`show`).
    - iOS 17 has no scroll phase. There `page` follows `scrolled` at once, at the swipe's halfway: the anchor fix
      alone.
- **LOW 3 - the pager's `.scrollIndicators(.hidden)` reached the pages' own lists** through the environment. It is now
  `.scrollIndicators(.hidden, axes: .horizontal)`.
- **LOW 4 - pressed, the primary's label went grey with its fill.**
  - The bug: `colorMultiply(0.92)` is the web's `brightness(0.92)`, and it covers the whole button, label included.
    White became #ebebeb, at 4.13:1 on the pressed fill's top, 4.39:1 a fifth down (Core's mix; the review measured
    4.42) and 5.64:1 at the foot.
  - The fix darkens only the fill and the edge, using Core's `PrimaryButton.pressedTop`, `pressedBottom` and
    `pressedEdge` (each `Contrast.brightness(…, 0.92)`) and `pressedFill(at:)`. In the App these become
    `Palette.primaryFillPressed` and `primaryEdgePressed`. `colorMultiply` is gone.
  - White on the pressed fill is 4.92:1 at the top, 5.23:1 a fifth down and 6.72:1 at the foot.
  - The 1 pt highlight is left as it is. The web's filter takes it from white at 0.22 to #ebebeb at 0.22, and nobody
    reads it.
  - This is a small, deliberate departure from the web, said in PrimaryButton.swift. `pressed`'s comment no longer
    says "over the whole button", and ButtonFaces' header says what is darkened.
- **LOW 5 - the pager read the downloads online.** The body read `downloads.songsHereCount` even online, so every
  change to the records redrew the pager. The songs here are now read only while deadwax can't be reached.
- **LOW 6 - offline, the pull could arm with nothing to play.**
  - The bug: `songsHereCount` counted finished records, but `songsHere` drops a song with no kept album or playlist
    answer to play it by.
  - The readiness is now `songsHere.count`, the very list the shuffle plays.
  - `songsHere` is kept until something it is made of changes. Its version goes up in the `didSet` of `records` and
    of `albums`, and its key includes the kept playlists' ids, reads and song counts. The getter still reads all three
    each time, so a view that reads it is redrawn by them.
  - `songsHereCount` is gone.
  - If the list empties between the draw and the release (a removal), the Shuffle says "Nothing on this phone to
    shuffle" (question 22's `PullShuffleWords.nothingHere`) and plays nothing.
- **LOW 7 - a pull a call or Siri cut short still shuffled.**
  - The bug: any phase change away from `.interacting` counted as the finger lifting.
  - The fix: Core's `PullShuffle.interrupted()` returns to idle, unless a release was already made, which stays
    released. The App's `ShufflePull.interrupted()` also forgets the finger, so the phase change that follows shuffles
    nothing. It is called from:
    - `UIApplication.willResignActiveNotification`, which is said before the scene's phase;
    - the scene's phase leaving `.active`;
    - the audio session's interruption beginning (a call, Siri, an alarm), received on the main queue;
    - the lift itself, when `UIApplication.shared.applicationState` isn't `.active`.
  - What can't be told apart: SwiftUI's scroll phase doesn't say whether a touch was cancelled or ended. A touch the
    system takes while the app stays active and no audio interruption comes - a call's banner over the app, say -
    reads as a lift.
  - The order is the phone's to tell. If iOS ends the scroll's interaction before it says the app is resigning, while
    its state still reads `.active`, the pull shuffles. That is accepted, with a phone check (check 95's new
    sentence).
- **LOW 8 - the palette test caught only one spelling.**
  - It now uses a regex, `\bborderedProminent\b|\bBorderedProminentButtonStyle\b`, over every line of ios/App's
    Swift, comments aside (ButtonFaces' header names it).
  - ButtonFaces' fields are matched as whole names, because `PrimaryButton.pressed` matched inside `pressedTop`
    otherwise. `pressedTop`, `pressedBottom` and `pressedEdge` are in the list.
  - There is no `colorMultiply` or `.brightness(` in ButtonFaces.
- **LOW 9 - SecondaryPill's comment said it lightened as pressed, and check 99 said both darken.**
  - What theme.css says: `--dw-secondary-bg` is white at 0.09 to 0.05, top to bottom, and `--dw-secondary-bg-active`
    is 0.05 to 0.09 - the same gradient reversed. It is lit from below, as if pressed in, and neither lighter nor
    darker. `.pl-pill:active` uses it.
  - The code already drew that (`Palette.secondaryFillPressed`). So the review's suggestion, darkening the pill too,
    isn't what the web does.
  - The comment, check 99 (docs/ios.md and the spec) and 2.8 now say it: Play darkens with its label staying white,
    and Shuffle's shading turns over.
  - `test_the_secondary_pill_turns_its_gradient_over_when_pressed` holds theme.css's two gradients as each other's
    reverse, player.css's `.pl-pill:active` as drawn from them, DeadwaxApp.swift's `secondaryFillPressed` as bottom
    then top, and ButtonFaces as using it pressed.
- **Test gap 10 - the feed was never run as PlayerModel runs it.** The reviewer's simulation (ZFeedSimTests) drove
  ShuffleFeedRun over the real QueueController. It is now in the suite as ShuffleFeedLoopTests, and it drives Core's
  new ShuffleFeedLoop, which is PlayerModel's own steps (below).

### Core: the feed's loop (the review's gap)

**ShuffleFeedLoop.swift** (new) is what PlayerModel did with ShuffleFeedRun by hand:
- `look(controller)` is called from the queue's and Repeat's changes.
- What each answer does: `page`, `gone`, `fresh` and `failed` carry it. For an extension, the songs go to `adding`
  first, then they are added as an edit like Play Last (`extendQueue`, whose edit catches the queue up with the
  engine first), then the notice is said. PlayerModel's own `controller.catchUp()` before `extendQueue` was the same
  call twice, and is not carried over: a mutant taking it out of the loop was equivalent.
- `retryDue` is the timer firing: the failed ask is let go, and the queue is looked at again while there is one.
- `stopped` lets every ask and the retry go.
- A new ask calls off a waiting retry.

The App gives the loop four closures:
- `send` makes the ask of deadwax;
- `adding` is PlayerModel's `shelve`;
- `say` says the notice;
- `retry`, called with true, starts the 30 s timer afresh, and with false calls it off.

PlayerModel's `feedRun`, `feedLook`, `carry` and `feedStop` are gone. Its stop calls `feed.stopped()`, and
`queueChanged` and `repeatChanged` call `feed.look`.

The reset when the person changes reaches the loop through `reset()`, which stops the player. It is tested as a stop.

What stays phone-only:
- `feedSend`'s two network calls, `shufflePage` and `shuffleStart` with the claim. A 404 is told apart there by
  `APIFailure.status`.
- The retry's `Task.sleep`.
- `shelve`, which keeps the songs for Info and the stream cache.
- The pager's scroll-phase wiring and the pull's scene, notification and audio wiring.

**PullShuffle.interrupted()** and **PrimaryButton's pressed colours** are described above.

### Tests

- **ShuffleFeedLoopTests** (new, 6). A `World` has deadwax's orders by token, the asks out, the retry's timer, the
  songs heard (one per queue entry from the order, Play Next's not counted), the notices and the songs handed over. It
  runs over the real QueueController and QueueControllerTests' FakeEngine. Each step:
  - maybe Play Next, or Repeat moved to One and back to All;
  - maybe the oldest ask answered, or failed at a rate;
  - maybe the retry firing;
  - maybe the next song scheduled (D4's held edits);
  - then the song moving on by a join or by Next. Three joins in ten are said a moment late, so answers, retries and
    Play Next land while the engine is a song ahead of the controller (what `extendQueue`'s catch-up is for).

  The tests:
  - `everySongOnceUnderRepeatOff`: 25 seeds, 1037 songs, failing at 0.2 and held at 0.3. Every song is heard once,
    none twice and none lost.
  - `underRepeatAllEachRoundIsWholeWhateverMoves`: 60 seeds, 437 songs, three rounds, with Play Next and Repeat
    moving. Each round is the whole order, and no round begins with the song that ended the last.
  - `anOrderDeadwaxLostStartsOverAndSaysSoOnce`: the 404, then a fresh order asked; said once; 200 songs handed over;
    the queue 400 and on the new token.
  - `aRetryDueAsksAgainFromTheSamePlace`: after a failure the song moving on asks nothing, and the retry asks the
    same page (offset 200, the same order).
  - `stoppingLetsEveryAskAndTheRetryGo`: a stop while the retry waits calls it off; the timer firing anyway with no
    queue asks nothing; another shuffle's ask out, then a stop: its answer dropped.
  - `aNewAskCallsOffTheRetry`.

  They run in under a second.
- **PullShuffleTests**: 10 to 11. `aTouchTheSystemTookNeverShuffles`:
  - armed or pulling, then interrupted: idle, nothing drawn, and the lift shuffles nothing;
  - released, then interrupted: still released;
  - afterwards, a pull from rest arms afresh.
- **PrimaryButtonTests** (5). `pressedItReadsBetter` became `pressedTheFillDarkensAndTheLabelStaysWhite`, which
  measures what is drawn:
  - the three pressed colours are the web's brightness, and `pressedFill` meets its ends;
  - white on it measures 4.918 and 6.720, and every tenth is 4.5:1 or more;
  - the web's darkened label (235, 235, 235) measures 4.125 at the top, under 4.5 a fifth down and 5.637 at the foot,
    so going back to multiplying the whole button fails here.
- **tests/test_ios_palette.py**: 5 to 6 (LOW 8 and LOW 9 above).
- **Mutations**: 16 over the review's Core changes. The first run caught 14 and missed 2:
  - `controller.catchUp()` taken out of the loop's extension: equivalent, since `extendQueue`'s edit catches up first.
    The call is gone (above), and three joins in ten said late now put that catch-up under the property tests.
  - a stop that kept the retry: the test stopped only after the retry had fired. It now stops while the retry waits,
    and `aRetryDueAsksAgainFromTheSamePlace` took over what that test had also caught (a retry due that never looks).

  The second run, 15, caught all 15:
  - the songs never handed over, the notice never said;
  - a new ask keeping the retry; a stop keeping the retry or the asks;
  - a retry due never looking, or keeping the failed ask; a failure never starting the timer;
  - a 404's fresh ask carried as nothing;
  - the feed's key without where in the order (caught by ShuffleTests' short last page);
  - an interruption doing nothing, or undoing a release;
  - the pressed top, the pressed edge, or the pressed fill left undarkened.

  The App's wiring (the pager's phase, the pull's notifications, the cache's version) has no mutation run: it has no
  test here.

### Verified, and not

Verified:
- `swift test`: Core 1335 (1328 + 7), Audio 158, Turntable 12. ShuffleFeedLoopTests run in about a second.
- The unsigned Release and Debug device builds (Xcode, `generic/platform=iOS`): no warnings.
- `check_project.py` ok.
- The iOS pytest files and test_source_bytes: 180 passed, 1 skipped.
- The 11 ios sims and shuffle.sim.cjs.

Not verified - only the phone can tell (the spec's section 9; docs/ios.md's checks 92, 95 and 99):
- That iOS 18's scroll phase reaches `.idle` as a swipe settles, so the switch, the bar and Find follow then and a
  half swipe changes nothing; and that the switch's animated tap ends on the page tapped.
- The order in which iOS says the system took a touch: a pull cut short by Notification Center, Siri or a call
  should shuffle nothing. A banner call over an active app, with no audio interruption, can't be told from a lift.
- The pressed primary on James's screen beside the web's: the fill a little darker, the label still white.
- iOS 17 (the page following at the swipe's halfway): not run on one.

## Going back in Up Next, ported - and main's 2.1.18-2.1.21 merged (2026-11-14)

Branch `rollback-port`, from ios (5aeb89a): the merge of main's 2.1.18 to 2.1.21 (a18acbc), then the port. The app
stays 0.9 (9); src/__init__.py is main's 2.1.21, untouched.

**Why one piece.** Main's 2.1.18 made a tap above the song playing ROLL BACK (James: "so it just moves back up the
list"; notes/play-history.md): a History row moves the playing point up to it, and an older row of the play history
brings it and every older row below it back into the queue ahead of History's songs - lib/upNext.ts, playHistory.ts
and resume.ts (snapshot v2). 2.1.19 put the turntable's head on the bar (ARM_PARTS.lift a scale and a shadow), 2.1.20
squared off Now Playing's bar, 2.1.21 sends each playlist's `smart`. The sims hold the phone to the web's own
TypeScript - iostraces to upNext.ts and resume.ts, ioshistory to playHistory.ts, iosdeck to ARM_PARTS - so the merge
alone left them red: the merge and the port are one piece, as notes/play-history.md's iPhone list said.

### What the merge brought, besides going back

- **The turntable's lift** (2.1.19): `TurntableGeometry.headLift` (scale 1.08, shadow 3, 0.14 s) is held to
  turntable.json's `ARM_PARTS.lift` by TurntableGeometryTests, and `armLift` (5) is gone - see "The turntable's head
  stays on the arm". `TurntablePalette.ttHeadShadow` is now one of the tokens, held to `--dw-tt-head-shadow`:
  export-deck-vectors.cjs's TOKENS gained 'tt-head-shadow', and Fixtures/deck was made again on Node 20.12.2 (3063 KB
  of its 3072 KB budget). export-deck-recording.cjs was run again too: its `--check` said the recording is the same,
  so only web-script.made.json moved (turntable.ts's hash) - tests/test_ios_deck_recording.py had failed on it.
- **Smart playlists** (2.1.21): summary() sends `smart`, so tests/test_ios_contract.py's `PLAYLIST_AHEAD` exemption
  is gone, `assert_decodes`' `ahead` with it - the Playlist's keys are summary()'s exactly. The phone still reads it
  loosely, false when absent: a deadwax before 2.1.21 says no playlist is smart.
- **Now Playing's bar** (2.1.20) was the phone's already ("Now Playing's bar, squared off").

### The port (DeadwaxCore), to the web's rules exactly

- **UpNextTypes**: `Mark.starts` ([Int64]?, a row brought back's start moments) and `UpNextState.reached` (the
  key of the furthest unit played, while after the song playing).
- **UpNext.swift**: `layoutAt`/`layout` (the list runs on to the reach and through what was drawn after it then),
  `reachedPlace`, `furthest`; passPlaying's fallback (no list song before: the round of the first after);
  withRepeat's round the max with the reach's; withShuffle keeps the later rounds up to the reach's - each shuffled on
  its own, never starting with the song that ends the last, or with Shuffle off sorted by place (Swift's sort isn't
  stable: ties by offset, as Array.prototype.sort), the reach then on whichever moved-down unit is last; withoutKey
  hands the reach to the unit before it; movedKey keeps each place's time round (recast) and the reach on the last
  unit at or before it; `jumpedTo(queue, key, mode)` - History's row is `rolledBack` (`Jump.back`; copies after it
  go outside Repeat One, `copyAfter`); `broughtBack(queue, rows, mode, floor:)` with `Brought` {track, starts,
  entry}; `heldStarts`; shownKeys to the end of the reach's unit; wentBack names the furthest.
- **PlayHistory**: `QueueShows.held` (each `at:id` the queue holds, as UTF-16 units), `heldByQueue`, pastRows (a run
  of one song's starts all on its row; `entry` only when begun in this queue), `rowsFrom`.
- **Resume**: `snapshotVersion` - 2 with `reached` or `starts`, else 1 when a list song is at or before the index,
  else 2; toSave writes `v` by it, then `reached` (after the song playing, in the window) and `starts` last; a
  snapshot of v 1 or 2 is read (`readable`); fromSnapshot reads `starts` (refusing a copy's, a key twice or not in the
  window, an empty list, a negative or fractional moment) and `reached` (kept only after the index, not a copy).
- **QueueController**: jumpTo hands jumpedTo the device's Repeat; `rollBack(rows, floor:)` replaces playAgain, and
  playsAlone is gone; `jump(made:)`'s back path - the same entries: `move(to:)`, the engine's skip, as Previous moves;
  other entries (copies let go, older rows brought back): the queue played afresh from the row. Never refused, never
  held; a held edit still runs after it, as after every move.

### The app

- **PlayerModel.rollBack(rows, floor:)** replaces playAgain: each row's song at the setting's level for a song
  (`levelFor(normalization, .songs)`), as a song's Play Next queues it, then QueueController.rollBack. Nothing with no
  controller - the old fallback that played an older row as a queue of its own went with playsAlone, as the web's
  broughtBack is null with nothing playing.
- **UpNextScreen**: History's row - `player.jump(to:)`, then `rolledTo`; an older row - `PlayHistory.rowsFrom` of the
  pastRows drawn, with the floor History's first row's key, else the song playing's (the web's replayPast). `rolledTo`
  holds the scroll (the card is where the row was, under the finger), then - once drawn - moves VoiceOver to what
  plays next (Playing Next's head, else the list's first, else Done) and says "Playing {title}".

### Where the phone can't follow the web exactly

- **No gesture unlock.** The web's back path calls `unlockSpare()` - iOS Safari unlocks each audio element from a
  gesture, and Gapless has a second one. The phone's engine has no such rule, so nothing stands for it.
- **A skip, or played afresh - decided by the entries, not the stream.** The web seeks within its one stream when it
  still holds the song (moveInStream), else loads a new one from the row. The phone's engine holds every entry it was
  given, so the same entries are always a skip (`move(to:)`), and other entries are always `engine.play` from the
  row. The web can make a new stream with the songs unchanged (a stream begun after the row); the phone never needs to.
- **Moments as integers.** The web takes a start's moment or `reached` as any JavaScript integer (`Number.isInteger`,
  1e300 included); the phone's reader takes whole numbers under 9.2e18 only, so a snapshot holding a larger one is
  refused where the web reads it. Moments are milliseconds since 1970 (1.8e12 now), so no real snapshot differs.
- **QueueShows.held** is a Set of UTF-16 unit arrays where the web's is a Set of strings: the same comparison (the
  web's `===`), another type - Swift's `==` on String would take "é" for "e\u{301}".

### Fixtures and exporters

- **export-traces.cjs**: stateOf records `reached`, `starts` and - where an entry's level isn't its song's in the
  table (a row brought back at the setting's) - `levels`; Run.jumpedTo(key, repeat) records `back`; new ops
  broughtBack (rows as [id, level, starts, entry]), heldStarts, shownKeys; `set` takes reached and starts. The 2.1.18
  and review scenarios of upnext.sim, 69 scenarios in all; the property loop is upnext.sim's again (the seed's first
  draw let go, one run in twenty a 55-74 song album, op 14 older rows), canonical() with reached, starts and levels;
  the resume cases (v 1 or 2, starts and reached read or refused), and the round trip at 1,000 runs (older rows
  brought back every other run), counting rolled, brought, reachedKept, startsKept and v2.
  - **The 200-song scenario** (past Up Next's 100) is recorded as one `set` of the state the sim's song-by-song walk
    reaches, held to that walk by the exporter (it stops if the two differ): its 210 ops made scenarios.json 896 KB.
  - Sizes: scenarios.json 528 KB (263 before), traces.json 2.17 MB (1.99), resume/cases.json 1.40 MB (1.25),
    roundtrip.json 1.30 MB (1.07).
- **export-history.cjs**: the History tap's jump with Repeat; op 6 brings back rowsFrom with the floor; each line
  carries the starts the queue holds and each older row's starts and entry; the words' `playing` once (one rolledTo
  says it).
- Every ios*.sim `--check` green.

### Tests

- **UpNextTraceTests**: the replay knows jumpedTo's mode and `back`, broughtBack, heldStarts and shownKeys, and
  compares each state's reached, starts and levels; `set` reads them.
- **UpNextPropertyTests**: upnext.sim's loop and checks again - a History tap the same queue at the row less its
  copies, drawn as it was, Previous's walk to it with no copies; older rows each its own entry, first, in order,
  moved or added, with their starts, the queue after them as it was; Up Next drawing every song up to the furthest
  played. Its tallies: walkedTo > 300, brought > 500, broughtMoved > 200, broughtNew > 500, longRuns > 50.
- **ResumeRoundTripTests**: 1,000 runs; `reached` in what reads back; Up Next to come and the starts held the same
  after a reload; the counts. **ResumeCaseTests**: the counts.
- **HistoryVectorTests**: the moves and lines as export-history's, and drawnOnce as history.sim's 2.1.18 check (a
  start held by a row brought back is the queue's; one moved back down past the rows drawn is to come).
- **UpNextTests**: every jump names Repeat; `historysTapRollsBack`, `aRollBackUnderRepeat`,
  `pastUpNextsHundredTheRoundMovedBackDownIsHeld`, `aShuffleRolledBackKeepsItsOrder`, `olderRowsBroughtBack` and
  `theFloorDrawnKeepsTheQueueFromThere` - upnext.sim's 2.1.18 section check by check; wentBack's `reached` and
  Repeat keeping a round played in the 2.1.3 tests.
- **QueueControllerTests**: History's tap a skip, nothing replaced, Playing Next kept after the song that was
  playing; from a pause with a seek on its way, never refused; Repeat One's copies let go, played afresh - and kept
  with Repeat One still on, a skip;
  QueueControllerRollBackTests (an older row, a pause, the next song scheduled, the floor after the engine ran on,
  nothing playing) in place of the play-again suite.
- **Mutations**: 36 over the ported rules, each run alone (copyAfter both ways, shownKeys' reach, broughtBack's
  floor, order, starts, startedAt and reach, withRepeat's and withShuffle's later rounds - kept, the song before, each
  shuffled, the reach - withoutKey's and movedKey's reach and rounds, wentBack's and rolledBack's furthest,
  passPlaying's fallback, layout's reach, the History tap's back, heldStarts, snapshotVersion both ways, v2 refused,
  starts read and on a copy, reached written, heldByQueue, rowsFrom, pastRows' entry and starts, the back path's skip
  and play, rollBack's floor, jumpTo's Repeat), all caught. The first run missed one, closed by a test: jumpTo handing
  jumpedTo Repeat off always (`aRollBackUnderRepeatOneKeepsItsCopiesAndSkips`: with Repeat One still on, a History tap
  keeps the copies and skips).

### Verified, and not

- Verified: `swift test` (DeadwaxKit, every target), the unsigned Release device build (Xcode 27.2 here),
  ios/scripts/check_project.py, all 81 sims on Node 22 (iosdeck on Node 20.12.2 too), pytest's ios files and
  test_source_bytes.py, the mutations.
- Not verified: CI's Xcode 26.6 (an older Swift; the closures new here spell out their types). The app's halves -
  rolledTo's scroll and focus, the floor handed from the screen - are compiled, not tested: they're the phone's
  checks 85-91 in docs/ios.md, with the rest of going back on the phone, locked.

## Phase 4's branch takes ios at 893390b (2026-11-14)

`phase4-library` merged `ios` at 893390b, which brought three things:
- main's 2.1.18-2.1.21;
- the History roll-back's port ("Going back in Up Next, ported", above);
- 893390b's test-only split of UpNextPropertyTests' digest, so CI's Xcode 26.6 can type-check it.

The app stays 0.9 (9).

**Conflicts.** Only docs/ios.md and notes/ios.md conflicted, each because both sides added at the same place.
- The port's phone checks keep 85-91, so slice 3b's are now **92-101**. They are renumbered in docs/ios.md, the
  spec's section 8, and slice 3b's two sections here.
- Three files merged by themselves:
  - PlayerModel: the feed's loop beside `rollBack`;
  - Playlists.swift: the smart comment beside `PlaylistRules.found`;
  - tests/test_ios_contract.py: `PLAYLIST_AHEAD` gone, beside the shuffle routes and ROUTE_COUNT 38.

**Where the two meet.** Going back keeps a library shuffle's pages. History's tap moves the place only, and
`broughtBack` keeps the state (`var next = state`), so the feed carries on after it.
- ShuffleFeedLoopTests has a new test, `goingBackMidShuffleLosesAndDoublesNothing`. It runs 12 seeds of 650 songs,
  with up to 8 History rows a few songs back tapped while pages are out, failing and landing. The order reaches the
  queue whole, each song once, and the feed runs to its end.
- Rows brought back from deadwax's older history come in as `.added`, outside the order. They are untested with the
  feed.

Finding 1 of slice 3b's review (a paged shuffle's snapshot past `snapshotMax`) is still open: the port didn't change
the limit.

Verified on the merged tree:
- `swift test`: Core 1343, Audio 158, Turntable 12.
- The unsigned Release and Debug device builds: no warnings.
- `check_project.py` ok.
- `npm run build` and all 81 sims on Node 22.23.4, every ios sim's exporter `--check` among them: iostraces against
  upNext.ts and resume.ts, ioshistory against playHistory.ts, iosdeck against ARM_PARTS.
- The iOS pytest files and test_source_bytes: 180 passed, 1 skipped.

Not verified: CI's Xcode 26.6, which has the older Swift. The new tests spell out their closures' types. Nothing has
run on a phone: checks 85-101.

## Main's 2.1.22 and 2.1.23 ported, and the going-back port's review (2026-11-14)

Branch `paged-resume-ios`, from ios (893390b): the merge of main's 2.1.22 and 2.1.23 (49a83cb), then this. The app
stays 0.9 (9); src/__init__.py is main's 2.1.23, untouched.

**Why.** Two resume bugs the web and the phone share, both fixed on main first (notes/app.md "A library's shuffle saved
however long it plays (2.1.22)", notes/play-history.md "Gone back twice: the reach saved while it plays (2.1.23)"):
a library's shuffle some 750 songs in outgrew the snapshot's cap and came back a plain list whose feed asked no more;
and a second roll-back, saved by its position alone after a full save made while the reach's song played, left
deadwax's record without `reached`. The phone's own items from the review of the going-back port came with them.

### The port (DeadwaxCore), to the web's rules exactly

- **Resume.swift `savedList`** (2.1.22): a library's shuffle (`paged`) keeps the songs its window's marks name (a
  copy's names its song's place), in the list's order, each mark's place renumbered to them, and `left` empty; any
  other list whole. toSave writes `source`, `sourceLevels`, `extra` and `left` from it.
- **toSave's reach** (2.1.23): `reached` is written while it names the song playing's own unit (walked back over
  Repeat One's copies, inside the window) or a later one, and snapshotVersion follows it - v2. fromSnapshot is
  unchanged.
- **Where it differs**: the walk back stops at the window's end too (`unit < window.count`). The web's indexes the
  mark without that guard and would throw on an index past the songs; neither ever saves one, so no snapshot differs.

### The review's items

- **HIGH, the reach** - the port above, and the reviewer's probe as a Core test
  (`ResumeUnitTests.goneBackTwiceTheRecordKeepsHowFarItHadGot`): Repeat All, three songs, the second time round's 2
  playing; the first 1 tapped; played on to that 2; Play Next x; the first 1 tapped again - a `.song` change; the save
  between v2 with the reach; read at the song tapped it puts back 1 2 3 1 2 x 3 under Repeat off (it read 1 2 3 x), Up
  Next under Repeat All drawing 2 3 1 2 x 3, as a full save of it would; played past the reach, left out. The reader
  before 2.1.18 (the web's frozen one in resume.sim) puts a v2 back as the plain list; the phone has no frozen old
  reader, and its readers before the roll-back's port took v1 alone.
- **LOW, a 422 to a v2** (ResumeController `saveFull`): a deadwax before 2.1.18 refuses a v2 snapshot
  (src/play_queue.py snapshot_problem took v 1 alone), and the phone tried again every 30 s for ever, keeping nothing.
  Now a full save carrying v2 answered 422 is sent ONCE more, at once, with `snapshot: nil` - the songs, the one
  playing and the second, which every server keeps; picked up there it is the plain list. A second refusal is the
  failure it always was (failedAt, tried again 30 s on, in full with its v2 - one more pair). A v1's 422 is not sent
  again. The web has no such path and needs none: a page is served by the deadwax it saves to, so it never meets an
  older one. docs/ios.md says so in Up Next's going-back passage; James runs 2.1.21, so it is for others.
- **Test gap, the held edit through a roll-back**: `QueueControllerTests.aChangeHeldThroughItIsMadeAfterIt` (an older
  row's tap) and `aChangeHeldThroughAHistoryTapThatLetsCopiesGoIsMadeAfterIt` (History's row, Repeat One's copy let
  go): Play Next with the next song scheduled is held, the tap plays afresh, and 9 comes right after the song tapped.
  Replacing jump()'s back-path `runHeld()` with `heldEdit = nil` now fails both.
- **Test gap, what the app hands the roll-back**: `PlayHistory.brought(plays, queue:, key:, setting:)` (and
  `brought(rows:...)` over rows drawn) is the web's replayPast in Core - pastRows at Up Next's default limit, rowsFrom,
  each song at `levelFor(setting, .songs)` (Off: as it was, as queued() leaves it), the floor History's first row's
  key, else the song playing's. UpNextScreen's older row calls it with `player.queue` and `player.normalization`, and
  `PlayerModel.rollBack` takes its `[Brought]` and floor as they are. The web's replayPast is a component's inline
  handler, already held to its text by app-rules.sim (its regex at :2472) - so nothing changed on main for this.
  export-history.cjs reads it from UpNext.tsx (stopping if its body isn't the one composed), hashes it into the
  vectors (`replayPast`, which HistoryVectorTests pins), and makes its hand-over from the web's own parts: 48 `brought`
  cases over rows given whole (a song's own level among them, every setting, a key no row has, a queue with History,
  one without, a plain queue), and a field on every line of the 300-run property - the middle drawn row tapped, at a
  setting by turns.
- **Type-check time** (UpNextPropertyTests' older-row check): its one ternary of && chains and its `||` with an
  inferred `contains` closure are split into named parts, the closure's types spelt out; the length test still
  guards the indexes. Measured afterwards with `-warn-long-expression-type-checking=100` (this Mac's Swift, a
  build of DeadwaxKit and its tests on a scratch path of its own): nothing in a file this touches reaches 100 ms. The
  only expressions over it are the EQ tests' - EQRenderTests.swift:287, :311 (451 ms) and :361, EQBankTests.swift:129
  (418 ms), StreamCacheAndHeardEstimateTests.swift:74 - left as they are (not this work's; CI's older Swift is
  slower, so they are the first to look at if it gives up on one).

### Fixtures and exporters

- **export-traces.cjs**: referenceSnapshot compacts a library's shuffle and writes the reach by the unit rule; the
  round trip's expectation compacts too, refuses a library's shuffle that took out a song its window names, and
  counts `pagedNamed` (1,887 of 5,000); `toSavePaged`, 6 recipes of a library's shuffle thousands of songs in (2,200
  in, its order whole under Repeat All, songs taken out before the window and three played next, from its first song
  5,000 fetched, Repeat One's copies, 60 copies played so the window begins among them) - the snapshot's length,
  hash and head, the queue's list and `left`, and what reads back (its feed, Up Next's rows); the 2.1.23 probe as 4
  toSave cases (the save between, the tap saved in full, played past, a copy of the reach's song playing) and its
  record read at the song tapped under all four settings.
  - Sizes: resume/cases.json 1.43 MB (1.40), roundtrip.json 1.26 MB (1.30 - a library's shuffle's snapshots smaller).
- **export-history.cjs**: lib/loudness.ts compiled too (levelled); `replayPast`, `brought` and the lines' hand-over
  field. history/vectors.json 532 KB (519).

### Tests

- **ResumeRoundTripTests**: `wanted` compacts a library's shuffle; `pagedNamed` equal to the web's and over 300; and
  at every step `positionSaves` - History's first row tapped and Previous, each move changedSince calls `.song` read
  back from this step's snapshot as a full save of it would (the reach, Up Next's songs to come, what each Repeat keeps,
  All's round shuffled by one seeded draw each), over 3,000 of them and every one back before the reach.
- **ResumeCaseTests**: `librariesShufflesThousandsOfSongsIn` rebuilds the recipes (`pagedQueue`); the counts (33
  toSave, 327 fromSnapshot, 49 given a new id).
- **ResumeUnitTests**, **ResumeControllerTests** (`aV2SnapshotRefusedIsSentOnceMoreWithoutIt`),
  **QueueControllerTests**, **HistoryVectorTests** (`whatAnOlderRowsTapHandsTheRollBack`, the property's lines): above.
- **Mutations**, 12, each run alone over the filtered suites, all caught: the reach by 2.1.18's rule, by the song
  playing alone (not its unit), written whenever in the window, the version not following it; a library's shuffle's
  list kept whole, its `left` kept, its places in the order met, a copy's place not named (a crash: the place it names
  isn't kept); the 422 not sent again, sent again however often refused, a v1 sent again; jump()'s back path dropping
  the change held.

### Verified, and not

- Verified: `swift test` (DeadwaxKit, every target: 1,298 tests and 12), the unsigned Release device build (Xcode
  27.2 here), ios/scripts/check_project.py, all 81 sims on Node 22, pytest's ios files and test_source_bytes.py (170
  passed, 1 skipped), the mutations, the type-check times above; on main, resume.sim's own probe and property, all
  sims, the build and pytest 4224.
- Not verified: CI's Xcode 26.6; a server before 2.1.18 answering a real phone (the 422 path is the fake server's);
  the app's call of PlayHistory.brought is compiled, not tested - it is checks 85-91 in docs/ios.md; a long library
  shuffle put back on the phone by hand.

## Phase 4, slice 4: Artists (2026-11-14)

notes/ios-specs/phase4-library.md 2.6, 3.1 and 6.4, and question 4 (6.10 points here): Artists joins the Library's
switch - Your artists, or Artists without a library of your own, and All music's All artists - and an artist's page:
their picture and name, their albums newest first with yours marked, Play and Shuffle over every album, and the album
page's artist line becoming the link to it. No discography, description, pins or managing (question 4: nothing of
MusicBrainz's on the phone's artist page). On `phase4-artists` from `ios` 8a26431. **The app stays 0.9 (9)**;
src/__init__.py untouched; **no server change**: the two routes are the web's own, `GET /deadwax/navidrome/artists`
and `/artists/{artist_id}` (2.0.0-player.17). ROUTE_COUNT 40.

### Core (DeadwaxCore)

- **Artists.swift** (new), the web's pure rules ported - lib/shelves.ts's artists, lib/artistPage.ts, lib/yourLibrary.ts
  `yourArtists`, ArtistPage.tsx's prefetch:
  - `Artist` (id required; name, albumCount, coverArt, musicBrainzId read leniently, `counting(_:)` for your count),
    `ArtistList` and `ArtistWithAlbums` (an unreadable artist or album left out of its list, not the list lost).
  - `ArtistOrder` - Name and Most albums, kept per phone under the web's `deadwax-player-artist-order`, anything else
    read as Name.
  - `ArtistShelf` - `sorted` (Name: Fold's key, "#" last, a tie in Navidrome's order; Most albums: most first, an
    uncounted artist as none, a tie in Navidrome's order), `groups` (letters for Name, one unlabelled group for Most
    albums), `filter` (every word typed, Find's folding), and `view` - the order, groups, index and count line one
    page draws, the sorted list passed back in so Find doesn't sort again.
  - `YourArtists.of` - Navidrome's artists your albums name as album artist, each counting your albums of theirs.
  - `ArtistWords` - the web's words verbatim (titles, Find's placeholder, the sort label, the empty and no-match lines,
    `albumCountLine`) and the phone's own `offlineList`.
  - `ArtistPage` - `atOnce` 4 (PREFETCH_AT_ONCE), `kept` 20 (ARTISTS_KEPT); `rows` (artistRows over Navidrome's albums
    alone: each album once, the newest year first, the undated last, then the folded title, then the row's key),
    `line`, `marked`, `playOrder` (each album once, an empty id none), `playsLine` (every albums, in hand, settled,
    library and personal case).
  - `InTurns` - inTurns as a state the app drives (`begin`, `settled`), at least one at a time, only while going.
  - `ArtistAlbumAsks` - the prefetch: the albums Play plays asked four at a time in the page's order, asked anew only
    when they are other albums (the web's `playKey`, the ids sorted), what is in hand kept, only the newest round's
    answers and failures counting, Try again asking those that didn't come; `settled`, `playable`, `someMissing`,
    `answers`, `line`.
  - `ArtistPlay.plan` - every album in hand in the page's order, each song with its own album; Play at the album level
    from the first song, Shuffle at the songs level anywhere; nil with no song.
  - `ArtistOffline` - 3.1's rule for artists: `albums` (the answer in hand, else the downloads naming them),
    `playable` (only the songs on this phone, an album with none left out), `artists` (the artists of the downloaded
    albums, for the list when none was ever had).
  - `ArtistLink` - the album's artist line: a link once an id and a name are known; plain when the album answered
    without one; and while it might still become one, drawn as a link but not tappable (`pending`), so it never
    flashes from grey to purple.
- **ShelfIndex**: `kind`, `shows` and `entries` for an artist order (letters for Name, none for Most albums; shown at
  50 or more sorted, nothing typed) over the albums' own entries.
- **LibrarySwitch**: `LibraryPage.artists`, joining a saved order at its end (question 23's rule, already built);
  question 26 built - `LibraryMenuItem.order(page)` and `.layout(grid:)` are the •••'s second section (Albums: its
  order and Show as list/grid; Artists: its order; Playlists: neither), and `.allMusic` is a submenu,
  `LibraryMenu.allMusic` (All albums, All artists).
- **Routes**: `artists` and `artist` - 40. **DeadwaxClient**: `artists()`, `artist(id:)` (nil for the route's `{}`).
- **export-artist-vectors.cjs** (new) compiles shelves.ts, artistPage.ts, yourLibrary.ts, appFrame.ts and whose.ts and
  reads the words and numbers that live in components (LibrarySection.tsx, ArtistPage.tsx, persisted.ts), writing
  Fixtures/artists/artist-vectors.json: lists of artists (fixed awkward names and seeded random ones either side of
  the index's 50) under both orders with Find's for several words, yourArtists, rows, playOrder over rows as they
  come, every playsLine, inTurns driven step by step, and the words. **ui/test/iosartists.sim.cjs** runs its `--check`.

### Where the phone can't follow the web exactly

The web breaks an artist page's last two ties - two albums of one year - with `localeCompare`, ICU's collation, which
Linux's Foundation hasn't. The phone compares the folded titles by code unit (the same for every pair whose folding
leaves ASCII) and the rows' keys as ICU collates ASCII (`asciiCollate`: case folded first, then lowercase first). Two
albums of one year titled in other scripts may stand in another order than the web's. The exporter checks every row
vector is one where the two agree, and throws rather than write one the port can't meet. The year is compared as the
web compares it, as words ("999" before "2008").

### The app

- **The Artists page** (ArtistsScreen.swift, new), drawn as the switch's page or pushed (All music's All artists):
  rows, as the web's `Shelf kind="list"` - the round picture (48 pt, a person in its place), the name, "2 albums" (or
  "12 albums in the collection" on All artists), the chevron - under letter headers, the index down the edge at 50 or
  more (ShelfIndexStrip without years), Find's binding the page's own, "No artists match “…”.", the empty lines, the
  pull to shuffle on the page and pull to refresh pushed. Asked each time the page becomes the one shown, and as the
  app comes back to it; your albums asked with it, for your counts. Offline, an artist with nothing downloaded is
  dimmed.
- **ArtistsModel** (new, an environment object made with the server, reset for a new person): the one list, the
  newest ask's only, its failure; the order (UserDefaults); the drawn views per kind - all, yours, here - cached on
  what they're made from, built on the main actor; the artists' answers kept in memory, the last 20 opened (the web's
  ARTISTS_KEPT).
- **The artist page** (Artist/ArtistView.swift and ArtistPageModel, new): the round picture (200 pt), the name under
  it and in the bar once scrolled away, Play and Shuffle (PlayButtons, dimmed until `playable`), the line under them,
  Try again when some didn't come; then "Albums": each row's cover, title, the green tick when `marked`, "1994 · in
  your library", the chevron, opening the album with the artist's id handed on. The kept answer draws at once and is
  asked again as the page opens; a `{}` or a 404 draws "This artist isn't here any more…" (ErrorWords.artistGone) and
  forgets them; another failure keeps what was in hand. The album asks run in unstructured tasks (they carry on
  while the page is covered, so coming back finds them in hand), a generation guard dropping a landing for another
  artist. Pull to refresh asks the artist again, and Try again the albums. Back online, it asks again by itself.
- **PlayerModel**: `play(artist:shuffle:)` - ArtistPlay's plan, every album remembered (rememberQueue), the songs
  shelved for Info, in the tap.
- **The album page's artist line** (AlbumHero, AlbumModel's `artistLink`, AlbumRoute's `artistId` from the album the
  opener had): ArtistLink's three - a purple button opening the artist (at least 44 pt tall), purple and still while
  pending, grey when plain. A Button, not a NavigationLink: inside the hero's List row a NavigationLink takes the
  whole row.
- **LibraryView**: the third page; Find's binding and prompt the page shown's; the bar holds the switch, Playlists'
  + and the •••; the •••'s second section the page's order (a Picker in a Menu, showing the one chosen) and Albums'
  Show as list/grid; All music a submenu; Refresh asks the artists too. AlbumsScreen's EmptyLibraryNote,
  RefreshProblemNote and ShelfNote are shared with the Artists page.
- **AppRoute**: `.artists(scope)` and `.artist(ArtistRoute)` (the id, and the artist the opener had, drawn first).

### Decided here (the spec was silent, or this departs from it)

Questions 27-31 in the spec, each built to its recommendation: the artist page's picture round and centred, not the
web's full-bleed hero (27); every album Navidrome has a row and played, two pressings both (28); an album whose ask
answers `{}` left out as one that didn't load (29); Playlists' + kept in the bar (30); the artists list kept in memory,
not on disk (31). Question 26 is built as recommended. And:

- **Rows, not tiles**: the spec's 6.4 said "tiles or rows"; the web's artists are rows (`Shelf kind="list"`).
- **All music is a submenu** (All albums, All artists), not two more items in the •••.
- **No re-ask on coming back to an artist's page**: the asks carried on while it was covered; only back online, Pull
  to refresh and Try again ask again.
- **The line under Play isn't announced** by VoiceOver as it changes (the web's is `aria-live="polite"`): it changes
  as the page opens, where an announcement would talk over the page being read; the buttons' dimming says the same,
  and the line is read where it stands.

### Tests

- **ArtistTests** (17): the list and one artist read leniently (an unreadable artist or album left out), and `{}`;
  your count; Name's order a permutation with "#" last and ties in Navidrome's order, and Most albums' (property tests
  over seeded lists); Find keeping exactly the artists holding every word; the order as kept; rows newest first, the
  undated last, each album once, their ties, ASCII as ICU collates it, and their order as a property; inTurns never
  running more than its limit; the asks four at a time in order, others asking only what isn't in hand (an older
  round's answer and failure dropped), and every interleaving of answers and failures (150 seeded) settling with each
  album in hand or left out, never more than four out, Try again asking exactly those; Play and Shuffle's plan and
  levels; offline's albums, play and artists; the album's artist line.
- **ArtistVectorTests** (8): every vector of artist-vectors.json - the words and numbers, both orders' sorts, groups and
  index over 10 lists, Find's, yourArtists, rows and lines, playOrder over rows as they come, every playsLine (192),
  inTurns' steps.
- **LibrarySwitchTests** (9): three pages read and moved as the List moves them; the •••'s sections and words on each
  page, with All music's submenu.
- **ClientTests**: the two routes among Routes.all (40).
- **tests/test_ios_contract.py**: ROUTE_COUNT 40; `test_the_artist_answers_are_what_the_app_decodes` - ArtistList,
  Artist and ArtistWithAlbums within what /artists and /artists/{id} return (navidrome.py's keys, `{}` for a missing
  artist, the fields `Artist` reads, only the id required), and tests/test_navidrome_artists.py's fixtures within
  them.
- **Mutations**: 61 over Artists.swift, LibrarySwitch, ShelfIndex's artist half and the client's `{}`; 56 caught by a
  failing test at first. The 5 missed, each closed:
  - the index while Find keeps 50 or more - closed by a Find word, "e", added to the random lists' vectors (every
    find had kept fewer than 50, so the index was hidden by the count as much as by the typing);
  - an artist with an empty id counted as yours - a yours vector with one;
  - Play's order keeping an album twice - `playOrders`, the web's playOrder over rows as they come (artistRows already
    keeps each album once), which also drop an empty id: the phone didn't, and now does;
  - an old round's failure taken - a test of a failure landing after its album was asked again;
  - `stop()` keeping its key - `stop()` is gone: the app never called it (another artist gets a new ArtistAlbumAsks
    behind the page model's generation).
  Run again - the five, an empty id played in stop's place - all caught.

### Verified, and not

Verified:
- `swift test`: Core 1370, Audio 158, Turntable 12.
- The unsigned Debug and Release device builds (Xcode, `generic/platform=iOS`): no warnings but the usual
  appintentsmetadataprocessor line; no change to the .xcodeproj (the new files and Artist/ joined the synchronized
  App folder).
- `check_project.py` ok.
- `npm run build` and all 82 sims on Node 22.23.4, iosartists' `--check` among them.
- The full pytest suite: 4378 passed, 1 skipped (test_compose_example's docs rule among them: check 97 reads as on
  `ios`).
- The mutations above.

Not verified - only the phone can tell (the spec's section 9; docs/ios.md's checks 102-111):
- The Artists page's pictures (the cover art Navidrome names for each artist) on a real Navidrome; that the counts
  match the web's.
- The three pages in the pager, and the bar at the largest text size with the switch, Playlists' + and the •••.
- The •••'s Picker submenus on iOS 17 and 18; All music's submenu.
- The album asks four at a time against a real Navidrome, and on a locked phone; Play and Shuffle starting in the tap.
- The artist line's 44 pt button in the hero's row beside the title, and that it never flashes.
- Offline: the list from downloads after a force-quit; the dimming.
- CI's Xcode 26.6 (the older Swift): the new code spells out its closures' types.

## Phase 4, slice 4, after its review (2026-11-14)

The review of 8fbf50e found nothing serious, and four smaller bugs. All four are fixed in one commit on
`phase4-artists`, with Core holding each rule it can. The app stays 0.9 (9).

### What was wrong, and the fix

1. **Reopening an artist said "None of their albums are here to play."** while their albums were listed. A kept
   answer drew the albums at once, but ArtistPageModel asked their songs only after deadwax's answer to the artist
   came - up to the transport's 8 s. Until then the asks had no albums and the library was `.done`, so Play and
   Shuffle were dimmed under the wrong line. The same happened when deadwax came back to a page opened offline from
   a kept answer. The web asks the songs from its kept rows at once. Now `load` asks the albums in hand as soon as
   deadwax can be reached, before the artist's ask. ArtistAlbumAsks is keyed on the albums' sorted ids, so deadwax's
   answer naming the same albums asks nothing more, and one naming another album asks only it.
2. **Your artists could spin for ever.** With a library of your own and nothing of yours in hand (a first sign-in,
   another person), a failed first `/album_index?scope=yours` left no list to draw and no artists' failure. Only
   LibraryModel's `failures[.yours]` was set, and the page never read it. So the spinner stayed, with no Try again,
   and the pull shuffles - only the •••'s Refresh got out. Now `ArtistsWaiting.failure` (Core) says the artists'
   failure, or, for Your artists only, your albums', with Try again asking both.
3. **An album's artist line could stay purple and untappable for good.** An album opened without its artist's id
   (Now Playing's Go to the album, Downloads' `AlbumRoute(id:)`) whose load failed, found nothing, or wasn't asked
   (deadwax out of reach, nothing of it on the phone) stayed `.pending`. The web draws it plain then. `ArtistLink.of`
   now takes `coming`: with no album in hand and none coming, `.plain`. AlbumModel passes `!albumFailed && online`.
   With the opener's id the line still links, as the web's preview does.
4. **Offline, an artist could be named after a collaboration.** `ArtistOffline.artists` named each artist as the
   first downloaded album naming their id did, by its display line - the credit, so an "A & B" album listed first
   named artist A "A & B" for the sort, Find and their page's title. **Now each artist is named as most of their
   albums here name them; a tie goes to the shortest name, then to the first seen.** The shortest, because a
   collaboration's credit holds the artist's own name and more, so of two credits given equally often the shorter
   is the likelier to be the artist alone. An album naming nobody (nil or "") counts for none; an artist only such
   albums name has no name. The order is still where each artist first appears. Considered and not taken: a
   kept artist answer's name (Navidrome's own) - the stand-in is drawn only with no list in hand, when there
   is almost never one.

Also: the spec's own copy of check 97 now says to restart the deadwax container, as docs/ios.md's does.

### Tests

- **ArtistTests** (17 + 4):
  - `aKeptAnswersAsksCarryOverToDeadwaxsAnswer`: what the line said before the albums were asked; the kept answer's
    albums asked at once; deadwax's answer with the same albums (another title, another order) asking nothing, the
    kept round's answers counting; one more album asking only it.
  - `offlineAnArtistIsNamedAsMostOfTheirAlbumsNameThem` and `offlineArtistsByProperty` (300 seeded downloads of
    credits): each artist once where they first appear, named by a name one of their albums gives, no other given
    more often or as often and shorter, nameless only when no album names them.
  - `nothingToDrawSaysWhichAskFailed`: your albums' failure for Your artists only, the artists' own first.
  - `theAlbumsArtistLineLinksWhenItCan`: every case both ways of `coming`; with nothing coming and no id, plain.
- Fix 1's call order is the app's (ArtistPageModel); Core holds what it relies on.
- **Mutations**: 11 over the three Core rules - `coming` dropped and turned over; the name by the fewest albums, a tie
  to the longest, a full tie to the last seen, the first album's as before, an empty name counted, each album counted
  once; your albums' failure for every list, never read, and before the artists' - all caught.

### Verified, and not

Verified on the fixes' commit:
- `swift test` of the artists', the switch's, the index's and the client's suites: 74 (70 + 4).
- The unsigned Debug and Release device builds: no warnings.
- `check_project.py` ok.
- The 11 mutants.

Verified on its merge with `ios` at 3a2ae53 (main's 2.1.22-2.1.23 and their port, check 97's words). That merge
conflicted only here, at the end, where both had added; ios's section stands first.
- `swift test`: Core 1380, Audio 158, Turntable 12. Its warnings are all in test files slice 4 doesn't touch:
  - the Audio tests' redundant `#require`s and DeckReviewTests' `wait`;
  - ios's PlayHistoryTests (`record`'s result unused) and ResumeCaseTests (a redundant `#require`).
- The unsigned Debug and Release device builds: no warnings.
- `check_project.py` ok.
- `npm run build` and all 82 sims on Node 22.23.4.
- The full pytest: 4378 passed, 1 skipped.

Not verified - on the phone (docs/ios.md's checks 106, 108 and 110 now ask for each): the reopened artist's line,
the grey line in Airplane Mode, the collaboration's name offline. Fix 2 needs a first sign-in with deadwax's album
index failing, which no check asks for.

## Phase 4, slice 5: Songs, All songs' Shuffle, the app as 0.10 (2026-11-14)

notes/ios-specs/phase4-library.md 2.7, 3.1 and 6.5, and questions 2 and 24 (6.11 points here). The last slice of
Phase 4. It adds:
- **Songs**: every song of the collection, 100 a page, in Navidrome's order. A row opens its album and its ••• is the
  song's menu. It is the switch's fourth page where the collection is the Library, and All music > All songs with a
  library of your own.
- **All songs' Shuffle**: the collection's, at the head of All songs.
- **The feed held to the web**: useShuffleFeed.ts itself driven by an exporter, and replayed through the phone's
  ShuffleFeedRun.
- **The app as 0.10 (10)**.

On `phase4-songs` from `ios` 20bb0b3. src/__init__.py untouched; **no server change**: Songs pages the web's own
`GET /deadwax/navidrome/search` (search3, `q=&songCount=100&songOffset=`, artists and albums 0), and the Shuffle is
3b's two routes. ROUTE_COUNT stays 40.

### Core (DeadwaxCore)

- **Songs.swift** (new), the web's app/usePaged.ts and LibraryViews.tsx's SongsView ported:
  - `SongWords`: the web's words verbatim (Songs / All songs and `title(personal:)`, NO_SONGS, ", opens its album",
    the count line) and the phone's own (Find's "Find in songs", "No songs match “…”.", the offline line).
  - `SongsPaging`: the list a page at a time. Keyed on the query ("" for every song, else Find's words):
    - `start` asks the first page. Another query empties the list at once; the same query again keeps the list
      drawn until the first page lands in its place (`stale`).
    - `more` asks the next page - not while one is out, once every page is in, after a failure, or over a stale
      list. `retry` asks the failed page again.
    - `answered` adds a page, leaving out songs already drawn (`appended`, the web's appendPage). The next offset
      follows what the server handed out; a page short of 100 is the last.
    - `failed`; `reset`; `isNewest` (only the newest ask's answer or failure counts, the web's latestOnly).
    - `countText`: "N songs", once every page is in.
  - `SongsBody` (a spinner, the failure, the empty or no-match line, the offline line, the rows) and `SongsFoot` (a
    spinner, the failure, a refresh's "couldn't update", nothing).
  - `SongsList`: Find's query (trimmed), whether a row opens its album (an album id), whether it is dimmed (offline and
    not on the phone), and `asksMore` - the next page asked 25 rows from the end (usePaged's 800 px rootMargin, and a
    flick's worth more).
  - `ShuffleButtonFace`: All songs' Shuffle from ShuffleCan - Shuffle; Shuffle downloads; Getting ready… dimmed, with
    why under it after a failure; no button with nothing to shuffle.
- **LibrarySwitch**:
  - `LibraryPage.songs`, joining a saved order at its end (question 23's rule, already built).
  - Question 32: `LibraryPages.shown(_:personal:)` (Songs left out with a library of your own),
    `moved(_:personal:from:to:)` (Edit order's move over the pages shown, Songs keeping its place in the order kept)
    and `showing(_:in:)` (the page shown, or the first shown when it went).
  - `LibraryMenuItem.allSongs`, the end of `LibraryMenu.allMusic`; Songs has no page section in the •••.
- **Shuffle.swift**:
  - `ShuffleOf` (`.library` follows the Library's scope, `.allSongs` is always the store's) and `ShuffleAheads`:
    two ShuffleAheads behind one API (subscript, shown, answered, failed, take, reset), so neither lets the other's
    first page go (question 42).
  - `ShuffleFeed.startingElsewhere` made the web's exactly (question 41a): it draws even when there is no other
    song to start with, and a draw out of range swaps nothing. 3b's clamped the draw and made none then.
- **export-shuffle-vectors.cjs** (new) compiles useShuffleFeed.ts and usePaged.ts, with lib/upNext.ts,
  yourLibrary.ts, appFrame.ts and artistPage.ts, under shuffle.sim's Preact stand-in. Its own stand-ins are
  player/api.js (a faked deadwax keeping every ask, answered when the run says), app/usePins.js (the notice) and
  api/http.js. It writes Fixtures/shuffle/shuffle-vectors.json:
  - the words and numbers;
  - 524 `startingElsewhere` cases, each with its seed and how many draws it made;
  - 272 `songsAhead` queues, made by seeded runs of lib/upNext.ts's own edits;
  - 39 `appendPage` cases;
  - 60 runs of the hook itself: shuffle.sim.cjs's own 12 cases scripted, and 48 seeded. Their 3,477 steps are songs
    moving on, Repeat, Play Next, another shuffle, the queue cleared, an ask answered, failed or 404'd, and a retry.
    Each records the asks made, what extendQueue was handed (token, ids, levels, next order), the notice, the retries
    waiting, and the queue after.

  Plain ASCII, every random choice seeded. **ui/test/iosshuffle.sim.cjs** runs its `--check`.

### Where the phone and the web part

- **The retry** (question 41b, kept): the web's effect runs again when Repeat changes, and keeps every timer it
  started; the phone keeps one 30 s retry whatever changes. No run of the fixture changes Repeat, or starts another
  shuffle, while a retry waits; ShuffleTests hold the phone's own rule there.
- **Find on Songs** (question 33) asks Navidrome's search. The web's Songs has no Find.
- **The list kept while the app runs** (question 35). The web's SongsView asks its first page again each time it is
  drawn.
- **VoiceOver** says ", opens its album" only on a row that opens one (question 39).
- **A row's •••** is the song's whole menu (question 40).

### The app

- **SongsModel** (new, an environment object made with the server, reset for a new person): one list per person.
  - `show` asks only when the query differs, or nothing was drawn after a failure; `refresh` asks the first page
    again; `near(index)` asks the next page; `retry`.
  - The asks are `client.search(query, songs: 100, songOffset:)`. Each cancels the one before; an epoch and
    `isNewest` guard what lands; `landed` moves when a first page does, and the screen goes to its top.
- **SongsScreen** and **SongRow** (new), drawn two ways (question 32): as the switch's page (`SongsScreen(page:)`:
  the switch's Find, bar and •••, the pull shuffling the Library) or pushed (`SongsScreen()`, AppRoute.allSongs: its
  own title and Find, pull to refresh, All songs' Shuffle at its head as a SecondaryPill).
  - The ask is keyed on the person, deadwax reachable, the page being the one shown, and the query; while typing it
    waits 350 ms.
  - Rows are SongRow: the cover (48 pt), the title, "artist · album", a NavigationLink to the album
    (AppRoute.album), the song's QueueMenu (Play Next, Play Last, Add to a playlist…, the download items).
  - A row 25 from the end asks for more as it appears; the foot follows SongsFoot; a refresh's failure is
    RefreshProblemNote at the top.
  - Offline, rows not on this phone are dimmed and open nothing, and no more is asked. It goes to its top on another
    Find, a first page landing, and the Library tab tapped.
- **ShuffleModel** holds `ShuffleAheads`: every call names `.library` or `.allSongs`. LibraryView's are `.library`;
  All songs asks `.allSongs` as it shows, back in front, deadwax back, and on its pull. All songs' tap plays its page
  as `player.play(shuffled:)` does the Library's, in the tap; offline it is Shuffle downloads.
- **LibraryView**:
  - The pager, the switch, Edit order and the first page are the pages shown (`shownOrder`); Songs' Find text and its
    pull are the page's own.
  - A library of your own arriving or going re-shows the page (`onChange(of: server.access.hasLibrary)`).
  - The •••'s All music ends with All songs (symbol music.note).
  - Refresh asks Songs' first page again, once it has been shown, without a library of your own.
- **AppRoute.allSongs**; DeadwaxApp makes the SongsModel and resets it with the others.
- **The app's version 0.10 (10)**: Base.xcconfig (and its comment's list of versions), check_project.py, ios.yml's
  plutil check, tests/test_ios_install.py; ios/README.md, docs/ios.md (the install line, About, checks 112-120), the
  README's iPhone paragraph (Phases 1 to 4).

### Decided here (the spec was silent, or this departs from it)

Questions 32-42 in the spec, each built to its recommendation:
- 32 Songs a page only where the collection is the Library;
- 33 Find asking Navidrome;
- 34 offline;
- 35 the list kept while the app runs;
- 36 a page that won't come waiting for Try again;
- 37 All songs' Shuffle, and none on the switch's Songs page;
- 38 the page kept with no songs;
- 39 VoiceOver's ", opens its album" only where true;
- 40 the song's whole •••;
- 41 the feed's two partings;
- 42 two ShuffleAheads.

Questions 2 and 24 are built as recommended.

### Tests

- **SongsTests** (16):
  - The paging: every song a page at a time; a page of exactly 100 asking once more; the offset following what the
    server handed out; only the newest ask counting; another query emptying the list; the same query keeping it
    until its first page; a refresh's failure; a failed page waiting for Try again.
  - The body and the foot in every state.
  - A row's rules, VoiceOver's words and the words.
  - All songs' button.
  - The two Shuffles' scopes, and that they never move each other.
- **ShuffleVectorTests** (5): every vector of shuffle-vectors.json - the words and numbers, `startingElsewhere` (its
  draws counted), `songsAhead`, `appended`, and every run replayed step by step through ShuffleFeedRun and Up Next's
  Swift functions - counted, so a fixture that stopped meeting answers, next orders, the notice or retries fails.
- **LibrarySwitchTests** (9 + 4): four pages; a three-page saved order reading back with Songs at its end; `shown`
  and `showing`; the personal moves, every one-page move with Songs in each of its four places (the pages shown moved
  as the List moves them, Songs where it was); the •••'s sections and words with All songs.
- **ShuffleTests** (+1): a draw made with nothing else to start with; a random of 1 now swaps nothing;
  `repeatTurnedOffWhileARoundIsOnItsWay` races the next round's answer under Repeat Off as well as One, and lands it
  under All (the mutation below).
- **ClientTests**: `songsAskForEverySong` - the ask's path and items (`q` "", `artistCount` 0, `albumCount` 0,
  `songCount` 100, `songOffset` 200).
- **tests/test_ios_contract.py**: unchanged but a comment - the feed's numbers and words are still read from the web's
  own source.
- **Mutations**: 69 over:
  - Songs.swift: the paging, the body and the foot, a row's rules, the button;
  - LibrarySwitch's pages shown;
  - Shuffle.swift's feed: `startingElsewhere` (3b's clamp and its skipped draw among them), `songsAhead`, and
    ShuffleFeedRun's look, fresh, retry and letting go;
  - the two ShuffleAheads.

  67 were caught at first. The 2 that lived:
  - a next round's answer played under Repeat Off when it lands before the look has caught up - the fixture's runs
    always look when Repeat changes, which lets the ask go first, and ShuffleTests raced it under One only. Closed by
    racing it under Off too; run again, caught.
  - `more()` asking over a refresh's old list (`!stale` dropped) - equivalent: a list is stale only while its first
    page is out or has failed, which `!loading` and `!failing` already refuse. Kept, as the rule's own statement.

### Verified, and not

Verified:
- `swift test`: Core 1406, Audio 158, Turntable 12. No new warnings.
- The unsigned Debug and Release device builds (Xcode, `generic/platform=iOS`): no warnings but the usual
  appintentsmetadataprocessor line; no change to the .xcodeproj (the new files joined the synchronized App folder).
- `check_project.py` ok.
- `npm run build` and all 83 sims on Node 22.23.4, iosshuffle's `--check` among them.
- The full pytest suite: 4378 passed, 1 skipped (test_compose_example's docs rule, test_source_bytes and
  test_ios_install's 0.10 among them).
- The mutations above.

Not verified - only the phone can tell (the spec's section 9; docs/ios.md's checks 112-120):
- Songs against a real Navidrome: that search3 with an empty query pages every song, in the web's order, to its end;
  what its search finds for Find's words.
- Paging under a fast flick: that the next page is in before the end is reached; scrolling 10,000 rows.
- The four pages in the pager with logins off, and the switch and Edit order with logins on and off on one phone.
- All songs' Shuffle playing in the tap, past 200, and its "Getting ready…".
- Offline: the dimmed rows, no spinner at the end.
- VoiceOver's rows.
- CI's Xcode 26.6 (the older Swift): the new code spells out its closures' types.

## Phase 4, slice 5, after its review (2026-11-14)

The review of 0de4fbd found nothing serious, and six smaller things. All six are fixed in one commit on
`phase4-songs`, with Core holding each rule it can. The app stays 0.10 (10).

### What was wrong, and the fix

1. **Songs' empty and no-match words followed Find's live text.** SongsBody built them from what Find held, not
   what was searched. So after a search for "zzz" found nothing, typing "zzzq" said "No songs match “zzzq”." during
   the 350 ms pause before it was asked - and offline, where it isn't asked, for good. Clearing Find after a no-match
   flashed "No songs yet." for a frame. **SongsBody.of now takes no `typed`**: the words are built from
   `paging.query`, what the list drawn was searched for.
2. **Paging didn't pick up when deadwax came back to a reader at the end of the list.** The last rows' `onAppear`
   fired offline and asked nothing; `show` asks nothing for the same query; so the list stopped there, with no spinner
   and no Try again, until the reader scrolled away and back. **SongsReach** (Core, new) keeps the furthest row that
   appeared:
   - SongsModel's `appeared(_:online:)` records every row, and asks the next page as before while deadwax can be
     reached.
   - Its `resumed()`, called by SongsScreen when deadwax is back, asks it when the furthest row is near the end
     (`SongsList.asksMore`) and `more()` would.
   - SongsReach is held outside what the screen observes. Kept in SongsPaging, every row appearing would have
     redrawn the whole list.
   - It knows the list it was drawn from by SongsPaging's new `list`, one more each time another list is drawn
     (another query, a first page in place of the old), and forgets the rows of a list gone.
3. **The refresh banner's Try again asked while offline**, against question 34. It now asks whether deadwax is back,
   as the page's other Try agains do.
4. **All songs' pull to refresh ended at once**: `pulled()` didn't wait for the refresh, so the spinner went while
   nothing new was drawn. SongsModel's `refresh` hands back its ask's task, and `pulled()` awaits it, as Artists'
   does.
5. **The exporter claim.** 0de4fbd said export-shuffle-vectors.cjs drove usePaged.ts; it compiled it but called only
   `appendPage`, so SongsPaging's state machine was held by the hand-written tests alone. **The exporter now drives
   usePaged as SongsView renders it** (`paged`), under the same Preact stand-in:
   - the end of the list is a fake IntersectionObserver's sentinel coming into range;
   - each page is kept open until a step answers it, from the key's list as it is then, or fails it.

   It writes 49 runs: 9 of usePaged's own cases scripted (a page at a time, a last page of exactly 100, none at all,
   a list that grows at its front, one that loses a song, a failure and Try again, the first page failing, another key
   with the old one's page landing or failing late, another key while a page has failed) and 40 seeded. That is 1,904
   steps, each with the pages asked, what is drawn (its count, first and last, and FNV-1a over every id), loading,
   done and the error shown.

   ShuffleVectorTests' `songsPageAsTheWebsUsePagedPages` replays each through SongsPaging: near is `more()`, Try again
   `retry()`, another key `start(_:)`. Every step matched at once. The one place the two part is question 36: the
   web's sentinel asks again when it comes back into range after a failure, and the phone waits for Try again. So no
   run comes near the end while the error shows.
6. **The README** (and ios/README.md, and docs/ios.md's introduction and The Library) said the switch is Albums,
   Playlists, Artists and Songs. With logins on it is three pages, every song under All music > All songs. Each now
   says both.

### Tests

- **SongsTests** (16 + 1):
  - `whatSongsDraws`: the no-match line names what was searched, offline too, and Find cleared draws the spinner.
  - `deadwaxBackPicksUpWhereTheReaderGotTo` (new):
    - rows to the end appearing offline, then the next page asked;
    - a row past the list counting for nothing;
    - only near the end;
    - another query, or a first page in place of the old, forgetting the old list's rows - a refresh's old list
      still drawn keeps them, and asks nothing over it.
- **ShuffleVectorTests** (5 + 1): `songsPageAsTheWebsUsePagedPages`, counting answers, pages that repeated a song
  already drawn, failures, finished lists and keys, so a fixture that stopped reaching them fails.
- Fixes 3 and 4 are the screen's and the model's (no Core to hold them).
- **Mutations**:
  - 9 over the fixes' Core: the words from nothing searched, or no-match said of every song; SongsReach keeping
    another list's rows, wanting more of another list, keeping the latest row rather than the furthest, counting a
    row past the list, wanting more wherever the reader got; `list` not moved by a first page or another query. All
    caught.
  - Slice 5's 20 paging mutants run again against ShuffleVectorTests **alone**, to see what the web's usePaged now
    holds by itself: 11 of 20 caught. The 9 it can't reach are the phone's own rules, each caught by SongsTests in
    slice 5's run:
    - a refresh of the same query (`stale`: 4 of them) - the web has no such refresh;
    - more() after a failure - question 36's departure, which the runs leave out;
    - reset() for a new person; the count line waiting for every page;
    - more() before anything was asked, and Try again with nothing failed - states the web never reaches (every run
      begins with a first page, and Try again shows only with the error).
  - One of the 11 at first took the test process down (`asks[n]` out of range once the phone had parted from the
    web). The replay now records an issue and ends the run instead; run again, caught with issues.

### Verified, and not

Verified, on the final tree:
- `swift test` on the whole package: DeadwaxCore 1,408 tests in 161 suites, DeadwaxAudio 158 in 17, and the other
  12, all passed.
- The unsigned device builds, Debug and Release: both succeeded.
- `check_project.py`: passed.
- `npm run build`, and every sim: 83 run, none failed.
- The full pytest: 4,378 passed, 1 skipped.

Not verified - on the phone (docs/ios.md's checks 115, 116 and 119 ask for each): the no-match line while typing on,
paging picking up when Airplane Mode goes off at the end of All songs, the pull's spinner lasting until the songs
come.

## Phase 5, slice 1: Search, your library's half (2026-11-14)

notes/ios-specs/phase5-search.md 2.1-2.9, 3.1-3.5 and 6.1, and questions 1-7 and 10 (6.5 points here). The first slice
of Phase 5: the Search tab, with one list as the web's Search draws it - Top results, then Artists, Albums and Songs,
yours first in each - from Navidrome's search3, a song playing in its tap. MusicBrainz's half (albums, artists and songs
you don't have), the album you don't have and Get are slices 2-4.

On `phase5-search` from `ios` 3458122, after the spec (4bf7793) on its own. src/__init__.py untouched; the app stays
0.10 (10). **No server change**: `/navidrome/search` takes every offset already, and `/library/owned` has answered since
v0.9.1. ROUTE_COUNT 40 -> 41 (`/library/owned`, new to the phone).

### Core (DeadwaxCore)

- **Owned.swift** (new), ui/src/lib/owned.ts:
  - `OwnedAlbum` and `OwnedAnswer`, read leniently (a field of the wrong shape is absent; a year as digits or text).
    `OwnedAnswer.artists` is the album artists, once each - the names the box is read against (app/useOwned.ts).
  - `OwnedIndex`: by release, by release group, and by name for a folder with no MusicBrainz ids (buildOwnedIndex);
    `forRelease`, and `forGroup` (slice 2's, ported with the index).
- **SearchReading.swift** (new), ui/src/lib/searchQuery.ts: `artistNames` (folded name -> the library's spelling);
  `read` - album-by-artist, an artist, or free words; the longest name winning, at the start or the end; the
  separators; Various Artists and "va"; `words`, `quoteTerm`, `withTypeFilter`, `fieldedAlbumQuery` (slice 2's
  MusicBrainz queries, ported with the reading they belong to); the numbers (`librarySettleMs` 200, MusicBrainz's 700
  ms and 3 characters for slice 2, `maxCharacters` 200).
- **SearchList.swift** (new), ui/src/lib/searchList.ts, searchResults.ts and whose.ts, and songs.ts' titleKey:
  - `SearchKind`, `SearchView`; `LibraryResults` (search3's three lists, each read leniently); `SearchCounts`.
  - `SearchPacing`: All's 5 artists, 8 albums, 12 songs; a kind view's 50, 50, 100; Top results 3 and the
    sections' previews 2, 3, 3 (a phone's); the 5 albums prefetched (`albumsToPrefetch`, Top results' songs first),
    `songIndex`, `plays`, `preferredSongs`.
  - `SearchRow`; `SearchMarks` (logins on with a library of your own; the folders' index; your albums and how many
    of each artist's; the albums in hand); `SearchWhose` (navidromeYours, albumYours, songYours, artistYours,
    rowYours, libraryPlace) - an unknown whose is never "not yours".
  - `SearchList`: `namedArtist`, `knownArtists`, `pool` (each kind's rows, yours before the collection's,
    `sectionRows`), `matchTier`, `ranks` (tier, then source, kind, position), `candidates`, `family`, `topResults`
    (the rounds, the family), `line` and `artistLine` (the facts and the place, apart), `Drawn` and `draw` (the All
    view's list for some words), `kindRows` (a kind view's, Artists led by the artist the box named), `knownNames`.
  - `KindLibrary`: a kind view's own search3 - its state, its rows, `full` (as many as asked), and More appended
    without repeats.
  - `SearchWords` (the web's words, and the phone's own hint and offline line); `SongTitle.key` (titleKey).
- **SearchState.swift** (new), the state Search.tsx keeps:
  - The box (`typed`: trimmed as JavaScript trims; an empty box lets everything go), the view (`choose`), Try again,
    the keyboard's Search (`submitted`).
  - All's search3: asked once per words (`wantsLibrary`), again only after a failure, Try again or the keyboard's
    Search on a failure; only the newest ask's token counts; `librarySkipped` while Navidrome is known not to be there.
  - `advance`: the list drawn once per run, only in All - a chip, See all and Back to All draw afresh. Typing other
    words keeps the list until theirs settles.
  - `albumsWanted` and `albumReady`: the albums asked for so a song plays, kept for the box's life, an album landing
    for an ask let go dropped.
  - A kind view's own (`wantsKind`, `askingKind`, `kindAnswered`, `kindFailed`, `kindSkipped`, `kindShown`) and its
    More (`askingMore` with the offsets, `moreAnswered`, `moreFailed`).
- **JavaScript's semantics, kept**: strings compared by UTF-16 code units (WebText.same), a stable sort (Swift's isn't:
  the index breaks ties), JavaScript's trim (JSText.trim), and titleKey's `/iu` regex - ſ folds to s, and `\b` counts
  ASCII word characters plus U+017F and U+212A.
- **Routes**: `search` gains `artistOffset` and `albumOffset`; `libraryOwned` (41), given 30 s (it walks the library
  when the saved scan is behind). `DeadwaxClient.searchLibrary(_:counts:offsets:)` (each offset sent only above 0, as
  the web's searchLibrary) and `owned(ifNoneMatch:)` (a 304 as `.unchanged`).
- **export-search-vectors.cjs** (new) compiles lib/searchList.ts with tsc and runs searchList, searchQuery,
  searchResults, songs, whose and owned, reading SEARCH_COUNTS from api.ts and the box's, Top results', More's and
  the nothing-found words from Search.tsx. It writes Fixtures/search/search-vectors.json (1.4 MB, plain ASCII, every
  random choice seeded - 5151):
  - the numbers (11) and words (14);
  - 78 hard names and titles folded (foldName and titleKey: asides, accents, ligatures, Final Sigma, the long s);
  - 12 name lists over 57 texts read (672 readings);
  - 4 folder lists indexed and looked up;
  - whose under 6 kinds of marks;
  - the prefetch;
  - 244 searches - 24 worked and 220 seeded, their texts biased to the names in hand. Each holds its reading, pool,
    every candidate's tier, Top results, the sections capped and in full, every line in a section and in Top results,
    the words, and the albums asked for first.

  **ui/test/iossearch.sim.cjs** runs its `--check`. It is already 1.4 MB: slices 2-4 put theirs in a second file, as
  the spec's 5.2 allows.

### Where the phone can't follow the web exactly

- **No MusicBrainz yet**: no phantoms, no slots, no `RESULTS_WAIT_MS`. Top results are decided on the library alone -
  the web's `decidedTop` with no MusicBrainz candidates, which is what the fixture's cases run.
- **The late library** (question 7): no `LIBRARY_LATE_MS`. The asking line stays until the library settles (the
  transport's 8 seconds at most).
- **The hint and nothing found** (questions 3 and 4): "Search your library." / "Search your library and the
  collection.", and "No results for “…”." with "Check the spelling or try a new search." until slice 2.
- **Navidrome's status unknown**: the web waits for it before asking search3; the phone asks (NavidromeGate's
  `shownOnPhone`, the Library's own rule) and skips only once a check has found Navidrome isn't there.
- **Offline** (questions 5 and 12) is the phone's own.
- **`/library/owned`** (question 6): asked as Search shows, kept in memory per person with its ETag, never on disk.
- **The sections and Top results are always a phone's** (2, 3, 3 and 3): the web's at a phone's width.

### The app

- **The tab** (question 1): `AppTab.search` between Library and You, `magnifyingglass`. AppNavigation has its stack
  (`search`) and `searchScrollToTop`: Search tapped on a pushed page pops to the list, at the list scrolls to its top.
  `open` and the pages' going back know the tab.
- **SearchModel** (new, an environment object made in DeadwaxApp with the server, the Library's and Artists' models
  and Reachability; reset for a new person). It keeps Core's SearchState and makes the asks it calls for:
  - All's search3 200 ms after typing pauses (or at once on the keyboard's Search), a kind view's own beside it, More
    by offset, each cancelling the one before; an epoch drops anything begun for the last person.
  - As an answer lands, its five albums - a Songs view's too, as the web's - so a song's tap plays.
  - `/library/owned` with its ETag each time Search shows, and your albums and the library's artists when not in hand.
  - The list announced as it draws ("In your library: 1 artist, 2 albums, 11 songs.", or "No results for …"), a chip as
    it is pressed, More's count as it lands.
  - The box clamped to 200 Unicode scalars, as `q` counts them.
  - Nothing asked while deadwax can't be reached; when it is back, or Navidrome is found again, what wasn't asked is.
- **SearchScreen** (new, ios/App/Search/): a ScrollView of rows under the navigation bar's `.searchable` field, always
  drawn (question 2), the keyboard's Search submitting.
  - The chips: a segmented Picker (All, Artists, Albums, Songs) while the box has words.
  - All: Top results, then each section with See all; a kind view: its rows, More from your library when full, with
    Loading… and Try again.
  - The asking line, a failure's words with Try again, nothing found, the hint, the offline line, and the Library's
    gate words above the list while Navidrome is known not to be there.
  - It goes to its top when the view changes or new words' list is drawn (question 13).
- **The rows** (`SearchRowView`), as the Library's:
  - The cover (round for an artist), the title, and the line - its facts truncating, its place ("in your library")
    never.
  - A song's tap plays its album from it, in the tap with nothing awaited, when the album is in hand (▶ after it),
    else opens the album (question 10). Its ••• is the album page's song menu once the album is in hand, the song's
    own before (question 11).
  - An album and an artist push their pages on Search's stack.
  - Offline, what has nothing on this phone is dimmed and opens nothing (question 12).
  - VoiceOver reads a row as one: its title, its line, and for a song ", plays it from its album" or ", opens its album".

### Decided here (the spec was silent, or this departs from it)

Questions 11-13 in the spec, each built to its recommendation:
- 11, a song's ••• before its album is in hand;
- 12, offline rows dimmed as the Library dims them;
- 13, the list to its top when it changes.

And smaller ones, not worth a question:
- `/library/owned` given 30 s, as the album index;
- the box clamped by Unicode scalars;
- Try again while deadwax can't be reached checks whether it is back (Reachability.tryNow), as the other pages' do;
- Navidrome found again asks what was skipped for the words.

### Tests

- **SearchVectorTests** (8): every vector of search-vectors.json - the numbers and words, folding, the readings, the
  folders indexed and looked up, whose, the prefetch, and every search: its pool, candidates, Top results, the
  sections capped and in full, each line, whose, the words, the albums prefetched, the artist named, the list as
  drawn, and the Artists view's rows.
- **SearchTests** (18), by hand:
  - The state: the list drawn once the library settles, then frozen; new words keeping the old list until theirs
    settles; an empty box letting everything go; a failure drawn, and asked again only when asked to; Try again and
    Back to All drawing afresh; a library not there skipped, not "nothing found"; a kind view's own and More by
    offset; a full page with nothing new ending More; a kind view for other words not shown.
  - The rules: a song plays only from its album in hand; the albums prefetched once and kept for the box; tied
    candidates keeping their order as JavaScript's sort does; your albums counted by their artist; the phone's own
    words.
  - Reading leniently: search3's answer and the folders'.
  - The client: the library asked with its counts, and offsets only above 0; the folders asked with their ETag.
- **ClientTests**: `Routes.all` 41; `/library/owned` among the routes given longer (30 s). **FixtureFiles**: the new
  fixture.
- **tests/test_ios_contract.py**: ROUTE_COUNT 41; every count and offset Search sends within the route's bounds; three
  new tests - `/library/owned`'s fields within OWNED_FIELDS and `yours` (the path the one needed), search3's keys
  LibraryResults', and the box's limit `q`'s 200.
- **Mutations**: 25, each applied alone with SearchTests and SearchVectorTests run. 22 were caught at first; the 3
  that lived were closed and caught when run again:
  - 4, Top results' sort not stable: no search in the fixture tied two candidates on every key. Closed by
    `tiedCandidatesKeepTheirOrderAsJavaScriptsSortDoes`.
  - 16, the separators kept in the title: no text put a separator where a longer name can't take it in. Closed by
    five texts that do ("- dummy portishead", "| third | portishead", "portishead third : |" among them).
  - 18, an untagged folder indexed by name even with ids: no lookup asked a tagged folder's name. Closed by two
    ("Third" and "Dummy" by Portishead, under a group nobody holds) - a folder with ids is never a guess by its name.

  The 25:
  1. starts-with needing two characters, not three;
  2. an artist read as exact under album-by-artist;
  3. Top results without the best's family;
  4. Top results' sort not stable;
  5. the source before the tier;
  6. a folder deadwax said nothing of not yours;
  7. a song's album unknown read as the collection's;
  8. the collection's rows before yours;
  9. the named artist not leading;
  10. a year of 0 said;
  11. titleKey's long s not an s;
  12. titleKey's remaster aside without its word's end;
  13. titleKey's brackets folded away;
  14. the prefetch's order;
  15. the reading preferring the trailing artist;
  16. the separators kept;
  17. "va" not Various Artists;
  18. an untagged folder indexed by name even with ids;
  19. a guess looked for though something is held;
  20. the list drawn again each time;
  21. an older ask's answer kept;
  22. a failure not asked again;
  23. the box emptied keeping the albums in hand;
  24. More's page appended with its repeats;
  25. Back to All not drawing afresh.

### Verified, and not

Verified:
- `swift test`: Core 1434, Audio 158, Turntable 12. No new warnings.
- The unsigned Debug and Release device builds (Xcode, `generic/platform=iOS`): no warnings but the usual
  appintentsmetadataprocessor line; no change to the .xcodeproj (ios/App/Search/ and the model joined the synchronized
  App folder).
- `check_project.py` ok.
- `npm ci`, `npm run build` and all 84 sims on Node 22.23.4, iossearch's `--check` among them.
- The full pytest suite: 4382 passed, 1 skipped (test_ios_contract's new three, and test_compose_example's docs rule, among them).
- The mutations above.

Not verified - only the phone can tell (the spec's section 9; docs/ios.md's checks 121-129):
- `.searchable` in a tab's NavigationStack keeping its words over a pushed page, and the keyboard's Search key
  submitting on iOS 27.
- The 200 ms pause over WireGuard, the list never flickering as older asks are cancelled, and the prefetch landing
  before a finger reaches a song.
- `/library/owned`'s first answer for James's library, and its 304 after.
- The segmented chips at 320 points and at accessibility sizes.
- Navidrome's real search3 ordering and matching as the fixtures' fakes do.
- VoiceOver's rows and announcements; offline's dimmed rows.
- CI's Xcode 26.6 (the older Swift): the new code spells out its closures' types.

## Phase 5, slice 1, after its review (2026-11-14)

The review of 7291225 found the Core port solid and four bugs in the app's wiring, the first two confirmed by a probe of
Core. All four are fixed in one commit on `phase5-search`, with Core holding each rule it can; then `ios` 45c4c5f (the
Phase 4 spec's question 32 answered, docs only) is merged in. The app stays 0.10 (10); no server change.

### What was wrong, and the fix

1. **A failed search asked again when deadwax came back was never drawn.** Reachability counts the phone offline only
   after two failures, so a first search over a dropping WireGuard runs, fails, and its failure is drawn. When
   deadwax answered again, `resumed()` asked again, but started a new run only for a library *skipped*, never for one
   that *failed*. `advance` then had nothing new to draw - and the answer cleared `failure`, so the failure's note
   fell back to "Search works once deadwax is back." while online.
   - **Core: `SearchState.resumed()`**, the web's own rule (Search.tsx's status effect, :1087-1100, from its late
     review): the words' library, failed or skipped, is asked again, and a list this run drew for the words starts a
     new run, so the answer takes its place. SearchModel's `resumed()` calls it whenever Navidrome isn't known to be
     away.
   - **The failure's words stay with the list drawn with them**: SearchModel lets `failure` go only when a list
     without a failure is drawn, not when an answer lands. The note's fallback (never reached now) says "Something went
     wrong." online, the offline line only offline.
2. **Going back to words whose answer had landed drew nothing.** Type "port", pause (asked), type "a": "port"'s answer
   lands under "porta" and isn't drawn. Backspace inside the pause: the words were asked already, so nothing is asked
   again - and nothing drew, because SearchModel drew only as an answer landed, where the web's `advance` runs on every
   render. A spinner for ever, or the last words' list under these.
   - **SearchModel draws as the box changes, as the pause ends and on the keyboard's Search**, besides as an answer
     lands. `advance` draws nothing unless the library has settled for the box's words, so drawing more often draws
     nothing more.
3. **Your albums were never asked again once in hand.** `shown()` loaded `.yours` only when there was none. After an
   Add or a Remove, LibraryModel keeps the old list under a forgotten generation, so Search read whose a row is from a
   list let go; the web asks again on each Add or Remove (`yoursGeneration`).
   - `shown()` looks at your albums every time (LibraryModel asks only when the generation has moved), and SearchScreen
     calls it as `library.generations[.yours]` moves while Search is on screen - an Add, a Remove, a star seen from
     elsewhere. `/library/owned` is asked again with it (a 304 unless something changed; its `yours` follows an Add too).
4. **Repeated ids reached a SwiftUI ForEach.** search3 can name a song twice (the fixture's seeded answers do), and a
   ForEach given one id twice draws the wrong rows.
   - **Core: `SearchList.drawable`** - each key once, the first kept, search3's order otherwise. The screen draws Top
     results, each section and a kind view's rows through it. The sections' rules stay the web's (the vectors hold the
     web's repeats); this is the drawing's alone.

And the review's note on type-checking: `SearchScreen.swift:356` took 366 ms. The row view is now small functions with
every value's type spelled out (the link rows, the three `dims`, the song row and its menu, the face's picture, line
and trailing mark). Measured with `-warn-long-expression-type-checking=40 -warn-long-function-bodies=80`:
- **Release (whole module)**: nothing in the Search files over either limit.
- **Debug**: the row view's slowest function took 374 ms - `dims(album:)`, one `downloads.album(id:)` call.
  - Moving `dims(song:)` above it moved the cost to `!downloads.isHere(id)`, 267 ms: it is the first member lookup
    into DownloadModel in the file's frontend job, an @Observable class whose macro-made members are expanded for that
    lookup. The expression's own complexity has nothing to do with it.
  - The same one-time cost lands on SongsScreen's `allSongsCan` (374 ms), BackgroundWork's `downloads` didSet (260-346
    ms), AlbumView's `libraryLine` (365 ms) and others in the same build. `tapped` (147 ms) is the file's first lookup
    into PlayerModel.
  - SearchScreen's body is 102-123 ms (its longest expression 57-62 ms).
  - No spelling of the expression avoids that lookup: whichever line asks DownloadModel first pays it, once per file.
    A whole-module build - Release, which is what CI's device build is (ios.yml) - pays it once per module.

### Tests

- **SearchTests** (+5, 23):
  - `deadwaxBackAsksAFailedLibraryAgainAndDrawsItsAnswer`: the failure drawn; asked again without a new run, drawn
    nowhere (the bug, held as a fact); resumed, the failure staying while it is asked, then the answer in its place.
  - `navidromeFoundAgainAsksASkippedLibraryAndDrawsItsAnswer`.
  - `resumingLeavesAnAnswerAndAKindViewsRunAlone`: an answer isn't asked again; another text's failure isn't the
    box's; a failure under a chip is asked again and drawn when All is chosen.
  - `backToWordsAlreadyAnsweredDrawsWithoutAsking`: the review's "port", "porta", "port".
  - `aRowNamedTwiceIsDrawnOnce`: the first kept, search3's order, a song and an album with one id both drawn.
- **Mutations**: 8 more, each applied alone with SearchTests and SearchVectorTests run, all caught:
  1. resumed starting no new run;
  2. resumed not asking a skipped library again;
  3. resumed for another text's failure;
  4. resumed only for a skip (the bug);
  5. resumed for an answer too;
  6. drawable keeping repeats;
  7. drawable keeping the last of a repeat;
  8. drawable by id alone.

  The model's own wiring (when it calls `resumed`, `draw` and `load`) has no test: SearchModel is the app's, untested
  off a phone, as every model is.

### Verified, and not

Verified, on the fixed tree before its commit (the merge of `ios` after it brings two lines of the Phase 4 spec):
- `swift test`: Core 1439, Audio 158, Turntable 12.
- The unsigned Debug and Release device builds: no warnings but the usual appintentsmetadataprocessor line; the
  .xcodeproj unchanged.
- `check_project.py` ok.
- `npm run build` and all 84 sims on Node 22.23.4.
- The full pytest suite: 4382 passed, 1 skipped.
- The 8 mutations above; the type-check timings above, Debug and Release.

Not verified - only the phone can tell: each fix as James would see it (docs/ios.md's checks 127 and 128 cover the
first two: words typed back to, and a search when deadwax comes back), and Search's lines following an Add made from
an album page pushed over it.

## The Cover Art Archive relay (2.1.24)

Phase 5's question 8 (notes/ios-specs/phase5-search.md on `phase5-search`, sections 4 and 10): the web draws a
MusicBrainz album's cover straight from coverartarchive.org (`lib/pressings.ts` coverAddresses, `requestsView.ts`,
`LibraryParts.tsx`), and the app talks only to deadwax. So deadwax passes the Archive's front covers on, as a main
patch before Search's slice 2. The web doesn't change.

- **The route**: `GET /deadwax/coverart/{kind}/{mbid}?size=`, a user's (included with `current_user`;
  tests/test_logins.py ROUTES, "user"). `kind` is `release` or `release-group` (a `Literal`, 422 otherwise); `mbid`
  is MBID_PATTERN, the lowercase hyphenated UUID every other route takes (422 otherwise - an uppercase one too, as
  MusicBrainz writes them lowercase; one with a slash never reaches the route, a 404); `size` is `250` (the default:
  Search's rows draw a 44 pt cover, 132 px on a 3x screen), `500` or `1200`, 422 otherwise. Answers: 200
  with the image (jpeg, png, gif or webp - the Archive's thumbnails are JPEGs), `ETag` (blake2b of the bytes, as
  json_etag's) and `Cache-Control: private, max-age=604800` (a week: a front can change, so not immutable), a 304 with
  no body for an If-None-Match naming it (weak or strong, a list, or `*`); 404 when the Archive has no front; 502 when
  it couldn't be had; 504 when the Archive was too slow. Every failure `Cache-Control: no-store`, `detail` a short
  sentence (routes/coverart.py WORDS) - the phone draws the empty cover either way. Under GuardMedia's headers
  (nosniff, the sandbox, same-origin) and never gzipped: `/deadwax/coverart/` is in app.py MEDIA_PREFIXES.
- **The fetch** (src/api/coverart_endpoint.py `ArchiveFronts`, `archive_fronts`): its own httpx client beside
  CoverArtClient, `follow_redirects=False`, each hop followed by hand and checked by `on_the_archive()` - http or https,
  no port but the scheme's own, no user, the host `coverartarchive.org`, `archive.org` or a subdomain of
  `archive.org`; anything else refused and never asked (an address by number included, so nothing on the network
  deadwax runs in can be reached through it). At most FRONT_REDIRECTS (5) hops. Only an image type (MIME_EXTENSIONS)
  is passed on; a Content-Length past FRONT_MAX_BYTES (4 MB) is refused unread, a body read a piece at a time and
  refused as soon as it passes; an empty one refused. FRONT_DEADLINE_SECONDS (20) for the whole fetch, every hop and
  the body, and httpx's 10 s between pieces, 5 to connect. The agent is CoverArtClient's (the MusicBrainz one, with
  its contact, as the Archive asks - else `deadwax/<version>`). Three outcomes: a front, None (a 404 anywhere in the
  chain), or a failure - ArchiveDown (unreachable, 429, 5xx), ArchiveSlow (the deadline, an httpx timeout: the 504)
  or ArchiveRefused (this answer's own: an off-Archive redirect, not an image, too big, empty, another status, too
  many redirects).
- **The answers** (src/coverart_cache.py `CoverRelay`, one per app as `app.state.coverart`, made at the first ask):
  a kept cover from disk, at once; a 404 remembered MISS_SECONDS (five minutes) - brief, since one answer can't tell
  a missing cover from an outage (notes/tooling.md) - so a list of twenty albums with no art asks once, not on every
  scroll; a failure remembered FAILED_SECONDS (30) and answered as it was; and one that looks like an outage
  (ArchiveDown, ArchiveSlow) holds EVERY cover not kept for OUTAGE_SECONDS (30): a 502 at once, the Archive not
  asked, said once in deadwax's log at info level as the hold begins. An ArchiveRefused holds only its own cover.
  One fetch per cover however many ask at once (single flight); an ask waits ANSWER_SECONDS (7 - under the phone's
  8 s, URLSessionTransport.standardTimeout) and is a 504 after it, the fetch shielded so it carries on to its own
  deadline and its cover is kept for the next ask. A kept cover older than FRESH_SECONDS (30 days, by when it was
  fetched) is answered at once and fetched again behind it: a new one replaces it, a 404 drops it, a failure leaves
  it. A fault in deadwax while fetching is a 502 with its traceback in the log. The app's shutdown cancels the
  fetches under way and closes the client.
- **Bounded** (the review's, before it shipped): the first cut limited nothing in flight - a task per cover not kept,
  each holding up to 4 MB for up to 20 s and carrying on past its ask's 7 s answer - so a Search list of fifty asked
  archive.org fifty times at once, and anyone asking new mbids in a loop (with logins off, anyone on the network) could
  start hundreds. Now:
  - **FETCHING_AT_ONCE, 6** (a browser's own connections a host): an asyncio.Semaphore around `fronts.front()` alone,
    one per event loop. The wait for a turn isn't part of FRONT_DEADLINE_SECONDS - the deadline is the Archive's, not
    the queue's - and the ask's ANSWER_SECONDS still bounds what the phone waits: a cover queued past it is a 504,
    and kept for the next ask when its turn comes.
  - **PENDING_MAX, 64** (a Search list of fifty fits, queued six at a time): the fetches under way, running or waiting
    their turn. An ask that would start one more - a cover not kept and not already being fetched - is a 502 at
    once with nothing remembered (no failure, no outage hold), so it is asked as ever once they drain; said once in
    the log while full. An ask for a cover already being fetched joins it, full or not.
  - **A kept cover's refresh** is a fetch like any other: it takes a turn and counts against PENDING_MAX. The kept
    cover is answered at once either way; with no room, the refresh isn't started this time, and the next ask tries.
  - At about half a second a cover from the Archive (assumed - not timed from James's server), fifty take 4-5 s six
    at a time, inside the 7; slower than that, the last rows are 504s whose covers are kept for the next draw.
- **Where they're kept, and why there**: `deadwax-covers`, beside the player cache's `deadwax-player` - inside
  PLAYER_CACHE_PATH, else the container's temporary space - made private and checked by player_cache.open_folder()
  (its new `name` parameter), so the same rules hold: a real folder, deadwax's own, 0700, never a link; one that
  isn't is used for nothing, said once. Not the config volume, which people back up and these don't need; not the
  MusicBrainz file, which is JSON answers in SQLite; not inside `deadwax-player`, whose MP4s that cache counts and
  clears by rules of its own (and whose `_prepare` clears loose files). No setting of its own - PLAYER_CACHE_PATH
  moves both, and its row in Server settings and docs/configuration.md now say so. Files are named
  `<kind>_<mbid>_<size>.<ext>`, written to a `.part` and renamed into place, read with O_NOFOLLOW and refused unless
  a regular file under FRONT_MAX_BYTES.
- **The bound**: KEPT_MAX_BYTES, 128 MB - about 3,000 covers at 250 px (41 KB each, seen by hand) or 480 at 1200
  (268 KB). Past it the covers served longest ago go until the folder is under TRIM_TO (90%) of it, never the one
  just put; one bigger than the cap alone is answered and not kept, and none is written with less than
  player_cache.DISK_SPARE_BYTES free. Which was served when is kept in memory (`KeptCovers`, an OrderedDict under a
  threading.Lock, its disk work on worker threads through asyncio.to_thread); a start reads the folder ordered by
  each file's mtime, which is when it was fetched, clearing `.part` files ten minutes old.

### Decided here (the spec didn't say)

- **Lowercase only.** Every other route's MBID_PATTERN; Swift's `UUID().uuidString` is uppercase, so the app must
  send the mbid as MusicBrainz gave it (a string), not through `UUID`.
- **http allowed** on the Archive's hosts as well as https: every hop seen on 2026-11-14 was https, but a redirect
  to http on archive.org refused would be a missing cover for nothing, and only an image type is passed on.
- **The outage hold** is global and short: it makes the second wave of a list quick during an outage, at the price
  of a 30 s gap after one bad answer from the Archive's servers.
- **No troubleshooting entry yet**: nothing calls the route until the phone's slice 2, so no listener can see it
  fail; slice 2 should add one with what the phone shows. (It did: troubleshooting.md's "The iPhone app shows no
  cover for an album you don't have".)

### Verified, and not

- **pytest**: tests/test_coverart_relay.py, through start() with no lifespan and one event loop (as
  tests/test_autoeq.py), the Archive an httpx MockTransport shaped as the real one was seen (below); plus the route
  in tests/test_logins.py's ROUTES and a test there that a signed-out ask is a 401 with the Archive never asked (and
  a signed-in one answered), and the path in tests/test_media_headers.py. Eleven mutations tried by hand - redirect
  hosts unchecked, no shield, no outage hold, no miss memory, never trimmed, the declared length unchecked, no
  deadline, any type passed on, the disk never read, never refreshed, the cover just put trimmed - each fails a test.
  The caps (the review's): no more than six asked at once over twenty covers, a turn's wait outside the deadline
  (six covers, two turns, a deadline shorter than the queue), a 502 past the pending cap at once and asked
  normally after, and a refresh counted against both caps while its cover is served at once. Four more
  mutations - no turns, no pending cap, nothing counted as pending, ten turns - each fail a test.
- **By hand with curl, 2026-11-14** (not deadwax): `coverartarchive.org/release-group/b1392450-…/front-250` answers
  307 to `archive.org/download/mbid-30702389-…/mbid-30702389-…-43287476628_thumb250.jpg` (a release group's front
  goes straight to its release's image, not through a `/release/` address), which answers 302 (typed image/jpeg) to
  `dn720706.ca.archive.org/0/items/…`, which answers 200 image/jpeg, 41,268 bytes; the release's `front-1200` the same
  chain, 268,304 bytes; a release with no art (`00000000-0000-4000-8000-000000000000`) a 404 as text/html. All https.
- **Not seen**: deadwax itself has never asked the real Archive through this route - every answer it has read is the
  MockTransport's. How long the chain takes from James's server, what an outage really answers (a 503, a hang, a
  404), and the phone drawing them (slice 2) are unwatched.

## Phase 5, slice 2: albums you don't have (2026-11-14)

notes/ios-specs/phase5-search.md 2.7, 3.6 and 6.2, and questions 8 and 14-23 (6.6 points here). The second slice of
Phase 5: MusicBrainz's albums in Search's one list, after yours, with the web's moments - the list drawn in steps
and nothing moving under a finger - and the album you don't have, its pressings and tracklists, opening from them.
MusicBrainz's artists and songs are slice 3; what's saved and the kept answers slice 4; Get is Phase 6.

On `phase5-search` at `ios` d15bb82 (slice 1 merged, and main's 2.1.24, the Cover Art Archive relay, merged in). src/
__init__.py untouched; the app stays 0.10 (10); the .xcodeproj unchanged (the new files joined the synchronized App
folder). ROUTE_COUNT 41 -> 44: `/search_musicbrainz/fully_search`, `/search_musicbrainz/release_group` and
`/coverart/{kind}/{mbid}`, with `/store/album` taking `release_mbid` (question 15). It builds and runs against 2.1.23:
the covers' route answering an older server's 404 is the empty cover.

### Core (DeadwaxCore)

- **MusicBrainz.swift** (new): `ReleaseGroup` (id required, everything else lenient - a field of the wrong shape is
  absent), `FullySearchAnswer` (`release-groups`, `count`), `ReleaseGroupAnswer` (`{id, releases, problem}`) and its
  `PageRelease`s with their media and tracks, `Credits` (the credit as written, `sole`), `MBID.isOne` (the routes'
  MBID_PATTERN spelled out), `ArchiveCoverID` and its `Kind` (`release`, `release-group`).
- **SearchAlbums.swift** (new), searchResults.ts, idBridge.ts and artistPage.ts: `limit` (12, MUSICBRAINZ_LIMIT),
  a group's `year`, `kind` and section `word`; `held`, `place`, `yours`, `maybe`; `notInLibrary` and `heldUnlisted` (a
  held album never shows nowhere); `studioOrder`; `allAlbumsQuery` (an artist you have alone is their studio albums
  and EPs, never Various Artists); `heldInOrder` and `heldReleases` (the id bridge's order); `libraryArtist`
  (libraryArtistFor).
- **Pressings.swift** (new), pressings.ts and tracklistDiff.ts: each pressing's format, year, country, label and
  facts; the usual tracklist (`representative`) and the default; the picker's rows, its fold and its filter
  (`filterMin` 30, `filterWords`, `moreWords`); `summary`; the tracklist as the chosen pressing has it, each track's
  mark (Bonus, Other version, Renamed) and what it leaves out; `header`, `metaLine`, `holding`, `place`, `maybeLine`;
  `GroupPage` (the page as drawn from what is in hand); `KeptPressings` (the last 20 complete lists, a list with a
  problem never kept - question 20).
- **SearchList.swift**, slice 2's half of searchList.ts: the pool with MusicBrainz's albums (`SearchKindPool`:
  library, brought, musicbrainz), `sectionRows` and `lateRows` with both caps (3 of yours and 3 of MusicBrainz's, a
  phone's), the candidates' sources (yours 0, the collection's 1, MusicBrainz's 2), the phantoms and `decidedTop` (Top
  results decided before MusicBrainz lands, a place kept for the pick still to come), `decidedPrefix`; the moments -
  `sectionsReady`, `lateKinds`, `drawInOrFold`, `nextBehind` (Behind); a group's line; `MBFailure` (failureOf) and the
  words (`searching` with MusicBrainz in it, `allHeld`, `typeMore`, `studioNote`, `musicBrainz`, `failure`, `fold`,
  `empty`, `libraryLate`, `librarySkipped`, the hint's slice 2 words).
- **SearchReading.swift**: `typeFilter`, `asksMusicBrainzBySettling` (three UTF-16 units), `musicBrainzOnTyping`
  (clear, settle, drop, keep).
- **SearchState.swift**, the rest of Search.tsx's state: MusicBrainz's albums asked (`askingMusicBrainz`, its token,
  the studio clause, the fallback to the plain words), answered (`albumsAnswered`: the studio clause's in studio order,
  only the newest ask's) or failed; the run's moments (`advance` drawing Top results at the library's moment, the
  sections when they're ready or the cap passes, a late kind's slot drawn in or folded, `showFolded`); the late
  library (`libraryLateSlot`, `showLibrary`); Behind across runs (`noteBehind`); a kind view's MusicBrainz part below
  its own and its late clock (`kindView`, `kindLatePassed`); `resumed` (a paused search picking up).
- **Routes and the client**: the three routes; `fullySearch` asked with `releases=false` and `quick=true` (the web's
  Search's), `releaseGroup(mbid:)`, `archiveCover(_:size:ifNoneMatch:)` (a 200 as `.fresh`, a 304 as `.unchanged`,
  anything else nil), `navidromeAlbum(releaseMbid:)` and `navidromeAlbum(releases:)` (the first Navidrome has).
  `fullySearch` given 20 s and `releaseGroup` 60 s (question 22); `ArchiveCoverSize` row 250, hero 1200 (question 19).
- **export-search-albums-vectors.cjs** (new) compiles lib/searchList.ts, lib/pressings.ts, lib/idBridge.ts and
  lib/artistPage.ts with tsc, reads MUSICBRAINZ_LIMIT, OWNED_WAIT_MS and the all-failed foot's words from Search.tsx
  and PRESSINGS_KEPT from pressingLists.ts, and writes a second fixture, Fixtures/search/search-albums-vectors.json
  (1.3 MB, plain ASCII, seeded): the numbers (7) and words; typing (6 filters, 21 settling texts, 147 typing steps, 44
  readings' album queries); 21 groups; 5 folder lists' holding and 5 studio orders; every combination of the moments
  (48 ready, 16 late, 36 landing, 10 behind); 95 whole searches with MusicBrainz's albums in hand (the pool, every
  candidate, the phantoms, decidedTop, Top results with and without the prefix fixed, the sections capped and in full,
  a late answer's rows, every line); and 5 pressing lists (tests/fixtures/pressings/'s real groups and a made one) read
  as the page draws them, with 36 meta lines, the disc headings, the holding and the covers.
  **ui/test/iossearchalbums.sim.cjs** runs its `--check`.

### Where the phone can't follow the web exactly

- **Albums only** (question 14): the Artists and Songs views ask no MusicBrainz yet, so the moments wait on the albums
  alone, and a kind view's late clock is armed only for Albums.
- **The album you don't have** (questions 17 and 18): no description, no MusicBrainz links, no editors' sentence, and
  Get's place empty; the picker a sheet.
- **Offline** (question 21) is the phone's own: nothing of MusicBrainz's is drawn offline.
- **How long it waits** (question 22): the phone stops waiting before deadwax would on a hung connection.
- **Covers**: the relay's, never the Archive's own address (the web's `<img>` goes to coverartarchive.org).

### The app

- **SearchModel** gains MusicBrainz's half:
  - Typing: MusicBrainz asked 700 ms after typing pauses, only for words the reading says may (three letters, and
    `musicBrainzOnTyping`'s settle) and not asked already; under three letters the albums in hand are dropped; an empty
    box lets everything go (`letGo`: every task and clock cancelled).
  - The keyboard's Search: the library, a kind view's own and MusicBrainz asked at once, the words read again
    (`reread`), the late library's clock armed.
  - `askMusicBrainz`: the first query (the studio clause for an artist alone, or the plain words in the Albums view),
    then the plain words when a fielded read found nothing and the ask is still the newest; it waits up to 1.5 s for
    `/library/owned` (OWNED_WAIT_MS) so what you hold is known before the albums are placed; a failure as `MBFailure`.
  - The clocks: the sections' cap (RESULTS_WAIT_MS, 1.5 s after MusicBrainz is asked, once per run), the late
    library (LIBRARY_LATE_MS, 1.5 s), a kind view's late clock (once per words and kind).
  - `draw` advances the state, announces what it said ("In your library: …", then "Also found: 3 albums." or the
    failure's words), notes Behind and re-arms the cap.
  - `open(_ group:)`: a held album through the id bridge (question 16) - `heldReleases`, then
    `navidromeAlbum(releases:)` with the row's `opening` set; your album's page when found, else the album you don't
    have's.
  - `resumed()`: a search paused offline picks up - the library, the kind view, and MusicBrainz for words the pause
    would have asked.
- **SearchScreen**: the drawn list's moments - Top results with `TopPlace` (the place kept), "Searching…" where the
  sections will go, `DrawnSection` with its `SectionSlot` (Searching…, Show N more albums, nothing found, a short
  failure) and the studio line, `LibraryLateSlot` at the top (Searching your library…, Show N from your library,
  nothing found, skipped), the foot (`typeMore`, the all-failed `MusicBrainzFailure` with Try again and "What's in
  your library is above."); a kind view's MusicBrainz part below its own with its foot (`KindFoot`). Offline, every
  MusicBrainz row, slot and word is filtered out of a drawn list. A MusicBrainz album's row (`groupRow`): its
  `ArchiveCover`, its title and line; a spinner while it's opening yours; dimmed and inert offline.
- **GroupView** (new, `AppRoute.group` on Search's stack, `GroupRoute` carrying the row's group as its preview so the
  title and cover draw at once) and **GroupPageModel** (new): the hero cover (the chosen pressing's front, then the
  group's), the title, the credit (a link to your library's artist when one is theirs), the meta line with "maybe in
  your library" dashed, Pressing and its facts, Get's place (empty), the maybe sentence, then the summary and the
  tracklist with its disc headings and "Not on this pressing" - or Loading…, the trouble (Pressings.trouble for a 503
  or a problem, the listener's words for anything else, "That link isn't an album." for an id that isn't one) with
  Try again, or the offline line. The title moves into the bar once the hero scrolls away. Answers kept in
  `KeptPressings` for the session.
- **PressingPickerSheet** (new): the picker as a sheet (medium and large), each row ticked when chosen with its label,
  facts, compared note (amber when it differs) and "In your library"; the fold; the filter over 30 pressings, its words
  announced; Done.
- **ArchiveCover** (new) and **CoverCache.loadArchive**: a list of addresses tried in turn through the relay, each
  kept in the same memory cache as Navidrome's covers (`archive/<kind>/<mbid>` keys, never a Navidrome id's shape), a
  failure not asked again within a minute, never kept on the phone; the empty cover for anything but a front.

### Decided here (the spec was silent, or this departs from it)

Questions 14-23 in the spec, each built to its recommendation:
- 14, albums only;
- 15, three routes, not four;
- 16, a held album through the id bridge;
- 17, what the page leaves out;
- 18, the picker a sheet;
- 19, the cover sizes;
- 20, twenty pressing lists kept;
- 21, nothing of MusicBrainz offline;
- 22, how long the phone waits;
- 23, slice 1's stand-ins replaced by the web's.

And smaller ones, not worth a question:
- the timeouts held by the contract test above deadwax's own give-up while MusicBrainz is busy, not by a guess;
- no ETag sent for a cover yet, so the relay never answers the phone a 304 - the memory cache holds what it fetched,
  and `archiveCover` reads a 304 as `.unchanged` for when one is;
- the row's cover, like a library album's, hidden from VoiceOver (the row reads its title and line).

### Tests

- **SearchAlbumsVectorTests** (13): every vector of search-albums-vectors.json - the numbers and words, typing and the
  queries, a group's year, kind and credit, what is held, the studio order, the moments, every search with albums, and
  the pressings (each pressing, the usual tracklist and the default, the picker, each page with its summary, the
  page's words).
- **SearchAlbumsTests** (16), by hand: an album nobody has leading Top results once it lands; the cap drawing the
  sections with a slot; the studio clause's answer in studio order and its fallback's as MusicBrainz gave it; a late
  answer drawn in last, and one with nothing saying so; everything held said, a failure drawn with Try again (and
  busy only as a 503 says it); the late library's place and Show them; short words dropping the albums; a fielded read
  asking the plain words; the Albums view's MusicBrainz part below its own; the page drawn from what's in hand; a held
  album opening yours by its releases in order; twenty pressing lists kept, the newest last; MusicBrainz's answers read
  leniently; the client's three calls (asked quickly without pressings, the cover through deadwax and anything but a
  front nil, the id bridge release by release).
- **SearchTests** and **SearchVectorTests** (slice 1's) drawn through MusicBrainz's half: the albums answered at once
  with nothing, so the library's tests draw whole ("… Nothing more found.").
- **ClientTests**: `Routes.all` 44; `fullySearch` (20 s) and `releaseGroup` (60 s) among the routes given longer.
  **FixtureFiles**: the new fixture read from the checkout.
- **tests/test_ios_contract.py**: ROUTE_COUNT 44; five new tests - `/fully_search` asked as the web's Search asks it
  and its answer's keys FullySearchAnswer's; `/release_group`'s `{id, releases, problem}` and the MBID pattern; the
  relay's kinds and sizes the app sends within its Literals, and anything but a 200 nil; the timeouts above deadwax's
  give-up while MusicBrainz is busy (and the pressings' above the search's); a held album found by its release
  through `/store/album`.
- **Mutations**: 19, each applied alone with the four Search suites run. 16 were caught at first; the 3 that lived
  were closed and caught when run again:
  - 16, "leaves out" said "removes": no view the fixture asked chose a pressing that leaves a track out. Closed by
    each pressing's own summary in the fixture (`pages[].summary`, every clause met - adds, leaves out, renames,
    another version).
  - 17, busy read without a 503: no failure said busy on another status. Closed by a 500 saying `busy: true` - not
    busy, as failureOf reads it.
  - 18, the fallback's answer read in studio order: no test answered the plain words after the studio clause. Closed
    by `theStudioClausesAnswerIsInStudioOrderAndItsFallbacksAsMusicBrainzGaveIt`.

  The 19:
  1. the albums asked for 11, not 12;
  2. 19 pressing lists kept, not 20;
  3. a plain album said "Album" in a section;
  4. held albums not taken out of MusicBrainz's;
  5. a held album search3 listed brought in again;
  6. an artist's EPs before their albums;
  7. the pressing filter from 31, not 30;
  8. a pressing list with a problem kept;
  9. the sections drawn only once every kind is in (no cap);
  10. a late kind drawn in above a tappable foot;
  11. Behind ended by a superseded search;
  12. MusicBrainz asked by the pause from four letters;
  13. Top results decided past a phantom;
  14. the editors' sentence on the phone;
  15. "not in your library" left unsaid;
  16. "leaves out" said "removes";
  17. busy read without a 503;
  18. the fallback's answer read in studio order;
  19. a pressing asked for that the album hasn't, chosen.

### Verified, and not

Verified:
- `swift test`: Core 1468, Audio 158, Turntable 12 (FixtureFiles and the two album suites again after the new
  fixture joined FixtureFiles: 31). No new warnings.
- The unsigned Debug and Release device builds (Xcode, `generic/platform=iOS`): no warnings but the usual
  appintentsmetadataprocessor line; no change to the .xcodeproj (the four App files joined the synchronized folder).
- `check_project.py` ok.
- `npm run build` and all 85 sims on Node 22.23.4, iossearchalbums' `--check` among them.
- The full pytest suite: 4508 passed, 1 skipped (test_ios_contract's five new tests, and test_compose_example's docs rule, among
  them).
- The mutations above.

Not verified - only the phone can tell (docs/ios.md's checks 130-139, beside the spec's section 9):
- The moments' timing over WireGuard - 700 ms before MusicBrainz is asked, the 1.5 s cap, a late answer drawn in or
  folded - and that nothing moves under a finger as the albums land.
- The pressing picker's sheet, its filter (`.searchable` in a sheet's NavigationStack) and its detents on iOS 27.
- The covers through a real relay from the real Archive (the relay's notes: deadwax has never asked it), at both
  sizes; 2.1.23's 404 drawn as the empty cover.
- A held album opening yours through `/store/album?release_mbid=` against James's store index.
- VoiceOver's rows, the page's Pressing button and the picker's selected row; "Also found: 3 albums." announced.
- Offline's filtering of MusicBrainz's rows, and the page staying as it was.
- CI's Xcode 26.6 (the older Swift): the new code spells out its closures' types, as slice 1's.

## Phase 5, slice 2, after its review (2026-11-14)

The review of 2fc64f1 found three bugs in the app's wiring and one small one. All four are fixed in one commit on
`phase5-search`. Core gains one rule (`SearchState.libraryUnplaced`) and a test; the rest is the app's. The app stays
0.10 (10); no server change.

### What was wrong, and the fix

1. **Offline, new words went blank after a second and a half.** `settled()` armed the library's late clock with no
   online check, and the clock drew when it ran out. In Airplane Mode, "portishead" drew moment 1 with `libraryLate`
   set and an empty list (the offline filter takes MusicBrainz's part out). All then showed that blank DrawnList, not
   "Search works once deadwax is back.". Short words did the same through the whole branch. Once deadwax was back,
   `libraryLate` stayed set, so moment 2 left the person's own rows behind "Show N from your library". That undid
   slice 1's check 128.
   - **SearchModel**: `armLibraryLate()` returns while deadwax can't be reached, and the clock checks again before
     `libraryLatePassed`, so a clock running out offline is dropped. Offline, `advance` then draws nothing, and the
     offline line stands.
   - **`resumed()` arms the late clock whenever it asks the library.** It asks again after a failure or a skip
     (`state.resumed()`), or for the first time for words typed while away (`wantsLibrary`). It also arms the clock
     when the library is still out with no place kept for it (Core's `libraryUnplaced`): an ask in flight whose clock
     was dropped offline. The list is then drawn with the library, or a place for it, never without both.
2. **Slots grew when their answer landed.** `SectionSlot` and `LibraryLateSlot` had a 44 pt minimum height. A
   MusicBrainz failure (words over a button) or the library's FailureNote replaced a 44 pt asking line with 64-86 pt,
   and the sections below jumped.
   - **One fixed height, one row (the web's `.app-search-slot`)**:
     - `SlotFrame` holds 60 pt (`--app-search-slot`, 44 + 2 x 8) through a `@ScaledMetric(relativeTo: .body)`, so it
       holds at the accessibility sizes.
     - Everything in a slot is one line ending in "…": the asking line (`SlotAsking`, the sweep and its words), a
       Show button, its words, or a failure as one row (`SlotFailure`, the web's `is-row`). The failure's words fill
       the row and Try again sits at its end, with none for words MusicBrainz refused.
     - The library's failure says its listener's line (`ErrorWords.of(...).said`, the web's `late.message`). The raw
       detail an admin sees in a FailureNote has no room in a slot, and the web's slot has none either.
     - The all-failed foot and a kind view's foot are not slots, and keep MusicBrainzFailure.
3. **The id bridge's answer opened on whatever was showing when it landed.** `open(_ group:)` pushed with
   `navigation.open`, which appends to the current tab's stack, and only typing or a reset stood the ask down. While a
   held album's row spun (up to 8 s a release), tapping another row or switching to Library got the album page pushed
   over that page or into that tab.
   - **The answer opens only on the list it was tapped on**: `open` captures the tab and the Search stack at the tap.
     The answer opens only if both are unchanged and Now Playing isn't over them; otherwise it lets `opening` go and
     drops the answer.
   - **`standDown()`** (the web's, which lets its heldRequests go when the tab's root stops showing) cancels the ask.
     SearchScreen calls it when the tab changes away from Search, when the Search stack changes (a page pushed or
     popped), and when Now Playing opens.
4. **Covers stayed empty after coming back online.** CoverImage's and ArchiveCover's `.task(id:)` keys held nothing
   about reachability. A cover asked offline (short-circuited to the empty square) wasn't asked again until its key
   changed, even though `CoverCache.reach` had cleared the failure.
   - **The load's id adds `reachability.online`.** Reachability's `whenChanged` clears the failures before SwiftUI
     restarts the tasks, so a cover on screen asks once more as deadwax comes back. What is drawn stays under the key
     without it, so going offline never blanks a cover the view holds.
   - **The 60 s memory of an answer is kept.** `reach` used to forget every failure. CoverCache now marks the ones
     that were deadwax not reached (`unreached`): asked offline, or a transport failure (thrown by `archiveCover`, or
     anything but `APIFailure.answered` from `cover`). It forgets only those. A 404, or the relay's 502 or 504, keeps
     its minute. `forgetFailures()` (the app back to the front) still forgets all of them.

### Tests

- **SearchAlbumsTests** (+1, 17): `wordsTypedWhileDeadwaxIsAwayDrawNothingAndTheLibraryOnceBack`. Words typed with
  nothing asked draw nothing. Once back, `resumed()` has nothing failed to ask again, but the words want the library
  and have no place for it (`libraryUnplaced`). Asked and answered, the list is drawn with the library: no
  `libraryLate`, no late slot, "In your library: …" said. The contrast: a clock run out while away draws the list
  without the library, `libraryUnplaced` false (a place is kept), and the answer goes behind `.show(3)`.
- **Mutations**: 3, each applied alone with SearchAlbumsTests run, all caught:
  1. `libraryUnplaced` without its place clause;
  2. without its settled clause;
  3. always false.
- The model's wiring (the online guards, the stand-down, the tab and stack check), the slots' frame and the covers'
  ids have no test. They are the app's, untested off a phone, as every model and view is.

### Verified, and not

Verified, on the fixed tree before its commit:
- `swift test`: Core 1469, Audio 158, Turntable 12.
- The unsigned Debug and Release device builds: no warnings but the usual appintentsmetadataprocessor line; the
  .xcodeproj unchanged.
- `check_project.py` ok.
- `npm run build` and all 85 sims on Node 22.23.4.
- The full pytest suite: 4508 passed, 1 skipped.
- The 3 mutations above.

Not verified - only the phone can tell (docs/ios.md's checks 140-143):
- Typing in Airplane Mode keeps the offline line, and the library's rows are drawn in the list once back.
- The slots holding their height as their answer lands, at the largest text size too.
- A held album's row left before its answer, by another tab or another row.
- Covers loading in place once back online.

## Phase 5, slice 3: artists and songs from MusicBrainz (2026-11-14)

notes/ios-specs/phase5-search.md 6.3, and questions 9 and 24-27 (6.7 points here). The third slice of Phase 5:
MusicBrainz's artists and songs in Search's one list, after yours, through the moments slice 2 built; a song's
albums opening under it, and the album it names opening with the song marked; and a MusicBrainz artist's page.
What's saved, the kept answers and More from MusicBrainz are slice 4; Get is Phase 6; a description and links
Phase 7.

On `phase5-search` at `ios` b451241 (slice 2 and its review merged, and CI's type-checking fix). src/__init__.py
untouched; the app stays 0.10 (10); the .xcodeproj unchanged (the two new App files joined the synchronized folder).
ROUTE_COUNT 44 -> 48: `/search_musicbrainz/artists`, `/search_musicbrainz/songs`, `/search_musicbrainz/artist` and
`/search_musicbrainz/discography`, all on the server since before 2.1.23 - no server change.

### Core (DeadwaxCore)

- **SongSearch.swift** (new), songs.ts and searchQuery.ts' song queries:
  - `/songs`' answer read leniently: `SongSearchAnswer`, `MBRecording`, `MBRecordingRelease`, `MBRecordingMedium`,
    `MBRecordingTrack`.
  - The songs: `key` (songKey), `group` (groupSongs: every take of one title by one credit one `FoundSong`, its
    albums unioned and ordered so the studio album leads - `band`, `sortAlbums`), `bands` and `foldLabel` (the
    disclosure: the albums listed, the rest folded, "On 11 compilations, live albums and soundtracks").
  - What's held: `holding` (songAlbumHolding: a pressing the song was found on, one whose kept tracklist has it, one
    the library's own search shows it on, and one nothing vouches for), `held`, `heldReleases` (the id bridge's
    order), `heldWords`, `albumWords`, `namedAlbum` (the first album you have the song on, yours before the
    collection's, else the first it's on), `albumLine`. `SongEvidence` is the web's `evidence`: the library half's
    songs, and the album pressings the session keeps.
  - The album opened from a song: `ids` (songIds - lowercase MBIDs, each once, at most 8), `matcher` (songMatcher:
    one of its recordings, or a track titled as one of those is), `pressing` (songPressing).
  - The queries: `query` (songSearchQuery - nothing for an artist's name alone), `titleQuery` (songTitleQuery, the
    fallback), `fieldedQuery`. `limit` 25, `rowsShown` 3, `idsKept` 8.
  - The words: `needATitle`, `noRelease`, `songWords`; `disclosureHint` and `foldHint` (the phone's own, question
    25).
- **MBArtist.swift** (new): `MBArtistSearch.limit` (10), `ArtistSearchAnswer`, `MBArtistFacts` (the fields the line
  reads), `DiscographyAnswer` (`brokenOff` when `problem` is said: never their albums); `MBArtistPage` - artistPage.ts
  for a MusicBrainz artist alone: `rows` (artistRows([], groups, index): each group once, newest year first, the
  undated last, then by folded title in localeCompare's order), `line` (rowLine), `marked`, `asksBridge` (openRow),
  `factsLine`; `kept` (20, ARTISTS_KEPT) and ArtistPage.tsx's words.
- **Collation.swift** (new): `WebCollation.compare`, JavaScript's `localeCompare` as ICU's root collation answers it
  - letters first with accents and case away, then accents, then case lowercase first, punctuation weighed in ICU's
  order before digits and letters. Linux has no ICU tables, so it's an approximation, built from what Node's ICU
  answers for the characters titles carry; the fixture's 364 titles and 600 seeded pairs hold it. songs.ts sorts an
  album's pressings, and artistPage.ts an artist's albums, by localeCompare: a bootleg's "1984-09-24" stands before
  "1984‐09‐15" there because a hyphen-minus weighs less than a hyphen, which no code-point order gets.
- **MusicBrainz.swift**: `MBArtistMatch` (artist_match less its score, read leniently) and its `line` ("as Kanye
  West", disambiguation, type, country).
- **SearchList.swift**, slice 3's half of searchList.ts: the rows `.mbArtist`, `.mbSong` and `.songAlbum`; the pool
  with MusicBrainz's artists and songs - `newArtists` (a library artist answering to a match, by its MusicBrainz id or
  by a name only one match answers to, brought in - never drawn twice) and `newSongs` (a song whose title and credit
  are a library song's dropped; one held on an album it's on brought in); their candidates, Top results' relatives and
  `decidedTop` over three kinds; `sectionRows` with both caps for each kind; every new row's line; `hasAside`.
- **SearchState.swift**: MusicBrainz's three kinds, each its own `Answer` (`albums`, `artists`, `songs`: idle,
  searching, done or failed, only the newest ask's): `wantedKinds` and `keyFor` (the web's - artists not asked under the
  album-by-artist reading, songs not for an artist's name alone); `askingMusicBrainz` returns `MusicBrainzAsks`, one
  ask a kind not in hand or on its way (the songs' with its fallback, the box's words as one title, for a title beside
  an artist); `artistsAnswered`, `songsAnswered` (the recordings made songs) and their failures; `failure(of:)`; the
  moments over the kinds asked. A kind view asks its own kind (the Songs view under an artist's name alone says
  `needATitle`).
- **Pressings.swift**: the album opened from a song - `GroupPage` takes `song` (the recording ids) and a
  `fallbackTitle` (drawn while the pressings load: the route carries the album's title, no preview); the default
  pressing is one with the song (`SongSearch.pressing`), and `trackRows` marks its tracks (`song`). `KeptPressings`
  gives the session's releases by album, for `SongEvidence`.
- **Routes and the client**: the four routes; `searchArtists` (`name`, `limit`), `searchSongs` (`query`, `limit`),
  `artistFacts(mbid:)` and `discography(mbid:studioOnly:)` (`types=album`, `studio_only=true` with Studio only).
  `/artists` and `/songs` given 20 s; `/artist` and `/discography` 60 s (question 27).
- **export-search-songs-vectors.cjs** (new) compiles lib/searchList.ts, lib/songs.ts, lib/artistPage.ts,
  lib/pressings.ts and lib/idBridge.ts with tsc, reads noReleaseWords from Search.tsx, SONG_WORDS from
  ReleaseGroupPage.tsx and ARTISTS_KEPT and the discography's words from ArtistPage.tsx, and writes a third fixture,
  Fixtures/search/search-songs-vectors.json (2.4 MB, plain ASCII, seeded): the numbers (5) and words; 76 readings'
  song queries; the 7 recorded song searches in tests/fixtures/songs/ grouped (each recording's key, the songs in
  full, their bands and folds); every album's holding over 5 to 7 folder lists and 4 kinds of evidence (the last list, the song's first album the
  collection's alone and a later one yours, added for mutation 17); The Slow Rush's
  pressings opened from a song (tests/fixtures/songs/slow-rush-pressings.json: ids, matcher, pressing, the tracks
  marked); 68 whole searches with MusicBrainz's artists, albums and songs in hand (23 worked, 45 seeded: the pool,
  Top results, the sections, every line, every song's disclosure); 16 artist pages and 8 facts lines; and
  localeCompare over 364 titles and 600 pairs. **ui/test/iossearchsongs.sim.cjs** runs its `--check`.

### Where the phone can't follow the web exactly

- **A MusicBrainz artist's page** (question 9): their albums only - no description, links, Play or Navidrome albums
  merged in; Studio only a button at the heading's end.
- **Their rows before the library answers** (question 26): drawn as the discography lands, the library's words filling
  in place, where the web waits up to 1.5 s.
- **Offline** (question 24): the artist page's albums not drawn.
- **VoiceOver's disclosure** (question 25): hints, where the web has `aria-expanded`.
- **localeCompare**: WebCollation is ICU's order as far as the recorded answers and the seeded titles reach; two
  titles in another script tying on everything before them could stand in another order than the web's. (Its tables
  are made from ICU since the review - "Phase 5, slice 3, after its review" says what it still can't follow.)

### The app

- **SearchModel** gains the artists and songs:
  - `askMusicBrainz` sends each ask `askingMusicBrainz` returns - `askAlbums`, `askArtists`, `askSongs` - each
    waiting up to 1.5 s for `/library/owned` before it draws, as the albums do. `askSongs` asks the fallback (the
    words as one title) when a title beside an artist found no recording, the ask still the newest, and closes
    every song's albums and fold as an answer lands.
  - `marks` carries `evidence`: All's search3 songs and `GroupPageModel.keptReleases`.
  - `openSongAlbum` (Search.tsx's openSongAlbum, in its order): a pressing the song was found on, or whose kept
    tracklist has it - yours through the id bridge, the row busy; a pressing the library's own search shows it on -
    that album, at once; only a pressing nothing vouches for, its pressings not kept - they are asked (busy) and kept
    for the page, then the bridge if a held pressing has the song; else the album you don't have (`GroupRoute(album)`,
    its title and the song's recording ids). It runs on `askingHeld`, so `standDown()` covers it, and opens only on
    the list it was tapped on (the tab, the Search stack, Now Playing not over it, the same epoch).
  - `openArtist` pushes `AppRoute.mbArtist`; `toggleSong` and `toggleFold` keep which songs are open.
  - `letGo` and the `drop` effect cancel all three asks and close every song.
- **SearchScreen**: a MusicBrainz artist's row (its line, a chevron; dimmed and inert offline); a MusicBrainz song's
  row in a section as `SongDisclosure` - its title and line, a chevron turning as it opens onto `SongAlbumRow`s (a
  36 pt cover through the relay, `albumLine`, busy while the bridge is asked), the fold's button or caption, the hints
  for VoiceOver; in Top results a song's row opens its named album. `KindFoot` says `needATitle`; `SectionSlot`
  reads each kind's failure (`failure(of:)`).
- **Routes**: `AppRoute.mbArtist(MBArtistRoute)` (mbid, name); `GroupRoute` gains `title` and `song` (`init(_ album:
  SongAlbum)`), so the album opened from a song draws its title at once and marks the song.
- **GroupView**: `GroupPage` given the route's title and song; the pick rule keeps any pick on a page opened from a
  song (the default chosen again would otherwise hand the choice back to the song); the song's tracks tinted
  (`Palette.pressed`, a 3 pt accent bar, an 8 pt bleed - app.css's `--app-rg-mark-bleed` and `--app-song-bar`), its
  title in the accent, ", the song you searched for" for VoiceOver alone; brought into view once, as first drawn,
  only while the page is the one shown and not scrolled (`ScrollViewReader`, the least scroll - the web's
  `scrollIntoView({block: 'nearest'})`). The credit opens the library artist's page, else (one MusicBrainz artist
  credited) their MusicBrainz page, else words.
- **MBArtistModel** (new) and **MBArtistView** (new): `load` asks the facts and the albums together; `browse` - the
  session's at once (unless Try again), else `/discography`, `brokenOff` or a 503 said as `MBArtistPage.away`, any
  other failure in a listener's words with Try again; a re-browse keeps the last answer on screen, and a failure keeps
  it only when it answered the same question; facts that fail leave the line out. Studio only on unless turned off,
  kept per artist; the session keeps 20 artists' facts, albums and Studio only (the oldest let go). A row's tap:
  `asksBridge` - the id bridge, the row busy, opening yours only on the page it was tapped on (the tab, its stack, Now
  Playing not over it) - else the album you don't have; `standDown()` on another tab, Now Playing, or the page
  leaving. The hero's facts line is held with a space while it loads; the rows are one line each, so nothing below
  moves as an answer lands. Offline: the hero, and "Their albums show once deadwax is back." - asked again as deadwax
  comes back.

### Decided here (the spec was silent, or this departs from it)

Question 9 built to its recommendation (a MusicBrainz artist's page, their albums alone), and questions 24-27 in the
spec, each built to its recommendation:
- 24, nothing of their albums offline;
- 25, the disclosure's hints for VoiceOver;
- 26, rows drawn as the discography lands;
- 27, how long the phone waits for the four routes.

And smaller ones, not worth a question:
- `/artist`'s timeout raised from 20 s to 60 s while writing the contract test: get_artist takes deadwax's ten
  attempts (no search patience), 3 s apart on a 503, which 20 s would give up before;
- the album a song names opens with its title and no preview, as the web's `{id, title}` does - the cover and
  credit come with the pressings;
- an album Search's `openSongAlbum` fetched is kept in `KeptPressings` for its page, so the page draws at once;
- the song's tint and bar are the web's `.is-song` sizes, under the phone's own palette.

### Tests

- **SearchSongsVectorTests** (10): every vector of search-songs-vectors.json - the numbers and words, the queries,
  titles and bands, the recorded songs grouped, the holding, the pressings opened from a song, every whole search,
  the artist pages and facts lines, and the collation (each title's place, each pair's sign).
- **SearchSongsTests** (8), by hand: each kind asked by the reading (artists not under album-by-artist, songs not for
  a name alone, the fallback only for a title beside an artist); an answer keeping what was asked and an older one
  dropped; the Artists view bringing in the library's artist once and MusicBrainz's others below; the Songs view
  saying it can't ask (`needATitle`) and what it found nothing of (`noRelease` beside a library song, "No songs for"
  with none); the album opened from a song showing a pressing with it and marking it; a MusicBrainz artist's page
  listing their albums newest first with what's held; the answers read leniently; the four calls asked as the web
  asks them (the query items, the timeouts, a 503 an `APIFailure`).
- **SearchTests** and **SearchVectorTests** answer every kind asked with nothing (`answerEmpty`), so the earlier
  slices' tests draw whole with three kinds asked; **SearchAlbumsTests** answers the artists and songs so, its
  every-kind-failed test failing the artists too, and what each view asks is slice 3's (an artist's name: their
  albums and artists, no songs).
- **ClientTests**: `Routes.all` 48; the four among the routes given longer. **FixtureFiles**: the new fixture read
  from the checkout.
- **tests/test_ios_contract.py**: ROUTE_COUNT 48; four new tests - `/artists` and `/songs` asked within their bounds
  with the server's own page sizes, the name within `/artists`' and the longest song query the box can make (4 x 200
  + 45) within `/songs`'; their answers' keys (ArtistSearchAnswer, MBArtistMatch less `score`, SongSearchAnswer) and a
  recording's fields within what MusicBrainz's recorded answers carry; `/artist`'s fields within ARTIST_FACT_FIELDS
  and `/discography` asked with `types=album` and `studio_only`, its every answer carrying `release-groups`,
  `truncated` and `problem`; the timeouts above deadwax's own waits (the searches' patience, `/artist`'s ten 3 s
  pauses, the discography's five pages as the pressings').
- **Mutations**: 18, each applied alone with the six Search suites run (ios/DeadwaxKit's `--filter Search`). 16 were
  caught at first; the 2 that lived were closed and caught when run again:
  - 5, the tick only for yours even without a library of your own: the tick's rule is ArtistPage.tsx's, a
    component the exporter doesn't compile, and no by-hand row was held by the collection alone. Closed in
    `aMusicBrainzArtistsPageListsTheirAlbumsNewestFirstWithWhatIsHeld` (ticked without a library of your own, not
    with one, "in the collection").
  - 17, the named album not yours first: no folder list held the song's first album by the collection alone and a
    later one by you. Closed by that list in the exporter (the fixture regenerated; 122 cases then failed).

  The 18:
  1. the song search asks 24, not 25;
  2. 19 artist pages kept, not 20;
  3. an address keeps 7 recording ids;
  4. an artist's albums oldest first;
  5. the tick only for yours, even without a library of your own;
  6. an ended artist said "since";
  7. a library artist matched by name alone never brought in;
  8. a song you have drawn again from MusicBrainz;
  9. "a pressing" left out of an album held without the song;
  10. artists asked under album-by-artist;
  11. songs asked for an artist's name alone;
  12. a hyphen weighed before a hyphen-minus (WebCollation);
  13. the fielded song query without `artistname`;
  14. no fallback to the title alone;
  15. the song never marked on its album;
  16. the fold always plural;
  17. the named album not yours first;
  18. an album heard holding the song said as only a pressing.

### Verified, and not

Verified, on the tree before its commit:
- `swift test`: Core 1487, Audio 158, Turntable 12. No new warnings.
- The unsigned Debug and Release device builds (Xcode, `generic/platform=iOS`): no warnings but the usual
  appintentsmetadataprocessor line; the .xcodeproj unchanged (MBArtistModel and MBArtistView joined the
  synchronized folder).
- `check_project.py` ok.
- `npm run build` and all 86 sims on Node 22.23.4, iossearchsongs' `--check` among them.
- The full pytest suite: 4516 passed, 1 skipped (test_ios_contract's four new tests and the four new routes' parameter
  checks among them, and test_compose_example's docs rule).
- The 18 mutations above, the 2 that lived closed and caught.

Not verified - only the phone can tell (docs/ios.md's checks 144-155, beside the spec's section 9):
- The rows' timing over WireGuard with three kinds asked: the artists and songs landing in their slots, nothing moving.
- A song's disclosure opening and folding in a LazyVStack, and the album page bringing the song into view
  (`ScrollViewReader` in a lazy stack, a 50 ms wait for the layout).
- `Toggle` in `.button` style as Studio only, and how VoiceOver reads it.
- The id bridge from a song's album and from an artist page's row against James's store index; `/release_group` asked
  first for a song only a pressing nothing vouches for is on.
- `/artists`, `/songs`, `/artist` and `/discography` against real MusicBrainz through deadwax (the contract test reads
  the server's code; the recorded answers are MusicBrainz's own, from the web's work).
- WebCollation against ICU for titles outside the recorded answers.
- CI's Xcode 26.6 (the older Swift): the new code spells out its closures' types and keeps each `#expect` small.

## Phase 5, slice 3, after its review (2026-11-14)

The review of 9a38566 found nothing high or medium, and three low findings. All three are fixed in one commit on
`phase5-search`. The app stays 0.10 (10); no server change. Not fixed, as asked: the Songs view's "none is on an
album yet" when every MusicBrainz song was dropped as yours. It is Search.tsx's `kindView` word for word, and the
phone keeps the web's wording.

### What was wrong, and the fix

1. **The song was never brought into view if its tracks first drew while the page wasn't shown.** `showSong` set
   `songShown` before its "is this page shown" guard. So: open a song's album (`/release_group` loading), switch to
   Library, the pressings land, come back to Search - the page never scrolled to the song.
   - **GroupView**: `songShown` is set only once the page is the one shown (`isShown`: the top of the tab shown's
     stack, Now Playing not over it), as ReleaseGroupPage's `shown` does. `showSong` is called again as the page
     shows: `.onAppear`, a change of `navigation.tab`, and Now Playing closing.
   - The scrolled check stays inside the 50 ms wait, so it reads the hero's own `onAppear` after the page comes
     back: a page scrolled before it left is still left where it is.
2. **A MusicBrainz artist's facts line could grow from one line to two.** The placeholder was `" "` but the line was
   `lineLimit(2)`, so at large Dynamic Type the albums moved down when the facts landed. That contradicted question
   26's "nothing moves".
   - **MBArtistView**: `lineLimit(2, reservesSpace: true)`. The web's `.app-artist-facts` wraps freely, so two lines
     held matches its line better than one truncated.
3. **WebCollation ordered some titles differently from ICU.** The reviewer ran 208 awkward titles against Node's
   `Intl.Collator('en-US')` and got 792 disagreeing ordered pairs. The causes were kana by code point, the modifier
   letters as letters, ə and ŧ after z, punctuation the table didn't list after every symbol, currency before the
   other symbols, and ™ against "TM".
   - **The tables are now made from ICU**, by **ios/scripts/collation-tables.cjs** (new), written between
     Collation.swift's `BEGIN collation-tables.cjs` and `END` lines:
     - `variables`: 1,880 punctuation and symbols in ICU's order, with their ties. Most are from ASCII, Latin-1,
       the modifier letters, general punctuation, letterlike symbols, arrows, maths, box drawing, shapes, dingbats
       and CJK's; every currency sign is included. Punctuation runs up to "`", symbols up to "¤", then currency.
     - `unlistedSymbolsBefore`: where an emoji stands. ICU puts every symbol the table doesn't list after its own
       symbols but before CJK's symbols and the modifier letters it weighs as symbols (ː, ゝ, ー).
     - `marks`: ICU's order at the second level, with their ties.
     - `letterPlaces`: each Latin letter beyond a-z, placed after the letter ICU puts it after.
     - `variants`: ø, đ, ð, ł, ħ and the rest. Each is its letter plus a mark of its own, placed among the marks.
     - `middleDotAfterL`: ICU weighs "l·" as an l with a mark, and so ŀ.
     - `markLetters`: the combining letters, weighed as their letter a level down ("t" < "tͭ" < "T").
     - `numbers`: ❽, ⓰, 〨 and the rest, weighed as the digits of their value a level down.
     - `scriptLetters`: Greek, Cyrillic, Georgian, Armenian, Hebrew and Arabic's letters, in ICU's order.
     - `contractions`: й, and Arabic's alef with a hamza or madda, which ICU weighs as letters of their own though
       they decompose.
     - `ignorableMarks`: the combining grapheme joiner and the like.
   - **Collation.swift**:
     - The first level is in bands in ICU's order: punctuation, symbols, the last symbols, currency, digits, Latin,
       the other alphabets, Hangul's jamo, kana, Bopomofo, Yi, Han. In each band, a character a table lists goes by
       its rank there, and any other by code point after them.
     - A string is decomposed canonically first, so a character the same as another is weighed as that one (Greek's
       oxia as ´), and contractions are read from that.
     - **Kana**: hiragana and katakana are alike at the first level, and a small kana is weighed as its letter. At
       the third level the order is small hiragana, hiragana, small katakana, katakana, then halfwidth ("カタカナ" <
       "きた", "ぁ" < "あ" < "ァ" < "ア" < "ｱ").
     - **A compatibility symbol's parts** take their own case at the third level, so "tm" < "tM" < "Tm" < "TM" <
       "™".
     - **Greek's final sigma** is its sigma a level down ("σ" < "Σ" < "ς" < "σa").
     - Unchanged: æ, œ and ß as their two letters (ß as "ss") with a mark of their own, and the digits by value.
   - **The generator's `--check`** makes the tables again and compares them with Collation.swift, but only when
     this Node's ICU is the one the tables were made with (78.3, Node 22.23.4). Another ICU would make other tables,
     not wrong ones, so then it says which ICU and passes. **ui/test/iossearchsongs.sim.cjs** runs it beside the
     exporter's `--check`.
   - **The exporter's collation list** gains 100 titles, one or more with each of these characters. The list is now
     464 titles and 600 seeded pairs (only the fixture's `collation` vector changed).
     - From the review: kana, the modifier letters (Hawaiʻi beside Hawai'i, Hawai’i and Hawaii), ə and ŧ, CJK's
       brackets and ⁄, currency against ♥ ☆ ♫ ✓, and ™ against TM, Tm, tM.
     - From what the measuring below found: final sigma, й ("йа" beside "иб"), Catalan's l·l, ❽ and 〨, a combining
       letter, emoji, Hangul beside Ethiopic and Khmer, and "Don't Stop" beside "Don’s Song" (an apostrophe and a
       right quote tie at the first level).
     - The vectors made under ICU 74.2 (Node 20) come out the same as under 78.3.

### Measured against ICU

The reviewer's 208 titles weren't kept, so the measuring here used a Swift harness: Collation.swift compiled with a
small main, run over every ordered pair of titles against Node 22's `Intl.Collator('en-US')` signs.

| titles | old disagreements | new disagreements |
| --- | --- | --- |
| 962 awkward titles: each of the review's characters, alone, after "a", before "a" and inside "x…y", among Latin variants, quotes, dashes, symbols, currency, scripts and digits | 62,630 of 925,444 | 52 |
| 800 random strings of 1 to 4 characters, over Latin, punctuation, symbols, emoji, other alphabets, kana, Hangul, Han, marks and modifier letters | 16,148 of 640,000 | 8 |
| 700 random strings over Latin, punctuation, marks and modifier letters | 55,806 of 490,000 | 24 |
| 700 random strings over other alphabets, CJK and symbols | 5,614 of 490,000 | 42 |
| 700 random strings over the whole pool, another seed | 11,086 of 490,000 | 232 |
| the fixture's own 464 titles, every pair | 454 misplaced in the sorted list | 0 |

### What it still can't follow, and why

- **Han beyond its first block.** ICU orders Han by radical and stroke count. Extension A (㐀) and B (𠀀) interleave
  with the core block, and the core block itself strays from code-point order in about 0.6% of pairs. Matching that
  would take Unihan's radical-stroke data for 98,000 characters; even as runs it is thousands of entries. So Han
  stays in code-point order. All of the 52 left in the first measure are this.
- **Bopomofo's later letters** (ㄪ, ㄫ, ㄬ) stand by their phonetic place in ICU, not by code point.
- **Scripts the tables don't list**, such as Thai, Devanagari, Ethiopic, Khmer and Cherokee, stand after the listed
  alphabets by code point. That keeps them between Arabic and Hangul as ICU does, but not always in ICU's order among
  themselves.
  - Devanagari's and Bengali's vowel signs are weighed as marks, where ICU gives them letters' weights.
  - Thai's and Lao's prevowels are not swapped with the consonant after them.
- **Symbols outside the table's blocks**, such as Cyrillic's ҂ and some musical and technical ones, go after the
  listed symbols with the emoji. ICU spreads them through its symbols.
- **The finer third-level steps.** Halfwidth small kana tie with halfwidth kana ("ｫ" against "ｵ").
- **Numbers outside the table's blocks** that ICU weighs as their own (𝍠, ↀ) stand as symbols.
- **The rare letters that expand** (ʣ for "dz", ỻ for "ll") are placed as one letter, so a word continuing past them
  can stand on the wrong side.
- **A string of marks alone** (no letter under them) ties where ICU orders the marks.

None of these reaches the recorded answers or the fixture's titles.

### Tests

- **SearchSongsVectorTests**' collation test holds the 464 titles' order and the 600 pairs (the fixture
  regenerated).
- **Mutations**: 19 on the new collation, each applied alone to a copy of Collation.swift and compiled with the
  test's harness (the fixture's sorted titles and pairs). 16 were caught at first. The 3 that lived were closed by
  titles added to the exporter, and caught when run again:
  - no contractions, closed by "йа" and "иб";
  - the quote ties given primaries of their own, closed by "Don't Stop" and "Don’s Song";
  - Hangul among the other scripts, closed by Ethiopic's ሀ and Khmer's ក.

  The 19:
  1. katakana not as hiragana;
  2. katakana before hiragana at the third level;
  3. small kana not as their letter;
  4. emoji after the last symbols;
  5. a symbol's parts all lowercase;
  6. no contractions;
  7. no l·;
  8. final sigma by code point;
  9. the combining letters as marks;
  10. the numbers as symbols;
  11. the other alphabets by code point;
  12. the Latin places ignored;
  13. the variants without their mark;
  14. the quote ties given primaries of their own;
  15. the quote ties the same at the second level;
  16. the marks unranked;
  17. no canonical decomposition first;
  18. Hangul among the other scripts;
  19. Han among the other scripts.

### Verified, and not

Verified, on the tree before its commit:
- `swift test`: Core 1487, Audio 158, Turntable 12. No warnings.
- The unsigned Debug and Release device builds: no warnings; the .xcodeproj unchanged (collation-tables.cjs is a
  script, not in the project).
- `check_project.py` ok.
- `npm run build` and all 86 sims on Node 22.23.4 (ICU 78.3), iossearchsongs running both `--check`s. Under Node 20
  (ICU 74.2) the exporter's vectors came out the same, and the tables' check said which ICU and passed.
- The full pytest suite: 4516 passed, 1 skipped.
- The 19 mutations above, the 3 that lived closed and caught.

Not verified - only the phone can tell (docs/ios.md's checks 144 and 149 gain a sentence each):
- The song brought into view on coming back to the tab. The 50 ms wait has to cover the hero's `onAppear`.
- The facts line's two lines held at the largest text size.

## Phase 5, slice 4: what's saved, the kept answers, More from MusicBrainz, the app as 0.11 (2026-11-14)

notes/ios-specs/phase5-search.md 5.1 and 6.4, and questions 28-33 (6.8 points here). The last slice of Phase 5.
Before it, the phone asked MusicBrainz afresh for every search: words searched a minute before waited for it again,
and what deadwax had saved of MusicBrainz's earlier answers - for anyone's search - wasn't drawn until MusicBrainz
answered. A kind view had no way past MusicBrainz's first page. Now:
- what's saved is drawn at the library's moment, and MusicBrainz's answer adds only what isn't there;
- the session's last 24 answers are used with no request;
- a kind view pages on with More from MusicBrainz.

Get is Phase 6; a description and links Phase 7.

On `phase5-search` at `ios` 540cfcc (slice 3 and its review merged). src/__init__.py untouched. The app is **0.11
(11)**: Base.xcconfig, check_project.py, ios.yml, test_ios_install.py, YouView's comment, ios/README.md, docs/ios.md
and the README pinned to it, as 0.10 was. The .xcodeproj is unchanged (no new App files). ROUTE_COUNT 48 -> 49:
`/search_musicbrainz/saved`, on the server since 2.0.0-player.56. There is no server change.

### Core (DeadwaxCore)

- **SearchSaved.swift** (new), slice 4's half of searchList.ts, searchResults.ts, songs.ts and app/searchAnswers.ts:
  - **What's saved.**
    - `SavedSearchAnswer` reads `/saved`'s answer leniently (`looseField`): a kind missing or of the wrong shape is
      none, and a missing `available` means nothing was searched.
    - `SavedFound` is the answer in hand, its songs grouped as they land.
    - `SearchSaved`:
      - `waitMs` 400 (SAVED_WAIT_MS);
      - `artistAlbums` 12;
      - `studioGroup`;
      - `savedFor`, what's saved for a view's reading: artists, albums and songs for the kinds the view asks. For an
        artist's name alone, their credited albums in studio order, at most 12. The studio's alone where the web's
        studio query asks. Held albums are left out as they're drawn, never as they land.
  - **A kind view's rows kept in place.** `KindArea.arrange` (kindArea) keeps, by key, what a kind view drew below its
    library's rows, and as what (saved or MusicBrainz's): each row stays where it was first drawn, and new rows go
    below it. After a failure or a MusicBrainz row, what's saved lands below too, never above what's there.
  - **The kept answers.** `KeptSearchAnswer` and `SearchAnswersKept`:
    - `count` 24, `keep` (delete then set, so the oldest goes first);
    - keys of route, words and page size (`albumsKey`, `artistsKey`, `songsKey`);
    - `albums(ask)` and `songs(ask)`: an answer kept for the first query, else, when that one found nothing, for its
      fallback. A fielded reading needs both kept.
  - **More.** `SearchMore`:
    - `offsetMax` 1000 (FULLY_SEARCH_OFFSET_MAX);
    - `pages` (morePages: `.more`, `.end`, or `.far` past the furthest offset);
    - `appendPage` (the groups not already got, the held left out as the first page leaves them);
    - `pageWords` (morePageWords, "in the collection" with a library of your own);
    - `artistsSaid` (the page's own count);
    - `appendSongs` (every page regrouped, the songs drawn kept in their places, a later take adding its albums in
      place) and `songsWords`;
    - `button`, `far`.
  - **The words.** `SearchWords.saved` ("Found earlier: 1 album."), `savedAwaySaid`, `musicBrainz(_:answered:saved:)`
    ("More found: …" under what's saved), `savedAway` (MusicBrainz's failure under what's saved: "Showing earlier
    results…", a refusal's own words as ever) and `nothingMore`.
- **SearchList.swift**:
  - The pool takes `saved` (a `SavedAnswer`). Its blocks are what's saved first, then MusicBrainz's answer less
    what's saved. Artists are read as one list by `newArtists`, so a library artist is brought in once. Each
    `SearchPlaced` says whether it is from what's saved.
  - Candidates carry `saved`, ranked at `Source.saved`. `familyMarked` marks a family's rows as saved with their
    row. A song's named album counts too, when it is a group of what's saved.
  - `decidedTop` and `topResults` say which picks are saved (`savedPicks`).
  - `sectionRows` and `lateRows` lead MusicBrainz's rows with what's saved. A late slot adds only what isn't drawn
    above it already.
  - The drawn list carries what's saved as key sets: `Section.saved` and `holdsSaved`, and `Drawn.topSaved`. That way
    a late answer knows what it adds to, and the words know what to say.
- **SearchState.swift**:
  - **What's saved.** `Saved` (idle, asking, done, none). `askingSaved` asks once per words. `savedAnswered` and
    `savedFailed` act only on the newest ask. `savedGaveUp` lets the answer go past `waitMs`. `savedSettled` is what
    the library's moment waits on. `savedOf` gives what's saved for a view's reading, only once MusicBrainz is for
    the words.
  - **The moments.** The first draw waits for `savedSettled` beside the library. What's saved is drawn in its
    sections and Top results. MusicBrainz's answer then adds only what isn't there, and its words say so: "Found
    earlier: …" with the first draw, "More found: …" or "Nothing more found." with the answer. Every kind failing
    under what's saved says these are earlier results.
  - **`takeKept`** takes every kind the view would ask that a kept answer holds, with no request. Its words must be
    asked for, or ask by settling.
  - **More.** `askingMoreMusicBrainz` returns a `MoreAsk` (the kind's token, key, words and offset), and only while
    `pages` says `.more`. The token is the kind's own, so new words let it go. `moreAnswered` (albums, artists or
    songs) appends the page and returns what to announce. `moreFailed` keeps the failure until Try again.
    `MorePage`: idle, asking, failed, added.
  - **`kindView(artistList:marks:before:)`.** The rows are: what's saved (`savedRows`), the foot, the rows landed
    after it (`below`), More (`KindView.More`: the note, the failure, the pages, the button's label) and the area to
    keep (`area`). MusicBrainz's rows are held (`mbHeld`) while what's saved is still asking for these words. The
    view's region words (`KindView.Said`) are its library's, then MusicBrainz's with what's saved's. `kindAreaKey` is
    the key to keep the area by.
- **Routes and the client**: `Routes.savedSearch` (49); `savedSearch(_:)` (`words`). `fullySearch`, `searchArtists`
  and `searchSongs` take `offset`, sent only above 0, so a first page is asked exactly as before.
- **export-search-saved-vectors.cjs** (new) compiles lib/searchList.ts, lib/songs.ts, lib/searchResults.ts and
  app/searchAnswers.ts with tsc, and reads More's buttons and the far note from Search.tsx. It writes a fourth
  fixture, Fixtures/search/search-saved-vectors.json (2.8 MB, plain ASCII, seed 5454):
  - the numbers and the words;
  - 42 groups, 5 folder lists and the 7 recorded song searches;
  - studioGroup over the 42;
  - 135 saved answers read for a view (15 worked, 120 seeded);
  - 70 kind views' runs (270 steps), each a kindArea fed what landed next;
  - 1485 morePages counts;
  - 90 pages of albums appended;
  - 41 runs of songs' pages and the defaults. The 41st is made, not seeded: a song's first take on no release, so
    never drawn, then a take of it on one;
  - 6 runs of kept answers;
  - 82 whole searches with what's saved and MusicBrainz's answer in hand (12 worked, 70 seeded). Each holds the
    pool, the candidates, the decided prefix, the moment's Top results and sections, the full list, the late rows,
    the counts and every row's family.

  **ui/test/iossearchsaved.sim.cjs** runs its `--check`.

### Held to the web: by the exporter, or by hand

The exporter holds the web's real code for these:
- savedFor, studioGroup and kindArea;
- the pool with what's saved, the candidates, decidedTop and topResults with the saved marks, familyOf's marks,
  sectionRows, lateRows and drawnCounts;
- appendPage, morePages and morePageWords; appendSongs and moreSongsWords;
- keepAnswer and keptAnswer;
- the saved words and More's.

Search.tsx's state is a component the exporter can't compile, so its rules are held by hand (SearchSavedTests),
from reading it:
- askSaved, once per words, and its SAVED_WAIT_MS give-up;
- savedSettled holding the library's moment;
- what's saved drawn only once MusicBrainz is for the words;
- takeKept at the library's moment, and only for words MusicBrainz is asked for;
- the More asks, their offsets, their staleness under new words, and never in All;
- the kind view's held rows and its area across answers;
- the words each moment says, the answers decoded, and the client.

### Where the phone can't follow the web exactly

- **The kept answers' keys** are route, words and page size, where the web's are the request's path. Each names the
  same request. They outlast a sign-out, and since the review each lasts an hour, where the web's last the page's life
  (question 28).
- **A More asking as new words are typed** (question 34, since the review): let go at once, where the web's lands
  until the kind is asked for the new words.
- **More's last page under VoiceOver** (question 32): announced, but no focus move.
- **A kind view's words** (question 33): said through the app's announcement, each once per words and kind, where the
  web's is a live region.

### The app

- **SearchModel**:
  - `askSaved` asks `/saved` when typing settles on words MusicBrainz is to be asked for, and beside every
    `askMusicBrainz` (the keyboard's Search on fewer than three letters). Its own clock (`savedClock`, `waitMs`) gives
    it up and draws without it.
  - `kept` is static on the type: the session's kept answers, which survive `reset()`. `keptAlbums`, `keptArtists`
    and `keptSongs` answer from it, else ask and keep the answer. A kept answer doesn't wait for `/library/owned`, as
    the web's doesn't. `takeKept` runs as the library answers, fails or is skipped, and as a chip is pressed. It runs
    only online, and then asks `/library/owned` again to mark rows in place.
  - `moreMusicBrainz` asks the next page through the kind's token on `askingMoreMusicBrainz`. `letGo` (a new
    person, the box cleared) cancels it, and new words cancel it and drop its page. It announces what came.
  - `standDown()` is unchanged. It lets go of what would open a page, and none of slice 4's asks opens one: each
    draws into the list only if it is still the newest ask for its words and kind.
  - `kindView` keeps each view's area (`kindAreas`, by "kind\nwords"). Typing lets go of other words' areas.
  - `announceKind` says the view's region words, each once. A chip drawn at once says "Showing albums." with them.
  - Nothing asks while deadwax can't be reached, and none of it opens a page.
- **SearchScreen**:
  - `KindMusicBrainz` (was `KindFoot`) draws a kind view's MusicBrainz part: Type a little more, or a title needed.
    Else, in order, what's saved, the asking line or the failure, MusicBrainz's rows or why there are none, the rows
    landed after, and `MusicBrainzMore`.
  - `MusicBrainzMore` draws the page's note, the failure, the button (`SecondaryPill`: the kind's words, "Loading…"
    and disabled while asking, "Try again"), or the far note.
  - `SectionSlot` and `MusicBrainzFailure` take `saved` and say `savedAway`'s words under what's saved.
  - All of it is drawn only online. More is at the list's foot, so its lines growing move nothing above them.

### Decided here (the spec was silent, or this departs from it)

Questions 28-33 in the spec, each built to its recommendation:
- 28, the kept answers' life, keys, and sharing across people;
- 29, SAVED_WAIT_MS kept at 400 ms on the phone;
- 30, what's saved offline;
- 31, More's wait;
- 32, More's last page under VoiceOver;
- 33, a kind view's words.

Question 5's search of what's downloaded while offline was not built in this slice either: the spec says so, and
docs/ios.md's "What it can't do yet" says it.

And smaller ones, not worth a question:
- the saved rows ride in the drawn list as key sets, not a second row type, so every slice-1-3 rule over rows holds
  unchanged;
- the kind view's area is the model's, kept by the view's words and kind, as the web keeps a ref;
- the kept answers' wait for `/library/owned` is skipped, as the web skips it (`!found.kept`).

### Tests

- **SearchSavedVectorTests** (10): every vector of search-saved-vectors.json:
  - the numbers and the words;
  - studioGroup;
  - savedFor;
  - the kind views' runs;
  - morePages;
  - the album pages and songs' pages appended;
  - the kept answers;
  - every whole search: the pool, Top results at the moment and in full, the sections, the late rows, the counts
    and the families.
- **SearchSavedTests** (17), by hand, for Search.tsx's state:
  - what's saved asked once per words, and given up past its wait;
  - what's saved drawn only once MusicBrainz is for the words;
  - leading at the library's moment, with MusicBrainz adding only what isn't there;
  - every kind failing under it, and a late answer bringing nothing new;
  - the answers read leniently;
  - a kind view's saved rows leading, landing late, and failing;
  - the kept answers taken with no request, a fielded reading's needing its fallback kept, and 24 kept;
  - More asked, appended, failed and retried, dropped by new words and never in All, the furthest page narrowed;
  - the client's two new asks.
- **SearchTests, SearchAlbumsTests and SearchSongsTests** run unchanged. What's saved is idle unless asked, so the
  earlier slices' moments draw as before.
- **ClientTests**: `Routes.all` 49. **FixtureFiles**: the new fixture read from the checkout.
- **tests/test_ios_contract.py**: ROUTE_COUNT 49, and two new tests:
  - `/saved` is asked by `words`, the box's 200 characters within its bound. Its answer's kinds are the app's,
    `available` is in every answer, it is read leniently, and its page of each kind (SAVED_ARTISTS, SAVED_ALBUMS,
    SAVED_SONGS) is the app's own, with `artistAlbums` within SAVED_CREDITED;
  - More's `offsetMax` is FULLY_SEARCH_OFFSET_MAX, within `/fully_search`'s, `/artists`' and `/songs`' `offset`,
    sent only past the first page.
- **Mutations**: 26, each applied alone with the eight Search suites run (`--filter Search`). 22 were caught at
  first. Of the 4 that lived, 3 were closed and caught when run again:
  - 14, appendSongs keeping the songs in groupSongs' order rather than as drawn. The seeded runs never drew a song
    out of groupSongs' order. Closed by the made run in the exporter (the fixture written again; 6 tests then
    failed).
  - 19, the kept answers taken for words MusicBrainz isn't asked for. The by-hand test had no answer kept for the
    short words. Closed in `theKeptAnswersAreTakenAtTheLibrarysMomentWithNoRequest`: "ro" kept from the keyboard's
    Search, then typed again.
  - 20, a page of albums landing on the kind's newer ask of the same words. The test only changed the words. Closed
    in `moreFromMusicBrainzIsDroppedByNewWordsAndNeverAskedInAll`: back to the words, their first page answered again
    (as a kept answer is, at once), then the old page.

  The fourth, 16 (`savedAway` without its refusal line), is equivalent: `MBFailure.of` never makes a failure both
  refused (a 422) and busy or away (a 503).

  The 26:
  1. what's saved waited 401 ms;
  2. 23 answers kept, not 24;
  3. an answer kept again keeps its old place;
  4. what's saved not narrowed to the studio's;
  5. an artist's saved albums 13, not 12;
  6. an artist's saved albums not from the credited;
  7. what's saved after a failure drawn above it;
  8. a kind view's row kept as saved whatever it was;
  9. an empty last page not the end;
  10. the furthest page itself narrowed;
  11. a page of albums repeating what was got;
  12. a page held said "in your library" with a library of your own;
  13. the songs drawn gaining albums, unsaid;
  14. the songs drawn not kept in their drawn places;
  15. "Also found" under what's saved;
  16. a refusal said as earlier results under what's saved;
  17. the library's moment not waiting for what's saved;
  18. what's saved asked again for the same words;
  19. kept answers taken for words MusicBrainz isn't asked for;
  20. a page of albums landing whatever was asked since;
  21. the next offset a full page on, whatever came;
  22. a kind view's MusicBrainz rows not held for what's saved;
  23. a late slot repeating what was drawn above it;
  24. what's saved ranked as MusicBrainz's;
  25. MusicBrainz's albums repeating what's saved;
  26. a song's named album not marked saved as a saved group.

### Verified, and not

Verified, on the tree before its commit:
- `swift test`: Core 1514 (27 new), Audio 158, Turntable 12. No new warnings.
- The unsigned Debug and Release device builds (Xcode, `generic/platform=iOS`) succeeded, with no warnings but the
  usual appintentsmetadataprocessor line. The .xcodeproj is unchanged.
- `check_project.py` ok, with the app as 0.11 (11).
- `npm run build` and all 87 sims on Node 22.23.4, iossearchsaved's `--check` among them.
- The full pytest suite: 4519 passed, 1 skipped (test_ios_contract's two new tests, test_ios_install at 0.11, and
  test_compose_example's docs rule among them).
- The 26 mutations above: the 3 that lived closed and caught, the fourth equivalent.

Not verified - only the phone can tell (docs/ios.md's checks 156-165, beside the spec's section 9):
- `/saved` inside its 400 ms over WireGuard, and how often it is given up there (question 29).
- What `/saved` finds against James's saved answers, beside the web's Search for the same words. The fakes are the
  web's.
- A kind view's rows holding their places at accessibility sizes as what's saved, MusicBrainz and More's pages land.
- Where VoiceOver's cursor goes as More's button goes (question 32), and how the announcements queue with a chip's.
- More against real MusicBrainz through deadwax: its offsets, `count`, and the furthest page.
- The kept answers across a sign-out on a real phone, and how much memory 24 answers take there.
- CI's Xcode 26.6 (the older Swift). The new code spells out its closures' types and keeps each `#expect` small.

## Phase 5, slice 4, after its review (2026-11-14)

The review of slice 4 found one medium-low bug and three low ones. This fixes three of them, in a commit of its own
on `phase5-search`. The second (an album both what's saved and MusicBrainz found drawn nowhere in All while
`/library/owned` isn't in hand) is the web's rule too: it was fixed in searchList.ts on main (2.1.25) and ported
here in a commit of its own once it reached ios - "Phase 5, slice 4's review, finding 2", below.

### What was wrong, and the fix

1. **One More task was shared by all three kinds** (medium-low).
   - What happened: SearchModel held a single `askingMoreMusicBrainz` task and cancelled it before each More. A
     cancelled URL load ends as a CancellationError, which `isCancellation` passes over in silence. So the kind it
     belonged to stayed `.asking`, and Core's `askingMoreMusicBrainz()` (`found.more != .asking`) refused every
     later More for that kind.
   - The scenario: in Albums, tap More albums while MusicBrainz is slow, then go to Songs and tap More songs. Back
     in Albums, the button says "Loading…", disabled, until the words change.
   - The web gives each kind its own latestOnly (Search.tsx's askMore, askMoreArtists, askMoreSongs).
   - Fix: the model keeps one task for each kind (`askingMoreMusicBrainz: [SearchKind: Task]`), so asking one
     kind's More never cancels another's. Core gains `moreLetGo(kind)`: a kind asking is idle again. `moreAnswered`
     and `moreFailed` now take only an ask that is still asking, so the page or failure of an ask let go lands on
     nothing. Every cancel of a More (`cancelMore()`: new words, a new person, the box cleared) comes with Core's
     let-go, so a cancelled More can always be asked again.
3. **A More page that landed after new words were typed was still appended and announced** (low).
   - What happened: `type()` cancelled More only on `.drop`, and `moreAnswered` checked only the token and the key.
     So in the window before MusicBrainz was asked for the new words (`.settle`, about 700 ms), the old page landed
     under them. The slice 4 notes said new words cancel it, and for `.settle` they didn't.
   - Fix: Core's `typed` lets every kind's More go on any new words, and the model cancels every More task. The note
     is now true. This departs from the web, whose page lands until the kind is asked again (question 34).
4. **Kept answers "for the app's life"** (low, design). An iPhone app's life runs to days, since only a force-quit
   ends it. A search repeated days later was answered from memory with no request, and its More's offsets followed
   that old first page. docs/ios.md said closing the app lets them go, which is only true of a force-quit.
   - Fix: each kept answer is stamped with when it landed, and is missing after `SearchAnswersKept.lifetime`, an
     hour. That is deadwax's own in-memory hour (ResponseCache's `ttl_seconds`), and the contract test holds the two
     equal.
   - The model stamps and reads by `Monotonic.seconds()`. That is a ContinuousClock, which counts the phone asleep
     and doesn't move when the wall clock is set.
   - `kept(_:at:)`, `keep(_:_:at:)`, `albums/artists/songs(_:at:)` and `takeKept(…now:…)` take the time, so Core
     stays pure and its tests inject the clock.
   - Question 28 says so (the web's last the page's life, the phone's an hour), and docs/ios.md is corrected.

### Tests

- **SearchSavedTests**, four new:
  - `aMoreLetGoCanBeAskedAgainAndItsPageLandsOnNothing`: asking, let go, idle. The old ask's page and failure land
    on nothing, More asks again at the same offset, its page lands, and a let-go with nothing asking leaves the page's
    words.
  - `oneKindsMoreLeavesAnothersAsking`: Albums' More asking, Songs' asked, Albums' still asking, and its page lands.
  - `newWordsLetAMoreGoBeforeMusicBrainzIsAskedForThem`: More asked, then "roseland n" typed (`.settle`). The old
    page is neither said nor appended, More is idle, and back on "roseland" More asks again.
  - `aKeptAnswerIsAnsweredFromForAnHourThenAskedAgain`, with an injected clock. The answer is there at once and at
    the last second of the hour, missing a second past it and days on. The library's moment takes it inside the hour
    and not past it, and kept again, the hour runs from then.
- The kept answers' earlier tests and the vector replay pass times. The replay steps a second at a time, well inside
  the hour, which the web's page has no end to.
- **tests/test_ios_contract.py**: `test_the_apps_kept_answers_last_deadwaxs_own_hour`, which checks
  `SearchAnswersKept.lifetime` against ResponseCache's `ttl_seconds` default.
- **Mutations**: 5, each applied alone with the Search suites run, and all caught:
  1. new words leaving a More asking;
  2. an albums' More let go staying asking;
  3. a let-go albums page still appended;
  4. a kept answer answered from for ever;
  5. an hour less a second.

### Verified, and not

Verified, on the tree before its commit:
- `swift test`: Core 1518 (4 new), Audio 158, Turntable 12. One warning, and not a new one:
  SearchSavedVectorTests.swift:432's `#require(each.studio)` is ambiguous (an optional Bool). It has been there since
  slice 4, whose full run compiled nothing new and so didn't print it - its "No new warnings" missed it. Fixed with
  finding 2's port.
- The unsigned Debug and Release device builds (Xcode, `generic/platform=iOS`) succeeded. The .xcodeproj is unchanged.
- `check_project.py` ok.
- `npm run build` and all 87 sims on Node 22.23.4.
- The full pytest suite: 4520 passed, 1 skipped (test_ios_contract's new hour test among them).
- The 5 mutations above, all caught.

Not verified - only the phone can tell (checks 162 and 163 gain a sentence each):
- More on two chips over a slow connection.
- A kept answer asked again after an hour with the phone asleep in between.

## Phase 5, slice 4's review, finding 2: saved albums before the library's index (2026-11-14)

The review's second finding is the web's rule too. It was fixed on main as 2.1.25 (notes/backend-gotchas.md, "Saved
albums before the library's index (2.1.25)"), merged into ios, and from there into `phase5-search`.

- **What was wrong.** `pool` left every album what's saved holds out of MusicBrainz's answer (`savedGroupIds`),
  while `savedFor` draws none of them until the library's index (`/library/owned`) is in hand: its `shown` is empty
  before then. So an album both had found was drawn nowhere before the index, neither as saved nor as MusicBrainz's.
  A slow or failed `/library/owned` was enough, and All, frozen once drawn, kept the gap for those words.
- **The port.** SearchList.swift's pool keeps `savedDrawn`, the saved groups it draws: `shown`, and the held ones it
  brings in. It filters MusicBrainz's `groups` and `shown` by that set, never by every saved group. Before the index,
  the album comes as MusicBrainz's row; once the index is in, it is drawn once, as saved.
- **docs/ios.md**'s What's saved now says so, in the web's words (docs/finding-music.md): saved albums wait for the
  index, saved artists and songs don't, and MusicBrainz's albums come as ever.

### Tests

- **The exporter** (export-search-saved-vectors.cjs) gains two fixed cases, "portishead" with no index (list 0) and
  with one (list 3), where what's saved and MusicBrainz both found Portishead, Dummy Remixed and Glory Box EP.
  - Before the index, all three are MusicBrainz's rows. With it, Portishead and Glory Box EP are saved rows and Dummy
    Remixed is MusicBrainz's, each drawn once.
  - search-saved-vectors.json is re-exported. The other three Search fixtures (search, search-albums, search-songs)
    are unchanged by the web's change, each checked with `--check`.
- Against the unported Swift, the replay failed 10 cases, the new no-index one among them. Ported, all pass.
- **Mutations**: 2, both caught.
  1. The held saved groups brought in left out of `savedDrawn` (7 cases).
  2. MusicBrainz's `shown` not filtered at all (35).
- The replay's `#require(each.studio)` is now `as Bool?`, which ends its ambiguity warning.

### Verified, and not

Verified, on the tree before its commit:
- `swift test`: Core 1518, Audio 158, Turntable 12, with no warnings.
- The unsigned Debug and Release device builds succeeded. The .xcodeproj is unchanged.
- `check_project.py` ok.
- `npm run build` and all 87 sims on Node 22.23.4, iossearchsaved's `--check` among them, and searchList's two new
  checks from main.
- The full pytest suite: 4520 passed, 1 skipped.
- The 2 mutations above, both caught.

Not verified: the phone with a slow `/library/owned` (the first look after the deadwax container starts, on a
sleeping disk). The web's commit didn't see it in a browser either.

## Phase 5 as a whole (2026-11-14)

Search on the phone is the web app's Search: one list, the web's rules ported to Core and held to its own
TypeScript.
- Your library through search3. MusicBrainz's albums, artists and songs after yours, deduped against what you
  hold.
- Top results picked as the web picks them.
- The moments that keep anything from moving under a finger.
- The album you don't have, with its pressings and tracklists. A song's albums, and the album it names, with the
  song marked. A MusicBrainz artist's page.
- What's saved, the kept answers, and More.

Four slices, each with its review. The app is 0.11 (11).

- **Routes**: 40 -> 49. `/library/owned`, `/fully_search`, `/release_group`, `/coverart/{kind}/{mbid}` (the
  relay, main's 2.1.24 - the phase's one server change), `/artists`, `/songs`, `/artist`, `/discography` and
  `/saved`.
- **Held to the web**: four fixtures, about 8 MB:
  - search-vectors.json (1.4 MB);
  - search-albums-vectors.json (1.3 MB);
  - search-songs-vectors.json (2.4 MB);
  - search-saved-vectors.json (2.8 MB).

  Each is written by its exporter from lib/searchList.ts and the files beside it, and checked by its sim:
  iossearch, iossearchalbums, iossearchsongs (with the collation tables' check) and iossearchsaved. Search.tsx's own
  state is held by hand in SearchTests, SearchAlbumsTests, SearchSongsTests and SearchSavedTests.
- **Questions**: 1-34 in the spec, each built to its recommendation unless it says otherwise.
- **James's checks**: 121-165 in docs/ios.md. None has been done on the phone yet.
- **Not in Phase 5**:
  - Get and Requests (Phase 6);
  - an artist's description and links (Phase 7), and Home and pins (a later phase);
  - a search of what's downloaded while deadwax can't be reached (question 5: not built - offline, a list
    already drawn stays, and new words wait for deadwax).

## Phase 6, slice 1: Requests (2026-11-14)

notes/ios-specs/phase6-get-requests.md 2.1-2.7, 2.12, 3.1-3.3 and 6.1, and questions 1-12. Before it, the phone
showed nothing of a download: whatever was asked for in the web app was seen only there. Now Requests is a fourth
tab, between Search and You:
- every download the person asked for, wherever they asked, under the web's four headings, in the web's words;
- the ✕ (asking first in the card, with You > Getting albums' Confirm before cancelling), Another source, Same source
  again and Clear done;
- a Done row opening its album, and its ▶ playing it;
- the badge, the announcements, offline and the background.

Nothing on the phone asks for a download yet: Get is slice 2.

On `phase6-get` from `ios` at 3fc9a17, after the spec's own commit (2e8b2cc). src/__init__.py untouched; the app
stays **0.11 (11)**; the .xcodeproj is unchanged (the new files are in the synchronized App folder). ROUTE_COUNT
49 -> 54: `/download/jobs` and its four writes, every one on the server since 2.0.0 (src/routes/download.py). There
is no server change.

### Core (DeadwaxCore)

- **Requests.swift** (new): requestsView.ts, ported to the character.
  - `DownloadJob`: a row of `/jobs`, read leniently but for its id and status (`looseField`, `looseList`). `JobsAnswer`,
    `CancelAnswer`, `RetryAnswer`, `RetrySameAnswer`, `ClearAnswer`: the writes' answers, each within what its route
    returns.
  - `RequestSection`, `RequestTone`, `RetryProblem` (deadwax's own words, or a sentence with the error's own beside
    it), `RequestRow` (every field of the web's row, but `cover`: the release's id, for the relay, where the web makes
    the Archive's own address), `RequestsInput`, and `RequestsView.make(_:now:)`.
  - `RequestWords`: every word of the board, the cards, the hook's refusals and You's Confirm before cancelling - and
    the small rules: `age`, `outcome`, `badgeText`, `badgeLabel`, `ordinal`, `speed`, `section`, `retryProblemWords`,
    `cantOpen` (App.tsx `navidromeProblem`), `note` (Requests.tsx `noteFor`), `emptyLine`, `keepsAsking`. The phone's
    one sentence of its own: `offline`, "Requests show once deadwax is back." (question 4).
- **RequestOverlays.swift** (new): downloadOverlay.ts, speed.ts and perPerson.ts.
  - `PendingDownload` and `RequestOverlays`: `withPending`, `settlePending`, `withoutRefused`, `visibleJobs`,
    `activeCount`, `visiblePending`, `reconcile` and `finishedIds`, and the overlays' 15 s (`ttlSeconds`).
  - `SpeedSamples`: the rate measured from byte counts over a second or more, kept 6 s through quiet polls.
  - `CancelWords` and `PerPerson`: who asked, what a cancel does, and what a filing gave them (grantWords and
    partlyWords, from myLibrary.ts).
- **RequestsWatch.swift** (new):
  - `Watching` and `RequestsWatch`: `watching` (watchingOf), `stallsOn`, `asksAgain`, and libraryEvents.ts'
    `statuses` and `newlyFiled` (statusesOf and newlyOrganized).
  - `RequestsPolling`: the poll's pace, `delay(open:hasActive:filing:online:watching:)` and `asks(online:watching:)` -
    the web's 0.5 s, 1 s and 5 s, and none offline or in the background (question 3).
  - `RequestChanges`: `changes` (and `focusAfterGone`, which it uses).
  - `DoneLooks`: `looks`, the Done rows' albums looked for ahead (DONE_PREFETCHED 5, DONE_SCAN_SETTLE_MS 10 s, the
    5 s backoff doubling to 60 s, songs asked again when 30 s older than the tab's coming into view).
  - `ConfirmCancel`: the web's key `deadwax-player-confirm-cancel`, "off" off and anything else on.
- **Routes.swift**: `jobs`, `cancelJob`, `retryJob`, `retryJobSame` and `clearJobs`, in `all`, with their times to
  answer (question 11): 20 s, 30 s, 60 s, 30 s and 30 s.
- **DeadwaxClient**: `jobs()`, `cancelJob(_:)`, `retryJob(_:)`, `retryJobSame(_:)`, `clearJobs()`, and
  `storeAlbum(releaseMbid:)` - the id bridge's whole answer by a pressing, for a Done row's note
  (`navidromeAlbum(releaseMbid:)` now goes through it).

### Held to the web: by the exporter, or by hand

`ios/scripts/export-requests-vectors.cjs` compiles lib/requestsView.ts, lib/downloadOverlay.ts, lib/speed.ts and
lib/libraryEvents.ts, with what they import (perPerson, myLibrary, errorWords, format, jobs), and reads the numbers and
words of useDownloadJobs.ts, Requests.tsx, JobCard.tsx, You.tsx, ConfirmCancelChoice.tsx, persisted.ts and
permissions.ts from their source. It writes Fixtures/requests/requests-vectors.json (2.2 MB, seed 6606):
- 140 ordinals, 10 badges, 17 speeds, 48 ages, 8 partly-filed counts;
- 489 endings, 32 retry problems, 45 askers, 288 sections;
- 100 seeded boards (535 rows, every field of every row);
- 30 runs of five looks for `changes`;
- 120 overlay cases and 40 speed traces of 14 polls;
- every watching, stalling and asking-again combination (60, 36, 16);
- 200 Done rows' looks;
- and 40 runs of six looks for what was filed (31 jobs filed).

`ui/test/iosrequests.sim.cjs` runs it with `--check`; `RequestsVectorTests` (14) replays it through the real models.
libraryEvents.ts was added to the spec's list: newlyOrganized is plain TypeScript, so it is held rather than ported
by hand.

What lives in a hook or a component the exporter can't compile is ported by hand, with tests of its own
(`RequestsTests`, 16):
- the poll's cadences;
- `noteFor` and `navidromeProblem`;
- Confirm before cancelling's read;
- a request becoming its job, a refused one keeping its detail;
- "left" said for a cancel that only leaves;
- the speed over a second and through quiet polls;
- `DownloadJob` reading the route's own rows (logins off and on, and an odd field);
- the client's five requests and the id bridge's, their methods, paths and times, and a refused write's kind.

The hook's and the page's state - the overlays set before a write and rolled back after, the retry's give-up words,
the Done rows' state - is RequestsModel's in the app, read from useDownloadJobs.ts and Requests.tsx.

### Where the phone can't follow the web exactly

- **A field of a shape the app doesn't know** (a `queue_position` of "4th", a name that isn't a string) is none, not
  the whole list gone: the web's JavaScript would draw the rest, and a strict Decodable would draw nothing. Only a row
  without its id or status throws.
- **Offline** (question 4): none of the last answer drawn, where the web's page keeps showing it; back, it is drawn
  again at once and asked afresh. **In the background** (question 3): no poll, where the web's goes on until iOS
  suspends the page. **Under the sign-in over the app**: no poll either - every look would be a 401.
- **No Home** (question 7): `home` never comes; the badge is the only sign of a download outside Requests.
- **No focus moves** (question 10): what changed is announced, and VoiceOver keeps its own place in the List.
- **Each sentence `changes` says is announced**, where the web's live region speaks only when its text changes - the
  same sentence twice in a row is heard twice here.
- **▶ doesn't warm the album's levels itself** (the web's `warmAlbum`): the player's LoudnessBook asks for every
  album the new queue names as it is set (`wantQueue`), which is the same ask.
- **A cancel or Clear done that fails** is only rolled back, as the web's (whose console.error has no phone
  counterpart): the row coming back is the word.
- **The cover's id is lowercased** for the relay, which takes MusicBrainz's ids only as MusicBrainz gives them.
- **Clear done waits offline** as well as with nothing to clear.

### The app

- **RequestsModel** (Models/RequestsModel.swift):
  - The one poll: `kick()` starts a loop, the one before let go (`stopPolling`, one more `looks`), and each answer
    lands only for the newest loop and the person it began for (`epoch`). `RequestsPolling` decides each wait; a turn
    of `open` (Requests' root, or `stallsOn`) asks at once, even from inside the loop, as the web's effect re-runs.
  - `watch(_:)`, from MainTabs: Requests' root coming into view starts a period of looking, leaving it lets every
    look go (`letLooksGo`); the background stops the poll; `asksAgain` asks once.
  - `reachChanged()`, from Reachability: offline stops everything; back, the failure from while deadwax was away is
    forgotten, the board drawn again and a look asked.
  - `land(_:)`: the speeds sampled (on the monotonic clock), `newlyFiled` asking Search's owned index again
    (question 8), the overlays reconciled.
  - `redraw()`: the board made from the last answer and the overlays; `changes` announced while Requests' root shows;
    each Done row's first moment kept (0 for the first answer's); the looks run again.
  - `cancel`, `retry(_:same:)` and `clear()`: the overlay up before the request, each write its own task, rolled back
    or given up with the web's words; an answered write asks at once. The overlays' clocks are tasks too, and a reset
    lets every one go.
  - The Done rows: `runLooks()` - the id bridge by release, then the album's songs - with the due clock, all only while
    Requests' root shows. `open(_:)` opens a known album at once, else asks and opens only if the root still shows, the
    same period, and no second tap; a row that can't open gets its note. `plays(_:)` hands a ▶ the songs in hand.
  - `reset()`: everything let go, and the new person's first look asked once the new session is in hand.
- **RequestsScreen** and **RequestCards** (Requests/): a List of Sections, each heading only with rows; the failed
  look's card, the untracked card (DB_PATH for whoever runs deadwax), the spinner until the first answer, the empty
  card (Get's words only to someone who can Get), the offline line. Clear done in the bar. The cards: the cover
  through ArchiveCover (44 and 52 points, scaled), the title on one line as the web's, the data line always drawn and
  one line, DownloadBar, the ✕ (44 points, its 32-point face, disabled while its cancel is out), the card's question
  (SecondaryPill's Keep it and the red action), Needs attention's buttons (PrimaryFace for the first Another source,
  SecondaryPill for the rest, disabled while busy) and GET_OFF without Get albums, and the Done row's button and ▶.
  The ✕ reads Confirm before cancelling at the tap; one card asks at a time, and a second tap closes it.
- **MainTabs**: the tab, `square.and.arrow.down`, its badge (`Text?`, nil at 0 - an empty string would draw an empty
  badge), the Label's accessibility label "Requests, 2 arriving"; `watching` from the scene, the tab, its stack's depth,
  Now Playing and the sign-in over the app, handed over with `onChange(initial: true)`, and `.hidden` as the tabs go.
  (Since the squared look the tab is the app's own bar's, its badge and label on its button: "Requests on the app's
  own tab bar" below.)
- **AppNavigation**: `AppTab.requests`, the `requests` stack and `requestsScrollToTop`, in every switch.
- **You**: GettingAlbumsSection, before Playback (the web's order) - the toggle, `@AppStorage` under the web's key.
- **DeadwaxApp**: the model made after Search, `reachability.whenChanged` and `whenPersonChanges` wired, in the
  environment. **Palette.dimmed** 0.55 (`--app-job-dimmed`).

### Decided here (the spec was silent, or this departs from it)

Questions 1-12 in the spec, each built to its recommendation. And smaller ones, not worth a question:
- the Done rows' clock is this phone's wall clock in milliseconds, as the web's Date.now() (a first answer's rows at 0
  are then long done); the speeds' is the monotonic one, as the spec says of SpeedSamples;
- the lines that come once - a reason, a retry's refusal, a Done row's note - wrap, as the web's do; the one that
  changes at every look (the data line) is one line high, drawn when empty;
- the web's tinted Another source is drawn as the secondary pill: the phone has two button faces, and the solid one
  is still only the first;
- a turn of `open` from inside the loop asks at once, as the web's effect re-runs: one extra look when a stall ends;
- the sign-in over the app counts as hidden.

### Tests

- **RequestsVectorTests** (14): every vector of requests-vectors.json - the numbers and words, the small rules, the
  endings, the retry problems, who asked, 100 whole boards (over 400 rows checked field by field, and activeCount over
  the same overlays), `changes` over 30 runs, the overlays, the speed traces, the watching grids, what was filed and
  the Done rows' looks.
- **RequestsTests** (16), by hand, as listed above.
- **ClientTests**: `Routes.all` 54, and the five new times to answer.
- **tests/test_ios_contract.py**: ROUTE_COUNT 54; `DownloadJob`'s keys within what `/jobs` builds; the real `/jobs`
  route (logins off, a fake slskd: queued, organized, failed with a runner-up) decoded as the app decodes it; the four
  writes' answers within their routes'; `/retry`'s 60 s at least what deadwax's own asks of slskd can take. And
  `test_a_held_album_is_found_by_its_release` reads the id bridge's call where it now is, in `storeAlbum(releaseMbid:)`
  (it read the line `navidromeAlbum(releaseMbid:)` used to make itself, and failed on the move).
- **iosrequests.sim.cjs**: the exporter's `--check`.

**Mutations** - each rule broken on purpose, the tests run, the rule put back. All 22 were caught:
1. the poll asking offline (`nothingIsAskedOfflineNorInTheBackground`);
2. filing at the background's pace, and 3. polling on with nothing active (`thePollIsFast…`);
4. asking again after Requests, and 6. stalling with nothing arriving (`whatTheAppWatchesIsTheWebs`);
5. what was filed before the first look counted as news (`anAlbumJustFiledIsNoticed…`);
7. "left" said for every cancel that went (`whatAScreenReaderHearsIsTheWebs`);
8. the backoff doubling one early, and 9. songs never asked again (`theDoneRowsAlbumsAreLookedFor…`);
10. Confirm before cancelling off unless "on" (`confirmBeforeCancellingIsOnUnlessTurnedOff`);
11. a cancel kept after its job stopped, and 22. Clear done keeping the refused requests (`theOverlaysAreTheWebs`);
12. activeCount without the requests (`aRequestBecomesItsJob…`, the boards);
13. a rate from under a second (`aSpeedIsMeasuredOverASecond…`);
14. a strict queue place emptying the list (`anOddFieldIsNone…`);
15. a queued job with bytes moving left under Waiting, and 18. 99+ from 101 (`theSmallRulesAreTheWebs`);
16. the music server's being unreachable unsaid, and 21. the store's folders not read for the note
    (`aDoneRowsNote…`, `aDoneRowsAlbumIsAskedOfTheIdBridge…`);
17. no solid Another source, and 20. an already-there album's row playing (`everyBoardIsDrawnAsTheWebDrawsIt`);
19. an admin's cancel of a shared download only leaving (`aJobIsReadAsDeadwaxSendsItWithLoginsOn`, the boards).

The App's own wiring (the loop, the periods, the looks' tasks) has no tests: it is SwiftUI's and URLSession's, and the
rules it applies are each tested in Core.

### Verified, and not

Verified, on the tree before its commit:
- `swift test`: Core 1548, Audio 158, Turntable 12. No warnings.
- The unsigned Debug and Release device builds (Xcode, `generic/platform=iOS`) succeeded, with no warnings but the
  usual appintentsmetadataprocessor line. The .xcodeproj is unchanged; `check_project.py` ok.
- `npm run build` and all 88 sims on Node 22.23.4, iosrequests' `--check` among them.
- The full pytest suite: 4529 passed, 1 skipped (test_ios_contract's four new tests among them). Its first run
  failed test_a_held_album_is_found_by_its_release, fixed as above.
- The 22 mutations above, each caught.

Not verified - only the phone can tell (docs/ios.md's checks 166-177, beside the spec's section 9):
- Whether a 0.5 s poll keeps up over WireGuard, and what Requests left open costs the battery.
- Whether the tab is read "Requests, 2 arriving": an accessibility label on a `.tabItem`'s Label isn't documented to
  reach the tab bar, which may read the badge its own way. (Moot since the merge below: the bar is the app's own, the
  label its button's.)
- Whether an announcement made as the List redraws is heard whole, and where VoiceOver's cursor is after a card moves
  or goes.
- Whether a card's question opening and closing in a List row moves the rows around it at the largest text size.
- Real slskd: its queue places, the speed, a refusal and a cancel, in the board's words. Every slskd here is a fake.
- The in-app pieces themselves - the loop's periods, the looks' tasks, a Done row's open left behind - have run only in
  the compiler: no Simulator is used here.
- CI's Xcode 26.6 (the older Swift). The new code spells out its closures' types and keeps each `#expect` small.

## The squared look (14 Nov)

James, on his iPhone at app 0.11, in this order:

- "the search bar is kinda in the way" (the Library's Find bar);
- "let's put a magnifying glass button on the left side of the slider, and then maybe refine the slider size a
  little so the top looks complete. maybe square off the slider and the bar at the bottom and the now playing bar as
  well";
- "as a matter of fact, let's square everything off a bit more, especially the album arts";
- "but the search button and options button at the top can be circles".

Fonts are being chosen apart from this, and nothing here changes one. Built on `square-look` from `ios` 3fc9a17.
**The app stays 0.11 (11)**; src/__init__.py untouched; no server change; the engine files untouched (no playback
change of any kind).

### What changed

- **One set of corners** (ios/App/Shared/Corners.swift): `art` 2, `card` 4, `control` 4, `track` 2, `fill` 1, with
  their continuous shapes and `controlBorder` (a system button's `buttonBorderShape`). Every RoundedRectangle and
  Capsule in ios/App is now one of them (the table below); test_ios_palette.py's
  `test_every_corner_in_the_app_is_a_token` fails on a radius written anywhere else, a `Capsule()` or a `.capsule`,
  and `test_every_system_bordered_button_is_squared` on a `.bordered` without `Corners.controlBorder` (iOS 26's
  is a capsule).
- **The Library's top** (LibraryView, new Library/LibraryTop.swift): the navigation bar is hidden on the pager, and
  the Library draws its own top in a `safeAreaInset(edge: .top)`: Find's magnifying glass, the switch filling the
  room between (`maxWidth: .infinity`), the ••• - 12 pt from the edges to the circles' 44 pt targets and 8 pt between
  targets and switch, so the faces sit 16 pt in (the pages' gutter) with 12 pt either side of the switch. On
  --dw-tab-bar, running up under the status bar, a hairline of --dw-border at its foot. `navigationTitle("Library")`
  stays, for the back button of a page pushed over it. The Navidrome gate and the moment before the path is known
  keep the system bar.
- **The offline banner under that top, not over it**: an inset applied later sits above one applied earlier, and
  TabStack applied the banner outside LibraryView. So TabStack takes `ownTop` (the Library's, true) and passes
  `showsOfflineBanner(false)`; LibraryView applies the banner itself - on the pager inside its top's inset, and on
  the gate, the spinner and the empty moment as before.
- **Find, shown on demand**: the `.searchable` drawer (`displayMode: .always`) is gone from the Library's root. The
  magnifying glass opens Find - its own TextField under the switch, for the page shown (`find(page)`, the prompt
  `findPrompt(page)`), focused in a `.task` once it is drawn (a focus asked before the field exists is lost), the
  keyboard up; tapped again while open, the field is focused again. Each page keeps its own words while it is open
  (a swipe or the switch shows the next page's). **Cancel** (LibrarySwitchWords.cancelFind) hides it and clears
  **every** page's words, not only the page shown's: the point is that a hidden Find never filters a list unseen, and
  words typed on Albums before a swipe to Playlists would otherwise stay on Albums with no field showing them. The
  keyboard's Search puts the keyboard away and leaves the words. A new person closes and clears it. The magnifying
  glass's VoiceOver label is the page shown's own prompt ("Find in albums", "Find in playlists", ArtistWords' and
  SongWords' findPlaceholder) - the app's existing words. All music's Artists/Albums/Songs, the Search tab, the EQ
  picker and the pressing picker keep their `.searchable` bars.
- **The switch, the app's own** (LibrarySwitchControl): iOS's segmented Picker can't be squared. The web's
  `.app-segmented` / `.app-segment`: a 32 pt well (--dw-segmented) of --dw-well with a --dw-border edge and its inset
  shade, segments 2 pt apart (--app-segment-gap), the chosen one --dw-toggled-bg under a --dw-toggled-border edge in
  --dw-accent-text, the others --dw-text-2, footnote semibold; the well and the segment both `Corners.control` (the
  web's segment is --dw-radius-tag, 3). Each segment is a Button with `.isSelected`; the whole is a `.contain`
  element labelled "Library pages", as the Picker was. A segment's target reaches 6 pt above and below the well
  (--app-segment-reach, a content shape of its own, never into the next segment). The chosen segment's tint slides
  between segments (`matchedGeometryEffect`) on any change - a tap, or the pager settling after a swipe - with
  `.snappy`, and moves at once under Reduce Motion; a tap moves the pager as the Picker's did (`withAnimation(.snappy)`
  unless Reduce Motion). It follows the order kept, so Edit order reorders it.
- **Playlists' + is the •••'s New playlist**: with a + on Playlists alone the switch would narrow on that page and the
  top would be uneven again. Core's `LibraryMenuItem.newPlaylist(online:)` is the page's own section on Playlists
  (as the orders are on Albums and Artists since question 26), dimmed while deadwax can't be reached, as the + was;
  it opens the same sheet. The empty Playlists page keeps its own New playlist button.
- **The circles** (CircleFace, ButtonFaces.swift): the secondary face (the look button's gradient, edge and top
  highlight, turned over while pressed) drawn round, 36 pt in a 44 pt target. The ••• is a `Menu` with
  `.menuStyle(.button)`, whose label takes the button style in use, its glyph `ellipsis` (it was `ellipsis.circle` in
  the bar: a circle in a circle now).
- **The tab bar, the app's own** (AppTabBar, MainTabs.swift): iOS's can't be reshaped (on iOS 26 and later it floats,
  a glass capsule), so `.toolbar(.hidden, for: .tabBar)` on each tab's NavigationStack, its root and every page
  pushed (appRoutes) - on all three, so no push brings it back - and AppTabBar is an overlay on the TabView's foot:
  the tabs in one HStack, each its symbol (filled, as iOS's bar draws them) over its words, --dw-tab-item 49 tall,
  --dw-tab-pad 4 above, --app-tab-side 8 either side, --app-tab-gap 3 between; the one shown --dw-accent, the others
  --dw-tab-inactive; --dw-tab-bar under them running down under the home indicator; a hairline of --dw-border along
  its top. The TabView stays, for each tab's state; a tap is `AppNavigation.select` (another tab, or back to the root
  and then the top). **The tabs are one list**: `AppTab.allCases` draws the bar and MainTabs' `ForEach` builds the
  stacks, each tab's words and symbol on AppTab, its stack in MainTabs' `stack(_:)` - Phase 6's Requests is one case
  there (the compiler names every switch it must join).
- **The keyboard**: the bar `.ignoresSafeArea(.keyboard)`, so it stays down under the keyboard as iOS's did. The
  mini player still rides the keyboard (an overlay in the stack's safe area). MainTabs hears
  keyboardWillShow/WillHide and, while it is up, sets `tabBarRoom` to 0: the player sits on the keyboard and the pages
  make no room for a bar that's under it.
- **The room at a page's foot**: `tabBarRoom` (the bar's height as drawn, above the home indicator - measured with
  `onGeometryChange`, so it follows the text size) is an environment value from MainTabs; TabStack pads the player
  overlay by it, and `playerClearance` is now the player's height (while drawn) plus it - so every list's last row,
  and the Library's letter index (an overlay in the page's safe area), end above the mini player and the bar. With
  nothing playing the room is the bar's alone.
- **VoiceOver**: the bar is a `.contain` element with `.isTabBar`; each tab a button with its words, `.isSelected` on
  the one shown. **Dynamic Type**: the bar's words and symbols grow up to `.xxxLarge` and hold there, and each tab
  shows itself in the Large Content Viewer on a long press at the accessibility sizes (iOS's own bar grows less and
  does the same).
- **The mini player**: `Corners.card` (12 before), its cover `Corners.art` (6).

### The switch at the largest text sizes (the fallback chosen)

The segments' words are footnote semibold and grow with the text size up to **`.accessibility1`**, then hold (the
switch's `dynamicTypeSize(...accessibility1)`); a title too long for its segment **shrinks to 70%**
(`minimumScaleFactor(0.7)`), **then truncates at its end**; at the accessibility sizes a long press on a segment
shows its title large (Large Content Viewer). The well grows from its 32 pt with the words. The two circles' glyphs
grow up to `.xxxLarge` and hold, the faces a fixed 36 pt, each with the Large Content Viewer too. Why accessibility1:
by then footnote is about 23 pt, so a 70% Playlists still fits a third of an iPhone's width less the circles; past
it the top would take a fifth of the screen to say three words that the Large Content Viewer says better.

### Corners, before and after

**Since 15 Nov every "after" below is 0**, the primary button and the secondary pill's with them: James asked for
actual corners, and Corners' five went to 0 (see "Actual corners (15 Nov)"). The table still says which kind each
place takes.

| where | before | after |
| --- | --- | --- |
| the album page's, the playlist page's and the album you don't have's cover (the hero) | 10 | art 2 |
| Now Playing's cover | 12 | art 2 |
| the Library's tiles | 6 | art 2 |
| rows' covers: albums, songs, playlists (and a playing song's shade), the picker's, an artist's and a MusicBrainz artist's albums, Search's rows and Top results' empty place, Downloads', Up Next's | 4 | art 2 |
| Search's albums under a song | 3 | art 2 |
| the mini player's cover, Up Next's playing card's, Info's album card's | 6 | art 2 |
| the mini player | 12 | card 4 |
| the notice (D11), Up Next's "loading earlier" | capsule | card 4 |
| the first ask (Downloaded) | 12 | card 4 |
| a list that couldn't be asked again, the sign-in's reason | 10 | card 4 |
| the song you searched for, on its album's tracklist | 8 | card 4 |
| the sign-in's fields, the pressing picker's button | 10 | control 4 |
| the "In your library" badge | 6 | control 4 |
| the maybe (dashed), a pressing's track mark, Up Next's Shuffle and Repeat, the EQ's held value and handle numbers | capsule | control 4 |
| the New mark | 4 | control 4 |
| `.bordered` buttons (Try again on lyrics and the EQ's two pickers, See All music, Keep them / Remove), Paste | iOS's own; Paste a capsule | control 4 (`buttonBorderShape`) |
| the primary button and the secondary pill | 4 (PrimaryButton.radius) | 4, unchanged (= control) |
| the switch's well and segments | iOS's segmented control | control 4 |
| the Library's Find field | iOS's search bar | control 4 |
| the EQ slider's track (4 pt wide) | capsule (2) | track 2 |
| You > Downloads' bars: track, fill | 2, 1 | track 2, fill 1 |
| the download control's stop square | 18% of its side (about 1.6) | fill 1 |
| the tab bar | iOS's (a floating glass capsule on 26+) | square, full width |

**Round, kept round**: the lyrics' and the letter index's dots, You's avatar, **artists' pictures** (a person's
picture, as the web draws them - `is-round` - and in Search's one list the circle is what tells an artist's row from an
album's; the brief's "every album or artist cover" was read as the album covers on an artist's page, and this is one
line in ArtistPicture to change if James wants them square), the download rings, the EQ's knobs and handles, the
pull's ring and disc, the Library's two circles. **The turntable's own**: TurntableFace.lookRadius (4) - the plinth's
look button and Now Playing's speed chip (square since "Actual corners", after its review) - and its icons, as drawn;
the scrubber was squared already (two Rectangles,
"Now Playing's bar, squared off"). The app icon is untouched. **Not squared, iOS's own**: grouped Lists' and Forms'
section corners (You, Up Next, Downloads, the EQ's pages), sheets, menus, alerts, the keyboard, and the system search
bars named above - SwiftUI has no say over those short of redrawing them.

### Where the phone departs from the web, on purpose

theme.css's --dw-radius-cover is 3 and --dw-radius-card 6; the phone's art is 2 and its card 4 - James asked the phone
to be squarer, and the web wasn't asked. test_ios_palette.py's `test_the_corners_are_the_squared_looks` holds that
both are below the web's, and that control (4), track (2) and fill (1) are the web's own - control also
PrimaryButton.radius, so the button test above stays truthful: the primary's corners didn't move. The switch's
segment is control (4) where the web's is --dw-radius-tag (3), as the brief set. The tab bar and the switch take the
web's colours and sizes, held by `test_the_apps_own_bars_are_the_webs` (and that iOS's bar is hidden in both places,
and the bar has `.isTabBar`).

### Tests

- **LibrarySwitchTests**: the •••'s sections on Playlists (New playlist, online and not), its words and `enabled`,
  `cancelFind`.
- **tests/test_ios_palette.py** (4 new): the corners and the web's; no radius, capsule or unsquared `.bordered` left in
  ios/App; the bars' colours and sizes from theme.css and app.css.

### Verified, and not

Verified, 14 Nov, on the Mac:
- `swift test` through the wrapper: 12, 1518 and 158 tests, all passed.
- The Debug and Release device builds (Xcode 27.2): succeeded, with no new warnings. The one warning is the
  appintentsmetadataprocessor line, which was there before.
- The .xcodeproj is unchanged; the two new files are in synchronized folders.
- check_project.py: ok.
- Node 22 `npm ci` and `npm run build`: ok.
- Every sim (87): passed.
- The full pytest: 4524 passed, 1 skipped.

Nothing has been seen on a screen: no simulator was used.

Not verified - only the phone can show (docs/ios.md's checks 200-209, numbered from 200 because Phase 6's are
written at the same time after 165):
- that iOS's tab bar stays hidden through pushes, pops and the swipe back on iOS 27, with no blank band where it was;
- that the overlay bar sits flush with the bottom edge, its fill under the home indicator, and its height reaches
  the pages (the letter index's foot, a list's last row) with the player and without;
- the keyboard: that keyboardWillShow/WillHide arrive as the Library's Find, Search, Server address and a sheet's
  field bring it up, and that the mini player then sits on it with no bar-sized gap under a list's end;
- that a horizontal pager with the navigation bar hidden lays its pages out under the top inset as it did under the
  bar, the pull still reading 0 at rest; that the field is focused with the keyboard up on the first tap;
- that `.menuStyle(.button)` draws the ••• with CircleFace on iOS 27, and the circles' and switch's look beside the
  web's; that the chosen segment slides, and doesn't under Reduce Motion;
- Dynamic Type at the largest sizes (the switch's shrink and truncation, the Large Content Viewer) and VoiceOver's
  reading of the bar, the switch and Find.

## Requests on the app's own tab bar (2026-11-15)

phase6-get merged ios at 90f4a13 (the squared look) after slice 1. The squared look draws its own tab bar
(AppTabBar, MainTabs.swift) from `AppTab.allCases`, each case its `title` and `symbol`, and hides iOS's on every
stack - so slice 1's `.tabItem` with `.badge(...)` and an accessibility label on its Label (the one way iOS's bar
could carry them) went, and Requests became a case like the rest:

- **AppTab.requests**: `RequestWords.tab`, `square.and.arrow.down`, between `.search` and `.you` (the web's order less
  Home, question 1); MainTabs' `stack(_:)` gives it `TabStack(path: paths.requests) { RequestsScreen() }`.
- **The badge** is drawn by AppTabBar on Requests' button alone: TabBadge, over the symbol's top right corner as the
  web's .app-tab-badge - --app-tab-badge 16 (its height and narrowest, scaled with caption2), --app-tab-badge-pad 4 a
  side, its left edge 2 right of the symbol's centre and its top 5 above the symbol's box (the web's 14 and -5 on its
  24 icon), --dw-badge-purple-bg over --dw-tab-bar (Palette.badgeFill over Palette.tabBar, so no stroke of the symbol
  shows through), a 1-point --dw-badge-purple-border edge (Palette.badgeEdge), --dw-accent-text in caption2 bold, a
  control's corners (Corners.controlShape). None at 0, and none offline (`RequestsModel.badgeCount` is 0 then).
- **What VoiceOver reads** is the button's own label now, "Requests, 2 arriving" (`RequestWords.badgeLabel`); the
  badge itself is hidden from it. The Large Content Viewer shows the same words. That settles slice 1's open question
  of whether a `.tabItem` Label's accessibility label reaches iOS's bar - it is no longer asked to.
- **The watch** is unchanged: MainTabs still hands `watching` to RequestsModel with `onChange(initial: true)` and
  `.hidden` as it goes.
- **Corners**: RequestCover clips with `Corners.artShape` (it was 4, a cover's old corner); nothing else of slice 1
  wrote a radius (the ✕'s and ▶'s faces are circles, round staying round).
- **Room at the foot**: Requests' root is a TabStack's root, so its List takes `clearsPlayer()`'s inset of the
  player's height plus `tabBarRoom` - its last card ends above both, as every tab's does. Pages pushed from it get
  the same from `appRoutes()`.

tests/test_ios_palette.py's `test_the_requests_badge_is_the_webs` holds the badge's colours to theme.css's, its sizes
and place to app.css's tokens, and its drawing to Requests' button and label.

Verified: swift test, a Debug device build, check_project, the sims and pytest (the merge commit's message has the
numbers). Not verified: the badge's look beside the web's, its place at the largest text sizes, and VoiceOver's
reading of it - checks 166 and 168 on the phone.

## Phase 6, slice 1's review (2026-11-15)

Six findings on slice 1 (and on its move to the app's own tab bar), fixed in one commit on phase6-get after it merged
ios at c8da2eb (main's 2.1.26).

1. **The poll could stop for good** (MainTabs). `.onDisappear { requests.watch(.hidden) }` had no `.onAppear`, and the
   way back relied on `onChange(of: watching, initial: true)` alone. If iOS takes the tabs away under Now Playing's
   full-screen cover (it is not documented either way), `watching` reads `.other` before and after, so onChange never
   fires on the way back and the model stays `.hidden`: no poll, the badge frozen until Requests' root or the
   background. **Kept the onDisappear and added `.onAppear { requests.watch(watching) }`.** The onDisappear is still
   needed: the tabs also go when the launch screen or the sign-in takes their place, and `asks` (launch ready, no
   sign-in over, a client) stops a look going out then but never starts one again - it is the `.hidden` in between
   that makes the return a change (`asksAgain(.hidden, .other)` asks once; back on Requests' root `open` turns, which
   asks). Under a cover that does take the tabs, the poll now rests while Now Playing is up and asks the moment it
   closes. Check 178.
2. **A dropped connection left stale in-flight entries** (RequestsModel). `letLooksGo()` cancelled the looks but never
   cleared `inFlight`, and a cancelled look returned at its `Task.isCancelled` guard before removing its release - so
   back in reach `DoneLooks.looks` skipped those releases for good, and `open()` skipped its songs ask. Now
   **DoneLooks.InFlight** (Core) holds each ask with a ticket: every way an ask ends - answered, failed or cancelled -
   ends its ticket first, before any guard; `letLooksGo` ends the tickets of what it lets go at once; a reset clears
   it. A ticket keeps an old ask that ends late from taking out a newer ask of the same release - the web's plain set
   (whose rejection handler deletes too) has that hole. The web also empties its set at every change of the tab's
   period; the phone no longer needs to, and doesn't, so a tapped row's songs ask still out stays in flight.
3. **A tapped Done row's songs ask was always let go.** `open()` asks for the songs (`period: nil`, to land wherever
   the app is) and then pushes the album page; the push makes `watching` `.other`, and `letLooksGo()` cancelled that
   very ask - so past the first five rows a ▶ never had its songs. That ask is now its own task (`tappedSongs`), out of
   what `letLooksGo` lets go, still guarded by the epoch (the person) and cancelled by a reset; it lands as the web's
   does (`() => mounted.current`). Check 179's last sentence.
4. **The accessibility sizes squeezed the words out** (RequestCards). The covers (44, 52) and the ✕'s and ▶'s faces
   (32) were `@ScaledMetric(relativeTo: .body)`, uncapped: at AX5 a cover was about 160 points and a title about 30,
   drawn as "…"; the two buttons of a question or of Needs attention sat side by side at one line each, cut to about
   five letters. Now the covers and faces are fixed (CardSizes, as LibraryRow.cover and Up Next's 44 are), the glyphs
   grow to xxxLarge and hold there, with the Large Content Viewer on a long press; a title takes up to 3 lines at the
   accessibility sizes; and a pair of buttons is a **ButtonPair** - ViewThatFits, side by side when both fit on one
   line each, one over the other otherwise, on up to 3 lines each at the accessibility sizes. The data line stays one
   line (it mustn't jump as the speed comes and goes). Check 179.
5. **Clear done's ids.** The finding said the web takes `finishedIds` of the visible list; it doesn't - its
   clearFinished (useDownloadJobs.ts, line 306) reads the hook's own `jobs` state (line 109), the jobs as polled, which
   is what the phone took. But the case it named is real on both: a second Clear done while the first waits for its
   poll takes the first's ids again, and if it fails it gives them back - the first clear's rows return until the next
   poll lands. **The phone now takes `RequestOverlays.toClear(polled)`, `finishedIds` of `visibleJobs`**: what a clear
   hides isn't taken again, so a failure gives back only what it took. This departs from the web on purpose; the web
   has the same flaw, and its fix would be main's (a patch of its own), after which the two agree again.
6. **Two collections grew** (minor). `lookTasks` is now keyed by ticket and each task is removed as it ends (and all
   at `letLooksGo`); `doneSince` is pruned at each answer to the jobs deadwax lists (**DoneLooks.kept**) - a row hidden
   by a clear waiting for its poll is still listed, so a clear rolled back doesn't make its rows look new.

Core: RequestsTests gains 5 (`aDoneRowsLookLetGoIsLookedForAgain`, `anOldAskEndingLateLeavesTheNewOneInFlight`,
`anAskEndsHoweverItEnds`, `aSecondClearDoneThatFailsGivesBackOnlyWhatItTook`,
`theDoneRowsTimesAreKeptOnlyForJobsStillListed`). `RequestRow.key(job:)` names the "job-<id>" key once, for jobRow and `kept`. The vectors are unchanged: InFlight,
`toClear` and `kept` have no counterpart on the web to hold them to (`finishedIds`, `visibleJobs` and `doneLooks` keep
theirs).

Not verified - only the phone can tell: whether iOS does take the tabs from under a full-screen cover (check 178
passes either way, if this is right); the cards at the accessibility sizes (179); and, as before, every in-app piece
only in the compiler.

## Noto Sans (15 Nov)

James chose the app's face from six set side by side, each drawn as the squared Library's top
(~/Library/Caches/deadwax-build/fonts/font-options.html). His pick was "Noto Sans (the web's)". The whole app now draws
its words in it. Fonts weren't part of the squared look; they were chosen separately and come after it, on the same
branch (square-look).

### The files: the web's own, made one font per weight

- **Nothing was fetched.** ios/scripts/make-fonts.py makes ios/App/Fonts from interface/styles/font/noto-sans/: the
  web's seven variable woff2 files (Noto Sans 2.015; weight axis 100-900) and its OFL.txt, copied unchanged.
- **Does iOS read a woff2 as it is?** This Mac's CoreText does: `CTFontManagerCreateFontDescriptorsFromData` gives
  each file's nine named instances. But that doesn't settle the bundle:
  - Every subset calls itself NotoSans-Regular (and NotoSans-Bold, and so on). Registered side by side, only the
    first would take; the rest are refused as the same name.
  - iOS has no unicode-range to choose between them.
  - Whether the phone's CoreText reads woff2 has never been tried.
- **So each weight the app draws is one TrueType font.** The weights are 400, 500, 600 and 700. For each:
  - each of the seven subsets is pinned at that weight (fontTools' instancer, `updateFontNames`);
  - the seven are merged into one font (fontTools' Merger), latin first, so its glyph wins a character two subsets
    share and its header and names are the font's.
- **Why static:** the Merger takes no variable font.
- **What came out** (sha256 as committed; the script reproduces them byte for byte, with the latin file's dates and
  no timestamp of its own):

  | file | bytes | sha256 |
  | --- | --- | --- |
  | NotoSans-Regular.ttf | 181,256 | `d0b2dcbc…eef0` |
  | NotoSans-Medium.ttf | 181,620 | `03ed4445…1169` |
  | NotoSans-SemiBold.ttf | 181,688 | `4782bd3d…9a61` |
  | NotoSans-Bold.ttf | 181,332 | `d3c95d22…83c7` |

  About 725 KB in all. Each has 2,022 glyphs: the subsets' shared glyphs are kept twice, renamed, by the Merger.
  Each maps 1,672 characters: exactly the union of the web's seven cmaps (tests/fixtures/font_cmaps.json).
- **The subsets: all seven**, not latin and latin-ext alone. Merged under one family there's no collision, and a
  Polish, Vietnamese, Greek or Cyrillic name is in the same face as the Latin beside it, as on the web. Anything
  else, such as Japanese, Korean or Arabic, falls through to iOS's face.
- **The tools:** fontTools 4.68.0 and brotli, in a venv of their own (~/Library/Caches/deadwax-build/fonttools-venv),
  never the repo's .venv nor anything system-wide.

### Registered by UIAppFonts

- Info.plist names the four (`UIAppFonts`).
- App/ is a synchronized folder, so the files are copied to the bundle's root, which is where UIAppFonts looks. This
  was checked in the built Deadwax.app: the four .ttf and OFL.txt are there at the root, byte for byte the committed
  ones, and the built Info.plist lists them.
- **The .xcodeproj is unchanged.**
- check_project.py now also checks:
  - UIAppFonts names exactly App/Fonts' .ttf files;
  - each of them is TrueType;
  - OFL.txt is there beside them;
  - no two resources in App/ share a name, since every one lands at the bundle's root.
- UIAppFonts was chosen over registering at launch: it is declarative, it is done before any view is made, and there
  is no code to fail.

### Typeface (ios/App/Shared/Typeface.swift): one layer, like Corners

- **Every text style iOS has**, at its size at the standard text size: largeTitle 34, title 28, title2 22, title3 20,
  headline 17 semibold, body 17, callout 16, subheadline 15, footnote 13, caption 12, caption2 11. Each is
  `Font.custom("Noto Sans", size:, relativeTo: <that style>)`, so it scales with Dynamic Type exactly as iOS's own
  style did.
- **The default:** the root is given `.font(Typeface.body)`, so a Text or control that sets no font is Noto Sans.
- **Weights: `.weight()`, `.bold()` and `Text.fontWeight()` work unchanged.** This was measured on this Mac (macOS 27.2, SwiftUI's
  ImageRenderer, the four faces registered for the process): `.custom("NotoSans-Regular").weight(.semibold)`,
  `.weight(.medium)`, `.weight(.bold)`, `.bold()`, `Text.bold()` and `Text.fontWeight(.semibold)` each draw
  **pixel for pixel** the named face (NotoSans-SemiBold and so on), and so does the family name with a weight. The
  web's variable woff2, registered alone, moved along its axis the same way.
  - The phone's SwiftUI is the same code, but it hasn't been seen there: check 211.
  - So the 80-odd call sites kept their `.weight(...)`. Only `.medium`, `.semibold` and `.bold` are used, and each
    has its face.
- **Figures:** Noto Sans's are tabular as they are. Every digit is 572 thousandths wide (`1111` and `0000` measured
  the same width), so the times and track numbers hold still. `.monospacedDigit()` is kept where it was; it changes
  nothing drawn (measured).
- **The exceptions are kept by name, through Typeface:**
  - `Typeface.symbol(.style)` / `symbol(size:weight:)`: an SF Symbol drawn alone keeps iOS's own font, which is how
    a symbol is sized. 47 sites were classified by the head of their modifier chain being an Image, plus DownloadMark
    (always a symbol), a label style's icon and CircleFace's label. A symbol inside a Label or a container takes
    the container's Noto Sans at the same point size, as any text beside it does.
  - `Typeface.mono(.style)`: data (ids, paths, versions, an error's detail, Debug's values, the turntable's time
    line) keeps the system's monospace, as before. The web's Noto Sans Mono isn't bundled; doing that is a follow-up.
  - The turntable's Canvas readouts (`UIFont.monospacedSystemFont`) are its own drawing, left alone.
- **Section headers and footers:** all 94 got an explicit `Typeface.footnote`, iOS's size for both. A List's style
  sets its headers' text itself, so the root's font can't be relied on to reach them, and if it did they would turn
  body-sized. InfoView's six string-titled sections became header closures. A Menu's sections (QueueMenu,
  DownloadControl) are UIMenu titles and were left.
- **UIKit, `Typeface.configureUIKit()`,** called in AppDelegate's didFinishLaunching. It sets only the font, and uses
  the legacy appearance properties, not a UINavigationBarAppearance, so that iOS 26+'s own bar look is untouched.
  The faces:
  - large titles Bold 34;
  - inline titles SemiBold 17;
  - bar buttons and the back button Regular 17;
  - UISearchTextField Regular 17;
  - segmented controls Regular 13, the chosen segment SemiBold 13.

  Each is scaled with UIFontMetrics at launch, so a text size changed while the app is open reaches the bars at
  the next launch (check 214).
- **What can't take a font:** menus, alerts, confirmation dialogs, swipe actions and PasteButton are iOS's own and
  stay in iOS's face.

### Where it looks different

- **Wider and taller.** At the same point size Noto Sans is about 6% wider than SF (a 40 pt sample: 824 against 775
  px) and its lines about 17% taller (55 against 47 px: Noto's ascent and descent are 1069 and 293 thousandths).
  Rows grow a little, and text truncates a little sooner where room is tight (check 217).
- **Bold Text isn't followed.** With `legibilityWeight` bold, SF regular drew as SF semibold, but Noto Sans,
  static or variable, drew unchanged (measured). SwiftUI applies Bold Text to the system font only. Following it
  would mean every weight resolved by Typeface from the environment, which is a larger change than this one, and
  it was left (check 216).

### Tests

tests/test_ios_palette.py has four new tests:
- **The fonts are the web's own:**
  - the four files, and Info.plist's UIAppFonts;
  - OFL.txt byte for byte the web's;
  - each name table's family "Noto Sans" and PostScript names equal to Typeface.Face;
  - each font's cmap, parsed by hand (the suite has no fontTools), equal to the union of the web's seven.
- **Every text style's size and `relativeTo:` are iOS's own,** the root font is set, and configureUIKit sets each
  appearance.
- **No system text font is left in ios/App:** no leading-dot style in a `.font(...)` once Typeface.symbol and mono
  are set aside, no `.system(` or custom font of its own, no style handed on as a value, no bare `.monospaced()`,
  and no UIKit font but the turntable's. A slipped-back `.subheadline` fails it (tried).
- **Every List section's header and footer takes Typeface,** and only a menu's section is titled by a string.

### Verified, and not

Verified on the Mac: see the commit, which has the checks' results. Not verified: anything on the phone (checks
210-217): the face itself on iOS 27, its weights, the alphabets, the navigation bars' and search fields' fonts on iOS
27's bars, the section headers' size, Bold Text, and where Noto's extra width and height crowd a layout.

## The play bar on the tab bar (15 Nov)

James, on his iPhone at app 0.11, in this order:

- "merge the play bar with the bottom bar so it doesn't look like it's floating";
- "I would like to be able to swipe on the title to skip forward and backward while also being able to seek. let's
  put the progress on top of the play bar";
- "opaque the whole way";
- "get rid of the skip forward button";
- "dragging up or tapping on the title should bring up the play page. let's make sure the play/pause isn't right up
  against the edge as well, so its easily pressable".

Built on `square-look` after Noto Sans (68b4b97). **The app stays 0.11 (11)**. src/__init__.py is untouched (2.1.26,
from ios's c8da2eb). There is no server change, and the engine files are untouched. The only new playback action is
the swipe right's "the song before": QueueController's own move, made from Previous's rules without its restart.
Next and seek are the ones already there.

### What changed

- **The mini player is the tab bar's top** (AppTabBar, MainTabs.swift):
  - It is one VStack: MiniPlayerView while something is queued, a hairline of --dw-border, then the tabs.
  - The whole block sits on --dw-tab-bar, solid, running down under the home indicator. The `.regularMaterial` card,
    its corners and its 8 pt inset are gone, so nothing of the page shows through.
  - With the play bar there, its seek line is the block's top edge; the 1 px hairline along the top is drawn only
    with nothing queued. Nothing queued, the bar is exactly as it was.
  - `.isTabBar` and `.contain` moved onto the tabs' HStack, so VoiceOver reads the play bar as its own elements
    before the tab bar.
  - The `.dynamicTypeSize(...xxxLarge)` cap now covers the block (see the decisions).
- **The play bar** (MiniPlayerView, rewritten):
  - The cover, flush left, the bar's full height, `Corners.art`.
  - Then the title (subheadline semibold) and PlayerWords.secondLine (footnote, quiet).
  - Then Play/Pause alone: a 48 pt wide target, the bar's full height tall, with 14 pt past it to the screen's edge.
    Its glyph (title2) and spinner are as they were, and it shows itself in the Large Content Viewer. The Next button
    is gone.
  - The row is `max(60, @ScaledMetric(relativeTo: .subheadline) 60)` tall, so it and the cover grow with the two lines.
- **BarTitle** (the cover and the words; one gesture area):
  - A tap opens Now Playing (`.onTapGesture`).
  - A `DragGesture(minimumDistance: PlayBar.decideAfter)` reads its direction once, on its first change
    (PlayBar.way), and keeps it: across, up or down.
  - **Across**: the words follow the finger (an offset inside a clipped column, on the words' own view, so the words
    leaving keep where the finger left them and the new song's come in from the column's edge). Toward a song that isn't there
    (PlayerModel.hasSongBefore / hasSongAfter) they follow a third of the way (PlayBar.followed).
  - On letting go, PlayBar.skip decides. Left is `player.next()`, right is `player.songBefore()`, and anything else
    springs back. The words carry `.id(entry.key)` and a transition chosen by `sliding`, which is set while the drag
    goes across (so the words leaving already carry it) and cleared once the key has changed. The old words leave
    one way and the new ones come in from the other, `.animation(value: entry.key)` on the column alone. A song that
    changes by itself, or from the lock screen, changes the words at once, as before. Under Reduce Motion they fade.
  - **Up**: Now Playing opens on letting go, if PlayBar.opens. **Down**: nothing.
  - A drag the system takes away (the `@GestureState`, as ScrubberView's) skips and opens nothing, and springs back.
  - VoiceOver: one element, "Now playing: Roads, Portishead - open" (PlayerWords.miniPlayerLabel, as before), a
    button whose activation opens Now Playing. Its actions are "Next song" and "Previous song", each only while there
    is a song that way.
- **SeekLine** (along the top edge; a view of its own, so only it redraws as the position moves, as Hairline did):
  - At rest, a 2 pt line of --dw-border with the part played in the accent, its top on the bar's top edge.
  - A 16 pt touch area centred on it, an overlay, so it adds no room and reaches 7 pt over the page. (Replaced after
    review: see "The play bar after review (15 Nov)" - the line takes no touch now.)
  - A finger on it: 8 pt thick, and a tag over the finger, "1:23 / 4:56" (PlayerWords.barTime). The tag is caption
    with monospaced digits, on --dw-tab-bar with a --dw-border edge and `Corners.control`, 6 pt above the line and
    kept 8 pt from the screen's sides.
  - Every rule is Scrub's, as ScrubberView's: dragStart, dragMove, dragEnd (one seek, on letting go), dragFor (the
    song changing drops it), the cancel, and `shownPosition` holding the target until it lands. One rule is the bar's
    own (see the decisions).
  - VoiceOver: adjustable, "Position in the song", "0:12 of 5:00" (the scrubber's words), PlayBar.adjusted's 10 s.
- **The room** (TabStack):
  - `tabBarRoom` is still AppTabBar's measured height, which now includes the play bar and the hairline under it.
  - PlayerInset became NoticeInset, which holds only the notice. `playerClearance` is the notice's height (while one
    shows) plus `tabBarRoom`, so the two add up to the block and a list's last row clears it.
  - The seek line's reach over the page and its tag are overlays, overlap rather than room.
- **The keyboard**: the block keeps `.ignoresSafeArea(.keyboard)`, so the play bar now stays under the keyboard with
  the tabs, and `tabBarRoom` is 0 while it's up. The notice still rides the keyboard.
- **Core**:
  - `entryBefore(_:)` (UpNext.swift): backward()'s entry at position 0, past Repeat One's copies, or nil.
  - `QueueController.toEntryBefore()`: catchUp, then Previous's move without its restart.
  - **PlayBar.swift**, the gestures' rules and numbers.
  - PlayerWords: `nextSong`, `previousSong`, `barTime`.
  - PlayerModel adds `songBefore()` (as next(): cancelRetry, act, startTicking), `hasSongBefore` and `hasSongAfter`
    (onward, or Repeat All with a queue). previous() is unchanged.
- Corners.swift's comments: the play bar is no longer a card.

### Decided here (the brief left these open, or this departs from it)

- **Now Playing opens on letting go; it doesn't follow the finger.** It is a `fullScreenCover`, which can't be driven
  by a drag. Following the finger would mean presenting Now Playing as the app's own overlay: its dismiss drag, the
  turntable's full screen, and the sheets over it would all move with it. That is a larger change than this one.
  Check 224 asks whether it feels wrong.
- **A tap on the seek line seeks nowhere.** ScrubberView seeks on a tap, but the line's 16 pt touch area reaches 7 pt
  over the page's foot and 9 pt into the title's top, where a tap means a row or Now Playing. A seek there would jump
  the song by surprise, so a touch must move PlayBar.seekSlop (4 pt) across before it seeks. It still thickens and
  shows the time at once. (Replaced after review: see "The play bar after review (15 Nov)".)
- **The keyboard covers the play bar.** It used to ride the keyboard as a card. As one block with the tabs, it goes
  under the keyboard with them, as Music's does. Check 202 now says so, and the notice still rides the keyboard.
- **The cap covers the play bar.** The mini player had no Dynamic Type cap; the block now holds at `.xxxLarge`, the
  tab bar's, so the joined block can't take half the screen at the accessibility sizes. Play/Pause has the Large
  Content Viewer. The title has none, since its long press would fight the drag.
- **The numbers**, all in PlayBar:
  - a direction is read after 10 pt;
  - a skip at 50 pt, still going that way, or a flick whose predicted end is past 120;
  - Now Playing at 40 pt up, still going up, or a flick past 120;
  - a third of the way toward a song that isn't there;
  - the line's slop is 4 pt and its VoiceOver step 10 s (the scrubber's is 5).
- **"Right always goes to the song before"** is entryBefore: past Repeat One's copies as Previous does, with History
  following (wentBack). At the first song (or with only copies before it) the title springs back. Left is Next's own
  rule, Repeat All's next time round included.
- **The actions only when there's a song that way**, so VoiceOver never offers one that does nothing.
- **"Mostly horizontal"** is a drag that has moved more across than up or down by the time it is read. The bar
  isn't in a scroll view, so no vertical scroll is there to steal; the 7 pt of the line's touch area over the page is
  the only overlap, as the brief set it.

### Tests

- **PlayBarTests** (13):
  - the way, read once past 10 pt (a tie isn't across);
  - left is next and right is before;
  - under the threshold, or flung back, it springs back;
  - a flick skips;
  - the resistance, and which way has a song;
  - a drag up opens, and a short or reversed one doesn't;
  - the line's slop;
  - VoiceOver's 10 s, and the song's ends;
  - the words;
  - entryBefore on a plain queue.
- **QueueControllerSongBeforeTests** (6):
  - the song before at 30 s, a skip and never a seek;
  - at the first song nothing moves;
  - paused stays paused;
  - History's floor follows, as Previous's does;
  - a join no change has seen is caught up first;
  - Repeat One's copies are passed over.
- **tests/test_ios_palette.py**, `test_the_play_bar_is_the_tab_bars_top`:
  - AppTabBar draws MiniPlayerView, and nothing else does;
  - no material or card in it;
  - no Next or Previous glyph;
  - its 60, 48 and an edge of 12-16 pt;
  - both VoiceOver actions.

### Verified, and not

Verified on the Mac: see the commit, which has the checks' results. Nothing has been seen on a screen, since no
simulator was used.

Not verified, so only the phone can show (docs/ios.md's checks 218-227, and 228 since the review):
- that the block sits flush and opaque, the cover flush, and Play/Pause easy to hit one-handed;
- that the 16 pt touch area above the bar takes a finger, with the overlay offset outside the block's frame, and that
  the tag sits where it should;
- that `.onTapGesture` and the drag share the title as intended, with no tap after a swipe;
- that the transition chosen during the drag is the one the leaving words take on iOS 27, and that the slide looks
  right;
- the thresholds' feel;
- VoiceOver's reading and actions;
- that `tabBarRoom` measured with the play bar reaches every list's foot;
- the keyboard over the block.

## Requests on Noto Sans and the play bar (2026-11-15)

phase6-get merged ios at 9a7fc74 - Noto Sans (68b4b97) and the play bar on the tab bar (f5aea9b) - after slice 1's
review. Slice 1 was folded onto both:

- **Noto Sans**: every `.font` of the Requests files goes through Typeface, mapped as the rest of the app is - a title
  `Typeface.body.weight(.semibold)`, a line `Typeface.footnote` (the data line `.monospacedDigit()` on it), the card's
  question `Typeface.subheadline`, the cards above the rows `Typeface.headline` over `Typeface.callout`, an error's
  detail `Typeface.mono(.footnote)`, the ✕'s and ▶'s glyphs `Typeface.symbol(.footnote).weight(.semibold)` (a symbol
  drawn alone keeps iOS's face), and TabBadge's count `Typeface.caption2.weight(.bold)`. The board's section headers
  and You > Getting albums' header and footer take `Typeface.footnote`, as every list's do. ButtonPair names no font:
  its pills' faces are ButtonFace's.
- **The play bar on the tab bar**: AppTabBar draws the mini player at its top, a hairline, then the tabs; TabBadge
  stays on Requests' button in the tabs' row, under the hairline. It rises 5 points above the symbol's box: at the
  standard text size that is inside the row (its 4-point top padding and the button's room around a 44-point symbol
  and name); from about the larger sizes, where the symbol and name fill the 49-point button, it can reach a point
  above the row, onto the line - check 179 asks. `tabBarRoom` is now the whole block's height,
  so Requests' last card, like every page's, ends above the play bar and the tabs (TabStack's `clearsPlayer()`).
- **The watch**: MainTabs' `onChange(of: watching, initial: true)`, `.onAppear` and `.onDisappear` merged unmoved, on
  the TabView as before: check 178 holds as written.
- The guide's tabs paragraph names four tabs and the badge over ios's new words for the block; checks 166 and 179 ask
  that the last card clear the whole bar at the foot, and 179 that the badge sit clear of the play bar.

Not verified - only the phone can tell: Requests in Noto Sans beside the web's, and the badge under the play bar.

## The play bar after review (15 Nov)

A review of Noto Sans and the play bar (merged into ios as 9a7fc74, installed on James's phone) found four things.
The fix is built on ios's 8939ad9 (Requests merged). AppTabBar is untouched, so Requests' badge stays as it was.

### 1. The seek line took too much (high)

**What was wrong.** SeekLine's 16 pt touch area (7 pt over the page, 9 pt into the bar) was an overlay with
`DragGesture(minimumDistance: 0)`, and its slop counted only the width. As a result:
- a scroll, or a drag up, that began in it and drifted 4 pt sideways sought the song;
- a tap on the last row's bottom 7 pt was lost;
- a tap on the top 9 pt of the cover, the title or Play/Pause did nothing.

**The fix: one drag for the whole bar, inside the bar, read once; the line drawn only.**
- MiniPlayerView holds the bar's only gesture: a `.highPriorityGesture` DragGesture with `minimumDistance:
  PlayBar.decideAfter` (10 pt) on the row, `.contentShape(Rectangle())`.
- At its first change it is read once and kept until it is let go. Its way comes from PlayBar.way, and its role from
  where it began, `PlayBar.role(way, startY:, onTitle:)`:
  - across from the bar's top `PlayBar.seekReach` (14 pt) is a seek;
  - across from the cover or title below that is a skip;
  - across from Play/Pause is nothing;
  - up from anywhere on the bar opens Now Playing;
  - down does nothing.
- A tap is never this drag, because it never moves 10 pt. The high-priority drag fails at lift, and the tap is the
  cover's or title's (`.onTapGesture`, Now Playing) or Play/Pause's (its Button), wherever on them it lands, the
  top edge included.
- SeekLine is `.allowsHitTesting(false)`, drawn only, and keeps its accessibility element. Nothing above the bar is
  hit-testable, so the page just above it keeps its taps and its scrolls.

**Why this, and not the alternatives:**
- A narrower band alone would still have swallowed taps on what it covered.
- Forwarding a tap by its x could reach the cover, title and Play/Pause, but never a list row on the page above. SwiftUI
  can't pass a touch to a sibling under an overlay.
- A window-level UIKit pan that never cancels touches could have kept the band over the page. It would have had to
  arbitrate with every list's swipe actions and scroll view.
- With one gesture, the views underneath keep their own taps and the direction is read once.

**14 pt.** That is the line (the top 2 pt) and the room above the title's letters. At the standard size, the two lines
of words are 40 pt tall, centred in 60, and the title's capitals begin about 15 pt down; at larger sizes the bar grows
and they sit lower. A swipe on the words is a skip, and one along the top edge is a seek.

**What it costs.** A thumb aimed at the line now has to land on the bar (its top 14 pt), not above it. Check 220 asks
whether the line is still easy to catch. If it isn't, the reach can grow into the bar, at the cost of the top of the
title's swipe.

**Seek's rules are unchanged.** It still follows Scrub: dragStart at the point the drag is read across, dragMove,
dragEnd (`.up`) once at lift, dragFor by track, the cancel on a system takeover, and `shownPosition`'s hold. The drag
lives in MiniPlayerView and is handed to SeekLine (`SeekLine(drag:)`). Only during a drag does MiniPlayerView redraw;
SeekLine alone still reads the position. PlayBar.seekSlop and `seeks(moved:)` are gone: the drag's reading replaces
them.

### 2. A swipe across a song change skipped twice (low)

**What was wrong.** BarTitle kept `way`, `offset` and `sliding` across a song change mid-drag, and acted at lift on
whatever was playing then. A swipe held across a join could therefore skip the song after.

**The fix.**
- The drag's Hold keeps the entry's key from its first reading.
- From then on, a change of the entry playing drops the drag: the words spring back, and any seek's finger is let
  go. It stays dropped until the finger is lifted.
- At lift, `PlayBar.atLetGo(role, began:, now:)` turns a seek or a skip into nothing when the key differs. Opening
  Now Playing doesn't depend on the song, so it still opens.
- PlayBarTests holds both rules.

### 3. UIKit's fonts grew without a cap (medium)

**What was wrong.** Typeface.uiFont used `UIFontMetrics.scaledFont(for:)` with no maximum. At AX5 the inline title
and bar buttons (headline and body, 17) reached about 53 pt in a 44 pt bar, and a segmented control's 13 reached
about 44 pt in a 32 pt control.

**The fix.**
- `uiFont` now uses `scaledFont(for:maximumPointSize:)`. The cap is `Typeface.cap`, the style's size at
  `.extraExtraExtraLarge`, the tab bar's own cap: 23 pt for the 17s, 19 pt for the 13s.
- At 19 pt, Noto's line is about 26 pt, which fits a 32 pt segmented control. At 23 pt the inline title's line is
  about 31 pt in a 44 pt bar.

**The large title is left uncapped** (`capped: false`), on UIFontMetrics' own curve, which is iOS's: 34 pt at the
standard size, 40 at xxxLarge, 60 at AX5 by Apple's Dynamic Type table.
- Noto's line at 60 pt is about 82 pt against SF's about 72.
- Whether UINavigationBar's large-title area grows to fit that taller line, or clips it, isn't something this Mac
  can show: UIKit's bar isn't on macOS. Check 227 asks.
- As far as I know, iOS's own inline title and bar buttons stay at 17 pt at every text size (iOS shows them in the
  Large Content Viewer instead). Ours growing up to 23 pt is more than iOS's own, but within the bar, as the review
  asked.

### 4. VoiceOver's order (a guess)

**What was wrong.** The line's frame starts 7 pt above the bar (drawn there still, centred on the line), so VoiceOver
might have read it first.

**The fix.** The row is now `.accessibilityElement(children: .contain)`, with `.accessibilitySortPriority` 3 for the
title, 2 for Play/Pause and 1 for the line. Check 225's order is set explicitly, not left to the frames.

### Docs

docs/ios.md:
- The Playing section's line paragraph now states what holds. Only a sideways drag that starts on the mini player
  seeks. A tap there is what's under it. A drag up there opens Now Playing. The page just above the mini player is
  the page's.
- The swipe's paragraph says a swipe held across a song change springs back.
- Check 220 asks for the thumb on the top edge, and taps there; check 222 asks for a swipe held across a join.
- Check 214 says what stops growing, and check 227 asks about the bars' fonts at the largest sizes and the big
  titles.
- **New check 228**, scrolling near the mini player: a scroll started just above it, a tap on a row's bottom edge, and
  a drag up from its top edge.

### Tests

- **PlayBarTests**: the slop test is replaced by five tests.
  - Across from the line's reach is a seek.
  - Below the reach it is a skip on the title, and nothing over Play/Pause.
  - Up from anywhere opens Now Playing, and down does nothing.
  - A skip or a seek across a song change does nothing.
  - Opening doesn't depend on the song.
- **test_ios_palette.py**:
  - The bar's test now holds one DragGesture, high-priority, with the minimum distance and no `minimumDistance: 0`;
    the line with `allowsHitTesting(false)` and no gesture; and the three sort priorities.
  - The Typeface test holds the cap: `maximumPointSize:`, xxxLarge's trait, only the large title `capped: false`,
    and the tab bar's own `.xxxLarge`.

### Verified, and not

Verified on the Mac: see the commit, which has the checks' results.

Not verified, so only the phone can show:
- that the high-priority drag lets taps through to the title and to Play/Pause at once, its top edge included, with
  no lag felt (check 220);
- that a scroll started just above the bar is the page's (check 228);
- that a thumb catches the line within the bar (check 220);
- the sort order VoiceOver follows (check 225);
- the bars' fonts at the largest sizes, and the large titles (check 227).

## Phase 6, slice 2: Get and Sources (2026-11-15)

notes/ios-specs/phase6-get-requests.md 2.8-2.10, 3.4, 3.5 and 6.2. Before it, an album you don't have showed its
pressings on the phone but was got in the web app. Now:
- **Get the album** under the chosen pressing's facts on GroupView (where "Phase 6's Get the album goes here" was), and
  under it **the store line**: what the store and the downloads already have of that pressing, from
  `/download/store_state`, which searches nothing;
- **the Sources sheet**, "Choose a source": Soulseek searched for that pressing (`/download/find_candidates`, with the
  person's Format), every folder a card - its score, folder and peer, Speed, Tracks, Quality, Size, Starts, what's
  missing - and behind a tap on the score its reasoning; the chips (from the person's quality floor) and the sort;
  Search again; every state's line;
- **a card's Get**: `/download/enqueue` asked in the tap, the pending row up in Requests from that moment, the sheet
  closing onto Requests' root.

On `phase6-get` from `ios` at 8939ad9 (slice 1 merged), then fast-forwarded to 90f2964 (the play bar after review).
src/__init__.py untouched; the app stays **0.11 (11)**; the .xcodeproj is unchanged (App/Get/ and the two new models
are in the synchronized App folder). ROUTE_COUNT 54 -> 58: `/download/store_state`, `/download/find_candidates`,
`/download/enqueue` and `GET /me/preferences`, every one on the server already. There is no server change.

### Core (DeadwaxCore)

- **GetRelease.swift** (new): releasePayload.ts and release.ts - what a Get sends. `GetGroup` and `GetRelease.group`
  (`getGroup`: the group's title, first date and credit, from Search's preview or the pressings' own), and
  `GetRelease.build` (`buildDownloadRelease`): the pressing's title, credit (`creditName`, `currentName`, `creditIds`),
  year and original year, every track (`GetTrack`: position, title, length, disc and disc position, artist, the video
  flag), the disc titles, format, country (its first event's area code, raw), catalogue number, label, packaging and
  `detectEditionTags` - or the group's fallback with no pressing. Encoded with `FindCandidatesRequest`'s field names.
- **MusicBrainz.swift**: what a Get needs that the page didn't read - a track's own credit, its recording's credit and
  video flag, each release event's country and the packaging - all read leniently, nil where MusicBrainz gave none (an
  empty credit kept as one: JavaScript's `[]` is truthy, so a track credited to nobody is "N/A", not its recording's).
- **StoreLine.swift** (new): candidates.ts `storeStatus` and `storeNotes`, perPerson.ts `storeStatusFor`, `withoutJoin`
  and the quality floor's word (`floorVerdict`, `floorNote`), with `StoreStateAnswer`, `HeldPressing`,
  `DownloadInFlight` and `OtherPressing`, read leniently (an answer missing a field is never a failure). And the
  phone's own `withoutAdd` and `drawn` - below.
- **GetSettings.swift** (new): getSettings.ts - `readGetSettings`' three values (`GetMode`, `QualityFloor`,
  `FormatPreference`, the route's defaults for anything wrong), `floorFilters`, `sourceChips` (`chips`), the phone's
  `candidateFilters` and `pressedCount` - without Match details' minimums and the sample-rate floor, which are the
  web's desktop panel's own (a phone-wide window of the web app has neither, docs/downloading.md).
- **Sources.swift** (new): candidates.ts and the sheet's and a card's words. `Candidate`, `FindCandidatesAnswer` (the
  store's four keys read off the same answer), `FindCandidatesBody` (the release flat, with the Format and an edited
  query), `EnqueueBody` (the folder, the release searched for, up to ten runners-up as shown, the quality),
  `EnqueueAnswer`; `CandidateFilters`, `QualityFilters`, `CandidateSort`; and `Sources`' rules - `passes`, `sorted`,
  `best`, `band`, `percent`, `queryOverride`, `speedFact`, `startsFact`, `qualityText`, `tracksText`, `size`,
  `signalChips`, `editionTags`, `missingLine`, `quality`, and every state's line and the announcement.
  `SourcesWords`: the words the web builds inline in Sources.tsx, SourceCard.tsx and ReleaseGroupPage.tsx, read from
  their source by the exporter - and three of the phone's own: `percent` (a score as drawn, for the App, which can't
  see WebText), `subtitle` (ReleaseGroupPage.tsx's, a template literal there), and VoiceOver's `expanded`/`collapsed`.
- **Whose.withStoreLine** (whose.ts): the folders held, each with whose it is as the store line says, so the meta line
  ("in your library", "in the collection") never disagrees with the line under Get. **GroupPage** takes `store:` - the
  last answer and the pressing it was for - and lays it on only for the pressing shown.
- **Routes.swift**: the four routes in `all`, with their times to answer: `storeState` 20 s (the store's look may ask
  slskd how far a download has got), `findCandidates` 180 s, `enqueue` 30 s; the preferences keep the default.
  180 s is above what deadwax may take: two rounds of slskd's search at SLSKD_SEARCH_TIMEOUT's top (60 s) plus its 17 s
  of bookkeeping each, and the 8 s it gives the former-names lookup - 162 s (test_the_app_waits_for_a_search...).
  **Both were wrong, and are 300 s since the review** (below): the 162 s left out deadwax's search gate, and the
  enqueue has no bound on the server at all.
- **DeadwaxClient**: `storeState(_:)`, `findCandidates(_:)`, `enqueue(_:)` (a 409 is deadwax's "already downloading" or
  "already in your library", a 502 slskd's refusal, each thrown with its words) and `getSettings()`.

### Held to the web: by the exporter, or by hand

`ios/scripts/export-get-vectors.cjs` compiles lib/releasePayload.ts, lib/release.ts, lib/pressings.ts,
lib/candidates.ts, lib/getSettings.ts, lib/perPerson.ts, lib/whose.ts and lib/format.ts, with what they import, and
reads the words that live in components (Sources.tsx's, SourceCard.tsx's, ReleaseGroupPage.tsx's Get the album,
permissions.ts's GET_OFF) from their source. It writes Fixtures/get/get-vectors.json (3.6 MB, every choice seeded):
- the speed bar's full rate and the score bands; every word;
- what each of the main page's two Find buttons sent (tests/fixtures/payloads/find-buttons.json): 8 cases, the body
  the one builder makes of each and of the album as a whole;
- `getGroup` over the real pressings (tests/fixtures/pressings/): 76 groups, with and without Search's preview, each
  pressing chosen and none, and each body;
- 120 seeded groups and pressings with every edge a payload has, and their bodies;
- 96 edition-word cases (JavaScript's `\s` included) and 65 video-flag cases;
- 200 store answers: `storeStatus`, `storeStatusFor` at every floor, `withoutJoin`, `storeNotes`, each download's
  progress, copy and floor verdict; 80 `withStoreLine` cases;
- 200 seeded folders, every fact a card draws and its reasoning;
- 120 seeded answers through seeded chips and every sort: what passes, in what order, the best, every state's line
  and the announcement;
- `sourceChips`, `floorFilters` and `pressedCount` for every floor and set of chips; 9 settings answers; 11
  searching lines; 24 query overrides.

`ui/test/iosget.sim.cjs` runs it with `--check`; `GetVectorTests` (15) replays it.

By hand (`GetTests`, 11): `withoutAdd` and `drawn` (the web has no case without Add - every page of its gives it -
so the vectors can't hold it); a Get's body flat with its Format; a card's Get sending the next ten as shown, itself
left out; a real `find_candidates` answer read; an enqueue's two answers (a job, a join); the four requests' methods,
paths and times; a refused enqueue thrown in deadwax's words; the meta line taking the store line's word only for the
pressing shown; the sheet's subtitle; a score as drawn.

### The app

- **GetSettingsModel** (Models/, new): You > Getting albums as kept on deadwax - `ask()` shares the read in flight
  (one per person, `epoch`-guarded), `format()` waits for it (else asks once) and gives the Format a search is scored
  by, the defaults if deadwax can't say; `floorNow` the chips' start. Asked as the album's page shows; nothing is
  seeded on the phone (spec 2.12: slice 3 brings You's three choices). Reset with the person.
- **SourcesSearch** (Models/, new): one search per Get - `start`, `requery` (an edited query only:
  `Sources.queryOverride`), `stop` (the request cancelled, which stops it in slskd too: the route's `unless_abandoned`),
  and only the newest run lands. `download()` allows one Get per search.
- **SourcesSheet** (Get/, new): a NavigationStack sheet, "Choose a source" with Cancel; the subtitle; the chips in a row
  that scrolls sideways (`ChipFace`: a 30-point face in a 44-point target) and the sort's Menu; then the states in a
  LazyVStack - asking, an error (ErrorNote in a listener's words, Try again), the store's status in the cards' place
  (held whole or downloading whole: nothing was searched), notes, nothing lossless, nothing found (the query there to
  edit), none through the chips (Clear filters), the cards and the line saying what was searched, and Search again.
  The chips start as the floor and are re-made from it if its word lands after the sheet opened, unless one was tapped
  since. Each outcome is announced (`Sources.announcement`).
- **SourceCardView** (Get/, new): the score toggle (green from 75, amber under, the chevron turning; "92% match",
  expanded or collapsed, to VoiceOver), the folder and "from <peer>", Get (`PrimaryFace` for the best match only -
  edged in `Palette.best` - `TintedFace` for the rest, each named "Get <folder> from <peer>"), the speed's well and bar,
  the facts in a `ViewThatFits` (side by side, two by two, one over another), what's missing in amber, and the
  reasoning last on the card (the edition words in a wrapping layout, each signal's badge and meaning), so opening it
  moves nothing above.
- **StoreLineView** (Get/, new): the box - its title (green for held), its lines - and the notes under it; nothing at
  all with nothing to say.
- **GroupView**: Get the album (`PrimaryFace(large: true)`) and the store line under the pressing's facts, nothing
  before a pressing is chosen; GET_OFF without Get albums; offline, no Get and `StoreLine.offline` in the line's place
  (only for someone who could Get). The line is asked (`.task(id: StoreAsk)`) on the pressing, `RequestsModel.filed`,
  the page shown (its tab current, no sheet, the app active), reachability and the person; the last answer for the same
  pressing stays until the new one lands; a new title is announced while the page shows. The sheet is `item:`-driven
  (`GetRequest`, a new id per Get, so the same album got twice searches twice).
- **RequestsModel**: `enqueue(_:)` - the pending row (`pending-N`) laid with `withPending` and drawn at once, then
  `.job(id)` settled (and the pending key expired once the job is seen) or the row dropped for an answer with no job,
  or `.refused` with the words `ErrorWords.of` gives (RequestWords.enqueueBroke as the fallback) - and the poll kicked.
  `filed` counts each answer that filed something, for the store line.
- **AppNavigation.showRequestsRoot()**: Now Playing closed, the Requests tab, its stack at the root.
- **Palette**: `card`, `label`, `best`, `barGreen`/`barGrey` (gradients), `dangerFill`/`dangerEdge`, each commented with
  its web token (test_the_sources_sheet_is_drawn_in_the_webs_colours).

### Decided here (the spec was silent, or this departs from it)

- **No Join, no Add, no auto-pick** (slice 3's). So the phone draws `StoreLine.drawn` - `withoutJoin`, then the phone's
  own `withoutAdd` - and the box never says "Join it" or "add it" above no button; "In the collection, not in your
  library" stays as the title, as it's still true. Every Get shows the sources, whatever When I tap Get says. The
  quality floor's line keeps the web's "getting a copy of your own isn't offered yet", which is the web's own word.
- **Search again is built here**, not in slice 3: the web's sheet has it under folders found, and leaving it out would
  have stranded "Nothing found" with no way on. The spec's slice 3 "Search again with your own words" is done.
- **The hand-over to Requests happens in the sheet's `onDismiss`**, after the sheet has gone - switching the tab while
  a sheet is presented from a tab not about to be shown is the kind of thing SwiftUI drops or animates oddly.
- **The store line is asked again whenever the page shows**, not only as the pressing is chosen - so a Get, a cancel
  in Requests or a filing elsewhere is said on coming back; the last answer stays meanwhile so the line doesn't flash.
  Another pressing's answer never stands for the one shown (the web's `said` check).
- **Offline: no Get at all**, and `StoreLine.offline` ("Getting albums works once deadwax is back.") where the line goes -
  only for someone with Get albums; without, GET_OFF stands as ever.
- **Get albums' preferences aren't seeded on the phone**: until deadwax answers, the chips start empty and the Format
  is the route's default; the floor landing late re-makes the chips unless touched.
- **The enqueue's refusal words**: a 409 is deadwax's sentence, said as a retry's refusal ("It's already
  downloading."); anything else through `ErrorWords.of` with the downloads as its service.

### Tests

- **GetVectorTests** (15) and **GetTests** (11), above. **FixtureFiles** knows the new fixture.
- **ClientTests**: `Routes.all` 58, and the three new times to answer (its first full run failed on both, still
  slice 1's 54 routes and times - fixed).
- **tests/test_ios_contract.py**: ROUTE_COUNT 58; a Get sends only what `FindCandidatesRequest`, `EnqueueRequest`,
  `Alternative`, `Track`, `Quality` and `EnqueueFile` declare, and everything they need (pydantic drops the rest without
  a word); the store's word within what `_nothing_here`, `held_copy`, `describe_job` and `other_pressings` build, each
  struct read leniently; a search within `_serialize_candidate` and both `find_candidates` returns; an enqueue's two
  returns and its 409 and 502; GetSettings within the preferences route, its defaults the route's; the 180 s; and
  `find_candidates` and `enqueue` needing `request` (Get albums), as the app's Get does, while `store_state` needs
  nothing more.
- **tests/test_ios_palette.py**: the new colours against theme.css and drawn where the web draws them.
- **iosget.sim.cjs**: the exporter's `--check`.

**Mutations** - each rule broken on purpose, GetTests and GetVectorTests run, the rule put back. All 12 were caught:
1. `withoutAdd` keeping the add line (`withoutAddDropsTheLineTellingYouToAddIt`);
2. `drawn` keeping Join's line (`somebodyElsesDownloadIsSaidWithNoJoinUnderIt`);
3. a part held said as held whole (`theStoreLineIsTheWebs`);
4. the green band from 70 (`theNumbersAreTheWebs`, `aCardSaysWhatTheWebsSays`);
5. nine runners-up (`aCardsGetSendsTheFolderAndTheNextTenAsShown`);
6. an unedited query overriding (`onlyAnEditedQueryOverrides`);
7. 320 kbps always a chip (`theChipsAreTheWebs`);
8. "after 1 others" (`aCardSaysWhatTheWebsSays`);
9. Highest quality sorted worst first, 10. Complete albums only letting a gap through, and 12. Starts now ignored
   (`theListPassesSortsAndSaysWhatTheWebsDoes`);
11. the subtitle keeping an empty part (`theSheetsSubtitleIsTheTitleAndThePressingEitherLeftOutWhenEmpty`).

The App's own wiring (the sheet, the asks, the hand-over) has no tests: it is SwiftUI's, and the rules it applies are
each tested in Core.

### Verified, and not

Verified, on the tree before its commit:
- `swift test`: Core 1602, Audio 158, Turntable 12. No warnings. (Its first run failed ClientTests' two route tests,
  still slice 1's - fixed, above.)
- The unsigned Debug and Release device builds (Xcode, `generic/platform=iOS`) succeeded, with no warnings but the
  usual appintentsmetadataprocessor line. The .xcodeproj is unchanged; `check_project.py` ok.
- `npm run build` and all 89 sims on Node 22.23.4, iosget's `--check` among them.
- The full pytest suite: 4550 passed, 1 skipped (test_ios_contract's six new tests and test_ios_palette's one among
  them); the tests that read the docs, the iOS ones and test_source_bytes run again after the last doc edits: 482
  passed.
- The 12 mutations above, each caught.

Not verified - only the phone can tell (docs/ios.md's checks 180-192):
- Real slskd and real Soulseek: a search's answer, a refusal, an enqueue's - every slskd here is a fake, and Sources
  has been seen only against fakes (CLAUDE.md's Next up 2).
- The sheet closing and the tab switching in `onDismiss` on a device: whether it reads as one movement, and whether
  the Search stack is where it was on coming back.
- Whether a search cancelled by Cancel or a swipe really stops in slskd (the route's `unless_abandoned` on a dropped
  connection, over WireGuard).
- VoiceOver: the store line's and the sheet's announcements heard whole as the views redraw; the score's disclosure
  read as "92% match, collapsed".
- The cards and the chips at the largest text sizes, and `ViewThatFits` choosing as intended.
- The in-app pieces themselves have run only in the compiler: no Simulator is used here.
- CI's Xcode 26.6 (the older Swift). The new code spells out its closures' types and keeps each `#expect` small.

## Phase 6, slice 2's review (2026-11-15)

Five findings, fixed on phase6-get after 41f62c6, in one commit. The review found the contract matching the server field
for field and the vectors regenerating byte for byte.

### 1. The Sources sheet ignored Reachability (high)

The cards kept live Get buttons while deadwax was out of reach, and a Get then closed onto a Requests tab that, offline,
shows only "Requests show once deadwax is back." - so whether the Get failed was never seen. Now the sheet reads
Reachability:
- out of reach, "Getting albums works once deadwax is back." (StoreLine.offline, the album page's own words) at the top
  of whatever it shows, and announced as deadwax goes;
- the cards found before dimmed (`Palette.dimmed`), and every card's Get off (`SourceCardView.gets`), as are Try again
  and Search - and `get()` refuses in the tap too, so nothing hands over to Requests;
- back in reach, all of it live again, and Search again is under the cards as ever;
- a search that failed while deadwax was away (nothing answered, or not in time - `ErrorWords.kind` .offline or .timeout,
  looked at only as deadwax comes back) searches again by itself.

docs/ios.md said a sheet already searching "says it can't connect". It doesn't, at once: the request waits until
URLSession gives up. The guide now says so, and check 188 asks it.

### 2. The enqueue's 30 s was the phone's alone (high)

deadwax puts no bound on `/download/enqueue`: it waits for the release's lock, then for slskd's enqueue (no timeout of
its own), which answers once the peer is reached - and the web's fetch has no timeout. So a slow peer past 30 s left a
refused "didn't start" row that never reconciled, beside the real job under Waiting. Now:
- `Routes.timeouts[enqueue]` is the search's, 300 s (test_ios_contract holds them equal, and that the route and slskd's
  enqueue still set no bound);
- an answer that never came (`RequestOverlays.unanswered`: ErrorWords' .timeout class - URLSession's own, or a proxy's
  408 or 504) isn't settled as refused: the row stays "starting…" (`stoppedWaiting`), and the poll keeps going for it
  while nothing else is active (`looksForAJob`, in the poll's `hasActive`);
- every poll looks for its job (`claimed`, before `reconcile`): a job not listed when the request was asked
  (`PendingDownload.listedBefore`), for the same pressing (`releaseMbid`) - its own folder from its own peer first
  (`directory`, `username`), else any (with logins on, the download deadwax joined it to). One job goes to one request,
  and the row goes as an answer's would;
- `RequestOverlays.unansweredSeconds` (600 s) after the tap with no job found, it is given up on (`gaveUp`): Needs
  attention, "no answer", and RequestWords.mayHaveStarted - "deadwax didn't answer in time, so this may have started
  anyway. If it doesn't appear here soon, get it again." Clear done takes it; a job showing later still claims it.

The web has none of it (its request never times out), so it is held by hand: GetTests'
`onlyAnAnswerThatNeverCameIsUnansweredRatherThanRefused`, `aGetWhoseAnswerNeverCameStaysStartingAndIsLookedFor`,
`aPollFindsTheJobOfAnUnansweredGetByItsPressingAndFolder` and `givenUpOnAnUnansweredGetSaysItMayHaveStarted`.
PendingDownload's four new fields are optional, so the web's vectors decode as before.

### 3. The 180 s search timeout could be shorter than deadwax's worst case (medium)

The 162 s left out the search gate - every start waits its turn at SEARCH_GATE, up to SEARCH_TURN_SECONDS (30 s) - and
the time outside `_run_searches`' sleeps, which are all `max_wait` counts. The worst case, from the server's own
numbers in test_the_app_waits_for_a_search_as_long_as_deadwax_does:
- round one: two starts (the credit and the current name) behind the gate, 60 s, then max_wait (SLSKD_SEARCH_TIMEOUT's
  top, 60, plus the route's 17) and 15 s of margin for slskd's state asked each half second, the answers fetched and the
  searches deleted - 152 s;
- round two: one former name's start, 30 s, then the same 77 + 15 - 122 s;
- the former-names lookup, 8 s, counted whole though it runs beside round one; and 10 s for the store's look before and
  the ranking after.

That makes 292 s, and the phone's search is given 300 s. The test reads every number from the server: the gate's bound,
the range's top, each round's `max_wait` allowance (two of them), the lookup's budget. It checks that the rounds are
still each start behind the gate, and that Routes.swift's comment says "292 s at worst". It fails if any of them grows
past 300. An artist renamed more than once starts a search behind the gate for every name; deadwax bounds none of it as
a whole, so this is the worst case of an artist renamed once.

### 4. Dynamic Type cut the facts short (low)

`Fact`'s value was one line even in the one-over-another fallback, so "FLAC, MP3 VBR 128-320k" ended in "…" at the
accessibility sizes. It now has the folder name's treatment: up to three lines at those sizes. ViewThatFits measures a
text's one-line width whatever its limit, so which layout is chosen doesn't change. Check 190 asks for it.

### 5. A Get could be dropped without a word (low)

`RequestsModel.enqueue` returned quietly with no client, and the sheet still closed onto Requests. It now says whether
the Get started (`-> Bool`, nothing laid down when it didn't). The sheet hands over only then; otherwise it stays, with
the error in a listener's words ("Can't connect to deadwax.", ErrorNote with the downloads as its service), and another
tap may ask again (`SourcesSearch.downloadAgain`).

### Docs

docs/ios.md's Getting an album:
- the offline paragraph, rewritten (finding 1);
- a paragraph on a Get whose answer doesn't come (finding 2);
- the facts at the largest sizes (finding 4).

Its checks:
- 188 asks the sheet offline;
- 190 asks the facts whole;
- a new 192 asks a slow peer, if one comes along.

The troubleshooting table has a "no answer" row.

### Tests

- GetTests: the four above, and the client's two times to answer (300 s each).
- ClientTests: the times.
- test_ios_contract.py: the search's worst case recomputed (finding 3), and the enqueue's.

**Mutations**: each rule broken on purpose, the tests run, the rule put back. All were caught:
1. `unanswered` taking an offline failure for no answer;
2. `claimed` matching a job listed before the tap;
3. `claimed` ignoring the pressing;
4. `claimed` giving one job to two requests;
5. `gaveUp` acting on a row still waiting for its answer;
6. `looksForAJob` counting a refused row;
7. the may-have-started row drawn as a refusal ("didn't start");
8. the enqueue's timeout back to 30 s;
9. SEARCH_TURN_SECONDS raised on the server (the contract test fails: the phone's 300 s no longer covers it).

### Verified, and not

Verified, on the tree before its commit:
- `swift test`: Core 1606, Audio 158, Turntable 12. Its first run of the Get tests failed GetTests' two times to
  answer (still 180 s and 30 s); fixed.
- The unsigned Debug and Release device builds succeeded, with no warnings but the usual appintentsmetadataprocessor
  line. The .xcodeproj is unchanged; `check_project.py` ok.
- `npm run build` and all 89 sims.
- The full pytest suite: 4550 passed, 1 skipped. After the last doc edits, the tests that read the docs, the iOS ones
  and test_source_bytes were run again: 482 passed.
- The 9 mutations above, each caught - the ninth on the server's own file, put back (src/ has no diff).

Not verified - only the phone can tell:
- whether a dimmed card and its dimmed Get read as "from before" (check 188);
- what URLSession does with a search in flight as WireGuard drops - an error at once or only at 300 s;
- a real slow peer (check 192): whether one ever takes long enough for any of this to show.

## Phase 6, slice 3: Join, Add, the pick and You's three (2026-11-15)

notes/ios-specs/phase6-get-requests.md 2.11, 2.12 and 6.3. Before it, the store line said what deadwax had of a
pressing but offered nothing to do about it, every Get showed the sources whatever When I tap Get said, and You's three
were set in the web app. Now:
- **Join this download**, under a download somebody else asked for (`POST /download/jobs/{job_id}/join`) - on the
  album you don't have's page (with Get albums) and in the Sources sheet's box;
- **Add to my library**, under a pressing the store holds that isn't yours (`POST /me/library/add`, the Get's release),
  on both;
- **Pick the best source for me**: on a fresh Get, the best match through the chips at 75 or more downloaded as a
  card's Get is, the sheet closing onto Requests - or why not said above the sources;
- **You > Getting albums**: When I tap Get, Quality floor and Format chosen on the phone, saved to deadwax
  (`PUT /me/preferences`) in turn with the reads, each shown at once.

On `phase6-get` from `ios` at b7ef21d (slice 2 merged). **The app is 0.12 (12)** (Base.xcconfig, check_project.py,
ios.yml, test_ios_install.py). src/__init__.py untouched; the .xcodeproj unchanged (AutoPick.swift is in the package,
the App files in the synchronized folder). ROUTE_COUNT 58 -> 60, both routes on the server already: **no server
change**.

### Core (DeadwaxCore)

- **AutoPick.swift** (new): candidates.ts' `AUTO_GRAB_MIN_SCORE` (75) and `autoGrabPick` (the list through the filters
  in the sort, its top only at 75 or more - `Sources.percent`, the web's `Math.round(score * 100)`), `autoPickBlocked`
  (downloading, held whole, part downloading, part held, read off the answer in that order; then no tracklist, then no
  release id), getSettings.ts' `PICK_SORT` (best match) and `notPickedLine` (nil with nothing found - the empty state
  says it), and `Sources.autoPick(fresh:mode:answer:release:filters:)`, useCandidateSearch.ts' `run` after the answer
  lands as one pure decision: `.off`, `.picked(candidate, list:)` or `.notPicked(line)`.
- **GetSettings.swift**: `GetSettingsAnswer` (the three and `can_save`, true unless deadwax says false - a struct of
  its own, so GetSettings stays the three the contract holds), `GetSettingsAnswer.shown` (useGetSettings' `shown`:
  deadwax's last word with every choice still being saved laid over it in the order made, over the defaults before it
  answered; nil with neither), `GetChoice` (only what was chosen encoded - `encodeIfPresent`, never a null, as the
  extra="forbid" Preferences takes it), `GetSettings.with`, `GetMode.label`, `FormatPreference.youOrder` and `label`,
  and `GettingWords` (the three titles, You's note, GETTING_UNSAVED with "Tell whoever runs deadwax." for anyone but
  whoever runs it, and the two problems' leads).
- **StoreLine.swift**: `withoutAdd` gone - the phone has Add wherever the web does; `addedStatus` (perPerson.ts: "Already
  in your library", the add line gone, `add` kept so the button's place keeps its words); `drawn(_:floor:joins:)`
  (Join only for someone with Get albums); `StoreWords` (Join's and Add's three words each).
- **Routes.swift**: `joinJob` (POST, 60 s - it waits for the same release's lock as an enqueue or Another source, which
  can be held while slskd is asked; a second Join is harmless, `joined` false) and `savePreferences` (PUT, the
  transport's 8 s, as the read). 60 routes.
- **Sources.swift**: `JoinAnswer` (status, job_id, joined), read leniently.
- **DeadwaxClient.swift**: `getSettings()` answers a GetSettingsAnswer; `saveSettings(_:)`, `joinJob(_:)` (no body) and
  `addToLibrary(_ release: GetRelease)` (the Get's release, FindCandidatesRequest's fields - the web's line sends
  `download.release`).

### Held to the web: by the exporter, or by hand

`ios/scripts/export-get-vectors.cjs` adds, at the end of its vectors so the earlier ones' seeded randomness is unchanged:
- `AUTO_GRAB_MIN_SCORE` and `PICK_SORT`; Join's and Add's words read out of StoreState.tsx (and `ADDED_WORDS`, and
  that the added state draws it); You's section, its three titles (GettingChoices.tsx), `GET_MODES` and `FORMATS`,
  the note read out of You.tsx (whitespace collapsed), GETTING_UNSAVED with how its tell is joined, and the two
  problems' leads out of useGetSettings.ts;
- four `can_save` answers among the settings (13 in all);
- 161 picks: 160 seeded answers - every store state, releases with and without tracks and ids, seeded chips - through
  `autoPickBlocked`, `autoGrabPick` (by PICK_SORT) and `notPickedLine`, and one with no answer at all;
- 120 store answers at every floor: `storeStatusFor`, and `addedStatus` of it.

The fixture grew from 3.7 to 4.8 MB. `iosget.sim.cjs` runs the exporter with `--check`; `GetVectorTests` (18) replays it.

By hand (`GetTests`, 21): what the vectors can't reach - the box drawn with Join only for Get albums (`drawn`'s
`joins`, which no web rule has) and Add under the collection's pressing; `Sources.autoPick` as the hook decides it
(fresh only, the mode, the chips deciding what passes, 74.49 not picked, a pressing held, the album as a whole, nothing
found); `GetSettingsAnswer.shown` (nothing shown before either, choices laid over in order, over the defaults, can_save
deadwax's alone); `GetChoice` sending only what was chosen; the client's join (POST, no body, 60 s), save (PUT, the
body) and Add (the Get's release, tracks and all); a refused Join thrown in deadwax's words.

### The app

- **GetSettingsModel**: `confirmed` (deadwax's last word), the choices still being saved, `answer`/`settings`/`canSave`
  as `GetSettingsAnswer.shown` lays them; `choose(_:)` shows at once and saves behind it; `ask()` shares a read in
  flight; every read and save in one line (`inTurn`: each starts once the one before has answered), so a read's answer
  is never older than a save before it; a read that fails keeps what was known, and only with nothing known is it a
  problem; a save refused leaves `saveProblem` until the next choice. `problem(admin:)` says either through
  `ErrorWords.notice` with useGetSettings' leads. `epoch`-guarded across a person change.
- **GettingAlbumsSection**: three Sections of rows (PlaybackSection's checkmark rows), When I tap Get under "Getting
  albums", then Quality floor, then Format in You's order, with the note, the unsaved line, the problem (announced as
  it appears) and - the phone's own - `StoreLine.offline` while deadwax can't be reached; then Confirm before
  cancelling. The rows are off (faded to `Palette.off`, `.disabled`) until deadwax has answered and while it can't be
  reached; a tap on the chosen one sends nothing.
- **YouView**: the three asked as You appears, on a pull (with /me) and as deadwax comes back into reach.
- **StoreLineView**: `onJoin` and `onAdd`. Without `onJoin`, `withoutJoin` (as StoreState.tsx). Each button is a
  `StoreActionButton` keyed as the web keys it (Join on the job, Add on the first line): idle, busy ("Joining…",
  faded to the new `Palette.busy` 0.75 - --app-job-busy - a second tap nothing), done (the words, announced); a refusal
  as an ErrorNote in `Palette.danger` under it, announced, the button back.
- **SourcesSearch**: `start(_:client:settings:picking:)` - a Get, Try again, and (until the review below) the search
  again by itself when deadwax comes back - gives a `Picking` (the chips read as the answer lands, and how to
  download); `requery` never does. As a fresh answer lands, `Sources.autoPick` with When I tap Get as it is then (the read before the search has
  landed by then). `notPicked`, reset by every search; `landed`, one more per answer.
- **SourcesSheet**: `begin` hands the search its Picking (`GetSettings.candidateFilters(filters)`, and `get`, which
  now says whether it asked); the box (`storeBox`: `drawn` with `joins`, `addedStatus` once Add added from this very
  answer - `addedFrom == landed`); the not-picked line above the sources; the announcement with it; Join (`requests.join`
  then `onQueued`) and Add (`library.add`, then `addedFrom`, and Search's owned marks asked again).
- **GroupView**: Join (only with `can(.request)`) and Add in the line; after either, `changed` moves the store's
  `StoreAsk`, so the line is asked again; an Add also asks Search's owned marks. The sheet's hand-over now checks the
  sheet still shows the Get that called it (`getting?.id == request.id`), so a Join answering after the sheet closed
  opens nothing.
- **RequestsModel.join(_:)**: the Join, then a look at once (`kick`) - nothing laid over the board, deadwax's next answer
  lists the job as the person's. **LibraryModel.add(_:)**: the Add, then `libraryChanged()`.

### Decided here (the spec was silent, or this departs from it)

- **Join only with Get albums, Add for anyone** - the web's pages give `onJoin` only then and `onAdd` always; deadwax
  refuses an Add in words where it can't (with logins off the box never offers it: everything is yours).
- **Join waits 60 s**, Another source's time: the route takes the release lock an enqueue or a retry holds while slskd
  is asked. A second Join is harmless.
- **The sheet's Join hands over to Requests; the page's doesn't** (the web's): the page asks the store again and the
  line becomes yours.
- **After an Add, the follower isn't told** (DownloadModel.libraryChanged takes Navidrome's album id, which the store
  line doesn't have): your library downloaded on the phone learns of it at its next read, as of an Add in the web app.
- **You's rows are off until deadwax answers and while it can't be reached** - the web's rows are off only until it
  answers; the phone also can't save offline, and says why with the sheet's words. A tap on the chosen row saves
  nothing (the web's saves the same value again).
- **Nothing is seeded from the phone**, as slice 2. A save here writes SEEDED on deadwax (every save does), so a browser
  that still has the old main page's settings won't carry them over afterwards - the main page retired at
  2.0.0-player.66, so only a browser untouched since then could.
- **The pick's enqueue that can't be asked at all** (no deadwax to ask) says nothing of not picking: the sheet's
  `getFailure` says why over the sources, as for a card's Get. The web's `ask` can't fail that way.
- **The search that runs again by itself as deadwax comes back** was made fresh here, on the reasoning that the Get's
  first answer never landed. That was wrong (the review's finding 1): the search that failed can be a search again
  by hand, after a first answer did land, with the chips loosened and words typed - and a fresh Get empties the field
  and may pick. It now runs again as the very search it was (After review, below).
- **The checks are 193-199, then 229-232**: 200-228 went to the look's builds while Phase 6 was being written.

### Tests

- **GetVectorTests** (18) and **GetTests** (21), above. **ClientTests**: `Routes.all` 60, the one PUT, `joinJob`'s 60 s.
- **tests/test_ios_contract.py**: ROUTE_COUNT 60; JoinAnswer within the join route's one literal, its five 409s and
  its 503 in words, no body, Get albums its permission (and the page and the sheet giving Join only with it), its time
  at least Another source's; the line's Add sending the GetRelease to a route that takes FindCandidatesRequest, with
  everything it needs; GetChoice exactly the extra="forbid" Preferences' keys, each enum the route's Literal and
  PREFERENCES, never a null; `can_save` read from `_answer`, which both routes return; the save's two 503s.
- **tests/test_ios_palette.py**: `Palette.busy` the web's --app-job-busy, and the box drawing it, the secondary pill
  and the danger colour.
- **tests/test_ios_install.py**: 0.12 (12).

**Mutations** - each rule broken on purpose, GetTests, GetVectorTests and ClientTests run, the rule put back. All 12
were caught:
1. a pick from 70 (`theNumbersAreTheWebs`, `aFreshGetSetToPickAsksForTheBestMatchThroughTheChips`);
2. held whole read before downloading (`aPickIsTheWebsAndSoIsWhyNot`);
3. a not-picked line with nothing found (`aPickIsNeverMadeForAPressingHeldOrOnItsWayOrUnjudgeable`, the vectors);
4. a search again picking (`aFreshGetSetToPickAsksForTheBestMatchThroughTheChips`);
5. the pick by Highest quality (`theNumbersAreTheWebs`);
6. no tracklist ignored (the hand test and the vectors);
7. the added box dropping Add (`theBoxOnceAddedIsTheWebs`, `theCollectionsPressingIsSaidWithAddUnderIt`);
8. Join for everyone (`somebodyElsesDownloadHasJoinOnlyForSomeoneWhoGetsAlbums`);
9. a choice sending a null for what wasn't chosen (`aChoiceSendsOnlyWhatWasChosen`, the client's);
10. the older choice winning (`aChoiceShowsAtOnceLaidOverDeadwaxsLastWord`);
11. a missing `can_save` read as false (`theSettingsAreReadAsTheWebReadsThem`, the client's);
12. a Join given the transport's 8 s (`joinSaveAndAddAreAskedAsTheServerDeclaresThem`, ClientTests' times).

The App's wiring (the sheet's pick, the buttons' states, the in-turn line) has no tests of its own: it is SwiftUI's
and Swift concurrency's, and every rule it applies is tested in Core.

### Verified, and not

Verified, on the tree before its commit:
- `swift test`: Core 1615, Audio 158, Turntable 12. No warnings.
- The unsigned Debug and Release device builds succeeded, with no warnings but the usual appintentsmetadataprocessor
  line; the built app's Info.plist reads 0.12 (12), as ios.yml checks. The .xcodeproj is unchanged; `check_project.py`
  ok.
- The exporter's `--check`; `npm run build` and all 89 sims on Node 22.23.4.
- The full pytest suite: 4555 passed, 1 skipped (test_ios_contract's three new tests and test_ios_palette's new lines
  among them). Its first run of the new contract tests failed one count - the join route raises five 409s, not four
  (cleared since is said at three moments) - fixed. After this write-up, the tests that read the docs, the iOS ones
  and test_source_bytes were run again.
- The 12 mutations above, each caught, every file put back.

Not verified - only the phone, and a real deadwax, can tell (docs/ios.md's checks 193-199, 229-232):
- a Join and an Add against a real deadwax with two people signed in, and the line asked again after each;
- the pick against real Soulseek answers - whether 75 through the floor's chips picks what a person would (CLAUDE.md's
  Next up 2: Sources is seen only against fakes);
- the sheet closing onto Requests as a pick lands, read as one movement; and whether a pick landing while VoiceOver is
  saying the sheet's line is heard;
- You's rows at the largest text sizes, and their "Selected" and "dimmed" to VoiceOver;
- a save refused by an unwritable database (check 230) - seen only in the contract's reading of the route;
- CI's Xcode 26.6 (the older Swift). The new code spells out its closures' types and keeps each `#expect` small.

### After review (2026-11-15)

The review found nothing high, and SEEDED checked out (the web's own save writes it too). Its four points, fixed in
one commit after 8ab48af:

1. **Coming back could pick after a search again.** The sheet's search that runs again by itself as deadwax comes
   back called `begin` - a fresh Get, which may pick - whatever had failed. But the failed search can be a search
   again by hand: chips loosened, words typed, WireGuard drops, and on its return the sheet picked an MP3 under the
   floor and closed, untapped. And `start` empties the query field, so the typed words were gone too. Now Core's
   `SourcesRun` names what ran (`.fresh`, or `.requery(override:)` with the query it sent), `picks` is true only for
   `.fresh`, and `SourcesRun.onReturn(run, error:)` gives the very run back for an offline or timed-out failure and
   nothing otherwise. SourcesSearch keeps `lastRun` (and a fresh Get's Picking), and `rerunOnReturn` runs a requery
   as itself - its override, the field untouched, no Picking - and only a fresh Get through `start`. The chips were
   never reset there (only `onAppear` sets them). Try again stays a fresh Get, which may pick, as the web's is.
2. **Join and Add were live offline in the sheet, and a pick landing offline was dropped without a word.**
   `StoreLineView(live:)` turns both off (`.disabled`, the pill's off face) while the sheet says deadwax is out of
   reach - a button already asked keeps waiting for its answer - and the box dims with the cards. `Picking.picked`
   now answers a `Sent` (`asked`, `offline`, `notAsked`): the sheet's closure answers `offline` before asking
   anything, and the search says `Sources.notPickedOffline` ("deadwax went out of reach as the sources came in -
   choose a source yourself once it's back.") above the sources, in the not-picked lines' own form, and to VoiceOver
   with the outcome. Nothing picks later: `rerunOnReturn` runs only after a failure, and this search answered.
3. **A Join that timed out read as refused, though it may have landed.** On an answer that never came
   (`RequestOverlays.unanswered`: URLSession's timeout, a 408 or 504), the box says `StoreWords.joinUnanswered`
   ("deadwax didn't answer in time, so you may have joined it anyway. If it isn't in your Requests soon, join it
   again.") in the secondary colour, never the danger one, and keeps the button - a second Join is harmless. The
   sheet asks `/store_state` again first: `StoreLine.joinLanded` (that very job, `yours` exactly true) hands over to
   Requests as a Join that answered does. The album page asks its line again (`changed`), which then shows the
   download as yours. `RequestsModel.join` kicks the board however it ends (`defer`, epoch-guarded). **Add** the
   same: `addUnanswered`, `StoreLine.addLanded` (`held.yours` exactly true), Search's owned marks and your library
   asked again on no answer too (`LibraryModel.add`). And Add was on the transport's 8 s while the route stars the
   album in Navidrome before it answers: `Routes.timeouts` gives `libraryAdd` 60 s, a join's.
   - **The review's "up to 60 s per read" was the player's client** (NavidromeClient's read=60). The add's starring
     goes through `stars.star_client`, an `auth.LoginClient`, whose `httpx.Timeout(10.0)` gives every phase 10 s, and
     the first call that finds Navidrome away (a transport error, a timeout among them) raises NavidromeDown, which
     `_star_now` catches and returns. So a Navidrome that never answers costs one call's four phases, 40 s at most,
     after up to five quick calls a folder; 60 s covers it with room. A Navidrome answering every call just under
     10 s could take longer - the may-have-landed words cover that, and the grant is written before the starring
     begins, so an add that times out has nearly always landed. test_ios_contract holds all of it to the source.
   - **The album page's own Add** (AlbumModel, the album you have, Phase 1) gains the 60 s, but keeps its refusal
     words on a timeout: it wasn't in the review, and its line is the id bridge's, not the store's.
4. **A pick could land while the sheet was being swiped away**: `stop()` ran only in `onDisappear`, after the slide.
   The search now belongs to the Get (`GetRequest.search`, made by GroupView), so it outlives the sheet's view and
   the page can reach it, and `SourcesSearch.close()` ends it for good: `closed` stops `start`, `run`, `pick`,
   `download` and an answer landing. It is called as the sheet starts going, three ways: `SheetGoing`, a
   representable whose controller hears `viewWillDisappear` as the dismissal's transition begins (for a swipe, once
   the finger lifts without pulling it back - `notifyWhenInteractionChanges`, `isCancelled` - and only when the
   sheet's presented controller `isBeingDismissed`); GroupView's sheet binding, whose setter closes the search as
   SwiftUI sets it to nil; and `onDisappear`, the backstop. Cancel calls `close()` in the tap, as it called `stop()`.
   - **When SwiftUI calls the binding's setter for a swipe, and whether a representable inside a sheet hears
     viewWillDisappear, are not known from here**: both are read from documented behaviour, not seen on a phone.
     Check 233 is the phone's answer; if neither comes early, `onDisappear` still closes the search, as before.
   - A pick landing while the finger is still on the sheet (the swipe not yet let go) is asked for, and the sheet
     closes onto Requests: the person hadn't let it go yet.

**The checks**: 233-236 (docs/ios.md's slice 3 checks, now "193-199, 229-236"): swiped away while it looks, back
after a Search of your own, Join and Add out of reach, no answer in time. Two troubleshooting rows: the may-have
words, and the pick dropped offline.

**Tests.** GetTests gains three (24): `deadwaxBackRunsTheVerySearchThatFailedForWantOfIt`,
`aPickAsDeadwaxWentOutOfReachSaysWhyAndLeavesTheChoiceToYou`, `aJoinOrAnAddWithNoAnswerInTimeIsLookedForInTheStore`.
ClientTests' map gains `libraryAdd: 60`. test_ios_contract gains two: the add's time held above the star client's
phases (the grant before `_star_now`, the login client's one Timeout, NavidromeDown ending the starring) with the
App's may-have handling, and the sheet's wiring - the very run on return, `live: online`, the offline pick, `close`
on the binding, SheetGoing, Cancel and `onDisappear`, and `!closed` in `start`, `run`, `pick` and `download`.

**Mutations** - 17, each caught (scratchpad p6s3_review_mutate.py): nine in Core against GetTests, GetVectorTests
and ClientTests (a search again picking; any failure running again; a search again run again as a fresh Get; the
typed words dropped; a join landed whoever's it is; on any download; an add landed on nothing said; the add on the
transport's time; the offline line without what to do), and eight in the App against the two contract tests (back
runs a fresh Get; Join and Add live offline; an offline pick asked for; the swipe not closing; a search again run
again picking; a closed search downloading; a failed join not kicking; an unanswered join said as refused). The
App's are the contract's reading of the source - they hold the wiring in place, not its behaviour on a phone.

**Verified**, on the tree before its commit: `swift test` (Core 1618, Audio 158, Turntable 12, no warnings); the
unsigned Debug and Release device builds, with no warnings but the usual appintentsmetadataprocessor line, the built
app 0.12 (12), the .xcodeproj unchanged and `check_project.py` ok; the exporter's `--check`; `npm run build` and the
89 sims; the full pytest suite, 4557 passed and 1 skipped; `git diff --check`; src/ has no diff; the 17 mutations.

**Not verified** - only the phone can tell (checks 233-236): when SwiftUI calls the sheet binding's setter for a
swipe, and whether SheetGoing's controller hears viewWillDisappear as the sheet goes (if neither comes early,
`onDisappear` closes the search, as before the review); the box dimmed offline and the may-have words read on a
phone; a real deadwax's Join and Add going unanswered.

## Phase 7: Managing (2026-11-15)

notes/ios-specs/phase7-managing.md, the plan's last phase. Before it, You had no way to the tools for looking after
deadwax: docs/ios.md's "What it can't do yet" listed People, Server settings, the event log, Needs a look, Library
care, the editors and changing your password, and the Library's Set up Navidrome opened the web app's Home. James's
binding decision is "managing links out to the web app", so nothing is rebuilt natively. Now:
- **You > Manage**, between Downloads and Account (the web's Manage comes before its Account), drawn only with a row:
  **Edit an album** (the phone's own), then the web's five in its order and words - **Needs a look**, **Library care**,
  **People**, **Server settings**, **Event log** - each by the web's permission rule, each opening the web app's own
  address for it in Safari;
- **Edit in the web app** at the end of an album page's bar •••, for someone the web gives the album's Edit: that
  album's page in the web app, its Edit chip one tap away;
- **Change password** in Account, above Sign out, for a Navidrome sign-in (never break-glass): the web app's You;
- **Set up Navidrome** (the Library's gate, an admin's) opens Server settings, not the web app's Home.

On `phase7-managing` from `ios` at 8f2d52f (Phase 6's slice 3 merged). **The app is 0.13 (13)** (Base.xcconfig,
check_project.py, ios.yml, test_ios_install.py). src/__init__.py untouched; the .xcodeproj unchanged (Managing.swift
is in the package, ManageSection.swift in the synchronized folder). **No route added and no server change**:
ROUTE_COUNT stays 60, and the rows read the /me the app already has.

### Core (DeadwaxCore)

- **Managing.swift** (new): permissions.ts' `managing` (`Parts` and `parts(_:loginsOn:)`: Needs a look with Look after
  the library, Library care with it or Edit albums, People with People and logins on, Server settings and the log with
  Settings and the log) and `albumEdit` (`AlbumEdit`: shown with Edit albums or Look after the library, the editors
  Edit albums', Delete Look after the library's); `Tool`, the six rows in You's order, and `tools(_ access:)`, the
  rows for a reader (the first by `albumEdit`, the rest by `parts` of `access.permissions` with `access.on`);
  ownPassword.ts' `changeOffered` (logins on, a name, not `deadwax` - compared unit for unit, as JavaScript does); and
  the addresses: `appPath` "/player/", `fragment(_:)` (formatRoute's without its `#`: `/library` for the editors, then
  `/you/queue/all`, `/you/care/library`, `/you/people/all`, `/you/settings/server`, `/you/log/all`),
  `albumFragment(id:)` (`/library/album/` + `encodeURIComponent`, TurntableGeometry's port), `youFragment`, and
  `url(_:at:)`, `albumURL(id:at:)` (nil for an empty id) and `youURL(at:)` - each `base + /player/#...`, nil without a
  server address, never a query.
- **ManagingWords**: the web's (Manage, the five rows, CHANGE_TITLE) and the phone's own: Edit an album and its line,
  Edit in the web app, the line under Change password, "Opens in Safari." (VoiceOver's hint), the footer's sentences
  (`footer(loginsOn:online:)`: where they open, or "These open once deadwax is back."; then Safari's sign-in with
  logins on), and the two symbols (`arrow.up.forward`, `safari`).
- **NavidromeGate.swift**: `setUpPath` gone; `setUpURL` is `Managing.url(.settings, at:)`.

### Held to the web: by the exporter, or by hand

`ios/scripts/export-managing-vectors.cjs` (new) compiles lib/permissions.ts, lib/appRoutes.ts, lib/ownPassword.ts and
app/access.ts with the repo's TypeScript (Preact's index and hooks stubbed) and reads You.tsx's Manage section out of
its source: the title, each row's label with the part of `managing` that draws it, in order, and You's own
`managing(...)` call, evaluated. It writes Fixtures/managing/managing-vectors.json (29 KB): `managing` and `albumEdit`
for all 64 sets of permissions, logins on and off; 20 /me answers (logins off, a Navidrome admin, break-glass, people
with one or more permissions, an answer from before permissions, names it doesn't know, unverified) through
`accessOf`, then `managing`, `albumEdit`, `seesDetail` and `changeOffered`; the addresses - every Managing page as You
opens it (`formatRoute({tab: 'you', page})`), the Library's and You's roots, and an album's for 14 ids from a hex id
to a slash, `%`, `#`, `?`, `&`, `+`, a space, an accent and an emoji - each with what `parseHash` makes of it and
whether `formatRoute` of that gives the same address back (all do); and the words. `ui/test/iosmanaging.sim.cjs` runs
it with `--check`; `ManagingVectorTests` (5) replays it - 320 checks of the sets, 180 of the answers (the rows the
phone draws among them), every address.

By hand (`ManagingTests`, 5): the addresses on every kind of base the phone may have (an IP, a name, a pasted
`…/player/` link, https with no port, IPv6 with a zone and without) - the page always `/player/`, the route the
fragment, no query; nil without an address and for an empty album id; the rows for the readers the phone has (logins
off: all but People; an admin and break-glass with every permission: all; /me's list deciding, an admin's included;
Everyone's downloads no tool); Change password's rule; the footer. `ScreenGateTests`: Set up Navidrome at Server
settings' address on both bases.

### The app

- **You/ManageSection.swift** (new): `ManageSection` draws `Managing.tools(server.access)` as `WebAppRow`s, the
  header "Manage" and the footer in `Typeface.footnote`. `WebAppRow` (Manage's rows and Account's Change password) is a
  Button: the label (and a line under it in footnote, quiet, for Edit an album and Change password), wrapping at every
  size, with `arrow.up.forward` at the trailing edge (`Typeface.symbol(.body)`, quiet, hidden from VoiceOver) where a
  pushed page's row has its chevron. The tap is SwiftUI's `openURL` - the default browser, never a web view in the app.
  Out of reach it is dimmed (`Palette.off`) and `.disabled`. VoiceOver reads one button: the label, the line, then the
  hint "Opens in Safari."
- **YouView**: `ManageSection()` after `DownloadsRow()`, before Account. **AccountSection**: Change password first, by
  `Managing.changeOffered(server.me)`, live by reachability.
- **QueueMenuRequest.webEdit** (new): QueueMenu ends with a section of its own, "Edit in the web app" with the `safari`
  symbol, opened with `openURL` - only while deadwax is in reach and the album isn't gone, as Add to a playlist is.
  AlbumView's bar ••• sets it when `Managing.albumEdit(server.access.permissions).shown`. A song's ••• never has it.

### Decided here (the spec's open questions, each built with its recommendation)

1. **Safari through `openURL`, not a web view in the app** - James's decision; the web app is a player too, and in
   the app its audio would sit beside the native engine's; SFSafariViewController keeps cookies of its own, a third
   sign-in.
2. **The section is "Manage"**, the web's title.
3. **The editors have no address** (the Edit panel opens only from an album page's chip): You's **Edit an album**
   opens the Library, saying so under the row, and the album's ••• gains **Edit in the web app**. A web change to open
   the panel from an address would be main's, and one tap doesn't need it.
4. **The artist page's managing isn't linked** - not in the plan's list; the Library reaches it.
5. **Needs a look's count isn't shown** - it would be the phone's first ask of `/library/queue/summary`, for a row
   that opens a page counting them itself.
6. **Connections isn't a row**: no address of its own, several sections down the web's You. Three read-only rows from
   routes deadwax has, if ever wanted - a native change of its own.
7. **Change password is a row in Account**, opening the web app's You, its line saying where it is.
8. **Set up Navidrome opens Server settings** (`#/you/settings/server`), the page the gate's line names, at its first
   tab: the tab is kept per page, not in the address, so Connections can't be named.
9. **The words say Safari**, though `openURL` opens the default browser.
10. **Offline, the rows are dimmed and off**, "These open once deadwax is back." - not hidden, not live.
11. **The app's session is never handed to Safari**: it could only go in the address. Safari signs in once, with the
    same name and password, and keeps its sign-in as any browser does (30 days from its last use).

Also read, not built: ATS governs the app's own loading, so a URL handed to `openURL` is Safari's to load by its own
rules - Info.plist gains nothing (`LSApplicationQueriesSchemes` is for `canOpenURL`, and http/https need no entry).
The cookie's SameSite=Strict doesn't stand in the way: `/player/` itself needs no cookie, and every request the page
makes is same-site. The sign-in keeps the address (signInGate.tsx renders the app after, and its history starts from
`location.hash`), so the first sign-in lands on the page the row named.

### Tests

- **ManagingVectorTests** (5) and **ManagingTests** (5), above; **ScreenGateTests**' Set up Navidrome test now holds
  it to Server settings' address. FixtureFiles lists the new fixture.
- **tests/test_ios_install.py**: 0.13 (13).

**Mutations** - each rule broken on purpose, ManagingTests, ManagingVectorTests and ScreenGateTests run, the rule put
back (scratchpad mutate.py). All 12 were caught:
1. Library care without Edit albums (`everySetOfPermissionsShowsTheWebsParts`, `everyAnswerOfMeShowsTheWebsRows`,
   `eachReaderHasTheRowsTheirPermissionsGive`);
2. People with logins off (the same three);
3. the album's Edit by Edit albums alone (the same three);
4. Needs a look at `#/you/queue` (`everyAddressIsTheWebsAndOpensAsItself`, `everyToolOpensTheWebAppAtThePhonesServer`);
5. an album's id not encoded (the same two);
6. break-glass compared ignoring case (`changePasswordIsANavidromeSignInsAlone`, `everyAnswerOfMeShowsTheWebsRows`);
7. Change password with logins off (the same two);
8. Edit an album last (`theWordsAndTheOrderAreTheWebs`, and the rows' two);
9. Safari's sign-in line with logins off (`theFooterSaysWhereTheyOpenAndHowSafariSignsIn`);
10. the web app at `/player` without its slash (the addresses' two, and ScreenGateTests' Set up Navidrome);
11. the route after a `?route=` instead of the `#` (the same three);
12. Set up Navidrome back at the web app's Home (`setUpOpensTheWebAppsServerSettingsAtThePhonesServer`).

The App's wiring (which section draws, the menu's item, the tap's `openURL`) has no tests of its own: it is SwiftUI's,
and every rule it applies is in Core.

### Verified, and not

Verified, on the tree before its commit:
- `swift test`: Core 1628, Audio 158, Turntable 12. No warnings.
- The unsigned Debug and Release device builds succeeded, with no warnings but the usual appintentsmetadataprocessor
  line; the built app's Info.plist reads 0.13 (13) and net.lizardlounge.deadwax. The .xcodeproj is unchanged;
  `check_project.py` ok.
- The exporter's `--check`; `npm run build` and all 90 sims on Node 22.23.4.
- The full pytest suite: 4557 passed, 1 skipped. src/ has no diff; `git diff --check` clean.
- The 12 mutations above, each caught, every file put back.

Not verified - only the phone can tell (docs/ios.md's checks 237-246):
- that Safari opens each address on the page it names, over plain http on the Wi-Fi and over WireGuard, with no
  warning James didn't ask for - and whether it opens a new tab each time or goes back to one it has;
- that the first sign-in in Safari lands on the page the row named, and the second time goes straight there (the
  SameSite reading above);
- that Safari asks nothing about the local network;
- the rows at the largest text sizes, and VoiceOver's reading of them ("Opens in Safari." as a hint, after the label);
- CI's Xcode 26.6 (the older Swift). The new code spells out its closures' types and keeps each `#expect` small.

### After review (2026-11-15)

The review found no wrong row, address or crash; its four low points, fixed in one commit after 6cb6767:

1. **A refused open said nothing.** Every way out called `openURL(url)` without its completion - Manage's rows,
   Change password, the album's Edit in the web app, and the Library's Set up Navidrome (which had been like that
   since Phase 1). With Safari turned off in Screen Time and no other browser, a tap did nothing at all. They now open
   through `OpenURLAction.webApp(_:player:)` (ManageSection.swift), whose completion hands `accepted` to Core's
   `Managing.notice(opened:)`: nothing when the browser took it, else `ManagingWords.notOpened` - "Couldn't open the
   web app - Safari may be turned off in Screen Time." - said over the tabs by `PlayerModel.say` (the notice, 5 s,
   announced). The address isn't said, even to whoever runs deadwax: iOS refused the kind of link, not this one, so it
   would help nobody. ManagingTests' `anOpenIOSRefusedSaysSoInAListenersWords` holds the words to ErrorWords'
   `plumbing` (none) and to having no address in them.
2. **The rows follow the app's person; the page follows Safari's.** Nothing compares the two, and nothing could
   without handing the session over (question 11). The page is still the server's to refuse, so nobody gets what
   Safari's person doesn't have - but signed in to the app as one person and to Safari as another, a row opens with
   the other's access, and Change password changes the other's password. The footer's sign-in line now ends "The pages
   open as whoever is signed in there, who may not be who's signed in here."; Change password's line ends "It changes
   the password of whoever is signed in in Safari." (it's shown to people with no Manage, so it carries its own);
   docs/ios.md's Manage section says it in bold and how to see Safari's name (the web app's You heads with it), and a
   troubleshooting row covers a page with someone else's access. **Check 241 was wrong**: it had the admin change
   permissions "in the web app", which on the same phone signs Safari in as the admin, after which Library care opens
   with full access. It now does the admin's part on another device, with Safari signed in as the person under test.
3. **People refuses in its own words**: "Only an admin can open People - it comes with being a Navidrome admin."
   (People.tsx's `PEOPLE_ONLY`), not NO_PERMISSION's. docs/ios.md's Manage section and its troubleshooting row said
   every refused page read NO_PERMISSION; both now give People's too.
4. **The vectors missed two of App.tsx's rules.** The album page's Edit chip is drawn by `onEdit={albumEdit(perms).shown
   ? …}` in App.tsx, which wasn't hashed or run, and the addresses' `tab: 'you'` and `tab: 'library'` were written into
   the exporter. It now reads out of App.tsx and hashes: the chip's rule (exactly one such `onEdit`, or it stops) and
   App's `const perms = …`, both evaluated as written - `albumPage` for every set and every /me answer, which
   ManagingVectorTests replays (64 × 6 and 20 × 10 checks; Edit an album's row now follows `albumPage`); and
   `openManagingPage` - the stack it reads, the tab it shows and the scroll key's tab, which must agree and be one of
   appRoutes.ts's `TABS` - whose tab every Managing page's address and You's are made with. The Library's tab is the
   phone's own choice (an album opens on whichever tab shows, openAlbum), held to `TABS`. The fixture carries both
   (`addresses.tabs`), and the vector test holds each fragment to its tab. 31 KB.

Also: check 245 gained Safari turned off in Screen Time (the range stays 237-246), and two troubleshooting rows (someone
else's access; the refusal's words).

**Mutations** - 11, each caught (scratchpad mutate_p7_review.py, and two more by hand with its helpers): five in Core
against the Managing tests (a refusal saying nothing; an accepted open saying the refusal; the address in the words;
the footer without whose page it is; Change password's line without whose password), and six in App.tsx against the
exporter's `--check` (the chip by `.editors`; `perms` an empty set; `perms` written so it can't be evaluated; a
Managing page opened on Home; its stack another tab's; a second albumEdit `onEdit`). The unmutated tree passed
`--check` first, and every file was put back.

**Verified**, on the tree before its commit: `swift test` (Core 1629, Audio 158, Turntable 12, no warnings); the
unsigned Debug and Release device builds, with no warnings but the usual appintentsmetadataprocessor line, the built
app 0.13 (13), the .xcodeproj unchanged and `check_project.py` ok; the exporter's `--check`; `npm run build` and the
90 sims on Node 22.23.4; the full pytest suite, 4557 passed and 1 skipped; `git diff --check`; src/ and ui/src have no diff; the
11 mutations. `ios` was still at 8f2d52f, so there was nothing to merge.

**Not verified** - only the phone can tell: that openURL's completion says `false` with Safari turned off in Screen
Time, so the notice shows (check 245); the notice read by VoiceOver after the tap.

## Search again at the top of Choose a source (2026-11-15)

James: "When finding a peer, search again should be somewhere near the top as well." Choose a source had Search again
only under the cards (and under "none match your filters"), so with forty sources the way to try other words was a
scroll to the end. It went first into a row above the first card (how many shown, and Search again at its right -
7fa2d2b); James then: "Maybe on the right of 'choose a source'", so it is in the bar instead, and that row is gone. The
web's sheet (ui/src/app/Sources.tsx) has it in the one place under the cards still; this is the phone's alone until
James says otherwise.

- **Where**: a `.topBarTrailing` item, beside Cancel's `.cancellationAction` - not `.confirmationAction`, which iOS 26
  draws as the tinted, prominent action, and this is no sheet's Done. Only while folders found are shown
  (`foundFolders`: not searching, no error, no store box, something found - nothing found already shows its words to
  change).
- **Words, then a glass**: measured in the app's Noto Sans at 17 points (fontTools' advances), "Choose a source" in
  semibold is 135 points, "Search again" 103 and "Cancel" 53. On James's iPhone 17 Pro (402 points), with iOS 26's
  glass capsules round both buttons, that leaves the title about 140 - it fits at the default text size, just; one size
  up it would be cut short. So above `.large` the item is a magnifying glass, named "Search again" for VoiceOver either
  way. The capsules' padding is a guess from the look, not a measurement: check 247 asks the phone whether the title
  reads whole.
- **Its field opens above the chips**, outside the list, so it is there however far the list was scrolled - no
  ScrollViewReader needed - and it scrolls nothing away. The one under the cards opens under itself, as before.
- **One form at a time**: `again` is `AgainPlace?` (`.top`, `.bottom`) rather than a Bool; a second tap closes it,
  the other's moves it (its field focused again by the form's own `.task`). A search starting - begin() or requery() -
  closes it, as it did. The field, Search, an edited query searched as typed, and offline (the form's Search off) are
  queryForm's, shared by both.

**Tests**: `test_search_again_sits_in_the_bar_as_well_as_under_the_cards` (tests/test_ios_contract.py) holds the bar's
item after Cancel and only with folders found, what `foundFolders` requires, the bar's form above the chips and outside
the ScrollView, the list's two, one form at a time and both closed by a search starting, and the words-or-glass rule
with its VoiceOver name and state.

**Verified**: the unsigned Debug device build; the test above and the full pytest suite. **Not verified** - only the
phone can tell: that the title reads whole beside the words, the glass one size up, and the field opening above the
chips with the keyboard (docs/ios.md check 247).

## The bars, smooth (15 Nov)

James: "Can we make the progress bar smooth instead of updating every half second?" The play bar's seek line and Now
Playing's scrubber drew PlayerModel's `shownPosition`, which moves when the ticker reads the engine - twice a second -
so both stepped.

- **Drawn every frame while the song plays**: each bar's fill is inside a `TimelineView(.animation(minimumInterval:
  PlayClock.frame, paused: !runs))`, 30 frames a second at most. `runs` is `player.barsRun` (playing and not loading -
  `isPlaying && !isLoading`, so a speed change's hidden restart keeps it running) with no finger on the bar, and for
  the play bar Now Playing not over it (`navigation.nowPlayingShown`); for the scrubber, it seen (`visible`: on the
  cover, no sheet over Now Playing - since the review, below). Paused, the timeline stops and its content shows
  `shownPosition`, exactly as before. The seek line's timeline holds its accent fill alone; the scrubber's two (since
  the review) its fill and its clocks, which are `ScrubberClocks` (Equatable, `.equatable()`) fed the same value's
  words, so they are drawn again only when the words change - and never disagree with the bar.
  VoiceOver's value and its swipes stay on `shownPosition`, so it isn't told thirty times a second.
- **The engine isn't asked per frame**: the brief allowed `clock()` (the lyrics' read) if it is trivially cheap.
  Measured with a temporary test on this Mac (a live offline engine, 5,000 reads; deleted after, so DeadwaxAudio has no
  diff): 3.4 us a read with the engine's queue idle, 13 us straight after a render's completions, and 0.4-1.9 ms
  straight after a play or a seek, waiting behind the start being decoded - and the phone decodes FLAC there, slower.
  Thirty of those a second on the main thread, landing exactly when a song starts or a seek lands, is not trivial.
- **So the tick's reading is carried on (Core's PlayClock, pure)**: at each tick, `PlayClock.reading(entry:seconds:at:
  rate:shown:)` keeps the engine's seconds, when (Monotonic), and the speed; `PlayClock.shown(_:now:)` is those seconds
  plus the time since at the speed - at most `reach` (1 s, two ticks), so with no reading it stops rather than running
  on - never under the reading's `floor`. The floor is what the bars showed as the reading came, when that was ahead of
  it by less than `holdWithin` (Scrub.landedWithin, 1.5 s): a reading behind is waited for, the line standing still
  until the song catches up, never jumped back to. Between ticks that is milliseconds; at a seek's landing it is the
  target the bars held (Scrub lets a target go within 1.5 s of it), so a seek never lands with a jump back. Further
  behind is a real move (AirPlay's 2 s of latency) and is gone to. A speed change carries on from where the bars are
  at the new rate (`PlayClock.atRate`), with no wait for the next tick.
- **PlayerModel** gains `barsRun`, `barPosition(at:)` - nil reading, another entry's, or not running: `shownPosition`;
  else the carried reading under a seek's target (Scrub.reportedPosition) - and `smooth`, set in `tick()` from the very
  reading it already takes (`before` read first) and dropped whenever the bars don't run, at the speed hold's expiry
  (they stop with no tick) and at a stop. Nothing the ticker drives changed: still 0.5 s, and the plays, Repeat's
  top-up, resume and the pace all read `position` as before. The lyrics keep `clock()`; the turntable and Debug read
  `shownPosition`, as before. No engine file has a diff.

**Tests**: PlayClockTests (Core, 10): the carry at 1x, 0.5x and 2x; the reach; a time before the reading; a reading
ahead gone to; one behind waited for and then moved on from; a seek landing short of its target holding it; far behind
gone to; a speed change; no rate; and 240 readings with a few ms of wobble and the engine's clock 0.2% slow, drawn at
30 frames a second - never back, never more than 20 ms off. `test_the_bars_run_smooth_only_while_the_song_plays`
(tests/test_ios_palette.py) holds the timelines and what pauses them, VoiceOver on `shownPosition`, the frame's value
read inside the timeline alone, the clocks' Equatable view, the ticker and what it drives, and the lyrics' clock.

**Verified**: swift test, the unsigned Debug and Release device builds, check_project, npm run build, the sims and
pytest. **Not verified** - only the phone can tell: that it looks smooth, that the frames cost nothing a listener
notices (no warmth, no stutter), the stop on pause, and the landings (docs/ios.md check 248).

## The Library's top, clear of the Dynamic Island (15 Nov)

James: "on the app the top bar is obstructed by the Dynamic Island" - the Library's own top (the round search button,
the switch, the round •••), on his iPhone 17 Pro on iOS 27.2.

- **How it was**: LibraryTop was a `.safeAreaInset(edge: .top)` on the pager - a horizontal ScrollView whose pages are
  `.containerRelativeFrame([.horizontal, .vertical])` - with the offline banner a second inset inside it, under
  `.toolbar(.hidden, for: .navigationBar)`. An inset is placed against the safe area the modified view has, and a
  scroll view is free to run under the status bar; which of the two put the row in the island's strip on iOS 27.2
  was not found out - no simulator here, by the rules - and it didn't need to be: the new layout doesn't depend on it.
- **How it is**: the pager's page is a `VStack(spacing: 0)` of LibraryTop, then the OfflineBanner, then the pager. A
  VStack is laid out inside the safe area, whatever its children do, so the row starts under the status bar and the
  island on every iPhone (notch, island, none), and the banner and the pages follow it down; only LibraryTop's own
  background, Palette.tabBar, ignores the top safe area, filling up behind the status bar so nothing of the pages
  shows there. The pages now end at the row's foot instead of scrolling under it (it was opaque, so nothing showed
  through it anyway); the pull to shuffle measures from the list's own inset (`contentOffset.y + contentInsets.top`),
  so it is the same either way. Find still opens under the switch, inside LibraryTop, and the pager gives it the room.
- **The other pages**: the Library is the only page that hides iOS's navigation bar; every other page's top is iOS's
  own bar. The other views that reach under the status bar are fills alone: RootView's background, and Now Playing's
  black and its blurred cover - its content stays in the safe area.

**Tests**: `test_the_librarys_top_sits_under_the_status_bar` (tests/test_ios_palette.py) holds the VStack's order
(the top, the banner, the pager), no top inset left in LibraryView, LibraryTop's one ignore on its background, the
Library as the only page hiding the navigation bar, and the four views that reach under the status bar, all fills.

**Verified**: swift test, the unsigned Debug and Release device builds, check_project, npm run build, the sims and
pytest. **Not verified** - only the phone can tell: the row clear of the island, the fill behind the status bar, Find
and the banner under the row, at the normal and the largest text sizes (docs/ios.md check 249).

### The Library's top, measured (15 Nov, the second time)

James, on 282e9b9 (the VStack above in it): "it looks good, but the library's top still doesn't clear the dynamic
island". The row was laid out in SwiftUI's safe area twice - an inset on the pager, then a VStack - and stood in the
island's strip both times on his iPhone 17 Pro on iOS 27.2. Nothing in the app's own code takes the top safe area away
(every `ignoresSafeArea` that reaches the top is a fill, the test above holds them), so the safe area the Library's views
are given there isn't the screen's, for a reason inside SwiftUI and the TabView with iOS's bars hidden that can't be
found without the phone, or a simulator - which the rules rule out.

- **What it does now**: the row no longer trusts that safe area. LibraryTop measures where its own top is on the screen
  (`proxy.frame(in: .global).minY`, through `onGeometryChange`, with its safe area's top in the measured value too so a
  change of it measures again) and pads its row down by whatever of the key window's top safe area (`KeyWindow`,
  about 62 points on an iPhone 17 Pro, 20 with a Home button) that top doesn't clear - Core's `TopClearance.extra`.
  Laid out as it should be, under the status bar, that is 0, so a layout that was right stays right. The padding is
  inside the view measured, so coming down never moves what it measures: no loop.
- **Kept, not followed down**: `TopClearance.kept` keeps the larger of the room kept and the room measured, so a
  measurement taken with the screen drawn smaller under a sheet (iOS's presentation can shrink what's under it) never
  lifts the row back into the strip for the moment the sheet is up and drops it as it goes. A new window inset (the
  only thing that can make less room right - the app is portrait only) starts it afresh.
- **KeyWindow** (ios/App/Shared): the key window's safe area, shared with MainTabs's home indicator room - the window's,
  never a view's, as that one already was.
- **The banner and the pages** follow the row down, as the VStack has them; Find's field opens under the row as before.

**Tests**: TopClearanceTests (Core: the row at the top edge comes down the inset, part way the rest, already clear
nothing, no inset or no number nothing, above the screen at most the inset; kept under a sheet, afresh with a new inset);
`test_the_librarys_top_sits_under_the_status_bar` holds the padding, the measure and its order, and KeyWindow's use by
both; the tab bar's test reads the bottom through KeyWindow.

**Verified on the phone (15 Nov)**: James, on 267ea8f's build: "the library top clears the island now" - so the
safe area SwiftUI gave the Library's views really was short of the window's, and measuring against the window is what
works. Why SwiftUI's was short is still not known. **Not verified**: the rest of check 249 - no jump as sheets, Now
Playing and pushed pages come and go, Find, the offline banner, the largest text size, a phone with a notch or an SE.

## The tab bar, lower (15 Nov)

James: "there might be a little too much space below the bottom tab bar". AppTabBar was an overlay inside the safe
area, so on a Face ID iPhone the whole 34 points of the home indicator's room were under it, and each tab's 49 points
(a 26-point symbol, 3 between, then the words, about 15 in Noto Sans's caption2 - about 2.5 points of slack under
them) stood on top of that: the words' baseline about 40 points off the screen's edge. iOS's own bar before iOS 26 lays
its items out the same way, over the whole 34.

- **The number - 14 points down (Core's `TabBarFoot.drop`)**: the tabs' foot 20 points off the edge, so the words' line
  is about 22 up and their baseline about 26. The home indicator is a 5-point bar about 8 points off the edge, its top
  about 13 up: that leaves some 9 points of clear room between the words and it - clear at a glance, and the words no
  longer floating. On a phone with a Home button (no such room, 0) the tabs keep 6 points off the edge
  (`TabBarFoot.least`), where they had none.
- **How**: AppTabBar ignores the container's bottom safe area itself, so it runs to the edge, and pads under its play bar
  and tabs by `TabBarFoot.below(home:)`; its fill still runs to the edge. The home indicator's room is the key window's
  bottom safe area (MainTabs's `home`), read from UIKit because a window's never counts the keyboard - a view's
  safeAreaInsets would, and the bar would grow under the keyboard. (Since the review, below, it is read again each time
  SwiftUI lays the screen out anew.) The bar measures its play bar and tabs alone
  (`measured`, before the padding), and `tabBarRoom` - the pages' room at their foot and the notice's lift, over the home
  indicator's own - is `TabBarFoot.room(content:home:)`: that height and the room under it, less the home indicator's
  (86 for a 100-point bar on a Face ID iPhone; 106 on an SE). So nothing sits under the bar, and its height follows the
  text size as before.
- **Unchanged**: the keyboard - the bar stays under it (`.ignoresSafeArea(.keyboard, edges: .bottom)`) and the pages make
  no room for it meanwhile (`keyboardUp`); the bar's sizes and its tabs' look.

**Tests**: TabBarFootTests (Core, 4): 20 on a Face ID iPhone, clear of the indicator, 6 with none (and nonsense), and the
pages' room. `test_the_tab_bar_comes_down_into_the_home_indicators_room` (tests/test_ios_palette.py) holds the bar's
padding and its own ignore, the measure before the padding, the room from TabBarFoot, the window's inset, and the
keyboard's ignore and `keyboardUp`.

**Verified**: swift test, the unsigned Debug and Release device builds, check_project, npm run build, the sims and
pytest. **Not verified** - only the phone can tell: how the gap looks, the indicator clear of the words, the last rows
and the notice over the bar, the keyboard, and an SE's margin (docs/ios.md check 250).

## Actual corners (15 Nov)

James: "let's square off everything already square a bit more. Actual corners. The pause, skip buttons, etc. I like the
square look. Even the library icon should be a bit more square."

- **Every corner 0**: Corners.art, card, control, track and fill all go from 2, 4, 4, 2 and 1 to 0, and with them
  `controlBorder` (a system button's border: the `.bordered` buttons and Paste). The kinds keep their names, so what
  each is for stays said. The primary button and the secondary pill (ButtonFaces' PrimaryFace) drew
  PrimaryButton.radius, the web's --dw-radius-control (4); they now draw Corners.control, so they are square too, and
  PrimaryButton.radius stays the web's number in Core, held to theme.css as before. Round stays round, as Corners' doc
  says: the dots, the avatar, artists' pictures, the rings, the sliders' knobs, the Library's two circles, Requests'
  round ▶ and ✕, the turntable's own corners (TurntableFace.lookRadius - the look button and the speed chip until the
  review squared them, below; the plinth and its readout's well still) and the app icon. The squared look's table
  ("Corners, before and after") is history now: every "after" there is 0.
- **What a 0 changed beyond the corners**: PrimaryFace's highlight - the light line inside its top edge - was masked
  to the top `radius` points, which at 0 is nothing, so the line would have gone; its band is now at least two
  hairlines tall, which holds the top line (and its square ends). The switch's well shade inside its top edge was
  kept off the corners by `Corners.control`, and now runs edge to edge inside the border, as a square well's should.
  To look at on the phone (check 251): the switch's chosen segment, a square 1 point inside a square well, and the
  Requests count, a square badge over the icon's corner.
- **Sharp transport glyphs** (Core's SharpGlyph, the shapes; the app's Shared/SharpGlyphs.swift, the views): SF
  Symbols has no sharp-cornered play, pause, forward or backward, so they are drawn - the play triangle, pause's two
  bars, forward's and backward's two triangles point to base - as straight lines meeting at points. **Measured, not
  guessed**: SwiftUI's own rendering of each symbol at 44 points (ImageRenderer at 8x on the Mac - the symbols are
  iOS's artwork; scratch scripts, not kept) gave the frame SwiftUI lays it into, where its ink sits there (play.fill's
  from 14% to 98% across and 9% to 91% down; pause's bars 0.405 of their box each, 0.19 between) and how much of the
  frame it inks. Each sharp glyph is its shape in the symbol's ink box, grown or shrunk about the box's centre until
  it inks just as much: the same weight. Rounding a triangle cuts most at its points, so a sharp one in the rounded
  one's box would ink 15-16% less: play grows 8% and the skip pair 9%, their points reaching where the rounding had
  cut them (the skip pair's a little past their frames' edges, under 3% of the frame - the overlay isn't clipped);
  pause's bars and the stack shrink under 1.5%. Filling the whole frame would have drawn each glyph about a fifth
  larger than its symbol: SF Symbols' frames hold 8-14% of room around the ink. `SharpSymbol` lays a glyph into the
  frame of its SF Symbol at the font in use (the symbol is still there, `.hidden()`, as the template), so each is the
  size it was at every text size and grows with Dynamic Type as the symbol did. Measured at the regular weight; at
  semibold (Requests' ▶, the album page's Play) the template's larger frame carries the weight's size, its ink about
  5% heavier than the sharp glyph's. `PlayPauseGlyph` holds both, crossfading 0.15 s as Play/Pause turns (the symbols
  swapped at once; at once under Reduce Motion, as the EQ's animations are), in the larger's room, so the button never
  changes size. Used in the play bar, Now Playing (previous, play/pause, next), the album and playlist pages' Play
  (AlbumHero), Requests' ▶, Search's ▶ and Debug's three. The Large Content Viewer shows images, so `SharpGlyph.image`
  is the same path in a template UIImage, the symbol's own size at 44 points. The lock screen's controls are iOS's and
  keep its symbols. The Library's ••• menu keeps its "square.stack" beside Albums: a menu row's icon, iOS's to draw,
  not the Library's icon.
- **The Library's icon**: AppTab's `sharp` (Routes.swift) is `.library` for the Library alone: square.stack.fill's own
  parts measured the same way and squared - the front card a true square at the foot (37.6 points a side at 44), the
  two cards behind it strips above, each narrower, with the symbol's gaps - in square.stack.fill's frame. The tab bar
  draws every tab's symbol in its fill variant, shown or not (`.symbolVariant(.fill)`, unconditional before this too),
  so the stack is always filled, in the accent when shown and --dw-tab-inactive when not, like the other three, which
  keep their SF Symbols. Its Large Content Viewer shows the sharp image.

**Tests**: Core's SharpGlyphTests (9) - each glyph inks what its symbol did, centred on its ink, the triangles grown
and the rectangles hardly, none far past its frame, pause's bars, previous as next turned round, the Library's front
card square. tests/test_ios_palette.py - `test_the_corners_are_the_squared_looks` holds every corner at 0 and the
web's above it, `test_every_corner_in_the_app_is_a_token` the face's Corners.control, the primary's test every
PrimaryButton number but the radius, and `test_the_transport_and_the_librarys_icon_have_actual_corners` that no
transport symbol is named in the app but Core's templates, each place's glyph, the crossfade, the Large Content
Viewer's images and the Library tab's.

**Verified**: swift test, the unsigned Debug and Release device builds, check_project, npm run build, the sims and
pytest. **Not verified** - only the phone can tell: how the corners read, the glyphs' size and weight beside the old
ones' memory, the fade, the Library icon beside the others, at the default and largest text sizes (docs/ios.md checks
251-252).

## The bars, the tabs and the corners after review (15 Nov)

The four commits above (the smooth bars, the Library's top, the tab bar lower, actual corners) were reviewed; nothing
had to be fixed, and five things were, in one commit.

- **The scrubber drew frames no one saw**: Now Playing keeps it in its row on the turntable, at opacity 0 (the time
  line over it), and under its full-height sheets, and its timeline ran on through both - the whole row, 30 times a
  second. ScrubberView takes `visible` (NowPlayingView: `!turntable && !sheetOver`, `sheetOver` being Up Next, Info,
  the EQ, Add to a playlist or - since the merge with the cover's viewer - the cover full screen over it), and `runs` is
  `visible && player.barsRun && held == nil`. Its timelines hold
  only what moves, as the seek line's: one round the fill (the track and the touch outside it), one round the clocks;
  the value both draw is `drawn(_:length:)`, read inside them alone. The lyrics' own `covered` (Up Next, Info, the EQ)
  is as it was - it doesn't count the playlist picker, which the scrubber's does.
- **Two controls kept rounded corners**: the look button (TurntableView's LookFace) and the speed chip (NowPlayingView's
  SpeedChipFace) drew TurntableFace.lookRadius, 4. Both take Corners.control (0) now, and the look button's square
  glyph (the web's SquareIcon, which stands for the cover) is drawn with points too. The look button's highlight was
  masked to the top `lookRadius` points - at 0, nothing - so its band now runs to the line's foot (the inset and the
  line, 2 points). **Kept, as hardware**: the plinth's corners (TurntableFace.plinthRadius, 6) and the speed readout's
  well on it (TurntableFace.lookRadius, 4, drawn by DeadwaxTurntable's TurntableReadout among the plinth's own renders).
  TurntableFace.lookRadius and squareIcon keep the web's numbers (test_ios_turntable_face.py), as PrimaryButton.radius
  does.
- **The bars could step back at a speed restart's wait**: a restart still loading past its 1 s hold shows the spinner,
  and the expiry dropped the carried reading, so the bars went back to the last tick's position - up to half a second
  at the speed behind what they had drawn - and each tick of the wait read the engine stood at the restart's point.
  Now a wait (`barsWait`: loading to play - the restart past its hold, a seek's bytes, a stall) holds the reading where
  the bars stopped, Core's new `PlayClock.held` (the reading at no rate), at the expiry and at each tick of the wait;
  `barPosition(at:)` draws it while they wait; a speed sent meanwhile leaves it held (the reading after the wait takes
  the speed up). The reading after the wait corrects it as any reading does - ahead, gone to; behind by less than
  `holdWithin`, waited for - so nothing draws backwards through one. A pause still shows where the song is (it is where
  Play goes on from); a retry's wait isn't playing, as before.
- **The home indicator's room is read again on every new layout**: MainTabs's `home` was a computed read of the key
  window's inset, evaluated only when the body was, so a first pass before the window had its insets could have left
  the tabs over the home indicator until something else redrew it. It is `@State` now, set on appear and from a
  `Color.clear.ignoresSafeArea()` background's `onGeometryChange` of its size and bottom safe area - SwiftUI says when
  the screen is laid out anew (its first pass, a resize, its safe area's change), the window says what. Not the
  geometry's own inset: with the keyboard up a view's bottom safe area can count it, and the bar would grow under the
  keyboard. Cheap: one clear view, an action on a change of three numbers. (The app is portrait only.)
- **Check 248's speed part**: it asked for the speed to be changed on the turntable, where the scrubber is hidden. It now
  changes it on the turntable and flips back to the cover, and from the cover's chip and the ••• menu - and watches the
  bar through a restart's spinner, and after Up Next, Info and the turntable.

**Tests**: PlayClockTests (Core, 12 - 2 new: a wait holds the bars where they were, held again it stays; through a wait
with the engine stood behind and after it, never back). tests/test_ios_palette.py - the bars' test holds the scrubber's
`visible` in its `runs` and Now Playing's flag, the two timelines (fill and clocks) and the model's wait (`barsWait`, the
held reading at the expiry and in the tick); the corners' test no longer keeps TurntableFace.lookRadius in a view, and
holds the two faces' Corners.control and the look button's highlight; the tab bar's test the re-read; the Library top's
counts MainTabs's clear reader among what reaches the top edge. tests/test_ios_turntable_face.py finds the scrubber's
row by its new call.

**Verified**: swift test, the unsigned Debug and Release device builds, check_project, npm run build, the sims and
pytest. **Not verified** - only the phone can tell: that nothing is drawn for the hidden scrubber (no profiler here),
the bars through a slow restart, the tabs' place from the first frame, and the square look button and speed chip
beside the plinth's rounding (docs/ios.md checks 248, 250 and 251).


## Album info (2026-11-15)

James: "I'd like somewhere I can see all the album metadata like quality, media type, etc." An album as a whole, in a
listener's words, grouped, on a sheet of its own: **Album info**, in the album page's bar ••• (its last section, above
Edit in the web app, for everyone - offline too, and for an album gone from the collection), and as a row under Info's
album card, pushed inside Info's own stack. The web has no such sheet: its album page's Properties
(lib/albumProperties.ts) is the nearest, and its year, size, release link and Added are said here too. Still app 0.13
(13); the .xcodeproj unchanged (AlbumInfo.swift is in the package, the views in the synchronized folder).

**No server change.** Every line comes from a route the app could already call, so nothing went to main: one route
added to Routes.swift (ROUTE_COUNT 60 -> 61) is the track viewer's `GET /deadwax/library/tracks?album=<folder>`, a
user's route (tests/test_logins.py ROUTES), given 30 s (Routes.timeouts) since it reads every
file of the folder from the disk as it is asked.

### Where each line comes from

Looked up before anything was drawn - Navidrome's getAlbum and its OpenSubsonic fields (server/subsonic/helpers.go
buildOSAlbumID3, the OpenSubsonic spec's AlbumID3), the id bridge's `_facts` (src/routes/store_album.py), the tracks
route's `read_album_details` (src/library.py: DETAIL_TAGS by name, every tag raw), and Picard's tag map
(picard-docs appendices/tag_mapping) for the names each container keeps each tag under.

| line | from |
| --- | --- |
| Format, Bitrate, Channels | the album's songs as getAlbum answered them: `suffix` (else the content type), `bitDepth`, `samplingRate`, `bitRate`, `channelCount` - an M4A's codec from its `contentType` or the album's MP4 bitrate (After review) |
| Songs, Discs (titles), Disc title, Length, Size | the songs (`discNumber`, `duration`, `size`) and getAlbum's `discTitles` |
| Downloaded | DownloadModel: `album(songs)` and `here(songs)` |
| Media | the files' MEDIA: deadwax's filing's whole-release value (" + "-joined) once, else Picard's per disc (each disc's commonest), folded as MusicBrainz writes a release's format: "2×CD + DVD-Video" |
| Label | getAlbum's `recordLabels` (OpenSubsonic), else the files' LABEL / ORGANIZATION / TPUB |
| Catalogue number, Barcode, Country | the files' CATALOGNUMBER, BARCODE, RELEASECOUNTRY (MusicBrainz's own names for XW, XE and the gone countries - XC, XG, SU, YU, CS - ahead of Locale's English name; XU left out) |
| Released | getAlbum's `releaseDate`, else the files' DATE, else the album's `year` |
| First released | getAlbum's `originalReleaseDate`, else the files' ORIGINALDATE, else the bridge's `original_year` - only when it isn't Released |
| Type | getAlbum's `releaseTypes` (+ Compilation from `isCompilation`), else the files' RELEASETYPE |
| Status | the files' RELEASESTATUS - read raw: it isn't among DETAIL_TAGS |
| Edition | the bridge's `edition` (deadwax's own words for the pressing), else getAlbum's `version` |
| Genres | getAlbum's `genres`, else the album's `genre`, else the files' GENRE |
| Added | the bridge's earliest `first_seen`, ", downloaded by deadwax" when that earliest folder is `imported` |
| Release, Release group (and their pages) | the bridge's `release_mbid` (else the album's `musicBrainzId`), its `release_group_mbid` (else the files' MUSICBRAINZ_RELEASEGROUPID) |
| Folder(s) | the bridge's `present` paths (AboutCard.folderLine), for an admin (`Access.isAdmin`, as Info's) |

A tag is read by the server's own name for it first (`tags`, mutagen's easy keys, values joined "; "), else by any
of the names Picard writes it under in each container (`raw`, compared lower-cased): Vorbis comments' own,
`TXXX:MusicBrainz Album Status` and the like for ID3, `----:com.apple.iTunes:…` for MP4's freeform atoms (which Easy
MP4 has no names for - an M4A's every one is raw), `WM/…` for ASF. AlbumTag holds both lists.

### Core (DeadwaxCore)

- **AlbumInfo.swift** (new): `AlbumExtras` (getAlbum's OpenSubsonic fields the Album model doesn't keep, read
  leniently from the same answer - `Day`, `Named`), `AlbumFiles` and `AlbumFile` (the tracks route's files: `disc`,
  `tags`, `raw`; `values(_:)`), `AlbumTag` (each tag's names), `AlbumInfoRow` (label, value, lines under it, plain /
  copyable / link), `AlbumInfoSection`, `AlbumInfoWords`, and `AlbumInfo`'s rules: `quality`, `theAlbum`, `onPhone`,
  `release`, `musicBrainz` (a page made only for a UUID-shaped id), `server`, then `local` (Quality, The album, On this
  phone) and `fromServer` (The release, MusicBrainz, On the server), each leaving out a section with no lines;
  `foldersToRead` (the bridge's present paths, each once, at most 8), `foldersAtOnce` (2); `media`, `country`,
  `dateWords`.
- **Routes.swift**: `libraryTracks` (and 30 s); **DeadwaxClient**: `albumFiles(folder:)`.

### The app

- **Album/AlbumInfoAsk.swift**: what the sheet asks while open, Info's settle pattern (InfoAsk.details): getAlbum
  again (`albumAnswered` - the whole album, and AlbumExtras from the same body), the bridge, and - once the bridge names
  them - the folders' files, two at a time (After review); all held for each other until in or
  AlbumInfoWords.settleSeconds (3 s) has gone, then each landing as it comes. What failed is kept for the list to say
  (After review).
- **Album/AlbumInfoView.swift**: `AlbumInfoList` (the list - the header's cover, title and artist, then the sections;
  Copy, links, the reading row, the offline line) and `AlbumInfoSheet` (it in a NavigationStack with Done).
- **QueueMenu**: `QueueMenuRequest.albumInfo`, a button in the last section. **AlbumView**: sets it, and presents the
  sheet (`.sheet(item:)` on the album). **InfoView**: a NavigationLink under the album card whenever the queue knows
  the album's id.

### Decided here (the ask was silent)

- **The bridge is asked whatever D12 says.** The album page and Info ask it only with a library of one's own
  (`hasLibrary`); Album info asks it always, as the web's Properties does - it is a user's route either way, and its
  folders are the only way to the files' tags. With logins off, the release's tag lines would otherwise never show.
- **The files are read live**, not from the saved scan: the scan keeps none of these tags (DETAIL_TAGS are the track
  viewer's, read as asked), and adding them to it would be a server change and a SCAN_FORMAT bump for one sheet.
- **"songs", not "tracks"** ("all 10 songs"), as every other line of the app says them.
- **"downloaded by deadwax"**, not the web's "downloaded here" - on a phone "here" reads as this phone.
- **Bitrate is Navidrome's, weighed by length**, never the files' sizes over their lengths: a cover in every file
  would count as sound.
- **A lossy format never shows a depth** (a tag reader may give an MP3 one); a lossy group says its bitrate instead.
- **Countries in British English** (`Locale(identifier: "en_GB")`), the app's own, whatever the phone's language.
- **Info's album from a playlist is a stub** (`Album.partial`): its own lines wait for the album's answer rather
  than counting the playlist's songs as the album's.
- **Copy is a button beside the words**, not a long-press menu, so VoiceOver and a first look both find it; the words
  are selectable too.

### Left out, and why

- **MusicBrainz's release disambiguation and packaging**: Picard writes neither into the files by default, and
  getAlbum doesn't carry them; asking MusicBrainz from the sheet would be a second source that can disagree with the
  files. The bridge's `edition` (deadwax's own words for the pressing) stands in for the disambiguation.
- **An album not matched to MusicBrainz** has no bridge folder (the bridge is keyed on the release), so no files are
  read and none of the five tag-only lines show: the docs say so.
- **More than eight folders** of one album are not read (`foldersRead`): a set kept per disc is a handful; a dozen
  copies of one release is not this sheet's to read.

### Tests

- **AlbumInfoTests** (DeadwaxCoreTests, 24; 31 after review): every tag in each container from the route's own answers, media per
  disc, the named tag before raw, Quality's lines and mixes, the bitrate, channels, the album's lines, On this phone,
  the release from each source and in what order, dates and countries in words, the ids and their pages (and an id
  that isn't one), the folders, which folders are read, empty sections left out, getAlbum's other fields read
  leniently, and the files asked for by their folder with the 30 s.
- **Fixtures/albuminfo/files.json**: written by `ios/scripts/album_files_answers.py` - real FLAC (two discs), MP3 and
  M4A files tagged as Picard tags them, read by `read_album_details`, each file's raw sorted (a FLAC's come in a set's
  order).
- **tests/test_ios_contract.py**: the fixture is what the helper makes now, byte for byte; the real route over the same
  folders answers the same (and a missing folder 404s); AlbumFile and AlbumFiles read what the route sends, leniently;
  AlbumTag's names, parsed from the Swift, are DETAIL_TAGS' for the named ones (status and type not among them), lower
  case for the raw ones, and find every tag in each container's answer.
- ClientTests: 61 routes, libraryTracks' 30 s.

### Verified, and not

**Verified**: `swift test` (DeadwaxKit, all of it); the unsigned Debug device build, no warnings, the .xcodeproj
unchanged; the full pytest suite. **Not verified** - only the phone and a real library can tell (docs/ios.md checks
260-270): that a real Navidrome sends the OpenSubsonic fields as its source says (no recorded answer of a 0.5x
getAlbum is in the repo); what Picard-tagged and deadwax-filed albums in the real library actually carry; how long the
tracks route takes on the NAS for a box set on a sleeping disk; the sheet's look at the largest text and with
VoiceOver; Copy; and Safari opening musicbrainz.org beside the app.

### Album info after review (2026-11-15)

The coordinator's review of 38b404a, every item fixed in one commit; still app 0.13, still no server change.

- **deadwax's own media, said once.** organizer.py's `write_tags` writes `media` as the job's `media_format` - the
  WHOLE release's formats joined " + " (GetRelease.swift's and releasePayload.ts's join) - into every file of the set,
  so per-disc folding read a 2-CD set as "2×CD + CD". `AlbumInfo.media` now takes the commonest value holding " + "
  once, split and folded as Pressings.format folds ("CD + CD" -> "2×CD"); without one, Picard's per-disc reading as
  before. The fixture gained two deadwax-filed cases, written by `write_tags` itself (album_files_answers.py's
  FILED_SET, a 2-CD FLAC set, and FILED_SINGLE, an M4A), and the contract test holds the join the same in all three
  places. The docs' claim that nothing goes into an M4A was wrong: Easy MP4 registers `releasecountry` (as
  `----:com.apple.iTunes:MusicBrainz Release Country`), so the country does - only media and the catalogue number
  don't (no Easy MP4 names), and the sheet reads the country raw from an M4A by that name.
- **An M4A's codec: a lossless allowlist, not a lossy list.** A depth is drawn only for Sources.losslessFormats
  (flac, alac, ape, wav, aiff, aif, wv) or an MP4 whose audio is ALAC. The rule for an MP4 (m4a, mp4, m4b), since
  Navidrome's suffix ("m4a") and type ("audio/mp4") never say: ALAC when the contentType names "alac", AAC when it
  names "aac", and otherwise ALAC only when the album's MP4 songs average over 400 kbps by length (`alacOverKbps`:
  iTunes and Apple Music AAC is at most 320, ALAC rarely under 500 even for quiet 16-bit music). Decided for the album,
  so one quiet song of an ALAC album isn't AAC. Said "ALAC" or "AAC", never "M4A". An ALAC quieter than 400 kbps is
  said as AAC with its bitrate - the error that never claims a depth for a lossy file. TagLib's 16 bits for an AAC
  never reaches the line.
- **The Bitrate line only for an all-lossless album.** A lossy kind says its bitrate on its Format line already, so a
  Bitrate line under it repeated it, and under a mix it averaged FLAC with MP3 into a figure nothing has. It shows now
  only when every kind has a depth.
- **No spinner left turning.** A cancelled asking (deadwax out of reach mid-read, the sheet going) used to leave its
  last `reading = true` answer standing. `ask()` now numbers each asking, and when one ends, its own last answer, if
  still reading, is marked not reading and `cut`; a later asking's answer is left alone. The offline line now shows
  whenever deadwax is out of reach and the answer isn't `complete` (nothing cut, failed, missing or still reading) -
  not only before any answer came.
- **Countries that have gone.** MusicBrainz still lists XC Czechoslovakia, XG East Germany, SU Soviet Union, YU
  Yugoslavia and CS Serbia and Montenegro, which Locale names oddly or not at all; they're named by MusicBrainz's own
  words ahead of Locale, with XW and XE. XU (unknown) is no country: no Country line.
- **Failures said, in a listener's words.** getAlbum failing, the bridge failing, the files failing, and getAlbum
  answering no album, each said once under the sections through ErrorNote / ErrorWords.of (`albumFailed`,
  `storeFailed`, `filesFailed`; a 404 as `ErrorWords.albumGone` or `filesGone`) - the first of them in that order,
  since a later one follows from an earlier. A bridge with no folder (an album not matched to MusicBrainz) is no
  failure, so it's said quietly (`noFolder`), not as an error. Info's playlist stub, whose own lines wait for getAlbum,
  now says why they never came when it fails.
- **Two folders read at a time** (`foldersAtOnce`), the next started as each lands: each read takes one of the
  server's threads and opens every file of a folder on a disk that may have to wake; eight at once was a box set
  holding a NAS's thread pool.
- **Words**: release types "dj-mix" -> "DJ mix", "mixtape/street" -> "Mixtape/Street", "spokenword" -> "Spoken word";
  ID3v2.3's "/"-joined values split (Mixtape/Street kept whole). "downloaded by deadwax" only when the earliest
  folder - the one Added's date is - is the one deadwax filed: a copy filed later beside an older one didn't make the
  older one deadwax's.
- **More container names**: ASF `musicbrainz/release group id`, MP4 `----:com.apple.itunes:originaldate`, ASF
  `wm/originalreleasetime`, and MP4's `----:com.apple.itunes:musicbrainz release country` (deadwax's own).
- **libraryTracks' 30 s, held.** Routes.swift's comment said the contract test held it; it didn't. It does now
  (`test_the_app_waits_for_an_albums_files_as_long_as_the_route_takes`): above the transport's own 8 s
  (URLSessionTransport.standardTimeout) and above settleSeconds, with the route still unbounded (`asyncio.to_thread`,
  no `wait_for`), and foldersAtOnce 2.
- **Info's Album info stays on the album it was opened for** (decided): the row is a value link
  (`NavigationLink(value: AlbumInfoPush)`) with `.navigationDestination(for:)` on Info's stack, so the pushed page
  isn't tied to the List, which Info draws afresh (`.id`) for each song. Before, a pushed page belonged to a row of a
  List that was replaced when the song changed - it could pop or change album under a reader. Following the song
  would change a page someone is reading; Back to Info shows the song now playing instead.

Tests after review: AlbumInfoTests 31 (deadwax's whole-release media, the deadwax-filed FLAC and M4A, AAC and ALAC
by type and by bitrate, the bitrate said once, release types, Added's earliest folder, the containers' names for the
dates and the group, the gone countries and XU); the contract test's tag expectations for both deadwax cases and the
new timeout test. **Verified** and **not** as before: the Core and contract tests, the device build, pytest; not the
sheet on the phone (checks 260-270, extended for AAC, the cut read, Info's push, the no-folder line).

## The cover, full screen (2026-11-15)

James: "maybe when you tap the album art in the play screen it should become full screen so you can zoom in and look
at it." Now Playing's cover opens full screen on a tap; there it pinch-zooms, double-taps in and out, pans, and closes
by a swipe down, ✕ or VoiceOver's escape. The rules are DeadwaxCore's `CoverZoom` and `CoverViewerWords`
(ios/DeadwaxKit/Sources/DeadwaxCore/CoverViewer.swift, tested on Linux); the app's half is two new files,
ios/App/Player/CoverViewer.swift (the tap, the presentation, the loading) and CoverZoomView.swift (the zoom), and one
line in NowPlayingView.swift.

- **A tap, never the drag.** The cover is also Now Playing's grip: its `DragGesture` on the cover's room closes Now
  Playing by a drag down. The cover takes `.onTapGesture` alone (`opensCoverFullScreen(track, into: $viewing)`, after
  its clip), and since the review the room holds the grip as `.highPriorityGesture` (see "The cover and the index after
  review" below): a drag is the grip's from its first 6 points (`PlayerWords.dragStartDistance`), and the tap fires at
  lift only when no drag began. Only the plain cover's branch has it: Lyrics' and the turntable's places open nothing.
  Only a cover shown opens (`CoverZoom.opens`, after review); a song with no cover id isn't a button to VoiceOver.
- **The presentation**: `fullScreenCover(item:)`, on Now Playing's root since the review (`coverViewer($viewing)`),
  with the transaction's animations off (no slide up) and a
  `.clear` presentation background, then a 0.2-second ease-out fade of the viewer's own ground and cover; closing fades
  out first, then dismisses. The ground is `Palette.page`, new: theme.css's `--dw-bg` #000, the darkest of the app's
  grounds (`test_ios_cover_viewer.py` holds it to theme.css). The status bar is hidden while it shows. ✕ is a glyph
  on a 36-point square (scaled with the text since the review) of `Palette.card` in `Corners.controlShape`, with a
  44-point target, top right.
- **Drawn at once, then the full size.** The viewer opens on the cover Now Playing already has (CoverCache's
  largest step kept, 1024 down to 128; else the downloaded album's KeptCovers file at the hero size), then asks
  `fullCover(coverID:)` - the existing relay, `/deadwax/navidrome/cover/{cover_id}`, with no `size`, which the route
  leaves out of its getCoverArt call, so Navidrome sends the original (test_ios_cover_viewer.py drives the route with a
  fake transport to hold that). It's decoded off the main actor through ImageIO's thumbnail call capped at 4096 pixels
  on the longer side (a 6000-pixel scan as a full bitmap is 144 MB; capped, 64 MB), with the EXIF orientation applied,
  and crossfaded in over the drawn one (0.2 s; at once under Reduce Motion) where it was, keeping the zoom and the
  place. It's only shown if it's at least as big as what's drawn (`showsFull`). Offline it asks nothing. The last
  cover's bytes are kept, one cover at a time, so opening it again fetches nothing (only the decode again); a memory
  warning lets them go. Since the review the read stops past 30 MB and only a file up to 10 MB is kept.
- **The zoom: a UIScrollView, through UIViewRepresentable.** iOS 17's SwiftUI has no zooming scroll view, so a pinch
  about the fingers, a pan that carries on after a flick and stops at the edges, a spring past the zoom's ends and
  zoom-to-a-rect would all be gestures written by hand and tuned without a phone. UIScrollView is the way Photos'
  behaviour comes for free: `viewForZooming` the image view; centred by `contentInset` while smaller than the screen;
  `bounces = false` so a pan never pulls past an edge, with `bouncesZoom = true` so only the pinch springs back past
  its ends; double-tap is a two-tap recognizer and `zoom(to:animated:)` on the rect around the point tapped.
- **The numbers (decided here, not measured on the phone)**: the most zoom is twice the cover's native size on the
  screen, held between 3 and 8 (`maximum(pixels:fitted:scale:)` - a 600-pixel cover fitted 402 points wide at 3x is
  3; a 3000-pixel one is 5); recomputed when the full size lands, the zoom kept. Double-tap zooms to 2.5 (or the most,
  if lower), and from anything zoomed, back to 1. The close: a swipe down only when not zoomed (a zoom within 1% of 1
  counts), recognised by its own pan that the scroll view's pan waits on, beginning only downward and mostly
  vertical; the cover follows the finger and the ground fades to 25% over 300 points; let go 100 points down, or
  flicked at 900 points a second or more, and it closes; otherwise it springs back.
- **VoiceOver**: the scroll view is one element, the image named for the album ("Cover of Dummy, by Portishead"),
  adjustable - swipe up and down zoom by twice, half (snapping to 1 under 1.5) - its value "Not zoomed" or "Zoomed 2.5
  times"; zoomed, three-finger scrolls move by a screen and say where ("Showing the top left of the cover"); the
  two-finger Z (accessibilityPerformEscape, on it and on the viewer) closes it. ✕ reads "Close". The viewer is modal,
  so VoiceOver doesn't wander back into Now Playing beneath it.
- **Nothing in the player moved**: the viewer reads the QueueTrack it was handed and the cover caches; no engine
  file, no audio call (`test_ios_cover_viewer.py` holds that the new files never name the player).

**Tests**: CoverViewerTests (DeadwaxCore: every CoverZoom rule, every word, and that `fullCoverRequest` sends no size
and asks for an image, the sized one unchanged) and tests/test_ios_cover_viewer.py (the tap after the clip and only on
the cover's branch, the grip's DragGesture unchanged, the presentation and its black, the three closes, the scroll
view's edges and double-tap, VoiceOver's element and actions, drawn-then-full, the player untouched, and the route
leaving size out).

**Verified**: the Core tests and the full swift test, the unsigned Debug device build (no warnings), the source tests
and the full pytest suite. **Not verified** - only the phone can tell: a tap and a drag on the real cover (that a slow
drag never opens it), the fade, the full size landing without a jump, the pinch's feel and its limits, the edges
stopping dead (rather than Photos' little spring), whether Now Playing shows through the fading ground as you drag
(the clear presentation background says it should), VoiceOver's reading, and the music going on undisturbed
(docs/ios.md checks 271-278).

## The letter bar beats momentum (2026-11-15)

James: "if the library is still scrolling by momentum, I can't use the letter bar on the right side. I'd like that
seek bar to override the momentum." Flick Albums or Artists, touch the index while the list still glides: the tick
came, but the list flew on as if it hadn't been touched.

**The cause, found before fixing.** No Simulator here, so a probe: a Catalyst app built with swiftc
(`-target arm64-apple-ios17.0-macabi`, scratch only, never committed) running the same SwiftUI and UIKit as iOS 27.2,
with the app's shape - a ScrollView of 400 rows in a ScrollViewReader, a strip of the index's look as its
`.overlay(alignment: .trailing)` with the same `DragGesture(minimumDistance: 0)`, and the Library's pager around it
as a mode. It found the scroll views by walking up from inside the content, hit-tested the strip and the list
(`hitTest(_:with:)` at each), swizzled UIScrollView's `setContentOffset:`, `setContentOffset:animated:` and its
private stop methods to log who called what, and flung the list with UIKit's own private simulated scroll (a
translation of 1,500 points over 0.06 s, as a finger's flick) before jumping to row 100 in the middle of the glide.
Two things came out:

1. **The strip's touch never reaches the list's UIScrollView.** The hit for a point on the strip was the hosting
   view, with no scroll view anywhere in its chain; a point on the list had the list's. So the touch can't stop the
   list as a touch on the list does (UIScrollView stops its own deceleration on a touch-down inside itself), and the
   list can't swallow it either - the strip's gesture does run, which is why the tick came. (The pager mode looped
   SwiftUI's layout on Catalyst, so the hit test is from the page alone; with the pager, the walk up from the content
   met the list's own scroll view first, then the pager's - which is what the fix relies on.)
2. **A ScrollViewReader jump during a deceleration is unreliable.** `proxy.scrollTo(100, anchor: .top)` made while
   the list decelerated held in four flings of seven and was dropped in three (one of those a fling that only
   bounced at the top): in the dropped ones SwiftUI never set the offset at all and the list glided on to 13,490 of
   17,600 points. In the ones that held, SwiftUI had called UIKit's private stop itself - so whether it does is a race
   with the deceleration's frame. The same fling stopped first with `setContentOffset(contentOffset, animated: false)`
   - public, and UIKit's own way to end a deceleration (it calls the private stop with the delegate told, which the
   `contentOffset` setter doesn't) - then jumped, landed on row 100 (4,359 = 4,400 less the inset) in seven of seven,
   including from the very bottom.

The phone was not probed: there is no touch injection to it from here, so whether iOS 27.2 on an iPhone races the
same way is what check 279 asks. Catalyst's scroll view is iOS's, not AppKit's, so the cause should carry.

**The fix**: `MomentumStop` (ios/App/Library/MomentumStop.swift). Each strip screen keeps one (`@State`), puts
`.stopsMomentum(momentum)` on its ScrollView's content - a view of no size at the content's top, taking no touch and
hidden from VoiceOver, that finds the nearest UIScrollView up its superviews (the list's own; the pager is further up)
and holds it weakly - and hands it to `ShelfIndexStrip(momentum:)`. At touch-down, the first `onChanged` (press
still nil), the strip calls `momentum.stop()` before reading the entry and jumping; VoiceOver's "Jump to" buttons do
the same. `stop()` does nothing unless the list is decelerating - UIKit's own "the finger is up and it glides on"
(the `isDragging` guard it had at first was dropped in review) - so a list at rest is untouched. Everything else is the strip's as it was: entryAt over the strip as drawn at
touch-down, the jump at once, the haptic tick per jump, the strip's own DragGesture, and the pull to shuffle on the
same ScrollView. The only two uses of the strip are AlbumsScreen (grid and list, Title, Artist and the Year sorts) and
ArtistsScreen.

**Not taken**: putting the strip in a ZStack beside the list rather than over it (it already is outside the list - that
is the cause, not the cure); `highPriorityGesture` or `simultaneousGesture` (nothing competes with the strip's
gesture: it runs, and the tick proves it - the jump is what's lost); a UIKit gesture recognizer or touch surface under
the strip (the probe showed one does become the hit view, but the touch already arrives, and it wouldn't make the
jump stick); stopping by `isScrollEnabled` off and on (it also cancels a drag, and leaves the jump's race); and
`scrollPosition(id:)` (iOS 17's, the same SwiftUI scrolling underneath, with no stop).

**If the phone still loses the first touch** - no tick at all during a fling - the strip's SwiftUI gesture is what
doesn't begin there, and the next step is a UIKit recognizer for the strip's touch-down, calling the same stop and jump.

**Tests**: tests/test_ios_index_strip.py holds the stop at touch-down before the jump and in VoiceOver's action, the
stop's guard and UIKit's own call, the finder (nearest scroll view, no size, no touch, hidden), every screen drawing the
strip handing it its own list's stop from inside the ScrollView's content before the overlay, the pull to shuffle on
the same ScrollView, and the strip's DragGesture, entryAt and tick as they were.

**Verified**: the cause and the fix on the Catalyst probe (above); the unsigned Debug device build (no warnings); the
source tests and the full pytest suite. **Not verified** - only the phone can tell: a touch on the strip during a real
fling on Albums (grid and list) and Artists, and the Year sorts' decades - that it stops and jumps at once, with one
tick; that a list at rest, the pull to shuffle, a touch on the list itself and VoiceOver's Jump to are as they were
(docs/ios.md checks 279-281).

## The cover and the index after review (2026-11-15)

The review of e1b0653 and 06b6e4f, in one commit. Checks still 271-281.

- **The viewer closed itself as Lyrics took the cover's place.** `viewing` and `.fullScreenCover` were on the cover,
  the last branch of Now Playing's Lyrics / turntable / cover switch. With Lyrics on and a song with none, the next
  song (or deadwax coming back, `.notKept` to `.unknown`) made `lyricsShown` true, the cover's branch went, and the
  viewer with it, mid-zoom. Now the state is Now Playing's (`@State private var viewing: ViewedCover?`) and the
  presentation is on its root beside its sheets (`.coverViewer($viewing, onDismiss: eqAfterSheet)`, in
  CoverViewer.swift); the cover keeps only the tap and VoiceOver's button (`opensCoverFullScreen(track, into:)`, a
  binding). test_ios_cover_viewer.py holds where it lives: in `var body` after the root's offset, after the sheets,
  once, never in `content(_:)`, and CoverOpens with no `@State` and no presentation.
- **The tap against the grip.** A child's `.onTapGesture` under a parent's plain `.gesture(DragGesture)` has
  precedence, so the drag began only once the tap failed - at the tap's own slop, which is undocumented, not at the
  grip's 6 points: the sheet could start late and jump, and a short drag could open the viewer. The cover's room now
  holds the grip as `.highPriorityGesture(grip)`: the grip wins from its first `dragStartDistance`, and the tap fires
  at lift only when no drag began (the drag fails at lift if it never moved 6 points). Only the room changed: the top
  row keeps its plain `.gesture(grip)` (its chevron and look button are buttons, which a high-priority drag would sit
  over), Lyrics and the turntable are outside the grip as before, and the transport, scrubber and footer have their own
  gestures. Read from SwiftUI's documented precedence, not measured - check 271 is the phone's word on it.
- **Placeholder or failed covers (check 272 was wrong).** Navidrome gives nearly every song a coverArt id, and answers
  an album with no art with its own placeholder - so "a song with no cover opens nothing" almost never held. Decided:
  a cover opens once a picture of it is shown - drawn by Now Playing (any size in CoverCache) or kept with a downloaded
  album (`CoverZoom.opens(coverID:drawn:kept:)`, Core-tested). Navidrome's placeholder is such a picture (deadwax can't
  tell it from art: a 200 with an image) and opens as drawn; the grey square of a cover still loading or that failed
  opens nothing, and VoiceOver's double-tap on it says "The cover hasn't loaded." (`CoverViewerWords.notYet`). The
  button is hidden from VoiceOver only for a song with no cover id. Not covered: CoverCache (an NSCache) letting go of
  Now Playing's cover while it's still drawn would make a tap open nothing until it's drawn again - unlikely within 96
  MB, with Now Playing's the cover used last.
- **The spinner and the empty square** are under the image's fade, follow the drag down (`offset(y: dragged)`), and
  take no touch (`allowsHitTesting(false)`) - the zoom beneath has them, so a drag down on them still closes; the
  square is hidden from VoiceOver (the zoom is the cover, named, already).
- **Size caps.** The full cover is read no further than `CoverZoom.fullMostBytes`, 30 MB (a 6000-pixel JPEG scan is
  about 5 to 15): `fullCoverRequest` sets the new `HTTPRequest.mostBytes`, and the app's transport reads such a request
  through a delegate (`CappedRead`, its own URLSession, let go as it ends), refusing at the answer when its
  Content-Length is past it and calling the task off as the body passes it otherwise (whether Navidrome sends a cover's
  length isn't checked here; the relay passes one on when it does) - throwing `HTTPTooLarge`, which the client passes
  on as itself, not as "no
  answer"; `fullCover` refuses a body past it too, for a transport that read it all. The cover drawn stays. A task
  cancelled (the viewer closed) calls the read off; a read that ended before anything waited is kept for it. After
  close, `FullCovers` keeps a file only up to `CoverZoom.keptMostBytes`, 10 MB (a 3000-pixel JPEG is about 1 to 5): a
  larger one is let go and asked again next time.
- **`MomentumStop.stop()`'s `!isDragging`** is gone: `isDecelerating` already means the finger is up, and the extra
  guard could only leave a real fling unstopped.
- **A shared EQ file while the viewer is up** waits for it too: `shared()` closes the viewer (instantly, with no
  fade) and its `onDismiss` opens the EQ, as Up Next and Info do.
- **✕ at the largest text sizes.** Its glyph grew with Dynamic Type inside a fixed 36-point square. The button is a
  view of its own now, its square `@ScaledMetric(relativeTo: .body)` from 36, and the viewer holds it at
  `...DynamicTypeSize.accessibility1`, so the glyph and its square grow together and stop there.
- **The safe area (met in the merge of ios's b70e4a9).** "The Library's top, clear of the Dynamic Island" holds the
  list of views that reach under the status bar, each a fill or keeping its content in the safe area. The viewer's two
  are on it now: its black ground, a fill, and the zoomed picture, edge to edge as Photos' is, with the status bar
  hidden; at rest a square cover fitted to the width sits well clear of the island, and ✕ keeps to the safe area
  (test_ios_palette.py holds all three).

**Tests**: CoverViewerTests adds the request's 30 MB and the sized one's none, a body past 30 MB refused and one at
it read, a transport's HTTPTooLarge said as itself, the 10 MB kept rule and the opening rule;
test_ios_cover_viewer.py adds the presentation's place, the grip's priority on the room alone, the EQ's wait, the
placeholder, the caps through the transport and the ✕'s scaling; test_ios_index_strip.py holds the stop with no
isDragging.

**Verified**: the Core tests and the full swift test, the unsigned Debug device build (no warnings), the source tests
and the full pytest suite. **Not verified** - only the phone can tell: the grip from its first points and the tap at
lift (check 271), the placeholder and the grey square (272), ✕ at the largest text (276), and the viewer staying up as
the song changes with Lyrics on, and a shared EQ file (278). The capped read hasn't met a real file over 30 MB.

## Pull to shuffle on an album's and a playlist's page (2026-11-15)

James: "also let's add pull to shuffle to the album and playlists pages". The Library's pull (Phase 4, slice 3b, above)
on two more pages: an album's (ios/App/Album/AlbumView.swift) and a playlist's (ios/App/Playlists/PlaylistView.swift).
Nothing new to draw or measure - Core's `PullShuffle`, the App's `ShufflePull`, `.pullsToShuffle(_:)` and
`PullShuffleGraphic` are reused as they are, not forked. The app stays 0.13 (13); src/__init__.py untouched; no server
change; the player engine has no diff.

### What it does

- **Each page keeps one `ShufflePull`** and puts the Library's modifier on its `List`, right after `.listStyle(.plain)`:
  `PullShuffling(state: pull, can: can, on: …, start: pulled)`. It pulls while the page is the one on top - the
  album's existing `shown`, and a new `shown` on the playlist's page (its `onAppear`/`onDisappear`); the playlist's not
  while Edit is open (`on: shown && !editing`: Play and Shuffle wait while Edit is open, and the List is in edit mode).
  A page that stops pulling mid-pull is reset by the modifier's own `onChange(of: on)`.
- **The graphic is the hero's overlay**, `.overlay(alignment: .top)` with its top guide at its own bottom - so its foot
  is the hero's top and it is drawn upward into the room the pull opens, as the Library's is drawn over a zero-height
  anchor above its first row. A List row can't be zero high without changing every row's minimum, so the hero carries
  it. `PullShuffleGraphic` gains `of: PullShuffleOf` (`.library` by default, so the Library's four pages are
  unchanged; `.page` here), which only changes its line for the songs on this phone.
- **What it can do is `ShuffleCan.page(songs:phoneOnly:onPhone:)`** (Core), from the very songs the hero's Shuffle
  takes: the page computes `playable` once per draw and hands it to both the hero and `pullCan`. `songs` is the page's
  songs in hand (0: still loading, failed, gone, an empty playlist - `.none`, nothing drawn, never armed);
  `phoneOnly` is exactly the condition under which `playable` keeps only the songs on this phone (album:
  `!online || goneButHere`; playlist: `!online`); with some there `.downloads`, with none `.nothingHere`.
- **The release is the hero's Shuffle**: `pulled()` calls `play(at: nil, shuffle: true)` - the same call, so the same
  queue, source and level: the album through `player.play(songs:album:at:shuffle:)` as the album, the playlist through
  `player.play(playlist:at:shuffle:)`, each song with its own album, at the songs level. It runs in the scroll phase's
  change that ends the touch, nothing awaited first, as the Library's does. Should the phone-only list have emptied
  between the draw and the lift (a removal), it says "Nothing on this phone to shuffle" and plays nothing, as the
  Library's `shuffleNow` does.

### Decided here (the ask was silent; each the way the Library's pull already does it)

- **The pull never refreshes these pages now.** Both Lists had `.refreshable`; UIKit's refresh control starts its
  refresh during the drag, at a distance of its own, and holds the content down while it spins (UIKit's behaviour as
  known, not measured here), so one pull would do both. The Library's switch made the same choice (James: the
  Library's pull never refreshing), and both modifiers are gone.
- **Refresh moved to the bar's •••**, as the Library's ••• has it: `QueueMenuRequest.refresh`, drawn last in the
  menu's last section (after Album info and Edit in the web app) with the Library's own word and symbol
  (`LibrarySwitchWords.refresh`, `arrow.clockwise`). It does what the pull did: online, the album and its store row
  asked afresh (`AlbumModel.refresh`), the playlist asked again (`model.load`); offline, `reachability.tryNow()`.
  The playlist was already asked each time it shows and as the app comes back to the front, but the album wasn't -
  the ••• is how a change made in the web app's Edit is seen without leaving the page. On iOS 17, where there is no
  pull, it is now the only way, as the Library's ••• is there.
- **An album that failed with nothing drawn has Try again** (`LibraryWords.tryAgain`, the same `refresh()`): its
  ••• is dimmed with no songs in hand, and the pull was its only retry. Its own List row, so the error note's
  disclosure (for whoever runs deadwax) keeps its own tap - a second button in one List row would take the row's tap
  too - and no raw spacing is needed. Not for an album that is gone (a 404 or `{}`). The note's words now leave
  trying again to the button (`retry: true`). The playlist's first-load failure already had Try again.
- **Offline, a page shuffles only its songs on the phone**, said in its own words - "Pull to shuffle the songs on this
  phone" / "Release to shuffle the songs on this phone" (`PullShuffleWords.pullHere`, `releaseHere`) - not the
  Library's "your downloads", which would read as every song on the phone. "The songs on this phone" is the album
  page's own phrase for an album gone from the collection (`DownloadWords.albumGoneHere`), and that album pulls the
  same words online.
- **Offline with the page's songs in hand but none on the phone**: drawn, never armed, "Nothing on this phone to
  shuffle" - the Library's `.nothingHere`. **Offline with no songs in hand** (an album never opened online, a playlist
  not kept): nothing drawn - the page already says it isn't on this phone, and a page that can play nothing pulls
  nothing, as the Library's draws nothing with no songs at all (`.none`).
- **VoiceOver** doesn't read the graphic (it is hidden, as the Library's); the hero's Shuffle is the way there, as the
  Library's ••• Shuffle is for its pull. **Reduce Motion** and **iOS 17**: as the Library's.

### It works on a List (measured, not assumed)

Every page that pulled before was a ScrollView; these two are Lists. iOS 18's `onScrollGeometryChange` and
`onScrollPhaseChange` are documented for scroll views without saying which, so a scratch Catalyst probe (built with
swiftc, `-target arm64-apple-ios18.0-macabi`, never committed - as "The letter bar beats momentum" did, the same
SwiftUI and UIKit as iOS 27.2) ran the App's own PullShuffleView.swift and Core's PullShuffle.swift, with Palette and
Typeface stubbed, on a NavigationStack holding a plain `List` with an inline title and a toolbar item - the album
page's shape - its first row carrying the graphic as the pages here do:

- The List is SwiftUI's `UpdateCoalescingCollectionView`, with a 95 pt adjusted top inset under the bar. The geometry
  read the pull as 0 at rest, then 20, 60, 100, 115, 130 as the offset was set past the top.
- UIKit's own simulated drag (`_simulateScrollWithTranslation:duration:willBeginDragging:…`, UIScrollView's private
  method) gave the phases idle -> interacting -> decelerating -> idle, as a ScrollView's. A drag of 450 points down
  (rubber-banded to about 200) armed with one tick and, at the lift, shuffled once (`start` called once), the machine
  `released` until the List was back at rest, then idle; a drag of 150 (about 75) never armed and shuffled nothing; a
  drag the other way scrolled the songs and drew nothing.
- Snapshots of the window at 60 and 130 points: the ring and "Pull to shuffle", then the purple disc and "Release to
  shuffle", drawn above the first row in the room the pull opened, not clipped by the row's cell.

Not measured there: a real finger, the haptic, the iPhone's own bar (Catalyst's was transparent), and the order of a
call's or Siri's interruption against the lift.

### Tests

- **PullShuffleTests**: 11 to 13. `whatAPagesShuffleCanDo` - every state: online with songs, none in hand, offline
  with some, all and none here, offline with no songs in hand, and `starts` for each. `aPagesWords` - the page's
  lines for each `ShuffleCan`, the Library's unchanged by the default `of`.
- **tests/test_ios_pull_to_shuffle.py** (new, 8), read from the Swift as the other iOS tests are: one ShufflePull per
  page; `.pullsToShuffle` the List's own modifier after `.listStyle(.plain)`, with when it pulls; no `.refreshable`
  left; the playlist's `shown`; the graphic the hero's top overlay, its foot at the hero's top, `of: .page`, once per
  page; `pullCan` from `playable` with `phoneOnly` the very condition `playable` keeps the phone's songs under; the
  release the hero's Shuffle call with nothing awaited and the empty case said; the player's calls as they were; no
  gesture added (DragGesture, `.gesture`, high-priority or simultaneous) on either page or the pull's view; Refresh in
  QueueMenuRequest and drawn last, offline a probe; the album's Try again; and the Library's four pages still drawing
  the graphic with the library's words.

### Verified, and not

Verified: the probe (above); `swift test`; the unsigned Debug device build with no warnings in the files touched; the
full pytest suite.

Verified on the phone (15 Nov), James on 267ea8f's build: "pull to shuffle works on albums and playlists too".

Not verified - only the phone can tell (docs/ios.md checks 282-288, beyond that):
- The pull on a real finger on both pages, in detail: the tick once per arming, the graphic in the gap above the cover and clear
  of iOS's own bar at every text size, the music starting at the lift.
- That nothing fights it: Back's edge swipe, the ••• menus, Album info, a song's tap and a fling's bounce at the top.
- A pull a call, Siri or Notification Center cuts short shuffling nothing (the Library's wiring, check 95's caveat).
- Edit on a playlist's page showing nothing when pulled; Try again on an album that couldn't load.

## The artist's albums you don't have (2026-11-15)

James: "also on the artists page I'd like to also see albums I don't have yet". The library's artist page
(Artist/ArtistView.swift) now lists, among your albums, their albums on MusicBrainz that you don't have, as the web's
artist page (ArtistPage.tsx, lib/artistPage.ts's `artistRows`) does: each album once. Still app 0.13 (13); the
.xcodeproj unchanged (ArtistJoin.swift is in the package, the views in the synchronized folder).

**No server change, and no new route** (Routes.all stays 61). Who the artist is comes from `GET /artists/{id}`, which
passes Navidrome's `musicBrainzId` through, and from `/library/owned`, which Search already asks. Their albums come
from `/search_musicbrainz/discography`, asked by the MusicBrainz artist page's own model (MBArtistModel). The covers
come through the Cover Art Archive relay (ArchiveCover).

### Core (DeadwaxCore)

**ArtistJoin.swift** (new):

- `mbid` is the web's `artistMbid`. It takes Navidrome's own id for the artist. Without one, it takes what the
  library's folders say: folders of their albums' releases, or (when none of their albums carries a release id)
  folders filed under their name. It answers only when every folder that says agrees, and only on a single artist's
  id. Otherwise it is nil, and no guess is made.
- `claimed` is `artistRows`' own claim: which of MusicBrainz's groups an album of yours already is.
  - A group is claimed by its folders' releases, when they are an album Navidrome has that no other group claimed
    first.
  - Or it is claimed by an exact folded title, but only when no other listed group shares that title (a group listed
    twice counts twice), and only for an album whose release no folder ties to a group of its own (`knownGroup`).
- `theirs` is `MBArtistPage.rows` without the claimed groups.
- `rows` is your rows as `ArtistPage.rows` makes them, with theirs merged in among them by the web's order: the
  newest year first (compared as words), the undated last, then the folded title, then the key. `playOrder` takes your
  rows alone.
- `drawsTheirs` and `Foot`/`foot` decide when their rows are drawn and the one thing said under the rows.

### The app

- **ArtistPageModel**
  - `discography`: an MBArtistModel for the artist's MusicBrainz id. It is made again when the id changes, and let go
    (standDown) for none.
  - `theirAlbums(mbid:client:online:retry:)`: asks once, never offline, and never while an ask is out. After a
    failure it asks only with `retry`, and only then past the session's answer.
  - The id and the joined rows are kept until the artist's answer, MusicBrainz's groups or the library's folders
    change. The library is tracked by SearchModel's new `ownedVersion`. The view is drawn again as each album's songs
    land and as the name scrolls into the bar, and the id's fallback reads every folder.
- **ArtistView**
  - It asks `/library/owned` (`search.refreshOwned()`) as the page opens.
  - It asks their albums once the id is known, again with the id.
  - It waits `SearchPacing.ownedWaitMs` (1.5 s, the web's `ROWS_WAIT_MS`) at most for the library before drawing
    their rows.
  - It draws the joined rows: yours with ArtistAlbumRow, as before, and theirs with the MusicBrainz page's
    MBArtistAlbumRow (made non-private for this).
  - Under the rows, MusicBrainz's foot, once.
  - The Albums heading gains Studio only at its end.
  - Play, Shuffle, their line and the empty and offline states all read `ArtistPage.rows` (yours), as before.
- **SearchModel** gains `ownedVersion`, bumped whenever `ownedIndex` changes.

### Decided here

Each of these follows the web unless it says otherwise.

- **Finding the artist** is `artistMbid` exactly, held to the web by 17 vectors.
  - With no id, the page is today's, and says nothing.
  - **Departure:** the web says "Only the albums you have are shown - their other albums can't be found." The brief
    was that with no id the page says nothing went wrong.
- **Which are yours** is `artistRows`' claim exactly, held by 92 vectors.
- **Your rows are unchanged.** They keep Navidrome's title and year, "1994 · in your library", one row per album (two
  pressings stay two rows), ticks as before, and they open and play as before.
  - **Departure:** the web draws a claimed album as MusicBrainz's group: its title, its first year, the kind, and
    "· 2 pressings".
  - Because of that, the merge compares a row of theirs with yours by your album's own title and year. An album of
    yours dated by its pressing sorts by that date, as it did before.
  - Your rows never move among themselves; theirs come in between them.
- **The order** is the web's: newest year first, undated last, then folded title, then key.
  - Yours and theirs never tie, because `album:` keys sort before `group:` keys.
- **Their rows are the MusicBrainz artist page's.**
  - Each shows its cover through the relay, its title, and MBArtistPage's line ("2008 · Live album · not in your
    library").
  - A tap opens the album you don't have's page. A row held only by the store's word ("in your library", ticked)
    opens yours through the id bridge, spinning meanwhile, and lets go on a tab change, Now Playing or leaving (as that
    page does).
  - No Get chip on a row, as that page has none: Get is on the album you don't have's page.
- **Studio only** is on by default, at the heading's end, as on the web.
  - **Departure:** it is shared with the MusicBrainz artist page's per-artist memory (MBArtistModel's session
    `keptStudio`), so turning it off on one turns it off on the other. The web keeps the library page's and the `mb:`
    page's separately (keptArtists is by route id).
  - **Departure:** the toggle is laid out from the first frame and hidden until the id is known, so the heading is one
    height before and after. The web's chip appears with the id. The cost is that the heading of an artist MusicBrainz
    doesn't know is a few points taller than before. That is the only change to such a page.
- **When their rows come in.** Your rows never wait. Theirs are drawn once MusicBrainz has answered and the library
  has answered (or 1.5 s has passed), so that an album the library's folders alone tie to a group is never drawn as
  one you don't have and then taken away.
  - The web holds all its rows until every answer is in, or 1.5 s has passed. Within those 1.5 s the phone draws
    yours first, and theirs then come in among them once: the one movement the web doesn't have. The brief put "your
    albums never wait" first.
  - After that, the phone moves as the web does.
  - Studio only keeps the last answer on screen until the new one lands.
  - An answer the session kept draws at once.
- **What is said under the rows**, once (ArtistJoin.foot):
  - "Loading their albums…" while asking, and during the moment theirs wait for the library.
  - Their trouble, with **Try again**: MusicBrainz away is MBArtistPage.away; anything else is ErrorNote, in a
    listener's words.
  - "Showing their first 500 albums." at the cut.
  - "No studio albums found - turn off Studio only to see them all." only when the page has no row at all, as the
    web's `!rows.length`.
- **Asking again.** A pull, or deadwax coming back, asks MusicBrainz again only after a failure (and asks for the
  first time when the page opened offline). An answer in hand is the session's for `MBArtistPage.kept` artists, as on
  the MusicBrainz page.
- **Offline.** Nothing of MusicBrainz's is drawn, said or asked: the page is today's. Their rows come back with
  deadwax, from the session's answer.

### Tests

- **ArtistJoinTests** (9) cover:
  - your rows never waiting;
  - an album you have never listed again (by release, by title, before the library answers, twins, a bootleg's
    group);
  - theirs among yours, newest first, with their lines;
  - the key tie-break;
  - Play;
  - the wait for the library, and offline;
  - the foot's choices;
  - who they are;
  - 400 seeded pages where yours never move and the merge keeps the web's order.
- **ArtistVectorTests** checks the `joined` vectors (92: 60 crossed fixtures, 30 seeded, and two of one release under
  two groups) and the `mbids` vectors (17). They are exported from lib/artistPage.ts by
  ios/scripts/export-artist-vectors.cjs and checked by ui/test/iosartists.sim.cjs.
- **tests/test_ios_artist_discography.py** reads these from the Swift:
  - Play and Shuffle take yours alone;
  - offline nothing of MusicBrainz's is drawn, said or asked;
  - a row of theirs is the MusicBrainz page's (its model's open, its relay cover, standDown);
  - the trouble is said once, through ErrorNote and Core's words;
  - the library is asked as the page opens.
- **Mutations.** 17 mutations of ArtistJoin.swift were tried, each alone; 15 were killed.
  - "An album claimed twice" survived the first round, so the two "release under two groups" vectors were added; it
    is killed now.
  - Two mutations are equivalent, and survive because nothing can tell them apart:
    - Ties going to theirs: the keys never tie.
    - The first album of a release kept versus the last: either claims the same group, and a group's folders carry
      its id, so the other album's title claim is blocked by `knownGroup`.

### Verified, and not

**Verified**:

- `swift test` (all of DeadwaxKit);
- the unsigned Debug device build, with no warnings in the touched files;
- the full pytest suite;
- the iosartists sim's `--check`.

**Not verified** (docs/ios.md checks 300-309):

- a real artist's discography against the web's, side by side;
- whether rows of theirs coming in above the visible ones move what's under a finger when the list was scrolled
  before MusicBrainz answered;
- the Studio only toggle's look in the heading, and the hidden toggle's few points;
- the id bridge from this page on a real library;
- VoiceOver.

## Settings, pages like iOS Settings (2026-11-16)

James: "also instead of "you", let's just use settings", and "with maybe some better organization, and maybe some
dropdowns instead of big lists". Asked how to organize it, he chose **"Pages, like iOS Settings"**: a short list of
groups at the top, each opening its own page, and on a page each choice one row with a menu, not a list of ticks. The
app stays 0.13 (13); src/__init__.py untouched; no server change; the player engine has no diff. The web app keeps
its You - the phone departs on purpose, and says so where the web's words are held. The managing tools stay the web
app's in this change (other slices make them native); Needs a look's count isn't on the root yet.

### What changed

- **The tab is Settings**, drawn with `gearshape` (`person.crop.circle` was You's): AppTab.you's words are
  `YouWords.title`, now "Settings", so the tab bar, VoiceOver's label, the Large Content Viewer and the root's title
  all say it. The words that named the tab say Settings: the Download over / storage limit / only-while-charging
  lines of an album's download menu ("- in Settings > Downloads."), Debug's two Your library lines, and the Sources
  sheet's nothing-lossless note ("You can change it in Settings, under Getting albums."). Change password's line still
  says "Opens the web app's You": it is about the web app's tab, which is still You.
- **The root** (YouView) is the headline and its UNVERIFIED footer as before, then three groups:
  - **Getting albums**, **Playback**, **Downloads** - one section, Downloads last so its footer (DownloadsFooter, split
    out of DownloadsRow) sits under its row; Downloads keeps its size at the right.
  - **Manage**: ManageSection exactly as it was - the rows Managing.tools gives, each a WebAppRow opening Safari, the
    footer as before - only placed under the groups.
  - **Account** (only with `YouLines.account`, logins on), **This phone** - the server's host at its right
    (`ServerAddress.host`, new in Core: the name or IP alone, IPv6 in its brackets) - and **About**, the app's own
    version at its right ("0.13 (13)", `YouView.appVersion`). Both values in the data face, as the pages draw them.
- **Five new AppRoute cases**, `.gettingAlbums`, `.playback`, `.account`, `.thisPhone`, `.about`, drawn by
  `appRoutes()` as GettingAlbumsPage, PlaybackPage, AccountPage, ThisPhonePage and AboutPage - each a List holding
  the section that was You's, with the page's own title in place of the section's header (dropped where it would
  only say the title again). Downloads, Change address, Debug and the EQ are pushed as before, now one page deeper.
- **Every list of ticks is one menu Picker** (`.pickerStyle(.menu)`): Getting albums' When I tap Get (GetMode),
  Quality floor (QualityFloor) and Format (FormatPreference.youOrder); Playback's Now Playing opens as
  (TurntableSettings.Look) and Normalization; and, on Settings > Downloads, Download over (DownloadOver) - the one
  tick list left on a Settings page, beside Storage limit, which was already a menu. The toggles (Confirm before
  cancelling, Pause winds the record down) stay toggles. No `"checkmark"` or `.isSelected` is left in ios/App/You.
- **What each choice's own line said moved into its section's footer, for the chosen one**: Normalization's
  (`player.normalization.note`) and Download over's (`DownloadWords.over(...).note`) now lead their footers, before
  the notes that were there, and are each Picker's `accessibilityHint` - so VoiceOver still hears what the chosen one
  does on the control itself. Getting albums' choices and the two looks had no lines of their own; their footers are
  as they were.
- **Who asks what, and when.** The root asks /me the first time it shows and on its pull, as You did. Getting
  albums' three are asked by **their page**: as it shows (`onAppear`), on its pull, and as deadwax comes back into reach
  - the three things You did for the whole tab. The root no longer asks for them: it draws none, and Get asks for
  itself (GroupView as the album you don't have shows, the Sources sheet before every search). About and Account ask
  /me on their own pull, since both draw from it (About's error note is the place a failed /me is said).
- **Tapped again**, the tab goes back to the root, then to the top - as it already did and as every tab does
  (AppNavigation.select pops a non-empty stack, else bumps `youScrollToTop`, which YouView scrolls on). Nothing there
  changed; with pages it now has somewhere to pop from.

### Held to the web, and where the phone departs

- **The tab's name**: export-you-vectors.cjs now reads the web's name for the tab out of lib/appRoutes.ts's
  TAB_LABELS (`you: 'You'`, a new `made_from` piece) into you.json's `words.tab`, and writes a `departures` list
  beside it, by hand: the tab's name, You on the web, Settings on the phone, since 2026-11-16 and why. ScreenYouTests'
  `theTabIsSettingsWhereTheWebSaysYou` holds `YouWords.webTitle` to the web's word and `YouWords.title` to the
  departure's, and fails if the two ever meet again. iosyou.sim.cjs still checks the fixture byte for byte (136 cases).
- **The nothing-lossless note** (NOTHING_LOSSLESS_NOTE, held by get-vectors.json): GetVectorTests makes the web's
  words the phone's by one named replacement, `GetVectors.phones` ("in You, under Getting albums" -> "in Settings,
  under Getting albums", built from YouWords' two titles), used for the note and for every list's VoiceOver
  announcement; `theTabsNameIsTheOneWord` asserts the web's note names You there exactly once, the phone's names
  Settings, and that the replacement is the whole difference. The get fixture and its exporter are untouched (the web
  didn't change).
- The Download and Debug lines that said "You > Downloads" are the phone's own (no web counterpart): their tests now
  say Settings.

### Decided here (the ask was silent)

- **Swift names kept**: `YouView`, `AppTab.you`, `AppNavigation.you` and `youScrollToTop`, `YouWords`, `YouLines`,
  the section types and the file names under App/You - renaming them was a large diff for nothing a person sees.
  RequestsWatch's tab string stays "you" (internal). New types: GettingAlbumsPage, PlaybackPage, AccountPage,
  ThisPhonePage, AboutPage (AboutPage in YouView.swift, beside the About lines it took), DownloadsFooter.
- **The order inside Playback is the web's**, as it was (Gapless, Now Playing opens as, Pause winds the record down,
  Normalization, EQ) - not the mock's (Normalization, Turntable look, Gapless, EQ), which illustrated the pages, not an
  order; and Gapless stays a value ("On"), never the mock's toggle: the phone can't turn it off (screens.md Open
  question 1). The mock's "Turntable look Wood" is today's "Now Playing opens as" (Cover, Turntable) - no new setting.
- **The root's order is the mock's**: Account, This phone, About (You had About before This phone).
- **Before deadwax answers, a Getting albums row shows nothing**: its Picker carries a blank choice tagged nil only
  while nothing is known, so the row's value is empty (no default claimed, as no tick was before) and SwiftUI has a tag
  for the nil selection. The row is `.disabled` until deadwax answers and while it can't be reached; a choice already
  chosen chooses nothing, as before.
- **Values on the root**: This phone shows the host only (the full address is the page's), About the app's version
  (deadwax's is "…" until /me answers). Getting albums and Playback carry none: their choices are long, and three
  values on one row would only be cut short.
- **A failed /me is said on About's page only**, where it was said before (under About). The root shows nothing of it
  beyond what it always did (no identity line); its pull asks again. A Needs-a-look-style count or warning on the root
  is left to the later slice.
- **Account's page is empty** if a pull finds logins off while it's open (it draws from the same `YouLines.account`
  as the root's row), rather than offering a Sign out there's nothing to sign out of.
- **The guide**: docs/ios.md's You section is Settings now (the root, then Getting albums, Playback, and Downloads,
  Account, This phone and About), "### You > Downloads" is "### Settings > Downloads" (its anchor with it), every
  guide line naming the tab says Settings, and the iPhone's own Settings app is "the iPhone's Settings" where the two
  could be mixed up (Background App Refresh). The numbered checks keep their words; one line at the top of the checks
  says how to read "You > ..." in them, and 310-319 are the new layout's.

### Tests

- **tests/test_ios_settings.py** (new, 10), read from the Swift as the other iOS tests are: the tab's words and gear;
  no `"You"` in the App's code and no Core string naming "You >", "in You" or "You, under" (Change password's line
  about the web app's tab held as it is); the root's rows in order, the Downloads group with its footer, the two
  values, nothing of the pages left on the root; Manage's rules and its WebAppRow; each page an AppRoute case drawn by
  `appRoutes()` with its title; each page holding its section (Account, This phone with Debug for an admin, About's
  error note, the EQ push); who asks what and when; every choice one menu Picker, no tick list left, the Getting
  albums Picker's nil tag, disabling and guard; the chosen line first in Normalization's and Download over's footers
  and their hints; and the tab tapped again popping, then scrolling.
- **ScreenYouTests**: `theTabIsSettingsWhereTheWebSaysYou` (new); the new made_from piece. **GetVectorTests**:
  `theTabsNameIsTheOneWord` (new); the note and the announcements through `GetVectors.phones`.
  **AddressAndCookieTests**: `theHostIsTheNameOrIPAlone` (new). **DownloadWordsTests**, **LibraryChargingTests**:
  Settings > Downloads.

### Verified, and not

Verified: `swift test` (all of DeadwaxKit: 1721 Core tests in 184 suites, 158 Audio, 12 more); the unsigned Debug
device build - BUILD SUCCEEDED, no warning in any file touched (the only one is appintentsmetadataprocessor's, as on
every build); the full pytest suite (4610 passed, 1 skipped), test_ios_settings.py's 10 among them; every `ui/test/ios*.sim.cjs` (20) with a writable TMPDIR, iosyou's `--check`
against the regenerated fixture among them.

Not verified - only the phone can tell (docs/ios.md checks 310-319):
- How the menus look and behave in a List on iOS 27.2: the value and its chevrons at the row's right, the menu's tick
  on the chosen one, a dimmed row before deadwax answers and offline, the blank value while nothing is known.
- The long values at the largest text sizes ("Pick the best source for me" beside "When I tap Get"): wrapped or cut.
- VoiceOver on a menu Picker: that it reads the name and the choice, the hint after it, and the new choice once
  picked; that a disabled one is read as dimmed.
- The root's two values beside their labels at every text size, and an IPv6 host.
- That Getting albums' ask on the page's appearance fires again on coming back to the tab with the page shown (it did
  for You's tab as a whole).
- The pops: Settings tapped from the EQ (two pages deep) back to the root, then to the top.

### After review (16 Nov)

One review of 3185583 found no bug in the code (the menus' bindings, what asks when, the routes, the departure from the
web's "You" recorded in the vectors) and these in the words, fixed in the commit after it:
- **About keeps deadwax's last version.** ServerModel keeps `me` across a failed ask and restores it at launch, so About
  shows the version deadwax last gave, with why it didn't answer under it - "Not known" only if it never has. The guide
  and check 317 had said "Not known".
- **The last "You"s naming the tab**: two in docs/ios.md's tables, troubleshooting.md's iPhone list, docs/README.md, the
  READMEs' phase lines (the README now says the tab is Settings), GetSettingsModel's comments.
- **"Settings" now names two things**, so every path into the iPhone's own Settings says so: "the iPhone's Settings >
  Privacy & Security > Local Network" in HTTP.swift's words (what can't reach deadwax says), and every such path in
  docs/ios.md.
- **What's not claimed any more**: a menu names each choice and nothing more, so a choice's own line (Normalization's,
  Download over's) shows only once it's chosen - before, each sat under its row. Apple's own Settings does the same; the
  name says what each does, and the footer says the rest once chosen.
- **Left as it is**: Getting albums' three are asked again on coming back into reach only while their page is open
  (before, while the tab had been opened). Sources asks before every search and an album you don't have asks as it
  shows, so nothing reads a stale floor or format for a Get.
