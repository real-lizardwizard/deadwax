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
                            Info/, You/ (DebugView is Phase 0's test screen); URLSessionTransport,
                            SessionKeychain, AudioSessionController, NowPlayingController, SongFiles (stream
                            cache, downloads); Icon/ loose PNGs
  DeadwaxKit/               Package.swift (tools 6.0; iOS 17, macOS 14)
    Sources/DeadwaxCore/    pure Swift + Foundation, Swift 6 mode, tested on Linux
    Sources/DeadwaxAudio/   the engine; every file inside #if canImport(AVFAudio); Swift 5 mode
    Tests/DeadwaxCoreTests/ Swift Testing, 64 tests in Phase 0, 508 in 69 suites at app 0.2
    Tests/DeadwaxAudioTests/  offline-render tests, macOS only (12 in Phase 0, 54 at app 0.2)
  scripts/                  install.sh (James's), install_helper.py (its JSON/plist reading, in Xcode's
                            python3), check-linux.sh, check_project.py, make-icon.py, make-test-album.py
  README.md                 a pointer to docs/ios.md and this file
.github/workflows/ios.yml   branches '**' + paths: ios/** and itself (never a tag: GitHub applies no paths
                            filter to a tag push) - linux (swift:6.4.1-noble), project (check_project.py),
                            macos (swift test with the engine's renders, then the UNSIGNED device build)
tests/test_ios_contract.py  the routes, fields and bounds the app relies on, against the server (8 tests)
tests/test_ios_install.py   install_helper.py, check_project.py, install.sh against stand-ins, and the
                            test album, on Linux (18 tests)
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
- **No Simulator runtimes on CI**: GitHub's macOS runners come with them; ios.yml deletes them before
  the device build (best effort, both lists printed), so a tool that needs one fails there as on
  James's Mac. Even so, a green ios.yml is no stand-in for check 1 (install.sh on his Mac).
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
failed on a file that wasn't on the Mac. The Once steps were begun on 2026-10-27 (Xcode's first launch, the
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

- **Routes.swift** names all 23 routes the app calls, one `Endpoint(method:path:query:)` a line in the form
  tests/test_ios_contract.py reads, all listed in `Routes.all`. `Routes.timeouts` gives album_index 30 s (D2),
  everything else the transport's 8 s; `CoverSize` is row 128, tile 400, hero 1024 (and the lock screen's 1024).
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
