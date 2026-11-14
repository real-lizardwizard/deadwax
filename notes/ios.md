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
                            Info/, You/ (DebugView is Phase 0's test screen), EQ/ (app 0.5: EQModel,
                            EQStore, EQRouteReader, and the screens - EQScreen, EQCurveView (and slice 5's
                            handles), EQSliders, EQPresetsScreen, EQOutputViews, EQNameAlert, EQRoute;
                            slice 4's EQCorrectionScreen and EQProfileScreen; slice 5's EQFilterEditor,
                            EQImport, EQExport); URLSessionTransport,
                            SessionKeychain, AudioSessionController, NowPlayingController, SongFiles (stream
                            cache, downloads); Icon/ loose PNGs
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
                            make-eq-fixtures.py (the EQ's fixtures; numpy and scipy, run with python -I)
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
