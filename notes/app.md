# The one app: its structure, Now Playing and Info

The app at /player/: routes, the gesture rule, the restyle, Now Playing and Info.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### The one app (2.0.0-player.9)

James decided (2026-09-29) that the player and the requester become ONE app: five tabs, You at the
right end, Get showing sources by default, Home open. The plan that builds it slice by slice at
`/player/` was synthesized from three designs (the session scratchpad's `uplan/plan.md` and
`slices.md`). This is slice 1: the five tabs with the player inside them, the restyle to STYLE.md,
the `/deadwax/me` seam, and disc titles on the album page.

- **Where it lives: `/player/`, grown in place, for good.** The same page, `#player-root`, entry
  (`deadwax-player`) and manifest (`start_url` and `scope` `/player/`), so James's home-screen icon
  and its per-device settings (`deadwax-player-*`) carry on with nothing to add again.
  `player/main.tsx` renders `<App/>` from `ui/src/app/App.tsx`. Nothing changed in vite, rolldown,
  app.py's prefixes or the gzip exceptions: `/player/` was already revalidated. One new stylesheet,
  `interface/player/app.css`, linked after player.css. `tests/test_pages.py` holds, through
  `start()`: each hand-written page's `/dist/<name>.js` to a vite input (a mismatch was a silent
  blank page), every linked stylesheet and what it `@import`s to something served, the manifest to
  `/player/`, app.css to no-cache and gzip, and no page or stylesheet to a Google Fonts address
  (the boards link one; deadwax self-hosts Noto and runs offline). The main page at `/` is
  unchanged: it stays the desktop tool for searching, downloading, editing, the review queue,
  server settings and the log until the app covers them.
