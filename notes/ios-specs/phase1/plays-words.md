# Phase 1 spec: Plays, Info and the listener's words (app 0.2)

Scouted 2026-11-10 against `ios` = `main` = 2.1.0 (1199330). Paths are repo-relative. "web" = the app at /player/ as of 2.0.15. Every word in
backticks or quotes is verbatim (straight `'` and `"`, `·` = U+00B7, `…` = U+2026, `→` = U+2192).

## 0. Against 2.1.0: what this area needs, and what has to stay true

- **No server change.** Every route here exists on 2.1.0 and is `"user"` in tests/test_logins.py ROUTES:
  `POST /deadwax/navidrome/scrobble/{song_id}` (:179), `GET /deadwax/navidrome/songs/{song_id}` (:172),
  `GET /deadwax/me` (:195), `GET /deadwax/navidrome/status` (:165), `GET /deadwax/store/album` (:201).
  Info's Normalization words depend on the loudness route planned as 2.1.1 (another area): only its
  `state`/`why`/numbers are read here (section 2.6).
- **Files changed since 2.0.0 (85aa7be..HEAD)** in this area: aboutSound.ts, debugRows.ts, InfoSheet.tsx,
  aboutRows.ts, loudness.ts (2.0.7: "Playing" group became "Sound", in listener words; Debug relabelled);
  errorWords.ts (2.0.4 new; 2.0.6, 2.0.8, 2.0.13 added words); usePlayer.ts (2.0.7: three error strings
  only); api.ts (2.0.4: ApiError carries `path`); access.ts (2.0.4: `seesDetail`); permissions.ts (2.0.5-2.0.8
  words); signIn.ts (2.0.4, 2.0.8). **Unchanged since 2.0.0**: playQueue.ts (the play rule), the scrobble
  route, me.py, users.py. 2.0.15's Home "Recently played" is Navidrome's `getAlbumList2 type=recent`, so the
  phone's plays feed the web's Home too.
- **tests/test_ios_contract.py must be edited with the Swift** (it is Python, so CI catches drift):
  - `test_the_app_names_its_routes_in_the_form_this_test_reads` asserts `len(found) == 7` - raise it to the
    new count of `Endpoint(...)` lines (each must stay ONE line in the exact form
    `Endpoint(method: "...", path: "...", query: [...])`).
  - `test_what_the_app_reads_is_what_it_names` pins `required_fields("Me") == {"user", "admin", "auth"}`:
    every field added to `Me` must be OPTIONAL (`public let x: T?`), or that test (and the sign-in test) fails.
  - Add `time` to `test_what_the_app_sends_is_within_the_servers_bounds` (scrobble's `time` is `ge=0`).
- The phone's POSTs carry no `Origin`/`Referer`, so src/api/same_origin.py lets them through (its docstring:
  "A request with no Origin and no Referer at all ... is let through"). The proxy-refusal cause in
  docs/troubleshooting.md:1601 "Plays don't show up" never applies to the phone.
- Only main takes version numbers: nothing here bumps `src/__init__.py` on `ios`.

---

## 1. Plays

### 1.1 The rule (docs/player.md:2114 "How plays are counted"; code below)

1. **"Now playing"** (`submission=false`, no `time`) is sent when a song ACTUALLY STARTS PLAYING, once per
   listen - not at load, not on a skip while paused.
2. **A play** (`submission=true&time=<listen start, ms>`) is sent once per listen, at the update whose heard
   total first satisfies `countsAsPlayed`: song **longer than 30 s** (`duration > 30`, strictly) and heard
   `>= min(duration / 2, 240)` seconds. Heard = listening, not position.
3. **Seeking adds nothing**: a step across a seek (scrubber, lock screen, restart) counts 0; a step backwards
   counts 0; a step is capped at wall-clock elapsed x rate + 0.5 s slack.
4. **Dated from the start**: `time` = when the listen first began playing (ms since epoch), not when loaded.
5. **A new listen** (heard 0, not started, not submitted) begins at: a song loaded (any song change: next,
   previous to another song, a tap, an auto-advance, a skip after failure, a queue put back); "previous" that
   restarts the song (`position > 3` s, or the first song); play pressed on a song that has ENDED; each time
   round of Repeat All / Repeat One. **Same listen**: pause/resume, waiting for the network, a failure retried
   from where it stopped, any seek.
6. **A queue put back** (resume) starts a new listen at the tap; nothing heard before the app closed carries
   over. Put back at 3:00 of 4:00 and heard to the end = 60 s heard -> not a play (needs 120).
7. **A gapless join** inside one stream: the update spanning the join gives the old song's rest to the OLD song
   (and submits it under the OLD id with the OLD listen's start, if that crosses the rule), then a new listen for
   the new song pre-loaded with what was already heard of it, then "now playing" for the new song. A song passed
   wholly between two updates gets nothing.
8. **Fire and forget**: a report that fails changes nothing on screen (web: `console.warn`). Logins off: plays go
   to `NAVIDROME_USER`; logins on: to the signed-in person's own Navidrome account; break-glass `deadwax`'s go to
   `NAVIDROME_USER` (troubleshooting.md:1601).

### 1.2 Web code (pure rules: ui/src/lib/playQueue.ts, unchanged since 2.0.0)

| what | where | exact |
| --- | --- | --- |
| `RESTART_AFTER_SECONDS` | playQueue.ts:47 | `3` (Phase 0 has `PlayQueue.restartAfterSeconds`) |
| `previousAction` | :86-89 | `position > 3 \|\| index <= 0` -> restart, else go to index-1 |
| `countsAsPlayed(listened, duration)` | :97-100 | `if (!(duration > 30)) return false; return listened >= Math.min(duration / 2, 240)` |
| `LISTEN_SLACK_SECONDS` | :107 | `0.5` |
| `listenedStep({previous, now, elapsed, rate, seeked})` | :134-140 | `step = now - previous; if (seeked \|\| !(step > 0)) return 0; pace = rate > 0 ? rate : 1; allowed = max(0, elapsed) * pace + 0.5; return min(step, allowed)` |
| `Listen` | :148-157 | `{heard: seconds, startedAt: ms since epoch (0 = not yet), submitted: bool}` |
| `NEW_LISTEN` | :159 | `{heard: 0, startedAt: 0, submitted: false}` |
| `listenStarted(listen, now)` | :167-170 | startedAt set -> `{listen, nowPlaying: false}`; else `{listen with startedAt=now, nowPlaying: true}` |
| `listenHeard(listen, seconds, duration)` | :176-180 | `heard += seconds; submit = !submitted && countsAsPlayed(heard, duration); submitted \|\|= submit` |
| `splitAcrossJoin({previous, oldLength, now, elapsed, rate, seeked})` | streamPlan.ts:488-499 | seeked -> `{0,0}`; `allowed` as above; `before = max(0, oldLength - previous)`, `after = max(0, now)`; if `before + after > allowed`: `after = max(0, allowed - before)`, `before = min(before, allowed)` |
| `scrobble(id, submission, time?)` | player/api.ts:614-619 | POST `/navidrome/scrobble/{encodeURIComponent(id)}?submission=${submission}` + (`time` truthy ? `&time=${time}` : ''), no body; `.catch` -> console.warn only |

Where the engine (ui/src/player/usePlayer.ts, an engine file: read, never edit) drives them:
- `newListen()` :545-551 - `listen = NEW_LISTEN; lastPosition = 0; lastAt = now; seeked = false`. Called by
  `load()` :639, `moveInStream()` :749, `play()` on an ended element :888-892, `restart()` :985-993, `handOver()`
  (:1318; newListen at :1347), `restoreQueue()` :1680 (:1697).
- `beginListen()` :583-588 - `listenStarted(listen, Date.now())`; if `nowPlaying`, `scrobble(id, false)`. Called
  by the element's `playing` event (:1980/:1995), by `restart()` and `moveInStream()` when already playing (no
  `playing` event follows), and by `crossInto()` :1817.
