# Phase 5 - Search: what the iPhone app shows and does (app 0.11)

Design spec for the iPhone app's Phase 5 ("Search"), read 2026-11-14 at `ios` 3458122 (app 0.10 (10), server
2.1.23). Area: the Search tab - one list, Apple Music's way, as the web's Search: Top results, then Artists, Albums and
Songs, yours first in each, then what nobody here has yet from MusicBrainz; chips narrowing it to one kind; a song you
have playing in the tap; an album you don't have opening its MusicBrainz page, with room on it for Phase 6's Get - with
the phase's checks. Every path is repo-relative and every line number is the code's at 3458122.

**What binds it.** The plan (`~/Desktop/Code/deadwax-ios-plan.md`, outside the repo): James's answers at its top (the
app talks only to deadwax; a free account; no Simulator); its section 5's "Phase 5 - Search" ("one list, Apple Music's
way, as the web's Search: Top results, then Artists, Albums and Songs, yours first in each (`/navidrome/search`), then
MusicBrainz's (`fully_search`, `songs`, `artists`, `saved`). An album you don't have opens its MusicBrainz page.";
checks "search a song you have (it plays); search an album you don't (its MusicBrainz page opens)"); section 2's
routes table ("Search | `/navidrome/search`, `/search_musicbrainz/{fully_search,songs,artists,saved,release_group,
release,discography,artist}`"); section 4's offline rule ("Search, Get, Requests and managing say they need deadwax,
and show nothing stale as if live"). Phase 6 (Get and Requests) is not this phase's: the album you don't have leaves
room for Get and builds none of it. Then what is built: Phases 1-4 (`notes/ios.md`) - the player, the queue menus,
the downloads, the Library's albums, artists, playlists and songs - which this phase opens and plays through and
rebuilds none of.

**Where the words come from.** The web app has every one of these features, so its words and rules are the app's -
ported, and held to its TypeScript by a committed exporter wherever they are pure (as every port since Phase 1 is).
The web's files: `ui/src/lib/searchList.ts` (the list's rules and words: rows, whose, the pool, the sections, Top
results, the moments, the lines), `ui/src/lib/searchQuery.ts` (the box's reading and the queries), `ui/src/lib/
searchResults.ts` (the hint, the busy words, the prefetch, MusicBrainz's groups' words), `ui/src/lib/songs.ts` (song
search: titleKey, the grouping, the album a song names), `ui/src/lib/whose.ts` and `ui/src/lib/owned.ts` (what is
yours, what is held), `ui/src/app/Search.tsx` (the wiring, the state, the moments as drawn), `ui/src/app/
SearchRows.tsx` (the rows), `ui/src/app/searchAnswers.ts` (the kept answers), `ui/src/app/useOwned.ts`,
`ui/src/app/ReleaseGroupPage.tsx` (the album you don't have) with `ui/src/lib/pressings.ts`; `notes/
app-requests-search-get.md` ("Search, and albums you don't have (2.0.0-player.13)", "Song search (2.0.0-player.53)",
"Search like Apple Music (2.0.0-player.55)"). Where the phone has something the web hasn't (offline), the words are
new and listed in section 1.

## 0. The foundation - checked

- **The branch.** `phase5-search`, from `ios` 3458122, clean. `src/__init__.py` says `2.1.23`;
  `ios/Config/Base.xcconfig:11-12` say `MARKETING_VERSION = 0.10`, `CURRENT_PROJECT_VERSION = 10`. Phase 5's commits
  leave both alone until its last slice, which makes the app **0.11 (11)** with check_project.py, ios.yml,
  tests/test_ios_install.py, ios/README.md and docs/ios.md pinned with it (as 0.3 to 0.10 were).
- **Whose answers.** Every route below is the person's own: `/navidrome/*` asks Navidrome as the person signed in
  (`client_for(request)`), `/library/owned` says per album whether it is in the asker's own library (`yours`, logins
  on), and `/search_musicbrainz/*` is MusicBrainz's answer, the same for everyone (cached on disk since
  2.0.0-player.54). The app sends the person's cookie and nothing else, as every route since Phase 1.
- **The routes** (all exist; only `/navidrome/search` is in the app's `Routes` today, as `Routes.search`, which Songs
  pages):

  | route | answers | slice |
  | --- | --- | --- |
  | `GET /deadwax/navidrome/search` (`src/routes/navidrome.py:351`) | `{artists, albums, songs}`: search3 as the asker, `q` (at most 200 characters), `artistCount` (<= 50), `artistOffset`, `albumCount` (<= 50), `albumOffset`, `songCount` (<= 500), `songOffset` | 1 (gains `artistOffset`, `albumOffset`) |
  | `GET /deadwax/library/owned` (`src/routes/library.py:354`) | `{albums: [{path, artist, album, year, edition, release_mbid, release_group_mbid, formats, track_count, albumartist_mbids, yours?}], problem}` with an ETag (304 when unchanged); `yours` only with logins on and a ledger readable | 1 |
  | `GET /deadwax/navidrome/artists` (`:398`, already `Routes.artists`) | the library's every artist - Top results' family and the artist the box named | 1 (no change) |
  | `GET /deadwax/navidrome/album_index?scope=yours` (already `Routes.albumIndex`) | your albums - what is yours, and each artist's count of yours | 1 (no change) |
  | `GET /deadwax/navidrome/albums/{album_id}` (already `Routes.album`) | an album's songs - what lets a song's tap play | 1 (no change) |
  | `GET /deadwax/search_musicbrainz/fully_search` (`src/routes/search_musicbrainz.py:49`) | release groups for a query (`limit`, `releases`, `offset` <= `FULLY_SEARCH_OFFSET_MAX`, `quick`) | 2 |
  | `GET .../release_group` (`:322`) | one group's every pressing with its tracklist (`{id, releases, problem}`) - the album you don't have, as the web's page reads it (question 15) | 2 |
  | `GET /deadwax/coverart/{kind}/{mbid}?size=` (`src/routes/coverart.py`, server 2.1.24) | a release's or a group's front cover from the Cover Art Archive, through deadwax (question 8) | 2 |
  | `GET /deadwax/store/album?release_mbid=` (already `Routes.storeAlbum`) | Navidrome's album of a release you hold - a held album opening yours | 2 (a query added) |
  | `GET .../artists` (`:155`) | MusicBrainz artists by name (`limit` 10 by default, `offset`) | 3 |
  | `GET .../songs` (`:109`) | recordings for a query (`limit`, `offset`), grouped into songs on the phone | 3 |
  | `GET .../artist` (`:360`), `GET .../discography` (`:245`) | a MusicBrainz artist, and their release groups - a MusicBrainz artist's page (question 9) | 3 |
  | `GET .../saved` (`:203`) | what MusicBrainz answered before, searched under any words (`words`) | 4 |

  tests/test_ios_contract.py's ROUTE_COUNT moves 40 -> 41 (slice 1: `/library/owned`), 44 (2: `/fully_search`,
  `/release_group` and the covers' relay - question 15), 48 (3), 49 (4).
- **What search3 answers.** Navidrome's search3, passed on as it is: `artists` (ArtistID3: id, name, coverArt,
  albumCount, musicBrainzId, starred...), `albums` (AlbumID3: id, name, artist, artistId, coverArt, songCount,
  duration, year, genre, starred, musicBrainzId, created...), `songs` (Child: id, title, album, albumId, artist,
  artistId, coverArt, track, year, duration...). Navidrome matches what is typed against the starts of words
  (searchList.ts's `matchTier` leans on it); an empty `q` answers everything (Songs' paging, Phase 4). The phone reads `albums` and
  `songs` today (`SearchResult`, `Models.swift`), which the contract test pins as exactly those two; Search reads all
  three through a new lenient `LibraryResults` beside it, leaving `SearchResult` as Songs reads it.
- **What `/library/owned` is for.** The web asks it as Search first shows, beside each MusicBrainz search, and on a
  filing (`app/useOwned.ts`): its album artists are names the box is read against (2.1), its release ids say whose
  an album is when Navidrome hasn't starred it (`navidromeYours`, 2.2), and from slice 2 its release and group ids say
  which of MusicBrainz's albums you already have. It answers from the saved scan unless the library is behind (a
  filing, a retag), when it walks the library first - seconds on a spun-down array. One album is about 300 bytes of
  JSON; the ETag makes every ask after the first a 304 until the library changes.
- **What is already in Core**: `Fold.key` (the web's `foldName`, scalar for scalar), `JSText.trim` / `lowercase`,
  `Whose.inYourLibrary` / `inTheCollection` / `heldPhrase`, `Artist` and `YourArtists` (slice 4 of Phase 4), `Album`
  and `Song` (lenient), `QueuePick.song(_:of:)`, `PlaylistPlay.pick(song:)`, `OfflineAlbum.playable`,
  `NavidromeGate`, `ErrorWords`, `DeadwaxClient.fetch(ifNoneMatch:)`. Not in Core: the box's reading, titleKey,
  `/library/owned`'s answer and index, anything of the list.
- **The tabs.** `ios/App/Shared/Routes.swift:6` - `AppTab { library, you }` (Phase 1's screens.md "Tabs in Phase 1":
  "Home, Search, Requests appear with their phases"); the web's five are Home, Library, Search, Requests, You
  (`ui/src/lib/appRoutes.ts:64`), You at the right end.

## 1. Words

### 1.1 The vocabulary

The web's binding words hold (`ui/test/vocabulary.sim.cjs`): "your library", "the collection", never "the store" -
and, since 2.0.6 (UX batch 3), never MusicBrainz's name in a line a listener reads: what is searched is "your
library", "the collection" and "albums you don't have yet" / "albums nobody has yet". "Search" is the tab's title and
the keyboard's key.

### 1.2 Every line (slice 1's; later slices' are the web's same files' and are listed with them)

| where | words | source |
| --- | --- | --- |
| the tab | Search, `magnifyingglass` | TabBar.tsx; SF Symbol |
| the page's title | Search | Search.tsx:2165 |
| the box's prompt | Artists, albums and songs | Search.tsx:2178 |
| the box (VoiceOver) | Search for artists, albums and songs | searchResults.ts `searchWords().label` |
| an empty box - slice 1 | Search your library. / Search your library and the collection. (a library of your own) | the phone's own, question 3 |
| an empty box - slice 2 on | Search your library and albums you don't have yet. / Search your library, the collection, and albums nobody has yet. | searchResults.ts:31, :37 |
| the chips | All, Artists, Albums, Songs (VoiceOver: the group is "Show") | Search.tsx:2158, :2190 |
| asking | Searching your library… / Searching the collection… | searchResults.ts:33, :39 (`searching(false)`) |
| the sections | Top results; Artists; Albums; Songs; See all (VoiceOver: "See all artists") | Search.tsx:1849, SearchRows.tsx:59, :396 |
| an artist's line | 2 albums in your library (yours, with a library of your own), else `artistLine`: 12 albums in your library / 12 albums in the collection; in Top results "Artist" first | searchList.ts:986, searchResults.ts:205 |
| an album's line | Portishead · 1994 · in your library (Top results: Album · Portishead · 1994 · ...) | searchList.ts:1009 |
| a song's line | Portishead · Dummy · in your library (Top results: Song · Portishead · Dummy · ...) | searchList.ts:1019 |
| the place (logins on) | in your library / in the collection / nothing while it can't be told | whose.ts:150 `libraryPlace` |
| a song that plays (VoiceOver) | ", plays it from its album" / ", opens its album" | SearchRows.tsx:219 |
| a song's ••• | More for Roads | SearchRows.tsx:203 |
| what the list found (VoiceOver, announced) | In your library: 1 artist, 2 albums, 11 songs. / In the collection: ... | searchList.ts:1044 `libraryWords` |
| a chip pressed (announced) | Showing everything. / Showing albums. | searchList.ts:1123 `viewWords` |
| nothing found | No results for “dummy”. / No albums for “dummy”. - then "Check the spelling or try a new search." (All) | searchList.ts:1128, Search.tsx:1902 |
| the library failed | the failure's words (ErrorWords) and Try again | Search.tsx:1845 |
| a kind view's more | More from your library / More from the collection; Loading…; Try again | Search.tsx:2073 |
| ...and what it brought (announced) | 8 more albums from your library / 1 more song from the collection | Search.tsx:672 |
| Navidrome not there | the Library's gate words (NavidromeGate), above the list | NeedsNavidrome.tsx; the phone's NavidromeGate |
| offline, nothing drawn | Search works once deadwax is back. | the phone's own (Songs' and Playlists' shape), question 5 |
| offline, a list drawn | the list stays, songs not on this phone dimmed (VoiceOver: "Not on this phone") | the phone's own, as Songs (Phase 4 question 34) |

Slice 2 adds the web's MusicBrainz words (searchList.ts:1053-1135 - `musicBrainzWords`, `failureWords`, `foldWords`,
`emptyWords`, `libraryLateWords`, `TYPE_MORE`, `STUDIO_NOTE`; searchResults.ts' group kinds and years; the album you
don't have's, pressings.ts). Slice 3 adds songs.ts' and the artists' (`SONGS_NEED_A_TITLE`, the disclosure's).

## 2. The rules (DeadwaxCore: pure, tested on Linux)

### 2.1 The box's reading (`SearchReading`, slice 1; searchQuery.ts)

- **The words.** The box, trimmed (JavaScript's trim), split on runs of JavaScript white space. None: no reading, and
  the list is the hint. At most `SEARCH_MAX_CHARS` 200 characters typed (the box takes no more - the server's `q` is
  200 at most).
- **The names.** `artistNames`: `/library/owned`'s album artists (each trimmed, each once - useOwned.ts:61) then
  search3's artists of this answer (Search.tsx:420), keyed by `foldName`, the first spelling kept; "va" and "various
  artists" name Various Artists unless the library has them.
- **The reading** (`searchQuery`, :117): the whole box a name - `artist`; else the longest name at either end (at one
  length, the start before the end) with words left once separators (`- – — : / | · •`) are stripped from the rest -
  `album-by-artist`, that artist and that title; else `free`. The query MusicBrainz is asked (`artist:"A"`,
  `releasegroup:"T" AND (artist:"A" OR artistname:"A")`, the free words) is the reading's too, ported with it and
  first used in slice 2.
- **When it is read.** As the list is drawn for a text, with that text's own search3 answer in hand (Search.tsx's
  render reads `results` of the text drawn) - so the artists search3 just found count.

### 2.2 Whose (`SearchMarks`, slice 1; searchList.ts:140-224, whose.ts)

- **Logins off** (or the break-glass admin: no library of your own): everything Navidrome has is yours - every row
  is "in your library", and no row moves for whose it is.
- **With a library of your own** (`Access.hasLibrary`): an album is yours when it is among your albums (album_index
  `yours`), else when Navidrome has it starred for you, else when a folder holding its release is yours
  (`/library/owned`'s `yours`, absent counting as yours); unknown while none of those can be told. An album row made
  of a song's own fields (Top results' family) is read as search3 or the albums in hand have it - unknown otherwise,
  never "in the collection" on a guess. A song is its album's. An artist is yours with albums of theirs among yours,
  the collection's with none - unknown until your albums have answered.
- **Unknown is yours for the order** (`holder`): a row is never put after the collection's on a guess, and once drawn
  never moves when it becomes known (2.6) - only its words change.

### 2.3 The sections (`SearchList.pool`, `sectionRows`, slice 1; searchList.ts:440-590)

- Each kind's library rows in search3's order, each marked yours or the collection's. Under the album-by-artist
  reading, the artist the box named - by foldName, believed only when exactly one of the library's artists (the full
  list and search3's own, each once) answers to the name - leads Artists when search3 didn't list them (position -1).
- A section's rows: yours first, then the collection's, each in search3's order; the All view shows the first
  `PREVIEW.phone` of them - **2 artists, 3 albums, 3 songs** - and See all opens that kind's view. A kind with none
  is no section.
- From slice 2: what MusicBrainz brought in that you hold (into its holder's block), then MusicBrainz's own, each
  capped on its own; held MusicBrainz albums never drawn twice (`heldUnlisted`, `notInLibrary`).

### 2.4 Top results (`SearchList.topResults`, slice 1; searchList.ts:599-830)

- **The tier** (`matchTier`): 0 exact - an artist whose name folds to the box; an album or song whose title does (a
  song's by `titleKey`, which keeps brackets and apostrophes and drops only "(live …)", "(… remaster(ed) …)", "(mono)",
  "(stereo)" asides - songs.ts:100-118); under album-by-artist, one titled as read and credited to the artist read.
  1 by the box's artist - under the artist or album-by-artist reading, a row credited to that artist (and under
  album-by-artist the artist themselves). 2 starts with - three characters or more typed, and the name or title starts
  with them. 3 the rest. Under the artist reading a title is never exact ("portishead" means them, not the
  self-titled album).
- **The order** (`rank`): tier, then source (yours 0, the collection's 1; slice 2 adds what's saved 1.5 and
  MusicBrainz's 2), then kind (artists, albums, songs), then position in its answer.
- **The picks** (`topResults`, n = `TOP_RESULTS.phone` 3): the best; then its family as Apple pulls it in - a song's
  album (search3's row, else one made of the song's fields) then its artist (search3's, else the full list's, else
  one made of the name); an album's artist - each skipped if already picked; then round by round over the kinds, a
  kind with fewer picks than the round taking its best left, until there are three (fewer candidates, fewer picks).
- The web's worked examples hold on the phone (notes/app-requests-search-get.md): "portishead" with them held ->
  Portishead, Dummy, Roads; "roads" -> Roads, Dummy, Portishead; "glory box" -> Glory Box, Dummy, Portishead.
- From slice 2: phantoms for MusicBrainz kinds still out (`decidedTop`) - the picks before the first phantom drawn at
  once and frozen, one place kept for the rest.

### 2.5 The lines (`SearchList.rowLine`, slice 1; searchList.ts:986)

A row's second line as two parts - the facts (which take the ellipsis) and the place (never cut): an artist "Artist"
in Top results and nothing in a section, the place their count (2.2's: your own count when you have any, else
Navidrome's count of theirs, "in your library" / "in the collection"); an album "[Album ·] artist · year" (a year of 0
or none left out), the place `libraryPlace`; a song "[Song ·] artist · album", the place `libraryPlace` of its album's
whose. The parts joined with " · ", empty ones dropped; the place written after " · " when there are facts.

### 2.6 What is asked, and when (`SearchPacing`, slice 1; Search.tsx, api.ts)

- **The library** (All's): `LIBRARY_SETTLE_MS` 200 ms after typing stops - at once on the keyboard's Search - search3
  with `SEARCH_COUNTS` (5 artists, 8 albums, 12 songs), for every text whatever the view (the reading needs its
  artists); only the newest answer counts, and an older one's ask is cancelled.
- **A kind view's own**: beside All's, `CHIP_LIBRARY_COUNTS` (Artists 50, Albums 50, Songs 100, the other kinds 0),
  for that view's words and kind; kept until either changes. Full (as many as asked) offers More from your library:
  that kind's next page by offset (the other counts 0), appended without repeats; still full when the page was full
  and brought something new.
- **A song's album**, so its tap plays: as an answer lands, the albums of up to `SONG_ALBUMS_PREFETCHED` 5 of its
  songs - Top results' songs first, then the songs' in order, each album once - asked for and kept for the box's life
  (a scroll never lets one go; cleared when the box empties or the person changes); a Songs view's answer asks its
  own five. A song plays from its tap when its album's songs are in hand and it is among them.
- **`/library/owned`**: as Search shows for a person, and again each time it shows (the ETag: a 304 unless the
  library changed) - its answer kept in memory for the person; a failed ask keeps the last answer. Your albums
  (album_index `yours`, the Library's own list and ask) and the library's artists (`/navidrome/artists`, the Artists
  page's own list and ask) are asked as Search shows when not in hand - the same lists the Library draws, never a
  second copy.
- **Navidrome**: asked as the Library asks it (LibraryModel's check). Known not to be there: nothing is asked of
  search3, and the gate's words stand above the list (the web's NeedsNavidrome); not known yet is not "not there".

### 2.7 The list as drawn (`SearchDrawn`, slice 1; Search.tsx:176-200, :1236-1300)

- **Drawn once per text, then frozen.** When the library settles for a text in the All view (answered, or failed),
  the list is made: Top results' picks and each section's rows, in their order. Afterwards only the marks and the
  lines change in place - your albums landing, `/library/owned` landing, an Add elsewhere - and nothing moves under a
  finger. A chip, See all and Back to All draw afresh from what is in hand (your own act).
- **Typing on** keeps the list drawn until the new text's library settles, then the new list takes its place; an
  empty box drops everything (the hint again, the view back to All, the albums in hand let go).
- **Failure**: the list drawn with its failure's words at the top and Try again (which asks again and draws afresh).
- **Nothing found** (All, the library answered with nothing): "No results for “…”." and "Check the spelling or try a
  new search." - question 4. A kind view: "No albums for “…”.".
- From slice 2: the moments (Top results' decided picks first, the sections in an asking line's place, a late kind
  landing in its slot or folded behind "Show 3 more albums"), `RESULTS_WAIT_MS`, `LIBRARY_LATE_MS`, Behind.

### 2.8 Taps (slice 1; SearchRows.tsx:117-140, Search.tsx:1686-1712)

- An artist: their page (Phase 4's ArtistView, `AppRoute.artist`). An album: its page (`AppRoute.album`, with what the
  row knew drawn at once). A song: its album played from that song - at the album level, as the album page's row tap
  plays it, called in the tap with nothing awaited - when its album's songs are in hand; else its album's page (a
  fetch-then-play would start the music outside the tap). A song with no album and none in hand: nothing.
- A song's •••: Play Next, Play Last, Add to a playlist…, and its download items (Phase 1-4's QueueMenu) - the song as
  its album's when that album is in hand, else the song alone with its own album (Songs' row, Phase 4).
- From slice 2: a MusicBrainz album (the album you don't have, or yours when held - the id bridge); slice 3 a
  MusicBrainz artist and a MusicBrainz song (the albums it is on).

### 2.9 Offline (the phone's own, slice 1)

While deadwax can't be reached nothing is asked. A list drawn stays - the words searched are still what it answers -
with every song not on this phone dimmed (it opens and plays nothing), as Songs is; a song on this phone plays from
its album's songs on this phone. With nothing drawn, or for new words, "Search works once deadwax is back." Nothing
of MusicBrainz is drawn offline from slice 2 on - the plan's "show nothing stale as if live" (question 5).

(Slice 2's review) No clock of the list's runs offline either: the library's late clock is armed only while deadwax
can be reached, and one running out offline is dropped - a list drawn "without the library" then would be blank (its
MusicBrainz part left out) where the offline line stands, and once back the library's rows would sit behind "Show N
from your library". As deadwax comes back the words' library is asked with its late clock (`resumed`, by
`wantsLibrary` or `libraryUnplaced`), so the list is drawn with it. A held album's id-bridge answer (3.6) opens only
on the list it was tapped on, and a cover that failed for want of deadwax asks once more as it comes back.

## 3. The screens

### 3.1 The tab (slice 1)

Library | Search | You - the web's order, Home and Requests not yet built (question 1). Its own NavigationStack, as the
others: tapping Search again pops to its root, and at the root scrolls the list to its top. The mini player and the
notice sit above the tab bar as on every tab; every page the Library pushes (an album, an artist) is pushed here too.

### 3.2 The box and the chips (slice 1)

The navigation bar's search field (`.searchable`, drawn always, never hidden by a scroll), prompt "Artists, albums and
songs", no autocorrection or capitalisation (the web's `autoCapitalize="none"`, `spellcheck={false}`), the keyboard's
key Search. Typing asks after the pause; the keyboard's Search asks at once and puts the keyboard away. The chips -
All, Artists, Albums, Songs - a segmented control (the Library's switch is one) under the field, drawn only while the
box has words, as the web's.

### 3.3 All (slice 1)

```
 Search
 [ Artists, albums and songs        ]
 [ All | Artists | Albums | Songs ]
 Top results
  (o) Portishead           Artist · 3 albums in your library
  [ ] Dummy                Album · Portishead · 1994 · in your library
  [ ] Roads            >   Song · Portishead · Dummy ...       •••
 Artists                                   See all
  (o) Portishead           3 albums in your library
 Albums                                    See all
  [ ] Dummy                Portishead · 1994 · in your library
  ...
 Songs                                     See all
  [ ] Roads            >   Portishead · Dummy · in your library  •••
```

Rows as the Library's (`LibraryRow.cover` 44 pt, the row cover size, a round one for an artist), the title and the
line (the facts truncating, the place never), ▶ after a song that plays from its tap; a song's ••• at the row's end.
Each section's heading a header, with See all. The asking line while nothing is drawn; a failure at the top with Try
again; the gate's words above when Navidrome isn't there.

A slot (slice 2: a late kind's in its section, and the library's place at the top of a list drawn without it) is the
web's `.app-search-slot`: one fixed height whatever it holds (60 pt, `--app-search-slot`, a `@ScaledMetric` so it
holds at the accessibility sizes), one line ending in "…" - the asking line, a Show button, its words, or a failure
as one row (`is-row`): the words, then Try again at its end (none for words MusicBrainz refused). So nothing below it
moves under a finger when its answer lands (slice 2's review; it was a minimum height, and a failure two lines and a
button).

### 3.4 A kind view (slice 1)

The kind's heading, its rows (the chip's own search3, its order, the named artist first under album-by-artist), More
from your library when full (Loading… while it asks, Try again after a failure). Back to All by its chip.

### 3.5 VoiceOver and Dynamic Type

A row is one element: "Roads, Song · Portishead · Dummy · in your library, plays it from its album" (", opens its
album" when it doesn't play); an artist "Portishead, Artist · 3 albums in your library". The song's ••• "More for
Roads". What the list found is announced as it draws (`libraryWords`), and a chip's "Showing albums." The chips are a
group "Show". At accessibility sizes the title takes three lines and the line two, as the Library's rows.

### 3.6 The album you don't have (slice 2)

`app/ReleaseGroupPage.tsx` on the phone: the group's cover and title, its credit and year, its kind, the pressings
(`pressings.ts`: the usual pressing chosen, others to choose), the tracklist with what differs marked, "maybe in your
library" where a folder may hold it, and the song it was opened from marked (slice 3) - a page of its own on the tab's
stack (`AppRoute.group`). Phase 6's Get sits in its bar; slice 2 draws the bar's place with nothing in it.

## 4. The server

**Nothing new for slice 1.** Every route it calls exists: `/navidrome/search` takes the offsets already, and
`/library/owned`, `/navidrome/artists`, album_index and `/navidrome/albums/{id}` are as the web calls them. The phone
builds and runs against 2.1.23 as it is.

Slice 2's question (question 8): the Cover Art Archive. The web loads a MusicBrainz album's cover straight from
coverartarchive.org (`pressings.ts:512`); the plan's answers say the app talks only to deadwax. *Recommend*: a
deadwax relay for the archive's front covers (`GET /deadwax/coverart/{release-group|release}/{mbid}?size=`, cached as
Navidrome's covers are), a main 2.1.x patch made before slice 2; until then the phone draws MusicBrainz's albums with
the empty cover.

## 5. The machinery (for the builders)

### 5.1 Core, and the App

| Core (pure, tested on Linux) | App (wires it) |
| --- | --- |
| slice 1: `Owned.swift` - `OwnedAlbum`, `OwnedAnswer`, `OwnedIndex` (owned.ts: by release, by group, by name; `ownedForRelease`, `ownedForGroup`), `OwnedArtists` | `SearchModel` - the box, the view, the library's answers, the drawn list, a kind view's own, the albums in hand, `/library/owned` kept per person; reset on a new person |
| slice 1: `SearchReading.swift` - searchQuery.ts (`artistNames`, the reading, the queries) | `SearchScreen` - the tab's root: the box, the chips, All, a kind view, the gate's words, offline |
| slice 1: `SearchList.swift` - the rows, `SearchMarks` (whose), the pool and the sections, `SongTitle.key` (titleKey), the tier, the rank, the family, Top results, the lines, the words, `SearchPacing`, `SearchDrawn`, `KindLibrary` (a kind view's own and its More) | `SearchRow` views - an artist's, an album's, a song's (▶, •••, dimmed offline) |
| slice 1: `LibraryResults` (lenient), `Routes.libraryOwned` (41), `Routes.search` with `artistOffset` and `albumOffset`; `DeadwaxClient.searchLibrary(_:counts:offsets:)`, `owned(ifNoneMatch:)` | `AppTab.search`, its stack in `AppNavigation`, MainTabs' third tab |
| slice 2: MusicBrainz's groups (`ReleaseGroup` lenient), searchResults.ts' kinds and years, `notInLibrary`, `heldUnlisted`, the moments (`decidedTop`, `sectionsReady`, `lateKinds`, `drawInOrFold`, `nextBehind`), pressings.ts' page rules; 3 routes (44) | the moments as drawn, the album you don't have (`AppRoute.group`), Get's place |
| slice 3: songs.ts (`groupSongs`, `namedAlbum`, `newSongs`, the disclosure), `newArtists`, MusicBrainz artists; 4 routes (48) | the songs' disclosure, a MusicBrainz artist's page |
| slice 4: `savedFor`, `SAVED_WAIT_MS`, the kept answers (24), More from MusicBrainz; 1 route (49); the app 0.11 (11) | the saved rows, the kept answers |

### 5.2 Held to the web

`ios/scripts/export-search-vectors.cjs` compiles `ui/src/lib/searchList.ts` (with searchQuery.ts, searchResults.ts,
songs.ts, whose.ts, owned.ts and what they import) with the repo's TypeScript and writes
`Fixtures/search/search-vectors.json`: the box's readings over many texts and name lists; titleKey and foldName over
hard titles; owned indexes and their lookups; whose over every combination of the marks; and whole cases - a library
answer, the marks, the box - each with what the web's own functions make of it: the pool's rows and holders, the
sections as the All view caps them, every candidate's tier, Top results' picks, every row's line and place in a section
and in Top results, the albums prefetched, and the words. `ui/test/iossearch.sim.cjs` runs it with `--check`. Slices
2-4 add their rules to the same file (or a second one, if it grows past a few hundred kilobytes).

## 6. The slices

### 6.1 Slice 1 - your library's half

Core: 2.1-2.8 (the reading, whose, the sections, Top results, the lines, the pacing, the drawn list) with the fixture
and the sim; `/library/owned` and its index; `LibraryResults`; the route's offsets. App: the Search tab, its box and
chips, All and the kind views, the rows and their taps (a song playing in its tap), the gate, offline. No MusicBrainz:
the hint says what is searched (question 3). The app's version left at 0.10.

**Why this first.** It is the half that answers in a fifth of a second and plays music - the plan's first check
("search a song you have (it plays)") - and needs no page that isn't built. Every later slice's moments are built on
its frozen list: MusicBrainz's rows land under it in slots, never moving it, so the freeze has to be right before
anything arrives late. And it needs no server change, where slice 2's covers may (question 8).

### 6.2 Slice 2 - albums you don't have

MusicBrainz's albums in All and the Albums view (`fully_search`, `quick`, the studio query for an artist you have
alone, the plain words when a fielded query finds nothing), deduped against what you hold; the moments (2.7) with
phantoms, `RESULTS_WAIT_MS`, `LIBRARY_LATE_MS` and its Show them, Behind, the fold; "maybe in your library"; the hint
and the asking words with MusicBrainz in them; `TYPE_MORE`; the album you don't have (3.6), and a held one opening
yours (the id bridge, `/store/album`). Checks: the plan's second.

### 6.3 Slice 3 - artists and songs nobody has

MusicBrainz's artists (`/artists`, `newArtists`: a library artist answering to the name brought in, not drawn twice)
and songs (`/songs`, songs.ts' grouping, the song's disclosure onto the albums it is on, the album it names opening
with the song marked); a MusicBrainz artist's page (question 9).

### 6.4 Slice 4 - what's saved, the kept answers, app 0.11

What's saved (`/saved`, drawn at the library's moment, MusicBrainz's answer adding only what isn't there); the last
24 answers kept for the session, used with no request; More from MusicBrainz (by offset) in a kind view; the app's
version 0.11 (11) with everything pinned to it; docs/ios.md and README for the phase.

### 6.5 Slice 1, built (2026-11-14)

What slice 1 is, as built, is in notes/ios.md's "Phase 5, slice 1: Search, your library's half" - Core (Owned.swift,
SearchReading.swift, SearchList.swift, SearchState.swift, held to the web by export-search-vectors.cjs), the app
(SearchModel, SearchScreen, the Search tab), what was decided here, the tests and mutations, and what was verified.
Questions 1-7 and 10 were built with it; questions 11-13 came of it. docs/ios.md's checks 121-129 are its. Its
review's fixes (a failure asked again drawn, words come back to drawn, your albums asked again, a repeated row):
"Phase 5, slice 1, after its review".

### 6.6 Slice 2, built (2026-11-14)

What slice 2 is, as built, is in notes/ios.md's "Phase 5, slice 2: albums you don't have" - Core (MusicBrainz.swift,
SearchAlbums.swift, Pressings.swift, and slice 2's half of SearchList.swift, SearchReading.swift and SearchState.swift,
held to the web by export-search-albums-vectors.cjs and its second fixture), the app (SearchModel's MusicBrainz
half, the moments drawn in SearchScreen, GroupView and PressingPickerSheet, ArchiveCover through the 2.1.24
relay), what was decided here, the tests and mutations, and what was verified. Question 8 was built with it (the
relay, on main as 2.1.24); questions 14-23 came of it. docs/ios.md's checks 130-139 are its. Its review's fixes
(offline words drawn blank, slots growing as their answer lands, the id bridge's answer opening on whatever showed,
covers left empty after offline): "Phase 5, slice 2, after its review", with checks 140-143.

## 7. Tests (Swift Testing; Core's on Linux and macOS)

- **The fixture's replay** (slice 1): every rule of 2.1-2.5 over the web's own answers - readings of every shape (a
  name alone, at the start, at the end, both, the longest winning, separators, Various Artists, "va", nothing typed,
  white space JavaScript has and Foundation hasn't), foldName and titleKey over asides, accents, ligatures, Final
  Sigma, apostrophes and brackets; `/library/owned` indexes (tagged, untagged, a release without its group, duplicates
  by path) and every lookup; whose under logins off, on with nothing known, with your albums, with a star, with a
  folder of yours, absent `yours`; and cases built from the repo's own search3 fixtures (Portishead's, the worked
  examples, one artist under album-by-artist, an artist not listed, a song with no album, a year of 0, an empty
  answer) - the pool, the sections, every tier, Top results, every line.
- **By hand** (slice 1): `LibraryResults` and `OwnedAnswer` decoded leniently (a field of the wrong type, a kind
  missing, `{}`), the client's two calls (the paths, the offsets sent only when above 0, the ETag and the 304), the
  drawn list's freeze (marks changing in place, a new text's answer replacing it only once settled, an empty box),
  `KindLibrary`'s More (appending without repeats, full again only when the page was full and new), the prefetch's
  choice, the song tap's rule (in hand, among them, not, offline and on this phone), the pacing's numbers.
- **The contract** (tests/test_ios_contract.py): ROUTE_COUNT 41 (44 with slice 2); `/library/owned` named with the fields the app reads
  within `OWNED_FIELDS` and `yours`; `LibraryResults`' keys within what the route returns; every count and offset the
  app sends within the route's bounds; the box's limit at most `q`'s 200.
- **Mutations** run by hand and caught (notes/ios.md lists each).

## 8. James's checks (on his iPhone)

Numbered after Phase 4's 120. Slice 1's (docs/ios.md's "Search's checks (121-129)" holds them as James reads them):

- **121 The tab.** Library | Search | You. Search shows the field and "Search your library." (with logins on and a
  library of your own, "Search your library and the collection."). Tapping Search again on a pushed page goes back
  to the list, and at the list to its top.
- **122 A song you have** (the plan's first check). Type "roads" (a song of yours): Top results and Songs list it, ▶
  after it. Tap it: it plays from that song, its album's songs after it in Up Next - in the tap, no wait. Then a song
  further down Songs with no ▶: its album's page opens.
- **123 Top results, as the web's.** Type the same three searches in the web app's Search and on the phone -
  "portishead", "roads", "glory box" (or your own artist, song and album): Top results are the same three, in the same
  order, and the sections the same rows (the phone's sections show 2 artists, 3 albums, 3 songs, as the web's on a
  phone).
- **124 Album and artist.** "dummy portishead" and "portishead dummy": Dummy first. Tap an album: its page. Tap an
  artist: theirs.
- **125 The chips.** Albums: every album found (up to 50), More from your library when there are more; Back to All:
  the list as it was. See all under Songs: the Songs view.
- **126 Whose** (logins on, a library of your own). A song of an album you haven't added: "in the collection", after
  your own in its section; your own: "in your library". Add an album to your library in the web app, then search it
  on the phone: "in your library".
- **127 Typing fast.** Type "portishead" quickly, then delete back to "port" and on to "portis": one list at a time,
  never one row jumping under your finger while you watch; clearing the field brings the hint back.
- **128 Offline.** With a list drawn, turn on Airplane Mode: the list stays, songs not downloaded dimmed (a tap does
  nothing), a downloaded one plays. Type new words: "Search works once deadwax is back." Turn it off: searching works
  again.
- **129 VoiceOver.** A song's row reads its title, its line, and "plays it from its album" (or "opens its album"); the
  list found is announced ("In your library: 1 artist, 2 albums, 11 songs."); a chip's "Showing albums.".

The phase's (the plan's two, with slices 2-4): search an album you don't have - its MusicBrainz page opens (slice 2);
each slice numbers its own after the last. Slice 2's are 130-143 (docs/ios.md's "Search's checks, slice 2
(130-143)"): the hint, an album you don't have opening its page (the plan's second), its pressings and the filter,
held and maybe, the moments beside the web's, an artist alone and the studio line, short words, covers on 2.1.24
and 2.1.23, offline, VoiceOver - and, from its review, typing offline (the offline line stays, never an empty list,
and once back the library's rows in the list), the slots holding their height (at the largest text size too), a
held album's row left before it opens, and covers loading once back online.

## 9. What only the phone can tell

- That `.searchable` in a tab's NavigationStack keeps its words when a page is pushed over it and back, and that the
  keyboard's Search key submits (`onSubmit(of: .search)`) on iOS 27 as documented.
- That a fifth of a second after typing is quick enough over WireGuard (the web's pause, measured on a desktop's
  LAN), and that cancelling the older asks keeps the list from flickering.
- How long `/library/owned` takes for James's library the first time (its size: about 300 bytes an album) and that
  its 304 after is quick - Debug doesn't time it yet.
- That a song's tap plays at once when its album was prefetched - the five albums asked for as an answer lands, over
  the phone's network, before a finger reaches the row.
- That the segmented chips under the field fit at 320 points and at accessibility sizes (four short words).
- That Navidrome's real search3 orders and matches as the fakes do (the starts of words) - the worked examples come
  from the web's fixtures, not James's library.

## 10. Open questions (each with what the build does until James answers)

1. **Where Search sits.** The web's tabs are Home, Library, Search, Requests, You; iOS 26's `Tab(role: .search)` draws
   a search tab apart at the bar's end (Apple Music's own), after You. *Recommend, and built*: an ordinary tab between
   Library and You - the web's order, You still at the end - with `magnifyingglass`. The role tab would put Search
   after You and move MainTabs to the `Tab` API; it can be taken up with Home and Requests.
2. **The box's place.** *Recommend, and built*: the navigation bar's field, always drawn (`.navigationBarDrawer
   (displayMode: .always)`), so the tab opens ready to type; the keyboard is not raised by itself on opening (Apple
   Music's isn't either).
3. **The hint in slice 1.** The web's ("Search your library and albums you don't have yet.") promises MusicBrainz,
   which slice 1 hasn't. *Recommend, and built*: "Search your library." / "Search your library and the collection."
   until slice 2, then the web's.
4. **Nothing found in slice 1.** The web, with MusicBrainz not asked, says only "Type a little more, or press Search,
   to find albums you don't have yet." - which slice 1 can't do. *Recommend, and built*: "No results for “…”." and
   "Check the spelling or try a new search." (the web's words when nothing at all was found) - true of everything
   slice 1 searches; slice 2 brings back the web's rule.
5. **Offline.** The plan: Search says it needs deadwax and shows nothing stale as if live. *Recommend, and built*: a
   list drawn for words stays (it is that search's answer, not a stale one), songs not on this phone dimmed and a song
   on it playing; new words, or none drawn: "Search works once deadwax is back." A search of what is downloaded while
   offline is not built - it could come in slice 4.
6. **`/library/owned` on the phone.** It is the reading's names and the marks' last word, and the web asks it as
   Search shows; on the phone it is about 300 bytes an album. *Recommend, and built*: asked as Search shows, kept in
   memory per person with its ETag (a 304 each time after), never on disk - Search needs deadwax anyway. Its failure
   is quiet: the reading uses search3's artists alone and an unstarred album's place stays unsaid.
7. **The late library (`LIBRARY_LATE_MS`).** The web draws MusicBrainz's rows when the library is 1.5 s late, keeping
   a place for it at the top. *Recommend, and built*: not in slice 1, which has nothing else to draw - the asking line
   stays until the library settles (the transport's 8 seconds at most); slice 2 brings the web's rule with
   MusicBrainz's rows.
8. **MusicBrainz's covers** (slice 2). *Recommend*: a deadwax relay for the Cover Art Archive (section 4), a main
   2.1.x patch, since the app talks only to deadwax; until it exists, the empty cover. Built: the relay is main's
   2.1.24; the phone asks it at 250 for a row and 1200 for the album's own page (question 19), and draws the empty
   cover for anything but a 200 (it sends no ETag yet, so no 304 comes) - an older server's 404 for the route
   included, so it runs on 2.1.23.
9. **A MusicBrainz artist's page** (slice 3). The web's artist page opened from MusicBrainz (`mb:<mbid>`) is their
   discography and description. *Recommend*: their release groups in the web's order, each opening the album you
   don't have (or yours), and the description in Phase 7's links if at all. Not built (slice 3).
10. **A song's album not yet in hand.** *Recommend, and built*: as the web - its album's page opens (a tap that waited
    for the album and then played would start the music outside the tap, which iOS refuses on a locked phone).

11. **A song's ••• before its album is in hand.** The web's row menu queues the song alone. *Recommend, and built*:
    with its album in hand, the album page's song menu (Play Next, Play Last, Add to a playlist…, Download, the song
    queued with its album); before, the song's own (PlaylistPlay.pick - each song with its own album, as a
    playlist's), so the ••• never waits on anything.
12. **Offline rows** (beside question 5). *Recommend, and built*: dimmed as the Library dims them - a song not on this
    phone, an album with nothing here, an artist with no album here - and opening nothing; a song on the phone plays
    from its album's songs that are here, the album as it was downloaded when the prefetch didn't bring it.
13. **Where the list goes when it changes.** *Recommend, and built*: to its top, at once, when a chip changes the view
    and when new words' list takes the old one's place; a row's line changing in place never moves it, and Search
    tapped at the list scrolls to the top as the other tabs do.

14. **What slice 2 asks MusicBrainz** (slice 2). *Recommend, and built*: albums only - `/fully_search` for All's
    Albums and the Albums view. The Artists and Songs views, and All's Artists and Songs, ask nothing of MusicBrainz
    until slice 3, so the moments wait on the albums alone (the web's `sectionsReady` over the kinds asked), and a
    kind view's late clock is armed only for a view that asks (Albums). Core's row type has slice 3's MusicBrainz
    artist already; nothing makes one yet, and drawn it would open nothing.
15. **The routes** (slice 2). Section 0 counted four, `/releases` and `/release` among them; the web's album page
    reads every pressing's tracklist from `/release_group`'s one answer (`{id, releases, problem}`), and the covers
    need the relay. *Recommend, and built*: three - `/fully_search`, `/release_group` and `/coverart/{kind}/{mbid}` -
    and `/store/album` taking `release_mbid` beside `navidrome_id` (the app's already); ROUTE_COUNT 44, slices 3 and
    4 then 48 and 49.
16. **An album MusicBrainz found that you hold** (slice 2). The web opens yours through the id bridge
    (`heldReleases`, then `/store/album?release_mbid=` for each until Navidrome has one). *Recommend, and built*:
    the same - the row shows that it's asking and other rows wait; your album's page opens when found, else the
    album you don't have's page, its line saying it's in your library.
17. **What the album you don't have's page leaves out** (slice 2). The web's has the album's description,
    MusicBrainz's links, the editors' "Match it to a pressing in Edit album." and Get. *Recommend, and built*: the
    cover, the title, the credit (a link to your library's artist when one is theirs - a MusicBrainz artist's page
    is question 9's), the line with "maybe in your library" dashed, Pressing, the facts, the maybe sentence without
    the editors' (the phone has no Edit album), the summary and the tracklist with "Not on this pressing"; Get's
    place drawn empty for Phase 6; no description or links (Phase 7's, with the artist's).
18. **The pressing picker** (slice 2). *Recommend, and built*: a sheet (medium, then large), the chosen pressing
    ticked, a tap choosing it and closing the sheet; the web's filter (`.searchable`) only over 30 pressings, its
    words announced as it narrows; the web's fold ("3 more pressings with the usual tracklist").
19. **Cover sizes** (slice 2). *Recommend, and built*: the relay's 250 for a row (a row's cover is small, and 250
    is the Archive's smallest) and 1200 for the album's own page (its cover is the screen's width); the page tries
    the chosen pressing's front, then the album's, as the web does.
20. **Pressings kept** (slice 2). The web keeps the last 20 complete lists for the session (`PRESSINGS_KEPT`).
    *Recommend, and built*: the same, in memory, the newest last, a list with a problem never kept - so a page
    opened again, or offline, draws at once.
21. **MusicBrainz offline** (slice 2, beside question 5). *Recommend, and built*: none of it - a drawn list loses
    MusicBrainz's rows, its slots and its words (yours stay, as slice 1's), since each of them opens a page that
    needs deadwax (back online, they're drawn again); an album page keeps what it has shown, its pressings kept
    for the session, and one that hasn't loaded them says "This album's pressings load once deadwax is back." (the
    phone's own words, question 5's shape) and loads them once it is; a cover not yet fetched is the empty cover
    (none kept on the phone). Words searched while away are asked of MusicBrainz as the pause would have asked them.
    (Slice 2's review) Typed while away, the words draw nothing - "Search works once deadwax is back." stays, never
    an empty list - since no late clock runs offline; once back, their library is asked with its clock and drawn in
    the list. A cover that failed for want of deadwax asks once more as it comes back; one deadwax answered without
    (a 404, the Archive away) keeps its minute.
22. **How long the phone waits for MusicBrainz** (slice 2). *Recommend, and built*: 20 s for the albums - deadwax
    gives up in about eight seconds while MusicBrainz turns searches away (`SEARCH_PATIENCE`), which the contract
    test holds below it - and 60 s for an album's pressings (several of MusicBrainz's pages). A connection hanging
    on deadwax's side (up to about a minute and a half for a search) is then said as "That took too long." with Try
    again, where the web, waiting it out, says "Searching for more isn't working right now - try again in a few
    minutes." The other way: wait as long as deadwax could (minutes), for the web's words every time.
23. **Slice 1's stand-ins** (questions 3, 4 and 7). *Recommend, and built*: the web's again - the hint is
    searchResults.ts' ("Search your library and albums you don't have yet."); under three letters, with MusicBrainz
    not asked, `TYPE_MORE` where the albums would go; the late library drawn after 1.5 s with its place kept at the
    top ("Searching your library…", then Show 5 from your library, or that it found nothing); and nothing found
    with Navidrome not there says "No results for “…”." as the web does.