- **The route model** (`lib/appRoutes.ts`, pure, pinned by `routes.sim.cjs`). The hash, since
  StaticFiles has no fallback for page routes: `#/home|library|search|requests|you`, and pages
  pushed on a tab as `#/<tab>/album/<id>` - and, since 2.0.0-player.13, as
  `#/<tab>/group/<rgid>?release=<mbid>`, the album you don't have - and, since 2.0.0-player.17, as
  `#/<tab>/artist/<id>`, an artist by Navidrome's id or `mb:<mbid>` (`PageKind` 'album' | 'group' |
  'artist').
  A group page's `release` (the pressing shown) is in the address but is NOT part of the page's
  identity (`samePage` compares kind and id) nor of where its scroll is kept (`scrollKey`), and a
  pick REPLACES the entry (`router.update` -> `replaceTop`), never pushes one - see "Search, and
  albums you don't have". A legacy `#/album/<id>` is rewritten with replaceState to
  `#/library/album/<id>`; an empty or unknown hash goes to `#/home`.
  - **Per-tab stacks, as in iOS.** A page is pushed on the tab that opened it (pushState, so the edge
    swipe and back work); switching tab replaces the entry with that tab's top page; re-tapping the
    tab you are on pops it to its root, and again at the root scrolls to the top; a double tap opens
    one page. Back labels name the page below: the tab, or the album under this one - and since
    2.0.0-player.17 the artist page under this one (`Page.label`, never part of the address or of
    what makes two pages the same).
  - **Going back is history's own back only when the entries below are exactly the pages below,
    made in this session.** Each entry the app makes carries `{n, load}` in history.state - its
    place, and which page load made it - and `HistoryNote.entries[n]` is the address it was given;
    `stepsBack` compares. Otherwise the address is replaced. That is what makes a cold deep link
    work, and what stops a back walking into another tab's page: open A in the Library, switch to
    Home (replaced), open B (pushed), switch back (replaced) - the entry under A is now Home's.
  - **The note survives a reload** (review): it is kept in sessionStorage under
    `deadwax-player-history:<load>` (`saveNote`/`readNote`), and a reload on an entry the app
    made reads its load's note back (`startHistory(place, address, saved)`). Without it, back
    after a reload replaced the address and left a copy of the entry below behind: the next swipe
    showed nothing and only the one after left the app. The LOAD is in the key because the n's are
    only one load's own - a tab that opens /player/ twice has two sets counting from 0, and reading
    the other's note would send `history.go(-n)` into the wrong entries. A load name is
    `Date.now()` and `Math.random()` (not `crypto.randomUUID`, which needs a secure context and
    deadwax is plain http on the LAN); a state from before loads were recorded, or storage
    refused, means entries below unknown, as before.
  - **The browser's own back or forward onto ANOTHER tab's entry is that tab chosen, as it was
    left** (`browserMoved`, review). Switching tab replaces the entry, so the entries below one
    tab's root are whichever tab showed when they were made: back from the Library's root lands
    on an entry Home wrote. Followed literally (`followRoute`) it emptied Home's stack - the entry
    names Home's root - and dropped the album opened there. Now the tab's stack is kept and the
    entry is rewritten to its top page. A web page can't stop that back from leaving the tab; it
    can stop it losing the tab it lands on. Within the tab showing, and for an address typed in
    (no place: it says where to go), `followRoute` as before - except going FORWARD in the tab
    showing (a place past the note's), which puts the pages passed back on top (`forwardTo`, the
    note's entries between of this tab, then the one landed on) and never searches the stack.
    Since 2.0.0-player.10's Go to album one album can be in a stack twice ([X, Y, X]), and the
    search took the lower X going forward, cutting Y and leaving the stack and the history apart
    (review). popstate and hashchange for one move are taken once (the address last shown).
  - **`lib/appHistory.ts` drives it** (`createRouter`): the only thing that touches the history,
    handed `window.history`, `location.hash` and sessionStorage by App, and heard back through
    `show`. It takes nothing from `window` itself, so `routes.sim.cjs` drives it end to end
    against a fake history that keeps entries and state across a reload, fires popstate then
    hashchange, and runs `history.go()` later, as a browser does - the reviewers' scenarios as
    they were reported. `app-rules.sim.cjs` holds App to it: no pushState, replaceState or
    `history.go` of its own.
  - **What stays mounted**: every tab's root, hidden while another shows (the document stays the
    scroller, for the status bar's tap-to-top), and each tab's top page. Scroll is saved per route
    as it is left and restored in a layout effect; a page opened afresh starts at its top. The
    roots are memoised elements, so the music playing re-renders the player's parts and not the
    grids. Sheets are state, not addresses.
- **The gesture rule, and `app-rules.sim.cjs`.**
  - `usePlayer()` is called once, in `App`, which never unmounts. `PlayerContext` carries the player
    (a new object on every change of `playing` and the rest), `ActionsContext` the engine's actions,
    which never change (`pickActions`). Only pages read the contexts; leaf components take props,
    because the fake-Preact sims have no `useContext`.
  - The playback actions (playTracks, toggle, next, previous, setGapless, showAirPlay) are reached
    only from an allowlist: AlbumPage (playTracks), MiniPlayer (toggle, next), NowPlaying (toggle,
    next, previous, showAirPlay), GaplessChoice (setGapless, since 2.0.0-player.10 moved Gapless to
    You), Turntable (toggle, the record's tap, since 2.0.0-player.11 - and since 2.0.0-player.14 a
    release with no coast to wait for, and the deck's two named moves, `holdSong` and `resumeSong`:
    pause as a hand takes the record, play at speed after a coast; app-rules pins those four by
    name, and the deck calls no action itself), Search (playTracks, a song
    found, its album in hand, since 2.0.0-player.13), ArtistPage (playTracks, Play and Shuffle with
    every album of theirs you have in hand) and Requests (playTracks, a Done row's ▶ with its album
    in hand), both since 2.0.0-player.17, PlayerBar (toggle, next, previous, showAirPlay - the
    desktop's player bar, since 2.0.0-player.19), Visualizer (toggle - the desktop visualizer's
    play/pause, from its click or the Space key, since 2.0.0-player.20), and `app/context.ts`, which names them and
    calls none. Adding a file is a deliberate edit to the sim, like the Navidrome
    route list.
  - Nothing outside `app/` and `player/` imports usePlayer, the contexts or App.
  - Only App imports usePlayer as a VALUE, under any name (review: `usePlayer as useEngine`
    slipped past the call count), and `app/context.ts` calls none of the actions it names (a
    helper there that fetched and then played would start playback outside the tap for any page).
  - Nothing in `app/` contains setActionHandler, `new Audio`, `<audio`, `.src =`, srcObject or
    `.load(` - comments included, so don't name them in a comment there.
  - **A link out of the app opens beside it** (`target="_blank" rel="noopener"`, review): the
    Search card (until 2.0.0-player.13, and Requests' until .12), You's Managing row, the gate's settings link and
    (since 2.0.0-player.19) the desktop sidebar's "Open the main page" - and (since 2.0.0-player.21)
    the Edit panel's, for an album it can't find a folder for. Followed in the
    same page, `/` unloads the player - the audio element, any stream and the queue, which
    nothing keeps. From the home-screen app it opens outside the app's scope either way (Safari
    or a browser view over it; not seen on the phone). The sim fails on any `<a href>` in app/ or
    player/ that isn't a `#` link and doesn't open beside.
  - **While Now Playing is open, everything behind it is inert** (review): the panes, the mini
    player and the tab bar sit in one `.app-behind` wrapper with `inert` and `aria-hidden` while
    `sheetOpen`, so neither Tab nor VoiceOver reaches the five tabs under the sheet (activating one
    switched tabs out of sight). NowPlaying moves focus to its close button as it opens (a layout
    effect, before anything else can move it), and App gives it back to what had it (taken in the
    tap, before the page behind turns inert and the browser drops focus from it) - on iOS a tapped
    button never had focus, so nothing is given back there. No focus trap and no Escape: slice 2's
    shared sheet does those. (**Done in 2.0.0-player.10**: every sheet is `app/useSheet.ts`, with
    Escape, and the opener focuses itself in the tap, so there is something to give back on iOS
    too - see "Now Playing as designed, with Info".)
  - **Tiles navigate, never fetch-and-play.** Home's shelf and the Library grid open the album;
    they `prefetchAlbum()` on pointerdown (called off on pointercancel - the press became a scroll;
    taken once by `album()`, kept 30 s), so Play is usually live by the time the page opens, and
    Play is pressed on the page, in the tap.
- **The Navidrome gate narrowed** (`NeedsNavidrome`): drawn inside Home's shelf, the Library tab and
  the album pages only - and since 2.0.0-player.13 Search's library half. The tab bar, You,
  Requests, Search's MusicBrainz half and the album you don't have work with Navidrome unset or
  down. App asks `/navidrome/status` once for every gate.
- **You**: Maximum quality moved from the settings sheet (`player/Settings.tsx`, deleted with the
  gear) to You > Playback as `app/QualityChoice.tsx`: the words, the storage key and the keyboard
  handling unchanged, pinned by `settings.sim.cjs`, retargeted (it read the Gapless label from
  NowPlaying.tsx; from GaplessChoice.tsx since 2.0.0-player.10). Connections: the main page's two pings and Navidrome's status, asked the
  FIRST time You shows, not at start-up (the MusicBrainz ping is a real request to a rate-limited
  service), and on "Check again". About: the version and "logins are off" from `/deadwax/me`,
  asked WITH the pings, so "Check again" asks it again too (review: a first ask failing - deadwax
  restarting under Komodo - left "unknown" there until the app was killed; a failure clears as the
  next ask begins, and a failed ask after a good one keeps the version and says so). The identity
  line says only what deadwax said: nothing when it hasn't answered. Each connection row is its own
  polite, atomic live region (review: one region on the list read out a bare "Connected" with no
  service name, in whatever order the answers came). A row links to `/` for server settings, the
  review queue, the log and editing, in a new tab. Admin rows are gated on `me.admin` (true with
  logins off); Sign out isn't drawn while logins are off. Gapless stays on Now Playing until slice
  2 moves it here (it did, in 2.0.0-player.10: a checkbox above Maximum quality). `you.sim.cjs`
  renders You with deadwax faked and pins all of this.
- **Search and Requests were honest placeholders** ("On the main page for now", with a link),
  Search until slices.md's S4 (2.0.0-player.13, which deleted `app/Placeholder.tsx`; Requests keeps
  its `app-placeholder-*` card classes for its own empty and failed states) and Requests until S3. Home had only "Recently added"
  (getAlbumList2 `newest`, 20 albums): Arriving, Pinned and Not played in a while came in later
  slices and were NOT faked meanwhile. Requests and Arriving came in 2.0.0-player.12 (S3) - see
  "Requests, and what's arriving" - and Pinned and Not played in a while in 2.0.0-player.18 (S7) -
  see "Pins, and a finished Home". **Future slices are named by their slices.md id (S4 Search, S5
  Sources and Get, S6 Artists and the id bridge, S7 Pins, S8 the desktop frame), never a version
  number**: the turntable went in as .11 outside the plan, so every slice after it took the next
  number up, and slices.md's own numbers no longer say which version a slice ships as.
