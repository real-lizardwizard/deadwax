# Phase 1 screens - what the iPhone app shows, as the web app has it on a phone (2.1.0)

Scout for the deadwax iPhone app's Phase 1 ("the player"). Area: the screens - sign-in, the album
page, the queue menu, Now Playing and the mini player, the tab bar, You - and what happens to the
Phase 0 app. Read from the web app AS IT IS NOW (main = v2.1.0 = 1199330) and from the server's
routes and tests. Every path is repo-relative. Other areas (the Library screen, Up Next's content,
Info, the lock screen, resume, plays, the stream cache, normalization's route) are named where a
screen touches them, not specified.

## 0. The 2.1 foundation - checked

- `ios`, `origin/ios`, `origin/main` and tag `v2.1.0` are all `1199330` ("deadwax 2.1.0: the
  iPhone app's Phase 0 on main"). `src/__init__.py` says `2.1.0`. Working tree clean.
- The app is `0.1 (1)`: `ios/Config/Base.xcconfig:11` `MARKETING_VERSION = 0.1`, `:12`
  `CURRENT_PROJECT_VERSION = 1`. Phase 1 makes it `0.2` (plan decision) - and bumps the build
  number with every install James takes, or iOS keeps the old one's caches judged by build.
- Web changes since the plan's base (`git log 85aa7be..HEAD`) that touch these screens, all
  folded into this spec: 2.0.1 settings words (NormalizationChoice), 2.0.2 Change password (You),
  2.0.4 errors in a listener's words (SignIn, signInGate, lib/signIn, AlbumPage), 2.0.5 the
  vocabulary ("the collection", never "the store" - AlbumPage, whose.ts), 2.0.7 Now Playing and
  the mini player's words (mini player label, "Up Next" casing, playback errors), 2.0.8 plain
  words on managing pages (SignOutRow, SignIn, You), 2.0.9 fonts, 2.0.13 descriptions
  (AlbumPage - not Phase 1), 2.0.14 Shuffle and Repeat on Now Playing's main screen
  (NowPlaying, upNext.ts), 2.0.15 Recently played on Home (not Phase 1). TabBar, QueueMenu,
  ActionMenu, GaplessChoice, useMyLibrary, loudness.ts and levelling.ts are unchanged since.
- **Things on main that Phase 1 must change in the same commit as the app's routes**:
  - `tests/test_ios_contract.py:66-67` asserts exactly 7 `Endpoint(...)` lines in Routes.swift.
    Every route Phase 1 adds raises that number; the test must be edited with it.
  - `tests/test_ios_contract.py:45-51` `required_fields()` reads `public let name: Type` with
    `Type` matching `[\w\[\]]+\??` only. A property typed `[String: Int]`, `Int64?` (fine),
    `[DiscTitle]?` (fine) or a generic (`Optional<X>`, `Set<X>`) is invisible to it - keep model
    properties to plain names and arrays, or extend the regex.
  - `:170-173` pins `required_fields("Me") == {"user","admin","auth"}`; adding
    `permissions_unverified` as an optional keeps that true.
  - The loudness route the Normalization area needs (`GET /deadwax/navidrome/loudness/album/{id}`,
    per the iOS memory note) is NOT on main yet (`src/routes/navidrome.py` has no such route). It
    lands as server 2.1.1; the album page's warm (`POST .../level/album/{album_id}`) is already
    there (`src/routes/navidrome.py:665`).
- Nothing else on main stands in Phase 1's way: the same-origin guard passes the app's POSTs (no
  Origin header), the cookie the app keeps is the server's, and every route below is live.

## 1. The shell: launch, gates, tabs

### Launch order (native; the web's is `ui/src/app/signInGate.tsx`)

1. No address saved (UserDefaults `address`, as Phase 0) -> **Server address** screen (section 2).
2. Address saved -> `GET /deadwax/me` with the Keychain cookie (if any).
   - 200 -> `Me` in hand -> the app (tabs). `auth == "off"` means logins are off: no sign-in ever.
   - 401 -> **Sign in** screen alone, its reason = the 401's `detail` through `reasonShown`.
   - Any other failure (transport, 5xx, unreadable) -> web shows the sign-in form with
     `signInProblem(error)` above it (signInGate). Native: a "can't reach" screen (section 2's
     words) with **Try again** and **Change address** - see Open question 5.
3. Mid-use 401 on any request (web: `ui/src/api/http.ts` `noteSignedOut`):
   - ignored for `/deadwax/auth/*` paths, and for a request SENT under an older session than the
     current one (web keeps a session counter, `newSession`) - native: compare the cookie value
     the request carried with the one in hand now;
   - otherwise the sign-in is shown OVER the app (web: the app inert under it); **the music plays
     on**; on success `afterSignIn(before, now)` (`ui/src/lib/signIn.ts:66`): same user, or none
     before -> carry on; a different user -> start again (native: drop every model's state - the
     queue stops, pages pop to root - and reload `Me`).
4. `Me` is asked again when the app becomes active (`scenePhase == .active`; web: visibility
   visible and `pageshow` persisted) and after a stream failure, so a session that ended while
   the phone slept is noticed. A 401 there takes step 3.
5. Logins off, then turned on (web: `reloadWhenLoginsComeOn`, `RELOAD_AGAIN_MS 60_000`): any 401
   while `auth == "off"` -> re-ask `/me`; its 401 takes the sign-in screen.

### Who is who (the predicates every screen reads)

- `hasLibrary` = `me.auth == "on" && me.user != "deadwax"` (`ui/src/app/useMyLibrary.ts`
  `hasLibrary()`; server `src/routes/my_library.py:47 has_library`). False with logins off and
  for the break-glass admin.
- `isAdmin` = `me.auth == "off" || me.admin` (`ui/src/app/access.ts accessOf`).
- `seesDetail` = `isAdmin || permissions contains "server"` (`access.ts`) - who sees an error's
  raw words under the plain ones.
- Break-glass = `me.auth == "on" && me.user == "deadwax"` (`BREAK_GLASS_USER`,
  `ui/src/lib/signIn.ts:11`; `src/auth.py BREAK_GLASS_USER`): admin, no library, no queue (GET
  `/deadwax/navidrome/queue` answers empty, POST answers `{"rev": null, "ids_rev": null}` - the
  resume area stops saving silently), sign-in lasts 12 hours (`BREAK_GLASS_SECONDS`).
- Logins off: `/me` answers `{user: "local", admin: true, auth: "off", ...}`; Add/Remove answer
  409 `LOGINS_OFF`, so the album page never offers them.
- `permissions_unverified == true` (logins on): You shows `UNVERIFIED` (`ui/src/lib/permissions.ts`)
  "Some things an admin let you do are off for now - sign out and in again to get them back."

### Tabs in Phase 1 (`ui/src/app/TabBar.tsx`, `ui/src/lib/appRoutes.ts`)

Web: five tabs, `Home, Library, Search, Requests, You`, You at the right end; tapping the current
tab pops to its root, at the root scrolls to top; Requests carries a badge. **Phase 1 shows
`Library` and `You` only** (only they are built - Open question 3), same order, same names,
SF Symbols `square.stack` (Library) and `person.crop.circle` (You). The tab you're on pops to its
root on a second tap (NavigationStack path reset; at root, scroll to top) - the web's rule.
Library opens first.

The **mini player** sits above the tab bar on every tab whenever something is queued
(`.safeAreaInset(edge: .bottom)` on the TabView's content, iOS 17 - the bar itself is the
system's). It is never shown over Now Playing (a sheet covers it).

## 2. Server address (first run; later from You > This phone)

Phase 0's `ContentView` server section, kept as its own screen:

- Title "deadwax". One field, label **"deadwax's address"**, placeholder
  `http://192.168.1.20:8090` (Phase 0 `ios/App/ContentView.swift`), `.keyboardType(.URL)`,
  no autocapitalise, no autocorrect. Button **"Check"** -> `GET /deadwax/health` then `/me`.
- Words, Phase 0's (`ios/DeadwaxKit/Sources/DeadwaxCore/HTTP.swift`, `DeadwaxClient.swift`),
  kept verbatim - this is the one screen that speaks to whoever set the phone up:
  - unreachable: "Couldn't reach deadwax at X. (reason) Is the phone on your home Wi-Fi, or on
    WireGuard? If you said no when asked about the local network, turn deadwax on in Settings >
    Privacy & Security > Local Network."
  - HTML answered: "Something answered at X, but it isn't deadwax..." (DeadwaxClient `health()`).
  - bad address: `DeadwaxError.badAddress`'s words.
- On a good check: save the address (key the Keychain by server, as `SessionKeychain` does), then
  the launch order's step 2.
- The "can't reach" screen of step 2 says the web's `UNREACHED` (`lib/signIn.ts:17`) "Can't
  reach deadwax. Check you're on the right network (or your VPN is on) and try again." with
  **Try again** and **Change address**; an admin-only detail line is not possible here (no `Me`
  yet), so Phase 0's longer unreachable words go under a disclosure "For whoever runs deadwax"
  (`FOR_WHOEVER`, `lib/signIn.ts:21`) - the same split the sign-in screen makes.

## 3. Sign in

Web: `ui/src/app/SignIn.tsx`, rules `ui/src/lib/signIn.ts`, gate `ui/src/app/signInGate.tsx`,
pinned by `ui/test/signin.sim.cjs`. Server: `src/routes/auth.py`, `src/auth.py`, tests
`tests/test_logins.py`, `tests/test_ios_contract.py:136-157,176-184`.

### What it shows (top to bottom)

1. Avatar circle with **"d"**; title **"deadwax"**.
2. Lede: **"Sign in with your music server (Navidrome) account."**
3. Reason paragraph = `reasonShown(detail)` (`lib/signIn.ts:56`): the 401's `detail` trimmed;
   none when empty or equal to `PLAIN_SIGN_IN` "Sign in to use deadwax."; also hidden when it
   equals the problem line (no line twice). The 401 details it can carry (`src/auth.py`):
   "You've been signed out - sign in again." (SIGNED_OUT), "Your sign-in ran out after 30 days
   without use - sign in again." (EXPIRED), and LOGIN_GONE / KEY_CHANGED / BREAK_GLASS_ENDED /
   PASSWORD_RESET / PASSWORD_CHANGED / RESERVED_SESSION / "Your account was removed."
   (ACCOUNT_REMOVED) - shown as sent.
4. Form: **"User name"** (`.textContentType(.username)`, `.textInputAutocapitalization(.never)`,
   `.autocorrectionDisabled()`, focused when shown), **"Password"** (SecureField,
   `.textContentType(.password)` - the password manager fills it; the app never stores it).
   Return in the name moves to the password; return in the password submits.
5. Button **"Sign in"**, **"Signing in…"** and disabled while asking.
6. Problem line (announced - native: `AccessibilityNotification.Announcement`), then, when there
   is one, a disclosure **"For whoever runs deadwax"** holding `signInWhy(error)`.

### Rules

- Empty name or password (after trimming the name): "Type your user name and your password."
  - nothing sent (`SignIn.tsx`; the server says the same 400, `src/routes/auth.py`).
- The name is sent trimmed; the password as typed. Body `{"username", "password"}`
  (`Routes.swift SignInBody`; server `SignIn`: username max 200, password max 1000).
- The password field is cleared after every answer, good or bad.
- `signInProblem(error)` (`lib/signIn.ts:30`), exactly:
  1. an HTTP answer whose `detail` is a string and not plumbing (`lib/errorWords.ts:110
     plumbing`): if `why` is present and status is 503 -> `asSentence(detail) + " Tell whoever
     runs deadwax."`, else `detail` as sent;
  2. else 401 -> "That user name and password didn't work.";
  3. else 429 -> "Too many tries - wait a minute and try again.";
  4. else -> `SERVER_FAILED` "Something went wrong on the server - try again in a moment.";
  5. no HTTP answer -> `UNREACHED` "Can't reach deadwax. Check you're on the right network (or
     your VPN is on) and try again."
- `signInWhy(error)` (`:49`): `why` if sent; else `detail` if it is plumbing; else nothing.
- On 200: keep the session from `Set-Cookie: deadwax_session=...` in the Keychain (Phase 0
  `SessionCookie`, `SessionKeychain`), decode the answer as `Me`, `afterSignIn` (section 1).

### What the server answers (`src/routes/auth.py:50 login`)

| status | body | when |
| --- | --- | --- |
| 200 | `{user, admin, auth: "on", version, permissions: [..], permissions_unverified}` + cookie | signed in |
| 400 | `{"detail": "Type your user name and your password."}` | empty |
| 400 | `{"detail": "'{name}' is a name deadwax keeps for itself - nobody signs in as it."}` | `local` (RESERVED_NAMES) |
| 401 | `{"detail": "That user name and password didn't work."}` (WRONG_LOGIN) | wrong |
| 409 | `{"detail": "Logins are off, so there's nothing to sign in to: deadwax lets everyone in."}` | logins off - the app never shows the form then |
| 422 | `{"detail": SIGN_IN_FORM}` "deadwax couldn't read that sign-in - a user name is at most 200 characters and a password at most 1000. Check what you typed and try again." | over-long |
| 429 | `{"detail": "Too many tries for {name} - wait {s} seconds and try again. deadwax holds off so Navidrome doesn't lock the account."}` + `Retry-After` | 3 tries per 60 s per name |
| 503 | `{"detail", "why"}` (Explained, `src/api/app.py:465`): CANT_SIGN_IN "deadwax isn't ready for signing in, so nobody can use it just now.", NAVIDROME_UNSET "deadwax can't reach the music server, so nobody can sign in just now.", NO_DATABASE | can't run logins |
| 503 | `{"detail": "Navidrome isn't answering, so deadwax can't check your password right now - try again in a moment."}` | Navidrome down |
| 502 | `{"detail", "why"}` (Explained, `src/auth.py:1238,1247`): LDAP_ACCOUNT "This account can't sign in to deadwax: it's an LDAP account...", NAVIDROME_REFUSED "Navidrome couldn't check your password just now - try again in a moment." (`why` = Navidrome's own words) | Navidrome refused the check |

Phase 0's `signIn()` already throws `.refused(status, detailWords)`; Phase 1 must carry `why`
too (section 12), or the 503 split and the disclosure can't be drawn.

### Sign out (You > Account; web `ui/src/app/SignOutRow.tsx`)

- Row **"Sign out"**, value = the user name; **"Signing out…"** while asking.
- `POST /deadwax/auth/logout`. The server always clears the session: 200 `{"signed_out": true}`
  or 503 with `"problem"` (`src/routes/auth.py:78`). **Any HTTP answer = signed out** (web:
  any `ApiError` -> proceed). Phase 0's `signOut()` throws on anything but 200/401 - change it.
  Only no answer at all keeps you signed in: "Couldn't reach deadwax, so you're still signed in
  - try again."
- After: stop the player (the engine's `stop()`), clear the Now Playing info, delete the
  Keychain session, pop to the sign-in screen.
- Footnote under the row: break-glass -> "Signed in as deadwax, with the emergency admin
  password - this sign-in lasts 12 hours. "; otherwise "Signed in as {user}, with your music
  server (Navidrome) account. " - then, both: "Signing out ends this device's session and stops
  what's playing."

## 4. The album page

Web: `ui/src/player/AlbumPage.tsx` (opened from the Library, Now Playing's "Go to album", later
Search/Home). Rules: `ui/src/lib/whose.ts`, `ui/src/lib/discTitles.ts`, `ui/src/lib/format.ts`,
`ui/src/player/levelling.ts`. Pinned by `ui/test/whose.sim.cjs`, `discs.sim.cjs`,
`vocabulary.sim.cjs`, `loudness.sim.cjs`, `app-rules.sim.cjs`.

### What it asks, on open (all at once)

1. `GET /deadwax/navidrome/albums/{album_id}` (`src/routes/navidrome.py:331`) -> Navidrome's
   `getAlbum` `album` object as is, or `{}`. Errors: Navidrome code 70 -> 404 "Navidrome has
   nothing by that id"; others 502 with Navidrome's words (`_fail`).
2. With `hasLibrary` only: `GET /deadwax/store/album?navidrome_id={id}` (the id bridge,
   `src/routes/store_album.py:274`). Web asks it always and judges by `personal`; native may skip
   it when `!hasLibrary`, since without a library nothing on the page reads it in Phase 1
   (Properties, Pressings and Also chips are later phases).
3. When the album's answer lands: the warm, `POST /deadwax/navidrome/level/album/{album_id}`
   (`navidrome.py:665`, status 202) - **only** when the Normalization setting is not Off **and**
   some song is FLAC (`levelling.ts:28 warmAlbum`; FLAC = suffix `flac` or content type
   `audio/flac`, `lib/streamWrap isFlac`). Answer `{"state": "not_levelled" | "measuring" |
   "busy"}`; fire and forget, failures ignored (web `warmLevels` never sends one album's warm
   twice at once). Tests: `tests/test_normalization.py:702-757`.

Only the newest answer draws (`latestOnly`): a page left before its answer drops it.

### What it shows (top to bottom)

- **Hero**, drawn at once from what opened it (the Library row's id, name, artist, coverArt)
  then filled: cover (asked at 1024 - see "Covers"), title (two lines then truncate; long-title
  style over 60 code points, `lib/titles.ts heroTitleClass`), artist (plain text in Phase 1 -
  the artist page is Phase 3), meta line `[genre, year, format].filter(nonEmpty).join(" · ")`
  where `format = sharedFormat(songs)` (`lib/format.ts:44`: the one suffix every song shares,
  uppercased, else nothing).
- **Badge** (`whose.ts heldLabel`): "In your library" (with a checkmark) when `mine.yours ==
  true`, else "In the collection". Not drawn (space kept, invisible) until the bridge has answered
  or failed and `mine.pending` is false - so it never slides or flips.
- **Play** (filled) and **Shuffle** (plain), disabled until the songs are in. Play = start at
  song 0, not shuffled; Shuffle = no start song, shuffled (`startQueue(tracks, null, true)`,
  `ui/src/lib/playQueue.ts:59`: every song once, the first as random as the rest; a tapped song
  under shuffle plays first). Both queue `queued(tracks, "album")` (`levelling.ts:18`: each track
  carries `level = levelFor(setting, "album")`, `lib/loudness.ts:42`).
- **The mine block** (logins on with a library only), under the hero:
  - while pending and the album is in: an invisible placeholder holding the place of the likely
    line and button (`ADD_FROM_PAGE` + "Add to my library") so nothing jumps under a finger;
  - `mine.note` as a status line; `mine.action` as a button: add -> **"Add to my library"**
    (filled) / **"Adding…"**; remove -> **"Remove from my library"** (text button) /
    **"Removing…"**; aria-disabled (not disabled) while busy;
  - a refusal under it, in `errorWords` (section 12), announced.
- **Track list**: a disc heading row before the first song of each disc (rules below); each row:
  number = `song.track` (blank if none) or playing bars when it is the current song (bars still
  when paused); title; the song's artist only when present and different from the album's
  `artist`; time `trackTime(duration)` (`format.ts:34`: blank for 0/none, `m:ss`, rounded). A
  row's tap = Play from that index (shuffled if Shuffle is on in the player - the engine's rule,
  not the page's). A row's **•••** ("More for {title}") opens the queue menu with that one song.
- A spinner ("Loading") until the songs are drawn; on failure the error in `errorWords` with
  `gone: ALBUM_GONE` = "This album isn't here any more - it may have been moved or deleted."
  (404 -> that line).
- **Footer**: `"{n} song" / "{n} songs"` then `", " + formatDuration(total)` when total > 0
  (`format.ts:26`: rounded minutes, `"N min"` under an hour, else `"Hh Mm"`); total = sum of
  song durations.
- **Toolbar •••** "More for this album", disabled until the songs are in -> the queue menu with
  `{label: album.name, tracks: all, as: "album"}`.
- Not in Phase 1 (web has them): Also chips, Pressings, pin, Edit, description (2.0.13),
  Properties, the full-size cover viewer, the artist link.

### Disc headings (`ui/src/lib/discTitles.ts`, `ui/test/discs.sim.cjs`)

- `disc(song) = song.discNumber || 1`.
- `discTitleMap(discTitles)`: integer disc > 0, title trimmed and non-empty, the first per disc
  wins.
- Heading text: `"Disc N · <title>"` with a title, else `"Disc N"`.
- Headings are shown only when the album has more than one disc OR any disc has a title; then on
  the first song of each disc (every disc change, in list order).

### Add and Remove (`AlbumPage.tsx:305-330`, `whose.ts:203 albumMine`)

`albumMine` inputs: `personal = hasLibrary`; `starred = album.starred != nil` (null until the
album's answer; false if it failed); `storeDone`; `bridgeFailed`; `bridgeYours = store.yours`;
`present = store.present.count`; `release = store.release_mbid`; `releaseSaid =
album.musicBrainzId ?? ""` (null until the album's answer); `changed` (this page's own last Add
or Remove). Output `{yours: Bool?, badge, action: add|remove|nil, note: String?, pending}`.
In this order:

1. `!personal` -> yours true, badge "In your library", no action, no note.
2. `addable = release != nil && present > 0`.
3. changed added -> (true, remove, "Added to your library.")
4. changed removed -> (false, addable ? add : nil, addable ? REMOVED_FROM_PAGE :
   REMOVED_STAR_TO_RETURN)
5. `bridgeYours == true || starred == true` -> (true, remove, nil)
6. `starred == nil || !storeDone` -> pending (nil, nil, nil, pending true)
7. `bridgeFailed || (release == nil && releaseSaid non-empty)` -> (nil, nil, nil)
8. `why = release != nil ? NOT_FOUND_TO_ADD : NO_RELEASE_TO_ADD`
9. `bridgeYours == false` -> addable ? (false, add, ADD_FROM_PAGE) : (false, nil, why)
10. `present > 0` -> (nil, nil, nil)
11. else (false, nil, why)

Badge = yours == true ? "In your library" : "In the collection". Words (`whose.ts:158-169`):
- ADD_FROM_PAGE "It's already here - add it to your library to keep it with your music."
- ADDED_FROM_PAGE "Added to your library."
- REMOVED_FROM_PAGE "Removed from your library - it's still in the collection, and nothing was
  deleted."
- REMOVED_STAR_TO_RETURN = REMOVED_FROM_PAGE + " To add it back, make it a favourite in another
  music app."
- NO_RELEASE_TO_ADD "This album can't be added from here - make it a favourite in another music
  app, and it joins your library."
- NOT_FOUND_TO_ADD "This album can't be added from here yet - make it a favourite in another
  music app, and it joins your library."

The cases `ui/test/whose.sim.cjs` pins (port each as a Swift Testing case): logins off; in the
collection, not yours; yours by the bridge; yours by starred; starred before the bridge answers;
no release; no folder; bridge unable to say; bridge failed; no release where Navidrome names one;
pending before the bridge; pending before the album; added; removed even over a stale `starred`;
removed and not re-addable; and the words free of "star", "Subsonic", "Navidrome", "the store"
(`vocabulary.sim.cjs`).

**Add**: `POST /deadwax/me/library/add`, body (`FindCandidatesRequest`,
`src/routes/download.py:61-93`; `first = store.present[0]`):

```json
{"artist": "<first.artist || album.artist>", "album_artist": "<same>", "artist_mbids": [],
 "album": "<first.album || album.name || ''>", "year": "<first.year>" or null,
 "original_year": null, "release_mbid": "<store.release_mbid>", "edition_tags": [],
 "tracks": [], "release_group_mbid": "<store.release_group_mbid>" or null}
```

`artist` and `album` are required strings; only `release_mbid` decides what is added
(`src/store_index.py:416 held_copy` finds the folders by it; `tracks: []` means any held track
counts). Answers (`src/routes/my_library.py:125`):

| status | detail / body |
| --- | --- |
| 200 | `{"added": true, "already": Bool, "complete": Bool, "starred": Bool}` |
| 409 | LOGINS_OFF "Logins are off, so there's one library and everything in the collection is in it." |
| 409 | NO_ACCOUNT "The break-glass admin has no Navidrome account, so there's no library to add to - sign in as yourself." |
| 409 | "That pressing isn't matched to a release on MusicBrainz, so it can't be added from here." |
| 409 | "That pressing isn't in the collection now - Get it instead." |
| 503 | "deadwax can't read its database, so it can't keep your library" / "deadwax couldn't write to its database, so it couldn't add it" |

**Remove**: `POST /deadwax/me/library/remove`, body `{"navidrome_id": "<album id>"}` (1..256,
else 422). Answers (`my_library.py:229`): 200 `{"removed": true, "entries": Int, "words":
REMOVED}`; the same 409s and 503 (database); Navidrome's status and words on its failure (401
re-raised as signed out); 502 "It's still in your library - try Remove again in a moment.";
503 REMOVE_UNWRITTEN "It's out of your library, but deadwax couldn't save that, so it may come
back - try Remove again in a moment."

After either 200: `changed` = added/removed (the page says so at once, over the album's stale
`starred`), announce the note, and tell the Library area its list changed (web:
`useMyLibrary`'s refresh). A failure leaves `changed` as it was and shows the refusal.
Tests: `tests/test_personal_libraries.py:1087,1101,1108,344`; `tests/test_player_as_you.py:1042-1170`
(remove's words, 422 for a 300-char id, Add stars at once as you, refused with logins off and
for break-glass).

### The id bridge's answer (`src/routes/store_album.py:274`, `tests/test_store_lookup.py`)

`GET /deadwax/store/album?navidrome_id=` (exactly one of `release_mbid`/`navidrome_id`, else 422
"ask by exactly one of release_mbid and navidrome_id"):

- `release_mbid`: String? - Navidrome's reading of the album, lowercased; null when it has none
  or Navidrome is down (`test_navidrome_down_is_a_null_id_and_the_store_still_answers:321`).
- `release_group_mbid`: String?; `navidrome_id`: String?.
- `present`: [Row] - the folders of this release: `id` Int, `path`, `release_mbid`, `artist`,
  `album`, `edition`, `year` (a STRING), `formats` [String], `track_count` Int, and optional
  `size`, `original_year`, `first_seen`, `imported`.
- `other_pressings`: [Row + `navidrome_id`, `yours`?] - not read in Phase 1.
- `yours`: Bool? - only with logins on, a library, the ledger readable and something present.
- 401 when signed out.

### Covers

`GET /deadwax/navidrome/cover/{cover_id}?size=` (16..2000). The web asks only at steps
`[128, 400, 1024]` (`player/api.ts:438 COVER_SIZES`, `coverSize()` the smallest step that covers
the size asked, which callers give at 2x) so screens share fetches. Native: album hero 1024, Now
Playing 1024 (= Phase 0's `CoverSize.lockScreen`, so the lock screen reuses it), mini player
128, Library rows 400 (its area's call). A song's cover is `song.coverArt ?? album.coverArt`.

## 5. The queue menu - Play Next / Play Last

Web: `ui/src/app/QueueMenu.tsx`, words `ui/src/lib/upNext.ts:565`. Pinned by
`ui/test/upnext.sim.cjs:425`, `app-rules.sim.cjs:2424`.

- Opened from a track row's ••• (one song, `as` "songs") and the album's ••• (all songs, `as`
  "album"). A `QueuePick` = `{label, tracks, as}`.
- Native: `.confirmationDialog(pick.label, ...)` with **"Play Next"**, **"Play Last"**, and the
  system's **"Cancel"** (web's sheet: Play Next / Play Last / Add to a playlist… / Cancel - the
  playlist row is Phase 4).
- A choice queues `queued(pick.tracks, pick.as)` - so an album's Play Next carries its album
  level, a single song its own (`levelFor`). Playback action from the tap, nothing awaited.
- `playNext`/`playLast` say whether the music STARTED from it (nothing was playing). Only when it
  didn't: a notice for 5 s (`PIN_NOTICE_MS 5000`): `queuedWords("next", label)` = "Playing next:
  {label}", `("last")` = "Added to Up Next: {label}". When it did start, the mini player is the
  notice.
- Native notice: a capsule above the mini player, announced to VoiceOver, gone after 5 s.

## 6. The mini player

Web: `ui/src/player/MiniPlayer.tsx`; label pinned by `ui/test/info.sim.cjs:1112`.

- Shown whenever the queue has a current track. 64 pt tall (`--pl-mini-height 64px`), inset
  8 pt from the edges (`--pl-mini-inset`), above the tab bar.
- Cover (128), title (one line), second line = the player's error if any, else the track's
  artist; **Play/Pause** (busy look while buffering), **Next**; a hairline along its bottom edge
  = position / duration.
- The whole bar (not the buttons) opens Now Playing. Accessibility label `miniPlayerLabel(title,
  line)` = `"Now playing: {title}, {line} - open"`, or `"Now playing: {title} - open"` with no
  line.
- Playback errors (`ui/src/player/usePlayer.ts`, 2.0.7) as the line: "The connection dropped
  while this song was loading", "This device couldn't play this song's audio", "Couldn't play
  this song - it didn't come as audio this device can play", "Couldn't play this song"; a
  skipped song's notice (5 s, `SKIP_NOTICE_MS`): `Skipped "{title}" - this device couldn't play
  its audio` / `Skipped "{title}" - it wouldn't play`. Native maps its engine's `.failed(String)`
  to these words (the engine's own string is Debug's).

## 7. Now Playing (a phone)

Web: `ui/src/player/NowPlaying.tsx` (2.0.14 put Shuffle and Repeat on the main screen), scrub
`ui/src/lib/scrub.ts` (`ui/test/scrub.sim.cjs`), labels `ui/src/lib/upNext.ts:565-597`
(`upnext.sim.cjs:425-431`).

- A full-screen sheet over the tabs, opened from the mini player; closes with the **chevron**
  ("Close") at top or a drag down past 110 pt (`DISMISS_PX`, starting after 6 pt,
  `DRAG_START_PX`). Native: `.fullScreenCover` with a drag gesture of the same numbers.
- Backdrop: the cover, blurred (web asks 300 -> 400; native reuses the 1024).
- Cover, large, scaled to 0.82 while paused (`--pl-paused-scale`), springing back on play.
- The player's error line, if any, above the title.
- Title; byline `"{artist} — {album}"` (an em dash), a button "Go to the album: {byline}" when
  the track has an `albumId`: closes the sheet and opens the album page on the current tab (web
  `App.tsx:1234 goToAlbum`: the album last played, else a stub `{id, name: track.album,
  coverArt}`).
- **Scrubber** ("Position in the song", value "m:ss of m:ss"): a tap seeks there; a drag seeks
  only on release; a cancelled drag seeks nowhere; a drag in progress is dropped when the song
  changes. Clocks: elapsed `clock(shown)` and remaining `"-" + clock(length - shown)`, `clock`
  = floor `m:ss`. VoiceOver adjust = ±5 s (`KEY_STEP_S`); the web's ±30 s page step has no iOS
  gesture. After a seek the shown time holds the target until the engine reports within 1.5 s of
  it (`LANDED_WITHIN_S`) or 20 s pass (`PENDING_MAX_MS`) - so the thumb never snaps back.
- **Transport** (one row, 2.0.14): **Shuffle** (pressed state; label `shuffleLabel(scope)` =
  "Shuffle", or "Shuffle - shuffling all music" / "Shuffle - shuffling your whole library" for
  the Library's paged shuffle, then disabled), **Previous** (restarts the song after 3 s in,
  `RESTART_AFTER_SECONDS`, else goes back one), **Play/Pause** ("Pause"/"Play"; busy while
  buffering), **Next**, **Repeat** (pressed when not off; cycles off -> all -> one; label
  `repeatLabel`: "Repeat", "Repeat all", "Repeat one"; the repeat-one glyph `repeat.1` on one).
- **Footer**: **AirPlay** (`AVRoutePickerView` - native, always available), **Up Next**
  (`list.bullet`; label `upNextLabel(shuffle, repeat)`: "Up Next", "Up Next - Shuffle on",
  "Up Next - Repeat all", "Up Next - Repeat one", "Up Next - Shuffle and Repeat all"; untinted),
  **•••** ("More: info, go to album" in Phase 1; web adds "add to a playlist", ", pin").
- Not native: the turntable look button, SpeedChip (the web's own).

### How Up Next opens (its content is the Up Next area's)

From Now Playing's footer button, as a sheet OVER Now Playing (web: a sheet over the sheet on a
phone). Header: **Edit** (when editable) / **"Up Next"** / **Done** (ends Edit while editing,
else closes). Lines it may show: "Repeat one: this song plays again until you skip it."
(`REPEATING_ONE`), "Shuffling your whole library" (`SHUFFLING_LIBRARY`); chips Shuffle and
`repeatLabel`; a "Playing Next" section with **Clear**; "And N more songs." past 100
(`UP_NEXT_DRAWN`); a row's label "{title}, play now"; in Edit, "Move {title} up/down", "Remove
{title}" (native: `.onMove` / `.onDelete` in an editing List); announcements "Shuffle on",
"Shuffle off", "Repeat off" / `repeatLabel`, "Playing Next cleared".

### Now Playing's ••• (`ui/src/app/ActionMenu.tsx`)

Web: Info, Add to a playlist…, Go to album (with an albumId), Pin album to Home / Unpin, Cancel.
**Phase 1: "Info" and "Go to album" (with an albumId), and Cancel.** Info opens the Info sheet
(the Info area: About + the "Sound" group, 2.0.7).

## 8. You

Web: `ui/src/app/You.tsx` (pinned by `ui/test/you.sim.cjs`, `settings.sim.cjs`,
`ownpassword.sim.cjs`). Phase 1 shows, as a grouped `Form`, in order:

1. **Headline**: avatar = the signed-in user's first letter uppercased, else "d"; name = the user
   (logins on) else **"deadwax"**; under it, logins off: **"No sign-in needed"** (`NO_SIGN_IN`);
   while `/me` is unanswered: "…". With `permissions_unverified`: the `UNVERIFIED` line.
2. **Playback** (header "Playback"):
   - **Normalization** (`ui/src/app/NormalizationChoice.tsx`, `settings.sim.cjs`): a picker of four,
     each with its note (native: an inline `Picker` with `.pickerStyle(.inline)` and the note as
     each row's subtitle):
     - **Automatic** (`auto`, the default `DEFAULT_NORMALIZATION`): "An album you play keeps one
       level for the whole album, so its quiet songs stay quiet beside its loud ones. Anything
       else - a playlist, a shuffle, a song you add with Play Next - is levelled song by song."
     - **By song** (`song`): "Every song brought to the same loudness, even the quiet and loud
       songs of one album."
     - **By album** (`album`): "Every song at its album's level, even when it plays on its own or
       in a playlist."
     - **Off** (`off`): "No levelling: every song plays exactly as the file is, bit for bit,
       unless Maximum quality converts it." - native drops ", unless Maximum quality converts
       it" (Open question 2).
     - Section note (You.tsx): "Evens out FLAC songs only - other files play as they are. The
       first time an album is levelled, deadwax measures it, so its first song can take a few
       seconds to start."
     - Footer (You.tsx): "These are kept on this device. Maximum quality changes from the next
       song, and Normalization from the next thing you play." - native: "This is kept on this
       phone. Normalization changes from the next thing you play."
     - Kept per device (UserDefaults `normalization`, raw values `auto|song|album|off`), read at
       each play's tap (web `readPlayerNormalization()`), never changing what is queued.
   - **Gapless** (web `GaplessChoice.tsx`: a toggle, off by default, per device): the native engine
     is sample-exact within a format by nature - no toggle in Phase 1 (Open question 1).
   - Not native: the turntable look, Pause winds down, Maximum quality.
3. **Your library** (`app/YourLibrary.tsx`) - not Phase 1 (Open question 4).
4. **Account** - only when `auth == "on"`: Change password (2.0.2) is a later phase; **Sign out**
   (section 3) with its footnote.
5. **About**: **Version** = `me.version` ("Not known" when the answer had none, "…" while
   asking); for an admin, **Logins** "On"/"Off". Native adds **App** = `0.2 (build)`.
6. **This phone** (native): **Server** = the address, opening the Server address screen
   (changing it signs out of the old server: its Keychain session stays keyed to it).
7. **Debug** - admins only (`isAdmin`): Phase 0's `ContentView` content moved whole (Check and
   its `CheckReport` lines, test sounds Streamed/Downloaded, Download all, Remove the downloads,
   hi-res, the Playing readout via `RateWords`, the install line) - see section 10.

Failures of `/me` here: `errorWords` with the old version kept (`you.sim.cjs`: a failed ask after
a good one keeps the version and says it failed).

## 9. Errors in a listener's words (what the screens need from `lib/errorWords.ts`)

Every refusal a listener reads on these screens (album load, Add/Remove, playback) goes through a
port of `ui/src/lib/errorWords.ts` (`ui/test/errors.sim.cjs`); the sign-in screen through
`signInProblem` (section 3). The port needs, per failure: `status`, `detail` (string only),
`why`, `kind`, `busy`, `path` (web `ApiError`, `ui/src/api/http.ts`) - or "no answer"
(offline) / timeout.

- `errorKind` (`:134`), in order: server `kind` with a fit detail and not 401 -> refused;
  401/403 -> not-allowed; 404 -> not-found; 408/504 -> timeout; `why` and `detail` -> refused;
  502/503 with a fit detail -> refused; 502/503 -> unreachable; other 4xx with a fit detail ->
  refused; else other. No answer -> offline; a timeout -> timeout. `fit` = non-empty, not "Not
  Found", not plumbing.
- `errorWords` (`:189`) text and advice per kind: offline "Can't connect to deadwax." + "Check
  your connection, then try again."; timeout "That took too long." + "Try again."; unreachable
  `DOWN[service]` ("Can't reach the music server right now." for `/navidrome` paths, else
  "deadwax can't do that right now.") + "Try again in a minute - if it keeps happening, tell
  whoever runs deadwax." (admin: "Try again in a minute."); not-found: the caller's `gone` else a
  fit detail else "It isn't there any more."; not-allowed: 401 "Your sign-in has ended - sign in
  again." else a fit detail else "You don't have permission for that."; refused: the detail as
  sent, advice "Tell whoever runs deadwax." only for a 503 with `why` and a non-admin; other
  "Something went wrong." + "Try again - if it keeps happening, tell whoever runs deadwax."
  (admin "Try again."). `detail` (raw words) shown under it only for `seesDetail`.
- `plumbing` (`:110`): the regexes (URLs, setting names, `*Error`/`*Exception`, Errno/Traceback/
  HTTPConnectionPool/Max retries/host=/port=, `METHOD /path`, paths, slskd/Subsonic, "answered
  NNN"/"HTTP NNN", "(Navidrome|MusicBrainz) said") ported verbatim, each with
  `errors.sim.cjs`'s cases.

## 10. The Phase 0 app: what stays, what changes, where it goes

`ios/App/` (synchronized folder - new files need no project edit) and `DeadwaxCore`:

| file | Phase 1 |
| --- | --- |
| `DeadwaxApp.swift` | stays: one WindowGroup, `.preferredColorScheme(.dark)`, `.tint(Palette.accent)` (#C084FC); its root becomes `RootView` |
| `AppModel.swift` | split: `ServerModel` (address, client, `Me`, sign-in state, the 401 rule) and `PlayerModel` (engine, queue, Now Playing info, interruption, ticker); the test-song code moves to `DebugModel` |
| `ContentView.swift` | becomes `You/DebugView.swift` (admins only), minus the address field (now `ServerAddressView`) and Sign in (now `SignInView`); footer "deadwax for iPhone 0.2 (n)" without "- Phase 0" |
| `NowPlayingController.swift` | stays; `show()` gets the real queue; repeat/shuffle remote commands are the lock screen area's call (Open question 8) |
| `AudioSessionController.swift`, `URLSessionTransport.swift`, `SessionKeychain.swift` | stay as they are |
| `SongFiles.swift` | stays for streaming; the downloads half stays Debug's until the cache area |
| `DeadwaxClient.swift` | `signOut()` treats any HTTP answer as signed out; failures carry `why/kind/busy/path`; new calls below |
| `HTTP.swift` | `DeadwaxError.refused` grows into an `APIFailure` (section 11); Phase 0's words stay for the address screen |
| `Check.swift` | stays, read by Debug |
| `Routes.swift` | add the endpoints below; update `tests/test_ios_contract.py`'s count |
| `Models.swift` | add the models below; `Me` gains `permissions_unverified: Bool?` |

## 11. Core additions for these screens

### Routes (`Routes.swift`, each one `Endpoint(method:path:query:)` line the contract test reads)

| name | endpoint |
| --- | --- |
| `album` | `GET /deadwax/navidrome/albums/{album_id}` `[]` |
| `storeAlbum` | `GET /deadwax/store/album` `["navidrome_id"]` |
| `libraryAdd` | `POST /deadwax/me/library/add` `[]` |
| `libraryRemove` | `POST /deadwax/me/library/remove` `[]` |
| `levelAlbum` | `POST /deadwax/navidrome/level/album/{album_id}` `[]` |

(+ the Library, Up Next/resume, plays and loudness areas' own.) The contract test checks each
path parameter is named as the server names it (`album_id`), and each query name is declared.

### Models (`Models.swift`; required = non-optional `let`, what the contract test checks)

- `Me`: `user`, `admin`, `auth`; optional `version`, `permissions: [String]?`,
  `permissions_unverified: Bool?`.
- `Album`: `id`; optional `name`, `artist`, `artistId`, `coverArt`, `songCount`, `duration`
  (Double), `year` (Int), `genre`, `musicBrainzId`, `starred` (String, ISO), `created`, `played`,
  `song: [Song]?`, `discTitles: [DiscTitle]?`. (`getAlbum` answers `{}` for nothing - decode
  `id` optional-safe or treat `{}` as gone.)
- `DiscTitle`: `disc` Int, `title` String (both optional-tolerant; the rule drops bad ones).
- `Song` (Phase 0's): add `artistId`, `year`; `title` is optional in Phase 0 - keep it.
- `StoreAlbum`: optional `release_mbid`, `release_group_mbid`, `navidrome_id`, `yours`;
  required `present: [StoreRow]`.
- `StoreRow`: required `id` Int, `path`; optional `artist`, `album`, `year` (String),
  `release_mbid`, `edition`, `formats`, `track_count`.
- `AddRelease` (Encodable): the body in section 4.
- `AddedToLibrary`: `added`, `already`, `complete`, `starred` (Bool).
- `RemovedFromLibrary`: `removed` Bool; optional `entries` Int, `words` String.
- `RemoveBody`: `navidrome_id`.
- `LevelWarm`: `state` String.

### Pure rules (DeadwaxCore, each tested on Linux against the sim's cases)

`SignInRules.swift` (signInProblem, signInWhy, reasonShown, afterSignIn, the constants),
`ErrorWords.swift` (section 9), `Whose.swift` (albumMine, heldLabel, the six words),
`DiscTitles.swift`, `Format.swift` (trackTime, formatDuration, sharedFormat, clock),
`Scrub.swift` (the pending-seek and drag rules), `PlayerWords.swift` (miniPlayerLabel,
queuedWords, repeatLabel, shuffleLabel, upNextLabel, nextRepeat, the playback error words),
`Access.swift` (hasLibrary, isAdmin, seesDetail, isBreakGlass), `Loudness.swift`
(Normalization, levelFor - shared with the Normalization area).

## 12. SwiftUI layout proposed for `ios/App`

```
ios/App/
  DeadwaxApp.swift            (stays) root = RootView
  Models/ServerModel.swift    address, client, Me, session, 401 rule, re-ask on active
  Models/PlayerModel.swift    the engine, queue, Now Playing info (from AppModel)
  Models/AlbumModel.swift     one album page's loads (album, bridge, warm), mine, Add/Remove
  Models/DebugModel.swift     Phase 0's test songs and downloads
  Root/RootView.swift         address -> unreachable -> sign-in -> MainTabs; sign-in over the app
  Root/ServerAddressView.swift
  Root/UnreachableView.swift
  Root/SignInView.swift
  Root/MainTabs.swift         TabView(Library, You) + mini player inset + notice
  Album/AlbumView.swift       hero, badge, Play/Shuffle, mine block, list, footer
  Album/TrackRow.swift
  Album/MineBlock.swift
  Player/MiniPlayerView.swift
  Player/NowPlayingView.swift
  Player/ScrubberView.swift
  Player/AirPlayButton.swift  AVRoutePickerView wrapper
  Player/NowPlayingMenu.swift Info, Go to album
  Player/QueueMenu.swift      confirmationDialog modifier: Play Next, Play Last
  Shared/Notice.swift         the 5 s capsule, announced
  Shared/CoverImage.swift     cover by id and step, cached in memory
  Shared/ErrorNote.swift      ErrorWords drawn (text, advice, detail for seesDetail)
  You/YouView.swift
  You/PlaybackSection.swift   Normalization
  You/AccountSection.swift    Sign out + footnote
  You/DebugView.swift         Phase 0's ContentView, admins only
  (system glue, unchanged)    NowPlayingController, AudioSessionController, SongFiles,
                              URLSessionTransport, SessionKeychain
```

Library/ (its area) and UpNext/ (its area) slot in beside Album/ and Player/.

## 13. What pins each rule (to mirror in Swift Testing)

- `ui/test/signin.sim.cjs`: signInProblem, signInWhy, reasonShown, afterSignIn, the empty check,
  the trimmed name, the password cleared, the problem not shown twice.
- `ui/test/whose.sim.cjs:107-180`: albumMine's cases (section 4); `vocabulary.sim.cjs` the words.
- `ui/test/discs.sim.cjs`: disc headings.
- `ui/test/errors.sim.cjs`: errorKind, errorWords, plumbing.
- `ui/test/scrub.sim.cjs`: clock, drag start/move/end, cancel, pending seek.
- `ui/test/upnext.sim.cjs:425-431`: queuedWords, repeatLabel, shuffleLabel, upNextLabel.
- `ui/test/info.sim.cjs:1112`: miniPlayerLabel.
- `ui/test/settings.sim.cjs`: the Normalization names, notes and default.
- `ui/test/loudness.sim.cjs`: levelFor.
- `ui/test/playqueue.sim.cjs`: startQueue (Shuffle with no start; a tapped song first).
- pytest: `tests/test_ios_contract.py` (routes, fields, bounds), `test_logins.py` (sign-in and
  out), `test_personal_libraries.py` and `test_player_as_you.py` (Add/Remove),
  `test_store_lookup.py` (bridge), `test_normalization.py:702-757` (warm).

## 14. Phase 1 checks these screens owe (on James's iPhone)

1. First run: address, Check, sign in as himself; a wrong password says "That user name and
   password didn't work."; the password manager fills the form.
2. An album: hero, badge, disc headings on a multi-disc album, Play, Shuffle, a row's tap, row
   ••• Play Next / Play Last with the notice.
3. Add and Remove on an album in the collection; the words; the Library shows the change.
4. Now Playing: scrub (tap, drag, cancel), prev/play/next, Shuffle, Repeat (all, one), AirPlay,
   Go to album, swipe down.
5. Sign out stops the music and returns to sign-in; signing in as someone else starts clean.
6. Break-glass: no Add/Remove, badge "In your library", footnote's 12 hours, Debug present.
7. Normalization changed: the next thing played follows it; Off plays bit for bit.

## Open questions

1. **Gapless toggle natively?** The engine is gapless by construction; the web's toggle exists
   because browsers aren't. Recommend: no toggle; one line under Playback: "Albums play straight
   through, with no gap between songs." Revisit only if a format crossing proves audible.
2. **Off's note**: the web's ends ", unless Maximum quality converts it", a setting the app has
   no screen for (hi-res is resampled by the engine/server as needed). Recommend: native says
   "No levelling: every song plays exactly as the file is, bit for bit." - and if a hi-res file
   IS resampled for the phone, say that in Info's Sound group, not here.
3. **Tabs in Phase 1**: recommend Library and You only (Home, Search, Requests appear with their
   phases), Library first. Showing empty or "coming later" tabs would be dead ends.
4. **You's "Your library" section** (counts, New): recommend leaving it to the phase that brings
   Home's New shelf; Phase 1's Library already shows what's yours.
5. **Launch when `/me` fails with no 401**: the web shows the sign-in form with the problem. A
   form can't fix an unreachable server. Recommend a "can't reach" screen (UNREACHED words, Try
   again, Change address, the detail under "For whoever runs deadwax"); from Phase 2, start
   from the last `Me` kept on the phone so downloaded music plays offline.
6. **Who sees Debug**: recommend `isAdmin` only (a Navidrome admin, break-glass, or anyone with
   logins off). An ordinary user who needs it is asked to sign in as an admin; no hidden gesture.
7. **Server ordering**: the contract test's count and the loudness route (2.1.1) must be on main
   before an app 0.2 that calls it is installed. Recommend each server addition its own 2.1.x
   commit on main (count and models in step), the app's Phase 1 merged after; James's server
   runs `:experimental`, which picks them up on push.
8. **Lock screen Shuffle/Repeat**: Phase 0 disables `changeShuffleCommand` and
   `changeRepeatModeCommand`. Recommend enabling both now that Now Playing has them, mapping
   `.all/.one/.off` and `.items/.off`, so CarPlay and Control Center show the same state.
9. **The notice's place**: recommend a capsule just above the mini player (where the web's sits
   above the player bar), 5 s, announced; never covering the mini player's buttons.
10. **Skip the id bridge without a library?** The web asks it on every album; native needs it only
    for `hasLibrary`. Recommend skipping it otherwise in Phase 1, asking it always once Properties
    or Pressings arrive.
