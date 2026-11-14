# Phase 3 - Auto-download your library: what the iPhone app shows and does (app 0.9)

Design spec for the iPhone app's Phase 3 ("Auto-download your library"), read 2026-11-13 at `ios` 305f6a8 (app 0.8 (8),
server 2.1.15). Area: your library followed from deadwax, kept on this phone as far as the storage limit allows, in
step as it changes - the setting, the check and what it does, the order and the eviction, "N of M albums fit", only
while charging, the background - with the phase's checks. Every path is repo-relative and every line number is the
code's at 305f6a8.

**What binds it.** The plan (`~/Desktop/Code/deadwax-ios-plan.md`, outside the repo): James's answers at its top (the
two download settings, binding since Phase 2); its section 4 "Offline" - "The settings" (Auto-download your library:
"Off until chosen (first run asks)"; Only while charging (auto-download): Off), "Auto-download of your library, kept in
step", "Storage limit and eviction", "Background downloads"; section 5's "Phase 3 - Auto-download your library" (its
features and four checks); "Choices made" 15, 17, 18 and 19; section 2's "What the server needs" 3 (the optional
`albums_songs`) and risk R13. Then Phase 2, as built: `notes/ios-specs/phase2-downloads.md` (above all 8.2's store and
origins, 8.5's planner, 6's You > Downloads) and `notes/ios.md` "Phase 2: downloads". Phase 2's downloads, the
per-person store, the origins table, the storage limit and Wi-Fi only already exist: this phase builds on them and
rebuilds none of them.

**Where the words come from.** As Phase 2's: the web has no downloads to a device, so where it has a rule (the
vocabulary, errors in a listener's words) it is followed, and where it has nothing, Apple's own - Apple Music's
"Automatic Downloads" (Settings > Apps > Music, as remembered from iOS 17-18; **not seen here**, there is no
Simulator) and iOS's own Settings for how a switch with a note under it reads.

## 0. The foundation - checked

- **The branch.** `phase3-autodownload`, from `ios` 305f6a8, clean. `src/__init__.py` says `2.1.15`;
  `ios/Config/Base.xcconfig:11-12` say `MARKETING_VERSION = 0.8`, `CURRENT_PROJECT_VERSION = 8`. Phase 3's commits
  leave both alone until its last slice, which makes the app **0.9 (9)** with check_project.py, ios.yml and
  tests/test_ios_install.py pinned with it (as 0.3 to 0.8 were). `__version__` is the server's and never moves here.
- **What "your library" is on the server** (notes/logins.md "Personal libraries"): with logins on, the person's
  Navidrome album stars, listed by `GET /deadwax/navidrome/album_index?scope=yours` (`src/routes/navidrome.py:298`) -
  getAlbumList2 `starred`, read 500 at a time as the asker, newest star first. With logins off, and for the
  break-glass admin, the app's Albums list is the store's (`AlbumScope.albums(for:)`,
  `ios/DeadwaxKit/Sources/DeadwaxCore/LibraryModels.swift:20`) - `scope=store`, newest in the collection first. Phase
  3 follows **the same scope the Library's Albums list shows** (Choice 15): "your library" means on this phone what it
  means on its Library tab.