- `onTimeUpdate()` :1716-1763 - `step = listenedStep({previous: lastPosition, now: position, elapsed: (at -
  lastAt)/1000, rate: playbackRate, seeked})`; then `lastPosition/lastAt` updated, `seeked = false`;
  `listenHeard(listen, step, songLength())`; on `submit`, `scrobble(id, true, listen.startedAt)`.
- `'seeking'` event :2033 sets `seeked = true` (every seek, whoever asked).
- `crossInto()` :1771-1825 - `split = splitAcrossJoin(...)`; old listen `listenHeard(listen, split.before,
  old.length)` and submit under the OLD id with `listen.startedAt`; then `listen = listenHeard(NEW_LISTEN,
  split.after, song.length).listen` (its `submit` is DISCARDED - harmless: `after` is at most ~1 s), `lastPosition
  = now`, then `beginListen()`.
- `songLength()` :449-456 - the stream's own sample length, else the element's finite `duration > 0`, else the
  queue's Navidrome `duration`, else 0 (0 never counts).
- A failure retried (`onFailure` :1872, `retry`) keeps the listen; `resumeAt` reseeks (the seek counts 0).

### 1.3 Swift: DeadwaxCore (pure; Linux-tested)

```swift
public enum PlayRule {
    public static let longerThan: Double = 30      // countsAsPlayed: duration must be > this
    public static let atMost: Double = 240         // min(duration / 2, atMost)
    public static let slack: Double = 0.5          // LISTEN_SLACK_SECONDS
    public static func countsAsPlayed(listened: Double, duration: Double) -> Bool   // NaN duration -> false
    public static func listenedStep(previous: Double, now: Double, elapsed: Double, rate: Double = 1, seeked: Bool) -> Double
    public static func splitAcrossJoin(previous: Double, oldLength: Double, now: Double, elapsed: Double,
                                       rate: Double = 1, seeked: Bool) -> (before: Double, after: Double)
}
public struct Listen: Equatable, Sendable {
    public var heard: Double          // seconds
    public var startedAt: Int64?      // ms since epoch; nil = not begun (web's 0)
    public var submitted: Bool
    public static let new = Listen(heard: 0, startedAt: nil, submitted: false)
    public func started(atMs: Int64) -> (listen: Listen, nowPlaying: Bool)
    public func hearing(_ seconds: Double, of duration: Double) -> (listen: Listen, submit: Bool)
}
public enum PlayReport: Equatable, Sendable {
    case nowPlaying(songID: String)
    case played(songID: String, atMs: Int64?)    // atMs nil -> no `time` sent (web omits 0)
}
/// The engine-independent bookkeeping of usePlayer's listen state, so it is tested on Linux.
public struct ListenTracker: Sendable {
    // state: songID, listen, lastPosition (s), lastAt (monotonic s), seeked
    public mutating func newListen(songID: String, at monotonic: Double, from position: Double = 0)
    public mutating func seeked()                                             // any seek: next step counts 0
    public mutating func began(wallMs: Int64) -> PlayReport?                  // .nowPlaying once per listen
    public mutating func tick(position: Double, monotonic: Double, duration: Double) -> PlayReport?  // .played once
    public mutating func join(into songID: String, oldLength: Double, newPosition: Double, monotonic: Double,
                              newDuration: Double, wallMs: Int64) -> [PlayReport]  // [.played(old)?, .nowPlaying(new)]
}
```

