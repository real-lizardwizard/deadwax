# The native iPhone app (ios/)

James's request of 2026-10-23: "let's get started on the iOS app". The plan (written the same day,
kept outside the repo) and James's answers to it set what follows; this file is the project's memory
of it. The user guide is docs/ios.md.

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
- **`PlaybackEngine`**: AVAudioEngine, one AVAudioPlayerNode per **lane** (rate x channels) connected
  to the main mixer in that format. About 2 s scheduled ahead in 0.5 s buffers, refilled from each
  buffer's `.dataPlayedBack`. **The next song in the same format is scheduled straight after the last
  buffer on the same node** (sample-exact; nothing trimmed or crossfaded). Another format goes on its
  own lane, started with `play(at:)` the host time the first lane's last sample plays (offline: the
  render's sample count). A song that would begin on a lane still holding songs that play before the
  one scheduled last (44.1 kHz, a short 96 kHz song, 44.1 kHz again) waits, its first buffer parked,
  until that lane has run out - see "After review, again". **The output starts once and keeps running**; a song started from silence is
  scheduled `startLead` ahead (AVAudioSession's outputLatency + ioBufferDuration); a pause longer than
  60 s stops the engine, and the next play rebuilds from the frame left. A lane that runs dry mid-song
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
- **The rate conversion is the main mixer's, inside the app**: each lane is connected to the main
  mixer in its file's format, and the mixer's output runs at the route's rate (48 kHz on the speaker
  and AirPods), so the mixer converts a 44.1 kHz CD or a 96/192 kHz file. Any app must convert for a
  48 kHz output; how well AVAudioMixerNode does is undocumented and can't be set, so
  `theMixersRateConversionMeasured` renders 1 kHz (192/96/44.1 kHz -> 48 kHz) and a 30 kHz tone
  (aliasing) and prints the numbers on ios.yml's macOS job (bounds 60 dB and -40 dB catch only a
  broken conversion). If they fall short of James's fidelity rule, the fix is one AVAudioConverter per
  lane at `.max` quality, kept across buffers so joins stay continuous, with the lane connected at
  the output's rate. (The words used to say iOS converted "after the app"; corrected in review.) `conform` copies a
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

Normalization (gain in the engine, Phase 1, with the one new server route for album loudness),
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
- NOT run anywhere yet: the engine's 12 offline-render tests and the app's device build (ios.yml's macOS
  job, after the push), and everything on the phone.