- **The list's fields** (`INDEX_FIELDS`, navidrome.py:289): `id, name, artist, artistId, coverArt, year, genre,
  created, played, playCount, starred, musicBrainzId, songCount, duration`. **No size**: what an album takes on the
  phone is known only from its songs, so every album of the library is read once (`GET /deadwax/navidrome/albums/{id}`,
  navidrome.py:333) - the plan's R13, measured by slice 1 (2.4).
- **The ETag** is a hash of the body (`json_with_etag`, `src/api/json_etag.py:13`), and the route reads Navidrome
  afresh for every request, so a 304 is a second read of Navidrome that found exactly the same list. It also means
  the list changes whenever anything in it does - `played` and `playCount` included - so for someone listening, most
  checks are a 200 and only a quiet library is a 304. A 200 costs one list and a diff of ids in memory; only albums
  new to the list, or whose `songCount` or `duration` changed, are read again.
- **Add and Remove** (`src/routes/my_library.py:126`, `:230`): Add stars the album as the person at once
  (`_star_now`) - usually: `starred: false` leaves it to deadwax's worker; Remove unstars it and confirms with getAlbum
  before it answers. **deadwax's own read-back** (`src/stars.py`, `SYNC_SECONDS = 300`) re-stars a star lost
  mid-retag within about five minutes - the window a removal's second check must outlast (2.3).
- **Every route Phase 3 needs exists** and is already in the app's `Routes` (`albumIndex`, `album`, `levelAlbum`,
  `loudness`, `stream`, `cover`): `tests/test_ios_contract.py`'s count doesn't move. **No server addition is needed**
  (section 4 names the one that might be, and what decides it).
- **Phase 2's machinery, reused as it is**: the store's `origin` table already reserves `library`
  (`DownloadOrigin.other`, `DownloadModels.swift:136`; phase2-downloads.md 8.2: "Phase 3 'library'"); the planner
  (`DownloadPlan.plan`, `DownloadPlan.swift:139`) plans units and waits; Remove takes origins and deletes a song left
  with none (`DownloadDatabase.removeOrigins`); `DownloadModel` (`ios/App/Downloads/DownloadModel.swift`) opens a
  store per (server, person) and settles it at launch and at the front (`:657`, `:705`).
- **Info.plist** (`ios/Config/Info.plist`): `UIBackgroundModes` is `[audio]`, checked by
  `ios/scripts/check_project.py:271`. The background refresh (2.9) adds `fetch` and `processing` and
  `BGTaskSchedulerPermittedIdentifiers` - Info.plist keys, no entitlement, so a free account is untouched (Choice
  24). SwiftUI's `.backgroundTask(.appRefresh(_:))` is iOS 16+; its `.processingTask(_:)` is **iOS 27.0+** (this Mac's
  SDK, `SwiftUI.swiftinterface`), so the processing task is registered through `BGTaskScheduler` from an app
  delegate adaptor instead, which works from the app's iOS 17.

## 1. Words

### 1.1 The vocabulary

- The web's binding words hold (`ui/test/vocabulary.sim.cjs:5-6`): "your library", "the collection", never "the
  store", "Navidrome", "Browse" or "everything". Phase 2's add "sync", "cache", "MD5", "offline mode" to what a
  listener never reads; "sync" matters most here - a check with deadwax is **"checked"** ("Checked 3 minutes ago").
- **"Download your library"** names the setting with logins on (a library of your own); **"Download the collection"**
  with logins off and for the break-glass admin, whose Albums are the collection's. Sentence case, as "Storage limit"
  and "Download over" are (phase2-downloads.md 6.3, 6.4).
- **"fit"** is the plan's word ("1,240 of 3,010 albums fit in 20 GB"), and the limit is named as the picker names it
  (`StorageLimit.label`). Numbers are grouped by thousands, as the web's `toLocaleString('en-US')`.

### 1.2 Every line (AutoDownloadWords, slice 2; Debug's in slice 1)

| where | line |
| --- | --- |
| the switch (logins on) | **"Download your library"** |
| the switch (logins off, break-glass) | **"Download the collection"** |
| its note, off | "Keeps your library on this phone, newest first, as much as fits in the storage limit - albums you add come by themselves, and albums you remove go." (the collection's: "Keeps the collection on this phone, newest first, as much as fits in the storage limit.") |
| the fit line, all of it | "All 212 albums fit in 20 GB." |
| the fit line, not all | "1,240 of 3,010 albums fit in 20 GB. Raise the limit or download fewer." (the plan's own words) |
| the fit line, No limit | "All 3,010 albums, 1.4 TB." / with the phone short: "1,240 of 3,010 albums fit on this phone." |
| the fit line, the phone short as well | "... - 3 wait for space on this phone." appended |
| reading | "Reading your library - 1,240 of 3,010 albums" (the collection's: "Reading the collection - ...") |
| checked | "Checked just now" / "Checked 3 minutes ago" / "Checked at 14:02" (after an hour) / "Not checked yet" |
| couldn't check | "Couldn't check with deadwax - showing what was there last time." (ErrorWords' advice and, for `seesDetail`, the raw words under it) |
| only while charging | **"Only while charging"** - note: "Your library's albums download only while the phone is charging. Albums you download yourself don't wait." |
| the wait it causes | "Waiting for the phone to charge" (a song's, an album's; tile "Waiting") |
| the empty list's question | "deadwax says your library is empty. Remove the 212 albums downloaded with it from this phone?" - **"Keep Them"** / **"Remove"** (destructive) |
| a large drop's question | "deadwax's list of your library lost 1,240 of 3,010 albums at once. Remove them from this phone?" - **"Keep Them"** / **"Remove"** |
| Downloading's row | **"Your library"** - "38 of 412 albums to go · 12.4 GB" (the bar under it), or its wait ("Waiting for Wi-Fi") |
| an album page, in your library, no room | "Your library doesn't all fit in 20 GB - this one waits for room." |
| an album page, kept off | "You removed this download - your library leaves it off this phone." |
| the control's menu title, a library album here | "Downloaded with your library" |
| Remove from my library, with a library download | the mine block's line gains: "Its download goes from this phone too." (when no song of it was downloaded by hand) |
| Remove All with the switch on | the dialog's message gains: "Download your library is turned off too, or it would download them again." |
| the first ask (3.2) | **"Keep your library on this phone?"** - "deadwax can download your library, newest first, as much as fits in 20 GB, and keep it in step as you add and remove albums." - **"Turn On"** / **"Not Now"** |

Every line is tested (DownloadWords' ban list run over them too, as `DownloadWords.everyLine` is).

## 2. The rules (DeadwaxCore: pure, tested on Linux)

### 2.1 Your library on this phone (`FollowedAlbum`, the store's `library` table)

The phone keeps its own copy of the list - one row per album of your library as deadwax last listed it (the index
entry as it came), its place in that list, its songs as last read (only what the planner needs: id, disc, track,
size, suffix, content type, duration - about 100 bytes a song), when they were read, and three marks: **missing since**
(the first believed list that lacked it), **removed here** (Remove from my library in this app, answered) and **kept
off** (Remove Download on it, 2.7). It is the person's (in their download store, 5) and survives Remove All (it is
not a download), a sign-out and a relaunch.

### 2.2 When it is checked (`LibraryCheck`, `LibraryFollow.due`)

The plan's moments, each a reason:

| reason | due |
| --- | --- |
| `opened` - a store opened: launch, sign-in, another person | always |
| `front` - the app came to the front | when the last check began a minute or more ago |
| `timer` - every minute while the app is alive (in front, or playing in the background) | when the last check began 15 minutes or more ago (the plan's 15 min) |
| `changedHere` - Add to or Remove from my library answered in this app | always, at once (check 4: "acted on at once") |
| `byHand` - Debug's Check now; pull to refresh on You > Downloads | always |
| `background` - BGAppRefreshTask (2.9) | always |
| `back` - deadwax answering again after it couldn't be reached | as `front` |

One check at a time; one asked for while another runs is made once it ends. None while deadwax can't be reached (a
check that can't answer changes nothing anyway), nor while the person must sign in.

### 2.3 What a check does (`LibraryFollow.sync`)

1. `album_index?scope=` with `If-None-Match` - the ETag of the last list this person's store kept for that scope
   (another scope's is never sent).
2. **A 304** is the last list again, read afresh (0). Nothing is added or changed; it can only confirm (step 5). The
   check ends there: one small request.
3. **A 200**: each album in the list and not kept is **added** (in the list's order: newest first); each kept one is
   updated in place - its entry, its place - and **changed** when its `songCount` or `duration` (by more than half a
   second) moved, so its songs are read again; one that was missing and is listed again is **back** (its mark
   cleared), and a `removed here` mark on a listed album is cleared (the Remove didn't take, or it was added again).
4. **Absences, believed only from a whole, plausible list.** A list's absences are **held back** - nothing marked
   missing, nothing confirmed - when:
   - it is **empty** while the phone kept albums (the plan: "An empty list never deletes anything on its own; it is
     shown as a question instead");
   - it would newly miss **more than half of the albums kept, and more than 10** (a Navidrome mid-rescan, a library
     folder unmounted) - asked as the empty list is (open question 5);
   - it is **truncated** (over INDEX_MAX = 10,000, navidrome.py:288): what it left out can't be told from what was
     removed. Not a question - Debug says it.
   A held list is kept as the reason, so a 304 after it is held back too (it is that list again).
5. **Otherwise**, each kept album absent from the list: with **removed here** set, it is **removed** at once (the
   plan: "or a sync and an Add or Remove in the app"); else, newly absent, it is marked **missing** now; already
   missing for **10 minutes or more**, it is **removed** - two checks, at least 10 minutes apart, agree (the plan's "two
   syncs agree"; 10 minutes outlasts deadwax's own five-minute re-star of a star lost mid-retag, 0); missing for less,
   it waits. A 304 confirms exactly as a 200 does.
6. **Removed** albums leave the list; their library downloads go (2.7). **Added** and **changed** ones are read
   (2.4). The fill runs (2.6).
7. **A check that fails** (no answer, a 5xx, a 401) changes nothing: the list as kept stands, its marks unmoved, and
   no clock advances - a removal needs two lists that both answered.

An album whose Navidrome id changes (a re-file renames its folder; Navidrome's ids follow the path) reads as one
removed and one added: its old copies go after the 10 minutes, and it downloads again under its new ids. Accepted -
the song ids change with it, so nothing on the phone could be kept.

### 2.4 Reading each album's songs

- `GET /navidrome/albums/{id}` for every album of the list whose songs aren't kept (or were cleared by a change),
  **in the order of 2.5** - so the albums that fit are read first - **four at a time**. Its songs are kept on the
  album's row (`FollowedSong`); the full answer is not (a 3,000-album library is about 4 MB of rows, where whole
  answers would be about 60 MB) - an album that comes onto the phone has its whole answer kept then, as Phase 2's do
  (`keepAlbum`).
- A missing album isn't read. One that fails isn't asked again until the next check.
- **The first read is the plan's R13**: a 3,000-album library is 3,000 requests once. Debug times it (slice 1); the
  route that would make it one request in 50 is named in section 4, and built only if this time says so.
- An album page opened while the album is in the list refreshes its kept songs from the page's answer (the same
  facts, so no second request): a replaced file's new size reaches the plan without waiting for the index to change.

### 2.5 The order (`LibraryFollow.placedAt`, `ordered`)

The plan: "the library's albums, most recently starred first, with albums played in the last 30 days moved up".
Built as: **each album placed at the later of when it entered your library and when you last played it, a play
counting only within the last 30 days; newest first.** "When it entered" is `starred` for your library (`created`
when Navidrome gave none), `created` for the collection. Ties keep deadwax's own order (Navidrome's: star, then
collection date). Albums with no date at all go last, in deadwax's order.

Why "the later of" rather than a played group above everything (open question 2): a group of everything played this
month above every star would put an album starred today below forty played this month - on a full phone, starring an
album would no longer bring it. Placing each by its latest moment keeps both promises: a new star goes to the top,
and so does what you're listening to.

`played` is Navidrome's per-user date (as the asker, so the person's own plays, from every device - the phone's
included once its plays are sent). An album played from the stream that didn't fit moves up and comes down; the one at
the bottom gives way. That is the intended churn: the phone keeps what you're listening to.

### 2.6 The fill (`LibraryFill.plan`): to the limit, whole albums, never a hand download

In: your library's albums in 2.5's order - each with its bytes (its songs' sizes, a transcode's estimate for what
iOS can't decode, `DownloadRules.expectedBytes`; songs also wanted by hand left out: they are counted as hand
downloads), its bytes on the phone, unread or kept off; and the hand downloads' bytes (here, and to come for the units
Phase 2's planner lets go), the storage limit, the phone's free space and the 2 GB reserve. Out: the albums that fit,
in order; why each other one waits (`room`, `phoneFull`, `unread`, `keptOff`); which albums with songs here must
**give way**; "N of M".

- **Hand downloads first**, whole (Choice 19): their bytes are taken from the limit before any album of the library,
  and they are never given way. A hand download asked for on a full phone makes the library give way from the bottom.
- **Two budgets.** The limit's: the limit less the hand downloads. The phone's: the free space, plus the library's
  bytes already here (they would be given back), less what hand downloads have yet to receive, less 2 GB. Walking the
  order, an album **fits** when its whole bytes fit both what's left of each; it **waits `room`** when it doesn't fit
  the limit's, and the next album is tried (a big album never holds up smaller ones, as Phase 2's planner has it);
  it **waits `phoneFull`** when it fits the limit's but not the phone's - it keeps its place under the limit, so room
  on the phone resumes it without moving anything else.
- **Giving way**: an album with songs here that doesn't fit is evicted **whole** - its library songs' copies deleted,
  the album left in your library and in the fill's order, waiting. Never a song with another origin (2.7). So a lowered
  limit evicts from the bottom (the plan), and so does the phone falling under its 2 GB: the library gives back what
  the phone needs (open question 6). While free space stays above the reserve, nothing here is ever given way for it.
- **Unread** albums (songs not read yet) are skipped, neither fitting nor holding room; **kept off** albums too.
- **"N of M"**: N the albums that fit, M every album of the library (unread and kept off included); the phone-full ones
  said apart. No limit: every album fits the limit's budget, and the phone's alone decides.

### 2.7 How it meets Phase 2's downloads

- **Origin `library`** (`DownloadOrigin.library`, the raw "library" Phase 2 already reads as `.other("library")`): an
  album that fits has its songs asked for under it - a song already asked for by hand gains the origin beside its own.
  Only albums that fit have song rows; the rest live in the `library` table alone, so the store, You > Downloads and the
  Library's Downloaded never carry thousands of waiting rows.
- **The planner** (`DownloadPlan.plan`) gains a second kind of unit: an album of your library, its room already decided
  by the fill - after every hand unit, in the fill's order, under the same shared waits (network, deadwax, sign-in, and
  Only while charging's for library songs alone, 2.8) and the same 100 tasks out. Hand units' fit is checked against
  the hand downloads' bytes alone: library bytes give way to them.
- **Removed from your library** (2.3, or the empty list's Remove): the `library` origin is taken from its songs; a song
  left with none is deleted (Phase 2's `removeOrigins`). A song also downloaded by hand stays (the plan: "A song also
  downloaded by hand, or in a downloaded playlist, stays"; plan open question 4's last: yes).
- **Given way** (2.6): the same, but the album stays in your library, waiting for room.
- **Remove Download on an album of your library** (its page, You > Downloads' swipe): its songs go, hand and library
  origins alike, and the album is **kept off** - the fill skips it until you download it again (open question 7).
  Without that mark it would come straight back at the next check.
- **Download on an album of your library** that waits for room or is kept off: an ordinary hand download (origin
  `album:<id>`), first in the order, never given way; its kept-off mark cleared (open question 8).
- **Remove All Downloads** with the switch on turns the switch off first, and its dialog says so (open question 10);
  the `library` table is kept.
- **The switch turned off**: every `library` origin is taken; songs left with none are deleted; the table stays (an
  instant "N of M" when it is turned on again; checks stop).
- **Covers, loudness and lyrics** of a library album are kept exactly as a hand download's (Phase 2's `keepAlbum`,
  `keepLoudness`, lyrics' 4.7): the album page, the lock screen and Normalization work offline for it.

### 2.8 Only while charging (`DownloadWait.charging`)

- **On**: songs whose only origin is `library` get their tasks only while the phone is charging or full
  (`UIDevice.batteryState`, monitoring on); otherwise they wait **`charging`** (after the shared waits, before room).
  Hand downloads never wait for it.
- **Unplugged while the app runs** (in front, or playing): the library's tasks out are cancelled with their resume data
  kept, and made again from it when it charges. **While the app is suspended** it can't stop a task iOS already has,
  so with the switch on at most **one album's worth** of library tasks (its songs, or 20, whichever is more) is handed
  to iOS at a time: an unplug overnight overruns by one album at most. Each batch's end relaunches the app (the
  background session's event), which hands over the next while it still charges.
- **Plugged in with the app suspended**: a `BGProcessingTask` with `requiresExternalPower` and
  `requiresNetworkConnectivity` (2.9) wakes the app to check and hand over the first batch.
- **Off** (the default, the plan's): library tasks are made as hand ones, up to 100 out (iOS fetches three at a time).

### 2.9 In the background

- **`BGAppRefreshTask`** `net.lizardlounge.deadwax.library` (`UIBackgroundModes: fetch`): asked for at each move to
  the background, not before 15 minutes on (`earliestBeginDate`). It runs a check (`background`) and hands over what
  the fill lets go; iOS gives it about 30 seconds, so the read of new albums' songs stops at 20 and resumes at the next
  chance. iOS decides when, possibly rarely (the plan's words). Only with the switch on.
- **`BGProcessingTask`** `net.lizardlounge.deadwax.charging` (`UIBackgroundModes: processing`): only with Only while
  charging on, asked for when the library has something waiting `charging`.
- Both identifiers in `BGTaskSchedulerPermittedIdentifiers`; registered at launch by `BGTaskScheduler.register` in an
  app delegate adaptor (0: SwiftUI's processing task is iOS 27+). Both run the same `check(.background)` the app does,
  so nothing about the rules differs in the background.
- **A task made in the background is treated by iOS as discretionary** (Phase 2's 8.3): it may wait for power and
  Wi-Fi. That suits the library. The planner otherwise makes everything it lets go while the app is in front.
- **Force quit** stops all of it, as iOS rules (Phase 2's words in You > Downloads already say so).

## 3. The screens (slice 2, but Debug's in slice 1)

### 3.1 You > Downloads: Your library

A section between **Storage** and **Download over** (the library is what fills the storage), headed **"Your library"**
(the collection's: "The collection"):

1. The switch, **"Download your library"** (1.2), its note under it, footnote quiet - drawn as iOS's own Settings draws
   a switch with an explanation.
2. On: **the fit line** (1.2) in body text, amber when not all fit (as 6.3's over-the-limit line); while reading,
   the reading line with the bar (Phase 2's `DownloadBar`, its fill the albums read over M).
3. On: **"Only while charging"**, a switch, its note under it.
4. On: the footer, **"Checked 3 minutes ago"** - or "Couldn't check with deadwax - ..." amber with ErrorNote's split.
5. The empty list's or the drop's question, when held (2.3), as an amber row with its two buttons, Remove asking
   nothing more (the question is the asking).

A pull on the screen checks now (`byHand`). VoiceOver: the switch as iOS reads one ("Download your library, switch
button, off", its note as the hint); the fit line one element.

### 3.2 The first ask

The plan: "Off until chosen (first run asks)". **Recommended (open question 1): a card at the top of the Library's
root, once per phone**, not a dialog at launch - the app opens to music, and a dialog in the way of the first tap is
the wrong moment. The card: the title, its line (1.2) with the current limit, **"Turn On"** (accent) and **"Not
Now"**. Either answer puts it away for good (`autoDownloadAsked` in UserDefaults). Shown only once deadwax answered and
the person has albums to download (a library of their own, or the collection). The setting is in You > Downloads
either way.

### 3.3 Downloading, Downloaded and the Library

- **Downloading** (6.5) gains **one row** for your library while any of its albums is on its way: "Your library",
  "38 of 412 albums to go · 12.4 GB" or its wait, the bar. A tap opens the Library's Downloaded. Hand downloads keep
  their rows; library albums never get rows of their own here.
- **Didn't download** (6.5): a library album with failed songs has its row as any other.
- **Downloaded** (6.6) lists library albums here as any other (largest first); its swipe is Remove Download (2.7).
- **The Library's Downloaded** (5.1) lists a library album once a song of it is here or fetching - never one only
  waiting.

### 3.4 The album page

- A library album here: the control as Phase 2's; its menu's title **"Downloaded with your library"**; Remove Download
  keeps it off (2.7).
- In your library, waiting for room: ⬇ (it isn't asked for), and under the badge, quiet: "Your library doesn't all fit
  in 20 GB - this one waits for room." ⬇ downloads it by hand.
- Kept off: ⬇, and "You removed this download - your library leaves it off this phone."
- The mine block's Remove from my library: its line gains "Its download goes from this phone too." when a library
  download of it is here and no song of it was downloaded by hand.

### 3.5 Debug (an admin's): Your library (slice 1)

A section of its own after Downloads: **Follow your library** (slice 1's switch, off by default, kept per phone - slice
2 replaces it with the real one); what is followed (scope); albums, songs read, missing (pending, with the oldest
mark's time), held (why); the last check (200/304/failed, how long it took, when); **the first read's time** and the
mean per album (R13); **"Would fit"**: the fill's N of M at the current limit and free space, the bytes the fitting
take, the phone-full and unread counts; **Check now**; and the downloads log's library lines.

### 3.6 VoiceOver and Dynamic Type

As Phase 2's 6.8: every line wraps at accessibility sizes; the fit line and the Downloading row are one element each
("Your library, 38 of 412 albums to go, 12.4 GB, 40 percent", `.updatesFrequently`); the card's buttons are its
actions, its title the label.

## 4. The server

**Nothing is needed.** Every route the phase uses exists (0). Two things are named, not built:

- **`GET /deadwax/navidrome/album_songs?ids=a,b,...`** (permission **user**), only if slice 1's measurement (check
  L0a) says the first read over WireGuard takes **more than 10 minutes**. Up to 50 Navidrome album ids, each read with
  getAlbum as the asker (the call is already on the fixed list for `/albums`), answering
  `{"albums": [{"id", "songs": [{"id", "discNumber", "track", "size", "suffix", "contentType", "duration"}]}],
  "missing": [ids]}` - an album that fails is listed in `missing`, never failing the batch. It joins
  `test_there_is_no_general_proxy`'s list, test_logins' ROUTES and test_player_as_you's walk; a 2.1.x patch on main
  with its README, docs and contract test. The phone would then read 50 at a time (60 requests for 3,000 albums).
- Phase 2's strong ETag on the raw relay (should resume data never come) stays as Phase 2 named it.

## 5. The machinery (for the builders)

### 5.1 The store: `PRAGMA user_version = 4` (5 after the review)

```sql
CREATE TABLE library (              -- your library as this phone follows it (2.1)
  album_id      TEXT PRIMARY KEY,   -- Navidrome's album id
  position      INTEGER NOT NULL,   -- its place in deadwax's last list (missing ones after)
  entry         BLOB NOT NULL,      -- the list's entry for it (IndexAlbum's JSON)
  songs         BLOB,               -- its songs as the plan reads them (FollowedSong JSON); NULL until read
  read_at       INTEGER,            -- when they were read (ms)
  missing_since INTEGER,            -- the first believed list without it (ms)
  removed_here  INTEGER,            -- Remove from my library in this app, answered (ms)
  kept_off      INTEGER);           -- Remove Download on it: left off this phone until downloaded again (ms)