- **`/deadwax/me` and `current_user`** (`src/users.py`, `src/routes/me.py`): a FastAPI DEPENDENCY
  returning `local` - never `@app.middleware("http")`, which hides disconnects. The answer is
  `{user, admin: true, auth: 'off', version}`. Step 3 changes `current_user`'s body and nothing
  else; `test_me.py` overrides the dependency to prove the route reads it.
- **The token section, theme.css section 10 (`--dw-*`)**: STYLE.md's "just a touch of Windows 7"
  as tokens, aliasing what exists - `--font-family` (the self-hosted Noto), `--font-mono`,
  `--accent-hover`, section 7's durations (so reduced motion still collapses them). Nothing in
  main.css reads a `--dw-*`, so the main page doesn't change by a pixel.
  - player.css keeps `--pl-*` for the MECHANICS (safe areas, edges, hit sizes, the sheet's motion,
    the scrubber's sizes, `100dvh`) and points its LOOK at `--dw-*`: Noto instead of SF, STYLE's
    palette, 3/4/6px corners (covers 3), the blur tokens `none` (the sheet's blurred-cover backdrop
    isn't drawn: `--pl-backdrop-display`), shadows no bigger than 0 1px 2px, the scrub track a sunken
    well (a hairline edge, an inset shadow, a grey gradient fill; the round thumb kept), and no
    uppercase or letter-spaced labels (the hero's meta line, the disc headings). The order chips
    were secondary and toggled, Play primary (the chips went with 2.0.0-player.17's Library chips
    and sort, and their rules and tokens with them, after review). Layout lives in the rules, so no
    hit area moved, and reverting the look is a token change.
  - The mini player keeps its 64px, its sides and its buttons, and moves up:
    `.app-shell .pl-mini { bottom: <the tab bar> + inset }`, with `.app-shell` padding for both.
    Stacking: the tab bar 8, the mini player 10, Now Playing 20 (and since 2.0.0-player.10 its •••
    menu and Info, 30; since 2.0.0-player.15 the Sources sheet, 25).
  - New chrome is `app-` classes in app.css, tokens only - line heights, the pressed opacity and
    the primary button's pressed filter included (`--dw-leading-*`, `--dw-pressed-cover`,
    `--dw-primary-pressed`, review). `tests/test_app_css.py` reads the rules and fails on a raw
    length, time, line height, opacity or filter outside :root. The Gapless switch is still iOS's
    pill until slice 2 makes it a checkbox in You (2.0.0-player.10 did; the `--pl-switch-*` tokens
    and rules went with it).
  - **Play and pause stay round** (`--pl-radius-round`, STYLE.md; the restyle had given the
    transport buttons the card's 6px, so a press flashed a rounded square).
  - **Focus rings**: one drawn outside what it marks only where there is room (a free button, a
    shelf tile - the shelf keeps `--app-ring-room` above and below its tiles); one drawn INSIDE
    (`--app-ring-inset`) for a row of a grouped list, the tab and the radio, since `.app-group`
    clips with `overflow: hidden` and a ring outside a row there was clipped away entirely.
  - **Keyboard focus scrolls clear of the fixed chrome**: `scroll-padding` on `html`, the tab bar
    (and the mini player, `html:has(.app-shell.has-mini)`) at the bottom and the album page's
    sticky bar at the top - the same room the shell's padding keeps (`--app-chrome-bottom*`). A
    browser counts a control under fixed chrome as in view and wouldn't scroll to it at all.
  - **A phone on its side gets iOS's compact tab bar** (`@media (max-height: 500px)`: the icon
    beside the label, `--dw-tab-item-compact` 32px), since at 844x390 the full bar and the mini
    player covered half the screen. Everything clearing the bar reads `--app-tabbar-height`, which
    is built from `--app-tab-item`, so it follows. The mini player keeps its size.
  - **Home as the board has it**: 12px from a heading to its shelf (`--app-shelf-heading-gap`;
    You's cards keep 6px), and a tile's title and artist in one block with nothing between.
- **The engine guard, on every slice**: `git diff --stat` is empty for `ui/src/player/usePlayer.ts`,
  `streamSource.ts` and `ui/src/lib/{playQueue,gapless,scrub,streamWrap,streamPlan,fmp4}.ts`, and
  `player.sim.cjs` and the engine sims pass untouched. `player/api.ts` may grow route wrappers (it
  gained `prefetchAlbum`/`dropPrefetch`, a `size` for `albumPage`, a `signal` for `navidromeStatus`
  and `discTitles` on the album type; and in 2.0.0-player.10 `rememberPlayed`/`playedAlbum`, the
  album answers Info reads, and `sentFormat`, streamFormat's question put to the engine's own
  element - none of them a route).
- **Disc titles from Navidrome** (James: "make sure the disc titles get picked up from navidrome").
  getAlbum's OpenSubsonic `discTitles: [{disc, title}]` - Navidrome's reading of the `discsubtitle`
  deadwax writes, passed through untouched by `/deadwax/navidrome/albums/{id}` - goes through
  `lib/discTitles.ts`: "Disc 4 · <title>", or "Disc 4" for a disc without one; headings show when
  the album has more than one disc OR any of its discs has a title, so an ordinary one-disc album is
  unchanged; no disc number is disc 1; a blank title, or one for a disc with no songs, is ignored.
  `discs.sim.cjs` pins it, and that AlbumPage reads `album.discTitles`. **A one-disc album deadwax
  filed shows no title** (review): Navidrome records a disc's title only for a disc number above 0
  (`ToAlbum` in model/mediafile.go; a missing tag reads 0), and `tag_values` writes no disc number
  for a one-disc release - so its `discsubtitle` never reaches `discTitles`. The guide says a
  one-disc album shows its title only when its files carry a disc number (Picard's "1/1", or Disc
  set with Disc title in the tag editor), and the sim holds the guide to it. Writing
  `discnumber=1` beside a title on a one-disc release would be a change on MAIN (every titled
  one-disc album gets a one-time disc-number diff) - James's call, not made here.
- **Verified**: 1825 Python tests, pyflakes, tsc, and all 23 sims (routes, app-rules, discs and
  you new); 33 mutations, one per rule pinned, each caught and restored byte for byte - and after
  the review, 27 more, one per fix (each a test failing without it). **NOT verified here**: the
  real page, which the build workaround and a check against the stubs cover after this change;
  and everything on the iPhone - the tab bar (compact on its side), the mini player above it and
  the safe areas under a real finger, a link to the main page from the home-screen app, whether
  Navidrome 0.64.2 sends `discTitles` for James's albums, and the home-screen icon opening the new
  app with its settings kept. The guide's "Not yet verified" list carries the same.
- **After review**: seventeen findings, each confirmed by skeptics, fixed together - the links
  opening beside the app, another tab's entry gone back onto, `/me` asked again, the one-disc
  title in the guide, the reload's note, the clipped focus rings, the live regions, the scroll
  padding, the inert page behind Now Playing, the compact tab bar, the round transport, Home's
  spacing, raw values, the two gaps in `app-rules.sim.cjs`, the unverified claims in the guide,
  the back label promise, and the troubleshooting wording (You shows **Not set up** or **Can't
  reach it**).

### Now Playing as designed, with Info (2.0.0-player.10)

Slice 2 of the one app (`uplan/slices.md` S2). James: "the 'in one stream' and the quality
shouldn't be displayed in the player, at least not by default, but I would like an 'info' tab in
the menu in the player that would show you everything", "I'd like the info to be more about the
song, album, and artist. with maybe a debug tab to show everything there now", and "gapless should
be a switch in the global settings".

- **Now Playing as its board draws it** (`NowPlaying.dc.html`): the cover, the title, "Artist —
  Album" as ONE line in the accent that goes to the album (a button; the same box as a `<p>` for a
  song with no album id, which nothing makes today), the scrubber, the transport, and a row of
  icons: AirPlay while there is a speaker, and ••• always, at the right end. Only what does
  something today: no Lyrics, Up next or turntable buttons, and no "Now Playing opens as" setting
  (the turntable came next - see "The turntable (2.0.0-player.11)"). The two readouts and the
  Gapless switch left it.
- **Nothing whose height can change sits below the title** - the rule from the 1.1.0-player.2
  review, which put the readouts ABOVE the title. With them gone, the one line that comes and goes
  is `player.error` (a failure, the skip notice), and it moved above the title too: it moves the
  cover, never the album line, the bar or the buttons. The album line is one `nowrap` line, a line
  tall even when empty; the icon row is `height: var(--pl-hit)` (not min-height) with or without
  AirPlay, `justify-content: flex-end` so ••• holds its place when AirPlay comes and goes.
  `app-rules.sim.cjs` pins the body's order, `test_app_css.py` the fixed row. The album line's tap
  target reaches 44px through `::before`: up over the lower half of the title (which takes no
  taps) and down into the gap above the scrubber, stopping short of the bar's own target
  (`--pl-byline-reach-*` against `--pl-scrub-gap`, held by the test). The ellipsis is on the span
  INSIDE the button, since clipping the button would clip that reach away.
- **The ••• menu** (`app/ActionMenu.tsx`): the board draws the button, not the menu, so it is a short
  sheet from the bottom over a dimmed Now Playing: Info, Go to album, Cancel - and since
  2.0.0-player.18 "Pin album to Home" (see "Pins, and a finished Home"). Go to album is left out,
  not greyed, for a song with no album id.
- **Go to album** - the menu's row, the album line and Info's album card, one `toAlbum` in App:
  every sheet closes and the album opens on the tab showing, through the `openAlbum` a tile uses,
  drawn at once from the answer it was played from (`playedAlbum`) or the queue's name and cover.
  Focus is not sent back to ••• (its sheet is going): Now Playing gives it to its own opener.
- **Info** (`app/InfoSheet.tsx`, `NowPlayingInfo.dc.html`): a sheet whose top is
  `max(52px, safe-top + 8px)` - the board's 52px is from the top of the SCREEN, status bar
  included - with Done, a segmented control that is a real tab list (the arrows move the choice and
  the focus, one tab stop), and one scrolling panel. The board's grabber isn't drawn: nothing drags
  Info, and a grabber that doesn't is a dead control. Debug's rows follow the board, the label at
  the left and the value at the right end of its line, and a value too long for that goes whole to
  the line under it, at the left (flex-wrap, the LABEL taking the slack - `margin-right: auto` -
  so a value alone on its line has no margin pushing it right). Info stays mounted, hidden while
  closed, so its one scroller would keep its offset: a layout effect on `[open, tab]` puts it back
  at the top as Info opens and as the tab changes, never as it closes (it is still sliding away in
  sight); the tab itself is kept. The menu and Info are placed by the insets (`left`/`right` at
  `--pl-safe-*`, as the mini player is) and capped and centred inside that, their padding the
  board's alone (16px, the menu's 8) - padding by the inset as well put their contents 47px in
  from their own edge on a phone on its side. Each half of the segmented control reaches 44px to a
  finger: its `::before` sits against the half's PADDING box, `--app-segment-edge` (the well's
  border and padding and the half's own border, three hairlines) inside the well, so the reach is
  `--app-segment-reach` plus that edge (it was 38px).
  - **About** (`lib/aboutRows.ts`, pure) asks NO server anything - in 2.0.0-player.10; since
    2.0.0-player.17 Info asks four things as it opens (`app/useInfoDetails.ts`: getSong, the id
    bridge, getArtist, MusicBrainz's facts) and About draws them, the album's line gains its label,
    and the artist's card goes to the song's own artist's page (see "Artists, and the two libraries
    joined"). The queue's `QueueTrack` carries
    only what playing needs (and `lib/playQueue.ts` is the engine's, not to be touched), so the
    album answer a queue is played from is REMEMBERED at the tap: AlbumPage's play calls
    `rememberPlayed(album)` and then `playTracks`, in the same turn, nothing awaited
    (`player/api.ts` over `lib/playedAlbums.ts`, the last `PLAYED_KEPT` (8) - and since
    2.0.0-player.17 every album of an artist's Play, `rememberQueue`). The song: its title,
    its artist, "Track n of N · length" (N counted on the song's OWN disc - numbers restart per
    disc on a set deadwax filed; a number past its disc's count is counted against the album, and
    past that N is left out), and its disc line, read off the album page's own `discHeadings()`
    so the two can't disagree ("Disc 2 · Unreleased Tracks", only where the album page draws
    headings). The album's card: cover, title, and "year · format · N songs" (`sharedFormat`
    moved to `lib/format.ts` for both), going to the album. The artist: the song's, with "The
    album is by X" when the album's own artist differs. **A field Navidrome didn't send is LEFT
    OUT** - no year 0, no "Track 0", no placeholder. With the album answer not in hand, only what
    the queue knows.
  - **Debug** (`lib/debugRows.ts`, pure): the readouts as labelled rows, BUILT ON
    `describeGaps`, `describeSeek` and `describeWrap`, so the phrases the guide explains and the
    engine sims pin ("handed over, from memory", "in one stream", "FLAC in MP4") are still the
    phrases shown - but not line for line: each row drops its line's opening words, and the seek
    line's tail (how the song came) is the Sent as and Resampled rows. Format (OpenSubsonic's
    samplingRate, bitDepth, channelCount; a part not given left out); Sent as (describeWrap's words
    with the depth and rate the song was SENT at - 24-bit at the new rate when resampled, whatever
    the source's depth); Resampled (`192 kHz to 48 kHz, 3 dB quieter`, `RESAMPLE_HEADROOM_DB` held
    to src/resample.py's HEADROOM_DB). **Asked for resampled and not answered yet**
    (`awaitingResample`): an MP4 before its headers (`got` null), or a stream song before its head
    is in (`got` 'stream', `resampled` AND `hiRes` both null - once the head is in, one of them is
    set for any song above 48 kHz) that `resamples()` under the setting - deadwax makes a
    resampled song whole before sending any of it, seconds on a NAS, and Debug is likeliest opened
    then. Sent as drops its depth and rate, Resampled says `Not known yet` and Why "Asked for
    resampled; deadwax hasn't answered yet", where they read "No", the file's own 192 kHz and "or
    deadwax sent it as it is". Why (the
    first reason that holds whatever the setting - the rate, the kind, the ratio, the depth,
    `resamples()`'s own tests, so the two can't disagree - and then the setting, by QualityChoice's
    names, held by the sim: a 44.1 kHz song under "Original" says the rate, not the setting); Gapless (Off, On, On in one stream); Gap (describeGaps less its first
    words, the changes before on an "Earlier" note); Last seek; and **Navidrome sent**: the sorted
    field NAMES of the playing song and of its album, as deadwax's route passed them through
    untouched - names, never values - so the fields slices.md's S6 and S7 want (musicBrainzId,
    played, playCount, composer) can be read off James's iPhone against 0.64.2 first. "Not known"
    without the album answer. **A name alone misled both ways** (review, read in Navidrome
    v0.64.2's responses.go and helpers.go): OpenSubsonic fields without omitempty are ALWAYS sent -
    `musicBrainzId` (song and album), `discTitles`, `displayComposer`, `bpm`, `bitDepth`,
    `channelCount`, `userRating` on an album - as "", [], 0 when the files have nothing; and
    `playCount`, `played` (set only when PlayCount > 0), `starred`, `userRating` on a song, `year`,
    `track`, `discNumber` are omitempty, gone whenever zero or unset. deadwax never writes a
    recording id, so every song it filed sends `musicBrainzId: ""`. So each row puts the names sent
    EMPTY ("", 0, null, [], {} - `isEmptyValue`; `false` is a value) on an "Empty: ..." note, and a
    third row, **On other songs** (`otherSongsFields`), names the fields another song of the album
    carries with a value and this one doesn't: where `playCount` shows for a song never played.
    The answer is the tap-time snapshot (`rememberPlayed`), so a song played since still lacks
    `playCount` until its album page is opened and played from again - the guide says so.
  - **Sent as asks the engine's own element.** Whether a song is asked for as the file or as
    Navidrome's MP3 (`streamFormat`) turns on `canPlayType`, which the engine doesn't expose and
    can't be changed to. `sentFormat()` in player/api.ts puts streamFormat's question to
    `document.querySelector('audio')`, the element the engine made - every element gives the same
    answer - and NEVER makes one (iOS unlocks audio per element), sets nothing and starts nothing.
    It is asked only while Debug is drawn.
  - The rows are worked out only while Info is open; what it last drew stays drawn as it slides
    away.
- **Every sheet is a sheet by one hook** (`app/useSheet.ts` - a hook, not a wrapping component, so
  the fake-Preact sims, which render one component and none inside it, run all of it): **its own
  scroll-lock class on `<html>`** (`pl-sheet-open`, `app-menu-open`, `app-info-open`: one shared
  class would be taken off by whichever closed first, with another still open), focus in to its
  first control before the paint, **focus back to its opener as it closes**, **Escape for the sheet
  on top only** (one with another over it - `covered` - doesn't listen, so one press closes one
  sheet), and, in the markup, `inert` while closed and a backdrop tap. **The opener focuses itself
  in the tap** (`takeOpener`): WebKit never focuses a tapped button, so without it there was
  nothing to give focus back to on an iPhone or in Safari (2.0.0-player.9 gave nothing back
  there). Now Playing is inert and hidden while the menu or Info is over it. The two are never open
  together: choosing Info closes the menu with no focus given back (App leaves the menu's opener
  out while Info is over), and Info gives focus to ••• itself when it closes. The mini player and
  ••• pass their click's event up for this. Stacking: the menu and Info at `--app-z-over` (30),
  over Now Playing's 20.
- **Touch.** `.app-layer`, the menu's and Info's, is `touch-action: none` like `.pl-sheet`, so no
  touch on them pans the page behind; Info's scroller opts out with `touch-action: pan-y` and
  `overscroll-behavior: contain`. A scroller starts its own count (Pointer Events: the touch
  behaviours are those of the elements from the one touched up to the nearest scroller; WebKit's
  style adjuster resets them at an element with scrollable overflow), so the panning comes back
  inside it and nowhere else. **Not seen under a real finger yet.**
- **Gapless is a checkbox in You > Playback** (`app/GaplessChoice.tsx`): the You board draws a
  checkbox, and the app's rule is "checkboxes, not switches". A `role="checkbox"` button, above
  Maximum quality, with a note under it. **Its tap is the
  gesture**: `setGapless` straight from the click, in the same turn - turning it on makes and
  unlocks the second audio element, and iOS unlocks per element from a tap - and a click, never a
  change event. It is the ONE new file on `app-rules.sim.cjs`'s allowlist; NowPlaying lost
  setGapless. You hands it the player itself and names no action of its own. The storage key is
  unchanged (`deadwax-player-gapless`), so an installed app keeps the setting. `settings.sim.cjs`
  renders it and holds the call to the tap, reads the label from GaplessChoice.tsx now, and holds
  Maximum quality's notes to "with Gapless on" (they said "the Gapless switch").
- **Docs**: player.md's "The readout" became "Info → Debug", with every row, and every "switch"
  went; troubleshooting has a new entry saying where the readouts went (and how the wording moved),
  and its Gapless and seek entries name the rows; configuration's device table and the README say
  where Gapless is. The skip notice is now said to sit above the title.
- **After review**: twelve findings, each confirmed by skeptics, fixed together. The two in
  Debug's words and the router's are above (Navidrome sent's empty and missing names, a stream
  song not answered yet, forward onto a duplicate page). Also: Info's list reopening where it was
  left; the segmented halves 38px to a finger, and a test whose arithmetic vouched for 44; the menu
  and Info padded by the notch inside a sheet already clear of it; `app-rules.sim.cjs`'s "one
  handler for all three" answered by the NEXT element's props (a lazy `[\s\S]*?` running past
  `/>` - now each element's own props, `propsOf`, and the opener and open checks the same way);
  debug.sim missing a 16-bit resampled source and an MP4 outside a stream with Gapless on; info.sim
  missing a track number past the album's count, the album's cover over the song's, and a song
  count with no songs; player.md's step 7 saying Original applies "from the next song" (a stream
  keeps its setting - start again from a tap); and the docs saying the rows keep the old lines'
  words, where they keep the phrases and moved the rest.
- **Verified**: 1833 Python tests, pyflakes, tsc, and all 25 sims (debug and info new); 59
  mutations, one per rule pinned here, each caught and restored byte for byte - four of them first
  got past a test (Why's order, the menu's backdrop) or failed it only by a crash (Info's backdrop,
  the checkbox's role), and the tests were tightened until each failed on a check - and after the
  review, one or more per fix, each failing a test without it. The engine guard is empty and
  `player.sim.cjs` untouched.
  **NOT verified here**: the real page (the build workaround and a check against the stubs come
  after this change) and everything on the iPhone - Info's scroll and the page not moving under a
  finger, a tap above Info closing it, focus coming back with VoiceOver, the Gapless checkbox
  unlocking the second element from its tap, and what the Navidrome sent row says against 0.64.2.
