# The app's Library

### A better Library (2.0.0-player.59)

James, 2026-10-20: **"also I'd like to get playlist functionality and a better library interface. sort, grouping,
etc."** - Apple Music his reference, as it was for Search (.55). Playlists were .58 (notes/playlists.md); this is the
rest: the Library laid out as Apple's, with sorts that suit a big library, headers that group what is sorted, an
index down the edge to jump, a field that filters in place, and the speed to do all of it over thousands of albums
on an iPhone over plain http and WireGuard. The spec is `deadwax-scratch/uplan/slice-library-interface.md` as amended
by the end of `uplan/slice-queue.md` ("The two specs built around this one"); James approved every choice in it the
same day. A commit on player-spike, no tag, so no release notes.

**What was wrong** (from the code at .58): four album orders and two artist orders, no year order, no headers, no
index, no filter, the artist order forgotten on every mount; two rows of chips on a phone with logins on before the
sort; your albums six requests of 500 made one after another from the phone; tiles added 60 at a time and never
removed (about 15k nodes for 3,000 albums, up to three grids mounted); the count only once the last page was in; the
store pageable in Navidrome's orders only, so never groupable; `foldName` inside the comparator (~70,000 calls for
3,000 albums).

**The phone's root** (`app/LibraryHome.tsx`): the title, the Library's Shuffle (.57's `ShuffleSongs scope="yours"`,
at the head of the first group - the amendment), the first group - .58's Playlists row
(`button.app-row.app-link-row.app-library-row.app-library-playlists`, still `onOpenPlaylists`, its page never a
section) then `libraryItems(hasSongs, personal)` without `recent` - and with a library of your own a **Browse** group
(`browseItems`), then Recently added: the 12 newest with See all (the `recent` section). Yours come from the album
index sorted by `created`; with logins off ONE `albumPage('newest', 0, signal, 12)` - the store's whole list is asked
only as a store section opens (Choice 17: with logins on the first show fetches your whole list, which Albums and
Search then share). Your library empty: `EmptyLibrary`, whose Browse the store opens the store's section. .58's
`div.app-group.app-library-playlists` wrapper went with the chips, and with it its desktop rule (`.app-desk
.app-library-playlists { display: none }`, a desktop never draws the phone root) and the rule hiding the chips on a
desktop (`.app-desk .pl-library > .app-library-views`) - on purpose; Search's own `.app-library-views` rules stay.

**A section** (`app/LibrarySection.tsx`, one component for every view: AlbumSection, ArtistSection, SongSection):
on a phone a PAGE of its own (`#/library/section/<id>`, `lib/appRoutes.ts` PageKind `section`, `SECTION_IDS` exactly
the LibraryPick values - routes.sim reads the type to hold them equal; an unknown id, or a section on another tab, is
the tab's root); on a desktop drawn INLINE at the Library's root for the sidebar's pick (each visited view kept
mounted and hidden, its scroll kept by `onLibraryLeaving`, as Library.tsx always did). Top to bottom: a page's back
bar, the title (`libraryTitle`, today's words), a bar of Find (albums and artists), the sort (not for `recent`) and
the count - Find on a line of its own on a phone, all three on the title's row on a desktop (the desktop grid's
column 2) - then the shelf. A page takes focus (preventScroll) as it mounts only when focus fell to the page or into
the hidden root (the review rule Browse the store already followed); a desktop's Browse the store hands it to the
store's title. Opening one is App's `openSection`: pushed from the root, or REPLACING a section on top
(`router.become`), so a section is never pushed on a section; a fresh open starts at its top.

