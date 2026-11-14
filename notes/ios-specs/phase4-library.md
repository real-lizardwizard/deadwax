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
  | `GET /deadwax/navidrome/shuffle` (`:1014`) | `{token, total, songs}` (the first 200) | 5 |
  | `GET /deadwax/navidrome/shuffle/{token}` (`:1057`) | `{total, songs}` from `offset`; 404 "gone" | 5 |

  tests/test_ios_contract.py's ROUTE_COUNT moves 30 -> 32 (slice 1), 36 (2), 38 (4), 40 (5).
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
| an empty playlist (slice 1) | "Nothing in this playlist yet." - the web's PLAYLIST_EMPTY's first sentence; its second ("Add songs from a song's or an album's ••• menu - Add to a playlist...") comes with slice 2, when it is true here |
| the list, empty (slice 1) | "No playlists yet." alone - PLAYLISTS_EMPTY_HOW ("Make one here, or start one from...") with slice 2 |
| the list, deadwax out of reach, none in hand | "Your playlists show here once deadwax is back." |
| a playlist, out of reach, not in hand | "This playlist opens once deadwax is back." |
| a playlist, out of reach, in hand | the songs not on this phone dimmed (as an album's are), Play and Shuffle taking only those that are |

Slice 2's (the web's, verbatim): New playlist, Add to a playlist… (the picker: `pickLine`, "Made Late night with
Roads", `addedWords`, `duplicateQuestion` with "Add it again" / "Add them again" / "Add them all" / "Skip that one" /
"Skip those 3" / "Cancel"), Edit, Done, Saving…, Cancel, "Discard your changes?" (Discard / Keep editing), Name,
Description, "Shared with everyone" with SHARED_NOTE, "A playlist needs a name.", PLAYLIST_CHANGED, `hiddenEditWords`,
Delete playlist with `deleteQuestion` (Delete playlist / Keep it, Deleting…), Move up / Move down / Remove, "Roads: 3
of 12" and "Roads removed" (VoiceOver). Slice 3's: section 6.3. Slice 4's: `playsLine` ("Plays the 2 albums you have",
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
`onMove` and swipe to delete, with Move up / Move down / Remove as VoiceOver actions), Done sending `editBody` (`base`
the songs as drawn when Edit began, `tried` after a Done that failed); 409 -> drawn as it is now with
PLAYLIST_CHANGED, the page at its top; Cancel with changes asks; Delete asks, there is no undo. `startEdit`,
`moveRow`, `removeRow`, `editChanged`, `editBody`, `isRearrangement` ported and held to the fixture.

### 2.5 Downloading a playlist (slice 3)

- **Its own origin** `playlist:<id>` (`DownloadOrigin.playlist(id)`), beside `song`, `album:<id>` and `library` - a
  hand download: never given way, never evicted (Choice 19). Remove Download on the playlist takes that origin
  alone; a song with no origin left goes.
- **The answer kept**: the playlist's last answer is kept with it in the store (a new table, DB version 6), so it
  opens and plays offline - the Library's **On this phone** gains **Playlists** (downloaded ones).
- **Kept in step** (question 3): the playlists list is read at the library follower's cadence; a playlist whose
  `changed` moved is read again. A song the playlist gained comes; a song it lost goes only when two reads 10 minutes
  apart agree (Phase 3's caution) - or at once after this phone's own Edit. A playlist missing from two lists 10
  minutes apart, or deleted here, lets its origin go. An empty song list is never taken in on its own.

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

### 2.7 Songs and the Library's Shuffle (slice 5)

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

## 3. The screens

### 3.1 The Library's root (slice 1: Playlists; 4: Artists; 5: Songs and Shuffle)

Phase 1's root stays (question 1): the albums, with places above them. Slice 1 adds one row at the top, under the
first ask's card, **Playlists** (the playlist symbol, no count), pushing the Playlists screen. It is on the Downloaded
root too (the Library's root while deadwax can't be reached), under the way back to the albums: without it, the
playlists in hand that question 5 lets play offline could be reached only from a screen already open (changed as
slice 1 was built; this said "not while the root is Downloaded"). Slices 4 and 5 add Your artists, Shuffle and Songs
beside it.

### 3.2 Playlists (slice 1)

Large title "Playlists"; Yours, Shared with you (each a heading and its rows), From files (N) as a disclosure row
opening its rows in place for the screen's life. A row: the cover (Navidrome's 2x2 mosaic, or the playlist symbol on a
quiet square for none) at the rows' 48 pt, the name, `rowLine`, the chevron; a tap opens the playlist, nothing plays.
Pull to refresh asks now. Empty: "No playlists yet." Slice 2 adds New playlist to the bar.

