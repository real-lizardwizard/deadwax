# Phase 2 - Downloads: what the iPhone app shows and does (app 0.3)

Design spec for the iPhone app's Phase 2 ("Downloads"), read 2026-11-12 at `p2/downloads` b4ee591 (= `ios` e1c1351
plus the Phase 1 specs; server 2.1.3, app 0.2 (2)). Area: every place a download is asked for, You > Downloads,
offline, and the machinery under them, with Phase 2's checks. Every path is repo-relative and every line number is
the code's at b4ee591.

**What binds it.** The plan (`~/Desktop/Code/deadwax-ios-plan.md`, outside the repo): James's answers at its top
(lines 3-7: "two download settings he must be able to change in the app (Settings -> Downloads): Download over:
Wi-Fi only (default) / Wi-Fi and cellular ..., and Storage limit (a picker, e.g. 5 / 10 / 20 (default) / 50 / 100 GB
/ No limit - what downloads may take; the streaming cache apart). Both from Phase 2, shown with what's used now.");
its section 4 "Offline"; section 5's Phase 2 (features and 6 checks); "Choices made" 16, 17, 19 and 20. Then Phase 1's
design: `notes/ios-specs/phase1/` (screens.md above all), `notes/ios.md`'s app sections, `docs/ios.md`, and the app
as built.

**Where the words and marks come from.** The web app has no downloads to a device - its "Download" and
"Downloading" are Soulseek's (Requests, `ui/src/lib/requestsView.ts:49`) - so this is the first area of the app with
no web screen to read. Where the web has a rule (errors in a listener's words, the vocabulary, the badge, the bar),
it is followed and cited; where it has nothing, Apple Music's own download marks are followed, as remembered from
iOS 17-18 (**not seen here**: there is no Simulator, and Apple Music on James's phone is the check - section 10).
Every SF Symbol named was looked up in this Mac's own symbol table,
`/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist`, with the iOS release
it first shipped in. `Image(systemName:)` with a name iOS doesn't have draws nothing and fails no build, so no
symbol newer than iOS 17 is used without `if #available`.

## 0. The foundation - checked

- `p2/downloads` is b4ee591, clean. `src/__init__.py` says `2.1.3`; `ios/Config/Base.xcconfig:11-12` say
  `MARKETING_VERSION = 0.2`, `CURRENT_PROJECT_VERSION = 2`. Phase 2's commits leave both alone; the app becomes
  0.3 at the merge, with check_project.py, ios.yml and tests/test_ios_install.py pinned with it (as 0.2 was,
  notes/ios.md "Phase 1: the app (0.2)").
- **Every route Phase 2 needs is already in the app's Routes** (`ios/DeadwaxKit/Sources/DeadwaxCore/Routes.swift`)
  and live on the server, so `tests/test_ios_contract.py`'s count doesn't move:

  | what | route | server |
  | --- | --- | --- |
  | the song's file | `Routes.stream` `GET /deadwax/navidrome/stream/{song_id}?format=` (:28) | `src/routes/navidrome.py:472` |
  | the cover, kept | `Routes.cover` `GET /deadwax/navidrome/cover/{cover_id}?size=` (:29) | `navidrome.py:450` |
  | the album, kept for offline | `Routes.album` `GET /deadwax/navidrome/albums/{album_id}` (:37) | `navidrome.py:332` |
  | its loudness, kept | `Routes.loudness` `GET /deadwax/navidrome/loudness/album/{album_id}` (:49) | `navidrome.py:685` |
  | measuring it first | `Routes.levelAlbum` `POST /deadwax/navidrome/level/album/{album_id}` (:45) | `navidrome.py:666` |
  | plays sent later | `Routes.scrobble` `POST .../scrobble/{song_id}?submission=&time=` (:41) | `navidrome.py:701` |
  | queue saves sent later | `Routes.saveQueue`, `Routes.saveQueueAt` (:53-54) | `navidrome.py:1448,1476` |
  | is deadwax there | `Routes.health` `GET /deadwax/health` (:23) | `src/api/app.py:496`, public (`tests/test_logins.py:91`) |

- **No server addition is needed for Phase 2.** The raw stream already relays what a resumable background
  download needs: `PASSED_HEADERS` carries `content-length`, `content-range`, `accept-ranges`, `last-modified` and
  `etag` (`navidrome.py:55-56`), and `STREAM_CONDITIONS` passes `range` and `if-range` up (`:79`). *Assumed, not
  seen*: that Navidrome's raw stream answers with a `Last-Modified` (it serves the file through Go's
  `http.ServeContent`, as read from its source, never recorded from a real one - CLAUDE.md "What the tests cannot
  tell you"). Without a validator URLSession makes no resume data and an interrupted song starts again from its
  first byte; nothing breaks, and check 5 shows which. If it is missing, the 2.1.x patch on main would be deadwax
  adding a strong `ETag` to the raw relay (from Navidrome's `size` and the song's `updated`); not built here.
- **No Info.plist key and no entitlement.** A background `URLSession` needs neither (the plan's "Background
  downloads"); `UIBackgroundModes` stays `[audio]` (`ios/Config/Info.plist`, checked by
  `ios/scripts/check_project.py:270`). `fetch` and `BGTaskSchedulerPermittedIdentifiers` are Phase 3's
  (auto-download).
- **Phase 0's own downloads retire.** `SongFiles`' downloads half (`ios/App/SongFiles.swift:133-177`, the folder
  `Application Support/deadwax/phase0`, `:36`), DebugModel's use of it (`ios/App/Models/DebugModel.swift:115-134`)
  and the engine's `copies` branch (`ios/App/Models/PlayerModel+Engine.swift:196`) give way to the downloads below.
  The `phase0` folder is deleted once at 0.3's first launch.
- **Not the `downloads` permission.** `Access`'s `downloads` (`DeadwaxCore/Access.swift:10`) is deadwax's own -
  Get, Soulseek. A download to the phone is the same raw stream the person may already play, so it is never gated
  by it: anyone who can play a song can download it.
- **Files other rounds are working on** (MainTabs.swift and the screens' bottom insets; Up Next's Core,
  QueueController and UpNextScreen): this spec adds one modifier beside that round's `clearsPlayer()` - in its
  TabStack and in `appRoutes()` (`ios/App/Shared/Routes.swift:129`), built after it merges (section 7.2) - and
  leaves Up Next's files alone (section 4.3). New screens (Downloads, Downloaded) take the mini player's room the
  way that round settles, nothing of their own.

*Reviewed the same day* (a second commit), as a demanding designer would read it against Phase 1's screens, the
app as built and Apple's patterns: the changes are in place below, and the review's list is in the commit message.

## 1. Words and marks

### 1.1 The vocabulary

- **"Download"** is the verb, as Apple Music has it: keep a song on this phone, to play without deadwax.
  **"Downloaded"** is the state and the Library's list. **"this phone"** is the app's own phrase ("This phone" in
  You, `YouWords.thisPhone`; "This is kept on this phone.", `YouWords.kept`), used wherever "download" alone could
  be read as deadwax fetching from Soulseek: "Removed from this phone: Dummy", "On this phone", "Not on this phone".
- The web's binding words hold: "your library", "the collection", "All music"; never "the store", "Navidrome",
  "Browse" or "everything" (`ui/test/vocabulary.sim.cjs:5-6`). Never "offline mode", "sync", "cache", "MD5" or
  "checksum" for a listener: a check is "checked", and what it checked is said in plain words (6.6). Debug, an
  admin's, names MD5.
- **"Wi-Fi and cellular"** is James's own name for the choice (binding); the lines under it say **"mobile data"**,
  as his phone's Settings does (check 2 reads "Settings > Mobile Data"). Open question 21.
- Errors in a listener's words (CLAUDE.md "Errors in a listener's words"): a failed HTTP request or transport is
  said by Core's ErrorWords, through an `APIFailure` made for the stream's path (`/navidrome/stream/...`, so its
  service is the music server's, `ErrorWords.service(of:)`, ErrorWords.swift:93); only the download's own
  failures (a wrong size, a sound that didn't match, a file iOS can't read, no room) get new words, in
  DownloadWords, in the same voice (2.4).
- Title case for menu items, as Phase 1's are ("Play Next", "Play Last"): **"Download"**, **"Remove Download"**,
  **"Download Again"**, **"Download Up Next"**. Sentence case for buttons in a screen, as the app's are
  (`LibraryWords.tryAgain` "Try again", LibraryWords.swift:25): **"Try again"**, **"Try all again"**.

### 1.2 The marks

| state | mark | iOS | colour | taken from |
| --- | --- | --- | --- | --- |
| not downloaded (the control) | `arrow.down.circle` | 13.0 | `Palette.accent` (the tint) | Apple Music's download button |
| waiting | `arrow.down.circle.dotted` | 17.0 | `Palette.quiet` | Apple Music's "waiting" mark; the symbol is the one SF Symbols 5 added for it |
| downloading | the ring (1.3) - on the control with a `stop.fill` square at its centre, everywhere else the ring alone | 13.0 | accent arc on a quiet track | Apple Music's progress ring |
| downloaded | `arrow.down.circle.fill` | 13.0 | `Palette.quiet` | Apple Music's grey downloaded mark beside a song |
| didn't download | `exclamationmark.circle.fill` | 13.0 | `Palette.amberIcon` (new) | deadwax's own: the web's amber is a warning that can be acted on |
| not on this phone (offline) | the row or tile at `Palette.off` (new), no mark | - | - | iOS's own "dimmed"; the web's `--app-pin-off` |
| checked (You > Downloads) | `checkmark.circle` + "Checked" | 13.0 | `Palette.held` | the web's green "In your library" badge |
| offline (the banner) | `wifi.slash` (no network) / `wifi.exclamationmark` (deadwax not answering) | 13.0 | `Palette.amber` on `Palette.amberFill` | the web's amber badge; `wifi.exclamationmark` is the app's own can't-reach mark (`ios/App/Root/UnreachableView.swift:23`) |

Not used, though they fit: `arrow.down.circle.badge.pause` and `.badge.xmark` (iOS 26.0), `.badge.clock` and
`.badge.checkmark` (iOS 27.2) - newer than the app's iOS 17 target, and one look on every phone is worth more than
a richer one on James's alone. `network.slash` (iOS 17.0) reads as a broken network, which isn't always so - deadwax
may be the one not answering. `icloud.slash` reads as iCloud, which deadwax isn't.

**One place, one meaning.** Wherever a song or an album shows its state - a row, a tile, the hero's line, the
Library's rows - it is the same slot with the same mark, so a reader learns it once: filled for here, dotted for
waiting, the ring for on its way, amber for didn't. The stop square is the control's alone: it is the one ring that
can be tapped, and a square that promised a stop where a tap plays the song would lie.

### 1.3 The ring

Drawn by the app (SwiftUI's circular `ProgressView` is a spinner on iOS whatever its value): a `Circle` stroked
`Palette.quiet.opacity(0.35)` for the track, a second trimmed `0...fraction`, stroked `Palette.accent` with round
caps, rotated -90° so it fills from twelve o'clock, and - on the control only (1.2) - `stop.fill` at about a third
of the diameter in the centre, Apple Music's own. Line width 2 pt (toolbar) / 1.5 pt (rows, tiles). The fraction
moves with `.linear(duration: 0.25)`, and not at all with Reduce Motion.

The ring is always determinate - nothing turns, so there is nothing for Reduce Motion to stop. A task out with no
byte yet is `waiting(queued)` and draws the dotted mark (2.1); a transcode, which has no size, fills by its bytes
over its estimate (8.5), held under 95% until it lands.

### 1.4 Palette additions (`ios/App/DeadwaxApp.swift:51-72`, each named for its token)

- `amberIcon` - `--dw-amber-icon` `#fbbf24` (`interface/styles/theme.css:513`).
- `off` - an opacity, `--app-pin-off` `0.45` (`interface/player/app.css:298`: "a pin, or an Edit button, that
  can't be used just now").
- `barTrack` - `--dw-track` `#121117` (theme.css:491), `barEdge` - `--dw-border` `#2c2a36` (:497), and
  `barFill` - `--dw-bar-purple`, `#b56af5` to `#9333ea` top to bottom (:538): the Requests board's bar,
  `.app-bar` (app.css:1614-1630), 6 pt tall (`--dw-bar`, :539), radius 2 (`--dw-radius-track`, :547) with a 1 pt
  fill radius (:548), a hairline border and the track's inset shade. You > Downloads draws its bars with it, so a
  download on the phone looks like one on the web. (Named `bar…`, not `track`: in a music app a track is a song.)

## 2. A download's state (DeadwaxCore: the rules every screen draws)

### 2.1 A song

| state | what it means | plays from |
| --- | --- | --- |
| `none` | not asked for | the stream |
| `waiting(reason)` | asked for; not being fetched now | the stream |
| `fetching(fraction)` | its first bytes have come; the fraction is bytes received over bytes expected (a transcode's over its estimate, 1.3) | the stream |
| `done(check)` | on the phone, its length checked | **the phone** |
| `failed(reason)` | given up on after three tries (8.3) | the stream |

`check` is `unchecked` (a FLAC not yet decoded), `matched` (its decoded sound's MD5 is STREAMINFO's) or `bySize`
(not a FLAC, a FLAC whose MD5 is all zeros, or one over 24 bits - 8.4). A copy whose sound doesn't match is never a
state: it is deleted and is a try, back to `waiting` (8.4).

Waiting reasons, in the order the planner gives them (8.5): `connection` (no network at all), `deadwax` (the network
is there, deadwax doesn't answer), `signIn` (a 401: the session ended), `wifi` (Wi-Fi only, on mobile data),
`hotspot` (Wi-Fi only, on a Wi-Fi that is a phone's hotspot - iOS calls it expensive), `lowData`, `room` (the
storage limit), `phoneFull` (2 GB of the phone must stay free), `queued` (its task is out and hasn't had a byte yet -
the session fetches three at a time, 8.3).

### 2.2 An album (`AlbumDownload.of(songs)`)

From the album's songs as deadwax lists them, in this order:

1. any `fetching` -> **downloading**, fraction = (bytes of its songs on the phone and received so far) over (bytes of
   every song of it on the phone or asked for);
2. any `waiting` -> **waiting(the first song's reason)**;
3. any `failed` -> **failed(count, the first reason)**;
4. every song `done` -> **downloaded** (and `checking` while any is `unchecked`);
5. some `done` -> **partial(n of m)**;
6. else **none**.

### 2.3 The words (DownloadWords, every one tested)

| state | the album's line (hero, 3.2) and the control's VoiceOver value | a song's (row, VoiceOver) | a tile's line (Downloaded, 5.1) |
| --- | --- | --- | --- |
| none | (nothing) | (nothing) | - |
| partial | "3 of 12 songs downloaded" | - | "3 of 12 songs" |
| downloading | "Downloading - 4 of 12 songs" (value: "Downloading, 40 percent") | "Downloading, 40 percent" | "Downloading" |
| waiting `queued` | "Waiting to download" | the same | "Waiting" |
| waiting `connection` | "Waiting for a connection" | the same | "Waiting" |
| waiting `deadwax` | "Waiting for deadwax" | the same | "Waiting" |
| waiting `signIn` | "Waiting for you to sign in" | the same | "Waiting" |
| waiting `wifi` | "Waiting for Wi-Fi" | the same | "Waiting" |
| waiting `hotspot` | "Waiting - this Wi-Fi is a hotspot" | the same | "Waiting" |
| waiting `lowData` | "Waiting - Low Data Mode is on" | the same | "Waiting" |
| waiting `room` | "Waiting for room - the storage limit is reached" | the same | "Waiting" |
| waiting `phoneFull` | "Waiting for space on this phone" | the same | "Waiting" |
| failed | "1 song didn't download" / "2 songs didn't download" | "Didn't download" | "Didn't download" (amber) |
| downloaded | "Downloaded" | "Downloaded" | "12 songs" |
| offline, not here | (the page's own line, 3.7) | "Not on this phone" | (dimmed, "Not on this phone" spoken) |

"1 song" / "2 songs" as `AlbumPageLines.footer` counts them (`Format.swift:80-85`). A tile has one short line
(lineLimit 1 at a tile's width); its VoiceOver words are the album's line in full.

Two more lines, each the page's (3.7):

- an album deadwax no longer has, with songs of it on this phone: **"This album isn't in the collection any more -
  the songs on this phone still play."**;
- an album not on this phone, opened while deadwax can't be reached: **"This album isn't on this phone - it plays
  once deadwax is back."**

### 2.4 Why a song didn't download

Said in the row's ••• (3.4), in You > Downloads (6.5), and as the reason a waiting song stands for:

- **An HTTP answer or no answer** - an `APIFailure` for `GET /navidrome/stream/{id}` said by ErrorWords.of, with
  `gone: "This song isn't on deadwax any more."` for a 404. So: "Can't connect to deadwax.", "That took too
  long.", "Your sign-in has ended - sign in again.", "You don't have permission for that.", "Can't reach the music
  server right now.", "Something went wrong." (ErrorWords.swift:72-87), each with its own advice and, for
  `seesDetail`, the raw words under it - the same split every refusal in the app has.
- **The download's own** (DownloadWords, the advice ErrorWords gives "other": "Try again - if it keeps happening,
  tell whoever runs deadwax.", an admin's "Try again.", ErrorWords.swift:188):
  - the length was wrong three times: **"The copy kept arriving the wrong size."**
  - the sound didn't match three times: **"The copy's sound didn't match the original."**
  - iOS couldn't open or decode it: **"This phone couldn't read the copy."** (as ErrorWords' media words say "This
    device couldn't play this song's audio", ErrorWords.swift:466 - "this phone" being the app's own word)
  - the file couldn't be written: **"This phone couldn't save it."**
- 401 and the network gone are never failures: they are `signIn`, `connection` and `deadwax` waits, and carry on
  by themselves. A full phone is `phoneFull`.

### 2.5 What each menu offers (`DownloadChoices.for(songs)`)

- **One song**: `none` -> "Download"; `waiting` or `fetching` or `done` -> "Remove Download"; `failed` -> "Download
  Again" and "Remove Download".
- **Several** (an album, Up Next): "Download" when any song is `none` or `failed` (it asks for those, and only
  those); "Remove Download" when any is anything but `none` (it stops what is coming and deletes what is here).
- "Remove Download" is `role: .destructive` (red) with `trash`; "Download" and "Download Up Next" have
  `arrow.down.circle`; "Download Again" `arrow.clockwise` (iOS 13.0 each).

## 3. The album page

`ios/App/Album/AlbumView.swift` (hero, rows, the bar's •••), `AlbumHero.swift`, `TrackRow.swift`,
`ios/App/Player/QueueMenu.swift`. The page reads the album's and each song's state from one `DownloadModel` in the
environment (8.9), by the album's id - never from what the page itself last did.

### 3.1 The control, in the bar

A `ToolbarItem(placement: .topBarTrailing)` placed **before** the •••'s (AlbumView.swift:90-95), so the two sit
together in the bar's group as Apple Music's download button sits beside its •••. It is drawn from the album's
state (2.2):

| state | drawn | a tap |
| --- | --- | --- |
| none, partial | `arrow.down.circle`, accent | **downloads at once** - every song not on the phone, as the album |
| waiting | `arrow.down.circle.dotted`, quiet | opens a menu: its title the album's line ("Waiting for Wi-Fi") - for a wait a setting causes, a second line naming it ("Download over is Wi-Fi only - in You > Downloads.", "The storage limit is 20 GB - in You > Downloads.") - and "Remove Download" |
| downloading | the ring | a menu: "Downloading - 4 of 12 songs", and "Remove Download" |
| failed | `exclamationmark.circle.fill`, amber | a menu: "2 songs didn't download", the first reason under it, "Download Again", "Remove Download" |
| downloaded | `arrow.down.circle.fill`, quiet | a menu: "Downloaded · 412 MB", and "Remove Download" |

- Only the arrow acts at once - it is what it promises, and it adds, never takes away. Every other state opens a
  SwiftUI `Menu` from the control itself (the rule Phase 1 learned, notes/ios.md "The ••• menus open from the
  •••"), `menuOrder(.fixed)`, whose title says in words what the mark only shows. Apple Music stops a download at a
  tap on its ring; here the ring's tap says how far it has got and offers Remove, so a tap meant for the ••• beside
  it never throws a download away (Open question 5). The menu's title is one `Section` header of one or two lines
  (a newline between them); iOS wraps a menu's title, which check 7 sees.
- A wait a setting causes says where the setting is, in the menu, rather than offering to get round it ("download
  over mobile data this time"): one place for each setting, and the words point to it.
- Disabled, as the ••• is, until the album's songs are in (`model.album != nil`): a download needs them. A
  downloaded album's page has them at once from the phone (3.7), so its control is live at once.
- **VoiceOver**: label "Download" in every state; value the album's line (2.3), "Downloading, 40 percent" while
  fetching, with `.updatesFrequently`; nothing in `none`. **Large Content Viewer**
  (`.accessibilityShowsLargeContentViewer`), as the bar's own items have, since a bar's symbols don't grow with
  Dynamic Type.
- When a download asked for from this page ends while the page is on top: an announcement, "Downloaded Dummy", or
  "Dummy: 2 songs didn't download" - VoiceOver hears the end of what it started; nothing is drawn for it beyond the
  control and the line changing.

### 3.2 The hero's line

A line of its own **directly under the badge** (AlbumHero.swift:48-51), centred, above Play and Shuffle: the
album's line (2.3) drawn in the "In the collection" style (caption, semibold, `Palette.quiet`, no box) with the
state's mark in front at caption size - `arrow.down.circle.fill` for downloaded and partial, the dotted mark for
waiting, a 9 pt ring for downloading, amber `exclamationmark.circle.fill` (and amber words) for failed. Nothing at
all in `none` - no space held - so an album never downloaded looks exactly as in Phase 1.

- **Its own line, not beside the badge.** Side by side, centred, the badge would slide sideways each time the
  count changed ("4 of 12" to "10 of 12"), and the pair would jump between one row and two as a wait's words grew
  ("Waiting for room - …") - the hero's own rule is that nothing slides or flips (the badge's place is held unseen
  for it). Alone on its line it only re-centres itself, and wraps at the largest sizes (`fixedSize(horizontal:
  false, vertical: true)`).
- It appears with a state, moving Play and Shuffle down one caption line. That happens only from the person's own
  tap at the top of the page (the control, the bar's •••, a row's •••) or as the page draws - `DownloadModel` holds
  every state in memory from launch, so a page never learns its state late and never jumps after it is drawn.
  The move is animated (`.default`), not with Reduce Motion.
- The line is the words the control's mark stands for: a reader who doesn't know a dotted circle reads "Waiting for
  Wi-Fi". It is the hero's only addition: no third button beside Play and Shuffle.
- VoiceOver reads it in the hero's order, after the badge. It is not a button; the control is.

### 3.3 The rows

TrackRow (TrackRow.swift:22-63) gains a **state slot** between the title and the time, inside the row's play
button: the song's mark at `.caption` (`@ScaledMetric(relativeTo: .caption)` 13 pt for the ring - the ring alone,
no stop square: the row's tap plays the song), `Palette.quiet` (amber for failed), aligned to the title's first
baseline (`alignmentGuide(.firstTextBaseline)`), as the row's HStack is (TrackRow.swift:25).

- The slot is drawn on every row of an album where **any** song has a state, and on none where none does, so the
  times stay in one column and an album never downloaded is Phase 1's page exactly.
- Nothing per row for `unchecked`: a song plays before its check (8.4), and the difference is You's and Info's to
  say.
- **VoiceOver**: the row's words gain the song's state after the title - "Roads, Downloaded, 4:12" - and the row gets
  `accessibilityActions` with the song's menu items (2.5: "Download", "Remove Download", "Download Again"), so
  nobody needs to find the ••• to download one song.
- Dynamic Type: the mark grows with the caption style; at accessibility sizes the row's title already wraps
  (`typeSize.isAccessibilitySize ? 3 : 1`, :31) and the mark stays on the first line, aligned to its baseline.

### 3.4 The menus

QueueMenu (QueueMenu.swift:34-50) gains a second `Section` under Play Next and Play Last, drawn from 2.5:

```
Roads                        Dummy
  Play Next                    Play Next
  Play Last                    Play Last
  ─────────                    ─────────
  Download                     Download
                               Remove Download   (red)
```

- A failed song's section has the reason as its header ("Can't connect to deadwax."), then "Download Again" and
  "Remove Download".
- Every item gets its symbol (Open question 17): Play Next `text.line.first.and.arrowtriangle.forward`, Play Last
  `text.line.last.and.arrowtriangle.forward` (iOS 16.0 each), the download items as 2.5 says - Apple's menus carry
  one on every item, and a menu where two items had one and two hadn't would look unfinished. The same holds for
  Now Playing's ••• (4.1): Info `info.circle`, Go to album `square.stack` (the app's own albums mark - the Library
  tab's and All albums', MainTabs.swift:19, AlbumsScreen.swift:255), iOS 13.0 each. `Button(_:systemImage:)`, so
  the symbol is the menu's own trailing image and VoiceOver reads the words alone.
- Each item is carried out in its tap, through `DownloadModel` (8.9). A download never starts the music, so the
  gesture rule's allowlist (`ui/test/app-rules.sim.cjs`'s, CLAUDE.md "The player") is untouched.
- The bar's ••• is dimmed until the songs are in, as now.

### 3.5 The footer

Under "12 songs, 48 min" (`AlbumPageLines.footer`, Format.swift:80), a second line whenever any song is on the
phone: **"412 MB on this phone"** (`Bytes.words`, 8.6), or for a partial album **"3 of 12 songs on this phone ·
92 MB"**. Footnote, `Palette.quiet`. The size is deadwax's own: Apple Music doesn't say it, but space is what the
storage limit spends.

### 3.6 Notices

- **Download, from the page**: no notice - the control, the line and the rows all change.
- **Remove Download, from the page**: **"Removed from this phone: Dummy"** (or the song's title), for the notice's
  5 s (D11, `Notice.seconds`, Notice.swift:3,7), announced. Taking a download away changes only a mark, so it is said.
- Words through `PlayerModel.say` (PlayerModel.swift:259), the one notice there is; nothing new in MainTabs'
  PlayerInset.

### 3.7 Offline, and a downloaded album's page at any time

- **Drawn from the phone first**: `AlbumModel.load` (AlbumModel.swift:103) draws the album's kept answer (8.2's
  `album` table) at once when there is one, then asks deadwax as now; the answer, when it comes, replaces it and is
  kept again. So a downloaded album opens at once, online or not, and its hero cover is the kept one (8.8).
- **Offline** (section 7):
  - songs not on the phone are drawn at `Palette.off` and are not buttons (`.disabled(true)`, which VoiceOver says
    as "dimmed"); their ••• keeps Download (it waits for deadwax) and drops Play Next and Play Last;
  - **Play** and **Shuffle** queue the songs on the phone only - the album's, in its order, as an album; Shuffle
    those once each - and are disabled when there are none;
  - the mine block (Add / Remove) is not drawn: it needs deadwax, and nothing stale is shown as if it could act. The
    badge stays, from the kept album's `starred`;
  - the footer's second line says what is here, as online: **"3 of 12 songs on this phone · 92 MB"**;
  - a pull to refresh asks deadwax at once (7.1's probe) and changes nothing if it isn't there; the banner says why.
- **An album not on the phone, opened while deadwax can't be reached** (Now Playing's Go to album, Info's album
  card, a queue made before): the hero from what opened it, and where the songs would be, quiet, **"This album isn't
  on this phone - it plays once deadwax is back."** Nothing was asked (7.1: nothing that needs deadwax is asked while
  it can't be reached), so there is no failure to say - this is a state, in DownloadWords, not ErrorNote's offline
  words, which stay for an ask that went out and failed (online a moment ago, Phase 1's case). The control and the
  ••• are dimmed (no songs in hand). It is drawn again from deadwax as soon as the banner goes.
- **An album deadwax no longer has** (404, or Navidrome's `{}` - AlbumModel.swift:152-162), with songs of it on
  this phone: the page keeps the kept answer - hero, rows, Play, the songs on the phone - and in place of Phase 1's
  "This album isn't here any more" (`ErrorWords.albumGone`), quiet, under the hero, **"This album isn't in the
  collection any more - the songs on this phone still play."** Songs not on the phone are dimmed as offline; the
  control offers Remove Download (and Download is gone: there is nothing to fetch). Nothing is deleted by itself: it
  was downloaded by hand (Choice 19). With nothing of it on the phone, Phase 1's page, unchanged.

## 4. Now Playing, and Up Next

### 4.1 Now Playing's •••

NowPlayingMenu (`ios/App/Player/NowPlayingMenu.swift:15-32`) gains a second section under Info and Go to album:

- for the song playing, 2.5's one-song items ("Download", "Remove Download", "Download Again");
- **"Download Up Next"** - every song from the one playing to the end of the queue that is `none` or `failed`, each
  asked for as a song (a hand download, 8.2) - shown only when there are at least two such songs, so it never
  duplicates "Download". **Not offered during a library's shuffle** (`player.paged`, NowPlayingView.swift:118): that
  queue is your whole library in pages, and keeping your library on the phone is Phase 3's own setting, with its
  limit and its order - not a menu item that would start tens of thousands of downloads.
- Every item carries its symbol (3.4): Info `info.circle`, Go to album `square.stack`, the download items 2.5's.
- The button's name becomes `NowPlayingWords.more` with ", download" (`Info.swift:420`, "More: info, go to album,
  download").

### 4.2 Its notices - over Now Playing

Now Playing has no mark to change, so these are said: **"Downloading: Roads"** (as "Playing next: Roads" is),
**"Downloading 23 songs from Up Next"** ("1 song"), **"Removed from this phone: Roads"**. Now Playing is a
`fullScreenCover` over the tabs (MainTabs.swift:30), so the notice capsule behind it can't be seen: NowPlayingView
draws `player.notice` itself, the same `Notice` view, for its 5 s - **in its top row, centred, as an overlay** on
the chevron's row (NowPlayingView.swift:43-53), where nothing else is. Not above the footer: the footer sits 12 pt
under the transport (:84-87), so a capsule there would either push Play and Next up under a finger or cover them.
In the top row it moves nothing and covers nothing but the space beside the chevron (at the largest text sizes it
may reach over the cover's top margin, for its 5 s). It comes in with opacity alone.

- **Announced once, by whoever says it.** Two capsules now draw the one `player.notice` - the tabs' (PlayerInset,
  MainTabs.swift:46-49, behind the cover) and Now Playing's - and each `Notice` announces as it appears
  (Notice.swift:19-20), so VoiceOver would hear it twice; and whether a view under a full-screen cover still
  "appears" isn't known here. So the announcement moves out of the view into `PlayerModel.say`
  (PlayerModel.swift:259), once per notice said, and `Notice` only draws. Nothing changes for a notice over the
  mini player.

### 4.3 Up Next

No download control in Up Next (it is about order, and its files are another round's): its Download is Now
Playing's "Download Up Next". Its rows' marks and their dimming offline waited for that round to merge - one small
change to UpNextScreen's row, drawn from the same `DownloadModel`, and Open question 11 - and are decided here.

#### 4.3.1 The rows' marks and dimming (the finishing round)

Up Next (`ios/App/UpNext/UpNextScreen.swift`) draws a song as a cover, its title, and a line under it -
"Portishead · Dummy" (`UpNextWords.songLine`) - with nothing after: the shape of the Library's list row (5.3), not
the album page's, which ends in a time column. Apple Music's Up Next, as remembered (iOS 17-18; not looked at again
for this), draws its rows the same way with no download marks at all; deadwax's queue mixes songs on the phone with
songs that need deadwax, and Download Up Next fills it, so here the marks earn their place.

- **The mark** is 3.3's song mark, the same `DownloadMark` view TrackRow's slot draws - filled for here, dotted for
  waiting, the ring alone while downloading (no stop square: the row's tap plays), amber for didn't; nothing for
  `none`, and nothing for `unchecked` (Info says it). At `.caption`, `Palette.quiet` (amber for didn't).
- **Where**: at the end of the row's line, outside its words - an `HStack(alignment: .firstTextBaseline, spacing: 4)`
  with the line's `Text`, the mark `fixedSize` - as the Library row carries an album's (5.3's `ArtistLine`). So a long
  line wraps before the mark rather than taking it, the mark stays on the line's first baseline at every text size,
  and the trailing edge stays the drag handle's in Edit. A song with no line (neither artist nor album) carries it
  after its title. No room is held on rows without a state: the album page holds a slot to keep its times in one
  column, and Up Next has no column after the line.
- **Which rows**: every song Up Next shows - History's, the song playing's card, Playing Next's and the list's -
  and in Edit too (offline, the marks are how you choose what to take out). The card is marked but never dimmed:
  the song playing is the player's to speak for (7.3's stopped line), and Info's Plays from (4.4).
- **Dimmed offline** (7.4): while deadwax can't be reached (`Reachability.online` false), a row whose song isn't
  downloaded (`SongDownload.isHere` false) is drawn at `Palette.off` - by downloads alone, as the album page's rows
  are (3.7), though the player also plays a whole stream-cache copy (`playsHere`): "Not on this phone" means one
  thing everywhere, and the player's check reads the disk (and touches the copy's date), which no row should do as
  it draws. Out of Edit a dimmed row isn't a button (`disabled`): its tap would only stop on the song, "Not on this
  phone - it plays once deadwax is back" - a History row's the same. In Edit only its words and mark dim: its red
  minus and the List's drag handle stay whole and work, since offline is exactly when you'd take out what won't
  play, and the order still holds for when deadwax is back.
- **VoiceOver**: a row keeps its name ("Roads, play now", "Roads, play again" - UpNextWords, the web's words) and
  gains the song's state as its **value**, read after the name: "Downloaded", "Downloading, 40 percent", "Waiting for
  Wi-Fi", "Didn't download" (`DownloadWords.songLine`), and, dimmed, "Not on this phone" with iOS's own "dimmed". In
  Edit, the row's one element ("Roads, Portishead · Dummy") gains the same value; its actions stay Move up, Move
  down and Remove - no Download among them, as there is no download control here. The card: "Roads, Portishead ·
  Dummy, Downloaded, heading".
- **Cheap for a long queue**: the mark and the dim are small views of their own (`UpNextSongMark` and the
  `upNextDownload` modifier), each reading the `DownloadModel` for its one song (`state(id)`, three dictionary
  lookups) and `Reachability.online`. So a song arriving, or progress four times a second, redraws only those views
  of the rows on screen - the List draws no others - never Up Next's own body, which makes Core's `upNextView` of
  the whole queue. Progress is followed once for the sheet, in its `.task` (`followProgress()`, the album page's
  way), and asks the session only while something is fetching: no timer per row. (History is at most 50 rows, the
  list 100, then "And N more songs.")
- **Unchanged**: the row's tap, its words, Edit's moves and removals, the scroll and focus rules, the sheet's
  closing; no download item anywhere in Up Next.

### 4.4 Info - where the song plays from

The plan has a downloaded song "shown as 'not yet checked'" until its check is done, and its check 1 that "every
song shows 'checked'": the album page draws nothing per row for that (3.3), so the song's own place to say it is
Info, the sheet that already says how it sounds.

- **About > Sound** (InfoView.swift:142-148) gains a fourth row under Format, Gapless and Normalization: **"Plays
  from"** - **"This phone - checked"** (`matched`, or an MP3's `bySize`), **"This phone - checked by size"** (a
  FLAC with no fingerprint), **"This phone - not checked yet"** (`unchecked`), or **"Streamed from deadwax"**. With
  Debug's "Stream even when downloaded" on, the last - the row says what is heard, not what is kept.
- It is drawn by the App from DownloadWords, **after** `LevelWords.soundRows`' three, so those stay the web's
  (aboutSound.ts's rows, held to its vectors) and the phone's own row is apart from them.
- **Info > Debug** (admins), "Sent to this device", gains **"On this phone"**: the check and STREAMINFO's facts in
  Debug's words ("matched - MD5 4f1c…e2, 24-bit 96 kHz, 2 ch"; "not kept" for a song not on the phone).

## 5. The Library

### 5.1 Downloaded, a list of its own

Everything on this phone, whoever's library it is in - an album downloaded from All albums is as much on the phone
as one of yours. It is **one more Albums screen** (`ios/App/Library/AlbumsScreen.swift`), drawn exactly as the
others are: the same five sorts (`AlbumSort`, Shelves.swift:9-25, one choice for every list as now), Find ("Find in
albums"), the headers, the index at 50+ albums, tiles or rows. Its albums are the kept album answers (8.2) made into
`IndexAlbum`s.

- Title **"Downloaded"**; its count ("12 albums") as every list's, `ShelfView.countText` (AlbumsScreen.swift:55-56).
- **"Recently added" means downloaded to this phone**, newest first, grouped by the month its first song arrived -
  as it means added to your library on Your albums and to the collection on All albums (`AddedBy`, Shelves.swift:38,
  its groups :212; `AlbumScope.addedBy`, LibraryModels.swift:16). `AddedBy` gains `.phone`.
- An album in it is downloaded, partly downloaded, or on its way:
  - tiles and rows carry the album's mark in the one slot at the end of the artist line (5.3) - the filled mark,
    the dotted mark, the ring (9 pt, no stop square) or the amber mark - never on the cover, whose top left is the
    New mark's (LibraryTiles.swift:16-18);
  - **every** tile and row here has a third line, footnote, quiet: the tile's line of 2.3 - "12 songs", "3 of 12
    songs", "Downloading", "Waiting", amber "Didn't download". Every tile, not only the partial ones, so the grid's
    rows keep one height (LazyVGrid sizes a row by its tallest tile, AlbumsScreen.swift:148-150) - and on the one
    list that is about this phone, the state in words is worth its line.
- **Empty** (offline with nothing downloaded, or the last album removed while it shows): the Library's own empty
  note, as Your albums' is (EmptyLibraryNote, AlbumsScreen.swift:287-301) - **"Nothing downloaded yet."**, and
  quiet under it **"Download an album from its page, and it plays here even when deadwax can't be reached."** Left
  aligned in the list's flow, under the title - not a `ContentUnavailableView`: the app has none, and an empty list
  here reads as Your albums' does.
- Find with no match: LibraryWords' own "No albums match “…”.".
- Core: the list is `AlbumList.downloaded` beside `.scope(AlbumScope)` - **`AlbumScope` itself is left alone**,
  since it names kept files (KeptAlbumIndex.swift:59-62) and Downloaded is never asked of deadwax.
  `AppRoute.downloaded` pushes it.

### 5.2 Where it is reached

The Library root's top group (AlbumsScreen.swift:52-54, `AllMusicRow` :247-272) gains a second row, under its own
header, for everyone - logins off and the break-glass admin included:

```
All music                      (with a library of your own, as now)
  [square.stack]        All albums          ›
On this phone
  [arrow.down.circle]   Downloaded      12  ›
```

- Shown once anything is downloaded, on its way, or failed - never as an empty row for someone who only streams.
- The count is albums, `.monospacedDigit()`, quiet. Hidden while finding, as All music is.
- Drawn as All music's row is (the header in `.title3.weight(.semibold)`, the accent mark, the chevron, the divider),
  so the two groups read as one list of places - as Apple Music's Library lists Downloaded among its own.
- The same row sits under the Navidrome gate's buttons when the gate is closed while deadwax answers (5.4).

### 5.3 Marks on every Albums screen

LibraryTile and LibraryRow (`ios/App/Library/LibraryTiles.swift:6-80`): an album with a state carries its mark at
`.caption2`, quiet (amber for failed), at the end of its artist line - where Apple Music puts it in its Library's
grid: `arrow.down.circle.fill` for downloaded and partly downloaded (one mark; their difference is in the words),
the dotted mark while waiting, the ring while downloading, amber `exclamationmark.circle.fill` for didn't.

- The mark sits **outside** the artist's `Text`, in an `HStack(spacing: 4)` with it, `fixedSize`, so a long artist
  truncates before the mark rather than taking it with it (the tile's lines are `lineLimit(1)`, :27).
- VoiceOver: the tile's words (`LibraryTile.spoken`, :38) gain the state after the artist, before "New in your
  library": **"Downloaded"**, **"Partly downloaded"**, **"Downloading"**, **"Waiting to download"**, **"Didn't
  download"** - and, dimmed offline, **"Not on this phone"**.

### 5.4 Offline

- **The root shows Downloaded** in place of Your albums (or Albums): the plan's "Downloaded filter on by itself".
  LibraryView already swaps its root by scope with its own scroll and Find (`.id(library.scope)`,
  LibraryView.swift:45-47), so this is one more case of it.
- **The root never swaps under a finger** (Core's `LibraryRoot.shown`, pure): it changes only while the root isn't
  on screen - another tab chosen, a page pushed over it, the app in the background - and the app opening while
  deadwax can't be reached starts on Downloaded. While the root is on screen when deadwax goes away, it stays the
  list it was, with every album not on the phone dimmed (the next bullet's look), and the banner comes; it becomes
  Downloaded the next time it is shown. Coming back is the same rule the other way: Downloaded stays until the
  root is next shown, its top row (below) then reading plainly **"Your albums"**, so one tap takes you there. And
  Reachability changes no more often than its probe (7.1), so a WireGuard blip moves nothing at all.
- The root's top group, while it is Downloaded, holds one row: **"Your albums"** (**"All albums"** without a
  library of your own), with **"Only downloaded albums play until deadwax is back."** under it, footnote, quiet,
  while deadwax can't be reached. It opens the kept list (Phase 1's, drawn from disk, notes/ios.md "The Library
  (p1/app-library)") with every album not on the phone at `Palette.off`, disabled (VoiceOver "dimmed", and **"Not on
  this phone"** in its words). A partly downloaded album isn't dimmed: some of it plays.
- **"Couldn't update this list - showing it as it was."** (RefreshProblemNote, AlbumsScreen.swift:60-62,303-320) is
  not drawn while deadwax can't be reached: the banner says it once for every screen, and a box with its own Try
  again on each list would say it twice. It is drawn as now for a failure while deadwax answers.
- **The Navidrome gate** (LibraryView.swift:43-55, NavidromeGate): a check that fails because deadwax didn't answer
  (`Checked.offline`) closes the Library today - "Your music isn't available right now", with no way to what is on
  the phone. So:
  - while deadwax can't be reached the gate isn't consulted - the root is the list above - and its check runs
    again when deadwax answers;
  - when deadwax answers but its Navidrome doesn't (the gate closed, online), the gate's screen gains the Downloaded
    row (5.2) under its buttons, whenever anything is on the phone: the songs on the phone play from the phone, and
    Navidrome being down is no reason to hide them.
- Their covers: a downloaded album's from the phone (8.8); any other's only if the in-memory cover cache still has
  it, else the empty square (Open question 13).

## 6. You > Downloads

### 6.1 Its row in You

YouView (`ios/App/You/YouView.swift:34-39`) gains a section between Playback and Account: one `NavigationLink`
(`AppRoute.downloads`), **"Downloads"**, its value the bytes on the phone ("2.1 GB", `Bytes.words`; nothing at
all when none), and a footer only while something is happening: **"Downloading - 6 songs to go"**, the first wait
("Waiting for Wi-Fi"), or, amber, **"2 songs didn't download"**. Kept to one line, so You stays calm.

You > Account's footnote (`DeadwaxCore/SignInRules.swift:195`, screens.md 3's "Signing out ends this device's
session and stops what's playing.") gains, when anything is on the phone, **" Your downloads stay on this phone
for when you sign in again."** - Sign out is where someone wonders, and the Downloads screen's own footer (6.2) is a
screen away.

### 6.2 The screen, top to bottom

An inset-grouped `List`, title **"Downloads"**:

1. **Storage** (6.3) - what's used, the bar, and the **Storage limit** under it: the limit is shown with what's
   used now by sitting beside it.
2. **Download over** (6.4) - its two choices, with the network in use now under them.
3. **Downloading** - only while something waits or fetches (6.5).
4. **Didn't download** - only when something failed (6.5).
5. **Downloaded** - every album with a song on the phone, largest first (6.6).
6. **Remove All Downloads** (6.7).
7. The screen's last footer: **"Closing deadwax from the app switcher stops downloads until you open it again;
   locking the phone doesn't. Downloads stay on this phone when you sign out."**

With nothing downloaded, waiting or failed, 3-6 give way to one section, **Downloaded**, holding one quiet row:
**"Nothing downloaded yet."** and under it **"Download an album from its page, and it plays here even when deadwax
can't be reached."** - the Library's own empty words (5.1), drawn as a list row is, not a `ContentUnavailableView`
(the app has none; its empty states are lines, AlbumsScreen.swift:287-335). The settings stay above it: they are
chosen before the first download. The last footer stays too.

**When the store can't be read** (the database won't open: a full disk at its migration, a damaged file): downloads
are off for this launch, nothing is deleted, and the screen holds, under Storage, **"This phone couldn't read its
downloads - close deadwax from the app switcher and open it again."** - for `seesDetail` with SQLite's own words
under "For whoever runs deadwax" (ErrorNote's split). The You row's value is "…" and its footer says the same in
amber. What was downloaded plays from the stream meanwhile.

### 6.3 Storage - what's used, and the limit

The section's first row, drawn as iOS's own iPhone Storage draws a total:

- **"2.1 GB"** in `.title2.bold()` (as You's own headline, YouView.swift:59), then **"of 20 GB"** in quiet (with No
  limit: **"downloaded"**) - one `Text`, so at the largest sizes it wraps as a sentence.
- The bar (1.4's, full width): the fill is downloads over the limit; with No limit, over the downloads plus the
  phone's free space.
- **"12 albums · 148 songs · 41.2 GB free on this phone"**, footnote, quiet.
- Over the limit (the limit lowered below what's here): the fill is amber and full, and the line, amber: **"More
  than the 10 GB limit - nothing is removed for it, but new downloads wait for room."**
- Nothing here yet: **"Nothing downloaded yet"** in its place (headline), the bar empty, and the free-space line.
- VoiceOver: one element, label "Downloads", value "2.1 GB of 20 GB used, 41.2 GB free on this phone".

"Used" is the songs' bytes and their covers', as the planner counts them (8.5).

The second row, **Storage limit** (binding): a `Picker` in the menu style (a grouped list's default, as iOS's own
Settings draws a choice of many) - **"5 GB"**, **"10 GB"**, **"20 GB"** (the default), **"50 GB"**, **"100 GB"**,
**"No limit"** - its choice on the right. What's used now is the row above it, so the row needs no line of its own
(two lines saying "2.1 GB" one above the other would be one too many).

- With other accounts' downloads on this phone (8.1), a third row: **"Other accounts on this phone"**, its value
  their bytes ("1.2 GB"), and a borderless **"Remove"**, which asks first (its `confirmationDialog` from the button,
  as Remove All's): **"Remove other accounts' downloads?"** / **"1.2 GB of music downloaded by other accounts goes
  from this phone. They can download it again when they sign in."** / **"Remove"** (destructive). It deletes
  someone else's, so it asks.
- The section's footer: **"The storage limit is what downloads may take - songs kept from streaming (up to 2 GB) are
  apart from it."**

### 6.4 Download over (binding)

Drawn **as Normalization is** (PlaybackSection.swift:25-65, You's one other setting): a section headed **"Download
over"**, one row per choice - its name, its note under it in footnote quiet, a checkmark on the chosen one in the
accent - a radio group for VoiceOver (each choice's name, "selected", its note as the hint). Two choices whose
difference needs saying are read best with both in view, as iOS's Photos settings show their two; a menu would hide
the second.

- **"Wi-Fi only"** (the default) - **"Downloads use Wi-Fi alone - never mobile data, a hotspot or Low Data Mode."**
- **"Wi-Fi and cellular"** - **"Downloads use mobile data too, whenever there's no Wi-Fi."**

The section's footer: first **what's used now** (James's binding), from NWPathMonitor (7.1) - amber while
something waits for it - then **"These are kept on this phone."** (as `YouWords.kept` is, Normalization's footer):

| now | Wi-Fi only | Wi-Fi and cellular |
| --- | --- | --- |
| on Wi-Fi | "On Wi-Fi now." | "On Wi-Fi now." |
| on mobile data | **"On mobile data now - downloads wait for Wi-Fi."** | "On mobile data now - downloads use it." |
| on a phone's hotspot | "On a hotspot now - downloads wait until you're off it." | "On a hotspot now - downloads use it." |
| Low Data Mode | "Low Data Mode is on - downloads wait until it's off." | "Low Data Mode is on - downloads use it." |
| no network | "No connection now." | "No connection now." |

- Both settings are kept per device in UserDefaults (`downloadOver`: `wifi` | `any`; `storageLimit`: `5` | `10` |
  `20` | `50` | `100` | `none`), as Normalization is. GB here is 1,000,000,000 bytes, as iOS's Storage counts them
  (and as StreamCache's limit is, StreamCache.swift:22).
- A change applies at once: tasks waiting or running are made again under it (8.3), and the planner runs (8.5).
  Raising the limit starts what waited for room; lowering it removes nothing (Choice 19: hand downloads are never
  evicted) - it says what doesn't fit (6.3's amber line).
- VoiceOver: Storage limit reads "Storage limit, 20 GB, pop-up button" with the usage row read just before it;
  Download over's choices as Normalization's, and the footer's line after them.

### 6.5 Downloading, and Didn't download

**Downloading** (header), a row per album with something asked for, in the order asked:

- the cover (44 pt, `@ScaledMetric`, from the phone or at 128), the album, the artist;
- **"4 of 12 songs"** - the album page's own count (2.3), of the songs of it asked for - or the wait's words in
  place of it ("Waiting for Wi-Fi"); when all that is asked of the album is one song, **the song's title** instead
  ("Roads") - never "1 of 1 song";
- while fetching, the bar (1.4) under it, the album's fraction;
- a tap opens the album's page, as a Downloaded row's does (6.6);
- a swipe: **"Remove"** (destructive, `trash`) - the album's Remove Download; VoiceOver has it as an action.
- Footer, when it applies: all waiting for Wi-Fi -> **"Downloads wait for Wi-Fi - Download over is set to Wi-Fi
  only."**; after a force quit -> **"Downloads stopped when deadwax was closed from the app switcher, and carried on
  when it opened again."** (shown until the downloads it names have finished, or a day).

**Didn't download** (header), a row per album with failed songs:

- the cover, the album, and amber with its mark: **"2 songs didn't download"**; under it the first reason (2.4)
  and its advice, quiet; for `seesDetail` the raw words (status, the transport's code) under "For whoever runs
  deadwax" - ErrorNote itself (`ios/App/Shared/ErrorNote.swift`), so the split is the app's one;
- a trailing **"Try again"** (borderless): its songs asked for afresh, tries from 0;
- a swipe: **"Remove"** - its songs no longer asked for;
- with more than one row, a last row of its own, **"Try all again"** (accent, leading) - a row, not a button in the
  footer: a footer is read as a note, and VoiceOver reaches a row in the list's order.

### 6.6 Downloaded

**Downloaded** (header), every album with a song on the phone, **largest first** - the order iOS's own storage lists
keep (Settings > General > iPhone Storage), since this screen is where space is made; browsing by name is the
Library's Downloaded (5.1). Each row:

- the cover, the album, the artist;
- **"12 songs · 412 MB"**, or **"3 of 12 songs · 92 MB"**;
- trailing, the album's check: **"Checked"** with `checkmark.circle`, `Palette.held`, when every song is `matched`
  or checked by size where that is all a file allows (an MP3); **"Checked by size"**, quiet, when a FLAC carries no
  sound fingerprint (8.4); **"Checking…"**, quiet, while any is `unchecked`. At accessibility sizes it moves under
  the size line, leading (`typeSize.isAccessibilitySize`, as TrackRow reads it), so the title never shares a line
  with it;
- a tap opens the album's page (pushed on You's stack, `navigation.open(.album(...))`); a swipe: **"Remove"**.
- The section's footer: **"Each song is checked once it's here: its size against deadwax's file, and a FLAC's sound
  against the fingerprint it carries. A song plays before its check is done."**

Rows are albums, not songs: the app is album-shaped, and an album's page shows its songs one by one.

### 6.7 Remove All Downloads

The last section: one destructive button, **"Remove All Downloads"**, centred. Its `confirmationDialog` is attached
to the button itself, so it comes up from it (notes/ios.md "The ••• menus open from the •••"):

- title **"Remove all downloads?"** (`titleVisibility: .visible`);
- message **"148 songs (2.1 GB) go from this phone. They stay in the collection, and you can download them
  again."**;
- **"Remove All Downloads"** (destructive), and the system's Cancel.

It stops everything waiting or fetching too, and deletes the files, covers and kept albums; plays and queue saves
not yet sent are kept (they aren't downloads). Afterwards the screen is its empty state, announced as "Removed all
downloads". Removing one album needs no confirmation (6.5, 6.6, 3.4): it can be downloaded again, and two taps -
the menu, then the item - stand in for one. Remove All is the one that can cost hours of Wi-Fi.

### 6.8 Dynamic Type and VoiceOver on the screen

- Rows keep the cover at the leading edge and let every line wrap at accessibility sizes (no `lineLimit` there),
  as TrackRow does; the bar stays under the text.
- Each album row is one element: "Dummy, Portishead, 12 songs, 412 MB, Checked"; a Downloading row "Dummy,
  Portishead, 4 of 12 songs, 40 percent" (`.updatesFrequently`); with Remove (and Try again) as actions.
- Download over's choices read as Normalization's do: "Wi-Fi only, selected", its note as the hint; the footer's
  "On mobile data now - downloads wait for Wi-Fi." after them.

### 6.9 Debug (an admin's)

You > Debug gains **Downloads**: the songs by state and their bytes; the session's tasks (running, waiting, with
resume data); the reachability state, the path's facts (Wi-Fi, cellular, expensive, constrained) and the last
probe; plays and queue saves waiting to be sent; the last 50 download events in a ring, as the engine log keeps its
lines; **the time each check took** (the plan's R9: "Debug shows the time per check", "If heavy, check only while
charging"); and **"Stream even when downloaded"** - Phase 0's Streamed/Downloaded switch, kept as the admin's A/B.
"Download all 10" and "Remove the downloads" on the test songs now ask DownloadModel, as the album page does.

## 7. Offline

### 7.1 How the app knows (`Reachability`, App, over Core's `OfflineRule`)

- **The phone's network**: `NWPathMonitor` - `status`, `usesInterfaceType(.wifi / .cellular)`, `isExpensive`,
  `isConstrained`. `unsatisfied` is offline at once: no request is tried.
- **deadwax**: a request that fails with no HTTP answer (`APIFailure` `.offline` or `.timeout` -
  notes/ios.md "The API, models and errors in the listener's words") sets off a **probe**, `GET /deadwax/health`
  with a 3 s timeout. Any HTTP answer is deadwax reached - a 503 from a stopped poller included (app.py:496-516
  answers 503 then, and the plays and files still flow). Two failures in a row (the request and its probe) make
  deadwax **unreachable**; the probe then runs every 30 s, and at once whenever the path changes (Wi-Fi joined,
  WireGuard up) or a list is pulled. One answer makes it **reachable** again.
- So there are three states: `online`, `noNetwork`, `unreachable`. The rule is pure (Core: path facts, results and
  times in, the state and the next probe out) and tested on Linux; the monitor, the probe and the timer are the
  App's.
- While not `online`, nothing that needs deadwax is asked: no level reads (7.3), no stream, no /me loop. Each
  model asks again when it comes back.

### 7.2 The banner

A slim strip **at the top of each page, just under its navigation bar**, pinned there as the page scrolls:
`OfflineBanner`, applied by one modifier, `showsOfflineBanner()` - a `.safeAreaInset(edge: .top, spacing: 0)` on
**the page's own content** - beside the inset round's `clearsPlayer()`, in the same two places: TabStack's roots and
`appRoutes()` (Routes.swift:129), so every page has it, root or pushed.

- **Never on the NavigationStack.** An inset on the stack doesn't reach the pages inside it - the lesson of the mini
  player covering the last row (ios `ae2fe30`, FB23732628) - and above the navigation bar it would sit where iOS
  draws its own call and recording pills, pushing the large title down. On the page, under the bar (and under the
  Library's Find field, `.searchable`'s drawer), it is where an app's own "no connection" strip is expected.
- Its look: `Palette.amber` words, footnote semibold, its mark in front, on `Palette.amberFill` laid **over the
  bar's own material** (`.background(.bar)` under the fill - as the New mark lays its tint over a solid,
  LibraryTiles.swift:90-95): a page's content scrolls up under the inset, and a 14% fill alone would let it show
  through. An `amberEdge` hairline at its foot. 6 pt above and below, the page's side margins. One line; two at
  the larger sizes, the text capped at `accessibility2` (`dynamicTypeSize(...)`, as the Library's index is capped,
  AlbumsScreen.swift:81) - a pinned strip must leave the page room.
  - no network: `wifi.slash` **"Offline - showing what's on this phone"** (the plan's words);
  - deadwax unreachable: `wifi.exclamationmark` **"Can't reach deadwax - showing what's on this phone"**.
- It is a button: a tap opens it to a second line and a button (and closes it again) -
  - no network: **"Turn off Airplane Mode or join a network to play what isn't on this phone."**;
  - unreachable: **"Check you're on the right network (or your VPN is on)."** (`ErrorWords.unreached`'s own advice,
    ErrorWords.swift:420, its "and try again" being the button) and **"Try again"** (borderless, amber), which
    probes at once - **"Trying…"** and dimmed while it asks (3 s at worst), as Sign in says "Signing in…".
  - VoiceOver: one button, its words the line, its value "Shows more" / "Showing more" as it is closed or open;
    Try again its own button once open.
- It slides down in and up out (`.move(edge: .top)` with opacity; opacity alone with Reduce Motion), and is
  announced as it comes; as it goes, VoiceOver hears **"Back online"**. Nothing is drawn for coming back.
- **Why the top**: the bottom is the notice's and the mini player's (MainTabs.swift:40-58), and they say what just
  happened; the banner says how things are, and stays. Apart, they never stack or cover the last row. Now Playing
  covers it, and needs nothing from it: the music plays either way.

### 7.3 What plays

- **A downloaded copy always**, online or not (8.7).
- **Gapless and normalized the same**: a downloaded copy is the file, and plays through the same `FileSource`
  (`DeadwaxAudio/PCMSource.swift:83-122`) a complete stream-cache copy already does, at the same level: the album's
  loudness answer is kept with the download (8.2) and put on the loudness shelf for the queue's albums as the queue
  starts, marked old (`fetchedAt` 0). Online, it is read again first as any answer not fresh is
  (`LoudnessAsking.fresh`, LevelDecision.swift:237; `believed`, PlayerWiring.swift:92). Offline, LoudnessBook
  doesn't ask, and marks the read failed at once - so `LevelWait.shouldWait(readFailed: true)` ends the wait
  (PlayerWiring.swift:102-103) and the entry is decided from the kept answer in hand (PlayerModel+Engine.swift:
  262-284, "once the wait is over, decided from what is in hand"). No rule changes; Info says the same level
  offline as online.
- **The queue**: a song not on the phone, met while not `online`, is passed over at once - its open throws, and
  `PlayerWords.afterEngineFailure` (PlayerWiring.swift:114) gains `notOnPhone`: skip, no 1.5 s retry. Its notice:
  **"Skipped "Roads" - it isn't on this phone"**, and for a run of them within the notice's 5 s, **"Skipped 3 songs
  that aren't on this phone"** - the plan's "one line saying how many". A play started offline never meets one: the
  album page and Downloaded queue only what is here (3.7).
- **Nothing left that is here**: when every song still to come is off the phone (or the one tapped in Up Next is - a
  tap made just as deadwax went away, since offline 4.3.1 makes those rows no button),
  the player stops on the first of them, paused, its cover and title shown, its line - the mini player's second line
  and Now Playing's error line, where Phase 1's playback errors go (screens.md 6) - **"Not on this phone - it plays
  once deadwax is back."** Play then tries it again: from the stream if deadwax answers, else the same line. The
  queue is kept as it is.
- No prefetch for a song on the phone, and none at all offline.

### 7.4 What's dimmed and what's hidden (`Palette.off`, disabled, VoiceOver "dimmed")

| where | offline |
| --- | --- |
| Library root | Downloaded in place of your albums, swapped only while the root isn't on screen (5.4); "Couldn't update this list" not drawn; the Navidrome gate not consulted |
| Your albums / All albums (from the root's row, or the root not yet swapped) | albums not on the phone dimmed |
| an album page | songs not on the phone dimmed; Play and Shuffle take only what's here; mine block hidden; an album with nothing here says so in place of its songs (3.7) |
| the ••• menus | Play Next / Play Last hidden for a song not here; Download stays (it waits) |
| Up Next | songs not on the phone dimmed, and not buttons out of Edit; in Edit their minus and handle still work; the song playing's card never dimmed (4.3.1) |
| Now Playing, the mini player, the lock screen | unchanged, but for the line when nothing left is here (7.3) |
| Info | what it has; rows that need deadwax keep their "…"; Plays from says "This phone - …" (4.4) |
| You | unchanged; /me's failure is said as now ("a failed ask after a good one keeps the version", screens.md:505) |
| You > Downloads | all of it works; downloads wait for a connection, or for deadwax |
| Search, Get, Requests | not in the app yet; their phases say they need deadwax |

### 7.5 The app opening with no network

- Today the launch waits for `/me` and shows the can't-reach screen when nothing answers (ServerModel.check,
  `ios/App/Models/ServerModel.swift:115-142`; RootView's `.checking` spinner) - up to 8 s of spinner on a plane
  (URLSessionTransport's 8 s), then a dead end.
- **Phase 2**: every good `/me` answer is kept (`Application Support/deadwax/<server>/me.json`, per server, beside
  the album index). At launch, with an address, a kept `Me`, and a session in the Keychain (or logins off), the app
  is `.ready` **at once** from the kept `Me`, and `/me` is asked behind it:
  - 200 -> taken as now;
  - 401 -> the sign-in over the app, the music playing on (the mid-use rule, screens.md 1's launch order, step 3);
  - no answer -> the app stays, Reachability hears the failure, and the banner shows.
- The can't-reach screen (D10) stays for a phone that has never had a `Me` from this address.
- So in Airplane Mode the app opens straight onto the banner and Downloaded: the Library from disk (Phase 1 already
  draws the kept list before asking), the albums and covers from the download store.
- The queue: the last queue this phone saved or took is kept (7.6) and put back, paused, as resume does from
  deadwax; offline its songs not here are dimmed in the album pages and passed over as they come (7.3).

### 7.6 Plays and queue saves kept, and sent later

- **Plays**: PlayReporter drops a failed send today (`ios/App/Models/PlayReporter.swift:60-64`; plays-words.md Open question 4,
  :629: "so Phase 2's `play_pending` is a change in one place"). Phase 2: a **play** (`submission=true`, always with its
  `time`, the moment its listen began) that can't be sent - not `online`, or no HTTP answer - is kept in
  `play_pending` with that time. "Now playing" (`submission=false`) is never kept: it would be stale. When deadwax
  answers again, they are sent **oldest first, one at a time**, each forgotten on a 200; a 401 holds them until
  the same person signs in again (they are in that person's store, below); any other 4xx (a song gone, a refused
  time) drops that one; a 5xx or no answer stops the run until the next. Plays older than Last.fm's 14 days are
  sent too: Navidrome counts them, Last.fm turns them away on its own (Open question 19). Navidrome takes `time`
  (`navidrome.py:701-716` passes it on).
- **Queue saves**: ResumeController already tries again at the next trigger, at most every 30 s
  (`DeadwaxCore/ResumeController.swift:18-25`); Phase 2 keeps **the latest unsent save** on disk too
  (`queue_pending`, one row), so a force quit offline doesn't lose it. At the next open or return, resume's own rule
  runs first - it asks `GET /queue`, and a queue another device saved since wins, as the web's 409 rule has it
  (resume.md Open question 4) - and only then is the kept save sent.
- Both live in the person's download store (8.2), so they are never sent under someone else's sign-in.

## 8. The machinery (for the builders)

### 8.1 Where it lives

```
Application Support/deadwax/<server>/                  (KeptAlbumIndex.safeName(server), KeptAlbumIndex.swift:59-68)
  album-index/...                                      Phase 1's kept lists (unchanged)
  me.json                                              the last /me (7.5)
  downloads/<person>/                                  (safeName(me.user); "local" with logins off)
    downloads.sqlite (+ -wal, -shm)                    the store (8.2)
    music/<song-id>.<suffix>                           the file as served (LocalFiles.name, Formats.swift:55)
    music/<song-id>.<suffix>.part                      a finished task's file until its length is checked
    covers/<cover-id>-1024.<ext>                       one size: album pages, the lock screen, tiles scaled down
Caches/deadwax/stream/...                              the streaming cache (unchanged: its own 2 GB, LRU)
```

- **Application Support, not Caches**: iOS empties Caches under pressure, and downloads must stay (the plan's
  "Storage layout"). The `downloads` folder is `isExcludedFromBackup` (its children with it) - else the music goes
  into iCloud backups.
- **File protection `completeUntilFirstUserAuthentication`**, set on the folder (new files inherit it) and again
  on each file and the database: a locked phone must open the next song and record a finished download in a
  background relaunch. Set explicitly, so a change of default can't turn it off (as SongFiles.swift:168 does).
- **Per person** (Open question 3): another sign-in on the same phone has its own downloads; the first person's
  stay for them. You > Downloads then has a row **"Other accounts on this phone"** with their bytes and **"Remove"**
  (6.3), shown only when there are some. (Logins turned on after downloading with them off is such a case: "local"
  becomes another account.)
- The phase0 folder is deleted once (0.3's first launch).

### 8.2 The store (SQLite, `PRAGMA user_version = 1`, WAL)

```sql
CREATE TABLE album (             -- the album's answer, for every album with a song asked for or here
  id         TEXT PRIMARY KEY,   -- Navidrome's album id
  json       BLOB NOT NULL,      -- GET /navidrome/albums/{id}'s body, as answered
  cover      TEXT,               -- covers/<file>, once kept
  fetched_at INTEGER NOT NULL);  -- ms since 1970
CREATE TABLE loudness (          -- GET /navidrome/loudness/album/{id}, as answered (AlbumLoudness)
  album_id   TEXT PRIMARY KEY,
  json       BLOB NOT NULL,
  algorithm  INTEGER NOT NULL,   -- read again when the server's differs (LoudnessModels.swift:29)
  fetched_at INTEGER NOT NULL);
CREATE TABLE song (              -- one row per song asked for or here
  id            TEXT PRIMARY KEY,
  album_id      TEXT NOT NULL,
  disc INTEGER, track INTEGER,   -- the album's order, for the planner
  format        TEXT NOT NULL,   -- 'raw' | 'mp3' (StreamFormat.format, Formats.swift:11)
  suffix        TEXT NOT NULL,   -- as it arrives (StreamFormat.suffix)
  size_expected INTEGER,         -- Navidrome's size; NULL for a transcode
  state         TEXT NOT NULL,   -- 'wanted' | 'fetching' | 'done' | 'failed'
  wait          TEXT,            -- a waiting reason, while 'wanted' (2.1)
  check_state   TEXT,            -- 'unchecked' | 'matched' | 'by_size', while 'done'
  bytes         INTEGER,         -- the file's length, once done
  flac_rate INTEGER, flac_bits INTEGER, flac_md5 TEXT,   -- STREAMINFO's, for Info and Debug
  tries         INTEGER NOT NULL DEFAULT 0,
  failure       TEXT,            -- the reason, while 'failed' (2.4), as a code
  failure_raw   TEXT,            -- status and transport code, for seesDetail
  task          TEXT,            -- the task's description (8.3) while one is out
  resume        BLOB,            -- resume data, while an interrupted fetch waits
  wanted_at     INTEGER NOT NULL,
  done_at       INTEGER);
CREATE TABLE origin (            -- why a song is wanted; a song with none left is removed
  song_id TEXT NOT NULL,
  origin  TEXT NOT NULL,         -- 'song' | 'album:<id>'; Phase 3 'library'; Phase 4 'playlist:<id>'
  at      INTEGER NOT NULL,
  PRIMARY KEY (song_id, origin));
CREATE TABLE play_pending (id INTEGER PRIMARY KEY, song_id TEXT NOT NULL, time_ms INTEGER NOT NULL);
CREATE TABLE queue_pending (one INTEGER PRIMARY KEY CHECK (one = 1), kind TEXT NOT NULL, body BLOB NOT NULL,
                            kept_at INTEGER NOT NULL);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);    -- 'force_quit_at', the schema's own facts
```

- **Origins**, not one origin column: a song can be wanted by hand, by its album and (Phase 3) by your library at
  once, and the plan's Phase 3 rule - "the songs whose only origin was `library` are deleted" - needs every one.
  Remove Download takes away the origins it was asked through (a song's own and its album's) and deletes the songs
  left with none.
- **Progress is never kept**: it is read from the tasks (`countOfBytesReceived`) - deadwax's own rule for
  Soulseek downloads ("Progress is never persisted: derived from slskd on read", CLAUDE.md) holds here too.
- **SQLite through a `CSQLite` system-library target** (`module CSQLite [system] { header "shim.h"; link
  "sqlite3" }`), used by DeadwaxCore's `DownloadDatabase`: Apple's SDKs carry sqlite3, and Linux gets it from
  `libsqlite3-dev`, so the schema, its migrations and every query are tested on Linux with the rest of Core
  (ios.yml's ubuntu job gains an `apt-get install -y libsqlite3-dev` step if its image lacks it). Package.swift's
  products are unchanged, so check_project.py's linked-products check holds. (Open question 20, for a JSON ledger
  instead.)

### 8.3 The background session (App: `DownloadSession`)

- **One** `URLSessionConfiguration.background(withIdentifier: "net.lizardlounge.deadwax.downloads")`, made at every
  launch so iOS can hand it the events of tasks that ran while the app was gone. Download tasks only;
  `httpMaximumConnectionsPerHost = 3`; `httpShouldSetCookies = false`, cookies never accepted: the session goes as
  each request's own `Cookie:` header, as every request does (HTTP.swift:42-44).
- **The relaunch**: SwiftUI's `.backgroundTask(.urlSession("net.lizardlounge.deadwax.downloads"))` on the
  `WindowGroup` (iOS 16+; `ios/App/DeadwaxApp.swift:35`) stands in for `handleEventsForBackgroundURLSession` - no app
  delegate.
- **Each task's `taskDescription`** is `<server>|<person>|<song id>`, so a completion lands in the right store even
  after someone else signed in.
- **The request**: `Routes.stream` with `format` = `StreamFormat.format(for:)` - `raw`, or `mp3` only for what iOS
  can't decode (Ogg, Opus, WMA), exactly what the stream sends (Formats.swift:7-15). So a downloaded copy is the
  bytes a stream of it would be: the file itself, or the same transcode. `allowsCellularAccess`,
  `allowsExpensiveNetworkAccess` and `allowsConstrainedNetworkAccess` are set **on each request** (false, false,
  false with Wi-Fi only; true with Wi-Fi and cellular), so a change of setting is a new request, not a new session.
- **Order**: an album's cover first (a foreground request: it is small, and the page has it), then its songs in the
  album's order, each task's `priority` stepping down - a part-downloaded album plays from the top. Every task the
  planner lets go (8.5) is made at once, while the app is in front: a task made in the background is treated as
  discretionary by iOS and may wait for power and Wi-Fi. The session itself fetches three at a time
  (`httpMaximumConnectionsPerHost`); a task out with no byte yet is `waiting(queued)`, and becomes `fetching` with
  its first byte - so "three at a time" is the session's, not the planner's, and the two never disagree.
- **A task that finishes**: `didFinishDownloadingTo` moves the file to `music/<name>.part` before it returns (the
  system deletes it after), and then the store is told. A status other than 200 (206 for a resumed task) is a
  failure, whatever the body: a background download "succeeds" with an error page.
- **A task that fails** with resume data keeps it in `song.resume` and is made again from it. A failure counts as a
  **try** only when deadwax answered since the task began: one that failed because deadwax went away is a `deadwax`
  (or `connection`) wait, made again when it answers, and a 401 is a `signIn` wait, made again - from the start,
  since resume data carries the old cookie - once the same person has signed in. Three tries -> `failed` (8.4),
  with the last reason. Failed songs get one more try at the app's next launch (Phase 3's sync takes this over), and
  any number from "Try again".
- **A setting changed, or the person signing out**: every task out is cancelled `byProducingResumeData`, and made
  again under the new request (or after sign-in).
- **A force quit**: iOS cancels the session's tasks; at the next launch each comes back with
  `NSURLErrorCancelled` and `NSURLErrorBackgroundTaskCancelledReasonKey` = user force-quit, and resume data when it
  can resume (Apple's documentation, as remembered; check 5). The store marks `force_quit_at`, keeps the resume
  data, and makes the tasks again at once - the app is in front - and You says so (6.5).
- **The stream cache first**: a song asked for whose complete copy is in the streaming cache (StreamCache's reuse
  check, StreamCache.swift) is copied in (an APFS clone, at once) and checked as any download, with no task.

### 8.4 The checks

On the phone, a song at a time, whenever the app runs - in front, while playing, or in a background relaunch (each
inside `beginBackgroundTask`) - at utility priority:

1. **The length** (on the `.part`, as it arrives): `LocalFiles.lengthMatches` (Formats.swift:70-73) against
   Navidrome's `size`; a transcode, which has none, any length but 0. A mismatch is deleted and is a try. A match is
   renamed to its own name and is `done(unchecked)` for a FLAC, `done(bySize)` for anything else - **and plays from
   then on** (the plan's "Until checked, a song still plays").
2. **A FLAC's sound**: `FLACStreamInfo.parse` (FLACStreamInfo.swift:23-52) reads STREAMINFO. With `md5Known`
   (:55) and 24 bits or fewer, the file is **decoded once, with the decoder playback uses** - AVAudioFile at its own
   rate in Float32, as FileSource opens it (PCMSource.swift:87-95) - each sample turned back to its integer (exact:
   Float32 holds any 24-bit sample; `x * 2^(bits-1)`), packed little-endian in `(bits + 7) / 8` bytes, channels
   interleaved, and the MD5 of it all compared with STREAMINFO's. This proves the bytes **and** that iOS reads them
   as the encoder meant.
   - equal -> `matched`;
   - different -> deleted, a try ("The copy's sound didn't match the original." after three);
   - an all-zero MD5, or over 24 bits -> `bySize` ("Checked by size");
   - iOS can't open or decode it -> deleted, a try ("This phone couldn't read the copy.").
3. **The loudness** (8.2's `loudness`): copied from the route as the album is asked for, after a warm
   (`POST /level/album/{id}`, whatever Normalization is set to - a person may turn it on later); read again at each
   launch for an album not yet `measured`, or whose `algorithm` isn't the server's.

- A retag on the server rewrites tags, not audio, and keeps the song's id: a copy with old tags plays the right
  sound, and the app shows the kept album's names until it is read again. An audio replacement shows as another
  `size` the next time the album is read (its page, or a launch), and the copy is fetched again (the plan's "When the
  store changes a file").
- **Pure parts in Core**: MD5 (RFC 1321, pure Swift - Linux has no CryptoKit; its own vectors) and the packing
  (`FLACMD5`), so the check is the same everywhere. **The decode in DeadwaxAudio** (`FLACVerifier`, reading only,
  never playing): the one DeadwaxAudio addition.

### 8.5 The planner and the storage limit (Core: `DownloadPlan`, pure)

In: every song asked for (its origins, `wanted_at`, album, order, expected bytes), every song here (bytes), the
limit (bytes, or none), the phone's free space (`volumeAvailableCapacityForImportantUsage`, the App's), the
reachability state and the path's facts, the setting, and the tasks out. Out: which songs to fetch now and why each
other one waits.

- **Units**: an album asked for as an album is planned **whole** - all of its songs not here fit, or the album
  waits - so a download never stops at half an album for room. A song asked for alone is a unit of its own.
- **Order**: by `wanted_at` (the order asked), then disc and track. A unit that doesn't fit waits, and the next is
  tried - one big album never holds up small ones; when room comes, the oldest goes first.
- **Fits** when: bytes here + bytes expected of every unit started + this unit's ≤ the limit; and the phone's free
  space - what the started units have yet to receive - this unit ≥ **2 GB** (the plan's reserve). Expected bytes
  are `size`; a transcode's is its duration at 320 kbps, an upper bound.
- **Nothing is ever evicted in Phase 2**: everything here was asked for by hand, and hand downloads never go by
  themselves (Choice 19). Lowering the limit below what's here makes new units wait `room` and says so (6.3, 3.1) -
  check 6's "it says what didn't fit". Phase 3 adds your library's albums, evicted by order, below these.
- **The waits**, in order: no network -> `connection`; deadwax unreachable -> `deadwax`; signed out -> `signIn`;
  Wi-Fi only on mobile data -> `wifi`; Wi-Fi only on a hotspot (Wi-Fi, expensive) -> `hotspot`; Wi-Fi only in Low
  Data Mode -> `lowData`; over the limit -> `room`; under the reserve -> `phoneFull`. A song the planner lets go is
  `queued` until its task's first byte (8.3).
- Run at every ask, finish, failure, setting change, path change, reachability change and coming to the front.

### 8.6 Sizes in words (Core: `Bytes.words`)

Decimal, as iOS's Storage counts: under 1 GB, whole MB ("412 MB"; "1 MB" for anything above 0 and under it); from 1
GB to under 100 GB, one decimal with a trailing ".0" dropped ("2.1 GB", "20 GB"); 100 GB and over, whole ("128
GB"). Tested on Linux with the edges (999,999,999 bytes, 1 GB exactly, 99.95 GB).

### 8.7 The player prefers a downloaded copy

`makeTracks` (PlayerModel+Engine.swift:184-205): `if let url = downloads.playable(song)` - `done`, whatever its
check - the song opens as `FileSource(url:start:)`; else the stream as now. Debug's "Stream even when
downloaded" turns it off. `keepAndPrefetch` (PlayerModel.swift:779) prefetches nothing for a song on the phone;
`SongFiles.header(of:)` (SongFiles.swift:120) reads the downloaded copy first. **No DeadwaxAudio change is needed
to play one**: it is the path a complete stream-cache copy takes today. Removing a download while it plays is safe
(the open file plays on); the next play streams.

### 8.8 Covers from the phone

`CoverCache.load` (`ios/App/Shared/CoverImage.swift`) looks in the download store for the cover id first, decoding
the kept 1024 down to the size asked (ImageIO's thumbnail, at the size the view gives), and only then asks deadwax.
So the album hero, the Library's tiles of downloaded albums, Now Playing and the lock screen all draw a downloaded
album's cover with no network, through the one cache they share.

### 8.9 Core, and the App

| DeadwaxCore (pure, tested on Linux) | the App (and DeadwaxAudio), tested on the phone |
| --- | --- |
| `DownloadModels` - the states, reasons, origins, checks (2.1) | `DownloadModel` (@MainActor @Observable): each song's and album's state for the views, want/remove/retry in the tap, progress read from the session ~4 times a second while something on screen shows it |
| `DownloadRules` - transitions, tries, the album's state (2.2), the menus' items (2.5), what plays offline | `DownloadSession` - the background URLSession and its delegate, the file moves |
| `DownloadPlan` - the planner (8.5), `StorageLimit`, `DownloadOver` | `DownloadStore` (an actor) - DownloadDatabase and the files: protection, backup, free space |
| `DownloadWords` - every word in this spec | `Reachability` - NWPathMonitor, the probe, its timer |
| `Bytes` (8.6), `FLACMD5` (8.4) | `FLACVerifier` (DeadwaxAudio) - the decode |
| `DownloadDatabase` + `CSQLite` - the schema, migrations, queries (8.2) | `OfflineBanner` and `showsOfflineBanner()` (7.2), `DownloadControl` (the control, the ring, the one mark slot), `DownloadsScreen`, the Library's Downloaded row and root, the gate's Downloaded row |
| `OfflineRule` (7.1), `PendingPlays` (7.6), `AlbumList`, `AddedBy.phone` (5.1), `LibraryRoot.shown` (5.4) | ServerModel's kept `Me` (7.5), PlayReporter's kept plays, LoudnessBook's seeding (7.3) |
| `PlayerWords.afterEngineFailure`'s `notOnPhone`, the skip words and the stopped line (7.3) | Info's Plays from and Debug's On this phone (4.4); the notice announced from `PlayerModel.say`, Now Playing's capsule (4.2) |

New App files go in the synchronized folder with no project change (notes/ios.md "The project without Xcode");
check_project.py must pass. Proposed: `App/Downloads/` (DownloadModel, DownloadSession, DownloadStore,
DownloadControl, DownloadsScreen), `App/Root/OfflineBanner.swift`, `App/Models/Reachability.swift`.

## 9. Tests (Swift Testing; nothing here has a web counterpart, so the cases are this spec's)

**DeadwaxCore** (Linux and macOS):

- `DownloadRules`: every transition of 2.1, including tries (a failure while deadwax was away isn't one), a 401 as
  `signIn`, a force quit's resume; the album's state for each row of 2.2 (and their order: fetching over waiting
  over failed); the menu items of 2.5 for each mix.
- `DownloadPlan`: an album that fits whole, one that doesn't (it waits and a smaller one after it goes), the 2 GB
  reserve, No limit, a limit lowered below what's here (nothing removed, new units wait `room`), a transcode's
  estimate (and its fraction held under 95%), the waits' order - `connection` before `deadwax`, `wifi` on mobile
  data and `hotspot` on an expensive Wi-Fi, neither with Wi-Fi and cellular - and `queued` until a first byte.
- `DownloadWords`: every line of 2.3 (the tile's short lines included), 2.4, 3.7, 4.4, 6 and 7, and none containing
  "Navidrome", "the store", "cache", "sync", "MD5", "offline mode" or "everything" (the vocabulary sim's rule,
  ported for these words); the waits a setting causes name it (3.1).
- `LibraryRoot.shown`: offline at launch -> Downloaded; deadwax going while the root is on screen -> unchanged until
  it is off screen; back while Downloaded is on screen -> unchanged until it is off screen; a blip shorter than the
  probe -> nothing.
- `Bytes`: 8.6's edges. `FLACMD5`: RFC 1321's seven vectors; 16- and 24-bit packing, sign included.
- `DownloadDatabase`: the schema made, a song through every state, origins added and taken (a song with none goes),
  plays kept and given back oldest first, queue_pending's one row, the migration from nothing.
- `OfflineRule`: no network at once; two failures to unreachable; any HTTP answer back; the probe's 30 s and the
  path change's "at once".
- The Navidrome gate (NavidromeGate's own tests, extended): not consulted while not `online`; closed while online
  with something on the phone -> its Downloaded row.
- The Library: `Shelf` over `AlbumList.downloaded` with `AddedBy.phone` - its months, the four other sorts as the
  other lists have them (the existing vectors' rules, new albums).

**DeadwaxAudio** (macOS, offline render):

- `aDownloadedCopyRendersTheSamplesItsStreamDoes`: one FLAC through `FileSource` from a downloads folder and through
  `StreamSource` over its bytes (GrowingBytes, as the tests feed streams) render identical buffers - Off, and at
  -6.02 dB through `GainedSource`.
- `anAlbumOfDownloadedCopiesJoinsSampleExact`: the existing gapless render test over FileSources from the store.
- `theVerifierHashesWhatPlaybackDecodes`: the 16-bit 44.1 kHz and 24-bit 96 kHz fixtures `matched`; one audio byte
  flipped (its FLAC frame CRC fixed up, so it decodes) found not to match (the verifier's answer, never a kept
  state); a zero MD5 `bySize`.
- The fixtures come from `ios/scripts/make-test-album.py`'s own encoder (it writes STREAMINFO's MD5, and
  `tests/test_ios_install.py` checks its files with libsndfile and mutagen), extended to 24-bit; pytest checks the
  fixtures' MD5 against a decode by libsndfile, so the Swift test's "matched" has an independent reference.

## 10. Phase 2's checks (on James's iPhone)

The plan's six, then the design's own. Note what you see for each.

1. **An album, locked.** On Wi-Fi, open an album, tap ⬇ at the top: the dotted mark for a moment, then the ring
   fills, and "Downloading - 0 of 12 songs" appears under the badge, counting up; lock the phone. Unlock later:
   the album says "Downloaded", every row has the grey mark, You > Downloads lists it with "Checked", and Info on
   any of its songs says "Plays from: This phone - checked".
2. **Wi-Fi only.** On mobile data **with WireGuard on** (as away from home), download an album: it says "Waiting for
   Wi-Fi" on the page and in You > Downloads, where Download over's footer says "On mobile data now - downloads wait
   for Wi-Fi." in amber; the control's menu names the setting. Nothing arrives (Settings > Mobile Data shows deadwax
   using nothing more). Choose "Wi-Fi and cellular": it downloads.
3. **Airplane mode.** Turn it on, force-quit deadwax, open it: no spinner and no can't-reach screen - the banner
   "Offline - showing what's on this phone", and the Library showing Downloaded. Play the album: every join
   seamless, and Info's Normalization says the same as it did online. Lock the phone: the lock screen shows the
   song and its cover, and play and pause work there.
4. **Plays, later.** Still offline, play three songs through (each past half its length, or four minutes). Turn
   Airplane Mode off and open the app: within a minute the three are in Navidrome's recently played, at the times
   they were played.
5. **Force quit.** Start a big album downloading, then swipe deadwax away in the app switcher. Open it again:
   Downloads says "Downloads stopped when deadwax was closed from the app switcher, and carried on when it opened
   again.", and the album carries on - from where it stopped (Debug > Downloads shows its resume data) or, if
   Navidrome gave no validator, from its first byte.
6. **The limit.** With more than 5 GB downloaded, set Storage limit to 5 GB: nothing goes, the bar turns amber and
   says "More than the 5 GB limit - nothing is removed for it, but new downloads wait for room."; download one more
   album: it waits, "Waiting for room - the storage limit is reached". Set it back: it downloads.
7. **The marks, beside Apple Music.** An album page: ⬇, the ring, the filled mark; a tap of the ring or the dotted
   mark - its menu's title, on two lines where a setting causes the wait; a song's ••• Download on another album,
   then Remove Download ("Removed from this phone: ..."). Open Apple Music beside it: do the marks read the same
   way? Anything that looks foreign to the phone, note.
8. **Now Playing.** ••• > Download on a song: "Downloading: ..." shows in Now Playing's top row, beside the
   chevron, and nothing else moves. ••• > Download Up Next: "Downloading N songs from Up Next". With VoiceOver on,
   each is heard once. During a library's shuffle, Download Up Next isn't in the menu.
9. **deadwax away, the network not.** On home Wi-Fi with WireGuard off, away from home (or deadwax's container
   stopped): the banner says "Can't reach deadwax - showing what's on this phone"; tap it: Try again. Turn WireGuard
   on: the banner goes within a few seconds (the path changing sets off a probe).
10. **A queue that meets offline.** Queue an album you haven't downloaded after one you have, then go offline as the
    first plays: at its end, "Skipped N songs that aren't on this phone", and the music goes on to what is here -
    or, with nothing here left, stops paused on the first song not here, its line "Not on this phone - it plays once
    deadwax is back."
11. **VoiceOver.** The control ("Download, Downloading, 40 percent"), a row's actions (Download, Remove Download), the
    banner as it appears (and "Shows more" on it) and "Back online" as it goes, You > Downloads' rows and Download
    over's choices (as Normalization's).
12. **The largest text size.** You > Downloads and an album page with marks and its download line: nothing cut off,
    nothing overlapping; the banner two lines at most, the page still usable under it.
13. **Remove All.** You > Downloads > Remove All Downloads: the question comes from the button; after it, the
    Library's Downloaded row is gone and iOS's Settings > General > iPhone Storage > deadwax shows the space back.
14. **A downloaded album opens at once**, online too - no spinner before its songs.
15. **deadwax up, Navidrome down.** With Navidrome's container stopped (deadwax's running): the Library shows its
    "isn't available" screen **with the Downloaded row under it**, and a downloaded album plays from it.
16. **Going offline on the Library.** With Your albums on screen, turn on Airplane Mode: the banner comes and the
    albums not on the phone dim, but the list doesn't change under your finger; switch to You and back: it is
    Downloaded. Turn Airplane Mode off: the banner goes and Downloaded stays until you leave the tab and come back.
17. **The banner under every bar.** On the Library root (with its Find field), an album page and You > Downloads,
    offline: the banner sits under the bar, the list scrolls under it without showing through, and the bar's title
    and buttons are where they always are.
18. **Up Next's marks** (4.3.1). Queue a downloaded album, then Play Last an album that isn't; open Up Next: the
    first album's rows carry the grey filled mark at the end of their line, the second's none. Now Playing's ••• >
    Download Up Next, with Up Next open again: the second album's rows go dotted, then the ring fills, then the filled
    mark - nothing else in the row moves. History's rows are marked the same. With VoiceOver: "Roads, play now,
    Downloaded".
19. **Up Next offline** (4.3.1). Queue a downloaded album and one that isn't, turn on Airplane Mode, open Up Next:
    the second album's rows (and any History rows not on the phone) are dimmed, a tap on one does nothing, VoiceOver
    says "Not on this phone, dimmed"; the song playing's card isn't dimmed. Edit: the dimmed rows' minus and handle
    work; take one out, move one. At the largest text size, the line wraps and the mark sits after it, level with
    its first line, clear of the handle.
20. **The queue kept** (7.5, 7.6). Pause a downloaded album mid-song, close deadwax from the app switcher, turn on
    Airplane Mode, open it: the song is in the mini player, paused at its second, no notice, Up Next as it was. Skip
    to another song, pause, close it again; play something on the Mac for a minute; turn Airplane Mode off and open
    the phone: "Picked up from your Mac" - the Mac's queue, not the phone's offline one. Without the Mac's play, the
    phone's is put back and the web then picks it up ("Picked up from your iPhone").

## 11. What only the phone can tell

- **Nothing has been drawn.** No view of this spec has been seen or heard; every mark, line and menu is checked by
  10's list.
- Whether **a background session's tasks finish while locked** on iOS 27.2 for a free-account app, and how long
  iOS takes to relaunch it to record each.
- Whether **`allowsCellularAccess = false` holds over WireGuard** on mobile data (a VPN's path over cellular) - check 2.
- Whether **a force quit's tasks come back with resume data**, and whether Navidrome's raw stream gives the
  validator resuming needs - check 5.
- **The check's time** for a CD song and a 24/192 song on the iPhone 17 Pro (the plan's R9 says "well under a second"
  for a CD song, unmeasured), and whether it ever stutters playback (it runs at utility priority beside the engine).
- Whether a **pull to refresh or a tap of the banner** while unreachable answers quickly enough to feel like a
  button (3 s at worst).
- Whether the menus' two-line section headers (3.1) and `menuOrder(.fixed)` look as described on 27.2.
- Whether **the bar's glass group** (iOS 26 and later draw a bar's trailing items in one glass capsule) keeps the
  control's colours - the accent arrow, the quiet filled mark, the amber one - or draws them all in the label
  colour, as it may a plain bar button. If it flattens them, the shape alone still carries each state (1.2).
- Whether **a page's own top inset** reaches its List or ScrollView on 17-27 - the same thing the inset round
  assumes for the bottom (its notes: "the pushed-page update is assumed") - check 17.
- Whether a view under a full-screen cover still "appears" - moot once the notice is announced from `say` (4.2).

## Open questions (each with what the build does until James answers)

1. **A format setting?** The plan's table has Download: Original / Up to 48 kHz / MP3 320, but James's answers name
   two settings only. **Recommend: Original only in Phase 2** - the copy is the file, played bit for bit as its
   stream is (audio fidelity first); Up to 48 kHz saves space only on hi-res albums and nothing he can hear on
   AirPods. Revisit if the limit bites.
2. **The streaming cache's own settings** (2 GB, "Keep a stream's copy")? **Recommend: none in Phase 2**; the cache
   stays 2 GB, and the Storage section's footer says it is apart from the limit (6.3).
3. **Downloads per person or per phone?** **Recommend per (server, person)** (8.1): a song another person can't play
   must not play for them offline from someone else's copy (deadwax checks a song is theirs before streaming it,
   `_theirs`, `navidrome.py:133`). For James's one sign-in it changes nothing.
4. **"Download" beside Requests' "Downloading"** (Phase 6). **Recommend keeping Apple Music's word** for the phone -
   it is the one he uses daily - with "this phone" wherever the two could meet, and Requests keeping "Get" and
   its own section names under its own tab.
5. **The ring's tap**: Apple Music stops at once; **recommend a menu** that says how far it has got, with Remove
   Download, so a near miss of the ••• beside it never throws a download away. The stop square stays on the
   control's ring - it still leads to stopping, one tap on - and nowhere else (1.2).
6. **No confirmation for Remove Download** on a song or an album (the menu is the second step); only Remove All
   asks. **Recommend as designed.**
7. **Download and your library are separate.** Apple Music downloads only what is in its library. **Recommend: a
   download never adds to your library, and Remove from my library never removes a download** - "your library" is
   shared with every device (Navidrome favourites), what's on this phone is this phone's. The mine block's "nothing
   was deleted" stays true.
8. **Over the limit**: **recommend waiting, never refusing at the tap and never evicting a hand download** (Choice
   19), said in 6.3 and on the album.
9. **Wi-Fi only also waits out a hotspot and Low Data Mode** (the plan's table: `allowsConstrainedNetworkAccess =
   false`). **Recommend yes** - a hotspot is a phone's data - with Wi-Fi only's own note saying so (6.4), and a
   wait of its own, "Waiting - this Wi-Fi is a hotspot", since "Waiting for Wi-Fi" on a Wi-Fi would read as wrong.
10. **Offline, the Library root becomes Downloaded** rather than a filter chip on Your albums. **Recommend as
    designed**: a filter on Your albums would hide what was downloaded from All albums, which is on the phone just
    the same - and the swap waits until the root isn't on screen, both ways (5.4).
11. **Up Next's rows** (marks, dimming offline) **after the Up Next round merges**, as a small follow-up. **Decided
    and built** in the finishing round: 4.3.1.
12. **A long press on a Library tile** (Download, Remove Download)? **Recommend later**, with Phase 4's Library work:
    a tile's menu needs the album's songs first.
13. **Covers offline for albums not downloaded**: **recommend the empty square** (dimmed anyway); Phase 3 brings
    your library's covers with its albums.
14. **Failed songs** get one more try at each launch, and any number from "Try again". **Recommend as designed**
    until Phase 3's sync.
15. **FLAC over 24 bits** (FLAC 1.4's 32-bit) can't round-trip through Float32: **checked by size**, said "Checked by
    size". Rare.
16. **Copying from the streaming cache** when it holds the song whole (8.3): **recommend yes** - the same bytes, no
    data spent, checked as any download.
17. **A symbol on every menu item**, Play Next and Play Last included (3.4), and Now Playing's Info and Go to album
    (4.1). **Recommend yes** in Phase 2: Apple's menus carry one on each, and the download items need theirs.
18. **Downloaded's "Recently added" means downloaded to this phone.** **Recommend yes** (5.1).
19. **Plays older than 14 days**: **recommend sending them anyway** - Navidrome counts them; Last.fm drops them by
    its own rule.
20. **SQLite or a JSON file?** Phase 1 keeps its lists as JSON files. **Recommend SQLite** (8.2): a state change per
    song would rewrite a ledger of every song (Phase 3: tens of thousands) many times over; SQLite changes a row.
    The cost is the CSQLite target and libsqlite3-dev on Linux.
21. **"Wi-Fi and cellular" or "Wi-Fi and mobile data"?** James named the choice "Wi-Fi and cellular"; his phone's
    Settings say "Mobile Data", and the lines under it say "mobile data" (1.1). **The build uses his words for the
    choice**; one word for both would read better, and it is his to change.
22. **Signed out, with music on the phone.** A 401 brings the sign-in over the app (screens.md 1, step 3), and if
    signing in can't work just then (Navidrome down: a 503), what is on the phone can't be reached behind it.
    **Recommend later**: a "Not now" on the sign-in when this person has downloads, closing it into the banner's
    third state, "Signed out - showing what's on this phone", whose tap brings the sign-in back. **The build keeps
    Phase 1's sign-in as it is** until James says.
