# Phase 4 - Playlists, artists, songs: what the iPhone app shows and does (app 0.10)

Design spec for the iPhone app's Phase 4 ("Playlists, artists, songs"), read 2026-11-13 at `ios` b4cf8e0 (app 0.9 (9),
server 2.1.15). Area: Navidrome's playlists as the person signed in - the list, a playlist's page, playing one, Add to
a playlist, New, Edit and Delete, and Download a playlist with its own origin; the artists and an artist's page; every
song, paged; the Library's Shuffle of the whole library, past its first page - with the phase's checks. Every path is
repo-relative and every line number is the code's at b4cf8e0.

**What binds it.** The plan (`~/Desktop/Code/deadwax-ios-plan.md`, outside the repo): James's answers at its top; its
section 5's "Phase 4 - Playlists, artists, songs" (the four features and three checks); section 2's routes table
("Playlists | GET/POST /navidrome/playlists, GET /playlists/{id}, POST .../add, .../edit, .../delete"); section 4's
"Storage limit and eviction" ("songs downloaded by hand and downloaded playlists, which are never evicted
automatically") and "What a sync does" 3 ("A song also downloaded by hand, or in a downloaded playlist, stays");
"Choices made" 19. Then what is built: Phase 1's library.md (above all Open question 1: "the root of rows arrives in
Phase 4 with Artists, Songs and Playlists"), Phase 2's downloads and Phase 3's library (`notes/ios.md`). This phase
builds on the player, the queue menus, the downloads and their origins, and rebuilds none of them.

**Where the words come from.** The web app has every one of these features, so its words and rules are the app's -
ported, and held to its TypeScript by a committed exporter wherever they are pure (as every port since Phase 1 is).
The web's files: `ui/src/lib/playlists.ts` (the rules and words), `ui/src/app/PlaylistsPage.tsx`, `PlaylistPage.tsx`,
`PlaylistPicker.tsx`, `NewPlaylistForm.tsx`, `usePlaylists.ts` (the list and the kept pages), `ui/src/lib/playedAlbums.ts`
(the albums Info knows), `ui/src/lib/artistPage.ts` and `app/ArtistPage.tsx`, `ui/src/lib/shelves.ts` (the artist
sorts), `app/LibraryViews.tsx` (Songs), `app/ShuffleSongs.tsx` and `app/useShuffleFeed.ts` (the Library's Shuffle);
`notes/playlists.md`, `notes/app-library.md`, `notes/app-artists-pins.md`, `notes/logins.md` "The player as you",
`notes/app.md` "Up Next, shuffle and repeat". Where the phone has something the web hasn't (downloads, offline), the
words are new and listed in section 1.

## 0. The foundation - checked

- **The branch.** `phase4-library`, from `ios` b4cf8e0, clean. `src/__init__.py` says `2.1.15`;
  `ios/Config/Base.xcconfig:11-12` say `MARKETING_VERSION = 0.9`, `CURRENT_PROJECT_VERSION = 9`. Phase 4's commits
  leave both alone until its last slice, which makes the app **0.10 (10)** with check_project.py, ios.yml,
  tests/test_ios_install.py, ios/README.md and docs/ios.md pinned with it (as 0.3 to 0.9 were).
- **Whose playlists** (`src/playlists.py:59-100`, `src/routes/navidrome.py:1078-1420`). Navidrome's own, read and
  written **as the asker** (`client_for(request)`: the session's own Navidrome login with logins on). With logins off,
  and for the break-glass admin, the asker is the shared `NAVIDROME_USER`, whose playlists are "mine". `mine` = the
  owner, case-folded, is the asker; listed = mine or public (somebody else's private playlist is never listed, even to
  an admin); `editable` = mine and not `readonly` (a smart playlist, or one kept in step with an .m3u). The app never
  asks as anyone else: every route is the person's own cookie.
- **The routes** (all exist, none in the app's `Routes` yet):

  | route | answers | slice |
  | --- | --- | --- |
  | `GET /deadwax/navidrome/playlists` (`:1266`) | `{playlists: [Playlist]}`, Navidrome's order (by name) | 1 |
  | `GET /deadwax/navidrome/playlists/{playlist_id}` (`:1294`) | `{playlist, songs: [Song], hidden}`; 404 for one not listed | 1 |
  | `POST /deadwax/navidrome/playlists` (`:1282`) | `{name, song_ids}` -> PlaylistWithSongs | 2 |
  | `POST .../{id}/add` (`:1307`) | `{song_ids, duplicates: ask|add|skip}` -> `{done: false, already, asked}` or `{done: true, added, already}` | 2 |
  | `POST .../{id}/edit` (`:1329`) | `{base, song_ids, tried?, name?, comment?, public?}` -> PlaylistWithSongs; 409 changed elsewhere; 422 not only a rearrangement; 502 part saved | 2 |
  | `POST .../{id}/delete` (`:1405`) | `{deleted: true}` | 2 |
  | `GET /deadwax/navidrome/artists` (`:398`) | `{artists: [{id, name, albumCount, coverArt, musicBrainzId}]}` | 4 |
  | `GET /deadwax/navidrome/artists/{artist_id}` (`:420`) | getArtist's artist with its `album` list | 4 |
  | `GET /deadwax/navidrome/search` (`:351`, already `Routes.search`) | an empty `q` pages every song (`songCount`, `songOffset`) | 5 |
  | `GET /deadwax/navidrome/shuffle` (`:1014`) | `{token, total, songs}` (the first 200) | 3b |
  | `GET /deadwax/navidrome/shuffle/{token}` (`:1057`) | `{total, songs}` from `offset`; 404 "gone" | 3b |

  tests/test_ios_contract.py's ROUTE_COUNT moves 30 -> 32 (slice 1), 36 (2), 38 (3b: the two shuffle routes, which
  were slice 5's until the Library's pull to shuffle needed them), 40 (4); slice 5 adds none (Songs pages the
  search route the app already calls).
- **A playlist's summary** (`summary`, `src/playlists.py:84`): `id, name, comment, songCount, duration, created,
  changed, owner, public, coverArt (null for none), mine, editable` - every field always sent ('' or 0 for what
  Navidrome left out). On one playlist, `songCount` and `duration` are the songs listed (`with_songs`, `:109`), and
  `hidden` the songs Navidrome counts but isn't listing just now (deleted, being moved), for an editable one only.
  The limits (`:20-22`): a name of 200, a description of 1,000, 2,000 songs edited.
- **What is already in Core**: `Paged`, `PagedScope`, `withMore`, `QueueController.extendQueue(token:tracks:next:)`
  and `playTracks(_:start:shuffle:paged:)` - the shuffle's paging, ported with Up Next in Phase 1 (Resume already
  saves `paged` and `pagedRounds`); the feed that asks for the next page is not. `DownloadOrigin` (`.song`,
  `.album(id)`, `.other(raw)`; `.library` is `.other("library")`, `DownloadModels.swift:136`): a `playlist:<id>`
  would read today as `.other`, and the library's fill never takes a non-library origin (byHand = every origin but
  `library`), so a downloaded playlist is never given way - Choice 19 - without a change to the planner.
- **What the app has of "the albums Info knows"**: `PlayerModel.remember` keeps the last 8 album answers
  (`PlayerModel.swift:1260`); the web keeps 8, or every album of a queue of several up to 64 (`lib/playedAlbums.ts`).
  A playlist is a queue of several albums, so slice 1 ports the web's store (2.3).

## 1. Words

### 1.1 The vocabulary

The web's binding words hold (`ui/test/vocabulary.sim.cjs`): "your library", "the collection", never "the store",
"Navidrome" (except where the web's own playlist words name it: "Navidrome made this playlist from a file...",
"It goes from Navidrome for good" - a playlist IS Navidrome's, and the web says so on purpose), "Browse" or
"everything". A playlist's owner is named as Navidrome has them ("Sam's · Shared with you").

### 1.2 Every line

From `ui/src/lib/playlists.ts` (ported verbatim, held by the fixture):

| where | line |
| --- | --- |
| a row, yours | "12 songs · 48 min" (· "Shared" when public) |
| a row, shared with you | "Sam · 12 songs · 48 min" ("Somebody" with no owner) |
| a row, from a file | "From a file · 12 songs" |
| the page, whose | "Yours" / "Yours · Shared with everyone" / "Sam's · Shared with you" / "From a file in the music folders" |
| the page, no Edit | "Only Sam can change this playlist." / the file's sentence / "deadwax edits playlists of up to 2,000 songs - edit this one in Amperfy or Navidrome." |
| the page, count | "12 songs, 48 min" (the hero and the footer) |
| songs not listed | "2 songs in this playlist aren't in the library just now - deleted, or being moved." |
| none | "No playlists yet." |
| gone | "This playlist isn't on Navidrome any more - deleted in another app, maybe." |
| the list failed | "Couldn't list your playlists. <why>" |

From the web's TSX (copied with their source named, as Phase 1's were): "Playlists", "Yours", "Shared with you",
"From files (N)", "Couldn't open this playlist. <why>", "Couldn't update this playlist - showing it as it was. <why>",
"Try again", "Play", "Shuffle", "More for this playlist", "More for <title>". A row's second line is
`[artist, album]` joined with " · ".

**Slice 1's own** (the phone's - section 10, question 6):

| where | line |
| --- | --- |
| an empty playlist | "Nothing in this playlist yet." alone in slice 1 - the web's PLAYLIST_EMPTY's first sentence; since slice 2, when it is true here, the whole of it ("... Add songs from a song's or an album's ••• menu - Add to a playlist - or from Now Playing's ••• while a song plays.") |
| the list, empty | "No playlists yet." alone in slice 1; since slice 2 with PLAYLISTS_EMPTY_HOW under it ("Make one here, or start one from a song's or an album's ••• menu, or from Now Playing: Add to a playlist.") and New playlist |
| the list, deadwax out of reach, none in hand | "Your playlists show here once deadwax is back." |
| a playlist, out of reach, not in hand | "This playlist opens once deadwax is back." |
| a playlist, out of reach, in hand | the songs not on this phone dimmed (as an album's are), Play and Shuffle taking only those that are |

Slice 2's (the web's, verbatim): New playlist, Add to a playlist… (the picker: `pickLine`, "Made Late night with
Roads", `addedWords`, `duplicateQuestion` with "Add it again" / "Add them again" / "Add them all" / "Skip that one" /
"Skip those 3" / "Cancel"), Edit, Done, Saving…, Cancel, "Discard your changes?" (Discard / Keep editing), Name,
Description, "Shared with everyone" with SHARED_NOTE, "A playlist needs a name.", PLAYLIST_CHANGED, `hiddenEditWords`,
Delete playlist with `deleteQuestion` (Delete playlist / Keep it, Deleting…), Move up / Move down / Remove, "Roads: 3
of 12" and "Roads removed" (VoiceOver). As built, also the web's: the picker's "Add to a playlist" (its title), "New
playlist…", "No playlists yet - make one:", "Adding…", "Nothing added - some are in Late night already" and "Couldn't add
to Late night." (both said in the notice when the sheet has closed meanwhile), the menus' "Add to a playlist…",
NewPlaylistForm's Name / Create / Creating… / Cancel, PlaylistsPage's "Made Late night" and PlaylistPage's "Deleted Late
night"; and two of the phone's own: the New playlist sheet's title ("New playlist") and Edit's "Songs" heading. Slice 3's: section 6.3. Slice 3b's: section 6.3b. Slice 4's: `playsLine` ("Plays the 2 albums you have",
"Getting the songs of the 2 albums you have…", "Plays 1 of the 2 albums you have - the rest didn't load",
"Couldn't load their songs.", "None of their albums are here to play."), "Artists", "Your artists", "All artists",
"Name" / "Most albums", the album count line. Slice 5's: "Songs" / "All songs", "Shuffle", "Getting ready…",
"Couldn't get your songs ready to shuffle", "Your shuffle started over - deadwax no longer had its order".

## 2. The rules (DeadwaxCore: pure, tested on Linux)

### 2.1 The list (`PlaylistRules`, slice 1)

- **Groups** (`groupOf`): not mine -> **Shared with you**; mine and editable -> **Yours**; mine and not editable ->
  **From files**. `groups(list)` keeps Navidrome's order within each. The screen draws Yours, Shared with you, then
  From files folded behind one row "From files (N)", each only when it has something.
- **The list is one per person**, in memory: asked as the screen first shows and each time it shows again
  (`fresh`), else not within 30 s of the last answer (PLAYLISTS_FRESH_MS); the newest answer only; a failure with a
  list in hand keeps the list and says so under the title; with none, says why with Try again. A new person drops it.
- **Row lines, whose, no-Edit, the counts, hidden** - `rowLine`, `ownerLine`, `readOnlyWords`, `songCount`,
  `lengthText` (whole minutes by JS Math.round; "1h 5m" from 60), `songsLine`, `hiddenWords`.

### 2.2 A playlist's page (slice 1)

- **Asked as it opens**, drawn at once from the answer kept for it (the last 8 by id, PLAYLISTS_KEPT), else from the
  row that opened it (the hero only); asked again each time it shows after not showing; a refresh that fails keeps what
  is drawn and says so; a 404 is gone (the kept answer let go); nothing drawn and the first ask failing: why, and Try
  again. Only the newest answer draws.
- **The songs** are Navidrome's own, as they are: a song twice is two rows. The total is the songs' own durations
  summed (the web's footer), not the summary's.

### 2.3 Playing one (`PlaylistPlay`, `PlayedAlbums`, slice 1)

- **Each song is queued with its own album** (the web's `toQueueTrack(song, stubFor(song))`): the song's own artist,
  album, cover and format; a song with no album id names none (`albumId` nil - Go to album and Info's album card then
  have nothing to open).
- **At the songs level** (`queued(tracks, 'songs')`): with Normalization's Auto, each song at its own track level -
  a playlist is not an album. Play from the first, Shuffle every song once in a random order Up Next can un-shuffle,
  a row's tap from that song; Play Next and Play Last (a row's •••, the bar's for the whole playlist) as songs.
- **The albums Info knows** (`playlistAlbums`, `withHeld`, `PlayedAlbums.rememberQueue`): one stub per album in the
  order its first song plays, holding the playlist's songs of it, `partial` (Info counts none of the album's from it:
  no "Track 1 of 1", no "1 song"), no MusicBrainz id. An album's own answer held already is kept as it is, never a
  stub over it; an earlier playlist's stub of it keeps its songs beside the new ones. The web's store
  (`lib/playedAlbums.ts`), ported: `remember` (an album's Play: floor 0, the last 8), `rememberQueue` (a queue of
  several albums: every one kept, up to 64, until the next queue), `also` (Play Next or Last: in as the newest, letting
  go of nothing held, up to 64). The album page showing its album is `also` on the phone (the web remembers only on
  play; the phone has kept the page's album for Info since Phase 1). **The phone's own rule (after slice 1's
  review): an album the queue names is never let go.** Every write takes `keeping` - the queue's album ids
  (`QueueAlbums.named`), and those being added - and the trim passes over them, and over the album just put; so a
  page shown, or a Play Next, never lets go of a playlist's album still to play, and a playlist of more than 64 albums
  keeps them all. With `keeping` empty the store is the web's, which the fixture holds. (`also` alone climbs the floor
  by one per page shown, and past 64 lets the oldest go: after `rememberQueue`, the playlist's last album. The web
  has the same eviction, but calls `also` only for Play Next and Play Last.)
- **The gesture rule**: every play is in the tap, the songs in hand, nothing awaited first.
- **Offline**: Play and Shuffle take only the songs on this phone, in the playlist's order; the rest are dimmed. A
  row's tap starts at its place among them (`PlaylistPlay.offlineStart`: counted, since a song listed twice is two
  rows; nil for a row not on this phone).

### 2.4 Add, New, Edit, Delete (slice 2)

As the web, rule for rule: the picker lists `pickerPlaylists` (yours and editable, the one changed last first, ties
by name), adds with `duplicates: ask` first and asks the duplicate question from the answer, New playlist from the
picker makes one with the songs (`madeWords`). Edit (yours, editable, at most 2,000 songs; offered only once this
page's own ask has answered): the name, the description, sharing, the songs removed or reordered (the List's own
`onMove` and one tap on a row's red minus, as Up Next's Edit - question 9 - with Move up / Move down / Remove as
VoiceOver actions), Done sending `editBody` (`base`
the songs as drawn when Edit began, `tried` after a Done that failed); 409 -> drawn as it is now with
PLAYLIST_CHANGED, the page at its top; Cancel with changes asks; Delete asks, there is no undo. `startEdit`,
`moveRow`, `removeRow`, `editChanged`, `editBody`, `isRearrangement` ported and held to the fixture.

As built (PlaylistChanges.swift), beside those: `PlaylistRules.outcome` (an add's answer as the question or the
notice's words), `PlaylistEdit.refusal` (a refused Done: 409 changed elsewhere, 404 gone, anything else refused - Edit
open with why, the next Done sending `tried`), `needsName` and `trimmed` (the web's `.trim()`), `clamped` (a typed name or
description kept within 200 or 1,000 UTF-16 units, as an HTML field's maxLength counts, never cutting a character),
and the picks the menus make (`PlaylistPick` from a QueuePick of songs, or from the song playing).

### 2.5 Downloading a playlist (slice 3)

- **Its own origin** `playlist:<id>` (`DownloadOrigin.playlist(id)`), beside `song`, `album:<id>` and `library` - a
  hand download: never given way, never evicted (Choice 19). Remove Download on the playlist takes that origin
  alone; a song with no origin left goes.
- **The answer kept**: the playlist's last answer is kept with it in the store (a new table, DB version 6), so it
  opens and plays offline - **Downloaded playlists**, on the Library's Downloaded (question 15: not a place of its
  own above the albums - this said "On this phone gains Playlists" until slice 3 was built).
- **Planned whole** (question 14): a downloaded playlist's songs are one unit of the planner, as an album's are - the
  storage limit and the 2 GB reserve checked for all of them at once. After slice 3's review: those not yet started.
  A song of it already on its way (asked for by hand, with your library, or with another playlist) carries on as
  itself, and never lets the rest past the limit.
- **Remove Download elsewhere** (built): a song's own Remove Download, or an album's, is offered only when it would
  take something - a song a downloaded playlist keeps says "Downloaded with Late night" in its menu instead, and
  stays; your library (Phase 3) never takes a playlist's origin.
- **Kept in step** (question 3): the playlists list is read at the library follower's cadence; a playlist whose
  `changed` moved is read again. A song the playlist gained comes; a song it lost goes only when two reads 10 minutes
  apart agree (Phase 3's caution) - or at once after this phone's own Edit, those it took out and only those. While
  Navidrome is hiding at least as many songs as an answer lacks (`hidden`), none of them is marked. A playlist
  missing from two lists 10 minutes apart, or deleted here, lets its origin go. An empty song list is never taken in
  on its own.
- **Smart playlists** (question 16, James: "No Download for them"): one of Navidrome's smart playlists offers no
  Download, and plays only online. Its page says why: "Smart playlists are worked out again each time, so this one
  plays only while deadwax can be reached." One downloaded before deadwax said it was smart stays as it was: never
  read again, nothing asked or taken, with Remove Download as any playlist's. Known by `smart` in the playlist summary
  (section 4).

### 2.6 Artists (slice 4)

- **The list**: Your artists (with a library of your own: the artists of your albums, `yourArtists`, counting your
  albums of theirs) and All artists (`GET /artists`). Sorts Name (deadwax's own folding, `#` last) and Most albums,
  kept per device as `deadwax-player-artist-order`; Find; letter headers and the index for Name. `sortArtistsBy`,
  `groupArtists`, `filterArtists`, `artistOrderFrom` ported and held.
- **The page**: the picture, the name, their albums newest first with yours marked; Play (each album at its album
  level, in order) and Shuffle (every song of them, songs level) over all their albums in the collection - the songs
  asked 4 albums at a time as the page opens, so they are in hand at the tap (`inTurns`); `playsLine` under the
  buttons. Every album remembered (`rememberQueue`). No MusicBrainz discography, description, pins or managing
  (question 4).

### 2.7 Songs and the Library's Shuffle (slice 5; the Shuffle itself built in slice 3b)

**Built in slice 3b** (2.8): the Library's Shuffle of your library - its first page asked ahead, the tap's play path
and the feed, every rule below but Songs and All songs' Shuffle - since the Library's pull shuffles (James,
2026-11-14). Slice 5 adds Songs and, with a library of your own, All songs' Shuffle for the collection, through the
same `ShuffleAhead` (a second one, of the store's scope) and the same feed; and its exporter holds the feed's pure
part (`startingElsewhere`, `songsAhead`) to useShuffleFeed.ts, which 3b holds by hand - its numbers and words are
held by the contract test already (question 24).

- **Songs**: every song, 100 a page (search3 with an empty `q`, SONGS_PAGE), in Navidrome's order; a row opens its
  album (the web's: a fetch-then-play would start the music outside the tap); its ••• is the song's Play Next / Play
  Last. With a library of your own, it is **All music > All songs** (Subsonic can't list your songs alone - question
  2); otherwise **Songs**.
- **Shuffle** (the root's, for your library; with a library of your own, also All songs' for the collection): the
  first page asked as the root shows (again after 10 minutes, SHUFFLE_FRESH_MS), so the tap plays songs in hand;
  "Getting ready…" until then; "Couldn't get your songs ready to shuffle" if it fails. A tap plays the 200 with
  `paged` (the token and the total) and names `playing` on the next ask. **The feed** (useShuffleFeed.ts, ported):
  under 50 songs ahead of the one playing (FEED_BELOW), the next page is asked and added (`extendQueue`); at the end
  under Repeat All, a fresh claimed order; a 404 starts a fresh order and says SHUFFLE_STARTED_OVER once; a failure
  is asked again after 30 s while songs remain. 413 (over 200,000 songs) says the server's words.

### 2.8 The Library's switch, pull to shuffle, and the primary button (slice 3b)

James, 2026-11-14 (the coordinator's words of his, binding): "I'm not a huge fan of the weird section of buttons at the
top of the library page. I like just opening library to your albums." He chose a switch at the top - Albums |
Playlists | Artists | Songs - "and I would also like to be able to swipe left and right between them, and maybe a way
to rearrange the order"; and for the pull, "if you drag down far enough there can be a cool little shuffle graphic
that changes as you pull down, and then once you go far enough, it changes, and starts shuffling when you release" -
choosing "Pull shuffles": the Library's pull never refreshes. And: "the color of the play button on the album page
doesn't show the play icon."

- **The pages** (`LibraryPage`, Core): Albums and Playlists in slice 3b; Artists joins in slice 4, Songs in slice 5.
  **The order** (`LibraryPages`): kept per phone in UserDefaults under `deadwax-library-pages`, the pages' names
  joined with commas ("playlists,albums"), read with care - a name it doesn't know, or a page named twice, left out;
  a page the value doesn't name (one added since, a damaged value, nothing saved) added after the rest in the
  default order (Albums, Playlists, Artists, Songs) - so it is never empty and holds every page once. Edit order's
  move is the List's own (offsets to a destination), the other pages keeping their order; the switch follows it at
  once and the page shown stays shown.
- **Which page shows**: the first of the order as the app opens and when the person changes; after that the one
  last shown (another tab and back, the app back in front). The switch and the swipe set it and each follows the
  other - a swipe once the pager is at rest (slice 3b's review: the page shown is the settled page, the one at the
  pager's centre when it stops, so the switch, the bar, Find and the pulls never change under a finger and a half
  swipe let go changes nothing; iOS 17, with no scroll phase, follows at the swipe's halfway). The Library tab tapped
  at its root scrolls the page shown to its top, as the root list did.
- **Find** is the switch's: one field under the bar, each page with its own words in it. Albums' as before; on
  Playlists it keeps the playlists whose name holds every word typed, in any order and anywhere (Find's folding,
  `PlaylistRules.found`), the groups drawn as before - and none: "No playlists match “…”." (`Find.noMatchText`).
- **The pull** (`PullShuffle`, Core: a state machine, as TurntablePress, Scrub and LyricsHold are). The app feeds it
  how far the page shown is pulled past its top, in points (0 at rest), and whether a finger is on it, and draws what
  it says. **idle** -> **pulling** (its progress, the pull over the line, `line` 110 pt, held under 1) -> **armed** at
  the line: once per arming, the event the haptic tick is drawn from -> pulled back under `line - slack` (100 pt):
  **pulling** again (no tick) -> the finger lifts while armed: **released**, and the shuffle starts in that same call,
  nothing awaited first - then released until the page is back at rest (0), idle after. Lifted while pulling: no
  shuffle; the graphic follows the page back to rest. A pull no finger made (a fling's bounce at the top) stays idle.
  A touch the system takes (slice 3b's review: a call, Siri, Notification Center, the app leaving the front - told by
  the app resigning active, the scene's phase, the audio session's interruption, or the app not active at the lift)
  is **interrupted**: idle, and the finger's going shuffles nothing (`PullShuffle.interrupted`; a release already
  made stays released).
  It arms only when a shuffle can start (`ready`); otherwise the graphic reaches its full ring and says why, and a
  lift does nothing. Every page of the switch pulls the same shuffle (question 21): no page refreshes on a pull now.
  The lists pushed over the switch - All albums, Downloaded, Downloaded playlists - keep their pull to refresh.
- **The Library's Shuffle** (ShuffleSongs.tsx ported: `ShuffleAhead`, Core). Its scope is the Library's: `yours`
  with a library of your own, else `store` (logins off, the break-glass admin). Its first page is asked as the
  Library comes into view - the app opening on it, the tab picked, the app back in front on it, a new person - and
  again when it does so more than 10 minutes after the last ask (SHUFFLE_FRESH_MS, the route's SHUFFLE_LIST_TTL_S),
  the page in hand let go; never twice meanwhile. Ready once a page with songs is in. The ••• Shuffle's tap and the
  pull's release play that page from its first song at the songs level (each at its own track level under Auto, none
  with Off), each song with its album as the answer names it, as a library's shuffle (`paged`: the token, the total,
  the songs fetched, the scope, the level the first song got) - then ask for a new order naming the one just played
  (`playing`), until one gets through, so deadwax claims it. An ask that fails leaves it unready, saying
  "Couldn't get your songs ready to shuffle" - or, for a 413, the server's own words ("Your library is too big to
  shuffle here") - and asks again the next time the Library shows. A scope with no songs at all (`total` 0) offers no
  Shuffle: the ••• leaves it out, and the pull draws nothing. Only the newest answer counts; a new person lets every
  ask go.
- **The feed** (useShuffleFeed.ts ported: `ShuffleFeed`, `ShuffleFeedRun`, Core; PlayerModel carries it out), for any
  queue that is a library's shuffle - this phone's, or one put back paused from the web's or the phone's own. Looked at
  each time the queue or Repeat changes, and on a retry: under 50 of the list's songs after the song playing
  (FEED_BELOW, `songsAhead`), the next page from where the order has got to (`fetched`), added at the end as the list's
  songs (`extendQueue`) at the level the shuffle was queued at; with the whole order in, nothing more under Repeat off
  or One, and under Repeat All a fresh order, asked for claimed, as the next time round, never starting with the song
  that ends this one (`startingElsewhere`). A 404 - the order gone from deadwax (it restarted, or a day untouched) -
  asks a fresh order, claimed, as the rest of this round, and the notice says "Your shuffle started over - deadwax no
  longer had its order" once (not for an empty one). One ask at a time, keyed on the order, `fetched` and, with the
  whole order in, Repeat: what is being asked is never asked again meanwhile. Another shuffle, or none, lets an ask
  go; Repeat moved off All while a fresh round is on its way lets it go, and an answer landing anyway is dropped
  unless Repeat is All. A page that won't come is asked again 30 s later (FEED_RETRY_MS) while the queue has songs -
  and not sooner, though the songs move on meanwhile (`retried`; the web's effect isn't run again by a song changing);
  the music plays on. A fresh order with no songs is appended as nothing and asked for no more. It only ever adds
  to the queue: nothing in it plays.
- **Offline** (the phone's own, question 22): while deadwax can't be reached, Shuffle shuffles every song on this
  phone - a queue of its own (not paged: every one is in hand), in a random order, each song with its own album, at
  the songs level, as a playlist's Shuffle is. The ••• says "Shuffle downloads"; the pull "Pull to shuffle your
  downloads" and "Release to shuffle your downloads". Nothing on the phone: no Shuffle in the •••, and the pull says
  "Nothing on this phone to shuffle" and never arms. Whether there is something is the very list the shuffle plays
  (slice 3b's review): a song here with no kept answer to play it by isn't counted, and a list emptied between the
  draw and the release says "Nothing on this phone to shuffle" and plays nothing. It is read only while offline.
- **The Library's •••** (`LibraryMenu`, its items Core's): Shuffle (or "Getting ready…", dimmed; offline "Shuffle
  downloads"; none with nothing to shuffle); then Downloaded - or, offline, where the Albums page is Downloaded, the
  way back to the albums ("Your albums", "Albums" without a library of your own); All music (with a library of your
  own and online: the store's albums, pushed); then Refresh (Your albums and the playlists asked now, whatever their
  age - or, offline, whether deadwax is back) and Edit order. Its button reads "More for the Library".
- **The primary button** (`PrimaryButton`, Core's colours, held to theme.css by tests/test_ios_palette.py): the
  web's (app.css .app-rg-get, player.css .pl-pill.is-primary) - --dw-primary-bg, #a24ef2 to #8a2ee0 top to bottom;
  a 1 pt edge of --dw-primary-border #7c3aed; --dw-primary-highlight, a 1 pt line of white at 0.22 inside the top
  edge; --dw-radius-control's 4 pt corners; the label white (--dw-text), semibold; pressed, --dw-primary-pressed
  (brightness 0.92) on the fill and the edge, the label left white (slice 3b's review: the web's filter darkens the
  whole button, its label to #ebebeb - 4.13:1 at the pressed top and under 4.5:1 a fifth down - so the phone departs
  from it there, for the label); disabled, faded to 0.45 (Palette.off). The large one is the web's pill,
  48 pt (--pl-pill-height). It replaces `.borderedProminent`, whose fill was the app's tint, #C084FC - the web's
  accent for text on black - under a white label: 2.64:1. Measured (`Contrast`, WCAG 2's relative luminance; Core,
  tested): white on #8a2ee0 5.92:1, on the middle of the gradient 5.05:1, a fifth of the way down - the top of a
  label's line on the 48 pt button - 4.57:1, and on #a24ef2 at the very top edge, where no glyph is drawn, 4.28:1;
  pressed, 4.92:1 and 6.72:1; the edge against white 5.70:1. So the label passes AA (4.5:1) wherever it is drawn, and
  the play glyph - a graphic, 3:1 - everywhere. Every `.borderedProminent` in the app takes it (the album's and the
  playlist's Play, Your library's Add, the EQ's Use for, the picker's Create, the sign-in, Try again on the
  unreachable and Navidrome gates, Set up Navidrome); a `.bordered` button beside one in the same pair takes the
  web's secondary pill (--dw-secondary-bg, the look button's face) so the pair is one shape (question 25). Pressed,
  the pill's gradient turns over (--dw-secondary-bg-active, .pl-pill:active: lit from below, neither lighter nor
  darker).

## 3. The screens

### 3.1 The Library's root (slice 3b: the switch; 4: Artists; 5: Songs)

**Since slice 3b** (2.8, James's): the switch. The bar holds the switch in its middle - a segmented control,
Albums | Playlists in the order chosen - with the page's own buttons and the Library's ••• at its right (Albums: the
order and Show as list/grid; Playlists: New playlist's +), and Find under it. Under them, the pages side by side: a
swipe left or right moves between them, the switch following, and a tap on the switch moves the page (at once under
Reduce Motion). The Albums page is the albums alone, from the top: their count, then the albums - no rows above them.
The Playlists page is 3.2's list, drawn as rows of the same height, cover, words and chevron. Pulling either page
down shuffles (2.8, 3.5).

What went from the top of the albums: the first ask's card (question 17: now at the top of Downloaded), Playlists
(the switch's), All music > All albums and On this phone > Downloaded (the •••'s). Downloaded playlists stays at the
top of Downloaded (question 15), now reached from the •••.

While deadwax can't be reached (the root's rule, Phase 2's 5.4, unchanged - the Albums page changes only off screen,
question 19): the same switch; the Albums page is Downloaded - its heading, Downloaded playlists' row when there are
any, "Only downloaded albums play until deadwax is back." and the albums on the phone - and the Playlists
page lists as it does offline (question 5, slice 3's downloaded ones). The way back to the albums is the •••'s. When
Navidrome can't be reached, the Navidrome gate is drawn in the switch's place, as before.

(Phase 1 to slice 3, superseded: the albums with places above them - Playlists, All music, On this phone - and the
first ask's card over them; question 1.)

### 3.2 Playlists (slice 1)

Large title "Playlists"; Yours, Shared with you (each a heading and its rows), From files (N) as a disclosure row
opening its rows in place for the screen's life. A row: the cover (Navidrome's 2x2 mosaic, or the playlist symbol on a
quiet square for none) at the rows' 48 pt, the name, `rowLine`, the chevron; a tap opens the playlist, nothing plays.
Pull to refresh asks now (since slice 3b a page of the switch: no title of its own, and the pull shuffles - 3.1).
Empty: "No playlists yet." Slice 2 adds New playlist to the bar - built as the bar's +
(dimmed while deadwax can't be reached), opening a sheet with the name: Create makes an empty playlist and opens its
page once the sheet has gone (question 12); and, empty, PLAYLISTS_EMPTY_HOW and a New playlist button under the line.

### 3.3 A playlist (slice 1)

As an album's page: the hero (the mosaic at 280, or the symbol; the name, two lines, smaller over 60 letters;
`ownerLine`; why there is no Edit, when there is none; the description; `songsLine`; Play and Shuffle), the hidden
line, a refresh's failure line, the songs, the footer. A row: the song's own cover (48 pt), the playing bars over it
for the song playing, its title, "artist · album", the download slot (as an album's rows: only when a song of it has a
state), its time, its ••• (Play Next, Play Last, the song's download items). The bar: the title once the hero's has
scrolled away, and the ••• for the whole playlist (Play Next, Play Last; no download items until slice 3 - question
7). Gone: the gone line alone. Slice 2 adds Edit to the bar; slice 3 the download control beside the •••.

Slice 2's Edit, as built: Edit in the bar (yours and editable only; dimmed until this page's own ask has answered,
and while deadwax can't be reached); in Edit the hero stays (Play and Shuffle dimmed, as the web's) and the hidden
line gives way to a form - the name, "A playlist
needs a name." under a blank one, the description (two to six lines), Shared with everyone (its note the hint), and
`hiddenEditWords` - then "Songs", each row its title and artist with the red minus and the drag handle, then Delete
playlist last (question 11); the bar has Cancel (asking `discardQuestion` when anything changed) and Done (Saving…;
dimmed with a blank name), the back button hidden while Edit is open - and the tab tapped again goes back no further
than the page. Nothing is saved until Done answers, and the page then draws the server's answer, never what was
typed.

### 3.4 VoiceOver and Dynamic Type

A playlist row reads its name and its line as one ("Late night, 12 songs · 48 min"); From files (N) is a button whose
value is "collapsed" / "expanded"; a song row reads "Roads, Portishead · Dummy, 5:04", "playing" or "paused" for the
one the player has, and its download state; its ••• is "More for Roads"; the bar's is "More for this playlist". At the
accessibility sizes the rows' text wraps (three lines for a title) and Play and Shuffle stack.

### 3.5 The pull's graphic, and Edit order (slice 3b)

**The graphic** rides above the page's first row, in the room the pull opens, and follows it. Pulling: a ring round
the shuffle mark, filling as the pull nears the line, the mark growing from 0.6 to its full size and turning a half
turn by the line; its line under it, "Pull to shuffle". Armed: the ring a solid disc in the primary's purple, the mark
white on it, with a light haptic tick as it changes; "Release to shuffle". Released: "Shuffling", the mark going round
once while the page settles. Not ready: the ring and the mark as pulling, never the disc, and why: "Getting ready…",
"Couldn't get your songs ready to shuffle" (or the server's words), "Nothing on this phone to shuffle". Offline, its
words are the downloads' (2.8). Nothing at all is drawn with no songs to shuffle. **Reduce Motion**: the mark keeps its
size and doesn't turn or go round; the ring still fills with the finger (a measure, not a motion) and the states swap
at once. A touch the system takes (2.8) leaves nothing drawn. **VoiceOver** doesn't read it - the ••• Shuffle is the way there (and Switch Control's); the haptic is only
the touch's. **iOS 17** can't read how far a List or a ScrollView is pulled without iOS 18's scroll geometry, so
there is no pull on 17, only the ••• Shuffle (the app's target is 17; James's phone is on 27).

**Edit order**: the •••'s Edit order opens a sheet titled "Edit order" - the pages as rows, each with its drag handle
(a List held in edit mode, no deletions), "Drag the pages into the order you want. The Library opens on the first." as
its footer, Done in its bar. Kept as each move is made.

## 4. The server

**One field** (slice 3's review, question 16): `smart: bool` in each playlist summary (src/playlists.py `summary()`),
from Navidrome's playlist. It is James's, on main as its own 2.1.x. The phone reads it ahead of the server, as false
when it is absent, so it builds and runs without it. Otherwise every route Phase 4 reads or writes exists (section 0's
table) and answers what the web already reads. Two things looked at and left: a route listing *your* songs alone
(Subsonic can't; the web's answer, followed here, is Songs as the collection's with your songs through your albums
and the Shuffle - question 2), and a playlist's `changed` on the list being enough to keep a downloaded playlist in
step (it is: Navidrome moves it on every add and removal, `notes/playlists.md`), so no new "changed since" route.

## 5. The machinery (for the builders)

### 5.1 Core, and the App

| Core (pure, tested on Linux) | App (wires it) |
| --- | --- |
| `Playlists.swift` - `Playlist`, `PlaylistWithSongs`, `PlaylistList`, `PlaylistGroup`, `PlaylistRules` (groups, lines, words, kept) | `PlaylistsModel` - the one list per person, a page's answers kept (8), reset on a new person |
| `PlaylistPlay.swift` - `albums` (stubs), `withHeld`, `tracks` (songs level), the picks for a row and for the whole playlist | `PlayerModel.play(playlist:at:shuffle:)`, `choose(_:_:album:)` with no album for a playlist's songs |
| `PlayedAlbums.swift` - lib/playedAlbums.ts | `PlayerModel`'s albums for Info, Go to album and the turntable |
| `Album.partial`, `AboutAlbum(album:)` passing it | Info, unchanged |
| `Routes.playlists`, `Routes.playlist`; `DeadwaxClient.playlists()`, `playlist(id:)` | `PlaylistsScreen`, `PlaylistView`, `AppRoute.playlists` / `.playlist`, the root's row |
| slice 2: `PlaylistChanges.swift` - the four writes' bodies and answers, the picker's order, the picks, the add words and question, `PlaylistEdit` (Edit's rows, moves, removes, the body, a refusal's meaning); 4 routes (36) | `PlaylistsModel`'s writes (each telling the list and the pages, `lastChange`), `PlaylistPageModel`'s Edit and Delete, `PlaylistPicker` (MainTabs' sheet, and Now Playing's own), `NewPlaylistFields`, New on Playlists |
| slice 3: `DownloadOrigin.playlist`, `PlaylistDownloads` (the keeping-in-step rules, the control, the rows), `DownloadRemoval`; store v6 | `PlaylistKeeper` (DownloadModel's), the playlist's control and ••• items, Downloaded > Downloaded playlists, You > Downloads' rows |
| slice 4: the artist sorts and lines; 2 routes | Artists, an artist's page |
| slice 3b: `LibraryPage`/`LibraryPages`, `PullShuffle`, `ShuffleAhead`, `ShuffleFeed`/`ShuffleFeedRun` (and, since its review, `ShuffleFeedLoop`: PlayerModel's feed carried out over a QueueController), `ShuffleHere`, `PlaylistRules.found`, `PrimaryButton`/`Contrast`; 2 routes (38) and `DeadwaxClient.shuffleStart`/`shufflePage` | the switch and its pages (LibraryView, AlbumsScreen as a page, PlaylistsPage), the ••• and Edit order, the pull's graphic, `ShuffleModel`, `PlayerModel.play(shuffled:)` and the feed, the primary and secondary button styles |
| slice 5: Songs; the feed held to the web (5.2) | Songs, All songs' Shuffle |

### 5.2 Held to the web

`ios/scripts/export-playlist-vectors.cjs` compiles `ui/src/lib/playlists.ts` and `ui/src/lib/playedAlbums.ts` with the
repo's TypeScript and writes `Fixtures/playlists/playlist-vectors.json`; `ui/test/iosplaylists.sim.cjs` runs it with
`--check`. Slice 2 adds the edit and add rules to the same file; slice 4 adds `lib/shelves.ts`' artist rules and
`lib/artistPage.ts`' `playsLine` (to export-library-vectors.cjs or a new file); slice 5 the feed's pure part (built in slice 3b: its behaviour held by hand until then, over shuffle.sim.cjs's own
cases; its numbers and words already held by tests/test_ios_contract.py, read from ShuffleSongs.tsx and
useShuffleFeed.ts - question 24).

## 6. The slices

### 6.1 Slice 1 - playlists, read and play

Core: 2.1-2.3 (Playlists, PlaylistPlay, PlayedAlbums, `Album.partial`, the two routes and the client's calls) with the
fixture and the sim. App: PlaylistsModel; the root's Playlists row; the Playlists screen; a playlist's page with Play,
Shuffle, a row's tap and the two •••; offline as 1.2 says. PlayerModel's albums become PlayedAlbums. No writes, no
downloads of a playlist, the app's version left at 0.9.

### 6.2 Slice 2 - Add to a playlist, New, Edit, Delete

The picker (a sheet: New playlist at its top, then `pickerPlaylists`; the duplicate question; the notice), from a
song's and an album's ••• (the album page's rows and bar, a playlist's rows and bar) and Now Playing's •••; New playlist
on the Playlists screen (a name, then its page); Edit and Delete on a playlist's page; the full empty words. The list
and the kept pages told of every write (the web's `announcePlaylistChanged`). Built: 6.7.

### 6.3 Slice 3 - Download a playlist

The control in a playlist's bar (Download, then the ring and the mark, as an album's), its ••• items, the hero's line,
the rows' marks; `DownloadOrigin.playlist(id)`; the store's `playlist` table (id, the answer as deadwax sent it, when
read, the songs missing since when) at DB version 6; keeping in step (2.5); Downloading's row per playlist ("Late
night - 3 of 12 songs to go"); Downloaded > Downloaded playlists (question 15; this said On this phone > Playlists
until it was built); Remove Download; Remove All taking playlists too. Words: "Download", "Remove Download" (Phase
2's), "Downloaded with Late night" (a song's menu title), "This playlist is downloaded - it plays with no
connection.", "Downloaded playlists" (the place). After its review: "Smart playlists are worked out again each time,
so this one plays only while deadwax can be reached." (a smart one's page) and "Smart playlists are worked out again
each time, so this download stays as it was when you made it." (one downloaded before deadwax said it was smart).
Built: 6.8.

### 6.3b Slice 3b - the Library's switch, pull to shuffle, the Play button (James's, 2026-11-14)

The switch (Albums | Playlists) with the swipe, the order and Edit order, Find on both pages, the rows above the
albums gone and the Library's •••, the first ask's card moved to Downloaded (2.8, 3.1); the pull's machine and its
graphic (3.5); the Library's Shuffle - its first page asked ahead, the play path, the feed, the two routes, offline
(2.7, 2.8); the primary button and the secondary pill beside it (2.8). The app stays 0.9 (9); no server change.

Words (the phone's own unless named): "Albums" and "Playlists" (the switch); "More for the Library" (the •••'s
button); "Shuffle", "Getting ready…" and "Couldn't get your songs ready to shuffle" (ShuffleSongs.tsx), "Shuffle
downloads", "Downloaded" (Phase 2's), "Your albums" / "Albums" (Phase 1's titles), "All music" (Phase 1's), "Refresh",
"Edit order"; the sheet's "Edit order", "Drag the pages into the order you want. The Library opens on the first." and
"Done"; the pull's "Pull to shuffle", "Release to shuffle", "Shuffling", "Pull to shuffle your downloads", "Release to
shuffle your downloads", "Nothing on this phone to shuffle"; the notice's "Your shuffle started over - deadwax no
longer had its order" (useShuffleFeed.ts); the 413's "Your library is too big to shuffle here" (the server's);
Find's "Find in playlists" and "No playlists match “…”."; Downloaded's own note, "Only downloaded albums play until
deadwax is back." (Phase 2's).

### 6.4 Slice 4 - Artists

The root's Your artists (or Artists), All music > All artists with a library of your own; the list (tiles or rows,
the round picture; the sorts, Find, the index); an artist's page (2.6); Go to the artist from an album's artist line
(today plain text: it becomes the link the web has).

### 6.5 Slice 5 - Songs and the Library's Shuffle (app 0.10)

Songs (2.7), with All songs' Shuffle for the collection on slice 3b's Shuffle and feed; the feed's fixture; the app's
version 0.10 (10) with everything pinned to it; docs/ios.md and README for the phase.

### 6.6 Slice 1, built (2026-11-13)

What slice 1 is, as built, is in notes/ios.md's "Phase 4, slice 1: playlists, read and play" - what Core and the app
hold, what was decided where this spec was silent, the tests and what was verified.

### 6.7 Slice 2, built (2026-11-13)

What slice 2 is, as built, is in notes/ios.md's "Phase 4, slice 2: Add to a playlist, New, Edit, Delete" - Core and the
app, what was decided here, the tests and mutations, and what was verified. Questions 9-13 came of it.

### 6.8 Slice 3, built (2026-11-14)

What slice 3 is, as built, is in notes/ios.md's "Phase 4, slice 3: Download a playlist" - Core (PlaylistDownloads,
the store's version 6) and the app (PlaylistKeeper, the control, the rows), what was decided here, the tests and
mutations, and what was verified. Questions 14-15 came of it. Downloaded playlists sit under the Library's Downloaded,
where the Library's switch (slice 3b, James's 2026-11-14) wants them. Its review's fixes, and question 16: "Phase 4,
slice 3, after its review".

### 6.9 Slice 3b, built (2026-11-14)

What slice 3b is, as built, is in notes/ios.md's "Phase 4, slice 3b: the Library's switch, pull to shuffle, the Play
button" - Core and the app, what was decided here, the tests and mutations, and what was verified. Questions 17-26
came of it.

## 7. Tests (Swift Testing; Core's on Linux and macOS)

- **The fixture's replay** (slice 1): every rule of 2.1 and 2.3 over the web's own answers - groups, every line under
  every kind of playlist (yours, shared, public, file, no owner, none, 1, 2,000 and 2,001 songs, lengths 0, 59 s, 89 s,
  59.5 min, 60 min, 65 min, 10 h), hidden 0/1/2, the words, `playlistAlbums` over songs with and without album ids,
  years, covers, album artists, a song twice and albums interleaved; `withHeld` over none, a whole one, a stub with
  overlapping songs; PlayedAlbums driven through remember / rememberQueue / also / get sequences at the bounds.
- **By hand** (slice 1): a playlist's songs as queue tracks (own album, no album id -> nil, the songs level under
  each Normalization setting); the picks for a row and the bar; the routes' answers decoded (a list, one, an empty
  `{}` playlists key, a playlist with no songs, a field of the wrong type read leniently); Info's `partial`.
- **The contract** (tests/test_ios_contract.py): ROUTE_COUNT 32; `Playlist`'s and `PlaylistWithSongs`' fields within
  what `summary()` and `with_songs()` send.
- **Mutations** run by hand and caught (notes/ios.md lists each): the groups swapped, the songs level made the album
  level, `withHeld` putting a stub over a whole album, `rememberQueue`'s floor, a song with no album id keeping "".
- **Slice 2's fixture** (the same file): `pickerPlaylists` over six lists - none; every slice 1 playlist; changed to the
  millisecond, one never changed; ties by name with case and accents folded, a whole tie keeping the list's order, and shared, from-a-file
  and not-mine-but-editable playlists left out; `pickLine`, `madeWords`, `addedWords` (ten answers, every mode) and
  `duplicateQuestion` (nine already-of-asked pairs) over seven picks - one song (with an artist, an empty one, none),
  two songs, eleven, a song twice, no songs; `hiddenEditWords` at -1, 0, 1, 2 and 10; `startEdit` over four songs with one
  listed twice, every `moveRow` from -1 to 4 to -2 to 5, every `removeRow` from -1 to 4, `editBody` and `editChanged`
  over fifteen changes from three starts (renamed, spaces round a name - a BOM, a no-break space, a tab - and U+0085,
  which JS keeps; a description cleared; shared; rows moved, moved back, removed, all removed; a twice-listed song's two
  rows swapped; everything at once), and `isRearrangement` over nine pairs. The one rule the fixture can't hold, the
  picker's tie on names equal once folded (ICU's and the phone's differ there), is held by hand.
- **Slice 2 by hand**: the bodies' JSON keys (none sent for nil), the add's three answers decoded (leniently), the four
  calls (POST, the cookie, the paths, the delete with no body), a refusal's words through ErrorWords (409, 403, 422),
  `outcome`, `refusal`, the picks from a QueuePick and the song playing, Edit's rows, `needsName` and `trimmed` (a
  BOM and a no-break space trimmed, U+0085 kept), `clamped` (at the bound, and a character of two UTF-16 units across
  it).
- **The contract** (slice 2): the three bodies' keys exactly the extra="forbid" models' fields, the required sent, only
  fields with a default optional; the duplicates the route's Literal; the bounds the server's; the add's three answers
  and the delete's within what the app decodes; the statuses the phone reads where the routes raise them.
- **Slice 3** (PlaylistDownloadTests, PlaylistDatabaseTests): the origin's raw form read back and as Phase 2 reserved
  it; what each Remove Download takes and what stays; the staying choices; the library never taking a playlist's
  origin; the planner's playlist unit, planned whole under the limit and the reserve; every rule of keeping in step
  (`listed`, `missing`, `read`, `actions`, `orphans`, `dueReads`, `nextLook`, `due`) at the 10-minute bounds; the
  control's state, items and lines; the rows' progress and words; the store's `playlist` table written, read back,
  an unreadable row kept; Remove All; and a real version-5 file brought to version 6 with every row of every table
  kept. No new route: ROUTE_COUNT stays 32, and the playlist's body is kept as deadwax sent it.
- **Slice 3's review** (PlaylistDownloadTests, PlaylistKeepingTests): a started song never letting its playlist past
  the limit or the reserve; a song two playlists share; an Edit's own removals and songs Navidrome is hiding; a mark
  from the future; a list at the moment of a download; the rows' rules; the keeper's order (a write before its
  effects, nothing after a failed write or take, an older answer dropped); smart playlists. The contract reads
  `smart` ahead of the server (`PLAYLIST_AHEAD`).

- **Slice 3b** (LibrarySwitchTests, PullShuffleTests, ShuffleTests, PrimaryButtonTests): the order read from every
  kind of value (nothing, one page, both, reversed, a name unknown, a page twice, spaces, a damaged value) and written
  back; each move of the List's; the first page. The pull through every path - pulling, armed at the line and not a
  point before, one tick per arming, disarmed under the slack and not at it, released on a lift only while armed and
  ready, at rest after, a bounce with no finger never pulling, not ready never arming. The Shuffle ahead: asked as it
  shows, not again inside 10 minutes and again past them, ready only with songs, the tap's tracks and `paged`, the ask
  after it naming the order played until one gets through, a failure asked again the next time it shows, an older
  answer dropped, a new scope or person starting afresh, total 0. The feed: nothing for a plain queue or with 50
  ahead, a page at 49 from `fetched`, one ask at a time whatever changes meanwhile, an answer for a superseded ask
  dropped, the whole order in under Off and One nothing and under All a fresh claimed round never starting with the
  song ending - at once when a short last page leaves the music near its end - a 404 starting over said once (not for
  an empty order), a failure retried only when its retry is due (and a retry due after another ask letting nothing
  go), a page queued at the shuffle's level, Repeat turned off with a round on its way; and (slice 3b's review)
  `ShuffleFeedLoop` over the real QueueController and a fake engine, answers late or failing, retries, held edits, Play
  Next and Repeat moving - every song once a round under Off and All, no round beginning with the song ending the last
  - with a lost order started over said once and a stop letting every ask and the retry go; `startingElsewhere` and `songsAhead` by hand over the web's own cases (shuffle.sim.cjs). The two
  answers decoded (leniently), the two calls (paths, `scope`, `playing`, `claim`, `offset`). Offline: every song here,
  each once. Find on playlists. The contrast: WCAG's own pairs, and the primary's numbers in 2.8.
- **The contract** (slice 3b): ROUTE_COUNT 38; `ShuffleStart`'s and `ShufflePage`'s fields what the routes return;
  `PagedScope`'s raw values the route's Literal; `ShuffleAhead.freshSeconds` the route's SHUFFLE_LIST_TTL_S and
  ShuffleSongs.tsx's SHUFFLE_FRESH_MS; `ShuffleFeed.below` and `retrySeconds` useShuffleFeed.ts's FEED_BELOW and
  FEED_RETRY_MS; "Getting ready…", the unready line and the started-over notice the web's own constants; the 413's
  words the route's own. tests/test_ios_palette.py: `PrimaryButton`'s colours, edge, highlight, pressed, corner and
  height theme.css's and player.css's; no `borderedProminent` however spelled in ios/App's code; the secondary pill's
  pressed gradient theme.css's reversed. The pull interrupted: idle, nothing shuffled. Pressed, white on the darkened
  fill AA all the way down, and the web's darkened label not.

## 8. James's checks (on his iPhone)

Numbered after Phase 3's 63. Slice 1's:

- **64 Your playlists.** Library > Playlists: the same playlists as the web app's, under Yours and Shared with you, and
  From files folded (if you have any). Each row says what the web's row says.
- **65 Playing one.** Open a playlist of songs from several albums: Play plays it in order; Shuffle in a random order;
  a song's tap from that song. Each song shows its own album's cover in the mini player and on the lock screen.
  Info > About on a song names its own album and year, and says "Track 5" alone - no "of 12", and no disc line,
  since the app holds only the playlist's songs of that album. Then, playing, open a dozen album pages or more and skip
  to the playlist's last songs: Info still names each one's album (2.3's `keeping`).
- **66 Normalization.** With Normalization on Automatic, play a playlist: Info > About > Sound > Normalization says
  "Song volume matching, ..." for each song, never "Album volume matching".
- **67 Play Next from a playlist.** A row's •••: Play Next and Play Last queue that song; the bar's ••• queues the whole
  playlist. Go to album from Now Playing opens the song's own album.
- **68 Changed elsewhere.** Add a song to a playlist in the web app or Amperfy; back on the phone, go back to the list
  and open the playlist again: it has the song. Delete a playlist in the web app with its page open on the phone, and
  pull down on it: it says it has gone.
- **69 Offline.** Download a song of a playlist (its •••), then turn on Airplane Mode with the playlist open: only that
  song is bright and plays. Back on the Library (it may open on Downloaded): Playlists is there and that playlist
  opens; one not opened, or with nothing on the phone, is dimmed. And scrolling a long playlist, and VoiceOver's rows.

docs/ios.md's "Playlists' checks (64-69)" holds them as James reads them.

The phase's (the plan's three, with slices 2, 3 and 5): make a playlist on the phone and see it in the web app and
Amperfy (slice 2's **70**); download it and play it offline (slice 3's **77**); shuffle the whole library and let it
run past the first 200 songs - numbered with slice 5 (this said 71 and 72 before slice 2 was built; each slice numbers
its own after the last). Each slice adds its own.

Slice 2's:

- **70 Make one** (the phase's). Library > Playlists > +: a name, Create - its page opens, empty, with the whole
  empty line. Then it is in the web app's Playlists and Amperfy's, under the same name.
- **71 Add to a playlist.** An album's •••, an album page's song's, a playlist's song's and its bar's, and Now Playing's
  •••: Add to a playlist… opens the picker, its head what it adds ("Dummy · 11 songs", "Roads · Portishead"), your
  playlists the one changed last first; a tap closes it and the notice says "Added 11 songs to Late night". New
  playlist… in the picker makes one with them ("Made Late night with Roads"). In the web app, the songs are there. A
  tap, the picker closed while it says Adding…, opened again (or Now Playing's): still Adding…, the songs added once.
- **72 Already in it.** Add the same album again: "These 11 songs are all in Late night already." (Add them again /
  Cancel); with one of them there: "1 of these 11 songs is in Late night already." (Add them all / Skip that one); one
  song: "Roads is in Late night already." (Add it again / Cancel). Each does what it says.
- **73 Edit.** On a playlist of yours: Edit - rename it, change the description, share it, drag a song, take one out
  with its red minus (one tap), Done: Saving…, then the page as Navidrome has it; the web app agrees. A blank name
  says "A playlist needs a name." and Done is dimmed. Cancel after a change asks "Discard your changes?". The name
  stops at 200 typed or pasted; the tab tapped again stays on the playlist; a Done refused goes to why.
- **74 Changed elsewhere.** Open Edit on the phone, add a song to that playlist in the web app, then change something
  on the phone and Done: it says the playlist changed in another app and your changes weren't saved, and shows it with
  the web app's song.
- **75 Delete.** Edit > Delete playlist > the question > Delete playlist: back on Playlists, "Deleted Late night", and
  it has gone from the web app and Amperfy. New playlist's sheet swiped away straight after Create, and opened again:
  the second keeps its name.
- **76 Only yours, and offline.** A playlist shared with you, or from a file: no Edit, and the picker never lists it.
  In Airplane Mode: no Add to a playlist… in the ••• menus or Now Playing's, and + and Edit dimmed. With VoiceOver, in
  Edit: each song's actions (Move up, Move down, Remove), and what is said ("Roads: 3 of 12", "Roads removed").

docs/ios.md's "Playlists' changes' checks (70-76)" holds them as James reads them.

Slice 3's:

- **77 Download one and play it offline** (the phase's). The arrow, the ring, "Downloading - 4 of 12 songs", the
  Downloading row; then "This playlist is downloaded - it plays with no connection."; then in Airplane Mode after a
  force quit, Downloaded > Downloaded playlists opens it and every song plays, each with its own album's cover; and
  Library > Playlists lists it, bright.
- **78 Kept in step.** A song added in the web app comes; one taken out there stays on the phone until a look ten
  minutes on agrees; one taken out with Edit here goes at once.
- **79 What stays.** A song downloaded by hand, or with an album, stays after the playlist's Remove Download; a song
  only the playlist brought says "Downloaded with …" with no Remove Download; turning Download your library off keeps
  the playlist's songs.
- **80 Where it is.** Downloaded playlists; You > Downloads' Downloaded with the playlist first and its songs under no
  album row; a swipe's Remove; Remove All's question saying they go too.
- **81 Deleted.** Deleted here: gone at once. Deleted in the web app: stays ten minutes or more, then goes.
- **82 Room.** Under the storage limit the whole playlist waits; nothing half-fetched.
- **83 VoiceOver.** The control's label and values; a Downloading row read as one.
- **84 Smart playlists** (once main sends `smart`). A smart playlist: no arrow, nothing to download in its •••, and
  the line saying why. One downloaded before: kept as it was, Remove Download still there.

docs/ios.md's "Downloaded playlists' checks (77-84)" holds them as James reads them.

Slice 3b's:

- **85 The switch.** The Library opens on Albums, with nothing above the albums but their count; Albums | Playlists in
  the bar. Swipe left: Playlists, the switch, the bar and Find following as the page settles; half a swipe let go
  springs back and changes nothing; tap Albums: back. Leave for You and come back: the same
  page. Scroll down a long way and tap the Library tab: the page shown goes to its top. Force-quit and open: Albums.
- **86 Edit order.** ••• > Edit order: drag Playlists above Albums, Done. The switch reads Playlists | Albums; force-quit
  and open: the Library opens on Playlists.
- **87 The •••.** Downloaded opens what's on the phone (its first ask's card at the top, once, on a phone that never
  answered it); All music opens All albums (with a library of your own); Refresh asks now (a playlist made in the web
  app shows); Shuffle plays your library shuffled.
- **88 Pull to shuffle.** On Albums, pull down slowly: the ring fills and the mark grows and turns, "Pull to shuffle";
  at the line a tick, the purple disc, "Release to shuffle"; push back up a little: the ring again, no tick; down again:
  a tick. Let go armed: "Shuffling", and your library plays shuffled - the mini player, a song from anywhere in it. Let
  go before the line: nothing plays. The same on Playlists. A fast fling to the top shows nothing. Armed, then pull
  down Notification Center (or ask Siri, or take a call) before letting go: nothing plays.
- **89 Past the first 200** (the phase's). With the shuffle playing, skip ahead with Next 160 times or so (or let it
  play an evening): Up Next keeps going, never ending at 200; with Repeat off it ends only once every song of your
  library has played. With Repeat All, at the end a new round starts with a different song.
- **90 Started over.** Shuffle, then restart deadwax (or leave the phone a day) and skip ahead past 150: "Your shuffle
  started over - deadwax no longer had its order", once, and the music carries on.
- **91 Offline.** Airplane Mode: the Library on Downloaded's albums under the same switch; ••• > Shuffle downloads, and
  the pull's "Release to shuffle your downloads": only songs on the phone, every one of them in time. ••• > Your albums
  is the way back. With nothing downloaded: no Shuffle, and the pull says "Nothing on this phone to shuffle".
- **92 The Play button.** An album's page and a playlist's: Play is the web's purple with a white triangle and word,
  plainly readable; Shuffle beside it the web's grey pill, the same height and corners. Pressed, Play darkens, its
  label staying white, and Shuffle's shading turns over, as the web's do. The other
  purple buttons - Add to my library, the EQ's Use for, Create in the picker, Sign in, Try again - the same purple.
- **93 Find on Playlists.** On Playlists type part of a name: only the playlists that hold it; nonsense: "No playlists
  match “…”."; back on Albums, Find holds its own words.
- **94 VoiceOver and Reduce Motion.** The switch reads "Albums, 1 of 2" (or as iOS words it); the ••• reads "More for
  the Library", Shuffle first. With Reduce Motion on, the pull's mark doesn't grow or turn, the states change at once,
  and a tap on the switch moves the page without sliding.

docs/ios.md's "The Library's switch's checks (85-94)" holds them as James reads them.

## 9. What only the phone can tell

- That the mosaic covers (`pl-<id>_<hash>`) come through deadwax's cover route at the rows' and the hero's sizes as
  Navidrome makes them (only fakes here).
- That a playlist of a few hundred songs draws and scrolls smoothly (a plain List of rows, each with its own cover).
- That the lock screen and the mini player show each song's own album cover as a playlist plays across albums.
- That Navidrome's real `changed` and `owner` (its case, an admin's view) group the playlists as the web does.
- Slice 2's: that TextFields and a Toggle answer inside a List in edit mode; that the red minus (a borderless button
  in an edit-mode row) takes one tap and doesn't open the row; that a sheet opens from a Menu's action (the picker from
  every •••) and from Now Playing's full-screen cover; that confirmation dialogs anchored on the bar's Cancel and on
  Delete playlist show where they should; the notice over Now Playing; and Navidrome's real `changed` moving on every
  write, so the picker's order and the 409 behave as against the fakes.
- Slice 3's: that Navidrome's real `changed` moves on an add or removal made in another app, so a list's look reads the
  playlist again (only fakes here; the page's own ask takes it in either way); that a Menu with a header and no items
  (a song's ••• with nothing to offer but "Downloaded with …") shows its header; that the control sits beside the
  ••• in the bar as the album's does; that a downloaded playlist's songs, from many albums, fetch in the background
  and on a locked phone as an album's do; and how long a playlist of a few hundred songs takes to be planned and
  asked for (one transaction, one plan).
- Slice 3's review: that a real Navidrome's getPlaylists and getPlaylist carry `validUntil` for a smart playlist,
  including one never yet worked out (the field main's `smart` can be read from, going by the source at 46c4327); and
  that a rename's Done while a song's file is being moved keeps that song.

- Slice 3b's: that a horizontal paging ScrollView of two pages, each its own vertical ScrollView, swipes and scrolls
  as one would hope - a vertical scroll never pages, a sideways swipe on the letter index pages or not (question
  18), Find and the bar sitting over both; that iOS 18's scroll geometry reads the pull under Find's drawer from 0
  at rest; that the scroll's phase leaves `interacting` the moment a finger lifts, so the release starts the music
  then; that the tick lands at the line and not twice; that the graphic sits in the room the pull opens on every
  text size; that the feed's asks are answered on a locked phone mid-shuffle (the phone runs while it plays); and the
  primary's purple on James's screen as the web's.
- Slice 3b's review: that iOS 18's scroll phase reaches `.idle` once a swipe settles (the page shown follows only
  then) and that a layout's move at rest is followed; that the system taking a touch is told before the scroll's
  phase leaves `.interacting` - the app resigning, the scene's phase, the audio session's interruption, or the app's
  state at the lift - and so a pull a call or Siri cut short shuffles nothing; a banner call over an active app, with
  no audio interruption, can't be told from a lift.

## 10. Open questions (each with what the build does until James answers)

1. **The Library's top level.** Apple Music's Library is a list of rows (Playlists, Artists, Albums, Songs,
   Downloaded) with Recently Added under it; the web's phone has a root of rows too. Phase 1's answer (library.md
   Open question 1) opened the tab straight on the Albums. *Recommend, and built*: keep it - the albums with the places
   above them, Playlists the first; Your artists, Songs and Shuffle join them in slices 4-5. A list of rows would put a
   tap between the Library and every album. **Superseded by James (2026-11-14, slice 3b)**: the switch - Albums |
   Playlists | Artists | Songs, swiped between, in an order he chooses - and nothing above the albums (2.8, 3.1).
2. **"All your songs".** Subsonic can't list a person's songs alone (search3 with an empty query is the collection's).
   *Recommend*: as the web - Songs is the collection's (All music > All songs with a library of your own), and your
   songs come through your albums and the Shuffle, which deadwax builds from your albums.
3. **A downloaded playlist's songs removed elsewhere.** *Recommend*: Phase 3's caution - a song goes from the phone
   only when two reads 10 minutes apart agree it has gone from the playlist, or at once after an Edit made here.
4. **The artist page's MusicBrainz parts** (discography, description, facts, Get). *Recommend*: left out in Phase 4 -
   they are Search and Get's (Phase 5-6); the page is their albums in the collection, Play and Shuffle.
5. **Playlists offline.** *Recommend*: in slices 1-2 a playlist plays offline only from the answer the app has in
   memory, and only its songs on this phone; slice 3's downloaded playlists are kept on disk and open offline.
6. **The empty words in slice 1.** The web's how-lines name Add to a playlist and New playlist, which slice 1 hasn't.
   *Recommend, and built*: their first sentences alone until slice 2 ("No playlists yet.", "Nothing in this playlist
   yet."). Slice 2 built: the whole lines now.
7. **The bar's ••• and downloads in slice 1.** *Recommend, and built*: no download items for the whole playlist until
   slice 3, so a playlist's songs are never downloaded as loose songs that slice 3 couldn't tell from hand downloads; a
   row's ••• keeps the song's own items (a hand download of that song).
8. **The album page's own album for Info.** The phone has kept the album a page shows for Info since Phase 1; the web
   remembers only on play. *Recommend, and built*: kept as `also`, so showing an album page never lets go of a
   playlist's albums mid-play.
9. **Removing a song in Edit.** The spec said swipe to delete; iOS draws no swipe in a List in edit mode, and Up
   Next's Edit (James's choice, Phase 1) is one tap on a red minus. *Recommend, and built*: the same one tap - nothing
   is saved until Done, and Cancel puts everything back, so a mistaken tap costs nothing.
10. **Writes while deadwax can't be reached.** *Recommend, and built*: none are queued for later - Add to a playlist…
    is left out of the ••• menus and Now Playing's while offline, and New (+) and Edit are dimmed; a playlist is
    Navidrome's, changed from other apps too, and a write held for later could land on a playlist that has changed
    since.
11. **Where Delete lives.** *Recommend, and built*: inside Edit, last, as the web has it - two deliberate steps and a
    question before a deletion there is no undo for; not in the bar's •••, which plays and queues.
12. **New playlist on the Playlists screen.** The web opens its form in place. *Recommend, and built*: the bar's +
    opens a sheet with the name (the phone's way); Create makes an empty playlist and opens its page. In the picker,
    New playlist… opens the name in place of its row, as the web's.
13. **One write at a time in the picker.** The web lets a playlist's tap through while a New playlist… is being made.
    *Recommend, and built*: every row and New playlist… wait for the write that is out, so one tap is one write and a
    second tap never adds the songs twice - across every opening of the picker and both its openers (the tabs' and Now
    Playing's), as the web's one picker's `writing` lasts (built so after the review: the first build's gate was each
    opening's own).
14. **A downloaded playlist and the room.** Planned song by song, a playlist bigger than the room left would fetch
    its first songs and stop; planned whole, it waits until all of it fits. *Recommend, and built*: whole, as an
    album is (Phase 2's units) - a playlist downloaded to play offline is useless half there, and a hand download
    never gives way. A song of it also asked for with its album goes in the album's unit; the rest are one unit,
    the first downloaded playlist's by id when a song is in two.
15. **Where downloaded playlists live.** The spec said the Library's On this phone gains Playlists. James's
    redesign of the Library (2026-11-14, slice 3b: the Library's switch) moves Downloaded into the Library's •••
    and takes the places rows away. *Recommend, and built*: **Downloaded playlists** is a row at the top of the
    Downloaded screen (pushed, or the root while deadwax can't be reached), with how many - no place of its own
    above the albums - and the Playlists screen, offline with no list in hand, lists the downloaded ones. Their
    mosaic covers aren't kept with the download (a cover route of their own, with no kept file): offline, the
    cover cache's or the empty cover.
16. **Smart playlists** (slice 3's review). Navidrome works a smart playlist out again each time it is read, so a
    download of one would chase a list that moves on every look. **James: "No Download for them."** Built: no
    Download and no download items; the page says why ("Smart playlists are worked out again each time, so this one
    plays only while deadwax can be reached."); one downloaded before deadwax said it was smart is kept as it was -
    never read again, nothing asked or taken - with Remove Download as any playlist's, and let go once two lists
    agree it has gone. Ordinary and .m3u-synced playlists download as before. The server sends `smart` from main's
    2.1.x; until then the phone can tell no playlist is smart (`readonly` is true for .m3u-synced ones and anyone
    else's too), so none is treated as one.
17. **Where the first ask went** (slice 3b). Its card sat at the top of the albums - the rows James took away.
    *Recommend, and built*: at the top of Downloaded (pushed from the •••, or the Albums page while deadwax can't be
    reached), once per phone as before and only while deadwax can be reached - where downloading is what is on the
    screen; the setting stays in You > Downloads. A phone that never opens Downloaded is never asked, which is the
    point: the Library opens to music. Not a dialog at launch (Phase 3's question 1).
18. **The swipe and swipes of rows'.** Neither page has a row with a swipe action (a playlist's and an album's actions
    are their ••• menus and their pages'), so the pages' sideways swipe takes nothing from a row. *Recommend, and
    built*: keep it so - a page that joins the switch (Artists, Songs) puts a row's actions in its •••, never in a
    swipe. The letter index down Albums' right edge is a vertical drag; whether a sideways drag that begins on it pages
    is the phone's to say (section 9).
19. **The switch while deadwax can't be reached.** *Recommend, and built*: the same switch. The Albums page is
    Downloaded (Phase 2's 5.4 rule, unchanged: it changes only off screen), headed so, with Downloaded playlists'
    row and the line saying only what's downloaded plays; Playlists lists as it does offline. The •••'s Downloaded
    becomes the way back to the albums ("Your albums"), All music goes, Shuffle shuffles the downloads, Refresh asks
    whether deadwax is back. A switch that changed its pages offline would move under a finger as the connection
    came and went.
20. **The Library's Shuffle without the pull** (VoiceOver, Switch Control, anyone who doesn't pull). *Recommend, and
    built*: the •••'s first item, Shuffle - "Getting ready…" dimmed until its page is in. Not a button over the
    albums: that is the row of buttons James took away.
21. **Which pages pull to shuffle.** *Recommend, and built*: every page of the switch, the same shuffle of your
    library - no page refreshes on a pull now (Refresh is the •••'s), and a gesture that did different things on
    different pages would have to be relearnt on each. Lists pushed over the switch keep pull to refresh.
22. **Shuffle while deadwax can't be reached.** The web's Shuffle is deadwax's order. *Recommend, and built*: shuffle
    every song on this phone ("Shuffle downloads") - offline, only those play, and they are all in hand, so the queue
    is complete with no paging; with nothing on the phone, no Shuffle and the pull says so. Saying "can't" would
    leave the gesture dead exactly when the phone is all there is.
23. **Edit order's form.** *Recommend, and built*: a sheet from the •••, the pages as rows with drag handles (a List
    in edit mode), kept per phone as each move is made, the switch following at once. A page added later (Artists,
    Songs) joins at the end of an order already saved, so nobody's order is rearranged for them.
24. **The feed held by hand until slice 5.** useShuffleFeed.ts's pure part lives in a hook file that imports Preact,
    and the exporters compile pure lib files. *Recommend, and built*: its numbers and words held to the web's files
    now - tests/test_ios_contract.py reads FEED_BELOW, FEED_RETRY_MS and SHUFFLE_STARTED_OVER from useShuffleFeed.ts,
    and SHUFFLE_FRESH_MS and the two Shuffle lines from ShuffleSongs.tsx - and its behaviour (`startingElsewhere`,
    `songsAhead`, the run) by hand in 3b, over shuffle.sim.cjs's own cases; slice 5's exporter compiles the hook with
    shuffle.sim's Preact stand-in, as that sim does, and holds the behaviour too. Moving the two functions into a lib
    file would be a web change, main's to make.
25. **The primary's shape, and the button beside it.** iOS 26 draws `.borderedProminent` as a capsule; the web's
    primary has 4 pt corners. *Recommend, and built*: the web's button, corners and all - one look across the web app
    and the phone, as the turntable's look button already is - and a `.bordered` button paired with a primary (the
    album's and the playlist's Shuffle, the unreachable gate's Change address, the picker's Cancel) the web's
    secondary pill, so a pair is one shape. Other `.bordered` buttons stay the system's until James sees these.
26. **Room in the bar for four pages.** The switch sits in the bar's middle with the page's own buttons at its right
    (Albums: the order and the layout, then the •••). Albums | Playlists fits any phone; Albums | Playlists | Artists |
    Songs at a large text size won't, beside three buttons. *Recommend* (for slices 4-5, nothing built yet): the order
    and the layout move into the ••• then, leaving the switch and the ••• alone in the bar.