### 3.3 A playlist (slice 1)

As an album's page: the hero (the mosaic at 280, or the symbol; the name, two lines, smaller over 60 letters;
`ownerLine`; why there is no Edit, when there is none; the description; `songsLine`; Play and Shuffle), the hidden
line, a refresh's failure line, the songs, the footer. A row: the song's own cover (48 pt), the playing bars over it
for the song playing, its title, "artist · album", the download slot (as an album's rows: only when a song of it has a
state), its time, its ••• (Play Next, Play Last, the song's download items). The bar: the title once the hero's has
scrolled away, and the ••• for the whole playlist (Play Next, Play Last; no download items until slice 3 - question
7). Gone: the gone line alone. Slice 2 adds Edit to the bar; slice 3 the download control beside the •••.

### 3.4 VoiceOver and Dynamic Type

A playlist row reads its name and its line as one ("Late night, 12 songs · 48 min"); From files (N) is a button whose
value is "collapsed" / "expanded"; a song row reads "Roads, Portishead · Dummy, 5:04", "playing" or "paused" for the
one the player has, and its download state; its ••• is "More for Roads"; the bar's is "More for this playlist". At the
accessibility sizes the rows' text wraps (three lines for a title) and Play and Shuffle stack.

## 4. The server

**Nothing is needed.** Every route Phase 4 reads or writes exists (section 0's table) and answers what the web
already reads. Two things looked at and left: a route listing *your* songs alone (Subsonic can't; the web's answer,
followed here, is Songs as the collection's with your songs through your albums and the Shuffle - question 2), and a
playlist's `changed` on the list being enough to keep a downloaded playlist in step (it is: Navidrome moves it on
every add and removal, `notes/playlists.md`), so no new "changed since" route.

## 5. The machinery (for the builders)

### 5.1 Core, and the App

| Core (pure, tested on Linux) | App (wires it) |
| --- | --- |
| `Playlists.swift` - `Playlist`, `PlaylistWithSongs`, `PlaylistList`, `PlaylistGroup`, `PlaylistRules` (groups, lines, words, kept) | `PlaylistsModel` - the one list per person, a page's answers kept (8), reset on a new person |
| `PlaylistPlay.swift` - `albums` (stubs), `withHeld`, `tracks` (songs level), the picks for a row and for the whole playlist | `PlayerModel.play(playlist:at:shuffle:)`, `choose(_:_:album:)` with no album for a playlist's songs |
| `PlayedAlbums.swift` - lib/playedAlbums.ts | `PlayerModel`'s albums for Info, Go to album and the turntable |
| `Album.partial`, `AboutAlbum(album:)` passing it | Info, unchanged |
| `Routes.playlists`, `Routes.playlist`; `DeadwaxClient.playlists()`, `playlist(id:)` | `PlaylistsScreen`, `PlaylistView`, `AppRoute.playlists` / `.playlist`, the root's row |
| slice 2: the edit rules and the add words; 4 routes | the picker sheet, New, Edit, Delete |
| slice 3: `DownloadOrigin.playlist`, the keeping-in-step rules; store v6 | Download a playlist, On this phone > Playlists |
| slice 4: the artist sorts and lines; 2 routes | Artists, an artist's page |
| slice 5: the shuffle feed's rules; 2 routes | Songs, the Shuffle button, the feed |

### 5.2 Held to the web

`ios/scripts/export-playlist-vectors.cjs` compiles `ui/src/lib/playlists.ts` and `ui/src/lib/playedAlbums.ts` with the
repo's TypeScript and writes `Fixtures/playlists/playlist-vectors.json`; `ui/test/iosplaylists.sim.cjs` runs it with
`--check`. Slice 2 adds the edit and add rules to the same file; slice 4 adds `lib/shelves.ts`' artist rules and
`lib/artistPage.ts`' `playsLine` (to export-library-vectors.cjs or a new file); slice 5 the feed's pure part.

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
and the kept pages told of every write (the web's `announcePlaylistChanged`).

### 6.3 Slice 3 - Download a playlist

The control in a playlist's bar (Download, then the ring and the mark, as an album's), its ••• items, the hero's line,
the rows' marks; `DownloadOrigin.playlist(id)`; the store's `playlist` table (id, the answer as deadwax sent it, when
read, the songs missing since when) at DB version 6; keeping in step (2.5); Downloading's row per playlist ("Late
night - 3 of 12 songs to go"); On this phone > Playlists; Remove Download; Remove All taking playlists too. Words:
"Download", "Remove Download" (Phase 2's), "Downloaded with Late night" (a song's menu title), "This playlist is
downloaded - it plays with no connection.", "Downloaded playlists" (the place).

### 6.4 Slice 4 - Artists

The root's Your artists (or Artists), All music > All artists with a library of your own; the list (tiles or rows,
the round picture; the sorts, Find, the index); an artist's page (2.6); Go to the artist from an album's artist line
(today plain text: it becomes the link the web has).

### 6.5 Slice 5 - Songs and the Library's Shuffle (app 0.10)

Songs (2.7) and the Shuffle button with its feed; the app's version 0.10 (10) with everything pinned to it; docs/ios.md
and README for the phase.

### 6.6 Slice 1, built (2026-11-13)

What slice 1 is, as built, is in notes/ios.md's "Phase 4, slice 1: playlists, read and play" - what Core and the app
hold, what was decided where this spec was silent, the tests and what was verified.

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

The phase's (the plan's three, with slices 2, 3 and 5): **70** make a playlist on the phone and see it in the web app
and Amperfy; **71** download it and play it offline; **72** shuffle the whole library and let it run past the first
200 songs. Each slice adds its own.

