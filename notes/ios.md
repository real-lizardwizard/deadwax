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
  - **Fixed in 2.1.32: the cap counted bytes after decompression.** Found by the review of the artist pictures'
    relay, which has the same pattern. httpx asks for gzip by default, and `aiter_bytes()` decodes it, so a gzip body
    - or a nested `gzip, gzip` one - was inflated far past FRONT_MAX_BYTES before the count saw it: 141 MB from 269
    bytes on the wire, in the review. Now every hop sends `Accept-Encoding: identity`, and an answer whose
    Content-Encoding is anything but absent or `identity` is an ArchiveRefused (a 502) before its body is read
    (`sent_as_it_is()`, shared with the pictures' relay). Nothing is lost: covers are JPEGs, compressed already.
    tests/test_coverart_relay.py: identity asked on every hop, six encodings refused unread, `identity` passed on.
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
  fail; slice 2 should add one with what the phone shows.

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

## The artist pictures' relay (2.1.32)

Phase 8's server change B (notes/ios-specs/phase8-managing.md on `ios`, sections 4 and 12, decision 1): the app's
Artist images (slice 5) draws the candidates `POST /library/artist/images/preview` offers, and their `preview`s are on
other hosts - the web's ArtistPanel loads `candidate.preview` straight into an `<img>`. The app talks only to deadwax,
so deadwax passes them on. The web doesn't change.

- **The route**: `GET /deadwax/library/artist/picture?url=`, Edit albums' like the preview that names those
  addresses (`dependencies=EDIT` on the library router, which is included with `current_user` - never middleware;
  tests/test_logins.py ROUTES, "edit"). `url` is required, at most PICTURE_URL_MAX (2048) characters (422 otherwise).
  Answers: 200 with the picture as `served_image_type()` names it - and refused unless that is one of
  SERVED_IMAGE_TYPES (jpeg, png, gif, webp, bmp: never an SVG) - with `Cache-Control: private, max-age=604800` (a
  week: fanart.tv's and TheAudioDB's addresses carry the upload's own id, Commons' the file's title); 400 for an
  address the relay won't ask, before anything is asked; 404 when the host has no such picture (a 404 or a 410
  anywhere in the chain); 502 when it couldn't be had; 503 when PICTURES_PENDING_MAX asks are under way already,
  nothing asked; 504 when the host was too slow. Every refusal `no-store`, its `detail` one of routes/library.py
  PICTURE_WORDS - the phone draws the words either way. A 502 has two sets of words (the review's): "deadwax couldn't
  get that picture just now." when the host is away or in trouble, or deadwax faulted - worth asking again - and
  PICTURE_REFUSED_WORDS, "That picture's site won't let deadwax pass it on.", for a PictureRefused - a 403
  (Wikimedia's robot policy), a redirect elsewhere, not an image, too big - which asking again won't change. No ETag:
  nothing is kept to make one from cheaply. Under GuardMedia's headers and never gzipped: the path is in app.py
  MEDIA_PATHS (an exact path - the existing guard applied to one more route, no rule changed). FastAPI's own 401, 403
  (NEEDS' words) and 422 are as every route's.
- **With logins off** (the review's): anyone on the network is the implicit admin, so any page a browser on it opens
  can make deadwax fetch these pictures; the same-origin Cross-Origin-Resource-Policy GuardMedia sends stops that
  page reading what comes back. That is the cover relay's position too, and it stays: the fetch is of the five hosts
  alone, and the caps bound it.
- **The fetch** (src/api/artist_images_endpoint.py `ArtistPictures`, `artist_pictures`; closed with the app): its own
  httpx client beside ArtistImagesClient, `follow_redirects=False`. **Not a general proxy**: `picture_address()`
  parses the address once (the same parse is checked and fetched) and `passes_on()` lets through only `https`, no
  userinfo, no port but https's own (`:443` is normalized away), and a host - read from `raw_host`, never decoded,
  since httpx's `.host` raises for a malformed international name - exactly one of PICTURE_HOSTS. So
  `https://commons.wikimedia.org@evil.example/` (host evil.example), `https://evil.example\@commons.wikimedia.org/`
  (a user to httpx), an address by number, a subdomain, a trailing dot and the sources' API hosts are all a 400
  with nothing asked. `picture()` checks again, so nothing reaches the network unchecked. Each redirect is followed by
  hand, its target `passes_on()` or the answer is refused (502) and the target never asked; at most
  PICTURE_REDIRECTS (4) hops. A Location that isn't an address is refused the same way - httpx reads it itself even
  with redirects off, as its RemoteProtocolError "Invalid URL in location header", or idna's ValueError for a name
  that can't be decoded; a RemoteProtocolError of any other kind (the host broke off) is an outage. Only a declared
  `image/*` is read (anything else refused unread). **Undecoded** (the review's): every hop sends
  `Accept-Encoding: identity`, and an answer with any Content-Encoding but none or `identity` is refused unread
  (`sent_as_it_is()`, in coverart_endpoint.py) - before, httpx asked for gzip and `aiter_bytes()` inflated it, so the
  cap counted bytes after decompression (141 MB from 269 bytes of nested gzip, in the review); the cover relay had
  the same flaw, fixed in the same commit (above). So a Content-Length past PICTURE_MAX_BYTES is refused unread, a
  body read a piece at a time is the bytes that came and is refused as soon as it passes, an empty one refused.
  PICTURE_DEADLINE_SECONDS (7) for the whole fetch - the wait for a turn, every hop and the body - with httpx's 5 s
  between pieces and 4 to connect. The agent is `image_user_agent()`, moved out of ArtistImagesClient.user_agent
  (which now returns it): the MusicBrainz one with its contact, else `deadwax/<version>` - what Wikimedia, TheAudioDB
  and fanart.tv are already sent by Artist images. The outcomes, as ArchiveFronts': a picture (a memoryview of what
  was read - the answer goes out with no second copy), None (404 or 410), PicturesBusy (503), or PictureHostDown
  (unreachable, broken off, 429, 5xx: 502), PictureHostSlow (the deadline, an httpx timeout: 504), PictureRefused
  (this answer's own: off-list or broken redirect, not an image, encoded, too big, empty, another status - 403
  included - too many redirects: 502). A fault in deadwax while fetching is a 502 with its traceback in the log.
  Nothing is kept: no folder, no memory of a failure, each ask asks again.
- **Bounded**: at most PICTURES_AT_ONCE (6) fetches at once (a semaphore per event loop, as the cover relay's), and
  at most PICTURES_PENDING_MAX (64, the cover relay's PENDING_MAX - the review's) asks under way, waiting for a turn or
  fetching; one more is a 503 at once, nothing asked or remembered, and counted down whatever ends it. What is true
  of memory: **at most 6 bodies are being read at once, each refused past 8 MB - 48 MB being read, at most**; a
  waiting ask holds nothing but itself. A picture once read leaves both counts and is held until its answer is handed
  to the server to send, which neither count covers: in practice at once, but a phone reading slowly keeps its picture
  (at most 8 MB) alive that long. (The first cut's notes said "at most 48 MB is held", which wasn't so.)
- **The hosts** (PICTURE_HOSTS, where each came from):
  - `commons.wikimedia.org` - every Commons candidate's preview (`artists.commons_file_url`: the `image` relation's
    and Wikidata's P18/P154, Special:FilePath with `?width=`), and its own first hop.
  - `thumb.wikimedia.org` and `upload.wikimedia.org` - where Commons sends it: **seen by hand, 2026-11-16, with curl
    (not deadwax)**, `Special:FilePath/<file>?width=600` answers 302 to
    `commons.wikimedia.org/w/index.php?title=Special:Redirect/file/<file>&width=600`, which answers 301 to
    `thumb.wikimedia.org/wikipedia/commons/thumb/…/960px-<file>` for a file wider than asked (a 960px JPEG, 127 KB;
    an SVG logo as a 960px PNG, 60 KB - Wikimedia now rounds a thumbnail up to its own sizes) or to
    `upload.wikimedia.org/wikipedia/commons/…/<file>` for one no wider (Example.jpg, 9 KB, served as it is). The code
    named only upload.wikimedia.org (the robot-policy comments); **thumb.wikimedia.org was found only by asking**, and
    without it every Commons thumbnail would have been a 502.
  - `r2.theaudiodb.com` - tests/test_artists.py's fixture, and **seen by hand**: every image field of a row asked
    with TheAudioDB's public test key (Coldplay) is an `https://r2.theaudiodb.com/images/media/artist/…` address,
    which answers 200 at once (a thumb 89 KB, a background 178 KB). `www.theaudiodb.com/images/…` answers 404, so the
    API host isn't on the list.
  - `assets.fanart.tv` - **assumed**, from fanart.tv's API documentation: no code or fixture names it (the fixtures
    use `https://f/…`), there is no project key here to ask with, and on 2026-11-16 the host couldn't be reached
    from where this was built (something on that network answered for it with a certificate of its own). Whether the
    host redirects is unseen.
  - **fanart.tv over https** (the review's): fanart.tv's v3 API is known to name its pictures
    `http://assets.fanart.tv/…`, so every fanart.tv preview - fanart.tv leads SOURCE_ORDER - would have been a 400.
    `artists.from_fanarttv` now upgrades exactly that prefix (`fanarttv_https()`, case-insensitive) to `https://`,
    for the candidate's `url` and so its `preview` - one address, so the choice apply checks against the candidates is
    the same URL the picker offered, and apply fetches it over https. No other host's scheme is touched, nor disc
    art's (`fanarttv_cdart`), and fanart.tv's `/preview/` paths aren't used (unverified). The web's Artist images
    loads those pictures over https now too - assumed to work, since the same host serving https is what everything
    else that uses fanart.tv relies on, but not seen here.
- **The cap**: PICTURE_MAX_BYTES, 8 MB - more than the cover relay's 4, because only Commons' preview is a
  600px thumbnail: fanart.tv's and TheAudioDB's `preview` is the picture itself (`artists._candidate`), and fanart.tv
  offers 4K backgrounds (`artist4kbackground`), a few MB each. Under it, no more than a picker should be sent.
- **The deadline**: 7 s, the cover relay's ANSWER_SECONDS: nothing carries on past the ask here, so the deadline is
  what the phone waits, under its 8 s (ios/App/URLSessionTransport.swift `timeoutIntervalForRequest`). A 4K background
  on a slow host may not make it; the phone then shows that candidate as words.

### Decided here (the spec didn't say)

- **https only**, as asked - unlike the cover relay, which allows http on the Archive's hosts. Every hop seen was
  https.
- **One list for the first address and every hop**: the spec's "the hosts the previews are on, plus where they
  redirect"; a phone may send a `thumb.wikimedia.org` address directly, and gets it.
- **No cache, no single flight**: the spec's "nothing kept on disk". The phone's own URL cache (a week) is the cache;
  a picker shows a picture once.
- **A turn's wait inside the deadline**, unlike the cover relay (whose fetch carries on to keep the cover): here a
  picture queued past 7 s would be thrown away anyway.

### Review (before it shipped)

A review of the first cut found no way off the host list - forty tricky addresses and thirty-one redirect Locations
all handled - and five things, each fixed in the same commit: fanart.tv's `http://` addresses (upgraded in
`from_fanarttv`, above); the cap counting decompressed bytes, in this relay and the cover relay's (identity only,
above); the six at once covering only the fetch (PICTURES_PENDING_MAX, and the memory claim corrected, above); the
words (a 410 a 404; a refusal's 502 said for good, not "just now"); and the logins-off position, written down above
and unchanged.

### Verified, and not

- **pytest**: tests/test_artist_picture_relay.py, through start() with no lifespan, the hosts an httpx MockTransport
  shaped as they were seen (above): each source's preview, Commons through its own two redirects (thumb and upload);
  every preview the `from_*` functions make passing `picture_address()`; fanart.tv's `http://` pictures end to end -
  the images preview offering them as https, the relay passing each on, apply honouring that address and fetching it
  over https; forty addresses refused with a 400 and nothing asked; redirects followed within the hosts and refused
  off them (seventeen targets - an undecodable name and a broken address among them - a chain leaving part way, none,
  too many); the cap declared, streamed, at the cap, and a 6 MB picture under the real one; identity asked on every
  hop, eight encodings refused unread (a nested-gzip bomb), `identity` passed on, the bytes counted the bytes sent;
  the deadline over Commons' three hops; 404 and 410, 403 and the other statuses said for good, 429/5xx, unreachable
  and broken off said for now, timeouts; non-images (an SVG, AVIF, an icon, HTML, an untyped answer refused unread
  whatever its bytes); six at once over twenty; a turn's wait as a 504; the pending cap a refusal at once, nothing
  asked, asked once they drain, the count back to 0 after a picture, an outage, a refusal, a 404 and a timeout, and
  the route's 503; nothing kept; the agent, with and without a contact; GuardMedia's headers and no gzip; logins off
  as the implicit admin. tests/test_artists.py: `from_fanarttv` upgrades fanart.tv's `http://` (any case) and
  nothing else, TheAudioDB's left alone. tests/test_coverart_relay.py: the cover relay's identity fix.
  tests/test_logins.py: ROUTES, and a test that signed out is a 401 and without Edit albums a 403 in NEEDS' words,
  each with the host never asked, then let through for a person given Edit albums, a Navidrome admin and
  break-glass. tests/test_media_headers.py names the path. Twenty-four mutations by hand - http allowed, userinfo,
  port and host unchecked, redirect targets unchecked, no deadline, the declared length or the stream unchecked, any
  type read, no turns, the route's type check gone, the client trusting its caller, a 410 as a 502, the route skipping
  the address check; and the review's: gzip asked for and the encoding unchecked (in each relay), no pending cap, the
  count never coming down, refusals said for now, busy as a 502, fanart.tv left on http, every http upgraded - each
  fails a test.
- **Not seen**: deadwax itself has never asked a real host through this route - every answer it has read is the
  MockTransport's. fanart.tv (above), how long each chain takes from James's server, and the phone drawing them
  (slice 5) are unwatched.

## The scan without its tracks (2.1.28)

Phase 8's server change A (notes/ios-specs/phase8-managing.md on `ios`, sections 3.1 and 12): the app's album editor
finds an album's folder from the scan's albums, as the web's does (`albumEdit.ts` `editFolders`), but every field it
reads of an album is album-level, and `/library/albums` carries every track of every album - most of the body even
compacted (notes/performance.md, "Tracks travel compact"), twice a visit. So `GET /deadwax/library/albums` and `POST
/deadwax/library/rescan` take `tracks` (a query parameter, default true). `?tracks=false` sends each album as
`compact_for_wire()` would, less its `tracks` and `track_defaults` (`library.albums_without_tracks()`: the same keys in
the same order, the server-only fields dropped as ever, new dicts so the cache is never trimmed); everything else is
the same answer - the scan, `queue`, `issue_types`, each album's issues, the `X-Scan-*` headers, the snapshot form.
The ETag is of the body, so the two forms never answer each other's If-None-Match. The web never sends it, so nothing
it reads changed; no route was added (tests/test_logins.py ROUTES as it was) and no permission moved (`/albums` a
user's, `/rescan` Look after the library's).

- **Not chosen**: the full scan on the phone (megabytes a visit), and a one-folder route (`edition_count`,
  `split_discs` and `disc_label` are worked out across the whole scan, and Needs a look and Library care read the list
  anyway).
- **Verified**: tests/test_library_cache.py - the lean body equals the full one less the two keys, key for key; its
  own ETag is a 304 and each form's ETag a 200 for the other; the snapshot form stale and from the saved scan; rescan's
  form, and an unchanged library's forced read the same lean answer. **Not seen**: the phone asking it (slice 1).