-- version 5 (after the review, 6.6):
ALTER TABLE library ADD COLUMN left_songs BLOB;  -- songs a read found had left it: {song id: first read without it}
```

Meta keys: `library_scope`, `library_etag` (the last list's, for that scope), `library_held` (why its absences weren't
believed), `library_checked_at`, and after the review `library_removed` as JSON (each album removed and not yet let
go, with the songs it was last read with). A version-3 file gains the table with every row of the others kept, a
version-4 file the column; `removeAll` leaves it (2.7).

### 5.2 Core, and the App

| DeadwaxCore (pure, Linux) | the App |
| --- | --- |
| `LibraryFollow` (2.2-2.5: `FollowedAlbum`, `FollowedSong`, `sync`, `due`, `placedAt`, `ordered`, `toRead`, `songsChanged`) | `LibraryFollower` (App/Downloads/): the checks and their timer, the reads four at a time, the fill run, Debug's state; owned by DownloadModel, given its store as it opens |
| `LibraryFill` (2.6) | DownloadModel: the hand downloads' bytes for the fill; (slice 2) the library's asks, give-ways and removals |
| `DownloadDatabase` v4 (5.1) | AlbumModel / AlbumView: Add and Remove tell DownloadModel (`changedHere`) |
| `LibraryFollowWords` (Debug's lines), `AutoDownloadWords` (slice 2, 1.2) | DebugView's Your library section; (slice 2) DownloadsScreen's section, the Library's card |
| (slice 2) `DownloadOrigin.library`, `DownloadPlan`'s library units, `AutoDownload` settings | (slice 3) the background tasks, the charging gate |

## 6. The slices

Three, each merged on `ios` and each leaving everything before it working, then the phase's version. Nothing in
DeadwaxAudio changes in any of them. **No Simulator anywhere**: Core on Linux and macOS, the App's build on this Mac and
ios.yml's runner, the rest on James's phone.

### 6.1 Slice 1 - following your library, read-only (Core, and Debug)

- **Core**: `LibraryFollow.swift` (2.1-2.5), `LibraryFill.swift` (2.6), `LibraryFollowWords` (Debug's lines),
  `DownloadDatabase` version 4 (5.1), `StreamFormat.format(suffix:contentType:)` (so a `FollowedSong` is planned as its
  stream is fetched).
- **App**: `LibraryFollower` - checks at `opened`, `front`, `timer`, `changedHere`, `byHand` and `back` (2.2), the reads
  (2.4), the fill for Debug at the current limit and free space; DownloadModel opens and closes it with the store;
  AlbumView tells it of an Add or a Remove; DebugView's **Your library** (3.5), with its own switch, off by default.
- **Nothing downloads and nothing is deleted** - no origin is written, the planner is untouched. It exists to prove
  the rules against James's real library and to **measure the first read** (R13) before anything depends on it.
- **Checks**: L0a-L0g (8.1).

### 6.2 Slice 2 - downloading it (Core, and the screens)

- **Core**: `DownloadOrigin.library`; `DownloadPlan` with library units (2.7); `AutoDownload` (the two switches,
  their keys - `autoDownloadLibrary`, `autoDownloadOnlyWhileCharging`, `autoDownloadAsked` - per phone, as Download
  over and the limit are, applying to whoever is signed in: open question 13); `AutoDownloadWords` (1.2); the
  question's answers; what Remove Download, Download, Remove All and the switch do to origins and marks (2.7).
- **App**: the follower acts - fits asked for under `library`, give-ways and removals deleted, kept off, the switch
  replacing Debug's; You > Downloads' section (3.1); the Library's card (3.2); Downloading's row, Downloaded and the
  Library's lists (3.3); the album page's lines and menu (3.4); the mine block's line.
- **Checks**: the phase's 50-53 and 55-60 (8.2).

### 6.3 Slice 3 - only while charging, and in the background (app 0.9)

- **Core**: `DownloadWait.charging`, its place in the waits; the batch rule (2.8).
- **App**: the charging gate and the unplug's cancel; `BGAppRefreshTask` and `BGProcessingTask` registered through an
  app delegate adaptor, asked for at each move to the background; Info.plist's `fetch`, `processing` and
  `BGTaskSchedulerPermittedIdentifiers`, check_project.py checking them (and still `audio`).
- **The app's version: 0.9 (9)**, with check_project.py, ios.yml, tests/test_ios_install.py, ios/README.md and
  docs/ios.md.
- **Checks**: 54 and 61-63 (8.2).

### 6.4 Slice 1, built (2026-11-13)

Written up in notes/ios.md, "Phase 3, slice 1: following your library (read-only)". What the build decided where
this spec was silent, each kept for slices 2 and 3 unless James says otherwise:

- **Another scope** (logins switched on or off under the same store): the kept list is the other scope's, so its
  absences say nothing - the library is forgotten and followed afresh, its ETag with it.
- **A missing album stays in the fill** until removed: it is in your library until two checks agree.
- **An unread album's bytes here aren't the phone's to give** (2.6): it is never given way while its songs are read
  again, so they aren't counted as room.
- **A play dated ahead of now counts as now** (2.5) - a server clock a little ahead shouldn't drop a play.
- **The album page refreshing an album's kept songs** (2.4's last point) waits for slice 2, where it matters (in
  slice 1 nothing is planned from the songs). Built after the review (6.6), with a weekly re-read.

### 6.5 Slice 2, built (2026-11-13)

Written up in notes/ios.md, "Phase 3, slice 2: downloading your library". Open questions 1-10, 12, 13 and 15 are built
as recommended (11 is slice 3's; 14 waits for L0a). What the build decided, or did differently:

- **Remove on the question (2.3) doesn't act on that list.** It makes the next checks believe a held list
  (`believing`, kept in meta), whose absences are marked missing and removed only by a second check 10 minutes or
  more on - the same rule as any removal. A list that isn't held ends it. Keep Them keeps everything and puts the
  question away until a list isn't held again.
- **Removed here** (open question 9) goes when the next list confirms it - a check is made as soon as Remove from my
  library answers.
- **Another scope** now drops only the ETag, not the list (6.4's first point is replaced): the drop rule judges the
  next list, so a scope change that empties it is held.
- **Nothing new is asked from a kept list until a check has answered** since the store opened or the switch went on.
- **At most 10 albums on their way at once**, the next as those arrive, and **nothing asked below an album whose
  songs are still to be read**.
- **A song your library keeps offers no Remove Download of its own**; a failed library song's swipe lets it go and keeps
  its album off - the library lets go of the rest of the album, and its songs downloaded by hand stay.
- **The Library's Downloaded** lists a library album only once a song of it is here or on its way (open question 15).
- **Debug's switch is retired**: You > Downloads' Download your library replaces it.

### 6.6 After the review of slices 1-2 (2026-11-13)

The review found nothing that breaks the hard rules (only `[.library]` is ever taken; the empty, drop and truncated
lists hold; two checks 10 minutes apart; the migration; nothing crosses people), and thirteen real problems in the
fill, the planner and the edges. Each is now a Core rule with a test, and each test was seen failing with its rule
broken (notes/ios.md, "Phase 3, after the review"). What changed, against the sections above:

- **An album's own cover is its own** (2.6). An album only your library wants counts its kept cover in what it takes
  and in what it has here - 1 MB until its answer is kept - not as a hand download's bytes. So keepAlbum writing the
  cover no longer pushes an album at the edge out of the fill, which then deleted it, and asked for it again, in a loop.
  Album rows and lyrics are a few KB in SQLite and aren't counted in what's used. The margin covers them.
- **Hysteresis** (2.6): an album new to the phone fits only with a margin to spare: 50 MB, or 1% of the limit if that
  is more. One already asked for or here keeps its place while it fits at all. The band lies *below* the limit, so
  nothing is ever over it (the review suggested letting a held album run over by the margin; this keeps the limit
  exact, with the same band).
- **The phone's budget** (replaces 2.6's second point for the phone): new albums fit only into `free - handToCome -
  reserve`, less what the albums already held have yet to receive, with the margin. An album here never needs more of
  the phone, so a new star above it never pushes it out. Albums here give way only when the phone itself is short -
  `free - handToCome < reserve` - from the bottom, only as much as it is short, and only once plans at least 3 minutes
  apart have both seen it (`deficitConfirmMs`, on the uptime clock): one bad or momentary free-space reading never
  deletes anything.
- **One number for what the library can give back** (2.7): `LibraryFill.givable` (the bytes here of albums the fill
  can give way: read, or kept off), used as the planner's `libraryHere` and in the fill's fixed bytes alike. An album
  being read again, or a library song on no album of the library, isn't credited to a hand download any more.
- **A hand download on a full phone waits for the room**: taken on with the library's bytes credited (counted in
  `handToCome`, so the fill makes room), but its tasks are made only once the phone has the room as it is - so a hand
  download never takes the phone under 2 GB waiting for the library. It waits "the phone is full" for the 3 minutes
  the deficit takes to be believed.
- **Tasks out** (2.7's "the same 100"): your library has at most 20 of the 100. The hand downloads' are counted first,
  and a library task beyond its share is let go, its resume data kept. So a hand album never queues behind the
  library's.
- **A song leaves its album only on two reads** (2.4, 2.7): a read without a song the library has of it marks it
  (`left`, kept in the `library` row's new `left_songs` - store version 5) with the time of the first read without it.
  It goes only when a read 10 minutes or more after that agrees. An empty answer is never taken in (Navidrome
  mid-rescan): the album stays as it was. Until the second read, the song is still read on that album.
- **Kept song lists are read again** (2.4's last point, now built): a list a week old is read again, the oldest
  first, up to 20 a check within the four-at-a-time reads; an album due its second read is read then; and an album
  page opened online reads its album again from the page's own answer (no second request). Songs that left go only
  by the two-read rule.
- **A read that fails is skipped and the reads go on**, up to 12 failures a run. An album that failed is read after
  the rest at the next check, and never more than once a check.
- **Turning the switch off asks first** (3.1) when it would delete anything: "Remove the 412 albums downloaded with
  your library?", with "They go from this phone (12.4 GB). What you downloaded yourself stays.", **Turn Off and
  Remove** and Cancel. VoiceOver's action asks the same. Turning it off with nothing of it here asks nothing. Remove
  All still turns it off in its own question.
- **Didn't download's swipe on a library album** asks first when keeping the album off would delete songs of it
  already here: "Leave Dummy off this phone?", "Your library leaves it off until you download it again. Its 9 songs
  already here go too; songs of it you downloaded yourself stay.", **Remove Download** and Cancel.
- **Remove on the question survives a check already out**: a 304 of the held list keeps it, and a check that was out
  when Remove was answered keeps it and asks the next list afresh.
- **Removing your last album here** removes it: the empty-list question counts only albums not removed here.
- **A removed album's songs go by id too**: the songs each removed album was last read with are kept with it (meta
  `library_removed`, now JSON; slice 2's lines still read), so a song asked from a queue with no album id goes with
  its album. A song a retag moved onto an album still in the library stays with that album.
- **Phase 2's paths the library now runs far more often**: removeOrigins forgets kept albums only from a read of the
  songs that answered (a failed read had deleted every kept album's answer, cover and loudness), and settle sweeps
  song files no row names. That means only the store's own song names (`<id>.<suffix>`), only in its own music
  folder, and only from a read of the rows that answered. A crash after a row's delete commits no longer leaves its
  audio for ever.
- **A failed check changes nothing**, not even when the last one began, so the next minute's timer is due again (as
  6.4's notes always said; the code had set it before the fetch). **The 10-minute rules use the wall clock**: a phone
  whose clock is moved forward by 10 minutes or more between two checks could have them agree early. That is a
  known limit, left as it is. The deficit's 3 minutes are on the uptime clock, which Settings can't move.

### 6.7 Slice 3, built (2026-11-13)

Written up in notes/ios.md, "Phase 3, slice 3: only while charging, and in the background". Open question 11 is built
as recommended, literally. App 0.9 (9). What the build decided, or did differently:

- **One album at a time, within the library's 20** - not 2.8's "its songs, or 20, whichever is more". The review
  capped the library at 20 tasks out (6.6), so an album of more than 20 songs is handed over 20 at a time, the rest of
  the same album as those end, and never beside another album of the library. An unplug overnight still overruns by
  one album at most. Hand downloads beside it keep their own slots.
- **The batch is the first album of the library with a task out**, else the first in the fill's order that may make
  one. A new star above it doesn't take its place: iOS may be part-way through those songs with the app suspended.
  Any other album's tasks out are let go, their resume data kept.
- **The batch rule holds whenever Only while charging is on**, plugged in or not. Unplugged there are no library tasks
  at all; plugged in, the bound is what makes an unplug the app can't see cost one album.
- **The charging wait holds no room**, and the fill doesn't see it: an album waiting for the charger is still one
  that fits, so Only while charging never makes anything give way or go.
- **The power is read** from UIDevice's battery-state notification while the app runs, and again at every coming to
  the front, every background run and every relaunch for the session's events - iOS never tells a suspended app.
  `unknown` (monitoring off, or iOS can't tell) is not charging: Only while charging is literal.
- **A background run checks only if no check began within the minute** (`due(.front)`): a launch for the task makes
  the store's own opening check, and the run waits for that and its reads rather than asking twice. It waits up to
  10 seconds for the store and deadwax to be askable, then reads at most 20 albums' songs, then plans.
- **Nothing in the background deletes where the front wouldn't.** The run is the same check, the same plan and the
  same `removeOrigins([.library])`. The two checks 10 minutes apart are the store's, on the wall clock. The phone's
  deficit is confirmed on plans 3 minutes apart in one process on its uptime clock, so a run that launched the app,
  which iOS gives about 30 seconds, never confirms one - it waits for the app in front, or a long-lived background.
- **The tasks are asked for** at each move to the background, after each run (the refresh 15 minutes on again), and
  whenever a plan in the background changes what is wanted - so an unplug seen at a relaunch asks for the charger's
  task. A task not wanted has its request cancelled.
- **A relaunch for the session's events waits for a plan** (5 seconds at most) before telling iOS its events are
  done, so the next batch is handed over before the app is suspended again.
- **Debug keeps the last five runs** (UserDefaults `libraryBackgroundRuns`, per phone): which task, when, how long,
  and what came of it - check 61's evidence that iOS ran one at all.
- **Only while charging shows only while Download your library is on** (3.1's third row), off until chosen, per
  phone (`autoDownloadOnlyWhileCharging`).

### 6.8 Slice 3, after its review (2026-11-13)

The review of 953b8e5 found nothing that breaks Phase 2 or deletes what the front wouldn't, and kept the app delegate
adaptor (SwiftUI's own delegate handles the session's events and forwards only what it doesn't implement). Its
fixes, against 2.8, 2.9 and 6.7 (notes/ios.md, "Phase 3, slice 3, after its review"):

- **A run asks for the next as it begins**, not only as it ends: a refresh's request is used up when it runs, and a
  run iOS ends early had left nothing asked for until the app next went to the background.
- **Each run has its own deadline**: the check and the reads are waited for 15 seconds (the store's opening wait
  within it) and then stopped, and the plan has until 20 seconds. iOS's expiration still ends a run sooner, and the
  task is told it is complete exactly once.
- **Reads a background run cuts short hold the asks below them** (6.5's rule), until a run reads to the end -
  `LibraryFollow.readsPending` is `(running || cutShort) && unread`. Too many failures still moves on (6.6), and coming
  to the front carries the cut reads on at once.
- **A run's end stops the follower's run** while the app is still in the background - nothing reads on uncapped
  after it, and a check still out is dropped as a failed one is. Two runs at once each have their own cap.
- **The charger's task is asked for whatever wait the songs show** (2.9's "something waiting `charging`" replaced):
  with the switch and Only while charging on and songs only the library wants still to come, plugged in or not. A
  Wi-Fi, deadwax or network wait had hidden the charger's, so a phone left while out and plugged in at home did
  nothing. Before the store opens, its request is left as it is.
- **A stalled task doesn't hold the batch** (2.8): with Only while charging on, a library task that has brought
  nothing for 30 minutes (as this launch has seen, on the continuous clock) is let go with its resume data and made
  again at the next plan. An album whose every task out has stalled isn't the batch, so the library moves on.
- **A relaunch for the session's events has one 25-second budget**: the plan gets what the events left of it.
- **A launch that can't read its settings changes nothing.** iOS may launch the app before the phone's first unlock,
  when UserDefaults reads every switch as off. A launch is readable when it found the mark every readable launch leaves,
  or the phone is unlocked (a first launch ever). An unreadable one cancels no request and keeps no run, and only
  puts back the request the run used up. (`isProtectedDataAvailable` alone can't say it: it is false whenever the
  phone is locked, when nearly every run happens.)
- **check_project.py** requires UIBackgroundModes to be exactly audio, fetch, processing, the order ios.yml reads. A
  missing identifier makes BGTaskScheduler.register return false, so its task never runs; it doesn't crash the app.

## 7. Tests (Swift Testing; Core's on Linux and macOS)

- **LibraryFollowTests**: added in the list's order; changed (songCount, duration past half a second) clears the songs,
  a same entry keeps them; missing at the first absence, not removed before 10 minutes, removed at a check 10 minutes
  on - a 200 or a 304; back clears the mark; removed here removes at once, and is cleared when the album is listed;
  the empty list, the drop (half and more than 10; exactly half, or 10, not held) and a truncated list mark nothing and
  confirm nothing, a pending mark surviving them; a 304 after a held list held; duplicates in a list taken once;
  missing albums kept after the listed ones; `placedAt` (a star; a play within 30 days later than it; a play 31 days
  old ignored; a play dated ahead counted as now; the collection by `created`; none); `ordered` (newest first, ties by
  deadwax's order, undated last); `toRead` (unread in order, missing never); `due` for every reason.
- **LibraryFillTests**: all fit; the limit reached in order and a smaller album after a big one fitting; hand bytes
  first; no limit; the phone's budget - an album that fits the limit but not the phone waits `phoneFull` and holds
  its limit room; the phone under its reserve giving way from the bottom; library bytes here counted as the phone's to
  give; an album here needs no phone room; unread and kept off skipped and counted in M; give-way lists only albums
  with bytes here; N of M.
- **DownloadDatabase** (version 4): the table made; an album through every mark; a list replaced (gone rows deleted, a
  kept album's songs kept unless changed); songs set; removed here set; a version-3 file given the table with every
  other row kept; `removeAll` keeping the table.
- **LibraryFollowWords**: Debug's lines; (slice 2) **AutoDownloadWords**: every line of 1.2, the ban list over them.
- Mutations, as Phase 1's (each must fail a test): confirming at the first absence; the 10 minutes as `>` 10 (a check
  exactly 10 minutes on must remove); an empty list marking; a 304 not confirming; the drop's "and more than 10"
  dropped; `placedAt` taking a play of any age; the fill skipping hand bytes; a phone-full album not holding its limit
  room; give-way of an album with nothing here.

## 8. James's checks (on his iPhone)

### 8.1 Slice 1's (L0a-L0g)

You > Debug > **Your library**, with **Follow your library** on. Nothing downloads in this build.

- **L0a The first read** (R13). At home on Wi-Fi, turn it on: "Albums" says how many your library has (the web's
  Library count), and "Songs read" climbs to all of them. Note **how long the first read took** (its row) and the mean
  per album. If you can, once more over WireGuard away from home (Debug's switch off and on reads again from nothing)
  - this decides section 4's route.
- **L0b A star elsewhere.** Star an album in Amperfy or the web app; go to the Home Screen and back: within seconds
  Albums is one more, and its songs are read.
- **L0c Unstarred elsewhere.** Unstar one in the web app; back in the app: "Missing: 1 (since ...)". Ten minutes later,
  Check now: it's gone, and the log says "removed".
- **L0d Unchanged.** Check now twice with nothing played meanwhile: the second says "unchanged (304)". (A song played
  in between makes it a 200: the list carries when each album was last played.)
- **L0e Removed here.** Remove from my library on an album's page: Debug has it gone at once, no ten minutes.
- **L0f Would fit.** "Would fit" says N of M at your limit; set Storage limit to 5 GB and back: the line follows.
- **L0g Nothing else moved.** You > Downloads is as before; nothing is downloading that you didn't ask for.

### 8.2 The phase's (50-63)

The plan's four, then the design's own.

- **50 Overnight** (the plan's 1). At home on Wi-Fi, turn on Download your library with the phone on charge overnight:
  in the morning, your library is downloaded - or as much as fits, said in numbers in You > Downloads.
- **51 A star elsewhere** (the plan's 2). Star an album in Amperfy or the web app: within 15 minutes of the app being
  open (or at the next launch), it starts downloading.
- **52 An unstar** (the plan's 3). Unstar one: its songs go after the next check that is 10 minutes after the first
  that missed it - unless a song of it was downloaded by hand, which stays.
- **53 Add and Remove here** (the plan's 4). Add to my library on an album's page: it starts downloading at once.
  Remove from my library: its download goes at once, and the block said so.
- **54 Only while charging.** Turn it on and unplug: library albums say "Waiting for the phone to charge"; an album you
  download yourself doesn't wait. Plug in: they carry on.
- **55 The limit lowered.** Set the limit below what your library has here: the oldest albums go, whole, never one you
  downloaded yourself; the fit line says what fits now. Raise it: they come back.
- **56 A hand download on a full phone.** With your library filling the limit, download another album yourself: it
  downloads, and the bottom of your library gives way.
- **57 Remove Download on a library album.** It goes, and doesn't come back at the next check; its page says why.
  Download it again: it comes back, as yours.
- **58 The first ask.** On a phone that has never been asked: the card on the Library; Not Now puts it away for good.
- **59 Remove All** with the switch on: the dialog says the switch goes off too; afterwards nothing downloads again.
- **60 An empty list.** (Only if it can be arranged safely: stop Navidrome's music folder from mounting, or unstar
  everything on a test account.) Nothing goes from the phone; You > Downloads asks; Keep Them keeps them.
- **61 In the background.** Star an album on the Mac, leave the phone locked and not playing for an hour: note
  whether it came down without opening the app (iOS decides when; it may not).
- **62 Unplugged overnight.** Only while charging on, start a big library downloading, unplug and lock: in the
  morning, at most one album more than when you unplugged.
- **63 VoiceOver and the largest text size** on You > Downloads' section, the card and Downloading's row.

## 9. What only the phone can tell

- **The first read's time** over home Wi-Fi and over WireGuard (R13) - L0a.
- How often iOS runs a `BGAppRefreshTask` for a free-account app that's rarely in the background without music, and
  whether a `BGProcessingTask` with `requiresExternalPower` runs on a phone charging overnight.
- Whether background-made download tasks (discretionary) wait for power as Apple's documentation says, and how long.
- Whether `UIDevice.batteryState` changes reach a suspended app soon enough (they don't, by design: the batch bound is
  the guard).
- How much a 200 of a 3,000-album list costs on the phone (decode, diff, a transaction of 3,000 rows) - Debug times
  the check.
- Nothing drawn has been seen.

## 10. Open questions (each with what the build does until James answers)

1. **The first ask.** The plan: "Off until chosen (first run asks)". **Recommend: Off, asked once per phone by a
   card at the top of the Library's root** (3.2), not a dialog at launch.
2. **The order.** "Most recently starred first, with albums played in the last 30 days moved up". **Recommend: each
   album placed at the later of its star and its last play (a play counting within 30 days)** (2.5) - a group of the
   month's plays above every star would keep a new star off a full phone.
3. **Logins off.** **Recommend: the collection, newest first, as much as fits** - the Albums list the phone already
   shows (Choice 15); not the shared account's stars.
4. **Two checks agree** when **10 minutes or more** apart (2.3). Recommend 10: past deadwax's own five-minute re-star.
5. **A large drop** (more than half the albums and more than 10, at once) **is asked, as an empty list is**. Recommend
   yes - a Navidrome mid-rescan or an unmounted folder is the case the empty-list rule exists for.
6. **The phone's 2 GB** - **recommend the library gives back albums from the bottom when the phone falls under 2 GB
   free, and to make room for a hand download**, and never otherwise (2.6). The plan calls free space "a second limit".
7. **Remove Download on an album of your library** keeps it off this phone until downloaded again. **Recommend.**
   (Else it comes back at the next check; Apple Music's Automatic Downloads leaves a removed download removed.)
8. **Download on a library album waiting for room** makes it a hand download - first in the order, never given way.
   **Recommend.**
9. **Remove from my library** removes its library download at once (unless a song of it was downloaded by hand), and
   the mine block says so. **Recommend** (Phase 2's open question 7 kept: a hand download is never touched).
10. **Remove All Downloads with the switch on** turns the switch off, said in its dialog. **Recommend** - else the
    next check downloads it all again.
11. **Only while charging** is literal: library tasks only while charging, an unplug cancels what the app can, and at
    most one album handed to iOS at a time with it on. **Recommend.**
12. **A hand-downloaded album later starred** stays a hand download: never given way. **Recommend** (Choice 19).
13. **The switch per phone**, as Download over and the limit are - applying to whoever is signed in. **Recommend.**
14. **The `album_songs` route** only if L0a's first read over WireGuard takes over 10 minutes. **Recommend.**
15. **Library albums waiting for room** appear nowhere but the fit line and their own pages - one Downloading row, no
    tiles. **Recommend.**
16. **Reads four at a time.** **Recommend** - deadwax's Navidrome is asked in parallel by the web too; slice 1's
    measurement says whether more would help.
