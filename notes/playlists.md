# Playlists

### Playlists (2.0.0-player.58)

James, 2026-10-20: **"also I'd like to get playlist functionality and a better library interface. sort, grouping,
etc."** - Apple Music his reference. This is the playlists; the Library's sorting and grouping is .59. He approved
every choice of `uplan/slice-playlists.md` the same day, as amended by the end of `uplan/slice-queue.md` ("The two
specs built around this one"), written after Up Next (.57) put a ••• on every song row: Add to a playlist lives in
those menus instead of a button of its own. A commit on player-spike, no tag, so no release notes.

**The default taken, his to overrule: playlists ARE Navidrome's own**, made AS THE ASKER (`client_for(request)`), so
Amperfy - James's iPhone Subsonic client, which syncs Navidrome's playlists both ways (it reads getPlaylists /
getPlaylist and writes create / update / delete, AM `SubsonicServerApi.swift:721-795`) - shows the same ones, as his
favourites are already Navidrome stars. deadwax keeps no playlist of its own: no table, no cache on disk. Every
Navidrome fact below was read in Navidrome 0.64.2's source (ND), not run.

- **Whose** (`src/playlists.py`, pure). Navidrome lists, to a non-admin, their own playlists and everyone's public
  ones (ND `persistence/playlist_repository.go:84-93`), and to an admin every playlist; its `readonly` is true for
  anyone but the owner, and for a smart or file-synced playlist even to its owner (ND `server/subsonic/playlists.go`
  buildOSPlaylist). deadwax decides on `owner`, never on `readonly` alone (an admin sees `readonly: true` on others'
  that Navidrome would still let it change): **mine** = owner equal, case-folded, to the account asked as - the
  signed-in user's name (`UserClient.username`), else `Config.NAVIDROME_USER` (`asked_as` in routes/navidrome.py);
  **listed** = mine or public - somebody else's PRIVATE playlist is never listed nor opened (404), even when deadwax
  asks as a Navidrome admin and Navidrome hands it over (with logins off, a shared admin account would otherwise show
  every deadwax user every Navidrome user's private playlists); **editable** = mine and not readonly. Three groups
  (`lib/playlists.ts` groupPlaylists): Yours, Shared with you, From files - the last mine and read-only (a smart
  `.nsp`, or one Navidrome imported from an `.m3u`), drawn folded behind "From files (N)", never in the picker or
  the sidebar, because deadwax's own filing puts a download's `.m3u` sidecars into its album folder
  (`src/organizer.py` COMPANION_EXTENSIONS) and Navidrome imports each as a private playlist of its first admin
  (ND `scanner/phase_4_playlists.go:53-64`; AutoImportPlaylists defaults on) - with logins off there may be one per
  download. Stopping the organizer copying them is the real fix, left for later.
- **Six routes, five Subsonic calls** (routes/navidrome.py, the fixed list; `tests/test_logins.py` ROUTES, all a
  user's): `GET /playlists` (getPlaylists - summaries, unlisted left out, none at all `[]`), `POST /playlists`
  (createPlaylist with `name` and every `songId` in order; Navidrome answers the whole new playlist), `GET
  /playlists/{id}` (getPlaylist and getPlaylists together - `hidden`, below), `POST .../add` (getPlaylist, then
  updatePlaylist's `songIdToAdd` unless it asks), `POST .../edit`, `POST .../delete` (getPlaylist, deletePlaylist).
  The request models forbid extras (a field the page sends that isn't declared is a 422, never dropped - pinned);
  names trimmed, blank or a control character refused; a description keeps new lines and tabs. The limits (200, 1,000,
  2,000) are the models' own validators, never Field's `max_length`, so every refusal is a ValueError in deadwax's
  words, which `src/api/app.py`'s RequestValidationError handler sends as a plain `detail` for a path under
  `/deadwax/navidrome/playlists` (`validation_words`) - every other route's 422 is FastAPI's own list, as before
  (pinned both ways). Every write reads the
  playlist first and refuses one that isn't listed (404), isn't mine (403 naming its owner) or is mine and read-only
  (403) - nothing written. Navidrome's errors: 70 is GONE, 50 (not the owner, or songs that can't be edited - ND
  maps both) the owner's words, a refused login the 401 that ends the session.
- **Writes go as a form POST** (`NavidromeClient.call(..., form=True)`, `UserClient.call` and `_NoLogin.call` taking
  it too - without it `_NoLogin` raised a TypeError, a 500, where the 401 belongs): every parameter and the login in
  an `application/x-www-form-urlencoded` body, a list as its key repeated in order, nothing in the URL. Navidrome
  takes a form body on every Subsonic endpoint (OpenSubsonic formPost, ND `server/subsonic/middlewares.go:32-50`),
  and a 2,000-song replace is ~60 KB of `songId=` pairs - fine for Go, refused by a reverse proxy at its usual 8 KB
  request line. Reads stay GETs.
- **Why the replace, never `songIndexToRemove`, for a removal or a reorder.** Navidrome numbers a playlist's rows 1..n
  INCLUDING rows whose file is missing, which getPlaylist doesn't list (ND `playlist_repository.go:161-163`), and
  `songIndexToRemove=i` deletes position i+1 among all of them (ND `core/playlists/playlists.go` Update). Once a
  playlist holds a hidden row - an album deadwax deleted, a folder mid-move - removing by the place the page sees
  removes the WRONG song (Amperfy's own reorder has the same hole, AM `SubsonicLibrarySyncer.swift:1062-1076`). So an
  edit that changes the songs is createPlaylist with `playlistId` and every `songId` in the new order - Navidrome's
  replace: every row deleted, the list written from position 1 (ND Create -> Put). Exact; its cost is dropping the
  hidden rows, which Edit says before Done (`hiddenEditWords`). Emptying one: createPlaylist with no `songId` does
  NOTHING to the songs ("only update tracks if they were specified", ND `playlist_repository.go:136-139`), and
  removing by a count misses an orphan row (no foreign key until `removeOrphans`), so it is a replace with base's
  first song (the songs as they are now), then `songIndexToRemove=0`. A change only to name, description or sharing is one updatePlaylist with
  only those - no song touched, a hidden row kept.
- **Edit's base check.** Done sends `base` (the ids as drawn when Edit began) and the ids now; the route reads the
  playlist and, unless its ids are exactly `base`, answers 409 and writes nothing - an add made in Amperfy between
  the read and the save. The page closes Edit, draws the playlist as it is now and says so. Merging isn't tried:
  Subsonic edits by place, and two lists reordered apart can't be merged honestly. The new list must only remove and
  reorder the songs as they are now (a Counter comparison, mirrored in lib/playlists.ts) - else 422. Over
  PLAYLIST_SONGS_MAX (2,000): 409, no Edit offered. Songs saved and the metadata refused: 502 saying so
  (PART_SAVED); everything written and only the read after it failing: 502 SAVED_UNREAD ("Saved - but Navidrome
  didn't answer…"), never a bare 502. **A Done refused can't be retried as it stood** (review): its songs may be
  written already, so the next Done, finding them where `base` isn't, answered 409 CHANGED - "changed in another app
  … Your changes weren't saved", both false. The page now keeps the songs a refused Done sent and sends them as
  `tried` on the next one; the route takes the playlist as it is as base, tried, or - tried empty - any ONE of base's
  songs alone (an emptying stopped after its first step, which leaves the first song of the list IT began from - base,
  or one a Done failed before it left; second review: base's first song alone made a third Done after two failures a
  false 409), and writes from there: the songs only if they differ from what
  is there now, the metadata only what differs. Leaving Edit after a refused Done asks the playlist again. `tried`
  never excuses a change made elsewhere (the songs as neither base nor tried: 409, pinned).
- **Hidden songs**: `hidden = counter - listed` for an EDITABLE playlist, where `counter` is getPlaylists' stored
  songCount (refreshCounters joins media_file with no missing filter, ND `playlist_repository.go:333-365`, and runs
  only on edits) - 0 for anything else, since getPlaylist re-evaluates a smart playlist as it answers while the
  counter read beside it may be the old one.
- **Duplicates.** An add reads the playlist as it is at the tap. `ask` (the default) with any of the songs there
  already writes nothing and answers `{done: false, already, asked}`; the picker asks - one song: Add it again /
  Cancel; all: Add them again / Cancel; some: Add them all / Skip those N - and sends `add` or `skip`. Navidrome's own
  web UI asks the same (ND `ui/src/dialogs/DuplicateSongDialog.jsx`). Songs are appended after Navidrome's last row,
  hidden ones included (ND `playlist_track_repository.go` Add, max(id)+1), so nothing already there moves.
- **The app.** Pages of their own kinds (`lib/appRoutes.ts` `playlists` - one page, `#/<tab>/playlists/all` - and
  `playlist` by Navidrome's id), never a Library view (.59 reworks those). On a phone a **Playlists** row at the top
  of the Library (`player/Library.tsx`, before the scope chips - whose.sim's regex unmoved; since 2.0.0-player.59 the
  first row of the phone root's first group, app/LibraryHome.tsx - notes/app-library.md), no count (a count would
  make the Library ask Navidrome at its first show); on a desktop the sidebar's **Playlists** group after the
  Library's and Browse's, All playlists then up to 20 by name (`lib/appFrame.ts` SIDEBAR_PLAYLISTS, sidebarCurrent's
  branch ahead of the Library tab's, sidebarMove `{how: 'playlists'}`), its picks siblings that replace one another
  (App's `openPlaylistsPage`, kind AND id - `samePage`); while the list isn't known, or the last ask failed, the group
  is All playlists alone. `app/usePlaylists.ts` is the one list (asked fresh by the
  Playlists page and the picker, not fresh by App for the sidebar, after every write by `announcePlaylistChanged`,
  which also tells a page of that id), through latestOnly; it also keeps a page's last eight answers, which the page
  draws on its FIRST render - App draws only each tab's top page, so back to a playlist from an album remounts it,
  and the route's scroll is put back in App's layout effect before anything could have been fetched. **A kept
  answer is for drawing, never Done's base** (second review): an add from the picker kept the page's old answer, so
  opening the playlist again drew the songs without the add and offered Edit at once - Edit tapped before the ask
  landed began from them, the fresh answer was then dropped (none draws in Edit), and Done answered a false 409 for
  the user's own add. Now `announcePlaylistChanged(id, now?)` keeps the answer a write gave (Done, a New playlist)
  and lets go of `id`'s kept answer otherwise (an add, a delete); and the page offers Edit (`canBegin`, aria-disabled
  until then) only once its own ask has answered - or its own Done - and again only after the ask that follows a
  409, a refused Done left, or an add here told it of. A refresh that fails leaves Edit waiting.
- **Playing one** is `playTracks` from the playlist's own page (`app/PlaylistPage.tsx`, added to app-rules'
  ALLOWED), its songs in hand: `rememberQueue(playlistAlbums(songs))` then `player.playTracks(tracks, start,
  shuffle)` from Play, Shuffle and a row's tap, nothing awaited (pinned exactly). The albums are STUBS - one per
  album in the order its songs first appear, `{id, name, artist (the album's own first), coverArt, year, song}` and no
  `musicBrainzId` key at all (an empty one makes Now Playing's pin unpinnable, App's menuPinNow; left out, it falls
  back to Navidrome's id), and `partial: true` - its `song` only the playlist's songs of the album - so Info's About
  for a song played from a playlist has fewer album facts (no label, no disc titles) and counts none of the album's
  from the stub (lib/aboutRows.ts: "Track 4" with no "of", no disc line, no format or song count on the album's card
  - review: it said "Track 1 of 1" and "1 song"); getSong still fills its play count and writers. Accepted. **A stub
  never replaces an album's own answer** (review): what is remembered goes through `withHeld(stubs, playedAlbum)` at
  the tap - Play, Shuffle, a row, and the albums handed to a row's ••• and the bar's (QueueMenu's rememberAdded) - so
  an album held whole (played from its own page) stays whole, and the album already playing keeps its disc's art on
  the turntable and the visualizer and its facts in Info (a stub put over it made playingDisc fall back to disc 1); an
  earlier playlist's stub of it keeps its songs beside the new ones. A song with no album id gets no stub and
  its queue track names none (null). The page reads of the player only what an album page reads - playTracks,
  playing, track?.id - so App's pages memo needs no new key. Play Next and Play Last are Up Next's song menu: a row's
  ••• and the bar's ••• for the whole playlist (QueueMenu - which also has Add to a playlist…, its songs into
  another).
- **Add to a playlist** (`app/PlaylistPicker.tsx`, one sheet on both frames, over everything - the page behind,
  a desktop's side panels and Now Playing inert): **the amendment applied** - "Add to a playlist…" is the third row of
  QueueMenu (every song row's ••• - album pages, Search's songs, the Library's Songs, playlist pages - and an album's or
  a playlist's bar •••), the second of Now Playing's ••• menu (ActionMenu, after Info; its ••• label says ", add to a
  playlist"), and a button in the desktop player bar's tools before Info. No album-bar button of its own. **"Choose
  songs" was left out** (the amendment's choice): with a ••• on every song row one song is two taps from anywhere,
  and Apple's own Add to a Playlist is a song's or the whole album's - a checklist inside the picker was four taps for
  the one-song case and nothing Apple has. New playlist… first (the form in its place, `app/NewPlaylistForm.tsx`, makes
  it WITH the songs), then yours you can add to, the one changed last on top (Navidrome moves `changed` on every add).
  One write at a time (a ref, set in the tap), the row saying Adding…; done - the app's one notice (`sayPins`:
  "Added 11 songs to Late night", "Added 9 songs to Late night - 2 were in it already", "Nothing added - they're all in
  Late night already", "Made Late night with Roads") and closed, focus back to what opened it; refused - said under
  the list, a gone playlist asking the list again. Closing it while an add is out calls nothing off - and the answer
  frees the rows however it went (review: closed and opened again meanwhile, they stayed "Adding…" and New playlist…
  did nothing). The question's button pressed is the one saying Adding…; refused from the question, focus goes to the
  list's first row. The heading, what it adds and the refusal sit on a card of their own (`.app-playlist-picker-head`,
  an `.app-group`) - on the bare scrim the page showed through them (review). Rendered after QueueMenu (after Info),
  so where the menu closes as it opens, focus ends in it.
- **Edit** (yours, editable, ≤ 2,000): Cancel in Back's place, Done in Edit's (one toggle, focus kept), the name, the
  description, **Shared with everyone** (a checkbox row, its note always under it), the rows as Home's Pinned rows
  (up, down, remove - focus where Pinned keeps it, each change read out - and the grip, its drag dropIndex and
  dragOffset imported from lib/pins). New against Pinned: **the page scrolls itself while a dragged row is within
  DRAG_EDGE_PX (56) of the bar's bottom or the bottom chrome's top**, `edgeScroll` px a frame (at most 16), from a
  requestAnimationFrame loop held only while a drag is (app-rules lists it beside the deck's and the visualizer's), and
  the row's distance counts that scroll (`dragDistance`), so a song can go from 80th to 3rd in one drag. Nothing is
  saved until Done (`editBody`: only what changed); Cancel with changes asks (`app/ConfirmLine.tsx`: Discard / Keep
  editing); **Delete playlist**, last and red, asks too (Delete playlist / Keep it, focus on Keep it) - App says
  "Deleted <name>" and goes back, only while that playlist's page is still the route showing (review: a delete
  answering after a tap on Home, or another sidebar pick, popped that page instead); a playlist made on the Playlists
  page after it stopped showing is said in the notice, not pushed on whatever shows. No undo; the confirmations are
  the net. `confirm()` stays barred. **Done's reason and Cancel's question are a line of the sticky bar**
  (`.app-playlist-ask`, full width under its buttons, `.app-playlist-bar` wrapping): drawn above the hero they were
  off screen from the foot of a long playlist (review, measured at top -3741px); a 409 scrolls the page to its top,
  where its words are, the playlist drawn afresh. A page with nothing in hand whose first ask fails says "Couldn't
  open this playlist: …" with Try again (no empty hero, no "again").
- **The sidebar's All playlists** from a playlist opened from the Playlists page goes BACK to it (lib/appRoutes.ts
  `playlistsMove`: stay / back / become / open, held by routes.sim) - replacing the top made two Playlists pages, one
  over the other (review).
- **The desktop player bar for a finger** (1024-1279, pointer: coarse): Add to a playlist made five tools with an
  iPad's AirPlay, 5 x 44 + 4 x 6 = 244px in a 240px side, each shrunk to 43px; the side is 304px there (five tools,
  their gaps and a speed's chip), the transport still fitting at 1024; 320px from 1280 as before.
- **Covers**: a playlist's `coverArt` (`pl-<id>_<hash>`, Navidrome's 2x2 of random albums, made in a background
  worker when the songs change - ND `core/artwork/resolve.go`) through the existing `/cover/{id}` route; an empty
  playlist has none and shows the glyph. No cover upload.
- **Constants** held equal by a test: PLAYLIST_NAME_MAX 200, PLAYLIST_COMMENT_MAX 1000, PLAYLIST_SONGS_MAX 2000.
  No new setting.

**Verified.** `tests/test_playlists.py` (67, against test_player_as_you's fake Navidrome - its Player gained the five
calls shaped from ND: per-user owners as stored, public, readonly, smart and sync, an admin seeing everyone's, rows
numbered counting missing and orphan songs, the stored counter refreshed only by writes, createPlaylist's replace,
updatePlaylist's removals-additions-metadata order, `name=''` as absent; it keeps repeated values and reads a form
body merged with the query, and records whether each call was a form); the walk (`WALK`) covers the six routes for
ethan, logins off and break-glass, keyed by method and path (`/playlists` is two ways), the edit's base read fresh
before it posts; test_navidrome's fixed list, test_navidrome_search's seam test and test_turntable_disc_art's list
gained them; test_app_css / test_app_desktop_css two tests each. Python 3231 collected (3229 passed, 2 skipped; 75 more than .57's 3156). Sims: `playlists.sim.cjs` (new - the rules, the
store, the picker, both pages, the form and the question), app-rules (ALLOWED, the exact `play`, the covered pins
with `pickerOpen`, the picker after Info and QueueMenu, lib/playlists pure, the frame loop), info (the menu's rows and
the ••• label), upnext (QueueMenu's third row, the bar's button), routes (the two kinds, samePage, the back label,
sidebarCurrent and sidebarMove). 36 mutations - every rule the spec named (the listed filter, mine case-folded,
editable from readonly alone, the base check, a new id let through, a removal by index, the empty case as an empty
create or by a count, the wrong counter, hidden on a smart playlist, a duplicate counted twice, `ask` writing, the
form flag, `extra="forbid"`, the owner check before a delete, the picker's filter and order, two writes at once, a
`musicBrainzId` on a stub, rememberQueue after playTracks, Edit on somebody else's, unchanged fields sent, a 409
leaving Edit open, Delete in one step, the scroll left out of a drag, the edge, From files in the sidebar, the two
covered pins, the page reading more of the player, the store asking while fresh, a late answer drawing, the kept
answer not drawn first, QueueMenu's row, the constants, a song with no album id) - each caught, the bytes restored.

**After review (the fixes above marked "review").** Twenty findings checked: real and fixed - the stub over a held
album (and Info's false counts), the half-saved Done's retry, the picker stuck on Adding… after a close mid-add and
its focus and button after a refused question, the sidebar's two Playlists pages, the 422s never reaching the page in
words, the picker's words on the scrim, Edit's question and reason off screen, the delete and the create moving the
wrong page, the first ask failing to an empty page, the bar's tools under 44px at 1024 with AirPlay, a raw 90deg,
GripIcon's comment, the docs' hidden-song line, notes/player.md's count; and four boundaries pinned that nothing
held (one song already there asking, a rename refused with no song written, Navidrome's 50, the edit's limits).
test_playlists.py gained 21 tests, test_app_css and test_app_desktop_css one each; playlists.sim (withHeld, the
picker reopened, the question's button and focus, a Create after the page stopped showing, an album held whole on
Play and both •••, the first ask failed, `tried`, the bar's line and question, the refetch after a refused Done, 409
to the top, onDeleted's id), info.sim (a stub's About), routes.sim (playlistsMove), app-rules (`remembered`, the
delete guard). **34 mutations**, one at a time by script, each caught, every file restored byte for byte (sha256):
the one-song ask, PART_SAVED with no song written, the 50 branch, each limit and validator of the edit and the
create, the words handler, `tried` ignored, the emptying resumed, the rearrangement checked against base, the songs
rewritten on a retry, SAVED_UNREAD, withHeld and the page bypassing it, `partial` and Info counting a stub, the
picker's late failure, its focus and its button, the head card, the page's `tried` and its refetch, the 409 scroll,
the line out of the bar, the bar's wrap, the first-ask notice, onDeleted's id, App's delete guard, the Create guard,
playlistsMove's back, the bar's 304px, the token. NOT driven in a real page: the picker's card, the bar's line at 390
with the keyboard up, the 1024 coarse bar with AirPlay on an iPad.

**After a second review.** Four findings, all real: the stale kept answer behind a false 409 (above); a third Done
after two failed ones answering a false 409 (an emptying retry now takes any one of base's songs, not base's first;
pinned with two failures in a row, and that a lone song base never had is still a 409); test_another_routes_422 now
trips a pins validator's own ValueError, so validation_words' path check is held; and two route rules pinned that
nothing held - the read after a write answering Navidrome's 70 is GONE, never SAVED_UNREAD, and name, description and
sharing sent as they stand write nothing. test_playlists.py gained 4 tests; playlists.sim the store's forgetting,
Edit waiting on the first render, after an add here, after a 409 and after a refused Done, and the reviewer's case
(kept, added, opened again). **13 mutations**, one at a time, each caught, files restored byte for byte (sha256): the
path check, base[:1] back, the 404 exception, public / name / comment sent unchanged, the forget, `canBegin` without
`fresh`, the add's reset, the toggle's aria-disabled, beginEdit's guard, the 409's and the refused Done's resets.

**A real page, by the builder** (its own deadwax on 8115 with logins off, a stand-in Navidrome on 4554 extended with
the five calls and form POSTs, headless Chromium as `deadwax.test` over plain http): the Library's row, the empty
Playlists page, New playlist -> its page (the stand-in's `demo` owning it, written as a form, nothing in the URL); an
album's ••• -> Add to a playlist… -> the picker (named, focus on New playlist…, the page inert) -> added, the notice,
focus back on the •••; again -> the question -> Add them again; the playlist's page (a song twice drawn twice), Play
(the mini player and both rows marked); Edit (Cancel/Done, the 44px controls, remove, move down - read out - rename,
share, Done -> the stand-in replaced in the new order by createPlaylist with the id); Delete's two steps and the
notice; nothing wider than the window at 390, 375, 320 and 1440; on a desktop the row hidden, the sidebar's group with
All playlists current, a new playlist listed and current, the player bar's button opening the picker for the song
playing, Escape closing it with focus back; Now Playing's ••• (labelled "More: info, add to a playlist, go to album, pin") ->
Add to a playlist… -> the picker over Now Playing (which stays open, inert) -> New playlist… -> made with the song
playing, the notice, focus back on •••; no console errors. **Timings** (stand-in at STUB_DELAY 50 ms, 390 wide):
the album •••'s Add to a playlist… to the playlists drawn - 76 ms the first time (the list asked), 2-3 ms after (the
held list drawn at once, asked again behind it); a 500-song playlist's page from the address changing to all 500 rows
drawn - 196 ms the first time, 87-103 ms after (its kept answer drawn on the first render).

**NOT verified**: logins ON in a real page, ethan seeing james's shared one read-only and not in his picker, a
change made "in Amperfy" mid-edit (the 409) and `missing.json`'s hidden songs in a real page (all pinned by
test_playlists.py against the fake, not driven in Chromium); a drag of 50th to 2nd on a 60-song playlist with the
page scrolling itself, by touch emulation; a smart/sync playlist in a real page. **A real Navidrome 0.64.2**: the
form POST of createPlaylist / updatePlaylist / deletePlaylist (read in ND, never run), the counter-minus-listed
arithmetic and the replace dropping hidden rows, how long the 2x2 cover takes to appear, a big smart playlist's cost
on open. **Amperfy** after deadwax replaces a playlist's songs or deletes one. **James's server**: whether
NAVIDROME_USER is a Navidrome admin, whether `.m3u` sidecars were imported there. **The iPhone**: the edit drag with
pointer capture and the page scrolling itself; the picker's name field with the keyboard up (the sheet is fixed to
the bottom of the layout viewport); VoiceOver through the picker and Edit. A playlist with the same song twice under
Gapless, and a playlist on Repeat All in one stream.

**Left out, on purpose**: Choose songs (above); long-press menus; folders, cover uploads, smart-playlist rules,
collaborative editing, copying somebody's playlist to yours; a playlist pinned to Home, a playlists shelf, playlists in
Search (search3 doesn't search them); a sort or filter on the Playlists page (.59 may add one, in lib/playlists.ts
beside groupPlaylists), a view sort inside a playlist (never written - a playlist's order is its owner's); "Playing
from <playlist>"; a count on the Library row; showing hidden songs by name (Subsonic doesn't list them); stopping the
organizer copying `.m3u` sidecars; undo; saving Up Next as a playlist (now possible - for later).

**What .59 (a better Library) must keep** (spec section 16): the phone's way in at the top of the Library with no
count; the two page kinds and their addresses, never a LibraryPick; the sidebar's group between the Library's (and
Browse's) and Managing, sidebarCurrent's playlist branch before any Library-tab branch; usePlaylists as the one list;
Library tiles and rows only navigate - a playlist plays from its own page. .59 removes this slice's `.app-desk
.app-library-playlists { display: none }` and its test, on purpose.