**Kept under a page.** App renders only each tab's root and top page, so an album opened from a section page would
have unmounted it and Back rebuilt it. Now the Library stack's first page, when it is a section with a page over it,
is drawn hidden under that page (`sectionBase`, the pane's middle slot), by the SAME `sectionView` as the top slot and
under the same key - so Preact moves the instance rather than making a new one. Checked in the real page: a marker
set on the section's node survives an album and Back, the scroll is where it was, Find's text is still there, and no
`album_index` is asked.

**Sorts** (`lib/shelves.ts`, pure, shelves.sim): seven album sorts - Artist (the default: fold key, then year oldest
first with undated last, then title; Recently added has its own place now - Choice 3), Title, Recently added
(`created` newest first), Year newest / oldest first (no year or 0 last), Recently played (only the played), Most
played (`playCount` > 0, then `played`) - one choice for your albums and the store's, kept in `deadwax-player-order`,
whose four old values mean what they did (anything else reads as Artist). Artists by Name (now by `foldName` with
`#` last, so the letter headers are contiguous - Navidrome strips articles foldName doesn't) or Most albums, kept in a
new key, `deadwax-player-artist-order`. The `#` bucket (digits, symbols, other scripts, nothing) sorts after Z, as
Apple's does. Ties keep Navidrome's order. Fold keys are made once per album object (a WeakMap): shelves.sim counts
6,000 foldName calls for two sorts and their groups over 3,000 albums. Both scopes are sorted in the browser the same
way, so the store's Artist order changed a little from Navidrome's (compilations last, then title) - in
troubleshooting.md. A sort change brings the section back to its top, as Find does (another order is another list).

**Headers** `h2.app-shelf-head` in the flow: the fold key's first letter (A-Z, else #), the year ("No year"), the UTC
month of `created` from a fixed English table ("Date unknown" for one that won't parse - the dev stand-in's float),
none for the played sorts and Most albums.

**The index** (`app/ShelfIndex.tsx`): drawn when the sort has one, Find is empty and the list holds 50 or more.
Letters: all 27, one with no group jumping to the next (or the last); years: the decades present, in the sort's
direction ("Jump to the 1990s"). It is the shelf's sibling in `div.app-shelf-wrap` (a grid: shelf, then a token-wide
column), sticky at `--app-nav-clear` on a phone (0 on a desktop), as tall as the view between the bars (the mini
player's height too; on a desktop the window above the player bar), hidden under a desktop's drawer. `fitIndex`
keeps as many entries as fit at `--app-index-entry` with a dot between each two (the first and last kept, the rest
spread) - the finger's entry is the drawn slot under it (`entryAt`): a letter's own, or over a dot one of the letters
it stands for, spread over the dot's height so a drag reaches each; read over the DRAWN slots, not the strip's box
(see "After review" and "After the second review" below). `touch-action: none`, pointer capture,
a jump on pointerdown and on each entry change while dragging, at most once a frame (one `requestAnimationFrame` per
move - app-rules' frame-loop list gains ShelfIndex, on purpose: no loop). A toolbar with a roving tabindex: Up/Down,
Home/End, Enter/Space. **A jump** is the target head's `scrollIntoView({ block: 'start' })`, instant; the spec's
`scroll-margin-top: var(--app-nav-clear)` was NOT added - html's own `scroll-padding-top` is already
`--app-nav-clear` on a phone, and the two would add (measured: the S header lands at 52 px, the bar's bottom).

**Find**: every word typed (folded: accents, case, "&") a substring of the folded "title artist" - folded by
`findText`, foldName's steps WITHOUT its dropping of a bracketed aside and a leading "The", which are words a person
types to find an album ("deluxe" finds "Dummy (Deluxe Edition)"; the spec said foldName - a deliberate change, said
here). No debounce; the headers stay, the index goes, the count says "12 of 3012 albums", none found "No albums match
“…”.". Escape empties it; leaving the page does (it is the section's state).

**The data: one list per scope, in one request** - `GET /deadwax/navidrome/album_index?scope=yours|store` (a user's
route, `tests/test_logins.py` ROUTES, `test_there_is_no_general_proxy`, test_player_as_you's WALK both ways): the only
Subsonic call is getAlbumList2 (already on the list for /albums), as the asker through client_for, `starred` or
`newest`, 500 a page until a short page or 10,000 (`truncated`), each id once, trimmed to INDEX_FIELDS with the
values as sent, Navidrome's order; a failing page fails the whole answer; sent through `json_with_etag` (moved
unchanged from routes/library.py into `src/api/json_etag.py`), so an unchanged list is a 304. `newest` for the store
because a filing mid-read pushes the rest along (a repeat, left out by id) where an alphabetical read by offset could
skip one. The app's side is `app/albumIndex.ts` (one ask per scope shared by every reader, a generation per scope,
`keptIndex` to draw at once, `forgetIndex`, `refreshIfOld` - INDEX_FRESH_MS, a minute, never while one is on its way);
`app/useYourAlbums.ts` stays as its `yours` face for Search and the artists (Add, Remove and the starred count forget
it; a filing never does - the second review's rule). `refreshIfOld` runs as a section shows (mounting shown, a
desktop's pick coming back, Back to a kept section) and as the Library tab shows (App's `libraryShown`). A list asked
again is swapped in under the one drawn - never emptied; a refresh that fails says "Couldn't refresh: …" with Try
again above the list it keeps. `lib/yourLibrary.ts` lost YOURS_PAGE, YOURS_MAX and sortYourAlbums; yourEmptyNotice
takes an AlbumSort and treats Most played as Recently played.

**The shelf** (`app/Shelf.tsx`): blocks of 60 (`blocks` - 60 divides by 2-6 columns, so a block never ends in a
part row), each `section.app-shelf-block` with `content-visibility: auto`, a labelled group's first block opening with
its head, a grid's block one `div.pl-grid` (so six across on a desktop still holds), a list's a
`ul.app-results.app-library-list`. Its estimate: ceil(items / columns) × a row + the grid's padding less one gap +
the head - read from the first drawn block after its first paint (an effect) and on resize; before that the tokens.
The padding term matters: without it every block was ~10 px too tall and index jumps landed under the bar.

**Windowing: measured, and built at block level.** Step 1 (every tile in the page, the browser skipping what's off
screen) against the stand-in's 3,005 albums, headless Chromium, CPU throttled 4x:

| | open Albums (list kept) | sort change | Find a letter / back | jump to S | a fling's longest task | nodes |
| --- | --- | --- | --- | --- | --- | --- |
| 390×844, step 1 | 2,847 ms | 718 ms | 373 / 709 ms | 70 ms | 52 ms | 12,779 |
| 1440×900, step 1 | - | 902 ms | 369 / 656 ms | 63 ms | 62 ms | - |
| 390×844, built | 148 ms | 75 ms | 83 / 97 ms | 69 ms | 61 ms | 939 |
| 1440×900, built | - | 66 ms | 69 / 67 ms | 69 ms | 59 ms | - |

Opening, the sort and Find were over the 250 ms threshold, so windowing was built - but not the spec's row windowing
(`lib/shelfWindow.ts`: absolutely placed rows in a container of the total height, measured heights per kind, the
focused row pinned, a hidden-shelf scroll guard). Making 12,000 nodes was the cost, not laying them out, so the
windowing is by BLOCK: every block and every header stays in the page, and a block's tiles are made only while it is
within a screen of the view (an IntersectionObserver, rootMargin `100% 0px`). A block drawn once and let go keeps its
real height inline as its place (until the list or the width changes); one holding the focus is never let go; the
observer changes nothing while the shelf isn't drawn (a desktop's hidden view, a phone's section under a page - so
Back finds its tiles); a new list, sort or Find draws at once the blocks within a screen of where the page is, by
the estimates (`blocksNear`), and the observer corrects it. A jump re-aligns its header as the blocks near it are
drawn (a layout effect on the drawn set) until the page's own touch, wheel, key or pointer, or 700 ms. What it keeps
of the spec's goals: every header in the page (VoiceOver's rotor), real elements for Tab (checked: 130 Tabs from the
first tile walk tile after tile across the 60-tile block boundary), the index's jumps exact (the drag lands each
letter's header at the bar, F - absent from the stand-in - going to G). What it costs: the tiles of a far block
aren't in the page until you scroll near them, so the browser's find-in-page can't see them (Find can).

**Real page** (deadwax on 8110 logins on and 8111 off, my stand-in from pl52's with STUB_EXTRA_ALBUMS - 3,000 albums
over ~1,000 artists, "The …", accented, digit-led, non-Latin and empty names, years 1955-2026 with 3% none, `created`
over three years, a third played per user - and STUB_DELAY 0.1 s a call; Chromium as deadwax.test): a cold launch
onto Home asks the Library nothing; logins off the root is Playlists, Albums, Artists, Songs, its 12 from ONE
`albums?order=newest&size=12`, no album_index until a section opens; See all is Recently added with month headers, no
index, its title focused; Albums: Artist with A, B, C… headers and 27 index entries, S lands its header under the bar,
the drag runs letter by letter without the page scrolling of itself; Year newest first has year headers ending "No
year" and a 2020, 2010… index; Recently played and Most played logins off say "Nothing played yet."; Find "dummy"
gives "299 of 3005 albums" and no index; an album and Back as above; both orders kept over a reload; nothing past
the edge at 390, 375 and 320 (the index keeps 27 at 568 px tall: 405 px of entries fit). As james (3,000 starred):
one `album_index?scope=yours` - 813 KB, 132 KB gzipped, 0.76 s (seven pages at 0.1 s); Recently played and Most
played 989 albums. As ethan (a dozen): his 12 on the root, Your artists counting his. As nora (none): the empty
notice on the root and in Your albums, Browse the store replacing the page with Albums in the store, its title
focused, Back to the root. Desktop 1440×900: every sidebar item inline with Find, sort and count on the title's row,
six across, the index at the right edge; with Info as a third column the index's right edge is the panel's left
(970 px); at 1100×800 with Info a drawer, the index hidden; a section page opened at 390 and widened stays a page with
its bar, the sidebar naming it. The store's list from the stand-in: 653 KB, 115 KB gzipped, 0.76 s; a 304 on
If-None-Match. No console errors.

**Changed on purpose in existing tests**: test_navidrome's fixed list (+ `/album_index`, with a docstring paragraph);
test_logins ROUTES and test_player_as_you's WALK (+ both scopes); test_app_css's playlists check (the row in the
root's first group); test_app_desktop_css's chips and Playlists-row checks (their rules gone); artist.sim (Name by
fold key - "The Beatles" under B, `#` last); whose.sim (sortYourAlbums' cases on sortAlbums, the module run against
app/albumIndex.ts with the kept list drawn meanwhile and refreshIfOld, the wiring read off the sections, the root and
App, no scope chips); mylibrary.sim (the New mark read off app/AlbumTile.tsx); app-rules (the Library's rows check
over the new files, the probe and Songs rows read off the root, the desktop root's title and Recently added off the
section, the pages memo keyed on `hasSongs` too, sidebarCurrent's `base`, the libraryShown effect, the Shuffles'
actions from the root and the sections, the frame-loop list + ShelfIndex). New: test_navidrome_album_index.py (21),
shelves.sim, routes.sim's sections, app-rules' "a better Library", test_app_css's shelf and root rows, and
test_app_desktop_css's head, shelf and index.

**Left out, as the spec says**: Genres (deadwax writes none, so they'd be whatever each download carried),
Compilations, Composers, Downloaded, Made for You; a grid/list switch; per-artist headers in Albums; a direction for
every sort (only Year has both); sorted or grouped Songs (Subsonic has no "every song, sorted", and Search finds
songs); Play or Shuffle buttons on the album and artist sections beyond .57's Shuffle; ••• or long-press on tiles;
a server-side cache or a snapshot across launches; per-user sorts (they'd be two PREFERENCES keys, and the Library
would wait for /me/preferences).

**Not verified** (only James's iPhone and server can say): the index drag in Safari standalone; `position: sticky`
with `dvh` there; `content-visibility: auto` and the block windowing in WebKit - whether scrolling back up over
blocks drawn for the first time moves what's on screen (WebKit has no scroll anchoring; the jump's re-align covers a
jump, not a scroll); the real 0.64.2's seven-ish pages' time for his library (its size isn't recorded anywhere), and
the real AlbumID3's bytes (the stand-in's are lighter - no musicBrainzId on the extras); Navidrome's `starred` paging
when two albums share a `starred_at` across a page boundary (a repeat is left out; a skip waits for the next ask).

### After review (2.0.0-player.59)

Reproduced and fixed before it shipped:

- **The index jumped to the wrong letter.** `under()` mapped the finger over the strip's own box - the view's
  height, its 27 letters (`flex: none`, 15 px) centred in it by `justify-content: center` - so at 390×844 a finger
  on A, in a 718 px strip whose letters fill its middle 405, went to G, and a desktop click on A went to H. The
  builder's drag passed because it stepped by box.height/27. Now `extent()` reads the first slot's top to the last
  slot's bottom (every slot, dots too, is one height). (Then mapped over the FULL list - wrong on a thinned strip:
  see "After the second review".)
  Two more came with it: (a) the click a press leaves jumped AGAIN - with the pointer captured a mouse's goes to the
  strip, and on a first tap before the strip is stuck the jump scrolls the page and the strip moves up 161 px under
  the finger, so the click landed on another letter (A went to L). A pointer's jump is now the jump: the button's
  click is let go when `detail > 0` and a press was seen (`pressed`, cleared by the strip's own click after it, by
  pointercancel and by the keys), so Enter and Space (`detail` 0) and a screen reader's activation with no
  pointerdown still jump. (b) A press reads the slots AS THEY WERE at pointerdown (`held`), so a twitch after that
  first jump has moved the strip isn't a drag to another letter. Measured in headless Chromium (3,005 albums, the
  stand-in, logins off): every drawn letter tapped from the section's top and again with the strip stuck, touch
  at 390×844 and 320×568, mouse at 1440×900 and 390×844, lands on its own header (or, with nothing under it, the
  next, as designed); a drag over the drawn letters names each in turn; Enter, Down Down Space and Home Enter
  still jump. At 320×568 the strip's lower letters are below the tab bar until the page scrolls (it is sticky
  beside the shelf, which starts under the title): a tap there reaches nothing, as before. Pinned: app-rules'
  "the index reads the finger over the DRAWN slots" and "a pointer's jump is the jump" (a regex - the layout
  isn't in any sim), shelves.sim's mid-slot `entryAt` points (a round in place of the floor now fails).
- **The sidebar's current pick, clicked from another tab with a section at the Library stack's foot** (reached by
  its address, or a phone's widened to a desktop) opened that section - Albums clicked, Artists shown, and Artists
  marked current by sidebarCurrent's `base`. `sidebarMove` takes the same `base` now: the section's view is "the
  tab", and any other item - the pick's own included - is that view at the Library's root (`router.root`). Pinned:
  routes.sim.
- **Logins off, the root's Recently added never refreshed** (its one newest-of-12 ask, which no generation covers,
  was made once per mount, while See all refreshed after a minute). It is asked again as the root shows
  (`shown`), once the last answer is over INDEX_FRESH_MS old, its grid kept drawn meanwhile. With logins on it
  follows the `yours` generation as before. Pinned: app-rules.
- **docs/configuration.md** still described the chips and the four old orders: its table now has thirteen settings,
  the seven orders with Artist the default, the Library view as a desktop's, and the new Artists order row.
- **Unpinned rules pinned**: choosing an order writes it (both keys); a failed /album_index ask is let go, so Try
  again asks again (whose.sim, the stub failing once); where the amendment puts .57's Shuffles, the root's newest
  12, the 10,000 notice, Find's Escape body and the index's keys (app-rules).
- player.md's "Back from an album ... without asking deadwax again" was untrue after a minute (the kept section's
  `shown` runs refreshIfOld): reworded. CLAUDE.md's map gains `src/api/json_etag.py`.

