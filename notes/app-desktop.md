# The app on a desktop: the frame, editing, Needs a look, settings and the log

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### The desktop frame (2.0.0-player.19)

Slice 8 of the one app (`uplan/slices.md` S8, numbered .19: built beside .18's pins, on
player-spike, and rebased onto it). The boards are `DesktopLibrary.dc.html` (the frame: sidebar,
grid, player bar), `DesktopRequest.dc.html` and `DesktopRequestBonus.dc.html` (getting an album on a
desktop) and `Main.dc.html`; `DesktopSourcesTable` is the alternative James rejected ("choosing a
source uses CARDS on phone AND desktop"), `DesktopManage` is S9 and `DesktopVisualizer` later.
James's decisions it carries: desktop is "the same app with a desktop frame, not a second app"; the
album you don't have shows its tracklist with a pressing dropdown on both; the turntable is
phone-only ("I don't think it makes a lot of sense on desktop"), a full-screen visualizer comes
later; "Managing links to / for now".

- **THE BREAKPOINT: 1024px, and 1280px for a third column** (`lib/appFrame.ts`, pure, pinned by
  `routes.sim.cjs`: `DESKTOP_MIN`, `COLUMN_MIN`, `frameFor`/`frameOf`). `app/useFrame.ts` asks the
  same two media queries through matchMedia (addListener before iOS 14), so the markup's frame and
  the stylesheets' can't disagree; `tests/test_app_desktop_css.py` reads the constants and holds every
  `@media` in app-desktop.css to them. An iPad on its side (1024px and up) gets the desktop frame.
- **THE FRAME IS CHOSEN IN App, BELOW THE ENGINE**: `useFrame()` right after `usePlayer()` and
  `pickActions`. Crossing 1024px swaps the chrome around the panes and nothing else: the sidebar is
  `{desktop && <Sidebar/>}` before the panes, the player `{desktop ? <PlayerBar/> : <MiniPlayer/>}`
  after them, the tab bar `{!desktop && <TabBar/>}` - each in its own slot, so the panes (each keyed
  on its tab) and their memoised roots and pages stay mounted, the engine's useMemo never runs again,
  and the one audio element (two with Gapless) plays on. Below 1024px the DOM is exactly the phone's
  (a false in a slot renders nothing; `has-mini` only off a desktop). app-rules pins the order and
  the slots.
- **THE PANEL RULE**: Sources and Info are sheets on a phone and a SIDE PANEL on a desktop - a third
  column from 1280px (the shell's `.has-side` makes room: `makesRoom`), a drawer over the main area's
  right edge between 1024 and 1279 (1024 - 232 - 470 = 322px would leave no tracklist). **A panel is
  not modal** (`panelIsModal`): `covered = !desktop && (sheetOpen || sourcesOpen)`, so nothing behind
  goes inert; `useSheet` takes `modal` (no scroll lock when false) and `area` (Escape closes a
  non-modal panel only from inside its box - Escape in the page is the page's: a search field, the
  pressing list); focus still goes in as it opens and back as it closes; no backdrop (CSS);
  `aria-modal="false"`. **One panel at a time**: `openSources` puts Info away (its opener cleared, so
  focus lands in Sources), the player bar's Info (`toggleInfo`) puts Sources away (its opener cleared,
  the search stopped by Sources' backstop). `sideOf` says which shows. Info on a desktop is
  `infoOpen = desktop ? infoPanel : sheetOpen && over === 'info'`, its opener the bar's Info button.
  **Crossing frames** (`closesOnCrossing`): into the desktop Now Playing and what is over it close;
  back to the phone the Info panel does; the Sources sheet stays open across, a panel one side and a
  sheet the other. Search's root and the album pages count as "shown" beside a desktop panel
  (`sourcesOver = sourcesOpen && !desktop` in `searchActive`, `requestsActive` and the pages' `shown`).
  A drawer showing marks the shell `.has-drawer` (`liesOver`): what the page needs beside it keeps to
  the part left in view (the album you don't have's Get and pressing, below), and the Info drawer
  closes as you go to an album or artist from the player (`leaveInfoDrawer` in `goToAlbum` and
  `toArtist`: the bar's byline, Info's cards) - a column stays. A panel's box is a tab stop of -1, so
  a click on its heading or the chips' row (or, in Safari, on a chip, which WebKit never focuses)
  focuses it and Escape there still counts as inside; a sheet's box has no tabindex. And a panel that
  becomes a sheet while open (or back) takes focus in again (`useSheet`'s `modal` effect) unless it
  is already inside - the page going inert behind a sheet, the head's button another one.
- **THE TURNTABLE IS THE PHONE'S ALONE**: Now Playing (and so the turntable) opens only from the
  mini player (`openSheet` - app-rules counts its two mentions), which a desktop doesn't draw; the
  player bar is a desktop's player. Nothing draws `<Turntable` but NowPlaying.
- **The sidebar** (`app/Sidebar.tsx`, a leaf): the wordmark, the search field, Home and Requests (the
  tab's badge, `badgeText`), the Library's views (`SIDEBAR_LIBRARY`: Recently added, Albums, Artists,
  Songs - Songs left out when Navidrome lists none, `libraryItems`), Managing ("Open the main page",
  opening BESIDE the app; the links-out list in app-rules gained it; shown unless deadwax says this
  user isn't an admin - nobody, with logins off: App asks `/deadwax/me` through a latestOnly() as the
  desktop frame shows and hands `admin` down, true until it answers, as You's rows; and no badge,
  since the review-queue count needs the Managing slice's route - built in 2.0.0-player.25, "Needs a
  look": Managing's first item, with its count), and You at the foot. `sidebarCurrent` highlights where the app is
  (`aria-current`; none on Search, whose place is the field); `sidebarMove` is what a click does -
  Home, Requests, You and the Library view showing are tab buttons (selectTab: as left, or back to
  the root), another Library view is that view at the Library's root, opened at its top (App deletes
  the Library root's kept scroll and `router.root('library')` when it was away).
- **The search field is Search's own box** (`app/searchBox.ts`, a module): Search shares its text
  (`shareSearchText` in an effect), takes the sidebar's typing as its own (`onSearchTyped(setText)`)
  and answers its Enter as its form's submit (`submitSearch`) - so the search, its pacing and its
  guards stay Search's. The sidebar's typing also shows Search's results (`showSearch`:
  `router.root('search')` unless at Search's root). Search's own form is `display: none` on a desktop.
  `search.sim.cjs` pins the three.
- **The Library's view is a store** (`app/libraryPick.ts`): the phone's chips and the sidebar both
  choose from it, and both leave Songs out by its `hasSongs` (the Library's one-song probe reports
  there - `setLibrarySongs`). **"Recently added" is the desktop's**: a view of its own (the albums,
  newest first - a second `AlbumsView order="newest"`), so Albums keeps the order chosen for it; never
  kept on the device (deadwax-player-library-view keeps albums, artists or songs), and a phone shows
  the albums for it (`shownPick`). The view being left is told first (`onLibraryLeaving`), and the
  Library keeps its scroll only while its tab is on screen (`getClientRects`) - the sidebar can choose
  from another tab, whose page owns the document's scroll then. On a desktop the Library's title is
  the view's name (`LIBRARY_TITLES`), its chips hidden, its sort and count on the title's row.
  `routes.sim.cjs` drives the store (what is kept, the leaving call before the change).
- **The player bar** (`player/PlayerBar.tsx`, classes `app-playbar*` - not `app-bar`, which is a job's
  progress track: the review found every Arriving card's and Requests row's bar fixed across the foot
  of the screen by the bar's rules, and `test_the_desktops_own_parts_have_class_names_of_their_own`
  now fails on any class the bar or the sidebar shares - the one more file on app-rules' allowlist: toggle,
  next, previous, showAirPlay, each straight from the click): the cover, title and "Artist — Album"
  (Go to album), previous, a round white play/pause and next, Now Playing's own scrubber (`Scrubber`,
  now exported - seek on release, keys; its clocks at its ends by `display: contents`, its thumb shown
  on hover, held or focus), AirPlay when there's a speaker, and Info. The visualizer's place is left
  at the end of the tools, empty (filled in 2.0.0-player.20: the visualizer's button). "Nothing playing" holds its place with no song.
- **The album you don't have, desktop** (`ReleaseGroupPage`'s `desktop`): the cover beside the title,
  Get FIRST and the pressing inline after it (the same one `class="app-rg-get"` app-rules counts), the
  store line under both, and the tracklist as a table (`DeskTracklist`: #, Title, Length, and an
  **"Against the usual tracklist"** column holding each marked track's chip and its note whenever any
  pressing differs - `anyPressingDiffers`, on every pressing so a choice moves no column; none when
  all are alike, as DesktopRequest draws it). The note is the board's short one (`TrackMark.brief`:
  "only on this pressing", "usually 3:58", `usually “X”` - the phone's `note` didn't fit 190px), drawn
  as plain inline text so an ellipsis shortens it (an inline-flex box was hidden whole: "Other version
  …"), the whole note and every title in the cell's `title`. **Its header is a grid** (app-desktop.css,
  `.app-rg` only - the album you have keeps the absolute cover): the cover in column 1, title, artist
  and line in column 2, and until 1280px Get and the pressing in a row UNDER the cover across both
  columns, at the main area's edge - beside the cover they start 236px in, and a 1024px drawer covers
  everything past 322px; with a drawer open (`.has-drawer`) the row keeps to the part left in view, the
  pressing (`flex: 1 1 auto`, its list as wide as it) wrapping under Get with its label shortened -
  the desktop `.app-picker` is `min-width: 0; max-width: 100%`, or its ellipsis never comes. From 1280
  the row goes back to column 2 and the cover spans every row, as the board draws it. **The Sources
  panel follows the pressing**: Get sends `from` (the page's id); App's `sourcesGroup` (only on a
  desktop, only while Sources shows) and `sourcesPressing` (the release the panel searched) give the
  page `sourcesPressing` when the panel shows a Get of THIS album; Get is `aria-pressed` - and a click
  closes the panel - only while that is the pressing on screen (the review: matched on the album
  alone, a page met again at its usual pressing with the panel still open for another read pressed,
  and its first click closed the panel); and while the panel shows another pressing's of this album -
  one chosen here, or the panel left open as you went back and came to the album again - the page
  asks App again with `again: true` for the pressing on screen, focus still going back to Get
  (`getButton`). Only the page that shows asks (`shown`), so the album open on two tabs never takes
  turns. `group.sim.cjs` pins it, and that a phone's Get has no pressed state.
- **The Sources panel** (`Sources`' `panel`): the board's head ("Sources", "for <subtitle>", a ✕ that
  takes focus) instead of Cancel and "Choose a source"; the SAME SourceCards, laid out by CSS as the
  board's (folder and peer inline; the facts a five-column grid, Speed first: `display: contents` on
  the speed's lines and the facts list); and a **Signals** chip before the sort (`SignalsChip`: a
  slider per signal of `SIGNAL_LABELS`, 0 for any, a count on the chip, Reset, Escape taken there so
  the panel stays). The minimums go through `candidateFilters(filters, minSignals)` - the cards and a
  pick - and `pressedCount` counts them, so Clear filters shows for a minimum alone and clears them.
  **Only where the chip is drawn**: `minimums = modal ? undefined : signals` - carried into a phone's
  sheet (a window narrowed with the panel open, an iPad turned upright) they are kept but filter
  nothing, and are back on the panel (the review: they went on hiding cards with no chip on screen).
  **`again`** searches with `start(release, false)` - `useCandidateSearch`'s new `fresh` - keeping the
  chips and minimums and never picking, even with "Pick the best source for me" (you are choosing);
  a fresh Get in the panel re-seeds the chips and picks as on a phone. `sources.sim.cjs` pins it all.
- **Style**: `interface/player/app-desktop.css`, linked LAST (test_pages), revalidated and gzipped
  like app.css. EVERY rule inside `@media (min-width: 1024px)` (or 1280px, or 1024px and a coarse
  pointer) and every selector but `html`/`:root` under `.app-desk` - the phone app can't be reached
  by it (`test_nothing_reaches_the_phone`). Tokens only (`--app-desk-*` in the media query's
  `:root`, which also points `--pl-edge-left`/`-right` at the desktop's 32px and the scrub track at
  6px). theme.css section 10 gains the frame's surfaces (`--dw-sidebar`, `--dw-side-panel`,
  `--dw-player-bar`, `--dw-frame-border`, `--dw-row-border`, Explorer's `--dw-selection-*`,
  `--dw-selected-text`) and, in its own `@media (min-width: 1024px)` `:root`, the desktop's values
  for the look's tokens: labels 11px, headings 13px, data 12px, titles 28/30px, the album's artist
  18px, cards #1e1c26 on #0b0a10, the pressing list a desktop list. **`--dw-text-body` is NOT
  redefined**: text fields read it, and an iPad on its side is a desktop where iOS zooms into a field
  under 16px - the sidebar's field takes the board's 13px only for a fine pointer.
  **A coarse pointer gets a finger's targets** (the review: the board's 16px scrubber sat 6px under a
  22px Previous on an iPad): in `@media (min-width: 1024px) and (pointer: coarse)` the scrubber, play,
  the transport's boxes, the bar's tools, the sidebar's items, the rows, Get and the pressing, a
  panel's close button, chips and a source's Get are all `--pl-hit`, and the bar is
  `--app-desk-bar-touch` (100px: the transport's 44 over the scrubber's 44, no gap) plus the home
  indicator's `--pl-safe-bottom`. **Beside a third column** (`.has-side`) the grids are `auto-fill`
  at `--app-desk-tile-min` (150px, the phone grid's), never more than six (each column the larger of
  that and a sixth of the row; Arriving's cards: three) - six in 514px were 66px covers at 1280. **A
  source's facts** in the panel are `min-width: auto` and wrap between words (the phone's
  `min-width: 0` let "FLAC 16-24/44.1-96" run over Size and "12 ahead" out of the card).
- **The phone app below 1024px is unchanged**: no phone rule, class or DOM order touched (the
  orchestrator compares 390x844 screenshots of 2.0.0-player.17 with this). Home, AlbumPage,
  ArtistPage and NowPlaying are edited only as layout needs (Home and ArtistPage not at all;
  AlbumPage not at all - its desktop header is CSS; NowPlaying exports `Scrubber`), so .18's rebase
  stays small.
- **Not built, on purpose**: pins (.18, in parallel); the visualizer (later - its place is left; built in
  2.0.0-player.20, see "The desktop visualizer");
  the turntable on a desktop; the desktop editor (S9, DesktopManage - built in 2.0.0-player.21, "Editing
  an album on desktop"); the comparison table (rejected);
  "Mine / Everything in the store" (logins are off); the sidebar's "Needs a look" count (built in
  2.0.0-player.25, "Needs a look"), Settings and Log as their own items (one "Open the main page" link
  until the Managing slices; built in 2.0.0-player.33, "Server settings and the log in the app"); Lyrics
  and Queue in
  the bar (nothing for them to open); a desktop Now Playing; "Results for …" as the breadcrumb (the
  back label stays the tab's name). You's "Now Playing opens as" and "Pause winds the record down"
  still show on a desktop - they are this device's phone settings, and an iPad turns between frames.
- **Verified**: 2133 Python tests (22 new: `test_app_desktop_css.py` 20, two in `test_pages.py`),
  pyflakes, tsc, and all 35 sims (`routes` 182, `app-rules` 156, `sources` 89, `group` 91, `info` 127
  and `search` 71 extended, `pressings`' marks given their short note); 67 mutations, one or more per rule pinned, each caught and
  restored byte for byte - three first survived (the panel precedence when both were open, Clear
  filters for a minimum alone, and a guard in the follow effect that turned out unreachable and was
  removed) and gained the checks that catch them. The engine guard is empty and `player.sim.cjs`
  untouched. **After review** (22 findings confirmed, 17 once duplicates are merged, and a class clash
  a skeptic found - all fixed, each testable one with a check that fails without it, mutated and
  restored - 39 mutations, all caught): the `app-bar` class clash; a finger's targets on a coarse pointer; the
  against column's short notes, inline and with tooltips; the pressing's width; the facts' columns;
  the grids beside a column; Get and the pressing under the cover, clear of a drawer; Get pressed only
  for the pressing the panel searched, and the page met again following it; Signals filtering only
  on the panel; a panel's box focusable by a click; focus in again across 1024px; the Info drawer
  closing on Go to album; the sidebar's Managing on `/me`; useFrame itself driven against a fake
  matchMedia in `routes.sim.cjs`, with app-rules holding toggleInfo's close and the shell's classes;
  the two Signals rules sources.sim claimed and didn't pin (a pick with a minimum set, a fresh Get
  clearing them); and the guides' wording (no boards or slices, the sliders' own names, You's two
  phone-only settings, the Library view's click).
  **NOT verified here**: the real page (the orchestrator builds the bundle and checks at 1440x900,
  1280x800 and 1024x768 against the stubs, resizes across 1024 while playing - one audio element, the
  music carrying on - compares the 390x844 screenshots, and runs the overflow audit); the drawer and
  column's look; the Signals popover's place at the panel's edge; an iPad on its side (the coarse
  pointer's 44px targets and taller bar); the group page's grid header at 1024-1279 and its row clear
  of a drawer; the grids' column count beside a panel; a source's facts wrapping; and the boards'
  exact spacing, which the CSS follows from the boards' numbers but nobody has seen drawn.

### Editing an album on desktop (2.0.0-player.21)

Slice S9 of the one app (`uplan/slices.md` S9, numbered .21: built beside .20's desktop visualizer on
player-spike, and rebased onto it). The board is `DesktopManage.dc.html`: the album page's **Edit**
toggle, and an "Edit album" side panel with underline tabs - Release, Tags, Artwork, Lyrics, Delete.
James's decisions it carries: "Managing links to / for now" (so the review queue, settings and the
log stay the main page's); no editor on the phone (there is no board for one); the editors are the
main page's, reused - their hard-won state rules stay exactly as they are.

- **Edit on the album page, a desktop's and an admin's**: App hands AlbumPage `onEdit` only when
  `desktop && admin` (`admin` is the `/deadwax/me` answer the sidebar's Managing reads - true until
  deadwax says otherwise, so everyone with logins off), and AlbumPage draws Edit (`pl-pill
  app-edit-toggle`, `aria-pressed` while the panel shows this album) after Play and Shuffle only when
  handed it - so below 1024px the DOM is the phone's, untouched. Live once the album has answered:
  its tap hands App the album as Navidrome sent it (`lib/albumEdit.ts` `editAlbum`), which is what
  the panel finds the folder by when the store can't.
- **A third side panel, by the frame's rule** (`lib/appFrame.ts`): `Side` gains `'edit'` (`sideOf`
  takes `{ sources, info, edit }`; were two ever open, Info, then Edit, then Sources), so `.has-side`
  and `.has-drawer` come from it as from the others; one at a time - `toggleEdit` puts Sources (its
  search going with it, by Sources' backstop) and Info away, `openSources` and `toggleInfo` put Edit
  away, Edit pressed again on its album closes it; `closesOnCrossing('phone').editPanel`; and App
  draws `{desktop && <EditPanel .../>}` after InfoSheet (app-rules' Sources-then-NowPlaying checks
  stand). **The panel is the album page's**: it closes as that page stops being the one on top of the
  tab showing (`editShown`, an effect) - another page, a tab, the sidebar. Not modal (`useSheet` with
  `modal` from the panel style - never a sheet), focus in to its close button and back to Edit,
  Escape from inside it; its box a tab stop of -1, as Sources' is. 470px, the frame's panel token
  (the board draws 440), so the shell's `.has-side` room holds.
- **The editors, reused - `ui/src/components/` has no diff**: Release is `MetadataEditor` (keyed on a
  `session` counter that moves per album and per folder chosen, never per apply - the main page's
  rule); Tags is the panel's own track list with a tick box each (`TagsList`: `tickTracks` from
  lib/tagEdit.ts, Shift for a run, the head's tri-state box) and `TrackTagEditor` for the ticked ones -
  or all, none ticked - its file list fixed as it opens, its details from `useTrackDetails`, fetched
  only once Tags has been opened (generation: the panel's library albums, as on the main page);
  Artwork is `GetArtButton` and `GetDiscArtButton`, with a line saying why when either draws nothing
  (it has a cover - replaced in Release, comparing; no release id - match one first); Lyrics is
  `GetLyricsButton` and the count; Delete is `DeleteAlbumDialog`, mounted only while its tab shows so
  its summary is read live. "Tick boxes on the track table" is read as the Tags tab's table (the
  scan's filenames), not the album page's Navidrome song list: pairing Navidrome's songs with files
  needs paths Navidrome reports only with ReportRealPath, and an untagged file - the case hand edits
  are for - has no track number to pair by.
- **Escape, twice over.** The editors listen for Escape on the whole document and close themselves
  (the main page's floating windows always did). Beside the page that Escape is the page's, so the
  panel takes keydown in the CAPTURE phase and passes over an editor's close or cancel while an
  Escape from outside its box is still being dispatched (`escape.current.eventPhase !== 0` - a
  dispatched event's phase is 0 once it is done; clearing a flag in a microtask would be too early,
  since a native dispatch runs a microtask checkpoint after each listener). Inside the box Escape
  closes the panel (useSheet, and the release editor's own close - both the same) - EXCEPT in a layer
  over a tab, the tag editor or the delete confirmation (review): there Escape is that layer's alone
  (useSheet's `covered: inner`, and the capture listener records the press as `'inner'`, which the
  release editor's close - listening on the document whatever tab shows - passes over). Where it came
  from is recorded in the capture phase, before any listener has changed state: a re-render in the
  checkpoint after the tag editor's own listener would otherwise make the release editor's see the
  layer gone. The cover viewer still stops Escape on `window`'s capture before anything hears it, as
  on the main page - and is let go with the editors once the panel has closed (below), so it can't go
  on taking the next Escape anywhere in the app.
- **Which folder** (`editFolders`, pure, routes.sim): the id bridge's `present` rows, asked by the
  page's Navidrome id (`/store/album`, through a latestOnly); else the library's scan by the release
  (the bridge's, else the album's own `musicBrainzId` - the bridge failing degrades to this) - and
  NEVER by name for a tagged album; else, no release anywhere, the scan's untagged folders by
  `foldName` of the name and artist, narrowed by Navidrome's `songCount` when that still leaves
  several. Several by name are a choice the user makes (`needsChoice`: a guess could hand the release
  editor the wrong copy); several of one release - a set kept one folder per disc - start on the
  first, a Folder select above the tabs for the rest. **The scan fallback is not optional**: the
  bridge answers nothing for an album Navidrome knows by no release, and that is the v0.9.33 staged
  rip - the album the release editor exists for. The scan is `useLibrary` (the main page's hook: the
  saved scan, then a real one), read the first time the panel opens, and the album taken only from a
  REAL scan (`loaded && !stale`) - and read AGAIN underneath on every Edit after that (review: the app
  is a player left open for hours, and an album changed from the main page or another device was
  shown as the first read had it, with no way to refresh): the album is taken from the scan in hand
  at once and followed to the fresh read by path - let go, to be taken again from the fresh folders,
  when its folder is gone - unless a write was made meanwhile (`writes`, a count), whose own reload
  followed it already. The bridge's answer counts only for the Edit it was asked for (`askedFor`).
- **The album is held, never derived** (the main page's lesson about a rename landing as two
  commits): `subject` is set once and followed from the array `library.reload()` resolves with, a
  functional update keyed on the old path. Each write carries the Edit it was made under
  (`afterWrite(at, ...)`): an apply that waited for Navidrome can land after another album's Edit.
- **After a write** (`AlbumChange`, App's `albumChanged`): `written` - `announceAlbumsFiled()` (the
  owned marks, an album-you-don't-have page's store line; the panel's own useLibrary rescans after its
  gather, cheap and ETag-unchanged) and the album page asked again; `settled` - asked once more after
  `EDIT_SETTLE_MS` (10 s: Navidrome's watcher waits ~5 s, then scans); the folders re-asked by
  release; and, only after an apply that CHANGED the album's release (`followRelease`), its new id
  looked for by that release (`FOLLOW_LOOKS_MS`: at once, 3, 6, 12, 24 s - 45 s in all) - `moved`:
  the page on top becomes that album's in place (`becomeTop` / `Router.become`: the entry replaced,
  never pushed; the preview and the scroll carried to the new key), the panel following it (the same
  request key, the new id). Only a changed release, because Navidrome makes an album's id from its
  release id when it has one (its PID - "The 1.0.1 fixes"): a retag or rename keeping the release
  keeps the id; the staged rip gaining its first release, or another one applied, gets a new id.
  `deleted` - the panel closes, the page goes back when nothing of the album is left in Navidrome
  (`deletesAll`: its only folder, or - found by name among several, which Navidrome may keep as
  albums of their own - one holding as many songs as Navidrome lists), and otherwise is asked again
  at once and after `EDIT_SETTLE_MS`, as after any write (review: it was asked once, before
  Navidrome had noticed). The asking again goes through one latestOnly() - the next write calls the
  last one's off - but the LOOK for a new id has a latestOnly of its own (`follows`, review): a write
  straight after an apply (CD art, a hand edit, a cover) used to call the look off and start none,
  leaving the page on an id Navidrome no longer had. App remembers each move (`moves`, `noteMove`):
  a page of the old id that comes back on top - back, forward, its tab chosen, the page left during
  the rename's wait - becomes the new one's by the same `become` (`movedTo`, an effect on `nav`), and
  a `settled` landing after its move asks the new id.
- **AlbumPage's `refresh`** (App's `refreshes`, a count PER ALBUM - one album asked again never
  changes the prop another is handed, so nothing else re-asks): the album (prefetchAlbum `fresh`,
  then taken) and the bridge asked afresh, what is drawn kept until they answer, a failed refresh
  silent - the album may be under a new id Navidrome hasn't scanned yet. app-rules holds the pages'
  memo to `admin, editOpen, edit, refreshes` too.
- **Style** (app-desktop.css, every rule under `.app-desk`, inside the desktop media queries): the
  panel joins the side panels' shared rules (`.app-edit` beside `.app-sources` and `.app-info`), the
  board's underline tabs (2px accent rule, the chosen white and semibold), Edit toggled while it
  shows; and the main page's editors styled by their own ids under `.app-desk .app-edit`
  (`#metadata-window`, `#tags-window`, `#delete-window`, `#art-viewer`, their classes and the main
  page's colour classes in this page's palette) - no main.css and no resize.js on this page, and a
  side panel neither moves nor resizes. The editor's own ✕ is hidden (the panel's stands for it);
  Apply is the solid purple at the board's 36px, sticky at the panel's foot with the summary;
  "delete permanently" is the one red button (`--dw-danger-bg`, `--dw-danger-border`, new in
  theme.css section 10). Busy is player.css's `pl-spin` ring - app-desktop.css can't hold keyframes
  (its only contexts are the three media queries test_app_desktop_css holds), and theme.css's
  reduced-motion rule stops it after one turn. The cover viewer is drawn inside the panel (beside the
  editor's window, as the main page draws it) and `position: fixed` is still the window's: the
  panel's box has no transform once open, and overflow never clips a fixed box; its z is within the
  panel's layer (30), over the frame (8). A coarse pointer: controls and Apply 44px, the tabs a
  finger's height, the fields 17px (iOS zooms under 16), the viewer's touch hint. Tokens
  `--app-desk-edit-*`, `--app-desk-spin*`, `--app-desk-viewer-*`, `--app-z-edit-viewer`.
- **After review** (21 findings, every one fixed but a footer order - all in the panel's own files,
  `ui/src/components/` still without a diff): the editors drawn only while the panel shows and let go
  once it has closed (`letGo`: at once as a column, after `EDIT_SLIDE_MS` for a drawer) - every Edit is
  a new request anyway; the follow's own latestOnly and the remembered moves (above); the library read
  again on each Edit (above); what the body says moved to the pure `editStatus` - nothing over an album
  still HELD (a hand edit renaming an untagged album out of the name it was found by had put "can't
  tell which folder" over working editors), and a failed real scan after the saved one said with Look
  again rather than "Finding…" for good; a control that removes itself (Edit N tracks…, the tag
  editor's Close, Delete's Cancel, Look again, a folder chosen) hands focus on inside the panel once
  the swap has drawn (`focusNext`, a layout effect - only when focus fell to the body), and after a
  move App re-points what focus goes back to at the new page's Edit; a delete of one folder of
  several gives focus back to Edit. CSS: the album page's Play, Shuffle and Edit go under the cover
  while a drawer is open (`.has-drawer .pl-album-page:not(.app-rg)`, as `.app-rg`'s Get - Edit's own
  drawer had covered Edit from 1024 to about 1225px); a tag's raw key broken inside the preview's 84px
  column; busy words inside Apply, the tag editor's Apply, the viewer's Save and "delete permanently"
  the button's white; a pressing's track count on its first line (`order`); long names broken, never
  clipped (the panel's notes, the delete warning's other files, the tag editor's list); and each tick
  box in a label filling its cell, 44px where the pointer is coarse (`--app-desk-edit-tick`), with the
  panel's other small targets. **Not changed**: Apply before Cancel, as the board draws them - the
  reused editors keep their DOM order, and reordering by CSS would part what is seen from the
  keyboard's order.
- **Not built, on purpose**: an editor on the phone (no board); the review queue's stepping (Review
  N), the bulk runs, artist images and re-filing (the main page's still - FRONTEND-MIGRATION lists
  what remains before parity); tick boxes on the album page's own song list (above); following an
  album with NO release id through a hand edit that changes its Navidrome id (nothing to look it up
  by - the page keeps what it drew); the Library's grid refreshing itself (it is Navidrome's).
- **Verified**: 2219 Python tests (17 new: `test_store_lookup.py` 5 - a row's path IS the folder the library's
  routes take, a folder at the library's root and one of awkward characters, a re-file answered at the
  new folder by the same row, a merged disc folder left holding a cover answered as the one it joined,
  and an album deleted through the route answered as nothing; `test_app_desktop_css.py` 12, 6 of them
  the review's), pyflakes, tsc, and all 37 sims (`routes` 218 and `app-rules` 198 extended); 64
  mutations, one or more per rule pinned, each caught and restored byte for byte - and 49 more after
  review, one or more per fix and per rule the review found unpinned (the release editor keyed on the
  session, the needsChoice guard, `loaded && !stale`, `useLibrary(open)`, the tagsSeen gate, albumChanged's
  follow, count, ask and close, `prefetchAlbum`'s `fresh`, the Escape's direction and each handler's
  guard), all caught - two first got past and gained the checks that catch
  them (the release compared without its case on the BEFORE side too; the merge test, whose disc
  folder had been removed, so the bridge's own liveness check hid it whether or not it was marked
  merged - it now keeps the folder, holding the cover a merge leaves behind). The engine guard is
  empty, `player.sim.cjs` untouched, and `ui/src/components/` and `ui/src/hooks/` have no diff;
  `tags.sim` and `queue.sim` pass as they were.
- **Verified in the real page** (headless Brave against the stubs on :8082, real mouse input at
  1440x900, 18 checks): the v0.9.33 staged-rip check - Portishead's Third copied to the library's root
  as `Third rip`, its MusicBrainz tags, original date, pictures and cover stripped. The album page
  has Edit; Edit opens the panel as a column, which finds the rip's folder by name; Release lists the
  pressings, a pick draws its preview, says it renames and will wait for Navidrome first, and Apply
  says it is applying; the folder is re-filed as `Portishead/Third (2008) [Made in Germany by EDC]`
  and the rip folder is gone; **the page follows the album to its new id**; the tag editor opens on
  two ticked tracks and writes the genre to those two only; Get CD art answers; Delete shows the
  summary, deleting closes the panel and goes back from the page, and the folder is gone from disk;
  a phone has no Edit; no console errors. Two bugs it found, both fixed here:
  - **The bridge handed out a stale id.** `navidrome_album` kept a release's Navidrome id for ten
    minutes and trusted it: an apply writes the tags, Navidrome scans the album at its OLD folder
    (a Navidrome that ids albums by folder, as the stub does), the bridge finds and keeps that id,
    and the rename a moment later gives the album a new one - which the bridge then never reported.
    A kept id is now checked with one getAlbum before each use and looked up afresh when Navidrome
    no longer has it as that release (kept as found while Navidrome can't be reached).
    `test_store_lookup.py` has three new tests, each failing with the check taken out.
  - **The page's follow gave up at once.** `lookForMove` stopped at the first answer with any id -
    and right after a rename that answer is the page's OWN id (the album still listed at the old
    folder, scanned between the tags and the rename). The page's own id is no answer now: the look
    goes on until Navidrome has scanned the move, or its ~45 s run out. With a Navidrome that keeps
    ids across a rename, that is five small requests and the page stays, as it should.
    `app-rules.sim` pins it.
  Also from the real page: "In your library" and its chips sat centred mid-column on the desktop
  album page, the phone's centred row under a left-aligned hero (a .19 slip); `.app-desk
  .app-album-chips` now starts them under the title. **After the rebase onto .20**, the Edit panel
  takes `covered` as Sources and Info do: built beside the visualizer, it stayed live and tabbable
  under it (app-rules pins it, and fails without it). An Escape from the visualizer is the page's to
  every editor, so none closes under it. **Totals after the rebase**: 2227 Python tests, pyflakes,
  tsc, all 40 sims (`app-rules` 231, `routes` 218).
  **NOT verified here**: the editors' look at 1280x800 and 1024x768 (the drawer, with Play, Shuffle
  and Edit under the cover), an iPad, a real Navidrome giving the new id after an apply (search3 by
  the release id, the title fallback), and, of the review's fixes, the label forwarding a Shift-click
  to its box, focus landing where `focusNext` sends it, one Escape closing one layer, a cover viewer
  gone with the panel.

### Needs a look (2.0.0-player.25)

The first of the Managing slices (the plan's section 10: the review queue with a cheap summary route;
server settings, the log and the bulk runs are later slices). There is NO board for this screen; the
boards only name it - the desktop sidebar's Managing has "Needs a look" with a count, You has "Albums
that need a look" with a purple count - so it is built from STYLE.md and the desktop frame's parts. The
spec is the session scratchpad's `uplan/slice-needs-a-look.md`. Its rules are the main page's review
queue's, carried over exactly ("The metadata queue stores only what you IGNORED", "The tab badge and the
queue must never count different things", "Prune review rows...", "The new-import prompt is recorded at
import time", "Don't derive an overlay's subject from a list that a write reloads", "The editor is keyed
on a step counter"); LibraryView.tsx, `ui/src/components/` and `ui/src/hooks/` have no diff.

- **Where it is**: the desktop sidebar's Managing, a new first item "Needs a look" (`SIDEBAR_QUEUE`,
  `SidebarId` 'queue') with Requests' badge look and `badgeText`'s rule ("Needs a look, 3 albums" to
  VoiceOver, `needsLookLabel`), above "Open the main page" (whose title then named what was still the
  main page's: server settings, the log, the bulk runs, artist images - the settings and the log built
  in 2.0.0-player.33, "Server settings and the log in the app"); `aria-current` while its page is on
  top (`sidebarCurrent`'s new `page` argument: the queue page is its item whatever tab it is on). And
  You's "Managing deadwax", desktop only, admin only: a row "Albums that need a look" with the same badge
  (`.app-queue-badge`), above the link to the main page; on a desktop the footnote no longer claims the
  queue and the editor are the main page's. Both go through App's `openQueue`: You's tab as it was left,
  the page pushed over it - nothing when it is already the page on top there (two history moves are
  never a back and then a push: `history.go` is asynchronous).
- **The route** (`lib/appRoutes.ts`): `PageKind` 'queue', `#/you/queue/all?facet=<id>` - ONE page
  (`QUEUE_ID` 'all'; any other id in an address is it, made canonical), the facet in the address as a
  group page's pressing is and, like it, not its identity: `replaceTop` compares and carries both
  `release` and `facet`, `scrollKey` leaves both out, `samePage` is kind and id. A facet chosen is
  `router.update` (App's `pickFacet`): the entry replaced, so a reload keeps it and back leaves the page
  in one step. routes.sim drives it end to end.
- **The count: `GET /deadwax/library/queue/summary`** -> `{known, needs_attention, new_imports, total,
  unscanned_imports, tracking_enabled}`. It NEVER walks the disk: `snapshot_library` (the saved scan,
  loaded from the database by `_ensure_cache_loaded` after a restart) decorated exactly as
  `/albums?snapshot=true` decorates it (`attach_issues` with `album_reviews`), and `total` is what
  `queueAlbums(albums, null)` lists over it - an outstanding issue, or `imported && !reviewed` - so the
  badge and the page count the same albums BY CONSTRUCTION (`test_the_badge_and_the_page_count_the_same_
  albums` runs both over one library; needslook.sim holds the page's All count to `summaryTotal`, which
  is `queueAlbums(albums, null).length`). **One thing beyond the spec's letter**: an import row whose
  folder the saved scan doesn't hold (filed since the last scan - the poller writes the row as it files,
  the scan cache learns the folder only from the next scan) is counted too (`unscanned_imports`, read by
  attach_issues's own rule: source 'import', no `reviewed_at`), because "the new-import prompt is
  recorded at import time" - a badge blind to the album just downloaded would be the 1.1.2 bug again. With
  no saved scan at all `known` is false and `total` is `store.new_import_summary`'s count, never a real
  scan in its place. No LIBRARY_PATH or no store: zeros, `known` false, a 200. No ETag (optional, not
  built). `tests/test_queue_summary.py` (10) through `TestClient(start())`.
- **The app's one store of it: `app/useQueueSummary.ts`** (a module, as useOwned and usePins): one
  request in flight and one "ask again"; asked by App's `useEffect([desktop, admin, pageShown])` - as the
  desktop frame first shows for an admin and as the app comes back from hidden; by `albumChanged` on
  EVERY change the Edit panel reports; by the queue page after each album it marks reviewed; and by
  `onAlbumsFiled` once anything has asked. No timer. While the queue page shows with a REAL scan and no
  session its own All count stands in (`setPageQueueCount`, cleared as it hides, starts a session or
  goes); a failed ask keeps the last number, and with none the count is null - no badge drawn over an
  unknown (badgeText(0) is '' anyway).
- **The page: `app/NeedsALook.tsx`**, its pure rules `lib/needsLook.ts`. The library through the main
  page's own `useLibrary(desktop && shown)` - the saved scan drawn at once, a real scan underneath - read
  only once it first shows, and read again (ETag'd) when it shows again later with nothing under way.
  Title "Needs a look" under a back button; `NEEDS_LOOK_LINE`; facet chips (the Library chips' look,
  `aria-pressed`): All N, Newly added N (`NEW_FACET`, only when there is one), then one chip per issue
  type with albums, the most first, then by label, each titled with its hint (`facets`); the list is
  `facetAlbums` = `queueAlbums(albums, facet)` (Newly added: its new imports, in its order); a facet
  that has emptied shows All (`facetShown`) and the address is told once a real scan says so. A row is a
  button: the folder's cover (`albumArtUrl`, the plain tile when none or a failed load), album, artist
  and edition (`disc_label`, else `edition`), "New" for a new import, its outstanding issues as chips.
  States: the spinner until the first answer; `problem` (LIBRARY_PATH) plainly; a failed read with
  nothing to show, with Try again; "Nothing needs a look."; and "Checking the library…" in a line that is
  always in the page and a row tall (`.app-queue-checking`, its going moves no row; a failed refresh
  with albums on screen is said there, with Try again). No solid purple: Apply in the panel is the
  screen's one.
- **The session** (`startSession`, `stepTarget`, `rowChanged`, `markFor`, `leavingAtEnd`): a row
  clicked fixes the list as shown (facet applied) - its paths, in order, the clicked one current. While
  it lasts the rows drawn are the SESSION's, never the scan's: an album fixed, ignored or deleted stays in
  its row, faded, saying **Fixed** / **Ignored** / **Deleted** (`MARK_WORDS`; judged against what put it
  in the list - every issue gone and none accepted is Fixed, some accepted Ignored, a clean new import
  nothing), a re-filed one followed to its new path (`rowChanged`, by the path it had). Stepping away
  from an album - Next, Previous, another row, the panel closing, the page left (an unmount cleanup) -
  marks it reviewed (`markReviewed`, then the count asked again), never one deleted here
  (`mark_album_reviewed` would write a row for a folder that isn't there). An album gone when stepped to
  ends the session, as leaveQueue does: deleted here, or absent from the page's own scan - unless a
  write has told the page of it (`heard`), since that scan may predate a rename. The session ends as the
  panel closes (an effect: `editing` back to null after the page has seen it open - `opened`), the facet
  changes (the panel closed with it), or the page goes; its rows are held (`ending`) until the fresh scan
  that ends it lands, then the list is worked out again. Its own row clicked again closes the panel, as
  Edit pressed again does. (The review's rules for the ending - the scan asked after the note, held
  rows refused, the chips held too - are under "After review" below.)
- **The Edit panel on a FOLDER** (`FolderRequest` beside the album page's `EditRequest`; `isFolderRequest`):
  `{folder, key, queue, reread, onChange}`. No bridge (`lookUp` marks the request asked, superseding any album-page lookup still out and clearing its answer), no name
  guess (`folderOnly`, `FoldersFrom` 'folder'), the subject taken from the panel's own scan by path; the
  library read again underneath only for a session's first album (`reread`; a step between two uses the
  scan the session began on - a scan per step would stat the whole library each Next); the release editor
  given the request's `queue` - its existing QueueContext ("3 of 17", ◁, skip ▷, Apply becoming "Next
  album ▷"), MetadataEditor untouched, keyed on the panel's `session` as before (a new request per step);
  what became of the album told by path (`toFolder`): to the page (`onChange`, FolderChange: from, the
  album as the panel's reload has it, deleted) and to App (`{kind: 'folder', from, path, wrote}` - an
  ignore or un-ignore is `wrote: false`: no file changed, so no announceAlbumsFiled). A delete there
  leaves the panel open saying so, with "Next album ▷" to go on (the row says Deleted). `deletesAll` takes
  an album that may be undefined. Every album-page rule stands; app-rules' Edit checks were EXTENDED to
  the union's spelling (`edit?.album?.id`, `editShown`'s queue branch, `!isFolderRequest(at)`), none
  weakened. The panel is the queue page's by the same rule: `editShown` is `topNow?.kind === 'queue'` for
  a folder request. **An album page of the same album elsewhere in the stacks is NOT followed** after a
  write from the queue - nothing keys it on a folder (acceptable, the spec says; docs/library.md says so).
- **App**: `openFolderEdit` (the one-panel rule - Sources and Info put away; `opener` the row, focus
  given back to it, re-pointed at the new current row on each step), `openQueue`, `pickFacet`,
  `queueView` (no Navidrome gate - nothing on it is Navidrome's), the pages memo already keyed on all it
  reads (nav, desktop, pageShown, editOpen, edit). You memo keyed on desktop and the count.
- **Style** (app-desktop.css, its own section at the end - every rule under `.app-desk` inside the 1024px
  query; tokens `--app-desk-queue-*`): rows at the frame's row height (`--app-desk-row`, 44px where the
  pointer is coarse) with a 28px cover; the chips give way before the album's name - the tree row's
  lesson: `flex: 0 var(--app-desk-queue-give) auto` (1000) against the name's `1 1 auto` and a
  `min(120px, 100%)` floor, and never cut to a stub: one line of whole chips (`flex-wrap: wrap`, a fixed
  height, overflow hidden), one alone ellipsizing; the row the panel has open in Explorer's selection;
  a row dealt with faded (`--app-desk-queue-done` on its cover and words) but never its word (green, at
  full strength); a drawer (1024-1279) keeping the list to the part left in view (`.has-drawer
  .app-queue-body`, as the group page's Get). The editor's ◁ and skip ▷ a pair with a gap
  (`.metadata-queue-nav`), its position in the secondary grey. On a phone the page is the app's own
  card for a page with nothing to show (`app-card app-placeholder-body` in `app-needs`, for the link's
  colour) - no CSS of its own there, and no other phone screen's DOM touched (the You row and the
  sidebar item are desktop-only, the phone's Managing footnote word for word as it was).
- **Not built, on purpose**: server settings, the log (both built in 2.0.0-player.33, "Server settings
  and the log in the app"), the bulk runs, artist images, re-filing, a phone editor, "Everyone's
  requests"; anything retired on the main page (LibraryView.tsx unchanged); an ETag
  on the summary; following an album page of the same album after a write from the queue.
- **Verified**: 2349 Python tests (10 new in `test_queue_summary.py`, five in `test_app_desktop_css.py`),
  pyflakes, tsc, the bundle, and all 43 sims (`needslook` 64 new; `routes` 237, `app-rules` 246 and `you`
  66 extended, app-rules' Edit checks moved to the union's spelling). 43 mutations, one or more per rule
  pinned (six on the route, eight on the pure rules, thirteen on the page - the re-show read among
  them - five on the routes and sidebar, eight on App, the panel, You and the store, three on the CSS), each caught and
  restored byte for byte (checked by hash). The engine guard is empty; `ui/src/components/` and
  `ui/src/hooks/` have no diff.
- **Checked in a real page** (headless Chromium, real mouse input, against a scratch copy of the step1
  library and database served by this worktree on :8095 - never the dev setup's :8081 - with a stranger's
  rip of Third staged at `Old Rips/Third rip` and The Slow Rush given an import row; 27 checks): You's row
  and the sidebar item with the count (1 - the import alone - before any saved scan, then 3); the page,
  its item current; the badge equal to the page's All count and to the summary route's, now from a saved
  scan; a row opening the panel, the row selected (aria-current), the editor saying "2 of 3"; **It's fine
  as it is** turning the row to Ignored in place, no row moving (pixel tops unchanged); skip ▷ moving the
  panel and the selection on; another row and closing the panel ending the session, the list worked out
  again (the ignored rip gone) and the new import no longer new; the badge following; a facet in the
  address, kept by a reload; at 1024 and 1280 every row clear of the panel, no sideways scroll; on a
  phone the note and no You row; no console errors.
- **NOT verified**: an apply through the queue in a real page (the scratch library is hard-linked to the
  dev setup's, so nothing was written to its files - the orchestrator's staged-rip check covers apply ->
  Next album), the real :8081 setup, an iPad on its side, and VoiceOver.
- **After review** (thirteen findings, each confirmed by skeptics, all fixed in this same version):
  - **The ending's scan is asked only once the album left has been noted reviewed** (major). `review()`
    returns the note's promise (settling, never rejecting) and `end(reviewLeaving, marked)` chains the
    reload onto it - go()'s own ending (an album gone when stepped to) hands its note in as `marked`.
    Fired side by side, the GET could read `album_reviews()` before the POST's write landed (2 stale
    scans in 20 through ASGITransport): the album kept its New chip, and the page's stale count beat
    the server's right one (`page ?? server`) until the page's library was read again.
  - **The list is worked out again only once no read is still out**: `Ending` is `{rows, chips, facet,
    read}`; the ending's read answering sets `read`, and an effect clears it only when
    `!library.loading`. A write's announceAlbumsFiled has the page's own useLibrary scan again a
    second later; closing inside that second, the ending's read could resolve SUPERSEDED (its albums
    never written), and the list was rebuilt from the scan from before the session - the fixed album
    back with its old chips until the next read landed.
  - **Held rows are seen to refuse a tap**: aria-disabled while `ending` (faded to `--app-job-busy`, a
    progress cursor, no hover - `.app-queue-row[aria-disabled='true']`), the click refused as before;
    they looked live and a click silently did nothing for as long as the scan took.
  - **The chips hold still for the whole session and while its rows are held** (`heldChips`, taken as
    the session begins, through `heldNow` since end() is reached from the panel's callbacks; the pressed
    chip is the session's, then the ending's, facet). A write rescanning the page's library had the
    session's own chip vanish (its count 0), later chips shift left under the pointer and All change.
  - **`rowChanged` takes the current row first** when it holds the path: after a disc folder merged
    into another row's folder two rows share one, and a delete from the second's panel marked the first
    Deleted - then Next noted the deleted folder reviewed.
  - **Focus never falls to the page**: a step through the queue (skip, ◁, Next album, Next album after
    a delete) sets the panel's `focusNext` to the Release tab in the reset effect when focus was in the
    panel or nowhere, so the editor going with the album hands it on; a Try again is aria-disabled
    while a read is out (never `disabled`), and one that worked hands focus to the page's body
    (`tabIndex -1`, no ring); a row the ended session was on that leaves the list (fixed, ignored,
    renamed) hands focus to the row now at its place, or the last, or the body - each only when focus
    fell to the page (`focusLost`).
  - **No flash of "The library's scan doesn't list <folder> yet."** on every step: a folder request is
    "asked" at once, so for a render the folder was known and not yet held. `editStatus` takes
    `listed` (the scan in hand lists the one folder) and says "Finding the album's folder…" then.
  - **Tests**: needslook.sim now runs the REAL useQueueSummary.ts against a faked deadwax (one request
    out, exactly one more after it, a failure keeping the last number - null when there was none -
    the page's count over the server's and back, filings asking again, the listener added once), and
    checks the race (no scan until the note is written, go()'s ending too), the held rows' refusal,
    a superseded ending read, the chips held, a facet not reset on a SAVED scan, `disc_label` before
    the edition, a failed cover's plain tile, Try again aria-disabled and refused, and the merged disc
    folders; app-rules pins the focus rules, the step's focusNext, `listed`, an ignore's and an
    un-ignore's `toFolder`, `written`'s dispatch to `wroteFolder`, its three callers and the Next album
    button after a delete (none of which any sim held: mutating each passed everything); routes.sim
    `editStatus`'s `listed`; test_app_desktop_css the held row and the body's focus. 29 mutations, one
    or more per fix, each caught and restored byte for byte (one, the ended row's focus call, first got
    past and gained its pin). troubleshooting.md says "only the new albums are counted" holds for a
    new database, a moved `LIBRARY_PATH` and a library whose last read found no albums - not only
    "until the library has been read once since this database began".
  - **Totals after review**: 2350 Python tests (2348 passed, 2 skipped; one new in
    `test_app_desktop_css.py`), pyflakes, tsc, the bundle, all 43 sims (`needslook` 100, `routes` 238,
    `app-rules` 250).
- **After a second review** (three findings, each fixed with a check that fails without it):
  - **A facet emptied while the page was hidden left a stale address.** Leaving the queue page closes
    the panel, the session's ending read lands under the other tab, and the fall-back-to-All effect
    called `onFacet(null)` - which `router.update` applies to the top of the tab SHOWING, so nothing
    changed, and the effect never ran again: the address kept `?facet=X` under All, and the page went
    back to X by itself when such an album turned up. The effect now needs `shown` (and has it in its
    deps), so the address is told as the page shows again.
  - **A folder request now supersedes an album-page lookup still out** (`lookups.supersede()` and
    `setAnswer(null)` in `lookUp`'s folder branch): the panel stays mounted, so a slow search3 from an
    earlier Edit used to land on the folder request, set `askedFor` to the old key and leave the panel on
    "Finding the album's folder…" with no Look again.
  - **The page's count cleared as it goes with no session** is pinned now (it was true but untested:
    only the unmount WITH a session was checked, where the count was null already).
  - 6 mutations (the `shown` guard, `shown` in the deps, the unmount clear, the supersede and the
    cleared answer, each alone and together), all caught, each file restored byte for byte.
    `needslook` 104 checks, `app-rules` 250.

### Server settings and the log in the app (2.0.0-player.33)

The second Managing slice (the plan's section 10), built like "Needs a look". No board draws either
screen; the desktop sidebar's Managing only names "Settings" and "Log". The spec is the session
scratchpad's `uplan/slice-settings-log.md`; it named the slice .27, and it is .33 because player-spike
took .26 to .32 (the launch audit and the turntable's sound) while it was built, to be rebased onto them. The main page's settings tab and log are unchanged: its
settings tab renders the same tree as before (checked once, by rendering the old and the new
SettingsView with function components drawn through, on all three server pages, untouched and with
drafts: identical), and init.js ignores the new fields on an event.

- **Where they are**: the desktop sidebar's Managing, after "Needs a look", **Settings** and **Log**
  (`SIDEBAR_SETTINGS`, `SIDEBAR_LOG`; `SidebarId` 'settings' | 'log'; current while their page is on
  top, `sidebarCurrent`'s `page`), an admin's, then "Open the main page" (its title now names only the
  bulk runs, artist images and re-filing). You's Managing, desktop only: **Server settings** and
  **Log** rows under "Albums that need a look" (`onManaging`), and the desktop footnote names only the
  bulk runs, artist images and re-filing. No unread badge on Log: it would need the stream held open.
- **The routes** (`lib/appRoutes.ts`): `PageKind` 'settings' and 'log', `#/you/settings/server` and
  `#/you/log/all` - one page each (`SETTINGS_ID`, `LOG_ID`, `ONE_PAGE`: any id in an address is it,
  made canonical, nothing more kept), back "You" (`SETTINGS_PAGE` and `LOG_PAGE` labelled "Server
  settings" and "Log" for a page above them). **The three Managing pages are siblings**
  (`openManagingPage` in App, which openQueue now goes through too): one opened while another is on
  top of You REPLACES it (`router.become`), never pushed over it, so Settings -> Log -> Settings never
  piles up and back from any of them says "You"; nothing when it is already on top. The queue page
  follows the same rule now (before, it had no siblings and was always pushed over what was on top),
  pinned in app-rules and driven in routes.sim.
- **The settings page: `app/ServerSettings.tsx`**, the SERVER half of the settings tab drawn from
  SettingsView's own parts, exported for it with no change to the tab's DOM: `ServerGroup` (a group's
  rows, `children` after them - the tab passes Re-time lyrics there), `SettingRow`, `Section`,
  `OrganizingVerdict`, `OrganizeModes` and `editedEnvDraft` (the draft rule: a value set back to the
  saved one is no change, except a secret's - any typing is a change). Its tabs are the tab's three
  server tabs (`lib/serverSettings.ts` `SERVER_TABS`: Library first, then Downloads, Connections - the
  main page lists them Downloads, Library, Connections after its Search tab; `tabForGroup` places each
  group, an unknown one under Library) as the Edit panel's underline tabs, marked by `tabMarks`
  (attention, else unsaved), the arrow keys moving round (and focus with them). Every edit is a draft
  until **Save changes**, kept across tabs; ONE save bar, always in the page (its WORDS the
  `role="status"` region, never Discard and Save - around them too, a screen reader read their names
  with every change), at the foot of the page area above the player bar, says nothing until there is
  something; the batch is the
  server's all-or-nothing PUT, a refusal said there ("Not saved: …", kept until the next save or
  Discard, as the main page keeps it) with every draft still drawn. Save is the page's one solid purple
  button. **The rows stay editable while a save is on its way** (the server stats every path it is
  sent - a moment on a NAS): an edit made then stays a draft (`draftsAfterSave`: only what was sent,
  still as sent, goes - a key typed again since, or one the save never carried, stays), and the bar
  says "N unsaved changes", never "Saved."; until the review a save cleared every draft and so wiped
  that edit unsent. A successful save also clears a failed re-read's "Couldn't read the settings again"
  line (the settings were just answered). **Focus is never dropped to the page**: Save and Discard are
  drawn only with a draft, so the save or discard that takes the last one takes them away with focus
  on one; a layout effect then gives focus to what the bar says (`tabIndex -1`, no ring) - only when it
  fell to the body. NOT here: the main page's browser preferences and Re-time lyrics - one line says
  so, the main page linked beside the app. Read (`getServerSettings`, which now takes a `signal`) the
  first time the page shows and again each time it comes back into view **with no draft**
  (`kept.drafts`), through latestOnly; a save calls any read still out off, so an older answer never
  lands over the save's. Never at start-up. **What the page holds outlives it** (`kept`, a module
  store with listeners, as useGetSettings is): App draws only a tab's top page, so the sidebar's Log or
  Needs a look (which replace it), Back or Go to album unmount it - and the drafts the bar had counted
  went with it, without a word, until the review. The settings as answered, the drafts, the refusal,
  the tab and a save on its way are kept there until Save or Discard (or a reload): coming back with a
  draft reads nothing over it, and a save left mid-way lands there all the same. Two copies drawn (an
  address can put the page on another tab) are one page. `forgetServerSettingsPage()` is the sims'.
- **The log page: `app/EventLog.tsx`** (pure rules `lib/eventLog.ts`): text lines, newest first, each
  with the server's time (`lineTime`, HH:MM:SS, monospace), its level (`levelOf`: errors red, warnings
  amber) and where it came from (`src`, always drawn so the words keep one column) - **all text**, never
  HTML (the log quotes strangers' titles and paths; the v0.9.21 rule). At most `LOG_KEPT` (500) kept.
  **Clear** empties the view and keeps the number, so nothing cleared comes back, and the empty view
  then says "Cleared. New lines show here as deadwax logs them." (`EMPTY_WORDS`), never "Nothing logged
  yet." - which is for a history that really was empty. Where the stream stands - Connecting…, Live,
  "The stream was lost - trying again" - is ONE line above the list (`STREAM_WORDS`), never a column of
  failures. **"Trying again" is kept true**: EventSource tries again by itself only after a NETWORK
  error; an answer that isn't the stream (a reverse proxy's 502 while deadwax restarts) ends it for good
  (readyState CLOSED), and the page then asks again itself after `STREAM_RETRY_MS` (5 s) - the history
  first, then the stream from where it ends - once per failure, the timer called off as the page stops
  showing. Without a proxy (James's setup) a restart refuses the connection, a network error, and
  EventSource recovers on its own. **A history that couldn't be read is filled in by the next**: the
  stream then opens from now, and the run's first line heard leaves a `gap` below it (LogState) - the
  lines deadwax kept from before it, which the page never had; the next history read puts them under
  the run's own lines and above any older run's (`fillGap`). Without it those lines, all at or below the
  newest number, were dropped as "had" for good. Clear drops a gap with the view. **The lines outlive
  the page** as the settings' drafts do (`kept`, the module's `LogState`; `forgetEventLogPage()` for
  the sims): left for a sibling or by Back and come back to, the history is joined by number to what
  was on screen - nothing twice, a gap filled, and nothing cleared back again (it was, every time, until
  the review, which made troubleshooting's "the lines cleared don't come back when you return" untrue).
- **The history** (`src/logger.py`): the last `LOG_HISTORY` (500) page-bound records - exactly what
  SSEHandler forwards (`frontend: True`), nothing else - each with `seq` (rising by one per line,
  across threads), `time` (the record's) and `boot` (`LOG_BOOT`, this run's name: numbers start again at
  1 when deadwax restarts). `emit` now runs whether or not a stream is open, and numbers, keeps and hands
  the line to the streams under one `threading.Lock`, so the streams get lines in the order they were
  numbered. **`GET /deadwax/interface_logs/recent`** -> `{lines, last, boot}` (oldest first; gzipped
  like any text route; a GET, so the same-origin guard passes it). **The stream takes `after` and
  `boot`**: `register_sse_client(after, boot)` returns the queue, the kept lines after `after` (all of
  them for another run's `boot`), and the number at or below which it has every line - taken together
  with adding the queue, nothing awaited between, so a line logged on another thread between the page's
  read and its stream is in one or the other, and the stream sends each number once (a publish at or
  below what the replay sent is skipped - the queue is handed each line once, in the order numbered, so
  that floor never needs moving). The queue now holds `(seq, json)`. `after` is 0 or more and `boot` at
  most 64 characters (deadwax's are 12), a 422 otherwise. **The spec said "fetch
  recent, open the stream, drop anything at or below `last`"**; that order alone has a gap (a line
  logged between the read and the stream's opening is in neither), which `after` closes. Without
  `after` (the main page) the stream is exactly as before: only what is logged from now, the first-chunk
  comment first. EventSource reconnecting by itself asks from the same `after`; the page drops what it
  has by number (`joinLine`).
- **The stream is held only while the page is what shows**: EventLog's effect on `[desktop, live]`
  opens nothing unless both, reads /recent first, then `new EventSource(logStreamUrl(last, boot))`, and
  closes it in its cleanup; App's `live` is `managingLive(tab)` - `pageShown && nav.tab === tab &&
  !visualizerShown` - and both pages get `desktop && admin` (a non-admin, impossible with logins off,
  would see the phone's note). A held connection is one of the six a browser allows the host over plain
  http/1.1, and the player's audio uses them. `visualizerShown` moved above the pages memo, which is
  keyed on it now.
- **Phone**: both addresses show the app's card ("Changing deadwax's settings needs a wider screen for
  now - or the main page.", "The log needs a wider screen for now - or the main page.") and ask nothing;
  no existing phone screen's DOM changed (You's new rows and the sidebar items are desktop-only, the
  phone footnote word for word as it was).
- **Style** (app-desktop.css, its own section at the end; tokens `--app-desk-set-*`, `--app-desk-log-*`):
  the settings tab's own classes styled by name under `.app-desk .app-settings` (no main.css on this
  page) - groups as cards, the key monospace, where a value came from a chip, an edited row amber at its
  edge, errors in the failure text, fields STYLE.md's well; long keys, notes, paths and the verdict broken
  anywhere; the settings page at least the page area's height (`--app-desk-set-page`, the window less
  the player bar; the body growing into it), so the save bar - `position: sticky; bottom:
  var(--app-desk-bar)`, `--app-desk-set-bar` tall, taller on a coarse pointer - is at the foot of the
  window on a short tab too, where sticky alone left it under the last group mid-screen; idle it takes
  no clicks (`pointer-events: none` without `is-said`: an invisible box over what a long tab scrolls
  under it swallowed presses on fields there), and while it says something `html:has(.app-desk
  .app-pane:not([hidden]) .app-settings-savebar.is-said)` adds its height to the scroll padding, so
  keyboard focus stops above it - only from the pane that SHOWS: the page stays drawn in You's hidden
  pane while another tab shows (holding "Saved." or a draft), and `:has()` matches what is hidden, so
  every other tab's focus stopped 55px higher than its player bar needed until the review
  (`test_nothing_reaches_the_phone` takes `html:has(.app-desk ...)`, which only a desktop can match);
  the log a grid of time, level, source and words at the data size, words broken anywhere;
  both pages kept clear of a drawer as the queue page is; a coarse pointer gets 17px fields and 44px
  controls.
- **Not built, on purpose**: the browser preferences and Re-time lyrics in the app, the bulk runs,
  artist images, re-filing, a phone editor or phone settings, an unread count on the Log, retiring
  anything on the main page.
- **Verified**: 2366 Python tests (2364 passed, 2 skipped; `test_log_history.py` 12 new, four in
  `test_app_desktop_css.py`; `test_log_stream.py`'s one call to `register_sse_client` reads its new
  return), pyflakes, tsc, the bundle, all 44 sims (`settingslog` new; `routes`, `app-rules` and `you`
  extended, `app-rules`' memo and `covered` checks moved to the new spelling, never weakened). 37
  mutations, one per rule pinned (seven on the server, 26 on the pages, the routes, App, the sidebar
  and You, three on the CSS, one on the draft rule), each restored byte for byte (checked by hash): all
  caught - one, the log page's `closed` check after the history answers, only by app-rules' text pin
  (it is a second guard: the cleanup's supersede already makes the answer stale); one, `tabMarks`
  handed the drafts, only after the sim gained a check on a tab with no attention mark of its own. The
  engine guard is empty.
- **Checked in a real page** (headless Chromium, real mouse input, this worktree's own instance on
  :8095 with a scratch database and an empty library - never the dev setup's :8081; 46 checks): the
  sidebar's Managing order; nothing read and no stream at start-up; Settings at `#/you/settings/server`,
  its item current, back "You", three tabs, no preference or Re-time; a path holding markup typed on
  Library and an address on Connections - the retype note, "2 unsaved changes", the bar above the player
  bar; Save refused (the password not retyped) with both drafts kept; the address set back and saved,
  the override stored and the row in error, Library marked; Log replacing Settings (back still "You"),
  Live, the line logged before it opened there from the history, drawn as text (no image made, nothing
  ran), a warning amber, one stream from `after=…&boot=…`, a line logged while it shows arriving once,
  the stream closed on leaving, the lines logged while away joined on coming back with none twice, Clear
  emptying the view with no request; at 1440, 1280 and 1024, with Info open beside, no sideways scroll
  and the page clear of the panel; the music playing through it all on one audio element; on a phone
  both notes with nothing asked, and no new You row; no console errors and no dialog.
- **After review** (fourteen findings confirmed, two of them the same - all fixed, each with a check that
  fails without it where it can be tested): an edit made while a save was on its way wiped unsent under
  "Saved." (`draftsAfterSave`); "The stream was lost - trying again" said for good once the browser had
  given up on the stream (CLOSED, behind a proxy answering 502) - the page now asks again itself; a
  history that failed once losing the lines kept from before the first line heard, for good (the `gap`);
  a failed re-read's line left beside the settings a save had just answered; the idle save bar, a
  transparent box, swallowing presses on the fields a long tab scrolled under it, and hiding a field
  focused under it once it said something (`pointer-events`, the scroll padding); focus dropped to the
  page as Save or Discard went; "Nothing logged yet." after Clear; the bar mid-screen on a short tab
  (the page's min-height); Discard clearing a refusal, the arrow keys' direction and the stream's query
  bounds pinned by nothing (now they are); `SERVER_TABS`' comment and the sim's label claiming the main
  page's tab order (it lists Downloads first); You.tsx's docstring saying all of Managing is the main
  page's (a phone's case only now); and the stream's `sent = seq`, redundant (the queue is handed lines
  in order) and dropped. A claimed duplicate `font-size` in the CSS was checked and isn't there.
  **Totals after review**: 2369 Python tests (2367 passed, 2 skipped; two more in `test_log_history.py`,
  the bounds asked straight through the app so an endless stream can't hang them, and one in
  `test_app_desktop_css.py`), pyflakes, tsc, the bundle, all 44 sims (`settingslog` 114 checks, 40 of
  them the review's; `app-rules` 262). 35 mutations, one or more per fix, each restored byte for byte
  (checked by hash): all caught. The engine guard is empty. **Checked in a real page** (headless
  Chromium, this worktree's own instance on :8096, a scratch database and an empty library; 31 checks):
  at 1440x900, 1280x800 and 1024x768 the save bar's foot on the player bar's top on the short Downloads
  tab (no scroll added: at 1024 its own content is taller than the window) and the long Library; a real
  click on a field scrolled under the idle bar landing in the field; with a draft the page's bottom
  scroll padding 127px (72 + 54 + the hairline) and Tab to a control under the bar scrolling it clear -
  and, the rule overridden to the player bar's 72px, the same Tab leaving it under the bar (the control);
  Save and Discard by the keyboard leaving focus on the bar's words, no ring; Clear saying "Cleared…";
  a reload whose history read was answered 502 live from then, its earlier lines filled in on coming
  back, none twice; the stream answered 502 (the browser's EventSource CLOSED) saying "trying again",
  asked again three times in 12 s rather than in a loop, Live once answered, and nothing asked after
  leaving. A coarse pointer (touch emulation, 1180x820): the bottom padding 165px (100 + 64 + the
  hairline), exactly the 100px player bar and the 65px save bar on it, fields 17px.
- **NOT verified**: an iPad on its side (17px fields, 44px targets), VoiceOver (the save bar's and the
  stream line's live regions), Safari's EventSource reconnecting, a real restart of deadwax under an open
  Log page (the `boot` parameter is pinned in the Python tests and, since the second review, in the sims
  through the REAL api/logs.ts), and the real :8081 setup.
- **After a second review** (eight findings confirmed, two pairs the same - six fixes, each testable one
  with a check that fails without it): the drafts dropped without a word when the page was left (above:
  the module store, and the log's lines with it - each page now drawn again by the module's listeners,
  so the sims also hold that a change tells every copy drawn and a copy gone nothing: a line from the
  stream is what tells the log page to draw its new line); the save bar's scroll padding on every tab (above); the
  version, set to .27 as the spec said when player-spike had already taken .27 (then .30, taken too
  while this was fixed - now .33); the sim
  carrying its own copy of api/logs.ts, so the stream's address could lose `boot` with every suite
  passing - which would break the one thing `boot` exists for, a deadwax restart without a proxy
  (EventSource reconnecting with `after=N` and no run: nothing replayed, the new run's first N lines
  skipped) - it now runs the real file, deadwax faked at `fetch` one layer down, and asks for the
  addresses themselves (`after=0` sent, a run's name encoded, a number with no run from now); the save
  bar's live region round its buttons (above); and "Needs a look"'s section, whose sidebar title and
  "Not built" list still named the server settings and the log (both now say where they were built).
  **Totals after the second review**: 2369 Python tests (2367 passed, 2 skipped; none new - the CSS
  test's selector check was tightened in place), pyflakes, tsc, the bundle, all 44 sims (`settingslog`
  140 checks, 26 of them the second review's; `app-rules` 263). 14 mutations, one or more per testable
  fix (the drafts and the lines dying with their page, a page or a gone copy told nothing, a read over
  kept drafts, the padding from any pane, the stream's address losing `boot`, `after=0` or the
  encoding, or keeping `after` with no run, the history's path, the live region on the bar), each
  restored byte for byte (checked by hash): all caught - three (the drafts' and the lines' listeners,
  a gone log page's) only once the sim could see a page told to draw again (`redraws`, its first hook).
  **Checked in a real page** (headless Chromium, real clicks and typed text, this worktree's own
  instance on :8097 with a scratch database and an empty library; 30 checks): two drafts on two tabs
  kept through the sidebar's Log, Needs a look, the sidebar's You and Back - the page gone each time,
  nothing read over them, the tab left on and its mark; a refused save's words kept through Log and
  back; the bottom scroll padding 127px on Settings with a draft and 72px on Home and the Library with
  the page still drawn in You's hidden pane, its bar saying something (a draft, and "Saved."); the
  accessibility tree's status region the bar's count alone, no button in it; a line logged while the
  Log shows drawn with nothing else done; the lines on screen drawn at once on coming back, the line
  logged while away joined, every kept line once and in order, one new stream from where the history
  ended; Cleared kept through leaving; no console error, no dialog.
  After the rebase onto 2.0.0-player.32 the merged tree is 2373 Python tests (the four of "Loading,
  audited" joining) and `app-rules` 269 checks, every sim passing and the engine guard empty.
