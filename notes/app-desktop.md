# The app on a desktop: the frame, editing, Needs a look, settings and the log - and on a phone since 2.0.0-player.47

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
  for the look's tokens: titles 28/30px, the album's artist 18px, cards #1e1c26 on #0b0a10, the
  pressing list a desktop list - and the type scale, which since 2.0.9 is the frame's whole scale:
  body 14px, headings, meta and data 13px, labels 12px, the brand 20px (until 2.0.9 labels were 11px,
  data 12px and body 17px). **Text fields read `--dw-text-field` (17px), which is NEVER redefined**:
  an iPad on its side is a desktop where iOS zooms into a field under 16px, so a field reading
  `--dw-text-body` would now be 14px - the sidebar's field takes the board's 13px only for a fine
  pointer. See "Fonts and type (2.0.9)" in notes/interface.md.
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
  desktop frame first shows for an admin and as the app comes back from hidden (since 2.0.0-player.47
  `[asksQueueSummary, admin, pageShown]`, the flag `desktop || nav.tab === 'you'`: true on a desktop all
  along, so the same asks there, and a phone's as You shows); by `albumChanged` on
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

### Looking after the library (2.0.0-player.42)

James (2026-10-14): "Finish the web app". The parity audit (`uplan/parity-audit.json`, its "library"
and "manage" areas) found the main page's library care missing from the app: Rescan, the bulk runs,
re-timing lyrics, the queue's warning that ignores can't be saved, and the Edit panel's one way on for
an album it can't find a folder for being a link to the main page. Desktop only (1024px and up); the
phone is decided separately. The spec is `uplan/slice-library-care.md`. There is no board; it is the
Managing pages' parts and STYLE.md. Built beside 2.0.0-player.41 (Get parity) and landing after it.

- **Where it is**: the sidebar's Managing gains **Library care** straight after Needs a look
  (`SIDEBAR_CARE`, `SidebarId` 'care', current while its page is on top), and You's Managing a desktop
  row of the same name under "Albums that need a look" - both an admin's, as the others. The route is
  `#/you/care/library` (`PageKind` 'care', `CARE_ID`, `CARE_PAGE` labelled "Library care", one page:
  `ONE_PAGE`), a sibling of Needs a look, Settings and Log (`MANAGING_KINDS`, `openManagingPage`:
  one replaces another, never piles up). `ManagingKind` ('care' | 'settings' | 'log') names what
  `openManaging` and You's `onManaging` take. The main page's link (sidebar title, You's footnote) now
  names only artist images and re-filing.
- **The page: `app/LibraryCare.tsx`**, its words `lib/libraryCare.ts` (pure), its runs
  `app/useLibraryCare.ts`. The library through the main page's own `useLibrary(desktop && live)` -
  the saved scan at once, a real one underneath - read only once it shows (App's `managingLive`), read
  again quietly as it shows again with nothing under way. Two cards:
  - **Rescan**: `reload(true)` (POST /library/rescan), refused (aria-disabled) while ours is out or a
    plain read over a real scan is - and offered while the saved scan is on screen with the first real
    one under way, as the main page offers it (`disabled={loading && !stale}`; useLibrary draws only the
    newest answer, so the rescan wins); once it answers the library's listeners are told
    (`announceAlbumsFiled` - the count, the owned marks, the Edit panel's and Needs a look's scans: a
    retag elsewhere moves all of them). Under it what the scan holds and how old it is, as the main
    page's status bar says them (`scanTotals`: albums grouped as the main page groups them, tracks,
    size; `scanAge`: "Saved scan from…" with "· checking for changes" while the real scan runs,
    "Scanned 3 min ago in 2s", "Rescanning - reading every file again…" while ours is out - a plain
    scan under way is never called a rescan), a status region; and `RESCAN_WORDS`, what it is for.
  - **The bulk runs**: Covers, CD art, Lyrics - each a row with its heading, its button
    (`BULK_LABELS` · N, the main page's words), what it will act on before it starts (`planWords`:
    how many album FOLDERS - as `scopeLine` counts them, beside the scan line's grouped albums - which,
    where - "in the whole library" or "among the folders matching “x”" - and what it writes, CD art by
    the names `disc_art_filename` gives), and what the last run did (`bulkSummary`, a status region,
    empty until a run ends - and drawn even then, taking no room: the row's gap given back by a
    negative margin, as `app-rg-store` does, since VoiceOver reads only a region already there).
    **Narrow to** (`narrowAlbums`: every word typed somewhere in the folder's artist, album,
    edition or path, accents and case aside - `lib/typedMatch.ts`) decides what the runs act on,
    `scopeLine` saying so; the main page narrows by its tree's filter and facets, which the app has no
    tree for, so typed words it is. **Offered only from a REAL scan** (`loaded && !stale`): the saved
    one can be behind what is on disk ("Checking the library…" meanwhile) - stricter than the main
    page, which offers them over the saved scan.
- **The targets are `lib/bulkTargets.ts`'s, on BOTH pages**: `coverTargets` (a release, no cover),
  `discTargets` (a release, none of deadwax's own `disc*` - a download's `cd.jpg` doesn't count),
  `lyricsTargets` (no lyrics at all); LibraryView.tsx now takes them (its only diff besides the import),
  and care.sim holds them to the main page's inline rules as they stood, over 108 combinations - same
  albums, same order. The main page's loops and status bar are untouched.
- **A run** (`runBulk`): one album at a time - the next only once the last has answered, a plain
  `for` with an `await` - through the route a single click uses (`fetchCoverArt`, `fetchDiscArt`,
  `fetchLyrics`), never a loop of its own on the server (notes/decisions.md); Stop asked before each
  album, landing after the one being fetched ("Stopping after 3 of 12", aria-disabled); what each came
  to counted apart (`addOutcome`): a 404 none to find, anything else failed; lyrics in TRACKS (saved,
  not on LRCLIB or instrumental, failed - a lookup that failed outright counts its album's tracks,
  `failedAs`), as the main page counts. `bulkSummary` is the main page's status bar's template, word
  for word (held to it in care.sim). Each kind runs on its own, as on the main page.
- **The runs outlive the page** (`app/useLibraryCare.ts`, a module store with listeners, as the
  server settings' drafts and the log's lines are): App draws only a tab's top page, so the sidebar's
  Log or Settings, Back, Go to album would unmount it, and a run over a whole library takes minutes.
  Kept there, a run goes on while you look at the Log, its Stop still works when you come back, and
  each run's result stays until the next of its kind (and the narrowing with them) - until a reload.
  One of a kind at a time (asked again while running, nothing); each kind through a latestOnly() of its
  own, so nothing of an older run (`forgetLibraryCare`, the sims') is drawn over a newer; the library
  told once at a run's END, only when something was written (the main page reloads once at its end).
  **A run that wrote leaves its kind `behind`** (set in the same telling as its end): the scan the page
  holds still lists what it just did as missing, so the page reads the library again at once (as the
  main page does after a run) and holds that kind's button back ("Checking the library…") until a read
  begun after the run ended has landed - its own read answered and no newer one out (useLibrary draws
  only the newest), `caughtUp` - never drawing it again over the albums it just did. A page drawn fresh
  begins every read after any run that ended while it was away, so it clears `behind` as it mounts. A
  catch-up read that fails lets go too (the page says the read failed, with Try again). A run's button
  that goes as the run ends hands focus to the run's words (`tabIndex -1`, no ring) - only when focus
  was on that button and fell to the page. Focus moving on is asked a microtask after the blur: Chromium
  blurs a focused button AS it removes it, while it is still connected, and that is the button going
  (handed on by the layout effect in the same commit), not focus moving on.
- **Clear MusicBrainz's saved answers in the app** (2.0.0-player.54): `components/MusicBrainzAnswers.tsx`,
  drawn as `ServerGroup`'s child for the `musicbrainz-cache` group on both pages (Connections), keyed on
  the group's saved values so a save draws it afresh, refused while `MUSICBRAINZ_CACHE_PATH` is a draft.
  Told `live` by the app's page and read again each time it comes back into view (the review: the page
  stays drawn while another tab shows, so the line went on saying "Nothing saved yet." after a search),
  but never over a Clear on its way. Refused with `aria-disabled`, never `disabled` - it refuses itself
  on its own press, and a focused button made disabled dropped the focus to the page, against this
  page's own rule for Save and Discard. Its row is styled by the Re-time row's rules, extended to
  `.settings-answers`, the refused look on `[aria-disabled='true']`. The whole change: "MusicBrainz
  answers kept on disk (2.0.0-player.54)" in notes/backend-gotchas.md.
- **Re-time saved lyrics in the app**: `components/RetimeLyrics.tsx` is the settings tab's own
  component moved out of SettingsView.tsx so both draw it (`ServerGroup`'s children for the `lyrics`
  group on both pages), refused (`disabled`, "Save the new lead first.") while `LYRICS_LEAD_MS` has a
  draft - a revert of it too - and reading a REAL scan (`listAlbums`, never the snapshot: notes/library.md
  "The lead"). **Its run moved into the module** too, with a latestOnly(): the app's settings page goes
  whenever another page takes its place, and the main page's settings tab draws nothing while another
  tab shows - there a run went on invisibly with no Stop, and a second could be started beside it;
  now it is drawn again, Stop and all. Its DOM on the main page is unchanged in every state. **How a
  run ended is said once**: one that ended is let go as the last thing drawing it goes (and one that
  ended while nothing drew it is said on coming back, then let go the same way), and as soon as a new
  lead is typed - its words were at the old lead. A lead typed WHILE it runs lets it go as it ends
  (`leadMoved`, cleared as a run starts), saved by then or not: the server reads `LYRICS_LEAD_MS` on each
  album's request (routes/library.py, `Config.lyrics_lead_ms()`), so a save mid-run left the albums
  before it at the old lead, and "re-timed 5 tracks." under the new one said the job was done (second
  review; the old component had the same gap). A change on the main page, on purpose: there, as the
  component's state, an ended run's words went with a tab switch but stayed through a new lead saved on
  the same visit ("re-timed 29 tracks." under a lead it wasn't timed to); kept in the module without
  letting go, they outlived every visit (review). The app's
  settings line no longer sends re-timing to the main page, nor does the Edit panel's Lyrics tab ("in
  Managing's Settings, under Library").
- **Needs a look warns when ignores can't be saved** (`IGNORES_UNSAVED`, `ignoresUnsaved`): the
  library's answer saying review tracking is off (`review_tracking_enabled`, once a read has landed -
  useLibrary's default says nothing) or the count's route (`tracking_enabled` - useQueueSummary.ts now
  keeps it, `queueTrackingNow`/`useQueueTracking`, null until answered). Amber, above the list, as the
  main page's queue warns under its views.
- **Choose the folder** (`app/FolderPicker.tsx`, pure rules `folderChoices`/`folderChoicesWords` in
  lib/albumEdit.ts): where the Edit panel finds NO folder - by release ("has no folder of this album")
  or by name ("can't tell which folder") - `editStatus` says `choose` (was `mainPage`) and the panel
  draws **Choose the folder** beside Look again, in place of "Open the main page" (the panel has no
  link out now). It opens a field (focus into it) over the scan's folders, by path, each with its
  artist and album and "no release" when untagged, narrowed by every word typed (path, artist, album),
  the first `FOLDER_CHOICES_SHOWN` (50) drawn and how many match said in a status. A folder clicked is
  `chosen` for that Edit (keyed on the request, reset with the next): `folders` becomes `folderOnly`
  of it - the subject taken from the scan by path, as a folder request's is - followed through a
  rename by `follow`; the rest of the panel is the album page's (its writes ask the page again and,
  after a release changes, look for the new id - the staged rip's case). Focus goes to the Release tab.
  Offered for the release case too: there the album's tags were often changed by another program
  (Rescan first) or it lives somewhere deadwax can't match - picking it beats leaving.
- **Style** (app-desktop.css, its own section at the end; tokens `--app-desk-care-*`): the page at the
  Managing pages' readable width and clear of a drawer; its two parts cards as the settings groups are;
  runs as rows inside the second card; STYLE.md's secondary buttons at the frame's control height (no
  solid purple on the page); a running one with the player's busy ring (`pl-spin`); the field the well;
  words broken anywhere. Choose the folder's field joins the panel's well rule; Needs a look's warning
  amber on the amber tint; Re-time styled by the tab's own classes under `.app-settings` (a row under
  the lyrics group's rows, aligned with them by a transparent edge; its spinner the busy ring). The Edit
  panel's `.app-edit-link` rules went with the link. Choose the folder's field and every
  `.app-edit-choice` (the "Which one is it?" list's too) draw their focus rings inside
  (`--app-ring-inset`, a class more than the panel's ring rule): the panel's body clips sideways and
  they run to its edges, which cut the ring off. A coarse pointer: the field 17px, Try again 44px.
- **Not built, on purpose**: anything on the phone (the page is a note there); the main page's facets
  as the runs' narrowing (typed words instead); Rescan or the runs anywhere but Library care; the
  main page's loops moved onto `runBulk` (only the targets are shared, as the spec asked - its words
  are pinned equal instead); artist images and re-filing; showing which album a run is on.
- **The cover route tells "none" from "no answer"** (after review): `/library/art/fetch` answered 404
  "has no front cover" for EVERY way no cover came back - `fetch_front` drops `_fetch`'s reason - so a
  run of Get covers during one of the Archive's outages said "N had none on the Archive", on both
  pages, against notes/decisions.md's split. `CoverArtClient.fetch_front_why` keeps the reason - after
  the 1200px fallback (`full`, an original that isn't an image) that request's own (`fetch_front`, which
  retag uses, is unchanged); the route answers 404 only for "missing" (the Archive's
  404, or no release) and 502 otherwise ("couldn't be reached - try again", or "the cover couldn't be
  downloaded … - try again"), as `/disc_art/fetch` already did - counted failed by both pages' runs.
  The single Get cover button and the editor's save treat any failure alike and show the message.
- **Seen, not changed** (pre-existing, outside the slice): deadwax counts a macOS AppleDouble
  `._cover.jpg` as a cover (the scratch library has them beside every track - removing `cover.jpg` left
  the album "with a cover" until `._cover.jpg` went too). Re-time's button says "reading the library"
  until its first album is done (its count starts there), as before.
- **After review** (fourteen findings, merged to eleven fixes; each with a check that fails without it):
  Re-time's ended run said once (let go as the last thing drawing it goes and as a new lead is typed -
  above); a run that wrote holding its kind back until the library is read again (above, `behind`);
  `/library/art/fetch` 502 for an Archive that gave no answer (above); Rescan's rule written as the code
  and the main page have it (a comment and this file said the opposite); the CD art plan naming the
  writer's files; focus moving on asked after Chromium's blur-on-removal; the empty result regions drawn
  (no `display: none`); the picker's rings inside; the plans counting album folders, not albums (a library
  of 7 albums said "8 albums with no lyrics" - `scopeWords` now says "among the folders matching"); the
  store's listeners pinned (care.sim counts each page's redraws - LibraryCare told as a run starts, as each
  album answers, on Stop, at the end and as the narrowing changes, Re-time as its run moves, a page gone
  told nothing; needslook.sim the same for useQueueTracking); the Edit panel's Lyrics note and the
  sidebar's main-page title pinned in app-rules; "Under it" for the facts line here and in
  docs/library.md.
- **After a second review** (three findings, each confirmed by skeptics, all fixed with a check that
  fails without it): Re-time's words let go as a run ends when a new lead was typed while it ran, saved
  by then or not (`leadMoved`, above - care.sim types and saves a lead mid-run and expects the prompt, a
  run after it its own words again, and a read that failed the same; app-rules pins the effect, every
  ending through `ended()` and the flag cleared as a run starts); Library care's two guards against
  reading over a read still out pinned - shown again with a read out asks nothing, nor does either Try
  again while one is (care.sim; the code was right, nothing held it); and the cover client's reason
  after the 1200px fallback pinned - at `COVER_ART_SIZE=full` with an original that isn't an image, the
  1200px copy's own answer is the reason (a 404 "missing" and the route's 404, unreachable a 502), never
  "not an image" (six tests in `test_coverart_client.py`).
- **Verified**: 2420 Python tests (2418 passed, 2 skipped; at the build, 2400 - five new in
  `test_app_desktop_css.py`, one changed, the link it pinned gone - and after review 14 more: 12 in
  `test_coverart_client.py`, the reasons and the route's 404/502 through the real client over a fake
  Archive, and two in `test_app_desktop_css.py`, the drawn live region and the inside rings - and after
  the second review six more in `test_coverart_client.py`, the 1200px fallback's reason), pyflakes,
  tsc, the bundle, all 48 sims (`care` new, 129 checks; `routes` 271, `app-rules` 315, `you` 72,
  `needslook` 121, `settingslog` 146 extended - app-rules' links-out list, Managing order and siblings
  checks moved to the new spelling, none weakened). At the build, 62 mutations, one or more per rule
  pinned, each restored byte for byte (checked by hash): 61 caught at once; the one that got past (the
  store ignoring Stop - the check pressed Stop only on a run's last album, and a sim whose awaited answer
  never comes lets Node exit 0) gained a mid-run Stop check and care.sim a guard that fails it should it
  end early, and is caught; a mutation first caught only by tsc (Re-time reading the snapshot) was redone
  so it is caught at run time. After review, 23 more, one or more per fix, all caught by the suite named
  (the reviewer's five unpinned redraws among them), every file restored byte for byte; after the second
  review 9 more, all caught (the lead's flag not set, not cleared, an ending not through `ended()`, the
  old effect; each Library care guard dropped; the fallback's reason dropped). `sidebarMove`'s
  'care' is pinned by the type system as well as routes.sim. The engine guard is empty.
- **Checked in a real page** (headless Chromium over plain http as `deadwax.test`, real mouse input,
  this change's own instance on :8115 with a scratch database and a COPY of the builder36 library -
  covers removed from two albums, one album retagged in place with its folder's date put back - and a
  second on :8116 with no job store; the live Cover Art Archive and LRCLIB; 45 checks): the sidebar's
  and You's Managing order; Library care at its address, its item current, back "You"; the facts line;
  the three runs' counts and their plans; Rescan finding the in-place retag a plain scan didn't; Get
  covers to its end ("fetched 2 covers", both on disk) and the page's scan read again by itself, the
  button gone (a first run, before the checks were tightened, had the Archive answer 500 for one album:
  "fetched 1 cover, 1 had none on the Archive", and a fresh page then offered "Get covers · 1");
  Get CD art stopped after its first album
  ("Stopping after 1 of 7", then "stopped at 1 of 7"); Get lyrics narrowed to "portishead" (3 albums,
  32 tracks saved, no other album touched); Re-time under Lyrics, refused with 300 typed, run after
  saving ("re-timed 29 tracks."); the runs' words still there after Settings; Choose the folder on the
  retagged album (focus in the field, 8 folders, narrowed to one by "test signal", the editors drawn for
  it, focus on Release; its Lyrics tab pointing at Settings); the warning with no job store, none with
  one; at 1440x900 and 1024x768 no sideways scroll and nothing past the window on the page, Settings,
  the panel (a drawer at 1024) and Needs a look; a phone's note; no console error or dialog.
- **Checked in a real page after review** (the fixer's own instances: :8117 with a scratch database and a
  fresh COPY of the builder36 library - Third's and BULLY's covers and their `._cover.jpg` removed, Test
  Signal retagged in place - and :8118 over a copy of those two albums with the Cover Art Archive
  unreachable, `HTTPS_PROXY` at a closed port; headless Chromium at 1440x900 and 1024x768 as
  `deadwax.test`, 34 checks, 33 passed): the plans in album folders beside "7 albums" in the scan line, CD
  art's file names, the facts under Rescan; the three empty result regions `display: block`, 0px, the row
  ending where its plan does, and five status nodes in the accessibility tree before any run; Get covers
  started from the keyboard (Enter on a focused button) to "fetched 2 covers", both on disk, sampled every
  ~25 ms for 4 s after: "Get covers · 2" never again, "Checking the library…" seen, then no button, and
  focus on the run's words - Chromium's blur as the button went no longer dropping it to the page; a
  lyrics run narrowed to "third" (11 tracks) not offered again; Re-time run on the app's Settings and on
  the main page's, then the Log or the Library tab and back: the prompt both times; Choose the folder's
  field and a folder reached by Tab with `outline-offset: -2px`, the ring whole (the field runs to the
  body's edge, the folder to both), at 1440 and in the 1024 drawer; :8118's route answering 502 "couldn't
  be reached - try again" and its run "fetched 0 covers, 2 failed - try those again", offered again at
  once, its words kept across the Log and back at 1024; no sideways scroll; no console error. (A check
  that a run's words outlive a full navigation to the main page and back failed, as designed: a reload
  forgets them.)
- **NOT verified**: an iPad on its side (17px field, 44px targets), VoiceOver (the facts', a run's and
  the picker's status regions), a library of thousands (the picker draws 50; the runs' counts work over
  the whole scan each render), a run left going while the app is backgrounded on a phone-sized iPad,
  the real :8081 setup, and the merge with 2.0.0-player.41.

### Inside a track (2.0.0-player.44)

James (2026-10-14), finishing the web app: the parity audit (`uplan/parity-audit.json`, its "library" area
and the critic's gap list, section 4 - "Looking inside a track") found the main page's track viewer missing
from the app: a track's fields, "All tags in this file", "Pictures in this file", its lyrics, Previous and
Next, and the cover viewer. James chose **a per-track inspector in the Edit panel's Tags tab** over the main
page's wide table: the column table and its drag and resize go with the main page. The spec is
`uplan/slice-track-inspector.md`. Built beside the artist page (2.0.0-player.45, which landed after it), from .42.

- **The inspector: `app/TrackInspector.tsx`**, its words `lib/trackInspector.ts` (pure). In the Tags tab a
  track's NAME is a button of its own (`app-edit-track-open`, `data-file`), apart from its tick box (which
  ticks as before); it opens the track's inspector, a view pushed over the list: **Tracks** back to it and
  "2 of 11"; the title (the file's tag once read, else the scan's - "No title tag - this is the file's
  name" for a file with none); where it sits as the main page's track view says it (`trackPlace`:
  "Track 2", "Unnumbered", "disc 2 of 2 · <disc title>", its length and format); **Previous** / **Next** in
  the album's order and **Edit this track…** (the tag editor on that one file). Then **every field the main
  page offers** - `lib/trackFields.ts`'s whole registry, not only the Fields menu's choice (37 fields: 22
  Tags, 7 Audio, 5 MusicBrainz, 3 File) - grouped as the main page groups them (`inspectorGroups`): the
  file's own value where read (it wins), the scan's until then, a dash for a field the file lacks, `…` only
  for a field the scan can't fill while the file is read, and the dimmed disc 1 of a file with no disc tag
  with its reason as the tooltip (`inferred`, the main page's); the data face only for a value. Then
  **Pictures in this file** (each picture's declared type, its pixel size measured as it loads, its bytes
  and format - `pictureFacts`, the main page's `pictureBytes` - a tap opening that picture alone in the
  cover viewer), the **lyrics** (the .lrc, else embedded: synced lines with their times, a blank synced
  line a gap, "synced", where they came from - `lyricsSource` - and the main page's "none" pointing at the
  Lyrics tab), and **All tags in this file (N)**, a disclosure of every raw tag and the file's name. Read
  only: it reaches no writer, and nothing about the tag editor or its rules changed. The details are the
  panel's own `useTrackDetails` (fetched once Tags has been opened, as before); the lyrics are asked as the
  track shows and again when the folder's mtime or the scan's .lrc count moves (`lyricsKey`), through a
  latestOnly() - a step on calls the last track's off, and a late answer draws nothing.
  `api/library.ts` `trackLyrics` gained an optional signal (the main page's call is unchanged).
- **The panel's layer rules** (app/EditPanel.tsx): `inspecting` (`path`, `filename`, `listTop`), shown only
  for a track still in the folder shown (`inspected`), is a layer over the Tags tab as the tag editor is:
  `inner` includes it (useSheet `covered`; the release editor's close passes an 'inner' Escape over), and an
  Escape inside the panel while it is the Tags tab's top layer (`inspectorTop`: open, not covered, the Tags
  tab, no tag editor over it) goes back to the list - Escape out in the page is the page's (`escapeFrom()`).
  One press, one layer: the tag editor (opened from "Edit this track…") closes back to the inspector, the
  inspector to the list, then the panel closes; the cover viewer stops its own Escape on the window first.
  Focus: to **Tracks** as it opens (the name tapped went with the list - `focusNext`), back to the track's
  own name as it closes (by `data-file`, the track it shows THEN - Previous and Next move it), the list
  scrolled where it was (`listTop`, put back by a layout effect - `restoreView`) and then, when Previous
  and Next moved past the rows that were in view, on by the least that shows that name (`revealBy`,
  review); kept on Previous and Next, which are
  `aria-disabled` at the ends, never `disabled` (a focused button made disabled drops focus to the page);
  and to "Edit this track…" as the tag editor it opened closes (`closeTagEditor` tries it before the list's
  button) - the editor opening from its top (`openTagEditor` keeps where the view under it was,
  `editorOver`) and, as it closes, that view put back and the button brought into view by the same effect
  (review, second round). It starts afresh for every Edit and every folder chosen, and follows a rename (`follow`). For a
  screen reader (review) a visually hidden polite, atomic status line, always the inspector's first child,
  says the track and where it is ("Sour Times, 2 of 11", `trackNow`): the inspector isn't redrawn per step,
  so a step (focus staying on Previous or Next) changes its words and is spoken, and Back is described by
  it (`aria-describedby`) as the inspector opens with focus there.
- **The cover viewer: `app/CoverViewer.tsx`** round the main page's `components/ArtViewer.tsx` (unchanged:
  zoom about the cursor, drag, pinch, notes/library.md "Looking at a cover close up"), the only way the app
  reaches it (the release editor's own "Compare full size" aside, inside MetadataEditor). Its own scroll
  lock (`VIEWER_LOCK`, `app-viewer-open`), focus into its ✕ before the paint and back to the opener (taken
  in the tap by `takeOpener`) as it closes, Tab kept inside it. Opened from **an album page's cover, on both
  frames** - the hero cover is now a button carrying `pl-hero-cover` itself, the picture filling it, so it
  sits where the cover sat on a phone, a desktop and in a drawer's grid; the picture is Navidrome's own,
  unresized (`coverFullUrl`, the cover route with no `size`; the page's own sized cover its fallback) - from the Edit
  panel's **Artwork** (the cover, `coverSources(album, 'full')` as the main page opens it; and the CD art,
  now shown as pictures with their names - the main page's Properties thumbnails - each opening alone),
  and from the inspector's pictures. The panel's are drawn inside the panel, so they go with its editors.
  A move through the history while it shows (popstate, hashchange) closes it (review): App keeps each
  tab's top page mounted, only `hidden`, so a Back onto another tab's entry (a tab switch replaces the
  entry under a page, so that history is ordinary) left an album page's viewer open in the hidden pane -
  `app-viewer-open` still on `<html>`, so the page shown couldn't scroll, and ArtViewer's window-capture
  Escape swallowing that page's next Escape (the Edit panel's, say), and the viewer back on returning.
  The app's own moves push or replace the address and fire neither event; its in-app Back does, but the
  viewer's scrim covers it. Chosen over a `shown` prop from App: it closes all three viewers the same way
  and touches no shared file.
- **Properties on the album page, both frames** (`app/AlbumProperties.tsx`, `lib/albumProperties.ts`), at
  the foot under the songs: **Year** ("1994 (this pressing 2014)" when the original year isn't this
  pressing's - the main page's "(this press …)"), **Size**, **Release** (the id, linked to
  musicbrainz.org, opening beside the app; "Not tagged with a MusicBrainz release" only once Navidrome's
  own answer for the album has SAID there is none - its `musicBrainzId` '', or that answer without the
  field, `releaseSaid` in AlbumPage - never from the bridge's null alone, review) and **First seen** (", filed by deadwax" for a download). Placed on the
  album page rather than the Edit panel's header because the spec asked for both frames and the phone has no
  panel yet. They come from the id bridge's answer the page asks already - no new request: since this
  change its `present` rows carry what the main page's details pane says of the folder
  (`src/routes/store_album.py` `_facts`): `size` and `original_year` from the saved scan
  (`library.cached_album`, one folder of the in-memory cache, a copy; `_ensure_cache_loaded` first, so a
  restart answers before anyone opens the library) and `first_seen`/`imported` from its review row
  (`JobStore.album_seen`, those paths only) - nothing read from the disk, other pressings' rows untouched,
  and a failure leaving the rows answered without them. A set kept one folder per disc is one album: sizes
  added (only when every folder said), the earliest first seen, filed by deadwax when any folder was.
- **Style** (app.css, its own section at the end, every value a token; `--app-viewer-*`, `--app-props-*`,
  `--app-inspect-*`, `--app-edit-disc*`, `--app-z-viewer` 35 - over Info and the Edit panel, under the pin
  notice): frame-agnostic, so the inspector fits a 390px panel as well as 470 (the fields a label column of
  112px and a value column that breaks ids, paths and strangers' tags anywhere; the actions wrapping) and the
  viewer and Properties work on a phone (the viewer's frame the screen inside its safe areas, the touch hint
  under a coarse pointer, 44px ✕ and Close; the release link a finger's height by a negative-margin reach -
  since review worked out from the list's own type tokens, `--app-props-link-line` (13px × 1.4) and
  `--app-props-link-reach` ((44 - that) / 2), with `min-height: var(--pl-hit)` because the layout's 64ths
  of a pixel left the sum 0.03px short, and `position: relative` so the row under it - a grid item drawn
  after it - no longer takes the bottom of the reach: at 12px fixed it was 42px, about 35 of it hit).
  Inside the panel on a desktop app-desktop.css's panel rules win where they say more (buttons, words, the
  panel viewer). app-desktop.css's own section: the album page viewer the panel viewer's size (tokens), a
  track's name the table's row height, and the rings of the inspector's controls, the track names and
  (review) Artwork's cover and CD art drawn inside the panel body's clipping edges - a class more than the
  panel's ring rule (app.css draws those two inside as well).
- **Not built, on purpose**: the track table's columns (choosing, dragging, sizing - the main page's, by
  James's decision); the inspector on a phone (it is wherever the Edit panel is; the panel comes to the
  phone in a later slice - the inspector is styled for it already); comparing two pictures side by side
  (a tap opens one; the main page opened all of a file's together); "Find on MusicBrainz", the album's
  issues and the edition pills on the album page (other gaps of the audit, not this slice's).
- **Verified**: 2447 Python tests (2445 passed, 2 skipped; 16 new - 8 in `test_store_lookup.py`: the rows'
  facts, a folder nobody knows, one found by a scan, the saved scan after a restart, a set's folders, a
  failure leaving the rows, `album_seen`, `cached_album`'s copy; 7 in `test_app_css.py`: the viewer over
  everything but the notice, its lock and touch hint, its targets and rings, the album cover's button, the
  inspector at 390px, its targets and rings, Properties' breaking and reach; 1 in `test_app_desktop_css.py`),
  pyflakes, tsc, the bundle, all 49 sims (`inspector` new, 81 checks; `app-rules` 339, extended - two of
  its Edit panel checks moved to the new spelling, the inspector added as a layer, none weakened; the
  links-out list gains `app/AlbumProperties.tsx`). 52 mutations, one or more per rule pinned, every file
  restored byte for byte (checked by hash): 49 caught at once; one got past (the lyrics' `ticket.current()`
  dropped - the sim answered the older track first, which the key check hides) and the sim now answers the
  newer first and the older late, and catches it; one could not apply as written and was re-aimed; one was
  equivalent (facts spread onto the other pressings - only present paths have facts) and was replaced by
  the facts dropped from the present rows, caught. None was caught only by tsc. The engine guard is empty,
  `player.sim.cjs` untouched, and `ui/src/components/` and `ui/src/hooks/` have no diff.
- **Checked in a real page** (headless Chromium over plain http as `deadwax.test`, real mouse and touch
  input, this change's own instance on :8115 with a scratch database and a hard-linked COPY of the builder36
  library - Dummy's Sour Times given two embedded pictures and Strangers embedded lyrics on copies whose
  links were broken first, Mysterons a synced .lrc and the folder a `disc.jpg` as new files - and the
  stand-in Navidrome on 4533; 59 checks): at 1440x900 the album page's Properties (Year, Size, the release
  linked beside the app, First seen), the reissue's "1994 (this pressing 2014)"; the cover opened full size
  (600 × 600, the route with no size), focus on ✕, the page locked, a click zooming to 2x about the point
  (down the picture; across it held at the clamp, as designed), a drag, the wheel, Escape closing it with
  focus back on the cover; Tags' names as buttons beside their tick boxes; Sour Times' inspector (focus on
  Tracks, "Track 2 · 4:14 · FLAC", "2 of 11", the four groups and 22/7/5/3 fields, the dimmed disc with its
  reason, a dash for Genre), its two pictures with "600 × 600 · 6 KB · JPEG", one opened alone in the
  viewer inside the panel, zoomed and dragged, Escape closing the viewer alone (focus back on the
  picture); Next to Strangers (focus kept, embedded plain lyrics), Previous twice to Mysterons (the .lrc's
  synced lines, the verse gap, "synced", "From 01 - Mysterons.lrc", Previous greyed, keeping focus and
  refusing the click); All tags (10) with the file's name; Edit this track… on that file, Escape back to
  the track with focus on Edit this track…; the inspector in a 390px panel (`--app-desk-panel` set to 390px)
  with nothing past its edges; Escape back to the list (focus on the track's name), Escape again closing the
  panel; Artwork's CD art as a picture and its cover, each into the viewer and back. At 1024x768 the same
  Properties, the viewer inside the window, the inspector in the drawer with nothing past its edges, a
  picture into the viewer. At 390x844 (touch) Properties on the phone's album page, no Edit there, the
  release id broken inside its column with a 44px link; a tap on the cover opening the viewer with the
  touch hint, its frame the screen, its ✕ 44px, a two-finger pinch zooming, the ✕ closing it. No sideways
  scroll anywhere, no console error, exception or dialog.
- **After review** (thirteen findings, eleven once merged, every one confirmed and fixed): the docs' panel
  Escape rule naming the inspector as a layer (docs/library.md, and "back to the track or to its tab" in
  both guides); the viewer closed by a history move (above - it had stayed open in a hidden tab, holding the
  lock and taking the next Escape); Artwork's cover and CD art rings drawn inside; the track focus goes back
  to brought into view (it could land out of sight below a list longer than the panel, the next Tab or Enter
  on a row nobody could see); the screen reader's status line; three wirings app-rules claimed or the docs
  promised but nothing pinned - "Edit this track…" on that one file (`[filename]`, not the album's
  tracks), the list's scroll put back by its layout effect, the viewer's sources in order (the unresized
  cover first); the README's two app paragraphs and notes/sims.md's app-rules line brought up to date; and
  Properties' link reach from tokens, a whole 44px, all of it hit. Tests: `inspector` 81 → 97 checks (the
  viewer through popstate and hashchange, through the close given last, nothing listening once shut or
  gone; `trackNow`; `revealBy`; the status line, first and kept, its words per step, Back described by
  it); `app-rules` 339 → 343 (the restore effect after the focus hand-on, "Edit this track…"'s one file,
  the history listeners, the sources' order - and the focus check moved to `trackName`, none weakened);
  `test_app_css.py` and `test_app_desktop_css.py` extended in place (the two rings; the reach from the
  list's tokens, `min-height`, `position`) - 2447 Python tests still. 20 mutations, every one caught by a
  check (none by tsc alone), each file restored and checked by hash: one, the status line drawn only past
  the first track, was first written as a syntax error and re-aimed, and the check it then reached threw
  rather than failed - it reads with `?.` now, and says FAIL. Real page (this fixer's own instance on :8116, the same library): Back onto
  another tab's page with the viewer open at 390x844 touch and 1440x900 - no viewer left, no lock, a finger
  scrolling the page shown, one Escape closing the Edit panel there, the viewer not back on returning;
  the link 44px on one line and every row of it hit; both Artwork rings inside the clip; at 1440x560
  Next ten times from Mysterons and back by Escape or Tracks with Glory Box's name in view, upwards from
  the foot too, and a list whose row stayed in view put back exactly; the status line's words and its
  description of Back; Escape in the panel's viewer closing it alone; Back with it open leaving no viewer,
  panel or lock - 26 checks, and the builder's 59 again, all passing, no console error.
- **After review, second round** (four findings, each confirmed by skeptics, all fixed): **closing the tag
  editor opened from "Edit this track…"** put focus on that button out of sight - the editor's scroll stayed
  on the taller inspector (1526px against the editor's 801), so at 1440x700 scrolled to the editor's foot
  the button sat at -75 against the body's top of 116, its ring drawn where nobody could see and the next
  Enter acting unseen. The restore effect is now one for both ways back (`restoreView`: a top to put back
  and the control to bring into view - the track's name from the inspector, "Edit this track…" or "Edit N
  tracks…" from the tag editor), and the editor opens from its top, keeping where the view under it was
  (`editorOver`) - so the list's own way back, which had the same weakness on a long album, is fixed with
  it. **Properties said "Not tagged with a MusicBrainz release" when Navidrome merely didn't answer**: the
  bridge's `release_mbid: null` is also its answer when Navidrome couldn't be asked or has no album by that
  id (`navidrome_release` swallows both - `album_release`'s docstring warns of it), so an old address after
  a rescan showed the line under "Navidrome has nothing by that id". It now comes only from the album's own
  answer (`releaseSaid`: its `musicBrainzId`, '' when the answer came without one - 0.64.2 always sends it,
  the stub leaves it out - a list preview's until it comes); chosen over a flag in the bridge's answer as it
  touches no shared route. And two checks the docs promised but nothing held: the `…` a field only the file
  carries shows while it is read (rendered now, so dropping it or the inspector's `details.loading` fails),
  and what Artwork's two buttons open (the cover `coverSources(album, 'full')`, each CD art picture the very
  `discArtUrl` its thumbnail shows). Tests: `inspector` 97 → 100 checks, `app-rules` 343 → 346 (two
  existing checks moved to `restoreView` and `releaseSaid`, none weakened) - 2447 Python tests still. 19
  mutations, every one caught by a sim (two by tsc as well), each file restored and checked by hash. Real
  page (this fixer's own instance on :8117, the step1 library, headless Chromium as deadwax.test): at
  1440x700, 1366x660 and 1440x900, by Cancel clicked, Cancel by Enter and Escape in a field, the editor
  opening at 0 with its first field in view, and closing back on "Edit this track…" in view with the
  inspector where it was, the next Enter opening the editor again from its top; an inspector scrolled so
  the button was half above the top put back and moved on just enough to show it; the list's "Edit all
  tracks…" the same; Back after Next ten times still on Glory Box's name in view; Properties - nothing for
  `0000aaaa1111gone` under its error, "Not tagged" for the stub's Windows, Dummy's release linked - 24
  checks, no console error. With the two fixes undone and the bundle rebuilt, 12 of them failed (the button
  out of view at 289 and 329, "Not tagged" under the error), and passed again once restored.
- **NOT verified**: a real Navidrome's unresized cover (its original file; the stub's is 600px), an iPhone
  (the pinch, the touch hint, the release link opening beside the app in a home-screen app, the back
  gesture closing the viewer), VoiceOver (the inspector's headings and lists, its status line spoken on a
  step, the viewer as a dialog), an iPad on its side (44px targets in the panel), a track with dozens of
  pictures or a huge raw tag list, a real Navidrome's untagged album saying "Not tagged" (its
  `musicBrainzId: ""`, read from 0.64.2's source, never seen from a running one), and the merge with
  2.0.0-player.45.

### Navidrome required (2.0.0-player.46)

Finishing the web app (James, 2026-10-14; the spec is `uplan/slice-navidrome-required.md`, from the parity
audit's critic, "missed" point 1 and gap section 6). The one app's library is Navidrome's - the Library tab,
album pages, artist pages but `mb:` ones, Home's shelves and Search's library half all sit behind
`NeedsNavidrome` - while the README and getting-started called Navidrome optional, and the main page's
library is deadwax's own scan. James decided: **Navidrome is required for the library**, said so in the
docs and the gate, and **a folder Navidrome doesn't list gets a "Not in Navidrome" chip in Needs a look**,
so no folder on disk becomes unreachable once the main page goes - not a second library view. The gate's
words are notes/app.md's "Navidrome required (2.0.0-player.46)"; this is the queue's half.

- **The issue** (`metadata_health.py`): `not_in_navidrome` in `ISSUE_TYPES` - label "Not in Navidrome", a
  hint saying what it means (the app can't show or play it) and each thing to do (Navidrome hasn't scanned
  it: start a scan; can't read its files: the user Navidrome runs as; outside Navidrome's music folder:
  point it at `LIBRARY_PATH`'s folder), severity WRONG (the album may be perfectly identified). Still pure:
  `inspect_album(album, unlisted=False)` and `attach_issues(albums, reviews, unlisted=None)` take the paths
  Navidrome doesn't list from the route - a fact about Navidrome, never read off the album. So everything
  downstream is the existing machinery: the chip and its hint, the facet (`facets` lists any code with
  albums), `queueAlbums`' order by severity, the Edit panel on a queue folder, per-issue ignores, the main
  page's queue too (it renders `issue_types` as sent; LibraryView.tsx has no diff). Derived on every
  response, never stored - "the metadata queue stores only what you ignored" holds.
- **How deadwax knows: `src/navidrome_listing.py`** (new; pure match + the cache, the client passed in so
  its tests need no network - lyrics.py's shape). Internal client calls only, no route added, the fixed
  list and `test_there_is_no_general_proxy` untouched: **getScanStatus first**, then **getAlbumList2
  `alphabeticalByName`, 500 a page** (Subsonic's cap) until a short page (a repeated page ends it too,
  `LISTING_PAGES_MAX` 200 bounds it), then **getScanStatus again**. Asked as deadwax's own account (the
  shared `navidrome`, not `client_for`): what Navidrome lists is a fact about the server every viewer of
  the queue shares, cached once, as the scan wait's getScanStatus is.
  - **The match** (`judge`, pure): a folder is listed when Navidrome has an album with its release id
    (OpenSubsonic `musicBrainzId`, lowercased). Else by name - `artists._fold` (pins.py's precedent) of the
    folder's album title and any of its artists (the scan's, each file's album artist and artist) against
    each album's title and every name it's credited to (`artist`, `displayArtist`, OpenSubsonic `artists`);
    a folder no file of which names an artist is also tried as "[Unknown Artist]" (Navidrome's
    `consts.UnknownArtist` - the scan's own artist is then the parent folder's name). Title alone
    against an album credited to Various Artists or `isCompilation` - but only for a folder with no album
    artist tagged other than Various Artists (`may_be_compilation`): Navidrome credits the tagged album
    artist whenever there is one, so Queen's "Greatest Hits" is found by (title, Queen) or not at all,
    never "listed" by somebody's compilation of that name. **A folder with a
    release id matches by name only albums Navidrome knows by NO id**: an album carrying another release's
    id is another pressing (the deluxe beside the standard - a folder of the deluxe Navidrome doesn't
    list is flagged though the standard of the same title is listed). **A folder with no album tag on any
    file is never judged** (the scan names it after the folder; Navidrome files it under "[Unknown Album]").
  - **A negative needs evidence from a scan that saw the folder as it is now.** A folder changed after
    Navidrome's last scan BEGAN - `lastScan` (from the first getScanStatus) less its `elapsedTime` (a Go
    duration, nanoseconds: 0.64.2 writes `last_scan_at` as a scan ENDS, and works elapsedTime out as
    lastScan less the start it keeps to the second, so the difference is at or before the real start);
    with no elapsedTime above zero (an older server, a scan that began and never finished, a scan
    running) `LISTING_SETTLE_SECONDS` (120) before lastScan stands in - by the folder's own change
    (`changed_at`, new in the scan, SCAN_FORMAT 9: the later of its mtime and its CTIME - a folder
    added, a file renamed or added, a lyrics or cover fetch, and a folder moved or copied in by hand,
    which `mv`, `cp -a`, `rsync -a` and an unzip leave with its OLD mtime but whose ctime nothing outside
    the kernel can set back) or by deadwax writing it (`written_at`: every writer calls
    `forget_cached_album()` once its files are written, which notes the time - a retag moves neither
    mtime nor ctime - and the scan's next read of the folder stamps it on the album, so it is SAVED with
    the scan cache and `seed_cache` brings it back after a restart; `ALBUM_SERVER_ONLY_FIELDS` keeps
    both off the wire) - keeps the verdict it last had, and has none until judged once. So a
    just-filed album, a just-applied release (Navidrome still has the old id for the seconds before its
    watcher scans), a just-fetched cover and a folder just moved in are never NEWLY flagged - and one
    already flagged stays flagged until Navidrome has looked again, so an apply on a Not-in-Navidrome
    folder doesn't read "Fixed" in the session's row. **But for `LISTING_GRACE_SECONDS` (900) at most**,
    counted from the change to when the listing in hand was asked (`Listing.asked_at`, moved on every
    refresh that finds no scan since): a folder outside Navidrome's music folder never wakes its
    watcher, and with scheduled scans off by default lastScan never moves - waiting for a scan would
    leave exactly the folders the issue is for unflagged for good. The watcher scans about 5 s after a
    change, so a quarter of an hour is long past any scan that was coming. The last verdicts are kept in memory per path (`_verdicts`), never written down:
    MERGED from every read (a snapshot - the count's route, a page's first draw, the artist routes -
    lacks a folder a writer has just forgotten, and its verdict must outlive that read), pruned only by a
    real scan with no problem that found albums, carried along when deadwax moves a folder (`follow()`:
    the apply's rename, beside its `moved_to`; the artist re-file, per album - a merge's folder keeps its
    own), and dropped when `LIBRARY_PATH` changes (`forget_folders()`). **An UNSETTLED listing** - a scan running at either
    getScanStatus, or `lastScan` moving between them (an album can slip between two pages while
    Navidrome adds and removes them) - can say an album IS there, never that it isn't (the last
    verdict stands) and is never reused. No usable lastScan (a server that won't say): measured from
    the listing's own time less `LISTING_SETTLE_SECONDS` (120). Go's zero time (never scanned) judges
    nothing.
  - **The cost**: a refresh whose first getScanStatus matches the last listing's (settled, nothing
    running) reuses it - one call, Navidrome's albums can't have changed without a scan.
  - **When** (`ask(due_after, wait, rescan)`): a real scan (`/albums`, not a snapshot) asks when the last
    answer is older than `LISTING_FRESH_SECONDS` (10), **alongside the disk's walk** (`asyncio.gather`);
    `/rescan` always asks; the count's route asks only with no answer yet or one older than
    `LISTING_STALE_SECONDS` (300); a snapshot never asks. **A read is judged by the answer in hand and
    never held for a refresh** ("never blocking the queue") - the refresh runs behind it, for the next
    read. Two waits, each at most `LISTING_WAIT_SECONDS` (3): Navidrome's very FIRST answer (since start,
    or since a setting changed) - the one that can put a chip on the page first opened, as nothing reads
    again on its own - counted from when that refresh began, so the reads that come while it is out
    share one wait; and a Rescan's, counted from the Rescan, beside its re-read of every file - the way
    to see the check afresh. One refresh at a time, on the running loop (TestClient runs a request per
    loop, so a task of another loop is never joined - the route tests that need a refresh to land serve
    the app on one loop, `served`). **Until Navidrome has answered, nothing is raised; Navidrome unset or
    failing raises nothing** (a failure drops the listing). Each call bounded
    (`LISTING_CALL_TIMEOUT_SECONDS` 10), and the first getScanStatus NOT REACHING Navidrome (refused,
    timed out) ends the refresh there - the album pages would only wait out the same timeout again; an
    answer it can't use goes on, as a server that won't say when it scanned. A Navidrome setting changing
    forgets it all (`forget()`: the settings route beside `forget_navidrome_ids`, and on its own when URL
    or user differ from the answers').
- **The routes** (`routes/library.py`): `_scan_with_queue` passes `navidrome_listing.unlisted(albums,
  prune=<a real scan without a problem>)` to `attach_issues` and answers `navidrome_check: {state,
  problem}` - `listed | scanning | checking | unset | failed`, read by `check()` straight after the
  verdicts (never `ask()`'s return: a refresh can land while the walk or the reviews are awaited), no
  time in it, so an unchanged library is still a 304 (pinned). `/queue/summary` judges its saved scan by
  the same listing: the badge and the page count the same albums, from what is cached. The apply route
  (`_follow_verdict`) and the artist re-file carry a moved folder's verdict; the settings route's
  `library` invalidation drops them all.
- **The page** (`NeedsALook.tsx`, `lib/needsLook.ts`'s `navidromeNote`): why there may be no chip, said
  in the STATUS LINE (`.app-queue-checking`, always there and a row tall) when it has nothing else to say
  - not over a read's "Checking the library…" nor a failed read's Try again - as
  `<span class="app-queue-navidrome" title=…>`, one line with an ellipsis and its whole in the title (one
  rule in app-desktop.css, inside the desktop query: `min-width: 0`, `overflow: hidden`, `text-overflow:
  ellipsis`, `white-space: nowrap`), so its coming and going moves no row, over the saved scan, as the
  disk's read lands, mid-session, or as a session ends: `NAVIDROME_UNSET` (with where to set it up - "in
  deadwax's settings (Connections)", true of either page), `navidromeFailed(problem)`,
  `NAVIDROME_SCANNING` (past tense, "was scanning when last asked": nothing reads again on its own, so
  it must stay true once the scan has ended), `NAVIDROME_WAITING` (a disk read landed before
  Navidrome's first answer - asked again on the next read; no timer). Not over `problem` (no library),
  not on a phone (the page is still the phone's note). `NEEDS_LOOK_LINE` names the new kind of row ("...
  or that Navidrome doesn't list"). `useLibrary` exposes `navidromeCheck` (`api/types.ts` `NavidromeCheck`).
- **Not built, on purpose**: an "On disk" library view (James: not a second library view); a timer to
  re-read while Navidrome hasn't answered; matching a folder by path (Navidrome's song `path` is a fake one
  unless "report real path" is on for the player); following a folder renamed OUTSIDE deadwax (its new
  path counts as changed when it was renamed - its ctime - and its old verdict stays behind); per-user
  listings (step 6 - the queue is the admin's); persisting the verdicts (the metadata queue stores only
  what you ignored - the write time is a fact about the folder, saved with the scan's other facts).
- **Known limits**: a second copy of a release Navidrome lists, outside its folder, is "listed" (same id);
  getScanStatus can't say which folders a scan read (scan_wait.py's caveat: an admin's targeted scan or a
  second library moves lastScan too); with Navidrome's watcher off (or blind, on a network mount), a
  changed folder is judged 15 minutes after the change with no scan since - so a release applied IN
  PLACE is flagged then, Navidrome still listing the album under its old id (the hint's "start a scan"
  is the fix, and the app shows the album as it was, not "can't show" it); the verdicts are memory
  only, so a folder flagged and then written by deadwax shortly before a restart is unflagged until
  Navidrome scans or its 15 minutes are up (the safe direction); a ctime moved without the mtime
  (chmod, chown) on a folder the scan cache already holds isn't seen until the folder is read again;
  the SCAN_FORMAT bump means the first read after upgrading re-reads every folder's tags, as every
  bump does; a folder with NO album artist tag still matches a Various Artists
  album of its title (the scan doesn't read the compilation flag, so a single-artist rip with no album
  artist and that flag can't be told from one without - wrongly flagging those would be worse); a
  server sending no elapsedTime, with a scan longer than `LISTING_SETTLE_SECONDS`, could still flag a
  folder written while it ran; since a read never waits, what Navidrome changes shows one read late (or
  at a Rescan) - the badge's count up to five minutes late.
- **After review** (17 findings, every one confirmed by its skeptics; fixed, each with a test that fails
  without the fix):
  - *Reads waited up to 3 s on Navidrome* (two findings - the badge, the main page's Library tab, every
    Edit panel reload after a write, and a black-holed host costing 3 s a read for 20 s in every 30):
    `ask()` now holds a read only for Navidrome's FIRST answer (counted from when that refresh began, so
    reads while it is out share one wait) and for a Rescan; every other read is judged by the answer in
    hand. An unreachable first getScanStatus ends the refresh (one 10 s timeout, not two). Measured on
    the fixer's instance against a black hole: the first real read 3.01 s, the next 0.006 s, the count
    0.003 s; failed after 10 s, reads 0.006 s.
  - *A flagged folder lost its chip* (two findings, one major - a snapshot or the count read between a
    writer's forget and the next scan rebuilt `_verdicts` without the folder; a rename left the verdict
    at the old path; an unreadable scan wiped them all): verdicts merged, pruned only by a real scan
    with no problem that found albums, carried through the apply's rename and the artist re-file.
  - *lastScan is a scan's END* (0.64.2: `ScanEnd` writes `last_scan_at`): measured from lastScan less
    `elapsedTime`, so a folder filed while Navidrome scanned isn't flagged by that scan.
  - *[Unknown Artist]*: an artist-less folder is tried under Navidrome's placeholder.
  - *Any Various Artists title hid every folder of that title*: the title-only match only for a folder
    with no album artist but Various Artists.
  - *`navidrome_check` from before the chips*: read by `check()` with the verdicts.
  - *The Navidrome line moved every row* (two findings - arriving after the saved scan, coming and going
    mid-session): it lives in the always-there status line, one line, its whole in its title; the
    scanning words in the past tense.
  - *The start-up log said /player/ is off*: it says the app shows Connect Navidrome where the library
    would be, and what works without it; the partial-settings ERROR the same.
  - *Needs a look's line didn't cover the new row*: `NEEDS_LOOK_LINE` names albums Navidrome doesn't list.
  - *The compose and .env templates still said "Optional"*: their Navidrome blocks say needed for the
    app's library, reading the same music folder, and what it brings; getting-started's step 7 points
    at them.
  - *Unpinned* (four findings): a real scan asking again past ten seconds and the 304's re-ask; the
    badge's five minutes (scan, 60 s on: nothing asked; 300 s on: asked); the tagged-folder rule for
    compilations and `displayArtist`; the per-call bound, the catch-all, pruning and the page size - and
    the numbers the docs give pinned in one test.
- **After the second review** (9 findings, two of them twice - 7 fixes, each with a test that fails
  without it, but the docs line):
  - *A folder moved in by hand was flagged at once* (`mv`, `cp -a`, `rsync -a` and an unzip keep its
    old mtime, so it looked unchanged since Navidrome's last scan): the scan now reads `changed_at`, the
    later of the folder's mtime and ctime - a rename, a copy's arrival, an unzip all move the ctime, and
    nothing outside the kernel sets one back. (The first-seen time from the review store was the
    review's proposal; its skeptics showed it would leave every folder unjudged on a fresh database.)
  - *A folder filed after Navidrome's last scan was never flagged while no scan came* - the issue's own
    case, a folder outside Navidrome's music folder, never wakes its watcher: `LISTING_GRACE_SECONDS`
    (900) bounds the wait, counted from the change to `Listing.asked_at`, which a refresh finding no
    scan since moves on (`replace`). Bounded for every kind of change, a write by deadwax included, so
    the outcome is the same whether or not deadwax restarted in between; the cost, with the watcher
    off, is an in-place apply flagged after 15 minutes (Known limits).
  - *A restart flagged an album deadwax had just written* (the write time was memory only): the scan
    stamps it on the album (`written_at`), the scan cache saves it, `seed_cache` restores it. So
    `unlisted()` reads it off the album and lost its `root` argument - which also settles *the count
    route's `root` was unpinned*: there is no `root` to drop, and a route test pins the badge = the page
    for a folder written in place.
  - *docs/library.md put the Navidrome line "under its title"* (two findings): "in the line above its
    list where *Checking the library…* shows", as the rest of the page says.
  - *`useLibrary` passing `navidrome_check` on was unpinned*: needslook.sim runs the real hook.
  - *The count's "never held" check ran when the count had no reason to ask*: it runs past five minutes.
  - *The failure paths' generation fences were unpinned*: a forget, the new server's answer, then the
    old refresh FAILING (a NavidromeError, and anything else) - the new answer stands.
- **Verified**: 2531 Python tests (2529 passed, 2 skipped; 84 new in this change - `test_navidrome_listing.py`
  55, the match and the cache against a fake client; `test_not_in_navidrome.py` 25, through `start()`
  against a MockTransport Navidrome - those needing a refresh a read leaves running to land served on ONE
  event loop (`served`, anyio's blocking portal and httpx's ASGITransport), as uvicorn serves: the chip and
  its words, the badge = the page, the badge's first ask and its five minutes, a snapshot asking nothing,
  unset, down, the untagged and nameless rips, a folder filed since lastScan and one filed while
  Navidrome scanned, one moved in by hand, one no scan comes for past its grace, an apply a moment ago
  and across a restart, the badge = the page for a folder written in place, freshness, Rescan waiting,
  a read never held once answered,
  the check read with the verdicts, the 304, the ignore, a verdict through a count read and through a
  move, the apply and the re-file carrying it; two in `test_metadata_health.py`, two in
  `test_navidrome_settings.py` - a new LIBRARY_PATH forgetting the verdicts, and the start-up words),
  pyflakes, tsc, the bundle, all 49 sims (`needslook` 121 → 161: the note's rules, the page's chip, facet,
  address and Edit panel for a not-listed folder, the note in the status line in each state - the body's
  parts and the rows unchanged, mid-session too - and where it isn't, the page's line, and the gate's
  words, NeedsNavidrome.tsx compiled into the page's sim, and the real useLibrary.ts passing
  `navidrome_check` and `review_tracking_enabled` on). 50 mutations at first (judge's every rule, the
  cache's reuse, settling, ordering, paging, fencing, waiting and failure, the write log, each route's ask
  and judge, the settings forget, the start-up words, the note's rules, the page and the gate) - three
  first got past (an unsettled listing reused when the status matched again, a second refresh started
  while one was out, `unlisted()` with Navidrome unset) and gained their pins; after review 43 more over
  the fixes, on a copy of the worktree, each restored and checked by hash, all caught (one, the route not
  saying Rescan, first got past and gained `test_a_rescan_waits_for_navidromes_answer`); after the second
  review 16 more (ctime, the grace, `asked_at` moved on, the stamp, the restore, the wire, the hook
  three ways - tsc passing each - the count's wait, the count without the write time, both failure
  fences), all caught, the route tests alone catching the five that reach a route - both fences first
  got past, the test letting the old refresh start only after the forget, and now holds it out first.
  The engine guard is empty.
- **Checked in a real page** (headless Chromium over plain http as `deadwax.test`; this change's own
  deadwax on :8115 - a scratch database, a hard-linked copy of builder36's library plus a real copy of
  BULLY retagged as Portishead's "Roseland NYC Live" - against its own copy of the stand-in Navidrome on
  :8116 serving the library without that folder, and a Navidrome-unset instance on :8117; 29 checks): at
  1440x900 the sidebar's badge 2 = the page's All = the summary's; the chips All 2, ... Not in Navidrome 1
  titled with the hint; the Roseland row's one chip, no other row's; no line; the facet in the address,
  pressed, the list narrowed; the row opening the Edit album panel "1 of 1", the row current; the stub
  stopped - one line "Couldn't ask Navidrome which albums it has… couldn't be reached at
  http://127.0.0.1:8116…", no chip, the badge 1 = All 1 = the summary; the Library's gate "Can't reach
  Navidrome" with the reason, "Your library comes from Navidrome…" and Try again; the stub back and a
  Rescan raising it again; on :8117 the gate "Connect Navidrome" with "deadwax needs Navidrome for your
  library…" and its link to `/` beside the app, Needs a look's unset line with the rest of the queue,
  Requests and You drawn ungated; at 390x844 the gate's words, Needs a look still the phone's note, the
  Library ungated with Navidrome up, no sideways scroll; no console errors. **After review** (the fixer's
  own deadwax on :8115 against its own stand-in on :8116, and on :8117 against a black hole on :8118 -
  a port that accepts and never answers; 17 checks): badge = All = the summary; the page's line naming
  albums Navidrome doesn't list; the status line a row tall (36 px) and empty when checked; the stub
  stopped, the failure said IN the status line with its reason, its whole in its title, one line
  (18 px, clipped with an ellipsis), no chip, badge = All = summary = 1, and the first row and the status
  line exactly where and as tall as they were (285 px, 36 px); Roseland copied into the stub's library and
  scanned, a Rescan's answer the new one (no chip, one row, the first row unmoved, badge 1), and taken out
  again, a Rescan raising it again; at 1024 against the black hole, "didn't answer within 10s" in the
  status line, one line with the Edit panel open; 390 still the phone's note; no sideways scroll; no
  console errors. By hand against the black hole: the first real read 3.01 s, the next 0.006 s, the count
  0.003 s; failed after 10 s (one call), every read after 0.006 s. **After the second review** (the
  fixer's own deadwax on :8115 against its own stand-in on :8116 - whose watcher sees only its own
  folder, so nothing deadwax's library gains ever brings a scan, the case the grace is for; 32 checks
  in three passes): a copy of Roseland given an hour-old mtime and `mv`ed into the library, and Windows'
  album tag edited in place through `/tags/apply` (its folder's mtime and ctime unmoved, the stand-in
  still listing it as "Windows") - a moment after: neither flagged, Roseland (there before the stand-in's
  scan) flagged, one row chipped, "Not in Navidrome 1", badge 3 = All 3 = the summary, the status line
  empty; deadwax restarted (the saved scan carrying Windows' `written_at`): the same; 16 minutes on,
  no scan since: both flagged - three rows chipped, "Not in Navidrome 3", badge 3 = All 3 = the summary
  (the sidebar's count had asked the fifteen-minute-old answer again before the page's read, so the
  page's first read showed it). In every pass no album on the wire carried `changed_at` or
  `written_at`, 390 was still the phone's note with no sideways scroll, and no console errors.
- **NOT verified**: a real Navidrome 0.64.2 - that getAlbumList2 sends every album's `musicBrainzId`,
  `displayArtist`, `artists` and `isCompilation` as OpenSubsonic says, that getScanStatus sends
  `elapsedTime` in nanoseconds as its source says (`int64(status.ElapsedTime)`, a Go duration - read
  from source, never from a running one), and how long paging takes on a large library; the real :8081
  setup; VoiceOver.

### Looking after deadwax from a phone (2.0.0-player.47)

James (2026-10-14), finishing the web app: the phone gets all four managing pages a desktop has -
editing an album, Needs a look, server settings and the log ("phone" being any window under 1024px, an
iPad held upright included) - and Library care with them, the same kind of page. The main page, which
the phone's notes pointed at, will retire. There is no board; the artist page's panel (2.0.0-player.45,
"The artist page, as the main page had it") is the pattern. The spec is `uplan/slice-phone-managing.md`.
Built from .45 beside "Navidrome required" (.46, which lands first and also touches NeedsNavidrome and
Needs a look - the edits to the shared files here are kept small for that merge).

- **The Edit panel, a phone's sheet** (app/EditPanel.tsx): App draws `<EditPanel>` on both frames (it
  was `{desktop && …}`). On a phone App's `panel` is 'sheet', so `panelIsModal` makes it modal, as the
  artist page's panel: useSheet's scroll lock (`app-edit-open`), App's `covered` gains `editOpen` (the
  page, the tab bar and the mini player inert behind it), focus in to its close button and back to the
  Edit that opened it, and every Escape its own - `useEscapeFrom` takes `modal`, so an Escape from
  outside the box (focus fallen to the body - nothing behind can hold it) is the sheet's, never 'page',
  and the box takes no tabindex (a sheet's box never does). The layer is `is-sheet` there, `is-panel
  is-<column|drawer>` on a desktop. One layer at a time as before: the tag editor, the track inspector
  and the delete confirmation are layers over their tab, the cover viewers stop their own Escape first.
  **Its backdrop closes nothing** (after review): the sheet is capped at the content's width, so a phone
  on its side (102px of dimmed backdrop each side at 844px) and an iPad upright (64-190px) show it
  beside the sheet, where thumbs rest, and a stray tap there closed the sheet and - the editors let go
  as it slid away - threw away a tag draft, a pressing chosen with its preview or an open delete
  confirmation without a word. The app's other sheets keep theirs (they hold searches and cheap choices,
  not typed work); this one closes by its ✕, Escape and the editors' own Cancel, as iOS's own sheets
  with an edit in them refuse to be swiped away. A desktop's panel draws no backdrop, so nothing changes
  there. **It stays open across 1024px** (`closesOnCrossing` lost `editPanel`), a panel one side and a sheet
  the other, as Sources and the artist page's panel do; its editors are let go `EDIT_SLIDE_MS` after a
  sheet closes, as after a drawer (`panel === 'column' ? 0 : EDIT_SLIDE_MS`). In a sheet the Tags tab's
  note leaves out "Shift ticks a run" (`TagsList`'s `sheet` - a phone has no Shift). Everything else is
  the desktop panel's, unchanged: the same request, which folder, the page following the album to a new
  id after an apply, a delete going back, the queue's stepping.
- **Edit on the phone's album page**: App hands `onEdit` to an admin on both frames, and `editAt` -
  'actions' on a desktop (after Play and Shuffle, as before), 'bar' on a phone: a chip in the album
  page's sticky bar between the back link and the pin (`app-edit-toggle app-edit-chip`, `aria-pressed`
  while the sheet shows the album, disabled until the album has answered, drawn from the first frame).
  Above the title, so nothing under it moves whether it is drawn or not, and in reach from anywhere
  down the page. Chosen over the action row (a third pill beside Play and Shuffle crowds 320px) and a
  ••• menu (the album page has none - Now Playing's is the song's). It carries `app-edit-toggle`, so
  App's focus re-point after a move (`.app-edit-toggle[aria-pressed="true"]`) finds it.
- **The four Managing pages on a phone**: NeedsALook, LibraryCare, ServerSettings and EventLog are told
  `admin`, never the frame (their prop was `desktop`, App handing `desktop && admin`), so a phone draws
  each exactly as a desktop does; for anyone deadwax says isn't an admin - nobody, with logins off -
  each draws `MANAGING_ADMINS_ONLY` (lib/appRoutes.ts) and asks nothing, as `is-refused` - the four notes'
  class, which was `is-phone`; app-desktop.css's full-height settings page skipped the note by it, and
  that exclusion follows it, `.app-desk .app-settings:not(.is-refused)` (after the second review: left
  as `:not(.is-phone)` it excluded nothing, and the note took the page's column). The phone notes, their words
  (`NEEDS_LOOK_PHONE`, `CARE_PHONE`, `SETTINGS_PHONE`, `LOG_PHONE`) and their links to the main page are
  gone. The routes were always both frames'; You's Managing rows - Albums that need a look with its
  count, Library care, Server settings, Log - are drawn on both (You takes no `desktop` any more), and
  open the pages as siblings through `openManagingPage`; the footnote is the desktop's ("Everything here
  is in the app now; the main page stays until it retires.") on both (until it retired in .66).
- **What App asks on a phone**: `/deadwax/me` as an album page, an artist page, a Managing page or You's
  tab comes on top (`adminsOnTop`, which was `artistOnTop`); the review count as You's tab shows
  (`asksQueueSummary && admin && pageShown`, the one flag `desktop || nav.tab === 'you'`), where its row
  draws it - never at start-up, no timer. One flag (after review): with `desktop` and "You showing" as two
  dependencies a desktop - true either way - asked again each time it moved to or from You (its sidebar,
  any Managing page), two requests a visit; the flag stays true there, so the desktop asks as before.
- **The log's stream on a phone** is held by the same rule, and `managingLive` is also false while Now
  Playing shows (`!sheetOpen` - Now Playing over the page is to the log what the visualizer is on a
  desktop); the pages memo is keyed on `sheetOpen` too.
- **Set up Navidrome, on every frame**: the gate's not-set-up branch (app/NeedsNavidrome.tsx) lost its
  link to the main page's settings tab. It says "Set it up in deadwax's settings, under Connections" and
  has **Set up Navidrome** (`app-button app-needs-setup`), which calls `setUpNavidrome()` from
  `app/navidromeSetUp.ts` - a module, as searchBox.ts is: the gate is drawn by Home, Search, the Library
  and the album and artist pages, and App is what opens pages. App says what it does
  (`setUpNavidromeBy`): `showServerSettingsTab('connections')` (the settings page's kept tab; its drafts
  left as they are) and `openManaging('settings')`. ServerSettings tells its listeners of each save the
  server TOOK, with the keys it carried (`onServerSettingsSaved`, after the answer, never for a refusal),
  and App asks Navidrome again after one carrying a `NAVIDROME_` key - the server applies the three
  without a restart - so the gate a first run was opened from opens by itself. **Asked through
  `lib/navidromeCheck.ts`** (after review - the first re-ask was App's old `checkNavidrome`, with two
  faults the new caller made reachable): `navidromeChecks(navidromeStatus, setStatus)`, made once, whose
  `check()` (start-up, a gate's Try again) puts the status away first as before, and whose `recheck()`
  (after a save) is QUIET while the gates are open - the status drawn stays until the answer lands. The
  old one blanked it on every save, and NeedsNavidrome draws a spinner in place of what it guards while
  there is no status, so retyping the password on a working setup unmounted every gate's subtree on every
  tab - the Library (its loaded pages, scroll and artist sort lost), Home's shelf, the album or artist page
  on top of each stack - and fetched them all again. An answer that isn't ok still closes the gates; a
  gate not open yet shows its spinner while it asks, as Try again's. And each ask is a `latestOnly()`
  ticket, drawing (its answer or its failure) only while it is the newest: a save is the first caller that
  can overlap another ask (Try again hides as its ask starts), and an address that doesn't answer waits out
  the server's 10 s connect timeout (closing the old httpx client doesn't cut a connect short), so a fix
  saved inside it answered ok and the first ask's late "can't reach" - naming the new, working address -
  closed every gate again. A working-to-working change of NAVIDROME_URL leaves the pages drawn as they
  were, as before this change (nothing re-asked then). `settingslog.sim.cjs` drives the module; app-rules
  pins App to it. The
  "Can't reach Navidrome" branch keeps its Try again alone (the spec asked only for "set it up").
- **Style** (app.css, a section of its own at the end, tokens `--app-ph-*`): EVERY rule under
  `.app-shell:not(.app-desk)` - the phone's frame alone, App putting `.app-desk` on the shell from
  1024px - or `html.app-edit-open` / `html:has(.app-shell:not(.app-desk) …)`, which only a phone's
  sheet or page can set; app-desktop.css changes only by the settings page's exclusion following the
  note's class (above), so its rules for the same parts are still all that draw them on a desktop (`test_the_phones_managing_rules_never_reach_the_desktop`). The sheet is
  the artist page's: from the very top, its words clear of the status bar by padding, placed clear of
  a notch by left and right, at most the content's width, no transform once open (so the cover viewers'
  fixed frames are the screen's - the release editor's own "Compare full size…" viewer styled as the
  album page's viewer through `#app-edit-panel-release`, scoped to the phone), its body the one part
  that scrolls (pan-y), each tab's end clear of the home indicator unless its Apply bar clears it. The
  five underline tabs a finger tall, spread across where they fit and scrolling sideways by themselves
  where they don't (at 320px Delete runs off the edge) - `touch-action: pan-x` on the sheet's alone
  (`.app-edit .app-edit-tabs`: its layer takes every touch), never on Server settings' row of the same
  class, which sits in the page's own scroll, where it stopped a swipe up begun on the row from scrolling
  the page (after review); on a phone on its side (`max-height: 500px`)
  the title and its close button beside the tabs, a row of height given back to the body. The hosted
  editors are styled by their own ids and classes, as app-desktop.css styles them in the panel: fields
  17px and a finger tall, every button and tick box's label 44px, the release editor one column (the
  pressings in the sheet's own scroll - no list scrolling inside another), a change the tag over its old
  value (struck) and new side by side, long names, paths and ids broken anywhere, Apply and Cancel
  sticky at the foot under the summary and padded over the home indicator, delete the one red button.
  The Managing pages: each body inside the page's edges; Needs a look's rows a 48px cover beside name
  and artist, its chips under them wrapping (one alone too wide ellipsized); the settings' rows a key
  over its field, the save bar sticky above the tab bar and the mini player (`--app-ph-bar-mini`),
  taking no taps while it says nothing, the scroll padding keeping keyboard focus (and the field the
  keyboard comes up for) clear of it from the pane that shows only, as the desktop's - its words over
  Discard and Save, and on one line from 600px wide (a phone on its side, an iPad upright: found in the
  real page, where at 844x390 the two-row bar, the mini player and the tab bar left 140px of page;
  `--app-ph-bar` is the shorter bar there); the log's line its time, level and source over its words,
  which wrap; Library care's two cards, its field 17px (its placeholder "Artist, album or folder" - "- empty
  for the whole library" was cut off at 17px on a phone, and the line under the field says it: after
  review); in the sheet, Choose the folder's field the same, its placeholder "Name, artist or path"
  (app/FolderPicker.tsx, both frames: "Type part of its name, artist or path" took 282px of the 262px a
  320px phone gives its words, losing "path", and the status under the field says the rest - after the
  second review). The album page's chip is the pin's size, its reach 44px by a `::before`.
- **Not built, on purpose**: a history entry for the sheet (none of the app's sheets has one - a
  browser Back with it open goes back from the album page and the sheet closes with it, as the artist
  page's does); Try again's sibling for "Can't reach Navidrome" (above); a layout of its own for an
  iPad upright beyond the phone's (600-1023px gets the phone's, with the one-line save bar).
- **After review** (eleven findings, merged to seven fixes, each described in its bullet above): the
  Navidrome re-ask after a save through `lib/navidromeCheck.ts` - quiet while the gates are open, each ask
  a `latestOnly()` ticket (four findings); the review count by one flag, so a desktop moving to and from
  You asks nothing more; the Edit sheet's backdrop closing nothing; the tabs' `pan-x` the sheet's alone;
  Library care's placeholder shortened; docs/FRONTEND-MIGRATION.md's lead sentence rewritten for .47
  rather than contradicted at the paragraph's end; CLAUDE.md's rule on the hosted editors naming the
  phone's sheet and app.css's section beside the desktop's panel and app-desktop.css. And two guards in
  `test_app_css.py`: the phone's section is held to its rules only up to the next `/* ===== ` heading (it
  ran to the end of the file, so the next change appending an ordinary rule to app.css would have failed
  it), and every id and class the section styles is held to the source
  (`test_every_id_and_class_the_phones_section_styles_is_still_in_the_markup` - renaming `.tags-footer` in
  TrackTagEditor and checking the main page and the desktop's panel left the phone's sticky Apply bar
  matching nothing with every test green). 18 mutations, one per fix undone (six on the module, four on
  App, one on the panel's backdrop, three on the CSS, the section's end, two renames in the editors'
  markup, the placeholder), each caught, every file restored byte for byte (sha256). In a real page
  (this change's deadwax on :8110 against a stand-in Navidrome on :8111 over a copy of builder36's
  library, headless Chromium with touch over plain http as `deadwax.test`): at 844x390 and 768x1024 a
  tap on the backdrop beside the sheet (what `elementFromPoint` found there) left it open with a tag
  editor's typed draft, Escape closing the tag editor alone and the ✕ the sheet, focus back on Edit; at
  390x844, 375x667 and 320x568 a swipe up begun on Server settings' tab row scrolled the page, the
  sheet's own tabs still `pan-x` over a `none` layer; at 1440x900 and 390x844 NAVIDROME_PASSWORD retyped
  and saved asked Navidrome once with no gate letting go (no spinner, the Library and the album page on it
  the very same elements, the album not fetched again), a wrong password closing the gates with "Can't
  reach Navidrome" and the right one opening them by themselves; with the HTTP cache off, an address that
  doesn't answer (10.255.255.1) saved and the fix saved 1.5 s later, the gates open from the fix to 15 s -
  quiet while open, a spinner while closed - and never closed by the first ask; a desktop asking the count
  once as it showed and not at all over five moves to and from You, a phone not at start-up and once each
  time You showed; Library care's placeholder 177px in a 220px field at 320px; the builder's four-size run
  (20 checks each) passing again; the desktop's Edit panel at 1440x900 and 1100x800 drawing no backdrop.
  No console error.
- **After the second review** (two findings, both nits): Choose the folder's placeholder shortened, as
  Library care's was (above), pinned in `care.sim.cjs`; and app-desktop.css's `:not(.is-phone)` on the
  settings page, which the notes' rename to `is-refused` left excluding nothing - reachable by nobody
  while logins are off (`/deadwax/me` says everyone is the admin), the note anyone else gets on a desktop
  would have stretched to the page area's height - renamed with it, `test_app_desktop_css.py`'s settings
  test asserting the new selector and the note's class in ServerSettings.tsx, and a guard,
  `test_every_class_a_not_exclusion_names_is_still_drawn`: every class a `:not(.x)` in app.css or
  app-desktop.css names is still in ui/src. 7 mutations, each caught, every file restored byte for byte
  (sha256): the exclusion back to `.is-phone` (caught by the settings test, the guard and the real page
  alone), the body rule alone left behind, the note renamed with the exclusion left, a new exclusion naming
  a class nothing draws, the long placeholder back. In a real page (this change's deadwax on :8110 over
  a library holding Portishead and Ye's BULLY only, against a stand-in Navidrome on :8111 over builder36's
  whole library, so Tame Impala's album is Navidrome's with no folder here; headless Chromium with touch
  over plain http as `deadwax.test`): at 320x568, 375x667, 390x844 and 844x390 the Edit sheet on that
  album offered Choose the folder, the field took focus, its placeholder 161px of the 262/317/332/582px
  its words have (17px Noto Sans; the old one 282px), the scan's four folders each a finger tall, no
  sideways scroll, no field under 16px, "bully" typed narrowing it to one, Escape closing the sheet with
  focus back on Edit; the same in the desktop's panel at 1440x900 (10 checks a size); and at 1440x900,
  `/deadwax/me` answered `admin: false` by the browser (CDP Fetch), Server settings' note a block 198px
  tall where the admin's page is the 828px flex column - with the exclusion put back to `.is-phone`, the
  note was the 828px column too. No console error.
- **Verified**: 2477 Python tests (2475 passed, 2 skipped; 12 new in `test_app_css.py`, one of them
  extended for the one-line save bar, and one in `test_app_desktop_css.py`), pyflakes, tsc, the bundle, all 49 sims (`app-rules` 363 → 374,
  `routes` 273 → 274, `settingslog` 146 → 170, `care` 129 → 132, `needslook` 121 → 122, `you` 88 - its
  desktop-and-phone checks rewritten to "no frame in it", none weakened; app-rules' links-out list
  loses the four pages and the gate). 50 mutations, one or more per rule pinned (twelve on App, one on
  the frame's crossing, six on the panel, two on the album page's chip, thirteen on the four pages, the gate
  and its module, one on You, fifteen on the CSS), each caught, every file restored byte for byte
  (sha256 checked). The engine guard is empty, `player.sim.cjs` untouched, and `ui/src/components/` and
  `ui/src/hooks/` have no diff.
- **Checked in a real page** (headless Chromium with touch over plain http as `deadwax.test`, this
  change's own deadwax on :8110 against its own stand-in Navidrome on :8111 over a COPY of the builder36
  library with Portishead's Third staged at the root as a stranger's rip, a first run on :8112 with no
  Navidrome set, and the base commit's build on :8113 over the same library for comparison; 25 + 14 +
  4 × 22 + 4 × 20 + 9 + 7 checks, all passing, no console error): at 390x844 the rip's album page has
  Edit in its bar, a finger's reach every way; Edit opens the sheet (focus on its close, the page inert
  and locked), the rip found by name, the pressings listed, a pressing's preview (a change per line,
  Apply sticky at the foot and still in view scrolled), **Apply** re-filing it under Portishead and the
  page following the album to its new id with the sheet still open; two tracks ticked and a genre written
  to them, Escape closing the tag editor alone; a track inspected (focus on Tracks, Escape back to its
  name); Get CD art; the cover full size over the sheet (the screen's, ✕ 44px), Escape closing the viewer
  alone; Delete (the folder gone from disk, the sheet closed, the page gone back from, nothing locked).
  At 390x844, 375x667, 320x568 and 844x390: the sheet over the whole screen, its tabs a finger tall, a
  preview with Apply in view, Tags, the inspector, Artwork, Lyrics and Delete with no sideways scroll or
  field under 16px, Escape one layer at a time and focus back on Edit; Needs a look's rows and the sheet
  on a folder saying "1 of 2", skip ▷ and ◁ stepping with focus kept inside, its close giving focus back
  to the row; Server settings from You (three tabs, a draft marking its row, the bar above the mini
  player and the tab bar, the scroll padding reaching over it, Save storing the lead, Connections), the
  log from You (Live, one stream, the save's line from the history, a line logged while it shows
  arriving, every line's words inside the width; Now Playing over it letting the stream go and taking it
  again as it closes; leaving for You letting it go), Library care (Rescan, a run narrowed to
  "portishead" to its end, its words said); the release editor's own "Compare full size…" viewer the
  whole screen; widened to 1280 with the sheet open it became the side panel (not modal, the page live,
  no lock) and narrowed back a sheet again with focus inside. A first run: Home's gate with **Set up
  Navidrome** and no link, opening Server settings on You at Connections; the three typed and saved,
  deadwax reaching the stand-in, and the Library's and Home's gates opened by themselves. Compared with
  the base build pixel by pixel: at 1440x900 Home, the Library, the album page, the artist page, Needs a
  look, Settings (but for the scratch download folder's own path), Library care, You and the Edit
  panel's five tabs drawn the same; at 390x844 Home, the Library, the artist page, Search, Requests and
  You's top drawn the same, the album page differing only by the chip in its bar and You's foot only by
  Managing's rows and footnote.
- **NOT verified**: an iPhone (the sheet's safe areas, the keyboard over a field with the scroll padding,
  VoiceOver through the sheet and the four pages, the chip's reach under a real finger, the back gesture
  with the sheet open), an iPad upright, a real Navidrome giving an album a new id after an apply from a
  phone, Safari's EventSource on a phone, and the merge with 2.0.0-player.46.