## 9. What only the phone can tell

- That the mosaic covers (`pl-<id>_<hash>`) come through deadwax's cover route at the rows' and the hero's sizes as
  Navidrome makes them (only fakes here).
- That a playlist of a few hundred songs draws and scrolls smoothly (a plain List of rows, each with its own cover).
- That the lock screen and the mini player show each song's own album cover as a playlist plays across albums.
- That Navidrome's real `changed` and `owner` (its case, an admin's view) group the playlists as the web does.

## 10. Open questions (each with what the build does until James answers)

1. **The Library's top level.** Apple Music's Library is a list of rows (Playlists, Artists, Albums, Songs,
   Downloaded) with Recently Added under it; the web's phone has a root of rows too. Phase 1's answer (library.md
   Open question 1) opened the tab straight on the Albums. *Recommend, and built*: keep it - the albums with the places
   above them, Playlists the first; Your artists, Songs and Shuffle join them in slices 4-5. A list of rows would put a
   tap between the Library and every album.
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
   yet.").
7. **The bar's ••• and downloads in slice 1.** *Recommend, and built*: no download items for the whole playlist until
   slice 3, so a playlist's songs are never downloaded as loose songs that slice 3 couldn't tell from hand downloads; a
   row's ••• keeps the song's own items (a hand download of that song).
8. **The album page's own album for Info.** The phone has kept the album a page shows for Info since Phase 1; the web
   remembers only on play. *Recommend, and built*: kept as `also`, so showing an album page never lets go of a
   playlist's albums mid-play.