Phone decisions (the engine has an exact position, so the inputs differ from the web's; the rule does not):
- **rate** is always 1 (no speed control in the native app).
- **position**: the engine's `heard()` position of the CURRENT entry (LaneTimeline), in seconds of the song's
  own frames. **duration**: the decoded length (frames / file rate: STREAMINFO total samples or
  `AVAudioFile.length`) once known, else Navidrome's `duration`, else 0 - as `songLength()`.
- **monotonic clock**: `ContinuousClock` (counts while the phone sleeps; `DispatchTime`/`mach_absolute_time`
  don't), passed in as seconds so tests drive it.
- **ticks**: the app's 0.5 s ticker AND each `.dataRendered` completion may call `tick` (locked, the ticker may be
  sparse; the cap uses elapsed, so sparse ticks still count in full - playqueue.sim "updates only every 5s - a
  locked phone").
- **"began"** = the engine reports the entry `.playing` (its first sample scheduled onto a running output); for a
  join, the tick that first sees the new index. `wallMs` = `Int64((Date().timeIntervalSince1970 * 1000)
  .rounded(.down))` (an integer: the server's `time: int` rejects a fraction with 422).
- **A start that isn't 0** (a queue put back at 1:35, a failure retried from its frame): `newListen(from:
  position)` (or `seeked()` right after), so the jump from 0 is never counted. Retry = same listen: do NOT call
  `newListen`, call `seeked()`.
- **Pause**: Phase 1's pause stops the engine output at once (notes/ios.md "The pause the lock screen didn't
  see"); resume rebuilds from the frame left. Nothing special: the next step is small, `started` is already
  set, so no second "now playing".
- **Repeat**: each time round is a new queue entry (upNext's copies) -> `newListen` -> new now-playing and play.
- **Stop / sign-out / a new queue**: the current listen is dropped as it is (nothing sent).

### 1.4 What the app sends

```swift
public static let scrobble = Endpoint(method: "POST", path: "/deadwax/navidrome/scrobble/{song_id}", query: ["submission", "time"])
```

- Now playing: `POST /deadwax/navidrome/scrobble/<id>?submission=false`. Play: `...?submission=true&time=<ms>`.
  `submission` is the literal `true`/`false`. No body, no Content-Type; the session cookie as for every request.
- Server (src/routes/navidrome.py:684-698): `submission: bool = False`, `time: int | None = Query(None, ge=0)`;
  calls Navidrome `scrobble` as the asker (`client_for`); `time=None` is dropped from the Subsonic call
  (navidrome_endpoint.py:385-390 `_params` drops `None`). Answers `200 {"ok": true}` (don't decode it).
  Failures: 401 (session ended - detail one of auth.py's words; treat like any 401: signed out), 404 (Navidrome
  code 70), 502/503 (Navidrome down/unset), 422 (a bad `time`).
- Phase 1 sends at once and drops a failure (web parity; log it). Every report goes through ONE
  `PlayReporter` so Phase 2 can add `play_pending` (plan section 4: kept with their time, sent oldest first).
- Navidrome lists the phone as the same player `deadwax` (CLIENT_NAME); Last.fm/ListenBrainz forwarding needs
  scrobbling on for that player on Navidrome's Players page (troubleshooting.md:1601).

### 1.5 Tests to mirror (Swift Testing, DeadwaxCoreTests)

ui/test/playqueue.sim.cjs:94-200 (each a `check` name):
- `half of a 200s song counts` (100,200)->true; `just short of half does not` (99,200)->false; `four minutes of a
  long song is enough` (240,1200)->true; `a 30s song never counts` (30,30)->false; `an unknown length never
  counts` (500,0)->false.
- listenedStep: `a quarter-second tick is listening` (10->10.25, e .25)=0.25; `a step a moment ahead of the clock
  still counts in full` (20->20.5, e .25)=0.5; `a seek forward is not listening` (10->150, seeked)=0; `a seek back`
  (150->10)=0; `a jump the seek flag missed counts no more than the time that passed` (10->150, e .25)=0.75; `a
  clock that stood still allows only the slack` (10->12, e 0)=0.5; `updates only every 5s` (40->45, e 5)=5; rate
  cases (20->24 e1 r4)=4, (r1)=1.5, (r0)=1.5; playspeed.sim:258-260 [(10->18,e4,r2)=8, (10->11,e4,r.25)=1],
  [(10->100,e4,r.25)=1.5, (r2)=8.5].
- Whole songs (`play()` helper, 0.25 s ticks): heard through = 200; every 5 s = a play; seek 50->150 = 100 heard;
  seek at 0.5 to 199 then heard out -> not a play.
- Listens: started at 11:00 though loaded at 9:00 -> `startedAt` = 11:00 and `nowPlaying` true; started again ->
  same startedAt, `nowPlaying` false; heard through -> submitted once at heard=100 (`[100]`); 60+60 across a pause
  -> `[100]`; a new listen of the same song -> `[100]` again; NEW is `[0, nil, false]`; 99 heard -> not submitted;
  a 30 s song -> `[]`.
- splitAcrossJoin, ui/test/stream.sim.cjs:478-493 (in microseconds): defaults (198.7, 200, 0.3, 1.6) -> {1.3, 0.3};
  seeked -> {0,0}; (199, now 2, e1) -> {1, 0.5}; (190, now 5, e1) -> {1.5, 0}; (199, now 3, e1, r2) -> {1, 1.5};
  r0 like r1 -> {1, 0.5}; e -3 -> {0.5, 0}; previous 200.2 (now .4, e .5) -> {0, 0.4}; now -0.1 -> {1.3, 0}.
- Behaviour, from ui/test/player.sim.cjs (port as ListenTracker traces): `"now playing" for song 2 when it began`
  (:3307); `songs this short (30 s or less) never count as plays` (:3313); `...each a play, under its own id`
  ['1','9','2','3'] across joins (:4794); Repeat All x3 of 35 s songs -> 10 plays in order (:5022); Repeat One ->
  3 now-playing, 3 plays (:5053); a put-back queue: `nothing scrobbled before it plays`, then `['3:now']` (:6089,
  :6093).
- pytest (server, already green): tests/test_navidrome.py:1544 `test_a_play_is_counted_as_a_submission` (id,
  "true", "1727000000000" reach Navidrome); tests/test_player_as_you.py:1028
  `test_plays_and_now_playing_are_each_users_own`.

---

## 2. Info

### 2.1 Shape (ui/src/app/InfoSheet.tsx, ui/src/lib/debugRows.ts:584-606)

- Opened from Now Playing's •••. Title `Info`, button `Done`.
- Tabs (`INFO_TABS` :584): `About`, `Debug`. `infoTabs(admin)` :594 - an admin gets both (a segmented control);
  anyone else ONLY About and **no tab strip**. `shownTab(tab, admin)` :599 - Debug chosen, admin gone -> About
  (and the choice is forgotten: the role coming back opens on About). `admin` = /me's (section 4).
- About's sections, in order, with these headings: `The song`, `The album`, `The artist`, `Sound`, then (admin
  only) `On the server` with one row `Folder`. A section with nothing is left out.
- Rows are worked out only while Info is open; the list scrolls to its top as Info opens and as the tab changes.

### 2.2 What About is drawn from

1. The queue entry (QueueTrack: id, title, artist, album, albumId?, coverArt?, duration, contentType?, suffix?,
   sampleRate, bitDepth, channels; + `level` album/track/nil).
2. The album answer the queue was played from (`GET /navidrome/albums/{id}`), kept for the last 8 albums played
   (`PLAYED_KEPT = 8`, lib/playedAlbums.ts:26; 64 for a multi-album queue). Nil for a queue put back at launch.
   Read (all optional, `AboutAlbumFields` aboutRows.ts:64): `id, name, artist, year (Int), coverArt, songCount,
   song[], discTitles[{disc (Int|String), title}], artistId, recordLabels[{name}]`, and `partial` (deadwax's
   playlist stub - Phase 4).
3. `details`, asked as Info opens and again for another song while open (app/useInfoDetails.ts:41-131):
   - **`GET /deadwax/navidrome/songs/{song_id}`** (src/routes/navidrome.py:434-446): Subsonic `getSong`, the `song`
     object passed back AS IS (`{}` when Navidrome sent none). 404 when Navidrome says code 70; 502 for its other
     errors (logins off, a refused login names `NAVIDROME_USER`: plumbing); 401 with logins on when the login
     ended. Path id 1..256 chars (`ID_MAX = 256`; 257 -> 422, Navidrome not asked). Fields About reads
     (`AboutSongFields` aboutRows.ts:47, all optional): `id: String, artist: String, artistId: String, track: Int,
     discNumber: Int, duration: Double, suffix: String, playCount: Int` (Navidrome LEAVES IT OUT until played),
     `displayComposer: String`, `contributors: [{role: String, artist: {name: String}}]`. Fixture:
     tests/test_navidrome_artists.py:64 `SONG = {"id": "so-1", "title": "Glory Box", "albumId": "al-1",
     "artistId": "ar-1", "playCount": 12, "displayComposer": "Geoff Barrow, Beth Gibbons, Adrian Utley"}`.
   - `GET /deadwax/store/album?navidrome_id=<albumId>` (the id bridge, also Phase 1's Add): `present[]` rows
     `{path, edition, year (String), formats [String]}` read here.
   - getArtist + MusicBrainz facts: Phase 4 (see Open questions).
   - Rules: only the newest answer draws (latestOnly); the song's and the store's answers are HELD until both
     have answered or `INFO_SETTLE_MS = 500` ms passed (useInfoDetails.ts:16), so a card doesn't grow under a
     finger; a failure leaves its lines out, silently.

### 2.3 The song card (aboutRows.ts:210-269; helpers lib/format.ts, lib/discTitles.ts)

Let `songs = album?.song ?? []`, `song = songs.first { $0.id == track.id }`, `all = album?.partial ? [] :
songs`, `fresh = details.song` when its `id == track.id`.
- Title: `track.title`. Artist line: `track.artist` (when non-empty).
- Line 1 = `[trackOf(song, all) if song, length, played].filter(nonEmpty).joined(" · ")`:
  - `length = trackTime(song?.duration ?? track.duration)` - `trackTime` format.ts:34: `''` for 0/nil; `whole =
    round(seconds)` (half up); `"\(whole/60):\(two-digit whole%60)"` -> `5:08`, `1:01`.
  - `trackOf` aboutRows.ts:187: `number = whole(song.track)` (a positive integer, else 0 -> `''`); `onDisc` =
    songs with the same disc (`discNumber || 1`); `of = number <= onDisc ? onDisc : number <= songs.count ?
    songs.count : 0`; `"Track \(n) of \(of)"`, or `"Track \(n)"` when `of == 0`.
  - `played = playedLine(fresh ? fresh.playCount : song?.playCount)` :153: `''` unless a positive integer; 1 ->
    `played once`; n -> `played \(n) times`.
- Line 2 (only when `song` and the album is in hand and not `partial`): `discLine` :200 = the album page's
  heading over the first song of the song's disc: headings show when the album has >1 disc OR any disc has a
  title; `Disc \(n) · \(title)` or `Disc \(n)` (discTitles.ts:27-60: titles trimmed, blank and non-integer/<=0
  discs ignored, first one per disc wins, a song with no disc number is disc 1).
- `Written by \(writers)` when `writtenBy(fresh ?? song)` :142 is non-empty: `displayComposer` trimmed, else the
  `contributors` whose `role` lowercased == `composer`, names trimmed, empties dropped, de-duplicated in order,
  joined `", "`.

### 2.4 The album card

- Present when `title = album?.name || track.album` is non-empty.
- Goes to the album (`id = track.albumId ?? album?.id`), drawn as a link only with an id. Cover: `album?.coverArt
  ?? track.coverArt` (the album's own over the song's), drawn at 120.
- Line = `[year, labels, format, count].filter(nonEmpty).joined(" · ")`: `year` only a positive integer;
  `labelLine` :159 = `recordLabels` names trimmed, empties dropped, de-duplicated, joined `" / "`; `format =
  sharedFormat(all)` format.ts:44 = the ONE uppercased `suffix` every song has (a song without one makes it nil;
  empty list nil); `count = all.count` or else `whole(songCount)`, as `1 song` / `\(n) songs`.
- `This pressing: …` (from `present`, idBridge.ts:62-86) only when `pressingAdds(present, {year, format})`: the
  first row's edition non-blank, or its 4-digit year != the album line's year, or the formats (de-duplicated,
  uppercased, joined `/`) != the line's format. Line: `This pressing: ` + `[edition trimmed, 4-digit year,
  formats]` non-empty joined `" · "`.

### 2.5 The artist card (Phase 1 subset)

- `name = song?.artist || track.artist || album?.artist || ''`; no card when empty.
- Note: `The album is by \(album.artist)` when the album artist is non-empty and not `sameName` (trimmed,
  lowercased) with `name`.
- Phase 1: no link, no facts, no count (they need /artists/{id}, MusicBrainz and /library/owned - Phase 4).
  Rules kept for then: `cardArtist` :174, useInfoDetails.ts:82-123.

### 2.6 Sound (lib/aboutSound.ts, 2.0.7)

`SOUND_TITLE = 'Sound'` :28. Three rows (`soundRows` :120), labels and order exactly, all in the text face:

| label | value |
| --- | --- |
| `Format` | `formatWords(track)` or `Not known` (`NOT_KNOWN`, debugRows.ts:58) |
| `Gapless` | `On` or `Off` (never "On, in one stream" here) - the phone is always gapless: `On` |
| `Normalization` | `aboutLevel(track, format, report)` below |

`formatWords` debugRows.ts:149: `[kind, bits>0 ? "\(bits)-bit", rate>0 ? khz(rate), channels>0 ?
channelWords]` non-empty joined `", "`. `kindOf` :133: `suffix.uppercased()` if any, else `contentType` before `;`,
trimmed, lowercased, minus `audio/` and a leading `x-`, uppercased (`audio/x-flac` -> `FLAC`); not `audio/*` -> `''`.
`khz` :120 = JS `${rate / 1000} kHz` - the shortest decimal, no trailing `.0`: 44100 -> `44.1 kHz`, 192000 ->
`192 kHz`, 88200 -> `88.2 kHz`, **22050 -> `22.05 kHz`** (Phase 0's `RateWords.kHz` rounds to 0.1 and would
say `22.1`: don't reuse it). `channelWords`: 1 `mono`, 2 `stereo`, n `\(n) channels`.

**`aboutLevel(track, format, report)`** :84-109, in order (`report` is used only when `report.level ==
track.level`, else treated as nil - soundRows :122):
1. `track.level == nil` -> `Off`
2. not `levels(track, format)` (loudness.ts:68: a level, `format == raw`, and `isFlac` - streamWrap.ts:54:
   suffix `flac`, or type before `;` `audio/flac`/`audio/x-flac`) -> FLAC ? `OFF_WORDS.transcoded` :
   `OFF_WORDS.kind`
3. `report == nil` -> `Checking…` (`LEVEL_CHECKING` :31)
4. `state == not_levelled` -> `offWords(why)`
5. `measuring` -> album: `Measuring the album… (\(measured_songs) of \(songs) \(songs == 1 ? "song" : "songs"))`;
   track: `Measuring the song…`
6. `plain` -> `Not this time - the \(whose) was still being measured` (`whose` = `album` / `song`)
7. `unmeasured`, or `gain_db == nil` -> `Not this time - the \(whose) hasn't been measured yet`
8. `head = "Album volume matching"` / `"Song volume matching"`;
   `loudness_lufs == nil` -> `\(head) - nothing to adjust, the \(whose) is silent`
9. `held && (wanted_db ?? 0) > 0 && toFixed(|gain_db|, 1) == "0.0"` -> `\(head) - kept as it is, it can't go
   louder without distorting`
10. `\(head), \(volumeChange(gain_db))` + (`held` ? ` - as loud as it can go without distorting` : ``)

`volumeChange(g)` :72: `size = toFixed(|g|, 1)`; `"0.0"` -> `no change needed`; else `\(size) dB quieter` (g<0)
/ `\(size) dB louder`.

`OFF_WORDS` :37 (each starts `Off for this song - `): `server` `Off for this song - this server can't adjust
volume`; `kind` `Off for this song - only FLAC songs are adjusted`; `transcoded` `Off for this song - this
device can't play FLAC, so it's sent as MP3`; `large` `Off for this song - its file is too large`; `file` `Off for
this song - its file can't be measured`. `offWords(why)` :65: first match of `ABOUT_REASONS` :58 -
`/without numpy|player's cache can't be used/` -> server, `/^it isn't a FLAC file/` -> kind, `/MiB a song is held
in memory/` -> large; anything else (nil included) -> file. Server reasons (src/levels.py:107-110): `NOT_FLAC = "it
isn't a FLAC file"`, `UNREADABLE = "its file can't be read as FLAC by deadwax (20- or 32-bit)"`, `NO_CACHE = "the
player's cache can't be used on this server"`, `NO_LIBRARIES = "deadwax is running without numpy and soundfile"`.

**JS `toFixed` is not printf.** At an exact binary tie JS rounds UP (away from zero for the non-negative values
used here); `String(format: "%.1f")` rounds to EVEN. Gains are hundredths, so `x.25`/`x.75` happen. Port a
`jsToFixed(_ x: Double, _ digits: Int)`: printf's result, except when `x * 10^digits` is exactly representable
with fraction exactly 0.5, round up. Vectors (node, 2026-11-10): toFixed(1): 0.25->`0.3`, 3.25->`3.3`,
0.75->`0.8`, 3.75->`3.8`, 2.35->`2.4`, 0.15->`0.1`, 1.45->`1.4`, 0.05->`0.1`, 0.04->`0.0`, 12.65->`12.7`
(printf gives 0.2 and 3.2 for the first two). `volumeChange(-3.25)` = `3.3 dB quieter`; aboutLevel with
gain -3.25 = `Album volume matching, 3.3 dB quieter`.

**The phone's report** (a `LevelReport` with LevelAnswer's fields, loudness.ts:91: `level, state (measured |
measuring | unmeasured | plain | not_levelled), gain_db?, wanted_db?, loudness_lufs?, peak_db?, held, songs,
measured_songs, why?`), so aboutLevel/describeLevel port verbatim:
- For the song PLAYING: what the engine APPLIED, fixed when its first buffer was made (gain never changes
  mid-song): applied a gain -> `measured` with the phone's own `gain_for` values (reserve 0); applied none because
  the album/song wasn't measured at that moment -> `plain` if the loudness route said `measuring`, else
  `unmeasured`; refused by the route -> `not_levelled` with the route's `why` as sent.
- For a song not begun yet (a queue put back, paused): the loudness route's current answer (so `Measuring the
  album… (3 of 10 songs)` can show), re-asked every 5 s while `measuring` (`LEVEL_ASK_AGAIN_MS = 5000`,
  useInfoDetails.ts:134).
- Nil until either exists -> `Checking…`. The phone never transcodes a FLAC, so `transcoded` can't arise.

### 2.7 On the server (admin only)

`seesFolders(admin)` :137 = `admin`. Heading `On the server`, row `Folder`, value `folderLine(present)`
(idBridge.ts:88): the rows' non-empty `path`s joined with `\n` (one per line for a set kept per disc), selectable,
in the data (mono) face, outside any link, last.

### 2.8 Debug (admin only)

Web sections (debugRows.ts:604-614): `The file` / `Sent to this device` / `Last song change and seek` / `The
turntable` / `Fields from Navidrome`. Port to the phone:

1. **`The file`** - `Format`: `formatWords` or `Navidrome didn't say` (`formatRow` :159).
2. **`Sent to this device`**:
   - `Sent as` (sentAsRow :191, no MP4 on the phone): raw -> `\(KIND), as the file is` (`The file as it is` with
     no kind); mp3 -> `MP3, transcoded by Navidrome`; unknown -> `Not known`. (Phase 2 adds the downloaded copy.)
   - `Normalization` - `describeLevel(track, format, report)` loudness.ts:130-155, same report and level rule:
     `Off`; not levels -> `Not levelled - \(KIND) songs play as they are` (suffix uppercased) or `Not levelled -
     only FLAC songs are levelled` (no suffix); nil -> `Asked for; deadwax hasn't said yet`; not_levelled ->
     `Not levelled - \(why ?? "deadwax won't level it")` (raw `why`: admins only); measuring -> `Measuring its
     album… (\(m) of \(n) song|songs)` / `Measuring the song…`; plain -> `Played as it is this time - its album was
     still being measured` / `- its loudness was still being measured`; unmeasured or no gain -> `Not measured yet -
     it played as it is this time`; measured: `head = "Album, \(signedDb(gain))"` / `"Song, …"`; held && wanted !=
     nil -> `\(head) · held there by its peak (it wanted \(signedDb(wanted) minus " dB"))`; lufs nil -> `\(head) · the
     \(whose) is silent`; else `\(head) · the \(whose) at \(lufs(L))`. `signedDb(v)` :105 = `toFixed(|v|,2)`, sign
     `-` only when v<0 and the digits aren't `0.00`, else `+`, then ` dB` (-0.004 -> `+0.00 dB`). `lufs(v)` :111 =
     `toFixed(|v|,1)`, `-` only when v<0 and not `0.0`, then ` LUFS` (-0.04 -> `0.0 LUFS`; -10.25 -> `-10.3 LUFS`).
   - `Gapless`: `On` (proposal: the phone has no switch).
   - The phone's own rows (the plan's "lanes, output rate and latency, buffers, last start" - NEW words, proposed):
     `Output` `48 kHz · AirPods Pro · 21 ms latency`; `Conversion` Phase 0's readout (`24-bit 192 kHz FLAC file → 48
     kHz output`); `Lane` `44.1 kHz stereo, converted to 48 kHz` / `48 kHz stereo, no conversion`; `Buffered
     ahead` `1.8 s`; `Source` `Streaming, 4.2 of 31.0 MB` / `From the stream cache`; `Last start` `0.31 s from the
     tap to sound`.
3. **`Fields from Navidrome`** (debugRows.ts:505-571), on the song's and album's RAW JSON (keep the album answer's
   bytes/`JSONValue`, not only the decoded model): `Song fields`, `Only on other songs`, `Album fields`.
   `fieldNames` = keys sorted by code unit; `isEmptyValue`: null, `""`, `0`, `[]`, `{}` are empty, **`false` is a
   value** (decode JSON into an enum that keeps Bool apart from numbers - JSONSerialization's NSNumber makes
   `false == 0`); `sentRow`: no answer or no keys -> `Not known`; else filled joined `", "` (or `Nothing with a
   value`), mono, note `Empty: a, b` (mono) when any empty. `Only on other songs`: no song or no `song` list ->
   `Not known`; the names filled on another song (not the same object, not the same `id`) and not filled on this
   one, sorted, joined `", "` (mono), or `Nothing this song lacks`.
- Left out (web-only): Resampled, Why sent this way, Speed, Last song change/seek, the turntable.

### 2.9 Tests to mirror

- ui/test/info.sim.cjs:292-357 (Sound) - every expectation verbatim: `Off`/`Checking…`/other-level `Checking…`;
  measured `Album volume matching, 3.6 dB quieter`, `Song volume matching, 1.2 dB louder`, `Song volume matching,
  no change needed` (0.04); held `Song volume matching, 1.2 dB louder - as loud as it can go without distorting`;
  silent `Album volume matching - nothing to adjust, the album is silent`; held at -0.01 wanting 4 -> `Album volume
  matching - kept as it is, it can't go louder without distorting` (and the track version), unheld -0.01 -> `Album
  volume matching, no change needed`; measuring/plain/unmeasured six lines; MP3 and transcoded; every server
  reason -> its OFF line (server/kind/large/file incl. `it has 6 channels - only mono and stereo are levelled`, `its
  STREAMINFO doesn't say how long it is`, `the file is empty`, `its first bytes aren't a FLAC file's`, `Error
  opening: unknown format`, nil); About's words never match `/\d\.\d\d|LUFS|levelled|numpy|soundfile|MiB|
  STREAMINFO|Navidrome|hasn't said/`; rows hires `FLAC, 24-bit, 192 kHz, stereo`/`On`/…, unknown `Not known`/`Off`/
  `Off`; `volumeChange` (-7.42, 2.35, -0.04, 0) -> `7.4 dB quieter`, `2.4 dB louder`, `no change needed` x2.
- info.sim:243-290 (song and album cards): `Track 3 of 6 · 5:08` + `Disc 2 · Unreleased Tracks`; `Disc 1` on the
  untitled disc of a titled set; one-disc no line; titled one-disc `Disc 1 · Live`; straight-through numbering
  `Track 8 of 11 · 5:08`; `Track 14 · 5:00`; `1:01`; `[]`; album not in hand `['5:08']`; album line `1975 · FLAC ·
  11 songs`, no year / year 0 / mixed formats / `1 song` / `10 songs` from songCount; cover precedence; no id; no
  card; artist note `The album is by Various Artists`, case-insensitive.
- info.sim:360-423 (details): `played 12 times` + writers; `playedLine(1,2,0,nil)`; `labelLine`; nothing sent ->
  nothing drawn; This pressing only when it adds.
- ui/test/debug.sim.cjs:304-312 (Format) and :450-487 (Normalization: `Album, -7.42 dB · the album at -10.6 LUFS`,
  `Song, -3.10 dB · the song at -14.9 LUFS`, `Song, +1.20 dB · held there by its peak (it wanted +2.35)`, `Song,
  +0.00 dB · the song is silent`, `Measuring its album… (7 of 12 songs)`, `Not measured yet - it played as it is
  this time`, the two `Played as it is this time` lines, `Not levelled - MP3 songs play as they are`, `…OPUS…`,
  `…FLAC…` for mp3, the UNREADABLE line).
- Extra vectors (compiled TS): `Measuring the album… (0 of 1 song)`; formatWords 88200/24 `FLAC, 24-bit, 88.2 kHz,
  stereo`, 22050/6ch `FLAC, 16-bit, 22.05 kHz, 6 channels`, suffix m4a `M4A, 16-bit, 44.1 kHz, stereo`;
  `playedLine(2.5)` `''`; writtenBy of `Composer`/`composer` duplicates -> `Geoff Barrow`.

---

## 3. The listener's words (ui/src/lib/errorWords.ts, 2.0.4+)

### 3.1 Sentences (verbatim)

| constant | words | line |
| --- | --- | --- |
| `TELL` | `Tell whoever runs deadwax.` | :48 |
| KEEPS (advice tail) | `if it keeps happening, tell whoever runs deadwax.` | :51 |
| KEEPS_TOLD | `If it keeps happening, tell whoever runs deadwax.` | :52 |
| `OFFLINE` | `Can't connect to deadwax.` | :54 |
| `OFFLINE_ADVICE` | `Check your connection, then try again.` | :55 |
| `OFFLINE_RETRY` | `Check your connection.` (beside the page's own Try again) | :57 |
| `TIMEOUT` | `That took too long.` | :58 |
| `SIGNED_OUT` | `Your sign-in has ended - sign in again.` | :59 |
| `NOT_ALLOWED` | `You don't have permission for that.` | :60 |
| `GONE` | `It isn't there any more.` | :61 |
| `OTHER` | `Something went wrong.` | :62 |
| `DOWN.music` / `.downloads` / `.deadwax` | `Can't reach the music server right now.` / `Downloads aren't working right now.` / `deadwax can't do that right now.` | :65 |
| `ALBUM_GONE` (a `gone`) | `This album isn't here any more - it may have been moved or deleted.` | player/AlbumPage.tsx:122 |
| `COULDNT_REFRESH` | `Couldn't update this list - showing it as it was.` | app/LibrarySection.tsx:29 |

### 3.2 The class (`errorKind` :134-157), first match wins

An API answer (status, `detail`?, `why`?, `kind`?, `path`): 1. `kind` set && status != 401 && `fit(detail)` ->
refused; 2. 401/403 -> not-allowed; 3. 404 -> not-found; 4. 408/504 -> timeout; 5. `why` && `detail` -> refused;
6. 502/503 && `fit(detail)` -> refused; 7. 502/503 -> unreachable; 8. 400-499 && `fit(detail)` -> refused; 9.
other. No answer: offline (web: fetch's TypeError) ; a timeout -> timeout; anything else -> other.
`fit(t)` :253 = non-empty, trimmed != `Not Found`, and not `plumbing`. `serviceOf` :126 by path under `/deadwax`:
`/navidrome…` -> music, `/download…` or `/monitor_slskd…` -> downloads, else deadwax.

`plumbing` :97-114 - any match: `/https?:\/\//i`; `/\b[A-Z][A-Z0-9]*_[A-Z0-9_]+\b/`; `/\b[A-Za-z]*(Error|
Exception)\b/`; `/Errno|Traceback|HTTPConnectionPool|Max retries|\bhost=|\bport=/`; `/\b(GET|POST|PUT|DELETE|
PATCH) \//`; `/(^|[\s('"])\/[\w.-]+\/[\w./-]*/`; `/\bslskd\b|\bSubsonic\b/i`; `/\banswered [1-5]\d\d\b|\bHTTP
[1-5]\d\d\b/`; `/\b(Navidrome|MusicBrainz) said\b/`. In NSRegularExpression write `\w` as `[A-Za-z0-9_]` (ICU's
is Unicode); the two `/i` patterns case-insensitive, the rest not; `^` = start of string.

### 3.3 The words (`errorWords(error, {admin, service, gone, failed, retry})` :189-232)

| kind | text | advice (retry=false) | advice (retry=true) |
| --- | --- | --- | --- |
| offline | `OFFLINE` | `OFFLINE_ADVICE` | `OFFLINE_RETRY` |
| timeout | `TIMEOUT` | `Try again.` | `` |
| unreachable | `failed ?? DOWN[service]` | admin `Try again in a minute.`; else `Try again in a minute - ` + KEEPS | admin ``; else KEEPS_TOLD |
| not-found | `gone ?? (fit(detail) ? detail : GONE)` | `` | `` |
| not-allowed | 401 `SIGNED_OUT`; else `fit(detail) ? detail : NOT_ALLOWED` | `` | `` |
| refused | `detail ?? ''` (as written, never re-cased) | `` if admin or status < 500; else `why` ? (503 ? `TELL` : ``) : KEEPS_TOLD | same |
| other | `failed ?? OTHER` | admin `Try again.`; else `Try again - ` + KEEPS | admin ``; else KEEPS_TOLD |

`detail` (the smaller line) = admin && raw non-empty && raw != text ? raw : nil, `raw` = (`why` || `detail` ||
message).trimmed - message for an answer is `"\(METHOD) \(path) failed"`, for no answer the system's words.
`said(words)` :236: advice empty -> text; text empty -> advice; else text (+ `.` unless it ends `.!?…`) + ` ` +
advice. `asSentence` :159: trim; first letter up unless it starts `deadwax`/`slskd` (`\b`); `.` added unless it
ends `.!?…`. `safeWords(text, fallback)` :258. `noticeWords(lead, error)` :246 = `lead said` + ` (detail)` for
whoever runs deadwax.

**`seesDetail`** (app/access.ts:69) = `admin || permissions contains "server"` - the `admin` option above: they
see the raw words and are never told to tell themselves; everyone else gets the tell.

### 3.4 Swift mapping (DeadwaxCore)

- Today `DeadwaxError.refused(status:detail:)` holds `detailWords`, which INVENTS `deadwax answered \(status) and
  said nothing more.` when there's no detail, and drops `why`/`kind`; `.unreachable` carries words naming
  WireGuard and Settings (Phase 0's Check screen - keep it there). Phase 1 needs a raw failure: `APIFailure {status,
  detail: String?, why: String?, kind: String?, path: String (under /deadwax), method}` read from the JSON body
  (`detail` string, or FastAPI's list of `msg`; `why`, `kind` strings) - and a no-answer case split by URLError:
  `.timedOut` -> timeout; `.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
  .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff` -> offline; anything else -> other.
- `ErrorWords.of(failure, admin:, service:, gone:, failed:, retry:) -> (kind, text, advice, detail?)` +
  `said`, `asSentence`, `plumbing`, `fit` - pure, Linux-tested.

### 3.5 The player's own failures (usePlayer.ts:189-224; 2.0.7 words; rules lib/playQueue.ts:183-224)

| code | when (web) | phone equivalent | words (`describeMediaError`) |
| --- | --- | --- | --- |
| 2 NETWORK | the connection dropped loading | URLError mid-fetch, or before any byte | `The connection dropped while this song was loading` |
| 3 DECODE | can't decode | AudioConverter/AVAudioFile decode error | `This device couldn't play this song's audio` |
| 4 SRC_NOT_SUPPORTED | not playable, OR a failed request | HTTP status not 200/206, or no audio found in the bytes | `Couldn't play this song - it didn't come as audio this device can play` |
| other | | anything else | `Couldn't play this song` |

(No full stop: they are shown as they are.) `afterFailure` :219: `!intendsToPlay || ABORTED(1)` -> stop; code 2 or
4 and not yet retried -> retry after `LOAD_RETRY_DELAY_MS = 1500` from where it stopped (same listen; words shown,
the play button busy); otherwise the next song (past Repeat One copies of the failed one) -> skip; none -> stop
(words stay). A skip shows `skipNotice` :220 for `SKIP_NOTICE_MS = 5000` IN PLACE OF the artist line (mini player
and Now Playing): decode -> `Skipped "\(title)" - this device couldn't play its audio`; else `Skipped "\(title)" -
it wouldn't play` (title `a song` when unknown); cleared early by anything replacing it. A stall (lane dry) shows
only the busy play button, no words. Web-only, not ported: `Tap play to start - this browser only plays audio
from a tap`. Phase 0's engine words (`deadwax answered 500 for this song.`, `The song stopped arriving: …`) become
the raw detail (Debug), never the listener's line. Pinned: playqueue.sim.cjs "a song that will not play" (:203+).

### 3.6 Signed out, signing in (src/auth.py:133-167; ui/src/lib/signIn.ts)

- Any 401 from any route but `/auth/*`, for a request sent under the CURRENT session (api/http.ts:98-102
  `noteSignedOut`; a 401 to a request sent before the latest sign-in is ignored) -> the sign-in comes up over the
  app; the app stays as it was underneath (the music plays on as far as it has). Its detail is shown above the
  form unless it is the plain `Sign in to use deadwax.` (`reasonShown` signIn.ts:56).
- 401 details: `Sign in to use deadwax.` (no session), `You've been signed out - sign in again.`, `Your sign-in ran
  out after 30 days without use - sign in again.`, `Navidrome no longer accepts the login you signed in with - if you
  changed your Navidrome password, sign in with the new one.`, `deadwax's sign-ins have been reset since you signed
  in - sign in again.`, `The break-glass sign-in has ended - it lasts 12 hours, and ends when
  DEADWAX_ADMIN_PASSWORD changes. Sign in again.`, `An admin reset your password - sign in with the new one.`, `Your
  account was removed.`, `Your password was changed from another device - sign in with the new one.`, `deadwax keeps
  that user name for itself now, so the sign-in it had has ended - sign in with another Navidrome account.`
- A failed sign-in (`signInProblem` :30): an answer whose detail isn't plumbing -> the detail (a split 503 with
  `why`: `asSentence(detail) + " Tell whoever runs deadwax."`); else 401 `That user name and password didn't
  work.`, 429 `Too many tries - wait a minute and try again.`, other `Something went wrong on the server - try again
  in a moment.`; no answer `Can't reach deadwax. Check you're on the right network (or your VPN is on) and try
  again.` `signInWhy` :49 (`why`, or a plumbing detail) folded under `For whoever runs deadwax`. Server details:
  `That user name and password didn't work.`, `Too many tries for <name> - wait <n> seconds and try again. …`,
  `deadwax can't read its database just now, so it can't check who you are.` (503, why names DB_PATH), `deadwax
  isn't ready for signing in, so nobody can use it just now.`, `deadwax can't reach the music server, so nobody can
  sign in just now.`, `Navidrome couldn't check your password just now - try again in a moment.`, `This account
  can't sign in to deadwax: it's an LDAP account, and deadwax needs a local Navidrome account. Ask an admin for one.`
- `afterSignIn(before, now)` :66: same user -> carry on; another -> start again (the queue was theirs).

### 3.7 Navidrome down or refusing (app/NeedsNavidrome.tsx; `GET /deadwax/navidrome/status`)

Status (src/routes/navidrome.py:240-261): `{configured: Bool, ok: Bool, server: String?, problem: String?}`; not
set up `{false,false,null,NOT_CONFIGURED}`; ping failed `{true,false,null,str(e)}` (an address: plumbing); ok
`server` = `Navidrome 0.64.2`; a refused personal login -> 401. The phone adds `offline` when deadwax itself
didn't answer (navidromeCheck.ts:41).
- Listener (not seesDetail): heading `Your music isn't available right now` (configured) / `Your music isn't
  available yet`; line `Can't connect to deadwax. Check your connection.` (offline) / `Can't reach the music server
  right now. If it keeps happening, tell whoever runs deadwax.` / `deadwax hasn't been connected to a music server
  yet. Tell whoever runs deadwax.`; `Try again` when configured.
- Whoever runs deadwax: `Can't reach Navidrome` + `problem` + `Your library comes from Navidrome, so it shows here
  once deadwax can reach it.` + `Try again`; or `Connect Navidrome` + `problem` + `deadwax needs Navidrome for your
  library: the app shows and plays the albums Navidrome lists, through deadwax - so the phone never needs
  Navidrome's password.` + (admin) `Set it up in Server settings (Connections), then come back.` / (not admin) `An
  admin can set it up in Server settings (Connections).`
- 403 (no Phase 1 route has a permission): `That needs \(label), which an admin hasn't given you. You're signed in
  as \(user).` (src/users.py:60; labels :50) - shown as written (fit).

### 3.8 Tests to mirror

ui/test/errors.sim.cjs:99-200: the class table (`Navidrome unreached` 502 with an address -> unreachable; `Navidrome
not set up` 503 naming NAVIDROME_URL -> unreachable; 404 `Not Found`; 401; 403; 409 in words -> refused; 503 in
deadwax's words -> refused; split 503 -> refused; 500 with slskd's traceback -> other; 422 `LIBRARY_PATH: not a
folder` -> other); serviceOf; offline for listener and admin (`detail` = raw only for admin); `That took too long.
Try again.`; unreachable for listener (`Try again in a minute - if it keeps happening, tell whoever runs deadwax.`)
and admin (`Try again in a minute.`, detail = Navidrome's words); not-found trio; not-allowed trio; refused
as written; deadwax's 5xx (`… If it keeps happening, tell whoever runs deadwax.` / admin bare); split 503 (`… Tell
whoever runs deadwax.` / admin detail = why); other; `said`; `asSentence('deadwax broke')` = `deadwax broke.`;
`noticeWords`; named refusals; the `retry` row (:192-200). signin.sim.cjs for 3.6; tests/test_error_words.py (server
words hold no setting for a listener).

---

## 4. `GET /deadwax/me` (src/routes/me.py:115-124)

### 4.1 The answer (200)

| field | type | logins off | logins on |
| --- | --- | --- | --- |
| `user` | String | `"local"` | the signed-in name (break-glass: `"deadwax"`) |
| `admin` | Bool | `true` | Navidrome's adminRole as last read, or break-glass (users.py:78) |
| `auth` | `"on"`/`"off"` | `"off"` | `"on"` |
| `version` | String | `src/__init__.py` (`"2.1.0"`) | same |
| `permissions` | [String], in order `request, edit, library, downloads, server, people` | all six | admin: all six; else `request` unless taken away + what an admin ticked; never `people` |
| `permissions_unverified` | Bool | `false` | `true` when an admin's grants aren't honoured this session (sign out and in) |

Pinned: tests/test_me.py:15 (logins off exact JSON: `{"user": "local", "admin": true, "auth": "off", "version":
<v>, "permissions": [all six], "permissions_unverified": false}`), :25 (`admin` false for another user with logins
off). The sign-in's 200 answer has the SAME six fields (src/routes/auth.py:69-73) - decode it as `Me`.
Failures: 401 + one of 3.6's details (with logins on and no/ended session); 503 Explained `{detail, why}` (database
unreadable, logins unusable) - classify with 3.2. With logins off nothing answers 401.

### 4.2 What the app derives (app/access.ts:34-71, lib/permissions.ts:71-75)

- `permissions` = auth off ? ALL : `permissionsOf(me)` = names from the list that are KNOWN (a stray word grants
  nothing); no list at all -> `admin ? ALL : NONE`.
- `on` = `auth == "on"`; `unverified` = `permissions_unverified == true`; `admin` = `auth == "off" || admin`.
- `seesDetail` = `admin || permissions.contains("server")`.
- Phase 1 uses: `admin` -> Debug tab and the Folder row; `seesDetail` -> error details; `on` -> Sign out (You)
  and Add/Remove to "my library"; `unverified` -> You's line `Some things an admin let you do are off for now -
  sign out and in again to get them back.` (permissions.ts:66); `request` -> Get (Phase 6). `version` may be shown
  in You.
- Before /me answers: the last Me kept with the session (the web uses the session's word; no session = logins off
  = admin). Asked: at launch, on returning to the foreground (scenePhase `.active`), after a sign-in, and when a
  song fails to load (to learn of a 401 at the first failure) - never on a timer (signInGate.tsx:17-35). Only the
  newest answer applies.

### 4.3 Swift changes

`Me` (Models.swift:19) gains `permissionsUnverified: Bool?` (CodingKey `permissions_unverified`) - OPTIONAL (section
0). Add `public struct Access { permissions: Set<Permission>; on, unverified, admin: Bool; seesDetail }` with
`Access(me:)` per 4.2 and `enum Permission: String { request, edit, library, downloads, server, people }`. Tests:
the logins-off JSON above -> all six, admin, not on; `{user, admin: false, auth: "on", permissions: ["request",
"bogus"]}` -> {request}; no list + admin -> ALL, no list + not admin -> NONE; seesDetail for `server` alone.

---

## 5. Open questions (each with a recommended answer)

1. **Info's Normalization on the phone: the gain APPLIED or the album's state now?** The web's `plain` is
   deadwax's memo of what it played; the phone decides at the song's start. **Recommend: the applied decision for
   the song playing (2.6), the route's live state only for a song not begun** - Info then never says "3.6 dB
   quieter" over a song heard as it is.
2. **Non-FLAC songs.** The plan proposes Navidrome's `replayGain` for MP3/AAC and for FLAC not yet measured; the web
   levels FLAC only and says `Off for this song - only FLAC songs are adjusted` / `Not this time - …`. **Recommend
   FLAC only in Phase 1**, so the 2.0.7 words stay true; replayGain would need new words (and a James decision).
3. **A 401 on a song's stream.** The web retries once and skips on through the queue (the gate shows sign-in).
   **Recommend: on the phone a 401 stops the queue at that song (held, not skipped) and asks /me**, so signing in
   carries on from it rather than finding the queue skipped to its end.
4. **Plays that fail to send in Phase 1.** **Recommend dropping them as the web does**, through one `PlayReporter`,
   with `time` always set on a submission, so Phase 2's `play_pending` is a change in one place.
5. **The artist card.** **Recommend name + "The album is by …" only in Phase 1** (no link, facts or count): its
   page, `/artists/{id}` and MusicBrainz facts arrive in Phase 4.
6. **The Gapless row.** The phone has no switch. **Recommend keeping the row, always `On`** (true: joins within a
   format are sample-exact; across formats it is a lane switch, which Debug can say).
7. **Error detail under the player's own failure line.** The web shows none (console only). **Recommend the same
   for Now Playing, plus a Debug row `Last failure` with the engine's raw words** for an admin.
8. **The admin's "Set it up in Server settings (Connections), then come back."** names a page the phone hasn't got
   until Phase 7. **Recommend keeping the words and making the line's action open `/player/` in Safari** (Phase 7's
   link), rather than inventing phone words.
