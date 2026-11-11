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
  Config/                   Base.xcconfig (bundle id, MARKETING_VERSION 0.1, CURRENT_PROJECT_VERSION 1,
                            iOS 17.0, Swift 5 mode, signing Automatic, `#include? "Local.xcconfig"`),
                            Debug/Release.xcconfig (each includes Base), Local.xcconfig.example (the team
                            id; Local.xcconfig and `device` are gitignored), Info.plist (a plain file)
  App/                      the SwiftUI app: DeadwaxApp, AppModel (@Observable, @MainActor), ContentView,
                            URLSessionTransport, SessionKeychain, AudioSessionController,
                            NowPlayingController, SongFiles (stream cache, downloads); Icon/ loose PNGs
  DeadwaxKit/               Package.swift (tools 6.0; iOS 17, macOS 14)
    Sources/DeadwaxCore/    pure Swift + Foundation, Swift 6 mode, tested on Linux
    Sources/DeadwaxAudio/   the engine; every file inside #if canImport(AVFAudio); Swift 5 mode
    Tests/DeadwaxCoreTests/ Swift Testing, 64 tests
    Tests/DeadwaxAudioTests/  12 offline-render tests, macOS only
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
  own lane, started with `play(at:)` the host time the first lane's last sample plays (offline: the
  render's sample count). A song that would begin on a lane still holding songs that play before the
  one scheduled last (44.1 kHz, a short 96 kHz song, 44.1 kHz again) waits, its first buffer parked,
  until that lane has run out - see "After review, again". **The output starts once and keeps running while something plays**; a song
  started from silence is scheduled `startLead` ahead (AVAudioSession's outputLatency + ioBufferDuration);
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
  runs dry mid-song keeps its converter, so the song goes on unbroken (the position reads up to the
  filter's hold, under a millisecond, ahead). A configuration change makes the lanes again, since the
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
  (`manualRenderingSampleTime`).
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

**Not built yet: the screens** (the specs' screens.md: the tab bar, sign-in, the Library, the album page, the
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

### Verified (Phase 1's Core, p1/merge, 2026-11-10)

All on James's Mac (8 GB; heavy builds one at a time), Xcode 27.1's toolchain:
- `swift test --package-path ios/DeadwaxKit`, from a clean build: **DeadwaxCore 392 tests in 54 suites,
  DeadwaxAudio 54 tests in 2 suites**, all passing, no compiler warning (Phase 0 ended at 64 and 13; the merge
  at 389 in 53, before the review fixes' title test and FixtureFilesTests' two).
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

- **DeadwaxCore on Linux**: no Linux toolchain here, and none of Phase 1's Core has been compiled on Linux.
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