### After the second review (2.0.0-player.59)

- **A thinned index still landed on the wrong letter.** `entryAt` took the finger's place over the FULL list of 27
  spread over the drawn extent, while fitIndex places its kept letters at `round(n·26/(kept-1))` - the two agree mid
  strip only. At 13 slots ('A•E•J•N•R•W•#', a phone on its side with the mini player) A went to B, E to F, W to V
  and # to Z; at 18, U to T - and the press's own click is let go, so the wrong letter stood. `entryAt(drawn, y,
  top, height)` now takes the DRAWN SLOT under the finger first: an entry's slot is that entry, and a dot's slot
  spreads the letters it stands for over its own height (`before.at + 1 + floor(within · between)`), so a drag still
  reaches every letter left out. With all 27 drawn it is the same mapping as before. `held` keeps the slots with
  their extent, so a press reads one strip throughout. Pinned: shelves.sim - every drawn letter at the top, middle
  and foot of its slot lands on itself at every slot count from 1 to 27; a drag across A•E names B, C, D; a drag down
  the whole strip at 3, 7, 13, 18 and 26 slots reaches all 27.
- **The sidebar item for the open section, clicked again, swapped the view.** With `#/library/section/artists` at
  the stack's foot and the pick left on Albums, Artists was "the tab", whose button pops to the root - and the root
  drew the pick, Albums. `sidebarMove` now carries the section's view on that move (`{ how: 'tab', tab: 'library',
  pick }`) and App's `chooseFromSidebar` sets it (`chooseLibrary`) before `chooseTab`, so the root it pops to draws
  the view the item named. Pinned: routes.sim (the move) and whose.sim (App applying it before the tab).
- **Two refresh rules were unpinned**: the root's Recently added keyed on the `yours` generation, and Your artists'
  `refreshIfOld('yours')` as it shows. Either could be dropped with every sim passing; app-rules pins both now.
